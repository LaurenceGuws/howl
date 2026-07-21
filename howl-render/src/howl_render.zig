//! Owns shared terminal text, glyph masks, and frame draw preparation.

const std = @import("std");
const howl_frame = @import("howl_frame");
const howl_text = @import("howl_text");

/// Bounds zero-byte glyph metadata and direct lookup work independently of the
/// byte cap. One thousand twenty-four entries occupy 48 KiB on 64-bit targets.
pub const cache_capacity: usize = 1_024;
/// Bounds all retained glyph alpha masks to eight MiB.
pub const cache_byte_capacity: usize = 8 * 1024 * 1024;
/// Bounds one composed window generation to sixteen visible terminals.
pub const max_panes: usize = 16;

/// Reports invalid composition facts or exact shared-text/cache failure.
pub const Error = howl_text.ShapeError || howl_text.RasterError ||
    howl_text.GeneratedError || std.mem.Allocator.Error || error{
    InvalidGeneration,
    InvalidWindow,
    InvalidPane,
    InvalidFrame,
    GlyphRunTooLarge,
    CacheFull,
    CacheGenerationExhausted,
    MaskIdentityExhausted,
    MaskTooLarge,
};

/// Places one terminal frame in logical window pixels.
pub const Pane = struct {
    /// Locates the pane's left edge in window pixels.
    x: u32,
    /// Locates the pane's top edge in window pixels.
    y: u32,
    /// Bounds presentation to this nonzero pixel width.
    width: u32,
    /// Bounds presentation to this nonzero pixel height.
    height: u32,
    /// Borrows one immutable terminal-local frame for this call only.
    frame: howl_frame.TerminalFrame,
};

/// Reports exact cache-backed preparation work for one accepted generation.
/// This checkpoint emits no GLES draw commands: the result proves that every
/// damaged visible glyph mask needed by the accepted frames is resident and
/// gives a bounded generation/fact boundary for the later draw owner.
pub const Prepared = struct {
    /// Identifies the accepted strictly increasing composition generation.
    generation: u64,
    /// Reports how many panes were validated and prepared.
    panes: u8,
    /// Counts cells visited through complete or row-damage preparation.
    cells: usize,
    /// Counts visible source clusters submitted to text shaping.
    clusters: usize,
    /// Counts positioned glyph masks resolved for damaged clusters.
    glyphs: usize,
    /// Counts cells rendered as U+FFFD because no configured face covered them.
    replacement_cells: usize,
    /// Counts glyph masks reused from the shared cache.
    cache_hits: usize,
    /// Counts glyph masks admitted to the shared cache.
    cache_misses: usize,
    /// Reports bytes retained by all cache entries after preparation.
    cache_bytes: usize,
};

/// Borrows one cache-resident alpha mask and its exact cell placement.
pub const Glyph = struct {
    /// Identifies this cache admission without reuse.
    identity: u64,
    /// Borrows tightly packed alpha bytes until the next preparation call.
    pixels: []const u8,
    /// Reports the mask width in pixels.
    width: u16,
    /// Reports the mask height in pixels.
    height: u16,
    /// Places the mask left edge relative to the shaped pen.
    left: i16,
    /// Places the mask top edge relative to the text baseline.
    top: i16,
    /// Applies the shaped horizontal offset in FreeType 26.6 units.
    x_offset: i32,
    /// Applies the shaped vertical offset in FreeType 26.6 units.
    y_offset: i32,
};

/// Carries every positioned glyph emitted for one bounded terminal cell.
pub const CellGlyphs = struct {
    /// Stores only the first `count` initialized glyph placements.
    values: [max_cell_codepoints]Glyph = undefined,
    /// Bounds initialized placements to one base plus trailing cell scalars.
    count: u8 = 0,

    /// Borrows only initialized glyph facts.
    pub fn slice(self: *const CellGlyphs) []const Glyph {
        return self.values[0..self.count];
    }
};

const max_cell_codepoints = howl_frame.max_combining + 1;

const Key = union(enum) {
    native: struct { face: u8, glyph: u32, span: u16 },
    generated: struct { codepoint: u21, width: u16, height: u16 },
};

