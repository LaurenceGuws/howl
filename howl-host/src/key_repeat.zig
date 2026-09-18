//! Bounded Wayland keyboard-repeat scheduling. The platform owner supplies
//! monotonic time and resolves the repeated key through its current xkb state.

const std = @import("std");

const ns_per_ms: u64 = std.time.ns_per_ms;
const ns_per_s: u64 = std.time.ns_per_s;
const maximum_rate: u32 = 1000;

pub const Held = struct {
    keycode: u32,
    serial: u32,
    time: u32,
};

pub const State = struct {
    rate: u32 = 0,
    delay_ms: u32 = 0,
    held: ?Held = null,
    next_ns: u64 = 0,
    period_ns: u64 = 0,

    pub fn configure(self: *State, rate: u32, delay_ms: u32, now_ns: u64) void {
        self.rate = @min(rate, maximum_rate);
        self.delay_ms = delay_ms;
        self.period_ns = if (self.rate == 0) 0 else @max(ns_per_ms, ns_per_s / self.rate);
        if (self.rate == 0) {
            self.cancel();
        } else if (self.held != null) {
            self.next_ns = now_ns +| @as(u64, delay_ms) *| ns_per_ms;
        }
    }

    /// Starts/replaces repeat only for an xkb-repeatable key. A modifier or
    /// other non-repeatable key press does not steal an already-held repeater.
    pub fn press(
        self: *State,
        key: Held,
        repeatable: bool,
        now_ns: u64,
    ) void {
        if (!repeatable or self.rate == 0) return;
        self.held = key;
        self.next_ns = now_ns +| @as(u64, self.delay_ms) *| ns_per_ms;
    }

    pub fn release(self: *State, keycode: u32) void {
        if (self.held) |held| {
            if (held.keycode == keycode) self.cancel();
        }
    }

    pub fn cancel(self: *State) void {
        self.held = null;
        self.next_ns = 0;
    }

    /// Poll timeout in milliseconds. -1 means no active repeat.
    pub fn timeoutMs(self: State, now_ns: u64) i32 {
        if (self.held == null or self.rate == 0) return -1;
        if (now_ns >= self.next_ns) return 0;
        const remaining = self.next_ns - now_ns;
        const rounded = (remaining +| (ns_per_ms - 1)) / ns_per_ms;
        return @intCast(@min(rounded, @as(u64, std.math.maxInt(i32))));
    }

    /// Returns one due repeat and schedules from "now", intentionally skipping
    /// missed ticks rather than emitting a catch-up burst after a stalled loop.
    pub fn takeDue(self: *State, now_ns: u64) ?Held {
        const held = self.held orelse return null;
        if (self.rate == 0 or now_ns < self.next_ns) return null;
        self.next_ns = now_ns +| self.period_ns;
        return held;
    }
};

test "repeat starts after delay and advances without catch-up bursts" {
    var state: State = .{};
    state.configure(25, 400, 1_000_000_000);
    state.press(.{ .keycode = 30, .serial = 7, .time = 8 }, true, 1_000_000_000);
    try std.testing.expectEqual(@as(i32, 400), state.timeoutMs(1_000_000_000));
    try std.testing.expect(state.takeDue(1_399_000_000) == null);
    const first = state.takeDue(1_400_000_000).?;
    try std.testing.expectEqual(@as(u32, 30), first.keycode);
    try std.testing.expectEqual(@as(i32, 40), state.timeoutMs(1_400_000_000));

    // A long stall yields one occurrence, then resumes from current time.
    const resumed = state.takeDue(2_000_000_000).?;
    try std.testing.expectEqual(@as(u32, 30), resumed.keycode);
    try std.testing.expectEqual(@as(i32, 40), state.timeoutMs(2_000_000_000));
}

test "modifier press does not steal active repeat and release cancels only owner" {
    var state: State = .{};
    state.configure(30, 250, 0);
    state.press(.{ .keycode = 30, .serial = 1, .time = 1 }, true, 0);
    state.press(.{ .keycode = 42, .serial = 2, .time = 2 }, false, 10);
    try std.testing.expectEqual(@as(u32, 30), state.held.?.keycode);
    state.release(42);
    try std.testing.expect(state.held != null);
    state.release(30);
    try std.testing.expect(state.held == null);
}

test "zero rate disables and policy changes reschedule an active key" {
    var state: State = .{};
    state.configure(20, 300, 0);
    state.press(.{ .keycode = 44, .serial = 3, .time = 4 }, true, 10);
    state.configure(10, 500, 100);
    try std.testing.expectEqual(@as(i32, 500), state.timeoutMs(100));
    state.configure(0, 0, 200);
    try std.testing.expect(state.held == null);
    try std.testing.expectEqual(@as(i32, -1), state.timeoutMs(200));
}
