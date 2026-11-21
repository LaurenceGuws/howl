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

test "logical output copy releases every caller allocation failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        copyLogicalOutputAllocation,
        .{},
    );
}

fn copyLogicalOutputAllocation(allocator: std.mem.Allocator) !void {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 2, 8, 4);
    defer terminal.deinit();
    try feedChanged(&terminal, "one\r\ntwo\r\nopen");

    // Force the moving/shrinking fallback: whether the backing allocator can
    // remap in place varies with heap layout and otherwise changes the number
    // of alloc calls between failure trials. All fallback allocations still
    // pass through the injected allocator and must unwind on failure.
    var moving = std.testing.FailingAllocator.init(allocator, .{ .resize_fail_index = 0 });
    var output = switch (try terminal.copyLogicalOutput(moving.allocator(), 0, 4, 128)) {
        .output => |value| value,
        else => return error.UnexpectedOutputResult,
    };
    output.deinit();
}

test "logical output finalization is allocation-free after initialization" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var terminal = try Terminal.initWithHistory(failing.allocator(), 2, 8, 4);
    defer terminal.deinit();
    try feedChanged(&terminal, "line");

    failing.fail_index = failing.alloc_index;
    try feedChanged(&terminal, "\r\n");
    try std.testing.expect(!failing.has_induced_failure);
    try std.testing.expectEqual(@as(u64, 1), terminal.logicalOutputRange().newest);
    failing.fail_index = std.math.maxInt(usize);
}

test "line feed retains history and unread input across OOM" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var terminal = try Terminal.initWithHistory(failing.allocator(), 2, 4, 8);
    defer terminal.deinit();
    const input = "AAAA\r\nBBBB\r\nC";
    failing.fail_index = failing.alloc_index;
    const blocked = try terminal.feedAtServiceBoundary(input, 1);
    try std.testing.expectEqual(@as(usize, input.len - 1), blocked.consumed);
    try std.testing.expectEqual(error.OutOfMemory, blocked.input_blocked.?);
    try std.testing.expect(!blocked.summary.historyLost());
    try std.testing.expectEqual(@as(u32, 0), terminal.semanticView(0).history_count);
    try std.testing.expectEqual(@as(u21, 'A'), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), terminal.semanticView(0).cellAt(1, 0));
    const stalled = try terminal.feedAtServiceBoundary(input[blocked.consumed..], 2);
    try std.testing.expectEqual(@as(usize, 0), stalled.consumed);
    try std.testing.expectEqual(error.OutOfMemory, stalled.input_blocked.?);
    failing.fail_index = std.math.maxInt(usize);
    const recovered = try terminal.feedAtServiceBoundary(input[blocked.consumed..], 3);
    try std.testing.expectEqual(@as(usize, 1), recovered.consumed);
    try std.testing.expect(recovered.input_blocked == null);
    try std.testing.expect(!recovered.summary.historyLost());
    try std.testing.expectEqual(@as(u32, 1), terminal.semanticView(0).history_count);
    try std.testing.expectEqual(@as(u21, 'A'), terminal.semanticView(1).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'C'), terminal.semanticView(0).cellAt(1, 0));
}

test "warm lazy history turnover is allocation free at stable payload shape" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var terminal = try Terminal.initWithHistory(failing.allocator(), 29, 117, 512);
    defer terminal.deinit();

    var line = std.ArrayList(u8).empty;
    defer line.deinit(std.testing.allocator);
    for (0..19) |_| try line.appendSlice(
        std.testing.allocator,
        "e\u{0300}\u{0301}\u{0302}\u{0303}\u{0304}\u{0305}",
    );
    try line.appendSlice(std.testing.allocator, "\r\n");

    // Fill the logical store and rotate another complete capacity so each
    // segmented stream has already observed its stable alignment high-water.
    for (0..1053) |_| {
        const summary = try terminal.feed(line.items);
        try std.testing.expect(summary.stateChanged());
        try std.testing.expect(!summary.historyLost());
    }
    try std.testing.expectEqual(@as(u32, 512), terminal.semanticView(0).history_count);

    failing.fail_index = failing.alloc_index;
    for (0..1024) |_| {
        const summary = try terminal.feed(line.items);
        try std.testing.expect(summary.stateChanged());
        try std.testing.expect(!summary.historyLost());
    }
    try std.testing.expect(!failing.has_induced_failure);
    failing.fail_index = std.math.maxInt(usize);
}

test "evicted projected cells never return while current output remains exact" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithHistory(allocator, 2, 2, 4);
    defer terminal.deinit();
    const payload = "abcdefghijklmnopqrst";

    try feedChanged(&terminal, payload);
    var narrow_output = switch (try terminal.copyLogicalOutput(allocator, 0, 4, 64)) {
        .output => |value| value,
        else => return error.UnexpectedOutputResult,
    };
    defer narrow_output.deinit();
    try std.testing.expectEqualStrings(payload, narrow_output.open_line);
    try std.testing.expectEqual(@as(u32, 4), terminal.semanticView(0).history_count);

    try terminal.resize(2, 20);
    const widened = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u32, 0), widened.history_count);
    try std.testing.expectEqual(@as(u21, 'i'), widened.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 't'), widened.cellAt(0, 11));
    try std.testing.expectEqual(@as(u21, 0), widened.cellAt(0, 12));

    var wide_output = switch (try terminal.copyLogicalOutput(allocator, 0, 4, 64)) {
        .output => |value| value,
        else => return error.UnexpectedOutputResult,
    };
    defer wide_output.deinit();
    try std.testing.expectEqualStrings(payload, wide_output.open_line);
}

test "reverse history selects the exact bounded current semantic line" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithHistory(allocator, 2, 2, 2);
    defer terminal.deinit();

    try feedChanged(&terminal, "abcdefghijkl");
    var initial = switch (try terminal.copyLogicalOutput(allocator, 0, 4, 64)) {
        .output => |value| value,
        else => return error.UnexpectedOutputResult,
    };
    defer initial.deinit();
    try std.testing.expectEqualStrings("abcdefghijkl", initial.open_line);

    try feedChanged(&terminal, "\x1b[+T");
    var once = switch (try terminal.copyLogicalOutput(allocator, 0, 4, 64)) {
        .output => |value| value,
        else => return error.UnexpectedOutputResult,
    };
    defer once.deinit();
    try std.testing.expectEqualStrings("abcdefghij", once.open_line);

    try feedChanged(&terminal, "\x1b[+T");
    var twice = switch (try terminal.copyLogicalOutput(allocator, 0, 4, 64)) {
        .output => |value| value,
        else => return error.UnexpectedOutputResult,
    };
    defer twice.deinit();
    try std.testing.expectEqualStrings("abcdefgh", twice.open_line);

    try terminal.resize(2, 8);
    const widened = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'e'), widened.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'h'), widened.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 0), widened.cellAt(0, 4));
    var wide_output = switch (try terminal.copyLogicalOutput(allocator, 0, 4, 64)) {
        .output => |value| value,
        else => return error.UnexpectedOutputResult,
    };
    defer wide_output.deinit();
    try std.testing.expectEqualStrings("abcdefgh", wide_output.open_line);
}

test "clear scrollback drops cells but preserves bounded current output evidence" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithHistory(allocator, 2, 2, 2);
    defer terminal.deinit();

    try feedChanged(&terminal, "abcdefghijkl");
    try feedChanged(&terminal, "\x1b[3J");
    const cleared = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u32, 0), cleared.history_count);
    try std.testing.expectEqual(@as(u21, 'i'), cleared.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'l'), cleared.cellAt(1, 1));

    var output = switch (try terminal.copyLogicalOutput(allocator, 0, 4, 64)) {
        .output => |value| value,
        else => return error.UnexpectedOutputResult,
    };
    defer output.deinit();
    try std.testing.expectEqualStrings("abcdefghijkl", output.open_line);

    try terminal.resize(2, 8);
    const widened = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'i'), widened.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'l'), widened.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 0), widened.cellAt(0, 4));
    var wide_output = switch (try terminal.copyLogicalOutput(allocator, 0, 4, 64)) {
        .output => |value| value,
        else => return error.UnexpectedOutputResult,
    };
    defer wide_output.deinit();
    try std.testing.expectEqualStrings("abcdefghijkl", wide_output.open_line);
}

