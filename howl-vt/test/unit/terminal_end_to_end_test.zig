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

test "terminal: tab controls share exact stored-stop and clamping behavior" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 20);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b[3g\x1b[6G\x1bH\x1b[11G\x1bH\r\x1b[I")).history_lost);
    try std.testing.expectEqual(@as(u16, 5), terminal.screen_state.activeConst().cursor.col);
    try std.testing.expect(!(try terminal.feed("\x1b[0I")).history_lost);
    try std.testing.expectEqual(@as(u16, 10), terminal.screen_state.activeConst().cursor.col);
    try std.testing.expect(!(try terminal.feed("\x1b[0Z")).history_lost);
    try std.testing.expectEqual(@as(u16, 5), terminal.screen_state.activeConst().cursor.col);
    try std.testing.expect(!(try terminal.feed("\x1b[999999I")).history_lost);
    try std.testing.expectEqual(@as(u16, 19), terminal.screen_state.activeConst().cursor.col);
    try std.testing.expect(!(try terminal.feed("\x1b[2Z")).history_lost);
    try std.testing.expectEqual(@as(u16, 5), terminal.screen_state.activeConst().cursor.col);

    try std.testing.expect(!(try terminal.feed("\x1b[g\r\x09")).history_lost);
    try std.testing.expectEqual(@as(u16, 10), terminal.screen_state.activeConst().cursor.col);
    try std.testing.expect(!(try terminal.feed("\x1b[5g\r\x09")).history_lost);
    try std.testing.expectEqual(@as(u16, 19), terminal.screen_state.activeConst().cursor.col);

    try std.testing.expect(!(try terminal.feed("\x1b[6G\x1bH\x1b[3g\r\x09")).history_lost);
    try std.testing.expectEqual(@as(u16, 19), terminal.screen_state.activeConst().cursor.col);
    try std.testing.expect(!(try terminal.feed("\x1b[?5W\r\x09\x1b[I\x1b[999999Z")).history_lost);
    try std.testing.expectEqual(@as(u16, 0), terminal.screen_state.activeConst().cursor.col);

    try std.testing.expect(!(try terminal.feed("\x1b[6G\x88\r\x09")).history_lost);
    try std.testing.expectEqual(@as(u16, 5), terminal.screen_state.activeConst().cursor.col);
}

test "terminal: 7-bit and C1 index controls preserve scroll-region effects" {
    const allocator = std.testing.allocator;
    const controls = [_]struct {
        ind: []const u8,
        nel: []const u8,
        ri: []const u8,
    }{
        .{ .ind = "\x1bD", .nel = "\x1bE", .ri = "\x1bM" },
        .{ .ind = "\x84", .nel = "\x85", .ri = "\x8d" },
    };

    for (controls) |control| {
        var terminal = try Terminal.init(allocator, 4, 8);
        defer terminal.deinit();

        try std.testing.expect(!(try terminal.feed("\x1b[2;3r\x1b[2;1HA\x1b[3;1HB\x1b[3;6H")).history_lost);
        try std.testing.expect(!(try terminal.feed(control.ind)).history_lost);
        const after_ind = terminal.screen_state.activeConst();
        try std.testing.expectEqual(@as(u21, 'B'), after_ind.cellAt(1, 0));
        try std.testing.expectEqual(@as(u21, 0), after_ind.cellAt(2, 0));
        try std.testing.expectEqual(@as(u16, 2), after_ind.cursor.row);
        try std.testing.expectEqual(@as(u16, 5), after_ind.cursor.col);

        try std.testing.expect(!(try terminal.feed("\x1b[2;6H")).history_lost);
        try std.testing.expect(!(try terminal.feed(control.ri)).history_lost);
        const after_ri = terminal.screen_state.activeConst();
        try std.testing.expectEqual(@as(u21, 0), after_ri.cellAt(1, 0));
        try std.testing.expectEqual(@as(u21, 'B'), after_ri.cellAt(2, 0));
        try std.testing.expectEqual(@as(u16, 1), after_ri.cursor.row);
        try std.testing.expectEqual(@as(u16, 5), after_ri.cursor.col);

        try std.testing.expect(!(try terminal.feed("\x1b[3;6H")).history_lost);
        try std.testing.expect(!(try terminal.feed(control.nel)).history_lost);
        const after_nel = terminal.screen_state.activeConst();
        try std.testing.expectEqual(@as(u21, 'B'), after_nel.cellAt(1, 0));
        try std.testing.expectEqual(@as(u21, 0), after_nel.cellAt(2, 0));
        try std.testing.expectEqual(@as(u16, 2), after_nel.cursor.row);
        try std.testing.expectEqual(@as(u16, 0), after_nel.cursor.col);
    }
}

test "terminal: CSI cursor positioning shares parameter, margin, and origin bounds" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 8, 12);
    defer terminal.deinit();

    const cursor = &terminal.screen_state.active().cursor;
    try std.testing.expect(!(try terminal.feed("\x1b[4;6H\x1b[A\x1b[0B\x1b[999999C")).history_lost);
    try std.testing.expectEqual(@as(u16, 3), cursor.row);
    try std.testing.expectEqual(@as(u16, 11), cursor.col);
    try std.testing.expect(!(try terminal.feed("\x1b[0D\x1b[999999D\x1b[0E")).history_lost);
    try std.testing.expectEqual(@as(u16, 4), cursor.row);
    try std.testing.expectEqual(@as(u16, 0), cursor.col);
    try std.testing.expect(!(try terminal.feed("\x1b[999999F\x1b[999999B")).history_lost);
    try std.testing.expectEqual(@as(u16, 7), cursor.row);
    try std.testing.expectEqual(@as(u16, 0), cursor.col);

    try std.testing.expect(!(try terminal.feed("\x1b[0G\x1b[999999`\x1b[0d\x1b[999999e")).history_lost);
    try std.testing.expectEqual(@as(u16, 7), cursor.row);
    try std.testing.expectEqual(@as(u16, 11), cursor.col);
    try std.testing.expect(!(try terminal.feed("\x1b[0;0f\x1b[999999;999999H")).history_lost);
    try std.testing.expectEqual(@as(u16, 7), cursor.row);
    try std.testing.expectEqual(@as(u16, 11), cursor.col);

    try std.testing.expect(!(try terminal.feed("\x1b[3;6r\x1b[?69h\x1b[4;9s\x1b[?6h")).history_lost);
    try std.testing.expectEqual(@as(u16, 2), cursor.row);
    try std.testing.expectEqual(@as(u16, 3), cursor.col);
    try std.testing.expect(!(try terminal.feed("\x1b[999999B\x1b[999999C")).history_lost);
    try std.testing.expectEqual(@as(u16, 5), cursor.row);
    try std.testing.expectEqual(@as(u16, 8), cursor.col);
    try std.testing.expect(!(try terminal.feed("\x1b[999999A\x1b[999999D")).history_lost);
    try std.testing.expectEqual(@as(u16, 2), cursor.row);
    try std.testing.expectEqual(@as(u16, 3), cursor.col);
    try std.testing.expect(!(try terminal.feed("\x1b[2;2H\x1b[999999d")).history_lost);
    try std.testing.expectEqual(@as(u16, 5), cursor.row);
    try std.testing.expectEqual(@as(u16, 4), cursor.col);
    try std.testing.expect(!(try terminal.feed("\x1b[0d\x1b[d")).history_lost);
    try std.testing.expectEqual(@as(u16, 2), cursor.row);
    try std.testing.expectEqual(@as(u16, 4), cursor.col);
    try std.testing.expect(!(try terminal.feed("\x1b[2;2H\x1b[0E\x1b[0F")).history_lost);
    try std.testing.expectEqual(@as(u16, 3), cursor.row);
    try std.testing.expectEqual(@as(u16, 3), cursor.col);
    try std.testing.expect(!(try terminal.feed("\x1b[999999d\x1b[999999G")).history_lost);
    try std.testing.expectEqual(@as(u16, 5), cursor.row);
    try std.testing.expectEqual(@as(u16, 8), cursor.col);
    try std.testing.expect(!(try terminal.feed("\x1b[0;0H\x1b[999999;999999f")).history_lost);
    try std.testing.expectEqual(@as(u16, 5), cursor.row);
    try std.testing.expectEqual(@as(u16, 8), cursor.col);

    try std.testing.expect(!(try terminal.feed("\x1b[?6l\x1b[1;1H\x1b[999999B\x1b[999999C")).history_lost);
    try std.testing.expectEqual(@as(u16, 5), cursor.row);
    try std.testing.expectEqual(@as(u16, 8), cursor.col);
    try std.testing.expect(!(try terminal.feed("\x1b[8;12H\x1b[999999A\x1b[999999D")).history_lost);
    try std.testing.expectEqual(@as(u16, 2), cursor.row);
    try std.testing.expectEqual(@as(u16, 3), cursor.col);
    try std.testing.expect(!(try terminal.feed("\x1b[4;6H\x1b[E")).history_lost);
    try std.testing.expectEqual(@as(u16, 4), cursor.row);
    try std.testing.expectEqual(@as(u16, 3), cursor.col);
}

test "terminal: CSI grid edits clamp counts and preserve region boundaries" {
    const allocator = std.testing.allocator;

    {
        var terminal = try Terminal.init(allocator, 2, 8);
        defer terminal.deinit();
        try std.testing.expect(!(try terminal.feed("ABCDEFGH\x1b[?69h\x1b[3;6s\x1b[1;4H\x1b[@")).history_lost);
        const screen = terminal.screen_state.activeConst();
        try std.testing.expectEqual(@as(u21, 'A'), screen.cellAt(0, 0));
        try std.testing.expectEqual(@as(u21, 'B'), screen.cellAt(0, 1));
        try std.testing.expectEqual(@as(u21, 'C'), screen.cellAt(0, 2));
        try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 3));
        try std.testing.expectEqual(@as(u21, 'D'), screen.cellAt(0, 4));
        try std.testing.expectEqual(@as(u21, 'E'), screen.cellAt(0, 5));
        try std.testing.expectEqual(@as(u21, 'G'), screen.cellAt(0, 6));
        try std.testing.expectEqual(@as(u21, 'H'), screen.cellAt(0, 7));

        try std.testing.expect(!(try terminal.feed("\x1b[1;1H\x1b[999999P")).history_lost);
        try std.testing.expectEqual(@as(u21, 'A'), screen.cellAt(0, 0));
        try std.testing.expectEqual(@as(u21, 'B'), screen.cellAt(0, 1));
        try std.testing.expect(!(try terminal.feed(
            "\x1b[1\"qZ\x1b[48;2;40;44;52m\x1b[1;1H\x1b[999999X",
        )).history_lost);
        try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 0));
        try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 7));
        try std.testing.expectEqual(Screen.Color.rgbComponents(40, 44, 52), screen.cellInfoAt(0, 7).attrs.bg);
        try std.testing.expectEqual(@as(u16, 0), screen.cursor.col);
    }

    {
        var terminal = try Terminal.init(allocator, 4, 6);
        defer terminal.deinit();
        try std.testing.expect(!(try terminal.feed(
            "\x1b[1;1HAAAAAA\x1b[2;1HBBBBBB\x1b[3;1HCCCCCC\x1b[4;1HDDDDDD" ++
                "\x1b[2;4r\x1b[?69h\x1b[2;5s\x1b[2;3H\x1b[L",
        )).history_lost);
        const screen = terminal.screen_state.activeConst();
        try std.testing.expectEqual(@as(u21, 'B'), screen.cellAt(1, 0));
        try std.testing.expectEqual(@as(u21, 0), screen.cellAt(1, 1));
        try std.testing.expectEqual(@as(u21, 0), screen.cellAt(1, 4));
        try std.testing.expectEqual(@as(u21, 'B'), screen.cellAt(1, 5));
        try std.testing.expectEqual(@as(u21, 'C'), screen.cellAt(2, 0));
        try std.testing.expectEqual(@as(u21, 'B'), screen.cellAt(2, 1));
        try std.testing.expectEqual(@as(u21, 'B'), screen.cellAt(2, 4));
        try std.testing.expectEqual(@as(u21, 'C'), screen.cellAt(2, 5));

        try std.testing.expect(!(try terminal.feed("\x1b[2;1H\x1b[999999M")).history_lost);
        try std.testing.expectEqual(@as(u21, 'B'), screen.cellAt(1, 0));
        try std.testing.expectEqual(@as(u21, 'B'), screen.cellAt(2, 1));
        try std.testing.expect(!(try terminal.feed("\x1b[2;3H\x1b[999999M")).history_lost);
        try std.testing.expectEqual(@as(u21, 0), screen.cellAt(1, 1));
        try std.testing.expectEqual(@as(u21, 0), screen.cellAt(3, 4));
    }

    {
        var terminal = try Terminal.init(allocator, 4, 5);
        defer terminal.deinit();
        try std.testing.expect(!(try terminal.feed(
            "\x1b[1;1HAAAAA\x1b[2;1HBBBBB\x1b[3;1HCCCCC\x1b[4;1HDDDDD" ++
                "\x1b[2;4r\x1b[?69h\x1b[2;4s\x1b[999999S",
        )).history_lost);
        const screen = terminal.screen_state.activeConst();
        try std.testing.expectEqual(@as(u21, 'A'), screen.cellAt(0, 2));
        try std.testing.expectEqual(@as(u21, 'B'), screen.cellAt(1, 0));
        try std.testing.expectEqual(@as(u21, 0), screen.cellAt(1, 1));
        try std.testing.expectEqual(@as(u21, 0), screen.cellAt(3, 3));
        try std.testing.expectEqual(@as(u21, 'D'), screen.cellAt(3, 4));
        const cursor = screen.cursor;
        try std.testing.expect(!(try terminal.feed("\x1b[0T")).history_lost);
        try std.testing.expectEqual(cursor.row, screen.cursor.row);
        try std.testing.expectEqual(cursor.col, screen.cursor.col);
    }

    {
        var terminal = try Terminal.initWithHistory(allocator, 2, 3, 2);
        defer terminal.deinit();
        try std.testing.expect(!(try terminal.feed("\x1b[1;1HAAA\x1b[2;1HBBB\x1b[2;2H")).history_lost);
        const before = terminal.screen_state.activeConst().cursor;
        try std.testing.expect(!(try terminal.feed("\x1b[S")).history_lost);
        const screen = terminal.screen_state.activeConst();
        try std.testing.expectEqual(@as(u32, 1), screen.historyCount());
        try std.testing.expectEqual(before.row, screen.cursor.row);
        try std.testing.expectEqual(before.col, screen.cursor.col);
        try std.testing.expect(!screen.rowWrapped(1));
        try std.testing.expect(screen.peekDirtyRows() != null);
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
