//! Owns one concrete EGL/GLES render thread for one retained terminal grid.
//!
//! Submission copies caller-owned visual state into one bounded pending slot.
//! The render thread takes that slot before shaping, rasterization, texture
//! upload, drawing, and swap, so no terminal borrow or caller storage crosses
//! the thread boundary. New submissions replace only pending work.

const std = @import("std");
const render = @import("howl_render");
const terminal = render.terminal;
const text = render.terminal_text;
const viewport = @import("viewport.zig");
const measure = @import("measure.zig");

const c = @import("renderer_c");

// Bounds one admitted terminal dimension before C integer narrowing.
const max_dimension: u16 = 512;
// Bounds retained visual cells for the initial one-terminal owner.
const max_cells: usize = 512 * 256;
// One row stages each base scalar and every bounded combining scalar.
const max_run_scalars: usize = @as(usize, max_dimension) * (terminal.max_combining + 1);
// HarfBuzz substitutions may expand beyond the input scalar count, so output
// storage follows the render capability's public glyph ceiling.
const max_run_glyphs: usize = render.text.max_glyphs;
const run_codepoint_bytes = max_run_scalars * @sizeOf(u32);
const run_cluster_bytes = max_run_scalars * @sizeOf(u32);
const run_shaped_bytes = max_run_glyphs * @sizeOf(render.text.Glyph);
const run_positioned_bytes = max_run_glyphs * @sizeOf(text.PositionedGlyph);
const run_scratch_bytes =
    run_codepoint_bytes + run_cluster_bytes + run_shaped_bytes + run_positioned_bytes;
// Bounds shared glyph identity and atlas storage independently of the grid.
const glyph_capacity: usize = 2_048;
const glyph_bucket_capacity: usize = glyph_capacity * 2;
const glyph_atlas_capacity: usize = 8;
const glyph_atlas_max_extent: u16 = 1_024;
const glyph_atlas_byte_capacity: usize = glyph_atlas_capacity *
    @as(usize, glyph_atlas_max_extent) * glyph_atlas_max_extent;
const glyph_metadata_byte_capacity: usize = 128 * 1024;
const clear_color = terminal.Rgb{ .r = 0x28, .g = 0x28, .b = 0x28 };

/// Supplies one nonzero concrete EGL window extent.
pub const PixelSize = struct {
    /// Sets width before checked C integer narrowing.
    width: u32,
    /// Sets height before checked C integer narrowing.
    height: u32,
};

/// Supplies borrowed Wayland and font construction facts through startup.
pub const Init = struct {
    /// Borrows the connected display through renderer shutdown.
    display: *c.struct_wl_display,
    /// Borrows the live surface through renderer shutdown.
    surface: *c.struct_wl_surface,
    /// Sets the initial nonzero surface extent.
    size: PixelSize,
    /// Sizes each retained snapshot for the initial nonzero row count.
    rows: u16,
    /// Sizes each retained snapshot for the initial nonzero column count.
    cols: u16,
    /// Borrows exact font configurations through synchronous startup only.
    fonts: []const text.FontConfig,
    measurement: measure.Reference,
};

/// Borrows one complete immutable executable-retained visual grid for submit.
pub const Submission = struct {
    /// Is strictly increasing and nonzero for accepted work.
    generation: u64,
    /// Sets the current nonzero terminal row count.
    rows: u16,
    /// Sets the current nonzero terminal column count.
    cols: u16,
    /// Borrows exactly `rows * cols` cells for the duration of submit.
    cells: []const terminal.Cell,
    /// Borrows exactly one DEC geometry fact per visible row for submit.
    row_geometry: []const terminal.LineGeometry,
    /// Copies the current cursor overlay.
    cursor: terminal.Cursor,
    /// Sets the current nonzero presentation extent.
    size: PixelSize,
    /// Copies optional host-owned scrollbar pixels for this visual state.
    scrollbar: ?viewport.Scrollbar = null,
    /// Identifies the complete retained terminal image state.
    image_generation: u64 = 0,
    /// Identifies decoded image content independently of placement churn.
    image_content_generation: u64 = 0,
    /// Borrows packed RGBA8 image bytes only through submit.
    image_pixels: []const u8 = &.{},
    /// Borrows complete retained image descriptions.
    images: []const terminal.ImageUpload = &.{},
    /// Borrows complete visible image placements.
    image_placements: []const terminal.ImagePlacement = &.{},
};

/// Reports exact construction, admission, preparation, or device failure.
pub const Error = std.mem.Allocator.Error || std.Thread.SpawnError ||
    render.text.ShapeBufferInitError || text.FontMapInitError ||
    text.PrepareError || text.RasterError || error{
    InvalidSubmission,
    StaleGeneration,
    Stopping,
    EglDisplay,
    EglInitialize,
    EglConfig,
    EglContext,
    EglSurface,
    Shader,
    Texture,
    CacheFull,
    Draw,
    Swap,
    Signal,
    Cleanup,
};

const Snapshot = struct {
    allocator: std.mem.Allocator,
    cells: []terminal.Cell,
    row_geometry: []terminal.LineGeometry,
    generation: u64 = 0,
    rows: u16 = 0,
    cols: u16 = 0,
    cursor: terminal.Cursor = undefined,
    size: PixelSize = undefined,
    scrollbar: ?viewport.Scrollbar = null,
    image_generation: u64 = 0,
    image_content_generation: u64 = 0,
    image_pixels: []u8 = &.{},
    images: []terminal.ImageUpload = &.{},
    image_placements: []terminal.ImagePlacement = &.{},
    image_pixel_count: usize = 0,
    image_count: usize = 0,
    image_placement_count: usize = 0,
    submitted_at: measure.Mark = if (measure.enabled) undefined else {},

    fn init(allocator: std.mem.Allocator, rows: u16, cols: u16) std.mem.Allocator.Error!Snapshot {
        const cells = try allocator.alloc(terminal.Cell, @as(usize, rows) * cols);
        errdefer allocator.free(cells);
        const row_geometry = try allocator.alloc(terminal.LineGeometry, rows);
        return .{ .allocator = allocator, .cells = cells, .row_geometry = row_geometry };
    }

    fn ensureCapacity(self: *Snapshot, rows: u16, cols: u16) std.mem.Allocator.Error!void {
        const required_cells = @as(usize, rows) * cols;
        if (required_cells <= self.cells.len and rows <= self.row_geometry.len) return;
        const cells = if (required_cells > self.cells.len)
            try self.allocator.alloc(terminal.Cell, required_cells)
        else
            null;
        errdefer if (cells) |owned| self.allocator.free(owned);
        const geometry = if (rows > self.row_geometry.len)
            try self.allocator.alloc(terminal.LineGeometry, rows)
        else
            null;
        if (cells) |owned| {
            self.allocator.free(self.cells);
            self.cells = owned;
        }
        if (geometry) |owned| {
            self.allocator.free(self.row_geometry);
            self.row_geometry = owned;
        }
        self.generation = 0;
        self.rows = 0;
        self.cols = 0;
    }

    fn ensureImageCapacity(
        self: *Snapshot,
        pixel_count: usize,
        image_count: usize,
        placement_count: usize,
    ) std.mem.Allocator.Error!void {
        const pixels = if (pixel_count > self.image_pixels.len)
            try self.allocator.alloc(u8, pixel_count)
        else
            null;
        errdefer if (pixels) |owned| self.allocator.free(owned);
        const images = if (image_count > self.images.len)
            try self.allocator.alloc(terminal.ImageUpload, image_count)
        else
            null;
        errdefer if (images) |owned| self.allocator.free(owned);
        const placements = if (placement_count > self.image_placements.len)
            try self.allocator.alloc(terminal.ImagePlacement, placement_count)
        else
            null;
        if (pixels) |owned| {
            self.allocator.free(self.image_pixels);
            self.image_pixels = owned;
        }
        if (images) |owned| {
            self.allocator.free(self.images);
            self.images = owned;
        }
        if (placements) |owned| {
            self.allocator.free(self.image_placements);
            self.image_placements = owned;
        }
    }

    fn deinit(self: *Snapshot) void {
        self.allocator.free(self.cells);
        self.allocator.free(self.row_geometry);
        self.allocator.free(self.image_pixels);
        self.allocator.free(self.images);
        self.allocator.free(self.image_placements);
        self.* = undefined;
    }

    fn write(self: *Snapshot, submission: Submission, submitted_at: measure.Mark) void {
        const count = @as(usize, submission.rows) * submission.cols;
        std.debug.assert(count <= self.cells.len);
        @memcpy(self.cells[0..count], submission.cells);
        @memcpy(self.row_geometry[0..submission.rows], submission.row_geometry);
        self.generation = submission.generation;
        self.rows = submission.rows;
        self.cols = submission.cols;
        self.cursor = submission.cursor;
        self.size = submission.size;
        self.scrollbar = submission.scrollbar;
        self.submitted_at = submitted_at;
        if (self.image_content_generation != submission.image_content_generation) {
            std.debug.assert(submission.image_pixels.len <= self.image_pixels.len);
            std.debug.assert(submission.images.len <= self.images.len);
            @memcpy(self.image_pixels[0..submission.image_pixels.len], submission.image_pixels);
            @memcpy(self.images[0..submission.images.len], submission.images);
            self.image_pixel_count = submission.image_pixels.len;
            self.image_count = submission.images.len;
            self.image_content_generation = submission.image_content_generation;
        }
        if (self.image_generation != submission.image_generation) {
            std.debug.assert(submission.image_placements.len <= self.image_placements.len);
            @memcpy(
                self.image_placements[0..submission.image_placements.len],
                submission.image_placements,
            );
            self.image_placement_count = submission.image_placements.len;
            self.image_generation = submission.image_generation;
        }
    }

    fn view(self: *const Snapshot) Submission {
        const count = @as(usize, self.rows) * self.cols;
        return .{
            .generation = self.generation,
            .rows = self.rows,
            .cols = self.cols,
            .cells = self.cells[0..count],
            .row_geometry = self.row_geometry[0..self.rows],
            .cursor = self.cursor,
            .size = self.size,
            .scrollbar = self.scrollbar,
            .image_generation = self.image_generation,
            .image_content_generation = self.image_content_generation,
            .image_pixels = self.image_pixels[0..self.image_pixel_count],
            .images = self.images[0..self.image_count],
            .image_placements = self.image_placements[0..self.image_placement_count],
        };
    }
};

const Mailbox = struct {
    pending: ?*Snapshot = null,
    active: ?*Snapshot = null,
    free_first: ?*Snapshot = null,
    free_second: ?*Snapshot = null,

    fn release(self: *Mailbox, slot: *Snapshot) void {
        if (self.free_first == null) {
            self.free_first = slot;
        } else {
            std.debug.assert(self.free_second == null);
            self.free_second = slot;
        }
    }

    fn writable(self: *Mailbox) ?*Snapshot {
        if (self.free_second) |slot| {
            self.free_second = null;
            return slot;
        }
        const slot = self.free_first;
        self.free_first = null;
        return slot;
    }

    fn write(
        self: *Mailbox,
        submission: Submission,
        submitted_at: measure.Mark,
    ) std.mem.Allocator.Error!void {
        if (self.writable()) |slot| {
            errdefer self.release(slot);
            try slot.ensureCapacity(submission.rows, submission.cols);
            try slot.ensureImageCapacity(
                submission.image_pixels.len,
                submission.images.len,
                submission.image_placements.len,
            );
            slot.write(submission, submitted_at);
            if (self.admit(slot)) |replaced| self.release(replaced);
            return;
        }
        const slot = self.pending.?;
        try slot.ensureCapacity(submission.rows, submission.cols);
        try slot.ensureImageCapacity(
            submission.image_pixels.len,
            submission.images.len,
            submission.image_placements.len,
        );
        slot.write(submission, submitted_at);
    }

    fn admit(self: *Mailbox, slot: *Snapshot) ?*Snapshot {
        const replaced = self.pending;
        self.pending = slot;
        return replaced;
    }

    fn take(self: *Mailbox) ?*Snapshot {
        std.debug.assert(self.active == null);
        const slot = self.pending orelse return null;
        self.pending = null;
        self.active = slot;
        return slot;
    }

    fn complete(self: *Mailbox) void {
        const slot = self.active.?;
        self.active = null;
        self.release(slot);
    }
};

const TextureUv = struct {
    left: f32 = 0,
    top: f32 = 0,
    right: f32 = 1,
    bottom: f32 = 1,
};

const Glyph = struct {
    key: text.GlyphKey,
    atlas: ?u8,
    rect: AtlasRect = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    width: u16,
    height: u16,
    left: i16,
    top: i16,
    used: u64,
};

const AtlasRect = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,
};

const Atlas = struct {
    name: c.GLuint,
    x: u16 = 0,
    y: u16 = 0,
    row_height: u16 = 0,

    fn plan(self: Atlas, extent: u16, width: u16, height: u16) ?AtlasRect {
        if (width == 0 or height == 0 or width > extent or height > extent) return null;
        if (@as(u32, self.x) + width <= extent and
            @as(u32, self.y) + height <= extent)
            return .{ .x = self.x, .y = self.y, .width = width, .height = height };
        const next_y = @as(u32, self.y) + self.row_height;
        if (next_y + height > extent) return null;
        return .{ .x = 0, .y = @intCast(next_y), .width = width, .height = height };
    }

    fn admit(self: *Atlas, rect: AtlasRect) void {
        self.x = rect.x + rect.width;
        if (rect.y != self.y) self.row_height = 0;
        self.y = rect.y;
        self.row_height = @max(self.row_height, rect.height);
    }
};

const AtlasAdmission = union(enum) {
    existing: AtlasSelection,
    grow: AtlasRect,
    replace: AtlasSelection,
};

const AtlasSelection = struct { atlas: u8, rect: AtlasRect };

const GlyphCache = struct {
    extent: u16,
    glyphs: [glyph_capacity]Glyph = undefined,
    glyph_count: usize = 0,
    buckets: [glyph_bucket_capacity]u16 = @splat(0),
    atlases: [glyph_atlas_capacity]Atlas = undefined,
    atlas_count: usize = 0,

    fn find(self: *GlyphCache, key: text.GlyphKey, comparisons: *usize) ?*Glyph {
        var bucket = glyphHash(key) % self.buckets.len;
        for (0..self.buckets.len) |_| {
            const encoded = self.buckets[bucket];
            if (encoded == 0) return null;
            comparisons.* += 1;
            const glyph = &self.glyphs[encoded - 1];
            if (std.meta.eql(glyph.key, key)) return glyph;
            bucket = (bucket + 1) % self.buckets.len;
        }
        return null;
    }

    fn plan(self: *const GlyphCache, width: u16, height: u16, generation: u64) ?AtlasAdmission {
        if (width == 0 or height == 0 or width > self.extent or height > self.extent) return null;
        if (self.glyph_count < self.glyphs.len) {
            for (self.atlases[0..self.atlas_count], 0..) |atlas, index|
                if (atlas.plan(self.extent, width, height)) |rect|
                    return .{ .existing = .{ .atlas = @intCast(index), .rect = rect } };
            if (self.atlas_count < self.atlases.len) return .{
                .grow = .{ .x = 0, .y = 0, .width = width, .height = height },
            };
        }
        const victim = self.oldestAtlas(generation) orelse return null;
        return .{ .replace = .{
            .atlas = @intCast(victim),
            .rect = .{ .x = 0, .y = 0, .width = width, .height = height },
        } };
    }

    fn admit(
        self: *GlyphCache,
        admission: AtlasAdmission,
        name: c.GLuint,
        key: text.GlyphKey,
        raster: text.Raster,
        generation: u64,
    ) *Glyph {
        const selected = switch (admission) {
            .existing => |value| value,
            .grow => |rect| blk: {
                const atlas: u8 = @intCast(self.atlas_count);
                self.atlases[self.atlas_count] = .{ .name = name };
                self.atlas_count += 1;
                break :blk AtlasSelection{ .atlas = atlas, .rect = rect };
            },
            .replace => |value| blk: {
                self.removeAtlasGlyphs(value.atlas);
                self.atlases[value.atlas] = .{ .name = name };
                break :blk value;
            },
        };
        self.atlases[selected.atlas].admit(selected.rect);
        std.debug.assert(self.glyph_count < self.glyphs.len);
        const index = self.glyph_count;
        self.glyphs[index] = .{
            .key = key,
            .atlas = selected.atlas,
            .rect = selected.rect,
            .width = raster.width,
            .height = raster.height,
            .left = raster.left,
            .top = raster.top,
            .used = generation,
        };
        self.glyph_count += 1;
        self.insertBucket(index);
        return &self.glyphs[index];
    }

    fn admitEmpty(self: *GlyphCache, key: text.GlyphKey, raster: text.Raster, generation: u64) ?*Glyph {
        if (self.glyph_count == self.glyphs.len) return null;
        const index = self.glyph_count;
        self.glyphs[index] = .{
            .key = key,
            .atlas = null,
            .width = raster.width,
            .height = raster.height,
            .left = raster.left,
            .top = raster.top,
            .used = generation,
        };
        self.glyph_count += 1;
        self.insertBucket(index);
        return &self.glyphs[index];
    }

    fn oldestAtlas(self: *const GlyphCache, generation: u64) ?usize {
        var oldest: ?usize = null;
        var oldest_use: u64 = std.math.maxInt(u64);
        for (0..self.atlas_count) |atlas| {
            var last_use: u64 = 0;
            var current = false;
            for (self.glyphs[0..self.glyph_count]) |glyph| {
                if (glyph.atlas != @as(u8, @intCast(atlas))) continue;
                if (glyph.used == generation) current = true;
                last_use = @max(last_use, glyph.used);
            }
            if (!current and (oldest == null or last_use < oldest_use)) {
                oldest = atlas;
                oldest_use = last_use;
            }
        }
        return oldest;
    }

    fn removeAtlasGlyphs(self: *GlyphCache, atlas: usize) void {
        var write: usize = 0;
        for (self.glyphs[0..self.glyph_count]) |glyph| {
            if (glyph.atlas == @as(u8, @intCast(atlas))) continue;
            self.glyphs[write] = glyph;
            write += 1;
        }
        self.glyph_count = write;
        self.rebuildBuckets();
    }

    fn rebuildBuckets(self: *GlyphCache) void {
        self.buckets = @splat(0);
        for (0..self.glyph_count) |index| self.insertBucket(index);
    }

    fn insertBucket(self: *GlyphCache, glyph: usize) void {
        var bucket = glyphHash(self.glyphs[glyph].key) % self.buckets.len;
        while (self.buckets[bucket] != 0) bucket = (bucket + 1) % self.buckets.len;
        self.buckets[bucket] = @intCast(glyph + 1);
    }
};

