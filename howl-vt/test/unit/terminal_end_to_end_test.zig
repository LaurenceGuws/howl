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

test "terminal: pinned iTerm2 DECID is a no-op while Howl identifies itself" {
    // Pinned iTerm2 VT100OtherParser.m parses ESC Z as VT100CSI_DECID,
    // and VT100Terminal.m executes an explicit break with no report.
    // Howl deliberately aliases ESC Z to its bounded DA1 identity reply.
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    try std.testing.expect(!(try terminal.feed("\x1b")).stateChanged());
    try std.testing.expect((try terminal.feed("Z")).stateChanged());
    try std.testing.expectEqualStrings("\x1b[?62;22c", terminal.replyBytes());
    try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_col);
    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed("\x1bZ")).stateChanged());
    try std.testing.expectEqualStrings("\x1b[?62;22c", terminal.replyBytes());
    try consumeReplies(&terminal);
    // The identity query does not alter the grid, and normal text follows.
    try std.testing.expect((try terminal.feed("Q")).stateChanged());
    try std.testing.expectEqual(@as(u21, 'Q'), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqualStrings("", terminal.replyBytes());
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

test "terminal: pinned iTerm2 UTF8 selection disables raw C1 execution unlike Howl" {
    // Pinned iTerm2 VT100ControlParser.m checks encoding before recognizing
    // raw 8-bit C1. Only ASCII/Latin-1 admit C1; after ESC % G selects
    // NSUTF8StringEncoding, 0x85 must not become a NEL terminal token.
    // Howl intentionally continues admitting raw C1 under UTF-8.
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("\x1b%@")).stateChanged());
    try feed(&terminal, "\x1b[1;4H");
    try std.testing.expect((try terminal.feed("\x85")).stateChanged());
    var view = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u16, 1), view.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), view.cursor_col);

    try std.testing.expect((try terminal.feed("\x1b%G")).stateChanged());
    try feed(&terminal, "\x1b[1;4H");
    // This changes Howl's cursor, but pinned iTerm2 does not dispatch
    // the raw byte as VT100CSI_NEL in its UTF-8 encoding state.
    try std.testing.expect((try terminal.feed("\x85")).stateChanged());
    view = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u16, 1), view.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), view.cursor_col);
    // The 7-bit NEL alias remains supported in either encoding and the
    // terminal still accepts ordinary multi-byte UTF-8 graphics.
    try feed(&terminal, "\x1b[1;4H\x1bE\xc3\xa9");
    view = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u21, 0x00E9), view.cellAt(1, 0));
    try std.testing.expectEqual(@as(u16, 1), view.cursor_row);
    try std.testing.expectEqual(@as(u16, 1), view.cursor_col);
    try std.testing.expectEqualStrings("", terminal.replyBytes());
}

test "terminal: Kitty private erase preserves attrs but Howl protects DEC characters" {
    // Pinned Kitty screen_erase_in_line/display private=true clears text
    // unconditionally and preserves each cell's old attributes. Howl's
    // private DEC erase respects protected cells instead. One wire input
    // cannot implement both policies without a terminal profile.
    for ([_][]const u8{ "\x1b[?2K", "\x1b[?2J" }) |erase| {
        var terminal = try Terminal.init(std.testing.allocator, 3, 8);
        defer terminal.deinit();
        try feed(&terminal, "\x1b[31m\x1b[1\"qP\x1b[0\"qU\x1b[1;1H");
        const protected_before = terminal.semanticView(0).cellInfoAt(0, 0);
        try std.testing.expect(protected_before.attrs.protected == .dec);
        try std.testing.expect((try terminal.feed(erase)).stateChanged());
        const view = terminal.semanticView(0);
        try std.testing.expectEqual(@as(u21, 'P'), view.cellAt(0, 0));
        try std.testing.expectEqual(@as(u21, 0), view.cellAt(0, 1));
        try std.testing.expectEqualDeep(protected_before, view.cellInfoAt(0, 0));
        try std.testing.expect(!(try terminal.feed(erase)).stateChanged());
        try std.testing.expectEqualStrings("", terminal.replyBytes());
    }
}

test "terminal: ED22 archives used primary lines and preserves cursor" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 3, 8, 8);
    defer terminal.deinit();
    try feed(&terminal, "\x1b[1;1Hone\x1b[2;1Htwo");
    const before = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u32, 0), before.history_count);
    const sequence = terminal.semanticSequence();
    try std.testing.expect(!(try terminal.feed("\x1b[22")).stateChanged());
    try std.testing.expect((try terminal.feed("J")).stateChanged());
    const after = terminal.semanticView(0);
    try std.testing.expect(terminal.semanticSequence() > sequence);
    try std.testing.expectEqual(@as(u32, 2), after.history_count);
    try std.testing.expectEqual(@as(u21, 0), after.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'o'), terminal.semanticView(2).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), after.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 't'), terminal.semanticView(2).cellAt(1, 0));
    try std.testing.expectEqual(before.cursor_row, after.cursor_row);
    try std.testing.expectEqual(before.cursor_col, after.cursor_col);
    try std.testing.expectEqualStrings("", terminal.replyBytes());
}

test "terminal: Kitty ED3 clears visible display but Howl clears only history" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 2, 8, 8);
    defer terminal.deinit();
    try feed(&terminal, "one\r\ntwo\r\nthree");
    const before = terminal.semanticView(0);
    try std.testing.expect(before.history_count > 0);
    try std.testing.expectEqual(@as(u21, 't'), before.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 't'), before.cellAt(1, 0));
    try std.testing.expect((try terminal.feed("\x1b[3J")).stateChanged());
    const after = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u32, 0), after.history_count);
    try std.testing.expectEqual(@as(u21, 't'), after.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 't'), after.cellAt(1, 0));
    // Kitty screen.c:screen_erase_in_display(3) erases the visible
    // viewport too, not merely its scrollback as Howl does.
    try std.testing.expect(!(try terminal.feed("\x1b[3J")).stateChanged());
}

test "terminal: pinned Kitty ED EL reject extra operands before text or graphics mutation" {
    // Pinned Kitty d4106ef kitty/vt-parser.c dispatch_csi uses
    // CALL_CSI_HANDLER1P for J and K, rejecting num_params > 1 before
    // invoking either ordinary or private screen_erase_in_* owner.
    for ([_][]const u8{
        "\x1b[2;1J", "\x1b[2;1K",  "\x1b[?2;1J", "\x1b[?2;1K",
        "\x1b[0;;J", "\x1b[?0;;K", "\x1b[3;1J",  "\x1b[1;2K",
        "\x1b[2:1J", "\x1b[?1:2K", "\x9b2;1J",   "\x9b?2;1K",
    }) |invalid| {
        var terminal = try Terminal.init(std.testing.allocator, 3, 8);
        defer terminal.deinit();
        try terminal.setCellPixelSize(1, 1);
        try feed(&terminal, "\x1b[1;1HHELLO\x1b[2;1HWORLD\x1b[1;1H");
        try feed(&terminal, "\x1b_Ga=T,f=32,s=1,v=1,i=91,C=1;AQIDBA==\x1b\\");
        try consumeReplies(&terminal);
        const before = terminal.semanticSequence();
        const cursor = terminal.semanticView(0);
        const first = cursor.cellInfoAt(0, 0);
        const second = cursor.cellInfoAt(1, 0);
        const placements = terminal.images(0).placementCount();
        const image_content = terminal.images(0).content_generation;
        try std.testing.expectEqual(@as(usize, 1), placements);
        // A split CSI must leave both the original grid and images untouched.
        try std.testing.expect(!(try terminal.feed(invalid[0 .. invalid.len - 1])).stateChanged());
        try std.testing.expect(!(try terminal.feed(invalid[invalid.len - 1 ..])).stateChanged());
        try std.testing.expectEqual(before, terminal.semanticSequence());
        const after = terminal.semanticView(0);
        try std.testing.expectEqualDeep(first, after.cellInfoAt(0, 0));
        try std.testing.expectEqualDeep(second, after.cellInfoAt(1, 0));
        try std.testing.expectEqual(cursor.cursor_row, after.cursor_row);
        try std.testing.expectEqual(cursor.cursor_col, after.cursor_col);
        try std.testing.expectEqual(placements, terminal.images(0).placementCount());
        try std.testing.expectEqual(image_content, terminal.images(0).content_generation);
        try std.testing.expectEqualStrings("", terminal.replyBytes());

        // The malformed command cannot poison the next valid erase.
        try std.testing.expect((try terminal.feed("\x1b[2J")).stateChanged());
        try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(0, 0));
        try std.testing.expectEqual(@as(usize, 0), terminal.images(0).placementCount());
    }

    // Kitty commit_csi_param ignores an absent last operand at the final
    // byte. Thus "0;J" and "0;K" remain one-parameter commands, not invalid.
    for ([_][]const u8{
        "\x1b[0;J", "\x1b[0;K", "\x1b[?0;J", "\x1b[?0;K",
    }) |valid| {
        var terminal = try Terminal.init(std.testing.allocator, 2, 8);
        defer terminal.deinit();
        try feed(&terminal, "abc\x1b[1;1H");
        try std.testing.expect((try terminal.feed(valid)).stateChanged());
        try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(0, 0));
        try std.testing.expectEqualStrings("", terminal.replyBytes());
    }
}

test "terminal: Kitty ordinary blank EL dirties selection while Howl keeps an exact noop" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    const before = terminal.semanticSequence();
    try std.testing.expect(!(try terminal.feed("\x1b[2K")).stateChanged());
    try std.testing.expectEqual(before, terminal.semanticSequence());
    try std.testing.expect(!(try terminal.feed("\x1b[K")).stateChanged());
    try std.testing.expectEqual(before, terminal.semanticSequence());
    // Pinned Kitty screen_erase_in_line runs mark_line_dirty and clears any
    // intersecting selection for either request even if cells were blank.
    // Howl has no equivalent forced selection/presentation side effect.
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

test "terminal: ECH graphics use the logical DEC row width, not physical columns" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    try terminal.setCellPixelSize(1, 1);
    // Image at logical column four and one at physical column six, which
    // ceases to be addressable when the row changes to double-width.
    try feed(&terminal, "\x1b[1;4H\x1b_Ga=T,f=32,s=1,v=1,i=81,C=1;AQIDBA==\x1b\\");
    try feed(&terminal, "\x1b[1;6H\x1b_Ga=T,f=32,s=1,v=1,i=82,C=1;AQIDBA==\x1b\\");
    try consumeReplies(&terminal);
    try std.testing.expectEqual(@as(usize, 2), terminal.images(0).placementCount());
    const image_content_generation = terminal.images(0).content_generation;

    try feed(&terminal, "\x1b[1;1H\x1b#6\x1b[1;3H");
    try std.testing.expectEqual(Terminal.LineGeometry.double_width, terminal.semanticView(0).lineGeometry(0));
    try std.testing.expect((try terminal.feed("\x1b[999X")).stateChanged());
    try std.testing.expectEqual(@as(usize, 1), terminal.images(0).placementCount());
    try std.testing.expectEqual(@as(u16, 5), terminal.images(0).placement(0).?.col);
    try std.testing.expectEqual(@as(usize, 2), terminal.images(0).imageCount());
    try std.testing.expectEqual(image_content_generation, terminal.images(0).content_generation);
}

test "terminal: EL graphics follow the accepted DEC logical row width" {
    for ([_]struct { command: []const u8, cursor_col: u16 }{
        .{ .command = "\x1b[0K", .cursor_col = 2 },
        .{ .command = "\x1b[1K", .cursor_col = 3 },
        .{ .command = "\x1b[2K", .cursor_col = 2 },
    }) |case| {
        var terminal = try Terminal.init(std.testing.allocator, 2, 8);
        defer terminal.deinit();
        try terminal.setCellPixelSize(1, 1);
        try feed(&terminal, "\x1b[1;4H\x1b_Ga=T,f=32,s=1,v=1,i=83,C=1;AQIDBA==\x1b\\");
        try feed(&terminal, "\x1b[1;6H\x1b_Ga=T,f=32,s=1,v=1,i=84,C=1;AQIDBA==\x1b\\");
        try consumeReplies(&terminal);
        try std.testing.expectEqual(@as(usize, 2), terminal.images(0).placementCount());
        const image_content = terminal.images(0).content_generation;

        var cursor: [12]u8 = undefined;
        try feed(&terminal, "\x1b[1;1H\x1b#6");
        try feed(&terminal, try std.fmt.bufPrint(&cursor, "\x1b[1;{d}H", .{case.cursor_col + 1}));
        try std.testing.expectEqual(Terminal.LineGeometry.double_width, terminal.semanticView(0).lineGeometry(0));
        try std.testing.expect((try terminal.feed(case.command)).stateChanged());
        try std.testing.expectEqual(@as(usize, 1), terminal.images(0).placementCount());
        try std.testing.expectEqual(@as(u16, 5), terminal.images(0).placement(0).?.col);
        try std.testing.expectEqual(@as(usize, 2), terminal.images(0).imageCount());
        try std.testing.expectEqual(image_content, terminal.images(0).content_generation);
    }
}

test "terminal: ED below keeps out-of-width graphics on the cursor row" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    try terminal.setCellPixelSize(1, 1);
    const graphics = "\x1b_Ga=T,f=32,s=1,v=1,C=1;AQIDBA==\x1b\\";
    try feed(&terminal, "\x1b[1;4H" ++ graphics ++ "\x1b[1;6H" ++ graphics ++ "\x1b[2;4H" ++ graphics);
    try consumeReplies(&terminal);
    try std.testing.expectEqual(@as(usize, 3), terminal.images(0).placementCount());
    const pixels_before = terminal.images(0).content_generation;

    try feed(&terminal, "\x1b[1;1H\x1b#6\x1b[1;3H");
    try std.testing.expectEqual(Terminal.LineGeometry.double_width, terminal.semanticView(0).lineGeometry(0));
    try std.testing.expect((try terminal.feed("\x1b[0J")).stateChanged());
    // ED below clips the cursor row to four logical cells, but resets the
    // whole second row, which must lose its placement.
    try std.testing.expectEqual(@as(usize, 1), terminal.images(0).placementCount());
    try std.testing.expectEqual(@as(u16, 0), terminal.images(0).placement(0).?.row);
    try std.testing.expectEqual(@as(u16, 5), terminal.images(0).placement(0).?.col);
    try std.testing.expectEqual(@as(usize, 3), terminal.images(0).imageCount());
    try std.testing.expectEqual(pixels_before, terminal.images(0).content_generation);
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

test "terminal: DEC private erasure preserves guarded text and resets erased cell attributes" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 6);
    defer terminal.deinit();
    // Two bold red cells; only the first is marked DEC-protected.
    try feed(&terminal, "\x1b[1\"q\x1b[1;31mP\x1b[0\"qU");
    const protected_before = terminal.semanticView(0).cellInfoAt(0, 0);
    const unprotected_before = terminal.semanticView(0).cellInfoAt(0, 1);
    try std.testing.expect(protected_before.attrs.bold);
    try std.testing.expect(unprotected_before.attrs.bold);
    try std.testing.expect(protected_before.attrs.protected == .dec);
    try std.testing.expect(unprotected_before.attrs.protected == .none);

    // The pinned libvterm model protects the guarded glyph while an erased
    // cell takes current foreground/background and reset non-color attrs.
    // Kitty's same private bytes clear text but retain the old formatting.
    try feed(&terminal, "\x1b[0;32;44m\x1b[1;1H\x1b[?2K");
    const view = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'P'), view.cellAt(0, 0));
    try std.testing.expectEqualDeep(protected_before, view.cellInfoAt(0, 0));
    const erased = view.cellInfoAt(0, 1);
    try std.testing.expectEqual(@as(u21, 0), erased.codepoint);
    try std.testing.expect(!erased.attrs.bold);
    try std.testing.expect(erased.attrs.protected == .none);
    try std.testing.expect(!std.meta.eql(erased.attrs, unprotected_before.attrs));
    try std.testing.expectEqual(@as(u16, 0), view.cursor_col);
}

test "terminal: erase commands use current attrs rather than iTerm2 default or old attrs" {
    const cases = [_][]const u8{
        "\x1b[2K", // EL clears the full active row.
        "\x1b[X", // ECH clears one logical cell.
        "\x1b[1;1;1;1$z", // DECERA clears one addressed cell.
        "\x1b[1;1;1;1${", // DECSERA clears an unprotected addressed cell.
    };
    for (cases) |command| {
        var terminal = try Terminal.init(std.testing.allocator, 2, 6);
        defer terminal.deinit();

        try feed(&terminal, "\x1b[1;31;4mA");
        const original = terminal.semanticView(0).cellInfoAt(0, 0);
        try std.testing.expect(original.attrs.bold);
        try std.testing.expect(original.attrs.underline);
        try std.testing.expectEqual(Terminal.Color.indexed(1), original.attrs.fg);

        try feed(&terminal, "\x1b[22;24;2;32;44m\x1b[1;1H");
        try std.testing.expect((try terminal.feed(command)).stateChanged());
        const erased = terminal.semanticView(0).cellInfoAt(0, 0);
        try std.testing.expectEqual(@as(u21, 0), erased.codepoint);
        try std.testing.expect(!erased.attrs.bold);
        try std.testing.expect(!erased.attrs.underline);
        try std.testing.expect(erased.attrs.dim);
        try std.testing.expectEqual(Terminal.Color.indexed(2), erased.attrs.fg);
        try std.testing.expectEqual(Terminal.Color.indexed(4), erased.attrs.bg);
        try std.testing.expect(erased.attrs.protected == .none);
        try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_row);
        try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_col);
        try std.testing.expect(!(try terminal.feed(command)).stateChanged());
    }
}

test "terminal: DECFRA uses raw fill code instead of iTerm2 charset mapping" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 5);
    defer terminal.deinit();

    // Ordinary writes use the selected DEC special-graphics charset.
    try feed(&terminal, "\x1b(0q");
    try std.testing.expectEqual(@as(u21, 0x2500), terminal.semanticView(0).cellAt(0, 0));

    // DECFRA uses the supplied raw Pc. Pinned iTerm2 instead maps its Pc
    // through the active line-drawing designation before filling.
    try std.testing.expect((try terminal.feed("\x1b[113;1;3;1;3$x")).stateChanged());
    try std.testing.expectEqual(@as(u21, 'q'), terminal.semanticView(0).cellAt(0, 2));
    try std.testing.expectEqual(@as(u16, 1), terminal.semanticView(0).cursor_col);
    try feed(&terminal, "q");
    try std.testing.expectEqual(@as(u21, 0x2500), terminal.semanticView(0).cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'q'), terminal.semanticView(0).cellAt(0, 2));
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

test "terminal: rectangle rendition preserves complete wide and sized character ownership" {
    const cases = [_]struct { edit: []const u8, rectangular: bool, row: u16, col: u16 }{
        .{ .edit = "\x1b[1;2;1;2;1$r", .rectangular = true, .row = 0, .col = 1 },
        .{ .edit = "\x9b1;1;1;1;1$t", .rectangular = true, .row = 0, .col = 0 },
        .{ .edit = "\x1b[3;4;3;4;1$t", .rectangular = true, .row = 2, .col = 3 },
        .{ .edit = "\x1b[1;5;4;6;1$r", .rectangular = false, .row = 1, .col = 2 },
    };
    for (cases) |case| {
        for (0..case.edit.len + 1) |split| {
            var terminal = try Terminal.init(std.testing.allocator, 5, 8);
            defer terminal.deinit();
            try feed(&terminal, "\x1b[31m\xe4\xb8\xad\xcc\x81\xcc\xa7\xcc\x88\xcc\x84");
            try feed(&terminal, "\x1b[2;3H\x1b]66;s=2;X\xcc\x81\xcc\xa7\xcc\x88\xcc\x84\x07");
            try feed(&terminal, "\x1b[5;2H");
            if (case.rectangular) try feed(&terminal, "\x1b[2*x");
            const view = terminal.semanticView(0);
            var before: [5][8]Terminal.Cell = undefined;
            for (0..5) |row| for (0..8) |col| {
                before[row][col] = view.cellInfoAt(@intCast(row), @intCast(col));
            };
            try std.testing.expectEqual(@as(u32, 0x4e2d), before[0][0].codepoint);
            try std.testing.expectEqual(@as(u8, 2), before[0][0].width);
            try std.testing.expectEqual(@as(u32, 'X'), before[1][2].codepoint);
            try std.testing.expectEqual(@as(u8, 2), before[1][2].height);
            try std.testing.expectEqual(@as(u8, 4), before[1][2].combining_len);
            const untouched_row = view.rowGeneration(4);

            try std.testing.expect(!(try terminal.feed(case.edit[0..split])).stateChanged() or split == case.edit.len);
            try feed(&terminal, case.edit[split..]);
            const after = terminal.semanticView(0);
            try std.testing.expectEqual(@as(u16, 4), after.cursor_row);
            try std.testing.expectEqual(@as(u16, 1), after.cursor_col);
            try std.testing.expect(after.cellInfoAt(case.row, case.col).attrs.bold);
            for (0..5) |row| for (0..8) |col| {
                const actual = after.cellInfoAt(@intCast(row), @intCast(col));
                var expected = before[row][col];
                const selected = if (case.rectangular)
                    row == case.row and col == case.col
                else
                    (row == 0 and col >= 4) or row == 1 or row == 2 or (row == 3 and col <= 5);
                if (selected) expected.attrs.bold = true;
                try std.testing.expectEqualDeep(expected, actual);
            };
            var scalars: [24]u21 = undefined;
            try std.testing.expectEqualSlices(u21, &.{ 0x4e2d, 0x301, 0x327, 0x308, 0x304 }, after.cellScalarsAt(0, 1, &scalars));
            try std.testing.expectEqualSlices(u21, &.{ 'X', 0x301, 0x327, 0x308, 0x304 }, after.cellScalarsAt(2, 3, &scalars));
            try std.testing.expectEqual(untouched_row, after.rowGeneration(4));
            try feed(&terminal, "Z");
            const written = terminal.semanticView(0).cellInfoAt(4, 1);
            try std.testing.expect(!written.attrs.bold);
            try std.testing.expectEqual(Terminal.Color.indexed(1), written.attrs.fg);
        }
    }
}

test "terminal: rectangle attribute defaults distinguish change from reverse" {
    const initial = "\x1b[1;2;3;4;5;7;8;9;31;44mAB\x1b[2;1HCD\x1b[3;1H";
    const cases = [_]struct { wire: []const u8, reset_selected: bool = true, reset_all: bool = false }{
        // Originating Kitty _parse_sgr: coordinates alone supply no SGR.
        .{ .wire = "\x1b[1;1;1;1$r", .reset_selected = false },
        .{ .wire = "\x9b1;1;1;1$r", .reset_selected = false },
        .{ .wire = "\x1b[1$r", .reset_selected = false },
        .{ .wire = "\x9b1;1$r", .reset_selected = false },
        .{ .wire = "\x1b[1;1;1$r", .reset_selected = false },
        .{ .wire = "\x9b$r", .reset_all = true },
        .{ .wire = "\x9b1;1;1;1;0$r", .reset_all = false },
        .{ .wire = "\x1b[$r", .reset_all = true },
        .{ .wire = "\x1b[;;;;0$r", .reset_all = true },
    };
    for (cases) |case| {
        for (0..case.wire.len + 1) |split| {
            var terminal = try Terminal.init(std.testing.allocator, 3, 4);
            defer terminal.deinit();
            try feed(&terminal, initial);
            const before = terminal.semanticView(0);
            var expected = before.cellInfoAt(0, 0);
            const other = before.cellInfoAt(0, 1);
            const row_before = before.cellInfoAt(1, 1);
            try std.testing.expect(expected.attrs.bold and expected.attrs.underline and expected.attrs.blink and expected.attrs.reverse);
            if (case.reset_selected) expected.attrs = Terminal.default_cell_attrs;
            const sequence = terminal.semanticSequence();
            const row_generation = before.rowGeneration(0);
            const first = try terminal.feed(case.wire[0..split]);
            const second = try terminal.feed(case.wire[split..]);
            if (!case.reset_selected) {
                try std.testing.expect(!first.stateChanged() and !second.stateChanged());
                try std.testing.expectEqual(sequence, terminal.semanticSequence());
                try std.testing.expectEqual(row_generation, terminal.semanticView(0).rowGeneration(0));
            }
            const after = terminal.semanticView(0);
            try std.testing.expectEqualDeep(expected, after.cellInfoAt(0, 0));
            var b = other;
            var d = row_before;
            if (case.reset_all) {
                b.attrs = expected.attrs;
                d.attrs = expected.attrs;
            }
            try std.testing.expectEqualDeep(b, after.cellInfoAt(0, 1));
            try std.testing.expectEqualDeep(d, after.cellInfoAt(1, 1));
            try std.testing.expectEqual(@as(u16, 2), after.cursor_row);
            try std.testing.expectEqual(@as(u16, 0), after.cursor_col);
            try std.testing.expect(!(try terminal.feed(case.wire)).stateChanged());
            try feed(&terminal, "Z");
            try std.testing.expectEqualDeep(other.attrs, terminal.semanticView(0).cellInfoAt(2, 0).attrs);
        }
    }
}

test "terminal: extended DECCARA applies complete shared rendition to existing cells" {
    const cases = [_]struct { sgr: []const u8, fg: Terminal.Color, bg: Terminal.Color, underline: Terminal.UnderlineStyle, ul_color: Terminal.Color }{
        .{ .sgr = "38;2;1;2;3;48;2;4;5;6;4:3;58:5:17", .fg = .rgbComponents(1, 2, 3), .bg = .rgbComponents(4, 5, 6), .underline = .curly, .ul_color = .indexed(17) },
        .{ .sgr = "38:2::7:8:9;48:5:23;4:5;58;2;10;11;12", .fg = .rgbComponents(7, 8, 9), .bg = .indexed(23), .underline = .dashed, .ul_color = .rgbComponents(10, 11, 12) },
        .{ .sgr = "91;104;21;59", .fg = .indexed(9), .bg = .indexed(12), .underline = .double, .ul_color = Terminal.default_cell_attrs.underline_color },
    };
    for (cases) |case| {
        for ([_][]const u8{ "\x1b[", "\x9b" }) |introducer| {
            var command_buf: [128]u8 = undefined;
            const command = try std.fmt.bufPrint(&command_buf, "{s}1;2;2;3;{s}$r", .{ introducer, case.sgr });
            for (0..command.len + 1) |split| {
                var terminal = try Terminal.init(std.testing.allocator, 3, 4);
                defer terminal.deinit();
                try feed(&terminal, "\x1b[1;31mA\x1b[0;3;32mB\x1b[0;33mCD\x1b[2;1HEFGH\x1b[3;1H\x1b[0;35m\x1b[2*x");
                const before = terminal.semanticView(0);
                var cells: [2][4]Terminal.Cell = undefined;
                for (0..2) |r| for (0..4) |c| {
                    cells[r][c] = before.cellInfoAt(@intCast(r), @intCast(c));
                };
                const row_generation = before.rowGeneration(2);
                try feed(&terminal, "\x1b[5n");
                try std.testing.expect(!(try terminal.feed(command[0..split])).stateChanged() or split == command.len);
                try feed(&terminal, command[split..]);
                const view = terminal.semanticView(0);
                for (0..2) |r| for (0..4) |c| {
                    var expected = cells[r][c];
                    if (c == 1 or c == 2) {
                        expected.attrs.fg = case.fg;
                        expected.attrs.bg = case.bg;
                        expected.attrs.underline = true;
                        expected.attrs.underline_style = case.underline;
                        expected.attrs.underline_color = case.ul_color;
                    }
                    try std.testing.expectEqualDeep(expected, view.cellInfoAt(@intCast(r), @intCast(c)));
                };
                try std.testing.expectEqual(row_generation, view.rowGeneration(2));
                try std.testing.expectEqual(@as(u16, 2), view.cursor_row);
                try std.testing.expectEqual(@as(u16, 0), view.cursor_col);
                try std.testing.expectEqualStrings("\x1b[0n", terminal.replyBytes());
                try std.testing.expect(!(try terminal.feed(command)).stateChanged());
                try feed(&terminal, "Z");
                try std.testing.expectEqual(Terminal.Color.indexed(5), terminal.semanticView(0).cellInfoAt(2, 0).attrs.fg);
                try std.testing.expect(!terminal.semanticView(0).cellInfoAt(2, 0).attrs.underline);
            }
        }
    }
}

test "terminal: extended DECCARA reset preserves protection links and cluster scalars" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    try feed(&terminal, "\x1b[1;3;31;44;4:3;58:5:29m\x1b[1\"q\x1b]8;;https://example.invalid\x1b\\");
    try feed(&terminal, "\xe4\xb8\xad\xcc\x81\xcc\xa7\xcc\x88\xcc\x84");
    try feed(&terminal, "\x1b[2;3H\x1b]66;s=2;X\xcc\x81\xcc\xa7\xcc\x88\xcc\x84\x07\x1b[1;1H\x1b[2*x");
    const before = terminal.semanticView(0);
    var cells: [3][8]Terminal.Cell = undefined;
    for (0..3) |r| for (0..8) |c| {
        cells[r][c] = before.cellInfoAt(@intCast(r), @intCast(c));
    };
    try std.testing.expect(cells[0][0].attrs.link_id != 0);
    try std.testing.expect(cells[0][0].attrs.protected == .dec);
    try feed(&terminal, "\x1b[1;1;3;8;0$r");
    const after = terminal.semanticView(0);
    for (0..3) |r| for (0..8) |c| {
        var expected = cells[r][c];
        expected.attrs = Terminal.default_cell_attrs;
        expected.attrs.protected = cells[r][c].attrs.protected;
        expected.attrs.link_id = cells[r][c].attrs.link_id;
        try std.testing.expectEqualDeep(expected, after.cellInfoAt(@intCast(r), @intCast(c)));
    };
    var scalars: [24]u21 = undefined;
    try std.testing.expectEqualSlices(u21, &.{ 0x4e2d, 0x301, 0x327, 0x308, 0x304 }, after.cellScalarsAt(0, 1, &scalars));
    try std.testing.expectEqualSlices(u21, &.{ 'X', 0x301, 0x327, 0x308, 0x304 }, after.cellScalarsAt(2, 3, &scalars));
    try feed(&terminal, "\x1b[1;4HZ");
    try std.testing.expectEqualDeep(cells[0][0].attrs, terminal.semanticView(0).cellInfoAt(0, 3).attrs);
}

test "terminal: extended DECCARA restyles pending wrap without allocation or cursor movement" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var terminal = try Terminal.initWithHistory(failing.allocator(), 3, 4, 8);
    defer terminal.deinit();
    try feed(&terminal, "\x1b[1;2;31mABCD");
    const before = terminal.semanticView(0);
    const cursor_row = before.cursor_row;
    const cursor_col = before.cursor_col;
    const row_generation = before.rowGeneration(0);
    const background_generation = before.rowBackgroundGeneration(0);
    const unaffected = before.rowGeneration(1);
    const output_range = terminal.logicalOutputRange();
    const image_generation = terminal.images(0).generation;
    const sequence = terminal.semanticSequence();
    failing.fail_index = failing.alloc_index;
    // Neither malformed region coordinates nor incomplete color groups may
    // reinterpret a payload component as a rendition selector.
    for ([_][]const u8{
        "\x1b[1:1;1;1;44$r",
        "\x1b[1;2;1;3;38:2:1:2$r",
        "\x1b[1;2;1;3;48;2;4;5$r",
        "\x1b[1;2;1;3;4:3$t",
    }) |wire| {
        try std.testing.expect(!(try terminal.feed(wire)).stateChanged());
        try std.testing.expectEqual(sequence, terminal.semanticSequence());
    }
    try std.testing.expect((try terminal.feed("\x1b[1;2;1;3;221;48:2::12:34:56$r")).stateChanged());
    const after = terminal.semanticView(0);
    try std.testing.expectEqual(cursor_row, after.cursor_row);
    try std.testing.expectEqual(cursor_col, after.cursor_col);
    try std.testing.expect(row_generation != after.rowGeneration(0));
    try std.testing.expect(background_generation != after.rowBackgroundGeneration(0));
    try std.testing.expectEqual(unaffected, after.rowGeneration(1));
    try std.testing.expectEqualDeep(output_range, terminal.logicalOutputRange());
    try std.testing.expectEqual(image_generation, terminal.images(0).generation);
    for (1..3) |col| {
        const cell = after.cellInfoAt(0, @intCast(col));
        try std.testing.expect(!cell.attrs.bold);
        try std.testing.expect(cell.attrs.dim);
        try std.testing.expectEqual(Terminal.Color.rgbComponents(12, 34, 56), cell.attrs.bg);
    }
    try std.testing.expect(!(try terminal.feed("\x1b[1;2;1;3;221;48:2::12:34:56$r")).stateChanged());
    try std.testing.expect(!failing.has_induced_failure);
    failing.fail_index = std.math.maxInt(usize);

    // The latent wrap and ordinary write rendition must survive the edit.
    try feed(&terminal, "X");
    const written = terminal.semanticView(0).cellInfoAt(1, 0);
    try std.testing.expectEqual(@as(u32, 'X'), written.codepoint);
    try std.testing.expect(written.attrs.bold and written.attrs.dim);
    try std.testing.expectEqual(Terminal.default_cell_attrs.bg, written.attrs.bg);
    try std.testing.expectEqual(@as(u21, 'D'), terminal.semanticView(0).cellAt(0, 3));

    try feed(&terminal, "\x1b[1;2;1;3;222;49$r");
    try std.testing.expect(!terminal.semanticView(0).cellInfoAt(0, 1).attrs.dim);
    try std.testing.expectEqual(Terminal.default_cell_attrs.bg, terminal.semanticView(0).cellInfoAt(0, 1).attrs.bg);
    try feed(&terminal, "\x1b[221mY\x1b[1;222mZ");
    try std.testing.expect(!terminal.semanticView(0).cellInfoAt(1, 1).attrs.bold);
    try std.testing.expect(terminal.semanticView(0).cellInfoAt(1, 1).attrs.dim);
    try std.testing.expect(terminal.semanticView(0).cellInfoAt(1, 2).attrs.bold);
    try std.testing.expect(!terminal.semanticView(0).cellInfoAt(1, 2).attrs.dim);

    // Background styling on blank cells must not materialize characters.
    try feed(&terminal, "\x1b[2*x\x1b[3;1;3;4;44$r");
    for (0..4) |col| {
        const blank = terminal.semanticView(0).cellInfoAt(2, @intCast(col));
        try std.testing.expectEqual(@as(u32, 0), blank.codepoint);
        try std.testing.expectEqual(Terminal.Color.indexed(4), blank.attrs.bg);
    }
}

test "terminal: rectangle reverse zero toggles original four in selector order" {
    for ([_][]const u8{ "\x1b[1;1;1;1;0$t", "\x9b1;1;1;1;0$t" }) |wire| {
        for (0..wire.len + 1) |split| {
            var terminal = try Terminal.init(std.testing.allocator, 3, 4);
            defer terminal.deinit();
            try feed(&terminal, "\x1b[1;2;3;5;8;9;31;44mA\x1b[2;1H");
            const before = terminal.semanticView(0).cellInfoAt(0, 0);
            const sequence = terminal.semanticSequence();
            try std.testing.expect(!(try terminal.feed("\x1b[$t\x1b[1;1;1;1$t")).stateChanged());
            try std.testing.expectEqual(sequence, terminal.semanticSequence());
            try feed(&terminal, wire[0..split]);
            try feed(&terminal, wire[split..]);
            var expected = before;
            expected.attrs.bold = false;
            expected.attrs.underline = true;
            expected.attrs.blink = false;
            expected.attrs.reverse = true;
            try std.testing.expectEqualDeep(expected, terminal.semanticView(0).cellInfoAt(0, 0));
            try feed(&terminal, wire);
            try std.testing.expectEqualDeep(before, terminal.semanticView(0).cellInfoAt(0, 0));
            try std.testing.expect(!(try terminal.feed("\x1b[1;1;1;1;1;1$t")).stateChanged());
            try feed(&terminal, "\x1b[1;1;1;1;0;4;5$t");
            expected.attrs.underline = false;
            expected.attrs.blink = true;
            try std.testing.expectEqualDeep(expected, terminal.semanticView(0).cellInfoAt(0, 0));
            try std.testing.expectEqual(@as(u16, 1), terminal.semanticView(0).cursor_row);
            try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_col);
        }
    }
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

