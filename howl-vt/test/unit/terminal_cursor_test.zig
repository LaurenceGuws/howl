const std = @import("std");
const terminal_mod = @import("../../src/howl_vt.zig");

const Terminal = terminal_mod.Terminal;

fn feed(terminal: *Terminal, bytes: []const u8) Terminal.FeedError!void {
    const summary = try terminal.feed(bytes);
    std.debug.assert(!summary.historyLost() or summary.stateChanged());
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
    try std.testing.expectEqual(.block, view(&terminal).cursor_shape);
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
        try std.testing.expect((try terminal.feed(case.bytes)).stateChanged());
        try std.testing.expectEqual(case.shape, view(&terminal).cursor_shape);
        try std.testing.expectEqual(case.blink, view(&terminal).cursor_blink);
    }

    try std.testing.expect(!(try terminal.feed("\x1b[0 ")).stateChanged());
    try std.testing.expect((try terminal.feed("q")).stateChanged());
    try std.testing.expectEqual(.block, view(&terminal).cursor_shape);
    try std.testing.expect(view(&terminal).cursor_blink);
    try std.testing.expect(!(try terminal.feed("\x1b[ q\x1b[7 q\x1b[999999 q")).stateChanged());
    try std.testing.expectEqual(.block, view(&terminal).cursor_shape);
    try std.testing.expect(view(&terminal).cursor_blink);

    try std.testing.expect((try terminal.feed("\x1bP$q q\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings("\x1bP1$r1 q\x1b\\", terminal.replyBytes());

    // A caller-configured default must win over a previous program override,
    // not silently restore the constructor's blinking block.
    var configured = try Terminal.init(allocator, 2, 4);
    defer configured.deinit();
    configured.setDefaultCursorStyle(.{ .shape = .bar, .blink = false });
    try feed(&configured, "\x1b[2;3H\x1b[3 q");
    try std.testing.expectEqual(.underline, view(&configured).cursor_shape);
    try std.testing.expect(view(&configured).cursor_blink);
    try std.testing.expect(!(try configured.feed("\x1b[0 ")).stateChanged());
    try std.testing.expect((try configured.feed("q")).stateChanged());
    try std.testing.expectEqual(.bar, view(&configured).cursor_shape);
    try std.testing.expect(!view(&configured).cursor_blink);
    try std.testing.expectEqual(@as(u16, 1), view(&configured).cursor_row);
    try std.testing.expectEqual(@as(u16, 2), view(&configured).cursor_col);
    const revision = configured.semanticSequence();
    try std.testing.expect(!(try configured.feed("\x1b[0 q\x1b[7 q")).stateChanged());
    try std.testing.expectEqual(revision, configured.semanticSequence());
    try feed(&configured, "\x1b[?47h\x1b[4 q\x1b[0 q");
    try std.testing.expectEqual(.bar, view(&configured).cursor_shape);
    try std.testing.expect(!view(&configured).cursor_blink);
    try feed(&configured, "\x1b[?47l");
    try std.testing.expectEqual(.bar, view(&configured).cursor_shape);
    try std.testing.expect(!view(&configured).cursor_blink);
}

test "terminal cursor: pinned Kitty DECSCUSR rejects excess operands before changing appearance" {
    // Frozen Kitty vt-parser.c::dispatch_csi uses CALL_CSI_HANDLER1M for
    // ordinary CSI Ps SP q, refusing more than one committed parameter.
    // Pinned libvterm/iTerm2 instead apply the first. This proof does not
    // change Kitty CSI > Pm SP q multi-cursor admission or default policy.
    const image = "\x1b_Ga=T,f=32,s=1,v=1,i=97,C=1;AQIDBA==\x1b\\";
    for ([_][]const u8{
        "\x1b[3;6 q", "\x1b[3;0 q", "\x1b[3;; q",   "\x1b[3:6 q",
        "\x9b3;6 q",  "\x1b[;4 q",  "\x1b[3;6;1 q",
    }) |invalid| {
        var terminal = try Terminal.initWithHistory(std.testing.allocator, 4, 8, 4);
        defer terminal.deinit();
        try terminal.setCellPixelSize(1, 1);
        try feed(&terminal, "\x1b[1;1HABCDEFGH\x1b[2;1HIJKLMNOP\x1b[3;3H" ++ image ++ "\x1b[2;3H\x1b[6 q");
        // The graphics upload has its own acknowledged reply. Drain only
        // that acknowledgement, then retain DSR 5 as the FIFO sentinel.
        try terminal.consumeReplyBytes(terminal.replyBytes().len);
        try feed(&terminal, "\x1b[5n");
        const before = view(&terminal);
        try std.testing.expectEqual(.bar, before.cursor_shape);
        try std.testing.expect(!before.cursor_blink);
        try std.testing.expectEqualStrings("\x1b[0n", terminal.replyBytes());
        const seq = terminal.semanticSequence();
        const edit = terminal.observation().structuralEditGeneration();
        const cells = [_]@TypeOf(before.cellInfoAt(0, 0)){
            before.cellInfoAt(0, 0), before.cellInfoAt(1, 1),
            before.cellInfoAt(1, 4), before.cellInfoAt(2, 0),
        };
        const graphics = terminal.images(0);
        try std.testing.expectEqual(@as(usize, 1), graphics.placementCount());
        const placement = graphics.placement(0).?;
        const image_count = graphics.imageCount();
        const generation = graphics.generation;
        const content_generation = graphics.content_generation;

        try std.testing.expect(!(try terminal.feed(invalid[0 .. invalid.len - 1])).stateChanged());
        try std.testing.expect(!(try terminal.feed(invalid[invalid.len - 1 ..])).stateChanged());
        const after = view(&terminal);
        try std.testing.expectEqual(seq, terminal.semanticSequence());
        try std.testing.expectEqual(before.cursor_row, after.cursor_row);
        try std.testing.expectEqual(before.cursor_col, after.cursor_col);
        try std.testing.expectEqual(before.cursor_shape, after.cursor_shape);
        try std.testing.expectEqual(before.cursor_blink, after.cursor_blink);
        try std.testing.expectEqual(before.history_count, after.history_count);
        try std.testing.expectEqual(edit, terminal.observation().structuralEditGeneration());
        try std.testing.expectEqualDeep(cells[0], after.cellInfoAt(0, 0));
        try std.testing.expectEqualDeep(cells[1], after.cellInfoAt(1, 1));
        try std.testing.expectEqualDeep(cells[2], after.cellInfoAt(1, 4));
        try std.testing.expectEqualDeep(cells[3], after.cellInfoAt(2, 0));
        try std.testing.expectEqual(image_count, terminal.images(0).imageCount());
        try std.testing.expectEqual(@as(usize, 1), terminal.images(0).placementCount());
        try std.testing.expectEqual(placement.row, terminal.images(0).placement(0).?.row);
        try std.testing.expectEqual(placement.col, terminal.images(0).placement(0).?.col);
        try std.testing.expectEqual(generation, terminal.images(0).generation);
        try std.testing.expectEqual(content_generation, terminal.images(0).content_generation);
        try std.testing.expectEqualStrings("\x1b[0n", terminal.replyBytes());

        // The invalid control cannot poison the next valid style change
        // or consume the already staged status reply.
        try std.testing.expect((try terminal.feed("\x1b[3 q")).stateChanged());
        try std.testing.expectEqual(.underline, view(&terminal).cursor_shape);
        try std.testing.expect(view(&terminal).cursor_blink);
        try std.testing.expectEqualStrings("\x1b[0n", terminal.replyBytes());
    }

    // Legal one-count and final-empty forms still admit Kitty's ordinary
    // style values, including the caller-selected default for zero.
    for ([_]struct { bytes: []const u8, shape: Terminal.CursorShape, blink: bool }{
        .{ .bytes = "\x1b[ q", .shape = .block, .blink = true },
        .{ .bytes = "\x1b[0 q", .shape = .block, .blink = true },
        .{ .bytes = "\x1b[0; q", .shape = .block, .blink = true },
        .{ .bytes = "\x1b[3 q", .shape = .underline, .blink = true },
        .{ .bytes = "\x1b[3; q", .shape = .underline, .blink = true },
        .{ .bytes = "\x9b4 q", .shape = .underline, .blink = false },
        .{ .bytes = "\x1b[5 q", .shape = .bar, .blink = true },
        .{ .bytes = "\x1b[6 q", .shape = .bar, .blink = false },
    }) |case| {
        var terminal = try Terminal.init(std.testing.allocator, 2, 8);
        defer terminal.deinit();
        try feed(&terminal, "\x1b[6 q");
        try feed(&terminal, case.bytes);
        try std.testing.expectEqual(case.shape, view(&terminal).cursor_shape);
        try std.testing.expectEqual(case.blink, view(&terminal).cursor_blink);
    }

    // A rejected style control must not consume pending right-edge wrap.
    for ([_][]const u8{ "\x1b[3;6 q", "\x9b3;6 q" }) |invalid| {
        var terminal = try Terminal.init(std.testing.allocator, 2, 8);
        defer terminal.deinit();
        try feed(&terminal, "\x1b[1;8H!");
        const seq = terminal.semanticSequence();
        try std.testing.expect(!(try terminal.feed(invalid)).stateChanged());
        try std.testing.expectEqual(seq, terminal.semanticSequence());
        try feed(&terminal, "X");
        try std.testing.expectEqual(@as(u21, '!'), view(&terminal).cellAt(0, 7));
        try std.testing.expectEqual(@as(u21, 'X'), view(&terminal).cellAt(1, 0));
    }
}

test "terminal cursor: Kitty multiple-cursor forms are exact unsupported no-ops" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 4);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b[4 q")).stateChanged());
    const before = view(&terminal);
    try std.testing.expect(!(try terminal.feed("\x1b[>100;29:2:1")).stateChanged());
    try std.testing.expect(!(try terminal.feed(":2 q\x1b[> q")).stateChanged());
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
    )).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1bP@kitty-restore-cursor\x18")).stateChanged());
    try std.testing.expectEqual(.underline, view(&terminal).cursor_shape);
    try std.testing.expect(!view(&terminal).cursor_visible);
    try std.testing.expect(!(try terminal.feed("\x1bP@kitty-restore-cursor-appe")).stateChanged());
    try std.testing.expect((try terminal.feed("arance|ignored\x1b\\")).stateChanged());

    try std.testing.expectEqual(.block, view(&terminal).cursor_shape);
    try std.testing.expect(view(&terminal).cursor_blink);
    try std.testing.expectEqual(@as(u16, 1), view(&terminal).cursor_row);
    try std.testing.expectEqual(@as(u16, 2), view(&terminal).cursor_col);
    try std.testing.expect(view(&terminal).cursor_visible);
    try std.testing.expectEqual(@as(?Terminal.Rgb, null), terminal.presentation().cursor);
    try std.testing.expect(!(try terminal.feed("\x1bP@kitty-restore-cursor-appearance|\x1b\\")).stateChanged());

    try std.testing.expect((try terminal.feed("\x1b[?47l")).stateChanged());
    try std.testing.expectEqual(.block, view(&terminal).cursor_shape);
    try std.testing.expect((try terminal.feed("\x90@kitty-restore-cursor-appearance|x\x9c")).stateChanged());
    try std.testing.expectEqual(.block, view(&terminal).cursor_shape);
    try std.testing.expect(view(&terminal).cursor_blink);
    try std.testing.expect(!(try terminal.feed("\x1bP@kitty-restore-cursor-appearance|x\x1b\\")).stateChanged());

    // Both screen banks must restore the caller's configured shape/blink,
    // visibility and cursor-color override, not just the factory block style.
    terminal.setDefaultCursorStyle(.{ .shape = .bar, .blink = false });
    try feed(&terminal, "\x1b[2;2H\x1b[3 q\x1b[?25l\x1b]12;#010203\x1b\\");
    try std.testing.expectEqual(.underline, view(&terminal).cursor_shape);
    try std.testing.expect(view(&terminal).cursor_blink);
    try std.testing.expect(!view(&terminal).cursor_visible);
    try std.testing.expect(terminal.presentation().cursor != null);
    try std.testing.expect(!(try terminal.feed("\x1bP@kitty-restore-cursor-appear")).stateChanged());
    try std.testing.expect((try terminal.feed("ance|\x1b\\")).stateChanged());
    try std.testing.expectEqual(.bar, view(&terminal).cursor_shape);
    try std.testing.expect(!view(&terminal).cursor_blink);
    try std.testing.expect(view(&terminal).cursor_visible);
    try std.testing.expectEqual(@as(?Terminal.Rgb, null), terminal.presentation().cursor);
    try std.testing.expectEqual(@as(u16, 1), view(&terminal).cursor_row);
    try std.testing.expectEqual(@as(u16, 1), view(&terminal).cursor_col);
    try std.testing.expect(!(try terminal.feed("\x1bP@kitty-restore-cursor-appearance|\x1b\\")).stateChanged());

    try feed(&terminal, "\x1b[?47h\x1b[1;3H\x1b[6 q\x1b[?25l\x1b]12;#040506\x1b\\");
    try std.testing.expectEqual(.bar, view(&terminal).cursor_shape);
    try std.testing.expect(!view(&terminal).cursor_blink);
    try std.testing.expect(!view(&terminal).cursor_visible);
    try std.testing.expect((try terminal.feed("\x90@kitty-restore-cursor-appearance|\x9c")).stateChanged());
    try std.testing.expectEqual(.bar, view(&terminal).cursor_shape);
    try std.testing.expect(!view(&terminal).cursor_blink);
    try std.testing.expect(view(&terminal).cursor_visible);
    try std.testing.expectEqual(@as(?Terminal.Rgb, null), terminal.presentation().cursor);
    try std.testing.expectEqual(@as(u16, 0), view(&terminal).cursor_row);
    try std.testing.expectEqual(@as(u16, 2), view(&terminal).cursor_col);
    try feed(&terminal, "\x1b[?47l");
    try std.testing.expectEqual(.bar, view(&terminal).cursor_shape);
    try std.testing.expect(!view(&terminal).cursor_blink);
}

