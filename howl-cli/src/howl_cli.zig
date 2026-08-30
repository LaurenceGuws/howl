//! Native human/agent client for one canonical Howl session.

pub const version = "0.1.6-dev";
pub const version_schema = "howl.version/v1";

pub const snapshot = @import("snapshot.zig");
pub const state = @import("state.zig");
pub const actions = @import("actions.zig");
