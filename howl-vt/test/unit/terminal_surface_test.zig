const std = @import("std");
const terminal_mod = @import("../../src/terminal.zig");
const screen = @import("../../src/terminal.zig");
const screen_capture = @import("../support/screen_capture.zig");
const screen_set = @import("../../src/terminal.zig");
const selection_projection = @import("../../src/terminal.zig");
const input_encode = @import("../../src/terminal.zig");
const input_keyboard = @import("../../src/terminal.zig");
const stream_harness = @import("../support/stream_harness.zig");

const Terminal = terminal_mod.Terminal;
const Screen = screen.Screen;
const StreamHarness = stream_harness.Harness;

var encode_scratch: input_encode.Scratch = .{};

fn encodeKey(terminal: *Terminal, key: input_keyboard.InputKey, mod: input_keyboard.Modifier) []const u8 {
    var encoded = terminal.encodeInput(std.testing.allocator, &encode_scratch, .{ .key = .{ .key = key, .mods = mod } }) catch unreachable;
    defer encoded.deinit();
    return encoded.bytes;
}

fn activeScreen(terminal: *const Terminal) *const Screen {
    return terminal.screen_state.activeConst();
}

fn visibleView(terminal: *const Terminal, scrollback_offset: u32) screen_set.View {
    return screen_set.visibleView(&terminal.screen_state, scrollback_offset);
}

fn historyCapacity(terminal: *const Terminal) u16 {
    return screen_set.historyCapacity(&terminal.screen_state);
}

fn clearDirtyRows(terminal: *Terminal) void {
    screen_set.clearDirtyRows(&terminal.screen_state);
}

fn visualDirtyRow(view: Terminal.VisualView, row: u16) ?Terminal.VisualDirtyRow {
    const rows = switch (view.dirty) {
        .rows => |rows| rows,
        else => return null,
    };
    var iterator = rows.iterator();
    while (iterator.next()) |dirty| {
        if (dirty.row == row) return dirty;
    }
    return null;
}

fn expectVisualDirtyRow(view: Terminal.VisualView, row: u16, start_col: u16, end_col: u16) !void {
    try std.testing.expectEqual(
        Terminal.VisualDirtyRow{ .row = row, .start_col = start_col, .end_col = end_col },
        visualDirtyRow(view, row).?,
    );
}

fn captureSnapshot(terminal: *const Terminal) !screen_capture.Capture {
    return screen_capture.Capture.captureFromScreen(
        terminal.allocator,
        terminal.screen_state.activeConst(),
        terminal.screen_state.activeSelectionConst().state(),
    );
}

fn resizeTerminal(terminal: *Terminal, rows: u16, cols: u16) !void {
    try terminal.screen_state.resize(terminal.allocator, rows, cols);
    terminal.screen_state.activeSelection().clearIfInvalidatedByGrid(terminal.screen_state.activeConst());
}

test "snapshot capture remains deterministic" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 5, 10);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("TEST");

    var snap1 = try captureSnapshot(&terminal);
    defer snap1.deinit();

    var snap2 = try captureSnapshot(&terminal);
    defer snap2.deinit();

    try std.testing.expectEqual(snap1.rows, snap2.rows);
    try std.testing.expectEqual(snap1.cols, snap2.cols);
    try std.testing.expectEqual(snap1.cursor_row, snap2.cursor_row);
    try std.testing.expectEqual(snap1.cursor_col, snap2.cursor_col);
}

test "resize keeps history enabled state" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithHistory(allocator, 1, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("111\n222\n333");
    const before = visibleView(&terminal, 0).history_count;
    try resizeTerminal(&terminal, 3, 3);

    try std.testing.expectEqual(@as(u16, 8), historyCapacity(&terminal));
    try std.testing.expect(visibleView(&terminal, 0).history_count <= before);
}

