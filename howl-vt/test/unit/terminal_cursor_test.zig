const std = @import("std");
const terminal_mod = @import("../../src/terminal.zig");
const screen_mod = @import("../../src/terminal.zig");
const screen_set = @import("../../src/terminal.zig");
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
    try std.testing.expectEqual(@as(u8, 'B'), terminal.designations[0]);
    try std.testing.expectEqual(@as(u8, 'B'), terminal.designations[1]);
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

test "terminal cursor: DECSCUSR restores host default and rejects unsupported values" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 2, 2);
    defer terminal.deinit();
    terminal.screen_state.primary.setDefaultCursorStyle(.{ .shape = .underline, .blink = false });

    const cases = [_]struct { bytes: []const u8, shape: Screen.CursorShape, blink: bool }{
        .{ .bytes = "\x1b[1 q", .shape = .block, .blink = true },
        .{ .bytes = "\x1b[2 q", .shape = .block, .blink = false },
        .{ .bytes = "\x1b[3 q", .shape = .underline, .blink = true },
        .{ .bytes = "\x1b[4 q", .shape = .underline, .blink = false },
        .{ .bytes = "\x1b[5 q", .shape = .bar, .blink = true },
        .{ .bytes = "\x1b[6 q", .shape = .bar, .blink = false },
    };
    for (cases) |case| {
        try std.testing.expect((try terminal.feed(case.bytes)).state_changed);
        try std.testing.expectEqual(case.shape, active(&terminal).cursor.effective_shape);
        try std.testing.expectEqual(case.blink, active(&terminal).cursor.blink_intent);
    }

    try std.testing.expect(!(try terminal.feed("\x1b[0 ")).state_changed);
    try std.testing.expect((try terminal.feed("q")).state_changed);
    try std.testing.expectEqual(.underline, active(&terminal).cursor.effective_shape);
    try std.testing.expect(!active(&terminal).cursor.blink_intent);
    try std.testing.expect(!(try terminal.feed("\x1b[ q\x1b[7 q\x1b[999999 q")).state_changed);
    try std.testing.expectEqual(.underline, active(&terminal).cursor.effective_shape);
    try std.testing.expect(!active(&terminal).cursor.blink_intent);

    try std.testing.expect((try terminal.feed("\x1bP$q q\x1b\\")).state_changed);
    try std.testing.expectEqualStrings("\x1bP1$r4 q\x1b\\", terminal.host.pendingOutput());
}

test "terminal cursor: Kitty DCS restores configured appearance across fragmented input" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 4);
    defer terminal.deinit();
    terminal.screen_state.primary.setDefaultCursorStyle(.{ .shape = .underline, .blink = false });
    terminal.screen_state.alternate.setDefaultCursorStyle(.{ .shape = .bar, .blink = true });

    try std.testing.expect((try terminal.feed(
        "\x1b[1 q\x1b[?25l\x1b]12;#112233\x1b\\\x1b]21;cursor_text=#445566\x1b\\" ++
            "\x1b[?47h\x1b[2;3H\x1b[4 q",
    )).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1bP@kitty-restore-cursor\x18")).state_changed);
    try std.testing.expectEqual(.underline, active(&terminal).cursor.effective_shape);
    try std.testing.expect(!active(&terminal).cursor.visible);
    try std.testing.expect(!(try terminal.feed("\x1bP@kitty-restore-cursor-appe")).state_changed);
    try std.testing.expect((try terminal.feed("arance|ignored\x1b\\")).state_changed);

    try std.testing.expectEqual(.bar, active(&terminal).cursor.effective_shape);
    try std.testing.expect(active(&terminal).cursor.blink_intent);
    try std.testing.expectEqual(@as(u16, 1), active(&terminal).cursor.row);
    try std.testing.expectEqual(@as(u16, 2), active(&terminal).cursor.col);
    try std.testing.expect(terminal.screen_state.primary.cursor.visible);
    try std.testing.expect(terminal.screen_state.alternate.cursor.visible);
    try std.testing.expectEqual(@as(?Screen.Rgb, null), terminal.screen_state.primary.cursor.cursor_color);
    try std.testing.expectEqual(@as(?Screen.Rgb, null), terminal.screen_state.alternate.cursor.cursor_color);
    try std.testing.expectEqual(@as(?Screen.Rgb, null), terminal.host.terminalColorState().cursor);
    try std.testing.expectEqual(
        @as(?Screen.Rgb, .{ .r = 0x44, .g = 0x55, .b = 0x66 }),
        active(&terminal).cursor.cursor_text_color,
    );
    try std.testing.expect(!(try terminal.feed("\x1bP@kitty-restore-cursor-appearance|\x1b\\")).state_changed);

    try std.testing.expect((try terminal.feed("\x1b[?47l")).state_changed);
    try std.testing.expectEqual(.block, active(&terminal).cursor.effective_shape);
    try std.testing.expect((try terminal.feed("\x90@kitty-restore-cursor-appearance|x\x9c")).state_changed);
    try std.testing.expectEqual(.underline, active(&terminal).cursor.effective_shape);
    try std.testing.expect(!active(&terminal).cursor.blink_intent);
    try std.testing.expect(!(try terminal.feed("\x1bP@kitty-restore-cursor-appearance|x\x1b\\")).state_changed);
}

