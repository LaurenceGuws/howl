//! Projects borrowed VT semantics into caller-owned backend-neutral visual patches.

const std = @import("std");
const howl_vt = @import("howl_vt");

const VtTerminal = howl_vt.Terminal;

/// Bounds trailing Unicode scalars copied with one terminal cell.
pub const max_combining: usize = 3;

/// Copies one resolved RGB color without terminal palette identity.
pub const Rgb = struct {
    /// Stores the red component.
    r: u8,
    /// Stores the green component.
    g: u8,
    /// Stores the blue component.
    b: u8,
};

/// Selects normal, raised, or lowered terminal-cell placement.
pub const CellBaseline = enum(u2) { normal, raised, lowered };

/// Selects the resolved visible underline shape.
pub const UnderlineStyle = enum(u3) { none, single, double, curly, dotted, dashed };

/// Selects block, underline, bar, or hidden cursor presentation.
pub const CursorShape = enum(u2) { block, underline, bar, none };

/// Copies one row's DEC geometry without prescribing pixel scaling.
pub const LineGeometry = enum(u2) {
    single_width,
    double_width,
    double_height_top,
    double_height_bottom,
};

/// Supplies final colors for VT-resolved selected cells.
pub const SelectionStyle = struct {
    /// Replaces selected-cell foreground.
    foreground: Rgb,
    /// Replaces selected-cell background.
    background: Rgb,
};

/// Copies one bounded Kitty OSC 66 multicell placement.
pub const TextSizing = struct {
    /// Reports the complete block width in physical cells.
    width: u8 = 1,
    /// Reports the complete block height in physical cells.
    height: u8 = 1,
    /// Locates this cell horizontally within the block.
    x: u8 = 0,
    /// Locates this row vertically within the block.
    y: u8 = 0,
    /// Retains fractional-scale numerator zero through fifteen.
    subscale_n: u4 = 0,
    /// Retains fractional-scale denominator zero through fifteen.
    subscale_d: u4 = 0,
    /// Retains top, bottom, center, or reserved vertical alignment.
    vertical_align: u2 = 0,
    /// Retains left, right, center, or reserved horizontal alignment.
    horizontal_align: u2 = 0,
};

/// Copies one complete backend-neutral terminal visual cell.
pub const Cell = struct {
    /// Stores the base Unicode scalar, or zero for a blank cell.
    codepoint: u21,
    /// Bounds initialized trailing scalars within `combining`.
    combining_len: u8,
    /// Stores up to three trailing Unicode scalars.
    combining: [max_combining]u21,
    /// Copies complete ordinary or Kitty multicell placement.
    sizing: TextSizing = .{},
    /// Copies final foreground color.
    foreground: Rgb,
    /// Copies final background color.
    background: Rgb,
    /// Copies resolved underline color.
    underline_color: Rgb,
    /// Selects the terminal-requested font slot.
    font: u4,
    /// Selects baseline displacement.
    baseline: CellBaseline,
    /// Retains bold rendition intent.
    bold: bool,
    /// Retains dim rendition intent.
    dim: bool,
    /// Retains italic rendition intent.
    italic: bool,
    /// Retains ordinary blink intent.
    blink: bool,
    /// Retains rapid blink intent.
    blink_fast: bool,
    /// Reports whether glyph content is hidden.
    invisible: bool,
    /// Reports whether underline presentation is enabled.
    underline: bool,
    /// Reports whether strikethrough presentation is enabled.
    strikethrough: bool,
    /// Selects the resolved underline shape.
    underline_style: UnderlineStyle,
    /// Reports whether VT selection covers this cell.
    selected: bool,
    /// Identifies retained hyperlink state without interaction policy.
    link_id: u32,
};

/// Copies resolved cursor overlay facts without owning blink timing.
pub const Cursor = struct {
    /// Identifies the cursor row when visible, otherwise zero.
    row: u16,
    /// Identifies the cursor column when visible, otherwise zero.
    col: u16,
    /// Reports whether the overlay is visible.
    visible: bool,
    /// Selects the visible shape, or `none` when hidden.
    shape: CursorShape,
    /// Retains terminal blink intent without owning its phase.
    blink: bool,
    /// Copies resolved cursor fill color.
    color: Rgb,
    /// Copies resolved text color beneath the cursor.
    text_color: Rgb,
};

