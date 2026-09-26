//! Explicit Local-Instance placeholder for Odin targets without a native PTY.
//!
//! Remote routes stay available. Local creation fails visibly until the target
//! earns its own PTY owner, such as the later Windows ConPTY implementation.

const std = @import("std");
const client = @import("howl_client");

pub const Error = error{LocalUnsupported};

pub const State = struct {};

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

pub fn destroy(_: *State, _: std.Io, _: u64) bool {
    return false;
}

pub fn connect(
    _: *State,
    _: std.Io,
    _: u64,
    _: *client.ConnectDiagnostic,
    _: ?*client.Interrupt,
) Error!client.Connection {
    return error.LocalUnsupported;
}

pub fn empty(_: *const State) bool {
    return true;
}
