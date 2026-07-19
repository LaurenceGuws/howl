//! Typed reflow computation and temporary resize storage.

const std = @import("std");
const dirty = @import("dirty.zig");
const cell = @import("cell.zig");
const history_mod = @import("history.zig");
const tabs = @import("tabs.zig");

const Cell = cell.Cell;
const LogicalLine = history_mod.LogicalLine;
const LogicalSnapshot = history_mod.LogicalSnapshot;
const RewrappedRow = history_mod.RewrappedRow;
const default_cell = cell.default_cell;

/// Owned reflow rows, line projections, and projected cursor state.
pub const ReflowState = struct {
    flat_rows: std.ArrayListUnmanaged(Cell) = .empty,
    rewrapped: std.ArrayListUnmanaged(RewrappedRow) = .empty,
    line_row_starts: std.ArrayListUnmanaged(u32) = .empty,
    line_row_counts: std.ArrayListUnmanaged(u16) = .empty,
    global_cursor_row: u32 = 0,
    global_cursor_col: u16 = 0,
    next_wrap_pending: bool = false,

    /// Release every reflow allocation and reset the value.
    pub fn deinit(self: *ReflowState, allocator: std.mem.Allocator) void {
        self.flat_rows.deinit(allocator);
        self.rewrapped.deinit(allocator);
        self.line_row_starts.deinit(allocator);
        self.line_row_counts.deinit(allocator);
        self.* = .{};
    }
};

/// Derived viewport window into complete reflow output.
pub const ViewportState = struct {
    total_rows: u32,
    visible_rows_kept: u16,
    visible_start: u32,
    first_visible_line: u32,
    hidden_rows_in_first_visible_line: u16,
};

/// Owned visible-grid buffers transferred together into a replacement Screen.
pub const ResizeBuffers = struct {
    cells: ?[]Cell,
    row_wraps: ?[]bool,
    dirty_state: dirty.DirtyState,
    tab_stops: ?[]bool,

    const empty: ResizeBuffers = .{
        .cells = null,
        .row_wraps = null,
        .dirty_state = .{},
        .tab_stops = null,
    };

    /// Release every owned buffer and reset the value.
    pub fn deinit(self: *ResizeBuffers, allocator: std.mem.Allocator) void {
        if (self.cells) |buf| allocator.free(buf);
        if (self.row_wraps) |buf| allocator.free(buf);
        self.dirty_state.deinit(allocator);
        if (self.tab_stops) |buf| allocator.free(buf);
        self.* = empty;
    }

    /// Transfer all buffers to one owner and leave this value empty.
    pub fn take(self: *ResizeBuffers) ResizeBuffers {
        const owned = self.*;
        self.* = empty;
        return owned;
    }
};

/// Reflow one borrowed logical snapshot to allocator-owned rows without consuming it.
///
/// Allocation failure releases partial output and leaves the snapshot reusable.
pub fn reflowLogicalLines(allocator: std.mem.Allocator, lines: LogicalSnapshot, cols: u16) std.mem.Allocator.Error!ReflowState {
    var result = ReflowState{};
    errdefer result.deinit(allocator);

    var row_cursor_base: u32 = 0;
    for (lines.logical_lines.items, 0..) |line, line_idx| {
        const rewrapped_before = result.rewrapped.items.len;
        const has_cursor = lines.cursor_found and lines.cursor_line_index == line_idx;
        const line_cursor_offset = boundedCursorOffset(line, has_cursor, lines.cursor_offset);
        const row_count: u16 = @intCast(history_mod.rowCountForCells(history_mod.count32(line.cells.items.len), cols));
        try result.line_row_starts.append(allocator, @intCast(result.rewrapped.items.len));
        try result.line_row_counts.append(allocator, row_count);
        updateCursor(&result, row_cursor_base, line_cursor_offset, cols, has_cursor);
        try appendRewrappedRows(allocator, &result, line.cells.items, row_count, cols);
        row_cursor_base += row_count;

        std.debug.assert(result.line_row_starts.items.len == result.line_row_counts.items.len);
        std.debug.assert(result.rewrapped.items.len == rewrapped_before + row_count);
        std.debug.assert(result.rewrapped.items.len == row_cursor_base);
        std.debug.assert(result.flat_rows.items.len == result.rewrapped.items.len * colCount(cols));
    }

    std.debug.assert(result.line_row_starts.items.len == lines.logical_lines.items.len);
    std.debug.assert(result.line_row_counts.items.len == lines.logical_lines.items.len);
    return result;
}

