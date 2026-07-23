const std = @import("std");
const screen_set = @import("../../src/terminal.zig");
const terminal_mod = @import("../../src/terminal.zig");
const stream_harness = @import("../support/stream_harness.zig");

const Terminal = terminal_mod.Terminal;

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
    try std.testing.expect(summary.state_changed);
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

test "oversized finalized line records loss and terminal continues rendering" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 2, std.math.maxInt(u16), 32);
    defer terminal.deinit();
    var chunk: [64 * 1024]u8 = @splat('x');
    const chunk_count = Terminal.logical_output_line_max_bytes / chunk.len + 1;
    for (0..chunk_count) |_| try feedChanged(&terminal, &chunk);
    switch (try terminal.copyLogicalOutput(
        std.testing.allocator,
        0,
        1,
        Terminal.logical_output_max_bytes,
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
        Terminal.logical_output_max_bytes,
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

test "terminal history retention is transactional at every allocation failure" {
    var probe = std.testing.FailingAllocator.init(std.testing.allocator, .{ .resize_fail_index = 0 });
    var terminal = try Terminal.initWithHistory(probe.allocator(), 2, 4, 8);
    defer terminal.deinit();
    try feedChanged(&terminal, "AAAA\r\nBBBB");
    const first_history_allocation = probe.alloc_index;
    try feedChanged(&terminal, "\r\nCCCC");
    const allocation_limit = probe.alloc_index;
    try std.testing.expect(allocation_limit > first_history_allocation);

    var fail_index = first_history_allocation;
    while (fail_index < allocation_limit) : (fail_index += 1) {
        try historyRetentionFailure(fail_index);
    }

    var wrapped_probe = std.testing.FailingAllocator.init(std.testing.allocator, .{ .resize_fail_index = 0 });
    var wrapped_terminal = try Terminal.initWithHistory(wrapped_probe.allocator(), 2, 4, 8);
    defer wrapped_terminal.deinit();
    try feedChanged(&wrapped_terminal, "ABCDEFGHIJKL");
    const first_wrapped_allocation = wrapped_probe.alloc_index;
    try feedChanged(&wrapped_terminal, "M");
    const wrapped_allocation_limit = wrapped_probe.alloc_index;
    try std.testing.expect(wrapped_allocation_limit > first_wrapped_allocation);

    fail_index = first_wrapped_allocation;
    while (fail_index < wrapped_allocation_limit) : (fail_index += 1) {
        try openHistoryRetentionFailure(fail_index);
    }

    var full_probe = std.testing.FailingAllocator.init(std.testing.allocator, .{ .resize_fail_index = 0 });
    var full_terminal = try Terminal.initWithHistory(full_probe.allocator(), 2, 4, 2);
    defer full_terminal.deinit();
    try feedChanged(&full_terminal, "AAAA\r\nBBBB\r\nCCCC\r\nDDDD");
    const first_full_allocation = full_probe.alloc_index;
    try feedChanged(&full_terminal, "\r\nEEEE");
    const full_allocation_limit = full_probe.alloc_index;
    try std.testing.expect(full_allocation_limit > first_full_allocation);

    fail_index = first_full_allocation;
    while (fail_index < full_allocation_limit) : (fail_index += 1) {
        try fullHistoryRetentionFailure(fail_index);
    }
}

fn historyRetentionFailure(fail_index: usize) !void {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = fail_index,
        .resize_fail_index = 0,
    });
    var terminal = try Terminal.initWithHistory(failing.allocator(), 2, 4, 8);
    defer terminal.deinit();
    try feedChanged(&terminal, "AAAA\r\nBBBB");

    feedChanged(&terminal, "\r\nCCCC") catch |failure| {
        try std.testing.expectEqual(error.OutOfMemory, failure);
        try std.testing.expect(failing.has_induced_failure);
        failing.fail_index = std.math.maxInt(usize);
        try feedChanged(&terminal, "\r\nCCCC");
        return;
    };
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectEqual(@as(u32, 0), terminal.screen_state.primary.historyCount());
    try std.testing.expectEqual(@as(usize, 0), terminal.screen_state.primary.history_lines.items.len);
    try std.testing.expect(terminal.screen_state.primary.open_history_line == null);
    try std.testing.expectEqual(@as(u21, 'B'), terminal.screen_state.primary.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'C'), terminal.screen_state.primary.cellAt(1, 0));

    failing.fail_index = std.math.maxInt(usize);
    try feedChanged(&terminal, "\r\nDDDD");
    try std.testing.expectEqual(@as(u32, 1), terminal.screen_state.primary.historyCount());
    try std.testing.expectEqual(@as(usize, 1), terminal.screen_state.primary.history_lines.items.len);
    try std.testing.expectEqual(@as(u21, 'B'), terminal.screen_state.primary.historyRowAt(0, 0));
}

