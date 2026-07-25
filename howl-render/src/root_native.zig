//! Exposes the selected compile-time Howl rendering capabilities.

/// Owns caller-neutral tab, pane-frame, label, and scrollbar projection.
pub const chrome = @import("chrome");

/// Owns native font loading, shaping, metrics, and alpha rasterization.
pub const text = @import("native_text");
