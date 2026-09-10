//! Projects immutable terminal client views through howl-text into bounded Canvas producer updates.
//!
//! This layer owns presentation derivation only. It neither parses `text_v1` nor
//! retains terminal truth. Every font metric, shape, source-cluster mapping,
//! ordinary glyph identity and alpha raster come from `howl-text`; terminal
//! drawing glyphs use the repository's Kitty-derived generated rasterizer.

const std = @import("std");
const client = @import("howl_client");
const text = @import("howl_text");
const canvas = @import("canvas");
const generated = @import("generated_glyphs");

pub const View = client.view;
const TextColor = View.TextColor;
const Metrics = text.Metrics;

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
const ShapeCache = opaque {};

pub const ShapeCacheUsage = struct {
    entries: usize,
    scalars: usize,
    glyphs: usize,
};

/// Opaque explicitly owned glyph-atlas cache.
///
/// The cache never evicts or recycles storage implicitly. `resetAtlas` is the
/// only operation that invalidates atlas references returned by prior frames.
const Atlas = opaque {};

/// Read-only borrowed atlas image for one cache generation.
const AtlasView = struct {
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

/// Fixes every allocation and terminal presentation lattice used by one
/// Canvas producer. The font set supplied to `initContent` must outlive the
/// producer. None of these values are terminal truth or stable ABI.
pub const ContentConfig = struct {
    cell_size: canvas.Size,
    box_drawing: generated.BoxDrawingConfig,
    shape_cache: ShapeCacheConfig,
    atlas: AtlasConfig,
    shaped_capacity: usize,
    raster_bytes: usize,
    command_capacity: usize,
};

/// Supplies topology identity which terminal state cannot own.
///
/// The presentation host issues these values. Terminal presentation combines
/// them with exact cursor target/revision/color facts from the immutable view.
pub const CursorContext = struct {
    pane: u64,
    source: canvas.SourceId,
    visible_set_revision: u64,
    lifecycle_revision: u64,
};

/// Opaque bounded owner of terminal -> Canvas presentation state.
///
/// Returned `canvas.ProducerUpdate` slices borrow this owner and must be applied
/// or copied synchronously before any later Content operation. Canvas/Composer
/// retain their own accepted resource and command copies.
pub const Content = opaque {};

pub const ContentUsage = struct {
    shape: ShapeCacheUsage,
    atlas_entries: usize,
    producer_revision: u64,
    resource_generation: u64,
};

pub const ContentInitError = std.mem.Allocator.Error || ShapeCacheInitError || AtlasError || error{
    InvalidContentConfig,
};

pub const ContentError = AtlasError || ShapeCacheError || error{
    InvalidView,
    InvalidColor,
    InvalidCursorContext,
    InvalidPresentationGeometry,
    CommandLimit,
    ProducerRevisionOverflow,
    ResourceGenerationOverflow,
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

const ContentImpl = struct {
    allocator: std.mem.Allocator,
    fonts: *text.FontSet,
    config: ContentConfig,
    shape_cache: *ShapeCache,
    atlas: *Atlas,
    clusters: []u32,
    shaped: []text.Glyph,
    raster: []u8,
    commands: []canvas.Input,
    uploads: [1]canvas.ResourceUpload = undefined,
    producer_revision: u64 = 0,
    resource_generation: u64 = 0,
    published_atlas_generation: u64 = 0,
    published_atlas_entries: usize = 0,
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
fn initShapeCache(
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

fn deinitShapeCache(cache: *ShapeCache) void {
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
fn resetShapeCache(cache: *ShapeCache) void {
    const impl = shapeCacheImpl(cache);
    impl.entry_count = 0;
    impl.scalar_count = 0;
    impl.glyph_count = 0;
}

fn shapeCacheUsage(cache: *const ShapeCache) ShapeCacheUsage {
    const impl = constShapeCacheImpl(cache);
    return .{
        .entries = impl.entry_count,
        .scalars = impl.scalar_count,
        .glyphs = impl.glyph_count,
    };
}

/// Allocates one bounded atlas owner. There are no allocations on cache hits or
/// misses after initialization; misses rasterize through caller scratch.
fn initAtlas(
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
fn deinitAtlas(atlas: *Atlas) void {
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
fn resetAtlas(atlas: *Atlas) AtlasError!void {
    const impl = atlasImpl(atlas);
    if (impl.generation == std.math.maxInt(u64)) return error.GenerationOverflow;
    impl.generation += 1;
    impl.entry_count = 0;
    impl.next_x = 0;
    impl.shelf_y = 0;
    impl.shelf_height = 0;
    @memset(impl.pixels, 0);
}

fn atlasView(atlas: *const Atlas) AtlasView {
    const impl = constAtlasImpl(atlas);
    return .{
        .generation = impl.generation,
        .width = impl.config.width,
        .height = impl.config.height,
        .pixels = impl.pixels,
    };
}

fn atlasEntryCount(atlas: *const Atlas) usize {
    return constAtlasImpl(atlas).entry_count;
}

/// Allocates one bounded terminal Canvas producer.
///
/// The producer owns presentation caches and fixed scratch only. `fonts` remains
/// caller-owned and must outlive Content. Every later Content operation is
/// allocation-free.
pub fn initContent(
    allocator: std.mem.Allocator,
    fonts: *text.FontSet,
    config: ContentConfig,
) ContentInitError!*Content {
    if (config.cell_size.width == 0 or config.cell_size.height == 0 or
        config.shaped_capacity == 0 or config.raster_bytes == 0 or
        config.command_capacity == 0)
        return error.InvalidContentConfig;

    const impl = try allocator.create(ContentImpl);
    errdefer allocator.destroy(impl);
    const shape_cache = try initShapeCache(allocator, fonts, config.shape_cache);
    errdefer deinitShapeCache(shape_cache);
    const atlas = try initAtlas(allocator, fonts, config.atlas);
    errdefer deinitAtlas(atlas);
    const clusters = try allocator.alloc(u32, @intCast(config.shape_cache.max_sequence_scalars));
    errdefer allocator.free(clusters);
    const shaped = try allocator.alloc(text.Glyph, config.shaped_capacity);
    errdefer allocator.free(shaped);
    const raster = try allocator.alloc(u8, config.raster_bytes);
    errdefer allocator.free(raster);
    const commands = try allocator.alloc(canvas.Input, config.command_capacity);
    errdefer allocator.free(commands);

    impl.* = .{
        .allocator = allocator,
        .fonts = fonts,
        .config = config,
        .shape_cache = shape_cache,
        .atlas = atlas,
        .clusters = clusters,
        .shaped = shaped,
        .raster = raster,
        .commands = commands,
    };
    return @ptrCast(impl);
}

/// Releases one terminal Canvas producer and every private presentation cache.
pub fn deinitContent(content: *Content) void {
    const impl = contentImpl(content);
    const allocator = impl.allocator;
    const shape_cache = impl.shape_cache;
    const atlas = impl.atlas;
    const clusters = impl.clusters;
    const shaped = impl.shaped;
    const raster = impl.raster;
    const commands = impl.commands;
    impl.* = undefined;
    allocator.free(commands);
    allocator.free(raster);
    allocator.free(shaped);
    allocator.free(clusters);
    deinitAtlas(atlas);
    deinitShapeCache(shape_cache);
    allocator.destroy(impl);
}

/// Explicitly forgets private shaping and raster caches.
///
/// Previously accepted Canvas/Composer state remains independent. The next
/// successful update which references raster content publishes a newer resource
/// generation. No cache reset occurs implicitly.
pub fn resetContentCaches(content: *Content) AtlasError!void {
    const impl = contentImpl(content);
    try resetAtlas(impl.atlas);
    resetShapeCache(impl.shape_cache);
}

pub fn contentUsage(content: *const Content) ContentUsage {
    const impl = constContentImpl(content);
    return .{
        .shape = shapeCacheUsage(impl.shape_cache),
        .atlas_entries = atlasEntryCount(impl.atlas),
        .producer_revision = impl.producer_revision,
        .resource_generation = impl.resource_generation,
    };
}

/// Projects one immutable terminal view into one complete Canvas producer state.
///
/// `cursor_context` is optional because terminal state does not own pane,
/// Composer-source, visible-set, or lifecycle identity. When supplied, those
/// host facts are combined with exact terminal cursor target/revision/color facts
/// into one `canvas.CursorBinding`. Returned slices borrow Content until the next
/// Content operation and must be synchronously copied or applied before then.
pub fn takeContentUpdate(
    content: *Content,
    snapshot: *const View.Snapshot,
    cursor_context: ?CursorContext,
) ContentError!canvas.ProducerUpdate {
    const impl = contentImpl(content);
    const surface = try contentSurfaceSize(View.begin(snapshot), impl.config.cell_size);
    const projection = try buildContentCommands(
        snapshot,
        impl.atlas,
        impl.shape_cache,
        surface,
        impl.commands,
        impl.config.cell_size,
        impl.config.box_drawing,
        impl.clusters,
        impl.shaped,
        impl.raster,
    );
    const atlas = atlasView(impl.atlas);
    const atlas_entries = atlasEntryCount(impl.atlas);
    const atlas_changed = atlas.generation != impl.published_atlas_generation or
        atlas_entries != impl.published_atlas_entries;

    var next_resource_generation = impl.resource_generation;
    const publish_atlas = projection.has_raster and
        (next_resource_generation == 0 or atlas_changed);
    if (publish_atlas) {
        if (next_resource_generation == std.math.maxInt(u64))
            return error.ResourceGenerationOverflow;
        next_resource_generation += 1;
    }
    const resource = if (projection.has_raster)
        contentResource(next_resource_generation)
    else
        null;
    if (resource) |value|
        bindContentResource(impl.commands[0..projection.command_count], value);

    const cursor_binding = try contentCursorBinding(
        snapshot,
        surface,
        impl.config.cell_size,
        cursor_context,
    );
    if (impl.producer_revision == std.math.maxInt(u64))
        return error.ProducerRevisionOverflow;
    const next_producer_revision = impl.producer_revision + 1;

    const uploads: []const canvas.ResourceUpload = if (publish_atlas) blk: {
        const value = resource orelse return error.InvalidPresentationGeometry;
        impl.uploads[0] = .{
            .resource = value,
            .format = .alpha8,
            .pixels = .{
                .bytes = atlas.pixels,
                .width = atlas.width,
                .height = atlas.height,
                .stride = atlas.width,
            },
        };
        break :blk impl.uploads[0..1];
    } else &.{};

    impl.producer_revision = next_producer_revision;
    if (publish_atlas) {
        impl.resource_generation = next_resource_generation;
        impl.published_atlas_generation = atlas.generation;
        impl.published_atlas_entries = atlas_entries;
    }
    return .{
        .revision = @fromBackingInt(@intCast(next_producer_revision)),
        .uploads = uploads,
        .removals = &.{},
        .commands = impl.commands[0..projection.command_count],
        .cursor_binding = cursor_binding,
    };
}

const content_style_dim: u16 = 1 << 1;
const content_style_reverse: u16 = 1 << 5;
const content_style_invisible: u16 = 1 << 6;
const content_style_underline: u16 = 1 << 7;
const content_style_strike: u16 = 1 << 8;
const maximum_operator_run_cells: usize = 4;

const ContentCellColors = struct {
    foreground: canvas.Color,
    background: canvas.Color,
    underline: canvas.Color,
};

fn contentSurfaceSize(begin: *const View.Begin, cell_size: canvas.Size) ContentError!canvas.Size {
    const width = std.math.mul(
        u32,
        @as(u32, begin.columns),
        @as(u32, cell_size.width),
    ) catch return error.InvalidPresentationGeometry;
    const height = std.math.mul(
        u32,
        @as(u32, begin.rows),
        @as(u32, cell_size.height),
    ) catch return error.InvalidPresentationGeometry;
    if (width == 0 or height == 0 or
        width > std.math.maxInt(u16) or height > std.math.maxInt(u16))
        return error.InvalidPresentationGeometry;
    return .{ .width = @intCast(width), .height = @intCast(height) };
}

fn contentSurfaceRect(size: canvas.Size) canvas.Rect {
    return .{ .x = 0, .y = 0, .width = size.width, .height = size.height };
}

fn contentCellRect(row: usize, column: usize, cell_size: canvas.Size) ContentError!canvas.Rect {
    const x = std.math.mul(usize, column, @as(usize, cell_size.width)) catch
        return error.InvalidPresentationGeometry;
    const y = std.math.mul(usize, row, @as(usize, cell_size.height)) catch
        return error.InvalidPresentationGeometry;
    return .{
        .x = std.math.cast(i32, x) orelse return error.InvalidPresentationGeometry,
        .y = std.math.cast(i32, y) orelse return error.InvalidPresentationGeometry,
        .width = cell_size.width,
        .height = cell_size.height,
    };
}

const ContentCellSizing = struct {
    origin: canvas.Rect,
    allocation: canvas.Rect,
    scale_n: u16,
    scale_d: u16,
    offset_x: u16,
    offset_y: u16,
};

fn contentCellSizing(
    row: usize,
    column: usize,
    cell: View.Cell,
    cell_size: canvas.Size,
) ContentError!ContentCellSizing {
    if (cell.width == 0 or cell.height == 0 or cell.width % cell.height != 0)
        return error.InvalidView;
    const base_width_cells = cell.width / cell.height;
    const base_width = std.math.mul(
        u16,
        cell_size.width,
        @as(u16, base_width_cells),
    ) catch return error.InvalidPresentationGeometry;
    const allocation_width = std.math.mul(
        u16,
        cell_size.width,
        @as(u16, cell.width),
    ) catch return error.InvalidPresentationGeometry;
    const allocation_height = std.math.mul(
        u16,
        cell_size.height,
        @as(u16, cell.height),
    ) catch return error.InvalidPresentationGeometry;
    var scale_n: u16 = cell.height;
    var scale_d: u16 = 1;
    if (cell.subscale_n != 0 and cell.subscale_d != 0 and
        cell.subscale_n < cell.subscale_d)
    {
        scale_n = std.math.mul(
            u16,
            scale_n,
            @as(u16, cell.subscale_n),
        ) catch return error.InvalidPresentationGeometry;
        scale_d = cell.subscale_d;
    }
    const scaled_width = try contentScaleExtent(base_width, scale_n, scale_d);
    const scaled_height = try contentScaleExtent(cell_size.height, scale_n, scale_d);
    if (scaled_width > allocation_width or scaled_height > allocation_height)
        return error.InvalidPresentationGeometry;
    const remaining_x = allocation_width - scaled_width;
    const remaining_y = allocation_height - scaled_height;
    const offset_x: u16 = switch (cell.horizontal_align) {
        2 => remaining_x / 2,
        1, 3 => remaining_x,
        else => 0,
    };
    const offset_y: u16 = switch (cell.vertical_align) {
        1 => remaining_y,
        2 => remaining_y / 2,
        else => 0,
    };
    const lead = try contentCellRect(row, column, cell_size);
    return .{
        .origin = .{
            .x = lead.x,
            .y = lead.y,
            .width = base_width,
            .height = cell_size.height,
        },
        .allocation = .{
            .x = lead.x,
            .y = lead.y,
            .width = allocation_width,
            .height = allocation_height,
        },
        .scale_n = scale_n,
        .scale_d = scale_d,
        .offset_x = offset_x,
        .offset_y = offset_y,
    };
}

fn contentScaleExtent(value: u16, numerator: u16, denominator: u16) ContentError!u16 {
    if (value == 0 or numerator == 0 or denominator == 0)
        return error.InvalidPresentationGeometry;
    const product = std.math.mul(u32, value, numerator) catch
        return error.InvalidPresentationGeometry;
    const rounded = std.math.add(u32, product, denominator - 1) catch
        return error.InvalidPresentationGeometry;
    const result = rounded / denominator;
    return std.math.cast(u16, result) orelse error.InvalidPresentationGeometry;
}

fn contentScaleCoordinate(value: i64, numerator: u16, denominator: u16) ContentError!i64 {
    if (numerator == 0 or denominator == 0) return error.InvalidPresentationGeometry;
    const product = std.math.mul(i64, value, numerator) catch
        return error.InvalidPresentationGeometry;
    return @divFloor(product, denominator);
}

fn contentCellTransformRect(
    rect: canvas.Rect,
    sizing: ContentCellSizing,
) ContentError!canvas.Rect {
    const local_x = std.math.sub(i64, rect.x, sizing.origin.x) catch
        return error.InvalidPresentationGeometry;
    const local_y = std.math.sub(i64, rect.y, sizing.origin.y) catch
        return error.InvalidPresentationGeometry;
    const scaled_x = try contentScaleCoordinate(local_x, sizing.scale_n, sizing.scale_d);
    const scaled_y = try contentScaleCoordinate(local_y, sizing.scale_n, sizing.scale_d);
    const x = std.math.add(
        i64,
        @as(i64, sizing.origin.x) + sizing.offset_x,
        scaled_x,
    ) catch return error.InvalidPresentationGeometry;
    const y = std.math.add(
        i64,
        @as(i64, sizing.origin.y) + sizing.offset_y,
        scaled_y,
    ) catch return error.InvalidPresentationGeometry;
    return .{
        .x = std.math.cast(i32, x) orelse return error.InvalidPresentationGeometry,
        .y = std.math.cast(i32, y) orelse return error.InvalidPresentationGeometry,
        .width = try contentScaleExtent(rect.width, sizing.scale_n, sizing.scale_d),
        .height = try contentScaleExtent(rect.height, sizing.scale_n, sizing.scale_d),
    };
}

const ContentLineScale = struct {
    x: u16,
    y: u16,
    bottom_half: bool,
};

fn contentLineScale(geometry: u8) ContentError!ContentLineScale {
    return switch (geometry) {
        0 => .{ .x = 1, .y = 1, .bottom_half = false },
        1 => .{ .x = 2, .y = 1, .bottom_half = false },
        2 => .{ .x = 2, .y = 2, .bottom_half = false },
        3 => .{ .x = 2, .y = 2, .bottom_half = true },
        else => error.InvalidView,
    };
}

fn contentLineColumnCount(columns: u16, geometry: u8) ContentError!u16 {
    const scale = try contentLineScale(geometry);
    return if (scale.x == 1) columns else @max(@as(u16, 1), columns / 2);
}

fn contentLineTransformRect(
    rect: canvas.Rect,
    row: usize,
    geometry: u8,
    cell_size: canvas.Size,
) ContentError!canvas.Rect {
    const scale = try contentLineScale(geometry);
    const row_y = std.math.mul(i64, @as(i64, @intCast(row)), @as(i64, cell_size.height)) catch
        return error.InvalidPresentationGeometry;
    const local_y = std.math.sub(i64, rect.y, row_y) catch
        return error.InvalidPresentationGeometry;
    var y = std.math.add(
        i64,
        row_y,
        std.math.mul(i64, local_y, scale.y) catch return error.InvalidPresentationGeometry,
    ) catch return error.InvalidPresentationGeometry;
    if (scale.bottom_half)
        y = std.math.sub(i64, y, cell_size.height) catch return error.InvalidPresentationGeometry;
    const x = std.math.mul(i64, rect.x, scale.x) catch
        return error.InvalidPresentationGeometry;
    const width = std.math.mul(u16, rect.width, scale.x) catch
        return error.InvalidPresentationGeometry;
    const height = std.math.mul(u16, rect.height, scale.y) catch
        return error.InvalidPresentationGeometry;
    return .{
        .x = std.math.cast(i32, x) orelse return error.InvalidPresentationGeometry,
        .y = std.math.cast(i32, y) orelse return error.InvalidPresentationGeometry,
        .width = width,
        .height = height,
    };
}

fn contentIntersectRects(left: canvas.Rect, right: canvas.Rect) ?canvas.Rect {
    const x1 = @max(@as(i64, left.x), @as(i64, right.x));
    const y1 = @max(@as(i64, left.y), @as(i64, right.y));
    const x2 = @min(
        @as(i64, left.x) + left.width,
        @as(i64, right.x) + right.width,
    );
    const y2 = @min(
        @as(i64, left.y) + left.height,
        @as(i64, right.y) + right.height,
    );
    if (x2 <= x1 or y2 <= y1) return null;
    return .{
        .x = @intCast(x1),
        .y = @intCast(y1),
        .width = @intCast(x2 - x1),
        .height = @intCast(y2 - y1),
    };
}

fn contentLineClip(
    clip: canvas.Rect,
    row: usize,
    geometry: u8,
    cell_size: canvas.Size,
    surface: canvas.Size,
) ContentError!?canvas.Rect {
    const transformed = try contentLineTransformRect(clip, row, geometry, cell_size);
    var row_strip = try contentCellRect(row, 0, cell_size);
    row_strip.width = surface.width;
    const visible = contentIntersectRects(transformed, row_strip) orelse return null;
    return contentIntersectRects(visible, contentSurfaceRect(surface));
}

fn contentCellVisibleClip(
    sizing: ContentCellSizing,
    row: usize,
    geometry: u8,
    cell_size: canvas.Size,
    surface: canvas.Size,
) ContentError!?canvas.Rect {
    if (sizing.allocation.height == cell_size.height or geometry != 0)
        return contentLineClip(sizing.allocation, row, geometry, cell_size, surface);
    const transformed = try contentLineTransformRect(
        sizing.allocation,
        row,
        geometry,
        cell_size,
    );
    return contentIntersectRects(transformed, contentSurfaceRect(surface));
}

fn contentUsesMulticellAllocation(cell: View.Cell) bool {
    return cell.height > 1 or cell.subscale_n != 0 or cell.subscale_d != 0 or
        cell.vertical_align != 0 or cell.horizontal_align != 0 or
        (cell.width > 1 and !cell.semantic_width);
}

fn contentIsContextualOperatorCell(
    cell: View.Cell,
    scalars: []const u32,
) ContentError!bool {
    if (cell.scalar_count != 1 or cell.width != 1 or cell.height != 1 or
        cell.x != 0 or cell.y != 0 or cell.subscale_n != 0 or cell.subscale_d != 0 or
        cell.vertical_align != 0 or cell.horizontal_align != 0 or cell.semantic_width or
        cell.font != 0 or cell.baseline != 0 or cell.style_bits & content_style_invisible != 0)
        return false;
    const index = @as(usize, cell.scalar_offset);
    if (index >= scalars.len) return error.InvalidView;
    const value = scalars[index];
    return value >= 0x21 and value <= 0x2f or
        value >= 0x3a and value <= 0x40 or
        value >= 0x5b and value <= 0x60 or
        value >= 0x7b and value <= 0x7e;
}

fn contentSameContextualRendition(left: View.Cell, right: View.Cell) bool {
    return left.style_bits == right.style_bits and left.font == right.font and
        left.baseline == right.baseline and left.underline_style == right.underline_style and
        left.protection == right.protection and left.link_id == right.link_id and
        std.meta.eql(left.foreground, right.foreground) and
        std.meta.eql(left.background, right.background) and
        std.meta.eql(left.underline_color, right.underline_color);
}

fn contentContextualClustersPreserveCells(glyphs: []const text.Glyph, cell_count: usize) bool {
    if (cell_count < 2 or cell_count > maximum_operator_run_cells) return false;
    var seen: u8 = 0;
    for (glyphs) |glyph| {
        if (glyph.cluster >= cell_count) return false;
        seen |= @as(u8, 1) << @intCast(glyph.cluster);
    }
    const expected = (@as(u8, 1) << @intCast(cell_count)) - 1;
    return seen == expected;
}

fn contentFontVisibleClip(
    cell: View.Cell,
    sizing: ContentCellSizing,
    row: usize,
    geometry: u8,
    cell_size: canvas.Size,
    surface: canvas.Size,
) ContentError!?canvas.Rect {
    if (contentUsesMulticellAllocation(cell))
        return contentCellVisibleClip(sizing, row, geometry, cell_size, surface);
    var row_strip = try contentCellRect(row, 0, cell_size);
    row_strip.width = surface.width;
    return contentLineClip(row_strip, row, geometry, cell_size, surface);
}

fn appendContentLineSolid(
    output: []canvas.Input,
    used: *usize,
    rect: canvas.Rect,
    clip: canvas.Rect,
    color: canvas.Color,
    row: usize,
    geometry: u8,
    cell_size: canvas.Size,
    surface: canvas.Size,
) ContentError!void {
    const visible_clip = try contentLineClip(clip, row, geometry, cell_size, surface) orelse return;
    try appendContentSolid(
        output,
        used,
        try contentLineTransformRect(rect, row, geometry, cell_size),
        visible_clip,
        color,
    );
}

fn appendContentCellSolid(
    output: []canvas.Input,
    used: *usize,
    rect: canvas.Rect,
    color: canvas.Color,
    sizing: ContentCellSizing,
    row: usize,
    geometry: u8,
    cell_size: canvas.Size,
    surface: canvas.Size,
) ContentError!void {
    const visible_clip = try contentCellVisibleClip(
        sizing,
        row,
        geometry,
        cell_size,
        surface,
    ) orelse return;
    const sized_rect = try contentCellTransformRect(rect, sizing);
    try appendContentSolid(
        output,
        used,
        try contentLineTransformRect(sized_rect, row, geometry, cell_size),
        visible_clip,
        color,
    );
}

fn richColor(value: client.rich.Rgba) canvas.Color {
    return .{ .r = value.r, .g = value.g, .b = value.b, .a = value.a };
}

fn contentColor(
    value: TextColor,
    presentation: *const View.Presentation,
    foreground: bool,
) ContentError!canvas.Color {
    return switch (value.kind) {
        .default => richColor(if (foreground) presentation.foreground else presentation.background),
        .indexed => blk: {
            if (value.value >= presentation.palette.len) return error.InvalidColor;
            break :blk richColor(presentation.palette[value.value]);
        },
        .rgb => .{
            .r = @intCast((value.value >> 16) & 0xff),
            .g = @intCast((value.value >> 8) & 0xff),
            .b = @intCast(value.value & 0xff),
            .a = 0xff,
        },
    };
}

fn dimContentColor(value: canvas.Color) canvas.Color {
    var result = value;
    result.a = @intCast((@as(u16, value.a) * 55 + 50) / 100);
    return result;
}

fn contentCellColors(
    cell: View.Cell,
    presentation: *const View.Presentation,
) ContentError!ContentCellColors {
    var foreground = try contentColor(cell.foreground, presentation, true);
    var background = try contentColor(cell.background, presentation, false);
    if (cell.style_bits & content_style_reverse != 0)
        std.mem.swap(canvas.Color, &foreground, &background);
    if (presentation.reverse_screen)
        std.mem.swap(canvas.Color, &foreground, &background);
    if (cell.style_bits & content_style_dim != 0)
        foreground = dimContentColor(foreground);
    return .{
        .foreground = foreground,
        .background = background,
        .underline = try contentColor(cell.underline_color, presentation, true),
    };
}

fn appendContentInput(
    output: []canvas.Input,
    used: *usize,
    value: canvas.Input,
) ContentError!void {
    if (used.* >= output.len) return error.CommandLimit;
    output[used.*] = value;
    used.* += 1;
}

fn appendContentSolid(
    output: []canvas.Input,
    used: *usize,
    rect: canvas.Rect,
    clip: canvas.Rect,
    color: canvas.Color,
) ContentError!void {
    try appendContentInput(output, used, .{ .solid = .{
        .rect = rect,
        .clip = clip,
        .color = color,
    } });
}

fn appendContentUnderline(
    output: []canvas.Input,
    used: *usize,
    clip: canvas.Rect,
    y: i32,
    thickness: u16,
    style: u8,
    color: canvas.Color,
    sizing: ContentCellSizing,
    row: usize,
    geometry: u8,
    cell_size: canvas.Size,
    surface: canvas.Size,
) ContentError!void {
    const height = @max(@as(u16, 1), thickness);
    switch (style) {
        1 => {
            try appendContentCellSolid(output, used, .{
                .x = clip.x,
                .y = y,
                .width = clip.width,
                .height = height,
            }, color, sizing, row, geometry, cell_size, surface);
            const second_y = std.math.add(
                i32,
                y,
                @as(i32, height) + 1,
            ) catch return error.InvalidPresentationGeometry;
            try appendContentCellSolid(output, used, .{
                .x = clip.x,
                .y = second_y,
                .width = clip.width,
                .height = height,
            }, color, sizing, row, geometry, cell_size, surface);
        },
        2 => for (0..clip.width) |offset| {
            const x = std.math.add(
                i32,
                clip.x,
                @as(i32, @intCast(offset)),
            ) catch return error.InvalidPresentationGeometry;
            const wave_y = std.math.add(
                i32,
                y,
                @as(i32, @intCast(offset & 1)),
            ) catch return error.InvalidPresentationGeometry;
            try appendContentCellSolid(output, used, .{
                .x = x,
                .y = wave_y,
                .width = 1,
                .height = 1,
            }, color, sizing, row, geometry, cell_size, surface);
        },
        3 => {
            var offset: usize = 0;
            while (offset < clip.width) : (offset += 2) {
                const x = std.math.add(
                    i32,
                    clip.x,
                    @as(i32, @intCast(offset)),
                ) catch return error.InvalidPresentationGeometry;
                try appendContentCellSolid(output, used, .{
                    .x = x,
                    .y = y,
                    .width = 1,
                    .height = height,
                }, color, sizing, row, geometry, cell_size, surface);
            }
        },
        4 => {
            var offset: usize = 0;
            while (offset < clip.width) : (offset += 5) {
                const x = std.math.add(
                    i32,
                    clip.x,
                    @as(i32, @intCast(offset)),
                ) catch return error.InvalidPresentationGeometry;
                const remaining = @as(usize, clip.width) - offset;
                const width: u16 = @intCast(@min(@as(usize, 3), remaining));
                try appendContentCellSolid(output, used, .{
                    .x = x,
                    .y = y,
                    .width = width,
                    .height = height,
                }, color, sizing, row, geometry, cell_size, surface);
            }
        },
        else => try appendContentCellSolid(output, used, .{
            .x = clip.x,
            .y = y,
            .width = clip.width,
            .height = height,
        }, color, sizing, row, geometry, cell_size, surface),
    }
}

fn fixedContent26_6(value: i64) ContentError!i32 {
    return std.math.cast(i32, @divFloor(value, 64)) orelse
        error.InvalidPresentationGeometry;
}

fn contentLineOffset(metrics: Metrics, cell_size: canvas.Size) i64 {
    const difference = @as(i64, cell_size.height) - @as(i64, metrics.line_height);
    return @divFloor(difference, 2);
}

const ContentProjection = struct {
    command_count: usize,
    has_raster: bool,
};

fn buildContentCommands(
    snapshot: *const View.Snapshot,
    atlas: *Atlas,
    shape_cache: *ShapeCache,
    surface: canvas.Size,
    output: []canvas.Input,
    cell_size: canvas.Size,
    box_drawing: generated.BoxDrawingConfig,
    cluster_scratch: []u32,
    shaped_scratch: []text.Glyph,
    raster_scratch: []u8,
) ContentError!ContentProjection {
    const atlas_impl = atlasImpl(atlas);
    if (shapeCacheImpl(shape_cache).fonts != atlas_impl.fonts)
        return error.FontSetMismatch;
    const begin = View.begin(snapshot);
    const presentation = View.presentation(snapshot);
    const rows = View.rows(snapshot);
    const cells = View.cells(snapshot);
    const scalars = View.scalars(snapshot);
    if (rows.len != begin.rows) return error.InvalidView;

    const metrics = atlas_impl.fonts.metrics();
    const whole = contentSurfaceRect(surface);
    const default_background = richColor(presentation.background);
    const line_offset = contentLineOffset(metrics, cell_size);
    var used: usize = 0;
    try appendContentSolid(output, &used, whole, whole, default_background);

    // Preserve terminal paint ordering: all backgrounds and decorations are
    // established before any glyph mask can overlap a later cell.
    for (rows, 0..) |row, row_index| {
        const first = @as(usize, row.cell_offset);
        const count = @as(usize, row.cell_count);
        const end = std.math.add(usize, first, count) catch return error.InvalidView;
        if (end > cells.len or count != begin.columns) return error.InvalidView;
        const line_columns = try contentLineColumnCount(begin.columns, row.line_geometry);
        for (cells[first..][0..line_columns], 0..) |cell, column| {
            const colors = try contentCellColors(cell, presentation);
            const physical = try contentCellRect(row_index, column, cell_size);
            if (!std.meta.eql(colors.background, default_background))
                try appendContentLineSolid(
                    output,
                    &used,
                    physical,
                    physical,
                    colors.background,
                    row_index,
                    row.line_geometry,
                    cell_size,
                    surface,
                );
            if (cell.scalar_count == 0 or cell.x != 0 or cell.y != 0 or
                cell.style_bits & content_style_invisible != 0)
                continue;
            const sizing = try contentCellSizing(row_index, column, cell, cell_size);
            const clip = sizing.origin;
            if (cell.style_bits & content_style_underline != 0) {
                const line_y = std.math.add(i64, @as(i64, physical.y), line_offset) catch
                    return error.InvalidPresentationGeometry;
                const y = std.math.add(i64, line_y, @as(i64, metrics.underline_y)) catch
                    return error.InvalidPresentationGeometry;
                try appendContentUnderline(
                    output,
                    &used,
                    clip,
                    std.math.cast(i32, y) orelse return error.InvalidPresentationGeometry,
                    metrics.underline_height,
                    cell.underline_style,
                    colors.underline,
                    sizing,
                    row_index,
                    row.line_geometry,
                    cell_size,
                    surface,
                );
            }
            if (cell.style_bits & content_style_strike != 0) {
                const line_y = std.math.add(i64, @as(i64, physical.y), line_offset) catch
                    return error.InvalidPresentationGeometry;
                const y = std.math.add(i64, line_y, @as(i64, metrics.strike_y)) catch
                    return error.InvalidPresentationGeometry;
                try appendContentCellSolid(output, &used, .{
                    .x = clip.x,
                    .y = std.math.cast(i32, y) orelse return error.InvalidPresentationGeometry,
                    .width = clip.width,
                    .height = @max(@as(u16, 1), metrics.strike_height),
                }, colors.underline, sizing, row_index, row.line_geometry, cell_size, surface);
            }
        }
    }

    const placeholder_resource = contentResource(1);
    var has_raster = false;
    for (rows, 0..) |row, row_index| {
        const first = @as(usize, row.cell_offset);
        const count = @as(usize, row.cell_count);
        const end = std.math.add(usize, first, count) catch return error.InvalidView;
        if (end > cells.len or count != begin.columns) return error.InvalidView;
        const line_columns = try contentLineColumnCount(begin.columns, row.line_geometry);
        const row_cells = cells[first..][0..line_columns];
        var skip_until: usize = 0;
        for (row_cells, 0..) |cell, column| {
            if (column < skip_until or cell.scalar_count == 0) continue;
            if (cell.x != 0 or cell.y != 0) return error.InvalidView;
            if (cell.style_bits & content_style_invisible != 0) continue;

            const scalar_first = @as(usize, cell.scalar_offset);
            const scalar_count = @as(usize, cell.scalar_count);
            const scalar_end = std.math.add(usize, scalar_first, scalar_count) catch
                return error.InvalidView;
            if (scalar_end > scalars.len) return error.InvalidView;
            const sequence = scalars[scalar_first..scalar_end];
            const colors = try contentCellColors(cell, presentation);

            var run: text.Run = undefined;
            var contextual = false;
            var cluster_stride_26_6: i64 = 0;
            if (row.line_geometry == 0 and
                try contentIsContextualOperatorCell(cell, scalars))
            {
                const run_limit = @min(
                    row_cells.len - column,
                    @min(
                        maximum_operator_run_cells,
                        @as(usize, shapeCacheImpl(shape_cache).max_sequence_scalars),
                    ),
                );
                var run_end = column + 1;
                var run_scalar_end = scalar_end;
                while (run_end - column < run_limit) : (run_end += 1) {
                    const next = row_cells[run_end];
                    if (!contentSameContextualRendition(cell, next)) break;
                    if (!try contentIsContextualOperatorCell(next, scalars)) break;
                    if (@as(usize, next.scalar_offset) != run_scalar_end)
                        return error.InvalidView;
                    run_scalar_end = std.math.add(usize, run_scalar_end, 1) catch
                        return error.InvalidView;
                }
                if (run_end - column >= 2) {
                    if (try shapeContextualPrimary(
                        shape_cache,
                        scalars[scalar_first..run_scalar_end],
                        cluster_scratch,
                        shaped_scratch,
                    )) |candidate| {
                        if (contentContextualClustersPreserveCells(
                            candidate.glyphs,
                            run_end - column,
                        )) {
                            const cell_advance = std.math.mul(
                                i64,
                                @as(i64, cell_size.width),
                                64,
                            ) catch return error.InvalidPresentationGeometry;
                            const font_advance = std.math.mul(
                                i64,
                                @as(i64, metrics.advance_width),
                                64,
                            ) catch return error.InvalidPresentationGeometry;
                            cluster_stride_26_6 = std.math.sub(
                                i64,
                                cell_advance,
                                font_advance,
                            ) catch return error.InvalidPresentationGeometry;
                            run = candidate;
                            contextual = true;
                            skip_until = run_end;
                        }
                    }
                }
            }
            const physical = try contentCellRect(row_index, column, cell_size);
            const sizing = try contentCellSizing(row_index, column, cell, cell_size);
            const allocation_clip = try contentCellVisibleClip(
                sizing,
                row_index,
                row.line_geometry,
                cell_size,
                surface,
            ) orelse continue;

            if (sequence.len == 1 and generated.classify(sequence[0]) != null) {
                const sized_frame = try contentCellTransformRect(sizing.origin, sizing);
                const generated_raster = try resolveGeneratedAtlas(
                    atlas,
                    sequence[0],
                    sized_frame.width,
                    sized_frame.height,
                    generatedSizing(cell),
                    box_drawing,
                    raster_scratch,
                );
                has_raster = true;
                try appendContentInput(output, &used, .{ .alpha_mask = .{
                    .destination = try contentLineTransformRect(
                        sized_frame,
                        row_index,
                        row.line_geometry,
                        cell_size,
                    ),
                    .clip = allocation_clip,
                    .resource = .{
                        .resource = placeholder_resource,
                        .format = .alpha8,
                        .size = .{
                            .width = atlas_impl.config.width,
                            .height = atlas_impl.config.height,
                        },
                        .source = .{
                            .x = generated_raster.atlas_x,
                            .y = generated_raster.atlas_y,
                            .width = generated_raster.width,
                            .height = generated_raster.height,
                        },
                    },
                    .color = colors.foreground,
                    .cursor_component = true,
                } });
                continue;
            }
            if (!contextual)
                run = try resolveShape(
                    shape_cache,
                    sequence,
                    cluster_scratch,
                    shaped_scratch,
                );
            const font_clip = if (contextual) blk: {
                var row_clip = try contentCellRect(row_index, 0, cell_size);
                row_clip.width = surface.width;
                break :blk try contentLineClip(
                    row_clip,
                    row_index,
                    row.line_geometry,
                    cell_size,
                    surface,
                ) orelse continue;
            } else try contentFontVisibleClip(
                cell,
                sizing,
                row_index,
                row.line_geometry,
                cell_size,
                surface,
            ) orelse continue;

            var pen_x = std.math.mul(i64, @as(i64, physical.x), 64) catch
                return error.InvalidPresentationGeometry;
            const baseline_px = std.math.add(
                i64,
                std.math.add(i64, @as(i64, physical.y), line_offset) catch
                    return error.InvalidPresentationGeometry,
                @as(i64, metrics.baseline),
            ) catch return error.InvalidPresentationGeometry;
            var pen_y: i64 = 0;
            for (run.glyphs) |shaped| {
                const cluster_adjust = std.math.mul(
                    i64,
                    @as(i64, shaped.cluster),
                    cluster_stride_26_6,
                ) catch return error.InvalidPresentationGeometry;
                const raster = try resolveFontAtlas(
                    atlas,
                    run.face_index,
                    shaped.id,
                    raster_scratch,
                );
                if (raster.width != 0 and raster.height != 0) {
                    has_raster = true;
                    var left = std.math.add(i64, pen_x, cluster_adjust) catch
                        return error.InvalidPresentationGeometry;
                    left = std.math.add(i64, left, shaped.x_offset) catch
                        return error.InvalidPresentationGeometry;
                    left = std.math.add(i64, left, @as(i64, raster.left) * 64) catch
                        return error.InvalidPresentationGeometry;
                    var top = std.math.mul(i64, baseline_px, 64) catch
                        return error.InvalidPresentationGeometry;
                    top = std.math.add(i64, top, pen_y) catch
                        return error.InvalidPresentationGeometry;
                    top = std.math.sub(i64, top, shaped.y_offset) catch
                        return error.InvalidPresentationGeometry;
                    top = std.math.sub(i64, top, @as(i64, raster.top) * 64) catch
                        return error.InvalidPresentationGeometry;
                    const base_destination = canvas.Rect{
                        .x = try fixedContent26_6(left),
                        .y = try fixedContent26_6(top),
                        .width = raster.width,
                        .height = raster.height,
                    };
                    const sized_destination = try contentCellTransformRect(
                        base_destination,
                        sizing,
                    );
                    try appendContentInput(output, &used, .{ .alpha_mask = .{
                        .destination = try contentLineTransformRect(
                            sized_destination,
                            row_index,
                            row.line_geometry,
                            cell_size,
                        ),
                        .clip = font_clip,
                        .resource = .{
                            .resource = placeholder_resource,
                            .format = .alpha8,
                            .size = .{
                                .width = atlas_impl.config.width,
                                .height = atlas_impl.config.height,
                            },
                            .source = .{
                                .x = raster.atlas_x,
                                .y = raster.atlas_y,
                                .width = raster.width,
                                .height = raster.height,
                            },
                        },
                        .color = colors.foreground,
                        .cursor_component = true,
                    } });
                }
                pen_x = std.math.add(i64, pen_x, shaped.x_advance) catch
                    return error.InvalidPresentationGeometry;
                pen_y = std.math.add(i64, pen_y, shaped.y_advance) catch
                    return error.InvalidPresentationGeometry;
            }
        }
    }
    return .{ .command_count = used, .has_raster = has_raster };
}

fn generatedSizing(cell: View.Cell) generated.BoxDrawingSizing {
    const proper_fraction = cell.subscale_n != 0 and cell.subscale_d != 0 and
        cell.subscale_n < cell.subscale_d;
    return .{
        .scale = cell.height,
        .subscale_n = if (proper_fraction) @intCast(cell.subscale_n) else 0,
        .subscale_d = if (proper_fraction) @intCast(cell.subscale_d) else 0,
    };
}

fn bindContentResource(commands: []canvas.Input, resource: canvas.ResourceRef) void {
    for (commands) |*command| switch (command.*) {
        .alpha_mask => command.alpha_mask.resource.resource = resource,
        else => {},
    };
}

fn contentResource(generation: u64) canvas.ResourceRef {
    std.debug.assert(generation != 0);
    return .{
        .resource = canvas.ResourceId.local(1) catch unreachable,
        .generation = @fromBackingInt(@intCast(generation)),
    };
}

fn contentCursorBinding(
    snapshot: *const View.Snapshot,
    surface: canvas.Size,
    cell_size: canvas.Size,
    context: ?CursorContext,
) ContentError!?canvas.CursorBinding {
    const host = context orelse return null;
    if (host.pane == 0 or @backingInt(host.source) == 0 or
        host.visible_set_revision == 0 or host.lifecycle_revision == 0)
        return error.InvalidCursorContext;
    const begin = View.begin(snapshot);
    if (!begin.cursor_visible or begin.cursor_shape == 3) return null;
    if (begin.cursor_row >= begin.rows or begin.cursor_column >= begin.columns)
        return null;
    if (begin.revision == 0 or begin.terminal_revision == 0)
        return error.InvalidCursorContext;
    const presentation = View.presentation(snapshot);
    const rows = View.rows(snapshot);
    const row = rows[begin.cursor_row];
    if (begin.cursor_column >= try contentLineColumnCount(begin.columns, row.line_geometry))
        return null;
    const base_rect = try contentCellRect(begin.cursor_row, begin.cursor_column, cell_size);
    const rect = try contentLineClip(
        base_rect,
        begin.cursor_row,
        row.line_geometry,
        cell_size,
        surface,
    ) orelse return null;
    return .{
        .pane = host.pane,
        .source = host.source,
        .terminal_sequence = begin.terminal_revision,
        .cursor_revision = begin.revision,
        .visible_set_revision = host.visible_set_revision,
        .lifecycle_revision = host.lifecycle_revision,
        .rect = rect,
        .cell_origin = .{ .x = 0, .y = 0 },
        .cell_size = .{ .width = rect.width, .height = rect.height },
        .clip = contentSurfaceRect(surface),
        .shape = switch (begin.cursor_shape) {
            1 => .underline,
            2 => .bar,
            3 => .none,
            else => .block,
        },
        .color = richColor(presentation.cursor orelse presentation.foreground),
        .text_color = richColor(presentation.cursor_text orelse presentation.background),
        .visible = true,
    };
}

fn contentImpl(content: *Content) *ContentImpl {
    return @ptrCast(@alignCast(content));
}

fn constContentImpl(content: *const Content) *const ContentImpl {
    return @ptrCast(@alignCast(content));
}

fn shapeContextualPrimary(
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

fn resolveFontAtlas(
    atlas: *Atlas,
    face_index: u8,
    glyph_id: u32,
    raster_scratch: []u8,
) AtlasError!AtlasRaster {
    const impl = atlasImpl(atlas);
    const key = AtlasKey{ .font = .{ .face_index = face_index, .glyph_id = glyph_id } };
    if (findAtlas(impl, key)) |entry| return atlasRaster(entry);

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
    return cacheAtlas(
        impl,
        key,
        raster.width,
        raster.height,
        raster.left,
        raster.top,
        raster.pixels,
    );
}

fn resolveGeneratedAtlas(
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

fn findAtlas(impl: *const AtlasImpl, key: AtlasKey) ?AtlasEntry {
    for (impl.entries[0..impl.entry_count]) |entry|
        if (std.meta.eql(entry.key, key)) return entry;
    return null;
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
