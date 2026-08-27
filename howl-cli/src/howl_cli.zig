//! Curates the maintained non-GUI Howl operator and agent client owners.

/// Owns one bounded negotiated session-wire connection.
pub const client = @import("client.zig");
/// Owns validated ephemeral runtime session discovery.
pub const discovery = @import("discovery.zig");

/// Owns physical key parsing, held-key state, chords, and timed sequences.
pub const input = @import("input.zig");

/// Re-exports the frozen session protocol used by CLI command parsing.
pub const protocol = @import("howl_session").protocol;