test "terminal cursor: savepoint restores presentation while host colors remain current" {
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
    terminal.designations[0] = '0';
    terminal.designations[1] = 'A';
    try std.testing.expect(terminal.saveCursor());

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
    terminal.designations[0] = 'B';
    terminal.designations[1] = 'B';

    try std.testing.expect(terminal.restoreCursor());

    try std.testing.expectEqual(@as(u16, 2), active(&terminal).cursor.row);
    try std.testing.expectEqual(@as(u16, 5), active(&terminal).cursor.col);
    try std.testing.expectEqual(.bar, active(&terminal).cursor.effective_shape);
    try std.testing.expect(!active(&terminal).cursor.blink_intent);
    try std.testing.expect(active(&terminal).current_attrs.bold);
    try std.testing.expect(terminal.modes.reverse_screen_mode);
    try std.testing.expect(active(&terminal).origin_mode);
    try std.testing.expect(!active(&terminal).auto_wrap);
    try std.testing.expect(!active(&terminal).cursor.visible);
    try std.testing.expect(!terminal.screen_state.alternate.cursor.visible);
    try std.testing.expectEqual(@as(?Screen.Rgb, .{ .r = 1, .g = 2, .b = 3 }), active(&terminal).cursor.cursor_color);
    try std.testing.expectEqual(@as(?Screen.Rgb, .{ .r = 4, .g = 5, .b = 6 }), active(&terminal).cursor.cursor_text_color);
    try std.testing.expectEqual(@as(u8, 1), terminal.gl_index);
    try std.testing.expectEqual(@as(u8, '0'), terminal.designations[0]);
    try std.testing.expectEqual(@as(u8, 'A'), terminal.designations[1]);
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

test "terminal cursor: presentation modes preserve exact bank and lifetime truth" {
    var terminal = try Terminal.init(std.testing.allocator, 4, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b[6 ")).state_changed);
    try std.testing.expect((try terminal.feed("q")).state_changed);
    try std.testing.expectEqual(.bar, active(&terminal).cursor.effective_shape);
    try std.testing.expect(!active(&terminal).cursor.blink_intent);
    try std.testing.expect(!(try terminal.feed("\x1b[6 q")).state_changed);

    try std.testing.expect((try terminal.feed("\x1b[?12h\x1b[?25l")).state_changed);
    try std.testing.expect(active(&terminal).cursor.blink_intent);
    try std.testing.expect(!active(&terminal).cursor.visible);
    try std.testing.expect(!(try terminal.feed("\x1b[?12h\x1b[?25l")).state_changed);

    try std.testing.expect((try terminal.feed("\x1b[?12;25s")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?12l\x1b[?25h")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?12;25r")).state_changed);
    try std.testing.expect(active(&terminal).cursor.blink_intent);
    try std.testing.expect(!active(&terminal).cursor.visible);
    try std.testing.expect((try terminal.feed("\x1b[?12$p\x1b[?25$p")).state_changed);
    try std.testing.expectEqualStrings("\x1b[?12;1$y\x1b[?25;2$y", terminal.host.pendingOutput());
    terminal.host.clearPendingOutput();

    try std.testing.expect((try terminal.feed("\x1b[?47h")).state_changed);
    try std.testing.expectEqual(.none, active(&terminal).cursor.effective_shape);
    try std.testing.expect(active(&terminal).cursor.blink_intent);
    try std.testing.expect(!active(&terminal).cursor.visible);
    try std.testing.expect((try terminal.feed("\x1b[?12l")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b[?25l")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?47l")).state_changed);
    try std.testing.expectEqual(.bar, active(&terminal).cursor.effective_shape);
    try std.testing.expect(active(&terminal).cursor.blink_intent);
    try std.testing.expect(!active(&terminal).cursor.visible);

    try terminal.resize(6, 12);
    try std.testing.expectEqual(.bar, active(&terminal).cursor.effective_shape);
    try std.testing.expect(active(&terminal).cursor.blink_intent);
    try std.testing.expect(!active(&terminal).cursor.visible);

    try std.testing.expect((try terminal.feed("\x1b[2 q")).state_changed);
    try std.testing.expectEqual(.block, active(&terminal).cursor.effective_shape);
    try std.testing.expect(!active(&terminal).cursor.blink_intent);
    try std.testing.expect(!(try terminal.feed("\x1b[2 q")).state_changed);
    try std.testing.expect((try terminal.feed("\x1bc")).state_changed);
    try std.testing.expectEqual(.block, active(&terminal).cursor.effective_shape);
    try std.testing.expect(active(&terminal).cursor.blink_intent);
    try std.testing.expect(active(&terminal).cursor.visible);
}