comptime {
    std.debug.assert(@sizeOf(GlyphCache) <= glyph_metadata_byte_capacity);
}

fn glyphHash(key: text.GlyphKey) usize {
    var hash: u64 = 0xcbf29ce484222325;
    switch (key) {
        .native => |native| {
            hashByte(&hash, 0);
            hashByte(&hash, native.font.slot);
            hashByte(&hash, @backingInt(native.font.style));
            hashByte(&hash, native.face_index);
            hashU32(&hash, native.glyph_id);
            hashU32(&hash, native.cell_span);
        },
        .generated => |generated| {
            hashByte(&hash, 1);
            hashU32(&hash, generated.codepoint);
            hashU32(&hash, generated.width_px);
            hashU32(&hash, generated.height_px);
            hashU32(&hash, generated.baseline_px);
        },
    }
    return @intCast(hash % glyph_bucket_capacity);
}

fn hashByte(hash: *u64, value: u8) void {
    hash.* = (hash.* ^ value) *% 0x100000001b3;
}

fn hashU32(hash: *u64, value: u32) void {
    var remaining = value;
    for (0..@sizeOf(u32)) |_| {
        hashByte(hash, @truncate(remaining));
        remaining >>= 8;
    }
}

fn glyphUv(glyph: Glyph, extent: u16) TextureUv {
    std.debug.assert(glyph.atlas != null and glyph.rect.width != 0 and glyph.rect.height != 0);
    const divisor: f32 = @floatFromInt(extent);
    return .{
        .left = @as(f32, @floatFromInt(glyph.rect.x)) / divisor,
        .top = @as(f32, @floatFromInt(glyph.rect.y)) / divisor,
        .right = @as(f32, @floatFromInt(glyph.rect.x + glyph.rect.width)) / divisor,
        .bottom = @as(f32, @floatFromInt(glyph.rect.y + glyph.rect.height)) / divisor,
    };
}

const ImageTexture = struct {
    identity: terminal.ImageIdentity,
    name: c.GLuint,
    width: u32,
    height: u32,
};

const PixelRect = struct {
    x: i32,
    y: i32,
    width: u32,
    height: u32,
};

const BackgroundSpan = struct {
    rect: PixelRect,
    color: terminal.Rgb,
};

const BackgroundSpans = struct {
    work: Submission,
    row: u16,
    metrics: text.CellMetrics,
    logical_cols: u16,
    at: usize = 0,

    fn next(self: *BackgroundSpans) error{InvalidSubmission}!?BackgroundSpan {
        while (self.at < self.segmentCount()) {
            var span = try self.segment(self.at);
            self.at += 1;
            if (std.meta.eql(span.color, clear_color)) continue;
            while (self.at < self.segmentCount()) {
                const following = try self.segment(self.at);
                const right = @as(i64, span.rect.x) + span.rect.width;
                if (!std.meta.eql(span.color, following.color) or right != following.rect.x) break;
                span.rect.width = std.math.add(
                    u32,
                    span.rect.width,
                    following.rect.width,
                ) catch return error.InvalidSubmission;
                self.at += 1;
            }
            return span;
        }
        return null;
    }

    fn segmentCount(self: BackgroundSpans) usize {
        return @as(usize, self.logical_cols) + @intFromBool(self.tailWidth() != 0);
    }

    fn segment(self: BackgroundSpans, index: usize) error{InvalidSubmission}!BackgroundSpan {
        if (index < self.logical_cols) {
            const col: u16 = @intCast(index);
            const cell = self.work.cells[@as(usize, self.row) * self.work.cols + col];
            var rect = planCell(
                self.row,
                col,
                self.work.row_geometry[self.row],
                self.metrics,
            ) orelse return error.InvalidSubmission;
            const x: u32 = std.math.cast(u32, rect.x) orelse return error.InvalidSubmission;
            if (x >= self.rowWidth()) return error.InvalidSubmission;
            rect.width = @min(rect.width, self.rowWidth() - x);
            return .{
                .rect = rect,
                .color = cellFill(
                    cell,
                    self.work.cursor,
                    cursorBlockCovers(self.work, self.row, col),
                ),
            };
        }
        std.debug.assert(index == self.logical_cols and self.tailWidth() != 0);
        const covered = self.coveredWidth();
        const cell = self.work.cells[@as(usize, self.row) * self.work.cols + self.logical_cols];
        return .{
            .rect = .{
                .x = std.math.cast(i32, covered) orelse return error.InvalidSubmission,
                .y = std.math.cast(
                    i32,
                    @as(u64, self.row) * self.metrics.height_px,
                ) orelse return error.InvalidSubmission,
                .width = self.tailWidth(),
                .height = self.metrics.height_px,
            },
            .color = cell.background,
        };
    }

    fn coveredWidth(self: BackgroundSpans) u32 {
        return @as(u32, self.logical_cols) * self.metrics.width_px *
            lineScale(self.work.row_geometry[self.row]).x;
    }

    fn tailWidth(self: BackgroundSpans) u32 {
        return self.rowWidth() -| self.coveredWidth();
    }

    fn rowWidth(self: BackgroundSpans) u32 {
        return @as(u32, self.work.cols) * self.metrics.width_px;
    }
};

const Scale = struct {
    x: u2,
    y: u2,
    y_offset_cells: i2,
};

