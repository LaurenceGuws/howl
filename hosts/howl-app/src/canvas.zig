//! Retains content pixels and paints the cursor from complete immutable frames.
const std = @import("std");
const c = @import("desktop");
const instance = @import("howl_instance");
const terminal = @import("terminal.zig");
const selection = @import("selection.zig");
const render = instance.render.terminal;

/// Host focus/blink composition over one immutable cursor frame.
pub const CursorDisplay = enum { shown, hidden, outline };

const resource_limit = render.maximum_frame_resources;
// SDL3.4.18 merges queued geometry. Historical NVIDIA client-array uploads
// above 4 MiB retained growing storage. Bound the whole content queue, including
// colour-only copies: 2048 quads need at most 393216 bytes of GL vertex data.
const batch_quads = 2048;
const quad_indices = blk: {
    @setEvalBranchQuota(batch_quads * 8);
    var indices: [batch_quads * 6]c_int = undefined;
    for (0..batch_quads) |quad| {
        const vertex: c_int = @intCast(quad * 4);
        indices[quad * 6 ..][0..6].* = .{ vertex, vertex + 1, vertex + 2, vertex, vertex + 2, vertex + 3 };
    }
    break :blk indices;
};

const Texture = struct {
    residency: render.Residency,
    texture: *c.SDL_Texture,
};

/// One graphical-thread scratch batch shared by all panes.
pub const Geometry = struct {
    vertices: [batch_quads * 4]c.SDL_Vertex = undefined,
    count: usize = 0,
    queued_quads: usize = 0,
    texture: ?*c.SDL_Texture = null,
    clip: c.SDL_Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },

    // SDL owns copied vertex data after RenderGeometry returns. Bound the
    // entire queued content batch, including RGBA copies, rather than forcing
    // a backend submission whenever texture or clip changes.
    fn reserve(self: *Geometry, renderer: *c.SDL_Renderer, quads: usize) !void {
        std.debug.assert(self.queued_quads <= batch_quads and quads <= batch_quads);
        if (self.queued_quads > batch_quads - quads) try self.submit(renderer);
    }

    fn submit(self: *Geometry, renderer: *c.SDL_Renderer) !void {
        if (self.queued_quads == 0) return;
        if (!c.SDL_FlushRenderer(renderer)) return error.SDLGeometry;
        self.queued_quads = 0;
    }

    fn flush(self: *Geometry, renderer: *c.SDL_Renderer) !void {
        if (self.count == 0) return;
        try self.reserve(renderer, self.count);
        if (!c.SDL_SetRenderClipRect(renderer, &self.clip) or
            !c.SDL_RenderGeometry(renderer, self.texture, &self.vertices, @intCast(self.count * 4), &quad_indices, @intCast(self.count * 6)))
            return error.SDLGeometry;
        self.queued_quads += self.count;
        self.count = 0;
    }

    fn finish(self: *Geometry, renderer: *c.SDL_Renderer) !void {
        try self.flush(renderer);
        try self.submit(renderer);
    }

    fn append(
        self: *Geometry,
        renderer: *c.SDL_Renderer,
        texture: ?*c.SDL_Texture,
        clip: c.SDL_Rect,
        dest: c.SDL_FRect,
        source: c.SDL_FRect,
        color: render.Color,
    ) !void {
        if (self.count == batch_quads or self.texture != texture or !rectEqual(self.clip, clip)) try self.flush(renderer);
        self.texture = texture;
        self.clip = clip;
        const base = self.count * 4;
        const rgba: c.SDL_FColor = .{
            .r = @as(f32, @floatFromInt(color.r)) / 255,
            .g = @as(f32, @floatFromInt(color.g)) / 255,
            .b = @as(f32, @floatFromInt(color.b)) / 255,
            .a = @as(f32, @floatFromInt(color.a)) / 255,
        };
        self.vertices[base..][0..4].* = .{
            .{ .position = .{ .x = dest.x, .y = dest.y }, .color = rgba, .tex_coord = .{ .x = source.x, .y = source.y } },
            .{ .position = .{ .x = dest.x + dest.w, .y = dest.y }, .color = rgba, .tex_coord = .{ .x = source.x + source.w, .y = source.y } },
            .{ .position = .{ .x = dest.x + dest.w, .y = dest.y + dest.h }, .color = rgba, .tex_coord = .{ .x = source.x + source.w, .y = source.y + source.h } },
            .{ .position = .{ .x = dest.x, .y = dest.y + dest.h }, .color = rgba, .tex_coord = .{ .x = source.x, .y = source.y + source.h } },
        };
        self.count += 1;
    }
};

