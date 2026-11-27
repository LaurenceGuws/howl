//! Proves cursor motion, margins, save state, and wrap semantics owned by Screen.

const std = @import("std");
const screen_mod = @import("../screen.zig");

const Screen = screen_mod.Screen;
const Grid = Screen;
const Action = screen_mod.Screen.Action;

fn apply(screen: *Screen, event: Action) void {
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
    apply(&s, Action{ .cursor_visible = false });
    apply(&s, Action{ .auto_wrap = false });
    try std.testing.expect(!s.cursor.visible);
    try std.testing.expect(!s.auto_wrap);
    try std.testing.expectEqual(@as(u16, 1), s.cursor.row);
    try std.testing.expectEqual(@as(u16, 4), s.cursor.col);
}

test "screen cursor: origin mode makes cursor positioning relative to scroll region" {
    var s = Screen.init(6, 10);
    try std.testing.expect(s.setScrollRegion(2, 4));
    apply(&s, Action{ .origin_mode = true });
    apply(&s, Action{ .cursor_position = .{ .row = 0, .col = 1 } });
    try std.testing.expectEqual(@as(u16, 2), s.cursor.row);
    try std.testing.expectEqual(@as(u16, 1), s.cursor.col);
    apply(&s, Action{ .cursor_position = .{ .row = 2, .col = 0 } });
    try std.testing.expectEqual(@as(u16, 4), s.cursor.row);
}

test "screen cursor: directional and absolute moves clamp correctly" {
    var s = Screen.init(24, 80);
    s.cursor.setRowByClient(5);
    apply(&s, Action{ .cursor_up = 3 });
    try std.testing.expectEqual(@as(u16, 2), s.cursor.row);
    s.cursor.setRowByClient(1);
    apply(&s, Action{ .cursor_up = 5 });
    try std.testing.expectEqual(@as(u16, 0), s.cursor.row);
    s.cursor.setRowByClient(20);
    apply(&s, Action{ .cursor_down = 10 });
    try std.testing.expectEqual(@as(u16, 23), s.cursor.row);
    s.cursor.setColByClient(75);
    apply(&s, Action{ .cursor_forward = 10 });
    try std.testing.expectEqual(@as(u16, 79), s.cursor.col);
    apply(&s, Action{ .cursor_position = .{ .row = 10, .col = 40 } });
    try std.testing.expectEqual(@as(u16, 10), s.cursor.row);
    try std.testing.expectEqual(@as(u16, 40), s.cursor.col);
}

test "screen cursor: line-relative and axis-specific moves update the right fields" {
    var s = Grid.init(24, 80);
    s.cursor.setPositionByClient(5, 40);
    apply(&s, Action{ .cursor_next_line = 3 });
    try std.testing.expectEqual(@as(u16, 8), s.cursor.row);
    try std.testing.expectEqual(@as(u16, 0), s.cursor.col);
    s.cursor.setPositionByClient(5, 40);
    apply(&s, Action{ .cursor_prev_line = 3 });
    try std.testing.expectEqual(@as(u16, 2), s.cursor.row);
    try std.testing.expectEqual(@as(u16, 0), s.cursor.col);
    s.cursor.setPositionByClient(12, 20);
    apply(&s, Action{ .cursor_horizontal_absolute = 7 });
    try std.testing.expectEqual(@as(u16, 12), s.cursor.row);
    try std.testing.expectEqual(@as(u16, 7), s.cursor.col);
    apply(&s, Action{ .cursor_vertical_absolute = 7 });
    try std.testing.expectEqual(@as(u16, 7), s.cursor.row);
    try std.testing.expectEqual(@as(u16, 7), s.cursor.col);
}

test "screen cursor: zero rows and primitive cursor controls do not panic" {
    var s = Screen.init(0, 0);
    apply(&s, Action{ .cursor_down = 5 });
    apply(&s, Action{ .cursor_forward = 5 });
    try std.testing.expectEqual(@as(u16, 0), s.cursor.row);

    var t = Grid.init(4, 10);
    t.cursor.setPositionByClient(1, 7);
    apply(&t, Action.line_feed);
    apply(&t, Action.carriage_return);
    try std.testing.expectEqual(@as(u16, 2), t.cursor.row);
    try std.testing.expectEqual(@as(u16, 0), t.cursor.col);
    t.cursor.setColByClient(5);
    apply(&t, Action.backspace);
    try std.testing.expectEqual(@as(u16, 4), t.cursor.col);
}

