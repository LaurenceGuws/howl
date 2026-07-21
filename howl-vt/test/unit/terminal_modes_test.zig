const std = @import("std");
const dcs_payload = @import("../../src/terminal.zig");
const host_state = @import("../../src/terminal.zig");
const legacy_control = @import("../../src/terminal.zig");
const screen_capture = @import("../support/screen_capture.zig");
const screen_set = @import("../../src/terminal.zig");
const selection = @import("../../src/terminal.zig");
const terminal_mod = @import("../../src/terminal.zig");
const input_encode = @import("../../src/terminal.zig");
const input_keyboard = @import("../../src/terminal.zig");
const input_mouse = @import("../../src/terminal.zig");
const parser_mod = @import("../../src/parser.zig");
const stream_harness = @import("../support/stream_harness.zig");

const Terminal = terminal_mod.Terminal;
const HostState = host_state;
const StreamHarness = stream_harness.Harness;

var encode_scratch: input_encode.Scratch = .{};

fn encodeKey(terminal: *Terminal, key: input_keyboard.InputKey, mod: input_keyboard.Modifier) []const u8 {
    var encoded = terminal.encodeInput(std.testing.allocator, &encode_scratch, .{ .key = .{ .key = key, .mods = mod } }) catch unreachable;
    defer encoded.deinit();
    return encoded.bytes;
}

fn encodeMouse(terminal: *Terminal, event: input_mouse.MouseEvent) []const u8 {
    var encoded = terminal.encodeInput(std.testing.allocator, &encode_scratch, .{ .mouse = event }) catch unreachable;
    defer encoded.deinit();
    return encoded.bytes;
}

fn encodeFocusIn(terminal: *Terminal) []const u8 {
    var encoded = terminal.encodeInput(std.testing.allocator, &encode_scratch, .{ .focus = .in }) catch unreachable;
    defer encoded.deinit();
    return encoded.bytes;
}

fn encodeFocusOut(terminal: *Terminal) []const u8 {
    var encoded = terminal.encodeInput(std.testing.allocator, &encode_scratch, .{ .focus = .out }) catch unreachable;
    defer encoded.deinit();
    return encoded.bytes;
}

fn visibleView(terminal: *const Terminal, scrollback_offset: u32) screen_set.View {
    return screen_set.visibleView(&terminal.screen_state, scrollback_offset);
}

fn captureSnapshot(terminal: *const Terminal) !screen_capture.Capture {
    return screen_capture.Capture.captureFromScreen(
        terminal.allocator,
        terminal.screen_state.activeConst(),
        terminal.screen_state.activeSelectionConst().state(),
    );
}

fn write(stream: *StreamHarness, bytes: []const u8) void {
    stream.nextSlice(bytes) catch unreachable;
}

fn pendingOutput(terminal: *const Terminal) []const u8 {
    return terminal.host.pendingOutput();
}

fn clearPendingOutput(terminal: *Terminal) void {
    terminal.host.clearPendingOutput();
}

fn dcsPayloadKind(terminal: *const Terminal) ?dcs_payload.DcsPayloadKind {
    return terminal.host.dcsPayloadKind();
}

fn dcsPayload(terminal: *const Terminal) ?[]const u8 {
    return terminal.host.dcsPayload();
}

fn legacyControl(terminal: *const Terminal) ?legacy_control.LegacyControlKind {
    return terminal.host.legacyControl();
}

fn reverseWraparoundMode(terminal: *const Terminal) bool {
    return terminal.modes.reverse_wraparound_mode;
}

fn extendedReverseWraparoundMode(terminal: *const Terminal) bool {
    return terminal.modes.extended_reverse_wraparound_mode;
}

fn mediaCopyRequest(terminal: *const Terminal) ?u16 {
    return terminal.host.mediaCopyRequest();
}

test "encodeMouse returns empty output and does not mutate state" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 5, 10);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    write(&stream, "HELLO");

    var snap_before = try captureSnapshot(&terminal);
    defer snap_before.deinit();

    const mouse_event = input_mouse.MouseEvent{
        .kind = .press,
        .button = .left,
        .row = 2,
        .col = 3,
        .pixel_x = null,
        .pixel_y = null,
        .mod = .{},
        .buttons_down = 1,
    };

    const output = encodeMouse(&terminal, mouse_event);
    try std.testing.expectEqual(@as(usize, 0), output.len);
    try std.testing.expectEqualSlices(u8, "", output);

    var snap_after = try captureSnapshot(&terminal);
    defer snap_after.deinit();

    try std.testing.expectEqual(snap_before.cursor_row, snap_after.cursor_row);
    try std.testing.expectEqual(snap_before.cursor_col, snap_after.cursor_col);
    try std.testing.expectEqual(snap_before.selection, snap_after.selection);
    try std.testing.expectEqual(snap_before.history_count, snap_after.history_count);
}

test "mouse reporting is gated by DECSET mouse modes and SGR protocol" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 5, 10);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    const mouse_event = input_mouse.MouseEvent{
        .kind = .press,
        .button = .left,
        .row = 2,
        .col = 3,
        .pixel_x = null,
        .pixel_y = null,
        .mod = .{},
        .buttons_down = 1,
    };

    try std.testing.expectEqualStrings("", encodeMouse(&terminal, mouse_event));
    write(&stream, "\x1b[?1000h\x1b[?1006h");
    try std.testing.expectEqualStrings("\x1b[<0;4;3M", encodeMouse(&terminal, mouse_event));

    const move_event = input_mouse.MouseEvent{
        .kind = .move,
        .button = .left,
        .row = 2,
        .col = 3,
        .pixel_x = null,
        .pixel_y = null,
        .mod = .{},
        .buttons_down = 1,
    };
    try std.testing.expectEqualStrings("", encodeMouse(&terminal, move_event));
    write(&stream, "\x1b[?1002h");
    try std.testing.expectEqualStrings("\x1b[<32;4;3M", encodeMouse(&terminal, move_event));
    write(&stream, "\x1b[?1003h");
    const hover_event = input_mouse.MouseEvent{
        .kind = .move,
        .button = .none,
        .row = 1,
        .col = 1,
        .pixel_x = null,
        .pixel_y = null,
        .mod = .{},
        .buttons_down = 0,
    };
    try std.testing.expectEqualStrings("\x1b[<35;2;2M", encodeMouse(&terminal, hover_event));
}

test "mouse reporting supports legacy x10 normal utf8 and urxvt encodings" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 5, 10);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    const press = input_mouse.MouseEvent{ .kind = .press, .button = .left, .row = 2, .col = 3, .mod = .{ .shift = true, .alt = true }, .buttons_down = 1 };
    const release = input_mouse.MouseEvent{ .kind = .release, .button = .left, .row = 2, .col = 3, .mod = .{}, .buttons_down = 0 };
    const wheel = input_mouse.MouseEvent{ .kind = .wheel, .button = .wheel_down, .row = 2, .col = 3, .mod = .{}, .buttons_down = 0 };

    write(&stream, "\x1b[?9h");
    try std.testing.expectEqualStrings("\x1b[M $#", encodeMouse(&terminal, press));
    try std.testing.expectEqualStrings("", encodeMouse(&terminal, release));

    write(&stream, "\x1b[?1000h");
    try std.testing.expectEqualStrings("\x1b[M,$#", encodeMouse(&terminal, press));
    try std.testing.expectEqualStrings("\x1b[M#$#", encodeMouse(&terminal, release));
    try std.testing.expectEqualStrings("\x1b[Ma$#", encodeMouse(&terminal, wheel));

    write(&stream, "\x1b[?1005h");
    const far_press = input_mouse.MouseEvent{ .kind = .press, .button = .left, .row = 240, .col = 240, .mod = .{}, .buttons_down = 1 };
    try std.testing.expectEqualStrings("\x1b[M \xc4\x91\xc4\x91", encodeMouse(&terminal, far_press));

    write(&stream, "\x1b[?1015h");
    try std.testing.expectEqualStrings("\x1b[32;241;241M", encodeMouse(&terminal, far_press));
}

test "mouse mode queries and save restore include extended protocols" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    write(&stream, "\x1b[?1003h\x1b[?1016h\x1b[?1003;1016s");
    write(&stream, "\x1b[?1000h\x1b[?1006h");
    write(&stream, "\x1b[?1003;1016r");
    write(&stream, "\x1b[?9$p\x1b[?1000$p\x1b[?1003$p\x1b[?1005$p\x1b[?1006$p\x1b[?1015$p\x1b[?1016$p");

    try std.testing.expectEqualStrings(
        "\x1b[?9;2$y\x1b[?1000;2$y\x1b[?1003;1$y\x1b[?1005;2$y" ++
            "\x1b[?1006;2$y\x1b[?1015;2$y\x1b[?1016;1$y",
        pendingOutput(&terminal),
    );
}

