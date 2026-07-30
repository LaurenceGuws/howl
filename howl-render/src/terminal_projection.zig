//! Projects borrowed VT semantics into caller-owned backend-neutral visual patches.

const std = @import("std");
const howl_vt = @import("howl_vt");

const VtTerminal = howl_vt.Terminal;

/// Owns one fixed bounded cohort of overflow scalars.
pub const ScalarStorage = howl_vt.ScalarStorage;

/// Borrows one exact bounded accepted overflow-scalar cohort synchronously.
pub const ScalarBaseline = struct {
    storage: ?*const ScalarStorage,
    cell_count: usize,

    /// Describes a complete cohort whose cells own no sidecar ranges.
    pub fn empty(cell_count: usize) ScalarBaseline {
        return .{ .storage = null, .cell_count = cell_count };
    }

    /// Borrows one retained cohort for exactly `cell_count` cells.
    pub fn retained(
        storage: *const ScalarStorage,
        cell_count: usize,
    ) ScalarBaseline {
        return .{ .storage = storage, .cell_count = cell_count };
    }

    pub fn validRange(
        self: ScalarBaseline,
        cell: usize,
        combining_len: u8,
    ) bool {
        if (cell >= self.cell_count) return false;
        const storage = self.storage orelse
            return combining_len <= max_combining;
        return storage.validRange(cell, combining_len);
    }

    pub fn tail(
        self: ScalarBaseline,
        cell: usize,
        combining_len: u8,
    ) error{InvalidRange}![]const u32 {
        const storage = self.storage orelse {
            if (combining_len > max_combining or cell >= self.cell_count)
                return error.InvalidRange;
            return &.{};
        };
        return try storage.tail(cell, combining_len);
    }
};

/// Bounds complete base-plus-trailing scalars retained by one lead cell.
pub const maximum_scalars: usize = howl_vt.scalar.maximum_scalars;
/// Bounds trailing scalars retained directly with one lead cell.
pub const max_combining: usize = howl_vt.scalar.inline_scalars - 1;

/// Borrows pinned Unicode classification used after VT occupancy is complete.
pub const UnicodeProperties = howl_vt.UnicodeProperties;

/// Returns exact pinned Unicode facts without assigning cell occupancy.
pub fn unicodeProperties(codepoint: u21) UnicodeProperties {
    return howl_vt.unicodeProperties(codepoint);
}

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

/// Identifies one caller-mapped visible row and column.
///
/// Signed rows permit a caller to clip a selection that extends outside the
/// currently projected view.
pub const SelectionPoint = struct {
    /// Identifies the caller-mapped visible row; negative values are clipped.
    row: i32,
    /// Identifies the caller-mapped visible column.
    col: u16,
};

