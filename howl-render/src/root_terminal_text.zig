//! Exposes native terminal text with mandatory generated terminal glyphs.

/// Owns bounded backend-neutral clipped drawing facts.
pub const canvas = @import("canvas");
/// Owns caller-neutral tab, pane-frame, label, and scrollbar projection.
pub const chrome = @import("chrome");

/// Owns native font loading, shaping, metrics, and alpha rasterization.
pub const text = @import("native_text");
/// Owns terminal projection and complete clipped Canvas pane rendering.
pub const terminal = @import("terminal_projection");
/// Owns stateless terminal image-to-upload projection.
pub const terminal_images = @import("image_projection");
/// Owns bounded terminal native groups and shared font-resource production.
pub const terminal_font_owner = @import("terminal_font_owner");