test "evicted external scalar cells remain output evidence but never reflow" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithHistory(allocator, 2, 2, 2);
    defer terminal.deinit();
    const early = "a\u{0301}\u{0302}\u{0303}\u{0304}";
    const late = "b\u{0311}\u{0312}\u{0313}\u{0314}";
    const payload = early ++ early ++ late ++ late ++ late ++ late ++ late ++ late ++ late ++ late;

    try feedChanged(&terminal, payload);
    var narrow_output = switch (try terminal.copyLogicalOutput(allocator, 0, 4, 256)) {
        .output => |value| value,
        else => return error.UnexpectedOutputResult,
    };
    defer narrow_output.deinit();
    try std.testing.expectEqualStrings(payload, narrow_output.open_line);

    try terminal.resize(2, 8);
    const widened = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'b'), widened.cellAt(0, 0));
    var scalars: [24]u21 = undefined;
    try std.testing.expectEqualSlices(
        u21,
        &.{ 'b', 0x0311, 0x0312, 0x0313, 0x0314 },
        widened.cellScalarsAt(0, 0, &scalars),
    );
    var col: u16 = 0;
    while (col < widened.cols) : (col += 1) {
        try std.testing.expect(widened.cellAt(0, col) != 'a');
    }

    var wide_output = switch (try terminal.copyLogicalOutput(allocator, 0, 4, 256)) {
        .output => |value| value,
        else => return error.UnexpectedOutputResult,
    };
    defer wide_output.deinit();
    try std.testing.expectEqualStrings(payload, wide_output.open_line);
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

test "text extraction rejects evicted or out of bounds ranges instead of copying a partial survivor" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 2, 4, 1);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("ONE\r\nTWO\r\nTHREE")).stateChanged());
    const view = terminal.semanticView(0);
    try std.testing.expect(view.history_row_base > 0);
    try std.testing.expectError(
        error.InvalidRange,
        terminal.copyText(
            std.testing.allocator,
            .{ .start = .{ .row = 0, .col = 0 }, .end = .{ .row = 2, .col = 2 } },
            64,
        ),
    );
    try std.testing.expectError(
        error.InvalidRange,
        terminal.copyText(
            std.testing.allocator,
            .{ .start = .{ .row = @intCast(view.history_row_base), .col = 4 }, .end = .{ .row = @intCast(view.history_row_base), .col = 4 } },
            64,
        ),
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

test "text extraction keeps grapheme scalars and suppresses concealed cells" {
    var terminal = try Terminal.init(std.testing.allocator, 1, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("e\xcc\x81\x1b[8mSECRET\x1b[28mZ")).stateChanged());
    const copied = try terminal.copyText(
        std.testing.allocator,
        .{ .start = .{ .row = 0, .col = 0 }, .end = .{ .row = 0, .col = 7 } },
        32,
    );
    defer std.testing.allocator.free(copied);
    try std.testing.expectEqualStrings("e\xcc\x81      Z", copied);
}

test "text extraction normalizes a continuation endpoint to its grapheme lead" {
    var terminal = try Terminal.init(std.testing.allocator, 1, 4);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("界Z")).stateChanged());
    const copied = try terminal.copyText(
        std.testing.allocator,
        .{ .start = .{ .row = 0, .col = 1 }, .end = .{ .row = 0, .col = 1 } },
        16,
    );
    defer std.testing.allocator.free(copied);
    try std.testing.expectEqualStrings("界", copied);
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

test "pinned iTerm2 synchronized DCS rejects padded parameter while Howl accepts numeric" {
    // Pinned iTerm2 VT100DCSParser.m::execute checks the raw parameter
    // string against exactly "1" and "2". With 01/02 it generates no
    // DCS_BEGIN/END_SYNCHRONIZED_UPDATE. Howl parses u16 params, so
    // zero-padded 01/02 work, with matching 7-bit and C1 framing.
    var vt = try Terminal.init(std.testing.allocator, 2, 8);
    defer vt.deinit();
    try std.testing.expect(!(try vt.feed("\x1bP=01s")).stateChanged());
    try std.testing.expect((try vt.feed("\x1b\\")).stateChanged());
    try std.testing.expect(vt.synchronizedOutput());
    try std.testing.expect(!(try vt.feed("\x90=001s\x9c")).stateChanged());
    try std.testing.expect((try vt.feed("\x90=02s\x9c")).stateChanged());
    try std.testing.expect(!vt.synchronizedOutput());
    try std.testing.expect(!(try vt.feed("\x1bP=002s\x1b\\")).stateChanged());
    try std.testing.expect((try vt.feed("\x1bP=1s\x1b\\")).stateChanged());
    try std.testing.expect(vt.synchronizedOutput());
    try std.testing.expect((try vt.feed("\x1bP=2s\x1b\\")).stateChanged());
    try std.testing.expect(!vt.synchronizedOutput());
    try std.testing.expectEqualStrings("", vt.replyBytes());
}

test "pinned iTerm2 DEC 2026 repeats the host sync callback unlike Howl" {
    // Pinned VT100Terminal.m::setSynchronizedUpdates invokes the host
    // terminalSynchronizedUpdate callback after every assignment, even
    // repeated equal DECSET/DECRST. Howl reports real transitions only;
    // both standard first-on and first-off wire forms still work.
    var vt = try Terminal.init(std.testing.allocator, 2, 8);
    defer vt.deinit();
    try std.testing.expect((try vt.feed("\x1b[?2026h")).stateChanged());
    try std.testing.expect(vt.synchronizedOutput());
    const held = vt.semanticSequence();
    try std.testing.expect(!(try vt.feed("\x1b[?2026h")).stateChanged());
    try std.testing.expectEqual(held, vt.semanticSequence());
    try std.testing.expect((try vt.feed("\x1b[?2026l")).stateChanged());
    try std.testing.expect(!vt.synchronizedOutput());
    const released = vt.semanticSequence();
    try std.testing.expect(!(try vt.feed("\x1b[?2026l")).stateChanged());
    try std.testing.expectEqual(released, vt.semanticSequence());
    try std.testing.expectEqualStrings("", vt.replyBytes());
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

    // RIS returns to a cleared primary bank, clears the inactive bank, and
    // invalidates both explicit and 1049 cursor savepoints.
    const revision_before_reset = vt.semanticSequence();
    try std.testing.expect((try vt.feed(
        "\x1b[HKEEP\x1b[?47h\x1b[6 q\x1b[1;3mALT2\x1b7\x1bc",
    )).stateChanged());
    view = vt.semanticView(0);
    try std.testing.expect(!view.is_alternate_screen);
    try std.testing.expectEqual(@as(u16, 2), view.rows);
    try std.testing.expectEqual(@as(u16, 4), view.cols);
    try std.testing.expectEqual(@as(u21, 0), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u16, 0), view.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), view.cursor_col);
    try std.testing.expectEqual(Terminal.CursorShape.block, view.cursor_shape);
    try std.testing.expect(view.cursor_blink);
    try std.testing.expect(view.cursor_visible);
    try std.testing.expect(!vt.presentation().reverse_screen);
    try std.testing.expectEqual(revision_before_reset + 1, vt.semanticSequence());

    const canonical_revision = vt.semanticSequence();
    try std.testing.expect(!(try vt.feed("\x1b[?47l\x1b8")).stateChanged());
    try std.testing.expectEqual(canonical_revision, vt.semanticSequence());
    view = vt.semanticView(0);
    try std.testing.expect(!view.is_alternate_screen);
    try std.testing.expectEqual(@as(u21, 0), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u16, 0), view.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), view.cursor_col);
    try std.testing.expect((try vt.feed("X")).stateChanged());
    const restored = vt.semanticView(0).cellInfoAt(0, 0);
    try std.testing.expect(!restored.attrs.bold);
    try std.testing.expect(!restored.attrs.italic);

    // The inactive bank is reset too; entering it cannot reveal ALT2 or its
    // saved cursor state. Repeated RIS remains a bounded headless revision.
    try std.testing.expect((try vt.feed("\x1b[?47h")).stateChanged());
    view = vt.semanticView(0);
    try std.testing.expect(view.is_alternate_screen);
    try std.testing.expectEqual(@as(u21, 0), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u16, 0), view.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), view.cursor_col);
    try std.testing.expectEqual(Terminal.CursorShape.block, view.cursor_shape);
    try std.testing.expect(view.cursor_blink);
    const alternate_revision = vt.semanticSequence();
    try std.testing.expect(!(try vt.feed("\x1b8")).stateChanged());
    try std.testing.expectEqual(alternate_revision, vt.semanticSequence());
    try std.testing.expect((try vt.feed("Y")).stateChanged());
    const alternate_cell = vt.semanticView(0).cellInfoAt(0, 0);
    try std.testing.expect(!alternate_cell.attrs.bold);
    try std.testing.expect(!alternate_cell.attrs.italic);
    const revision_before_repeated_reset = vt.semanticSequence();
    try std.testing.expect((try vt.feed("\x1bc")).stateChanged());
    try std.testing.expectEqual(revision_before_repeated_reset + 1, vt.semanticSequence());
    view = vt.semanticView(0);
    try std.testing.expect(!view.is_alternate_screen);
    try std.testing.expectEqual(@as(u21, 0), view.cellAt(0, 0));
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

