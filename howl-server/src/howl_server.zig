//! Bounded owner for a collection of canonical Howl Sessions.
//!
//! The first accepted cut preserves the static multi-terminal collection that
//! originated in howl-cli. Collection lifetime and Session ownership live here;
//! operator command vocabulary remains in howl-cli.

const server = @import("server.zig");

pub const protocol = @import("howl_server_protocol");
pub const Registry = @import("registry.zig").Registry;
pub const Manager = @import("manager.zig").Manager;
pub const ListenerSpec = @import("manager.zig").ListenerSpec;

pub const Error = server.Error;
pub const RunOutcome = server.RunOutcome;
pub const run = server.run;