/// Holds one immutable canonical frame until a newer publication replaces it.
/// The producer retains two free/replaceable slots and never waits for this lease.
pub const Canvas = struct {
    allocator: std.mem.Allocator,
    lease: ?instance.RenderLease = null,
    selection_paint: selection.Paint = .{},
    textures: [resource_limit]Texture = undefined,
    count: usize = 0,
    converted: std.ArrayList(u8) = .empty,
    generation: u64 = 0,
    content: ?*c.SDL_Texture = null,
    content_revision: ?u64 = null,
    content_size: render.Size = .{ .width = 1, .height = 1 },

    /// Creates an empty backend resource owner with no canonical or frame authority.
    pub fn init(allocator: std.mem.Allocator) Canvas {
        return .{ .allocator = allocator };
    }

    /// Retires the held frame before releasing graphical resources and scratch.
    pub fn deinit(self: *Canvas) void {
        if (self.lease) |*lease| lease.abandon();
        self.clearTextures();
        self.converted.deinit(self.allocator);
        self.* = undefined;
    }

    /// Borrows the held immutable publication; valid until update or deinit.
    pub fn frame(self: *const Canvas) ?instance.PublishedFrame {
        return if (self.lease) |lease| lease.value else null;
    }

    /// Transfers an immutable publication only when ready; duplicate wakeups keep the old lease.
    pub fn update(self: *Canvas, renderer: *c.SDL_Renderer, owner: *terminal.Terminal) !void {
        var residency: [resource_limit]render.Residency = undefined;
        for (self.textures[0..self.count], 0..) |texture, index| residency[index] = texture.residency;
        var lease = (try owner.replaceFrame(if (self.lease) |*previous| previous else null, residency[0..self.count], &self.selection_paint)) orelse return;
        self.lease = null;
        errdefer lease.abandon();
        const value = lease.value;
        if (self.generation != value.presentation_generation) {
            self.clearTextures();
            self.generation = value.presentation_generation;
        }
        for (value.removals) |resource| self.remove(resource, true);
        for (value.uploads) |upload| {
            const source = value.pixels[upload.pixel_offset..][0..upload.pixel_count];
            const width: usize = upload.size.width;
            const height: usize = upload.size.height;
            var pixels: []const u8 = source;
            var stride = upload.stride;
            if (upload.format == .alpha8) {
                try self.converted.resize(self.allocator, width * height * 4);
                for (0..height) |y| for (0..width) |x| {
                    const at = (y * width + x) * 4;
                    self.converted.items[at..][0..4].* = .{ 255, 255, 255, source[y * upload.stride + x] };
                };
                pixels = self.converted.items;
                stride = width * 4;
            }
            const texture = c.SDL_CreateTexture(renderer, c.SDL_PIXELFORMAT_RGBA32, c.SDL_TEXTUREACCESS_STATIC, upload.size.width, upload.size.height) orelse return error.SDLTexture;
            var owned = true;
            errdefer if (owned) c.SDL_DestroyTexture(texture);
            if (!c.SDL_SetTextureScaleMode(texture, c.SDL_SCALEMODE_NEAREST) or
                !c.SDL_SetTextureBlendMode(texture, c.SDL_BLENDMODE_BLEND) or
                !c.SDL_UpdateTexture(texture, null, pixels.ptr, @intCast(stride))) return error.SDLTexture;
            self.remove(upload.resource, false);
            if (self.count == resource_limit) return error.ResourceLimit;
            self.textures[self.count] = .{
                .texture = texture,
                .residency = .{ .resource = upload.resource, .format = upload.format, .size = upload.size },
            };
            self.count += 1;
            owned = false;
        }
        // Feedback describes the resources just applied, while frame storage stays leased.
        for (self.textures[0..self.count], 0..) |texture, index| residency[index] = texture.residency;
        try lease.reportResidency(residency[0..self.count]);
        self.lease = lease;
    }

    /// Draws canonical commands with exact pane/resource clipping using shared bounded batches.
    pub fn draw(self: *Canvas, renderer: *c.SDL_Renderer, geometry: *Geometry, logical_pane: c.SDL_FRect, scale: f32, cursor: CursorDisplay) !void {
        const value = self.frame() orelse return;
        // Canonical commands already use physical pixels. Dividing then letting
        // SDL scale them back introduces fractional cell edges and visible seams.
        var previous_x: f32 = 0;
        var previous_y: f32 = 0;
        if (!c.SDL_GetRenderScale(renderer, &previous_x, &previous_y) or
            !c.SDL_SetRenderScale(renderer, 1, 1)) return error.SDLScale;
        // zig-audit: acknowledge discard
        // reason: Best-effort state restoration on draw failure preserves the original SDL error.
        errdefer _ = c.SDL_SetRenderScale(renderer, previous_x, previous_y);
        // zig-audit: acknowledge discard
        // reason: Best-effort clip retirement on draw failure preserves the original SDL error.
        errdefer _ = c.SDL_SetRenderClipRect(renderer, null);
        const pane: c.SDL_FRect = .{
            .x = @round(logical_pane.x * scale),
            .y = @round(logical_pane.y * scale),
            .w = logical_pane.w * scale,
            .h = logical_pane.h * scale,
        };
        if (self.content == null or !std.meta.eql(self.content_size, value.surface)) {
            self.invalidateContent();
            const target = c.SDL_CreateTexture(renderer, c.SDL_PIXELFORMAT_RGBA32, c.SDL_TEXTUREACCESS_TARGET, value.surface.width, value.surface.height) orelse return error.SDLTexture;
            errdefer c.SDL_DestroyTexture(target);
            if (!c.SDL_SetTextureScaleMode(target, c.SDL_SCALEMODE_NEAREST) or
                !c.SDL_SetTextureBlendMode(target, c.SDL_BLENDMODE_NONE)) return error.SDLTexture;
            self.content = target;
            self.content_size = value.surface;
        }
        const target = self.content.?;
        if (self.content_revision != value.content_revision) {
            const previous_target = c.SDL_GetRenderTarget(renderer);
            if (!c.SDL_SetRenderTarget(renderer, target)) return error.SDLTexture;
            // zig-audit: acknowledge discard
            // reason: Restore the caller's render target on failure without hiding the original SDL error.
            errdefer _ = c.SDL_SetRenderTarget(renderer, previous_target);
            if (!c.SDL_SetRenderClipRect(renderer, null) or
                !c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 0) or
                !c.SDL_RenderClear(renderer)) return error.SDLTexture;
            try self.drawCommands(renderer, geometry, .{
                .x = 0,
                .y = 0,
                .w = @floatFromInt(value.surface.width),
                .h = @floatFromInt(value.surface.height),
            }, value.commands[0..value.content_command_count]);
            if (!c.SDL_SetRenderTarget(renderer, previous_target)) return error.SDLTexture;
            self.content_revision = value.content_revision;
        }
        const pane_clip = pixelClip(pane);
        const destination_rect: c.SDL_FRect = .{
            .x = pane.x,
            .y = pane.y,
            .w = @floatFromInt(value.surface.width),
            .h = @floatFromInt(value.surface.height),
        };
        if (!c.SDL_SetRenderClipRect(renderer, &pane_clip) or
            !c.SDL_RenderTexture(renderer, target, null, &destination_rect)) return error.SDLTexture;
        try self.drawSelection(renderer, pane, value);
        switch (cursor) {
            .shown => try self.drawCommands(renderer, geometry, pane, value.commands[value.content_command_count..]),
            .hidden => {},
            .outline => if (value.cursor) |overlay| {
                const r = overlay.rect;
                const right = r.x + @as(i32, r.width) - 1;
                const bottom = r.y + @as(i32, r.height) - 1;
                // Four filled physical-pixel edges avoid scale-dependent SDL strokes.
                const commands = [_]render.Command{
                    .{ .solid = .{ .rect = .{ .x = r.x, .y = r.y, .width = r.width, .height = 1 }, .color = overlay.color } },
                    .{ .solid = .{ .rect = .{ .x = r.x, .y = bottom, .width = r.width, .height = 1 }, .color = overlay.color } },
                    .{ .solid = .{ .rect = .{ .x = r.x, .y = r.y, .width = 1, .height = r.height }, .color = overlay.color } },
                    .{ .solid = .{ .rect = .{ .x = right, .y = r.y, .width = 1, .height = r.height }, .color = overlay.color } },
                };
                try self.drawCommands(renderer, geometry, pane, &commands);
            },
        }
        if (!c.SDL_SetRenderClipRect(renderer, null)) return error.SDLClip;
        if (!c.SDL_SetRenderScale(renderer, previous_x, previous_y)) return error.SDLScale;
    }

    fn drawSelection(self: *const Canvas, renderer: *c.SDL_Renderer, pane: c.SDL_FRect, value: instance.PublishedFrame) !void {
        // Selection is a transient overlay, below the cursor and outside the
        // retained content texture. Its spans belong to this exact frame.
        if (self.selection_paint.rows == 0) return;
        const rows = value.surface.height / value.cell_size.height;
        const columns = value.surface.width / value.cell_size.width;
        if (!c.SDL_SetRenderDrawColor(renderer, 180, 180, 180, 100)) return error.SDLGeometry;
        for (self.selection_paint.spans[0..@min(self.selection_paint.spans.len, @min(self.selection_paint.rows, rows))], 0..) |span, row| if (span) |range| {
            if (range.last < range.first or range.first >= columns) continue;
            const last = @min(range.last, columns - 1);
            const rect: c.SDL_FRect = .{
                .x = pane.x + @as(f32, @floatFromInt(@as(u32, range.first) * value.cell_size.width)),
                .y = pane.y + @as(f32, @floatFromInt(row * value.cell_size.height)),
                .w = @floatFromInt(@as(u32, last - range.first + 1) * value.cell_size.width),
                .h = @floatFromInt(value.cell_size.height),
            };
            if (!c.SDL_RenderFillRect(renderer, &rect)) return error.SDLGeometry;
        };
    }

    /// Discards backend content pixels; the next draw reconstructs from the held frame.
    pub fn invalidateContent(self: *Canvas) void {
        if (self.content) |target| c.SDL_DestroyTexture(target);
        self.content = null;
        self.content_revision = null;
    }

    fn drawCommands(self: *Canvas, renderer: *c.SDL_Renderer, geometry: *Geometry, pane: c.SDL_FRect, commands: []const render.Command) !void {
        const pane_clip = pixelClip(pane);
        // Retire any preceding UI/target commands before accounting this
        // content pass. A failed prior pass cannot lend uncounted queue work.
        if (!c.SDL_FlushRenderer(renderer)) return error.SDLGeometry;
        geometry.count = 0;
        geometry.queued_quads = 0;
        for (commands) |command| {
            switch (command) {
                .solid => |solid| try geometry.append(renderer, null, pane_clip, destination(solid.rect, pane), .{ .x = 0, .y = 0, .w = 0, .h = 0 }, solid.color),
                .alpha_mask => |mask| {
                    const texture = self.find(mask.resource.resource) orelse return error.MissingTexture;
                    const dest = destination(mask.destination, pane);
                    const clip = commandClip(mask.destination, mask.clip, pane, pane_clip) orelse continue;
                    const src: render.SourceRect = mask.resource.source orelse .{ .x = 0, .y = 0, .width = mask.resource.size.width, .height = mask.resource.size.height };
                    const width: f32 = @floatFromInt(mask.resource.size.width);
                    const height: f32 = @floatFromInt(mask.resource.size.height);
                    try geometry.append(renderer, texture, clip, dest, .{
                        .x = @as(f32, @floatFromInt(src.x)) / width,
                        .y = @as(f32, @floatFromInt(src.y)) / height,
                        .w = @as(f32, @floatFromInt(src.width)) / width,
                        .h = @as(f32, @floatFromInt(src.height)) / height,
                    }, mask.color);
                },
                .rgba => |image| {
                    try geometry.flush(renderer);
                    const texture = self.find(image.resource.resource) orelse return error.MissingTexture;
                    const clip = commandClip(image.destination, image.clip, pane, pane_clip) orelse continue;
                    const src: render.SourceRect = image.resource.source orelse .{ .x = 0, .y = 0, .width = image.resource.size.width, .height = image.resource.size.height };
                    const source: c.SDL_FRect = .{ .x = @floatFromInt(src.x), .y = @floatFromInt(src.y), .w = @floatFromInt(src.width), .h = @floatFromInt(src.height) };
                    const dest = destination(image.destination, pane);
                    try geometry.reserve(renderer, 1);
                    if (!c.SDL_SetRenderClipRect(renderer, &clip) or
                        !c.SDL_RenderTexture(renderer, texture, &source, &dest)) return error.SDLTexture;
                    geometry.queued_quads += 1;
                },
            }
        }
        try geometry.finish(renderer);
    }

    fn find(self: *const Canvas, resource: render.ResourceRef) ?*c.SDL_Texture {
        for (self.textures[0..self.count]) |texture| {
            if (texture.residency.resource.resource == resource.resource and
                texture.residency.resource.generation == resource.generation) return texture.texture;
        }
        return null;
    }

    fn remove(self: *Canvas, resource: render.ResourceRef, exact: bool) void {
        for (self.textures[0..self.count], 0..) |texture, index| {
            if (texture.residency.resource.resource != resource.resource or
                (exact and texture.residency.resource.generation != resource.generation)) continue;
            c.SDL_DestroyTexture(texture.texture);
            self.count -= 1;
            self.textures[index] = self.textures[self.count];
            return;
        }
    }

    fn clearTextures(self: *Canvas) void {
        self.invalidateContent();
        for (self.textures[0..self.count]) |texture| c.SDL_DestroyTexture(texture.texture);
        self.count = 0;
    }
};