const Entry = struct {
    identity: u64,
    key: Key,
    pixels: []u8,
    width: u16,
    height: u16,
    left: i16,
    top: i16,
    last_used_generation: u64,
};

const Cache = struct {
    entries: [cache_capacity]Entry = undefined,
    count: u16 = 0,
    bytes: usize = 0,
    last_identity: u64 = 0,

    fn deinit(self: *Cache, allocator: std.mem.Allocator) void {
        for (self.entries[0..self.count]) |entry| allocator.free(entry.pixels);
        self.* = undefined;
    }

    fn find(self: *Cache, key: Key, generation: u64) ?Entry {
        for (self.entries[0..self.count]) |*entry| {
            if (!std.meta.eql(entry.key, key)) continue;
            entry.last_used_generation = generation;
            return entry.*;
        }
        return null;
    }

    fn admit(
        self: *Cache,
        allocator: std.mem.Allocator,
        generation: u64,
        candidate: Candidate,
    ) Error!Entry {
        // Rejection precedes mutation and leaves candidate pixels caller-owned;
        // success performs no allocation and transfers that exact slice.
        if (candidate.pixels.len > cache_byte_capacity) return error.MaskTooLarge;
        if (self.last_identity == std.math.maxInt(u64))
            return error.MaskIdentityExhausted;
        var reclaimable_entries: usize = 0;
        var reclaimable_bytes: usize = 0;
        for (self.entries[0..self.count]) |entry| {
            if (entry.last_used_generation == generation) continue;
            reclaimable_entries += 1;
            reclaimable_bytes += entry.pixels.len;
        }
        const entry_needed = self.count == cache_capacity;
        const byte_needed = self.bytes > cache_byte_capacity - candidate.pixels.len;
        if (entry_needed and reclaimable_entries == 0 or
            byte_needed and reclaimable_bytes <
                self.bytes - (cache_byte_capacity - candidate.pixels.len))
            return error.CacheFull;
        while (self.count == cache_capacity or
            self.bytes > cache_byte_capacity - candidate.pixels.len)
        {
            const victim = self.oldestBefore(generation) orelse
                return error.CacheFull;
            self.remove(allocator, victim);
        }
        const index = self.count;
        const entry = Entry{
            .identity = self.last_identity + 1,
            .key = candidate.key,
            .pixels = candidate.pixels,
            .width = candidate.width,
            .height = candidate.height,
            .left = candidate.left,
            .top = candidate.top,
            .last_used_generation = generation,
        };
        self.entries[index] = entry;
        self.count += 1;
        self.bytes += candidate.pixels.len;
        self.last_identity = entry.identity;
        return entry;
    }

    fn oldestBefore(self: *const Cache, generation: u64) ?u16 {
        var oldest: ?u16 = null;
        for (self.entries[0..self.count], 0..) |entry, index| {
            if (entry.last_used_generation == generation) continue;
            if (oldest == null or entry.last_used_generation <
                self.entries[oldest.?].last_used_generation)
                oldest = @intCast(index);
        }
        return oldest;
    }

    fn remove(self: *Cache, allocator: std.mem.Allocator, index: u16) void {
        const removed = self.entries[index];
        self.bytes -= removed.pixels.len;
        allocator.free(removed.pixels);
        self.count -= 1;
        if (index != self.count) self.entries[index] = self.entries[self.count];
    }
};

const Candidate = struct {
    key: Key,
    /// Transfers this exact allocation to Cache only when admission succeeds.
    pixels: []u8,
    width: u16,
    height: u16,
    left: i16,
    top: i16,
};

