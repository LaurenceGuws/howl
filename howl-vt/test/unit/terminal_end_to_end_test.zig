const std = @import("std");
const screen_mod = @import("../../src/terminal.zig");
const terminal_mod = @import("../../src/terminal.zig");
const stream_harness = @import("../support/stream_harness.zig");

const Screen = screen_mod.Screen;
const Terminal = terminal_mod.Terminal;
const StreamHarness = stream_harness.Harness;

test "terminal: stream applies bytes to grid state deterministically" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("ab");
    try stream.next('c');
    try stream.nextSlice("\r\nxy");

    const s = terminal.screen_state.activeConst();
    try std.testing.expectEqual(@as(u21, 'a'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'c'), s.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 'x'), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'y'), s.cellAt(1, 1));
    try std.testing.expectEqual(@as(u16, 1), s.cursor.row);
    try std.testing.expectEqual(@as(u16, 2), s.cursor.col);
}

test "terminal: C0 controls retain exact stream effects" {
    const allocator = std.testing.allocator;

    {
        var terminal = try Terminal.init(allocator, 3, 16);
        defer terminal.deinit();
        try std.testing.expect(!(try terminal.feed("\x07")).history_lost);
        try std.testing.expectEqual(@as(u64, 1), terminal.surfaceSnapshot().bell_generation);
    }
    {
        var terminal = try Terminal.init(allocator, 3, 16);
        defer terminal.deinit();
        try std.testing.expect(!(try terminal.feed("ab\x08X")).history_lost);
        try std.testing.expectEqual(@as(u21, 'a'), terminal.screen_state.activeConst().cellAt(0, 0));
        try std.testing.expectEqual(@as(u21, 'X'), terminal.screen_state.activeConst().cellAt(0, 1));
    }
    {
        var terminal = try Terminal.init(allocator, 3, 16);
        defer terminal.deinit();
        try std.testing.expect(!(try terminal.feed("\x1b[3gABC\x1bH\r\x09X")).history_lost);
        try std.testing.expectEqual(@as(u21, 'X'), terminal.screen_state.activeConst().cellAt(0, 3));
    }
    for ([_]u8{ 0x0A, 0x0B, 0x0C }) |control| {
        var terminal = try Terminal.init(allocator, 3, 16);
        defer terminal.deinit();
        try std.testing.expect(!(try terminal.feed(&.{ 'A', control, 'B' })).history_lost);
        try std.testing.expectEqual(@as(u21, 'B'), terminal.screen_state.activeConst().cellAt(1, 1));
    }
    {
        var terminal = try Terminal.init(allocator, 3, 16);
        defer terminal.deinit();
        try std.testing.expect(!(try terminal.feed("ab\x0dX")).history_lost);
        try std.testing.expectEqual(@as(u21, 'X'), terminal.screen_state.activeConst().cellAt(0, 0));
        try std.testing.expectEqual(@as(u21, 'b'), terminal.screen_state.activeConst().cellAt(0, 1));
    }
    {
        var terminal = try Terminal.init(allocator, 3, 16);
        defer terminal.deinit();
        try std.testing.expect(!(try terminal.feed("\x1b)0\x0eq\x0fq")).history_lost);
        try std.testing.expectEqual(@as(u21, 0x2500), terminal.screen_state.activeConst().cellAt(0, 0));
        try std.testing.expectEqual(@as(u21, 'q'), terminal.screen_state.activeConst().cellAt(0, 1));
    }
}

test "terminal: OSC cursor colors route into semantic cursor owner" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]12;#010203\x1b\\\x1b]21;cursor_text=#040506\x1b\\");

    const cursor = terminal.screen_state.activeConst().cursor;
    try std.testing.expectEqual(@as(?Screen.Rgb, .{ .r = 1, .g = 2, .b = 3 }), cursor.cursor_color);
    try std.testing.expectEqual(@as(?Screen.Rgb, .{ .r = 4, .g = 5, .b = 6 }), cursor.cursor_text_color);
}

test "terminal: every byte split preserves mixed control framing" {
    const allocator = std.testing.allocator;
    const transcript = "A\x08B\x1b[2;3HC\x1b]0;first\x07\x1bP$qm\x1b\\" ++
        "\x1b_ignore\x1b\\\x1b^ignore\x1b\\\x1bXignore\x1b\\" ++
        "\x9b3;1HZ\x9d2;final\x9c";

    var expected = try Terminal.init(allocator, 4, 8);
    defer expected.deinit();
    try std.testing.expect(!(try expected.feed(transcript)).history_lost);

    var split: usize = 0;
    while (split <= transcript.len) : (split += 1) {
        var actual = try Terminal.init(allocator, 4, 8);
        defer actual.deinit();
        try std.testing.expect(!(try actual.feed(transcript[0..split])).history_lost);
        try std.testing.expect(!(try actual.feed(transcript[split..])).history_lost);

        const expected_screen = expected.screen_state.activeConst();
        const actual_screen = actual.screen_state.activeConst();
        try std.testing.expectEqual(expected_screen.cursor.row, actual_screen.cursor.row);
        try std.testing.expectEqual(expected_screen.cursor.col, actual_screen.cursor.col);
        var row: u16 = 0;
        while (row < expected_screen.rows) : (row += 1) {
            var col: u16 = 0;
            while (col < expected_screen.cols) : (col += 1) {
                try std.testing.expectEqual(expected_screen.cellAt(row, col), actual_screen.cellAt(row, col));
            }
        }
        try std.testing.expectEqualStrings(expected.host.current_title.?, actual.host.current_title.?);
        try std.testing.expectEqualStrings(expected.host.pendingOutput(), actual.host.pendingOutput());
    }
}