fn destination(rect: render.Rect, pane: c.SDL_FRect) c.SDL_FRect {
    return .{
        .x = pane.x + @as(f32, @floatFromInt(rect.x)),
        .y = pane.y + @as(f32, @floatFromInt(rect.y)),
        .w = @as(f32, @floatFromInt(rect.width)),
        .h = @as(f32, @floatFromInt(rect.height)),
    };
}

fn pixelClip(rect: c.SDL_FRect) c.SDL_Rect {
    const x: c_int = @intFromFloat(@floor(rect.x));
    const y: c_int = @intFromFloat(@floor(rect.y));
    return .{ .x = x, .y = y, .w = @as(c_int, @intFromFloat(@ceil(rect.x + rect.w))) - x, .h = @as(c_int, @intFromFloat(@ceil(rect.y + rect.h))) - y };
}

fn commandClip(ink: render.Rect, clip: render.Rect, pane: c.SDL_FRect, pane_clip: c.SDL_Rect) ?c.SDL_Rect {
    if (contained(ink, clip)) {
        if (pane_clip.w <= 0 or pane_clip.h <= 0) return null;
        return pane_clip;
    }
    const requested = pixelClip(destination(clip, pane));
    var visible: c.SDL_Rect = undefined;
    if (!c.SDL_GetRectIntersection(&requested, &pane_clip, &visible)) return null;
    return visible;
}