test "alternate screen exit preserves primary scrollback" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithHistory(allocator, 2, 4, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("AAAA\nBBBB\nCCCC\nDDDD");
    var before = try captureSnapshot(&terminal);
    defer before.deinit();
    const history_before = visibleView(&terminal, 0).history_count;
    try std.testing.expect(history_before > 0);

    try stream.nextSlice("\x1b[?1049hALT!");
    try std.testing.expect(visibleView(&terminal, 0).is_alternate_screen);
    try std.testing.expectEqual(@as(u32, 0), visibleView(&terminal, 0).history_count);
    try std.testing.expectEqual(@as(u21, 'A'), activeScreen(&terminal).cellAt(0, 0));

    try stream.nextSlice("\x1b[?1049l");
    var after = try captureSnapshot(&terminal);
    defer after.deinit();
    try std.testing.expect(!visibleView(&terminal, 0).is_alternate_screen);
    try std.testing.expectEqual(history_before, visibleView(&terminal, 0).history_count);
    try std.testing.expectEqual(before.cursor_row, after.cursor_row);
    try std.testing.expectEqual(before.cursor_col, after.cursor_col);
    var row: u16 = 0;
    while (row < before.rows) : (row += 1) {
        var col: u16 = 0;
        while (col < before.cols) : (col += 1) {
            try std.testing.expectEqual(before.cellAt(row, col), after.cellAt(row, col));
        }
    }
}

test "alternate screen 1049 restores primary cursor" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b[3;4H");
    const before_enter = activeScreen(&terminal).cursor.position_changed_by_client_at;
    try stream.nextSlice("\x1b[3;4H\x1b[?1049h\x1b[2;2H\x1b[?1049l");
    try std.testing.expectEqual(@as(u16, 2), activeScreen(&terminal).cursor.row);
    try std.testing.expectEqual(@as(u16, 3), activeScreen(&terminal).cursor.col);
    try std.testing.expectEqual(before_enter, activeScreen(&terminal).cursor.position_changed_by_client_at);
}

test "alternate screen switches mark active viewport fully dirty" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 4);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    clearDirtyRows(&terminal);
    try stream.nextSlice("\x1b[?1049h");
    const enter_dirty = activeScreen(&terminal).peekDirtyRows().?;
    try std.testing.expectEqual(@as(u16, 0), enter_dirty.start_row);
    try std.testing.expectEqual(@as(u16, 2), enter_dirty.end_row);
    try std.testing.expectEqual(@as(u16, 0), enter_dirty.dirty_cols_start[0]);
    try std.testing.expectEqual(@as(u16, 3), enter_dirty.dirty_cols_end[2]);

    clearDirtyRows(&terminal);
    try stream.nextSlice("\x1b[?1049l");
    const exit_dirty = activeScreen(&terminal).peekDirtyRows().?;
    try std.testing.expectEqual(@as(u16, 0), exit_dirty.start_row);
    try std.testing.expectEqual(@as(u16, 2), exit_dirty.end_row);
    try std.testing.expectEqual(@as(u16, 0), exit_dirty.dirty_cols_start[0]);
    try std.testing.expectEqual(@as(u16, 3), exit_dirty.dirty_cols_end[2]);
}

test "state snapshot borrows metadata and tracks alternate identity" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();

    const initial = try terminal.feed("\x1b]2;first\x07\x1b]1;one\x07");
    try std.testing.expect(initial.title_changed);
    try std.testing.expect(initial.icon_changed);
    const first = terminal.stateSnapshot();
    const first_visual = terminal.visualView();
    try std.testing.expectEqualStrings("first", first.title.?);
    try std.testing.expectEqualStrings("one", first.icon.?);
    try std.testing.expect(!first.is_alternate_screen);

    const changed = try terminal.feed("\x1b]2;second\x07\x1b[?1049h");
    try std.testing.expect(changed.title_changed);
    const second = terminal.stateSnapshot();
    try std.testing.expect(terminal.visualView().dirty_token != first_visual.dirty_token);
    try std.testing.expectEqualStrings("second", second.title.?);
    try std.testing.expectEqualStrings("one", second.icon.?);
    try std.testing.expect(second.is_alternate_screen);

    const restored = try terminal.feed("\x1b[?1049l");
    try std.testing.expect(restored.state_changed);
    const primary = terminal.stateSnapshot();
    try std.testing.expect(!primary.is_alternate_screen);
}

