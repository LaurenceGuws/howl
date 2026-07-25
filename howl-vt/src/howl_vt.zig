//! Public embedding root for the terminal emulator.

const terminal = @import("terminal.zig");
const std = @import("std");

/// Owns one terminal emulator, its retained state, replies, and consequences.
pub const Terminal = terminal.Terminal;

test {
    std.testing.refAllDecls(Terminal);
}
