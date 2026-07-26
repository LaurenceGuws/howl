//! Converts backend-neutral chrome into bounded Vulkan-ready geometry and one
//! caller-configured native-font alpha atlas. It owns no Vulkan objects.

const std = @import("std");
const render = @import("howl_render");
const build_options = @import("host_build_options");

/// Fixes both dimensions of the shared alpha atlas.
pub const atlas_extent: u16 = 2048;
/// Bounds caller-owned CPU and GPU atlas storage.
pub const atlas_bytes: usize = @as(usize, atlas_extent) * atlas_extent;
/// Bounds all solid and glyph rectangles in one plan.
pub const max_quads: usize = 4096;
/// Bounds initialized vertex staging for one plan.
pub const max_vertices: usize = max_quads * 4;
/// Bounds initialized index staging for one plan.
pub const max_indices: usize = max_quads * 6;
/// Bounds deterministic pipeline/scissor draw commands.
pub const max_commands: usize = 1024;
/// Bounds labels retained by one chrome projection.
pub const max_labels: usize = 24;
const shape_capacity: u32 = 256;
/// Bounds retained face/glyph identity entries for one chrome projection.
pub const max_cached_glyphs: usize = max_labels * @as(usize, shape_capacity);
const raster_scratch_bytes: usize = 256 * 1024;
const glyph_raster_width: u16 = 256;
const test_font_path = build_options.test_font_path;

/// Names exact font-owner construction failures.
pub const InitError = error{
    OutOfMemory,
    InvalidConfig,
} || render.text.InitError || render.text.ShapeBufferInitError;

/// Names exact observable chrome-build failures. Atlas pressure is consumed
/// by `build()` and reported through `Plan.labels_omitted` instead.
pub const BuildError = error{
    InvalidText,
    TextTooLong,
    GeometryFull,
    ArithmeticOverflow,
} || render.text.ShapeError || render.text.RasterError;
const InternalBuildError = BuildError || error{AtlasFull};

/// Selects the solid-color or alpha-atlas pipeline.
pub const Kind = enum { solid, text };

/// Supplies one Vulkan-ready vertex in surface-pixel coordinates.
pub const Vertex = extern struct {
    position: [2]f32,
    uv: [2]f32,
    color: [4]f32,
};

/// Describes one ordered indexed draw and its exact clip rectangle.
pub const Command = struct {
    kind: Kind,
    first_index: u32,
    index_count: u32,
    clip: render.chrome.Rect,
};

/// Borrows Engine staging until its next build and reports whether atlas bytes
/// must be uploaded before drawing.
pub const Plan = struct {
    vertices: []const Vertex,
    indices: []const u16,
    commands: []const Command,
    atlas_changed: bool,
    /// Reports that label pixels were intentionally omitted after bounded
    /// atlas/geometry pressure; solid chrome remains complete.
    labels_omitted: bool,
};

const AtlasEntry = struct {
    face: u8,
    glyph: u32,
    x: u16,
    y: u16,
    width: u16,
    height: u16,
    left: i16,
    top: i16,
};

