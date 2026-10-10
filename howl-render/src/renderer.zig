//! Projects semantic terminal sources through howl-text into bounded terminal frames.
//!
//! This module owns terminal presentation derivation, private shape/raster caches,
//! resource publication, and backend-independent frame production. It knows no
//! VT owner, client transport, snapshot storage, window system, or graphics backend.

const std = @import("std");
const text = @import("howl_text");
const source_semantics = @import("source");
const limits = @import("limits");
const frame_vocabulary = @import("frame.zig");
const generated = text.generated;
const glyph_cache = @import("glyph_cache.zig");

/// Re-exports terminal-local alpha-atlas bounds used by Renderer configuration.
pub const AtlasConfig = glyph_cache.AtlasConfig;
/// Re-exports retained shaping bounds used by Store and Renderer configuration.
pub const ShapeCacheConfig = glyph_cache.ShapeCacheConfig;
/// Re-exports exact retained shaping usage counters.
pub const ShapeCacheUsage = glyph_cache.ShapeCacheUsage;
/// Re-exports runtime rasterization and bounded atlas-capacity failures.
pub const AtlasError = glyph_cache.AtlasError;
const AtlasInitError = glyph_cache.AtlasInitError;
/// Re-exports shape-cache construction failures for Store initialization.
pub const ShapeCacheInitError = glyph_cache.ShapeCacheInitError;
/// Re-exports runtime shaping and retained-shape capacity failures.
pub const ShapeCacheError = glyph_cache.ShapeCacheError;
/// Re-exports the four terminal font style variants.
pub const FontVariant = glyph_cache.FontVariant;
/// Re-exports one caller-owned terminal font family with deterministic fallback.
pub const FontFaces = glyph_cache.FontFaces;

const ShapeCache = glyph_cache.ShapeCache;
const Atlas = glyph_cache.Atlas;

const TextColor = source_semantics.TextColor;
const Metrics = text.Metrics;

/// Re-exports the exact backend-independent frame color type.
pub const Color = frame_vocabulary.Color;
/// Re-exports one nonzero pixel extent.
pub const Size = frame_vocabulary.Size;
/// Re-exports one signed destination/clip rectangle.
pub const Rect = frame_vocabulary.Rect;
/// Re-exports one unsigned resource source rectangle.
pub const SourceRect = frame_vocabulary.SourceRect;
/// Re-exports one logical backend resource identity.
pub const ResourceId = frame_vocabulary.ResourceId;
/// Re-exports one replacement generation for a logical backend resource.
pub const ResourceGeneration = frame_vocabulary.ResourceGeneration;
/// Re-exports the accepted alpha-mask and RGBA resource formats.
pub const ResourceFormat = frame_vocabulary.ResourceFormat;
/// Re-exports one exact logical resource occurrence.
pub const ResourceRef = frame_vocabulary.ResourceRef;
/// Re-exports one complete or sub-region resource sampling view.
pub const ResourceView = frame_vocabulary.ResourceView;
/// Re-exports one exact backend residency claim.
pub const Residency = frame_vocabulary.Residency;
/// Re-exports one Render-owned frame upload descriptor.
pub const FrameResourceUpload = frame_vocabulary.FrameResourceUpload;
/// Re-exports one visible Host-owned resource missing from backend residency.
pub const FrameExternalResource = frame_vocabulary.FrameExternalResource;
/// Re-exports one final surface-clipped backend command.
pub const Command = frame_vocabulary.Command;
/// Re-exports one ordered pre-projection draw fact used by retained row scenes.
pub const Input = frame_vocabulary.Input;

// File map:
//   - bounded Content lifecycle and Renderer resource publication
//   - terminal cell/DEC geometry, color, and decoration projection
//   - retained-row command reuse for revision-relative observations
//   - terminal text, image, and cursor projection into Renderer commands

/// Fixes every allocation and terminal presentation lattice used by one terminal Renderer.
/// The supplied FontSet remains caller-owned and must outlive the Renderer.
pub const Config = struct {
    cell_size: frame_vocabulary.Size,
    box_drawing: generated.BoxDrawingConfig,
    shape_cache: ShapeCacheConfig,
    atlas: AtlasConfig,
    shaped_capacity: usize,
    raster_bytes: usize,
    /// Initial resident terminal-command slots.
    command_capacity: usize,
    /// Maximum command slots this renderer may grow to. Zero fixes the
    /// historical behavior where `command_capacity` is also the hard limit.
    command_limit: usize = 0,
    /// Optional retained-row acceleration budget. Zero disables the cache.
    incremental_row_capacity: u16 = 0,
    incremental_command_capacity: usize = 0,
};

/// Binds one exact terminal image generation to Host-owned RGBA residency.
pub const ExternalImageBinding = struct {
    image_id: u32,
    generation: u64,
    resource: frame_vocabulary.ResourceRef,
};

/// Static image bound shared by maintained hosts. One resource slot is reserved
/// for the glyph atlas, leaving seven exact terminal image resources.
pub const maximum_external_images: usize = 7;

/// One terminal presentation owner. There is no producer/compositor layer.
// zig-audit: acknowledge opaque_type
// reason: Renderer intentionally hides the allocator-owned Impl layout so callers can mutate presentation state only through bounded renderer operations.
pub const Renderer = opaque {};

/// Process render knowledge shared by externally serialized terminal renderers.
///
/// FontFaces remain caller-owned and must
/// outlive the Store. The Store owns retained shaping knowledge and reusable
/// shape/raster scratch. Callers must serialize mutable Store use.
// zig-audit: acknowledge opaque_type
// reason: Store intentionally hides the allocator-owned StoreImpl layout so shared shaping state remains bounded and externally serialized.
pub const Store = opaque {};

/// Bounds reusable process render knowledge for one exact font/raster lane.
pub const StoreConfig = struct {
    shape_cache: ShapeCacheConfig,
    shaped_capacity: usize,
    raster_bytes: usize,
};

/// Reports retained shared process-render knowledge without terminal-local state.
pub const StoreUsage = struct {
    shape: ShapeCacheUsage,
};

/// Reports terminal-local cache, command-storage, revision, and resource identity state.
pub const Usage = struct {
    shape: ShapeCacheUsage,
    atlas_entries: usize,
    command_capacity: usize,
    revision: u64,
    content_revision: u64,
    resource_generation: u64,
    resource_high_water: u64,
};

/// Identifies a complete content prefix already stored in the same command buffer.
/// Valid only for this Renderer lifetime, while that prefix remains unmodified.
pub const RetainedContent = struct {
    revision: u64,
    commands: []const frame_vocabulary.Command,
};

/// Supplies caller-owned scratch receiving one backend-facing frame transaction.
pub const FrameBuffers = struct {
    retained_content: ?RetainedContent = null,
    uploads: []frame_vocabulary.FrameResourceUpload,
    removals: []frame_vocabulary.ResourceRef,
    commands: []frame_vocabulary.Command,
    pixels: []u8,
};

/// Borrows one completed backend-facing frame until the next Renderer mutation.
pub const Frame = struct {
    revision: u64,
    content_revision: u64,
    /// Commands before this boundary paint content; the suffix paints the cursor.
    content_command_count: usize,
    uploads: []const frame_vocabulary.FrameResourceUpload,
    removals: []const frame_vocabulary.ResourceRef,
    commands: []const frame_vocabulary.Command,
    pixels: []const u8,
};

/// Distinguishes a complete retained-row baseline from a revision-relative patch hint.
pub const RowSceneKind = enum { baseline, patch };

/// Locates one row's command span inside a retained RowScene command array.
pub const RowSceneRow = struct {
    start: usize = 0,
    count: usize = 0,
};

/// Borrows the current retained plain-row glyph scene until the next Renderer mutation.
/// `commands + rows` always describe the complete current scene. Patch metadata is
/// an acceleration hint; a backend may rebuild all rows from this same view.
pub const RowScene = struct {
    kind: RowSceneKind,
    revision: u64,
    base_revision: ?u64,
    shift_rows: u16,
    surface: frame_vocabulary.Size,
    cell_size: frame_vocabulary.Size,
    background: frame_vocabulary.Color,
    commands: []const frame_vocabulary.Input,
    rows: []const RowSceneRow,
    repairs: []const bool,
};

/// Reports allocation, cache construction, configuration, or font-family failure during Renderer initialization.
pub const InitError = std.mem.Allocator.Error || ShapeCacheInitError || AtlasInitError || error{
    InvalidConfig,
    InvalidFontFaces,
};

/// Reports allocation, shaping-cache construction, configuration, or font-family failure during Store initialization.
pub const StoreInitError = std.mem.Allocator.Error || ShapeCacheInitError || error{
    InvalidConfig,
    InvalidFontFaces,
};

/// Reports semantic projection, bounded cache/storage, resource-publication, or frame-production failure.
pub const Error = AtlasError || ShapeCacheError || frame_vocabulary.Error || error{
    InvalidView,
    InvalidColor,
    InvalidImageBinding,
    ImageLimit,
    InvalidPresentationGeometry,
    FontSetMismatch,
    GenerationOverflow,
    CommandLimit,
    MissingExternalResource,
    ResourceLimit,
    PixelLimit,
    RevisionOverflow,
    ResourceIdentityOverflow,
    ResourceGenerationOverflow,
};

/// Validates one exact backend residency set without mutating Render state.
pub fn validateResidencies(residency: []const frame_vocabulary.Residency) frame_vocabulary.Error!void {
    return frame_vocabulary.validateResidencies(residency);
}

/// Plans exact image generations in this renderer's local resource identity space.
/// Identities never recycle below the accepted high-water mark.
pub fn planImageBindings(
    current: []const ExternalImageBinding,
    current_usage: Usage,
    images: []const source_semantics.Image,
    output: *[maximum_external_images]ExternalImageBinding,
) error{ ImageLimit, InvalidImageBinding, ResourceIdentityOverflow }![]const ExternalImageBinding {
    if (images.len > output.len) return error.ImageLimit;
    var allocation_cursor = current_usage.resource_high_water;
    var first_new = true;
    for (images, 0..) |image, index| {
        output[index] = try planExternalImageBinding(
            current,
            current_usage,
            image.image_id,
            image.generation,
            &allocation_cursor,
            &first_new,
        );
    }
    return output[0..images.len];
}

fn planExternalImageBinding(
    current: []const ExternalImageBinding,
    current_usage: Usage,
    image_id: u32,
    generation: u64,
    allocation_cursor: *u64,
    first_new: *bool,
) error{ InvalidImageBinding, ResourceIdentityOverflow }!ExternalImageBinding {
    if (image_id == 0 or generation == 0) return error.InvalidImageBinding;
    const retained: ?ExternalImageBinding = for (current) |binding| {
        if (binding.image_id == image_id) break binding;
    } else null;
    if (retained) |prior| {
        if (generation < prior.generation) return error.InvalidImageBinding;
        var binding = prior;
        if (generation > prior.generation) {
            binding.generation = generation;
            binding.resource.generation = @fromBackingInt(generation);
        }
        return binding;
    }
    const step: u64 = if (first_new.* and current_usage.resource_generation == 0) 2 else 1;
    allocation_cursor.* = std.math.add(u64, allocation_cursor.*, step) catch
        return error.ResourceIdentityOverflow;
    first_new.* = false;
    if (allocation_cursor.* == 0 or allocation_cursor.* > frame_vocabulary.ResourceId.max_identity)
        return error.ResourceIdentityOverflow;
    return .{
        .image_id = image_id,
        .generation = generation,
        .resource = .{
            .resource = frame_vocabulary.ResourceId.init(allocation_cursor.*) catch
                return error.ResourceIdentityOverflow,
            .generation = @fromBackingInt(generation),
        },
    };
}

const Cursor = struct {
    rect: frame_vocabulary.Rect,
    clip: frame_vocabulary.Rect,
    shape: source_semantics.CursorShape,
    color: frame_vocabulary.Color,
    text_color: frame_vocabulary.Color,
};

const IncrementalRowCommands = RowSceneRow;

