//! Owns visible cells, history projection, cursor state, margins, and screen mutation.

const std = @import("std");
const parser_mod = @import("parser.zig");
const semantic_event = @import("semantic_event.zig");
const cell = @import("screen/cell.zig");
const color = @import("screen/color.zig");
const cursor = @import("screen/cursor.zig");
const dirty = @import("screen/dirty.zig");
const erase = @import("screen/erase.zig");
const history_mod = @import("screen/history.zig");
const rect = @import("screen/rect.zig");
const resize_mod = @import("screen/resize.zig");
const style_mod = @import("screen/style.zig");
const tabs = @import("screen/tabs.zig");

const SemanticEvent = semantic_event.SemanticEvent;
const HistoryLine = history_mod.HistoryLine;
const LogicalLine = history_mod.LogicalLine;
const LogicalSnapshot = history_mod.LogicalSnapshot;
const RewrappedRow = history_mod.RewrappedRow;
const ReflowState = resize_mod.ReflowState;
const ViewportState = resize_mod.ViewportState;
const ResizeBuffers = resize_mod.ResizeBuffers;

/// Terminal screen state for cursor, cells, margins, and history.
pub const Screen = struct {
    /// Failure while validating dimensions or allocating owned Screen storage.
    const InitError = error{ InvalidDimensions, OutOfMemory };

    /// Uses the canonical terminal RGB value for screen state.
    pub const Rgb = color.Rgb;
    /// Uses the canonical default, indexed, or RGB terminal color.
    pub const Color = color.Color;
    /// Uses the canonical terminal underline style.
    pub const UnderlineStyle = cell.UnderlineStyle;
    /// Uses the canonical complete cell attribute value.
    pub const CellAttrs = cell.CellAttrs;
    /// Uses the canonical terminal cell value.
    pub const Cell = cell.Cell;
    /// Uses the canonical cursor shape.
    pub const CursorShape = cursor.CursorShape;
    /// Uses the canonical cursor style.
    pub const CursorStyle = cursor.CursorStyle;
    const SemanticCursor = cursor.SemanticCursor;
    /// Provides the canonical default cursor style.
    pub const default_cursor_style = cursor.default_cursor_style;
    /// Provides the canonical default foreground color.
    pub const default_fg = color.default_fg;
    const default_bg = color.default_bg;
    /// Provides the canonical default underline color.
    pub const default_underline_color = color.default_underline_color;
    /// Provides the canonical default cell attributes.
    pub const default_cell_attrs = cell.default_cell_attrs;
    const default_cell = cell.default_cell;
    const isCellContinuation = cell.isCellContinuation;
    /// Uses the canonical borrowed dirty-row publication view.
    pub const DirtyRows = dirty.DirtyRows;
    const EraseMode = erase.EraseMode;
    const CellPixelSize = struct {
        width: u32,
        height: u32,
    };

    allocator: ?std.mem.Allocator,
    rows: u16,
    cols: u16,
    cursor: SemanticCursor,
    wrap_pending: bool,
    auto_wrap: bool,
    origin_mode: bool,
    insert_mode: bool,
    left_right_margin_mode: bool,
    left_margin: u16,
    right_margin: u16,
    attr_change_extent_rect: bool,
    view_padding_rows: u16,
    row_origin: u16,
    scroll_top: u16,
    scroll_bottom: u16,
    cells: ?[]Cell,
    row_wraps: ?[]bool,
    history: ?[]Cell,
    history_wraps: ?[]bool,
    history_capacity: u16,
    history_count: u32,
    history_write_idx: u32,
    history_row_base: u32,
    history_lines: std.ArrayListUnmanaged(HistoryLine),
    history_lines_start: u32,
    open_history_line: ?HistoryLine,
    last_graphic_codepoint: ?u21,
    current_attrs: CellAttrs,
    dirty_state: dirty.DirtyState,
    tab_stops: ?[]bool,
    cell_pixel_size: ?CellPixelSize,

    fn cellCount(rows: u16, cols: u16) u32 {
        return @as(u32, rows) * @as(u32, cols);
    }

    fn initBase(
        allocator: ?std.mem.Allocator,
        rows: u16,
        cols: u16,
        cursor_style_default: CursorStyle,
        cells: ?[]Cell,
        row_wraps: ?[]bool,
        history: ?[]Cell,
        history_wraps: ?[]bool,
        history_capacity: u16,
        dirty_state: dirty.DirtyState,
        tab_stops: ?[]bool,
    ) Screen {
        return .{
            .allocator = allocator,
            .rows = rows,
            .cols = cols,
            .cursor = cursor.SemanticCursor.init(cursor_style_default),
            .wrap_pending = false,
            .auto_wrap = true,
            .origin_mode = false,
            .insert_mode = false,
            .left_right_margin_mode = false,
            .left_margin = 0,
            .right_margin = cols -| 1,
            .attr_change_extent_rect = false,
            .view_padding_rows = 0,
            .row_origin = 0,
            .scroll_top = 0,
            .scroll_bottom = rows -| 1,
            .cells = cells,
            .row_wraps = row_wraps,
            .history = history,
            .history_wraps = history_wraps,
            .history_capacity = history_capacity,
            .history_count = 0,
            .history_write_idx = 0,
            .history_row_base = 0,
            .history_lines = .empty,
            .history_lines_start = 0,
            .open_history_line = null,
            .last_graphic_codepoint = null,
            .current_attrs = default_cell_attrs,
            .dirty_state = dirty_state,
            .tab_stops = tab_stops,
            .cell_pixel_size = null,
        };
    }

    /// Initialize cursor-only grid state.
    pub fn init(rows: u16, cols: u16) Screen {
        return initWithDefaultCursorStyle(rows, cols, cursor.default_cursor_style);
    }

    fn initWithDefaultCursorStyle(rows: u16, cols: u16, cursor_style_default: CursorStyle) Screen {
        return initBase(null, rows, cols, cursor_style_default, null, null, null, null, 0, .{}, null);
    }

    /// Initialize screen with owned cell storage.
    pub fn initWithCells(allocator: std.mem.Allocator, rows: u16, cols: u16) InitError!Screen {
        return initWithCellsAndDefaultCursorStyle(allocator, rows, cols, cursor.default_cursor_style);
    }

    fn initOwnedVisibleGrid(allocator: std.mem.Allocator, rows: u16, cols: u16, cursor_style_default: CursorStyle) InitError!Screen {
        if (rows == 0 or cols == 0) return error.InvalidDimensions;
        const cell_count = cellCount(rows, cols);
        const cells: ?[]Cell = if (cell_count > 0) blk: {
            const buf = try allocator.alloc(Cell, @intCast(cell_count));
            @memset(buf, default_cell);
            break :blk buf;
        } else null;
        errdefer if (cells) |c| allocator.free(c);
        const row_wraps: ?[]bool = if (rows > 0) blk: {
            const buf = try allocator.alloc(bool, rows);
            @memset(buf, false);
            break :blk buf;
        } else null;
        errdefer if (row_wraps) |buf| allocator.free(buf);
        const dirty_cols_start = try dirty.allocDirtyCols(allocator, rows, 0);
        errdefer if (dirty_cols_start) |buf| allocator.free(buf);
        const dirty_cols_end = try dirty.allocDirtyCols(allocator, rows, cols -| 1);
        errdefer if (dirty_cols_end) |buf| allocator.free(buf);
        const tab_stops = try tabs.allocTabStops(allocator, cols);
        errdefer if (tab_stops) |buf| allocator.free(buf);
        return initBase(
            allocator,
            rows,
            cols,
            cursor_style_default,
            cells,
            row_wraps,
            null,
            null,
            0,
            dirty.DirtyState.initFull(rows, dirty_cols_start, dirty_cols_end),
            tab_stops,
        );
    }

    fn initWithCellsAndDefaultCursorStyle(allocator: std.mem.Allocator, rows: u16, cols: u16, cursor_style_default: CursorStyle) InitError!Screen {
        return initOwnedVisibleGrid(allocator, rows, cols, cursor_style_default);
    }

    /// Initialize screen with cells and history storage.
    pub fn initWithCellsAndHistory(allocator: std.mem.Allocator, rows: u16, cols: u16, history_capacity: u16) InitError!Screen {
        return initWithCellsHistoryAndDefaultCursorStyle(allocator, rows, cols, history_capacity, cursor.default_cursor_style);
    }

    fn initWithCellsHistoryAndDefaultCursorStyle(allocator: std.mem.Allocator, rows: u16, cols: u16, history_capacity: u16, cursor_style_default: CursorStyle) InitError!Screen {
        var screen = try initOwnedVisibleGrid(allocator, rows, cols, cursor_style_default);
        errdefer screen.deinit(allocator);

        const history: ?[]Cell = if (screen.cells != null and history_capacity > 0) blk: {
            const buf = try allocator.alloc(Cell, 0);
            break :blk buf;
        } else null;
        errdefer if (history) |buf| allocator.free(buf);
        const history_wraps: ?[]bool = if (screen.cells != null and history_capacity > 0) blk: {
            const buf = try allocator.alloc(bool, 0);
            break :blk buf;
        } else null;

        screen.history = history;
        screen.history_wraps = history_wraps;
        screen.history_capacity = if (screen.cells != null) history_capacity else 0;
        return screen;
    }

    /// Release owned cell and history buffers.
    pub fn deinit(self: *Screen, allocator: std.mem.Allocator) void {
        if (self.cells) |c| allocator.free(c);
        self.cells = null;
        if (self.row_wraps) |buf| allocator.free(buf);
        self.row_wraps = null;
        self.dirty_state.deinit(allocator);
        if (self.tab_stops) |buf| allocator.free(buf);
        self.tab_stops = null;
        if (self.history) |h| allocator.free(h);
        self.history = null;
        if (self.history_wraps) |buf| allocator.free(buf);
        self.history_wraps = null;
        for (self.history_lines.items) |*line| line.deinit(allocator);
        self.history_lines.deinit(allocator);
        if (self.open_history_line) |*line| line.deinit(allocator);
        self.open_history_line = null;
    }

    /// Replace this screen with a reflowed grid of the requested dimensions.
    ///
    /// Allocation failure leaves this screen unchanged. Successful replacement
    /// preserves logical content and configured cursor defaults, resets margins
    /// to the full new grid, and releases the old owned storage.
    pub fn resize(self: *Screen, allocator: std.mem.Allocator, rows: u16, cols: u16) std.mem.Allocator.Error!void {
        var replacement = try self.prepareResize(allocator, rows, cols);
        std.mem.swap(Screen, self, &replacement);
        replacement.deinit(allocator);
    }

    /// Build complete reflowed screen state without mutating this screen.
    ///
    /// The caller owns the returned Screen and must call `deinit` unless it
    /// transfers ownership by swapping it into a Screen owner.
    pub fn prepareResize(self: *const Screen, allocator: std.mem.Allocator, rows: u16, cols: u16) std.mem.Allocator.Error!Screen {
        var lines = try self.collectLogicalSnapshot(allocator);
        defer lines.deinit(allocator);

        var reflow = try resize_mod.reflowLogicalLines(allocator, lines, cols);
        defer reflow.deinit(allocator);

        const viewport = resize_mod.projectViewport(history_mod.count32(lines.logical_lines.items.len), reflow, rows);
        var buffers = try resize_mod.allocResizeBuffers(allocator, rows, cols, self.tab_stops);
        errdefer buffers.deinit(allocator);

        resize_mod.copyVisibleRows(&buffers, reflow, viewport, cols);
        var replacement = self.replacementBase(allocator);
        replacement.installResizeState(rows, cols, buffers.take());
        errdefer replacement.deinit(allocator);
        try replacement.rebuildResizeAuthority(allocator, lines, reflow, viewport, cols);
        replacement.restoreResizeCursor(rows, cols, reflow, viewport);
        return replacement;
    }

    fn replacementBase(self: *const Screen, allocator: std.mem.Allocator) Screen {
        var replacement = self.*;
        replacement.allocator = allocator;
        replacement.cells = null;
        replacement.row_wraps = null;
        replacement.dirty_state = .{};
        replacement.tab_stops = null;
        replacement.history = null;
        replacement.history_wraps = null;
        replacement.history_count = 0;
        replacement.history_write_idx = 0;
        replacement.history_lines = .empty;
        replacement.history_lines_start = 0;
        replacement.open_history_line = null;
        return replacement;
    }

    fn installResizeState(self: *Screen, rows: u16, cols: u16, buffers: ResizeBuffers) void {
        self.rows = rows;
        self.cols = cols;
        self.cells = buffers.cells;
        self.row_wraps = buffers.row_wraps;
        self.dirty_state = buffers.dirty_state;
        self.tab_stops = buffers.tab_stops;
        self.history = null;
        self.history_wraps = null;
        self.history_count = 0;
        self.history_write_idx = 0;
        self.row_origin = 0;
        self.view_padding_rows = 0;
        self.scroll_top = 0;
        self.scroll_bottom = rows -| 1;
        self.left_right_margin_mode = false;
        self.left_margin = 0;
        self.right_margin = cols -| 1;
        self.attr_change_extent_rect = false;
        self.dirty_state.rows = dirty.rowsForFull(rows, self.dirty_state.cols_start, self.dirty_state.cols_end);

        std.debug.assert(self.rows == rows);
        std.debug.assert(self.cols == cols);
        std.debug.assert((self.cells != null) == (rows > 0 and cols > 0));
        std.debug.assert((self.row_wraps != null) == (rows > 0));
        std.debug.assert((self.dirty_state.cols_start != null) == (rows > 0));
        std.debug.assert((self.dirty_state.cols_end != null) == (rows > 0));
        std.debug.assert((self.tab_stops != null) == (cols > 0));
        if (self.cells) |buf| std.debug.assert(buf.len == cellCount(rows, cols));
        if (self.row_wraps) |buf| std.debug.assert(buf.len == rows);
        if (self.dirty_state.cols_start) |buf| std.debug.assert(buf.len == rows);
        if (self.dirty_state.cols_end) |buf| std.debug.assert(buf.len == rows);
        if (self.tab_stops) |buf| std.debug.assert(buf.len == cols);
        std.debug.assert(self.history == null);
        std.debug.assert(self.history_wraps == null);
        std.debug.assert(self.history_count == 0);
        std.debug.assert(self.history_write_idx == 0);
        std.debug.assert(self.row_origin == 0);
        std.debug.assert(self.view_padding_rows == 0);
        std.debug.assert(self.scroll_top == 0);
        std.debug.assert(self.scroll_bottom == rows -| 1);
        std.debug.assert(self.left_right_margin_mode == false);
        std.debug.assert(self.left_margin == 0);
        std.debug.assert(self.right_margin == cols -| 1);
    }

    fn rebuildResizeAuthority(
        self: *Screen,
        allocator: std.mem.Allocator,
        lines: LogicalSnapshot,
        reflow: ReflowState,
        viewport: ViewportState,
        cols: u16,
    ) std.mem.Allocator.Error!void {
        std.debug.assert(reflow.line_row_starts.items.len == lines.logical_lines.items.len);
        std.debug.assert(reflow.line_row_counts.items.len == lines.logical_lines.items.len);
        std.debug.assert(viewport.total_rows == history_mod.count32(reflow.rewrapped.items.len));
        std.debug.assert(viewport.first_visible_line <= history_mod.count32(lines.logical_lines.items.len));
        if (viewport.first_visible_line < history_mod.count32(lines.logical_lines.items.len)) {
            std.debug.assert(viewport.hidden_rows_in_first_visible_line < reflow.line_row_counts.items[@intCast(viewport.first_visible_line)]);
        } else {
            std.debug.assert(viewport.hidden_rows_in_first_visible_line == 0);
        }

        try self.replaceHistoryAuthority(
            allocator,
            lines.logical_lines.items,
            reflow.line_row_starts.items,
            reflow.line_row_counts.items,
            viewport.first_visible_line,
            viewport.hidden_rows_in_first_visible_line,
            reflow.rewrapped.items,
            cols,
        );
        try self.installResizeProjection(allocator, reflow, viewport);
    }

    fn installResizeProjection(self: *Screen, allocator: std.mem.Allocator, reflow: ReflowState, viewport: ViewportState) std.mem.Allocator.Error!void {
        self.history_count = 0;
        self.history_write_idx = 0;
        if (self.history_capacity == 0 or self.cols == 0) return;

        const kept_complete_start = viewport.first_visible_line -| self.history_capacity;
        const first_projected_row = if (kept_complete_start < history_mod.count32(reflow.line_row_starts.items.len))
            reflow.line_row_starts.items[@intCast(kept_complete_start)]
        else
            viewport.visible_start;
        std.debug.assert(first_projected_row <= viewport.visible_start);
        std.debug.assert(viewport.visible_start <= history_mod.count32(reflow.rewrapped.items.len));

        var row_index = first_projected_row;
        while (row_index < viewport.visible_start) : (row_index += 1) {
            const row = reflow.rewrapped.items[@intCast(row_index)];
            const row_end = row.start + self.cols;
            std.debug.assert(row.len <= self.cols);
            std.debug.assert(row_end <= history_mod.count32(reflow.flat_rows.items.len));
            try self.appendProjectedRow(
                allocator,
                reflow.flat_rows.items[@intCast(row.start)..@intCast(row.start + row.len)],
                row.wrapped,
            );
        }
    }

    fn replaceHistoryAuthority(
        self: *Screen,
        allocator: std.mem.Allocator,
        logical_lines: []const LogicalLine,
        line_row_starts: []const u32,
        line_row_counts: []const u16,
        first_visible_line: u32,
        hidden_rows_in_first_visible_line: u16,
        rewrapped: []const RewrappedRow,
        cols: u16,
    ) std.mem.Allocator.Error!void {
        self.clearHistoryAuthority(allocator);

        std.debug.assert(line_row_starts.len == logical_lines.len);
        std.debug.assert(line_row_counts.len == logical_lines.len);
        std.debug.assert(first_visible_line <= history_mod.count32(logical_lines.len));
        if (first_visible_line < history_mod.count32(logical_lines.len)) {
            std.debug.assert(hidden_rows_in_first_visible_line < line_row_counts[@intCast(first_visible_line)]);
        } else {
            std.debug.assert(hidden_rows_in_first_visible_line == 0);
        }

        const kept_complete_start = if (first_visible_line > self.history_capacity)
            first_visible_line - self.history_capacity
        else
            0;

        var line_idx: u32 = kept_complete_start;
        while (line_idx < first_visible_line) : (line_idx += 1) {
            var line = try cloneAuthorityLine(allocator, logical_lines[@intCast(line_idx)].cells.items);
            self.history_lines.append(allocator, line) catch |err| {
                line.deinit(allocator);
                return err;
            };
        }
        std.debug.assert(self.history_lines.items.len == first_visible_line - kept_complete_start);

        if (first_visible_line < history_mod.count32(logical_lines.len) and hidden_rows_in_first_visible_line > 0) {
            const line = logical_lines[@intCast(first_visible_line)];
            const row_start = line_row_starts[@intCast(first_visible_line)];
            const row_limit = @min(hidden_rows_in_first_visible_line, line_row_counts[@intCast(first_visible_line)]);
            std.debug.assert(row_start + row_limit <= history_mod.count32(rewrapped.len));
            var prefix_len: u32 = 0;
            var hidden_row: u16 = 0;
            while (hidden_row < row_limit) : (hidden_row += 1) {
                const row = rewrapped[@intCast(row_start + hidden_row)];
                std.debug.assert(row.len <= cols);
                prefix_len += rewrapped[@intCast(row_start + hidden_row)].len;
            }
            prefix_len = @min(prefix_len, history_mod.count32(line.cells.items.len));
            std.debug.assert(prefix_len <= history_mod.count32(line.cells.items.len));
            self.open_history_line = try cloneAuthorityLine(allocator, line.cells.items[0..@intCast(prefix_len)]);
        }

        if (self.history_lines.items.len > self.history_capacity) {
            const drop = self.history_lines.items.len - self.history_capacity;
            std.debug.assert(drop <= self.history_lines.items.len);
            var index: u32 = 0;
            while (index < drop) : (index += 1) {
                self.history_lines.items[@intCast(index)].deinit(allocator);
            }
            std.mem.copyForwards(HistoryLine, self.history_lines.items[0 .. self.history_lines.items.len - drop], self.history_lines.items[drop..]);
            self.history_lines.shrinkRetainingCapacity(self.history_lines.items.len - drop);
        }
    }

    fn restoreResizeCursor(self: *Screen, rows: u16, cols: u16, reflow: ReflowState, viewport: ViewportState) void {
        if (rows == 0 or cols == 0 or viewport.total_rows == 0) {
            self.cursor.setPositionStructural(0, 0);
            self.wrap_pending = false;
            std.debug.assert(self.cursor.row == 0);
            std.debug.assert(self.cursor.col == 0);
            std.debug.assert(self.wrap_pending == false);
            return;
        }

        const last_visible_row = viewport.visible_start + viewport.visible_rows_kept - 1;
        const clamped_cursor_row = std.math.clamp(reflow.global_cursor_row, viewport.visible_start, last_visible_row);
        self.cursor.setPositionStructural(@intCast(clamped_cursor_row - viewport.visible_start), @min(reflow.global_cursor_col, cols - 1));
        self.wrap_pending = reflow.next_wrap_pending and self.cursor.row < rows and self.cursor.col == cols - 1;

        std.debug.assert(viewport.visible_rows_kept > 0);
        std.debug.assert(clamped_cursor_row >= viewport.visible_start);
        std.debug.assert(clamped_cursor_row <= last_visible_row);
        std.debug.assert(self.cursor.row < rows);
        std.debug.assert(self.cursor.col < cols);
        if (self.wrap_pending) std.debug.assert(self.cursor.col == cols - 1);
    }

    /// Retain one visible row only after all authority and projection allocations succeed.
    ///
    /// Allocation failure drops this row while preserving paired retained state for the next scroll.
    fn storeHistoryRow(self: *Screen, row: u16) void {
        if (self.history_capacity == 0) return;
        const allocator = self.allocator orelse return;
        const wrapped = self.rowWrapped(row);
        const len = self.visibleRowContentLen(row);
        var next_line = cloneAuthorityLine(
            allocator,
            if (self.open_history_line) |line| line.cells.items else &.{},
        ) catch return;
        defer next_line.deinit(allocator);

        next_line.cells.ensureTotalCapacity(allocator, next_line.cells.items.len + len) catch return;
        var col: u16 = 0;
        while (col < len) : (col += 1) {
            next_line.cells.appendAssumeCapacity(self.cellInfoAt(row, col));
        }

        const replacing_oldest = !wrapped and self.history_lines.items.len == self.history_capacity;
        const projected_drop = if (replacing_oldest)
            self.projectedRowCountForCells(self.historyLineAt(0).cells.items)
        else
            0;
        const projected_after_drop = self.history_count -| projected_drop;
        const projected_target = @min(projected_after_drop + 1, @as(u32, self.history_capacity));
        self.ensureProjectedCapacity(allocator, projected_target) catch return;
        if (!wrapped and !replacing_oldest) {
            self.history_lines.ensureTotalCapacity(allocator, self.history_lines.items.len + 1) catch return;
        }

        const replacement_slot = if (replacing_oldest) self.dropOldestHistoryLine(allocator) else null;
        self.appendProjectedRowAssumeCapacity(
            next_line.cells.items[next_line.cells.items.len - len ..],
            wrapped,
        );

        if (self.open_history_line) |*line| line.deinit(allocator);
        self.open_history_line = null;
        if (wrapped) {
            self.open_history_line = next_line;
        } else if (replacement_slot) |slot| {
            self.history_lines.items[@intCast(slot)] = next_line;
        } else {
            self.history_lines.appendAssumeCapacity(next_line);
        }
        next_line = .{};
    }

    /// Release retained logical history while preserving list capacity.
    fn clearHistoryAuthority(self: *Screen, allocator: std.mem.Allocator) void {
        for (self.history_lines.items) |*line| line.deinit(allocator);
        self.history_lines.clearRetainingCapacity();
        self.history_lines_start = 0;
        if (self.open_history_line) |*line| line.deinit(allocator);
        self.open_history_line = null;
    }

    /// Rebuild projected history rows from retained logical authority.
    fn rebuildHistoryProjection(self: *Screen, allocator: std.mem.Allocator) std.mem.Allocator.Error!void {
        self.history_count = 0;
        self.history_write_idx = 0;

        if (self.history_capacity == 0 or self.cols == 0) return;

        var line_idx: u32 = 0;
        while (line_idx < self.historyLineCount()) : (line_idx += 1) {
            const line = self.historyLineAt(line_idx);
            try self.appendProjectionRows(allocator, line.cells.items, false);
        }
        if (self.open_history_line) |line| {
            try self.appendProjectionRows(allocator, line.cells.items, true);
        }
    }

    /// Clone retained, open, and visible content into one allocator-owned logical snapshot.
    ///
    /// Allocation failure releases partial clones and leaves this Screen unchanged.
    pub fn collectLogicalSnapshot(self: *const Screen, allocator: std.mem.Allocator) std.mem.Allocator.Error!LogicalSnapshot {
        var result = LogicalSnapshot{};
        errdefer result.deinit(allocator);

        var current_line = try cloneLogicalLine(
            allocator,
            if (self.open_history_line) |line| line.cells.items else &.{},
        );
        defer current_line.deinit(allocator);

        var history_line_idx: u32 = 0;
        while (history_line_idx < self.historyLineCount()) : (history_line_idx += 1) {
            const line = self.historyLineAt(history_line_idx);
            var copied = try cloneLogicalLine(allocator, line.cells.items);
            result.logical_lines.append(allocator, copied) catch |err| {
                copied.deinit(allocator);
                return err;
            };
        }

        var row: u16 = 0;
        while (row < self.rows) : (row += 1) {
            try self.appendSourceRowToLogicalSnapshot(allocator, &result, &current_line, row);
        }

        if (current_line.cells.items.len > 0 or current_line.cursor_offset != null or result.logical_lines.items.len == 0) {
            if (current_line.cursor_offset) |offset| {
                result.cursor_found = true;
                result.cursor_line_index = @intCast(result.logical_lines.items.len);
                result.cursor_offset = offset;
            }
            try result.logical_lines.append(allocator, current_line);
            current_line = .{};
        }

        while (result.logical_lines.items.len > 1) {
            const last_idx = result.logical_lines.items.len - 1;
            const last = &result.logical_lines.items[last_idx];
            if (last.cells.items.len > 0) break;
            if (result.cursor_found and result.cursor_line_index == last_idx) break;
            last.deinit(allocator);
            result.logical_lines.items.len = last_idx;
        }
        return result;
    }

    fn appendSourceRowToLogicalSnapshot(
        self: *const Screen,
        allocator: std.mem.Allocator,
        result: *LogicalSnapshot,
        current_line: *LogicalLine,
        row: u16,
    ) std.mem.Allocator.Error!void {
        const wrapped = self.rowWrapped(row);
        const content_len = self.sourceRowContentLen(row);

        if (row == self.cursor.row) {
            current_line.cursor_offset = @as(u32, @intCast(current_line.cells.items.len)) + self.cursorOffsetInRow();
        }

        var col: u16 = 0;
        while (col < content_len) : (col += 1) {
            try current_line.cells.append(allocator, self.cellInfoAt(row, col));
        }

        if (!wrapped) {
            if (current_line.cursor_offset) |offset| {
                result.cursor_found = true;
                result.cursor_line_index = @intCast(result.logical_lines.items.len);
                result.cursor_offset = offset;
            }
            try result.logical_lines.append(allocator, current_line.*);
            current_line.* = .{};
        }
    }

    fn sourceRowContentLen(self: *const Screen, row: u16) u16 {
        var last_non_zero: u16 = 0;
        var has_content = false;
        var col: u16 = 0;
        while (col < self.cols) : (col += 1) {
            if (self.cellInfoAt(row, col).codepoint != 0) {
                has_content = true;
                last_non_zero = col + 1;
            }
        }

        var len: u16 = if (has_content) last_non_zero else 0;
        if (self.rowWrapped(row) and self.cols > 0) len = @max(len, self.cols);
        return len;
    }

    fn cursorOffsetInRow(self: *const Screen) u32 {
        if (self.cols == 0) return 0;
        if (self.wrap_pending and self.cursor.col == self.cols - 1) return self.cols;
        return self.cursor.col;
    }

    fn appendProjectionRows(self: *Screen, allocator: std.mem.Allocator, cells: []const Cell, continues_to_visible: bool) std.mem.Allocator.Error!void {
        const cols: u32 = self.cols;
        if (cols == 0) return;
        const cell_count: u32 = @intCast(cells.len);
        const row_count = @max(@as(u32, 1), std.math.divCeil(u32, cell_count, self.cols) catch unreachable);
        std.debug.assert(row_count > 0);

        var row_idx: u32 = 0;
        while (row_idx < row_count) : (row_idx += 1) {
            const start = row_idx * cols;
            const end = @min(cell_count, start + cols);
            std.debug.assert(start <= end);
            std.debug.assert(end <= cell_count);
            try self.appendProjectedRow(allocator, cells[@intCast(start)..@intCast(end)], row_idx + 1 < row_count or continues_to_visible);
        }
    }

    fn visibleRowContentLen(self: *const Screen, row: u16) u16 {
        var col = self.cols;
        while (col > 0) {
            const idx = col - 1;
            if (self.cellInfoAt(row, idx).codepoint != 0) return col;
            col -= 1;
        }
        if (self.rowWrapped(row) and self.cols > 0) return self.cols;
        return 0;
    }

    fn dropOldestHistoryLine(self: *Screen, allocator: std.mem.Allocator) u32 {
        std.debug.assert(self.historyLineCount() == self.history_capacity);
        const slot = self.history_lines_start;
        self.dropOldestProjectedRows(self.projectedRowCountForCells(self.history_lines.items[@intCast(slot)].cells.items));
        self.history_lines.items[@intCast(slot)].deinit(allocator);
        self.history_lines.items[@intCast(slot)] = .{};
        self.history_lines_start = (self.history_lines_start + 1) % self.historyLineCount();
        return slot;
    }

    fn appendProjectedRow(self: *Screen, allocator: std.mem.Allocator, cells: []const Cell, wrapped: bool) std.mem.Allocator.Error!void {
        if (self.cols == 0) return;
        const capacity_target = @min(self.history_count + 1, @as(u32, self.history_capacity));
        try self.ensureProjectedCapacity(allocator, capacity_target);
        self.appendProjectedRowAssumeCapacity(cells, wrapped);
    }

    fn appendProjectedRowAssumeCapacity(self: *Screen, cells: []const Cell, wrapped: bool) void {
        const wraps = self.history_wraps orelse return;
        const history = self.history orelse return;
        std.debug.assert(self.projectedCapacity() >= @min(self.history_count + 1, @as(u32, self.history_capacity)));
        if (self.history_count == self.history_capacity) {
            self.dropOldestProjectedRows(1);
        }
        const slot = self.projectedAppendSlot();
        const cols: u32 = self.cols;
        const base = slot * cols;
        const cell_count: u32 = @intCast(cells.len);

        std.debug.assert(cell_count <= cols);
        std.debug.assert(slot < wraps.len);
        std.debug.assert(base + cols <= history.len);

        @memset(history[@intCast(base)..@intCast(base + cols)], default_cell);
        @memcpy(history[@intCast(base)..@intCast(base + cell_count)], cells);
        wraps[@intCast(slot)] = wrapped;
        self.history_count += 1;
    }

    fn ensureProjectedCapacity(self: *Screen, allocator: std.mem.Allocator, min_rows: u32) std.mem.Allocator.Error!void {
        if (self.cols == 0) return;

        const current_rows = self.projectedCapacity();
        if (current_rows >= min_rows) return;

        const new_rows = @max(min_rows, @max(current_rows * 2, @as(u32, 8)));
        const cols: u32 = self.cols;
        const new_history = try allocator.alloc(Cell, @intCast(new_rows * cols));
        errdefer allocator.free(new_history);
        @memset(new_history, default_cell);

        const new_wraps = try allocator.alloc(bool, @intCast(new_rows));
        errdefer allocator.free(new_wraps);
        @memset(new_wraps, false);

        const old_count = self.history_count;
        std.debug.assert(old_count <= current_rows);
        var logical_row: u32 = 0;
        while (logical_row < old_count) : (logical_row += 1) {
            const old_slot = self.historySlotForLogicalRow(logical_row) orelse break;
            const source_start = old_slot * cols;
            const dest_start = logical_row * cols;
            std.debug.assert(old_slot < current_rows);
            std.debug.assert(source_start + cols <= if (self.history) |history| history.len else 0);
            std.debug.assert(dest_start + cols <= new_history.len);
            if (self.history) |history| {
                @memcpy(new_history[@intCast(dest_start)..@intCast(dest_start + cols)], history[@intCast(source_start)..@intCast(source_start + cols)]);
            }
            if (self.history_wraps) |wraps| new_wraps[@intCast(logical_row)] = wraps[@intCast(old_slot)];
        }

        if (self.history) |history| allocator.free(history);
        if (self.history_wraps) |wraps| allocator.free(wraps);
        self.history = new_history;
        self.history_wraps = new_wraps;
        self.history_write_idx = 0;
    }

    fn dropOldestProjectedRows(self: *Screen, row_count: u32) void {
        if (row_count == 0 or self.history_count == 0) return;

        const drop = @min(row_count, self.history_count);
        const capacity = self.projectedCapacity();
        std.debug.assert(drop <= self.history_count);
        if (drop == self.history_count or capacity == 0) {
            self.history_row_base += self.history_count;
            self.history_count = 0;
            self.history_write_idx = 0;
            return;
        }

        std.debug.assert(self.history_write_idx < capacity);
        self.history_write_idx = (self.history_write_idx + drop) % capacity;
        self.history_count -= drop;
        self.history_row_base += drop;
    }

    /// Reset visible grid state to defaults.
    pub fn reset(self: *Screen) void {
        self.cursor.reset();
        self.wrap_pending = false;
        self.auto_wrap = true;
        self.origin_mode = false;
        self.insert_mode = false;
        self.left_right_margin_mode = false;
        self.left_margin = 0;
        self.right_margin = self.cols -| 1;
        self.attr_change_extent_rect = false;
        self.view_padding_rows = 0;
        self.row_origin = 0;
        self.scroll_top = 0;
        self.scroll_bottom = self.rows -| 1;
        self.last_graphic_codepoint = null;
        self.current_attrs = default_cell_attrs;
        self.markAllRowsDirty();
        if (self.cells) |c| @memset(c, default_cell);
        if (self.row_wraps) |buf| @memset(buf, false);
        if (self.tab_stops) |stops| tabs.setDefaultTabStops(stops);
    }

    /// Replaces the configured cursor default on this screen.
    pub fn setDefaultCursorStyle(self: *Screen, style: CursorStyle) void {
        self.cursor.setDefaultStyle(style);
    }

    /// Borrows current dirty bounds until the next screen mutation.
    pub fn peekDirtyRows(self: *const Screen) ?DirtyRows {
        return self.dirty_state.rows;
    }

    /// Acknowledges and clears all current dirty publication bounds.
    pub fn clearDirtyRows(self: *Screen) void {
        self.dirty_state.rows = null;
        if (self.dirty_state.cols_start) |buf| @memset(buf, self.cols);
        if (self.dirty_state.cols_end) |buf| @memset(buf, 0);
    }

    /// Read visible cell value by row and column.
    pub fn cellAt(self: *const Screen, row: u16, col: u16) u21 {
        return @intCast(self.cellInfoAt(row, col).codepoint);
    }

    /// Returns a copied visible cell, or the blank default outside the grid.
    pub fn cellInfoAt(self: *const Screen, row: u16, col: u16) Cell {
        const c = self.cells orelse return default_cell;
        if (row >= self.rows or col >= self.cols) return default_cell;
        const start = self.rowStart(row);
        return c[@intCast(start + @as(u32, col))];
    }

    /// Return whether `col` is a configured stop, using default eight-column stops without storage.
    pub fn tabStopAt(self: *const Screen, col: u16) bool {
        if (self.tab_stops) |stops| {
            if (col < stops.len) return stops[col];
        }
        return col != 0 and col % 8 == 0;
    }

    /// Read history cell by recency index and column.
    pub fn historyRowAt(self: *const Screen, history_idx: u32, col: u16) u21 {
        return @intCast(self.historyCellAt(history_idx, col).codepoint);
    }

    /// Returns a copied history cell by recency, or a blank cell out of range.
    pub fn historyCellAt(self: *const Screen, history_idx: u32, col: u16) Cell {
        const h = self.history orelse return default_cell;
        const bounded_idx: u32 = history_idx;
        if (bounded_idx >= self.history_count or col >= self.cols) return default_cell;
        const slot = self.historySlotForRecency(history_idx) orelse return default_cell;
        return h[@intCast(slot * @as(u32, self.cols) + @as(u32, col))];
    }

    /// Return retained history row count.
    pub fn historyCount(self: *const Screen) u32 {
        return self.history_count;
    }

    /// Returns the oldest projected history row identity.
    pub fn historyRowBase(self: *const Screen) u32 {
        return self.history_row_base;
    }

    /// Return configured history capacity.
    pub fn historyCapacity(self: *const Screen) u16 {
        return self.history_capacity;
    }

    /// Report whether selection endpoint should be invalidated.
    pub fn shouldInvalidateSelectionEndpoint(self: *const Screen, endpoint_row: i32) bool {
        if (endpoint_row < 0) return true;
        const oldest_row = self.history_row_base;
        const newest_row_exclusive = oldest_row + self.history_count + self.rows;
        if (@as(u32, @intCast(endpoint_row)) < oldest_row) return true;
        if (@as(u32, @intCast(endpoint_row)) >= newest_row_exclusive) return true;
        return false;
    }

    /// Apply one routed screen mutation request to this Screen.
    pub fn applyScreen(self: *Screen, event: SemanticEvent) void {
        switch (event) {
            .cursor_up,
            .cursor_down,
            .cursor_forward,
            .cursor_back,
            .cursor_next_line,
            .cursor_prev_line,
            .cursor_horizontal_absolute,
            .cursor_vertical_absolute,
            .cursor_position,
            => self.applyCursorMove(event),
            .write_text, .write_codepoint, .repeat_preceding, .sgr => self.applyRetainedState(event),
            .line_feed, .next_line, .reverse_index, .carriage_return, .backspace, .horizontal_tab, .horizontal_tab_forward, .horizontal_tab_back => self.applyFlowMove(event),
            .horizontal_tab_set, .tab_clear_current, .tab_clear_all, .reset_default_tab_stops => self.applyTabState(event),
            .cursor_visible,
            .cursor_style,
            .cursor_shape,
            .cursor_color,
            .cursor_text_color,
            .auto_wrap,
            .origin_mode,
            .insert_mode,
            .character_protection,
            .attr_change_extent_rect,
            .left_right_margin_mode,
            .set_left_right_margins,
            => self.applyScreenState(event),
            .insert_lines, .delete_lines, .insert_chars, .delete_chars, .scroll_up_lines, .scroll_down_lines, .set_scroll_region, .reset_screen => self.applyLineEdit(event),
            .erase_display_below,
            .erase_display_above,
            .erase_display_complete,
            .erase_display_scrollback,
            .erase_display_scroll_complete,
            .erase_line,
            .selective_erase_line,
            .erase_chars,
            .shift_left_columns,
            .shift_right_columns,
            .insert_columns,
            .delete_columns,
            => self.applyGridEdit(event),
            .rect_erase, .rect_selective_erase, .rect_fill, .rect_copy, .rect_attrs_change => self.applyRectEdit(event),
            else => unreachable,
        }
    }

    fn applyCursorMove(self: *Screen, event: SemanticEvent) void {
        self.wrap_pending = false;
        switch (event) {
            .cursor_up => |n| self.cursor.setRowByClient(self.cursor.row -| n),
            .cursor_down => |n| self.cursor.setRowByClient(@min(self.cursor.row +| n, self.rows -| 1)),
            .cursor_forward => |n| self.cursor.setColByClient(@min(self.cursor.col +| n, self.rightBoundary())),
            .cursor_back => |n| self.cursor.setColByClient(@max(self.cursor.col -| n, self.leftBoundary())),
            .cursor_next_line => |n| self.cursor.setPositionByClient(@min(self.cursor.row +| n, self.rows -| 1), self.lineHomeCol()),
            .cursor_prev_line => |n| self.cursor.setPositionByClient(self.cursor.row -| n, self.lineHomeCol()),
            .cursor_horizontal_absolute => |col| self.cursor.setColByClient(@min(self.resolveAbsoluteCol(col), self.rightBoundary())),
            .cursor_vertical_absolute => |row| self.cursor.setRowByClient(@min(row, self.rows -| 1)),
            .cursor_position => |pos| self.cursor.setPositionByClient(@min(self.resolveAbsoluteRow(pos.row), self.rows -| 1), @min(self.resolveAbsoluteCol(pos.col), self.rightBoundary())),
            else => unreachable,
        }
    }

    fn applyRetainedState(self: *Screen, event: SemanticEvent) void {
        switch (event) {
            .write_text => |text| self.writeText(text),
            .write_codepoint => |codepoint| self.writeCell(codepoint),
            .repeat_preceding => |count| self.repeatPreceding(count),
            .sgr => |sgr| self.applySgr(sgr.params, sgr.separators),
            else => unreachable,
        }
    }

    fn applyFlowMove(self: *Screen, event: SemanticEvent) void {
        self.wrap_pending = false;
        switch (event) {
            .line_feed => {
                self.setRowWrapped(self.cursor.row, false);
                self.lineFeed();
            },
            .next_line => {
                self.setRowWrapped(self.cursor.row, false);
                self.cursor.setColByClient(0);
                self.lineFeed();
            },
            .reverse_index => self.reverseIndex(),
            .carriage_return => self.cursor.setColByClient(0),
            .backspace => self.cursor.setColByClient(self.cursor.col -| 1),
            .horizontal_tab => self.horizontalTabForward(1),
            .horizontal_tab_forward => |count| self.horizontalTabForward(count),
            .horizontal_tab_back => |count| self.horizontalTabBack(count),
            else => unreachable,
        }
    }

    fn applyTabState(self: *Screen, event: SemanticEvent) void {
        switch (event) {
            .horizontal_tab_set => self.setTabStop(),
            .tab_clear_current => self.clearCurrentTabStop(),
            .tab_clear_all => self.clearAllTabStops(),
            .reset_default_tab_stops => self.resetDefaultTabStops(),
            else => unreachable,
        }
    }

    fn applyScreenState(self: *Screen, event: SemanticEvent) void {
        switch (event) {
            .cursor_visible => |visible| self.cursor.visible = visible,
            .cursor_style => |cursor_style| switch (cursor_style) {
                .restore_default => self.cursor.restoreDefaultStyle(),
                .program_override => |style| self.cursor.setProgramStyle(style),
            },
            .cursor_shape => |shape| self.cursor.setProgramShape(shape),
            .cursor_color => |value| self.cursor.cursor_color = value,
            .cursor_text_color => |value| self.cursor.cursor_text_color = value,
            .auto_wrap => |enabled| {
                self.auto_wrap = enabled;
                if (!enabled) self.wrap_pending = false;
            },
            .origin_mode => |enabled| {
                self.origin_mode = enabled;
                self.wrap_pending = false;
                self.cursor.setPositionByClient(if (enabled) self.scroll_top else 0, self.lineHomeCol());
            },
            .insert_mode => |enabled| self.insert_mode = enabled,
            .character_protection => |enabled| self.current_attrs.protected = enabled,
            .attr_change_extent_rect => |enabled| self.attr_change_extent_rect = enabled,
            .left_right_margin_mode => |enabled| self.setLeftRightMarginMode(enabled),
            .set_left_right_margins => |margins| self.setLeftRightMargins(margins.left, margins.right),
            else => unreachable,
        }
    }

    fn applyLineEdit(self: *Screen, event: SemanticEvent) void {
        switch (event) {
            .insert_lines => |count| {
                self.wrap_pending = false;
                self.insertLines(count);
            },
            .delete_lines => |count| {
                self.wrap_pending = false;
                self.deleteLines(count);
            },
            .insert_chars => |count| {
                self.wrap_pending = false;
                self.insertChars(count);
            },
            .delete_chars => |count| {
                self.wrap_pending = false;
                self.deleteChars(count);
            },
            .scroll_up_lines => |count| {
                self.wrap_pending = false;
                self.scrollUpRegion(self.scroll_top, self.scrollBottom(), count);
            },
            .scroll_down_lines => |count| {
                self.wrap_pending = false;
                self.scrollDownRegion(self.scroll_top, self.scrollBottom(), count);
            },
            .set_scroll_region => |region| {
                self.wrap_pending = false;
                self.setScrollRegion(region.top, region.bottom);
            },
            .reset_screen => self.reset(),
            else => unreachable,
        }
    }

    fn applyGridEdit(self: *Screen, event: SemanticEvent) void {
        self.wrap_pending = false;
        switch (event) {
            .erase_display_below => |protected| self.eraseDisplay(.cursor_to_end, protected),
            .erase_display_above => |protected| self.eraseDisplay(.start_to_cursor, protected),
            .erase_display_complete => |protected| self.eraseDisplay(.all, protected),
            .erase_display_scrollback => |protected| self.eraseDisplay(.scrollback, protected),
            .erase_display_scroll_complete => |protected| self.eraseDisplay(.all, protected),
            .erase_line => |mode| self.eraseLine(mode),
            .selective_erase_line => |mode| self.selectiveEraseLine(mode),
            .erase_chars => |count| self.eraseChars(count),
            .shift_left_columns => |count| self.shiftColumnsLeft(count),
            .shift_right_columns => |count| self.shiftColumnsRight(count),
            .insert_columns => |count| self.insertColumns(count),
            .delete_columns => |count| self.deleteColumns(count),
            else => unreachable,
        }
    }

    fn applyRectEdit(self: *Screen, event: SemanticEvent) void {
        self.wrap_pending = false;
        switch (event) {
            .rect_erase => |area| self.eraseRect(area, false),
            .rect_selective_erase => |area| self.eraseRect(area, true),
            .rect_fill => |request| self.fillRect(request.area, request.ch),
            .rect_copy => |request| self.copyRect(request),
            .rect_attrs_change => |request| self.changeRectAttrs(request.area, request.attrs.params[0..request.attrs.param_count], request.reverse),
            else => unreachable,
        }
    }

    const RectBounds = struct {
        top: u16,
        left: u16,
        bottom: u16,
        right: u16,
    };

    /// Erase display content according to `mode`, optionally preserving protected cells.
    fn eraseDisplay(self: *Screen, mode: EraseMode, protected: bool) void {
        const cells = self.cells orelse return;
        if (self.rows == 0 or self.cols == 0) return;
        switch (mode) {
            .cursor_to_end => {
                self.markDirtyRows(self.cursor.row, self.rows -| 1);
                self.clearDisplayRowRange(protected, self.cursor.row, self.cursor.col, self.cols);
                var row = self.cursor.row + 1;
                while (row < self.rows) : (row += 1) {
                    self.clearDisplayRowRange(protected, row, 0, self.cols);
                    self.setRowWrapped(row, false);
                }
            },
            .start_to_cursor => {
                self.markDirtyRows(0, self.cursor.row);
                var row: u16 = 0;
                while (row < self.cursor.row) : (row += 1) {
                    self.clearDisplayRowRange(protected, row, 0, self.cols);
                    self.setRowWrapped(row, false);
                }
                self.clearDisplayRowRange(protected, self.cursor.row, 0, self.cursor.col + 1);
            },
            .all => {
                self.markAllRowsDirty();
                if (protected) {
                    var row: u16 = 0;
                    while (row < self.rows) : (row += 1) self.clearDisplayRowRange(true, row, 0, self.cols);
                } else {
                    const erase_cell = self.eraseCell();
                    @memset(cells, erase_cell);
                }
                if (self.row_wraps) |buf| @memset(buf, false);
            },
            .scrollback => self.clearScrollback(),
        }
    }

    fn clearDisplayRowRange(self: *Screen, protected: bool, row: u16, start_col: u16, end_col_exclusive: u16) void {
        if (protected) {
            self.selectiveClearRowRange(row, start_col, end_col_exclusive);
        } else {
            self.clearRowRange(row, start_col, end_col_exclusive);
        }
    }

    /// Sets the hyperlink identity copied into subsequently written cells.
    pub fn setCurrentLinkId(self: *Screen, link_id: u32) void {
        self.current_attrs.link_id = link_id;
    }

    /// Resolve a zero-based row against the active origin region, saturating at its bottom.
    fn resolveAbsoluteRow(self: *const Screen, row: u16) u16 {
        if (!self.origin_mode) return row;
        const bottom = if (self.rows == 0) 0 else @min(self.scroll_bottom, self.rows - 1);
        const region_len = bottom - self.scroll_top;
        return self.scroll_top + @min(row, region_len);
    }

    /// Resolve a zero-based column against active origin-mode horizontal margins.
    fn resolveAbsoluteCol(self: *const Screen, col: u16) u16 {
        if (!(self.origin_mode and self.left_right_margin_mode)) return col;
        const region_len = self.right_margin - self.left_margin;
        return self.left_margin + @min(col, region_len);
    }

    /// Return the line-home column selected by origin and horizontal-margin modes.
    fn lineHomeCol(self: *const Screen) u16 {
        return if (self.origin_mode and self.left_right_margin_mode) self.left_margin else 0;
    }

    /// Clears visible cells and marks the complete screen dirty.
    pub fn clearVisibleCells(self: *Screen) void {
        if (self.cells) |cells| @memset(cells, default_cell);
        if (self.row_wraps) |row_wraps| @memset(row_wraps, false);
        self.markAllRowsDirty();
    }

    /// Moves the alternate-screen cursor to origin and clears pending wrap.
    pub fn resetCursorForAltEntry(self: *Screen) void {
        self.cursor.resetForAltEntry();
        self.wrap_pending = false;
        self.current_attrs = default_cell_attrs;
    }

    /// Return the active horizontal editing boundary on the left.
    fn leftBoundary(self: *const Screen) u16 {
        return if (self.left_right_margin_mode) self.left_margin else 0;
    }

    /// Return the active horizontal editing boundary on the right.
    fn rightBoundary(self: *const Screen) u16 {
        return if (self.left_right_margin_mode) self.right_margin else self.cols -| 1;
    }

    fn clearScrollback(self: *Screen) void {
        const allocator = self.allocator orelse return;
        self.history_row_base += self.history_count;
        self.clearHistoryAuthority(allocator);
        self.history_count = 0;
        self.history_write_idx = 0;
        self.markAllRowsDirty();
    }

    /// Stores one nonzero host cell-pixel fact for terminal protocol reports.
    pub fn setCellPixelSize(self: *Screen, width: u32, height: u32) void {
        std.debug.assert(width > 0);
        std.debug.assert(height > 0);
        self.cell_pixel_size = .{ .width = width, .height = height };
    }

    /// Returns configured nonzero cell pixels, when supplied by the embedding host.
    pub fn cellPixelSize(self: *const Screen) ?CellPixelSize {
        return self.cell_pixel_size;
    }

    /// Erase the active line range selected by `mode`.
    fn eraseLine(self: *Screen, mode: EraseMode) void {
        if (self.cells == null) return;
        if (self.rows == 0 or self.cols == 0) return;
        switch (mode) {
            .cursor_to_end => {
                self.markDirtyCols(self.cursor.row, self.cursor.col, self.cols -| 1);
                self.clearRowRange(self.cursor.row, self.cursor.col, self.cols);
            },
            .start_to_cursor => {
                self.markDirtyCols(self.cursor.row, 0, self.cursor.col);
                self.clearRowRange(self.cursor.row, 0, self.cursor.col + 1);
            },
            .all => {
                self.markDirtyRow(self.cursor.row);
                self.clearRowRange(self.cursor.row, 0, self.cols);
                self.setRowWrapped(self.cursor.row, false);
            },
            .scrollback => {},
        }
    }

    /// Erase at least one character from the cursor through the active right boundary.
    pub fn eraseChars(self: *Screen, count: u16) void {
        if (self.rows == 0 or self.cols == 0) return;
        const amount = @min(@max(count, 1), self.rightBoundary() - self.cursor.col + 1);
        self.markDirtyCols(self.cursor.row, self.cursor.col, self.cursor.col + amount - 1);
        self.clearRowRange(self.cursor.row, self.cursor.col, self.cursor.col + amount);
    }

    /// Change attributes in the clipped rectangle using rectangular or stream extent.
    fn changeRectAttrs(self: *Screen, area: rect.RectArea, attrs: []const u16, reverse: bool) void {
        const cells = self.cells orelse return;
        if (attrs.len == 0) return;
        const bounds = self.rectBounds(area) orelse return;
        self.markDirtyRows(bounds.top, bounds.bottom);
        var row = bounds.top;
        while (row <= bounds.bottom) : (row += 1) {
            const row_start = self.rowStart(row);
            const start_col = if (self.attr_change_extent_rect or row == bounds.top) bounds.left else 0;
            const end_col = if (self.attr_change_extent_rect or row == bounds.bottom) bounds.right else self.cols -| 1;
            var col = start_col;
            while (col <= end_col) : (col += 1) {
                const idx = row_start + @as(u32, col);
                style_mod.applyRectAttrOps(&cells[@intCast(idx)].attrs, attrs, reverse);
            }
        }
    }

    /// Erase unprotected cells on the active line according to `mode`.
    fn selectiveEraseLine(self: *Screen, mode: EraseMode) void {
        if (self.rows == 0 or self.cols == 0) return;
        switch (mode) {
            .cursor_to_end => self.selectiveClearRowRange(self.cursor.row, self.cursor.col, self.cols),
            .start_to_cursor => self.selectiveClearRowRange(self.cursor.row, 0, self.cursor.col + 1),
            .all => {
                self.selectiveClearRowRange(self.cursor.row, 0, self.cols);
                self.setRowWrapped(self.cursor.row, false);
            },
            .scrollback => {},
        }
    }

    /// Erase a clipped rectangle, optionally preserving protected cells.
    fn eraseRect(self: *Screen, area: rect.RectArea, selective: bool) void {
        const bounds = self.rectBounds(area) orelse return;
        self.markDirtyRows(bounds.top, bounds.bottom);
        var row = bounds.top;
        while (row <= bounds.bottom) : (row += 1) {
            if (selective) {
                self.selectiveClearRowRange(row, bounds.left, bounds.right + 1);
            } else {
                self.clearRowRange(row, bounds.left, bounds.right + 1);
            }
            if (bounds.left == 0 and bounds.right + 1 == self.cols) self.setRowWrapped(row, false);
        }
    }

    /// Fill a clipped rectangle with `codepoint` and the current write attributes.
    fn fillRect(self: *Screen, area: rect.RectArea, codepoint: u21) void {
        const cells = self.cells orelse return;
        const bounds = self.rectBounds(area) orelse return;
        self.markDirtyRows(bounds.top, bounds.bottom);
        var row = bounds.top;
        while (row <= bounds.bottom) : (row += 1) {
            const start = self.rowStart(row);
            var col = bounds.left;
            while (col <= bounds.right) : (col += 1) {
                cells[start + col] = .{ .codepoint = codepoint, .attrs = self.current_attrs };
            }
        }
    }

    /// Copy one clipped page-one rectangle in overlap-safe row and column order.
    ///
    /// Unsupported pages and missing storage leave the destination unchanged.
    fn copyRect(self: *Screen, request: rect.RectCopy) void {
        const cells = self.cells orelse return;
        if (request.source_page != 1 or request.dest_page != 1) return;
        const source = self.rectBounds(request.area) orelse return;
        const row_base: u16 = if (self.origin_mode) self.scroll_top else 0;
        const row_limit: u16 = if (self.origin_mode) self.scrollBottom() else self.rows -| 1;
        const dest_top = row_base + @min(request.dest_top, row_limit -| row_base);
        const dest_left = @min(request.dest_left, self.cols -| 1);
        const height: u16 = source.bottom - source.top + 1;
        const width: u16 = source.right - source.left + 1;
        if (dest_top >= self.rows or dest_left >= self.cols) return;
        const copy_height = @min(height, self.rows - dest_top);
        const copy_width = @min(width, self.cols - dest_left);
        if (copy_height == 0 or copy_width == 0) return;

        self.markDirtyRows(dest_top, dest_top + copy_height - 1);
        var copied_rows: u16 = 0;
        while (copied_rows < copy_height) : (copied_rows += 1) {
            const row = if (dest_top > source.top) copy_height - copied_rows - 1 else copied_rows;
            const source_start = self.rowStart(source.top + row) + source.left;
            const dest_start = self.rowStart(dest_top + row) + dest_left;
            const source_cells = cells[@intCast(source_start)..@intCast(source_start + copy_width)];
            const dest_cells = cells[@intCast(dest_start)..@intCast(dest_start + copy_width)];
            if (dest_start > source_start) {
                std.mem.copyBackwards(Cell, dest_cells, source_cells);
            } else {
                std.mem.copyForwards(Cell, dest_cells, source_cells);
            }
        }
    }

    /// Insert columns at the cursor across the active vertical scroll region.
    fn insertColumns(self: *Screen, count: u16) void {
        const bottom = self.scrollBottom();
        if (self.cursor.col >= self.cols or self.scroll_top > bottom) return;
        var row = self.scroll_top;
        while (row <= bottom) : (row += 1) self.insertColumnsInRow(row, count);
    }

    /// Delete columns at the cursor across the active vertical scroll region.
    fn deleteColumns(self: *Screen, count: u16) void {
        const bottom = self.scrollBottom();
        if (self.cursor.col >= self.cols or self.scroll_top > bottom) return;
        var row = self.scroll_top;
        while (row <= bottom) : (row += 1) self.deleteColumnsInRow(row, count);
    }

    /// Shift active scroll-region rows left within current horizontal boundaries.
    fn shiftColumnsLeft(self: *Screen, count: u16) void {
        const bottom = self.scrollBottom();
        if (self.cols == 0 or self.scroll_top > bottom) return;
        var row = self.scroll_top;
        while (row <= bottom) : (row += 1) self.shiftRowLeft(row, count);
    }

    /// Shift active scroll-region rows right within current horizontal boundaries.
    fn shiftColumnsRight(self: *Screen, count: u16) void {
        const bottom = self.scrollBottom();
        if (self.cols == 0 or self.scroll_top > bottom) return;
        var row = self.scroll_top;
        while (row <= bottom) : (row += 1) self.shiftRowRight(row, count);
    }

    /// Insert at least one erase cell at the cursor within the right boundary.
    pub fn insertChars(self: *Screen, count: u16) void {
        if (self.rows == 0 or self.cols == 0) return;
        if (self.cursor.col >= self.cols) return;

        const amount = @min(@max(count, 1), self.rightBoundary() - self.cursor.col + 1);
        const row = self.rowCells(self.cursor.row) orelse return;
        const src_col = colCount(self.cursor.col);
        const dst_col = src_col + colCount(amount);
        const move_len = colCount(self.rightBoundary() + 1) - dst_col;

        std.debug.assert(src_col <= dst_col);
        std.debug.assert(dst_col <= colCount(self.rightBoundary() + 1));
        std.debug.assert(dst_col + move_len == colCount(self.rightBoundary() + 1));
        std.debug.assert(src_col + move_len <= row.len);
        std.debug.assert(dst_col + move_len <= row.len);
        std.debug.assert(src_col + colCount(amount) <= row.len);

        self.markDirtyCols(self.cursor.row, self.cursor.col, self.rightBoundary());
        if (move_len > 0) {
            std.mem.copyBackwards(Cell, row[@intCast(dst_col)..@intCast(dst_col + move_len)], row[@intCast(src_col)..@intCast(src_col + move_len)]);
        }
        @memset(row[@intCast(src_col)..@intCast(src_col + colCount(amount))], self.eraseCell());
        self.setRowWrapped(self.cursor.row, false);
    }

    /// Delete at least one cell at the cursor within the right boundary.
    pub fn deleteChars(self: *Screen, count: u16) void {
        if (self.rows == 0 or self.cols == 0) return;
        if (self.cursor.col >= self.cols) return;

        const amount = @min(@max(count, 1), self.rightBoundary() - self.cursor.col + 1);
        const row = self.rowCells(self.cursor.row) orelse return;
        const dst_col = colCount(self.cursor.col);
        const src_col = @min(dst_col + colCount(amount), colCount(self.rightBoundary() + 1));
        const move_len = colCount(self.rightBoundary() + 1) - src_col;
        const tail_start = colCount(self.rightBoundary() + 1) - colCount(amount);
        const tail_end = colCount(self.rightBoundary() + 1);

        std.debug.assert(dst_col <= src_col);
        std.debug.assert(src_col <= tail_end);
        std.debug.assert(src_col + move_len == tail_end);
        std.debug.assert(dst_col + move_len <= row.len);
        std.debug.assert(src_col + move_len <= row.len);
        std.debug.assert(tail_start <= tail_end);
        std.debug.assert(tail_end <= row.len);

        self.markDirtyCols(self.cursor.row, self.cursor.col, self.rightBoundary());
        if (move_len > 0) {
            std.mem.copyForwards(Cell, row[@intCast(dst_col)..@intCast(dst_col + move_len)], row[@intCast(src_col)..@intCast(src_col + move_len)]);
        }
        @memset(row[@intCast(tail_start)..@intCast(tail_end)], self.eraseCell());
        self.setRowWrapped(self.cursor.row, false);
    }

    fn insertColumnsInRow(self: *Screen, row: u16, count: u16) void {
        const amount = @min(@max(count, 1), self.cols - self.cursor.col);
        const cells = self.rowCells(row) orelse return;
        const cursor_col = colCount(self.cursor.col);
        const dst_col = cursor_col + colCount(amount);
        const move_len = colCount(self.cols) - dst_col;

        std.debug.assert(cursor_col <= dst_col);
        std.debug.assert(dst_col <= colCount(self.cols));
        std.debug.assert(dst_col + move_len == colCount(self.cols));
        std.debug.assert(cursor_col + move_len <= cells.len);
        std.debug.assert(dst_col + move_len <= cells.len);
        std.debug.assert(cursor_col + colCount(amount) <= cells.len);

        self.markDirtyCols(row, self.cursor.col, self.cols -| 1);
        if (move_len > 0) std.mem.copyBackwards(Cell, cells[@intCast(dst_col)..@intCast(dst_col + move_len)], cells[@intCast(cursor_col)..@intCast(cursor_col + move_len)]);
        @memset(cells[@intCast(cursor_col)..@intCast(cursor_col + colCount(amount))], self.eraseCell());
        self.setRowWrapped(row, false);
    }

    fn deleteColumnsInRow(self: *Screen, row: u16, count: u16) void {
        const amount = @min(@max(count, 1), self.cols - self.cursor.col);
        const cells = self.rowCells(row) orelse return;
        const cursor_col = colCount(self.cursor.col);
        const src_col = @min(cursor_col + colCount(amount), colCount(self.cols));
        const move_len = colCount(self.cols) - src_col;

        std.debug.assert(cursor_col <= src_col);
        std.debug.assert(src_col <= colCount(self.cols));
        std.debug.assert(src_col + move_len == colCount(self.cols));
        std.debug.assert(cursor_col + move_len <= cells.len);
        std.debug.assert(src_col + move_len <= cells.len);
        std.debug.assert(colCount(self.cols) - colCount(amount) <= colCount(self.cols));

        self.markDirtyCols(row, self.cursor.col, self.cols -| 1);
        if (move_len > 0) std.mem.copyForwards(Cell, cells[@intCast(cursor_col)..@intCast(cursor_col + move_len)], cells[@intCast(src_col)..@intCast(src_col + move_len)]);
        @memset(cells[@intCast(colCount(self.cols) - colCount(amount))..@intCast(colCount(self.cols))], self.eraseCell());
        self.setRowWrapped(row, false);
    }

    fn shiftRowLeft(self: *Screen, row: u16, count: u16) void {
        const left = if (self.left_right_margin_mode) self.left_margin else 0;
        const right = if (self.left_right_margin_mode) self.right_margin else self.cols -| 1;
        if (left > right or right >= self.cols) return;

        const width = right - left + 1;
        const amount = @min(@max(count, 1), width);
        const cells = self.rowCells(row) orelse return;
        const left_idx = colCount(left);
        const move_len = colCount(width - amount);

        std.debug.assert(width > 0);
        std.debug.assert(amount <= width);
        std.debug.assert(right + 1 <= self.cols);
        std.debug.assert(left_idx + colCount(width) <= cells.len);
        std.debug.assert(left_idx + colCount(amount) + move_len <= cells.len);
        std.debug.assert(left_idx + move_len <= left_idx + colCount(width));

        self.markDirtyCols(row, left, right);
        if (move_len > 0) {
            std.mem.copyForwards(
                Cell,
                cells[@intCast(left_idx)..@intCast(left_idx + move_len)],
                cells[@intCast(left_idx + colCount(amount))..@intCast(left_idx + colCount(amount) + move_len)],
            );
        }
        @memset(cells[@intCast(left_idx + move_len)..@intCast(left_idx + colCount(width))], self.eraseCell());
        self.setRowWrapped(row, false);
    }

    fn shiftRowRight(self: *Screen, row: u16, count: u16) void {
        const left = if (self.left_right_margin_mode) self.left_margin else 0;
        const right = if (self.left_right_margin_mode) self.right_margin else self.cols -| 1;
        if (left > right or right >= self.cols) return;

        const width = right - left + 1;
        const amount = @min(@max(count, 1), width);
        const cells = self.rowCells(row) orelse return;
        const left_idx = colCount(left);
        const move_len = colCount(width - amount);

        std.debug.assert(width > 0);
        std.debug.assert(amount <= width);
        std.debug.assert(right + 1 <= self.cols);
        std.debug.assert(left_idx + colCount(width) <= cells.len);
        std.debug.assert(left_idx + colCount(amount) + move_len <= cells.len);
        std.debug.assert(left_idx + colCount(amount) <= left_idx + colCount(width));

        self.markDirtyCols(row, left, right);
        if (move_len > 0) {
            std.mem.copyBackwards(
                Cell,
                cells[@intCast(left_idx + colCount(amount))..@intCast(left_idx + colCount(amount) + move_len)],
                cells[@intCast(left_idx)..@intCast(left_idx + move_len)],
            );
        }
        @memset(cells[@intCast(left_idx)..@intCast(left_idx + colCount(amount))], self.eraseCell());
        self.setRowWrapped(row, false);
    }

    fn rowCells(self: *Screen, row: u16) ?[]Cell {
        const cells = self.cells orelse return null;
        const start = self.rowStart(row);
        std.debug.assert(row < self.rows);
        std.debug.assert(start + colCount(self.cols) <= cells.len);
        return cells[@intCast(start)..@intCast(start + colCount(self.cols))];
    }

    /// Write one byte per cell through the terminal's graphic write path.
    pub fn writeText(self: *Screen, text: []const u8) void {
        for (text) |byte| self.writeCell(@intCast(byte));
    }

    /// Repeat the last graphic codepoint up to `count` times.
    fn repeatPreceding(self: *Screen, count: u16) void {
        if (self.last_graphic_codepoint) |cp| {
            var remaining = count;
            while (remaining > 0) : (remaining -= 1) self.writeCell(cp);
        }
    }

    /// Write one codepoint with combining, insertion, wrapping, dirty, and cursor semantics.
    fn writeCell(self: *Screen, cp: u21) void {
        if (self.cols == 0 or self.rows == 0) return;
        if (self.appendCombiningToLeadCell(cp)) return;

        const right = self.rightBoundary();
        if (self.wrap_pending) {
            self.wrap_pending = false;
            if (self.cursor.col == right) {
                self.setRowWrapped(self.cursor.row, true);
                self.lineFeed();
                self.cursor.setColByClient(if (self.left_right_margin_mode) self.left_margin else 0);
            }
        }
        if (self.insert_mode) self.insertChars(1);
        if (self.cells) |cells| {
            const start = self.rowStart(self.cursor.row);
            self.markDirtyCols(self.cursor.row, self.cursor.col, self.cursor.col);
            cells[@intCast(start + @as(u32, self.cursor.col))] = .{
                .codepoint = cp,
                .attrs = self.current_attrs,
            };
        }
        self.last_graphic_codepoint = cp;
        if (self.cursor.col < right) {
            self.cursor.setColByClient(self.cursor.col + 1);
        } else if (self.auto_wrap) {
            self.wrap_pending = true;
        }
    }

    fn appendCombiningToLeadCell(self: *Screen, cp: u21) bool {
        if (!isTrailingCombiningCodepoint(cp)) return false;

        const pos = self.previousLeadCellPos() orelse return false;
        const cells = self.cells orelse return false;
        const idx = self.rowStart(pos.row) + @as(u32, pos.col);
        const lead_cell = &cells[@intCast(idx)];
        if (lead_cell.codepoint == 0) return false;
        if (lead_cell.combining_len >= lead_cell.combining.len) return true;

        lead_cell.combining[lead_cell.combining_len] = cp;
        lead_cell.combining_len += 1;
        self.markDirtyCols(pos.row, pos.col, pos.col);
        return true;
    }

    fn previousLeadCellPos(self: *const Screen) ?struct { row: u16, col: u16 } {
        const right = self.rightBoundary();
        if (self.wrap_pending) return .{ .row = self.cursor.row, .col = right };

        if (self.cursor.col == 0) return null;
        return .{ .row = self.cursor.row, .col = self.cursor.col - 1 };
    }

    /// Apply SGR parameters to the retained attributes used by subsequent writes.
    pub fn applySgr(self: *Screen, params: []const i32, separators: parser_mod.CsiSeparatorList) void {
        if (params.len == 0) {
            self.current_attrs = default_cell_attrs;
            return;
        }

        std.debug.assert(params.len <= std.math.maxInt(u8));
        const param_len: u8 = @intCast(params.len);
        var idx: u8 = 0;
        while (idx < param_len) : (idx += 1) {
            const param = params[idxOf(idx)];
            switch (param) {
                4 => self.applyUnderlineStyle(params, separators, &idx),
                38 => self.applyExtendedColor(params, &idx, true),
                48 => self.applyExtendedColor(params, &idx, false),
                58 => self.applyUnderlineColor(params, &idx),
                else => self.applyBasicSgr(param),
            }
        }
    }

    fn applyBasicSgr(self: *Screen, param: i32) void {
        switch (param) {
            0 => self.current_attrs = default_cell_attrs,
            1 => self.current_attrs.bold = true,
            2 => self.current_attrs.dim = true,
            3 => self.current_attrs.italic = true,
            5, 6 => self.current_attrs.blink = true,
            7 => self.current_attrs.reverse = true,
            8 => self.current_attrs.invisible = true,
            9 => self.current_attrs.strikethrough = true,
            22 => {
                self.current_attrs.bold = false;
                self.current_attrs.dim = false;
            },
            23 => self.current_attrs.italic = false,
            24 => self.clearUnderline(),
            25 => self.clearBlink(),
            27 => self.current_attrs.reverse = false,
            28 => self.current_attrs.invisible = false,
            29 => self.current_attrs.strikethrough = false,
            30...37 => self.current_attrs.fg = ansi16Color(@intCast(param - 30)),
            39 => self.current_attrs.fg = default_cell_attrs.fg,
            40...47 => self.current_attrs.bg = ansi16Color(@intCast(param - 40)),
            49 => self.current_attrs.bg = default_cell_attrs.bg,
            59 => self.current_attrs.underline_color = default_underline_color,
            90...97 => self.current_attrs.fg = ansi16Color(@intCast((param - 90) + 8)),
            100...107 => self.current_attrs.bg = ansi16Color(@intCast((param - 100) + 8)),
            else => {},
        }
    }

    fn applyUnderlineStyle(self: *Screen, params: []const i32, separators: parser_mod.CsiSeparatorList, idx: *u8) void {
        const next = idx.* + 1;
        if (next < params.len and separators.isSet(idx.*)) {
            self.setUnderlineStyle(params[idxOf(next)]);
            idx.* += 1;
            return;
        }
        self.current_attrs.underline = true;
        self.current_attrs.underline_style = .straight;
    }

    fn setUnderlineStyle(self: *Screen, value: i32) void {
        switch (value) {
            0 => self.clearUnderline(),
            1 => self.setUnderline(.straight),
            2 => self.setUnderline(.double),
            3 => self.setUnderline(.curly),
            4 => self.setUnderline(.dotted),
            5 => self.setUnderline(.dashed),
            else => {},
        }
    }

    fn setUnderline(self: *Screen, underline_style: UnderlineStyle) void {
        self.current_attrs.underline = true;
        self.current_attrs.underline_style = underline_style;
    }

    fn clearUnderline(self: *Screen) void {
        self.current_attrs.underline = false;
        self.current_attrs.underline_style = .straight;
    }

    fn clearBlink(self: *Screen) void {
        self.current_attrs.blink = false;
        self.current_attrs.blink_fast = false;
    }

    fn applyExtendedColor(self: *Screen, params: []const i32, idx: *u8, is_fg: bool) void {
        const sgr_color = decodeExtendedColor(params, idx) orelse return;
        if (is_fg) self.current_attrs.fg = sgr_color else self.current_attrs.bg = sgr_color;
    }

    fn applyUnderlineColor(self: *Screen, params: []const i32, idx: *u8) void {
        const sgr_color = decodeExtendedColor(params, idx) orelse return;
        self.current_attrs.underline_color = sgr_color;
    }

    /// Move forward through at most `count` tab stops, clamping at the last column.
    fn horizontalTabForward(self: *Screen, count: u16) void {
        if (self.cols == 0) return;
        var remaining = count;
        while (remaining > 0) : (remaining -= 1) {
            if (self.cursor.col >= self.cols - 1) break;
            var col = self.cursor.col + 1;
            while (col < self.cols and !self.tabStopAt(col)) : (col += 1) {}
            self.cursor.setColByClient(if (col < self.cols) col else self.cols - 1);
        }
    }

    /// Move backward through at most `count` tab stops, clamping at column zero.
    fn horizontalTabBack(self: *Screen, count: u16) void {
        var remaining = count;
        while (remaining > 0) : (remaining -= 1) {
            if (self.cursor.col == 0) break;
            var col = self.cursor.col - 1;
            while (col > 0 and !self.tabStopAt(col)) : (col -= 1) {}
            self.cursor.setColByClient(if (self.tabStopAt(col)) col else 0);
        }
    }

    /// Set a stored tab stop at the current in-bounds cursor column.
    fn setTabStop(self: *Screen) void {
        if (self.tab_stops) |stops| {
            if (self.cursor.col < stops.len) stops[self.cursor.col] = true;
        }
    }

    /// Clear a stored tab stop at the current in-bounds cursor column.
    fn clearCurrentTabStop(self: *Screen) void {
        if (self.tab_stops) |stops| {
            if (self.cursor.col < stops.len) stops[self.cursor.col] = false;
        }
    }

    /// Clear every stored tab stop.
    fn clearAllTabStops(self: *Screen) void {
        if (self.tab_stops) |stops| @memset(stops, false);
    }

    /// Restore default eight-column stops in the stored tab-stop buffer.
    fn resetDefaultTabStops(self: *Screen) void {
        if (self.tab_stops) |stops| tabs.setDefaultTabStops(stops);
    }

    /// Advance within the scroll region, scrolling it upward at its bottom edge.
    fn lineFeed(self: *Screen) void {
        if (self.rows == 0) return;
        const bottom = self.scrollBottom();
        if (self.cursor.row < bottom) {
            self.cursor.setRowByClient(self.cursor.row + 1);
            return;
        }
        if (self.cursor.row == bottom) {
            self.scrollUpRegion(self.scroll_top, bottom, 1);
            return;
        }
        if (self.cursor.row < self.rows - 1) self.cursor.setRowByClient(self.cursor.row + 1);
    }

    /// Move upward, scrolling the active region downward at its top edge.
    fn reverseIndex(self: *Screen) void {
        if (self.rows == 0) return;
        if (self.cursor.row == self.scroll_top) {
            self.scrollDownRegion(self.scroll_top, self.scrollBottom(), 1);
        } else {
            self.cursor.setRowByClient(self.cursor.row -| 1);
        }
    }

    fn scrollUp(self: *Screen) void {
        const cells = self.cells orelse return;
        if (self.rows == 0 or self.cols == 0) return;
        self.markDirtyRow(self.rows - 1);
        const row_len = @as(u32, self.cols);
        self.storeHistoryRow(0);
        self.row_origin = (self.row_origin + 1) % self.rows;
        const bottom_start = self.rowStart(self.rows - 1);
        @memset(cells[@intCast(bottom_start)..@intCast(bottom_start + row_len)], default_cell);
        self.setRowWrapped(self.rows - 1, false);
    }

    fn scrollBottom(self: *const Screen) u16 {
        return if (self.rows == 0) 0 else @min(self.scroll_bottom, self.rows - 1);
    }

    /// Set the vertical scrolling region when its clamped endpoints remain ordered.
    fn setScrollRegion(self: *Screen, top: u16, bottom: ?u16) void {
        if (self.rows == 0) {
            self.scroll_top = 0;
            self.scroll_bottom = 0;
            self.cursor.setPositionByClient(0, 0);
            return;
        }

        const new_top = @min(top, self.rows - 1);
        const new_bottom = if (bottom) |value| @min(value, self.rows - 1) else self.rows - 1;
        if (new_top >= new_bottom) return;

        self.scroll_top = new_top;
        self.scroll_bottom = new_bottom;
        self.cursor.setPositionByClient(if (self.origin_mode) self.scroll_top else 0, self.lineHomeCol());
    }

    /// Enable horizontal margins, or disable them and restore full-width defaults.
    fn setLeftRightMarginMode(self: *Screen, enabled: bool) void {
        self.left_right_margin_mode = enabled;
        if (!enabled) {
            self.left_margin = 0;
            self.right_margin = self.cols -| 1;
        }
    }

    /// Set ordered horizontal margins and home the cursor after a valid change.
    fn setLeftRightMargins(self: *Screen, left: u16, right: ?u16) void {
        if (!self.left_right_margin_mode or self.cols < 2) return;
        const new_left = @min(left, self.cols - 2);
        const new_right = if (right) |value| @min(value, self.cols - 1) else self.cols - 1;
        if (new_left >= new_right) return;
        self.left_margin = new_left;
        self.right_margin = new_right;
        self.wrap_pending = false;
        self.cursor.setPositionByClient(if (self.origin_mode) self.scroll_top else 0, self.lineHomeCol());
    }

    /// Insert lines at the cursor within the active vertical scroll region.
    fn insertLines(self: *Screen, count: u16) void {
        const bottom = self.scrollBottom();
        if (self.cursor.row < self.scroll_top or self.cursor.row > bottom) return;
        self.scrollDownRegion(self.cursor.row, bottom, count);
    }

    /// Delete lines at the cursor within the active vertical scroll region.
    fn deleteLines(self: *Screen, count: u16) void {
        const bottom = self.scrollBottom();
        if (self.cursor.row < self.scroll_top or self.cursor.row > bottom) return;
        self.scrollUpRegion(self.cursor.row, bottom, count);
    }

    /// Scroll an ordered, clamped region upward by at most its row count.
    fn scrollUpRegion(self: *Screen, top: u16, bottom: u16, count: u16) void {
        if (self.rows == 0 or self.cols == 0 or top >= self.rows or top > bottom) return;
        const bounded_bottom = @min(bottom, self.rows - 1);
        const region_len: u16 = bounded_bottom - top + 1;
        const amount = @min(count, region_len);
        if (amount == 0) return;

        if (top == 0 and bounded_bottom == self.rows - 1) {
            var remaining = amount;
            while (remaining > 0) : (remaining -= 1) self.scrollUp();
            return;
        }

        self.markDirtyRows(top, bounded_bottom);
        const left = if (self.left_right_margin_mode) self.left_margin else 0;
        const right = if (self.left_right_margin_mode) self.right_margin else self.cols -| 1;

        var dst = top;
        while (dst + amount <= bounded_bottom) : (dst += 1) {
            self.copyRowRange(dst, dst + amount, left, right + 1);
        }

        var clear_row = bounded_bottom - amount + 1;
        while (clear_row <= bounded_bottom) : (clear_row += 1) {
            self.clearRowRange(clear_row, left, right + 1);
            self.setRowWrapped(clear_row, false);
        }
    }

    /// Scroll an ordered, clamped region downward by at most its row count.
    fn scrollDownRegion(self: *Screen, top: u16, bottom: u16, count: u16) void {
        if (self.rows == 0 or self.cols == 0 or top >= self.rows or top > bottom) return;
        const bounded_bottom = @min(bottom, self.rows - 1);
        const region_len: u16 = bounded_bottom - top + 1;
        const amount = @min(count, region_len);
        if (amount == 0) return;

        self.markDirtyRows(top, bounded_bottom);
        const left = if (self.left_right_margin_mode) self.left_margin else 0;
        const right = if (self.left_right_margin_mode) self.right_margin else self.cols -| 1;

        var dst = bounded_bottom;
        while (dst >= top + amount) {
            self.copyRowRange(dst, dst - amount, left, right + 1);
            if (dst == top + amount) break;
            dst -= 1;
        }

        var clear_row = top;
        while (clear_row < top + amount) : (clear_row += 1) {
            self.clearRowRange(clear_row, left, right + 1);
            self.setRowWrapped(clear_row, false);
        }
    }

    fn rowStart(self: *const Screen, logical_row: u16) u32 {
        if (self.rows == 0) return 0;
        const physical_row = (self.row_origin + logical_row) % self.rows;
        return @as(u32, physical_row) * @as(u32, self.cols);
    }

    fn rowWrapIndex(self: *const Screen, logical_row: u16) ?u16 {
        if (self.row_wraps == null) return null;
        if (self.rows == 0 or logical_row >= self.rows) return null;
        return (self.row_origin + logical_row) % self.rows;
    }

    /// Reports whether a visible row continues into the next row.
    pub fn rowWrapped(self: *const Screen, logical_row: u16) bool {
        const wraps = self.row_wraps orelse return false;
        const idx = self.rowWrapIndex(logical_row) orelse return false;
        return wraps[@intCast(idx)];
    }

    fn setRowWrapped(self: *Screen, logical_row: u16, wrapped: bool) void {
        const wraps = self.row_wraps orelse return;
        const idx = self.rowWrapIndex(logical_row) orelse return;
        wraps[@intCast(idx)] = wrapped;
    }

    /// Return a value view whose cells borrow the retained logical history line.
    fn historyLineAt(self: *const Screen, logical_index: u32) HistoryLine {
        std.debug.assert(logical_index < self.historyLineCount());
        const slot = (self.history_lines_start + logical_index) % self.historyLineCount();
        return self.history_lines.items[@intCast(slot)];
    }

    /// Resolve an oldest-first projected history row to its physical ring slot.
    fn historySlotForLogicalRow(self: *const Screen, logical_row: u32) ?u32 {
        const capacity = self.projectedCapacity();
        if (logical_row >= self.history_count or capacity == 0) return null;
        return (self.history_write_idx + logical_row) % capacity;
    }

    /// Resolve a newest-first projected history row to its physical ring slot.
    fn historySlotForRecency(self: *const Screen, history_idx: u32) ?u32 {
        if (history_idx >= self.history_count) return null;
        return self.historySlotForLogicalRow(self.history_count - 1 - history_idx);
    }

    /// Return whether a newest-first projected history row continues logically.
    fn historyRowWrapped(self: *const Screen, history_idx: u32) bool {
        const wraps = self.history_wraps orelse return false;
        const slot = self.historySlotForRecency(history_idx) orelse return false;
        return wraps[@intCast(slot)];
    }

    /// Return the physical ring slot for the next projected history row.
    fn projectedAppendSlot(self: *const Screen) u32 {
        const capacity = self.projectedCapacity();
        if (capacity == 0) return 0;
        return (self.history_write_idx + self.history_count) % capacity;
    }

    /// Return allocated projected-history row capacity.
    fn projectedCapacity(self: *const Screen) u32 {
        const wraps = self.history_wraps orelse return 0;
        std.debug.assert(wraps.len <= std.math.maxInt(u32));
        return @intCast(wraps.len);
    }

    /// Return projected row count for `cells` at the current column width.
    fn projectedRowCountForCells(self: *const Screen, cells: []const Cell) u32 {
        return history_mod.rowCountForCells(history_mod.count32(cells.len), self.cols);
    }

    /// Return retained logical history-line count.
    fn historyLineCount(self: *const Screen) u32 {
        std.debug.assert(self.history_lines.items.len <= std.math.maxInt(u32));
        return @intCast(self.history_lines.items.len);
    }

    /// Fill an assumed in-bounds row range with the current erase cell.
    fn clearRowRange(self: *Screen, row: u16, start_col: u16, end_col_exclusive: u16) void {
        const cells = self.cells orelse return;
        const start = self.rowStart(row);
        const erase_cell = self.eraseCell();
        @memset(cells[@intCast(start + @as(u32, start_col))..@intCast(start + @as(u32, end_col_exclusive))], erase_cell);
    }

    /// Fill unprotected cells in an assumed in-bounds row range with the erase cell.
    fn selectiveClearRowRange(self: *Screen, row: u16, start_col: u16, end_col_exclusive: u16) void {
        const cells = self.cells orelse return;
        const start = self.rowStart(row);
        const erase_cell = self.eraseCell();
        var col = start_col;
        while (col < end_col_exclusive) : (col += 1) {
            const idx = start + @as(u32, col);
            if (cells[@intCast(idx)].attrs.protected) continue;
            cells[@intCast(idx)] = erase_cell;
        }
    }

    /// Clamps a protocol rectangle to this screen, returning null when empty.
    pub fn rectBounds(self: *const Screen, area: rect.RectArea) ?RectBounds {
        if (self.rows == 0 or self.cols == 0) return null;
        const row_base: u16 = if (self.origin_mode) self.scroll_top else 0;
        const row_limit: u16 = if (self.origin_mode) self.scrollBottom() else self.rows - 1;
        const row_span = row_limit -| row_base;
        const top = row_base + @min(area.top, row_span);
        const bottom = row_base + @min(area.bottom orelse row_span, row_span);
        const left = @min(area.left, self.cols - 1);
        const right = @min(area.right orelse self.cols - 1, self.cols - 1);
        if (top > bottom or left > right) return null;
        return .{ .top = top, .left = left, .bottom = bottom, .right = right };
    }

    /// Construct an empty cell carrying the current erase attributes.
    fn eraseCell(self: *const Screen) Cell {
        return .{ .codepoint = 0, .attrs = self.current_attrs };
    }

    fn clearFullRow(self: *Screen, row: u16) void {
        if (self.cols == 0) return;
        self.clearRowRange(row, 0, self.cols);
        self.setRowWrapped(row, false);
    }

    fn copyRow(self: *Screen, dst_row: u16, src_row: u16) void {
        const c = self.cells orelse return;
        const row_len = @as(u32, self.cols);
        const dst_start = self.rowStart(dst_row);
        const src_start = self.rowStart(src_row);
        std.mem.copyForwards(Cell, c[@intCast(dst_start)..@intCast(dst_start + row_len)], c[@intCast(src_start)..@intCast(src_start + row_len)]);
        self.setRowWrapped(dst_row, self.rowWrapped(src_row));
    }

    fn copyRowRange(self: *Screen, dst_row: u16, src_row: u16, start_col: u16, end_col_exclusive: u16) void {
        const c = self.cells orelse return;
        const dst_start = self.rowStart(dst_row);
        const src_start = self.rowStart(src_row);
        const start_col32 = @as(u32, start_col);
        const end_col32 = @as(u32, end_col_exclusive);
        std.mem.copyForwards(Cell, c[@intCast(dst_start + start_col32)..@intCast(dst_start + end_col32)], c[@intCast(src_start + start_col32)..@intCast(src_start + end_col32)]);
        self.setRowWrapped(dst_row, false);
    }

    /// Mark one in-bounds row dirty across its full visible width.
    fn markDirtyRow(self: *Screen, row: u16) void {
        if (self.rows == 0 or row >= self.rows) return;
        self.markDirtyCols(row, 0, self.cols -| 1);
    }

    /// Union an ordered, clamped column range into one row's dirty state.
    pub fn markDirtyCols(self: *Screen, row: u16, start_col: u16, end_col: u16) void {
        if (self.rows == 0 or self.cols == 0 or row >= self.rows) return;
        const start = @min(start_col, self.cols -| 1);
        const end = @min(end_col, self.cols -| 1);
        const lo = @min(start, end);
        const hi = @max(start, end);
        if (self.dirty_state.rows) |*d| {
            d.start_row = @min(d.start_row, row);
            d.end_row = @max(d.end_row, row);
            d.dirty_cols_start = self.dirty_state.cols_start orelse &.{};
            d.dirty_cols_end = self.dirty_state.cols_end orelse &.{};
        } else {
            self.dirty_state.rows = .{
                .start_row = row,
                .end_row = row,
                .dirty_cols_start = self.dirty_state.cols_start orelse &.{},
                .dirty_cols_end = self.dirty_state.cols_end orelse &.{},
            };
        }
        if (self.dirty_state.cols_start) |cols_start| {
            cols_start[row] = @min(cols_start[row], lo);
        }
        if (self.dirty_state.cols_end) |cols_end| {
            cols_end[row] = @max(cols_end[row], hi);
        }
    }

    /// Mark a clamped row range fully dirty and union it with prior dirty rows.
    pub fn markDirtyRows(self: *Screen, start_row: u16, end_row: u16) void {
        if (self.rows == 0) return;
        const start = @min(start_row, self.rows -| 1);
        const end = @min(end_row, self.rows -| 1);
        if (self.dirty_state.cols_start) |cols_start| {
            var row = start;
            while (row <= end) : (row += 1) cols_start[row] = 0;
        }
        if (self.dirty_state.cols_end) |cols_end| {
            var row = start;
            while (row <= end) : (row += 1) cols_end[row] = self.cols -| 1;
        }
        if (self.dirty_state.rows) |*d| {
            d.start_row = @min(d.start_row, start);
            d.end_row = @max(d.end_row, end);
            d.dirty_cols_start = self.dirty_state.cols_start orelse &.{};
            d.dirty_cols_end = self.dirty_state.cols_end orelse &.{};
        } else {
            self.dirty_state.rows = .{
                .start_row = start,
                .end_row = end,
                .dirty_cols_start = self.dirty_state.cols_start orelse &.{},
                .dirty_cols_end = self.dirty_state.cols_end orelse &.{},
            };
        }
    }

    /// Mark every row and column dirty while refreshing borrowed column slices.
    pub fn markAllRowsDirty(self: *Screen) void {
        if (self.rows == 0) return;
        if (self.dirty_state.cols_start) |buf| @memset(buf, 0);
        if (self.dirty_state.cols_end) |buf| @memset(buf, self.cols -| 1);
        self.dirty_state.rows = dirty.rowsForFull(self.rows, self.dirty_state.cols_start, self.dirty_state.cols_end);
    }
};