/// Owns the configured native fonts, bounded shaping/raster scratch, shared
/// alpha atlas, cache identity, and caller-independent geometry staging.
pub const Engine = struct {
    allocator: std.mem.Allocator,
    fonts: render.text.FontSet,
    shape: render.text.ShapeBuffer,
    glyphs: [shape_capacity]render.text.Glyph = undefined,
    raster_storage: []u8,
    raster_scratch: std.heap.FixedBufferAllocator,
    atlas_pixels: []u8,
    rebuild_pixels: []u8,
    atlas: [max_cached_glyphs]AtlasEntry = undefined,
    atlas_count: u16 = 0,
    shelf_x: u16 = 0,
    shelf_y: u16 = 0,
    shelf_height: u16 = 0,
    vertices: [max_vertices]Vertex = undefined,
    vertex_count: u16 = 0,
    indices: [max_indices]u16 = undefined,
    index_count: u16 = 0,
    commands: [max_commands]Command = undefined,
    command_count: u16 = 0,
    surface: render.chrome.Size = .{ .width = 1, .height = 1 },

    /// Copies native font ownership through `allocator` and allocates all
    /// scratch/atlas bytes before rendering begins.
    pub fn init(allocator: std.mem.Allocator, font_path: []const u8) InitError!Engine {
        if (!std.fs.path.isAbsolute(font_path)) return error.InvalidConfig;
        const raster_storage = allocator.alloc(u8, raster_scratch_bytes) catch return error.OutOfMemory;
        errdefer allocator.free(raster_storage);
        const atlas_pixels = allocator.alloc(u8, atlas_bytes) catch return error.OutOfMemory;
        errdefer allocator.free(atlas_pixels);
        @memset(atlas_pixels, 0);
        const rebuild_pixels = allocator.alloc(u8, atlas_bytes) catch return error.OutOfMemory;
        errdefer allocator.free(rebuild_pixels);
        @memset(rebuild_pixels, 0);
        var fonts = try render.text.FontSet.init(allocator, .{
            .primary = font_path,
            .pixel_height = 16,
        });
        errdefer fonts.deinit();
        const shape = try render.text.ShapeBuffer.init(shape_capacity);
        return .{
            .allocator = allocator,
            .fonts = fonts,
            .shape = shape,
            .raster_storage = raster_storage,
            .raster_scratch = std.heap.FixedBufferAllocator.init(raster_storage),
            .atlas_pixels = atlas_pixels,
            .rebuild_pixels = rebuild_pixels,
        };
    }

    /// Releases native font and allocator-owned storage in reverse order.
    pub fn deinit(self: *Engine) void {
        self.shape.deinit();
        self.fonts.deinit();
        self.allocator.free(self.atlas_pixels);
        self.allocator.free(self.rebuild_pixels);
        self.allocator.free(self.raster_storage);
        self.* = undefined;
    }

    /// Shapes copied chrome labels, admits missing glyph masks transactionally,
    /// and returns bounded borrowed vertices, indices, and commands.
    pub fn build(self: *Engine, surface: render.chrome.Size, output: render.chrome.Output) BuildError!Plan {
        return self.buildOnce(surface, output) catch |failure| {
            switch (failure) {
                error.AtlasFull => {
                    const rebuilt = self.rebuildAndBuild(surface, output) catch |rebuild_failure| {
                        switch (rebuild_failure) {
                            error.AtlasFull, error.GeometryFull => return self.buildWithoutLabels(surface, output),
                            else => return @errorCast(rebuild_failure),
                        }
                    };
                    return rebuilt;
                },
                error.GeometryFull => return self.buildWithoutLabels(surface, output),
                else => return @errorCast(failure),
            }
        };
    }

    fn buildOnce(self: *Engine, surface: render.chrome.Size, output: render.chrome.Output) InternalBuildError!Plan {
        if (surface.width == 0 or surface.height == 0) return error.ArithmeticOverflow;
        const retained_atlas_count = self.atlas_count;
        const retained_shelf_x = self.shelf_x;
        const retained_shelf_y = self.shelf_y;
        const retained_shelf_height = self.shelf_height;
        errdefer {
            self.atlas_count = retained_atlas_count;
            self.shelf_x = retained_shelf_x;
            self.shelf_y = retained_shelf_y;
            self.shelf_height = retained_shelf_height;
        }
        self.surface = surface;
        self.vertex_count = 0;
        self.index_count = 0;
        self.command_count = 0;
        const old_atlas_count = self.atlas_count;
        for (output.primitives) |primitive| switch (primitive) {
            .fill => |fill| try self.addSolid(fill.rect, fill.color),
            .border => |border| {
                if (border.edges.top) try self.addSolid(.{ .x = border.rect.x, .y = border.rect.y, .width = border.rect.width, .height = 1 }, border.color);
                if (border.edges.right) try self.addSolid(.{ .x = border.rect.x + border.rect.width - 1, .y = border.rect.y, .width = 1, .height = border.rect.height }, border.color);
                if (border.edges.bottom) try self.addSolid(.{ .x = border.rect.x, .y = border.rect.y + border.rect.height - 1, .width = border.rect.width, .height = 1 }, border.color);
                if (border.edges.left) try self.addSolid(.{ .x = border.rect.x, .y = border.rect.y, .width = 1, .height = border.rect.height }, border.color);
            },
            .scrollbar => |bar| {
                try self.addSolid(bar.track, bar.color);
                try self.addSolid(bar.thumb, bar.thumb_color);
            },
            .label => |label| try self.addLabel(label.rect, label.text, label.color),
        };
        return .{
            .vertices = self.vertices[0..self.vertex_count],
            .indices = self.indices[0..self.index_count],
            .commands = self.commands[0..self.command_count],
            .atlas_changed = self.atlas_count != old_atlas_count,
            .labels_omitted = false,
        };
    }

    fn rebuildAndBuild(self: *Engine, surface: render.chrome.Size, output: render.chrome.Output) InternalBuildError!Plan {
        const old_pixels = self.atlas_pixels;
        const old_count = self.atlas_count;
        const old_shelf_x = self.shelf_x;
        const old_shelf_y = self.shelf_y;
        const old_shelf_height = self.shelf_height;
        const old_entries = self.atlas;
        self.atlas_pixels = self.rebuild_pixels;
        self.rebuild_pixels = old_pixels;
        @memset(self.atlas_pixels, 0);
        self.atlas_count = 0;
        self.shelf_x = 0;
        self.shelf_y = 0;
        self.shelf_height = 0;
        return self.buildOnce(surface, output) catch |failure| {
            const failed_pixels = self.atlas_pixels;
            self.atlas_pixels = self.rebuild_pixels;
            self.rebuild_pixels = failed_pixels;
            self.atlas = old_entries;
            self.atlas_count = old_count;
            self.shelf_x = old_shelf_x;
            self.shelf_y = old_shelf_y;
            self.shelf_height = old_shelf_height;
            return failure;
        };
    }

    /// Preserves solid chrome when a hostile label workload exceeds atlas or
    /// vertex residency; label pixels are a bounded visual enhancement, not a
    /// reason to terminate the persistent surface.
    fn buildWithoutLabels(self: *Engine, surface: render.chrome.Size, output: render.chrome.Output) BuildError!Plan {
        self.surface = surface;
        self.vertex_count = 0;
        self.index_count = 0;
        self.command_count = 0;
        for (output.primitives) |primitive| switch (primitive) {
            .fill => |fill| try self.addSolid(fill.rect, fill.color),
            .border => |border| {
                if (border.edges.top) try self.addSolid(.{ .x = border.rect.x, .y = border.rect.y, .width = border.rect.width, .height = 1 }, border.color);
                if (border.edges.right) try self.addSolid(.{ .x = border.rect.x + border.rect.width - 1, .y = border.rect.y, .width = 1, .height = border.rect.height }, border.color);
                if (border.edges.bottom) try self.addSolid(.{ .x = border.rect.x, .y = border.rect.y + border.rect.height - 1, .width = border.rect.width, .height = 1 }, border.color);
                if (border.edges.left) try self.addSolid(.{ .x = border.rect.x, .y = border.rect.y, .width = 1, .height = border.rect.height }, border.color);
            },
            .scrollbar => |bar| {
                try self.addSolid(bar.track, bar.color);
                try self.addSolid(bar.thumb, bar.thumb_color);
            },
            .label => {},
        };
        return .{ .vertices = self.vertices[0..self.vertex_count], .indices = self.indices[0..self.index_count], .commands = self.commands[0..self.command_count], .atlas_changed = false, .labels_omitted = true };
    }

    fn addSolid(self: *Engine, rect: render.chrome.Rect, color: render.chrome.Color) BuildError!void {
        try self.addQuad(.solid, rect, rect, .{ 0, 0, 0, 0 }, color);
    }

    fn addLabel(self: *Engine, clip: render.chrome.Rect, bytes: []const u8, color: render.chrome.Color) InternalBuildError!void {
        var codepoints: [shape_capacity]u32 = undefined;
        var clusters: [shape_capacity]u32 = undefined;
        var count: usize = 0;
        var offset: usize = 0;
        while (offset < bytes.len) {
            if (count == codepoints.len) return error.TextTooLong;
            const sequence = std.unicode.utf8ByteSequenceLength(bytes[offset]) catch return error.InvalidText;
            if (sequence > bytes.len - offset) return error.InvalidText;
            codepoints[count] = std.unicode.utf8Decode(bytes[offset .. offset + sequence]) catch return error.InvalidText;
            clusters[count] = @intCast(offset);
            count += 1;
            offset += sequence;
        }
        if (count == 0) return;
        const shaped = try self.fonts.shape(
            &self.shape,
            .{ .codepoints = codepoints[0..count], .clusters = clusters[0..count] },
            &self.glyphs,
        );
        var pen_x: i64 = @as(i64, clip.x) * 64;
        var pen_y: i64 = (@as(i64, clip.y) + self.fonts.metrics.baseline) * 64;
        for (shaped.glyphs) |glyph| {
            const entry = try self.atlasGlyph(shaped.face_index, glyph.id);
            if (entry.width == 0 or entry.height == 0) {
                pen_x += glyph.x_advance;
                pen_y += glyph.y_advance;
                continue;
            }
            const glyph_rect = glyphRect(pen_x, pen_y, glyph, entry);
            if (clipRect(glyph_rect, clip)) |visible| {
                const dx: u16 = @intCast(visible.x - glyph_rect.x);
                const dy: u16 = @intCast(visible.y - glyph_rect.y);
                const uv = [4]f32{
                    @as(f32, @floatFromInt(entry.x + dx)) / atlas_extent,
                    @as(f32, @floatFromInt(entry.y + dy)) / atlas_extent,
                    @as(f32, @floatFromInt(entry.x + dx + visible.width)) / atlas_extent,
                    @as(f32, @floatFromInt(entry.y + dy + visible.height)) / atlas_extent,
                };
                try self.addQuad(.text, visible, clip, uv, color);
            }
            pen_x += glyph.x_advance;
            pen_y += glyph.y_advance;
        }
    }

    fn atlasGlyph(self: *Engine, face: u8, glyph: u32) InternalBuildError!AtlasEntry {
        for (self.atlas[0..self.atlas_count]) |entry|
            if (entry.face == face and entry.glyph == glyph) return entry;
        if (self.atlas_count == self.atlas.len) return error.AtlasFull;
        var raster = try self.fonts.rasterize(
            self.raster_scratch.allocator(),
            face,
            glyph,
            glyph_raster_width,
        );
        defer {
            raster.deinit();
            self.raster_scratch.reset();
        }
        if (raster.width == 0 or raster.height == 0) {
            const empty = AtlasEntry{
                .face = face,
                .glyph = glyph,
                .x = 0,
                .y = 0,
                .width = 0,
                .height = 0,
                .left = raster.left,
                .top = raster.top,
            };
            self.atlas[self.atlas_count] = empty;
            self.atlas_count += 1;
            return empty;
        }
        var x = self.shelf_x;
        var y = self.shelf_y;
        var shelf_height = self.shelf_height;
        if (@as(u32, x) + raster.width > atlas_extent) {
            x = 0;
            y = std.math.add(u16, y, shelf_height) catch return error.AtlasFull;
            shelf_height = 0;
        }
        if (@as(u32, y) + raster.height > atlas_extent) return error.AtlasFull;
        const next_x = std.math.add(u16, x, raster.width) catch return error.AtlasFull;
        for (0..raster.height) |row| {
            const destination = (@as(usize, y) + row) * atlas_extent + x;
            const source = row * raster.width;
            @memcpy(self.atlas_pixels[destination .. destination + raster.width], raster.pixels[source .. source + raster.width]);
        }
        const entry = AtlasEntry{
            .face = face,
            .glyph = glyph,
            .x = x,
            .y = y,
            .width = raster.width,
            .height = raster.height,
            .left = raster.left,
            .top = raster.top,
        };
        self.atlas[self.atlas_count] = entry;
        self.atlas_count += 1;
        self.shelf_x = next_x;
        self.shelf_y = y;
        self.shelf_height = @max(shelf_height, raster.height);
        return entry;
    }

    fn addQuad(self: *Engine, kind: Kind, rect: render.chrome.Rect, clip: render.chrome.Rect, uv: [4]f32, color: render.chrome.Color) BuildError!void {
        const merges = self.command_count != 0 and
            self.commands[self.command_count - 1].kind == kind and
            std.meta.eql(self.commands[self.command_count - 1].clip, clip) and
            self.commands[self.command_count - 1].first_index + self.commands[self.command_count - 1].index_count == self.index_count;
        if (self.vertex_count > max_vertices - 4 or self.index_count > max_indices - 6 or (!merges and self.command_count == max_commands)) return error.GeometryFull;
        const vertex_start = self.vertex_count;
        const index_start = self.index_count;
        const width: f32 = @floatFromInt(self.surface.width);
        const height: f32 = @floatFromInt(self.surface.height);
        const x0 = @as(f32, @floatFromInt(rect.x)) / width * 2 - 1;
        const y0 = @as(f32, @floatFromInt(rect.y)) / height * 2 - 1;
        const x1 = @as(f32, @floatFromInt(@as(i64, rect.x) + rect.width)) / width * 2 - 1;
        const y1 = @as(f32, @floatFromInt(@as(i64, rect.y) + rect.height)) / height * 2 - 1;
        const rgba = [4]f32{
            @as(f32, @floatFromInt(color.r)) / 255,
            @as(f32, @floatFromInt(color.g)) / 255,
            @as(f32, @floatFromInt(color.b)) / 255,
            @as(f32, @floatFromInt(color.a)) / 255,
        };
        self.vertices[vertex_start..][0..4].* = .{
            .{ .position = .{ x0, y0 }, .uv = .{ uv[0], uv[1] }, .color = rgba },
            .{ .position = .{ x1, y0 }, .uv = .{ uv[2], uv[1] }, .color = rgba },
            .{ .position = .{ x1, y1 }, .uv = .{ uv[2], uv[3] }, .color = rgba },
            .{ .position = .{ x0, y1 }, .uv = .{ uv[0], uv[3] }, .color = rgba },
        };
        const base: u16 = @intCast(vertex_start);
        self.indices[index_start..][0..6].* = .{ base, base + 1, base + 2, base, base + 2, base + 3 };
        if (merges) {
            const previous = &self.commands[self.command_count - 1];
            previous.index_count += 6;
        } else {
            self.commands[self.command_count] = .{ .kind = kind, .first_index = index_start, .index_count = 6, .clip = clip };
            self.command_count += 1;
        }
        self.vertex_count += 4;
        self.index_count += 6;
    }
};

