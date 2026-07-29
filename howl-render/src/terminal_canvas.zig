//! Renders one complete retained terminal pane into ordered Canvas commands.

const std = @import("std");
const projection = @import("terminal_projection_impl");
const images = @import("image_projection");
const text = @import("terminal_text_capability");
const canvas = @import("canvas");
const canvas_validation = @import("canvas_validation");
const features = @import("terminal_canvas_features");
const font_owner = if (features.native_text)
    @import("terminal_font_owner")
else
    struct {};
const NativeShapeBuffer = if (features.native_text)
    @typeInfo(@FieldType(text.NativeScratch, "shaper")).pointer.child
else
    void;
const NativeShapedGlyph = if (features.native_text)
    @typeInfo(@FieldType(text.NativeScratch, "shaped")).pointer.child
else
    void;

/// Preserves the terminal projection's bounded combining-scalar limit.
pub const max_combining = projection.max_combining;
/// Preserves the terminal projection's RGB fact.
pub const Rgb = projection.Rgb;
/// Preserves terminal baseline placement.
pub const CellBaseline = projection.CellBaseline;
/// Preserves terminal underline semantics.
pub const UnderlineStyle = projection.UnderlineStyle;
/// Preserves terminal cursor shape.
pub const CursorShape = projection.CursorShape;
/// Preserves DEC row geometry.
pub const LineGeometry = projection.LineGeometry;
/// Preserves caller-selected terminal selection appearance.
pub const SelectionStyle = projection.SelectionStyle;
/// Preserves one terminal selection coordinate.
pub const SelectionPoint = projection.SelectionPoint;
/// Preserves one terminal selection range.
pub const SelectionRange = projection.SelectionRange;
/// Preserves Kitty multicell sizing.
pub const TextSizing = projection.TextSizing;
/// Preserves one projected terminal cell.
pub const Cell = projection.Cell;
/// Preserves the resolved terminal cursor.
pub const Cursor = projection.Cursor;
/// Preserves the complete caller-owned terminal projection.
pub const ProjectionBaseline = projection.ProjectionBaseline;
/// Selects full or incremental semantic projection.
pub const ProjectMode = projection.ProjectMode;
/// Supplies semantic projection storage.
pub const Buffers = projection.Buffers;
/// Preserves one projected row patch.
pub const RowPatch = projection.RowPatch;
/// Borrows one semantic projection result.
pub const Update = projection.Update;
/// Reports semantic projection failures.
pub const Error = projection.Error;
/// Projects frozen VT facts into terminal cells and row patches.
pub const project = projection.project;

const PaneGeometry = struct {
    /// Places terminal column zero.
    x: i32,
    /// Places terminal row zero.
    y: i32,
    /// Clips every terminal fact to this caller-owned content rectangle.
    clip: canvas.Rect,
    /// Supplies ordinary cell metrics used by terminal shaping.
    metrics: text.CellMetrics,
    /// Locates the fallback underline from the cell top.
    underline_y: u16,
    /// Supplies fallback underline thickness.
    underline_height: u16,
    /// Locates the fallback strike line from the cell top.
    strike_y: u16,
    /// Supplies fallback strike thickness.
    strike_height: u16,
};

const RenderInput = struct {
    /// Borrows complete row-major projected cells and geometry.
    projection: ProjectionBaseline,
    /// Borrows a complete image projection produced with no retained identities.
    images: RetainedImages,
    /// Supplies terminal pixel placement and clipping.
    geometry: PaneGeometry,
};

const RetainedImages = struct {
    entries: []const ImageEntry,
    pixels: []const u8,
    placements: []const images.ImagePlacement,
};

const WorkBuffers = struct {
    inputs: []Draw,
    cursor_glyphs: []u16,
    image_order: []u16,
    decoration_pixels: []u8,
    text: if (features.native_text) text.NativeScratch else void,
};

const Draw = union(enum) {
    solid: struct { rect: canvas.Rect, clip: canvas.Rect, color: canvas.Color },
    alpha_mask: struct {
        destination: canvas.Rect,
        clip: canvas.Rect,
        resource: canvas.ResourceRef,
        size: canvas.Size,
        color: canvas.Color,
    },
    rgba: struct {
        destination: canvas.Rect,
        clip: canvas.Rect,
        resource: canvas.ResourceRef,
        size: canvas.Size,
        source: ?canvas.SourceRect,
    },
};

const ImageEntry = struct {
    identity: images.ImageIdentity,
    resource: canvas.ResourceRef,
    transferred: ?canvas.ResourceRef,
    width: u16,
    height: u16,
    pixel_offset: usize,
    pixel_count: usize,
    dirty: bool,
};

const GlyphEntry = struct {
    key: text.GlyphKey,
    resource: ?canvas.ResourceRef,
    width: u16,
    height: u16,
    left: i16,
    top: i16,
};

const MaskEntry = struct {
    hash: u64,
    style: UnderlineStyle,
    thickness: u16,
    position: i16,
    resource: canvas.ResourceRef,
    width: u16,
    height: u16,
    pixel_offset: usize,
    pixel_count: usize,
};