const Vertex = extern struct {
    x: f32,
    y: f32,
    u: f32,
    v: f32,
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

const batch_quad_capacity = 4096;
const vertices_per_quad = 6;

const DrawState = struct {
    texture: c.GLuint,
    texture_color: bool,
    scissor: ?PixelRect,
};

const DrawCommand = struct {
    state: DrawState,
    first: u32,
    count: u32,
};

const DrawBatch = struct {
    allocator: std.mem.Allocator,
    vertices: []Vertex,
    commands: []DrawCommand,
    vertex_count: usize = 0,
    command_count: usize = 0,

    fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!DrawBatch {
        const vertices = try allocator.alloc(Vertex, batch_quad_capacity * vertices_per_quad);
        errdefer allocator.free(vertices);
        const commands = try allocator.alloc(DrawCommand, batch_quad_capacity);
        return .{
            .allocator = allocator,
            .vertices = vertices,
            .commands = commands,
        };
    }

    fn stage(self: *DrawBatch, vertices: [vertices_per_quad]Vertex, state: DrawState) bool {
        if (self.vertex_count > self.vertices.len - vertices.len) return false;
        const first = self.vertex_count;
        const previous = if (self.command_count == 0)
            null
        else
            &self.commands[self.command_count - 1];
        const merge = if (previous) |command|
            std.meta.eql(command.state, state) and
                @as(usize, command.first) + command.count == first
        else
            false;
        if (!merge and self.command_count == self.commands.len) return false;
        @memcpy(self.vertices[first..][0..vertices.len], &vertices);
        self.vertex_count += vertices.len;
        if (merge) {
            previous.?.count += vertices.len;
        } else {
            self.commands[self.command_count] = .{
                .state = state,
                .first = @intCast(first),
                .count = vertices.len,
            };
            self.command_count += 1;
        }
        return true;
    }

    fn reset(self: *DrawBatch) void {
        self.vertex_count = 0;
        self.command_count = 0;
    }

    fn deinit(self: *DrawBatch) void {
        self.allocator.free(self.commands);
        self.allocator.free(self.vertices);
        self.* = undefined;
    }
};

const RunScratch = struct {
    allocator: std.mem.Allocator,
    shaper: render.text.ShapeBuffer,
    codepoints: []u32,
    clusters: []u32,
    shaped: []render.text.Glyph,
    positioned: []text.PositionedGlyph,

    fn init(
        allocator: std.mem.Allocator,
    ) (std.mem.Allocator.Error || render.text.ShapeBufferInitError)!RunScratch {
        const codepoints = try allocator.alloc(u32, max_run_scalars);
        errdefer allocator.free(codepoints);
        const clusters = try allocator.alloc(u32, max_run_scalars);
        errdefer allocator.free(clusters);
        const shaped = try allocator.alloc(render.text.Glyph, max_run_glyphs);
        errdefer allocator.free(shaped);
        const positioned = try allocator.alloc(text.PositionedGlyph, max_run_glyphs);
        errdefer allocator.free(positioned);
        const shaper = try render.text.ShapeBuffer.init(max_run_glyphs);
        return .{
            .allocator = allocator,
            .shaper = shaper,
            .codepoints = codepoints,
            .clusters = clusters,
            .shaped = shaped,
            .positioned = positioned,
        };
    }

    fn borrow(self: *RunScratch) text.NativeScratch {
        return .{
            .shaper = &self.shaper,
            .codepoints = self.codepoints,
            .clusters = self.clusters,
            .shaped = self.shaped,
            .positioned = self.positioned,
        };
    }

    fn deinit(self: *RunScratch) void {
        self.shaper.deinit();
        self.allocator.free(self.positioned);
        self.allocator.free(self.shaped);
        self.allocator.free(self.clusters);
        self.allocator.free(self.codepoints);
        self.* = undefined;
    }
};

const Device = struct {
    allocator: std.mem.Allocator,
    display: c.EGLDisplay,
    context: c.EGLContext,
    surface: c.EGLSurface,
    window: *c.struct_wl_egl_window,
    program: c.GLuint,
    texture_color_uniform: c.GLint,
    buffer: c.GLuint,
    white: c.GLuint,
    fonts: text.FontMap,
    run_scratch: RunScratch,
    draw_batch: DrawBatch,
    metrics: text.CellMetrics,
    glyph_cache: GlyphCache,
    image_textures: [256]ImageTexture = undefined,
    image_texture_count: usize = 0,
    image_texture_bytes: usize = 0,
    image_generation: u64 = 0,
    size: PixelSize,
    io: std.Io,
    measurement: measure.Reference,

    fn init(allocator: std.mem.Allocator, io: std.Io, values: Init) Error!Device {
        try validateSize(values.size);
        var fonts = try text.FontMap.init(allocator, values.fonts);
        errdefer fonts.deinit();
        var run_scratch = try RunScratch.init(allocator);
        errdefer run_scratch.deinit();
        var draw_batch = try DrawBatch.init(allocator);
        errdefer draw_batch.deinit();
        const default_key = text.FontKey{ .slot = 0, .style = .normal };
        const metrics = fonts.cellMetrics(default_key) orelse return error.InvalidSubmission;
        const window = c.wl_egl_window_create(
            values.surface,
            @intCast(values.size.width),
            @intCast(values.size.height),
        ) orelse return error.EglSurface;
        errdefer c.wl_egl_window_destroy(window);
        const display = c.eglGetDisplay(@ptrCast(values.display));
        if (display == c.EGL_NO_DISPLAY) return error.EglDisplay;
        if (c.eglInitialize(display, null, null) != c.EGL_TRUE) return error.EglInitialize;
        errdefer if (c.eglTerminate(display) != c.EGL_TRUE)
            @panic("EGL display rollback failed");
        if (c.eglBindAPI(c.EGL_OPENGL_ES_API) != c.EGL_TRUE) return error.EglContext;
        const attributes = [_]c.EGLint{
            c.EGL_SURFACE_TYPE,    c.EGL_WINDOW_BIT,
            c.EGL_RENDERABLE_TYPE, c.EGL_OPENGL_ES2_BIT,
            c.EGL_RED_SIZE,        8,
            c.EGL_GREEN_SIZE,      8,
            c.EGL_BLUE_SIZE,       8,
            c.EGL_NONE,
        };
        var config: c.EGLConfig = null;
        var config_count: c.EGLint = 0;
        if (c.eglChooseConfig(display, &attributes, &config, 1, &config_count) != c.EGL_TRUE or
            config_count != 1) return error.EglConfig;
        const context_attributes = [_]c.EGLint{ c.EGL_CONTEXT_CLIENT_VERSION, 2, c.EGL_NONE };
        const context = c.eglCreateContext(display, config, c.EGL_NO_CONTEXT, &context_attributes);
        if (context == c.EGL_NO_CONTEXT) return error.EglContext;
        errdefer if (c.eglDestroyContext(display, context) != c.EGL_TRUE)
            @panic("EGL context rollback failed");
        const surface = c.eglCreateWindowSurface(display, config, @intFromPtr(window), null);
        if (surface == c.EGL_NO_SURFACE) return error.EglSurface;
        errdefer if (c.eglDestroySurface(display, surface) != c.EGL_TRUE)
            @panic("EGL surface rollback failed");
        if (c.eglMakeCurrent(display, surface, surface, context) != c.EGL_TRUE)
            return error.EglContext;
        errdefer if (c.eglMakeCurrent(
            display,
            c.EGL_NO_SURFACE,
            c.EGL_NO_SURFACE,
            c.EGL_NO_CONTEXT,
        ) != c.EGL_TRUE) @panic("EGL current-context rollback failed");
        const program = try createProgram();
        errdefer c.glDeleteProgram(program);
        const texture_color_uniform = c.glGetUniformLocation(program, "texture_color");
        if (texture_color_uniform < 0) return error.Shader;
        c.glUniform1i(texture_color_uniform, 0);
        var max_texture_size: c.GLint = 0;
        c.glGetIntegerv(c.GL_MAX_TEXTURE_SIZE, &max_texture_size);
        if (max_texture_size <= 0 or c.glGetError() != c.GL_NO_ERROR) return error.Texture;
        const atlas_extent: u16 = @intCast(@min(
            max_texture_size,
            @as(c.GLint, glyph_atlas_max_extent),
        ));
        std.debug.assert(
            @as(usize, atlas_extent) * atlas_extent * glyph_atlas_capacity <=
                glyph_atlas_byte_capacity,
        );
        var buffer: c.GLuint = 0;
        c.glGenBuffers(1, &buffer);
        if (buffer == 0 or c.glGetError() != c.GL_NO_ERROR) return error.Draw;
        errdefer c.glDeleteBuffers(1, &buffer);
        var white: c.GLuint = 0;
        c.glGenTextures(1, &white);
        if (white == 0) return error.Texture;
        errdefer c.glDeleteTextures(1, &white);
        const pixel = [_]u8{255};
        configureTexture(white);
        measure.State.textureBind(values.measurement);
        c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_ALPHA, 1, 1, 0, c.GL_ALPHA, c.GL_UNSIGNED_BYTE, &pixel);
        if (c.glGetError() != c.GL_NO_ERROR) return error.Texture;
        c.glEnable(c.GL_BLEND);
        c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
        if (c.glGetError() != c.GL_NO_ERROR) return error.Draw;
        c.glViewport(0, 0, @intCast(values.size.width), @intCast(values.size.height));
        const clear_component: f32 = @as(f32, @floatFromInt(clear_color.r)) / 255.0;
        c.glClearColor(clear_component, clear_component, clear_component, 1.0);
        c.glClear(c.GL_COLOR_BUFFER_BIT);
        if (c.glGetError() != c.GL_NO_ERROR) return error.Draw;
        // The first swap maps the Wayland surface before PTY construction, so
        // a tiling compositor can supply the child's initial grid. It is not a
        // terminal workload frame and remains outside `measure.State.frame`.
        if (c.eglSwapBuffers(display, surface) != c.EGL_TRUE) return error.Swap;
        return .{
            .allocator = allocator,
            .display = display,
            .context = context,
            .surface = surface,
            .window = window,
            .program = program,
            .texture_color_uniform = texture_color_uniform,
            .buffer = buffer,
            .white = white,
            .fonts = fonts,
            .run_scratch = run_scratch,
            .draw_batch = draw_batch,
            .metrics = metrics,
            .glyph_cache = .{ .extent = atlas_extent },
            .size = values.size,
            .io = io,
            .measurement = values.measurement,
        };
    }

    fn draw(self: *Device, snapshot: *const Snapshot) Error!void {
        const draw_started = measure.now(self.io);
        const work = snapshot.view();
        try self.syncImages(work);
        if (!std.meta.eql(self.size, work.size)) {
            try validateSize(work.size);
            c.wl_egl_window_resize(self.window, @intCast(work.size.width), @intCast(work.size.height), 0, 0);
            self.size = work.size;
        }
        c.glViewport(0, 0, @intCast(self.size.width), @intCast(self.size.height));
        const clear_component: f32 = @as(f32, @floatFromInt(clear_color.r)) / 255.0;
        c.glClearColor(clear_component, clear_component, clear_component, 1.0);
        c.glClear(c.GL_COLOR_BUFFER_BIT);
        c.glUseProgram(self.program);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, self.buffer);
        c.glEnableVertexAttribArray(0);
        c.glEnableVertexAttribArray(1);
        c.glEnableVertexAttribArray(2);
        for (0..work.rows) |row| try self.drawRowBackground(work, @intCast(row));
        try self.drawImages(work, .behind_text);
        for (0..work.rows) |row| try self.drawRowContent(work, @intCast(row));
        try self.drawImages(work, .above_text);
        try self.drawCursor(work);
        try self.drawScrollbar(work.scrollbar);
        try self.flush();
        if (c.glGetError() != c.GL_NO_ERROR) return error.Draw;
        const draw_ns = measure.elapsed(draw_started, self.io);
        const swap_started = measure.now(self.io);
        if (c.eglSwapBuffers(self.display, self.surface) != c.EGL_TRUE) return error.Swap;
        measure.State.frame(
            self.measurement,
            draw_ns,
            measure.elapsed(swap_started, self.io),
            measure.elapsed(snapshot.submitted_at, self.io),
        );
    }

    fn drawScrollbar(self: *Device, value: ?viewport.Scrollbar) Error!void {
        const scrollbar = value orelse return;
        try self.quad(
            .scrollbar,
            @intCast(scrollbar.track.x),
            @intCast(scrollbar.track.y),
            scrollbar.track.width,
            @intCast(scrollbar.track.height),
            .{ .r = 0x50, .g = 0x49, .b = 0x45 },
            self.white,
        );
        try self.quad(
            .scrollbar,
            @intCast(scrollbar.thumb.x),
            @intCast(scrollbar.thumb.y),
            scrollbar.thumb.width,
            @intCast(scrollbar.thumb.height),
            .{ .r = 0x92, .g = 0x83, .b = 0x74 },
            self.white,
        );
    }

    fn syncImages(self: *Device, work: Submission) Error!void {
        if (self.image_generation == work.image_content_generation) return;
        var required_bytes: usize = 0;
        for (work.images) |image| required_bytes += image.pixel_count;
        if (required_bytes > 64 * 1024 * 1024 or work.images.len > self.image_textures.len)
            return error.CacheFull;
        var admitted: [256]ImageTexture = undefined;
        var admitted_count: usize = 0;
        var admitted_owned = true;
        errdefer if (admitted_owned) for (admitted[0..admitted_count]) |created|
            c.glDeleteTextures(1, &created.name);
        for (work.images) |image| {
            var found = false;
            for (self.image_textures[0..self.image_texture_count]) |retained| {
                if (std.meta.eql(retained.identity, image.identity)) {
                    found = true;
                    break;
                }
            }
            if (found) continue;
            if (image.pixel_offset > work.image_pixels.len or
                image.pixel_count > work.image_pixels.len - image.pixel_offset)
                return error.InvalidSubmission;
            var name: c.GLuint = 0;
            c.glGenTextures(1, &name);
            if (name == 0) return error.Texture;
            errdefer c.glDeleteTextures(1, &name);
            configureRgbaTexture(name);
            measure.State.textureBind(self.measurement);
            c.glTexImage2D(
                c.GL_TEXTURE_2D,
                0,
                c.GL_RGBA,
                @intCast(image.width),
                @intCast(image.height),
                0,
                c.GL_RGBA,
                c.GL_UNSIGNED_BYTE,
                work.image_pixels.ptr + image.pixel_offset,
            );
            if (c.glGetError() != c.GL_NO_ERROR) return error.Texture;
            measure.State.imageUpload(self.measurement, image.pixel_count);
            admitted[admitted_count] = .{
                .identity = image.identity,
                .name = name,
                .width = image.width,
                .height = image.height,
            };
            admitted_count += 1;
        }
        var index: usize = 0;
        while (index < self.image_texture_count) {
            const retained = self.image_textures[index];
            var found = false;
            for (work.images) |image| {
                if (std.meta.eql(retained.identity, image.identity)) {
                    found = true;
                    break;
                }
            }
            if (found) {
                index += 1;
                continue;
            }
            c.glDeleteTextures(1, &retained.name);
            self.image_texture_count -= 1;
            if (index != self.image_texture_count)
                self.image_textures[index] = self.image_textures[self.image_texture_count];
        }
        @memcpy(
            self.image_textures[self.image_texture_count..][0..admitted_count],
            admitted[0..admitted_count],
        );
        self.image_texture_count += admitted_count;
        self.image_texture_bytes = required_bytes;
        admitted_owned = false;
        self.image_generation = work.image_content_generation;
    }

    const ImageLayer = enum { behind_text, above_text };

    fn drawImages(self: *Device, work: Submission, layer: ImageLayer) Error!void {
        for (work.image_placements) |placement| {
            if (imageLayer(placement.z) != layer) continue;
            const image = for (self.image_textures[0..self.image_texture_count]) |*candidate| {
                if (candidate.identity.id == placement.image_id) break candidate;
            } else continue;
            if (placement.source_width == 0 or placement.source_height == 0 or
                placement.pixel_width == 0 or placement.pixel_height == 0 or
                placement.source_x > image.width -| placement.source_width or
                placement.source_y > image.height -| placement.source_height)
                return error.InvalidSubmission;
            const x64 = @as(u64, placement.col) * self.metrics.width_px + placement.cell_x;
            const y64 = @as(u64, placement.row) * self.metrics.height_px + placement.cell_y;
            if (x64 > std.math.maxInt(i32) or y64 > std.math.maxInt(i32))
                return error.InvalidSubmission;
            const clip = clipToSurface(.{
                .x = @intCast(x64),
                .y = @intCast(y64),
                .width = placement.pixel_width,
                .height = placement.pixel_height,
            }, self.size) orelse continue;
            const vertices = imageVertices(
                @intCast(x64),
                @intCast(y64),
                placement.pixel_width,
                placement.pixel_height,
                self.size,
                placement,
                image.width,
                image.height,
            );
            try self.stage(.image, vertices, .{
                .texture = image.name,
                .texture_color = true,
                .scissor = clip,
            });
        }
    }

    fn drawRowBackground(self: *Device, work: Submission, row: u16) Error!void {
        const geometry = work.row_geometry[row];
        const logical_cols = rowColumns(geometry, work.cols);
        measure.State.visitRow(self.measurement, logical_cols);
        var spans = BackgroundSpans{
            .work = work,
            .row = row,
            .metrics = self.metrics,
            .logical_cols = logical_cols,
        };
        while (try spans.next()) |span| {
            try self.quad(
                .background,
                span.rect.x,
                span.rect.y,
                span.rect.width,
                span.rect.height,
                span.color,
                self.white,
            );
        }
    }

    fn drawRowContent(self: *Device, work: Submission, row: u16) Error!void {
        const start = @as(usize, row) * work.cols;
        const cells = work.cells[start..][0..work.cols];
        const geometry = work.row_geometry[row];
        const logical_cols = rowColumns(geometry, work.cols);
        var at: u16 = 0;
        while (at < logical_cols) {
            const prepare_started = measure.now(self.io);
            const prepared = try text.prepareNextRun(&self.fonts, .{
                .cells = cells[0..logical_cols],
                .affected_start = at,
                .affected_end = logical_cols - 1,
                .geometry = geometry,
                .metrics = self.metrics,
            }, at, self.run_scratch.borrow());
            const glyph_count: usize = switch (prepared.glyphs) {
                .none => 0,
                .generated => 1,
                .native => |glyphs| glyphs.len,
            };
            measure.State.prepared(
                self.measurement,
                switch (prepared.glyphs) {
                    .none => .empty,
                    .generated => .generated,
                    .native => .native,
                },
                glyph_count,
                measure.elapsed(prepare_started, self.io),
            );
            try self.drawPrepared(work, row, cells, prepared);
            std.debug.assert(prepared.end_cell > at);
            at = prepared.end_cell;
        }
        try self.drawDecorations(row, cells[0..logical_cols], geometry);
    }

    fn drawPrepared(
        self: *Device,
        work: Submission,
        row: u16,
        cells: []const terminal.Cell,
        prepared: text.PreparedRun,
    ) Error!void {
        switch (prepared.glyphs) {
            .none => {},
            .generated => |glyph| try self.drawGlyph(work, row, cells, prepared, glyph),
            .native => |glyphs| for (glyphs) |glyph|
                try self.drawGlyph(work, row, cells, prepared, glyph),
        }
    }

    fn drawGlyph(
        self: *Device,
        work: Submission,
        row: u16,
        cells: []const terminal.Cell,
        prepared: text.PreparedRun,
        glyph: text.PositionedGlyph,
    ) Error!void {
        std.debug.assert(glyph.source_start < glyph.source_end and glyph.source_end <= cells.len);
        const cached = try self.texture(work.generation, glyph.key);
        if (cached.width == 0 or cached.height == 0) return;
        const atlas = self.glyph_cache.atlases[cached.atlas.?];
        const texture_uv = glyphUv(cached.*, self.glyph_cache.extent);
        const base_x = glyphPixelX(
            prepared.first_cell,
            self.metrics.width_px,
            cached.left,
            glyph.x_26_6,
        );
        const base_y = @as(i32, self.metrics.baseline_px) -
            cached.top - @divTrunc(glyph.y_26_6, 64);
        const rect = planContent(
            row,
            glyph.source_start,
            prepared.geometry,
            prepared.baseline,
            self.metrics,
            planTextSizing(prepared.first_cell, prepared.sizing, self.metrics, .{
                .x = base_x,
                .y = base_y,
                .width = cached.width,
                .height = cached.height,
            }) orelse return error.InvalidSubmission,
        ) orelse return error.InvalidSubmission;
        const cursor_block = cursorBlockCovers(work, row, prepared.first_cell);
        if (prepared.sizing.width > 1 or prepared.sizing.height > 1) {
            const clip = clipToSurface(
                clusterCellRect(
                    row,
                    prepared.first_cell,
                    prepared.geometry,
                    prepared.sizing,
                    self.metrics,
                ) orelse return error.InvalidSubmission,
                self.size,
            ) orelse return;
            try self.quadClipped(
                .text,
                rect.x,
                rect.y,
                rect.width,
                rect.height,
                glyphColor(cells[glyph.source_start], work.cursor, cursor_block),
                atlas.name,
                texture_uv,
                clip,
            );
            return;
        }
        var col = glyph.source_start;
        while (col < glyph.source_end) : (col += 1) {
            const clip = clipToSurface(
                planCell(row, col, prepared.geometry, self.metrics) orelse
                    return error.InvalidSubmission,
                self.size,
            ) orelse continue;
            try self.quadClipped(
                .text,
                rect.x,
                rect.y,
                rect.width,
                rect.height,
                glyphColor(cells[col], work.cursor, cursorBlockCovers(work, row, col)),
                atlas.name,
                texture_uv,
                clip,
            );
        }
    }

    fn drawDecorations(
        self: *Device,
        row: u16,
        cells: []const terminal.Cell,
        geometry: terminal.LineGeometry,
    ) Error!void {
        for (cells, 0..) |cell, col_usize| {
            if (cell.sizing.x != 0 or cell.sizing.y != 0) continue;
            if (!cell.strikethrough and !cell.underline) continue;
            const col: u16 = @intCast(col_usize);
            const decorations = self.fonts.decorationMetrics(cellFontKey(cell)) orelse
                return error.MissingFontConfiguration;
            if (cell.strikethrough) try self.drawDecoration(
                row,
                col,
                geometry,
                cell.baseline,
                cell.sizing,
                decorations.strike_y,
                decorations.strike_height,
                .single,
                cell.foreground,
            );
            if (cell.underline) try self.drawDecoration(
                row,
                col,
                geometry,
                cell.baseline,
                cell.sizing,
                decorations.underline_y,
                decorations.underline_height,
                cell.underline_style,
                cell.underline_color,
            );
        }
    }

    fn drawDecoration(
        self: *Device,
        row: u16,
        col: u16,
        geometry: terminal.LineGeometry,
        baseline: terminal.CellBaseline,
        sizing: terminal.TextSizing,
        y: u16,
        height: u16,
        style: terminal.UnderlineStyle,
        color: terminal.Rgb,
    ) Error!void {
        const clip = clipToSurface(
            clusterCellRect(row, col, geometry, sizing, self.metrics) orelse
                return error.InvalidSubmission,
            self.size,
        ) orelse return;
        const base = PixelRect{
            .x = @as(i32, col) * self.metrics.width_px,
            .y = y,
            .width = std.math.cast(u16, @as(u32, self.metrics.width_px) * sizing.width) orelse
                return error.InvalidSubmission,
            .height = height,
        };
        switch (style) {
            .none => {},
            .single => try self.drawDecorationRect(
                row,
                col,
                geometry,
                baseline,
                sizing,
                base,
                color,
                clip,
            ),
            .double => {
                const upper_y = y -| (height + 1);
                var upper = base;
                upper.y = upper_y;
                try self.drawDecorationRect(
                    row,
                    col,
                    geometry,
                    baseline,
                    sizing,
                    upper,
                    color,
                    clip,
                );
                try self.drawDecorationRect(
                    row,
                    col,
                    geometry,
                    baseline,
                    sizing,
                    base,
                    color,
                    clip,
                );
            },
            .curly, .dotted, .dashed => {
                const unit = @max(@as(u16, 1), height);
                var x: u16 = 0;
                while (x < base.width) : (x += 1) {
                    const rise = decorationRise(style, x, unit) orelse continue;
                    var segment = base;
                    segment.x += x;
                    segment.width = 1;
                    segment.y -|= @min(segment.y, rise);
                    try self.drawDecorationRect(
                        row,
                        col,
                        geometry,
                        baseline,
                        sizing,
                        segment,
                        color,
                        clip,
                    );
                }
            },
        }
    }

    fn drawDecorationRect(
        self: *Device,
        row: u16,
        col: u16,
        geometry: terminal.LineGeometry,
        baseline: terminal.CellBaseline,
        sizing: terminal.TextSizing,
        base: PixelRect,
        color: terminal.Rgb,
        clip: PixelRect,
    ) Error!void {
        const sized = planTextSizing(col, sizing, self.metrics, base) orelse
            return error.InvalidSubmission;
        const rect = planContent(row, col, geometry, baseline, self.metrics, sized) orelse
            return error.InvalidSubmission;
        try self.quadClipped(
            .decoration,
            rect.x,
            rect.y,
            rect.width,
            rect.height,
            color,
            self.white,
            .{},
            clip,
        );
    }

    fn drawCursor(self: *Device, work: Submission) Error!void {
        if (!work.cursor.visible or work.cursor.shape == .block) return;
        std.debug.assert(work.cursor.row < work.rows and work.cursor.col < work.cols);
        const cursor_cell = work.cells[@as(usize, work.cursor.row) * work.cols + work.cursor.col];
        const anchor_row = work.cursor.row -| cursor_cell.sizing.y;
        const anchor_col = work.cursor.col -| cursor_cell.sizing.x;
        const width: u16 = switch (work.cursor.shape) {
            .bar => @max(1, self.metrics.width_px / 8),
            else => std.math.cast(
                u16,
                @as(u32, self.metrics.width_px) * cursor_cell.sizing.width,
            ) orelse return error.InvalidSubmission,
        };
        const height: u16 = switch (work.cursor.shape) {
            .underline => @max(1, self.metrics.height_px / 8),
            .none => return,
            else => std.math.cast(
                u16,
                @as(u32, self.metrics.height_px) * cursor_cell.sizing.height,
            ) orelse return error.InvalidSubmission,
        };
        const cluster_height = @as(u32, self.metrics.height_px) * cursor_cell.sizing.height;
        const y_offset: u16 = if (work.cursor.shape == .underline)
            std.math.cast(u16, cluster_height - height) orelse return error.InvalidSubmission
        else
            0;
        const geometry = work.row_geometry[anchor_row];
        const rect = planContent(
            anchor_row,
            anchor_col,
            geometry,
            .normal,
            self.metrics,
            .{
                .x = @as(i32, anchor_col) * self.metrics.width_px,
                .y = y_offset,
                .width = width,
                .height = height,
            },
        ) orelse return error.InvalidSubmission;
        var cluster = planCell(anchor_row, anchor_col, geometry, self.metrics) orelse
            return error.InvalidSubmission;
        const cluster_width = @as(u64, cluster.width) * cursor_cell.sizing.width;
        const cluster_height_u64 = @as(u64, cluster.height) * cursor_cell.sizing.height;
        if (cluster_width > std.math.maxInt(u32) or cluster_height_u64 > std.math.maxInt(u32))
            return error.InvalidSubmission;
        cluster.width = @intCast(cluster_width);
        cluster.height = @intCast(cluster_height_u64);
        const clip = clipToSurface(cluster, self.size) orelse return;
        try self.quadClipped(
            .cursor,
            rect.x,
            rect.y,
            rect.width,
            rect.height,
            work.cursor.color,
            self.white,
            .{},
            clip,
        );
    }

    fn texture(self: *Device, generation: u64, key: text.GlyphKey) Error!*Glyph {
        var comparisons: usize = 0;
        if (self.glyph_cache.find(key, &comparisons)) |entry| {
            entry.used = generation;
            measure.State.cache(self.measurement, comparisons, true);
            return entry;
        }
        measure.State.cache(self.measurement, comparisons, false);
        var raster = try text.rasterizeGlyph(self.allocator, &self.fonts, key);
        defer raster.deinit();
        if (raster.width == 0 or raster.height == 0) {
            const entry = self.glyph_cache.admitEmpty(key, raster, generation) orelse
                return error.CacheFull;
            measure.State.raster(self.measurement, raster.pixels.len, false);
            return entry;
        }
        if (raster.pixels.len != @as(usize, raster.width) * raster.height)
            return error.InvalidSubmission;
        const admission = self.glyph_cache.plan(raster.width, raster.height, generation) orelse
            return error.CacheFull;
        const name = switch (admission) {
            .existing => |value| blk: {
                const retained = self.glyph_cache.atlases[value.atlas].name;
                c.glBindTexture(c.GL_TEXTURE_2D, retained);
                measure.State.textureBind(self.measurement);
                c.glTexSubImage2D(
                    c.GL_TEXTURE_2D,
                    0,
                    value.rect.x,
                    value.rect.y,
                    value.rect.width,
                    value.rect.height,
                    c.GL_ALPHA,
                    c.GL_UNSIGNED_BYTE,
                    raster.pixels.ptr,
                );
                if (c.glGetError() != c.GL_NO_ERROR) return error.Texture;
                break :blk retained;
            },
            .grow => |rect| try self.createGlyphAtlas(rect, raster.pixels),
            .replace => |value| try self.createGlyphAtlas(value.rect, raster.pixels),
        };
        errdefer switch (admission) {
            .grow, .replace => c.glDeleteTextures(1, &name),
            .existing => {},
        };
        switch (admission) {
            .replace => |value| c.glDeleteTextures(
                1,
                &self.glyph_cache.atlases[value.atlas].name,
            ),
            else => {},
        }
        switch (admission) {
            .grow => measure.State.glyphAtlas(self.measurement, false),
            .replace => measure.State.glyphAtlas(self.measurement, true),
            .existing => {},
        }
        measure.State.raster(self.measurement, raster.pixels.len, true);
        return self.glyph_cache.admit(admission, name, key, raster, generation);
    }

    fn createGlyphAtlas(self: *Device, rect: AtlasRect, pixels: []const u8) Error!c.GLuint {
        var name: c.GLuint = 0;
        c.glGenTextures(1, &name);
        if (name == 0) return error.Texture;
        errdefer c.glDeleteTextures(1, &name);
        configureTexture(name);
        measure.State.textureBind(self.measurement);
        c.glTexImage2D(
            c.GL_TEXTURE_2D,
            0,
            c.GL_ALPHA,
            self.glyph_cache.extent,
            self.glyph_cache.extent,
            0,
            c.GL_ALPHA,
            c.GL_UNSIGNED_BYTE,
            null,
        );
        if (c.glGetError() != c.GL_NO_ERROR) return error.Texture;
        c.glTexSubImage2D(
            c.GL_TEXTURE_2D,
            0,
            rect.x,
            rect.y,
            rect.width,
            rect.height,
            c.GL_ALPHA,
            c.GL_UNSIGNED_BYTE,
            pixels.ptr,
        );
        if (c.glGetError() != c.GL_NO_ERROR) return error.Texture;
        return name;
    }

    fn quad(
        self: *Device,
        kind: measure.QuadKind,
        x: i32,
        y: i32,
        width: u32,
        height: u32,
        color: terminal.Rgb,
        texture_name: c.GLuint,
    ) Error!void {
        if (width == 0 or height == 0) return;
        try self.stage(kind, quadVertices(x, y, width, height, self.size, color), .{
            .texture = texture_name,
            .texture_color = false,
            .scissor = null,
        });
    }

    fn quadClipped(
        self: *Device,
        kind: measure.QuadKind,
        x: i32,
        y: i32,
        width: u32,
        height: u32,
        color: terminal.Rgb,
        texture_name: c.GLuint,
        texture_uv: TextureUv,
        clip: PixelRect,
    ) Error!void {
        if (width == 0 or height == 0) return;
        const clipped = clipQuad(
            .{ .x = x, .y = y, .width = width, .height = height },
            clip,
            self.size,
            color,
            texture_uv,
        ) orelse {
            measure.State.cpuClip(self.measurement, false, true);
            return;
        };
        measure.State.cpuClip(self.measurement, clipped.changed, false);
        try self.stage(kind, clipped.vertices, .{
            .texture = texture_name,
            .texture_color = false,
            .scissor = null,
        });
    }

    fn stage(
        self: *Device,
        kind: measure.QuadKind,
        vertices: [vertices_per_quad]Vertex,
        state: DrawState,
    ) Error!void {
        // Glyph eviction excludes the current render generation, and image
        // reconciliation finishes before drawing, so every deferred texture
        // name remains alive until this batch is flushed.
        if (!self.draw_batch.stage(vertices, state)) {
            try self.flush();
            if (!self.draw_batch.stage(vertices, state)) @panic("empty draw batch rejected one quad");
        }
        measure.State.stagedQuad(self.measurement, kind);
    }

    fn flush(self: *Device) Error!void {
        if (self.draw_batch.vertex_count == 0) return;
        defer self.draw_batch.reset();
        const vertex_bytes = std.math.mul(
            usize,
            self.draw_batch.vertex_count,
            @sizeOf(Vertex),
        ) catch return error.Draw;
        const gl_bytes = std.math.cast(c.GLsizeiptr, vertex_bytes) orelse return error.Draw;
        for (self.draw_batch.commands[0..self.draw_batch.command_count]) |command|
            if (!validDrawRange(command, self.draw_batch.vertex_count)) return error.Draw;
        c.glBufferData(
            c.GL_ARRAY_BUFFER,
            gl_bytes,
            self.draw_batch.vertices.ptr,
            c.GL_STREAM_DRAW,
        );
        c.glVertexAttribPointer(0, 2, c.GL_FLOAT, c.GL_FALSE, @sizeOf(Vertex), @ptrFromInt(0));
        c.glVertexAttribPointer(
            1,
            2,
            c.GL_FLOAT,
            c.GL_FALSE,
            @sizeOf(Vertex),
            @ptrFromInt(2 * @sizeOf(f32)),
        );
        c.glVertexAttribPointer(
            2,
            4,
            c.GL_FLOAT,
            c.GL_FALSE,
            @sizeOf(Vertex),
            @ptrFromInt(4 * @sizeOf(f32)),
        );
        var bound_texture: ?c.GLuint = null;
        var texture_color: ?bool = null;
        var scissor: ?PixelRect = null;
        var scissor_enabled = false;
        for (self.draw_batch.commands[0..self.draw_batch.command_count]) |command| {
            if (bound_texture == null or bound_texture.? != command.state.texture) {
                c.glBindTexture(c.GL_TEXTURE_2D, command.state.texture);
                measure.State.textureBind(self.measurement);
                bound_texture = command.state.texture;
            }
            if (texture_color == null or texture_color.? != command.state.texture_color) {
                c.glUniform1i(self.texture_color_uniform, @intFromBool(command.state.texture_color));
                texture_color = command.state.texture_color;
            }
            if (!std.meta.eql(scissor, command.state.scissor)) {
                if (command.state.scissor) |rect| {
                    if (!scissor_enabled) {
                        c.glEnable(c.GL_SCISSOR_TEST);
                        scissor_enabled = true;
                    }
                    setScissor(rect, self.size);
                } else if (scissor_enabled) {
                    c.glDisable(c.GL_SCISSOR_TEST);
                    scissor_enabled = false;
                }
                scissor = command.state.scissor;
            }
            const first: c.GLint = @intCast(command.first);
            const count: c.GLsizei = @intCast(command.count);
            c.glDrawArrays(c.GL_TRIANGLES, first, count);
        }
        if (scissor_enabled) c.glDisable(c.GL_SCISSOR_TEST);
        const quad_count = self.draw_batch.vertex_count / vertices_per_quad;
        std.debug.assert(self.draw_batch.command_count <= quad_count);
        measure.State.batch(
            self.measurement,
            self.draw_batch.command_count,
            quad_count - self.draw_batch.command_count,
            vertex_bytes,
        );
        if (c.glGetError() != c.GL_NO_ERROR) return error.Draw;
    }

    fn deinit(self: *Device) Error!void {
        while (self.image_texture_count != 0) {
            self.image_texture_count -= 1;
            self.image_texture_bytes -= @as(usize, self.image_textures[self.image_texture_count].width) *
                self.image_textures[self.image_texture_count].height * 4;
            c.glDeleteTextures(1, &self.image_textures[self.image_texture_count].name);
        }
        while (self.glyph_cache.atlas_count != 0) {
            self.glyph_cache.atlas_count -= 1;
            c.glDeleteTextures(1, &self.glyph_cache.atlases[self.glyph_cache.atlas_count].name);
        }
        self.draw_batch.deinit();
        self.run_scratch.deinit();
        self.fonts.deinit();
        c.glDeleteTextures(1, &self.white);
        c.glDeleteBuffers(1, &self.buffer);
        c.glDeleteProgram(self.program);
        var failed = c.glGetError() != c.GL_NO_ERROR;
        if (c.eglMakeCurrent(self.display, c.EGL_NO_SURFACE, c.EGL_NO_SURFACE, c.EGL_NO_CONTEXT) != c.EGL_TRUE)
            failed = true;
        if (c.eglDestroySurface(self.display, self.surface) != c.EGL_TRUE) failed = true;
        if (c.eglDestroyContext(self.display, self.context) != c.EGL_TRUE) failed = true;
        if (c.eglTerminate(self.display) != c.EGL_TRUE) failed = true;
        c.wl_egl_window_destroy(self.window);
        self.* = undefined;
        if (failed) return error.Cleanup;
    }
};

