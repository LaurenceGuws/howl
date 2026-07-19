const std = @import("std");
const screen_mod = @import("../../../src/screen.zig");
const semantic_event = @import("../../../src/semantic_event.zig");
const parser_mod = @import("../../../src/parser.zig");

const Screen = screen_mod.Screen;
const Grid = Screen;
const SemanticEvent = semantic_event.SemanticEvent;

fn apply(screen: *Screen, event: SemanticEvent) void {
    screen.applyScreen(event);
}

fn emptySeparators() parser_mod.CsiSeparatorList {
    return parser_mod.CsiSeparatorList.initEmpty();
}

fn colonSeparator(after_param_idx: u8) parser_mod.CsiSeparatorList {
    var separators = parser_mod.CsiSeparatorList.initEmpty();
    separators.set(@intCast(after_param_idx));
    return separators;
}

test "screen write: reset clears cursor wrap and cells" {
    const gpa = std.testing.allocator;
    var s = try Screen.initWithCells(gpa, 2, 5);
    defer s.deinit(gpa);
    apply(&s, SemanticEvent{ .write_text = "abcdef" });
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
    apply(&s, SemanticEvent{ .write_text = "abc" });
    try std.testing.expectEqual(@as(u21, 'a'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'c'), s.cellAt(0, 2));

    var c = try Screen.initWithCells(gpa, 2, 4);
    defer c.deinit(gpa);
    apply(&c, SemanticEvent{ .write_codepoint = 'o' });
    apply(&c, SemanticEvent{ .write_codepoint = 0x0300 });
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
    apply(&s, SemanticEvent{ .sgr = .{ .params = fg_params[0..], .separators = emptySeparators() } });
    const bg_params = [_]i32{ 48, 5, 23 };
    apply(&s, SemanticEvent{ .sgr = .{ .params = bg_params[0..], .separators = emptySeparators() } });
    apply(&s, SemanticEvent{ .write_text = "X" });
    const cell = s.cellInfoAt(0, 0);
    try std.testing.expectEqual(Grid.Color.indexed(196), cell.attrs.fg);
    try std.testing.expectEqual(Grid.Color.indexed(23), cell.attrs.bg);

    var r = try Grid.initWithCells(gpa, 2, 4);
    defer r.deinit(gpa);
    const red_params = [_]i32{31};
    apply(&r, SemanticEvent{ .sgr = .{ .params = red_params[0..], .separators = emptySeparators() } });
    apply(&r, SemanticEvent{ .write_text = "A" });
    const reset_params = [_]i32{0};
    apply(&r, SemanticEvent{ .sgr = .{ .params = reset_params[0..], .separators = emptySeparators() } });
    apply(&r, SemanticEvent{ .write_text = "B" });
    try std.testing.expectEqual(Grid.Color.indexed(1), r.cellInfoAt(0, 0).attrs.fg);
    try std.testing.expectEqual(Screen.default_fg, r.cellInfoAt(0, 1).attrs.fg);
}

test "screen write: style attrs and kitty underline forms apply correctly" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 1, 2);
    defer s.deinit(gpa);
    const set_params = [_]i32{ 1, 2, 3, 8, 9 };
    apply(&s, SemanticEvent{ .sgr = .{ .params = set_params[0..], .separators = emptySeparators() } });
    apply(&s, SemanticEvent{ .write_text = "A" });
    const reset_params = [_]i32{ 22, 23, 28, 29 };
    apply(&s, SemanticEvent{ .sgr = .{ .params = reset_params[0..], .separators = emptySeparators() } });
    apply(&s, SemanticEvent{ .write_text = "B" });
    try std.testing.expect(s.cellInfoAt(0, 0).attrs.bold);
    try std.testing.expect(!s.cellInfoAt(0, 1).attrs.bold);

    var u = try Screen.initWithCells(gpa, 2, 4);
    defer u.deinit(gpa);
    const colon_params = [_]i32{ 4, 3 };
    apply(&u, SemanticEvent{ .sgr = .{ .params = colon_params[0..], .separators = colonSeparator(0) } });
    apply(&u, SemanticEvent{ .write_text = "C" });
    const semicolon_params = [_]i32{ 4, 5 };
    apply(&u, SemanticEvent{ .sgr = .{ .params = semicolon_params[0..], .separators = emptySeparators() } });
    apply(&u, SemanticEvent{ .write_text = "S" });
    try std.testing.expectEqual(Grid.UnderlineStyle.curly, u.cellInfoAt(0, 0).attrs.underline_style);
    try std.testing.expectEqual(Grid.UnderlineStyle.straight, u.cellInfoAt(0, 1).attrs.underline_style);

    var c = try Grid.initWithCells(gpa, 2, 4);
    defer c.deinit(gpa);
    const color_params = [_]i32{ 4, 58, 2, 1, 2, 3 };
    apply(&c, SemanticEvent{ .sgr = .{ .params = color_params[0..], .separators = emptySeparators() } });
    apply(&c, SemanticEvent{ .write_text = "C" });
    const reset_underline_params = [_]i32{59};
    apply(&c, SemanticEvent{ .sgr = .{ .params = reset_underline_params[0..], .separators = emptySeparators() } });
    apply(&c, SemanticEvent{ .write_text = "R" });
    try std.testing.expectEqual(Grid.Color.rgbComponents(1, 2, 3), c.cellInfoAt(0, 0).attrs.underline_color);
    try std.testing.expectEqual(Grid.default_underline_color, c.cellInfoAt(0, 1).attrs.underline_color);
}