fn openHistoryRetentionFailure(fail_index: usize) !void {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = fail_index,
        .resize_fail_index = 0,
    });
    var terminal = try Terminal.initWithHistory(failing.allocator(), 2, 4, 8);
    defer terminal.deinit();
    try feedChanged(&terminal, "ABCDEFGHIJKL");

    try feedChanged(&terminal, "M");
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectEqual(@as(u32, 1), terminal.screen_state.primary.historyCount());
    try std.testing.expectEqual(@as(usize, 0), terminal.screen_state.primary.history_lines.items.len);
    try std.testing.expectEqual(@as(usize, 4), terminal.screen_state.primary.open_history_line.?.cells.items.len);
    try std.testing.expectEqual(@as(u21, 'A'), terminal.screen_state.primary.historyRowAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'I'), terminal.screen_state.primary.cellAt(0, 0));

    failing.fail_index = std.math.maxInt(usize);
    try feedChanged(&terminal, "NOPQ");
    try std.testing.expectEqual(@as(u32, 2), terminal.screen_state.primary.historyCount());
    try std.testing.expectEqual(@as(usize, 8), terminal.screen_state.primary.open_history_line.?.cells.items.len);
    try std.testing.expectEqual(@as(u21, 'I'), terminal.screen_state.primary.historyRowAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'A'), terminal.screen_state.primary.historyRowAt(1, 0));
}

fn fullHistoryRetentionFailure(fail_index: usize) !void {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = fail_index,
        .resize_fail_index = 0,
    });
    var terminal = try Terminal.initWithHistory(failing.allocator(), 2, 4, 2);
    defer terminal.deinit();
    try feedChanged(&terminal, "AAAA\r\nBBBB\r\nCCCC\r\nDDDD");

    feedChanged(&terminal, "\r\nEEEE") catch |failure| {
        try std.testing.expectEqual(error.OutOfMemory, failure);
        try std.testing.expect(failing.has_induced_failure);
        failing.fail_index = std.math.maxInt(usize);
        try feedChanged(&terminal, "\r\nEEEE");
        return;
    };
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectEqual(@as(u32, 2), terminal.screen_state.primary.historyCount());
    try std.testing.expectEqual(@as(usize, 2), terminal.screen_state.primary.history_lines.items.len);
    try std.testing.expectEqual(@as(u21, 'B'), terminal.screen_state.primary.historyRowAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'A'), terminal.screen_state.primary.historyRowAt(1, 0));

    failing.fail_index = std.math.maxInt(usize);
    try feedChanged(&terminal, "\r\nFFFF");
    try std.testing.expectEqual(@as(u32, 2), terminal.screen_state.primary.historyCount());
    try std.testing.expectEqual(@as(usize, 2), terminal.screen_state.primary.history_lines.items.len);
    try std.testing.expectEqual(@as(u21, 'D'), terminal.screen_state.primary.historyRowAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), terminal.screen_state.primary.historyRowAt(1, 0));
}

test "terminal resize is transactional in both active-screen modes" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, resizeTerminalTransaction, .{false});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, resizeTerminalTransaction, .{true});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, resizeWithNotificationTransaction, .{});
}

fn resizeWithNotificationTransaction(allocator: std.mem.Allocator) !void {
    var terminal = try Terminal.initWithHistory(allocator, 2, 4, 8);
    defer terminal.deinit();
    try terminal.setCellPixelSize(9, 17);
    const enabled = try terminal.feed("\x1b[?2048h");
    try std.testing.expect(enabled.state_changed);

    terminal.resize(3, 5) catch |failure| {
        try std.testing.expectEqual(@as(u16, 2), terminal.screen_state.primary.rows);
        try std.testing.expectEqual(@as(u16, 4), terminal.screen_state.primary.cols);
        try std.testing.expectEqual(@as(u16, 2), terminal.screen_state.alternate.rows);
        try std.testing.expectEqual(@as(u16, 4), terminal.screen_state.alternate.cols);
        try std.testing.expectEqualStrings("", terminal.host.pendingOutput());
        return failure;
    };
    try std.testing.expectEqualStrings("\x1b[48;3;5;51;45t", terminal.host.pendingOutput());
}

