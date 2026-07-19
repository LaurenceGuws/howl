//! Allocates, initializes, and copies terminal tab-stop state.

const std = @import("std");

/// Allocates one tab-stop flag per column and installs default stops.
pub fn allocTabStops(allocator: std.mem.Allocator, cols: u16) std.mem.Allocator.Error!?[]bool {
    if (cols == 0) return null;
    const buf = try allocator.alloc(bool, cols);
    setDefaultTabStops(buf);
    return buf;
}

/// Replaces all stops with the terminal default every eight columns.
pub fn setDefaultTabStops(stops: []bool) void {
    @memset(stops, false);
    for (stops, 0..) |*stop, idx| {
        if (idx != 0 and idx % 8 == 0) stop.* = true;
    }
}

/// Copies the overlapping prefix of optional old and replacement tab stops.
pub fn copyTabStops(dst: ?[]bool, src: ?[]const bool) void {
    const d = dst orelse return;
    const s = src orelse return;
    @memcpy(d[0..@min(d.len, s.len)], s[0..@min(d.len, s.len)]);
}