fn appendRewrappedRows(allocator: std.mem.Allocator, result: *ReflowState, cells: []const Cell, row_count: u16, cols: u16) std.mem.Allocator.Error!void {
    if (cols == 0) return;
    if (row_count == 0) unreachable;

    const flat_rows_before = history_mod.count32(result.flat_rows.items.len);
    const cell_len = history_mod.count32(cells.len);

    var row_idx: u16 = 0;
    while (row_idx < row_count) : (row_idx += 1) {
        const start = rowStart(row_idx, cols);
        const end = @min(cell_len, start + colCount(cols));
        std.debug.assert(start <= end);
        std.debug.assert(end <= cell_len);
        try result.rewrapped.append(allocator, .{
            .start = history_mod.count32(result.flat_rows.items.len),
            .len = @intCast(end - start),
            .wrapped = row_idx + 1 < row_count,
        });
        try appendRowCells(allocator, &result.flat_rows, cells, start, cols);
    }

    std.debug.assert(history_mod.count32(result.flat_rows.items.len) == flat_rows_before + @as(u32, row_count) * colCount(cols));
}

fn appendRowCells(allocator: std.mem.Allocator, flat_rows: *std.ArrayListUnmanaged(Cell), cells: []const Cell, start: u32, cols: u16) std.mem.Allocator.Error!void {
    const cell_len = history_mod.count32(cells.len);
    var col_idx: u16 = 0;
    while (col_idx < cols) : (col_idx += 1) {
        const src_idx = start + @as(u32, col_idx);
        if (src_idx < cell_len) {
            try flat_rows.append(allocator, cells[@intCast(src_idx)]);
        } else {
            try flat_rows.append(allocator, default_cell);
        }
    }
}

fn updateCursor(result: *ReflowState, row_cursor_base: u32, line_cursor_offset: u32, cols: u16, has_cursor: bool) void {
    if (!has_cursor) return;
    if (cols == 0) {
        result.global_cursor_row = 0;
        result.global_cursor_col = 0;
        result.next_wrap_pending = false;
        return;
    }

    if (lineCursorWraps(line_cursor_offset, cols)) {
        result.global_cursor_row = row_cursor_base + @as(u32, line_cursor_offset / cols) - 1;
        result.global_cursor_col = cols - 1;
        result.next_wrap_pending = true;
        return;
    }

    result.global_cursor_row = row_cursor_base + @as(u32, line_cursor_offset / cols);
    result.global_cursor_col = @intCast(line_cursor_offset % cols);
    result.next_wrap_pending = false;
}

/// Select the visible tail and hidden-history boundary from reflow output.
pub fn projectViewport(logical_line_count: u32, reflow: ReflowState, rows: u16) ViewportState {
    const total_rows: u32 = @intCast(reflow.rewrapped.items.len);
    const visible_rows_kept: u16 = @intCast(@min(@as(u32, rows), total_rows));
    const visible_start = total_rows - visible_rows_kept;
    const first_visible_line = history_mod.firstLineForRowBounded(
        reflow.line_row_starts.items,
        reflow.line_row_counts.items,
        visible_start,
    ) orelse logical_line_count;
    const hidden_rows_in_first_visible_line: u16 = if (first_visible_line < logical_line_count)
        @intCast(visible_start - reflow.line_row_starts.items[@intCast(first_visible_line)])
    else
        0;

    std.debug.assert(visible_rows_kept <= rows);
    std.debug.assert(visible_rows_kept <= total_rows);
    std.debug.assert(visible_start <= total_rows);
    std.debug.assert(visible_start + visible_rows_kept == total_rows);
    std.debug.assert(first_visible_line <= logical_line_count);
    if (total_rows == 0) {
        std.debug.assert(first_visible_line == logical_line_count);
        std.debug.assert(hidden_rows_in_first_visible_line == 0);
    } else {
        std.debug.assert(first_visible_line < logical_line_count);
        std.debug.assert(reflow.line_row_starts.items[@intCast(first_visible_line)] <= visible_start);
        std.debug.assert(hidden_rows_in_first_visible_line < reflow.line_row_counts.items[@intCast(first_visible_line)]);
    }

    return .{
        .total_rows = total_rows,
        .visible_rows_kept = visible_rows_kept,
        .visible_start = visible_start,
        .first_visible_line = first_visible_line,
        .hidden_rows_in_first_visible_line = hidden_rows_in_first_visible_line,
    };
}

