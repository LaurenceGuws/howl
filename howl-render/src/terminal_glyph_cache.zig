//! Private bounded text-shape and alpha-atlas caches for terminal presentation.
//!
//! This module consumes only howl-text. It owns no terminal/client semantics,
//! Canvas resources, host topology, or backend state.

const std = @import("std");
const text = @import("howl_text");
const generated = text.generated;

/// Caller-selected memory and packing bounds for one terminal glyph atlas.
///
/// These values are presentation policy, not terminal state or a stable ABI. The
/// font set supplied at initialization must outlive the atlas and fixes the face
/// set and raster size for every cached key until deinitialization.
pub const AtlasConfig = struct {
    width: u16,
    height: u16,
    entry_capacity: usize,
    /// Empty alpha pixels left after each packed raster on both shelf axes.
    gap: u16 = 1,
};

/// Caller-selected retained-shaping bounds for one fixed howl-text font set.
///
/// Exact scalar sequences are the cache key. Retained glyph clusters are relative
/// to that sequence and are rebased to each immutable view during projection.
pub const ShapeCacheConfig = struct {
    entry_capacity: usize,
    scalar_capacity: usize,
    glyph_capacity: usize,
    max_sequence_scalars: u32,
};

/// Opaque explicitly owned shaped-run cache.
///
/// No returned frame borrows this storage. `resetShapeCache` may therefore forget
/// retained runs without invalidating atlas generations or prior frame placements.
pub const ShapeCache = opaque {};

pub const ShapeCacheUsage = struct {
    entries: usize,
    scalars: usize,
    glyphs: usize,
};

/// Opaque explicitly owned glyph-atlas cache.
///
/// The cache never evicts or recycles storage implicitly. `resetAtlas` is the
/// only operation that invalidates atlas references returned by prior frames.
pub const Atlas = opaque {};

/// Read-only borrowed atlas image for one cache generation.
pub const AtlasView = struct {
    generation: u64,
    width: u16,
    height: u16,
    /// Complete row-major alpha image. Unused pixels are deterministically zero.
    pixels: []const u8,
};

pub const AtlasError = std.mem.Allocator.Error || text.RasterError || generated.Error || error{
    InvalidAtlasConfig,
    CacheFull,
    AtlasFull,
    GlyphTooLarge,
    RasterExtentMismatch,
    GenerationOverflow,
};

pub const ShapeCacheInitError = std.mem.Allocator.Error || text.ShapeBufferInitError || error{
    InvalidShapeCacheConfig,
};

pub const ShapeCacheError = text.ShapeError || error{
    FontSetMismatch,
    ShapeSequenceLimit,
    ShapeEntryFull,
    ShapeScalarFull,
    ShapeGlyphFull,
};

const AtlasKey = union(enum) {
    font: struct {
        face_index: u8,
        glyph_id: u32,
    },
    generated: struct {
        codepoint: u32,
        width: u16,
        height: u16,
        sizing: generated.BoxDrawingSizing,
    },
};

const AtlasEntry = struct {
    key: AtlasKey,
    atlas_x: u16,
    atlas_y: u16,
    width: u16,
    height: u16,
    left: i16,
    top: i16,
};

const ShapeEntry = struct {
    hash: u64,
    scalar_offset: usize,
    scalar_count: usize,
    glyph_offset: usize,
    glyph_count: usize,
    face_index: u8,
};

const printable_ascii_first: u32 = 0x20;
const printable_ascii_last: u32 = 0x7e;
const printable_ascii_count: usize = printable_ascii_last - printable_ascii_first + 1;

pub fn printableAsciiIndex(sequence: []const u32) ?usize {
    if (sequence.len != 1) return null;
    const scalar = sequence[0];
    if (scalar < printable_ascii_first or scalar > printable_ascii_last) return null;
    return @intCast(scalar - printable_ascii_first);
}

