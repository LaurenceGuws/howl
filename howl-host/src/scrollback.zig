//! Native-host wheel routing and retained-history anchor policy.

const std = @import("std");

pub const WheelRoute = enum {
    history,
    terminal_mouse,
    alternate_scroll,
    ignore,
    interaction_state,
};

/// Chooses one wheel owner without inferring terminal modes in the platform layer.
pub fn routeWheel(
    history_active: bool,
    force_history: bool,
    state_known: bool,
    mouse_tracking: bool,
    alternate_screen: bool,
    alternate_scroll: bool,
) WheelRoute {
    if (history_active or force_history) return .history;
    if (!state_known) return .interaction_state;
    if (mouse_tracking) return .terminal_mouse;
    if (!alternate_screen) return .history;
    return if (alternate_scroll) .alternate_scroll else .ignore;
}

/// Retains one viewport's absolute history anchor across canonical output growth.
pub const State = struct {
    offset: u32 = 0,
    anchor_top_row: u64 = 0,
    anchor_valid: bool = false,

    pub fn active(self: State) bool {
        return self.offset != 0;
    }

    pub fn reset(self: *State) void {
        self.* = .{};
    }

    /// Applies one signed row delta against the latest accepted history extent.
    pub fn scroll(
        self: *State,
        rows_delta: i32,
        history_count: u32,
        history_row_base: u32,
        alternate_screen: bool,
    ) void {
        if (rows_delta == 0 or alternate_screen or history_count == 0) {
            if (alternate_screen) self.reset();
            return;
        }
        const requested = @as(i64, self.offset) + rows_delta;
        const clamped_i64 = std.math.clamp(requested, 0, @as(i64, history_count));
        const clamped: u32 = @intCast(clamped_i64);
        if (clamped == self.offset) return;
        self.offset = clamped;
        if (clamped == 0) {
            self.anchor_top_row = 0;
            self.anchor_valid = false;
        } else {
            self.anchor_top_row =
                @as(u64, history_row_base) + history_count - clamped;
            self.anchor_valid = true;
        }
    }

    /// Follows the same absolute top row as retained history grows underneath it.
    pub fn follow(
        self: *State,
        history_count: u32,
        history_row_base: u32,
        alternate_screen: bool,
    ) void {
        if (self.offset == 0) return;
        if (alternate_screen or history_count == 0 or !self.anchor_valid) {
            self.reset();
            return;
        }
        const newest_history_end = @as(u64, history_row_base) + history_count;
        if (newest_history_end <= self.anchor_top_row) {
            self.reset();
            return;
        }
        const requested = newest_history_end - self.anchor_top_row;
        const clamped: u32 = @intCast(@min(requested, @as(u64, history_count)));
        if (clamped == 0) {
            self.reset();
            return;
        }
        self.offset = clamped;
        if (clamped != requested)
            self.anchor_top_row = newest_history_end - clamped;
    }

    /// Accepts the server's exact clamped history window after one observation.
    pub fn accept(
        self: *State,
        history_offset: u32,
        history_count: u32,
        history_row_base: u32,
        alternate_screen: bool,
    ) void {
        if (alternate_screen or history_offset == 0 or history_count == 0) {
            self.reset();
            return;
        }
        const accepted = @min(history_offset, history_count);
        if (accepted == 0) {
            self.reset();
            return;
        }
        self.offset = accepted;
        self.anchor_top_row =
            @as(u64, history_row_base) + history_count - accepted;
        self.anchor_valid = true;
    }
};

test "wheel routing matches terminal interaction ownership" {
    try std.testing.expectEqual(WheelRoute.history, routeWheel(true, false, true, true, false, false));
    try std.testing.expectEqual(WheelRoute.history, routeWheel(false, true, true, true, false, false));
    try std.testing.expectEqual(WheelRoute.interaction_state, routeWheel(false, false, false, false, false, false));
    try std.testing.expectEqual(WheelRoute.terminal_mouse, routeWheel(false, false, true, true, false, false));
    try std.testing.expectEqual(WheelRoute.history, routeWheel(false, false, true, false, false, false));
    try std.testing.expectEqual(WheelRoute.alternate_scroll, routeWheel(false, false, true, false, true, true));
    try std.testing.expectEqual(WheelRoute.ignore, routeWheel(false, false, true, false, true, false));
}

test "history state clamps wheel rows and returns live at zero" {
    var state: State = .{};
    state.scroll(3, 10, 100, false);
    try std.testing.expectEqual(@as(u32, 3), state.offset);
    try std.testing.expectEqual(@as(u64, 107), state.anchor_top_row);
    state.scroll(99, 10, 100, false);
    try std.testing.expectEqual(@as(u32, 10), state.offset);
    try std.testing.expectEqual(@as(u64, 100), state.anchor_top_row);
    state.scroll(-99, 10, 100, false);
    try std.testing.expectEqual(@as(u32, 0), state.offset);
    try std.testing.expect(!state.anchor_valid);
}

test "history state follows absolute top row as output grows" {
    var state: State = .{};
    state.accept(5, 20, 100, false);
    try std.testing.expectEqual(@as(u64, 115), state.anchor_top_row);
    state.follow(23, 100, false);
    try std.testing.expectEqual(@as(u32, 8), state.offset);
    try std.testing.expectEqual(@as(u64, 115), state.anchor_top_row);

    // Retention moved past the old anchor, so clamp to the oldest retained row.
    state.follow(10, 120, false);
    try std.testing.expectEqual(@as(u32, 10), state.offset);
    try std.testing.expectEqual(@as(u64, 120), state.anchor_top_row);

    state.follow(10, 120, true);
    try std.testing.expectEqual(State{}, state);
}