fn clipRect(rect: render.chrome.Rect, clip: render.chrome.Rect) ?render.chrome.Rect {
    const x0 = @max(@as(i64, rect.x), clip.x);
    const y0 = @max(@as(i64, rect.y), clip.y);
    const x1 = @min(@as(i64, rect.x) + rect.width, @as(i64, clip.x) + clip.width);
    const y1 = @min(@as(i64, rect.y) + rect.height, @as(i64, clip.y) + clip.height);
    if (x1 <= x0 or y1 <= y0) return null;
    return .{ .x = @intCast(x0), .y = @intCast(y0), .width = @intCast(x1 - x0), .height = @intCast(y1 - y0) };
}

fn glyphRect(pen_x: i64, baseline: i64, glyph: render.text.Glyph, entry: AtlasEntry) render.chrome.Rect {
    return .{
        .x = @intCast(@divFloor(pen_x + glyph.x_offset + @as(i64, entry.left) * 64, 64)),
        .y = @intCast(@divFloor(baseline - glyph.y_offset - @as(i64, entry.top) * 64, 64)),
        .width = entry.width,
        .height = entry.height,
    };
}

test "native Unicode labels become bounded atlas glyph geometry" {
    var engine = try Engine.init(std.testing.allocator, test_font_path);
    defer engine.deinit();
    var primitives = [_]render.chrome.Primitive{
        .{ .label = .{
            .rect = .{ .x = 3, .y = 4, .width = 120, .height = 24 },
            .text = "Howl λ",
            .color = .{ .r = 230, .g = 235, .b = 245, .a = 255 },
        } },
    };
    const plan = try engine.build(.{ .width = 160, .height = 40 }, .{ .primitives = &primitives, .text = "Howl λ" });
    try std.testing.expect(plan.atlas_changed);
    try std.testing.expect(plan.vertices.len >= 4);
    try std.testing.expect(plan.indices.len >= 6);
    for (plan.commands) |command| try std.testing.expectEqual(Kind.text, command.kind);
    const retained = engine.atlas_count;
    const repeated = try engine.build(.{ .width = 160, .height = 40 }, .{ .primitives = &primitives, .text = "Howl λ" });
    try std.testing.expect(!repeated.atlas_changed);
    try std.testing.expectEqual(retained, engine.atlas_count);
}