/// Retains one complete terminal pane and emits bounded canonical Canvas updates.
pub const Content = struct {
    /// Supplies one terminal pane's pixel geometry for retained update production.
    pub const Geometry = PaneGeometry;
    /// Supplies the exact terminal-font resource producer for one update.
    pub const FontProducer = if (features.native_text)
        union(enum) {
            local,
            shared: *font_owner.Producer,
        }
    else
        void;
    /// Fixes all retained and candidate capacity at initialization.
    pub const Limits = struct {
        /// Bounds retained row-major cells.
        cells: usize,
        /// Bounds retained row geometry.
        rows: usize,
        /// Bounds retained terminal images.
        images: usize,
        /// Bounds retained visible image placements.
        placements: usize,
        /// Bounds retained RGBA image bytes per bank.
        image_bytes: usize,
        /// Bounds stable glyph identities.
        glyphs: usize,
        /// Bounds stable decoration-mask identities.
        masks: usize,
        /// Bounds complete ordered Canvas commands.
        commands: usize,
        /// Bounds sparse uploads and removals in one update.
        resources_per_update: usize,
        /// Bounds copied upload bytes returned by one update.
        upload_bytes: usize,
        /// Bounds temporary raster bytes for one update transfer.
        raster_bytes: usize,
        /// Bounds each retained/candidate mask pixel bank and mask work.
        decoration_bytes: usize,
    };

    /// Reports invalid caller limits or construction allocation failure.
    pub const InitError = error{ InvalidLimits, OutOfMemory };
    /// Reports incompatible complete state or exact image-acceptance failure.
    pub const RecoverError = error{
        InvalidProjection,
        InvalidUpdate,
        StaleUpdate,
        ArithmeticOverflow,
        ImageLimit,
        ImagePixelLimit,
        PlacementLimit,
        ResourceMutationLimit,
        IdentityExhausted,
    };
    /// Reports malformed, stale, incompatible, or exhausted sparse terminal state.
    pub const ApplyError = error{
        InvalidUpdate,
        StaleUpdate,
        ArithmeticOverflow,
        ImageLimit,
        ImagePixelLimit,
        PlacementLimit,
        ResourceMutationLimit,
        IdentityExhausted,
    };
    /// Reports complete Canvas transfer, shaping, raster, or capacity failure.
    pub const TakeError = error{
        WorkTooSmall,
        InvalidProjection,
        InvalidGeometry,
        InvalidUpdate,
        CommandLimit,
        DecorationLimit,
        ArithmeticOverflow,
        GlyphLimit,
        MaskLimit,
        ResourceMutationLimit,
        UploadByteLimit,
        IdentityExhausted,
        OutOfMemory,
    } || text.PrepareError || text.RasterError ||
        if (features.native_text) font_owner.ResourceError else error{};

    /// Owns one terminal thread's reusable shaping, raster, and transfer storage.
    ///
    /// A Work may serve any Content whose work-facing limits do not exceed its
    /// capacities. ProducerUpdate upload, pixel, and command slices borrow this
    /// storage until the next Work operation; its removal slice borrows the
    /// producing Content until that Content's next operation.
    pub const Work = struct {
        allocator: std.mem.Allocator,
        limits: Limits,
        draws: []Draw,
        cursor_indices: []u16,
        image_indices: []u16,
        decoration_pixels: []u8,
        canvas_inputs: []canvas.Input,
        uploads: []canvas.ResourceUpload,
        upload_pixels: []u8,
        raster_arena: []u8,
        native_shape_owner: NativeShapeBuffer,
        native_codepoints: if (features.native_text) []u32 else void,
        native_clusters: if (features.native_text) []u32 else void,
        native_glyphs: if (features.native_text) []NativeShapedGlyph else void,
        native_positioned: if (features.native_text) []text.PositionedGlyph else void,

        /// Allocates all ephemeral storage transactionally.
        pub fn init(allocator: std.mem.Allocator, limits: Limits) InitError!Work {
            try validateLimits(limits);
            const draws = allocator.alloc(Draw, limits.commands) catch return error.OutOfMemory;
            errdefer allocator.free(draws);
            const cursor_indices = allocator.alloc(u16, limits.commands) catch return error.OutOfMemory;
            errdefer allocator.free(cursor_indices);
            const image_indices = allocator.alloc(u16, limits.placements) catch return error.OutOfMemory;
            errdefer allocator.free(image_indices);
            const decoration_pixels = allocator.alloc(u8, limits.decoration_bytes) catch return error.OutOfMemory;
            errdefer allocator.free(decoration_pixels);
            const canvas_inputs = allocator.alloc(canvas.Input, limits.commands) catch return error.OutOfMemory;
            errdefer allocator.free(canvas_inputs);
            const uploads = allocator.alloc(canvas.ResourceUpload, limits.resources_per_update) catch return error.OutOfMemory;
            errdefer allocator.free(uploads);
            const upload_pixels = allocator.alloc(u8, limits.upload_bytes) catch return error.OutOfMemory;
            errdefer allocator.free(upload_pixels);
            const raster_arena = allocator.alloc(u8, limits.raster_bytes) catch return error.OutOfMemory;
            errdefer allocator.free(raster_arena);
            var result = Work{
                .allocator = allocator,
                .limits = limits,
                .draws = draws,
                .cursor_indices = cursor_indices,
                .image_indices = image_indices,
                .decoration_pixels = decoration_pixels,
                .canvas_inputs = canvas_inputs,
                .uploads = uploads,
                .upload_pixels = upload_pixels,
                .raster_arena = raster_arena,
                .native_shape_owner = if (features.native_text) undefined else {},
                .native_codepoints = if (features.native_text) undefined else {},
                .native_clusters = if (features.native_text) undefined else {},
                .native_glyphs = if (features.native_text) undefined else {},
                .native_positioned = if (features.native_text) undefined else {},
            };
            if (comptime features.native_text) {
                result.native_codepoints = allocator.alloc(u32, limits.commands) catch return error.OutOfMemory;
                errdefer allocator.free(result.native_codepoints);
                result.native_clusters = allocator.alloc(u32, limits.commands) catch return error.OutOfMemory;
                errdefer allocator.free(result.native_clusters);
                result.native_glyphs = allocator.alloc(NativeShapedGlyph, limits.commands) catch return error.OutOfMemory;
                errdefer allocator.free(result.native_glyphs);
                result.native_positioned = allocator.alloc(text.PositionedGlyph, limits.commands) catch return error.OutOfMemory;
                errdefer allocator.free(result.native_positioned);
                result.native_shape_owner = NativeShapeBuffer.init(@intCast(limits.commands)) catch
                    return error.OutOfMemory;
            }
            return result;
        }

        /// Releases all ephemeral storage in reverse allocation order.
        pub fn deinit(self: *Work) void {
            if (comptime features.native_text) {
                self.native_shape_owner.deinit();
                self.allocator.free(self.native_positioned);
                self.allocator.free(self.native_glyphs);
                self.allocator.free(self.native_clusters);
                self.allocator.free(self.native_codepoints);
            }
            self.allocator.free(self.raster_arena);
            self.allocator.free(self.upload_pixels);
            self.allocator.free(self.uploads);
            self.allocator.free(self.canvas_inputs);
            self.allocator.free(self.decoration_pixels);
            self.allocator.free(self.image_indices);
            self.allocator.free(self.cursor_indices);
            self.allocator.free(self.draws);
            self.* = undefined;
        }

        fn accepts(self: *const Work, limits: Limits) bool {
            return self.limits.commands >= limits.commands and
                self.limits.placements >= limits.placements and
                self.limits.decoration_bytes >= limits.decoration_bytes and
                self.limits.resources_per_update >= limits.resources_per_update and
                self.limits.upload_bytes >= limits.upload_bytes and
                self.limits.raster_bytes >= limits.raster_bytes;
        }
    };

    allocator: std.mem.Allocator,
    limits: Limits,
    fonts: if (features.native_text) *text.FontMap else void,
    cells: []Cell,
    geometry: []LineGeometry,
    rows: u16 = 0,
    cols: u16 = 0,
    cursor: Cursor = undefined,
    images_a: []ImageEntry,
    images_b: []ImageEntry,
    image_pixels_a: []u8,
    image_pixels_b: []u8,
    placements_a: []images.ImagePlacement,
    placements_b: []images.ImagePlacement,
    images_a_active: bool = true,
    image_count: usize = 0,
    image_pixel_count: usize = 0,
    placement_count: usize = 0,
    image_revision: u64 = 0,
    image_content_revision: u64 = 0,
    glyphs: []GlyphEntry,
    glyph_candidates: []GlyphEntry,
    glyph_count: usize = 0,
    glyph_candidate_count: usize = 0,
    masks: []MaskEntry,
    mask_candidates: []MaskEntry,
    mask_count: usize = 0,
    mask_candidate_count: usize = 0,
    mask_pixels: []u8,
    mask_candidate_pixels: []u8,
    mask_pixel_count: usize = 0,
    mask_candidate_pixel_count: usize = 0,
    next_resource_id: u64 = 1,
    pending_removals: []canvas.ResourceRemoval,
    pending_removal_count: usize = 0,
    producer_revision: u64 = 1,
    last_geometry: ?PaneGeometry = null,
    initialized: bool = false,

    /// Allocates retained and per-Content candidate storage transactionally.
    ///
    /// `fonts` is borrowed for the complete Content lifetime when native text
    /// is selected. No mutation allocates after successful initialization.
    pub fn init(
        allocator: std.mem.Allocator,
        limits: Limits,
        fonts: if (features.native_text) *text.FontMap else void,
    ) InitError!Content {
        try validateLimits(limits);
        const cells = allocator.alloc(Cell, limits.cells) catch return error.OutOfMemory;
        errdefer allocator.free(cells);
        const geometry = allocator.alloc(LineGeometry, limits.rows) catch return error.OutOfMemory;
        errdefer allocator.free(geometry);
        const images_a = allocator.alloc(ImageEntry, limits.images) catch return error.OutOfMemory;
        errdefer allocator.free(images_a);
        const images_b = allocator.alloc(ImageEntry, limits.images) catch return error.OutOfMemory;
        errdefer allocator.free(images_b);
        const image_pixels_a = allocator.alloc(u8, limits.image_bytes) catch return error.OutOfMemory;
        errdefer allocator.free(image_pixels_a);
        const image_pixels_b = allocator.alloc(u8, limits.image_bytes) catch return error.OutOfMemory;
        errdefer allocator.free(image_pixels_b);
        const placements_a = allocator.alloc(images.ImagePlacement, limits.placements) catch return error.OutOfMemory;
        errdefer allocator.free(placements_a);
        const placements_b = allocator.alloc(images.ImagePlacement, limits.placements) catch return error.OutOfMemory;
        errdefer allocator.free(placements_b);
        const glyphs = allocator.alloc(GlyphEntry, limits.glyphs) catch return error.OutOfMemory;
        errdefer allocator.free(glyphs);
        const glyph_candidates = allocator.alloc(GlyphEntry, limits.glyphs) catch
            return error.OutOfMemory;
        errdefer allocator.free(glyph_candidates);
        const masks = allocator.alloc(MaskEntry, limits.masks) catch return error.OutOfMemory;
        errdefer allocator.free(masks);
        const mask_candidates = allocator.alloc(MaskEntry, limits.masks) catch
            return error.OutOfMemory;
        errdefer allocator.free(mask_candidates);
        const mask_pixels = allocator.alloc(u8, limits.decoration_bytes) catch return error.OutOfMemory;
        errdefer allocator.free(mask_pixels);
        const mask_candidate_pixels = allocator.alloc(u8, limits.decoration_bytes) catch
            return error.OutOfMemory;
        errdefer allocator.free(mask_candidate_pixels);
        const removals = allocator.alloc(canvas.ResourceRemoval, limits.resources_per_update) catch return error.OutOfMemory;
        errdefer allocator.free(removals);
        return .{
            .allocator = allocator,
            .limits = limits,
            .fonts = fonts,
            .cells = cells,
            .geometry = geometry,
            .images_a = images_a,
            .images_b = images_b,
            .image_pixels_a = image_pixels_a,
            .image_pixels_b = image_pixels_b,
            .placements_a = placements_a,
            .placements_b = placements_b,
            .glyphs = glyphs,
            .glyph_candidates = glyph_candidates,
            .masks = masks,
            .mask_candidates = mask_candidates,
            .mask_pixels = mask_pixels,
            .mask_candidate_pixels = mask_candidate_pixels,
            .pending_removals = removals,
        };
    }

    /// Releases retained and per-Content candidate allocations in reverse order.
    pub fn deinit(self: *Content) void {
        self.allocator.free(self.pending_removals);
        self.allocator.free(self.mask_candidate_pixels);
        self.allocator.free(self.mask_pixels);
        self.allocator.free(self.mask_candidates);
        self.allocator.free(self.masks);
        self.allocator.free(self.glyph_candidates);
        self.allocator.free(self.glyphs);
        self.allocator.free(self.placements_b);
        self.allocator.free(self.placements_a);
        self.allocator.free(self.image_pixels_b);
        self.allocator.free(self.image_pixels_a);
        self.allocator.free(self.images_b);
        self.allocator.free(self.images_a);
        self.allocator.free(self.geometry);
        self.allocator.free(self.cells);
        self.* = undefined;
    }

    /// Retires committed glyph and decoration resources without allocation.
    /// Projection, geometry, cursor, selections, images, producer revision,
    /// and identity high-water marks remain unchanged. The next update builds
    /// fresh raster resources; repeated calls are deterministic and silent.
    pub fn invalidateFonts(self: *Content) void {
        var removals = self.pending_removal_count;
        for (self.masks[0..self.mask_count]) |entry| {
            if (entry.resource.resource.isShared())
                @panic("shared font invalidation requires its producer");
            std.debug.assert(removals < self.pending_removals.len);
            self.pending_removals[removals] = .{ .resource = entry.resource };
            removals += 1;
        }
        for (self.glyphs[0..self.glyph_count]) |entry| {
            const resource = entry.resource orelse continue;
            if (resource.resource.isShared())
                @panic("shared font invalidation requires its producer");
            std.debug.assert(removals < self.pending_removals.len);
            self.pending_removals[removals] = .{ .resource = resource };
            removals += 1;
        }
        self.pending_removal_count = removals;
        self.glyph_count = 0;
        self.glyph_candidate_count = 0;
        self.mask_count = 0;
        self.mask_candidate_count = 0;
        self.mask_pixel_count = 0;
        self.mask_candidate_pixel_count = 0;
    }

    /// Rebinds this pane to one already accepted native map and retires every
    /// transferred font resource. The caller must quiesce synchronous shaping
    /// and raster work before changing the borrowed map.
    pub fn rebindFonts(
        self: *Content,
        fonts: *text.FontMap,
        producer: FontProducer,
    ) void {
        for (self.masks[0..self.mask_count]) |entry| {
            if (entry.resource.resource.isShared())
                releaseCommittedShared(producer, entry.resource);
        }
        for (self.glyphs[0..self.glyph_count]) |entry| {
            const resource = entry.resource orelse continue;
            if (resource.resource.isShared())
                releaseCommittedShared(producer, resource);
        }
        self.fonts = fonts;
        var removals = self.pending_removal_count;
        for (self.masks[0..self.mask_count]) |entry| {
            if (entry.resource.resource.isShared()) continue;
            std.debug.assert(removals < self.pending_removals.len);
            self.pending_removals[removals] = .{ .resource = entry.resource };
            removals += 1;
        }
        for (self.glyphs[0..self.glyph_count]) |entry| {
            const resource = entry.resource orelse continue;
            if (resource.resource.isShared()) continue;
            std.debug.assert(removals < self.pending_removals.len);
            self.pending_removals[removals] = .{ .resource = resource };
            removals += 1;
        }
        self.pending_removal_count = removals;
        self.glyph_count = 0;
        self.glyph_candidate_count = 0;
        self.mask_count = 0;
        self.mask_candidate_count = 0;
        self.mask_pixel_count = 0;
        self.mask_candidate_pixel_count = 0;
    }

    /// Releases every pane reference to shared font resources before Content
    /// or its native group owner is retired.
    pub fn releaseFontResources(
        self: *Content,
        producer: FontProducer,
    ) void {
        for (self.masks[0..self.mask_count]) |entry|
            if (entry.resource.resource.isShared())
                releaseCommittedShared(producer, entry.resource);
        for (self.glyphs[0..self.glyph_count]) |entry| {
            const resource = entry.resource orelse continue;
            if (resource.resource.isShared())
                releaseCommittedShared(producer, resource);
        }
        self.glyph_count = 0;
        self.glyph_candidate_count = 0;
        self.mask_count = 0;
        self.mask_candidate_count = 0;
        self.mask_pixel_count = 0;
        self.mask_candidate_pixel_count = 0;
    }

    /// Replaces incompatible or explicitly recovered terminal and image state.
    ///
    /// Recovery may retain an unchanged image generation when it carries no
    /// resource mutation; sparse application still requires every supplied
    /// image generation to advance.
    pub fn recover(
        self: *Content,
        full: ProjectionBaseline,
        image_update: images.Update,
    ) RecoverError!void {
        try self.validateFullProjection(full);
        try self.validateImageUpdate(image_update, full.rows, full.cols, true);
        try self.canAdvanceRevision();
        self.replaceProjection(full);
        try self.commitImages(image_update);
        self.producer_revision += 1;
        self.initialized = true;
    }

    /// Applies one compatible sparse projection and optional image transaction.
    ///
    /// The complete projection and optional image candidate are validated
    /// before mutation. Only affected rows are then copied; an image candidate
    /// commits through its already-validated inactive bank. Cursor, resource
    /// deltas, identities, and producer revision commit exactly once. Failure
    /// preserves every retained domain and revision byte-for-byte.
    pub fn apply(
        self: *Content,
        projection_update: Update,
        image_update: ?images.Update,
    ) ApplyError!void {
        try self.validateProjectionUpdate(projection_update);
        if (image_update) |update|
            try self.validateImageUpdate(update, self.rows, self.cols, false);
        try self.canAdvanceRevision();

        for (projection_update.row_patches) |patch| {
            const start = @as(usize, patch.row) * self.cols + patch.start_col;
            @memcpy(
                self.cells[start..][0..patch.cell_count],
                projection_update.cells[patch.cell_offset..][0..patch.cell_count],
            );
            self.geometry[patch.row] = patch.geometry;
        }
        if (image_update) |update| try self.commitImages(update);
        self.cursor = projection_update.cursor;
        self.producer_revision += 1;
    }

    fn validateProjectionUpdate(
        self: *const Content,
        update: Update,
    ) error{InvalidUpdate}!void {
        if (!self.initialized or update.full or update.rows != self.rows or update.cols != self.cols)
            return error.InvalidUpdate;
        if (update.cursor.visible and
            (update.cursor.row >= self.rows or update.cursor.col >= self.cols))
            return error.InvalidUpdate;
        var expected_cells: usize = 0;
        var prior_row: ?u16 = null;
        for (update.row_patches) |patch| {
            const cell_end = std.math.add(
                usize,
                patch.cell_offset,
                patch.cell_count,
            ) catch return error.InvalidUpdate;
            if (patch.row >= self.rows or patch.start_col > self.cols or
                patch.cell_count > self.cols - patch.start_col or
                patch.cell_offset != expected_cells or
                cell_end > update.cells.len or
                patch.damage_start > patch.damage_end or
                patch.damage_end >= self.cols or
                (prior_row != null and patch.row <= prior_row.?))
                return error.InvalidUpdate;
            prior_row = patch.row;
            expected_cells = std.math.add(
                usize,
                expected_cells,
                patch.cell_count,
            ) catch return error.InvalidUpdate;
        }
        if (expected_cells != update.cells.len) return error.InvalidUpdate;
    }

    fn commitImages(
        self: *Content,
        update: images.Update,
    ) error{IdentityExhausted}!void {
        const target_entries = self.inactiveImages();
        const target_pixels = self.inactiveImagePixels();
        var target_count: usize = 0;
        var pixel_count: usize = 0;
        var next_id = self.next_resource_id;
        var removals = self.pending_removal_count;

        for (self.activeImages()[0..self.image_count]) |entry| {
            var removed = false;
            for (update.removals) |id| if (id == entry.identity.id) {
                removed = true;
                break;
            };
            for (update.uploads) |upload| if (upload.identity.id == entry.identity.id) {
                removed = true;
                break;
            };
            if (removed) {
                var explicit_removal = false;
                for (update.removals) |id| if (id == entry.identity.id) {
                    explicit_removal = true;
                    break;
                };
                if (explicit_removal) {
                    if (entry.transferred) |transferred| {
                        self.pending_removals[removals] = .{
                            .resource = transferred,
                        };
                        removals += 1;
                    }
                }
                continue;
            }
            const source_pixels = self.activeImagePixels()[entry.pixel_offset..][0..entry.pixel_count];
            @memcpy(target_pixels[pixel_count..][0..entry.pixel_count], source_pixels);
            var copied_entry = entry;
            copied_entry.pixel_offset = pixel_count;
            target_entries[target_count] = copied_entry;
            target_count += 1;
            pixel_count += entry.pixel_count;
        }
        for (update.uploads) |upload| {
            const width: u16 = @intCast(upload.width);
            const height: u16 = @intCast(upload.height);
            const end = upload.pixel_offset + upload.pixel_count;
            var resource: canvas.ResourceRef = undefined;
            var active_found: ?ImageEntry = null;
            for (self.activeImages()[0..self.image_count]) |entry|
                if (entry.identity.id == upload.identity.id) {
                    active_found = entry;
                    break;
                };
            if (active_found) |old| {
                resource = .{
                    .resource = old.resource.resource,
                    .generation = @fromBackingInt(@intCast(upload.identity.generation)),
                };
            } else {
                resource = .{
                    .resource = canvas.ResourceId.local(next_id) catch
                        return error.IdentityExhausted,
                    .generation = @fromBackingInt(@intCast(upload.identity.generation)),
                };
                next_id += 1;
            }
            @memcpy(
                target_pixels[pixel_count..][0..upload.pixel_count],
                update.pixels[upload.pixel_offset..end],
            );
            target_entries[target_count] = .{
                .identity = upload.identity,
                .resource = resource,
                .transferred = if (active_found) |old| old.transferred else null,
                .width = width,
                .height = height,
                .pixel_offset = pixel_count,
                .pixel_count = upload.pixel_count,
                .dirty = true,
            };
            target_count += 1;
            pixel_count += upload.pixel_count;
        }
        @memcpy(self.inactivePlacements()[0..update.placements.len], update.placements);
        self.images_a_active = !self.images_a_active;
        self.image_count = target_count;
        self.image_pixel_count = pixel_count;
        self.placement_count = update.placements.len;
        self.pending_removal_count = removals;
        self.next_resource_id = next_id;
        self.image_revision = update.generation;
        self.image_content_revision = update.content_generation;
    }

    /// Transfers one complete command list and its pending sparse resources
    /// through the exact local or shared font producer.
    ///
    /// The caller must first secure its destination capacity, then copy or
    /// synchronously apply the returned slices before any further Content
    /// operation. A successful call consumes pending uploads and removals and
    /// commits current glyph and decoration resources. Upload, pixel, and
    /// command slices borrow Work until its next operation; removals borrow
    /// Content until its next operation. No acknowledgement follows.
    pub fn takeUpdate(
        self: *Content,
        work: *Work,
        geometry: Geometry,
        producer: FontProducer,
    ) TakeError!canvas.ProducerUpdate {
        errdefer if (comptime features.native_text) switch (producer) {
            .local => {},
            .shared => |shared| shared.cancelUpdate(),
        };
        if (!self.initialized) return error.InvalidProjection;
        if (!work.accepts(self.limits)) return error.WorkTooSmall;
        var fixed = std.heap.FixedBufferAllocator.init(work.raster_arena);
        self.glyph_candidate_count = 0;
        self.mask_candidate_count = 0;
        self.mask_candidate_pixel_count = 0;
        const id_before = self.next_resource_id;
        const revision_before = self.producer_revision;
        const removals_before = self.pending_removal_count;
        const geometry_changed = self.last_geometry == null or
            !std.meta.eql(self.last_geometry.?, geometry);
        var upload_count: usize = 0;
        var upload_bytes: usize = 0;
        errdefer {
            self.glyph_candidate_count = 0;
            self.mask_candidate_count = 0;
            self.mask_candidate_pixel_count = 0;
            self.next_resource_id = id_before;
            self.producer_revision = revision_before;
            self.pending_removal_count = removals_before;
        }
        for (self.activeImages()[0..self.image_count]) |entry| {
            if (!entry.dirty) continue;
            try appendUpload(
                work,
                &upload_count,
                &upload_bytes,
                entry.resource,
                .rgba8,
                entry.width,
                entry.height,
                self.activeImagePixels()[entry.pixel_offset..][0..entry.pixel_count],
            );
        }
        var build = Build{
            .allocator = fixed.allocator(),
            .input = .{
                .projection = self.baseline(),
                .images = .{
                    .entries = self.activeImages()[0..self.image_count],
                    .pixels = self.activeImagePixels()[0..self.image_pixel_count],
                    .placements = self.activePlacements()[0..self.placement_count],
                },
                .geometry = geometry,
            },
            .fonts = self.fonts,
            .producer = producer,
            .buffers = .{
                .inputs = work.draws,
                .cursor_glyphs = work.cursor_indices,
                .image_order = work.image_indices,
                .decoration_pixels = work.decoration_pixels,
                .text = if (features.native_text) .{
                    .shaper = &work.native_shape_owner,
                    .codepoints = work.native_codepoints,
                    .clusters = work.native_clusters,
                    .shaped = work.native_glyphs,
                    .positioned = work.native_positioned,
                } else {},
            },
            .content = self,
            .work = work,
            .upload_count = &upload_count,
            .upload_bytes = &upload_bytes,
        };
        try validatePane(build.input);
        try build.backgrounds();
        try build.orderImages();
        try build.imagesFor(false);
        try build.glyphs();
        try build.decorations();
        try build.cursor();
        try build.imagesFor(true);
        const mask_changed = try self.appendRetiredMasks();
        const glyph_changed = try self.appendRetiredGlyphs();
        if (build.input_used > work.canvas_inputs.len) return error.CommandLimit;
        for (build.buffers.inputs[0..build.input_used], 0..) |draw, index|
            work.canvas_inputs[index] = drawInput(draw);
        if (geometry_changed or glyph_changed or mask_changed)
            try self.advanceRevision();
        self.releaseRetiredSharedGlyphs(producer);
        self.releaseRetiredSharedMasks(producer);
        std.mem.swap([]GlyphEntry, &self.glyphs, &self.glyph_candidates);
        self.glyph_count = self.glyph_candidate_count;
        self.glyph_candidate_count = 0;
        std.mem.swap([]MaskEntry, &self.masks, &self.mask_candidates);
        std.mem.swap([]u8, &self.mask_pixels, &self.mask_candidate_pixels);
        self.mask_count = self.mask_candidate_count;
        self.mask_pixel_count = self.mask_candidate_pixel_count;
        self.mask_candidate_count = 0;
        self.mask_candidate_pixel_count = 0;
        self.last_geometry = geometry;
        for (self.activeImages()[0..self.image_count]) |*entry| {
            if (entry.dirty) entry.transferred = entry.resource;
            entry.dirty = false;
        }
        const result = canvas.ProducerUpdate{
            .revision = @fromBackingInt(@intCast(self.producer_revision)),
            .uploads = work.uploads[0..upload_count],
            .removals = self.pending_removals[0..self.pending_removal_count],
            .commands = work.canvas_inputs[0..build.input_used],
        };
        self.pending_removal_count = 0;
        if (comptime features.native_text) switch (producer) {
            .local => {},
            .shared => |shared| shared.commitUpdate(),
        };
        return result;
    }

    /// Produces one explicitly source-local update for non-sharing capability
    /// graphs and retained local-only proofs.
    pub fn takeLocalUpdate(
        self: *Content,
        work: *Work,
        geometry: Geometry,
    ) TakeError!canvas.ProducerUpdate {
        if (comptime features.native_text)
            return self.takeUpdate(work, geometry, .local);
        return self.takeUpdate(work, geometry, {});
    }

    fn appendRetiredGlyphs(self: *Content) TakeError!bool {
        var changed = self.glyph_count != self.glyph_candidate_count;
        for (self.glyphs[0..self.glyph_count]) |entry| {
            var retained = false;
            for (self.glyph_candidates[0..self.glyph_candidate_count]) |candidate| {
                if (!std.meta.eql(entry.key, candidate.key)) continue;
                retained = true;
                break;
            }
            if (retained) continue;
            changed = true;
            const resource = entry.resource orelse continue;
            if (resource.resource.isShared()) continue;
            if (self.pending_removal_count >= self.pending_removals.len)
                return error.ResourceMutationLimit;
            self.pending_removals[self.pending_removal_count] = .{
                .resource = resource,
            };
            self.pending_removal_count += 1;
        }
        return changed;
    }

    fn appendRetiredMasks(self: *Content) TakeError!bool {
        var changed = self.mask_count != self.mask_candidate_count;
        for (self.masks[0..self.mask_count]) |entry| {
            var retained = false;
            for (self.mask_candidates[0..self.mask_candidate_count]) |candidate| {
                if (!std.meta.eql(entry.resource, candidate.resource)) continue;
                retained = true;
                break;
            }
            if (retained) continue;
            changed = true;
            if (entry.resource.resource.isShared()) continue;
            if (self.pending_removal_count >= self.pending_removals.len)
                return error.ResourceMutationLimit;
            self.pending_removals[self.pending_removal_count] = .{
                .resource = entry.resource,
            };
            self.pending_removal_count += 1;
        }
        return changed;
    }

    fn releaseRetiredSharedGlyphs(
        self: *Content,
        producer: FontProducer,
    ) void {
        for (self.glyphs[0..self.glyph_count]) |entry| {
            const resource = entry.resource orelse continue;
            if (!resource.resource.isShared()) continue;
            var retained = false;
            for (self.glyph_candidates[0..self.glyph_candidate_count]) |candidate|
                if (std.meta.eql(entry.key, candidate.key)) {
                    retained = true;
                    break;
                };
            if (!retained) releaseCommittedShared(producer, resource);
        }
    }

    fn releaseRetiredSharedMasks(
        self: *Content,
        producer: FontProducer,
    ) void {
        for (self.masks[0..self.mask_count]) |entry| {
            if (!entry.resource.resource.isShared()) continue;
            var retained = false;
            for (self.mask_candidates[0..self.mask_candidate_count]) |candidate|
                if (std.meta.eql(entry.resource, candidate.resource)) {
                    retained = true;
                    break;
                };
            if (!retained) releaseCommittedShared(producer, entry.resource);
        }
    }

    fn replaceProjection(self: *Content, full: ProjectionBaseline) void {
        @memcpy(self.cells[0..full.cells.len], full.cells);
        @memcpy(self.geometry[0..full.geometry.len], full.geometry);
        self.rows = full.rows;
        self.cols = full.cols;
        self.cursor = full.cursor;
    }

    fn validateFullProjection(
        self: *const Content,
        full: ProjectionBaseline,
    ) RecoverError!void {
        const cell_count = std.math.mul(usize, full.rows, full.cols) catch
            return error.ArithmeticOverflow;
        if (full.rows == 0 or full.cols == 0 or
            full.rows > self.limits.rows or cell_count > self.limits.cells or
            full.cells.len != cell_count or full.geometry.len != full.rows or
            (full.cursor.visible and
                (full.cursor.row >= full.rows or full.cursor.col >= full.cols)))
            return error.InvalidProjection;
    }

    fn validateImageUpdate(
        self: *const Content,
        update: images.Update,
        rows: u16,
        cols: u16,
        allow_unchanged_generation: bool,
    ) ApplyError!void {
        const initial_empty = !self.initialized and update.generation == 0 and
            update.content_generation == 0 and update.uploads.len == 0 and
            update.removals.len == 0 and update.placements.len == 0;
        const unchanged_recovery = allow_unchanged_generation and
            update.generation == self.image_revision and
            update.content_generation == self.image_content_revision and
            update.uploads.len == 0 and update.removals.len == 0;
        if (!initial_empty and !unchanged_recovery and
            (update.generation == 0 or update.generation < self.image_revision or
                (!allow_unchanged_generation and update.generation == self.image_revision)))
            return error.StaleUpdate;
        if (!initial_empty and !unchanged_recovery and (update.content_generation == 0 or
            update.content_generation < self.image_content_revision or
            ((update.uploads.len != 0 or update.removals.len != 0) and
                update.content_generation <= self.image_content_revision)))
            return error.StaleUpdate;
        if (update.placements.len > self.limits.placements) return error.PlacementLimit;
        var retained_count = self.image_count;
        var retained_bytes = self.image_pixel_count;
        var removals = self.pending_removal_count;
        var new_resources: usize = 0;

        for (update.removals, 0..) |id, index| {
            if (id == 0) return error.InvalidUpdate;
            for (update.removals[index + 1 ..]) |other|
                if (other == id) return error.InvalidUpdate;
            for (update.uploads) |upload|
                if (upload.identity.id == id) return error.InvalidUpdate;
            for (self.activeImages()[0..self.image_count]) |entry| {
                if (entry.identity.id != id) continue;
                retained_count -= 1;
                retained_bytes -= entry.pixel_count;
                if (entry.transferred != null) removals += 1;
                break;
            }
        }
        for (update.uploads, 0..) |upload, index| {
            if (upload.identity.id == 0 or upload.identity.generation == 0)
                return error.InvalidUpdate;
            for (update.uploads[index + 1 ..]) |other|
                if (other.identity.id == upload.identity.id) return error.InvalidUpdate;
            const width = std.math.cast(u16, upload.width) orelse return error.InvalidUpdate;
            const height = std.math.cast(u16, upload.height) orelse return error.InvalidUpdate;
            if (width == 0 or height == 0) return error.InvalidUpdate;
            const end = std.math.add(usize, upload.pixel_offset, upload.pixel_count) catch
                return error.ArithmeticOverflow;
            const row_bytes = std.math.mul(usize, width, 4) catch
                return error.ArithmeticOverflow;
            const required = std.math.mul(usize, row_bytes, height) catch
                return error.ArithmeticOverflow;
            if (end > update.pixels.len or required != upload.pixel_count)
                return error.InvalidUpdate;
            var replaced = false;
            for (self.activeImages()[0..self.image_count]) |entry| {
                if (entry.identity.id != upload.identity.id) continue;
                if (upload.identity.generation <= entry.identity.generation)
                    return error.StaleUpdate;
                retained_bytes -= entry.pixel_count;
                replaced = true;
                break;
            }
            if (!replaced) {
                retained_count += 1;
                new_resources += 1;
            }
            retained_bytes = std.math.add(usize, retained_bytes, upload.pixel_count) catch
                return error.ArithmeticOverflow;
        }
        if (retained_count > self.limits.images) return error.ImageLimit;
        if (retained_bytes > self.limits.image_bytes) return error.ImagePixelLimit;
        if (removals > self.pending_removals.len or
            update.uploads.len > self.limits.resources_per_update)
            return error.ResourceMutationLimit;
        const new_resource_count = std.math.cast(u64, new_resources) orelse
            return error.IdentityExhausted;
        if (new_resource_count > 0) {
            if (self.next_resource_id == 0 or
                self.next_resource_id > canvas.ResourceId.max_identity)
                return error.IdentityExhausted;
            const remaining = canvas.ResourceId.max_identity -
                self.next_resource_id + 1;
            if (new_resource_count > remaining)
                return error.IdentityExhausted;
        }
        for (update.placements) |placement| {
            if (placement.image_id == 0 or placement.generation == 0 or
                placement.row >= rows or placement.col >= cols)
                return error.InvalidUpdate;
            var exists = false;
            var width: u32 = 0;
            var height: u32 = 0;
            for (update.uploads) |upload| {
                if (upload.identity.id != placement.image_id) continue;
                exists = true;
                width = upload.width;
                height = upload.height;
                break;
            }
            if (!exists) for (self.activeImages()[0..self.image_count]) |entry| {
                if (entry.identity.id != placement.image_id) continue;
                var removed = false;
                for (update.removals) |id| if (id == entry.identity.id) {
                    removed = true;
                    break;
                };
                if (!removed) {
                    exists = true;
                    width = entry.width;
                    height = entry.height;
                }
                break;
            };
            if (!exists) return error.InvalidUpdate;
            if (placement.source_x >= width or placement.source_y >= height)
                return error.InvalidUpdate;
            const source_width = if (placement.source_width == 0)
                width - placement.source_x
            else
                placement.source_width;
            const source_height = if (placement.source_height == 0)
                height - placement.source_y
            else
                placement.source_height;
            if (source_width == 0 or source_height == 0 or
                source_width > width - placement.source_x or
                source_height > height - placement.source_y or
                placement.pixel_width == 0 or placement.pixel_height == 0 or
                placement.pixel_width > std.math.maxInt(u16) or
                placement.pixel_height > std.math.maxInt(u16))
                return error.InvalidUpdate;
        }
    }

    fn canAdvanceRevision(self: *const Content) error{IdentityExhausted}!void {
        if (self.producer_revision == std.math.maxInt(u64))
            return error.IdentityExhausted;
    }

    fn activeImages(self: *const Content) []ImageEntry {
        return if (self.images_a_active) self.images_a else self.images_b;
    }

    fn inactiveImages(self: *Content) []ImageEntry {
        return if (self.images_a_active) self.images_b else self.images_a;
    }

    fn activeImagePixels(self: *const Content) []u8 {
        return if (self.images_a_active) self.image_pixels_a else self.image_pixels_b;
    }

    fn inactiveImagePixels(self: *Content) []u8 {
        return if (self.images_a_active) self.image_pixels_b else self.image_pixels_a;
    }

    fn activePlacements(self: *const Content) []images.ImagePlacement {
        return if (self.images_a_active) self.placements_a else self.placements_b;
    }

    fn inactivePlacements(self: *Content) []images.ImagePlacement {
        return if (self.images_a_active) self.placements_b else self.placements_a;
    }

    fn advanceRevision(self: *Content) error{IdentityExhausted}!void {
        if (self.producer_revision == std.math.maxInt(u64))
            return error.IdentityExhausted;
        self.producer_revision += 1;
    }

    fn appendUpload(
        work: *Work,
        count: *usize,
        bytes_used: *usize,
        resource: canvas.ResourceRef,
        format: canvas.ResourceFormat,
        width: u16,
        height: u16,
        bytes: []const u8,
    ) TakeError!void {
        if (count.* >= work.uploads.len) return error.ResourceMutationLimit;
        const bytes_per_pixel: usize = if (format == .rgba8) 4 else 1;
        const validation_result = switch (format) {
            .alpha8 => canvas_validation.alpha8(bytes.len, width, height, width),
            .rgba8 => canvas_validation.rgba8(
                bytes.len,
                width,
                height,
                @as(usize, width) * 4,
            ),
        };
        validation_result catch |err| return switch (err) {
            error.ArithmeticOverflow => error.ArithmeticOverflow,
            else => error.InvalidUpdate,
        };
        if (bytes_used.* > work.upload_pixels.len or
            bytes.len > work.upload_pixels.len - bytes_used.*)
            return error.UploadByteLimit;
        const destination = work.upload_pixels[bytes_used.*..][0..bytes.len];
        @memcpy(destination, bytes);
        work.uploads[count.*] = .{
            .resource = resource,
            .format = format,
            .pixels = .{
                .bytes = destination,
                .width = width,
                .height = height,
                .stride = @as(usize, width) * bytes_per_pixel,
            },
        };
        count.* += 1;
        bytes_used.* += bytes.len;
    }

    fn glyph(
        self: *Content,
        work: *Work,
        allocator: std.mem.Allocator,
        fonts: if (features.native_text) *text.FontMap else void,
        producer: FontProducer,
        key: text.GlyphKey,
        upload_count: *usize,
        upload_bytes: *usize,
    ) TakeError!*const GlyphEntry {
        for (self.glyph_candidates[0..self.glyph_candidate_count]) |*entry|
            if (std.meta.eql(entry.key, key)) return entry;
        if (self.glyph_candidate_count >= self.glyph_candidates.len)
            return error.GlyphLimit;
        for (self.glyphs[0..self.glyph_count]) |entry| {
            if (!std.meta.eql(entry.key, key)) continue;
            self.glyph_candidates[self.glyph_candidate_count] = entry;
            self.glyph_candidate_count += 1;
            const retained = &self.glyph_candidates[self.glyph_candidate_count - 1];
            if (retained.resource) |resource|
                try redeclareGlyphIfRequired(
                    work,
                    allocator,
                    fonts,
                    producer,
                    key,
                    retained,
                    resource,
                    upload_count,
                    upload_bytes,
                );
            return retained;
        }
        var raster = if (comptime features.native_text)
            try text.rasterizeGlyph(allocator, fonts, key)
        else
            try text.rasterizeGlyph(allocator, key);
        defer raster.deinit();
        const produced = if (raster.width != 0 and raster.height != 0)
            try produceGlyphResource(
                &self.next_resource_id,
                producer,
                key,
                raster.width,
                raster.height,
                raster.pixels,
            )
        else
            null;
        const resource = if (produced) |value| value.resource else null;
        if (produced) |value| if (value.declaration_required)
            try appendUpload(
                work,
                upload_count,
                upload_bytes,
                value.resource,
                .alpha8,
                raster.width,
                raster.height,
                raster.pixels,
            );
        self.glyph_candidates[self.glyph_candidate_count] = .{
            .key = key,
            .resource = resource,
            .width = raster.width,
            .height = raster.height,
            .left = raster.left,
            .top = raster.top,
        };
        self.glyph_candidate_count += 1;
        return &self.glyph_candidates[self.glyph_candidate_count - 1];
    }

    fn mask(
        self: *Content,
        work: *Work,
        producer: FontProducer,
        style: UnderlineStyle,
        thickness: u16,
        position: i16,
        pixels: []const u8,
        width: u16,
        height: u16,
        upload_count: *usize,
        upload_bytes: *usize,
    ) TakeError!*const MaskEntry {
        const hash = std.hash.Wyhash.hash(0, pixels);
        for (self.mask_candidates[0..self.mask_candidate_count]) |*entry|
            if (entry.hash == hash and entry.style == style and
                entry.thickness == thickness and entry.position == position and
                entry.width == width and entry.height == height and
                std.mem.eql(
                    u8,
                    self.mask_candidate_pixels[entry.pixel_offset..][0..entry.pixel_count],
                    pixels,
                ))
                return entry;
        if (self.mask_candidate_count >= self.mask_candidates.len)
            return error.MaskLimit;
        if (self.mask_candidate_pixel_count > self.mask_candidate_pixels.len or
            pixels.len >
                self.mask_candidate_pixels.len - self.mask_candidate_pixel_count)
            return error.MaskLimit;
        for (self.masks[0..self.mask_count]) |entry| {
            if (entry.hash != hash or entry.style != style or
                entry.thickness != thickness or entry.position != position or
                entry.width != width or entry.height != height or
                !std.mem.eql(
                    u8,
                    self.mask_pixels[entry.pixel_offset..][0..entry.pixel_count],
                    pixels,
                ))
                continue;
            const candidate = MaskEntry{
                .hash = entry.hash,
                .style = entry.style,
                .thickness = entry.thickness,
                .position = entry.position,
                .resource = entry.resource,
                .width = entry.width,
                .height = entry.height,
                .pixel_offset = self.mask_candidate_pixel_count,
                .pixel_count = entry.pixel_count,
            };
            @memcpy(
                self.mask_candidate_pixels[self.mask_candidate_pixel_count..][0..entry.pixel_count],
                pixels,
            );
            self.mask_candidates[self.mask_candidate_count] = candidate;
            self.mask_candidate_pixel_count += entry.pixel_count;
            self.mask_candidate_count += 1;
            try redeclareMaskIfRequired(
                work,
                producer,
                &self.mask_candidates[self.mask_candidate_count - 1],
                pixels,
                upload_count,
                upload_bytes,
            );
            return &self.mask_candidates[self.mask_candidate_count - 1];
        }
        const produced = try produceDecorationResource(
            &self.next_resource_id,
            producer,
            style,
            width,
            height,
            thickness,
            position,
            pixels,
        );
        const resource = produced.resource;
        if (produced.declaration_required)
            try appendUpload(
                work,
                upload_count,
                upload_bytes,
                resource,
                .alpha8,
                width,
                height,
                pixels,
            );
        self.mask_candidates[self.mask_candidate_count] = .{
            .hash = hash,
            .style = style,
            .thickness = thickness,
            .position = position,
            .resource = resource,
            .width = width,
            .height = height,
            .pixel_offset = self.mask_candidate_pixel_count,
            .pixel_count = pixels.len,
        };
        @memcpy(
            self.mask_candidate_pixels[self.mask_candidate_pixel_count..][0..pixels.len],
            pixels,
        );
        self.mask_candidate_pixel_count += pixels.len;
        self.mask_candidate_count += 1;
        return &self.mask_candidates[self.mask_candidate_count - 1];
    }

    fn baseline(self: *const Content) ProjectionBaseline {
        const count = @as(usize, self.rows) * self.cols;
        return .{
            .rows = self.rows,
            .cols = self.cols,
            .cursor = self.cursor,
            .cells = self.cells[0..count],
            .geometry = self.geometry[0..self.rows],
        };
    }
};