/// Owns one mutable font set and one glyph-mask cache shared by every pane.
/// Calls are externally serialized on the future render thread. Frame slices
/// are borrowed only for `prepare`; no frame-publisher lock is held here.
pub const Renderer = struct {
    allocator: std.mem.Allocator,
    fonts: howl_text.FontSet,
    cache: Cache = .{},
    last_generation: u64 = 0,
    cache_generation: u64 = 0,

    /// Opens exactly one shared font owner and an initially empty cache.
    pub fn init(
        allocator: std.mem.Allocator,
        config: howl_text.Config,
    ) howl_text.InitError!Renderer {
        return .{
            .allocator = allocator,
            .fonts = try .init(allocator, config),
        };
    }

    /// Releases every retained alpha mask and the shared native font owner.
    pub fn deinit(self: *Renderer) void {
        self.cache.deinit(self.allocator);
        self.fonts.deinit();
        self.* = undefined;
    }

    /// Returns immutable font-derived geometry for host layout.
    pub fn metrics(self: *const Renderer) howl_text.Metrics {
        return self.fonts.metrics;
    }

    /// Validates and prepares one strictly newer complete pane composition.
    /// Superseded generations are rejected; callers coalesce before entering
    /// this owner. Cache entries used by this generation cannot be evicted
    /// until preparation finishes. A later shaping/raster failure leaves
    /// successfully prepared masks reusable while generation remains
    /// unaccepted, so retrying the same generation is valid and bounded.
    pub fn prepare(
        self: *Renderer,
        generation: u64,
        window_width: u32,
        window_height: u32,
        panes: []const Pane,
    ) Error!Prepared {
        if (generation == 0 or generation <= self.last_generation)
            return error.InvalidGeneration;
        if (window_width == 0 or window_height == 0)
            return error.InvalidWindow;
        if (panes.len == 0 or panes.len > max_panes) return error.InvalidPane;
        try validatePanes(window_width, window_height, panes, self.fonts.metrics);

        if (self.cache_generation == std.math.maxInt(u64))
            return error.CacheGenerationExhausted;
        self.cache_generation += 1;
        const cache_generation = self.cache_generation;
        var prepared = Prepared{
            .generation = generation,
            .panes = @intCast(panes.len),
            .cells = 0,
            .clusters = 0,
            .glyphs = 0,
            .replacement_cells = 0,
            .cache_hits = 0,
            .cache_misses = 0,
            .cache_bytes = 0,
        };
        for (panes) |pane|
            try self.preparePane(cache_generation, pane, &prepared);
        self.last_generation = generation;
        prepared.cache_bytes = self.cache.bytes;
        return prepared;
    }

    fn preparePane(
        self: *Renderer,
        cache_generation: u64,
        pane: Pane,
        prepared: *Prepared,
    ) Error!void {
        const frame = pane.frame;
        for (0..frame.rows) |row| {
            const damage = frame.damage.rows[row];
            if (!frame.damage.full and !damage.dirty) continue;
            const start: u16 = if (frame.damage.full) 0 else damage.start;
            const end: u16 = if (frame.damage.full) frame.cols - 1 else damage.end;
            var col = start;
            while (col <= end) : (col += 1) {
                prepared.cells += 1;
                const cell = frame.cells[row * frame.cols + col];
                if (cell.x != 0 or cell.y != 0 or cell.codepoint == 0 or
                    cell.invisible) continue;
                prepared.clusters += 1;
                const glyphs = try self.resolveCell(
                    cache_generation,
                    cell,
                    prepared,
                );
                prepared.glyphs += glyphs.count;
            }
        }
    }

    fn resolveCell(
        self: *Renderer,
        cache_generation: u64,
        cell: howl_frame.Cell,
        prepared: *Prepared,
    ) Error!CellGlyphs {
        var codepoints: [max_cell_codepoints]u32 = undefined;
        codepoints[0] = cell.codepoint;
        for (cell.combining[0..cell.combining_len], 0..) |value, index|
            codepoints[index + 1] = value;
        var values = codepoints[0 .. cell.combining_len + 1];
        if (values.len == 1 and howl_text.classifyGenerated(cell.codepoint) != null) {
            const glyph = try self.resolveGenerated(
                cache_generation,
                cell.codepoint,
                cell.width,
                prepared,
            );
            var result = CellGlyphs{};
            result.values[0] = glyph;
            result.count = 1;
            return result;
        }
        const clusters = [_]u32{0} ** max_cell_codepoints;
        var run = self.fonts.shape(self.allocator, .{
            .codepoints = values,
            .clusters = clusters[0..values.len],
            .cell_span = cell.width,
        }) catch |failure| switch (failure) {
            error.MissingGlyph => replacement: {
                codepoints[0] = 0xfffd;
                values = codepoints[0..1];
                prepared.replacement_cells += 1;
                break :replacement try self.fonts.shape(self.allocator, .{
                    .codepoints = values,
                    .clusters = clusters[0..1],
                    .cell_span = cell.width,
                });
            },
            else => return failure,
        };
        defer run.deinit();
        if (run.glyphs.len > max_cell_codepoints) return error.GlyphRunTooLarge;
        var result = CellGlyphs{};
        var pen_x: i32 = 0;
        var pen_y: i32 = 0;
        for (run.glyphs) |glyph| {
            const key = Key{ .native = .{
                .face = run.face_index,
                .glyph = glyph.id,
                .span = cell.width,
            } };
            const entry = if (self.cache.find(key, cache_generation)) |found| hit: {
                prepared.cache_hits += 1;
                break :hit found;
            } else admitted: {
                var raster = try self.fonts.rasterize(
                    self.allocator,
                    run.face_index,
                    glyph.id,
                    cell.width,
                );
                const value = self.cache.admit(self.allocator, cache_generation, .{
                    .key = key,
                    .pixels = raster.pixels,
                    .width = raster.width,
                    .height = raster.height,
                    .left = raster.left,
                    .top = raster.top,
                }) catch |failure| {
                    raster.deinit();
                    return failure;
                };
                raster.pixels = undefined;
                prepared.cache_misses += 1;
                break :admitted value;
            };
            result.values[result.count] = glyphFromEntry(
                entry,
                std.math.add(i32, pen_x, glyph.x_offset) catch
                    return error.InvalidShapeResult,
                std.math.add(i32, pen_y, glyph.y_offset) catch
                    return error.InvalidShapeResult,
            );
            result.count += 1;
            pen_x = std.math.add(i32, pen_x, glyph.x_advance) catch
                return error.InvalidShapeResult;
            pen_y = std.math.add(i32, pen_y, glyph.y_advance) catch
                return error.InvalidShapeResult;
        }
        return result;
    }

    fn resolveGenerated(
        self: *Renderer,
        cache_generation: u64,
        codepoint: u21,
        span: u8,
        prepared: *Prepared,
    ) Error!Glyph {
        const width = std.math.mul(u16, self.fonts.metrics.cell_width, span) catch
            return error.InvalidFrame;
        const height = self.fonts.metrics.cell_height;
        const key = Key{ .generated = .{
            .codepoint = codepoint,
            .width = width,
            .height = height,
        } };
        if (self.cache.find(key, cache_generation)) |entry| {
            prepared.cache_hits += 1;
            return glyphFromEntry(entry, 0, 0);
        }
        const count = std.math.mul(usize, width, height) catch
            return error.InvalidFrame;
        const pixels = self.allocator.alloc(u8, count) catch
            return error.OutOfMemory;
        errdefer self.allocator.free(pixels);
        try howl_text.rasterizeGenerated(pixels, width, height, codepoint);
        const entry = try self.cache.admit(self.allocator, cache_generation, .{
            .key = key,
            .pixels = pixels,
            .width = width,
            .height = height,
            .left = 0,
            .top = @intCast(self.fonts.metrics.baseline),
        });
        prepared.cache_misses += 1;
        return glyphFromEntry(entry, 0, 0);
    }

    /// Resolves one cell after successful preparation without admitting a new
    /// mask. The concrete draw owner consumes the returned borrowed pixels
    /// before another preparation call may mutate cache ownership.
    pub fn preparedGlyphs(self: *Renderer, cell: howl_frame.Cell) Error!CellGlyphs {
        var facts = Prepared{
            .generation = self.last_generation,
            .panes = 0,
            .cells = 0,
            .clusters = 0,
            .glyphs = 0,
            .replacement_cells = 0,
            .cache_hits = 0,
            .cache_misses = 0,
            .cache_bytes = self.cache.bytes,
        };
        const glyphs = try self.resolveCell(self.cache_generation, cell, &facts);
        if (facts.cache_misses != 0)
            @panic("successful preparation omitted a visible glyph mask");
        return glyphs;
    }
};

