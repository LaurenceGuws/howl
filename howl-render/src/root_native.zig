//! Exposes backend-neutral drawing plus terminal-to-Canvas presentation.

/// Owns the bounded maintained-client presentation envelope.
pub const presentation = @import("presentation");
/// Owns bounded backend-neutral clipped drawing and retained resource state.
pub const canvas = @import("canvas");
/// Temporary package-graph pass-through; implementation ownership remains howl-text.
pub const text = @import("howl_text");
/// Projects immutable terminal client views through howl-text into Canvas updates.
pub const terminal = @import("terminal");