/// Allocate complete visible-grid replacement buffers for transfer to one Screen.
///
/// Allocation failure releases every completed buffer and returns no owner.
pub fn allocResizeBuffers(allocator: std.mem.Allocator, rows: u16, cols: u16, old_tab_stops: ?[]bool) std.mem.Allocator.Error!ResizeBuffers {
    const cell_count = cellCount(rows, cols);
    var cells: ?[]Cell = null;
    if (cell_count > 0) {
        const buf = try allocator.alloc(Cell, cell_count);
        @memset(buf, default_cell);
        cells = buf;
    }
    errdefer if (cells) |buf| allocator.free(buf);

    var row_wraps: ?[]bool = null;
    if (rows > 0) {
        const buf = try allocator.alloc(bool, rows);
        @memset(buf, false);
        row_wraps = buf;
    }
    errdefer if (row_wraps) |buf| allocator.free(buf);

    const dirty_cols_start = try dirty.allocDirtyCols(allocator, rows, 0);
    errdefer if (dirty_cols_start) |buf| allocator.free(buf);
    const dirty_cols_end = try dirty.allocDirtyCols(allocator, rows, cols -| 1);
    errdefer if (dirty_cols_end) |buf| allocator.free(buf);
    const tab_stops = try tabs.allocTabStops(allocator, cols);
    errdefer if (tab_stops) |buf| allocator.free(buf);
    tabs.copyTabStops(tab_stops, old_tab_stops);

    std.debug.assert((cells != null) == (cell_count > 0));
    std.debug.assert((row_wraps != null) == (rows > 0));
    std.debug.assert((dirty_cols_start != null) == (rows > 0));
    std.debug.assert((dirty_cols_end != null) == (rows > 0));
    std.debug.assert((tab_stops != null) == (cols > 0));
    if (cells) |buf| std.debug.assert(buf.len == cell_count);
    if (row_wraps) |buf| std.debug.assert(buf.len == rows);
    if (dirty_cols_start) |buf| std.debug.assert(buf.len == rows);
    if (dirty_cols_end) |buf| std.debug.assert(buf.len == rows);
    if (tab_stops) |buf| std.debug.assert(buf.len == cols);

    return .{
        .cells = cells,
        .row_wraps = row_wraps,
        .dirty_state = dirty.DirtyState.initFull(rows, dirty_cols_start, dirty_cols_end),
        .tab_stops = tab_stops,
    };
}

/// Copy the selected visible rows into allocated replacement buffers.
pub fn copyVisibleRows(buffers: *ResizeBuffers, reflow: ReflowState, viewport: ViewportState, cols: u16) void {
    const dst = buffers.cells orelse return;
    const dst_wraps = buffers.row_wraps orelse return;

    std.debug.assert(viewport.visible_start + viewport.visible_rows_kept <= viewport.total_rows);
    std.debug.assert(viewport.total_rows == history_mod.count32(reflow.rewrapped.items.len));
    std.debug.assert(history_mod.count32(dst_wraps.len) >= viewport.visible_rows_kept);
    std.debug.assert(history_mod.count32(dst.len) >= cellCount(viewport.visible_rows_kept, cols));
    std.debug.assert(history_mod.count32(reflow.flat_rows.items.len) == history_mod.count32(reflow.rewrapped.items.len) * colCount(cols));

    var src_row = viewport.visible_start;
    var view_row: u16 = 0;
    while (view_row < viewport.visible_rows_kept) : (view_row += 1) {
        const src = reflow.rewrapped.items[@intCast(src_row)];
        const dst_start = rowStart(view_row, cols);
        std.debug.assert(dst_start + colCount(cols) <= history_mod.count32(dst.len));
        @memcpy(dst[@intCast(dst_start)..@intCast(dst_start + colCount(cols))], flatRowSlice(reflow.flat_rows.items, src, cols));
        dst_wraps[@intCast(view_row)] = src.wrapped;
        src_row += 1;
    }

    std.debug.assert(src_row == viewport.visible_start + viewport.visible_rows_kept);
}

fn boundedCursorOffset(line: LogicalLine, has_cursor: bool, cursor_offset: u32) u32 {
    if (!has_cursor) return 0;
    return @min(cursor_offset, @as(u32, @intCast(line.cells.items.len)));
}

fn lineCursorWraps(line_cursor_offset: u32, cols: u16) bool {
    return line_cursor_offset > 0 and line_cursor_offset % cols == 0;
}

fn flatRowSlice(flat_rows: []const Cell, row: RewrappedRow, cols: u16) []const Cell {
    const start = row.start;
    std.debug.assert(start + colCount(cols) <= history_mod.count32(flat_rows.len));
    return flat_rows[@intCast(start)..@intCast(start + colCount(cols))];
}

fn cellCount(rows: u16, cols: u16) u32 {
    return @as(u32, rows) * @as(u32, cols);
}

fn rowStart(row: u16, cols: u16) u32 {
    return @as(u32, row) * @as(u32, cols);
}

fn colCount(cols: u16) u32 {
    return cols;
}