test "terminal: pinned libvterm string C0 policy remains independent of Howl OSC grammar" {
    // Pinned libvterm executes C0 LF, VT, FF, and CR inside OSC strings.
    // Howl holds the string boundary and does not move the cursor.
    for ([_]u8{ 0x0a, 0x0b, 0x0c, 0x0d }) |control| {
        var terminal = try Terminal.init(std.testing.allocator, 4, 8);
        defer terminal.deinit();
        try feed(&terminal, "\x1b[2;3H\x1b]2;head");
        try feed(&terminal, &.{control});
        const held = terminal.semanticView(0);
        try std.testing.expectEqual(@as(u16, 1), held.cursor_row);
        try std.testing.expectEqual(@as(u16, 2), held.cursor_col);
        try feed(&terminal, "tail\x07Z");
        const result = terminal.semanticView(0);
        try std.testing.expectEqual(@as(u16, 1), result.cursor_row);
        try std.testing.expectEqual(@as(u16, 3), result.cursor_col);
        try std.testing.expectEqual(@as(u21, 'Z'), result.cellAt(1, 2));
    }
}

test "terminal: libvterm ground C0 phantom and raw NEL retain Howl's distinct admission" {
    // Pinned libvterm can keep its one-past-column phantom after unchanged
    // coordinate C0 BS/CR. Howl stores an explicit pending-wrap flag which
    // these commands cancel, so the next cell overwrites rather than wraps.
    for ([_]u8{ 0x08, 0x0d }) |control| {
        var terminal = try Terminal.init(std.testing.allocator, 2, 1);
        defer terminal.deinit();
        try feed(&terminal, "A");
        try feed(&terminal, &.{control});
        try feed(&terminal, "B");
        const view = terminal.semanticView(0);
        try std.testing.expectEqual(@as(u21, 'B'), view.cellAt(0, 0));
        try std.testing.expectEqual(@as(u21, 0), view.cellAt(1, 0));
    }
    // Raw C1 NEL is dispatched by Howl even when UTF-8 is selected, while
    // libvterm's pinned UTF-8 parser does not dispatch a standalone 0x85.
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    try feed(&terminal, "\x1b[1;4H\x85X");
    const view = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'X'), view.cellAt(1, 0));
    try std.testing.expectEqual(@as(u16, 1), view.cursor_row);
    try std.testing.expectEqual(@as(u16, 1), view.cursor_col);
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

test "terminal: pinned Kitty bell host throttle differs from ordered native BEL events" {
    // Frozen Kitty screen.c::screen_bell suppresses repeated BEL while its
    // ignore_bells timer is active, then drives audio, visual and on_bell
    // platform hooks. Howl VT queues every BEL in exact FIFO order and
    // leaves audio/visual throttling policy to its caller.
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("\x07\x07")).stateChanged());
    try std.testing.expectEqual(@as(u16, 2), terminal.consequenceCount());
    const first = terminal.consequenceHead().?;
    try std.testing.expect(first == .bell);
    try terminal.consumeConsequence(first.id());
    const second = terminal.consequenceHead().?;
    try std.testing.expect(second == .bell);
    try std.testing.expect(second.id() > first.id());
    try terminal.consumeConsequence(second.id());
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
    try std.testing.expectEqualStrings("", terminal.replyBytes());
    try std.testing.expect((try terminal.feed("A")).stateChanged());
    try std.testing.expectEqual(@as(u21, 'A'), terminal.semanticView(0).cellAt(0, 0));
}

test "terminal: pinned iTerm2 LF VT FF and IND gate bottom scrolling outside horizontal margins" {
    // Pinned iTerm2 VT100ScreenMutableState+TerminalDelegate.m::terminalLineFeed
    // returns early at the vertical region bottom if its cursor is outside
    // the left-right scroll region. VT100Terminal.m invokes this exact
    // delegate for C0 LF, VT, FF and ESC D (IND). Howl Screen.lineFeed
    // allows the region to scroll at the same cursor coordinate.
    for ([_][]const u8{ "\x0a", "\x0b", "\x0c", "\x1bD" }) |command| {
        var terminal = try Terminal.init(std.testing.allocator, 4, 6);
        defer terminal.deinit();
        try feed(
            &terminal,
            "\x1b[1;1HAAAAAA\x1b[2;1HBBBBBB\x1b[3;1HCCCCCC\x1b[4;1HDDDDDD" ++
                "\x1b[2;3r\x1b[?69h\x1b[3;4s\x1b[3;1H",
        );
        const before = terminal.semanticView(0);
        try std.testing.expectEqual(@as(u16, 2), before.cursor_row);
        try std.testing.expectEqual(@as(u16, 0), before.cursor_col);
        try std.testing.expectEqual(@as(u21, 'B'), before.cellAt(1, 2));
        try std.testing.expectEqual(@as(u21, 'C'), before.cellAt(2, 2));
        try std.testing.expect((try terminal.feed(command)).stateChanged());
        const after = terminal.semanticView(0);
        try std.testing.expectEqual(@as(u16, 2), after.cursor_row);
        try std.testing.expectEqual(@as(u16, 0), after.cursor_col);
        try std.testing.expectEqual(@as(u21, 'C'), after.cellAt(1, 2));
        try std.testing.expectEqual(@as(u21, 0), after.cellAt(2, 2));
        try std.testing.expectEqual(@as(u21, 'B'), after.cellAt(1, 0));
        try std.testing.expectEqual(@as(u21, 'D'), after.cellAt(3, 0));
    }
}

test "terminal: pinned iTerm2 carriage return homes at horizontal margin unlike Howl" {
    // Pinned iTerm2 VT100ScreenMutableState.m::carriageReturn moves to
    // the left margin unless starting outside it on the left. Howl's
    // CR always sets column zero, independently of the horizontal region.
    for ([_]struct { column: u8, reference_home: u16 }{
        .{ .column = 1, .reference_home = 0 },
        .{ .column = 3, .reference_home = 2 },
        .{ .column = 6, .reference_home = 2 },
    }) |case| {
        var terminal = try Terminal.init(std.testing.allocator, 3, 6);
        defer terminal.deinit();
        var sequence: [32]u8 = undefined;
        const setup = try std.fmt.bufPrint(
            &sequence,
            "\x1b[?69h\x1b[3;4s\x1b[2;{d}H",
            .{case.column},
        );
        try feed(&terminal, setup);
        try std.testing.expectEqual(@as(u16, case.column - 1), terminal.semanticView(0).cursor_col);
        const update = try terminal.feed("\r");
        try std.testing.expectEqual(case.column != 1, update.stateChanged());
        const after = terminal.semanticView(0);
        try std.testing.expectEqual(@as(u16, 0), after.cursor_col);
        try std.testing.expectEqual(@as(u16, 1), after.cursor_row);
        // The expected pinned home is independently specified above,
        // exposing its conflict for inside/right-of-margin positions.
        try std.testing.expect(case.reference_home == 0 or case.reference_home == 2);
        if (case.column != 1) try std.testing.expect(case.reference_home != after.cursor_col);
    }
}

test "terminal: pinned iTerm2 NEL and RI gate margin-edge scrolling unlike Howl" {
    // Pinned iTerm2 invokes terminalLineFeed THEN carriageReturn for ESC E.
    // When outside LR margins at the bottom, the first step is a no-op,
    // whereas Howl's NEL changes column then scrolls. At the top, pinned
    // VT100ScreenMutableState.m::reverseIndex likewise refuses to scroll
    // outside horizontal margins; Howl Screen.reverseIndex does scroll.
    for ([_]struct { command: []const u8, row: u8, expected_top: u21, expected_bottom: u21 }{
        .{ .command = "\x1bE", .row = 3, .expected_top = 'C', .expected_bottom = 0 },
        .{ .command = "\x1bM", .row = 2, .expected_top = 0, .expected_bottom = 'B' },
    }) |case| {
        var terminal = try Terminal.init(std.testing.allocator, 4, 6);
        defer terminal.deinit();
        try feed(&terminal, "\x1b[1;1HAAAAAA\x1b[2;1HBBBBBB\x1b[3;1HCCCCCC\x1b[4;1HDDDDDD\x1b[2;3r\x1b[?69h\x1b[3;4s");
        var pos: [24]u8 = undefined;
        try feed(&terminal, try std.fmt.bufPrint(&pos, "\x1b[{d};1H", .{case.row}));
        try std.testing.expect((try terminal.feed(case.command)).stateChanged());
        const view = terminal.semanticView(0);
        try std.testing.expectEqual(case.expected_top, view.cellAt(1, 2));
        try std.testing.expectEqual(case.expected_bottom, view.cellAt(2, 2));
        try std.testing.expectEqual(@as(u16, 0), view.cursor_col);
        try std.testing.expectEqual(@as(u16, case.row - 1), view.cursor_row);
        try std.testing.expectEqual(@as(u21, 'A'), view.cellAt(0, 0));
        try std.testing.expectEqual(@as(u21, 'D'), view.cellAt(3, 0));
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

test "terminal: libvterm SS2 survives SO and SI until the next graphic" {
    for ([_]struct { shift: u8, second: u21 }{
        .{ .shift = 0x0e, .second = 0x23bc },
        .{ .shift = 0x0f, .second = 'r' },
    }) |case| {
        var terminal = try Terminal.init(std.testing.allocator, 2, 16);
        defer terminal.deinit();
        try feed(&terminal, "\x1b)0\x1b*0\x1b");
        try feed(&terminal, "N");
        try feed(&terminal, &.{case.shift});
        try feed(&terminal, "qr");
        try std.testing.expectEqual(@as(u21, 0x2500), terminal.semanticView(0).cellAt(0, 0));
        try std.testing.expectEqual(case.second, terminal.semanticView(0).cellAt(0, 1));
    }
}

test "terminal: libvterm string-embedded SO and SI remain a distinct C0 parser policy" {
    // Frozen libvterm executes C0 SO/SI during OSC payload assembly and
    // changes GL for following text. Howl deliberately keeps these bytes
    // out of OSC content and does not execute a charset switch.
    var shifted = try Terminal.init(std.testing.allocator, 2, 16);
    defer shifted.deinit();
    try feed(&shifted, "\x1b)0\x1b]2;x\x0ey\x07q");
    try std.testing.expectEqual(@as(u21, 'q'), shifted.semanticView(0).cellAt(0, 0));
    try feed(&shifted, "\x0eq");
    try std.testing.expectEqual(@as(u21, 0x2500), shifted.semanticView(0).cellAt(0, 1));

    var unshifted = try Terminal.init(std.testing.allocator, 2, 16);
    defer unshifted.deinit();
    try feed(&unshifted, "\x1b)0\x0e\x1b]2;x\x0fy\x07q");
    try std.testing.expectEqual(@as(u21, 0x2500), unshifted.semanticView(0).cellAt(0, 0));
    try feed(&unshifted, "\x0fq");
    try std.testing.expectEqual(@as(u21, 'q'), unshifted.semanticView(0).cellAt(0, 1));
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

test "terminal: pinned libvterm UTF8 GR locking shifts differ from Howl Unicode mapping" {
    // Pinned libvterm src/state.c:on_text sends high-bit input to
    // encoding_utf8 when vt->mode.utf8 is enabled, before choosing GR.
    // Thus ESC ~, }, | change GR selection but cannot remap UTF-8 ñ.
    // Howl's charset mapCodepoint still applies configured GR G1-G3
    // to decoded U+00F1, mapping its 0x71 low byte to DEC line 'q'.
    for ([_]struct { designation: []const u8, shift: []const u8 }{
        .{ .designation = "\x1b)0", .shift = "\x1b~" },
        .{ .designation = "\x1b*0", .shift = "\x1b}" },
        .{ .designation = "\x1b+0", .shift = "\x1b|" },
    }) |case| {
        var terminal = try Terminal.init(std.testing.allocator, 1, 8);
        defer terminal.deinit();
        try feed(&terminal, "\x1b%G");
        try std.testing.expect((try terminal.feed(case.designation)).stateChanged());
        if (!std.mem.eql(u8, case.shift, "\x1b~"))
            try std.testing.expect((try terminal.feed(case.shift)).stateChanged())
        else
            try std.testing.expect(!(try terminal.feed(case.shift)).stateChanged());
        try std.testing.expect(!(try terminal.feed("\xc3")).stateChanged());
        try std.testing.expect((try terminal.feed("\xb1")).stateChanged());
        try std.testing.expectEqual(@as(u21, 0x2500), terminal.semanticView(0).cellAt(0, 0));
        // ASCII GL text remains unaffected by GR selection.
        try feed(&terminal, "q");
        try std.testing.expectEqual(@as(u21, 'q'), terminal.semanticView(0).cellAt(0, 1));
    }
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

test "terminal: pinned libvterm DECSWL requires a line-info callback unlike Howl" {
    // Pinned libvterm src/state.c::set_lineinfo commits NO_FORCE changes
    // only when a registered setlineinfo callback returns true. ESC # 5
    // is NO_FORCE and may therefore leave lineinfo unchanged; Howl's
    // Screen.applyLineGeometry directly owns the transition.
    for ([_]struct { command: []const u8, geometry: Terminal.LineGeometry }{
        .{ .command = "\x1b#3", .geometry = .double_height_top },
        .{ .command = "\x1b#4", .geometry = .double_height_bottom },
        .{ .command = "\x1b#6", .geometry = .double_width },
    }) |case| {
        var terminal = try Terminal.init(std.testing.allocator, 2, 8);
        defer terminal.deinit();
        try std.testing.expect(!(try terminal.feed("\x1b#5")).stateChanged());
        try std.testing.expect((try terminal.feed(case.command)).stateChanged());
        try std.testing.expectEqual(case.geometry, terminal.semanticView(0).lineGeometry(0));
        try std.testing.expect((try terminal.feed("\x1b#5")).stateChanged());
        try std.testing.expectEqual(Terminal.LineGeometry.single_width, terminal.semanticView(0).lineGeometry(0));
        try std.testing.expect(!(try terminal.feed("\x1b#5")).stateChanged());
        try std.testing.expect((try terminal.feed("\x1b[?69h")).stateChanged());
        // Both implementations ignore DEC line geometry while DECLRMM
        // is enabled, including all four ESC # 3..6 commands.
        for ([_][]const u8{ "\x1b#3", "\x1b#4", "\x1b#5", "\x1b#6" }) |command|
            try std.testing.expect(!(try terminal.feed(command)).stateChanged());
        try std.testing.expectEqual(Terminal.LineGeometry.single_width, terminal.semanticView(0).lineGeometry(0));
    }
}

test "terminal: libvterm ICH and DCH require vertical scroll-region admission" {
    // Pinned libvterm src/state.c:on_csi calls is_cursor_in_scrollregion
    // for both ICH and DCH. Howl Screen.insertChars/deleteChars check
    // the horizontal edit region but permit ordinary row edits outside
    // the current vertical scroll region.
    for ([_]struct { command: []const u8, expected: []const u8 }{
        .{ .command = "\x1b[2@", .expected = "AB  CD" },
        .{ .command = "\x1b[2P", .expected = "ABEF  " },
    }) |case| {
        var terminal = try Terminal.init(std.testing.allocator, 4, 6);
        defer terminal.deinit();
        try feed(&terminal, "\x1b[1;1HABCDEF\x1b[2;1HGHIJKL\x1b[2;3r\x1b[1;3H");
        try std.testing.expect((try terminal.feed(case.command)).stateChanged());
        const view = terminal.semanticView(0);
        try std.testing.expectEqual(@as(u16, 0), view.cursor_row);
        try std.testing.expectEqual(@as(u16, 2), view.cursor_col);
        for (case.expected, 0..) |byte, col|
            try std.testing.expectEqual(if (byte == ' ') @as(u21, 0) else @as(u21, byte), view.cellAt(0, @intCast(col)));
        for ("GHIJKL", 0..) |byte, col|
            try std.testing.expectEqual(@as(u21, byte), view.cellAt(1, @intCast(col)));
    }
}

test "terminal: libvterm ED3 callback gate differs from native scrollback clearing" {
    // Pinned libvterm src/state.c:on_csi handles ordinary and selective
    // ED mode 3 through optional state->callbacks->sb_clear. With no
    // callback or an unaccepted result it does not erase scrollback.
    // Howl Screen.eraseDisplay(.scrollback) directly clears its history.
    for ([_][]const u8{ "\x1b[3J", "\x1b[?3J" }) |sequence| {
        var terminal = try Terminal.initWithHistory(std.testing.allocator, 2, 6, 8);
        defer terminal.deinit();
        try feed(&terminal, "one\r\ntwo\r\nthree");
        try std.testing.expect(terminal.semanticView(0).history_count > 0);
        const before = terminal.semanticView(0).cellAt(0, 0);
        try std.testing.expect((try terminal.feed(sequence)).stateChanged());
        const after = terminal.semanticView(0);
        try std.testing.expectEqual(@as(u32, 0), after.history_count);
        try std.testing.expectEqual(before, after.cellAt(0, 0));
        try std.testing.expect(!(try terminal.feed(sequence)).stateChanged());
    }
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

test "terminal: character edits beyond shifted DEC row width are no-ops" {
    var terminal = try Terminal.init(std.testing.allocator, 4, 10);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b[3;1H\x1b#6")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[2;4r\x1b[2;9H")).stateChanged());
    var view = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u16, 1), view.cursor_row);
    try std.testing.expectEqual(@as(u16, 8), view.cursor_col);
    try std.testing.expectEqual(Terminal.LineGeometry.single_width, view.lineGeometry(view.cursor_row));

    try std.testing.expect((try terminal.feed("\x1b[S")).stateChanged());
    view = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u16, 8), view.cursor_col);
    try std.testing.expectEqual(Terminal.LineGeometry.double_width, view.lineGeometry(view.cursor_row));

    try std.testing.expect(!(try terminal.feed("\x1b[@")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[P")).stateChanged());
    view = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u16, 8), view.cursor_col);
    try std.testing.expectEqual(Terminal.LineGeometry.double_width, view.lineGeometry(view.cursor_row));
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
    // TBC 5 is a no-op: the stop at column 10 survives the query.
    try std.testing.expect(!(try terminal.feed("\x1b[5g\r\x09")).historyLost());
    try std.testing.expectEqual(@as(u16, 10), terminal.semanticView(0).cursor_col);

    try std.testing.expect(!(try terminal.feed("\x1b[6G\x1bH\x1b[3g\r\x09")).historyLost());
    try std.testing.expectEqual(@as(u16, 19), terminal.semanticView(0).cursor_col);
    try std.testing.expect(!(try terminal.feed("\x1b[?5W\r\x09\x1b[I\x1b[999999Z")).historyLost());
    try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_col);

    try std.testing.expect(!(try terminal.feed("\x1b[6G\x88\r\x09")).historyLost());
    try std.testing.expectEqual(@as(u16, 5), terminal.semanticView(0).cursor_col);
}

test "terminal: tab stops remain bank local and Kitty DECST8C resets only the active bank" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 20);
    defer terminal.deinit();

    // Custom primary stop at physical column 6, with defaults removed.
    try feed(&terminal, "\x1b[3g\x1b[6G\x1bH\r\t");
    try std.testing.expectEqual(@as(u16, 5), terminal.semanticView(0).cursor_col);

    // Kitty's alternate buffer owns independent default stops. Entering it
    // does not borrow the primary stop at column 6.
    try feed(&terminal, "\x1b[?1049h\r\t");
    try std.testing.expect(terminal.semanticView(0).is_alternate_screen);
    try std.testing.expectEqual(@as(u16, 8), terminal.semanticView(0).cursor_col);

    // Change the alternate's tabs, then reset default spacing on that bank
    // only. Re-entering the alternate later preserves this reset.
    // C1 HTS and ESC HTS share libvterm's one set_col_tabstop owner.
    // Both change only the active bank in Howl.
    try feed(&terminal, "\x1b[3g\x1b[13G\x88\x1bH\r\t");
    try std.testing.expectEqual(@as(u16, 12), terminal.semanticView(0).cursor_col);
    // Only private CSI ? 5 W is DECST8C. An ordinary CSI 5 W or an
    // unknown private option must not reset the custom alternate stops.
    try feed(&terminal, "\x1b[5W\x1b[?4W\x1b[?5;1W\r\t");
    try std.testing.expectEqual(@as(u16, 12), terminal.semanticView(0).cursor_col);
    try feed(&terminal, "\x9b?5W\r\t");
    try std.testing.expectEqual(@as(u16, 8), terminal.semanticView(0).cursor_col);
    try feed(&terminal, "\t");
    try std.testing.expectEqual(@as(u16, 16), terminal.semanticView(0).cursor_col);

    try feed(&terminal, "\x1b[?1049l\r\t");
    try std.testing.expect(!terminal.semanticView(0).is_alternate_screen);
    try std.testing.expectEqual(@as(u16, 5), terminal.semanticView(0).cursor_col);
    try feed(&terminal, "\x1b[?1049h\r\t");
    try std.testing.expectEqual(@as(u16, 8), terminal.semanticView(0).cursor_col);

    // Growth retains the existing bank-specific prefix and supplies new
    // eight-column defaults, including the first added stop at column 25.
    try terminal.resize(3, 30);
    try feed(&terminal, "\r\x1b[3I");
    try std.testing.expectEqual(@as(u16, 24), terminal.semanticView(0).cursor_col);
    try feed(&terminal, "\x1b[?1049l\r\t");
    try std.testing.expectEqual(@as(u16, 5), terminal.semanticView(0).cursor_col);
}

test "terminal: bank-local stops differ from pinned libvterm and iTerm2 global stop owners" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 20);
    defer terminal.deinit();

    // One custom primary stop, no default stops.
    try feed(&terminal, "\x1b[3g\x1b[6G\x1bH\r\t");
    try std.testing.expectEqual(@as(u16, 5), terminal.semanticView(0).cursor_col);

    // Pinned libvterm and iTerm2 store one tab-stop owner outside the
    // primary/alternate grid. Their alternate HT/CHT/CBT all see column 5;
    // Howl and pinned Kitty retain separate banks, so alt starts at 8.
    try feed(&terminal, "\x1b[?1049h\r\t");
    try std.testing.expectEqual(@as(u16, 8), terminal.semanticView(0).cursor_col);
    try feed(&terminal, "\r\x1b[I");
    try std.testing.expectEqual(@as(u16, 8), terminal.semanticView(0).cursor_col);
    try feed(&terminal, "\x1b[19G\x1b[Z");
    try std.testing.expectEqual(@as(u16, 16), terminal.semanticView(0).cursor_col);

    // Alternate HTS plus TBC alter only Howl's active bank. On the frozen
    // libvterm/iTerm2 global owner these changes replace primary's stops.
    try feed(&terminal, "\x1b[3g\x1b[13G\x1bH\r\t");
    try std.testing.expectEqual(@as(u16, 12), terminal.semanticView(0).cursor_col);
    try feed(&terminal, "\x1b[?1049l\r\t");
    try std.testing.expectEqual(@as(u16, 5), terminal.semanticView(0).cursor_col);
    try feed(&terminal, "\x1b[20G\x1b[Z");
    try std.testing.expectEqual(@as(u16, 5), terminal.semanticView(0).cursor_col);

    // The alternate remains independent after a second enter/exit.
    try feed(&terminal, "\x1b[?1049h\r\t\x1b[?1049l\r\t");
    try std.testing.expectEqual(@as(u16, 5), terminal.semanticView(0).cursor_col);
}

test "terminal: tab-stop growth differs from pinned iTerm2's retained offscreen stops" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 20);
    defer terminal.deinit();
    try feed(&terminal, "\x1b[3g\r\t");
    try std.testing.expectEqual(@as(u16, 19), terminal.semanticView(0).cursor_col);

    // iTerm2 creates the default stop set out to 1000 columns. Clearing
    // it removes even out-of-view stops. Howl allocates only 20 columns
    // and after growth installs new 8-column stops at columns 24, etc.
    try terminal.resize(2, 30);
    try feed(&terminal, "\r\t");
    try std.testing.expectEqual(@as(u16, 24), terminal.semanticView(0).cursor_col);
}

test "terminal: accepted DEC/xterm TBC unsupported selectors preserve state and tabs" {
    const ignored = [_][]const u8{
        "\x1b[1g", "\x1b[2g", "\x1b[4g", "\x1b[5g", "\x9b5g",
    };
    for (ignored) |command| {
        var terminal = try Terminal.init(std.testing.allocator, 2, 20);
        defer terminal.deinit();
        try feed(&terminal, "\x1b[3g\x1b[6G\x1bH");
        const identity = terminal.semanticSequence();
        const first = command.len - 1;
        try std.testing.expect(!(try terminal.feed(command[0..first])).stateChanged());
        try std.testing.expect(!(try terminal.feed(command[first..])).stateChanged());
        try std.testing.expectEqual(identity, terminal.semanticSequence());
        try std.testing.expectEqualStrings("", terminal.replyBytes());
        try feed(&terminal, "\r\t");
        try std.testing.expectEqual(@as(u16, 5), terminal.semanticView(0).cursor_col);
    }
}

test "terminal: accepted DEC/xterm TBC 5 preserves a custom stop" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 20);
    defer terminal.deinit();
    try feed(&terminal, "\x1b[3g\x1b[6G\x1bH\r\t");
    try std.testing.expectEqual(@as(u16, 5), terminal.semanticView(0).cursor_col);
    // DEC/xterm, iTerm2 and Kitty retain the custom stop for Ps=5.
    // libvterm's Ps=5 all-clear is recorded as an unsupported alternative.
    try feed(&terminal, "\x1b[5g\r\t");
    try std.testing.expectEqual(@as(u16, 5), terminal.semanticView(0).cursor_col);
}

test "terminal: iTerm2 blank-span tab filler is not retained by Howl canonical cells" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 20);
    defer terminal.deinit();
    try feed(&terminal, "\x1b[H\t");
    try std.testing.expectEqual(@as(u16, 8), terminal.semanticView(0).cursor_col);
    // Pinned iTerm2 appendTabAtCursor inserts TAB_FILLER and publishes
    // the tab through screenAppendScreenCharArray on a blank span.
    // Howl's C0 HT / CSI CHT are cursor-only and do not retain it.
    for (0..8) |col| {
        try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(0, @intCast(col)));
    }
    try feed(&terminal, "\r\x1b[I");
    try std.testing.expectEqual(@as(u16, 8), terminal.semanticView(0).cursor_col);
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(0, 0));
}

test "terminal: DEC/xterm TBC five remains a no-op after custom HTS" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 20);
    defer terminal.deinit();

    try feed(&terminal, "\x1b[3g\x1b[6G\x1bH\r\t");
    try std.testing.expectEqual(@as(u16, 5), terminal.semanticView(0).cursor_col);
    // Ps=5 must preserve the stop; only 0 and 3 clear DEC/xterm tabs.
    try feed(&terminal, "\x1b[5g\r\t");
    try std.testing.expectEqual(@as(u16, 5), terminal.semanticView(0).cursor_col);
    try feed(&terminal, "\x1b[?5W\r\t");
    try std.testing.expectEqual(@as(u16, 8), terminal.semanticView(0).cursor_col);
}

test "terminal: forward tabs move the cursor without Kitty preserved tab marker cells" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 20);
    defer terminal.deinit();
    try feed(&terminal, "\x1b[H\x1b[I");
    try std.testing.expectEqual(@as(u16, 8), terminal.semanticView(0).cursor_col);
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(0, 1));
    // Pinned Kitty screen_tab, when intervening cells are blank, stores a
    // composite tab marker at the source. Its line-string test observes
    // this as '\t'; Howl retains only cursor movement without that marker.
    try feed(&terminal, "\r\t");
    try std.testing.expectEqual(@as(u16, 8), terminal.semanticView(0).cursor_col);
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(0, 0));
}

test "terminal: HTS at pending wrap retains physical column stop unlike Kitty phantom skip" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 20);
    defer terminal.deinit();
    try feed(&terminal, "\x1b[3gABCDEFGHIJKLMNOPQRST\x1bH");
    // Howl represents the phantom edge as wrap_pending plus col=19 and
    // currently sets a stop there; pinned Kitty has cursor->x >= columns
    // on a phantom edge and refuses to set a stop outside the grid.
    try terminal.resize(2, 30);
    try feed(&terminal, "\r\t");
    try std.testing.expectEqual(@as(u16, 19), terminal.semanticView(0).cursor_col);
}

test "terminal: Kitty CBT traverses only active-bank stops and clamps exact counts" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 20);
    defer terminal.deinit();
    try feed(&terminal, "\x1b[3g\x1b[6G\x1bH\x1b[11G\x1bH\x1b[20G");
    try feed(&terminal, "\x1b[0Z");
    try std.testing.expectEqual(@as(u16, 10), terminal.semanticView(0).cursor_col);
    try feed(&terminal, "\x9b2Z");
    try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_col);
    try feed(&terminal, "\x1b[999999Z");
    try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_col);

    try feed(&terminal, "\x1b[?1049h\x1b[18G\x1b[Z");
    try std.testing.expectEqual(@as(u16, 16), terminal.semanticView(0).cursor_col);
    try feed(&terminal, "\x1b[?1049l\x1b[20G\x1b[Z");
    try std.testing.expectEqual(@as(u16, 10), terminal.semanticView(0).cursor_col);
}

test "terminal: pinned libvterm UTF8 C1 RI admission differs from Howl" {
    // Pinned libvterm src/parser.c c1_allowed = !vt->mode.utf8. When its
    // UTF-8 mode is enabled, raw 0x8d is sent to the text callback, not
    // src/state.c::on_control(RI). Howl accepts raw RI even in UTF-8.
    for ([_][]const u8{ "\x8d", "\x1bM" }) |ri| {
        var terminal = try Terminal.init(std.testing.allocator, 3, 4);
        defer terminal.deinit();
        try feed(&terminal, "\x1b%G\x1b[2;3r\x1b[2;1HBBBB\x1b[3;1HCCCC\x1b[2;3H");
        try std.testing.expect((try terminal.feed(ri)).stateChanged());
        const view = terminal.semanticView(0);
        try std.testing.expectEqual(@as(u21, 0), view.cellAt(1, 0));
        try std.testing.expectEqual(@as(u21, 'B'), view.cellAt(2, 0));
        try std.testing.expectEqual(@as(u16, 1), view.cursor_row);
        try std.testing.expectEqual(@as(u16, 2), view.cursor_col);
        try std.testing.expectEqual(@as(u21, 0), view.cellAt(0, 0));
    }
}

test "terminal: pinned libvterm SS2 C1 UTF8 gate and ESC N alias differ from Howl" {
    // In pinned libvterm src/state.c on_control handles only raw 0x8e
    // for SS2, while on_escape has no ESC N case. The C1 is disabled
    // by its parser when vterm_set_utf8(vt, 1) is active.
    var terminal = try Terminal.init(std.testing.allocator, 1, 8);
    defer terminal.deinit();
    try feed(&terminal, "\x1b*0\x1b%G");
    try std.testing.expect((try terminal.feed("\x8e")).stateChanged());
    try feed(&terminal, "qq");
    try std.testing.expectEqual(@as(u21, 0x2500), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'q'), terminal.semanticView(0).cellAt(0, 1));
    try std.testing.expect(!(try terminal.feed("\x1b")).stateChanged());
    try std.testing.expect((try terminal.feed("N")).stateChanged());
    try feed(&terminal, "qq");
    try std.testing.expectEqual(@as(u21, 0x2500), terminal.semanticView(0).cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 'q'), terminal.semanticView(0).cellAt(0, 3));
}

test "terminal: pinned libvterm SS3 C1 UTF8 gate and ESC O alias differ from Howl" {
    // Pinned libvterm has on_control(0x8f) but no on_escape ESC O
    // selector and disables C1 dispatch in UTF-8. Howl implements both
    // forms with one-shot G3 charset mapping.
    var terminal = try Terminal.init(std.testing.allocator, 1, 8);
    defer terminal.deinit();
    try feed(&terminal, "\x1b+A\x1b%G");
    try std.testing.expect((try terminal.feed("\x8f")).stateChanged());
    try feed(&terminal, "##");
    try std.testing.expectEqual(@as(u21, 0x00A3), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, '#'), terminal.semanticView(0).cellAt(0, 1));
    try std.testing.expect(!(try terminal.feed("\x1b")).stateChanged());
    try std.testing.expect((try terminal.feed("O")).stateChanged());
    try feed(&terminal, "##");
    try std.testing.expectEqual(@as(u21, 0x00A3), terminal.semanticView(0).cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, '#'), terminal.semanticView(0).cellAt(0, 3));
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

test "terminal: IND ignores ANSI newline mode while LF and NEL retain their own column rules" {
    for ([_][]const u8{ "\x1bD", "\x84" }) |ind| {
        var terminal = try Terminal.init(std.testing.allocator, 4, 8);
        defer terminal.deinit();
        try feed(&terminal, "\x1b[20h\x1b[1;5H");
        try feed(&terminal, ind[0 .. ind.len - 1]);
        try feed(&terminal, ind[ind.len - 1 ..]);
        try std.testing.expectEqual(@as(u16, 1), terminal.semanticView(0).cursor_row);
        try std.testing.expectEqual(@as(u16, 4), terminal.semanticView(0).cursor_col);

        try feed(&terminal, "\x1b[1;5H\n");
        try std.testing.expectEqual(@as(u16, 1), terminal.semanticView(0).cursor_row);
        try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_col);

        try feed(&terminal, "\x1b[1;5H\x1bE");
        try std.testing.expectEqual(@as(u16, 1), terminal.semanticView(0).cursor_row);
        try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_col);
    }
}

test "terminal: bare CSI s selects DEC savepoint or default margins by DECLRMM" {
    for ([_][]const u8{ "\x1b[s", "\x9bs" }) |command| {
        for (0..command.len + 1) |split| {
            var terminal = try Terminal.init(std.testing.allocator, 4, 8);
            defer terminal.deinit();

            // With DECLRMM disabled, CSI s and ESC 8 share the DEC savepoint.
            try feed(&terminal, "\x1b[2;5H\x1b[1m");
            try feed(&terminal, command[0..split]);
            try feed(&terminal, command[split..]);
            try feed(&terminal, "\x1b[0m\x1b[3;6H\x1b8");
            try std.testing.expectEqual(@as(u16, 1), terminal.semanticView(0).cursor_row);
            try std.testing.expectEqual(@as(u16, 4), terminal.semanticView(0).cursor_col);
            try feed(&terminal, "S");
            try std.testing.expect(terminal.semanticView(0).cellInfoAt(1, 4).attrs.bold);

            // With DECLRMM enabled, bare CSI s resets the horizontal margins
            // without replacing an independent ESC 7 savepoint.
            try feed(&terminal, "\x1b[?69h\x1b[2;7s\x1b[2;5H\x1b7\x1b[3;6H");
            try feed(&terminal, command[0..split]);
            try feed(&terminal, command[split..]);
            try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_row);
            try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_col);
            try std.testing.expect(!(try terminal.feed(command)).stateChanged());
            try feed(&terminal, "\x1b[?6h\x1b[1;8H");
            try std.testing.expectEqual(@as(u16, 7), terminal.semanticView(0).cursor_col);

            try feed(&terminal, "\x1b[u");
            try std.testing.expectEqual(@as(u16, 1), terminal.semanticView(0).cursor_row);
            try std.testing.expectEqual(@as(u16, 4), terminal.semanticView(0).cursor_col);

            // Private Kitty negotiation is independent of ordinary CSI u.
            try feed(&terminal, "\x1b[=1u\x1b[?u");
            try std.testing.expectEqualStrings("\x1b[?1u", terminal.replyBytes());
        }
    }
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

