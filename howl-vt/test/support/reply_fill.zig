//! Fills the bounded reply queue through real terminal protocol reports.

const std = @import("std");
const terminal_mod = @import("../../src/terminal.zig");

/// Returns a copy of exactly `count` retained reply bytes.
pub fn fill(
    terminal: *terminal_mod.Terminal,
    allocator: std.mem.Allocator,
    count: usize,
    eight_bit_after: bool,
) ![]u8 {
    try std.testing.expectEqual(@as(usize, 0), terminal.replyBytes().len);
    const eight_bit_queries = (4 - count % 4) % 4;
    const seven_bit_bytes = count - eight_bit_queries * 3;
    try std.testing.expectEqual(@as(usize, 0), seven_bit_bytes % 4);
    const seven_bit_queries = seven_bit_bytes / 4;
    try std.testing.expect(seven_bit_queries != 0);

    try std.testing.expect((try terminal.feed("\x1b F\x1b[5n")).state_changed);
    for (1..seven_bit_queries) |_|
        try std.testing.expect((try terminal.feed("\x1b[5n")).state_changed);
    if (eight_bit_queries != 0 or eight_bit_after)
        try std.testing.expect((try terminal.feed("\x1b G")).state_changed);
    for (0..eight_bit_queries) |_|
        try std.testing.expect((try terminal.feed("\x9b5n")).state_changed);
    if (!eight_bit_after and eight_bit_queries != 0)
        try std.testing.expect((try terminal.feed("\x1b F")).state_changed);

    try std.testing.expectEqual(count, terminal.replyBytes().len);
    return allocator.dupe(u8, terminal.replyBytes());
}