fn glyphFromEntry(entry: Entry, x_offset: i32, y_offset: i32) Glyph {
    return .{
        .identity = entry.identity,
        .pixels = entry.pixels,
        .width = entry.width,
        .height = entry.height,
        .left = entry.left,
        .top = entry.top,
        .x_offset = x_offset,
        .y_offset = y_offset,
    };
}

fn validatePanes(
    window_width: u32,
    window_height: u32,
    panes: []const Pane,
    metrics_value: howl_text.Metrics,
) Error!void {
    for (panes) |pane| {
        if (pane.width == 0 or pane.height == 0 or
            pane.x >= window_width or pane.y >= window_height or
            pane.width > window_width - pane.x or
            pane.height > window_height - pane.y)
            return error.InvalidPane;
        const frame = pane.frame;
        if (frame.generation == 0 or frame.rows == 0 or frame.cols == 0 or
            frame.cells.len != @as(usize, frame.rows) * frame.cols or
            frame.line_geometry.len != frame.rows or
            frame.damage.rows.len != frame.rows)
            return error.InvalidFrame;
        if (frame.cell_pixels) |pixels| {
            if (pixels.width != metrics_value.cell_width or
                pixels.height != metrics_value.cell_height)
                return error.InvalidFrame;
        }
        if (@as(u64, frame.cols) * metrics_value.cell_width > pane.width or
            @as(u64, frame.rows) * metrics_value.cell_height > pane.height)
            return error.InvalidPane;
        if (frame.cursor.row >= frame.rows or frame.cursor.col >= frame.cols)
            return error.InvalidFrame;
        for (frame.damage.rows) |damage| if (damage.dirty and
            (damage.start > damage.end or damage.end >= frame.cols))
            return error.InvalidFrame;
        for (frame.cells) |cell| if (cell.combining_len > howl_frame.max_combining or
            cell.width == 0 or cell.height == 0 or cell.x >= cell.width or
            cell.y >= cell.height)
            return error.InvalidFrame;
    }
}