test "screen write: SGR clamps colors and preserves malformed parameter advancement" {
    var screen = Screen.init(1, 1);

    const rgb_params = [_]i32{ 38, 2, -1, 300, 42 };
    screen.applySgr(rgb_params[0..], emptySeparators());
    try std.testing.expectEqual(Grid.Color.rgbComponents(0, 255, 42), screen.current_attrs.fg);

    const malformed_params = [_]i32{ 31, 38, 5 };
    screen.applySgr(malformed_params[0..], emptySeparators());
    try std.testing.expectEqual(Grid.Color.indexed(1), screen.current_attrs.fg);
    try std.testing.expect(screen.current_attrs.blink);

    screen.current_attrs.blink_fast = true;
    const clear_blink_params = [_]i32{25};
    screen.applySgr(clear_blink_params[0..], emptySeparators());
    try std.testing.expect(!screen.current_attrs.blink);
    try std.testing.expect(!screen.current_attrs.blink_fast);
}

test "screen write: wrapping and exact-fill behavior remain explicit" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 4, 5);
    defer s.deinit(gpa);
    apply(&s, SemanticEvent{ .write_text = "abcdefgh" });
    try std.testing.expectEqual(@as(u16, 1), s.cursor.row);
    try std.testing.expectEqual(@as(u16, 3), s.cursor.col);
    try std.testing.expectEqual(@as(u21, 'f'), s.cellAt(1, 0));

    var exact = try Grid.initWithCells(gpa, 2, 5);
    defer exact.deinit(gpa);
    apply(&exact, SemanticEvent{ .write_text = "abcde" });
    try std.testing.expectEqual(@as(u16, 4), exact.cursor.col);
    apply(&exact, SemanticEvent{ .write_text = "f" });
    try std.testing.expectEqual(@as(u16, 1), exact.cursor.row);
    try std.testing.expectEqual(@as(u21, 'f'), exact.cellAt(1, 0));

    var combining = try Grid.initWithCells(gpa, 2, 2);
    defer combining.deinit(gpa);
    apply(&combining, SemanticEvent{ .write_text = "ab" });
    apply(&combining, SemanticEvent{ .write_codepoint = 0x0300 });
    try std.testing.expectEqual(@as(u21, 'b'), combining.cellInfoAt(0, 1).codepoint);

    var bottom = try Grid.initWithCells(gpa, 2, 5);
    defer bottom.deinit(gpa);
    apply(&bottom, SemanticEvent{ .write_text = "abcde" });
    apply(&bottom, SemanticEvent{ .write_text = "fghij" });
    apply(&bottom, SemanticEvent{ .write_text = "k" });
    try std.testing.expectEqual(@as(u21, 'f'), bottom.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'k'), bottom.cellAt(1, 0));

    var nowrap = try Grid.initWithCells(gpa, 2, 5);
    defer nowrap.deinit(gpa);
    apply(&nowrap, SemanticEvent{ .auto_wrap = false });
    apply(&nowrap, SemanticEvent{ .write_text = "abcdefg" });
    try std.testing.expectEqual(@as(u16, 0), nowrap.cursor.row);
    try std.testing.expectEqual(@as(u21, 'g'), nowrap.cellAt(0, 4));
}

test "screen write: out-of-bounds cell lookup returns zero" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(10, 0));
}