test "glyph placement uses shaping offsets and baseline minus raster top" {
    const rect = glyphRect(
        10 * 64,
        30 * 64,
        .{ .id = 1, .cluster = 0, .x_advance = 0, .y_advance = 0, .x_offset = 32, .y_offset = 64 },
        .{ .face = 0, .glyph = 1, .x = 0, .y = 0, .width = 7, .height = 9, .left = 2, .top = 8 },
    );
    try std.testing.expectEqual(@as(i32, 12), rect.x);
    try std.testing.expectEqual(@as(i32, 21), rect.y);
}

test "glyph cache identity is independent of changing label width" {
    var engine = try Engine.init(std.testing.allocator, test_font_path);
    defer engine.deinit();
    const first = try engine.atlasGlyph(0, 36);
    const count = engine.atlas_count;
    const second = try engine.atlasGlyph(0, 36);
    try std.testing.expectEqual(first.x, second.x);
    try std.testing.expectEqual(count, engine.atlas_count);
}

test "mixed pipeline commands preserve ordered nonmergeable draws" {
    var engine = try Engine.init(std.testing.allocator, test_font_path);
    defer engine.deinit();
    var primitives = [_]render.chrome.Primitive{
        .{ .fill = .{ .rect = .{ .x = 0, .y = 0, .width = 20, .height = 20 }, .color = .{ .r = 1, .g = 2, .b = 3, .a = 255 } } },
        .{ .label = .{ .rect = .{ .x = 1, .y = 1, .width = 18, .height = 18 }, .text = "A", .color = .{ .r = 250, .g = 250, .b = 250, .a = 255 } } },
        .{ .fill = .{ .rect = .{ .x = 20, .y = 0, .width = 20, .height = 20 }, .color = .{ .r = 4, .g = 5, .b = 6, .a = 255 } } },
    };
    const plan = try engine.build(.{ .width = 40, .height = 20 }, .{ .primitives = &primitives, .text = "A" });
    try std.testing.expectEqual(@as(usize, 3), plan.commands.len);
    try std.testing.expectEqual(Kind.solid, plan.commands[0].kind);
    try std.testing.expectEqual(Kind.text, plan.commands[1].kind);
    try std.testing.expectEqual(Kind.solid, plan.commands[2].kind);
}

