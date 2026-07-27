//! Exposes the selected compile-time Howl rendering capabilities.

/// Owns bounded backend-neutral clipped drawing facts.
pub const canvas = @import("canvas");
/// Owns caller-neutral tab, pane-frame, label, and scrollbar projection.
pub const chrome = @import("chrome");