fn testFrame(cells: []const howl_frame.Cell, generation: u64) howl_frame.TerminalFrame {
    const damage = [_]howl_frame.RowDamage{.{ .dirty = true, .start = 0, .end = 1 }};
    const geometry = [_]howl_frame.LineGeometry{.single_width};
    return .{
        .generation = generation,
        .surface_generation = generation,
        .terminal_generation = generation,
        .geometry_generation = 1,
        .rows = 1,
        .cols = 2,
        .cell_pixels = null,
        .cells = cells,
        .line_geometry = &geometry,
        .cursor = .{
            .row = 0,
            .col = 0,
            .visible = true,
            .shape = .block,
            .blink = false,
            .color = .{ .r = 255, .g = 255, .b = 255 },
            .text_color = .{ .r = 0, .g = 0, .b = 0 },
        },
        .selection = null,
        .alternate_screen = false,
        .damage = .{ .full = false, .rows = &damage },
    };
}

fn testCell(codepoint: u21) howl_frame.Cell {
    return .{
        .codepoint = codepoint,
        .combining_len = 0,
        .combining = @splat(0),
        .width = 1,
        .height = 1,
        .x = 0,
        .y = 0,
        .foreground = .{ .r = 1, .g = 2, .b = 3 },
        .background = .{ .r = 0, .g = 0, .b = 0 },
        .underline_color = .{ .r = 1, .g = 2, .b = 3 },
        .font = 0,
        .baseline = .normal,
        .bold = false,
        .dim = false,
        .italic = false,
        .blink = false,
        .blink_fast = false,
        .invisible = false,
        .underline = false,
        .strikethrough = false,
        .underline_style = .straight,
        .link_id = 0,
    };
}