/// Owns two bounded visual snapshots, one render thread, fonts, and GLES state.
pub const Renderer = struct {
    /// Retains the caller allocator through renderer cleanup.
    allocator: std.mem.Allocator,
    /// Retains the process I/O implementation used by mutexes and conditions.
    io: std.Io,
    /// Serializes bounded snapshot admission and completion facts.
    mutex: std.Io.Mutex = .init,
    /// Wakes the renderer for work and startup/shutdown transitions.
    condition: std.Io.Condition = .init,
    /// Owns the sole EGL/GLES device thread until deinit joins it.
    thread: std.Thread,
    /// Signals coalesced draw completion or failure to the Wayland loop.
    signal_fd: c_int,
    /// Borrows native startup values only until `start` returns.
    init_values: Init,
    /// Owns exactly two independently growable immutable snapshots.
    slots: [2]Snapshot,
    /// Tracks free, pending, and active snapshot ownership.
    mailbox: Mailbox,
    /// Revokes new work and asks the render thread to exit.
    stopping: bool = false,
    /// Reports completion of synchronous device construction.
    started: bool = false,
    /// Retains exact device construction failure until `start` observes it.
    startup_failure: ?Error = null,
    /// Retains the first draw or cleanup failure.
    failure: ?Error = null,
    /// Identifies the newest accepted generation.
    submitted: u64 = 0,
    /// Identifies the newest swapped generation.
    completed: u64 = 0,
    /// Copies immutable cell metrics established during startup.
    metrics_value: text.CellMetrics = undefined,

    /// Allocates two geometry-sized snapshots and starts the sole EGL/GLES owner.
    pub fn start(allocator: std.mem.Allocator, io: std.Io, values: Init) Error!*Renderer {
        try validateInit(values);
        const self = try allocator.create(Renderer);
        errdefer allocator.destroy(self);
        const signal_fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
        if (signal_fd < 0) return error.Signal;
        errdefer closeSignal(signal_fd);
        var first = try Snapshot.init(allocator, values.rows, values.cols);
        var first_owned = true;
        errdefer if (first_owned) first.deinit();
        var second = try Snapshot.init(allocator, values.rows, values.cols);
        var second_owned = true;
        errdefer if (second_owned) second.deinit();
        self.* = .{
            .allocator = allocator,
            .io = io,
            .thread = undefined,
            .signal_fd = signal_fd,
            .init_values = values,
            .slots = .{ first, second },
            .mailbox = .{
                .free_first = &self.slots[0],
                .free_second = &self.slots[1],
            },
        };
        first_owned = false;
        second_owned = false;
        var snapshots_owned_by_thread_owner = true;
        errdefer if (snapshots_owned_by_thread_owner) {
            self.slots[1].deinit();
            self.slots[0].deinit();
        };
        self.thread = try .spawn(.{}, threadMain, .{self});
        snapshots_owned_by_thread_owner = false;
        self.mutex.lockUncancelable(io);
        while (!self.started) self.condition.waitUncancelable(io, &self.mutex);
        const failure = self.startup_failure;
        self.init_values.fonts = &.{};
        self.mutex.unlock(io);
        if (failure) |cause| {
            self.thread.join();
            self.slots[1].deinit();
            self.slots[0].deinit();
            return cause;
        }
        return self;
    }

    /// Copies and coalesces one complete visual state without waiting for draw.
    pub fn submit(self: *Renderer, submission: Submission) Error!void {
        try validateSubmission(submission);
        const submitted_at = measure.now(self.io);
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.failure) |failure| return failure;
        if (self.stopping) return error.Stopping;
        if (submission.generation <= self.submitted) return error.StaleGeneration;
        const coalesced = self.mailbox.pending != null;
        try self.mailbox.write(submission, submitted_at);
        measure.State.snapshot(
            self.init_values.measurement,
            submission.rows,
            @as(usize, submission.rows) * submission.cols,
            coalesced,
        );
        self.submitted = submission.generation;
        self.condition.signal(self.io);
    }

    /// Returns the immutable cell metrics established during synchronous startup.
    pub fn metrics(self: *const Renderer) text.CellMetrics {
        return self.metrics_value;
    }

    /// Exposes the pollable completion/failure descriptor until deinit.
    pub fn signalFd(self: *const Renderer) c_int {
        return self.signal_fd;
    }

    /// Drains coalesced completion signals and reports the newest swapped generation.
    pub fn completedGeneration(self: *Renderer) Error!u64 {
        try drainSignal(self.signal_fd);
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.failure) |failure| return failure;
        return self.completed;
    }

    /// Revokes submission, joins the thread, and releases every owner.
    pub fn deinit(self: *Renderer) Error!void {
        self.mutex.lockUncancelable(self.io);
        self.stopping = true;
        self.condition.broadcast(self.io);
        self.mutex.unlock(self.io);
        self.thread.join();
        const failure = self.failure;
        self.slots[1].deinit();
        self.slots[0].deinit();
        closeSignal(self.signal_fd);
        const allocator = self.allocator;
        allocator.destroy(self);
        if (failure) |cause| return cause;
    }

    fn threadMain(self: *Renderer) void {
        var device = Device.init(self.allocator, self.io, self.init_values) catch |failure| {
            self.mutex.lockUncancelable(self.io);
            self.startup_failure = failure;
            self.started = true;
            self.condition.broadcast(self.io);
            self.mutex.unlock(self.io);
            return;
        };
        self.mutex.lockUncancelable(self.io);
        self.metrics_value = device.metrics;
        self.started = true;
        self.condition.broadcast(self.io);
        self.mutex.unlock(self.io);

        while (true) {
            self.mutex.lockUncancelable(self.io);
            while (self.mailbox.pending == null and !self.stopping)
                self.condition.waitUncancelable(self.io, &self.mutex);
            if (self.stopping) {
                self.mutex.unlock(self.io);
                break;
            }
            const slot = self.mailbox.take().?;
            self.mutex.unlock(self.io);

            device.draw(slot) catch |failure| {
                self.mutex.lockUncancelable(self.io);
                self.failure = failure;
                self.mailbox.complete();
                self.condition.broadcast(self.io);
                self.mutex.unlock(self.io);
                signal(self.signal_fd);
                break;
            };
            self.mutex.lockUncancelable(self.io);
            self.completed = slot.generation;
            self.mailbox.complete();
            self.condition.broadcast(self.io);
            self.mutex.unlock(self.io);
            signal(self.signal_fd);
        }
        device.deinit() catch |failure| {
            self.mutex.lockUncancelable(self.io);
            if (self.failure) |prior| {
                if (prior != failure) @panic("device cleanup failed after distinct render failure");
            } else {
                self.failure = failure;
            }
            self.condition.broadcast(self.io);
            self.mutex.unlock(self.io);
            signal(self.signal_fd);
        };
    }
};

fn validateInit(values: Init) error{ InvalidSubmission, MissingDefaultConfiguration }!void {
    try validateSize(values.size);
    if (values.rows == 0 or values.cols == 0 or values.rows > max_dimension or
        values.cols > max_dimension or @as(usize, values.rows) * values.cols > max_cells)
        return error.InvalidSubmission;
    if (values.fonts.len == 0) return error.MissingDefaultConfiguration;
}

fn validateSize(size: PixelSize) error{InvalidSubmission}!void {
    if (size.width == 0 or size.height == 0 or
        size.width > std.math.maxInt(c_int) or size.height > std.math.maxInt(c_int))
        return error.InvalidSubmission;
}

fn validateSubmission(value: Submission) error{InvalidSubmission}!void {
    try validateSize(value.size);
    if (value.generation == 0 or value.rows == 0 or value.cols == 0 or
        value.rows > max_dimension or value.cols > max_dimension)
        return error.InvalidSubmission;
    const count = @as(usize, value.rows) * value.cols;
    if (count > max_cells or value.cells.len != count or value.row_geometry.len != value.rows)
        return error.InvalidSubmission;
    if (value.cursor.visible and
        (value.cursor.row >= value.rows or value.cursor.col >= value.cols))
        return error.InvalidSubmission;
    if (value.scrollbar) |scrollbar| {
        if (!validRect(scrollbar.track, value.size) or
            !validRect(scrollbar.thumb, value.size) or
            scrollbar.thumb.x != scrollbar.track.x or
            scrollbar.thumb.width != scrollbar.track.width or
            scrollbar.thumb.y < scrollbar.track.y or
            @as(u64, scrollbar.thumb.y) + scrollbar.thumb.height >
                @as(u64, scrollbar.track.y) + scrollbar.track.height or
            scrollbar.history_count == 0 or scrollbar.offset > scrollbar.history_count)
            return error.InvalidSubmission;
    }
    if (value.images.len > 256 or value.image_placements.len > 1024 or
        value.image_pixels.len > 64 * 1024 * 1024)
        return error.InvalidSubmission;
    for (value.images) |image| {
        if (image.identity.id == 0 or image.width == 0 or image.height == 0 or
            image.width > 4096 or image.height > 4096 or
            image.pixel_count != @as(usize, image.width) * image.height * 4 or
            image.pixel_offset > value.image_pixels.len or
            image.pixel_count > value.image_pixels.len - image.pixel_offset)
            return error.InvalidSubmission;
    }
    for (value.image_placements) |placement| {
        if (placement.row >= value.rows or placement.col >= value.cols)
            return error.InvalidSubmission;
        var found = false;
        for (value.images) |image| if (image.identity.id == placement.image_id) {
            found = true;
            break;
        };
        if (!found) return error.InvalidSubmission;
    }
}

fn validRect(rect: viewport.Rect, size: PixelSize) bool {
    return rect.width != 0 and rect.height != 0 and
        @as(u64, rect.x) + rect.width <= size.width and
        @as(u64, rect.y) + rect.height <= size.height;
}

fn signal(fd: c_int) void {
    const value: u64 = 1;
    while (true) {
        const count = c.write(fd, &value, @sizeOf(u64));
        if (count == @sizeOf(u64) or (count < 0 and std.posix.errno(count) == .AGAIN)) return;
        if (count < 0 and std.posix.errno(count) == .INTR) continue;
        @panic("render completion signal failed");
    }
}

fn drainSignal(fd: c_int) error{Signal}!void {
    while (true) {
        var value: u64 = 0;
        const count = c.read(fd, &value, @sizeOf(u64));
        if (count == @sizeOf(u64)) continue;
        if (count < 0 and std.posix.errno(count) == .INTR) continue;
        if (count < 0 and std.posix.errno(count) == .AGAIN) return;
        return error.Signal;
    }
}

