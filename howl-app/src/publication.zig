const std = @import("std");

/// Presentation policy only. Canonical service always precedes this decision.
pub const Gate = struct {
    revision: u64 = 0,
    hold_started: ?u64 = null,
    timed_out: bool = false,
    pending: bool = true,

    /// Tracks pending canonical change and exact release/hold deadlines without changing VT.
    pub fn note(self: *Gate, revision: u64, held: bool, ended: bool, now: u64) void {
        if (ended or !held) {
            self.hold_started = null;
            self.timed_out = false;
        }
        self.pending = self.pending or revision != self.revision;
        self.revision = revision;
        if (held and !self.timed_out) {
            const started = self.hold_started orelse now;
            self.hold_started = started;
            if (now -| started >= std.time.ns_per_s) {
                self.timed_out = true;
                self.hold_started = null;
            }
        }
    }

    /// Allows projection only outside a hold or after its bounded timeout.
    pub fn released(self: Gate, held: bool) bool {
        return !held or self.timed_out;
    }

    /// Supplies the next hold deadline, including a quiescent child.
    pub fn waitMs(self: Gate, now: u64) ?i32 {
        const start = self.hold_started orelse return null;
        const ns = std.time.ns_per_s -| (now -| start);
        return @intCast((ns + std.time.ns_per_ms - 1) / std.time.ns_per_ms);
    }
};

/// One absolute retained-row anchor, independent of output arrival.
pub const History = struct {
    offset: u32 = 0,
    anchor: ?u64 = null,

    /// Returns this viewport to live and retires its absolute anchor.
    pub fn reset(self: *History) void {
        self.* = .{};
    }

    /// Clamps an explicit history window and records its absolute retained-row anchor.
    pub fn seek(self: *History, offset: u32, count: u32, base: u32, alternate: bool) void {
        self.offset = if (alternate) 0 else @min(offset, count);
        self.anchor = if (self.offset == 0) null else @as(u64, base) + count - self.offset;
    }

    /// Applies bounded signed row intent against exact retained extent.
    pub fn scroll(self: *History, delta: i32, count: u32, base: u32, alternate: bool) void {
        const next = std.math.clamp(@as(i64, self.offset) + delta, 0, @as(i64, count));
        self.seek(@intCast(next), count, base, alternate);
    }

    /// Keeps the same absolute top row during output and clamps it after eviction.
    pub fn follow(self: *History, count: u32, base: u32, alternate: bool) void {
        const anchor = self.anchor orelse return;
        if (alternate) return self.reset();
        const end = @as(u64, base) + count;
        self.seek(@intCast(@min(end -| anchor, count)), count, base, false);
    }
};

test "held output releases on timeout without new child output, then resets on exact release" {
    var gate: Gate = .{ .pending = false };
    gate.note(7, true, false, 100);
    try std.testing.expect(gate.pending);
    try std.testing.expect(!gate.released(true));
    try std.testing.expectEqual(@as(?i32, 1000), gate.waitMs(100));
    gate.note(7, true, false, 100 + std.time.ns_per_s);
    try std.testing.expect(gate.released(true));
    try std.testing.expectEqual(@as(?i32, null), gate.waitMs(100 + std.time.ns_per_s));
    gate.pending = false;
    gate.note(8, true, true, 200 + std.time.ns_per_s);
    try std.testing.expect(!gate.released(true));
    gate.note(8, false, false, 201 + std.time.ns_per_s);
    try std.testing.expect(gate.released(false));
}

test "history anchor follows output, clamps eviction and resets alternate screen" {
    var history: History = .{};
    history.seek(20, 100, 10, false);
    history.follow(110, 10, false);
    try std.testing.expectEqual(@as(u32, 30), history.offset);
    try std.testing.expectEqual(@as(?u64, 90), history.anchor);
    history.follow(15, 100, false);
    try std.testing.expectEqual(@as(u32, 15), history.offset);
    try std.testing.expectEqual(@as(?u64, 100), history.anchor);
    history.follow(15, 100, true);
    try std.testing.expectEqual(@as(u32, 0), history.offset);
}
