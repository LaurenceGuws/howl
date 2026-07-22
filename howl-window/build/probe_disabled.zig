const std = @import("std");

pub const enabled = false;
pub const queue_capacity: usize = 4_096;
pub const Owner = enum(u8) { scenario, window, render, probe };
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
pub const Values = struct {
    duration_ns: u64 = 0,
    bytes: u64 = 0,
    count: u64 = 0,
    generation: u64 = 0,
    auxiliary: u64 = 0,
    detail: u64 = 0,
    flags: u16 = 0,
};
pub const Summary = struct {
    accepted: u64,
    dropped: u64,
    high_water: u32,
    records: u64,
    samples: u64,
};
pub const StartError = error{};
pub const StopError = error{};

pub inline fn start(_: std.Io, _: []const u8) StartError!void {}
pub inline fn stop() StopError!Summary {
    return .{ .accepted = 0, .dropped = 0, .high_water = 0, .records = 0, .samples = 0 };
}
pub inline fn emit(_: Owner, _: Kind, _: Values) void {}
pub inline fn now() u64 {
    return 0;
}