test "surface top maps to Vulkan negative Y and bottom maps positive" {
    var engine = try Engine.init(std.testing.allocator, test_font_path);
    defer engine.deinit();
    var primitives = [_]render.chrome.Primitive{
        .{ .fill = .{ .rect = .{ .x = 0, .y = 0, .width = 100, .height = 20 }, .color = .{ .r = 1, .g = 2, .b = 3, .a = 255 } } },
    };
    const plan = try engine.build(.{ .width = 100, .height = 100 }, .{ .primitives = &primitives, .text = "" });
    try std.testing.expectEqual(@as(f32, -1), plan.vertices[0].position[1]);
    try std.testing.expectApproxEqAbs(@as(f32, -0.6), plan.vertices[2].position[1], 0.0001);
}

fn constructAndRetire(allocator: std.mem.Allocator, font_path: []const u8) !void {
    var engine = try Engine.init(allocator, font_path);
    engine.deinit();
}

test "construction allocation failures roll back every owned byte" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, constructAndRetire, .{test_font_path});
}

test "atlas saturation is exact and leaves retained entries reusable" {
    var engine = try Engine.init(std.testing.allocator, test_font_path);
    defer engine.deinit();
    const retained = try engine.atlasGlyph(0, 36);
    engine.atlas_count = max_cached_glyphs;
    try std.testing.expectError(error.AtlasFull, engine.atlasGlyph(0, 37));
    engine.atlas_count = 1;
    const repeated = try engine.atlasGlyph(0, 36);
    try std.testing.expectEqual(retained.x, repeated.x);
    try std.testing.expectEqual(retained.y, repeated.y);
}

