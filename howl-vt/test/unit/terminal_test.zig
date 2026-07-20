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

test "open logical output is publication scoped and does not advance its cursor" {
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
    try std.testing.expect(second.publication > first.publication);
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
    var chunk: [64 * 1024]u8 = .{'x'} ** (64 * 1024);
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
    var probe = std.testing.FailingAllocator.init(std.testing.allocator, .{});
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

    var wrapped_probe = std.testing.FailingAllocator.init(std.testing.allocator, .{});
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

    var full_probe = std.testing.FailingAllocator.init(std.testing.allocator, .{});
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
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = fail_index });
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
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = fail_index });
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
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = fail_index });
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
    const dirty_generation_before = terminal.dirty_generation;

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
        try std.testing.expectEqual(dirty_generation_before, terminal.dirty_generation);
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
    try std.testing.expectEqual(dirty_generation_before + 1, terminal.dirty_generation);
}

test "selection copy owns exact allocation and codepoint failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, copySelectionAllocation, .{});

    var terminal = try Terminal.init(std.testing.allocator, 1, 1);
    defer terminal.deinit();
    terminal.startSelection(0, 0);
    terminal.finishSelection();

    terminal.screen_state.primary.cells.?[0].codepoint = 0x110000;
    try std.testing.expectError(error.CodepointTooLarge, terminal.copySelection(std.testing.allocator));
    terminal.screen_state.primary.cells.?[0].codepoint = 0xD800;
    try std.testing.expectError(error.Utf8CannotEncodeSurrogateHalf, terminal.copySelection(std.testing.allocator));
}

fn copySelectionAllocation(allocator: std.mem.Allocator) !void {
    var terminal = try Terminal.init(allocator, 1, 4);
    defer terminal.deinit();
    terminal.screen_state.primary.writeText("COPY");
    terminal.startSelection(0, 0);
    terminal.updateSelection(0, 3);
    terminal.finishSelection();

    const copied = terminal.copySelection(allocator) catch |err| {
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
    const view = terminal.surfaceSnapshot().snapshot.view;
    try std.testing.expectEqual(@as(u16, 2), view.rows);
    try std.testing.expectEqual(@as(u16, 3), view.cols);
}

test "terminal tracks synchronized output private mode" {
    var vt = try Terminal.init(std.testing.allocator, 2, 8);
    defer vt.deinit();
    var stream = try stream_harness.Harness.init(&vt);

    try stream.nextSlice("\x1b[?2026h");
    try std.testing.expect(vt.modes.synchronized_output);

    try stream.nextSlice("\x1b[?2026l");
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

    try stream.nextSlice("kept\x1b[2;9H\x1b#6\x1b[3g\x1b[?1;6;25;1000;1004;1006;2004h");
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
