//! Exposes terminal-frame projection backed by howl-text.

/// Exposes shared terminal-frame storage limits.
pub const limits = @import("limits");
/// Temporary package-graph pass-through; implementation ownership remains howl-text.
pub const text = @import("howl_text");
/// Owns semantic terminal-to-backend presentation, resources, and final frames.
pub const terminal = @import("terminal");
