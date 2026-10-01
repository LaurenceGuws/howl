//! Exposes backend-independent terminal rendering backed by howl-text.

/// Exposes shared terminal-frame storage limits.
pub const limits = @import("limits");
/// Re-exports the exact howl-text module instance used by this renderer.
///
/// Embedders construct caller-owned FontSet values through this namespace so
/// Renderer FontFaces and the caller share one Zig type identity.
pub const text = @import("howl_text");
/// Owns semantic terminal-to-frame rendering, resources, and final frames.
pub const terminal = @import("terminal");
