//! Exposes the selected compile-time Howl rendering capabilities.

/// Owns bounded backend-neutral clipped drawing input.
pub const canvas = @import("canvas");
/// Owns caller-neutral tab, pane-frame, label, and scrollbar projection.
pub const chrome = @import("chrome");

/// Owns bounded generated terminal-glyph classification and rasterization.
pub const generated = @import("generated_glyphs");
