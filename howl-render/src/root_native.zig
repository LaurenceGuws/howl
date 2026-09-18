//! Exposes the one shared terminal presentation owner.

/// Owns the bounded maintained-client presentation envelope.
pub const presentation = @import("presentation");
/// Temporary package-graph pass-through; implementation ownership remains howl-text.
pub const text = @import("howl_text");
/// Owns semantic terminal-to-backend presentation, resources, and final frames.
pub const terminal = @import("terminal");
