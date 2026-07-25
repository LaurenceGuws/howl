const std = @import("std");
const screen_capture = @import("../support/screen_capture.zig");
const screen_set = @import("../../src/terminal.zig");
const terminal_mod = @import("../../src/terminal.zig");
const stream_harness = @import("../support/stream_harness.zig");

const Terminal = terminal_mod.Terminal;
const StreamHarness = stream_harness.Harness;

fn gridCellCount(rows: u16, cols: u16) u32 {
    return @as(u32, rows) * @as(u32, cols);
}

fn captureSnapshot(terminal: *const Terminal) !screen_capture.Capture {
    return screen_capture.Capture.captureFromScreen(
        terminal.allocator,
        terminal.screen_state.activeConst(),
    );
}

fn visibleView(terminal: *const Terminal) screen_set.View {
    return screen_set.visibleView(&terminal.screen_state, 0);
}

test "snapshot: capture from simple text" {
    const gpa = std.testing.allocator;
    var terminal = try Terminal.init(gpa, 5, 10);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("HELLO");

    var snap = try captureSnapshot(&terminal);
    defer snap.deinit();

    try std.testing.expectEqual(@as(u16, 5), snap.rows);
    try std.testing.expectEqual(@as(u16, 10), snap.cols);
    try std.testing.expectEqual(@as(u16, 0), snap.cursor_row);
    try std.testing.expectEqual(@as(u16, 5), snap.cursor_col);
    try std.testing.expectEqual(true, snap.cursor_visible);
    try std.testing.expectEqual(@as(@TypeOf(snap.cursor_shape), .block), snap.cursor_shape);
    try std.testing.expectEqual(true, snap.cursor_blink);
    try std.testing.expectEqual(true, snap.auto_wrap);
    try std.testing.expectEqual(@as(u21, 'H'), snap.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'E'), snap.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'L'), snap.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 'L'), snap.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'O'), snap.cellAt(0, 4));
}

test "snapshot: determinism across identical state" {
    const gpa = std.testing.allocator;

    var vt_core1 = try Terminal.init(gpa, 5, 10);
    defer vt_core1.deinit();
    var stream1 = try StreamHarness.init(&vt_core1);
    try stream1.nextSlice("TEST");
    var snap1 = try captureSnapshot(&vt_core1);
    defer snap1.deinit();

    var vt_core2 = try Terminal.init(gpa, 5, 10);
    defer vt_core2.deinit();
    var stream2 = try StreamHarness.init(&vt_core2);
    try stream2.nextSlice("TEST");
    var snap2 = try captureSnapshot(&vt_core2);
    defer snap2.deinit();

    try std.testing.expectEqual(snap1.cursor_row, snap2.cursor_row);
    try std.testing.expectEqual(snap1.cursor_col, snap2.cursor_col);
    try std.testing.expectEqual(snap1.cursor_visible, snap2.cursor_visible);
    try std.testing.expectEqual(snap1.cursor_shape, snap2.cursor_shape);
    try std.testing.expectEqual(snap1.cursor_blink, snap2.cursor_blink);
    try std.testing.expectEqual(snap1.auto_wrap, snap2.auto_wrap);

    if (snap1.cells != null and snap2.cells != null) {
        const size = gridCellCount(snap1.rows, snap1.cols);
        try std.testing.expectEqualSlices(u21, snap1.cells.?[0..@intCast(size)], snap2.cells.?[0..@intCast(size)]);
    }
}

test "visual view carries OSC colors and complete cell presentation" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 4);
    defer terminal.deinit();
    const summary = try terminal.feed(
        "\x1b]4;2;#010203\x1b\\" ++
            "\x1b]10;#111213\x1b\\" ++
            "\x1b]11;#212223\x1b\\" ++
            "\x1b]12;#313233\x1b\\" ++
            "\x1b[38;5;2;48;2;4;5;6;58;2;7;8;9;2;4:3;8;9mX",
    );
    try std.testing.expect(summary.state_changed);

    const presentation = terminal.presentation();
    try std.testing.expectEqual(
        Terminal.Rgb{ .r = 1, .g = 2, .b = 3 },
        presentation.palette[2],
    );
    try std.testing.expectEqual(
        Terminal.Rgb{ .r = 0x11, .g = 0x12, .b = 0x13 },
        presentation.foreground,
    );
    try std.testing.expectEqual(
        Terminal.Rgb{ .r = 0x21, .g = 0x22, .b = 0x23 },
        presentation.background,
    );
    try std.testing.expectEqual(
        @as(?Terminal.Rgb, .{ .r = 0x31, .g = 0x32, .b = 0x33 }),
        presentation.cursor,
    );
    const cell = terminal.semanticView(0).cellInfoAt(0, 0);
    try std.testing.expectEqual(
        presentation.palette[2],
        cell.attrs.fg.resolve(presentation.foreground, &presentation.palette),
    );
    try std.testing.expectEqual(
        Terminal.Rgb{ .r = 4, .g = 5, .b = 6 },
        cell.attrs.bg.resolve(presentation.background, &presentation.palette),
    );
    try std.testing.expectEqual(
        Terminal.Rgb{ .r = 7, .g = 8, .b = 9 },
        cell.attrs.underline_color.resolve(
            presentation.foreground,
            &presentation.palette,
        ),
    );
    try std.testing.expect(cell.attrs.dim);
    try std.testing.expect(cell.attrs.underline);
    try std.testing.expectEqual(.curly, cell.attrs.underline_style);
    try std.testing.expect(cell.attrs.invisible);
    try std.testing.expect(cell.attrs.strikethrough);
}