const Build = struct {
    allocator: std.mem.Allocator,
    input: RenderInput,
    fonts: if (features.native_text) *text.FontMap else void,
    producer: Content.FontProducer,
    buffers: WorkBuffers,
    content: *Content,
    work: *Content.Work,
    upload_count: *usize,
    upload_bytes: *usize,
    input_used: usize = 0,
    cursor_used: usize = 0,
    decoration_used: usize = 0,

    fn backgrounds(self: *Build) Content.TakeError!void {
        var row: usize = 0;
        while (row < self.input.projection.rows) : (row += 1) {
            var col: usize = 0;
            while (col < self.input.projection.cols) : (col += 1) {
                const cell_value = self.cell(row, col);
                var run: usize = 1;
                while (col + run < self.input.projection.cols and
                    std.meta.eql(
                        self.cell(row, col + run).background,
                        cell_value.background,
                    ))
                    run += 1;
                try self.append(.{ .solid = .{
                    .rect = try self.cellRect(row, col, @intCast(run), 1),
                    .clip = self.input.geometry.clip,
                    .color = color(cell_value.background),
                } });
                col += run - 1;
            }
        }
    }

    fn orderImages(self: *Build) Content.TakeError!void {
        const placements = self.input.images.placements;
        if (self.buffers.image_order.len < placements.len)
            return error.InvalidProjection;
        for (placements, 0..) |_, index|
            self.buffers.image_order[index] = @intCast(index);
        var index: usize = 1;
        while (index < placements.len) : (index += 1) {
            const value = self.buffers.image_order[index];
            var destination = index;
            while (destination > 0) {
                const prior = self.buffers.image_order[destination - 1];
                const prior_value = placements[prior];
                const current_value = placements[value];
                if (prior_value.z < current_value.z or
                    (prior_value.z == current_value.z and prior < value))
                    break;
                self.buffers.image_order[destination] = prior;
                destination -= 1;
            }
            self.buffers.image_order[destination] = value;
        }
    }

    fn imagesFor(self: *Build, above: bool) Content.TakeError!void {
        for (self.buffers.image_order[0..self.input.images.placements.len]) |ordered| {
            const placement = self.input.images.placements[ordered];
            if ((placement.z >= 0) != above) continue;
            try self.append(try self.imageFact(placement));
        }
    }

    fn imageFact(self: *Build, placement: images.ImagePlacement) Content.TakeError!Draw {
        var found: ?ImageEntry = null;
        for (self.input.images.entries) |entry| {
            if (entry.identity.id != placement.image_id) continue;
            if (found != null) return error.InvalidUpdate;
            found = entry;
        }
        const entry = found orelse return error.InvalidUpdate;
        const width = entry.width;
        const height = entry.height;
        const pixel_end = std.math.add(usize, entry.pixel_offset, entry.pixel_count) catch
            return error.ArithmeticOverflow;
        if (width == 0 or height == 0 or pixel_end > self.input.images.pixels.len)
            return error.InvalidUpdate;
        const row_bytes = std.math.mul(usize, width, 4) catch
            return error.ArithmeticOverflow;
        const required = std.math.mul(usize, row_bytes, height) catch
            return error.ArithmeticOverflow;
        if (required != entry.pixel_count) return error.InvalidUpdate;
        const source_x = std.math.cast(u16, placement.source_x) orelse
            return error.InvalidUpdate;
        const source_y = std.math.cast(u16, placement.source_y) orelse
            return error.InvalidUpdate;
        if (source_x >= width or source_y >= height)
            return error.InvalidUpdate;
        const source_width = if (placement.source_width == 0)
            width - source_x
        else
            std.math.cast(u16, placement.source_width) orelse
                return error.InvalidUpdate;
        const source_height = if (placement.source_height == 0)
            height - source_y
        else
            std.math.cast(u16, placement.source_height) orelse
                return error.InvalidUpdate;
        if (source_width == 0 or source_height == 0 or
            @as(u32, source_x) + source_width > width or
            @as(u32, source_y) + source_height > height)
            return error.InvalidUpdate;
        const destination_width = std.math.cast(u16, placement.pixel_width) orelse
            return error.InvalidUpdate;
        const destination_height = std.math.cast(u16, placement.pixel_height) orelse
            return error.InvalidUpdate;
        if (destination_width == 0 or destination_height == 0)
            return error.InvalidUpdate;
        const anchor = try self.cellOrigin(placement.row, placement.col);
        const x = std.math.add(i64, anchor.x, placement.cell_x) catch
            return error.ArithmeticOverflow;
        const y = std.math.add(i64, anchor.y, placement.cell_y) catch
            return error.ArithmeticOverflow;
        return .{ .rgba = .{
            .destination = .{
                .x = try i32Coordinate(x),
                .y = try i32Coordinate(y),
                .width = destination_width,
                .height = destination_height,
            },
            .clip = self.input.geometry.clip,
            .resource = entry.resource,
            .size = .{ .width = width, .height = height },
            .source = .{
                .x = source_x,
                .y = source_y,
                .width = source_width,
                .height = source_height,
            },
        } };
    }

    fn glyphs(self: *Build) Content.TakeError!void {
        var row: usize = 0;
        while (row < self.input.projection.rows) : (row += 1) {
            const cells = self.rowCells(row);
            var cell_index: u16 = 0;
            while (cell_index < cells.len) {
                const row_input = text.RowInput{
                    .cells = cells,
                    .affected_start = 0,
                    .affected_end = @intCast(cells.len - 1),
                    .geometry = self.input.projection.geometry[row],
                    .metrics = self.input.geometry.metrics,
                };
                const run = if (comptime features.native_text)
                    try text.prepareNextRun(self.fonts, row_input, cell_index, self.buffers.text)
                else
                    try text.prepareNextRun(row_input, cell_index);
                if (comptime features.native_text and features.generated_glyphs) {
                    switch (run.glyphs) {
                        .none => {},
                        .generated => |glyph_value| try self.glyph(row, run, glyph_value),
                        .native => |glyph_values| for (glyph_values) |glyph_value|
                            try self.glyph(row, run, glyph_value),
                    }
                } else if (comptime features.native_text) {
                    switch (run.glyphs) {
                        .none => {},
                        .native => |glyph_values| for (glyph_values) |glyph_value|
                            try self.glyph(row, run, glyph_value),
                    }
                } else {
                    switch (run.glyphs) {
                        .none => {},
                        .generated => |glyph_value| try self.glyph(row, run, glyph_value),
                    }
                }
                cell_index = run.end_cell;
            }
        }
    }

    fn glyph(
        self: *Build,
        row: usize,
        run: text.PreparedRun,
        value: text.PositionedGlyph,
    ) Content.TakeError!void {
        const cached = try self.content.glyph(
            self.work,
            self.allocator,
            self.fonts,
            self.producer,
            value.key,
            self.upload_count,
            self.upload_bytes,
        );
        if (cached.width == 0 or cached.height == 0) return;
        const destination = try self.glyphRect(
            row,
            run,
            value,
            cached,
        );
        if (destination.width == 0 or destination.height == 0) return;
        if (run.sizing.width > 1 or run.sizing.height > 1) {
            const clip = intersectRect(destination, self.input.geometry.clip) orelse return;
            const index = self.input_used;
            try self.append(glyphInput(
                destination,
                clip,
                cached,
                color(self.cell(row, value.source_start).foreground),
            ));
            if (self.cursorCovers(row, value.source_start, value.source_end))
                try self.rememberCursorGlyph(index);
            return;
        }
        var col = value.source_start;
        while (col < value.source_end) : (col += 1) {
            const clip = intersectRect(
                try self.cellRect(row, col, 1, 1),
                self.input.geometry.clip,
            ) orelse continue;
            const index = self.input_used;
            try self.append(glyphInput(
                destination,
                clip,
                cached,
                color(self.cell(row, col).foreground),
            ));
            if (self.cursorCovers(row, col, col + 1))
                try self.rememberCursorGlyph(index);
        }
    }

    fn glyphRect(
        self: *Build,
        row: usize,
        run: text.PreparedRun,
        value: text.PositionedGlyph,
        raster: *const GlyphEntry,
    ) Content.TakeError!canvas.Rect {
        const metrics = self.input.geometry.metrics;
        const base_x = std.math.add(
            i64,
            std.math.mul(i64, run.first_cell, metrics.width_px) catch
                return error.ArithmeticOverflow,
            @divFloor(value.x_26_6, 64),
        ) catch
            return error.ArithmeticOverflow;
        const placed_x = std.math.add(i64, base_x, raster.left) catch
            return error.ArithmeticOverflow;
        const placed_y = std.math.sub(
            i64,
            std.math.sub(i64, metrics.baseline_px, raster.top) catch
                return error.ArithmeticOverflow,
            @divTrunc(value.y_26_6, 64),
        ) catch
            return error.ArithmeticOverflow;
        var local = canvas.Rect{
            .x = try i32Coordinate(placed_x),
            .y = try i32Coordinate(placed_y),
            .width = raster.width,
            .height = raster.height,
        };
        local = try textSizingRect(run.first_cell, run.sizing, metrics, local);
        local = try contentRect(row, value.source_start, run.geometry, run.baseline, metrics, local);
        local.x = std.math.add(i32, local.x, self.input.geometry.x) catch
            return error.ArithmeticOverflow;
        local.y = std.math.add(i32, local.y, self.input.geometry.y) catch
            return error.ArithmeticOverflow;
        return local;
    }

    fn glyphInput(
        destination: canvas.Rect,
        clip: canvas.Rect,
        raster: *const GlyphEntry,
        glyph_color: canvas.Color,
    ) Draw {
        return .{ .alpha_mask = .{
            .destination = destination,
            .clip = clip,
            .resource = raster.resource.?,
            .size = .{ .width = raster.width, .height = raster.height },
            .color = glyph_color,
        } };
    }

    fn cursorCovers(self: *const Build, row: usize, start: u16, end: u16) bool {
        const value = self.input.projection.cursor;
        return value.visible and value.shape == .block and value.row == row and
            value.col >= start and value.col < end;
    }

    fn rememberCursorGlyph(self: *Build, input_index: usize) Content.TakeError!void {
        if (self.cursor_used >= self.buffers.cursor_glyphs.len or
            input_index > std.math.maxInt(u16))
            return error.CommandLimit;
        self.buffers.cursor_glyphs[self.cursor_used] = @intCast(input_index);
        self.cursor_used += 1;
    }

    fn decorations(self: *Build) Content.TakeError!void {
        var row: usize = 0;
        while (row < self.input.projection.rows) : (row += 1) {
            var col: usize = 0;
            while (col < self.input.projection.cols) : (col += 1) {
                const cell_value = self.cell(row, col);
                if (cell_value.sizing.x != 0 or cell_value.sizing.y != 0) continue;
                if (cell_value.underline and cell_value.underline_style != .none)
                    try self.underline(row, col, cell_value);
                if (cell_value.strikethrough) {
                    const rect = try self.decorationRect(
                        row,
                        col,
                        cell_value,
                        self.input.geometry.strike_y,
                        self.input.geometry.strike_height,
                    );
                    const clip = intersectRect(
                        try self.clusterRect(
                            row,
                            @intCast(col),
                            self.input.projection.geometry[row],
                            cell_value.sizing,
                        ),
                        self.input.geometry.clip,
                    ) orelse continue;
                    try self.append(.{ .solid = .{
                        .rect = rect,
                        .clip = clip,
                        .color = color(cell_value.foreground),
                    } });
                }
            }
        }
    }

    fn underline(
        self: *Build,
        row: usize,
        col: usize,
        cell_value: Cell,
    ) Content.TakeError!void {
        const line = try self.decorationRect(
            row,
            col,
            cell_value,
            self.input.geometry.underline_y,
            self.input.geometry.underline_height,
        );
        const clip = intersectRect(
            try self.clusterRect(
                row,
                @intCast(col),
                self.input.projection.geometry[row],
                cell_value.sizing,
            ),
            self.input.geometry.clip,
        ) orelse return;
        switch (cell_value.underline_style) {
            .none => {},
            .single => try self.append(.{ .solid = .{
                .rect = line,
                .clip = clip,
                .color = color(cell_value.underline_color),
            } }),
            .double => {
                const upper_offset = self.input.geometry.underline_y -|
                    (self.input.geometry.underline_height +| 1);
                const upper = try self.decorationRect(
                    row,
                    col,
                    cell_value,
                    upper_offset,
                    self.input.geometry.underline_height,
                );
                try self.append(.{ .solid = .{
                    .rect = upper,
                    .clip = clip,
                    .color = color(cell_value.underline_color),
                } });
                try self.append(.{ .solid = .{
                    .rect = line,
                    .clip = clip,
                    .color = color(cell_value.underline_color),
                } });
            },
            .curly, .dotted, .dashed => try self.patternUnderline(line, clip, cell_value),
        }
    }

    fn patternUnderline(
        self: *Build,
        line: canvas.Rect,
        clip: canvas.Rect,
        cell_value: Cell,
    ) Content.TakeError!void {
        const unit = @max(@as(u16, 1), line.height);
        const pattern_height = std.math.add(u16, line.height, unit) catch
            return error.ArithmeticOverflow;
        const count = std.math.mul(usize, line.width, pattern_height) catch
            return error.ArithmeticOverflow;
        if (self.decoration_used > self.buffers.decoration_pixels.len or
            count > self.buffers.decoration_pixels.len - self.decoration_used)
            return error.DecorationLimit;
        const pixels = self.buffers.decoration_pixels[self.decoration_used .. self.decoration_used + count];
        @memset(pixels, 0);
        var y: usize = 0;
        while (y < pattern_height) : (y += 1) {
            var x: usize = 0;
            while (x < line.width) : (x += 1) {
                const rise: ?u16 = switch (cell_value.underline_style) {
                    .curly => if (x % (unit * 2) >= unit) unit else 0,
                    .dotted => if (x % (unit * 2) < unit) 0 else null,
                    .dashed => if (x % (unit * 4) < unit * 3) 0 else null,
                    else => null,
                };
                const on = if (rise) |value|
                    y >= unit - value and y < unit - value + line.height
                else
                    false;
                if (on) pixels[y * line.width + x] = 255;
            }
        }
        self.decoration_used += count;
        const mask = try self.content.mask(
            self.work,
            self.producer,
            cell_value.underline_style,
            line.height,
            @intCast(self.input.geometry.underline_y),
            pixels,
            line.width,
            pattern_height,
            self.upload_count,
            self.upload_bytes,
        );
        const pattern_y = std.math.sub(i32, line.y, unit) catch
            return error.ArithmeticOverflow;
        try self.append(.{ .alpha_mask = .{
            .destination = .{
                .x = line.x,
                .y = pattern_y,
                .width = line.width,
                .height = pattern_height,
            },
            .clip = clip,
            .resource = mask.resource,
            .size = .{ .width = line.width, .height = pattern_height },
            .color = color(cell_value.underline_color),
        } });
    }

    fn decorationRect(
        self: *const Build,
        row: usize,
        col: usize,
        cell_value: Cell,
        offset: u16,
        height: u16,
    ) Content.TakeError!canvas.Rect {
        if (height == 0 or offset >= self.input.geometry.metrics.height_px or
            @as(u32, offset) + height > self.input.geometry.metrics.height_px)
            return error.InvalidGeometry;
        var rect = canvas.Rect{
            .x = try i32Coordinate(
                std.math.mul(i64, @as(i64, @intCast(col)), self.input.geometry.metrics.width_px) catch
                    return error.ArithmeticOverflow,
            ),
            .y = offset,
            .width = self.input.geometry.metrics.width_px,
            .height = height,
        };
        rect = try textSizingRect(
            @intCast(col),
            cell_value.sizing,
            self.input.geometry.metrics,
            rect,
        );
        rect = try contentRect(
            row,
            @intCast(col),
            self.input.projection.geometry[row],
            cell_value.baseline,
            self.input.geometry.metrics,
            rect,
        );
        rect.x = std.math.add(i32, rect.x, self.input.geometry.x) catch
            return error.ArithmeticOverflow;
        rect.y = std.math.add(i32, rect.y, self.input.geometry.y) catch
            return error.ArithmeticOverflow;
        return rect;
    }

    fn cursor(self: *Build) Content.TakeError!void {
        const cursor_value = self.input.projection.cursor;
        if (!cursor_value.visible or cursor_value.shape == .none) return;
        var rect = try self.cellRect(cursor_value.row, cursor_value.col, 1, 1);
        switch (cursor_value.shape) {
            .block => {},
            .underline => {
                rect.y = std.math.add(i32, rect.y, rect.height - 1) catch
                    return error.ArithmeticOverflow;
                rect.height = 1;
            },
            .bar => rect.width = 1,
            .none => return,
        }
        try self.append(.{ .solid = .{
            .rect = rect,
            .clip = self.input.geometry.clip,
            .color = color(cursor_value.color),
        } });
        if (cursor_value.shape != .block) return;
        const text_clip = intersectRect(rect, self.input.geometry.clip) orelse return;
        for (self.buffers.cursor_glyphs[0..self.cursor_used]) |index| {
            var fact = self.buffers.inputs[index];
            fact.alpha_mask.color = color(cursor_value.text_color);
            fact.alpha_mask.clip = text_clip;
            try self.append(fact);
        }
    }

    fn append(self: *Build, input: Draw) Content.TakeError!void {
        if (self.input_used >= self.buffers.inputs.len)
            return error.CommandLimit;
        self.buffers.inputs[self.input_used] = input;
        self.input_used += 1;
    }

    fn cell(self: *const Build, row: usize, col: usize) Cell {
        return self.input.projection.cells[row * self.input.projection.cols + col];
    }

    fn rowCells(self: *const Build, row: usize) []const Cell {
        const start = row * self.input.projection.cols;
        return self.input.projection.cells[start .. start + self.input.projection.cols];
    }

    fn cellOrigin(self: *const Build, row: usize, col: usize) Content.TakeError!struct { x: i64, y: i64 } {
        const scale = lineScale(self.input.projection.geometry[row]);
        const x_offset = std.math.mul(
            i64,
            @as(i64, @intCast(col)),
            @as(i64, self.input.geometry.metrics.width_px) * scale.x,
        ) catch
            return error.ArithmeticOverflow;
        const y_offset = std.math.mul(i64, @as(i64, @intCast(row)), self.input.geometry.metrics.height_px) catch
            return error.ArithmeticOverflow;
        return .{
            .x = std.math.add(i64, self.input.geometry.x, x_offset) catch
                return error.ArithmeticOverflow,
            .y = std.math.add(i64, self.input.geometry.y, y_offset) catch
                return error.ArithmeticOverflow,
        };
    }

    fn cellRect(
        self: *const Build,
        row: usize,
        col: usize,
        width: u16,
        height: u16,
    ) Content.TakeError!canvas.Rect {
        const origin = try self.cellOrigin(row, col);
        const scale = lineScale(self.input.projection.geometry[row]);
        return .{
            .x = try i32Coordinate(origin.x),
            .y = try i32Coordinate(origin.y),
            .width = std.math.mul(
                u16,
                self.input.geometry.metrics.width_px,
                std.math.mul(u16, width, scale.x) catch return error.ArithmeticOverflow,
            ) catch
                return error.ArithmeticOverflow,
            .height = std.math.mul(u16, self.input.geometry.metrics.height_px, height) catch
                return error.ArithmeticOverflow,
        };
    }

    fn clusterRect(
        self: *const Build,
        row: usize,
        col: usize,
        geometry: LineGeometry,
        sizing: TextSizing,
    ) Content.TakeError!canvas.Rect {
        var rect = try self.cellRect(row, col, 1, 1);
        if (geometry != self.input.projection.geometry[row])
            return error.InvalidProjection;
        rect.width = std.math.mul(u16, rect.width, sizing.width) catch
            return error.ArithmeticOverflow;
        rect.height = std.math.mul(u16, rect.height, sizing.height) catch
            return error.ArithmeticOverflow;
        return rect;
    }
};