/// Retains only metadata required to project from an admitted visual state.
pub const ProjectionBaseline = struct {
    /// Records admitted row geometry.
    rows: u16,
    /// Records admitted column geometry.
    cols: u16,
    /// Records the admitted cursor overlay.
    ///
    /// Visible cursors must be in bounds. Hidden cursors use the canonical
    /// zero-valued position, colors, and blink intent produced by `Update`.
    cursor: Cursor,
    /// Records the admitted selection appearance policy.
    selection_style: SelectionStyle,
};

/// Selects complete reconstruction or sparse projection from admitted metadata.
pub const ProjectMode = union(enum) {
    /// Reconstructs every visible row and cell.
    full,
    /// Projects cumulative VT dirtiness and cursor-overlay differences.
    incremental: ProjectionBaseline,
};

/// Supplies caller-owned destination storage for one projection call.
pub const Buffers = struct {
    /// Receives packed initialized cells selected by row patches.
    cells: []Cell,
    /// Receives one ordered patch per affected row.
    rows: []RowPatch,
};

/// Copies one affected visible row and its inclusive visual damage.
pub const RowPatch = struct {
    /// Identifies the visible viewport row.
    row: u16,
    /// Identifies the first copied cell, or cursor damage for an empty patch.
    start_col: u16,
    /// Locates this patch's cells in `Update.cells`.
    cell_offset: usize,
    /// Counts copied cells; zero identifies canonical cursor-only damage.
    cell_count: u16,
    /// Copies current DEC row geometry.
    geometry: LineGeometry,
    /// Identifies the first visually affected column.
    damage_start: u16,
    /// Identifies the last visually affected column.
    damage_end: u16,
};

/// Borrows initialized prefixes of caller buffers after complete projection.
pub const Update = struct {
    /// Copies source row geometry.
    rows: u16,
    /// Copies source column geometry.
    cols: u16,
    /// Reports complete reconstruction rather than a sparse delta.
    full: bool,
    /// Borrows initialized packed cells from the caller buffer.
    cells: []const Cell,
    /// Borrows initialized ordered row patches from the caller buffer.
    row_patches: []const RowPatch,
    /// Copies current canonical cursor overlay.
    cursor: Cursor,
    /// Supplies metadata to retain only after runtime admission succeeds.
    next_baseline: ProjectionBaseline,
};

/// Reports only caller-capacity or explicit reconstruction requirements.
pub const Error = error{ FullRequired, InsufficientCells, InsufficientPatches };

/// Identifies one decoded terminal image already retained by the caller.
pub const ImageIdentity = struct {
    /// Matches the application-selected Kitty image identity.
    id: u32,
    /// Distinguishes replacement content under the same identity.
    generation: u64,
};

/// Locates one newly required RGBA upload in caller pixel storage.
pub const ImageUpload = struct {
    /// Supplies identity and replacement generation.
    identity: ImageIdentity,
    /// Supplies decoded pixel width.
    width: u32,
    /// Supplies decoded pixel height.
    height: u32,
    /// Locates exact RGBA8 bytes in `ImageUpdate.pixels`.
    pixel_offset: usize,
    /// Counts exact RGBA8 bytes.
    pixel_count: usize,
};

/// Copies one visible ordinary terminal image placement.
pub const ImagePlacement = struct {
    /// Resolves retained image content.
    image_id: u32,
    /// Distinguishes placement churn independently of image content.
    generation: u64,
    /// Identifies the visible viewport row.
    row: u16,
    /// Identifies the physical terminal column.
    col: u16,
    /// Selects the first decoded source column.
    source_x: u32 = 0,
    /// Selects the first decoded source row.
    source_y: u32 = 0,
    /// Counts selected decoded source columns.
    source_width: u32 = 0,
    /// Counts selected decoded source rows.
    source_height: u32 = 0,
    /// Offsets the destination within its anchor cell horizontally.
    cell_x: u32 = 0,
    /// Offsets the destination within its anchor cell vertically.
    cell_y: u32 = 0,
    /// Counts destination pixels horizontally.
    pixel_width: u32 = 0,
    /// Counts destination pixels vertically.
    pixel_height: u32 = 0,
    /// Orders the image relative to terminal text.
    z: i32 = 0,
};

