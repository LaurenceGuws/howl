//! Projects immutable terminal client views through howl-text into bounded Canvas producer updates.
//!
//! This layer owns presentation derivation only. It neither parses `text_v1` nor
//! retains terminal truth. Every font metric, shape, source-cluster mapping,
//! ordinary and generated terminal glyph identity/rasterization come from
//! `howl-text`. This file owns terminal-to-Canvas presentation only.

const std = @import("std");
const client = @import("howl_client");
const text = @import("howl_text");
const canvas = @import("canvas");
const generated = text.generated;
const glyph_cache = @import("terminal_glyph_cache.zig");

pub const AtlasConfig = glyph_cache.AtlasConfig;
pub const ShapeCacheConfig = glyph_cache.ShapeCacheConfig;
pub const ShapeCacheUsage = glyph_cache.ShapeCacheUsage;
pub const AtlasError = glyph_cache.AtlasError;
pub const ShapeCacheInitError = glyph_cache.ShapeCacheInitError;
pub const ShapeCacheError = glyph_cache.ShapeCacheError;

const ShapeCache = glyph_cache.ShapeCache;
const Atlas = glyph_cache.Atlas;

pub const View = client.view;
const TextColor = View.TextColor;
const Metrics = text.Metrics;

// File map:
//   - bounded Content lifecycle and Canvas resource publication
//   - terminal cell/DEC geometry, color, and decoration projection
//   - retained-row command reuse for revision-relative observations
//   - terminal text, image, and cursor projection into Canvas commands

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
    /// Optional retained-row acceleration budget. Zero disables the cache.
    incremental_row_capacity: u16 = 0,
    incremental_command_capacity: usize = 0,
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

/// Binds one exact terminal image generation to a Host-managed Canvas resource.
///
/// Content never owns or fetches the RGBA bytes. The Host keeps this association
/// so a later Canvas missing-resource result can be mapped back to the exact
/// terminal `image_id + generation` fetch key.
pub const ExternalImageBinding = struct {
    image_id: u32,
    generation: u64,
    resource: canvas.ResourceRef,
};

/// Portable static-image resource bound shared by the maintained native and Web
/// hosts. Native Canvas retains eight resources total and may spend one on the
/// glyph atlas, leaving seven exact terminal image resources.
pub const maximum_external_images: usize = 7;
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
    resource_high_water: u64,
};

/// Plans exact image generations in Content's local resource identity space.
/// Reserves the first unpublished atlas slot and never recycles identities below
/// the accepted high-water mark. No Content state or image bytes are changed.
/// Current bindings and output must be disjoint; output is disposable scratch
/// and may be partially written on error. Commit only after Content accepts.
pub fn planExternalImageBindings(
    current: []const ExternalImageBinding,
    usage: ContentUsage,
    images: []const View.Image,
    output: *[maximum_external_images]ExternalImageBinding,
) error{ ImageLimit, InvalidImageBinding, ResourceIdentityOverflow }![]const ExternalImageBinding {
    if (images.len > output.len) return error.ImageLimit;
    var allocation_cursor = usage.resource_high_water;
    var first_new = true;
    for (images, 0..) |image, index| {
        if (image.image_id == 0 or image.generation == 0)
            return error.InvalidImageBinding;
        const retained: ?ExternalImageBinding = for (current) |binding| {
            if (binding.image_id == image.image_id) break binding;
        } else null;
        if (retained) |prior| {
            if (image.generation < prior.generation) return error.InvalidImageBinding;
            var binding = prior;
            if (image.generation > prior.generation) {
                binding.generation = image.generation;
                binding.resource.generation = @fromBackingInt(@intCast(image.generation));
            }
            output[index] = binding;
            continue;
        }

        const step: u64 = if (first_new and usage.resource_generation == 0) 2 else 1;
        allocation_cursor = std.math.add(u64, allocation_cursor, step) catch
            return error.ResourceIdentityOverflow;
        first_new = false;
        if (allocation_cursor == 0 or allocation_cursor > canvas.ResourceId.max_identity)
            return error.ResourceIdentityOverflow;
        output[index] = .{
            .image_id = image.image_id,
            .generation = image.generation,
            .resource = .{
                .resource = canvas.ResourceId.local(allocation_cursor) catch
                    return error.ResourceIdentityOverflow,
                .generation = @fromBackingInt(@intCast(image.generation)),
            },
        };
    }
    return output[0..images.len];
}

pub const ContentInitError = std.mem.Allocator.Error || ShapeCacheInitError || AtlasError || error{
    InvalidContentConfig,
};

