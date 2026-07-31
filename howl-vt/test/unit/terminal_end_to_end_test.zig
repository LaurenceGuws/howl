const std = @import("std");
const terminal_mod = @import("../../src/howl_vt.zig");
const reply_fill = @import("../support/reply_fill.zig");

const Terminal = terminal_mod.Terminal;

fn feed(terminal: *Terminal, bytes: []const u8) Terminal.FeedError!void {
    const summary = try terminal.feed(bytes);
    std.debug.assert(!summary.historyLost() or summary.stateChanged());
}

fn consumeReplies(terminal: *Terminal) !void {
    try terminal.consumeReplyBytes(terminal.replyBytes().len);
}

test "terminal: stream applies bytes to grid state deterministically" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try feed(&terminal, "ab");
    try feed(&terminal, "c");
    try feed(&terminal, "\r\nxy");

    const s = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'a'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'c'), s.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 'x'), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'y'), s.cellAt(1, 1));
    try std.testing.expectEqual(@as(u16, 1), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), s.cursor_col);
}

test "terminal: VT52 exit escape is an exact fragmented no-op" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 4);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b[31;1m\x1b[?1hABCD")).stateChanged());
    const sequence_before = terminal.semanticSequence();
    const before = terminal.semanticView(0).cellInfoAt(0, 3);
    try std.testing.expect(before.attrs.bold);
    try std.testing.expectEqual(Terminal.Color.indexed(1), before.attrs.fg);

    try std.testing.expect(!(try terminal.feed("\x1b")).stateChanged());
    try std.testing.expect(!(try terminal.feed("<")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b<\x1b<")).stateChanged());
    try std.testing.expectEqual(sequence_before, terminal.semanticSequence());
    const after = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u16, 0), after.cursor_row);
    try std.testing.expectEqual(@as(u16, 3), after.cursor_col);
    try std.testing.expectEqual(@as(u8, 0), terminal.consequenceCount());
    try std.testing.expect((try terminal.feed("\x1b[?1$p")).stateChanged());
    try std.testing.expectEqualStrings("\x1b[?1;1$y", terminal.replyBytes());
    try consumeReplies(&terminal);
    try std.testing.expectEqualStrings("", terminal.replyBytes());

    try std.testing.expect((try terminal.feed("E\x1b<\x1b[2;3HF")).stateChanged());
    const completed = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'E'), completed.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'F'), completed.cellAt(1, 2));
    try std.testing.expectEqual(@as(u16, 1), completed.cursor_row);
    try std.testing.expectEqual(@as(u16, 3), completed.cursor_col);
}