fn colCount(value: u16) u32 {
    return value;
}

fn cloneLogicalLine(allocator: std.mem.Allocator, cells: []const cell.Cell) std.mem.Allocator.Error!LogicalLine {
    var line = LogicalLine{};
    errdefer line.deinit(allocator);
    try line.cells.appendSlice(allocator, cells);
    return line;
}

fn cloneAuthorityLine(allocator: std.mem.Allocator, cells: []const cell.Cell) std.mem.Allocator.Error!HistoryLine {
    var line = HistoryLine{};
    errdefer line.deinit(allocator);
    try line.cells.appendSlice(allocator, cells);
    return line;
}

fn decodeExtendedColor(params: []const i32, idx: *u8) ?color.Color {
    const next = idx.* + 1;
    if (next >= params.len) return null;
    const mode = params[idxOf(next)];
    if (mode == 5) {
        if (idx.* + 2 >= params.len) return null;
        idx.* += 2;
        return .indexed(clampByte(params[idxOf(idx.*)]));
    }
    if (mode == 2) {
        if (idx.* + 4 >= params.len) return null;
        idx.* += 4;
        return color.Color.rgb(.{
            .r = clampByte(params[idxOf(idx.* - 2)]),
            .g = clampByte(params[idxOf(idx.* - 1)]),
            .b = clampByte(params[idxOf(idx.*)]),
        });
    }
    return null;
}