fn rectEqual(a: c.SDL_Rect, b: c.SDL_Rect) bool {
    return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h;
}

test "fractional pane clips cover edge pixels without crossing the integer pane bounds" {
    const clip = pixelClip(.{ .x = 10.2, .y = 5.8, .w = 15.4, .h = 20.1 });
    try std.testing.expectEqual(c.SDL_Rect{ .x = 10, .y = 5, .w = 16, .h = 21 }, clip);
}

fn contained(a: render.Rect, b: render.Rect) bool {
    return a.x >= b.x and a.y >= b.y and
        @as(i64, a.x) + a.width <= @as(i64, b.x) + b.width and
        @as(i64, a.y) + a.height <= @as(i64, b.y) + b.height;
}

test "command clipping equals SDL for contained clipped fractional negative and empty panes" {
    for (0..10000) |i| {
        const pane: c.SDL_FRect = .{
            .x = @as(f32, @floatFromInt(@as(i32, @intCast(i % 31)) - 15)) + @as(f32, @floatFromInt(i % 4)) / 4,
            .y = @as(f32, @floatFromInt(@as(i32, @intCast(i % 23)) - 11)) + @as(f32, @floatFromInt(i % 3)) / 3,
            .w = @floatFromInt(if (i % 17 == 0) @as(usize, 0) else 1 + i % 257),
            .h = @floatFromInt(if (i % 19 == 0) @as(usize, 0) else 1 + i % 193),
        };
        const pane_clip = pixelClip(pane);
        const ink: render.Rect = .{ .x = @as(i32, @intCast(i % 43)) - 21, .y = @as(i32, @intCast(i % 37)) - 18, .width = @intCast(2 + i % 19), .height = @intCast(2 + i % 29) };
        const clip: render.Rect = switch (i % 3) {
            0 => ink,
            1 => .{ .x = ink.x + 1, .y = ink.y + 1, .width = ink.width - 1, .height = ink.height - 1 },
            else => .{ .x = 0, .y = 0, .width = 320, .height = 200 },
        };
        const requested = if (contained(ink, clip)) pane_clip else pixelClip(destination(clip, pane));
        var intersection: c.SDL_Rect = undefined;
        const expected: ?c.SDL_Rect = if (c.SDL_GetRectIntersection(&requested, &pane_clip, &intersection)) intersection else null;
        try std.testing.expectEqualDeep(expected, commandClip(ink, clip, pane, pane_clip));
    }
}

test "overhanging commands keep their exact clip, contained quads share the pane clip" {
    const clip: render.Rect = .{ .x = -3, .y = 7, .width = 12, .height = 14 };
    try std.testing.expect(contained(.{ .x = -3, .y = 7, .width = 12, .height = 14 }, clip));
    try std.testing.expect(!contained(.{ .x = -4, .y = 7, .width = 12, .height = 14 }, clip));
    try std.testing.expect(!contained(.{ .x = -3, .y = 7, .width = 13, .height = 14 }, clip));
}

