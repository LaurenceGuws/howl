//! Reusable native client for one existing Howl Instance endpoint.
//!
//! This package owns client-side endpoint parsing, the frozen framed connection,
//! handshake, bounded frame I/O, and request-result mechanics. It owns no PTY,
//! VT, Instance lifecycle, discovery, renderer, CLI presentation, or platform UI.
//! Native hosts use explicit Unix or numeric-IPv4 TCP streams. Byte-entry consumers need no subprocess.

const impl = @import("client.zig");

/// Frozen Instance interaction protocol shared with the attached endpoint.
pub const protocol = @import("howl_instance_protocol");
/// Common connection allocation, transport, framing, and handshake failures.
pub const Error = impl.Error;
/// Exact native transport setup stage used by connection diagnostics.
pub const ConnectStage = impl.ConnectStage;
/// Bounded native transport diagnostic retained across setup.
pub const ConnectDiagnostic = impl.ConnectDiagnostic;
/// Owned decoded HWLS frame type.
pub const Frame = impl.Frame;
/// Independently owned duplicate used to wake blocked receive.
pub const Cancellation = impl.Cancellation;
/// Caller-owned interrupt token for setup and I/O cancellation.
pub const Interrupt = impl.Interrupt;
/// One established HWLS connection owner.
pub const Connection = impl.Connection;
/// Completes the HWLS handshake over an already-owned transport stream.
pub const connectTransport = impl.connectTransport;

/// Canonical client-side Instance mutation requests.
pub const actions = @import("actions.zig");
/// Host-consequence authority, observation, consume, and reply operations.
pub const consequences = @import("consequences.zig");
/// Coherent terminal interaction-state query operations.
pub const state = @import("state.zig");
/// Compact reasoning-friendly snapshot projection.
pub const snapshot = @import("snapshot.zig");
/// Lossless native rich snapshot decoder and owner.
pub const rich = @import("rich.zig");
/// Immutable normalized terminal view projection.
pub const view = @import("view.zig");
/// Canonical text-selection geometry and extraction helpers.
pub const selection = @import("selection.zig");
/// Client-local exact text search over projected snapshots.
pub const search = @import("search.zig");
/// Demand-driven exact terminal-image resource retrieval.
pub const images = @import("images.zig");

// Exported modules are lazy; reference them so package tests cannot be empty.
test {
    @import("std").testing.refAllDecls(@This());
}