fn resizeTerminalTransaction(allocator: std.mem.Allocator, alternate_active: bool) !void {
    var terminal = try Terminal.initWithHistory(allocator, 2, 4, 8);
    defer terminal.deinit();

    terminal.screen_state.primary.writeText("PRIMARY-ROWS");
    terminal.screen_state.alternate.writeText("ALTERNATE");
    terminal.screen_state.alt_active = alternate_active;
    terminal.screen_state.primary.cursor.setDefaultStyle(.{ .shape = .bar, .blink = false });
    terminal.screen_state.alternate.cursor.setDefaultStyle(.{ .shape = .underline, .blink = true });
    terminal.screen_state.primary.left_right_margin_mode = true;
    terminal.screen_state.primary.left_margin = 1;
    terminal.screen_state.primary.right_margin = 2;
    terminal.startSelection(0, 0);
    terminal.finishSelection();

    const primary_history_count = terminal.screen_state.primary.historyCount();
    const primary_history_cell = terminal.screen_state.primary.historyRowAt(0, 0);
    const alternate_cell = terminal.screen_state.alternate.cellAt(0, 0);
    const selection_before = terminal.selectionState();
    const semantic_sequence_before = terminal.semantic_sequence;

    terminal.resize(3, 3) catch |err| {
        try std.testing.expectEqual(@as(u16, 2), terminal.screen_state.primary.rows);
        try std.testing.expectEqual(@as(u16, 4), terminal.screen_state.primary.cols);
        try std.testing.expectEqual(@as(u16, 2), terminal.screen_state.alternate.rows);
        try std.testing.expectEqual(@as(u16, 4), terminal.screen_state.alternate.cols);
        try std.testing.expectEqual(primary_history_count, terminal.screen_state.primary.historyCount());
        try std.testing.expectEqual(primary_history_cell, terminal.screen_state.primary.historyRowAt(0, 0));
        try std.testing.expectEqual(alternate_cell, terminal.screen_state.alternate.cellAt(0, 0));
        try std.testing.expectEqual(alternate_active, terminal.screen_state.alt_active);
        try std.testing.expectEqual(selection_before, terminal.selectionState());
        try std.testing.expectEqual(semantic_sequence_before, terminal.semantic_sequence);
        try std.testing.expect(terminal.screen_state.primary.left_right_margin_mode);
        try std.testing.expectEqual(@as(u16, 1), terminal.screen_state.primary.left_margin);
        try std.testing.expectEqual(@as(u16, 2), terminal.screen_state.primary.right_margin);
        try std.testing.expectEqual(.bar, terminal.screen_state.primary.cursor.default_style.shape);
        try std.testing.expectEqual(.underline, terminal.screen_state.alternate.cursor.default_style.shape);
        terminal.screen_state.active().writeText("Z");
        return err;
    };

    try std.testing.expectEqual(@as(u16, 3), terminal.screen_state.primary.rows);
    try std.testing.expectEqual(@as(u16, 3), terminal.screen_state.primary.cols);
    try std.testing.expectEqual(@as(u16, 3), terminal.screen_state.alternate.rows);
    try std.testing.expectEqual(@as(u16, 3), terminal.screen_state.alternate.cols);
    try std.testing.expectEqual(alternate_active, terminal.screen_state.alt_active);
    try std.testing.expect(!terminal.screen_state.primary.left_right_margin_mode);
    try std.testing.expectEqual(@as(u16, 0), terminal.screen_state.primary.left_margin);
    try std.testing.expectEqual(@as(u16, 2), terminal.screen_state.primary.right_margin);
    try std.testing.expectEqual(.bar, terminal.screen_state.primary.cursor.default_style.shape);
    try std.testing.expectEqual(.underline, terminal.screen_state.alternate.cursor.default_style.shape);
    try std.testing.expectEqual(semantic_sequence_before + 1, terminal.semantic_sequence);
}

test "selection copy owns exact allocation and codepoint failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, copySelectionAllocation, .{});

    var terminal = try Terminal.init(std.testing.allocator, 1, 1);
    defer terminal.deinit();
    terminal.startSelection(0, 0);
    terminal.finishSelection();

    terminal.screen_state.primary.cells.?[0].codepoint = 0x110000;
    try std.testing.expectError(error.CodepointTooLarge, terminal.copySelection(std.testing.allocator, std.math.maxInt(usize)));
    terminal.screen_state.primary.cells.?[0].codepoint = 0xD800;
    try std.testing.expectError(error.Utf8CannotEncodeSurrogateHalf, terminal.copySelection(std.testing.allocator, std.math.maxInt(usize)));
}

test "selection resolves scrolled history reverse drag and bounded copy" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 3, 5, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("1AAAA\r\n2BBBB\r\n3CCCC\r\n4DDDD")).state_changed);
    try std.testing.expect(terminal.scrollViewport(.{ .absolute = 1 }));
    terminal.startSelection(1, 1);
    terminal.updateSelection(0, 0);
    terminal.finishSelection();
    const finished_sequence = terminal.semanticSequence();
    terminal.finishSelection();
    try std.testing.expectEqual(finished_sequence, terminal.semanticSequence());

    const copied = try terminal.copySelection(std.testing.allocator, 16);
    defer std.testing.allocator.free(copied);
    try std.testing.expectEqualStrings("1AAAA\n2B", copied);
    try std.testing.expectError(
        error.SelectionLimit,
        terminal.copySelection(std.testing.allocator, copied.len - 1),
    );
}