test "mirrored terminal frames share one glyph cache identity" {
    const paths = @import("render_test_paths");
    var renderer = try Renderer.init(std.testing.allocator, .{
        .primary = paths.font,
        .pixel_height = 18,
    });
    defer renderer.deinit();
    const cells = [_]howl_frame.Cell{ testCell('A'), testCell(0) };
    const frame = testFrame(&cells, 1);
    const metrics_value = renderer.metrics();
    const pane_width = @as(u32, metrics_value.cell_width) * 2;
    const panes = [_]Pane{
        Pane{
            .x = 0,
            .y = 0,
            .width = pane_width,
            .height = metrics_value.cell_height,
            .frame = frame,
        },
        Pane{
            .x = pane_width,
            .y = 0,
            .width = pane_width,
            .height = metrics_value.cell_height,
            .frame = frame,
        },
    };
    const prepared = try renderer.prepare(
        1,
        pane_width * 2,
        metrics_value.cell_height,
        &panes,
    );
    try std.testing.expectEqual(@as(usize, 1), prepared.cache_misses);
    try std.testing.expectEqual(@as(usize, 1), prepared.cache_hits);
    try std.testing.expectEqual(@as(u16, 1), renderer.cache.count);
}

test "prepared glyphs borrow the admitted mask without allocation or identity drift" {
    const paths = @import("render_test_paths");
    var renderer = try Renderer.init(std.testing.allocator, .{
        .primary = paths.font,
        .pixel_height = 18,
    });
    defer renderer.deinit();
    const cell = testCell('A');
    const cells = [_]howl_frame.Cell{ cell, testCell(0) };
    const frame = testFrame(&cells, 1);
    const metrics_value = renderer.metrics();
    const pane = Pane{
        .x = 0,
        .y = 0,
        .width = @as(u32, metrics_value.cell_width) * 2,
        .height = metrics_value.cell_height,
        .frame = frame,
    };
    const prepared = try renderer.prepare(1, pane.width, pane.height, &.{pane});
    try std.testing.expectEqual(@as(usize, 1), prepared.glyphs);
    const before = renderer.cache;
    const first = try renderer.preparedGlyphs(cell);
    const second = try renderer.preparedGlyphs(cell);
    try std.testing.expectEqual(@as(u8, 1), first.count);
    try std.testing.expectEqual(first.values[0].identity, second.values[0].identity);
    try std.testing.expectEqual(first.values[0].pixels.ptr, second.values[0].pixels.ptr);
    try std.testing.expectEqualDeep(before, renderer.cache);
}

test "damage and generation validation reject stale work before cache mutation" {
    const paths = @import("render_test_paths");
    var renderer = try Renderer.init(std.testing.allocator, .{
        .primary = paths.font,
        .pixel_height = 18,
    });
    defer renderer.deinit();
    const cells = [_]howl_frame.Cell{ testCell('A'), testCell(0) };
    const frame = testFrame(&cells, 1);
    const metrics_value = renderer.metrics();
    const pane = Pane{
        .x = 0,
        .y = 0,
        .width = @as(u32, metrics_value.cell_width) * 2,
        .height = metrics_value.cell_height,
        .frame = frame,
    };
    const accepted = try renderer.prepare(2, pane.width, pane.height, &.{pane});
    try std.testing.expectEqual(@as(u64, 2), accepted.generation);
    const before = renderer.cache;
    try std.testing.expectError(
        error.InvalidGeneration,
        renderer.prepare(2, pane.width, pane.height, &.{pane}),
    );
    try std.testing.expectEqualDeep(before, renderer.cache);
}

test "cache capacity pins one generation and later work evicts oldest" {
    var cache = Cache{};
    defer cache.deinit(std.testing.allocator);
    var pixel: u8 = 1;
    while (cache.count < cache_capacity) : (pixel +%= 1) {
        const pixels = try std.testing.allocator.dupe(u8, &.{pixel});
        const admitted = try cache.admit(std.testing.allocator, 1, .{
            .key = .{ .native = .{
                .face = 0,
                .glyph = cache.count + 1,
                .span = 1,
            } },
            .pixels = pixels,
            .width = 1,
            .height = 1,
            .left = 0,
            .top = 1,
        });
        try std.testing.expect(admitted.identity != 0);
    }
    const before = cache;
    const rejected = try std.testing.allocator.dupe(u8, &.{255});
    defer std.testing.allocator.free(rejected);
    try std.testing.expectError(error.CacheFull, cache.admit(
        std.testing.allocator,
        1,
        .{
            .key = .{ .native = .{ .face = 0, .glyph = 999, .span = 1 } },
            .pixels = rejected,
            .width = 1,
            .height = 1,
            .left = 0,
            .top = 1,
        },
    ));
    try std.testing.expectEqualDeep(before, cache);
    const replacement = try std.testing.allocator.dupe(u8, &.{255});
    const admitted = try cache.admit(std.testing.allocator, 2, .{
        .key = .{ .native = .{ .face = 0, .glyph = 999, .span = 1 } },
        .pixels = replacement,
        .width = 1,
        .height = 1,
        .left = 0,
        .top = 1,
    });
    try std.testing.expect(admitted.identity != 0);
    try std.testing.expect(cache.find(
        .{ .native = .{ .face = 0, .glyph = 999, .span = 1 } },
        2,
    ) != null);
    try std.testing.expectEqual(@as(u16, cache_capacity), cache.count);
    try std.testing.expectEqual(@as(usize, cache_capacity), cache.bytes);
}