fn idxOf(value: u8) usize {
    return @intCast(value);
}

fn clampByte(value: i32) u8 {
    return @intCast(@max(0, @min(255, value)));
}

fn ansi16Color(idx: u8) color.Color {
    return switch (idx) {
        0...15 => .indexed(idx),
        else => cell.default_cell_attrs.fg,
    };
}

fn isTrailingCombiningCodepoint(cp: u21) bool {
    return switch (cp) {
        0x0300...0x036F,
        0x0483...0x0489,
        0x0591...0x05BD,
        0x05BF,
        0x05C1...0x05C2,
        0x05C4...0x05C5,
        0x0610...0x061A,
        0x064B...0x065F,
        0x0670,
        0x06D6...0x06DC,
        0x06DF...0x06E4,
        0x06E7...0x06E8,
        0x06EB...0x06EC,
        0x0730...0x074A,
        0x07EB...0x07F3,
        0x0816...0x0819,
        0x081B...0x0823,
        0x0825...0x0827,
        0x0829...0x082D,
        0x0951...0x0954,
        0x0F82...0x0F83,
        0x0F86...0x0F87,
        0x135D...0x135F,
        0x17DD,
        0x193A,
        0x1A17,
        0x1A75...0x1A7C,
        0x1B6B...0x1B73,
        0x1CD0...0x1CD2,
        0x1CDA...0x1CDB,
        0x1CE0,
        0x1AB0...0x1AFF,
        0x1DC0...0x1DFF,
        0x20D0...0x20FF,
        0x2CEF...0x2CF1,
        0x2DE0...0x2DFF,
        0xA66F,
        0xA67C...0xA67D,
        0xA6F0...0xA6F1,
        0xA8E0...0xA8F1,
        0xAAB0,
        0xAAB2...0xAAB3,
        0xAAB7...0xAAB8,
        0xAABE...0xAABF,
        0xAAC1,
        0x200C...0x200D,
        0xFE00...0xFE0F,
        0xFE20...0xFE2F,
        0x10A0F,
        0x10A38,
        0x1D185...0x1D189,
        0x1D1AA...0x1D1AD,
        0x1D242...0x1D244,
        0xE0100...0xE01EF,
        => true,
        else => false,
    };
}
