//! Exposes the selected compile-time Howl rendering capabilities.

/// Owns caller-neutral tab, pane-frame, label, and scrollbar projection.
pub const chrome = @import("chrome");

/// Owns native font loading, shaping, metrics, and alpha rasterization.
pub const text = @import("native_text");
/// Owns bounded generated terminal-glyph classification and rasterization.
pub const generated = @import("generated_glyphs");
/// Owns stateless terminal semantic-to-visual projection.
pub const terminal = @import("terminal_projection");
/// Owns stateless terminal image-to-upload projection.
pub const terminal_images = @import("image_projection");
/// Owns one-run terminal text preparation without cache or backend policy.
pub const terminal_text = @import("terminal_text_capability");