test "snapshot: split-feed equivalence" {
    const gpa = std.testing.allocator;

    var vt_core_atomic = try Terminal.init(gpa, 5, 10);
    defer vt_core_atomic.deinit();
    var atomic_stream = try StreamHarness.init(&vt_core_atomic);
    try atomic_stream.nextSlice("ABCDEFGHIJ");
    var snap_atomic = try captureSnapshot(&vt_core_atomic);
    defer snap_atomic.deinit();

    var vt_core_chunked = try Terminal.init(gpa, 5, 10);
    defer vt_core_chunked.deinit();
    var chunked_stream = try StreamHarness.init(&vt_core_chunked);
    try chunked_stream.next('A');
    try chunked_stream.next('B');
    try chunked_stream.nextSlice("CD");
    try chunked_stream.nextSlice("EFGHIJ");
    var snap_chunked = try captureSnapshot(&vt_core_chunked);
    defer snap_chunked.deinit();

    try std.testing.expectEqual(snap_atomic.cursor_col, snap_chunked.cursor_col);
    try std.testing.expectEqual(snap_atomic.cursor_row, snap_chunked.cursor_row);

    if (snap_atomic.cells != null and snap_chunked.cells != null) {
        const size = gridCellCount(snap_atomic.rows, snap_atomic.cols);
        try std.testing.expectEqualSlices(u21, snap_atomic.cells.?[0..@intCast(size)], snap_chunked.cells.?[0..@intCast(size)]);
    }
}

test "snapshot: history capture when history is enabled" {
    const gpa = std.testing.allocator;
    var terminal = try Terminal.initWithHistory(gpa, 3, 5, 10);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("AAA\nBBB\nCCC\nDDD");

    var snap = try captureSnapshot(&terminal);
    defer snap.deinit();

    try std.testing.expectEqual(@as(u16, 3), snap.rows);
    try std.testing.expectEqual(@as(u16, 5), snap.cols);
    try std.testing.expectEqual(@as(u16, 10), snap.history_capacity);
    try std.testing.expectEqual(snap.history_count, visibleView(&terminal).history_count);

    if (snap.history != null) {
        try std.testing.expect(snap.history.?.len > 0);
    }
}

test "snapshot: historyRowAt matches terminal after wraparound" {
    const gpa = std.testing.allocator;
    var terminal = try Terminal.initWithHistory(gpa, 2, 3, 2);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    // Force history ring-buffer wraparound (capacity 2, scroll more than 2 rows).
    try stream.nextSlice("111\n222\n333\n444\n555");

    var snap = try captureSnapshot(&terminal);
    defer snap.deinit();

    try std.testing.expectEqual(visibleView(&terminal).history_count, snap.history_count);
    try std.testing.expectEqual(screen_set.historyCapacity(&terminal.screen_state), snap.history_capacity);

    var idx: u32 = 0;
    while (idx < visibleView(&terminal).history_count) : (idx += 1) {
        var col: u16 = 0;
        while (col < terminal.screen_state.activeConst().cols) : (col += 1) {
            try std.testing.expectEqual(screen_set.historyRowAt(&terminal.screen_state, idx, col), snap.historyRowAt(idx, col));
        }
    }
}

test "snapshot: parity with direct screen state" {
    const gpa = std.testing.allocator;
    var terminal = try Terminal.init(gpa, 5, 10);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("TEST");

    var snap = try captureSnapshot(&terminal);
    defer snap.deinit();

    const screen = terminal.screen_state.activeConst();
    try std.testing.expectEqual(screen.rows, snap.rows);
    try std.testing.expectEqual(screen.cols, snap.cols);
    try std.testing.expectEqual(screen.cursor.row, snap.cursor_row);
    try std.testing.expectEqual(screen.cursor.col, snap.cursor_col);
    try std.testing.expectEqual(screen.cursor.visible, snap.cursor_visible);
    try std.testing.expectEqual(screen.cursor.effective_shape, snap.cursor_shape);
    try std.testing.expectEqual(screen.cursor.blink_intent, snap.cursor_blink);
    try std.testing.expectEqual(screen.auto_wrap, snap.auto_wrap);
}
