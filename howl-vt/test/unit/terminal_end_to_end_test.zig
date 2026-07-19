const std = @import("std");
const screen_mod = @import("../../src/screen.zig");
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