test "terminal: REP retains bounded glyph state and exact lifetime" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b[b")).stateChanged());
    try std.testing.expect((try terminal.feed("A\xcc\x81\xcc\xa7\xcc\x88\xcc\x84")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[")).stateChanged());
    try std.testing.expect((try terminal.feed("2b")).stateChanged());

    for (0..3) |col| {
        const cell = terminal.semanticView(0).cellInfoAt(0, @intCast(col));
        try std.testing.expectEqual(@as(u21, 'A'), cell.codepoint);
        try std.testing.expectEqual(@as(u8, 4), cell.combining_len);
        try std.testing.expectEqualSlices(u32, &.{ 0x301, 0x327, 0x308 }, cell.combining[0..3]);
        var retained: [24]u21 = undefined;
        try std.testing.expectEqualSlices(
            u21,
            &.{ 'A', 0x301, 0x327, 0x308, 0x304 },
            terminal.semanticView(0).cellScalarsAt(0, @intCast(col), &retained),
        );
    }

    try std.testing.expect((try terminal.feed("\x1b[32;4m\x1b[0b")).stateChanged());
    const defaulted = terminal.semanticView(0).cellInfoAt(0, 3);
    try std.testing.expectEqual(@as(u21, 'A'), defaulted.codepoint);
    try std.testing.expectEqual(@as(u8, 4), defaulted.combining_len);
    try std.testing.expectEqual(Terminal.Color.indexed(2), defaulted.attrs.fg);
    try std.testing.expect(defaulted.attrs.underline);

    // Parser-bounded counts remain allocation-free and use the ordinary
    // wrapping path rather than constructing a repeated glyph buffer.
    try std.testing.expect((try terminal.feed("\x1b[?7l\x1b[999999b")).stateChanged());
    try std.testing.expectEqual(@as(u21, 'A'), terminal.semanticView(0).cellAt(0, 7));
    try std.testing.expect(terminal.semanticView(0).cellInfoAt(0, 7).attrs.underline);
    try std.testing.expect((try terminal.feed("\x1b[?7h")).stateChanged());

    try std.testing.expect((try terminal.feed("\x1b[?1049h")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[3b")).stateChanged());
    try std.testing.expect((try terminal.feed("B\x1b[b")).stateChanged());
    try std.testing.expectEqual(@as(u21, 'B'), terminal.semanticView(0).cellAt(0, 1));

    try std.testing.expect((try terminal.feed("\x1b[?1049l")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[b")).stateChanged());
    const repeated = terminal.semanticView(0).cellInfoAt(0, 3);
    try std.testing.expectEqual(@as(u21, 'A'), repeated.codepoint);
    try std.testing.expectEqual(@as(u8, 4), repeated.combining_len);

    try terminal.resize(3, 10);
    try std.testing.expect((try terminal.feed("\x1b[b")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1bc")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[b")).stateChanged());
}

test "terminal: cursor savepoints retain exact bank reset and resize state" {
    var terminal = try Terminal.init(std.testing.allocator, 4, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b8")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[31;1m\x1b)0\x0e\x1b[?5h\x1b[3;4H")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b8")).stateChanged());
    try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_col);
    try std.testing.expect((try terminal.feed("q")).stateChanged());
    const default_savepoint_cell = terminal.semanticView(0).cellInfoAt(0, 0);
    try std.testing.expectEqual(@as(u21, 'q'), default_savepoint_cell.codepoint);
    try std.testing.expect(default_savepoint_cell.attrs.bold);
    try std.testing.expectEqual(Terminal.Color.indexed(1), default_savepoint_cell.attrs.fg);
    try std.testing.expect(!terminal.presentation().reverse_screen);
    terminal.hardReset();
    try std.testing.expect((try terminal.feed(
        "\x1b[31;1;3m" ++
            "\x1b[1\"q" ++
            "\x1b)0\x0e" ++
            "\x1b[?5h\x1b[?6h\x1b[?7h\x1b[?25l" ++
            "\x1b[2;8HZ",
    )).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b")).stateChanged());
    try std.testing.expect((try terminal.feed("7")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b7")).stateChanged());

    try std.testing.expect((try terminal.feed(
        "\x1b[0m\x1b[0\"q\x0f\x1b[?5l\x1b[?6l\x1b[?7l\x1b[?25h\x1b[1;1H",
    )).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[")).stateChanged());
    try std.testing.expect((try terminal.feed("u")).stateChanged());

    try std.testing.expectEqual(@as(u16, 1), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 7), terminal.semanticView(0).cursor_col);
    try std.testing.expect(!terminal.semanticView(0).cursor_visible);
    try std.testing.expect(terminal.presentation().reverse_screen);
    try std.testing.expect((try terminal.feed("q")).stateChanged());
    const restored_cell = terminal.semanticView(0).cellInfoAt(2, 0);
    try std.testing.expectEqual(@as(u21, 0x2500), restored_cell.codepoint);
    try std.testing.expect(restored_cell.attrs.bold);
    try std.testing.expect(restored_cell.attrs.italic);
    try std.testing.expect(restored_cell.attrs.protected == .dec);
    try std.testing.expect((try terminal.feed("\x1b[?6$p\x1b[?7$p")).stateChanged());
    try std.testing.expectEqualStrings("\x1b[?6;1$y\x1b[?7;1$y", terminal.replyBytes());
    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed("\x1b[u")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[s")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[u")).stateChanged());

    try std.testing.expect((try terminal.feed("\x1b[?47hB\x1b[s\x1b[1;4HC\x1b[u")).stateChanged());
    try std.testing.expectEqual(@as(u16, 1), terminal.semanticView(0).cursor_col);
    try std.testing.expect((try terminal.feed("\x1b[?47l")).stateChanged());
    try std.testing.expectEqual(@as(u16, 7), terminal.semanticView(0).cursor_col);

    try terminal.resize(4, 5);
    try std.testing.expect((try terminal.feed("\x1b[1;1H\x1b[u")).stateChanged());
    try std.testing.expectEqual(@as(u16, 4), terminal.semanticView(0).cursor_col);
    try std.testing.expect((try terminal.feed("q")).stateChanged());
    try std.testing.expectEqual(@as(u21, 0x2500), terminal.semanticView(0).cellAt(2, 0));

    try std.testing.expect((try terminal.feed("\x1b[?1;1000;1004;1006;2004h\x1b[2;4;20h")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1bc")).stateChanged());
    try std.testing.expect((try terminal.feed(
        "\x1b[?1$p\x1b[?1000$p\x1b[?1004$p\x1b[?1006$p\x1b[?2004$p\x1b[2$p\x1b[4$p\x1b[20$p",
    )).stateChanged());
    try std.testing.expectEqualStrings(
        "\x1b[?1;2$y\x1b[?1000;2$y\x1b[?1004;2$y\x1b[?1006;2$y\x1b[?2004;2$y" ++
            "\x1b[2;2$y\x1b[4;2$y\x1b[20;2$y",
        terminal.replyBytes(),
    );
    try std.testing.expect(!(try terminal.feed("\x1b8")).stateChanged());
}

test "terminal: ISO-8859-1 and UTF-8 selection own exact decoding lifetime" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 12);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b%")).stateChanged());
    try std.testing.expect((try terminal.feed("@")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b%@")).stateChanged());
    try std.testing.expect((try terminal.feed("\xe9\xc3\xa9")).stateChanged());
    try std.testing.expectEqual(@as(u21, 0xE9), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0xC3), terminal.semanticView(0).cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 0xA9), terminal.semanticView(0).cellAt(0, 2));

    try std.testing.expect(!(try terminal.feed("\x1b%X")).stateChanged());
    try std.testing.expect((try terminal.feed("\xe9")).stateChanged());
    try std.testing.expectEqual(@as(u21, 0xE9), terminal.semanticView(0).cellAt(0, 3));

    try std.testing.expect((try terminal.feed("\x9b2;1H")).stateChanged());
    try std.testing.expectEqual(@as(u16, 1), terminal.semanticView(0).cursor_row);
    try std.testing.expect(!(try terminal.feed("\x1b%")).stateChanged());
    try std.testing.expect((try terminal.feed("G")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\xc3")).stateChanged());
    try std.testing.expect((try terminal.feed("\xa9")).stateChanged());
    try std.testing.expectEqual(@as(u21, 0xE9), terminal.semanticView(0).cellAt(1, 0));
    try std.testing.expect(!(try terminal.feed("\x1b%G")).stateChanged());

    try std.testing.expect((try terminal.feed("\x1b%@\xe9\x1bc")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\xe9")).stateChanged());
    try std.testing.expect(!(try terminal.feed("X")).stateChanged());
    try std.testing.expect((try terminal.feed("\xc3\xa9")).stateChanged());
    try std.testing.expectEqual(@as(u21, 0xE9), terminal.semanticView(0).cellAt(0, 0));
}

test "terminal: erase families retain exact ranges protection geometry and mutation" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 3, 8, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("ABCDEFGH" ++ "I")).stateChanged());

    try std.testing.expect((try terminal.feed("\x1b[2;1H\x1b[1\"qP\x1b[0\"qqrs")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[48;2;40;44;52m\x1b[2;2H")).stateChanged());
    const cursor_row_before = terminal.semanticView(0).cursor_row;
    const cursor_col_before = terminal.semanticView(0).cursor_col;
    try std.testing.expect(!(try terminal.feed("\x1b[?0")).stateChanged());
    try std.testing.expect((try terminal.feed("K")).stateChanged());
    try std.testing.expectEqual(cursor_row_before, terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(cursor_col_before, terminal.semanticView(0).cursor_col);
    try std.testing.expectEqual(@as(u21, 'P'), terminal.semanticView(0).cellAt(1, 0));
    for (1..8) |col| {
        const cell = terminal.semanticView(0).cellInfoAt(1, @intCast(col));
        try std.testing.expectEqual(@as(u21, 0), cell.codepoint);
        try std.testing.expectEqual(Terminal.Color.rgbComponents(40, 44, 52), cell.attrs.bg);
    }

    try std.testing.expect((try terminal.feed("\x1b[2;2Hqr\x1b[2;2H\x1b[?1K")).stateChanged());
    try std.testing.expectEqual(@as(u21, 'P'), terminal.semanticView(0).cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(1, 1));
    try std.testing.expectEqual(@as(u21, 'r'), terminal.semanticView(0).cellAt(1, 2));
    try std.testing.expect((try terminal.feed("\x1b[?2K")).stateChanged());
    try std.testing.expectEqual(@as(u21, 'P'), terminal.semanticView(0).cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(1, 2));
    try std.testing.expect(!(try terminal.feed("\x1b[?2K")).stateChanged());

    try std.testing.expect((try terminal.feed("\x1b[2K")).stateChanged());
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(1, 0));
    try std.testing.expect(!(try terminal.feed("\x1b[2K")).stateChanged());

    try std.testing.expect((try terminal.feed("\x1b[1;4H\x1b[0K")).stateChanged());
    try std.testing.expectEqual(@as(u21, 'A'), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'C'), terminal.semanticView(0).cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(0, 3));

    try std.testing.expect((try terminal.feed("\x1b[2;1Habc\x1b[2;2H\x1b[1K")).stateChanged());
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(1, 1));
    try std.testing.expectEqual(@as(u21, 'c'), terminal.semanticView(0).cellAt(1, 2));
    try std.testing.expect((try terminal.feed("\x1b[1;1HZ\x1b[2;1Habc\x1b[2;2H\x1b[1J")).stateChanged());
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(1, 1));
    try std.testing.expectEqual(@as(u21, 'c'), terminal.semanticView(0).cellAt(1, 2));

    try std.testing.expect((try terminal.feed("\x1b[3;1H\x1b#6WXYZ\x1b[3;2H")).stateChanged());
    try std.testing.expectEqual(Terminal.LineGeometry.double_width, terminal.semanticView(0).lineGeometry(2));
    const ech_cursor_row = terminal.semanticView(0).cursor_row;
    const ech_cursor_col = terminal.semanticView(0).cursor_col;
    try std.testing.expect(!(try terminal.feed("\x1b[999")).stateChanged());
    try std.testing.expect((try terminal.feed("X")).stateChanged());
    try std.testing.expectEqual(ech_cursor_row, terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(ech_cursor_col, terminal.semanticView(0).cursor_col);
    try std.testing.expectEqual(@as(u21, 'W'), terminal.semanticView(0).cellAt(2, 0));
    for (1..4) |col| {
        try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(2, @intCast(col)));
    }
    try std.testing.expectEqual(Terminal.LineGeometry.double_width, terminal.semanticView(0).lineGeometry(2));
    try std.testing.expect((try terminal.feed("Q\x1b[3;2H\x1b[X")).stateChanged());
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(2, 1));
    try std.testing.expect(!(try terminal.feed("\x1b[X")).stateChanged());

    const invalid_cursor_row = terminal.semanticView(0).cursor_row;
    const invalid_cursor_col = terminal.semanticView(0).cursor_col;
    try std.testing.expect(!(try terminal.feed("\x1b[9K\x1b[?9K\x1b[9J\x1b[?9J")).stateChanged());
    try std.testing.expectEqual(invalid_cursor_row, terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(invalid_cursor_col, terminal.semanticView(0).cursor_col);

    try std.testing.expect((try terminal.feed("\x1b[1;1H\x1b#6L\x1b[2;1Hline\x1b[2;3H\x1b[0J")).stateChanged());
    try std.testing.expectEqual(Terminal.LineGeometry.double_width, terminal.semanticView(0).lineGeometry(0));
    try std.testing.expectEqual(Terminal.LineGeometry.single_width, terminal.semanticView(0).lineGeometry(2));
    try std.testing.expectEqual(@as(u21, 'l'), terminal.semanticView(0).cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'i'), terminal.semanticView(0).cellAt(1, 1));
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(1, 2));
    try std.testing.expect(!(try terminal.feed("\x1b[0J")).stateChanged());

    try std.testing.expect((try terminal.feed(
        "\x1b[2J\x1b[1;1H\x1b[1\"qA\x1b[0\"qB" ++
            "\x1b[2;1H\x1b[1\"qC\x1b[0\"qD\x1b[1;2H\x1b[?0J",
    )).stateChanged());
    try std.testing.expectEqual(@as(u21, 'A'), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'C'), terminal.semanticView(0).cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(1, 1));
    try std.testing.expect((try terminal.feed("\x1b[1;2HB\x1b[2;2HD\x1b[2;2H\x1b[?1J")).stateChanged());
    try std.testing.expectEqual(@as(u21, 'A'), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'C'), terminal.semanticView(0).cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(1, 1));
    try std.testing.expect(!(try terminal.feed("\x1b[?2J")).stateChanged());

    try std.testing.expect((try terminal.feed("\x1b[1;2HT\x1b[?2J")).stateChanged());
    try std.testing.expectEqual(@as(u21, 'A'), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(0, 1));
    try std.testing.expect((try terminal.feed("\x1b[2J")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[2J")).stateChanged());

    try std.testing.expect((try terminal.feed("\x1b[1;1H\x1b[1\"qS\x1b[0\"qT\x1b[?2J")).stateChanged());
    try std.testing.expectEqual(@as(u21, 'S'), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(0, 1));
    try std.testing.expect((try terminal.feed("\x1b[2J")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[2J")).stateChanged());

    try std.testing.expect((try terminal.feed("one\r\ntwo\r\nthree\r\nfour")).stateChanged());
    try std.testing.expect(terminal.semanticView(0).history_count > 0);
    try std.testing.expect((try terminal.feed("\x1b[3J")).stateChanged());
    try std.testing.expectEqual(@as(u32, 0), terminal.semanticView(0).history_count);
    try std.testing.expect(!(try terminal.feed("\x1b[3J")).stateChanged());
    try std.testing.expect((try terminal.feed("five\r\nsix\r\nseven\r\neight")).stateChanged());
    try std.testing.expect(terminal.semanticView(0).history_count > 0);
    try std.testing.expect((try terminal.feed("\x1b[?3J")).stateChanged());
    try std.testing.expectEqual(@as(u32, 0), terminal.semanticView(0).history_count);
}

test "terminal: ISO and DEC protection retain distinct erase semantics" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 6);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b")).stateChanged());
    try std.testing.expect((try terminal.feed("V")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1bV")).stateChanged());
    try std.testing.expect((try terminal.feed("A\x1b[0mB\x1bWC")).stateChanged());
    try std.testing.expect(terminal.semanticView(0).cellInfoAt(0, 0).attrs.protected == .iso);
    try std.testing.expect(terminal.semanticView(0).cellInfoAt(0, 1).attrs.protected == .iso);
    try std.testing.expect(terminal.semanticView(0).cellInfoAt(0, 2).attrs.protected == .none);

    try std.testing.expect((try terminal.feed("\r\x1b[2K")).stateChanged());
    try std.testing.expectEqual(@as(u21, 'A'), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), terminal.semanticView(0).cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(0, 2));
    try std.testing.expect(!(try terminal.feed("\x1b[2K")).stateChanged());

    try std.testing.expect((try terminal.feed("\x1b[2;1H\x1b[1\"qD\x1b[0mE\x1b[2\"qF")).stateChanged());
    try std.testing.expect(terminal.semanticView(0).cellInfoAt(1, 0).attrs.protected == .dec);
    try std.testing.expect(terminal.semanticView(0).cellInfoAt(1, 1).attrs.protected == .dec);
    try std.testing.expect((try terminal.feed("\r\x1b[2K")).stateChanged());
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(1, 1));

    try std.testing.expect((try terminal.feed("\x96D\x1b[0mE\x97F\r\x1b[?2K")).stateChanged());
    try std.testing.expectEqual(@as(u21, 'D'), terminal.semanticView(0).cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'E'), terminal.semanticView(0).cellAt(1, 1));
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(1, 2));
    try std.testing.expect(!(try terminal.feed("\x97")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[0\"q")).stateChanged());
}

test "terminal: erase mutation owns pending wrap and retained continuation" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 4);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("ABCD")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[0J")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[0J")).stateChanged());

    try std.testing.expect((try terminal.feed("\x1b[1;4HX")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[0K")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[0K")).stateChanged());

    try std.testing.expect((try terminal.feed("\x1b[1;4HX")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[X")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[X")).stateChanged());

    terminal.hardReset();
    try std.testing.expect((try terminal.feed("\x1b[1\"qABCDE\x1b[1;1H")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[?2K")).stateChanged());
    try std.testing.expectEqual(@as(u21, 'A'), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'D'), terminal.semanticView(0).cellAt(0, 3));
    try std.testing.expect(!(try terminal.feed("\x1b[?2K")).stateChanged());
}

test "terminal: rectangle erase owns exact pending wrap mutation" {
    var terminal = try Terminal.init(std.testing.allocator, 1, 4);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("\x1bV    ")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1bW")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[1;1;1;4$z")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[1;1;1;4$z")).stateChanged());

    try std.testing.expect((try terminal.feed("\x1b[1\"q ")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[1;1;1;4${")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[1;1;1;4${")).stateChanged());
}

test "terminal: rendition protection and rectangle owners report exact mutation" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 4);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b[31m")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[31m")).stateChanged());
    try std.testing.expect((try terminal.feed("ABCD\x1b[2;1HEFGH\x1b[3;1HIJKL")).stateChanged());

    try std.testing.expect((try terminal.feed("\x1b[1;1;2;2;1$r")).stateChanged());
    try std.testing.expect(terminal.semanticView(0).cellInfoAt(0, 0).attrs.bold);
    try std.testing.expect(terminal.semanticView(0).cellInfoAt(1, 1).attrs.bold);
    try std.testing.expect(!(try terminal.feed("\x1b[1;1;2;2;1$r")).stateChanged());

    try std.testing.expect((try terminal.feed("\x1b[2*x")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[2*x")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[1\"q")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[1\"q")).stateChanged());

    try std.testing.expect((try terminal.feed("\x1b[88;1;1;1")).stateChanged() == false);
    try std.testing.expect((try terminal.feed(";2$x")).stateChanged());
    try std.testing.expectEqual(@as(u21, 'X'), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'X'), terminal.semanticView(0).cellAt(0, 1));
    try std.testing.expect(!(try terminal.feed("\x1b[88;1;1;1;2$x")).stateChanged());

    try std.testing.expect(!(try terminal.feed("\x1b[1;1;1;2;1;1;1;1$v")).stateChanged());
    const before = terminal.semanticView(0).cellInfoAt(2, 3);
    try std.testing.expect(!(try terminal.feed("\x1b[3;4;2;1;1$r")).stateChanged());
    try std.testing.expectEqualDeep(before, terminal.semanticView(0).cellInfoAt(2, 3));
}

test "terminal: ANSI insert and newline modes retain exact global lifetime" {
    var terminal = try Terminal.init(std.testing.allocator, 4, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("ABCD\x1b[1;2H")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[4;20")).stateChanged());
    try std.testing.expect((try terminal.feed("h")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[4;20h")).stateChanged());
    try std.testing.expect((try terminal.feed("X")).stateChanged());
    try std.testing.expectEqual(@as(u21, 'A'), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'X'), terminal.semanticView(0).cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'B'), terminal.semanticView(0).cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 'C'), terminal.semanticView(0).cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'D'), terminal.semanticView(0).cellAt(0, 4));

    try std.testing.expect((try terminal.feed("\x1b[1;5H\n")).stateChanged());
    try std.testing.expectEqual(@as(u16, 1), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_col);
    try std.testing.expect((try terminal.feed("\x1b[2;5H\x0b")).stateChanged());
    try std.testing.expectEqual(@as(u16, 2), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_col);
    try std.testing.expect((try terminal.feed("\x1b[3;5H\x0c")).stateChanged());
    try std.testing.expectEqual(@as(u16, 3), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_col);

    try std.testing.expect((try terminal.feed("\x1b[?47hAB\x1b[1GZ")).stateChanged());
    try std.testing.expectEqual(@as(u21, 'Z'), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'A'), terminal.semanticView(0).cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'B'), terminal.semanticView(0).cellAt(0, 2));
    try std.testing.expect((try terminal.feed("\x1b[?47l")).stateChanged());

    try terminal.resize(5, 10);
    try std.testing.expect((try terminal.feed("\x1b[4$p\x1b[20$p")).stateChanged());
    try std.testing.expectEqualStrings("\x1b[4;1$y\x1b[20;1$y", terminal.replyBytes());
    try terminal.consumeReplyBytes(terminal.replyBytes().len);

    try std.testing.expect((try terminal.feed("\x1b[20l\x1b[1;5H\n")).stateChanged());
    try std.testing.expectEqual(@as(u16, 1), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 4), terminal.semanticView(0).cursor_col);
    try std.testing.expect((try terminal.feed("\x1bc")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[4$p\x1b[20$p")).stateChanged());
    try std.testing.expectEqualStrings("\x1b[4;2$y\x1b[20;2$y", terminal.replyBytes());
}

test "terminal: XTPUSHSGR restores selected rendition with bounded stack truth" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 16);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b[#}")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[1;31;44mS\x1b[1;30#")).stateChanged());
    try std.testing.expect((try terminal.feed("{")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[3;32;45m\x1b[#qA")).stateChanged());

    const saved = terminal.semanticView(0).cellInfoAt(0, 0).attrs;
    const selected = terminal.semanticView(0).cellInfoAt(0, 1).attrs;
    try std.testing.expect(selected.bold);
    try std.testing.expect(selected.italic);
    try std.testing.expectEqual(saved.fg, selected.fg);
    try std.testing.expect(!std.meta.eql(selected.bg, saved.bg));

    try std.testing.expect((try terminal.feed("\x1b[#{\x1b[#{\x1b[22;23;39;49m\x1b[#}\x1b[#}B")).stateChanged());
    const nested = terminal.semanticView(0).cellInfoAt(0, 2).attrs;
    try std.testing.expect(selected.bold == nested.bold);
    try std.testing.expect(selected.italic == nested.italic);
    try std.testing.expectEqual(selected.fg, nested.fg);
    try std.testing.expectEqual(selected.bg, nested.bg);

    try std.testing.expect((try terminal.feed(
        "\x1b[1;2;3;4:2;5;7;8;9;38:2::1:2:3;48:2::4:5:6m" ++
            "\x1b[#p\x1b[0m\x1b[#}C",
    )).stateChanged());
    const complete = terminal.semanticView(0).cellInfoAt(0, 3).attrs;
    try std.testing.expect(complete.bold);
    try std.testing.expect(complete.dim);
    try std.testing.expect(complete.italic);
    try std.testing.expect(complete.blink);
    try std.testing.expect(complete.reverse);
    try std.testing.expect(complete.invisible);
    try std.testing.expect(complete.underline);
    try std.testing.expect(complete.strikethrough);
    try std.testing.expectEqual(Terminal.UnderlineStyle.double, complete.underline_style);
    try std.testing.expectEqual(Terminal.Color.rgbComponents(1, 2, 3), complete.fg);
    try std.testing.expectEqual(Terminal.Color.rgbComponents(4, 5, 6), complete.bg);

    try std.testing.expect((try terminal.feed("\x1b[4m\x1b[21#{\x1b[24m\x1b[#}D")).stateChanged());
    try std.testing.expect(!terminal.semanticView(0).cellInfoAt(0, 4).attrs.underline);

    var pushes: u8 = 0;
    while (pushes < 10) : (pushes += 1)
        try std.testing.expect((try terminal.feed("\x1b[#{")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[#{")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[#}")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[#{")).stateChanged());
}

test "terminal: XTPUSHSGR stack spans resize screen switches and reset" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 2, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b[1;38;2;1;2;3m\x1b[#{\x1b[22;39m")).stateChanged());
    try terminal.resize(3, 12);
    try std.testing.expect((try terminal.feed("\x1b[#}R")).stateChanged());
    const restored = terminal.semanticView(0).cellInfoAt(0, 0).attrs;
    try std.testing.expect(restored.bold);
    try std.testing.expectEqual(Terminal.Color.rgbComponents(1, 2, 3), restored.fg);

    try std.testing.expect((try terminal.feed("\x1b[31mP\x1b[#{\x1b[?1049h\x1b[32m\x1b[#}A")).stateChanged());
    const alternate = terminal.semanticView(0).cellInfoAt(0, 0).attrs;
    try std.testing.expectEqual(Terminal.Color.indexed(1), alternate.fg);
    try std.testing.expect((try terminal.feed("\x1b[?1049l")).stateChanged());

    try std.testing.expect((try terminal.feed("\x1b[31m\x1b[#{\x1bc")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[#}S")).stateChanged());
    const reset_restored = terminal.semanticView(0).cellInfoAt(0, 0).attrs;
    try std.testing.expect(!std.meta.eql(Terminal.default_cell_attrs.fg, reset_restored.fg));
}

test "terminal: C0 controls retain exact stream effects" {
    const allocator = std.testing.allocator;

    {
        var terminal = try Terminal.init(allocator, 3, 16);
        defer terminal.deinit();
        try std.testing.expect(!(try terminal.feed("\x07")).historyLost());
        try std.testing.expectEqual(@as(u64, 1), terminal.consequenceHead().?.bell.id);
    }
    {
        var terminal = try Terminal.init(allocator, 3, 16);
        defer terminal.deinit();
        try std.testing.expect(!(try terminal.feed("ab\x08X")).historyLost());
        try std.testing.expectEqual(@as(u21, 'a'), terminal.semanticView(0).cellAt(0, 0));
        try std.testing.expectEqual(@as(u21, 'X'), terminal.semanticView(0).cellAt(0, 1));
    }
    {
        var terminal = try Terminal.init(allocator, 3, 16);
        defer terminal.deinit();
        try std.testing.expect(!(try terminal.feed("\x1b[3gABC\x1bH\r\x09X")).historyLost());
        try std.testing.expectEqual(@as(u21, 'X'), terminal.semanticView(0).cellAt(0, 3));
    }
    for ([_]u8{ 0x0A, 0x0B, 0x0C }) |control| {
        var terminal = try Terminal.init(allocator, 3, 16);
        defer terminal.deinit();
        try std.testing.expect(!(try terminal.feed(&.{ 'A', control, 'B' })).historyLost());
        try std.testing.expectEqual(@as(u21, 'B'), terminal.semanticView(0).cellAt(1, 1));
    }
    {
        var terminal = try Terminal.init(allocator, 3, 16);
        defer terminal.deinit();
        try std.testing.expect(!(try terminal.feed("ab\x0dX")).historyLost());
        try std.testing.expectEqual(@as(u21, 'X'), terminal.semanticView(0).cellAt(0, 0));
        try std.testing.expectEqual(@as(u21, 'b'), terminal.semanticView(0).cellAt(0, 1));
    }
    {
        var terminal = try Terminal.init(allocator, 3, 16);
        defer terminal.deinit();
        try std.testing.expect(!(try terminal.feed("\x1b)0\x0eq\x0fq")).historyLost());
        try std.testing.expectEqual(@as(u21, 0x2500), terminal.semanticView(0).cellAt(0, 0));
        try std.testing.expectEqual(@as(u21, 'q'), terminal.semanticView(0).cellAt(0, 1));
    }
}

test "terminal: G0 G1 designation maps implemented repertoires across split feeds" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 64);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b(")).stateChanged());
    try std.testing.expect((try terminal.feed("0")).stateChanged());
    try std.testing.expect(!(try terminal.feed("+,-.0_`abcdefghijklmnopqrstuvwxyz{|}~")).historyLost());
    const dec = [_]u21{
        0x2192, 0x2190, 0x2191, 0x2193, 0x2588,
        0x00A0, 0x25C6, 0x2592, 0x2409, 0x240C,
        0x240D, 0x240A, 0x00B0, 0x00B1, 0x2591,
        0x240B, 0x2518, 0x2510, 0x250C, 0x2514,
        0x253C, 0x23BA, 0x23BB, 0x2500, 0x23BC,
        0x23BD, 0x251C, 0x2524, 0x2534, 0x252C,
        0x2502, 0x2264, 0x2265, 0x03C0, 0x2260,
        0x00A3, 0x00B7,
    };
    for (dec, 0..) |expected, col|
        try std.testing.expectEqual(expected, terminal.semanticView(0).cellAt(0, @intCast(col)));

    try std.testing.expect(!(try terminal.feed("\x1b)")).stateChanged());
    try std.testing.expect((try terminal.feed("A\x0e#A\x0f#")).stateChanged());
    try std.testing.expectEqual(@as(u21, 0x00A3), terminal.semanticView(0).cellAt(0, 37));
    try std.testing.expectEqual(@as(u21, 'A'), terminal.semanticView(0).cellAt(0, 38));
    try std.testing.expectEqual(@as(u21, '#'), terminal.semanticView(0).cellAt(0, 39));

    try std.testing.expect((try terminal.feed("\x1b(U")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b(0")).stateChanged());
    try std.testing.expect((try terminal.feed("_")).stateChanged());
    try std.testing.expectEqual(@as(u21, 0x00A0), terminal.semanticView(0).cellAt(0, 40));

    try terminal.resize(2, 64);
    try std.testing.expect(!(try terminal.feed("\r\n\r\nq")).historyLost());
    try std.testing.expectEqual(@as(u21, 0x2500), terminal.semanticView(0).cellAt(1, 0));

    try std.testing.expect((try terminal.feed("\x1bc#_")).stateChanged());
    try std.testing.expectEqual(@as(u21, '#'), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, '_'), terminal.semanticView(0).cellAt(0, 1));
}

test "terminal: repeated locking shifts are stable and real selection advances once" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b)0")).stateChanged());
    const before_gl = terminal.semanticSequence();
    try std.testing.expect((try terminal.feed("\x0e")).stateChanged());
    try std.testing.expectEqual(before_gl + 1, terminal.semanticSequence());
    const after_gl = terminal.semanticSequence();
    try std.testing.expect(!(try terminal.feed("\x0e")).stateChanged());
    try std.testing.expectEqual(after_gl, terminal.semanticSequence());

    try std.testing.expect((try terminal.feed("\x0f")).stateChanged());
    try std.testing.expectEqual(after_gl + 1, terminal.semanticSequence());
    const after_gr = terminal.semanticSequence();
    try std.testing.expect(!(try terminal.feed("\x0f")).stateChanged());
    try std.testing.expectEqual(after_gr, terminal.semanticSequence());
}

test "terminal: four charset slots share locking single-shift save and reset ownership" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 32);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b*")).stateChanged());
    try std.testing.expect((try terminal.feed("0\x1b+A")).stateChanged());

    try std.testing.expect((try terminal.feed("\x1bnq\x1bo#")).stateChanged());
    try std.testing.expectEqual(@as(u21, 0x2500), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0x00A3), terminal.semanticView(0).cellAt(0, 1));

    try std.testing.expect((try terminal.feed("\x0f")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b")).stateChanged());
    try std.testing.expect((try terminal.feed("N\x07qz\x8f#x")).stateChanged());
    try std.testing.expectEqual(@as(u21, 0x2500), terminal.semanticView(0).cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 'z'), terminal.semanticView(0).cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 0x00A3), terminal.semanticView(0).cellAt(0, 4));
    try std.testing.expectEqual(@as(u21, 'x'), terminal.semanticView(0).cellAt(0, 5));

    try std.testing.expect((try terminal.feed("\x1bO#\x8eq")).stateChanged());
    try std.testing.expectEqual(@as(u21, 0x00A3), terminal.semanticView(0).cellAt(0, 6));
    try std.testing.expectEqual(@as(u21, 0x2500), terminal.semanticView(0).cellAt(0, 7));

    try std.testing.expect((try terminal.feed("\x1b}ñ")).stateChanged());
    try std.testing.expectEqual(@as(u21, 0x2500), terminal.semanticView(0).cellAt(0, 8));
    try std.testing.expect((try terminal.feed("\x1b)A\x1b~£")).stateChanged());
    try std.testing.expectEqual(@as(u21, 0x00A3), terminal.semanticView(0).cellAt(0, 9));

    try std.testing.expect((try terminal.feed("\x1b|ñ")).stateChanged());
    try std.testing.expectEqual(@as(u21, 0x00F1), terminal.semanticView(0).cellAt(0, 10));

    try std.testing.expect((try terminal.feed("\x1bo\x1b7\x1b(B\x1b)B\x1b*B\x1b+B\x0f\x1bN")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b8")).stateChanged());
    try std.testing.expect((try terminal.feed("#")).stateChanged());
    try std.testing.expectEqual(@as(u21, 0x00a3), terminal.semanticView(0).cellAt(0, 11));

    try std.testing.expect((try terminal.feed("\x1b*U\x1b+V")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1bc")).stateChanged());
    try std.testing.expect((try terminal.feed("#")).stateChanged());
    try std.testing.expectEqual(@as(u21, '#'), terminal.semanticView(0).cellAt(0, 0));
}

test "terminal: Kitty CP437 and VAX42 share existing charset lifetime" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 32);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b)")).stateChanged());
    try std.testing.expect((try terminal.feed("U")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b)U")).stateChanged());
    try std.testing.expect((try terminal.feed("\xC2\xA0³àþÿ")).stateChanged());
    try std.testing.expectEqual(@as(u21, 0x00E1), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0x2502), terminal.semanticView(0).cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 0x03B1), terminal.semanticView(0).cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 0x25A0), terminal.semanticView(0).cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 0x00FF), terminal.semanticView(0).cellAt(0, 4));

    try std.testing.expect((try terminal.feed("\x1b*V\x1bN!?")).stateChanged());
    try std.testing.expectEqual(@as(u21, 0x043B), terminal.semanticView(0).cellAt(0, 5));
    try std.testing.expectEqual(@as(u21, '?'), terminal.semanticView(0).cellAt(0, 6));

    try std.testing.expect((try terminal.feed("\x1b(V\x1b7\x1b(B\x1b8!?ahortu")).stateChanged());
    const vax = [_]u21{ 0x043B, 0x0435, 0x0441, 0x0435, 0x043A, 0x0442, 0x043B, 0x0435 };
    for (vax, 0..) |expected, index|
        try std.testing.expectEqual(expected, terminal.semanticView(0).cellAt(0, @intCast(index + 7)));
    try std.testing.expect((try terminal.feed("\x1b)V³")).stateChanged());
    try std.testing.expectEqual(@as(u21, 0x2502), terminal.semanticView(0).cellAt(0, 15));

    try std.testing.expect(!(try terminal.feed("\x1b(X")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1bc!")).stateChanged());
    try std.testing.expectEqual(@as(u21, '!'), terminal.semanticView(0).cellAt(0, 0));
}

test "terminal: DEC line geometry owns width movement scroll resize reset and visual observation" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 4, 10, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("abcdef\x1b#6")).stateChanged());
    try std.testing.expectEqual(Terminal.LineGeometry.double_width, terminal.semanticView(0).lineGeometry(0));
    try std.testing.expectEqual(@as(u16, 4), terminal.semanticView(0).cursor_col);
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(0, 5));

    try std.testing.expect((try terminal.feed("\r\x1b[99CX")).stateChanged());
    try std.testing.expectEqual(@as(u21, 'X'), terminal.semanticView(0).cellAt(0, 4));
    try std.testing.expect((try terminal.feed("\x1b[2K")).stateChanged());
    try std.testing.expectEqual(Terminal.LineGeometry.double_width, terminal.semanticView(0).lineGeometry(0));
    try std.testing.expect((try terminal.feed("\x1b#5\x1b[99GZ")).stateChanged());
    try std.testing.expectEqual(Terminal.LineGeometry.single_width, terminal.semanticView(0).lineGeometry(0));
    try std.testing.expectEqual(@as(u21, 'Z'), terminal.semanticView(0).cellAt(0, 9));

    try std.testing.expect((try terminal.feed("\x1b[2;1H\x1b#6\x1b[3;1H\x1b#3\x1b[4;1H\x1b#4")).stateChanged());
    try std.testing.expectEqual(Terminal.LineGeometry.double_width, terminal.semanticView(0).lineGeometry(1));
    try std.testing.expectEqual(Terminal.LineGeometry.double_height_top, terminal.semanticView(0).lineGeometry(2));
    try std.testing.expectEqual(Terminal.LineGeometry.double_height_bottom, terminal.semanticView(0).lineGeometry(3));

    try std.testing.expect((try terminal.feed("\x1b[2;4r\x1b[4;1H\x1bD")).stateChanged());
    try std.testing.expectEqual(Terminal.LineGeometry.double_height_top, terminal.semanticView(0).lineGeometry(1));
    try std.testing.expectEqual(Terminal.LineGeometry.double_height_bottom, terminal.semanticView(0).lineGeometry(2));
    try std.testing.expectEqual(Terminal.LineGeometry.single_width, terminal.semanticView(0).lineGeometry(3));

    try std.testing.expect((try terminal.feed("\x1b[2;1H\x1b#5")).stateChanged());

    try std.testing.expect((try terminal.feed("\x1b[3;1H\x1b#3")).stateChanged());
    var view = terminal.semanticView(0);
    try std.testing.expectEqual(Terminal.LineGeometry.double_height_top, view.lineGeometry(2));
    try terminal.resize(5, 12);
    view = terminal.semanticView(0);
    try std.testing.expectEqual(Terminal.LineGeometry.single_width, view.lineGeometry(2));
    try std.testing.expect((try terminal.feed("\x1b[3;1H\x1b#3")).stateChanged());

    const cursor_row_before_alignment = terminal.semanticView(0).cursor_row;
    const cursor_col_before_alignment = terminal.semanticView(0).cursor_col;
    try std.testing.expect((try terminal.feed("\x1b#8")).stateChanged());
    view = terminal.semanticView(0);
    for (0..view.rows) |row| for (0..view.cols) |col| {
        const expected: u21 = if (row == 2 and col >= 6) 0 else 'E';
        try std.testing.expectEqual(expected, view.cellAt(@intCast(row), @intCast(col)));
    };
    try std.testing.expectEqual(cursor_row_before_alignment, terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(cursor_col_before_alignment, terminal.semanticView(0).cursor_col);
    try std.testing.expectEqual(Terminal.LineGeometry.double_height_top, view.lineGeometry(2));

    try std.testing.expect((try terminal.feed("\x1b[?69h")).stateChanged());
    try std.testing.expectEqual(Terminal.LineGeometry.single_width, terminal.semanticView(0).lineGeometry(2));
    try std.testing.expect(!(try terminal.feed("\x1b#6")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[?69l\x1b#6\x1bc")).stateChanged());
    for (0..terminal.semanticView(0).rows) |row|
        try std.testing.expectEqual(
            Terminal.LineGeometry.single_width,
            terminal.semanticView(0).lineGeometry(@intCast(row)),
        );

    var history_terminal = try Terminal.initWithHistory(std.testing.allocator, 3, 10, 4);
    defer history_terminal.deinit();
    try std.testing.expect((try history_terminal.feed("\x1b#6\x1b[3;1H\x1bD")).stateChanged());
    try std.testing.expectEqual(@as(u32, 1), history_terminal.semanticView(0).history_count);
    try std.testing.expectEqual(
        Terminal.LineGeometry.double_width,
        history_terminal.semanticView(history_terminal.semanticView(0).history_count).lineGeometry(0),
    );
    try history_terminal.resize(4, 12);
    view = history_terminal.semanticView(0);
    try std.testing.expectEqual(Terminal.LineGeometry.single_width, view.lineGeometry(0));
}

test "terminal: DECALN owns exact retained grid and mutation truth" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 6);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b[31;44;1mABCDEFx\x1b[2;1H\x1b#6")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[2;3r\x1b[2;3H")).stateChanged());
    const cursor_row_before = terminal.semanticView(0).cursor_row;
    const cursor_col_before = terminal.semanticView(0).cursor_col;
    try std.testing.expectEqual(Terminal.LineGeometry.double_width, terminal.semanticView(0).lineGeometry(1));

    try std.testing.expect(!(try terminal.feed("\x1b#")).stateChanged());
    try std.testing.expect((try terminal.feed("8")).stateChanged());
    try std.testing.expectEqual(cursor_row_before, terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(cursor_col_before, terminal.semanticView(0).cursor_col);
    try std.testing.expectEqual(Terminal.LineGeometry.double_width, terminal.semanticView(0).lineGeometry(1));
    const aligned = terminal.semanticView(0);
    for (0..aligned.rows) |row| {
        const line_cols: usize = if (row == 1) 3 else 6;
        for (0..aligned.cols) |col| {
            const cell = aligned.cellInfoAt(@intCast(row), @intCast(col));
            try std.testing.expectEqual(if (col < line_cols) @as(u21, 'E') else 0, cell.codepoint);
            try std.testing.expect(cell.attrs.bold);
            try std.testing.expectEqual(Terminal.Color.indexed(1), cell.attrs.fg);
            try std.testing.expectEqual(Terminal.Color.indexed(4), cell.attrs.bg);
        }
    }

    try std.testing.expect(!(try terminal.feed("\x1b#8")).stateChanged());

    try std.testing.expect((try terminal.feed("\x1b[1;6HE")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b#8")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b#8")).stateChanged());
}

test "terminal: resize resets physical geometry without reassigning it to reflowed content" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("ABCD\x1b#6\x1b[2;1HEFGH\x1b[3;1HIJKL")).stateChanged());
    try terminal.resize(6, 3);

    const view = terminal.semanticView(0);
    const expected = [_][3]u21{
        .{ 'A', 'B', 'C' },
        .{ 'D', 0, 0 },
        .{ 'E', 'F', 'G' },
        .{ 'H', 0, 0 },
        .{ 'I', 'J', 'K' },
        .{ 'L', 0, 0 },
    };
    for (expected, 0..) |row_cells, row| {
        try std.testing.expectEqual(Terminal.LineGeometry.single_width, view.lineGeometry(@intCast(row)));
        for (row_cells, 0..) |codepoint, col|
            try std.testing.expectEqual(codepoint, view.cellAt(@intCast(row), @intCast(col)));
    }
}

test "terminal: repeated DECLRMM set reports alternate-bank geometry reset" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b[?47h\x1b#6\x1b[?47l")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[?47h")).stateChanged());
    try std.testing.expectEqual(Terminal.LineGeometry.double_width, terminal.semanticView(0).lineGeometry(0));
    try std.testing.expect((try terminal.feed("\x1b[?47l")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[?69h")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[?47h")).stateChanged());
    try std.testing.expectEqual(
        Terminal.LineGeometry.double_width,
        terminal.semanticView(0).lineGeometry(0),
    );
    try std.testing.expect((try terminal.feed("\x1b[?69h")).stateChanged());
    try std.testing.expectEqual(
        Terminal.LineGeometry.single_width,
        terminal.semanticView(0).lineGeometry(0),
    );
}

test "terminal: tab controls share exact stored-stop and clamping behavior" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 20);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b[3g\x1b[6G\x1bH\x1b[11G\x1bH\r\x1b[I")).historyLost());
    try std.testing.expectEqual(@as(u16, 5), terminal.semanticView(0).cursor_col);
    try std.testing.expect(!(try terminal.feed("\x1b[0I")).historyLost());
    try std.testing.expectEqual(@as(u16, 10), terminal.semanticView(0).cursor_col);
    try std.testing.expect(!(try terminal.feed("\x1b[0Z")).historyLost());
    try std.testing.expectEqual(@as(u16, 5), terminal.semanticView(0).cursor_col);
    try std.testing.expect(!(try terminal.feed("\x1b[999999I")).historyLost());
    try std.testing.expectEqual(@as(u16, 19), terminal.semanticView(0).cursor_col);
    try std.testing.expect(!(try terminal.feed("\x1b[2Z")).historyLost());
    try std.testing.expectEqual(@as(u16, 5), terminal.semanticView(0).cursor_col);

    try std.testing.expect(!(try terminal.feed("\x1b[g\r\x09")).historyLost());
    try std.testing.expectEqual(@as(u16, 10), terminal.semanticView(0).cursor_col);
    try std.testing.expect(!(try terminal.feed("\x1b[5g\r\x09")).historyLost());
    try std.testing.expectEqual(@as(u16, 19), terminal.semanticView(0).cursor_col);

    try std.testing.expect(!(try terminal.feed("\x1b[6G\x1bH\x1b[3g\r\x09")).historyLost());
    try std.testing.expectEqual(@as(u16, 19), terminal.semanticView(0).cursor_col);
    try std.testing.expect(!(try terminal.feed("\x1b[?5W\r\x09\x1b[I\x1b[999999Z")).historyLost());
    try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_col);

    try std.testing.expect(!(try terminal.feed("\x1b[6G\x88\r\x09")).historyLost());
    try std.testing.expectEqual(@as(u16, 5), terminal.semanticView(0).cursor_col);
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

        try std.testing.expect(!(try terminal.feed("\x1b[2;3r\x1b[2;1HA\x1b[3;1HB\x1b[3;6H")).historyLost());
        try std.testing.expect(!(try terminal.feed(control.ind)).historyLost());
        const after_ind = terminal.semanticView(0);
        try std.testing.expectEqual(@as(u21, 'B'), after_ind.cellAt(1, 0));
        try std.testing.expectEqual(@as(u21, 0), after_ind.cellAt(2, 0));
        try std.testing.expectEqual(@as(u16, 2), after_ind.cursor_row);
        try std.testing.expectEqual(@as(u16, 5), after_ind.cursor_col);

        try std.testing.expect(!(try terminal.feed("\x1b[2;6H")).historyLost());
        try std.testing.expect(!(try terminal.feed(control.ri)).historyLost());
        const after_ri = terminal.semanticView(0);
        try std.testing.expectEqual(@as(u21, 0), after_ri.cellAt(1, 0));
        try std.testing.expectEqual(@as(u21, 'B'), after_ri.cellAt(2, 0));
        try std.testing.expectEqual(@as(u16, 1), after_ri.cursor_row);
        try std.testing.expectEqual(@as(u16, 5), after_ri.cursor_col);

        try std.testing.expect(!(try terminal.feed("\x1b[3;6H")).historyLost());
        try std.testing.expect(!(try terminal.feed(control.nel)).historyLost());
        const after_nel = terminal.semanticView(0);
        try std.testing.expectEqual(@as(u21, 'B'), after_nel.cellAt(1, 0));
        try std.testing.expectEqual(@as(u21, 0), after_nel.cellAt(2, 0));
        try std.testing.expectEqual(@as(u16, 2), after_nel.cursor_row);
        try std.testing.expectEqual(@as(u16, 0), after_nel.cursor_col);
    }
}

test "terminal: parameterless CSI s remains a savepoint under DECLRMM" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b[?69h\x1b[2;7s\x1b[2;5H")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[")).stateChanged());
    try std.testing.expect((try terminal.feed("s")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[s")).stateChanged());

    try std.testing.expect((try terminal.feed("\x1b[3;8s\x1b[1;3H\x1b[u")).stateChanged());
    try std.testing.expectEqual(@as(u16, 1), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 4), terminal.semanticView(0).cursor_col);
    try std.testing.expect(!(try terminal.feed("\x1b[u")).stateChanged());
}

test "terminal: HPB and VPB retain bounded cursor movement and exact mutation" {
    var terminal = try Terminal.init(std.testing.allocator, 4, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("\x1b[4;8H\x1b[0j")).stateChanged());
    try std.testing.expectEqual(@as(u16, 6), terminal.semanticView(0).cursor_col);
    try std.testing.expect((try terminal.feed("\x1b[j")).stateChanged());
    try std.testing.expectEqual(@as(u16, 5), terminal.semanticView(0).cursor_col);
    try std.testing.expect((try terminal.feed("\x1b[999999j")).stateChanged());
    try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_col);
    try std.testing.expect(!(try terminal.feed("\x1b[j")).stateChanged());

    try std.testing.expect((try terminal.feed("\x1b[0k")).stateChanged());
    try std.testing.expectEqual(@as(u16, 2), terminal.semanticView(0).cursor_row);
    try std.testing.expect(!(try terminal.feed("\x1b[")).stateChanged());
    try std.testing.expect((try terminal.feed("k")).stateChanged());
    try std.testing.expectEqual(@as(u16, 1), terminal.semanticView(0).cursor_row);
    try std.testing.expect((try terminal.feed("\x1b[999999k")).stateChanged());
    try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_row);
    try std.testing.expect(!(try terminal.feed("\x1b[k")).stateChanged());
}

test "terminal: DECFI and DECBI shift exact active margin rows at horizontal edges" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 6);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed(
        "\x1b[1;1HABCDEF\x1b[2;1HGHIJKL\x1b[3;1HMNOPQR" ++
            "\x1b[2;3r\x1b[?69h\x1b[2;5s\x1b[2;5H",
    )).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b")).stateChanged());
    try std.testing.expect((try terminal.feed("9")).stateChanged());
    const after_left = [_][]const u8{ "ABCDEF", "GIJK\x00L", "MOPQ\x00R" };
    for (after_left, 0..) |expected, row| for (expected, 0..) |ch, col| {
        try std.testing.expectEqual(@as(u21, ch), terminal.semanticView(0).cellAt(@intCast(row), @intCast(col)));
    };
    try std.testing.expectEqual(@as(u16, 1), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 4), terminal.semanticView(0).cursor_col);

    try std.testing.expect((try terminal.feed("\x1b[2;2H\x1b6")).stateChanged());
    const after_right = [_][]const u8{ "ABCDEF", "G\x00IJKL", "M\x00OPQR" };
    for (after_right, 0..) |expected, row| for (expected, 0..) |ch, col| {
        try std.testing.expectEqual(@as(u21, ch), terminal.semanticView(0).cellAt(@intCast(row), @intCast(col)));
    };
    try std.testing.expectEqual(@as(u16, 1), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 1), terminal.semanticView(0).cursor_col);

    try std.testing.expect((try terminal.feed("\x1bc\x1b[?69h\x1b[2;5s\x1b[2;5H")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b9")).stateChanged());
}

test "terminal: CSI cursor positioning shares parameter, margin, and origin bounds" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 8, 12);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b[4;6H\x1b[A\x1b[0B\x1b[999999C")).historyLost());
    try std.testing.expectEqual(@as(u16, 3), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 11), terminal.semanticView(0).cursor_col);
    try std.testing.expect(!(try terminal.feed("\x1b[0D\x1b[999999D\x1b[0E")).historyLost());
    try std.testing.expectEqual(@as(u16, 4), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_col);
    try std.testing.expect(!(try terminal.feed("\x1b[999999F\x1b[999999B")).historyLost());
    try std.testing.expectEqual(@as(u16, 7), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_col);

    try std.testing.expect(!(try terminal.feed("\x1b[0G\x1b[999999`\x1b[0d\x1b[999999e")).historyLost());
    try std.testing.expectEqual(@as(u16, 7), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 11), terminal.semanticView(0).cursor_col);
    try std.testing.expect(!(try terminal.feed("\x1b[0;0f\x1b[999999;999999H")).historyLost());
    try std.testing.expectEqual(@as(u16, 7), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 11), terminal.semanticView(0).cursor_col);

    try std.testing.expect(!(try terminal.feed("\x1b[3;6r\x1b[?69h\x1b[4;9s\x1b[?6h")).historyLost());
    try std.testing.expectEqual(@as(u16, 2), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 3), terminal.semanticView(0).cursor_col);
    try std.testing.expect(!(try terminal.feed("\x1b[999999B\x1b[999999C")).historyLost());
    try std.testing.expectEqual(@as(u16, 5), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 8), terminal.semanticView(0).cursor_col);
    try std.testing.expect(!(try terminal.feed("\x1b[999999A\x1b[999999D")).historyLost());
    try std.testing.expectEqual(@as(u16, 2), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 3), terminal.semanticView(0).cursor_col);
    try std.testing.expect(!(try terminal.feed("\x1b[2;2H\x1b[999999d")).historyLost());
    try std.testing.expectEqual(@as(u16, 5), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 4), terminal.semanticView(0).cursor_col);
    try std.testing.expect(!(try terminal.feed("\x1b[0d\x1b[d")).historyLost());
    try std.testing.expectEqual(@as(u16, 2), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 4), terminal.semanticView(0).cursor_col);
    try std.testing.expect(!(try terminal.feed("\x1b[2;2H\x1b[0E\x1b[0F")).historyLost());
    try std.testing.expectEqual(@as(u16, 3), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 3), terminal.semanticView(0).cursor_col);
    try std.testing.expect(!(try terminal.feed("\x1b[999999d\x1b[999999G")).historyLost());
    try std.testing.expectEqual(@as(u16, 5), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 8), terminal.semanticView(0).cursor_col);
    try std.testing.expect(!(try terminal.feed("\x1b[0;0H\x1b[999999;999999f")).historyLost());
    try std.testing.expectEqual(@as(u16, 5), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 8), terminal.semanticView(0).cursor_col);

    try std.testing.expect(!(try terminal.feed("\x1b[?6l\x1b[1;1H\x1b[999999B\x1b[999999C")).historyLost());
    try std.testing.expectEqual(@as(u16, 5), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 8), terminal.semanticView(0).cursor_col);
    try std.testing.expect(!(try terminal.feed("\x1b[8;12H\x1b[999999A\x1b[999999D")).historyLost());
    try std.testing.expectEqual(@as(u16, 2), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 3), terminal.semanticView(0).cursor_col);
    try std.testing.expect(!(try terminal.feed("\x1b[4;6H\x1b[E")).historyLost());
    try std.testing.expectEqual(@as(u16, 4), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 3), terminal.semanticView(0).cursor_col);
}

