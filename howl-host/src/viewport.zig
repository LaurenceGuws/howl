//! Owns one terminal's host-side scroll intent and scrollbar geometry.

const std = @import("std");

/// Copies terminal-owned viewport bounds needed by executable policy.
pub const Facts = struct {
    /// Reports retained primary rows reachable above the screen.
    history_count: u32 = 0,
    /// Reports the terminal-applied distance from the live bottom.
    offset: u32 = 0,
    /// Reports visible terminal rows.
    rows: u16 = 1,
    /// Suppresses primary-history policy while the alternate screen is active.
    alternate_screen: bool = false,
    /// Gives application mouse tracking ownership of pointer events.
    mouse_reporting: bool = false,
};

/// Selects one bounded host scroll operation.
pub const Move = union(enum) {
    /// Moves by signed retained rows; positive values review older rows.
    lines: i32,
    /// Reviews one visible page toward older history.
    page_up,
    /// Reviews one visible page toward live output.
    page_down,
    /// Reviews the oldest retained primary row.
    top,
    /// Returns to following live output.
    bottom,
};

/// Retains applied viewport intent without mutating terminal state speculatively.
pub const State = struct {
    /// Copies the last facts returned by the terminal owner.
    facts: Facts = .{},
    /// Reports whether the applied terminal viewport follows live output.
    follow: bool = true,

    /// Reconciles only terminal-returned facts.
    pub fn reconcile(self: *State, facts: Facts) void {
        std.debug.assert(facts.offset <= facts.history_count);
        self.* = .{ .facts = facts, .follow = facts.offset == 0 };
    }

    /// Computes an absolute terminal request without changing retained intent.
    pub fn requested(self: State, move: Move) u32 {
        if (self.facts.alternate_screen or self.facts.history_count == 0) return 0;
        return switch (move) {
            .top => self.facts.history_count,
            .bottom => 0,
            .page_up => addClamped(self.facts.offset, pageRows(self.facts.rows), self.facts.history_count),
            .page_down => self.facts.offset -| pageRows(self.facts.rows),
            .lines => |lines| if (lines >= 0)
                addClamped(self.facts.offset, @intCast(lines), self.facts.history_count)
            else
                self.facts.offset -| negativeMagnitude(lines),
        };
    }
};

/// Defines one bounded painted or hit-tested pixel rectangle.
pub const Rect = struct {
    /// Sets the left surface pixel.
    x: u32,
    /// Sets the top surface pixel.
    y: u32,
    /// Sets the nonzero pixel width.
    width: u16,
    /// Sets the nonzero pixel height.
    height: u32,

    /// Reports whether one nonnegative surface pixel is inside the rectangle.
    pub fn contains(self: Rect, x: i64, y: i64) bool {
        if (x < 0 or y < 0) return false;
        const px: u64 = @intCast(x);
        const py: u64 = @intCast(y);
        return px >= self.x and px < @as(u64, self.x) + self.width and
            py >= self.y and py < @as(u64, self.y) + self.height;
    }
};

/// Copies the exact track and thumb pixels painted and hit-tested by the host.
pub const Scrollbar = struct {
    /// Defines every painted and admitted scrollbar pixel.
    track: Rect,
    /// Defines the painted current-view indicator.
    thumb: Rect,
    /// Copies the terminal history bound used by drag mapping.
    history_count: u32,
    /// Copies the applied terminal offset represented by the thumb.
    offset: u32,

    /// Returns a drag anchor only for pixels painted as track or thumb.
    pub fn begin(self: Scrollbar, x: i64, y: i64) ?Drag {
        if (!self.track.contains(x, y)) return null;
        const anchor: u32 = if (self.thumb.contains(x, y))
            @intCast(y - self.thumb.y)
        else
            self.thumb.height / 2;
        return .{ .track = self.track, .thumb_height = self.thumb.height, .anchor = anchor };
    }
};

/// Retains one bounded scrollbar drag independent of pointer protocol state.
pub const Drag = struct {
    /// Retains the exact painted track admitted by the initial press.
    track: Rect,
    /// Retains the admitted thumb height.
    thumb_height: u32,
    /// Retains the pointer's y offset within the moved thumb.
    anchor: u32,

    /// Maps one surface y pixel to an absolute history offset.
    pub fn offset(self: Drag, y: i64, history_count: u32) u32 {
        if (history_count == 0) return 0;
        const travel = self.track.height - self.thumb_height;
        if (travel == 0) return 0;
        const requested_top = (y -| @as(i64, self.track.y)) -| self.anchor;
        const top: u64 = @intCast(std.math.clamp(requested_top, 0, @as(i64, travel)));
        const distance_from_top = @min(
            @as(u64, history_count),
            (top * history_count + travel / 2) / travel,
        );
        return history_count - @as(u32, @intCast(distance_from_top));
    }
};

