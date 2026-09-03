const std = @import("std");
const terminal_mod = @import("../../src/howl_vt.zig");

const Terminal = terminal_mod.Terminal;

fn feed(terminal: *Terminal, bytes: []const u8) Terminal.FeedError!void {
    const summary = try terminal.feed(bytes);
    std.debug.assert(!summary.historyLost() or summary.stateChanged());
}

const expected_logical_output_bytes: usize = 1024 * 1024;

test "terminal rejects zero dimensions exactly" {
    try std.testing.expectError(error.InvalidDimensions, Terminal.init(std.testing.allocator, 0, 1));
    try std.testing.expectError(error.InvalidDimensions, Terminal.init(std.testing.allocator, 1, 0));
    try std.testing.expectError(error.InvalidDimensions, Terminal.initWithHistory(std.testing.allocator, 0, 0, 8));
}

test "terminal constructors clean up every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, initTerminal, .{});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, initTerminalWithHistory, .{});
}

fn initTerminal(allocator: std.mem.Allocator) !void {
    var terminal = try Terminal.init(allocator, 2, 3);
    terminal.deinit();
}

fn initTerminalWithHistory(allocator: std.mem.Allocator) !void {
    var terminal = try Terminal.initWithHistory(allocator, 2, 3, 4);
    terminal.deinit();
}

fn feedChanged(terminal: *Terminal, bytes: []const u8) !void {
    const summary = try terminal.feed(bytes);
    try std.testing.expect(summary.stateChanged());
}

test "finalized logical output keeps identity across resize and rejects an evicted cursor" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithHistory(allocator, 2, 8, 3);
    defer terminal.deinit();
    try feedChanged(&terminal, "one\r\ntwo\r\nthree\r\nopen");

    var first = switch (try terminal.copyLogicalOutput(allocator, 0, 8, 128)) {
        .output => |output| output,
        else => return error.UnexpectedOutputResult,
    };
    defer first.deinit();
    try std.testing.expectEqualStrings("one\ntwo\nthree", first.text);
    try std.testing.expectEqualStrings("open", first.open_line);
    try std.testing.expectEqual(@as(u64, 1), first.oldest);
    try std.testing.expectEqual(@as(u64, 3), first.cursor);
    try std.testing.expectEqual(@as(u64, 3), first.newest);

    try terminal.resize(3, 4);
    var resized = switch (try terminal.copyLogicalOutput(allocator, 0, 8, 128)) {
        .output => |output| output,
        else => return error.UnexpectedOutputResult,
    };
    defer resized.deinit();
    try std.testing.expectEqualStrings(first.text, resized.text);
    try std.testing.expectEqual(first.oldest, resized.oldest);
    try std.testing.expectEqual(first.cursor, resized.cursor);

    try feedChanged(&terminal, "\r\nfour\r\nfive\r\nsix");
    switch (try terminal.copyLogicalOutput(allocator, 0, 8, 128)) {
        .cursor_stale => |oldest| try std.testing.expect(oldest > first.oldest),
        else => return error.UnexpectedOutputResult,
    }
}

test "alternate-screen output does not enter finalized primary output" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithHistory(allocator, 2, 8, 4);
    defer terminal.deinit();
    try feedChanged(&terminal, "primary\r\nopen");
    const before = terminal.logicalOutputRange();
    try feedChanged(&terminal, "\x1b[?1049halt-a\r\nalt-b\r\nalt-c\x1b[?1049l");
    const after = terminal.logicalOutputRange();
    try std.testing.expectEqual(before, after);
}

test "open logical output is semantic-observation scoped and does not advance its cursor" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithHistory(allocator, 2, 8, 4);
    defer terminal.deinit();
    try feedChanged(&terminal, "open");
    var first = switch (try terminal.copyLogicalOutput(allocator, 0, 4, 64)) {
        .output => |output| output,
        else => return error.UnexpectedOutputResult,
    };
    defer first.deinit();
    try std.testing.expectEqualStrings("open", first.open_line);
    try std.testing.expectEqual(@as(u64, 0), first.cursor);

    try feedChanged(&terminal, "-line");
    var second = switch (try terminal.copyLogicalOutput(allocator, 0, 4, 64)) {
        .output => |output| output,
        else => return error.UnexpectedOutputResult,
    };
    defer second.deinit();
    try std.testing.expectEqualStrings("open-line", second.open_line);
    try std.testing.expectEqual(first.cursor, second.cursor);
    try std.testing.expect(second.semantic_sequence > first.semantic_sequence);
}