test "failed backend allocation retires its candidate; a fresh presentation generation rebuilds exact resources" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const presentation: instance.PresentationConfig = .{
        .text = .{ .private = .{ .regular = .{ .path = .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 15 } } } } },
        .box_drawing = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
        .shape_cache = .{ .entry_capacity = 32, .scalar_capacity = 128, .glyph_capacity = 128, .max_sequence_scalars = 16 },
        .atlas = .{ .width = 256, .height = 256, .entry_capacity = 128 },
        .shaped_capacity = 128,
        .raster_bytes = 256 * 256,
        .command_capacity = 256,
        .command_limit = instance.render.limits.maximum_frame_commands,
    };
    const owner = try terminal.Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf 'HELLO\\033]0;READY\\007'; read line; printf '\\033]0;CONTINUED\\007'; sleep 30",
        .rows = 4,
        .columns = 20,
    }, presentation, c.SDL_RegisterEvents(1), true);
    defer owner.destroy();
    var stage: []const u8 = "canonical READY";
    var accepted_generation: u64 = 0;
    errdefer std.debug.print("backend recovery failure at {s}; accepted generation {d}, canonical {any}, presentation {any}\n", .{ stage, accepted_generation, owner.snapshot().failure, owner.snapshot().presentation_failure });
    var attempts: u16 = 0;
    while (attempts < 5000) : (attempts += 1) {
        const status = owner.snapshot();
        if (std.mem.eql(u8, status.title[0..status.title_len], "READY")) break;
        if (status.failure) |failure| return failure;
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    if (attempts == 5000) return error.Timeout;
    const surface = c.SDL_CreateSurface(250, 100, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var backend = Canvas.init(failing.allocator());
    defer backend.deinit();
    owner.requestFrame();
    stage = "injected backend allocation";
    var failed = false;
    attempts = 0;
    while (!failed and attempts < 5000) : (attempts += 1) {
        backend.update(renderer, owner) catch |failure| {
            try std.testing.expectEqual(error.OutOfMemory, failure);
            failed = true;
        };
        if (!failed) try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(failed);
    stage = "canonical CONTINUED after rejected backend";
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    attempts = 0;
    while (attempts < 5000) : (attempts += 1) {
        const status = owner.snapshot();
        if (std.mem.eql(u8, status.title[0..status.title_len], "CONTINUED")) break;
        if (status.failure) |failure| return failure;
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    if (attempts == 5000) return error.Timeout;
    backend.deinit();
    backend = Canvas.init(std.testing.allocator);
    stage = "font reconfiguration";
    const configured = try owner.reconfigure(presentation, null);
    try std.testing.expect(configured.cell_size.width > 0);
    attempts = 0;
    while (backend.frame() == null and attempts < 5000) : (attempts += 1) {
        try backend.update(renderer, owner);
        if (backend.frame() == null) try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    stage = "fresh backend generation";
    const accepted = backend.frame() orelse return error.MissingFrame;
    accepted_generation = accepted.presentation_generation;
    try std.testing.expect(accepted.presentation_generation > 1);
    const geometry = try std.testing.allocator.create(Geometry);
    defer std.testing.allocator.destroy(geometry);
    geometry.* = .{};
    try backend.draw(renderer, geometry, .{ .x = 0, .y = 0, .w = 250, .h = 100 }, 1, .shown);
    try std.testing.expect(c.SDL_RenderPresent(renderer));
    try std.testing.expectEqual(@as(?terminal.Failure, null), owner.snapshot().failure);
}

test "repeated alternate-screen blank and text cuts retain exact backend residency" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const presentation: instance.PresentationConfig = .{
        .text = .{ .private = .{ .regular = .{ .path = .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 15 } } } } },
        .box_drawing = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
        .shape_cache = .{ .entry_capacity = 32, .scalar_capacity = 128, .glyph_capacity = 128, .max_sequence_scalars = 16 },
        .atlas = .{ .width = 256, .height = 256, .entry_capacity = 128 },
        .shaped_capacity = 128,
        .raster_bytes = 256 * 256,
        .command_capacity = 256,
        .command_limit = instance.render.limits.maximum_frame_commands,
    };
    const owner = try terminal.Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf 'HELLO\\033]0;WARM\\007'; read line; printf '\\033[1;1H\\033]0;READY\\007'; i=0; while [ \"$i\" -lt 4 ]; do read line; printf '\\033[?1049h\\033[2J\\033[H\\033]0;BLANK\\007'; read line; printf 'HELLO\\033]0;TEXT\\007'; read line; printf '\\033[2J\\033[H\\033]0;EXIT-BLANK\\007'; read line; printf '\\033[?1049l\\033]0;MAIN\\007'; i=$((i+1)); done; read line",
        .rows = 4,
        .columns = 20,
    }, presentation, 0, true);
    defer owner.destroy();
    const surface = c.SDL_CreateSurface(250, 100, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    var backend = Canvas.init(std.testing.allocator);
    defer backend.deinit();
    const geometry = try std.testing.allocator.create(Geometry);
    defer std.testing.allocator.destroy(geometry);
    geometry.* = .{};
    var previous_revision: u64 = 0;
    for (0..18) |step| {
        if (step != 0) try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
        const title = if (step == 0) "WARM" else if (step == 1) "READY" else ([_][]const u8{ "BLANK", "TEXT", "EXIT-BLANK", "MAIN" })[(step - 2) % 4];
        var attempts: u16 = 0;
        while (attempts < 5000) : (attempts += 1) {
            try backend.update(renderer, owner);
            const status = owner.snapshot();
            if (status.failure) |failure| return failure;
            if (status.presentation_failure) |failure| return failure;
            if (std.mem.eql(u8, status.title[0..status.title_len], title)) {
                if (backend.frame()) |value| if (value.terminal_revision == status.revision and value.terminal_revision != previous_revision) break;
            }
            owner.requestFrame();
            try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
        }
        if (attempts == 5000) return error.Timeout;
        const value = backend.frame().?;
        previous_revision = value.terminal_revision;
        const blank = step >= 2 and (step - 2) % 2 == 0;
        try std.testing.expectEqual(step >= 2 and (step - 2) % 4 != 3, value.alternate_screen);
        errdefer std.debug.print("alternate texture failure at step {d}, title {s}, uploads {d}, removals {d}, textures {d}\n", .{ step, title, value.uploads.len, value.removals.len, backend.count });
        try backend.draw(renderer, geometry, .{ .x = 0, .y = 0, .w = 250, .h = 100 }, 1, .shown);
        try std.testing.expect(c.SDL_RenderPresent(renderer));
        try std.testing.expectEqual(@as(usize, if (blank) 0 else 1), backend.count);
        var retained: [250 * 100][3]u8 = undefined;
        const visible_width = @min(value.surface.width, 250);
        const visible_height = @min(value.surface.height, 100);
        for (0..visible_height) |y| for (0..visible_width) |x| {
            try std.testing.expect(c.SDL_ReadSurfacePixel(surface, @intCast(x), @intCast(y), &retained[y * visible_width + x][0], &retained[y * visible_width + x][1], &retained[y * visible_width + x][2], null));
        };
        try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255));
        try std.testing.expect(c.SDL_RenderClear(renderer));
        try backend.drawCommands(renderer, geometry, .{ .x = 0, .y = 0, .w = 250, .h = 100 }, value.commands);
        try std.testing.expect(c.SDL_RenderPresent(renderer));
        for (0..visible_height) |y| for (0..visible_width) |x| {
            var pixel: [3]u8 = undefined;
            try std.testing.expect(c.SDL_ReadSurfacePixel(surface, @intCast(x), @intCast(y), &pixel[0], &pixel[1], &pixel[2], null));
            try std.testing.expectEqual(retained[y * visible_width + x], pixel);
        };
        owner.requestFrame();
    }
}

