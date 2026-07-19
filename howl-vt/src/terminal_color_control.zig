//! Defines host-facing terminal color-control commands.

/// Borrows one terminal color key and optional replacement value.
pub const TerminalColorControlCommand = struct {
    command: u16,
    payload: []const u8,
};
