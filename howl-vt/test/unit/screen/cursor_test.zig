const std = @import("std");
const screen_mod = @import("../../../src/screen.zig");
const semantic_event = @import("../../../src/semantic_event.zig");

const Screen = screen_mod.Screen;
const Grid = Screen;
const SemanticEvent = semantic_event.SemanticEvent;

fn apply(screen: *Screen, event: SemanticEvent) void {
    screen.applyScreen(event);
}

test "screen cursor: initial cursor at origin" {
    const s = Screen.init(24, 80);
    try std.testing.expectEqual(@as(u16, 0), s.cursor.row);
    try std.testing.expectEqual(@as(u16, 0), s.cursor.col);
}

test "screen cursor: visibility and auto-wrap modes do not move cursor" {
    var s = Screen.init(2, 5);
    s.cursor.setPositionByClient(1, 4);
    apply(&s, SemanticEvent{ .cursor_visible = false });
    apply(&s, SemanticEvent{ .auto_wrap = false });
    try std.testing.expect(!s.cursor.visible);
    try std.testing.expect(!s.auto_wrap);
    try std.testing.expectEqual(@as(u16, 1), s.cursor.row);
    try std.testing.expectEqual(@as(u16, 4), s.cursor.col);
}

test "screen cursor: origin mode makes cursor positioning relative to scroll region" {
    var s = Screen.init(6, 10);
    apply(&s, SemanticEvent{ .set_scroll_region = .{ .top = 2, .bottom = 4 } });
    apply(&s, SemanticEvent{ .origin_mode = true });
    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 0, .col = 1 } });
    try std.testing.expectEqual(@as(u16, 2), s.cursor.row);
    try std.testing.expectEqual(@as(u16, 1), s.cursor.col);
    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 2, .col = 0 } });
    try std.testing.expectEqual(@as(u16, 4), s.cursor.row);
}

test "screen cursor: directional and absolute moves clamp correctly" {
    var s = Screen.init(24, 80);
    s.cursor.setRowByClient(5);
    apply(&s, SemanticEvent{ .cursor_up = 3 });
    try std.testing.expectEqual(@as(u16, 2), s.cursor.row);
    s.cursor.setRowByClient(1);
    apply(&s, SemanticEvent{ .cursor_up = 5 });
    try std.testing.expectEqual(@as(u16, 0), s.cursor.row);
    s.cursor.setRowByClient(20);
    apply(&s, SemanticEvent{ .cursor_down = 10 });
    try std.testing.expectEqual(@as(u16, 23), s.cursor.row);
    s.cursor.setColByClient(75);
    apply(&s, SemanticEvent{ .cursor_forward = 10 });
    try std.testing.expectEqual(@as(u16, 79), s.cursor.col);
    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 10, .col = 40 } });
    try std.testing.expectEqual(@as(u16, 10), s.cursor.row);
    try std.testing.expectEqual(@as(u16, 40), s.cursor.col);
}

test "screen cursor: line-relative and axis-specific moves update the right fields" {
    var s = Grid.init(24, 80);
    s.cursor.setPositionByClient(5, 40);
    apply(&s, SemanticEvent{ .cursor_next_line = 3 });
    try std.testing.expectEqual(@as(u16, 8), s.cursor.row);
    try std.testing.expectEqual(@as(u16, 0), s.cursor.col);
    s.cursor.setPositionByClient(5, 40);
    apply(&s, SemanticEvent{ .cursor_prev_line = 3 });
    try std.testing.expectEqual(@as(u16, 2), s.cursor.row);
    try std.testing.expectEqual(@as(u16, 0), s.cursor.col);
    s.cursor.setPositionByClient(12, 20);
    apply(&s, SemanticEvent{ .cursor_horizontal_absolute = 7 });
    try std.testing.expectEqual(@as(u16, 12), s.cursor.row);
    try std.testing.expectEqual(@as(u16, 7), s.cursor.col);
    apply(&s, SemanticEvent{ .cursor_vertical_absolute = 7 });
    try std.testing.expectEqual(@as(u16, 7), s.cursor.row);
    try std.testing.expectEqual(@as(u16, 7), s.cursor.col);
}