test "terminal: DECFI and DECBI outside horizontal margins shift matching image columns" {
    const cases = [_]struct {
        command: []const u8,
        image_col: u16,
        cursor_col: u16,
        expected_col: u16,
        expected_text: u21,
    }{
        .{ .command = "\x1b9", .image_col = 4, .cursor_col = 5, .expected_col = 3, .expected_text = 'E' },
        .{ .command = "\x1b6", .image_col = 2, .cursor_col = 0, .expected_col = 3, .expected_text = 'C' },
    };
    for (cases) |case| {
        var terminal = try Terminal.init(std.testing.allocator, 3, 6);
        defer terminal.deinit();
        try terminal.setCellPixelSize(1, 1);
        try feed(&terminal, "\x1b[1;1HABCDEF");
        var cmd: [24]u8 = undefined;
        try feed(&terminal, try std.fmt.bufPrint(&cmd, "\x1b[1;{d}H", .{case.image_col + 1}));
        try feed(&terminal, "\x1b_Ga=T,f=32,s=1,v=1,i=37,C=1;AQIDBA==\x1b\\");
        try consumeReplies(&terminal);
        try std.testing.expectEqual(case.image_col, terminal.images(0).placement(0).?.col);
        try feed(&terminal, "\x1b[?69h\x1b[2;4s");
        try feed(&terminal, try std.fmt.bufPrint(&cmd, "\x1b[1;{d}H", .{case.cursor_col + 1}));
        const before = terminal.images(0);
        try std.testing.expect((try terminal.feed(case.command)).stateChanged());
        const after = terminal.images(0);
        try std.testing.expectEqual(case.expected_col, after.placement(0).?.col);
        try std.testing.expectEqual(case.expected_text, terminal.semanticView(0).cellAt(0, 3));
        try std.testing.expect(after.generation > before.generation);
        try std.testing.expectEqual(before.content_generation, after.content_generation);
        try std.testing.expectEqual(@as(u8, 0), terminal.consequenceCount());
    }
}

test "terminal: CSI horizontal row shifts keep image placements with admitted text" {
    for ([_]struct {
        sequence: []const u8,
        source_col: u16,
        expected_col: u16,
    }{
        .{ .sequence = "\x1b[ @", .source_col = 4, .expected_col = 3 },
        .{ .sequence = "\x1b[ A", .source_col = 2, .expected_col = 3 },
    }) |case| {
        var terminal = try Terminal.init(std.testing.allocator, 3, 6);
        defer terminal.deinit();
        try terminal.setCellPixelSize(1, 1);
        try feed(&terminal, "\x1b[1;1HABCDEF\x1b[2;1HABCDEF\x1b[3;1HABCDEF");
        var position: [20]u8 = undefined;
        try feed(&terminal, try std.fmt.bufPrint(&position, "\x1b[2;{d}H", .{case.source_col + 1}));
        try feed(&terminal, "\x1b_Ga=T,f=32,s=1,v=1,i=71,C=1;AQIDBA==\x1b\\");
        try feed(&terminal, "\x1b[3;5H\x1b_Ga=T,f=32,s=1,v=1,i=72,C=1;AQIDBA==\x1b\\");
        try consumeReplies(&terminal);
        try std.testing.expectEqual(@as(usize, 2), terminal.images(0).placementCount());
        try std.testing.expectEqual(case.source_col, terminal.images(0).placement(0).?.col);
        try std.testing.expectEqual(@as(u16, 4), terminal.images(0).placement(1).?.col);

        // The first two rows shift; the fixed bottom row and its placement do not.
        try feed(&terminal, "\x1b[1;2r");
        const before = terminal.images(0);
        try std.testing.expect((try terminal.feed(case.sequence)).stateChanged());
        const after = terminal.images(0);
        try std.testing.expectEqual(case.expected_col, after.placement(0).?.col);
        try std.testing.expectEqual(@as(u16, 4), after.placement(1).?.col);
        try std.testing.expect(after.generation > before.generation);
        try std.testing.expectEqual(before.content_generation, after.content_generation);
        try std.testing.expectEqual(@as(u21, if (case.source_col == 4) 'E' else 'C'), terminal.semanticView(0).cellAt(1, 3));
        try std.testing.expectEqual(@as(u21, 'E'), terminal.semanticView(0).cellAt(2, 4));
    }
}

test "terminal: CSI partial-column shift retires only straddling placement, not its image" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    try terminal.setCellPixelSize(1, 1);
    // Two-pixel image covers columns 2-3, crossing the later left margin
    // (column 3). A whole-placement translation would mutate an outside cell.
    try feed(&terminal, "\x1b[2;2H\x1b_Ga=T,f=32,s=2,v=1,i=73,C=1;AQIDBAUGBwg=\x1b\\");
    try consumeReplies(&terminal);
    try std.testing.expectEqual(@as(usize, 1), terminal.images(0).placementCount());
    try std.testing.expectEqual(@as(usize, 1), terminal.images(0).imageCount());
    const image_generation = terminal.images(0).content_generation;

    try feed(&terminal, "\x1b[?69h\x1b[3;6s\x1b[1;2r");
    try std.testing.expect((try terminal.feed("\x1b[ @")).stateChanged());
    try std.testing.expectEqual(@as(usize, 0), terminal.images(0).placementCount());
    try std.testing.expectEqual(@as(usize, 1), terminal.images(0).imageCount());
    try std.testing.expectEqual(image_generation, terminal.images(0).content_generation);
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

test "terminal: pinned Kitty VPA CBT reject excess operands and preserve cursor and graphics" {
    // Frozen Kitty d4106ef vt-parser.c::dispatch_csi uses
    // CALL_CSI_HANDLER1 for VPA and CBT. An extra operand must not
    // reach either cursor owner; final empty semicolons add no operand.
    // Pinned libvterm state.c::on_csi and iTerm2's VT100CSIParser.m and
    // VT100Terminal.m consume only the first operand without that guard.
    // The catalogue explicitly adjudicates these same-wire differences.
    const image = "\x1b_Ga=T,f=32,s=1,v=1,i=96,C=1;AQIDBA==\x1b\\";
    for ([_]struct { invalid: []const u8, valid: []const u8, row: u16, col: u16 }{
        .{ .invalid = "\x1b[3;2d", .valid = "\x1b[4d", .row = 4, .col = 18 },
        .{ .invalid = "\x1b[1;3d", .valid = "\x1b[4d", .row = 4, .col = 18 },
        .{ .invalid = "\x1b[3;;d", .valid = "\x1b[4d", .row = 4, .col = 18 },
        .{ .invalid = "\x1b[3:2d", .valid = "\x1b[4d", .row = 4, .col = 18 },
        .{ .invalid = "\x9b3;2d", .valid = "\x1b[4d", .row = 4, .col = 18 },
        .{ .invalid = "\x1b[3;2;1d", .valid = "\x1b[4d", .row = 4, .col = 18 },
        .{ .invalid = "\x1b[1;2Z", .valid = "\x1b[Z", .row = 2, .col = 16 },
        .{ .invalid = "\x1b[1;;Z", .valid = "\x1b[Z", .row = 2, .col = 16 },
        .{ .invalid = "\x1b[1:2Z", .valid = "\x1b[Z", .row = 2, .col = 16 },
        .{ .invalid = "\x9b1;2Z", .valid = "\x1b[Z", .row = 2, .col = 16 },
        .{ .invalid = "\x1b[;2Z", .valid = "\x1b[Z", .row = 2, .col = 16 },
        .{ .invalid = "\x1b[1;2;0Z", .valid = "\x1b[Z", .row = 2, .col = 16 },
    }) |case| {
        var terminal = try Terminal.initWithHistory(std.testing.allocator, 6, 20, 4);
        defer terminal.deinit();
        try terminal.setCellPixelSize(1, 1);
        try feed(&terminal, "\x1b[1;1HAAAAAAAA\x1b[2;1HBBBBBBBB\x1b[3;1HCCCCCCCC\x1b[4;1HDDDDDDDD\x1b[5;1HEEEEEEEE\x1b[6;1HFFFFFFFF");
        try feed(&terminal, "\x1b[3;2H" ++ image ++ "\x1b[2;5r\x1b[?6h\x1b[2;19H");
        try consumeReplies(&terminal);
        const before = terminal.semanticView(0);
        try std.testing.expectEqual(@as(u16, 2), before.cursor_row);
        try std.testing.expectEqual(@as(u16, 18), before.cursor_col);
        const baseline_cells = [_]@TypeOf(before.cellInfoAt(0, 0)){
            before.cellInfoAt(0, 0),
            before.cellInfoAt(1, 0),
            before.cellInfoAt(2, 0),
            before.cellInfoAt(3, 0),
            before.cellInfoAt(4, 0),
            before.cellInfoAt(5, 0),
        };
        const sequence = terminal.semanticSequence();
        const edit_generation = terminal.observation().structuralEditGeneration();
        const graphics = terminal.images(0);
        try std.testing.expectEqual(@as(usize, 1), graphics.placementCount());
        const placement = graphics.placement(0).?;
        const image_count = graphics.imageCount();
        const image_generation = graphics.generation;
        const content_generation = graphics.content_generation;

        try std.testing.expect(!(try terminal.feed(case.invalid[0 .. case.invalid.len - 1])).stateChanged());
        try std.testing.expect(!(try terminal.feed(case.invalid[case.invalid.len - 1 ..])).stateChanged());
        const after = terminal.semanticView(0);
        try std.testing.expectEqual(sequence, terminal.semanticSequence());
        try std.testing.expectEqual(before.cursor_row, after.cursor_row);
        try std.testing.expectEqual(before.cursor_col, after.cursor_col);
        try std.testing.expectEqual(before.history_count, after.history_count);
        try std.testing.expectEqual(edit_generation, terminal.observation().structuralEditGeneration());
        for (baseline_cells, 0..) |cell, row| try std.testing.expectEqualDeep(cell, after.cellInfoAt(@intCast(row), 0));
        try std.testing.expectEqual(image_count, terminal.images(0).imageCount());
        try std.testing.expectEqual(@as(usize, 1), terminal.images(0).placementCount());
        try std.testing.expectEqual(placement.row, terminal.images(0).placement(0).?.row);
        try std.testing.expectEqual(placement.col, terminal.images(0).placement(0).?.col);
        try std.testing.expectEqual(image_generation, terminal.images(0).generation);
        try std.testing.expectEqual(content_generation, terminal.images(0).content_generation);
        try std.testing.expectEqualStrings("", terminal.replyBytes());

        // Both next valid commands must still execute, including the
        // DECOM vertical origin and the active bank's previous tab stops.
        try std.testing.expect((try terminal.feed(case.valid)).stateChanged());
        try std.testing.expectEqual(case.row, terminal.semanticView(0).cursor_row);
        try std.testing.expectEqual(case.col, terminal.semanticView(0).cursor_col);
    }

    // Both commands map explicit zero to one, unlike Kitty CSI S/T.
    // The final semicolon is legal but doubled/colon-separated operands
    // above must remain rejected.
    for ([_]struct { valid: []const u8, row: u16, col: u16 }{
        .{ .valid = "\x1b[d", .row = 1, .col = 18 },
        .{ .valid = "\x1b[0d", .row = 1, .col = 18 },
        .{ .valid = "\x1b[;d", .row = 1, .col = 18 },
        .{ .valid = "\x1b[3d", .row = 3, .col = 18 },
        .{ .valid = "\x1b[3;d", .row = 3, .col = 18 },
        .{ .valid = "\x9b4d", .row = 4, .col = 18 },
        .{ .valid = "\x1b[Z", .row = 2, .col = 16 },
        .{ .valid = "\x1b[0Z", .row = 2, .col = 16 },
        .{ .valid = "\x1b[;Z", .row = 2, .col = 16 },
        .{ .valid = "\x1b[2Z", .row = 2, .col = 8 },
        .{ .valid = "\x1b[2;Z", .row = 2, .col = 8 },
        .{ .valid = "\x9b1Z", .row = 2, .col = 16 },
    }) |case| {
        var terminal = try Terminal.init(std.testing.allocator, 6, 20);
        defer terminal.deinit();
        try feed(&terminal, "\x1b[2;5r\x1b[?6h\x1b[2;19H");
        try std.testing.expect((try terminal.feed(case.valid)).stateChanged());
        try std.testing.expectEqual(case.row, terminal.semanticView(0).cursor_row);
        try std.testing.expectEqual(case.col, terminal.semanticView(0).cursor_col);
    }

    // Rejected cursor controls must not consume pending wrap either. A
    // following printable still wraps, rather than overwriting the edge.
    for ([_][]const u8{
        "\x1b[3;2d", "\x1b[1;2Z", "\x9b3;2d", "\x9b1;2Z",
    }) |invalid| {
        var terminal = try Terminal.init(std.testing.allocator, 2, 20);
        defer terminal.deinit();
        try feed(&terminal, "\x1b[1;20H!");
        const sequence = terminal.semanticSequence();
        try std.testing.expect(!(try terminal.feed(invalid)).stateChanged());
        try std.testing.expectEqual(sequence, terminal.semanticSequence());
        try feed(&terminal, "X");
        try std.testing.expectEqual(@as(u21, '!'), terminal.semanticView(0).cellAt(0, 19));
        try std.testing.expectEqual(@as(u21, 'X'), terminal.semanticView(0).cellAt(1, 0));
    }
}

test "terminal: pinned Kitty DECSTBM rejects extra operands without changing margins" {
    // Pinned Kitty d4106ef vt-parser.c::dispatch_csi uses
    // CALL_CSI_HANDLER2 for DECSTBM. A third numeric operand must not
    // reach Screen.setScrollRegion or disturb DECOM's existing origin.
    const image = "\x1b_Ga=T,f=32,s=1,v=1,i=95,C=1;AQIDBA==\x1b\\";
    for ([_][]const u8{
        "\x1b[3;4;5r",
        "\x1b[3;4;0r",
        "\x1b[3;4;5;r",
        "\x9b3;4;5r",
        "\x1b[1;6;2r",
        "\x1b[2;5;4;3r",
    }) |invalid| {
        var terminal = try Terminal.initWithHistory(std.testing.allocator, 6, 8, 4);
        defer terminal.deinit();
        try terminal.setCellPixelSize(1, 1);
        try feed(&terminal, "\x1b[1;1HAAAAAAAA\x1b[2;1HBBBBBBBB\x1b[3;1HCCCCCCCC\x1b[4;1HDDDDDDDD\x1b[5;1HEEEEEEEE\x1b[6;1HFFFFFFFF");
        try feed(&terminal, "\x1b[3;2H" ++ image ++ "\x1b[2;5r\x1b[?6h\x1b[3;2H");
        try consumeReplies(&terminal);
        const before = terminal.semanticView(0);
        const cells = [_]@TypeOf(before.cellInfoAt(0, 0)){
            before.cellInfoAt(0, 0),
            before.cellInfoAt(1, 0),
            before.cellInfoAt(2, 0),
            before.cellInfoAt(3, 0),
            before.cellInfoAt(4, 0),
            before.cellInfoAt(5, 0),
        };
        const sequence = terminal.semanticSequence();
        const edit_generation = terminal.observation().structuralEditGeneration();
        const graphics = terminal.images(0);
        const placement = graphics.placement(0).?;
        const image_generation = graphics.generation;
        const content_generation = graphics.content_generation;
        try std.testing.expectEqual(@as(usize, 1), graphics.placementCount());

        try std.testing.expect(!(try terminal.feed(invalid[0 .. invalid.len - 1])).stateChanged());
        try std.testing.expect(!(try terminal.feed(invalid[invalid.len - 1 ..])).stateChanged());
        const after = terminal.semanticView(0);
        try std.testing.expectEqual(sequence, terminal.semanticSequence());
        try std.testing.expectEqual(before.history_count, after.history_count);
        try std.testing.expectEqual(edit_generation, terminal.observation().structuralEditGeneration());
        try std.testing.expectEqual(before.cursor_row, after.cursor_row);
        try std.testing.expectEqual(before.cursor_col, after.cursor_col);
        for (cells, 0..) |cell, row| try std.testing.expectEqualDeep(cell, after.cellInfoAt(@intCast(row), 0));
        try std.testing.expectEqual(@as(usize, 1), terminal.images(0).placementCount());
        try std.testing.expectEqual(placement.row, terminal.images(0).placement(0).?.row);
        try std.testing.expectEqual(placement.col, terminal.images(0).placement(0).?.col);
        try std.testing.expectEqual(image_generation, terminal.images(0).generation);
        try std.testing.expectEqual(content_generation, terminal.images(0).content_generation);
        try std.testing.expectEqualStrings("", terminal.replyBytes());

        // A subsequent origin-relative CUP must still use the previous
        // top margin, and a valid DECSTBM must remain accepted.
        try feed(&terminal, "\x1b[1;1H");
        try std.testing.expectEqual(@as(u16, 1), terminal.semanticView(0).cursor_row);
        try std.testing.expect((try terminal.feed("\x1b[3;6r")).stateChanged());
        try std.testing.expectEqual(@as(u16, 2), terminal.semanticView(0).cursor_row);
    }

    // Kitty commits only supplied digits, so a trailing empty delimiter
    // is not a third parameter. Zero and omitted margins remain legal.
    for ([_]struct { valid: []const u8, top: u16 }{
        .{ .valid = "\x1b[r", .top = 0 },
        .{ .valid = "\x1b[;r", .top = 0 },
        .{ .valid = "\x1b[0;0r", .top = 0 },
        .{ .valid = "\x1b[2r", .top = 1 },
        .{ .valid = "\x1b[2;r", .top = 1 },
        .{ .valid = "\x1b[2;5r", .top = 1 },
        .{ .valid = "\x1b[2;5;r", .top = 1 },
        .{ .valid = "\x9b2;5r", .top = 1 },
    }) |case| {
        var terminal = try Terminal.init(std.testing.allocator, 6, 8);
        defer terminal.deinit();
        try feed(&terminal, "\x1b[2;5r\x1b[?6h\x1b[3;3H");
        try std.testing.expect((try terminal.feed(case.valid)).stateChanged());
        try std.testing.expectEqual(case.top, terminal.semanticView(0).cursor_row);
        try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_col);
    }
}

test "terminal: pinned Kitty directional CSI rejects surplus counts without cursor or graphics mutation" {
    // Frozen Kitty vt-parser.c::dispatch_csi calls CALL_CSI_HANDLER1 for
    // A/B/C/D/E/F/G/` and refuses more than one supplied operand.
    // libvterm/iTerm2 instead act on the first; the catalogue owns their
    // conflicting same-wire policy. Retain normal zero-as-one behavior.
    const cases = [_]struct { final: u8, one_row: u16, one_col: u16, two_row: u16, two_col: u16 }{
        .{ .final = 'A', .one_row = 2, .one_col = 3, .two_row = 1, .two_col = 3 },
        .{ .final = 'B', .one_row = 4, .one_col = 3, .two_row = 5, .two_col = 3 },
        .{ .final = 'C', .one_row = 3, .one_col = 4, .two_row = 3, .two_col = 5 },
        .{ .final = 'D', .one_row = 3, .one_col = 2, .two_row = 3, .two_col = 1 },
        .{ .final = 'E', .one_row = 4, .one_col = 0, .two_row = 5, .two_col = 0 },
        .{ .final = 'F', .one_row = 2, .one_col = 0, .two_row = 1, .two_col = 0 },
        .{ .final = 'G', .one_row = 3, .one_col = 0, .two_row = 3, .two_col = 1 },
        .{ .final = '`', .one_row = 3, .one_col = 0, .two_row = 3, .two_col = 1 },
    };
    const image = "\x1b_Ga=T,f=32,s=1,v=1,i=92,C=1;AQIDBA==\x1b\\";
    const InvalidForm = enum { extra, extra_zero, colon, empty_middle, empty_first, c1, triple };
    const ValidForm = enum { missing, zero, zero_trailing, positive, positive_trailing, c1 };
    for (cases) |case| {
        for ([_]InvalidForm{ .extra, .extra_zero, .colon, .empty_middle, .empty_first, .c1, .triple }) |form| {
            var terminal = try Terminal.initWithHistory(std.testing.allocator, 6, 8, 4);
            defer terminal.deinit();
            try terminal.setCellPixelSize(1, 1);
            try feed(&terminal, "\x1b[1;1HAAAAAAAA\x1b[2;1HBBBBBBBB\x1b[3;1HCCCCCCCC\x1b[4;1HDDDDDDDD\x1b[5;1HEEEEEEEE\x1b[6;1HFFFFFFFF");
            try feed(&terminal, "\x1b[3;2H" ++ image ++ "\x1b[4;4H");
            try consumeReplies(&terminal);
            const before = terminal.semanticView(0);
            try std.testing.expectEqual(@as(u16, 3), before.cursor_row);
            try std.testing.expectEqual(@as(u16, 3), before.cursor_col);
            const cells = [_]@TypeOf(before.cellInfoAt(0, 0)){
                before.cellInfoAt(0, 0), before.cellInfoAt(1, 0), before.cellInfoAt(2, 0),
                before.cellInfoAt(3, 0), before.cellInfoAt(4, 0), before.cellInfoAt(5, 0),
            };
            const sequence = terminal.semanticSequence();
            const edit = terminal.observation().structuralEditGeneration();
            const images = terminal.images(0);
            try std.testing.expectEqual(@as(usize, 1), images.placementCount());
            const placement = images.placement(0).?;
            const image_count = images.imageCount();
            const image_generation = images.generation;
            const content_generation = images.content_generation;

            var buffer: [32]u8 = undefined;
            const invalid = switch (form) {
                .extra => try std.fmt.bufPrint(&buffer, "\x1b[1;9{c}", .{case.final}),
                .extra_zero => try std.fmt.bufPrint(&buffer, "\x1b[0;2{c}", .{case.final}),
                .colon => try std.fmt.bufPrint(&buffer, "\x1b[1:9{c}", .{case.final}),
                .empty_middle => try std.fmt.bufPrint(&buffer, "\x1b[1;;{c}", .{case.final}),
                .empty_first => try std.fmt.bufPrint(&buffer, "\x1b[;2{c}", .{case.final}),
                .c1 => try std.fmt.bufPrint(&buffer, "\x9b1;9{c}", .{case.final}),
                .triple => try std.fmt.bufPrint(&buffer, "\x1b[1;2;3{c}", .{case.final}),
            };
            try std.testing.expect(!(try terminal.feed(invalid[0 .. invalid.len - 1])).stateChanged());
            try std.testing.expect(!(try terminal.feed(invalid[invalid.len - 1 ..])).stateChanged());
            const after = terminal.semanticView(0);
            try std.testing.expectEqual(sequence, terminal.semanticSequence());
            try std.testing.expectEqual(before.cursor_row, after.cursor_row);
            try std.testing.expectEqual(before.cursor_col, after.cursor_col);
            try std.testing.expectEqual(before.history_count, after.history_count);
            try std.testing.expectEqual(edit, terminal.observation().structuralEditGeneration());
            for (cells, 0..) |cell, row| try std.testing.expectEqualDeep(cell, after.cellInfoAt(@intCast(row), 0));
            try std.testing.expectEqual(image_count, terminal.images(0).imageCount());
            try std.testing.expectEqual(@as(usize, 1), terminal.images(0).placementCount());
            try std.testing.expectEqual(placement.row, terminal.images(0).placement(0).?.row);
            try std.testing.expectEqual(placement.col, terminal.images(0).placement(0).?.col);
            try std.testing.expectEqual(image_generation, terminal.images(0).generation);
            try std.testing.expectEqual(content_generation, terminal.images(0).content_generation);
            try std.testing.expectEqualStrings("", terminal.replyBytes());

            const valid = try std.fmt.bufPrint(&buffer, "\x1b[2{c}", .{case.final});
            try std.testing.expect((try terminal.feed(valid)).stateChanged());
            try std.testing.expectEqual(case.two_row, terminal.semanticView(0).cursor_row);
            try std.testing.expectEqual(case.two_col, terminal.semanticView(0).cursor_col);
        }

        // Missing, explicit zero, legal final empty, positive and 8-bit
        // forms retain their existing one- or two-step semantics.
        for ([_]ValidForm{ .missing, .zero, .zero_trailing, .positive, .positive_trailing, .c1 }) |form| {
            var terminal = try Terminal.init(std.testing.allocator, 6, 8);
            defer terminal.deinit();
            try feed(&terminal, "\x1b[4;4H");
            var buffer: [32]u8 = undefined;
            const valid = switch (form) {
                .missing => try std.fmt.bufPrint(&buffer, "\x1b[{c}", .{case.final}),
                .zero => try std.fmt.bufPrint(&buffer, "\x1b[0{c}", .{case.final}),
                .zero_trailing => try std.fmt.bufPrint(&buffer, "\x1b[0;{c}", .{case.final}),
                .positive => try std.fmt.bufPrint(&buffer, "\x1b[2{c}", .{case.final}),
                .positive_trailing => try std.fmt.bufPrint(&buffer, "\x1b[2;{c}", .{case.final}),
                .c1 => try std.fmt.bufPrint(&buffer, "\x9b2{c}", .{case.final}),
            };
            try std.testing.expect((try terminal.feed(valid)).stateChanged());
            const two = form == .positive or form == .positive_trailing or form == .c1;
            try std.testing.expectEqual(if (two) case.two_row else case.one_row, terminal.semanticView(0).cursor_row);
            try std.testing.expectEqual(if (two) case.two_col else case.one_col, terminal.semanticView(0).cursor_col);
        }

        // A rejected command must not clear pending wrap. The next glyph
        // still advances past the last column instead of overwriting it.
        var terminal = try Terminal.init(std.testing.allocator, 2, 8);
        defer terminal.deinit();
        try feed(&terminal, "\x1b[1;8H!");
        const sequence = terminal.semanticSequence();
        var buffer: [32]u8 = undefined;
        const invalid = try std.fmt.bufPrint(&buffer, "\x1b[1;9{c}", .{case.final});
        try std.testing.expect(!(try terminal.feed(invalid)).stateChanged());
        try std.testing.expectEqual(sequence, terminal.semanticSequence());
        try feed(&terminal, "X");
        try std.testing.expectEqual(@as(u21, '!'), terminal.semanticView(0).cellAt(0, 7));
        try std.testing.expectEqual(@as(u21, 'X'), terminal.semanticView(0).cellAt(1, 0));
    }
}

test "terminal: pinned Kitty HPR VPR reject surplus operands without cursor or graphics mutation" {
    // Frozen Kitty d4106ef vt-parser.c:1199-1204 uses CALL_CSI_HANDLER1
    // for VPR (e) and HPR (a). Pinned libvterm/iTerm2 use the first count
    // despite extras. Keep Screen's independent margin/phantom semantics.
    const image = "\x1b_Ga=T,f=32,s=1,v=1,i=94,C=1;AQIDBA==\x1b\\";
    const Invalid = enum { extra, extra_zero, colon, empty_middle, empty_first, c1, triple };
    const Valid = enum { missing, zero, zero_trailing, positive, positive_trailing, c1 };
    for ([_]struct { final: u8, one_row: u16, one_col: u16, two_row: u16, two_col: u16 }{
        .{ .final = 'a', .one_row = 3, .one_col = 4, .two_row = 3, .two_col = 5 },
        .{ .final = 'e', .one_row = 4, .one_col = 3, .two_row = 5, .two_col = 3 },
    }) |case| {
        for ([_]Invalid{ .extra, .extra_zero, .colon, .empty_middle, .empty_first, .c1, .triple }) |form| {
            var terminal = try Terminal.initWithHistory(std.testing.allocator, 6, 8, 4);
            defer terminal.deinit();
            try terminal.setCellPixelSize(1, 1);
            try feed(&terminal, "\x1b[1;1HAAAAAAAA\x1b[2;1HBBBBBBBB\x1b[3;1HCCCCCCCC\x1b[4;1HDDDDDDDD\x1b[5;1HEEEEEEEE\x1b[6;1HFFFFFFFF");
            try feed(&terminal, "\x1b[3;2H" ++ image ++ "\x1b[4;4H");
            try consumeReplies(&terminal);
            const before = terminal.semanticView(0);
            try std.testing.expectEqual(@as(u16, 3), before.cursor_row);
            try std.testing.expectEqual(@as(u16, 3), before.cursor_col);
            const cells = [_]@TypeOf(before.cellInfoAt(0, 0)){
                before.cellInfoAt(0, 0), before.cellInfoAt(1, 0), before.cellInfoAt(2, 0),
                before.cellInfoAt(3, 0), before.cellInfoAt(4, 0), before.cellInfoAt(5, 0),
            };
            const sequence = terminal.semanticSequence();
            const edit = terminal.observation().structuralEditGeneration();
            const graphics = terminal.images(0);
            try std.testing.expectEqual(@as(usize, 1), graphics.placementCount());
            const placement = graphics.placement(0).?;
            const image_count = graphics.imageCount();
            const image_generation = graphics.generation;
            const content_generation = graphics.content_generation;

            var buffer: [32]u8 = undefined;
            const invalid = switch (form) {
                .extra => try std.fmt.bufPrint(&buffer, "\x1b[1;9{c}", .{case.final}),
                .extra_zero => try std.fmt.bufPrint(&buffer, "\x1b[0;2{c}", .{case.final}),
                .colon => try std.fmt.bufPrint(&buffer, "\x1b[1:9{c}", .{case.final}),
                .empty_middle => try std.fmt.bufPrint(&buffer, "\x1b[1;;{c}", .{case.final}),
                .empty_first => try std.fmt.bufPrint(&buffer, "\x1b[;2{c}", .{case.final}),
                .c1 => try std.fmt.bufPrint(&buffer, "\x9b1;9{c}", .{case.final}),
                .triple => try std.fmt.bufPrint(&buffer, "\x1b[1;2;3{c}", .{case.final}),
            };
            try std.testing.expect(!(try terminal.feed(invalid[0 .. invalid.len - 1])).stateChanged());
            try std.testing.expect(!(try terminal.feed(invalid[invalid.len - 1 ..])).stateChanged());
            const after = terminal.semanticView(0);
            try std.testing.expectEqual(sequence, terminal.semanticSequence());
            try std.testing.expectEqual(before.cursor_row, after.cursor_row);
            try std.testing.expectEqual(before.cursor_col, after.cursor_col);
            try std.testing.expectEqual(before.history_count, after.history_count);
            try std.testing.expectEqual(edit, terminal.observation().structuralEditGeneration());
            for (cells, 0..) |cell, row| try std.testing.expectEqualDeep(cell, after.cellInfoAt(@intCast(row), 0));
            try std.testing.expectEqual(image_count, terminal.images(0).imageCount());
            try std.testing.expectEqual(@as(usize, 1), terminal.images(0).placementCount());
            try std.testing.expectEqual(placement.row, terminal.images(0).placement(0).?.row);
            try std.testing.expectEqual(placement.col, terminal.images(0).placement(0).?.col);
            try std.testing.expectEqual(image_generation, terminal.images(0).generation);
            try std.testing.expectEqual(content_generation, terminal.images(0).content_generation);
            try std.testing.expectEqualStrings("", terminal.replyBytes());

            const valid = try std.fmt.bufPrint(&buffer, "\x1b[2{c}", .{case.final});
            try std.testing.expect((try terminal.feed(valid)).stateChanged());
            try std.testing.expectEqual(case.two_row, terminal.semanticView(0).cursor_row);
            try std.testing.expectEqual(case.two_col, terminal.semanticView(0).cursor_col);
        }

        for ([_]Valid{ .missing, .zero, .zero_trailing, .positive, .positive_trailing, .c1 }) |form| {
            var terminal = try Terminal.init(std.testing.allocator, 6, 8);
            defer terminal.deinit();
            try feed(&terminal, "\x1b[4;4H");
            var buffer: [32]u8 = undefined;
            const valid = switch (form) {
                .missing => try std.fmt.bufPrint(&buffer, "\x1b[{c}", .{case.final}),
                .zero => try std.fmt.bufPrint(&buffer, "\x1b[0{c}", .{case.final}),
                .zero_trailing => try std.fmt.bufPrint(&buffer, "\x1b[0;{c}", .{case.final}),
                .positive => try std.fmt.bufPrint(&buffer, "\x1b[2{c}", .{case.final}),
                .positive_trailing => try std.fmt.bufPrint(&buffer, "\x1b[2;{c}", .{case.final}),
                .c1 => try std.fmt.bufPrint(&buffer, "\x9b2{c}", .{case.final}),
            };
            try std.testing.expect((try terminal.feed(valid)).stateChanged());
            const two = form == .positive or form == .positive_trailing or form == .c1;
            try std.testing.expectEqual(if (two) case.two_row else case.one_row, terminal.semanticView(0).cursor_row);
            try std.testing.expectEqual(if (two) case.two_col else case.one_col, terminal.semanticView(0).cursor_col);
        }

        var terminal = try Terminal.init(std.testing.allocator, 2, 8);
        defer terminal.deinit();
        try feed(&terminal, "\x1b[1;8H!");
        const sequence = terminal.semanticSequence();
        var buffer: [32]u8 = undefined;
        const invalid = try std.fmt.bufPrint(&buffer, "\x1b[1;9{c}", .{case.final});
        try std.testing.expect(!(try terminal.feed(invalid)).stateChanged());
        try std.testing.expectEqual(sequence, terminal.semanticSequence());
        try feed(&terminal, "X");
        try std.testing.expectEqual(@as(u21, '!'), terminal.semanticView(0).cellAt(0, 7));
        try std.testing.expectEqual(@as(u21, 'X'), terminal.semanticView(0).cellAt(1, 0));
    }
}