test "selection copy joins soft-wrapped rows without inventing a newline" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 3);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("ABCDEF")).state_changed);
    terminal.startSelection(0, 0);
    terminal.updateSelection(1, 2);
    terminal.finishSelection();
    const copied = try terminal.copySelection(std.testing.allocator, 6);
    defer std.testing.allocator.free(copied);
    try std.testing.expectEqualStrings("ABCDEF", copied);
}

test "selection appearance dirties exact active rows and resets at lifecycle boundaries" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 3, 5, 2);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("ABCDE\r\nFGHIJ")).state_changed);
    try std.testing.expect(terminal.ackVisual(terminal.visualView().dirty_token));

    terminal.startSelection(0, 1);
    terminal.updateSelection(1, 2);
    const dirty = terminal.visualView();
    try std.testing.expect(dirty.dirty == .rows);
    try std.testing.expectEqual(@as(u16, 0), dirty.dirty.rows.start_row);
    try std.testing.expectEqual(@as(u16, 1), dirty.dirty.rows.end_row);
    var rows = dirty.dirty.rows.iterator();
    try std.testing.expectEqual(
        Terminal.VisualDirtyRow{ .row = 0, .start_col = 1, .end_col = 4 },
        rows.next().?,
    );
    try std.testing.expectEqual(
        Terminal.VisualDirtyRow{ .row = 1, .start_col = 0, .end_col = 2 },
        rows.next().?,
    );
    try std.testing.expect(rows.next() == null);

    terminal.hardReset();
    try std.testing.expect(terminal.selectionState() == null);
    terminal.startSelection(0, 0);
    try std.testing.expect(terminal.switchScreenMode(true, true, true));
    try std.testing.expect(terminal.selectionState() == null);
    terminal.startSelection(0, 0);
    try std.testing.expect(terminal.switchScreenMode(false, false, true));
    try std.testing.expect(terminal.selectionState() == null);
}

test "selection invalidates when retained endpoint is evicted or resized away" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 2, 3, 2);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("AAA\r\nBBB\r\nCCC")).state_changed);
    try std.testing.expect(terminal.scrollViewport(.top));
    terminal.startSelection(0, 0);
    terminal.finishSelection();
    try std.testing.expect((try terminal.feed("\r\nDDD\r\nEEE\r\nFFF")).state_changed);
    try std.testing.expect(terminal.selectionState() == null);

    var resized = try Terminal.init(std.testing.allocator, 2, 3);
    defer resized.deinit();
    resized.startSelection(1, 0);
    try resized.resize(1, 3);
    try std.testing.expect(resized.selectionState() == null);
}

fn copySelectionAllocation(allocator: std.mem.Allocator) !void {
    var terminal = try Terminal.init(allocator, 1, 4);
    defer terminal.deinit();
    terminal.screen_state.primary.writeText("COPY");
    terminal.startSelection(0, 0);
    terminal.updateSelection(0, 3);
    terminal.finishSelection();

    const copied = terminal.copySelection(allocator, std.math.maxInt(usize)) catch |err| {
        try std.testing.expect(terminal.selectionState() != null);
        try std.testing.expectEqual(@as(u21, 'C'), terminal.screen_state.primary.cellAt(0, 0));
        return err;
    };
    defer allocator.free(copied);
    try std.testing.expectEqualStrings("COPY", copied);
}

test "terminal rejects zero resize without changing dimensions" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 3);
    defer terminal.deinit();

    try std.testing.expectError(error.InvalidDimensions, terminal.resize(0, 3));
    const view = terminal.visualView().view;
    try std.testing.expectEqual(@as(u16, 2), view.rows);
    try std.testing.expectEqual(@as(u16, 3), view.cols);
}

test "terminal tracks synchronized output private mode" {
    var vt = try Terminal.init(std.testing.allocator, 2, 8);
    defer vt.deinit();
    var stream = try stream_harness.Harness.init(&vt);

    try stream.nextSlice("\x1b[?2026h");
    try std.testing.expect(vt.modes.synchronized_output);
    try std.testing.expect(vt.visualView().synchronized_output);

    try stream.nextSlice("\x1b[?2026l");
    try std.testing.expect(!vt.modes.synchronized_output);
    try std.testing.expect(!vt.visualView().synchronized_output);
}

