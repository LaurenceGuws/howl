const std = @import("std");
const terminal_mod = @import("../../src/howl_vt.zig");

const Terminal = terminal_mod.Terminal;

fn expectViewsEqual(a: Terminal.SemanticView, b: Terminal.SemanticView) !void {
    try std.testing.expectEqual(a.rows, b.rows);
    try std.testing.expectEqual(a.cols, b.cols);
    try std.testing.expectEqual(a.cursor_row, b.cursor_row);
    try std.testing.expectEqual(a.cursor_col, b.cursor_col);
    try std.testing.expectEqual(a.cursor_visible, b.cursor_visible);
    try std.testing.expectEqual(a.cursor_shape, b.cursor_shape);
    try std.testing.expectEqual(a.cursor_blink, b.cursor_blink);
    try std.testing.expectEqual(a.history_count, b.history_count);
    for (0..a.rows) |row| {
        try std.testing.expectEqualSlices(
            Terminal.Cell,
            a.rowCells(@intCast(row)),
            b.rowCells(@intCast(row)),
        );
    }
}

test "borrowed semantic view exposes complete cells and cursor facts" {
    var terminal = try Terminal.init(std.testing.allocator, 5, 10);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("HELLO")).state_changed);

    const view = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u16, 5), view.rows);
    try std.testing.expectEqual(@as(u16, 10), view.cols);
    try std.testing.expectEqual(@as(u16, 0), view.cursor_row);
    try std.testing.expectEqual(@as(u16, 5), view.cursor_col);
    try std.testing.expect(view.cursor_visible);
    try std.testing.expectEqual(.block, view.cursor_shape);
    try std.testing.expect(view.cursor_blink);
    try std.testing.expectEqual(@as(u21, 'H'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'O'), view.cellAt(0, 4));
}

test "borrowed semantic view is deterministic across identical terminals and feed splits" {
    var whole = try Terminal.init(std.testing.allocator, 2, 10);
    defer whole.deinit();
    try std.testing.expect((try whole.feed("ABCDEFGHIJ")).state_changed);

    var split = try Terminal.init(std.testing.allocator, 2, 10);
    defer split.deinit();
    try std.testing.expect((try split.feed("AB")).state_changed);
    try std.testing.expect((try split.feed("CDE")).state_changed);
    try std.testing.expect((try split.feed("FGHIJ")).state_changed);

    try expectViewsEqual(whole.semanticView(0), split.semanticView(0));
}

test "semantic view carries OSC colors and complete cell presentation" {
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
    try std.testing.expectEqual(Terminal.Rgb{ .r = 1, .g = 2, .b = 3 }, presentation.palette[2]);
    try std.testing.expectEqual(Terminal.Rgb{ .r = 0x11, .g = 0x12, .b = 0x13 }, presentation.foreground);
    try std.testing.expectEqual(Terminal.Rgb{ .r = 0x21, .g = 0x22, .b = 0x23 }, presentation.background);
    try std.testing.expectEqual(@as(?Terminal.Rgb, .{ .r = 0x31, .g = 0x32, .b = 0x33 }), presentation.cursor);

    const cell = terminal.semanticView(0).cellInfoAt(0, 0);
    try std.testing.expectEqual(presentation.palette[2], cell.attrs.fg.resolve(presentation.foreground, &presentation.palette));
    try std.testing.expectEqual(Terminal.Rgb{ .r = 4, .g = 5, .b = 6 }, cell.attrs.bg.resolve(presentation.background, &presentation.palette));
    try std.testing.expectEqual(
        Terminal.Rgb{ .r = 7, .g = 8, .b = 9 },
        cell.attrs.underline_color.resolve(presentation.foreground, &presentation.palette),
    );
    try std.testing.expect(cell.attrs.dim);
    try std.testing.expect(cell.attrs.underline);
    try std.testing.expectEqual(.curly, cell.attrs.underline_style);
    try std.testing.expect(cell.attrs.invisible);
    try std.testing.expect(cell.attrs.strikethrough);
}

test "retained history facts survive ring wraparound" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 2, 3, 2);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("111\r\n222\r\n333\r\n444\r\n555")).state_changed);

    const live = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u32, 2), live.history_count);

    const top = terminal.semanticView(live.history_count);
    try std.testing.expectEqual(live.history_count, top.history_offset);
    try std.testing.expectEqual(@as(u21, '2'), top.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, '2'), top.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, '2'), top.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, '3'), top.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, '3'), top.cellAt(1, 1));
    try std.testing.expectEqual(@as(u21, '3'), top.cellAt(1, 2));
}
