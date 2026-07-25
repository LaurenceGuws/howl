//! Owns screen-bank cells, cursor, margins, history, reflow, and SGR state.

const std = @import("std");

const logical_output_line_bytes_max: usize = 1024 * 1024;

const ParsedTextSize = struct {
    text: []const u8,
    scale: u8 = 1,
    width: u8 = 0,
    subscale_n: u4 = 0,
    subscale_d: u4 = 0,
    vertical_align: u2 = 0,
    horizontal_align: u2 = 0,
};

fn parseTextSize(payload: []const u8) ?ParsedTextSize {
    const separator = std.mem.indexOfScalar(u8, payload, ';') orelse return null;
    var result = ParsedTextSize{ .text = payload[separator + 1 ..] };
    var fields = std.mem.splitScalar(u8, payload[0..separator], ':');
    while (fields.next()) |field| {
        if (field.len == 0) continue;
        if (field.len < 3 or field[1] != '=') return null;
        const value = parseTextSizeNumber(field[2..]) orelse return null;
        switch (field[0]) {
            's' => result.scale = @intCast(@max(1, @min(value, 7))),
            'w' => result.width = @intCast(@min(value, 7)),
            'n' => result.subscale_n = @intCast(@min(value, 15)),
            'd' => result.subscale_d = @intCast(@min(value, 15)),
            'v' => result.vertical_align = @intCast(@min(value, 3)),
            'h' => result.horizontal_align = @intCast(@min(value, 3)),
            else => return null,
        }
    }
    if (!std.unicode.utf8ValidateSlice(result.text)) return null;
    return result;
}

fn parseTextSizeNumber(bytes: []const u8) ?u32 {
    if (bytes.len == 0 or bytes.len > 10) return null;
    var value: u64 = 0;
    for (bytes) |byte| {
        if (byte < '0' or byte > '9') return null;
        value = value * 10 + byte - '0';
        if (value > std.math.maxInt(u32)) return null;
    }
    return @intCast(value);
}

fn isIgnoredSizedTextCodepoint(cp: u21) bool {
    return cp < 0x20 or (cp >= 0x7f and cp <= 0x9f);
}

// Validates the bounded current cell payload before any terminal mutation.
fn validateSizedText(parsed: ParsedTextSize) bool {
    var iterator = std.unicode.Utf8View.initUnchecked(parsed.text).iterator();
    var cluster_len: u8 = 0;
    var cluster_count: usize = 0;
    while (iterator.nextCodepoint()) |cp| {
        if (isIgnoredSizedTextCodepoint(cp)) continue;
        if (parsed.width == 0 and cluster_len != 0 and !isTrailingCombiningCodepoint(cp)) {
            cluster_count += 1;
            cluster_len = 0;
        }
        if (cluster_len == 4) return false;
        cluster_len += 1;
    }
    if (cluster_len != 0) cluster_count += 1;
    return cluster_count != 0 and (parsed.width == 0 or cluster_count == 1);
}