fn relieveOneNonReplyConsequence(machine: *Terminal) Terminal.FeedError!void {
    const head = machine.consequenceHead() orelse return error.ConsequencePressure;
    machine.consumeConsequence(head.id()) catch |failure| switch (failure) {
        // zig-audit: acknowledge unreachable
        // reason: The surrounding validation and exhaustive state machine exclude this branch; reaching it would prove an internal invariant violation.
        error.StaleConsequence, error.ReplyRequired => unreachable,
    };
}

test "strict service boundary exposes pressure after already-applied ordinary prefix" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    for (0..32) |_| {
        const progress = try terminal.feedAtServiceBoundary(&.{0x07}, 1);
        try std.testing.expectEqual(@as(usize, 1), progress.consumed);
    }
    try std.testing.expectEqual(@as(u16, 32), terminal.consequenceCount());

    const before = terminal.semanticSequence();
    try std.testing.expectError(
        error.ConsequencePressure,
        terminal.feedAtServiceBoundary(&.{ 'X', 0x07, 'Y' }, 2),
    );
    const view = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'X'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), view.cellAt(0, 1));
    try std.testing.expect(terminal.semanticSequence() > before);
    try std.testing.expectEqual(@as(u16, 32), terminal.consequenceCount());
}

test "service boundary relieves one retained head and retries exact semantic event" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    for (0..32) |_| {
        const progress = try terminal.feedAtServiceBoundary(&.{0x07}, 1);
        try std.testing.expectEqual(@as(usize, 1), progress.consumed);
    }
    try std.testing.expectEqual(@as(u64, 1), terminal.consequenceHead().?.id());

    const pressure = try terminal.feedAtServiceBoundaryRelievingConsequences(
        &.{ 'X', 0x07, 'Y' },
        2,
        relieveOneNonReplyConsequence,
    );
    try std.testing.expectEqual(@as(usize, 2), pressure.consumed);
    try std.testing.expect(pressure.consequence_pressure_relieved);
    try std.testing.expectEqual(@as(u16, 32), terminal.consequenceCount());
    try std.testing.expectEqual(@as(u64, 2), terminal.consequenceHead().?.id());
    var view = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'X'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), view.cellAt(0, 1));

    const tail = try terminal.feedAtServiceBoundary(&.{'Y'}, 3);
    try std.testing.expectEqual(@as(usize, 1), tail.consumed);
    try std.testing.expect(!tail.consequence_pressure_relieved);
    view = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'X'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'Y'), view.cellAt(0, 1));
}

fn consumeOneConsequenceThenFail(machine: *Terminal) Terminal.FeedError!void {
    const head = machine.consequenceHead() orelse return error.ConsequencePressure;
    machine.consumeConsequence(head.id()) catch |failure| switch (failure) {
        // zig-audit: acknowledge unreachable
        // reason: The surrounding validation and exhaustive state machine exclude this branch; reaching it would prove an internal invariant violation.
        error.StaleConsequence, error.ReplyRequired => unreachable,
    };
    return error.ReplyLimit;
}

test "failed relief preserves caller mutation without admitting pressure event" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();

    for (0..32) |_| {
        const progress = try terminal.feedAtServiceBoundary(&.{0x07}, 1);
        try std.testing.expectEqual(@as(usize, 1), progress.consumed);
    }
    try std.testing.expectEqual(@as(u16, 32), terminal.consequenceCount());
    try std.testing.expectEqual(@as(u64, 1), terminal.consequenceHead().?.id());

    const before = terminal.semanticSequence();
    try std.testing.expectError(
        error.ReplyLimit,
        terminal.feedAtServiceBoundaryRelievingConsequences(
            &.{ 'X', 0x07, 'Y' },
            2,
            consumeOneConsequenceThenFail,
        ),
    );

    // Caller-owned relief already retired exactly one old occurrence before its
    // own error escaped. The pressure-causing BEL was never retried/admitted.
    try std.testing.expectEqual(@as(u16, 31), terminal.consequenceCount());
    try std.testing.expectEqual(@as(u64, 2), terminal.consequenceHead().?.id());
    var view = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'X'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), view.cellAt(0, 1));
    try std.testing.expect(terminal.semanticSequence() > before);

    // The caller may resume with new bytes deliberately. Nothing from the failed
    // parsed event is replayed implicitly.
    const resumed = try terminal.feedAtServiceBoundary(&.{'Y'}, 3);
    try std.testing.expectEqual(@as(usize, 1), resumed.consumed);
    try std.testing.expectEqual(@as(u16, 31), terminal.consequenceCount());
    view = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'X'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'Y'), view.cellAt(0, 1));
}

test "resize preserves a concentrated history row with external combining scalars" {
    const allocator = std.testing.allocator;
    var failing = std.testing.FailingAllocator.init(allocator, .{});
    const terminal = try allocator.create(Terminal);
    defer allocator.destroy(terminal);
    try Terminal.initWithHistoryInto(terminal, failing.allocator(), 42, 512, 64);
    defer terminal.deinit();
    const grapheme = "e\u{0301}\u{0302}\u{0303}\u{0304}\u{0305}\u{0306}\u{0307}\u{0308}";
    try feed(terminal, "\x1b[?7l");
    for (0..512) |_| try feed(terminal, grapheme);
    for (0..42) |_| try feed(terminal, "\r\n");
    const before = &terminal.screen_state.primary;
    try std.testing.expectEqual(@as(u32, 1), before.historyCount());
    for (0..512) |col| try std.testing.expectEqual(@as(u8, 8), before.historyCellAt(0, @intCast(col)).combining_len);
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, terminal.resize(42, 511));
    failing.fail_index = std.math.maxInt(usize);
    try std.testing.expectEqual(@as(u32, 1), before.historyCount());
    try std.testing.expectEqual(@as(u8, 8), before.historyCellAt(0, 511).combining_len);
    try terminal.resize(42, 511);
    const after = &terminal.screen_state.primary;
    try std.testing.expectEqual(@as(u32, 2), after.historyCount());
    const expected = [_]u32{ 'e', 0x0301, 0x0302, 0x0303, 0x0304, 0x0305, 0x0306, 0x0307, 0x0308 };
    var scalars: [24]u32 = undefined;
    for (0..511) |col| {
        try std.testing.expectEqual(@as(u8, 8), after.historyCellAt(1, @intCast(col)).combining_len);
        try std.testing.expectEqualSlices(u32, &expected, after.historyCellScalarsAt(1, @intCast(col), &scalars));
    }
    try std.testing.expectEqual(@as(u8, 8), after.historyCellAt(0, 0).combining_len);
    try std.testing.expectEqualSlices(u32, &expected, after.historyCellScalarsAt(0, 0, &scalars));
}

test "terminal input grows scalar storage for dense combining text" {
    const allocator = std.testing.allocator;
    const terminal = try allocator.create(Terminal);
    defer allocator.destroy(terminal);
    try Terminal.initWithHistoryInto(terminal, allocator, 1, 512, 0);
    defer terminal.deinit();
    try feed(terminal, "\x1b[?7l");
    const grapheme = "e\u{0301}\u{0302}\u{0303}\u{0304}\u{0305}\u{0306}\u{0307}\u{0308}";
    for (0..512) |_| try feed(terminal, grapheme);
    const screen = &terminal.screen_state.primary;
    const expected = [_]u32{ 'e', 0x0301, 0x0302, 0x0303, 0x0304, 0x0305, 0x0306, 0x0307, 0x0308 };
    var scalars: [24]u32 = undefined;
    for (0..512) |col| try std.testing.expectEqualSlices(u32, &expected, screen.cellScalarsAt(0, @intCast(col), &scalars));
}