test "terminal: cursor origin margins own exact aliases geometry wrap and resize" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 6, 12);
    defer terminal.deinit();

    // Missing and zero counts are one; aliases share the same directional owner.
    try std.testing.expect((try terminal.feed("\x1b[4;7H\x1b[A\x1b[0B\x1b[a\x1b[0D")).stateChanged());
    try std.testing.expectEqual(@as(u16, 3), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 6), terminal.semanticView(0).cursor_col);
    try std.testing.expect(!(try terminal.feed("\x1b[k\x1b[e\x1b[0C\x1b[j")).stateChanged());
    try std.testing.expectEqual(@as(u16, 3), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 6), terminal.semanticView(0).cursor_col);

    // A cursor command cancels pending wrap even when its resolved position is unchanged.
    try std.testing.expect((try terminal.feed("\x1b[1;12HX")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[999999C")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[999999C")).stateChanged());

    // Invalid margins preserve the complete cursor/margin/wrap state.
    try std.testing.expect((try terminal.feed("Y")).stateChanged());
    const sequence_before_invalid = terminal.semanticSequence();
    try std.testing.expect(!(try terminal.feed("\x1b[6;2r\x1b[12;2s")).stateChanged());
    try std.testing.expectEqual(sequence_before_invalid, terminal.semanticSequence());

    // Fragmented valid margins home once. Directional aliases clamp into a region from
    // either side, and line-relative movement returns to the active left margin.
    try std.testing.expect(!(try terminal.feed("\x1b[2;")).stateChanged());
    try std.testing.expect((try terminal.feed("5r\x1b[?69h\x1b[4;9s")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[1;12H\x1b[999B\x1b[0E")).stateChanged());
    try std.testing.expectEqual(@as(u16, 4), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 3), terminal.semanticView(0).cursor_col);
    try std.testing.expect((try terminal.feed("\x1b[6;12H\x1b[999A\x1b[0F")).stateChanged());
    try std.testing.expectEqual(@as(u16, 1), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 3), terminal.semanticView(0).cursor_col);
    try std.testing.expect((try terminal.feed("\x1b[?6h")).stateChanged());
    try std.testing.expectEqual(@as(u16, 1), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 3), terminal.semanticView(0).cursor_col);
    try std.testing.expect(!(try terminal.feed("\x1b[2;5r\x1b[4;9s")).stateChanged());

    // Line geometry and horizontal margins are mutually exclusive; absolute aliases still
    // resolve vertical origin and clamp against the addressed row's logical width.
    try std.testing.expect((try terminal.feed("\x1b[?69l\x1b[2;2H\x1b#6")).stateChanged());
    try std.testing.expectEqual(Terminal.LineGeometry.double_width, terminal.semanticView(0).lineGeometry(2));
    try std.testing.expect((try terminal.feed("\x1b[2;999999f")).stateChanged());
    try std.testing.expectEqual(@as(u16, 2), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 5), terminal.semanticView(0).cursor_col);
    try std.testing.expect((try terminal.feed("\x1b[0G\x1b[0d")).stateChanged());
    try std.testing.expectEqual(@as(u16, 1), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_col);

    // Resize is transactional at Terminal and resets physical margins and row geometry.
    try terminal.resize(4, 7);
    try std.testing.expect(terminal.semanticView(0).cursor_row < 4);
    try std.testing.expect(terminal.semanticView(0).cursor_col < 7);
    for (0..4) |row| try std.testing.expectEqual(
        Terminal.LineGeometry.single_width,
        terminal.semanticView(0).lineGeometry(@intCast(row)),
    );
}

