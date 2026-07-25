//! Public embedding root for the terminal emulator.

const terminal = @import("terminal.zig");

/// Owns one terminal emulator, its retained state, replies, and consequences.
pub const Terminal = terminal.Terminal;

test {
    _ = terminal;
}
