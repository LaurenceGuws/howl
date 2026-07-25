//! Exercises the 0.1.4 development embedding boundary as a native Zig program.

const std = @import("std");
const howl_vt = @import("howl_vt");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var terminal = try howl_vt.Terminal.init(allocator, 2, 8);
    defer terminal.deinit();

    const summary = try terminal.feed("Howl\x1b[5n");
    if (!summary.state_changed) return error.TerminalStateDidNotChange;

    const view = terminal.semanticView(0);
    if (view.cellAt(0, 0) != 'H' or view.cellAt(0, 3) != 'l')
        return error.TerminalStateMismatch;

    const reply = terminal.replyBytes();
    if (!std.mem.eql(u8, reply, "\x1b[0n"))
        return error.TerminalReplyMismatch;
    try terminal.consumeReplyBytes(reply.len);
}