test "mouse and focus modes own exact protocol selection mutation and pixel reports" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b[?1000h\x1b[?1006h")).state_changed);
    try std.testing.expect((try terminal.feed("12345678")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?1000h\x1b[?1006h")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b[?1000h\x1b[?1006h")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?1002h\x1b[?1016")).state_changed);
    try std.testing.expect((try terminal.feed("h")).state_changed);

    const pixel_press = input_mouse.MouseEvent{
        .kind = .press,
        .button = .left,
        .row = 1,
        .col = 2,
        .pixel_x = 319,
        .pixel_y = 239,
        .mod = .{ .control = true },
        .buttons_down = 1,
    };
    try std.testing.expectEqualStrings("\x1b[<16;320;240M", encodeMouse(&terminal, pixel_press));

    const missing_pixel = input_mouse.MouseEvent{
        .kind = .press,
        .button = .left,
        .row = 1,
        .col = 2,
        .pixel_x = 319,
        .mod = .{},
        .buttons_down = 1,
    };
    try std.testing.expectEqualStrings("", encodeMouse(&terminal, missing_pixel));

    try std.testing.expect((try terminal.feed("\x1b[?1016l")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b[?1016l")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?1004h")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b[?1004h")).state_changed);
    try std.testing.expectEqualStrings("\x1b[I", encodeFocusIn(&terminal));
    try std.testing.expect((try terminal.feed("\x1b[?1004l")).state_changed);
    try std.testing.expectEqualStrings("", encodeFocusIn(&terminal));
}

test "application cursor mode changes arrow key encoding" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try std.testing.expectEqualStrings("\x1b[A", encodeKey(&terminal, .{ .named = .up }, .{}));
    write(&stream, "\x1b[?1h");
    try std.testing.expectEqualStrings("\x1bOA", encodeKey(&terminal, .{ .named = .up }, .{}));
    try std.testing.expectEqualStrings("\x1b[1;5A", encodeKey(&terminal, .{ .named = .up }, .{ .control = true }));
    write(&stream, "\x1b[?1l");
    try std.testing.expectEqualStrings("\x1b[A", encodeKey(&terminal, .{ .named = .up }, .{}));
}

test "kitty keyboard stack has exact flags depth mutation and replies" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b[=128u")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?u")).state_changed);
    try std.testing.expectEqualStrings("\x1b[?0u", pendingOutput(&terminal));
    clearPendingOutput(&terminal);

    try std.testing.expect(!(try terminal.feed("\x1b[=127;1")).state_changed);
    try std.testing.expect((try terminal.feed("u")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b[=127u")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b[?")).state_changed);
    try std.testing.expect((try terminal.feed("u")).state_changed);
    try std.testing.expectEqualStrings("\x1b[?127u", pendingOutput(&terminal));
    clearPendingOutput(&terminal);

    try std.testing.expect((try terminal.feed("\x1b[=8;3u\x1b[=3;2u\x1b[?u")).state_changed);
    try std.testing.expectEqualStrings("\x1b[?119u", pendingOutput(&terminal));
    clearPendingOutput(&terminal);

    try std.testing.expect((try terminal.feed(
        "\x1b[>1u\x1b[>2u\x1b[>3u\x1b[>4u\x1b[>5u\x1b[>6u\x1b[>7u\x1b[>8u",
    )).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[<7u\x1b[?u")).state_changed);
    try std.testing.expectEqualStrings("\x1b[?1u", pendingOutput(&terminal));
    clearPendingOutput(&terminal);

    try std.testing.expect((try terminal.feed("\x1b[<u\x1b[?u")).state_changed);
    try std.testing.expectEqualStrings("\x1b[?0u", pendingOutput(&terminal));
    clearPendingOutput(&terminal);
    try std.testing.expect(!(try terminal.feed("\x1b[<u")).state_changed);
}

test "invalid Kitty keyboard set mode preserves state" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    write(&stream, "\x1b[=5u\x1b[=8;4u\x1b[?u");
    try std.testing.expectEqualStrings("\x1b[?5u", pendingOutput(&terminal));
}

test "kitty keyboard flags stay separate across alternate screen" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    write(&stream, "\x1b[=1u\x1b[?1049h\x1b[=8u");
    try std.testing.expect(visibleView(&terminal, 0).is_alternate_screen);
    write(&stream, "\x1b[?u");
    try std.testing.expectEqualStrings("\x1b[?8u", pendingOutput(&terminal));
    clearPendingOutput(&terminal);
    write(&stream, "\x1b[?1049l");
    write(&stream, "\x1b[?u");
    try std.testing.expectEqualStrings("\x1b[?1u", pendingOutput(&terminal));
    clearPendingOutput(&terminal);

    write(&stream, "\x1b[?1049h\x1b[=7u\x1bc\x1b[?u");
    try std.testing.expectEqualStrings("\x1b[?0u", pendingOutput(&terminal));
    clearPendingOutput(&terminal);
    write(&stream, "\x1b[?1049h\x1b[?u");
    try std.testing.expectEqualStrings("\x1b[?0u", pendingOutput(&terminal));
}

test "kitty keyboard query preserves full pending output on failure" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    const fill_len = HostState.pending_output_max_bytes - 4;
    const fill = try allocator.alloc(u8, fill_len);
    defer allocator.free(fill);
    @memset(fill, 'x');
    try terminal.host.appendPendingOutput(fill);

    try std.testing.expectError(error.ConsequenceLimit, terminal.feed("\x1b[?u"));
    try std.testing.expectEqual(fill_len, pendingOutput(&terminal).len);
    for (pendingOutput(&terminal)) |byte| try std.testing.expectEqual(@as(u8, 'x'), byte);
}

test "kitty keyboard mode switches existing keys to CSI-u family" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    write(&stream, "\x1b[=1u");
    try std.testing.expectEqualStrings("\x1b[27u", encodeKey(&terminal, .{ .named = .escape }, .{}));
    try std.testing.expectEqualStrings("\x1b[127;5u", encodeKey(&terminal, .{ .named = .backspace }, .{ .control = true }));
    try std.testing.expectEqualStrings("\x1b[1;5A", encodeKey(&terminal, .{ .named = .up }, .{ .control = true }));
    try std.testing.expectEqualStrings("\x1b[15~", encodeKey(&terminal, .{ .named = .f5 }, .{}));

    write(&stream, "\x1b[=8u");
    try std.testing.expectEqualStrings("\x1b[127;5u", encodeKey(&terminal, .{ .named = .backspace }, .{ .control = true }));
}

test "Kitty all-key mode encodes committed Unicode key identity" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    var scratch: Terminal.InputScratch = .{};

    var legacy = try terminal.encodeInput(std.testing.allocator, &scratch, .{
        .key = .{
            .key = try Terminal.Key.initUnicode('a'),
            .legacy_text = "A",
            .text = "A",
        },
    });
    defer legacy.deinit();
    try std.testing.expectEqualStrings("A", legacy.bytes);

    write(&stream, "\x1b[=31u\x1b[?u");
    try std.testing.expectEqualStrings("\x1b[?31u", pendingOutput(&terminal));
    var encoded = try terminal.encodeInput(std.testing.allocator, &scratch, .{
        .key = .{ .key = try Terminal.Key.initUnicode('a'), .text = "A" },
    });
    defer encoded.deinit();
    try std.testing.expectEqualStrings("\x1b[97;;65u", encoded.bytes);
}

test "Kitty key events retain action alternates and bounded associated text" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    var scratch: Terminal.InputScratch = .{};
    write(&stream, "\x1b[=31u");

    var repeated = try terminal.encodeInput(std.testing.allocator, &scratch, .{
        .key = .{
            .key = try Terminal.Key.initUnicode('a'),
            .mods = .{ .shift = true },
            .action = .repeat,
            .shifted = 'A',
            .alternate = 'q',
            .text = "A",
        },
    });
    defer repeated.deinit();
    try std.testing.expectEqualStrings("\x1b[97:65:113;2:2;65u", repeated.bytes);

    var released = try terminal.encodeInput(std.testing.allocator, &scratch, .{
        .key = .{
            .key = try Terminal.Key.initUnicode('a'),
            .action = .release,
        },
    });
    defer released.deinit();
    try std.testing.expectEqualStrings("\x1b[97;1:3u", released.bytes);

    try std.testing.expectError(error.InvalidUtf8, terminal.encodeInput(
        std.testing.allocator,
        &scratch,
        .{ .key = .{ .key = try Terminal.Key.initUnicode('a'), .text = "\xff" } },
    ));
    const oversized = [_]u8{'a'} ** (input_keyboard.max_text_bytes + 1);
    try std.testing.expectError(error.KeyTextLimit, terminal.encodeInput(
        std.testing.allocator,
        &scratch,
        .{ .key = .{ .key = try Terminal.Key.initUnicode('a'), .text = &oversized } },
    ));
}