test "cache takes one owned allocation without a second allocation" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var cache = Cache{};
    defer cache.deinit(failing.allocator());
    const pixels = try failing.allocator().dupe(u8, &.{1});
    failing.fail_index = failing.alloc_index;
    const admitted = try cache.admit(
        failing.allocator(),
        1,
        .{
            .key = .{ .native = .{ .face = 0, .glyph = 1, .span = 1 } },
            .pixels = pixels,
            .width = 1,
            .height = 1,
            .left = 0,
            .top = 1,
        },
    );
    try std.testing.expect(admitted.identity != 0);
    try std.testing.expect(!failing.has_induced_failure);
    try std.testing.expectEqual(@as(u16, 1), cache.count);
    try std.testing.expectEqual(@as(usize, 1), cache.bytes);
}

test "oversized mask rejection preserves caller ownership and cache" {
    var cache = Cache{};
    defer cache.deinit(std.testing.allocator);
    const pixels = try std.testing.allocator.alloc(u8, cache_byte_capacity + 1);
    defer std.testing.allocator.free(pixels);
    try std.testing.expectError(error.MaskTooLarge, cache.admit(
        std.testing.allocator,
        1,
        .{
            .key = .{ .native = .{ .face = 0, .glyph = 1, .span = 1 } },
            .pixels = pixels,
            .width = 1,
            .height = 1,
            .left = 0,
            .top = 1,
        },
    ));
    try std.testing.expectEqual(@as(u16, 0), cache.count);
    try std.testing.expectEqual(@as(usize, 0), cache.bytes);
}

test "byte preflight rejects before evicting insufficient old masks" {
    var cache = Cache{};
    defer cache.deinit(std.testing.allocator);
    const pinned = try std.testing.allocator.alloc(u8, 4 * 1024 * 1024);
    const admitted = try cache.admit(std.testing.allocator, 2, .{
        .key = .{ .native = .{ .face = 0, .glyph = 1, .span = 1 } },
        .pixels = pinned,
        .width = 1,
        .height = 1,
        .left = 0,
        .top = 1,
    });
    try std.testing.expect(admitted.identity != 0);
    for (2..4) |glyph| {
        const old = try std.testing.allocator.alloc(u8, 1024 * 1024);
        const old_admission = try cache.admit(std.testing.allocator, 1, .{
            .key = .{ .native = .{
                .face = 0,
                .glyph = @intCast(glyph),
                .span = 1,
            } },
            .pixels = old,
            .width = 1,
            .height = 1,
            .left = 0,
            .top = 1,
        });
        try std.testing.expect(old_admission.identity != 0);
    }
    const before_count = cache.count;
    const before_bytes = cache.bytes;
    const rejected = try std.testing.allocator.alloc(u8, 5 * 1024 * 1024);
    defer std.testing.allocator.free(rejected);
    try std.testing.expectError(error.CacheFull, cache.admit(
        std.testing.allocator,
        2,
        .{
            .key = .{ .native = .{ .face = 0, .glyph = 4, .span = 1 } },
            .pixels = rejected,
            .width = 1,
            .height = 1,
            .left = 0,
            .top = 1,
        },
    ));
    try std.testing.expectEqual(before_count, cache.count);
    try std.testing.expectEqual(before_bytes, cache.bytes);
    try std.testing.expectEqual(@as(u32, 2), cache.entries[1].key.native.glyph);
    try std.testing.expectEqual(@as(u32, 3), cache.entries[2].key.native.glyph);
}