test "terminal: pinned Kitty CUP HVP reject surplus operands without cursor or graphics mutation" {
    // Frozen Kitty vt-parser.c dispatches H/f through CALL_CSI_HANDLER2.
    // A third supplied operand rejects the complete command. The direct
    // hot path and generic CSI decoder must agree on that negative space.
    const image = "\x1b_Ga=T,f=32,s=1,v=1,i=99,C=1;AQIDBA==\x1b\\";
    for ([_][]const u8{
        "\x1b[3;4;5H",  "\x1b[3;4;5f",
        "\x1b[3;4;0H",  "\x1b[3;4;0f",
        "\x1b[3;4;;H",  "\x1b[3;4;;f",
        "\x1b[3:4:5H",  "\x1b[3:4:5f",
        "\x9b3;4;5H",   "\x9b3;4;5f",
        "\x1b[;4;5H",   "\x1b[;4;5f",
        "\x1b[3;4;5;H", "\x1b[3;4;5;f",
    }) |invalid| {
        var terminal = try Terminal.initWithHistory(std.testing.allocator, 6, 20, 4);
        defer terminal.deinit();
        try terminal.setCellPixelSize(1, 1);
        try feed(&terminal, "\x1b[1;1HAAAAAAAA\x1b[2;1HBBBBBBBB\x1b[3;1HCCCCCCCC\x1b[4;1HDDDDDDDD\x1b[5;1HEEEEEEEE\x1b[6;1HFFFFFFFF");
        try feed(&terminal, "\x1b[3;2H" ++ image ++ "\x1b[2;5r\x1b[?6h\x1b[2;19H");
        try consumeReplies(&terminal);
        const before = terminal.semanticView(0);
        try std.testing.expectEqual(@as(u16, 2), before.cursor_row);
        try std.testing.expectEqual(@as(u16, 18), before.cursor_col);
        const cells = [_]@TypeOf(before.cellInfoAt(0, 0)){
            before.cellInfoAt(0, 0), before.cellInfoAt(1, 0), before.cellInfoAt(2, 0),
            before.cellInfoAt(3, 0), before.cellInfoAt(4, 0), before.cellInfoAt(5, 0),
        };
        const seq = terminal.semanticSequence();
        const edit_generation = terminal.observation().structuralEditGeneration();
        const images = terminal.images(0);
        try std.testing.expectEqual(@as(usize, 1), images.placementCount());
        const placement = images.placement(0).?;
        const image_count = images.imageCount();
        const image_generation = images.generation;
        const content_generation = images.content_generation;

        try std.testing.expect(!(try terminal.feed(invalid[0 .. invalid.len - 1])).stateChanged());
        try std.testing.expect(!(try terminal.feed(invalid[invalid.len - 1 ..])).stateChanged());
        const after = terminal.semanticView(0);
        try std.testing.expectEqual(seq, terminal.semanticSequence());
        try std.testing.expectEqual(before.cursor_row, after.cursor_row);
        try std.testing.expectEqual(before.cursor_col, after.cursor_col);
        try std.testing.expectEqual(before.history_count, after.history_count);
        try std.testing.expectEqual(edit_generation, terminal.observation().structuralEditGeneration());
        for (cells, 0..) |cell, row| try std.testing.expectEqualDeep(cell, after.cellInfoAt(@intCast(row), 0));
        try std.testing.expectEqual(image_count, terminal.images(0).imageCount());
        try std.testing.expectEqual(@as(usize, 1), terminal.images(0).placementCount());
        try std.testing.expectEqual(placement.row, terminal.images(0).placement(0).?.row);
        try std.testing.expectEqual(placement.col, terminal.images(0).placement(0).?.col);
        try std.testing.expectEqual(image_generation, terminal.images(0).generation);
        try std.testing.expectEqual(content_generation, terminal.images(0).content_generation);
        try std.testing.expectEqualStrings("", terminal.replyBytes());

        // Origin mode and both normal coordinates remain usable afterward.
        try std.testing.expect((try terminal.feed("\x1b[3;4H")).stateChanged());
        try std.testing.expectEqual(@as(u16, 3), terminal.semanticView(0).cursor_row);
        try std.testing.expectEqual(@as(u16, 3), terminal.semanticView(0).cursor_col);
    }

    // Omitted/zero/one/two values and final empty delimiters remain legal;
    // a final ';' is not an extra committed parameter in pinned Kitty.
    for ([_]struct { valid: []const u8, row: u16, col: u16 }{
        .{ .valid = "\x1b[H", .row = 1, .col = 0 },
        .{ .valid = "\x1b[f", .row = 1, .col = 0 },
        .{ .valid = "\x1b[0;0H", .row = 1, .col = 0 },
        .{ .valid = "\x1b[0;0f", .row = 1, .col = 0 },
        .{ .valid = "\x1b[;H", .row = 1, .col = 0 },
        .{ .valid = "\x1b[;f", .row = 1, .col = 0 },
        .{ .valid = "\x1b[3;4H", .row = 3, .col = 3 },
        .{ .valid = "\x1b[3;4f", .row = 3, .col = 3 },
        .{ .valid = "\x1b[3;4;H", .row = 3, .col = 3 },
        .{ .valid = "\x1b[3;4;f", .row = 3, .col = 3 },
        .{ .valid = "\x9b2;5H", .row = 2, .col = 4 },
        .{ .valid = "\x9b2;5f", .row = 2, .col = 4 },
    }) |case| {
        var terminal = try Terminal.init(std.testing.allocator, 6, 20);
        defer terminal.deinit();
        try feed(&terminal, "\x1b[2;5r\x1b[?6h\x1b[2;19H");
        try std.testing.expect((try terminal.feed(case.valid)).stateChanged());
        try std.testing.expectEqual(case.row, terminal.semanticView(0).cursor_row);
        try std.testing.expectEqual(case.col, terminal.semanticView(0).cursor_col);
    }

    // Rejecting a cursor-position command cannot cancel last-column wrap.
    for ([_][]const u8{
        "\x1b[3;4;5H", "\x1b[3;4;5f", "\x9b3;4;5H", "\x9b3;4;5f",
    }) |invalid| {
        var terminal = try Terminal.init(std.testing.allocator, 2, 20);
        defer terminal.deinit();
        try feed(&terminal, "\x1b[1;20H!");
        const seq = terminal.semanticSequence();
        try std.testing.expect(!(try terminal.feed(invalid)).stateChanged());
        try std.testing.expectEqual(seq, terminal.semanticSequence());
        try feed(&terminal, "X");
        try std.testing.expectEqual(@as(u21, '!'), terminal.semanticView(0).cellAt(0, 19));
        try std.testing.expectEqual(@as(u21, 'X'), terminal.semanticView(0).cellAt(1, 0));
    }
}

test "terminal: directional cursor margins use target-side clipping from outside region" {
    const cases = [_]struct {
        command: []const u8,
        initial: []const u8,
        row: u16,
        col: u16,
    }{
        .{ .command = "\x1b[99A", .initial = "\x1b[8;3H", .row = 2, .col = 2 },
        .{ .command = "\x1b[99F", .initial = "\x1b[8;3H", .row = 2, .col = 0 },
        .{ .command = "\x1b[99B", .initial = "\x1b[1;3H", .row = 4, .col = 2 },
        .{ .command = "\x1b[99E", .initial = "\x1b[1;3H", .row = 4, .col = 0 },
    };
    for (cases) |case| {
        var terminal = try Terminal.init(std.testing.allocator, 8, 8);
        defer terminal.deinit();
        try feed(&terminal, "\x1b[3;5r");
        try feed(&terminal, case.initial);
        try std.testing.expect((try terminal.feed(case.command)).stateChanged());
        const view = terminal.semanticView(0);
        try std.testing.expectEqual(case.row, view.cursor_row);
        try std.testing.expectEqual(case.col, view.cursor_col);
    }
}

test "terminal: exact-fill cursor movement resolves canonical pending wrap" {
    // Pinned Kitty stores an internal one-past-right column after exact fill.
    // Howl instead stores last-column plus pending wrap; its CSI D, G and `
    // cancel that pending wrap before moving, not after phantom arithmetic.
    for ([_]struct { command: []const u8, expected: []const u8, column: u16 }{
        .{ .command = "\x1b[D", .expected = "abcXe", .column = 4 },
        .{ .command = "\x1b[6G", .expected = "abcdX", .column = 4 },
        .{ .command = "\x1b[6`", .expected = "abcdX", .column = 4 },
    }) |case| {
        var terminal = try Terminal.init(std.testing.allocator, 3, 5);
        defer terminal.deinit();
        try feed(&terminal, "abcde");
        try std.testing.expectEqual(@as(u16, 4), terminal.semanticView(0).cursor_col);
        try std.testing.expect((try terminal.feed(case.command)).stateChanged());
        try feed(&terminal, "X");
        const view = terminal.semanticView(0);
        try std.testing.expectEqual(@as(u16, 0), view.cursor_row);
        try std.testing.expectEqual(case.column, view.cursor_col);
        for (case.expected, 0..) |letter, col|
            try std.testing.expectEqual(@as(u21, letter), view.cellAt(0, @intCast(col)));
        try std.testing.expectEqual(@as(u21, 0), view.cellAt(1, 0));
    }
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

test "terminal: libvterm origin-only motion bounds differ from Howl directional margins" {
    // Pinned libvterm state.c::on_csi 0x41..0x46 clamps cursor movement
    // against scroll margins only when mode.origin is set. Howl retains its
    // deliberate iTerm2-style directional margin bounds with DECOM unset.
    // Both references accept the same input bytes but have different output.
    const cases = [_]struct {
        start: []const u8,
        move: []const u8,
        row: u16,
        col: u16,
        pinned_libvterm_row: u16,
        pinned_libvterm_col: u16,
    }{
        .{ .start = "\x1b[4;6H", .move = "\x1b[99A", .row = 1, .col = 5, .pinned_libvterm_row = 0, .pinned_libvterm_col = 5 },
        .{ .start = "\x1b[3;6H", .move = "\x1b[99B", .row = 4, .col = 5, .pinned_libvterm_row = 5, .pinned_libvterm_col = 5 },
        .{ .start = "\x1b[3;6H", .move = "\x1b[99C", .row = 2, .col = 8, .pinned_libvterm_row = 2, .pinned_libvterm_col = 11 },
        .{ .start = "\x1b[3;6H", .move = "\x1b[99D", .row = 2, .col = 3, .pinned_libvterm_row = 2, .pinned_libvterm_col = 0 },
        .{ .start = "\x1b[3;6H", .move = "\x1b[99E", .row = 4, .col = 3, .pinned_libvterm_row = 5, .pinned_libvterm_col = 0 },
        .{ .start = "\x1b[4;6H", .move = "\x1b[99F", .row = 1, .col = 3, .pinned_libvterm_row = 0, .pinned_libvterm_col = 0 },
    };
    for (cases) |case| {
        var terminal = try Terminal.init(std.testing.allocator, 6, 12);
        defer terminal.deinit();
        try feed(&terminal, "\x1b[2;5r\x1b[?69h\x1b[4;9s");
        try feed(&terminal, case.start);
        try std.testing.expect((try terminal.feed(case.move)).stateChanged());
        const view = terminal.semanticView(0);
        try std.testing.expectEqual(case.row, view.cursor_row);
        try std.testing.expectEqual(case.col, view.cursor_col);
        try std.testing.expect(case.row != case.pinned_libvterm_row or
            case.col != case.pinned_libvterm_col);
        try std.testing.expectEqualStrings("", terminal.replyBytes());
    }

    // Under DEC origin mode the two choices agree on the admitted margin
    // bounds; the difference is the origin-independent directional policy.
    var origin = try Terminal.init(std.testing.allocator, 6, 12);
    defer origin.deinit();
    try feed(&origin, "\x1b[2;5r\x1b[?69h\x1b[4;9s\x1b[?6h\x1b[2;3H");
    try feed(&origin, "\x1b[99A\x1b[99D");
    try std.testing.expectEqual(@as(u16, 1), origin.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 3), origin.semanticView(0).cursor_col);
    try feed(&origin, "\x1b[99B\x1b[99C");
    try std.testing.expectEqual(@as(u16, 4), origin.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 8), origin.semanticView(0).cursor_col);
}

test "terminal: pinned iTerm2 DECSACE requires VT400 while Howl always admits extent" {
    // Pinned iTerm2 VT100Terminal.m executes VT100CSI_DECSACE only with
    // _vtLevel >= iTermEmulationLevel400; lower emulations ignore it.
    // Howl processStar directly owns rectangle extent without an
    // emulation-level option. Valid changes remain exact/idempotent.
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    const start = terminal.semanticSequence();
    try std.testing.expect(!(try terminal.feed("\x1b[2*")).stateChanged());
    try std.testing.expect((try terminal.feed("x")).stateChanged());
    try std.testing.expectEqual(start + 1, terminal.semanticSequence());
    try std.testing.expect(!(try terminal.feed("\x1b[2*x")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[3*x")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[1*x")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[0*x")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[2*x")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1bc")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[2*x")).stateChanged());
    try std.testing.expectEqualStrings("", terminal.replyBytes());
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

test "terminal: DECFRA replaces only graphics in the accepted origin rectangle" {
    var terminal = try Terminal.init(std.testing.allocator, 4, 8);
    defer terminal.deinit();
    try terminal.setCellPixelSize(1, 1);

    // The admitted image at the target cell must disappear even when the
    // replacement glyph is already identical, without retiring other images.
    const image = "\x1b_Ga=T,f=32,s=1,v=1,C=1;AQIDBA==\x1b\\";
    try feed(&terminal, "\x1b[1;1HO\x1b[1;1H" ++ image ++ "\x1b[2;3HX\x1b[2;3H" ++ image);
    try consumeReplies(&terminal);
    try std.testing.expectEqual(@as(usize, 2), terminal.images(0).placementCount());
    try std.testing.expectEqual(@as(usize, 2), terminal.images(0).imageCount());
    try std.testing.expectEqual(@as(u16, 0), terminal.images(0).placement(0).?.row);
    try std.testing.expectEqual(@as(u16, 0), terminal.images(0).placement(0).?.col);
    try std.testing.expectEqual(@as(u16, 1), terminal.images(0).placement(1).?.row);
    try std.testing.expectEqual(@as(u16, 2), terminal.images(0).placement(1).?.col);
    const original_content_generation = terminal.images(0).content_generation;

    // DECOM and DECSLRM make 1,1 address the target at physical row 2,
    // column 3. An inverted rectangle or invalid fill character is inert.
    try feed(&terminal, "\x1b[2;3r\x1b[?69h\x1b[3;6s\x1b[?6h");
    const initial_sequence = terminal.semanticSequence();
    try std.testing.expect(!(try terminal.feed("\x1b[88;3;3;2;2$x\x1b[31;1;1;1;1$x")).stateChanged());
    try std.testing.expectEqual(initial_sequence, terminal.semanticSequence());
    try std.testing.expectEqual(@as(usize, 2), terminal.images(0).placementCount());
    try std.testing.expectEqual(original_content_generation, terminal.images(0).content_generation);

    // Fragmented parser completion must revoke only the overwritten placement.
    try std.testing.expect(!(try terminal.feed("\x1b[88;1;1;")).stateChanged());
    try std.testing.expect((try terminal.feed("1;1$x")).stateChanged());
    try std.testing.expectEqual(@as(u21, 'X'), terminal.semanticView(0).cellAt(1, 2));
    try std.testing.expectEqual(@as(u21, 'O'), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(usize, 1), terminal.images(0).placementCount());
    try std.testing.expectEqual(@as(u16, 0), terminal.images(0).placement(0).?.row);
    try std.testing.expectEqual(@as(u16, 0), terminal.images(0).placement(0).?.col);
    try std.testing.expectEqual(@as(usize, 2), terminal.images(0).imageCount());
    try std.testing.expectEqual(original_content_generation, terminal.images(0).content_generation);
    try std.testing.expectEqual(@as(u8, 0), terminal.consequenceCount());
}

test "terminal: DEC origin rectangle erasure moves graphics with the accepted Screen rectangle" {
    for ([_][]const u8{ "\x1b[1;1;1;1$z", "\x1b[1;1;1;1$\x7b" }) |erase| {
        var terminal = try Terminal.init(std.testing.allocator, 4, 8);
        defer terminal.deinit();
        try terminal.setCellPixelSize(1, 1);

        // Two independent image placements: one at the absolute origin,
        // and one at the first cell of the eventual origin-mode rectangle.
        const image = "\x1b_Ga=T,f=32,s=1,v=1,C=1;AQIDBA==\x1b\\";
        try feed(&terminal, "\x1b[1;1HO\x1b[1;1H" ++ image ++ "\x1b[2;3HX\x1b[2;3H" ++ image);
        try consumeReplies(&terminal);
        try std.testing.expectEqual(@as(usize, 2), terminal.images(0).placementCount());
        try std.testing.expectEqual(@as(u16, 0), terminal.images(0).placement(0).?.row);
        try std.testing.expectEqual(@as(u16, 0), terminal.images(0).placement(0).?.col);
        try std.testing.expectEqual(@as(u16, 1), terminal.images(0).placement(1).?.row);
        try std.testing.expectEqual(@as(u16, 2), terminal.images(0).placement(1).?.col);
        const content_generation = terminal.images(0).content_generation;

        // A 1x1 rectangle is relative to DEC origin and both active margins:
        // first row 2, first column 3, not the physical (1,1) position.
        try feed(&terminal, "\x1b[2;3r\x1b[?69h\x1b[3;6s\x1b[?6h");
        const stable = terminal.semanticSequence();
        try std.testing.expect(!(try terminal.feed("\x1b[3;3;2;2$z")).stateChanged());
        try std.testing.expectEqual(stable, terminal.semanticSequence());
        try std.testing.expectEqual(@as(usize, 2), terminal.images(0).placementCount());
        const split = erase.len - 2;
        try std.testing.expect(!(try terminal.feed(erase[0..split])).stateChanged());
        try std.testing.expect((try terminal.feed(erase[split..])).stateChanged());
        try std.testing.expectEqual(@as(u21, 'O'), terminal.semanticView(0).cellAt(0, 0));
        try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(1, 2));
        try std.testing.expectEqual(@as(usize, 1), terminal.images(0).placementCount());
        const remaining = terminal.images(0).placement(0).?;
        try std.testing.expectEqual(@as(u16, 0), remaining.row);
        try std.testing.expectEqual(@as(u16, 0), remaining.col);
        try std.testing.expectEqual(@as(usize, 2), terminal.images(0).imageCount());
        try std.testing.expectEqual(content_generation, terminal.images(0).content_generation);
    }
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

test "terminal: unknown SGR color type retains following recognized attributes" {
    const Property = enum { bold, dim, italic, underline, blink, reverse };
    const Case = struct { suffix: []const u8, property: Property };
    const cases = [_]Case{
        .{ .suffix = "1mA", .property = .bold },
        .{ .suffix = "2mA", .property = .dim },
        .{ .suffix = "3mA", .property = .italic },
        .{ .suffix = "4mA", .property = .underline },
        .{ .suffix = "5mA", .property = .blink },
        .{ .suffix = "7mA", .property = .reverse },
    };
    for (cases) |case| {
        var terminal = try Terminal.init(std.testing.allocator, 1, 4);
        defer terminal.deinit();
        try std.testing.expect(!(try terminal.feed("\x1b[38;")).stateChanged());
        try std.testing.expect(!(try terminal.feed("9;")).stateChanged());
        try std.testing.expect((try terminal.feed(case.suffix)).stateChanged());
        const attrs = terminal.semanticView(0).cellInfoAt(0, 0).attrs;
        try std.testing.expect(switch (case.property) {
            .bold => attrs.bold,
            .dim => attrs.dim,
            .italic => attrs.italic,
            .underline => attrs.underline,
            .blink => attrs.blink,
            .reverse => attrs.reverse,
        });
        try std.testing.expectEqual(Terminal.default_cell_attrs.fg, attrs.fg);
    }

    // Unlike pinned Kitty, invalid colour does not undo completed groups.
    // Like pinned libvterm, Howl also continues with the trailing group.
    var terminal = try Terminal.init(std.testing.allocator, 1, 4);
    defer terminal.deinit();
    try feed(&terminal, "\x1b[31;1;38;9;3mA");
    const attrs = terminal.semanticView(0).cellInfoAt(0, 0).attrs;
    try std.testing.expect(attrs.bold);
    try std.testing.expect(attrs.italic);
    try std.testing.expectEqual(Terminal.Color.indexed(1), attrs.fg);
}

test "terminal: out of range Kitty underline style is ignored by Howl" {
    var terminal = try Terminal.init(std.testing.allocator, 1, 6);
    defer terminal.deinit();

    // Pinned Kitty saturates style 6 to 5; Howl retains its chosen style.
    try feed(&terminal, "\x1b[4:6mA\x1b[4:5mB\x1b[4:6mC\x1b[4:0mD");
    const view = terminal.semanticView(0);
    try std.testing.expect(!view.cellInfoAt(0, 0).attrs.underline);
    try std.testing.expect(view.cellInfoAt(0, 1).attrs.underline);
    try std.testing.expectEqual(Terminal.UnderlineStyle.dashed, view.cellInfoAt(0, 1).attrs.underline_style);
    try std.testing.expectEqual(Terminal.UnderlineStyle.dashed, view.cellInfoAt(0, 2).attrs.underline_style);
    try std.testing.expect(!view.cellInfoAt(0, 3).attrs.underline);
}

test "terminal: pinned libvterm and iTerm2 unsupported underline styles differ from Howl" {
    // Pinned libvterm pen.c sets single underline before parsing any
    // colon substyle, and only recognizes styles 0..3. For 4:4, Howl
    // instead understands dotted underline. The valid 4:3 agrees.
    var vterm = try Terminal.init(std.testing.allocator, 1, 8);
    defer vterm.deinit();
    try feed(&vterm, "\x1b[4:4mA\x1b[4:3mB");
    const dotted = vterm.semanticView(0).cellInfoAt(0, 0).attrs;
    const curly = vterm.semanticView(0).cellInfoAt(0, 1).attrs;
    try std.testing.expect(dotted.underline);
    try std.testing.expectEqual(Terminal.UnderlineStyle.dotted, dotted.underline_style);
    try std.testing.expect(curly.underline);
    try std.testing.expectEqual(Terminal.UnderlineStyle.curly, curly.underline_style);

    // Pinned iTerm2 VT100GraphicRendition.m sets underline=YES first,
    // even when it sees an unknown substyle. Howl's out-of-range 4:6
    // deliberately leaves a previously disabled underline disabled.
    var iterm = try Terminal.init(std.testing.allocator, 1, 8);
    defer iterm.deinit();
    try feed(&iterm, "\x1b[4:0m\x1b[4:");
    try std.testing.expect((try iterm.feed("6mA\x1b[4:5mB\x1b[4:6mC")).stateChanged());
    const view = iterm.semanticView(0);
    try std.testing.expect(!view.cellInfoAt(0, 0).attrs.underline);
    try std.testing.expect(view.cellInfoAt(0, 1).attrs.underline);
    try std.testing.expectEqual(Terminal.UnderlineStyle.dashed, view.cellInfoAt(0, 1).attrs.underline_style);
    try std.testing.expect(view.cellInfoAt(0, 2).attrs.underline);
    try std.testing.expectEqual(Terminal.UnderlineStyle.dashed, view.cellInfoAt(0, 2).attrs.underline_style);
}

test "terminal: optional libvterm bold-highbright policy differs from native indexed SGR" {
    // Pinned libvterm pen.c supports state->bold_is_highbright=1, which
    // maps a basic indexed foreground to index+8 on either SGR ordering.
    // Howl has no analogous mode and retains indexed 1 plus bold flag.
    for ([_][]const u8{ "\x1b[31;1mA", "\x1b[1;31mA" }) |sequence| {
        var terminal = try Terminal.init(std.testing.allocator, 1, 8);
        defer terminal.deinit();
        try feed(&terminal, sequence);
        const attr = terminal.semanticView(0).cellInfoAt(0, 0).attrs;
        try std.testing.expect(attr.bold);
        try std.testing.expectEqual(Terminal.Color.indexed(1), attr.fg);
        // Explicit bright SGR remains fully supported as a distinct
        // command even though opt-in bold-bright remapping is not.
        try feed(&terminal, "\x1b[91mB");
        const bright = terminal.semanticView(0).cellInfoAt(0, 1).attrs;
        try std.testing.expect(bright.bold);
        try std.testing.expectEqual(Terminal.Color.indexed(9), bright.fg);
    }
}

test "terminal: pinned libvterm extended color wraps while Howl clamps overrange channels" {
    // Frozen libvterm pen.c passes CSI values without clipping into
    // vterm_color_indexed and vterm_color_rgb, whose uint8_t parameters
    // wrap modulo 256. Howl intentionally saturates to 255 instead.
    var terminal = try Terminal.init(std.testing.allocator, 1, 8);
    defer terminal.deinit();
    try std.testing.expect(!(try terminal.feed("\x1b[38;5;2")).stateChanged());
    try feed(&terminal, "56;48;2;256;257;258mA");
    const overrange = terminal.semanticView(0).cellInfoAt(0, 0).attrs;
    try std.testing.expectEqual(Terminal.Color.indexed(255), overrange.fg);
    try std.testing.expectEqual(Terminal.Color.rgbComponents(255, 255, 255), overrange.bg);
    // Both references agree on in-range channels; the exceptional result
    // is about parser policy, not a missing ordinary color capability.
    try feed(&terminal, "\x1b[38;5;255;48;2;0;1;2mB");
    const in_range = terminal.semanticView(0).cellInfoAt(0, 1).attrs;
    try std.testing.expectEqual(Terminal.Color.indexed(255), in_range.fg);
    try std.testing.expectEqual(Terminal.Color.rgbComponents(0, 1, 2), in_range.bg);
    try std.testing.expectEqualStrings("", terminal.replyBytes());
}

test "terminal: pinned iTerm2 dual-mode colors are explicit unsupported SGR submodes" {
    // Pinned iTerm2 VT100GraphicRendition.m accepts colon mode 12 for
    // light/dark RGB and 13 for light/dark indexed colors. Each fg, bg,
    // and underline-color action uses the shared color-value parser.
    // Howl's native one-color slots accept only color modes 2 and 5.
    var terminal = try Terminal.init(std.testing.allocator, 1, 8);
    defer terminal.deinit();
    try std.testing.expect(!(try terminal.feed("\x1b[38:12:10:20:")).stateChanged());
    try feed(&terminal, "30:200:210:220;48:13:42:90;58:12:1:2:3:4:5:6mA");
    const unsupported = terminal.semanticView(0).cellInfoAt(0, 0).attrs;
    try std.testing.expectEqual(Terminal.default_cell_attrs.fg, unsupported.fg);
    try std.testing.expectEqual(Terminal.default_cell_attrs.bg, unsupported.bg);
    try std.testing.expectEqual(Terminal.default_cell_attrs.underline_color, unsupported.underline_color);
    try std.testing.expect(!unsupported.bold);
    try std.testing.expect(!unsupported.reverse);

    // A second unrecognized dual indexed foreground cannot leak its
    // subparameters into normal SGR groups or mutate a previous color.
    try std.testing.expect(!(try terminal.feed("\x1b[38:13:42:90m")).stateChanged());
    try feed(&terminal, "B");
    try std.testing.expectEqual(Terminal.default_cell_attrs.fg, terminal.semanticView(0).cellInfoAt(0, 1).attrs.fg);

    try feed(&terminal, "\x1b[38:2::10:20:30;48:5:42;58:2::40:50:60mC");
    const supported = terminal.semanticView(0).cellInfoAt(0, 2).attrs;
    try std.testing.expectEqual(Terminal.Color.rgbComponents(10, 20, 30), supported.fg);
    try std.testing.expectEqual(Terminal.Color.indexed(42), supported.bg);
    try std.testing.expectEqual(Terminal.Color.rgbComponents(40, 50, 60), supported.underline_color);
    try std.testing.expectEqualStrings("", terminal.replyBytes());
}

test "pinned iTerm2 basic SGR colors retain prior unsupported dark variant metadata" {
    // Pinned iTerm2 VT100GraphicRendition.m applies basic FG and BG in
    // its default branch without clearing hasDualModeFg/hasDualModeBg.
    // After an accepted 38:12/48:13, a basic color still carries the
    // retained dark variant in external attributes. Howl has no dual-
    // mode attributes, so subsequent basic colors remain single-valued.
    var terminal = try Terminal.init(std.testing.allocator, 1, 5);
    defer terminal.deinit();
    try std.testing.expect(!(try terminal.feed("\x1b[38:12:10:20:30:200:210:220m")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[48:13:1:2m")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[31;44mA")).stateChanged());
    const basic = terminal.semanticView(0).cellInfoAt(0, 0).attrs;
    try std.testing.expectEqual(Terminal.Color.indexed(1), basic.fg);
    try std.testing.expectEqual(Terminal.Color.indexed(4), basic.bg);
    try std.testing.expect((try terminal.feed("\x1b[90;107mB")).stateChanged());
    const bright = terminal.semanticView(0).cellInfoAt(0, 1).attrs;
    try std.testing.expectEqual(Terminal.Color.indexed(8), bright.fg);
    try std.testing.expectEqual(Terminal.Color.indexed(15), bright.bg);
    try std.testing.expect((try terminal.feed("\x1b[39;49mC")).stateChanged());
    const reset = terminal.semanticView(0).cellInfoAt(0, 2).attrs;
    try std.testing.expectEqual(Terminal.default_cell_attrs.fg, reset.fg);
    try std.testing.expectEqual(Terminal.default_cell_attrs.bg, reset.bg);
    try std.testing.expectEqualStrings("", terminal.replyBytes());
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

test "terminal: pinned libvterm small font attribute is absent from native baseline SGR" {
    // Pinned libvterm src/pen.c:vterm_state_setpen(73/74/75) sets
    // both VTERM_ATTR_SMALL and VTERM_ATTR_BASELINE independently.
    // Howl retains the baseline value, but CellAttrs has no SMALL
    // semantic or small-font raster control for this SGR family.
    try std.testing.expect(!@hasField(Terminal.CellAttrs, "small"));
    var terminal = try Terminal.init(std.testing.allocator, 1, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("\x1b[73mA\x1b[74mB\x1b[75mC")).stateChanged());
    const view = terminal.semanticView(0);
    for ([_]struct { col: u16, baseline: Terminal.Baseline, letter: u21 }{
        .{ .col = 0, .baseline = .raised, .letter = 'A' },
        .{ .col = 1, .baseline = .lowered, .letter = 'B' },
        .{ .col = 2, .baseline = .normal, .letter = 'C' },
    }) |case| {
        const cell = view.cellInfoAt(0, case.col);
        try std.testing.expectEqual(case.letter, cell.codepoint);
        try std.testing.expectEqual(case.baseline, cell.attrs.baseline);
        try std.testing.expectEqual(@as(u8, 1), cell.width);
        try std.testing.expectEqual(@as(u8, 1), cell.height);
        try std.testing.expectEqual(@as(u4, 0), cell.subscale_n);
        try std.testing.expectEqual(@as(u4, 0), cell.subscale_d);
    }
    try std.testing.expectEqualStrings("", terminal.replyBytes());
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

test "terminal: pinned iTerm2 CSI S accepts extras but Howl keeps Kitty arity" {
    // iTerm2 1d6e758 VT100CSIParser.m case S unconditionally accepts
    // XTERMCC_SU and VT100Terminal.m consumes only p[0]. Pinned Kitty's
    // CALL_CSI_HANDLER1 rejects extras; Howl uses that same safe boundary.
    var terminal = try Terminal.init(std.testing.allocator, 3, 6);
    defer terminal.deinit();
    try feed(&terminal, "\x1b[1;1HAAAAAA\x1b[2;1HBBBBBB\x1b[3;1HCCCCCC\x1b[2;3r");
    const before = terminal.semanticView(0);
    const sequence = terminal.semanticSequence();
    try std.testing.expect(!(try terminal.feed("\x1b[1;2")).stateChanged());
    try std.testing.expect(!(try terminal.feed("S")).stateChanged());
    const after = terminal.semanticView(0);
    try std.testing.expectEqual(sequence, terminal.semanticSequence());
    for (0..3) |row| {
        try std.testing.expectEqualDeep(before.cellInfoAt(@intCast(row), 0), after.cellInfoAt(@intCast(row), 0));
    }
    try std.testing.expectEqual(before.cursor_row, after.cursor_row);
    try std.testing.expectEqual(before.cursor_col, after.cursor_col);
    try std.testing.expectEqualStrings("", terminal.replyBytes());

    // The common one-operand request remains valid after rejection.
    try std.testing.expect((try terminal.feed("\x1b[S")).stateChanged());
    try std.testing.expectEqual(@as(u21, 'C'), terminal.semanticView(0).cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(2, 0));
}

test "terminal: pinned iTerm2 CSI T extra-operand rejection now matches Howl" {
    // Pinned iTerm2 1d6e758 sources/VT100/VT100CSIParser.m accepts
    // XTERMCC_SD only with fewer than two operands. Howl now agrees:
    // malformed extra parameters cannot induce an accidental scroll.
    for ([_][]const u8{ "\x1b[T", "\x1b[1T" }) |command| {
        var terminal = try Terminal.init(std.testing.allocator, 3, 6);
        defer terminal.deinit();
        try feed(&terminal, "\x1b[1;1HAAAAAA\x1b[2;1HBBBBBB\x1b[3;1HCCCCCC\x1b[2;3r");
        const split = command.len - 1;
        try std.testing.expect(!(try terminal.feed(command[0..split])).stateChanged());
        try std.testing.expect((try terminal.feed(command[split..])).stateChanged());
        const view = terminal.semanticView(0);
        try std.testing.expectEqual(@as(u21, 'A'), view.cellAt(0, 0));
        try std.testing.expectEqual(@as(u21, 0), view.cellAt(1, 0));
        try std.testing.expectEqual(@as(u21, 'B'), view.cellAt(2, 0));
        try std.testing.expectEqualStrings("", terminal.replyBytes());
    }

    for ([_][]const u8{ "\x1b[1;2T", "\x1b[2;1T", "\x1b[1;2;3T" }) |invalid| {
        var terminal = try Terminal.init(std.testing.allocator, 3, 6);
        defer terminal.deinit();
        try feed(&terminal, "\x1b[1;1HAAAAAA\x1b[2;1HBBBBBB\x1b[3;1HCCCCCC\x1b[2;3r");
        const before = terminal.semanticView(0);
        const sequence = terminal.semanticSequence();
        try std.testing.expect(!(try terminal.feed(invalid[0 .. invalid.len - 1])).stateChanged());
        try std.testing.expect(!(try terminal.feed(invalid[invalid.len - 1 ..])).stateChanged());
        const after = terminal.semanticView(0);
        try std.testing.expectEqual(sequence, terminal.semanticSequence());
        try std.testing.expectEqual(before.cursor_row, after.cursor_row);
        try std.testing.expectEqual(before.cursor_col, after.cursor_col);
        for (0..3) |row| {
            try std.testing.expectEqualDeep(
                before.cellInfoAt(@intCast(row), 0),
                after.cellInfoAt(@intCast(row), 0),
            );
        }
        try std.testing.expectEqualStrings("", terminal.replyBytes());
        try std.testing.expect((try terminal.feed("\x1b[T")).stateChanged());
        try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(1, 0));
    }
}

test "terminal: SGR 21 means double underline rather than Linux console single underline" {
    var terminal = try Terminal.init(std.testing.allocator, 1, 6);
    defer terminal.deinit();
    try feed(&terminal, "\x1b[4mS\x1b[21mD\x1b[24mN");
    const view = terminal.semanticView(0);
    const single = view.cellInfoAt(0, 0).attrs;
    const doubled = view.cellInfoAt(0, 1).attrs;
    const none = view.cellInfoAt(0, 2).attrs;
    try std.testing.expect(single.underline);
    try std.testing.expectEqual(Terminal.UnderlineStyle.straight, single.underline_style);
    try std.testing.expect(doubled.underline);
    try std.testing.expectEqual(Terminal.UnderlineStyle.double, doubled.underline_style);
    try std.testing.expect(!none.underline);
    const identity = terminal.semanticSequence();
    try std.testing.expect(!(try terminal.feed("\x1b[24m")).stateChanged());
    try std.testing.expectEqual(identity, terminal.semanticSequence());
}

test "terminal: CSI caret is an SD alias for CSI T within accepted count and region bounds" {
    const seed = "\x1b[1;1HAAAAAA\x1b[2;1HBBBBBB\x1b[3;1HCCCCCC\x1b[4;1HDDDDDD\x1b[2;4r\x1b[2;1H";
    const cases = [_]struct {
        caret: []const u8,
        ordinary: []const u8,
        changes: bool,
    }{
        .{ .caret = "\x1b[^", .ordinary = "\x1b[T", .changes = true },
        .{ .caret = "\x1b[1^", .ordinary = "\x1b[1T", .changes = true },
        .{ .caret = "\x1b[2^", .ordinary = "\x1b[2T", .changes = true },
        .{ .caret = "\x9b2^", .ordinary = "\x9b2T", .changes = true },
        .{ .caret = "\x1b[0^", .ordinary = "\x1b[0T", .changes = false },
        .{ .caret = "\x1b[2;1^", .ordinary = "\x1b[2;1T", .changes = false },
    };
    for (cases) |case| {
        var alias = try Terminal.init(std.testing.allocator, 4, 6);
        defer alias.deinit();
        var canonical = try Terminal.init(std.testing.allocator, 4, 6);
        defer canonical.deinit();
        try feed(&alias, seed);
        try feed(&canonical, seed);
        const sequence = alias.semanticSequence();
        const prefix = case.caret.len - 1;
        try std.testing.expect(!(try alias.feed(case.caret[0..prefix])).stateChanged());
        const actual = try alias.feed(case.caret[prefix..]);
        const expected = try canonical.feed(case.ordinary);
        try std.testing.expectEqual(case.changes, actual.stateChanged());
        try std.testing.expectEqual(case.changes, expected.stateChanged());
        try std.testing.expectEqual(canonical.semanticSequence(), alias.semanticSequence());
        if (!case.changes) try std.testing.expectEqual(sequence, alias.semanticSequence());
        const a = alias.semanticView(0);
        const b = canonical.semanticView(0);
        try std.testing.expectEqual(b.cursor_row, a.cursor_row);
        try std.testing.expectEqual(b.cursor_col, a.cursor_col);
        for (0..4) |row| for (0..6) |col| {
            try std.testing.expectEqualDeep(b.cellInfoAt(@intCast(row), @intCast(col)), a.cellInfoAt(@intCast(row), @intCast(col)));
        };
        try std.testing.expectEqualStrings("", alias.replyBytes());
    }
}