fn closeSignal(fd: c_int) void {
    const result = c.close(fd);
    if (result != 0 and std.posix.errno(result) != .INTR)
        @panic("render completion descriptor close failed");
}

fn createProgram() Error!c.GLuint {
    const vertex_source: [:0]const u8 =
        \\attribute vec2 position;
        \\attribute vec2 texture_coordinate;
        \\attribute vec4 color;
        \\varying vec2 texture_coordinate_out;
        \\varying vec4 color_out;
        \\void main() {
        \\  gl_Position = vec4(position, 0.0, 1.0);
        \\  texture_coordinate_out = texture_coordinate;
        \\  color_out = color;
        \\}
    ;
    const fragment_source: [:0]const u8 =
        \\precision mediump float;
        \\uniform sampler2D image;
        \\uniform bool texture_color;
        \\varying vec2 texture_coordinate_out;
        \\varying vec4 color_out;
        \\void main() {
        \\  vec4 sample = texture2D(image, texture_coordinate_out);
        \\  gl_FragColor = texture_color ? sample : vec4(color_out.rgb, color_out.a * sample.a);
        \\}
    ;
    const vertex = try compileShader(c.GL_VERTEX_SHADER, vertex_source);
    defer c.glDeleteShader(vertex);
    const fragment = try compileShader(c.GL_FRAGMENT_SHADER, fragment_source);
    defer c.glDeleteShader(fragment);
    const program = c.glCreateProgram();
    if (program == 0) return error.Shader;
    errdefer c.glDeleteProgram(program);
    c.glAttachShader(program, vertex);
    c.glAttachShader(program, fragment);
    c.glBindAttribLocation(program, 0, "position");
    c.glBindAttribLocation(program, 1, "texture_coordinate");
    c.glBindAttribLocation(program, 2, "color");
    c.glLinkProgram(program);
    var linked: c.GLint = 0;
    c.glGetProgramiv(program, c.GL_LINK_STATUS, &linked);
    if (linked != c.GL_TRUE) return error.Shader;
    c.glUseProgram(program);
    const image = c.glGetUniformLocation(program, "image");
    if (image < 0) return error.Shader;
    c.glUniform1i(image, 0);
    if (c.glGetError() != c.GL_NO_ERROR) return error.Shader;
    return program;
}

fn compileShader(kind: c.GLenum, source: [:0]const u8) Error!c.GLuint {
    const shader = c.glCreateShader(kind);
    if (shader == 0) return error.Shader;
    errdefer c.glDeleteShader(shader);
    const pointer: [*c]const c.GLchar = source.ptr;
    c.glShaderSource(shader, 1, &pointer, null);
    c.glCompileShader(shader);
    var compiled: c.GLint = 0;
    c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &compiled);
    if (compiled != c.GL_TRUE) return error.Shader;
    return shader;
}

fn configureTexture(name: c.GLuint) void {
    c.glBindTexture(c.GL_TEXTURE_2D, name);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
    c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1);
}

fn configureRgbaTexture(name: c.GLuint) void {
    c.glBindTexture(c.GL_TEXTURE_2D, name);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
}

fn pixelToNdc(value: i64, extent: u32) f32 {
    return @as(f32, @floatFromInt(value)) * 2.0 / @as(f32, @floatFromInt(extent)) - 1.0;
}

fn quadVertices(
    x: i32,
    y: i32,
    width: u32,
    height: u32,
    size: PixelSize,
    color: terminal.Rgb,
) [6]Vertex {
    return quadUvVertices(x, y, width, height, size, color, 0, 0, 1, 1);
}

fn quadUvVertices(
    x: i32,
    y: i32,
    width: u32,
    height: u32,
    size: PixelSize,
    color: terminal.Rgb,
    texture_left: f32,
    texture_top: f32,
    texture_right: f32,
    texture_bottom: f32,
) [6]Vertex {
    std.debug.assert(width != 0 and height != 0);
    std.debug.assert(texture_left >= 0 and texture_left <= texture_right and texture_right <= 1);
    std.debug.assert(texture_top >= 0 and texture_top <= texture_bottom and texture_bottom <= 1);
    const left = pixelToNdc(x, size.width);
    const right = pixelToNdc(@as(i64, x) + width, size.width);
    const top = -pixelToNdc(y, size.height);
    const bottom = -pixelToNdc(@as(i64, y) + height, size.height);
    const red = @as(f32, @floatFromInt(color.r)) / 255.0;
    const green = @as(f32, @floatFromInt(color.g)) / 255.0;
    const blue = @as(f32, @floatFromInt(color.b)) / 255.0;
    return .{
        .{ .x = left, .y = top, .u = texture_left, .v = texture_top, .r = red, .g = green, .b = blue, .a = 1 },
        .{ .x = right, .y = bottom, .u = texture_right, .v = texture_bottom, .r = red, .g = green, .b = blue, .a = 1 },
        .{ .x = left, .y = bottom, .u = texture_left, .v = texture_bottom, .r = red, .g = green, .b = blue, .a = 1 },
        .{ .x = left, .y = top, .u = texture_left, .v = texture_top, .r = red, .g = green, .b = blue, .a = 1 },
        .{ .x = right, .y = top, .u = texture_right, .v = texture_top, .r = red, .g = green, .b = blue, .a = 1 },
        .{ .x = right, .y = bottom, .u = texture_right, .v = texture_bottom, .r = red, .g = green, .b = blue, .a = 1 },
    };
}

const ClippedQuad = struct {
    vertices: [vertices_per_quad]Vertex,
    changed: bool,
};

fn clipQuad(
    rect: PixelRect,
    clip: PixelRect,
    size: PixelSize,
    color: terminal.Rgb,
    texture_uv: TextureUv,
) ?ClippedQuad {
    std.debug.assert(rect.width != 0 and rect.height != 0);
    const visible = intersectRect(rect, clip) orelse return null;
    const left: u32 = @intCast(@as(i64, visible.x) - rect.x);
    const top: u32 = @intCast(@as(i64, visible.y) - rect.y);
    const right = left + visible.width;
    const bottom = top + visible.height;
    std.debug.assert(right <= rect.width and bottom <= rect.height);
    const width_f: f32 = @floatFromInt(rect.width);
    const height_f: f32 = @floatFromInt(rect.height);
    const texture_width = texture_uv.right - texture_uv.left;
    const texture_height = texture_uv.bottom - texture_uv.top;
    return .{
        .vertices = quadUvVertices(
            visible.x,
            visible.y,
            visible.width,
            visible.height,
            size,
            color,
            texture_uv.left + @as(f32, @floatFromInt(left)) / width_f * texture_width,
            texture_uv.top + @as(f32, @floatFromInt(top)) / height_f * texture_height,
            texture_uv.left + @as(f32, @floatFromInt(right)) / width_f * texture_width,
            texture_uv.top + @as(f32, @floatFromInt(bottom)) / height_f * texture_height,
        ),
        .changed = !std.meta.eql(rect, visible),
    };
}

fn imageVertices(
    x: i32,
    y: i32,
    width: u32,
    height: u32,
    size: PixelSize,
    placement: terminal.ImagePlacement,
    image_width: u32,
    image_height: u32,
) [6]Vertex {
    const left = pixelToNdc(x, size.width);
    const right = pixelToNdc(@as(i64, x) + width, size.width);
    const top = -pixelToNdc(y, size.height);
    const bottom = -pixelToNdc(@as(i64, y) + height, size.height);
    const texture_left = @as(f32, @floatFromInt(placement.source_x)) / @as(f32, @floatFromInt(image_width));
    const texture_top = @as(f32, @floatFromInt(placement.source_y)) / @as(f32, @floatFromInt(image_height));
    const texture_right = @as(f32, @floatFromInt(placement.source_x + placement.source_width)) /
        @as(f32, @floatFromInt(image_width));
    const texture_bottom = @as(f32, @floatFromInt(placement.source_y + placement.source_height)) /
        @as(f32, @floatFromInt(image_height));
    return .{
        .{ .x = left, .y = top, .u = texture_left, .v = texture_top, .r = 1, .g = 1, .b = 1, .a = 1 },
        .{ .x = right, .y = bottom, .u = texture_right, .v = texture_bottom, .r = 1, .g = 1, .b = 1, .a = 1 },
        .{ .x = left, .y = bottom, .u = texture_left, .v = texture_bottom, .r = 1, .g = 1, .b = 1, .a = 1 },
        .{ .x = left, .y = top, .u = texture_left, .v = texture_top, .r = 1, .g = 1, .b = 1, .a = 1 },
        .{ .x = right, .y = top, .u = texture_right, .v = texture_top, .r = 1, .g = 1, .b = 1, .a = 1 },
        .{ .x = right, .y = bottom, .u = texture_right, .v = texture_bottom, .r = 1, .g = 1, .b = 1, .a = 1 },
    };
}

fn lineScale(geometry: terminal.LineGeometry) Scale {
    // DEC double-height rows share one 2x canvas; the bottom row shifts that
    // canvas up before both halves are clipped to their physical row.
    return switch (geometry) {
        .single_width => .{ .x = 1, .y = 1, .y_offset_cells = 0 },
        .double_width => .{ .x = 2, .y = 1, .y_offset_cells = 0 },
        .double_height_top => .{ .x = 2, .y = 2, .y_offset_cells = 0 },
        .double_height_bottom => .{ .x = 2, .y = 2, .y_offset_cells = -1 },
    };
}

fn rowColumns(geometry: terminal.LineGeometry, cols: u16) u16 {
    return switch (geometry) {
        .single_width => cols,
        else => @max(1, cols / 2),
    };
}

fn planCell(
    row: u16,
    col: u16,
    geometry: terminal.LineGeometry,
    metrics: text.CellMetrics,
) ?PixelRect {
    const scale = lineScale(geometry);
    const x = @as(u64, col) * metrics.width_px * scale.x;
    const y = @as(u64, row) * metrics.height_px;
    const width = @as(u32, metrics.width_px) * scale.x;
    if (x > std.math.maxInt(i32) or y > std.math.maxInt(i32)) return null;
    return .{
        .x = @intCast(x),
        .y = @intCast(y),
        .width = width,
        .height = metrics.height_px,
    };
}

fn clusterCellRect(
    row: u16,
    col: u16,
    geometry: terminal.LineGeometry,
    sizing: terminal.TextSizing,
    metrics: text.CellMetrics,
) ?PixelRect {
    var rect = planCell(row, col, geometry, metrics) orelse return null;
    const width = @as(u64, rect.width) * sizing.width;
    const height = @as(u64, rect.height) * sizing.height;
    if (width > std.math.maxInt(u32) or height > std.math.maxInt(u32)) return null;
    rect.width = @intCast(width);
    rect.height = @intCast(height);
    return rect;
}

fn planTextSizing(
    anchor_col: u16,
    sizing: terminal.TextSizing,
    metrics: text.CellMetrics,
    base: PixelRect,
) ?PixelRect {
    std.debug.assert(sizing.width > 0 and sizing.height > 0);
    std.debug.assert(sizing.x == 0 and sizing.y == 0);
    const fractional = sizing.subscale_n > 0 and sizing.subscale_d > 0 and
        sizing.subscale_n < sizing.subscale_d;
    const numerator: u32 = @as(u32, sizing.height) *
        (if (fractional) sizing.subscale_n else 1);
    const denominator: u32 = if (fractional) sizing.subscale_d else 1;
    const block_width = @as(u64, sizing.width) * metrics.width_px;
    const block_height = @as(u64, sizing.height) * metrics.height_px;
    const area_width = block_width * numerator / (@as(u64, sizing.height) * denominator);
    const area_height = block_height * numerator / (@as(u64, sizing.height) * denominator);
    const x_offset: u64 = switch (sizing.horizontal_align) {
        1 => block_width - area_width,
        2 => (block_width - area_width) / 2,
        else => 0,
    };
    const y_offset: u64 = switch (sizing.vertical_align) {
        1 => block_height - area_height,
        2 => (block_height - area_height) / 2,
        else => 0,
    };
    const anchor_x = @as(i64, anchor_col) * metrics.width_px;
    const x = anchor_x + @divFloor((@as(i64, base.x) - anchor_x) * numerator, denominator) +
        @as(i64, @intCast(x_offset));
    const y = @divFloor(@as(i64, base.y) * numerator, denominator) +
        @as(i64, @intCast(y_offset));
    const width = @as(u64, base.width) * numerator / denominator;
    const height = @as(u64, base.height) * numerator / denominator;
    if (x < std.math.minInt(i32) or x > std.math.maxInt(i32) or
        y < std.math.minInt(i32) or y > std.math.maxInt(i32) or
        width > std.math.maxInt(u32) or height > std.math.maxInt(u32))
        return null;
    return .{
        .x = @intCast(x),
        .y = @intCast(y),
        .width = @intCast(width),
        .height = @intCast(height),
    };
}

fn planContent(
    row: u16,
    anchor_col: u16,
    geometry: terminal.LineGeometry,
    baseline: terminal.CellBaseline,
    metrics: text.CellMetrics,
    base: PixelRect,
) ?PixelRect {
    const anchor_x = @as(i64, anchor_col) * metrics.width_px;
    var x = @as(i64, base.x);
    var y = @as(i64, base.y);
    var width = @as(u64, base.width);
    var height = @as(u64, base.height);
    if (baseline != .normal) {
        // SGR 73/74 use Kitty's explicit half-size top/bottom alignment while
        // retaining the normal shaped mask and its cache identity.
        x = anchor_x + @divFloor(x - anchor_x, 2);
        width = (width + 1) / 2;
        height = (height + 1) / 2;
        y = @divFloor(y, 2);
        if (baseline == .lowered) y += metrics.height_px - (metrics.height_px + 1) / 2;
    }
    const scale = lineScale(geometry);
    x *= scale.x;
    y = @as(i64, row) * metrics.height_px +
        @as(i64, scale.y_offset_cells) * metrics.height_px + y * scale.y;
    width *= scale.x;
    height *= scale.y;
    if (x < std.math.minInt(i32) or x > std.math.maxInt(i32) or
        y < std.math.minInt(i32) or y > std.math.maxInt(i32) or
        width > std.math.maxInt(u32) or height > std.math.maxInt(u32))
        return null;
    return .{ .x = @intCast(x), .y = @intCast(y), .width = @intCast(width), .height = @intCast(height) };
}

fn clipToSurface(rect: PixelRect, size: PixelSize) ?PixelRect {
    const left = @max(@as(i64, 0), rect.x);
    const top = @max(@as(i64, 0), rect.y);
    const right = @min(@as(i64, size.width), @as(i64, rect.x) + rect.width);
    const bottom = @min(@as(i64, size.height), @as(i64, rect.y) + rect.height);
    if (left >= right or top >= bottom) return null;
    return .{
        .x = @intCast(left),
        .y = @intCast(top),
        .width = @intCast(right - left),
        .height = @intCast(bottom - top),
    };
}

fn imageLayer(z: i32) Device.ImageLayer {
    return if (z < 0) .behind_text else .above_text;
}

fn validDrawRange(command: DrawCommand, vertex_count: usize) bool {
    if (command.first > std.math.maxInt(c.GLint) or
        command.count > std.math.maxInt(c.GLsizei))
        return false;
    const first: usize = command.first;
    const count: usize = command.count;
    return first <= vertex_count and count <= vertex_count - first;
}

fn intersectRect(a: PixelRect, b: PixelRect) ?PixelRect {
    const left = @max(@as(i64, a.x), b.x);
    const top = @max(@as(i64, a.y), b.y);
    const right = @min(@as(i64, a.x) + a.width, @as(i64, b.x) + b.width);
    const bottom = @min(@as(i64, a.y) + a.height, @as(i64, b.y) + b.height);
    if (left >= right or top >= bottom) return null;
    return .{
        .x = @intCast(left),
        .y = @intCast(top),
        .width = @intCast(right - left),
        .height = @intCast(bottom - top),
    };
}

fn setScissor(rect: PixelRect, size: PixelSize) void {
    std.debug.assert(rect.x >= 0 and rect.y >= 0);
    std.debug.assert(@as(u64, @intCast(rect.x)) + rect.width <= size.width);
    std.debug.assert(@as(u64, @intCast(rect.y)) + rect.height <= size.height);
    c.glScissor(
        @intCast(rect.x),
        @intCast(size.height - @as(u32, @intCast(rect.y)) - rect.height),
        @intCast(rect.width),
        @intCast(rect.height),
    );
}

fn glyphPixelX(run_start: u16, cell_width: u16, raster_left: i16, shaped_x_26_6: i32) i32 {
    return @as(i32, run_start) * cell_width + raster_left + @divTrunc(shaped_x_26_6, 64);
}

fn cursorBlockCovers(work: Submission, row: u16, col: u16) bool {
    if (!work.cursor.visible or work.cursor.shape != .block or
        row >= work.rows or col >= work.cols or
        work.cursor.row >= work.rows or work.cursor.col >= work.cols)
        return false;
    const candidate = work.cells[@as(usize, row) * work.cols + col];
    const cursor_cell = work.cells[@as(usize, work.cursor.row) * work.cols + work.cursor.col];
    return row -| candidate.sizing.y == work.cursor.row -| cursor_cell.sizing.y and
        col -| candidate.sizing.x == work.cursor.col -| cursor_cell.sizing.x;
}

fn cellFill(cell: terminal.Cell, cursor: terminal.Cursor, cursor_block: bool) terminal.Rgb {
    return if (cursor_block) cursor.color else cell.background;
}

fn glyphColor(cell: terminal.Cell, cursor: terminal.Cursor, cursor_block: bool) terminal.Rgb {
    return if (cursor_block) cursor.text_color else cell.foreground;
}

fn cellFontKey(cell: terminal.Cell) text.FontKey {
    return .{
        .slot = cell.font,
        .style = if (cell.bold and cell.italic)
            .bold_italic
        else if (cell.bold)
            .bold
        else if (cell.italic)
            .italic
        else
            .normal,
    };
}