test "DECARM owns repeat encoding query save and reset lifetime" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 4);
    defer terminal.deinit();
    var scratch: Terminal.InputScratch = .{};

    var default_repeat = try terminal.encodeInput(std.testing.allocator, &scratch, .{
        .key = .{
            .key = try Terminal.Key.initUnicode('a'),
            .action = .repeat,
            .legacy_text = "a",
        },
    });
    defer default_repeat.deinit();
    try std.testing.expectEqualStrings("a", default_repeat.bytes);

    try std.testing.expect(!(try terminal.feed("\x1b[?8")).state_changed);
    try std.testing.expect((try terminal.feed("l")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b[?8l")).state_changed);
    var suppressed = try terminal.encodeInput(std.testing.allocator, &scratch, .{
        .key = .{
            .key = try Terminal.Key.initUnicode('a'),
            .action = .repeat,
            .text = "\xff",
        },
    });
    defer suppressed.deinit();
    try std.testing.expectEqualStrings("", suppressed.bytes);

    try std.testing.expect((try terminal.feed("xxxx\x1b[?8l")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b[?8l")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[=31u")).state_changed);
    var press = try terminal.encodeInput(std.testing.allocator, &scratch, .{
        .key = .{ .key = try Terminal.Key.initUnicode('a') },
    });
    defer press.deinit();
    try std.testing.expectEqualStrings("\x1b[97u", press.bytes);
    var release = try terminal.encodeInput(std.testing.allocator, &scratch, .{
        .key = .{
            .key = try Terminal.Key.initUnicode('a'),
            .action = .release,
        },
    });
    defer release.deinit();
    try std.testing.expectEqualStrings("\x1b[97;1:3u", release.bytes);

    try std.testing.expect((try terminal.feed("\x1b[?8s\x1b[?8h")).state_changed);
    var enabled_repeat = try terminal.encodeInput(std.testing.allocator, &scratch, .{
        .key = .{ .key = try Terminal.Key.initUnicode('a'), .action = .repeat },
    });
    defer enabled_repeat.deinit();
    try std.testing.expectEqualStrings("\x1b[97;1:2u", enabled_repeat.bytes);
    try std.testing.expect((try terminal.feed("\x1b[?8r")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b[!p")).state_changed);

    clearPendingOutput(&terminal);
    try std.testing.expect((try terminal.feed("\x1b[?8$p")).state_changed);
    try std.testing.expectEqualStrings("\x1b[?8;2$y", pendingOutput(&terminal));
    try std.testing.expect((try terminal.feed("\x1bc")).state_changed);
    var reset_repeat = try terminal.encodeInput(std.testing.allocator, &scratch, .{
        .key = .{
            .key = try Terminal.Key.initUnicode('a'),
            .action = .repeat,
            .legacy_text = "a",
        },
    });
    defer reset_repeat.deinit();
    try std.testing.expectEqualStrings("a", reset_repeat.bytes);
    clearPendingOutput(&terminal);
    try std.testing.expect((try terminal.feed("\x1b[?8$p")).state_changed);
    try std.testing.expectEqualStrings("\x1b[?8;1$y", pendingOutput(&terminal));
}

test "Kitty key fields preserve empty alternates locks and committed text" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    var scratch: Terminal.InputScratch = .{};
    write(&stream, "\x1b[=31u");

    var encoded = try terminal.encodeInput(std.testing.allocator, &scratch, .{
        .key = .{
            .key = try Terminal.Key.initUnicode('a'),
            .mods = .{ .super = true, .caps_lock = true, .num_lock = true },
            .alternate = 'q',
            .legacy_text = "\x1b\x01",
            .text = "éx",
        },
    });
    defer encoded.deinit();
    try std.testing.expectEqualStrings("\x1b[97::113;201;233:120u", encoded.bytes);
    try std.testing.expectError(error.InvalidText, terminal.encodeInput(
        std.testing.allocator,
        &scratch,
        .{ .key = .{
            .key = try Terminal.Key.initUnicode('a'),
            .legacy_text = "\x01",
            .text = "\x01",
        } },
    ));

    var exact: [input_keyboard.max_kitty_encoded_bytes]u8 = undefined;
    const direct = try input_keyboard.encodeEvent(
        &exact,
        try Terminal.Key.initUnicode('a'),
        .{},
        .press,
        null,
        null,
        "a",
        "a",
        false,
        false,
        0,
        0,
        31,
    );
    try std.testing.expect(direct.len <= exact.len);
    try std.testing.expectError(error.EncodingLimit, input_keyboard.encodeEvent(
        exact[0 .. input_keyboard.max_kitty_encoded_bytes - 1],
        try Terminal.Key.initUnicode('a'),
        .{},
        .press,
        null,
        null,
        "a",
        "a",
        false,
        false,
        0,
        0,
        31,
    ));

    write(&stream, "\x1b[=16u");
    var undefined_text_only = try terminal.encodeInput(
        std.testing.allocator,
        &scratch,
        .{ .key = .{
            .key = try Terminal.Key.initUnicode('a'),
            .legacy_text = "legacy",
            .text = "committed",
        } },
    );
    defer undefined_text_only.deinit();
    try std.testing.expectEqualStrings("legacy", undefined_text_only.bytes);
}

test "Kitty event reporting preserves legacy controls until all-key mode" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    var scratch: Terminal.InputScratch = .{};
    write(&stream, "\x1b[=2u");

    var enter_press = try terminal.encodeInput(std.testing.allocator, &scratch, .{
        .key = .{ .key = .{ .named = .enter } },
    });
    defer enter_press.deinit();
    try std.testing.expectEqualStrings("\r", enter_press.bytes);
    var enter_release = try terminal.encodeInput(std.testing.allocator, &scratch, .{
        .key = .{ .key = .{ .named = .enter }, .action = .release },
    });
    defer enter_release.deinit();
    try std.testing.expectEqualStrings("", enter_release.bytes);
    var shift = try terminal.encodeInput(std.testing.allocator, &scratch, .{
        .key = .{ .key = .{ .named = .left_shift } },
    });
    defer shift.deinit();
    try std.testing.expectEqualStrings("", shift.bytes);

    write(&stream, "\x1b[=10u");
    var reported_shift = try terminal.encodeInput(std.testing.allocator, &scratch, .{
        .key = .{ .key = .{ .named = .left_shift }, .mods = .{ .shift = true } },
    });
    defer reported_shift.deinit();
    try std.testing.expectEqualStrings("\x1b[57441;2u", reported_shift.bytes);
}

test "focus reports are gated by DECSET 1004" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try std.testing.expectEqualStrings("", encodeFocusIn(&terminal));
    try std.testing.expectEqualStrings("", encodeFocusOut(&terminal));
    write(&stream, "\x1b[?1004h");
    try std.testing.expectEqualStrings("\x1b[I", encodeFocusIn(&terminal));
    try std.testing.expectEqualStrings("\x1b[O", encodeFocusOut(&terminal));
    write(&stream, "\x1b[?1004l");
    try std.testing.expectEqualStrings("", encodeFocusIn(&terminal));
}

test "terminal paste encoding is gated by DECSET 2004" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    var plain = try terminal.encodeInput(allocator, &encode_scratch, .{ .paste = "paste" });
    defer plain.deinit();
    try std.testing.expectEqualStrings("paste", plain.bytes);
    write(&stream, "\x1b[?2004h");
    var bracketed = try terminal.encodeInput(allocator, &encode_scratch, .{ .paste = "paste" });
    defer bracketed.deinit();
    try std.testing.expectEqualStrings("\x1b[200~paste\x1b[201~", bracketed.bytes);
    write(&stream, "\x1b[?2004l");
    var plain_again = try terminal.encodeInput(allocator, &encode_scratch, .{ .paste = "paste" });
    defer plain_again.deinit();
    try std.testing.expectEqualStrings("paste", plain_again.bytes);
}

test "paste encoding distinguishes borrowed and owned results" {
    const text = "paste";
    var no_storage: [0]u8 = .{};
    var fixed = std.heap.FixedBufferAllocator.init(&no_storage);

    var plain = try input_encode.encodePaste(false, fixed.allocator(), text);
    try std.testing.expectEqualStrings(text, plain.bytes);
    try std.testing.expectEqual(text.ptr, plain.bytes.ptr);
    try std.testing.expectEqual(@as(?std.mem.Allocator, null), plain.allocator);
    plain.deinit();
    try std.testing.expectEqualStrings("", plain.bytes);

    try std.testing.expectError(
        error.OutOfMemory,
        input_encode.encodePaste(true, fixed.allocator(), text),
    );

    var bracketed = try input_encode.encodePaste(true, std.testing.allocator, text);
    try std.testing.expectEqualStrings("\x1b[200~paste\x1b[201~", bracketed.bytes);
    try std.testing.expect(bracketed.allocator != null);
    bracketed.deinit();
    try std.testing.expectEqualStrings("", bracketed.bytes);
    try std.testing.expectEqual(@as(?std.mem.Allocator, null), bracketed.allocator);
}

test "report queries append pending host output" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    write(&stream, "\x1b[2;3H\x1b[5n\x1b[6n\x1b[c\x1b[>c\x1b[>0q\x1b[#S");
    try std.testing.expectEqualStrings("\x1b[0n\x1b[2;3R\x1b[?62;22c\x1b[>1;10;0c\x1bP>|howl-vt dev\x1b\\\x1b[0;0#S", pendingOutput(&terminal));

    clearPendingOutput(&terminal);
    try std.testing.expectEqualStrings("", pendingOutput(&terminal));
}