test "whole-slice feed retains a split scalar after allocation failure" {
    const allocator = std.testing.allocator;
    var failing = std.testing.FailingAllocator.init(allocator, .{});
    const terminal = try allocator.create(Terminal);
    defer allocator.destroy(terminal);
    try Terminal.initWithHistoryInto(terminal, failing.allocator(), 1, 512, 0);
    defer terminal.deinit();
    try feed(terminal, "\x1b[?7l");
    failing.fail_index = failing.alloc_index;
    var failed_col: ?u16 = null;
    var prior: [24]u32 = undefined;
    var prior_len: usize = 0;
    outer: for (0..512) |col| {
        try feed(terminal, "e");
        for (0..8) |_| {
            const screen = &terminal.screen_state.primary;
            var buffer: [24]u32 = undefined;
            const before = screen.cellScalarsAt(0, @intCast(col), &buffer);
            @memcpy(prior[0..before.len], before);
            prior_len = before.len;
            try feed(terminal, "\xcc");
            const result = terminal.feed("\x81") catch |failure| switch (failure) {
                error.OutOfMemory => {
                    failed_col = @intCast(col);
                    break :outer;
                },
                else => return failure,
            };
            try std.testing.expect(result.stateChanged());
        }
    }
    const col = failed_col orelse return error.ExpectedAllocationFailure;
    const screen = &terminal.screen_state.primary;
    var actual: [24]u32 = undefined;
    try std.testing.expectEqualSlices(u32, prior[0..prior_len], screen.cellScalarsAt(0, col, &actual));
    failing.fail_index = std.math.maxInt(usize);
    try std.testing.expectError(error.OutOfMemory, terminal.feed("\x81"));
    const progress = try terminal.feedAtServiceBoundary("", 1);
    try std.testing.expectEqual(@as(usize, 0), progress.consumed);
    try std.testing.expect(progress.input_blocked == null);
    const recovered = screen.cellScalarsAt(0, col, &actual);
    try std.testing.expectEqual(prior_len + 1, recovered.len);
    try std.testing.expectEqualSlices(u32, prior[0..prior_len], recovered[0..prior_len]);
    try std.testing.expectEqual(@as(u32, 0x301), recovered[prior_len]);
}

test "service feed retains split scalar on allocation failure" {
    const allocator = std.testing.allocator;
    var failing = std.testing.FailingAllocator.init(allocator, .{});
    const terminal = try allocator.create(Terminal);
    defer allocator.destroy(terminal);
    try Terminal.initWithHistoryInto(terminal, failing.allocator(), 1, 512, 0);
    defer terminal.deinit();
    try feed(terminal, "\x1b[?7l");
    failing.fail_index = failing.alloc_index;
    var failed_col: ?u16 = null;
    var prior: [24]u32 = undefined;
    var prior_len: usize = 0;
    outer: for (0..511) |col| {
        const base = try terminal.feedAtServiceBoundary("e", 1);
        try std.testing.expectEqual(@as(usize, 1), base.consumed);
        try std.testing.expectEqual(@as(?error{ OutOfMemory, ScalarCapacity }, null), base.input_blocked);
        for (0..8) |_| {
            const screen = &terminal.screen_state.primary;
            var buffer: [24]u32 = undefined;
            const before = screen.cellScalarsAt(0, @intCast(col), &buffer);
            @memcpy(prior[0..before.len], before);
            prior_len = before.len;
            const first = try terminal.feedAtServiceBoundary("\xcc", 1);
            try std.testing.expectEqual(@as(usize, 1), first.consumed);
            const last = try terminal.feedAtServiceBoundary("\x81", 1);
            try std.testing.expectEqual(@as(usize, 1), last.consumed);
            if (last.input_blocked) |reason| {
                try std.testing.expectEqual(error.OutOfMemory, reason);
                failed_col = @intCast(col);
                break :outer;
            }
        }
    }
    const col = failed_col orelse return error.ExpectedAllocationFailure;
    const screen = &terminal.screen_state.primary;
    var actual: [24]u32 = undefined;
    try std.testing.expectEqualSlices(u32, prior[0..prior_len], screen.cellScalarsAt(0, col, &actual));
    const still_blocked = try terminal.feedAtServiceBoundary("X", 2);
    try std.testing.expectEqual(@as(usize, 0), still_blocked.consumed);
    try std.testing.expectEqual(error.OutOfMemory, still_blocked.input_blocked.?);
    try std.testing.expectError(error.OutOfMemory, terminal.feed("X"));
    try std.testing.expectError(error.InputPending, terminal.resize(1, 511));
    failing.fail_index = std.math.maxInt(usize);
    // The failed scalar may have ended exactly at the PTY read boundary.
    // Retrying with no new bytes must still commit it once.
    const resumed = try terminal.feedAtServiceBoundary("", 3);
    try std.testing.expectEqual(@as(usize, 0), resumed.consumed);
    try std.testing.expectEqual(@as(?error{ OutOfMemory, ScalarCapacity }, null), resumed.input_blocked);
    try std.testing.expect(resumed.summary.stateChanged());
    const following = try terminal.feedAtServiceBoundary("X", 4);
    try std.testing.expectEqual(@as(usize, 1), following.consumed);
    try std.testing.expectEqual(@as(?error{ OutOfMemory, ScalarCapacity }, null), following.input_blocked);
    const recovered = screen.cellScalarsAt(0, col, &actual);
    try std.testing.expectEqual(prior_len + 1, recovered.len);
    try std.testing.expectEqualSlices(u32, prior[0..prior_len], recovered[0..prior_len]);
    try std.testing.expectEqual(@as(u32, 0x301), recovered[prior_len]);
    try std.testing.expectEqual(@as(u32, 'X'), screen.cellScalarsAt(0, col + 1, &actual)[0]);
}

test "service reports the per-grapheme limit without discarding the pending scalar" {
    const allocator = std.testing.allocator;
    const terminal = try allocator.create(Terminal);
    defer allocator.destroy(terminal);
    try Terminal.initWithHistoryInto(terminal, allocator, 1, 8, 0);
    defer terminal.deinit();
    try feed(terminal, "e");
    for (0..23) |_| try feed(terminal, "\xcc\x81");
    const blocked = try terminal.feedAtServiceBoundary("\xcc\x81X", 1);
    try std.testing.expectEqual(@as(usize, 2), blocked.consumed);
    try std.testing.expectEqual(error.ScalarCapacity, blocked.input_blocked.?);
    try std.testing.expect(terminal.inputBlocked());
    var actual: [24]u32 = undefined;
    try std.testing.expectEqual(@as(usize, 24), terminal.screen_state.primary.cellScalarsAt(0, 0, &actual).len);
    const stalled = try terminal.feedAtServiceBoundary("X", 2);
    try std.testing.expectEqual(@as(usize, 0), stalled.consumed);
    try std.testing.expectEqual(error.ScalarCapacity, stalled.input_blocked.?);
    terminal.hardReset();
    try std.testing.expect(!terminal.inputBlocked());
    try feed(terminal, "X");
    try std.testing.expectEqual(@as(u21, 'X'), terminal.semanticView(0).cellAt(0, 0));
}

test "service resumes a partially applied REP without replaying earlier repetitions" {
    const allocator = std.testing.allocator;
    var failing = std.testing.FailingAllocator.init(allocator, .{});
    const terminal = try allocator.create(Terminal);
    defer allocator.destroy(terminal);
    try Terminal.initWithHistoryInto(terminal, failing.allocator(), 1, 512, 0);
    defer terminal.deinit();
    try feed(terminal, "e");
    for (0..23) |_| try feed(terminal, "\xcc\x81");
    failing.fail_index = failing.alloc_index;
    const bytes = "\x1b[500bX";
    const partial = try terminal.feedAtServiceBoundary(bytes, 1);
    try std.testing.expectEqual(bytes.len - 1, partial.consumed);
    try std.testing.expectEqual(error.OutOfMemory, partial.input_blocked.?);
    try std.testing.expect(partial.summary.stateChanged());
    const held = try terminal.feedAtServiceBoundary(bytes[partial.consumed..], 2);
    try std.testing.expectEqual(@as(usize, 0), held.consumed);
    try std.testing.expectEqual(error.OutOfMemory, held.input_blocked.?);
    failing.fail_index = std.math.maxInt(usize);
    const resumed = try terminal.feedAtServiceBoundary(bytes[partial.consumed..], 3);
    try std.testing.expectEqual(@as(usize, 1), resumed.consumed);
    try std.testing.expect(resumed.input_blocked == null);
    var expected: [24]u32 = @splat(0x301);
    expected[0] = 'e';
    var actual: [24]u32 = undefined;
    const screen = &terminal.screen_state.primary;
    for (0..501) |col| try std.testing.expectEqualSlices(u32, &expected, screen.cellScalarsAt(0, @intCast(col), &actual));
    try std.testing.expectEqual(@as(u21, 'X'), terminal.semanticView(0).cellAt(0, 501));
}