fn validateLimits(limits: Content.Limits) Content.InitError!void {
    const glyph_mask_count = std.math.add(usize, limits.glyphs, limits.masks) catch
        return error.InvalidLimits;
    const required_removals = std.math.add(usize, glyph_mask_count, limits.images) catch
        return error.InvalidLimits;
    if (limits.cells == 0 or limits.rows == 0 or limits.images == 0 or
        limits.placements == 0 or limits.image_bytes == 0 or
        limits.glyphs == 0 or limits.masks == 0 or limits.commands == 0 or
        limits.resources_per_update == 0 or limits.upload_bytes == 0 or
        limits.raster_bytes == 0 or
        limits.decoration_bytes == 0 or
        limits.resources_per_update < required_removals or
        limits.rows > std.math.maxInt(u16) or
        limits.placements > std.math.maxInt(u16) or
        limits.commands > std.math.maxInt(u16))
        return error.InvalidLimits;
}

fn issueResource(
    next: *u64,
    generation: u64,
) error{ InvalidUpdate, IdentityExhausted }!canvas.ResourceRef {
    canvas_validation.localIdentity(next.*, generation) catch return error.InvalidUpdate;
    const id = next.*;
    if (id > canvas.ResourceId.max_identity) return error.IdentityExhausted;
    next.* += 1;
    return .{
        .resource = canvas.ResourceId.local(id) catch return error.IdentityExhausted,
        .generation = @fromBackingInt(@intCast(generation)),
    };
}

