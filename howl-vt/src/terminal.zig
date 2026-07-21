//! Owns the complete terminal state machine, host consequences, and publication lifecycle.

const std = @import("std");
const parser_mod = @import("parser.zig");

const logical_output_line_bytes_max: usize = 1024 * 1024;
const logical_output_bytes_max: usize = 1024 * 1024;

/// Terminal screen state for cursor, cells, margins, and history.
pub const Screen = struct {
    /// Failure while validating dimensions or allocating owned Screen storage.
    const InitError = error{ InvalidDimensions, OutOfMemory };

    /// Uses the canonical terminal RGB value for screen state.
    pub const Rgb = ScreenRgb;
    /// Uses the canonical default, indexed, or RGB terminal color.
    pub const Color = ScreenColor;
    /// Uses the canonical terminal underline style.
    pub const UnderlineStyle = ScreenUnderlineStyle;
    /// Uses the canonical terminal baseline displacement.
    pub const Baseline = ScreenBaseline;
    /// Uses the canonical complete cell attribute value.
    pub const CellAttrs = ScreenCellAttrs;
    /// Distinguishes unprotected, ISO guarded-area, and DEC selective-erase cells.
    pub const Protection = ScreenProtection;
    /// Uses the canonical terminal cell value.
    pub const Cell = ScreenCell;
    /// Uses the canonical cursor shape.
    pub const CursorShape = ScreenCursorShape;
    /// Uses the canonical cursor style.
    pub const CursorStyle = ScreenCursorStyle;
    const SemanticCursor = ScreenSemanticCursor;
    /// Provides the canonical default cursor style.
    pub const default_cursor_style = initial_cursor_style;
    /// Provides the canonical default foreground color.
    pub const default_fg = default_cell_foreground;
    const default_bg = default_cell_background;
    /// Provides the canonical default underline color.
    pub const default_underline_color = default_cell_underline_color;
    /// Provides the canonical default cell attributes.
    pub const default_cell_attrs = initial_cell_attrs;
    const default_cell = blank_cell;
    /// Uses the canonical borrowed dirty-row publication view.
    pub const DirtyRows = ScreenDirtyRows;
    /// Describes one row's DEC presentation geometry without prescribing host rendering.
    pub const LineGeometry = enum(u2) {
        single_width,
        double_width,
        double_height_top,
        double_height_bottom,
    };
    const EraseMode = ScreenEraseMode;
    const CellPixelSize = struct {
        width: u32,
        height: u32,
    };
    const row_wrapped_bit: u8 = 1;
    const row_geometry_shift: u3 = 1;
    const row_geometry_mask: u8 = 0b110;

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
    row_flags: ?[]u8,
    history: ?[]Cell,
    history_flags: ?[]u8,
    history_capacity: u16,
    history_count: u32,
    history_write_idx: u32,
    history_row_base: u32,
    history_lines: std.ArrayListUnmanaged(HistoryLine),
    history_lines_start: u32,
    open_history_line: ?HistoryLine,
    output_lines: std.ArrayListUnmanaged(?OutputLine),
    output_lines_start: u32,
    output_lines_count: u16,
    output_bytes: usize,
    next_output_id: u64,
    history_loss_generation: u64,
    last_graphic: ?LastGraphic,
    current_attrs: CellAttrs,
    dirty_state: DirtyState,
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
        row_flags: ?[]u8,
        history: ?[]Cell,
        history_flags: ?[]u8,
        history_capacity: u16,
        dirty_state: DirtyState,
        tab_stops: ?[]bool,
    ) Screen {
        return .{
            .allocator = allocator,
            .rows = rows,
            .cols = cols,
            .cursor = ScreenSemanticCursor.init(cursor_style_default),
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
            .row_flags = row_flags,
            .history = history,
            .history_flags = history_flags,
            .history_capacity = history_capacity,
            .history_count = 0,
            .history_write_idx = 0,
            .history_row_base = 0,
            .history_lines = .empty,
            .history_lines_start = 0,
            .open_history_line = null,
            .output_lines = .empty,
            .output_lines_start = 0,
            .output_lines_count = 0,
            .output_bytes = 0,
            .next_output_id = 1,
            .history_loss_generation = 0,
            .last_graphic = null,
            .current_attrs = initial_cell_attrs,
            .dirty_state = dirty_state,
            .tab_stops = tab_stops,
            .cell_pixel_size = null,
        };
    }

    /// Initialize cursor-only grid state.
    pub fn init(rows: u16, cols: u16) Screen {
        return initWithDefaultCursorStyle(rows, cols, initial_cursor_style);
    }

    fn initWithDefaultCursorStyle(rows: u16, cols: u16, cursor_style_default: CursorStyle) Screen {
        return initBase(null, rows, cols, cursor_style_default, null, null, null, null, 0, .{}, null);
    }

    /// Initialize screen with owned cell storage.
    pub fn initWithCells(allocator: std.mem.Allocator, rows: u16, cols: u16) InitError!Screen {
        return initWithCellsAndDefaultCursorStyle(allocator, rows, cols, initial_cursor_style);
    }

    fn initOwnedVisibleGrid(
        allocator: std.mem.Allocator,
        rows: u16,
        cols: u16,
        cursor_style_default: CursorStyle,
    ) InitError!Screen {
        if (rows == 0 or cols == 0) return error.InvalidDimensions;
        const cell_count = cellCount(rows, cols);
        const cells: ?[]Cell = if (cell_count > 0) blk: {
            const buf = try allocator.alloc(Cell, @intCast(cell_count));
            @memset(buf, blank_cell);
            break :blk buf;
        } else null;
        errdefer if (cells) |c| allocator.free(c);
        const row_flags: ?[]u8 = if (rows > 0) blk: {
            const buf = try allocator.alloc(u8, rows);
            @memset(buf, 0);
            break :blk buf;
        } else null;
        errdefer if (row_flags) |buf| allocator.free(buf);
        const dirty_cols_start = try allocDirtyCols(allocator, rows, 0);
        errdefer if (dirty_cols_start) |buf| allocator.free(buf);
        const dirty_cols_end = try allocDirtyCols(allocator, rows, cols -| 1);
        errdefer if (dirty_cols_end) |buf| allocator.free(buf);
        const tab_stops = try allocTabStops(allocator, cols);
        errdefer if (tab_stops) |buf| allocator.free(buf);
        return initBase(
            allocator,
            rows,
            cols,
            cursor_style_default,
            cells,
            row_flags,
            null,
            null,
            0,
            DirtyState.initFull(rows, dirty_cols_start, dirty_cols_end),
            tab_stops,
        );
    }

    fn initWithCellsAndDefaultCursorStyle(
        allocator: std.mem.Allocator,
        rows: u16,
        cols: u16,
        cursor_style_default: CursorStyle,
    ) InitError!Screen {
        return initOwnedVisibleGrid(allocator, rows, cols, cursor_style_default);
    }

    /// Initialize screen with cells and history storage.
    pub fn initWithCellsAndHistory(
        allocator: std.mem.Allocator,
        rows: u16,
        cols: u16,
        history_capacity: u16,
    ) InitError!Screen {
        return initWithCellsHistoryAndDefaultCursorStyle(allocator, rows, cols, history_capacity, initial_cursor_style);
    }

    fn initWithCellsHistoryAndDefaultCursorStyle(
        allocator: std.mem.Allocator,
        rows: u16,
        cols: u16,
        history_capacity: u16,
        cursor_style_default: CursorStyle,
    ) InitError!Screen {
        var screen = try initOwnedVisibleGrid(allocator, rows, cols, cursor_style_default);
        errdefer screen.deinit(allocator);

        const history: ?[]Cell = if (screen.cells != null and history_capacity > 0) blk: {
            const buf = try allocator.alloc(Cell, 0);
            break :blk buf;
        } else null;
        errdefer if (history) |buf| allocator.free(buf);
        const history_flags: ?[]u8 = if (screen.cells != null and history_capacity > 0) blk: {
            const buf = try allocator.alloc(u8, 0);
            break :blk buf;
        } else null;

        screen.history = history;
        screen.history_flags = history_flags;
        screen.history_capacity = if (screen.cells != null) history_capacity else 0;
        return screen;
    }

    /// Release owned cell and history buffers.
    pub fn deinit(self: *Screen, allocator: std.mem.Allocator) void {
        if (self.cells) |c| allocator.free(c);
        self.cells = null;
        if (self.row_flags) |buf| allocator.free(buf);
        self.row_flags = null;
        self.dirty_state.deinit(allocator);
        if (self.tab_stops) |buf| allocator.free(buf);
        self.tab_stops = null;
        if (self.history) |h| allocator.free(h);
        self.history = null;
        if (self.history_flags) |buf| allocator.free(buf);
        self.history_flags = null;
        for (self.history_lines.items) |*line| line.deinit(allocator);
        self.history_lines.deinit(allocator);
        if (self.open_history_line) |*line| line.deinit(allocator);
        self.open_history_line = null;
        for (self.output_lines.items) |*slot| if (slot.*) |*line| line.deinit(allocator);
        self.output_lines.deinit(allocator);
    }

    /// Replace this screen with a reflowed grid of the requested dimensions.
    ///
    /// Allocation failure leaves this screen unchanged. Successful replacement
    /// preserves logical content and configured cursor defaults, resets margins
    /// and physical-row geometry to the full new grid, and releases old storage.
    pub fn resize(self: *Screen, allocator: std.mem.Allocator, rows: u16, cols: u16) std.mem.Allocator.Error!void {
        var replacement = try self.prepareResize(allocator, rows, cols);
        std.mem.swap(Screen, self, &replacement);
        replacement.deinit(allocator);
    }

    /// Build complete reflowed screen state without mutating this screen.
    ///
    /// The caller owns the returned Screen and must call `deinit` unless it
    /// transfers ownership by swapping it into a Screen owner.
    pub fn prepareResize(
        self: *const Screen,
        allocator: std.mem.Allocator,
        rows: u16,
        cols: u16,
    ) std.mem.Allocator.Error!Screen {
        var lines = try self.collectLogicalSnapshot(allocator);
        defer lines.deinit(allocator);

        var reflow = try reflowLogicalLines(allocator, lines, cols);
        defer reflow.deinit(allocator);

        const viewport = projectViewport(screenCount32(lines.logical_lines.items.len), reflow, rows);
        var buffers = try allocResizeBuffers(allocator, rows, cols, self.tab_stops);
        errdefer buffers.deinit(allocator);

        copyVisibleRows(&buffers, reflow, viewport, cols);
        var replacement = self.replacementBase(allocator);
        replacement.installResizeState(rows, cols, buffers.take());
        errdefer replacement.deinit(allocator);
        try replacement.cloneOutputAuthority(allocator, self);
        try replacement.rebuildResizeAuthority(allocator, lines, reflow, viewport, cols);
        replacement.restoreResizeCursor(rows, cols, reflow, viewport);
        return replacement;
    }

    fn replacementBase(self: *const Screen, allocator: std.mem.Allocator) Screen {
        var replacement = self.*;
        replacement.allocator = allocator;
        replacement.cells = null;
        replacement.row_flags = null;
        replacement.dirty_state = .{};
        replacement.tab_stops = null;
        replacement.history = null;
        replacement.history_flags = null;
        replacement.history_count = 0;
        replacement.history_write_idx = 0;
        replacement.history_lines = .empty;
        replacement.history_lines_start = 0;
        replacement.open_history_line = null;
        replacement.output_lines = .empty;
        replacement.output_lines_start = 0;
        replacement.output_lines_count = 0;
        replacement.output_bytes = 0;
        return replacement;
    }

    fn installResizeState(self: *Screen, rows: u16, cols: u16, buffers: ResizeBuffers) void {
        self.rows = rows;
        self.cols = cols;
        self.cells = buffers.cells;
        self.row_flags = buffers.row_flags;
        self.dirty_state = buffers.dirty_state;
        self.tab_stops = buffers.tab_stops;
        self.history = null;
        self.history_flags = null;
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
        self.dirty_state.rows = rowsForFull(rows, self.dirty_state.cols_start, self.dirty_state.cols_end);

        std.debug.assert(self.rows == rows);
        std.debug.assert(self.cols == cols);
        std.debug.assert((self.cells != null) == (rows > 0 and cols > 0));
        std.debug.assert((self.row_flags != null) == (rows > 0));
        std.debug.assert((self.dirty_state.cols_start != null) == (rows > 0));
        std.debug.assert((self.dirty_state.cols_end != null) == (rows > 0));
        std.debug.assert((self.tab_stops != null) == (cols > 0));
        if (self.cells) |buf| std.debug.assert(buf.len == cellCount(rows, cols));
        if (self.row_flags) |buf| std.debug.assert(buf.len == rows);
        if (self.dirty_state.cols_start) |buf| std.debug.assert(buf.len == rows);
        if (self.dirty_state.cols_end) |buf| std.debug.assert(buf.len == rows);
        if (self.tab_stops) |buf| std.debug.assert(buf.len == cols);
        std.debug.assert(self.history == null);
        std.debug.assert(self.history_flags == null);
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

    fn cloneOutputAuthority(
        self: *Screen,
        allocator: std.mem.Allocator,
        source: *const Screen,
    ) std.mem.Allocator.Error!void {
        try self.output_lines.ensureTotalCapacity(allocator, source.output_lines.items.len);
        while (self.output_lines.items.len < source.output_lines.items.len) {
            self.output_lines.appendAssumeCapacity(null);
        }
        for (source.output_lines.items, 0..) |slot, index| {
            const line = slot orelse continue;
            self.output_lines.items[index] = .{
                .id = line.id,
                .value = switch (line.value) {
                    .text => |text| .{ .text = try allocator.dupe(u8, text) },
                    .loss => |loss| .{ .loss = loss },
                },
            };
        }
        self.output_lines_start = source.output_lines_start;
        self.output_lines_count = source.output_lines_count;
        self.output_bytes = source.output_bytes;
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
        std.debug.assert(viewport.total_rows == screenCount32(reflow.rewrapped.items.len));
        std.debug.assert(viewport.first_visible_line <= screenCount32(lines.logical_lines.items.len));
        if (viewport.first_visible_line < screenCount32(lines.logical_lines.items.len)) {
            std.debug.assert(
                viewport.hidden_rows_in_first_visible_line <
                    reflow.line_row_counts.items[@intCast(viewport.first_visible_line)],
            );
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

    fn installResizeProjection(
        self: *Screen,
        allocator: std.mem.Allocator,
        reflow: ReflowState,
        viewport: ViewportState,
    ) std.mem.Allocator.Error!void {
        self.history_count = 0;
        self.history_write_idx = 0;
        if (self.history_capacity == 0 or self.cols == 0) return;

        const kept_complete_start = viewport.first_visible_line -| self.history_capacity;
        const first_projected_row = if (kept_complete_start < screenCount32(reflow.line_row_starts.items.len))
            reflow.line_row_starts.items[@intCast(kept_complete_start)]
        else
            viewport.visible_start;
        std.debug.assert(first_projected_row <= viewport.visible_start);
        std.debug.assert(viewport.visible_start <= screenCount32(reflow.rewrapped.items.len));

        var row_index = first_projected_row;
        while (row_index < viewport.visible_start) : (row_index += 1) {
            const row = reflow.rewrapped.items[@intCast(row_index)];
            const row_end = row.start + self.cols;
            std.debug.assert(row.len <= self.cols);
            std.debug.assert(row_end <= screenCount32(reflow.flat_rows.items.len));
            try self.appendProjectedRow(
                allocator,
                reflow.flat_rows.items[@intCast(row.start)..@intCast(row.start + row.len)],
                row.wrapped,
                row.geometry,
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
        std.debug.assert(first_visible_line <= screenCount32(logical_lines.len));
        if (first_visible_line < screenCount32(logical_lines.len)) {
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

        if (first_visible_line < screenCount32(logical_lines.len) and hidden_rows_in_first_visible_line > 0) {
            const line = logical_lines[@intCast(first_visible_line)];
            const row_start = line_row_starts[@intCast(first_visible_line)];
            const row_limit = @min(hidden_rows_in_first_visible_line, line_row_counts[@intCast(first_visible_line)]);
            std.debug.assert(row_start + row_limit <= screenCount32(rewrapped.len));
            var prefix_len: u32 = 0;
            var hidden_row: u16 = 0;
            while (hidden_row < row_limit) : (hidden_row += 1) {
                const row = rewrapped[@intCast(row_start + hidden_row)];
                std.debug.assert(row.len <= cols);
                prefix_len += rewrapped[@intCast(row_start + hidden_row)].len;
            }
            prefix_len = @min(prefix_len, screenCount32(line.cells.items.len));
            std.debug.assert(prefix_len <= screenCount32(line.cells.items.len));
            self.open_history_line = try cloneAuthorityLine(allocator, line.cells.items[0..@intCast(prefix_len)]);
        }

        if (self.history_lines.items.len > self.history_capacity) {
            const drop = self.history_lines.items.len - self.history_capacity;
            std.debug.assert(drop <= self.history_lines.items.len);
            var index: u32 = 0;
            while (index < drop) : (index += 1) {
                self.history_lines.items[@intCast(index)].deinit(allocator);
            }
            std.mem.copyForwards(
                HistoryLine,
                self.history_lines.items[0 .. self.history_lines.items.len - drop],
                self.history_lines.items[drop..],
            );
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
        const cursor_row: u16 = @intCast(clamped_cursor_row - viewport.visible_start);
        self.cursor.setPositionStructural(
            cursor_row,
            @min(reflow.global_cursor_col, self.lineRightBoundary(cursor_row)),
        );
        self.wrap_pending = reflow.next_wrap_pending and
            self.cursor.row < rows and self.cursor.col == self.lineRightBoundary(self.cursor.row);

        std.debug.assert(viewport.visible_rows_kept > 0);
        std.debug.assert(clamped_cursor_row >= viewport.visible_start);
        std.debug.assert(clamped_cursor_row <= last_visible_row);
        std.debug.assert(self.cursor.row < rows);
        std.debug.assert(self.cursor.col < cols);
        if (self.wrap_pending) std.debug.assert(self.cursor.col == self.lineRightBoundary(self.cursor.row));
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
        ) catch {
            self.recordHistoryLoss();
            return;
        };
        defer next_line.deinit(allocator);

        next_line.cells.ensureTotalCapacity(allocator, next_line.cells.items.len + len) catch {
            self.recordHistoryLoss();
            return;
        };
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
        self.ensureProjectedCapacity(allocator, projected_target) catch {
            self.recordHistoryLoss();
            return;
        };
        if (!wrapped and !replacing_oldest) {
            self.history_lines.ensureTotalCapacity(allocator, self.history_lines.items.len + 1) catch {
                self.recordHistoryLoss();
                return;
            };
        }

        const replacement_slot = if (replacing_oldest) self.dropOldestHistoryLine(allocator) else null;
        self.appendProjectedRowAssumeCapacity(
            next_line.cells.items[next_line.cells.items.len - len ..],
            wrapped,
            self.lineGeometry(row),
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

    fn recordHistoryLoss(self: *Screen) void {
        self.history_loss_generation = std.math.add(
            u64,
            self.history_loss_generation,
            1,
        ) catch @panic("terminal history loss generation exhausted");
    }

    fn finalizeOutputLine(
        self: *Screen,
        allocator: std.mem.Allocator,
    ) std.mem.Allocator.Error!void {
        if (self.history_capacity == 0) return;
        const byte_count = openOutputLineByteCount(self);
        if (byte_count > logical_output_line_bytes_max) {
            try self.retainOutputLoss(allocator, byte_count);
            return;
        }
        const text = copyOpenOutputLine(
            allocator,
            self,
            byte_count,
        ) catch |failure| switch (failure) {
            error.OutOfMemory => return error.OutOfMemory,
            error.LineTooLong => unreachable,
        };
        errdefer allocator.free(text);
        try self.retainOutputText(allocator, text);
    }

    // Finalized output is copied separately because logical-history rows are
    // retained only after leaving the viewport, while output identity belongs
    // to the earlier line-finalization boundary and must survive later reflow.
    fn retainOutputText(
        self: *Screen,
        allocator: std.mem.Allocator,
        text: []u8,
    ) std.mem.Allocator.Error!void {
        std.debug.assert(text.len <= logical_output_line_bytes_max);
        try self.retainOutputLine(allocator, .{ .text = text });
    }

    fn retainOutputLoss(
        self: *Screen,
        allocator: std.mem.Allocator,
        byte_count: usize,
    ) std.mem.Allocator.Error!void {
        std.debug.assert(byte_count > logical_output_line_bytes_max);
        try self.retainOutputLine(allocator, .{ .loss = .{
            .byte_count = byte_count,
            .reason = .line_too_long,
        } });
    }

    fn retainOutputLine(
        self: *Screen,
        allocator: std.mem.Allocator,
        value: OutputLine.Value,
    ) std.mem.Allocator.Error!void {
        if (self.output_lines.items.len == 0) {
            try self.output_lines.ensureTotalCapacity(allocator, self.history_capacity);
            while (self.output_lines.items.len < self.history_capacity) {
                self.output_lines.appendAssumeCapacity(null);
            }
        }
        while (self.output_lines_count == self.history_capacity or
            value.retainedBytes() > logical_output_bytes_max - self.output_bytes)
        {
            self.evictOldestOutputLine(allocator);
        }
        const slot = (self.output_lines_start + self.output_lines_count) %
            @as(u32, @intCast(self.output_lines.items.len));
        std.debug.assert(self.output_lines.items[@intCast(slot)] == null);
        self.output_lines.items[@intCast(slot)] = .{
            .id = self.takeOutputId(),
            .value = value,
        };
        self.output_lines_count += 1;
        self.output_bytes += value.retainedBytes();
        std.debug.assert(self.output_bytes <= logical_output_bytes_max);
    }

    fn evictOldestOutputLine(self: *Screen, allocator: std.mem.Allocator) void {
        std.debug.assert(self.output_lines_count > 0);
        const slot = &self.output_lines.items[@intCast(self.output_lines_start)];
        var line = slot.* orelse unreachable;
        self.output_bytes -= line.value.retainedBytes();
        line.deinit(allocator);
        slot.* = null;
        self.output_lines_count -= 1;
        self.output_lines_start = (self.output_lines_start + 1) %
            @as(u32, @intCast(self.output_lines.items.len));
    }

    fn takeOutputId(self: *Screen) u64 {
        const id = self.next_output_id;
        self.next_output_id = std.math.add(u64, id, 1) catch
            @panic("terminal logical output identity exhausted");
        return id;
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
    pub fn collectLogicalSnapshot(
        self: *const Screen,
        allocator: std.mem.Allocator,
    ) std.mem.Allocator.Error!LogicalSnapshot {
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

        if (current_line.cells.items.len > 0 or
            current_line.cursor_offset != null or
            result.logical_lines.items.len == 0)
        {
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
        const line_cols = self.lineColumnCount(row);
        while (col < line_cols) : (col += 1) {
            if (self.cellInfoAt(row, col).codepoint != 0) {
                has_content = true;
                last_non_zero = col + 1;
            }
        }

        var len: u16 = if (has_content) last_non_zero else 0;
        if (self.rowWrapped(row) and line_cols > 0) len = @max(len, line_cols);
        return len;
    }

    fn cursorOffsetInRow(self: *const Screen) u32 {
        if (self.cols == 0) return 0;
        const line_cols = self.lineColumnCount(self.cursor.row);
        if (self.wrap_pending and self.cursor.col == line_cols - 1) return line_cols;
        return self.cursor.col;
    }

    fn appendProjectionRows(
        self: *Screen,
        allocator: std.mem.Allocator,
        cells: []const Cell,
        continues_to_visible: bool,
    ) std.mem.Allocator.Error!void {
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
            try self.appendProjectedRow(
                allocator,
                cells[@intCast(start)..@intCast(end)],
                row_idx + 1 < row_count or continues_to_visible,
                .single_width,
            );
        }
    }

    fn visibleRowContentLen(self: *const Screen, row: u16) u16 {
        const line_cols = self.lineColumnCount(row);
        var col = line_cols;
        while (col > 0) {
            const idx = col - 1;
            if (self.cellInfoAt(row, idx).codepoint != 0) return col;
            col -= 1;
        }
        if (self.rowWrapped(row) and line_cols > 0) return line_cols;
        return 0;
    }

    fn dropOldestHistoryLine(self: *Screen, allocator: std.mem.Allocator) u32 {
        std.debug.assert(self.historyLineCount() == self.history_capacity);
        const slot = self.history_lines_start;
        self.dropOldestProjectedRows(
            self.projectedRowCountForCells(self.history_lines.items[@intCast(slot)].cells.items),
        );
        self.history_lines.items[@intCast(slot)].deinit(allocator);
        self.history_lines.items[@intCast(slot)] = .{};
        self.history_lines_start = (self.history_lines_start + 1) % self.historyLineCount();
        return slot;
    }

    fn appendProjectedRow(
        self: *Screen,
        allocator: std.mem.Allocator,
        cells: []const Cell,
        wrapped: bool,
        geometry: LineGeometry,
    ) std.mem.Allocator.Error!void {
        if (self.cols == 0) return;
        const capacity_target = @min(self.history_count + 1, @as(u32, self.history_capacity));
        try self.ensureProjectedCapacity(allocator, capacity_target);
        self.appendProjectedRowAssumeCapacity(cells, wrapped, geometry);
    }

    fn appendProjectedRowAssumeCapacity(
        self: *Screen,
        cells: []const Cell,
        wrapped: bool,
        geometry: LineGeometry,
    ) void {
        const flags = self.history_flags orelse return;
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
        std.debug.assert(slot < flags.len);
        std.debug.assert(base + cols <= history.len);

        @memset(history[@intCast(base)..@intCast(base + cols)], blank_cell);
        @memcpy(history[@intCast(base)..@intCast(base + cell_count)], cells);
        flags[@intCast(slot)] = rowFlags(wrapped, geometry);
        self.history_count += 1;
    }

    fn ensureProjectedCapacity(
        self: *Screen,
        allocator: std.mem.Allocator,
        min_rows: u32,
    ) std.mem.Allocator.Error!void {
        if (self.cols == 0) return;

        const current_rows = self.projectedCapacity();
        if (current_rows >= min_rows) return;

        const new_rows = @max(min_rows, @max(current_rows * 2, @as(u32, 8)));
        const cols: u32 = self.cols;
        const new_history = try allocator.alloc(Cell, @intCast(new_rows * cols));
        errdefer allocator.free(new_history);
        @memset(new_history, blank_cell);

        const new_flags = try allocator.alloc(u8, @intCast(new_rows));
        errdefer allocator.free(new_flags);
        @memset(new_flags, 0);

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
                @memcpy(
                    new_history[@intCast(dest_start)..@intCast(dest_start + cols)],
                    history[@intCast(source_start)..@intCast(source_start + cols)],
                );
            }
            if (self.history_flags) |flags| new_flags[@intCast(logical_row)] = flags[@intCast(old_slot)];
        }

        if (self.history) |history| allocator.free(history);
        if (self.history_flags) |flags| allocator.free(flags);
        self.history = new_history;
        self.history_flags = new_flags;
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
        self.last_graphic = null;
        self.current_attrs = initial_cell_attrs;
        self.markAllRowsDirty();
        if (self.cells) |c| @memset(c, blank_cell);
        if (self.row_flags) |buf| @memset(buf, 0);
        if (self.tab_stops) |stops| setDefaultTabStops(stops);
    }

    // Applies DECSTR's bank-local defaults without erasing cells or moving the cursor.
    fn softReset(self: *Screen) bool {
        const cursor_before = self.cursor;
        var changed = self.wrap_pending or !self.auto_wrap or self.origin_mode or
            self.attr_change_extent_rect or self.scroll_top != 0 or self.scroll_bottom != self.rows -| 1 or
            !std.meta.eql(self.current_attrs, initial_cell_attrs);

        self.wrap_pending = false;
        self.auto_wrap = true;
        self.origin_mode = false;
        self.attr_change_extent_rect = false;
        self.scroll_top = 0;
        self.scroll_bottom = self.rows -| 1;
        self.current_attrs = initial_cell_attrs;
        self.cursor.restoreDefaultStyle();
        changed = !std.meta.eql(cursor_before, self.cursor) or changed;

        if (self.tab_stops) |stops| {
            for (stops, 0..) |stop, col| {
                if (stop != (col != 0 and col % 8 == 0)) changed = true;
            }
            setDefaultTabStops(stops);
        }
        var row: u16 = 0;
        while (row < self.rows) : (row += 1) {
            if (self.lineGeometry(row) != .single_width) changed = true;
            self.resetLineGeometry(row);
        }
        return changed;
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
        const c = self.cells orelse return blank_cell;
        if (row >= self.rows or col >= self.cols) return blank_cell;
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
        const h = self.history orelse return blank_cell;
        const bounded_idx: u32 = history_idx;
        if (bounded_idx >= self.history_count or col >= self.cols) return blank_cell;
        const slot = self.historySlotForRecency(history_idx) orelse return blank_cell;
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
            .write_text, .write_codepoint, .sgr => self.applyRetainedState(event),
            .line_feed,
            .next_line,
            .reverse_index,
            .carriage_return,
            .backspace,
            .horizontal_tab,
            .horizontal_tab_forward,
            .horizontal_tab_back,
            => self.applyFlowMove(event),
            .horizontal_tab_set,
            .tab_clear_current,
            .tab_clear_all,
            .reset_default_tab_stops,
            => self.applyTabState(event),
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
            .insert_lines,
            .delete_lines,
            .insert_chars,
            .delete_chars,
            .scroll_up_lines,
            .scroll_down_lines,
            .set_scroll_region,
            .hard_reset,
            => self.applyLineEdit(event),
            .rect_fill, .rect_copy, .rect_attrs_change => self.applyRectEdit(event),
            else => unreachable,
        }
    }

    fn applyCursorMove(self: *Screen, event: SemanticEvent) void {
        self.wrap_pending = false;
        switch (event) {
            .cursor_up => |n| self.setCursorRowClamped(@max(self.cursor.row -| n, self.cursorTopBoundary())),
            .cursor_down => |n| self.setCursorRowClamped(@min(self.cursor.row +| n, self.cursorBottomBoundary())),
            .cursor_forward => |n| self.cursor.setColByClient(@min(self.cursor.col +| n, self.cursorRightBoundary())),
            .cursor_back => |n| self.cursor.setColByClient(@max(self.cursor.col -| n, self.cursorLeftBoundary())),
            .cursor_next_line => |n| self.cursor.setPositionByClient(
                @min(self.cursor.row +| n, self.cursorBottomBoundary()),
                self.relativeLineHomeCol(),
            ),
            .cursor_prev_line => |n| self.cursor.setPositionByClient(
                @max(self.cursor.row -| n, self.cursorTopBoundary()),
                self.relativeLineHomeCol(),
            ),
            .cursor_horizontal_absolute => |col| self.cursor.setColByClient(
                @min(self.resolveAbsoluteCol(col), self.lineRightBoundary(self.cursor.row)),
            ),
            .cursor_vertical_absolute => |row| self.setCursorRowClamped(self.resolveAbsoluteRow(row)),
            .cursor_position => |pos| {
                const row = @min(self.resolveAbsoluteRow(pos.row), self.rows -| 1);
                self.cursor.setPositionByClient(
                    row,
                    @min(self.resolveAbsoluteCol(pos.col), self.lineRightBoundary(row)),
                );
            },
            else => unreachable,
        }
    }

    // Applies one cursor-positioning event and reports exact position or pending-wrap mutation.
    fn moveCursor(self: *Screen, event: SemanticEvent) bool {
        const cursor_before = self.cursor;
        const wrap_before = self.wrap_pending;
        self.applyCursorMove(event);
        return !std.meta.eql(cursor_before, self.cursor) or wrap_before != self.wrap_pending;
    }

    fn applyRetainedState(self: *Screen, event: SemanticEvent) void {
        switch (event) {
            .write_text => |text| self.writeText(text),
            .write_codepoint => |codepoint| self.writeCell(codepoint),
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
            .backspace => self.applyBackspace(false),
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

    // Applies iTerm2's reverse-wrap policy to one C0 BS and reports exact cursor or phantom mutation.
    fn backspace(self: *Screen, reverse_wraparound: bool) bool {
        const cursor_before = self.cursor;
        const pending_before = self.wrap_pending;
        self.applyBackspace(reverse_wraparound);
        return !std.meta.eql(cursor_before, self.cursor) or pending_before != self.wrap_pending;
    }

    fn applyBackspace(self: *Screen, reverse_wraparound: bool) void {
        if (self.wrap_pending) {
            self.wrap_pending = false;
            if (!reverse_wraparound or !self.auto_wrap) {
                self.cursor.setColByClient(self.cursor.col -| 1);
            }
        } else if (self.shouldReverseWrap(reverse_wraparound)) {
            const previous_row = self.cursor.row - 1;
            const right = if (self.left_right_margin_mode)
                @min(self.right_margin, self.lineRightBoundary(previous_row))
            else
                self.lineRightBoundary(previous_row);
            self.cursor.setPositionByClient(previous_row, right);
        } else {
            const left = if (self.left_right_margin_mode) self.left_margin else 0;
            if (self.cursor.col > left or (self.cursor.col < left and self.cursor.col > 0)) {
                self.cursor.setColByClient(self.cursor.col - 1);
            }
        }
    }

    fn shouldReverseWrap(self: *const Screen, reverse_wraparound: bool) bool {
        if (!self.auto_wrap) return false;
        const left = if (self.left_right_margin_mode) self.left_margin else 0;
        if (self.cursor.col != left and self.cursor.col != 0) return false;
        if (self.cursor.row == 0 or self.cursor.row == self.scroll_top) return false;
        if (reverse_wraparound) return true;
        return !self.left_right_margin_mode and self.rowWrapped(self.cursor.row - 1);
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
            .character_protection => |protection| self.current_attrs.protected = protection,
            .attr_change_extent_rect => |enabled| self.attr_change_extent_rect = enabled,
            .left_right_margin_mode => |enabled| {
                if (self.setLeftRightMarginMode(enabled)) return;
            },
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
            .hard_reset => self.reset(),
            else => unreachable,
        }
    }

    fn applyRectEdit(self: *Screen, event: SemanticEvent) void {
        self.wrap_pending = false;
        switch (event) {
            .rect_fill => |request| self.fillRect(request.area, request.ch),
            .rect_copy => |request| self.copyRect(request),
            .rect_attrs_change => |request| self.changeRectAttrs(
                request.area,
                request.attrs.params[0..request.attrs.param_count],
                request.reverse,
            ),
            else => unreachable,
        }
    }

    const RectBounds = struct {
        top: u16,
        left: u16,
        bottom: u16,
        right: u16,
    };

    /// Erases one display mode, preserving protected cells when requested.
    /// Returns whether cells, row facts, history, or pending wrap changed; it cannot fail.
    pub fn eraseDisplay(self: *Screen, mode: EraseMode, protected: bool) bool {
        var changed = self.cancelPendingWrap();
        if (self.cells == null) return changed;
        if (self.rows == 0 or self.cols == 0) return changed;
        switch (mode) {
            .cursor_to_end => {
                changed = self.clearDisplayRowRange(
                    protected,
                    self.cursor.row,
                    self.cursor.col,
                    self.lineColumnCount(self.cursor.row),
                ) or changed;
                if (self.cursor.col < self.lineColumnCount(self.cursor.row)) {
                    changed = self.clearRowContinuation(self.cursor.row) or changed;
                }
                var row = self.cursor.row + 1;
                while (row < self.rows) : (row += 1) {
                    changed = self.eraseFullDisplayRow(row, protected) or changed;
                }
            },
            .start_to_cursor => {
                var row: u16 = 0;
                while (row < self.cursor.row) : (row += 1) {
                    changed = self.eraseFullDisplayRow(row, protected) or changed;
                }
                changed = self.clearDisplayRowRange(protected, self.cursor.row, 0, self.cursor.col + 1) or changed;
            },
            .all => {
                var row: u16 = 0;
                while (row < self.rows) : (row += 1) {
                    changed = self.eraseFullDisplayRow(row, protected) or changed;
                }
            },
            .scrollback => return self.clearScrollback() or changed,
        }
        return changed;
    }

    fn clearDisplayRowRange(self: *Screen, protected: bool, row: u16, start_col: u16, end_col_exclusive: u16) bool {
        return self.eraseRowRange(row, start_col, end_col_exclusive, protected);
    }

    fn eraseFullDisplayRow(self: *Screen, row: u16, protected: bool) bool {
        var changed = self.clearDisplayRowRange(protected, row, 0, self.lineColumnCount(row));
        changed = self.clearRowContinuation(row) or changed;
        if (self.lineGeometry(row) != .single_width) {
            self.resetLineGeometry(row);
            self.markDirtyRow(row);
            changed = true;
        }
        return changed;
    }

    fn cancelPendingWrap(self: *Screen) bool {
        const changed = self.wrap_pending;
        self.wrap_pending = false;
        return changed;
    }

    // Row continuation is published metadata, so changing it dirties the complete row.
    fn clearRowContinuation(self: *Screen, row: u16) bool {
        if (!self.rowWrapped(row)) return false;
        self.setRowWrapped(row, false);
        self.markDirtyRow(row);
        return true;
    }

    /// Set the hyperlink identity copied into subsequent cells and report exact mutation.
    pub fn setCurrentLinkId(self: *Screen, link_id: u32) bool {
        if (self.current_attrs.link_id == link_id) return false;
        self.current_attrs.link_id = link_id;
        return true;
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

    fn relativeLineHomeCol(self: *const Screen) u16 {
        return if (self.left_right_margin_mode) self.left_margin else 0;
    }

    // Relative movement follows iTerm2's directional margin rule: movement toward an active
    // margin stops there even when starting beyond the opposite margin.
    fn cursorTopBoundary(self: *const Screen) u16 {
        return if (self.cursor.row >= self.scroll_top) self.scroll_top else 0;
    }

    fn cursorBottomBoundary(self: *const Screen) u16 {
        const bottom = self.scrollBottom();
        return if (self.cursor.row <= bottom) bottom else self.rows -| 1;
    }

    fn cursorLeftBoundary(self: *const Screen) u16 {
        if (!self.left_right_margin_mode) return 0;
        if (self.cursor.col >= self.left_margin) return self.left_margin;
        return 0;
    }

    fn cursorRightBoundary(self: *const Screen) u16 {
        const line_right = self.lineRightBoundary(self.cursor.row);
        if (!self.left_right_margin_mode) return line_right;
        return if (self.cursor.col <= self.right_margin) @min(self.right_margin, line_right) else line_right;
    }

    /// Clears visible cells and marks the complete screen dirty.
    pub fn clearVisibleCells(self: *Screen) void {
        if (self.cells) |cells| @memset(cells, blank_cell);
        if (self.row_flags) |flags| @memset(flags, 0);
        self.markAllRowsDirty();
    }

    /// Moves the alternate-screen cursor to origin and clears pending wrap.
    pub fn resetCursorForAltEntry(self: *Screen) void {
        self.cursor.resetForAltEntry();
        self.wrap_pending = false;
        self.current_attrs = initial_cell_attrs;
    }

    /// Return the active horizontal editing boundary on the left.
    fn leftBoundary(self: *const Screen) u16 {
        return if (self.left_right_margin_mode) self.left_margin else 0;
    }

    /// Return the active horizontal editing boundary on the right.
    fn rightBoundary(self: *const Screen) u16 {
        return if (self.left_right_margin_mode)
            @min(self.right_margin, self.lineRightBoundary(self.cursor.row))
        else
            self.lineRightBoundary(self.cursor.row);
    }

    fn lineRightBoundary(self: *const Screen, row: u16) u16 {
        return self.lineColumnCount(row) -| 1;
    }

    fn setCursorRowClamped(self: *Screen, row: u16) void {
        self.cursor.setPositionByClient(row, @min(self.cursor.col, self.lineRightBoundary(row)));
    }

    fn clearScrollback(self: *Screen) bool {
        const allocator = self.allocator orelse return false;
        const changed = self.history_count != 0 or self.history_lines.items.len != 0 or self.open_history_line != null;
        self.history_row_base += self.history_count;
        self.clearHistoryAuthority(allocator);
        self.history_count = 0;
        self.history_write_idx = 0;
        if (changed) self.markAllRowsDirty();
        return changed;
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

    /// Erases one active-line mode, preserving protected cells when `selective` is set.
    /// Returns whether cells, continuation, or pending wrap changed; it cannot fail.
    pub fn eraseLine(self: *Screen, mode: EraseMode, selective: bool) bool {
        var changed = self.cancelPendingWrap();
        if (self.cells == null) return changed;
        if (self.rows == 0 or self.cols == 0) return changed;
        const line_cols = self.lineColumnCount(self.cursor.row);
        const range: [2]u16 = switch (mode) {
            .cursor_to_end => .{ self.cursor.col, line_cols },
            .start_to_cursor => .{ @as(u16, 0), self.cursor.col + 1 },
            .all => .{ @as(u16, 0), line_cols },
            .scrollback => return changed,
        };
        changed = self.eraseRowRange(self.cursor.row, range[0], range[1], selective) or changed;
        if (mode == .all or mode == .cursor_to_end) {
            if (range[1] == line_cols) {
                changed = self.clearRowContinuation(self.cursor.row) or changed;
            }
        }
        return changed;
    }

    /// Erases at least one character through the logical row edge.
    /// Returns whether cells, continuation, or pending wrap changed; it cannot fail.
    pub fn eraseChars(self: *Screen, count: u16) bool {
        var changed = self.cancelPendingWrap();
        if (self.rows == 0 or self.cols == 0) return changed;
        const line_cols = self.lineColumnCount(self.cursor.row);
        if (self.cursor.col >= line_cols) return changed;
        const amount = @min(@max(count, 1), line_cols - self.cursor.col);
        changed = self.eraseRowRange(self.cursor.row, self.cursor.col, self.cursor.col + amount, false) or changed;
        if (self.cursor.col + amount == line_cols) {
            changed = self.clearRowContinuation(self.cursor.row) or changed;
        }
        return changed;
    }

    /// Change attributes in the clipped rectangle using rectangular or stream extent.
    fn changeRectAttrs(self: *Screen, area: RectArea, attrs: []const u16, reverse: bool) void {
        const cells = self.cells orelse return;
        if (attrs.len == 0) return;
        const bounds = self.rectBounds(area) orelse return;
        self.markDirtyRect(bounds);
        var row = bounds.top;
        while (row <= bounds.bottom) : (row += 1) {
            const row_start = self.rowStart(row);
            const start_col = if (self.attr_change_extent_rect or row == bounds.top) bounds.left else 0;
            const end_col = if (self.attr_change_extent_rect or row == bounds.bottom) bounds.right else self.cols -| 1;
            var col = start_col;
            while (col <= end_col) : (col += 1) {
                const idx = row_start + @as(u32, col);
                applyRectAttrOps(&cells[@intCast(idx)].attrs, attrs, reverse);
            }
        }
    }

    /// Erase one clipped rectangle under ISO or DEC protection rules.
    /// Returns exact cell, row-continuation, or pending-wrap mutation.
    pub fn eraseRect(self: *Screen, area: RectArea, selective: bool) bool {
        var changed = self.cancelPendingWrap();
        const bounds = self.rectBounds(area) orelse return changed;
        var row = bounds.top;
        while (row <= bounds.bottom) : (row += 1) {
            changed = self.eraseRowRange(row, bounds.left, bounds.right + 1, selective) or changed;
            if (bounds.left == 0 and bounds.right + 1 == self.cols) {
                changed = self.clearRowContinuation(row) or changed;
            }
        }
        return changed;
    }

    /// Fill a clipped rectangle with `codepoint` and the current write attributes.
    fn fillRect(self: *Screen, area: RectArea, codepoint: u21) void {
        const cells = self.cells orelse return;
        const bounds = self.rectBounds(area) orelse return;
        self.markDirtyRect(bounds);
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
    fn copyRect(self: *Screen, request: RectCopy) void {
        const cells = self.cells orelse return;
        if (request.source_page != 1 or request.dest_page != 1) return;
        const source = self.rectBounds(request.area) orelse return;
        const origin = self.activeOriginBounds();
        const dest_top = origin.top + @min(request.dest_top, origin.bottom - origin.top);
        const dest_left = origin.left + @min(request.dest_left, origin.right - origin.left);
        const height: u16 = source.bottom - source.top + 1;
        const width: u16 = source.right - source.left + 1;
        const copy_height = @min(height, origin.bottom - dest_top + 1);
        const copy_width = @min(width, origin.right - dest_left + 1);
        if (copy_height == 0 or copy_width == 0) return;

        const dest_bottom = dest_top + copy_height - 1;
        const dest_right = dest_left + copy_width - 1;
        self.markDirtyRect(.{
            .top = dest_top,
            .left = dest_left,
            .bottom = dest_bottom,
            .right = dest_right,
        });
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

    /// Inserts columns from the cursor through the active right margin across the vertical region.
    /// Returns exact cell, continuation, or pending-wrap mutation; an outside cursor changes no rows.
    pub fn insertColumns(self: *Screen, count: u16) bool {
        var changed = self.cancelPendingWrap();
        const bottom = self.scrollBottom();
        if (self.rows == 0 or self.cols == 0 or self.scroll_top > bottom) return changed;
        if (self.cursor.row < self.scroll_top or self.cursor.row > bottom) return changed;
        if (!self.cursorWithinHorizontalMargins()) return changed;
        var row = self.scroll_top;
        while (row <= bottom) : (row += 1) changed = self.insertColumnsInRow(row, count) or changed;
        return changed;
    }

    /// Deletes columns from the cursor through the active right margin across the vertical region.
    /// Returns exact cell, continuation, or pending-wrap mutation; an outside cursor changes no rows.
    pub fn deleteColumns(self: *Screen, count: u16) bool {
        var changed = self.cancelPendingWrap();
        const bottom = self.scrollBottom();
        if (self.rows == 0 or self.cols == 0 or self.scroll_top > bottom) return changed;
        if (self.cursor.row < self.scroll_top or self.cursor.row > bottom) return changed;
        if (!self.cursorWithinHorizontalMargins()) return changed;
        var row = self.scroll_top;
        while (row <= bottom) : (row += 1) changed = self.deleteColumnsInRow(row, count) or changed;
        return changed;
    }

    /// Shift active scroll-region rows left within current horizontal boundaries.
    /// Returns exact cell, continuation, or pending-wrap mutation.
    pub fn shiftColumnsLeft(self: *Screen, count: u16) bool {
        const changed = self.cancelPendingWrap();
        return self.shiftColumnsLeftInBounds(count, self.leftBoundary(), self.rightBoundary()) or changed;
    }

    /// Shift active scroll-region rows right within current horizontal boundaries.
    /// Returns exact cell, continuation, or pending-wrap mutation.
    pub fn shiftColumnsRight(self: *Screen, count: u16) bool {
        const changed = self.cancelPendingWrap();
        return self.shiftColumnsRightInBounds(count, self.leftBoundary(), self.rightBoundary()) or changed;
    }

    fn shiftColumnsLeftInBounds(self: *Screen, count: u16, left: u16, right: u16) bool {
        const bottom = self.scrollBottom();
        if (self.cols == 0 or left > right or right >= self.cols or self.scroll_top > bottom) return false;
        var changed = false;
        var row = self.scroll_top;
        while (row <= bottom) : (row += 1) changed = self.shiftRowLeft(row, count, left, right) or changed;
        return changed;
    }

    fn shiftColumnsRightInBounds(self: *Screen, count: u16, left: u16, right: u16) bool {
        const bottom = self.scrollBottom();
        if (self.cols == 0 or left > right or right >= self.cols or self.scroll_top > bottom) return false;
        var changed = false;
        var row = self.scroll_top;
        while (row <= bottom) : (row += 1) changed = self.shiftRowRight(row, count, left, right) or changed;
        return changed;
    }

    /// Insert at least one erase cell at the cursor within the right boundary.
    pub fn insertChars(self: *Screen, count: u16) void {
        if (self.rows == 0 or self.cols == 0) return;
        if (self.cursor.col >= self.cols) return;
        if (!self.cursorWithinHorizontalMargins()) return;

        const amount = @min(@max(count, 1), self.rightBoundary() - self.cursor.col + 1);
        const row = self.rowCells(self.cursor.row) orelse return;
        const src_col = screenColCount(self.cursor.col);
        const dst_col = src_col + screenColCount(amount);
        const move_len = screenColCount(self.rightBoundary() + 1) - dst_col;

        std.debug.assert(src_col <= dst_col);
        std.debug.assert(dst_col <= screenColCount(self.rightBoundary() + 1));
        std.debug.assert(dst_col + move_len == screenColCount(self.rightBoundary() + 1));
        std.debug.assert(src_col + move_len <= row.len);
        std.debug.assert(dst_col + move_len <= row.len);
        std.debug.assert(src_col + screenColCount(amount) <= row.len);

        self.markDirtyCols(self.cursor.row, self.cursor.col, self.rightBoundary());
        if (move_len > 0) {
            std.mem.copyBackwards(
                Cell,
                row[@intCast(dst_col)..@intCast(dst_col + move_len)],
                row[@intCast(src_col)..@intCast(src_col + move_len)],
            );
        }
        @memset(row[@intCast(src_col)..@intCast(src_col + screenColCount(amount))], self.eraseCell());
        self.setRowWrapped(self.cursor.row, false);
    }

    /// Delete at least one cell at the cursor within the right boundary.
    pub fn deleteChars(self: *Screen, count: u16) void {
        if (self.rows == 0 or self.cols == 0) return;
        if (self.cursor.col >= self.cols) return;
        if (!self.cursorWithinHorizontalMargins()) return;

        const amount = @min(@max(count, 1), self.rightBoundary() - self.cursor.col + 1);
        const row = self.rowCells(self.cursor.row) orelse return;
        const dst_col = screenColCount(self.cursor.col);
        const src_col = @min(dst_col + screenColCount(amount), screenColCount(self.rightBoundary() + 1));
        const move_len = screenColCount(self.rightBoundary() + 1) - src_col;
        const tail_start = screenColCount(self.rightBoundary() + 1) - screenColCount(amount);
        const tail_end = screenColCount(self.rightBoundary() + 1);

        std.debug.assert(dst_col <= src_col);
        std.debug.assert(src_col <= tail_end);
        std.debug.assert(src_col + move_len == tail_end);
        std.debug.assert(dst_col + move_len <= row.len);
        std.debug.assert(src_col + move_len <= row.len);
        std.debug.assert(tail_start <= tail_end);
        std.debug.assert(tail_end <= row.len);

        self.markDirtyCols(self.cursor.row, self.cursor.col, self.rightBoundary());
        if (move_len > 0) {
            std.mem.copyForwards(
                Cell,
                row[@intCast(dst_col)..@intCast(dst_col + move_len)],
                row[@intCast(src_col)..@intCast(src_col + move_len)],
            );
        }
        @memset(row[@intCast(tail_start)..@intCast(tail_end)], self.eraseCell());
        self.setRowWrapped(self.cursor.row, false);
    }

    fn insertColumnsInRow(self: *Screen, row: u16, count: u16) bool {
        const line_cols = self.lineColumnCount(row);
        const line_right = line_cols - 1;
        const right = if (self.left_right_margin_mode) @min(self.right_margin, line_right) else line_right;
        if (self.cursor.col > right) return false;
        const amount = @min(@max(count, 1), right - self.cursor.col + 1);
        const amount_cols = screenColCount(amount);
        const cells = self.rowCells(row) orelse return false;
        const cursor_col = screenColCount(self.cursor.col);
        const dst_col = cursor_col + amount_cols;
        const end = screenColCount(right + 1);
        const move_len = end - dst_col;
        const erase = self.eraseCell();
        var changed = false;
        var col = cursor_col;
        while (col < end) : (col += 1) {
            const replacement = if (col < dst_col) erase else cells[@intCast(col - amount_cols)];
            if (!std.meta.eql(cells[@intCast(col)], replacement)) changed = true;
        }

        std.debug.assert(cursor_col <= dst_col);
        std.debug.assert(dst_col <= end);
        std.debug.assert(dst_col + move_len == end);
        std.debug.assert(cursor_col + move_len <= cells.len);
        std.debug.assert(dst_col + move_len <= cells.len);
        std.debug.assert(cursor_col + amount_cols <= cells.len);

        if (move_len > 0) {
            std.mem.copyBackwards(
                Cell,
                cells[@intCast(dst_col)..@intCast(dst_col + move_len)],
                cells[@intCast(cursor_col)..@intCast(cursor_col + move_len)],
            );
        }
        @memset(cells[@intCast(cursor_col)..@intCast(cursor_col + amount_cols)], erase);
        changed = self.clearRowContinuation(row) or changed;
        if (changed) self.markDirtyCols(row, self.cursor.col, right);
        return changed;
    }

    fn deleteColumnsInRow(self: *Screen, row: u16, count: u16) bool {
        const line_cols = self.lineColumnCount(row);
        const line_right = line_cols - 1;
        const right = if (self.left_right_margin_mode) @min(self.right_margin, line_right) else line_right;
        if (self.cursor.col > right) return false;
        const amount = @min(@max(count, 1), right - self.cursor.col + 1);
        const amount_cols = screenColCount(amount);
        const cells = self.rowCells(row) orelse return false;
        const cursor_col = screenColCount(self.cursor.col);
        const end = screenColCount(right + 1);
        const src_col = cursor_col + amount_cols;
        const move_len = end - src_col;
        const tail_start = end - amount_cols;
        const erase = self.eraseCell();
        var changed = false;
        var col = cursor_col;
        while (col < end) : (col += 1) {
            const replacement = if (col < tail_start) cells[@intCast(col + amount_cols)] else erase;
            if (!std.meta.eql(cells[@intCast(col)], replacement)) changed = true;
        }

        std.debug.assert(cursor_col <= src_col);
        std.debug.assert(src_col <= end);
        std.debug.assert(src_col + move_len == end);
        std.debug.assert(cursor_col + move_len <= cells.len);
        std.debug.assert(src_col + move_len <= cells.len);

        if (move_len > 0) {
            std.mem.copyForwards(
                Cell,
                cells[@intCast(cursor_col)..@intCast(cursor_col + move_len)],
                cells[@intCast(src_col)..@intCast(src_col + move_len)],
            );
        }
        @memset(
            cells[@intCast(tail_start)..@intCast(end)],
            erase,
        );
        changed = self.clearRowContinuation(row) or changed;
        if (changed) self.markDirtyCols(row, self.cursor.col, right);
        return changed;
    }

    fn shiftRowLeft(self: *Screen, row: u16, count: u16, left: u16, right: u16) bool {
        if (left > right or right >= self.cols) return false;

        const width = right - left + 1;
        const amount = @min(@max(count, 1), width);
        const cells = self.rowCells(row) orelse return false;
        const left_idx = screenColCount(left);
        const move_len = screenColCount(width - amount);
        const end = left_idx + screenColCount(width);
        const erase = self.eraseCell();
        var changed = false;
        var col = left_idx;
        while (col < end) : (col += 1) {
            const replacement = if (col < left_idx + move_len)
                cells[@intCast(col + screenColCount(amount))]
            else
                erase;
            if (!std.meta.eql(cells[@intCast(col)], replacement)) changed = true;
        }

        std.debug.assert(width > 0);
        std.debug.assert(amount <= width);
        std.debug.assert(right + 1 <= self.cols);
        std.debug.assert(left_idx + screenColCount(width) <= cells.len);
        std.debug.assert(left_idx + screenColCount(amount) + move_len <= cells.len);
        std.debug.assert(left_idx + move_len <= left_idx + screenColCount(width));

        if (move_len > 0) {
            const source_start = left_idx + screenColCount(amount);
            std.mem.copyForwards(
                Cell,
                cells[@intCast(left_idx)..@intCast(left_idx + move_len)],
                cells[@intCast(source_start)..@intCast(source_start + move_len)],
            );
        }
        @memset(cells[@intCast(left_idx + move_len)..@intCast(end)], erase);
        changed = self.clearRowContinuation(row) or changed;
        if (changed) self.markDirtyCols(row, left, right);
        return changed;
    }

    fn shiftRowRight(self: *Screen, row: u16, count: u16, left: u16, right: u16) bool {
        if (left > right or right >= self.cols) return false;

        const width = right - left + 1;
        const amount = @min(@max(count, 1), width);
        const cells = self.rowCells(row) orelse return false;
        const left_idx = screenColCount(left);
        const move_len = screenColCount(width - amount);
        const amount_cols = screenColCount(amount);
        const end = left_idx + screenColCount(width);
        const erase = self.eraseCell();
        var changed = false;
        var col = left_idx;
        while (col < end) : (col += 1) {
            const replacement = if (col < left_idx + amount_cols) erase else cells[@intCast(col - amount_cols)];
            if (!std.meta.eql(cells[@intCast(col)], replacement)) changed = true;
        }

        std.debug.assert(width > 0);
        std.debug.assert(amount <= width);
        std.debug.assert(right + 1 <= self.cols);
        std.debug.assert(left_idx + screenColCount(width) <= cells.len);
        std.debug.assert(left_idx + screenColCount(amount) + move_len <= cells.len);
        std.debug.assert(left_idx + screenColCount(amount) <= left_idx + screenColCount(width));

        if (move_len > 0) {
            const destination_start = left_idx + amount_cols;
            std.mem.copyBackwards(
                Cell,
                cells[@intCast(destination_start)..@intCast(destination_start + move_len)],
                cells[@intCast(left_idx)..@intCast(left_idx + move_len)],
            );
        }
        @memset(cells[@intCast(left_idx)..@intCast(left_idx + amount_cols)], erase);
        changed = self.clearRowContinuation(row) or changed;
        if (changed) self.markDirtyCols(row, left, right);
        return changed;
    }

    fn rowCells(self: *Screen, row: u16) ?[]Cell {
        const cells = self.cells orelse return null;
        const start = self.rowStart(row);
        std.debug.assert(row < self.rows);
        std.debug.assert(start + screenColCount(self.cols) <= cells.len);
        return cells[@intCast(start)..@intCast(start + screenColCount(self.cols))];
    }

    /// Write one byte per cell through the terminal's graphic write path.
    pub fn writeText(self: *Screen, text: []const u8) void {
        for (text) |byte| self.writeCell(@intCast(byte));
    }

    /// Repeat the complete bounded preceding glyph using the current rendition.
    ///
    /// A zero count has the protocol default of one. The result is false only
    /// when no preceding graphic exists; accepted repetition uses the ordinary
    /// write path and therefore owns its wrapping, insertion, and dirty facts.
    fn repeatPreceding(self: *Screen, count: u16) bool {
        const graphic = self.last_graphic orelse return false;
        var remaining = @max(count, 1);
        while (remaining > 0) : (remaining -= 1) {
            self.writeCell(graphic.codepoint);
            for (graphic.combining[0..graphic.combining_len]) |cp| self.writeCell(cp);
        }
        return true;
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
        self.last_graphic = .{ .codepoint = cp };
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
        if (self.last_graphic) |*graphic| {
            if (graphic.combining_len < graphic.combining.len) {
                graphic.combining[graphic.combining_len] = cp;
                graphic.combining_len += 1;
            }
        }
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
            self.resetRendition();
            return;
        }

        std.debug.assert(params.len <= std.math.maxInt(u8));
        const param_len: u8 = @intCast(params.len);
        var idx: u8 = 0;
        while (idx < param_len) : (idx += 1) {
            const param = params[idxOf(idx)];
            switch (param) {
                4 => self.applyUnderlineStyle(params, separators, &idx),
                38 => self.applyExtendedColor(params, separators, &idx, true),
                48 => self.applyExtendedColor(params, separators, &idx, false),
                58 => self.applyUnderlineColor(params, separators, &idx),
                else => self.applyBasicSgr(param),
            }
        }
    }

    // SGR does not own ISO or DEC character protection.
    fn resetRendition(self: *Screen) void {
        const protection = self.current_attrs.protected;
        self.current_attrs = initial_cell_attrs;
        self.current_attrs.protected = protection;
    }

    fn applyBasicSgr(self: *Screen, param: i32) void {
        switch (param) {
            0 => self.resetRendition(),
            1 => self.current_attrs.bold = true,
            2 => self.current_attrs.dim = true,
            3 => self.current_attrs.italic = true,
            5, 6 => self.current_attrs.blink = true,
            7 => self.current_attrs.reverse = true,
            8 => self.current_attrs.invisible = true,
            9 => self.current_attrs.strikethrough = true,
            10...19 => self.current_attrs.font = @intCast(param - 10),
            21 => self.setUnderline(.double),
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
            30...37 => self.current_attrs.fg = screenAnsi16Color(@intCast(param - 30)),
            39 => self.current_attrs.fg = initial_cell_attrs.fg,
            40...47 => self.current_attrs.bg = screenAnsi16Color(@intCast(param - 40)),
            49 => self.current_attrs.bg = initial_cell_attrs.bg,
            59 => self.current_attrs.underline_color = default_cell_underline_color,
            73 => self.current_attrs.baseline = .raised,
            74 => self.current_attrs.baseline = .lowered,
            75 => self.current_attrs.baseline = .normal,
            90...97 => self.current_attrs.fg = screenAnsi16Color(@intCast((param - 90) + 8)),
            100...107 => self.current_attrs.bg = screenAnsi16Color(@intCast((param - 100) + 8)),
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

    fn applyExtendedColor(
        self: *Screen,
        params: []const i32,
        separators: parser_mod.CsiSeparatorList,
        idx: *u8,
        is_fg: bool,
    ) void {
        const sgr_color = decodeExtendedColor(params, separators, idx) orelse return;
        if (is_fg) self.current_attrs.fg = sgr_color else self.current_attrs.bg = sgr_color;
    }

    fn applyUnderlineColor(
        self: *Screen,
        params: []const i32,
        separators: parser_mod.CsiSeparatorList,
        idx: *u8,
    ) void {
        const sgr_color = decodeExtendedColor(params, separators, idx) orelse return;
        self.current_attrs.underline_color = sgr_color;
    }

    /// Move forward through at most `count` tab stops, clamping at the last column.
    fn horizontalTabForward(self: *Screen, count: u16) void {
        if (self.cols == 0) return;
        const line_cols = self.lineColumnCount(self.cursor.row);
        var remaining = count;
        while (remaining > 0) : (remaining -= 1) {
            if (self.cursor.col >= line_cols - 1) break;
            var col = self.cursor.col + 1;
            while (col < line_cols and !self.tabStopAt(col)) : (col += 1) {}
            self.cursor.setColByClient(if (col < line_cols) col else line_cols - 1);
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
        if (self.tab_stops) |stops| setDefaultTabStops(stops);
    }

    /// Advance within the scroll region, scrolling it upward at its bottom edge.
    fn lineFeed(self: *Screen) void {
        if (self.rows == 0) return;
        const bottom = self.scrollBottom();
        if (self.cursor.row < bottom) {
            self.setCursorRowClamped(self.cursor.row + 1);
            return;
        }
        if (self.cursor.row == bottom) {
            self.scrollUpRegion(self.scroll_top, bottom, 1);
            return;
        }
        if (self.cursor.row < self.rows - 1) self.setCursorRowClamped(self.cursor.row + 1);
    }

    /// Move upward, scrolling the active region downward at its top edge.
    fn reverseIndex(self: *Screen) void {
        if (self.rows == 0) return;
        if (self.cursor.row == self.scroll_top) {
            self.scrollDownRegion(self.scroll_top, self.scrollBottom(), 1);
        } else {
            self.setCursorRowClamped(self.cursor.row -| 1);
        }
    }

    // DECFI advances within the cursor's horizontal region and shifts its active rows at the edge.
    fn forwardIndex(self: *Screen) bool {
        var changed = self.cancelPendingWrap();
        if (self.rows == 0 or self.cols == 0) return changed;
        const inside = self.cursorWithinHorizontalMargins();
        const right = if (inside and self.left_right_margin_mode) self.right_margin else self.cols - 1;
        if (self.cursor.col < right) {
            self.cursor.setColByClient(self.cursor.col + 1);
            return true;
        }
        if (self.cursor.col == right) {
            changed = self.shiftColumnsLeftInBounds(1, if (inside) self.leftBoundary() else 0, right) or changed;
        }
        return changed;
    }

    // DECBI retreats within the cursor's horizontal region and shifts its active rows at the edge.
    fn backIndex(self: *Screen) bool {
        var changed = self.cancelPendingWrap();
        if (self.rows == 0 or self.cols == 0) return changed;
        const inside = self.cursorWithinHorizontalMargins();
        const left = if (inside and self.left_right_margin_mode) self.left_margin else 0;
        if (self.cursor.col > left) {
            self.cursor.setColByClient(self.cursor.col - 1);
            return true;
        }
        if (self.cursor.col == left) {
            const right = if (inside and self.left_right_margin_mode) self.right_margin else self.cols - 1;
            changed = self.shiftColumnsRightInBounds(1, left, right) or changed;
        }
        return changed;
    }

    fn scrollUp(self: *Screen) void {
        const cells = self.cells orelse return;
        if (self.rows == 0 or self.cols == 0) return;
        self.markDirtyRow(self.rows - 1);
        const row_len = @as(u32, self.cols);
        self.storeHistoryRow(0);
        self.row_origin = (self.row_origin + 1) % self.rows;
        const bottom_start = self.rowStart(self.rows - 1);
        @memset(cells[@intCast(bottom_start)..@intCast(bottom_start + row_len)], blank_cell);
        self.setRowWrapped(self.rows - 1, false);
        self.resetLineGeometry(self.rows - 1);
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
    ///
    /// Every enable clears physical-row geometry, including repeated sets after
    /// a screen-bank switch. The result reports every resulting state mutation.
    fn setLeftRightMarginMode(self: *Screen, enabled: bool) bool {
        var changed = self.left_right_margin_mode != enabled;
        self.left_right_margin_mode = enabled;
        if (enabled) {
            var row: u16 = 0;
            while (row < self.rows) : (row += 1) {
                if (self.lineGeometry(row) == .single_width) continue;
                self.resetLineGeometry(row);
                changed = true;
            }
        }
        if (!enabled) {
            changed = changed or self.left_margin != 0 or self.right_margin != self.cols -| 1;
            self.left_margin = 0;
            self.right_margin = self.cols -| 1;
        }
        return changed;
    }

    /// Set ordered horizontal margins and home the cursor after a valid change.
    fn setLeftRightMargins(self: *Screen, left: u16, right: ?u16) void {
        if (!self.left_right_margin_mode or self.cols < 2) return;
        if (left >= self.cols - 1) return;
        if (right) |value| if (left >= value) return;
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
        if (!self.cursorWithinHorizontalMargins()) return;
        self.scrollDownRegion(self.cursor.row, bottom, count);
    }

    /// Delete lines at the cursor within the active vertical scroll region.
    fn deleteLines(self: *Screen, count: u16) void {
        const bottom = self.scrollBottom();
        if (self.cursor.row < self.scroll_top or self.cursor.row > bottom) return;
        if (!self.cursorWithinHorizontalMargins()) return;
        self.scrollUpRegion(self.cursor.row, bottom, count);
    }

    fn cursorWithinHorizontalMargins(self: *const Screen) bool {
        if (!self.left_right_margin_mode) return true;
        return self.cursor.col >= self.left_margin and self.cursor.col <= self.right_margin;
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
            if (left == 0 and right + 1 == self.cols) self.resetLineGeometry(clear_row);
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
            if (left == 0 and right + 1 == self.cols) self.resetLineGeometry(clear_row);
        }
    }

    fn rowStart(self: *const Screen, logical_row: u16) u32 {
        if (self.rows == 0) return 0;
        const physical_row = (self.row_origin + logical_row) % self.rows;
        return @as(u32, physical_row) * @as(u32, self.cols);
    }

    fn rowWrapIndex(self: *const Screen, logical_row: u16) ?u16 {
        if (self.row_flags == null) return null;
        if (self.rows == 0 or logical_row >= self.rows) return null;
        return (self.row_origin + logical_row) % self.rows;
    }

    /// Reports whether a visible row continues into the next row.
    pub fn rowWrapped(self: *const Screen, logical_row: u16) bool {
        const flags = self.row_flags orelse return false;
        const idx = self.rowWrapIndex(logical_row) orelse return false;
        return flags[@intCast(idx)] & row_wrapped_bit != 0;
    }

    /// Returns one visible row's DEC geometry, defaulting outside retained state.
    pub fn lineGeometry(self: *const Screen, logical_row: u16) LineGeometry {
        const flags = self.row_flags orelse return .single_width;
        const idx = self.rowWrapIndex(logical_row) orelse return .single_width;
        return @enumFromInt((flags[@intCast(idx)] & row_geometry_mask) >> row_geometry_shift);
    }

    fn setLineGeometry(self: *Screen, logical_row: u16, geometry: LineGeometry) bool {
        const flags = self.row_flags orelse return false;
        const idx = self.rowWrapIndex(logical_row) orelse return false;
        const previous = self.lineGeometry(logical_row);
        if (previous == geometry) return false;
        flags[@intCast(idx)] = (flags[@intCast(idx)] & ~row_geometry_mask) |
            (@as(u8, @intFromEnum(geometry)) << row_geometry_shift);
        const width = self.lineColumnCount(logical_row);
        if (self.cells != null and width < self.cols) self.clearRowRange(logical_row, width, self.cols);
        if (self.cursor.row == logical_row) {
            self.cursor.setColByClient(@min(self.cursor.col, width -| 1));
            self.wrap_pending = false;
        }
        self.markDirtyRow(logical_row);
        return true;
    }

    fn applyLineGeometry(self: *Screen, geometry: LineGeometry) bool {
        if (self.left_right_margin_mode) return false;
        return self.setLineGeometry(self.cursor.row, geometry);
    }

    fn resetLineGeometry(self: *Screen, row: u16) void {
        if (self.lineGeometry(row) == .single_width) return;
        std.debug.assert(self.setLineGeometry(row, .single_width));
    }

    fn alignmentDisplay(self: *Screen) bool {
        const cells = self.cells orelse return false;
        const fill = Cell{ .codepoint = 'E', .attrs = self.current_attrs };
        var row: u16 = 0;
        while (row < self.rows) : (row += 1) {
            const start = self.rowStart(row);
            const line_cols = self.lineColumnCount(row);
            @memset(cells[@intCast(start)..@intCast(start + line_cols)], fill);
            @memset(cells[@intCast(start + line_cols)..@intCast(start + self.cols)], self.eraseCell());
        }
        self.wrap_pending = false;
        if (self.row_flags) |flags| {
            for (flags) |*flag| flag.* &= ~row_wrapped_bit;
        }
        self.markAllRowsDirty();
        return true;
    }

    fn lineColumnCount(self: *const Screen, logical_row: u16) u16 {
        return switch (self.lineGeometry(logical_row)) {
            .single_width => self.cols,
            .double_width, .double_height_top, .double_height_bottom => @max(@as(u16, 1), self.cols / 2),
        };
    }

    fn setRowWrapped(self: *Screen, logical_row: u16, wrapped: bool) void {
        const flags = self.row_flags orelse return;
        const idx = self.rowWrapIndex(logical_row) orelse return;
        if (wrapped)
            flags[@intCast(idx)] |= row_wrapped_bit
        else
            flags[@intCast(idx)] &= ~row_wrapped_bit;
    }

    fn rowFlags(wrapped: bool, geometry: LineGeometry) u8 {
        return (if (wrapped) row_wrapped_bit else 0) |
            (@as(u8, @intFromEnum(geometry)) << row_geometry_shift);
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
        const flags = self.history_flags orelse return false;
        const slot = self.historySlotForRecency(history_idx) orelse return false;
        return flags[@intCast(slot)] & row_wrapped_bit != 0;
    }

    fn historyLineGeometry(self: *const Screen, history_idx: u32) LineGeometry {
        const flags = self.history_flags orelse return .single_width;
        const slot = self.historySlotForRecency(history_idx) orelse return .single_width;
        return @enumFromInt((flags[@intCast(slot)] & row_geometry_mask) >> row_geometry_shift);
    }

    /// Return the physical ring slot for the next projected history row.
    fn projectedAppendSlot(self: *const Screen) u32 {
        const capacity = self.projectedCapacity();
        if (capacity == 0) return 0;
        return (self.history_write_idx + self.history_count) % capacity;
    }

    /// Return allocated projected-history row capacity.
    fn projectedCapacity(self: *const Screen) u32 {
        const flags = self.history_flags orelse return 0;
        std.debug.assert(flags.len <= std.math.maxInt(u32));
        return @intCast(flags.len);
    }

    /// Return projected row count for `cells` at the current column width.
    fn projectedRowCountForCells(self: *const Screen, cells: []const Cell) u32 {
        return rowCountForCells(screenCount32(cells.len), self.cols);
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
        @memset(
            cells[@intCast(start + @as(u32, start_col))..@intCast(start + @as(u32, end_col_exclusive))],
            erase_cell,
        );
    }

    // Erases one bounded row range and reports exact cell mutation.
    fn eraseRowRange(
        self: *Screen,
        row: u16,
        start_col: u16,
        end_col_exclusive: u16,
        selective: bool,
    ) bool {
        const cells = self.cells orelse return false;
        const start = self.rowStart(row);
        const erase_cell = self.eraseCell();
        var changed = false;
        var col = start_col;
        while (col < end_col_exclusive) : (col += 1) {
            const cell = &cells[@intCast(start + @as(u32, col))];
            if (cell.attrs.protected == .iso or (selective and cell.attrs.protected == .dec)) continue;
            if (std.meta.eql(cell.*, erase_cell)) continue;
            cell.* = erase_cell;
            self.markDirtyCols(row, col, col);
            changed = true;
        }
        return changed;
    }

    /// Reject an inverted rectangle, then clamp it to the active origin bounds.
    pub fn rectBounds(self: *const Screen, area: RectArea) ?RectBounds {
        if (self.rows == 0 or self.cols == 0) return null;
        if (area.bottom) |bottom| if (area.top > bottom) return null;
        if (area.right) |right| if (area.left > right) return null;
        const origin = self.activeOriginBounds();
        const row_span = origin.bottom - origin.top;
        const col_span = origin.right - origin.left;
        const top = origin.top + @min(area.top, row_span);
        const bottom = origin.top + @min(area.bottom orelse row_span, row_span);
        const left = origin.left + @min(area.left, col_span);
        const right = origin.left + @min(area.right orelse col_span, col_span);
        if (top > bottom or left > right) return null;
        return .{ .top = top, .left = left, .bottom = bottom, .right = right };
    }

    // Returns the page bounds used to resolve origin-relative rectangle coordinates.
    fn activeOriginBounds(self: *const Screen) RectBounds {
        std.debug.assert(self.rows > 0 and self.cols > 0);
        const horizontal = self.origin_mode and self.left_right_margin_mode;
        return .{
            .top = if (self.origin_mode) self.scroll_top else 0,
            .left = if (horizontal) self.left_margin else 0,
            .bottom = if (self.origin_mode) self.scrollBottom() else self.rows - 1,
            .right = if (horizontal) self.right_margin else self.cols - 1,
        };
    }

    fn markDirtyRect(self: *Screen, bounds: RectBounds) void {
        var row = bounds.top;
        while (row <= bounds.bottom) : (row += 1)
            self.markDirtyCols(row, bounds.left, bounds.right);
    }

    /// Construct an empty cell carrying the current erase attributes.
    fn eraseCell(self: *const Screen) Cell {
        var attrs = self.current_attrs;
        attrs.protected = .none;
        return .{ .codepoint = 0, .attrs = attrs };
    }

    fn clearFullRow(self: *Screen, row: u16) void {
        if (self.cols == 0) return;
        self.clearRowRange(row, 0, self.cols);
        self.setRowWrapped(row, false);
        self.resetLineGeometry(row);
    }

    fn copyRow(self: *Screen, dst_row: u16, src_row: u16) void {
        const c = self.cells orelse return;
        const row_len = @as(u32, self.cols);
        const dst_start = self.rowStart(dst_row);
        const src_start = self.rowStart(src_row);
        std.mem.copyForwards(
            Cell,
            c[@intCast(dst_start)..@intCast(dst_start + row_len)],
            c[@intCast(src_start)..@intCast(src_start + row_len)],
        );
        self.copyRowFlags(dst_row, src_row);
    }

    fn copyRowRange(self: *Screen, dst_row: u16, src_row: u16, start_col: u16, end_col_exclusive: u16) void {
        const c = self.cells orelse return;
        const dst_start = self.rowStart(dst_row);
        const src_start = self.rowStart(src_row);
        const start_col32 = @as(u32, start_col);
        const end_col32 = @as(u32, end_col_exclusive);
        std.mem.copyForwards(
            Cell,
            c[@intCast(dst_start + start_col32)..@intCast(dst_start + end_col32)],
            c[@intCast(src_start + start_col32)..@intCast(src_start + end_col32)],
        );
        if (start_col == 0 and end_col_exclusive == self.cols)
            self.copyRowFlags(dst_row, src_row)
        else
            self.setRowWrapped(dst_row, false);
    }

    fn copyRowFlags(self: *Screen, dst_row: u16, src_row: u16) void {
        const flags = self.row_flags orelse return;
        const dst = self.rowWrapIndex(dst_row) orelse return;
        const src = self.rowWrapIndex(src_row) orelse return;
        flags[@intCast(dst)] = flags[@intCast(src)];
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
        self.dirty_state.rows = rowsForFull(self.rows, self.dirty_state.cols_start, self.dirty_state.cols_end);
    }
};

fn screenColCount(value: u16) u32 {
    return value;
}

fn cloneLogicalLine(allocator: std.mem.Allocator, cells: []const ScreenCell) std.mem.Allocator.Error!LogicalLine {
    var line = LogicalLine{};
    errdefer line.deinit(allocator);
    try line.cells.appendSlice(allocator, cells);
    return line;
}

fn cloneAuthorityLine(allocator: std.mem.Allocator, cells: []const ScreenCell) std.mem.Allocator.Error!HistoryLine {
    var line = HistoryLine{};
    errdefer line.deinit(allocator);
    try line.cells.appendSlice(allocator, cells);
    return line;
}

fn appendCellTextBounded(
    allocator: std.mem.Allocator,
    bytes: *std.ArrayList(u8),
    cell: ScreenCell,
    limit: usize,
) (std.mem.Allocator.Error || error{LineTooLong})!void {
    if (isCellContinuation(cell)) return;
    var encoded: [4]u8 = undefined;
    const codepoint: u21 = if (cell.codepoint == 0)
        ' '
    else
        std.math.cast(u21, cell.codepoint) orelse unreachable;
    const length = std.unicode.utf8Encode(codepoint, &encoded) catch unreachable;
    if (length > limit -| bytes.items.len) return error.LineTooLong;
    try bytes.appendSlice(allocator, encoded[0..length]);
    for (cell.combining[0..cell.combining_len]) |combining| {
        const scalar = std.math.cast(u21, combining) orelse unreachable;
        const combining_length = std.unicode.utf8Encode(scalar, &encoded) catch unreachable;
        if (combining_length > limit -| bytes.items.len) return error.LineTooLong;
        try bytes.appendSlice(allocator, encoded[0..combining_length]);
    }
}

fn cellTextByteCount(cell: ScreenCell) usize {
    if (isCellContinuation(cell)) return 0;
    var encoded: [4]u8 = undefined;
    const codepoint: u21 = if (cell.codepoint == 0)
        ' '
    else
        std.math.cast(u21, cell.codepoint) orelse unreachable;
    var count: usize = std.unicode.utf8Encode(codepoint, &encoded) catch unreachable;
    for (cell.combining[0..cell.combining_len]) |combining| {
        const scalar = std.math.cast(u21, combining) orelse unreachable;
        const length = std.unicode.utf8Encode(scalar, &encoded) catch unreachable;
        count = std.math.add(usize, count, length) catch
            @panic("resident logical output byte count overflow");
    }
    return count;
}

fn openOutputLineByteCount(screen: *const Screen) usize {
    var count: usize = 0;
    var start_row = screen.cursor.row;
    while (start_row > 0 and screen.rowWrapped(start_row - 1)) start_row -= 1;
    if (start_row == 0) {
        if (screen.open_history_line) |line| {
            for (line.cells.items) |cell| {
                count = std.math.add(usize, count, cellTextByteCount(cell)) catch
                    @panic("resident logical output byte count overflow");
            }
        }
    }
    var row = start_row;
    while (row < screen.rows) : (row += 1) {
        const content_len = screen.sourceRowContentLen(row);
        var col: u16 = 0;
        while (col < content_len) : (col += 1) {
            count = std.math.add(usize, count, cellTextByteCount(screen.cellInfoAt(row, col))) catch
                @panic("resident logical output byte count overflow");
        }
        if (!screen.rowWrapped(row)) break;
    }
    return count;
}

fn copyOpenOutputLine(
    allocator: std.mem.Allocator,
    screen: *const Screen,
    limit: usize,
) (std.mem.Allocator.Error || error{LineTooLong})![]u8 {
    var bytes = std.ArrayList(u8).empty;
    errdefer bytes.deinit(allocator);
    var start_row = screen.cursor.row;
    while (start_row > 0 and screen.rowWrapped(start_row - 1)) start_row -= 1;
    if (start_row == 0) {
        if (screen.open_history_line) |line|
            for (line.cells.items) |cell|
                try appendCellTextBounded(allocator, &bytes, cell, limit);
    }
    var row = start_row;
    while (row < screen.rows) : (row += 1) {
        const content_len = screen.sourceRowContentLen(row);
        var col: u16 = 0;
        while (col < content_len) : (col += 1) {
            try appendCellTextBounded(allocator, &bytes, screen.cellInfoAt(row, col), limit);
        }
        if (!screen.rowWrapped(row)) break;
    }
    return bytes.toOwnedSlice(allocator);
}

fn decodeExtendedColor(
    params: []const i32,
    separators: parser_mod.CsiSeparatorList,
    idx: *u8,
) ?ScreenColor {
    const next = idx.* + 1;
    if (next >= params.len) return null;
    const mode = params[idxOf(next)];
    if (separators.isSet(idx.*)) return decodeColonColor(params, separators, idx, mode);
    if (mode == 5) {
        if (idx.* + 2 >= params.len) {
            idx.* = @intCast(params.len - 1);
            return null;
        }
        idx.* += 2;
        return .indexed(clampByte(params[idxOf(idx.*)]));
    }
    if (mode == 2) {
        if (idx.* + 4 >= params.len) {
            idx.* = @intCast(params.len - 1);
            return null;
        }
        idx.* += 4;
        return ScreenColor.rgb(.{
            .r = clampByte(params[idxOf(idx.* - 2)]),
            .g = clampByte(params[idxOf(idx.* - 1)]),
            .b = clampByte(params[idxOf(idx.*)]),
        });
    }
    idx.* += 1;
    return null;
}

// Decodes one colon-delimited color group and consumes every owned subparameter.
fn decodeColonColor(
    params: []const i32,
    separators: parser_mod.CsiSeparatorList,
    idx: *u8,
    mode: i32,
) ?ScreenColor {
    var end = idx.*;
    while (end + 1 < params.len and separators.isSet(end)) end += 1;
    defer idx.* = end;

    const count = end - idx.* + 1;
    if (mode == 5) {
        if (count < 3) return null;
        return .indexed(clampByte(params[idxOf(idx.* + 2)]));
    }
    if (mode != 2 or count < 5) return null;

    // Five fields are the widespread 2:R:G:B form. Six or more carry a
    // color-space field before RGB; unsupported trailing tolerance fields are ignored.
    const red = idx.* + if (count == 5) @as(u8, 2) else 3;
    if (red + 2 > end) return null;
    return ScreenColor.rgb(.{
        .r = clampByte(params[idxOf(red)]),
        .g = clampByte(params[idxOf(red + 1)]),
        .b = clampByte(params[idxOf(red + 2)]),
    });
}

fn idxOf(value: u8) usize {
    return @intCast(value);
}

fn clampByte(value: i32) u8 {
    return @intCast(@max(0, @min(255, value)));
}

fn screenAnsi16Color(idx: u8) ScreenColor {
    return switch (idx) {
        0...15 => .indexed(idx),
        else => initial_cell_attrs.fg,
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

// Identifies the supported terminal underline rendering styles.
const ScreenUnderlineStyle = enum(u3) {
    straight,
    double,
    curly,
    dotted,
    dashed,
};

// Identifies the baseline displacement retained for one terminal cell.
const ScreenBaseline = enum(u2) {
    normal,
    raised,
    lowered,
};

// Distinguishes ISO guarded areas from DEC selective-erase protection.
const ScreenProtection = enum(u2) {
    none,
    iso,
    dec,
};

// Stores one cell's font, baseline, style, colors, protection, and hyperlink identity.
const ScreenCellAttrs = struct {
    fg: ScreenColor,
    bg: ScreenColor,
    font: u4,
    baseline: ScreenBaseline,
    bold: bool,
    dim: bool,
    italic: bool,
    blink: bool,
    blink_fast: bool,
    reverse: bool,
    invisible: bool,
    underline: bool,
    strikethrough: bool,
    underline_style: ScreenUnderlineStyle,
    underline_color: ScreenColor,
    protected: ScreenProtection,
    link_id: u32,
};

const sgr_stack_capacity = 10;
const sgr_stack_default_selection: u16 = 0b111_1111_1111;

// Retains one bounded selective rendition snapshot for XTPUSHSGR.
const SgrStackEntry = struct {
    attrs: ScreenCellAttrs = initial_cell_attrs,
    selection: u16 = 0,
};

// Stores one Unicode codepoint, display width, and complete cell attributes.
const ScreenCell = struct {
    codepoint: u32,
    combining_len: u8 = 0,
    combining: [3]u32 = .{ 0, 0, 0 },
    width: u8 = 1,
    height: u8 = 1,
    x: u8 = 0,
    y: u8 = 0,
    attrs: ScreenCellAttrs,
};

// Retains the complete bounded graphic cluster consumed by REP.
const LastGraphic = struct {
    codepoint: u21,
    combining_len: u8 = 0,
    combining: [3]u21 = .{ 0, 0, 0 },
};

fn isCellContinuation(cell: ScreenCell) bool {
    return cell.x != 0 or cell.y != 0;
}

// Provides immutable default terminal cell attributes.
const initial_cell_attrs = ScreenCellAttrs{
    .fg = default_cell_foreground,
    .bg = default_cell_background,
    .font = 0,
    .baseline = .normal,
    .bold = false,
    .dim = false,
    .italic = false,
    .blink = false,
    .blink_fast = false,
    .reverse = false,
    .invisible = false,
    .underline = false,
    .strikethrough = false,
    .underline_style = .straight,
    .underline_color = default_cell_underline_color,
    .protected = .none,
    .link_id = 0,
};

// Provides the blank default cell used for clearing and allocation.
const blank_cell = ScreenCell{
    .codepoint = 0,
    .attrs = initial_cell_attrs,
};

// Stores one exact 24-bit terminal color.
const ScreenRgb = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,
};

const Kind = enum(u8) {
    default,
    indexed,
    rgb,
};

// Stores a default, indexed, or RGB terminal color.
const ScreenColor = struct {
    kind: Kind,
    value: u32,

    /// Constructs an indexed terminal color.
    pub fn indexed(idx: u8) ScreenColor {
        return .{ .kind = .indexed, .value = idx };
    }

    /// Constructs an exact RGB terminal color.
    pub fn rgb(rgb_value: ScreenRgb) ScreenColor {
        return .{
            .kind = .rgb,
            .value = (@as(u32, rgb_value.r) << 16) | (@as(u32, rgb_value.g) << 8) | @as(u32, rgb_value.b),
        };
    }

    /// Returns RGB components only when this color is RGB.
    pub fn rgbComponents(r: u8, g: u8, b: u8) ScreenColor {
        return rgb(.{ .r = r, .g = g, .b = b });
    }

    /// Resolves this cell color against one complete terminal palette and
    /// caller-selected default without retaining either borrowed value.
    pub fn resolve(self: ScreenColor, default_value: ScreenRgb, palette: *const [256]ScreenRgb) ScreenRgb {
        return switch (self.kind) {
            .default => default_value,
            .indexed => palette[@as(u8, @intCast(self.value))],
            .rgb => .{
                .r = @truncate(self.value >> 16),
                .g = @truncate(self.value >> 8),
                .b = @truncate(self.value),
            },
        };
    }
};

// Provides the immutable default foreground color.
const default_cell_foreground = ScreenColor{ .kind = .default, .value = 0 };
// Provides the immutable default background color.
const default_cell_background = ScreenColor{ .kind = .default, .value = 0 };
// Provides the immutable default underline color.
const default_cell_underline_color = ScreenColor{ .kind = .default, .value = 0 };

// Identifies block, underline, bar, or hidden cursor presentation.
const ScreenCursorShape = enum {
    block,
    underline,
    bar,
    none,
};

// Stores cursor shape and blink state.
const ScreenCursorStyle = struct {
    shape: ScreenCursorShape,
    blink: bool,
};

// Selects a program override or restoration to configured default style.
const CursorStyleCommand = union(enum) {
    restore_default,
    program_override: ScreenCursorStyle,
};

// Provides the default blinking block cursor.
const initial_cursor_style = ScreenCursorStyle{ .shape = .block, .blink = true };

// Owns cursor position, style layers, and client-movement identity.
const ScreenSemanticCursor = struct {
    row: u16,
    col: u16,
    visible: bool,
    effective_shape: ScreenCursorShape,
    blink_intent: bool,
    default_style: ScreenCursorStyle,
    program_override_style: ?ScreenCursorStyle,
    cursor_color: ?ScreenRgb,
    cursor_text_color: ?ScreenRgb,
    position_changed_by_client_at: u64,

    /// Initializes a cursor at the origin with the supplied default style.
    pub fn init(default_style: ScreenCursorStyle) ScreenSemanticCursor {
        return .{
            .row = 0,
            .col = 0,
            .visible = true,
            .effective_shape = default_style.shape,
            .blink_intent = default_style.blink,
            .default_style = default_style,
            .program_override_style = null,
            .cursor_color = null,
            .cursor_text_color = null,
            .position_changed_by_client_at = 0,
        };
    }

    /// Returns position and style to terminal-reset defaults and advances client identity.
    pub fn reset(self: *ScreenSemanticCursor) void {
        const default_style = self.default_style;
        self.* = init(default_style);
    }

    /// Returns position and pending wrap to the alternate-screen origin.
    pub fn resetForAltEntry(self: *ScreenSemanticCursor) void {
        self.row = 0;
        self.col = 0;
        self.effective_shape = .none;
        self.blink_intent = true;
        self.program_override_style = null;
        self.position_changed_by_client_at = 0;
    }

    /// Returns the program override when present, otherwise the configured default.
    pub fn effectiveStyle(self: *const ScreenSemanticCursor) ScreenCursorStyle {
        return .{ .shape = self.effective_shape, .blink = self.blink_intent };
    }

    /// Replaces the configured default without disturbing a program override.
    pub fn setDefaultStyle(self: *ScreenSemanticCursor, style: ScreenCursorStyle) void {
        self.default_style = style;
        if (self.program_override_style == null) self.applyStyle(style);
    }

    /// Installs a program cursor-style override.
    pub fn setProgramStyle(self: *ScreenSemanticCursor, style: ScreenCursorStyle) void {
        self.program_override_style = style;
        self.applyStyle(style);
    }

    /// Replaces only the program-selected shape while preserving blink intent.
    pub fn setProgramShape(self: *ScreenSemanticCursor, shape: ScreenCursorShape) void {
        self.setProgramStyle(.{ .shape = shape, .blink = self.blink_intent });
    }

    // Replaces blink intent while preserving the active shape and style layer.
    fn setBlink(self: *ScreenSemanticCursor, enabled: bool) bool {
        if (self.blink_intent == enabled) return false;
        self.blink_intent = enabled;
        if (self.program_override_style) |*style| style.blink = enabled;
        return true;
    }

    /// Restores a previously saved effective style as the program override.
    pub fn restoreSavedStyle(self: *ScreenSemanticCursor, style: ScreenCursorStyle) void {
        self.program_override_style = if (style.shape == self.default_style.shape and
            style.blink == self.default_style.blink)
            null
        else
            style;
        self.applyStyle(style);
    }

    /// Clears the program override and exposes the configured default.
    pub fn restoreDefaultStyle(self: *ScreenSemanticCursor) void {
        self.program_override_style = null;
        self.applyStyle(self.default_style);
    }

    /// Moves to exact bounded coordinates and advances client-movement identity.
    pub fn setPositionByClient(self: *ScreenSemanticCursor, row: u16, col: u16) void {
        if (self.row != row or self.col != col) self.position_changed_by_client_at +|= 1;
        self.row = row;
        self.col = col;
    }

    /// Moves to exact bounded coordinates without changing client identity.
    pub fn setPositionStructural(self: *ScreenSemanticCursor, row: u16, col: u16) void {
        self.row = row;
        self.col = col;
    }

    /// Moves the row and advances client-movement identity.
    pub fn setRowByClient(self: *ScreenSemanticCursor, row: u16) void {
        self.setPositionByClient(row, self.col);
    }

    fn setRowStructural(self: *ScreenSemanticCursor, row: u16) void {
        self.setPositionStructural(row, self.col);
    }

    /// Moves the column and advances client-movement identity.
    pub fn setColByClient(self: *ScreenSemanticCursor, col: u16) void {
        self.setPositionByClient(self.row, col);
    }

    fn setColStructural(self: *ScreenSemanticCursor, col: u16) void {
        self.setPositionStructural(self.row, col);
    }

    fn applyStyle(self: *ScreenSemanticCursor, style: ScreenCursorStyle) void {
        self.effective_shape = style.shape;
        self.blink_intent = style.blink;
    }
};

// Borrows the dirty row interval and optional per-row column bounds.
const ScreenDirtyRows = struct {
    start_row: u16,
    end_row: u16,
    dirty_cols_start: []const u16 = &.{},
    dirty_cols_end: []const u16 = &.{},
};

// Owns dirty publication bounds for one screen allocation.
const DirtyState = struct {
    rows: ?ScreenDirtyRows = null,
    cols_start: ?[]u16 = null,
    cols_end: ?[]u16 = null,

    /// Marks every row and column dirty using caller-owned column arrays.
    pub fn initFull(row_count: u16, cols_start: ?[]u16, cols_end: ?[]u16) DirtyState {
        return .{
            .rows = rowsForFull(row_count, cols_start, cols_end),
            .cols_start = cols_start,
            .cols_end = cols_end,
        };
    }

    /// Releases optional dirty-column arrays through the screen allocator.
    pub fn deinit(self: *DirtyState, allocator: std.mem.Allocator) void {
        if (self.cols_start) |buf| allocator.free(buf);
        if (self.cols_end) |buf| allocator.free(buf);
        self.* = .{};
    }
};

// Allocates and initializes one u16 column bound per row when rows are nonzero.
fn allocDirtyCols(allocator: std.mem.Allocator, rows: u16, initial: u16) std.mem.Allocator.Error!?[]u16 {
    if (rows == 0) return null;
    const buf = try allocator.alloc(u16, rows);
    @memset(buf, initial);
    return buf;
}

// Returns a full dirty-row view when the screen has at least one row.
fn rowsForFull(rows: u16, dirty_cols_start: ?[]const u16, dirty_cols_end: ?[]const u16) ?ScreenDirtyRows {
    if (rows == 0) return null;
    return .{
        .start_row = 0,
        .end_row = rows -| 1,
        .dirty_cols_start = dirty_cols_start orelse &.{},
        .dirty_cols_end = dirty_cols_end orelse &.{},
    };
}

/// Erase extent selected by CSI display and line erase controls.
pub const ScreenEraseMode = enum(u2) {
    cursor_to_end = 0,
    start_to_cursor = 1,
    all = 2,
    scrollback = 3,
};

// Convert a checked standard-library length to the history/reflow domain.
fn screenCount32(len: usize) u32 {
    std.debug.assert(len <= std.math.maxInt(u32));
    return @intCast(len);
}

// Return rows needed for `cell_count`, or zero when no columns exist.
fn rowCountForCells(cell_count: u32, cols: u16) u32 {
    if (cols == 0) return 0;
    return @max(@as(u32, 1), std.math.divCeil(u32, cell_count, cols) catch unreachable);
}

// Owned logical terminal line used while reflowing retained content.
const LogicalLine = struct {
    cells: std.ArrayListUnmanaged(ScreenCell) = .empty,
    cursor_offset: ?u32 = null,

    /// Release cloned cells and reset the line.
    pub fn deinit(self: *LogicalLine, allocator: std.mem.Allocator) void {
        self.cells.deinit(allocator);
        self.* = .{};
    }
};

/// Owned logical-content snapshot and cursor location used by resize.
pub const LogicalSnapshot = struct {
    logical_lines: std.ArrayListUnmanaged(LogicalLine) = .empty,
    cursor_found: bool = false,
    cursor_line_index: u32 = 0,
    cursor_offset: u32 = 0,

    /// Release every cloned line and reset the snapshot.
    pub fn deinit(self: *LogicalSnapshot, allocator: std.mem.Allocator) void {
        for (self.logical_lines.items) |*line| line.deinit(allocator);
        self.logical_lines.deinit(allocator);
        self.* = .{};
    }
};

// Owns one logical history line’s cells until deinit.
const HistoryLine = struct {
    cells: std.ArrayListUnmanaged(ScreenCell) = .empty,

    /// Releases a history line’s cell allocation.
    pub fn deinit(self: *HistoryLine, allocator: std.mem.Allocator) void {
        self.cells.deinit(allocator);
        self.* = .{};
    }
};

const OutputLossReason = enum { line_too_long };

const OutputLoss = struct {
    byte_count: usize,
    reason: OutputLossReason,
};

// Owns one bounded finalized primary-screen result and its stable identity.
const OutputLine = struct {
    const Value = union(enum) {
        text: []u8,
        loss: OutputLoss,

        fn retainedBytes(self: Value) usize {
            return switch (self) {
                .text => |text| text.len,
                .loss => 0,
            };
        }
    };

    id: u64,
    value: Value,

    fn deinit(self: *OutputLine, allocator: std.mem.Allocator) void {
        switch (self.value) {
            .text => |text| allocator.free(text),
            .loss => {},
        }
        self.* = undefined;
    }
};

// Borrows one row window from a reflowed logical line.
const RewrappedRow = struct {
    start: u32,
    len: u16,
    wrapped: bool,
    geometry: Screen.LineGeometry = .single_width,
};

// Finds the logical line containing a projected row within parallel bounded arrays.
fn firstLineForRowBounded(line_row_starts: []const u32, line_row_counts: []const u16, row_index: u32) ?u32 {
    std.debug.assert(line_row_starts.len == line_row_counts.len);
    for (line_row_starts, line_row_counts, 0..) |row_start, row_count, line_idx| {
        if (row_count == 0) continue;
        if (row_index < row_start + row_count) return @intCast(line_idx);
    }
    return null;
}

// Zero-based rectangular area whose optional lower bounds extend to the page edge.
const RectArea = struct {
    top: u16,
    left: u16,
    bottom: ?u16,
    right: ?u16,
};

// Optional rectangular locator filter coordinates.
const OptionalRectArea = struct {
    top: ?u16,
    left: ?u16,
    bottom: ?u16,
    right: ?u16,
};

// Page-qualified rectangular copy request.
const RectCopy = struct {
    area: RectArea,
    source_page: u16,
    dest_top: u16,
    dest_left: u16,
    dest_page: u16,
};

/// Owned reflow rows, line projections, and projected cursor state.
pub const ReflowState = struct {
    flat_rows: std.ArrayListUnmanaged(ScreenCell) = .empty,
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

// Derived viewport window into complete reflow output.
const ViewportState = struct {
    total_rows: u32,
    visible_rows_kept: u16,
    visible_start: u32,
    first_visible_line: u32,
    hidden_rows_in_first_visible_line: u16,
};

/// Owned visible-grid buffers transferred together into a replacement Screen.
pub const ResizeBuffers = struct {
    cells: ?[]ScreenCell,
    row_flags: ?[]u8,
    dirty_state: DirtyState,
    tab_stops: ?[]bool,

    const empty: ResizeBuffers = .{
        .cells = null,
        .row_flags = null,
        .dirty_state = .{},
        .tab_stops = null,
    };

    /// Release every owned buffer and reset the value.
    pub fn deinit(self: *ResizeBuffers, allocator: std.mem.Allocator) void {
        if (self.cells) |buf| allocator.free(buf);
        if (self.row_flags) |buf| allocator.free(buf);
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
pub fn reflowLogicalLines(
    allocator: std.mem.Allocator,
    lines: LogicalSnapshot,
    cols: u16,
) std.mem.Allocator.Error!ReflowState {
    var result = ReflowState{};
    errdefer result.deinit(allocator);

    var row_cursor_base: u32 = 0;
    for (lines.logical_lines.items, 0..) |line, line_idx| {
        const rewrapped_before = result.rewrapped.items.len;
        const has_cursor = lines.cursor_found and lines.cursor_line_index == line_idx;
        const line_cursor_offset = boundedCursorOffset(line, has_cursor, lines.cursor_offset);
        const row_count: u16 = @intCast(rowCountForCells(screenCount32(line.cells.items.len), cols));
        try result.line_row_starts.append(allocator, @intCast(result.rewrapped.items.len));
        try result.line_row_counts.append(allocator, row_count);
        updateCursor(&result, row_cursor_base, line_cursor_offset, cols, has_cursor);
        try appendRewrappedRows(allocator, &result, line.cells.items, row_count, cols);
        row_cursor_base += row_count;

        std.debug.assert(result.line_row_starts.items.len == result.line_row_counts.items.len);
        std.debug.assert(result.rewrapped.items.len == rewrapped_before + row_count);
        std.debug.assert(result.rewrapped.items.len == row_cursor_base);
        std.debug.assert(result.flat_rows.items.len == result.rewrapped.items.len * screenResizeColCount(cols));
    }

    std.debug.assert(result.line_row_starts.items.len == lines.logical_lines.items.len);
    std.debug.assert(result.line_row_counts.items.len == lines.logical_lines.items.len);
    return result;
}

fn appendRewrappedRows(
    allocator: std.mem.Allocator,
    result: *ReflowState,
    cells: []const ScreenCell,
    row_count: u16,
    cols: u16,
) std.mem.Allocator.Error!void {
    if (cols == 0) return;
    if (row_count == 0) unreachable;

    const flat_rows_before = screenCount32(result.flat_rows.items.len);
    const cell_len = screenCount32(cells.len);

    var row_idx: u16 = 0;
    while (row_idx < row_count) : (row_idx += 1) {
        const start = rowStart(row_idx, cols);
        const end = @min(cell_len, start + screenResizeColCount(cols));
        std.debug.assert(start <= end);
        std.debug.assert(end <= cell_len);
        try result.rewrapped.append(allocator, .{
            .start = screenCount32(result.flat_rows.items.len),
            .len = @intCast(end - start),
            .wrapped = row_idx + 1 < row_count,
        });
        try appendRowCells(allocator, &result.flat_rows, cells, start, cols);
    }

    std.debug.assert(
        screenCount32(result.flat_rows.items.len) ==
            flat_rows_before + @as(u32, row_count) * screenResizeColCount(cols),
    );
}

fn appendRowCells(
    allocator: std.mem.Allocator,
    flat_rows: *std.ArrayListUnmanaged(ScreenCell),
    cells: []const ScreenCell,
    start: u32,
    cols: u16,
) std.mem.Allocator.Error!void {
    const cell_len = screenCount32(cells.len);
    var col_idx: u16 = 0;
    while (col_idx < cols) : (col_idx += 1) {
        const src_idx = start + @as(u32, col_idx);
        if (src_idx < cell_len) {
            try flat_rows.append(allocator, cells[@intCast(src_idx)]);
        } else {
            try flat_rows.append(allocator, blank_cell);
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

// Select the visible tail and hidden-history boundary from reflow output.
fn projectViewport(logical_line_count: u32, reflow: ReflowState, rows: u16) ViewportState {
    const total_rows: u32 = @intCast(reflow.rewrapped.items.len);
    const visible_rows_kept: u16 = @intCast(@min(@as(u32, rows), total_rows));
    const visible_start = total_rows - visible_rows_kept;
    const first_visible_line = firstLineForRowBounded(
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
        std.debug.assert(
            hidden_rows_in_first_visible_line <
                reflow.line_row_counts.items[@intCast(first_visible_line)],
        );
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
pub fn allocResizeBuffers(
    allocator: std.mem.Allocator,
    rows: u16,
    cols: u16,
    old_tab_stops: ?[]bool,
) std.mem.Allocator.Error!ResizeBuffers {
    const cell_count = resizeCellCount(rows, cols);
    var cells: ?[]ScreenCell = null;
    if (cell_count > 0) {
        const buf = try allocator.alloc(ScreenCell, cell_count);
        @memset(buf, blank_cell);
        cells = buf;
    }
    errdefer if (cells) |buf| allocator.free(buf);

    var row_flags: ?[]u8 = null;
    if (rows > 0) {
        const buf = try allocator.alloc(u8, rows);
        @memset(buf, 0);
        row_flags = buf;
    }
    errdefer if (row_flags) |buf| allocator.free(buf);

    const dirty_cols_start = try allocDirtyCols(allocator, rows, 0);
    errdefer if (dirty_cols_start) |buf| allocator.free(buf);
    const dirty_cols_end = try allocDirtyCols(allocator, rows, cols -| 1);
    errdefer if (dirty_cols_end) |buf| allocator.free(buf);
    const tab_stops = try allocTabStops(allocator, cols);
    errdefer if (tab_stops) |buf| allocator.free(buf);
    copyTabStops(tab_stops, old_tab_stops);

    std.debug.assert((cells != null) == (cell_count > 0));
    std.debug.assert((row_flags != null) == (rows > 0));
    std.debug.assert((dirty_cols_start != null) == (rows > 0));
    std.debug.assert((dirty_cols_end != null) == (rows > 0));
    std.debug.assert((tab_stops != null) == (cols > 0));
    if (cells) |buf| std.debug.assert(buf.len == cell_count);
    if (row_flags) |buf| std.debug.assert(buf.len == rows);
    if (dirty_cols_start) |buf| std.debug.assert(buf.len == rows);
    if (dirty_cols_end) |buf| std.debug.assert(buf.len == rows);
    if (tab_stops) |buf| std.debug.assert(buf.len == cols);

    return .{
        .cells = cells,
        .row_flags = row_flags,
        .dirty_state = DirtyState.initFull(rows, dirty_cols_start, dirty_cols_end),
        .tab_stops = tab_stops,
    };
}

// Copy the selected visible rows into allocated replacement buffers.
fn copyVisibleRows(buffers: *ResizeBuffers, reflow: ReflowState, viewport: ViewportState, cols: u16) void {
    const dst = buffers.cells orelse return;
    const dst_flags = buffers.row_flags orelse return;

    std.debug.assert(viewport.visible_start + viewport.visible_rows_kept <= viewport.total_rows);
    std.debug.assert(viewport.total_rows == screenCount32(reflow.rewrapped.items.len));
    std.debug.assert(screenCount32(dst_flags.len) >= viewport.visible_rows_kept);
    std.debug.assert(screenCount32(dst.len) >= resizeCellCount(viewport.visible_rows_kept, cols));
    std.debug.assert(
        screenCount32(reflow.flat_rows.items.len) ==
            screenCount32(reflow.rewrapped.items.len) * screenResizeColCount(cols),
    );

    var src_row = viewport.visible_start;
    var view_row: u16 = 0;
    while (view_row < viewport.visible_rows_kept) : (view_row += 1) {
        const src = reflow.rewrapped.items[@intCast(src_row)];
        const dst_start = rowStart(view_row, cols);
        std.debug.assert(dst_start + screenResizeColCount(cols) <= screenCount32(dst.len));
        @memcpy(
            dst[@intCast(dst_start)..@intCast(dst_start + screenResizeColCount(cols))],
            flatRowSlice(reflow.flat_rows.items, src, cols),
        );
        dst_flags[@intCast(view_row)] = Screen.rowFlags(src.wrapped, src.geometry);
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

fn flatRowSlice(flat_rows: []const ScreenCell, row: RewrappedRow, cols: u16) []const ScreenCell {
    const start = row.start;
    std.debug.assert(start + screenResizeColCount(cols) <= screenCount32(flat_rows.len));
    return flat_rows[@intCast(start)..@intCast(start + screenResizeColCount(cols))];
}

fn resizeCellCount(rows: u16, cols: u16) u32 {
    return @as(u32, rows) * @as(u32, cols);
}

fn rowStart(row: u16, cols: u16) u32 {
    return @as(u32, row) * @as(u32, cols);
}

fn screenResizeColCount(cols: u16) u32 {
    return cols;
}

// Applies bounded rectangular attribute operations to one cell in protocol order.
fn applyRectAttrOps(target: *ScreenCellAttrs, attrs: []const u16, reverse: bool) void {
    for (attrs) |attr| {
        switch (attr) {
            0 => if (!reverse) {
                target.bold = false;
                target.dim = false;
                target.italic = false;
                target.underline = false;
                target.underline_style = .straight;
                target.blink = false;
                target.blink_fast = false;
                target.reverse = false;
                target.invisible = false;
                target.strikethrough = false;
            },
            1 => {
                if (reverse) target.bold = !target.bold else target.bold = true;
            },
            2 => {
                if (reverse) target.dim = !target.dim else target.dim = true;
            },
            3 => {
                if (reverse) target.italic = !target.italic else target.italic = true;
            },
            4 => {
                if (reverse) {
                    target.underline = !target.underline;
                    if (target.underline) target.underline_style = .straight;
                } else {
                    target.underline = true;
                    target.underline_style = .straight;
                }
            },
            5 => {
                if (reverse) target.blink = !target.blink else target.blink = true;
            },
            7 => {
                if (reverse) target.reverse = !target.reverse else target.reverse = true;
            },
            8 => {
                if (reverse) target.invisible = !target.invisible else target.invisible = true;
            },
            9 => {
                if (reverse) target.strikethrough = !target.strikethrough else target.strikethrough = true;
            },
            22 => {
                if (!reverse) {
                    target.bold = false;
                    target.dim = false;
                }
            },
            23 => {
                if (!reverse) target.italic = false;
            },
            24 => {
                if (!reverse) {
                    target.underline = false;
                    target.underline_style = .straight;
                }
            },
            25 => {
                if (!reverse) {
                    target.blink = false;
                    target.blink_fast = false;
                }
            },
            27 => {
                if (!reverse) target.reverse = false;
            },
            28 => {
                if (!reverse) target.invisible = false;
            },
            29 => {
                if (!reverse) target.strikethrough = false;
            },
            else => {},
        }
    }
}

// Allocates one tab-stop flag per column and installs default stops.
fn allocTabStops(allocator: std.mem.Allocator, cols: u16) std.mem.Allocator.Error!?[]bool {
    if (cols == 0) return null;
    const buf = try allocator.alloc(bool, cols);
    setDefaultTabStops(buf);
    return buf;
}

// Replaces all stops with the terminal default every eight columns.
fn setDefaultTabStops(stops: []bool) void {
    @memset(stops, false);
    for (stops, 0..) |*stop, idx| {
        if (idx != 0 and idx % 8 == 0) stop.* = true;
    }
}

// Copies the overlapping prefix of optional old and replacement tab stops.
fn copyTabStops(dst: ?[]bool, src: ?[]const bool) void {
    const d = dst orelse return;
    const s = src orelse return;
    @memcpy(d[0..@min(d.len, s.len)], s[0..@min(d.len, s.len)]);
}

/// Caller-owned fixed storage for nonallocating input encodings.
pub const Scratch = struct {
    buf: [512]u8 = undefined,
};

// Exact failures while constructing an encoded paste result.
const PasteError = error{ LengthOverflow, OutOfMemory };

/// Encode borrowed paste text for the active bracketed-paste mode.
///
/// Plain paste returns a borrowed view of `text` without allocating. Bracketed
/// paste allocates one caller-owned result containing the fixed CSI 200/201
/// pair. Encoded-length overflow is distinct from allocator exhaustion. The
/// caller must call `Encoded.deinit` once for either successful result.
pub fn encodePaste(bracketed_paste: bool, allocator: std.mem.Allocator, text: []const u8) PasteError!Encoded {
    const start = if (bracketed_paste) "\x1b[200~" else "";
    const end = if (bracketed_paste) "\x1b[201~" else "";
    if (start.len == 0 and end.len == 0) return .{ .bytes = text };

    const encoded_len = try bracketedPasteLength(text.len);
    const out = try allocator.alloc(u8, encoded_len);
    std.debug.assert(out.len == encoded_len);
    @memcpy(out[0..start.len], start);
    @memcpy(out[start.len .. start.len + text.len], text);
    @memcpy(out[start.len + text.len ..], end);
    return .{ .allocator = allocator, .bytes = out };
}

fn bracketedPasteLength(text_len: usize) error{LengthOverflow}!usize {
    const with_start = std.math.add(usize, "\x1b[200~".len, text_len) catch return error.LengthOverflow;
    return std.math.add(usize, with_start, "\x1b[201~".len) catch return error.LengthOverflow;
}

// Copy fixed protocol bytes into caller scratch storage.
//
// The returned slice borrows `scratch` until its next use.
fn writeScratch(scratch: *Scratch, bytes: []const u8) []const u8 {
    std.debug.assert(bytes.len <= scratch.buf.len);
    @memcpy(scratch.buf[0..bytes.len], bytes);
    return scratch.buf[0..bytes.len];
}

test "bracketed paste length reports arithmetic overflow" {
    try std.testing.expectEqual(@as(usize, 15), try bracketedPasteLength(3));
    try std.testing.expectError(error.LengthOverflow, bracketedPasteLength(std.math.maxInt(usize)));
}

// Holds encoded bytes that either borrow caller scratch or own one allocation.
const Encoded = struct {
    allocator: ?std.mem.Allocator = null,
    bytes: []const u8 = "",

    /// Release owned bytes, or only clear a borrowed result.
    ///
    /// Every successful input encoding result accepts one call. The value is
    /// reset afterward so it retains neither ownership nor a borrowed slice.
    pub fn deinit(self: *Encoded) void {
        if (self.allocator) |allocator| allocator.free(self.bytes);
        self.* = .{};
    }
};

test "encoded owner deinit releases owned buffer" {
    const allocator = std.testing.allocator;
    const bytes = try allocator.dupe(u8, "payload");
    var encoded: Encoded = .{ .allocator = allocator, .bytes = bytes };

    encoded.deinit();

    try std.testing.expectEqual(@as(?std.mem.Allocator, null), encoded.allocator);
    try std.testing.expectEqualStrings("", encoded.bytes);
}

// Borrow-free physical key event with typed identity and complete modifiers.
const KeyEvent = struct {
    key: InputKey,
    mods: Modifier = .{},
    action: Action = .press,
    shifted: ?u21 = null,
    alternate: ?u21 = null,
    /// Borrows the exact bytes used only by legacy terminal encoding.
    legacy_text: []const u8 = "",
    /// Borrows committed text for this press/repeat until encoding returns.
    text: []const u8 = "",
};

// Identifies host focus gained or lost for terminal focus reporting.
const FocusEvent = enum {
    in,
    out,
};

// Host input borrowed by one terminal encoding call.
//
// `bytes` carries committed text, while `key` carries a named or validated
// Unicode physical-key event for terminal keyboard protocol encoding. Byte
// and paste slices must remain valid until `Terminal.encodeInput` returns.
const Event = union(enum) {
    bytes: []const u8,
    key: KeyEvent,
    mouse: MouseEvent,
    focus: FocusEvent,
    paste: []const u8,
};

test "event owner exposes input union tags" {
    const key_event: Event = .{ .key = .{ .key = .{ .named = .enter } } };
    const focus_event: Event = .{ .focus = .in };

    try std.testing.expectEqual(@as(std.meta.Tag(Event), .key), std.meta.activeTag(key_event));
    try std.testing.expectEqual(@as(std.meta.Tag(Event), .focus), std.meta.activeTag(focus_event));
}

// Named physical key whose terminal identity is distinct from Unicode text.
const KeyName = enum {
    enter,
    tab,
    backspace,
    escape,
    up,
    down,
    left,
    right,
    insert,
    delete,
    home,
    end,
    page_up,
    page_down,
    left_shift,
    right_shift,
    left_control,
    right_control,
    left_alt,
    right_alt,
    left_super,
    right_super,
    left_hyper,
    right_hyper,
    left_meta,
    right_meta,
    caps_lock,
    num_lock,
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
    keypad_0,
    keypad_1,
    keypad_2,
    keypad_3,
    keypad_4,
    keypad_5,
    keypad_6,
    keypad_7,
    keypad_8,
    keypad_9,
    keypad_decimal,
    keypad_add,
    keypad_subtract,
    keypad_multiply,
    keypad_divide,
    keypad_separator,
    keypad_equal,
    keypad_enter,
};

/// Valid Unicode scalar produced by one physical key event.
const UnicodeScalar = struct {
    value: u21,

    /// Validate one scalar before it enters terminal keyboard encoding.
    ///
    /// Surrogate halves and values outside Unicode's scalar range are rejected.
    fn init(value: u21) error{InvalidUnicodeScalar}!UnicodeScalar {
        if (!std.unicode.utf8ValidCodepoint(value)) return error.InvalidUnicodeScalar;
        return .{ .value = value };
    }
};

/// Physical key identity consumed by terminal keyboard protocols.
pub const InputKey = union(enum) {
    named: KeyName,
    unicode: UnicodeScalar,

    /// Construct a Unicode key, rejecting non-scalar values.
    pub fn initUnicode(value: u21) error{InvalidUnicodeScalar}!InputKey {
        return .{ .unicode = try UnicodeScalar.init(value) };
    }
};

// Identifies one physical key transition for Kitty event reporting.
const Action = enum(u2) { press = 1, repeat = 2, release = 3 };

/// Bounds committed key text before decimal Kitty encoding.
pub const max_text_bytes: u8 = 64;

/// Complete modifier state accepted by terminal keyboard and mouse protocols.
///
/// The packed representation has no spare bits, so every value is valid.
pub const Modifier = packed struct(u8) {
    shift: bool = false,
    alt: bool = false,
    control: bool = false,
    super: bool = false,
    hyper: bool = false,
    meta: bool = false,
    caps_lock: bool = false,
    num_lock: bool = false,

    fn protocolBits(self: Modifier) u8 {
        return @bitCast(self);
    }

    fn protocolParameter(self: Modifier) u16 {
        return 1 + @as(u16, self.protocolBits());
    }

    fn none(self: Modifier) bool {
        return self.protocolBits() == 0;
    }

    fn legacy(self: Modifier) Modifier {
        return .{ .shift = self.shift, .alt = self.alt, .control = self.control };
    }
};

const max_encoded_len: usize = 32;
// One-byte UTF-8 scalars maximize decimal text bytes: three digits plus one
// separator per source byte. The remaining fields use their exact maxima.
const max_associated_encoded_bytes: usize = @as(usize, max_text_bytes) * 4;
/// Bounds one complete Kitty key encoding under the 64-byte text limit.
pub const max_kitty_encoded_bytes: usize = 2 + 7 + 1 + 7 + 1 + 7 +
    1 + 3 + 1 + 1 + max_associated_encoded_bytes + 1;

/// Encode one host key for the active terminal keyboard modes.
pub fn encodeKey(
    buf: []u8,
    key: InputKey,
    mod: Modifier,
    application_cursor_keys: bool,
    application_keypad: bool,
    modify_other_keys: i8,
    format_other_keys: u16,
    kitty_keyboard_flags: u8,
) []const u8 {
    const report_all = kitty_keyboard_flags & 8 != 0;
    const disambiguate = kitty_keyboard_flags & 1 != 0;
    if (report_all) {
        if (encodeKittyKey(buf, key, mod)) |encoded| return encoded;
    } else if (disambiguate) {
        if (encodeDisambiguatedKey(buf, key, mod)) |encoded| return encoded;
    }
    const legacy_mod = mod.legacy();
    return switch (key) {
        .named => |named| encodeNamedKey(buf, named, legacy_mod, application_cursor_keys, application_keypad),
        .unicode => |scalar| encodeTextKey(buf, scalar.value, legacy_mod, modify_other_keys, format_other_keys),
    };
}

/// Encodes one complete physical key fact under current terminal modes.
pub fn encodeEvent(
    buf: []u8,
    key: InputKey,
    mod: Modifier,
    action: Action,
    shifted: ?u21,
    alternate: ?u21,
    legacy_text: []const u8,
    text: []const u8,
    application_cursor_keys: bool,
    application_keypad: bool,
    modify_other_keys: i8,
    format_other_keys: u16,
    kitty_flags: u8,
) error{ InvalidUtf8, InvalidText, KeyTextLimit, EncodingLimit }![]const u8 {
    if (text.len > max_text_bytes) return error.KeyTextLimit;
    if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8;
    if (kitty_flags & 16 != 0 and kitty_flags & 8 != 0) {
        var text_view = std.unicode.Utf8View.initUnchecked(text);
        var text_iterator = text_view.iterator();
        while (text_iterator.nextCodepoint()) |codepoint|
            if (codepoint < 32 or (codepoint >= 127 and codepoint <= 159))
                return error.InvalidText;
    }
    const report_all = kitty_flags & 8 != 0;
    if (key == .named and isModifier(key.named) and !report_all)
        return buf[0..0];
    if (key == .named and isLegacyControl(key.named) and !report_all and mod.none()) {
        if (action == .release) return buf[0..0];
        return encodeKey(
            buf,
            key,
            mod,
            application_cursor_keys,
            application_keypad,
            modify_other_keys,
            format_other_keys,
            0,
        );
    }
    const report_events = kitty_flags & 2 != 0;
    if (action == .release and !report_events) return buf[0..0];
    if (legacy_text.len != 0 and !report_all and action != .release)
        return legacy_text;
    if (kitty_flags & (2 | 4 | 8 | 16) != 0)
        return try encodeKittyEvent(buf, key, mod, action, shifted, alternate, text, kitty_flags);
    return encodeKey(
        buf,
        legacyKey(key, mod, shifted),
        mod,
        application_cursor_keys,
        application_keypad,
        modify_other_keys,
        format_other_keys,
        kitty_flags,
    );
}

// Legacy terminals consume the produced Shift identity, while extended key
// protocols retain physical, shifted, and alternate identities separately.
fn legacyKey(key: InputKey, mod: Modifier, shifted: ?u21) InputKey {
    if (!mod.shift) return key;
    return switch (key) {
        .named => key,
        .unicode => if (shifted) |value| InputKey.initUnicode(value) catch key else key,
    };
}

fn isLegacyControl(key: KeyName) bool {
    return key == .enter or key == .tab or key == .backspace;
}

fn isModifier(key: KeyName) bool {
    return switch (key) {
        .left_shift,
        .right_shift,
        .left_control,
        .right_control,
        .left_alt,
        .right_alt,
        .left_super,
        .right_super,
        .left_hyper,
        .right_hyper,
        .left_meta,
        .right_meta,
        .caps_lock,
        .num_lock,
        => true,
        else => false,
    };
}

fn encodeKittyEvent(
    buf: []u8,
    key: InputKey,
    mod: Modifier,
    action: Action,
    shifted: ?u21,
    alternate: ?u21,
    text: []const u8,
    flags: u8,
) error{EncodingLimit}![]const u8 {
    if (buf.len < max_kitty_encoded_bytes) return error.EncodingLimit;
    var builder = Builder.init(buf);
    try builder.append("\x1b[");
    const identity = kittyIdentityForKey(key);
    try builder.decimal(identity.code);
    if (flags & 4 != 0 and (shifted != null or alternate != null)) {
        try builder.append(":");
        if (shifted) |value| try builder.decimal(value);
        if (alternate) |value| {
            try builder.append(":");
            try builder.decimal(value);
        }
    }
    const add_action = flags & 2 != 0 and action != .press;
    const add_text = flags & 16 != 0 and flags & 8 != 0 and text.len != 0;
    if (!mod.none() or add_action or add_text) {
        try builder.append(";");
        if (!mod.none() or add_action) try builder.decimal(mod.protocolParameter());
        if (add_action) {
            try builder.append(":");
            try builder.decimal(@intFromEnum(action));
        }
    }
    if (add_text) {
        var view = std.unicode.Utf8View.initUnchecked(text);
        var iterator = view.iterator();
        var first = true;
        while (iterator.nextCodepoint()) |codepoint| {
            try builder.append(if (first) ";" else ":");
            first = false;
            try builder.decimal(codepoint);
        }
    }
    try builder.append(&.{identity.trailer});
    return builder.written();
}

const KittyIdentity = struct { code: u32, trailer: u8 = 'u' };

fn kittyIdentityForKey(key: InputKey) KittyIdentity {
    return switch (key) {
        .unicode => |scalar| .{ .code = scalar.value },
        .named => |named| switch (named) {
            .escape => .{ .code = 27 },
            .enter => .{ .code = 13 },
            .tab => .{ .code = 9 },
            .backspace => .{ .code = 127 },
            .insert => .{ .code = 2, .trailer = '~' },
            .delete => .{ .code = 3, .trailer = '~' },
            .up => .{ .code = 1, .trailer = 'A' },
            .down => .{ .code = 1, .trailer = 'B' },
            .right => .{ .code = 1, .trailer = 'C' },
            .left => .{ .code = 1, .trailer = 'D' },
            .home => .{ .code = 1, .trailer = 'H' },
            .end => .{ .code = 1, .trailer = 'F' },
            .page_up => .{ .code = 5, .trailer = '~' },
            .page_down => .{ .code = 6, .trailer = '~' },
            .f1 => .{ .code = 1, .trailer = 'P' },
            .f2 => .{ .code = 1, .trailer = 'Q' },
            .f3 => .{ .code = 13, .trailer = '~' },
            .f4 => .{ .code = 1, .trailer = 'S' },
            .f5 => .{ .code = 15, .trailer = '~' },
            .f6 => .{ .code = 17, .trailer = '~' },
            .f7 => .{ .code = 18, .trailer = '~' },
            .f8 => .{ .code = 19, .trailer = '~' },
            .f9 => .{ .code = 20, .trailer = '~' },
            .f10 => .{ .code = 21, .trailer = '~' },
            .f11 => .{ .code = 23, .trailer = '~' },
            .f12 => .{ .code = 24, .trailer = '~' },
            .keypad_0 => .{ .code = 57399 },
            .keypad_1 => .{ .code = 57400 },
            .keypad_2 => .{ .code = 57401 },
            .keypad_3 => .{ .code = 57402 },
            .keypad_4 => .{ .code = 57403 },
            .keypad_5 => .{ .code = 57404 },
            .keypad_6 => .{ .code = 57405 },
            .keypad_7 => .{ .code = 57406 },
            .keypad_8 => .{ .code = 57407 },
            .keypad_9 => .{ .code = 57408 },
            .keypad_decimal => .{ .code = 57409 },
            .keypad_divide => .{ .code = 57410 },
            .keypad_multiply => .{ .code = 57411 },
            .keypad_subtract => .{ .code = 57412 },
            .keypad_add => .{ .code = 57413 },
            .keypad_enter => .{ .code = 57414 },
            .keypad_equal => .{ .code = 57415 },
            .keypad_separator => .{ .code = 57416 },
            .left_shift => .{ .code = 57441 },
            .left_control => .{ .code = 57442 },
            .left_alt => .{ .code = 57443 },
            .left_super => .{ .code = 57444 },
            .right_shift => .{ .code = 57447 },
            .right_control => .{ .code = 57448 },
            .right_alt => .{ .code = 57449 },
            .right_super => .{ .code = 57450 },
            .left_hyper => .{ .code = 57445 },
            .left_meta => .{ .code = 57446 },
            .right_hyper => .{ .code = 57451 },
            .right_meta => .{ .code = 57452 },
            .caps_lock => .{ .code = 57358 },
            .num_lock => .{ .code = 57360 },
        },
    };
}

const Builder = struct {
    bytes: []u8,
    len: usize = 0,

    fn init(bytes: []u8) Builder {
        return .{ .bytes = bytes };
    }

    fn append(self: *Builder, bytes: []const u8) error{EncodingLimit}!void {
        if (self.len > self.bytes.len or bytes.len > self.bytes.len - self.len)
            return error.EncodingLimit;
        @memcpy(self.bytes[self.len .. self.len + bytes.len], bytes);
        self.len += bytes.len;
    }

    fn decimal(self: *Builder, value: u32) error{EncodingLimit}!void {
        const digits = std.fmt.bufPrint(self.bytes[self.len..], "{d}", .{value}) catch
            return error.EncodingLimit;
        self.len += digits.len;
    }

    fn written(self: *const Builder) []const u8 {
        return self.bytes[0..self.len];
    }
};

fn encodeDisambiguatedKey(buf: []u8, key: InputKey, mod: Modifier) ?[]const u8 {
    return switch (key) {
        .unicode => null,
        .named => |named| switch (named) {
            .escape => csiU(buf, 27, mod.protocolParameter()),
            .enter, .tab, .backspace => if (mod.none()) null else encodeKittyKey(buf, key, mod),
            else => encodeKittyKey(buf, key, mod),
        },
    };
}

fn encodeNamedKey(
    buf: []u8,
    key: KeyName,
    mod: Modifier,
    application_cursor_keys: bool,
    application_keypad: bool,
) []const u8 {
    if (encodeKeypadKey(buf, key, application_keypad)) |encoded| return encoded;
    if (encodeControlKey(buf, key, mod)) |encoded| return encoded;
    if (encodeCursorKey(buf, key, mod, application_cursor_keys)) |encoded| return encoded;
    if (encodeHomeEndKey(buf, key, mod, application_cursor_keys)) |encoded| return encoded;
    if (encodeTildeKey(buf, key, mod)) |encoded| return encoded;
    if (encodeFunctionKey(buf, key, mod)) |encoded| return encoded;
    return buf[0..0];
}

fn encodeKeypadKey(buf: []u8, key: KeyName, application_keypad: bool) ?[]const u8 {
    const normal: ?u8 = switch (key) {
        .keypad_0 => '0',
        .keypad_1 => '1',
        .keypad_2 => '2',
        .keypad_3 => '3',
        .keypad_4 => '4',
        .keypad_5 => '5',
        .keypad_6 => '6',
        .keypad_7 => '7',
        .keypad_8 => '8',
        .keypad_9 => '9',
        .keypad_decimal => '.',
        .keypad_add => '+',
        .keypad_subtract => '-',
        .keypad_multiply => '*',
        .keypad_divide => '/',
        .keypad_separator => ',',
        .keypad_equal => '=',
        .keypad_enter => '\r',
        else => null,
    };
    const ch = normal orelse return null;
    if (!application_keypad) {
        std.debug.assert(buf.len >= 1);
        buf[0] = ch;
        return buf[0..1];
    }
    const final: u8 = switch (key) {
        .keypad_0 => 'p',
        .keypad_1 => 'q',
        .keypad_2 => 'r',
        .keypad_3 => 's',
        .keypad_4 => 't',
        .keypad_5 => 'u',
        .keypad_6 => 'v',
        .keypad_7 => 'w',
        .keypad_8 => 'x',
        .keypad_9 => 'y',
        .keypad_decimal => 'n',
        .keypad_add => 'k',
        .keypad_subtract => 'm',
        .keypad_multiply => 'j',
        .keypad_divide => 'o',
        .keypad_separator => 'l',
        .keypad_equal => 'X',
        .keypad_enter => 'M',
        else => return null,
    };
    std.debug.assert(buf.len >= 3);
    buf[0] = '\x1b';
    buf[1] = 'O';
    buf[2] = final;
    return buf[0..3];
}

fn encodeModifyOtherKey(
    buf: []u8,
    codepoint: u21,
    mod: Modifier,
    modify_other_keys: i8,
    format_other_keys: u16,
) ?[]const u8 {
    if (modify_other_keys < 2 and !(modify_other_keys == 1 and format_other_keys == 1)) return null;
    if (mod.none() and modify_other_keys < 3) return null;
    if (format_other_keys == 1) {
        return std.fmt.bufPrint(
            buf,
            "\x1b[{d};{d}u",
            .{ codepoint, mod.protocolParameter() },
        ) catch null;
    }
    return std.fmt.bufPrint(buf, "\x1b[27;{d};{d}~", .{ mod.protocolParameter(), codepoint }) catch null;
}

fn encodeKittyKey(buf: []u8, key: InputKey, mod: Modifier) ?[]const u8 {
    const modifier = mod.protocolParameter();
    return switch (key) {
        .unicode => |scalar| csiU(buf, scalar.value, modifier),
        .named => |named| switch (named) {
            .enter => csiU(buf, 13, modifier),
            .tab => csiU(buf, 9, modifier),
            .backspace => csiU(buf, 127, modifier),
            .escape => csiU(buf, 27, modifier),
            .up => csiFinal(buf, 'A', modifier),
            .down => csiFinal(buf, 'B', modifier),
            .right => csiFinal(buf, 'C', modifier),
            .left => csiFinal(buf, 'D', modifier),
            .home => csiFinal(buf, 'H', modifier),
            .end => csiFinal(buf, 'F', modifier),
            .f1 => csiFinal(buf, 'P', modifier),
            .f2 => csiFinal(buf, 'Q', modifier),
            .f3 => csiTilde(buf, 13, modifier),
            .f4 => csiFinal(buf, 'S', modifier),
            .insert => csiTilde(buf, 2, modifier),
            .delete => csiTilde(buf, 3, modifier),
            .page_up => csiTilde(buf, 5, modifier),
            .page_down => csiTilde(buf, 6, modifier),
            .f5 => csiTilde(buf, 15, modifier),
            .f6 => csiTilde(buf, 17, modifier),
            .f7 => csiTilde(buf, 18, modifier),
            .f8 => csiTilde(buf, 19, modifier),
            .f9 => csiTilde(buf, 20, modifier),
            .f10 => csiTilde(buf, 21, modifier),
            .f11 => csiTilde(buf, 23, modifier),
            .f12 => csiTilde(buf, 24, modifier),
            else => null,
        },
    };
}

fn encodeControlKey(buf: []u8, key: KeyName, mod: Modifier) ?[]const u8 {
    const bytes = switch (key) {
        .enter => "\r",
        .tab => if (mod.shift) "\x1b[Z" else "\t",
        .backspace => "\x7f",
        .escape => "\x1b",
        else => null,
    } orelse return null;
    if (!mod.alt) return writeBytes(buf, bytes);
    buf[0] = '\x1b';
    @memcpy(buf[1 .. bytes.len + 1], bytes);
    return buf[0 .. bytes.len + 1];
}

fn encodeCursorKey(buf: []u8, key: KeyName, mod: Modifier, application_cursor_keys: bool) ?[]const u8 {
    const final: u8 = switch (key) {
        .up => 'A',
        .down => 'B',
        .right => 'C',
        .left => 'D',
        else => return null,
    };
    return if (!mod.none())
        csi1ModifiedFinal(buf, final, mod)
    else if (application_cursor_keys)
        fixed3(buf, '\x1b', 'O', final)
    else
        fixed3(buf, '\x1b', '[', final);
}

fn encodeHomeEndKey(buf: []u8, key: KeyName, mod: Modifier, application_cursor_keys: bool) ?[]const u8 {
    const final: u8 = switch (key) {
        .home => 'H',
        .end => 'F',
        else => return null,
    };
    return if (!mod.none())
        csi1ModifiedFinal(buf, final, mod)
    else if (application_cursor_keys)
        fixed3(buf, '\x1b', 'O', final)
    else
        fixed3(buf, '\x1b', '[', final);
}

fn encodeTildeKey(buf: []u8, key: KeyName, mod: Modifier) ?[]const u8 {
    const code: u8 = switch (key) {
        .insert => 2,
        .delete => 3,
        .page_up => 5,
        .page_down => 6,
        .f5 => 15,
        .f6 => 17,
        .f7 => 18,
        .f8 => 19,
        .f9 => 20,
        .f10 => 21,
        .f11 => 23,
        .f12 => 24,
        else => return null,
    };
    return if (!mod.none())
        csiTildeModified(buf, code, mod)
    else
        csiTildePlain(buf, code);
}

fn encodeFunctionKey(buf: []u8, key: KeyName, mod: Modifier) ?[]const u8 {
    const final: u8 = switch (key) {
        .f1 => 'P',
        .f2 => 'Q',
        .f3 => 'R',
        .f4 => 'S',
        else => return null,
    };
    return if (!mod.none())
        csi1ModifiedFinal(buf, final, mod)
    else
        fixed3(buf, '\x1b', 'O', final);
}

fn encodeTextKey(buf: []u8, codepoint: u21, mod: Modifier, modify_other_keys: i8, format_other_keys: u16) []const u8 {
    if (codepoint > 31 and codepoint < 127) {
        if (encodeModifyOtherKey(buf, codepoint, mod, modify_other_keys, format_other_keys)) |encoded| return encoded;
    }
    if (mod.control) if (legacyControlByte(codepoint)) |byte| {
        if (!mod.alt) return writeBytes(buf, &.{byte});
        buf[0] = '\x1b';
        buf[1] = byte;
        return buf[0..2];
    };
    const prefix_len: usize = @intFromBool(mod.alt);
    if (mod.alt) buf[0] = '\x1b';
    if (codepoint > 31 and codepoint < 127) {
        buf[prefix_len] = @intCast(codepoint);
        return buf[0 .. prefix_len + 1];
    }
    if (codepoint > 127) {
        const len = std.unicode.utf8Encode(codepoint, buf[prefix_len..]) catch unreachable;
        std.debug.assert(prefix_len + len <= buf.len);
        return buf[0 .. prefix_len + len];
    }
    return buf[0..0];
}

fn writeBytes(buf: []u8, bytes: []const u8) []const u8 {
    std.debug.assert(bytes.len <= buf.len);
    @memcpy(buf[0..bytes.len], bytes);
    return buf[0..bytes.len];
}

// ASCII control chords are legacy byte semantics; lock state has already been
// removed by Modifier.legacy and remains available only to extended protocols.
fn legacyControlByte(codepoint: u21) ?u8 {
    return switch (codepoint) {
        ' ' => 0,
        '@'...'_' => @intCast(codepoint - '@'),
        'a'...'z' => @intCast(codepoint - 'a' + 1),
        '?' => 0x7f,
        else => null,
    };
}

fn singleByte(buf: []u8, byte: u8) ?[]const u8 {
    std.debug.assert(buf.len >= 1);
    buf[0] = byte;
    return buf[0..1];
}

fn fixed3(buf: []u8, a: u8, b: u8, c: u8) []const u8 {
    std.debug.assert(buf.len >= 3);
    buf[0] = a;
    buf[1] = b;
    buf[2] = c;
    return buf[0..3];
}

fn csi1ModifiedFinal(buf: []u8, final: u8, mod: Modifier) []const u8 {
    std.debug.assert(buf.len >= 6);
    buf[0] = '\x1b';
    buf[1] = '[';
    buf[2] = '1';
    buf[3] = ';';
    buf[4] = modifierParamDigit(mod);
    buf[5] = final;
    return buf[0..6];
}

fn csiTildePlain(buf: []u8, code: u8) []const u8 {
    std.debug.assert(buf.len >= 5);
    const tens = if (code >= 10) '0' + @divTrunc(code, 10) else null;
    buf[0] = '\x1b';
    buf[1] = '[';
    if (tens) |digit| {
        buf[2] = digit;
        buf[3] = '0' + @mod(code, 10);
        buf[4] = '~';
        return buf[0..5];
    }
    buf[2] = '0' + code;
    buf[3] = '~';
    return buf[0..4];
}

fn csiTildeModified(buf: []u8, code: u8, mod: Modifier) []const u8 {
    std.debug.assert(buf.len >= 7);
    const tens = if (code >= 10) '0' + @divTrunc(code, 10) else null;
    buf[0] = '\x1b';
    buf[1] = '[';
    if (tens) |digit| {
        buf[2] = digit;
        buf[3] = '0' + @mod(code, 10);
        buf[4] = ';';
        buf[5] = modifierParamDigit(mod);
        buf[6] = '~';
        return buf[0..7];
    }
    buf[2] = '0' + code;
    buf[3] = ';';
    buf[4] = modifierParamDigit(mod);
    buf[5] = '~';
    return buf[0..6];
}

fn modifierParamDigit(mod: Modifier) u8 {
    return '0' + @as(u8, @intCast(mod.legacy().protocolParameter()));
}

fn csiU(buf: []u8, code: u32, modifier: u16) []const u8 {
    return if (modifier == 1)
        std.fmt.bufPrint(buf, "\x1b[{d}u", .{code}) catch ""
    else
        std.fmt.bufPrint(buf, "\x1b[{d};{d}u", .{ code, modifier }) catch "";
}

fn csiFinal(buf: []u8, final: u8, modifier: u16) []const u8 {
    return if (modifier == 1)
        std.fmt.bufPrint(buf, "\x1b[{c}", .{final}) catch ""
    else
        std.fmt.bufPrint(buf, "\x1b[1;{d}{c}", .{ modifier, final }) catch "";
}

fn csiTilde(buf: []u8, code: u32, modifier: u16) []const u8 {
    return if (modifier == 1)
        std.fmt.bufPrint(buf, "\x1b[{d}~", .{code}) catch ""
    else
        std.fmt.bufPrint(buf, "\x1b[{d};{d}~", .{ code, modifier }) catch "";
}

test "typed key identity separates old integer collisions" {
    var buf: [max_encoded_len]u8 = undefined;
    const none = Modifier{};
    const unicode_soh = try InputKey.initUnicode(1);

    try std.testing.expectEqualStrings("\r", encodeKey(&buf, .{ .named = .enter }, none, false, false, 0, 0, 0));
    try std.testing.expectEqualStrings("", encodeKey(&buf, unicode_soh, none, false, false, 0, 0, 0));
    try std.testing.expectEqualStrings("\x1b[1u", encodeKey(&buf, unicode_soh, none, false, false, 0, 0, 8));
    try std.testing.expectError(error.InvalidUnicodeScalar, InputKey.initUnicode(0xD800));
}

test "named key classes retain exact legacy encodings" {
    var buf: [max_encoded_len]u8 = undefined;
    const none = Modifier{};

    try std.testing.expectEqualStrings("\t", encodeKey(&buf, .{ .named = .tab }, none, false, false, 0, 0, 0));
    try std.testing.expectEqualStrings("\x1b[H", encodeKey(&buf, .{ .named = .home }, none, false, false, 0, 0, 0));
    try std.testing.expectEqualStrings("\x1b[3~", encodeKey(&buf, .{ .named = .delete }, none, false, false, 0, 0, 0));
    try std.testing.expectEqualStrings("\x1bOP", encodeKey(&buf, .{ .named = .f1 }, none, false, false, 0, 0, 0));
    try std.testing.expectEqualStrings("\x1b[24~", encodeKey(&buf, .{ .named = .f12 }, none, false, false, 0, 0, 0));
    try std.testing.expectEqualStrings("+", encodeKey(&buf, .{ .named = .keypad_add }, none, false, false, 0, 0, 0));
    try std.testing.expectEqualStrings(
        "\x1bOk",
        encodeKey(&buf, .{ .named = .keypad_add }, none, false, true, 0, 0, 0),
    );
    try std.testing.expectEqualStrings(
        ",",
        encodeKey(&buf, .{ .named = .keypad_separator }, none, false, false, 0, 0, 0),
    );
    try std.testing.expectEqualStrings(
        "\x1bOl",
        encodeKey(&buf, .{ .named = .keypad_separator }, none, false, true, 0, 0, 0),
    );
    try std.testing.expectEqualStrings(
        "=",
        encodeKey(&buf, .{ .named = .keypad_equal }, none, false, false, 0, 0, 0),
    );
    try std.testing.expectEqualStrings(
        "\x1bOX",
        encodeKey(&buf, .{ .named = .keypad_equal }, none, false, true, 0, 0, 0),
    );
    try std.testing.expectEqualStrings("", encodeKey(&buf, .{ .named = .left_shift }, none, false, false, 0, 0, 0));
}

test "legacy keys preserve application modes modifiers and text boundaries" {
    var buf: [max_encoded_len]u8 = undefined;
    const none = Modifier{};

    try std.testing.expectEqualStrings("\x1bOA", encodeKey(&buf, .{ .named = .up }, none, true, false, 0, 0, 0));
    try std.testing.expectEqualStrings("\x1bOH", encodeKey(&buf, .{ .named = .home }, none, true, false, 0, 0, 0));
    try std.testing.expectEqualStrings("\x1bOF", encodeKey(&buf, .{ .named = .end }, none, true, false, 0, 0, 0));
    try std.testing.expectEqualStrings("\x1bOQ", encodeKey(&buf, .{ .named = .f2 }, none, false, false, 0, 0, 0));
    try std.testing.expectEqualStrings(
        "\x1b\x03",
        encodeKey(&buf, try InputKey.initUnicode('c'), .{ .alt = true, .control = true }, false, false, 0, 0, 0),
    );
    try std.testing.expectEqualStrings(
        "\x1b\u{e9}",
        encodeKey(&buf, try InputKey.initUnicode('é'), .{ .alt = true }, false, false, 0, 0, 0),
    );
    try std.testing.expectEqualStrings(
        "\x1b\x1b[Z",
        encodeKey(&buf, .{ .named = .tab }, .{ .shift = true, .alt = true }, false, false, 0, 0, 0),
    );
    try std.testing.expectEqualStrings(
        "\x1b\x1b",
        encodeKey(&buf, .{ .named = .escape }, .{ .alt = true }, false, false, 0, 0, 0),
    );
}

test "every modifier combination has one Kitty parameter" {
    var buf: [max_encoded_len]u8 = undefined;
    const scalar = try InputKey.initUnicode('a');
    const cases = [_]struct { modifier: Modifier, expected: []const u8 }{
        .{ .modifier = .{}, .expected = "\x1b[97u" },
        .{ .modifier = .{ .shift = true }, .expected = "\x1b[97;2u" },
        .{ .modifier = .{ .alt = true }, .expected = "\x1b[97;3u" },
        .{ .modifier = .{ .shift = true, .alt = true }, .expected = "\x1b[97;4u" },
        .{ .modifier = .{ .control = true }, .expected = "\x1b[97;5u" },
        .{ .modifier = .{ .shift = true, .control = true }, .expected = "\x1b[97;6u" },
        .{ .modifier = .{ .alt = true, .control = true }, .expected = "\x1b[97;7u" },
        .{ .modifier = .{ .shift = true, .alt = true, .control = true }, .expected = "\x1b[97;8u" },
    };
    for (cases) |case| {
        try std.testing.expectEqualStrings(
            case.expected,
            encodeKey(&buf, scalar, case.modifier, false, false, 0, 0, 8),
        );
    }
}

test "legacy control encoding ignores num lock" {
    var buf: [max_encoded_len]u8 = undefined;
    const cases = [_]struct { key: u21, modifier: Modifier, expected: []const u8 }{
        .{ .key = 'b', .modifier = .{ .control = true, .num_lock = true }, .expected = "\x02" },
        .{ .key = 'c', .modifier = .{ .control = true, .num_lock = true }, .expected = "\x03" },
        .{ .key = 'r', .modifier = .{ .control = true, .num_lock = true }, .expected = "\x12" },
    };
    for (cases) |case| {
        try std.testing.expectEqualStrings(
            case.expected,
            try encodeEvent(
                &buf,
                try InputKey.initUnicode(case.key),
                case.modifier,
                .press,
                if (case.modifier.shift) '?' else null,
                case.key,
                "",
                "",
                false,
                false,
                0,
                0,
                0,
            ),
        );
    }
}

test "legacy shift identity ignores num lock" {
    var buf: [max_encoded_len]u8 = undefined;
    try std.testing.expectEqualStrings(
        "?",
        try encodeEvent(
            &buf,
            try InputKey.initUnicode('/'),
            .{ .shift = true, .num_lock = true },
            .press,
            '?',
            '/',
            "",
            "",
            false,
            false,
            0,
            0,
            0,
        ),
    );
}

/// Mouse button values.
const MouseButton = enum(u8) {
    none = 0,
    left = 1,
    middle = 2,
    right = 3,
    wheel_up = 4,
    wheel_down = 5,
};

/// Mouse event kinds.
const MouseEventKind = enum(u8) {
    press,
    release,
    move,
    wheel,
};

/// Host mouse event payload.
pub const MouseEvent = struct {
    kind: MouseEventKind,
    button: MouseButton,
    row: i32,
    col: u16,
    pixel_x: ?u32 = null,
    pixel_y: ?u32 = null,
    mod: Modifier,
    buttons_down: u8,
};

// Selects which host mouse events the terminal has requested.
const MouseTrackingMode = enum(u8) {
    off,
    x10,
    normal,
    button_event,
    any_event,
};

// Selects the negotiated byte encoding for mouse reports.
const MouseProtocol = enum(u8) {
    none,
    utf8,
    sgr,
    sgr_pixel,
    urxvt,
};

fn wouldEncodeMouse(event: MouseEvent, tracking: MouseTrackingMode, protocol: MouseProtocol) bool {
    if (tracking == .off) return false;

    const emit = switch (event.kind) {
        .press, .wheel => true,
        .release => tracking != .x10 and event.button != .wheel_up and event.button != .wheel_down,
        .move => switch (tracking) {
            .button_event => event.buttons_down != 0,
            .any_event => true,
            else => false,
        },
    };
    if (!emit) return false;

    const row1 = mouseRow1(event.row);
    const col1 = @as(u32, event.col) + 1;
    const cb = mouseCode(event, tracking);
    if (protocol == .sgr_pixel) {
        const pixel_x = event.pixel_x orelse return false;
        const pixel_y = event.pixel_y orelse return false;
        return pixel_x < std.math.maxInt(u32) and pixel_y < std.math.maxInt(u32);
    }
    if (protocol == .sgr or protocol == .urxvt) return true;
    if (protocol == .utf8) {
        return validMouseCodepoint(cb + 32) and
            validMouseCodepoint(col1 + 32) and
            validMouseCodepoint(row1 + 32);
    }
    return cb <= 223 and col1 <= 223 and row1 <= 223;
}

// Host rows are signed so callers can report positions above the viewport.
// Normalizing in u32 preserves that policy and makes maxInt(i32) + 1 exact.
fn mouseRow1(row: i32) u32 {
    return if (row < 0) 1 else @as(u32, @intCast(row)) + 1;
}

fn validMouseCodepoint(value: u32) bool {
    return value <= 0x10FFFF and std.unicode.utf8ValidCodepoint(@intCast(value));
}

/// Encode one host mouse event for the active terminal mouse protocol.
pub fn encodeMouse(buf: []u8, event: MouseEvent, tracking: MouseTrackingMode, protocol: MouseProtocol) []const u8 {
    if (!wouldEncodeMouse(event, tracking, protocol)) return buf[0..0];

    const row1 = mouseRow1(event.row);
    const col1 = @as(u32, event.col) + 1;
    const cb = mouseCode(event, tracking);
    return switch (protocol) {
        .sgr => encodeSgrMouse(buf, cb, col1, row1, event.kind == .release),
        .sgr_pixel => encodeSgrMouse(
            buf,
            cb,
            event.pixel_x.? + 1,
            event.pixel_y.? + 1,
            event.kind == .release,
        ),
        .urxvt => encodeUrxvtMouse(buf, cb, col1, row1),
        .utf8 => encodeCsiMMouse(buf, cb, col1, row1, true),
        .none => encodeCsiMMouse(buf, cb, col1, row1, false),
    };
}

fn mouseCode(event: MouseEvent, tracking: MouseTrackingMode) u16 {
    var code: u16 = switch (event.kind) {
        .press => pressButtonCode(event.button),
        .release => 3,
        .wheel => wheelButtonCode(event.button),
        .move => moveBaseCode(event),
    };
    if (tracking != .x10) {
        if (event.mod.shift) code += 4;
        if (event.mod.alt) code += 8;
        if (event.mod.control) code += 16;
    }
    if (event.kind == .move) code += 32;
    return code;
}

fn encodeSgrMouse(buf: []u8, cb: u16, col1: u32, row1: u32, release: bool) []const u8 {
    const final: u8 = if (release) 'm' else 'M';
    return std.fmt.bufPrint(buf, "\x1b[<{d};{d};{d}{c}", .{ cb, col1, row1, final }) catch buf[0..0];
}

fn encodeUrxvtMouse(buf: []u8, cb: u16, col1: u32, row1: u32) []const u8 {
    return std.fmt.bufPrint(buf, "\x1b[{d};{d};{d}M", .{ cb + 32, col1, row1 }) catch buf[0..0];
}

fn encodeCsiMMouse(buf: []u8, cb: u16, col1: u32, row1: u32, utf8: bool) []const u8 {
    if (!utf8 and (cb > 223 or col1 > 223 or row1 > 223)) return buf[0..0];
    var idx: u8 = 0;
    buf[idx] = '\x1b';
    idx += 1;
    buf[idx] = '[';
    idx += 1;
    buf[idx] = 'M';
    idx += 1;
    idx += encodeMouseNumber(buf[idx..], cb + 32, utf8);
    idx += encodeMouseNumber(buf[idx..], col1 + 32, utf8);
    idx += encodeMouseNumber(buf[idx..], row1 + 32, utf8);
    return buf[0..idx];
}

fn encodeMouseNumber(out: []u8, value: u32, utf8: bool) u8 {
    if (!utf8 or value < 128) {
        out[0] = @intCast(value);
        return 1;
    }
    return @intCast(std.unicode.utf8Encode(@intCast(value), out) catch 0);
}

fn pressButtonCode(button: MouseButton) u16 {
    return switch (button) {
        .left => 0,
        .middle => 1,
        .right => 2,
        .wheel_up => 64,
        .wheel_down => 65,
        .none => 3,
    };
}

fn wheelButtonCode(button: MouseButton) u16 {
    return switch (button) {
        .wheel_up => 64,
        .wheel_down => 65,
        else => pressButtonCode(button),
    };
}

fn moveBaseCode(event: MouseEvent) u16 {
    if ((event.buttons_down & 0x01) != 0) return 0;
    if ((event.buttons_down & 0x02) != 0) return 1;
    if ((event.buttons_down & 0x04) != 0) return 2;
    return 3;
}

test "mouse protocols encode boundaries without partial sequences" {
    var buf: [max_encoded_len]u8 = undefined;
    const base: MouseEvent = .{
        .kind = .press,
        .button = .left,
        .row = 4,
        .col = 6,
        .mod = .{ .shift = true, .alt = true, .control = true },
        .buttons_down = 1,
    };

    try std.testing.expectEqualStrings("\x1b[<28;7;5M", encodeMouse(&buf, base, .normal, .sgr));
    try std.testing.expectEqualStrings("", encodeMouse(&buf, base, .normal, .sgr_pixel));
    try std.testing.expectEqualStrings("\x1b[<28;320;240M", encodeMouse(
        &buf,
        .{
            .kind = .press,
            .button = .left,
            .row = 4,
            .col = 6,
            .pixel_x = 319,
            .pixel_y = 239,
            .mod = .{ .shift = true, .alt = true, .control = true },
            .buttons_down = 1,
        },
        .normal,
        .sgr_pixel,
    ));
    try std.testing.expectEqualStrings("\x1b[60;7;5M", encodeMouse(&buf, base, .normal, .urxvt));
    try std.testing.expectEqualStrings("\x1b[M#\"!", encodeMouse(
        &buf,
        .{ .kind = .release, .button = .left, .row = 0, .col = 1, .mod = .{}, .buttons_down = 0 },
        .normal,
        .none,
    ));
    try std.testing.expectEqualStrings("", encodeMouse(
        &buf,
        .{ .kind = .press, .button = .left, .row = 223, .col = 0, .mod = .{}, .buttons_down = 1 },
        .normal,
        .none,
    ));

    // A UTF-8 mouse field must be a Unicode scalar; rejecting the whole event
    // prevents an ESC [ M prefix from escaping without all three fields.
    try std.testing.expectEqualStrings("", encodeMouse(
        &buf,
        .{ .kind = .press, .button = .left, .row = 0xD800 - 33, .col = 0, .mod = .{}, .buttons_down = 1 },
        .normal,
        .utf8,
    ));

    const last_row: MouseEvent = .{
        .kind = .press,
        .button = .left,
        .row = std.math.maxInt(i32),
        .col = 0,
        .mod = .{},
        .buttons_down = 1,
    };
    try std.testing.expectEqualStrings("\x1b[<0;1;2147483648M", encodeMouse(&buf, last_row, .normal, .sgr));
    try std.testing.expectEqualStrings("\x1b[32;1;2147483648M", encodeMouse(&buf, last_row, .normal, .urxvt));
    try std.testing.expectEqualStrings("", encodeMouse(&buf, last_row, .normal, .utf8));
    try std.testing.expectEqualStrings("", encodeMouse(&buf, last_row, .normal, .none));
    try std.testing.expectEqualStrings("", encodeMouse(
        &buf,
        .{
            .kind = .press,
            .button = .left,
            .row = 0,
            .col = 0,
            .pixel_x = std.math.maxInt(u32),
            .pixel_y = 0,
            .mod = .{},
            .buttons_down = 1,
        },
        .normal,
        .sgr_pixel,
    ));
    try std.testing.expectEqual(@as(u32, 1), mouseRow1(std.math.minInt(i32)));
}

// Carries Kitty keyboard flags and the set, add, or remove operation mode.
const KeyFormatChange = struct {
    resource: ?u8,
    value: ?u16,
};

const saved_dec_mode_limit = 16;
const SavedDecModeCount = u8;
const SavedDecModeSlot = u8;

// Stores terminal modes that affect screen mutation, input encoding, and reports.
const ModeState = struct {
    keyboard_action_mode: bool = false,
    application_cursor_keys: bool = false,
    application_keypad: bool = false,
    auto_repeat: bool = true,
    reverse_screen_mode: bool = false,
    send_receive_mode: bool = false,
    newline_mode: bool = false,
    modify_other_keys: i8 = 0,
    key_format: [8]u16 = [_]u16{0} ** 8,
    focus_reporting: bool = false,
    bracketed_paste: bool = false,
    synchronized_output: bool = false,
    inband_resize_notifications: bool = false,
    reverse_wraparound_mode: bool = false,
    extended_reverse_wraparound_mode: bool = false,
    mouse_tracking: MouseTrackingMode = .off,
    mouse_protocol: MouseProtocol = .none,
    pointer_mode: u2 = 1,
    saved_dec_modes: [saved_dec_mode_limit]SavedDecMode =
        [_]SavedDecMode{.{ .mode = 0, .state = 0 }} ** saved_dec_mode_limit,
    saved_dec_mode_count: SavedDecModeCount = 0,
};

const SavedDecMode = struct {
    mode: u16,
    state: u8,
};

// Borrows the DEC mode facts required to answer one mode query.
const DecView = struct {
    application_cursor_keys: bool,
    application_keypad: bool,
    auto_repeat: bool,
    reverse_screen_mode: bool,
    origin_mode: bool,
    auto_wrap: bool,
    left_right_margin_mode: bool,
    cursor_blink: bool,
    cursor_visible: bool,
    alt_active: bool,
    mouse_tracking: MouseTrackingMode,
    mouse_protocol: MouseProtocol,
    focus_reporting: bool,
    bracketed_paste: bool,
    synchronized_output: bool,
    inband_resize_notifications: bool,
    reverse_wraparound: bool,
    extended_reverse_wraparound: bool,
};

// Borrows the ANSI mode facts required to answer one mode query.
const AnsiView = struct {
    keyboard_action_mode: bool,
    insert_mode: bool,
    send_receive_mode: bool,
    newline_mode: bool,
};

// Returns the DEC mode report state for a supported numeric mode.
fn decModeStateForView(view: DecView, mode: u16) u8 {
    return switch (mode) {
        1 => boolToDecModeState(view.application_cursor_keys),
        5 => boolToDecModeState(view.reverse_screen_mode),
        6 => boolToDecModeState(view.origin_mode),
        7 => boolToDecModeState(view.auto_wrap),
        8 => boolToDecModeState(view.auto_repeat),
        12 => boolToDecModeState(view.cursor_blink),
        45 => boolToDecModeState(view.reverse_wraparound),
        69 => boolToDecModeState(view.left_right_margin_mode),
        66 => boolToDecModeState(view.application_keypad),
        25 => boolToDecModeState(view.cursor_visible),
        47, 1047, 1049 => boolToDecModeState(view.alt_active),
        9 => if (view.mouse_tracking == .x10) 1 else 2,
        1000 => if (view.mouse_tracking == .normal) 1 else 2,
        1002 => if (view.mouse_tracking == .button_event) 1 else 2,
        1003 => if (view.mouse_tracking == .any_event) 1 else 2,
        1004 => boolToDecModeState(view.focus_reporting),
        1005 => boolToDecModeState(view.mouse_protocol == .utf8),
        1006 => boolToDecModeState(view.mouse_protocol == .sgr),
        1016 => boolToDecModeState(view.mouse_protocol == .sgr_pixel),
        1015 => boolToDecModeState(view.mouse_protocol == .urxvt),
        2004 => boolToDecModeState(view.bracketed_paste),
        2026 => boolToDecModeState(view.synchronized_output),
        2048 => boolToDecModeState(view.inband_resize_notifications),
        1045 => boolToDecModeState(view.extended_reverse_wraparound),
        else => 0,
    };
}

// Returns the ANSI mode report state for a supported numeric mode.
fn ansiModeStateForView(view: AnsiView, mode: u16) u8 {
    return switch (mode) {
        2 => boolToDecModeState(view.keyboard_action_mode),
        4 => boolToDecModeState(view.insert_mode),
        12 => boolToDecModeState(view.send_receive_mode),
        20 => boolToDecModeState(view.newline_mode),
        else => 0,
    };
}

fn boolToDecModeState(enabled: bool) u8 {
    return if (enabled) 1 else 2;
}

fn replaceBool(target: *bool, value: bool) bool {
    if (target.* == value) return false;
    target.* = value;
    return true;
}

// Returns an existing saved-mode slot or appends one within caller capacity.
fn savedDecModeSlot(saved_modes: []SavedDecMode, saved_count: *SavedDecModeCount, mode: u16) ?SavedDecModeSlot {
    const cap = savedDecModeCap(saved_modes);
    var slot: SavedDecModeSlot = 0;
    while (slot < saved_count.*) : (slot += 1) {
        if (saved_modes[savedIndex(slot)].mode == mode) return slot;
    }
    if (saved_count.* < cap) {
        const new_slot = saved_count.*;
        saved_count.* += 1;
        return new_slot;
    }
    return null;
}

// Returns a saved DEC mode value when the bounded store contains it.
fn savedDecModeState(saved_modes: []const SavedDecMode, saved_count: SavedDecModeCount, mode: u16) ?u8 {
    var slot: SavedDecModeSlot = 0;
    while (slot < saved_count) : (slot += 1) {
        const idx = savedIndex(slot);
        if (saved_modes[idx].mode == mode) return saved_modes[idx].state;
    }
    return null;
}

// Reports whether a DEC mode has implemented set and reset behavior.
fn canSetDecMode(mode: u16) bool {
    return switch (mode) {
        1,
        5,
        6,
        7,
        8,
        9,
        12,
        25,
        45,
        47,
        66,
        69,
        1047,
        1049,
        1045,
        1000,
        1002,
        1003,
        1004,
        1005,
        1006,
        1015,
        1016,
        2004,
        2026,
        2048,
        => true,
        else => false,
    };
}

fn savedIndex(slot: SavedDecModeSlot) usize {
    return @intCast(slot);
}

fn savedDecModeCap(saved_modes: []const SavedDecMode) SavedDecModeCount {
    std.debug.assert(saved_modes.len <= std.math.maxInt(SavedDecModeCount));
    return @intCast(saved_modes.len);
}

test "saved dec mode slot reuses existing entry" {
    var saved = [_]SavedDecMode{.{ .mode = 0, .state = 0 }} ** saved_dec_mode_limit;
    saved[0] = .{ .mode = 7, .state = 1 };
    var count: SavedDecModeCount = 1;
    try std.testing.expectEqual(@as(?SavedDecModeSlot, 0), savedDecModeSlot(saved[0..], &count, 7));
    try std.testing.expectEqual(@as(SavedDecModeCount, 1), count);
}

test "saved dec mode slot appends and saturates" {
    var saved = [_]SavedDecMode{.{ .mode = 0, .state = 0 }} ** saved_dec_mode_limit;
    var count: SavedDecModeCount = 0;
    try std.testing.expectEqual(@as(?SavedDecModeSlot, 0), savedDecModeSlot(saved[0..], &count, 7));
    try std.testing.expectEqual(@as(SavedDecModeCount, 1), count);
    saved[saved_dec_mode_limit - 1] = .{ .mode = 2004, .state = 1 };
    count = saved_dec_mode_limit;
    try std.testing.expectEqual(@as(?SavedDecModeSlot, null), savedDecModeSlot(saved[0..], &count, 1004));
    try std.testing.expectEqual(@as(SavedDecModeCount, saved_dec_mode_limit), count);
    try std.testing.expectEqual(@as(u16, 2004), saved[saved_dec_mode_limit - 1].mode);
    try std.testing.expectEqual(@as(u8, 1), saved[saved_dec_mode_limit - 1].state);
}

test "saved dec mode state scans only saved entries" {
    var saved = [_]SavedDecMode{.{ .mode = 0, .state = 0 }} ** saved_dec_mode_limit;
    saved[0] = .{ .mode = 7, .state = 1 };
    saved[1] = .{ .mode = 1004, .state = 2 };
    saved[2] = .{ .mode = 2004, .state = 1 };
    try std.testing.expectEqual(@as(?u8, 2), savedDecModeState(saved[0..], 2, 1004));
    try std.testing.expectEqual(@as(?u8, null), savedDecModeState(saved[0..], 2, 2004));
}

const locator_report_max_bytes = 40;

const ReportingMode = enum(u2) {
    disabled,
    continuous,
    one_shot,
};

const FilterRect = struct {
    top: u16,
    left: u16,
    bottom: u16,
    right: u16,
};

// Stores DEC locator reporting mode, filter rectangle, and one-shot event flags.
const Locator = struct {
    mode: ReportingMode = .disabled,
    coordinate_unit: u16 = 0,
    report_button_down: bool = false,
    report_button_up: bool = false,
    filter_rect: ?FilterRect = null,
    last_row: ?u16 = null,
    last_col: ?u16 = null,
    last_pixel_x: ?u32 = null,
    last_pixel_y: ?u32 = null,
    last_buttons_down: u8 = 0,
};

// Sets locator reporting and coordinate units, disabling unsupported values.
fn setReporting(state: *Locator, mode: u16, unit: u16) void {
    state.mode = switch (mode) {
        1 => .continuous,
        2 => .one_shot,
        else => .disabled,
    };
    state.coordinate_unit = unit;
}

// Installs an optional locator filter rectangle and clears its outside latch.
fn setFilter(state: *Locator, area: OptionalRectArea) void {
    const row = state.last_row orelse 0;
    const col = state.last_col orelse 0;
    const top = area.top orelse row;
    const left = area.left orelse col;
    const bottom = area.bottom orelse row;
    const right = area.right orelse col;
    if (area.top == null and area.left == null and area.bottom == null and area.right == null) {
        state.filter_rect = null;
        return;
    }
    if (top > bottom or left > right) return;
    state.filter_rect = .{ .top = top, .left = left, .bottom = bottom, .right = right };
}

// Replaces one-shot locator event flags from borrowed numeric modes.
fn setEvents(state: *Locator, modes: []const u16) void {
    for (modes) |mode| switch (mode) {
        0 => {
            state.report_button_down = false;
            state.report_button_up = false;
            state.filter_rect = null;
        },
        1 => state.report_button_down = true,
        2 => state.report_button_down = false,
        3 => state.report_button_up = true,
        4 => state.report_button_up = false,
        else => {},
    };
}

// Appends a bounded locator status or position reply for one request parameter.
fn appendReportForRequest(
    state: *Locator,
    allocator: std.mem.Allocator,
    output: *PendingOutput,
    encode_buf: []u8,
    param: u16,
) ApplyError!void {
    if (param > 1) return;
    if (state.mode == .disabled or state.last_row == null or state.last_col == null) {
        try appendCsiReply(output, allocator, .terminal, "0&w");
        return;
    }
    try appendReport(
        state,
        allocator,
        output,
        encode_buf,
        1,
        state.last_buttons_down,
        state.last_row.?,
        state.last_col.?,
    );
}

// Appends the supported locator device-status reply for parameter 53.
fn appendDeviceStatusReport(
    allocator: std.mem.Allocator,
    output: *PendingOutput,
    encode_buf: []u8,
    param: u16,
) ApplyError!void {
    const text = switch (param) {
        55 => formatLocatorReport(encode_buf, "?50n", .{}),
        56 => formatLocatorReport(encode_buf, "?57;1n", .{}),
        else => return,
    };
    try appendCsiReply(output, allocator, .terminal, text);
}

// Updates representable locator coordinates and appends enabled reports.
//
// Rows outside the retained `u16` coordinate domain are ignored. Report
// allocation or capacity failure preserves one-shot and filter latches.
fn handleMouseEvent(
    state: *Locator,
    allocator: std.mem.Allocator,
    output: *PendingOutput,
    encode_buf: []u8,
    event: MouseEvent,
) ApplyError!void {
    if (event.row < 0 or event.row > std.math.maxInt(u16)) return;
    const row: u16 = @intCast(event.row);
    const col = event.col;
    state.last_row = row;
    state.last_col = col;
    state.last_pixel_x = event.pixel_x;
    state.last_pixel_y = event.pixel_y;
    state.last_buttons_down = event.buttons_down;

    if (state.mode == .disabled) return;

    if (state.filter_rect) |filter| {
        if (row < filter.top or row > filter.bottom or col < filter.left or col > filter.right) {
            try appendReport(state, allocator, output, encode_buf, 10, event.buttons_down, row, col);
            state.filter_rect = null;
            return;
        }
    }

    const event_code: ?u16 = switch (event.kind) {
        .press => if (state.report_button_down) switch (event.button) {
            .left => 2,
            .middle => 4,
            .right => 6,
            else => null,
        } else null,
        .release => if (state.report_button_up) switch (event.button) {
            .left => 3,
            .middle => 5,
            .right => 7,
            else => null,
        } else null,
        else => null,
    };
    if (event_code) |code| try appendReport(state, allocator, output, encode_buf, code, event.buttons_down, row, col);
}

fn appendReport(
    state: *Locator,
    allocator: std.mem.Allocator,
    output: *PendingOutput,
    encode_buf: []u8,
    event_code: u16,
    buttons_down: u8,
    row: u16,
    col: u16,
) ApplyError!void {
    const button_mask = buttonsMask(buttons_down);
    const coords = coordinates(state, row, col);
    const text = formatLocatorReport(
        encode_buf,
        "{d};{d};{d};{d};0&w",
        .{ event_code, button_mask, coords.row + 1, coords.col + 1 },
    );
    try appendCsiReply(output, allocator, .terminal, text);
    if (state.mode == .one_shot) state.mode = .disabled;
}

fn formatLocatorReport(encode_buf: []u8, comptime fmt: []const u8, args: anytype) []const u8 {
    std.debug.assert(encode_buf.len >= locator_report_max_bytes);
    return std.fmt.bufPrint(encode_buf, fmt, args) catch unreachable;
}

fn coordinates(state: *const Locator, row: u16, col: u16) struct { row: u32, col: u32 } {
    if (state.coordinate_unit == 1) {
        return .{ .row = state.last_pixel_y orelse row, .col = state.last_pixel_x orelse col };
    }
    return .{ .row = row, .col = col };
}

fn buttonsMask(buttons_down: u8) u16 {
    var mask: u16 = 0;
    if ((buttons_down & 0b001) != 0) mask |= 4;
    if ((buttons_down & 0b010) != 0) mask |= 2;
    if ((buttons_down & 0b100) != 0) mask |= 1;
    return mask;
}

const ClipboardRequestOwned = struct {
    raw: []u8,
    selection_len: u8,
    kind: ClipboardRequestKind,
};

const ClipboardRequestKind = enum { set, query };

const ClipboardRequestView = struct {
    /// Borrows exact OSC 52 selection bytes; empty selection leaves the choice to host policy.
    selection: []const u8,
    /// Distinguishes clipboard replacement from a host-approved reply request.
    kind: ClipboardRequestKind,
};

const ParsedClipboardRequest = struct {
    selection: []const u8,
    data: []const u8,
    kind: ClipboardRequestKind,
};

const CopyIntoResult = union(enum) {
    copied: u64,
    short: u64,
};

const ClipboardDrainResult = union(enum) {
    none,
    copied: u64,
    short: u64,
    failed,
};

// Reports allocation failure or rejection by a concrete retained-consequence bound.
const ApplyError = error{
    OutOfMemory,
    ConsequenceLimit,
};

// Selects adaptive terminal replies or extension-mandated seven-bit framing.
const ReplyProtocol = enum { terminal, kitty, iterm };

// Names the C1 controls emitted by current terminal reply families.
const ReplyControl = enum { csi, dcs, osc, st };

// Owns bounded reply bytes and the terminal-selected C1 transmission form.
const PendingOutput = struct {
    bytes: std.ArrayList(u8),
    eight_bit_controls: bool = false,

    fn init() PendingOutput {
        return .{ .bytes = .empty };
    }
};

/// Accumulated replies await a host drain and stop at a bounded 64 KiB queue.
pub const pending_output_max_bytes: u32 = 64 * 1024;
/// OSC 52 is unchunked; retain at most the parser's 1 MiB clipboard packet.
const clipboard_max_bytes: u32 = 1024 * 1024;
/// OSC 52 names four standard selections and eight numbered cut buffers.
const clipboard_selection_max_bytes: u8 = 12;
/// One query reply fits regardless of selection length and 7-bit framing.
const clipboard_reply_bytes_max: u32 =
    ((pending_output_max_bytes - clipboard_selection_max_bytes - 8) / 4) * 3;
/// Retained DCS families are metadata protocols bounded by parser acceptance.
const dcs_payload_max_bytes: u32 = 2 * 1024;
/// One retained OSC 8 URI and optional identity share the ordinary metadata scale.
const hyperlink_target_max_bytes: u32 = 2 * 1024;
/// Each retained title or icon name follows the 1 KiB parser metadata scale.
pub const max_metadata_bytes: u32 = 1024;
/// Kitty retains the newest ten nonempty child titles.
const title_stack_limit = 10;
/// A terminal instance interns at most 4096 distinct hyperlink targets.
const hyperlink_target_max_count: u32 = 4096;
// Owns the latest bounded OSC 133 shell mark.
const ShellMark = struct {
    // Advances only after one valid OSC 133 mark is retained successfully.
    generation: u64 = 0,
    kind: u8 = 0,
    status: ?i32 = null,
    metadata: []u8 = &[_]u8{},
};

// Owns validated shell-integration identity until replacement or deinit.
const ShellIntegration = struct {
    version: u32,
    shell: ?[]u8,
};

// Borrows one child-reported directory and preserves whether its bytes are a URI or path.
const WorkingDirectoryReport = struct {
    kind: enum { uri, path },
    value: []const u8,
};

const TitleStackEffect = struct {
    changed: bool = false,
    title_changed: bool = false,
};

comptime {
    std.debug.assert(max_metadata_bytes <= hyperlink_target_max_bytes);
    std.debug.assert(hyperlink_target_max_bytes <= std.math.maxInt(u16));
    std.debug.assert(dcs_payload_max_bytes <= pending_output_max_bytes);
    std.debug.assert(clipboard_reply_bytes_max < pending_output_max_bytes);
    std.debug.assert(hyperlink_target_max_count > 0);
}

// Converts a slice length after asserting it fits the protocol-owned u32 domain.
fn byteCount(bytes: []const u8) u32 {
    std.debug.assert(bytes.len <= std.math.maxInt(u32));
    return @intCast(bytes.len);
}

fn hyperlinkCount(items: []const HyperlinkTarget) u32 {
    std.debug.assert(items.len <= std.math.maxInt(u32));
    return @intCast(items.len);
}

// Borrows one parsed OSC 8 hyperlink until the parser dispatch returns.
const HyperlinkSpec = struct {
    uri: []const u8,
    id: ?[]const u8,
};

// Owns one bounded URI and optional explicit identity in a single allocation.
const HyperlinkTarget = struct {
    storage: []u8,
    uri_len: u16,

    fn uri(self: HyperlinkTarget) []const u8 {
        return self.storage[0..self.uri_len];
    }

    fn id(self: HyperlinkTarget) ?[]const u8 {
        if (self.storage.len == self.uri_len) return null;
        return self.storage[self.uri_len..];
    }

    fn matches(self: HyperlinkTarget, spec: HyperlinkSpec) bool {
        if (!std.mem.eql(u8, self.uri(), spec.uri)) return false;
        const retained_id = self.id();
        if (retained_id == null or spec.id == null) return retained_id == null and spec.id == null;
        return std.mem.eql(u8, retained_id.?, spec.id.?);
    }
};

/// Retains bounded terminal consequences for later host inspection or drain.
///
/// `allocator` is borrowed for the HostState lifetime and owns every retained
/// allocation; caller-selected drain allocators own only returned buffers.
pub const HostState = struct {
    // Host consequence retention is heap-backed today, but every retained path
    // is bounded by this file's product capacity constants before allocation.
    const DcsPayloadOwned = struct {
        kind: DcsPayloadKind,
        payload: []u8,
    };

    allocator: std.mem.Allocator,
    colors: TerminalColorState = .{},
    pending_output: PendingOutput,
    hyperlink_targets: std.ArrayList(HyperlinkTarget),
    pending_clipboard: ?ClipboardRequestOwned = null,
    current_title: ?[]u8 = null,
    current_icon: ?[]u8 = null,
    working_directory_report: ?WorkingDirectoryReport = null,
    title_stack: [title_stack_limit]?[]u8 = [_]?[]u8{null} ** title_stack_limit,
    title_stack_len: u8 = 0,
    shell_integration: ?ShellIntegration = null,
    shell_mark: ShellMark = .{},
    bell_generation: u64 = 0,
    locator: Locator = .{},
    media_copy_request: ?u16 = null,
    dcs_payload: ?DcsPayloadOwned = null,
    legacy_control: ?LegacyControlKind = null,

    /// Initialize empty consequence state borrowing `allocator` until deinit.
    pub fn init(allocator: std.mem.Allocator) HostState {
        return .{
            .allocator = allocator,
            .pending_output = PendingOutput.init(),
            .hyperlink_targets = std.ArrayList(HyperlinkTarget).empty,
        };
    }

    /// Release every retained allocation through the initializer allocator.
    pub fn deinit(self: *HostState) void {
        for (self.hyperlink_targets.items) |target| self.allocator.free(target.storage);
        self.hyperlink_targets.deinit(self.allocator);
        if (self.pending_clipboard) |req| self.allocator.free(req.raw);
        if (self.current_title) |title| self.allocator.free(title);
        if (self.current_icon) |icon| self.allocator.free(icon);
        if (self.working_directory_report) |directory| self.allocator.free(directory.value);
        for (self.title_stack[0..self.title_stack_len]) |title| self.allocator.free(title.?);
        if (self.shell_integration) |integration|
            if (integration.shell) |shell| self.allocator.free(shell);
        self.allocator.free(self.shell_mark.metadata);
        if (self.dcs_payload) |payload| self.allocator.free(payload.payload);
        self.pending_output.bytes.deinit(self.allocator);
    }

    /// Reset host-observed state governed by terminal reset.
    pub fn resetTerminalState(self: *HostState) void {
        self.locator = .{};
        if (self.working_directory_report) |directory| self.allocator.free(directory.value);
        self.working_directory_report = null;
    }

    /// Borrow pending terminal reply bytes until the next HostState mutation.
    pub fn pendingOutput(self: *const HostState) []const u8 {
        return self.pending_output.bytes.items;
    }

    /// Append already serialized host-owned bytes transactionally without framing reinterpretation.
    pub fn appendPendingOutput(self: *HostState, bytes: []const u8) ApplyError!void {
        try appendOutput(&self.pending_output, self.allocator, bytes);
    }

    /// Replace the bounded title transactionally and report whether its bytes changed.
    pub fn replaceTitle(self: *HostState, title: []const u8) ApplyError!bool {
        return replaceMetadata(self, &self.current_title, title);
    }

    /// Replace the bounded icon name transactionally and report whether it changed.
    pub fn replaceIcon(self: *HostState, icon: []const u8) ApplyError!bool {
        return replaceMetadata(self, &self.current_icon, icon);
    }

    // Replaces one bounded child-reported URI or path transactionally and reports exact mutation.
    fn replaceWorkingDirectoryReport(
        self: *HostState,
        directory: WorkingDirectoryReport,
    ) ApplyError!bool {
        try ensureRetainedBound(byteCount(directory.value), max_metadata_bytes);
        if (self.working_directory_report) |current| {
            if (current.kind == directory.kind and std.mem.eql(u8, current.value, directory.value)) return false;
        }
        const owned = try self.allocator.dupe(u8, directory.value);
        if (self.working_directory_report) |current| self.allocator.free(current.value);
        self.working_directory_report = .{ .kind = directory.kind, .value = owned };
        return true;
    }

    /// Pushes one nonempty current title, dropping the oldest only after allocation succeeds.
    fn pushTitle(self: *HostState) ApplyError!bool {
        const current = self.current_title orelse return false;
        if (current.len == 0) return false;
        const owned = try self.allocator.dupe(u8, current);
        if (self.title_stack_len == title_stack_limit) {
            self.allocator.free(self.title_stack[0].?);
            std.mem.copyForwards(
                ?[]u8,
                self.title_stack[0 .. title_stack_limit - 1],
                self.title_stack[1..title_stack_limit],
            );
            self.title_stack[title_stack_limit - 1] = owned;
            return true;
        }
        self.title_stack[self.title_stack_len] = owned;
        self.title_stack_len += 1;
        return true;
    }

    /// Pops one retained title, transferring its allocation into current title ownership.
    fn popTitle(self: *HostState) TitleStackEffect {
        if (self.title_stack_len == 0) return .{};
        self.title_stack_len -= 1;
        const slot = &self.title_stack[self.title_stack_len];
        const restored = slot.*.?;
        slot.* = null;
        const title_changed = !optionalBytesEqual(self.current_title, restored);
        if (self.current_title) |current| self.allocator.free(current);
        self.current_title = restored;
        return .{ .changed = true, .title_changed = title_changed };
    }

    /// Replaces typed shell integration after optional shell allocation succeeds.
    pub fn replaceShellIntegration(
        self: *HostState,
        integration: ItermShellIntegration,
    ) ApplyError!void {
        const shell = if (integration.shell) |value| blk: {
            if (value.len > max_shell_name_bytes) return error.ConsequenceLimit;
            break :blk try self.allocator.dupe(u8, value);
        } else null;
        if (self.shell_integration) |old|
            if (old.shell) |value| self.allocator.free(value);
        self.shell_integration = .{
            .version = integration.version,
            .shell = shell,
        };
    }

    /// Replaces one bounded shell mark without disturbing the prior mark on failure.
    pub fn replaceShellMark(self: *HostState, mark: ItermShellMark) ApplyError!void {
        try ensureRetainedBound(byteCount(mark.metadata), max_metadata_bytes);
        const metadata = try self.allocator.dupe(u8, mark.metadata);
        self.allocator.free(self.shell_mark.metadata);
        self.shell_mark = .{
            .generation = std.math.add(u64, self.shell_mark.generation, 1) catch
                @panic("terminal shell-mark identity exhausted"),
            .kind = mark.kind,
            .status = mark.status,
            .metadata = metadata,
        };
    }

    /// Replace title and icon together transactionally and report any changed bytes.
    pub fn replaceTitleAndIcon(self: *HostState, value: []const u8) ApplyError!bool {
        try ensureRetainedBound(byteCount(value), max_metadata_bytes);
        if (optionalBytesEqual(self.current_title, value) and
            optionalBytesEqual(self.current_icon, value)) return false;
        const title = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(title);
        const icon = try self.allocator.dupe(u8, value);
        if (self.current_title) |old| self.allocator.free(old);
        if (self.current_icon) |old| self.allocator.free(old);
        self.current_title = title;
        self.current_icon = icon;
        return true;
    }

    /// Retain one BEL occurrence without choosing an audible or visual policy.
    pub fn ringBell(self: *HostState) ApplyError!void {
        if (self.bell_generation == std.math.maxInt(u64))
            return error.ConsequenceLimit;
        self.bell_generation += 1;
    }

    /// Replace one valid clipboard request transactionally and report exact retained mutation.
    pub fn replaceClipboard(self: *HostState, payload: []const u8) ApplyError!bool {
        try ensureRetainedBound(byteCount(payload), clipboard_max_bytes);
        const parsed = parseClipboardRequest(payload) orelse return false;
        if (self.pending_clipboard) |request|
            if (std.mem.eql(u8, request.raw, payload)) return false;
        const owned = try self.allocator.dupe(u8, payload);
        if (self.pending_clipboard) |req| self.allocator.free(req.raw);
        self.pending_clipboard = .{
            .raw = owned,
            .selection_len = @intCast(parsed.selection.len),
            .kind = parsed.kind,
        };
        return true;
    }

    /// Replace the retained DCS payload after bounds and allocation succeed.
    pub fn replaceDcsPayload(self: *HostState, payload: DcsPayload) ApplyError!void {
        try ensureRetainedBound(byteCount(payload.payload), dcs_payload_max_bytes);
        const owned = try self.allocator.dupe(u8, payload.payload);
        if (self.dcs_payload) |old| self.allocator.free(old.payload);
        self.dcs_payload = .{ .kind = payload.kind, .payload = owned };
    }

    // Returns a stable nonzero hyperlink identity, preserving existing identities on failure.
    fn internHyperlink(self: *HostState, spec: HyperlinkSpec) ApplyError!u32 {
        for (self.hyperlink_targets.items, 0..) |existing, idx| {
            if (existing.matches(spec)) return @intCast(idx + 1);
        }
        const id_len = if (spec.id) |id| id.len else 0;
        const storage_len = std.math.add(usize, spec.uri.len, id_len) catch return error.ConsequenceLimit;
        if (storage_len > hyperlink_target_max_bytes or spec.uri.len > std.math.maxInt(u16))
            return error.ConsequenceLimit;
        if (hyperlinkCount(self.hyperlink_targets.items) >= hyperlink_target_max_count) return error.ConsequenceLimit;
        const owned = try self.allocator.alloc(u8, storage_len);
        errdefer self.allocator.free(owned);
        @memcpy(owned[0..spec.uri.len], spec.uri);
        if (spec.id) |id| @memcpy(owned[spec.uri.len..], id);
        try self.hyperlink_targets.append(self.allocator, .{
            .storage = owned,
            .uri_len = @intCast(spec.uri.len),
        });
        return hyperlinkCount(self.hyperlink_targets.items);
    }

    /// Copy pending replies into caller memory without consuming them.
    fn copyPendingOutputInto(self: *const HostState, out: []u8) CopyIntoResult {
        const pending = self.pendingOutput();
        if (out.len < pending.len) return .{ .short = @intCast(pending.len) };
        if (pending.len != 0) @memcpy(out[0..pending.len], pending);
        return .{ .copied = @intCast(pending.len) };
    }

    /// Consume pending replies while retaining their allocation capacity.
    pub fn clearPendingOutput(self: *HostState) void {
        self.pending_output.bytes.clearRetainingCapacity();
    }

    /// Borrow the URI for a retained nonzero identity, or return null.
    pub fn hyperlinkUriForId(self: *const HostState, link_id: u32) ?[]const u8 {
        if (link_id == 0) return null;
        const idx = link_id - 1;
        if (idx >= self.hyperlink_targets.items.len) return null;
        return self.hyperlink_targets.items[idx].uri();
    }

    /// Borrow the pending raw clipboard request until the next HostState mutation.
    pub fn pendingClipboardSet(self: *const HostState) ?[]const u8 {
        if (self.pending_clipboard) |req|
            if (req.kind == .set) return req.raw;
        return null;
    }

    /// Borrow one pending OSC 52 operation and its exact host-policy selection bytes.
    pub fn pendingClipboardRequest(self: *const HostState) ?ClipboardRequestView {
        const request = self.pending_clipboard orelse return null;
        return .{
            .selection = request.raw[0..request.selection_len],
            .kind = request.kind,
        };
    }

    /// Consume and release the pending raw clipboard request.
    fn clearPendingClipboard(self: *HostState) void {
        if (self.pending_clipboard) |req| self.allocator.free(req.raw);
        self.pending_clipboard = null;
    }

    /// Decode into caller-owned memory; allocation failure preserves the request.
    pub fn drainPendingClipboardSet(self: *HostState, allocator: std.mem.Allocator) error{OutOfMemory}!?[]u8 {
        const pending = self.pendingClipboardSet() orelse return null;
        const decoded = decodeClipboardSet(allocator, pending) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                self.clearPendingClipboard();
                return null;
            },
        };
        self.clearPendingClipboard();
        return decoded;
    }

    /// Serialize one host-approved OSC 52 query reply and consume the query only on success.
    pub fn replyPendingClipboardQuery(self: *HostState, bytes: []const u8) ApplyError!bool {
        const request = self.pendingClipboardRequest() orelse return false;
        if (request.kind != .query) return false;
        const selection = request.selection;
        if (bytes.len > clipboard_reply_bytes_max) return error.ConsequenceLimit;
        const encoded_len = std.base64.standard.Encoder.calcSize(bytes.len);
        const prefix_len = std.math.add(usize, 4, selection.len) catch
            return error.ConsequenceLimit;
        const payload_len = std.math.add(usize, prefix_len, encoded_len) catch
            return error.ConsequenceLimit;
        if (payload_len > pending_output_max_bytes) return error.ConsequenceLimit;
        const payload = try self.allocator.alloc(u8, payload_len);
        defer self.allocator.free(payload);
        @memcpy(payload[0..3], "52;");
        @memcpy(payload[3 .. 3 + selection.len], selection);
        payload[prefix_len - 1] = ';';
        const encoded = std.base64.standard.Encoder.encode(payload[prefix_len..], bytes);
        std.debug.assert(encoded.len == encoded_len);
        try appendStringReply(&self.pending_output, self.allocator, .terminal, .osc, payload);
        self.clearPendingClipboard();
        return true;
    }

    /// Decode into caller memory and consume only after a complete copy.
    fn drainPendingClipboardSetInto(self: *HostState, out: []u8) ClipboardDrainResult {
        const pending = self.pendingClipboardSet() orelse return .none;
        const decoded_len = decodedClipboardSetSize(pending) catch return .failed;
        if (out.len < decoded_len) return .{ .short = decoded_len };
        const written = decodeClipboardSetInto(pending, out) catch return .failed;
        self.clearPendingClipboard();
        return .{ .copied = written };
    }

    /// Return the most recently retained media-copy request.
    pub fn mediaCopyRequest(self: *const HostState) ?u16 {
        return self.media_copy_request;
    }

    /// Return the retained DCS payload kind, if any.
    pub fn dcsPayloadKind(self: *const HostState) ?DcsPayloadKind {
        if (self.dcs_payload) |payload| return payload.kind;
        return null;
    }

    /// Borrow the retained DCS payload bytes, if any.
    pub fn dcsPayload(self: *const HostState) ?[]const u8 {
        if (self.dcs_payload) |payload| return payload.payload;
        return null;
    }

    /// Return the most recently observed legacy control kind.
    pub fn legacyControl(self: *const HostState) ?LegacyControlKind {
        return self.legacy_control;
    }

    /// Return a value snapshot of host-observable terminal colors.
    pub fn terminalColorState(self: *const HostState) TerminalColorState {
        return self.colors;
    }
};

fn replaceMetadata(
    self: *HostState,
    destination: *?[]u8,
    bytes: []const u8,
) ApplyError!bool {
    try ensureRetainedBound(byteCount(bytes), max_metadata_bytes);
    if (optionalBytesEqual(destination.*, bytes)) return false;
    const owned = try self.allocator.dupe(u8, bytes);
    if (destination.*) |old| self.allocator.free(old);
    destination.* = owned;
    return true;
}

fn optionalBytesEqual(current: ?[]const u8, replacement: []const u8) bool {
    return if (current) |bytes| std.mem.eql(u8, bytes, replacement) else false;
}

test "working-directory replacement is bounded transactional and distinguishes representation" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        replaceWorkingDirectoryAllocation,
        .{},
    );

    var state = HostState.init(std.testing.allocator);
    defer state.deinit();
    const oversized = [_]u8{'x'} ** (max_metadata_bytes + 1);
    try std.testing.expectError(error.ConsequenceLimit, state.replaceWorkingDirectoryReport(.{
        .kind = .path,
        .value = &oversized,
    }));
    try std.testing.expect(state.working_directory_report == null);
}

fn replaceWorkingDirectoryAllocation(allocator: std.mem.Allocator) !void {
    var state = HostState.init(allocator);
    defer state.deinit();
    const first_changed = state.replaceWorkingDirectoryReport(.{
        .kind = .uri,
        .value = "file://host/work",
    }) catch |failure| {
        try std.testing.expect(state.working_directory_report == null);
        return failure;
    };
    try std.testing.expect(first_changed);
    const second_changed = state.replaceWorkingDirectoryReport(.{ .kind = .path, .value = "/work" }) catch |failure| {
        const retained = state.working_directory_report.?;
        try std.testing.expect(retained.kind == .uri);
        try std.testing.expectEqualStrings("file://host/work", retained.value);
        return failure;
    };
    try std.testing.expect(second_changed);
    const retained = state.working_directory_report.?;
    try std.testing.expect(retained.kind == .path);
    try std.testing.expectEqualStrings("/work", retained.value);
}

test "shell mark replacement is bounded transactional and reusable" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        replaceShellMarkAllocation,
        .{},
    );

    var state = HostState.init(std.testing.allocator);
    defer state.deinit();
    const oversized = [_]u8{'x'} ** (max_metadata_bytes + 1);
    try std.testing.expectError(error.ConsequenceLimit, state.replaceShellMark(.{
        .kind = 'C',
        .status = null,
        .metadata = &oversized,
    }));
}

fn replaceShellMarkAllocation(allocator: std.mem.Allocator) !void {
    var state = HostState.init(allocator);
    defer state.deinit();
    state.replaceShellMark(.{ .kind = 'C', .status = null, .metadata = "old" }) catch |failure| {
        try std.testing.expectEqual(@as(u8, 0), state.shell_mark.kind);
        return failure;
    };
    state.replaceShellMark(.{ .kind = 'D', .status = 7, .metadata = "7" }) catch |failure| {
        try std.testing.expectEqual(@as(u8, 'C'), state.shell_mark.kind);
        try std.testing.expectEqualStrings("old", state.shell_mark.metadata);
        return failure;
    };
    try std.testing.expectEqual(@as(u8, 'D'), state.shell_mark.kind);
    try std.testing.expectEqual(@as(?i32, 7), state.shell_mark.status);
    try std.testing.expectEqualStrings("7", state.shell_mark.metadata);
}

// Appends a reply transactionally within the accumulated-output bound.
fn appendOutput(output: *PendingOutput, allocator: std.mem.Allocator, bytes: []const u8) ApplyError!void {
    try ensureAppendBound(byteCount(output.bytes.items), byteCount(bytes), pending_output_max_bytes);
    try output.bytes.appendSlice(allocator, bytes);
}

// Appends one reply framing control through the sole 7-bit/8-bit decision.
fn appendReplyControl(
    output: *PendingOutput,
    allocator: std.mem.Allocator,
    protocol: ReplyProtocol,
    control: ReplyControl,
) ApplyError!void {
    const eight_bit = protocol == .terminal and output.eight_bit_controls;
    const bytes = if (eight_bit) switch (control) {
        .csi => "\x9b",
        .dcs => "\x90",
        .osc => "\x9d",
        .st => "\x9c",
    } else switch (control) {
        .csi => "\x1b[",
        .dcs => "\x1bP",
        .osc => "\x1b]",
        .st => "\x1b\\",
    };
    try appendOutput(output, allocator, bytes);
}

// Appends one complete CSI reply transactionally.
fn appendCsiReply(
    output: *PendingOutput,
    allocator: std.mem.Allocator,
    protocol: ReplyProtocol,
    payload: []const u8,
) ApplyError!void {
    const start = byteCount(output.bytes.items);
    errdefer restorePendingOutput(output, start);
    try appendReplyControl(output, allocator, protocol, .csi);
    try appendOutput(output, allocator, payload);
}

// Appends one complete DCS or OSC reply with a matching ST transactionally.
fn appendStringReply(
    output: *PendingOutput,
    allocator: std.mem.Allocator,
    protocol: ReplyProtocol,
    control: enum { dcs, osc },
    payload: []const u8,
) ApplyError!void {
    const start = byteCount(output.bytes.items);
    errdefer restorePendingOutput(output, start);
    try appendReplyControl(output, allocator, protocol, switch (control) {
        .dcs => .dcs,
        .osc => .osc,
    });
    try appendOutput(output, allocator, payload);
    try appendReplyControl(output, allocator, protocol, .st);
}

// Restores drained reply bytes ahead of current output without partial mutation.
fn restorePendingOutput(output: *PendingOutput, len: u32) void {
    std.debug.assert(len <= byteCount(output.bytes.items));
    output.bytes.items.len = len;
}

fn ensureAppendBound(current_len: u32, append_len: u32, max_len: u32) ApplyError!void {
    const next_len = std.math.add(u32, current_len, append_len) catch return error.ConsequenceLimit;
    try ensureRetainedBound(next_len, max_len);
}

fn ensureRetainedBound(len: u32, max_len: u32) ApplyError!void {
    if (len > max_len) return error.ConsequenceLimit;
}

test "clipboard replacement preserves the retained request on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, replaceClipboardAllocation, .{});
}

test "title replacement preserves the retained title on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, replaceTitleAllocation, .{});
}

test "icon replacement preserves title and prior icon on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, replaceIconAllocation, .{});
}

test "paired title and icon replacement is transactional under allocation failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        replaceTitleAndIconAllocation,
        .{},
    );
}

test "title stack push preserves current and retained titles on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, pushTitleAllocation, .{});
}

test "title stack retains only the newest ten titles" {
    var state = HostState.init(std.testing.allocator);
    defer state.deinit();
    var buf: [2]u8 = undefined;
    for (0..title_stack_limit + 1) |idx| {
        const title = try std.fmt.bufPrint(&buf, "{d}", .{idx});
        try std.testing.expect(try state.replaceTitle(title));
        try std.testing.expect(try state.pushTitle());
    }
    try std.testing.expectEqual(@as(u8, title_stack_limit), state.title_stack_len);
    try std.testing.expectEqualStrings("1", state.title_stack[0].?);
    try std.testing.expectEqualStrings("10", state.title_stack[title_stack_limit - 1].?);
}

fn pushTitleAllocation(allocator: std.mem.Allocator) !void {
    var state = HostState.init(allocator);
    defer state.deinit();
    try std.testing.expect(try state.replaceTitle("first"));
    try std.testing.expect(try state.pushTitle());
    try std.testing.expect(try state.replaceTitle("second"));
    const changed = state.pushTitle() catch |err| {
        try std.testing.expectEqualStrings("second", state.current_title.?);
        try std.testing.expectEqual(@as(u8, 1), state.title_stack_len);
        try std.testing.expectEqualStrings("first", state.title_stack[0].?);
        return err;
    };
    try std.testing.expect(changed);
    try std.testing.expectEqual(@as(u8, 2), state.title_stack_len);
}

fn replaceTitleAllocation(allocator: std.mem.Allocator) !void {
    var state = HostState.init(allocator);
    defer state.deinit();
    try std.testing.expect(try state.replaceTitle("old"));
    const changed = state.replaceTitle("new") catch |err| {
        try std.testing.expectEqualStrings("old", state.current_title.?);
        return err;
    };
    try std.testing.expect(changed);
    try std.testing.expectEqualStrings("new", state.current_title.?);
}

fn replaceIconAllocation(allocator: std.mem.Allocator) !void {
    var state = HostState.init(allocator);
    defer state.deinit();
    try std.testing.expect(try state.replaceTitle("title"));
    try std.testing.expect(try state.replaceIcon("old"));
    const changed = state.replaceIcon("new") catch |err| {
        try std.testing.expectEqualStrings("title", state.current_title.?);
        try std.testing.expectEqualStrings("old", state.current_icon.?);
        return err;
    };
    try std.testing.expect(changed);
    try std.testing.expectEqualStrings("title", state.current_title.?);
    try std.testing.expectEqualStrings("new", state.current_icon.?);
}

fn replaceTitleAndIconAllocation(allocator: std.mem.Allocator) !void {
    var state = HostState.init(allocator);
    defer state.deinit();
    try std.testing.expect(try state.replaceTitle("old-title"));
    try std.testing.expect(try state.replaceIcon("old-icon"));
    const changed = state.replaceTitleAndIcon("both") catch |err| {
        try std.testing.expectEqualStrings("old-title", state.current_title.?);
        try std.testing.expectEqualStrings("old-icon", state.current_icon.?);
        return err;
    };
    try std.testing.expect(changed);
    try std.testing.expectEqualStrings("both", state.current_title.?);
    try std.testing.expectEqualStrings("both", state.current_icon.?);
}

fn replaceClipboardAllocation(allocator: std.mem.Allocator) !void {
    var state = HostState.init(allocator);
    defer state.deinit();
    try std.testing.expect(try state.replaceClipboard("c;b2xk"));
    const changed = state.replaceClipboard("c;bmV3") catch |err| {
        try std.testing.expectEqualStrings("c;b2xk", state.pendingClipboardSet().?);
        return err;
    };
    try std.testing.expect(changed);
    try std.testing.expectEqualStrings("c;bmV3", state.pendingClipboardSet().?);
}

test "hyperlink interning preserves prior identities on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, internHyperlinkAllocation, .{});
}

fn internHyperlinkAllocation(allocator: std.mem.Allocator) !void {
    var state = HostState.init(allocator);
    defer state.deinit();
    try std.testing.expectEqual(@as(u32, 1), try state.internHyperlink(.{ .uri = "https://one.example", .id = null }));
    const second_id = state.internHyperlink(.{ .uri = "https://two.example", .id = "second" }) catch |err| {
        try std.testing.expectEqualStrings("https://one.example", state.hyperlinkUriForId(1).?);
        try std.testing.expectEqual(@as(?[]const u8, null), state.hyperlinkUriForId(2));
        return err;
    };
    try std.testing.expectEqual(@as(u32, 2), second_id);
    try std.testing.expectEqualStrings("https://one.example", state.hyperlinkUriForId(1).?);
    try std.testing.expectEqualStrings("https://two.example", state.hyperlinkUriForId(2).?);
}

test "clipboard drain preserves the retained request on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, drainClipboardAllocation, .{});
}

test "clipboard query reply preserves request and output on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, replyClipboardAllocation, .{});
}

fn replyClipboardAllocation(allocator: std.mem.Allocator) !void {
    var state = HostState.init(allocator);
    defer state.deinit();
    const retained = try state.replaceClipboard("c;?");
    try std.testing.expect(retained);
    const replied = state.replyPendingClipboardQuery("Howl") catch |failure| {
        const request = state.pendingClipboardRequest().?;
        try std.testing.expect(request.kind == .query);
        try std.testing.expectEqualStrings("c", request.selection);
        try std.testing.expectEqualStrings("", state.pendingOutput());
        return failure;
    };
    try std.testing.expect(replied);
    try std.testing.expectEqualStrings("\x1b]52;c;SG93bA==\x1b\\", state.pendingOutput());
    try std.testing.expectEqual(@as(?ClipboardRequestView, null), state.pendingClipboardRequest());
}

test "retained host consequences enforce owner-specific boundaries" {
    const allocator = std.testing.allocator;
    var state = HostState.init(allocator);
    defer state.deinit();

    const title = try allocator.alloc(u8, max_metadata_bytes + 1);
    defer allocator.free(title);
    @memset(title, 't');
    try std.testing.expect(try state.replaceTitle(title[0 .. max_metadata_bytes - 1]));
    try std.testing.expect(try state.replaceTitle(title[0..max_metadata_bytes]));
    try std.testing.expectError(error.ConsequenceLimit, state.replaceTitle(title));
    try std.testing.expectEqual(max_metadata_bytes, byteCount(state.current_title.?));

    const hyperlink = try allocator.alloc(u8, hyperlink_target_max_bytes + 1);
    defer allocator.free(hyperlink);
    @memset(hyperlink, 'h');
    try std.testing.expectEqual(@as(u32, 1), try state.internHyperlink(.{
        .uri = hyperlink[0 .. hyperlink_target_max_bytes - 1],
        .id = null,
    }));
    try std.testing.expectEqual(@as(u32, 2), try state.internHyperlink(.{
        .uri = hyperlink[0 .. hyperlink_target_max_bytes - 1],
        .id = hyperlink[0..1],
    }));
    try std.testing.expectError(error.ConsequenceLimit, state.internHyperlink(.{
        .uri = hyperlink[0..hyperlink_target_max_bytes],
        .id = hyperlink[0..1],
    }));
    try std.testing.expectEqual(@as(u32, 2), hyperlinkCount(state.hyperlink_targets.items));

    const dcs = try allocator.alloc(u8, dcs_payload_max_bytes + 1);
    defer allocator.free(dcs);
    @memset(dcs, 'd');
    try state.replaceDcsPayload(.{ .kind = .xtsettcap, .payload = dcs[0 .. dcs_payload_max_bytes - 1] });
    try state.replaceDcsPayload(.{ .kind = .xtsettcap, .payload = dcs[0..dcs_payload_max_bytes] });
    try std.testing.expectError(
        error.ConsequenceLimit,
        state.replaceDcsPayload(.{ .kind = .xtsettcap, .payload = dcs }),
    );
    try std.testing.expectEqual(dcs_payload_max_bytes, byteCount(state.dcsPayload().?));

    const clipboard = try allocator.alloc(u8, clipboard_max_bytes + 1);
    defer allocator.free(clipboard);
    @memset(clipboard, 'A');
    clipboard[0] = 'c';
    clipboard[1] = 'p';
    clipboard[2] = 'q';
    clipboard[3] = ';';
    try std.testing.expect(try state.replaceClipboard(clipboard[0 .. clipboard_max_bytes - 4]));
    try std.testing.expect(try state.replaceClipboard(clipboard[0..clipboard_max_bytes]));
    try std.testing.expectError(error.ConsequenceLimit, state.replaceClipboard(clipboard));
    try std.testing.expectEqual(clipboard_max_bytes, byteCount(state.pendingClipboardSet().?));
}

test "pending output enforces exact accumulated boundary" {
    const allocator = std.testing.allocator;
    var output = PendingOutput.init();
    defer output.bytes.deinit(allocator);

    const bytes = try allocator.alloc(u8, pending_output_max_bytes + 1);
    defer allocator.free(bytes);
    @memset(bytes, 'o');

    try appendOutput(&output, allocator, bytes[0 .. pending_output_max_bytes - 1]);
    try appendOutput(&output, allocator, bytes[pending_output_max_bytes - 1 .. pending_output_max_bytes]);
    try std.testing.expectEqual(pending_output_max_bytes, byteCount(output.bytes.items));
    try std.testing.expectError(
        error.ConsequenceLimit,
        appendOutput(&output, allocator, bytes[pending_output_max_bytes..]),
    );
    try std.testing.expectEqual(pending_output_max_bytes, byteCount(output.bytes.items));
}

fn drainClipboardAllocation(result_allocator: std.mem.Allocator) !void {
    var state = HostState.init(std.testing.allocator);
    defer state.deinit();
    try std.testing.expect(try state.replaceClipboard("c;SG93bA=="));
    const decoded = state.drainPendingClipboardSet(result_allocator) catch |err| {
        try std.testing.expectEqualStrings("c;SG93bA==", state.pendingClipboardSet().?);
        return err;
    };
    defer result_allocator.free(decoded.?);
    try std.testing.expectEqualStrings("Howl", decoded.?);
    try std.testing.expectEqual(@as(?[]const u8, null), state.pendingClipboardSet());
}

// Borrows one parsed OSC 133 shell mark until parser mutation.
const ItermShellMark = struct {
    kind: u8,
    status: ?i32,
    metadata: []const u8,
};

// Borrows a decimal version and optional bounded `shell` identity.
// Duplicate, malformed, or unknown suffix keys reject the complete update.
const ItermShellIntegration = struct {
    version: u32,
    shell: ?[]const u8,
};

// Bounds one shell name without creating a generic metadata namespace.
const max_shell_name_bytes: u8 = 32;

// Names iTerm controls whose effects are safe inside the native terminal contract.
const ItermCommand = union(enum) {
    cursor_shape: ScreenCursorShape,
    report_cell_size,
    set_colors: []const u8,
    shell_integration: ItermShellIntegration,
    current_directory: []const u8,
};

// Decodes one borrowed OSC 50 or 1337 payload under its exact command family.
fn parse(osc_command: u16, payload: []const u8) ?ItermCommand {
    return switch (osc_command) {
        50 => parseCursorShape(payload),
        1337 => parse1337(payload),
        else => null,
    };
}

fn parse1337(payload: []const u8) ?ItermCommand {
    const separator = std.mem.indexOfScalar(u8, payload, '=') orelse {
        return if (std.mem.eql(u8, payload, "ReportCellSize"))
            .report_cell_size
        else
            null;
    };
    const key = payload[0..separator];
    const value = payload[separator + 1 ..];
    // iTerm ignores the value of this request key.
    if (std.mem.eql(u8, key, "ReportCellSize")) return .report_cell_size;
    if (std.mem.eql(u8, key, "CursorShape")) return parseCursorShape(payload);
    if (std.mem.eql(u8, key, "SetColors")) return .{ .set_colors = value };
    if (std.mem.eql(u8, key, "CurrentDir")) return .{ .current_directory = value };
    if (std.mem.eql(u8, key, "ShellIntegrationVersion"))
        return .{ .shell_integration = parseShellIntegration(value) orelse return null };
    return null;
}

fn parseCursorShape(payload: []const u8) ?ItermCommand {
    const prefix = "CursorShape=";
    if (!std.mem.startsWith(u8, payload, prefix)) return null;
    const value = payload[prefix.len..];
    if (value.len != 1) return null;
    return .{ .cursor_shape = switch (value[0]) {
        '0' => .block,
        '1' => .bar,
        '2' => .underline,
        else => return null,
    } };
}

fn parseShellIntegration(payload: []const u8) ?ItermShellIntegration {
    var parts = std.mem.splitScalar(u8, payload, ';');
    const version_text = parts.next() orelse return null;
    if (version_text.len == 0) return null;
    const version = std.fmt.parseUnsigned(u32, version_text, 10) catch return null;
    var shell: ?[]const u8 = null;
    while (parts.next()) |part| {
        const separator = std.mem.indexOfScalar(u8, part, '=') orelse return null;
        const key = part[0..separator];
        const value = part[separator + 1 ..];
        if (!std.mem.eql(u8, key, "shell") or shell != null or
            value.len == 0 or value.len > max_shell_name_bytes)
            return null;
        for (value) |byte| if (!isShellNameByte(byte)) return null;
        shell = value;
    }
    return .{ .version = version, .shell = shell };
}

fn isShellNameByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or
        byte == '.' or byte == '_' or byte == '+' or byte == '-';
}

// Parses one OSC 133 mark and optional command-exit status.
fn parseShellMark(payload: []const u8) ?ItermShellMark {
    if (payload.len == 0) return null;
    const separator = std.mem.indexOfScalar(u8, payload, ';') orelse payload.len;
    if (separator != 1) return null;
    const kind = payload[0];
    switch (kind) {
        'A', 'B', 'C', 'D' => {},
        else => return null,
    }
    const metadata = if (separator < payload.len) payload[separator + 1 ..] else "";
    const status = if (kind == 'D' and metadata.len > 0)
        std.fmt.parseInt(i32, metadata, 10) catch null
    else
        null;
    return .{ .kind = kind, .status = status, .metadata = metadata };
}

test "iTerm safe controls decode without accepting policy commands" {
    try std.testing.expect(parse(1337, "ReportCellSize").? == .report_cell_size);
    try std.testing.expect(parse(1337, "ReportCellSize=ignored").? == .report_cell_size);
    try std.testing.expectEqual(ScreenCursorShape.bar, parse(50, "CursorShape=1").?.cursor_shape);
    try std.testing.expectEqual(ScreenCursorShape.bar, parse(1337, "CursorShape=1").?.cursor_shape);
    try std.testing.expectEqualStrings("fg=fff", parse(1337, "SetColors=fg=fff").?.set_colors);
    try std.testing.expectEqualStrings("/work/tree", parse(1337, "CurrentDir=/work/tree").?.current_directory);
    const integration = parse(1337, "ShellIntegrationVersion=20;shell=bash").?.shell_integration;
    try std.testing.expectEqual(@as(u32, 20), integration.version);
    try std.testing.expectEqualStrings("bash", integration.shell.?);
    try std.testing.expect(parse(1337, "ShellIntegrationVersion=20;shell=bash;shell=zsh") == null);
    try std.testing.expect(parse(1337, "ShellIntegrationVersion=20;unknown=value") == null);
    try std.testing.expect(parse(1337, "ShellIntegrationVersion=broken;shell=bash") == null);
    try std.testing.expect(parse(50, "CursorShape=9") == null);
    try std.testing.expect(parse(50, "SetColors=fg=fff") == null);
    try std.testing.expect(parse(50, "ShellIntegrationVersion=20;shell=bash") == null);
    try std.testing.expect(parse(50, "ReportCellSize") == null);
    try std.testing.expect(parse(49, "CursorShape=1") == null);
}

const KittyColorState = TerminalColorState;

// Selects one terminal-owned Kitty color-stack operation and its zero-based stack convention.
const KittyColorCommand = union(enum) {
    push: u16,
    pop: u16,
};

// Stores Kitty's ten bounded color slots, sequential depth, and initialized slot extent.
const KittyColorStack = struct {
    stack: [10]KittyColorState = undefined,
    len: u8 = 0,
    slot_count: u8 = 0,
};

// Saves current colors sequentially or by one-based slot and reports exact stack mutation.
fn pushState(stack: *KittyColorStack, colors: *const KittyColorState, index: u16) bool {
    if (index > stack.stack.len) return false;
    if (index != 0) {
        const required: u8 = @intCast(index);
        const expanded = required > stack.slot_count;
        while (stack.slot_count < required) : (stack.slot_count += 1) {
            stack.stack[stack.slot_count] = .{};
        }
        if (!expanded and std.meta.eql(stack.stack[required - 1], colors.*)) return false;
        stack.stack[required - 1] = colors.*;
        return true;
    }

    if (stack.len == stack.slot_count and stack.slot_count < stack.stack.len) stack.slot_count += 1;
    if (stack.len == stack.stack.len) {
        std.mem.copyForwards(KittyColorState, stack.stack[0 .. stack.stack.len - 1], stack.stack[1..]);
        stack.len -= 1;
    }

    stack.stack[stack.len] = colors.*;
    stack.len += 1;
    return true;
}

// Restores sequentially or from one initialized one-based slot and reports exact mutation.
fn popState(stack: *KittyColorStack, colors: *KittyColorState, index: u16) bool {
    if (index > stack.stack.len) return false;
    if (index != 0) {
        const slot: u8 = @intCast(index - 1);
        if (slot >= stack.slot_count) return false;
        if (std.meta.eql(colors.*, stack.stack[slot])) return false;
        colors.* = stack.stack[slot];
        return true;
    }
    if (stack.len == 0) return false;
    stack.len -= 1;
    colors.* = stack.stack[stack.len];
    stack.stack[stack.len] = .{};
    return true;
}

// Applies one Kitty color control or appends its bounded query reply.
fn handleKittyControl(
    allocator: std.mem.Allocator,
    colors: *KittyColorState,
    output: *PendingOutput,
    payload: []const u8,
) ApplyError!void {
    var parts = std.mem.splitScalar(u8, payload, ';');
    while (parts.next()) |raw_part| {
        const part = std.mem.trim(u8, raw_part, " \t\r\n");
        if (part.len == 0) continue;
        const eq = std.mem.indexOfScalar(u8, part, '=');
        if (eq) |pos| {
            const key = std.mem.trim(u8, part[0..pos], " \t");
            const value = std.mem.trim(u8, part[pos + 1 ..], " \t");
            if (std.mem.eql(u8, value, "?")) {
                try appendKittyQueryReply(allocator, output, key, colors.*);
            } else {
                setColorKey(colors, key, value);
            }
        } else {
            resetColorKey(colors, std.mem.trim(u8, part, " \t"));
        }
    }
}
fn appendKittyQueryReply(
    allocator: std.mem.Allocator,
    output: *PendingOutput,
    key: []const u8,
    colors: KittyColorState,
) ApplyError!void {
    const start = byteCount(output.bytes.items);
    errdefer restorePendingOutput(output, start);
    try appendReplyControl(output, allocator, .kitty, .osc);
    try appendOutput(output, allocator, "21;");
    try appendOutput(output, allocator, key);
    try appendOutput(output, allocator, "=");
    if (colorForKey(colors, key)) |color| {
        try appendColorOsc(allocator, output, color);
    } else if (isKnownColorKey(key)) {
        // Empty value means dynamic/undefined for Kitty color control.
    } else {
        try appendOutput(output, allocator, "?");
    }
    try appendReplyControl(output, allocator, .kitty, .st);
}

const key_report_max_bytes = 16;
const kitty_keyboard_flag_mask: u8 = 0x7f;
const kitty_keyboard_stack_capacity = 8;

// Stores Kitty's current keyboard flags and seven predecessors: eight active
// protocol stack slots in total.
const KittyKeyStack = struct {
    flags: u8 = 0,
    stack: [kitty_keyboard_stack_capacity - 1]u8 =
        [_]u8{0} ** (kitty_keyboard_stack_capacity - 1),
    len: u8 = 0,

    /// Replaces, sets, or clears the current seven-bit Kitty flag set.
    pub fn set(self: *KittyKeyStack, requested: u8, mode: u8) bool {
        const before = self.flags;
        const flags = requested & kitty_keyboard_flag_mask;
        switch (mode) {
            1 => self.flags = flags,
            2 => self.flags |= flags,
            3 => self.flags &= ~flags,
            else => return false,
        }
        return self.flags != before;
    }

    /// Pushes flags into Kitty's eight-slot stack, dropping the oldest at capacity.
    pub fn push(self: *KittyKeyStack, requested: u8) bool {
        const before = self.*;
        const flags = requested & kitty_keyboard_flag_mask;
        if (self.len == self.stack.len) {
            std.mem.copyForwards(u8, self.stack[0 .. self.stack.len - 1], self.stack[1..self.stack.len]);
            self.len -= 1;
        }
        self.stack[self.len] = self.flags;
        self.len += 1;
        self.flags = flags;
        return !std.meta.eql(before, self.*);
    }

    /// Pops up to count active slots; exhausting the stack restores zero flags.
    pub fn pop(self: *KittyKeyStack, count: u16) bool {
        const before = self.*;
        var remaining = count;
        while (remaining > 0 and self.len > 0) : (remaining -= 1) {
            self.len -= 1;
            self.flags = self.stack[self.len];
        }
        if (remaining > 0) self.flags = 0;
        return !std.meta.eql(before, self.*);
    }

    /// Appends the current keyboard flags as one bounded Kitty reply.
    pub fn appendReport(
        self: *const KittyKeyStack,
        allocator: std.mem.Allocator,
        output: *PendingOutput,
        encode_buf: []u8,
    ) ApplyError!void {
        std.debug.assert(encode_buf.len >= key_report_max_bytes);
        const payload = std.fmt.bufPrint(encode_buf, "?{d}u", .{self.flags}) catch unreachable;
        try appendCsiReply(output, allocator, .kitty, payload);
    }
};

test "keyboard stack retains seven-bit flags and reports exact mutation" {
    var stack: KittyKeyStack = .{};
    try std.testing.expect(stack.set(0x7f, 1));
    try std.testing.expectEqual(@as(u8, 0x7f), stack.flags);
    try std.testing.expect(stack.push(8));
    try std.testing.expectEqual(@as(u8, 8), stack.flags);
    try std.testing.expect(stack.pop(1));
    try std.testing.expectEqual(@as(u8, 0x7f), stack.flags);
    try std.testing.expect(stack.set(8, 3));
    try std.testing.expectEqual(@as(u8, 0x77), stack.flags);
    try std.testing.expect(!stack.set(0, 4));
    try std.testing.expectEqual(@as(u8, 0x77), stack.flags);
    try std.testing.expect(stack.pop(1));
    try std.testing.expectEqual(@as(u8, 0), stack.flags);
}

const ScreenState = struct {
    keyboard: KittyKeyStack = .{},
};

// Combines per-screen keyboard stacks with the terminal color stack.
const KittyState = struct {
    main: ScreenState = .{},
    alt: ScreenState = .{},
    color_stack: KittyColorStack = .{},

    /// Returns mutable Kitty state for the currently selected screen.
    pub fn activeScreen(self: *KittyState, alt_active: bool) *ScreenState {
        return if (alt_active) &self.alt else &self.main;
    }

    /// Returns borrowed read-only Kitty state for the selected screen.
    pub fn activeScreenConst(self: *const KittyState, alt_active: bool) *const ScreenState {
        return if (alt_active) &self.alt else &self.main;
    }

    /// Resets Kitty state governed by terminal reset.
    pub fn resetTerminalState(self: *KittyState) void {
        self.main.keyboard = .{};
        self.alt.keyboard = .{};
        self.color_stack.len = 0;
        for (self.color_stack.stack[0..self.color_stack.slot_count]) |*slot| slot.* = .{};
    }
};

/// Identifies the supported DCS family owning a captured payload.
pub const DcsPayloadKind = enum {
    xtsettcap,
    decudk,
    decaupss,
};

// Borrows one complete DCS payload for immediate semantic decoding.
const DcsPayload = struct {
    kind: DcsPayloadKind,
    payload: []const u8,
};

/// Identifies a legacy terminal mode transition retained for host observation.
pub const LegacyControlKind = enum {
    tek_point_plot,
    tek_graph,
    tek_incremental_plot,
    tek_alpha,
    tek_copy,
    tek_special_point_plot,
    tek_write_thru_short_dashed,
    hp_memory_lock,
};

// Borrows one terminal color key and optional replacement value.
const TerminalColorControlCommand = struct {
    command: u16,
    payload: []const u8,
};

// Selects one terminal-owned cell or host-supplied pixel size report.
const SizeReport = enum {
    window_pixels,
    cell_pixels,
    text_cells,
};

const TitleStackCommand = enum {
    push,
    pop,
};

const C0Action = enum {
    bell,
    line_feed,
    carriage_return,
    backspace,
    horizontal_tab,
};

const C0 = enum(u8) {
    bell = 0x07,
    backspace = 0x08,
    horizontal_tab = 0x09,
    line_feed = 0x0A,
    vertical_tab = 0x0B,
    form_feed = 0x0C,
    carriage_return = 0x0D,
    file_separator = 0x1C,
    group_separator = 0x1D,
    record_separator = 0x1E,
    unit_separator = 0x1F,
    _,
};

// Classifies one byte as its exact C0 code without rejecting unknown values.
fn fromByte(byte: u8) C0 {
    return @enumFromInt(byte);
}

fn c0Action(control: C0) ?C0Action {
    return switch (control) {
        .bell => .bell,
        .line_feed, .vertical_tab, .form_feed => .line_feed,
        .carriage_return => .carriage_return,
        .backspace => .backspace,
        .horizontal_tab => .horizontal_tab,
        else => null,
    };
}

// Converts a C0 code into its terminal mutation, or null when it is ignored.
fn c0Process(control: C0) ?SemanticEvent {
    switch (control) {
        .file_separator => return SemanticEvent{ .legacy_control = .tek_point_plot },
        .group_separator => return SemanticEvent{ .legacy_control = .tek_graph },
        .record_separator => return SemanticEvent{ .legacy_control = .tek_incremental_plot },
        .unit_separator => return SemanticEvent{ .legacy_control = .tek_alpha },
        else => {},
    }
    const mapped = c0Action(control) orelse return null;
    return switch (mapped) {
        .bell => SemanticEvent.bell,
        .line_feed => SemanticEvent.line_feed,
        .carriage_return => SemanticEvent.carriage_return,
        .backspace => SemanticEvent.backspace,
        .horizontal_tab => SemanticEvent.horizontal_tab,
    };
}

// Selects the 7-bit ESC alias for implemented C1 bytes; all other bytes retain C0 handling.
fn controlProcess(control: u8) ?SemanticEvent {
    return switch (control) {
        0x84 => escProcess('D'),
        0x85 => escProcess('E'),
        0x88 => escProcess('H'),
        0x8D => escProcess('M'),
        0x96 => escProcess('V'),
        0x97 => escProcess('W'),
        else => c0Process(fromByte(control)),
    };
}

test "c0 handled controls keep protocol values" {
    try std.testing.expectEqual(@as(u8, 0x07), @intFromEnum(C0.bell));
    try std.testing.expectEqual(@as(u8, 0x08), @intFromEnum(C0.backspace));
    try std.testing.expectEqual(@as(u8, 0x09), @intFromEnum(C0.horizontal_tab));
    try std.testing.expectEqual(@as(u8, 0x0A), @intFromEnum(C0.line_feed));
    try std.testing.expectEqual(@as(u8, 0x0B), @intFromEnum(C0.vertical_tab));
    try std.testing.expectEqual(@as(u8, 0x0C), @intFromEnum(C0.form_feed));
    try std.testing.expectEqual(@as(u8, 0x0D), @intFromEnum(C0.carriage_return));
}

test "c0 maps line and cursor stream controls" {
    try std.testing.expect(c0Process(.bell).? == .bell);
    try std.testing.expect(c0Process(.line_feed).? == .line_feed);
    try std.testing.expect(c0Process(.vertical_tab).? == .line_feed);
    try std.testing.expect(c0Process(.form_feed).? == .line_feed);
    try std.testing.expect(c0Process(.carriage_return).? == .carriage_return);
    try std.testing.expect(c0Process(.backspace).? == .backspace);
    try std.testing.expect(c0Process(.horizontal_tab).? == .horizontal_tab);
}

test "c0 legacy controls map host-neutral state" {
    try std.testing.expectEqual(LegacyControlKind.tek_point_plot, c0Process(.file_separator).?.legacy_control);
    try std.testing.expectEqual(LegacyControlKind.tek_graph, c0Process(.group_separator).?.legacy_control);
    try std.testing.expectEqual(LegacyControlKind.tek_incremental_plot, c0Process(.record_separator).?.legacy_control);
    try std.testing.expectEqual(LegacyControlKind.tek_alpha, c0Process(.unit_separator).?.legacy_control);
}

test "c0 ignores unsupported controls" {
    try std.testing.expectEqual(@as(?SemanticEvent, null), c0Process(fromByte(0x00)));
}

// Routes one completed borrowed CSI sequence; unsupported combinations return null.
fn csiProcess(
    final: u8,
    params: []const i32,
    separators: parser_mod.CsiSeparatorList,
    leader_byte: u8,
    is_private: bool,
    intermediates: []const u8,
) ?SemanticEvent {
    if (is_private) return decodePrivateCsi(final, params, leader_byte, intermediates);
    if (leader_byte != 0) return decodeCsiLeader(final, params, leader_byte, intermediates);
    if (decodeCsiIntermediate(final, params, intermediates)) |event| return event;
    return decodeCsi(final, params, separators, intermediates);
}

// Decodes one CSI sequence with intermediates; unsupported forms return null.
fn decodeCsiIntermediate(final: u8, params: []const i32, intermediates: []const u8) ?SemanticEvent {
    if (intermediates.len == 2) return processPair(final, params, intermediates);
    if (intermediates.len != 1) return null;
    return switch (intermediates[0]) {
        '"' => processQuote(final, params),
        '$' => processDollar(final, params),
        '*' => processStar(final, params),
        '+' => processPlus(final, params),
        '#' => processHash(final, params),
        '\'' => processTick(final, params),
        ' ' => processSpace(final, params),
        else => null,
    };
}

fn processPair(final: u8, params: []const i32, intermediates: []const u8) ?SemanticEvent {
    if (intermediates[0] != '\'' or intermediates[1] != '*') return null;
    if (final != '{') return null;
    return SemanticEvent{ .locator_events = collectParams(params) };
}

fn processQuote(final: u8, params: []const i32) ?SemanticEvent {
    if (final == 'q') {
        return switch (paramAtOrDefault0(params, 0)) {
            0, 2 => SemanticEvent{ .character_protection = .none },
            1 => SemanticEvent{ .character_protection = .dec },
            else => null,
        };
    }
    if (final == 'v') return SemanticEvent.screen_extent_report;
    return null;
}

fn processDollar(final: u8, params: []const i32) ?SemanticEvent {
    return switch (final) {
        'p' => if (queryParam(params)) |mode| SemanticEvent{ .ansi_mode_query = mode } else null,
        'r' => rectAttrsChange(params, false),
        't' => rectAttrsChange(params, true),
        'v' => rectCopy(params),
        'x' => rectFill(params),
        'z' => rectErase(params, false),
        '{' => rectErase(params, true),
        else => null,
    };
}

fn processStar(final: u8, params: []const i32) ?SemanticEvent {
    if (final == 'x') {
        return switch (paramAtOrDefault0(params, 0)) {
            0, 1 => SemanticEvent{ .attr_change_extent_rect = false },
            2 => SemanticEvent{ .attr_change_extent_rect = true },
            else => null,
        };
    }
    if (final != 'y') return null;
    const area = rectArea(params, 2) orelse return null;
    return SemanticEvent{ .rect_checksum_request = .{
        .request_id = paramAtOrDefault0(params, 0),
        .page = paramAtOrDefault1(params, 1),
        .area = area,
    } };
}

fn processPlus(final: u8, params: []const i32) ?SemanticEvent {
    return switch (final) {
        'T' => SemanticEvent{ .scroll_down_lines = paramAtOrDefault1(params, 0) },
        else => null,
    };
}

fn processHash(final: u8, params: []const i32) ?SemanticEvent {
    return switch (final) {
        'p', '{' => SemanticEvent{ .sgr_stack_push = collectParams(params) },
        'q', '}' => SemanticEvent.sgr_stack_pop,
        'P' => SemanticEvent{ .kitty_color_stack = .{ .push = queryParam(params) orelse return null } },
        'Q' => SemanticEvent{ .kitty_color_stack = .{ .pop = queryParam(params) orelse return null } },
        'S' => SemanticEvent.xttitlepos,
        'y' => SemanticEvent{ .xtchecksum = paramAtOrDefault0(params, 0) },
        'R' => SemanticEvent.xtreportcolors,
        '|' => if (rectArea(params, 0)) |area|
            SemanticEvent{ .selected_graphic_rendition_report = area }
        else
            null,
        else => null,
    };
}

fn processTick(final: u8, params: []const i32) ?SemanticEvent {
    return switch (final) {
        'w' => SemanticEvent{ .locator_filter = optionalRectArea(params) },
        '}' => SemanticEvent{ .insert_columns = paramAtOrDefault1(params, 0) },
        'z' => SemanticEvent{ .locator_reporting = .{
            .mode = paramAtOrDefault0(params, 0),
            .unit = paramAtOrDefault0(params, 1),
        } },
        '|' => SemanticEvent{ .locator_request = paramAtOrDefault0(params, 0) },
        '~' => SemanticEvent{ .delete_columns = paramAtOrDefault1(params, 0) },
        else => null,
    };
}

fn processSpace(final: u8, params: []const i32) ?SemanticEvent {
    return switch (final) {
        'q' => SemanticEvent{ .cursor_style = cursorStyle(paramAtOrDefault0(params, 0)) },
        '@' => SemanticEvent{ .shift_left_columns = paramAtOrDefault1(params, 0) },
        'A' => SemanticEvent{ .shift_right_columns = paramAtOrDefault1(params, 0) },
        else => null,
    };
}

fn rectAttrsChange(params: []const i32, reverse: bool) ?SemanticEvent {
    if (params.len < 5) return null;
    const area = rectArea(params, 0) orelse return null;
    return .{ .rect_attrs_change = .{
        .area = area,
        .attrs = attrParams(params, 4),
        .reverse = reverse,
    } };
}

fn rectCopy(params: []const i32) ?SemanticEvent {
    const area = rectArea(params, 0) orelse return null;
    return .{ .rect_copy = .{
        .area = area,
        .source_page = paramAtOrDefault1(params, 4),
        .dest_top = paramAtOrDefault1(params, 5) - 1,
        .dest_left = paramAtOrDefault1(params, 6) - 1,
        .dest_page = paramAtOrDefault1(params, 7),
    } };
}

fn rectFill(params: []const i32) ?SemanticEvent {
    const ch = paramAtOrDefault0(params, 0);
    if (!isValidRectFillChar(ch)) return null;
    const area = rectArea(params, 1) orelse return null;
    return .{ .rect_fill = .{ .area = area, .ch = ch } };
}

fn rectErase(params: []const i32, selective: bool) ?SemanticEvent {
    const area = rectArea(params, 0) orelse return null;
    return if (selective)
        SemanticEvent{ .rect_selective_erase = area }
    else
        SemanticEvent{ .rect_erase = area };
}

// Decodes one leader-qualified CSI sequence; unsupported forms return null.
fn decodeCsiLeader(final: u8, params: []const i32, leader: u8, intermediates: []const u8) ?SemanticEvent {
    return switch (leader) {
        '>' => switch (final) {
            'c' => if (intermediates.len == 0 and zeroQuery(params))
                SemanticEvent.secondary_device_attributes
            else
                null,
            'f' => keyFormatChange(params),
            'q' => if (!intermediatesHas(intermediates, ' ') and
                paramAtOrDefault0(params, 0) == 0)
                SemanticEvent.xtversion
            else
                null,
            'm' => if (paramAtOrDefault0(params, 0) == 4)
                SemanticEvent{ .modify_other_keys_set = @intCast(
                    @max(if (params.len >= 2) params[1] else 0, 0),
                ) }
            else
                null,
            'n' => if (paramAtOrDefault0(params, 0) == 4) SemanticEvent.modify_other_keys_disable else null,
            'p' => pointerMode(params),
            'u' => SemanticEvent{ .kitty_keyboard_push = keyboardFlags(params) },
            else => null,
        },
        '=' => switch (final) {
            'c' => if (intermediates.len == 0 and zeroQuery(params))
                SemanticEvent.tertiary_device_attributes
            else
                null,
            'u' => decodeKittyKeyboardSet(params),
            else => null,
        },
        '<' => switch (final) {
            'u' => SemanticEvent{ .kitty_keyboard_pop = paramAtOrDefault1(params, 0) },
            else => null,
        },
        else => null,
    };
}

fn decodeKittyKeyboardSet(params: []const i32) ?SemanticEvent {
    const raw_mode = if (params.len >= 2) params[1] else 1;
    if (raw_mode < 1 or raw_mode > 3) return null;
    return SemanticEvent{ .kitty_keyboard_set = .{
        .flags = keyboardFlags(params),
        .mode = @intCast(raw_mode),
    } };
}

fn keyboardFlags(params: []const i32) u8 {
    const raw: u32 = @intCast(@max(if (params.len != 0) params[0] else 0, 0));
    return @intCast(raw & kitty_keyboard_flag_mask);
}

fn keyFormatChange(params: []const i32) SemanticEvent {
    if (params.len == 0) return SemanticEvent{ .key_format_change = .{ .resource = null, .value = null } };
    const resource = keyFormatParamAtOrDefault0(params, 0);
    if (params.len == 1) return SemanticEvent{ .key_format_change = .{ .resource = resource, .value = null } };
    return SemanticEvent{ .key_format_change = .{ .resource = resource, .value = paramAtOrDefault0(params, 1) } };
}

fn pointerMode(params: []const i32) SemanticEvent {
    const value = if (params.len == 0) 1 else paramAtOrDefault0(params, 0);
    return SemanticEvent{ .pointer_mode = @intCast(@min(value, 3)) };
}

// Tracks colon separators across the parser-bounded CSI parameter array.
// Stores at most the parser CSI parameter bound as clamped u16 mode values.
const ModeParams = struct {
    params: [parser_mod.max_params]u16,
    param_count: u8,
};

fn sgrSelection(params: ModeParams) u16 {
    if (params.param_count == 0) return sgr_stack_default_selection;
    var selection: u16 = 0;
    for (params.params[0..params.param_count]) |param| {
        const bit: ?u4 = switch (param) {
            1 => 0,
            2 => 1,
            3 => 2,
            4 => 3,
            5 => 4,
            7 => 5,
            8 => 6,
            9 => 7,
            21 => 8,
            30 => 9,
            31 => 10,
            else => null,
        };
        if (bit) |value| selection |= @as(u16, 1) << value;
    }
    return selection;
}

fn restoreSelectedSgr(current: *ScreenCellAttrs, entry: SgrStackEntry) void {
    if (entry.selection & (1 << 0) != 0) current.bold = entry.attrs.bold;
    if (entry.selection & (1 << 1) != 0) current.dim = entry.attrs.dim;
    if (entry.selection & (1 << 2) != 0) current.italic = entry.attrs.italic;
    if (entry.selection & (1 << 3) != 0) {
        current.underline = entry.attrs.underline;
        current.underline_style = entry.attrs.underline_style;
    } else if (entry.selection & (1 << 8) != 0) {
        if (!entry.attrs.underline) {
            current.underline = false;
            current.underline_style = .straight;
        } else if (entry.attrs.underline_style == .double) {
            current.underline = true;
            current.underline_style = .double;
        }
    }
    if (entry.selection & (1 << 4) != 0) {
        current.blink = entry.attrs.blink;
        current.blink_fast = entry.attrs.blink_fast;
    }
    if (entry.selection & (1 << 5) != 0) current.reverse = entry.attrs.reverse;
    if (entry.selection & (1 << 6) != 0) current.invisible = entry.attrs.invisible;
    if (entry.selection & (1 << 7) != 0) current.strikethrough = entry.attrs.strikethrough;
    if (entry.selection & (1 << 9) != 0) current.fg = entry.attrs.fg;
    if (entry.selection & (1 << 10) != 0) current.bg = entry.attrs.bg;
}

// Stores a bounded suffix of clamped u16 rectangular attribute values.
const AttrParams = struct {
    params: [parser_mod.max_params]u16,
    param_count: u8,
};

fn paramCount32(items: []const i32) u32 {
    std.debug.assert(items.len <= std.math.maxInt(u32));
    return @intCast(items.len);
}

// Projects positive one-based parameters into optional zero-based rectangle edges.
fn optionalRectArea(params: []const i32) OptionalRectArea {
    return .{
        .top = if (params.len >= 1 and params[0] > 0) paramOrDefault1(params[0]) - 1 else null,
        .left = if (params.len >= 2 and params[1] > 0) paramOrDefault1(params[1]) - 1 else null,
        .bottom = if (params.len >= 3 and params[2] > 0) paramOrDefault1(params[2]) - 1 else null,
        .right = if (params.len >= 4 and params[3] > 0) paramOrDefault1(params[3]) - 1 else null,
    };
}

// Projects a parameter suffix into an ordered zero-based rectangle with open lower defaults.
fn rectArea(params: []const i32, start_idx: u8) ?RectArea {
    const start = @as(u32, start_idx);
    const param_len = paramCount32(params);
    const area: RectArea = .{
        .top = if (param_len > start) paramOrDefault1(params[@intCast(start)]) - 1 else 0,
        .left = if (param_len > start + 1) paramOrDefault1(params[@intCast(start + 1)]) - 1 else 0,
        .bottom = if (param_len > start + 2) paramOrDefault1(params[@intCast(start + 2)]) - 1 else null,
        .right = if (param_len > start + 3) paramOrDefault1(params[@intCast(start + 3)]) - 1 else null,
    };
    if (area.bottom) |bottom| if (area.top > bottom) return null;
    if (area.right) |right| if (area.left > right) return null;
    return area;
}

// Copies a bounded parameter suffix into rectangular attribute storage.
fn attrParams(params: []const i32, start_idx: u8) AttrParams {
    var out = [_]u16{0} ** parser_mod.max_params;
    const param_len = paramCount32(params);
    var idx: u8 = start_idx;
    var dst: u8 = 0;
    while (idx < param_len and dst < parser_mod.max_params) : ({
        idx += 1;
        dst += 1;
    }) {
        out[@intCast(dst)] = paramOrDefault0(params[@intCast(idx)]);
    }
    return .{ .params = out, .param_count = @intCast(dst) };
}

// Accepts the ECMA-48 graphic ranges permitted by DECFRA.
fn isValidRectFillChar(ch: u16) bool {
    return (ch >= 32 and ch <= 126) or (ch >= 160 and ch <= 255);
}

// Returns one for absent or nonpositive parameters and clamps positive values to u16.
fn paramAtOrDefault1(params: []const i32, idx: u8) u16 {
    return if (paramCount32(params) > idx) paramOrDefault1(params[idx]) else 1;
}

// Returns zero for absent or nonpositive parameters and clamps positive values to u16.
fn paramAtOrDefault0(params: []const i32, idx: u8) u16 {
    return if (paramCount32(params) > idx) paramOrDefault0(params[idx]) else 0;
}

// Returns an absent-zero key-format parameter clamped to u8.
fn keyFormatParamAtOrDefault0(params: []const i32, idx: u8) u8 {
    return @intCast(@min(paramAtOrDefault0(params, idx), std.math.maxInt(u8)));
}

// Maps a numeric erase parameter to the terminal erase domain.
fn eraseMode(v: i32) ?ScreenEraseMode {
    return switch (v) {
        0 => .cursor_to_end,
        1 => .start_to_cursor,
        2 => .all,
        3 => .scrollback,
        else => null,
    };
}

fn lineEraseMode(v: i32) ?ScreenEraseMode {
    const mode = eraseMode(v) orelse return null;
    return if (mode == .scrollback) null else mode;
}

// Maps DECSCUSR parameters to an explicit cursor-style command.
fn cursorStyle(param: u16) CursorStyleCommand {
    return switch (param) {
        0, 1 => .{ .program_override = .{ .shape = .block, .blink = true } },
        2 => .{ .program_override = .{ .shape = .block, .blink = false } },
        3 => .{ .program_override = .{ .shape = .underline, .blink = true } },
        4 => .{ .program_override = .{ .shape = .underline, .blink = false } },
        5 => .{ .program_override = .{ .shape = .bar, .blink = true } },
        6 => .{ .program_override = .{ .shape = .bar, .blink = false } },
        else => .{ .program_override = .{ .shape = .none, .blink = (param & 1) == 1 } },
    };
}

// Copies parser-bounded mode parameters into clamped u16 storage.
fn collectParams(params: []const i32) ModeParams {
    var out = [_]u16{0} ** parser_mod.max_params;
    const n = @min(paramCount32(params), parser_mod.max_params);
    var idx: u8 = 0;
    while (idx < n) : (idx += 1) out[@intCast(idx)] = paramOrDefault0(params[@intCast(idx)]);
    return .{ .params = out, .param_count = @intCast(n) };
}

fn paramOrDefault1(v: i32) u16 {
    if (v <= 0) return 1;
    if (v > std.math.maxInt(u16)) return std.math.maxInt(u16);
    return @intCast(v);
}

fn paramOrDefault0(v: i32) u16 {
    if (v <= 0) return 0;
    if (v > std.math.maxInt(u16)) return std.math.maxInt(u16);
    return @intCast(v);
}

// Reports whether a borrowed intermediate-byte sequence contains one byte.
fn intermediatesHas(intermediates: []const u8, needle: u8) bool {
    return std.mem.indexOfScalar(u8, intermediates, needle) != null;
}

// Decodes one ordinary CSI sequence; unsupported forms return null.
fn decodeCsi(
    final: u8,
    params: []const i32,
    separators: parser_mod.CsiSeparatorList,
    intermediates: []const u8,
) ?SemanticEvent {
    switch (final) {
        '@' => return SemanticEvent{ .insert_chars = paramAtOrDefault1(params, 0) },
        'A' => return SemanticEvent{ .cursor_up = paramAtOrDefault1(params, 0) },
        'B', 'e' => return SemanticEvent{ .cursor_down = paramAtOrDefault1(params, 0) },
        'C', 'a' => return SemanticEvent{ .cursor_forward = paramAtOrDefault1(params, 0) },
        'b' => return SemanticEvent{ .repeat_preceding = paramAtOrDefault1(params, 0) },
        'D' => return SemanticEvent{ .cursor_back = paramAtOrDefault1(params, 0) },
        'j' => return SemanticEvent{ .cursor_back = paramAtOrDefault1(params, 0) },
        'k' => return SemanticEvent{ .cursor_up = paramAtOrDefault1(params, 0) },
        'E' => return SemanticEvent{ .cursor_next_line = paramAtOrDefault1(params, 0) },
        'F' => return SemanticEvent{ .cursor_prev_line = paramAtOrDefault1(params, 0) },
        'G', '`' => return SemanticEvent{ .cursor_horizontal_absolute = paramAtOrDefault1(params, 0) - 1 },
        'd' => return SemanticEvent{ .cursor_vertical_absolute = paramAtOrDefault1(params, 0) - 1 },
        'I' => return SemanticEvent{ .horizontal_tab_forward = paramAtOrDefault1(params, 0) },
        'g' => switch (paramAtOrDefault0(params, 0)) {
            0 => return SemanticEvent.tab_clear_current,
            3, 5 => return SemanticEvent.tab_clear_all,
            else => return null,
        },
        'Z' => return SemanticEvent{ .horizontal_tab_back = paramAtOrDefault1(params, 0) },
        'L' => return SemanticEvent{ .insert_lines = paramAtOrDefault1(params, 0) },
        'M' => return SemanticEvent{ .delete_lines = paramAtOrDefault1(params, 0) },
        'P' => return SemanticEvent{ .delete_chars = paramAtOrDefault1(params, 0) },
        'S' => return SemanticEvent{ .scroll_up_lines = paramAtOrDefault1(params, 0) },
        'T' => return SemanticEvent{ .scroll_down_lines = paramAtOrDefault1(params, 0) },
        'h' => return SemanticEvent{ .ansi_mode_set = collectParams(params) },
        'l' => return SemanticEvent{ .ansi_mode_reset = collectParams(params) },
        'm' => return SemanticEvent{ .sgr = .{ .params = params, .separators = separators } },
        's' => if (params.len == 0)
            return SemanticEvent.save_cursor
        else
            return SemanticEvent{ .set_left_right_margins = .{
                .left = paramAtOrDefault1(params, 0) - 1,
                .right = if (params.len >= 2 and params[1] > 0)
                    paramAtOrDefault1(params, 1) - 1
                else
                    null,
            } },
        'u' => return SemanticEvent.restore_cursor,
        'H', 'f' => {
            const row = paramAtOrDefault1(params, 0);
            const col = paramAtOrDefault1(params, 1);
            return SemanticEvent{ .cursor_position = .{ .row = row - 1, .col = col - 1 } };
        },
        'r' => return SemanticEvent{ .set_scroll_region = .{
            .top = paramAtOrDefault1(params, 0) - 1,
            .bottom = if (params.len >= 2 and params[1] > 0) paramAtOrDefault1(params, 1) - 1 else null,
        } },
        'J' => return decodeEraseDisplay(eraseMode(paramAtOrDefault0(params, 0)) orelse return null, false),
        'K' => return SemanticEvent{
            .erase_line = lineEraseMode(paramAtOrDefault0(params, 0)) orelse return null,
        },
        'X' => return SemanticEvent{ .erase_chars = paramAtOrDefault1(params, 0) },
        'x' => {
            if (intermediates.len != 0) return null;
            const kind = queryParam(params) orelse return null;
            return SemanticEvent{ .parameters_report = kind };
        },
        't' => {
            if (intermediates.len != 0 or params.len == 0) return null;
            if (params[0] == 22 or params[0] == 23) {
                if (params.len > 3 or (params.len == 3 and params[2] != 0)) return null;
                if (params.len >= 2 and params[1] < 0) return null;
                const command: TitleStackCommand = if (params[0] == 22) .push else .pop;
                return SemanticEvent{ .title_stack = .{
                    .command = command,
                    .option = paramAtOrDefault0(params, 1),
                } };
            }
            if (params.len > 2) return null;
            if (params.len == 2 and params[1] < 0) return null;
            return switch (params[0]) {
                14 => SemanticEvent{ .size_report = .window_pixels },
                16 => SemanticEvent{ .size_report = .cell_pixels },
                18 => SemanticEvent{ .size_report = .text_cells },
                21 => if (params.len == 1) SemanticEvent.window_title_report else null,
                else => null,
            };
        },
        'n' => {
            if (intermediates.len != 0) return null;
            return switch (queryParam(params) orelse return null) {
                5 => SemanticEvent.device_status_report,
                6 => SemanticEvent.cursor_position_report,
                else => null,
            };
        },
        'c' => {
            if (intermediates.len != 0 or !zeroQuery(params)) return null;
            return SemanticEvent.primary_device_attributes;
        },
        'p' => {
            if (params.len == 0 and intermediates.len == 1 and intermediates[0] == '!') {
                return SemanticEvent.soft_reset;
            }
            return null;
        },
        else => return null,
    }
}

fn decodeEraseDisplay(mode: ScreenEraseMode, protected: bool) SemanticEvent {
    return switch (mode) {
        .cursor_to_end => SemanticEvent{ .erase_display_below = protected },
        .start_to_cursor => SemanticEvent{ .erase_display_above = protected },
        .all => SemanticEvent{ .erase_display_complete = protected },
        .scrollback => SemanticEvent{ .erase_display_scrollback = protected },
    };
}

// Decodes one private CSI sequence; unsupported forms return null.
fn decodePrivateCsi(final: u8, params: []const i32, leader: u8, intermediates: []const u8) ?SemanticEvent {
    if (leader != '?') return null;
    if (directQuery(final, params, intermediates)) |event| return event;
    if (params.len == 0) return null;
    if (modeReport(final, params, intermediates)) |event| return event;
    if (saveRestore(final, params, intermediates)) |event| return event;
    if (report(final, params, intermediates)) |event| return event;
    if (intermediates.len != 0) return null;
    return modeToggle(final, params[0]);
}

fn directQuery(final: u8, params: []const i32, intermediates: []const u8) ?SemanticEvent {
    if (intermediates.len != 0) return null;
    switch (final) {
        'u' => return SemanticEvent.kitty_keyboard_query,
        'g' => return SemanticEvent{ .key_format_query = keyFormatParamAtOrDefault0(params, 0) },
        'J' => return decodePrivateEraseDisplay(
            eraseMode(paramAtOrDefault0(params, 0)) orelse return null,
            true,
        ),
        'K' => return SemanticEvent{
            .selective_erase_line = lineEraseMode(paramAtOrDefault0(params, 0)) orelse return null,
        },
        'W' => if (paramAtOrDefault0(params, 0) == 5) return SemanticEvent.reset_default_tab_stops,
        else => {},
    }
    return null;
}

fn decodePrivateEraseDisplay(mode: ScreenEraseMode, protected: bool) SemanticEvent {
    return switch (mode) {
        .cursor_to_end => SemanticEvent{ .erase_display_below = protected },
        .start_to_cursor => SemanticEvent{ .erase_display_above = protected },
        .all => SemanticEvent{ .erase_display_complete = protected },
        .scrollback => SemanticEvent{ .erase_display_scrollback = protected },
    };
}

fn modeReport(final: u8, params: []const i32, intermediates: []const u8) ?SemanticEvent {
    if (final == 'm' and paramAtOrDefault0(params, 0) == 4) return SemanticEvent.modify_other_keys_query;
    if (final == 'p' and intermediates.len == 1 and intermediates[0] == '$') {
        const mode = queryParam(params) orelse return null;
        return SemanticEvent{ .dec_mode_query = mode };
    }
    return null;
}

fn saveRestore(final: u8, params: []const i32, intermediates: []const u8) ?SemanticEvent {
    if (intermediates.len != 0) return null;
    return switch (final) {
        's' => SemanticEvent{ .dec_mode_save = collectParams(params) },
        'r' => SemanticEvent{ .dec_mode_restore = collectParams(params) },
        else => null,
    };
}

fn report(final: u8, params: []const i32, intermediates: []const u8) ?SemanticEvent {
    if (intermediates.len != 0) return null;
    const param = queryParam(params) orelse return null;
    return switch (final) {
        'i' => SemanticEvent{ .media_copy_request = param },
        'n' => switch (param) {
            5 => SemanticEvent.device_status_report,
            6 => SemanticEvent.dec_cursor_position_report,
            55, 56 => |status| SemanticEvent{ .dec_device_status_report = status },
            else => null,
        },
        else => null,
    };
}

// Returns one default-zero scalar and rejects trailing query parameters.
fn queryParam(params: []const i32) ?u16 {
    if (params.len > 1) return null;
    return paramAtOrDefault0(params, 0);
}

fn zeroQuery(params: []const i32) bool {
    return (queryParam(params) orelse return false) == 0;
}

fn modeToggle(final: u8, mode: i32) ?SemanticEvent {
    if (basicModeToggle(final, mode)) |event| return event;
    if (mouseModeToggle(final, mode)) |event| return event;
    return altScreenToggle(final, mode);
}

fn basicModeToggle(final: u8, mode: i32) ?SemanticEvent {
    return switch (mode) {
        5 => boolEvent(final, .{ .reverse_screen_mode = true }, .{ .reverse_screen_mode = false }),
        12 => boolEvent(final, .{ .cursor_blink = true }, .{ .cursor_blink = false }),
        25 => boolEvent(final, .{ .cursor_visible = true }, .{ .cursor_visible = false }),
        7 => boolEvent(final, .{ .auto_wrap = true }, .{ .auto_wrap = false }),
        8 => boolEvent(final, .{ .auto_repeat = true }, .{ .auto_repeat = false }),
        6 => boolEvent(final, .{ .origin_mode = true }, .{ .origin_mode = false }),
        1 => boolEvent(final, .{ .application_cursor_keys = true }, .{ .application_cursor_keys = false }),
        66 => boolEvent(final, .{ .application_keypad = true }, .{ .application_keypad = false }),
        69 => boolEvent(final, .{ .left_right_margin_mode = true }, .{ .left_right_margin_mode = false }),
        45 => boolEvent(final, .{ .reverse_wraparound_mode = true }, .{ .reverse_wraparound_mode = false }),
        1004 => boolEvent(final, .{ .focus_reporting = true }, .{ .focus_reporting = false }),
        2004 => boolEvent(final, .{ .bracketed_paste = true }, .{ .bracketed_paste = false }),
        2026 => boolEvent(final, .{ .synchronized_output = true }, .{ .synchronized_output = false }),
        2048 => boolEvent(
            final,
            .{ .inband_resize_notifications = true },
            .{ .inband_resize_notifications = false },
        ),
        1045 => boolEvent(
            final,
            .{ .extended_reverse_wraparound_mode = true },
            .{ .extended_reverse_wraparound_mode = false },
        ),
        else => null,
    };
}

fn mouseModeToggle(final: u8, mode: i32) ?SemanticEvent {
    return switch (mode) {
        9 => boolEvent(final, SemanticEvent.mouse_tracking_x10, SemanticEvent.mouse_tracking_off),
        1000 => boolEvent(final, SemanticEvent.mouse_tracking_normal, SemanticEvent.mouse_tracking_off),
        1002 => boolEvent(final, SemanticEvent.mouse_tracking_button_event, SemanticEvent.mouse_tracking_off),
        1003 => boolEvent(final, SemanticEvent.mouse_tracking_any_event, SemanticEvent.mouse_tracking_off),
        1005 => boolEvent(final, .{ .mouse_protocol_utf8 = true }, .{ .mouse_protocol_utf8 = false }),
        1006 => boolEvent(final, .{ .mouse_protocol_sgr = true }, .{ .mouse_protocol_sgr = false }),
        1015 => boolEvent(final, .{ .mouse_protocol_urxvt = true }, .{ .mouse_protocol_urxvt = false }),
        1016 => boolEvent(final, .{ .mouse_protocol_sgr_pixel = true }, .{ .mouse_protocol_sgr_pixel = false }),
        else => null,
    };
}

fn altScreenToggle(final: u8, mode: i32) ?SemanticEvent {
    return switch (mode) {
        47 => boolEvent(
            final,
            .{ .enter_alt_screen = .{ .clear = false, .save_cursor = false } },
            .{ .exit_alt_screen = .{ .restore_cursor = false } },
        ),
        1047 => boolEvent(
            final,
            .{ .enter_alt_screen = .{ .clear = false, .save_cursor = false } },
            .{ .exit_alt_screen = .{ .restore_cursor = false } },
        ),
        1048 => boolEvent(final, SemanticEvent.save_cursor, SemanticEvent.restore_cursor),
        1049 => boolEvent(
            final,
            .{ .enter_alt_screen = .{ .clear = true, .save_cursor = true } },
            .{ .exit_alt_screen = .{ .restore_cursor = true } },
        ),
        else => null,
    };
}

fn boolEvent(final: u8, on: SemanticEvent, off: SemanticEvent) ?SemanticEvent {
    return switch (final) {
        'h' => on,
        'l' => off,
        else => null,
    };
}

fn requestStatusPayload(data: []const u8) ?[]const u8 {
    if (data.len >= 2 and data[0] == '$' and data[1] == 'q') return data[2..];
    return null;
}

fn requestTermcapPayload(data: []const u8) ?[]const u8 {
    if (data.len >= 2 and data[0] == '+' and data[1] == 'q') return data[2..];
    return null;
}

fn requestResourcePayload(data: []const u8) ?[]const u8 {
    if (data.len >= 2 and data[0] == '+' and data[1] == 'Q') return data[2..];
    return null;
}

const DcsEvent = @FieldType(parser_mod.Event, "dcs");

// Decodes one completed borrowed DCS payload; unsupported commands return null.
fn dcsProcess(dcs: DcsEvent) ?SemanticEvent {
    if (dcs.intermediates_len == 1 and dcs.intermediates[0] == '=' and
        dcs.final == 's' and dcs.param_count == 1)
    {
        return switch (dcs.params[0]) {
            1 => .{ .synchronized_output = true },
            2 => .{ .synchronized_output = false },
            else => null,
        };
    }
    if (dcs.intermediates_len == 1 and dcs.intermediates[0] == '$' and dcs.final == 'q')
        return SemanticEvent{ .dcs_request_status = dcs.payload };
    if (dcs.intermediates_len == 1 and dcs.intermediates[0] == '+' and dcs.final == 'q')
        return SemanticEvent{ .dcs_request_termcap = dcs.payload };
    if (dcs.intermediates_len == 1 and dcs.intermediates[0] == '+' and dcs.final == 'Q')
        return SemanticEvent{ .dcs_request_resource = dcs.payload };
    if (dcs.intermediates_len == 1 and dcs.intermediates[0] == '+' and dcs.final == 'p')
        return SemanticEvent{ .dcs_payload = .{ .kind = .xtsettcap, .payload = dcs.payload } };
    if (dcs.intermediates_len == 1 and dcs.intermediates[0] == '$' and dcs.final == 't') {
        if (dcs.param_count != 1) return null;
        return switch (dcs.params[0]) {
            1 => SemanticEvent{ .restore_cursor_information = dcs.payload },
            2 => SemanticEvent{ .restore_tab_stops = dcs.payload },
            else => null,
        };
    }
    if (dcs.final == '|') return SemanticEvent{ .dcs_payload = .{ .kind = .decudk, .payload = dcs.body } };
    if (dcs.intermediates_len == 1 and dcs.intermediates[0] == '!' and dcs.final == 'u')
        return SemanticEvent{ .dcs_payload = .{ .kind = .decaupss, .payload = dcs.body } };
    return null;
}

const TestIntermediate = enum {
    dollar,
    plus,
    bang,
};

fn dcsEvent(
    body: []const u8,
    payload: []const u8,
    final: u8,
    params: []const i32,
    param_count: u8,
    intermediate: ?TestIntermediate,
) DcsEvent {
    const intermediates: []const u8 = if (intermediate) |value|
        switch (value) {
            .dollar => "$",
            .plus => "+",
            .bang => "!",
        }
    else
        "";
    return .{
        .body = body,
        .payload = payload,
        .final = final,
        .params = params,
        .param_count = param_count,
        .intermediates = intermediates,
        .intermediates_len = @intCast(intermediates.len),
    };
}

test "dcs request payloads map to semantic events" {
    const empty = [_]i32{0} ** 24;
    const status = dcsProcess(dcsEvent("$q q", " q", 'q', empty[0..], 0, .dollar)).?;
    try std.testing.expectEqualStrings(" q", status.dcs_request_status);

    const termcap = dcsProcess(dcsEvent("+q436F", "436F", 'q', empty[0..], 0, .plus)).?;
    try std.testing.expectEqualStrings("436F", termcap.dcs_request_termcap);

    const resource = dcsProcess(dcsEvent(
        "+Q6E616D65",
        "6E616D65",
        'Q',
        empty[0..],
        0,
        .plus,
    )).?;
    try std.testing.expectEqualStrings("6E616D65", resource.dcs_request_resource);
}

test "dcs legacy payload protocols classify host-neutral payloads" {
    const empty = [_]i32{0} ** 24;

    const termcap = dcsProcess(dcsEvent(
        "+p436F=7661",
        "436F=7661",
        'p',
        empty[0..],
        0,
        .plus,
    )).?;
    try std.testing.expect(termcap.dcs_payload.kind == .xtsettcap);
    try std.testing.expectEqualStrings("436F=7661", termcap.dcs_payload.payload);

    try std.testing.expect(dcsProcess(dcsEvent(
        "1$tstate",
        "state",
        't',
        &.{1},
        1,
        .dollar,
    )).? == .restore_cursor_information);
    try std.testing.expect(dcsProcess(dcsEvent(
        "2$t8/16",
        "8/16",
        't',
        &.{2},
        1,
        .dollar,
    )).? == .restore_tab_stops);
    try std.testing.expect(dcsProcess(dcsEvent(
        "0;1|keys",
        "keys",
        '|',
        empty[0..],
        0,
        null,
    )).?.dcs_payload.kind == .decudk);
    try std.testing.expect(dcsProcess(dcsEvent(
        "0!uA",
        "A",
        'u',
        empty[0..],
        0,
        .bang,
    )).?.dcs_payload.kind == .decaupss);
}

const EscAction = union(enum) {
    line_feed,
    next_line,
    reverse_index,
    forward_index,
    back_index,
    primary_device_attributes,
    horizontal_tab_set,
    hard_reset,
    save_cursor,
    restore_cursor,
    application_keypad: bool,
    character_protection: ScreenProtection,
};

fn escAction(final: u8) ?EscAction {
    return switch (final) {
        'D' => .line_feed,
        'E' => .next_line,
        'M' => .reverse_index,
        '9' => .forward_index,
        '6' => .back_index,
        'Z' => .primary_device_attributes,
        'H' => .horizontal_tab_set,
        'c' => .hard_reset,
        '7' => .save_cursor,
        '8' => .restore_cursor,
        'V' => .{ .character_protection = .iso },
        'W' => .{ .character_protection = .none },
        '=' => EscAction{ .application_keypad = true },
        '>' => EscAction{ .application_keypad = false },
        else => null,
    };
}

// Decodes one completed ESC event; unsupported combinations return null.
fn escProcess(final: u8) ?SemanticEvent {
    switch (final) {
        0x17 => return SemanticEvent{ .legacy_control = .tek_copy },
        0x1C => return SemanticEvent{ .legacy_control = .tek_special_point_plot },
        'l' => return SemanticEvent{ .legacy_control = .hp_memory_lock },
        's' => return SemanticEvent{ .legacy_control = .tek_write_thru_short_dashed },
        else => {},
    }
    const mapped = escAction(final) orelse return null;
    return switch (mapped) {
        .line_feed => SemanticEvent.line_feed,
        .next_line => SemanticEvent.next_line,
        .reverse_index => SemanticEvent.reverse_index,
        .forward_index => SemanticEvent.forward_index,
        .back_index => SemanticEvent.back_index,
        .primary_device_attributes => SemanticEvent.primary_device_attributes,
        .horizontal_tab_set => SemanticEvent.horizontal_tab_set,
        .hard_reset => SemanticEvent.hard_reset,
        .save_cursor => SemanticEvent.save_cursor,
        .restore_cursor => SemanticEvent.restore_cursor,
        .application_keypad => |enabled| SemanticEvent{ .application_keypad = enabled },
        .character_protection => |protection| SemanticEvent{ .character_protection = protection },
    };
}

test "esc maps C1 7-bit aliases and cursor save restore" {
    try std.testing.expect(escProcess('D').? == .line_feed);
    try std.testing.expect(escProcess('E').? == .next_line);
    try std.testing.expect(escProcess('M').? == .reverse_index);
    try std.testing.expect(escProcess('7').? == .save_cursor);
    try std.testing.expect(escProcess('8').? == .restore_cursor);
}

test "esc maps DECID RIS and application keypad" {
    try std.testing.expect(escProcess('Z').? == .primary_device_attributes);
    try std.testing.expect(escProcess('c').? == .hard_reset);
    try std.testing.expect(escProcess('=').?.application_keypad);
    try std.testing.expect(!escProcess('>').?.application_keypad);
}

test "esc maps low legacy controls and ignores unsupported finals" {
    try std.testing.expect(escProcess(0x17).?.legacy_control == .tek_copy);
    try std.testing.expect(escProcess(0x1C).?.legacy_control == .tek_special_point_plot);
    try std.testing.expect(escProcess('l').?.legacy_control == .hp_memory_lock);
    try std.testing.expect(escProcess('s').?.legacy_control == .tek_write_thru_short_dashed);
    try std.testing.expectEqual(@as(?SemanticEvent, null), escProcess('z'));
}

// Reports malformed OSC 52 syntax, unsupported query input, invalid base64, or allocation failure.
const ClipboardSetError = error{
    InvalidCharacter,
    InvalidOsc52Payload,
    InvalidPadding,
    OutOfMemory,
    UnsupportedOsc52Query,
};

const ClipboardSizeError = error{
    InvalidOsc52Payload,
    InvalidPadding,
    UnsupportedOsc52Query,
};

const ClipboardIntoError = error{
    InvalidCharacter,
    InvalidOsc52Payload,
    InvalidPadding,
    ShortBuffer,
    UnsupportedOsc52Query,
};

// Decodes one complete borrowed OSC action into a canonical semantic event.
fn oscProcess(osc: parser_mod.OscAction) ?SemanticEvent {
    return switch (osc) {
        // A commandless OSC is the parser's legacy title form, not OSC 0.
        .raw_title => |v| SemanticEvent{ .title_set = v.payload },
        .title => |v| switch (v.command) {
            0 => SemanticEvent{ .title_and_icon_set = v.payload },
            2 => SemanticEvent{ .title_set = v.payload },
            else => null,
        },
        .icon => |v| SemanticEvent{ .icon_set = v.payload },
        .palette_control => |v| SemanticEvent{ .color_control = .{ .command = v.command, .payload = v.payload } },
        .palette_reset => |v| SemanticEvent{ .color_control = .{ .command = v.command, .payload = v.payload } },
        .dynamic_color => |v| SemanticEvent{ .color_control = .{ .command = v.command, .payload = v.payload } },
        .dynamic_reset => |v| SemanticEvent{ .color_control = .{ .command = v.command, .payload = v.payload } },
        .kitty_color => |v| SemanticEvent{ .color_control = .{ .command = v.command, .payload = v.payload } },
        .report_pwd => |v| SemanticEvent{ .working_directory_report = .{ .kind = .uri, .value = v.payload } },
        .shell_mark => |v| if (parseShellMark(v.payload)) |mark| SemanticEvent{ .shell_mark = mark } else null,
        .iterm2 => |v| if (parse(v.command, v.payload)) |command| switch (command) {
            .cursor_shape => |shape| SemanticEvent{ .cursor_shape = shape },
            .report_cell_size => SemanticEvent.iterm_report_cell_size,
            .set_colors => |payload| SemanticEvent{ .iterm_set_colors = payload },
            .current_directory => |value| SemanticEvent{
                .working_directory_report = .{ .kind = .path, .value = value },
            },
            .shell_integration => |integration| SemanticEvent{
                .shell_integration_set = integration,
            },
        } else null,
        .kitty_color_stack_push => SemanticEvent{ .kitty_color_stack = .{ .push = 0 } },
        .kitty_color_stack_pop => SemanticEvent{ .kitty_color_stack = .{ .pop = 0 } },
        .hyperlink => |v| parseHyperlink(v.payload),
        .clipboard => |v| SemanticEvent{ .clipboard_set = v.payload },
        else => null,
    };
}

// Parses one OSC 8 URI and its first nonempty `id=` parameter without retaining parser memory.
fn parseHyperlink(payload: []const u8) ?SemanticEvent {
    const separator = std.mem.indexOfScalar(u8, payload, ';') orelse return null;
    const uri = payload[separator + 1 ..];
    if (uri.len == 0) return SemanticEvent.hyperlink_clear;
    var id: ?[]const u8 = null;
    var params = std.mem.splitScalar(u8, payload[0..separator], ':');
    while (params.next()) |param| {
        if (param.len > 3 and std.mem.startsWith(u8, param, "id=")) {
            id = param[3..];
            break;
        }
    }
    return SemanticEvent{ .hyperlink_set = .{ .uri = uri, .id = id } };
}

// Allocates and decodes one base64 OSC 52 payload into caller-owned memory.
fn decodeClipboardSet(allocator: std.mem.Allocator, raw: []const u8) ClipboardSetError![]u8 {
    const decoded_len = try decodedClipboardSetSize(raw);
    const out = try allocator.alloc(u8, @intCast(decoded_len));
    errdefer allocator.free(out);
    std.debug.assert(out.len == decoded_len);
    const written = decodeClipboardSetInto(raw, out) catch |err| switch (err) {
        error.ShortBuffer => unreachable,
        error.InvalidCharacter => return error.InvalidCharacter,
        error.InvalidOsc52Payload => return error.InvalidOsc52Payload,
        error.InvalidPadding => return error.InvalidPadding,
        error.UnsupportedOsc52Query => return error.UnsupportedOsc52Query,
    };
    std.debug.assert(written == decoded_len);
    return out;
}

fn decodedClipboardSetSize(raw: []const u8) ClipboardSizeError!u64 {
    const request = parseClipboardEnvelope(raw) orelse return error.InvalidOsc52Payload;
    if (request.kind == .query) return error.UnsupportedOsc52Query;
    return @intCast(try decodedBase64Size(request.data));
}

fn decodeClipboardSetInto(raw: []const u8, out: []u8) ClipboardIntoError!u64 {
    const request = parseClipboardEnvelope(raw) orelse return error.InvalidOsc52Payload;
    if (request.kind == .query) return error.UnsupportedOsc52Query;
    const decoded_len = try decodedBase64Size(request.data);
    if (out.len < decoded_len) return error.ShortBuffer;
    std.debug.assert(out.len >= decoded_len);
    std.base64.standard.Decoder.decode(out[0..decoded_len], request.data) catch |err| switch (err) {
        error.InvalidCharacter => return error.InvalidCharacter,
        error.InvalidPadding => return error.InvalidPadding,
        error.NoSpaceLeft => unreachable,
    };
    return @intCast(decoded_len);
}

fn decodedBase64Size(data: []const u8) error{InvalidPadding}!usize {
    // Size calculation cannot inspect alphabet bytes or consume destination space.
    return std.base64.standard.Decoder.calcSizeForSlice(data) catch |err| switch (err) {
        error.InvalidPadding => return error.InvalidPadding,
        error.InvalidCharacter, error.NoSpaceLeft => unreachable,
    };
}

// Classifies one complete OSC 52 payload while retaining selection bytes for host policy.
fn parseClipboardRequest(raw: []const u8) ?ParsedClipboardRequest {
    const request = parseClipboardEnvelope(raw) orelse return null;
    if (request.kind == .set and !validClipboardBase64(request.data)) return null;
    return request;
}

fn parseClipboardEnvelope(raw: []const u8) ?ParsedClipboardRequest {
    const separator = std.mem.indexOfScalar(u8, raw, ';') orelse return null;
    const selection = raw[0..separator];
    if (selection.len > clipboard_selection_max_bytes) return null;
    for (selection) |byte| switch (byte) {
        'c', 'p', 'q', 's', '0'...'7' => {},
        else => return null,
    };
    const data = raw[separator + 1 ..];
    return .{
        .selection = selection,
        .data = data,
        .kind = if (std.mem.eql(u8, data, "?")) .query else .set,
    };
}

fn validClipboardBase64(data: []const u8) bool {
    if (data.len % 4 != 0) return false;
    var padding: u2 = 0;
    for (data, 0..) |byte, index| switch (byte) {
        'A'...'Z', 'a'...'z', '0'...'9', '+', '/' => if (padding != 0) return false,
        '=' => {
            if (index < data.len -| 2 or padding == 2) return false;
            padding += 1;
        },
        else => return false,
    };
    return true;
}

test "OSC 52 clipboard set payload decodes" {
    const decoded = try decodeClipboardSet(std.testing.allocator, "c;SG93bA==");
    defer std.testing.allocator.free(decoded);
    try std.testing.expectEqualStrings("Howl", decoded);
}

test "OSC 52 clipboard query is unsupported for set drain" {
    try std.testing.expectError(error.UnsupportedOsc52Query, decodeClipboardSet(std.testing.allocator, "c;?"));
}

test "OSC 52 clipboard decode reports exact syntax base64 and allocation failures" {
    const decode: *const fn (std.mem.Allocator, []const u8) ClipboardSetError![]u8 = decodeClipboardSet;
    try std.testing.expectError(error.InvalidOsc52Payload, decode(std.testing.allocator, "SG93bA=="));
    try std.testing.expectError(error.InvalidPadding, decode(std.testing.allocator, "c;A"));
    try std.testing.expectError(error.InvalidCharacter, decode(std.testing.allocator, "c;!!!!"));

    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, decode(failing.allocator(), "c;SG93bA=="));
    try std.testing.expect(failing.has_induced_failure);

    var short: [3]u8 = undefined;
    try std.testing.expectError(error.ShortBuffer, decodeClipboardSetInto("c;SG93bA==", &short));
}

test "OSC title commands retain exact title and icon semantics" {
    try std.testing.expectEqualStrings(
        "Both",
        oscProcess(.{ .title = .{
            .command = 0,
            .payload = "Both",
            .term = .bel,
        } }).?.title_and_icon_set,
    );
    try std.testing.expectEqualStrings(
        "Title",
        oscProcess(.{ .title = .{
            .command = 2,
            .payload = "Title",
            .term = .bel,
        } }).?.title_set,
    );
    try std.testing.expectEqualStrings(
        "Raw Title",
        oscProcess(.{ .raw_title = .{
            .payload = "Raw Title",
            .term = .bel,
        } }).?.title_set,
    );
    try std.testing.expectEqualStrings(
        "Icon",
        oscProcess(.{ .icon = .{
            .payload = "Icon",
            .term = .bel,
        } }).?.icon_set,
    );
}

test "OSC hyperlink actions map to semantic events" {
    const explicit = oscProcess(.{ .hyperlink = .{
        .payload = "target=_blank:id=build;https://example.com",
        .term = .bel,
    } }).?.hyperlink_set;
    try std.testing.expectEqualStrings("https://example.com", explicit.uri);
    try std.testing.expectEqualStrings("build", explicit.id.?);
    try std.testing.expect(oscProcess(.{ .hyperlink = .{ .payload = ";", .term = .bel } }).? == .hyperlink_clear);
}

test "OSC clipboard and color controls preserve payloads" {
    try std.testing.expectEqualStrings(
        "c;Zm9v",
        oscProcess(.{ .clipboard = .{
            .command = 52,
            .payload = "c;Zm9v",
            .term = .bel,
        } }).?.clipboard_set,
    );

    const kitty_color = oscProcess(.{ .kitty_color = .{ .command = 21, .payload = "foreground=?", .term = .st } }).?;
    try std.testing.expectEqual(@as(u16, 21), kitty_color.color_control.command);
    try std.testing.expectEqualStrings("foreground=?", kitty_color.color_control.payload);

    const xterm_palette = oscProcess(.{ .palette_control = .{ .command = 4, .payload = "1;#ff0000", .term = .st } }).?;
    try std.testing.expectEqual(@as(u16, 4), xterm_palette.color_control.command);
    try std.testing.expectEqualStrings("1;#ff0000", xterm_palette.color_control.payload);
}

test "OSC shell mark maps to neutral semantic metadata" {
    const shell_mark = oscProcess(.{ .shell_mark = .{ .payload = "D;7", .term = .bel } }).?;
    try std.testing.expectEqual(@as(u8, 'D'), shell_mark.shell_mark.kind);
    try std.testing.expectEqual(@as(?i32, 7), shell_mark.shell_mark.status);
}

test "OSC Kitty policy payloads remain parser facts without semantic effects" {
    try std.testing.expect(oscProcess(.{ .notification = .{
        .command = 99,
        .payload = "i=1:p=body;Hello",
        .term = .st,
    } }) == null);
    try std.testing.expect(oscProcess(.{ .pointer_shape = .{
        .payload = ">wait,pointer",
        .term = .st,
    } }) == null);
    const push = oscProcess(.{ .kitty_color_stack_push = .st }).?;
    const pop = oscProcess(.{ .kitty_color_stack_pop = .st }).?;
    try std.testing.expectEqual(@as(u16, 0), push.kitty_color_stack.push);
    try std.testing.expectEqual(@as(u16, 0), pop.kitty_color_stack.pop);
    try std.testing.expect(oscProcess(.{ .kitty_clipboard = .{
        .payload = "type=write",
        .term = .st,
    } }) == null);
    try std.testing.expect(oscProcess(.{ .kitty_file_transfer = .{
        .payload = "cmd=data",
        .term = .st,
    } }) == null);
    try std.testing.expect(oscProcess(.{ .kitty_text_size = .{
        .payload = "s=2;Big",
        .term = .st,
    } }) == null);
}

/// Canonical parser-to-domain event consumed synchronously by terminal state owners.
pub const SemanticEvent = union(enum) {
    cursor_up: u16,
    cursor_down: u16,
    cursor_forward: u16,
    cursor_back: u16,
    cursor_next_line: u16,
    cursor_prev_line: u16,
    cursor_horizontal_absolute: u16,
    cursor_vertical_absolute: u16,
    cursor_position: struct { row: u16, col: u16 },
    write_text: []const u8,
    write_codepoint: u21,
    repeat_preceding: u16,
    bell,
    line_feed,
    next_line,
    reverse_index,
    forward_index,
    back_index,
    carriage_return,
    backspace,
    horizontal_tab,
    horizontal_tab_forward: u16,
    horizontal_tab_back: u16,
    horizontal_tab_set,
    tab_clear_current,
    tab_clear_all,
    cursor_visible: bool,
    cursor_blink: bool,
    cursor_style: CursorStyleCommand,
    cursor_shape: ScreenCursorShape,
    cursor_color: ?ScreenRgb,
    cursor_text_color: ?ScreenRgb,
    reverse_screen_mode: bool,
    eight_bit_controls: bool,
    auto_wrap: bool,
    auto_repeat: bool,
    origin_mode: bool,
    insert_mode: bool,
    application_cursor_keys: bool,
    application_keypad: bool,
    ansi_mode_set: ModeParams,
    ansi_mode_reset: ModeParams,
    ansi_mode_query: u16,
    modify_other_keys_set: i8,
    modify_other_keys_query,
    modify_other_keys_disable,
    key_format_change: KeyFormatChange,
    key_format_query: u8,
    pointer_mode: u2,
    reverse_wraparound_mode: bool,
    extended_reverse_wraparound_mode: bool,
    focus_reporting: bool,
    bracketed_paste: bool,
    synchronized_output: bool,
    inband_resize_notifications: bool,
    mouse_tracking_off,
    mouse_tracking_x10,
    mouse_tracking_normal,
    mouse_tracking_button_event,
    mouse_tracking_any_event,
    mouse_protocol_utf8: bool,
    mouse_protocol_sgr: bool,
    mouse_protocol_urxvt: bool,
    mouse_protocol_sgr_pixel: bool,
    kitty_keyboard_set: struct { flags: u8, mode: u8 },
    kitty_keyboard_query,
    kitty_keyboard_push: u8,
    kitty_keyboard_pop: u16,
    shell_mark: ItermShellMark,
    kitty_color_stack: KittyColorCommand,
    sgr_stack_push: ModeParams,
    sgr_stack_pop,
    title_and_icon_set: []const u8,
    title_set: []const u8,
    icon_set: []const u8,
    shell_integration_set: ItermShellIntegration,
    working_directory_report: WorkingDirectoryReport,
    iterm_report_cell_size,
    iterm_set_colors: []const u8,
    color_control: TerminalColorControlCommand,
    hyperlink_set: HyperlinkSpec,
    hyperlink_clear,
    clipboard_set: []const u8,
    dec_mode_query: u16,
    dec_mode_save: ModeParams,
    dec_mode_restore: ModeParams,
    dcs_request_status: []const u8,
    dcs_request_termcap: []const u8,
    dcs_request_resource: []const u8,
    restore_cursor_information: []const u8,
    restore_tab_stops: []const u8,
    dcs_payload: DcsPayload,
    device_status_report,
    dec_device_status_report: u16,
    cursor_position_report,
    dec_cursor_position_report,
    primary_device_attributes,
    secondary_device_attributes,
    tertiary_device_attributes,
    xtversion,
    xttitlepos,
    xtchecksum: u16,
    rect_checksum_request: struct { request_id: u16, page: u16, area: RectArea },
    selected_graphic_rendition_report: RectArea,
    screen_extent_report,
    parameters_report: u16,
    size_report: SizeReport,
    window_title_report,
    title_stack: struct { command: TitleStackCommand, option: u16 },
    xtreportcolors,
    locator_reporting: struct { mode: u16, unit: u16 },
    locator_filter: OptionalRectArea,
    locator_events: ModeParams,
    locator_request: u16,
    media_copy_request: u16,
    legacy_control: LegacyControlKind,
    sgr: struct {
        params: []const i32,
        separators: parser_mod.CsiSeparatorList,
    },
    enter_alt_screen: struct { clear: bool, save_cursor: bool },
    exit_alt_screen: struct { restore_cursor: bool },
    save_cursor,
    restore_cursor,
    insert_lines: u16,
    delete_lines: u16,
    insert_chars: u16,
    delete_chars: u16,
    scroll_up_lines: u16,
    scroll_down_lines: u16,
    set_scroll_region: struct {
        top: u16,
        bottom: ?u16,
    },
    hard_reset,
    soft_reset,
    erase_display_below: bool,
    erase_display_above: bool,
    erase_display_complete: bool,
    erase_display_scrollback: bool,
    erase_display_scroll_complete: bool,
    erase_line: ScreenEraseMode,
    selective_erase_line: ScreenEraseMode,
    erase_chars: u16,
    shift_left_columns: u16,
    shift_right_columns: u16,
    character_protection: ScreenProtection,
    rect_erase: RectArea,
    rect_selective_erase: RectArea,
    rect_fill: struct { area: RectArea, ch: u21 },
    rect_copy: RectCopy,
    rect_attrs_change: struct { area: RectArea, attrs: AttrParams, reverse: bool },
    insert_columns: u16,
    delete_columns: u16,
    attr_change_extent_rect: bool,
    left_right_margin_mode: bool,
    set_left_right_margins: struct { left: u16, right: ?u16 },
    reset_default_tab_stops,
};

// Identifies whether a visible row comes from history or the active screen.
const RowSource = union(enum) {
    history: u32,
    screen: u16,
};

/// Borrows a unified history-and-screen viewport until screen-set mutation.
pub const View = struct {
    rows: u16,
    cols: u16,
    cursor_row: u16,
    cursor_col: u16,
    cursor_visible: bool,
    cursor_shape: Screen.CursorShape,
    cursor_blink: bool,
    is_alternate_screen: bool,
    scrollback_offset: u32,
    history_count: u32,
    history_row_base: u32,
    start: u32,
    screen: *const Screen,

    fn rowSource(self: View, row: u16) RowSource {
        if (self.rows == 0 or row >= self.rows) return .{ .screen = 0 };
        const src_row = self.start + rowIndex(row);
        std.debug.assert(self.start + rowIndex(self.rows) <= self.history_count + rowIndex(self.rows));
        std.debug.assert(src_row >= self.start);
        std.debug.assert(src_row < self.history_count + rowIndex(self.rows));
        if (src_row < self.history_count) return .{ .history = self.history_count - 1 - src_row };
        return .{ .screen = @intCast(@min(src_row - self.history_count, rowIndex(self.rows -| 1))) };
    }

    /// Returns a copied cell from an already resolved row source.
    pub fn sourceCellInfoAt(self: View, source: RowSource, col: u16) Screen.Cell {
        return switch (source) {
            .history => |recency| self.screen.historyCellAt(recency, col),
            .screen => |screen_row| self.screen.cellInfoAt(screen_row, col),
        };
    }

    /// Returns a copied viewport cell, clamping an invalid row to screen row zero.
    pub fn cellInfoAt(self: View, row: u16, col: u16) Screen.Cell {
        return self.sourceCellInfoAt(self.rowSource(row), col);
    }

    /// Returns the codepoint of one visible cell.
    pub fn cellAt(self: View, row: u16, col: u16) u21 {
        return @intCast(self.cellInfoAt(row, col).codepoint);
    }

    /// Returns one visible row's DEC geometry without prescribing host scaling.
    pub fn lineGeometry(self: View, row: u16) Screen.LineGeometry {
        return switch (self.rowSource(row)) {
            .history => |recency| self.screen.historyLineGeometry(recency),
            .screen => |screen_row| self.screen.lineGeometry(screen_row),
        };
    }

    /// Returns the display depth contributed by one visible row.
    pub fn rowDepth(self: View, row: u16) u32 {
        if (self.rows == 0 or row >= self.rows) return self.scrollback_offset;
        std.debug.assert(self.scrollback_offset <= self.history_count);
        return self.scrollback_offset + rowIndex(self.rows - 1 - row);
    }

    /// Returns the first blank column after visible row content.
    pub fn contentEndExclusive(self: View, row: u16) u16 {
        if (self.scrollback_offset == 0 and row > self.cursor_row) return 0;
        var scan = self.cols;
        while (scan > 0) {
            const idx = scan - 1;
            const cell = self.cellInfoAt(row, idx);
            if (cell.codepoint != 0 and cell.codepoint != ' ') return scan;
            scan -= 1;
        }
        return if (self.cols > 0) 1 else 0;
    }
};

// Pairs a borrowed visible view with its active selection.
const SurfaceSnapshot = struct {
    view: View,
    dirty: ?Screen.DirtyRows,
    selection: ?TerminalSelection,
};

// Owns primary and alternate screens plus their independent selections.
const Set = struct {
    primary: Screen,
    alternate: Screen,
    primary_selection: SelectionState = SelectionState.init(),
    alternate_selection: SelectionState = SelectionState.init(),
    alt_active: bool = false,

    /// Takes primary and alternate screen values into one screen set.
    pub fn init(primary: Screen, alternate: Screen) Set {
        return .{ .primary = primary, .alternate = alternate };
    }

    /// Returns the mutable screen selected by alternate-screen state.
    pub fn active(self: *Set) *Screen {
        return if (self.alt_active) &self.alternate else &self.primary;
    }

    /// Returns the borrowed screen selected by alternate-screen state.
    pub fn activeConst(self: *const Set) *const Screen {
        return if (self.alt_active) &self.alternate else &self.primary;
    }

    /// Returns mutable selection state paired with the active screen.
    pub fn activeSelection(self: *Set) *SelectionState {
        return if (self.alt_active) &self.alternate_selection else &self.primary_selection;
    }

    /// Returns borrowed selection state paired with the active screen.
    pub fn activeSelectionConst(self: *const Set) *const SelectionState {
        return if (self.alt_active) &self.alternate_selection else &self.primary_selection;
    }

    /// Resets the active screen while preserving selection and alternate-screen state.
    pub fn reset(self: *Set) void {
        self.active().reset();
    }

    /// Atomically resize primary and alternate screens.
    ///
    /// Allocation failure leaves both screens unchanged and at matching
    /// dimensions.
    pub fn resize(self: *Set, allocator: std.mem.Allocator, rows: u16, cols: u16) std.mem.Allocator.Error!void {
        var primary = try self.primary.prepareResize(allocator, rows, cols);
        errdefer primary.deinit(allocator);
        var alternate = try self.alternate.prepareResize(allocator, rows, cols);
        errdefer alternate.deinit(allocator);

        std.mem.swap(Screen, &self.primary, &primary);
        std.mem.swap(Screen, &self.alternate, &alternate);
        primary.deinit(allocator);
        alternate.deinit(allocator);
    }

    /// Copies one nonzero host cell-pixel fact to both screen identities.
    pub fn setCellPixelSize(self: *Set, width: u32, height: u32) void {
        self.primary.setCellPixelSize(width, height);
        self.alternate.setCellPixelSize(width, height);
    }

    /// Releases both screens through their shared terminal allocator.
    pub fn deinit(self: *Set, allocator: std.mem.Allocator) void {
        self.primary.deinit(allocator);
        self.alternate.deinit(allocator);
    }
};

/// Builds a borrowed viewport at a clamped scrollback offset.
pub fn visibleView(screen_state: *const Set, scrollback_offset: u32) View {
    const active = screen_state.activeConst();
    const history_count: u32 = if (screen_state.alt_active) 0 else active.historyCount();
    const offset = @min(scrollback_offset, history_count);
    const rows_count: u32 = active.rows;
    const total_rows = history_count + rows_count;
    const start = if (total_rows >= rows_count + offset) total_rows - rows_count - offset else 0;
    const cursor_visible = active.cursor.visible and offset == 0;
    std.debug.assert(offset <= history_count);
    std.debug.assert(total_rows >= rows_count);
    std.debug.assert(start + rows_count <= total_rows);
    std.debug.assert(total_rows - (start + rows_count) == offset);
    return .{
        .rows = active.rows,
        .cols = active.cols,
        .cursor_row = active.cursor.row,
        .cursor_col = active.cursor.col,
        .cursor_visible = cursor_visible,
        .cursor_shape = active.cursor.effective_shape,
        .cursor_blink = active.cursor.blink_intent,
        .is_alternate_screen = screen_state.alt_active,
        .scrollback_offset = offset,
        .history_count = history_count,
        .history_row_base = active.historyRowBase(),
        .start = start,
        .screen = active,
    };
}

// Builds a borrowed view and selection at a clamped u64 offset.
fn projectSurface(screen_state: *const Set, scrollback_offset: u64) SurfaceSnapshot {
    const history_count: u64 = if (screen_state.alt_active)
        0
    else
        screen_state.activeConst().historyCount();
    const offset: u32 = @intCast(@min(scrollback_offset, history_count));
    const view = visibleView(screen_state, offset);
    const dirty = peekDirtyRows(screen_state);
    return .{
        .view = view,
        .dirty = dirty,
        .selection = screen_state.activeSelectionConst().state(),
    };
}

fn peekDirtyRows(screen_state: *const Set) ?Screen.DirtyRows {
    return screen_state.activeConst().peekDirtyRows();
}

fn copyDirtyRows(dirty_rows_out: []u8, cols_start: []u16, cols_end: []u16, dirty: ?Screen.DirtyRows) void {
    @memset(dirty_rows_out, 0);
    @memset(cols_start, 0);
    @memset(cols_end, 0);
    if (dirty) |value| {
        std.debug.assert(value.dirty_cols_start.len == dirty_rows_out.len);
        std.debug.assert(value.dirty_cols_end.len == dirty_rows_out.len);
        @memcpy(cols_start, value.dirty_cols_start);
        @memcpy(cols_end, value.dirty_cols_end);
        var dirty_row = value.start_row;
        while (dirty_row <= value.end_row and dirty_row < dirty_rows_out.len) : (dirty_row += 1) {
            dirty_rows_out[dirty_row] = 1;
        }
    }
}

/// Acknowledges dirty state on the active screen.
pub fn clearDirtyRows(screen_state: *Set) void {
    screen_state.active().clearDirtyRows();
}

/// Returns one history codepoint by recency.
pub fn historyRowAt(screen_state: *const Set, history_idx: u32, col: u16) u21 {
    if (screen_state.alt_active) return 0;
    return screen_state.primary.historyRowAt(history_idx, col);
}

fn historyCellAt(screen_state: *const Set, history_idx: u32, col: u16) Screen.Cell {
    if (screen_state.alt_active) return Screen.default_cell;
    return screen_state.primary.historyCellAt(history_idx, col);
}

/// Returns the configured active-screen history row capacity.
pub fn historyCapacity(screen_state: *const Set) u16 {
    return screen_state.primary.historyCapacity();
}

fn rowIndex(row: u16) u32 {
    return row;
}

/// Selection endpoint coordinate in stable projected scrollback rows.
const SelectionPos = struct {
    row: i32,
    col: u16,
};

/// Selection state snapshot.
pub const TerminalSelection = struct {
    active: bool,
    selecting: bool,
    start: SelectionPos,
    end: SelectionPos,
};

// Selection lifecycle state container.
const SelectionState = struct {
    selection: TerminalSelection,

    /// Initialize inactive selection state.
    pub fn init() SelectionState {
        return .{
            .selection = .{
                .active = false,
                .selecting = false,
                .start = .{ .row = 0, .col = 0 },
                .end = .{ .row = 0, .col = 0 },
            },
        };
    }

    /// Clear and deactivate selection.
    pub fn clear(self: *SelectionState) void {
        self.selection.active = false;
        self.selection.selecting = false;
    }

    /// Start selection at row/column.
    pub fn start(self: *SelectionState, row: i32, col: u16) void {
        self.selection.active = true;
        self.selection.selecting = true;
        self.selection.start = .{ .row = row, .col = col };
        self.selection.end = .{ .row = row, .col = col };
    }

    /// Update selection end coordinate.
    pub fn update(self: *SelectionState, row: i32, col: u16) void {
        if (!self.selection.active) return;
        self.selection.end = .{ .row = row, .col = col };
    }

    /// Mark current selection as finished.
    pub fn finish(self: *SelectionState) void {
        if (!self.selection.active) return;
        self.selection.selecting = false;
    }

    /// Clear the selection when grid changes invalidate either endpoint.
    pub fn clearIfInvalidatedByGrid(self: *SelectionState, screen: *const Screen) void {
        if (!self.selection.active) return;
        if (screen.shouldInvalidateSelectionEndpoint(self.selection.start.row) or
            screen.shouldInvalidateSelectionEndpoint(self.selection.end.row))
        {
            self.clear();
        }
    }

    /// Return active selection snapshot or null.
    pub fn state(self: *const SelectionState) ?TerminalSelection {
        if (!self.selection.active) return null;
        return self.selection;
    }
};

// Returns selection endpoints in document order without mutating selection state.
fn orderedSelection(sel: TerminalSelection) struct { start: SelectionPos, end: SelectionPos } {
    if (sel.start.row < sel.end.row) return .{ .start = sel.start, .end = sel.end };
    if (sel.start.row > sel.end.row) return .{ .start = sel.end, .end = sel.start };
    if (sel.start.col <= sel.end.col) return .{ .start = sel.start, .end = sel.end };
    return .{ .start = sel.end, .end = sel.start };
}

test "selection: start in viewport coordinates" {
    var s = SelectionState.init();
    s.start(5, 10);
    const sel = s.state().?;
    try std.testing.expectEqual(@as(i32, 5), sel.start.row);
    try std.testing.expectEqual(@as(u16, 10), sel.start.col);
    try std.testing.expect(sel.active);
    try std.testing.expect(sel.selecting);
}

test "selection: start in projected scrollback coordinates" {
    var s = SelectionState.init();
    s.start(3, 7);
    const sel = s.state().?;
    try std.testing.expectEqual(@as(i32, 3), sel.start.row);
    try std.testing.expectEqual(@as(u16, 7), sel.start.col);
}

test "selection: update spanning projected rows" {
    var s = SelectionState.init();
    s.start(1, 0);
    s.update(5, 20);
    const sel = s.state().?;
    try std.testing.expectEqual(@as(i32, 1), sel.start.row);
    try std.testing.expectEqual(@as(i32, 5), sel.end.row);
    try std.testing.expectEqual(@as(u16, 20), sel.end.col);
}

test "selection: inactive returns null" {
    var s = SelectionState.init();
    try std.testing.expectEqual(@as(?TerminalSelection, null), s.state());
}

test "selection: start and update with viewport coordinates" {
    var sel = SelectionState.init();
    sel.start(5, 10);
    var state = sel.state().?;
    try std.testing.expectEqual(@as(i32, 5), state.start.row);
    try std.testing.expectEqual(@as(u16, 10), state.start.col);

    sel.update(7, 15);
    state = sel.state().?;
    try std.testing.expectEqual(@as(i32, 7), state.end.row);
    try std.testing.expectEqual(@as(u16, 15), state.end.col);
}

test "selection: start and update with projected coordinates" {
    var sel = SelectionState.init();
    sel.start(3, 2);
    var state = sel.state().?;
    try std.testing.expectEqual(@as(i32, 3), state.start.row);
    try std.testing.expectEqual(@as(u16, 2), state.start.col);

    sel.update(5, 8);
    state = sel.state().?;
    try std.testing.expectEqual(@as(i32, 5), state.end.row);
    try std.testing.expectEqual(@as(u16, 8), state.end.col);
}

test "selection: span projected rows" {
    var sel = SelectionState.init();
    sel.start(2, 0);
    var state = sel.state().?;
    try std.testing.expectEqual(@as(i32, 2), state.start.row);

    sel.update(5, 20);
    state = sel.state().?;
    try std.testing.expectEqual(@as(i32, 2), state.start.row);
    try std.testing.expectEqual(@as(i32, 5), state.end.row);
    try std.testing.expect(state.active);
    try std.testing.expect(state.selecting);
}

test "selection: clear deactivates selection" {
    var sel = SelectionState.init();
    sel.start(2, 5);
    try std.testing.expect(sel.state() != null);

    sel.clear();
    try std.testing.expectEqual(@as(?TerminalSelection, null), sel.state());
}

test "selection: finish stops selecting but keeps active" {
    var sel = SelectionState.init();
    sel.start(3, 7);
    var state = sel.state().?;
    try std.testing.expect(state.selecting);

    sel.finish();
    state = sel.state().?;
    try std.testing.expect(state.active);
    try std.testing.expect(!state.selecting);
}

/// Stores a half-open visible column range for one projected selection row.
pub const Range = struct {
    start: u16,
    end_exclusive: u16,
};

// Failures produced while copying selected cells into UTF-8 caller storage.
const CopyError = error{
    CodepointTooLarge,
    OutOfMemory,
    Utf8CannotEncodeSurrogateHalf,
};

fn rowSource(screen_state: *const Set, row: i32) ?RowSource {
    if (row < 0) return null;
    const active = screen_state.activeConst();
    const absolute: u32 = std.math.cast(u32, row) orelse return null;
    const history_base = if (screen_state.alt_active) 0 else screen_state.primary.historyRowBase();
    if (absolute < history_base) return null;
    const logical_row = absolute - history_base;
    const history_count = if (screen_state.alt_active) 0 else screen_state.primary.historyCount();
    if (logical_row < history_count) return .{ .history = history_count - 1 - logical_row };
    const screen_row = logical_row - history_count;
    if (screen_row >= active.rows) return null;
    return .{ .screen = @intCast(screen_row) };
}

fn contentEndExclusive(screen_state: *const Set, row: i32) u16 {
    const source = rowSource(screen_state, row) orelse return 0;
    const active = screen_state.activeConst();
    var scan = active.cols;
    while (scan > 0) {
        const idx = scan - 1;
        const cell = switch (source) {
            .history => |recency| active.historyCellAt(recency, idx),
            .screen => |screen_row| active.cellInfoAt(screen_row, idx),
        };
        if (cell.codepoint != 0 and cell.codepoint != ' ') return scan;
        scan -= 1;
    }
    return if (active.cols > 0) 1 else 0;
}

fn visibleRow(view: View, row: u16) i32 {
    std.debug.assert(row < view.rows or view.rows == 0);
    const absolute = @as(u64, view.history_row_base) + @as(u64, view.start) + @as(u64, row);
    return std.math.cast(i32, absolute) orelse std.math.maxInt(i32);
}

/// Projects an ordered selection onto one visible row, or null outside the selection.
pub fn visibleRange(view: View, selected: TerminalSelection, row: u16) ?Range {
    std.debug.assert(row < view.rows or view.rows == 0);
    const ordered = orderedSelection(selected);
    const selected_row = visibleRow(view, row);
    if (selected_row < ordered.start.row or selected_row > ordered.end.row) return null;

    const row_end = view.contentEndExclusive(row);
    if (row_end == 0) return null;

    const range_start: u16 = if (selected_row == ordered.start.row) ordered.start.col else 0;
    const unclamped_end: u32 = if (selected_row == ordered.end.row)
        @as(u32, ordered.end.col) + 1
    else
        row_end;
    const range_end: u16 = @intCast(@min(unclamped_end, row_end));
    if (range_start >= range_end) return null;
    std.debug.assert(range_end <= view.cols);
    return .{ .start = range_start, .end_exclusive = range_end };
}

// Copy selected cells into caller-owned UTF-8 memory.
//
// The caller owns a successful non-empty result. Invalid stored codepoints
// are reported exactly instead of trapping during integer narrowing.
fn copyText(allocator: std.mem.Allocator, screen_state: *const Set, selected: ?TerminalSelection) CopyError![]const u8 {
    const active_selection = selected orelse return &.{};
    const ordered_selection = orderedSelection(active_selection);
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var row = ordered_selection.start.row;
    while (row <= ordered_selection.end.row) : (row += 1) {
        const source = rowSource(screen_state, row) orelse break;
        const row_start = if (row == ordered_selection.start.row) ordered_selection.start.col else 0;
        const row_end = if (row == ordered_selection.end.row)
            @as(u16, @intCast(@min(@as(u32, ordered_selection.end.col) + 1, @as(u32, screen_state.activeConst().cols))))
        else
            contentEndExclusive(screen_state, row);
        if (row_end > row_start) {
            var col = row_start;
            while (col < row_end) : (col += 1) {
                const cell = switch (source) {
                    .history => |recency| screen_state.primary.historyCellAt(recency, col),
                    .screen => |screen_row| screen_state.activeConst().cellInfoAt(screen_row, col),
                };
                if (cell.codepoint == 0) continue;
                var utf8: [4]u8 = undefined;
                const codepoint = std.math.cast(u21, cell.codepoint) orelse return error.CodepointTooLarge;
                const len = try std.unicode.utf8Encode(codepoint, &utf8);
                try out.appendSlice(allocator, utf8[0..len]);
            }
        }
        if (row != ordered_selection.end.row) try out.append(allocator, '\n');
    }
    return out.toOwnedSlice(allocator);
}

// Tracks monotonic mutation, snapshot, and acknowledgement identities.
const Publication = struct {
    seq: u64 = 1,
    dirty_generation: u64 = 0,
    scrollback_offset: u64 = 0,
    start: u64 = 0,
    rows: u16 = 0,
    cols: u16 = 0,
    alt: bool = false,

    /// Publishes a new snapshot only when mutation advanced beyond the last publication.
    pub fn publish(self: *Publication, view: View, scrollback_offset: u64, dirty_generation: u64) u64 {
        std.debug.assert(view.rows > 0);
        std.debug.assert(view.cols > 0);
        const same_dirty = self.dirty_generation == dirty_generation;
        const same_offset = self.scrollback_offset == scrollback_offset;
        const same_start = self.start == view.start;
        const same_rows = self.rows == view.rows;
        const same_cols = self.cols == view.cols;
        const same_alt = self.alt == view.is_alternate_screen;
        if (!(same_dirty and same_offset and same_start and same_rows and same_cols and same_alt)) {
            if (self.dirty_generation != 0) self.seq +%= 1;
            self.dirty_generation = dirty_generation;
            self.scrollback_offset = scrollback_offset;
            self.start = view.start;
            self.rows = view.rows;
            self.cols = view.cols;
            self.alt = view.is_alternate_screen;
        }
        std.debug.assert(self.seq != 0);
        return self.seq;
    }

    /// Accepts acknowledgement only for a nonzero snapshot no newer than publication.
    pub fn canAck(self: Publication, snapshot_seq: u64, dirty_generation_current: u64) bool {
        if (snapshot_seq == 0) return false;
        return self.seq == snapshot_seq and self.dirty_generation == dirty_generation_current;
    }
};

// Apply one host-directed semantic event and retain its bounded consequence.
fn applyHostEvent(vt: *Terminal, event: SemanticEvent) ApplyError!bool {
    var scratch: Scratch = .{};
    const allocator = vt.allocator;
    switch (event) {
        .bell => try vt.host.ringBell(),
        .title_and_icon_set => |value| return vt.host.replaceTitleAndIcon(value),
        .title_set => |title| return vt.host.replaceTitle(title),
        .icon_set => |icon| return vt.host.replaceIcon(icon),
        .shell_integration_set => |integration| try vt.host.replaceShellIntegration(integration),
        .working_directory_report => |directory| return vt.host.replaceWorkingDirectoryReport(directory),
        .shell_mark => |mark| try vt.host.replaceShellMark(mark),
        .color_control => |cmd| {
            const before = vt.host.colors;
            const output_before = byteCount(vt.host.pending_output.bytes.items);
            errdefer {
                vt.host.colors = before;
                restorePendingOutput(&vt.host.pending_output, output_before);
            }
            switch (cmd.command) {
                21 => try handleKittyControl(allocator, &vt.host.colors, &vt.host.pending_output, cmd.payload),
                4 => try handleXtermPaletteControl(
                    allocator,
                    &vt.host.colors,
                    &vt.host.pending_output,
                    scratch.buf[0..],
                    cmd.payload,
                ),
                5 => try handleXtermSpecialPaletteControl(
                    allocator,
                    &vt.host.colors,
                    &vt.host.pending_output,
                    scratch.buf[0..],
                    cmd.payload,
                ),
                10, 11, 12, 13, 14, 15, 16, 17, 18, 19 => try handleXtermDynamicColor(
                    allocator,
                    &vt.host.colors,
                    &vt.host.pending_output,
                    scratch.buf[0..],
                    cmd.command,
                    cmd.payload,
                ),
                104 => resetXtermPalette(&vt.host.colors, cmd.payload),
                110, 111, 112, 113, 114, 115, 116, 117, 118, 119 => resetXtermDynamicColor(
                    &vt.host.colors,
                    cmd.command,
                    cmd.payload,
                ),
                else => {},
            }
            return !std.meta.eql(before, vt.host.colors) or output_before != vt.host.pending_output.bytes.items.len;
        },
        .hyperlink_set => |spec| return vt.screen_state.active().setCurrentLinkId(try vt.host.internHyperlink(spec)),
        .hyperlink_clear => return vt.screen_state.active().setCurrentLinkId(0),
        .clipboard_set => |payload| return try vt.host.replaceClipboard(payload),
        .locator_reporting => |cfg| setReporting(&vt.host.locator, cfg.mode, cfg.unit),
        .locator_filter => |area| setFilter(&vt.host.locator, area),
        .locator_events => |modes| setEvents(&vt.host.locator, modes.params[0..modes.param_count]),
        .locator_request => |param| try appendReportForRequest(
            &vt.host.locator,
            allocator,
            &vt.host.pending_output,
            scratch.buf[0..],
            param,
        ),
        .media_copy_request => |param| vt.host.media_copy_request = param,
        .dcs_payload => |payload| try vt.host.replaceDcsPayload(payload),
        .legacy_control => |kind| vt.host.legacy_control = kind,
        else => unreachable,
    }
    return true;
}

const xtversion_text = "howl-vt dev";
const terminal_report_max_bytes = 64;

const CursorReportView = struct {
    rows: u16,
    cols: u16,
    cursor_row: u16,
    cursor_col: u16,
    origin_mode: bool = false,
    origin_top: u16 = 0,
    origin_left: u16 = 0,
};

const RectChecksumRequest = struct {
    request_id: u16,
};

// Apply one report-directed semantic event to bounded host output.
fn applyReportEvent(vt: *Terminal, event: SemanticEvent) ApplyError!void {
    var scratch: Scratch = .{};
    const allocator = vt.allocator;
    const pending_output = &vt.host.pending_output;
    const encode_buf = scratch.buf[0..];
    const active = vt.screen_state.activeConst();
    const render_view = CursorReportView{
        .rows = active.rows,
        .cols = active.cols,
        .cursor_row = active.cursor.row,
        .cursor_col = active.cursor.col,
        .origin_mode = active.origin_mode,
        .origin_top = active.scroll_top,
        .origin_left = if (active.left_right_margin_mode) active.left_margin else 0,
    };
    const ansi_modes = AnsiView{
        .keyboard_action_mode = vt.modes.keyboard_action_mode,
        .insert_mode = active.insert_mode,
        .send_receive_mode = vt.modes.send_receive_mode,
        .newline_mode = vt.modes.newline_mode,
    };
    const dec_modes = DecView{
        .application_cursor_keys = vt.modes.application_cursor_keys,
        .application_keypad = vt.modes.application_keypad,
        .auto_repeat = vt.modes.auto_repeat,
        .reverse_screen_mode = vt.modes.reverse_screen_mode,
        .origin_mode = active.origin_mode,
        .auto_wrap = active.auto_wrap,
        .left_right_margin_mode = active.left_right_margin_mode,
        .cursor_blink = active.cursor.blink_intent,
        .cursor_visible = active.cursor.visible,
        .alt_active = vt.screen_state.alt_active,
        .mouse_tracking = vt.modes.mouse_tracking,
        .mouse_protocol = vt.modes.mouse_protocol,
        .focus_reporting = vt.modes.focus_reporting,
        .bracketed_paste = vt.modes.bracketed_paste,
        .synchronized_output = vt.modes.synchronized_output,
        .inband_resize_notifications = vt.modes.inband_resize_notifications,
        .reverse_wraparound = vt.modes.reverse_wraparound_mode,
        .extended_reverse_wraparound = vt.modes.extended_reverse_wraparound_mode,
    };
    switch (event) {
        .ansi_mode_query => |mode| try appendAnsiModeReport(
            allocator,
            pending_output,
            encode_buf,
            mode,
            ansiModeStateForView(ansi_modes, mode),
        ),
        .modify_other_keys_query => try appendModifyOtherKeysReport(
            allocator,
            pending_output,
            encode_buf,
            vt.modes.modify_other_keys,
        ),
        .key_format_query => |resource| if (isKeyFormatResource(resource))
            try appendKeyFormatReport(
                allocator,
                pending_output,
                encode_buf,
                resource,
                vt.modes.key_format[resource],
            ),
        .dec_mode_query => |mode| try appendDecModeReport(
            allocator,
            pending_output,
            encode_buf,
            mode,
            decModeStateForView(dec_modes, mode),
        ),
        .dcs_request_status => |request| try appendDecrqssReply(allocator, pending_output, encode_buf, active, request),
        .dcs_request_termcap => |request| try appendTermcapReports(allocator, pending_output, request),
        .dcs_request_resource => |request| try appendResourceInvalidReport(allocator, pending_output, request),
        .device_status_report => try appendCsiReply(pending_output, allocator, .terminal, "0n"),
        .dec_device_status_report => |param| try appendDeviceStatusReport(allocator, pending_output, encode_buf, param),
        .cursor_position_report => try appendCursorPositionReport(allocator, pending_output, encode_buf, render_view),
        .dec_cursor_position_report => try appendDecCursorPositionReport(
            allocator,
            pending_output,
            encode_buf,
            render_view,
        ),
        .primary_device_attributes => {
            const payload = std.fmt.bufPrint(encode_buf, "?{d};22c", .{dec_conformance_level}) catch unreachable;
            try appendCsiReply(pending_output, allocator, .terminal, payload);
        },
        .secondary_device_attributes => try appendCsiReply(pending_output, allocator, .terminal, ">1;10;0c"),
        .tertiary_device_attributes => try appendStringReply(
            pending_output,
            allocator,
            .terminal,
            .dcs,
            "!|00000000",
        ),
        .xtversion => try appendXtVersionReport(allocator, pending_output),
        .xttitlepos => try appendTitleStackPositionReport(allocator, pending_output, encode_buf, 0, 0),
        .xtchecksum => |flags| vt.xtchecksum_flags = flags,
        .rect_checksum_request => |req| try appendRectChecksumReport(
            allocator,
            pending_output,
            encode_buf,
            .{ .request_id = req.request_id },
            computeRectChecksum(active, vt.xtchecksum_flags, req.page, req.area),
        ),
        .selected_graphic_rendition_report => |area| try appendSelectedGraphicRenditionReport(
            allocator,
            pending_output,
            encode_buf,
            active,
            area,
        ),
        .screen_extent_report => try appendScreenExtentReport(allocator, pending_output, encode_buf, render_view),
        .parameters_report => |kind| try appendTerminalParametersReport(allocator, pending_output, encode_buf, kind),
        .window_title_report => try appendWindowTitleReport(vt),
        .xtreportcolors => try appendColorStackReport(allocator, pending_output, encode_buf, &vt.kitty.color_stack),
        .iterm_report_cell_size => try appendItermCellSizeReport(vt, encode_buf),
        else => unreachable,
    }
}

fn applyTitleStack(host: *HostState, command: @FieldType(SemanticEvent, "title_stack")) ApplyError!TitleStackEffect {
    if (command.option != 0 and command.option != 2) return .{};
    return switch (command.command) {
        .push => .{ .changed = try host.pushTitle() },
        .pop => host.popTitle(),
    };
}

fn appendWindowTitleReport(vt: *Terminal) ApplyError!void {
    const output = &vt.host.pending_output;
    const start = byteCount(output.bytes.items);
    errdefer restorePendingOutput(output, start);
    try appendReplyControl(output, vt.allocator, .iterm, .osc);
    try appendOutput(output, vt.allocator, "l");
    if (vt.host.current_title) |title| try appendOutput(output, vt.allocator, title);
    try appendReplyControl(output, vt.allocator, .iterm, .st);
}

fn appendSizeReport(vt: *Terminal, scratch: []u8, kind: SizeReport) ApplyError!bool {
    const active = vt.screen_state.activeConst();
    const payload = switch (kind) {
        .text_cells => std.fmt.bufPrint(scratch, "8;{d};{d}t", .{ active.rows, active.cols }) catch unreachable,
        .cell_pixels => blk: {
            const cell = active.cellPixelSize() orelse return false;
            break :blk std.fmt.bufPrint(scratch, "6;{d};{d}t", .{ cell.height, cell.width }) catch unreachable;
        },
        .window_pixels => blk: {
            // Without a distinct host frame fact, Ps=2 retains the text-area fallback.
            const cell = active.cellPixelSize() orelse return false;
            const height = @as(u64, cell.height) * @as(u64, active.rows);
            const width = @as(u64, cell.width) * @as(u64, active.cols);
            break :blk std.fmt.bufPrint(scratch, "4;{d};{d}t", .{ height, width }) catch unreachable;
        },
    };
    try appendCsiReply(&vt.host.pending_output, vt.allocator, .terminal, payload);
    return true;
}

fn appendItermCellSizeReport(vt: *Terminal, scratch: []u8) ApplyError!void {
    const cell = vt.cellPixelSize() orelse return;
    // The current host supplies logical pixel metrics and owns no output-scale
    // protocol, so points equal pixels and the reported scale is exactly one.
    const payload = std.fmt.bufPrint(
        scratch,
        "1337;ReportCellSize={d};{d};1",
        .{ cell.height, cell.width },
    ) catch unreachable;
    try appendStringReply(&vt.host.pending_output, vt.allocator, .iterm, .osc, payload);
}

fn appendDecrqssReply(
    allocator: std.mem.Allocator,
    output: *PendingOutput,
    encode_buf: []u8,
    screen: *const Screen,
    request: []const u8,
) ApplyError!void {
    const start = byteCount(output.bytes.items);
    errdefer restorePendingOutput(output, start);
    try appendReplyControl(output, allocator, .terminal, .dcs);
    if (std.mem.eql(u8, request, "m")) {
        try appendOutput(output, allocator, "1$r");
        try appendSgrAttrs(allocator, output, encode_buf, currentAttrs(screen));
        try appendReplyControl(output, allocator, .terminal, .st);
        return;
    }
    if (decrqssPayload(encode_buf, screen, request)) |payload| {
        try appendOutput(output, allocator, "1$r");
        try appendOutput(output, allocator, payload);
        try appendReplyControl(output, allocator, .terminal, .st);
        return;
    }
    try appendOutput(output, allocator, "0$r");
    try appendReplyControl(output, allocator, .terminal, .st);
}

// Howl identifies as a VT220-class terminal in DA1 and DECRQSS DECSCL.
const dec_conformance_level: u8 = 62;

fn decrqssPayload(encode_buf: []u8, screen: *const Screen, request: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, request, "\"p")) {
        return std.fmt.bufPrint(encode_buf, "{d}\"p", .{dec_conformance_level}) catch null;
    }
    if (std.mem.eql(u8, request, "r")) {
        const bottom = if (screen.rows == 0) @as(u16, 0) else @min(screen.scroll_bottom, screen.rows - 1);
        return std.fmt.bufPrint(encode_buf, "{d};{d}r", .{ screen.scroll_top + 1, bottom + 1 }) catch null;
    }
    if (std.mem.eql(u8, request, "s")) {
        const left = if (screen.left_right_margin_mode) screen.left_margin else 0;
        const right = if (screen.left_right_margin_mode) screen.right_margin else screen.cols -| 1;
        return std.fmt.bufPrint(encode_buf, "{d};{d}s", .{ left + 1, right + 1 }) catch null;
    }
    if (std.mem.eql(u8, request, " q")) {
        const style = screen.cursor.effectiveStyle();
        const value: u8 = switch (style.shape) {
            .none => 1,
            .block => if (style.blink) 1 else 2,
            .underline => if (style.blink) 3 else 4,
            .bar => if (style.blink) 5 else 6,
        };
        return std.fmt.bufPrint(encode_buf, "{d} q", .{value}) catch null;
    }
    if (std.mem.eql(u8, request, "\"q")) {
        const value: u8 = if (screen.current_attrs.protected == .dec) 1 else 2;
        return std.fmt.bufPrint(encode_buf, "{d}\"q", .{value}) catch null;
    }
    if (std.mem.eql(u8, request, "*x")) {
        const value: u8 = if (screen.attr_change_extent_rect) 2 else 0;
        return std.fmt.bufPrint(encode_buf, "{d}*x", .{value}) catch null;
    }
    if (std.mem.eql(u8, request, "t")) {
        return std.fmt.bufPrint(encode_buf, "{d}t", .{@max(@as(u16, 24), screen.rows)}) catch null;
    }
    return null;
}

fn appendModifyOtherKeysReport(
    allocator: std.mem.Allocator,
    output: *PendingOutput,
    encode_buf: []u8,
    value: i8,
) ApplyError!void {
    const payload = formatTerminalReport(encode_buf, ">4;{d}m", .{value});
    try appendCsiReply(output, allocator, .terminal, payload);
}

fn appendKeyFormatReport(
    allocator: std.mem.Allocator,
    output: *PendingOutput,
    encode_buf: []u8,
    resource: u8,
    value: u16,
) ApplyError!void {
    const payload = formatTerminalReport(encode_buf, ">{d};{d}f", .{ resource, value });
    try appendCsiReply(output, allocator, .terminal, payload);
}

fn appendXtVersionReport(allocator: std.mem.Allocator, output: *PendingOutput) ApplyError!void {
    try appendStringReply(output, allocator, .terminal, .dcs, ">|" ++ xtversion_text);
}

const TermcapValue = union(enum) {
    flag,
    encoded: []const u8,
};

// Answers only capability facts owned by terminal state rather than host configuration.
fn termcapValue(encoded_name: []const u8) ?TermcapValue {
    if (hexNameEquals(encoded_name, "Co") or hexNameEquals(encoded_name, "colors"))
        return .{ .encoded = "323536" };
    if (hexNameEquals(encoded_name, "RGB")) return .{ .encoded = "38" };
    if (hexNameEquals(encoded_name, "Tc") or hexNameEquals(encoded_name, "Su")) return .flag;
    return null;
}

fn hexNameEquals(encoded: []const u8, name: []const u8) bool {
    if (encoded.len % 2 != 0 or encoded.len / 2 != name.len) return false;
    for (name, 0..) |byte, index| {
        const high = std.fmt.charToDigit(encoded[index * 2], 16) catch return false;
        const low = std.fmt.charToDigit(encoded[index * 2 + 1], 16) catch return false;
        if (((high << 4) | low) != byte) return false;
    }
    return true;
}

fn appendTermcapReports(
    allocator: std.mem.Allocator,
    output: *PendingOutput,
    request: []const u8,
) ApplyError!void {
    const start = byteCount(output.bytes.items);
    errdefer restorePendingOutput(output, start);
    var names = std.mem.splitScalar(u8, request, ';');
    while (names.next()) |encoded_name| {
        try appendReplyControl(output, allocator, .terminal, .dcs);
        const value = termcapValue(encoded_name);
        try appendOutput(output, allocator, if (value == null) "0+r" else "1+r");
        try appendOutput(output, allocator, encoded_name);
        if (value) |known| switch (known) {
            .flag => {},
            .encoded => |encoded_value| {
                try appendOutput(output, allocator, "=");
                try appendOutput(output, allocator, encoded_value);
            },
        };
        try appendReplyControl(output, allocator, .terminal, .st);
    }
}

test "XTGETTCAP reply allocation failure rolls back the complete ordered response" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        appendTermcapReportsAllocation,
        .{},
    );
}

fn appendTermcapReportsAllocation(allocator: std.mem.Allocator) !void {
    var output = PendingOutput.init();
    defer output.bytes.deinit(allocator);
    appendTermcapReports(allocator, &output, "436F;5463;626F677573") catch |failure| {
        try std.testing.expectEqual(@as(usize, 0), output.bytes.items.len);
        return failure;
    };
    try std.testing.expectEqualStrings(
        "\x1bP1+r436F=323536\x1b\\\x1bP1+r5463\x1b\\\x1bP0+r626F677573\x1b\\",
        output.bytes.items,
    );
}

fn appendResourceInvalidReport(
    allocator: std.mem.Allocator,
    output: *PendingOutput,
    request: []const u8,
) ApplyError!void {
    const start = byteCount(output.bytes.items);
    errdefer restorePendingOutput(output, start);
    try appendReplyControl(output, allocator, .terminal, .dcs);
    try appendOutput(output, allocator, "0+R");
    try appendOutput(output, allocator, request);
    try appendReplyControl(output, allocator, .terminal, .st);
}

fn appendTitleStackPositionReport(
    allocator: std.mem.Allocator,
    output: *PendingOutput,
    encode_buf: []u8,
    current: u16,
    max: u16,
) ApplyError!void {
    const payload = formatTerminalReport(encode_buf, "{d};{d}#S", .{ current, max });
    try appendCsiReply(output, allocator, .terminal, payload);
}

fn appendCursorPositionReport(
    allocator: std.mem.Allocator,
    output: *PendingOutput,
    encode_buf: []u8,
    render_view: CursorReportView,
) ApplyError!void {
    const row = reportCursorCoordinate(render_view.cursor_row, render_view.origin_top, render_view.origin_mode);
    const col = reportCursorCoordinate(render_view.cursor_col, render_view.origin_left, render_view.origin_mode);
    const payload = formatTerminalReport(
        encode_buf,
        "{d};{d}R",
        .{ row, col },
    );
    try appendCsiReply(output, allocator, .terminal, payload);
}

fn appendDecCursorPositionReport(
    allocator: std.mem.Allocator,
    output: *PendingOutput,
    encode_buf: []u8,
    render_view: CursorReportView,
) ApplyError!void {
    const row = reportCursorCoordinate(render_view.cursor_row, render_view.origin_top, render_view.origin_mode);
    const col = reportCursorCoordinate(render_view.cursor_col, render_view.origin_left, render_view.origin_mode);
    const payload = formatTerminalReport(
        encode_buf,
        "?{d};{d}R",
        .{ row, col },
    );
    try appendCsiReply(output, allocator, .terminal, payload);
}

// A restored cursor may precede current margins; relative reports clamp that
// valid cross-savepoint state to the first addressable origin coordinate.
fn reportCursorCoordinate(position: u16, origin: u16, relative: bool) u32 {
    const zero_based: u32 = if (relative) position -| origin else position;
    return zero_based + 1;
}

test "cursor report coordinate saturates origin and preserves one-based u16 extent" {
    try std.testing.expectEqual(@as(u32, 1), reportCursorCoordinate(2, 6, true));
    try std.testing.expectEqual(@as(u32, 65_536), reportCursorCoordinate(std.math.maxInt(u16), 0, false));
}

fn appendDecModeReport(
    allocator: std.mem.Allocator,
    output: *PendingOutput,
    encode_buf: []u8,
    mode: u16,
    state: u8,
) ApplyError!void {
    const payload = formatTerminalReport(encode_buf, "?{d};{d}$y", .{ mode, state });
    try appendCsiReply(output, allocator, .terminal, payload);
}

fn appendAnsiModeReport(
    allocator: std.mem.Allocator,
    output: *PendingOutput,
    encode_buf: []u8,
    mode: u16,
    state: u8,
) ApplyError!void {
    const payload = formatTerminalReport(encode_buf, "{d};{d}$y", .{ mode, state });
    try appendCsiReply(output, allocator, .terminal, payload);
}

fn appendColorStackReport(
    allocator: std.mem.Allocator,
    output: *PendingOutput,
    encode_buf: []u8,
    stack: *const KittyColorStack,
) ApplyError!void {
    const index = if (stack.len == 0) 0 else stack.len - 1;
    const payload = formatTerminalReport(encode_buf, "{d};{d}#Q", .{ index, stack.len });
    try appendCsiReply(output, allocator, .kitty, payload);
}

fn appendTabStopReport(
    allocator: std.mem.Allocator,
    output: *PendingOutput,
    encode_buf: []u8,
    screen: *const Screen,
) ApplyError!void {
    const start = byteCount(output.bytes.items);
    errdefer restorePendingOutput(output, start);
    try appendReplyControl(output, allocator, .terminal, .dcs);
    try appendOutput(output, allocator, "2$u");
    var first = true;
    var col: u16 = 0;
    while (col < screen.cols) : (col += 1) {
        if (!screen.tabStopAt(col)) continue;
        if (!first) try appendOutput(output, allocator, "/");
        first = false;
        const text = formatTerminalReport(encode_buf, "{d}", .{col + 1});
        try appendOutput(output, allocator, text);
    }
    try appendReplyControl(output, allocator, .terminal, .st);
}

fn appendScreenExtentReport(
    allocator: std.mem.Allocator,
    output: *PendingOutput,
    encode_buf: []u8,
    render_view: CursorReportView,
) ApplyError!void {
    const payload = formatTerminalReport(encode_buf, "{d};{d};1;1;1\"w", .{ render_view.rows, render_view.cols });
    try appendCsiReply(output, allocator, .terminal, payload);
}

fn appendTerminalParametersReport(
    allocator: std.mem.Allocator,
    output: *PendingOutput,
    encode_buf: []u8,
    kind: u16,
) ApplyError!void {
    if (kind > 1) return;
    const payload = formatTerminalReport(encode_buf, "{d};1;1;128;128;1;0x", .{kind + 2});
    try appendCsiReply(output, allocator, .terminal, payload);
}

fn appendRectChecksumReport(
    allocator: std.mem.Allocator,
    output: *PendingOutput,
    encode_buf: []u8,
    req: RectChecksumRequest,
    checksum: u16,
) ApplyError!void {
    const payload = formatTerminalReport(encode_buf, "{d}!~{X:0>4}", .{ req.request_id, checksum });
    try appendStringReply(output, allocator, .terminal, .dcs, payload);
}

fn appendSelectedGraphicRenditionReport(
    allocator: std.mem.Allocator,
    output: *PendingOutput,
    encode_buf: []u8,
    screen: *const Screen,
    area: RectArea,
) ApplyError!void {
    const common = commonAttrsForRect(screen, area) orelse {
        try appendCsiReply(output, allocator, .terminal, "0m");
        return;
    };

    const start = byteCount(output.bytes.items);
    errdefer restorePendingOutput(output, start);
    try appendReplyControl(output, allocator, .terminal, .csi);
    try appendSgrAttrs(allocator, output, encode_buf, common);
}

// Appends one complete SGR parameter payload for retained terminal attributes.
fn appendSgrAttrs(
    allocator: std.mem.Allocator,
    output: *PendingOutput,
    encode_buf: []u8,
    attrs: CommonAttrs,
) ApplyError!void {
    var first = true;
    try appendSgrParam(allocator, output, &first, "0");
    if (attrs.bold) try appendSgrParam(allocator, output, &first, "1");
    if (attrs.dim) try appendSgrParam(allocator, output, &first, "2");
    if (attrs.italic) try appendSgrParam(allocator, output, &first, "3");
    if (attrs.underline) try appendSgrParam(allocator, output, &first, underlineStyleParam(attrs.underline_style));
    if (attrs.blink) try appendSgrParam(allocator, output, &first, "5");
    if (attrs.reverse) try appendSgrParam(allocator, output, &first, "7");
    if (attrs.invisible) try appendSgrParam(allocator, output, &first, "8");
    if (attrs.strikethrough) try appendSgrParam(allocator, output, &first, "9");
    if (attrs.font != 0) {
        const font = formatTerminalReport(encode_buf, "{d}", .{@as(u8, 10) + attrs.font});
        try appendSgrParam(allocator, output, &first, font);
    }
    try appendColorParam(allocator, output, encode_buf, &first, true, attrs.fg, Screen.default_cell_attrs.fg);
    try appendColorParam(allocator, output, encode_buf, &first, false, attrs.bg, Screen.default_cell_attrs.bg);
    if (attrs.underline and !colorEq(attrs.underline_color, Screen.default_underline_color)) {
        try appendExtendedColorParam(allocator, output, encode_buf, &first, 58, attrs.underline_color);
    }
    switch (attrs.baseline) {
        .normal => {},
        .raised => try appendSgrParam(allocator, output, &first, "73"),
        .lowered => try appendSgrParam(allocator, output, &first, "74"),
    }
    try appendOutput(output, allocator, "m");
}

fn computeRectChecksum(screen: *const Screen, xtchecksum_flags: u16, page: u16, area: RectArea) u16 {
    if (page != 1) return 0;
    const bounds = screen.rectBounds(area) orelse return 0;
    var sum: u16 = 0;
    var row = bounds.top;
    while (row <= bounds.bottom) : (row += 1) {
        var col = bounds.left;
        while (col <= bounds.right) : (col += 1) {
            const cell = screen.cellInfoAt(row, col);
            const is_blank = cell.codepoint == 0;
            if (is_blank and (xtchecksum_flags & (1 << 2)) == 0) continue;
            var cp: u32 = cell.codepoint;
            if ((xtchecksum_flags & (1 << 4)) == 0) cp &= 0xff;
            sum +%= @intCast(cp & 0xffff);
            if ((xtchecksum_flags & (1 << 1)) == 0) {
                sum +%= if (cell.attrs.bold) 1 else 0;
                sum +%= if (cell.attrs.underline) 2 else 0;
                sum +%= if (cell.attrs.blink) 4 else 0;
                sum +%= if (cell.attrs.reverse) 8 else 0;
            }
        }
    }
    if ((xtchecksum_flags & (1 << 0)) == 0) sum = ~sum;
    return sum;
}

const CommonAttrs = struct {
    font: u4,
    baseline: Screen.Baseline,
    bold: bool,
    dim: bool,
    italic: bool,
    underline: bool,
    underline_style: Screen.UnderlineStyle,
    underline_color: Screen.Color,
    blink: bool,
    reverse: bool,
    invisible: bool,
    strikethrough: bool,
    fg: Screen.Color,
    bg: Screen.Color,
};

// Copies current pen attributes into the shared bounded SGR report shape.
fn currentAttrs(screen: *const Screen) CommonAttrs {
    const attrs = screen.current_attrs;
    return .{
        .font = attrs.font,
        .baseline = attrs.baseline,
        .bold = attrs.bold,
        .dim = attrs.dim,
        .italic = attrs.italic,
        .underline = attrs.underline,
        .underline_style = attrs.underline_style,
        .underline_color = attrs.underline_color,
        .blink = attrs.blink,
        .reverse = attrs.reverse,
        .invisible = attrs.invisible,
        .strikethrough = attrs.strikethrough,
        .fg = attrs.fg,
        .bg = attrs.bg,
    };
}

fn commonAttrsForRect(screen: *const Screen, area: RectArea) ?CommonAttrs {
    const bounds = screen.rectBounds(area) orelse return null;
    const first_cell = screen.cellInfoAt(bounds.top, bounds.left);
    var common = CommonAttrs{
        .font = first_cell.attrs.font,
        .baseline = first_cell.attrs.baseline,
        .bold = first_cell.attrs.bold,
        .dim = first_cell.attrs.dim,
        .italic = first_cell.attrs.italic,
        .underline = first_cell.attrs.underline,
        .underline_style = first_cell.attrs.underline_style,
        .underline_color = first_cell.attrs.underline_color,
        .blink = first_cell.attrs.blink,
        .reverse = first_cell.attrs.reverse,
        .invisible = first_cell.attrs.invisible,
        .strikethrough = first_cell.attrs.strikethrough,
        .fg = first_cell.attrs.fg,
        .bg = first_cell.attrs.bg,
    };

    var row = bounds.top;
    while (row <= bounds.bottom) : (row += 1) {
        var col = bounds.left;
        while (col <= bounds.right) : (col += 1) {
            const attrs = screen.cellInfoAt(row, col).attrs;
            if (attrs.font != common.font) common.font = 0;
            if (attrs.baseline != common.baseline) common.baseline = .normal;
            if (attrs.bold != common.bold) common.bold = false;
            if (attrs.dim != common.dim) common.dim = false;
            if (attrs.italic != common.italic) common.italic = false;
            if (attrs.underline != common.underline) common.underline = false;
            if (attrs.blink != common.blink) common.blink = false;
            if (attrs.reverse != common.reverse) common.reverse = false;
            if (attrs.invisible != common.invisible) common.invisible = false;
            if (attrs.strikethrough != common.strikethrough) common.strikethrough = false;
            if (attrs.underline_style != common.underline_style) common.underline_style = .straight;
            if (!colorEq(attrs.fg, common.fg)) common.fg = Screen.default_cell_attrs.fg;
            if (!colorEq(attrs.bg, common.bg)) common.bg = Screen.default_cell_attrs.bg;
            if (!colorEq(attrs.underline_color, common.underline_color)) {
                common.underline_color = Screen.default_underline_color;
            }
        }
    }
    if (!common.underline) {
        common.underline_style = .straight;
        common.underline_color = Screen.default_underline_color;
    }
    return common;
}

fn appendSgrParam(
    allocator: std.mem.Allocator,
    output: *PendingOutput,
    first: *bool,
    text: []const u8,
) ApplyError!void {
    if (!first.*) try appendOutput(output, allocator, ";");
    first.* = false;
    try appendOutput(output, allocator, text);
}

fn underlineStyleParam(style: Screen.UnderlineStyle) []const u8 {
    return switch (style) {
        .straight => "4",
        .double => "4:2",
        .curly => "4:3",
        .dotted => "4:4",
        .dashed => "4:5",
    };
}

fn appendColorParam(
    allocator: std.mem.Allocator,
    output: *PendingOutput,
    encode_buf: []u8,
    first: *bool,
    is_fg: bool,
    color: Screen.Color,
    default_color: Screen.Color,
) ApplyError!void {
    if (colorEq(color, default_color)) return;
    switch (color.kind) {
        .default => return,
        .indexed => {
            const idx: u8 = @truncate(color.value);
            if (idx < 16) {
                const code: u16 = if (is_fg)
                    (if (idx < 8) 30 + idx else 90 + (idx - 8))
                else
                    (if (idx < 8) 40 + idx else 100 + (idx - 8));
                const text = formatTerminalReport(encode_buf, "{d}", .{code});
                try appendSgrParam(allocator, output, first, text);
                return;
            }
            try appendExtendedColorParam(allocator, output, encode_buf, first, if (is_fg) 38 else 48, color);
        },
        .rgb => try appendExtendedColorParam(allocator, output, encode_buf, first, if (is_fg) 38 else 48, color),
    }
}

fn appendExtendedColorParam(
    allocator: std.mem.Allocator,
    output: *PendingOutput,
    encode_buf: []u8,
    first: *bool,
    prefix: u8,
    color: Screen.Color,
) ApplyError!void {
    switch (color.kind) {
        .default => return,
        .indexed => {
            const text = formatTerminalReport(encode_buf, "{d};5;{d}", .{ prefix, color.value });
            try appendSgrParam(allocator, output, first, text);
        },
        .rgb => {
            const text = formatTerminalReport(encode_buf, "{d};2;{d};{d};{d}", .{
                prefix,
                (color.value >> 16) & 0xFF,
                (color.value >> 8) & 0xFF,
                color.value & 0xFF,
            });
            try appendSgrParam(allocator, output, first, text);
        },
    }
}

fn formatTerminalReport(encode_buf: []u8, comptime fmt: []const u8, args: anytype) []const u8 {
    std.debug.assert(encode_buf.len >= terminal_report_max_bytes);
    return std.fmt.bufPrint(encode_buf, fmt, args) catch unreachable;
}

fn colorEq(a: Screen.Color, b: Screen.Color) bool {
    return a.kind == b.kind and a.value == b.value;
}

test "cursor style report payload reads semantic cursor owner" {
    var screen = Screen.init(2, 2);
    screen.setDefaultCursorStyle(.{ .shape = .underline, .blink = false });
    screen.applyScreen(.{ .cursor_style = .{ .program_override = .{ .shape = .bar, .blink = true } } });

    var encode_buf: [64]u8 = undefined;
    const overridden = decrqssPayload(encode_buf[0..], &screen, " q").?;
    try std.testing.expectEqualStrings("5 q", overridden);

    screen.applyScreen(.{ .cursor_style = .{ .program_override = .{ .shape = .block, .blink = true } } });
    const block_blink = decrqssPayload(encode_buf[0..], &screen, " q").?;
    try std.testing.expectEqualStrings("1 q", block_blink);

    screen.applyScreen(.{ .cursor_style = .{ .program_override = .{ .shape = .none, .blink = false } } });
    const no_shape = decrqssPayload(encode_buf[0..], &screen, " q").?;
    try std.testing.expectEqualStrings("1 q", no_shape);
}

test "DECRQSS reply allocation failure preserves prior pending output" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        appendDecrqssReplyAllocation,
        .{},
    );
}

fn appendDecrqssReplyAllocation(allocator: std.mem.Allocator) !void {
    var output = PendingOutput.init();
    defer output.bytes.deinit(allocator);
    try appendOutput(&output, allocator, "kept");

    const screen = Screen.init(30, 80);
    var encode_buf: [terminal_report_max_bytes]u8 = undefined;
    appendDecrqssReply(allocator, &output, encode_buf[0..], &screen, "t") catch |failure| {
        try std.testing.expectEqualStrings("kept", output.bytes.items);
        return failure;
    };
    try std.testing.expectEqualStrings("kept\x1bP1$r30t\x1b\\", output.bytes.items);
}

test "DECRQSS reply capacity failure preserves the complete prior output" {
    const allocator = std.testing.allocator;
    var output = PendingOutput.init();
    defer output.bytes.deinit(allocator);
    const retained = try allocator.alloc(u8, pending_output_max_bytes - 1);
    defer allocator.free(retained);
    @memset(retained, 'k');
    try appendOutput(&output, allocator, retained);

    const screen = Screen.init(30, 80);
    var encode_buf: [terminal_report_max_bytes]u8 = undefined;
    try std.testing.expectError(
        error.ConsequenceLimit,
        appendDecrqssReply(allocator, &output, encode_buf[0..], &screen, "t"),
    );
    try std.testing.expectEqualSlices(u8, retained, output.bytes.items);
}

test "cursor position report payload names semantic cursor position" {
    var output = PendingOutput.init();
    defer output.bytes.deinit(std.testing.allocator);
    var encode_buf: [64]u8 = undefined;

    try appendCursorPositionReport(std.testing.allocator, &output, encode_buf[0..], .{
        .rows = 24,
        .cols = 80,
        .cursor_row = 2,
        .cursor_col = 4,
    });
    try std.testing.expectEqualStrings("\x1b[3;5R", output.bytes.items);
}

const Rgb = Screen.Rgb;
const osc_reply_max_bytes = 8;
const color_osc_max_bytes = 16;

// Owns the 256-color palette and dynamic foreground, background, and cursor colors.
const TerminalColorState = struct {
    foreground: Rgb = default_terminal_foreground,
    background: Rgb = default_terminal_background,
    cursor: ?Rgb = null,
    pointer_foreground: ?Rgb = null,
    pointer_background: ?Rgb = null,
    tektronix_foreground: ?Rgb = null,
    tektronix_background: ?Rgb = null,
    tektronix_cursor: ?Rgb = null,
    cursor_text: ?Rgb = null,
    selection_background: ?Rgb = null,
    selection_foreground: ?Rgb = null,
    special_palette: [5]?Rgb = [_]?Rgb{null} ** 5,
    palette: [256]Rgb = defaultPalette(),
};

const default_terminal_foreground = Rgb{ .r = 220, .g = 220, .b = 220 };
const default_terminal_background = Rgb{ .r = 24, .g = 25, .b = 33 };

const SpecialKey = enum { foreground, background, cursor, cursor_text, selection_background, selection_foreground };
const DynamicKey = enum {
    foreground,
    background,
    cursor,
    pointer_foreground,
    pointer_background,
    tektronix_foreground,
    tektronix_background,
    selection_background,
    tektronix_cursor,
    selection_foreground,
};
const SpecialPaletteKey = enum(u3) {
    bold = 0,
    underline = 1,
    blink = 2,
    reverse = 3,
    italic = 4,
};

// Applies or answers one OSC 4 palette request transactionally.
fn handleXtermPaletteControl(
    allocator: std.mem.Allocator,
    colors: *TerminalColorState,
    output: *PendingOutput,
    encode_buf: []u8,
    payload: []const u8,
) ApplyError!void {
    var parts = std.mem.splitScalar(u8, payload, ';');
    while (parts.next()) |idx_text| {
        const value = parts.next() orelse break;
        const idx = std.fmt.parseUnsigned(u16, idx_text, 10) catch continue;
        if (std.mem.eql(u8, value, "?")) {
            const text = formatOscReply(encode_buf, "4;{d};", .{idx});
            const start = byteCount(output.bytes.items);
            errdefer restorePendingOutput(output, start);
            try appendReplyControl(output, allocator, .terminal, .osc);
            try appendOutput(output, allocator, text);
            if (paletteTargetColor(colors.*, idx)) |color| try appendColorOsc(allocator, output, color);
            try appendReplyControl(output, allocator, .terminal, .st);
        } else if (parseColor(value)) |color| {
            setPaletteTarget(colors, idx, color);
        }
    }
}

// Applies or answers one OSC 5 special-palette request transactionally.
fn handleXtermSpecialPaletteControl(
    allocator: std.mem.Allocator,
    colors: *TerminalColorState,
    output: *PendingOutput,
    encode_buf: []u8,
    payload: []const u8,
) ApplyError!void {
    var parts = std.mem.splitScalar(u8, payload, ';');
    while (parts.next()) |idx_text| {
        const value = parts.next() orelse break;
        const idx = std.fmt.parseUnsigned(u3, idx_text, 10) catch continue;
        const text = formatOscReply(encode_buf, "5;{d};", .{idx});
        if (std.mem.eql(u8, value, "?")) {
            const start = byteCount(output.bytes.items);
            errdefer restorePendingOutput(output, start);
            try appendReplyControl(output, allocator, .terminal, .osc);
            try appendOutput(output, allocator, text);
            if (colors.special_palette[idx]) |color| try appendColorOsc(allocator, output, color);
            try appendReplyControl(output, allocator, .terminal, .st);
        } else if (parseColor(value)) |color| {
            colors.special_palette[idx] = color;
        }
    }
}

// Applies or answers one dynamic-color command transactionally.
fn handleXtermDynamicColor(
    allocator: std.mem.Allocator,
    colors: *TerminalColorState,
    output: *PendingOutput,
    encode_buf: []u8,
    command: u16,
    payload: []const u8,
) ApplyError!void {
    var key = dynamicKeyForCommand(command) orelse return;
    var parts = std.mem.splitScalar(u8, payload, ';');
    while (parts.next()) |value| {
        if (std.mem.eql(u8, value, "?")) {
            try appendXtermDynamicColorReply(allocator, output, encode_buf, colors.*, key);
        } else if (parseColor(value)) |color| {
            setDynamicColor(colors, key, color);
        }
        key = nextDynamicKey(key) orelse return;
    }
}

// Resets selected OSC 104 palette entries or the complete palette.
fn resetXtermPalette(colors: *TerminalColorState, payload: []const u8) void {
    if (payload.len == 0) {
        colors.palette = buildDefaultPalette();
        return;
    }
    var parts = std.mem.splitScalar(u8, payload, ';');
    while (parts.next()) |idx_text| {
        const idx = std.fmt.parseUnsigned(u8, idx_text, 10) catch continue;
        resetPaletteTarget(colors, idx);
    }
}

// Resets one dynamic color selected by its OSC command.
fn resetXtermDynamicColor(colors: *TerminalColorState, command: u16, payload: []const u8) void {
    if (payload.len != 0) return;
    const key = dynamicKeyForResetCommand(command) orelse return;
    resetDynamicColor(colors, key);
}

// Converts a cursor color-control request into a semantic event when applicable.
fn cursorColorEvent(command: TerminalColorControlCommand) ?SemanticEvent {
    if (command.command == 12) return cursorColorEventFromDynamicPayload(command.payload, .cursor);
    if (command.command == 112 and command.payload.len == 0) return .{ .cursor_color = null };
    if (command.command == 21) return cursorColorEventFromKittyPayload(command.payload);
    return null;
}

fn parseColor(value: []const u8) ?Rgb {
    const color_text = stripAlpha(std.mem.trim(u8, value, " \t\r\n"));
    if (color_text.len == 0) return null;
    if (std.mem.startsWith(u8, color_text, "#")) return parseHashColor(color_text[1..]);
    if (std.mem.startsWith(u8, color_text, "rgb:")) return parseRgbColor(color_text[4..]);
    if (std.ascii.eqlIgnoreCase(color_text, "black")) return .{ .r = 0, .g = 0, .b = 0 };
    if (std.ascii.eqlIgnoreCase(color_text, "red")) return .{ .r = 255, .g = 0, .b = 0 };
    if (std.ascii.eqlIgnoreCase(color_text, "green")) return .{ .r = 0, .g = 255, .b = 0 };
    if (std.ascii.eqlIgnoreCase(color_text, "blue")) return .{ .r = 0, .g = 0, .b = 255 };
    if (std.ascii.eqlIgnoreCase(color_text, "white")) return .{ .r = 255, .g = 255, .b = 255 };
    return null;
}

// Applies the iTerm SetColors subset represented by terminal presentation state.
//
// Bare and `srgb:` three- or six-digit values are accepted. Display-P3 and
// host-only selection, tab, badge, link, match, preset, and face-policy keys
// are intentionally left to an embedder with those domains. Matching iTerm's
// command loop, each valid pair commits independently while malformed or
// unsupported pairs are ignored without affecting their valid neighbors;
// `default` restores the corresponding native TerminalColorState default.
fn handleItermSetColors(colors: *TerminalColorState, payload: []const u8) void {
    const defaults = TerminalColorState{};
    var parts = std.mem.splitScalar(u8, payload, ',');
    while (parts.next()) |part| {
        const separator = std.mem.indexOfScalar(u8, part, '=') orelse continue;
        if (separator == 0 or separator + 1 == part.len) continue;
        const name = part[0..separator];
        const target = parseItermColorTarget(name) orelse continue;
        var value = part[separator + 1 ..];
        if (std.mem.eql(u8, value, "default")) {
            resetItermColor(colors, defaults, target);
            continue;
        }
        if (std.mem.startsWith(u8, value, "srgb:")) value = value[5..];
        if (std.mem.indexOfScalar(u8, value, ':') != null) continue;
        const rgb = parseItermHex(value) orelse continue;
        setItermColor(colors, target, rgb);
    }
}

const ItermColorTarget = union(enum) {
    foreground,
    background,
    cursor,
    cursor_text,
    palette: u8,
};

fn parseItermColorTarget(name: []const u8) ?ItermColorTarget {
    if (std.mem.eql(u8, name, "fg")) return .foreground;
    if (std.mem.eql(u8, name, "bg")) return .background;
    if (std.mem.eql(u8, name, "curbg")) return .cursor;
    if (std.mem.eql(u8, name, "curfg")) return .cursor_text;
    if (parseItermPaletteIndex(name)) |index| return .{ .palette = index };
    return null;
}

fn setItermColor(colors: *TerminalColorState, target: ItermColorTarget, rgb: Rgb) void {
    switch (target) {
        .foreground => colors.foreground = rgb,
        .background => colors.background = rgb,
        .cursor => colors.cursor = rgb,
        .cursor_text => colors.cursor_text = rgb,
        .palette => |index| colors.palette[index] = rgb,
    }
}

fn resetItermColor(
    colors: *TerminalColorState,
    defaults: TerminalColorState,
    target: ItermColorTarget,
) void {
    switch (target) {
        .foreground => colors.foreground = defaults.foreground,
        .background => colors.background = defaults.background,
        .cursor => colors.cursor = defaults.cursor,
        .cursor_text => colors.cursor_text = defaults.cursor_text,
        .palette => |index| colors.palette[index] = defaults.palette[index],
    }
}

fn parseItermHex(value: []const u8) ?Rgb {
    if (value.len != 3 and value.len != 6) return null;
    var expanded: [6]u8 = undefined;
    const hex = if (value.len == 3) blk: {
        for (value, 0..) |digit, index| {
            expanded[index * 2] = digit;
            expanded[index * 2 + 1] = digit;
        }
        break :blk expanded[0..];
    } else value;
    const rgb_value = std.fmt.parseUnsigned(u24, hex, 16) catch return null;
    return .{
        .r = @intCast(rgb_value >> 16),
        .g = @intCast((rgb_value >> 8) & 0xff),
        .b = @intCast(rgb_value & 0xff),
    };
}

fn parseItermPaletteIndex(name: []const u8) ?u8 {
    const names = [_][]const u8{
        "black",    "red",    "green",    "yellow",    "blue",    "magenta",    "cyan",    "white",
        "br_black", "br_red", "br_green", "br_yellow", "br_blue", "br_magenta", "br_cyan", "br_white",
    };
    for (names, 0..) |candidate, index|
        if (std.mem.eql(u8, name, candidate)) return @intCast(index);
    return null;
}

fn defaultPalette() [256]Rgb {
    return buildDefaultPalette();
}

fn defaultPaletteColor(idx: u8) Rgb {
    return paletteColor(idx);
}

fn specialColorKey(key: []const u8) ?SpecialKey {
    if (std.mem.eql(u8, key, "foreground")) return .foreground;
    if (std.mem.eql(u8, key, "background")) return .background;
    if (std.mem.eql(u8, key, "cursor")) return .cursor;
    if (std.mem.eql(u8, key, "cursor_text")) return .cursor_text;
    if (std.mem.eql(u8, key, "selection_background")) return .selection_background;
    if (std.mem.eql(u8, key, "selection_foreground")) return .selection_foreground;
    return null;
}

// Reports whether a borrowed Kitty color key names supported state.
fn isKnownColorKey(key: []const u8) bool {
    if (specialColorKey(key) != null) return true;
    return (std.fmt.parseUnsigned(u8, key, 10) catch null) != null;
}

// Returns the current color for a recognized Kitty key.
fn colorForKey(colors: TerminalColorState, key: []const u8) ?Rgb {
    if (std.fmt.parseUnsigned(u8, key, 10)) |idx| return colors.palette[idx] else |_| {}
    if (specialColorKey(key)) |special| return switch (special) {
        .foreground => colors.foreground,
        .background => colors.background,
        .cursor => colors.cursor,
        .cursor_text => colors.cursor_text,
        .selection_background => colors.selection_background,
        .selection_foreground => colors.selection_foreground,
    };
    return null;
}

fn paletteTargetColor(colors: TerminalColorState, idx: u16) ?Rgb {
    if (idx < 256) return colors.palette[@intCast(idx)];
    const special_idx = idx - 256;
    if (special_idx >= colors.special_palette.len) return null;
    return colors.special_palette[special_idx];
}

fn setPaletteTarget(colors: *TerminalColorState, idx: u16, color: Rgb) void {
    if (idx < 256) {
        colors.palette[@intCast(idx)] = color;
        return;
    }
    const special_idx = idx - 256;
    if (special_idx >= colors.special_palette.len) return;
    colors.special_palette[special_idx] = color;
}

fn resetPaletteTarget(colors: *TerminalColorState, idx: u8) void {
    colors.palette[idx] = paletteColor(idx);
}

fn dynamicKeyForCommand(command: u16) ?DynamicKey {
    return switch (command) {
        10 => .foreground,
        11 => .background,
        12 => .cursor,
        13 => .pointer_foreground,
        14 => .pointer_background,
        15 => .tektronix_foreground,
        16 => .tektronix_background,
        17 => .selection_background,
        18 => .tektronix_cursor,
        19 => .selection_foreground,
        else => null,
    };
}

fn cursorColorEventFromDynamicPayload(payload: []const u8, key: SpecialKey) ?SemanticEvent {
    var parts = std.mem.splitScalar(u8, payload, ';');
    const value = parts.next() orelse return null;
    if (std.mem.eql(u8, value, "?")) return null;
    return cursorColorEventForValue(key, value);
}

fn cursorColorEventFromKittyPayload(payload: []const u8) ?SemanticEvent {
    const split = std.mem.indexOfScalar(u8, payload, '=') orelse return null;
    const key_text = payload[0..split];
    const value = payload[split + 1 ..];
    const key = specialColorKey(key_text) orelse return null;
    switch (key) {
        .cursor, .cursor_text => return cursorColorEventForValue(key, value),
        .foreground, .background, .selection_background, .selection_foreground => return null,
    }
}

fn cursorColorEventForValue(key: SpecialKey, value: []const u8) ?SemanticEvent {
    if (std.mem.eql(u8, value, "?")) return null;
    if (value.len == 0) return switch (key) {
        .cursor => .{ .cursor_color = null },
        .cursor_text => .{ .cursor_text_color = null },
        else => null,
    };
    const rgb = parseColor(value) orelse return null;
    return switch (key) {
        .cursor => .{ .cursor_color = rgb },
        .cursor_text => .{ .cursor_text_color = rgb },
        else => null,
    };
}

fn dynamicKeyForResetCommand(command: u16) ?DynamicKey {
    return switch (command) {
        110 => .foreground,
        111 => .background,
        112 => .cursor,
        113 => .pointer_foreground,
        114 => .pointer_background,
        115 => .tektronix_foreground,
        116 => .tektronix_background,
        117 => .selection_background,
        118 => .tektronix_cursor,
        119 => .selection_foreground,
        else => null,
    };
}

fn nextDynamicKey(key: DynamicKey) ?DynamicKey {
    return switch (key) {
        .foreground => .background,
        .background => .cursor,
        .cursor => .pointer_foreground,
        .pointer_foreground => .pointer_background,
        .pointer_background => .tektronix_foreground,
        .tektronix_foreground => .tektronix_background,
        .tektronix_background => .selection_background,
        .selection_background => .tektronix_cursor,
        .tektronix_cursor => .selection_foreground,
        .selection_foreground => null,
    };
}

fn dynamicCommandForKey(key: DynamicKey) u16 {
    return switch (key) {
        .foreground => 10,
        .background => 11,
        .cursor => 12,
        .pointer_foreground => 13,
        .pointer_background => 14,
        .tektronix_foreground => 15,
        .tektronix_background => 16,
        .selection_background => 17,
        .tektronix_cursor => 18,
        .selection_foreground => 19,
    };
}

fn dynamicColor(colors: TerminalColorState, key: DynamicKey) ?Rgb {
    return switch (key) {
        .foreground => colors.foreground,
        .background => colors.background,
        .cursor => colors.cursor,
        .pointer_foreground => colors.pointer_foreground,
        .pointer_background => colors.pointer_background,
        .tektronix_foreground => colors.tektronix_foreground,
        .tektronix_background => colors.tektronix_background,
        .selection_background => colors.selection_background,
        .tektronix_cursor => colors.tektronix_cursor,
        .selection_foreground => colors.selection_foreground,
    };
}

fn setDynamicColor(colors: *TerminalColorState, key: DynamicKey, color: Rgb) void {
    switch (key) {
        .foreground => colors.foreground = color,
        .background => colors.background = color,
        .cursor => colors.cursor = color,
        .pointer_foreground => colors.pointer_foreground = color,
        .pointer_background => colors.pointer_background = color,
        .tektronix_foreground => colors.tektronix_foreground = color,
        .tektronix_background => colors.tektronix_background = color,
        .selection_background => colors.selection_background = color,
        .tektronix_cursor => colors.tektronix_cursor = color,
        .selection_foreground => colors.selection_foreground = color,
    }
}

fn resetDynamicColor(colors: *TerminalColorState, key: DynamicKey) void {
    switch (key) {
        .foreground => colors.foreground = default_terminal_foreground,
        .background => colors.background = default_terminal_background,
        .cursor => colors.cursor = null,
        .pointer_foreground => colors.pointer_foreground = null,
        .pointer_background => colors.pointer_background = null,
        .tektronix_foreground => colors.tektronix_foreground = null,
        .tektronix_background => colors.tektronix_background = null,
        .selection_background => colors.selection_background = null,
        .tektronix_cursor => colors.tektronix_cursor = null,
        .selection_foreground => colors.selection_foreground = null,
    }
}

// Appends one bounded rgb:RRRR/GGGG/BBBB OSC color reply.
fn appendColorOsc(allocator: std.mem.Allocator, output: *PendingOutput, color: Rgb) ApplyError!void {
    var buf: [32]u8 = undefined;
    const text = formatColorOsc(buf[0..], color);
    try appendOutput(output, allocator, text);
}

// Parses and applies a recognized Kitty color key, ignoring invalid values.
fn setColorKey(colors: *TerminalColorState, key: []const u8, value: []const u8) void {
    if (std.fmt.parseUnsigned(u8, key, 10)) |idx| {
        if (parseColor(value)) |color| colors.palette[idx] = color;
        return;
    } else |_| {}
    if (value.len == 0) {
        setSpecialColorDynamic(colors, key);
    } else if (parseColor(value)) |color| {
        if (specialColorKey(key)) |special| setSpecialColor(colors, special, color);
    }
}

// Restores a recognized Kitty color key to its default value.
fn resetColorKey(colors: *TerminalColorState, key: []const u8) void {
    if (std.fmt.parseUnsigned(u8, key, 10)) |idx| {
        colors.palette[idx] = paletteColor(idx);
        return;
    } else |_| {}
    if (specialColorKey(key)) |special| switch (special) {
        .foreground => colors.foreground = default_terminal_foreground,
        .background => colors.background = default_terminal_background,
        .cursor => colors.cursor = null,
        .cursor_text => colors.cursor_text = null,
        .selection_background => colors.selection_background = null,
        .selection_foreground => colors.selection_foreground = null,
    };
}

fn appendXtermSpecialColorReply(
    allocator: std.mem.Allocator,
    output: *PendingOutput,
    encode_buf: []u8,
    colors: TerminalColorState,
    key: SpecialKey,
) ApplyError!void {
    const osc: u8 = switch (key) {
        .foreground => 10,
        .background => 11,
        .cursor => 12,
        else => 10,
    };
    const color = switch (key) {
        .foreground => colors.foreground,
        .background => colors.background,
        .cursor => colors.cursor orelse colors.foreground,
        else => colors.foreground,
    };
    const text = formatOscReply(encode_buf, "{d};", .{osc});
    const start = byteCount(output.bytes.items);
    errdefer restorePendingOutput(output, start);
    try appendReplyControl(output, allocator, .terminal, .osc);
    try appendOutput(output, allocator, text);
    try appendColorOsc(allocator, output, color);
    try appendReplyControl(output, allocator, .terminal, .st);
}

fn appendXtermDynamicColorReply(
    allocator: std.mem.Allocator,
    output: *PendingOutput,
    encode_buf: []u8,
    colors: TerminalColorState,
    key: DynamicKey,
) ApplyError!void {
    const text = formatOscReply(encode_buf, "{d};", .{dynamicCommandForKey(key)});
    const start = byteCount(output.bytes.items);
    errdefer restorePendingOutput(output, start);
    try appendReplyControl(output, allocator, .terminal, .osc);
    try appendOutput(output, allocator, text);
    if (dynamicColor(colors, key)) |color| try appendColorOsc(allocator, output, color);
    try appendReplyControl(output, allocator, .terminal, .st);
}

fn setSpecialColor(colors: *TerminalColorState, key: SpecialKey, color: Rgb) void {
    switch (key) {
        .foreground => colors.foreground = color,
        .background => colors.background = color,
        .cursor => colors.cursor = color,
        .cursor_text => colors.cursor_text = color,
        .selection_background => colors.selection_background = color,
        .selection_foreground => colors.selection_foreground = color,
    }
}

fn setSpecialColorDynamic(colors: *TerminalColorState, key: []const u8) void {
    if (specialColorKey(key)) |special| switch (special) {
        .foreground => {},
        .background => {},
        .cursor => colors.cursor = null,
        .cursor_text => colors.cursor_text = null,
        .selection_background => colors.selection_background = null,
        .selection_foreground => colors.selection_foreground = null,
    };
}

fn formatOscReply(encode_buf: []u8, comptime fmt: []const u8, args: anytype) []const u8 {
    std.debug.assert(encode_buf.len >= osc_reply_max_bytes);
    return std.fmt.bufPrint(encode_buf, fmt, args) catch unreachable;
}

fn formatColorOsc(buf: []u8, color: Rgb) []const u8 {
    std.debug.assert(buf.len >= color_osc_max_bytes);
    return std.fmt.bufPrint(buf, "rgb:{x:0>2}/{x:0>2}/{x:0>2}", .{ color.r, color.g, color.b }) catch unreachable;
}

fn buildDefaultPalette() [256]Rgb {
    @setEvalBranchQuota(4096);
    var palette: [256]Rgb = undefined;
    var idx: u16 = 0;
    while (idx < 256) : (idx += 1) palette[idx] = paletteColor(@intCast(idx));
    return palette;
}

fn paletteColor(idx: u8) Rgb {
    if (idx < 16) return paletteAnsi16Color(idx);
    if (idx < 232) {
        const n = idx - 16;
        const r = cubeComponent(n / 36);
        const g = cubeComponent((n / 6) % 6);
        const b = cubeComponent(n % 6);
        return .{ .r = r, .g = g, .b = b };
    }
    const gray: u8 = 8 + (idx - 232) * 10;
    return .{ .r = gray, .g = gray, .b = gray };
}

fn cubeComponent(v: u8) u8 {
    return if (v == 0) 0 else 55 + v * 40;
}

fn paletteAnsi16Color(idx: u8) Rgb {
    return switch (idx) {
        0 => .{ .r = 0, .g = 0, .b = 0 },
        1 => .{ .r = 205, .g = 49, .b = 49 },
        2 => .{ .r = 13, .g = 188, .b = 121 },
        3 => .{ .r = 229, .g = 229, .b = 16 },
        4 => .{ .r = 36, .g = 114, .b = 200 },
        5 => .{ .r = 188, .g = 63, .b = 188 },
        6 => .{ .r = 17, .g = 168, .b = 205 },
        7 => .{ .r = 229, .g = 229, .b = 229 },
        8 => .{ .r = 102, .g = 102, .b = 102 },
        9 => .{ .r = 241, .g = 76, .b = 76 },
        10 => .{ .r = 35, .g = 209, .b = 139 },
        11 => .{ .r = 245, .g = 245, .b = 67 },
        12 => .{ .r = 59, .g = 142, .b = 234 },
        13 => .{ .r = 214, .g = 112, .b = 214 },
        14 => .{ .r = 41, .g = 184, .b = 219 },
        else => .{ .r = 255, .g = 255, .b = 255 },
    };
}

fn stripAlpha(value: []const u8) []const u8 {
    const at = std.mem.indexOfScalar(u8, value, '@') orelse return value;
    return value[0..at];
}

fn parseHashColor(hex: []const u8) ?Rgb {
    return switch (hex.len) {
        3 => blk: {
            const r = parseHexNibble(hex[0]) orelse return null;
            const g = parseHexNibble(hex[1]) orelse return null;
            const b = parseHexNibble(hex[2]) orelse return null;
            break :blk .{ .r = r << 4, .g = g << 4, .b = b << 4 };
        },
        6 => .{
            .r = parseHexByte(hex[0..2]) orelse return null,
            .g = parseHexByte(hex[2..4]) orelse return null,
            .b = parseHexByte(hex[4..6]) orelse return null,
        },
        9 => .{
            .r = parseHexByte(hex[0..2]) orelse return null,
            .g = parseHexByte(hex[3..5]) orelse return null,
            .b = parseHexByte(hex[6..8]) orelse return null,
        },
        12 => .{
            .r = parseHexByte(hex[0..2]) orelse return null,
            .g = parseHexByte(hex[4..6]) orelse return null,
            .b = parseHexByte(hex[8..10]) orelse return null,
        },
        else => null,
    };
}

fn parseRgbColor(text: []const u8) ?Rgb {
    var parts = std.mem.splitScalar(u8, text, '/');
    const r = parseRgbComponent(parts.next() orelse return null) orelse return null;
    const g = parseRgbComponent(parts.next() orelse return null) orelse return null;
    const b = parseRgbComponent(parts.next() orelse return null) orelse return null;
    return .{ .r = r, .g = g, .b = b };
}

fn parseRgbComponent(text: []const u8) ?u8 {
    if (text.len == 0 or text.len > 4) return null;
    const value = std.fmt.parseUnsigned(u16, text, 16) catch return null;
    return switch (text.len) {
        1 => @intCast(value * 17),
        2 => @intCast(value),
        3 => @intCast(value >> 4),
        4 => @intCast(value >> 8),
        else => null,
    };
}

fn parseHexByte(text: []const u8) ?u8 {
    if (text.len != 2) return null;
    return std.fmt.parseUnsigned(u8, text, 16) catch null;
}

fn parseHexNibble(byte: u8) ?u8 {
    return switch (byte) {
        '0'...'9' => byte - '0',
        'a'...'f' => byte - 'a' + 10,
        'A'...'F' => byte - 'A' + 10,
        else => null,
    };
}

test "cursor color control mutates semantic cursor owner through screen apply" {
    var screen = Screen.init(2, 2);

    const cursor_event = cursorColorEvent(.{ .command = 12, .payload = "#010203" }).?;
    screen.applyScreen(.{ .cursor_color = cursor_event.cursor_color });
    try std.testing.expectEqual(@as(?Rgb, .{ .r = 1, .g = 2, .b = 3 }), screen.cursor.cursor_color);

    const cursor_text_event = cursorColorEvent(.{ .command = 21, .payload = "cursor_text=#040506" }).?;
    screen.applyScreen(.{ .cursor_text_color = cursor_text_event.cursor_text_color });
    try std.testing.expectEqual(@as(?Rgb, .{ .r = 4, .g = 5, .b = 6 }), screen.cursor.cursor_text_color);

    const reset_event = cursorColorEvent(.{ .command = 112, .payload = "" }).?;
    screen.applyScreen(.{ .cursor_color = reset_event.cursor_color });
    try std.testing.expectEqual(@as(?Rgb, null), screen.cursor.cursor_color);
}

// Apply one Kitty-directed semantic event and report exact state or output mutation.
fn applyKittyEvent(vt: *Terminal, event: SemanticEvent) ApplyError!bool {
    var scratch: Scratch = .{};
    const allocator = vt.allocator;
    const active_screen = vt.kitty.activeScreen(vt.screen_state.alt_active);
    const active_screen_const = vt.kitty.activeScreenConst(vt.screen_state.alt_active);
    switch (event) {
        .kitty_keyboard_set => |req| {
            return active_screen.keyboard.set(req.flags, req.mode);
        },
        .kitty_keyboard_query => {
            try active_screen_const.keyboard.appendReport(allocator, &vt.host.pending_output, scratch.buf[0..]);
            return true;
        },
        .kitty_keyboard_push => |flags| {
            return active_screen.keyboard.push(flags);
        },
        .kitty_keyboard_pop => |count| {
            return active_screen.keyboard.pop(count);
        },
        else => unreachable,
    }
}

// Applies one bounded color-stack mutation and reports rejected or empty operations as unchanged.
fn applyKittyColorStack(vt: *Terminal, command: KittyColorCommand) bool {
    return switch (command) {
        .push => |index| pushState(&vt.kitty.color_stack, &vt.host.colors, index),
        .pop => |index| popState(&vt.kitty.color_stack, &vt.host.colors, index),
    };
}

// Observable terminal mutations produced while applying one parser event.
const EventEffect = struct {
    changed: bool,
    title_changed: bool,
    icon_changed: bool,
};

/// Classify one parsed event into the canonical parser-to-domain vocabulary.
pub fn process(event: parser_mod.Event) ?SemanticEvent {
    switch (event) {
        .style_change => |sc| {
            const params = sc.params[0..sc.param_count];
            const intermediates = sc.intermediates[0..sc.intermediates_len];
            return csiProcess(sc.final, params, sc.separators, sc.leader, sc.private, intermediates);
        },
        .invoke_charset, .configure_charset => return null,
        .text => |s| return SemanticEvent{ .write_text = s },
        .codepoint => |cp| return SemanticEvent{ .write_codepoint = cp },
        .control => |c| return controlProcess(c),
        .osc => |osc_event| return processOscEvent(osc_event),
        .esc_dispatch => |esc_dispatch| return escDispatchProcess(
            esc_dispatch.final,
            esc_dispatch.intermediates[0..esc_dispatch.intermediates_len],
        ),
        .apc => return null,
        .dcs => |dcs_data| return dcsProcess(dcs_data),
        .pm, .invalid_sequence => return null,
    }
}

fn escDispatchProcess(final: u8, intermediates: []const u8) ?SemanticEvent {
    if (std.mem.eql(u8, intermediates, " ")) return switch (final) {
        'F' => .{ .eight_bit_controls = false },
        'G' => .{ .eight_bit_controls = true },
        else => null,
    };
    if (intermediates.len != 0) return null;
    return escProcess(final);
}

fn processOscEvent(osc_event: parser_mod.OscAction) ?SemanticEvent {
    return oscProcess(osc_event);
}

/// Apply one parser event and report whether terminal or title state changed.
pub fn apply(vt: *Terminal, event: parser_mod.Event) ApplyError!EventEffect {
    switch (event) {
        .invoke_charset => |slot| {
            vt.gl_index = slot;
            return .{ .changed = true, .title_changed = false, .icon_changed = false };
        },
        .configure_charset => |cfg| {
            const changed = configureCharset(vt, cfg.slot, cfg.designation);
            return .{ .changed = changed, .title_changed = false, .icon_changed = false };
        },
        else => {},
    }

    const semantic = process(event) orelse return .{
        .changed = false,
        .title_changed = false,
        .icon_changed = false,
    };
    if (semantic == .title_stack) {
        const effect = try applyTitleStack(&vt.host, semantic.title_stack);
        return .{
            .changed = effect.changed,
            .title_changed = effect.title_changed,
            .icon_changed = false,
        };
    }
    const title_changed = switch (semantic) {
        .title_and_icon_set => |value| !optionalBytesEqual(vt.host.current_title, value),
        .title_set => |value| !optionalBytesEqual(vt.host.current_title, value),
        else => false,
    };
    const icon_changed = switch (semantic) {
        .title_and_icon_set => |value| !optionalBytesEqual(vt.host.current_icon, value),
        .icon_set => |value| !optionalBytesEqual(vt.host.current_icon, value),
        else => false,
    };
    const changed = try applySemantic(vt, semantic);
    return .{
        .changed = changed,
        .title_changed = title_changed,
        .icon_changed = icon_changed,
    };
}

fn applySemantic(vt: *Terminal, event: SemanticEvent) ApplyError!bool {
    switch (event) {
        .hard_reset => vt.hardReset(),
        .soft_reset => return vt.softReset(),
        .save_cursor => return vt.saveCursor(),
        .restore_cursor => return vt.restoreCursor(),
        .enter_alt_screen => |opts| {
            return vt.switchScreenMode(true, opts.clear, opts.save_cursor);
        },
        .exit_alt_screen => |opts| {
            return vt.switchScreenMode(false, false, opts.restore_cursor);
        },
        .size_report => |kind| {
            var scratch: Scratch = .{};
            return try appendSizeReport(vt, scratch.buf[0..], kind);
        },
        .title_stack => unreachable,
        .ansi_mode_query,
        .modify_other_keys_query,
        .key_format_query,
        .dec_mode_query,
        .dcs_request_status,
        .dcs_request_termcap,
        .dcs_request_resource,
        .device_status_report,
        .dec_device_status_report,
        .cursor_position_report,
        .dec_cursor_position_report,
        .primary_device_attributes,
        .secondary_device_attributes,
        .tertiary_device_attributes,
        .xtversion,
        .xttitlepos,
        .xtchecksum,
        .rect_checksum_request,
        .selected_graphic_rendition_report,
        .screen_extent_report,
        .parameters_report,
        .window_title_report,
        .xtreportcolors,
        .iterm_report_cell_size,
        => try applyReportEvent(vt, event),

        .kitty_keyboard_set,
        .kitty_keyboard_query,
        .kitty_keyboard_push,
        .kitty_keyboard_pop,
        => return try applyKittyEvent(vt, event),

        .kitty_color_stack => |command| return applyKittyColorStack(vt, command),
        .sgr_stack_push => |params| return vt.pushSgr(params),
        .sgr_stack_pop => return vt.popSgr(),
        .restore_cursor_information => |payload| return vt.restoreCursorInformation(payload),
        .restore_tab_stops => |payload| return vt.restoreTabStops(payload),

        .focus_reporting => |enabled| return vt.setDecMode(1004, enabled),
        .mouse_tracking_off => return vt.setMouseTracking(.off),
        .mouse_tracking_x10 => return vt.setDecMode(9, true),
        .mouse_tracking_normal => return vt.setDecMode(1000, true),
        .mouse_tracking_button_event => return vt.setDecMode(1002, true),
        .mouse_tracking_any_event => return vt.setDecMode(1003, true),
        .mouse_protocol_utf8 => |enabled| return vt.setDecMode(1005, enabled),
        .mouse_protocol_sgr => |enabled| return vt.setDecMode(1006, enabled),
        .mouse_protocol_urxvt => |enabled| return vt.setDecMode(1015, enabled),
        .mouse_protocol_sgr_pixel => |enabled| return vt.setDecMode(1016, enabled),

        .application_cursor_keys,
        .application_keypad,
        .auto_repeat,
        .reverse_screen_mode,
        .eight_bit_controls,
        .left_right_margin_mode,
        .cursor_visible,
        .cursor_blink,
        .ansi_mode_set,
        .ansi_mode_reset,
        .modify_other_keys_set,
        .modify_other_keys_disable,
        .key_format_change,
        .pointer_mode,
        .reverse_wraparound_mode,
        .extended_reverse_wraparound_mode,
        .bracketed_paste,
        .synchronized_output,
        .inband_resize_notifications,
        .dec_mode_save,
        .dec_mode_restore,
        => return vt.applyModeEvent(event),

        .sgr => {
            const screen = vt.screen_state.active();
            const before = screen.current_attrs;
            screen.applyScreen(event);
            return !std.meta.eql(before, screen.current_attrs);
        },

        .cursor_style,
        .cursor_shape,
        => {
            const cursor = &vt.screen_state.active().cursor;
            const before = cursor.*;
            vt.screen_state.active().applyScreen(event);
            return !std.meta.eql(before, cursor.*);
        },

        .color_control => |control| {
            const primary_before = vt.screen_state.primary.cursor;
            const alternate_before = vt.screen_state.alternate.cursor;
            errdefer {
                vt.screen_state.primary.cursor = primary_before;
                vt.screen_state.alternate.cursor = alternate_before;
            }
            if (cursorColorEvent(control)) |cursor_event| {
                vt.screen_state.primary.applyScreen(cursor_event);
                vt.screen_state.alternate.applyScreen(cursor_event);
            }
            const host_changed = try applyHostEvent(vt, event);
            return host_changed or
                !std.meta.eql(primary_before, vt.screen_state.primary.cursor) or
                !std.meta.eql(alternate_before, vt.screen_state.alternate.cursor);
        },
        .iterm_set_colors => |payload| {
            const before = vt.host.colors;
            handleItermSetColors(&vt.host.colors, payload);
            return !std.meta.eql(before, vt.host.colors);
        },
        .bell,
        .title_and_icon_set,
        .title_set,
        .icon_set,
        .shell_integration_set,
        .working_directory_report,
        .shell_mark,
        .hyperlink_set,
        .hyperlink_clear,
        .clipboard_set,
        .locator_reporting,
        .locator_filter,
        .locator_events,
        .locator_request,
        .media_copy_request,
        .dcs_payload,
        .legacy_control,
        => return applyHostEvent(vt, event),

        .line_feed, .next_line => {
            if (!vt.screen_state.alt_active) {
                try vt.screen_state.primary.finalizeOutputLine(vt.allocator);
            }
            vt.screen_state.active().applyScreen(
                if (event == .line_feed and vt.modes.newline_mode) .next_line else event,
            );
        },
        .backspace => return vt.screen_state.active().backspace(vt.modes.reverse_wraparound_mode),

        .erase_display_below => |protected| {
            return vt.screen_state.active().eraseDisplay(.cursor_to_end, protected);
        },
        .erase_display_above => |protected| {
            return vt.screen_state.active().eraseDisplay(.start_to_cursor, protected);
        },
        .erase_display_complete, .erase_display_scroll_complete => |protected| {
            return vt.screen_state.active().eraseDisplay(.all, protected);
        },
        .erase_display_scrollback => |protected| {
            return vt.screen_state.active().eraseDisplay(.scrollback, protected);
        },
        .erase_line => |mode| {
            return vt.screen_state.active().eraseLine(mode, false);
        },
        .selective_erase_line => |mode| {
            return vt.screen_state.active().eraseLine(mode, true);
        },
        .erase_chars => |count| {
            return vt.screen_state.active().eraseChars(count);
        },
        .rect_erase => |area| {
            return vt.screen_state.active().eraseRect(area, false);
        },
        .rect_selective_erase => |area| {
            return vt.screen_state.active().eraseRect(area, true);
        },
        .character_protection => |protection| {
            const active = vt.screen_state.active();
            if (active.current_attrs.protected == protection) return false;
            active.current_attrs.protected = protection;
            return true;
        },
        .repeat_preceding => |count| {
            return vt.screen_state.active().repeatPreceding(count);
        },
        .insert_columns => |count| {
            return vt.screen_state.active().insertColumns(count);
        },
        .delete_columns => |count| {
            return vt.screen_state.active().deleteColumns(count);
        },
        .forward_index => return vt.screen_state.active().forwardIndex(),
        .back_index => return vt.screen_state.active().backIndex(),
        .shift_left_columns => |count| return vt.screen_state.active().shiftColumnsLeft(count),
        .shift_right_columns => |count| return vt.screen_state.active().shiftColumnsRight(count),
        .cursor_up,
        .cursor_down,
        .cursor_forward,
        .cursor_back,
        .cursor_next_line,
        .cursor_prev_line,
        .cursor_horizontal_absolute,
        .cursor_vertical_absolute,
        .cursor_position,
        => return vt.screen_state.active().moveCursor(event),
        .auto_wrap => |enabled| return vt.setDecMode(7, enabled),
        .origin_mode => |enabled| return vt.setDecMode(6, enabled),

        .write_text,
        .write_codepoint,
        .reverse_index,
        .carriage_return,
        .horizontal_tab,
        .horizontal_tab_forward,
        .horizontal_tab_back,
        .horizontal_tab_set,
        .tab_clear_current,
        .tab_clear_all,
        .cursor_color,
        .cursor_text_color,
        .insert_mode,
        .insert_lines,
        .delete_lines,
        .insert_chars,
        .delete_chars,
        .scroll_up_lines,
        .scroll_down_lines,
        .set_scroll_region,
        .rect_fill,
        .rect_copy,
        .rect_attrs_change,
        .attr_change_extent_rect,
        .set_left_right_margins,
        .reset_default_tab_stops,
        => vt.screen_state.active().applyScreen(event),
    }
    return true;
}

// Reports parser allocation, parser bound, captured DCS bound, or retained-consequence failure.
const FeedError = error{
    ConsequenceLimit,
    OutOfMemory,
    ParsedEventLimit,
    StringControlLimit,
};

// Reports terminal mutation and distinct title or icon metadata changes.
const FeedSummary = struct {
    state_changed: bool,
    title_changed: bool,
    icon_changed: bool,
    history_lost: bool,
};

const DcsCapture = struct {
    const StartError = error{OutOfMemory};
    const PutError = error{ OutOfMemory, StringControlLimit };

    allocator: std.mem.Allocator,
    bytes: std.ArrayList(u8),
    params: [parser_mod.max_params]i32 = [_]i32{0} ** parser_mod.max_params,
    intermediates: [parser_mod.max_intermediates]u8 = [_]u8{0} ** parser_mod.max_intermediates,
    payload_start: usize = 0,
    final: u8 = 0,
    param_count: u8 = 0,
    intermediates_len: u8 = 0,
    active: bool = false,

    fn init(allocator: std.mem.Allocator) DcsCapture {
        return .{ .allocator = allocator, .bytes = .empty };
    }

    fn deinit(self: *DcsCapture) void {
        self.bytes.deinit(self.allocator);
    }

    fn reset(self: *DcsCapture) void {
        self.active = false;
        self.payload_start = 0;
        self.final = 0;
        self.param_count = 0;
        self.intermediates_len = 0;
        self.bytes.clearRetainingCapacity();
    }

    fn start(self: *DcsCapture, hook: parser_mod.DcsHook) StartError!void {
        std.debug.assert(hook.count <= parser_mod.max_params);
        std.debug.assert(hook.intermediates_len <= parser_mod.max_intermediates);
        self.reset();
        self.active = true;
        self.final = hook.final;
        self.param_count = hook.count;
        self.intermediates_len = hook.intermediates_len;
        std.mem.copyForwards(i32, self.params[0..hook.count], hook.params[0..hook.count]);
        std.mem.copyForwards(
            u8,
            self.intermediates[0..hook.intermediates_len],
            hook.intermediates[0..hook.intermediates_len],
        );

        errdefer self.reset();
        var idx: u8 = 0;
        while (idx < hook.count) : (idx += 1) {
            if (idx > 0) try self.bytes.append(self.allocator, ';');
            var text_buf: [32]u8 = undefined;
            const text = std.fmt.bufPrint(&text_buf, "{d}", .{hook.params[idx]}) catch unreachable;
            try self.bytes.appendSlice(self.allocator, text);
        }
        try self.bytes.appendSlice(self.allocator, self.intermediates[0..hook.intermediates_len]);
        try self.bytes.append(self.allocator, hook.final);
        self.payload_start = self.bytes.items.len;
    }

    fn put(self: *DcsCapture, byte: u8) PutError!void {
        std.debug.assert(self.active);
        if (self.bytes.items.len - self.payload_start >= @as(usize, parser_mod.max_metadata_control_bytes)) {
            return error.StringControlLimit;
        }
        try self.bytes.append(self.allocator, byte);
    }

    fn event(self: *const DcsCapture) parser_mod.Event {
        std.debug.assert(self.active);
        return .{ .dcs = .{
            .body = self.bytes.items,
            .payload = self.bytes.items[self.payload_start..],
            .final = self.final,
            .params = self.params[0..self.param_count],
            .param_count = self.param_count,
            .intermediates = self.intermediates[0..self.intermediates_len],
            .intermediates_len = self.intermediates_len,
        } };
    }
};

// Owns parser allocation and bounded DCS capture for one terminal lifetime.
const TerminalStreamState = struct {
    /// TerminalStream-state initialization can fail only while allocating parser storage.
    pub const InitError = error{OutOfMemory};

    parser: parser_mod.Parser,
    dcs: DcsCapture,

    /// Initializes parser storage and an empty DCS capture with one borrowed allocator.
    pub fn initAlloc(allocator: std.mem.Allocator) InitError!TerminalStreamState {
        return .{
            .parser = try parser_mod.Parser.init(allocator),
            .dcs = DcsCapture.init(allocator),
        };
    }

    /// Releases parser and DCS capture allocations.
    pub fn deinit(self: *TerminalStreamState) void {
        self.dcs.deinit();
        self.parser.deinit();
    }
};

// Borrows one terminal while translating input bytes into terminal mutation.
const TerminalStream = struct {
    terminal: *Terminal,

    /// Creates a stream borrowing the terminal until the stream is discarded.
    pub fn init(terminal: *Terminal) TerminalStream {
        return .{ .terminal = terminal };
    }

    /// Feeds one byte and omits the optional mutation summary while preserving failures.
    pub fn next(self: *TerminalStream, byte: u8) FeedError!void {
        const summary = try self.nextSummary(byte);
        std.debug.assert(!summary.title_changed or summary.state_changed);
        std.debug.assert(!summary.icon_changed or summary.state_changed);
    }

    /// Feeds a borrowed byte slice and omits the optional mutation summary.
    pub fn nextSlice(self: *TerminalStream, bytes: []const u8) FeedError!void {
        const summary = try self.nextSliceSummary(bytes);
        std.debug.assert(!summary.title_changed or summary.state_changed);
        std.debug.assert(!summary.icon_changed or summary.state_changed);
    }

    fn nextSummary(self: *TerminalStream, byte: u8) FeedError!FeedSummary {
        var state_changed = false;
        var title_changed = false;
        var icon_changed = false;
        const state = &self.terminal.stream_state;

        errdefer {
            state.parser.reset();
            state.dcs.reset();
        }

        const phases = state.parser.next(byte);
        if (state.parser.takeStringControlFailed()) |err| return err;

        for (phases) |phase| {
            if (phase) |action| {
                const effect = try self.applyAction(action);
                state_changed = state_changed or effect.changed;
                title_changed = title_changed or effect.title_changed;
                icon_changed = icon_changed or effect.icon_changed;
            }
        }

        return .{
            .state_changed = state_changed,
            .title_changed = title_changed,
            .icon_changed = icon_changed,
            .history_lost = false,
        };
    }

    /// Feeds a complete borrowed slice and merges per-byte mutation summaries.
    pub fn nextSliceSummary(self: *TerminalStream, bytes: []const u8) FeedError!FeedSummary {
        var summary: FeedSummary = .{
            .state_changed = false,
            .title_changed = false,
            .icon_changed = false,
            .history_lost = false,
        };
        const history_loss_before = self.terminal.screen_state.primary.history_loss_generation;
        for (bytes) |byte| {
            const byte_summary = try self.nextSummary(byte);
            summary.state_changed = summary.state_changed or byte_summary.state_changed;
            summary.title_changed = summary.title_changed or byte_summary.title_changed;
            summary.icon_changed = summary.icon_changed or byte_summary.icon_changed;
        }
        summary.history_lost =
            self.terminal.screen_state.primary.history_loss_generation != history_loss_before;
        return summary;
    }

    fn applyAction(self: *TerminalStream, action: parser_mod.Action) FeedError!EventEffect {
        return switch (action) {
            .print => |cp| self.applyPrint(cp),
            .execute => |ctrl| self.applyExecute(ctrl),
            .invalid => try self.applyEvent(.invalid_sequence),
            .csi_dispatch => |csi| try self.applyEvent(.{ .style_change = .{
                .final = csi.final,
                .params = csi.params[0..csi.count],
                .separators = csi.separators,
                .param_count = csi.count,
                .leader = csi.leader,
                .private = csi.private,
                .intermediates = csi.intermediates[0..csi.intermediates_len],
                .intermediates_len = csi.intermediates_len,
            } }),
            .osc_dispatch => |osc| try self.applyEvent(.{ .osc = osc }),
            .apc_start, .apc_put, .apc_end, .apc_cancel => discardedStringControl(),
            .dcs_hook => |hook| self.startDcs(hook),
            .dcs_put => |byte| self.putDcs(byte),
            .dcs_unhook => self.endDcs(),
            .dcs_cancel => self.cancelDcs(),
            .pm_start, .pm_put, .pm_end, .pm_cancel => discardedStringControl(),
            .sos_start, .sos_put, .sos_end, .sos_cancel => discardedStringControl(),
            .esc_dispatch => |esc| self.applyEsc(esc),
        };
    }

    fn applyPrint(self: *TerminalStream, cp: u21) FeedError!EventEffect {
        const mapped = self.mapCodepoint(cp);
        if (mapped <= 0x7f) {
            const ascii: [1]u8 = .{@intCast(mapped)};
            return try self.applyEvent(.{ .text = ascii[0..] });
        }
        return try self.applyEvent(.{ .codepoint = mapped });
    }

    fn applyExecute(self: *TerminalStream, ctrl: u8) FeedError!EventEffect {
        switch (ctrl) {
            0x0E, 0x0F, 0x8E, 0x8F => {
                const slot: u8 = switch (ctrl) {
                    0x0E => 1,
                    0x0F => 0,
                    0x8E => 2,
                    0x8F => 3,
                    else => unreachable,
                };
                const changed = if (ctrl == 0x8E or ctrl == 0x8F)
                    selectSingleShift(self.terminal, slot)
                else
                    selectGl(self.terminal, slot);
                return .{
                    .changed = changed,
                    .title_changed = false,
                    .icon_changed = false,
                };
            },
            else => return try self.applyEvent(.{ .control = ctrl }),
        }
    }

    fn applyEsc(self: *TerminalStream, esc: parser_mod.EscAction) FeedError!EventEffect {
        if (esc.intermediates_len == 1) {
            switch (esc.intermediates[0]) {
                '(', ')', '*', '+' => {
                    const slot: u8 = switch (esc.intermediates[0]) {
                        '(' => 0,
                        ')' => 1,
                        '*' => 2,
                        '+' => 3,
                        else => unreachable,
                    };
                    const changed = configureCharset(self.terminal, slot, esc.final);
                    return .{
                        .changed = changed,
                        .title_changed = false,
                        .icon_changed = false,
                    };
                },
                '#' => {
                    const active = self.terminal.screen_state.active();
                    const changed = switch (esc.final) {
                        '3' => active.applyLineGeometry(.double_height_top),
                        '4' => active.applyLineGeometry(.double_height_bottom),
                        '5' => active.applyLineGeometry(.single_width),
                        '6' => active.applyLineGeometry(.double_width),
                        '8' => active.alignmentDisplay(),
                        else => return try self.applyEvent(.{ .esc_dispatch = esc }),
                    };
                    return .{ .changed = changed, .title_changed = false, .icon_changed = false };
                },
                '%' => {
                    const latin1 = switch (esc.final) {
                        '@' => true,
                        'G' => false,
                        else => return try self.applyEvent(.{ .esc_dispatch = esc }),
                    };
                    return .{
                        .changed = self.terminal.stream_state.parser.selectLatin1(latin1),
                        .title_changed = false,
                        .icon_changed = false,
                    };
                },
                else => {},
            }
        }
        if (esc.intermediates_len == 0) {
            const changed = switch (esc.final) {
                'n' => selectGl(self.terminal, 2),
                'o' => selectGl(self.terminal, 3),
                '~' => selectGr(self.terminal, 1),
                '}' => selectGr(self.terminal, 2),
                '|' => selectGr(self.terminal, 3),
                'N' => selectSingleShift(self.terminal, 2),
                'O' => selectSingleShift(self.terminal, 3),
                else => return try self.applyEvent(.{ .esc_dispatch = esc }),
            };
            return .{ .changed = changed, .title_changed = false, .icon_changed = false };
        }
        return try self.applyEvent(.{ .esc_dispatch = esc });
    }

    fn applyEvent(self: *TerminalStream, event: parser_mod.Event) FeedError!EventEffect {
        return try apply(self.terminal, event);
    }

    fn startDcs(self: *TerminalStream, hook: parser_mod.DcsHook) FeedError!EventEffect {
        try self.terminal.stream_state.dcs.start(hook);
        return .{
            .changed = false,
            .title_changed = false,
            .icon_changed = false,
        };
    }

    fn putDcs(self: *TerminalStream, byte: u8) FeedError!EventEffect {
        try self.terminal.stream_state.dcs.put(byte);
        return .{
            .changed = false,
            .title_changed = false,
            .icon_changed = false,
        };
    }

    fn endDcs(self: *TerminalStream) FeedError!EventEffect {
        const state = &self.terminal.stream_state;
        const event = state.dcs.event();
        defer state.dcs.reset();
        return try apply(self.terminal, event);
    }

    fn cancelDcs(self: *TerminalStream) EventEffect {
        self.terminal.stream_state.dcs.reset();
        return discardedStringControl();
    }

    fn mapCodepoint(self: *TerminalStream, cp: u21) u21 {
        if (cp >= 0x20 and cp <= 0x7e) {
            const slot = self.terminal.single_shift orelse self.terminal.gl_index;
            self.terminal.single_shift = null;
            return mapCharset(self.terminal, slot, @intCast(cp), false);
        }
        if (cp >= 0xA0 and cp <= 0xFE)
            return mapCharset(self.terminal, self.terminal.gr_index, @intCast(cp - 0x80), true);
        return cp;
    }
};

fn discardedStringControl() EventEffect {
    return .{
        .changed = false,
        .title_changed = false,
        .icon_changed = false,
    };
}

fn configureCharset(terminal: *Terminal, slot: u8, designation: u8) bool {
    // Unsupported repertoires leave the selected slot unchanged.
    if (designation != '0' and designation != 'A' and designation != 'B') return false;
    if (slot >= terminal.designations.len) return false;
    const target = &terminal.designations[slot];
    if (target.* == designation) return false;
    target.* = designation;
    return true;
}

fn selectGl(terminal: *Terminal, slot: u8) bool {
    std.debug.assert(slot < terminal.designations.len);
    if (terminal.gl_index == slot and terminal.single_shift == null) return false;
    terminal.gl_index = slot;
    terminal.single_shift = null;
    return true;
}

fn selectGr(terminal: *Terminal, slot: u8) bool {
    std.debug.assert(slot > 0 and slot < terminal.designations.len);
    if (terminal.gr_index == slot) return false;
    terminal.gr_index = slot;
    return true;
}

fn selectSingleShift(terminal: *Terminal, slot: u8) bool {
    std.debug.assert(slot == 2 or slot == 3);
    if (terminal.single_shift == slot) return false;
    terminal.single_shift = slot;
    return true;
}

fn mapCharset(terminal: *const Terminal, slot: u8, byte: u8, gr: bool) u21 {
    std.debug.assert(slot < terminal.designations.len);
    const designation = terminal.designations[slot];
    return switch (designation) {
        '0' => mapDecSpecial(byte),
        'A' => if (byte == '#') 0x00A3 else charsetIdentity(byte, gr),
        else => charsetIdentity(byte, gr),
    };
}

fn charsetIdentity(byte: u8, gr: bool) u21 {
    return if (gr) @as(u21, byte) + 0x80 else byte;
}

fn mapDecSpecial(byte: u8) u21 {
    return switch (byte) {
        '+' => 0x2192,
        ',' => 0x2190,
        '-' => 0x2191,
        '.' => 0x2193,
        '0' => 0x2588,
        '_' => 0x00A0,
        '`' => 0x25C6,
        'a' => 0x2592,
        'b' => 0x2409,
        'c' => 0x240C,
        'd' => 0x240D,
        'e' => 0x240A,
        'f' => 0x00B0,
        'g' => 0x00B1,
        'h' => 0x2591,
        'i' => 0x240B,
        'j' => 0x2518,
        'k' => 0x2510,
        'l' => 0x250C,
        'm' => 0x2514,
        'n' => 0x253C,
        'o' => 0x23BA,
        'p' => 0x23BB,
        'q' => 0x2500,
        'r' => 0x23BC,
        's' => 0x23BD,
        't' => 0x251C,
        'u' => 0x2524,
        'v' => 0x2534,
        'w' => 0x252C,
        'x' => 0x2502,
        'y' => 0x2264,
        'z' => 0x2265,
        '{' => 0x03C0,
        '|' => 0x2260,
        '}' => 0x00A3,
        '~' => 0x00B7,
        else => byte,
    };
}

test "stream state initialization reports parser allocation failure" {
    const init: *const fn (
        std.mem.Allocator,
    ) TerminalStreamState.InitError!TerminalStreamState = TerminalStreamState.initAlloc;
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, init(failing.allocator()));
    try std.testing.expect(failing.has_induced_failure);
}

test "DCS capture start and put report exact failures and remain reusable" {
    const start: *const fn (*DcsCapture, parser_mod.DcsHook) DcsCapture.StartError!void = DcsCapture.start;
    const put: *const fn (*DcsCapture, u8) DcsCapture.PutError!void = DcsCapture.put;
    const hook: parser_mod.DcsHook = .{
        .final = 'q',
        .params = &.{1},
        .count = 1,
        .intermediates = "$",
        .intermediates_len = 1,
    };

    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var capture = DcsCapture.init(failing.allocator());
    defer capture.deinit();

    try std.testing.expectError(error.OutOfMemory, start(&capture, hook));
    try std.testing.expect(!capture.active);
    try std.testing.expectEqual(@as(usize, 0), capture.bytes.items.len);

    failing.fail_index = std.math.maxInt(usize);
    try start(&capture, hook);
    const payload_start = capture.payload_start;
    failing.fail_index = failing.alloc_index;

    var put_count: u32 = 0;
    while (!failing.has_induced_failure) : (put_count += 1) {
        try std.testing.expect(put_count < parser_mod.max_metadata_control_bytes);
        put(&capture, 'x') catch |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            break;
        };
    }
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expect(capture.active);
    try std.testing.expectEqual(payload_start + put_count, capture.bytes.items.len);

    failing.fail_index = std.math.maxInt(usize);
    try put(&capture, 'y');
    while (capture.bytes.items.len - capture.payload_start < parser_mod.max_metadata_control_bytes) {
        try put(&capture, 'z');
    }
    try std.testing.expectError(error.StringControlLimit, put(&capture, 'z'));
    capture.reset();
    try std.testing.expect(!capture.active);
    try start(&capture, hook);
}

test "discarded string controls stream without retaining payload bytes" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 2);
    defer terminal.deinit();
    var stream = TerminalStream.init(&terminal);

    try stream.nextSlice("\x1b_G");
    try stream.nextSlice("x" ** 8192);
    try stream.nextSlice("\x1b\\");
    try stream.nextSlice("\x1b^");
    try stream.nextSlice("y" ** 8192);
    try stream.nextSlice("\x1b\\");
    try stream.nextSlice("\x1bX");
    try stream.nextSlice("z" ** 8192);
    try stream.nextSlice("\x1b\\");
    try stream.nextSlice("ok");

    const view = terminal.surfaceSnapshot().snapshot.view;
    try std.testing.expectEqual(@as(u21, 'o'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'k'), view.cellAt(0, 1));
}

const RestoredCursorInformation = struct {
    row: u16,
    col: u16,
    reverse: bool,
    blink: bool,
    underline: bool,
    bold: bool,
    wrap_pending: bool,
    origin_mode: bool,
    g0_designation: u8,
};

// Parses the VT300 DECCIR fields that iTerm2 applies while validating the
// complete four-slot designation suffix before any terminal mutation.
fn parseCursorInformation(payload: []const u8) ?RestoredCursorInformation {
    var fields: [10][]const u8 = undefined;
    var parts = std.mem.splitScalar(u8, payload, ';');
    for (&fields) |*field| field.* = parts.next() orelse return null;
    if (parts.next() != null) return null;

    const row = parsePresentationCoordinate(fields[0]) orelse return null;
    const col = parsePresentationCoordinate(fields[1]) orelse return null;
    if (parseDecimalPresentationField(fields[2]) == null) return null;
    if (fields[3].len != 1 or fields[4].len != 1 or fields[5].len != 1 or fields[8].len != 1)
        return null;

    const rendition = fields[3][0];
    if (rendition & 0xf0 != 0x40) return null;
    if (parseDecimalPresentationField(fields[6]) == null or
        parseDecimalPresentationField(fields[7]) == null) return null;

    var designation_offset: usize = 0;
    var g0_designation: u8 = 0;
    for (0..4) |slot| {
        const designation = consumePresentationDesignation(fields[9], &designation_offset) orelse return null;
        if (slot == 0) g0_designation = designation;
    }
    if (designation_offset != fields[9].len or g0_designation == '%') return null;

    return .{
        .row = row,
        .col = col,
        .reverse = rendition & 8 != 0,
        .blink = rendition & 4 != 0,
        .underline = rendition & 2 != 0,
        .bold = rendition & 1 != 0,
        .wrap_pending = fields[5][0] & 8 != 0,
        .origin_mode = fields[5][0] & 1 != 0,
        .g0_designation = g0_designation,
    };
}

fn parsePresentationCoordinate(field: []const u8) ?u16 {
    const value = parseDecimalPresentationField(field) orelse return null;
    return @intCast(@min(value -| 1, std.math.maxInt(u16)));
}

fn parseDecimalPresentationField(field: []const u8) ?u32 {
    return std.fmt.parseInt(u32, field, 10) catch null;
}

fn consumePresentationDesignation(payload: []const u8, offset: *usize) ?u8 {
    if (offset.* >= payload.len) return null;
    const byte = payload[offset.*];
    if (byte == '%' and offset.* + 1 < payload.len and payload[offset.* + 1] == '5') {
        offset.* += 2;
        return '%';
    }
    if (byte != 'B' and byte != '0') return null;
    offset.* += 1;
    return byte;
}

/// Host-neutral terminal state and protocol engine.
pub const Terminal = struct {
    /// Exposes the terminal-borrowing byte stream type used by native hosts.
    pub const Stream = TerminalStream;
    /// Reports invalid zero dimensions or allocation failure during construction.
    pub const InitError = error{ InvalidDimensions, OutOfMemory };
    /// Reports invalid dimensions, bounded reply saturation, or allocation failure before resize mutation.
    pub const ResizeError = error{ InvalidDimensions, ConsequenceLimit } || std.mem.Allocator.Error;
    /// Reports a zero cell-pixel dimension before any screen mutation.
    pub const CellPixelSizeError = error{InvalidDimensions};
    /// Copies one nonzero host-provided terminal cell size in logical pixels.
    pub const CellPixelSize = struct {
        width: u32,
        height: u32,
    };
    /// Borrows validated shell-integration identity from one surface publication.
    pub const ShellIntegration = ItermShellIntegration;
    /// Borrows the latest child-reported directory bytes and their URI-or-path interpretation.
    pub const WorkingDirectory = WorkingDirectoryReport;
    /// Bounds the optional copied shell name in shell-integration metadata.
    pub const shell_name_max_bytes = max_shell_name_bytes;
    /// Bounds copied OSC 133 metadata retained by one shell mark.
    pub const shell_mark_metadata_max_bytes = max_metadata_bytes;
    /// Exposes the typed host-input vocabulary accepted by encodeInput.
    pub const InputEvent = Event;
    /// Exposes named physical keys whose terminal identity is not Unicode text.
    pub const NamedKey = KeyName;
    /// Validates Unicode physical-key identities before input encoding.
    pub const Key = InputKey;
    /// Provides caller-owned fixed scratch storage for allocation-free input encoding.
    pub const InputScratch = Scratch;
    /// Returns encoded input with explicit borrowed-or-owned byte lifetime.
    pub const EncodedInput = Encoded;
    /// Reports paste construction or bounded locator-report retention failure.
    pub const InputError = PasteError || ApplyError ||
        error{ InvalidUtf8, InvalidText, KeyTextLimit };
    /// Reports allocation or 64 KiB pending-output saturation without consuming a clipboard query.
    pub const ClipboardReplyError = error{ OutOfMemory, ConsequenceLimit };
    /// Bounds host clipboard bytes accepted by one query reply in every framing mode.
    pub const clipboard_reply_max_bytes = clipboard_reply_bytes_max;
    /// Exposes one borrowed OSC 52 operation and its exact host-policy selection bytes.
    pub const ClipboardRequest = ClipboardRequestView;
    /// Uses the canonical copied terminal RGB value.
    pub const Rgb = Screen.Rgb;
    /// Uses the canonical default, indexed, or RGB cell color.
    pub const Color = Screen.Color;
    /// Uses the canonical complete cell attribute value.
    pub const CellAttrs = Screen.CellAttrs;
    /// Uses the canonical terminal underline style.
    pub const UnderlineStyle = Screen.UnderlineStyle;
    /// Uses the canonical terminal baseline displacement.
    pub const Baseline = Screen.Baseline;
    /// Uses the canonical resolved cursor shape.
    pub const CursorShape = Screen.CursorShape;
    /// Provides the canonical default terminal cell attributes.
    pub const default_cell_attrs = Screen.default_cell_attrs;
    /// Provides the immutable terminal palette and dynamic-color defaults.
    pub const default_presentation = defaultPresentation();
    /// Bounds each borrowed title or icon value in a surface publication.
    pub const metadata_max_bytes = max_metadata_bytes;
    /// Bounds one finalized logical line retained as UTF-8 evidence.
    pub const logical_output_line_max_bytes = logical_output_line_bytes_max;
    /// Bounds all finalized logical-line UTF-8 evidence retained by one terminal.
    pub const logical_output_max_bytes = logical_output_bytes_max;

    /// Names why one finalized logical line has no retained text.
    pub const LogicalOutputLossReason = OutputLossReason;

    /// Copies bounded evidence for one finalized line whose text was omitted.
    pub const LogicalOutputLoss = struct {
        /// Identifies the omitted finalized line in output order.
        id: u64,
        /// Reports the exact UTF-8 byte count measured without retaining text.
        byte_count: usize,
        /// Reports why the finalized text was not retained.
        reason: LogicalOutputLossReason,
    };

    /// Owns one bounded copy of finalized primary output and the current open line.
    pub const LogicalOutput = struct {
        /// Frees both copied slices for this result.
        allocator: std.mem.Allocator,
        /// Contains newline-separated finalized lines after the requested cursor.
        text: []u8,
        /// Contains the current primary logical line for this publication.
        open_line: []u8,
        /// Reports that the open line did not fit after copied finalized evidence.
        open_line_omitted: bool,
        /// Owns ordered loss evidence within the copied cursor interval.
        losses: []LogicalOutputLoss,
        /// Identifies the oldest finalized line still retained.
        oldest: u64,
        /// Identifies the last finalized line copied, or the requested cursor.
        cursor: u64,
        /// Identifies the newest finalized line retained at publication time.
        newest: u64,
        /// Counts finalized lines copied into `text`.
        line_count: u16,
        /// Reports that another finalized line remains after `cursor`.
        more: bool,
        /// Binds `open_line` to one surface publication.
        publication: u64,

        /// Releases both copied byte slices exactly once.
        pub fn deinit(self: *LogicalOutput) void {
            self.allocator.free(self.losses);
            self.allocator.free(self.open_line);
            self.allocator.free(self.text);
            self.* = undefined;
        }
    };

    /// Distinguishes copied output from exact cursor and retention failures.
    pub const LogicalOutputResult = union(enum) {
        /// Owns copied finalized and publication-scoped open output.
        output: LogicalOutput,
        /// Reports the oldest cursor after whole-line retention eviction.
        cursor_stale: u64,
        /// Reports the newest cursor when a request is from the future.
        cursor_ahead: u64,
        /// Identifies a retained line requiring a larger bounded request.
        line_too_long: u64,
        /// Reports that the open line alone exceeds the requested byte bound.
        open_line_too_long,
    };

    /// Reports invalid zero limits or copy allocation failure.
    pub const LogicalOutputError = std.mem.Allocator.Error || error{InvalidLimit};

    /// Copies the retained finalized-line identity bounds without output bytes.
    pub const LogicalOutputRange = struct {
        /// Identifies the oldest retained line, or the next identity when empty.
        oldest: u64,
        /// Identifies the newest retained line, or zero when empty.
        newest: u64,
    };

    const ScreenSet = Set;

    allocator: std.mem.Allocator,
    stream_state: TerminalStreamState,
    screen_state: ScreenSet,
    modes: ModeState = .{},
    kitty: KittyState = .{},
    sgr_stack: [sgr_stack_capacity]SgrStackEntry = [_]SgrStackEntry{.{}} ** sgr_stack_capacity,
    sgr_stack_len: u8 = 0,
    xtchecksum_flags: u16 = 0,
    host: HostState,
    gl_index: u8 = 0,
    gr_index: u8 = 1,
    single_shift: ?u8 = null,
    designations: [4]u8 = .{ 'B', 'B', 'B', 'B' },
    primary_savepoint: Savepoint = .{},
    alternate_savepoint: Savepoint = .{},
    dirty_generation: u64 = 1,
    surface_publication: Publication = .{},
    scrollback_offset: u32 = 0,

    /// Selects absolute, relative, or edge-based history viewport movement.
    pub const ScrollViewport = union(enum) {
        top,
        bottom,
        delta: i64,
        absolute: u64,
    };

    fn initWithScreens(
        allocator: std.mem.Allocator,
        stream_state: TerminalStreamState,
        state: Screen,
        alt_state: Screen,
    ) Terminal {
        return .{
            .allocator = allocator,
            .stream_state = stream_state,
            .screen_state = ScreenSet.init(state, alt_state),
            .host = HostState.init(allocator),
        };
    }

    /// Initialize terminal state with owned primary and alternate cell storage.
    ///
    /// Both dimensions must be nonzero. The caller owns the returned terminal
    /// and must call `deinit`.
    pub fn init(allocator: std.mem.Allocator, rows: u16, cols: u16) InitError!Terminal {
        try validateDimensions(rows, cols);
        var stream_state = try TerminalStreamState.initAlloc(allocator);
        errdefer stream_state.deinit();
        var state = try Screen.initWithCells(allocator, rows, cols);
        errdefer state.deinit(allocator);
        var alt_state = try Screen.initWithCells(allocator, rows, cols);
        errdefer alt_state.deinit(allocator);
        return initWithScreens(allocator, stream_state, state, alt_state);
    }

    /// Initialize terminal state with owned cells and bounded primary history.
    ///
    /// Both dimensions must be nonzero. The caller owns the returned terminal
    /// and must call `deinit`. `history_capacity` bounds retained logical rows;
    /// the alternate screen never retains history.
    pub fn initWithHistory(
        allocator: std.mem.Allocator,
        rows: u16,
        cols: u16,
        history_capacity: u16,
    ) InitError!Terminal {
        try validateDimensions(rows, cols);
        var stream_state = try TerminalStreamState.initAlloc(allocator);
        errdefer stream_state.deinit();
        var state = try Screen.initWithCellsAndHistory(allocator, rows, cols, history_capacity);
        errdefer state.deinit(allocator);
        var alt_state = try Screen.initWithCells(allocator, rows, cols);
        errdefer alt_state.deinit(allocator);
        return initWithScreens(allocator, stream_state, state, alt_state);
    }

    /// Release Terminal resources.
    pub fn deinit(self: *Terminal) void {
        const allocator = self.allocator;
        self.host.deinit();
        self.screen_state.deinit(allocator);
        self.stream_state.deinit();
    }

    /// Returns a stream borrowing this terminal; the terminal must outlive its use.
    pub fn vtStream(self: *Terminal) Stream {
        return .init(self);
    }

    /// Applies a borrowed byte slice and reports mutation; failures reset transient parser state.
    pub fn feed(self: *Terminal, bytes: []const u8) FeedError!FeedSummary {
        const history_before = self.visibleHistoryCount();
        const was_scrolled = self.scrollback_offset > 0;
        var stream = self.vtStream();
        const summary = try stream.nextSliceSummary(bytes);
        self.postApply(summary.state_changed);
        self.repairScrollbackAfterHistoryChange(history_before, was_scrolled);
        return summary;
    }

    /// Publishes mutation identity and enforces cursor and selection invariants after routing.
    pub fn postApply(self: *Terminal, state_changed: bool) void {
        self.screen_state.activeSelection().clearIfInvalidatedByGrid(
            self.screen_state.activeConst(),
        );
        if (state_changed) self.dirty_generation +%= 1;
    }

    /// Resize both terminal screens.
    ///
    /// Both dimensions must be nonzero. Invalid dimensions or allocation
    /// failure leave both screens and terminal publication state unchanged.
    pub fn resize(self: *Terminal, rows: u16, cols: u16) ResizeError!void {
        try validateDimensions(rows, cols);
        const output_before = byteCount(self.host.pending_output.bytes.items);
        errdefer restorePendingOutput(&self.host.pending_output, output_before);
        if (self.modes.inband_resize_notifications) try self.appendInbandResizeReport(rows, cols);
        try self.screen_state.resize(self.allocator, rows, cols);
        self.screen_state.activeSelection().clearIfInvalidatedByGrid(
            self.screen_state.activeConst(),
        );
        self.clampScrollbackOffset();
        self.dirty_generation +%= 1;
    }

    // Appends one exact iTerm2/Kitty mode-2048 resize report when host pixel facts are known.
    fn appendInbandResizeReport(self: *Terminal, rows: u16, cols: u16) ResizeError!void {
        const cell = self.cellPixelSize() orelse return;
        const pixel_height = @as(u64, cell.height) * @as(u64, rows);
        const pixel_width = @as(u64, cell.width) * @as(u64, cols);
        var scratch: [96]u8 = undefined;
        const payload = std.fmt.bufPrint(
            scratch[0..],
            "48;{d};{d};{d};{d}t",
            .{ rows, cols, pixel_height, pixel_width },
        ) catch unreachable;
        try appendCsiReply(&self.host.pending_output, self.allocator, .terminal, payload);
    }

    /// Sets nonzero cell pixels on both screens; zero dimensions are rejected unchanged.
    pub fn setCellPixelSize(
        self: *Terminal,
        width: u32,
        height: u32,
    ) CellPixelSizeError!void {
        if (width == 0 or height == 0) return error.InvalidDimensions;
        const previous = self.screen_state.primary.cellPixelSize();
        if (previous) |cell| {
            if (cell.width == width and cell.height == height) return;
        }

        self.screen_state.setCellPixelSize(width, height);
    }

    /// Returns configured nonzero cell pixels for protocol reports, when known.
    pub fn cellPixelSize(self: *const Terminal) ?CellPixelSize {
        const value = self.screen_state.activeConst().cellPixelSize() orelse return null;
        return .{ .width = value.width, .height = value.height };
    }

    /// Applies RIS while preserving dimensions and owned allocations.
    pub fn hardReset(self: *Terminal) void {
        self.screen_state.reset();
        self.screen_state.primary.insert_mode = false;
        self.screen_state.alternate.insert_mode = false;
        self.modes = .{};
        self.primary_savepoint.clear();
        self.alternate_savepoint.clear();
        self.gl_index = 0;
        self.gr_index = 1;
        self.single_shift = null;
        self.designations = .{ 'B', 'B', 'B', 'B' };
        self.stream_state.parser.resetTextEncoding();
        self.host.pending_output.eight_bit_controls = false;
        self.kitty.resetTerminalState();
        self.host.resetTerminalState();
    }

    // Applies DECSTR to active-bank state and terminal-global modes without erasing text or moving the cursor.
    fn softReset(self: *Terminal) bool {
        const active = self.screen_state.active();
        var changed = active.softReset();

        changed = replaceBool(&self.screen_state.primary.insert_mode, false) or changed;
        changed = replaceBool(&self.screen_state.alternate.insert_mode, false) or changed;
        changed = self.screen_state.primary.setLeftRightMarginMode(false) or changed;
        changed = self.screen_state.alternate.setLeftRightMarginMode(false) or changed;
        changed = replaceBool(&self.screen_state.primary.cursor.visible, true) or changed;
        changed = replaceBool(&self.screen_state.alternate.cursor.visible, true) or changed;

        changed = replaceBool(&self.modes.application_cursor_keys, false) or changed;
        changed = replaceBool(&self.modes.application_keypad, false) or changed;
        changed = replaceBool(&self.modes.newline_mode, false) or changed;
        changed = replaceBool(&self.modes.focus_reporting, false) or changed;
        changed = replaceBool(&self.modes.bracketed_paste, false) or changed;
        changed = replaceBool(&self.modes.inband_resize_notifications, false) or changed;
        changed = replaceBool(&self.modes.reverse_wraparound_mode, false) or changed;
        changed = replaceBool(&self.modes.extended_reverse_wraparound_mode, false) or changed;
        if (self.modes.mouse_tracking != .off) changed = true;
        self.modes.mouse_tracking = .off;
        if (self.modes.mouse_protocol != .none) changed = true;
        self.modes.mouse_protocol = .none;
        changed = replaceBool(&self.host.pending_output.eight_bit_controls, false) or changed;
        if (self.gl_index != 0 or self.gr_index != 1 or self.single_shift != null or
            !std.mem.eql(u8, self.designations[0..], &.{ 'B', 'B', 'B', 'B' })) changed = true;
        self.gl_index = 0;
        self.gr_index = 1;
        self.single_shift = null;
        self.designations = .{ 'B', 'B', 'B', 'B' };
        return changed;
    }

    // Pushes selected active rendition attributes onto the fixed iTerm2-compatible stack.
    fn pushSgr(self: *Terminal, params: ModeParams) bool {
        if (self.sgr_stack_len == sgr_stack_capacity) return false;
        self.sgr_stack[self.sgr_stack_len] = .{
            .attrs = self.screen_state.activeConst().current_attrs,
            .selection = sgrSelection(params),
        };
        self.sgr_stack_len += 1;
        return true;
    }

    // Pops one snapshot and restores only the attributes selected by its push.
    fn popSgr(self: *Terminal) bool {
        if (self.sgr_stack_len == 0) return false;
        self.sgr_stack_len -= 1;
        const entry = self.sgr_stack[self.sgr_stack_len];
        restoreSelectedSgr(&self.screen_state.active().current_attrs, entry);
        return true;
    }

    // Restores the iTerm2-owned DECCIR subset after complete payload validation.
    fn restoreCursorInformation(self: *Terminal, payload: []const u8) bool {
        const info = parseCursorInformation(payload) orelse return false;
        const active = self.screen_state.active();
        const cursor_before = active.cursor;
        const attrs_before = active.current_attrs;
        const wrap_before = active.wrap_pending;
        const origin_before = active.origin_mode;

        const row = @min(info.row, active.rows - 1);
        const col = @min(info.col, active.lineRightBoundary(row));
        active.cursor.setPositionByClient(row, col);
        active.current_attrs.reverse = info.reverse;
        active.current_attrs.blink = info.blink;
        active.current_attrs.underline = info.underline;
        active.current_attrs.bold = info.bold;
        active.wrap_pending = info.wrap_pending and active.auto_wrap and col == active.lineRightBoundary(row);
        active.origin_mode = info.origin_mode;
        const designation_changed = configureCharset(self, 0, info.g0_designation);

        return !std.meta.eql(cursor_before, active.cursor) or
            !std.meta.eql(attrs_before, active.current_attrs) or
            wrap_before != active.wrap_pending or origin_before != active.origin_mode or
            designation_changed;
    }

    // Replaces the active screen's bounded tab-stop set from one-based DECTABSR values.
    fn restoreTabStops(self: *Terminal, payload: []const u8) bool {
        const stops = self.screen_state.active().tab_stops orelse return false;
        var restored: [parser_mod.max_metadata_control_bytes / 2 + 1]u16 = undefined;
        var restored_count: usize = 0;
        var values = std.mem.splitScalar(u8, payload, '/');
        while (values.next()) |field| {
            // iTerm2 filters invalid members independently instead of rejecting the complete stop set.
            const one_based = std.fmt.parseInt(u32, field, 10) catch continue;
            if (one_based == 0 or one_based > stops.len) continue;
            std.debug.assert(restored_count < restored.len);
            restored[restored_count] = @intCast(one_based - 1);
            restored_count += 1;
        }
        std.sort.block(u16, restored[0..restored_count], {}, std.sort.asc(u16));

        var changed = false;
        var restored_index: usize = 0;
        for (stops, 0..) |*stop, col| {
            const column: u16 = @intCast(col);
            while (restored_index < restored_count and restored[restored_index] < column)
                restored_index += 1;
            const next = restored_index < restored_count and restored[restored_index] == column;
            changed = stop.* != next or changed;
            stop.* = next;
        }
        return changed;
    }

    /// Saves cursor, rendition, charset, origin, and wrap state into the active screen slot.
    ///
    /// The result reports whether the bank-local savepoint changed.
    pub fn saveCursor(self: *Terminal) bool {
        const next = self.captureSavepoint();
        const savepoint = self.activeSavepoint();
        if (std.meta.eql(savepoint.*, next)) return false;
        savepoint.* = next;
        return true;
    }

    fn captureSavepoint(self: *const Terminal) Savepoint {
        const active = self.screen_state.activeConst();
        return .{
            .valid = true,
            .cursor = .{
                .row = active.cursor.row,
                .col = active.cursor.col,
                .style = active.cursor.effectiveStyle(),
            },
            .current_attrs = active.current_attrs,
            .reverse_screen_mode = self.modes.reverse_screen_mode,
            .origin_mode = active.origin_mode,
            .auto_wrap = active.auto_wrap,
            .wrap_pending = active.wrap_pending,
            .gl_index = self.gl_index,
            .gr_index = self.gr_index,
            .designations = self.designations,
        };
    }

    /// Restores the active bank savepoint and reports exact retained-state mutation.
    ///
    /// Position is clamped to current dimensions and a saved pending wrap survives
    /// only when the restored position remains at the active right boundary.
    pub fn restoreCursor(self: *Terminal) bool {
        const active = self.screen_state.active();
        const cursor_before = active.cursor;
        const attrs_before = active.current_attrs;
        const wrap_pending_before = active.wrap_pending;
        const auto_wrap_before = active.auto_wrap;
        const origin_before = active.origin_mode;
        const reverse_before = self.modes.reverse_screen_mode;
        const gl_before = self.gl_index;
        const gr_before = self.gr_index;
        const single_shift_before = self.single_shift;
        const designations_before = self.designations;

        self.restoreCursorState();
        return !std.meta.eql(cursor_before, active.cursor) or
            !std.meta.eql(attrs_before, active.current_attrs) or
            wrap_pending_before != active.wrap_pending or
            auto_wrap_before != active.auto_wrap or
            origin_before != active.origin_mode or
            reverse_before != self.modes.reverse_screen_mode or
            gl_before != self.gl_index or gr_before != self.gr_index or
            single_shift_before != self.single_shift or
            !std.mem.eql(u8, designations_before[0..], self.designations[0..]);
    }

    fn restoreCursorState(self: *Terminal) void {
        const active = self.screen_state.active();
        const savepoint = self.activeSavepointConst();
        active.wrap_pending = false;
        if (!savepoint.valid) {
            active.cursor.setPositionStructural(0, 0);
            self.modes.reverse_screen_mode = false;
            active.origin_mode = false;
            self.gl_index = 0;
            self.gr_index = 1;
            self.single_shift = null;
            self.designations = .{ 'B', 'B', 'B', 'B' };
            return;
        }

        self.modes.reverse_screen_mode = savepoint.reverse_screen_mode;
        active.origin_mode = savepoint.origin_mode;
        active.auto_wrap = savepoint.auto_wrap;
        active.current_attrs = savepoint.current_attrs;
        active.cursor.restoreSavedStyle(savepoint.cursor.style);
        restoreCursorPosition(active, savepoint.cursor.row, savepoint.cursor.col);
        active.wrap_pending = savepoint.wrap_pending and active.cursor.col == active.rightBoundary();
        self.gl_index = savepoint.gl_index;
        self.gr_index = savepoint.gr_index;
        self.single_shift = null;
        self.designations = savepoint.designations;
    }

    /// Switches primary or alternate screen with explicit clear and cursor-save behavior.
    pub fn switchScreenMode(self: *Terminal, enable_alt: bool, clear_alt: bool, save_restore_cursor: bool) bool {
        if (enable_alt) {
            if (self.screen_state.alt_active) return false;
            if (save_restore_cursor) self.activeSavepoint().* = self.captureSavepoint();
            self.screen_state.alt_active = true;
            self.scrollback_offset = 0;
            self.screen_state.activeSelection().clear();
            if (clear_alt) self.screen_state.alternate.clearVisibleCells();
            self.screen_state.alternate.resetCursorForAltEntry();
            self.screen_state.alternate.markAllRowsDirty();
            return true;
        }

        if (!self.screen_state.alt_active) return false;
        self.screen_state.alt_active = false;
        self.clampScrollbackOffset();
        self.screen_state.activeSelection().clear();
        if (save_restore_cursor) self.restoreCursorState();
        self.screen_state.primary.markAllRowsDirty();
        return true;
    }

    /// Apply one canonical semantic mode event.
    pub fn applyModeEvent(self: *Terminal, event: SemanticEvent) bool {
        switch (event) {
            .application_cursor_keys => |enabled| return replaceBool(&self.modes.application_cursor_keys, enabled),
            .application_keypad => |enabled| return replaceBool(&self.modes.application_keypad, enabled),
            .auto_repeat => |enabled| return self.setDecMode(8, enabled),
            .reverse_screen_mode => |enabled| return self.setDecMode(5, enabled),
            .eight_bit_controls => |enabled| {
                const changed = self.host.pending_output.eight_bit_controls != enabled;
                self.host.pending_output.eight_bit_controls = enabled;
                return changed;
            },
            .left_right_margin_mode => |enabled| return self.setDecMode(69, enabled),
            .cursor_visible => |enabled| return self.setDecMode(25, enabled),
            .cursor_blink => |enabled| return self.setDecMode(12, enabled),
            .ansi_mode_set => |modes| return self.setAnsiModes(modes.params[0..modes.param_count], true),
            .ansi_mode_reset => |modes| return self.setAnsiModes(modes.params[0..modes.param_count], false),
            .modify_other_keys_set => |value| {
                if (self.modes.modify_other_keys == value) return false;
                self.modes.modify_other_keys = value;
                return true;
            },
            .modify_other_keys_disable => {
                if (self.modes.modify_other_keys == -1) return false;
                self.modes.modify_other_keys = -1;
                return true;
            },
            .key_format_change => |change| {
                if (change.resource) |resource| {
                    if (!isKeyFormatResource(resource)) return false;
                    const value = change.value orelse 0;
                    if (self.modes.key_format[resource] == value) return false;
                    self.modes.key_format[resource] = value;
                    return true;
                } else {
                    const empty = [_]u16{0} ** 8;
                    if (std.mem.eql(u16, self.modes.key_format[0..], empty[0..])) return false;
                    self.modes.key_format = [_]u16{0} ** 8;
                    return true;
                }
            },
            .pointer_mode => |value| {
                if (self.modes.pointer_mode == value) return false;
                self.modes.pointer_mode = value;
                return true;
            },
            .reverse_wraparound_mode => |enabled| return self.setDecMode(45, enabled),
            .extended_reverse_wraparound_mode => |enabled| {
                return self.setDecMode(1045, enabled);
            },
            .bracketed_paste => |enabled| return replaceBool(&self.modes.bracketed_paste, enabled),
            .synchronized_output => |enabled| return replaceBool(&self.modes.synchronized_output, enabled),
            .inband_resize_notifications => |enabled| return self.setDecMode(2048, enabled),
            .dec_mode_save => |modes| return self.saveDecModes(modes.params[0..modes.param_count]),
            .dec_mode_restore => |modes| return self.restoreDecModes(modes.params[0..modes.param_count]),
            else => unreachable,
        }
    }

    fn decModeState(self: *const Terminal, mode_number: u16) u8 {
        const active = self.screen_state.activeConst();
        return decModeStateForView(.{
            .application_cursor_keys = self.modes.application_cursor_keys,
            .application_keypad = self.modes.application_keypad,
            .auto_repeat = self.modes.auto_repeat,
            .reverse_screen_mode = self.modes.reverse_screen_mode,
            .origin_mode = active.origin_mode,
            .auto_wrap = active.auto_wrap,
            .left_right_margin_mode = active.left_right_margin_mode,
            .cursor_blink = active.cursor.blink_intent,
            .cursor_visible = active.cursor.visible,
            .alt_active = self.screen_state.alt_active,
            .mouse_tracking = self.modes.mouse_tracking,
            .mouse_protocol = self.modes.mouse_protocol,
            .focus_reporting = self.modes.focus_reporting,
            .bracketed_paste = self.modes.bracketed_paste,
            .synchronized_output = self.modes.synchronized_output,
            .inband_resize_notifications = self.modes.inband_resize_notifications,
            .reverse_wraparound = self.modes.reverse_wraparound_mode,
            .extended_reverse_wraparound = self.modes.extended_reverse_wraparound_mode,
        }, mode_number);
    }

    fn saveDecModes(self: *Terminal, mode_numbers: []const u16) bool {
        var changed = false;
        for (mode_numbers) |mode_number| {
            if (!canSetDecMode(mode_number)) continue;
            const slot = savedDecModeSlot(
                self.modes.saved_dec_modes[0..],
                &self.modes.saved_dec_mode_count,
                mode_number,
            ) orelse continue;
            const value: SavedDecMode = .{
                .mode = mode_number,
                .state = self.decModeState(mode_number),
            };
            const target = &self.modes.saved_dec_modes[@intCast(slot)];
            if (target.mode == value.mode and target.state == value.state) continue;
            target.* = value;
            changed = true;
        }
        return changed;
    }

    fn restoreDecModes(self: *Terminal, mode_numbers: []const u16) bool {
        var changed = false;
        for (mode_numbers) |mode_number| {
            const state = savedDecModeState(
                self.modes.saved_dec_modes[0..],
                self.modes.saved_dec_mode_count,
                mode_number,
            ) orelse continue;
            switch (state) {
                1 => changed = self.setDecMode(mode_number, true) or changed,
                2 => changed = self.setDecMode(mode_number, false) or changed,
                else => {},
            }
        }
        return changed;
    }

    fn setDecMode(self: *Terminal, mode_number: u16, enabled: bool) bool {
        const active = self.screen_state.active();
        const pending_changed = active.cancelPendingWrap();
        const mode_changed = switch (mode_number) {
            1 => replaceBool(&self.modes.application_cursor_keys, enabled),
            5 => replaceBool(&self.modes.reverse_screen_mode, enabled),
            6 => changed: {
                const before = .{ active.origin_mode, active.cursor.row, active.cursor.col };
                active.applyScreen(.{ .origin_mode = enabled });
                break :changed !std.meta.eql(before, .{ active.origin_mode, active.cursor.row, active.cursor.col });
            },
            7 => changed: {
                const before = active.auto_wrap;
                active.applyScreen(.{ .auto_wrap = enabled });
                break :changed before != active.auto_wrap;
            },
            8 => replaceBool(&self.modes.auto_repeat, enabled),
            12 => active.cursor.setBlink(enabled),
            69 => result: {
                const inactive = if (self.screen_state.alt_active)
                    &self.screen_state.primary
                else
                    &self.screen_state.alternate;
                var changed = active.setLeftRightMarginMode(enabled);
                changed = replaceBool(&inactive.left_right_margin_mode, enabled) or changed;
                if (!enabled) {
                    changed = inactive.left_margin != 0 or
                        inactive.right_margin != inactive.cols -| 1 or changed;
                    inactive.left_margin = 0;
                    inactive.right_margin = inactive.cols -| 1;
                }
                break :result changed;
            },
            25 => result: {
                var changed = replaceBool(&self.screen_state.primary.cursor.visible, enabled);
                changed = replaceBool(&self.screen_state.alternate.cursor.visible, enabled) or changed;
                break :result changed;
            },
            45 => replaceBool(&self.modes.reverse_wraparound_mode, enabled),
            66 => replaceBool(&self.modes.application_keypad, enabled),
            47 => self.switchScreenMode(enabled, false, false),
            1047 => self.switchScreenMode(enabled, true, false),
            1049 => self.switchScreenMode(enabled, true, true),
            1045 => replaceBool(&self.modes.extended_reverse_wraparound_mode, enabled),
            9 => self.setMouseTracking(if (enabled) .x10 else .off),
            1000 => self.setMouseTracking(if (enabled) .normal else .off),
            1002 => self.setMouseTracking(if (enabled) .button_event else .off),
            1003 => self.setMouseTracking(if (enabled) .any_event else .off),
            1004 => replaceBool(&self.modes.focus_reporting, enabled),
            1005 => self.setMouseProtocol(if (enabled) .utf8 else .none),
            1006 => self.setMouseProtocol(if (enabled) .sgr else .none),
            1015 => self.setMouseProtocol(if (enabled) .urxvt else .none),
            1016 => self.setMouseProtocol(if (enabled) .sgr_pixel else .none),
            2004 => replaceBool(&self.modes.bracketed_paste, enabled),
            2026 => replaceBool(&self.modes.synchronized_output, enabled),
            2048 => replaceBool(&self.modes.inband_resize_notifications, enabled),
            else => false,
        };
        return mode_changed or pending_changed;
    }

    fn setAnsiModes(self: *Terminal, mode_numbers: []const u16, enabled: bool) bool {
        var changed = false;
        for (mode_numbers) |mode_number| switch (mode_number) {
            2 => changed = replaceBool(&self.modes.keyboard_action_mode, enabled) or changed,
            4 => {
                changed = replaceBool(&self.screen_state.primary.insert_mode, enabled) or changed;
                changed = replaceBool(&self.screen_state.alternate.insert_mode, enabled) or changed;
            },
            12 => changed = replaceBool(&self.modes.send_receive_mode, enabled) or changed,
            20 => changed = replaceBool(&self.modes.newline_mode, enabled) or changed,
            else => {},
        };
        return changed;
    }

    fn setMouseTracking(self: *Terminal, value: MouseTrackingMode) bool {
        const pending_changed = self.screen_state.active().cancelPendingWrap();
        if (self.modes.mouse_tracking == value) return pending_changed;
        self.modes.mouse_tracking = value;
        return true;
    }

    fn setMouseProtocol(self: *Terminal, value: MouseProtocol) bool {
        if (self.modes.mouse_protocol == value) return false;
        self.modes.mouse_protocol = value;
        return true;
    }

    /// Acknowledges a published snapshot and retires dirty state only for valid identities.
    pub fn ackSurface(self: *Terminal, snapshot_seq: u64) bool {
        if (!self.surface_publication.canAck(snapshot_seq, self.dirty_generation)) return false;
        clearDirtyRows(&self.screen_state);
        return true;
    }

    /// Moves the history viewport within current visible-history bounds.
    pub fn scrollViewport(self: *Terminal, behavior: ScrollViewport) bool {
        const history_count = self.visibleHistoryCount();
        const previous = self.scrollback_offset;
        self.scrollback_offset = switch (behavior) {
            .top => history_count,
            .bottom => 0,
            .delta => |delta| offset: {
                if (delta < 0) {
                    const decrease: u64 = if (delta == std.math.minInt(i64))
                        @as(u64, @intCast(std.math.maxInt(i64))) + 1
                    else
                        @intCast(-delta);
                    break :offset if (decrease >= previous) 0 else previous - @as(u32, @intCast(decrease));
                }
                const increase: u64 = @intCast(delta);
                const target = @as(u64, previous) + increase;
                break :offset @intCast(@min(target, history_count));
            },
            .absolute => |offset| @intCast(@min(offset, history_count)),
        };
        std.debug.assert(self.scrollback_offset <= history_count);
        return self.scrollback_offset != previous;
    }

    /// Returns history rows currently reachable above the active screen.
    pub fn visibleHistoryCount(self: *const Terminal) u32 {
        if (self.screen_state.alt_active) return 0;
        return self.screen_state.activeConst().historyCount();
    }

    fn clampScrollbackOffset(self: *Terminal) void {
        const history_count = self.visibleHistoryCount();
        self.scrollback_offset = @min(self.scrollback_offset, history_count);
        std.debug.assert(self.scrollback_offset <= history_count);
    }

    fn repairScrollbackAfterHistoryChange(self: *Terminal, history_before: u32, was_scrolled: bool) void {
        const history_after = self.visibleHistoryCount();
        if (history_after > history_before) {
            if (was_scrolled) {
                const delta = history_after - history_before;
                const target = @as(u64, self.scrollback_offset) + delta;
                self.scrollback_offset = @intCast(@min(target, history_after));
                std.debug.assert(self.scrollback_offset <= history_after);
            }
            return;
        }
        self.scrollback_offset = @min(self.scrollback_offset, history_after);
        std.debug.assert(self.scrollback_offset <= history_after);
    }

    /// Publishes and borrows the current surface until terminal mutation.
    pub fn surfaceSnapshot(self: *Terminal) SurfacePublication {
        const snapshot = projectSurface(&self.screen_state, self.scrollback_offset);
        const active = self.screen_state.activeConst();
        const colors = self.host.terminalColorState();
        return .{
            .snapshot_seq = self.surface_publication.publish(
                snapshot.view,
                self.scrollback_offset,
                self.dirty_generation,
            ),
            .dirty_generation = self.dirty_generation,
            .snapshot = snapshot,
            .presentation = .{
                .palette = colors.palette,
                .foreground = colors.foreground,
                .background = colors.background,
                .cursor = active.cursor.cursor_color orelse colors.cursor,
                .cursor_text = active.cursor.cursor_text_color orelse colors.cursor_text,
                .reverse_screen = self.modes.reverse_screen_mode,
            },
            .title = self.host.current_title,
            .icon = self.host.current_icon,
            .working_directory = self.host.working_directory_report,
            .shell_integration = if (self.host.shell_integration) |integration| .{
                .version = integration.version,
                .shell = integration.shell,
            } else null,
            .shell_mark = self.host.shell_mark,
            .bell_generation = self.host.bell_generation,
            .history_loss_generation = self.screen_state.primary.history_loss_generation,
            .is_alternate_screen = snapshot.view.is_alternate_screen,
        };
    }

    /// Returns copied dimensions, cursor, history, and active-screen metadata.
    pub fn visibleMeta(self: *Terminal) VisibleMeta {
        const publication = self.surfaceSnapshot();
        const view = publication.snapshot.view;
        return .{
            .rows = view.rows,
            .cols = view.cols,
            .history_count = view.history_count,
            .is_alternate_screen = view.is_alternate_screen,
            .snapshot_seq = publication.snapshot_seq,
            .dirty_generation = publication.dirty_generation,
        };
    }

    /// Copies finalized primary logical lines after `cursor` and one publication-scoped open line.
    pub fn copyLogicalOutput(
        self: *Terminal,
        allocator: std.mem.Allocator,
        cursor: u64,
        max_lines: u16,
        max_bytes: usize,
    ) LogicalOutputError!LogicalOutputResult {
        if (max_lines == 0 or max_bytes == 0 or max_bytes > logical_output_bytes_max) {
            return error.InvalidLimit;
        }
        const primary = &self.screen_state.primary;
        const count = primary.output_lines_count;
        const newest = primary.next_output_id - 1;
        const oldest = if (count == 0)
            primary.next_output_id
        else
            primary.output_lines.items[@intCast(primary.output_lines_start)].?.id;
        if (cursor > newest) return .{ .cursor_ahead = newest };
        if (oldest > 1 and cursor < oldest - 1) return .{ .cursor_stale = oldest };

        var text = std.ArrayList(u8).empty;
        errdefer text.deinit(allocator);
        var losses = std.ArrayList(LogicalOutputLoss).empty;
        errdefer losses.deinit(allocator);
        var entry_count: u16 = 0;
        var line_count: u16 = 0;
        var output_cursor = cursor;
        var more = false;
        var logical_index: u16 = 0;
        while (logical_index < count) : (logical_index += 1) {
            const slot = (primary.output_lines_start + @as(u32, @intCast(logical_index))) %
                @as(u32, @intCast(primary.output_lines.items.len));
            const line = primary.output_lines.items[@intCast(slot)].?;
            if (line.id <= cursor) continue;
            if (entry_count == max_lines) {
                more = true;
                break;
            }
            switch (line.value) {
                .loss => |loss| {
                    try losses.append(allocator, .{
                        .id = line.id,
                        .byte_count = loss.byte_count,
                        .reason = loss.reason,
                    });
                },
                .text => |line_text| {
                    const separator: usize = if (line_count == 0) 0 else 1;
                    const remaining = max_bytes - text.items.len;
                    if (separator > remaining or line_text.len > remaining - separator) {
                        if (entry_count == 0) return .{ .line_too_long = line.id };
                        more = true;
                        break;
                    }
                    if (separator != 0) try text.append(allocator, '\n');
                    try text.appendSlice(allocator, line_text);
                    line_count += 1;
                },
            }
            if (more) break;
            entry_count += 1;
            output_cursor = line.id;
        }
        var open_line_omitted = false;
        const open_line = copyOpenOutputLine(
            allocator,
            primary,
            max_bytes - text.items.len,
        ) catch |failure| switch (failure) {
            error.LineTooLong => if (entry_count == 0)
                return .open_line_too_long
            else blk: {
                open_line_omitted = true;
                break :blk try allocator.dupe(u8, "");
            },
            error.OutOfMemory => return error.OutOfMemory,
        };
        errdefer allocator.free(open_line);
        const owned_text = try text.toOwnedSlice(allocator);
        errdefer allocator.free(owned_text);
        const owned_losses = try losses.toOwnedSlice(allocator);
        errdefer allocator.free(owned_losses);
        const publication = self.surfaceSnapshot().snapshot_seq;
        return .{ .output = .{
            .allocator = allocator,
            .text = owned_text,
            .open_line = open_line,
            .open_line_omitted = open_line_omitted,
            .losses = owned_losses,
            .oldest = oldest,
            .cursor = output_cursor,
            .newest = newest,
            .line_count = line_count,
            .more = more,
            .publication = publication,
        } };
    }

    /// Returns the current finalized primary-output retention bounds.
    pub fn logicalOutputRange(self: *const Terminal) LogicalOutputRange {
        const primary = &self.screen_state.primary;
        const count = primary.output_lines_count;
        return .{
            .oldest = if (count == 0)
                primary.next_output_id
            else
                primary.output_lines.items[@intCast(primary.output_lines_start)].?.id,
            .newest = primary.next_output_id - 1,
        };
    }

    /// Borrows a cell hyperlink URI only when snapshot identity and coordinates are valid.
    pub fn visibleCellHyperlinkUri(
        self: *Terminal,
        snapshot_seq: u64,
        row: u16,
        col: u16,
    ) error{InvalidArgument}!?[]const u8 {
        if (snapshot_seq == 0) return error.InvalidArgument;
        const publication = self.surfaceSnapshot();
        if (publication.snapshot_seq != snapshot_seq) return error.InvalidArgument;
        const view = publication.snapshot.view;
        if (row >= view.rows or col >= view.cols) return error.InvalidArgument;
        return self.host.hyperlinkUriForId(view.cellInfoAt(row, col).attrs.link_id);
    }

    /// Borrows the current cell hyperlink URI, or null for invalid coordinates or no link.
    pub fn visibleCellHyperlinkUriCurrent(self: *Terminal, row: u16, col: u16) ?[]const u8 {
        const publication = self.surfaceSnapshot();
        const view = publication.snapshot.view;
        if (row >= view.rows or col >= view.cols) return null;
        return self.host.hyperlinkUriForId(view.cellInfoAt(row, col).attrs.link_id);
    }

    /// Returns a copied active-screen selection when one exists.
    pub fn selectionState(self: *const Terminal) ?TerminalSelection {
        return self.screen_state.activeSelectionConst().state();
    }

    /// Starts selection at a clamped column and VT/history row.
    pub fn startSelection(self: *Terminal, row: i32, col: u16) void {
        self.screen_state.activeSelection().start(self.selectionAbsoluteRow(row), col);
        self.noteSelectionChanged();
    }

    /// Moves the active selection endpoint to a clamped column.
    pub fn updateSelection(self: *Terminal, row: i32, col: u16) void {
        const before = self.selectionState() orelse return;
        self.screen_state.activeSelection().update(self.selectionAbsoluteRow(row), col);
        const after = self.selectionState() orelse return;
        if (before.end.row == after.end.row and before.end.col == after.end.col) return;
        self.noteSelectionChanged();
    }

    /// Marks the active selection complete without changing its endpoints.
    pub fn finishSelection(self: *Terminal) void {
        const before = self.selectionState() orelse return;
        self.screen_state.activeSelection().finish();
        const after = self.selectionState() orelse return;
        if (before.selecting == after.selecting) return;
        self.noteSelectionChanged();
    }

    /// Clears active-screen selection state.
    pub fn clearSelection(self: *Terminal) void {
        if (self.selectionState() == null) return;
        self.screen_state.activeSelection().clear();
        self.noteSelectionChanged();
    }

    /// Copy selected terminal text into caller-owned memory.
    ///
    /// The returned slice is always owned by `allocator`, including when no
    /// selection exists, and the caller must free it.
    pub fn copySelection(self: *const Terminal, allocator: std.mem.Allocator) CopyError![]const u8 {
        if (self.selectionState() == null) return allocator.dupe(u8, "");
        return copyText(allocator, &self.screen_state, self.selectionState());
    }

    /// Encode one host input event according to current terminal modes.
    ///
    /// Non-paste results borrow `scratch` or event bytes. Paste encoding may
    /// allocate through `allocator`; callers must always call `deinit` on the
    /// returned value. Paste length overflow is reported separately from
    /// allocator exhaustion. Mouse input may also fail while retaining a
    /// bounded locator report; failure preserves pending output and report
    /// latches.
    pub fn encodeInput(
        self: *Terminal,
        allocator: std.mem.Allocator,
        scratch: *InputScratch,
        event: InputEvent,
    ) InputError!EncodedInput {
        return switch (event) {
            .bytes => |bytes| .{ .bytes = bytes },
            .key => |key| .{ .bytes = try self.encodeKeyInput(scratch, key) },
            .mouse => |mouse| .{ .bytes = try self.encodeMouseInput(scratch, mouse) },
            .focus => |focus| .{ .bytes = self.encodeFocusInput(scratch, focus) },
            .paste => |text| encodePaste(self.modes.bracketed_paste, allocator, text),
        };
    }

    fn encodeKeyInput(
        self: *Terminal,
        scratch: *InputScratch,
        event: KeyEvent,
    ) error{ InvalidUtf8, InvalidText, KeyTextLimit }![]const u8 {
        if (self.modes.keyboard_action_mode) return scratch.buf[0..0];
        if (!self.modes.auto_repeat and event.action == .repeat) return scratch.buf[0..0];
        const kitty_flags = self.kitty.activeScreenConst(
            self.screen_state.alt_active,
        ).keyboard.flags;
        comptime std.debug.assert(@sizeOf(InputScratch) >=
            max_kitty_encoded_bytes);
        const encoded = encodeEvent(
            scratch.buf[0..],
            event.key,
            event.mods,
            event.action,
            event.shifted,
            event.alternate,
            event.legacy_text,
            event.text,
            self.modes.application_cursor_keys,
            self.modes.application_keypad,
            self.modes.modify_other_keys,
            self.modes.key_format[4],
            kitty_flags,
        ) catch |failure| switch (failure) {
            error.InvalidUtf8 => return error.InvalidUtf8,
            error.InvalidText => return error.InvalidText,
            error.KeyTextLimit => return error.KeyTextLimit,
            // InputScratch is mechanically larger than the complete encoding
            // bound asserted above; callers cannot reach this encoder error.
            error.EncodingLimit => unreachable,
        };
        std.debug.assert(encoded.len <= scratch.buf.len);
        if (self.modes.newline_mode and
            event.key == .named and
            event.key.named == .enter and
            std.mem.eql(u8, encoded, "\r"))
        {
            return writeScratch(scratch, "\r\n");
        }
        return encoded;
    }

    fn encodeMouseInput(self: *Terminal, scratch: *InputScratch, event: MouseEvent) ApplyError![]const u8 {
        try handleMouseEvent(&self.host.locator, self.allocator, &self.host.pending_output, scratch.buf[0..], event);
        const encoded = encodeMouse(scratch.buf[0..], event, self.modes.mouse_tracking, self.modes.mouse_protocol);
        std.debug.assert(encoded.len <= scratch.buf.len);
        return encoded;
    }

    fn encodeFocusInput(self: *const Terminal, scratch: *InputScratch, event: FocusEvent) []const u8 {
        if (!self.modes.focus_reporting) return scratch.buf[0..0];
        return writeScratch(scratch, switch (event) {
            .in => "\x1b[I",
            .out => "\x1b[O",
        });
    }

    /// Drain pending terminal reply bytes into caller-owned memory.
    ///
    /// Allocation failure preserves the pending bytes. The caller must free a
    /// successful result with `allocator`.
    pub fn drainPendingOutput(self: *Terminal, allocator: std.mem.Allocator) error{OutOfMemory}![]u8 {
        const owned = try allocator.dupe(u8, self.host.pendingOutput());
        self.host.clearPendingOutput();
        return owned;
    }

    /// Drain and decode a pending OSC 52 clipboard-set consequence.
    ///
    /// A returned slice is owned by `allocator`; `null` means no decodable set
    /// request was pending. Allocation failure preserves the request.
    pub fn drainPendingClipboard(self: *Terminal, allocator: std.mem.Allocator) error{OutOfMemory}!?[]u8 {
        return self.host.drainPendingClipboardSet(allocator);
    }

    /// Borrow one pending OSC 52 operation until replacement, drain, reply, or deinit.
    pub fn pendingClipboardRequest(self: *const Terminal) ?ClipboardRequest {
        return self.host.pendingClipboardRequest();
    }

    /// Queue one host-approved OSC 52 reply and consume its query only after complete bounded serialization.
    pub fn replyPendingClipboard(self: *Terminal, bytes: []const u8) ClipboardReplyError!bool {
        return self.host.replyPendingClipboardQuery(bytes);
    }

    fn noteSelectionChanged(self: *Terminal) void {
        self.screen_state.active().markAllRowsDirty();
        self.dirty_generation +%= 1;
    }

    fn selectionAbsoluteRow(self: *const Terminal, row: i32) i32 {
        if (row < 0) return row;
        const absolute = @as(u64, self.screen_state.activeConst().historyRowBase()) + @as(u64, @intCast(row));
        return std.math.cast(i32, absolute) orelse std.math.maxInt(i32);
    }

    fn activeSavepoint(self: *Terminal) *Savepoint {
        return if (self.screen_state.alt_active) &self.alternate_savepoint else &self.primary_savepoint;
    }

    fn activeSavepointConst(self: *const Terminal) *const Savepoint {
        return if (self.screen_state.alt_active) &self.alternate_savepoint else &self.primary_savepoint;
    }

    fn restoreCursorPosition(active: *Screen, row: u16, col: u16) void {
        if (active.rows == 0 or active.cols == 0) {
            active.cursor.setPositionStructural(0, 0);
            return;
        }

        const top = if (active.origin_mode) active.scroll_top else 0;
        const bottom = if (active.origin_mode) @min(active.scroll_bottom, active.rows - 1) else active.rows - 1;
        const bounded_row = @max(top, @min(row, bottom));
        const bounded_col = @min(col, active.cols - 1);
        active.cursor.setPositionStructural(bounded_row, bounded_col);
    }

    /// Pairs a borrowed complete surface and metadata until terminal mutation.
    pub const SurfacePublication = struct {
        snapshot_seq: u64,
        dirty_generation: u64,
        snapshot: SurfaceSnapshot,
        presentation: Presentation,
        title: ?[]const u8,
        icon: ?[]const u8,
        /// Borrows the latest OSC 7 URI or iTerm CurrentDir path until terminal mutation.
        working_directory: ?Terminal.WorkingDirectory,
        shell_integration: ?Terminal.ShellIntegration,
        shell_mark: ShellMark,
        /// Monotonic count of accepted BEL controls; presentation belongs to the embedder.
        bell_generation: u64,
        /// Monotonic count of history rows dropped after bounded allocation failure.
        history_loss_generation: u64,
        is_alternate_screen: bool,
    };

    /// Copies the palette, dynamic defaults, cursor colors, and screen-wide
    /// reverse state that resolve one complete surface publication.
    pub const Presentation = struct {
        palette: [256]Terminal.Rgb,
        foreground: Terminal.Rgb,
        background: Terminal.Rgb,
        cursor: ?Terminal.Rgb,
        cursor_text: ?Terminal.Rgb,
        reverse_screen: bool,
    };

    fn defaultPresentation() Presentation {
        const colors = TerminalColorState{};
        return .{
            .palette = colors.palette,
            .foreground = colors.foreground,
            .background = colors.background,
            .cursor = null,
            .cursor_text = null,
            .reverse_screen = false,
        };
    }

    /// Copies host-facing viewport dimensions, cursor, history, and active-screen facts.
    pub const VisibleMeta = struct {
        rows: u16,
        cols: u16,
        history_count: u32,
        is_alternate_screen: bool,
        snapshot_seq: u64,
        dirty_generation: u64,
    };

    /// Returns the active G0, G1, and GL charset selection for DECCIR reporting.
    pub fn deccirCharsetState(self: *const Terminal) parser_mod.DeccirCharsetState {
        return .{
            .gl_index = self.gl_index,
            .g0_designation = self.designations[0],
            .g1_designation = self.designations[1],
        };
    }
};

fn validateDimensions(rows: u16, cols: u16) error{InvalidDimensions}!void {
    if (rows == 0 or cols == 0) return error.InvalidDimensions;
}

fn isKeyFormatResource(resource: u8) bool {
    return resource <= 4 or resource == 6 or resource == 7;
}

comptime {
    const maximum_cell_count =
        @as(u64, std.math.maxInt(u16)) * @as(u64, std.math.maxInt(u16));
    std.debug.assert(maximum_cell_count <= std.math.maxInt(u32));
    std.debug.assert(maximum_cell_count <= std.math.maxInt(usize));
}

test "terminal scroll viewport owns bottom intent" {
    var vt = try Terminal.initWithHistory(std.testing.allocator, 3, 5, 8);
    defer vt.deinit();

    const feed = try vt.feed("1AAAA\r\n2BBBB\r\n3CCCC\r\n4DDDD");
    try std.testing.expect(feed.state_changed);
    try std.testing.expect(vt.visibleHistoryCount() > 0);
    try std.testing.expect(vt.scrollViewport(.top));
    try std.testing.expect(vt.scrollback_offset > 0);
    try std.testing.expect(vt.scrollViewport(.bottom));
    try std.testing.expectEqual(@as(u32, 0), vt.scrollback_offset);
    try std.testing.expect(!vt.scrollViewport(.bottom));
}

test "terminal feed preserves scrolled viewport as history grows" {
    var vt = try Terminal.initWithHistory(std.testing.allocator, 3, 5, 8);
    defer vt.deinit();

    const initial_feed = try vt.feed("1AAAA\r\n2BBBB\r\n3CCCC\r\n4DDDD");
    try std.testing.expect(initial_feed.state_changed);
    try std.testing.expect(vt.scrollViewport(.{ .absolute = 1 }));
    const before = vt.surfaceSnapshot().snapshot.view.cellAt(0, 0);
    const offset_before = vt.scrollback_offset;

    const append_feed = try vt.feed("\r\n5EEEE");
    try std.testing.expect(append_feed.state_changed);

    try std.testing.expect(vt.scrollback_offset > offset_before);
    try std.testing.expectEqual(before, vt.surfaceSnapshot().snapshot.view.cellAt(0, 0));
}

test "history allocation failures publish loss and preserve paired state" {
    inline for (0..4) |fail_offset| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        var screen = try Screen.initWithCellsAndHistory(failing.allocator(), 1, 2, 4);
        defer screen.deinit(failing.allocator());
        screen.writeText("x");
        failing.fail_index = failing.alloc_index + fail_offset;

        screen.storeHistoryRow(0);
        try std.testing.expect(failing.has_induced_failure);
        try std.testing.expectEqual(@as(u64, 1), screen.history_loss_generation);
        try std.testing.expectEqual(@as(u32, 0), screen.history_count);
        try std.testing.expectEqual(@as(usize, 0), screen.history_lines.items.len);
        try std.testing.expect(screen.open_history_line == null);

        failing.fail_index = std.math.maxInt(usize);
        screen.storeHistoryRow(0);
        try std.testing.expectEqual(@as(u64, 1), screen.history_loss_generation);
        try std.testing.expectEqual(@as(u32, 1), screen.history_count);
        try std.testing.expectEqual(@as(usize, 1), screen.history_lines.items.len);
    }
}

test "history clone allocation failure preserves the open wrapped line" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var screen = try Screen.initWithCellsAndHistory(failing.allocator(), 1, 2, 4);
    defer screen.deinit(failing.allocator());
    screen.writeText("x");
    screen.setRowWrapped(0, true);
    screen.storeHistoryRow(0);
    const open_len = screen.open_history_line.?.cells.items.len;
    const projected_count = screen.history_count;
    failing.fail_index = failing.alloc_index;

    screen.storeHistoryRow(0);
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectEqual(@as(u64, 1), screen.history_loss_generation);
    try std.testing.expectEqual(projected_count, screen.history_count);
    try std.testing.expectEqual(open_len, screen.open_history_line.?.cells.items.len);

    failing.fail_index = std.math.maxInt(usize);
    screen.storeHistoryRow(0);
    try std.testing.expectEqual(projected_count + 1, screen.history_count);
    try std.testing.expectEqual(open_len * 2, screen.open_history_line.?.cells.items.len);
}

test "feed summary and surface publish dropped history" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var terminal = try Terminal.initWithHistory(failing.allocator(), 1, 2, 4);
    defer terminal.deinit();
    failing.fail_index = failing.alloc_index;

    const dropped = try terminal.feed("\x1b[S");
    try std.testing.expect(dropped.state_changed);
    try std.testing.expect(dropped.history_lost);
    try std.testing.expectEqual(
        @as(u64, 1),
        terminal.surfaceSnapshot().history_loss_generation,
    );

    failing.fail_index = std.math.maxInt(usize);
    const retained = try terminal.feed("\x1b[S");
    try std.testing.expect(!retained.history_lost);
    try std.testing.expectEqual(
        @as(u64, 1),
        terminal.surfaceSnapshot().history_loss_generation,
    );
}

test "terminal publishes every bounded bell and remains reusable" {
    var vt = try Terminal.init(std.testing.allocator, 2, 2);
    defer vt.deinit();

    const first = try vt.feed("\x07");
    try std.testing.expect(first.state_changed);
    try std.testing.expectEqual(@as(u64, 1), vt.surfaceSnapshot().bell_generation);

    const second = try vt.feed("\x07x");
    try std.testing.expect(second.state_changed);
    const publication = vt.surfaceSnapshot();
    try std.testing.expectEqual(@as(u64, 2), publication.bell_generation);
    try std.testing.expectEqual(@as(u21, 'x'), publication.snapshot.view.cellAt(0, 0));

    vt.host.bell_generation = std.math.maxInt(u64);
    try std.testing.expectError(error.ConsequenceLimit, vt.feed("\x07"));
    try std.testing.expectEqual(std.math.maxInt(u64), vt.host.bell_generation);
    vt.host.bell_generation = 2;
    const reused = try vt.feed("y");
    try std.testing.expect(reused.state_changed);
    try std.testing.expectEqual(@as(u21, 'y'), vt.surfaceSnapshot().snapshot.view.cellAt(0, 1));
}

test "logical output aggregate evicts whole lines and preserves exact cursor loss" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 2, 2, 4);
    defer terminal.deinit();
    const line_bytes = logical_output_bytes_max / 2 + 1;
    const first = try std.testing.allocator.alloc(u8, line_bytes);
    @memset(first, 'a');
    terminal.screen_state.primary.retainOutputText(std.testing.allocator, first) catch |failure| {
        std.testing.allocator.free(first);
        return failure;
    };
    const second = try std.testing.allocator.alloc(u8, line_bytes);
    @memset(second, 'b');
    terminal.screen_state.primary.retainOutputText(std.testing.allocator, second) catch |failure| {
        std.testing.allocator.free(second);
        return failure;
    };

    const range = terminal.logicalOutputRange();
    try std.testing.expectEqual(@as(u64, 2), range.oldest);
    try std.testing.expectEqual(@as(u64, 2), range.newest);
    try std.testing.expectEqual(line_bytes, terminal.screen_state.primary.output_bytes);
    switch (try terminal.copyLogicalOutput(std.testing.allocator, 0, 1, logical_output_bytes_max)) {
        .cursor_stale => |oldest| try std.testing.expectEqual(range.oldest, oldest),
        else => return error.UnexpectedOutputResult,
    }
}

test "logical output accepts the maximum copyable line" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 2, 2, 2);
    defer terminal.deinit();
    const maximum = try std.testing.allocator.alloc(u8, logical_output_line_bytes_max);
    @memset(maximum, 'x');
    terminal.screen_state.primary.retainOutputText(std.testing.allocator, maximum) catch |failure| {
        std.testing.allocator.free(maximum);
        return failure;
    };
    terminal.screen_state.primary.writeText("open");

    var copied = switch (try terminal.copyLogicalOutput(
        std.testing.allocator,
        0,
        1,
        logical_output_bytes_max,
    )) {
        .output => |output| output,
        else => return error.UnexpectedOutputResult,
    };
    defer copied.deinit();
    try std.testing.expectEqual(logical_output_line_bytes_max, copied.text.len);
    try std.testing.expectEqual(@as(u64, 1), copied.cursor);
    try std.testing.expectEqual(@as(usize, 0), copied.losses.len);
    try std.testing.expect(copied.open_line_omitted);
    try std.testing.expectEqual(@as(usize, 0), copied.open_line.len);
    try std.testing.expectError(
        error.InvalidLimit,
        terminal.copyLogicalOutput(std.testing.allocator, 1, 1, logical_output_bytes_max + 1),
    );
}

const CursorSavepoint = struct {
    row: u16 = 0,
    col: u16 = 0,
    style: Screen.CursorStyle = Screen.default_cursor_style,
};

// Stores cursor, rendition, charset, origin, and wrap state for one screen-bank save slot.
const Savepoint = struct {
    valid: bool = false,
    cursor: CursorSavepoint = .{},
    current_attrs: Screen.CellAttrs = Screen.default_cell_attrs,
    reverse_screen_mode: bool = false,
    origin_mode: bool = false,
    auto_wrap: bool = true,
    wrap_pending: bool = false,
    gl_index: u8 = 0,
    gr_index: u8 = 1,
    designations: [4]u8 = .{ 'B', 'B', 'B', 'B' },

    /// Returns the savepoint to default cursor and charset state.
    pub fn clear(self: *Savepoint) void {
        self.* = .{};
    }
};
