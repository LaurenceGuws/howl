//! Exposes the selected compile-time Howl rendering capabilities.

/// Owns native font loading, shaping, metrics, and alpha rasterization.
pub const text = @import("native_text");
/// Owns bounded generated terminal-glyph classification and rasterization.
pub const generated = @import("generated_glyphs");