const ProducedResource = struct {
    resource: canvas.ResourceRef,
    declaration_required: bool,
};

fn produceGlyphResource(
    next: *u64,
    producer: Content.FontProducer,
    key: text.GlyphKey,
    width: u16,
    height: u16,
    pixels: []const u8,
) Content.TakeError!ProducedResource {
    if (comptime !features.native_text) return .{
        .resource = try issueResource(next, 1),
        .declaration_required = true,
    };
    return switch (producer) {
        .local => .{
            .resource = try issueResource(next, 1),
            .declaration_required = true,
        },
        .shared => |shared| blk: {
            const interned = try shared.internGlyph(
                key,
                .alpha8,
                .{ .width = width, .height = height },
                width,
                pixels,
            );
            break :blk .{
                .resource = interned.resource,
                .declaration_required = interned.declaration_required,
            };
        },
    };
}

fn produceDecorationResource(
    next: *u64,
    producer: Content.FontProducer,
    style: UnderlineStyle,
    width: u16,
    height: u16,
    thickness: u16,
    position: i16,
    pixels: []const u8,
) Content.TakeError!ProducedResource {
    if (comptime !features.native_text) return .{
        .resource = try issueResource(next, 1),
        .declaration_required = true,
    };
    return switch (producer) {
        .local => .{
            .resource = try issueResource(next, 1),
            .declaration_required = true,
        },
        .shared => |shared| blk: {
            const interned = try shared.internDecoration(
                @backingInt(style),
                width,
                height,
                thickness,
                position,
                pixels,
            );
            break :blk .{
                .resource = interned.resource,
                .declaration_required = interned.declaration_required,
            };
        },
    };
}