const IncrementalPlan = struct {
    shift: u16,
    repairs: []const bool,
    y_delta: i32,
};

const Impl = struct {
    allocator: std.mem.Allocator,
    config: Config,
    store: *Store,
    owned_store: ?*Store,
    atlas: *Atlas,
    commands: []frame_vocabulary.Input,
    incremental_commands: []frame_vocabulary.Input,
    incremental_rows: []IncrementalRowCommands,
    incremental_candidate_rows: []IncrementalRowCommands,
    incremental_repairs: []bool,
    incremental_command_count: usize = 0,
    incremental_scene_kind: RowSceneKind = .baseline,
    incremental_scene_revision: u64 = 0,
    incremental_scene_base_revision: ?u64 = null,
    incremental_scene_shift: u16 = 0,
    incremental_rows_count: u16 = 0,
    incremental_columns_count: u16 = 0,
    incremental_history_offset: u32 = 0,
    incremental_alternate_screen: bool = false,
    incremental_reverse_screen: bool = false,
    incremental_palette: [256]frame_vocabulary.Color = undefined,
    incremental_foreground: frame_vocabulary.Color = undefined,
    incremental_background: frame_vocabulary.Color = undefined,
    incremental_source_revision: ?u64 = null,
    incremental_ready: bool = false,
    placement_order: [limits.maximum_image_placements]u16 = undefined,
    frame_ready: bool = false,
    revision: u64 = 0,
    content_revision: u64 = 0,
    resource_generation: u64 = 0,
    resource_high_water: u64 = 0,
    atlas_resource_id: ?frame_vocabulary.ResourceId = null,
    published_images: [maximum_external_images]PublishedImage = undefined,
    published_image_count: usize = 0,
    published_atlas_generation: u64 = 0,
    published_atlas_entries: usize = 0,
    surface: frame_vocabulary.Size = .{ .width = 1, .height = 1 },
    command_count: usize = 0,
    atlas_visible: bool = false,
    // Command spans indexed by painted physical row, including glyph overhang.
    // Larger generic sources use the complete list; maintained hosts fit this bound.
    cursor_rows: [limits.maximum_rows]RowSceneRow = @splat(.{}),
    cursor_rows_ready: bool = false,
    cursor: ?Cursor = null,
};

const StoreImpl = struct {
    allocator: std.mem.Allocator,
    fonts: FontFaces,
    config: StoreConfig,
    shape_cache: *ShapeCache,
    clusters: []u32,
    shaped: []text.Glyph,
    raster: []u8,
};

const PublishedImage = struct {
    image_id: u32,
    generation: u64,
    external: frame_vocabulary.ExternalResource,
    visible: bool = false,
};

const ProjectedPlacement = struct {
    command: frame_vocabulary.Input,
};

fn commandLimit(config: Config) usize {
    return if (config.command_limit == 0) config.command_capacity else config.command_limit;
}

fn validCommandBounds(config: Config) bool {
    return config.command_capacity != 0 and commandLimit(config) >= config.command_capacity;
}

fn storeConfigFromRenderer(config: Config) StoreConfig {
    return .{
        .shape_cache = config.shape_cache,
        .shaped_capacity = config.shaped_capacity,
        .raster_bytes = config.raster_bytes,
    };
}

fn validateStoreConfig(config: StoreConfig) error{InvalidConfig}!void {
    if (config.shaped_capacity == 0 or config.raster_bytes == 0 or
        config.shape_cache.entry_capacity == 0 or
        config.shape_cache.scalar_capacity == 0 or
        config.shape_cache.glyph_capacity == 0 or
        config.shape_cache.max_sequence_scalars == 0)
        return error.InvalidConfig;
}

/// Allocates one process render lane for one exact caller-owned font recipe.
/// Mutable Store operations are externally serialized.
pub fn initStore(
    allocator: std.mem.Allocator,
    fonts: FontFaces,
    config: StoreConfig,
) StoreInitError!*Store {
    try validateStoreConfig(config);
    if (!fonts.terminalMetricsCompatible()) return error.InvalidFontFaces;

    const impl = try allocator.create(StoreImpl);
    errdefer allocator.destroy(impl);
    const shape_cache = try glyph_cache.initShapeCache(allocator, fonts, config.shape_cache);
    errdefer glyph_cache.deinitShapeCache(shape_cache);
    const clusters = try allocator.alloc(u32, @intCast(config.shape_cache.max_sequence_scalars));
    errdefer allocator.free(clusters);
    const shaped = try allocator.alloc(text.Glyph, config.shaped_capacity);
    errdefer allocator.free(shaped);
    const raster = try allocator.alloc(u8, config.raster_bytes);
    errdefer allocator.free(raster);
    impl.* = .{
        .allocator = allocator,
        .fonts = fonts,
        .config = config,
        .shape_cache = shape_cache,
        .clusters = clusters,
        .shaped = shaped,
        .raster = raster,
    };
    // zig-audit: acknowledge ptr_cast
    // reason: Store is the opaque handle for this exact allocator-owned StoreImpl allocation and preserves its address.
    return @ptrCast(impl);
}

/// Releases one process render lane. No Renderer may still borrow it.
pub fn deinitStore(owner: *Store) void {
    const impl = storeImpl(owner);
    const allocator = impl.allocator;
    const shape_cache = impl.shape_cache;
    const clusters = impl.clusters;
    const shaped = impl.shaped;
    const raster = impl.raster;
    impl.* = undefined;
    allocator.free(raster);
    allocator.free(shaped);
    allocator.free(clusters);
    glyph_cache.deinitShapeCache(shape_cache);
    allocator.destroy(impl);
}

/// Returns exact metrics for this Store's fixed font/raster lane.
pub fn storeMetrics(owner: *const Store) Metrics {
    return constStoreImpl(owner).fonts.metrics();
}

/// Reports retained process-shared cache usage.
pub fn storeUsage(owner: *const Store) StoreUsage {
    return .{ .shape = glyph_cache.shapeCacheUsage(constStoreImpl(owner).shape_cache) };
}

/// Forgets shared shaping knowledge without invalidating terminal-local atlases.
pub fn resetStore(owner: *Store) void {
    glyph_cache.resetShapeCache(storeImpl(owner).shape_cache);
}

/// Allocates a private Store and one terminal Renderer. For matching terminals,
/// create one Store and use initWithStore so native shaping knowledge is shared.
///
/// FontSets remain caller-owned and must outlive the Renderer. Serialize callers
/// that share native faces, even with private Stores. Missing styles fall back
/// deterministically. Shape/raster storage is fixed; command storage may grow
/// within the configured command limit.
pub fn initPrivate(
    allocator: std.mem.Allocator,
    fonts: FontFaces,
    config: Config,
) InitError!*Renderer {
    if (config.cell_size.width == 0 or config.cell_size.height == 0 or
        config.shaped_capacity == 0 or config.raster_bytes == 0 or
        !validCommandBounds(config) or
        ((config.incremental_row_capacity == 0) != (config.incremental_command_capacity == 0)))
        return error.InvalidConfig;
    if (!fonts.terminalMetricsCompatible()) return error.InvalidFontFaces;

    const store = try initStore(allocator, fonts, storeConfigFromRenderer(config));
    errdefer deinitStore(store);
    return initWithStoreOwned(allocator, store, config);
}

/// Allocates one terminal-local renderer borrowing process render knowledge.
/// The Store must outlive this Renderer and mutable Store use must be externally serialized.
pub fn initWithStore(
    allocator: std.mem.Allocator,
    store: *Store,
    config: Config,
) InitError!*Renderer {
    if (config.cell_size.width == 0 or config.cell_size.height == 0 or
        config.shaped_capacity == 0 or config.raster_bytes == 0 or
        !validCommandBounds(config) or
        ((config.incremental_row_capacity == 0) != (config.incremental_command_capacity == 0)))
        return error.InvalidConfig;
    const store_impl = storeImpl(store);
    if (!std.meta.eql(store_impl.config, storeConfigFromRenderer(config)))
        return error.InvalidConfig;
    return initWithStoreInner(allocator, store, null, config);
}

fn initWithStoreOwned(
    allocator: std.mem.Allocator,
    store: *Store,
    config: Config,
) InitError!*Renderer {
    return initWithStoreInner(allocator, store, store, config);
}

fn initWithStoreInner(
    allocator: std.mem.Allocator,
    store: *Store,
    owned_store: ?*Store,
    config: Config,
) InitError!*Renderer {
    const store_impl = storeImpl(store);

    const impl = try allocator.create(Impl);
    errdefer allocator.destroy(impl);
    const atlas = try glyph_cache.initAtlas(
        allocator,
        store_impl.fonts,
        config.box_drawing,
        config.atlas,
    );
    errdefer glyph_cache.deinitAtlas(atlas);
    const commands = try allocator.alloc(frame_vocabulary.Input, config.command_capacity);
    errdefer allocator.free(commands);
    const incremental_commands = try allocator.alloc(frame_vocabulary.Input, config.incremental_command_capacity);
    errdefer allocator.free(incremental_commands);
    const incremental_rows = try allocator.alloc(IncrementalRowCommands, config.incremental_row_capacity);
    errdefer allocator.free(incremental_rows);
    const incremental_candidate_rows = try allocator.alloc(IncrementalRowCommands, config.incremental_row_capacity);
    errdefer allocator.free(incremental_candidate_rows);
    const incremental_repairs = try allocator.alloc(bool, config.incremental_row_capacity);
    errdefer allocator.free(incremental_repairs);

    impl.* = .{
        .allocator = allocator,
        .config = config,
        .store = store,
        .owned_store = owned_store,
        .atlas = atlas,
        .commands = commands,
        .incremental_commands = incremental_commands,
        .incremental_rows = incremental_rows,
        .incremental_candidate_rows = incremental_candidate_rows,
        .incremental_repairs = incremental_repairs,
    };
    // zig-audit: acknowledge ptr_cast
    // reason: Renderer is the opaque handle for this exact allocator-owned Impl allocation and preserves its address.
    return @ptrCast(impl);
}

/// Releases one terminal Renderer and every private presentation cache.
pub fn deinit(owner: *Renderer) void {
    const impl = rendererImpl(owner);
    const allocator = impl.allocator;
    const owned_store = impl.owned_store;
    const atlas = impl.atlas;
    const commands = impl.commands;
    const incremental_commands = impl.incremental_commands;
    const incremental_rows = impl.incremental_rows;
    const incremental_candidate_rows = impl.incremental_candidate_rows;
    const incremental_repairs = impl.incremental_repairs;
    impl.* = undefined;
    allocator.free(commands);
    allocator.free(incremental_repairs);
    allocator.free(incremental_candidate_rows);
    allocator.free(incremental_rows);
    allocator.free(incremental_commands);
    glyph_cache.deinitAtlas(atlas);
    allocator.destroy(impl);
    if (owned_store) |store| deinitStore(store);
}

/// Forgets this terminal atlas and command readiness; shared shaping stays intact.
/// Use resetStore to forget process shaping knowledge. The next successful update
/// using glyphs publishes a newer atlas generation. Frames and refill queries
/// remain invalid until that update.
pub fn resetCaches(owner: *Renderer) error{GenerationOverflow}!void {
    const impl = rendererImpl(owner);
    impl.frame_ready = false;
    impl.incremental_ready = false;
    impl.incremental_command_count = 0;
    try glyph_cache.resetAtlas(impl.atlas);
}

/// Reports current terminal-local retained usage and resource publication counters.
pub fn usage(owner: *const Renderer) Usage {
    const impl = constRendererImpl(owner);
    return .{
        .shape = storeUsage(impl.store).shape,
        .atlas_entries = glyph_cache.atlasEntryCount(impl.atlas),
        .command_capacity = impl.commands.len,
        .revision = impl.revision,
        .content_revision = impl.content_revision,
        .resource_generation = impl.resource_generation,
        .resource_high_water = impl.resource_high_water,
    };
}