test "OSC 66 service resumes from the retained parser payload under scalar pressure" {
    for ([_][]const u8{ "\x07", "\x1b\\", "\x9c" }) |terminator| {
        const allocator = std.testing.allocator;
        var failing = std.testing.FailingAllocator.init(allocator, .{});
        const terminal = try allocator.create(Terminal);
        defer allocator.destroy(terminal);
        try Terminal.initWithHistoryInto(terminal, failing.allocator(), 1, 512, 0);
        defer terminal.deinit();
        const cluster = "e\u{0301}\u{0302}\u{0303}\u{0304}\u{0305}\u{0306}\u{0307}\u{0308}";
        var payload: [8192]u8 = undefined;
        const header = "\x1b]66;s=1;";
        @memcpy(payload[0..header.len], header);
        var length: usize = header.len;
        for (0..450) |_| {
            @memcpy(payload[length..][0..cluster.len], cluster);
            length += cluster.len;
        }
        @memcpy(payload[length..][0..terminator.len], terminator);
        length += terminator.len;
        // All OSC capture allocation occurs before the scalar failure is armed.
        try feed(terminal, payload[0 .. length - 1]);
        failing.fail_index = failing.alloc_index;
        const last = payload[length - 1];
        const suffix = [_]u8{ last, 'X' };
        const blocked = try terminal.feedAtServiceBoundary(&suffix, 1);
        try std.testing.expectEqual(@as(usize, 1), blocked.consumed);
        try std.testing.expectEqual(error.OutOfMemory, blocked.input_blocked.?);
        try std.testing.expect(blocked.summary.stateChanged());
        try std.testing.expectError(error.InputPending, terminal.resize(1, 511));
        const still_blocked = try terminal.feedAtServiceBoundary(suffix[1..], 2);
        try std.testing.expectEqual(@as(usize, 0), still_blocked.consumed);
        try std.testing.expectEqual(error.OutOfMemory, still_blocked.input_blocked.?);
        failing.fail_index = std.math.maxInt(usize);
        const resumed = try terminal.feedAtServiceBoundary(suffix[1..], 3);
        try std.testing.expectEqual(@as(usize, 1), resumed.consumed);
        try std.testing.expect(resumed.input_blocked == null);
        const expected = [_]u32{ 'e', 0x301, 0x302, 0x303, 0x304, 0x305, 0x306, 0x307, 0x308 };
        var actual: [24]u32 = undefined;
        const screen = &terminal.screen_state.primary;
        for (0..450) |col| try std.testing.expectEqualSlices(u32, &expected, screen.cellScalarsAt(0, @intCast(col), &actual));
        try std.testing.expectEqual(@as(u21, 'X'), terminal.semanticView(0).cellAt(0, 450));
    }
}

test "fragmented NEL retries history once without consuming its suffix" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var terminal = try Terminal.initWithHistory(failing.allocator(), 2, 4, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("AAAA\r\nBBBB")).stateChanged());
    const prefix = try terminal.feedAtServiceBoundary("\x1b", 1);
    try std.testing.expectEqual(@as(usize, 1), prefix.consumed);
    failing.fail_index = failing.alloc_index;
    const blocked = try terminal.feedAtServiceBoundary("EC", 2);
    try std.testing.expectEqual(@as(usize, 1), blocked.consumed);
    try std.testing.expectEqual(error.OutOfMemory, blocked.input_blocked.?);
    try std.testing.expect(!blocked.summary.historyLost());
    try std.testing.expectEqual(@as(u21, 'A'), terminal.semanticView(0).cellAt(0, 0));
    failing.fail_index = std.math.maxInt(usize);
    const resumed = try terminal.feedAtServiceBoundary("C", 3);
    try std.testing.expectEqual(@as(usize, 1), resumed.consumed);
    try std.testing.expect(resumed.input_blocked == null);
    try std.testing.expectEqual(@as(u32, 1), terminal.semanticView(0).history_count);
    try std.testing.expectEqual(@as(u21, 'A'), terminal.semanticView(1).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'C'), terminal.semanticView(0).cellAt(1, 0));
}

test "split UTF-8 wide wrap retains the graphic and suffix across history OOM" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var terminal = try Terminal.initWithHistory(failing.allocator(), 1, 4, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("ABC")).stateChanged());
    const prefix = try terminal.feedAtServiceBoundary("\xe4\xb8", 1);
    try std.testing.expectEqual(@as(usize, 2), prefix.consumed);
    failing.fail_index = failing.alloc_index;
    const blocked = try terminal.feedAtServiceBoundary("\xadX", 2);
    try std.testing.expectEqual(@as(usize, 1), blocked.consumed);
    try std.testing.expectEqual(error.OutOfMemory, blocked.input_blocked.?);
    try std.testing.expectEqual(@as(u32, 0), terminal.semanticView(0).history_count);
    try std.testing.expectEqual(@as(u21, 'C'), terminal.semanticView(0).cellAt(0, 2));
    failing.fail_index = std.math.maxInt(usize);
    const resumed = try terminal.feedAtServiceBoundary("X", 3);
    try std.testing.expectEqual(@as(usize, 1), resumed.consumed);
    try std.testing.expect(resumed.input_blocked == null);
    try std.testing.expectEqual(@as(u32, 1), terminal.semanticView(0).history_count);
    try std.testing.expectEqual(@as(u21, 'C'), terminal.semanticView(1).cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 0x4e2d), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'X'), terminal.semanticView(0).cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(0, 3));
}

test "split presentation selector retains original grapheme across history OOM" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var terminal = try Terminal.initWithHistory(failing.allocator(), 1, 4, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("AAA☺")).stateChanged());
    const prefix = try terminal.feedAtServiceBoundary("\xef\xb8", 1);
    try std.testing.expectEqual(@as(usize, 2), prefix.consumed);
    failing.fail_index = failing.alloc_index;
    const blocked = try terminal.feedAtServiceBoundary("\x8fX", 2);
    try std.testing.expectEqual(@as(usize, 1), blocked.consumed);
    try std.testing.expectEqual(error.OutOfMemory, blocked.input_blocked.?);
    var scalars: [24]u21 = undefined;
    try std.testing.expectEqualSlices(u21, &.{0x263a}, terminal.semanticView(0).cellScalarsAt(0, 3, &scalars));
    try std.testing.expectEqual(@as(u32, 0), terminal.semanticView(0).history_count);
    failing.fail_index = std.math.maxInt(usize);
    const resumed = try terminal.feedAtServiceBoundary("X", 3);
    try std.testing.expectEqual(@as(usize, 1), resumed.consumed);
    try std.testing.expect(resumed.input_blocked == null);
    try std.testing.expectEqual(@as(u32, 1), terminal.semanticView(0).history_count);
    try std.testing.expectEqualSlices(u21, &.{ 0x263a, 0xfe0f }, terminal.semanticView(0).cellScalarsAt(0, 0, &scalars));
    try std.testing.expectEqual(@as(u21, 'X'), terminal.semanticView(0).cellAt(0, 2));
}

test "bulk scroll resumes after a partially completed history admission" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var terminal = try Terminal.initWithHistory(failing.allocator(), 2, 2048, 8);
    defer terminal.deinit();
    var row: [2048]u8 = @splat('A');
    try feed(&terminal, &row);
    try feed(&terminal, "\x1b[2;1H");
    @memset(&row, 'B');
    try feed(&terminal, &row);
    try terminal.setCellPixelSize(1, 1);
    try feed(&terminal, "\x1b[2;1H\x1b_Ga=T,f=32,s=1,v=1,i=7,C=1;AQIDBA==\x1b\\\x1b[2;2048H");
    try std.testing.expect(terminal.images(0).placement(0) != null);
    try feed(&terminal, "\x1b[2");
    // First history row allocates the cell and attribute blocks. The second
    // row needs another cell block, so fail after one row has moved.
    failing.fail_index = failing.alloc_index + 2;
    const blocked = try terminal.feedAtServiceBoundary("SX", 1);
    try std.testing.expectEqual(@as(usize, 1), blocked.consumed);
    try std.testing.expectEqual(error.OutOfMemory, blocked.input_blocked.?);
    try std.testing.expect(!blocked.summary.historyLost());
    try std.testing.expectEqual(@as(u32, 1), terminal.semanticView(0).history_count);
    try std.testing.expectEqual(@as(u21, 'B'), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u16, 0), terminal.images(0).placement(0).?.row);
    const still_blocked = try terminal.feedAtServiceBoundary("X", 2);
    try std.testing.expectEqual(@as(usize, 0), still_blocked.consumed);
    try std.testing.expectEqual(error.OutOfMemory, still_blocked.input_blocked.?);
    try std.testing.expectEqual(@as(u32, 1), terminal.semanticView(0).history_count);
    failing.fail_index = std.math.maxInt(usize);
    const resumed = try terminal.feedAtServiceBoundary("X", 2);
    try std.testing.expectEqual(@as(usize, 1), resumed.consumed);
    try std.testing.expect(resumed.input_blocked == null);
    try std.testing.expectEqual(@as(u32, 2), terminal.semanticView(0).history_count);
    try std.testing.expectEqual(@as(u21, 'A'), terminal.semanticView(2).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), terminal.semanticView(2).cellAt(1, 0));
    try std.testing.expectEqual(@as(u16, 0), terminal.images(1).placement(0).?.row);
    try std.testing.expectEqual(@as(u21, 'X'), terminal.semanticView(0).cellAt(1, 2047));
}