test "maximum admitted label bytes retain bounded output" {
    var engine = try Engine.init(std.testing.allocator, test_font_path);
    defer engine.deinit();
    var labels: [max_labels][96]u8 = undefined;
    var primitives: [max_labels]render.chrome.Primitive = undefined;
    for (0..max_labels) |label_index| {
        @memset(&labels[label_index], 'A');
        primitives[label_index] = .{ .label = .{
            .rect = .{ .x = 0, .y = @intCast(label_index * 24), .width = 640, .height = 24 },
            .text = &labels[label_index],
            .color = .{ .r = 230, .g = 235, .b = 245, .a = 255 },
        } };
    }
    const plan = try engine.build(.{ .width = 640, .height = 600 }, .{ .primitives = &primitives, .text = "" });
    try std.testing.expect(plan.atlas_changed);
    try std.testing.expect(engine.atlas_count <= max_cached_glyphs);
}

test "atlas pressure rebuild is transactional and removes stale residency" {
    var engine = try Engine.init(std.testing.allocator, test_font_path);
    defer engine.deinit();
    var first = [_]render.chrome.Primitive{.{ .label = .{
        .rect = .{ .x = 0, .y = 0, .width = 80, .height = 24 },
        .text = "A",
        .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    } }};
    const first_plan = try engine.build(.{ .width = 80, .height = 24 }, .{ .primitives = &first, .text = "A" });
    try std.testing.expect(first_plan.atlas_changed);
    engine.atlas_count = max_cached_glyphs;
    var second = [_]render.chrome.Primitive{.{ .label = .{
        .rect = .{ .x = 0, .y = 0, .width = 80, .height = 24 },
        .text = "B",
        .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    } }};
    const second_plan = try engine.build(.{ .width = 80, .height = 24 }, .{ .primitives = &second, .text = "B" });
    try std.testing.expect(second_plan.atlas_changed);
    try std.testing.expect(engine.atlas_count < max_cached_glyphs);
}

