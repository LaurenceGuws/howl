//! Private bounded optional rendered-VT state; canonical input never waits for output.
//! Direct canonical physical rows -> retained row-local final commands.
//! Supports bounded live 1..192 by 1..512 active bank, bounded native styled/Unicode rows,
//! block/bar/underline/hidden cursor, whole upward scroll. No generic Source adapter.
//! One optional held snapshot; release before owner destruction. Working atlas
//! is separate from bounded immutable published alpha and color resource buffers.
//! Admitted operations: feed, resize, selectHistoryOffset, consumeReplyBytes,
//! resetAtlas/resetShapes, replaceWorkingBorrowed, flush and hold/release. Direct VT mutation is excluded.
//! Feed uses whole-slice VT.feed, not app service-boundary consumed-tail handling.
const std = @import("std");
const VT = @import("howl_vt").Terminal;
const text = @import("howl_text");
const cache = @import("glyph_cache");
const frame = @import("frame");
const support = @import("text_support");
const graphics_output = @import("graphics.zig");

/// Maximum supported output row count.
pub const rows = @import("limits").maximum_rows;
/// Maximum supported output column count.
pub const cols = @import("limits").maximum_columns;
const private_glyph_capacity = cols * 2;

fn resolveCommandLimit(config: Config, shared: ?*support.PresentationStore, cell_width: u16) error{InvalidCommandLimit}!usize {
    // Individual-cell runs fit the lane's scratch, including cached runs.
    // A contextual run uses a separate full-row lane of at most 2 * cols.
    const glyph_capacity = if (shared) |store|
        support.storeConfig(support.borrowStore(store)).shaped_capacity
    else
        private_glyph_capacity;
    // Scaled dotted underlines emit at most ceil(cell_width / 2) solids
    // per occupied column; lazy storage still grows only when needed.
    const dots = (@as(usize, cell_width) + 1) / 2;
    const decorations = std.math.add(usize, 4, dots) catch return error.InvalidCommandLimit;
    const per_cell = std.math.add(usize, glyph_capacity, decorations) catch return error.InvalidCommandLimit;
    const cells = std.math.mul(usize, cols, per_cell) catch return error.InvalidCommandLimit;
    const maximum = std.math.add(usize, cells, private_glyph_capacity) catch return error.InvalidCommandLimit;
    if (config.command_limit == 0) return maximum;
    if (config.command_limit > maximum) return error.InvalidCommandLimit;
    return config.command_limit;
}
/// ASCII warmup fixture used only by explicit proof configuration.
pub const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
/// Proof-only logical work counters; absent from ordinary state storage.
pub const Stats = struct {
    rows_rebuilt: u64 = 0,
    command_bytes_written: u64 = 0,
    full_ascii_rows: u64 = 0,
    command_bytes_copied: u64 = 0,
    identity_rows_checked: u64 = 0,
    descriptor_bytes_written: u64 = 0,
    resource_pixel_copies: u64 = 0,
    resource_pixel_bytes_copied: u64 = 0,
    broad_rebind_rows: u64 = 0,
    resource_rebind_bytes: u64 = 0,
    resource_allocation_attempts: u64 = 0,
    command_allocation_attempts: u64 = 0,
};
const Block = struct {
    commands: []frame.Command = &.{},
    background_end: usize = 0,
    decoration_end: usize = 0,
    count: usize = 0,
};
/// Conservative horizontal pixel band for one exact output transition.
/// A null band means full-row repair; an empty band needs no repaint.
pub const RowDamage = struct {
    first: u16 = 0,
    after: u16 = 0,

    fn include(self: *RowDamage, command: frame.Command, width: u16) void {
        const Footprint = struct { destination: frame.Rect, clip: ?frame.Rect };
        const footprint: Footprint = switch (command) {
            .solid => |value| .{ .destination = value.rect, .clip = null },
            .alpha_mask => |value| .{ .destination = value.destination, .clip = value.clip },
            .rgba => |value| .{ .destination = value.destination, .clip = value.clip },
        };
        var first: i64 = @max(0, footprint.destination.x);
        var after: i64 = @min(@as(i64, width), @as(i64, footprint.destination.x) + footprint.destination.width);
        if (footprint.clip) |clip| {
            first = @max(first, clip.x);
            after = @min(after, @as(i64, clip.x) + clip.width);
        }
        if (first >= after) return;
        const start: u16 = @intCast(first);
        const end: u16 = @intCast(after);
        if (self.first == self.after) {
            self.* = .{ .first = start, .after = end };
        } else {
            self.first = @min(self.first, start);
            self.after = @max(self.after, end);
        }
    }
};

fn changedPhase(before: []const frame.Command, after: []const frame.Command, width: u16, damage: *RowDamage) void {
    const shorter = @min(before.len, after.len);
    var prefix: usize = 0;
    while (prefix < shorter and std.meta.eql(before[prefix], after[prefix])) : (prefix += 1) {}
    var suffix: usize = 0;
    while (suffix < shorter - prefix and std.meta.eql(before[before.len - 1 - suffix], after[after.len - 1 - suffix])) : (suffix += 1) {}
    for (before[prefix .. before.len - suffix]) |command| damage.include(command, width);
    for (after[prefix .. after.len - suffix]) |command| damage.include(command, width);
}