test "logical output preserves external combining scalars" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithHistory(allocator, 3, 8, 4);
    defer terminal.deinit();
    const grapheme = "e\u{0301}\u{0302}\u{0303}\u{0304}";

    try feedChanged(&terminal, grapheme);
    var open = switch (try terminal.copyLogicalOutput(allocator, 0, 4, 64)) {
        .output => |output| output,
        else => return error.UnexpectedOutputResult,
    };
    defer open.deinit();
    try std.testing.expectEqualStrings(grapheme, open.open_line);

    try feedChanged(&terminal, "\r\nnext");
    var finalized = switch (try terminal.copyLogicalOutput(allocator, 0, 4, 64)) {
        .output => |output| output,
        else => return error.UnexpectedOutputResult,
    };
    defer finalized.deinit();
    try std.testing.expectEqualStrings(grapheme, finalized.text);
    try std.testing.expectEqualStrings("next", finalized.open_line);
}

test "logical output identity advances only after retained text allocation succeeds" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var terminal = try Terminal.initWithHistory(failing.allocator(), 2, 8, 4);
    defer terminal.deinit();
    try feedChanged(&terminal, "line");
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, terminal.feed("\r\n"));
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectEqual(@as(u64, 0), terminal.logicalOutputRange().newest);

    failing.fail_index = std.math.maxInt(usize);
    try feedChanged(&terminal, "\n");
    try std.testing.expectEqual(@as(u64, 1), terminal.logicalOutputRange().newest);
}

test "oversized finalized line records loss and terminal continues mutating" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 2, std.math.maxInt(u16), 32);
    defer terminal.deinit();
    var chunk: [64 * 1024]u8 = @splat('x');
    const chunk_count = expected_logical_output_bytes / chunk.len + 1;
    for (0..chunk_count) |_| try feedChanged(&terminal, &chunk);
    switch (try terminal.copyLogicalOutput(
        std.testing.allocator,
        0,
        1,
        expected_logical_output_bytes,
    )) {
        .open_line_too_long => {},
        else => return error.UnexpectedOutputResult,
    }

    try feedChanged(&terminal, "\r\n");
    try feedChanged(&terminal, "ok\r\nnext");
    var output = switch (try terminal.copyLogicalOutput(
        std.testing.allocator,
        0,
        3,
        expected_logical_output_bytes,
    )) {
        .output => |value| value,
        else => return error.UnexpectedOutputResult,
    };
    defer output.deinit();
    try std.testing.expectEqual(@as(u64, 2), output.cursor);
    try std.testing.expectEqualStrings("ok", output.text);
    try std.testing.expectEqualStrings("next", output.open_line);
    try std.testing.expectEqual(@as(usize, 1), output.losses.len);
    try std.testing.expectEqual(@as(u64, 1), output.losses[0].id);
    try std.testing.expectEqual(chunk_count * chunk.len, output.losses[0].byte_count);
    try std.testing.expectEqual(Terminal.LogicalOutputLossReason.line_too_long, output.losses[0].reason);
}

test "text extraction owns exact allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, copyTextAllocation, .{});
}

test "text extraction resolves projected history reverse ranges and bounded copy" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 3, 5, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("1AAAA\r\n2BBBB\r\n3CCCC\r\n4DDDD")).stateChanged());
    const range: Terminal.TextRange = .{
        .start = .{ .row = 1, .col = 1 },
        .end = .{ .row = 0, .col = 0 },
    };
    const copied = try terminal.copyText(std.testing.allocator, range, 16);
    defer std.testing.allocator.free(copied);
    try std.testing.expectEqualStrings("1AAAA\n2B", copied);
    try std.testing.expectError(
        error.TextLimit,
        terminal.copyText(std.testing.allocator, range, copied.len - 1),
    );
}

