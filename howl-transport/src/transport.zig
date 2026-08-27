//! Agent-experience transport over the frozen Howl session wire.
//!
//! This package owns no PTY, VT, session, discovery, lifecycle, or renderer
//! semantics. Its purpose is to make the existing composable session protocol
//! externally inspectable and exercisable without flattening terminal truth.

pub const wire = @import("wire.zig");
pub const observe = @import("observe.zig");