fn decorationRise(style: terminal.UnderlineStyle, x: u16, unit: u16) ?u16 {
    std.debug.assert(unit != 0);
    return switch (style) {
        .curly => if (x % (unit *| 2) >= unit) unit else 0,
        .dotted => if (x % (unit *| 2) < unit) 0 else null,
        .dashed => if (x % (unit *| 4) < unit *| 3) 0 else null,
        else => null,
    };
}

fn expectQuadUv(
    vertices: [vertices_per_quad]Vertex,
    texture_left: f32,
    texture_top: f32,
    texture_right: f32,
    texture_bottom: f32,
) !void {
    const epsilon: f32 = 0.000_001;
    try std.testing.expectApproxEqAbs(texture_left, vertices[0].u, epsilon);
    try std.testing.expectApproxEqAbs(texture_top, vertices[0].v, epsilon);
    try std.testing.expectApproxEqAbs(texture_right, vertices[1].u, epsilon);
    try std.testing.expectApproxEqAbs(texture_bottom, vertices[1].v, epsilon);
    try std.testing.expectApproxEqAbs(texture_left, vertices[2].u, epsilon);
    try std.testing.expectApproxEqAbs(texture_bottom, vertices[2].v, epsilon);
    try std.testing.expectApproxEqAbs(texture_left, vertices[3].u, epsilon);
    try std.testing.expectApproxEqAbs(texture_top, vertices[3].v, epsilon);
    try std.testing.expectApproxEqAbs(texture_right, vertices[4].u, epsilon);
    try std.testing.expectApproxEqAbs(texture_top, vertices[4].v, epsilon);
    try std.testing.expectApproxEqAbs(texture_right, vertices[5].u, epsilon);
    try std.testing.expectApproxEqAbs(texture_bottom, vertices[5].v, epsilon);
}

test "mailbox replaces only pending work while active ownership remains exact" {
    var slots = [_]Snapshot{
        try Snapshot.init(std.testing.allocator, 1, 1),
        try Snapshot.init(std.testing.allocator, 1, 1),
    };
    defer for (&slots) |*slot| slot.deinit();
    var mailbox = Mailbox{};
    mailbox.release(&slots[0]);
    mailbox.release(&slots[1]);
    const first = mailbox.writable().?;
    try std.testing.expect(mailbox.admit(first) == null);
    const second = mailbox.writable().?;
    const replaced = mailbox.admit(second).?;
    try std.testing.expect(replaced == first);
    mailbox.release(replaced);
    try std.testing.expect(mailbox.take() == second);
    try std.testing.expect(mailbox.active == second);
    const pending = mailbox.writable().?;
    try std.testing.expect(mailbox.admit(pending) == null);
    try std.testing.expect(mailbox.writable() == null);
    mailbox.complete();
    try std.testing.expect(mailbox.active == null);
    try std.testing.expect(mailbox.pending == first);
    try std.testing.expect(mailbox.writable() == second);
}

test "mailbox growth failure preserves every slot owner and pending work" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var slots = [_]Snapshot{
        try Snapshot.init(failing.allocator(), 1, 1),
        try Snapshot.init(failing.allocator(), 1, 1),
    };
    defer for (&slots) |*slot| slot.deinit();
    var mailbox = Mailbox{};
    mailbox.release(&slots[0]);
    mailbox.release(&slots[1]);
    const cells = [_]terminal.Cell{
        testCell('a'), testCell('b'), testCell('c'),
        testCell('d'), testCell('e'), testCell('f'),
        testCell('g'), testCell('h'), testCell('i'),
    };
    const geometry = [_]terminal.LineGeometry{
        .single_width, .single_width, .single_width,
    };

    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, mailbox.write(.{
        .generation = 1,
        .rows = 2,
        .cols = 2,
        .cells = cells[0..4],
        .row_geometry = geometry[0..2],
        .cursor = testCursor(),
        .size = .{ .width = 20, .height = 20 },
    }, measure.now(std.testing.io)));
    try std.testing.expect(mailbox.pending == null);
    try std.testing.expect(mailbox.active == null);
    try std.testing.expect(mailbox.free_first == &slots[0]);
    try std.testing.expect(mailbox.free_second == &slots[1]);

    failing.fail_index = std.math.maxInt(usize);
    try mailbox.write(.{
        .generation = 2,
        .rows = 2,
        .cols = 2,
        .cells = cells[0..4],
        .row_geometry = geometry[0..2],
        .cursor = testCursor(),
        .size = .{ .width = 20, .height = 20 },
    }, measure.now(std.testing.io));
    try std.testing.expect(mailbox.pending == &slots[1]);
    try std.testing.expect(mailbox.take() == &slots[1]);
    try mailbox.write(.{
        .generation = 3,
        .rows = 1,
        .cols = 1,
        .cells = cells[0..1],
        .row_geometry = geometry[0..1],
        .cursor = testCursor(),
        .size = .{ .width = 10, .height = 10 },
    }, measure.now(std.testing.io));
    const pending = mailbox.pending.?;
    const pending_generation = pending.generation;
    const pending_rows = pending.rows;
    const pending_cols = pending.cols;
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, mailbox.write(.{
        .generation = 4,
        .rows = 3,
        .cols = 3,
        .cells = &cells,
        .row_geometry = &geometry,
        .cursor = testCursor(),
        .size = .{ .width = 30, .height = 30 },
    }, measure.now(std.testing.io)));
    try std.testing.expect(mailbox.active == &slots[1]);
    try std.testing.expect(mailbox.pending == pending);
    try std.testing.expect(mailbox.free_first == null);
    try std.testing.expect(mailbox.free_second == null);
    try std.testing.expectEqual(pending_generation, pending.generation);
    try std.testing.expectEqual(pending_rows, pending.rows);
    try std.testing.expectEqual(pending_cols, pending.cols);

    failing.fail_index = std.math.maxInt(usize);
    try mailbox.write(.{
        .generation = 5,
        .rows = 3,
        .cols = 3,
        .cells = &cells,
        .row_geometry = &geometry,
        .cursor = testCursor(),
        .size = .{ .width = 30, .height = 30 },
    }, measure.now(std.testing.io));
    try std.testing.expect(mailbox.active == &slots[1]);
    try std.testing.expect(mailbox.pending == pending);
    try std.testing.expectEqual(@as(u64, 5), pending.generation);
}

test "snapshot copy has no caller lifetime and preserves newest identity" {
    var snapshot = try Snapshot.init(std.testing.allocator, 1, 2);
    defer snapshot.deinit();
    var cells = [_]terminal.Cell{ testCell('a'), testCell('b') };
    cells[0].baseline = .raised;
    var geometry = [_]terminal.LineGeometry{.double_width};
    const bar = viewport.scrollbar(
        .{ .history_count = 20, .offset = 4, .rows = 1 },
        20,
        10,
        10,
        10,
    ).?;
    snapshot.write(.{
        .generation = 7,
        .rows = 1,
        .cols = 2,
        .cells = &cells,
        .row_geometry = &geometry,
        .cursor = testCursor(),
        .size = .{ .width = 20, .height = 10 },
        .scrollbar = bar,
    }, measure.now(std.testing.io));
    cells[0].codepoint = 'z';
    cells[0].baseline = .normal;
    geometry[0] = .single_width;
    const copy = snapshot.view();
    try std.testing.expectEqual(@as(u21, 'a'), copy.cells[0].codepoint);
    try std.testing.expectEqual(terminal.CellBaseline.raised, copy.cells[0].baseline);
    try std.testing.expectEqual(terminal.LineGeometry.double_width, copy.row_geometry[0]);
    try std.testing.expectEqual(@as(u64, 7), copy.generation);
    try std.testing.expectEqual(bar, copy.scrollbar.?);
}

test "snapshot growth is transactional and unchanged geometry allocates nothing" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var snapshot = try Snapshot.init(failing.allocator(), 1, 2);
    defer snapshot.deinit();
    snapshot.generation = 9;
    snapshot.rows = 1;
    snapshot.cols = 2;
    const allocation_count = failing.alloc_index;
    try snapshot.ensureCapacity(1, 2);
    try std.testing.expectEqual(allocation_count, failing.alloc_index);

    failing.fail_index = failing.alloc_index + 1;
    try std.testing.expectError(error.OutOfMemory, snapshot.ensureCapacity(3, 4));
    try std.testing.expectEqual(@as(usize, 2), snapshot.cells.len);
    try std.testing.expectEqual(@as(usize, 1), snapshot.row_geometry.len);
    try std.testing.expectEqual(@as(u64, 9), snapshot.generation);
    try std.testing.expectEqual(@as(u16, 1), snapshot.rows);
    try std.testing.expectEqual(@as(u16, 2), snapshot.cols);

    var row_growth = try Snapshot.init(std.testing.allocator, 1, 4);
    defer row_growth.deinit();
    const cells_before = row_growth.cells.ptr;
    try row_growth.ensureCapacity(2, 2);
    try std.testing.expect(cells_before == row_growth.cells.ptr);
    try std.testing.expectEqual(@as(usize, 4), row_growth.cells.len);
    try std.testing.expectEqual(@as(usize, 2), row_growth.row_geometry.len);
}

test "submission rejects hostile bounds before snapshot mutation" {
    var snapshot = try Snapshot.init(std.testing.allocator, 1, 1);
    defer snapshot.deinit();
    snapshot.generation = 19;
    const cell = testCell('x');
    const geometry = [_]terminal.LineGeometry{.single_width};
    try std.testing.expectError(error.InvalidSubmission, validateSubmission(.{
        .generation = 1,
        .rows = 1,
        .cols = 2,
        .cells = (&cell)[0..1],
        .row_geometry = &geometry,
        .cursor = testCursor(),
        .size = .{ .width = 1, .height = 1 },
    }));
    try std.testing.expectEqual(@as(u64, 19), snapshot.generation);

    try std.testing.expectError(error.InvalidSubmission, validateSubmission(.{
        .generation = 1,
        .rows = 1,
        .cols = 1,
        .cells = (&cell)[0..1],
        .row_geometry = &geometry,
        .cursor = testCursor(),
        .size = .{ .width = 10, .height = 10 },
        .scrollbar = .{
            .track = .{ .x = 9, .y = 0, .width = 1, .height = 10 },
            .thumb = .{ .x = 9, .y = 9, .width = 1, .height = 2 },
            .history_count = 1,
            .offset = 0,
        },
    }));
}

test "renderer construction rejects missing fonts before device work" {
    var measurement = measure.State{};
    try std.testing.expectError(error.MissingDefaultConfiguration, validateInit(.{
        .display = @ptrFromInt(1),
        .surface = @ptrFromInt(1),
        .size = .{ .width = 1, .height = 1 },
        .rows = 1,
        .cols = 1,
        .fonts = &.{},
        .measurement = measurement.ref(),
    }));
}

test "glyph cache identity includes exact font and generated raster facts" {
    const native_a = text.GlyphKey{ .native = .{
        .font = .{ .slot = 0, .style = .normal },
        .face_index = 0,
        .glyph_id = 4,
        .cell_span = 1,
    } };
    const native_b = text.GlyphKey{ .native = .{
        .font = .{ .slot = 1, .style = .normal },
        .face_index = 0,
        .glyph_id = 4,
        .cell_span = 1,
    } };
    try std.testing.expect(!std.meta.eql(native_a, native_b));
    const generated_a = text.GlyphKey{ .generated = .{
        .codepoint = 0x2500,
        .width_px = 8,
        .height_px = 16,
        .baseline_px = 12,
    } };
    const generated_b = text.GlyphKey{ .generated = .{
        .codepoint = 0x2500,
        .width_px = 8,
        .height_px = 16,
        .baseline_px = 13,
    } };
    try std.testing.expect(!std.meta.eql(generated_a, generated_b));
}

test "glyph atlas packs shelves and preserves exact UV identity" {
    var cache = GlyphCache{ .extent = 8 };
    var pixels: [64]u8 = @splat(255);
    const first_key = testGlyphKey(0x2500);
    const first_raster = testRaster(pixels[0..6], 3, 2);
    const first_plan = cache.plan(3, 2, 1).?;
    try std.testing.expectEqual(
        AtlasAdmission{ .grow = .{ .x = 0, .y = 0, .width = 3, .height = 2 } },
        first_plan,
    );
    const first = cache.admit(first_plan, 11, first_key, first_raster, 1);
    try std.testing.expectEqual(@as(?u8, 0), first.atlas);
    try std.testing.expectEqual(
        TextureUv{ .left = 0, .top = 0, .right = 3.0 / 8.0, .bottom = 2.0 / 8.0 },
        glyphUv(first.*, cache.extent),
    );

    const second_plan = cache.plan(4, 3, 1).?;
    try std.testing.expectEqual(
        AtlasAdmission{ .existing = .{
            .atlas = 0,
            .rect = .{ .x = 3, .y = 0, .width = 4, .height = 3 },
        } },
        second_plan,
    );
    const second = cache.admit(
        second_plan,
        11,
        testGlyphKey(0x2501),
        testRaster(pixels[0..12], 4, 3),
        1,
    );
    try std.testing.expectEqual(@as(u16, 3), second.rect.x);
    const next_row = cache.plan(8, 4, 2).?;
    try std.testing.expectEqual(
        AtlasAdmission{ .existing = .{
            .atlas = 0,
            .rect = .{ .x = 0, .y = 3, .width = 8, .height = 4 },
        } },
        next_row,
    );
    const third = cache.admit(
        next_row,
        11,
        testGlyphKey(0x2502),
        testRaster(pixels[0..32], 8, 4),
        2,
    );
    try std.testing.expectEqual(@as(u16, 3), third.rect.y);
    try std.testing.expectEqual(@as(usize, 3), cache.glyph_count);
    try std.testing.expectEqual(@as(usize, 1), cache.atlas_count);
}

test "glyph atlas rejects oversize without mutation and grows transactionally" {
    var cache = GlyphCache{ .extent = 4 };
    try std.testing.expect(cache.plan(5, 1, 1) == null);
    try std.testing.expect(cache.plan(1, 5, 1) == null);
    try std.testing.expectEqual(@as(usize, 0), cache.glyph_count);
    try std.testing.expectEqual(@as(usize, 0), cache.atlas_count);

    var pixels: [16]u8 = @splat(255);
    const planned = cache.plan(4, 4, 1).?;
    // A failed GL upload leaves this pure plan and every cache owner untouched.
    try std.testing.expectEqual(@as(usize, 0), cache.glyph_count);
    try std.testing.expectEqual(@as(usize, 0), cache.atlas_count);
    const admitted = cache.admit(
        planned,
        17,
        testGlyphKey(0x2500),
        testRaster(&pixels, 4, 4),
        1,
    );
    try std.testing.expectEqual(@as(?u8, 0), admitted.atlas);
    try std.testing.expectEqual(@as(usize, 1), cache.glyph_count);
    try std.testing.expectEqual(@as(usize, 1), cache.atlas_count);
    try std.testing.expectEqual(@as(c.GLuint, 17), cache.atlases[0].name);
}

test "glyph cache count bound rejects without overwriting retained identity" {
    var cache = GlyphCache{ .extent = 4 };
    var no_pixels: [0]u8 = .{};
    const empty = testRaster(&no_pixels, 0, 0);
    for (0..glyph_capacity) |index| {
        const admitted = cache.admitEmpty(
            testGlyphKey(@intCast(0x1_0000 + index)),
            empty,
            1,
        ).?;
        try std.testing.expectEqual(@as(?u8, null), admitted.atlas);
    }
    try std.testing.expect(cache.admitEmpty(testGlyphKey(0x1_1000), empty, 2) == null);
    try std.testing.expectEqual(glyph_capacity, cache.glyph_count);
    var comparisons: usize = 0;
    try std.testing.expect(cache.find(testGlyphKey(0x1_0000), &comparisons) != null);
}

test "glyph atlas eviction protects current draws and rebuilds identity index" {
    var cache = GlyphCache{ .extent = 2 };
    var pixels: [4]u8 = @splat(255);
    for (0..glyph_atlas_capacity) |index| {
        const generation: u64 = @intCast(index + 1);
        const plan = cache.plan(2, 2, generation).?;
        const glyph = cache.admit(
            plan,
            @intCast(100 + index),
            testGlyphKey(@intCast(0x2500 + index)),
            testRaster(&pixels, 2, 2),
            generation,
        );
        try std.testing.expectEqual(@as(?u8, @intCast(index)), glyph.atlas);
    }
    try std.testing.expectEqual(glyph_atlas_capacity, cache.atlas_count);
    cache.glyphs[0].used = 20;
    const replacement = cache.plan(2, 2, 20).?;
    try std.testing.expectEqual(@as(u8, 1), replacement.replace.atlas);
    const replacement_glyph = cache.admit(
        replacement,
        200,
        testGlyphKey(0x2600),
        testRaster(&pixels, 2, 2),
        20,
    );
    try std.testing.expectEqual(@as(?u8, 1), replacement_glyph.atlas);
    var comparisons: usize = 0;
    try std.testing.expect(cache.find(testGlyphKey(0x2501), &comparisons) == null);
    try std.testing.expect(cache.find(testGlyphKey(0x2500), &comparisons) != null);
    try std.testing.expect(cache.find(testGlyphKey(0x2600), &comparisons) != null);
    try std.testing.expectEqual(@as(c.GLuint, 200), cache.atlases[1].name);
    for (cache.glyphs[0..cache.glyph_count]) |*glyph| glyph.used = 21;
    try std.testing.expect(cache.plan(2, 2, 21) == null);
}

test "fresh glyph atlas reconstructs the same placement after context loss" {
    var pixels: [15]u8 = @splat(255);
    const key = testGlyphKey(0x2500);
    const raster = testRaster(&pixels, 3, 5);
    var before = GlyphCache{ .extent = 16 };
    const first = before.admit(before.plan(3, 5, 1).?, 1, key, raster, 1).*;
    var rebuilt = GlyphCache{ .extent = 16 };
    const second = rebuilt.admit(rebuilt.plan(3, 5, 2).?, 2, key, raster, 2).*;
    try std.testing.expectEqual(first.rect, second.rect);
    try std.testing.expectEqual(glyphUv(first, 16), glyphUv(second, 16));
}