pub const ContentError = AtlasError || ShapeCacheError || error{
    InvalidView,
    InvalidColor,
    InvalidCursorContext,
    InvalidImageBinding,
    ImageLimit,
    InvalidPresentationGeometry,
    CommandLimit,
    ProducerRevisionOverflow,
    ResourceIdentityOverflow,
    ResourceGenerationOverflow,
};

const IncrementalRowCommands = struct {
    start: usize = 0,
    count: usize = 0,
};

const IncrementalPlan = struct {
    shift: u16,
    repairs: []const bool,
    y_delta: i32,
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
    incremental_commands: []canvas.Input,
    incremental_rows: []IncrementalRowCommands,
    incremental_candidate_rows: []IncrementalRowCommands,
    incremental_rows_count: u16 = 0,
    incremental_columns_count: u16 = 0,
    incremental_history_offset: u32 = 0,
    incremental_alternate_screen: bool = false,
    incremental_reverse_screen: bool = false,
    incremental_palette: [256]client.rich.Rgba = undefined,
    incremental_foreground: client.rich.Rgba = undefined,
    incremental_background: client.rich.Rgba = undefined,
    incremental_ready: bool = false,
    uploads: [1]canvas.ResourceUpload = undefined,
    external_resources: [maximum_external_images]canvas.ExternalResourceDeclaration = undefined,
    removals: [maximum_external_images]canvas.ResourceRemoval = undefined,
    placement_order: [View.maximum_image_placements]u16 = undefined,
    producer_revision: u64 = 0,
    resource_generation: u64 = 0,
    resource_high_water: u64 = 0,
    atlas_resource_id: ?canvas.ResourceId = null,
    published_images: [maximum_external_images]PublishedImage = undefined,
    published_image_count: usize = 0,
    published_atlas_generation: u64 = 0,
    published_atlas_entries: usize = 0,
};

const PublishedImage = struct {
    image_id: u32,
    generation: u64,
    external: canvas.ExternalResourceDeclaration,
};

const ProjectedPlacement = struct {
    command: canvas.Input,
};

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
        config.command_capacity == 0 or
        ((config.incremental_row_capacity == 0) != (config.incremental_command_capacity == 0)))
        return error.InvalidContentConfig;

    const impl = try allocator.create(ContentImpl);
    errdefer allocator.destroy(impl);
    const shape_cache = try glyph_cache.initShapeCache(allocator, fonts, config.shape_cache);
    errdefer glyph_cache.deinitShapeCache(shape_cache);
    const atlas = try glyph_cache.initAtlas(allocator, fonts, config.atlas);
    errdefer glyph_cache.deinitAtlas(atlas);
    const clusters = try allocator.alloc(u32, @intCast(config.shape_cache.max_sequence_scalars));
    errdefer allocator.free(clusters);
    const shaped = try allocator.alloc(text.Glyph, config.shaped_capacity);
    errdefer allocator.free(shaped);
    const raster = try allocator.alloc(u8, config.raster_bytes);
    errdefer allocator.free(raster);
    const commands = try allocator.alloc(canvas.Input, config.command_capacity);
    errdefer allocator.free(commands);
    const incremental_commands = try allocator.alloc(canvas.Input, config.incremental_command_capacity);
    errdefer allocator.free(incremental_commands);
    const incremental_rows = try allocator.alloc(IncrementalRowCommands, config.incremental_row_capacity);
    errdefer allocator.free(incremental_rows);
    const incremental_candidate_rows = try allocator.alloc(IncrementalRowCommands, config.incremental_row_capacity);
    errdefer allocator.free(incremental_candidate_rows);

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
        .incremental_commands = incremental_commands,
        .incremental_rows = incremental_rows,
        .incremental_candidate_rows = incremental_candidate_rows,
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
    const incremental_commands = impl.incremental_commands;
    const incremental_rows = impl.incremental_rows;
    const incremental_candidate_rows = impl.incremental_candidate_rows;
    impl.* = undefined;
    allocator.free(commands);
    allocator.free(incremental_candidate_rows);
    allocator.free(incremental_rows);
    allocator.free(incremental_commands);
    allocator.free(raster);
    allocator.free(shaped);
    allocator.free(clusters);
    glyph_cache.deinitAtlas(atlas);
    glyph_cache.deinitShapeCache(shape_cache);
    allocator.destroy(impl);
}

/// Explicitly forgets private shaping and raster caches.
///
/// Previously accepted Canvas/Composer state remains independent. The next
/// successful update which references raster content publishes a newer resource
/// generation. No cache reset occurs implicitly.
pub fn resetContentCaches(content: *Content) AtlasError!void {
    const impl = contentImpl(content);
    impl.incremental_ready = false;
    try glyph_cache.resetAtlas(impl.atlas);
    glyph_cache.resetShapeCache(impl.shape_cache);
}