test "alternate screen switching clears selection on the screen-set owner path" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 4);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    terminal.startSelection(0, 0);
    try std.testing.expect(terminal.selectionState() != null);

    try stream.nextSlice("\x1b[?1049h");
    try std.testing.expect(terminal.selectionState() == null);

    terminal.startSelection(0, 0);
    try std.testing.expect(terminal.selectionState() != null);

    try stream.nextSlice("\x1b[?1049l");
    try std.testing.expect(terminal.selectionState() == null);
}

test "visual view accumulates sparse cells and derives cursor overlay independently" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();

    const initial = terminal.visualView();
    try std.testing.expect(initial.dirty == .full);
    try std.testing.expect(terminal.ackVisual(initial.dirty_token));
    try std.testing.expect(!terminal.ackVisual(initial.dirty_token));

    try std.testing.expect((try terminal.feed("\x1b[2;3HX")).state_changed);
    const first = terminal.visualView();
    try expectVisualDirtyRow(first, 1, 2, 2);

    try std.testing.expect((try terminal.feed("\x1b[1;5HY")).state_changed);
    const cumulative = terminal.visualView();
    try expectVisualDirtyRow(cumulative, 0, 4, 4);
    try expectVisualDirtyRow(cumulative, 1, 2, 2);
    try std.testing.expect(!terminal.ackVisual(first.dirty_token));
    try std.testing.expect(terminal.ackVisual(cumulative.dirty_token));

    try std.testing.expect((try terminal.feed("\x1b[3;2H")).state_changed);
    const cursor_only = terminal.visualView();
    try std.testing.expect(cursor_only.dirty == .none);
    try std.testing.expect(cursor_only.dirty_token != cumulative.dirty_token);
    try std.testing.expect(terminal.ackVisual(cursor_only.dirty_token));

    try std.testing.expect((try terminal.feed("\x1b]2;metadata-only\x07")).title_changed);
    const metadata_only = terminal.visualView();
    try std.testing.expectEqual(cursor_only.dirty_token, metadata_only.dirty_token);
    try std.testing.expect(metadata_only.dirty == .none);
}

test "OSC 66 dirtiness and selection expand across the complete cluster" {
    var terminal = try Terminal.init(std.testing.allocator, 4, 8);
    defer terminal.deinit();
    try std.testing.expect(terminal.ackVisual(terminal.visualView().dirty_token));

    try std.testing.expect((try terminal.feed("\x1b]66;s=2:w=2;Hi\x1b\\")).state_changed);
    const created = terminal.visualView();
    try expectVisualDirtyRow(created, 0, 0, 3);
    try expectVisualDirtyRow(created, 1, 0, 3);
    try std.testing.expect(terminal.ackVisual(created.dirty_token));

    terminal.startSelection(0, 2);
    terminal.updateSelection(0, 3);
    const selected = terminal.visualView();
    try expectVisualDirtyRow(selected, 0, 0, 3);
    try expectVisualDirtyRow(selected, 1, 0, 3);
}

