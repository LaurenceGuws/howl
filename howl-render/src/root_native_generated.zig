//! Exposes the selected compile-time Howl rendering capabilities.

/// Owns bounded backend-neutral clipped drawing facts.
pub const canvas = @import("canvas");
/// Owns caller-neutral tab, pane-frame, label, and scrollbar projection.
pub const chrome = @import("chrome");

/// Owns native font loading, shaping, metrics, and alpha rasterization.
pub const text = @import("native_text");
/// Owns bounded generated terminal-glyph classification and rasterization.
pub const generated = @import("generated_glyphs");
