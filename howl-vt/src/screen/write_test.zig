//! Proves cell writing, clusters, attributes, and erasure owned by Screen.

const std = @import("std");
const screen_mod = @import("../screen.zig");

const Screen = screen_mod.Screen;
const Grid = Screen;
const Action = screen_mod.Screen.Action;

fn apply(screen: *Screen, event: Action) void {
    screen.applyScreen(event);
}

fn operands(values: []const i32) Screen.SgrOperands {
    return .{ .values = values };
}

fn colonOperands(values: []const i32, after_param_idx: u5) Screen.SgrOperands {
    return .{
        .values = values,
        .colon_after = @as(u32, 1) << after_param_idx,
    };
}

test "screen write: reset clears cursor wrap and cells" {
    const gpa = std.testing.allocator;
    var s = try Screen.initWithCells(gpa, 2, 5);
    defer s.deinit(gpa);
    apply(&s, Action{ .write_text = "abcdef" });
    try std.testing.expectEqual(@as(u21, 'a'), s.cellAt(0, 0));
    s.reset();
    try std.testing.expectEqual(@as(u16, 0), s.cursor.row);
    try std.testing.expectEqual(@as(u16, 0), s.cursor.col);
    try std.testing.expect(s.cursor.visible);
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(1, 0));
}

test "screen write: text and combining codepoints stay in lead cells" {
    const gpa = std.testing.allocator;
    var s = try Screen.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    apply(&s, Action{ .write_text = "abc" });
    try std.testing.expectEqual(@as(u21, 'a'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'c'), s.cellAt(0, 2));

    var c = try Screen.initWithCells(gpa, 2, 4);
    defer c.deinit(gpa);
    apply(&c, Action{ .write_codepoint = 'o' });
    apply(&c, Action{ .write_codepoint = 0x0300 });
    const cell = c.cellInfoAt(0, 0);
    try std.testing.expectEqual(@as(u21, 'o'), cell.codepoint);
    try std.testing.expectEqual(@as(u8, 1), cell.combining_len);
    try std.testing.expectEqual(@as(u32, 0x0300), cell.combining[0]);
}

test "screen write: sgr applies colors and resets for later writes" {
    const gpa = std.testing.allocator;
    var s = try Screen.initWithCells(gpa, 2, 4);
    defer s.deinit(gpa);

    const fg_params = [_]i32{ 38, 5, 196 };
    try std.testing.expect(s.applySgr(operands(fg_params[0..])));
    const bg_params = [_]i32{ 48, 5, 23 };
    try std.testing.expect(s.applySgr(operands(bg_params[0..])));
    apply(&s, Action{ .write_text = "X" });
    const cell = s.cellInfoAt(0, 0);
    try std.testing.expectEqual(Grid.Color.indexed(196), cell.attrs.fg);
    try std.testing.expectEqual(Grid.Color.indexed(23), cell.attrs.bg);

    var r = try Grid.initWithCells(gpa, 2, 4);
    defer r.deinit(gpa);
    const red_params = [_]i32{31};
    try std.testing.expect(r.applySgr(operands(red_params[0..])));
    apply(&r, Action{ .write_text = "A" });
    const reset_params = [_]i32{0};
    try std.testing.expect(r.applySgr(operands(reset_params[0..])));
    apply(&r, Action{ .write_text = "B" });
    try std.testing.expectEqual(Grid.Color.indexed(1), r.cellInfoAt(0, 0).attrs.fg);
    try std.testing.expectEqual(Screen.default_cell_attrs.fg, r.cellInfoAt(0, 1).attrs.fg);
}

