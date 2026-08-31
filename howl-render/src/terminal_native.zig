//! Projects immutable terminal client views through howl-text into bounded native glyph frames.
//!
//! This layer owns presentation derivation only. It neither parses `text_v1` nor
//! retains terminal truth. Every font metric, shape, source-cluster mapping,
//! glyph identity, and alpha raster comes from `howl-text`.

const std = @import("std");
const client = @import("howl_client");
const text = @import("howl_text");

pub const View = client.view;
pub const TextColor = View.TextColor;
pub const Metrics = text.Metrics;

/// Caller-selected memory and packing bounds for one native terminal glyph atlas.
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

/// Caller-selected retained-shaping bounds for one fixed native font set.
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

/// Describes one shaped terminal glyph backed by an atlas generation.
pub const Glyph = struct {
    row: u16,
    column: u16,
    cell_index: u32,
    /// howl-text/HarfBuzz source-cluster identity as the source scalar offset.
    cluster: u32,
    face_index: u8,
    glyph_id: u32,
    pen_x_26_6: i64,
    baseline_y_26_6: i64,
    x_offset_26_6: i32,
    y_offset_26_6: i32,
    x_advance_26_6: i32,
    y_advance_26_6: i32,
    atlas_x: u16,
    atlas_y: u16,
    raster_width: u16,
    raster_height: u16,
    raster_left: i16,
    raster_top: i16,
    style_bits: u16,
    foreground: TextColor,
};

/// Borrows one placement frame and the atlas generation it references.
///
/// `glyphs` borrows caller scratch. `atlas` borrows the cache and remains valid
/// across later cache hits/appends, but becomes invalid immediately after
/// `resetAtlas` or `deinitAtlas`.
pub const Frame = struct {
    revision: u64,
    terminal_revision: u64,
    rows: u16,
    columns: u16,
    metrics: Metrics,
    glyphs: []const Glyph,
    atlas: AtlasView,
};

/// Bounded caller scratch for one atlas-backed projection.
pub const Scratch = struct {
    clusters: []u32,
    shaped: []text.Glyph,
    glyphs: []Glyph,
    /// Temporary storage for one natural howl-text raster on a cache miss.
    raster: []u8,
};

