const std = @import("std");
const terminal_mod = @import("../../src/terminal.zig");
const screen_mod = @import("../../src/screen.zig");
const screen_set = @import("../../src/screen_set.zig");
const stream_harness = @import("../support/stream_harness.zig");

const Terminal = terminal_mod.Terminal;
const Screen = screen_mod.Screen;
const StreamHarness = stream_harness.Harness;

fn active(terminal: *const Terminal) *const Screen {
    return terminal.screen_state.activeConst();
}

fn view(terminal: *const Terminal) screen_set.View {
    return screen_set.visibleView(&terminal.screen_state, 0);
}

test "terminal cursor: save restore is terminal-owned per active bank" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b[2;6H\x1b[4 q\x1b7\x1b[1;1H\x1b[1 q\x1b8");
    try std.testing.expectEqual(@as(u16, 1), active(&terminal).cursor.row);
    try std.testing.expectEqual(@as(u16, 5), active(&terminal).cursor.col);
    try std.testing.expectEqual(.underline, active(&terminal).cursor.effective_shape);
    try std.testing.expect(!active(&terminal).cursor.blink_intent);
}

test "terminal cursor: restore without prior save homes and clears charset state only" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b[?5h\x1b[?6h\x1b[?7l\x1b)0\x1b8");
    try std.testing.expectEqual(@as(u16, 0), active(&terminal).cursor.row);
    try std.testing.expectEqual(@as(u16, 0), active(&terminal).cursor.col);
    try std.testing.expect(!terminal.modes.reverse_screen_mode);
    try std.testing.expect(!active(&terminal).origin_mode);
    try std.testing.expect(!active(&terminal).auto_wrap);
    try std.testing.expectEqual(@as(u8, 0), terminal.gl_index);
    try std.testing.expectEqual(@as(u8, 'B'), terminal.g0_designation);
    try std.testing.expectEqual(@as(u8, 'B'), terminal.g1_designation);
}

test "terminal cursor: alt screen enter resets alt cursor instead of copying primary" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b[3;4H\x1b[6 q\x1b[?47h");
    try std.testing.expect(view(&terminal).is_alternate_screen);
    try std.testing.expectEqual(@as(u16, 0), active(&terminal).cursor.row);
    try std.testing.expectEqual(@as(u16, 0), active(&terminal).cursor.col);
    try std.testing.expectEqual(.none, active(&terminal).cursor.effective_shape);
    try std.testing.expect(active(&terminal).cursor.blink_intent);
}

test "terminal cursor: decscusr no-shape stays explicit through surface view" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 2, 2);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b[7 q");
    const visible = view(&terminal);
    try std.testing.expectEqual(.none, active(&terminal).cursor.effective_shape);
    try std.testing.expectEqual(.none, visible.cursor_shape);
    try std.testing.expect(visible.cursor_visible);
}

test "terminal cursor: savepoint restores Kitty cursor payload and leaves visibility and colors alone" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();

    const active_screen = terminal.screen_state.active();
    active_screen.cursor.setPositionByClient(2, 5);
    active_screen.cursor.setProgramStyle(.{ .shape = .bar, .blink = false });
    active_screen.current_attrs.bold = true;
    terminal.modes.reverse_screen_mode = true;
    active_screen.origin_mode = true;
    active_screen.auto_wrap = false;
    active_screen.cursor.visible = false;
    active_screen.cursor.cursor_color = .{ .r = 0x11, .g = 0x22, .b = 0x33 };
    active_screen.cursor.cursor_text_color = .{ .r = 0x44, .g = 0x55, .b = 0x66 };
    terminal.gl_index = 1;
    terminal.g0_designation = '0';
    terminal.g1_designation = 'A';
    terminal.saveCursor();

    active_screen.cursor.setPositionByClient(0, 0);
    active_screen.cursor.setProgramStyle(.{ .shape = .block, .blink = true });
    active_screen.current_attrs.bold = false;
    terminal.modes.reverse_screen_mode = false;
    active_screen.origin_mode = false;
    active_screen.auto_wrap = true;
    active_screen.cursor.visible = true;
    active_screen.cursor.cursor_color = .{ .r = 1, .g = 2, .b = 3 };
    active_screen.cursor.cursor_text_color = .{ .r = 4, .g = 5, .b = 6 };
    terminal.gl_index = 0;
    terminal.g0_designation = 'B';
    terminal.g1_designation = 'B';

    terminal.restoreCursor();

    try std.testing.expectEqual(@as(u16, 2), active(&terminal).cursor.row);
    try std.testing.expectEqual(@as(u16, 5), active(&terminal).cursor.col);
    try std.testing.expectEqual(.bar, active(&terminal).cursor.effective_shape);
    try std.testing.expect(!active(&terminal).cursor.blink_intent);
    try std.testing.expect(active(&terminal).current_attrs.bold);
    try std.testing.expect(terminal.modes.reverse_screen_mode);
    try std.testing.expect(active(&terminal).origin_mode);
    try std.testing.expect(!active(&terminal).auto_wrap);
    try std.testing.expect(active(&terminal).cursor.visible);
    try std.testing.expectEqual(@as(?Screen.Rgb, .{ .r = 1, .g = 2, .b = 3 }), active(&terminal).cursor.cursor_color);
    try std.testing.expectEqual(@as(?Screen.Rgb, .{ .r = 4, .g = 5, .b = 6 }), active(&terminal).cursor.cursor_text_color);
    try std.testing.expectEqual(@as(u8, 1), terminal.gl_index);
    try std.testing.expectEqual(@as(u8, '0'), terminal.g0_designation);
    try std.testing.expectEqual(@as(u8, 'A'), terminal.g1_designation);
}

test "terminal cursor: 1049 restores primary bank and 47 leaves banks independent" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b[3;4H\x1b[4 q\x1b[?1049h\x1b[2;2H\x1b[?1049l");
    try std.testing.expectEqual(@as(u16, 2), active(&terminal).cursor.row);
    try std.testing.expectEqual(@as(u16, 3), active(&terminal).cursor.col);
    try std.testing.expectEqual(.underline, active(&terminal).cursor.effective_shape);
    try std.testing.expect(!active(&terminal).cursor.blink_intent);

    try stream.nextSlice("\x1b[?47h\x1b[2;2H\x1b[1 q\x1b[?47l");
    try std.testing.expectEqual(@as(u16, 2), active(&terminal).cursor.row);
    try std.testing.expectEqual(@as(u16, 3), active(&terminal).cursor.col);
    try std.testing.expectEqual(.underline, active(&terminal).cursor.effective_shape);
    try std.testing.expect(!active(&terminal).cursor.blink_intent);
}