test "semantic sequence spans visual and host consequence mutation truth" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    const initial = terminal.semanticSequence();
    const initial_visual = terminal.visualView().dirty_token;

    const ignored = try terminal.feed("\x1b[?9999h");
    try std.testing.expect(!ignored.state_changed);
    try std.testing.expectEqual(initial, terminal.semanticSequence());
    try std.testing.expect((try terminal.feed("A")).state_changed);
    const partial_line = terminal.semanticSequence();
    try std.testing.expect(partial_line > initial);
    try std.testing.expect((try terminal.feed("\r")).state_changed);
    const cursor = terminal.semanticSequence();
    try std.testing.expect(cursor > partial_line);

    const before_title_visual = terminal.visualView().dirty_token;
    try std.testing.expect((try terminal.feed("\x1b]2;owner truth\x07")).title_changed);
    const title = terminal.semanticSequence();
    try std.testing.expect(title > cursor);
    try std.testing.expectEqual(before_title_visual, terminal.visualView().dirty_token);
    const repeated_title = try terminal.feed("\x1b]2;owner truth\x07");
    try std.testing.expect(!repeated_title.state_changed);
    try std.testing.expectEqual(title, terminal.semanticSequence());
    try std.testing.expect((try terminal.feed("\x07")).state_changed);
    try std.testing.expect(terminal.semanticSequence() > title);
    try std.testing.expect(initial_visual != terminal.visualView().dirty_token);

    const before_resize = terminal.semanticSequence();
    try terminal.resize(3, 9);
    try std.testing.expect(terminal.semanticSequence() > before_resize);

    try std.testing.expect((try terminal.feed("Z")).state_changed);
    const before_reset = terminal.semanticSequence();
    try std.testing.expect((try terminal.feed("\x1bc")).state_changed);
    const reset = terminal.semanticSequence();
    try std.testing.expect(reset > before_reset);
    const repeated_reset = try terminal.feed("\x1bc");
    try std.testing.expect(repeated_reset.state_changed);
    try std.testing.expect(terminal.semanticSequence() > reset);

    terminal.host.bell_generation = std.math.maxInt(u64);
    const before_partial_failure = terminal.semanticSequence();
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed("Q\x07"));
    try std.testing.expect(terminal.semanticSequence() > before_partial_failure);
    const before_rejected = terminal.semanticSequence();
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed("\x07"));
    try std.testing.expectEqual(before_rejected, terminal.semanticSequence());
}

test "visual view marks selection geometry and source-wide discontinuities exactly" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();

    const initial = terminal.visualView();
    try std.testing.expectEqual(@as(usize, 8), initial.view.rowCells(0).len);
    try std.testing.expect(terminal.ackVisual(initial.dirty_token));
    try std.testing.expect((try terminal.feed("abcdef")).state_changed);
    try std.testing.expect(terminal.ackVisual(terminal.visualView().dirty_token));

    terminal.startSelection(0, 1);
    terminal.updateSelection(0, 3);
    const selected = terminal.visualView();
    try expectVisualDirtyRow(selected, 0, 1, 3);
    try std.testing.expect(terminal.ackVisual(selected.dirty_token));

    terminal.clearSelection();
    const cleared = terminal.visualView();
    try expectVisualDirtyRow(cleared, 0, 1, 3);
    try std.testing.expect(terminal.ackVisual(cleared.dirty_token));

    try std.testing.expect((try terminal.feed("\x1b[2;1H\x1b#6")).state_changed);
    const geometry = terminal.visualView();
    try expectVisualDirtyRow(geometry, 1, 0, 7);
    try std.testing.expect(terminal.ackVisual(geometry.dirty_token));

    try std.testing.expect((try terminal.feed("\x1b]4;1;#010203\x1b\\")).state_changed);
    try std.testing.expect(terminal.visualView().dirty == .full);
    try std.testing.expect(terminal.ackVisual(terminal.visualView().dirty_token));

    try terminal.resize(4, 10);
    const resized = terminal.visualView();
    try std.testing.expect(resized.dirty == .full);
    try std.testing.expectEqual(@as(u16, 4), resized.view.rows);
    try std.testing.expectEqual(@as(u16, 10), resized.view.cols);
    try std.testing.expectEqual(@as(usize, 10), resized.view.rowCells(0).len);

    try std.testing.expect((try terminal.feed("\x1bc")).state_changed);
    const reset = terminal.visualView();
    try std.testing.expect(reset.dirty == .full);
    try std.testing.expectEqual(@as(usize, 10), reset.view.rowCells(0).len);
}