fn sharedDeclarationRequired(
    producer: Content.FontProducer,
    resource: canvas.ResourceRef,
) Content.TakeError!bool {
    if (!resource.resource.isShared()) return false;
    if (comptime !features.native_text) return error.InvalidUpdate;
    return switch (producer) {
        .local => error.InvalidUpdate,
        .shared => |shared| try shared.declarationRequired(resource),
    };
}

fn releaseCommittedShared(
    producer: Content.FontProducer,
    resource: canvas.ResourceRef,
) void {
    if (comptime !features.native_text)
        @panic("non-native Content retained a shared font resource");
    switch (producer) {
        .local => @panic("local Content retained a shared font resource"),
        .shared => |shared| shared.releaseCommitted(resource),
    }
}

fn alreadyUploaded(
    work: *Content.Work,
    count: usize,
    resource: canvas.ResourceRef,
) bool {
    for (work.uploads[0..count]) |upload|
        if (std.meta.eql(upload.resource, resource)) return true;
    return false;
}

fn redeclareGlyphIfRequired(
    work: *Content.Work,
    allocator: std.mem.Allocator,
    fonts: if (features.native_text) *text.FontMap else void,
    producer: Content.FontProducer,
    key: text.GlyphKey,
    retained: *const GlyphEntry,
    resource: canvas.ResourceRef,
    upload_count: *usize,
    upload_bytes: *usize,
) Content.TakeError!void {
    if (!try sharedDeclarationRequired(producer, resource) or
        alreadyUploaded(work, upload_count.*, resource))
        return;
    var raster = if (comptime features.native_text)
        try text.rasterizeGlyph(allocator, fonts, key)
    else
        try text.rasterizeGlyph(allocator, key);
    defer raster.deinit();
    if (raster.width != retained.width or raster.height != retained.height or
        raster.left != retained.left or raster.top != retained.top)
        return error.InvalidUpdate;
    try Content.appendUpload(
        work,
        upload_count,
        upload_bytes,
        resource,
        .alpha8,
        raster.width,
        raster.height,
        raster.pixels,
    );
}