test "label fallback reports omission and preserves retained atlas storage" {
    var engine = try Engine.init(std.testing.allocator, test_font_path);
    defer engine.deinit();
    var seed = [_]render.chrome.Primitive{.{ .label = .{
        .rect = .{ .x = 0, .y = 0, .width = 80, .height = 24 },
        .text = "A",
        .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    } }};
    const seed_plan = try engine.build(.{ .width = 80, .height = 24 }, .{ .primitives = &seed, .text = "A" });
    try std.testing.expect(!seed_plan.labels_omitted);
    const retained_count = engine.atlas_count;
    const retained_entry = engine.atlas[0];
    const retained_hash = std.hash.Wyhash.hash(0, engine.atlas_pixels);
    engine.shelf_y = atlas_extent;
    const pressured = try std.testing.allocator.alloc(render.chrome.Primitive, max_quads + 1);
    defer std.testing.allocator.free(pressured);
    pressured[0] = .{ .fill = .{ .rect = .{ .x = 0, .y = 0, .width = 80, .height = 24 }, .color = .{ .r = 1, .g = 2, .b = 3, .a = 255 } } };
    pressured[1] = .{ .border = .{ .rect = .{ .x = 1, .y = 1, .width = 20, .height = 10 }, .edges = .{ .top = true, .right = true, .bottom = true, .left = true }, .color = .{ .r = 4, .g = 5, .b = 6, .a = 255 } } };
    for (pressured[2..]) |*primitive| primitive.* = .{ .label = .{ .rect = .{ .x = 0, .y = 0, .width = 80, .height = 24 }, .text = "B", .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 } } };
    const fallback = try engine.build(.{ .width = 80, .height = 24 }, .{ .primitives = pressured, .text = "B" });
    try std.testing.expect(fallback.labels_omitted);
    try std.testing.expect(!fallback.atlas_changed);
    try std.testing.expectEqual(@as(usize, 5), fallback.commands.len);
    for (fallback.commands) |command| try std.testing.expectEqual(Kind.solid, command.kind);
    try std.testing.expectEqual(retained_count, engine.atlas_count);
    try std.testing.expectEqual(retained_entry, engine.atlas[0]);
    try std.testing.expectEqual(retained_hash, std.hash.Wyhash.hash(0, engine.atlas_pixels));
    engine.shelf_y = 0;
    var ordinary = [_]render.chrome.Primitive{.{ .label = .{
        .rect = .{ .x = 0, .y = 0, .width = 80, .height = 24 },
        .text = "B",
        .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    } }};
    const recovered = try engine.build(.{ .width = 80, .height = 24 }, .{ .primitives = &ordinary, .text = "B" });
    try std.testing.expect(!recovered.labels_omitted);
}