test "screen write: style attrs and kitty underline forms apply correctly" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 1, 2);
    defer s.deinit(gpa);
    const set_params = [_]i32{ 1, 2, 3, 8, 9 };
    try std.testing.expect(s.applySgr(operands(set_params[0..])));
    apply(&s, Action{ .write_text = "A" });
    const reset_params = [_]i32{ 22, 23, 28, 29 };
    try std.testing.expect(s.applySgr(operands(reset_params[0..])));
    apply(&s, Action{ .write_text = "B" });
    try std.testing.expect(s.cellInfoAt(0, 0).attrs.bold);
    try std.testing.expect(!s.cellInfoAt(0, 1).attrs.bold);

    var u = try Screen.initWithCells(gpa, 2, 4);
    defer u.deinit(gpa);
    const colon_params = [_]i32{ 4, 3 };
    try std.testing.expect(u.applySgr(colonOperands(colon_params[0..], 0)));
    apply(&u, Action{ .write_text = "C" });
    const semicolon_params = [_]i32{ 4, 5 };
    try std.testing.expect(u.applySgr(operands(semicolon_params[0..])));
    apply(&u, Action{ .write_text = "S" });
    try std.testing.expectEqual(Grid.UnderlineStyle.curly, u.cellInfoAt(0, 0).attrs.underline_style);
    try std.testing.expectEqual(Grid.UnderlineStyle.straight, u.cellInfoAt(0, 1).attrs.underline_style);

    var c = try Grid.initWithCells(gpa, 2, 4);
    defer c.deinit(gpa);
    const color_params = [_]i32{ 4, 58, 2, 1, 2, 3 };
    try std.testing.expect(c.applySgr(operands(color_params[0..])));
    apply(&c, Action{ .write_text = "C" });
    const reset_underline_params = [_]i32{59};
    try std.testing.expect(c.applySgr(operands(reset_underline_params[0..])));
    apply(&c, Action{ .write_text = "R" });
    try std.testing.expectEqual(Grid.Color.rgbComponents(1, 2, 3), c.cellInfoAt(0, 0).attrs.underline_color);
    try std.testing.expectEqual(Grid.default_underline_color, c.cellInfoAt(0, 1).attrs.underline_color);
}

test "screen write: SGR clamps colors and consumes malformed color operands" {
    var screen = Screen.init(1, 1);

    const rgb_params = [_]i32{ 38, 2, -1, 300, 42 };
    try std.testing.expect(screen.applySgr(operands(rgb_params[0..])));
    try std.testing.expectEqual(Grid.Color.rgbComponents(0, 255, 42), screen.current_attrs.fg);

    const malformed_params = [_]i32{ 31, 38, 5 };
    try std.testing.expect(screen.applySgr(operands(malformed_params[0..])));
    try std.testing.expectEqual(Grid.Color.indexed(1), screen.current_attrs.fg);
    try std.testing.expect(!screen.current_attrs.blink);

    screen.current_attrs.blink_fast = true;
    const clear_blink_params = [_]i32{25};
    try std.testing.expect(screen.applySgr(operands(clear_blink_params[0..])));
    try std.testing.expect(!screen.current_attrs.blink);
    try std.testing.expect(!screen.current_attrs.blink_fast);
}

test "screen write: wrapping and exact-fill behavior remain explicit" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 4, 5);
    defer s.deinit(gpa);
    apply(&s, Action{ .write_text = "abcdefgh" });
    try std.testing.expectEqual(@as(u16, 1), s.cursor.row);
    try std.testing.expectEqual(@as(u16, 3), s.cursor.col);
    try std.testing.expectEqual(@as(u21, 'f'), s.cellAt(1, 0));

    var exact = try Grid.initWithCells(gpa, 2, 5);
    defer exact.deinit(gpa);
    apply(&exact, Action{ .write_text = "abcde" });
    try std.testing.expectEqual(@as(u16, 4), exact.cursor.col);
    apply(&exact, Action{ .write_text = "f" });
    try std.testing.expectEqual(@as(u16, 1), exact.cursor.row);
    try std.testing.expectEqual(@as(u21, 'f'), exact.cellAt(1, 0));

    var combining = try Grid.initWithCells(gpa, 2, 2);
    defer combining.deinit(gpa);
    apply(&combining, Action{ .write_text = "ab" });
    apply(&combining, Action{ .write_codepoint = 0x0300 });
    try std.testing.expectEqual(@as(u21, 'b'), combining.cellInfoAt(0, 1).codepoint);

    var bottom = try Grid.initWithCells(gpa, 2, 5);
    defer bottom.deinit(gpa);
    apply(&bottom, Action{ .write_text = "abcde" });
    apply(&bottom, Action{ .write_text = "fghij" });
    apply(&bottom, Action{ .write_text = "k" });
    try std.testing.expectEqual(@as(u21, 'f'), bottom.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'k'), bottom.cellAt(1, 0));

    var nowrap = try Grid.initWithCells(gpa, 2, 5);
    defer nowrap.deinit(gpa);
    apply(&nowrap, Action{ .auto_wrap = false });
    apply(&nowrap, Action{ .write_text = "abcdefg" });
    try std.testing.expectEqual(@as(u16, 0), nowrap.cursor.row);
    try std.testing.expectEqual(@as(u21, 'g'), nowrap.cellAt(0, 4));
}

test "screen write: out-of-bounds cell lookup returns zero" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(10, 0));
}