test "text extraction joins soft-wrapped rows without inventing a newline" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 3);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("ABCDEF")).stateChanged());
    const copied = try terminal.copyText(
        std.testing.allocator,
        .{ .start = .{ .row = 0, .col = 0 }, .end = .{ .row = 1, .col = 2 } },
        6,
    );
    defer std.testing.allocator.free(copied);
    try std.testing.expectEqualStrings("ABCDEF", copied);
}

fn copyTextAllocation(allocator: std.mem.Allocator) !void {
    var terminal = try Terminal.init(allocator, 1, 4);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("COPY")).stateChanged());
    const range: Terminal.TextRange = .{
        .start = .{ .row = 0, .col = 0 },
        .end = .{ .row = 0, .col = 3 },
    };
    const copied = terminal.copyText(allocator, range, std.math.maxInt(usize)) catch |err| {
        try std.testing.expectEqual(@as(u21, 'C'), terminal.semanticView(0).cellAt(0, 0));
        return err;
    };
    defer allocator.free(copied);
    try std.testing.expectEqualStrings("COPY", copied);
}

test "terminal rejects zero resize without changing dimensions" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 3);
    defer terminal.deinit();

    try std.testing.expectError(error.InvalidDimensions, terminal.resize(0, 3));
    const view = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u16, 2), view.rows);
    try std.testing.expectEqual(@as(u16, 3), view.cols);
}

test "terminal tracks synchronized output private mode" {
    var vt = try Terminal.init(std.testing.allocator, 2, 8);
    defer vt.deinit();

    try feed(&vt, "\x1b[?2026h");
    try std.testing.expect(vt.synchronizedOutput());

    try feed(&vt, "\x1b[?2026l");
    try std.testing.expect(!vt.synchronizedOutput());
}

test "stationary cursor movement advances semantic identity" {
    var vt = try Terminal.init(std.testing.allocator, 4, 8);
    defer vt.deinit();

    try std.testing.expect(!(try vt.feed("\x1b[?25h")).stateChanged());
    const before = vt.semanticView(0);
    try std.testing.expect(before.cursor_visible);
    const before_sequence = vt.semanticSequence();

    try std.testing.expect((try vt.feed("\x1b[3;4H")).stateChanged());
    const after = vt.semanticView(0);
    try std.testing.expect(vt.semanticSequence() != before_sequence);
    try std.testing.expectEqual(@as(u16, 2), after.cursor_row);
    try std.testing.expectEqual(@as(u16, 3), after.cursor_col);
}

test "synchronized update DCS shares exact bounded mode state" {
    var vt = try Terminal.init(std.testing.allocator, 2, 8);
    defer vt.deinit();

    try std.testing.expect(!(try vt.feed("\x1bP=1sbody")).stateChanged());
    try std.testing.expect(!vt.synchronizedOutput());
    try std.testing.expect((try vt.feed("\x1b\\")).stateChanged());
    try std.testing.expect(vt.synchronizedOutput());
    try std.testing.expect(!(try vt.feed("\x90=1s\x9c")).stateChanged());

    try std.testing.expect(!(try vt.feed(
        "\x1bP=3s\x1b\\\x1bP=1;2s\x1b\\\x1bP=s\x1b\\\x1bP=1q\x1b\\\x1bP?1s\x1b\\",
    )).stateChanged());
    try std.testing.expect(vt.synchronizedOutput());
    try std.testing.expect((try vt.feed("\x90=2signored\x9c")).stateChanged());
    try std.testing.expect(!vt.synchronizedOutput());
    try std.testing.expect(!(try vt.feed("\x1bP=2s\x1b\\")).stateChanged());

    try std.testing.expect((try vt.feed("\x1b[?2026h\x1b[?2026s\x1bP=2s\x1b\\")).stateChanged());
    try std.testing.expect(!vt.synchronizedOutput());
    try std.testing.expect((try vt.feed("\x1b[?2026r")).stateChanged());
    try std.testing.expect(vt.synchronizedOutput());
    try std.testing.expect((try vt.feed("\x1b[?2026$p")).stateChanged());
    try std.testing.expectEqualStrings("\x1b[?2026;1$y", vt.replyBytes());
    try vt.consumeReplyBytes(vt.replyBytes().len);
    try std.testing.expect((try vt.feed("\x1bc")).stateChanged());
    try std.testing.expect(!vt.synchronizedOutput());
}