fn redeclareMaskIfRequired(
    work: *Content.Work,
    producer: Content.FontProducer,
    retained: *const MaskEntry,
    pixels: []const u8,
    upload_count: *usize,
    upload_bytes: *usize,
) Content.TakeError!void {
    if (!try sharedDeclarationRequired(producer, retained.resource) or
        alreadyUploaded(work, upload_count.*, retained.resource))
        return;
    try Content.appendUpload(
        work,
        upload_count,
        upload_bytes,
        retained.resource,
        .alpha8,
        retained.width,
        retained.height,
        pixels,
    );
}

fn drawInput(draw: Draw) canvas.Input {
    return switch (draw) {
        .solid => |value| .{ .solid = .{
            .rect = value.rect,
            .clip = value.clip,
            .color = value.color,
        } },
        .alpha_mask => |value| .{ .alpha_mask = .{
            .destination = value.destination,
            .clip = value.clip,
            .resource = .{
                .resource = value.resource,
                .format = .alpha8,
                .size = value.size,
            },
            .color = value.color,
        } },
        .rgba => |value| .{ .rgba = .{
            .destination = value.destination,
            .clip = value.clip,
            .resource = .{
                .resource = value.resource,
                .format = .rgba8,
                .size = value.size,
                .source = value.source,
            },
        } },
    };
}

fn validatePane(input: RenderInput) Content.TakeError!void {
    if (input.projection.rows == 0 or input.projection.cols == 0 or
        input.geometry.metrics.width_px == 0 or input.geometry.metrics.height_px == 0 or
        input.geometry.metrics.baseline_px >= input.geometry.metrics.height_px or
        input.geometry.underline_height == 0 or input.geometry.strike_height == 0 or
        input.geometry.underline_y >= input.geometry.metrics.height_px or
        input.geometry.strike_y >= input.geometry.metrics.height_px)
        return error.InvalidGeometry;
    const cell_count = std.math.mul(
        usize,
        input.projection.rows,
        input.projection.cols,
    ) catch return error.ArithmeticOverflow;
    if (input.projection.cells.len != cell_count or
        input.projection.geometry.len != input.projection.rows or
        (input.projection.cursor.visible and
            (input.projection.cursor.row >= input.projection.rows or
                input.projection.cursor.col >= input.projection.cols)))
        return error.InvalidProjection;
}

const Scale = struct { x: u16, y: u16, y_offset_rows: i8 };

fn lineScale(geometry: LineGeometry) Scale {
    return switch (geometry) {
        .single_width => .{ .x = 1, .y = 1, .y_offset_rows = 0 },
        .double_width => .{ .x = 2, .y = 1, .y_offset_rows = 0 },
        .double_height_top => .{ .x = 2, .y = 2, .y_offset_rows = 0 },
        .double_height_bottom => .{ .x = 2, .y = 2, .y_offset_rows = -1 },
    };
}

fn textSizingRect(
    anchor_col: u16,
    sizing: TextSizing,
    metrics: text.CellMetrics,
    base: canvas.Rect,
) Content.TakeError!canvas.Rect {
    if (sizing.width == 0 or sizing.height == 0 or sizing.x != 0 or sizing.y != 0)
        return error.InvalidProjection;
    const fractional = sizing.subscale_n > 0 and sizing.subscale_d > 0 and
        sizing.subscale_n < sizing.subscale_d;
    const numerator: u64 = @as(u64, sizing.height) *
        (if (fractional) sizing.subscale_n else 1);
    const denominator: u64 = if (fractional) sizing.subscale_d else 1;
    const block_width = @as(u64, sizing.width) * metrics.width_px;
    const block_height = @as(u64, sizing.height) * metrics.height_px;
    const area_width = block_width * numerator /
        (@as(u64, sizing.height) * denominator);
    const area_height = block_height * numerator /
        (@as(u64, sizing.height) * denominator);
    const x_offset = switch (sizing.horizontal_align) {
        1 => block_width - area_width,
        2 => (block_width - area_width) / 2,
        else => 0,
    };
    const y_offset = switch (sizing.vertical_align) {
        1 => block_height - area_height,
        2 => (block_height - area_height) / 2,
        else => 0,
    };
    const anchor_x = @as(i64, anchor_col) * metrics.width_px;
    const x = std.math.add(
        i64,
        anchor_x + @divFloor((@as(i64, base.x) - anchor_x) * @as(i64, @intCast(numerator)), @as(i64, @intCast(denominator))),
        @intCast(x_offset),
    ) catch return error.ArithmeticOverflow;
    const y = std.math.add(
        i64,
        @divFloor(@as(i64, base.y) * @as(i64, @intCast(numerator)), @as(i64, @intCast(denominator))),
        @intCast(y_offset),
    ) catch return error.ArithmeticOverflow;
    const width = @as(u64, base.width) * numerator / denominator;
    const height = @as(u64, base.height) * numerator / denominator;
    return .{
        .x = try i32Coordinate(x),
        .y = try i32Coordinate(y),
        .width = std.math.cast(u16, width) orelse return error.ArithmeticOverflow,
        .height = std.math.cast(u16, height) orelse return error.ArithmeticOverflow,
    };
}

