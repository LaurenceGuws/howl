//! Bounded owner for a collection of canonical Howl Sessions.
//!
//! The first accepted cut preserves the static multi-terminal collection that
//! originated in howl-cli. Collection lifetime and Session ownership live here;
//! operator command vocabulary remains in howl-cli.

const server = @import("server.zig");

pub const protocol = @import("howl_server_protocol");

pub const Error = server.Error;
pub const RunOutcome = server.RunOutcome;
pub const run = server.run;
