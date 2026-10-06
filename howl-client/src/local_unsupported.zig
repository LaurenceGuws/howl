//! Explicit Local-Instance placeholder for targets without a native PTY.
//!
//! Remote routes stay available. Local creation fails visibly until that target
//! earns its own platform PTY owner.

const std = @import("std");
const client = @import("howl_client");

/// Reports that listener-free Local ownership is unavailable on this target.
pub const Error = error{LocalUnsupported};

/// Empty compatibility state for targets without a native Local owner.
pub const State = struct {};

/// Rejects Local Instance creation on unsupported targets.
pub fn create(
    _: *State,
    _: std.Io,
    _: std.process.Environ,
    _: []const u8,
    _: []const u8,
    _: []const u8,
    _: u16,
    _: u16,
    _: u16,
) Error!u64 {
    return error.LocalUnsupported;
}

/// Reports that no Local identity can exist on unsupported targets.
pub fn destroy(_: *State, _: std.Io, _: u64) bool {
    return false;
}

/// Rejects Local connection attempts on unsupported targets.
pub fn connect(
    _: *State,
    _: std.Io,
    _: u64,
    _: *client.ConnectDiagnostic,
    _: ?*client.Interrupt,
) Error!client.Connection {
    return error.LocalUnsupported;
}

/// Reports that the unsupported Local catalogue is always empty.
pub fn empty(_: *const State) bool {
    return true;
}