test "terminal: DEC margins bound rectangles and reject inverted coordinates" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 5, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed(
        "\x1b[1;1HABCDEFGH\x1b[2;1HIJKLMNOP\x1b[3;1HQRSTUVWX" ++
            "\x1b[4;1HYZabcdef\x1b[5;1Hghijklmn",
    )).historyLost());
    try std.testing.expect(!(try terminal.feed("\x1b[3;3H\x1b[1\"qP\x1b[2\"q")).historyLost());
    try std.testing.expect(!(try terminal.feed("\x1b[2;4r\x1b[?69h\x1b[2;7s\x1b[?6h")).historyLost());

    try std.testing.expectEqual(@as(u16, 1), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 1), terminal.semanticView(0).cursor_col);

    try std.testing.expect(!(try terminal.feed("\x1b[4;2r\x1b[999;999r\x1b[7;2s\x1b[999;999s")).historyLost());
    try std.testing.expectEqual(@as(u16, 1), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 1), terminal.semanticView(0).cursor_col);

    try std.testing.expect(!(try terminal.feed("\x1b[r")).historyLost());
    try std.testing.expect(!(try terminal.feed("\x1b[0;0s")).historyLost());
    try std.testing.expect(!(try terminal.feed("\x1b[2;4r\x1b[2;7s\x1b[2;3H")).historyLost());

    try std.testing.expect((try terminal.feed("\x1b[1;1;2;2${")).stateChanged());
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(1, 1));
    try std.testing.expectEqual(@as(u21, 'P'), terminal.semanticView(0).cellAt(2, 2));
    try std.testing.expectEqual(@as(u16, 2), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 3), terminal.semanticView(0).cursor_col);

    try std.testing.expect(!(try terminal.feed("\x1b[999;999;998;998$z")).stateChanged());
    try std.testing.expectEqual(@as(u21, 'P'), terminal.semanticView(0).cellAt(2, 2));

    try std.testing.expect(!(try terminal.feed("\x1b[48;2;40;44;52m")).historyLost());
    try std.testing.expect((try terminal.feed("\x1b[88;0;0;999;999$x")).stateChanged());
    try std.testing.expectEqual(@as(u21, 'X'), terminal.semanticView(0).cellAt(1, 1));
    try std.testing.expectEqual(@as(u21, 'X'), terminal.semanticView(0).cellAt(3, 6));
    try std.testing.expectEqual(@as(u21, 'I'), terminal.semanticView(0).cellAt(1, 0));
    try std.testing.expectEqual(Terminal.Color.rgbComponents(40, 44, 52), terminal.semanticView(0).cellInfoAt(1, 1).attrs.bg);

    try std.testing.expect((try terminal.feed("\x1b[$z")).stateChanged());
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(1, 1));
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(3, 6));
    try std.testing.expectEqual(@as(u21, 'I'), terminal.semanticView(0).cellAt(1, 0));
    try std.testing.expect((try terminal.feed("\x1b[2*x")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[3*x")).historyLost());
    try std.testing.expect((try terminal.feed("\x1b[0*x")).stateChanged());

    try terminal.resize(4, 6);
    try std.testing.expect(!(try terminal.feed("\x1b[2;3r\x1b[?69h\x1b[2;5s")).historyLost());
    try std.testing.expect((try terminal.feed("\x1bc")).stateChanged());
}

test "terminal: DECCRA preserves cursor and overlapping source bytes" {
    const allocator = std.testing.allocator;
    {
        var terminal = try Terminal.init(allocator, 4, 6);
        defer terminal.deinit();

        try std.testing.expect(!(try terminal.feed(
            "\x1b[1;1HABCDEF\x1b[2;1HGHIJKL\x1b[3;1HMNOPQR\x1b[4;1HSTUVWX\x1b[4;6H",
        )).historyLost());
        try std.testing.expect((try terminal.feed("\x1b[1;1;2;3;1;2;2;1$v")).stateChanged());
        try std.testing.expectEqual(@as(u16, 3), terminal.semanticView(0).cursor_row);
        try std.testing.expectEqual(@as(u16, 5), terminal.semanticView(0).cursor_col);
        try std.testing.expectEqual(@as(u21, 'A'), terminal.semanticView(0).cellAt(1, 1));
        try std.testing.expectEqual(@as(u21, 'C'), terminal.semanticView(0).cellAt(1, 3));
        try std.testing.expectEqual(@as(u21, 'G'), terminal.semanticView(0).cellAt(2, 1));
        try std.testing.expectEqual(@as(u21, 'I'), terminal.semanticView(0).cellAt(2, 3));
    }

    {
        var terminal = try Terminal.init(allocator, 5, 8);
        defer terminal.deinit();

        try std.testing.expect(!(try terminal.feed(
            "abcdefgh\r\nABCDEFGH\r\nIJKLMNOP\r\nQRSTUVWX\r\nyz012345" ++
                "\x1b[2;4r\x1b[?69h\x1b[2;7s\x1b[?6h\x1b[3;6H",
        )).historyLost());
        try std.testing.expect((try terminal.feed("\x1b[1;1;3;3;1;2;5;1$v")).stateChanged());

        try std.testing.expectEqual(@as(u16, 3), terminal.semanticView(0).cursor_row);
        try std.testing.expectEqual(@as(u16, 6), terminal.semanticView(0).cursor_col);
        try std.testing.expectEqual(@as(u21, 'M'), terminal.semanticView(0).cellAt(2, 4));
        try std.testing.expectEqual(@as(u21, 'B'), terminal.semanticView(0).cellAt(2, 5));
        try std.testing.expectEqual(@as(u21, 'C'), terminal.semanticView(0).cellAt(2, 6));
        try std.testing.expectEqual(@as(u21, 'P'), terminal.semanticView(0).cellAt(2, 7));
        try std.testing.expectEqual(@as(u21, 'J'), terminal.semanticView(0).cellAt(3, 5));
        try std.testing.expectEqual(@as(u21, 'K'), terminal.semanticView(0).cellAt(3, 6));
        try std.testing.expectEqual(@as(u21, '3'), terminal.semanticView(0).cellAt(4, 5));
    }
}

test "terminal: SGR retains exact rendition and colon color state" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 2, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed(
        "\x1b[1;2;3;4:3;5;7;8;9;31;44mA" ++
            "\x1b[22;23;24;25;27;28;29;39;49mB" ++
            "\x1b[21;90;107mC" ++
            "\x1b[38;5;196;48;2;1;2;3;58;5;45mD" ++
            "\x1b[38:2::10:20:30;48:5:200;58:2::40:50:60mE" ++
            "\x1b[4:0mF\x1b[4:1mG\x1b[4:2mH\x1b[4:4mI\x1b[4:5mJ\x1b[4:3mK" ++
            "\x1b[25;39m\x1b[38:5mL",
    )).historyLost());
    const set = terminal.semanticView(0).cellInfoAt(0, 0).attrs;
    try std.testing.expect(set.bold);
    try std.testing.expect(set.dim);
    try std.testing.expect(set.italic);
    try std.testing.expect(set.blink);
    try std.testing.expect(set.reverse);
    try std.testing.expect(set.invisible);
    try std.testing.expect(set.strikethrough);
    try std.testing.expect(set.underline);
    try std.testing.expectEqual(Terminal.UnderlineStyle.curly, set.underline_style);
    try std.testing.expectEqual(Terminal.Color.indexed(1), set.fg);
    try std.testing.expectEqual(Terminal.Color.indexed(4), set.bg);

    const cleared = terminal.semanticView(0).cellInfoAt(0, 1).attrs;
    try std.testing.expect(!cleared.bold);
    try std.testing.expect(!cleared.dim);
    try std.testing.expect(!cleared.italic);
    try std.testing.expect(!cleared.blink);
    try std.testing.expect(!cleared.reverse);
    try std.testing.expect(!cleared.invisible);
    try std.testing.expect(!cleared.strikethrough);
    try std.testing.expect(!cleared.underline);
    try std.testing.expectEqual(Terminal.default_cell_attrs.fg, cleared.fg);
    try std.testing.expectEqual(Terminal.default_cell_attrs.bg, cleared.bg);

    const bright = terminal.semanticView(0).cellInfoAt(0, 2).attrs;
    try std.testing.expect(bright.underline);
    try std.testing.expectEqual(Terminal.UnderlineStyle.double, bright.underline_style);
    try std.testing.expectEqual(Terminal.Color.indexed(8), bright.fg);
    try std.testing.expectEqual(Terminal.Color.indexed(15), bright.bg);

    const semicolon = terminal.semanticView(0).cellInfoAt(0, 3).attrs;
    try std.testing.expectEqual(Terminal.Color.indexed(196), semicolon.fg);
    try std.testing.expectEqual(Terminal.Color.rgbComponents(1, 2, 3), semicolon.bg);
    try std.testing.expectEqual(Terminal.Color.indexed(45), semicolon.underline_color);

    const colon = terminal.semanticView(0).cellInfoAt(0, 4).attrs;
    try std.testing.expectEqual(Terminal.Color.rgbComponents(10, 20, 30), colon.fg);
    try std.testing.expectEqual(Terminal.Color.indexed(200), colon.bg);
    try std.testing.expectEqual(Terminal.Color.rgbComponents(40, 50, 60), colon.underline_color);

    try std.testing.expect(!terminal.semanticView(0).cellInfoAt(0, 5).attrs.underline);
    try std.testing.expectEqual(Terminal.UnderlineStyle.straight, terminal.semanticView(0).cellInfoAt(0, 6).attrs.underline_style);
    try std.testing.expectEqual(Terminal.UnderlineStyle.double, terminal.semanticView(0).cellInfoAt(0, 7).attrs.underline_style);
    try std.testing.expectEqual(Terminal.UnderlineStyle.dotted, terminal.semanticView(0).cellInfoAt(1, 0).attrs.underline_style);
    try std.testing.expectEqual(Terminal.UnderlineStyle.dashed, terminal.semanticView(0).cellInfoAt(1, 1).attrs.underline_style);
    try std.testing.expectEqual(Terminal.UnderlineStyle.curly, terminal.semanticView(0).cellInfoAt(1, 2).attrs.underline_style);
    try std.testing.expect(!terminal.semanticView(0).cellInfoAt(1, 3).attrs.blink);
    try std.testing.expectEqual(Terminal.default_cell_attrs.fg, terminal.semanticView(0).cellInfoAt(1, 3).attrs.fg);
}