const ShapeCacheImpl = struct {
    allocator: std.mem.Allocator,
    fonts: *text.FontSet,
    shape: *text.ShapeBuffer,
    entries: []ShapeEntry,
    scalars: []u32,
    glyphs: []text.Glyph,
    max_sequence_scalars: u32,
    ascii_entries: [printable_ascii_count]?usize = @splat(null),
    entry_count: usize = 0,
    scalar_count: usize = 0,
    glyph_count: usize = 0,
};

const AtlasImpl = struct {
    allocator: std.mem.Allocator,
    fonts: *text.FontSet,
    entries: []AtlasEntry,
    pixels: []u8,
    config: AtlasConfig,
    ascii_entries: [printable_ascii_count]?usize = @splat(null),
    entry_count: usize = 0,
    next_x: usize = 0,
    shelf_y: usize = 0,
    shelf_height: usize = 0,
    generation: u64 = 1,
};

const AtlasPack = struct {
    x: usize,
    y: usize,
    next_x: usize,
    shelf_y: usize,
    shelf_height: usize,
};

pub const AtlasRaster = struct {
    atlas_x: u16,
    atlas_y: u16,
    width: u16,
    height: u16,
    left: i16,
    top: i16,
};

/// Allocates one bounded shaped-run owner for one fixed FontSet.
///
/// All entry/scalar/glyph storage and the reusable HarfBuzz buffer are allocated
/// during construction. Cache hits and misses allocate nothing afterward.
pub fn initShapeCache(
    allocator: std.mem.Allocator,
    fonts: *text.FontSet,
    config: ShapeCacheConfig,
) ShapeCacheInitError!*ShapeCache {
    if (config.entry_capacity == 0 or config.scalar_capacity == 0 or
        config.glyph_capacity == 0 or config.max_sequence_scalars == 0 or
        config.max_sequence_scalars > text.max_codepoints or
        @as(usize, config.max_sequence_scalars) > config.scalar_capacity)
        return error.InvalidShapeCacheConfig;

    const impl = try allocator.create(ShapeCacheImpl);
    errdefer allocator.destroy(impl);
    const entries = try allocator.alloc(ShapeEntry, config.entry_capacity);
    errdefer allocator.free(entries);
    const scalars = try allocator.alloc(u32, config.scalar_capacity);
    errdefer allocator.free(scalars);
    const glyphs = try allocator.alloc(text.Glyph, config.glyph_capacity);
    errdefer allocator.free(glyphs);
    const shape = try text.ShapeBuffer.init(allocator, config.max_sequence_scalars);
    errdefer shape.deinit();
    impl.* = .{
        .allocator = allocator,
        .fonts = fonts,
        .shape = shape,
        .entries = entries,
        .scalars = scalars,
        .glyphs = glyphs,
        .max_sequence_scalars = config.max_sequence_scalars,
    };
    return @ptrCast(impl);
}

pub fn deinitShapeCache(cache: *ShapeCache) void {
    const impl = shapeCacheImpl(cache);
    const allocator = impl.allocator;
    const shape = impl.shape;
    const entries = impl.entries;
    const scalars = impl.scalars;
    const glyphs = impl.glyphs;
    impl.* = undefined;
    shape.deinit();
    allocator.free(glyphs);
    allocator.free(scalars);
    allocator.free(entries);
    allocator.destroy(impl);
}

/// Forgets retained shaped runs without changing the fixed FontSet or atlas.
pub fn resetShapeCache(cache: *ShapeCache) void {
    const impl = shapeCacheImpl(cache);
    impl.entry_count = 0;
    impl.scalar_count = 0;
    impl.glyph_count = 0;
    impl.ascii_entries = @splat(null);
}

pub fn shapeCacheUsage(cache: *const ShapeCache) ShapeCacheUsage {
    const impl = constShapeCacheImpl(cache);
    return .{
        .entries = impl.entry_count,
        .scalars = impl.scalar_count,
        .glyphs = impl.glyph_count,
    };
}

