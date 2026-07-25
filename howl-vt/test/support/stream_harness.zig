const terminal_mod = @import("../../src/howl_vt.zig");
const std = @import("std");

const Terminal = terminal_mod.Terminal;

pub const Harness = struct {
    terminal: *Terminal,

    pub fn init(terminal: *Terminal) !Harness {
        return .{ .terminal = terminal };
    }

    pub fn next(self: *Harness, byte: u8) !void {
        try self.nextSlice(&.{byte});
    }

    pub fn nextSlice(self: *Harness, bytes: []const u8) !void {
        const summary = try self.terminal.feed(bytes);
        std.debug.assert(!summary.history_lost or summary.state_changed);
    }
};
