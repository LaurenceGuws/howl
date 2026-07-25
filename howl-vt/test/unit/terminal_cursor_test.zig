const std = @import("std");
const terminal_mod = @import("../../src/howl_vt.zig");

const Terminal = terminal_mod.Terminal;

fn feed(terminal: *Terminal, bytes: []const u8) Terminal.FeedError!void {
    const summary = try terminal.feed(bytes);
    std.debug.assert(!summary.history_lost or summary.state_changed);
}

fn view(terminal: *const Terminal) Terminal.SemanticView {
    return terminal.semanticView(0);
}

test "terminal cursor: save restore is terminal-owned per active bank" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();

    try feed(&terminal, "\x1b[2;6H\x1b[4 q\x1b7\x1b[1;1H\x1b[1 q\x1b8");
    try std.testing.expectEqual(@as(u16, 1), view(&terminal).cursor_row);
    try std.testing.expectEqual(@as(u16, 5), view(&terminal).cursor_col);
    try std.testing.expectEqual(.underline, view(&terminal).cursor_shape);
    try std.testing.expect(!view(&terminal).cursor_blink);
}

test "terminal cursor: restore without prior save homes the cursor" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();

    try feed(&terminal, "\x1b[?5h\x1b[?6h\x1b[?7l\x1b)0\x1b8");
    try std.testing.expectEqual(@as(u16, 0), view(&terminal).cursor_row);
    try std.testing.expectEqual(@as(u16, 0), view(&terminal).cursor_col);
}

test "terminal cursor: alt screen enter resets alt cursor instead of copying primary" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();

    try feed(&terminal, "\x1b[3;4H\x1b[6 q\x1b[?47h");
    try std.testing.expect(view(&terminal).is_alternate_screen);
    try std.testing.expectEqual(@as(u16, 0), view(&terminal).cursor_row);
    try std.testing.expectEqual(@as(u16, 0), view(&terminal).cursor_col);
    try std.testing.expectEqual(.none, view(&terminal).cursor_shape);
    try std.testing.expect(view(&terminal).cursor_blink);
}

test "terminal cursor: DECSCUSR restores the canonical default and rejects unsupported values" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 2, 2);
    defer terminal.deinit();
    const cases = [_]struct { bytes: []const u8, shape: Terminal.CursorShape, blink: bool }{
        .{ .bytes = "\x1b[1 q", .shape = .block, .blink = true },
        .{ .bytes = "\x1b[2 q", .shape = .block, .blink = false },
        .{ .bytes = "\x1b[3 q", .shape = .underline, .blink = true },
        .{ .bytes = "\x1b[4 q", .shape = .underline, .blink = false },
        .{ .bytes = "\x1b[5 q", .shape = .bar, .blink = true },
        .{ .bytes = "\x1b[6 q", .shape = .bar, .blink = false },
    };
    for (cases) |case| {
        try std.testing.expect((try terminal.feed(case.bytes)).state_changed);
        try std.testing.expectEqual(case.shape, view(&terminal).cursor_shape);
        try std.testing.expectEqual(case.blink, view(&terminal).cursor_blink);
    }

    try std.testing.expect(!(try terminal.feed("\x1b[0 ")).state_changed);
    try std.testing.expect((try terminal.feed("q")).state_changed);
    try std.testing.expectEqual(.block, view(&terminal).cursor_shape);
    try std.testing.expect(view(&terminal).cursor_blink);
    try std.testing.expect(!(try terminal.feed("\x1b[ q\x1b[7 q\x1b[999999 q")).state_changed);
    try std.testing.expectEqual(.block, view(&terminal).cursor_shape);
    try std.testing.expect(view(&terminal).cursor_blink);

    try std.testing.expect((try terminal.feed("\x1bP$q q\x1b\\")).state_changed);
    try std.testing.expectEqualStrings("\x1bP1$r1 q\x1b\\", terminal.replyBytes());
}

