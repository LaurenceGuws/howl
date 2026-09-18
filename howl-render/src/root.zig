//! Exposes the backend-neutral Howl drawing capability.

/// Owns the bounded maintained-client presentation envelope.
pub const presentation = @import("presentation");
/// Owns bounded backend-neutral clipped drawing and retained resource state.
pub const canvas = @import("canvas");