fn contentRect(
    row: usize,
    anchor_col: u16,
    geometry: LineGeometry,
    baseline: CellBaseline,
    metrics: text.CellMetrics,
    base: canvas.Rect,
) Content.TakeError!canvas.Rect {
    const anchor_x = @as(i64, anchor_col) * metrics.width_px;
    var x: i64 = base.x;
    var y: i64 = base.y;
    var width: u64 = base.width;
    var height: u64 = base.height;
    if (baseline != .normal) {
        x = anchor_x + @divFloor(x - anchor_x, 2);
        width = (width + 1) / 2;
        height = (height + 1) / 2;
        y = @divFloor(y, 2);
        if (baseline == .lowered)
            y += metrics.height_px - (metrics.height_px + 1) / 2;
    }
    const scale = lineScale(geometry);
    x = std.math.mul(i64, x, scale.x) catch return error.ArithmeticOverflow;
    const row_y = std.math.mul(i64, @as(i64, @intCast(row)), metrics.height_px) catch
        return error.ArithmeticOverflow;
    const offset_y = std.math.mul(i64, scale.y_offset_rows, metrics.height_px) catch
        return error.ArithmeticOverflow;
    y = std.math.add(
        i64,
        std.math.add(i64, row_y, offset_y) catch return error.ArithmeticOverflow,
        std.math.mul(i64, y, scale.y) catch return error.ArithmeticOverflow,
    ) catch return error.ArithmeticOverflow;
    width = std.math.mul(u64, width, scale.x) catch return error.ArithmeticOverflow;
    height = std.math.mul(u64, height, scale.y) catch return error.ArithmeticOverflow;
    return .{
        .x = try i32Coordinate(x),
        .y = try i32Coordinate(y),
        .width = std.math.cast(u16, width) orelse return error.ArithmeticOverflow,
        .height = std.math.cast(u16, height) orelse return error.ArithmeticOverflow,
    };
}

fn intersectRect(a: canvas.Rect, b: canvas.Rect) ?canvas.Rect {
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

fn color(value: Rgb) canvas.Color {
    return .{ .r = value.r, .g = value.g, .b = value.b, .a = 255 };
}

fn i32Coordinate(value: i64) Content.TakeError!i32 {
    if (value < std.math.minInt(i32) or value > std.math.maxInt(i32))
        return error.ArithmeticOverflow;
    return @intCast(value);
}

test "local resource identity exhaustion rejects before counter mutation" {
    var next = canvas.ResourceId.max_identity + 1;
    try std.testing.expectError(error.IdentityExhausted, issueResource(&next, 1));
    try std.testing.expectEqual(canvas.ResourceId.max_identity + 1, next);
    next = canvas.ResourceId.max_identity;
    const last = try issueResource(&next, 1);
    try std.testing.expectEqual(
        canvas.ResourceId.max_identity,
        try last.resource.identity(),
    );
    try std.testing.expectEqual(canvas.ResourceId.max_identity + 1, next);
    next = 1;
    const first = try issueResource(&next, 1);
    try std.testing.expectEqual(@as(u64, 1), @backingInt(first.resource));
    try std.testing.expectEqual(@as(u64, 2), next);
}

test "terminal image identity boundary is transactional and remains local" {
    if (comptime features.native_text) return error.SkipZigTest;

    const limits = Content.Limits{
        .cells = 1,
        .rows = 1,
        .images = 3,
        .placements = 1,
        .image_bytes = 12,
        .glyphs = 1,
        .masks = 1,
        .commands = 4,
        .resources_per_update = 5,
        .upload_bytes = 16,
        .raster_bytes = 16,
        .decoration_bytes = 8,
    };
    var content = try Content.init(std.testing.allocator, limits, {});
    defer content.deinit();
    @memset(std.mem.asBytes(content.images_a), 0);
    @memset(std.mem.asBytes(content.images_b), 0);
    @memset(content.image_pixels_a, 0);
    @memset(content.image_pixels_b, 0);
    @memset(std.mem.asBytes(content.placements_a), 0);
    @memset(std.mem.asBytes(content.placements_b), 0);
    @memset(std.mem.asBytes(content.pending_removals), 0);

    const cell = std.mem.zeroes(Cell);
    const baseline = ProjectionBaseline{
        .rows = 1,
        .cols = 1,
        .cursor = std.mem.zeroes(Cursor),
        .cells = &.{cell},
        .geometry = &.{.single_width},
    };
    const initial_pixels = [_]u8{ 1, 2, 3, 4 };
    const initial_upload = images.ImageUpload{
        .identity = .{ .id = 7, .generation = 1 },
        .width = 1,
        .height = 1,
        .pixel_offset = 0,
        .pixel_count = 4,
    };
    try content.recover(baseline, .{
        .generation = 1,
        .content_generation = 1,
        .pixels = &initial_pixels,
        .uploads = &.{initial_upload},
        .removals = &.{},
        .placements = &.{},
    });

    const two_pixels = [_]u8{ 5, 6, 7, 8, 9, 10, 11, 12 };
    const two_uploads = [_]images.ImageUpload{
        .{
            .identity = .{ .id = 8, .generation = 1 },
            .width = 1,
            .height = 1,
            .pixel_offset = 0,
            .pixel_count = 4,
        },
        .{
            .identity = .{ .id = 9, .generation = 1 },
            .width = 1,
            .height = 1,
            .pixel_offset = 4,
            .pixel_count = 4,
        },
    };
    content.next_resource_id = canvas.ResourceId.max_identity;
    const images_a_before = try std.testing.allocator.dupe(
        u8,
        std.mem.asBytes(content.images_a),
    );
    defer std.testing.allocator.free(images_a_before);
    const images_b_before = try std.testing.allocator.dupe(
        u8,
        std.mem.asBytes(content.images_b),
    );
    defer std.testing.allocator.free(images_b_before);
    const pixels_a_before = try std.testing.allocator.dupe(u8, content.image_pixels_a);
    defer std.testing.allocator.free(pixels_a_before);
    const pixels_b_before = try std.testing.allocator.dupe(u8, content.image_pixels_b);
    defer std.testing.allocator.free(pixels_b_before);
    const removals_before = try std.testing.allocator.dupe(
        u8,
        std.mem.asBytes(content.pending_removals),
    );
    defer std.testing.allocator.free(removals_before);
    const active_before = content.images_a_active;
    const count_before = content.image_count;
    const pixel_count_before = content.image_pixel_count;
    const removal_count_before = content.pending_removal_count;
    const image_revision_before = content.image_revision;
    const content_revision_before = content.image_content_revision;
    const producer_revision_before = content.producer_revision;

    try std.testing.expectError(error.IdentityExhausted, content.recover(baseline, .{
        .generation = 2,
        .content_generation = 2,
        .pixels = &two_pixels,
        .uploads = &two_uploads,
        .removals = &.{},
        .placements = &.{},
    }));
    try std.testing.expectEqualSlices(u8, images_a_before, std.mem.asBytes(content.images_a));
    try std.testing.expectEqualSlices(u8, images_b_before, std.mem.asBytes(content.images_b));
    try std.testing.expectEqualSlices(u8, pixels_a_before, content.image_pixels_a);
    try std.testing.expectEqualSlices(u8, pixels_b_before, content.image_pixels_b);
    try std.testing.expectEqualSlices(
        u8,
        removals_before,
        std.mem.asBytes(content.pending_removals),
    );
    try std.testing.expectEqual(active_before, content.images_a_active);
    try std.testing.expectEqual(count_before, content.image_count);
    try std.testing.expectEqual(pixel_count_before, content.image_pixel_count);
    try std.testing.expectEqual(removal_count_before, content.pending_removal_count);
    try std.testing.expectEqual(image_revision_before, content.image_revision);
    try std.testing.expectEqual(content_revision_before, content.image_content_revision);
    try std.testing.expectEqual(producer_revision_before, content.producer_revision);
    try std.testing.expectEqual(canvas.ResourceId.max_identity, content.next_resource_id);

    content.next_resource_id = canvas.ResourceId.max_identity + 1;
    try std.testing.expectError(error.IdentityExhausted, content.recover(baseline, .{
        .generation = 2,
        .content_generation = 2,
        .pixels = two_pixels[0..4],
        .uploads = two_uploads[0..1],
        .removals = &.{},
        .placements = &.{},
    }));
    try std.testing.expectEqualSlices(u8, images_a_before, std.mem.asBytes(content.images_a));
    try std.testing.expectEqualSlices(u8, images_b_before, std.mem.asBytes(content.images_b));
    try std.testing.expectEqualSlices(u8, pixels_a_before, content.image_pixels_a);
    try std.testing.expectEqualSlices(u8, pixels_b_before, content.image_pixels_b);
    try std.testing.expectEqualSlices(
        u8,
        removals_before,
        std.mem.asBytes(content.pending_removals),
    );
    try std.testing.expectEqual(active_before, content.images_a_active);
    try std.testing.expectEqual(count_before, content.image_count);
    try std.testing.expectEqual(pixel_count_before, content.image_pixel_count);
    try std.testing.expectEqual(removal_count_before, content.pending_removal_count);
    try std.testing.expectEqual(image_revision_before, content.image_revision);
    try std.testing.expectEqual(content_revision_before, content.image_content_revision);
    try std.testing.expectEqual(producer_revision_before, content.producer_revision);
    try std.testing.expectEqual(
        canvas.ResourceId.max_identity + 1,
        content.next_resource_id,
    );

    const replacement_pixels = [_]u8{ 13, 14, 15, 16 };
    const replacement = images.ImageUpload{
        .identity = .{ .id = 7, .generation = 2 },
        .width = 1,
        .height = 1,
        .pixel_offset = 0,
        .pixel_count = 4,
    };
    try content.recover(baseline, .{
        .generation = 2,
        .content_generation = 2,
        .pixels = &replacement_pixels,
        .uploads = &.{replacement},
        .removals = &.{},
        .placements = &.{},
    });
    try std.testing.expectEqual(
        canvas.ResourceId.max_identity + 1,
        content.next_resource_id,
    );
    try std.testing.expectEqual(
        @as(u64, 1),
        try content.activeImages()[0].resource.resource.identity(),
    );

    content.next_resource_id = canvas.ResourceId.max_identity;
    try content.recover(baseline, .{
        .generation = 3,
        .content_generation = 3,
        .pixels = two_pixels[0..4],
        .uploads = two_uploads[0..1],
        .removals = &.{},
        .placements = &.{},
    });
    var found_last = false;
    for (content.activeImages()[0..content.image_count]) |entry| {
        try std.testing.expect(!entry.resource.resource.isShared());
        if (entry.identity.id == 8) {
            found_last = true;
            try std.testing.expectEqual(
                canvas.ResourceId.max_identity,
                try entry.resource.resource.identity(),
            );
        }
    }
    try std.testing.expect(found_last);
    try std.testing.expectEqual(
        canvas.ResourceId.max_identity + 1,
        content.next_resource_id,
    );
}
