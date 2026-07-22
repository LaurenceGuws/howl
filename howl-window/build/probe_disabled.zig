//! Compiles the removable development probe boundary to predictable no-ops.

const std = @import("std");

/// Selects compile-time elimination of all development measurement work.
pub const enabled = false;
/// Mirrors the enabled queue contract without retaining its storage.
pub const queue_capacity: usize = 4_096;
/// Mirrors the enabled sampling contract without starting a worker.
pub const sample_interval_ms: u32 = 100;
/// Disabled emission retains no event payload.
pub const event_bytes: usize = 0;
/// Disabled emission retains no queue storage.
pub const queue_bytes: usize = 0;

/// Mirrors stable logical actor identity at compile time.
pub const Owner = enum(u8) { scenario, window, render, probe };
/// Mirrors the complete enabled event vocabulary at compile time.
pub const Kind = enum(u8) {
    thread_start,
    producer_baseline,
    pty_read,
    vt_feed,
    frame_publish,
    frame_saturated,
    frame_borrow_release,
    mailbox,
    render_prepare,
    draw,
    present,
    process_sample,
    thread_sample,
    summary,
};
/// Mirrors one enabled compact event without retaining values.
pub const Values = struct {
    /// Stores elapsed work or sampled CPU nanoseconds.
    duration_ns: u64 = 0,
    /// Stores transferred, retained, uploaded, backing, or RSS bytes.
    bytes: u64 = 0,
    /// Stores sequence, cell, quad, event, or thread count.
    count: u64 = 0,
    /// Stores the relevant publication identity or fault count.
    generation: u64 = 0,
    /// Stores the first kind-specific paired counter.
    auxiliary: u64 = 0,
    /// Stores the second counter or two packed bounded u32 counters.
    detail: u64 = 0,
    /// Stores exact mutation bits or sampled Linux task state.
    flags: u16 = 0,
};
/// Reports the exact zero-work disabled result.
pub const Summary = struct {
    /// Disabled workers drain no events.
    accepted: u64,
    /// Disabled producers reject no events because they perform no admission.
    dropped: u64,
    /// Disabled workers retain no queue depth.
    high_water: u32,
    /// Disabled workers write no records.
    records: u64,
    /// Disabled workers take no periodic or final samples.
    samples: u64,
};
/// Disabled startup cannot fail.
pub const StartError = error{};
/// Disabled shutdown cannot fail.
pub const StopError = error{};

/// Opens no file and starts no thread.
pub inline fn start(_: std.Io, _: []const u8) StartError!void {}
/// Returns exact zero retained work.
pub inline fn stop() StopError!Summary {
    return .{ .accepted = 0, .dropped = 0, .high_water = 0, .records = 0, .samples = 0 };
}
/// Compiles one producer call to no runtime work.
pub inline fn emit(_: Owner, _: Kind, _: Values) void {}
/// Compiles one timestamp request to the zero sentinel.
pub inline fn now() u64 {
    return 0;
}

test "disabled probe performs no filesystem or retained work" {
    try start(std.Io.failing, "/unavailable/howl-probe.jsonl");
    emit(.scenario, .vt_feed, .{ .bytes = 1 });
    try std.testing.expectEqual(@as(u64, 0), (try stop()).accepted);
}