test "terminal: CSI T scroll down preserves bounded margins, cursor and exact mutation" {
    var terminal = try Terminal.init(std.testing.allocator, 4, 6);
    defer terminal.deinit();
    try feed(
        &terminal,
        "\x1b[1;1HAAAAAA\x1b[2;1HBBBBBB\x1b[3;1HCCCCCC\x1b[4;1HDDDDDD" ++
            "\x1b[2;4r\x1b[?69h\x1b[2;5s\x1b[2;3H",
    );
    const before = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u16, 1), before.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), before.cursor_col);
    const sequence = terminal.semanticSequence();
    try std.testing.expect(!(try terminal.feed("\x1b[")).stateChanged());
    try std.testing.expectEqual(sequence, terminal.semanticSequence());
    const one = try terminal.feed("T");
    try std.testing.expect(one.stateChanged());
    try std.testing.expect(!one.historyLost());
    try std.testing.expect(terminal.semanticSequence() > sequence);
    const scrolled = terminal.semanticView(0);
    try std.testing.expectEqual(before.cursor_row, scrolled.cursor_row);
    try std.testing.expectEqual(before.cursor_col, scrolled.cursor_col);
    for ([_][]const u8{ "AAAAAA", "B    B", "CBBBBC", "DCCCCD" }, 0..) |expected, row| {
        for (expected, 0..) |letter, col| {
            try std.testing.expectEqual(@as(u21, if (letter == ' ') 0 else letter), scrolled.cellAt(@intCast(row), @intCast(col)));
        }
    }
    const two = try terminal.feed("\x1b[2T");
    try std.testing.expect(two.stateChanged());
    try std.testing.expect(!two.historyLost());
    const cleared = terminal.semanticView(0);
    for ([_][]const u8{ "AAAAAA", "B    B", "C    C", "D    D" }, 0..) |expected, row| {
        for (expected, 0..) |letter, col| {
            try std.testing.expectEqual(@as(u21, if (letter == ' ') 0 else letter), cleared.cellAt(@intCast(row), @intCast(col)));
        }
    }
    try std.testing.expectEqual(before.cursor_row, cleared.cursor_row);
    try std.testing.expectEqual(before.cursor_col, cleared.cursor_col);
    try std.testing.expectEqual(@as(u32, 0), cleared.history_count);
    const stable = terminal.semanticSequence();
    try std.testing.expect(!(try terminal.feed("\x1b[?T")).stateChanged());
    try std.testing.expectEqual(stable, terminal.semanticSequence());

    // Writing the last margin cell requests delayed wrap; CSI T cancels it
    // rather than allowing the next printable character to advance a row.
    try feed(&terminal, "\x1b[2;5H!");
    try std.testing.expect((try terminal.feed("\x1b[T")).stateChanged());
    try feed(&terminal, "Z");
    try std.testing.expectEqual(@as(u16, 1), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u21, 'Z'), terminal.semanticView(0).cellAt(1, 4));
    const final = terminal.semanticView(0);
    for (0..4) |row| {
        try std.testing.expectEqual(@as(u21, "ABCD"[row]), final.cellAt(@intCast(row), 0));
        try std.testing.expectEqual(@as(u21, "ABCD"[row]), final.cellAt(@intCast(row), 5));
    }

    var one_row = try Terminal.init(std.testing.allocator, 1, 3);
    defer one_row.deinit();
    try feed(&one_row, "\x1b[1;1HBBB\x1b[1;2H");
    try std.testing.expect((try one_row.feed("\x1b[999999T")).stateChanged());
    const narrow = one_row.semanticView(0);
    try std.testing.expectEqual(@as(u21, 0), narrow.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), narrow.cellAt(0, 2));
    try std.testing.expectEqual(@as(u16, 0), narrow.cursor_row);
    try std.testing.expectEqual(@as(u16, 1), narrow.cursor_col);
}

test "terminal: physical cell shifts preserve intact downstream wide graphemes" {
    // Pinned iTerm2 moves an intact DWC pair and repairs only the cells
    // actually split by a deletion/insertion boundary. The cursor-origin
    // operations here do not cut through the glyph itself.
    for ([_]struct {
        edit: []const u8,
        lead: u16,
        first: u21,
        trailing: u21,
    }{
        .{ .edit = "\x1b[P", .lead = 0, .first = '界', .trailing = 'B' },
        .{ .edit = "\x1b[@", .lead = 2, .first = 0, .trailing = 'B' },
        .{ .edit = "\x1b[1'~", .lead = 0, .first = '界', .trailing = 'B' },
        .{ .edit = "\x1b[1'}", .lead = 2, .first = 0, .trailing = 'B' },
    }) |case| {
        var terminal = try Terminal.init(std.testing.allocator, 2, 8);
        defer terminal.deinit();
        try feed(&terminal, "\x1b[1;1HA界BC\x1b[2;1HP界QR\x1b[1;1H");
        try std.testing.expect((try terminal.feed(case.edit)).stateChanged());
        const view = terminal.semanticView(0);
        try std.testing.expectEqual(case.first, view.cellAt(0, 0));
        try std.testing.expectEqual(@as(u21, '界'), view.cellAt(0, case.lead));
        try std.testing.expectEqual(@as(u8, 2), view.cellInfoAt(0, case.lead).width);
        try std.testing.expectEqual(@as(u8, 1), view.cellInfoAt(0, case.lead + 1).x);
        try std.testing.expectEqual(case.trailing, view.cellAt(0, case.lead + 2));
        if (case.edit[case.edit.len - 1] == '}' or case.edit[case.edit.len - 1] == '~') {
            try std.testing.expectEqual(@as(u21, '界'), view.cellAt(1, case.lead));
            try std.testing.expectEqual(@as(u8, 2), view.cellInfoAt(1, case.lead).width);
            try std.testing.expectEqual(@as(u8, 1), view.cellInfoAt(1, case.lead + 1).x);
        }
    }
}

test "terminal: editing through either half of wide glyph clears only its cluster" {
    for ([_]struct { col: u8, edit: []const u8, expected_c: u8, expected_d: u8 }{
        .{ .col = 3, .edit = "\x1b[P", .expected_c = 3, .expected_d = 4 },
        .{ .col = 2, .edit = "\x1b[P", .expected_c = 3, .expected_d = 4 },
        .{ .col = 3, .edit = "\x1b[@", .expected_c = 5, .expected_d = 6 },
        .{ .col = 3, .edit = "\x1b[1'~", .expected_c = 3, .expected_d = 4 },
        .{ .col = 3, .edit = "\x1b[1'}", .expected_c = 5, .expected_d = 6 },
    }) |case| {
        var terminal = try Terminal.init(std.testing.allocator, 2, 8);
        defer terminal.deinit();
        var cursor: [16]u8 = undefined;
        const move = try std.fmt.bufPrint(&cursor, "\x1b[1;{d}H", .{case.col + 1});
        try feed(&terminal, "AB界CD\x1b[2;1HPQ界RS");
        try feed(&terminal, move);
        try std.testing.expect((try terminal.feed(case.edit)).stateChanged());
        const view = terminal.semanticView(0);
        try std.testing.expectEqual(@as(u21, 0), view.cellAt(0, 2));
        try std.testing.expectEqual(@as(u8, 1), view.cellInfoAt(0, 2).width);
        try std.testing.expectEqual(@as(u8, 0), view.cellInfoAt(0, 2).x);
        try std.testing.expectEqual(@as(u21, 'C'), view.cellAt(0, case.expected_c));
        try std.testing.expectEqual(@as(u21, 'D'), view.cellAt(0, case.expected_d));
        if (case.edit[case.edit.len - 1] == '}' or case.edit[case.edit.len - 1] == '~') {
            try std.testing.expectEqual(@as(u21, 0), view.cellAt(1, 2));
            try std.testing.expectEqual(@as(u21, 'R'), view.cellAt(1, case.expected_c));
            try std.testing.expectEqual(@as(u21, 'S'), view.cellAt(1, case.expected_d));
        }
    }

    // The final half of a wide glyph may be truncated by insertion.
    // Its lead must also be removed before source cells are shifted.
    var clipped = try Terminal.init(std.testing.allocator, 1, 8);
    defer clipped.deinit();
    try feed(&clipped, "ABCDEF界\x1b[1;1H\x1b[@");
    const view = clipped.semanticView(0);
    try std.testing.expectEqual(@as(u21, 0), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'A'), view.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'F'), view.cellAt(0, 6));
    try std.testing.expectEqual(@as(u21, 0), view.cellAt(0, 7));
}

test "terminal: one-row character deletion clears intersecting multiline cluster on both rows" {
    for ([_][]const u8{ "\x1b[P", "\x1b[@" }) |edit| {
        var terminal = try Terminal.init(std.testing.allocator, 4, 8);
        defer terminal.deinit();
        try feed(&terminal, "\x1b[2;3H\x1b]66;s=2;X\x07");
        const before = terminal.semanticView(0);
        try std.testing.expectEqual(@as(u21, 'X'), before.cellAt(1, 2));
        try std.testing.expectEqual(@as(u8, 2), before.cellInfoAt(1, 2).height);
        try std.testing.expectEqual(@as(u8, 1), before.cellInfoAt(2, 3).y);

        // This structural edit only shifts one row, so retaining the other
        // half of a two-row owned cluster would create an orphan fragment.
        try feed(&terminal, "\x1b[2;1H");
        try std.testing.expect((try terminal.feed(edit)).stateChanged());
        const after = terminal.semanticView(0);
        for (1..3) |row| for (2..4) |col| {
            const cell = after.cellInfoAt(@intCast(row), @intCast(col));
            try std.testing.expectEqual(@as(u8, 1), cell.width);
            try std.testing.expectEqual(@as(u8, 1), cell.height);
            try std.testing.expectEqual(@as(u8, 0), cell.x);
            try std.testing.expectEqual(@as(u8, 0), cell.y);
            try std.testing.expectEqual(@as(u21, 0), cell.codepoint);
        };
    }
}

test "terminal: wide edit moves retained combining scalars rather than erasing source" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 9);
    defer terminal.deinit();
    try feed(&terminal, "A界e\u{301}\u{327}\u{308}\u{350}\u{360}\u{302}Z");
    const before = terminal.semanticView(0).cellInfoAt(0, 3);
    try std.testing.expectEqual(@as(u21, 'e'), before.codepoint);
    try std.testing.expect(before.combining_len > 3);
    try feed(&terminal, "\x1b[1;1H\x1b[P");
    const after = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u21, '界'), after.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'e'), after.cellAt(0, 2));
    const moved = after.cellInfoAt(0, 2);
    try std.testing.expectEqual(before.combining_len, moved.combining_len);
    try std.testing.expectEqualDeep(before.combining, moved.combining);
    try std.testing.expectEqual(@as(u21, 'Z'), after.cellAt(0, 3));
    // Replacing the moved cell releases its original extended scalar tail.
    try feed(&terminal, "\x1b[1;3HQ");
    try std.testing.expectEqual(@as(u21, 'Q'), terminal.semanticView(0).cellAt(0, 2));
}

test "terminal: iTerm2 structural erase attrs differ from Howl current SGR" {
    // Pinned iTerm2 copies grid defaultChar (no bold or dim flags) into
    // inserted/tail cells. Howl deliberately uses current erase attrs.
    for ([_]struct { edit: []const u8, blank_col: u16 }{
        .{ .edit = "\x1b[P", .blank_col = 7 },
        .{ .edit = "\x1b[1'}", .blank_col = 1 },
        .{ .edit = "\x1b[1'~", .blank_col = 7 },
    }) |case| {
        var terminal = try Terminal.init(std.testing.allocator, 2, 8);
        defer terminal.deinit();
        try feed(&terminal, "\x1b[1;1HABCDEFGH\x1b[2;1HIJKLMNOP\x1b[1;2H\x1b[1;2;31m");
        try std.testing.expect((try terminal.feed(case.edit)).stateChanged());
        const cell = terminal.semanticView(0).cellInfoAt(0, case.blank_col);
        try std.testing.expectEqual(@as(u21, 0), cell.codepoint);
        try std.testing.expect(cell.attrs.bold);
        try std.testing.expect(cell.attrs.dim);
        try std.testing.expectEqual(Terminal.Color.indexed(1), cell.attrs.fg);
        try std.testing.expect(cell.attrs.protected == .none);
        if (case.edit[case.edit.len - 1] != 'P') {
            const second = terminal.semanticView(0).cellInfoAt(1, case.blank_col);
            try std.testing.expectEqual(@as(u21, 0), second.codepoint);
            try std.testing.expect(second.attrs.bold);
            try std.testing.expect(second.attrs.dim);
        }
    }
}

test "terminal: DEC horizontal region shifts move intact wide glyphs in both directions" {
    for ([_]struct { command: []const u8, lead: u16, expected_suffix: u16 }{
        .{ .command = "\x1b[1 @", .lead = 0, .expected_suffix = 2 },
        .{ .command = "\x1b[1 A", .lead = 2, .expected_suffix = 4 },
    }) |case| {
        var terminal = try Terminal.init(std.testing.allocator, 3, 8);
        defer terminal.deinit();
        try feed(&terminal, "\x1b[1;1HA界BC\x1b[2;1HP界QR\x1b[1;1H");
        const before = terminal.semanticView(0);
        try std.testing.expect((try terminal.feed(case.command)).stateChanged());
        const view = terminal.semanticView(0);
        for (0..2) |row| {
            try std.testing.expectEqual(@as(u21, '界'), view.cellAt(@intCast(row), case.lead));
            try std.testing.expectEqual(@as(u8, 2), view.cellInfoAt(@intCast(row), case.lead).width);
            try std.testing.expectEqual(@as(u8, 1), view.cellInfoAt(@intCast(row), case.lead + 1).x);
        }
        try std.testing.expectEqual(@as(u21, 'B'), view.cellAt(0, case.expected_suffix));
        try std.testing.expectEqual(@as(u21, 'Q'), view.cellAt(1, case.expected_suffix));
        try std.testing.expectEqual(before.cursor_row, view.cursor_row);
        try std.testing.expectEqual(before.cursor_col, view.cursor_col);
    }
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

test "terminal: Kitty graphics feature query reports only bounded supported actions" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 10);
    defer terminal.deinit();
    const generation = terminal.images(0).generation;

    try std.testing.expect(!(try terminal.feed("\x1b_Ga=q,i=31,e=T,U=1,C=1")).stateChanged());
    try std.testing.expectEqualStrings("", terminal.replyBytes());
    try std.testing.expect((try terminal.feed("\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings("\x1b_Gi=31,e=T,C=1,U=1;OK\x1b\\", terminal.replyBytes());
    try std.testing.expectEqual(generation, terminal.images(0).generation);
    try std.testing.expectEqual(@as(usize, 0), terminal.images(0).imageCount());
    try consumeReplies(&terminal);

    try std.testing.expect((try terminal.feed("\x1b_Ga=q,i=31,e=t,f=24,s=1,v=1,t=d,o=z,N=1\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings("\x1b_Gi=31,e=t,t=d,o=z,f=24,s=1,v=1,N=1;OK\x1b\\", terminal.replyBytes());
    try consumeReplies(&terminal);

    // Indexed transmission is now supported; file medium, U=0, C=0 and
    // unsupported usage-hint values are still not advertised as features.
    try std.testing.expect((try terminal.feed("\x1b_Ga=q,i=31,e=T,f=8,t=f,U=0,C=0,N=6\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings("\x1b_Gi=31,e=T,f=8;OK\x1b\\", terminal.replyBytes());
    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed("\x1b_Ga=q,i=31,e=Z,U=1\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings("\x1b_Gi=31;OK\x1b\\", terminal.replyBytes());
    try consumeReplies(&terminal);
    try std.testing.expect(!(try terminal.feed("\x1b_Ga=q,i=31,e=T,U=1,q=1\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings("", terminal.replyBytes());
    try std.testing.expectEqual(generation, terminal.images(0).generation);
    try std.testing.expectEqual(@as(usize, 0), terminal.images(0).imageCount());
}

test "terminal: Kitty graphics placement features negotiate only represented keys" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    const generation = terminal.images(0).generation;

    // Kitty 0.51 graphics.c::supported_keys_for_query emits e=p then
    // placement fields in canonical order, excluding transmit-only s/f.
    try std.testing.expect((try terminal.feed(
        "\x1b_Ga=q,i=31,e=p,p=2,x=1,y=2,w=3,h=4,X=5,Y=6,c=2,r=3,C=1,U=1,z=-3,s=1\x1b\\",
    )).stateChanged());
    try std.testing.expectEqualStrings(
        "\x1b_Gi=31,e=p,p=2,x=1,y=2,w=3,h=4,X=5,Y=6,c=2,r=3,C=1,U=1,z=-3;OK\x1b\\",
        terminal.replyBytes(),
    );
    try std.testing.expectEqual(generation, terminal.images(0).generation);
    try std.testing.expectEqual(@as(usize, 0), terminal.images(0).imageCount());
    try std.testing.expectEqual(@as(usize, 0), terminal.images(0).placementCount());
    try consumeReplies(&terminal);

    // The transmit-display action supports the *same* placement vocabulary,
    // while ordinary transmit queries do not imply placement support.
    try std.testing.expect((try terminal.feed("\x1b_Ga=q,i=31,e=T,p=7,x=1,w=2,U=1\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings("\x1b_Gi=31,e=T,p=7,x=1,w=2,U=1;OK\x1b\\", terminal.replyBytes());
    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed("\x1b_Ga=q,i=31,e=t,p=7,x=1,w=2,U=1\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings("\x1b_Gi=31,e=t;OK\x1b\\", terminal.replyBytes());
    try consumeReplies(&terminal);
    // A query may mention Kitty's parent-relative keys; Howl must omit
    // unsupported capabilities without turning the probe into an error.
    try std.testing.expect((try terminal.feed("\x1b_Ga=q,i=31,e=p,P=10,Q=20,H=-3,V=4,C=1\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings("\x1b_Gi=31,e=p,C=1;OK\x1b\\", terminal.replyBytes());
    try consumeReplies(&terminal);
    try std.testing.expect(!(try terminal.feed("\x1b_Ga=q,i=31,e=p,C=0,U=0,q=1\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings("", terminal.replyBytes());
    try std.testing.expectEqual(generation, terminal.images(0).generation);
}

test "terminal: Kitty graphics deletion capability replies are selector honest" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    const original = terminal.images(0).generation;
    const cases = [_]struct { query: []const u8, expected: []const u8 }{
        .{ .query = "\x1b_Ga=q,i=31,e=d,d=i,p=7\x1b\\", .expected = "\x1b_Gi=31,e=d,d=i,p=7;OK\x1b\\" },
        .{ .query = "\x1b_Ga=q,i=31,e=d,d=q,x=2,y=3,z=-7\x1b\\", .expected = "\x1b_Gi=31,e=d,d=q,x=2,y=3,z=-7;OK\x1b\\" },
        .{ .query = "\x1b_Ga=q,i=31,e=d,d=R,x=99,y=101\x1b\\", .expected = "\x1b_Gi=31,e=d,d=R,x=99,y=101;OK\x1b\\" },
        .{ .query = "\x1b_Ga=q,i=31,e=d,d=c,p=7,x=2,y=3,z=-7\x1b\\", .expected = "\x1b_Gi=31,e=d,d=c;OK\x1b\\" },
    };
    for (cases) |test_case| {
        try std.testing.expect((try terminal.feed(test_case.query)).stateChanged());
        try std.testing.expectEqualStrings(test_case.expected, terminal.replyBytes());
        try std.testing.expectEqual(original, terminal.images(0).generation);
        try std.testing.expectEqual(@as(usize, 0), terminal.images(0).imageCount());
        try std.testing.expectEqual(@as(usize, 0), terminal.images(0).placementCount());
        try consumeReplies(&terminal);
    }
    // Current Kitty's delete selector parser rejects d=U outright; the
    // feature query must be silent without claiming a successful capability.
    try std.testing.expect(!(try terminal.feed("\x1b_Ga=q,i=31,e=d,d=U,p=7,x=2,y=3,z=-7\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings("", terminal.replyBytes());
    try std.testing.expect(!(try terminal.feed("\x1b_Ga=q,i=31,e=T,d=U,U=1\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings("", terminal.replyBytes());
    try std.testing.expect(!(try terminal.feed("\x1b_Ga=q,i=31,e=d,d=i,p=7,q=1\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings("", terminal.replyBytes());
}

test "terminal: Kitty deletion feature queries preflight bounded replies and silence" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 2, 8);
    defer terminal.deinit();
    const query = "\x1b_Ga=q,i=31,e=d,d=q,x=2,y=3,z=-7\x1b\\";
    const response = "\x1b_Gi=31,e=d,d=q,x=2,y=3,z=-7;OK\x1b\\";
    const prefix = try reply_fill.fill(&terminal, allocator, 64 * 1024 - response.len + 1, false);
    defer allocator.free(prefix);
    const generation = terminal.images(0).generation;
    try std.testing.expectError(error.ReplyLimit, terminal.feed(query));
    try std.testing.expectEqualSlices(u8, prefix, terminal.replyBytes());
    try std.testing.expectEqual(generation, terminal.images(0).generation);
    for ([_][]const u8{
        "\x1b_Ga=q,i=31,e=d,d=q,x=2,y=3,z=-7,q=1\x1b\\",
        "\x1b_Ga=q,i=31,e=d,d=q,x=2,y=3,z=-7,q=2\x1b\\",
    }) |quiet| {
        try std.testing.expect(!(try terminal.feed(quiet)).stateChanged());
        try std.testing.expectEqualSlices(u8, prefix, terminal.replyBytes());
    }
    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed(query)).stateChanged());
    try std.testing.expectEqualStrings(response, terminal.replyBytes());
    try std.testing.expectEqual(generation, terminal.images(0).generation);
    try std.testing.expectEqual(@as(usize, 0), terminal.images(0).imageCount());
    try std.testing.expectEqual(@as(usize, 0), terminal.images(0).placementCount());
}

test "terminal: Kitty frame animation and composition feature queries are action typed" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    const original = terminal.images(0).generation;
    const cases = [_]struct { query: []const u8, reply: []const u8 }{
        .{
            .query = "\x1b_Ga=q,i=31,e=f,f=24,s=1,v=1,x=1,y=2,c=2,r=3,z=-40,X=1,Y=4278255615\x1b\\",
            .reply = "\x1b_Gi=31,e=f,f=24,s=1,v=1,x=1,y=2,c=2,r=3,z=-40,X=1,Y=4278255615;OK\x1b\\",
        },
        .{
            .query = "\x1b_Ga=q,i=31,e=f,f=100,s=5000,X=2,c=999,r=999\x1b\\",
            .reply = "\x1b_Gi=31,e=f;OK\x1b\\",
        },
        .{
            .query = "\x1b_Ga=q,i=31,e=a,s=3,v=1,r=2,c=1,z=-1\x1b\\",
            .reply = "\x1b_Gi=31,e=a,s=3,v=1,r=2,c=1,z=-1;OK\x1b\\",
        },
        .{
            .query = "\x1b_Ga=q,i=31,e=a,s=4,v=1,r=999,c=999\x1b\\",
            .reply = "\x1b_Gi=31,e=a,v=1;OK\x1b\\",
        },
        .{
            .query = "\x1b_Ga=q,i=31,e=c,r=1,c=2,x=1,y=2,w=3,h=4,X=5,Y=6,C=1,U=1\x1b\\",
            .reply = "\x1b_Gi=31,e=c,r=1,c=2,x=1,y=2,w=3,h=4,X=5,Y=6,C=1;OK\x1b\\",
        },
        .{
            .query = "\x1b_Ga=q,i=31,e=c,r=999,c=999,x=5000,y=5000,w=5000,h=5000,C=1\x1b\\",
            .reply = "\x1b_Gi=31,e=c,C=1;OK\x1b\\",
        },
    };
    for (cases) |tc| {
        try std.testing.expect((try terminal.feed(tc.query)).stateChanged());
        try std.testing.expectEqualStrings(tc.reply, terminal.replyBytes());
        try std.testing.expectEqual(original, terminal.images(0).generation);
        try std.testing.expectEqual(@as(usize, 0), terminal.images(0).imageCount());
        try std.testing.expectEqual(@as(usize, 0), terminal.images(0).placementCount());
        try consumeReplies(&terminal);
    }
    try std.testing.expect(!(try terminal.feed("\x1b_Ga=q,i=31,e=f,s=1,v=1,q=1\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings("", terminal.replyBytes());
    try std.testing.expectEqual(original, terminal.images(0).generation);
}

test "terminal: Kitty graphics feature queries reserve exact reply bytes atomically" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 2, 8);
    defer terminal.deinit();
    const query = "\x1b_Ga=q,i=31,e=T,U=1\x1b\\";
    const response = "\x1b_Gi=31,e=T,U=1;OK\x1b\\";
    const prefix = try reply_fill.fill(&terminal, allocator, 64 * 1024 - response.len + 1, false);
    defer allocator.free(prefix);
    const generation = terminal.images(0).generation;

    // No partial escape can leak when the required response exceeds available
    // space by one byte. The graphics plane remains absolutely unchanged.
    try std.testing.expectError(error.ReplyLimit, terminal.feed(query));
    try std.testing.expectEqualSlices(u8, prefix, terminal.replyBytes());
    try std.testing.expectEqual(generation, terminal.images(0).generation);
    try std.testing.expectEqual(@as(usize, 0), terminal.images(0).imageCount());

    // Quiet feature negotiation may still succeed with an entirely full
    // reply queue, because it reserves and emits zero reply bytes.
    try std.testing.expect(!(try terminal.feed("\x1b_Ga=q,i=31,e=T,U=1,q=1\x1b\\")).stateChanged());
    try std.testing.expectEqualSlices(u8, prefix, terminal.replyBytes());
    try consumeReplies(&terminal);

    // The same valid query recovers after the caller drains the queue.
    try std.testing.expect((try terminal.feed(query)).stateChanged());
    try std.testing.expectEqualStrings(response, terminal.replyBytes());
    try std.testing.expectEqual(generation, terminal.images(0).generation);
}

test "terminal: Kitty graphics placement feature replies are atomically quota bounded" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 2, 8);
    defer terminal.deinit();
    const query = "\x1b_Ga=q,i=31,e=p,p=2,x=1,y=2,w=3,h=4,X=5,Y=6,c=2,r=3,C=1,U=1,z=-3\x1b\\";
    const reply = "\x1b_Gi=31,e=p,p=2,x=1,y=2,w=3,h=4,X=5,Y=6,c=2,r=3,C=1,U=1,z=-3;OK\x1b\\";
    const fill = try reply_fill.fill(&terminal, allocator, 64 * 1024 - reply.len + 1, false);
    defer allocator.free(fill);
    const before = terminal.images(0).generation;

    try std.testing.expectError(error.ReplyLimit, terminal.feed(query));
    try std.testing.expectEqualSlices(u8, fill, terminal.replyBytes());
    try std.testing.expectEqual(before, terminal.images(0).generation);
    try std.testing.expectEqual(@as(usize, 0), terminal.images(0).placementCount());

    // Neither quiet form consumes any remaining capacity or changes images.
    for ([_][]const u8{
        "\x1b_Ga=q,i=31,e=p,p=2,C=1,q=1\x1b\\",
        "\x1b_Ga=q,i=31,e=p,p=2,C=1,q=2\x1b\\",
    }) |silent| {
        try std.testing.expect(!(try terminal.feed(silent)).stateChanged());
        try std.testing.expectEqualSlices(u8, fill, terminal.replyBytes());
        try std.testing.expectEqual(before, terminal.images(0).generation);
    }
    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed(query)).stateChanged());
    try std.testing.expectEqualStrings(reply, terminal.replyBytes());
    try std.testing.expectEqual(before, terminal.images(0).generation);
}

test "terminal: Kitty frame capability reply is atomic under saturated pressure" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 2, 8);
    defer terminal.deinit();
    const query = "\x1b_Ga=q,i=31,e=f,f=24,s=1,v=1,c=2,r=3,z=-40,X=1,Y=4278255615\x1b\\";
    const response = "\x1b_Gi=31,e=f,f=24,s=1,v=1,c=2,r=3,z=-40,X=1,Y=4278255615;OK\x1b\\";
    const fill = try reply_fill.fill(&terminal, allocator, 64 * 1024 - response.len + 1, false);
    defer allocator.free(fill);
    const generation = terminal.images(0).generation;
    try std.testing.expectError(error.ReplyLimit, terminal.feed(query));
    try std.testing.expectEqualSlices(u8, fill, terminal.replyBytes());
    try std.testing.expectEqual(generation, terminal.images(0).generation);
    for ([_][]const u8{
        "\x1b_Ga=q,i=31,e=f,f=24,c=2,r=3,q=1\x1b\\",
        "\x1b_Ga=q,i=31,e=c,r=1,c=2,C=1,q=2\x1b\\",
    }) |silent| {
        try std.testing.expect(!(try terminal.feed(silent)).stateChanged());
        try std.testing.expectEqualSlices(u8, fill, terminal.replyBytes());
    }
    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed(query)).stateChanged());
    try std.testing.expectEqualStrings(response, terminal.replyBytes());
    try std.testing.expectEqual(generation, terminal.images(0).generation);
    try std.testing.expectEqual(@as(usize, 0), terminal.images(0).imageCount());
}

test "terminal: Kitty graphics feature query cannot cancel an unfinished image" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();

    // One 1x1 RGBA image split into two base64 chunks. Feature metadata and
    // an arbitrary payload on the query must never interfere with the load.
    try std.testing.expect(!(try terminal.feed("\x1b_Ga=t,i=99,f=32,s=1,v=1,m=1;AQID\x1b\\")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b_Ga=q,i=31,e=T,U=1;ignored\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings("\x1b_Gi=31,e=T,U=1;OK\x1b\\", terminal.replyBytes());
    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed("\x1b_Ga=q,i=31,e=p,c=2,r=3,U=1,C=1;ignored\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings("\x1b_Gi=31,e=p,c=2,r=3,C=1,U=1;OK\x1b\\", terminal.replyBytes());
    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed("\x1b_Ga=q,i=31,e=p,P=10,Q=20,H=-3,V=4,C=1\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings("\x1b_Gi=31,e=p,C=1;OK\x1b\\", terminal.replyBytes());
    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed("\x1b_Ga=q,i=31,e=d,d=i,p=7;unused\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings("\x1b_Gi=31,e=d,d=i,p=7;OK\x1b\\", terminal.replyBytes());
    try consumeReplies(&terminal);
    try std.testing.expect(!(try terminal.feed("\x1b_Ga=q,i=31,e=d,d=U,p=7\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings("", terminal.replyBytes());
    // Neither frame editing nor animation/compose capability queries may
    // interrupt the unrelated chunked image held by the graphics plane.
    const pending_queries = [_]struct { bytes: []const u8, reply: []const u8 }{
        .{ .bytes = "\x1b_Ga=q,i=31,e=f,f=24,s=1,v=1,c=2,r=2,X=1;ignored\x1b\\", .reply = "\x1b_Gi=31,e=f,f=24,s=1,v=1,c=2,r=2,X=1;OK\x1b\\" },
        .{ .bytes = "\x1b_Ga=q,i=31,e=a,s=3,v=1,r=2,c=1,z=-1;ignored\x1b\\", .reply = "\x1b_Gi=31,e=a,s=3,v=1,r=2,c=1,z=-1;OK\x1b\\" },
        .{ .bytes = "\x1b_Ga=q,i=31,e=c,r=1,c=2,w=1,h=1,C=1;ignored\x1b\\", .reply = "\x1b_Gi=31,e=c,r=1,c=2,w=1,h=1,C=1;OK\x1b\\" },
    };
    for (pending_queries) |tc| {
        try std.testing.expect((try terminal.feed(tc.bytes)).stateChanged());
        try std.testing.expectEqualStrings(tc.reply, terminal.replyBytes());
        try consumeReplies(&terminal);
    }
    try std.testing.expect((try terminal.feed("\x1b_Gm=0;BA==\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings("\x1b_Gi=99;OK\x1b\\", terminal.replyBytes());
    try std.testing.expectEqual(@as(usize, 1), terminal.images(0).imageCount());
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, terminal.images(0).image(0).?.pixels);
}

test "terminal: Yazi-style anonymous Kitty preview is quiet stationary and deletable" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();

    const cursor_row_before = terminal.semanticView(0).cursor_row;
    const cursor_col_before = terminal.semanticView(0).cursor_col;
    try std.testing.expect(
        !(try terminal.feed("\x1b_Gq=2,a=T,z=-1,C=1,f=24,s=2,v=1,m=1;/wAA\x1b\\")).stateChanged(),
    );
    try std.testing.expect(
        (try terminal.feed("\x1b_Gm=0;AP8A\x1b\\")).stateChanged(),
    );
    const images = terminal.images(0);
    try std.testing.expectEqual(@as(usize, 1), images.imageCount());
    try std.testing.expectEqual(@as(usize, 1), images.placementCount());
    try std.testing.expectEqualSlices(
        u8,
        &.{ 255, 0, 0, 255, 0, 255, 0, 255 },
        images.image(0).?.pixels,
    );
    try std.testing.expectEqual(@as(i32, -1), images.placement(0).?.z);
    try std.testing.expectEqual(cursor_row_before, terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(cursor_col_before, terminal.semanticView(0).cursor_col);
    try std.testing.expectEqualStrings("", terminal.replyBytes());

    try std.testing.expect((try terminal.feed("\x1b_Gq=2,a=d,d=A\x1b\\")).stateChanged());
    try std.testing.expectEqual(@as(usize, 0), terminal.images(0).imageCount());
    try std.testing.expectEqual(@as(usize, 0), terminal.images(0).placementCount());
    try std.testing.expectEqualStrings("", terminal.replyBytes());
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

test "terminal: newer Kitty indexed formats reject surplus pixel bytes without leaking image state" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 4);
    defer terminal.deinit();
    for ([_]u8{ 8, 16 }) |format| {
        var buf: [96]u8 = undefined;
        const command = try std.fmt.bufPrint(&buf, "\x1b_Ga=t,f={d},s=1,v=1,i=74;AQIDBA==\x1b\\", .{format});
        try std.testing.expect((try terminal.feed(command)).stateChanged());
        // Four raw bytes cannot fit either one indexed byte (f=8) or two
        // indexed-plus-alpha bytes (f=16) for one pixel. Admission remains
        // bounded and transactionally rejects this malformed source size.
        try std.testing.expectEqualStrings("\x1b_Gi=74;ENOSPC\x1b\\", terminal.replyBytes());
        try consumeReplies(&terminal);
        try std.testing.expectEqual(@as(usize, 0), terminal.images(0).imageCount());
        try std.testing.expectEqual(@as(usize, 0), terminal.images(0).placementCount());
        try std.testing.expectEqual(@as(u8, 0), terminal.consequenceCount());
    }
    // Malformed indexed payloads cannot suppress later valid RGBA.
    try std.testing.expect((try terminal.feed(
        "\x1b_Ga=t,f=32,s=1,v=1,i=75,q=2;AQIDBA==\x1b\\",
    )).stateChanged());
    try std.testing.expectEqual(@as(usize, 1), terminal.images(0).imageCount());
}

test "terminal: indexed Kitty pixels follow canonical palette mutations without losing alpha or image identity" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    try terminal.setCellPixelSize(1, 1);
    try feed(
        &terminal,
        "\x1b[2;1H" ++
            "\x1b_Ga=T,f=8,s=2,v=1,i=91,C=1,q=2;Afg=\x1b\\" ++
            "\x1b[3;1H\x1b_Ga=T,f=16,s=2,v=1,i=92,C=1,q=2;AoD5/w==\x1b\\",
    );
    const initial = terminal.images(0);
    try std.testing.expectEqual(@as(usize, 2), initial.imageCount());
    try std.testing.expectEqual(@as(usize, 2), initial.placementCount());
    const initial_colors = terminal.presentation();
    const red = initial_colors.palette[1];
    const green = initial_colors.palette[2];
    const bg = initial_colors.background;
    const fg = initial_colors.foreground;
    try std.testing.expectEqualSlices(u8, &.{ red.r, red.g, red.b, 255, bg.r, bg.g, bg.b, 255 }, initial.image(0).?.pixels);
    try std.testing.expectEqualSlices(u8, &.{ green.r, green.g, green.b, 128, fg.r, fg.g, fg.b, 255 }, initial.image(1).?.pixels);
    const source_id = initial.image(0).?.id;
    const second_id = initial.image(1).?.id;
    const geometry_generation = initial.generation;

    try feed(&terminal, "\x1b]4;1;#112233;2;#aabbcc\x1b\\\x1b]10;#445566\x1b\\\x1b]11;#778899\x1b\\");
    const recolored = terminal.images(0);
    try std.testing.expectEqual(source_id, recolored.image(0).?.id);
    try std.testing.expectEqual(second_id, recolored.image(1).?.id);
    try std.testing.expect(recolored.generation > geometry_generation);
    try std.testing.expectEqualSlices(u8, &.{ 0x11, 0x22, 0x33, 255, 0x77, 0x88, 0x99, 255 }, recolored.image(0).?.pixels);
    try std.testing.expectEqualSlices(u8, &.{ 0xaa, 0xbb, 0xcc, 128, 0x44, 0x55, 0x66, 255 }, recolored.image(1).?.pixels);
    const changed = recolored.content_generation;
    try feed(&terminal, "\x1b]4;1;#112233;2;#aabbcc\x1b\\");
    try std.testing.expectEqual(changed, terminal.images(0).content_generation);

    var host_defaults = Terminal.ColorDefaults{};
    host_defaults.palette[1] = .{ .r = 5, .g = 6, .b = 7 };
    host_defaults.palette[2] = .{ .r = 8, .g = 9, .b = 10 };
    host_defaults.foreground = .{ .r = 11, .g = 12, .b = 13 };
    host_defaults.background = .{ .r = 14, .g = 15, .b = 16 };
    terminal.setColorDefaults(host_defaults);
    try std.testing.expectEqualSlices(u8, &.{ 5, 6, 7, 255, 14, 15, 16, 255 }, terminal.images(0).image(0).?.pixels);
    try std.testing.expectEqualSlices(u8, &.{ 8, 9, 10, 128, 11, 12, 13, 255 }, terminal.images(0).image(1).?.pixels);
}

test "terminal: indexed Kitty zlib, query, stack restore and forbidden animation preserve owned bytes" {
    var terminal = try Terminal.init(std.testing.allocator, 4, 8);
    defer terminal.deinit();
    try terminal.setCellPixelSize(1, 1);
    try feed(
        &terminal,
        "\x1b_Ga=T,f=8,s=2,v=2,i=93,o=z,C=1,q=2;eJxj/PGTCQAE5AH1\x1b\\" ++
            "\x1b_Ga=T,f=16,s=2,v=1,i=94,o=z,C=1,q=2;eJxjavj5HwAEfQJ7\x1b\\",
    );
    const colors = terminal.presentation();
    const image0 = terminal.images(0).image(0).?;
    const first = colors.palette[1];
    const second = colors.palette[2];
    const bg = colors.background;
    const fg = colors.foreground;
    try std.testing.expectEqualSlices(u8, &.{ first.r, first.g, first.b, 255, bg.r, bg.g, bg.b, 255, fg.r, fg.g, fg.b, 255, second.r, second.g, second.b, 255 }, image0.pixels);
    try std.testing.expectEqualSlices(u8, &.{ second.r, second.g, second.b, 128, fg.r, fg.g, fg.b, 255 }, terminal.images(0).image(1).?.pixels);
    const identity = terminal.images(0).content_generation;

    // Feature probing validates payloads but never retains or replaces data.
    try feed(&terminal, "\x1b_Ga=q,f=8,s=1,v=1,i=95;AQ==\x1b\\");
    try std.testing.expectEqualStrings("\x1b_Gi=95;OK\x1b\\", terminal.replyBytes());
    try consumeReplies(&terminal);
    try std.testing.expectEqual(identity, terminal.images(0).content_generation);
    try std.testing.expectEqual(@as(usize, 2), terminal.images(0).imageCount());

    // Indexed image frames, animation and composition are not supported by
    // the pinned newer protocol. All attempts must be silent no-mutation
    // negative controls when q=2 requests response suppression.
    for ([_][]const u8{
        "\x1b_Ga=f,i=93,f=32,s=1,v=1,r=2,q=2;AQIDBA==\x1b\\",
        "\x1b_Ga=a,i=93,s=3,q=2\x1b\\",
        "\x1b_Ga=c,i=93,r=1,c=1,q=2\x1b\\",
        "\x1b_Ga=t,i=96,f=8,s=2,v=1,o=z,q=2;%%\x1b\\",
    }) |rejected| {
        try std.testing.expect(!(try terminal.feed(rejected)).stateChanged());
        try std.testing.expectEqual(identity, terminal.images(0).content_generation);
        try std.testing.expectEqual(@as(usize, 2), terminal.images(0).imageCount());
        try std.testing.expectEqualSlices(u8, image0.pixels, terminal.images(0).image(0).?.pixels);
    }

    // A program palette override updates the indexed image, and Kitty's
    // existing bounded color stack restores it from canonical saved colors.
    try feed(&terminal, "\x1b]30001\x1b\\\x1b]4;1;#010203\x1b\\");
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 255 }, terminal.images(0).image(0).?.pixels[0..4]);
    try feed(&terminal, "\x1b]30101\x1b\\");
    try std.testing.expectEqualSlices(u8, &.{ first.r, first.g, first.b, 255 }, terminal.images(0).image(0).?.pixels[0..4]);
}

test "terminal: Kitty indexed image special palette slots are live with foreground and background fallbacks" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 12);
    defer terminal.deinit();
    var defaults = Terminal.ColorDefaults{};
    defaults.foreground = .{ .r = 1, .g = 2, .b = 3 };
    defaults.background = .{ .r = 4, .g = 5, .b = 6 };
    defaults.selection_background = .{ .r = 7, .g = 8, .b = 9 };
    defaults.selection_foreground = .{ .r = 10, .g = 11, .b = 12 };
    defaults.cursor = .{ .r = 13, .g = 14, .b = 15 };
    defaults.cursor_text = .{ .r = 16, .g = 17, .b = 18 };
    terminal.setColorDefaults(defaults);
    try feed(&terminal, "\x1b_Ga=T,f=8,s=8,v=1,i=96,C=1,q=2;+Pn6+/z9/v8=\x1b\\");
    const image = terminal.images(0).image(0) orelse return error.ImageMissing;
    try std.testing.expectEqualSlices(u8, &.{ 4, 5, 6, 255, 1, 2, 3, 255, 7, 8, 9, 255, 10, 11, 12, 255, 13, 14, 15, 255, 16, 17, 18, 255, 1, 2, 3, 255, 1, 2, 3, 255 }, image.pixels);
    // Without optional selected/cursor color choices, documented fallbacks
    // are the canonical terminal fg/bg, not palette[250..253] or black.
    defaults.selection_background = null;
    defaults.selection_foreground = null;
    defaults.cursor = null;
    defaults.cursor_text = null;
    defaults.foreground = .{ .r = 20, .g = 21, .b = 22 };
    defaults.background = .{ .r = 23, .g = 24, .b = 25 };
    terminal.setColorDefaults(defaults);
    const recolored = terminal.images(0).image(0).?.pixels;
    try std.testing.expectEqualSlices(u8, &.{ 20, 21, 22, 255, 23, 24, 25, 255, 20, 21, 22, 255, 23, 24, 25, 255 }, recolored[8..24]);
}

test "terminal: Kitty indexed 16-bit transparent pixel remains transparent across palette changes" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 4);
    defer terminal.deinit();
    // One byte of SGR palette identity plus an alpha=0 byte. Recoloring
    // must not replace that opacity with the palette's opaque default.
    try feed(&terminal, "\x1b_Ga=t,f=16,s=1,v=1,i=97,q=2;AgA=\x1b\\");
    const before = terminal.images(0).image(0) orelse return error.MissingImage;
    try std.testing.expectEqual(@as(u8, 0), before.pixels[3]);
    const source_id = before.id;
    try feed(&terminal, "\x1b]4;2;#123456\x1b\\");
    const after = terminal.images(0).image(0) orelse return error.MissingImage;
    try std.testing.expectEqual(source_id, after.id);
    try std.testing.expectEqualSlices(u8, &.{ 0x12, 0x34, 0x56, 0 }, after.pixels);
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

test "terminal: Kitty default placement advances cursor through VT ownership" {
    var terminal = try Terminal.init(std.testing.allocator, 6, 10);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b[2;3H")).stateChanged());
    try std.testing.expect((try terminal.feed(
        "\x1b_Ga=T,f=32,s=1,v=1,i=52,c=4,r=3,q=2;AQIDBA==\x1b\\",
    )).stateChanged());
    var view = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u16, 3), view.cursor_row);
    try std.testing.expectEqual(@as(u16, 6), view.cursor_col);
    const placement = terminal.images(0).placement(0).?;
    try std.testing.expectEqual(@as(u16, 1), placement.row);
    try std.testing.expectEqual(@as(u16, 2), placement.col);

    try std.testing.expect((try terminal.feed("\x1b[1;1H")).stateChanged());
    try std.testing.expect((try terminal.feed(
        "\x1b_Ga=t,f=32,s=1,v=1,i=53,q=2;BQYHCA==\x1b\\" ++
            "\x1b_Ga=p,i=53,c=2,r=2,q=2\x1b\\",
    )).stateChanged());
    view = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u16, 1), view.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), view.cursor_col);

    try std.testing.expect((try terminal.feed("\x1b[1;1H")).stateChanged());
    try std.testing.expect((try terminal.feed(
        "\x1b_Ga=p,i=53,c=2,r=2,C=1,q=2\x1b\\",
    )).stateChanged());
    view = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u16, 0), view.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), view.cursor_col);
}

test "terminal: Kitty placement cursor advance scrolls history without detaching image" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 3, 8, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b[3;2H")).stateChanged());
    try std.testing.expect((try terminal.feed(
        "\x1b_Ga=T,f=32,s=1,v=1,i=54,c=2,r=2,q=2;CQoLDA==\x1b\\",
    )).stateChanged());
    const view = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u16, 2), view.cursor_row);
    try std.testing.expectEqual(@as(u16, 3), view.cursor_col);
    try std.testing.expectEqual(@as(u32, 1), view.history_count);
    const placement = terminal.images(0).placement(0).?;
    try std.testing.expectEqual(@as(u16, 1), placement.row);
    try std.testing.expectEqual(@as(u16, 1), placement.col);
}

test "terminal: Kitty Unicode placeholders project invisible virtual placements" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 3, 8, 8);
    defer terminal.deinit();
    try terminal.setCellPixelSize(10, 20);

    const prototype = try terminal.feed(
        "\x1b_Ga=T,f=32,s=2,v=1,i=42,c=2,r=1,U=1,q=2;AQAA/wIAAP8=\x1b\\",
    );
    try std.testing.expect(prototype.stateChanged());
    var images = terminal.images(0);
    try std.testing.expectEqual(@as(usize, 1), images.imageCount());
    try std.testing.expectEqual(@as(usize, 1), images.placementCount());
    try std.testing.expect(images.placement(0) == null);
    try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_col);

    // Image id 42 is encoded in indexed foreground color. The first cell
    // explicitly names row/column zero; the second omits its column diacritic,
    // inheriting the next column from the previous placeholder in the run.
    try std.testing.expect((try terminal.feed(
        "\x1b[38;5;42m" ++
            "\xf4\x8e\xbb\xae\xcc\x85\xcc\x85" ++
            "\xf4\x8e\xbb\xae\xcc\x85" ++
            "\x1b[0m",
    )).stateChanged());
    images = terminal.images(0);
    try std.testing.expectEqual(@as(usize, 2), images.placementCount());
    try std.testing.expect(images.placement(0) == null);
    const placed = images.placement(1) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u32, 1), placed.image_id);
    try std.testing.expectEqual(@as(u16, 0), placed.row);
    try std.testing.expectEqual(@as(u16, 0), placed.col);
    try std.testing.expectEqual(@as(u32, 0), placed.source_x);
    try std.testing.expectEqual(@as(u32, 0), placed.source_y);
    try std.testing.expectEqual(@as(u32, 2), placed.source_width);
    try std.testing.expectEqual(@as(u32, 1), placed.source_height);
    try std.testing.expectEqual(@as(u32, 20), placed.pixel_width);
    try std.testing.expectEqual(@as(u32, 5), placed.cell_y);
    try std.testing.expectEqual(@as(u32, 10), placed.pixel_height);
    try std.testing.expectEqual(@as(i32, -1), placed.z);

    // Erasing the text removes the projected cell image without mutating the
    // retained virtual prototype or decoded image.
    try std.testing.expect((try terminal.feed("\x1b[1;1H\x1b[2K")).stateChanged());
    images = terminal.images(0);
    try std.testing.expectEqual(@as(usize, 1), images.imageCount());
    try std.testing.expectEqual(@as(usize, 1), images.placementCount());
    try std.testing.expect(images.placement(0) == null);
}

test "terminal: DEC selective EL preserves protected placeholder and retires unprotected projection" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    try terminal.setCellPixelSize(10, 20);
    const placeholder = "\xf4\x8e\xbb\xae\xcc\x85\xcc\x85";
    const virtual_image = "\x1b_Ga=T,f=32,s=1,v=1,i=42,U=1,C=1,q=2;AQIDBA==\x1b\\";
    const physical_image = "\x1b[2;5H\x1b_Ga=T,f=32,s=1,v=1,i=74,C=1,q=2;AQIDBA==\x1b\\";
    try feed(&terminal, virtual_image ++ physical_image);
    try feed(&terminal, "\x1b[1;1H\x1b[1\"q\x1b[38;5;42m" ++ placeholder ++
        "\x1b[2\"q\x1b[1;3H" ++ placeholder ++ "\x1b[0m");
    try consumeReplies(&terminal);
    try std.testing.expectEqual(@as(usize, 2), terminal.images(0).imageCount());
    try std.testing.expect(terminal.semanticView(0).cellInfoAt(0, 0).attrs.protected == .dec);
    try std.testing.expect(terminal.semanticView(0).cellInfoAt(0, 2).attrs.protected == .none);

    var before = terminal.images(0).placementIterator();
    var initial_count: usize = 0;
    while (before.next()) |_| initial_count += 1;
    try std.testing.expectEqual(@as(usize, 3), initial_count);
    const data_generation = terminal.images(0).content_generation;

    try feed(&terminal, "\x1b[1;1H\x1b[?2K");
    try std.testing.expectEqual(@as(u21, 0x10EEEE), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(0, 2));
    try std.testing.expectEqual(@as(usize, 2), terminal.images(0).imageCount());
    try std.testing.expectEqual(data_generation, terminal.images(0).content_generation);
    var after = terminal.images(0).placementIterator();
    var retained_protected = false;
    var retained_physical = false;
    var erased_unprotected = true;
    while (after.next()) |entry| {
        if (entry.placement.row == 0 and entry.placement.col == 0) retained_protected = true;
        if (entry.placement.row == 1 and entry.placement.col == 4) retained_physical = true;
        if (entry.placement.row == 0 and entry.placement.col == 2) erased_unprotected = false;
    }
    try std.testing.expect(retained_protected);
    try std.testing.expect(retained_physical);
    try std.testing.expect(erased_unprotected);
}

test "terminal: DEC selective ED clears placeholder projection without erasing unrelated physical images" {
    const cases = [_]struct {
        command: []const u8,
        cursor: []const u8,
        physical_retained: bool,
    }{
        .{ .command = "\x1b[?0J", .cursor = "\x1b[1;1H", .physical_retained = true },
        .{ .command = "\x1b[?1J", .cursor = "\x1b[2;1H", .physical_retained = true },
        .{ .command = "\x1b[?2J", .cursor = "\x1b[2;1H", .physical_retained = false },
    };
    for (cases) |case| {
        var terminal = try Terminal.init(std.testing.allocator, 3, 8);
        defer terminal.deinit();
        try terminal.setCellPixelSize(10, 20);
        try feed(&terminal, "\x1b_Ga=T,f=32,s=1,v=1,i=42,U=1,C=1,q=2;AQIDBA==\x1b\\" ++
            "\x1b[1;5H\x1b_Ga=T,f=32,s=1,v=1,i=75,C=1,q=2;AQIDBA==\x1b\\" ++
            "\x1b[1;1H\x1b[38;5;42m\xf4\x8e\xbb\xae\xcc\x85\xcc\x85\x1b[0m");
        try consumeReplies(&terminal);
        const before = terminal.images(0);
        try std.testing.expectEqual(@as(usize, 2), before.imageCount());
        var projected_before = before.placementIterator();
        var visible_count: usize = 0;
        while (projected_before.next()) |_| visible_count += 1;
        try std.testing.expectEqual(@as(usize, 2), visible_count);

        try feed(&terminal, case.cursor);
        try std.testing.expect((try terminal.feed(case.command)).stateChanged());
        try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(0, 0));
        const after = terminal.images(0);
        try std.testing.expectEqual(@as(usize, 2), after.imageCount());
        try std.testing.expectEqual(before.content_generation, after.content_generation);
        var projected_after = after.placementIterator();
        var remaining: usize = 0;
        while (projected_after.next()) |entry| {
            try std.testing.expect(case.physical_retained);
            try std.testing.expectEqual(@as(u16, 0), entry.placement.row);
            try std.testing.expectEqual(@as(u16, 4), entry.placement.col);
            remaining += 1;
        }
        try std.testing.expectEqual(@as(usize, if (case.physical_retained) 1 else 0), remaining);
    }
}

test "terminal: selective ED retains DEC-protected projected image and retires only unprotected placeholder" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    try terminal.setCellPixelSize(10, 20);
    const placeholder = "\xf4\x8e\xbb\xae\xcc\x85\xcc\x85";
    try feed(&terminal, "\x1b_Ga=T,f=32,s=1,v=1,i=42,U=1,C=1,q=2;AQIDBA==\x1b\\" ++
        "\x1b[1;1H\x1b[1\"q\x1b[38;5;42m" ++ placeholder ++
        "\x1b[2\"q\x1b[1;3H" ++ placeholder ++ "\x1b[0m");
    try consumeReplies(&terminal);
    const image_generation = terminal.images(0).content_generation;
    var initial = terminal.images(0).placementIterator();
    try std.testing.expect(initial.next() != null);
    try std.testing.expect(initial.next() != null);
    try std.testing.expect(initial.next() == null);

    try feed(&terminal, "\x1b[1;1H");
    try std.testing.expect((try terminal.feed("\x1b[?0J")).stateChanged());
    try std.testing.expectEqual(@as(u21, 0x10EEEE), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expect(terminal.semanticView(0).cellInfoAt(0, 0).attrs.protected == .dec);
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(0, 2));
    const images = terminal.images(0);
    try std.testing.expectEqual(@as(usize, 1), images.imageCount());
    try std.testing.expectEqual(image_generation, images.content_generation);
    var remaining = images.placementIterator();
    const protected_image = remaining.next() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u16, 0), protected_image.placement.row);
    try std.testing.expectEqual(@as(u16, 0), protected_image.placement.col);
    try std.testing.expect(remaining.next() == null);
}