test "device and status queries retain exact scalar transcripts and origin coordinates" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 6, 10);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b[");
    try stream.nextSlice("c\x1b[>0");
    try stream.nextSlice("c\x1b[=c\x1b[5n");
    try std.testing.expectEqualStrings(
        "\x1b[?62;22c\x1b[>1;10;0c\x1bP!|00000000\x1b\\\x1b[0n",
        pendingOutput(&terminal),
    );

    clearPendingOutput(&terminal);
    write(&stream, "\x1b[2;5r\x1b[?69h\x1b[3;8s\x1b[?6h\x1b[2;3H\x1b[6n\x1b[?5n\x1b[?6n");
    try std.testing.expectEqualStrings("\x1b[2;3R\x1b[0n\x1b[?2;3R", pendingOutput(&terminal));
    const view = visibleView(&terminal, 0);
    try std.testing.expectEqual(@as(u16, 2), view.cursor_row);
    try std.testing.expectEqual(@as(u16, 4), view.cursor_col);

    clearPendingOutput(&terminal);
    const malformed = try terminal.feed(
        "\x1b[1c\x1b[>1c\x1b[=1c\x1b[5;6n\x1b[?6;7n\x1b[6;7$p\x1b[?6;7$p\x1b[0;1x\x1b[?9999n" ++
            "\x1b[0$c\x1b[>0$c\x1b[=0$c\x1b[5$n\x1b[?6$n\x1b[?6$#p\x1b[0$x",
    );
    try std.testing.expect(!malformed.state_changed);
    try std.testing.expectEqualStrings("", pendingOutput(&terminal));

    const unknown = try terminal.feed("\x1b[?9999$p\x1b[0x\x1b[1x\x1b[2x");
    try std.testing.expect(unknown.state_changed);
    try std.testing.expectEqualStrings(
        "\x1b[?9999;0$y\x1b[2;1;1;128;128;1;0x\x1b[3;1;1;128;128;1;0x",
        pendingOutput(&terminal),
    );
}

test "cursor reports bound restored positions against changed origin margins" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 8, 12);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    write(&stream, "\x1b[?69h\x1b[2;6r\x1b[2;8s\x1b[?6h\x1b[2;2H\x1b7");
    write(&stream, "\x1b[5;8r\x1b[7;12s\x1b8\x1b[6n\x1b[?6n");

    const view = visibleView(&terminal, 0);
    try std.testing.expectEqual(@as(u16, 4), view.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), view.cursor_col);
    try std.testing.expectEqualStrings("\x1b[1;1R\x1b[?1;1R", pendingOutput(&terminal));
}

test "report query limit fails without partial pending output" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    const fill_len = HostState.pending_output_max_bytes - 3;
    const fill = try allocator.alloc(u8, fill_len);
    defer allocator.free(fill);
    @memset(fill, 'x');
    try terminal.host.appendPendingOutput(fill);

    try std.testing.expectError(error.ConsequenceLimit, stream.nextSlice("\x1b[5n"));
    try std.testing.expectEqual(fill_len, pendingOutput(&terminal).len);

    clearPendingOutput(&terminal);
    try stream.nextSlice("\x1b[");
    try stream.nextSlice("5n");
    try std.testing.expectEqualStrings("\x1b[0n", pendingOutput(&terminal));

    clearPendingOutput(&terminal);
    try terminal.host.appendPendingOutput(fill);
    try std.testing.expectError(error.ConsequenceLimit, stream.nextSlice("\x1bP$qr\x1b\\"));
    try std.testing.expectEqual(fill_len, pendingOutput(&terminal).len);

    clearPendingOutput(&terminal);
    try stream.nextSlice("\x1bP$q");
    try stream.nextSlice("r\x1b\\");
    try std.testing.expectEqualStrings("\x1bP1$r1;4r\x1b\\", pendingOutput(&terminal));
}

test "S7C1T and S8C1T serialize mixed replies through one bounded owner" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    try terminal.setCellPixelSize(9, 18);

    write(&stream, "\x1b]4;1;#010203\x1b\\");
    clearPendingOutput(&terminal);
    try stream.nextSlice("\x1b ");
    try stream.nextSlice("G\x1b[5n\x1bP$qr\x1b\\\x1b]4;1;?\x1b\\\x1b[?u\x1b]1337;ReportCellSize\x07");
    try std.testing.expectEqualStrings(
        "\x9b0n\x901$r1;3r\x9c\x9d4;1;rgb:01/02/03\x9c" ++
            "\x1b[?0u\x1b]1337;ReportCellSize=18;9;1\x1b\\",
        pendingOutput(&terminal),
    );

    clearPendingOutput(&terminal);
    write(&stream, "\x1b7");
    try stream.nextSlice("\x1b ");
    try stream.nextSlice("F\x1b8\x1b[5n");
    try std.testing.expectEqualStrings("\x1b[0n", pendingOutput(&terminal));

    clearPendingOutput(&terminal);
    write(&stream, "\x1b G\x1bc\x1b[5n");
    try std.testing.expectEqualStrings("\x1b[0n", pendingOutput(&terminal));
}

test "terminal size reports use exact current cell and pixel facts" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 5);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b[1");
    try stream.nextSlice("8t");
    try std.testing.expectEqualStrings("\x1b[8;3;5t", pendingOutput(&terminal));

    clearPendingOutput(&terminal);
    try std.testing.expect(!(try terminal.feed("\x1b[14t\x1b[16t")).state_changed);
    try std.testing.expectEqualStrings("", pendingOutput(&terminal));

    try terminal.setCellPixelSize(9, 17);
    try terminal.resize(4, 7);
    clearPendingOutput(&terminal);
    try stream.nextSlice("\x1b G\x9b14");
    try stream.nextSlice(";0t\x9b16;0t\x9b18;0t");
    try std.testing.expectEqualStrings(
        "\x9b4;68;63t\x9b6;17;9t\x9b8;4;7t",
        pendingOutput(&terminal),
    );

    clearPendingOutput(&terminal);
    try stream.nextSlice("\x1bc");
    try stream.nextSlice("\x1b[14;2t\x1b[16t\x1b[18t");
    try std.testing.expectEqualStrings(
        "\x1b[4;68;63t\x1b[6;17;9t\x1b[8;4;7t",
        pendingOutput(&terminal),
    );

    clearPendingOutput(&terminal);
    try stream.nextSlice("\x1b[14;0;0t\x1b[16;-1t\x1b[19t");
    try std.testing.expectEqualStrings("", pendingOutput(&terminal));

    const fill = try allocator.alloc(u8, HostState.pending_output_max_bytes - 1);
    defer allocator.free(fill);
    @memset(fill, 'x');
    try terminal.host.appendPendingOutput(fill);
    try std.testing.expectError(error.ConsequenceLimit, stream.nextSlice("\x1b[18t"));
    try std.testing.expectEqualSlices(u8, fill, pendingOutput(&terminal));
}

test "title stack retains exact bounded title lifecycle and report bytes" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 5);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try std.testing.expect(!(try terminal.feed("\x1b[22t")).state_changed);
    try stream.nextSlice("\x1b]2;on");
    const first = try terminal.feed("e\x1b\\");
    try std.testing.expect(first.state_changed and first.title_changed);

    const push_first = try terminal.feed("\x1b[22t");
    try std.testing.expect(push_first.state_changed and !push_first.title_changed);
    try stream.nextSlice("\x1b]2;two\x07\x1b[22;2;0t\x1b]2;three\x1b\\");
    try std.testing.expect(!(try terminal.feed("\x1b[22;1t\x1b[23;1t")).state_changed);

    const pop_second = try terminal.feed("\x1b[23;2;0t");
    try std.testing.expect(pop_second.state_changed and pop_second.title_changed);
    try std.testing.expectEqualStrings("two", terminal.host.current_title.?);

    try stream.nextSlice("\x1bc");
    const pop_first = try terminal.feed("\x1b[23t");
    try std.testing.expect(pop_first.state_changed and pop_first.title_changed);
    try std.testing.expectEqualStrings("one", terminal.host.current_title.?);
    try std.testing.expect(!(try terminal.feed("\x1b[23t")).state_changed);

    clearPendingOutput(&terminal);
    try stream.nextSlice("\x1b G\x9b2");
    try stream.nextSlice("1t");
    try std.testing.expectEqualStrings("\x1b]lone\x1b\\", pendingOutput(&terminal));

    clearPendingOutput(&terminal);
    const fill = try allocator.alloc(u8, HostState.pending_output_max_bytes - 2);
    defer allocator.free(fill);
    @memset(fill, 'x');
    try terminal.host.appendPendingOutput(fill);
    try std.testing.expectError(error.ConsequenceLimit, stream.nextSlice("\x9b21t"));
    try std.testing.expectEqualSlices(u8, fill, pendingOutput(&terminal));
}

test "eight-bit multipart reply limit rolls back every framing byte" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    write(&stream, "\x1b G\x1b[1;3;38;5;200m");

    const fill_len = HostState.pending_output_max_bytes - 2;
    const fill = try allocator.alloc(u8, fill_len);
    defer allocator.free(fill);
    @memset(fill, 'x');
    try terminal.host.appendPendingOutput(fill);

    try std.testing.expectError(error.ConsequenceLimit, stream.nextSlice("\x1bP$qm\x1b\\"));
    try std.testing.expectEqual(fill_len, pendingOutput(&terminal).len);
    for (pendingOutput(&terminal)) |byte| try std.testing.expectEqual(@as(u8, 'x'), byte);
}

test "ENQ default answerback is empty and printable space remains text" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 2, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    write(&stream, "A \x05B");

    try std.testing.expectEqualStrings("", pendingOutput(&terminal));
    const view = visibleView(&terminal, 0);
    try std.testing.expectEqual(@as(u16, 0), view.cursor_row);
    try std.testing.expectEqual(@as(u16, 3), view.cursor_col);
    try std.testing.expectEqual(@as(u21, 'A'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, ' '), view.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'B'), view.cellAt(0, 2));
}