/// Supplies caller-owned storage for one image-plane projection.
pub const ImageBuffers = struct {
    /// Lists images retained by the caller before this projection.
    retained: []const ImageIdentity,
    /// Receives only new or replaced RGBA8 bytes.
    pixels: []u8,
    /// Receives only new or replaced image descriptions.
    uploads: []ImageUpload,
    /// Receives retained identities absent from the current VT plane.
    removals: []u32,
    /// Receives the complete current visible placement list.
    placements: []ImagePlacement,
};

/// Borrows initialized image delta prefixes from caller storage.
pub const ImageUpdate = struct {
    /// Reports the source plane identity represented by this delta.
    generation: u64,
    /// Reports the retained decoded image-content identity.
    content_generation: u64,
    /// Borrows packed RGBA8 bytes for `uploads`.
    pixels: []const u8,
    /// Borrows new or replaced images.
    uploads: []const ImageUpload,
    /// Borrows removed image identities.
    removals: []const u32,
    /// Borrows the complete visible placement snapshot.
    placements: []const ImagePlacement,
};

/// Reports exact caller image-delta capacity failures.
pub const ImageError = error{
    InsufficientImagePixels,
    InsufficientImageUploads,
    InsufficientImageRemovals,
    InsufficientImagePlacements,
};

/// Projects one immutable VT image plane into caller-owned upload/removal facts.
///
/// Unchanged retained image bytes are never copied. All capacities are
/// preflighted before any destination mutation.
pub fn projectImages(
    source: VtTerminal.VisualImages,
    buffers: ImageBuffers,
) ImageError!ImageUpdate {
    var pixel_count: usize = 0;
    var upload_count: usize = 0;
    var image_index: usize = 0;
    while (image_index < source.imageCount()) : (image_index += 1) {
        const value = source.image(image_index) orelse continue;
        if (containsImage(buffers.retained, value.id, value.generation)) continue;
        std.debug.assert(pixel_count <= std.math.maxInt(usize) - value.pixels.len);
        pixel_count += value.pixels.len;
        upload_count += 1;
    }
    var removal_count: usize = 0;
    for (buffers.retained) |retained|
        if (!sourceHasImage(source, retained.id)) {
            removal_count += 1;
        };
    var placement_count: usize = 0;
    var placement_index: usize = 0;
    while (placement_index < source.placementCount()) : (placement_index += 1)
        if (source.placement(placement_index) != null) {
            placement_count += 1;
        };

    if (buffers.pixels.len < pixel_count) return error.InsufficientImagePixels;
    if (buffers.uploads.len < upload_count) return error.InsufficientImageUploads;
    if (buffers.removals.len < removal_count) return error.InsufficientImageRemovals;
    if (buffers.placements.len < placement_count) return error.InsufficientImagePlacements;

    var pixel_used: usize = 0;
    var upload_used: usize = 0;
    image_index = 0;
    while (image_index < source.imageCount()) : (image_index += 1) {
        const value = source.image(image_index) orelse continue;
        if (containsImage(buffers.retained, value.id, value.generation)) continue;
        @memcpy(buffers.pixels[pixel_used..][0..value.pixels.len], value.pixels);
        buffers.uploads[upload_used] = .{
            .identity = .{ .id = value.id, .generation = value.generation },
            .width = value.width,
            .height = value.height,
            .pixel_offset = pixel_used,
            .pixel_count = value.pixels.len,
        };
        pixel_used += value.pixels.len;
        upload_used += 1;
    }
    var removal_used: usize = 0;
    for (buffers.retained) |retained| {
        if (sourceHasImage(source, retained.id)) continue;
        buffers.removals[removal_used] = retained.id;
        removal_used += 1;
    }
    var placement_used: usize = 0;
    placement_index = 0;
    while (placement_index < source.placementCount()) : (placement_index += 1) {
        const value = source.placement(placement_index) orelse continue;
        buffers.placements[placement_used] = .{
            .image_id = value.image_id,
            .generation = value.generation,
            .row = value.row,
            .col = value.col,
            .source_x = value.source_x,
            .source_y = value.source_y,
            .source_width = value.source_width,
            .source_height = value.source_height,
            .cell_x = value.cell_x,
            .cell_y = value.cell_y,
            .pixel_width = value.pixel_width,
            .pixel_height = value.pixel_height,
            .z = value.z,
        };
        placement_used += 1;
    }
    return .{
        .generation = source.generation,
        .content_generation = source.content_generation,
        .pixels = buffers.pixels[0..pixel_used],
        .uploads = buffers.uploads[0..upload_used],
        .removals = buffers.removals[0..removal_used],
        .placements = buffers.placements[0..placement_used],
    };
}

