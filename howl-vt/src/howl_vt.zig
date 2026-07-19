//! Sole native embedding root for the host-neutral terminal model.

const terminal = @import("terminal.zig");

/// Terminal state owner, byte-stream engine, and semantic surface publisher.
pub const Terminal = terminal.Terminal;

test {
    _ = terminal;
}