pub fn contentUsage(content: *const Content) ContentUsage {
    const impl = constContentImpl(content);
    return .{
        .shape = glyph_cache.shapeCacheUsage(impl.shape_cache),
        .atlas_entries = glyph_cache.atlasEntryCount(impl.atlas),
        .producer_revision = impl.producer_revision,
        .resource_generation = impl.resource_generation,
        .resource_high_water = impl.resource_high_water,
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
    if (View.graphics(snapshot).images.len != 0)
        return error.InvalidImageBinding;
    return takeContentUpdateInner(content, snapshot, cursor_context, &.{});
}

/// Projects one immutable terminal view plus one exact Host image binding.
///
/// This deliberately narrow image lane accepts exactly one visible image and
/// one placement. Kitty z-index selects one of the three terminal paint phases;
/// RGBA bytes remain outside Content and Canvas recovery storage.
pub fn takeContentUpdateWithImageBinding(
    content: *Content,
    snapshot: *const View.Snapshot,
    cursor_context: ?CursorContext,
    image_binding: ExternalImageBinding,
) ContentError!canvas.ProducerUpdate {
    return takeContentUpdateWithImageBindings(
        content,
        snapshot,
        cursor_context,
        &.{image_binding},
    );
}

/// Projects one immutable terminal view plus bounded exact Host image bindings.
///
/// Every visible image descriptor requires exactly one matching binding. One
/// image resource may have multiple placements. Placements are ordered by z,
/// then by canonical placement generation, independent of backend storage order.
pub fn takeContentUpdateWithImageBindings(
    content: *Content,
    snapshot: *const View.Snapshot,
    cursor_context: ?CursorContext,
    image_bindings: []const ExternalImageBinding,
) ContentError!canvas.ProducerUpdate {
    return takeContentUpdateInner(content, snapshot, cursor_context, image_bindings);
}

fn takeContentUpdateInner(
    content: *Content,
    snapshot: *const View.Snapshot,
    cursor_context: ?CursorContext,
    image_bindings: []const ExternalImageBinding,
) ContentError!canvas.ProducerUpdate {
    const impl = contentImpl(content);
    errdefer impl.incremental_ready = false;
    const begin = View.begin(snapshot);
    const surface = try contentSurfaceSize(begin, impl.config.cell_size);
    const row_shift = View.rowShift(snapshot);
    const wants_incremental = row_shift != null and row_shift.? != 0;
    const incremental_plan = if (wants_incremental)
        try planIncrementalRows(content, snapshot)
    else
        null;
    const candidate_rows = if (wants_incremental and begin.rows <= impl.incremental_candidate_rows.len)
        impl.incremental_candidate_rows[0..begin.rows]
    else
        null;
    const projection = try buildContentCommands(
        snapshot,
        impl.atlas,
        impl.shape_cache,
        surface,
        impl.commands,
        incremental_plan,
        impl.incremental_commands,
        impl.incremental_rows,
        candidate_rows,
        impl.config.cell_size,
        impl.config.box_drawing,
        impl.clusters,
        impl.shaped,
        impl.raster,
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
        if (next_resource_high_water >= canvas.ResourceId.max_identity)
            return error.ResourceIdentityOverflow;
        next_resource_high_water += 1;
        next_atlas_resource_id = canvas.ResourceId.local(next_resource_high_water) catch
            return error.ResourceIdentityOverflow;
    }
    const resource = if (projection.has_raster) contentResource(
        next_atlas_resource_id orelse return error.InvalidPresentationGeometry,
        next_resource_generation,
    ) else null;
    if (resource) |value|
        bindContentResource(impl.commands[0..command_count], value);

    const graphics = View.graphics(snapshot);
    if (graphics.images.len > maximum_external_images) return error.ImageLimit;
    if (image_bindings.len != graphics.images.len) return error.InvalidImageBinding;
    if (graphics.placements.len > impl.placement_order.len) return error.ImageLimit;

    var next_published_images: [maximum_external_images]PublishedImage = undefined;
    var next_published_count: usize = 0;
    var external_count: usize = 0;
    var removal_count: usize = 0;
    const new_resource_floor = next_resource_high_water;
    for (graphics.images) |image| {
        const binding = findExternalImageBinding(image_bindings, image.image_id, image.generation) orelse
            return error.InvalidImageBinding;
        const published = try publishedImage(image, binding);
        const image_identity = try contentExternalIdentity(published.external.resource);
        if (next_atlas_resource_id) |atlas_id| {
            if (atlas_id == published.external.resource.resource)
                return error.InvalidImageBinding;
        }
        for (next_published_images[0..next_published_count]) |prior| {
            if (prior.image_id == published.image_id or
                prior.external.resource.resource == published.external.resource.resource)
                return error.InvalidImageBinding;
        }

        const prior_resource = findPublishedImageByResource(
            impl.published_images[0..impl.published_image_count],
            published.external.resource.resource,
        );
        if (prior_resource) |prior| {
            if (prior.image_id != published.image_id) return error.InvalidImageBinding;
            if (!std.meta.eql(prior, published) and
                @backingInt(published.external.resource.generation) <=
                    @backingInt(prior.external.resource.generation))
                return error.InvalidImageBinding;
        } else {
            if (image_identity <= new_resource_floor) return error.InvalidImageBinding;
            next_resource_high_water = @max(next_resource_high_water, image_identity);
        }
        if (prior_resource == null or !std.meta.eql(prior_resource.?, published)) {
            impl.external_resources[external_count] = published.external;
            external_count += 1;
        }
        next_published_images[next_published_count] = published;
        next_published_count += 1;
    }
    for (impl.published_images[0..impl.published_image_count]) |published| {
        if (findPublishedImageByResource(
            next_published_images[0..next_published_count],
            published.external.resource.resource,
        ) != null) continue;
        impl.removals[removal_count] = .{ .resource = published.external.resource };
        removal_count += 1;
    }

    try insertExternalPlacements(
        snapshot,
        image_bindings,
        surface,
        impl.config.cell_size,
        projection,
        impl.commands,
        &command_count,
        &impl.placement_order,
    );

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
    const incremental_enabled = wants_incremental and impl.incremental_commands.len != 0 and candidate_rows != null;
    const incremental_eligible = incremental_plan != null or
        (incremental_enabled and projection.default_background_end == 1 and
            projection.background_end == 1 and try incrementalViewEligible(snapshot, null));
    if (incremental_eligible) {
        rememberIncrementalCommands(content, snapshot);
    } else {
        impl.incremental_ready = false;
    }
    return .{
        .revision = @fromBackingInt(@intCast(next_producer_revision)),
        .uploads = uploads,
        .external_resources = impl.external_resources[0..external_count],
        .removals = impl.removals[0..removal_count],
        .commands = impl.commands[0..command_count],
        .cursor_binding = cursor_binding,
    };
}

const maximum_operator_run_cells: usize = 4;
/// Kitty's deepest image layer is strictly below INT32_MIN/2. That phase is
/// painted after the terminal default background but before non-default cell
/// backgrounds. Ordinary negative z remains under foreground content.
const content_image_below_background_threshold: i32 = std.math.minInt(i32) / 2;

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

fn contentLineScale(geometry: View.LineGeometry) ContentError!ContentLineScale {
    return switch (geometry) {
        .single_width => .{ .x = 1, .y = 1, .bottom_half = false },
        .double_width => .{ .x = 2, .y = 1, .bottom_half = false },
        .double_height_top => .{ .x = 2, .y = 2, .bottom_half = false },
        .double_height_bottom => .{ .x = 2, .y = 2, .bottom_half = true },
    };
}

fn contentLineColumnCount(columns: u16, geometry: View.LineGeometry) ContentError!u16 {
    const scale = try contentLineScale(geometry);
    return if (scale.x == 1) columns else @max(@as(u16, 1), columns / 2);
}

fn contentLineTransformRect(
    rect: canvas.Rect,
    row: usize,
    geometry: View.LineGeometry,
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
    geometry: View.LineGeometry,
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
    geometry: View.LineGeometry,
    cell_size: canvas.Size,
    surface: canvas.Size,
) ContentError!?canvas.Rect {
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

fn contentUsesMulticellAllocation(cell: View.Cell) bool {
    return cell.height > 1 or cell.subscale_n != 0 or cell.subscale_d != 0 or
        cell.vertical_align != 0 or cell.horizontal_align != 0 or
        (cell.width > 1 and !cell.semantic_width);
}

fn contentUsesPlainGeometry(cell: View.Cell, line_geometry: View.LineGeometry) bool {
    return line_geometry == .single_width and cell.width == 1 and cell.height == 1 and
        cell.x == 0 and cell.y == 0 and
        cell.subscale_n == 0 and cell.subscale_d == 0 and
        cell.vertical_align == 0 and cell.horizontal_align == 0 and
        !cell.semantic_width;
}

fn contentIsContextualOperatorCell(
    cell: View.Cell,
    scalars: []const u32,
) ContentError!bool {
    if (cell.scalar_count != 1 or cell.width != 1 or cell.height != 1 or
        cell.x != 0 or cell.y != 0 or cell.subscale_n != 0 or cell.subscale_d != 0 or
        cell.vertical_align != 0 or cell.horizontal_align != 0 or cell.semantic_width or
        cell.font != 0 or cell.baseline != 0 or View.cellStyle(cell).invisible)
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
    geometry: View.LineGeometry,
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
    geometry: View.LineGeometry,
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
    geometry: View.LineGeometry,
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
    const style = View.cellStyle(cell);
    if (style.reverse)
        std.mem.swap(canvas.Color, &foreground, &background);
    if (presentation.reverse_screen)
        std.mem.swap(canvas.Color, &foreground, &background);
    if (style.dim)
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
    geometry: View.LineGeometry,
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

fn sameIncrementalCellPresentation(
    impl: *const ContentImpl,
    presentation: *const View.Presentation,
) bool {
    return impl.incremental_reverse_screen == presentation.reverse_screen and
        std.meta.eql(impl.incremental_palette, presentation.palette) and
        std.meta.eql(impl.incremental_foreground, presentation.foreground) and
        std.meta.eql(impl.incremental_background, presentation.background);
}

fn incrementalRowLayerEligible(
    snapshot: *const View.Snapshot,
    row_index: usize,
) ContentError!bool {
    const begin = View.begin(snapshot);
    const presentation = View.presentation(snapshot);
    const rows = View.rows(snapshot);
    const cells = View.cells(snapshot);
    if (presentation.reverse_screen or row_index >= rows.len) return false;
    const row = rows[row_index];
    if (View.lineGeometry(row) != .single_width or row.cell_count != begin.columns) return false;
    const first = @as(usize, row.cell_offset);
    const count = @as(usize, row.cell_count);
    const end = std.math.add(usize, first, count) catch return error.InvalidView;
    if (end > cells.len) return error.InvalidView;
    for (cells[first..end]) |cell| {
        if (!contentUsesPlainGeometry(cell, View.lineGeometry(row)) or
            blk: {
                const style = View.cellStyle(cell);
                break :blk style.reverse or style.underline or style.strikethrough;
            } or
            cell.background.kind != .default)
            return false;
    }
    return true;
}

fn incrementalViewEligible(
    snapshot: *const View.Snapshot,
    changed_rows: ?[]const bool,
) ContentError!bool {
    const begin = View.begin(snapshot);
    const rows = View.rows(snapshot);
    const graphics = View.graphics(snapshot);
    if (rows.len != begin.rows or graphics.images.len != 0 or graphics.placements.len != 0)
        return false;
    if (changed_rows) |changed| if (changed.len != rows.len) return error.InvalidView;
    for (rows, 0..) |_, row_index| {
        if (changed_rows) |changed| if (!changed[row_index]) continue;
        if (!try incrementalRowLayerEligible(snapshot, row_index)) return false;
    }
    return true;
}

fn planIncrementalRows(
    content: *Content,
    snapshot: *const View.Snapshot,
) ContentError!?IncrementalPlan {
    const impl = contentImpl(content);
    if (!impl.incremental_ready or impl.incremental_commands.len == 0 or
        impl.incremental_rows.len == 0)
        return null;
    const begin = View.begin(snapshot);
    if (begin.rows == 0 or begin.rows > impl.incremental_rows.len or
        begin.rows != impl.incremental_rows_count or
        begin.columns != impl.incremental_columns_count or
        begin.history_offset != impl.incremental_history_offset or
        begin.alternate_screen != impl.incremental_alternate_screen)
        return null;
    const shift = View.rowShift(snapshot) orelse return null;
    if (shift == 0) return null;
    const repairs = View.changedRows(snapshot) orelse return null;
    if (shift >= begin.rows or repairs.len != begin.rows or
        !sameIncrementalCellPresentation(impl, View.presentation(snapshot)))
        return null;
    var repair_count: usize = 0;
    for (repairs) |repair| if (repair) {
        repair_count += 1;
    };
    if (repair_count > @max(@as(usize, 1), repairs.len / 3)) return null;
    if (shift != 0) {
        const exposed_first = @as(usize, begin.rows - shift);
        for (repairs[exposed_first..]) |repair| if (!repair) return null;
    }
    if (!try incrementalViewEligible(snapshot, repairs)) return null;
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
    value: canvas.Input,
    y_delta: i32,
) ContentError!canvas.Input {
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
    content: *Content,
    snapshot: *const View.Snapshot,
) void {
    const impl = contentImpl(content);
    const begin = View.begin(snapshot);
    if (begin.rows == 0 or begin.rows > impl.incremental_rows.len) {
        impl.incremental_ready = false;
        return;
    }
    var used: usize = 0;
    for (impl.incremental_candidate_rows[0..begin.rows], 0..) |candidate, row_index| {
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
    const presentation = View.presentation(snapshot);
    impl.incremental_rows_count = begin.rows;
    impl.incremental_columns_count = begin.columns;
    impl.incremental_history_offset = begin.history_offset;
    impl.incremental_alternate_screen = begin.alternate_screen;
    impl.incremental_reverse_screen = presentation.reverse_screen;
    impl.incremental_palette = presentation.palette;
    impl.incremental_foreground = presentation.foreground;
    impl.incremental_background = presentation.background;
    impl.incremental_ready = true;
}

const ContentProjection = struct {
    command_count: usize,
    default_background_end: usize,
    background_end: usize,
    has_raster: bool,
};

fn buildContentCommands(
    snapshot: *const View.Snapshot,
    atlas: *Atlas,
    shape_cache: *ShapeCache,
    surface: canvas.Size,
    output: []canvas.Input,
    incremental_plan: ?IncrementalPlan,
    incremental_commands: []const canvas.Input,
    incremental_rows: []const IncrementalRowCommands,
    row_ranges: ?[]IncrementalRowCommands,
    cell_size: canvas.Size,
    box_drawing: generated.BoxDrawingConfig,
    cluster_scratch: []u32,
    shaped_scratch: []text.Glyph,
    raster_scratch: []u8,
) ContentError!ContentProjection {
    if (!glyph_cache.sameFontSet(shape_cache, atlas))
        return error.FontSetMismatch;
    const fonts = glyph_cache.fontSet(atlas);
    const atlas_size = glyph_cache.atlasSize(atlas);
    const begin = View.begin(snapshot);
    const presentation = View.presentation(snapshot);
    const rows = View.rows(snapshot);
    const cells = View.cells(snapshot);
    const scalars = View.scalars(snapshot);
    if (rows.len != begin.rows) return error.InvalidView;
    if (row_ranges) |ranges| if (ranges.len != rows.len) return error.InvalidView;

    const metrics = fonts.metrics();
    const whole = contentSurfaceRect(surface);
    const default_background = richColor(presentation.background);
    const line_offset = contentLineOffset(metrics, cell_size);
    var used: usize = 0;
    try appendContentSolid(output, &used, whole, whole, default_background);
    const default_background_end = used;

    // Cell backgrounds are a distinct Kitty graphics boundary: the deepest
    // image phase sits between the default background and these overrides.
    for (rows, 0..) |row, row_index| {
        const first = @as(usize, row.cell_offset);
        const count = @as(usize, row.cell_count);
        const end = std.math.add(usize, first, count) catch return error.InvalidView;
        if (end > cells.len or count != begin.columns) return error.InvalidView;
        const line_columns = try contentLineColumnCount(begin.columns, View.lineGeometry(row));
        for (cells[first..][0..line_columns], 0..) |cell, column| {
            const reversed = View.cellStyle(cell).reverse != presentation.reverse_screen;
            if (!reversed and cell.background.kind == .default) continue;
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
                    View.lineGeometry(row),
                    cell_size,
                    surface,
                );
        }
    }
    const background_end = used;

    // Decorations are foreground content. Ordinary negative-z images must sit
    // below them together with glyphs, not above them as if they were cells.
    for (rows, 0..) |row, row_index| {
        const first = @as(usize, row.cell_offset);
        const count = @as(usize, row.cell_count);
        const end = std.math.add(usize, first, count) catch return error.InvalidView;
        if (end > cells.len or count != begin.columns) return error.InvalidView;
        const line_columns = try contentLineColumnCount(begin.columns, View.lineGeometry(row));
        for (cells[first..][0..line_columns], 0..) |cell, column| {
            const style = View.cellStyle(cell);
            if (cell.scalar_count == 0 or cell.x != 0 or cell.y != 0 or
                style.invisible or (!style.underline and !style.strikethrough))
                continue;
            const colors = try contentCellColors(cell, presentation);
            const physical = try contentCellRect(row_index, column, cell_size);
            const sizing = try contentCellSizing(row_index, column, cell, cell_size);
            const clip = sizing.origin;
            if (style.underline) {
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
                    View.lineGeometry(row),
                    cell_size,
                    surface,
                );
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
                }, colors.underline, sizing, row_index, View.lineGeometry(row), cell_size, surface);
            }
        }
    }

    const placeholder_resource = placeholderContentResource();
    var has_raster = false;
    for (rows, 0..) |row, row_index| {
        const row_start = used;
        if (incremental_plan) |plan| {
            if (!plan.repairs[row_index]) {
                const source_row = row_index + @as(usize, plan.shift);
                if (source_row >= begin.rows or source_row >= incremental_rows.len)
                    return error.InvalidView;
                const cached = incremental_rows[source_row];
                const cached_end = std.math.add(usize, cached.start, cached.count) catch
                    return error.InvalidView;
                if (cached_end > incremental_commands.len or
                    cached.count > output.len - @min(used, output.len))
                    return error.InvalidView;
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
        const first = @as(usize, row.cell_offset);
        const count = @as(usize, row.cell_count);
        const end = std.math.add(usize, first, count) catch return error.InvalidView;
        if (end > cells.len or count != begin.columns) return error.InvalidView;
        const line_columns = try contentLineColumnCount(begin.columns, View.lineGeometry(row));
        const row_cells = cells[first..][0..line_columns];
        // Evaluate only after a visible font cell reaches the original checks.
        var plain_row_clip: ?canvas.Rect = null;
        var plain_row_baseline: ?i64 = null;
        var skip_until: usize = 0;
        for (row_cells, 0..) |cell, column| {
            if (column < skip_until or cell.scalar_count == 0) continue;
            if (cell.x != 0 or cell.y != 0) return error.InvalidView;
            if (View.cellStyle(cell).invisible) continue;

            const scalar_first = @as(usize, cell.scalar_offset);
            const scalar_count = @as(usize, cell.scalar_count);
            const scalar_end = std.math.add(usize, scalar_first, scalar_count) catch
                return error.InvalidView;
            if (scalar_end > scalars.len) return error.InvalidView;
            const sequence = scalars[scalar_first..scalar_end];
            if (View.isImagePlaceholder(sequence)) continue;
            const ascii_index = glyph_cache.printableAsciiIndex(sequence);
            const colors = try contentCellColors(cell, presentation);

            var run: text.Run = undefined;
            var contextual = false;
            var cluster_stride_26_6: i64 = 0;
            if (View.lineGeometry(row) == .single_width and
                try contentIsContextualOperatorCell(cell, scalars))
            {
                const run_limit = @min(
                    row_cells.len - column,
                    @min(
                        maximum_operator_run_cells,
                        @as(usize, glyph_cache.maximumSequenceScalars(shape_cache)),
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
                    if (try glyph_cache.shapeContextualPrimary(
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
            const plain_geometry = contentUsesPlainGeometry(cell, View.lineGeometry(row));
            const sizing: ?ContentCellSizing = if (plain_geometry)
                null
            else
                try contentCellSizing(row_index, column, cell, cell_size);
            const allocation_clip = if (plain_geometry)
                physical
            else
                try contentCellVisibleClip(
                    sizing.?,
                    row_index,
                    View.lineGeometry(row),
                    cell_size,
                    surface,
                ) orelse continue;

            if (sequence.len == 1 and generated.classify(sequence[0]) != null) {
                const sized_frame = if (plain_geometry)
                    physical
                else
                    try contentCellTransformRect(sizing.?.origin, sizing.?);
                const generated_raster = try glyph_cache.resolveGeneratedAtlas(
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
                    .destination = if (plain_geometry)
                        sized_frame
                    else
                        try contentLineTransformRect(
                            sized_frame,
                            row_index,
                            View.lineGeometry(row),
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
                    View.lineGeometry(row),
                    cell_size,
                    surface,
                ) orelse continue;
            } else try contentFontVisibleClip(
                cell,
                sizing.?,
                row_index,
                View.lineGeometry(row),
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
                    const base_destination = canvas.Rect{
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
                                View.lineGeometry(row),
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

fn placeholderContentResource() canvas.ResourceRef {
    return .{
        .resource = canvas.ResourceId.local(1) catch unreachable,
        .generation = @fromBackingInt(1),
    };
}

fn contentResource(resource: canvas.ResourceId, generation: u64) canvas.ResourceRef {
    std.debug.assert(generation != 0);
    return .{
        .resource = resource,
        .generation = @fromBackingInt(@intCast(generation)),
    };
}

fn contentExternalIdentity(resource: canvas.ResourceRef) ContentError!u64 {
    if (resource.resource.isShared() or @backingInt(resource.generation) == 0)
        return error.InvalidImageBinding;
    return resource.resource.identity() catch error.InvalidImageBinding;
}

fn contentGraphicsScaleFloor(
    value: u64,
    numerator: u16,
    denominator: u32,
) ContentError!u64 {
    if (denominator == 0) return error.InvalidPresentationGeometry;
    const product = std.math.mul(u64, value, numerator) catch
        return error.InvalidPresentationGeometry;
    return product / denominator;
}

fn contentGraphicsScaleCeil(
    value: u64,
    numerator: u16,
    denominator: u32,
) ContentError!u64 {
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
    resource: canvas.ResourceId,
) ?PublishedImage {
    for (images) |image| {
        if (image.external.resource.resource == resource) return image;
    }
    return null;
}

fn publishedImage(
    image: View.Image,
    binding: ExternalImageBinding,
) ContentError!PublishedImage {
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

fn findImage(images: []const View.Image, image_id: u32) ?View.Image {
    for (images) |image| {
        if (image.image_id == image_id) return image;
    }
    return null;
}

fn externalPlacementLessThan(
    placements: []const View.ImagePlacement,
    lhs_index: u16,
    rhs_index: u16,
) bool {
    const lhs = placements[lhs_index];
    const rhs = placements[rhs_index];
    if (lhs.z != rhs.z) return lhs.z < rhs.z;
    if (lhs.generation != rhs.generation) return lhs.generation < rhs.generation;
    return lhs_index < rhs_index;
}

fn insertExternalPlacements(
    snapshot: *const View.Snapshot,
    bindings: []const ExternalImageBinding,
    surface: canvas.Size,
    cell_size: canvas.Size,
    projection: ContentProjection,
    output: []canvas.Input,
    used: *usize,
    order_storage: *[View.maximum_image_placements]u16,
) ContentError!void {
    const graphics = View.graphics(snapshot);
    if (graphics.placements.len == 0) return;
    if (graphics.placements.len > order_storage.len) return error.ImageLimit;
    if (graphics.placements.len > output.len - @min(used.*, output.len))
        return error.CommandLimit;

    const order = order_storage[0..graphics.placements.len];
    for (order, 0..) |*index, value| index.* = @intCast(value);
    std.sort.heap(
        u16,
        order,
        graphics.placements,
        externalPlacementLessThan,
    );

    var deep_count: usize = 0;
    var negative_count: usize = 0;
    for (order) |index| {
        const z = graphics.placements[index].z;
        if (z < content_image_below_background_threshold)
            deep_count += 1
        else if (z < 0)
            negative_count += 1;
    }

    const old_count = used.*;
    const foreground_shift = deep_count + negative_count;
    std.mem.copyBackwards(
        canvas.Input,
        output[projection.background_end + foreground_shift .. old_count + foreground_shift],
        output[projection.background_end..old_count],
    );
    std.mem.copyBackwards(
        canvas.Input,
        output[projection.default_background_end + deep_count .. projection.background_end + deep_count],
        output[projection.default_background_end..projection.background_end],
    );

    var deep_at = projection.default_background_end;
    var negative_at = projection.background_end + deep_count;
    var positive_at = old_count + foreground_shift;
    for (order) |index| {
        const placement = graphics.placements[index];
        const image = findImage(graphics.images, placement.image_id) orelse
            return error.InvalidView;
        const binding = findExternalImageBinding(
            bindings,
            image.image_id,
            image.generation,
        ) orelse return error.InvalidImageBinding;
        const projected = try projectExternalPlacement(
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
    used.* = old_count + graphics.placements.len;
}

fn projectExternalPlacement(
    graphics: View.Graphics,
    image: View.Image,
    placement: View.ImagePlacement,
    binding: ExternalImageBinding,
    surface: canvas.Size,
    cell_size: canvas.Size,
) ContentError!ProjectedPlacement {
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
    const cursor_shape = View.cursorShape(snapshot);
    if (!begin.cursor_visible or cursor_shape == .none) return null;
    if (begin.cursor_row >= begin.rows or begin.cursor_column >= begin.columns)
        return null;
    if (begin.revision == 0 or begin.terminal_revision == 0)
        return error.InvalidCursorContext;
    const presentation = View.presentation(snapshot);
    const rows = View.rows(snapshot);
    const row = rows[begin.cursor_row];
    if (begin.cursor_column >= try contentLineColumnCount(begin.columns, View.lineGeometry(row)))
        return null;
    const base_rect = try contentCellRect(begin.cursor_row, begin.cursor_column, cell_size);
    const rect = try contentLineClip(
        base_rect,
        begin.cursor_row,
        View.lineGeometry(row),
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
        .shape = switch (cursor_shape) {
            .block => .block,
            .underline => .underline,
            .bar => .bar,
            .none => .none,
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