test "terminal visible view projects scrollback rows" {
    var vt = try Terminal.initWithHistory(std.testing.allocator, 2, 2, 4);
    defer vt.deinit();

    try feed(&vt, "aa\r\nbb\r\ncc");

    const live = vt.semanticView(0);
    try std.testing.expectEqual(0, live.history_offset);
    try std.testing.expectEqual(@as(u21, 'b'), live.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'c'), live.cellAt(1, 0));

    const scrolled = vt.semanticView(1);
    try std.testing.expectEqual(1, scrolled.history_offset);
    try std.testing.expectEqual(@as(u21, 'a'), scrolled.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), scrolled.cellAt(1, 0));
    try std.testing.expectEqual(2, scrolled.rowDepth(0));
    try std.testing.expectEqual(1, scrolled.rowDepth(1));
}

test "terminal Kitty unscroll consumes primary history in row order" {
    var vt = try Terminal.initWithHistory(std.testing.allocator, 3, 4, 8);
    defer vt.deinit();

    try std.testing.expect((try vt.feed("aaaa\r\nbbbb\r\ncccc\r\ndddd\r\neeee")).stateChanged());
    try std.testing.expectEqual(@as(u32, 2), vt.semanticView(0).history_count);
    try feedChanged(&vt, "\x1b[2;3H");

    try std.testing.expect((try vt.feed("\x1b[2+T")).stateChanged());
    try std.testing.expectEqual(@as(u32, 0), vt.semanticView(0).history_count);
    try std.testing.expectEqual(@as(u21, 'a'), vt.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), vt.semanticView(0).cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'c'), vt.semanticView(0).cellAt(2, 0));
    try std.testing.expectEqual(@as(u16, 1), vt.semanticView(0).cursor_row);
    try std.testing.expectEqual(@as(u16, 2), vt.semanticView(0).cursor_col);

    try vt.resize(3, 2);
    try std.testing.expectEqual(@as(u32, 3), vt.semanticView(0).history_count);
    const resized = vt.semanticView(3);
    try std.testing.expectEqual(@as(u21, 'a'), resized.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), resized.cellAt(2, 0));
}

test "terminal Kitty unscroll fragments and preserves alternate history" {
    var vt = try Terminal.initWithHistory(std.testing.allocator, 2, 3, 4);
    defer vt.deinit();

    try feedChanged(&vt, "aaa\r\nbbb\r\nccc");
    try std.testing.expectEqual(@as(u32, 1), vt.semanticView(0).history_count);
    try feedChanged(&vt, "\x1b[?1049hxxx");
    try std.testing.expect(!(try vt.feed("\x1b[")).stateChanged());
    try std.testing.expect((try vt.feed("+T")).stateChanged());
    try std.testing.expectEqual(@as(u21, 0), vt.semanticView(0).cellAt(0, 0));
    try feedChanged(&vt, "\x1b[?1049l\x1b[999999+T");
    try std.testing.expectEqual(@as(u32, 0), vt.semanticView(0).history_count);
    try std.testing.expectEqual(@as(u21, 0), vt.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'a'), vt.semanticView(0).cellAt(1, 0));
}

test "terminal Kitty unscroll preserves logical authority and cell state" {
    var vt = try Terminal.initWithHistory(std.testing.allocator, 2, 4, 2);
    defer vt.deinit();

    try feedChanged(&vt, "\x1b[31mAAAA\r\n1111\r\n2222");
    try std.testing.expectEqual(@as(u32, 1), vt.semanticView(0).history_count);
    try std.testing.expectEqual(@as(u21, 'A'), vt.semanticView(1).cellAt(0, 0));
    try std.testing.expect((try vt.feed("\x1b[+T")).stateChanged());
    try std.testing.expectEqual(@as(u32, 0), vt.semanticView(0).history_count);
    try std.testing.expectEqual(@as(u21, 'A'), vt.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(
        Terminal.Color.indexed(1),
        vt.semanticView(0).cellInfoAt(0, 0).attrs.fg,
    );

    try vt.resize(2, 2);
    try std.testing.expectEqual(@as(u32, 2), vt.semanticView(0).history_count);
    const resized = vt.semanticView(2);
    try std.testing.expectEqual(@as(u21, 'A'), resized.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'A'), resized.cellAt(1, 1));
}