fn containsImage(values: []const ImageIdentity, id: u32, generation: u64) bool {
    for (values) |value| if (value.id == id and value.generation == generation) return true;
    return false;
}

fn sourceHasImage(source: VtTerminal.VisualImages, id: u32) bool {
    var index: usize = 0;
    while (index < source.imageCount()) : (index += 1)
        if (source.image(index)) |value| if (value.id == id) return true;
    return false;
}

test "terminal images copy only changed bytes and preflight leaves destinations exact" {
    var vt = try VtTerminal.init(std.testing.allocator, 2, 4);
    defer vt.deinit();
    try std.testing.expect((try vt.feed("\x1b_Ga=T,f=32,s=1,v=1,i=7;AQIDBA==\x1b\\")).state_changed);
    const source = vt.visualView().images;
    var pixels = [_]u8{0xaa} ** 4;
    var uploads: [1]ImageUpload = undefined;
    var removals: [1]u32 = .{99};
    var placements: [1]ImagePlacement = undefined;
    const update = try projectImages(source, .{
        .retained = &.{},
        .pixels = &pixels,
        .uploads = &uploads,
        .removals = &removals,
        .placements = &placements,
    });
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, update.pixels);
    try std.testing.expectEqual(@as(u32, 7), update.uploads[0].identity.id);
    try std.testing.expectEqual(@as(u16, 0), update.placements[0].row);

    const retained = [_]ImageIdentity{update.uploads[0].identity};
    var untouched = [_]u8{0xcc} ** 4;
    const unchanged = try projectImages(source, .{
        .retained = &retained,
        .pixels = &untouched,
        .uploads = &uploads,
        .removals = &removals,
        .placements = &placements,
    });
    try std.testing.expectEqual(@as(usize, 0), unchanged.pixels.len);
    try std.testing.expectEqualSlices(u8, &.{ 0xcc, 0xcc, 0xcc, 0xcc }, &untouched);

    var short = [_]u8{0xdd} ** 3;
    try std.testing.expectError(error.InsufficientImagePixels, projectImages(source, .{
        .retained = &.{},
        .pixels = &short,
        .uploads = &uploads,
        .removals = &removals,
        .placements = &placements,
    }));
    try std.testing.expectEqualSlices(u8, &.{ 0xdd, 0xdd, 0xdd }, &short);
}

const Span = struct { start: u16, end: u16 };

const Work = struct {
    row: u16,
    cells: ?Span,
    damage: Span,
};