test "missing source glyph admits one shared replacement and continues" {
    const paths = @import("render_test_paths");
    var renderer = try Renderer.init(std.testing.allocator, .{
        .primary = paths.font,
        .pixel_height = 18,
    });
    defer renderer.deinit();
    const accepted_cells = [_]howl_frame.Cell{ testCell('A'), testCell(0) };
    const missing_cells = [_]howl_frame.Cell{ testCell(0x10ffff), testCell(0) };
    const metrics_value = renderer.metrics();
    const width = @as(u32, metrics_value.cell_width) * 2;
    const panes = [_]Pane{
        Pane{
            .x = 0,
            .y = 0,
            .width = width,
            .height = metrics_value.cell_height,
            .frame = testFrame(&accepted_cells, 1),
        },
        Pane{
            .x = width,
            .y = 0,
            .width = width,
            .height = metrics_value.cell_height,
            .frame = testFrame(&missing_cells, 1),
        },
    };
    const prepared = try renderer.prepare(1, width * 2, metrics_value.cell_height, &panes);
    try std.testing.expectEqual(@as(usize, 1), prepared.replacement_cells);
    try std.testing.expectEqual(@as(u16, 2), renderer.cache.count);

    const reused = [_]Pane{
        panes[0],
        Pane{
            .x = width,
            .y = 0,
            .width = width,
            .height = metrics_value.cell_height,
            .frame = testFrame(&missing_cells, 1),
        },
    };
    const repeated = try renderer.prepare(
        2,
        width * 2,
        metrics_value.cell_height,
        &reused,
    );
    try std.testing.expectEqual(@as(usize, 1), repeated.replacement_cells);
    try std.testing.expectEqual(@as(usize, 2), repeated.cache_hits);
    try std.testing.expectEqual(@as(usize, 0), repeated.cache_misses);
}

test "generated mask allocation failure leaves cache and generation unchanged" {
    const paths = @import("render_test_paths");
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var renderer = try Renderer.init(failing.allocator(), .{
        .primary = paths.font,
        .pixel_height = 18,
    });
    defer renderer.deinit();
    failing.fail_index = failing.alloc_index;
    const cells = [_]howl_frame.Cell{ testCell(0x2500), testCell(0) };
    const frame = testFrame(&cells, 1);
    const metrics_value = renderer.metrics();
    const pane = Pane{
        .x = 0,
        .y = 0,
        .width = @as(u32, metrics_value.cell_width) * 2,
        .height = metrics_value.cell_height,
        .frame = frame,
    };
    try std.testing.expectError(
        error.OutOfMemory,
        renderer.prepare(1, pane.width, pane.height, &.{pane}),
    );
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectEqual(@as(u64, 0), renderer.last_generation);
    try std.testing.expectEqual(@as(u16, 0), renderer.cache.count);
}

test "generated raster failure releases the staged mask" {
    const paths = @import("render_test_paths");
    var renderer = try Renderer.init(std.testing.allocator, .{
        .primary = paths.font,
        .pixel_height = 18,
    });
    defer renderer.deinit();
    try std.testing.expect(
        @as(u32, renderer.metrics().cell_width) * std.math.maxInt(u8) >
            howl_text.max_generated_extent_px,
    );
    var prepared = Prepared{
        .generation = 1,
        .panes = 1,
        .cells = 1,
        .clusters = 1,
        .glyphs = 0,
        .replacement_cells = 0,
        .cache_hits = 0,
        .cache_misses = 0,
        .cache_bytes = 0,
    };
    try std.testing.expectError(
        error.RasterTooLarge,
        renderer.resolveGenerated(
            1,
            0x2500,
            std.math.maxInt(u8),
            &prepared,
        ),
    );
    try std.testing.expectEqual(@as(u16, 0), renderer.cache.count);
    try std.testing.expectEqual(@as(usize, 0), renderer.cache.bytes);
    try std.testing.expectEqual(@as(usize, 0), prepared.cache_misses);
}