test "visual view remains cumulative across fragmented stream mutation" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    try std.testing.expect(terminal.ackVisual(terminal.visualView().dirty_token));

    var stream = terminal.vtStream();
    try stream.nextSlice("A");
    const first = terminal.visualView();
    try stream.nextSlice("B");
    const second = terminal.visualView();

    try std.testing.expect(!terminal.ackVisual(first.dirty_token));
    try expectVisualDirtyRow(second, 0, 0, 1);
    try std.testing.expect(terminal.ackVisual(second.dirty_token));
}

test "full-screen scroll dirties only exposed bottom row" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithHistory(allocator, 3, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("AAAA\nBBBB\nCCCC");
    clearDirtyRows(&terminal);

    try stream.nextSlice("\nDDDD");

    const dirty = activeScreen(&terminal).peekDirtyRows().?;
    try std.testing.expectEqual(@as(u16, 2), dirty.start_row);
    try std.testing.expectEqual(@as(u16, 2), dirty.end_row);
    try std.testing.expectEqual(@as(u16, 0), dirty.dirty_cols_start[2]);
    try std.testing.expectEqual(@as(u16, 3), dirty.dirty_cols_end[2]);
}

test "terminal feed fails overlong OSC instead of truncating it" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 2, 4);
    defer terminal.deinit();
    const clean = terminal.visualView();
    try std.testing.expect(terminal.ackVisual(clean.dirty_token));

    var bytes = try std.ArrayList(u8).initCapacity(allocator, 4_103);
    defer bytes.deinit(allocator);
    try bytes.appendSlice(allocator, "X\x1b]0;");
    try bytes.appendNTimes(allocator, 'A', 4_097);
    try bytes.append(allocator, 0x07);

    try std.testing.expectError(error.StringControlLimit, terminal.feed(bytes.items));
    const partial = terminal.visualView();
    try std.testing.expect(partial.dirty_token != clean.dirty_token);
    try std.testing.expectEqual(@as(u21, 'X'), partial.view.cellAt(0, 0));
    try expectVisualDirtyRow(partial, 0, 0, 0);

    const recovered = try terminal.feed("A");
    try std.testing.expect(recovered.state_changed);
}

test "terminal feed streams discarded PM and resumes visible text" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 2, 4);
    defer terminal.deinit();

    const start = try terminal.feed("\x1b^");
    try std.testing.expect(!start.state_changed);

    const chunk = try allocator.alloc(u8, 8 * 1024);
    defer allocator.free(chunk);
    @memset(chunk, 'P');

    var chunk_index: u8 = 0;
    while (chunk_index < 4) : (chunk_index += 1) {
        const streamed = try terminal.feed(chunk);
        try std.testing.expect(!streamed.state_changed);
    }
    const finish = try terminal.feed("\x1b\\");
    try std.testing.expect(!finish.state_changed);

    const recovered = try terminal.feed("A");
    try std.testing.expect(recovered.state_changed);
    try std.testing.expectEqual(@as(u21, 'A'), activeScreen(&terminal).cellAt(0, 0));
}

test "input encoding APIs are callable without terminal facade methods" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 5, 10);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("TEST");

    var snap_before = try captureSnapshot(&terminal);
    defer snap_before.deinit();

    _ = encodeKey(&terminal, try input_keyboard.InputKey.initUnicode('A'), .{});
    _ = encodeKey(&terminal, try input_keyboard.InputKey.initUnicode('B'), .{});

    var snap_after = try captureSnapshot(&terminal);
    defer snap_after.deinit();

    try std.testing.expectEqual(snap_before.cursor_row, snap_after.cursor_row);
    try std.testing.expectEqual(snap_before.cursor_col, snap_after.cursor_col);
    try std.testing.expectEqual(snap_before.history_count, snap_after.history_count);
    try std.testing.expectEqual(snap_before.selection, snap_after.selection);
}