test "top-margin multi-row scroll resumes history and keeps fixed image" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var terminal = try Terminal.initWithHistory(failing.allocator(), 3, 2048, 8);
    defer terminal.deinit();
    var row: [2048]u8 = @splat('A');
    try feed(&terminal, &row);
    try feed(&terminal, "\x1b[2;1H");
    @memset(&row, 'B');
    try feed(&terminal, &row);
    try terminal.setCellPixelSize(1, 1);
    try feed(&terminal, "\x1b[2;1H\x1b_Ga=T,f=32,s=1,v=1,i=7,C=1;AQIDBA==\x1b\\" ++
        "\x1b[3;1H\x1b_Ga=T,f=32,s=1,v=1,i=8,C=1;AQIDBA==\x1b\\\x1b[1;2r\x1b[2");
    try std.testing.expect(terminal.images(0).placement(0) != null);
    try std.testing.expect(terminal.images(0).placement(1) != null);
    failing.fail_index = failing.alloc_index + 2;
    const blocked = try terminal.feedAtServiceBoundary("SX", 1);
    try std.testing.expectEqual(@as(usize, 1), blocked.consumed);
    try std.testing.expectEqual(error.OutOfMemory, blocked.input_blocked.?);
    try std.testing.expect(!blocked.summary.historyLost());
    try std.testing.expectEqual(@as(u32, 1), terminal.semanticView(0).history_count);
    try std.testing.expectEqual(@as(u16, 0), terminal.images(0).placement(0).?.row);
    try std.testing.expectEqual(@as(u16, 2), terminal.images(0).placement(1).?.row);
    failing.fail_index = std.math.maxInt(usize);
    const resumed = try terminal.feedAtServiceBoundary("X", 2);
    try std.testing.expectEqual(@as(usize, 1), resumed.consumed);
    try std.testing.expect(resumed.input_blocked == null);
    try std.testing.expectEqual(@as(u32, 2), terminal.semanticView(0).history_count);
    try std.testing.expectEqual(@as(u21, 'A'), terminal.semanticView(2).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), terminal.semanticView(2).cellAt(1, 0));
    try std.testing.expectEqual(@as(u16, 0), terminal.images(1).placement(0).?.row);
    try std.testing.expectEqual(@as(u16, 2), terminal.images(0).placement(1).?.row);
    try std.testing.expectEqual(@as(u21, 'X'), terminal.semanticView(0).cellAt(0, 0));
}

test "multi-row OSC 66 resumes after partial history admission" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var terminal = try Terminal.initWithHistory(failing.allocator(), 3, 2048, 8);
    defer terminal.deinit();
    var row: [2048]u8 = @splat('A');
    try feed(&terminal, &row);
    try feed(&terminal, "\x1b[2;1H");
    @memset(&row, 'B');
    try feed(&terminal, &row);
    try feed(&terminal, "\x1b[3;1H\x1b]66;s=3;X");
    failing.fail_index = failing.alloc_index + 2;
    const blocked = try terminal.feedAtServiceBoundary("\x07Z", 1);
    try std.testing.expectEqual(@as(usize, 1), blocked.consumed);
    try std.testing.expectEqual(error.OutOfMemory, blocked.input_blocked.?);
    try std.testing.expect(!blocked.summary.historyLost());
    try std.testing.expectEqual(@as(u32, 1), terminal.semanticView(0).history_count);
    failing.fail_index = std.math.maxInt(usize);
    const resumed = try terminal.feedAtServiceBoundary("Z", 2);
    try std.testing.expectEqual(@as(usize, 1), resumed.consumed);
    try std.testing.expect(resumed.input_blocked == null);
    try std.testing.expectEqual(@as(u32, 2), terminal.semanticView(0).history_count);
    try std.testing.expectEqual(@as(u21, 'A'), terminal.semanticView(2).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), terminal.semanticView(2).cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'X'), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'Z'), terminal.semanticView(0).cellAt(0, 3));
}

test "multi-row OSC 66 keeps partial-margin images across history retry" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var terminal = try Terminal.initWithHistory(failing.allocator(), 4, 2048, 8);
    defer terminal.deinit();
    var row: [2048]u8 = @splat('A');
    try feed(&terminal, &row);
    try feed(&terminal, "\x1b[2;1H");
    @memset(&row, 'B');
    try feed(&terminal, &row);
    try terminal.setCellPixelSize(1, 1);
    try feed(&terminal, "\x1b[2;1H\x1b_Ga=T,f=32,s=1,v=1,i=7,C=1;AQIDBA==\x1b\\" ++
        "\x1b[4;1H\x1b_Ga=T,f=32,s=1,v=1,i=8,C=1;AQIDBA==\x1b\\\x1b[1;3r\x1b[3;1H\x1b]66;s=3;X");
    try std.testing.expect(terminal.images(0).placement(0) != null);
    try std.testing.expect(terminal.images(0).placement(1) != null);
    failing.fail_index = failing.alloc_index + 2;
    const blocked = try terminal.feedAtServiceBoundary("\x07Z", 1);
    try std.testing.expectEqual(@as(usize, 1), blocked.consumed);
    try std.testing.expectEqual(error.OutOfMemory, blocked.input_blocked.?);
    try std.testing.expectEqual(@as(u32, 1), terminal.semanticView(0).history_count);
    try std.testing.expectEqual(@as(u16, 0), terminal.images(0).placement(0).?.row);
    try std.testing.expectEqual(@as(u16, 3), terminal.images(0).placement(1).?.row);
    failing.fail_index = std.math.maxInt(usize);
    const resumed = try terminal.feedAtServiceBoundary("Z", 2);
    try std.testing.expectEqual(@as(usize, 1), resumed.consumed);
    try std.testing.expect(resumed.input_blocked == null);
    try std.testing.expectEqual(@as(u32, 2), terminal.semanticView(0).history_count);
    try std.testing.expectEqual(@as(u16, 0), terminal.images(1).placement(0).?.row);
    try std.testing.expectEqual(@as(u16, 3), terminal.images(0).placement(1).?.row);
    try std.testing.expectEqual(@as(u21, 'X'), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'Z'), terminal.semanticView(0).cellAt(0, 3));
}

test "multi-row OSC 66 resumes after a wrap and partial history admission" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var terminal = try Terminal.initWithHistory(failing.allocator(), 3, 2048, 8);
    defer terminal.deinit();
    var row: [2048]u8 = @splat('A');
    try feed(&terminal, &row);
    try feed(&terminal, "\x1b[2;1H");
    @memset(&row, 'B');
    try feed(&terminal, &row);
    try feed(&terminal, "\x1b[3;1H");
    @memset(&row, 'C');
    try feed(&terminal, &row);
    try feed(&terminal, "\x1b[3;2048H\x1b]66;s=3;X");
    failing.fail_index = failing.alloc_index + 2;
    const blocked = try terminal.feedAtServiceBoundary("\x07Z", 1);
    try std.testing.expectEqual(@as(usize, 1), blocked.consumed);
    try std.testing.expectEqual(error.OutOfMemory, blocked.input_blocked.?);
    try std.testing.expect(!blocked.summary.historyLost());
    try std.testing.expectEqual(@as(u32, 1), terminal.semanticView(0).history_count);
    failing.fail_index = std.math.maxInt(usize);
    const resumed = try terminal.feedAtServiceBoundary("Z", 2);
    try std.testing.expectEqual(@as(usize, 1), resumed.consumed);
    try std.testing.expect(resumed.input_blocked == null);
    try std.testing.expectEqual(@as(u32, 3), terminal.semanticView(0).history_count);
    try std.testing.expectEqual(@as(u21, 'A'), terminal.semanticView(3).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), terminal.semanticView(3).cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'C'), terminal.semanticView(3).cellAt(2, 0));
    try std.testing.expectEqual(@as(u21, 'X'), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'Z'), terminal.semanticView(0).cellAt(0, 3));
}