test "terminal Kitty unscroll consumes wrapped history ring authority" {
    var vt = try Terminal.initWithHistory(std.testing.allocator, 2, 2, 2);
    defer vt.deinit();

    try feedChanged(&vt, "aa\r\nbb\r\ncc\r\ndd\r\nee");
    try std.testing.expectEqual(@as(u32, 2), vt.semanticView(0).history_count);
    const retained = vt.semanticView(2);
    try std.testing.expectEqual(@as(u21, 'b'), retained.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'c'), retained.cellAt(1, 0));

    try feedChanged(&vt, "\x1b[+T");
    try std.testing.expectEqual(@as(u32, 1), vt.semanticView(0).history_count);
    try feedChanged(&vt, "\x1b[2;1Hzz\r\n");
    try std.testing.expectEqual(@as(u32, 2), vt.semanticView(0).history_count);

    try feedChanged(&vt, "\x1b[2+T");
    try std.testing.expectEqual(@as(u32, 0), vt.semanticView(0).history_count);
    try std.testing.expectEqual(@as(u21, 'b'), vt.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'c'), vt.semanticView(0).cellAt(1, 0));

    try vt.resize(2, 1);
    try std.testing.expectEqual(@as(u32, 2), vt.semanticView(0).history_count);
    const resized = vt.semanticView(2);
    try std.testing.expectEqual(@as(u21, 'b'), resized.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), resized.cellAt(1, 0));
}

test "terminal Kitty unscroll consumes newest rows of one wrapped line" {
    var vt = try Terminal.initWithHistory(std.testing.allocator, 2, 3, 4);
    defer vt.deinit();

    try feedChanged(&vt, "abcdefghij");
    try std.testing.expectEqual(@as(u32, 2), vt.semanticView(0).history_count);

    try feedChanged(&vt, "\x1b[+T");
    try std.testing.expectEqual(@as(u32, 1), vt.semanticView(0).history_count);
    try std.testing.expectEqual(@as(u21, 'd'), vt.semanticView(0).cellAt(0, 0));

    try feedChanged(&vt, "\x1b[+T");
    try std.testing.expectEqual(@as(u32, 0), vt.semanticView(0).history_count);
    try std.testing.expectEqual(@as(u21, 'a'), vt.semanticView(0).cellAt(0, 0));
}

test "terminal RIS delegates hard-reset owners" {
    var vt = try Terminal.init(std.testing.allocator, 2, 8);
    defer vt.deinit();

    try std.testing.expect((try vt.feed("ab\x1b[1;0'z\x1b[1'*{")).stateChanged());
    var scratch: Terminal.InputScratch = .{};
    var before = try vt.encodeInput(
        std.testing.allocator,
        &scratch,
        .{ .mouse = .{
            .kind = .press,
            .button = .left,
            .row = 0,
            .col = 0,
            .mod = .{},
            .buttons_down = 1,
        } },
    );
    defer before.deinit();
    try std.testing.expectEqual(@as(usize, 0), before.bytes.len);
    try std.testing.expect(vt.replyBytes().len != 0);
    try vt.consumeReplyBytes(vt.replyBytes().len);

    try std.testing.expect((try vt.feed("\x1bc")).stateChanged());

    try std.testing.expectEqual(@as(u21, 0), vt.semanticView(0).cellAt(0, 0));
    var after = try vt.encodeInput(
        std.testing.allocator,
        &scratch,
        .{ .mouse = .{
            .kind = .press,
            .button = .left,
            .row = 0,
            .col = 0,
            .mod = .{},
            .buttons_down = 1,
        } },
    );
    defer after.deinit();
    try std.testing.expectEqual(@as(usize, 0), after.bytes.len);
    try std.testing.expectEqual(@as(usize, 0), vt.replyBytes().len);
}

