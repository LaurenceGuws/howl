const std = @import("std");
const selection_mod = @import("../../src/selection.zig");
const screen_mod = @import("../../src/screen.zig");

const Selection = selection_mod;
const Screen = screen_mod.Screen;

pub const Capture = struct {
    allocator: std.mem.Allocator,
    rows: u16,
    cols: u16,
    cursor_row: u16,
    cursor_col: u16,
    cursor_visible: bool,
    cursor_shape: Screen.CursorShape,
    cursor_blink: bool,
    auto_wrap: bool,
    cells: ?[]u21,
    history: ?[]u21,
    history_count: u32,
    history_capacity: u16,
    selection: ?Selection.TerminalSelection,

    fn gridCellCount(rows: u16, cols: u16) u32 {
        return @as(u32, rows) * @as(u32, cols);
    }

    fn gridCellIndex(cols: u16, row: u16, col: u16) u32 {
        return @as(u32, row) * @as(u32, cols) + @as(u32, col);
    }

    fn historyCellCount(history_count: u32, cols: u16) u32 {
        return history_count * @as(u32, cols);
    }

    fn historyCellIndex(cols: u16, row: u32, col: u16) u32 {
        return row * @as(u32, cols) + @as(u32, col);
    }

    pub fn captureFromScreen(allocator: std.mem.Allocator, screen: *const Screen, selection: ?Selection.TerminalSelection) !Capture {
        const history_count = screen.historyCount();
        var capture = Capture{
            .allocator = allocator,
            .rows = screen.rows,
            .cols = screen.cols,
            .cursor_row = screen.cursor.row,
            .cursor_col = screen.cursor.col,
            .cursor_visible = screen.cursor.visible,
            .cursor_shape = screen.cursor.effective_shape,
            .cursor_blink = screen.cursor.blink_intent,
            .auto_wrap = screen.auto_wrap,
            .cells = null,
            .history = null,
            .history_count = history_count,
            .history_capacity = screen.history_capacity,
            .selection = selection,
        };
        errdefer {
            if (capture.cells) |cells| allocator.free(cells);
            if (capture.history) |history| allocator.free(history);
        }

        if (screen.cells != null) {
            const size = gridCellCount(screen.rows, screen.cols);
            const owned_cells = try allocator.alloc(u21, @intCast(size));
            var row: u16 = 0;
            while (row < screen.rows) : (row += 1) {
                var col: u16 = 0;
                while (col < screen.cols) : (col += 1) {
                    owned_cells[@intCast(gridCellIndex(screen.cols, row, col))] = screen.cellAt(row, col);
                }
            }
            capture.cells = owned_cells;
        }

        if (history_count > 0 and screen.cols > 0) {
            const size = historyCellCount(history_count, screen.cols);
            const owned_history = try allocator.alloc(u21, @intCast(size));
            var row: u32 = 0;
            while (row < history_count) : (row += 1) {
                var col: u16 = 0;
                while (col < screen.cols) : (col += 1) {
                    owned_history[@intCast(historyCellIndex(screen.cols, row, col))] = @intCast(screen.historyCellAt(history_count - 1 - row, col).codepoint);
                }
            }
            capture.history = owned_history;
        }

        return capture;
    }

    pub fn deinit(self: *Capture) void {
        if (self.cells) |cells| self.allocator.free(cells);
        self.cells = null;
        if (self.history) |history| self.allocator.free(history);
        self.history = null;
    }

    pub fn cellAt(self: *const Capture, row: u16, col: u16) u21 {
        const cells = self.cells orelse return 0;
        if (row >= self.rows or col >= self.cols) return 0;
        return cells[@intCast(gridCellIndex(self.cols, row, col))];
    }

    pub fn historyRowAt(self: *const Capture, history_idx: u32, col: u16) u21 {
        const history = self.history orelse return 0;
        if (history_idx >= self.history_count or col >= self.cols) return 0;
        const logical_slot = self.history_count - 1 - history_idx;
        return history[@intCast(historyCellIndex(self.cols, logical_slot, col))];
    }
};