test "shaped glyph placement anchors the pen once at the run start" {
    try std.testing.expectEqual(@as(i32, 89), glyphPixelX(8, 10, -1, 10 * 64));
}

test "snapshot retains complete image state and skips identical generation bytes" {
    var snapshot = try Snapshot.init(std.testing.allocator, 1, 1);
    defer snapshot.deinit();
    const cells = [_]terminal.Cell{testCell(' ')};
    const geometry = [_]terminal.LineGeometry{.single_width};
    const pixels = [_]u8{ 1, 2, 3, 4 };
    const images = [_]terminal.ImageUpload{.{
        .identity = .{ .id = 7, .generation = 1 },
        .width = 1,
        .height = 1,
        .pixel_offset = 0,
        .pixel_count = 4,
    }};
    const placements = [_]terminal.ImagePlacement{.{
        .image_id = 7,
        .generation = 1,
        .row = 0,
        .col = 0,
    }};
    try snapshot.ensureImageCapacity(4, 1, 1);
    snapshot.write(.{
        .generation = 1,
        .rows = 1,
        .cols = 1,
        .cells = &cells,
        .row_geometry = &geometry,
        .cursor = testCursor(),
        .size = .{ .width = 10, .height = 10 },
        .image_generation = 1,
        .image_content_generation = 1,
        .image_pixels = &pixels,
        .images = &images,
        .image_placements = &placements,
    }, measure.now(std.testing.io));
    {
        const before = snapshot.image_pixels[0..4].*;
        const changed_source = [_]u8{ 9, 9, 9, 9 };
        snapshot.write(.{
            .generation = 2,
            .rows = 1,
            .cols = 1,
            .cells = &cells,
            .row_geometry = &geometry,
            .cursor = testCursor(),
            .size = .{ .width = 10, .height = 10 },
            .image_generation = 2,
            .image_content_generation = 1,
            .image_pixels = &changed_source,
            .images = &images,
            .image_placements = &placements,
        }, measure.now(std.testing.io));
        try std.testing.expectEqualSlices(u8, &before, snapshot.image_pixels[0..4]);
    }
    try std.testing.expectEqual(@as(u64, 2), snapshot.view().image_generation);
    try std.testing.expectEqual(@as(usize, 1), snapshot.view().image_placements.len);
}

test "image vertices preserve exact cropped texture and scaled destination bounds" {
    const vertices = imageVertices(
        10,
        20,
        30,
        40,
        .{ .width = 100, .height = 100 },
        .{
            .image_id = 1,
            .generation = 1,
            .row = 0,
            .col = 0,
            .source_x = 20,
            .source_y = 10,
            .source_width = 40,
            .source_height = 20,
        },
        100,
        50,
    );
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), vertices[0].u, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), vertices[0].v, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.6), vertices[1].u, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.6), vertices[1].v, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, -0.8), vertices[0].x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.6), vertices[0].y, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, -0.2), vertices[1].x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, -0.2), vertices[1].y, 0.0001);
}

test "draw batch owns exact fixed storage and rolls back both allocations" {
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(Vertex));
    try std.testing.expectEqual(
        @as(usize, 786_432),
        batch_quad_capacity * vertices_per_quad * @sizeOf(Vertex),
    );
    try std.testing.expectEqual(
        @as(usize, batch_quad_capacity * @sizeOf(DrawCommand)),
        147_456,
    );
    inline for (0..2) |fail_index| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{
            .fail_index = fail_index,
        });
        try std.testing.expectError(error.OutOfMemory, DrawBatch.init(failing.allocator()));
    }
    var batch = try DrawBatch.init(std.testing.allocator);
    batch.deinit();
}

test "draw batch preserves exact vertices and merges only identical contiguous state" {
    var batch = try DrawBatch.init(std.testing.allocator);
    defer batch.deinit();
    const first = quadVertices(
        1,
        2,
        3,
        4,
        .{ .width = 100, .height = 80 },
        .{ .r = 1, .g = 2, .b = 3 },
    );
    const second = quadVertices(
        5,
        6,
        7,
        8,
        .{ .width = 100, .height = 80 },
        .{ .r = 4, .g = 5, .b = 6 },
    );
    const state = DrawState{
        .texture = 9,
        .texture_color = false,
        .scissor = .{ .x = 0, .y = 0, .width = 10, .height = 10 },
    };
    try std.testing.expect(batch.stage(first, state));
    try std.testing.expect(batch.stage(second, state));
    try std.testing.expectEqual(@as(usize, 1), batch.command_count);
    try std.testing.expectEqual(@as(u32, 12), batch.commands[0].count);
    try std.testing.expectEqualSlices(
        u8,
        std.mem.asBytes(&first),
        std.mem.sliceAsBytes(batch.vertices[0..vertices_per_quad]),
    );
    try std.testing.expectEqualSlices(
        u8,
        std.mem.asBytes(&second),
        std.mem.sliceAsBytes(batch.vertices[vertices_per_quad..][0..vertices_per_quad]),
    );

    var changed = state;
    changed.texture = 10;
    try std.testing.expect(batch.stage(first, changed));
    changed.texture_color = true;
    try std.testing.expect(batch.stage(first, changed));
    changed.scissor.?.x = 1;
    try std.testing.expect(batch.stage(first, changed));
    changed.scissor = null;
    try std.testing.expect(batch.stage(first, changed));
    try std.testing.expectEqual(@as(usize, 5), batch.command_count);
    for (batch.commands[0 .. batch.command_count - 1], batch.commands[1..batch.command_count]) |
        before,
        after,
    | try std.testing.expectEqual(before.first + before.count, after.first);
}

test "draw batch capacity rejects one quad without mutation and is reusable after reset" {
    var batch = try DrawBatch.init(std.testing.allocator);
    defer batch.deinit();
    const vertices = quadVertices(
        0,
        0,
        1,
        1,
        .{ .width = 1, .height = 1 },
        .{ .r = 0, .g = 0, .b = 0 },
    );
    var state = DrawState{ .texture = 1, .texture_color = false, .scissor = null };
    for (0..batch_quad_capacity) |index| {
        state.texture = @intCast(index + 1);
        try std.testing.expect(batch.stage(vertices, state));
    }
    const last = batch.commands[batch.command_count - 1];
    try std.testing.expect(!batch.stage(vertices, state));
    try std.testing.expectEqual(@as(usize, batch_quad_capacity * vertices_per_quad), batch.vertex_count);
    try std.testing.expectEqual(@as(usize, batch_quad_capacity), batch.command_count);
    try std.testing.expectEqual(last, batch.commands[batch.command_count - 1]);
    batch.reset();
    try std.testing.expect(batch.stage(vertices, state));
    try std.testing.expectEqual(@as(usize, vertices_per_quad), batch.vertex_count);
    try std.testing.expectEqual(@as(usize, 1), batch.command_count);
}

test "draw command range rejects host and GLES overflow before execution" {
    const state = DrawState{ .texture = 1, .texture_color = false, .scissor = null };
    try std.testing.expect(validDrawRange(.{
        .state = state,
        .first = 6,
        .count = 12,
    }, 18));
    try std.testing.expect(!validDrawRange(.{
        .state = state,
        .first = 7,
        .count = 12,
    }, 18));
    try std.testing.expect(!validDrawRange(.{
        .state = state,
        .first = std.math.maxInt(u32),
        .count = 1,
    }, batch_quad_capacity * vertices_per_quad));
    try std.testing.expect(!validDrawRange(.{
        .state = state,
        .first = 0,
        .count = std.math.maxInt(u32),
    }, batch_quad_capacity * vertices_per_quad));
}

test "draw batch retains ordered image text decoration cursor and scrollbar states" {
    var batch = try DrawBatch.init(std.testing.allocator);
    defer batch.deinit();
    const vertices = quadVertices(
        0,
        0,
        1,
        1,
        .{ .width = 1, .height = 1 },
        .{ .r = 0, .g = 0, .b = 0 },
    );
    const clip_a = PixelRect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    const clip_b = PixelRect{ .x = 1, .y = 2, .width = 3, .height = 4 };
    const states = [_]DrawState{
        .{ .texture = 1, .texture_color = false, .scissor = null },
        .{ .texture = 2, .texture_color = true, .scissor = clip_a },
        .{ .texture = 3, .texture_color = false, .scissor = clip_b },
        .{ .texture = 1, .texture_color = false, .scissor = clip_b },
        .{ .texture = 4, .texture_color = true, .scissor = clip_a },
        .{ .texture = 1, .texture_color = false, .scissor = clip_a },
        .{ .texture = 1, .texture_color = false, .scissor = null },
    };
    for (states) |state| try std.testing.expect(batch.stage(vertices, state));
    try std.testing.expectEqual(states.len, batch.command_count);
    for (states, batch.commands[0..batch.command_count]) |expected, command|
        try std.testing.expectEqual(expected, command.state);
}

test "draw batch retains OSC 66 and DEC clips and exact image z phases" {
    var batch = try DrawBatch.init(std.testing.allocator);
    defer batch.deinit();
    const metrics = text.CellMetrics{ .width_px = 9, .height_px = 15, .baseline_px = 11 };
    const size = PixelSize{ .width = 90, .height = 75 };
    const osc_clip = clipToSurface(
        clusterCellRect(1, 2, .single_width, .{
            .width = 3,
            .height = 2,
            .x = 0,
            .y = 0,
        }, metrics).?,
        size,
    ).?;
    const dec_clip = clipToSurface(
        planCell(3, 1, .double_height_bottom, metrics).?,
        size,
    ).?;
    const osc_vertices = quadVertices(18, 15, 27, 30, size, .{ .r = 1, .g = 2, .b = 3 });
    const dec_vertices = quadVertices(18, 30, 18, 30, size, .{ .r = 4, .g = 5, .b = 6 });
    try std.testing.expect(batch.stage(osc_vertices, .{
        .texture = 1,
        .texture_color = false,
        .scissor = osc_clip,
    }));
    try std.testing.expect(batch.stage(dec_vertices, .{
        .texture = 1,
        .texture_color = false,
        .scissor = dec_clip,
    }));
    try std.testing.expectEqual(@as(usize, 2), batch.command_count);
    try std.testing.expectEqual(osc_clip, batch.commands[0].state.scissor.?);
    try std.testing.expectEqual(dec_clip, batch.commands[1].state.scissor.?);
    try std.testing.expectEqual(Device.ImageLayer.behind_text, imageLayer(-1));
    try std.testing.expectEqual(Device.ImageLayer.above_text, imageLayer(0));
    try std.testing.expectEqual(Device.ImageLayer.above_text, imageLayer(1));
}

test "draw colors consume projected cell and cursor facts exactly" {
    var cell = testCell('x');
    cell.foreground = .{ .r = 1, .g = 2, .b = 3 };
    cell.background = .{ .r = 4, .g = 5, .b = 6 };
    var cursor = testCursor();
    cursor.color = .{ .r = 7, .g = 8, .b = 9 };
    cursor.text_color = .{ .r = 10, .g = 11, .b = 12 };
    try std.testing.expectEqual(cell.background, cellFill(cell, cursor, false));
    try std.testing.expectEqual(cell.foreground, glyphColor(cell, cursor, false));
    try std.testing.expectEqual(cursor.color, cellFill(cell, cursor, true));
    try std.testing.expectEqual(cursor.text_color, glyphColor(cell, cursor, true));
}

test "background spans elide clear cells and retain exact alternating fills" {
    const metrics = text.CellMetrics{ .width_px = 9, .height_px = 15, .baseline_px = 11 };
    var cells = [_]terminal.Cell{
        testCell(' '), testCell(' '), testCell(' '), testCell(' '), testCell(' '),
    };
    for (&cells) |*cell| cell.background = clear_color;
    const geometry = [_]terminal.LineGeometry{.single_width};
    var spans = BackgroundSpans{
        .work = testSubmission(&cells, &geometry, testCursor()),
        .row = 0,
        .metrics = metrics,
        .logical_cols = cells.len,
    };
    try std.testing.expectEqual(@as(?BackgroundSpan, null), try spans.next());

    const orange = terminal.Rgb{ .r = 0xd6, .g = 0x5d, .b = 0x0e };
    const green = terminal.Rgb{ .r = 0x98, .g = 0x97, .b = 0x1a };
    cells[0].background = orange;
    cells[1].background = green;
    cells[2].background = orange;
    cells[3].background = green;
    spans = .{
        .work = testSubmission(&cells, &geometry, testCursor()),
        .row = 0,
        .metrics = metrics,
        .logical_cols = cells.len,
    };
    for (0..4) |index| {
        const span = (try spans.next()).?;
        try std.testing.expectEqual(@as(i32, @intCast(index * 9)), span.rect.x);
        try std.testing.expectEqual(@as(u32, 9), span.rect.width);
        try std.testing.expectEqual(if (index % 2 == 0) orange else green, span.color);
    }
    try std.testing.expectEqual(@as(?BackgroundSpan, null), try spans.next());
}

test "background spans merge adjacent resolved colors and preserve cursor clusters" {
    const metrics = text.CellMetrics{ .width_px = 7, .height_px = 13, .baseline_px = 10 };
    const orange = terminal.Rgb{ .r = 0xd6, .g = 0x5d, .b = 0x0e };
    const blue = terminal.Rgb{ .r = 0x45, .g = 0x85, .b = 0x88 };
    var cells = [_]terminal.Cell{
        testCell(' '), testCell(' '), testCell(' '), testCell(' '), testCell(' '),
    };
    for (&cells) |*cell| cell.background = clear_color;
    cells[0].background = orange;
    cells[1].background = orange;
    cells[2].background = orange;
    cells[3].background = blue;
    cells[4].background = blue;
    const geometry = [_]terminal.LineGeometry{.single_width};
    var cursor = testCursor();
    cursor.visible = false;
    var spans = BackgroundSpans{
        .work = testSubmission(&cells, &geometry, cursor),
        .row = 0,
        .metrics = metrics,
        .logical_cols = cells.len,
    };
    try std.testing.expectEqual(
        BackgroundSpan{
            .rect = .{ .x = 0, .y = 0, .width = 21, .height = 13 },
            .color = orange,
        },
        (try spans.next()).?,
    );
    try std.testing.expectEqual(
        BackgroundSpan{
            .rect = .{ .x = 21, .y = 0, .width = 14, .height = 13 },
            .color = blue,
        },
        (try spans.next()).?,
    );

    for (&cells) |*cell| cell.background = clear_color;
    cells[0].sizing = .{ .width = 2, .height = 1, .x = 0, .y = 0 };
    cells[1].sizing = .{ .width = 2, .height = 1, .x = 1, .y = 0 };
    cursor.visible = true;
    cursor.shape = .block;
    cursor.row = 0;
    cursor.col = 0;
    cursor.color = orange;
    spans = .{
        .work = testSubmission(&cells, &geometry, cursor),
        .row = 0,
        .metrics = metrics,
        .logical_cols = cells.len,
    };
    try std.testing.expectEqual(@as(u32, 14), (try spans.next()).?.rect.width);
    try std.testing.expectEqual(@as(?BackgroundSpan, null), try spans.next());
}

test "background spans preserve resolved selection reverse differences and DEC odd tails" {
    const metrics = text.CellMetrics{ .width_px = 9, .height_px = 15, .baseline_px = 11 };
    const selected = terminal.Rgb{ .r = 0xee, .g = 0xee, .b = 0xee };
    const reversed = terminal.Rgb{ .r = 0xeb, .g = 0xdb, .b = 0xb2 };
    var cells = [_]terminal.Cell{
        testCell(' '), testCell(' '), testCell(' '), testCell(' '), testCell(' '),
    };
    cells[0].background = selected;
    cells[1].background = reversed;
    cells[2].background = selected;
    cells[3].background = clear_color;
    cells[4].background = clear_color;
    const geometry = [_]terminal.LineGeometry{.double_width};
    var cursor = testCursor();
    cursor.visible = false;
    var spans = BackgroundSpans{
        .work = testSubmission(&cells, &geometry, cursor),
        .row = 0,
        .metrics = metrics,
        .logical_cols = rowColumns(geometry[0], cells.len),
    };
    const first = (try spans.next()).?;
    const second = (try spans.next()).?;
    const tail = (try spans.next()).?;
    try std.testing.expectEqual(PixelRect{ .x = 0, .y = 0, .width = 18, .height = 15 }, first.rect);
    try std.testing.expectEqual(selected, first.color);
    try std.testing.expectEqual(PixelRect{ .x = 18, .y = 0, .width = 18, .height = 15 }, second.rect);
    try std.testing.expectEqual(reversed, second.color);
    try std.testing.expectEqual(PixelRect{ .x = 36, .y = 0, .width = 9, .height = 15 }, tail.rect);
    try std.testing.expectEqual(selected, tail.color);
    try std.testing.expectEqual(@as(i64, 45), @as(i64, tail.rect.x) + tail.rect.width);
    try std.testing.expectEqual(@as(?BackgroundSpan, null), try spans.next());

    var one = [_]terminal.Cell{testCell(' ')};
    one[0].background = selected;
    const one_geometry = [_]terminal.LineGeometry{.double_height_top};
    spans = .{
        .work = testSubmission(&one, &one_geometry, cursor),
        .row = 0,
        .metrics = metrics,
        .logical_cols = rowColumns(one_geometry[0], one.len),
    };
    try std.testing.expectEqual(@as(u32, 9), (try spans.next()).?.rect.width);
}

test "decoration metrics use the exact projected font identity" {
    var cell = testCell('x');
    cell.font = 15;
    cell.bold = true;
    cell.italic = true;
    try std.testing.expectEqual(
        text.FontKey{ .slot = 15, .style = .bold_italic },
        cellFontKey(cell),
    );
}