test "selection follows viewport movement through scrollback rows" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithHistory(allocator, 2, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("aa\r\nbb\r\ncc");

    terminal.startSelection(0, 0);
    terminal.updateSelection(1, 1);
    terminal.finishSelection();

    const live = terminal.visualView();
    const selected = @as(?selection_projection.Range, .{ .start = 0, .end_exclusive = 2 });
    try std.testing.expectEqual(selected, live.selectedSpan(0));
    try std.testing.expectEqual(selected, live.selectedSpan(1));

    try std.testing.expect(terminal.scrollViewport(.{ .absolute = 1 }));
    const scrolled = terminal.visualView();
    try std.testing.expectEqual(@as(?selection_projection.Range, null), scrolled.selectedSpan(0));
    try std.testing.expectEqual(selected, scrolled.selectedSpan(1));
    try std.testing.expectEqual(@as(?selection_projection.Range, null), scrolled.selectedSpan(2));
}

test "visual dirty rows resolve a mixed history and screen viewport" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 4, 6, 8);
    defer terminal.deinit();

    const history = "111111\r\n222222\r\n333333\r\n444444\r\n555555\r\n666666";
    try std.testing.expect((try terminal.feed(history)).state_changed);
    try std.testing.expect(terminal.scrollViewport(.{ .absolute = 2 }));
    const mixed = terminal.visualView();
    const expected_rows = [_]u21{ '1', '2', '3', '4' };
    for (expected_rows, 0..) |expected, row| {
        const cells = mixed.view.rowCells(@intCast(row));
        try std.testing.expectEqual(@as(usize, 6), cells.len);
        try std.testing.expectEqual(expected, cells[0].codepoint);
        for (cells, 0..) |cell, col| {
            try std.testing.expectEqual(cell, mixed.view.cellInfoAt(@intCast(row), @intCast(col)));
        }
    }
    try std.testing.expect(terminal.ackVisual(mixed.dirty_token));

    try std.testing.expect((try terminal.feed("\x1b[1;2HX\x1b[4;5HY")).state_changed);
    const visual = terminal.visualView();
    try std.testing.expectEqual(@as(u32, 2), visual.view.scrollback_offset);
    try expectVisualDirtyRow(visual, 2, 1, 1);
    try std.testing.expect(visualDirtyRow(visual, 0) == null);
    try std.testing.expect(visualDirtyRow(visual, 1) == null);
    try std.testing.expect(visualDirtyRow(visual, 3) == null);
}

test "visual hyperlink borrow requires the exact current visual identity" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 4);
    defer terminal.deinit();

    const current = terminal.visualView();
    try std.testing.expect(terminal.ackVisual(current.dirty_token));
    try std.testing.expect(try terminal.visibleCellHyperlinkUri(current.dirty_token, 0, 0) == null);

    try std.testing.expect((try terminal.feed("X")).state_changed);
    try std.testing.expectError(error.InvalidArgument, terminal.visibleCellHyperlinkUri(current.dirty_token, 0, 0));
}

test "retained animation frames stay visually clean until monotonic selection" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 4);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed(
        "\x1b_Ga=T,f=32,s=1,v=1,i=31,q=2;/wAA/w==\x1b\\",
    )).state_changed);
    try std.testing.expect(terminal.ackVisual(terminal.visualView().dirty_token));
    const clean = terminal.visualView().dirty_token;
    const semantic = terminal.semanticSequence();
    try std.testing.expect((try terminal.feed(
        "\x1b_Ga=f,f=32,s=1,v=1,i=31,r=2,q=2;AAD//w==\x1b\\",
    )).state_changed);
    try std.testing.expect(terminal.semanticSequence() > semantic);
    try std.testing.expectEqual(clean, terminal.visualView().dirty_token);
    try std.testing.expect((try terminal.feed("\x1b_Ga=a,i=31,s=3,q=2\x1b\\")).state_changed);
    try std.testing.expect(!terminal.advanceGraphics(100).changed);
    try std.testing.expect(terminal.advanceGraphics(140).changed);
    try std.testing.expect(clean != terminal.visualView().dirty_token);
}

test "cursor hides when viewport is scrolled off live bottom" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithHistory(allocator, 2, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("aa\r\nbb\r\ncc");

    try std.testing.expect(visibleView(&terminal, 0).cursor_visible);
    try std.testing.expect(!visibleView(&terminal, 1).cursor_visible);
}