test "extended report queries append host output" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 18);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    write(&stream, "\x1bH\x1b[=c\x1b[\"v\x1b[0x\x1b[1x");

    try std.testing.expectEqualStrings("\x1bP!|00000000\x1b\\\x1b[4;18;1;1;1\"w\x1b[2;1;1;128;128;1;0x\x1b[3;1;1;128;128;1;0x", pendingOutput(&terminal));
}

test "ANSI mode queries and XTREPORTCOLORS append host output" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    write(&stream, "\x1b[2h\x1b[4h\x1b[12h\x1b[20h\x1b]30001\x1b\\\x1b[2$p\x1b[4$p\x1b[12$p\x1b[20$p\x1b[#R");
    try std.testing.expectEqualStrings("\x1b[2;1$y\x1b[4;1$y\x1b[12;1$y\x1b[20;1$y\x1b[0;1#Q", pendingOutput(&terminal));
}

test "XTREPORTSGR reports common rectangle attrs conservatively" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 2, 4);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    write(&stream, "\x1b[31mAB\x1b[0mCD\x1b[1;1;1;2#|\x1b[1;1;1;4#|");
    try std.testing.expectEqualStrings("\x1b[0;31m\x1b[0m", pendingOutput(&terminal));
}

test "XTREPORTSGR reports extended style attrs" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 1, 2);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    write(&stream, "\x1b[1;2;3;8;9mAB\x1b[1;1;1;2#|");
    try std.testing.expectEqualStrings("\x1b[0;1;2;3;8;9m", pendingOutput(&terminal));
}

test "ANSI modes affect key encoding and insert writes" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 2, 4);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try std.testing.expectEqualStrings("\r", encodeKey(&terminal, .{ .named = .enter }, .{}));
    write(&stream, "\x1b[20h\x1b[2h");
    try std.testing.expectEqualStrings("", encodeKey(&terminal, try input_keyboard.InputKey.initUnicode('a'), .{}));

    write(&stream, "\x1b[2l");
    try std.testing.expectEqualStrings("\r\n", encodeKey(&terminal, .{ .named = .enter }, .{}));

    write(&stream, "ABCD\x1b[4h\x1b[1;2H!\x1b[4$p");
    const view = visibleView(&terminal, 0);
    try std.testing.expectEqual(@as(u21, 'A'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, '!'), view.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'B'), view.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 'C'), view.cellAt(0, 3));
    try std.testing.expectEqualStrings("\x1b[4;1$y", pendingOutput(&terminal));
}

test "checksum extension affects rectangular checksum reply" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 2, 2);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    write(&stream, "ABCD\x1b[0#y\x1b[7;1;1;1;1;2;2*y");
    try std.testing.expectEqualStrings("\x1bP7!~FF7C\x1b\\", pendingOutput(&terminal));

    clearPendingOutput(&terminal);
    write(&stream, "\x1b[1#y\x1b[8;1;1;1;1;2;2*y");
    try std.testing.expectEqualStrings("\x1bP8!~0083\x1b\\", pendingOutput(&terminal));
}

test "locator requests reply unavailable, then current position, then disable one-shot" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    write(&stream, "\x1b[0'|");
    try std.testing.expectEqualStrings("\x1b[0&w", pendingOutput(&terminal));

    clearPendingOutput(&terminal);
    write(&stream, "\x1b[1;0'z");
    _ = encodeMouse(&terminal, .{ .kind = .move, .button = .none, .row = 2, .col = 3, .mod = .{}, .buttons_down = 1 });
    write(&stream, "\x1b[0'|");
    try std.testing.expectEqualStrings("\x1b[1;4;3;4;0&w", pendingOutput(&terminal));

    clearPendingOutput(&terminal);
    write(&stream, "\x1b[2;0'z\x1b[0'|");
    try std.testing.expectEqualStrings("\x1b[1;4;3;4;0&w", pendingOutput(&terminal));
    clearPendingOutput(&terminal);
    write(&stream, "\x1b[0'|");
    try std.testing.expectEqualStrings("\x1b[0&w", pendingOutput(&terminal));
}

test "locator button and filter events append DECLRP" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    write(&stream, "\x1b[1;0'z\x1b[1;3'*{");

    _ = encodeMouse(&terminal, .{ .kind = .press, .button = .left, .row = 1, .col = 2, .mod = .{}, .buttons_down = 1 });
    try std.testing.expectEqualStrings("\x1b[2;4;2;3;0&w", pendingOutput(&terminal));

    clearPendingOutput(&terminal);
    _ = encodeMouse(&terminal, .{ .kind = .release, .button = .left, .row = 1, .col = 2, .mod = .{}, .buttons_down = 0 });
    try std.testing.expectEqualStrings("\x1b[3;0;2;3;0&w", pendingOutput(&terminal));

    clearPendingOutput(&terminal);
    write(&stream, "\x1b[2;2;2;2'w");
    _ = encodeMouse(&terminal, .{ .kind = .move, .button = .none, .row = 3, .col = 3, .mod = .{}, .buttons_down = 0 });
    try std.testing.expectEqualStrings("\x1b[10;0;4;4;0&w", pendingOutput(&terminal));
}

test "locator ignores rows outside its retained coordinate domain" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    write(&stream, "\x1b[1;0'z\x1b[1'*{");

    const rows = [_]i32{ -1, @as(i32, std.math.maxInt(u16)) + 1 };
    for (rows) |row| {
        var encoded = try terminal.encodeInput(allocator, &encode_scratch, .{ .mouse = .{
            .kind = .press,
            .button = .left,
            .row = row,
            .col = 2,
            .mod = .{},
            .buttons_down = 1,
        } });
        encoded.deinit();
        try std.testing.expectEqualStrings("", pendingOutput(&terminal));
    }

    var encoded = try terminal.encodeInput(allocator, &encode_scratch, .{ .mouse = .{
        .kind = .press,
        .button = .left,
        .row = std.math.maxInt(u16),
        .col = 2,
        .mod = .{},
        .buttons_down = 1,
    } });
    defer encoded.deinit();
    try std.testing.expectEqualStrings("\x1b[2;4;65536;3;0&w", pendingOutput(&terminal));
}

test "locator mouse allocation failure is exact and preserves one-shot reporting" {
    const setup = "\x1b[2;0'z\x1b[1'*{";
    const event: input_mouse.MouseEvent = .{
        .kind = .press,
        .button = .left,
        .row = 1,
        .col = 2,
        .mod = .{},
        .buttons_down = 1,
    };

    var probe_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    {
        var terminal = try Terminal.init(probe_allocator.allocator(), 4, 8);
        defer terminal.deinit();
        var stream = try StreamHarness.init(&terminal);
        try stream.nextSlice(setup);
    }

    var failing_allocator = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{ .fail_index = probe_allocator.alloc_index },
    );
    var terminal = try Terminal.init(failing_allocator.allocator(), 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    try stream.nextSlice(setup);

    try std.testing.expectError(
        error.OutOfMemory,
        terminal.encodeInput(failing_allocator.allocator(), &encode_scratch, .{ .mouse = event }),
    );
    try std.testing.expectEqualStrings("", pendingOutput(&terminal));

    failing_allocator.fail_index = std.math.maxInt(usize);
    var encoded = try terminal.encodeInput(failing_allocator.allocator(), &encode_scratch, .{ .mouse = event });
    encoded.deinit();
    try std.testing.expectEqualStrings("\x1b[2;4;2;3;0&w", pendingOutput(&terminal));

    clearPendingOutput(&terminal);
    encoded = try terminal.encodeInput(failing_allocator.allocator(), &encode_scratch, .{ .mouse = event });
    encoded.deinit();
    try std.testing.expectEqualStrings("", pendingOutput(&terminal));
}

test "locator mouse output limit is exact and preserves pending output" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    try stream.nextSlice("\x1b[1;0'z\x1b[1'*{");

    const fill = try allocator.alloc(u8, host_state.pending_output_max_bytes);
    defer allocator.free(fill);
    @memset(fill, 'x');
    try terminal.host.appendPendingOutput(fill);

    const event: input_mouse.MouseEvent = .{
        .kind = .press,
        .button = .left,
        .row = 1,
        .col = 2,
        .mod = .{},
        .buttons_down = 1,
    };
    try std.testing.expectError(
        error.ConsequenceLimit,
        terminal.encodeInput(allocator, &encode_scratch, .{ .mouse = event }),
    );
    try std.testing.expectEqual(@as(usize, host_state.pending_output_max_bytes), pendingOutput(&terminal).len);

    clearPendingOutput(&terminal);
    var encoded = try terminal.encodeInput(allocator, &encode_scratch, .{ .mouse = event });
    defer encoded.deinit();
    try std.testing.expectEqualStrings("\x1b[2;4;2;3;0&w", pendingOutput(&terminal));
}

test "DECCIR cursor information request is not supported" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 10);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    write(&stream, "\x1b[1$w");
    try std.testing.expectEqualStrings("", pendingOutput(&terminal));
}