/// Allocates one bounded atlas owner. There are no allocations on cache hits or
/// misses after initialization; misses rasterize through caller scratch.
pub fn initAtlas(
    allocator: std.mem.Allocator,
    fonts: *text.FontSet,
    config: AtlasConfig,
) AtlasError!*Atlas {
    if (config.width == 0 or config.height == 0 or config.entry_capacity == 0)
        return error.InvalidAtlasConfig;
    const pixel_count = std.math.mul(
        usize,
        @as(usize, config.width),
        @as(usize, config.height),
    ) catch return error.InvalidAtlasConfig;

    const impl = try allocator.create(AtlasImpl);
    errdefer allocator.destroy(impl);
    const entries = try allocator.alloc(AtlasEntry, config.entry_capacity);
    errdefer allocator.free(entries);
    const pixels = try allocator.alloc(u8, pixel_count);
    errdefer allocator.free(pixels);
    @memset(pixels, 0);
    impl.* = .{
        .allocator = allocator,
        .fonts = fonts,
        .entries = entries,
        .pixels = pixels,
        .config = config,
    };
    return @ptrCast(impl);
}

/// Releases the atlas. Every prior atlas view and frame becomes invalid.
pub fn deinitAtlas(atlas: *Atlas) void {
    const impl = atlasImpl(atlas);
    const allocator = impl.allocator;
    const entries = impl.entries;
    const pixels = impl.pixels;
    impl.* = undefined;
    allocator.free(pixels);
    allocator.free(entries);
    allocator.destroy(impl);
}

/// Explicitly invalidates every cached glyph and begins a new zeroed generation.
pub fn resetAtlas(atlas: *Atlas) AtlasError!void {
    const impl = atlasImpl(atlas);
    if (impl.generation == std.math.maxInt(u64)) return error.GenerationOverflow;
    impl.generation += 1;
    impl.entry_count = 0;
    impl.ascii_entries = @splat(null);
    impl.next_x = 0;
    impl.shelf_y = 0;
    impl.shelf_height = 0;
    @memset(impl.pixels, 0);
}

pub fn atlasView(atlas: *const Atlas) AtlasView {
    const impl = constAtlasImpl(atlas);
    return .{
        .generation = impl.generation,
        .width = impl.config.width,
        .height = impl.config.height,
        .pixels = impl.pixels,
    };
}

pub fn atlasEntryCount(atlas: *const Atlas) usize {
    return constAtlasImpl(atlas).entry_count;
}

/// Returns the fixed font owner shared by this atlas.
pub fn fontSet(atlas: *const Atlas) *text.FontSet {
    return constAtlasImpl(atlas).fonts;
}

/// Reports whether the shape cache and atlas belong to the same fixed font owner.
pub fn sameFontSet(shape_cache: *const ShapeCache, atlas: *const Atlas) bool {
    return constShapeCacheImpl(shape_cache).fonts == constAtlasImpl(atlas).fonts;
}

/// Returns the caller-fixed maximum scalar sequence accepted by the shape cache.
pub fn maximumSequenceScalars(shape_cache: *const ShapeCache) u32 {
    return constShapeCacheImpl(shape_cache).max_sequence_scalars;
}

/// Returns the fixed atlas pixel extent.
pub fn atlasSize(atlas: *const Atlas) struct { width: u16, height: u16 } {
    const impl = constAtlasImpl(atlas);
    return .{ .width = impl.config.width, .height = impl.config.height };
}

pub fn shapeContextualPrimary(
    cache: *ShapeCache,
    sequence: []const u32,
    cluster_scratch: []u32,
    glyph_scratch: []text.Glyph,
) ShapeCacheError!?text.Run {
    const impl = shapeCacheImpl(cache);
    if (sequence.len < 2 or sequence.len > @as(usize, impl.max_sequence_scalars) or
        sequence.len > cluster_scratch.len)
        return null;
    if ((try impl.fonts.faceFor(sequence)) != 0) return null;
    for (cluster_scratch[0..sequence.len], 0..) |*cluster, index|
        cluster.* = @intCast(index);
    return try impl.fonts.shape(
        impl.shape,
        .{ .codepoints = sequence, .clusters = cluster_scratch[0..sequence.len] },
        glyph_scratch,
    );
}