fn changedRow(before: *const Block, after: *const Block, width: u16) RowDamage {
    const old = [_][]const frame.Command{
        before.commands[0..before.background_end],
        before.commands[before.background_end..before.decoration_end],
        before.commands[before.decoration_end..before.count],
    };
    const next = [_][]const frame.Command{
        after.commands[0..after.background_end],
        after.commands[after.background_end..after.decoration_end],
        after.commands[after.decoration_end..after.count],
    };
    var damage: RowDamage = .{};
    for (old, next) |previous, current| changedPhase(previous, current, width, &damage);
    return damage;
}
const Slot = struct {
    blocks: [3]Block = @splat(.{}),
    current: u2 = 0,
    held: ?u2 = null,
    generation: u64 = 0,
    damage: ?RowDamage = null,
};
/// Borrowed immutable output pinned until the matching release.
pub const Snapshot = struct {
    row_generations: [rows]u64 = @splat(0),
    /// Only usable when the consumer retained the immediately previous content revision.
    row_damage: [rows]?RowDamage = @splat(null),
    visual_context: u64 = 0,
    row_origin: u16 = 0,
    history_offset: u32 = 0,
    history_count: u32 = 0,
    history_row_base: u32 = 0,
    terminal_revision: u64 = 0,
    content_revision: u64 = 0,
    cursor_blink: bool = false,
    /// Immutable text-ink phase and exact rows that contain blinking output.
    /// The clock never changes text content, row generations or image pixels.
    text_blink_visible: bool = true,
    text_blink_rows: [rows]bool = @splat(false),
    cursor_movement: u64 = 0,
    alternate: bool = false,
    rows: u16 = 24,
    cols: u16 = 80,
    surface: frame.Size = .{ .width = 0, .height = 0 },
    glyphs: [rows][]const frame.Command,
    backgrounds: [rows][]const frame.Command,
    decorations: [rows][]const frame.Command,
    background: frame.Command,
    cursor: ?frame.Command,
    cursor_shape: ?VT.CursorShape,
    /// Full cell bounds, independent of the painted bar or underline shape.
    cursor_cell: ?frame.Rect = null,
    cursor_text_color: ?frame.Color,
    /// Accepted canonical selection colors, copied with this immutable
    /// frame. The graphical host owns how the selected cells are painted.
    selection_background: ?VT.Rgb = null,
    selection_foreground: ?VT.Rgb = null,
    /// Color-matching transparency metadata copied at frame publication.
    /// A host decides whether its output surface can actually use alpha.
    transparent_background: [8]?VT.TransparentBackgroundColor = @splat(null),
    cursor_ink: []const frame.Command,
    cell_width: u16,
    cell_height: u16,
    atlas_pixels: []const u8,
    atlas_width: u16,
    atlas_height: u16,
    resource: frame.ResourceRef,
    color_atlas_pixels: []const u8 = &.{},
    color_atlas_width: u16 = 0,
    color_atlas_height: u16 = 0,
    color_resource: ?frame.ResourceRef = null,
    graphics: graphics_output.View = .{},
    format: frame.ResourceFormat = .alpha8,
};
/// Private bounded cache and output configuration shared by both specializations.
pub const Config = struct {
    history_capacity: u16 = 0,
    cursor_stroke_pixels: u8 = 2,
    warm: bool = false,
    faces: ?cache.FontFaces = null,
    box_drawing: text.generated.BoxDrawingConfig = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
    atlas: cache.AtlasConfig = .{ .width = 64, .height = 16, .entry_capacity = 16, .growth = .{ .entry_limit = 256, .alpha_height_limit = 512, .color_height_limit = 16 } },
    raster_bytes: usize = 512 * 512,
    /// Zero derives a ceiling from shaping capacities and font width; storage grows on demand.
    command_limit: usize = 0,
};
const Resource = struct {
    pixels: []u8 = &.{},
    len: usize = 0,
    width: u16 = 0,
    height: u16 = 0,
    generation: u64 = 0,
    atlas_epoch: u64 = 0,
    entries: usize = 0,
};
// Private mutable working state only. Every FontSet in faces is borrowed.
const Working = struct { atlas: *cache.Atlas, shapes: *cache.ShapeCache, raster: []u8, metrics: text.Metrics, shared: ?*support.PresentationStore = null };
/// Shared work bounds belong to the retained store, never to this local output policy.
pub const SharedConfig = struct {
    history_capacity: u16 = 0,
    cursor_stroke_pixels: u8 = 2,
    box_drawing: text.generated.BoxDrawingConfig = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
    atlas: cache.AtlasConfig = .{ .width = 64, .height = 16, .entry_capacity = 16, .growth = .{ .entry_limit = 256, .alpha_height_limit = 512, .color_height_limit = 16 } },
    /// Zero derives a ceiling from shaping capacities and font width; storage grows on demand.
    command_limit: usize = 0,
    fn internal(self: SharedConfig) Config {
        return .{ .history_capacity = self.history_capacity, .cursor_stroke_pixels = self.cursor_stroke_pixels, .box_drawing = self.box_drawing, .atlas = self.atlas, .command_limit = self.command_limit };
    }
};
fn prepareShared(allocator: std.mem.Allocator, store: *support.PresentationStore, config: Config) !Working {
    if (config.cursor_stroke_pixels == 0 or config.cursor_stroke_pixels > 16) return error.InvalidCursorStroke;
    try support.retain(store);
    errdefer support.release(store);
    support.claim(store);
    defer support.unclaim(store);
    const borrowed = support.borrowStore(store);
    const metrics = support.storeMetrics(borrowed);
    if (metrics.advance_width == 0 or metrics.line_height == 0) return error.UnsupportedMetrics;
    // zig-audit: acknowledge discard
    // reason: Overflow is rejected before the canonical pixel size or accepted output can change.
    _ = try std.math.mul(u16, 80, metrics.advance_width);
    // zig-audit: acknowledge discard
    // reason: Overflow is rejected before the canonical pixel size or accepted output can change.
    _ = try std.math.mul(u16, 24, metrics.line_height);
    const atlas = try support.initAtlasFromStore(allocator, borrowed, config.box_drawing, config.atlas);
    const work = support.work(borrowed);
    return .{ .atlas = atlas, .shapes = work.shape_cache, .raster = work.raster, .metrics = metrics, .shared = store };
}
fn destroyWorking(allocator: std.mem.Allocator, atlas: *cache.Atlas, shapes: *cache.ShapeCache, raster: []u8, shared: ?*support.PresentationStore) void {
    cache.deinitAtlas(atlas);
    if (shared) |store| support.release(store) else {
        cache.deinitShapeCache(shapes);
        allocator.free(raster);
    }
}
fn prepareWorking(allocator: std.mem.Allocator, font: *text.FontSet, config: Config) !Working {
    if (config.cursor_stroke_pixels == 0 or config.cursor_stroke_pixels > 16) return error.InvalidCursorStroke;
    const atlas = try cache.initAtlas(allocator, config.faces orelse .{ .regular = font }, config.box_drawing, config.atlas);
    errdefer cache.deinitAtlas(atlas);
    const shapes = try cache.initShapeCache(allocator, config.faces orelse .{ .regular = font }, .{
        .entry_capacity = 256,
        .scalar_capacity = 2048,
        .glyph_capacity = 1024,
        .max_sequence_scalars = 80,
    });
    errdefer cache.deinitShapeCache(shapes);
    const raster = try allocator.alloc(u8, config.raster_bytes);
    errdefer allocator.free(raster);
    var clusters: [16]u32 = undefined;
    var glyphs: [32]text.Glyph = undefined;
    for (if (config.warm) alphabet else "") |scalar| {
        const sequence = [_]u32{scalar};
        const run = try cache.resolveShape(shapes, .regular, &sequence, &clusters, &glyphs);
        if (run.glyphs.len != 1) return error.UnsupportedFont;
        const index = cache.printableAsciiIndex(&sequence).?;
        const image = try cache.resolveFontAtlas(atlas, .regular, run.face_index, run.glyphs[0].id, raster, index, 0);
        cache.rememberAsciiPlacement(atlas, .regular, index, run.glyphs[0], image);
        if (cache.asciiPlacement(atlas, .regular, index) == null)
            return error.UnsupportedFont;
    }
    const metrics = (config.faces orelse cache.FontFaces{ .regular = font }).metrics();
    if (metrics.advance_width == 0 or metrics.line_height == 0) return error.UnsupportedMetrics;
    // zig-audit: acknowledge discard
    // reason: Only checked overflow matters here; accepted width is formed after successful flush.
    _ = try std.math.mul(u16, 80, metrics.advance_width);
    // zig-audit: acknowledge discard
    // reason: Only checked overflow matters here; accepted height is formed after successful flush.
    _ = try std.math.mul(u16, 24, metrics.line_height);
    return .{ .atlas = atlas, .shapes = shapes, .raster = raster, .metrics = metrics };
}
/// One algorithm; instrumentation is absent from the ordinary specialization.
pub fn State(comptime instrumented: bool) type {
    return struct {
        const Candidate = @This();
        const glyph_rows = @import("glyph_rows").Emitter(instrumented);
        const WorkingError = @typeInfo(@typeInfo(@TypeOf(prepareWorking)).@"fn".return_type.?).error_union.error_set;
        /// Native initialization and bounded working-cache setup failures.
        pub const InitError = VT.InitError || WorkingError || SharedWorkingError || error{InvalidCommandLimit};
        /// Transactional borrowed-font replacement failures.
        pub const ReplaceError = WorkingError || error{ HistoryCapacityChange, InvalidCommandLimit };
        const SharedWorkingError = @typeInfo(@typeInfo(@TypeOf(prepareShared)).@"fn".return_type.?).error_union.error_set;
        /// Shared reference admission and local atlas setup failures.
        pub const SharedInitError = InitError;
        /// Shared replacement never changes accepted output on failure.
        pub const SharedReplaceError = SharedWorkingError || error{ HistoryCapacityChange, InvalidCommandLimit };
        /// Canonical bounded resize failures.
        pub const ResizeError = VT.ResizeError || error{UnsupportedDimensions};
        /// Proof-only eager storage reservation failures.
        pub const ReserveError = std.mem.Allocator.Error || error{ OutputAlreadyAccepted, CommandLimit, ResourceCapacityLimit };
        /// Pin admission failures before accepted storage is modified.
        pub const HoldError = error{ NotReady, LeaseBusy };
        /// Native row/resource preparation failures, plus proof faults only in test specialization.
        pub const FlushError = glyph_rows.BuildError || glyph_rows.CursorError || graphics_output.BuildError || std.mem.Allocator.Error || error{ GenerationOverflow, Overflow, PresentationBusy, PixelSizeMismatch } || (if (instrumented) error{ InjectedOutputFailure, InjectedResourceFailure } else error{});
        allocator: std.mem.Allocator,
        vt: *VT,
        owns_vt: bool,
        atlas: *cache.Atlas,
        shapes: *cache.ShapeCache,
        raster: []u8,
        config: Config,
        command_limit: usize,
        shared: ?*support.PresentationStore,
        resources: [3]Resource = @splat(.{}),
        resource_current: u2 = 0,
        resource_held: ?u2 = null,
        color_resources: [3]Resource = @splat(.{}),
        color_current: u2 = 0,
        color_held: ?u2 = null,
        graphics_cuts: [3]graphics_output.Cut = @splat(.{}),
        graphics_current: u2 = 0,
        graphics_held: ?u2 = null,
        graphics_generation: u64 = 0,
        structural_pending: bool = false,
        accepted_reset: u64 = 0,
        visual_context: u64 = 0,
        primary_cells: [*]VT.Cell,
        alternate_cells: [*]VT.Cell,
        accepted_alternate: bool = false,
        accepted_rows: u16 = 24,
        accepted_cols: u16 = 80,
        requested_offset: u32 = 0,
        accepted_offset: u32 = 0,
        accepted_history_base: u32 = 0,
        accepted_history_count: u32 = 0,
        accepted_presentation: VT.Presentation = VT.default_presentation,
        slots: [rows]Slot = @splat(.{}),
        origin: u16 = 0,
        cursor: ?frame.Command = null,
        cursor_shape: ?VT.CursorShape = null,
        cursor_cell: ?frame.Rect = null,
        cursor_text_color: ?frame.Color = null,
        accepted_terminal_revision: u64 = 0,
        accepted_content_revision: u64 = 0,
        accepted_cursor_blink: bool = false,
        accepted_text_blink_visible: bool = true,
        accepted_cursor_movement: u64 = 0,
        cursor_slot: Slot = .{},
        cell_width: u16,
        cell_height: u16,
        baseline: u16,
        working_cell_width: u16,
        working_cell_height: u16,
        config_pending: bool = false,
        ready: bool = false,
        leased: bool = false,
        lease_serial: u64 = 0,
        fail_after_rows: if (instrumented) ?usize else void = if (instrumented) null else {},
        fail_after_resource: if (instrumented) bool else void = if (instrumented) false else {},
        stats: if (instrumented) Stats else void = if (instrumented) .{} else {},

        /// Allocates stable canonical state with default output configuration.
        pub fn init(allocator: std.mem.Allocator, font: *text.FontSet) InitError!*Candidate {
            return initConfig(allocator, font, .{});
        }
        /// Initializes canonical VT in place and prepares private working caches.
        pub fn initConfig(allocator: std.mem.Allocator, font: *text.FontSet, config: Config) InitError!*Candidate {
            return initSource(allocator, .{ .private = font }, config);
        }
        /// Retains the owning shared lane; allocates only native state, local atlas and outputs.
        pub fn initShared(allocator: std.mem.Allocator, store: *support.PresentationStore, config: SharedConfig) SharedInitError!*Candidate {
            return initSource(allocator, .{ .shared = store }, config.internal());
        }
        const Source = union(enum) { private: *text.FontSet, shared: *support.PresentationStore };
        fn initSource(allocator: std.mem.Allocator, source: Source, config: Config) (InitError || SharedInitError)!*Candidate {
            const canonical = try allocator.create(VT);
            errdefer allocator.destroy(canonical);
            try VT.initWithHistoryInto(canonical, allocator, 24, 80, config.history_capacity);
            errdefer canonical.deinit();
            return initCanonical(allocator, canonical, true, source, config) catch |failure| switch (failure) {
                // zig-audit: acknowledge unreachable
                // reason: Owned construction sets canonical pixel size itself.
                error.PixelSizeMismatch, error.UnsupportedDimensions => unreachable,
                else => |err| return err,
            };
        }
        /// Borrowed output construction preserves the canonical VT on failure.
        pub const BorrowedInitError = SharedInitError || error{ PixelSizeMismatch, UnsupportedDimensions, HistoryCapacityMismatch };
        /// Binds output to an existing producer-owned VT without copying its state.
        /// The producer serializes all VT mutation and keeps it alive until deinit.
        pub fn initBorrowedShared(allocator: std.mem.Allocator, canonical: *VT, store: *support.PresentationStore, config: SharedConfig) BorrowedInitError!*Candidate {
            if (config.history_capacity != canonical.screen_state.primary.historyCapacity()) return error.HistoryCapacityMismatch;
            return initCanonical(allocator, canonical, false, .{ .shared = store }, config.internal());
        }
        fn initCanonical(allocator: std.mem.Allocator, canonical: *VT, owns_vt: bool, source: Source, config: Config) (InitError || SharedInitError || error{ PixelSizeMismatch, UnsupportedDimensions })!*Candidate {
            const screen = &canonical.screen_state.primary;
            if (screen.rows == 0 or screen.rows > rows or screen.cols == 0 or screen.cols > cols) return error.UnsupportedDimensions;
            const self = try allocator.create(Candidate);
            errdefer allocator.destroy(self);
            const working = switch (source) {
                .private => |font| try prepareWorking(allocator, font, config),
                .shared => |store| try prepareShared(allocator, store, config),
            };
            const atlas = working.atlas;
            const shapes = working.shapes;
            const raster = working.raster;
            const metrics = working.metrics;
            errdefer destroyWorking(allocator, atlas, shapes, raster, working.shared);
            if (owns_vt) {
                // zig-audit: acknowledge catch_unreachable
                // reason: prepareWorking validated both resolved regular cell dimensions as nonzero.
                canonical.setCellPixelSize(metrics.advance_width, metrics.line_height) catch unreachable;
            } else {
                const cell = canonical.cellPixelSize() orelse return error.PixelSizeMismatch;
                if (cell.width != metrics.advance_width or cell.height != metrics.line_height) return error.PixelSizeMismatch;
                // zig-audit: acknowledge discard
                // reason: Borrowed geometry must fit the output command's pixel extent.
                _ = try std.math.mul(u16, screen.cols, metrics.advance_width);
                // zig-audit: acknowledge discard
                // reason: Borrowed geometry must fit the output command's pixel extent.
                _ = try std.math.mul(u16, screen.rows, metrics.line_height);
            }
            self.allocator = allocator;
            self.vt = canonical;
            self.owns_vt = owns_vt;
            self.atlas = atlas;
            self.shapes = shapes;
            self.raster = raster;
            self.command_limit = try resolveCommandLimit(config, working.shared, metrics.advance_width);
            self.config = config;
            self.shared = working.shared;
            self.resources = @splat(.{});
            self.resource_current = 0;
            self.resource_held = null;
            self.color_resources = @splat(.{});
            self.color_current = 0;
            self.color_held = null;
            self.graphics_cuts = @splat(.{});
            self.graphics_current = 0;
            self.graphics_held = null;
            self.graphics_generation = 0;
            self.structural_pending = false;
            self.accepted_reset = 0;
            self.visual_context = 0;
            self.primary_cells = self.vt.screen_state.primary.cells.?.ptr;
            self.alternate_cells = self.vt.screen_state.alternate.cells.?.ptr;
            self.accepted_alternate = false;
            self.accepted_rows = canonical.screen_state.primary.rows;
            self.accepted_cols = canonical.screen_state.primary.cols;
            self.requested_offset = 0;
            self.accepted_offset = 0;
            self.accepted_history_base = 0;
            self.accepted_history_count = 0;
            self.accepted_presentation = VT.default_presentation;
            self.slots = @splat(.{});
            self.origin = 0;
            self.cursor = null;
            self.cursor_shape = null;
            self.cursor_cell = null;
            self.cursor_text_color = null;
            self.accepted_terminal_revision = 0;
            self.accepted_content_revision = 0;
            self.accepted_cursor_blink = false;
            self.accepted_cursor_movement = 0;
            self.cursor_slot = .{};
            self.cell_width = metrics.advance_width;
            self.cell_height = metrics.line_height;
            self.baseline = metrics.baseline;
            self.working_cell_width = metrics.advance_width;
            self.working_cell_height = metrics.line_height;
            self.config_pending = false;
            self.ready = false;
            self.leased = false;
            self.lease_serial = 0;
            if (instrumented) self.fail_after_rows = null;
            if (instrumented) self.fail_after_resource = false;
            if (instrumented) self.stats = .{};
            return self;
        }
        /// Private caches; all supplied FontSets (regular/bold/italic/bold_italic)
        /// remain caller-owned. Serialize native face use. On success old private
        /// caches are destroyed before return and old fonts may retire if no OTHER
        /// borrower remains. On failure old fonts are still required; new fonts may
        /// retire. New fonts must outlive the next successful replacement or deinit.
        /// No shared Store/ShapeCache claim or reset is performed.
        pub fn replaceWorkingBorrowed(self: *Candidate, font: *text.FontSet, config: Config) ReplaceError!void {
            if (config.history_capacity != self.config.history_capacity) return error.HistoryCapacityChange;
            const next = try prepareWorking(self.allocator, font, config);
            errdefer destroyWorking(self.allocator, next.atlas, next.shapes, next.raster, next.shared);
            try self.validateWorkingGeometry(next.metrics);
            self.installWorking(next, config, try resolveCommandLimit(config, next.shared, next.metrics.advance_width));
        }
        /// Prepared replacement owns its new shared claim and private atlas until committed or discarded.
        pub const Replacement = struct { working: ?Working, config: Config, command_limit: usize };
        /// Replacement preparation rejects unsupported target geometry before mutation.
        pub const StageReplaceError = SharedReplaceError || error{UnsupportedDimensions};

        /// Prepare everything that can fail before changing canonical geometry.
        pub fn stageWorkingShared(self: *Candidate, store: *support.PresentationStore, config: SharedConfig, new_rows: u16, new_cols: u16) StageReplaceError!Replacement {
            const local = config.internal();
            if (local.history_capacity != self.config.history_capacity) return error.HistoryCapacityChange;
            if (new_rows == 0 or new_rows > rows or new_cols == 0 or new_cols > cols) return error.UnsupportedDimensions;
            const next = try prepareShared(self.allocator, store, local);
            errdefer destroyWorking(self.allocator, next.atlas, next.shapes, next.raster, next.shared);
            // zig-audit: acknowledge discard
            // reason: Checked pixel extents must fit before the canonical resize.
            _ = try std.math.mul(u16, new_cols, next.metrics.advance_width);
            // zig-audit: acknowledge discard
            // reason: Checked pixel extents must fit before the canonical resize.
            _ = try std.math.mul(u16, new_rows, next.metrics.line_height);
            return .{ .working = next, .config = local, .command_limit = try resolveCommandLimit(local, next.shared, next.metrics.advance_width) };
        }
        /// Releases an uncommitted replacement without disturbing accepted output.
        pub fn discardWorking(self: *Candidate, replacement: *Replacement) void {
            const next = replacement.working orelse return;
            replacement.working = null;
            destroyWorking(self.allocator, next.atlas, next.shapes, next.raster, next.shared);
        }
        /// Commits an already prepared replacement after canonical resize succeeds.
        pub fn commitWorking(self: *Candidate, replacement: *Replacement) void {
            // zig-audit: acknowledge orelse_unreachable
            // reason: A replacement is committed only once after successful staging.
            const next = replacement.working orelse unreachable;
            replacement.working = null;
            self.installWorking(next, replacement.config, replacement.command_limit);
        }
        /// Replaces a shared lane while retaining the current canonical grid.
        pub fn replaceWorkingShared(self: *Candidate, store: *support.PresentationStore, config: SharedConfig) SharedReplaceError!void {
            const screen = &self.vt.screen_state.primary;
            var replacement = self.stageWorkingShared(store, config, screen.rows, screen.cols) catch |failure| switch (failure) {
                // zig-audit: acknowledge unreachable
                // reason: The current canonical grid was validated by this owner.
                error.UnsupportedDimensions => unreachable,
                else => |err| return err,
            };
            defer self.discardWorking(&replacement);
            self.commitWorking(&replacement);
        }
        fn validateWorkingGeometry(self: *const Candidate, metrics: text.Metrics) error{Overflow}!void {
            // zig-audit: acknowledge discard
            // reason: Only overflow matters; geometry is formed after the staged metrics commit.
            _ = try std.math.mul(u16, self.vt.screen_state.primary.cols, metrics.advance_width);
            // zig-audit: acknowledge discard
            // reason: Only overflow matters; geometry is formed after the staged metrics commit.
            _ = try std.math.mul(u16, self.vt.screen_state.primary.rows, metrics.line_height);
        }
        fn installWorking(self: *Candidate, next: Working, config: Config, command_limit: usize) void {
            // zig-audit: acknowledge catch_unreachable
            // reason: Staged metrics are nonzero; the canonical setter cannot fail or allocate here.
            self.vt.setCellPixelSize(next.metrics.advance_width, next.metrics.line_height) catch unreachable;
            const old_atlas = self.atlas;
            const old_shapes = self.shapes;
            const old_raster = self.raster;
            const old_shared = self.shared;
            self.shared = next.shared;
            self.atlas = next.atlas;
            self.shapes = next.shapes;
            self.raster = next.raster;
            self.config = config;
            self.command_limit = command_limit;
            self.working_cell_width = next.metrics.advance_width;
            self.working_cell_height = next.metrics.line_height;
            self.baseline = next.metrics.baseline;
            self.config_pending = true;
            destroyWorking(self.allocator, old_atlas, old_shapes, old_raster, old_shared);
        }
        /// Destroys unleased state and its private allocations, never borrowed fonts.
        pub fn deinit(self: *Candidate) void {
            std.debug.assert(!self.leased);
            if (self.owns_vt) {
                self.vt.deinit();
                self.allocator.destroy(self.vt);
            }
            destroyWorking(self.allocator, self.atlas, self.shapes, self.raster, self.shared);
            for (self.resources) |resource| self.allocator.free(resource.pixels);
            for (self.color_resources) |resource| self.allocator.free(resource.pixels);
            for (&self.graphics_cuts) |*cut| cut.deinit(self.allocator);
            for (self.slots) |slot| for (slot.blocks) |block| self.allocator.free(block.commands);
            for (self.cursor_slot.blocks) |block| self.allocator.free(block.commands);
            self.allocator.destroy(self);
        }
        // Unsupported input is still canonically committed. Only output is rejected.
        // The native parser alone owns arbitrary byte fragmentation.
        /// Commits whole-slice native input independently of output acceptance.
        pub fn feed(self: *Candidate, bytes: []const u8) VT.FeedError!void {
            // A failed native feed may already have committed a prefix: force repair.
            // zig-audit: acknowledge discard
            // reason: This whole-slice owner does not coordinate partial PTY service consumption.
            _ = self.vt.feed(bytes) catch |err| {
                self.structural_pending = true;
                return err;
            };
            // Native primary row identities survive a bank round trip. Hard reset
            // has its own monotonic key; neither is inferred from input bytes.
        }
        /// Selects the numeric history viewport for the next flush.
        pub fn selectHistoryOffset(self: *Candidate, offset: u32) void {
            self.requested_offset = offset;
        }
        /// Commits bounded native geometry before fallible output preparation.
        pub fn resize(self: *Candidate, new_rows: u16, new_cols: u16) ResizeError!void {
            if (new_rows == 0 or new_rows > rows or new_cols == 0 or new_cols > cols) return error.UnsupportedDimensions;
            // zig-audit: acknowledge discard
            // reason: Reject overflowing pixel geometry before changing canonical state.
            _ = std.math.mul(u16, new_cols, self.working_cell_width) catch return error.UnsupportedDimensions;
            // zig-audit: acknowledge discard
            // reason: Reject overflowing pixel geometry before changing canonical state.
            _ = std.math.mul(u16, new_rows, self.working_cell_height) catch return error.UnsupportedDimensions;
            const changed = self.vt.screen_state.primary.rows != new_rows or self.vt.screen_state.primary.cols != new_cols;
            try self.vt.resize(new_rows, new_cols);
            self.primary_cells = self.vt.screen_state.primary.cells.?.ptr;
            self.alternate_cells = self.vt.screen_state.alternate.cells.?.ptr;
            if (changed) self.structural_pending = true;
        }
        /// Consumes the acknowledged prefix of native reply bytes.
        pub fn consumeReplyBytes(self: *Candidate, count: usize) VT.ReplyConsumeError!void {
            try self.vt.consumeReplyBytes(count);
        }
        /// Counts allocated command capacity across current, held and staging blocks.
        pub fn retainedCommandBytes(self: *const Candidate) usize {
            var total: usize = 0;
            for (self.slots) |slot| for (slot.blocks) |block| {
                total += block.commands.len * @sizeOf(frame.Command);
            };
            for (self.cursor_slot.blocks) |block| total += block.commands.len * @sizeOf(frame.Command);
            return total;
        }
        /// Proof-only init reservation. Never warms or mutates the working atlas.
        /// Partial allocation failure retains reusable private capacities for retry.
        /// Once output is accepted, no reservation may move current or held storage.
        pub fn reserveOutput(self: *Candidate, command_capacity: usize, pixel_capacity: usize) ReserveError!void {
            if (self.ready or self.leased) return error.OutputAlreadyAccepted;
            const height_limit = if (self.config.atlas.growth) |growth| growth.alpha_height_limit else self.config.atlas.height;
            const pixel_limit = @as(usize, self.config.atlas.width) * height_limit;
            if (command_capacity > self.command_limit) return error.CommandLimit;
            if (pixel_capacity > pixel_limit) return error.ResourceCapacityLimit;
            for (&self.slots) |*slot| for (&slot.blocks) |*block| {
                try self.ensureBlock(block, command_capacity);
            };
            for (&self.resources) |*resource| {
                if (resource.pixels.len >= pixel_capacity) continue;
                if (instrumented) self.stats.resource_allocation_attempts += 1;
                const pixels = try self.allocator.alloc(u8, pixel_capacity);
                self.allocator.free(resource.pixels);
                resource.pixels = pixels;
            }
        }
        fn ensureBlock(self: *Candidate, block: *Block, capacity: usize) !void {
            if (block.commands.len >= capacity) return;
            if (capacity > self.command_limit) return error.CommandLimit;
            if (instrumented) self.stats.command_allocation_attempts += 1;
            const commands = try self.allocator.alloc(frame.Command, capacity);
            self.allocator.free(block.commands);
            block.commands = commands;
        }
        fn appendCursor(self: *Candidate, block: *Block, command: frame.Command) (std.mem.Allocator.Error || error{CommandLimit})!void {
            if (block.count == block.commands.len) {
                const capacity = @min(self.command_limit, @max(1, block.commands.len * 2));
                if (capacity == block.commands.len) return error.CommandLimit;
                block.commands = if (block.commands.len == 0)
                    try self.allocator.alloc(frame.Command, capacity)
                else
                    try self.allocator.realloc(block.commands, capacity);
            }
            block.commands[block.count] = command;
            block.count += 1;
        }
        /// Reports the concrete specialization size, excluding referenced allocations.
        pub fn retainedOwnerBytes(_: *const Candidate) usize {
            return @sizeOf(Candidate);
        }
        /// Borrows accepted immutable alpha pixels until the next unpinned replacement.
        pub fn atlasPixels(self: *const Candidate) []const u8 {
            const resource = self.resources[self.resource_current];
            return resource.pixels[0..resource.len];
        }
        /// Returns accepted alpha-resource width.
        pub fn atlasWidth(self: *const Candidate) u16 {
            return self.resources[self.resource_current].width;
        }
        /// Names the accepted alpha-resource generation.
        pub fn committedResource(self: *const Candidate) frame.ResourceRef {
            // zig-audit: acknowledge catch_unreachable
            // reason: The fixed logical resource identifier one is nonzero by construction.
            return .{ .resource = frame.ResourceId.init(1) catch unreachable, .generation = @fromBackingInt(self.resources[self.resource_current].generation) };
        }
        /// Counts working alpha pixels and retained immutable resource capacities.
        pub fn retainedResourceBytes(self: *const Candidate) usize {
            var total: usize = cache.atlasView(self.atlas).pixels.len;
            for (self.resources) |resource| total += resource.pixels.len;
            if (cache.colorAtlasView(self.atlas)) |color| total += color.pixels.len;
            for (self.color_resources) |resource| total += resource.pixels.len;
            for (self.graphics_cuts) |cut| total += cut.pixels.len;
            return total;
        }
        fn committedColorResource(self: *const Candidate) ?frame.ResourceRef {
            const resource = self.color_resources[self.color_current];
            if (resource.len == 0) return null;
            // zig-audit: acknowledge catch_unreachable
            // reason: The fixed color-plane resource identifier two is nonzero.
            return .{ .resource = frame.ResourceId.init(2) catch unreachable, .generation = @fromBackingInt(resource.generation) };
        }
        const ColorStage = struct { index: u2, changed: bool };
        fn stageColor(self: *Candidate) (std.mem.Allocator.Error || error{GenerationOverflow})!ColorStage {
            const accepted = self.color_resources[self.color_current];
            const view = cache.colorAtlasView(self.atlas);
            const entries = cache.colorAtlasEntryCount(self.atlas);
            const changed = if (view) |value|
                self.config_pending or !self.ready or accepted.atlas_epoch != value.generation or accepted.entries != entries or accepted.width != value.width or accepted.height != value.height
            else
                accepted.len != 0;
            if (!changed) return .{ .index = self.color_current, .changed = false };
            if (accepted.generation == std.math.maxInt(u64)) return error.GenerationOverflow;
            var next: u2 = 0;
            while (next == self.color_current or next == self.color_held) next += 1;
            const resource = &self.color_resources[next];
            if (view) |value| {
                if (resource.pixels.len < value.pixels.len) {
                    if (instrumented) self.stats.resource_allocation_attempts += 1;
                    const pixels = try self.allocator.alloc(u8, value.pixels.len);
                    self.allocator.free(resource.pixels);
                    resource.pixels = pixels;
                }
                @memcpy(resource.pixels[0..value.pixels.len], value.pixels);
                resource.len = value.pixels.len;
                resource.width = value.width;
                resource.height = value.height;
                resource.atlas_epoch = value.generation;
                resource.entries = entries;
                if (instrumented) self.stats.resource_pixel_copies += 1;
                if (instrumented) self.stats.resource_pixel_bytes_copied += value.pixels.len;
            } else {
                resource.len = 0;
                resource.width = 0;
                resource.height = 0;
                resource.atlas_epoch = 0;
                resource.entries = 0;
            }
            resource.generation = accepted.generation + 1;
            return .{ .index = next, .changed = true };
        }
        /// Resets this owner’s private working atlas without touching held resources.
        pub fn resetAtlas(self: *Candidate) error{GenerationOverflow}!void {
            try cache.resetAtlas(self.atlas);
        }
        /// Resets this owner’s private shape cache.
        pub fn resetShapes(self: *Candidate) error{SharedStore}!void {
            if (self.shared != null) return error.SharedStore;
            cache.resetShapeCache(self.shapes);
        }
        /// Returns the accepted full-view background.
        pub fn backgroundCommand(self: *const Candidate) frame.Command {
            const bg = self.accepted_presentation.background;
            return .{ .solid = .{
                .rect = .{ .x = 0, .y = 0, .width = self.accepted_cols * self.cell_width, .height = self.accepted_rows * self.cell_height },
                .color = .{ .r = bg.r, .g = bg.g, .b = bg.b, .a = bg.a },
            } };
        }
        /// Returns the accepted supported cursor command, if visible.
        pub fn cursorCommand(self: *const Candidate) ?frame.Command {
            return self.cursor;
        }
        /// Borrows the accepted block-cursor ink until the next unpinned flush.
        pub fn cursorInkCommands(self: *const Candidate) []const frame.Command {
            const block = &self.cursor_slot.blocks[self.cursor_slot.current];
            return block.commands[0..block.count];
        }
        /// Borrows accepted glyph commands for one logical output row.
        pub fn rowCommands(self: *const Candidate, logical_row: usize) []const frame.Command {
            std.debug.assert(self.ready and logical_row < self.accepted_rows);
            const slot = &self.slots[(logical_row + self.origin) % self.accepted_rows];
            const block = &slot.blocks[slot.current];
            return block.commands[block.decoration_end..block.count];
        }
        /// Borrows accepted background commands for one logical output row.
        pub fn rowBackgroundCommands(self: *const Candidate, logical_row: usize) []const frame.Command {
            const slot = &self.slots[(logical_row + self.origin) % self.accepted_rows];
            const block = &slot.blocks[slot.current];
            return block.commands[0..block.background_end];
        }
        /// Borrows accepted decoration commands for one logical output row.
        pub fn rowDecorationCommands(self: *const Candidate, logical_row: usize) []const frame.Command {
            const slot = &self.slots[(logical_row + self.origin) % self.accepted_rows];
            const block = &slot.blocks[slot.current];
            return block.commands[block.background_end..block.decoration_end];
        }
        /// Pins current row/resource blocks and returns immutable borrowed output.
        pub fn hold(self: *Candidate) HoldError!Snapshot {
            if (!self.ready) return error.NotReady;
            if (self.leased) return error.LeaseBusy;
            var result: Snapshot = .{ .history_offset = self.accepted_offset, .history_count = self.accepted_history_count, .history_row_base = self.accepted_history_base, .terminal_revision = self.accepted_terminal_revision, .content_revision = self.accepted_content_revision, .cursor_blink = self.accepted_cursor_blink, .cursor_movement = self.accepted_cursor_movement, .alternate = self.accepted_alternate, .rows = self.accepted_rows, .cols = self.accepted_cols, .surface = .{ .width = self.accepted_cols * self.cell_width, .height = self.accepted_rows * self.cell_height }, .glyphs = @splat(&.{}), .backgrounds = @splat(&.{}), .decorations = @splat(&.{}), .background = self.backgroundCommand(), .cursor = self.cursor, .cursor_shape = self.cursor_shape, .cursor_cell = self.cursor_cell, .cursor_text_color = self.cursor_text_color, .selection_background = self.accepted_presentation.selection_background, .selection_foreground = self.accepted_presentation.selection_foreground, .transparent_background = self.accepted_presentation.transparent_background, .cursor_ink = self.cursorInkCommands(), .cell_width = self.cell_width, .cell_height = self.cell_height, .atlas_pixels = self.atlasPixels(), .atlas_width = self.atlasWidth(), .atlas_height = self.resources[self.resource_current].height, .resource = self.committedResource(), .color_atlas_pixels = self.color_resources[self.color_current].pixels[0..self.color_resources[self.color_current].len], .color_atlas_width = self.color_resources[self.color_current].width, .color_atlas_height = self.color_resources[self.color_current].height, .color_resource = self.committedColorResource() };
            result.visual_context = self.visual_context;
            result.graphics = self.graphics_cuts[self.graphics_current].view();
            result.row_origin = self.origin;
            for (self.slots[0..self.accepted_rows]) |*slot| slot.held = slot.current;
            for (0..self.accepted_rows) |row| {
                result.row_generations[row] = self.slots[(row + self.origin) % self.accepted_rows].generation;
                result.row_damage[row] = self.slots[(row + self.origin) % self.accepted_rows].damage;
                result.glyphs[row] = self.rowCommands(row);
                result.backgrounds[row] = self.rowBackgroundCommands(row);
                result.decorations[row] = self.rowDecorationCommands(row);
                for (result.glyphs[row]) |command| {
                    if (frame.blinks(command)) {
                        result.text_blink_rows[row] = true;
                        break;
                    }
                }
                if (!result.text_blink_rows[row]) for (result.decorations[row]) |command| {
                    if (frame.blinks(command)) {
                        result.text_blink_rows[row] = true;
                        break;
                    }
                };
            }
            result.text_blink_visible = self.accepted_text_blink_visible;
            self.resource_held = self.resource_current;
            self.color_held = self.color_current;
            self.graphics_held = self.graphics_current;
            self.cursor_slot.held = self.cursor_slot.current;
            self.leased = true;
            if (instrumented) self.stats.descriptor_bytes_written += @sizeOf(Snapshot);
            return result;
        }
        /// Releases the single internal pin after its consumer finishes.
        pub fn release(self: *Candidate) void {
            std.debug.assert(self.leased);
            for (&self.slots) |*slot| slot.held = null;
            self.resource_held = null;
            self.color_held = null;
            self.graphics_held = null;
            self.cursor_slot.held = null;
            self.leased = false;
        }
        /// Builds private staging and atomically accepts a complete supported output.
        pub fn flush(self: *Candidate) FlushError!void {
            const alternate = self.vt.screen_state.alt_active;
            const screen = if (alternate) &self.vt.screen_state.alternate else &self.vt.screen_state.primary;
            if (screen.rows == 0 or screen.rows > rows or screen.cols == 0 or screen.cols > cols)
                return error.UnsupportedScene;
            const primary_cells = self.vt.screen_state.primary.cells.?.ptr;
            const alternate_cells = self.vt.screen_state.alternate.cells.?.ptr;
            const changed_backing = primary_cells != self.primary_cells or alternate_cells != self.alternate_cells;
            const pixel_size = self.vt.cellPixelSize() orelse return error.PixelSizeMismatch;
            if (pixel_size.width != self.working_cell_width or pixel_size.height != self.working_cell_height) return error.PixelSizeMismatch;
            // zig-audit: acknowledge discard
            // reason: An externally resized VT must fit before output is staged.
            _ = try std.math.mul(u16, screen.cols, self.working_cell_width);
            // zig-audit: acknowledge discard
            // reason: An externally resized VT must fit before output is staged.
            _ = try std.math.mul(u16, screen.rows, self.working_cell_height);
            const presentation = self.vt.presentation();
            if (screen.view_padding_rows != 0) return error.UnsupportedScene;
            const history_count = if (alternate) 0 else screen.historyCount();
            const history_base = if (alternate) 0 else screen.historyRowBase();
            const offset = @min(self.requested_offset, history_count);
            // Final image commands are cut directly from canonical VT graphics,
            // not from the separate terminal-observation/Render input lane.
            const images = self.vt.images(offset);
            // Placeholder cells are canonical text, so a retained invisible
            // Kitty prototype depends on non-cursor terminal content as well
            // as pixels. Cursor-only motion must not recopy image planes.
            const placeholder_revision: u64 = if (self.vt.graphics.hasVirtualPlacement(if (alternate) .alternate else .primary))
                self.vt.contentSequence()
            else
                0;
            const graphics_changed = !self.ready or !self.graphics_cuts[self.graphics_current].matches(
                images,
                alternate,
                screen.rows,
                screen.cols,
                self.working_cell_width,
                self.working_cell_height,
                placeholder_revision,
            );
            var graphics_next = self.graphics_current;
            if (graphics_changed) {
                if (self.graphics_generation == std.math.maxInt(u64)) return error.GenerationOverflow;
                graphics_next = 0;
                while (graphics_next == self.graphics_current or graphics_next == self.graphics_held) graphics_next += 1;
                // An inactive, unheld cut has no reader. Retire its slab
                // before staging so peak copied graphics stays within three
                // declared cuts even when new content grows to the quota.
                self.graphics_cuts[graphics_next].deinit(self.allocator);
                const cut = try graphics_output.build(
                    self.allocator,
                    images,
                    alternate,
                    screen.rows,
                    screen.cols,
                    self.working_cell_width,
                    self.working_cell_height,
                    placeholder_revision,
                    self.graphics_generation + 1,
                );
                self.graphics_cuts[graphics_next] = cut;
            }
            const accepted = self.resources[self.resource_current];
            const rebuild_all = changed_backing or self.config_pending or offset != self.accepted_offset or (offset != 0 and (history_count != self.accepted_history_count or history_base != self.accepted_history_base)) or screen.rows != self.accepted_rows or screen.cols != self.accepted_cols or alternate != self.accepted_alternate or !std.meta.eql(presentation, self.accepted_presentation) or self.structural_pending or self.vt.resetSequence() != self.accepted_reset or
                cache.atlasView(self.atlas).generation != accepted.atlas_epoch;
            const next_cursor = if (offset != 0) null else try glyph_rows.cursorCommand(self.vt, self.working_cell_width, self.working_cell_height, self.config.cursor_stroke_pixels);
            // One inactive block per changed physical row. No accepted block is
            // touched until EVERY row has passed validation/build.
            var staged: [rows]?u2 = @splat(null);
            var rebuilt: usize = 0;
            var claimed = false;
            defer if (claimed) support.unclaim(self.shared.?);
            var shared_work: ?support.Work = null;
            for (0..screen.rows) |physical| {
                if (instrumented) self.stats.identity_rows_checked += 1;
                const logical = if (offset == 0) (physical + screen.rows - screen.row_origin) % screen.rows else physical;
                const history: ?u32 = if (logical < offset) offset - 1 - @as(u32, @intCast(logical)) else null;
                const live_row: u16 = @intCast(if (history != null) 0 else logical - offset);
                const generation = if (history) |recency| screen.historyRowGeneration(recency).? else if (offset == 0) screen.row_metadata.?[physical].generation else screen.rowGeneration(live_row).?;
                const slot = &self.slots[physical];
                if (self.ready and !rebuild_all and generation == slot.generation) continue;
                if (!claimed) if (self.shared) |store| {
                    if (!support.tryClaim(store)) return error.PresentationBusy;
                    claimed = true;
                    shared_work = support.work(support.borrowStore(store));
                };
                if (instrumented) if (self.fail_after_rows) |limit| if (rebuilt == limit)
                    return error.InjectedOutputFailure;
                var next: u2 = 0;
                while (next == slot.current or next == slot.held) next += 1;
                const block = &slot.blocks[next];
                block.count = 0;
                block.background_end = 0;
                block.decoration_end = 0;
                // An untouched blank row emits no commands. Keep its staging
                // storage empty; the first actual command earns a reservation.
                const counts = while (true) {
                    const result = glyph_rows.buildSelectedRow(.{
                        .atlas = self.atlas,
                        .shapes = self.shapes,
                        .raster = self.raster,
                        .clusters = if (shared_work) |work| work.clusters else null,
                        .shaped = if (shared_work) |work| work.shaped else null,
                        .cell_width = self.working_cell_width,
                        .cell_height = self.working_cell_height,
                        .baseline = self.baseline,
                        .command_bytes_written = if (instrumented) &self.stats.command_bytes_written else {},
                        .full_ascii_rows = if (instrumented) &self.stats.full_ascii_rows else {},
                        .presentation = &presentation,
                        .alpha_resource = self.committedResource(),
                        .color_resource = self.committedColorResource() orelse .{ .resource = try frame.ResourceId.init(2), .generation = @fromBackingInt(1) },
                    }, self.vt, live_row, history, block.commands[0..@min(block.commands.len, self.command_limit)]) catch |err| {
                        if (err != error.CommandLimit or block.commands.len >= self.command_limit) return err;
                        const next_capacity = if (block.commands.len == 0)
                            @min(@as(usize, screen.cols), self.command_limit)
                        else
                            @min(self.command_limit, block.commands.len * 2);
                        try self.ensureBlock(block, next_capacity);
                        continue;
                    };
                    break result;
                };
                block.count = counts.count;
                block.background_end = counts.background_end;
                block.decoration_end = counts.decoration_end;
                staged[physical] = next;
                rebuilt += 1;
            }
            // Native face/cache/scratch work ends here. Publication below touches only
            // this owner's atlas pixels, command blocks and accepted metadata.
            if (claimed) {
                support.unclaim(self.shared.?);
                claimed = false;
            }
            // Freeze exactly the post-admission atlas version. Entry count is required:
            // native cache generation advances only at reset, not ordinary admissions.
            const view = cache.atlasView(self.atlas);
            const entries = cache.alphaAtlasEntryCount(self.atlas);
            const changed = self.config_pending or !self.ready or accepted.atlas_epoch != view.generation or
                accepted.entries != entries or accepted.width != view.width or accepted.height != view.height;
            var resource_next = self.resource_current;
            if (changed) {
                if (accepted.generation == std.math.maxInt(u64)) return error.GenerationOverflow;
                resource_next = 0;
                while (resource_next == self.resource_current or resource_next == self.resource_held) resource_next += 1;
                const resource = &self.resources[resource_next];
                if (resource.pixels.len < view.pixels.len) {
                    if (instrumented) self.stats.resource_allocation_attempts += 1;
                    const pixels = try self.allocator.alloc(u8, view.pixels.len);
                    self.allocator.free(resource.pixels);
                    resource.pixels = pixels;
                }
                @memcpy(resource.pixels[0..view.pixels.len], view.pixels);
                resource.len = view.pixels.len;
                resource.width = view.width;
                resource.height = view.height;
                resource.generation = accepted.generation + 1;
                resource.atlas_epoch = view.generation;
                resource.entries = entries;
                if (instrumented) self.stats.resource_pixel_copies += 1;
                if (instrumented) self.stats.resource_pixel_bytes_copied += view.pixels.len;
            }
            const color_stage = try self.stageColor();
            if (changed or color_stage.changed) {
                // Final commands contain full resource identities. Rebind via COW,
                // never by modifying accepted or held rows in place.
                for (self.slots[0..screen.rows], 0..) |*slot, physical| {
                    if (staged[physical] == null) {
                        const source = &slot.blocks[slot.current];
                        if (source.count == 0) continue;
                        var next: u2 = 0;
                        while (next == slot.current or next == slot.held) next += 1;
                        const target = &slot.blocks[next];
                        try self.ensureBlock(target, source.commands.len);
                        target.count = source.count;
                        target.background_end = source.background_end;
                        target.decoration_end = source.decoration_end;
                        @memcpy(target.commands[0..target.count], source.commands[0..source.count]);
                        staged[physical] = next;
                        if (instrumented) self.stats.command_bytes_copied += source.count * @sizeOf(frame.Command);
                        if (instrumented) self.stats.broad_rebind_rows += 1;
                    }
                }
            }
            const resource = self.resources[resource_next];
            const color = self.color_resources[color_stage.index];
            // Emitted commands already name the accepted resource. A stable
            // atlas needs no second command pass; changed planes still rebind.
            if (changed or color_stage.changed) for (staged, 0..) |next, physical| if (next) |index| {
                const block = &self.slots[physical].blocks[index];
                for (block.commands[0..block.count]) |*command| switch (command.*) {
                    .alpha_mask => |*mask| {
                        mask.resource.resource = .{ .resource = try frame.ResourceId.init(1), .generation = @fromBackingInt(resource.generation) };
                        mask.resource.format = .alpha8;
                        mask.resource.size = .{ .width = resource.width, .height = resource.height };
                        if (instrumented) self.stats.resource_rebind_bytes += @sizeOf(@TypeOf(mask.resource));
                    },
                    .rgba => |*image| {
                        if (color.len == 0) return error.UnsupportedScene;
                        image.resource.resource = .{ .resource = try frame.ResourceId.init(2), .generation = @fromBackingInt(color.generation) };
                        image.resource.format = .rgba8;
                        image.resource.size = .{ .width = color.width, .height = color.height };
                        if (instrumented) self.stats.resource_rebind_bytes += @sizeOf(@TypeOf(image.resource));
                    },
                    else => {},
                };
            };
            // Cursor ink is a final command suffix, staged separately so held
            // frames remain immutable across cursor movement and resource changes.
            var cursor_next: u2 = 0;
            while (cursor_next == self.cursor_slot.current or cursor_next == self.cursor_slot.held) cursor_next += 1;
            const cursor_block = &self.cursor_slot.blocks[cursor_next];
            cursor_block.count = 0;
            if (next_cursor) |cursor| if (cursor.shape == .block) {
                const ink = cursor.text_color;
                const rect = cursor.command.solid.rect;
                const logical: usize = @intCast(@divFloor(rect.y, self.working_cell_height));
                const physical = (logical + screen.row_origin) % screen.rows;
                const slot = &self.slots[physical];
                const block = &slot.blocks[staged[physical] orelse slot.current];
                const row_y: i32 = @intCast(logical * self.working_cell_height);
                for (block.commands[block.decoration_end..block.count]) |command| switch (command) {
                    .alpha_mask => |mask| {
                        if (!mask.cursor_component) continue;
                        var copy = mask;
                        copy.destination.y += row_y;
                        copy.clip.y += row_y;
                        // zig-audit: acknowledge discard
                        // reason: A nonintersecting glyph cannot contribute cursor ink.
                        _ = (try frame.intersectRects(copy.destination, rect)) orelse continue;
                        copy.clip = (try frame.intersectRects(copy.clip, rect)) orelse continue;
                        copy.color = ink;
                        copy.cursor_component = false;
                        try self.appendCursor(cursor_block, .{ .alpha_mask = copy });
                    },
                    .rgba => |image| {
                        var copy = image;
                        copy.destination.y += row_y;
                        copy.clip.y += row_y;
                        // zig-audit: acknowledge discard
                        // reason: A nonintersecting color glyph cannot contribute cursor ink.
                        _ = (try frame.intersectRects(copy.destination, rect)) orelse continue;
                        copy.clip = (try frame.intersectRects(copy.clip, rect)) orelse continue;
                        try self.appendCursor(cursor_block, .{ .rgba = copy });
                    },
                    else => {},
                };
            };
            if (instrumented) if (self.fail_after_resource) return error.InjectedResourceFailure;
            const next_context = if (!self.ready or rebuild_all or graphics_changed) try std.math.add(u64, self.visual_context, 1) else self.visual_context;
            const next_origin: u16 = if (offset == 0) screen.row_origin else 0;
            const content_changed = !self.ready or rebuild_all or rebuilt != 0 or changed or color_stage.changed or graphics_changed or next_origin != self.origin;
            const next_content_revision = if (content_changed) try std.math.add(u64, self.accepted_content_revision, 1) else self.accepted_content_revision;
            // Atomic acceptance: no fallible work below this point.
            self.visual_context = next_context;
            self.cell_width = self.working_cell_width;
            self.cell_height = self.working_cell_height;
            self.config_pending = false;
            self.accepted_rows = screen.rows;
            self.accepted_cols = screen.cols;
            self.accepted_alternate = alternate;
            self.accepted_presentation = presentation;
            self.resource_current = resource_next;
            self.color_current = color_stage.index;
            self.graphics_current = graphics_next;
            if (graphics_changed) self.graphics_generation += 1;
            self.accepted_reset = self.vt.resetSequence();
            self.primary_cells = primary_cells;
            self.alternate_cells = alternate_cells;
            self.structural_pending = false;
            // Only a few changed rows earn an exact command diff. Broad or
            // resource-changing frames keep the established whole-row path.
            const narrow = self.ready and !rebuild_all and !graphics_changed and !changed and !color_stage.changed and rebuilt <= 4;
            for (staged, 0..) |next, physical| if (next) |index| {
                const slot = &self.slots[physical];
                slot.damage = if (narrow) changedRow(&slot.blocks[slot.current], &slot.blocks[index], screen.cols * self.working_cell_width) else null;
                slot.current = index;
                const logical = if (offset == 0) (physical + screen.rows - screen.row_origin) % screen.rows else physical;
                slot.generation = if (logical < offset) screen.historyRowGeneration(offset - 1 - @as(u32, @intCast(logical))).? else if (offset == 0) screen.row_metadata.?[physical].generation else screen.rowGeneration(@intCast(logical - offset)).?;
                if (instrumented) self.stats.descriptor_bytes_written += @sizeOf(u2) + @sizeOf(u64);
            };
            self.accepted_offset = offset;
            self.accepted_history_base = history_base;
            self.accepted_history_count = history_count;
            self.origin = next_origin;
            self.cursor = if (next_cursor) |cursor| cursor.command else null;
            self.cursor_shape = if (next_cursor) |cursor| cursor.shape else null;
            self.cursor_cell = if (next_cursor) |cursor| cursor.cell else null;
            self.cursor_text_color = if (next_cursor) |cursor| cursor.text_color else null;
            const semantic_view = self.vt.semanticView(offset);
            self.accepted_terminal_revision = self.vt.semanticSequence();
            self.accepted_content_revision = next_content_revision;
            self.accepted_cursor_blink = semantic_view.cursor_blink;
            self.accepted_text_blink_visible = self.vt.textBlinkVisible();
            self.accepted_cursor_movement = semantic_view.cursor_movement_timestamp_ns;
            self.cursor_slot.current = cursor_next;
            self.ready = true;
            if (instrumented) self.stats.rows_rebuilt += rebuilt;
            if (instrumented) self.stats.descriptor_bytes_written += @sizeOf(u16) + @sizeOf(?frame.Command);
        }
    };
}
