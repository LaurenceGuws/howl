//! Exposes the selected compile-time Howl rendering capabilities.

/// Owns native font loading, shaping, metrics, and alpha rasterization.
pub const text = @import("native_text");