test "DECRSPS restores bounded cursor rendition wrap origin and line drawing" {
    var terminal = try Terminal.init(std.testing.allocator, 4, 12);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b[2;3H\x1b[2;3m")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1bP1$t3;12;1;")).state_changed);
    const restored = try terminal.feed("O;@;I;0;2;O;0BBB\x1b\\");
    try std.testing.expect(restored.state_changed);

    const active = terminal.screen_state.activeConst();
    try std.testing.expectEqual(@as(u16, 2), active.cursor.row);
    try std.testing.expectEqual(@as(u16, 11), active.cursor.col);
    try std.testing.expect(active.current_attrs.reverse);
    try std.testing.expect(active.current_attrs.blink);
    try std.testing.expect(active.current_attrs.underline);
    try std.testing.expect(active.current_attrs.bold);
    try std.testing.expect(active.wrap_pending);
    try std.testing.expect(active.origin_mode);
    try std.testing.expectEqual(@as(u8, '0'), terminal.designations[0]);

    const repeated = try terminal.feed("\x1bP1$t3;12;1;O;@;I;0;2;O;0BBB\x1b\\");
    try std.testing.expect(!repeated.state_changed);
    const malformed = try terminal.feed("\x1bP1$tbad;12;1;O;@;I;0;2;O;0BBB\x1b\\");
    try std.testing.expect(!malformed.state_changed);
    const cursor_before = terminal.screen_state.activeConst().cursor;
    const attrs_before = terminal.screen_state.activeConst().current_attrs;
    const wrap_before = terminal.screen_state.activeConst().wrap_pending;
    const origin_before = terminal.screen_state.activeConst().origin_mode;
    const designations_before = terminal.designations;
    const trailing_field = try terminal.feed("\x1bP1$t1;1;1;@;@;@;0;2;O;BBBB;extra\x1b\\");
    try std.testing.expect(!trailing_field.state_changed);
    const trailing_designation = try terminal.feed("\x1bP1$t1;1;1;@;@;@;0;2;O;BBBBx\x1b\\");
    try std.testing.expect(!trailing_designation.state_changed);
    try std.testing.expect(std.meta.eql(cursor_before, terminal.screen_state.activeConst().cursor));
    try std.testing.expect(std.meta.eql(attrs_before, terminal.screen_state.activeConst().current_attrs));
    try std.testing.expectEqual(wrap_before, terminal.screen_state.activeConst().wrap_pending);
    try std.testing.expectEqual(origin_before, terminal.screen_state.activeConst().origin_mode);
    try std.testing.expectEqualSlices(u8, designations_before[0..], terminal.designations[0..]);
    try std.testing.expectEqual(@as(u16, 2), terminal.screen_state.activeConst().cursor.row);
    const clamped = try terminal.feed("\x1bP1$t999999;999999;1;O;@;A;0;2;O;0BBB\x1b\\");
    try std.testing.expect(clamped.state_changed);
    try std.testing.expectEqual(@as(u16, 3), terminal.screen_state.activeConst().cursor.row);
    try std.testing.expectEqual(@as(u16, 11), terminal.screen_state.activeConst().cursor.col);
    try std.testing.expect(!terminal.screen_state.activeConst().wrap_pending);

    try std.testing.expect((try terminal.feed("\x1b)A\x0e")).state_changed);
    try std.testing.expectEqual(@as(u8, 1), terminal.gl_index);
    try std.testing.expectEqual(@as(u8, 'A'), terminal.designations[1]);
    const restore_g0 = try terminal.feed("\x1bP1$t4;12;1;O;@;A;0;2;O;BBBB\x1b\\");
    try std.testing.expect(restore_g0.state_changed);
    try std.testing.expectEqual(@as(u8, 1), terminal.gl_index);
    try std.testing.expectEqual(@as(u8, 'B'), terminal.designations[0]);
    try std.testing.expectEqual(@as(u8, 'A'), terminal.designations[1]);
}

test "DECRSPS replaces active bounded tab stops transactionally" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 18);
    defer terminal.deinit();

    try std.testing.expect(terminal.screen_state.activeConst().tabStopAt(8));
    try std.testing.expect(!(try terminal.feed("\x1bP2$t3/11/999/bad")).state_changed);
    try std.testing.expect((try terminal.feed("/0/3\x1b\\")).state_changed);
    const active = terminal.screen_state.activeConst();
    try std.testing.expect(active.tabStopAt(2));
    try std.testing.expect(active.tabStopAt(10));
    try std.testing.expect(!active.tabStopAt(8));

    try std.testing.expect(!(try terminal.feed("\x1bP2$t3/11/999/bad/0/3\x1b\\")).state_changed);
    try std.testing.expect((try terminal.feed("\x1bP2$t\x1b\\")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1bP2$t\x1b\\")).state_changed);
    try std.testing.expect(!terminal.screen_state.activeConst().tabStopAt(2));
}

test "DECXCPR appends DEC cursor position report" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    write(&stream, "\x1b[3;4H\x1b[?6n");
    try std.testing.expectEqualStrings("\x1b[?3;4R", pendingOutput(&terminal));
}

test "DEC locator DSR replies status and type" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    write(&stream, "\x1b[?55n\x1b[?56n");
    try std.testing.expectEqualStrings("\x1b[?50n\x1b[?57;1n", pendingOutput(&terminal));
}

test "DEC mode queries append DECRPM replies" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    write(&stream, "\x1b[?1004h\x1b[?2004h\x1b[?1002h\x1b[?1006h\x1b[?1004$p\x1b[?2004$p\x1b[?1002$p\x1b[?1006$p\x1b[?25$p\x1b[?9999$p");
    try std.testing.expectEqualStrings("\x1b[?1004;1$y\x1b[?2004;1$y\x1b[?1002;1$y\x1b[?1006;1$y\x1b[?25;1$y\x1b[?9999;0$y", pendingOutput(&terminal));
}

test "DECRQSS replies for owned state and invalid requests" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    write(&stream, "\x1bP$qr\x1b\\\x1bP$qs\x1b\\\x1bP$q q\x1b\\\x1bP$q\"q\x1b\\\x1bP$qm\x1b\\\x1bP$qbad\x1b\\");
    try std.testing.expectEqualStrings(
        "\x1bP1$r1;4r\x1b\\\x1bP1$r1;8s\x1b\\\x1bP1$r1 q\x1b\\" ++
            "\x1bP1$r2\"q\x1b\\\x1bP1$r0m\x1b\\\x1bP0$r\x1b\\",
        pendingOutput(&terminal),
    );

    clearPendingOutput(&terminal);
    write(
        &stream,
        "\x1b[2;3r\x1b[?69h\x1b[2;7s\x1b[3 q\x1b[1\"q" ++
            "\x1b[2*x\x1b[19;1;3;4:3;5;7;8;9;38;5;200;48;2;1;2;3;58;2;4;5;6;73m\x1b7" ++
            "\x1b[0m\x1b[0\"q\x1b[6 q\x1b8\x1b G",
    );
    try stream.nextSlice("\x90$q");
    try stream.nextSlice("r\x9c\x90$qs\x9c\x90$q q\x9c\x90$q\"q\x9c\x90$q*x\x9c\x90$qm\x9c");
    try std.testing.expectEqualStrings(
        "\x901$r2;3r\x9c\x901$r2;7s\x9c\x901$r3 q\x9c\x901$r1\"q\x9c\x901$r2*x\x9c" ++
            "\x901$r0;1;3;4:3;5;7;8;9;19;38;5;200;48;2;1;2;3;58;2;4;5;6;73m\x9c",
        pendingOutput(&terminal),
    );

    clearPendingOutput(&terminal);
    write(
        &stream,
        "\x1b[1 q\x90$q q\x9c\x1b[2 q\x90$q q\x9c\x1b[3 q\x90$q q\x9c" ++
            "\x1b[4 q\x90$q q\x9c\x1b[5 q\x90$q q\x9c\x1b[6 q\x90$q q\x9c",
    );
    try std.testing.expectEqualStrings(
        "\x901$r1 q\x9c\x901$r2 q\x9c\x901$r3 q\x9c\x901$r4 q\x9c\x901$r5 q\x9c\x901$r6 q\x9c",
        pendingOutput(&terminal),
    );

    clearPendingOutput(&terminal);
    write(&stream, "\x1bc\x1bP$qr\x1b\\\x1bP$qs\x1b\\\x1bP$q q\x1b\\\x1bP$q\"q\x1b\\\x1bP$qm\x1b\\");
    try std.testing.expectEqualStrings(
        "\x1bP1$r1;4r\x1b\\\x1bP1$r1;8s\x1b\\\x1bP1$r1 q\x1b\\" ++
            "\x1bP1$r2\"q\x1b\\\x1bP1$r0m\x1b\\",
        pendingOutput(&terminal),
    );
}

test "DECRQSS reports conformance and page length across framing modes" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    // DECSCL shares DA1's VT220 identity. DECSLPP follows iTerm2's minimum
    // page length of 24 while retaining larger owned screen dimensions.
    try std.testing.expect(!(try terminal.feed("\x1bP$q\"")).state_changed);
    try std.testing.expect((try terminal.feed("p\x1b\\\x1bP$qt\x1b\\\x1b[c")).state_changed);
    try std.testing.expectEqualStrings(
        "\x1bP1$r62\"p\x1b\\\x1bP1$r24t\x1b\\\x1b[?62;22c",
        pendingOutput(&terminal),
    );

    clearPendingOutput(&terminal);
    try terminal.resize(30, 8);
    write(&stream, "\x1b G\x90$q\"p\x9c\x90$qt\x9c");
    try std.testing.expectEqualStrings("\x901$r62\"p\x9c\x901$r30t\x9c", pendingOutput(&terminal));
}