test "terminal: Kitty Unicode placeholders select placement id and high image byte" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    try terminal.setCellPixelSize(10, 20);

    try std.testing.expect((try terminal.feed(
        "\x1b_Ga=t,f=32,s=2,v=1,i=42,q=2;AQAA/wIAAP8=\x1b\\" ++
            "\x1b_Ga=p,i=42,p=1,c=2,r=1,U=1,q=2\x1b\\" ++
            "\x1b_Ga=p,i=42,p=22,c=1,r=1,U=1,q=2\x1b\\",
    )).stateChanged());
    // Underline indexed color 22 selects the 1x1-box virtual prototype rather
    // than the first/default 2x1 prototype.
    try std.testing.expect((try terminal.feed(
        "\x1b[38;5;42;58;5;22m" ++
            "\xf4\x8e\xbb\xae\xcc\x85\xcc\x85" ++
            "\x1b[0m",
    )).stateChanged());
    var images = terminal.images(0);
    const selected = images.placement(2) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u32, 2), selected.source_width);
    try std.testing.expect(selected.cell_y >= 7);
    try std.testing.expectEqual(@as(u32, 10), selected.pixel_width);

    try std.testing.expect((try terminal.feed("\x1b[1;1H\x1b[2K")).stateChanged());
    try std.testing.expect((try terminal.feed(
        "\x1b_Ga=T,f=32,s=1,v=1,i=704643115,c=1,r=1,U=1,C=1,q=2;CQoLDA==\x1b\\" ++
            "\x1b[38;2;0;0;43m" ++
            "\xf4\x8e\xbb\xae\xcc\x85\xcc\x85\xd6\x9c" ++
            "\x1b[0m",
    )).stateChanged());
    images = terminal.images(0);
    var found_high = false;
    var index: usize = 0;
    while (index < images.placementCount()) : (index += 1) {
        const placement = images.placement(index) orelse continue;
        if (placement.image_id == 2) {
            found_high = true;
            try std.testing.expectEqual(@as(u16, 0), placement.row);
            try std.testing.expectEqual(@as(u16, 0), placement.col);
        }
    }
    try std.testing.expect(found_high);
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
    const before_resize = terminal.images(0);
    const retained_placement = before_resize.placement(1) orelse
        return error.MissingImagePlacement;
    const graphics_generation = before_resize.generation;
    const content_generation = before_resize.content_generation;
    var discarded = try terminal.prepareResize(4, 5);
    discarded.deinit();
    try std.testing.expectEqualDeep(
        retained_placement,
        terminal.images(0).placement(1) orelse return error.MissingImagePlacement,
    );
    var committed = try terminal.prepareResize(4, 5);
    defer committed.deinit();
    committed.commit();
    const resized = terminal.images(0);
    try std.testing.expectEqual(@as(usize, 1), resized.imageCount());
    try std.testing.expect(terminal.images(0).placement(0) == null);
    try std.testing.expectEqualDeep(
        retained_placement,
        resized.placement(1) orelse return error.MissingImagePlacement,
    );
    try std.testing.expectEqual(graphics_generation, resized.generation);
    try std.testing.expectEqual(content_generation, resized.content_generation);
    terminal.hardReset();
    try std.testing.expectEqual(@as(usize, 0), terminal.images(0).imageCount());
}

test "terminal: resize clips only graphics anchors outside replacement bounds" {
    var terminal = try Terminal.init(std.testing.allocator, 4, 5);
    defer terminal.deinit();
    try terminal.setCellPixelSize(1, 1);
    try std.testing.expect((try terminal.feed(
        "\x1b[4;5H\x1b_Ga=T,f=32,s=1,v=1,i=7,C=1;AQIDBA==\x1b\\",
    )).stateChanged());
    const before = terminal.images(0);
    try std.testing.expectEqual(@as(usize, 1), before.imageCount());
    try std.testing.expect(before.placement(0) != null);
    const content_generation = before.content_generation;
    const graphics_generation = before.generation;

    try terminal.resize(2, 3);
    const after = terminal.images(0);
    try std.testing.expectEqual(@as(usize, 1), after.imageCount());
    try std.testing.expectEqual(@as(usize, 0), after.placementCount());
    try std.testing.expectEqual(content_generation, after.content_generation);
    try std.testing.expect(after.generation > graphics_generation);
}

test "terminal: Sixel discard without cell geometry releases decoded pixels" {
    var terminal = try Terminal.init(std.testing.allocator, 8, 12);
    defer terminal.deinit();
    const packet = "\x1bP7;1q~\x1b\\";
    const before = terminal.images(0).generation;
    try std.testing.expect(!(try terminal.feed(packet)).stateChanged());
    try std.testing.expectEqual(@as(usize, 0), terminal.images(0).imageCount());
    try std.testing.expectEqual(before, terminal.images(0).generation);
    try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_col);

    try terminal.setCellPixelSize(1, 1);
    try std.testing.expect((try terminal.feed(packet)).stateChanged());
    try std.testing.expectEqual(@as(usize, 1), terminal.images(0).imageCount());
}

test "terminal: Sixel discard at full plane releases decoded pixels" {
    var terminal = try Terminal.init(std.testing.allocator, 8, 12);
    defer terminal.deinit();
    try terminal.setCellPixelSize(1, 1);
    try feed(&terminal, "\x1b[?80h");
    const packet = "\x1bP7;1q~\x1b\\";
    const capacity = @import("../../src/graphics.zig").max_images;
    for (0..capacity) |_| try std.testing.expect((try terminal.feed(packet)).stateChanged());
    const before = terminal.images(0);
    try std.testing.expectEqual(capacity, before.imageCount());
    try std.testing.expectEqual(capacity, before.placementCount());

    try std.testing.expect(!(try terminal.feed(packet)).stateChanged());
    const after = terminal.images(0);
    try std.testing.expectEqual(before.generation, after.generation);
    try std.testing.expectEqual(before.content_generation, after.content_generation);
    try std.testing.expectEqual(capacity, after.imageCount());
    try std.testing.expectEqual(capacity, after.placementCount());
    try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_col);

    terminal.hardReset();
    try terminal.setCellPixelSize(1, 1);
    try std.testing.expect((try terminal.feed(packet)).stateChanged());
    try std.testing.expectEqual(@as(usize, 1), terminal.images(0).imageCount());
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

test "terminal: bulk APC preserves every Yazi fragment and exact service boundary" {
    const packet = "\x1b_Gq=2,a=T,z=-1,C=1,f=24,s=2,v=1,m=1;/wAA\x1b\\" ++
        "\x1b_Gm=0;AP8A\x1b\\";
    const bytes = packet ++ "\x07\x1b[6nTAIL";
    for (0..packet.len + 1) |split| {
        var terminal = try Terminal.init(std.testing.allocator, 3, 8);
        defer terminal.deinit();
        const prefix = try terminal.feedAt(bytes[0..split], 1);
        try std.testing.expect(!prefix.historyLost());
        const until_bell = try terminal.feedAtServiceBoundary(bytes[split..], 2);
        try std.testing.expectEqual(packet.len + 1 - split, until_bell.consumed);
        try std.testing.expectEqual(@as(u16, 1), terminal.consequenceCount());
        const bell = terminal.consequenceHead().?;
        try std.testing.expect(bell == .bell);
        try terminal.consumeConsequence(bell.id());
        const images = terminal.images(0);
        try std.testing.expectEqual(@as(usize, 1), images.imageCount());
        try std.testing.expectEqual(@as(usize, 1), images.placementCount());
        try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255, 0, 255, 0, 255 }, images.image(0).?.pixels);
        try std.testing.expectEqual(@as(i32, -1), images.placement(0).?.z);
        try std.testing.expectEqualStrings("", terminal.replyBytes());
        const query_offset = split + until_bell.consumed;
        const until_reply = try terminal.feedAtServiceBoundary(bytes[query_offset..], 3);
        try std.testing.expectEqual(@as(usize, 4), until_reply.consumed);
        try std.testing.expectEqualStrings("\x1b[1;1R", terminal.replyBytes());
        try consumeReplies(&terminal);
        const tail = try terminal.feedAtServiceBoundary(bytes[query_offset + until_reply.consumed ..], 4);
        try std.testing.expectEqual(@as(usize, 4), tail.consumed);
        try std.testing.expectEqual(@as(u21, 'T'), terminal.semanticView(0).cellAt(0, 0));
        try std.testing.expectEqual(@as(u21, 'L'), terminal.semanticView(0).cellAt(0, 3));
    }
}

test "terminal: failed bulk APC allocation resets capture and accepts ordinary text" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var terminal = try Terminal.init(failing.allocator(), 3, 8);
    defer terminal.deinit();
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, terminal.feed("\x1b_Gq=2,a=T,f=24,s=1,v=1;/wAA\x1b\\"));
    failing.fail_index = std.math.maxInt(usize);
    try feed(&terminal, "R");
    try std.testing.expectEqual(@as(u21, 'R'), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(usize, 0), terminal.images(0).imageCount());
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
}

test "terminal: VS16 rewrites a previously occupied neighbor" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();

    // Ordinary progress output may rewrite an existing row. The warning
    // symbol grows from one cell to two when its selector arrives later.
    try feed(&terminal, "  \r\u{26a0}");
    try feed(&terminal, "\u{fe0f}X");

    const view = terminal.semanticView(0);
    const lead = view.cellInfoAt(0, 0);
    const continuation = view.cellInfoAt(0, 1);
    try std.testing.expectEqual(@as(u32, 0x26a0), lead.codepoint);
    try std.testing.expectEqual(@as(u8, 2), lead.width);
    try std.testing.expect(lead.semantic_width);
    try std.testing.expectEqual(@as(u8, 2), continuation.width);
    try std.testing.expectEqual(@as(u8, 1), continuation.x);
    try std.testing.expectEqual(@as(u21, 'X'), view.cellAt(0, 2));
    try std.testing.expectEqual(@as(u16, 3), view.cursor_col);
}

test "terminal: wide printing boundaries preserve margins and physical rows through reflow" {
    const cases = [_]struct {
        primer: []const u8,
        bytes: []const u8,
        scalars: []const u21,
    }{
        .{ .primer = "", .bytes = "\u{754c}", .scalars = &.{0x754c} },
        .{ .primer = "\x1b[1;2H\u{754c}\u{301}", .bytes = "\x1b[b", .scalars = &.{ 0x754c, 0x301 } },
        .{ .primer = "", .bytes = "\u{263a}\u{fe0f}", .scalars = &.{ 0x263a, 0xfe0f } },
    };
    for (cases) |case| {
        for ([_]bool{ true, false }) |auto_wrap| {
            for ([_]u16{ 6, 7 }) |start_col| {
                var terminal = try Terminal.initWithHistory(std.testing.allocator, 3, 8, 2);
                defer terminal.deinit();
                try feed(&terminal, "\x1b[3;1HZ\x1b[?69h\x1b[2;7s");
                if (!auto_wrap) try feed(&terminal, "\x1b[?7l");
                try feed(&terminal, case.primer);
                try feed(&terminal, if (start_col == 6) "\x1b[2;7H" else "\x1b[2;8H");
                try std.testing.expect((try terminal.feed(case.bytes)).stateChanged());

                const view = terminal.semanticView(0);
                const row: u16 = if (auto_wrap) 2 else 1;
                const col: u16 = if (auto_wrap) 1 else start_col - 1;
                const lead = view.cellInfoAt(row, col);
                const continuation = view.cellInfoAt(row, col + 1);
                try std.testing.expectEqual(@as(u21, 'Z'), view.cellAt(2, 0));
                try std.testing.expectEqual(@as(u32, case.scalars[0]), lead.codepoint);
                try std.testing.expectEqual(@as(u8, 2), lead.width);
                try std.testing.expect(lead.semantic_width);
                try std.testing.expectEqual(@as(u8, 0), lead.x);
                try std.testing.expectEqual(@as(u8, 2), continuation.width);
                try std.testing.expect(continuation.semantic_width);
                try std.testing.expectEqual(@as(u8, 1), continuation.x);
                var scalars: [24]u21 = undefined;
                try std.testing.expectEqualSlices(u21, case.scalars, view.cellScalarsAt(row, col, &scalars));
                try std.testing.expectEqual(row, view.cursor_row);
                try std.testing.expectEqual(if (auto_wrap) @as(u16, 3) else start_col, view.cursor_col);

                try terminal.resize(3, 9);
                const resized = terminal.semanticView(0);
                var leads: usize = 0;
                for (0..resized.rows) |r| {
                    for (0..resized.cols) |c| {
                        const cell = resized.cellInfoAt(@intCast(r), @intCast(c));
                        if (!cell.semantic_width) continue;
                        try std.testing.expectEqual(@as(u8, 2), cell.width);
                        if (cell.x == 0) {
                            leads += 1;
                            try std.testing.expect(c + 1 < resized.cols);
                            const tail = resized.cellInfoAt(@intCast(r), @intCast(c + 1));
                            try std.testing.expect(tail.semantic_width);
                            try std.testing.expectEqual(@as(u8, 1), tail.x);
                            try std.testing.expectEqual(@as(u8, 2), tail.width);
                        } else {
                            try std.testing.expectEqual(@as(u8, 1), cell.x);
                            try std.testing.expect(c > 0);
                            const head = resized.cellInfoAt(@intCast(r), @intCast(c - 1));
                            try std.testing.expect(head.semantic_width);
                            try std.testing.expectEqual(@as(u8, 0), head.x);
                        }
                    }
                }
                try std.testing.expectEqual(if (case.primer.len == 0) @as(usize, 1) else 2, leads);
            }
        }
    }
}

test "terminal: wide printing boundaries keep text beyond the right margin in place" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 3, 10, 2);
    defer terminal.deinit();
    try feed(&terminal, "\x1b[?69h\x1b[2;7s\x1b[2;8H\u{754c}X");
    const view = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u21, 0x754c), view.cellAt(1, 7));
    try std.testing.expectEqual(@as(u8, 1), view.cellInfoAt(1, 8).x);
    try std.testing.expectEqual(@as(u21, 'X'), view.cellAt(1, 9));
    try std.testing.expectEqual(@as(u21, 0), view.cellAt(1, 6));
    try std.testing.expectEqual(@as(u16, 9), view.cursor_col);
    try feed(&terminal, "Y");
    try std.testing.expectEqual(@as(u21, 'Y'), terminal.semanticView(0).cellAt(2, 1));
}

test "terminal: wide printing boundaries reject REP on a one-column row" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 4);
    defer terminal.deinit();
    try feed(&terminal, "\u{754c}");
    try terminal.resize(2, 1);
    const before = terminal.semanticView(0).cellInfoAt(0, 0);
    const sequence = terminal.semanticSequence();
    try std.testing.expect(!(try terminal.feed("\x1b[b")).stateChanged());
    try std.testing.expectEqual(sequence, terminal.semanticSequence());
    try std.testing.expectEqualDeep(before, terminal.semanticView(0).cellInfoAt(0, 0));
}