test "fractional SDL projection preserves every pixel of joined generated blocks and rules" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const presentation: instance.PresentationConfig = .{
        .text = .{ .private = .{ .regular = .{ .path = .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 15 } } } } },
        .box_drawing = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
        .shape_cache = .{ .entry_capacity = 32, .scalar_capacity = 128, .glyph_capacity = 128, .max_sequence_scalars = 16 },
        .atlas = .{ .width = 256, .height = 256, .entry_capacity = 128 },
        .shaped_capacity = 128,
        .raster_bytes = 256 * 256,
        .command_capacity = 256,
        .command_limit = instance.render.limits.maximum_frame_commands,
    };
    const owner = try terminal.Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "printf '\\033[?25l\\033[38;2;255;255;255m████\\r\\n████\\r\\n││││\\r\\n││││\\r\\n────\\r\\n────\\033]0;BLOCKS-READY\\007'; read line",
        .rows = 6,
        .columns = 4,
    }, presentation, 0, true);
    defer owner.destroy();
    const surface = c.SDL_CreateSurface(160, 160, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    var backend = Canvas.init(std.testing.allocator);
    defer backend.deinit();
    const geometry = try std.testing.allocator.create(Geometry);
    defer std.testing.allocator.destroy(geometry);
    geometry.* = .{};
    var attempts: u16 = 0;
    while (attempts < 5000) : (attempts += 1) {
        try backend.update(renderer, owner);
        const status = owner.snapshot();
        if (std.mem.eql(u8, status.title[0..status.title_len], "BLOCKS-READY")) {
            if (backend.frame()) |frame| if (frame.terminal_revision == status.revision) break;
        }
        if (status.failure) |failure| return failure;
        owner.requestFrame();
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    if (attempts == 5000) return error.Timeout;
    const frame = backend.frame().?;
    try std.testing.expect(frame.surface.width <= 160 and frame.surface.height <= 160);
    var reference: [160 * 160][3]u8 = undefined;
    for ([_]f32{ 1, 1.25, 1.5, 1.6, 1.7, 2 }) |scale| {
        try std.testing.expect(c.SDL_SetRenderScale(renderer, scale, scale));
        try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255));
        try std.testing.expect(c.SDL_RenderClear(renderer));
        try backend.draw(renderer, geometry, .{
            .x = 7 / scale,
            .y = 11 / scale,
            .w = @as(f32, @floatFromInt(frame.surface.width)) / scale,
            .h = @as(f32, @floatFromInt(frame.surface.height)) / scale,
        }, scale, .shown);
        try std.testing.expect(c.SDL_RenderPresent(renderer));
        var restored_x: f32 = 0;
        var restored_y: f32 = 0;
        try std.testing.expect(c.SDL_GetRenderScale(renderer, &restored_x, &restored_y));
        try std.testing.expectEqual(scale, restored_x);
        try std.testing.expectEqual(scale, restored_y);
        for (0..frame.surface.height) |y| for (0..frame.surface.width) |x| {
            var red: u8 = 0;
            var green: u8 = 0;
            var blue: u8 = 0;
            try std.testing.expect(c.SDL_ReadSurfacePixel(surface, @intCast(x + 7), @intCast(y + 11), &red, &green, &blue, null));
            const pixel = [3]u8{ red, green, blue };
            const at = y * frame.surface.width + x;
            if (scale == 1) reference[at] = pixel;
            const solid_rows = y < frame.surface.height / 3;
            if ((solid_rows and (red != 255 or green != 255 or blue != 255)) or
                !std.mem.eql(u8, &reference[at], &pixel))
            {
                std.debug.print("generated block seam scale={d} pixel=({d},{d}) rgb=({d},{d},{d})\n", .{ scale, x, y, red, green, blue });
                return error.GeneratedBlockSeam;
            }
        };
    }
    // Compare the retained content/cursor composition with the original full
    // command draw, including pane translation and the same physical lattice.
    try std.testing.expect(c.SDL_SetRenderScale(renderer, 1, 1));
    try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255));
    try std.testing.expect(c.SDL_RenderClear(renderer));
    try backend.drawCommands(renderer, geometry, .{
        .x = 7,
        .y = 11,
        .w = @floatFromInt(frame.surface.width),
        .h = @floatFromInt(frame.surface.height),
    }, frame.commands);
    try std.testing.expect(c.SDL_RenderPresent(renderer));
    for (0..frame.surface.height) |y| for (0..frame.surface.width) |x| {
        var red: u8 = 0;
        var green: u8 = 0;
        var blue: u8 = 0;
        try std.testing.expect(c.SDL_ReadSurfacePixel(surface, @intCast(x + 7), @intCast(y + 11), &red, &green, &blue, null));
        try std.testing.expectEqual(reference[y * frame.surface.width + x], [3]u8{ red, green, blue });
    };
    try std.testing.expect(c.SDL_SetRenderScale(renderer, 2, 2));
    backend.clearTextures();
    try std.testing.expectError(error.MissingTexture, backend.draw(renderer, geometry, .{ .x = 0, .y = 0, .w = 80, .h = 80 }, 2, .shown));
    var restored_x: f32 = 0;
    var restored_y: f32 = 0;
    try std.testing.expect(c.SDL_GetRenderScale(renderer, &restored_x, &restored_y));
    try std.testing.expectEqual(@as(f32, 2), restored_x);
    try std.testing.expectEqual(@as(f32, 2), restored_y);
    try std.testing.expect(!c.SDL_RenderClipEnabled(renderer));
}

