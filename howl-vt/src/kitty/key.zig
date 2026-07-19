//! Owns the bounded Kitty keyboard-protocol stack and report encoding.

const std = @import("std");
const host_state = @import("../host_state.zig");

const format_output_max_bytes = 16;
/// Howl implements every defined Kitty progressive keyboard flag.
pub const supported_flags: u8 = 1 | 2 | 4 | 8 | 16;

/// Stores current Kitty keyboard flags and at most sixteen prior flag sets.
pub const Stack = struct {
    flags: u8 = 0,
    stack: [16]u8 = [_]u8{0} ** 16,
    len: u8 = 0,

    /// Replaces, sets, or clears current keyboard flags according to Kitty mode semantics.
    pub fn set(self: *Stack, requested: u8, mode: u8) void {
        const flags = requested & supported_flags;
        switch (mode) {
            1 => self.flags = flags,
            2 => self.flags |= flags,
            3 => self.flags &= ~flags,
            else => return,
        }
    }

    /// Pushes current flags and installs new flags, dropping the oldest entry at capacity.
    pub fn push(self: *Stack, requested: u8) void {
        const flags = requested & supported_flags;
        if (self.len == self.stack.len) {
            std.mem.copyForwards(u8, self.stack[0 .. self.stack.len - 1], self.stack[1..self.stack.len]);
            self.len -= 1;
        }
        self.stack[self.len] = self.flags;
        self.len += 1;
        self.flags = flags;
    }

    /// Restores up to count prior flag sets and clears flags when count exceeds stack depth.
    pub fn pop(self: *Stack, count: u16) void {
        var remaining = count;
        while (remaining > 0 and self.len > 0) : (remaining -= 1) {
            self.len -= 1;
            self.flags = self.stack[self.len];
        }
        if (remaining > 0) self.flags = 0;
    }

    /// Appends the current keyboard flags as one bounded Kitty reply.
    pub fn appendReport(self: *const Stack, allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8) host_state.ApplyError!void {
        std.debug.assert(encode_buf.len >= format_output_max_bytes);
        const text = std.fmt.bufPrint(encode_buf, "\x1b[?{d}u", .{self.flags}) catch unreachable;
        try host_state.appendOutput(output, allocator, text);
    }
};

test "keyboard stack reports only implemented flags and restores bounded state" {
    var stack: Stack = .{};
    stack.set(0x7f, 1);
    try std.testing.expectEqual(supported_flags, stack.flags);
    stack.push(8);
    try std.testing.expectEqual(@as(u8, 8), stack.flags);
    stack.pop(1);
    try std.testing.expectEqual(supported_flags, stack.flags);
    stack.set(8, 3);
    try std.testing.expectEqual(@as(u8, 23), stack.flags);
    stack.set(0, 4);
    try std.testing.expectEqual(@as(u8, 23), stack.flags);
    stack.pop(1);
    try std.testing.expectEqual(@as(u8, 0), stack.flags);
}
