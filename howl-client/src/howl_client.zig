//! Reusable native client for one existing Howl Instance endpoint.
//!
//! This package owns client-side endpoint parsing, the frozen framed connection,
//! handshake, bounded frame I/O, and request-result mechanics. It owns no PTY,
//! VT, Instance lifecycle, discovery, renderer, CLI presentation, or platform UI.
//! Native hosts use explicit Unix or numeric-IPv4 TCP streams. Byte-entry consumers need no subprocess.

const impl = @import("client.zig");

pub const Error = impl.Error;
pub const ConnectStage = impl.ConnectStage;
pub const ConnectDiagnostic = impl.ConnectDiagnostic;
pub const Frame = impl.Frame;
pub const Cancellation = impl.Cancellation;
pub const Interrupt = impl.Interrupt;
pub const Connection = impl.Connection;
pub const connectTransport = impl.connectTransport;

pub const actions = @import("actions.zig");
pub const consequences = @import("consequences.zig");
pub const state = @import("state.zig");
pub const snapshot = @import("snapshot.zig");
pub const rich = @import("rich.zig");
pub const view = @import("view.zig");
pub const selection = @import("selection.zig");
pub const search = @import("search.zig");
pub const images = @import("images.zig");

// Exported modules are lazy; reference them so package tests cannot be empty.
test {
    @import("std").testing.refAllDecls(@This());
}
