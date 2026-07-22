//! Sole native embedding root for the host-neutral terminal model.

const terminal = @import("terminal.zig");

/// Terminal state owner, byte-stream engine, visual view, and consequence boundary.
pub const Terminal = terminal.Terminal;

test {
    _ = terminal;
}
