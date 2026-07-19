const terminal_mod = @import("../../src/terminal.zig");

const Terminal = terminal_mod.Terminal;

pub const Harness = struct {
    stream: Terminal.Stream,

    pub fn init(terminal: *Terminal) !Harness {
        return .{ .stream = terminal.vtStream() };
    }

    pub fn next(self: *Harness, byte: u8) !void {
        try self.stream.next(byte);
    }

    pub fn nextSlice(self: *Harness, bytes: []const u8) !void {
        try self.stream.nextSlice(bytes);
    }
};