test "stationary cursor movement advances visual identity outside synchronized output" {
    var vt = try Terminal.init(std.testing.allocator, 4, 8);
    defer vt.deinit();

    try std.testing.expect(!(try vt.feed("\x1b[?25h")).state_changed);
    const before = vt.visualView();
    try std.testing.expect(before.view.cursor_visible);
    const before_token = before.dirty_token;
    try std.testing.expect(vt.ackVisual(before_token));

    try std.testing.expect((try vt.feed("\x1b[3;4H")).state_changed);
    const after = vt.visualView();
    try std.testing.expect(after.dirty_token != before_token);
    try std.testing.expectEqual(@as(u16, 2), after.view.cursor_row);
    try std.testing.expectEqual(@as(u16, 3), after.view.cursor_col);
    try std.testing.expect(!after.synchronized_output);
}

test "synchronized update DCS shares exact bounded mode state" {
    var vt = try Terminal.init(std.testing.allocator, 2, 8);
    defer vt.deinit();

    try std.testing.expect(!(try vt.feed("\x1bP=1sbody")).state_changed);
    try std.testing.expect(!vt.modes.synchronized_output);
    try std.testing.expect((try vt.feed("\x1b\\")).state_changed);
    try std.testing.expect(vt.modes.synchronized_output);
    try std.testing.expect(!(try vt.feed("\x90=1s\x9c")).state_changed);

    try std.testing.expect(!(try vt.feed(
        "\x1bP=3s\x1b\\\x1bP=1;2s\x1b\\\x1bP=s\x1b\\\x1bP=1q\x1b\\\x1bP?1s\x1b\\",
    )).state_changed);
    try std.testing.expect(vt.modes.synchronized_output);
    try std.testing.expect((try vt.feed("\x90=2signored\x9c")).state_changed);
    try std.testing.expect(!vt.modes.synchronized_output);
    try std.testing.expect(!(try vt.feed("\x1bP=2s\x1b\\")).state_changed);

    try std.testing.expect((try vt.feed("\x1b[?2026h\x1b[?2026s\x1bP=2s\x1b\\")).state_changed);
    try std.testing.expect(!vt.modes.synchronized_output);
    try std.testing.expect((try vt.feed("\x1b[?2026r")).state_changed);
    try std.testing.expect(vt.modes.synchronized_output);
    try std.testing.expect((try vt.feed("\x1b[?2026$p")).state_changed);
    try std.testing.expectEqualStrings("\x1b[?2026;1$y", vt.host.pendingOutput());
    vt.host.clearPendingOutput();
    try std.testing.expect((try vt.feed("\x1bc")).state_changed);
    try std.testing.expect(!vt.modes.synchronized_output);
}

test "terminal visible view projects scrollback rows" {
    var vt = try Terminal.initWithHistory(std.testing.allocator, 2, 2, 4);
    defer vt.deinit();
    var stream = try stream_harness.Harness.init(&vt);

    try stream.nextSlice("aa\r\nbb\r\ncc");

    const live = screen_set.visibleView(&vt.screen_state, 0);
    try std.testing.expectEqual(0, live.scrollback_offset);
    try std.testing.expectEqual(@as(u21, 'b'), live.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'c'), live.cellAt(1, 0));

    const scrolled = screen_set.visibleView(&vt.screen_state, 1);
    try std.testing.expectEqual(1, scrolled.scrollback_offset);
    try std.testing.expectEqual(@as(u21, 'a'), scrolled.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), scrolled.cellAt(1, 0));
    try std.testing.expectEqual(2, scrolled.rowDepth(0));
    try std.testing.expectEqual(1, scrolled.rowDepth(1));
}

test "terminal Kitty unscroll consumes primary history in row order" {
    var vt = try Terminal.initWithHistory(std.testing.allocator, 3, 4, 8);
    defer vt.deinit();

    try std.testing.expect((try vt.feed("aaaa\r\nbbbb\r\ncccc\r\ndddd\r\neeee")).state_changed);
    try std.testing.expectEqual(@as(u32, 2), vt.visibleHistoryCount());
    vt.screen_state.active().cursor.setPositionByClient(1, 2);

    try std.testing.expect((try vt.feed("\x1b[2+T")).state_changed);
    try std.testing.expectEqual(@as(u32, 0), vt.visibleHistoryCount());
    try std.testing.expectEqual(@as(u21, 'a'), vt.screen_state.activeConst().cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), vt.screen_state.activeConst().cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'c'), vt.screen_state.activeConst().cellAt(2, 0));
    try std.testing.expectEqual(@as(u16, 1), vt.screen_state.activeConst().cursor.row);
    try std.testing.expectEqual(@as(u16, 2), vt.screen_state.activeConst().cursor.col);

    try vt.resize(3, 2);
    try std.testing.expectEqual(@as(u32, 3), vt.visibleHistoryCount());
    try std.testing.expectEqual(@as(u21, 'a'), vt.screen_state.primary.historyRowAt(2, 0));
    try std.testing.expectEqual(@as(u21, 'b'), vt.screen_state.primary.historyRowAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), vt.screen_state.primary.cellAt(0, 0));
}