/// Replaces one Renderer from a synchronous source-adapter snapshot without retaining it.
/// The source contract is compile-time only; accepted output is copied into Renderer-owned state.
pub fn updateSource(
    comptime Source: type,
    owner: *Renderer,
    snapshot: *const Source.Snapshot,
    image_bindings: []const ExternalImageBinding,
) Error!void {
    var atlas_retried = false;
    var shape_retried = false;
    while (true) {
        updateInnerOnce(Source, owner, snapshot, image_bindings) catch |failure| switch (failure) {
            error.CommandLimit => {
                if (!try growCommandStorage(owner)) return error.CommandLimit;
                continue;
            },
            error.CacheFull, error.AtlasFull => {
                if (atlas_retried) return failure;
                atlas_retried = true;
                try resetCaches(owner);
                continue;
            },
            error.ShapeEntryFull, error.ShapeScalarFull, error.ShapeGlyphFull => {
                if (shape_retried) return failure;
                shape_retried = true;
                resetStore(rendererImpl(owner).store);
                continue;
            },
            else => return failure,
        };
        return;
    }
}

/// Updates only cursor presentation against already prepared content. The caller
/// must prove the source content unchanged; no source borrow survives this call.
pub fn updateCursorSource(
    comptime Source: type,
    owner: *Renderer,
    snapshot: *const Source.Snapshot,
) Error!void {
    const impl = rendererImpl(owner);
    if (!impl.frame_ready) return error.InvalidView;
    const surface = try contentSurfaceSize(Source.rows(snapshot), Source.columns(snapshot), impl.config.cell_size);
    if (!std.meta.eql(surface, impl.surface)) return error.InvalidView;
    const cursor = try contentCursor(Source, snapshot, surface, impl.config.cell_size);
    if (impl.revision == std.math.maxInt(u64)) return error.RevisionOverflow;
    impl.cursor = cursor;
    impl.revision += 1;
}

fn growCommandStorage(owner: *Renderer) std.mem.Allocator.Error!bool {
    const impl = rendererImpl(owner);
    const limit = commandLimit(impl.config);
    if (impl.commands.len >= limit) return false;
    const doubled = std.math.mul(usize, impl.commands.len, 2) catch limit;
    const next = @min(limit, @max(impl.commands.len + 1, doubled));
    const replacement = try impl.allocator.alloc(frame_vocabulary.Input, next);
    impl.allocator.free(impl.commands);
    impl.commands = replacement;
    impl.frame_ready = false;
    impl.incremental_ready = false;
    impl.incremental_command_count = 0;
    return true;
}

fn updateInnerOnce(
    comptime Source: type,
    owner: *Renderer,
    snapshot: *const Source.Snapshot,
    image_bindings: []const ExternalImageBinding,
) Error!void {
    const impl = rendererImpl(owner);
    const store = storeImpl(impl.store);
    impl.frame_ready = false;
    errdefer impl.incremental_ready = false;
    const rows = Source.rows(snapshot);
    const surface = try contentSurfaceSize(rows, Source.columns(snapshot), impl.config.cell_size);
    const changed_rows = sourceChangedRows(Source, snapshot);
    const wants_incremental = changed_rows != null;
    const incremental_plan = if (wants_incremental)
        try planIncrementalRows(Source, owner, snapshot)
    else
        null;
    const candidate_rows = if (wants_incremental and rows <= impl.incremental_candidate_rows.len)
        impl.incremental_candidate_rows[0..rows]
    else
        null;
    const projection = try buildContentCommands(
        Source,
        snapshot,
        impl.atlas,
        store.shape_cache,
        surface,
        impl.commands,
        incremental_plan,
        impl.incremental_commands,
        impl.incremental_rows,
        candidate_rows,
        impl.config.cell_size,
        store.clusters,
        store.shaped,
        store.raster,
    );
    var command_count = projection.command_count;
    const atlas = glyph_cache.atlasView(impl.atlas);
    const atlas_entries = glyph_cache.atlasEntryCount(impl.atlas);
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
    var next_resource_high_water = impl.resource_high_water;
    var next_atlas_resource_id = impl.atlas_resource_id;
    if (publish_atlas and next_atlas_resource_id == null) {
        if (next_resource_high_water >= frame_vocabulary.ResourceId.max_identity)
            return error.ResourceIdentityOverflow;
        next_resource_high_water += 1;
        next_atlas_resource_id = frame_vocabulary.ResourceId.init(next_resource_high_water) catch
            return error.ResourceIdentityOverflow;
    }
    const atlas_resource = if (projection.has_raster) contentResource(
        next_atlas_resource_id orelse return error.InvalidPresentationGeometry,
        next_resource_generation,
    ) else null;
    if (atlas_resource) |value| bindContentResource(impl.commands[0..command_count], value);

    const graphics = Source.graphics(snapshot);
    if (Source.graphicsPlacementCount(graphics) > impl.placement_order.len)
        return error.ImageLimit;

    var next_published_images: [maximum_external_images]PublishedImage = undefined;
    var next_published_count: usize = 0;
    const new_resource_floor = next_resource_high_water;
    for (0..Source.graphicsImageCount(graphics)) |image_index| {
        const image = Source.graphicsImage(graphics, image_index);
        if (!Source.graphicsImageVisible(graphics, image.image_id)) continue;
        if (next_published_count == next_published_images.len) return error.ImageLimit;
        const binding = findExternalImageBinding(image_bindings, image.image_id, image.generation) orelse
            return error.InvalidImageBinding;
        const published = try publishedImage(image, binding);
        try frame_vocabulary.validateExternal(published.external);
        const image_identity = try contentExternalIdentity(published.external.resource);
        if (next_atlas_resource_id) |atlas_id| {
            if (atlas_id == published.external.resource.resource) return error.InvalidImageBinding;
        }
        for (next_published_images[0..next_published_count]) |prior| {
            if (prior.image_id == published.image_id or
                prior.external.resource.resource == published.external.resource.resource)
                return error.InvalidImageBinding;
        }
        const prior = findPublishedImageByResource(
            impl.published_images[0..impl.published_image_count],
            published.external.resource.resource,
        );
        if (prior) |value| {
            if (value.image_id != published.image_id) return error.InvalidImageBinding;
            // Visibility belongs to placements; it may change without replacing
            // the image occurrence or its immutable pixel/extent facts.
            if ((value.generation != published.generation or
                !std.meta.eql(value.external, published.external)) and
                @backingInt(published.external.resource.generation) <=
                    @backingInt(value.external.resource.generation))
                return error.InvalidImageBinding;
        } else {
            if (image_identity <= new_resource_floor) return error.InvalidImageBinding;
            next_resource_high_water = @max(next_resource_high_water, image_identity);
        }
        next_published_images[next_published_count] = published;
        next_published_count += 1;
    }

    if (image_bindings.len != next_published_count) return error.InvalidImageBinding;

    try insertExternalPlacements(
        Source,
        snapshot,
        image_bindings,
        surface,
        impl.config.cell_size,
        projection,
        impl.commands,
        &command_count,
        &impl.placement_order,
    );

    try indexCursorRows(impl, surface, command_count);
    for (next_published_images[0..next_published_count]) |*published| {
        published.visible = frame_vocabulary.resourceVisible(impl.commands[0..command_count], published.external.resource);
    }
    const cursor = try contentCursor(Source, snapshot, surface, impl.config.cell_size);
    if (impl.revision == std.math.maxInt(u64)) return error.RevisionOverflow;
    const previous_revision = impl.revision;
    const next_revision = impl.revision + 1;

    const incremental_enabled = wants_incremental and impl.incremental_commands.len != 0 and candidate_rows != null;
    const incremental_eligible = incremental_plan != null or
        (incremental_enabled and projection.default_background_end == 1 and
            projection.background_end == 1 and try incrementalViewEligible(Source, snapshot, null));

    impl.revision = next_revision;
    impl.content_revision = next_revision;
    impl.surface = surface;
    impl.command_count = command_count;
    impl.atlas_visible = projection.has_raster;
    impl.cursor = cursor;
    impl.resource_high_water = next_resource_high_water;
    impl.atlas_resource_id = next_atlas_resource_id;
    @memcpy(
        impl.published_images[0..next_published_count],
        next_published_images[0..next_published_count],
    );
    impl.published_image_count = next_published_count;
    if (publish_atlas) {
        impl.resource_generation = next_resource_generation;
        impl.published_atlas_generation = atlas.generation;
        impl.published_atlas_entries = atlas_entries;
    }
    if (incremental_eligible) {
        rememberIncrementalCommands(Source, owner, snapshot);
        if (impl.incremental_ready) {
            impl.incremental_scene_revision = next_revision;
            if (incremental_plan) |plan| {
                impl.incremental_scene_kind = .patch;
                impl.incremental_scene_base_revision = previous_revision;
                impl.incremental_scene_shift = plan.shift;
                @memcpy(impl.incremental_repairs[0..Source.rows(snapshot)], plan.repairs);
            } else {
                impl.incremental_scene_kind = .baseline;
                impl.incremental_scene_base_revision = null;
                impl.incremental_scene_shift = 0;
                @memset(impl.incremental_repairs[0..Source.rows(snapshot)], true);
            }
        }
    } else {
        impl.incremental_ready = false;
        impl.incremental_command_count = 0;
    }
    impl.frame_ready = true;
}

/// Borrows the current bounded retained plain-row glyph scene.
/// Returns null when the latest accepted frame is outside incremental eligibility.
pub fn rowScene(owner: *const Renderer) ?RowScene {
    const impl = constRendererImpl(owner);
    if (!impl.frame_ready or !impl.incremental_ready or impl.incremental_scene_revision != impl.revision)
        return null;
    const rows = @as(usize, impl.incremental_rows_count);
    if (rows == 0 or rows > impl.incremental_rows.len or rows > impl.incremental_repairs.len)
        return null;
    if (impl.incremental_command_count > impl.incremental_commands.len) return null;
    return .{
        .kind = impl.incremental_scene_kind,
        .revision = impl.incremental_scene_revision,
        .base_revision = impl.incremental_scene_base_revision,
        .shift_rows = impl.incremental_scene_shift,
        .surface = impl.surface,
        .cell_size = impl.config.cell_size,
        .background = impl.incremental_background,
        .commands = impl.incremental_commands[0..impl.incremental_command_count],
        .rows = impl.incremental_rows[0..rows],
        .repairs = impl.incremental_repairs[0..rows],
    };
}

/// Lists Host-owned terminal image resources required by the current frame but
/// absent from exact backend residency.
pub fn missingExternalResources(
    owner: *const Renderer,
    residency: []const frame_vocabulary.Residency,
    output: []frame_vocabulary.FrameExternalResource,
) Error![]const frame_vocabulary.FrameExternalResource {
    const impl = constRendererImpl(owner);
    if (!impl.frame_ready) return error.InvalidView;
    try frame_vocabulary.validateResidencies(residency);
    var needed: usize = 0;
    for (impl.published_images[0..impl.published_image_count]) |published| {
        const external = published.external;
        if (!published.visible) continue;
        if (frame_vocabulary.residencyMatches(residency, external.resource, external.format, external.size)) continue;
        if (needed == output.len) return error.ResourceLimit;
        output[needed] = .{
            .resource = external.resource,
            .format = external.format,
            .size = external.size,
            .stride = external.stride,
        };
        needed += 1;
    }
    return output[0..needed];
}