test "terminal DECSTR preserves text and position while resetting terminal state" {
    var vt = try Terminal.init(std.testing.allocator, 4, 16);
    defer vt.deinit();

    try feed(&vt, "kept\x1b[2;9H\x1b[3g\x1b[?1;6;25;1000;1004;1006;2004h\x1b#6");
    try feed(&vt, "\x1b[4;20h\x1b(B\x1b)0\x1b G");
    const row_before = vt.semanticView(0).cursor_row;
    const col_before = vt.semanticView(0).cursor_col;
    try std.testing.expect(vt.semanticView(0).lineGeometry(row_before) == .double_width);
    try std.testing.expect((try vt.feed("\x1b[5n")).stateChanged());
    try std.testing.expectEqualStrings("\x9b0n", vt.replyBytes());
    try vt.consumeReplyBytes(vt.replyBytes().len);

    const prefix = try vt.feed("\x1b[!");
    try std.testing.expect(!prefix.stateChanged());
    const reset = try vt.feed("p");
    try std.testing.expect(reset.stateChanged());

    var view = vt.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'k'), view.cellAt(0, 0));
    try std.testing.expectEqual(row_before, view.cursor_row);
    try std.testing.expectEqual(col_before, view.cursor_col);
    try std.testing.expectEqual(Terminal.LineGeometry.single_width, view.lineGeometry(row_before));
    try std.testing.expect(view.cursor_visible);
    try std.testing.expect((try vt.feed("\x1b[5n")).stateChanged());
    try std.testing.expectEqualStrings("\x1b[0n", vt.replyBytes());
    const repeated = try vt.feed("\x1b[!p");
    try std.testing.expect(!repeated.stateChanged());

    try std.testing.expect((try vt.feed("\x0eq")).stateChanged());
    view = vt.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'q'), view.cellAt(row_before, col_before));
}

test "terminal DECSTR resets mirrored modes across alternate-screen banks" {
    var vt = try Terminal.init(std.testing.allocator, 3, 12);
    defer vt.deinit();

    try std.testing.expect((try vt.feed(
        "ABC\x1b[1;1H\x1b[4h\x1b[?69h\x1b[?25l\x1b[?47hDEF\x1b[1;1H",
    )).stateChanged());
    try std.testing.expect(!vt.semanticView(0).cursor_visible);

    try std.testing.expect((try vt.feed("\x1b[!p")).stateChanged());
    try std.testing.expect(vt.semanticView(0).cursor_visible);
    try std.testing.expect(!(try vt.feed("\x1b[!p")).stateChanged());

    try std.testing.expect((try vt.feed("X\x1b[?47l\x1b[1;1HX")).stateChanged());
    var view = vt.semanticView(0);
    try std.testing.expect(view.cursor_visible);
    try std.testing.expectEqual(@as(u21, 'X'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), view.cellAt(0, 1));
    try std.testing.expect((try vt.feed("\x1b[?47h")).stateChanged());
    view = vt.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'X'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'E'), view.cellAt(0, 1));
}

