//! Listener-free Local Instance ownership shared by maintained desktop clients.
//!
//! Local owns one canonical Howl Instance in-process and exposes ordinary HWLS
//! client connections to it. No filesystem socket, listener, Server, or Session
//! exists in this route.

const builtin = @import("builtin");

const platform = switch (builtin.os.tag) {
    .linux => @import("local_linux.zig"),
    .windows => @import("local_windows.zig"),
    else => @import("local_unsupported.zig"),
};

pub const Error = platform.Error;
pub const State = platform.State;
pub const create = platform.create;
pub const destroy = platform.destroy;
pub const connect = platform.connect;
pub const empty = platform.empty;