test "terminal: SGR color mutation is exact fragmented and malformed-transactional" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 2, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b[0m")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[38;2;1")).stateChanged());
    try std.testing.expect((try terminal.feed(";2;3;48;5;196;58:2::4:5:6m")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[38;2;1;2;3;48;5;196;58:2::4:5:6m")).stateChanged());

    try std.testing.expect((try terminal.feed("A")).stateChanged());
    const before = terminal.semanticView(0).cellInfoAt(0, 0).attrs;
    try std.testing.expect(!(try terminal.feed("\x1b[38;2;1m")).stateChanged());
    try std.testing.expect((try terminal.feed("B")).stateChanged());
    try std.testing.expectEqualDeep(before, terminal.semanticView(0).cellInfoAt(0, 1).attrs);
    try std.testing.expect((try terminal.feed("\x1b[1;38;2;1mC")).stateChanged());
    const malformed_with_bold = terminal.semanticView(0).cellInfoAt(0, 2).attrs;
    try std.testing.expect(malformed_with_bold.bold);
    try std.testing.expectEqual(before.fg, malformed_with_bold.fg);

    try std.testing.expect((try terminal.feed("\x1b[31;104m")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[31;104m")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[39;49;59m")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[39;49;59m")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[1;2;3;4;5;7;8;9m")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[0m")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[m")).stateChanged());
}

test "terminal: SGR rapid blink is an exact fragmented no-op" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 2, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b[")).stateChanged());
    try std.testing.expect(!(try terminal.feed("6m")).stateChanged());
    try std.testing.expect((try terminal.feed("A")).stateChanged());
    try std.testing.expect(!terminal.semanticView(0).cellInfoAt(0, 0).attrs.blink);
    try std.testing.expect(!terminal.semanticView(0).cellInfoAt(0, 0).attrs.blink_fast);

    try std.testing.expect((try terminal.feed("\x1b[5m")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[6m")).stateChanged());
    try std.testing.expect((try terminal.feed("B")).stateChanged());
    try std.testing.expect(terminal.semanticView(0).cellInfoAt(0, 1).attrs.blink);
    try std.testing.expect(!terminal.semanticView(0).cellInfoAt(0, 1).attrs.blink_fast);

    try std.testing.expect((try terminal.feed("\x1b[25m")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[6m")).stateChanged());
}

test "terminal: SGR font and baseline retain exact cell save resize and bank state" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b[19;7")).stateChanged());
    try std.testing.expect((try terminal.feed("3mA")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[19;73m")).stateChanged());

    try std.testing.expect((try terminal.feed("\x1b7\x1b[10;74mB\x1b8\x1b[1;3HC")).stateChanged());
    const raised = terminal.semanticView(0).cellInfoAt(0, 0).attrs;
    const lowered = terminal.semanticView(0).cellInfoAt(0, 1).attrs;
    const restored = terminal.semanticView(0).cellInfoAt(0, 2).attrs;
    try std.testing.expectEqual(@as(u4, 9), raised.font);
    try std.testing.expectEqual(Terminal.Baseline.raised, raised.baseline);
    try std.testing.expectEqual(@as(u4, 0), lowered.font);
    try std.testing.expectEqual(Terminal.Baseline.lowered, lowered.baseline);
    try std.testing.expectEqual(raised, restored);

    try terminal.resize(3, 8);
    try std.testing.expectEqual(raised, terminal.semanticView(0).cellInfoAt(0, 0).attrs);
    try std.testing.expect((try terminal.feed("\x1b[?47hD")).stateChanged());
    const alternate = terminal.semanticView(0).cellInfoAt(0, 0).attrs;
    try std.testing.expectEqual(@as(u4, 0), alternate.font);
    try std.testing.expectEqual(Terminal.Baseline.normal, alternate.baseline);
    try std.testing.expect((try terminal.feed("\x1b[?47l")).stateChanged());
    try std.testing.expectEqual(raised, terminal.semanticView(0).cellInfoAt(0, 0).attrs);

    try std.testing.expect((try terminal.feed("\x1b[75m")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[75m")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[0m")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[0m")).stateChanged());
}

test "terminal: CSI grid edits clamp counts and preserve region boundaries" {
    const allocator = std.testing.allocator;

    {
        var terminal = try Terminal.init(allocator, 2, 8);
        defer terminal.deinit();
        try std.testing.expect(!(try terminal.feed("ABCDEFGH\x1b[?69h\x1b[3;6s\x1b[1;4H\x1b[@")).historyLost());
        try std.testing.expectEqual(@as(u21, 'A'), terminal.semanticView(0).cellAt(0, 0));
        try std.testing.expectEqual(@as(u21, 'B'), terminal.semanticView(0).cellAt(0, 1));
        try std.testing.expectEqual(@as(u21, 'C'), terminal.semanticView(0).cellAt(0, 2));
        try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(0, 3));
        try std.testing.expectEqual(@as(u21, 'D'), terminal.semanticView(0).cellAt(0, 4));
        try std.testing.expectEqual(@as(u21, 'E'), terminal.semanticView(0).cellAt(0, 5));
        try std.testing.expectEqual(@as(u21, 'G'), terminal.semanticView(0).cellAt(0, 6));
        try std.testing.expectEqual(@as(u21, 'H'), terminal.semanticView(0).cellAt(0, 7));

        try std.testing.expect(!(try terminal.feed("\x1b[1;1H\x1b[999999P")).historyLost());
        try std.testing.expectEqual(@as(u21, 'A'), terminal.semanticView(0).cellAt(0, 0));
        try std.testing.expectEqual(@as(u21, 'B'), terminal.semanticView(0).cellAt(0, 1));
        try std.testing.expect(!(try terminal.feed(
            "\x1b[1\"qZ\x1b[48;2;40;44;52m\x1b[1;1H\x1b[999999X",
        )).historyLost());
        try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(0, 0));
        try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(0, 7));
        try std.testing.expectEqual(Terminal.Color.rgbComponents(40, 44, 52), terminal.semanticView(0).cellInfoAt(0, 7).attrs.bg);
        try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_col);
    }

    {
        var terminal = try Terminal.init(allocator, 4, 6);
        defer terminal.deinit();
        try std.testing.expect(!(try terminal.feed(
            "\x1b[1;1HAAAAAA\x1b[2;1HBBBBBB\x1b[3;1HCCCCCC\x1b[4;1HDDDDDD" ++
                "\x1b[2;4r\x1b[?69h\x1b[2;5s\x1b[2;3H\x1b[L",
        )).historyLost());
        try std.testing.expectEqual(@as(u21, 'B'), terminal.semanticView(0).cellAt(1, 0));
        try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(1, 1));
        try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(1, 4));
        try std.testing.expectEqual(@as(u21, 'B'), terminal.semanticView(0).cellAt(1, 5));
        try std.testing.expectEqual(@as(u21, 'C'), terminal.semanticView(0).cellAt(2, 0));
        try std.testing.expectEqual(@as(u21, 'B'), terminal.semanticView(0).cellAt(2, 1));
        try std.testing.expectEqual(@as(u21, 'B'), terminal.semanticView(0).cellAt(2, 4));
        try std.testing.expectEqual(@as(u21, 'C'), terminal.semanticView(0).cellAt(2, 5));

        try std.testing.expect(!(try terminal.feed("\x1b[2;1H\x1b[999999M")).historyLost());
        try std.testing.expectEqual(@as(u21, 'B'), terminal.semanticView(0).cellAt(1, 0));
        try std.testing.expectEqual(@as(u21, 'B'), terminal.semanticView(0).cellAt(2, 1));
        try std.testing.expect(!(try terminal.feed("\x1b[2;3H\x1b[999999M")).historyLost());
        try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(1, 1));
        try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(3, 4));
    }

    {
        var terminal = try Terminal.init(allocator, 4, 5);
        defer terminal.deinit();
        try std.testing.expect(!(try terminal.feed(
            "\x1b[1;1HAAAAA\x1b[2;1HBBBBB\x1b[3;1HCCCCC\x1b[4;1HDDDDD" ++
                "\x1b[2;4r\x1b[?69h\x1b[2;4s\x1b[999999S",
        )).historyLost());
        try std.testing.expectEqual(@as(u21, 'A'), terminal.semanticView(0).cellAt(0, 2));
        try std.testing.expectEqual(@as(u21, 'B'), terminal.semanticView(0).cellAt(1, 0));
        try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(1, 1));
        try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(3, 3));
        try std.testing.expectEqual(@as(u21, 'D'), terminal.semanticView(0).cellAt(3, 4));
        const cursor_row_before = terminal.semanticView(0).cursor_row;
        const cursor_col_before = terminal.semanticView(0).cursor_col;
        try std.testing.expect(!(try terminal.feed("\x1b[0T")).historyLost());
        try std.testing.expectEqual(cursor_row_before, terminal.semanticView(0).cursor_row);
        try std.testing.expectEqual(cursor_col_before, terminal.semanticView(0).cursor_col);
    }

    {
        var terminal = try Terminal.initWithHistory(allocator, 2, 3, 2);
        defer terminal.deinit();
        try std.testing.expect(!(try terminal.feed("\x1b[1;1HAAA\x1b[2;1HBBB\x1b[2;2H")).historyLost());
        const cursor_row_before = terminal.semanticView(0).cursor_row;
        const cursor_col_before = terminal.semanticView(0).cursor_col;
        try std.testing.expect(!(try terminal.feed("\x1b[S")).historyLost());
        try std.testing.expectEqual(@as(u32, 1), terminal.semanticView(0).history_count);
        try std.testing.expectEqual(cursor_row_before, terminal.semanticView(0).cursor_row);
        try std.testing.expectEqual(cursor_col_before, terminal.semanticView(0).cursor_col);
    }
}

test "terminal: structural edits retain logical width row geometry and exact mutation" {
    const allocator = std.testing.allocator;

    {
        var terminal = try Terminal.init(allocator, 2, 8);
        defer terminal.deinit();
        try std.testing.expect((try terminal.feed("\x1b[1;1HABCD\x1b[1;1H\x1b#6\x1b[1;2H\x1b[@")).stateChanged());
        try std.testing.expectEqual(Terminal.LineGeometry.double_width, terminal.semanticView(0).lineGeometry(0));
        try std.testing.expectEqual(@as(u21, 'A'), terminal.semanticView(0).cellAt(0, 0));
        try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(0, 1));
        try std.testing.expectEqual(@as(u21, 'B'), terminal.semanticView(0).cellAt(0, 2));
        try std.testing.expectEqual(@as(u21, 'C'), terminal.semanticView(0).cellAt(0, 3));
        try std.testing.expect((try terminal.feed("\x1b[999999P")).stateChanged());
        try std.testing.expectEqual(@as(u21, 'A'), terminal.semanticView(0).cellAt(0, 0));
        for (1..8) |col| try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(0, @intCast(col)));
        try std.testing.expect(!(try terminal.feed("\x1b[999999P")).stateChanged());
    }

    {
        var terminal = try Terminal.init(allocator, 4, 8);
        defer terminal.deinit();
        try std.testing.expect((try terminal.feed(
            "\x1b[1;1HAAAAAAAA\x1b[2;1HBBBB\x1b[2;1H\x1b#6" ++
                "\x1b[3;1HCCCCCCCC\x1b[4;1HDDDDDDDD\x1b[2;4r\x1b[2;1H\x1b[L",
        )).stateChanged());
        try std.testing.expectEqual(Terminal.LineGeometry.single_width, terminal.semanticView(0).lineGeometry(1));
        try std.testing.expectEqual(Terminal.LineGeometry.double_width, terminal.semanticView(0).lineGeometry(2));
        try std.testing.expectEqual(Terminal.LineGeometry.single_width, terminal.semanticView(0).lineGeometry(3));
        try std.testing.expect((try terminal.feed("\x1b[2;1H\x1b[M")).stateChanged());
        try std.testing.expectEqual(Terminal.LineGeometry.double_width, terminal.semanticView(0).lineGeometry(1));
        try std.testing.expectEqual(Terminal.LineGeometry.single_width, terminal.semanticView(0).lineGeometry(2));
        try std.testing.expectEqual(Terminal.LineGeometry.single_width, terminal.semanticView(0).lineGeometry(3));
        try std.testing.expectEqual(@as(u21, 'B'), terminal.semanticView(0).cellAt(1, 0));
        try std.testing.expectEqual(@as(u21, 'C'), terminal.semanticView(0).cellAt(2, 0));
        try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(3, 0));
    }
}

test "terminal: DEC column edits require cursor regions and retain exact bounded mutation" {
    var terminal = try Terminal.init(std.testing.allocator, 4, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed(
        "\x1b[1;1Habcdefgh\x1b[2;1Hijklmnop" ++
            "\x1b[3;1Hqrstuvwx\x1b[4;1HABCDEFGH" ++
            "\x1b[2;3r\x1b[?69h\x1b[3;6s",
    )).stateChanged());

    try std.testing.expect((try terminal.feed("\x1b[1;4H")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[2'}")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[2;2H")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b['~")).stateChanged());

    try std.testing.expect((try terminal.feed("\x1b[48;2;40;44;52m\x1b[2;4H\x1b[2'}")).stateChanged());
    try std.testing.expectEqual(@as(u16, 1), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 3), terminal.semanticView(0).cursor_col);
    try std.testing.expectEqual(@as(u21, 'a'), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'h'), terminal.semanticView(0).cellAt(0, 7));
    try std.testing.expectEqual(@as(u21, 'k'), terminal.semanticView(0).cellAt(1, 2));
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(1, 3));
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(1, 4));
    try std.testing.expectEqual(@as(u21, 'l'), terminal.semanticView(0).cellAt(1, 5));
    try std.testing.expectEqual(@as(u21, 'o'), terminal.semanticView(0).cellAt(1, 6));
    try std.testing.expectEqual(@as(u21, 's'), terminal.semanticView(0).cellAt(2, 2));
    try std.testing.expectEqual(@as(u21, 't'), terminal.semanticView(0).cellAt(2, 5));
    for (1..3) |row| {
        for (3..5) |col| {
            try std.testing.expectEqual(
                Terminal.Color.rgbComponents(40, 44, 52),
                terminal.semanticView(0).cellInfoAt(@intCast(row), @intCast(col)).attrs.bg,
            );
        }
    }

    try std.testing.expect((try terminal.feed("\x1b[999999'~")).stateChanged());
    for (1..3) |row| {
        for (3..6) |col| {
            try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(@intCast(row), @intCast(col)));
        }
    }
    try std.testing.expect(!(try terminal.feed("\x1b[999999'~")).stateChanged());

    try std.testing.expect((try terminal.feed("\x1b[2;4HZ\x1b[2;4H\x1b[0'}")).stateChanged());
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(1, 3));
    try std.testing.expectEqual(@as(u21, 'Z'), terminal.semanticView(0).cellAt(1, 4));
    try std.testing.expect((try terminal.feed("\x1b['~")).stateChanged());
    try std.testing.expectEqual(@as(u21, 'Z'), terminal.semanticView(0).cellAt(1, 3));
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(1, 4));
    try std.testing.expectEqual(@as(u21, 'p'), terminal.semanticView(0).cellAt(1, 7));
    try std.testing.expectEqual(@as(u21, 'x'), terminal.semanticView(0).cellAt(2, 7));
    try std.testing.expectEqual(@as(u21, 'A'), terminal.semanticView(0).cellAt(3, 0));
}