/// Derives one complete terminal frame against exact backend residency.
pub fn frame(
    owner: *const Renderer,
    residency: []const frame_vocabulary.Residency,
    buffers: FrameBuffers,
) Error!Frame {
    const impl = constRendererImpl(owner);
    if (!impl.frame_ready) return error.InvalidView;
    try frame_vocabulary.validateResidencies(residency);

    for (impl.published_images[0..impl.published_image_count]) |published| {
        const external = published.external;
        if (!published.visible) continue;
        if (!frame_vocabulary.residencyMatches(residency, external.resource, external.format, external.size))
            return error.MissingExternalResource;
    }

    const atlas = glyph_cache.atlasView(impl.atlas);
    const atlas_ref: ?frame_vocabulary.ResourceRef = if (impl.atlas_resource_id != null and impl.resource_generation != 0)
        contentResource(impl.atlas_resource_id.?, impl.resource_generation)
    else
        null;
    const atlas_required = impl.atlas_visible;
    const atlas_upload = atlas_required and !frame_vocabulary.residencyMatches(
        residency,
        atlas_ref.?,
        .alpha8,
        .{ .width = atlas.width, .height = atlas.height },
    );

    var removal_count: usize = 0;
    for (residency) |value| {
        if (residencyRequired(impl, atlas, value)) continue;
        // A newer atlas generation replaces the same backend identity atomically.
        // Emitting a removal for that identity in the same frame would make the
        // replacement transaction internally contradictory.
        if (atlas_upload and value.resource.resource == atlas_ref.?.resource) continue;
        if (removal_count == buffers.removals.len) return error.ResourceLimit;
        removal_count += 1;
    }
    const cursor_extra = try cursorCommandUpperBound(impl);
    const command_limit = std.math.add(usize, impl.command_count, cursor_extra) catch
        return error.CommandLimit;
    if (buffers.commands.len < command_limit) return error.CommandLimit;
    if (atlas_upload) {
        if (buffers.uploads.len < 1) return error.ResourceLimit;
        if (buffers.pixels.len < atlas.pixels.len) return error.PixelLimit;
    }

    var projected = reuse: {
        if (buffers.retained_content) |retained| {
            if (retained.revision == impl.content_revision and
                retained.commands.ptr == buffers.commands.ptr)
            {
                if (retained.commands.len > impl.command_count or retained.commands.len > buffers.commands.len)
                    return error.InvalidView;
                break :reuse buffers.commands[0..retained.commands.len];
            }
        }
        break :reuse try frame_vocabulary.projectPrepared(
            impl.surface,
            impl.commands[0..impl.command_count],
            buffers.commands,
        );
    };
    const content_command_count = projected.len;
    var command_count = projected.len;
    try appendCursorCommands(impl, buffers.commands, &command_count);
    projected = buffers.commands[0..command_count];

    var upload_count: usize = 0;
    var pixel_count: usize = 0;
    if (atlas_upload) {
        @memcpy(buffers.pixels[0..atlas.pixels.len], atlas.pixels);
        buffers.uploads[0] = .{
            .resource = atlas_ref.?,
            .format = .alpha8,
            .size = .{ .width = atlas.width, .height = atlas.height },
            .pixel_offset = 0,
            .pixel_count = atlas.pixels.len,
            .stride = atlas.width,
        };
        upload_count = 1;
        pixel_count = atlas.pixels.len;
    }

    var removal_at: usize = 0;
    for (residency) |value| {
        if (residencyRequired(impl, atlas, value)) continue;
        if (atlas_upload and value.resource.resource == atlas_ref.?.resource) continue;
        buffers.removals[removal_at] = value.resource;
        removal_at += 1;
    }

    return .{
        .revision = impl.revision,
        .content_revision = impl.content_revision,
        .content_command_count = content_command_count,
        .uploads = buffers.uploads[0..upload_count],
        .removals = buffers.removals[0..removal_at],
        .commands = projected,
        .pixels = buffers.pixels[0..pixel_count],
    };
}

fn residencyRequired(
    impl: *const Impl,
    atlas: glyph_cache.AtlasView,
    value: frame_vocabulary.Residency,
) bool {
    if (impl.atlas_resource_id) |id| {
        if (impl.resource_generation != 0) {
            const ref = contentResource(id, impl.resource_generation);
            if (impl.atlas_visible and std.meta.eql(value.resource, ref))
                return value.format == .alpha8 and
                    std.meta.eql(value.size, frame_vocabulary.Size{ .width = atlas.width, .height = atlas.height });
        }
    }
    for (impl.published_images[0..impl.published_image_count]) |published| {
        const external = published.external;
        if (!published.visible) continue;
        if (std.meta.eql(value.resource, external.resource))
            return value.format == external.format and std.meta.eql(value.size, external.size);
    }
    return false;
}

// Build the search index only with content. Spans describe actual clipped ink,
// preserving combining glyphs, ligatures, DEC geometry and cross-row overhang.
fn indexCursorRows(impl: *Impl, surface: frame_vocabulary.Size, command_count: usize) Error!void {
    const height = impl.config.cell_size.height;
    const rows = surface.height / height;
    impl.cursor_rows_ready = rows <= impl.cursor_rows.len;
    if (!impl.cursor_rows_ready) return;
    @memset(&impl.cursor_rows, .{});
    const whole = contentSurfaceRect(surface);
    for (impl.commands[0..command_count], 0..) |command, index| switch (command) {
        .alpha_mask => |mask| {
            if (!mask.cursor_component) continue;
            const clipped = (try frame_vocabulary.intersectRects(mask.destination, mask.clip)) orelse continue;
            const ink = (try frame_vocabulary.intersectRects(clipped, whole)) orelse continue;
            const first = @as(usize, @intCast(ink.y)) / height;
            const last = (@as(usize, @intCast(ink.y)) + ink.height - 1) / height;
            for (impl.cursor_rows[first .. last + 1]) |*span| {
                if (span.count == 0) span.start = index;
                span.count = index + 1 - span.start;
            }
        },
        else => {},
    };
}

fn cursorInputs(impl: *const Impl, cursor: Cursor) []const frame_vocabulary.Input {
    const commands = impl.commands[0..impl.command_count];
    if (!impl.cursor_rows_ready) return commands;
    const height = impl.config.cell_size.height;
    const first = @as(usize, @intCast(cursor.rect.y)) / height;
    const last = (@as(usize, @intCast(cursor.rect.y)) + cursor.rect.height - 1) / height;
    var start = commands.len;
    var end: usize = 0;
    for (impl.cursor_rows[first .. last + 1]) |span| {
        if (span.count == 0) continue;
        start = @min(start, span.start);
        end = @max(end, span.start + span.count);
    }
    return if (end == 0) commands[0..0] else commands[start..end];
}

fn cursorCommandUpperBound(impl: *const Impl) Error!usize {
    const cursor = impl.cursor orelse return 0;
    var count: usize = 1;
    if (cursor.shape != .block) return count;
    for (cursorInputs(impl, cursor)) |command| switch (command) {
        .alpha_mask => |value| {
            if (value.cursor_component and
                (try frame_vocabulary.intersectRects(value.destination, cursor.rect)) != null)
                count = std.math.add(usize, count, 1) catch return error.CommandLimit;
        },
        else => {},
    };
    return count;
}

fn appendCursorCommands(
    impl: *const Impl,
    commands: []frame_vocabulary.Command,
    used: *usize,
) Error!void {
    const cursor = impl.cursor orelse return;
    var painted = cursor.rect;
    switch (cursor.shape) {
        .block => {},
        .bar => painted.width = @min(painted.width, 2),
        .underline => {
            const thickness = @min(painted.height, 2);
            painted.y = std.math.add(i32, painted.y, @as(i32, painted.height - thickness)) catch
                return error.InvalidPresentationGeometry;
            painted.height = thickness;
        },
        .none => return,
    }
    try appendProjectedInput(impl.surface, .{ .solid = .{
        .rect = painted,
        .clip = cursor.clip,
        .color = cursor.color,
    } }, commands, used);
    if (cursor.shape != .block) return;

    for (cursorInputs(impl, cursor)) |command| switch (command) {
        .alpha_mask => |value| {
            if (!value.cursor_component) continue;
            const clip = (try frame_vocabulary.intersectRects(value.clip, cursor.clip)) orelse continue;
            const cursor_clip = (try frame_vocabulary.intersectRects(clip, cursor.rect)) orelse continue;
            try appendProjectedInput(impl.surface, .{ .alpha_mask = .{
                .destination = value.destination,
                .clip = cursor_clip,
                .resource = value.resource,
                .color = cursor.text_color,
                .cursor_component = false,
            } }, commands, used);
        },
        else => {},
    };
}

fn appendProjectedInput(
    surface: frame_vocabulary.Size,
    input: frame_vocabulary.Input,
    commands: []frame_vocabulary.Command,
    used: *usize,
) Error!void {
    if (used.* == commands.len) return error.CommandLimit;
    var one = [_]frame_vocabulary.Input{input};
    const projected = try frame_vocabulary.projectPrepared(surface, &one, commands[used.*..]);
    if (projected.len == 1) used.* += 1;
}

const maximum_operator_run_cells: usize = 4;
const placeholder_resource_id = frame_vocabulary.ResourceId.init(1) catch
    @compileError("renderer placeholder resource identity must remain nonzero");
/// Kitty's deepest image layer is strictly below INT32_MIN/2. That phase is
/// painted after the terminal default background but before non-default cell
/// backgrounds. Ordinary negative z remains under foreground content.
const content_image_below_background_threshold: i32 = std.math.minInt(i32) / 2;

const ContentCellColors = struct {
    foreground: frame_vocabulary.Color,
    background: frame_vocabulary.Color,
    underline: frame_vocabulary.Color,
};

fn contentSurfaceSize(
    rows: u16,
    columns: u16,
    cell_size: frame_vocabulary.Size,
) Error!frame_vocabulary.Size {
    const width = std.math.mul(
        u32,
        @as(u32, columns),
        @as(u32, cell_size.width),
    ) catch return error.InvalidPresentationGeometry;
    const height = std.math.mul(
        u32,
        @as(u32, rows),
        @as(u32, cell_size.height),
    ) catch return error.InvalidPresentationGeometry;
    if (width == 0 or height == 0 or
        width > std.math.maxInt(u16) or height > std.math.maxInt(u16))
        return error.InvalidPresentationGeometry;
    return .{ .width = @intCast(width), .height = @intCast(height) };
}

fn contentSurfaceRect(size: frame_vocabulary.Size) frame_vocabulary.Rect {
    return .{ .x = 0, .y = 0, .width = size.width, .height = size.height };
}

fn contentCellRect(row: usize, column: usize, cell_size: frame_vocabulary.Size) Error!frame_vocabulary.Rect {
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
    origin: frame_vocabulary.Rect,
    allocation: frame_vocabulary.Rect,
    scale_n: u16,
    scale_d: u16,
    offset_x: u16,
    offset_y: u16,
};

fn contentFontVariant(style: source_semantics.CellStyle) FontVariant {
    if (style.bold and style.italic) return .bold_italic;
    if (style.bold) return .bold;
    if (style.italic) return .italic;
    return .regular;
}

