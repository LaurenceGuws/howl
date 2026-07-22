//! Exposes the selected compile-time Howl rendering capabilities.

/// Owns native font loading, shaping, metrics, and alpha rasterization.
pub const text = @import("native_text");
/// Owns stateless terminal semantic-to-visual projection.
pub const terminal = @import("terminal_projection");
/// Owns one-run terminal text preparation without cache or backend policy.
pub const terminal_text = @import("terminal_text_capability");