/// Supplies one caller-owned inclusive selection range in visible rows.
pub const SelectionRange = struct {
    /// Identifies the first selected cell.
    start: SelectionPoint,
    /// Identifies the last selected cell.
    end: SelectionPoint,
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
    /// Reports whether caller-supplied selection covers this cell.
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

/// Retains caller-owned metadata required for retained-state comparison.
pub const ProjectionBaseline = struct {
    /// Records caller-retained row geometry.
    rows: u16,
    /// Records caller-retained column geometry.
    cols: u16,
    /// Records the caller-retained cursor overlay.
    ///
    /// Visible cursors must be in bounds. Hidden cursors use the canonical
    /// zero-valued position, colors, and blink intent produced by `Update`.
    cursor: Cursor,
    /// Borrows the caller's complete previously accepted row-major cells.
    /// Incremental projection validates dimensions, cursor shape, and storage
    /// before comparing or writing anything.
    cells: []const Cell,
    /// Borrows complete overflow scalars keyed by row-major baseline cell.
    scalars: ?*const howl_vt.ScalarStorage = null,
    /// Borrows one previously accepted geometry fact per row.
    geometry: []const LineGeometry,
};

/// Selects complete reconstruction or sparse projection from caller-retained metadata.
pub const ProjectMode = union(enum) {
    /// Reconstructs every visible row and cell.
    full,
    /// Compares caller-retained cells and geometry to derive sparse differences.
    incremental: ProjectionBaseline,
};

/// Supplies caller-owned destination storage for one projection call.
pub const Buffers = struct {
    /// Receives packed initialized cells selected by row patches.
    cells: []Cell,
    /// Owns reusable candidate overflow scratch keyed by source row-major cell.
    /// A scalar-capacity failure may overwrite this private cohort; accepted
    /// baseline ownership changes only after the complete projection and
    /// downstream Content transaction succeed.
    scalars: ?*howl_vt.ScalarStorage = null,
    /// Receives one ordered patch per affected row.
    rows: []RowPatch,
};

/// Copies one affected visible row and its inclusive visual damage.
pub const RowPatch = struct {
    /// Identifies the caller-mapped visible row.
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
    /// Borrows the complete candidate overflow cohort keyed by row-major cell.
    scalars: ?*const howl_vt.ScalarStorage = null,
    /// Borrows initialized ordered row patches from the caller buffer.
    row_patches: []const RowPatch,
    /// Copies current canonical cursor overlay.
    cursor: Cursor,
};

/// Reports invalid caller state or capacity without changing accepted state.
///
/// Validation and ordinary output-capacity errors precede destination
/// mutation. `ScalarCapacity` may leave only `Buffers.scalars` overwritten as
/// reusable private scratch.
pub const Error = error{
    FullRequired,
    InvalidBaseline,
    InsufficientCells,
    InsufficientPatches,
    ScalarCapacity,
    AliasedStorage,
};

const Span = struct { start: u16, end: u16 };

const Work = struct {
    row: u16,
    cells: ?Span,
    damage: Span,
};

const WorkIterator = struct {
    source: *const VtTerminal.SemanticView,
    presentation: *const VtTerminal.Presentation,
    mode: ProjectMode,
    selection: ?SelectionRange,
    selection_style: SelectionStyle,
    cursor: Cursor,
    next_row: u16 = 0,

    fn init(
        source: *const VtTerminal.SemanticView,
        presentation: *const VtTerminal.Presentation,
        mode: ProjectMode,
        selection: ?SelectionRange,
        selection_style: SelectionStyle,
        cursor: Cursor,
    ) WorkIterator {
        return .{
            .source = source,
            .presentation = presentation,
            .mode = mode,
            .selection = selection,
            .selection_style = selection_style,
            .cursor = cursor,
        };
    }

    fn next(self: *WorkIterator) ?Work {
        while (self.next_row < self.source.rows) {
            const row = self.next_row;
            self.next_row += 1;
            const cells = switch (self.mode) {
                .full => Span{ .start = 0, .end = self.source.cols - 1 },
                .incremental => |baseline| changedCells(
                    self.source,
                    self.presentation,
                    baseline,
                    self.selection,
                    self.selection_style,
                    row,
                ),
            };
            const geometry_changed = switch (self.mode) {
                .full => true,
                .incremental => |baseline| baseline.geometry[row] != mapGeometry(self.source.lineGeometry(row)),
            };
            var damage = cells orelse Span{ .start = self.source.cols, .end = 0 };
            if (geometry_changed) damage = .{ .start = 0, .end = self.source.cols - 1 };
            const cursor_span = cursorDamage(self.mode, self.cursor, row);
            if (cursor_span) |span|
                damage = includeSpan(damage, span);
            if (self.mode == .full or cells != null or geometry_changed or cursor_span != null)
                return .{ .row = row, .cells = cells, .damage = damage };
        }
        return null;
    }
};

/// Projects one borrowed VT visual observation into caller-owned buffers.
///
/// This function allocates and owns nothing. The caller must exclude terminal
/// mutation for the complete call, then apply accepted row-cell patches,
/// geometries, and the returned cursor to its retained baseline. A failed
/// scalar admission may overwrite only `buffers.scalars`, which is reusable
/// candidate scratch; it never mutates the borrowed baseline, VT semantics, or
/// a producer revision. The caller must publish neither cells nor scalars until
/// the complete projection and downstream Content transaction both succeed.
pub fn project(
    source: VtTerminal.SemanticView,
    presentation: VtTerminal.Presentation,
    mode: ProjectMode,
    buffers: Buffers,
    selection: ?SelectionRange,
    fallback_selection_style: SelectionStyle,
) Error!Update {
    const source_ref = &source;
    const selection_style = SelectionStyle{
        .foreground = if (presentation.selection_foreground) |color|
            rgb(color)
        else
            fallback_selection_style.foreground,
        .background = if (presentation.selection_background) |color|
            rgb(color)
        else
            fallback_selection_style.background,
    };
    if (slicesOverlap(std.mem.sliceAsBytes(buffers.cells), std.mem.sliceAsBytes(buffers.rows)))
        return error.AliasedStorage;
    if (buffers.scalars) |candidate_scalars| {
        if (candidate_scalars.aliases(std.mem.sliceAsBytes(buffers.cells)) or
            candidate_scalars.aliases(std.mem.sliceAsBytes(buffers.rows)))
            return error.AliasedStorage;
    }
    const cursor = projectCursor(source_ref, &presentation);
    const full = switch (mode) {
        .full => true,
        .incremental => |baseline| incremental: {
            const required = @as(usize, source.rows) * source.cols;
            if (baseline.rows != source.rows or baseline.cols != source.cols or
                baseline.cells.len != required or
                baseline.geometry.len != source.rows)
                return error.FullRequired;
            if (slicesOverlap(std.mem.sliceAsBytes(buffers.cells), std.mem.sliceAsBytes(baseline.cells)) or
                slicesOverlap(std.mem.sliceAsBytes(buffers.rows), std.mem.sliceAsBytes(baseline.cells)) or
                slicesOverlap(std.mem.sliceAsBytes(buffers.cells), std.mem.sliceAsBytes(baseline.geometry)) or
                slicesOverlap(std.mem.sliceAsBytes(buffers.rows), std.mem.sliceAsBytes(baseline.geometry)))
                return error.AliasedStorage;
            if (baseline.scalars) |baseline_scalars| {
                if (baseline_scalars.aliases(std.mem.sliceAsBytes(buffers.cells)) or
                    baseline_scalars.aliases(std.mem.sliceAsBytes(buffers.rows)))
                    return error.AliasedStorage;
                if (buffers.scalars) |candidate_scalars| {
                    if (candidate_scalars.overlapsStorage(baseline_scalars))
                        return error.AliasedStorage;
                }
            }
            if (!validBaselineCursor(baseline.cursor, baseline.rows, baseline.cols))
                return error.InvalidBaseline;
            const scalar_baseline = if (baseline.scalars) |storage|
                ScalarBaseline.retained(storage, required)
            else
                ScalarBaseline.empty(required);
            for (baseline.cells, 0..) |cell, cell_index| {
                const continuation = cell.sizing.x != 0 or cell.sizing.y != 0;
                if (continuation and
                    (cell.codepoint != 0 or cell.combining_len != 0))
                    return error.InvalidBaseline;
                if (!scalar_baseline.validRange(
                    cell_index,
                    cell.combining_len,
                )) return error.InvalidBaseline;
                const tail = scalar_baseline.tail(
                    cell_index,
                    cell.combining_len,
                ) catch return error.InvalidBaseline;
                for (tail) |scalar|
                    if (scalar > std.math.maxInt(u21))
                        return error.InvalidBaseline;
            }
            break :incremental false;
        },
    };

    var patch_count: usize = 0;
    var cell_count: usize = 0;
    const maximum_cells = @as(usize, source.rows) * @as(usize, source.cols);
    var preflight = WorkIterator.init(source_ref, &presentation, mode, selection, selection_style, cursor);
    while (preflight.next()) |work| {
        std.debug.assert(patch_count < source.rows);
        patch_count += 1;
        if (work.cells) |span| {
            const count = @as(usize, span.end - span.start) + 1;
            std.debug.assert(count <= source.cols);
            std.debug.assert(cell_count <= maximum_cells - count);
            cell_count += count;
        }
    }
    if (buffers.rows.len < patch_count) return error.InsufficientPatches;
    if (buffers.cells.len < cell_count) return error.InsufficientCells;
    if (buffers.scalars) |storage| {
        if (storage.cellCapacity() < maximum_cells)
            return error.InsufficientCells;
        storage.clearAll();
        var scalar_row: u16 = 0;
        while (scalar_row < source.rows) : (scalar_row += 1) {
            const row_cells = source.rowCells(scalar_row);
            var scalar_col: u16 = 0;
            while (scalar_col < source.cols) : (scalar_col += 1) {
                const source_cell = row_cells[scalar_col];
                if (source_cell.x != 0 or source_cell.y != 0) continue;
                var scalars: [maximum_scalars]u21 = undefined;
                const sequence = source_ref.cellScalarsAt(
                    scalar_row,
                    scalar_col,
                    &scalars,
                );
                if (sequence.len <= howl_vt.scalar.inline_scalars) continue;
                var tail: [maximum_scalars - howl_vt.scalar.inline_scalars]u32 =
                    undefined;
                for (
                    sequence[howl_vt.scalar.inline_scalars..],
                    0..,
                ) |value, index| tail[index] = value;
                const destination = @as(usize, scalar_row) * source.cols +
                    scalar_col;
                storage.set(
                    destination,
                    0,
                    tail[0 .. sequence.len - howl_vt.scalar.inline_scalars],
                ) catch return error.ScalarCapacity;
            }
        }
    } else {
        var scalar_row: u16 = 0;
        while (scalar_row < source.rows) : (scalar_row += 1) {
            const row_cells = source.rowCells(scalar_row);
            var scalar_col: u16 = 0;
            while (scalar_col < source.cols) : (scalar_col += 1) {
                const source_cell = row_cells[scalar_col];
                if (source_cell.x != 0 or source_cell.y != 0) continue;
                if (source_cell.combining_len > max_combining)
                    return error.ScalarCapacity;
            }
        }
    }

    var row_used: usize = 0;
    var cell_used: usize = 0;
    var writer = WorkIterator.init(source_ref, &presentation, mode, selection, selection_style, cursor);
    while (writer.next()) |work| {
        const cell_offset = cell_used;
        if (work.cells) |span| {
            const row_cells = source.rowCells(work.row);
            var col = span.start;
            while (col <= span.end) : (col += 1) {
                buffers.cells[cell_used] = projectCell(
                    source_ref,
                    &presentation,
                    &row_cells[col],
                    work.row,
                    col,
                    selection,
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
            .geometry = mapGeometry(source.lineGeometry(work.row)),
            .damage_start = work.damage.start,
            .damage_end = work.damage.end,
        };
        row_used += 1;
    }
    std.debug.assert(row_used == patch_count and cell_used == cell_count);
    return .{
        .rows = source.rows,
        .cols = source.cols,
        .full = full,
        .cells = buffers.cells[0..cell_used],
        .scalars = buffers.scalars,
        .row_patches = buffers.rows[0..row_used],
        .cursor = cursor,
    };
}

fn changedCells(
    source: *const VtTerminal.SemanticView,
    presentation: *const VtTerminal.Presentation,
    baseline: ProjectionBaseline,
    selection: ?SelectionRange,
    selection_style: SelectionStyle,
    row: u16,
) ?Span {
    const row_cells = source.rowCells(row);
    var changed: ?Span = null;
    for (row_cells, 0..) |cell, col_index| {
        const col: u16 = @intCast(col_index);
        const current = projectCell(source, presentation, &cell, row, col, selection, selection_style);
        const baseline_index = @as(usize, row) * source.cols + col;
        var source_scalars: [maximum_scalars]u21 = undefined;
        const sequence = source.cellScalarsAt(row, col, &source_scalars);
        const source_tail = if (sequence.len > howl_vt.scalar.inline_scalars)
            sequence[howl_vt.scalar.inline_scalars..]
        else
            &.{};
        const baseline_tail = if (baseline.scalars) |storage|
            storage.tail(
                baseline_index,
                baseline.cells[baseline_index].combining_len,
            ) catch return null
        else
            &.{};
        var scalar_changed = source_tail.len != baseline_tail.len;
        if (!scalar_changed) {
            for (source_tail, baseline_tail) |source_value, baseline_value| {
                if (source_value != baseline_value) {
                    scalar_changed = true;
                    break;
                }
            }
        }
        if (scalar_changed or
            !std.meta.eql(current, baseline.cells[baseline_index]))
            changed = if (changed) |span| .{ .start = span.start, .end = col } else .{ .start = col, .end = col };
    }
    return changed;
}

fn selectionContains(selection: ?SelectionRange, row: u16, col: u16) bool {
    const range = selection orelse return false;
    const point_row: i32 = row;
    const start_before_end = range.start.row < range.end.row or
        (range.start.row == range.end.row and range.start.col <= range.end.col);
    const start_row = if (start_before_end) range.start.row else range.end.row;
    const start_col = if (start_before_end) range.start.col else range.end.col;
    const end_row = if (start_before_end) range.end.row else range.start.row;
    const end_col = if (start_before_end) range.end.col else range.start.col;
    const after_start = point_row > start_row or
        (point_row == start_row and col >= start_col);
    const before_end = point_row < end_row or
        (point_row == end_row and col <= end_col);
    return after_start and before_end;
}

fn cursorDamage(mode: ProjectMode, cursor: Cursor, row: u16) ?Span {
    const baseline = switch (mode) {
        .full => return null,
        .incremental => |value| value,
    };
    if (std.meta.eql(baseline.cursor, cursor)) return null;
    const old_col = if (baseline.cursor.visible and baseline.cursor.row == row) baseline.cursor.col else null;
    const new_col = if (cursor.visible and cursor.row == row) cursor.col else null;
    return if (old_col) |old| if (new_col) |new| .{
        .start = @min(old, new),
        .end = @max(old, new),
    } else .{ .start = old, .end = old } else if (new_col) |new| .{ .start = new, .end = new } else null;
}

fn includeSpan(base: Span, extra: Span) Span {
    if (base.start > base.end) return extra;
    return .{
        .start = @min(base.start, extra.start),
        .end = @max(base.end, extra.end),
    };
}

fn mapGeometry(value: VtTerminal.LineGeometry) LineGeometry {
    return switch (value) {
        .single_width => .single_width,
        .double_width => .double_width,
        .double_height_top => .double_height_top,
        .double_height_bottom => .double_height_bottom,
    };
}

fn projectCursor(source: *const VtTerminal.SemanticView, presentation: *const VtTerminal.Presentation) Cursor {
    if (!source.cursor_visible or source.cursor_shape == .none) return .{
        .row = 0,
        .col = 0,
        .visible = false,
        .shape = .none,
        .blink = false,
        .color = .{ .r = 0, .g = 0, .b = 0 },
        .text_color = .{ .r = 0, .g = 0, .b = 0 },
    };
    std.debug.assert(source.cursor_row < source.rows);
    std.debug.assert(source.cursor_col < source.cols);
    return .{
        .row = source.cursor_row,
        .col = source.cursor_col,
        .visible = true,
        .shape = switch (source.cursor_shape) {
            .block => .block,
            .underline => .underline,
            .bar => .bar,
            .none => .none,
        },
        .blink = source.cursor_blink,
        .color = rgb(presentation.cursor orelse presentation.foreground),
        .text_color = rgb(presentation.cursor_text orelse presentation.background),
    };
}

fn projectCell(
    source: *const VtTerminal.SemanticView,
    presentation: *const VtTerminal.Presentation,
    cell: *const VtTerminal.Cell,
    row: u16,
    col: u16,
    selection: ?SelectionRange,
    selection_style: SelectionStyle,
) Cell {
    std.debug.assert(cell.width > 0 and cell.height > 0);
    std.debug.assert(cell.x < cell.width and cell.y < cell.height);
    std.debug.assert(cell.combining_len < maximum_scalars);
    std.debug.assert(cell.codepoint <= std.math.maxInt(u21));
    const codepoint: u21 = @intCast(cell.codepoint);
    std.debug.assert(std.unicode.utf8ValidCodepoint(codepoint));
    var selected = selectionContains(selection, row, col);
    if (!selected and (cell.width != 1 or cell.height != 1)) {
        const cluster_top: i64 = @as(i64, row) - @as(i64, cell.y);
        const cluster_left: i64 = @as(i64, col) - @as(i64, cell.x);
        const cluster_bottom = cluster_top + @as(i64, cell.height);
        const cluster_right = cluster_left + @as(i64, cell.width);
        const visible_top = @max(cluster_top, @as(i64, 0));
        const visible_left = @max(cluster_left, @as(i64, 0));
        const visible_bottom = @min(cluster_bottom, @as(i64, source.rows));
        const visible_right = @min(cluster_right, @as(i64, source.cols));
        var cluster_row = visible_top;
        while (cluster_row < visible_bottom) : (cluster_row += 1) {
            var cluster_col = visible_left;
            while (cluster_col < visible_right) : (cluster_col += 1) {
                if (selectionContains(selection, @intCast(cluster_row), @intCast(cluster_col))) {
                    selected = true;
                    break;
                }
            }
            if (selected) break;
        }
    }
    var foreground = cell.attrs.fg.resolve(
        presentation.foreground,
        &presentation.palette,
    );
    var background = cell.attrs.bg.resolve(
        presentation.background,
        &presentation.palette,
    );
    if (cell.attrs.reverse != presentation.reverse_screen)
        std.mem.swap(VtTerminal.Rgb, &foreground, &background);
    const underline_color = cell.attrs.underline_color.resolve(
        foreground,
        &presentation.palette,
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
    const direct = @min(@as(usize, cell.combining_len), cell.combining.len);
    for (cell.combining[0..direct], 0..) |trailing, index|
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

fn validBaselineCursor(cursor: Cursor, rows: u16, cols: u16) bool {
    if (cursor.visible) {
        return cursor.shape != .none and cursor.row < rows and cursor.col < cols;
    }
    return std.meta.eql(cursor, Cursor{
        .row = 0,
        .col = 0,
        .visible = false,
        .shape = .none,
        .blink = false,
        .color = .{ .r = 0, .g = 0, .b = 0 },
        .text_color = .{ .r = 0, .g = 0, .b = 0 },
    });
}