fn shapeEntryRun(impl: *const ShapeCacheImpl, entry_index: usize) text.Run {
    std.debug.assert(entry_index < impl.entry_count);
    const entry = impl.entries[entry_index];
    return .{
        .face_index = entry.face_index,
        .glyphs = impl.glyphs[entry.glyph_offset .. entry.glyph_offset + entry.glyph_count],
    };
}

pub fn resolveShape(
    cache: *ShapeCache,
    sequence: []const u32,
    cluster_scratch: []u32,
    glyph_scratch: []text.Glyph,
) ShapeCacheError!text.Run {
    const impl = shapeCacheImpl(cache);
    if (sequence.len == 0 or sequence.len > @as(usize, impl.max_sequence_scalars))
        return error.ShapeSequenceLimit;
    const ascii_index = printableAsciiIndex(sequence);
    if (ascii_index) |index| {
        if (impl.ascii_entries[index]) |entry_index| {
            const entry = impl.entries[entry_index];
            std.debug.assert(entry.scalar_count == 1);
            std.debug.assert(impl.scalars[entry.scalar_offset] == sequence[0]);
            return shapeEntryRun(impl, entry_index);
        }
    }
    const hash = std.hash.Wyhash.hash(
        0x9e3779b97f4a7c15,
        std.mem.sliceAsBytes(sequence),
    );
    for (impl.entries[0..impl.entry_count], 0..) |entry, entry_index| {
        if (entry.hash != hash or entry.scalar_count != sequence.len) continue;
        const retained = impl.scalars[entry.scalar_offset .. entry.scalar_offset + entry.scalar_count];
        if (!std.mem.eql(u32, retained, sequence)) continue;
        if (ascii_index) |index| impl.ascii_entries[index] = entry_index;
        return shapeEntryRun(impl, entry_index);
    }

    if (impl.entry_count == impl.entries.len) return error.ShapeEntryFull;
    if (sequence.len > impl.scalars.len - impl.scalar_count) return error.ShapeScalarFull;
    if (sequence.len > cluster_scratch.len) return error.ShapeSequenceLimit;
    for (cluster_scratch[0..sequence.len], 0..) |*cluster, index| cluster.* = @intCast(index);
    const shaped = impl.fonts.shape(
        impl.shape,
        .{ .codepoints = sequence, .clusters = cluster_scratch[0..sequence.len] },
        glyph_scratch,
    ) catch |failure| switch (failure) {
        error.MissingGlyph => replacement: {
            const replacement_codepoints = [_]u32{0xfffd};
            cluster_scratch[0] = 0;
            break :replacement try impl.fonts.shape(
                impl.shape,
                .{ .codepoints = &replacement_codepoints, .clusters = cluster_scratch[0..1] },
                glyph_scratch,
            );
        },
        else => return failure,
    };
    if (shaped.glyphs.len > impl.glyphs.len - impl.glyph_count)
        return error.ShapeGlyphFull;

    const scalar_offset = impl.scalar_count;
    const glyph_offset = impl.glyph_count;
    @memcpy(impl.scalars[scalar_offset .. scalar_offset + sequence.len], sequence);
    @memcpy(impl.glyphs[glyph_offset .. glyph_offset + shaped.glyphs.len], shaped.glyphs);
    impl.scalar_count += sequence.len;
    impl.glyph_count += shaped.glyphs.len;
    const entry_index = impl.entry_count;
    impl.entries[entry_index] = .{
        .hash = hash,
        .scalar_offset = scalar_offset,
        .scalar_count = sequence.len,
        .glyph_offset = glyph_offset,
        .glyph_count = shaped.glyphs.len,
        .face_index = shaped.face_index,
    };
    impl.entry_count += 1;
    if (ascii_index) |index| impl.ascii_entries[index] = entry_index;
    return shapeEntryRun(impl, entry_index);
}