test "terminal Kitty unscroll fragments and preserves alternate history" {
    var vt = try Terminal.initWithHistory(std.testing.allocator, 2, 3, 4);
    defer vt.deinit();

    try feedChanged(&vt, "aaa\r\nbbb\r\nccc");
    try std.testing.expectEqual(@as(u32, 1), vt.visibleHistoryCount());
    try feedChanged(&vt, "\x1b[?1049hxxx");
    try std.testing.expect(!(try vt.feed("\x1b[")).state_changed);
    try std.testing.expect((try vt.feed("+T")).state_changed);
    try std.testing.expectEqual(@as(u21, 0), vt.screen_state.alternate.cellAt(0, 0));
    try std.testing.expectEqual(@as(u32, 1), vt.screen_state.primary.historyCount());
    try feedChanged(&vt, "\x1b[?1049l\x1b[999999+T");
    try std.testing.expectEqual(@as(u32, 0), vt.visibleHistoryCount());
    try std.testing.expectEqual(@as(u21, 0), vt.screen_state.primary.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'a'), vt.screen_state.primary.cellAt(1, 0));
}

test "terminal Kitty unscroll preserves logical authority and cell facts" {
    var vt = try Terminal.initWithHistory(std.testing.allocator, 2, 4, 2);
    defer vt.deinit();

    try feedChanged(&vt, "\x1b[31mAAAA\r\n1111\r\n2222");
    try std.testing.expectEqual(@as(u32, 1), vt.visibleHistoryCount());
    try std.testing.expectEqual(@as(u21, 'A'), vt.screen_state.primary.historyRowAt(0, 0));
    try std.testing.expect((try vt.feed("\x1b[+T")).state_changed);
    try std.testing.expectEqual(@as(u32, 0), vt.visibleHistoryCount());
    try std.testing.expectEqual(@as(u21, 'A'), vt.screen_state.primary.cellAt(0, 0));
    try std.testing.expectEqual(
        terminal_mod.Screen.Color.indexed(1),
        vt.screen_state.primary.cellInfoAt(0, 0).attrs.fg,
    );

    try vt.resize(2, 2);
    try std.testing.expectEqual(@as(u32, 2), vt.visibleHistoryCount());
    try std.testing.expectEqual(@as(u21, 'A'), vt.screen_state.primary.historyRowAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'A'), vt.screen_state.primary.historyRowAt(0, 1));
}

test "terminal Kitty unscroll consumes wrapped history ring authority" {
    var vt = try Terminal.initWithHistory(std.testing.allocator, 2, 2, 2);
    defer vt.deinit();

    try feedChanged(&vt, "aa\r\nbb\r\ncc\r\ndd\r\nee");
    try std.testing.expectEqual(@as(u32, 2), vt.visibleHistoryCount());
    try std.testing.expectEqual(@as(u21, 'c'), vt.screen_state.primary.historyRowAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), vt.screen_state.primary.historyRowAt(1, 0));

    try feedChanged(&vt, "\x1b[+T");
    try std.testing.expectEqual(@as(u32, 1), vt.visibleHistoryCount());
    try feedChanged(&vt, "\x1b[2;1Hzz\r\n");
    try std.testing.expectEqual(@as(u32, 2), vt.visibleHistoryCount());

    try feedChanged(&vt, "\x1b[2+T");
    try std.testing.expectEqual(@as(u32, 0), vt.visibleHistoryCount());
    try std.testing.expectEqual(@as(u21, 'b'), vt.screen_state.primary.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'c'), vt.screen_state.primary.cellAt(1, 0));

    try vt.resize(2, 1);
    try std.testing.expectEqual(@as(u32, 2), vt.visibleHistoryCount());
    try std.testing.expectEqual(@as(u21, 'b'), vt.screen_state.primary.historyRowAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'b'), vt.screen_state.primary.historyRowAt(0, 0));
}

test "terminal Kitty unscroll consumes newest rows of one wrapped line" {
    var vt = try Terminal.initWithHistory(std.testing.allocator, 2, 3, 4);
    defer vt.deinit();

    try feedChanged(&vt, "abcdefghij");
    try std.testing.expectEqual(@as(u32, 2), vt.visibleHistoryCount());

    try feedChanged(&vt, "\x1b[+T");
    try std.testing.expectEqual(@as(u32, 1), vt.visibleHistoryCount());
    try std.testing.expectEqual(@as(u21, 'd'), vt.screen_state.primary.cellAt(0, 0));

    try feedChanged(&vt, "\x1b[+T");
    try std.testing.expectEqual(@as(u32, 0), vt.visibleHistoryCount());
    try std.testing.expectEqual(@as(u21, 'a'), vt.screen_state.primary.cellAt(0, 0));
}

