//! Exposes the selected compile-time Howl rendering capabilities.

/// Owns bounded generated terminal-glyph classification and rasterization.
pub const generated = @import("generated_glyphs");
/// Owns stateless terminal semantic-to-visual projection.
pub const terminal = @import("terminal_projection");
/// Owns one-run terminal text preparation without cache or backend policy.
pub const terminal_text = @import("terminal_text_capability");
