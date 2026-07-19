//! Owns primary/alternate screens, selections, and unified visible surface views.

const std = @import("std");
const screen_mod = @import("screen.zig");
const selection = @import("selection.zig");

const Screen = screen_mod.Screen;
const SelectionState = selection.SelectionState;

/// Identifies whether a visible row comes from history or the active screen.
pub const RowSource = union(enum) {
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

/// Pairs a borrowed visible view with its active selection.
pub const SurfaceSnapshot = struct {
    view: View,
    dirty: ?Screen.DirtyRows,
    selection: ?selection.TerminalSelection,
};

/// Owns primary and alternate screens plus their independent selections.
pub const Set = struct {
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

/// Builds a borrowed view and selection at a clamped u64 offset.
pub fn surfaceSnapshot(screen_state: *const Set, scrollback_offset: u64) SurfaceSnapshot {
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