/// Resolves useful scrollbar pixels; null paints and admits no scrollbar.
pub fn scrollbar(facts: Facts, width: u32, height: u32, cell_width: u16, cell_height: u16) ?Scrollbar {
    if (facts.alternate_screen or facts.history_count == 0 or width == 0 or height == 0 or
        cell_width == 0 or cell_height == 0 or facts.rows == 0)
        return null;
    std.debug.assert(facts.offset <= facts.history_count);
    const grid_height = @min(@as(u64, height), @as(u64, facts.rows) * cell_height);
    if (grid_height < 3) return null;
    const track_height: u32 = @intCast(grid_height);
    const bar_width: u16 = @intCast(@min(
        width,
        @min(@as(u32, 4), @max(@as(u32, 2), cell_width / 6)),
    ));
    const total_rows = @as(u64, facts.history_count) + facts.rows;
    const proportional = grid_height * facts.rows / total_rows;
    const thumb_height: u32 = @intCast(@min(grid_height, @max(@as(u64, 3), proportional)));
    const travel = track_height - thumb_height;
    const rows_below = facts.history_count - facts.offset;
    const thumb_top: u32 = if (travel == 0)
        0
    else
        @intCast(@as(u64, rows_below) * travel / facts.history_count);
    const track = Rect{
        .x = width - bar_width,
        .y = 0,
        .width = bar_width,
        .height = track_height,
    };
    return .{
        .track = track,
        .thumb = .{
            .x = track.x,
            .y = thumb_top,
            .width = bar_width,
            .height = thumb_height,
        },
        .history_count = facts.history_count,
        .offset = facts.offset,
    };
}

fn pageRows(rows: u16) u32 {
    return @max(@as(u32, 1), @as(u32, rows) -| 1);
}

fn addClamped(value: u32, increase: u32, maximum: u32) u32 {
    return @intCast(@min(@as(u64, value) + increase, maximum));
}

fn negativeMagnitude(value: i32) u32 {
    std.debug.assert(value < 0);
    return if (value == std.math.minInt(i32))
        @as(u32, std.math.maxInt(i32)) + 1
    else
        @intCast(-value);
}

test "viewport intent commits only reconciled terminal facts" {
    var state = State{};
    state.reconcile(.{});
    try std.testing.expectEqual(@as(u32, 0), state.requested(.page_up));

    const available = Facts{ .history_count = 100, .rows = 24 };
    state.reconcile(available);
    try std.testing.expect(state.follow);
    try std.testing.expectEqual(@as(u32, 23), state.requested(.page_up));
    try std.testing.expectEqual(@as(u32, 100), state.requested(.top));
    try std.testing.expectEqual(@as(u32, 0), state.requested(.bottom));
    try std.testing.expectEqual(@as(u32, 100), state.requested(.{ .lines = std.math.maxInt(i32) }));

    const reviewed = Facts{ .history_count = 100, .offset = 70, .rows = 24 };
    state.reconcile(reviewed);
    try std.testing.expect(!state.follow);
    try std.testing.expectEqual(@as(u32, 47), state.requested(.page_down));
    try std.testing.expectEqual(@as(u32, 0), state.requested(.{ .lines = std.math.minInt(i32) }));

    const alternate = Facts{ .history_count = 0, .rows = 24, .alternate_screen = true };
    state.reconcile(alternate);
    try std.testing.expectEqual(@as(u32, 0), state.requested(.top));
}

test "scrollbar paint and hit geometry are exact at narrow and surplus bounds" {
    const top = scrollbar(
        .{ .history_count = 100, .offset = 100, .rows = 20 },
        1000,
        503,
        10,
        20,
    ).?;
    try std.testing.expectEqual(Rect{ .x = 998, .y = 0, .width = 2, .height = 400 }, top.track);
    try std.testing.expectEqual(@as(u32, 0), top.thumb.y);
    try std.testing.expect(top.track.contains(999, 399));
    try std.testing.expect(!top.track.contains(997, 399));
    try std.testing.expect(!top.track.contains(999, 400));

    const bottom = scrollbar(
        .{ .history_count = 100, .offset = 0, .rows = 20 },
        7,
        2,
        1,
        1,
    );
    try std.testing.expect(bottom == null);

    const narrow = scrollbar(
        .{ .history_count = 3, .offset = 0, .rows = 3 },
        2,
        3,
        1,
        1,
    ).?;
    try std.testing.expectEqual(Rect{ .x = 0, .y = 0, .width = 2, .height = 3 }, narrow.track);
    try std.testing.expectEqual(narrow.track, narrow.thumb);
}

test "scrollbar drag is the inverse of painted endpoints and clamps hostile y" {
    const top = scrollbar(
        .{ .history_count = 100, .offset = 100, .rows = 20 },
        100,
        400,
        10,
        20,
    ).?;
    const top_drag = top.begin(top.thumb.x, top.thumb.y).?;
    try std.testing.expectEqual(@as(u32, 100), top_drag.offset(top.thumb.y, top.history_count));
    try std.testing.expectEqual(@as(u32, 0), top_drag.offset(std.math.maxInt(i64), top.history_count));

    const bottom = scrollbar(
        .{ .history_count = 100, .offset = 0, .rows = 20 },
        100,
        400,
        10,
        20,
    ).?;
    const bottom_y = @as(i64, bottom.thumb.y) + bottom.thumb.height - 1;
    const bottom_drag = bottom.begin(bottom.thumb.x, bottom_y).?;
    try std.testing.expectEqual(@as(u32, 0), bottom_drag.offset(bottom_y, bottom.history_count));
    try std.testing.expectEqual(@as(u32, 100), bottom_drag.offset(std.math.minInt(i64), bottom.history_count));
    try std.testing.expect(top.begin(top.track.x - 1, 0) == null);
}