const WorkIterator = struct {
    source: *const VtTerminal.VisualView,
    full: bool,
    dirty_iterator: ?VtTerminal.VisualDirtyRows.Iterator,
    next_dirty: ?VtTerminal.VisualDirtyRow,
    cursor_rows: [2]?u16,
    previous_cursor: ?Cursor,
    cursor: Cursor,
    cursor_index: u2 = 0,
    full_row: u16 = 0,

    fn init(source: *const VtTerminal.VisualView, mode: ProjectMode, cursor: Cursor) WorkIterator {
        const dirty = switch (source.dirty) {
            .rows => |rows| rows,
            else => null,
        };
        const iterator = if (dirty) |rows| rows.iterator() else null;
        const baseline = switch (mode) {
            .full => null,
            .incremental => |value| value,
        };
        var cursor_rows = [2]?u16{ null, null };
        if (baseline) |previous| {
            if (!std.meta.eql(previous.cursor, cursor)) {
                if (previous.cursor.visible) cursor_rows[0] = previous.cursor.row;
                if (cursor.visible and cursor_rows[0] != cursor.row) cursor_rows[1] = cursor.row;
                if (cursor_rows[0] != null and cursor_rows[1] != null and
                    cursor_rows[1].? < cursor_rows[0].?)
                {
                    std.mem.swap(?u16, &cursor_rows[0], &cursor_rows[1]);
                }
            }
        }
        const is_full = switch (mode) {
            .full => true,
            .incremental => false,
        };
        var result = WorkIterator{
            .source = source,
            .full = is_full,
            .dirty_iterator = iterator,
            .next_dirty = null,
            .cursor_rows = cursor_rows,
            .previous_cursor = if (baseline) |value| value.cursor else null,
            .cursor = cursor,
        };
        result.next_dirty = if (result.dirty_iterator) |*it| it.next() else null;
        return result;
    }

    fn next(self: *WorkIterator) ?Work {
        if (self.full) {
            if (self.full_row >= self.source.view.rows) return null;
            const row = self.full_row;
            self.full_row += 1;
            return .{
                .row = row,
                .cells = .{ .start = 0, .end = self.source.view.cols - 1 },
                .damage = .{ .start = 0, .end = self.source.view.cols - 1 },
            };
        }

        const cursor_row = while (self.cursor_index < self.cursor_rows.len) {
            const value = self.cursor_rows[self.cursor_index];
            if (value != null) break value;
            self.cursor_index += 1;
        } else null;
        if (self.next_dirty == null and cursor_row == null) return null;
        const row = if (self.next_dirty) |dirty|
            if (cursor_row) |overlay| @min(dirty.row, overlay) else dirty.row
        else
            cursor_row.?;

        var cells: ?Span = null;
        if (self.next_dirty) |dirty| {
            if (dirty.row == row) {
                cells = .{ .start = dirty.start_col, .end = dirty.end_col };
                self.next_dirty = if (self.dirty_iterator) |*it| it.next() else null;
            }
        }
        var damage = cells orelse Span{ .start = self.source.view.cols, .end = 0 };
        while (self.cursor_index < self.cursor_rows.len and self.cursor_rows[self.cursor_index] == row) {
            if (self.previous_cursor) |previous| {
                if (previous.visible and previous.row == row) damage = includeCol(damage, previous.col);
            }
            if (self.cursor.visible and self.cursor.row == row) damage = includeCol(damage, self.cursor.col);
            self.cursor_index += 1;
        }
        std.debug.assert(damage.start <= damage.end);
        return .{ .row = row, .cells = cells, .damage = damage };
    }
};