test "row plans preserve logical columns and odd physical edges" {
    const metrics = text.CellMetrics{ .width_px = 9, .height_px = 15, .baseline_px = 11 };
    try std.testing.expectEqual(@as(u16, 5), rowColumns(.single_width, 5));
    try std.testing.expectEqual(@as(u16, 2), rowColumns(.double_width, 5));
    try std.testing.expectEqual(@as(u16, 1), rowColumns(.double_height_top, 1));
    try std.testing.expectEqual(
        PixelRect{ .x = 18, .y = 30, .width = 18, .height = 15 },
        planCell(2, 1, .double_width, metrics).?,
    );
}

test "double-height halves share one scaled canvas with exact row clipping" {
    const metrics = text.CellMetrics{ .width_px = 9, .height_px = 15, .baseline_px = 11 };
    const base = PixelRect{ .x = 9, .y = 2, .width = 7, .height = 9 };
    const top = planContent(1, 1, .double_height_top, .normal, metrics, base).?;
    const bottom = planContent(2, 1, .double_height_bottom, .normal, metrics, base).?;
    try std.testing.expectEqual(PixelRect{ .x = 18, .y = 19, .width = 14, .height = 18 }, top);
    try std.testing.expectEqual(top, bottom);
    try std.testing.expectEqual(
        PixelRect{ .x = 18, .y = 19, .width = 14, .height = 11 },
        intersectRect(top, planCell(1, 1, .double_height_top, metrics).?).?,
    );
    try std.testing.expectEqual(
        PixelRect{ .x = 18, .y = 30, .width = 14, .height = 7 },
        intersectRect(bottom, planCell(2, 1, .double_height_bottom, metrics).?).?,
    );
}

test "raised and lowered placement use half scale and top bottom alignment" {
    const metrics = text.CellMetrics{ .width_px = 9, .height_px = 15, .baseline_px = 11 };
    const base = PixelRect{ .x = 11, .y = 2, .width = 7, .height = 9 };
    try std.testing.expectEqual(
        PixelRect{ .x = 10, .y = 1, .width = 4, .height = 5 },
        planContent(0, 1, .single_width, .raised, metrics, base).?,
    );
    try std.testing.expectEqual(
        PixelRect{ .x = 10, .y = 8, .width = 4, .height = 5 },
        planContent(0, 1, .single_width, .lowered, metrics, base).?,
    );
    try std.testing.expectEqual(
        PixelRect{ .x = 20, .y = 2, .width = 8, .height = 10 },
        planContent(0, 1, .double_height_top, .raised, metrics, base).?,
    );
}

test "baseline scaling anchors every shaped glyph to its source cell" {
    const metrics = text.CellMetrics{ .width_px = 9, .height_px = 15, .baseline_px = 11 };
    const second = planContent(
        0,
        3,
        .single_width,
        .raised,
        metrics,
        .{ .x = 28, .y = 2, .width = 7, .height = 9 },
    ).?;
    try std.testing.expectEqual(@as(i32, 27), second.x);
    try std.testing.expect(second.x >= planCell(0, 3, .single_width, metrics).?.x);
    try std.testing.expect(second.x < planCell(0, 4, .single_width, metrics).?.x);
}

test "cursor and decoration rectangles share geometry and baseline transforms" {
    const metrics = text.CellMetrics{ .width_px = 9, .height_px = 15, .baseline_px = 11 };
    const cursor = PixelRect{ .x = 9, .y = 13, .width = 9, .height = 2 };
    try std.testing.expectEqual(
        PixelRect{ .x = 18, .y = 26, .width = 18, .height = 4 },
        planContent(0, 1, .double_height_top, .normal, metrics, cursor).?,
    );
    const underline = PixelRect{ .x = 9, .y = 12, .width = 9, .height = 1 };
    try std.testing.expectEqual(
        PixelRect{ .x = 18, .y = 12, .width = 10, .height = 2 },
        planContent(0, 1, .double_height_top, .raised, metrics, underline).?,
    );
    try std.testing.expectEqual(
        PixelRect{ .x = 18, .y = 26, .width = 10, .height = 2 },
        planContent(0, 1, .double_height_top, .lowered, metrics, underline).?,
    );
}

test "OSC 66 draw planning scales and aligns within the exact cell block" {
    const metrics = text.CellMetrics{ .width_px = 8, .height_px = 16, .baseline_px = 12 };
    const base = PixelRect{ .x = 0, .y = 4, .width = 8, .height = 8 };
    try std.testing.expectEqual(
        PixelRect{ .x = 0, .y = 8, .width = 16, .height = 16 },
        planTextSizing(0, .{ .width = 4, .height = 2 }, metrics, base).?,
    );
    try std.testing.expectEqual(
        PixelRect{ .x = 26, .y = 8, .width = 16, .height = 16 },
        planTextSizing(
            3,
            .{ .width = 4, .height = 2 },
            metrics,
            .{ .x = 25, .y = 4, .width = 8, .height = 8 },
        ).?,
    );
    try std.testing.expectEqual(
        PixelRect{ .x = 16, .y = 12, .width = 8, .height = 8 },
        planTextSizing(0, .{
            .width = 4,
            .height = 2,
            .subscale_n = 1,
            .subscale_d = 2,
            .vertical_align = 2,
            .horizontal_align = 1,
        }, metrics, base).?,
    );
    try std.testing.expectEqual(
        PixelRect{ .x = 8, .y = 16, .width = 32, .height = 32 },
        clusterCellRect(1, 1, .single_width, .{ .width = 4, .height = 2 }, metrics).?,
    );
    try std.testing.expectEqual(
        PixelRect{ .x = 24, .y = 16, .width = 8, .height = 16 },
        planCell(1, 3, .single_width, metrics).?,
    );

    var cells: [8]terminal.Cell = @splat(testCell('x'));
    for (&cells, 0..) |*cell, index| {
        cell.sizing = .{
            .width = 4,
            .height = 2,
            .x = @intCast(index % 4),
            .y = @intCast(index / 4),
        };
    }
    var cursor = testCursor();
    cursor.visible = true;
    cursor.shape = .block;
    cursor.row = 1;
    cursor.col = 2;
    const geometry = [_]terminal.LineGeometry{ .single_width, .single_width };
    const work = Submission{
        .generation = 1,
        .rows = 2,
        .cols = 4,
        .cells = &cells,
        .row_geometry = &geometry,
        .cursor = cursor,
        .size = .{ .width = 32, .height = 32 },
    };
    try std.testing.expect(cursorBlockCovers(work, 0, 0));
    try std.testing.expect(cursorBlockCovers(work, 1, 3));
    const native_metrics = text.CellMetrics{ .width_px = 8, .height_px = 20, .baseline_px = 16 };
    const raster = PixelRect{ .x = 0, .y = 3, .width = 8, .height = 13 };
    const scale_two = planTextSizing(0, .{ .width = 2, .height = 2 }, native_metrics, raster).?;
    const scale_two_clip = clusterCellRect(
        0,
        0,
        .single_width,
        .{ .width = 2, .height = 2 },
        native_metrics,
    ).?;
    try std.testing.expectEqual(scale_two, intersectRect(scale_two, scale_two_clip).?);
    const scale_three = planTextSizing(0, .{ .width = 3, .height = 3 }, native_metrics, raster).?;
    const scale_three_clip = clusterCellRect(
        0,
        0,
        .single_width,
        .{ .width = 3, .height = 3 },
        native_metrics,
    ).?;
    try std.testing.expectEqual(PixelRect{ .x = 0, .y = 9, .width = 24, .height = 39 }, scale_three);
    try std.testing.expectEqual(scale_three, intersectRect(scale_three, scale_three_clip).?);
}

test "decoration patterns are bounded and deterministic" {
    try std.testing.expectEqual(@as(?u16, 0), decorationRise(.curly, 0, 2));
    try std.testing.expectEqual(@as(?u16, 2), decorationRise(.curly, 2, 2));
    try std.testing.expectEqual(@as(?u16, 0), decorationRise(.dotted, 1, 2));
    try std.testing.expectEqual(@as(?u16, null), decorationRise(.dotted, 2, 2));
    try std.testing.expectEqual(@as(?u16, 0), decorationRise(.dashed, 5, 2));
    try std.testing.expectEqual(@as(?u16, null), decorationRise(.dashed, 6, 2));
    try std.testing.expectEqual(@as(?u16, null), decorationRise(.single, 0, 2));
}

test "CPU clipping preserves complete quads and clips every odd pixel edge" {
    const size = PixelSize{ .width = 45, .height = 31 };
    const color = terminal.Rgb{ .r = 1, .g = 2, .b = 3 };
    const rect = PixelRect{ .x = 4, .y = 3, .width = 11, .height = 13 };
    const complete = clipQuad(rect, rect, size, color, .{}).?;
    try std.testing.expect(!complete.changed);
    try std.testing.expectEqualSlices(
        Vertex,
        &quadVertices(rect.x, rect.y, rect.width, rect.height, size, color),
        &complete.vertices,
    );

    const cases = [_]struct {
        clip: PixelRect,
        u0: f32,
        v0: f32,
        u1: f32,
        v1: f32,
    }{
        .{ .clip = .{ .x = 5, .y = 3, .width = 10, .height = 13 }, .u0 = 1.0 / 11.0, .v0 = 0, .u1 = 1, .v1 = 1 },
        .{ .clip = .{ .x = 4, .y = 4, .width = 11, .height = 12 }, .u0 = 0, .v0 = 1.0 / 13.0, .u1 = 1, .v1 = 1 },
        .{ .clip = .{ .x = 4, .y = 3, .width = 10, .height = 13 }, .u0 = 0, .v0 = 0, .u1 = 10.0 / 11.0, .v1 = 1 },
        .{ .clip = .{ .x = 4, .y = 3, .width = 11, .height = 12 }, .u0 = 0, .v0 = 0, .u1 = 1, .v1 = 12.0 / 13.0 },
    };
    for (cases) |case| {
        const clipped = clipQuad(rect, case.clip, size, color, .{}).?;
        try std.testing.expect(clipped.changed);
        try expectQuadUv(clipped.vertices, case.u0, case.v0, case.u1, case.v1);
    }
    const atlas_uv = TextureUv{ .left = 0.25, .top = 0.125, .right = 0.75, .bottom = 0.625 };
    const atlas_clipped = clipQuad(rect, cases[0].clip, size, color, atlas_uv).?;
    try expectQuadUv(
        atlas_clipped.vertices,
        0.25 + 0.5 / 11.0,
        0.125,
        0.75,
        0.625,
    );
    try std.testing.expect(clipQuad(
        rect,
        .{ .x = 20, .y = 20, .width = 2, .height = 2 },
        size,
        color,
        .{},
    ) == null);
}

test "CPU clipping preserves DEC OSC 66 decoration and cursor geometry" {
    const size = PixelSize{ .width = 90, .height = 75 };
    const metrics = text.CellMetrics{ .width_px = 9, .height_px = 15, .baseline_px = 11 };
    const color = terminal.Rgb{ .r = 4, .g = 5, .b = 6 };

    const dec = planContent(
        2,
        1,
        .double_height_bottom,
        .normal,
        metrics,
        .{ .x = 9, .y = 2, .width = 7, .height = 9 },
    ).?;
    const dec_clip = planCell(2, 1, .double_height_bottom, metrics).?;
    const clipped_dec = clipQuad(dec, dec_clip, size, color, .{}).?;
    try std.testing.expect(clipped_dec.changed);
    try std.testing.expect(clipped_dec.vertices[0].v > 0);
    try std.testing.expectEqual(@as(f32, 1), clipped_dec.vertices[1].v);

    const sized = planTextSizing(
        1,
        .{ .width = 3, .height = 2 },
        metrics,
        .{ .x = 10, .y = 4, .width = 8, .height = 10 },
    ).?;
    const sized_clip = clusterCellRect(
        0,
        1,
        .single_width,
        .{ .width = 3, .height = 2 },
        metrics,
    ).?;
    const clipped_sized = clipQuad(sized, sized_clip, size, color, .{}).?;
    for (clipped_sized.vertices) |vertex| {
        try std.testing.expect(vertex.u >= 0 and vertex.u <= 1);
        try std.testing.expect(vertex.v >= 0 and vertex.v <= 1);
    }

    const decoration = planContent(
        0,
        1,
        .double_width,
        .raised,
        metrics,
        .{ .x = 9, .y = 12, .width = 9, .height = 1 },
    ).?;
    const cell_clip = planCell(0, 1, .double_width, metrics).?;
    try std.testing.expect(clipQuad(decoration, cell_clip, size, color, .{}) != null);
    const cursor = PixelRect{ .x = 18, .y = 0, .width = 2, .height = 15 };
    try std.testing.expect(!clipQuad(cursor, cell_clip, size, color, .{}).?.changed);
}

test "CPU-clipped same-state quads merge while image crop scissor remains distinct" {
    var batch = try DrawBatch.init(std.testing.allocator);
    defer batch.deinit();
    const size = PixelSize{ .width = 40, .height = 20 };
    const color = terminal.Rgb{ .r = 1, .g = 2, .b = 3 };
    const first = clipQuad(
        .{ .x = -2, .y = 0, .width = 10, .height = 10 },
        .{ .x = 0, .y = 0, .width = 40, .height = 20 },
        size,
        color,
        .{},
    ).?;
    const second = clipQuad(
        .{ .x = 8, .y = 0, .width = 10, .height = 10 },
        .{ .x = 0, .y = 0, .width = 40, .height = 20 },
        size,
        color,
        .{},
    ).?;
    const text_state = DrawState{ .texture = 7, .texture_color = false, .scissor = null };
    try std.testing.expect(batch.stage(first.vertices, text_state));
    try std.testing.expect(batch.stage(second.vertices, text_state));
    try std.testing.expectEqual(@as(usize, 1), batch.command_count);
    try std.testing.expectEqual(@as(usize, 12), batch.commands[0].count);

    const image_clip = PixelRect{ .x = 2, .y = 3, .width = 4, .height = 5 };
    try std.testing.expect(batch.stage(second.vertices, .{
        .texture = 7,
        .texture_color = true,
        .scissor = image_clip,
    }));
    try std.testing.expectEqual(@as(usize, 2), batch.command_count);
    try std.testing.expectEqual(image_clip, batch.commands[1].state.scissor.?);
}

test "surface clipping rejects empty and bounds hostile rectangles" {
    try std.testing.expect(clipToSurface(
        .{ .x = -10, .y = -20, .width = 5, .height = 5 },
        .{ .width = 40, .height = 30 },
    ) == null);
    try std.testing.expectEqual(
        PixelRect{ .x = 0, .y = 0, .width = 7, .height = 9 },
        clipToSurface(
            .{ .x = -3, .y = -2, .width = 10, .height = 11 },
            .{ .width = 40, .height = 30 },
        ).?,
    );
}

test "run scratch owns exact bounds and rolls back every allocation" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        constructRunScratch,
        .{},
    );
    var scratch = try RunScratch.init(std.testing.allocator);
    defer scratch.deinit();
    try std.testing.expectEqual(max_run_scalars, scratch.codepoints.len);
    try std.testing.expectEqual(max_run_scalars, scratch.clusters.len);
    try std.testing.expectEqual(max_run_glyphs, scratch.shaped.len);
    try std.testing.expectEqual(max_run_glyphs, scratch.positioned.len);
    try std.testing.expectEqual(@as(usize, 8_192), run_codepoint_bytes);
    try std.testing.expectEqual(@as(usize, 8_192), run_cluster_bytes);
    try std.testing.expectEqual(@as(usize, 1_572_864), run_shaped_bytes);
    try std.testing.expectEqual(@as(usize, 2_359_296), run_positioned_bytes);
    try std.testing.expectEqual(@as(usize, 3_948_544), run_scratch_bytes);
    try std.testing.expectEqual(max_run_glyphs, scratch.shaper.capacity);
    const borrowed = scratch.borrow();
    try std.testing.expectEqual(@intFromPtr(scratch.codepoints.ptr), @intFromPtr(borrowed.codepoints.ptr));
    try std.testing.expectEqual(@intFromPtr(scratch.positioned.ptr), @intFromPtr(borrowed.positioned.ptr));
}

fn constructRunScratch(allocator: std.mem.Allocator) !void {
    var scratch = try RunScratch.init(allocator);
    scratch.deinit();
}

fn testCell(codepoint: u21) terminal.Cell {
    return .{
        .codepoint = codepoint,
        .combining_len = 0,
        .combining = @splat(0),
        .foreground = .{ .r = 255, .g = 255, .b = 255 },
        .background = .{ .r = 0, .g = 0, .b = 0 },
        .underline_color = .{ .r = 255, .g = 255, .b = 255 },
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
        .underline_style = .none,
        .selected = false,
        .link_id = 0,
    };
}

fn testGlyphKey(codepoint: u21) text.GlyphKey {
    return .{ .generated = .{
        .codepoint = codepoint,
        .width_px = 8,
        .height_px = 16,
        .baseline_px = 12,
    } };
}

fn testRaster(pixels: []u8, width: u16, height: u16) text.Raster {
    std.debug.assert(pixels.len == @as(usize, width) * height);
    return .{
        .allocator = std.testing.allocator,
        .width = width,
        .height = height,
        .left = 0,
        .top = @intCast(height),
        .pixels = pixels,
    };
}

fn testCursor() terminal.Cursor {
    return .{
        .row = 0,
        .col = 0,
        .visible = false,
        .shape = .none,
        .blink = false,
        .color = .{ .r = 0, .g = 0, .b = 0 },
        .text_color = .{ .r = 0, .g = 0, .b = 0 },
    };
}

fn testSubmission(
    cells: []const terminal.Cell,
    geometry: []const terminal.LineGeometry,
    cursor: terminal.Cursor,
) Submission {
    std.debug.assert(geometry.len != 0 and cells.len % geometry.len == 0);
    return .{
        .generation = 1,
        .rows = @intCast(geometry.len),
        .cols = @intCast(cells.len / geometry.len),
        .cells = cells,
        .row_geometry = geometry,
        .cursor = cursor,
        .size = .{ .width = 1_000, .height = 1_000 },
    };
}