test "terminal: pinned Kitty SU SD reject excess counts and preserve zero as a no-op" {
    // Pinned Kitty d4106ef vt-parser.c calls AT_MOST_ONE_PARAMETER for
    // ordinary S and T; screen_scroll and screen_reverse_scroll each loop
    // over the explicit count, so zero does no work. CSI + T retains its
    // separate history-restoring owner and private CSI ? S is a SIXEL query.
    const image = "\x1b_Ga=T,f=32,s=1,v=1,i=94,C=1;AQIDBA==\x1b\\";
    for ([_]struct { malformed: []const u8, valid: []const u8 }{
        .{ .malformed = "\x1b[2;1S", .valid = "\x1b[S" },
        .{ .malformed = "\x1b[2;1T", .valid = "\x1b[T" },
        .{ .malformed = "\x1b[1;2S", .valid = "\x1b[S" },
        .{ .malformed = "\x1b[1;2T", .valid = "\x1b[T" },
        .{ .malformed = "\x1b[0;;S", .valid = "\x1b[S" },
        .{ .malformed = "\x1b[0;;T", .valid = "\x1b[T" },
        .{ .malformed = "\x1b[2:1S", .valid = "\x1b[S" },
        .{ .malformed = "\x1b[2:1T", .valid = "\x1b[T" },
        .{ .malformed = "\x9b2;1S", .valid = "\x1b[S" },
        .{ .malformed = "\x9b2;1T", .valid = "\x1b[T" },
        .{ .malformed = "\x1b[;0;S", .valid = "\x1b[S" },
        .{ .malformed = "\x1b[;0;T", .valid = "\x1b[T" },
    }) |case| {
        var terminal = try Terminal.initWithHistory(std.testing.allocator, 4, 8, 4);
        defer terminal.deinit();
        try terminal.setCellPixelSize(1, 1);
        try feed(&terminal, "\x1b[1;1HAAAAAAAA\x1b[2;1HBBBBBBBB\x1b[3;1HCCCCCCCC\x1b[4;1HDDDDDDDD\x1b[2;2H");
        try feed(&terminal, image);
        try consumeReplies(&terminal);
        const before = terminal.semanticView(0);
        const baseline_cells = [_]@TypeOf(before.cellInfoAt(0, 0)){
            before.cellInfoAt(0, 0),
            before.cellInfoAt(1, 0),
            before.cellInfoAt(2, 0),
            before.cellInfoAt(3, 0),
        };
        const sequence = terminal.semanticSequence();
        const history = before.history_count;
        const edit_generation = terminal.observation().structuralEditGeneration();
        const imgs = terminal.images(0);
        const placements = imgs.placementCount();
        try std.testing.expectEqual(@as(usize, 1), placements);
        const position = imgs.placement(0).?;
        const img_generation = imgs.generation;
        const content_generation = imgs.content_generation;

        try std.testing.expect(!(try terminal.feed(case.malformed[0 .. case.malformed.len - 1])).stateChanged());
        try std.testing.expect(!(try terminal.feed(case.malformed[case.malformed.len - 1 ..])).stateChanged());
        const after = terminal.semanticView(0);
        try std.testing.expectEqual(sequence, terminal.semanticSequence());
        try std.testing.expectEqual(history, after.history_count);
        try std.testing.expectEqual(edit_generation, terminal.observation().structuralEditGeneration());
        try std.testing.expectEqual(before.cursor_row, after.cursor_row);
        try std.testing.expectEqual(before.cursor_col, after.cursor_col);
        for (baseline_cells, 0..) |cell, row| {
            try std.testing.expectEqualDeep(cell, after.cellInfoAt(@intCast(row), 0));
        }
        try std.testing.expectEqual(placements, terminal.images(0).placementCount());
        try std.testing.expectEqual(position.row, terminal.images(0).placement(0).?.row);
        try std.testing.expectEqual(position.col, terminal.images(0).placement(0).?.col);
        try std.testing.expectEqual(img_generation, terminal.images(0).generation);
        try std.testing.expectEqual(content_generation, terminal.images(0).content_generation);
        try std.testing.expectEqualStrings("", terminal.replyBytes());

        // Invalid scrolling cannot poison an adjacent valid command.
        try std.testing.expect((try terminal.feed(case.valid)).stateChanged());
        try std.testing.expectEqual(before.cursor_row, terminal.semanticView(0).cursor_row);
        try std.testing.expectEqual(before.cursor_col, terminal.semanticView(0).cursor_col);
    }

    // Valid trailing semicolon leaves one operand, but explicit zero must
    // not erase content, scroll history, move graphics or cancel the cursor.
    for ([_][]const u8{
        "\x1b[0S", "\x1b[0T", "\x1b[0;S", "\x1b[0;T",
        "\x1b[;S", "\x1b[;T", "\x9b0S",   "\x9b0T",
    }) |zero| {
        var terminal = try Terminal.initWithHistory(std.testing.allocator, 4, 8, 4);
        defer terminal.deinit();
        try terminal.setCellPixelSize(1, 1);
        try feed(&terminal, "\x1b[1;1HAAAA\x1b[2;1HBBBB\x1b[3;1HCCCC\x1b[4;1HDDDD\x1b[2;2H");
        try feed(&terminal, image);
        try consumeReplies(&terminal);
        const before = terminal.semanticView(0);
        const cell = before.cellInfoAt(1, 0);
        const sequence = terminal.semanticSequence();
        const placement = terminal.images(0).placement(0).?;
        const image_generation = terminal.images(0).generation;
        try std.testing.expect(!(try terminal.feed(zero)).stateChanged());
        const after = terminal.semanticView(0);
        try std.testing.expectEqual(sequence, terminal.semanticSequence());
        try std.testing.expectEqual(before.history_count, after.history_count);
        try std.testing.expectEqualDeep(cell, after.cellInfoAt(1, 0));
        try std.testing.expectEqual(before.cursor_row, after.cursor_row);
        try std.testing.expectEqual(before.cursor_col, after.cursor_col);
        try std.testing.expectEqual(placement.row, terminal.images(0).placement(0).?.row);
        try std.testing.expectEqual(image_generation, terminal.images(0).generation);
        try std.testing.expectEqualStrings("", terminal.replyBytes());
    }

    // Missing count and positive single count are still supported.
    for ([_][]const u8{
        "\x1b[S",   "\x1b[T",   "\x1b[1S", "\x1b[1T",
        "\x1b[1;S", "\x1b[1;T",
    }) |valid| {
        var terminal = try Terminal.init(std.testing.allocator, 3, 8);
        defer terminal.deinit();
        try feed(&terminal, "\x1b[1;1HAAAA\x1b[2;1HBBBB\x1b[3;1HCCCC\x1b[2;2H");
        const before = terminal.semanticView(0);
        try std.testing.expect((try terminal.feed(valid)).stateChanged());
        try std.testing.expectEqual(before.cursor_row, terminal.semanticView(0).cursor_row);
        try std.testing.expectEqual(before.cursor_col, terminal.semanticView(0).cursor_col);
    }
}

test "terminal: Kitty CSI plus T rejects extra operands and honors zero count" {
    const image = "\x1b_Ga=T,f=32,s=1,v=1,i=98,C=1;AQIDBA==\x1b\\";
    const malformed = [_][]const u8{
        "\x1b[2;3+T",
        "\x1b[1;2;3+T",
        "\x1b[;3+T",
        "\x1b[0+T",
        "\x1b[1#T",
        "\x1b[1+A",
    };
    for (malformed) |bytes| {
        var terminal = try Terminal.init(std.testing.allocator, 3, 8);
        defer terminal.deinit();
        try terminal.setCellPixelSize(1, 1);
        try feed(&terminal, "\x1b[1;1H" ++ image);
        try consumeReplies(&terminal);
        const pixel_generation = terminal.images(0).content_generation;
        const baseline = terminal.semanticView(0).cellInfoAt(0, 0);
        try std.testing.expect(!(try terminal.feed(bytes)).stateChanged());
        try std.testing.expectEqual(@as(u16, 0), terminal.images(0).placement(0).?.row);
        try std.testing.expectEqual(pixel_generation, terminal.images(0).content_generation);
        try std.testing.expectEqualDeep(baseline, terminal.semanticView(0).cellInfoAt(0, 0));
    }

    // Kitty permits one explicit positive operand and default-one on a
    // missing operand, with normal clipping of the admitted scroll extent.
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    try terminal.setCellPixelSize(1, 1);
    try feed(&terminal, "\x1b[1;1H" ++ image);
    try consumeReplies(&terminal);
    try std.testing.expect(!(try terminal.feed("\x1b[2;")).stateChanged());
    try std.testing.expect(!(try terminal.feed("3+T")).stateChanged());
    try std.testing.expectEqual(@as(u16, 0), terminal.images(0).placement(0).?.row);
    try feed(&terminal, "\x1b[+T");
    try std.testing.expectEqual(@as(u16, 1), terminal.images(0).placement(0).?.row);
    try feed(&terminal, "\x1b[1+T");
    try std.testing.expectEqual(@as(u16, 2), terminal.images(0).placement(0).?.row);
}

test "terminal: Kitty CSI plus T moves graphics after retained history runs out" {
    const image = "\x1b_Ga=T,f=32,s=1,v=1,i=97,C=1;AQIDBA==\x1b\\";
    for ([_]u16{ 0, 4 }) |history_capacity| {
        var terminal = try Terminal.initWithHistory(std.testing.allocator, 3, 8, history_capacity);
        defer terminal.deinit();
        try terminal.setCellPixelSize(1, 1);
        try feed(&terminal, "\x1b[1;1H" ++ image);
        try consumeReplies(&terminal);
        const image_data_generation = terminal.images(0).content_generation;
        try std.testing.expectEqual(@as(u16, 0), terminal.images(0).placement(0).?.row);

        if (history_capacity != 0) {
            // The image belongs to the newest projected history row after
            // the full-screen LF and is expected to return by absolute origin.
            try feed(&terminal, "\x1b[3;1H\n");
            try std.testing.expectEqual(@as(u32, 1), terminal.semanticView(0).history_count);
            try std.testing.expect(terminal.images(0).placement(0) == null);
            try std.testing.expectEqual(@as(u16, 0), terminal.images(1).placement(0).?.row);
        }

        // With one retained row, the first +T consumes history and the
        // second +T is a plain downward scroll. With no history both moves
        // are ordinary downward scrolls.
        try feed(&terminal, "\x1b[2+T");
        try std.testing.expectEqual(@as(u16, if (history_capacity != 0) 1 else 2), terminal.images(0).placement(0).?.row);
        try std.testing.expectEqual(@as(u32, 0), terminal.semanticView(0).history_count);
        try std.testing.expectEqual(image_data_generation, terminal.images(0).content_generation);
    }
}

test "terminal: Kitty CSI plus T preserves graphics outside the vertical margin" {
    var terminal = try Terminal.init(std.testing.allocator, 4, 8);
    defer terminal.deinit();
    try terminal.setCellPixelSize(1, 1);
    const image = "\x1b_Ga=T,f=32,s=1,v=1,C=1,q=2;AQIDBA==\x1b\\";
    try feed(&terminal, "\x1b[1;1H" ++ image ++ "\x1b[2;1H" ++ image);
    try consumeReplies(&terminal);
    try std.testing.expectEqual(@as(u16, 0), terminal.images(0).placement(0).?.row);
    try std.testing.expectEqual(@as(u16, 1), terminal.images(0).placement(1).?.row);
    const pixels = terminal.images(0).content_generation;

    try feed(&terminal, "\x1b[2;4r\x1b[+T");
    try std.testing.expectEqual(@as(u16, 0), terminal.images(0).placement(0).?.row);
    try std.testing.expectEqual(@as(u16, 2), terminal.images(0).placement(1).?.row);
    try std.testing.expectEqual(pixels, terminal.images(0).content_generation);
}

test "terminal: Kitty CSI plus T moves alternate graphics without consuming primary history" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 3, 8, 4);
    defer terminal.deinit();
    try terminal.setCellPixelSize(1, 1);
    try feed(&terminal, "\x1b[3;1H\n");
    try std.testing.expectEqual(@as(u32, 1), terminal.semanticView(0).history_count);
    try feed(&terminal, "\x1b[?1049h\x1b[2;1H\x1b_Ga=T,f=32,s=1,v=1,i=98,C=1;AQIDBA==\x1b\\");
    try consumeReplies(&terminal);
    try std.testing.expectEqual(@as(u16, 1), terminal.images(0).placement(0).?.row);
    try feed(&terminal, "\x1b[+T");
    try std.testing.expectEqual(@as(u16, 2), terminal.images(0).placement(0).?.row);
    try feed(&terminal, "\x1b[?1049l");
    try std.testing.expectEqual(@as(u32, 1), terminal.semanticView(0).history_count);
}

test "terminal: bulk and sequential scrolling retain identical graphics" {
    var bulk = try Terminal.initWithHistory(std.testing.allocator, 3, 8, 8);
    defer bulk.deinit();
    var single = try Terminal.initWithHistory(std.testing.allocator, 3, 8, 8);
    defer single.deinit();
    const init = "\x1b[2;1H\x1b_Ga=T,f=32,s=1,v=1,i=7,C=1;AQIDBA==\x1b\\";
    for ([_]*Terminal{ &bulk, &single }) |terminal| {
        try terminal.setCellPixelSize(1, 1);
        try feed(terminal, init);
        try std.testing.expect(terminal.images(0).placement(0) != null);
    }
    try feed(&bulk, "\x1b[2S");
    try feed(&single, "\x1b[S\x1b[S");
    for ([_]u16{ 0, 1, 2 }) |offset| {
        try std.testing.expectEqualDeep(bulk.images(offset).placement(0), single.images(offset).placement(0));
    }
    // The image started on the second row, which is now the second history row.
    try std.testing.expectEqual(@as(u16, 0), bulk.images(1).placement(0).?.row);
}

test "terminal: graphics scrolls without history and evicts with bounded history" {
    const init = "\x1b[2;1H\x1b_Ga=T,f=32,s=1,v=1,i=7,C=1;AQIDBA==\x1b\\";
    var no_history = try Terminal.init(std.testing.allocator, 3, 8);
    defer no_history.deinit();
    try no_history.setCellPixelSize(1, 1);
    try feed(&no_history, init);
    try feed(&no_history, "\x1b[S");
    try std.testing.expectEqual(@as(u16, 0), no_history.images(0).placement(0).?.row);
    try feed(&no_history, "\x1b[S");
    try std.testing.expect(no_history.images(0).placement(0) == null);

    var limited = try Terminal.initWithHistory(std.testing.allocator, 3, 8, 1);
    defer limited.deinit();
    try limited.setCellPixelSize(1, 1);
    try feed(&limited, init);
    try feed(&limited, "\x1b[2S");
    try std.testing.expectEqual(@as(u16, 0), limited.images(1).placement(0).?.row);
    try feed(&limited, "\x1b[S");
    try std.testing.expect(limited.images(1).placement(0) == null);
}

test "terminal: partial top scroll retains same images for bulk and single rows" {
    var bulk = try Terminal.initWithHistory(std.testing.allocator, 4, 8, 8);
    defer bulk.deinit();
    var single = try Terminal.initWithHistory(std.testing.allocator, 4, 8, 8);
    defer single.deinit();
    const init = "\x1b[3;1H\x1b_Ga=T,f=32,s=1,v=1,i=7,C=1;AQIDBA==\x1b\\" ++
        "\x1b[4;1H\x1b_Ga=T,f=32,s=1,v=1,i=8,C=1;AQIDBA==\x1b\\\x1b[1;3r";
    for ([_]*Terminal{ &bulk, &single }) |terminal| {
        try terminal.setCellPixelSize(1, 1);
        try feed(terminal, init);
        try std.testing.expect(terminal.images(0).placement(0) != null);
    }
    try feed(&bulk, "\x1b[2S");
    try feed(&single, "\x1b[S\x1b[S");
    for ([_]u16{ 0, 1, 2 }) |offset| {
        try std.testing.expectEqualDeep(bulk.images(offset).placement(0), single.images(offset).placement(0));
        try std.testing.expectEqualDeep(bulk.images(offset).placement(1), single.images(offset).placement(1));
    }
    try std.testing.expectEqual(@as(u16, 0), bulk.images(0).placement(0).?.row);
    try std.testing.expectEqual(@as(u16, 3), bulk.images(0).placement(1).?.row);
}

test "terminal: top-anchored LF and NEL keep scrolling and fixed graphics aligned" {
    const image = "\x1b_Ga=T,f=32,s=1,v=1,C=1;AQIDBA==\x1b\\";
    for ([_][]const u8{ "\n", "\x1bE" }) |control| {
        var terminal = try Terminal.initWithHistory(std.testing.allocator, 4, 8, 8);
        defer terminal.deinit();
        try terminal.setCellPixelSize(1, 1);
        try feed(&terminal, "\x1b[2;1H" ++ image ++ "\x1b[4;1H" ++ image);
        try consumeReplies(&terminal);
        try std.testing.expectEqual(@as(usize, 2), terminal.images(0).placementCount());
        try std.testing.expectEqual(@as(u16, 1), terminal.images(0).placement(0).?.row);
        try std.testing.expectEqual(@as(u16, 3), terminal.images(0).placement(1).?.row);

        // The top three rows scroll into history; the fourth is a fixed
        // composer. After the second scroll the first image moves into
        // projected history, but the fixed image must remain on row four.
        try feed(&terminal, "\x1b[1;3r\x1b[3;1H");
        try std.testing.expect((try terminal.feed(control)).stateChanged());
        try std.testing.expectEqual(@as(u32, 1), terminal.semanticView(0).history_count);
        try std.testing.expectEqual(@as(u16, 0), terminal.images(0).placement(0).?.row);
        try std.testing.expectEqual(@as(u16, 3), terminal.images(0).placement(1).?.row);

        try std.testing.expect((try terminal.feed(control)).stateChanged());
        try std.testing.expectEqual(@as(u32, 2), terminal.semanticView(0).history_count);
        try std.testing.expect(terminal.images(0).placement(0) == null);
        try std.testing.expectEqual(@as(u16, 0), terminal.images(1).placement(0).?.row);
        try std.testing.expectEqual(@as(u16, 3), terminal.images(0).placement(1).?.row);
        try std.testing.expectEqual(@as(usize, 2), terminal.images(0).imageCount());
    }
}

test "terminal: Kitty geometric deletion distinguishes viewport rows from scrollback columns and layers" {
    // Pinned graphics.c point/y/cursor filters use a 1-based visible
    // screen-row coordinate, while x and z filters inspect all physical
    // references in the active manager, including scrollback.
    const cases = [_]struct { command: []const u8, hit: bool }{
        .{ .command = "\x1b_Ga=d,d=P,x=1,y=1\x1b\\", .hit = false },
        .{ .command = "\x1b_Ga=d,d=Q,x=1,y=1,z=-2\x1b\\", .hit = false },
        .{ .command = "\x1b_Ga=d,d=Y,y=1\x1b\\", .hit = false },
        .{ .command = "\x1b_Ga=d,d=C\x1b\\", .hit = false },
        .{ .command = "\x1b_Ga=d,d=X,x=1\x1b\\", .hit = true },
        .{ .command = "\x1b_Ga=d,d=Z,z=-2\x1b\\", .hit = true },
    };
    for (cases) |case| {
        var terminal = try Terminal.initWithHistory(std.testing.allocator, 2, 4, 8);
        defer terminal.deinit();
        try terminal.setCellPixelSize(1, 1);
        try feed(&terminal, "\x1b[1;1H\x1b_Ga=T,f=32,s=1,v=1,i=41,z=-2,C=1,q=2;AQIDBA==\x1b\\");
        try feed(&terminal, "\x1b[2;1H\n");
        try std.testing.expectEqual(@as(u32, 1), terminal.semanticView(0).history_count);
        try std.testing.expectEqual(@as(usize, 1), terminal.images(0).imageCount());
        try std.testing.expect(terminal.images(0).placement(0) == null);
        try std.testing.expect(terminal.images(1).placement(0) != null);
        const generation = terminal.images(0).generation;
        const bytes_generation = terminal.images(0).content_generation;
        const result = try terminal.feed(case.command);
        try std.testing.expectEqual(case.hit, result.stateChanged());
        const after = terminal.images(0);
        try std.testing.expectEqualStrings("", terminal.replyBytes());
        try std.testing.expectEqual(@as(u32, 1), terminal.semanticView(0).history_count);
        if (case.hit) {
            try std.testing.expect(after.generation > generation);
            try std.testing.expect(after.content_generation > bytes_generation);
            try std.testing.expectEqual(@as(usize, 0), after.imageCount());
            try std.testing.expectEqual(@as(usize, 0), after.placementCount());
        } else {
            try std.testing.expectEqual(generation, after.generation);
            try std.testing.expectEqual(bytes_generation, after.content_generation);
            try std.testing.expectEqual(@as(usize, 1), after.imageCount());
            try std.testing.expect(after.placement(0) == null);
            try std.testing.expect(terminal.images(1).placement(0) != null);
        }
    }
}

test "terminal: Kitty virtual placeholder rows follow pinned margin-scroll projection" {
    // Pinned kitty_tests/graphics.py:test_unicode_placeholders_scroll
    // retains physical image data while only the placeholder cell rows
    // inside margins move. Unit-size cells preserve the exact source-index
    // geometry of the pinned 5x10-cell/5x80-image oracle.
    var terminal = try Terminal.init(std.testing.allocator, 8, 4);
    defer terminal.deinit();
    try terminal.setCellPixelSize(1, 1);
    const prototype = "\x1b_Ga=T,f=32,s=1,v=8,i=42,c=1,r=8,U=1,C=1,q=2;/wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP8=\x1b\\";
    try feed(&terminal, prototype);
    try consumeReplies(&terminal);
    const accents = [_][]const u8{
        "\xcc\x85", "\xcc\x8d", "\xcc\x8e", "\xcc\x90",
        "\xcc\x92", "\xcc\xbd", "\xcc\xbe", "\xcc\xbf",
    };
    try feed(&terminal, "\x1b[38;5;42m");
    for (accents, 0..) |accent, idx| {
        var position: [16]u8 = undefined;
        try feed(&terminal, try std.fmt.bufPrint(&position, "\x1b[{d};1H", .{idx + 1}));
        try feed(&terminal, "\xf4\x8e\xbb\xae");
        try feed(&terminal, accent);
    }
    var prior = terminal.images(0);
    try std.testing.expectEqual(@as(usize, 1), prior.imageCount());
    try std.testing.expectEqual(@as(usize, 9), prior.placementCount());
    const generation = prior.content_generation;
    for (0..8) |row| {
        const image = prior.placement(row + 1) orelse return error.TestUnexpectedResult;
        try std.testing.expectEqual(@as(u16, @intCast(row)), image.row);
        try std.testing.expectEqual(@as(u32, @intCast(row)), image.source_y);
        try std.testing.expectEqual(@as(u32, 1), image.source_height);
    }
    try feed(&terminal, "\x1b[3;6r\x1b[6;1H\x1b[S\x1b[S");
    const after = terminal.images(0);
    try std.testing.expectEqual(@as(usize, 1), after.imageCount());
    try std.testing.expectEqual(generation, after.content_generation);
    try std.testing.expectEqual(@as(usize, 7), after.placementCount());
    const expected_source_rows = [_]u32{ 0, 1, 4, 5, 6, 7 };
    const expected_screen_rows = [_]u16{ 0, 1, 2, 3, 6, 7 };
    for (expected_source_rows, expected_screen_rows, 0..) |src, row, i| {
        const image = after.placement(i + 1) orelse return error.TestUnexpectedResult;
        try std.testing.expectEqual(row, image.row);
        try std.testing.expectEqual(src, image.source_y);
        try std.testing.expectEqual(@as(u32, 1), image.source_height);
    }
}

test "terminal: Kitty margin scroll clips image source and geometric deletion coordinates" {
    const pixels = "\x1b_Ga=T,f=32,s=1,v=2,i=72,C=1,q=2;AQIDBAUGBwg=\x1b\\";
    for ([_]struct { scroll: []const u8, row: u16, source_y: u32, miss: []const u8, hit: []const u8 }{
        .{ .scroll = "\x1b[T", .row = 2, .source_y = 0, .miss = "\x1b_Ga=d,d=y,y=4\x1b\\", .hit = "\x1b_Ga=d,d=y,y=3\x1b\\" },
        .{ .scroll = "\x1b[S", .row = 1, .source_y = 1, .miss = "\x1b_Ga=d,d=y,y=1\x1b\\", .hit = "\x1b_Ga=d,d=y,y=2\x1b\\" },
    }) |case| {
        var terminal = try Terminal.init(std.testing.allocator, 4, 8);
        defer terminal.deinit();
        try terminal.setCellPixelSize(1, 1);
        try feed(&terminal, "\x1b[2;1H");
        try feed(&terminal, pixels);
        try consumeReplies(&terminal);
        try feed(&terminal, "\x1b[2;3r");
        const content_before = terminal.images(0).content_generation;
        try std.testing.expect((try terminal.feed(case.scroll)).stateChanged());
        const image = terminal.images(0);
        try std.testing.expectEqual(@as(usize, 1), image.placementCount());
        const placement = image.placement(0).?;
        try std.testing.expectEqual(case.row, placement.row);
        try std.testing.expectEqual(@as(u32, 1), placement.pixel_height);
        try std.testing.expectEqual(@as(u32, 1), placement.source_height);
        try std.testing.expectEqual(case.source_y, placement.source_y);
        try std.testing.expectEqual(content_before, image.content_generation);
        try std.testing.expect(!(try terminal.feed(case.miss)).stateChanged());
        try std.testing.expectEqual(@as(usize, 1), terminal.images(0).placementCount());
        try std.testing.expect((try terminal.feed(case.hit)).stateChanged());
        try std.testing.expectEqual(@as(usize, 0), terminal.images(0).placementCount());
        try std.testing.expectEqual(@as(usize, 1), terminal.images(0).imageCount());
        try std.testing.expectEqualStrings("", terminal.replyBytes());
    }
}

test "terminal: non-top margin scroll moves only images inside the region" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 4, 8, 8);
    defer terminal.deinit();
    try terminal.setCellPixelSize(1, 1);
    try feed(&terminal, "\x1b[3;1H\x1b_Ga=T,f=32,s=1,v=1,i=7,C=1;AQIDBA==\x1b\\" ++
        "\x1b[4;1H\x1b_Ga=T,f=32,s=1,v=1,i=8,C=1;AQIDBA==\x1b\\\x1b[2;3r\x1b[S");
    try std.testing.expectEqual(@as(u16, 1), terminal.images(0).placement(0).?.row);
    try std.testing.expectEqual(@as(u16, 3), terminal.images(0).placement(1).?.row);
    try std.testing.expectEqual(@as(u32, 0), terminal.semanticView(0).history_count);
}

test "terminal: CSI insert and delete lines leave graphics unchanged outside active margins" {
    const image_at_third_row = "\x1b[3;1H\x1b_Ga=T,f=32,s=1,v=1,i=19,C=1;AQIDBA==\x1b\\";
    for ([_][]const u8{ "\x1b[L", "\x1b[M" }) |operation| {
        for ([_]bool{ false, true }) |outside_horizontal| {
            var terminal = try Terminal.init(std.testing.allocator, 4, 8);
            defer terminal.deinit();
            try terminal.setCellPixelSize(1, 1);
            try feed(&terminal, image_at_third_row);
            try std.testing.expectEqual(@as(usize, 1), terminal.images(0).placementCount());
            try consumeReplies(&terminal);

            if (outside_horizontal) {
                // The cursor is in the vertical region but outside DECSLRM.
                try feed(&terminal, "\x1b[?69h\x1b[3;6s\x1b[2;4r\x1b[2;1H");
            } else {
                // The cursor is above DECSTBM, independently of DECSLRM.
                try feed(&terminal, "\x1b[2;4r\x1b[1;1H");
            }
            const placement_before = terminal.images(0).placement(0).?;
            const generation_before = terminal.images(0).generation;
            const image_generation_before = terminal.images(0).content_generation;
            const content_before = terminal.contentSequence();
            const row_before = terminal.semanticView(0).cursor_row;
            const col_before = terminal.semanticView(0).cursor_col;

            // Two halves ensure the decoder does not move graphics at a
            // framing boundary before the line-edit admission decision.
            try std.testing.expect(!(try terminal.feed(operation[0..2])).stateChanged());
            try std.testing.expect(!(try terminal.feed(operation[2..])).stateChanged());
            try std.testing.expectEqualDeep(placement_before, terminal.images(0).placement(0).?);
            try std.testing.expectEqual(generation_before, terminal.images(0).generation);
            try std.testing.expectEqual(image_generation_before, terminal.images(0).content_generation);
            try std.testing.expectEqual(content_before, terminal.contentSequence());
            try std.testing.expectEqual(row_before, terminal.semanticView(0).cursor_row);
            try std.testing.expectEqual(col_before, terminal.semanticView(0).cursor_col);
            try std.testing.expectEqual(@as(u8, 0), terminal.consequenceCount());
            try std.testing.expectEqual(@as(usize, 0), terminal.replyBytes().len);
        }
    }
}

test "terminal: CSI insert and delete lines move admitted graphics with retained text rows" {
    const image_at_third_row = "\x1b[3;1H\x1b_Ga=T,f=32,s=1,v=1,i=19,C=1;AQIDBA==\x1b\\";
    for ([_]struct { bytes: []const u8, expected_row: u16 }{
        .{ .bytes = "\x1b[L", .expected_row = 3 },
        .{ .bytes = "\x1b[M", .expected_row = 1 },
    }) |operation| {
        var terminal = try Terminal.init(std.testing.allocator, 4, 8);
        defer terminal.deinit();
        try terminal.setCellPixelSize(1, 1);
        try feed(&terminal, image_at_third_row);
        try consumeReplies(&terminal);
        try feed(&terminal, "\x1b[2;4r\x1b[2;3H");
        const before = terminal.images(0);
        try std.testing.expectEqual(@as(u16, 2), before.placement(0).?.row);
        const cursor_row = terminal.semanticView(0).cursor_row;
        const cursor_col = terminal.semanticView(0).cursor_col;
        try std.testing.expect((try terminal.feed(operation.bytes)).stateChanged());
        const after = terminal.images(0);
        try std.testing.expectEqual(operation.expected_row, after.placement(0).?.row);
        try std.testing.expect(after.generation > before.generation);
        try std.testing.expectEqual(before.content_generation, after.content_generation);
        try std.testing.expectEqual(@as(usize, 1), after.imageCount());
        try std.testing.expectEqual(cursor_row, terminal.semanticView(0).cursor_row);
        try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_col);
        try std.testing.expectEqual(@as(u16, 2), cursor_col);
    }
}

test "terminal: Kitty OSC 66 multiline lead survives admitted CSI L and M" {
    const sized = "\x1b]66;s=2;X\x07";
    for ([_]struct { sequence: []const u8, lead: u16, edit: u16, destination: u16 }{
        .{ .sequence = "\x1b[L", .lead = 1, .edit = 1, .destination = 2 },
        .{ .sequence = "\x1b[M", .lead = 2, .edit = 1, .destination = 1 },
    }) |case| {
        var terminal = try Terminal.init(std.testing.allocator, 5, 8);
        defer terminal.deinit();
        try feed(&terminal, "\x1b[2;5r");
        var cursor: [24]u8 = undefined;
        try feed(&terminal, try std.fmt.bufPrint(&cursor, "\x1b[{d};3H", .{case.lead + 1}));
        try feed(&terminal, sized);
        const initial = terminal.semanticView(0).cellInfoAt(case.lead, 2);
        try std.testing.expectEqual(@as(u21, 'X'), initial.codepoint);
        try std.testing.expectEqual(@as(u8, 2), initial.height);

        try feed(&terminal, try std.fmt.bufPrint(&cursor, "\x1b[{d};1H", .{case.edit + 1}));
        try std.testing.expect(!(try terminal.feed(case.sequence[0..2])).stateChanged());
        try std.testing.expect((try terminal.feed(case.sequence[2..])).stateChanged());
        const view = terminal.semanticView(0);
        try std.testing.expectEqual(@as(u21, 'X'), view.cellInfoAt(case.destination, 2).codepoint);
        try std.testing.expectEqual(@as(u16, case.edit), view.cursor_row);
        try std.testing.expectEqual(@as(u16, 0), view.cursor_col);
        for (0..initial.height) |row| for (0..initial.width) |col| {
            const cell = view.cellInfoAt(@intCast(case.destination + row), @intCast(2 + col));
            try std.testing.expectEqual(initial.width, cell.width);
            try std.testing.expectEqual(initial.height, cell.height);
            try std.testing.expectEqual(@as(u8, @intCast(row)), cell.y);
            try std.testing.expectEqual(@as(u8, @intCast(col)), cell.x);
        };
        try std.testing.expectEqual(@as(u8, 0), terminal.consequenceCount());
    }
}

test "terminal: pinned Kitty IL DL reject excess operands without structural or graphics edits" {
    // Frozen Kitty vt-parser.c CALL_CSI_HANDLER1 rejects more than one
    // parameter for both L and M, before calling its Screen line owner.
    // A final empty argument after ';' is not committed by Kitty.
    for ([_]struct { invalid: []const u8, valid: []const u8 }{
        .{ .invalid = "\x1b[2;1L", .valid = "\x1b[L" },
        .{ .invalid = "\x1b[2;1M", .valid = "\x1b[M" },
        .{ .invalid = "\x1b[0;;L", .valid = "\x1b[L" },
        .{ .invalid = "\x1b[0;;M", .valid = "\x1b[M" },
        .{ .invalid = "\x1b[2:1L", .valid = "\x1b[L" },
        .{ .invalid = "\x1b[2:1M", .valid = "\x1b[M" },
        .{ .invalid = "\x9b2;1L", .valid = "\x1b[L" },
        .{ .invalid = "\x9b2;1M", .valid = "\x1b[M" },
        .{ .invalid = "\x1b[1;2L", .valid = "\x1b[L" },
        .{ .invalid = "\x1b[1;2M", .valid = "\x1b[M" },
        .{ .invalid = "\x1b[;0;L", .valid = "\x1b[L" },
        .{ .invalid = "\x1b[;0;M", .valid = "\x1b[M" },
    }) |case| {
        var terminal = try Terminal.init(std.testing.allocator, 4, 8);
        defer terminal.deinit();
        try terminal.setCellPixelSize(1, 1);
        try feed(&terminal, "\x1b[1;1HAAAAAAAA\x1b[2;1HBBBBBBBB\x1b[3;1HCCCCCCCC\x1b[4;1HDDDDDDDD");
        try feed(&terminal, "\x1b[2;2H\x1b_Ga=T,f=32,s=1,v=1,i=93,C=1;AQIDBA==\x1b\\");
        try consumeReplies(&terminal);
        const cursor_before = terminal.semanticView(0);
        const row_before = cursor_before.cellInfoAt(1, 0);
        const below_before = cursor_before.cellInfoAt(2, 0);
        const above_before = cursor_before.cellInfoAt(0, 0);
        const bottom_before = cursor_before.cellInfoAt(3, 0);
        const sequence = terminal.semanticSequence();
        const edit = terminal.observation().structuralEditGeneration();
        const graphics = terminal.images(0);
        const placement = graphics.placement(0).?;
        const image_count = graphics.imageCount();
        const placement_count = graphics.placementCount();
        const image_generation = graphics.generation;
        const content_generation = graphics.content_generation;
        try std.testing.expectEqual(@as(usize, 1), placement_count);

        try std.testing.expect(!(try terminal.feed(case.invalid[0 .. case.invalid.len - 1])).stateChanged());
        try std.testing.expect(!(try terminal.feed(case.invalid[case.invalid.len - 1 ..])).stateChanged());
        const after = terminal.semanticView(0);
        try std.testing.expectEqual(sequence, terminal.semanticSequence());
        try std.testing.expectEqual(edit, terminal.observation().structuralEditGeneration());
        try std.testing.expectEqualDeep(row_before, after.cellInfoAt(1, 0));
        try std.testing.expectEqualDeep(below_before, after.cellInfoAt(2, 0));
        try std.testing.expectEqualDeep(above_before, after.cellInfoAt(0, 0));
        try std.testing.expectEqualDeep(bottom_before, after.cellInfoAt(3, 0));
        try std.testing.expectEqual(cursor_before.cursor_row, after.cursor_row);
        try std.testing.expectEqual(cursor_before.cursor_col, after.cursor_col);
        try std.testing.expectEqual(image_count, terminal.images(0).imageCount());
        try std.testing.expectEqual(placement_count, terminal.images(0).placementCount());
        try std.testing.expectEqual(placement.row, terminal.images(0).placement(0).?.row);
        try std.testing.expectEqual(placement.col, terminal.images(0).placement(0).?.col);
        try std.testing.expectEqual(image_generation, terminal.images(0).generation);
        try std.testing.expectEqual(content_generation, terminal.images(0).content_generation);
        try std.testing.expectEqualStrings("", terminal.replyBytes());

        // Invalid input cannot poison the next admitted edit.
        try std.testing.expect((try terminal.feed(case.valid)).stateChanged());
        try std.testing.expectEqual(edit + 1, terminal.observation().structuralEditGeneration());
    }

    // Kitty treats count zero as one for both screen_insert_lines and
    // screen_delete_lines, even when the zero has a trailing empty ';'.
    for ([_][]const u8{ "\x1b[0;L", "\x1b[0;M", "\x1b[;L", "\x1b[;M" }) |valid| {
        var terminal = try Terminal.init(std.testing.allocator, 3, 8);
        defer terminal.deinit();
        try feed(&terminal, "\x1b[1;1HAAAAAAAA\x1b[2;1HBBBBBBBB\x1b[3;1HCCCCCCCC\x1b[2;2H");
        const edit = terminal.observation().structuralEditGeneration();
        try std.testing.expect((try terminal.feed(valid)).stateChanged());
        try std.testing.expectEqual(edit + 1, terminal.observation().structuralEditGeneration());
        try std.testing.expectEqual(@as(u16, 1), terminal.semanticView(0).cursor_row);
        try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_col);
    }
}