test "terminal: OSC cursor colors route into semantic cursor owner" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try feed(&terminal, "\x1b]12;#010203\x1b\\\x1b]21;cursor_text=#040506\x1b\\");

    const presentation = terminal.presentation();
    try std.testing.expectEqual(@as(?Terminal.Rgb, .{ .r = 1, .g = 2, .b = 3 }), presentation.cursor);
    try std.testing.expectEqual(@as(?Terminal.Rgb, .{ .r = 4, .g = 5, .b = 6 }), presentation.cursor_text);
}

test "terminal: fragmented Kitty static graphics retains display and query is probe only" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();

    const packet = "\x1b_Ga=T,f=32,s=1,v=1,i=7;/wAA/w==\x1b\\";
    var split: usize = 0;
    while (split <= packet.len) : (split += 1) {
        var actual = try Terminal.init(std.testing.allocator, 3, 8);
        defer actual.deinit();
        const first = try actual.feed(packet[0..split]);
        const second = try actual.feed(packet[split..]);
        try std.testing.expect(first.stateChanged() or second.stateChanged());
        const images = actual.images(0);
        try std.testing.expectEqual(@as(usize, 1), images.imageCount());
        try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, images.image(0).?.pixels);
        try std.testing.expectEqual(@as(usize, 1), images.placementCount());
        try std.testing.expectEqual(@as(u16, 0), images.placement(0).?.row);
        try std.testing.expectEqualStrings("\x1b_Gi=7;OK\x1b\\", actual.replyBytes());
    }

    const before = terminal.images(0).generation;
    try std.testing.expect(
        (try terminal.feed("\x1b_Ga=q,f=32,s=1,v=1,i=9;AQIDBA==\x1b\\")).stateChanged(),
    );
    const queried = terminal.images(0);
    try std.testing.expectEqual(before, queried.generation);
    try std.testing.expectEqual(@as(usize, 0), queried.imageCount());
    try std.testing.expectEqualStrings("\x1b_Gi=9;OK\x1b\\", terminal.replyBytes());
}