test "terminal cursor: Kitty multiple-cursor forms are exact unsupported no-ops" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 4);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b[4 q")).state_changed);
    const before = view(&terminal);
    try std.testing.expect(!(try terminal.feed("\x1b[>100;29:2:1")).state_changed);
    try std.testing.expect(!(try terminal.feed(":2 q\x1b[> q")).state_changed);
    const after = view(&terminal);
    try std.testing.expectEqual(before.cursor_shape, after.cursor_shape);
    try std.testing.expectEqual(before.cursor_blink, after.cursor_blink);
    try std.testing.expectEqual(before.cursor_row, after.cursor_row);
    try std.testing.expectEqual(before.cursor_col, after.cursor_col);
    try std.testing.expectEqualStrings("", terminal.replyBytes());
}

test "terminal cursor: Kitty DCS restores each bank default across fragmented input" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 4);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed(
        "\x1b[1 q\x1b[?25l\x1b]12;#112233\x1b\\\x1b]21;cursor_text=#445566\x1b\\" ++
            "\x1b[?47h\x1b[2;3H\x1b[4 q",
    )).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1bP@kitty-restore-cursor\x18")).state_changed);
    try std.testing.expectEqual(.underline, view(&terminal).cursor_shape);
    try std.testing.expect(!view(&terminal).cursor_visible);
    try std.testing.expect(!(try terminal.feed("\x1bP@kitty-restore-cursor-appe")).state_changed);
    try std.testing.expect((try terminal.feed("arance|ignored\x1b\\")).state_changed);

    try std.testing.expectEqual(.block, view(&terminal).cursor_shape);
    try std.testing.expect(view(&terminal).cursor_blink);
    try std.testing.expectEqual(@as(u16, 1), view(&terminal).cursor_row);
    try std.testing.expectEqual(@as(u16, 2), view(&terminal).cursor_col);
    try std.testing.expect(view(&terminal).cursor_visible);
    try std.testing.expectEqual(@as(?Terminal.Rgb, null), terminal.presentation().cursor);
    try std.testing.expect(!(try terminal.feed("\x1bP@kitty-restore-cursor-appearance|\x1b\\")).state_changed);

    try std.testing.expect((try terminal.feed("\x1b[?47l")).state_changed);
    try std.testing.expectEqual(.block, view(&terminal).cursor_shape);
    try std.testing.expect((try terminal.feed("\x90@kitty-restore-cursor-appearance|x\x9c")).state_changed);
    try std.testing.expectEqual(.block, view(&terminal).cursor_shape);
    try std.testing.expect(view(&terminal).cursor_blink);
    try std.testing.expect(!(try terminal.feed("\x1bP@kitty-restore-cursor-appearance|x\x1b\\")).state_changed);
}

test "terminal cursor: savepoint restores presentation while caller colors remain current" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed(
        "\x1b[?5h\x1b[?6h\x1b[?7l\x1b[?25l\x1b[3;6H\x1b[6 q\x1b[1m" ++
            "\x1b]12;#112233\x1b\\\x1b]21;cursor_text=#445566\x1b\\\x1b)0\x1b7",
    )).state_changed);
    try std.testing.expect((try terminal.feed(
        "\x1b[1;1H\x1b[1 q\x1b[22m\x1b[?5l\x1b[?6l\x1b[?7h\x1b[?25h" ++
            "\x1b]12;#010203\x1b\\\x1b]21;cursor_text=#040506\x1b\\\x1b)B\x1b8X",
    )).state_changed);

    try std.testing.expectEqual(@as(u16, 2), view(&terminal).cursor_row);
    try std.testing.expectEqual(@as(u16, 6), view(&terminal).cursor_col);
    try std.testing.expectEqual(.bar, view(&terminal).cursor_shape);
    try std.testing.expect(!view(&terminal).cursor_blink);
    try std.testing.expect(!view(&terminal).cursor_visible);
    try std.testing.expect(view(&terminal).cellInfoAt(2, 5).attrs.bold);
    try std.testing.expect(terminal.presentation().reverse_screen);
    try std.testing.expectEqual(@as(?Terminal.Rgb, .{ .r = 1, .g = 2, .b = 3 }), terminal.presentation().cursor);
    try std.testing.expectEqual(@as(?Terminal.Rgb, .{ .r = 4, .g = 5, .b = 6 }), terminal.presentation().cursor_text);
}