pub fn resolveFontAtlas(
    atlas: *Atlas,
    face_index: u8,
    glyph_id: u32,
    raster_scratch: []u8,
    ascii_index: ?usize,
) AtlasError!AtlasRaster {
    const impl = atlasImpl(atlas);
    const key = AtlasKey{ .font = .{ .face_index = face_index, .glyph_id = glyph_id } };
    if (ascii_index) |index| {
        if (impl.ascii_entries[index]) |entry_index| {
            std.debug.assert(entry_index < impl.entry_count);
            const entry = impl.entries[entry_index];
            std.debug.assert(std.meta.eql(entry.key, key));
            return atlasRaster(entry);
        }
    }
    if (findAtlasIndex(impl, key)) |entry_index| {
        if (ascii_index) |index| impl.ascii_entries[index] = entry_index;
        return atlasRaster(impl.entries[entry_index]);
    }

    var raster_allocator = std.heap.FixedBufferAllocator.init(raster_scratch);
    var raster = try impl.fonts.rasterize(
        raster_allocator.allocator(),
        face_index,
        glyph_id,
    );
    defer raster.deinit();
    const expected = std.math.mul(
        usize,
        @as(usize, raster.width),
        @as(usize, raster.height),
    ) catch return error.RasterExtentMismatch;
    if (expected != raster.pixels.len) return error.RasterExtentMismatch;
    const result = try cacheAtlas(
        impl,
        key,
        raster.width,
        raster.height,
        raster.left,
        raster.top,
        raster.pixels,
    );
    if (ascii_index) |index| {
        std.debug.assert(impl.entry_count != 0);
        impl.ascii_entries[index] = impl.entry_count - 1;
    }
    return result;
}

pub fn resolveGeneratedAtlas(
    atlas: *Atlas,
    codepoint: u32,
    width: u16,
    height: u16,
    sizing: generated.BoxDrawingSizing,
    box_drawing: generated.BoxDrawingConfig,
    raster_scratch: []u8,
) AtlasError!AtlasRaster {
    const impl = atlasImpl(atlas);
    const key = AtlasKey{ .generated = .{
        .codepoint = codepoint,
        .width = width,
        .height = height,
        .sizing = sizing,
    } };
    if (findAtlas(impl, key)) |entry| return atlasRaster(entry);

    const required = std.math.mul(usize, @as(usize, width), @as(usize, height)) catch
        return error.RasterTooLarge;
    if (required > raster_scratch.len) return error.BufferTooSmall;
    const pixels = raster_scratch[0..required];
    const family = generated.classify(codepoint) orelse return error.UnsupportedGlyph;
    switch (family) {
        .box => try generated.rasterizeBox(
            pixels,
            width,
            height,
            codepoint,
            box_drawing,
            sizing,
        ),
        .progress => try generated.rasterizeProgress(
            pixels,
            width,
            height,
            codepoint,
            box_drawing,
            sizing,
        ),
        .branch => if (codepoint == 0xf5ee)
            try generated.rasterize(pixels, width, height, codepoint)
        else
            try generated.rasterizeBranch(
                pixels,
                width,
                height,
                codepoint,
                box_drawing,
                sizing,
            ),
        .powerline => generated.rasterize(pixels, width, height, codepoint) catch |failure| switch (failure) {
            error.InvalidMetrics => try generated.rasterizePowerline(
                pixels,
                width,
                height,
                codepoint,
                box_drawing,
                sizing,
            ),
            else => return failure,
        },
        .block, .braille, .sextant, .octant => try generated.rasterize(pixels, width, height, codepoint),
    }
    return cacheAtlas(impl, key, width, height, 0, 0, pixels);
}

fn findAtlasIndex(impl: *const AtlasImpl, key: AtlasKey) ?usize {
    for (impl.entries[0..impl.entry_count], 0..) |entry, index|
        if (std.meta.eql(entry.key, key)) return index;
    return null;
}

fn findAtlas(impl: *const AtlasImpl, key: AtlasKey) ?AtlasEntry {
    const index = findAtlasIndex(impl, key) orelse return null;
    return impl.entries[index];
}