test "XTGETTCAP replies preserve ordered names values failures and C1 serialization" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1bP+q436F;636f6c6f")).state_changed);
    try std.testing.expect((try terminal.feed("7273;524742;5463;5375;626f677573;4;zz\x1b\\")).state_changed);
    try std.testing.expectEqualStrings(
        "\x1bP1+r436F=323536\x1b\\" ++
            "\x1bP1+r636f6c6f7273=323536\x1b\\" ++
            "\x1bP1+r524742=38\x1b\\" ++
            "\x1bP1+r5463\x1b\\" ++
            "\x1bP1+r5375\x1b\\" ++
            "\x1bP0+r626f677573\x1b\\" ++
            "\x1bP0+r4\x1b\\" ++
            "\x1bP0+rzz\x1b\\",
        pendingOutput(&terminal),
    );

    clearPendingOutput(&terminal);
    try std.testing.expect((try terminal.feed("\x1bP+Q6E616D65\x1b\\")).state_changed);
    try std.testing.expectEqualStrings("\x1bP0+R6E616D65\x1b\\", pendingOutput(&terminal));

    clearPendingOutput(&terminal);
    try std.testing.expect((try terminal.feed("\x1b G\x90+q436f;5463\x9c")).state_changed);
    try std.testing.expectEqualStrings("\x901+r436f=323536\x9c\x901+r5463\x9c", pendingOutput(&terminal));
}

test "XTGETTCAP response capacity failure rolls back every requested reply" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    const fill = try allocator.alloc(u8, host_state.pending_output_max_bytes - 8);
    defer allocator.free(fill);
    @memset(fill, 'x');
    try terminal.host.appendPendingOutput(fill);

    try std.testing.expectError(
        error.ConsequenceLimit,
        terminal.feed("\x1bP+q436F;5463\x1b\\"),
    );
    try std.testing.expectEqualSlices(u8, fill, pendingOutput(&terminal));
}

test "DCS legacy payload protocols retain latest host-neutral payload" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    write(&stream, "\x1bP+p436F=7661\x1b\\");
    try std.testing.expect(dcsPayloadKind(&terminal).? == .xtsettcap);
    try std.testing.expectEqualStrings("436F=7661", dcsPayload(&terminal).?);
}

test "DCS legacy payload protocols retain latest host-neutral payload across slices" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1bP+p436F=");
    try stream.nextSlice("7661\x1b\\");
    try std.testing.expect(dcsPayloadKind(&terminal).? == .xtsettcap);
    try std.testing.expectEqualStrings("436F=7661", dcsPayload(&terminal).?);
}

test "canceled DCS discards its partial consequence before the next complete DCS" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1bP+p436F=drop\x18");
    try std.testing.expectEqual(@as(?dcs_payload.DcsPayloadKind, null), dcsPayloadKind(&terminal));
    try std.testing.expectEqual(@as(?[]const u8, null), dcsPayload(&terminal));

    try stream.nextSlice("\x1bP+p436F=keep\x1b\\");
    try std.testing.expectEqual(dcs_payload.DcsPayloadKind.xtsettcap, dcsPayloadKind(&terminal).?);
    try std.testing.expectEqualStrings("436F=keep", dcsPayload(&terminal).?);
}

test "DCS payload bound reports overflow and remains restartable" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();

    const header = "\x1bP+p436F=";
    const half = (parser_mod.max_metadata_control_bytes - 5) / 2;
    const remainder = parser_mod.max_metadata_control_bytes - 5 - half;
    try std.testing.expect(!(try terminal.feed(header)).history_lost);
    try std.testing.expect(!(try terminal.feed("x" ** half)).history_lost);
    try std.testing.expect(!(try terminal.feed("x" ** remainder)).history_lost);
    try std.testing.expect(!(try terminal.feed("\x1b\\")).history_lost);
    try std.testing.expectEqual(@as(usize, parser_mod.max_metadata_control_bytes), dcsPayload(&terminal).?.len);

    try std.testing.expect(!(try terminal.feed(header)).history_lost);
    try std.testing.expect(!(try terminal.feed("y" ** half)).history_lost);
    try std.testing.expect(!(try terminal.feed("y" ** remainder)).history_lost);
    try std.testing.expectError(error.StringControlLimit, terminal.feed("y"));
    try std.testing.expectEqual(@as(usize, parser_mod.max_metadata_control_bytes), dcsPayload(&terminal).?.len);
    try std.testing.expectEqual(@as(u8, 'x'), dcsPayload(&terminal).?[5]);

    try std.testing.expect(!(try terminal.feed("\x1bP+pkeep\x1b\\")).history_lost);
    try std.testing.expectEqualStrings("keep", dcsPayload(&terminal).?);
}

test "legacy Tektronix C0 and ESC controls retain latest host-neutral state" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    write(&stream, "\x1c\x1d\x1e\x1f");
    try std.testing.expect(legacyControl(&terminal).? == .tek_alpha);

    write(&stream, "\x1b\x17\x1b\x1c\x1bl\x1bs");
    try std.testing.expect(legacyControl(&terminal).? == .tek_write_thru_short_dashed);
}

test "XTSAVE and XTRESTORE restore supported DEC private modes" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    write(&stream, "\x1b[?1h\x1b[?7l\x1b[?25l\x1b[?1004h\x1b[?2004h");
    write(&stream, "\x1b[?1;7;25;1004;2004s");
    write(&stream, "\x1b[?1l\x1b[?7h\x1b[?25h\x1b[?1004l\x1b[?2004l");
    write(&stream, "\x1b[?1;7;25;1004;2004r");
    write(&stream, "\x1b[?1$p\x1b[?7$p\x1b[?25$p\x1b[?1004$p\x1b[?2004$p");

    const view = visibleView(&terminal, 0);
    try std.testing.expectEqualStrings("\x1bOA", encodeKey(&terminal, .{ .named = .up }, .{}));
    try std.testing.expect(!view.screen.auto_wrap);
    try std.testing.expect(!view.cursor_visible);
    try std.testing.expectEqualStrings("\x1b[I", encodeFocusIn(&terminal));
    var paste = try terminal.encodeInput(allocator, &encode_scratch, .{ .paste = "x" });
    defer paste.deinit();
    try std.testing.expectEqualStrings("\x1b[200~x\x1b[201~", paste.bytes);
    try std.testing.expectEqualStrings("\x1b[?1;1$y\x1b[?7;2$y\x1b[?25;2$y\x1b[?1004;1$y\x1b[?2004;1$y", pendingOutput(&terminal));
}

