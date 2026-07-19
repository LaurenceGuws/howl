//! Owns terminal selection endpoints and selection lifecycle.

const std = @import("std");
const screen_mod = @import("screen.zig");

const Screen = screen_mod.Screen;

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

/// Selection lifecycle state container.
pub const SelectionState = struct {
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

/// Returns selection endpoints in document order without mutating selection state.
pub fn ordered(sel: TerminalSelection) struct { start: SelectionPos, end: SelectionPos } {
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