test "SDL queue budget admits its exact limit and retires before the next packet" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    const surface = c.SDL_CreateSurface(8, 8, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    const geometry = try std.testing.allocator.create(Geometry);
    defer std.testing.allocator.destroy(geometry);
    geometry.* = .{};
    geometry.queued_quads = batch_quads - 1;
    try geometry.reserve(renderer, 1);
    try std.testing.expectEqual(batch_quads - 1, geometry.queued_quads);
    geometry.queued_quads += 1;
    try geometry.reserve(renderer, 1);
    try std.testing.expectEqual(@as(usize, 0), geometry.queued_quads);
    geometry.queued_quads = 1;
    try geometry.reserve(renderer, batch_quads);
    try std.testing.expectEqual(@as(usize, 0), geometry.queued_quads);
    geometry.queued_quads = batch_quads;
    try geometry.finish(renderer);
    try std.testing.expectEqual(@as(usize, 0), geometry.queued_quads);
}

test "cursor shapes blink and outline above selection at fractional scales without replacing texture or frame" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const presentation: instance.PresentationConfig = .{
        .text = .{ .private = .{ .regular = .{ .path = .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 15 } } } } },
        .box_drawing = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
        .shape_cache = .{ .entry_capacity = 32, .scalar_capacity = 128, .glyph_capacity = 128, .max_sequence_scalars = 16 },
        .atlas = .{ .width = 256, .height = 256, .entry_capacity = 128 },
        .shaped_capacity = 128,
        .raster_bytes = 256 * 256,
        .command_capacity = 256,
        .command_limit = instance.render.limits.maximum_frame_commands,
    };
    const owner = try terminal.Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf 'W\\033[1;1H\\033]0;CURSOR-READY\\007'; while read line; do printf '\\033[%s q' \"$line\"; done",
        .rows = 2,
        .columns = 4,
        .color_defaults = .{
            .foreground = .{ .r = 245, .g = 245, .b = 245 },
            .background = .{ .r = 10, .g = 20, .b = 30 },
            .cursor = .{ .r = 240, .g = 20, .b = 30 },
            .cursor_text = .{ .r = 20, .g = 240, .b = 30 },
        },
    }, presentation, 0, true);
    defer owner.destroy();
    const surface = c.SDL_CreateSurface(160, 160, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    try std.testing.expect(c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND));
    var backend = Canvas.init(std.testing.allocator);
    defer backend.deinit();
    const geometry = try std.testing.allocator.create(Geometry);
    defer std.testing.allocator.destroy(geometry);
    geometry.* = .{};
    var ready_attempts: u16 = 0;
    while (ready_attempts < 5000) : (ready_attempts += 1) {
        try backend.update(renderer, owner);
        const status = owner.snapshot();
        if (status.failure) |failure| return failure;
        if (std.mem.eql(u8, status.title[0..status.title_len], "CURSOR-READY")) {
            if (backend.frame()) |frame| if (frame.terminal_revision == status.revision) break;
        }
        owner.requestFrame();
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    if (ready_attempts == 5000) return error.Timeout;
    var retained_revision: ?u64 = null;
    var retained_texture: ?*c.SDL_Texture = null;
    var pixels: [160 * 160][3]u8 = undefined;
    for ([_][]const u8{ "2", "1", "4", "3", "6", "5" }) |style| {
        const before_revision = owner.snapshot().revision;
        var input: [2]u8 = .{ style[0], '\n' };
        try owner.submit(.{ .input = .{ .bytes = &input } });
        var attempts: u16 = 0;
        while (attempts < 5000) : (attempts += 1) {
            try backend.update(renderer, owner);
            const status = owner.snapshot();
            if (status.failure) |failure| return failure;
            if (status.revision > before_revision) {
                if (backend.frame()) |frame| if (frame.terminal_revision == status.revision) break;
            }
            owner.requestFrame();
            try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
        }
        if (attempts == 5000) return error.Timeout;
        const frame = backend.frame().?;
        try std.testing.expectEqual((style[0] - '0') % 2 == 1, frame.cursor_blink);
        try std.testing.expect(frame.content_command_count < frame.commands.len);
        if (retained_revision) |revision| try std.testing.expectEqual(revision, frame.content_revision) else retained_revision = frame.content_revision;
        const pane: c.SDL_FRect = .{ .x = 0, .y = 0, .w = @floatFromInt(frame.surface.width), .h = @floatFromInt(frame.surface.height) };
        for ([_]CursorDisplay{ .shown, .hidden, .outline }) |mode| for ([_]f32{ 1, 1.25, 1.6, 2 }) |scale| for ([_]bool{ false, true }) |selected| {
            backend.selection_paint = .{ .rows = 2 };
            if (selected) backend.selection_paint.spans[0] = .{ .first = 0, .last = 1 };
            try std.testing.expect(c.SDL_SetRenderScale(renderer, scale, scale));
            try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255));
            try std.testing.expect(c.SDL_RenderClear(renderer));
            try backend.draw(renderer, geometry, pane, scale, mode);
            try std.testing.expect(c.SDL_RenderPresent(renderer));
            const target = backend.content.?;
            if (retained_texture) |previous| try std.testing.expectEqual(previous, target) else retained_texture = target;
            var green_ink: usize = 0;
            for (0..frame.surface.height) |y| for (0..frame.surface.width) |x| {
                const at = y * frame.surface.width + x;
                const pixel = &pixels[at];
                try std.testing.expect(c.SDL_ReadSurfacePixel(surface, @intCast(x), @intCast(y), &pixel[0], &pixel[1], &pixel[2], null));
                if (@as(u16, pixel[1]) > @as(u16, pixel[0]) + 50 and @as(u16, pixel[1]) > @as(u16, pixel[2]) + 50) green_ink += 1;
            };
            try std.testing.expect((green_ink != 0) == (mode == .shown and (style[0] == '1' or style[0] == '2')));
            try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255));
            try std.testing.expect(c.SDL_RenderClear(renderer));
            // Independent full-command oracle plus exact one-pixel outline edges.
            try std.testing.expect(c.SDL_SetRenderScale(renderer, 1, 1));
            try backend.drawCommands(renderer, geometry, pane, frame.commands[0..frame.content_command_count]);
            if (selected) {
                try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, 180, 180, 180, 100));
                const selected_rect: c.SDL_FRect = .{ .x = 0, .y = 0, .w = @floatFromInt(2 * frame.cell_size.width), .h = @floatFromInt(frame.cell_size.height) };
                try std.testing.expect(c.SDL_RenderFillRect(renderer, &selected_rect));
            }
            if (mode == .shown) try backend.drawCommands(renderer, geometry, pane, frame.commands[frame.content_command_count..]);
            try std.testing.expect(c.SDL_RenderPresent(renderer));
            for (0..frame.surface.height) |y| for (0..frame.surface.width) |x| {
                var actual: [3]u8 = undefined;
                try std.testing.expect(c.SDL_ReadSurfacePixel(surface, @intCast(x), @intCast(y), &actual[0], &actual[1], &actual[2], null));
                if (mode == .outline) {
                    const overlay = frame.cursor.?;
                    const r = overlay.rect;
                    const left: usize = @intCast(r.x);
                    const top: usize = @intCast(r.y);
                    if (x >= left and x < left + r.width and y >= top and y < top + r.height and
                        (x == left or x == left + r.width - 1 or y == top or y == top + r.height - 1))
                        actual = .{ overlay.color.r, overlay.color.g, overlay.color.b };
                }
                try std.testing.expectEqual(pixels[y * frame.surface.width + x], actual);
            };
            try std.testing.expectEqual(target, backend.content.?);
            try std.testing.expectEqual(frame.sequence, backend.frame().?.sequence);
            try std.testing.expectEqual(frame.content_revision, backend.content_revision.?);
        };
    }
}

