//! Curated public root for the reusable Vulkan package.

/// Mechanical Vulkan-Headers-derived declarations.
pub const abi = @import("abi.zig");
/// Validated, non-owning external image and semaphore procedure lookup.
pub const dispatch = @import("dispatch.zig");
