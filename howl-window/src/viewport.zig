//! Owns one pane's bounded history view and exact scrollbar geometry.

const std = @import("std");

/// Copies the VT facts needed to reconcile one host-owned viewport.
pub const Facts = struct {
    history_row_base: u32,
    history_count: u32,
    offset: u32,
    rows: u16,
    alternate_screen: bool,
    mouse_reporting: bool,
};

/// Describes one painted and clickable vertical scrollbar in window pixels.
pub const Scrollbar = struct {
    x: u32,
    y: u32,
    width: u16,
    height: u32,
    thumb_y: u32,
    thumb_height: u32,

    pub fn contains(self: Scrollbar, x: u32, y: u32) bool {
        return x >= self.x and x < self.x + self.width and y >= self.y and y < self.y + self.height;
    }
};

/// Retains one pane's follow intent and stable projected-history anchor.
pub const State = struct {
    offset: u32 = 0,
    anchor: u64 = 0,
    history_row_base: u32 = 0,
    history_count: u32 = 0,
    rows: u16 = 1,
    alternate_screen: bool = false,
    mouse_reporting: bool = false,

    /// Reconciles eviction/reflow facts while preserving bottom-follow or the
    /// oldest still-retained row at the prior absolute anchor.
    pub fn observe(self: *State, facts: Facts) void {
        self.history_row_base = facts.history_row_base;
        self.history_count = facts.history_count;
        self.rows = facts.rows;
        self.mouse_reporting = facts.mouse_reporting;
        if (facts.alternate_screen) {
            self.alternate_screen = true;
            self.offset = 0;
            self.anchor = @as(u64, facts.history_row_base) + facts.history_count;
        } else if (self.alternate_screen or self.offset == 0) {
            // Alternate-screen entry/exit deliberately returns to live output;
            // primary history is never projected behind the alternate screen.
            self.alternate_screen = false;
            self.offset = 0;
            self.anchor = @as(u64, facts.history_row_base) + facts.history_count;
        } else {
            self.alternate_screen = false;
            const oldest: u64 = facts.history_row_base;
            const newest = oldest + facts.history_count;
            self.anchor = std.math.clamp(self.anchor, oldest, newest);
            self.offset = @intCast(newest - self.anchor);
        }
    }

    /// Moves by signed retained rows; positive values move toward older rows.
    pub fn move(self: *State, delta: i64) bool {
        if (self.alternate_screen or delta == 0) return false;
        const previous = self.offset;
        if (delta > 0) {
            self.offset = @intCast(@min(@as(u64, self.history_count), @as(u64, previous) + @as(u64, @intCast(delta))));
        } else {
            const amount: u64 = if (delta == std.math.minInt(i64))
                @as(u64, std.math.maxInt(i64)) + 1
            else
                @intCast(-delta);
            self.offset = if (amount >= previous) 0 else previous - @as(u32, @intCast(amount));
        }
        self.anchor = @as(u64, self.history_row_base) + self.history_count - self.offset;
        return self.offset != previous;
    }

    /// Moves to the oldest retained row or live output.
    pub fn edge(self: *State, top: bool) bool {
        return self.move(if (top) std.math.maxInt(i64) else std.math.minInt(i64));
    }

    /// Resolves the exact scrollbar painted over one pane's right edge.
    pub fn scrollbar(self: State, x: u32, y: u32, width: u32, height: u32) ?Scrollbar {
        if (self.alternate_screen or self.history_count == 0 or width < 3 or height < 8) return null;
        const bar_width: u16 = @intCast(@min(width, 3));
        const total = @as(u64, self.history_count) + self.rows;
        const thumb_height: u32 = @intCast(@max(@as(u64, 6), @as(u64, height) * self.rows / total));
        const travel = height - @min(height, thumb_height);
        const from_top = self.history_count - self.offset;
        const thumb_y = y + @as(u32, @intCast(@as(u64, travel) * from_top / self.history_count));
        return .{
            .x = x + width - bar_width,
            .y = y,
            .width = bar_width,
            .height = height,
            .thumb_y = thumb_y,
            .thumb_height = @min(height, thumb_height),
        };
    }

    /// Maps one scrollbar pixel to the nearest retained viewport offset.
    pub fn seek(self: *State, bar: Scrollbar, y: u32) bool {
        const travel = bar.height - bar.thumb_height;
        const previous = self.offset;
        if (travel == 0) {
            self.offset = 0;
        } else {
            const center = bar.thumb_height / 2;
            const bounded_y = std.math.clamp(y, bar.y, bar.y + bar.height - 1);
            const local = (bounded_y - bar.y) -| center;
            const from_top = @min(@as(u64, self.history_count), @as(u64, local) * self.history_count / travel);
            self.offset = self.history_count - @as(u32, @intCast(from_top));
        }
        self.anchor = @as(u64, self.history_row_base) + self.history_count - self.offset;
        return self.offset != previous;
    }
};

test "viewport follows bottom and preserves retained absolute history" {
    var state = State{};
    state.observe(.{ .history_row_base = 10, .history_count = 8, .offset = 0, .rows = 4, .alternate_screen = false, .mouse_reporting = false });
    state.observe(.{ .history_row_base = 10, .history_count = 10, .offset = 0, .rows = 4, .alternate_screen = false, .mouse_reporting = false });
    try std.testing.expectEqual(@as(u32, 0), state.offset);
    try std.testing.expectEqual(@as(u64, 20), state.anchor);
    try std.testing.expect(state.move(3));
    try std.testing.expectEqual(@as(u64, 17), state.anchor);
    state.observe(.{ .history_row_base = 11, .history_count = 10, .offset = 4, .rows = 4, .alternate_screen = false, .mouse_reporting = false });
    try std.testing.expectEqual(@as(u32, 4), state.offset);
    state.observe(.{ .history_row_base = 19, .history_count = 10, .offset = 10, .rows = 4, .alternate_screen = false, .mouse_reporting = false });
    try std.testing.expectEqual(@as(u32, 10), state.offset);
    try std.testing.expectEqual(@as(u64, 19), state.anchor);
}

test "alternate screen resets host viewport without hidden history" {
    var state = State{ .offset = 4, .anchor = 12, .history_count = 8 };
    state.observe(.{ .history_row_base = 4, .history_count = 0, .offset = 0, .rows = 5, .alternate_screen = true, .mouse_reporting = true });
    try std.testing.expectEqual(@as(u32, 0), state.offset);
    try std.testing.expect(state.alternate_screen);
    try std.testing.expect(state.scrollbar(0, 0, 20, 20) == null);
    try std.testing.expect(!state.move(5));
    state.observe(.{ .history_row_base = 4, .history_count = 8, .offset = 0, .rows = 5, .alternate_screen = false, .mouse_reporting = false });
    try std.testing.expectEqual(@as(u32, 0), state.offset);
}

test "scrollbar paint and hit mapping share exact hostile bounds" {
    var state = State{ .history_count = 100, .rows = 20, .offset = 0 };
    const bar = state.scrollbar(10, 7, 50, 100).?;
    try std.testing.expectEqual(@as(u32, 57), bar.x);
    try std.testing.expectEqual(bar.y + bar.height, bar.thumb_y + bar.thumb_height);
    try std.testing.expect(state.seek(bar, bar.y));
    try std.testing.expectEqual(@as(u32, 100), state.offset);
    try std.testing.expect(state.seek(bar, bar.y + bar.height));
    try std.testing.expectEqual(@as(u32, 0), state.offset);
    try std.testing.expect((State{}).scrollbar(0, 0, 2, 100) == null);
}