fn contentCellSizing(
    comptime Source: type,
    row: usize,
    column: usize,
    cell: Source.Cell,
    cell_size: frame_vocabulary.Size,
) Error!ContentCellSizing {
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

fn contentScaleExtent(value: u16, numerator: u16, denominator: u16) Error!u16 {
    if (value == 0 or numerator == 0 or denominator == 0)
        return error.InvalidPresentationGeometry;
    const product = std.math.mul(u32, value, numerator) catch
        return error.InvalidPresentationGeometry;
    const rounded = std.math.add(u32, product, denominator - 1) catch
        return error.InvalidPresentationGeometry;
    const result = rounded / denominator;
    return std.math.cast(u16, result) orelse error.InvalidPresentationGeometry;
}

fn contentScaleCoordinate(value: i64, numerator: u16, denominator: u16) Error!i64 {
    if (numerator == 0 or denominator == 0) return error.InvalidPresentationGeometry;
    const product = std.math.mul(i64, value, numerator) catch
        return error.InvalidPresentationGeometry;
    return @divFloor(product, denominator);
}

fn contentCellTransformRect(
    rect: frame_vocabulary.Rect,
    sizing: ContentCellSizing,
) Error!frame_vocabulary.Rect {
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

fn contentLineScale(geometry: source_semantics.LineGeometry) Error!ContentLineScale {
    return switch (geometry) {
        .single_width => .{ .x = 1, .y = 1, .bottom_half = false },
        .double_width => .{ .x = 2, .y = 1, .bottom_half = false },
        .double_height_top => .{ .x = 2, .y = 2, .bottom_half = false },
        .double_height_bottom => .{ .x = 2, .y = 2, .bottom_half = true },
    };
}

fn contentLineColumnCount(columns: u16, geometry: source_semantics.LineGeometry) Error!u16 {
    const scale = try contentLineScale(geometry);
    return if (scale.x == 1) columns else @max(@as(u16, 1), columns / 2);
}

fn contentLineTransformRect(
    rect: frame_vocabulary.Rect,
    row: usize,
    geometry: source_semantics.LineGeometry,
    cell_size: frame_vocabulary.Size,
) Error!frame_vocabulary.Rect {
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

fn contentIntersectRects(left: frame_vocabulary.Rect, right: frame_vocabulary.Rect) ?frame_vocabulary.Rect {
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
    clip: frame_vocabulary.Rect,
    row: usize,
    geometry: source_semantics.LineGeometry,
    cell_size: frame_vocabulary.Size,
    surface: frame_vocabulary.Size,
) Error!?frame_vocabulary.Rect {
    const transformed = try contentLineTransformRect(clip, row, geometry, cell_size);
    var row_strip = try contentCellRect(row, 0, cell_size);
    row_strip.width = surface.width;
    const visible = contentIntersectRects(transformed, row_strip) orelse return null;
    return contentIntersectRects(visible, contentSurfaceRect(surface));
}

fn contentCellVisibleClip(
    sizing: ContentCellSizing,
    row: usize,
    geometry: source_semantics.LineGeometry,
    cell_size: frame_vocabulary.Size,
    surface: frame_vocabulary.Size,
) Error!?frame_vocabulary.Rect {
    if (sizing.allocation.height == cell_size.height or geometry != .single_width)
        return contentLineClip(sizing.allocation, row, geometry, cell_size, surface);
    const transformed = try contentLineTransformRect(
        sizing.allocation,
        row,
        geometry,
        cell_size,
    );
    return contentIntersectRects(transformed, contentSurfaceRect(surface));
}

fn contentUsesMulticellAllocation(comptime Source: type, cell: Source.Cell) bool {
    return cell.height > 1 or cell.subscale_n != 0 or cell.subscale_d != 0 or
        cell.vertical_align != 0 or cell.horizontal_align != 0 or
        (cell.width > 1 and !cell.semantic_width);
}

inline fn contentUsesPlainGeometry(
    comptime Source: type,
    cell: Source.Cell,
    line_geometry: source_semantics.LineGeometry,
) bool {
    return line_geometry == .single_width and cell.width == 1 and cell.height == 1 and
        cell.x == 0 and cell.y == 0 and
        cell.subscale_n == 0 and cell.subscale_d == 0 and
        cell.vertical_align == 0 and cell.horizontal_align == 0 and
        !cell.semantic_width;
}

inline fn contentIsContextualOperatorCell(
    comptime Source: type,
    cell: Source.Cell,
    sequence: []const u32,
) Error!bool {
    if (sequence.len != 1 or cell.width != 1 or cell.height != 1 or
        cell.x != 0 or cell.y != 0 or cell.subscale_n != 0 or cell.subscale_d != 0 or
        cell.vertical_align != 0 or cell.horizontal_align != 0 or cell.semantic_width or
        Source.cellFont(cell) != 0 or Source.cellBaseline(cell) != 0 or
        Source.cellStyle(cell).invisible)
        return false;
    const value = sequence[0];
    return value >= 0x21 and value <= 0x2f or
        value >= 0x3a and value <= 0x40 or
        value >= 0x5b and value <= 0x60 or
        value >= 0x7b and value <= 0x7e;
}

fn contentSameContextualGlyphPresentation(
    comptime Source: type,
    cell: Source.Cell,
    presentation: *const Source.Presentation,
    font_variant: FontVariant,
    foreground: frame_vocabulary.Color,
) Error!bool {
    if (contentFontVariant(Source.cellStyle(cell)) != font_variant) return false;
    const colors = try contentCellColors(Source, cell, presentation);
    return std.meta.eql(colors.foreground, foreground);
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
    comptime Source: type,
    cell: Source.Cell,
    sizing: ContentCellSizing,
    row: usize,
    geometry: source_semantics.LineGeometry,
    cell_size: frame_vocabulary.Size,
    surface: frame_vocabulary.Size,
) Error!?frame_vocabulary.Rect {
    if (contentUsesMulticellAllocation(Source, cell))
        return contentCellVisibleClip(sizing, row, geometry, cell_size, surface);
    var row_strip = try contentCellRect(row, 0, cell_size);
    row_strip.width = surface.width;
    return contentLineClip(row_strip, row, geometry, cell_size, surface);
}

fn appendContentLineSolid(
    output: []frame_vocabulary.Input,
    used: *usize,
    rect: frame_vocabulary.Rect,
    clip: frame_vocabulary.Rect,
    color: frame_vocabulary.Color,
    row: usize,
    geometry: source_semantics.LineGeometry,
    cell_size: frame_vocabulary.Size,
    surface: frame_vocabulary.Size,
) Error!void {
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
    output: []frame_vocabulary.Input,
    used: *usize,
    rect: frame_vocabulary.Rect,
    color: frame_vocabulary.Color,
    sizing: ContentCellSizing,
    row: usize,
    geometry: source_semantics.LineGeometry,
    cell_size: frame_vocabulary.Size,
    surface: frame_vocabulary.Size,
) Error!void {
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

fn contentRgba(comptime Source: type, value: Source.PresentationColor) frame_vocabulary.Color {
    return .{ .r = value.r, .g = value.g, .b = value.b, .a = value.a };
}

fn contentColor(
    comptime Source: type,
    value: TextColor,
    presentation: *const Source.Presentation,
    foreground: bool,
) Error!frame_vocabulary.Color {
    return switch (value.kind) {
        .default => contentRgba(Source, if (foreground) presentation.foreground else presentation.background),
        .indexed => blk: {
            if (value.value >= presentation.palette.len) return error.InvalidColor;
            break :blk contentRgba(Source, presentation.palette[value.value]);
        },
        .rgb => .{
            .r = @intCast((value.value >> 16) & 0xff),
            .g = @intCast((value.value >> 8) & 0xff),
            .b = @intCast(value.value & 0xff),
            .a = 0xff,
        },
    };
}

fn dimContentColor(value: frame_vocabulary.Color) frame_vocabulary.Color {
    var result = value;
    result.a = @intCast((@as(u16, value.a) * 55 + 50) / 100);
    return result;
}

inline fn contentCellColors(
    comptime Source: type,
    cell: Source.Cell,
    presentation: *const Source.Presentation,
) Error!ContentCellColors {
    var foreground = try contentColor(Source, Source.cellColor(cell, .foreground), presentation, true);
    var background = try contentColor(Source, Source.cellColor(cell, .background), presentation, false);
    const style = Source.cellStyle(cell);
    if (style.reverse != presentation.reverse_screen)
        std.mem.swap(frame_vocabulary.Color, &foreground, &background);
    if (style.dim)
        foreground = dimContentColor(foreground);
    return .{
        .foreground = foreground,
        .background = background,
        .underline = try contentColor(Source, Source.cellColor(cell, .underline_color), presentation, true),
    };
}

fn appendContentInput(
    output: []frame_vocabulary.Input,
    used: *usize,
    value: frame_vocabulary.Input,
) Error!void {
    if (used.* >= output.len) return error.CommandLimit;
    output[used.*] = value;
    used.* += 1;
}

fn appendContentSolid(
    output: []frame_vocabulary.Input,
    used: *usize,
    rect: frame_vocabulary.Rect,
    clip: frame_vocabulary.Rect,
    color: frame_vocabulary.Color,
) Error!void {
    try appendContentInput(output, used, .{ .solid = .{
        .rect = rect,
        .clip = clip,
        .color = color,
    } });
}

fn appendContentCellAlpha(
    output: []frame_vocabulary.Input,
    used: *usize,
    rect: frame_vocabulary.Rect,
    resource: frame_vocabulary.ResourceView,
    color: frame_vocabulary.Color,
    sizing: ContentCellSizing,
    row: usize,
    geometry: source_semantics.LineGeometry,
    cell_size: frame_vocabulary.Size,
    surface: frame_vocabulary.Size,
) Error!void {
    const visible_clip = try contentCellVisibleClip(
        sizing,
        row,
        geometry,
        cell_size,
        surface,
    ) orelse return;
    const sized_rect = try contentCellTransformRect(rect, sizing);
    try appendContentInput(output, used, .{ .alpha_mask = .{
        .destination = try contentLineTransformRect(sized_rect, row, geometry, cell_size),
        .clip = visible_clip,
        .resource = resource,
        .color = color,
    } });
}

fn appendContentUnderline(
    output: []frame_vocabulary.Input,
    used: *usize,
    atlas: *Atlas,
    atlas_size: glyph_cache.AtlasSize,
    placeholder_resource: frame_vocabulary.ResourceRef,
    raster_scratch: []u8,
    clip: frame_vocabulary.Rect,
    y: i32,
    thickness: u16,
    line_height: u16,
    style: u8,
    color: frame_vocabulary.Color,
    sizing: ContentCellSizing,
    row: usize,
    geometry: source_semantics.LineGeometry,
    cell_size: frame_vocabulary.Size,
    surface: frame_vocabulary.Size,
) Error!bool {
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
            return false;
        },
        2 => {
            const wave = try glyph_cache.resolveSmoothWaveAtlas(
                atlas,
                clip.width,
                height,
                line_height,
                raster_scratch,
            );
            const wave_y = std.math.sub(i32, y, wave.top) catch
                return error.InvalidPresentationGeometry;
            try appendContentCellAlpha(output, used, .{
                .x = clip.x,
                .y = wave_y,
                .width = wave.width,
                .height = wave.height,
            }, .{
                .resource = placeholder_resource,
                .format = .alpha8,
                .size = .{ .width = atlas_size.width, .height = atlas_size.height },
                .source = .{
                    .x = wave.atlas_x,
                    .y = wave.atlas_y,
                    .width = wave.width,
                    .height = wave.height,
                },
            }, color, sizing, row, geometry, cell_size, surface);
            return true;
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
            return false;
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
            return false;
        },
        else => {
            try appendContentCellSolid(output, used, .{
                .x = clip.x,
                .y = y,
                .width = clip.width,
                .height = height,
            }, color, sizing, row, geometry, cell_size, surface);
            return false;
        },
    }
}

fn fixedContent26_6(value: i64) Error!i32 {
    return std.math.cast(i32, @divFloor(value, 64)) orelse
        error.InvalidPresentationGeometry;
}

fn contentLineOffset(metrics: Metrics, cell_size: frame_vocabulary.Size) i64 {
    const difference = @as(i64, cell_size.height) - @as(i64, metrics.line_height);
    return @divFloor(difference, 2);
}

fn sameIncrementalCellPresentation(
    comptime Source: type,
    impl: *const Impl,
    presentation: *const Source.Presentation,
) bool {
    if (impl.incremental_reverse_screen != presentation.reverse_screen or
        !std.meta.eql(impl.incremental_foreground, contentRgba(Source, presentation.foreground)) or
        !std.meta.eql(impl.incremental_background, contentRgba(Source, presentation.background)))
        return false;
    for (impl.incremental_palette, presentation.palette) |retained, candidate| {
        if (!std.meta.eql(retained, contentRgba(Source, candidate))) return false;
    }
    return true;
}

fn incrementalRowLayerEligible(
    comptime Source: type,
    snapshot: *const Source.Snapshot,
    row_index: usize,
) Error!bool {
    const presentation = Source.presentation(snapshot);
    const row_count = Source.rowCount(snapshot);
    if (presentation.reverse_screen or row_index >= row_count) return false;
    const row = Source.rowAt(snapshot, row_index);
    if (Source.lineGeometry(snapshot, row) != .single_width or
        Source.rowCellCount(snapshot, row) != Source.columns(snapshot))
        return false;
    for (0..Source.columns(snapshot)) |column| {
        const cell = Source.cellAt(snapshot, row, column);
        if (!contentUsesPlainGeometry(Source, cell, Source.lineGeometry(snapshot, row)) or
            blk: {
                const style = Source.cellStyle(cell);
                break :blk style.reverse or style.underline or style.strikethrough;
            } or
            Source.cellColor(cell, .background).kind != .default)
            return false;
    }
    return true;
}

fn incrementalViewEligible(
    comptime Source: type,
    snapshot: *const Source.Snapshot,
    changed_rows: ?[]const bool,
) Error!bool {
    const row_count = Source.rowCount(snapshot);
    const graphics = Source.graphics(snapshot);
    if (row_count != Source.rows(snapshot) or
        Source.graphicsImageCount(graphics) != 0 or
        Source.graphicsPlacementCount(graphics) != 0)
        return false;
    if (changed_rows) |changed| if (changed.len != row_count) return error.InvalidView;
    for (0..row_count) |row_index| {
        if (changed_rows) |changed| if (!changed[row_index]) continue;
        if (!try incrementalRowLayerEligible(Source, snapshot, row_index)) return false;
    }
    return true;
}

fn planIncrementalRows(
    comptime Source: type,
    content: *Renderer,
    snapshot: *const Source.Snapshot,
) Error!?IncrementalPlan {
    if (comptime !Source.supports_incremental) return null;
    const impl = rendererImpl(content);
    if (!impl.incremental_ready or impl.incremental_commands.len == 0 or
        impl.incremental_rows.len == 0)
        return null;
    const rows = Source.rows(snapshot);
    if (rows == 0 or rows > impl.incremental_rows.len or
        rows != impl.incremental_rows_count or
        Source.columns(snapshot) != impl.incremental_columns_count or
        Source.historyOffset(snapshot) != impl.incremental_history_offset or
        Source.alternateScreen(snapshot) != impl.incremental_alternate_screen)
        return null;
    const base_revision = Source.changedRowsBaseRevision(snapshot) orelse return null;
    if (impl.incremental_source_revision == null or
        impl.incremental_source_revision.? != base_revision)
        return null;
    const shift = Source.rowShift(snapshot) orelse 0;
    const repairs = Source.changedRows(snapshot) orelse return null;
    if (shift >= rows or repairs.len != rows or
        !sameIncrementalCellPresentation(Source, impl, Source.presentation(snapshot)))
        return null;
    var repair_count: usize = 0;
    for (repairs) |repair| if (repair) {
        repair_count += 1;
    };
    if (repair_count > @max(@as(usize, 1), repairs.len / 3)) return null;
    if (shift != 0) {
        const exposed_first = @as(usize, rows - shift);
        for (repairs[exposed_first..]) |repair| if (!repair) return null;
    }
    if (!try incrementalViewEligible(Source, snapshot, repairs)) return null;
    const y_delta_value = std.math.mul(usize, shift, impl.config.cell_size.height) catch
        return error.InvalidPresentationGeometry;
    return .{
        .shift = shift,
        .repairs = repairs,
        .y_delta = std.math.cast(i32, y_delta_value) orelse
            return error.InvalidPresentationGeometry,
    };
}

fn translateIncrementalGlyph(
    value: frame_vocabulary.Input,
    y_delta: i32,
) Error!frame_vocabulary.Input {
    return switch (value) {
        .alpha_mask => |mask| blk: {
            var shifted = mask;
            shifted.destination.y = std.math.sub(i32, shifted.destination.y, y_delta) catch
                return error.InvalidPresentationGeometry;
            shifted.clip.y = std.math.sub(i32, shifted.clip.y, y_delta) catch
                return error.InvalidPresentationGeometry;
            break :blk .{ .alpha_mask = shifted };
        },
        else => error.InvalidView,
    };
}

fn rememberIncrementalCommands(
    comptime Source: type,
    content: *Renderer,
    snapshot: *const Source.Snapshot,
) void {
    if (comptime !Source.supports_incremental) return;
    const impl = rendererImpl(content);
    const rows = Source.rows(snapshot);
    if (rows == 0 or rows > impl.incremental_rows.len) {
        impl.incremental_ready = false;
        return;
    }
    var used: usize = 0;
    for (impl.incremental_candidate_rows[0..rows], 0..) |candidate, row_index| {
        const end = std.math.add(usize, candidate.start, candidate.count) catch {
            impl.incremental_ready = false;
            return;
        };
        if (end > impl.commands.len or
            candidate.count > impl.incremental_commands.len - @min(used, impl.incremental_commands.len))
        {
            impl.incremental_ready = false;
            return;
        }
        @memcpy(
            impl.incremental_commands[used .. used + candidate.count],
            impl.commands[candidate.start..end],
        );
        impl.incremental_rows[row_index] = .{ .start = used, .count = candidate.count };
        used += candidate.count;
    }
    const presentation = Source.presentation(snapshot);
    impl.incremental_rows_count = rows;
    impl.incremental_columns_count = Source.columns(snapshot);
    impl.incremental_history_offset = Source.historyOffset(snapshot);
    impl.incremental_alternate_screen = Source.alternateScreen(snapshot);
    impl.incremental_reverse_screen = presentation.reverse_screen;
    for (presentation.palette, 0..) |value, index|
        impl.incremental_palette[index] = contentRgba(Source, value);
    impl.incremental_foreground = contentRgba(Source, presentation.foreground);
    impl.incremental_background = contentRgba(Source, presentation.background);
    impl.incremental_source_revision = Source.observationRevision(snapshot);
    impl.incremental_command_count = used;
    impl.incremental_ready = true;
}

fn sourceChangedRows(
    comptime Source: type,
    snapshot: *const Source.Snapshot,
) ?[]const bool {
    if (comptime Source.supports_incremental) return Source.changedRows(snapshot);
    return null;
}

const ContentProjection = struct {
    command_count: usize,
    default_background_end: usize,
    background_end: usize,
    has_raster: bool,
};

fn buildContentCommands(
    comptime Source: type,
    snapshot: *const Source.Snapshot,
    atlas: *Atlas,
    shape_cache: *ShapeCache,
    surface: frame_vocabulary.Size,
    output: []frame_vocabulary.Input,
    incremental_plan: ?IncrementalPlan,
    incremental_commands: []const frame_vocabulary.Input,
    incremental_rows: []const IncrementalRowCommands,
    row_ranges: ?[]IncrementalRowCommands,
    cell_size: frame_vocabulary.Size,
    cluster_scratch: []u32,
    shaped_scratch: []text.Glyph,
    raster_scratch: []u8,
) Error!ContentProjection {
    if (!glyph_cache.sameFontFaces(shape_cache, atlas))
        return error.FontSetMismatch;
    const fonts = glyph_cache.fontFaces(atlas);
    const atlas_size = glyph_cache.atlasSize(atlas);
    const presentation = Source.presentation(snapshot);
    const row_count = Source.rowCount(snapshot);
    const rows = Source.rows(snapshot);
    const columns = Source.columns(snapshot);
    if (row_count != rows) return error.InvalidView;
    if (row_ranges) |ranges| if (ranges.len != row_count) return error.InvalidView;

    const metrics = fonts.metrics();
    const whole = contentSurfaceRect(surface);
    const default_background = contentRgba(Source, presentation.background);
    const line_offset = contentLineOffset(metrics, cell_size);
    var used: usize = 0;
    try appendContentSolid(output, &used, whole, whole, default_background);
    const default_background_end = used;

    // Cell backgrounds are a distinct Kitty graphics boundary: the deepest
    // image phase sits between the default background and these overrides.
    // This required scan also records whether a decoration pass can produce
    // anything, avoiding a second full-grid walk for ordinary undecorated frames.
    var has_decorations = false;
    for (0..row_count) |row_index| {
        const row = Source.rowAt(snapshot, row_index);
        const line_geometry = Source.lineGeometry(snapshot, row);
        if (Source.rowCellCount(snapshot, row) != columns) return error.InvalidView;
        const line_columns = try contentLineColumnCount(columns, line_geometry);
        for (0..line_columns) |column| {
            const cell = Source.cellAt(snapshot, row, column);
            const style = Source.cellStyle(cell);
            has_decorations = has_decorations or style.underline or style.strikethrough;
            const reversed = style.reverse != presentation.reverse_screen;
            if (!reversed and Source.cellColor(cell, .background).kind == .default) continue;
            const colors = try contentCellColors(Source, cell, presentation);
            const physical = try contentCellRect(row_index, column, cell_size);
            if (!std.meta.eql(colors.background, default_background))
                try appendContentLineSolid(
                    output,
                    &used,
                    physical,
                    physical,
                    colors.background,
                    row_index,
                    line_geometry,
                    cell_size,
                    surface,
                );
        }
    }
    const background_end = used;
    const placeholder_resource = placeholderContentResource();
    var has_raster = false;

    // Decorations are foreground content. Ordinary negative-z images must sit
    // below them together with glyphs, not above them as if they were cells.
    for (0..row_count) |row_index| {
        if (!has_decorations) break;
        const row = Source.rowAt(snapshot, row_index);
        const line_geometry = Source.lineGeometry(snapshot, row);
        if (Source.rowCellCount(snapshot, row) != columns) return error.InvalidView;
        const line_columns = try contentLineColumnCount(columns, line_geometry);
        for (0..line_columns) |column| {
            const cell = Source.cellAt(snapshot, row, column);
            const style = Source.cellStyle(cell);
            var scalar_scratch: [24]u32 = undefined;
            const sequence = Source.cellScalars(snapshot, row_index, column, cell, &scalar_scratch);
            if (sequence.len == 0 or cell.x != 0 or cell.y != 0 or
                style.invisible or (!style.underline and !style.strikethrough))
                continue;
            const colors = try contentCellColors(Source, cell, presentation);
            const physical = try contentCellRect(row_index, column, cell_size);
            const sizing = try contentCellSizing(Source, row_index, column, cell, cell_size);
            const clip = sizing.origin;
            if (style.underline) {
                const line_y = std.math.add(i64, @as(i64, physical.y), line_offset) catch
                    return error.InvalidPresentationGeometry;
                const y = std.math.add(i64, line_y, @as(i64, metrics.underline_y)) catch
                    return error.InvalidPresentationGeometry;
                if (try appendContentUnderline(
                    output,
                    &used,
                    atlas,
                    atlas_size,
                    placeholder_resource,
                    raster_scratch,
                    clip,
                    std.math.cast(i32, y) orelse return error.InvalidPresentationGeometry,
                    metrics.underline_height,
                    metrics.line_height,
                    Source.cellUnderlineStyle(cell),
                    colors.underline,
                    sizing,
                    row_index,
                    line_geometry,
                    cell_size,
                    surface,
                )) has_raster = true;
            }
            if (style.strikethrough) {
                const line_y = std.math.add(i64, @as(i64, physical.y), line_offset) catch
                    return error.InvalidPresentationGeometry;
                const y = std.math.add(i64, line_y, @as(i64, metrics.strike_y)) catch
                    return error.InvalidPresentationGeometry;
                try appendContentCellSolid(output, &used, .{
                    .x = clip.x,
                    .y = std.math.cast(i32, y) orelse return error.InvalidPresentationGeometry,
                    .width = clip.width,
                    .height = @max(@as(u16, 1), metrics.strike_height),
                }, colors.underline, sizing, row_index, line_geometry, cell_size, surface);
            }
        }
    }

    for (0..row_count) |row_index| {
        const row = Source.rowAt(snapshot, row_index);
        const line_geometry = Source.lineGeometry(snapshot, row);
        const row_start = used;
        if (incremental_plan) |plan| {
            if (!plan.repairs[row_index]) {
                const source_row = row_index + @as(usize, plan.shift);
                if (source_row >= rows or source_row >= incremental_rows.len)
                    return error.InvalidView;
                const cached = incremental_rows[source_row];
                const cached_end = std.math.add(usize, cached.start, cached.count) catch
                    return error.InvalidView;
                if (cached_end > incremental_commands.len)
                    return error.InvalidView;
                if (cached.count > output.len - @min(used, output.len))
                    return error.CommandLimit;
                for (incremental_commands[cached.start..cached_end]) |command| {
                    output[used] = try translateIncrementalGlyph(command, plan.y_delta);
                    used += 1;
                }
                has_raster = has_raster or cached.count != 0;
                if (row_ranges) |ranges| ranges[row_index] = .{
                    .start = row_start,
                    .count = used - row_start,
                };
                continue;
            }
        }
        if (Source.rowCellCount(snapshot, row) != columns) return error.InvalidView;
        const line_columns = try contentLineColumnCount(columns, line_geometry);
        // Evaluate only after a visible font cell reaches the original checks.
        var plain_row_clip: ?frame_vocabulary.Rect = null;
        var plain_row_baseline: ?i64 = null;
        var skip_until: usize = 0;
        for (0..line_columns) |column| {
            const cell = Source.cellAt(snapshot, row, column);
            if (column < skip_until) continue;
            var scalar_scratch: [24]u32 = undefined;
            const sequence = Source.cellScalars(snapshot, row_index, column, cell, &scalar_scratch);
            if (sequence.len == 0) continue;
            if (cell.x != 0 or cell.y != 0) return error.InvalidView;
            if (Source.cellStyle(cell).invisible) continue;

            if (Source.isImagePlaceholder(snapshot, row_index, column, sequence)) continue;
            // U+0020 has no glyph ink in the accepted terminal presentation.
            // Backgrounds, decorations and cursor paint are owned by their
            // separate layers above/below this glyph pass, so shaping and
            // atlas lookup for an ordinary space can only rediscover an empty
            // raster.
            if (sequence.len == 1 and sequence[0] == ' ') continue;
            const ascii_index = glyph_cache.printableAsciiIndex(sequence);
            const colors = try contentCellColors(Source, cell, presentation);
            const font_variant = contentFontVariant(Source.cellStyle(cell));

            var run: text.Run = undefined;
            var contextual = false;
            var cluster_stride_26_6: i64 = 0;
            if (line_geometry == .single_width and
                try contentIsContextualOperatorCell(Source, cell, sequence))
            {
                const run_limit = @min(
                    line_columns - column,
                    @min(
                        maximum_operator_run_cells,
                        @as(usize, glyph_cache.maximumSequenceScalars(shape_cache)),
                    ),
                );
                var operator_scalars: [maximum_operator_run_cells]u32 = undefined;
                operator_scalars[0] = sequence[0];
                var run_end = column + 1;
                while (run_end - column < run_limit) : (run_end += 1) {
                    const next = Source.cellAt(snapshot, row, run_end);
                    var next_scalar_scratch: [24]u32 = undefined;
                    const next_sequence = Source.cellScalars(snapshot, row_index, run_end, next, &next_scalar_scratch);
                    if (!try contentIsContextualOperatorCell(Source, next, next_sequence)) break;
                    if (!try contentSameContextualGlyphPresentation(
                        Source,
                        next,
                        presentation,
                        font_variant,
                        colors.foreground,
                    )) break;
                    operator_scalars[run_end - column] = next_sequence[0];
                }
                if (run_end - column >= 2) {
                    if (try glyph_cache.shapeContextualPrimary(
                        shape_cache,
                        font_variant,
                        operator_scalars[0 .. run_end - column],
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
            const plain_geometry = contentUsesPlainGeometry(Source, cell, line_geometry);
            const sizing: ?ContentCellSizing = if (plain_geometry)
                null
            else
                try contentCellSizing(Source, row_index, column, cell, cell_size);
            const allocation_clip = if (plain_geometry)
                physical
            else
                try contentCellVisibleClip(
                    sizing.?,
                    row_index,
                    line_geometry,
                    cell_size,
                    surface,
                ) orelse continue;

            if (sequence.len == 1 and @call(.always_inline, generated.classify, .{sequence[0]}) != null) {
                const sized_frame = if (plain_geometry)
                    physical
                else
                    try contentCellTransformRect(sizing.?.origin, sizing.?);
                const generated_raster = try glyph_cache.resolveGeneratedAtlas(
                    atlas,
                    sequence[0],
                    sized_frame.width,
                    sized_frame.height,
                    generatedSizing(Source, cell),
                    raster_scratch,
                );
                has_raster = true;
                try appendContentInput(output, &used, .{ .alpha_mask = .{
                    .destination = if (plain_geometry)
                        sized_frame
                    else
                        try contentLineTransformRect(
                            sized_frame,
                            row_index,
                            line_geometry,
                            cell_size,
                        ),
                    .clip = allocation_clip,
                    .resource = .{
                        .resource = placeholder_resource,
                        .format = .alpha8,
                        .size = .{
                            .width = atlas_size.width,
                            .height = atlas_size.height,
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
                run = try glyph_cache.resolveShape(
                    shape_cache,
                    font_variant,
                    sequence,
                    cluster_scratch,
                    shaped_scratch,
                );
            const font_clip = if (plain_geometry) blk: {
                if (plain_row_clip == null) {
                    var row_clip = try contentCellRect(row_index, 0, cell_size);
                    row_clip.width = surface.width;
                    plain_row_clip = row_clip;
                }
                break :blk plain_row_clip.?;
            } else if (contextual) blk: {
                var row_clip = try contentCellRect(row_index, 0, cell_size);
                row_clip.width = surface.width;
                break :blk try contentLineClip(
                    row_clip,
                    row_index,
                    line_geometry,
                    cell_size,
                    surface,
                ) orelse continue;
            } else try contentFontVisibleClip(
                Source,
                cell,
                sizing.?,
                row_index,
                line_geometry,
                cell_size,
                surface,
            ) orelse continue;

            var pen_x = std.math.mul(i64, @as(i64, physical.x), 64) catch
                return error.InvalidPresentationGeometry;
            const baseline_px = if (plain_geometry and plain_row_baseline != null)
                plain_row_baseline.?
            else blk: {
                const value = std.math.add(
                    i64,
                    std.math.add(i64, @as(i64, physical.y), line_offset) catch
                        return error.InvalidPresentationGeometry,
                    @as(i64, metrics.baseline),
                ) catch return error.InvalidPresentationGeometry;
                if (plain_geometry) plain_row_baseline = value;
                break :blk value;
            };
            var pen_y: i64 = 0;
            for (run.glyphs) |shaped| {
                const cluster_adjust = std.math.mul(
                    i64,
                    @as(i64, shaped.cluster),
                    cluster_stride_26_6,
                ) catch return error.InvalidPresentationGeometry;
                const raster = try glyph_cache.resolveFontAtlas(
                    atlas,
                    font_variant,
                    run.face_index,
                    shaped.id,
                    raster_scratch,
                    if (!contextual and run.glyphs.len == 1) ascii_index else null,
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
                    const base_destination = frame_vocabulary.Rect{
                        .x = try fixedContent26_6(left),
                        .y = try fixedContent26_6(top),
                        .width = raster.width,
                        .height = raster.height,
                    };
                    const sized_destination = if (plain_geometry)
                        base_destination
                    else
                        try contentCellTransformRect(base_destination, sizing.?);
                    try appendContentInput(output, &used, .{ .alpha_mask = .{
                        .destination = if (plain_geometry)
                            sized_destination
                        else
                            try contentLineTransformRect(
                                sized_destination,
                                row_index,
                                line_geometry,
                                cell_size,
                            ),
                        .clip = font_clip,
                        .resource = .{
                            .resource = placeholder_resource,
                            .format = .alpha8,
                            .size = .{
                                .width = atlas_size.width,
                                .height = atlas_size.height,
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
        if (row_ranges) |ranges| ranges[row_index] = .{
            .start = row_start,
            .count = used - row_start,
        };
    }
    return .{
        .command_count = used,
        .default_background_end = default_background_end,
        .background_end = background_end,
        .has_raster = has_raster,
    };
}

fn generatedSizing(comptime Source: type, cell: Source.Cell) generated.BoxDrawingSizing {
    const proper_fraction = cell.subscale_n != 0 and cell.subscale_d != 0 and
        cell.subscale_n < cell.subscale_d;
    return .{
        .scale = cell.height,
        .subscale_n = if (proper_fraction) @intCast(cell.subscale_n) else 0,
        .subscale_d = if (proper_fraction) @intCast(cell.subscale_d) else 0,
    };
}

fn bindContentResource(commands: []frame_vocabulary.Input, resource: frame_vocabulary.ResourceRef) void {
    for (commands) |*command| switch (command.*) {
        .alpha_mask => command.alpha_mask.resource.resource = resource,
        else => {},
    };
}

fn placeholderContentResource() frame_vocabulary.ResourceRef {
    return .{
        .resource = placeholder_resource_id,
        .generation = @fromBackingInt(1),
    };
}

fn contentResource(resource: frame_vocabulary.ResourceId, generation: u64) frame_vocabulary.ResourceRef {
    std.debug.assert(generation != 0);
    return .{
        .resource = resource,
        .generation = @fromBackingInt(@intCast(generation)),
    };
}

fn contentExternalIdentity(resource: frame_vocabulary.ResourceRef) Error!u64 {
    resource.validate() catch return error.InvalidImageBinding;
    return resource.resource.identity() catch error.InvalidImageBinding;
}

fn contentGraphicsScaleFloor(
    value: u64,
    numerator: u16,
    denominator: u32,
) Error!u64 {
    if (denominator == 0) return error.InvalidPresentationGeometry;
    const product = std.math.mul(u64, value, numerator) catch
        return error.InvalidPresentationGeometry;
    return product / denominator;
}

fn contentGraphicsScaleCeil(
    value: u64,
    numerator: u16,
    denominator: u32,
) Error!u64 {
    if (denominator == 0) return error.InvalidPresentationGeometry;
    const product = std.math.mul(u64, value, numerator) catch
        return error.InvalidPresentationGeometry;
    const rounded = std.math.add(u64, product, denominator - 1) catch
        return error.InvalidPresentationGeometry;
    return rounded / denominator;
}

fn findExternalImageBinding(
    bindings: []const ExternalImageBinding,
    image_id: u32,
    generation: u64,
) ?ExternalImageBinding {
    for (bindings) |binding| {
        if (binding.image_id == image_id and binding.generation == generation)
            return binding;
    }
    return null;
}

fn findPublishedImageByResource(
    images: []const PublishedImage,
    resource: frame_vocabulary.ResourceId,
) ?PublishedImage {
    for (images) |image| {
        if (image.external.resource.resource == resource) return image;
    }
    return null;
}

fn publishedImage(
    image: source_semantics.Image,
    binding: ExternalImageBinding,
) Error!PublishedImage {
    if (binding.image_id != image.image_id or binding.generation != image.generation)
        return error.InvalidImageBinding;
    const image_width = std.math.cast(u16, image.width) orelse
        return error.InvalidPresentationGeometry;
    const image_height = std.math.cast(u16, image.height) orelse
        return error.InvalidPresentationGeometry;
    const stride = std.math.mul(usize, @as(usize, image_width), 4) catch
        return error.InvalidPresentationGeometry;
    return .{
        .image_id = image.image_id,
        .generation = image.generation,
        .external = .{
            .resource = binding.resource,
            .format = .rgba8,
            .size = .{ .width = image_width, .height = image_height },
            .stride = stride,
        },
    };
}

fn findImage(
    comptime Source: type,
    graphics: Source.Graphics,
    image_id: u32,
) ?source_semantics.Image {
    for (0..Source.graphicsImageCount(graphics)) |index| {
        const image = Source.graphicsImage(graphics, index);
        if (image.image_id == image_id) return image;
    }
    return null;
}

fn externalPlacementLessThan(
    comptime Source: type,
    graphics: Source.Graphics,
    lhs_index: u16,
    rhs_index: u16,
) bool {
    const lhs = Source.graphicsPlacement(graphics, lhs_index).?;
    const rhs = Source.graphicsPlacement(graphics, rhs_index).?;
    if (lhs.z != rhs.z) return lhs.z < rhs.z;
    if (lhs.generation != rhs.generation) return lhs.generation < rhs.generation;
    return lhs_index < rhs_index;
}

fn insertExternalPlacements(
    comptime Source: type,
    snapshot: *const Source.Snapshot,
    bindings: []const ExternalImageBinding,
    surface: frame_vocabulary.Size,
    cell_size: frame_vocabulary.Size,
    projection: ContentProjection,
    output: []frame_vocabulary.Input,
    used: *usize,
    order_storage: *[limits.maximum_image_placements]u16,
) Error!void {
    const graphics = Source.graphics(snapshot);
    if (Source.graphicsPlacementCount(graphics) == 0) return;
    if (Source.graphicsPlacementCount(graphics) > order_storage.len) return error.ImageLimit;
    var visible_count: usize = 0;
    for (0..Source.graphicsPlacementCount(graphics)) |index| {
        if (Source.graphicsPlacement(graphics, index) == null) continue;
        order_storage[visible_count] = @intCast(index);
        visible_count += 1;
    }
    if (visible_count > output.len - @min(used.*, output.len)) return error.CommandLimit;
    const order = order_storage[0..visible_count];
    std.sort.heap(
        u16,
        order,
        graphics,
        struct {
            fn lessThan(context: @TypeOf(graphics), left: u16, right: u16) bool {
                return externalPlacementLessThan(Source, context, left, right);
            }
        }.lessThan,
    );

    var deep_count: usize = 0;
    var negative_count: usize = 0;
    for (order) |index| {
        const z = Source.graphicsPlacement(graphics, index).?.z;
        if (z < content_image_below_background_threshold)
            deep_count += 1
        else if (z < 0)
            negative_count += 1;
    }

    const old_count = used.*;
    const foreground_shift = deep_count + negative_count;
    std.mem.copyBackwards(
        frame_vocabulary.Input,
        output[projection.background_end + foreground_shift .. old_count + foreground_shift],
        output[projection.background_end..old_count],
    );
    std.mem.copyBackwards(
        frame_vocabulary.Input,
        output[projection.default_background_end + deep_count .. projection.background_end + deep_count],
        output[projection.default_background_end..projection.background_end],
    );

    var deep_at = projection.default_background_end;
    var negative_at = projection.background_end + deep_count;
    var positive_at = old_count + foreground_shift;
    for (order) |index| {
        const placement = Source.graphicsPlacement(graphics, index).?;
        const image = findImage(Source, graphics, placement.image_id) orelse
            return error.InvalidView;
        const binding = findExternalImageBinding(
            bindings,
            image.image_id,
            image.generation,
        ) orelse return error.InvalidImageBinding;
        const projected = try projectExternalPlacement(
            Source,
            graphics,
            image,
            placement,
            binding,
            surface,
            cell_size,
        );
        if (placement.z < content_image_below_background_threshold) {
            output[deep_at] = projected.command;
            deep_at += 1;
        } else if (placement.z < 0) {
            output[negative_at] = projected.command;
            negative_at += 1;
        } else {
            output[positive_at] = projected.command;
            positive_at += 1;
        }
    }
    used.* = old_count + visible_count;
}

fn projectExternalPlacement(
    comptime Source: type,
    graphics: Source.Graphics,
    image: source_semantics.Image,
    placement: source_semantics.ImagePlacement,
    binding: ExternalImageBinding,
    surface: frame_vocabulary.Size,
    cell_size: frame_vocabulary.Size,
) Error!ProjectedPlacement {
    if (binding.image_id != image.image_id or binding.generation != image.generation)
        return error.InvalidImageBinding;
    if (placement.image_id != image.image_id) return error.InvalidView;
    if (graphics.cell_pixel_width == 0 or graphics.cell_pixel_height == 0)
        return error.InvalidView;
    const published = try publishedImage(image, binding);
    const source_x = std.math.cast(u16, placement.source_x) orelse
        return error.InvalidPresentationGeometry;
    const source_y = std.math.cast(u16, placement.source_y) orelse
        return error.InvalidPresentationGeometry;
    const source_width = std.math.cast(u16, placement.source_width) orelse
        return error.InvalidPresentationGeometry;
    const source_height = std.math.cast(u16, placement.source_height) orelse
        return error.InvalidPresentationGeometry;

    const canonical_x = std.math.add(
        u64,
        std.math.mul(
            u64,
            placement.column,
            graphics.cell_pixel_width,
        ) catch return error.InvalidPresentationGeometry,
        placement.cell_x,
    ) catch return error.InvalidPresentationGeometry;
    const canonical_y = std.math.add(
        u64,
        std.math.mul(
            u64,
            placement.row,
            graphics.cell_pixel_height,
        ) catch return error.InvalidPresentationGeometry,
        placement.cell_y,
    ) catch return error.InvalidPresentationGeometry;
    const canonical_right = std.math.add(u64, canonical_x, placement.pixel_width) catch
        return error.InvalidPresentationGeometry;
    const canonical_bottom = std.math.add(u64, canonical_y, placement.pixel_height) catch
        return error.InvalidPresentationGeometry;
    const left = try contentGraphicsScaleFloor(
        canonical_x,
        cell_size.width,
        graphics.cell_pixel_width,
    );
    const top = try contentGraphicsScaleFloor(
        canonical_y,
        cell_size.height,
        graphics.cell_pixel_height,
    );
    const right = try contentGraphicsScaleCeil(
        canonical_right,
        cell_size.width,
        graphics.cell_pixel_width,
    );
    const bottom = try contentGraphicsScaleCeil(
        canonical_bottom,
        cell_size.height,
        graphics.cell_pixel_height,
    );
    if (right <= left or bottom <= top)
        return error.InvalidPresentationGeometry;

    return .{
        .command = .{ .rgba = .{
            .destination = .{
                .x = std.math.cast(i32, left) orelse
                    return error.InvalidPresentationGeometry,
                .y = std.math.cast(i32, top) orelse
                    return error.InvalidPresentationGeometry,
                .width = std.math.cast(u16, right - left) orelse
                    return error.InvalidPresentationGeometry,
                .height = std.math.cast(u16, bottom - top) orelse
                    return error.InvalidPresentationGeometry,
            },
            .clip = contentSurfaceRect(surface),
            .resource = .{
                .resource = binding.resource,
                .format = .rgba8,
                .size = published.external.size,
                .source = .{
                    .x = source_x,
                    .y = source_y,
                    .width = source_width,
                    .height = source_height,
                },
            },
        } },
    };
}

fn contentCursor(
    comptime Source: type,
    snapshot: *const Source.Snapshot,
    surface: frame_vocabulary.Size,
    cell_size: frame_vocabulary.Size,
) Error!?Cursor {
    const rows = Source.rows(snapshot);
    const columns = Source.columns(snapshot);
    const cursor_row = Source.cursorRow(snapshot);
    const cursor_column = Source.cursorColumn(snapshot);
    const cursor_shape = Source.cursorShape(snapshot);
    if (!Source.cursorVisible(snapshot) or cursor_shape == .none) return null;
    if (cursor_row >= rows or cursor_column >= columns) return null;
    const presentation = Source.presentation(snapshot);
    const row = Source.rowAt(snapshot, cursor_row);
    if (cursor_column >= try contentLineColumnCount(columns, Source.lineGeometry(snapshot, row)))
        return null;
    const base_rect = try contentCellRect(cursor_row, cursor_column, cell_size);
    const rect = try contentLineClip(
        base_rect,
        cursor_row,
        Source.lineGeometry(snapshot, row),
        cell_size,
        surface,
    ) orelse return null;
    return .{
        .rect = rect,
        .clip = contentSurfaceRect(surface),
        .shape = cursor_shape,
        .color = contentRgba(Source, presentation.cursor orelse presentation.foreground),
        .text_color = contentRgba(Source, presentation.cursor_text orelse presentation.background),
    };
}

fn rendererImpl(content: *Renderer) *Impl {
    // zig-audit: acknowledge ptr_cast
    // reason: Every mutable Renderer originates from an Impl allocation in initWithStoreInner at the same address.
    // zig-audit: acknowledge align_cast
    // reason: The originating Impl allocation guarantees the concrete alignment recovered here.
    return @ptrCast(@alignCast(content));
}

fn constRendererImpl(content: *const Renderer) *const Impl {
    // zig-audit: acknowledge ptr_cast
    // reason: Every borrowed Renderer originates from an Impl allocation in initWithStoreInner at the same address.
    // zig-audit: acknowledge align_cast
    // reason: The originating Impl allocation guarantees the concrete alignment recovered here.
    return @ptrCast(@alignCast(content));
}

fn storeImpl(content: *Store) *StoreImpl {
    // zig-audit: acknowledge ptr_cast
    // reason: Every mutable Store originates from a StoreImpl allocation in initStore at the same address.
    // zig-audit: acknowledge align_cast
    // reason: The originating StoreImpl allocation guarantees the concrete alignment recovered here.
    return @ptrCast(@alignCast(content));
}

fn constStoreImpl(content: *const Store) *const StoreImpl {
    // zig-audit: acknowledge ptr_cast
    // reason: Every borrowed Store originates from a StoreImpl allocation in initStore at the same address.
    // zig-audit: acknowledge align_cast
    // reason: The originating StoreImpl allocation guarantees the concrete alignment recovered here.
    return @ptrCast(@alignCast(content));
}

test "painted-row cursor search equals the complete command oracle including clipped overhang" {
    const resource = frame_vocabulary.ResourceView{
        .resource = .{ .resource = try frame_vocabulary.ResourceId.init(1), .generation = @fromBackingInt(1) },
        .format = .alpha8,
        .size = .{ .width = 32, .height = 32 },
        .source = .{ .x = 0, .y = 0, .width = 8, .height = 8 },
    };
    var inputs: [6]frame_vocabulary.Input = undefined;
    // Deliberately cross physical rows and clip one glyph to a different row.
    for ([_]frame_vocabulary.Rect{
        .{ .x = 0, .y = -3, .width = 12, .height = 17 },
        .{ .x = 8, .y = 7, .width = 17, .height = 18 },
        .{ .x = 20, .y = 16, .width = 12, .height = 18 },
        .{ .x = 0, .y = 18, .width = 20, .height = 12 },
        .{ .x = 4, .y = 2, .width = 8, .height = 20 },
        .{ .x = 30, .y = 0, .width = 8, .height = 8 },
    }, 0..) |rect, index| {
        inputs[index] = .{ .alpha_mask = .{
            .destination = rect,
            .clip = if (index == 4) .{ .x = 0, .y = 10, .width = 30, .height = 10 } else .{ .x = 0, .y = 0, .width = 30, .height = 30 },
            .resource = resource,
            .color = .{ .r = 20, .g = 30, .b = 40, .a = 255 },
            .cursor_component = true,
        } };
    }
    // These helpers access only geometry, commands, cursor and the index. No
    // allocator, font cache, atlas or renderer lifetime is constructed here.
    var impl: Impl = undefined;
    impl.commands = &inputs;
    impl.command_count = inputs.len;
    impl.config.cell_size = .{ .width = 10, .height = 10 };
    impl.surface = .{ .width = 30, .height = 30 };
    var commands: [2][16]frame_vocabulary.Command = undefined;
    for (0..3) |row| for (0..3) |column| {
        impl.cursor = .{
            .rect = .{ .x = @intCast(column * 10), .y = @intCast(row * 10), .width = 10, .height = 10 },
            .clip = .{ .x = 0, .y = 0, .width = 30, .height = 30 },
            .shape = .block,
            .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
            .text_color = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
        };
        try indexCursorRows(&impl, impl.surface, inputs.len);
        var indexed: usize = 0;
        try appendCursorCommands(&impl, &commands[0], &indexed);
        impl.cursor_rows_ready = false;
        var complete: usize = 0;
        try appendCursorCommands(&impl, &commands[1], &complete);
        try std.testing.expectEqualDeep(commands[1][0..complete], commands[0][0..indexed]);
    };
    try indexCursorRows(&impl, .{ .width = 30, .height = (limits.maximum_rows + 1) * 10 }, inputs.len);
    try std.testing.expect(!impl.cursor_rows_ready);
}