test "full-width scroll preserves one-row sized clusters in history and on screen" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 3, 8, 4);
    defer terminal.deinit();
    try feed(&terminal, "\x1b]66;s=1:w=3;X\x07\x1b[3;1H\x1b]66;s=1:w=3;Y\x07\x1b[S");
    try std.testing.expectEqual(@as(u32, 1), terminal.semanticView(0).history_count);
    try std.testing.expectEqual(@as(u21, 'X'), terminal.semanticView(1).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'Y'), terminal.semanticView(0).cellAt(1, 0));
    try std.testing.expectEqual(@as(u8, 3), terminal.semanticView(1).cellInfoAt(0, 0).width);
    try std.testing.expectEqual(@as(u8, 3), terminal.semanticView(0).cellInfoAt(1, 0).width);
}

test "full-width scroll retains the text of a multi-row cluster" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 3, 8, 4);
    defer terminal.deinit();
    try feed(&terminal, "\x1b]66;s=2;X\x07\x1b[S");
    try std.testing.expectEqual(@as(u32, 1), terminal.semanticView(0).history_count);
    try std.testing.expectEqual(@as(u21, 'X'), terminal.semanticView(1).cellAt(0, 0));
}

test "multi-row history and live fragment retain ownership across sequential scroll and overwrite" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 4, 8, 4);
    defer terminal.deinit();
    try feed(&terminal, "\x1b]66;s=3;X\x07\x1b[2S");
    try std.testing.expectEqual(@as(u32, 2), terminal.semanticView(0).history_count);
    try std.testing.expectEqual(@as(u21, 'X'), terminal.semanticView(2).cellAt(0, 0));
    try std.testing.expectEqual(@as(u8, 1), terminal.semanticView(2).cellInfoAt(1, 0).y);
    try std.testing.expectEqual(@as(u8, 2), terminal.semanticView(0).cellInfoAt(0, 0).y);
    // Explicit erase clears the remaining live fragment before writing.
    try feed(&terminal, "\x1b[1;3H\x1b[1XY");
    try std.testing.expectEqual(@as(u21, 'Y'), terminal.semanticView(0).cellAt(0, 2));
    try std.testing.expectEqual(@as(u8, 1), terminal.semanticView(0).cellInfoAt(0, 0).width);
    try std.testing.expectEqual(@as(u8, 1), terminal.semanticView(0).cellInfoAt(0, 1).width);
    try std.testing.expectEqual(@as(u21, 'X'), terminal.semanticView(2).cellAt(0, 0));
}

test "height resize preserves a tall cluster following a soft-wrapped line" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 6, 8, 8);
    defer terminal.deinit();
    try feed(&terminal, "abcdefghZ\x1b[4;1H\x1b]66;s=2;X\x07");
    try terminal.resize(7, 8);
    const view = terminal.semanticView(std.math.maxInt(u32));
    var lead: ?u16 = null;
    for (0..view.rows) |row| {
        if (view.cellAt(@intCast(row), 0) == 'X') lead = @intCast(row);
    }
    const row = lead orelse return error.MissingCluster;
    try std.testing.expect(row + 1 < view.rows);
    try std.testing.expectEqual(@as(u8, 2), view.cellInfoAt(row, 0).height);
    try std.testing.expectEqual(@as(u8, 1), view.cellInfoAt(row + 1, 0).y);
}

test "visible continuation resolves its full retained scalar sequence" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 3, 8, 4);
    defer terminal.deinit();
    try feed(&terminal, "\x1b]66;s=2;e\u{0301}\u{0302}\u{0303}\u{0304}\u{0305}\x07\x1b[S");
    const view = terminal.semanticView(0);
    var scalars: [24]u21 = undefined;
    try std.testing.expectEqualSlices(u21, &.{ 'e', 0x301, 0x302, 0x303, 0x304, 0x305 }, view.cellScalarsAt(0, 1, &scalars));
}

test "narrowing discards oversized OSC 66 text without restoring it on widening" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 4, 8, 8);
    defer terminal.deinit();
    try feed(&terminal, "\x1b]66;s=2:w=2;Hi\x07");
    try terminal.resize(4, 3);
    try terminal.resize(4, 8);
    const view = terminal.semanticView(std.math.maxInt(u32));
    var found = false;
    for (0..view.rows) |row| for (0..view.cols) |col| {
        if (view.cellAt(@intCast(row), @intCast(col)) == 'H') found = true;
    };
    try std.testing.expect(!found);
}

test "one-row OSC 66 packed text and presentation survive reflow" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 4, 8, 8);
    defer terminal.deinit();
    try feed(&terminal, "ABCD\x1b[1;31m\x1b]66;s=1:w=1:n=1:d=2:h=2:v=1;ab\x07\x1b[0m");
    try terminal.resize(4, 3);
    const view = terminal.semanticView(std.math.maxInt(u32));
    var found = false;
    for (0..view.rows) |row| for (0..view.cols) |col| {
        const r: u16 = @intCast(row);
        const c: u16 = @intCast(col);
        if (view.cellAt(r, c) != 'a') continue;
        const cell = view.cellInfoAt(r, c);
        var scalars: [24]u21 = undefined;
        try std.testing.expectEqualSlices(u21, &.{ 'a', 'b' }, view.cellScalarsAt(r, c, &scalars));
        try std.testing.expectEqual(@as(u8, 1), cell.width);
        try std.testing.expectEqual(@as(u8, 1), cell.height);
        try std.testing.expectEqual(@as(u4, 1), cell.subscale_n);
        try std.testing.expectEqual(@as(u4, 2), cell.subscale_d);
        try std.testing.expectEqual(@as(u2, 2), cell.horizontal_align);
        try std.testing.expectEqual(@as(u2, 1), cell.vertical_align);
        try std.testing.expect(cell.attrs.bold);
        try std.testing.expectEqual(@as(u32, 1), cell.attrs.fg.value);
        found = true;
    };
    try std.testing.expect(found);
}

test "one-row three-column OSC 66 text survives fitting reflow" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 4, 8, 8);
    defer terminal.deinit();
    try feed(&terminal, "ABCD\x1b[1;31m\x1b]66;s=1:w=3;XY\x07\x1b[0m");
    try terminal.resize(4, 3);
    const view = terminal.semanticView(std.math.maxInt(u32));
    var found = false;
    for (0..view.rows) |row| for (0..view.cols) |col| {
        const r: u16 = @intCast(row);
        const c: u16 = @intCast(col);
        if (view.cellAt(r, c) != 'X') continue;
        const cell = view.cellInfoAt(r, c);
        var scalars: [24]u21 = undefined;
        try std.testing.expectEqualSlices(u21, &.{ 'X', 'Y' }, view.cellScalarsAt(r, c, &scalars));
        try std.testing.expectEqual(@as(u8, 3), cell.width);
        try std.testing.expect(cell.attrs.bold);
        found = true;
    };
    try std.testing.expect(found);
}

test "one-row OSC 66 widths reflow atomically and unfit blocks are discarded" {
    for (2..8) |width| {
        for ([_]bool{ true, false }) |fits| {
            var terminal = try Terminal.initWithHistory(std.testing.allocator, 5, 12, 16);
            defer terminal.deinit();
            const input = try std.fmt.allocPrint(std.testing.allocator, "ABCD\x1b]66;s=1:w={d};XY\x07Z", .{width});
            defer std.testing.allocator.free(input);
            try feed(&terminal, input);
            const cols: u16 = @intCast(if (fits) width else width - 1);
            try terminal.resize(5, cols);
            var count: usize = 0;
            var found_z = false;
            var offset: u32 = 0;
            const history = terminal.semanticView(0).history_count;
            while (offset <= history) : (offset += 1) {
                const view = terminal.semanticView(offset);
                // Each viewport overlaps; use only its first row, plus the live remainder below.
                const rows: u16 = if (offset == 0) view.rows else 1;
                for (0..rows) |row| for (0..view.cols) |col| {
                    const r: u16 = @intCast(row);
                    const c: u16 = @intCast(col);
                    const cell = view.cellInfoAt(r, c);
                    if (cell.codepoint == 'Z') found_z = true;
                    if (cell.codepoint != 'X') continue;
                    count += 1;
                    try std.testing.expectEqual(@as(u8, @intCast(width)), cell.width);
                    var scalars: [24]u21 = undefined;
                    try std.testing.expectEqualSlices(u21, &.{ 'X', 'Y' }, view.cellScalarsAt(r, c, &scalars));
                    for (1..width) |part| try std.testing.expectEqual(@as(u8, @intCast(part)), view.cellInfoAt(r, c + @as(u16, @intCast(part))).x);
                };
            }
            try std.testing.expectEqual(@as(usize, if (fits) 1 else 0), count);
            try std.testing.expect(found_z);
        }
    }
}

