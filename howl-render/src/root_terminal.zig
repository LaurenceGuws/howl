//! Exposes the selected compile-time Howl rendering capabilities.

/// Owns caller-neutral tab, pane-frame, label, and scrollbar projection.
pub const chrome = @import("chrome");

/// Owns stateless terminal semantic-to-visual projection.
pub const terminal = @import("terminal_projection");
/// Owns stateless terminal image-to-upload projection.
pub const terminal_images = @import("image_projection");