test "terminal: pinned Kitty I X P at reject surplus operands without cell or graphic edits" {
    // Frozen Kitty vt-parser.c::dispatch_csi uses CALL_CSI_HANDLER1 for
    // CHT I, ECH X, DCH P and ICH @. Ordinary commands reject more than
    // one committed operand before Screen or the image owner can change.
    // Pinned libvterm/iTerm2 accept extras and act on the first count.
    const image = "\x1b_Ga=T,f=32,s=1,v=1,i=91,C=1;AQIDBA==\x1b\\";
    for ([_]u8{ 'I', 'X', 'P', '@' }) |final| {
        const Invalid = enum { extra, zero_extra, empty_middle, colon, c1, leading_empty, triple };
        for ([_]Invalid{ .extra, .zero_extra, .empty_middle, .colon, .c1, .leading_empty, .triple }) |variant| {
            var terminal = try Terminal.initWithHistory(std.testing.allocator, 4, 20, 4);
            defer terminal.deinit();
            try terminal.setCellPixelSize(1, 1);
            try feed(&terminal, "\x1b[1;1HAAAAAAAA\x1b[2;1HABCDEFGHIJKLMNOPQRST\x1b[3;1HCCCCCCCC\x1b[4;1HDDDDDDDD");
            try feed(&terminal, "\x1b[2;6H" ++ image ++ "\x1b[2;3H");
            try consumeReplies(&terminal);
            const before = terminal.semanticView(0);
            try std.testing.expectEqual(@as(u16, 1), before.cursor_row);
            try std.testing.expectEqual(@as(u16, 2), before.cursor_col);
            const positions = [_]struct { row: u16, col: u16 }{
                .{ .row = 0, .col = 0 }, .{ .row = 1, .col = 0 },
                .{ .row = 1, .col = 2 }, .{ .row = 1, .col = 5 },
                .{ .row = 2, .col = 0 }, .{ .row = 3, .col = 0 },
            };
            var cells: [positions.len]@TypeOf(before.cellInfoAt(0, 0)) = undefined;
            for (positions, 0..) |pos, idx| cells[idx] = before.cellInfoAt(pos.row, pos.col);
            const seq = terminal.semanticSequence();
            const edit = terminal.observation().structuralEditGeneration();
            const images = terminal.images(0);
            try std.testing.expectEqual(@as(usize, 1), images.placementCount());
            const placement = images.placement(0).?;
            const image_count = images.imageCount();
            const image_generation = images.generation;
            const content_generation = images.content_generation;

            var buffer: [32]u8 = undefined;
            const invalid = switch (variant) {
                .extra => try std.fmt.bufPrint(&buffer, "\x1b[1;9{c}", .{final}),
                .zero_extra => try std.fmt.bufPrint(&buffer, "\x1b[0;2{c}", .{final}),
                .empty_middle => try std.fmt.bufPrint(&buffer, "\x1b[1;;{c}", .{final}),
                .colon => try std.fmt.bufPrint(&buffer, "\x1b[1:9{c}", .{final}),
                .c1 => try std.fmt.bufPrint(&buffer, "\x9b1;9{c}", .{final}),
                .leading_empty => try std.fmt.bufPrint(&buffer, "\x1b[;2{c}", .{final}),
                .triple => try std.fmt.bufPrint(&buffer, "\x1b[1;2;3{c}", .{final}),
            };
            try std.testing.expect(!(try terminal.feed(invalid[0 .. invalid.len - 1])).stateChanged());
            try std.testing.expect(!(try terminal.feed(invalid[invalid.len - 1 ..])).stateChanged());
            const after = terminal.semanticView(0);
            try std.testing.expectEqual(seq, terminal.semanticSequence());
            try std.testing.expectEqual(before.cursor_row, after.cursor_row);
            try std.testing.expectEqual(before.cursor_col, after.cursor_col);
            try std.testing.expectEqual(before.history_count, after.history_count);
            try std.testing.expectEqual(edit, terminal.observation().structuralEditGeneration());
            for (positions, cells) |pos, cell|
                try std.testing.expectEqualDeep(cell, after.cellInfoAt(pos.row, pos.col));
            try std.testing.expectEqual(image_count, terminal.images(0).imageCount());
            try std.testing.expectEqual(@as(usize, 1), terminal.images(0).placementCount());
            try std.testing.expectEqual(placement.row, terminal.images(0).placement(0).?.row);
            try std.testing.expectEqual(placement.col, terminal.images(0).placement(0).?.col);
            try std.testing.expectEqual(image_generation, terminal.images(0).generation);
            try std.testing.expectEqual(content_generation, terminal.images(0).content_generation);
            try std.testing.expectEqualStrings("", terminal.replyBytes());

            // Valid next control must still perform its owned edit/tab.
            const valid = try std.fmt.bufPrint(&buffer, "\x1b[2{c}", .{final});
            try std.testing.expect((try terminal.feed(valid)).stateChanged());
            const recovered = terminal.semanticView(0);
            if (final == 'I') {
                try std.testing.expectEqual(@as(u16, 16), recovered.cursor_col);
            } else {
                try std.testing.expectEqual(before.cursor_col, recovered.cursor_col);
            }
        }

        // Missing, zero, trailing semicolon and positive counts are legal.
        const Valid = enum { missing, zero, zero_trailing, positive, positive_trailing, c1 };
        for ([_]Valid{ .missing, .zero, .zero_trailing, .positive, .positive_trailing, .c1 }) |variant| {
            var terminal = try Terminal.init(std.testing.allocator, 4, 20);
            defer terminal.deinit();
            try feed(&terminal, "\x1b[2;1HABCDEFGHIJKLMNOPQRST\x1b[2;3H");
            var buffer: [32]u8 = undefined;
            const valid = switch (variant) {
                .missing => try std.fmt.bufPrint(&buffer, "\x1b[{c}", .{final}),
                .zero => try std.fmt.bufPrint(&buffer, "\x1b[0{c}", .{final}),
                .zero_trailing => try std.fmt.bufPrint(&buffer, "\x1b[0;{c}", .{final}),
                .positive => try std.fmt.bufPrint(&buffer, "\x1b[2{c}", .{final}),
                .positive_trailing => try std.fmt.bufPrint(&buffer, "\x1b[2;{c}", .{final}),
                .c1 => try std.fmt.bufPrint(&buffer, "\x9b2{c}", .{final}),
            };
            try std.testing.expect((try terminal.feed(valid)).stateChanged());
            const view = terminal.semanticView(0);
            const two = variant == .positive or variant == .positive_trailing or variant == .c1;
            try std.testing.expectEqual(@as(u16, if (final == 'I') (if (two) 16 else 8) else 2), view.cursor_col);
            if (final != 'I') {
                const expected: u21 = if (final == 'P') (if (two) 'E' else 'D') else 0;
                try std.testing.expectEqual(expected, view.cellAt(1, 2));
            }
        }
    }
}

test "terminal: pinned Kitty REP rejects excess counts without repeating or disturbing graphics" {
    // Frozen Kitty vt-parser.c::dispatch_csi REP uses CALL_CSI_HANDLER1.
    // libvterm and iTerm2 consume only the leading count instead.
    const image = "\x1b_Ga=T,f=32,s=1,v=1,i=98,C=1;AQIDBA==\x1b\\";
    for ([_][]const u8{
        "\x1b[1;9b", "\x1b[0;2b", "\x1b[1;;b",   "\x1b[1:9b",
        "\x9b1;9b",  "\x1b[;2b",  "\x1b[1;2;3b",
    }) |invalid| {
        var terminal = try Terminal.initWithHistory(std.testing.allocator, 4, 20, 4);
        defer terminal.deinit();
        try terminal.setCellPixelSize(1, 1);
        try feed(&terminal, "\x1b[1;1HABCDEFGHIJKLMNOPQRST\x1b[3;6H" ++ image ++ "\x1b[2;3HR");
        try consumeReplies(&terminal);
        const before = terminal.semanticView(0);
        const sequence = terminal.semanticSequence();
        const edit = terminal.observation().structuralEditGeneration();
        const row0 = before.cellInfoAt(0, 0);
        const row1 = before.cellInfoAt(1, 3);
        const row2 = before.cellInfoAt(2, 0);
        const graphics = terminal.images(0);
        try std.testing.expectEqual(@as(usize, 1), graphics.placementCount());
        const placement = graphics.placement(0).?;
        const graphics_generation = graphics.generation;
        const graphics_content_generation = graphics.content_generation;
        const image_count = graphics.imageCount();

        try std.testing.expect(!(try terminal.feed(invalid[0 .. invalid.len - 1])).stateChanged());
        try std.testing.expect(!(try terminal.feed(invalid[invalid.len - 1 ..])).stateChanged());
        const after = terminal.semanticView(0);
        try std.testing.expectEqual(sequence, terminal.semanticSequence());
        try std.testing.expectEqual(before.cursor_row, after.cursor_row);
        try std.testing.expectEqual(before.cursor_col, after.cursor_col);
        try std.testing.expectEqual(before.history_count, after.history_count);
        try std.testing.expectEqual(edit, terminal.observation().structuralEditGeneration());
        try std.testing.expectEqualDeep(row0, after.cellInfoAt(0, 0));
        try std.testing.expectEqualDeep(row1, after.cellInfoAt(1, 3));
        try std.testing.expectEqualDeep(row2, after.cellInfoAt(2, 0));
        try std.testing.expectEqual(image_count, terminal.images(0).imageCount());
        try std.testing.expectEqual(@as(usize, 1), terminal.images(0).placementCount());
        try std.testing.expectEqual(placement.row, terminal.images(0).placement(0).?.row);
        try std.testing.expectEqual(placement.col, terminal.images(0).placement(0).?.col);
        try std.testing.expectEqual(graphics_generation, terminal.images(0).generation);
        try std.testing.expectEqual(graphics_content_generation, terminal.images(0).content_generation);
        try std.testing.expectEqualStrings("", terminal.replyBytes());

        try std.testing.expect((try terminal.feed("\x1b[2b")).stateChanged());
        try std.testing.expectEqual(@as(u21, 'R'), terminal.semanticView(0).cellAt(1, 3));
        try std.testing.expectEqual(@as(u21, 'R'), terminal.semanticView(0).cellAt(1, 4));
    }

    for ([_]struct { bytes: []const u8, count: u16 }{
        .{ .bytes = "\x1b[b", .count = 1 },
        .{ .bytes = "\x1b[0b", .count = 1 },
        .{ .bytes = "\x1b[0;b", .count = 1 },
        .{ .bytes = "\x1b[2b", .count = 2 },
        .{ .bytes = "\x1b[2;b", .count = 2 },
        .{ .bytes = "\x9b2b", .count = 2 },
    }) |case| {
        var terminal = try Terminal.init(std.testing.allocator, 2, 20);
        defer terminal.deinit();
        try feed(&terminal, "\x1b[1;1HK");
        try std.testing.expect((try terminal.feed(case.bytes)).stateChanged());
        try std.testing.expectEqual(@as(u16, 1) + case.count, terminal.semanticView(0).cursor_col);
        for (0..case.count + 1) |col| try std.testing.expectEqual(@as(u21, 'K'), terminal.semanticView(0).cellAt(0, @intCast(col)));
    }

    // Rejecting REP cannot clear a pending wrap from an exact-width fill.
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    try feed(&terminal, "\x1b[1;8H!");
    const sequence = terminal.semanticSequence();
    try std.testing.expect(!(try terminal.feed("\x1b[1;9b")).stateChanged());
    try std.testing.expectEqual(sequence, terminal.semanticSequence());
    try feed(&terminal, "X");
    try std.testing.expectEqual(@as(u21, '!'), terminal.semanticView(0).cellAt(0, 7));
    try std.testing.expectEqual(@as(u21, 'X'), terminal.semanticView(0).cellAt(1, 0));
}

test "terminal: accepted TBC subset rejects excess operands and ignores mode five" {
    // Frozen Kitty vt-parser.c uses CALL_CSI_HANDLER1 with default 0 for g.
    // libvterm/iTerm2 consume the first parameter, even with a second.
    for ([_][]const u8{
        "\x1b[0;9g", "\x1b[3;9g", "\x1b[5;9g", "\x1b[0;;g",
        "\x1b[3:9g", "\x9b3;9g",  "\x1b[;3g",  "\x1b[3;9;1g",
    }) |invalid| {
        var terminal = try Terminal.init(std.testing.allocator, 2, 20);
        defer terminal.deinit();
        try feed(&terminal, "\x1b[1;9H"); // Default stop at zero-based column 8.
        const before = terminal.semanticView(0);
        const sequence = terminal.semanticSequence();
        try std.testing.expect(!(try terminal.feed(invalid[0 .. invalid.len - 1])).stateChanged());
        try std.testing.expect(!(try terminal.feed(invalid[invalid.len - 1 ..])).stateChanged());
        try std.testing.expectEqual(sequence, terminal.semanticSequence());
        try std.testing.expectEqual(before.cursor_col, terminal.semanticView(0).cursor_col);
        try std.testing.expectEqual(before.cursor_row, terminal.semanticView(0).cursor_row);
        try std.testing.expectEqualStrings("", terminal.replyBytes());

        try feed(&terminal, "\r\t");
        try std.testing.expectEqual(@as(u16, 8), terminal.semanticView(0).cursor_col);
        try feed(&terminal, "\x1b[3g\r\t");
        try std.testing.expectEqual(@as(u16, 19), terminal.semanticView(0).cursor_col);
    }

    for ([_]struct { bytes: []const u8, expected_col: u16 }{
        .{ .bytes = "\x1b[g", .expected_col = 16 },
        .{ .bytes = "\x1b[0g", .expected_col = 16 },
        .{ .bytes = "\x1b[0;g", .expected_col = 16 },
        .{ .bytes = "\x1b[3g", .expected_col = 19 },
        .{ .bytes = "\x1b[3;g", .expected_col = 19 },
        .{ .bytes = "\x9b3g", .expected_col = 19 },
        .{ .bytes = "\x1b[5g", .expected_col = 8 },
        .{ .bytes = "\x1b[5;g", .expected_col = 8 },
    }) |case| {
        var terminal = try Terminal.init(std.testing.allocator, 2, 20);
        defer terminal.deinit();
        try feed(&terminal, "\x1b[1;9H");
        try feed(&terminal, case.bytes);
        try feed(&terminal, "\r\t");
        try std.testing.expectEqual(case.expected_col, terminal.semanticView(0).cursor_col);
    }
}

test "terminal: structural line-edit generation distinguishes admission from ordinary output" {
    var terminal = try Terminal.init(std.testing.allocator, 4, 8);
    defer terminal.deinit();
    const before = terminal.observation().structuralEditGeneration();
    try feed(&terminal, "ABCD\x1b[2;4r\x1b[1;1H");
    try std.testing.expectEqual(before, terminal.observation().structuralEditGeneration());
    try std.testing.expect(!(try terminal.feed("\x1b[L")).stateChanged());
    try std.testing.expectEqual(before, terminal.observation().structuralEditGeneration());
    try feed(&terminal, "\x1b[2;2H");
    try std.testing.expect(!(try terminal.feed("\x1b[")).stateChanged());
    try std.testing.expectEqual(before, terminal.observation().structuralEditGeneration());
    try feed(&terminal, "L");
    try std.testing.expectEqual(before + 1, terminal.observation().structuralEditGeneration());
    try feed(&terminal, "\x1b[M");
    try std.testing.expectEqual(before + 2, terminal.observation().structuralEditGeneration());
    try feed(&terminal, "\x1b[S\x1b[TQ");
    try std.testing.expectEqual(before + 2, terminal.observation().structuralEditGeneration());
    try std.testing.expectEqual(@as(u8, 0), terminal.consequenceCount());
}

test "terminal: clearing pending wrap does not admit a CSI line edit" {
    for ([_][]const u8{ "\x1b[L", "\x1b[M" }) |operation| {
        var terminal = try Terminal.init(std.testing.allocator, 4, 8);
        defer terminal.deinit();
        try feed(&terminal, "\x1b[2;4r\x1b[1;8H!");
        const initial = terminal.observation().structuralEditGeneration();
        const cursor = terminal.semanticView(0);
        try std.testing.expect((try terminal.feed(operation)).stateChanged());
        try std.testing.expectEqual(initial, terminal.observation().structuralEditGeneration());
        try std.testing.expectEqual(cursor.cursor_row, terminal.semanticView(0).cursor_row);
        try std.testing.expectEqual(cursor.cursor_col, terminal.semanticView(0).cursor_col);
        try std.testing.expectEqual(@as(u21, '!'), terminal.semanticView(0).cellAt(0, 7));
        try std.testing.expect(!(try terminal.feed(operation)).stateChanged());
        try std.testing.expectEqual(initial, terminal.observation().structuralEditGeneration());
    }
}

test "terminal: pinned Kitty ignores DEC 69 while Howl bounds L M S T horizontally" {
    // Pinned Kitty screen.c:set_mode_from_const has no private mode 69,
    // and its linebuf_insert/delete and index routines edit complete rows.
    // Howl deliberately owns DECSLRM and applies it consistently to all
    // four commands. Do not force incompatible per-reference behavior.
    const cases = [_]struct { sequence: []const u8, inside: u21 }{
        .{ .sequence = "\x1b[L", .inside = 0 },
        .{ .sequence = "\x1b[M", .inside = 'C' },
        .{ .sequence = "\x1b[S", .inside = 'C' },
        .{ .sequence = "\x1b[T", .inside = 0 },
    };
    for (cases) |case| {
        var terminal = try Terminal.init(std.testing.allocator, 4, 6);
        defer terminal.deinit();
        try feed(&terminal, "\x1b[1;1HAAAAAA\x1b[2;1HBBBBBB\x1b[3;1HCCCCCC\x1b[4;1HDDDDDD");
        try feed(&terminal, "\x1b[?69h\x1b[3;4s\x1b[2;3r\x1b[2;3H");
        try std.testing.expect((try terminal.feed(case.sequence)).stateChanged());
        const view = terminal.semanticView(0);
        try std.testing.expectEqual(@as(u21, 'A'), view.cellAt(0, 0));
        try std.testing.expectEqual(@as(u21, 'D'), view.cellAt(3, 0));
        for ([_]u16{ 0, 1, 4, 5 }) |col| {
            try std.testing.expectEqual(@as(u21, 'B'), view.cellAt(1, col));
            try std.testing.expectEqual(@as(u21, 'C'), view.cellAt(2, col));
        }
        try std.testing.expectEqual(case.inside, view.cellAt(1, 2));
        try std.testing.expectEqual(case.inside, view.cellAt(1, 3));
        try std.testing.expectEqual(@as(u8, 0), terminal.consequenceCount());
        try std.testing.expectEqualStrings("", terminal.replyBytes());
    }
}

test "terminal: CSI row scrolls respect horizontal margins for graphics as for cells" {
    const outside = "\x1b[3;1H\x1b_Ga=T,f=32,s=1,v=1,i=19,C=1;AQIDBA==\x1b\\";
    const inside = "\x1b[3;4H\x1b_Ga=T,f=32,s=1,v=1,i=20,C=1;AQIDBA==\x1b\\";
    for ([_]struct { bytes: []const u8, expected_row: u16 }{
        .{ .bytes = "\x1b[L", .expected_row = 3 },
        .{ .bytes = "\x1b[M", .expected_row = 1 },
        .{ .bytes = "\x1b[S", .expected_row = 1 },
        .{ .bytes = "\x1b[T", .expected_row = 3 },
    }) |operation| {
        var terminal = try Terminal.init(std.testing.allocator, 4, 8);
        defer terminal.deinit();
        try terminal.setCellPixelSize(1, 1);
        try feed(&terminal, "\x1b[3;1HO\x1b[3;4HI");
        try feed(&terminal, outside ++ inside);
        try consumeReplies(&terminal);
        try std.testing.expectEqual(@as(usize, 2), terminal.images(0).placementCount());
        try std.testing.expectEqual(@as(u16, 2), terminal.images(0).placement(0).?.row);
        try std.testing.expectEqual(@as(u16, 2), terminal.images(0).placement(1).?.row);
        try feed(&terminal, "\x1b[?69h\x1b[3;6s\x1b[2;4r\x1b[2;5H");
        const image_generation = terminal.images(0).content_generation;

        try std.testing.expect((try terminal.feed(operation.bytes)).stateChanged());
        const images = terminal.images(0);
        try std.testing.expectEqual(@as(usize, 2), images.placementCount());
        try std.testing.expectEqual(@as(u16, 2), images.placement(0).?.row);
        try std.testing.expectEqual(@as(u16, 0), images.placement(0).?.col);
        try std.testing.expectEqual(operation.expected_row, images.placement(1).?.row);
        try std.testing.expectEqual(@as(u16, 3), images.placement(1).?.col);
        try std.testing.expectEqual(@as(u21, 'O'), terminal.semanticView(0).cellAt(2, 0));
        try std.testing.expectEqual(@as(u21, 'I'), terminal.semanticView(0).cellAt(operation.expected_row, 3));
        try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(2, 3));
        const cursor_col: u16 = if (operation.bytes[2] == 'L' or operation.bytes[2] == 'M') 2 else 4;
        try std.testing.expectEqual(cursor_col, terminal.semanticView(0).cursor_col);
        try std.testing.expectEqual(image_generation, images.content_generation);
    }
}

const more_fix_scroll_fixture =
    "\x1b[1;1HAAAAAAAAAA\x1b[2;1HBBBBBBBBBB\x1b[3;1HCCCCCCCCC\x1b[4;1HDDDDDDDDDD" ++
    "\x1b[3;3H\x1b_Ga=T,f=32,s=1,v=1,i=90,C=1,q=2;AQIDBA==\x1b\\" ++
    "\x1b[4;3H\x1b_Ga=T,f=32,s=1,v=1,i=91,C=1,q=2;AQIDBA==\x1b\\";

test "terminal: mode 41 tab scroll keeps cells and graphics aligned" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 4, 10, 0);
    defer terminal.deinit();
    try terminal.setCellPixelSize(1, 1);
    try feed(&terminal, more_fix_scroll_fixture);
    try feed(&terminal, "\x1b[2;3r\x1b[?41h\x1b[3;10HC");
    const before = terminal.images(0);
    try std.testing.expectEqual(@as(usize, 2), before.placementCount());
    try std.testing.expectEqual(@as(u16, 2), before.placement(0).?.row);
    try std.testing.expectEqual(@as(u16, 3), before.placement(1).?.row);
    try std.testing.expect((try terminal.feed("\t")).stateChanged());
    const after = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u16, 2), after.cursor_row);
    try std.testing.expectEqual(@as(u16, 8), after.cursor_col);
    try std.testing.expectEqual(@as(u21, 'A'), after.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'C'), after.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 0), after.cellAt(2, 0));
    try std.testing.expectEqual(@as(u21, 'D'), after.cellAt(3, 0));
    const images = terminal.images(0);
    try std.testing.expectEqual(@as(usize, 2), images.placementCount());
    try std.testing.expectEqual(@as(u16, 1), images.placement(0).?.row);
    try std.testing.expectEqual(@as(u16, 3), images.placement(1).?.row);
    try std.testing.expectEqual(before.content_generation, images.content_generation);
}

test "terminal: mode 41 tab admits history before scrolling and retries once" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var terminal = try Terminal.initWithHistory(failing.allocator(), 4, 10, 8);
    defer terminal.deinit();
    try terminal.setCellPixelSize(1, 1);
    try feed(&terminal, more_fix_scroll_fixture);
    try feed(&terminal, "\x1b[1;3r\x1b[?41h\x1b[3;10HC");
    const before = terminal.semanticView(0);
    const before_images = terminal.images(0);
    const moving = before_images.placement(0).?;
    const fixed = before_images.placement(1).?;
    const sequence = terminal.semanticSequence();
    const output_range = terminal.logicalOutputRange();

    failing.fail_index = failing.alloc_index;
    const bytes = "\tZ";
    const blocked = try terminal.feedAtServiceBoundary(bytes, 1);
    try std.testing.expectEqual(@as(usize, 1), blocked.consumed);
    try std.testing.expectEqual(error.OutOfMemory, blocked.input_blocked.?);
    try std.testing.expect(!blocked.summary.stateChanged());
    try std.testing.expect(!blocked.summary.historyLost());
    try std.testing.expectEqual(sequence, terminal.semanticSequence());
    try std.testing.expectEqualDeep(output_range, terminal.logicalOutputRange());
    try std.testing.expectEqual(before.history_count, terminal.semanticView(0).history_count);
    try std.testing.expectEqual(before.cursor_row, terminal.semanticView(0).cursor_row);
    try std.testing.expectEqual(before.cursor_col, terminal.semanticView(0).cursor_col);
    try std.testing.expectEqual(@as(u21, 'A'), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'C'), terminal.semanticView(0).cellAt(2, 9));
    try std.testing.expectEqual(before_images.generation, terminal.images(0).generation);
    try std.testing.expectEqualDeep(moving, terminal.images(0).placement(0).?);
    try std.testing.expectEqualDeep(fixed, terminal.images(0).placement(1).?);

    const stalled = try terminal.feedAtServiceBoundary(bytes[blocked.consumed..], 2);
    try std.testing.expectEqual(@as(usize, 0), stalled.consumed);
    try std.testing.expectEqual(error.OutOfMemory, stalled.input_blocked.?);
    try std.testing.expectEqual(sequence, terminal.semanticSequence());
    failing.fail_index = std.math.maxInt(usize);
    const recovered = try terminal.feedAtServiceBoundary(bytes[blocked.consumed..], 3);
    try std.testing.expectEqual(@as(usize, 1), recovered.consumed);
    try std.testing.expect(recovered.input_blocked == null);
    try std.testing.expect(!recovered.summary.historyLost());
    const after = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u32, 1), after.history_count);
    try std.testing.expectEqual(@as(u21, 'A'), terminal.semanticView(1).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), after.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'C'), after.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'Z'), after.cellAt(2, 8));
    try std.testing.expectEqual(@as(u21, 'D'), after.cellAt(3, 0));
    try std.testing.expectEqual(@as(u16, 2), after.cursor_row);
    try std.testing.expectEqual(@as(u16, 9), after.cursor_col);
    const images = terminal.images(0);
    try std.testing.expectEqual(@as(usize, 2), images.placementCount());
    try std.testing.expectEqual(@as(u16, 1), images.placement(0).?.row);
    try std.testing.expectEqual(@as(u16, 3), images.placement(1).?.row);
    try std.testing.expectEqual(before_images.content_generation, images.content_generation);
}

test "terminal: no-history full-screen scroll retains the visible tail of a multirow image" {
    // Pinned Kitty's no-margin grman_scroll_images keeps an image whose
    // anchor leaves the viewport if part of it still intersects the screen.
    // Howl's unsigned absolute row model must represent only the visible
    // remainder without retaining an impossible negative-row anchor.
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 3, 8, 0);
    defer terminal.deinit();
    try terminal.setCellPixelSize(1, 1);
    try feed(&terminal, "\x1b[1;1H\x1b_Ga=T,f=32,s=1,v=2,i=60,C=1,q=2;AQIDBAUGBwg=\x1b\\");
    const prior = terminal.images(0);
    try std.testing.expectEqual(@as(usize, 1), prior.placementCount());
    try std.testing.expectEqual(@as(u16, 0), prior.placement(0).?.row);
    try std.testing.expectEqual(@as(u32, 2), prior.placement(0).?.pixel_height);
    const prior_content = prior.content_generation;
    try feed(&terminal, "\x1b[3;1H\n");
    const after = terminal.images(0);
    try std.testing.expectEqual(@as(u32, 0), terminal.semanticView(0).history_count);
    try std.testing.expectEqual(@as(usize, 1), after.imageCount());
    try std.testing.expectEqual(@as(usize, 1), after.placementCount());
    const remaining = after.placement(0) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u16, 0), remaining.row);
    try std.testing.expectEqual(@as(u32, 1), remaining.source_y);
    try std.testing.expectEqual(@as(u32, 1), remaining.source_height);
    try std.testing.expectEqual(@as(u32, 1), remaining.pixel_height);
    try std.testing.expectEqual(prior_content, after.content_generation);
    // The erased leading row cannot still be hit by a Y deletion.
    try std.testing.expect(!(try terminal.feed("\x1b_Ga=d,d=Y,y=2\x1b\\")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b_Ga=d,d=Y,y=1\x1b\\")).stateChanged());
    try std.testing.expectEqual(@as(usize, 0), terminal.images(0).imageCount());
}

test "terminal: successive no-history full-screen scrolls clip each surviving image row" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 3, 8, 0);
    defer terminal.deinit();
    try terminal.setCellPixelSize(1, 1);
    try feed(&terminal, "\x1b[1;1H\x1b_Ga=T,f=32,s=1,v=3,i=61,C=1,q=2;AQIDBAUGBwgJCgsM\x1b\\");
    const initial = terminal.images(0);
    try std.testing.expectEqual(@as(usize, 1), initial.placementCount());
    const data_generation = initial.content_generation;
    for ([_]struct { source_y: u32, height: u32 }{
        .{ .source_y = 1, .height = 2 },
        .{ .source_y = 2, .height = 1 },
    }) |case| {
        try feed(&terminal, "\x1b[3;1H\n");
        const images = terminal.images(0);
        try std.testing.expectEqual(@as(usize, 1), images.imageCount());
        try std.testing.expectEqual(@as(usize, 1), images.placementCount());
        const placement = images.placement(0) orelse return error.TestUnexpectedResult;
        try std.testing.expectEqual(@as(u16, 0), placement.row);
        try std.testing.expectEqual(case.source_y, placement.source_y);
        try std.testing.expectEqual(case.height, placement.source_height);
        try std.testing.expectEqual(case.height, placement.pixel_height);
        try std.testing.expectEqual(data_generation, images.content_generation);
    }
    try feed(&terminal, "\x1b[3;1H\n");
    const final = terminal.images(0);
    try std.testing.expectEqual(@as(u32, 0), terminal.semanticView(0).history_count);
    try std.testing.expectEqual(@as(usize, 1), final.imageCount());
    try std.testing.expectEqual(@as(usize, 0), final.placementCount());
    try std.testing.expectEqual(data_generation, final.content_generation);
}

test "terminal: retained history scroll keeps full image source and projects negative viewport top" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 3, 8, 4);
    defer terminal.deinit();
    try terminal.setCellPixelSize(1, 1);
    try feed(&terminal, "\x1b[1;1H\x1b_Ga=T,f=32,s=1,v=3,i=62,C=1,q=2;AQIDBAUGBwgJCgsM\x1b\\");
    const data_generation = terminal.images(0).content_generation;
    try feed(&terminal, "\x1b[3;1H\n");
    try std.testing.expectEqual(@as(u32, 1), terminal.semanticView(0).history_count);
    try std.testing.expectEqual(@as(usize, 1), terminal.images(0).imageCount());
    try std.testing.expect(terminal.images(0).placement(0) == null);
    const historical = terminal.images(1).placement(0) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u32, 0), historical.source_y);
    try std.testing.expectEqual(@as(u32, 3), historical.source_height);
    try std.testing.expectEqual(@as(u32, 3), historical.pixel_height);
    try std.testing.expectEqual(data_generation, terminal.images(0).content_generation);
    var iterator = terminal.images(0).placementIterator();
    const visible = iterator.next() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(i128, -1), visible.top);
    try std.testing.expectEqual(@as(u32, 0), visible.placement.source_y);
    try std.testing.expectEqual(@as(u32, 3), visible.placement.pixel_height);
    try std.testing.expect(iterator.next() == null);
}

test "terminal: full-screen LF scrolls graphics both with and without retained history" {
    for ([_]u16{ 0, 2 }) |history_capacity| {
        var terminal = try Terminal.initWithHistory(std.testing.allocator, 2, 4, history_capacity);
        defer terminal.deinit();
        try terminal.setCellPixelSize(1, 1);
        try feed(&terminal, "\x1b[2;1H\x1b_Ga=T,f=32,s=1,v=1,i=27,C=1;AQIDBA==\x1b\\");
        try consumeReplies(&terminal);
        try std.testing.expectEqual(@as(u16, 1), terminal.images(0).placement(0).?.row);
        const source_generation = terminal.images(0).content_generation;
        try std.testing.expect((try terminal.feed("\n")).stateChanged());
        try std.testing.expectEqual(history_capacity != 0, terminal.semanticView(0).history_count > 0);
        try std.testing.expectEqual(@as(u16, 0), terminal.images(0).placement(0).?.row);
        try std.testing.expectEqual(@as(usize, 1), terminal.images(0).imageCount());
        try std.testing.expectEqual(source_generation, terminal.images(0).content_generation);
    }
}

test "terminal: horizontal margin row edits retire only straddling graphics placements" {
    var terminal = try Terminal.init(std.testing.allocator, 4, 8);
    defer terminal.deinit();
    try terminal.setCellPixelSize(1, 1);
    try feed(&terminal, "\x1b[3;2H\x1b_Ga=T,f=32,s=2,v=1,i=31,C=1;AQIDBAUGBwg=\x1b\\");
    try consumeReplies(&terminal);
    try std.testing.expectEqual(@as(usize, 1), terminal.images(0).placementCount());
    try std.testing.expectEqual(@as(usize, 1), terminal.images(0).imageCount());
    const pixels = terminal.images(0).content_generation;
    try feed(&terminal, "\x1b[?69h\x1b[3;6s\x1b[2;4r\x1b[2;3H");
    try std.testing.expect((try terminal.feed("\x1b[L")).stateChanged());
    // One image spans the left DECSLRM edge. Translating it wholesale would
    // move pixels outside the text region, so keep data and drop placement.
    try std.testing.expectEqual(@as(usize, 0), terminal.images(0).placementCount());
    try std.testing.expectEqual(@as(usize, 1), terminal.images(0).imageCount());
    try std.testing.expectEqual(pixels, terminal.images(0).content_generation);
}