test "screen cursor: zero rows and primitive cursor controls do not panic" {
    var s = Screen.init(0, 0);
    apply(&s, SemanticEvent{ .cursor_down = 5 });
    apply(&s, SemanticEvent{ .cursor_forward = 5 });
    try std.testing.expectEqual(@as(u16, 0), s.cursor.row);

    var t = Grid.init(4, 10);
    t.cursor.setPositionByClient(1, 7);
    apply(&t, SemanticEvent.line_feed);
    apply(&t, SemanticEvent.carriage_return);
    try std.testing.expectEqual(@as(u16, 2), t.cursor.row);
    try std.testing.expectEqual(@as(u16, 0), t.cursor.col);
    t.cursor.setColByClient(5);
    apply(&t, SemanticEvent.backspace);
    try std.testing.expectEqual(@as(u16, 4), t.cursor.col);
}

test "screen cursor: DECSCUSR override and default restore update semantic style" {
    var s = Grid.init(4, 4);
    s.setDefaultCursorStyle(.{ .shape = .underline, .blink = false });
    try std.testing.expectEqual(.underline, s.cursor.effective_shape);
    try std.testing.expect(!s.cursor.blink_intent);
    apply(&s, SemanticEvent{ .cursor_style = .{ .program_override = .{ .shape = .bar, .blink = false } } });
    try std.testing.expectEqual(.bar, s.cursor.effective_shape);
    try std.testing.expect(!s.cursor.blink_intent);
    try std.testing.expectEqual(@as(?Screen.CursorStyle, .{ .shape = .bar, .blink = false }), s.cursor.program_override_style);
    apply(&s, SemanticEvent{ .cursor_style = .restore_default });
    try std.testing.expectEqual(.underline, s.cursor.effective_shape);
    try std.testing.expect(!s.cursor.blink_intent);
    try std.testing.expectEqual(@as(?Screen.CursorStyle, null), s.cursor.program_override_style);
}

test "screen cursor: client movement advances position_changed_by_client_at" {
    var s = Grid.init(4, 4);
    try std.testing.expectEqual(@as(u64, 0), s.cursor.position_changed_by_client_at);

    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 1, .col = 2 } });
    try std.testing.expectEqual(@as(u64, 1), s.cursor.position_changed_by_client_at);

    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 1, .col = 2 } });
    try std.testing.expectEqual(@as(u64, 1), s.cursor.position_changed_by_client_at);

    apply(&s, SemanticEvent{ .cursor_forward = 1 });
    try std.testing.expectEqual(@as(u64, 2), s.cursor.position_changed_by_client_at);
}

test "screen cursor: alt entry reset keeps visibility and colors outside Kitty cursor payload" {
    var s = Grid.init(4, 4);
    s.cursor.visible = false;
    s.cursor.cursor_color = .{ .r = 1, .g = 2, .b = 3 };
    s.cursor.cursor_text_color = .{ .r = 4, .g = 5, .b = 6 };
    s.cursor.setPositionByClient(2, 3);
    s.cursor.setProgramStyle(.{ .shape = .bar, .blink = false });

    s.resetCursorForAltEntry();

    try std.testing.expectEqual(@as(u16, 0), s.cursor.row);
    try std.testing.expectEqual(@as(u16, 0), s.cursor.col);
    try std.testing.expectEqual(.none, s.cursor.effective_shape);
    try std.testing.expect(s.cursor.blink_intent);
    try std.testing.expectEqual(@as(?Screen.CursorStyle, null), s.cursor.program_override_style);
    try std.testing.expect(!s.cursor.visible);
    try std.testing.expectEqual(@as(?Screen.Rgb, .{ .r = 1, .g = 2, .b = 3 }), s.cursor.cursor_color);
    try std.testing.expectEqual(@as(?Screen.Rgb, .{ .r = 4, .g = 5, .b = 6 }), s.cursor.cursor_text_color);
}