pub const AtlasError = std.mem.Allocator.Error || text.RasterError || error{
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

pub const Error = AtlasError || ShapeCacheError || error{
    InvalidView,
    ClusterLimit,
    GlyphLimit,
    CoordinateOverflow,
};

const AtlasEntry = struct {
    face_index: u8,
    glyph_id: u32,
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

const ShapeCacheImpl = struct {
    allocator: std.mem.Allocator,
    fonts: *text.FontSet,
    shape: *text.ShapeBuffer,
    entries: []ShapeEntry,
    scalars: []u32,
    glyphs: []text.Glyph,
    max_sequence_scalars: u32,
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

const AtlasRaster = struct {
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

/// Reuses bounded exact-sequence shaping and persistent natural alpha rasters
/// while projecting every text-bearing lead cell.
///
/// Cell occupancy, style, color, revision and canonical state remain owned by
/// `howl-client.view`; font metrics, shaping, fallback and raster generation stay
/// owned by `howl-text`. The shape cache and atlas allocate nothing during
/// projection. Neither evicts or resets implicitly; cache-full failures preserve
/// retained state, and `CacheFull`, `AtlasFull`, and `GlyphTooLarge` leave all
/// existing atlas references valid so the caller decides when old frames are dead
/// enough to reset and retry.
pub fn project(
    snapshot: *const View.Snapshot,
    atlas: *Atlas,
    shape_cache: *ShapeCache,
    scratch: Scratch,
) Error!Frame {
    const impl = atlasImpl(atlas);
    const fonts = impl.fonts;
    if (shapeCacheImpl(shape_cache).fonts != fonts) return error.FontSetMismatch;
    const begin = View.begin(snapshot);
    const rows = View.rows(snapshot);
    const cells = View.cells(snapshot);
    const scalars = View.scalars(snapshot);
    if (rows.len != begin.rows) return error.InvalidView;

    const metrics = fonts.metrics();
    var glyph_used: usize = 0;
    for (rows, 0..) |row, row_index| {
        const first = @as(usize, row.cell_offset);
        const count = @as(usize, row.cell_count);
        const end = std.math.add(usize, first, count) catch return error.InvalidView;
        if (end > cells.len or count != begin.columns) return error.InvalidView;

        for (cells[first..end], 0..) |cell, column| {
            if (cell.scalar_count == 0) continue;
            if (cell.x != 0 or cell.y != 0) return error.InvalidView;

            const scalar_first = @as(usize, cell.scalar_offset);
            const scalar_count = @as(usize, cell.scalar_count);
            const scalar_end = std.math.add(usize, scalar_first, scalar_count) catch
                return error.InvalidView;
            if (scalar_end > scalars.len) return error.InvalidView;
            if (scalar_count > scratch.clusters.len) return error.ClusterLimit;
            if (scalar_first > std.math.maxInt(u32)) return error.InvalidView;

            const run = try resolveShape(
                shape_cache,
                scalars[scalar_first..scalar_end],
                scratch.clusters,
                scratch.shaped,
            );
            if (run.glyphs.len > scratch.glyphs.len -| glyph_used)
                return error.GlyphLimit;

            const cell_x_px = std.math.mul(
                i64,
                @as(i64, @intCast(column)),
                @as(i64, metrics.advance_width),
            ) catch return error.CoordinateOverflow;
            const line_top_px = std.math.mul(
                i64,
                @as(i64, @intCast(row_index)),
                @as(i64, metrics.line_height),
            ) catch return error.CoordinateOverflow;
            const baseline_px = std.math.add(
                i64,
                line_top_px,
                @as(i64, metrics.baseline),
            ) catch return error.CoordinateOverflow;
            const cell_x_26_6 = std.math.mul(i64, cell_x_px, 64) catch
                return error.CoordinateOverflow;
            const baseline_y_26_6 = std.math.mul(i64, baseline_px, 64) catch
                return error.CoordinateOverflow;
            const cell_index = std.math.add(usize, first, column) catch
                return error.InvalidView;
            if (cell_index > std.math.maxInt(u32)) return error.InvalidView;

            var pen_x_26_6: i64 = cell_x_26_6;
            var pen_y_26_6: i64 = 0;
            for (run.glyphs) |shaped| {
                const raster = try resolveAtlas(
                    atlas,
                    run.face_index,
                    shaped.id,
                    scratch.raster,
                );
                scratch.glyphs[glyph_used] = .{
                    .row = @intCast(row_index),
                    .column = @intCast(column),
                    .cell_index = @intCast(cell_index),
                    .cluster = try rebaseCluster(shaped.cluster, scalar_first, scalar_count),
                    .face_index = run.face_index,
                    .glyph_id = shaped.id,
                    .pen_x_26_6 = pen_x_26_6,
                    .baseline_y_26_6 = std.math.add(i64, baseline_y_26_6, pen_y_26_6) catch
                        return error.CoordinateOverflow,
                    .x_offset_26_6 = shaped.x_offset,
                    .y_offset_26_6 = shaped.y_offset,
                    .x_advance_26_6 = shaped.x_advance,
                    .y_advance_26_6 = shaped.y_advance,
                    .atlas_x = raster.atlas_x,
                    .atlas_y = raster.atlas_y,
                    .raster_width = raster.width,
                    .raster_height = raster.height,
                    .raster_left = raster.left,
                    .raster_top = raster.top,
                    .style_bits = cell.style_bits,
                    .foreground = cell.foreground,
                };
                glyph_used += 1;
                pen_x_26_6 = std.math.add(i64, pen_x_26_6, shaped.x_advance) catch
                    return error.CoordinateOverflow;
                pen_y_26_6 = std.math.add(i64, pen_y_26_6, shaped.y_advance) catch
                    return error.CoordinateOverflow;
            }
        }
    }

    return .{
        .revision = begin.revision,
        .terminal_revision = begin.terminal_revision,
        .rows = begin.rows,
        .columns = begin.columns,
        .metrics = metrics,
        .glyphs = scratch.glyphs[0..glyph_used],
        .atlas = atlasView(atlas),
    };
}

fn resolveShape(
    cache: *ShapeCache,
    sequence: []const u32,
    cluster_scratch: []u32,
    glyph_scratch: []text.Glyph,
) ShapeCacheError!text.Run {
    const impl = shapeCacheImpl(cache);
    if (sequence.len == 0 or sequence.len > @as(usize, impl.max_sequence_scalars))
        return error.ShapeSequenceLimit;
    const hash = std.hash.Wyhash.hash(
        0x9e3779b97f4a7c15,
        std.mem.sliceAsBytes(sequence),
    );
    for (impl.entries[0..impl.entry_count]) |entry| {
        if (entry.hash != hash or entry.scalar_count != sequence.len) continue;
        const retained = impl.scalars[entry.scalar_offset .. entry.scalar_offset + entry.scalar_count];
        if (!std.mem.eql(u32, retained, sequence)) continue;
        return .{
            .face_index = entry.face_index,
            .glyphs = impl.glyphs[entry.glyph_offset .. entry.glyph_offset + entry.glyph_count],
        };
    }

    if (impl.entry_count == impl.entries.len) return error.ShapeEntryFull;
    if (sequence.len > impl.scalars.len - impl.scalar_count) return error.ShapeScalarFull;
    if (sequence.len > cluster_scratch.len) return error.ShapeSequenceLimit;
    for (cluster_scratch[0..sequence.len], 0..) |*cluster, index| cluster.* = @intCast(index);
    const shaped = try impl.fonts.shape(
        impl.shape,
        .{ .codepoints = sequence, .clusters = cluster_scratch[0..sequence.len] },
        glyph_scratch,
    );
    if (shaped.glyphs.len > impl.glyphs.len - impl.glyph_count)
        return error.ShapeGlyphFull;

    const scalar_offset = impl.scalar_count;
    const glyph_offset = impl.glyph_count;
    @memcpy(impl.scalars[scalar_offset .. scalar_offset + sequence.len], sequence);
    @memcpy(impl.glyphs[glyph_offset .. glyph_offset + shaped.glyphs.len], shaped.glyphs);
    impl.scalar_count += sequence.len;
    impl.glyph_count += shaped.glyphs.len;
    impl.entries[impl.entry_count] = .{
        .hash = hash,
        .scalar_offset = scalar_offset,
        .scalar_count = sequence.len,
        .glyph_offset = glyph_offset,
        .glyph_count = shaped.glyphs.len,
        .face_index = shaped.face_index,
    };
    impl.entry_count += 1;
    return .{
        .face_index = shaped.face_index,
        .glyphs = impl.glyphs[glyph_offset .. glyph_offset + shaped.glyphs.len],
    };
}

fn rebaseCluster(relative: u32, scalar_first: usize, scalar_count: usize) error{InvalidView}!u32 {
    if (@as(usize, relative) >= scalar_count) return error.InvalidView;
    const absolute = std.math.add(usize, scalar_first, @as(usize, relative)) catch return error.InvalidView;
    if (absolute > std.math.maxInt(u32)) return error.InvalidView;
    return @intCast(absolute);
}

fn resolveAtlas(
    atlas: *Atlas,
    face_index: u8,
    glyph_id: u32,
    raster_scratch: []u8,
) AtlasError!AtlasRaster {
    const impl = atlasImpl(atlas);
    for (impl.entries[0..impl.entry_count]) |entry| {
        if (entry.face_index == face_index and entry.glyph_id == glyph_id) {
            return atlasRaster(entry);
        }
    }
    if (impl.entry_count == impl.entries.len) return error.CacheFull;

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

    const pack = try planAtlas(impl, raster.width, raster.height);
    if (raster.width != 0 and raster.height != 0) {
        const width = @as(usize, raster.width);
        const height = @as(usize, raster.height);
        const atlas_width = @as(usize, impl.config.width);
        for (0..height) |row| {
            const source_start = row * width;
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
                impl.pixels[destination .. destination + width],
                raster.pixels[source_start .. source_start + width],
            );
        }
    }
    impl.next_x = pack.next_x;
    impl.shelf_y = pack.shelf_y;
    impl.shelf_height = pack.shelf_height;
    const entry = AtlasEntry{
        .face_index = face_index,
        .glyph_id = glyph_id,
        .atlas_x = @intCast(pack.x),
        .atlas_y = @intCast(pack.y),
        .width = raster.width,
        .height = raster.height,
        .left = raster.left,
        .top = raster.top,
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