test "DEC cursor and alternate modes preserve bounded lifecycle truth" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed(
        "\x1b[?5h\x1b[?6h\x1b[?7l\x1b[3;4H\x1b[4 q\x1b[1m\x1b)0\x0e\x1b[?1048h",
    )).state_changed);
    try std.testing.expect((try terminal.feed(
        "\x1b[?5l\x1b[?6l\x1b[?7h\x1b[1;1H\x1b[1 q\x1b[0m\x1b)B\x0f\x1b[?1048l",
    )).state_changed);
    const restored = terminal.screen_state.activeConst();
    try std.testing.expectEqual(@as(u16, 2), restored.cursor.row);
    try std.testing.expectEqual(@as(u16, 3), restored.cursor.col);
    try std.testing.expectEqual(.underline, restored.cursor.effective_shape);
    try std.testing.expect(!restored.cursor.blink_intent);
    try std.testing.expect(restored.current_attrs.bold);
    try std.testing.expect(terminal.modes.reverse_screen_mode);
    try std.testing.expect(restored.origin_mode);
    try std.testing.expect(!restored.auto_wrap);
    try std.testing.expectEqual(@as(u8, 1), terminal.gl_index);
    try std.testing.expectEqual(@as(u8, '0'), terminal.designations[1]);

    clearPendingOutput(&terminal);
    const query = try terminal.feed("\x1b[?6$p");
    try std.testing.expect(!query.title_changed and !query.icon_changed);
    try std.testing.expectEqualStrings("\x1b[?6;1$y", pendingOutput(&terminal));

    try std.testing.expect((try terminal.feed("\x1b[?1049h")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b[?1049h")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?1049l")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b[?1049l")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b[?9999h\x1b[?1049x")).state_changed);

    try std.testing.expect((try terminal.feed("\x1b[?1047hALT")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?1047l")).state_changed);
    try terminal.resize(5, 10);
    try std.testing.expect((try terminal.feed("\x1b[?1047h")).state_changed);
    const alternate = terminal.screen_state.activeConst();
    try std.testing.expectEqual(@as(u16, 5), alternate.rows);
    try std.testing.expectEqual(@as(u16, 10), alternate.cols);
    try std.testing.expectEqual(@as(u21, 0), alternate.cellAt(0, 0));
    try std.testing.expectEqual(@as(u16, 0), alternate.cursor.row);
    try std.testing.expectEqual(@as(u16, 0), alternate.cursor.col);
}

test "DEC screen origin and autowrap modes own exact repeated command effects" {
    var terminal = try Terminal.init(std.testing.allocator, 4, 8);
    defer terminal.deinit();
    const screen = terminal.screen_state.active();

    try std.testing.expect((try terminal.feed("\x1b[1;8HX")).state_changed);
    try std.testing.expect(screen.wrap_pending);
    try std.testing.expect(!(try terminal.feed("\x1b[?7")).state_changed);
    try std.testing.expect((try terminal.feed("h")).state_changed);
    try std.testing.expect(!screen.wrap_pending);
    try std.testing.expect(!(try terminal.feed("\x1b[?7h")).state_changed);

    try std.testing.expect((try terminal.feed("\x1b[?5h")).state_changed);
    try std.testing.expect(terminal.modes.reverse_screen_mode);
    try std.testing.expect(!(try terminal.feed("\x1b[?5h")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?5l")).state_changed);
    try std.testing.expect(!terminal.modes.reverse_screen_mode);
    try std.testing.expect(!(try terminal.feed("\x1b[?5l")).state_changed);

    try std.testing.expect((try terminal.feed("\x1b[2;4r\x1b[?69h\x1b[3;6s\x1b[4;7H")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?6h")).state_changed);
    try std.testing.expect(screen.origin_mode);
    try std.testing.expectEqual(@as(u16, 1), screen.cursor.row);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor.col);
    try std.testing.expect(!(try terminal.feed("\x1b[?6h")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[2;2H\x1b[?6h")).state_changed);
    try std.testing.expectEqual(@as(u16, 1), screen.cursor.row);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor.col);
    try std.testing.expect((try terminal.feed("\x1b[?6l")).state_changed);
    try std.testing.expect(!screen.origin_mode);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor.row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor.col);
    try std.testing.expect(!(try terminal.feed("\x1b[?6l")).state_changed);

    try std.testing.expect((try terminal.feed("\x1b[?69l\x1b[?47h\x1b#6\x1b[?47l\x1b[?69h\x1b[?47h")).state_changed);
    const alternate = terminal.screen_state.active();
    try std.testing.expectEqual(.double_width, alternate.lineGeometry(0));
    try std.testing.expect((try terminal.feed("\x1b[?69h")).state_changed);
    try std.testing.expectEqual(.single_width, alternate.lineGeometry(0));
    try std.testing.expect(!(try terminal.feed("\x1b[?69h")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?47l\x1b[?69l")).state_changed);
    try std.testing.expectEqual(@as(u16, 0), screen.left_margin);
    try std.testing.expectEqual(@as(u16, 7), screen.right_margin);
    try std.testing.expect(!(try terminal.feed("\x1b[?69l")).state_changed);

    try std.testing.expect((try terminal.feed("\x1b[1;8HA\x1b[?7l")).state_changed);
    try std.testing.expect(!screen.auto_wrap);
    try std.testing.expect(!screen.wrap_pending);
    try std.testing.expect(!(try terminal.feed("\x1b[?7l")).state_changed);
    try std.testing.expect((try terminal.feed("B")).state_changed);
    try std.testing.expectEqual(@as(u21, 'B'), screen.cellAt(0, 7));
    try std.testing.expect((try terminal.feed("\x1b[?7h")).state_changed);
    try std.testing.expect(screen.auto_wrap);
    try std.testing.expect(!(try terminal.feed("\x1b[?7h")).state_changed);
}

test "application keypad modes affect keypad encoding and DECRQM" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try std.testing.expectEqualStrings("1", encodeKey(&terminal, .{ .named = .keypad_1 }, .{}));
    try std.testing.expectEqualStrings("\r", encodeKey(&terminal, .{ .named = .keypad_enter }, .{}));

    write(&stream, "\x1b=\x1b[?66$p");
    try std.testing.expectEqualStrings("\x1b[?66;1$y", pendingOutput(&terminal));
    try std.testing.expectEqualStrings("\x1bOq", encodeKey(&terminal, .{ .named = .keypad_1 }, .{}));
    try std.testing.expectEqualStrings("\x1bOM", encodeKey(&terminal, .{ .named = .keypad_enter }, .{}));

    write(&stream, "\x1b>");
    try std.testing.expectEqualStrings("1", encodeKey(&terminal, .{ .named = .keypad_1 }, .{}));
}

test "modifyOtherKeys set query disable and encoding" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try std.testing.expectEqualStrings("\x1ba", encodeKey(
        &terminal,
        try input_keyboard.InputKey.initUnicode('a'),
        .{ .alt = true },
    ));
    write(&stream, "\x1b[>4;2m\x1b[?4m");
    try std.testing.expectEqualStrings("\x1b[>4;2m", pendingOutput(&terminal));
    try std.testing.expectEqualStrings("\x1b[27;3;97~", encodeKey(&terminal, try input_keyboard.InputKey.initUnicode('a'), .{ .alt = true }));
    try std.testing.expectEqualStrings("a", encodeKey(&terminal, try input_keyboard.InputKey.initUnicode('a'), .{}));

    write(&stream, "\x1b[>4;3m");
    try std.testing.expectEqualStrings("\x1b[27;1;97~", encodeKey(&terminal, try input_keyboard.InputKey.initUnicode('a'), .{}));

    write(&stream, "\x1b[>4n");
    try std.testing.expectEqualStrings("\x1ba", encodeKey(
        &terminal,
        try input_keyboard.InputKey.initUnicode('a'),
        .{ .alt = true },
    ));
}

test "xterm key format query reset and other-key encoding" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    write(&stream, "\x1b[>4;1f\x1b[?4g\x1b[>4;1m");
    try std.testing.expectEqualStrings("\x1b[>4;1f", pendingOutput(&terminal));
    try std.testing.expectEqualStrings("\x1b[97;3u", encodeKey(&terminal, try input_keyboard.InputKey.initUnicode('a'), .{ .alt = true }));

    write(&stream, "\x1b[>4f\x1b[?4g");
    try std.testing.expectEqualStrings("\x1b[>4;1f\x1b[>4;0f", pendingOutput(&terminal));
}

test "low priority private modes and media copy retain host-neutral state" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    write(&stream, "\x1b[?45h\x1b[?1045h\x1b[?5i");
    try std.testing.expect(reverseWraparoundMode(&terminal));
    try std.testing.expect(extendedReverseWraparoundMode(&terminal));
    try std.testing.expectEqual(@as(?u16, 5), mediaCopyRequest(&terminal));

    write(&stream, "\x1b[?45l\x1b[?1045l");
    try std.testing.expect(!reverseWraparoundMode(&terminal));
    try std.testing.expect(!extendedReverseWraparoundMode(&terminal));
}

test "reverse wrap owns backspace margins phantom state query save and reset" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 5);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x08")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?45h\x1b[?1045h")).state_changed);
    try std.testing.expect((try terminal.feed("abcde")).state_changed);
    try std.testing.expect((try terminal.feed("\x08")).state_changed);
    try std.testing.expectEqual(@as(u16, 0), terminal.screen_state.activeConst().cursor.row);
    try std.testing.expectEqual(@as(u16, 4), terminal.screen_state.activeConst().cursor.col);
    try std.testing.expect((try terminal.feed("\x08")).state_changed);
    try std.testing.expectEqual(@as(u16, 3), terminal.screen_state.activeConst().cursor.col);

    terminal.hardReset();
    try std.testing.expect((try terminal.feed("abcdef\r")).state_changed);
    try std.testing.expect((try terminal.feed("\x08")).state_changed);
    try std.testing.expectEqual(@as(u16, 0), terminal.screen_state.activeConst().cursor.row);
    try std.testing.expectEqual(@as(u16, 4), terminal.screen_state.activeConst().cursor.col);

    terminal.hardReset();
    try std.testing.expect((try terminal.feed("\x1b[?69h\x1b[2;4s\x1b[?45h\x1b[2;2H")).state_changed);
    try std.testing.expect((try terminal.feed("\x08")).state_changed);
    try std.testing.expectEqual(@as(u16, 0), terminal.screen_state.activeConst().cursor.row);
    try std.testing.expectEqual(@as(u16, 3), terminal.screen_state.activeConst().cursor.col);
    try std.testing.expect((try terminal.feed("\x1b[2;4r\x1b[2;2H")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x08")).state_changed);
    try std.testing.expectEqual(@as(u16, 1), terminal.screen_state.activeConst().cursor.row);
    try std.testing.expectEqual(@as(u16, 1), terminal.screen_state.activeConst().cursor.col);

    terminal.hardReset();
    try std.testing.expect((try terminal.feed("abcdef\r\x1b[?69h\x1b[2;4s\x1b[2;2H")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x08")).state_changed);
    terminal.hardReset();
    try std.testing.expect((try terminal.feed("\x1b[?45h\x1b[?7l\x1b[2;1H")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x08")).state_changed);

    clearPendingOutput(&terminal);
    try std.testing.expect((try terminal.feed("\x1b[?45h\x1b[?1045h\x1b[?45;1045s")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?45l\x1b[?1045l")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?45$p\x1b[?1045$p")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?45;1045r\x1b[?45$p\x1b[?1045$p")).state_changed);
    try std.testing.expectEqualStrings(
        "\x1b[?45;2$y\x1b[?1045;2$y\x1b[?45;1$y\x1b[?1045;1$y",
        pendingOutput(&terminal),
    );

    try std.testing.expect((try terminal.feed("\x1b[!p")).state_changed);
    try std.testing.expect(!reverseWraparoundMode(&terminal));
    try std.testing.expect(!extendedReverseWraparoundMode(&terminal));
    try std.testing.expect(!(try terminal.feed("\x1b[!p")).state_changed);
}
