//! White-box proof root; never imported or exported by the public owner.
const state = @import("output_state");
/// Instrumented white-box specialization of the same owner algorithm.
pub const Candidate = state.State(true);
/// Borrowed immutable output pinned until the matching release.
pub const Snapshot = state.Snapshot;
/// Private bounded cache and output configuration shared by both specializations.
pub const Config = state.Config;
/// Proof-only logical work counters; absent from ordinary state storage.
pub const Stats = state.Stats;
/// Maximum supported output row count.
pub const rows = state.rows;
/// Maximum supported output column count.
pub const cols = state.cols;
/// Bounded final-command capacity per row.
pub const row_capacity = state.row_capacity;
/// ASCII warmup fixture used only by explicit proof configuration.
pub const alphabet = state.alphabet;
/// Instrumented row emitter used by focused white-box proofs.
pub const glyph_rows = @import("glyph_rows").Emitter(true);
