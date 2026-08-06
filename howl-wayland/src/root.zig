//! Curated reusable Wayland ABI, protocol, xkbcommon boundary, and input state.

/// Translated core and earned protocol declarations; object lifetime remains
/// with the embedding Window owner.
pub const c = @import("wayland_c");
/// Bounded caller-neutral input state and queue ownership.
pub const input = @import("input.zig");
/// The smallest xkbcommon object boundary: callers supply mapped keymap bytes
/// and retain the Wayland keymap descriptor and mapping themselves.
pub const xkb = @import("xkb.zig");