/// Projects one borrowed VT visual observation into caller-owned buffers.
///
/// This function allocates and owns nothing. The caller must exclude terminal
/// mutation for the complete call and retain no source borrow afterward.
pub fn project(
    source: VtTerminal.VisualView,
    mode: ProjectMode,
    buffers: Buffers,
    fallback_selection_style: SelectionStyle,
) Error!Update {
    const source_ref = &source;
    const selection_style = SelectionStyle{
        .foreground = if (source.presentation.selection_foreground) |color|
            rgb(color)
        else
            fallback_selection_style.foreground,
        .background = if (source.presentation.selection_background) |color|
            rgb(color)
        else
            fallback_selection_style.background,
    };
    std.debug.assert(!slicesOverlap(
        std.mem.sliceAsBytes(buffers.cells),
        std.mem.sliceAsBytes(buffers.rows),
    ));
    const cursor = projectCursor(source_ref);
    const full = switch (mode) {
        .full => true,
        .incremental => |baseline| incremental: {
            if (baseline.rows != source.view.rows or baseline.cols != source.view.cols or
                !std.meta.eql(baseline.selection_style, selection_style) or source.dirty == .full)
                return error.FullRequired;
            assertBaselineCursor(baseline.cursor, baseline.rows, baseline.cols);
            break :incremental false;
        },
    };

    var patch_count: usize = 0;
    var cell_count: usize = 0;
    const maximum_cells = @as(usize, source.view.rows) * @as(usize, source.view.cols);
    var preflight = WorkIterator.init(source_ref, mode, cursor);
    while (preflight.next()) |work| {
        std.debug.assert(patch_count < source.view.rows);
        patch_count += 1;
        if (work.cells) |span| {
            const count = @as(usize, span.end - span.start) + 1;
            std.debug.assert(count <= source.view.cols);
            std.debug.assert(cell_count <= maximum_cells - count);
            cell_count += count;
        }
    }
    if (buffers.rows.len < patch_count) return error.InsufficientPatches;
    if (buffers.cells.len < cell_count) return error.InsufficientCells;

    var row_used: usize = 0;
    var cell_used: usize = 0;
    var writer = WorkIterator.init(source_ref, mode, cursor);
    while (writer.next()) |work| {
        const cell_offset = cell_used;
        if (work.cells) |span| {
            const selected_span = source.selectedSpan(work.row);
            var col = span.start;
            while (col <= span.end) : (col += 1) {
                const selected = if (selected_span) |selected|
                    col >= selected.start and col < selected.end_exclusive
                else
                    false;
                buffers.cells[cell_used] = projectCell(
                    source_ref,
                    work.row,
                    col,
                    selected,
                    selection_style,
                );
                cell_used += 1;
            }
        }
        const copied: u16 = @intCast(cell_used - cell_offset);
        buffers.rows[row_used] = .{
            .row = work.row,
            .start_col = if (work.cells) |span| span.start else work.damage.start,
            .cell_offset = cell_offset,
            .cell_count = copied,
            .geometry = switch (source.view.lineGeometry(work.row)) {
                .single_width => .single_width,
                .double_width => .double_width,
                .double_height_top => .double_height_top,
                .double_height_bottom => .double_height_bottom,
            },
            .damage_start = work.damage.start,
            .damage_end = work.damage.end,
        };
        row_used += 1;
    }
    std.debug.assert(row_used == patch_count and cell_used == cell_count);
    const next_baseline = ProjectionBaseline{
        .rows = source.view.rows,
        .cols = source.view.cols,
        .cursor = cursor,
        .selection_style = selection_style,
    };
    return .{
        .rows = source.view.rows,
        .cols = source.view.cols,
        .full = full,
        .cells = buffers.cells[0..cell_used],
        .row_patches = buffers.rows[0..row_used],
        .cursor = cursor,
        .next_baseline = next_baseline,
    };
}

fn includeCol(span: Span, col: u16) Span {
    if (span.start > span.end) return .{ .start = col, .end = col };
    return .{ .start = @min(span.start, col), .end = @max(span.end, col) };
}

fn projectCursor(source: *const VtTerminal.VisualView) Cursor {
    if (!source.view.cursor_visible or source.view.cursor_shape == .none) return .{
        .row = 0,
        .col = 0,
        .visible = false,
        .shape = .none,
        .blink = false,
        .color = .{ .r = 0, .g = 0, .b = 0 },
        .text_color = .{ .r = 0, .g = 0, .b = 0 },
    };
    std.debug.assert(source.view.cursor_row < source.view.rows);
    std.debug.assert(source.view.cursor_col < source.view.cols);
    return .{
        .row = source.view.cursor_row,
        .col = source.view.cursor_col,
        .visible = true,
        .shape = switch (source.view.cursor_shape) {
            .block => .block,
            .underline => .underline,
            .bar => .bar,
            .none => .none,
        },
        .blink = source.view.cursor_blink,
        .color = rgb(source.presentation.cursor orelse source.presentation.foreground),
        .text_color = rgb(source.presentation.cursor_text orelse source.presentation.background),
    };
}

