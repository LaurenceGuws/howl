//! Reusable native client for one existing Howl session endpoint.
//!
//! This package owns client-side endpoint parsing, the frozen framed connection,
//! handshake, bounded frame I/O, and request-result mechanics. It owns no PTY,
//! VT, session lifecycle, discovery, remote transport, authentication, renderer,
//! CLI presentation, or platform UI.

const impl = @import("client.zig");

pub const Error = impl.Error;
pub const Frame = impl.Frame;
pub const Connection = impl.Connection;