test "terminal cursor: savepoint restores presentation while caller colors remain current" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed(
        "\x1b[?5h\x1b[?6h\x1b[?7l\x1b[?25l\x1b[3;6H\x1b[6 q\x1b[1m" ++
            "\x1b]12;#112233\x1b\\\x1b]21;cursor_text=#445566\x1b\\\x1b)0\x1b7",
    )).stateChanged());
    try std.testing.expect((try terminal.feed(
        "\x1b[1;1H\x1b[1 q\x1b[22m\x1b[?5l\x1b[?6l\x1b[?7h\x1b[?25h" ++
            "\x1b]12;#010203\x1b\\\x1b]21;cursor_text=#040506\x1b\\\x1b)B\x1b8X",
    )).stateChanged());

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

    try std.testing.expect(!(try terminal.feed("\x1b[6 ")).stateChanged());
    try std.testing.expect((try terminal.feed("q")).stateChanged());
    try std.testing.expectEqual(.bar, view(&terminal).cursor_shape);
    try std.testing.expect(!view(&terminal).cursor_blink);
    try std.testing.expect(!(try terminal.feed("\x1b[6 q")).stateChanged());

    try std.testing.expect((try terminal.feed("\x1b[?12h\x1b[?25l")).stateChanged());
    try std.testing.expect(view(&terminal).cursor_blink);
    try std.testing.expect(!view(&terminal).cursor_visible);
    try std.testing.expect(!(try terminal.feed("\x1b[?12h\x1b[?25l")).stateChanged());

    try std.testing.expect((try terminal.feed("\x1b[?12;25s")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[?12l\x1b[?25h")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[?12;25r")).stateChanged());
    try std.testing.expect(view(&terminal).cursor_blink);
    try std.testing.expect(!view(&terminal).cursor_visible);
    try std.testing.expect((try terminal.feed("\x1b[?12$p\x1b[?25$p")).stateChanged());
    try std.testing.expectEqualStrings("\x1b[?12;1$y\x1b[?25;2$y", terminal.replyBytes());
    try terminal.consumeReplyBytes(terminal.replyBytes().len);

    try std.testing.expect((try terminal.feed("\x1b[?47h")).stateChanged());
    try std.testing.expectEqual(.block, view(&terminal).cursor_shape);
    try std.testing.expect(view(&terminal).cursor_blink);
    try std.testing.expect(!view(&terminal).cursor_visible);
    try std.testing.expect((try terminal.feed("\x1b[?12l")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[?25l")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[?47l")).stateChanged());
    try std.testing.expectEqual(.bar, view(&terminal).cursor_shape);
    try std.testing.expect(view(&terminal).cursor_blink);
    try std.testing.expect(!view(&terminal).cursor_visible);

    try terminal.resize(6, 12);
    try std.testing.expectEqual(.bar, view(&terminal).cursor_shape);
    try std.testing.expect(view(&terminal).cursor_blink);
    try std.testing.expect(!view(&terminal).cursor_visible);

    try std.testing.expect((try terminal.feed("\x1b[2 q")).stateChanged());
    try std.testing.expectEqual(.block, view(&terminal).cursor_shape);
    try std.testing.expect(!view(&terminal).cursor_blink);
    try std.testing.expect(!(try terminal.feed("\x1b[2 q")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[?47h\x1b[6 q\x1bc")).stateChanged());
    try std.testing.expect(!view(&terminal).is_alternate_screen);
    try std.testing.expectEqual(@as(u16, 0), view(&terminal).cursor_row);
    try std.testing.expectEqual(@as(u16, 0), view(&terminal).cursor_col);
    try std.testing.expectEqual(.block, view(&terminal).cursor_shape);
    try std.testing.expect(view(&terminal).cursor_blink);
    try std.testing.expect(view(&terminal).cursor_visible);
}
