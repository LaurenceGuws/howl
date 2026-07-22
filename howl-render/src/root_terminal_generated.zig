//! Exposes the selected compile-time Howl rendering capabilities.

/// Owns bounded generated terminal-glyph classification and rasterization.
pub const generated = @import("generated_glyphs");
/// Owns stateless terminal semantic-to-visual projection.
pub const terminal = @import("terminal_projection");