test "terminal: canceled Kitty continuation releases transfer without retained mutation" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 4);
    defer terminal.deinit();

    try std.testing.expect(
        !(try terminal.feed("\x1b_Ga=t,f=32,s=1,v=1,i=7,m=1;AQ==\x1b\\")).stateChanged(),
    );
    try std.testing.expect(!(try terminal.feed("\x1b_Gm=0;IDBA==\x18")).stateChanged());
    try std.testing.expectEqual(@as(usize, 0), terminal.images(0).imageCount());

    try std.testing.expect(
        (try terminal.feed("\x1b_Ga=t,f=32,s=1,v=1,i=8;AQIDBA==\x1b\\")).stateChanged(),
    );
    try std.testing.expectEqual(@as(u32, 1), terminal.images(0).image(0).?.id);
}

test "terminal: Kitty image number gets stable identity for put reply and deletion" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 4);
    defer terminal.deinit();
    try std.testing.expect(
        (try terminal.feed("\x1b_Ga=t,f=32,s=1,v=1,I=44;AQIDBA==\x1b\\")).stateChanged(),
    );
    try std.testing.expectEqualStrings("\x1b_Gi=1,I=44;OK\x1b\\", terminal.replyBytes());
    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed("\x1b_Ga=p,I=44,p=2\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings("\x1b_Gi=1,I=44;OK\x1b\\", terminal.replyBytes());
    try consumeReplies(&terminal);
    try std.testing.expect(
        (try terminal.feed("\x1b_Ga=t,f=32,s=1,v=1,I=44;BQYHCA==\x1b\\")).stateChanged(),
    );
    try std.testing.expectEqualStrings("\x1b_Gi=2,I=44;OK\x1b\\", terminal.replyBytes());
    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed("\x1b_Ga=p,I=44,p=3\x1b\\")).stateChanged());
    try consumeReplies(&terminal);
    try std.testing.expect(!(try terminal.feed("\x1b_Ga=d,d=n,I=44,p=2\x1b\\")).stateChanged());
    try std.testing.expectEqual(@as(usize, 2), terminal.images(0).imageCount());
    try std.testing.expectEqual(@as(usize, 2), terminal.images(0).placementCount());
    try std.testing.expect((try terminal.feed("\x1b_Ga=d,d=n,I=44,p=3\x1b\\")).stateChanged());
    try std.testing.expectEqual(@as(usize, 1), terminal.images(0).placementCount());
    try std.testing.expect((try terminal.feed("\x1b_Ga=d,d=N,I=44\x1b\\")).stateChanged());
    try std.testing.expectEqual(@as(usize, 1), terminal.images(0).imageCount());
}