test "terminal RIS delegates hard-reset owners" {
    var vt = try Terminal.init(std.testing.allocator, 2, 8);
    defer vt.deinit();
    var stream = try stream_harness.Harness.init(&vt);

    vt.screen_state.active().writeText("ab");
    vt.host.locator.mode = .continuous;
    vt.host.locator.coordinate_unit = 1;

    try stream.nextSlice("\x1bc");

    try std.testing.expectEqual(@as(u21, 0), vt.screen_state.activeConst().cellAt(0, 0));
    try std.testing.expect(vt.host.locator.mode == .disabled);
    try std.testing.expectEqual(@as(u16, 0), vt.host.locator.coordinate_unit);
}

test "terminal DECSTR preserves text and position while resetting terminal state" {
    var vt = try Terminal.init(std.testing.allocator, 4, 16);
    defer vt.deinit();
    var stream = try stream_harness.Harness.init(&vt);

    try stream.nextSlice("kept\x1b[2;9H\x1b[3g\x1b[?1;6;25;1000;1004;1006;2004h\x1b#6");
    try stream.nextSlice("\x1b[4;20h\x1b(B\x1b)0\x1b G");
    const row_before = vt.screen_state.activeConst().cursor.row;
    const col_before = vt.screen_state.activeConst().cursor.col;
    try std.testing.expect(vt.screen_state.activeConst().lineGeometry(row_before) == .double_width);
    try std.testing.expect(!vt.screen_state.activeConst().tabStopAt(8));
    try std.testing.expect(vt.host.pending_output.eight_bit_controls);

    const prefix = try vt.feed("\x1b[!");
    try std.testing.expect(!prefix.state_changed);
    const reset = try vt.feed("p");
    try std.testing.expect(reset.state_changed);

    const active = vt.screen_state.activeConst();
    try std.testing.expectEqual(@as(u21, 'k'), active.cellAt(0, 0));
    try std.testing.expectEqual(row_before, active.cursor.row);
    try std.testing.expectEqual(col_before, active.cursor.col);
    try std.testing.expect(active.lineGeometry(row_before) == .single_width);
    try std.testing.expect(active.tabStopAt(8));
    try std.testing.expect(active.auto_wrap);
    try std.testing.expect(!active.origin_mode);
    try std.testing.expect(!active.insert_mode);
    try std.testing.expect(active.cursor.visible);
    try std.testing.expect(!vt.modes.application_cursor_keys);
    try std.testing.expect(!vt.modes.application_keypad);
    try std.testing.expect(!vt.modes.newline_mode);
    try std.testing.expect(!vt.modes.focus_reporting);
    try std.testing.expect(!vt.modes.bracketed_paste);
    try std.testing.expect(vt.modes.mouse_tracking == .off);
    try std.testing.expect(vt.modes.mouse_protocol == .none);
    try std.testing.expect(!vt.host.pending_output.eight_bit_controls);
    try std.testing.expectEqual(@as(u8, 0), vt.gl_index);
    try std.testing.expectEqual(@as(u8, 1), vt.gr_index);
    try std.testing.expectEqual([_]u8{ 'B', 'B', 'B', 'B' }, vt.designations);

    const repeated = try vt.feed("\x1b[!p");
    try std.testing.expect(!repeated.state_changed);
}

test "terminal DECSTR resets mirrored modes across alternate-screen banks" {
    var vt = try Terminal.init(std.testing.allocator, 3, 12);
    defer vt.deinit();

    try std.testing.expect((try vt.feed("\x1b[4h\x1b[?69h\x1b[?25l\x1b[?47h")).state_changed);
    try std.testing.expect(vt.screen_state.primary.insert_mode);
    try std.testing.expect(vt.screen_state.alternate.insert_mode);
    try std.testing.expect(vt.screen_state.primary.left_right_margin_mode);
    try std.testing.expect(vt.screen_state.alternate.left_right_margin_mode);
    try std.testing.expect(!vt.screen_state.primary.cursor.visible);
    try std.testing.expect(!vt.screen_state.alternate.cursor.visible);

    try std.testing.expect((try vt.feed("\x1b[!p")).state_changed);
    try std.testing.expect(!vt.screen_state.primary.insert_mode);
    try std.testing.expect(!vt.screen_state.alternate.insert_mode);
    try std.testing.expect(!vt.screen_state.primary.left_right_margin_mode);
    try std.testing.expect(!vt.screen_state.alternate.left_right_margin_mode);
    try std.testing.expect(vt.screen_state.primary.cursor.visible);
    try std.testing.expect(vt.screen_state.alternate.cursor.visible);
    try std.testing.expect(!(try vt.feed("\x1b[!p")).state_changed);

    try std.testing.expect((try vt.feed("\x1b[?47l")).state_changed);
    try std.testing.expect(!vt.screen_state.activeConst().insert_mode);
    try std.testing.expect(!vt.screen_state.activeConst().left_right_margin_mode);
    try std.testing.expect(vt.screen_state.activeConst().cursor.visible);
}