fn cacheAtlas(
    impl: *AtlasImpl,
    key: AtlasKey,
    width: u16,
    height: u16,
    left: i16,
    top: i16,
    pixels: []const u8,
) AtlasError!AtlasRaster {
    if (impl.entry_count == impl.entries.len) return error.CacheFull;
    const expected = std.math.mul(usize, @as(usize, width), @as(usize, height)) catch
        return error.RasterExtentMismatch;
    if (pixels.len != expected) return error.RasterExtentMismatch;

    const pack = try planAtlas(impl, width, height);
    if (width != 0 and height != 0) {
        const pixel_width = @as(usize, width);
        const pixel_height = @as(usize, height);
        const atlas_width = @as(usize, impl.config.width);
        for (0..pixel_height) |row| {
            const source_start = row * pixel_width;
            const destination_row = std.math.add(usize, pack.y, row) catch
                return error.AtlasFull;
            const destination_start = std.math.mul(
                usize,
                destination_row,
                atlas_width,
            ) catch return error.AtlasFull;
            const destination = std.math.add(usize, destination_start, pack.x) catch
                return error.AtlasFull;
            @memcpy(
                impl.pixels[destination .. destination + pixel_width],
                pixels[source_start .. source_start + pixel_width],
            );
        }
    }
    impl.next_x = pack.next_x;
    impl.shelf_y = pack.shelf_y;
    impl.shelf_height = pack.shelf_height;
    const entry = AtlasEntry{
        .key = key,
        .atlas_x = @intCast(pack.x),
        .atlas_y = @intCast(pack.y),
        .width = width,
        .height = height,
        .left = left,
        .top = top,
    };
    impl.entries[impl.entry_count] = entry;
    impl.entry_count += 1;
    return atlasRaster(entry);
}

fn atlasRaster(entry: AtlasEntry) AtlasRaster {
    return .{
        .atlas_x = entry.atlas_x,
        .atlas_y = entry.atlas_y,
        .width = entry.width,
        .height = entry.height,
        .left = entry.left,
        .top = entry.top,
    };
}

fn planAtlas(impl: *const AtlasImpl, width: u16, height: u16) AtlasError!AtlasPack {
    if (width == 0 or height == 0) {
        return .{
            .x = 0,
            .y = 0,
            .next_x = impl.next_x,
            .shelf_y = impl.shelf_y,
            .shelf_height = impl.shelf_height,
        };
    }
    const atlas_width = @as(usize, impl.config.width);
    const atlas_height = @as(usize, impl.config.height);
    const glyph_width = @as(usize, width);
    const glyph_height = @as(usize, height);
    const gap = @as(usize, impl.config.gap);
    if (glyph_width > atlas_width or glyph_height > atlas_height)
        return error.GlyphTooLarge;

    var x = impl.next_x;
    var y = impl.shelf_y;
    var shelf_height = impl.shelf_height;
    const row_end = std.math.add(usize, x, glyph_width) catch return error.AtlasFull;
    if (x != 0 and row_end > atlas_width) {
        x = 0;
        y = std.math.add(usize, y, shelf_height) catch return error.AtlasFull;
        shelf_height = 0;
    }
    const bottom = std.math.add(usize, y, glyph_height) catch return error.AtlasFull;
    if (bottom > atlas_height) return error.AtlasFull;
    const glyph_end = std.math.add(usize, x, glyph_width) catch return error.AtlasFull;
    const next_x = std.math.add(usize, glyph_end, gap) catch return error.AtlasFull;
    const row_height = std.math.add(usize, glyph_height, gap) catch return error.AtlasFull;
    return .{
        .x = x,
        .y = y,
        .next_x = next_x,
        .shelf_y = y,
        .shelf_height = @max(shelf_height, row_height),
    };
}

fn shapeCacheImpl(cache: *ShapeCache) *ShapeCacheImpl {
    return @ptrCast(@alignCast(cache));
}

fn constShapeCacheImpl(cache: *const ShapeCache) *const ShapeCacheImpl {
    return @ptrCast(@alignCast(cache));
}

fn atlasImpl(atlas: *Atlas) *AtlasImpl {
    return @ptrCast(@alignCast(atlas));
}

fn constAtlasImpl(atlas: *const Atlas) *const AtlasImpl {
    return @ptrCast(@alignCast(atlas));
}