test "terminal save reset and alternate lifecycle stays coherent across resize and bank changes" {
    var vt = try Terminal.init(std.testing.allocator, 4, 8);
    defer vt.deinit();

    // Save a primary cursor at the old edge with rendition and charset state
    // that must survive an alternate-bank soft reset and a narrower resize.
    try std.testing.expect((try vt.feed(
        "PRIMARY\x1b[4;8H\x1b[1;3m\x1b)0\x0e\x1b[?5h\x1b[?1049h",
    )).stateChanged());
    try std.testing.expect(vt.semanticView(0).is_alternate_screen);
    try std.testing.expectEqual(@as(u21, 0), vt.semanticView(0).cellAt(0, 0));

    // DECSTR is active-bank-local for row state and terminal-global for the
    // mirrored input, margin, and visibility state owned by Terminal.
    try std.testing.expect((try vt.feed(
        "ALT\x1b[4h\x1b[?25l\x1b[?69h\x1b[2;5s\x1b[3;4H\x1b[!p",
    )).stateChanged());
    var view = vt.semanticView(0);
    try std.testing.expect(view.is_alternate_screen);
    try std.testing.expectEqual(@as(u21, 'A'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u16, 2), view.cursor_row);
    try std.testing.expectEqual(@as(u16, 3), view.cursor_col);
    try std.testing.expect(view.cursor_visible);
    try std.testing.expect(!(try vt.feed("\x1b[!p")).stateChanged());

    try vt.resize(2, 4);
    try std.testing.expect((try vt.feed("\x1b[?1049l")).stateChanged());
    view = vt.semanticView(0);
    try std.testing.expect(!view.is_alternate_screen);
    try std.testing.expectEqual(@as(u16, 1), view.cursor_row);
    try std.testing.expectEqual(@as(u16, 3), view.cursor_col);
    try std.testing.expect(vt.presentation().reverse_screen);
    try std.testing.expect((try vt.feed("q")).stateChanged());
    const saved = vt.semanticView(0).cellInfoAt(1, 3);
    try std.testing.expectEqual(@as(u21, 0x2500), @as(u21, @intCast(saved.codepoint)));
    try std.testing.expect(saved.attrs.bold);
    try std.testing.expect(saved.attrs.italic);

    // RIS resets the selected bank and all terminal-global save state without
    // inventing an implicit screen switch or erasing the inactive bank.
    try std.testing.expect((try vt.feed("\x1b[HKEEP\x1b[?47hALT2\x1b7\x1bc")).stateChanged());
    view = vt.semanticView(0);
    try std.testing.expect(view.is_alternate_screen);
    try std.testing.expectEqual(@as(u21, 0), view.cellAt(0, 0));
    try std.testing.expect(!vt.presentation().reverse_screen);

    try std.testing.expect((try vt.feed("\x1b[?47l\x1b8")).stateChanged());
    view = vt.semanticView(0);
    try std.testing.expect(!view.is_alternate_screen);
    try std.testing.expectEqual(@as(u21, 'K'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u16, 0), view.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), view.cursor_col);
    try std.testing.expect((try vt.feed("X")).stateChanged());
    const restored = vt.semanticView(0).cellInfoAt(0, 0);
    try std.testing.expect(restored.attrs.bold);
    try std.testing.expect(restored.attrs.italic);
}

test "service-bounded feed stops exactly at child replies and host consequences" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 16);
    defer terminal.deinit();

    const reply_input = "ABC\x1b[5nDEF";
    const reply = try terminal.feedAtServiceBoundary(reply_input, 11);
    try std.testing.expectEqual(@as(usize, 7), reply.consumed);
    try std.testing.expect(reply.summary.stateChanged());
    try std.testing.expect(terminal.replyBytes().len != 0);
    try std.testing.expectEqual(@as(u21, 'A'), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'C'), terminal.semanticView(0).cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(0, 3));

    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    const reply_tail = try terminal.feedAtServiceBoundary(reply_input[reply.consumed..], 12);
    try std.testing.expectEqual(@as(usize, 3), reply_tail.consumed);
    try std.testing.expectEqual(@as(u21, 'F'), terminal.semanticView(0).cellAt(0, 5));

    const consequence_input = "GHI\x07JKL";
    const consequence = try terminal.feedAtServiceBoundary(consequence_input, 13);
    try std.testing.expectEqual(@as(usize, 4), consequence.consumed);
    try std.testing.expectEqual(@as(u16, 1), terminal.consequenceCount());
    try std.testing.expectEqual(@as(u21, 'I'), terminal.semanticView(0).cellAt(0, 8));
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(0, 9));

    const pending = terminal.consequenceHead() orelse return error.TestUnexpectedResult;
    try terminal.consumeConsequence(pending.id());
    const consequence_tail = try terminal.feedAtServiceBoundary(
        consequence_input[consequence.consumed..],
        14,
    );
    try std.testing.expectEqual(@as(usize, 3), consequence_tail.consumed);
    try std.testing.expectEqual(@as(u21, 'L'), terminal.semanticView(0).cellAt(0, 11));
}

test "service-bounded feed consumes ordinary slices as one transaction" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 16);
    defer terminal.deinit();

    const progress = try terminal.feedAtServiceBoundary("ordinary-output", 17);
    try std.testing.expectEqual(@as(usize, 15), progress.consumed);
    try std.testing.expect(progress.summary.stateChanged());
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
    try std.testing.expectEqual(@as(usize, 0), terminal.replyBytes().len);
}