test "terminal: Kitty frame reply includes exact admitted frame number" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 4);
    defer terminal.deinit();
    try std.testing.expect(
        (try terminal.feed("\x1b_Ga=t,f=32,s=1,v=1,i=50,q=2;AQIDBA==\x1b\\")).stateChanged(),
    );
    try std.testing.expect(
        (try terminal.feed("\x1b_Ga=f,f=32,s=1,v=1,i=50,r=2;BQYHCA==\x1b\\")).stateChanged(),
    );
    try std.testing.expectEqualStrings("\x1b_Gi=50,r=2;OK\x1b\\", terminal.replyBytes());
}

test "terminal: Kitty C=1 display retains cursor for explicit placement" {
    var terminal = try Terminal.init(std.testing.allocator, 6, 10);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("\x1b[2;3H")).stateChanged());
    const before_view = terminal.semanticView(0);
    const before = .{ before_view.cursor_row, before_view.cursor_col };
    try std.testing.expect((try terminal.feed(
        "\x1b_Ga=T,f=32,s=1,v=1,i=51,c=4,r=3,C=1,q=2;AQIDBA==\x1b\\",
    )).stateChanged());
    const after = terminal.semanticView(0);
    try std.testing.expectEqualDeep(before, .{ after.cursor_row, after.cursor_col });
    const placement = terminal.images(0).placement(0).?;
    try std.testing.expectEqual(@as(u16, 1), placement.row);
    try std.testing.expectEqual(@as(u16, 2), placement.col);
}

test "terminal: Kitty deletion is silent and preserves lowercase image data" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 4);
    defer terminal.deinit();
    try std.testing.expect(
        (try terminal.feed("\x1b_Ga=T,f=32,s=1,v=1,i=7;AQIDBA==\x1b\\")).stateChanged(),
    );
    try std.testing.expectEqualStrings("\x1b_Gi=7;OK\x1b\\", terminal.replyBytes());
    try consumeReplies(&terminal);

    const fill = try reply_fill.fill(&terminal, std.testing.allocator, 64 * 1024, false);
    defer std.testing.allocator.free(fill);
    try std.testing.expect((try terminal.feed("\x1b_Ga=d,d=i,i=7\x1b\\")).stateChanged());
    try std.testing.expectEqualSlices(u8, fill, terminal.replyBytes());
    try consumeReplies(&terminal);
    try std.testing.expectEqual(@as(usize, 1), terminal.images(0).imageCount());
    try std.testing.expectEqual(@as(usize, 0), terminal.images(0).placementCount());
    try std.testing.expect(!(try terminal.feed("\x1b_Ga=d,d=i,i=7\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings("", terminal.replyBytes());
}

test "terminal: static graphics follow scroll erase resize bank and reset lifetime" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 4);
    defer terminal.deinit();
    try terminal.setCellPixelSize(1, 1);
    try std.testing.expect(
        (try terminal.feed("\x1b[3;1H\x1b_Ga=T,f=32,s=1,v=1,i=7;AQIDBA==\x1b\\")).stateChanged(),
    );
    try std.testing.expectEqual(@as(u16, 2), terminal.images(0).placement(0).?.row);
    try std.testing.expect((try terminal.feed("\x1b[S")).stateChanged());
    try std.testing.expectEqual(@as(u16, 1), terminal.images(0).placement(0).?.row);
    try std.testing.expect((try terminal.feed("\x1b[2;1H\x1b[2K")).stateChanged());
    try std.testing.expect(terminal.images(0).placement(0) == null);
    try std.testing.expectEqual(@as(usize, 1), terminal.images(0).imageCount());

    try std.testing.expect(
        (try terminal.feed("\x1b[?1049h\x1b_Ga=p,i=7\x1b\\")).stateChanged(),
    );
    try std.testing.expectEqual(@as(usize, 1), terminal.images(0).placementCount());
    try std.testing.expect((try terminal.feed("\x1b[?1049l")).stateChanged());
    try std.testing.expect(terminal.images(0).placement(0) == null);
    try std.testing.expect(
        (try terminal.feed("\x1b_Ga=p,i=7\x1b\\")).stateChanged(),
    );
    try std.testing.expect(terminal.images(0).placement(1) != null);
    var discarded = try terminal.prepareResize(4, 5);
    discarded.deinit();
    try std.testing.expect(terminal.images(0).placement(1) != null);
    var committed = try terminal.prepareResize(4, 5);
    defer committed.deinit();
    committed.commit();
    try std.testing.expectEqual(@as(usize, 1), terminal.images(0).imageCount());
    try std.testing.expect(terminal.images(0).placement(0) == null);
    try std.testing.expect(terminal.images(0).placement(1) == null);
    terminal.hardReset();
    try std.testing.expectEqual(@as(usize, 0), terminal.images(0).imageCount());
}

test "terminal: fragmented Sixel retains exact image placement and cursor lifetime" {
    var terminal = try Terminal.init(std.testing.allocator, 8, 12);
    defer terminal.deinit();
    try terminal.setCellPixelSize(2, 3);
    try std.testing.expect((try terminal.feed("\x1b[3;4H\x1bPq\"1;1;3;6#1;2;100;")).stateChanged());
    try std.testing.expectEqual(@as(usize, 0), terminal.images(0).imageCount());
    try std.testing.expect(!(try terminal.feed("0;0!3~\x1b")).stateChanged());
    try std.testing.expect((try terminal.feed("\\")).stateChanged());

    const images = terminal.images(0);
    const view = terminal.semanticView(0);
    try std.testing.expectEqual(@as(usize, 1), images.imageCount());
    const image = images.image(0).?;
    try std.testing.expectEqual(@as(u32, 3), image.width);
    try std.testing.expectEqual(@as(u32, 6), image.height);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, image.pixels[0..4]);
    const placement = images.placement(0).?;
    try std.testing.expectEqual(@as(u16, 2), placement.row);
    try std.testing.expectEqual(@as(u16, 3), placement.col);
    try std.testing.expectEqual(@as(u16, 3), view.cursor_row);

    const generation = images.generation;
    try std.testing.expect(!(try terminal.feed("\x1bPq\"1;1#2;2;0;0;100~\x18")).stateChanged());
    try std.testing.expectEqual(generation, terminal.images(0).generation);
    try std.testing.expect((try terminal.feed("\x1bPq\"1;1#2;2;0;0;100~\x1b\\")).stateChanged());
    try std.testing.expectEqual(@as(usize, 2), terminal.images(0).imageCount());

    const after_restart = terminal.images(0).generation;
    try std.testing.expect(!(try terminal.feed("\x1bPq!0~\x1b\\")).stateChanged());
    try std.testing.expectEqual(after_restart, terminal.images(0).generation);
    try std.testing.expectEqual(@as(usize, 2), terminal.images(0).imageCount());
}

test "terminal: DECSIXEL mode owns query save reset and fixed-origin cursor preservation" {
    var terminal = try Terminal.init(std.testing.allocator, 8, 12);
    defer terminal.deinit();
    try terminal.setCellPixelSize(1, 1);
    try std.testing.expect(
        (try terminal.feed("\x1b[5;6H\x1b[?80h\x1b[?80$p\x1b[?80s\x1bPq\"1;1#1;2;0;100;0~\x1b\\")).stateChanged(),
    );
    try std.testing.expectEqualStrings("\x1b[?80;1$y", terminal.replyBytes());
    const images = terminal.images(0);
    const view = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u16, 0), images.placement(0).?.row);
    try std.testing.expectEqual(@as(u16, 0), images.placement(0).?.col);
    try std.testing.expectEqual(@as(u16, 4), view.cursor_row);
    try std.testing.expectEqual(@as(u16, 5), view.cursor_col);

    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed("\x1b[?80l\x1b[?80r\x1b[?80$p\x1b[!p\x1b[?80$p")).stateChanged());
    try std.testing.expectEqualStrings(
        "\x1b[?80;1$y\x1b[?80;2$y",
        terminal.replyBytes(),
    );
    try consumeReplies(&terminal);
}

test "terminal: Sixel image rows scroll primary history while preserving cursor column" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 3, 8, 4);
    defer terminal.deinit();
    try terminal.setCellPixelSize(1, 6);
    try std.testing.expect(
        (try terminal.feed("\x1b[3;5H\x1bP7;1q#2~-~\x1b\\")).stateChanged(),
    );

    const view = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u32, 1), view.history_count);
    try std.testing.expectEqual(@as(u16, 2), view.cursor_row);
    try std.testing.expectEqual(@as(u16, 4), view.cursor_col);
    try std.testing.expectEqual(@as(u16, 1), terminal.images(0).placement(0).?.row);
}

test "terminal: every byte split preserves mixed control framing" {
    const allocator = std.testing.allocator;
    const transcript = "A\x08B\x1b[2;3HC\x1b]0;first\x07\x1bP$qm\x1b\\" ++
        "\x1b_ignore\x1b\\\x1b^ignore\x1b\\\x1bXignore\x1b\\" ++
        "\x9b3;1HZ\x9d2;final\x9c";

    var expected = try Terminal.init(allocator, 4, 8);
    defer expected.deinit();
    try std.testing.expect(!(try expected.feed(transcript)).historyLost());

    var split: usize = 0;
    while (split <= transcript.len) : (split += 1) {
        var actual = try Terminal.init(allocator, 4, 8);
        defer actual.deinit();
        try std.testing.expect(!(try actual.feed(transcript[0..split])).historyLost());
        try std.testing.expect(!(try actual.feed(transcript[split..])).historyLost());

        const expected_view = expected.semanticView(0);
        const actual_view = actual.semanticView(0);
        try std.testing.expectEqual(expected_view.cursor_row, actual_view.cursor_row);
        try std.testing.expectEqual(expected_view.cursor_col, actual_view.cursor_col);
        var row: u16 = 0;
        while (row < expected_view.rows) : (row += 1) {
            var col: u16 = 0;
            while (col < expected_view.cols) : (col += 1) {
                try std.testing.expectEqual(expected_view.cellAt(row, col), actual_view.cellAt(row, col));
            }
        }
        try std.testing.expectEqualStrings(expected.title().?, actual.title().?);
        try std.testing.expectEqualStrings(expected.replyBytes(), actual.replyBytes());
    }
}