test "pending drag requests retain accepted selection paint; accepted clear removes it" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    const surface = c.SDL_CreateSurface(40, 20, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    var backend = Canvas.init(std.testing.allocator);
    defer backend.deinit();
    backend.selection_paint = .{ .serial = 11, .rows = 1 };
    backend.selection_paint.spans[0] = .{ .first = 0, .last = 1 };
    const frame: instance.PublishedFrame = .{
        .sequence = 1,
        .presentation_generation = 1,
        .revision = 1,
        .terminal_revision = 1,
        .history_offset = 0,
        .history_count = 0,
        .history_row_base = 0,
        .alternate_screen = false,
        .surface = .{ .width = 40, .height = 20 },
        .cell_size = .{ .width = 10, .height = 20 },
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{},
        .pixels = &.{},
    };
    try std.testing.expect(c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND));
    for ([_]bool{ false, true }) |cleared| {
        if (cleared) backend.selection_paint = .{ .serial = 999 };
        try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255));
        try std.testing.expect(c.SDL_RenderClear(renderer));
        try backend.drawSelection(renderer, .{ .x = 0, .y = 0, .w = 40, .h = 20 }, frame);
        try std.testing.expect(c.SDL_RenderPresent(renderer));
        var red: u8 = 0;
        try std.testing.expect(c.SDL_ReadSurfacePixel(surface, 5, 5, &red, null, null, null));
        try std.testing.expect(if (cleared) red == 0 else red > 0);
        try std.testing.expect(!c.SDL_RenderClipEnabled(renderer));
    }
}