test "one-row OSC 66 cold scalar tail survives history reflow" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 3, 10, 16);
    defer terminal.deinit();
    try feed(&terminal, "ABCD\x1b[1;31m\x1b]66;s=1:w=3;e\u{0301}\u{0302}\u{0303}\u{0304}\u{0305}\x07\x1b[0m\r\nline2\r\nline3\r\nline4");
    try std.testing.expect(terminal.semanticView(0).history_count > 0);
    const before = terminal.semanticView(std.math.maxInt(u32));
    var before_scalars: [24]u21 = undefined;
    try std.testing.expectEqualSlices(u21, &.{ 'e', 0x301, 0x302, 0x303, 0x304, 0x305 }, before.cellScalarsAt(0, 4, &before_scalars));
    try terminal.resize(3, 4);
    const view = terminal.semanticView(std.math.maxInt(u32));
    var found = false;
    for (0..view.rows) |row| for (0..view.cols) |col| {
        const r: u16 = @intCast(row);
        const c: u16 = @intCast(col);
        const cell = view.cellInfoAt(r, c);
        if (cell.codepoint != 'e' or cell.width != 3) continue;
        var scalars: [24]u21 = undefined;
        try std.testing.expectEqualSlices(u21, &.{ 'e', 0x301, 0x302, 0x303, 0x304, 0x305 }, view.cellScalarsAt(r, c, &scalars));
        try std.testing.expectEqual(@as(u8, 3), cell.width);
        try std.testing.expect(cell.attrs.bold);
        found = true;
    };
    try std.testing.expect(found);
}

test "one-row OSC 66 history resize failure preserves accepted text for retry" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var terminal = try Terminal.initWithHistory(failing.allocator(), 3, 10, 16);
    defer terminal.deinit();
    try feed(&terminal, "ABCD\x1b]66;s=1:w=3;e\u{0301}\u{0302}\u{0303}\u{0304}\u{0305}\x07\r\nline2\r\nline3\r\nline4");
    const before = terminal.semanticView(std.math.maxInt(u32));
    var scalars: [24]u21 = undefined;
    const expected = [_]u21{ 'e', 0x301, 0x302, 0x303, 0x304, 0x305 };
    try std.testing.expectEqualSlices(u21, &expected, before.cellScalarsAt(0, 4, &scalars));
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, terminal.resize(3, 4));
    const unchanged = terminal.semanticView(std.math.maxInt(u32));
    try std.testing.expectEqual(@as(u16, 10), unchanged.cols);
    try std.testing.expectEqualSlices(u21, &expected, unchanged.cellScalarsAt(0, 4, &scalars));
    failing.fail_index = std.math.maxInt(usize);
    try terminal.resize(3, 4);
    const after = terminal.semanticView(std.math.maxInt(u32));
    var found = false;
    for (0..after.rows) |row| for (0..after.cols) |col| {
        const r: u16 = @intCast(row);
        const c: u16 = @intCast(col);
        const cell = after.cellInfoAt(r, c);
        if (cell.codepoint != 'e' or cell.width != 3) continue;
        try std.testing.expectEqualSlices(u21, &expected, after.cellScalarsAt(r, c, &scalars));
        found = true;
    };
    try std.testing.expect(found);
}

test "one-row OSC 66 reflow is transactional at every allocation failure" {
    var observed_success = false;
    for (0..256) |failure_offset| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        var terminal = try Terminal.initWithHistory(failing.allocator(), 3, 10, 16);
        defer terminal.deinit();
        try feed(&terminal, "ABCD\x1b]66;s=1:w=3;e\u{0301}\u{0302}\u{0303}\u{0304}\u{0305}\x07\r\nline2\r\nline3\r\nline4");
        const expected = [_]u21{ 'e', 0x301, 0x302, 0x303, 0x304, 0x305 };
        failing.fail_index = failing.alloc_index + failure_offset;
        terminal.resize(3, 4) catch |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            const unchanged = terminal.semanticView(std.math.maxInt(u32));
            var scalars: [24]u21 = undefined;
            try std.testing.expectEqual(@as(u16, 10), unchanged.cols);
            try std.testing.expectEqualSlices(u21, &expected, unchanged.cellScalarsAt(0, 4, &scalars));
            failing.fail_index = std.math.maxInt(usize);
            try terminal.resize(3, 4);
            continue;
        };
        observed_success = true;
        break;
    }
    try std.testing.expect(observed_success);
}

test "reflow removes multi-row OSC 66 blocks but retains unrelated text in both screens" {
    for ([_]bool{ false, true }) |alternate| {
        var terminal = try Terminal.initWithHistory(std.testing.allocator, 5, 8, 16);
        defer terminal.deinit();
        if (alternate) try feed(&terminal, "\x1b[?1049h");
        try feed(&terminal, "ABCDEFG\x1b[3;1H\x1b]66;s=2;X\x07\x1b[5;1HZ");
        try terminal.resize(8, 4);
        const history = terminal.semanticView(0).history_count;
        var found_x = false;
        var found_a = false;
        var found_z = false;
        var offset: u32 = 0;
        while (offset <= history) : (offset += 1) {
            const view = terminal.semanticView(offset);
            const rows: u16 = if (offset == 0) view.rows else 1;
            for (0..rows) |row| for (0..view.cols) |col| {
                const cell = view.cellInfoAt(@intCast(row), @intCast(col));
                if (cell.codepoint == 'X') found_x = true;
                if (cell.codepoint == 'A') found_a = true;
                if (cell.codepoint == 'Z') found_z = true;
                try std.testing.expect(cell.height <= 1);
            };
        }
        try std.testing.expect(!found_x);
        try std.testing.expect(found_a);
        try std.testing.expect(found_z);
    }
}

test "height shrink discards a block taller than the new screen" {
    for ([_]bool{ false, true }) |alternate| {
        var terminal = try Terminal.initWithHistory(std.testing.allocator, 3, 8, 8);
        defer terminal.deinit();
        if (alternate) try feed(&terminal, "\x1b[?1049h");
        try feed(&terminal, "\x1b]66;s=2;X\x07");
        try terminal.resize(1, 8);
        const view = terminal.semanticView(std.math.maxInt(u32));
        for (0..view.rows) |row| for (0..view.cols) |col| {
            const cell = view.cellInfoAt(@intCast(row), @intCast(col));
            try std.testing.expect(cell.codepoint != 'X');
            try std.testing.expect(cell.height <= 1);
        };
    }
}

test "discarding tall cold scalars and unfit wide text does not panic on resize" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 3, 8, 8);
    defer terminal.deinit();
    try feed(&terminal, "\x1b]66;s=1:w=3;X\x07\x1b]66;s=2;e\u{0301}\u{0302}\u{0303}\u{0304}\u{0305}\x07");
    try terminal.resize(3, 2);
}

test "cursor maps past consecutive omitted OSC 66 blocks" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 5, 16, 8);
    defer terminal.deinit();
    try feed(&terminal, "\x1b]66;s=1:w=3;X\x07\x1b]66;s=1:w=3;Y\x07abcdef\x1b[1;7H");
    try terminal.resize(5, 2);
    const view = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'a'), view.cellAt(view.cursor_row, view.cursor_col));
}

test "whole tall block survives ordinary scroll without history" {
    for ([_]bool{ false, true }) |alternate| {
        var terminal = try Terminal.initWithHistory(std.testing.allocator, 3, 8, 0);
        defer terminal.deinit();
        if (alternate) try feed(&terminal, "\x1b[?1049h");
        try feed(&terminal, "\x1b[2;1H\x1b]66;s=2;X\x07\x1b[S");
        const view = terminal.semanticView(0);
        try std.testing.expectEqual(@as(u21, 'X'), view.cellAt(0, 0));
        try std.testing.expectEqual(@as(u8, 1), view.cellInfoAt(1, 0).y);
    }
}

test "whole tall block survives downward scroll with and without history restore" {
    for ([_]bool{ false, true }) |restore| {
        var terminal = try Terminal.initWithHistory(std.testing.allocator, 3, 8, 8);
        defer terminal.deinit();
        if (restore) try feed(&terminal, "H\r\n\r\n\r\n\x1b[H");
        try feed(&terminal, "\x1b]66;s=2;X\x07");
        if (restore) try feed(&terminal, "\x1b[1+T") else try feed(&terminal, "\x1b[T");
        const view = terminal.semanticView(0);
        if (restore) try std.testing.expectEqual(@as(u21, 'H'), view.cellAt(0, 0));
        try std.testing.expectEqual(@as(u21, 'X'), view.cellAt(1, 0));
        try std.testing.expectEqual(@as(u8, 1), view.cellInfoAt(2, 0).y);
    }
}