test "terminal save reset and alternate lifecycle stays coherent across resize and bank changes" {
    var vt = try Terminal.init(std.testing.allocator, 4, 8);
    defer vt.deinit();

    // Save a primary cursor at the old edge with rendition and charset facts
    // that must survive an alternate-bank soft reset and a narrower resize.
    try std.testing.expect((try vt.feed(
        "PRIMARY\x1b[4;8H\x1b[1;3m\x1b)0\x0e\x1b[?5h\x1b[?1049h",
    )).state_changed);
    try std.testing.expect(vt.screen_state.alt_active);
    try std.testing.expectEqual(@as(u21, 0), vt.screen_state.alternate.cellAt(0, 0));

    // DECSTR is active-bank-local for row state and terminal-global for the
    // mirrored input, margin, and visibility facts owned by Terminal.
    try std.testing.expect((try vt.feed(
        "ALT\x1b[4h\x1b[?25l\x1b[?69h\x1b[2;5s\x1b[3;4H\x1b[!p",
    )).state_changed);
    try std.testing.expect(vt.screen_state.alt_active);
    try std.testing.expectEqual(@as(u21, 'A'), vt.screen_state.alternate.cellAt(0, 0));
    try std.testing.expectEqual(@as(u16, 2), vt.screen_state.alternate.cursor.row);
    try std.testing.expectEqual(@as(u16, 3), vt.screen_state.alternate.cursor.col);
    try std.testing.expect(!vt.screen_state.primary.insert_mode);
    try std.testing.expect(!vt.screen_state.alternate.insert_mode);
    try std.testing.expect(!vt.screen_state.primary.left_right_margin_mode);
    try std.testing.expect(!vt.screen_state.alternate.left_right_margin_mode);
    try std.testing.expect(vt.screen_state.primary.cursor.visible);
    try std.testing.expect(vt.screen_state.alternate.cursor.visible);
    try std.testing.expect(!(try vt.feed("\x1b[!p")).state_changed);

    try vt.resize(2, 4);
    try std.testing.expect((try vt.feed("\x1b[?1049l")).state_changed);
    try std.testing.expect(!vt.screen_state.alt_active);
    try std.testing.expectEqual(@as(u16, 1), vt.screen_state.primary.cursor.row);
    try std.testing.expectEqual(@as(u16, 3), vt.screen_state.primary.cursor.col);
    try std.testing.expect(vt.screen_state.primary.current_attrs.bold);
    try std.testing.expect(vt.screen_state.primary.current_attrs.italic);
    try std.testing.expect(vt.modes.reverse_screen_mode);
    try std.testing.expectEqual(@as(u8, 1), vt.gl_index);
    try std.testing.expectEqual(@as(u8, '0'), vt.designations[1]);

    // RIS resets the selected bank and all terminal-global save state without
    // inventing an implicit screen switch or erasing the inactive bank.
    try std.testing.expect((try vt.feed("\x1b[HKEEP\x1b[?47hALT2\x1b7\x1bc")).state_changed);
    try std.testing.expect(vt.screen_state.alt_active);
    try std.testing.expectEqual(@as(u21, 0), vt.screen_state.alternate.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'K'), vt.screen_state.primary.cellAt(0, 0));
    try std.testing.expect(!vt.modes.reverse_screen_mode);
    try std.testing.expectEqual(@as(u8, 0), vt.gl_index);
    try std.testing.expectEqual([_]u8{ 'B', 'B', 'B', 'B' }, vt.designations);

    try std.testing.expect((try vt.feed("\x1b[?47l\x1b8")).state_changed);
    try std.testing.expect(!vt.screen_state.alt_active);
    try std.testing.expectEqual(@as(u16, 0), vt.screen_state.primary.cursor.row);
    try std.testing.expectEqual(@as(u16, 0), vt.screen_state.primary.cursor.col);
    try std.testing.expect(vt.screen_state.primary.current_attrs.bold);
    try std.testing.expect(vt.screen_state.primary.current_attrs.italic);
}