/// Terminal screen state for cursor, cells, margins, and history.
pub const Screen = struct {
    /// Maximum aggregate bytes retained across finalized logical-output lines.
    pub const retained_output_bytes_max: usize = 1024 * 1024;

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
    /// Provides the canonical blank terminal cell.
    pub const default_cell = blank_cell;
    /// Describes one row's DEC presentation geometry without prescribing host rendering.
    pub const LineGeometry = enum(u2) {
        single_width,
        double_width,
        double_height_top,
        double_height_bottom,
    };
    /// Finite terminal-semantic mutations owned directly by one screen bank.
    pub const Action = union(enum) {
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
        line_feed,
        next_line,
        carriage_return,
        backspace,
        horizontal_tab,
        horizontal_tab_forward: u16,
        horizontal_tab_back: u16,
        horizontal_tab_set,
        tab_clear_current,
        tab_clear_all,
        reset_default_tab_stops,
        cursor_visible: bool,
        cursor_style: CursorStyleCommand,
        cursor_shape: Screen.CursorShape,
        cursor_color: ?Screen.Rgb,
        cursor_text_color: ?Screen.Rgb,
        auto_wrap: bool,
        origin_mode: bool,
        insert_mode: bool,
        left_right_margin_mode: bool,
        hard_reset,
    };
    /// Borrows SGR values and records semantic colon adjacency independently
    /// of parser storage.
    pub const SgrOperands = struct {
        /// Maximum values and separator positions accepted by Screen SGR.
        pub const capacity: usize = @bitSizeOf(u32);

        values: []const i32,
        colon_after: u32 = 0,

        fn colonAfter(self: SgrOperands, index: u8) bool {
            if (index >= capacity) return false;
            return self.colon_after & (@as(u32, 1) << @intCast(index)) != 0;
        }
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
            .tab_stops = tab_stops,
            .cell_pixel_size = null,
        };
    }

    /// Initialize cursor-only grid state.
    pub fn init(rows: u16, cols: u16) Screen {
        return initWithDefaultCursorStyle(rows, cols, initial_cursor_style);
    }

    fn initWithDefaultCursorStyle(rows: u16, cols: u16, cursor_style_default: CursorStyle) Screen {
        return initBase(null, rows, cols, cursor_style_default, null, null, null, null, 0, null);
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
        for (lines.logical_lines.items) |*line| {
            for (line.cells.items) |*cell| {
                if (cell.width != 1 or cell.height != 1 or cell.x != 0 or cell.y != 0)
                    cell.* = blank_cell;
            }
        }

        var reflow = try reflowLogicalLines(allocator, lines, cols);
        defer reflow.deinit(allocator);

        const projection = projectViewport(screenCount32(lines.logical_lines.items.len), reflow, rows);
        var buffers = try allocResizeBuffers(allocator, rows, cols, self.tab_stops);
        errdefer buffers.deinit(allocator);

        copyVisibleRows(&buffers, reflow, projection, cols);
        var replacement = self.replacementBase(allocator);
        replacement.installResizeState(rows, cols, buffers.take());
        errdefer replacement.deinit(allocator);
        try replacement.cloneOutputAuthority(allocator, self);
        try replacement.rebuildResizeAuthority(allocator, lines, reflow, projection, cols);
        replacement.restoreResizeCursor(rows, cols, reflow, projection);
        return replacement;
    }

    fn replacementBase(self: *const Screen, allocator: std.mem.Allocator) Screen {
        var replacement = self.*;
        replacement.allocator = allocator;
        replacement.cells = null;
        replacement.row_flags = null;
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

        std.debug.assert(self.rows == rows);
        std.debug.assert(self.cols == cols);
        std.debug.assert((self.cells != null) == (rows > 0 and cols > 0));
        std.debug.assert((self.row_flags != null) == (rows > 0));
        std.debug.assert((self.tab_stops != null) == (cols > 0));
        if (self.cells) |buf| std.debug.assert(buf.len == cellCount(rows, cols));
        if (self.row_flags) |buf| std.debug.assert(buf.len == rows);
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
        projection: ResizeProjection,
        cols: u16,
    ) std.mem.Allocator.Error!void {
        std.debug.assert(reflow.line_row_starts.items.len == lines.logical_lines.items.len);
        std.debug.assert(reflow.line_row_counts.items.len == lines.logical_lines.items.len);
        std.debug.assert(projection.total_rows == screenCount32(reflow.rewrapped.items.len));
        std.debug.assert(projection.first_visible_line <= screenCount32(lines.logical_lines.items.len));
        if (projection.first_visible_line < screenCount32(lines.logical_lines.items.len)) {
            std.debug.assert(
                projection.hidden_rows_in_first_visible_line <
                    reflow.line_row_counts.items[@intCast(projection.first_visible_line)],
            );
        } else {
            std.debug.assert(projection.hidden_rows_in_first_visible_line == 0);
        }

        try self.replaceHistoryAuthority(
            allocator,
            lines.logical_lines.items,
            reflow.line_row_starts.items,
            reflow.line_row_counts.items,
            projection.first_visible_line,
            projection.hidden_rows_in_first_visible_line,
            reflow.rewrapped.items,
            cols,
        );
        try self.installResizeProjection(allocator, reflow, projection);
    }

    fn installResizeProjection(
        self: *Screen,
        allocator: std.mem.Allocator,
        reflow: ReflowState,
        projection: ResizeProjection,
    ) std.mem.Allocator.Error!void {
        self.history_count = 0;
        self.history_write_idx = 0;
        if (self.history_capacity == 0 or self.cols == 0) return;

        const kept_complete_start = projection.first_visible_line -| self.history_capacity;
        const first_projected_row = if (kept_complete_start < screenCount32(reflow.line_row_starts.items.len))
            reflow.line_row_starts.items[@intCast(kept_complete_start)]
        else
            projection.visible_start;
        std.debug.assert(first_projected_row <= projection.visible_start);
        std.debug.assert(projection.visible_start <= screenCount32(reflow.rewrapped.items.len));

        var row_index = first_projected_row;
        while (row_index < projection.visible_start) : (row_index += 1) {
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

    fn restoreResizeCursor(self: *Screen, rows: u16, cols: u16, reflow: ReflowState, projection: ResizeProjection) void {
        if (rows == 0 or cols == 0 or projection.total_rows == 0) {
            self.cursor.setPositionStructural(0, 0);
            self.wrap_pending = false;
            std.debug.assert(self.cursor.row == 0);
            std.debug.assert(self.cursor.col == 0);
            std.debug.assert(self.wrap_pending == false);
            return;
        }

        const last_visible_row = projection.visible_start + projection.visible_rows_kept - 1;
        const clamped_cursor_row = std.math.clamp(reflow.global_cursor_row, projection.visible_start, last_visible_row);
        const cursor_row: u16 = @intCast(clamped_cursor_row - projection.visible_start);
        self.cursor.setPositionStructural(
            cursor_row,
            @min(reflow.global_cursor_col, self.lineRightBoundary(cursor_row)),
        );
        self.wrap_pending = reflow.next_wrap_pending and
            self.cursor.row < rows and self.cursor.col == self.lineRightBoundary(self.cursor.row);

        std.debug.assert(projection.visible_rows_kept > 0);
        std.debug.assert(clamped_cursor_row >= projection.visible_start);
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

    /// Finalizes the primary screen's current logical output line.
    pub fn finalizeOutputLine(
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
    // retained only after leaving the projection, while output identity belongs
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
            value.retainedBytes() > Screen.retained_output_bytes_max - self.output_bytes)
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
        std.debug.assert(self.output_bytes <= Screen.retained_output_bytes_max);
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

    /// Clone retained, open, and visible content into one allocator-owned logical snapshot.
    ///
    /// Allocation failure releases partial clones and leaves this Screen unchanged.
    fn collectLogicalSnapshot(
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
        if (self.cells) |c| @memset(c, blank_cell);
        if (self.row_flags) |buf| @memset(buf, 0);
        if (self.tab_stops) |stops| setDefaultTabStops(stops);
    }

    // Applies DECSTR's bank-local defaults without erasing cells or moving the cursor.
    /// Resets soft terminal state while preserving cells and retained history.
    pub fn softReset(self: *Screen) bool {
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

    /// Borrows one visible row from this screen bank.
    pub fn visibleRowCells(self: *const Screen, row: u16) []const Cell {
        std.debug.assert(row < self.rows);
        const cells = self.cells orelse unreachable;
        const start: usize = @intCast(self.rowStart(row));
        return cells[start..][0..self.cols];
    }

    /// Borrows one retained history row by newest-first recency.
    pub fn historyRowCells(self: *const Screen, history_idx: u32) []const Cell {
        std.debug.assert(history_idx < self.history_count);
        const cells = self.history orelse unreachable;
        const slot = self.historySlotForRecency(history_idx) orelse unreachable;
        const start: usize = @intCast(slot * @as(u32, self.cols));
        return cells[start..][0..self.cols];
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

    /// Apply one routed screen mutation request to this Screen.
    pub fn applyScreen(self: *Screen, event: Screen.Action) void {
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
            .write_text, .write_codepoint => self.applyRetainedState(event),
            .line_feed,
            .next_line,
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
            .left_right_margin_mode,
            => self.applyScreenState(event),
            .hard_reset => self.applyLineEdit(event),
        }
    }

    fn applyCursorMove(self: *Screen, event: Screen.Action) void {
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
    /// Applies one cursor-motion action and reports semantic change.
    pub fn moveCursor(self: *Screen, event: Screen.Action) bool {
        const cursor_before = self.cursor;
        const wrap_before = self.wrap_pending;
        self.applyCursorMove(event);
        return !std.meta.eql(cursor_before, self.cursor) or wrap_before != self.wrap_pending;
    }

    fn applyRetainedState(self: *Screen, event: Screen.Action) void {
        switch (event) {
            .write_text => |text| self.writeText(text),
            .write_codepoint => |codepoint| self.writeCell(codepoint),
            else => unreachable,
        }
    }

    fn applyFlowMove(self: *Screen, event: Screen.Action) void {
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
            .carriage_return => self.cursor.setColByClient(0),
            .backspace => self.applyBackspace(false),
            .horizontal_tab => self.horizontalTabForward(1),
            .horizontal_tab_forward => |count| self.horizontalTabForward(count),
            .horizontal_tab_back => |count| self.horizontalTabBack(count),
            else => unreachable,
        }
    }

    fn applyTabState(self: *Screen, event: Screen.Action) void {
        switch (event) {
            .horizontal_tab_set => self.setTabStop(),
            .tab_clear_current => self.clearCurrentTabStop(),
            .tab_clear_all => self.clearAllTabStops(),
            .reset_default_tab_stops => self.resetDefaultTabStops(),
            else => unreachable,
        }
    }

    // Applies iTerm2's reverse-wrap policy to one C0 BS and reports exact cursor or phantom mutation.
    /// Applies backspace with the terminal-selected reverse-wrap mode.
    pub fn backspace(self: *Screen, reverse_wraparound: bool) bool {
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

    fn applyScreenState(self: *Screen, event: Screen.Action) void {
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
            .left_right_margin_mode => |enabled| {
                if (self.setLeftRightMarginMode(enabled)) return;
            },
            else => unreachable,
        }
    }

    fn applyLineEdit(self: *Screen, event: Screen.Action) void {
        switch (event) {
            .hard_reset => self.reset(),
            else => unreachable,
        }
    }

    /// Resolved inclusive physical bounds for one rectangular operation.
    pub const RectBounds = struct {
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
            changed = true;
        }
        return changed;
    }

    /// Cancels latent autowrap and reports whether it was pending.
    pub fn cancelPendingWrap(self: *Screen) bool {
        const changed = self.wrap_pending;
        self.wrap_pending = false;
        return changed;
    }

    // Row continuation is published metadata, so changing it dirties the complete row.
    fn clearRowContinuation(self: *Screen, row: u16) bool {
        if (!self.rowWrapped(row)) return false;
        self.setRowWrapped(row, false);
        return true;
    }

    /// Set the hyperlink identity copied into subsequent cells and report exact mutation.
    /// Selects the hyperlink identity stored by subsequent cells.
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
    /// Clears the visible grid without discarding retained history.
    pub fn clearVisibleCells(self: *Screen) void {
        if (self.cells) |cells| @memset(cells, blank_cell);
        if (self.row_flags) |flags| @memset(flags, 0);
    }

    /// Moves the alternate-screen cursor to origin and clears pending wrap.
    pub fn resetCursorForAltEntry(self: *Screen) void {
        self.cursor.resetForAltEntry();
        self.wrap_pending = false;
        self.current_attrs = initial_cell_attrs;
    }

    /// Return the active horizontal editing boundary on the left.
    /// Returns the effective left margin for cursor motion.
    pub fn leftBoundary(self: *const Screen) u16 {
        return if (self.left_right_margin_mode) self.left_margin else 0;
    }

    /// Return the active horizontal editing boundary on the right.
    /// Returns the effective right margin for cursor motion.
    pub fn rightBoundary(self: *const Screen) u16 {
        return if (self.left_right_margin_mode)
            @min(self.right_margin, self.lineRightBoundary(self.cursor.row))
        else
            self.lineRightBoundary(self.cursor.row);
    }

    /// Returns the effective right boundary for one physical row.
    pub fn lineRightBoundary(self: *const Screen, row: u16) u16 {
        return self.lineColumnCount(row) -| 1;
    }

    fn setCursorRowClamped(self: *Screen, row: u16) void {
        self.cursor.setPositionByClient(row, @min(self.cursor.col, self.lineRightBoundary(row)));
    }

    /// Clears retained scrollback while preserving the visible grid.
    pub fn clearScrollback(self: *Screen) bool {
        const allocator = self.allocator orelse return false;
        const changed = self.history_count != 0 or self.history_lines.items.len != 0 or self.open_history_line != null;
        self.history_row_base += self.history_count;
        self.clearHistoryAuthority(allocator);
        self.history_count = 0;
        self.history_write_idx = 0;
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

    /// Select ISO, DEC, or unprotected provenance for subsequently written cells.
    /// Returns false when the retained protection fact is already identical.
    pub fn setCharacterProtection(self: *Screen, protection: Protection) bool {
        if (self.current_attrs.protected == protection) return false;
        self.current_attrs.protected = protection;
        return true;
    }

    /// Select rectangular or stream extent for subsequent rectangle-attribute changes.
    /// Returns false when the retained extent fact is already identical.
    pub fn setRectAttrExtent(self: *Screen, rectangular: bool) bool {
        if (self.attr_change_extent_rect == rectangular) return false;
        self.attr_change_extent_rect = rectangular;
        return true;
    }

    /// Change attributes in the clipped rectangle using rectangular or stream extent.
    /// Returns exact cell-attribute or pending-wrap mutation.
    pub fn changeRectAttrs(self: *Screen, area: RectArea, attrs: []const u16, reverse: bool) bool {
        var changed = self.cancelPendingWrap();
        const cells = self.cells orelse return changed;
        if (attrs.len == 0) return changed;
        const bounds = self.rectBounds(area) orelse return changed;
        changed = self.clearClustersIntersecting(
            bounds.top,
            bounds.bottom + 1,
            bounds.left,
            bounds.right + 1,
        ) or changed;
        var row = bounds.top;
        while (row <= bounds.bottom) : (row += 1) {
            const row_start = self.rowStart(row);
            const start_col = if (self.attr_change_extent_rect or row == bounds.top) bounds.left else 0;
            const end_col = if (self.attr_change_extent_rect or row == bounds.bottom) bounds.right else self.cols -| 1;
            var col = start_col;
            while (col <= end_col) : (col += 1) {
                const idx = row_start + @as(u32, col);
                if (applyRectAttrOps(&cells[@intCast(idx)].attrs, attrs, reverse)) {
                    changed = true;
                }
            }
        }
        return changed;
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
    /// Returns exact cell or pending-wrap mutation.
    pub fn fillRect(self: *Screen, area: RectArea, codepoint: u21) bool {
        var changed = self.cancelPendingWrap();
        const cells = self.cells orelse return changed;
        const bounds = self.rectBounds(area) orelse return changed;
        changed = self.clearClustersIntersecting(
            bounds.top,
            bounds.bottom + 1,
            bounds.left,
            bounds.right + 1,
        ) or changed;
        const fill = Cell{ .codepoint = codepoint, .attrs = self.current_attrs };
        var row = bounds.top;
        while (row <= bounds.bottom) : (row += 1) {
            const start = self.rowStart(row);
            var col = bounds.left;
            while (col <= bounds.right) : (col += 1) {
                const cell = &cells[start + col];
                if (std.meta.eql(cell.*, fill)) continue;
                cell.* = fill;
                changed = true;
            }
        }
        return changed;
    }

    /// Copy one clipped page-one rectangle in overlap-safe row and column order.
    ///
    /// Unsupported pages and missing storage leave the destination unchanged.
    /// Returns exact destination-cell or pending-wrap mutation.
    pub fn copyRect(self: *Screen, request: RectCopy) bool {
        var changed = self.cancelPendingWrap();
        const cells = self.cells orelse return changed;
        if (request.source_page != 1 or request.dest_page != 1) return changed;
        const source = self.rectBounds(request.area) orelse return changed;
        const origin = self.activeOriginBounds();
        const dest_top = origin.top + @min(request.dest_top, origin.bottom - origin.top);
        const dest_left = origin.left + @min(request.dest_left, origin.right - origin.left);
        const height: u16 = source.bottom - source.top + 1;
        const width: u16 = source.right - source.left + 1;
        const copy_height = @min(height, origin.bottom - dest_top + 1);
        const copy_width = @min(width, origin.right - dest_left + 1);
        if (copy_height == 0 or copy_width == 0) return changed;
        var source_row = source.top;
        while (source_row < source.top + copy_height) : (source_row += 1) {
            var source_col = source.left;
            while (source_col < source.left + copy_width) : (source_col += 1) {
                const source_cell = cells[@intCast(self.rowStart(source_row) + source_col)];
                if (source_cell.width != 1 or source_cell.height != 1 or
                    source_cell.x != 0 or source_cell.y != 0)
                    return changed;
            }
        }
        changed = self.clearClustersIntersecting(
            dest_top,
            dest_top + copy_height,
            dest_left,
            dest_left + copy_width,
        ) or changed;

        var copied_rows: u16 = 0;
        while (copied_rows < copy_height) : (copied_rows += 1) {
            const row = if (dest_top > source.top) copy_height - copied_rows - 1 else copied_rows;
            const source_start = self.rowStart(source.top + row) + source.left;
            const dest_start = self.rowStart(dest_top + row) + dest_left;
            const source_cells = cells[@intCast(source_start)..@intCast(source_start + copy_width)];
            const dest_cells = cells[@intCast(dest_start)..@intCast(dest_start + copy_width)];
            for (dest_cells, source_cells) |dest, source_cell| {
                if (std.meta.eql(dest, source_cell)) continue;
                changed = true;
            }
            if (dest_start > source_start) {
                std.mem.copyBackwards(Cell, dest_cells, source_cells);
            } else {
                std.mem.copyForwards(Cell, dest_cells, source_cells);
            }
        }
        return changed;
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
    /// Returns exact cell, continuation, or pending-wrap mutation.
    pub fn insertChars(self: *Screen, count: u16) bool {
        var changed = self.cancelPendingWrap();
        if (self.rows == 0 or self.cols == 0) return changed;
        if (self.cursor.col >= self.cols) return changed;
        if (!self.cursorWithinHorizontalMargins()) return changed;

        const amount = @min(@max(count, 1), self.rightBoundary() - self.cursor.col + 1);
        changed = self.clearClustersIntersecting(
            self.cursor.row,
            self.cursor.row + 1,
            self.cursor.col,
            self.rightBoundary() + 1,
        ) or changed;
        const row = self.rowCells(self.cursor.row) orelse return changed;
        const src_col = screenColCount(self.cursor.col);
        const dst_col = src_col + screenColCount(amount);
        const move_len = screenColCount(self.rightBoundary() + 1) - dst_col;

        std.debug.assert(src_col <= dst_col);
        std.debug.assert(dst_col <= screenColCount(self.rightBoundary() + 1));
        std.debug.assert(dst_col + move_len == screenColCount(self.rightBoundary() + 1));
        std.debug.assert(src_col + move_len <= row.len);
        std.debug.assert(dst_col + move_len <= row.len);
        std.debug.assert(src_col + screenColCount(amount) <= row.len);

        const erase = self.eraseCell();
        var cells_changed = false;
        var col = src_col;
        const end = screenColCount(self.rightBoundary() + 1);
        while (col < end) : (col += 1) {
            const replacement = if (col < dst_col) erase else row[@intCast(col - screenColCount(amount))];
            if (!std.meta.eql(row[@intCast(col)], replacement)) cells_changed = true;
        }
        if (move_len > 0) {
            std.mem.copyBackwards(
                Cell,
                row[@intCast(dst_col)..@intCast(dst_col + move_len)],
                row[@intCast(src_col)..@intCast(src_col + move_len)],
            );
        }
        @memset(row[@intCast(src_col)..@intCast(src_col + screenColCount(amount))], erase);
        cells_changed = self.clearRowContinuation(self.cursor.row) or cells_changed;
        return cells_changed or changed;
    }

    /// Delete at least one cell at the cursor within the right boundary.
    /// Returns exact cell, continuation, or pending-wrap mutation.
    pub fn deleteChars(self: *Screen, count: u16) bool {
        var changed = self.cancelPendingWrap();
        if (self.rows == 0 or self.cols == 0) return changed;
        if (self.cursor.col >= self.cols) return changed;
        if (!self.cursorWithinHorizontalMargins()) return changed;

        const amount = @min(@max(count, 1), self.rightBoundary() - self.cursor.col + 1);
        changed = self.clearClustersIntersecting(
            self.cursor.row,
            self.cursor.row + 1,
            self.cursor.col,
            self.rightBoundary() + 1,
        ) or changed;
        const row = self.rowCells(self.cursor.row) orelse return changed;
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

        const erase = self.eraseCell();
        var cells_changed = false;
        var col = dst_col;
        while (col < tail_end) : (col += 1) {
            const replacement = if (col < tail_start) row[@intCast(col + screenColCount(amount))] else erase;
            if (!std.meta.eql(row[@intCast(col)], replacement)) cells_changed = true;
        }
        if (move_len > 0) {
            std.mem.copyForwards(
                Cell,
                row[@intCast(dst_col)..@intCast(dst_col + move_len)],
                row[@intCast(src_col)..@intCast(src_col + move_len)],
            );
        }
        @memset(row[@intCast(tail_start)..@intCast(tail_end)], erase);
        cells_changed = self.clearRowContinuation(self.cursor.row) or cells_changed;
        return cells_changed or changed;
    }

    fn insertColumnsInRow(self: *Screen, row: u16, count: u16) bool {
        const line_cols = self.lineColumnCount(row);
        const line_right = line_cols - 1;
        const right = if (self.left_right_margin_mode) @min(self.right_margin, line_right) else line_right;
        if (self.cursor.col > right) return false;
        const amount = @min(@max(count, 1), right - self.cursor.col + 1);
        var changed = self.clearClustersIntersecting(row, row + 1, self.cursor.col, right + 1);
        const amount_cols = screenColCount(amount);
        const cells = self.rowCells(row) orelse return false;
        const cursor_col = screenColCount(self.cursor.col);
        const dst_col = cursor_col + amount_cols;
        const end = screenColCount(right + 1);
        const move_len = end - dst_col;
        const erase = self.eraseCell();
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
        return changed;
    }

    fn deleteColumnsInRow(self: *Screen, row: u16, count: u16) bool {
        const line_cols = self.lineColumnCount(row);
        const line_right = line_cols - 1;
        const right = if (self.left_right_margin_mode) @min(self.right_margin, line_right) else line_right;
        if (self.cursor.col > right) return false;
        const amount = @min(@max(count, 1), right - self.cursor.col + 1);
        var changed = self.clearClustersIntersecting(row, row + 1, self.cursor.col, right + 1);
        const amount_cols = screenColCount(amount);
        const cells = self.rowCells(row) orelse return false;
        const cursor_col = screenColCount(self.cursor.col);
        const end = screenColCount(right + 1);
        const src_col = cursor_col + amount_cols;
        const move_len = end - src_col;
        const tail_start = end - amount_cols;
        const erase = self.eraseCell();
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
        return changed;
    }

    fn shiftRowLeft(self: *Screen, row: u16, count: u16, left: u16, right: u16) bool {
        if (left > right or right >= self.cols) return false;

        var changed = self.clearClustersIntersecting(row, row + 1, left, right + 1);
        const width = right - left + 1;
        const amount = @min(@max(count, 1), width);
        const cells = self.rowCells(row) orelse return false;
        const left_idx = screenColCount(left);
        const move_len = screenColCount(width - amount);
        const end = left_idx + screenColCount(width);
        const erase = self.eraseCell();
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
        return changed;
    }

    fn shiftRowRight(self: *Screen, row: u16, count: u16, left: u16, right: u16) bool {
        if (left > right or right >= self.cols) return false;

        var changed = self.clearClustersIntersecting(row, row + 1, left, right + 1);
        const width = right - left + 1;
        const amount = @min(@max(count, 1), width);
        const cells = self.rowCells(row) orelse return false;
        const left_idx = screenColCount(left);
        const move_len = screenColCount(width - amount);
        const amount_cols = screenColCount(amount);
        const end = left_idx + screenColCount(width);
        const erase = self.eraseCell();
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
    pub fn repeatPreceding(self: *Screen, count: u16) bool {
        const graphic = self.last_graphic orelse return false;
        var remaining = @max(count, 1);
        while (remaining > 0) : (remaining -= 1) {
            self.writeCell(graphic.codepoint);
            for (graphic.combining[0..graphic.combining_len]) |cp| self.writeCell(cp);
        }
        return true;
    }

    // Applies one validated OSC 66 payload as fixed bounded cell clusters.
    /// Applies one validated OSC 66 sized-text payload.
    pub fn writeSizedText(self: *Screen, payload: []const u8) bool {
        const parsed = parseTextSize(payload) orelse return false;
        if (!validateSizedText(parsed)) return false;
        var changed = false;
        var iterator = std.unicode.Utf8View.initUnchecked(parsed.text).iterator();
        if (parsed.width != 0) {
            var scalars: [4]u21 = undefined;
            var count: u8 = 0;
            while (iterator.nextCodepoint()) |cp| {
                if (isIgnoredSizedTextCodepoint(cp)) continue;
                scalars[count] = @intCast(cp);
                count += 1;
            }
            if (count != 0) changed = self.writeSizedCluster(parsed, scalars[0..count], parsed.width);
            return changed;
        }

        var scalars: [4]u21 = undefined;
        var count: u8 = 0;
        while (iterator.nextCodepoint()) |cp| {
            if (isIgnoredSizedTextCodepoint(cp)) continue;
            if (count != 0 and !isTrailingCombiningCodepoint(cp)) {
                changed = self.writeSizedCluster(parsed, scalars[0..count], 1) or changed;
                count = 0;
            }
            scalars[count] = @intCast(cp);
            count += 1;
        }
        if (count != 0) changed = self.writeSizedCluster(parsed, scalars[0..count], 1) or changed;
        return changed;
    }

    fn writeSizedCluster(
        self: *Screen,
        parsed: ParsedTextSize,
        scalars: []const u21,
        width_cells: u8,
    ) bool {
        std.debug.assert(scalars.len > 0 and scalars.len <= 4);
        const physical_width = @as(u16, parsed.scale) * width_cells;
        const height: u16 = parsed.scale;
        const left = self.leftBoundary();
        const right = self.rightBoundary();
        const available_width = right - left + 1;
        const available_height = self.scrollBottom() - self.scroll_top + 1;
        if (physical_width > available_width or height > available_height) return false;

        var changed = self.cancelPendingWrap();
        if (self.cursor.col + physical_width - 1 > right) {
            if (self.auto_wrap) {
                self.setRowWrapped(self.cursor.row, true);
                self.lineFeed();
                self.cursor.setColByClient(left);
                changed = true;
            } else {
                self.cursor.setColByClient(right - physical_width + 1);
                changed = true;
            }
        }
        const bottom = self.scrollBottom();
        if (self.cursor.row + height - 1 > bottom) {
            const amount = self.cursor.row + height - 1 - bottom;
            changed = self.scrollUpRegion(self.scroll_top, bottom, amount) or changed;
            self.cursor.setPositionByClient(self.cursor.row - amount, self.cursor.col);
        }

        const cells = self.cells orelse return changed;
        const top = self.cursor.row;
        const start_col = self.cursor.col;
        var row = top;
        while (row < top + height) : (row += 1) {
            var col = start_col;
            while (col < start_col + physical_width) : (col += 1)
                changed = self.clearClusterAt(row, col, false) or changed;
        }

        var cell = Cell{
            .codepoint = scalars[0],
            .combining_len = @intCast(scalars.len - 1),
            .width = @intCast(physical_width),
            .height = parsed.scale,
            .subscale_n = parsed.subscale_n,
            .subscale_d = parsed.subscale_d,
            .vertical_align = parsed.vertical_align,
            .horizontal_align = parsed.horizontal_align,
            .attrs = self.current_attrs,
        };
        for (scalars[1..], 0..) |cp, index| cell.combining[index] = cp;
        row = top;
        while (row < top + height) : (row += 1) {
            cell.y = @intCast(row - top);
            var col = start_col;
            while (col < start_col + physical_width) : (col += 1) {
                cell.x = @intCast(col - start_col);
                const index = self.rowStart(row) + col;
                if (!std.meta.eql(cells[@intCast(index)], cell)) {
                    cells[@intCast(index)] = cell;
                    changed = true;
                }
            }
        }
        self.last_graphic = null;
        if (start_col + physical_width <= right) {
            self.cursor.setColByClient(start_col + physical_width);
        } else if (self.auto_wrap) {
            self.cursor.setColByClient(right);
            self.wrap_pending = true;
        } else {
            self.cursor.setColByClient(right);
        }
        return changed;
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
        if (self.cells) |cells| {
            const target = cells[@intCast(self.rowStart(self.cursor.row) + self.cursor.col)];
            if (target.y > 0 and target.width > 0 and target.x < target.width) {
                const after = self.cursor.col -| target.x + target.width;
                if (after <= right) {
                    self.cursor.setColByClient(after);
                } else {
                    self.lineFeed();
                    self.cursor.setColByClient(if (self.left_right_margin_mode) self.left_margin else 0);
                }
            }
        }
        if (self.insert_mode) {
            const inserted = self.insertChars(1);
            std.debug.assert(inserted or !self.wrap_pending);
        }
        if (self.cells) |cells| {
            const start = self.rowStart(self.cursor.row);
            const target = cells[@intCast(start + @as(u32, self.cursor.col))];
            if (target.width != 1 or target.height != 1 or target.x != 0 or target.y != 0) {
                std.debug.assert(self.clearClusterAt(
                    self.cursor.row,
                    self.cursor.col,
                    self.cursor.col != self.clusterAnchorCol(self.cursor.row, self.cursor.col),
                ));
            }
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
        const observed = cells[@intCast(self.rowStart(pos.row) + pos.col)];
        const anchor_row = pos.row -| observed.y;
        const anchor_col = pos.col -| observed.x;
        const idx = self.rowStart(anchor_row) + @as(u32, anchor_col);
        const lead_cell = &cells[@intCast(idx)];
        if (lead_cell.codepoint == 0) return false;
        if (lead_cell.combining_len >= lead_cell.combining.len) return true;

        const combining_index = lead_cell.combining_len;
        var row = anchor_row;
        while (row < @min(self.rows, anchor_row + lead_cell.height)) : (row += 1) {
            var col = anchor_col;
            while (col < @min(self.cols, anchor_col + lead_cell.width)) : (col += 1) {
                const member = &cells[@intCast(self.rowStart(row) + col)];
                member.combining[combining_index] = cp;
                member.combining_len = combining_index + 1;
            }
        }
        if (self.last_graphic) |*graphic| {
            if (graphic.combining_len < graphic.combining.len) {
                graphic.combining[graphic.combining_len] = cp;
                graphic.combining_len += 1;
            }
        }
        return true;
    }

    fn previousLeadCellPos(self: *const Screen) ?struct { row: u16, col: u16 } {
        const right = self.rightBoundary();
        if (self.wrap_pending) return .{ .row = self.cursor.row, .col = right };

        if (self.cursor.col == 0) return null;
        return .{ .row = self.cursor.row, .col = self.cursor.col - 1 };
    }

    /// Apply SGR parameters to the retained attributes used by subsequent writes.
    pub fn applySgr(self: *Screen, operands: SgrOperands) bool {
        const params = operands.values;
        const before = self.current_attrs;
        if (params.len == 0) {
            self.resetRendition();
            return !std.meta.eql(before, self.current_attrs);
        }

        std.debug.assert(params.len <= SgrOperands.capacity);
        const param_len: u8 = @intCast(params.len);
        var idx: u8 = 0;
        while (idx < param_len) : (idx += 1) {
            const param = params[idxOf(idx)];
            switch (param) {
                4 => self.applyUnderlineStyle(operands, &idx),
                38 => self.applyExtendedColor(operands, &idx, true),
                48 => self.applyExtendedColor(operands, &idx, false),
                58 => self.applyUnderlineColor(operands, &idx),
                else => self.applyBasicSgr(param),
            }
        }
        return !std.meta.eql(before, self.current_attrs);
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
            5 => self.current_attrs.blink = true,
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

    fn applyUnderlineStyle(self: *Screen, operands: SgrOperands, idx: *u8) void {
        const params = operands.values;
        const next = idx.* + 1;
        if (next < params.len and operands.colonAfter(idx.*)) {
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
        operands: SgrOperands,
        idx: *u8,
        is_fg: bool,
    ) void {
        const sgr_color = decodeExtendedColor(operands, idx) orelse return;
        if (is_fg) self.current_attrs.fg = sgr_color else self.current_attrs.bg = sgr_color;
    }

    fn applyUnderlineColor(
        self: *Screen,
        operands: SgrOperands,
        idx: *u8,
    ) void {
        const sgr_color = decodeExtendedColor(operands, idx) orelse return;
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
    /// Applies one terminal line feed within the active vertical margins.
    pub fn lineFeed(self: *Screen) void {
        if (self.rows == 0) return;
        const bottom = self.scrollBottom();
        if (self.cursor.row < bottom) {
            self.setCursorRowClamped(self.cursor.row + 1);
            return;
        }
        if (self.cursor.row == bottom) {
            std.debug.assert(self.scrollUpRegion(self.scroll_top, bottom, 1));
            return;
        }
        if (self.cursor.row < self.rows - 1) self.setCursorRowClamped(self.cursor.row + 1);
    }

    /// Move upward, scrolling the active region downward at its top edge.
    pub fn reverseIndex(self: *Screen) bool {
        const changed = self.cancelPendingWrap();
        if (self.rows == 0) return changed;
        if (self.cursor.row == self.scroll_top) {
            return self.scrollDownRegion(self.scroll_top, self.scrollBottom(), 1) or changed;
        }
        const row = self.cursor.row;
        self.setCursorRowClamped(row -| 1);
        return self.cursor.row != row or changed;
    }

    /// Applies DECFI within the cursor's horizontal region.
    pub fn forwardIndex(self: *Screen) bool {
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

    /// Applies DECBI within the cursor's horizontal region.
    pub fn backIndex(self: *Screen) bool {
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
        if (self.clearClustersIntersecting(0, 1, 0, self.cols)) {
            self.setRowWrapped(0, false);
        }
        const row_len = @as(u32, self.cols);
        self.storeHistoryRow(0);
        self.row_origin = (self.row_origin + 1) % self.rows;
        const bottom_start = self.rowStart(self.rows - 1);
        @memset(cells[@intCast(bottom_start)..@intCast(bottom_start + row_len)], blank_cell);
        self.setRowWrapped(self.rows - 1, false);
        self.resetLineGeometry(self.rows - 1);
    }

    /// Returns the effective lower vertical margin.
    pub fn scrollBottom(self: *const Screen) u16 {
        return if (self.rows == 0) 0 else @min(self.scroll_bottom, self.rows - 1);
    }

    /// Set zero-based vertical margins after clamping them to the grid.
    ///
    /// An unordered result changes nothing. A valid command homes the cursor,
    /// cancels pending wrap, and reports whether any retained fact changed.
    pub fn setScrollRegion(self: *Screen, top: u16, bottom: ?u16) bool {
        if (self.rows == 0) {
            const changed = self.scroll_top != 0 or self.scroll_bottom != 0 or
                self.cursor.row != 0 or self.cursor.col != 0 or self.wrap_pending;
            self.scroll_top = 0;
            self.scroll_bottom = 0;
            self.cursor.setPositionByClient(0, 0);
            self.wrap_pending = false;
            return changed;
        }

        const new_top = @min(top, self.rows - 1);
        const new_bottom = if (bottom) |value| @min(value, self.rows - 1) else self.rows - 1;
        if (new_top >= new_bottom) return false;

        const home_row = if (self.origin_mode) new_top else 0;
        const home_col = self.lineHomeCol();
        const changed = self.scroll_top != new_top or self.scroll_bottom != new_bottom or
            self.cursor.row != home_row or self.cursor.col != home_col or self.wrap_pending;
        self.scroll_top = new_top;
        self.scroll_bottom = new_bottom;
        self.cursor.setPositionByClient(home_row, home_col);
        self.wrap_pending = false;
        return changed;
    }

    /// Enable horizontal margins, or disable them and restore full-width defaults.
    ///
    /// Every enable clears physical-row geometry, including repeated sets after
    /// a screen-bank switch. The result reports every resulting state mutation.
    /// Selects DEC left/right margin mode and restores full-width margins.
    pub fn setLeftRightMarginMode(self: *Screen, enabled: bool) bool {
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

    /// Set zero-based horizontal margins while left-right margin mode is active.
    ///
    /// Disabled, undersized, or unordered input changes nothing. A valid command
    /// homes the cursor, cancels pending wrap, and reports exact retained mutation.
    pub fn setLeftRightMargins(self: *Screen, left: u16, right: ?u16) bool {
        if (!self.left_right_margin_mode or self.cols < 2) return false;
        if (left >= self.cols - 1) return false;
        if (right) |value| if (left >= value) return false;
        const new_left = @min(left, self.cols - 2);
        const new_right = if (right) |value| @min(value, self.cols - 1) else self.cols - 1;
        if (new_left >= new_right) return false;
        const home_row = if (self.origin_mode) self.scroll_top else 0;
        const home_col = if (self.origin_mode) new_left else 0;
        const changed = self.left_margin != new_left or self.right_margin != new_right or
            self.cursor.row != home_row or self.cursor.col != home_col or self.wrap_pending;
        self.left_margin = new_left;
        self.right_margin = new_right;
        self.wrap_pending = false;
        self.cursor.setPositionByClient(home_row, home_col);
        return changed;
    }

    /// Insert at least one line at an admitted cursor inside both active regions.
    ///
    /// Counts clamp to the remaining region. An outside cursor changes only a
    /// pending-wrap fact; the result reports exact row or wrap mutation.
    pub fn insertLines(self: *Screen, count: u16) bool {
        const changed = self.cancelPendingWrap();
        const bottom = self.scrollBottom();
        if (self.cursor.row < self.scroll_top or self.cursor.row > bottom) return changed;
        if (!self.cursorWithinHorizontalMargins()) return changed;
        return self.scrollDownRegion(self.cursor.row, bottom, @max(count, 1)) or changed;
    }

    /// Delete at least one line at an admitted cursor inside both active regions.
    ///
    /// Counts clamp to the remaining region. An outside cursor changes only a
    /// pending-wrap fact; the result reports exact row or wrap mutation.
    pub fn deleteLines(self: *Screen, count: u16) bool {
        const changed = self.cancelPendingWrap();
        const bottom = self.scrollBottom();
        if (self.cursor.row < self.scroll_top or self.cursor.row > bottom) return changed;
        if (!self.cursorWithinHorizontalMargins()) return changed;
        return self.scrollUpRegion(self.cursor.row, bottom, @max(count, 1)) or changed;
    }

    fn cursorWithinHorizontalMargins(self: *const Screen) bool {
        if (!self.left_right_margin_mode) return true;
        return self.cursor.col >= self.left_margin and self.cursor.col <= self.right_margin;
    }

    /// Scroll an ordered region upward by at most its bounded row count.
    /// Returns exact cell, row-fact, history, damage, or pending-wrap mutation.
    pub fn scrollUpRegion(self: *Screen, top: u16, bottom: u16, count: u16) bool {
        var changed = self.cancelPendingWrap();
        if (self.rows == 0 or self.cols == 0 or top >= self.rows or top > bottom) return changed;
        const bounded_bottom = @min(bottom, self.rows - 1);
        const region_len: u16 = bounded_bottom - top + 1;
        const amount = @min(count, region_len);
        if (amount == 0) return changed;
        changed = self.clearClustersIntersecting(top, top + amount, 0, self.cols) or changed;
        changed = self.clearClustersIntersecting(bounded_bottom, bounded_bottom + 1, 0, self.cols) or changed;

        if (top == 0 and bounded_bottom == self.rows - 1) {
            var remaining = amount;
            while (remaining > 0) : (remaining -= 1) self.scrollUp();
            return true;
        }

        const left = if (self.left_right_margin_mode) self.left_margin else 0;
        const right = if (self.left_right_margin_mode) self.right_margin else self.cols -| 1;
        if (left != 0 or right + 1 != self.cols) {
            changed = self.clearClustersIntersecting(top, bounded_bottom + 1, left, right + 1) or changed;
        }

        var dst = top;
        while (dst + amount <= bounded_bottom) : (dst += 1) {
            changed = self.copyRowRange(dst, dst + amount, left, right + 1) or changed;
        }

        var clear_row = bounded_bottom - (amount - 1);
        while (clear_row <= bounded_bottom) : (clear_row += 1) {
            changed = self.clearClustersIntersecting(clear_row, clear_row + 1, left, right + 1) or changed;
            changed = self.clearStructuralRowRange(clear_row, left, right + 1) or changed;
        }
        return changed;
    }

    /// Scroll an ordered region downward by at most its bounded row count.
    /// Returns exact cell, row-fact, damage, or pending-wrap mutation.
    pub fn scrollDownRegion(self: *Screen, top: u16, bottom: u16, count: u16) bool {
        var changed = self.cancelPendingWrap();
        if (self.rows == 0 or self.cols == 0 or top >= self.rows or top > bottom) return changed;
        const bounded_bottom = @min(bottom, self.rows - 1);
        const region_len: u16 = bounded_bottom - top + 1;
        const amount = @min(count, region_len);
        if (amount == 0) return changed;
        changed = self.clearClustersIntersecting(
            bounded_bottom - (amount - 1),
            bounded_bottom + 1,
            0,
            self.cols,
        ) or changed;
        changed = self.clearClustersIntersecting(top, top + 1, 0, self.cols) or changed;

        const left = if (self.left_right_margin_mode) self.left_margin else 0;
        const right = if (self.left_right_margin_mode) self.right_margin else self.cols -| 1;
        if (left != 0 or right + 1 != self.cols) {
            changed = self.clearClustersIntersecting(top, bounded_bottom + 1, left, right + 1) or changed;
        }

        var dst = bounded_bottom;
        while (dst >= top + amount) {
            changed = self.copyRowRange(dst, dst - amount, left, right + 1) or changed;
            if (dst == top + amount) break;
            dst -= 1;
        }

        var clear_row = top;
        while (clear_row < top + amount) : (clear_row += 1) {
            changed = self.clearClustersIntersecting(clear_row, clear_row + 1, left, right + 1) or changed;
            changed = self.clearStructuralRowRange(clear_row, left, right + 1) or changed;
        }
        return changed;
    }

    // Removes the newest projected history row and its matching logical authority.
    // A partially consumed logical line becomes the open prefix so later resize
    // cannot rejoin visible content to a completed history line.
    fn consumeNewestHistoryRow(self: *Screen) void {
        std.debug.assert(self.history_count > 0);
        const allocator = self.allocator orelse unreachable;
        self.history_count -= 1;

        if (self.open_history_line) |*line| {
            const row_count = self.projectedRowCountForCells(line.cells.items);
            std.debug.assert(row_count > 0);
            const remove = line.cells.items.len - @as(usize, row_count - 1) * self.cols;
            std.debug.assert(remove > 0);
            line.cells.shrinkRetainingCapacity(line.cells.items.len - remove);
            if (line.cells.items.len == 0) {
                line.deinit(allocator);
                self.open_history_line = null;
            }
            return;
        }

        const count = self.historyLineCount();
        std.debug.assert(count > 0);
        if (self.history_lines_start != 0) {
            const split: usize = @intCast(self.history_lines_start);
            std.mem.reverse(HistoryLine, self.history_lines.items[0..split]);
            std.mem.reverse(HistoryLine, self.history_lines.items[split..]);
            std.mem.reverse(HistoryLine, self.history_lines.items);
            self.history_lines_start = 0;
        }
        const newest: usize = @intCast(count - 1);
        var line = self.history_lines.items[newest];
        const row_count = self.projectedRowCountForCells(line.cells.items);
        std.debug.assert(row_count > 0);
        if (row_count > 1) {
            const tail = line.cells.items.len - @as(usize, row_count - 1) * self.cols;
            std.debug.assert(tail > 0 and tail <= self.cols);
            line.cells.shrinkRetainingCapacity(line.cells.items.len - tail);
            self.open_history_line = line;
        } else {
            line.deinit(allocator);
        }
        self.history_lines.items[newest] = .{};
        self.history_lines.shrinkRetainingCapacity(newest);
    }

    /// Reverse-scroll and restore newest primary scrollback rows when available.
    /// Restores up to `count` retained rows into the visible grid.
    pub fn scrollDownFromHistory(self: *Screen, count: u16) bool {
        var changed = self.cancelPendingWrap();
        if (self.rows == 0 or self.cols == 0 or count == 0) return changed;
        const limit = @max(@as(u32, self.rows), self.history_count);
        var remaining: u32 = @min(@as(u32, count), limit);
        while (remaining > 0) : (remaining -= 1) {
            const history_slot = self.historySlotForRecency(0);
            const history_flags = if (history_slot) |slot| self.history_flags.?[@intCast(slot)] else 0;
            changed = self.scrollDownRegion(self.scroll_top, self.scrollBottom(), 1) or changed;
            if (history_slot) |slot| {
                const history = self.history.?;
                const source = slot * @as(u32, self.cols);
                const destination = self.rowStart(self.scroll_top);
                @memcpy(
                    self.cells.?[@intCast(destination)..@intCast(destination + self.cols)],
                    history[@intCast(source)..@intCast(source + self.cols)],
                );
                self.row_flags.?[@intCast(self.rowWrapIndex(self.scroll_top).?)] = history_flags;
                self.consumeNewestHistoryRow();
                changed = true;
            }
        }
        return changed;
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
        return @fromBackingInt(@intCast((flags[@intCast(idx)] & row_geometry_mask) >> row_geometry_shift));
    }

    fn setLineGeometry(self: *Screen, logical_row: u16, geometry: LineGeometry) bool {
        const flags = self.row_flags orelse return false;
        const idx = self.rowWrapIndex(logical_row) orelse return false;
        const previous = self.lineGeometry(logical_row);
        if (previous == geometry) return false;
        flags[@intCast(idx)] = (flags[@intCast(idx)] & ~row_geometry_mask) |
            (@as(u8, @backingInt(geometry)) << row_geometry_shift);
        const width = self.lineColumnCount(logical_row);
        if (self.cells != null and width < self.cols) self.clearRowRange(logical_row, width, self.cols);
        if (self.cursor.row == logical_row) {
            self.cursor.setColByClient(@min(self.cursor.col, width -| 1));
            self.wrap_pending = false;
        }
        return true;
    }

    /// Applies one DEC line-presentation geometry at the cursor row.
    pub fn applyLineGeometry(self: *Screen, geometry: LineGeometry) bool {
        if (self.left_right_margin_mode) return false;
        return self.setLineGeometry(self.cursor.row, geometry);
    }

    fn resetLineGeometry(self: *Screen, row: u16) void {
        if (self.lineGeometry(row) == .single_width) return;
        std.debug.assert(self.setLineGeometry(row, .single_width));
    }

    /// Applies the DEC screen-alignment fill and reports semantic change.
    pub fn alignmentDisplay(self: *Screen) bool {
        const cells = self.cells orelse return false;
        const fill = Cell{ .codepoint = 'E', .attrs = self.current_attrs };
        const erased = self.eraseCell();
        var changed = self.wrap_pending;
        self.wrap_pending = false;
        var row: u16 = 0;
        while (row < self.rows) : (row += 1) {
            const start = self.rowStart(row);
            const line_cols = self.lineColumnCount(row);
            var row_changed = false;
            for (cells[@intCast(start)..@intCast(start + line_cols)]) |*cell| {
                if (std.meta.eql(cell.*, fill)) continue;
                cell.* = fill;
                row_changed = true;
            }
            for (cells[@intCast(start + line_cols)..@intCast(start + self.cols)]) |*cell| {
                if (std.meta.eql(cell.*, erased)) continue;
                cell.* = erased;
                row_changed = true;
            }
            if (self.row_flags) |flags| {
                const idx = self.rowWrapIndex(row) orelse unreachable;
                if (flags[@intCast(idx)] & row_wrapped_bit != 0) {
                    flags[@intCast(idx)] &= ~row_wrapped_bit;
                    row_changed = true;
                }
            }
            if (row_changed) {
                changed = true;
            }
        }
        return changed;
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
            (@as(u8, @backingInt(geometry)) << row_geometry_shift);
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

    /// Returns retained DEC line geometry by newest-first history recency.
    pub fn historyLineGeometry(self: *const Screen, history_idx: u32) LineGeometry {
        const flags = self.history_flags orelse return .single_width;
        const slot = self.historySlotForRecency(history_idx) orelse return .single_width;
        return @fromBackingInt(@intCast((flags[@intCast(slot)] & row_geometry_mask) >> row_geometry_shift));
    }

    /// Reports whether one retained history row continues into its successor.
    pub fn historyRowWrapped(self: *const Screen, history_idx: u32) bool {
        const flags = self.history_flags orelse return false;
        const slot = self.historySlotForRecency(history_idx) orelse return false;
        return flags[@intCast(slot)] & row_wrapped_bit != 0;
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

    // Clear one structural-edit range and its row facts, reporting only observable mutation.
    fn clearStructuralRowRange(self: *Screen, row: u16, start_col: u16, end_col_exclusive: u16) bool {
        const cells = self.cells orelse return false;
        const start = self.rowStart(row);
        const erase = self.eraseCell();
        var changed = false;
        var col = start_col;
        while (col < end_col_exclusive) : (col += 1) {
            const cell = &cells[@intCast(start + @as(u32, col))];
            if (std.meta.eql(cell.*, erase)) continue;
            cell.* = erase;
            changed = true;
        }
        changed = self.clearRowContinuation(row) or changed;
        if (start_col == 0 and end_col_exclusive == self.cols and self.lineGeometry(row) != .single_width) {
            self.resetLineGeometry(row);
            changed = true;
        }
        return changed;
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
            if (cell.width != 1 or cell.height != 1 or cell.x != 0 or cell.y != 0) {
                changed = self.clearClusterAt(row, col, false) or changed;
                continue;
            }
            if (std.meta.eql(cell.*, erase_cell)) continue;
            cell.* = erase_cell;
            changed = true;
        }
        return changed;
    }

    /// Reject an inverted rectangle, then clamp it to the active origin bounds.
    /// Resolves protocol rectangle coordinates against the active grid.
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

    /// Construct an empty cell carrying the current erase attributes.
    fn eraseCell(self: *const Screen) Cell {
        var attrs = self.current_attrs;
        attrs.protected = .none;
        return .{ .codepoint = 0, .attrs = attrs };
    }

    fn clusterAnchorCol(self: *const Screen, row: u16, col: u16) u16 {
        const cells = self.cells orelse return col;
        if (row >= self.rows or col >= self.cols) return col;
        const cell = cells[@intCast(self.rowStart(row) + col)];
        return col -| cell.x;
    }

    // Clears one complete bounded multicell cluster intersecting an in-bounds cell.
    fn clearClusterAt(self: *Screen, row: u16, col: u16, replace_with_space: bool) bool {
        const cells = self.cells orelse return false;
        if (row >= self.rows or col >= self.cols) return false;
        const observed = cells[@intCast(self.rowStart(row) + col)];
        if (observed.width == 1 and observed.height == 1 and observed.x == 0 and observed.y == 0)
            return false;
        if (observed.width == 0 or observed.height == 0 or observed.x >= observed.width or
            observed.y >= observed.height or col < observed.x or row < observed.y)
        {
            cells[@intCast(self.rowStart(row) + col)] = self.eraseCell();
            return true;
        }
        const top = row - observed.y;
        const left = col - observed.x;
        const bottom = @min(self.rows, top + observed.height);
        const right = @min(self.cols, left + observed.width);
        const replacement = if (replace_with_space) Cell{
            .codepoint = ' ',
            .attrs = self.current_attrs,
        } else self.eraseCell();
        var changed = false;
        var y = top;
        while (y < bottom) : (y += 1) {
            var first: ?u16 = null;
            var last: u16 = left;
            var x = left;
            while (x < right) : (x += 1) {
                const candidate = &cells[@intCast(self.rowStart(y) + x)];
                if (candidate.width != observed.width or candidate.height != observed.height or
                    candidate.x != x - left or candidate.y != y - top)
                    continue;
                if (!std.meta.eql(candidate.*, replacement)) {
                    candidate.* = replacement;
                    if (first == null) first = x;
                    last = x;
                    changed = true;
                }
            }
        }
        return changed;
    }

    // Removes every multicell intersecting one bounded mutation rectangle.
    fn clearClustersIntersecting(
        self: *Screen,
        top: u16,
        bottom_exclusive: u16,
        left: u16,
        right_exclusive: u16,
    ) bool {
        var changed = false;
        var row = top;
        while (row < bottom_exclusive) : (row += 1) {
            var col = left;
            while (col < right_exclusive) : (col += 1)
                changed = self.clearClusterAt(row, col, false) or changed;
        }
        return changed;
    }

    fn copyRowRange(self: *Screen, dst_row: u16, src_row: u16, start_col: u16, end_col_exclusive: u16) bool {
        const c = self.cells orelse return false;
        const dst_start = self.rowStart(dst_row);
        const src_start = self.rowStart(src_row);
        const start_col32 = @as(u32, start_col);
        const end_col32 = @as(u32, end_col_exclusive);
        const dst = c[@intCast(dst_start + start_col32)..@intCast(dst_start + end_col32)];
        const src = c[@intCast(src_start + start_col32)..@intCast(src_start + end_col32)];
        var changed = false;
        for (dst, src) |dst_cell, src_cell| {
            if (!std.meta.eql(dst_cell, src_cell)) changed = true;
        }
        std.mem.copyForwards(
            Cell,
            dst,
            src,
        );
        if (start_col == 0 and end_col_exclusive == self.cols) {
            changed = self.rowFlagsValue(dst_row) != self.rowFlagsValue(src_row) or changed;
            self.copyRowFlags(dst_row, src_row);
        } else {
            changed = self.clearRowContinuation(dst_row) or changed;
        }
        return changed;
    }

    fn rowFlagsValue(self: *const Screen, row: u16) u8 {
        const flags = self.row_flags orelse return 0;
        const idx = self.rowWrapIndex(row) orelse return 0;
        return flags[@intCast(idx)];
    }

    fn copyRowFlags(self: *Screen, dst_row: u16, src_row: u16) void {
        const flags = self.row_flags orelse return;
        const dst = self.rowWrapIndex(dst_row) orelse return;
        const src = self.rowWrapIndex(src_row) orelse return;
        flags[@intCast(dst)] = flags[@intCast(src)];
    }
};

// Screen storage, reflow, and cell-value support.

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

/// Exact failures while copying one unfinished logical output line.
pub const CopyOpenOutputLineError = error{ OutOfMemory, LineTooLong };

/// Copies the current unfinished logical line into caller-owned storage.
pub fn copyOpenOutputLine(
    allocator: std.mem.Allocator,
    screen: *const Screen,
    limit: usize,
) CopyOpenOutputLineError![]u8 {
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
    operands: Screen.SgrOperands,
    idx: *u8,
) ?ScreenColor {
    const params = operands.values;
    const next = idx.* + 1;
    if (next >= params.len) return null;
    const mode = params[idxOf(next)];
    if (operands.colonAfter(idx.*)) return decodeColonColor(operands, idx, mode);
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
    operands: Screen.SgrOperands,
    idx: *u8,
    mode: i32,
) ?ScreenColor {
    const params = operands.values;
    var end = idx.*;
    while (end + 1 < params.len and operands.colonAfter(end)) end += 1;
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

/// Distinguishes ISO guarded areas from DEC selective-erase protection.
pub const ScreenProtection = enum(u2) {
    none,
    iso,
    dec,
};

/// Stores one cell's font, baseline, style, colors, protection, and hyperlink identity.
pub const ScreenCellAttrs = struct {
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

// Stores one bounded Unicode cluster, ordinary or OSC 66 placement, and complete attributes.
const ScreenCell = struct {
    codepoint: u32,
    combining_len: u8 = 0,
    combining: [3]u32 = .{ 0, 0, 0 },
    width: u8 = 1,
    height: u8 = 1,
    x: u8 = 0,
    y: u8 = 0,
    subscale_n: u4 = 0,
    subscale_d: u4 = 0,
    vertical_align: u2 = 0,
    horizontal_align: u2 = 0,
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

/// Identifies block, underline, bar, or hidden cursor presentation.
pub const ScreenCursorShape = enum {
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

/// Selects a program override or restoration to configured default style.
pub const CursorStyleCommand = union(enum) {
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
    /// Selects effective cursor blinking and reports semantic change.
    pub fn setBlink(self: *ScreenSemanticCursor, enabled: bool) bool {
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

    /// Moves the column and advances client-movement identity.
    pub fn setColByClient(self: *ScreenSemanticCursor, col: u16) void {
        self.setPositionByClient(self.row, col);
    }

    fn applyStyle(self: *ScreenSemanticCursor, style: ScreenCursorStyle) void {
        self.effective_shape = style.shape;
        self.blink_intent = style.blink;
    }
};

fn advanceIdentity(value: *u64) void {
    value.* = std.math.add(u64, value.*, 1) catch @panic("monotonic identity exhausted");
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
    fn deinit(self: *LogicalLine, allocator: std.mem.Allocator) void {
        self.cells.deinit(allocator);
        self.* = .{};
    }
};

/// Owned logical-content snapshot and cursor location used by resize.
const LogicalSnapshot = struct {
    logical_lines: std.ArrayListUnmanaged(LogicalLine) = .empty,
    cursor_found: bool = false,
    cursor_line_index: u32 = 0,
    cursor_offset: u32 = 0,

    /// Release every cloned line and reset the snapshot.
    fn deinit(self: *LogicalSnapshot, allocator: std.mem.Allocator) void {
        for (self.logical_lines.items) |*line| line.deinit(allocator);
        self.logical_lines.deinit(allocator);
        self.* = .{};
    }
};

// Owns one logical history line’s cells until deinit.
const HistoryLine = struct {
    cells: std.ArrayListUnmanaged(ScreenCell) = .empty,

    /// Releases a history line’s cell allocation.
    fn deinit(self: *HistoryLine, allocator: std.mem.Allocator) void {
        self.cells.deinit(allocator);
        self.* = .{};
    }
};

/// Identifies why one finalized logical-output line could not be retained.
pub const OutputLossReason = enum { line_too_long };

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

/// Zero-based rectangular area whose optional lower bounds extend to the page edge.
pub const RectArea = struct {
    top: u16,
    left: u16,
    bottom: ?u16,
    right: ?u16,
};

/// Optional rectangular locator filter coordinates.
pub const OptionalRectArea = struct {
    top: ?u16,
    left: ?u16,
    bottom: ?u16,
    right: ?u16,
};

/// Page-qualified rectangular copy request.
pub const RectCopy = struct {
    area: RectArea,
    source_page: u16,
    dest_top: u16,
    dest_left: u16,
    dest_page: u16,
};

/// Owned reflow rows, line projections, and projected cursor state.
const ReflowState = struct {
    flat_rows: std.ArrayListUnmanaged(ScreenCell) = .empty,
    rewrapped: std.ArrayListUnmanaged(RewrappedRow) = .empty,
    line_row_starts: std.ArrayListUnmanaged(u32) = .empty,
    line_row_counts: std.ArrayListUnmanaged(u16) = .empty,
    global_cursor_row: u32 = 0,
    global_cursor_col: u16 = 0,
    next_wrap_pending: bool = false,

    /// Release every reflow allocation and reset the value.
    fn deinit(self: *ReflowState, allocator: std.mem.Allocator) void {
        self.flat_rows.deinit(allocator);
        self.rewrapped.deinit(allocator);
        self.line_row_starts.deinit(allocator);
        self.line_row_counts.deinit(allocator);
        self.* = .{};
    }
};

// Derived projection window into complete reflow output.
const ResizeProjection = struct {
    total_rows: u32,
    visible_rows_kept: u16,
    visible_start: u32,
    first_visible_line: u32,
    hidden_rows_in_first_visible_line: u16,
};

/// Owned visible-grid buffers transferred together into a replacement Screen.
const ResizeBuffers = struct {
    cells: ?[]ScreenCell,
    row_flags: ?[]u8,
    tab_stops: ?[]bool,

    const empty: ResizeBuffers = .{
        .cells = null,
        .row_flags = null,
        .tab_stops = null,
    };

    /// Release every owned buffer and reset the value.
    fn deinit(self: *ResizeBuffers, allocator: std.mem.Allocator) void {
        if (self.cells) |buf| allocator.free(buf);
        if (self.row_flags) |buf| allocator.free(buf);
        if (self.tab_stops) |buf| allocator.free(buf);
        self.* = empty;
    }

    /// Transfer all buffers to one owner and leave this value empty.
    fn take(self: *ResizeBuffers) ResizeBuffers {
        const owned = self.*;
        self.* = empty;
        return owned;
    }
};

/// Reflow one borrowed logical snapshot to allocator-owned rows without consuming it.
///
/// Allocation failure releases partial output and leaves the snapshot reusable.
fn reflowLogicalLines(
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
fn projectViewport(logical_line_count: u32, reflow: ReflowState, rows: u16) ResizeProjection {
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
fn allocResizeBuffers(
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

    const tab_stops = try allocTabStops(allocator, cols);
    errdefer if (tab_stops) |buf| allocator.free(buf);
    copyTabStops(tab_stops, old_tab_stops);

    std.debug.assert((cells != null) == (cell_count > 0));
    std.debug.assert((row_flags != null) == (rows > 0));
    std.debug.assert((tab_stops != null) == (cols > 0));
    if (cells) |buf| std.debug.assert(buf.len == cell_count);
    if (row_flags) |buf| std.debug.assert(buf.len == rows);
    if (tab_stops) |buf| std.debug.assert(buf.len == cols);

    return .{
        .cells = cells,
        .row_flags = row_flags,
        .tab_stops = tab_stops,
    };
}

// Copy the selected visible rows into allocated replacement buffers.
fn copyVisibleRows(buffers: *ResizeBuffers, reflow: ReflowState, projection: ResizeProjection, cols: u16) void {
    const dst = buffers.cells orelse return;
    const dst_flags = buffers.row_flags orelse return;

    std.debug.assert(projection.visible_start + projection.visible_rows_kept <= projection.total_rows);
    std.debug.assert(projection.total_rows == screenCount32(reflow.rewrapped.items.len));
    std.debug.assert(screenCount32(dst_flags.len) >= projection.visible_rows_kept);
    std.debug.assert(screenCount32(dst.len) >= resizeCellCount(projection.visible_rows_kept, cols));
    std.debug.assert(
        screenCount32(reflow.flat_rows.items.len) ==
            screenCount32(reflow.rewrapped.items.len) * screenResizeColCount(cols),
    );

    var src_row = projection.visible_start;
    var view_row: u16 = 0;
    while (view_row < projection.visible_rows_kept) : (view_row += 1) {
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

    std.debug.assert(src_row == projection.visible_start + projection.visible_rows_kept);
}

test "resize allocation owners release partial state and remain reusable" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, collectSnapshotAllocation, .{});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, reflowAllocation, .{});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, resizeBuffersAllocation, .{});
}

fn collectSnapshotAllocation(allocator: std.mem.Allocator) !void {
    var screen = try Screen.initWithCellsAndHistory(std.testing.allocator, 2, 4, 8);
    defer screen.deinit(std.testing.allocator);
    screen.applyScreen(.{ .write_text = "ABCDEFGHIJ" });

    var snapshot = screen.collectLogicalSnapshot(allocator) catch |err| {
        var retry = try screen.collectLogicalSnapshot(std.testing.allocator);
        retry.deinit(std.testing.allocator);
        return err;
    };
    snapshot.deinit(allocator);
}

fn reflowAllocation(allocator: std.mem.Allocator) !void {
    var screen = try Screen.initWithCellsAndHistory(std.testing.allocator, 2, 4, 8);
    defer screen.deinit(std.testing.allocator);
    screen.applyScreen(.{ .write_text = "ABCDEFGHIJ" });
    var snapshot = try screen.collectLogicalSnapshot(std.testing.allocator);
    defer snapshot.deinit(std.testing.allocator);

    var state = reflowLogicalLines(allocator, snapshot, 3) catch |err| {
        var retry = try reflowLogicalLines(std.testing.allocator, snapshot, 3);
        retry.deinit(std.testing.allocator);
        return err;
    };
    state.deinit(allocator);
}

fn resizeBuffersAllocation(allocator: std.mem.Allocator) !void {
    var buffers = allocResizeBuffers(allocator, 3, 5, null) catch |err| {
        var retry = try allocResizeBuffers(std.testing.allocator, 3, 5, null);
        retry.deinit(std.testing.allocator);
        return err;
    };
    buffers.deinit(allocator);
}

fn canonicalLogicalStream(allocator: std.mem.Allocator, screen: *const Screen) ![]u21 {
    var snapshot = try screen.collectLogicalSnapshot(allocator);
    defer snapshot.deinit(allocator);

    var lines: std.ArrayList(u21) = .empty;
    defer lines.deinit(allocator);
    for (snapshot.logical_lines.items) |line| {
        try lines.append(allocator, 0);
        for (line.cells.items) |cell| try lines.append(allocator, @intCast(cell.codepoint));
    }
    return lines.toOwnedSlice(allocator);
}

test "logical content survives reflow when projected history saturates" {
    const allocator = std.testing.allocator;
    var screen = try Screen.initWithCellsAndHistory(allocator, 2, 6, 4);
    defer screen.deinit(allocator);

    screen.applyScreen(.{ .write_text = "AAAAAA\nBBBBBB\nCCCCCC\nDDDDDD\nEEEEEE" });
    const before = try canonicalLogicalStream(allocator, &screen);
    defer allocator.free(before);

    try screen.resize(allocator, 5, 3);
    try std.testing.expectEqual(@as(u32, 4), screen.historyCount());

    const after = try canonicalLogicalStream(allocator, &screen);
    defer allocator.free(after);
    try std.testing.expectEqualSlices(u21, before, after);
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
fn applyRectAttrOps(target: *ScreenCellAttrs, attrs: []const u16, reverse: bool) bool {
    const before = target.*;
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
    return !std.meta.eql(before, target.*);
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

test "logical output byte bound evicts complete oldest lines" {
    var screen = try Screen.initWithCellsAndHistory(std.testing.allocator, 2, 2, 4);
    defer screen.deinit(std.testing.allocator);
    const line_bytes = Screen.retained_output_bytes_max / 2 + 1;
    const first = try std.testing.allocator.alloc(u8, line_bytes);
    @memset(first, 'a');
    try screen.retainOutputText(std.testing.allocator, first);
    const second = try std.testing.allocator.alloc(u8, line_bytes);
    @memset(second, 'b');
    try screen.retainOutputText(std.testing.allocator, second);

    try std.testing.expectEqual(@as(u16, 1), screen.output_lines_count);
    try std.testing.expectEqual(@as(u64, 2), screen.output_lines.items[@intCast(screen.output_lines_start)].?.id);
    try std.testing.expectEqual(line_bytes, screen.output_bytes);
}

test "logical output accepts its exact per-line byte bound" {
    var screen = try Screen.initWithCellsAndHistory(std.testing.allocator, 2, 2, 2);
    defer screen.deinit(std.testing.allocator);
    const maximum = try std.testing.allocator.alloc(u8, logical_output_line_bytes_max);
    @memset(maximum, 'x');
    try screen.retainOutputText(std.testing.allocator, maximum);

    try std.testing.expectEqual(@as(u16, 1), screen.output_lines_count);
    try std.testing.expectEqual(logical_output_line_bytes_max, screen.output_bytes);
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