test "terminal cursor: 1049 restores primary bank and 47 leaves banks independent" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();

    try feed(&terminal, "\x1b[3;4H\x1b[4 q\x1b[?1049h\x1b[2;2H\x1b[?1049l");
    try std.testing.expectEqual(@as(u16, 2), view(&terminal).cursor_row);
    try std.testing.expectEqual(@as(u16, 3), view(&terminal).cursor_col);
    try std.testing.expectEqual(.underline, view(&terminal).cursor_shape);
    try std.testing.expect(!view(&terminal).cursor_blink);

    try feed(&terminal, "\x1b[?47h\x1b[2;2H\x1b[1 q\x1b[?47l");
    try std.testing.expectEqual(@as(u16, 2), view(&terminal).cursor_row);
    try std.testing.expectEqual(@as(u16, 3), view(&terminal).cursor_col);
    try std.testing.expectEqual(.underline, view(&terminal).cursor_shape);
    try std.testing.expect(!view(&terminal).cursor_blink);
}

test "terminal cursor: presentation modes preserve exact bank and lifetime truth" {
    var terminal = try Terminal.init(std.testing.allocator, 4, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b[6 ")).state_changed);
    try std.testing.expect((try terminal.feed("q")).state_changed);
    try std.testing.expectEqual(.bar, view(&terminal).cursor_shape);
    try std.testing.expect(!view(&terminal).cursor_blink);
    try std.testing.expect(!(try terminal.feed("\x1b[6 q")).state_changed);

    try std.testing.expect((try terminal.feed("\x1b[?12h\x1b[?25l")).state_changed);
    try std.testing.expect(view(&terminal).cursor_blink);
    try std.testing.expect(!view(&terminal).cursor_visible);
    try std.testing.expect(!(try terminal.feed("\x1b[?12h\x1b[?25l")).state_changed);

    try std.testing.expect((try terminal.feed("\x1b[?12;25s")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?12l\x1b[?25h")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?12;25r")).state_changed);
    try std.testing.expect(view(&terminal).cursor_blink);
    try std.testing.expect(!view(&terminal).cursor_visible);
    try std.testing.expect((try terminal.feed("\x1b[?12$p\x1b[?25$p")).state_changed);
    try std.testing.expectEqualStrings("\x1b[?12;1$y\x1b[?25;2$y", terminal.replyBytes());
    try terminal.consumeReplyBytes(terminal.replyBytes().len);

    try std.testing.expect((try terminal.feed("\x1b[?47h")).state_changed);
    try std.testing.expectEqual(.none, view(&terminal).cursor_shape);
    try std.testing.expect(view(&terminal).cursor_blink);
    try std.testing.expect(!view(&terminal).cursor_visible);
    try std.testing.expect((try terminal.feed("\x1b[?12l")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b[?25l")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?47l")).state_changed);
    try std.testing.expectEqual(.bar, view(&terminal).cursor_shape);
    try std.testing.expect(view(&terminal).cursor_blink);
    try std.testing.expect(!view(&terminal).cursor_visible);

    try terminal.resize(6, 12);
    try std.testing.expectEqual(.bar, view(&terminal).cursor_shape);
    try std.testing.expect(view(&terminal).cursor_blink);
    try std.testing.expect(!view(&terminal).cursor_visible);

    try std.testing.expect((try terminal.feed("\x1b[2 q")).state_changed);
    try std.testing.expectEqual(.block, view(&terminal).cursor_shape);
    try std.testing.expect(!view(&terminal).cursor_blink);
    try std.testing.expect(!(try terminal.feed("\x1b[2 q")).state_changed);
    try std.testing.expect((try terminal.feed("\x1bc")).state_changed);
    try std.testing.expectEqual(.block, view(&terminal).cursor_shape);
    try std.testing.expect(view(&terminal).cursor_blink);
    try std.testing.expect(view(&terminal).cursor_visible);
}
