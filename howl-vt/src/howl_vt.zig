//! Sole native embedding root for the host-neutral terminal model.

const terminal_mod = @import("terminal.zig");

/// Terminal state owner, byte-stream engine, and semantic surface publisher.
pub const Terminal = terminal_mod.Terminal;

test {
    _ = terminal_mod;
}