fn projectCell(
    source: *const VtTerminal.VisualView,
    row: u16,
    col: u16,
    selected_direct: bool,
    selection_style: SelectionStyle,
) Cell {
    const cell = source.view.cellInfoAt(row, col);
    std.debug.assert(cell.width > 0 and cell.height > 0);
    std.debug.assert(cell.x < cell.width and cell.y < cell.height);
    std.debug.assert(cell.combining_len <= max_combining);
    std.debug.assert(cell.codepoint <= std.math.maxInt(u21));
    const codepoint: u21 = @intCast(cell.codepoint);
    std.debug.assert(std.unicode.utf8ValidCodepoint(codepoint));
    var selected = selected_direct;
    const cluster_top = row - cell.y;
    const cluster_left = col - cell.x;
    var cluster_row = cluster_top;
    while (!selected and cluster_row < @min(source.view.rows, cluster_top + cell.height)) : (cluster_row += 1) {
        if (source.selectedSpan(cluster_row)) |span| {
            selected = span.start < cluster_left + cell.width and
                span.end_exclusive > cluster_left;
        }
    }
    var foreground = cell.attrs.fg.resolve(
        source.presentation.foreground,
        &source.presentation.palette,
    );
    var background = cell.attrs.bg.resolve(
        source.presentation.background,
        &source.presentation.palette,
    );
    if (cell.attrs.reverse != source.presentation.reverse_screen)
        std.mem.swap(VtTerminal.Rgb, &foreground, &background);
    const underline_color = cell.attrs.underline_color.resolve(
        foreground,
        &source.presentation.palette,
    );
    var result = Cell{
        .codepoint = codepoint,
        .combining_len = cell.combining_len,
        .combining = @splat(0),
        .sizing = .{
            .width = cell.width,
            .height = cell.height,
            .x = cell.x,
            .y = cell.y,
            .subscale_n = cell.subscale_n,
            .subscale_d = cell.subscale_d,
            .vertical_align = cell.vertical_align,
            .horizontal_align = cell.horizontal_align,
        },
        .foreground = if (selected) selection_style.foreground else rgb(foreground),
        .background = if (selected) selection_style.background else rgb(background),
        .underline_color = rgb(underline_color),
        .font = cell.attrs.font,
        .baseline = switch (cell.attrs.baseline) {
            .normal => .normal,
            .raised => .raised,
            .lowered => .lowered,
        },
        .bold = cell.attrs.bold,
        .dim = cell.attrs.dim,
        .italic = cell.attrs.italic,
        .blink = cell.attrs.blink,
        .blink_fast = cell.attrs.blink_fast,
        .invisible = cell.attrs.invisible,
        .underline = cell.attrs.underline,
        .strikethrough = cell.attrs.strikethrough,
        .underline_style = if (!cell.attrs.underline) .none else switch (cell.attrs.underline_style) {
            .straight => .single,
            .double => .double,
            .curly => .curly,
            .dotted => .dotted,
            .dashed => .dashed,
        },
        .selected = selected,
        .link_id = cell.attrs.link_id,
    };
    for (cell.combining[0..cell.combining_len], 0..) |trailing, index|
        result.combining[index] = @intCast(trailing);
    return result;
}

fn rgb(value: VtTerminal.Rgb) Rgb {
    return .{ .r = value.r, .g = value.g, .b = value.b };
}

fn slicesOverlap(a: []const u8, b: []const u8) bool {
    if (a.len == 0 or b.len == 0) return false;
    const a_start = @intFromPtr(a.ptr);
    const b_start = @intFromPtr(b.ptr);
    return if (a_start <= b_start)
        b_start - a_start < a.len
    else
        a_start - b_start < b.len;
}

fn assertBaselineCursor(cursor: Cursor, rows: u16, cols: u16) void {
    if (cursor.visible) {
        std.debug.assert(cursor.shape != .none and cursor.row < rows and cursor.col < cols);
        return;
    }
    std.debug.assert(std.meta.eql(cursor, Cursor{
        .row = 0,
        .col = 0,
        .visible = false,
        .shape = .none,
        .blink = false,
        .color = .{ .r = 0, .g = 0, .b = 0 },
        .text_color = .{ .r = 0, .g = 0, .b = 0 },
    }));
}