test "screen cursor: DECSCUSR override and default restore update semantic style" {
    var s = Grid.init(4, 4);
    s.setDefaultCursorStyle(.{ .shape = .underline, .blink = false });
    try std.testing.expectEqual(.underline, s.cursor.effective_shape);
    try std.testing.expect(!s.cursor.blink_intent);
    apply(&s, Action{ .cursor_style = .{ .program_override = .{ .shape = .bar, .blink = false } } });
    try std.testing.expectEqual(.bar, s.cursor.effective_shape);
    try std.testing.expect(!s.cursor.blink_intent);
    try std.testing.expectEqual(@as(?Screen.CursorStyle, .{ .shape = .bar, .blink = false }), s.cursor.program_override_style);
    apply(&s, Action{ .cursor_style = .restore_default });
    try std.testing.expectEqual(.underline, s.cursor.effective_shape);
    try std.testing.expect(!s.cursor.blink_intent);
    try std.testing.expectEqual(@as(?Screen.CursorStyle, null), s.cursor.program_override_style);
}

test "screen cursor: client movement advances position_changed_by_client_at" {
    var s = Grid.init(4, 4);
    try std.testing.expectEqual(@as(u64, 0), s.cursor.position_changed_by_client_at);

    apply(&s, Action{ .cursor_position = .{ .row = 1, .col = 2 } });
    try std.testing.expectEqual(@as(u64, 1), s.cursor.position_changed_by_client_at);

    apply(&s, Action{ .cursor_position = .{ .row = 1, .col = 2 } });
    try std.testing.expectEqual(@as(u64, 1), s.cursor.position_changed_by_client_at);

    apply(&s, Action{ .cursor_forward = 1 });
    try std.testing.expectEqual(@as(u64, 2), s.cursor.position_changed_by_client_at);
}

test "screen cursor: alt entry reset keeps visibility and colors outside Kitty cursor payload" {
    var s = Grid.init(4, 4);
    s.setDefaultCursorStyle(.{ .shape = .underline, .blink = false });
    s.cursor.visible = false;
    s.cursor.cursor_color = .{ .r = 1, .g = 2, .b = 3 };
    s.cursor.cursor_text_color = .{ .r = 4, .g = 5, .b = 6 };
    s.cursor.setPositionByClient(2, 3);
    s.cursor.setProgramStyle(.{ .shape = .bar, .blink = true });
    try std.testing.expectEqual(.bar, s.cursor.effective_shape);
    try std.testing.expect(s.cursor.blink_intent);

    s.resetCursorForAltEntry();

    try std.testing.expectEqual(@as(u16, 0), s.cursor.row);
    try std.testing.expectEqual(@as(u16, 0), s.cursor.col);
    try std.testing.expectEqual(.underline, s.cursor.effective_shape);
    try std.testing.expect(!s.cursor.blink_intent);
    try std.testing.expectEqual(@as(?Screen.CursorStyle, null), s.cursor.program_override_style);
    try std.testing.expect(!s.cursor.visible);
    try std.testing.expectEqual(@as(?Screen.Rgb, .{ .r = 1, .g = 2, .b = 3 }), s.cursor.cursor_color);
    try std.testing.expectEqual(@as(?Screen.Rgb, .{ .r = 4, .g = 5, .b = 6 }), s.cursor.cursor_text_color);
}

test "screen cursor: direct absolute movement reports the exact prior cursor contract" {
    var s = try Screen.initWithCells(std.testing.allocator, 4, 8);
    defer s.deinit(std.testing.allocator);
    s.setDefaultCursorStyle(.{ .shape = .underline, .blink = false });
    s.cursor.setProgramStyle(.{ .shape = .bar, .blink = true });
    s.cursor.visible = false;
    s.cursor.cursor_color = .{ .r = 1, .g = 2, .b = 3 };
    s.cursor.cursor_text_color = .{ .r = 4, .g = 5, .b = 6 };
    for ([_]u64{ 0, std.math.maxInt(u64) }) |identity| {
        for ([_]u64{ 0, 37 }) |timestamp| {
            for ([_]bool{ false, true }) |pending| {
                for ([_]u16{ 0, 1, 99 }) |row| {
                    for ([_]u16{ 0, 1, 99 }) |col| {
                        s.cursor.setPositionByClient(0, 0);
                        s.cursor.position_changed_by_client_at = identity;
                        s.cursor.position_changed_timestamp_ns = 0;
                        s.setCursorMovementTimestamp(timestamp);
                        s.wrap_pending = pending;
                        const before = s.cursor;
                        const changed = s.moveCursorPosition(row, col);
                        var expected = before;
                        expected.row = @min(row, 3);
                        expected.col = @min(col, 7);
                        expected.position_changed_by_client_at +|= @intFromBool(expected.row != 0 or expected.col != 0);
                        expected.position_changed_timestamp_ns = timestamp;
                        try std.testing.expectEqualDeep(expected, s.cursor);
                        try std.testing.expectEqual(!std.meta.eql(before, s.cursor) or pending, changed);
                        try std.testing.expect(!s.wrap_pending);
                        try std.testing.expect(!s.moveCursorPosition(row, col));
                    }
                }
            }
        }
    }
}
