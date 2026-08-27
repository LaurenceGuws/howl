//! Curates the maintained non-GUI Howl operator and agent client owners.

/// Owns one bounded negotiated session-wire connection.
pub const client = @import("client.zig");
/// Owns validated ephemeral runtime session discovery.
pub const discovery = @import("discovery.zig");
