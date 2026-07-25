const std = @import("std");
const dcs_payload = @import("../../src/terminal.zig");
const selection = @import("../../src/terminal.zig");
const terminal_mod = @import("../../src/terminal.zig");
const input_encode = @import("../../src/terminal.zig");
const input_keyboard = @import("../../src/terminal.zig");
const input_mouse = @import("../../src/terminal.zig");
const parser_mod = @import("../../src/parser.zig");
const reply_fill = @import("../support/reply_fill.zig");
const stream_harness = @import("../support/stream_harness.zig");

const Terminal = terminal_mod.Terminal;
const Screen = terminal_mod.Screen;
const StreamHarness = stream_harness.Harness;

const expected_color_preference_query_capacity: u8 = 16;
const expected_window_request_capacity: u8 = 32;
const expected_metadata_bytes: usize = 1024;
const expected_reply_bytes: usize = 64 * 1024;

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

fn visibleView(terminal: *const Terminal, history_offset: u32) Terminal.SemanticView {
    return terminal.semanticView(history_offset);
}

fn write(stream: *StreamHarness, bytes: []const u8) void {
    stream.nextSlice(bytes) catch unreachable;
}

fn pendingOutput(terminal: *const Terminal) []const u8 {
    return terminal.replyBytes();
}

fn consumeReplies(terminal: *Terminal) !void {
    try terminal.consumeReplyBytes(terminal.replyBytes().len);
}

fn dcsPayloadKind(terminal: *Terminal) ?dcs_payload.DcsPayloadKind {
    if (terminal.consequenceHead()) |consequence| return consequence.dcs.kind;
    return null;
}

fn dcsPayload(terminal: *Terminal) ?[]const u8 {
    if (terminal.consequenceHead()) |consequence| return consequence.dcs.payload;
    return null;
}

fn reverseWraparoundMode(terminal: *const Terminal) bool {
    return terminal.modes.reverse_wraparound_mode;
}

fn extendedReverseWraparoundMode(terminal: *const Terminal) bool {
    return terminal.modes.extended_reverse_wraparound_mode;
}

test "encodeMouse returns empty output and does not mutate state" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 5, 10);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    write(&stream, "HELLO");

    const view_before = terminal.semanticView(0);
    const cursor_row_before = view_before.cursor_row;
    const cursor_col_before = view_before.cursor_col;
    const history_count_before = view_before.history_count;

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

    const view_after = terminal.semanticView(0);
    try std.testing.expectEqual(cursor_row_before, view_after.cursor_row);
    try std.testing.expectEqual(cursor_col_before, view_after.cursor_col);
    try std.testing.expectEqual(history_count_before, view_after.history_count);
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

test "legacy X10 mouse mode owns exact input query save and reset lifetime" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 5, 10);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    const press = input_mouse.MouseEvent{
        .kind = .press,
        .button = .left,
        .row = 2,
        .col = 3,
        .mod = .{ .shift = true, .alt = true },
        .buttons_down = 1,
    };
    const release = input_mouse.MouseEvent{
        .kind = .release,
        .button = .left,
        .row = 2,
        .col = 3,
        .mod = .{},
        .buttons_down = 0,
    };

    try std.testing.expect(!(try terminal.feed("\x1b[?9")).state_changed);
    try std.testing.expectEqualStrings("", encodeMouse(&terminal, press));
    try std.testing.expect((try terminal.feed("h")).state_changed);
    try std.testing.expectEqualStrings("\x1b[M $#", encodeMouse(&terminal, press));
    try std.testing.expectEqualStrings("", encodeMouse(&terminal, release));
    try std.testing.expectEqualStrings("", encodeMouse(&terminal, .{
        .kind = .press,
        .button = .left,
        .row = 223,
        .col = 0,
        .mod = .{},
        .buttons_down = 1,
    }));
    try std.testing.expect(!(try terminal.feed("\x1b[?9h")).state_changed);

    try stream.nextSlice("\x1b[?9$p");
    try std.testing.expectEqualStrings("\x1b[?9;1$y", pendingOutput(&terminal));
    try consumeReplies(&terminal);
    try stream.nextSlice("\x1b[?9s\x1b[?1000h\x1b[?9r\x1b[?9$p\x1b[?1000$p");
    try std.testing.expectEqualStrings("\x1b[?9;1$y\x1b[?1000;2$y", pendingOutput(&terminal));
    try consumeReplies(&terminal);

    try stream.nextSlice("\x1b[?1049h\x1b[?1049l");
    try terminal.resize(7, 12);
    try std.testing.expectEqualStrings("\x1b[M $#", encodeMouse(&terminal, press));
    try stream.nextSlice("\x1bc\x1b[?9$p");
    try std.testing.expectEqualStrings("\x1b[?9;2$y", pendingOutput(&terminal));
    try std.testing.expectEqualStrings("", encodeMouse(&terminal, press));
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
    try consumeReplies(&terminal);

    try std.testing.expect(!(try terminal.feed("\x1b[=127;1")).state_changed);
    try std.testing.expect((try terminal.feed("u")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b[=127u")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b[?")).state_changed);
    try std.testing.expect((try terminal.feed("u")).state_changed);
    try std.testing.expectEqualStrings("\x1b[?127u", pendingOutput(&terminal));
    try consumeReplies(&terminal);

    try std.testing.expect((try terminal.feed("\x1b[=8;3u\x1b[=3;2u\x1b[?u")).state_changed);
    try std.testing.expectEqualStrings("\x1b[?119u", pendingOutput(&terminal));
    try consumeReplies(&terminal);

    try std.testing.expect((try terminal.feed(
        "\x1b[>1u\x1b[>2u\x1b[>3u\x1b[>4u\x1b[>5u\x1b[>6u\x1b[>7u\x1b[>8u",
    )).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[<7u\x1b[?u")).state_changed);
    try std.testing.expectEqualStrings("\x1b[?1u", pendingOutput(&terminal));
    try consumeReplies(&terminal);

    try std.testing.expect((try terminal.feed("\x1b[<u\x1b[?u")).state_changed);
    try std.testing.expectEqualStrings("\x1b[?0u", pendingOutput(&terminal));
    try consumeReplies(&terminal);
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
    try consumeReplies(&terminal);
    write(&stream, "\x1b[?1049l");
    write(&stream, "\x1b[?u");
    try std.testing.expectEqualStrings("\x1b[?1u", pendingOutput(&terminal));
    try consumeReplies(&terminal);

    write(&stream, "\x1b[?1049h\x1b[=7u\x1bc\x1b[?u");
    try std.testing.expectEqualStrings("\x1b[?0u", pendingOutput(&terminal));
    try consumeReplies(&terminal);
    write(&stream, "\x1b[?1049h\x1b[?u");
    try std.testing.expectEqualStrings("\x1b[?0u", pendingOutput(&terminal));
}

test "kitty keyboard query preserves full pending output on failure" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    const fill_len = expected_reply_bytes - 4;
    const fill = try reply_fill.fill(&terminal, allocator, fill_len, false);
    defer allocator.free(fill);

    try std.testing.expectError(error.ConsequenceLimit, terminal.feed("\x1b[?u"));
    try std.testing.expectEqual(fill_len, pendingOutput(&terminal).len);
    try std.testing.expectEqualSlices(u8, fill, pendingOutput(&terminal));
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
    const oversized = @as([(input_keyboard.max_text_bytes + 1)]u8, @splat('a'));
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

    try consumeReplies(&terminal);
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
    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed("\x1b[?8$p")).state_changed);
    try std.testing.expectEqualStrings("\x1b[?8;1$y", pendingOutput(&terminal));
}

test "Kitty parameterless mode save restores the exact curated mode set" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 4);
    defer terminal.deinit();

    const enable =
        "\x1b[20h\x1b[4h" ++
        "\x1b[?8l\x1b[?2004h\x1b[?1004h\x1b[?2031h\x1b[?5522h\x1b[?2048h" ++
        "\x1b[?1h\x1b[?25l\x1b[?7l\x1b[?1003h\x1b[?1006h\x1b[?5h";
    try std.testing.expect((try terminal.feed(enable)).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b[?")).state_changed);
    try std.testing.expect((try terminal.feed("s")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b[?s")).state_changed);

    const invert =
        "\x1b[20l\x1b[4l" ++
        "\x1b[?8h\x1b[?2004l\x1b[?1004l\x1b[?2031l\x1b[?5522l\x1b[?2048l" ++
        "\x1b[?1l\x1b[?25h\x1b[?7h\x1b[?1003l\x1b[?1006l\x1b[?5l";
    try std.testing.expect((try terminal.feed(invert)).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b[?")).state_changed);
    try std.testing.expect((try terminal.feed("r")).state_changed);

    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed(
        "\x1b[20$p\x1b[4$p" ++
            "\x1b[?8$p\x1b[?2004$p\x1b[?1004$p\x1b[?2031$p\x1b[?5522$p\x1b[?2048$p" ++
            "\x1b[?1$p\x1b[?25$p\x1b[?7$p\x1b[?1003$p\x1b[?1006$p\x1b[?5$p",
    )).state_changed);
    try std.testing.expectEqualStrings(
        "\x1b[20;1$y\x1b[4;1$y" ++
            "\x1b[?8;2$y\x1b[?2004;1$y\x1b[?1004;1$y\x1b[?2031;1$y" ++
            "\x1b[?5522;1$y\x1b[?2048;1$y\x1b[?1;1$y\x1b[?25;2$y" ++
            "\x1b[?7;2$y\x1b[?1003;1$y\x1b[?1006;1$y\x1b[?5;1$y",
        pendingOutput(&terminal),
    );
    try consumeReplies(&terminal);
    try std.testing.expect(!(try terminal.feed("\x1b[?r")).state_changed);

    try std.testing.expect((try terminal.feed("\x1bc")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?r")).state_changed);
    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed("\x1b[?8$p\x1b[?25$p\x1b[?7$p")).state_changed);
    try std.testing.expectEqualStrings(
        "\x1b[?8;2$y\x1b[?25;2$y\x1b[?7;2$y",
        pendingOutput(&terminal),
    );
}

test "individual DEC mode saves retain every implemented mode without saturation" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 4);
    defer terminal.deinit();

    const modes = [_]u16{
        1,    3,    5,    6,    7,    8,    9,    12,   25,   45,
        47,   66,   69,   1045, 1047, 1049, 1000, 1002, 1003, 1004,
        1005, 1006, 1015, 1016, 2004, 2026, 2031, 2048, 5522,
    };
    var changed_count: usize = 0;
    for (modes) |mode| {
        var bytes: [24]u8 = undefined;
        const command = try std.fmt.bufPrint(&bytes, "\x1b[?{d}s", .{mode});
        const first = try terminal.feed(command);
        changed_count += @intFromBool(first.state_changed);
        const second = try terminal.feed(command);
        try std.testing.expect(!second.state_changed);
    }
    try std.testing.expectEqual(@as(usize, 4), changed_count);
    try std.testing.expect(!(try terminal.feed("\x1b[?9999s\x1b[?9999r")).state_changed);

    try std.testing.expect((try terminal.feed("\x1b[?5522h\x1b[?5522r")).state_changed);
    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed("\x1b[?5522$p")).state_changed);
    try std.testing.expectEqualStrings("\x1b[?5522;2$y", pendingOutput(&terminal));

    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed("\x1b[?1;7;25h")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b[?1;7;25h")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?1;7;25l")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b[?1;7;25l")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?1$p\x1b[?7$p\x1b[?25$p")).state_changed);
    try std.testing.expectEqualStrings("\x1b[?1;2$y\x1b[?7;2$y\x1b[?25;2$y", pendingOutput(&terminal));
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

test "Kitty host-coordinated modes retain exact state reports and color notifications" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.reportColorSchemePreference(.dark)));
    try std.testing.expectEqualStrings("", pendingOutput(&terminal));

    try std.testing.expect((try terminal.feed("\x1b[?2031h\x1b[?5522h")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b[?199")).state_changed);
    try std.testing.expect((try terminal.feed("97h")).state_changed);
    try std.testing.expect(terminal.colorPreferenceNotifications());
    try std.testing.expect(terminal.pasteEvents());
    try std.testing.expect(terminal.termiosSignals());
    try std.testing.expect(!(try terminal.feed("\x1b[?2031h\x1b[?5522h\x1b[?19997h")).state_changed);

    try std.testing.expect((try terminal.feed("\x1b[?2031$p\x1b[?5522$p\x1b[?19997$p")).state_changed);
    try std.testing.expectEqualStrings(
        "\x1b[?2031;1$y\x1b[?5522;1$y\x1b[?19997;0$y",
        pendingOutput(&terminal),
    );
    try consumeReplies(&terminal);

    try std.testing.expect((try terminal.feed("\x1b G")).state_changed);
    try std.testing.expect(try terminal.reportColorSchemePreference(.dark));
    try std.testing.expect(try terminal.reportColorSchemePreference(.light));
    try std.testing.expectEqualStrings("\x1b[?997;1n\x1b[?997;2n", pendingOutput(&terminal));
    try consumeReplies(&terminal);

    try std.testing.expect((try terminal.feed("\x1b[?2031;5522;19997s")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?2031l\x1b[?5522l\x1b[?19997l")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?2031;5522;19997r")).state_changed);
    try std.testing.expect(terminal.colorPreferenceNotifications());
    try std.testing.expect(terminal.pasteEvents());
    try std.testing.expect(!terminal.termiosSignals());

    const fill = try reply_fill.fill(&terminal, allocator, expected_reply_bytes, false);
    defer allocator.free(fill);
    try std.testing.expectError(error.ConsequenceLimit, terminal.reportColorSchemePreference(.dark));
    try std.testing.expectEqual(fill.len, pendingOutput(&terminal).len);
    try std.testing.expect(terminal.colorPreferenceNotifications());

    try std.testing.expect((try terminal.feed("\x1bc")).state_changed);
    try std.testing.expect(!terminal.colorPreferenceNotifications());
    try std.testing.expect(!terminal.pasteEvents());
    try std.testing.expect(!terminal.termiosSignals());
}

test "Kitty color-preference queries retain ordered intent and transactional replies" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b[?99")).state_changed);
    try std.testing.expect((try terminal.feed("6n\x9b?996n")).state_changed);
    try std.testing.expectEqual(@as(u8, 2), terminal.consequenceCount());
    try std.testing.expectEqual(@as(u64, 1), terminal.consequenceHead().?.color_preference_query.id);
    try std.testing.expectError(
        error.StaleColorPreferenceQuery,
        terminal.replyColorPreference(2, .dark),
    );

    const fill = try reply_fill.fill(&terminal, allocator, expected_reply_bytes, false);
    defer allocator.free(fill);
    try std.testing.expectError(
        error.ConsequenceLimit,
        terminal.replyColorPreference(1, .dark),
    );
    try std.testing.expectEqualSlices(u8, fill, pendingOutput(&terminal));
    try std.testing.expectEqual(@as(u64, 1), terminal.consequenceHead().?.color_preference_query.id);

    try consumeReplies(&terminal);
    try terminal.replyColorPreference(1, .dark);
    try std.testing.expectEqualStrings("\x1b[?997;1n", pendingOutput(&terminal));
    try std.testing.expectEqual(@as(u64, 2), terminal.consequenceHead().?.color_preference_query.id);
    try std.testing.expectEqual(@as(u8, 1), terminal.consequenceCount());

    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed("\x1bc\x1b G\x1b[?1049h\x1b[?1049l")).state_changed);
    try terminal.resize(4, 10);
    try terminal.replyColorPreference(2, .light);
    try std.testing.expectEqualStrings("\x1b[?997;2n", pendingOutput(&terminal));
    try std.testing.expect(terminal.consequenceHead() == null);

    try consumeReplies(&terminal);
    for (0..expected_color_preference_query_capacity) |_| {
        try std.testing.expect((try terminal.feed("\x1b[?996n")).state_changed);
    }
    try std.testing.expectEqual(expected_color_preference_query_capacity, terminal.consequenceCount());
    const head_before_full = terminal.consequenceHead().?.color_preference_query.id;
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed("\x1b[?996n"));
    try std.testing.expectEqual(head_before_full, terminal.consequenceHead().?.color_preference_query.id);
    try std.testing.expectEqual(expected_color_preference_query_capacity, terminal.consequenceCount());

    for (0..expected_color_preference_query_capacity) |offset| {
        const generation = terminal.consequenceHead().?.color_preference_query.id;
        try std.testing.expectEqual(head_before_full + @as(u64, @intCast(offset)), generation);
        try terminal.replyColorPreference(generation, .dark);
        try consumeReplies(&terminal);
    }
    try std.testing.expect(terminal.consequenceHead() == null);
    try std.testing.expect(!(try terminal.feed("\x1b[?996;1n")).state_changed);
    try std.testing.expect(terminal.consequenceHead() == null);
    try std.testing.expectError(
        error.StaleColorPreferenceQuery,
        terminal.replyColorPreference(head_before_full - 1, .dark),
    );
}

test "iTerm2 host-coordinated input modes retain reports and terminal lifetime" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect(!terminal.alternateScroll());
    try std.testing.expect(!terminal.metaSendsEscape());
    try std.testing.expect(!terminal.reportKeyUp());

    try std.testing.expect(!(try terminal.feed("\x1b[?100")).state_changed);
    try std.testing.expect((try terminal.feed("7h\x1b[?1036h\x1b[?1337h")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b[?1007h\x1b[?1036h\x1b[?1337h")).state_changed);
    try std.testing.expect(terminal.alternateScroll());
    try std.testing.expect(terminal.metaSendsEscape());
    try std.testing.expect(terminal.reportKeyUp());

    var scratch: Terminal.InputScratch = .{};
    var meta = try terminal.encodeInput(allocator, &scratch, .{ .key = .{
        .key = try Terminal.Key.initUnicode('é'),
        .mods = .{ .alt = true },
        .legacy_text = "é",
    } });
    defer meta.deinit();
    try std.testing.expectEqualStrings("\x1bé", meta.bytes);
    var plain = try terminal.encodeInput(allocator, &scratch, .{ .key = .{
        .key = try Terminal.Key.initUnicode('é'),
        .legacy_text = "é",
    } });
    defer plain.deinit();
    try std.testing.expectEqualStrings("é", plain.bytes);
    const oversized = @as([@sizeOf(Terminal.InputScratch)]u8, @splat('x'));
    try std.testing.expectError(error.KeyTextLimit, terminal.encodeInput(
        allocator,
        &scratch,
        .{ .key = .{
            .key = try Terminal.Key.initUnicode('x'),
            .mods = .{ .alt = true },
            .legacy_text = &oversized,
        } },
    ));

    try std.testing.expect((try terminal.feed("\x1b[?1007$p\x1b[?1036$p\x1b[?1337$p")).state_changed);
    try std.testing.expectEqualStrings(
        "\x1b[?1007;1$y\x1b[?1036;1$y\x1b[?1337;1$y",
        pendingOutput(&terminal),
    );
    try consumeReplies(&terminal);

    try std.testing.expect((try terminal.feed("\x1b[?1047h")).state_changed);
    try terminal.resize(4, 10);
    try std.testing.expect(terminal.alternateScroll());
    try std.testing.expect(terminal.metaSendsEscape());
    try std.testing.expect(terminal.reportKeyUp());

    try std.testing.expect((try terminal.feed("\x1b[?1036l\x1b[?1036$p")).state_changed);
    try std.testing.expectEqualStrings("\x1b[?1036;2$y", pendingOutput(&terminal));
    try consumeReplies(&terminal);
    var disabled = try terminal.encodeInput(allocator, &scratch, .{ .key = .{
        .key = try Terminal.Key.initUnicode('a'),
        .mods = .{ .alt = true },
        .legacy_text = "a",
    } });
    defer disabled.deinit();
    try std.testing.expectEqualStrings("a", disabled.bytes);

    try std.testing.expect((try terminal.feed("\x1bc")).state_changed);
    try std.testing.expect(!terminal.alternateScroll());
    try std.testing.expect(!terminal.metaSendsEscape());
    try std.testing.expect(!terminal.reportKeyUp());
}

test "input mode category preserves encoding gates screen stacks and reset lifetime" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var scratch: Terminal.InputScratch = .{};

    try std.testing.expect(!(try terminal.feed("\x1b[?1")).state_changed);
    try std.testing.expect((try terminal.feed("h\x1b=\x1b[?1004h\x1b[?1003h\x1b[?1016h\x1b[?2004h\x1b[?8l")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b[?1h\x1b=\x1b[?1004h\x1b[?1003h\x1b[?1016h\x1b[?2004h\x1b[?8l")).state_changed);
    try std.testing.expectEqualStrings("\x1bOA", encodeKey(&terminal, .{ .named = .up }, .{}));
    try std.testing.expectEqualStrings("\x1bOk", encodeKey(&terminal, .{ .named = .keypad_add }, .{}));
    try std.testing.expectEqualStrings("\x1b[I", encodeFocusIn(&terminal));
    try std.testing.expectEqualStrings("\x1b[O", encodeFocusOut(&terminal));
    try std.testing.expectEqualStrings("\x1b[<16;320;240M", encodeMouse(&terminal, .{
        .kind = .press,
        .button = .left,
        .row = 1,
        .col = 2,
        .pixel_x = 319,
        .pixel_y = 239,
        .mod = .{ .control = true },
        .buttons_down = 1,
    }));

    var paste = try terminal.encodeInput(allocator, &scratch, .{ .paste = "x\x00y" });
    defer paste.deinit();
    try std.testing.expectEqualStrings("\x1b[200~x\x00y\x1b[201~", paste.bytes);
    var repeat = try terminal.encodeInput(allocator, &scratch, .{ .key = .{
        .key = try Terminal.Key.initUnicode('a'),
        .action = .repeat,
        .legacy_text = "a",
    } });
    defer repeat.deinit();
    try std.testing.expectEqualStrings("", repeat.bytes);

    try std.testing.expect(!(try terminal.feed("\x1b[=3")).state_changed);
    try std.testing.expect((try terminal.feed("u")).state_changed);
    var release = try terminal.encodeInput(allocator, &scratch, .{ .key = .{
        .key = try Terminal.Key.initUnicode('a'),
        .action = .release,
    } });
    defer release.deinit();
    try std.testing.expectEqualStrings("\x1b[97;1:3u", release.bytes);

    try std.testing.expect((try terminal.feed("\x1b[?1049h")).state_changed);
    var alternate_release = try terminal.encodeInput(allocator, &scratch, .{ .key = .{
        .key = try Terminal.Key.initUnicode('a'),
        .action = .release,
    } });
    defer alternate_release.deinit();
    try std.testing.expectEqualStrings("", alternate_release.bytes);
    try std.testing.expect((try terminal.feed("\x1b[?1049l\x1bc")).state_changed);
    try std.testing.expectEqualStrings("\x1b[A", encodeKey(&terminal, .{ .named = .up }, .{}));
    try std.testing.expectEqualStrings("+", encodeKey(&terminal, .{ .named = .keypad_add }, .{}));
    try std.testing.expectEqualStrings("", encodeFocusIn(&terminal));
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

    try consumeReplies(&terminal);
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

    try consumeReplies(&terminal);
    write(&stream, "\x1b[2;5r\x1b[?69h\x1b[3;8s\x1b[?6h\x1b[2;3H\x1b[6n\x1b[?5n\x1b[?6n");
    try std.testing.expectEqualStrings("\x1b[2;3R\x1b[0n\x1b[?2;3R", pendingOutput(&terminal));
    const view = visibleView(&terminal, 0);
    try std.testing.expectEqual(@as(u16, 2), view.cursor_row);
    try std.testing.expectEqual(@as(u16, 4), view.cursor_col);

    try consumeReplies(&terminal);
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

    const fill_len = expected_reply_bytes - 3;
    const fill = try reply_fill.fill(&terminal, allocator, fill_len, false);
    defer allocator.free(fill);

    try std.testing.expectError(error.ConsequenceLimit, stream.nextSlice("\x1b[5n"));
    try std.testing.expectEqual(fill_len, pendingOutput(&terminal).len);

    try consumeReplies(&terminal);
    try stream.nextSlice("\x1b[");
    try stream.nextSlice("5n");
    try std.testing.expectEqualStrings("\x1b[0n", pendingOutput(&terminal));

    try consumeReplies(&terminal);
    const refill = try reply_fill.fill(&terminal, allocator, fill_len, false);
    defer allocator.free(refill);
    try std.testing.expectError(error.ConsequenceLimit, stream.nextSlice("\x1bP$qr\x1b\\"));
    try std.testing.expectEqual(fill_len, pendingOutput(&terminal).len);

    try consumeReplies(&terminal);
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
    try consumeReplies(&terminal);
    try stream.nextSlice("\x1b ");
    try stream.nextSlice("G\x1b[5n\x1bP$qr\x1b\\\x1b]4;1;?\x1b\\\x1b[?u\x1b]1337;ReportCellSize\x07");
    try std.testing.expectEqualStrings(
        "\x9b0n\x901$r1;3r\x9c\x9d4;1;rgb:0101/0202/0303\x9c" ++
            "\x1b[?0u\x1b]1337;ReportCellSize=18;9;1\x1b\\",
        pendingOutput(&terminal),
    );

    try consumeReplies(&terminal);
    write(&stream, "\x1b7");
    try stream.nextSlice("\x1b ");
    try stream.nextSlice("F\x1b8\x1b[5n");
    try std.testing.expectEqualStrings("\x1b[0n", pendingOutput(&terminal));

    try consumeReplies(&terminal);
    write(&stream, "\x1b G\x1bc\x1b[5n");
    try std.testing.expectEqualStrings("\x1b[0n", pendingOutput(&terminal));
}

test "fragmented mixed report families preserve order and per-query rollback" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    try terminal.setCellPixelSize(9, 18);

    write(&stream, "\x1b[2;3H\x1b G");
    try consumeReplies(&terminal);
    const request =
        "\x1bZ\x9b?c\x9b=c\x9b5n\x9b6n\x9b?6n\x9b?7$p\x9b4$p" ++
        "\x90$qr\x9c\x90+q436f\x9c\x9b>0q\x9b18t" ++
        "\x9d1337;ReportCellSize\x9c";
    var offset: usize = 0;
    var completed_queries: usize = 0;
    while (offset < request.len) : (offset += 1) {
        const summary = try terminal.feed(request[offset .. offset + 1]);
        if (summary.state_changed) completed_queries += 1;
    }
    try std.testing.expectEqual(@as(usize, 12), completed_queries);
    try std.testing.expectEqualStrings(
        "\x9b?62;22c\x90!|00000000\x9c" ++
            "\x9b0n\x9b2;3R\x9b?2;3R\x9b?7;1$y\x9b4;2$y" ++
            "\x901$r1;4r\x9c\x901+r436f=323536\x9c" ++
            "\x90>|howl-vt dev\x9c\x9b8;4;8t" ++
            "\x1b]1337;ReportCellSize=18;9;1\x1b\\",
        pendingOutput(&terminal),
    );

    try consumeReplies(&terminal);
    const fill = try reply_fill.fill(&terminal, allocator, expected_reply_bytes - 6, true);
    defer allocator.free(fill);
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed("\x9b5n\x9b6n"));
    try std.testing.expectEqual(fill.len + 3, pendingOutput(&terminal).len);
    try std.testing.expectEqualSlices(u8, fill, pendingOutput(&terminal)[0..fill.len]);
    try std.testing.expectEqualStrings("\x9b0n", pendingOutput(&terminal)[fill.len..]);
}

test "terminal size reports use exact current cell and pixel facts" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 5);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b[1");
    try stream.nextSlice("8t");
    try std.testing.expectEqualStrings("\x1b[8;3;5t", pendingOutput(&terminal));

    try consumeReplies(&terminal);
    try std.testing.expect(!(try terminal.feed("\x1b[14t\x1b[16t")).state_changed);
    try std.testing.expectEqualStrings("", pendingOutput(&terminal));

    try terminal.setCellPixelSize(9, 17);
    try terminal.resize(4, 7);
    try consumeReplies(&terminal);
    try stream.nextSlice("\x1b G\x9b14");
    try stream.nextSlice(";0t\x9b16;0t\x9b18;0t");
    try std.testing.expectEqualStrings(
        "\x9b4;68;63t\x9b6;17;9t\x9b8;4;7t",
        pendingOutput(&terminal),
    );

    try consumeReplies(&terminal);
    try stream.nextSlice("\x1bc");
    try stream.nextSlice("\x1b[14;2t\x1b[16t\x1b[18t");
    try std.testing.expectEqualStrings(
        "\x1b[4;68;63t\x1b[6;17;9t\x1b[8;4;7t",
        pendingOutput(&terminal),
    );

    try consumeReplies(&terminal);
    try stream.nextSlice("\x1b[14;0;0t\x1b[16;-1t\x1b[19t");
    try std.testing.expectEqualStrings("", pendingOutput(&terminal));

    const fill = try reply_fill.fill(&terminal, allocator, expected_reply_bytes - 1, false);
    defer allocator.free(fill);
    try std.testing.expectError(error.ConsequenceLimit, stream.nextSlice("\x1b[18t"));
    try std.testing.expectEqualSlices(u8, fill, pendingOutput(&terminal));
}

test "window controls retain ordered bounded host requests and lifetime" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 5);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed(
        "\x1b[3;2147483647;42t\x1b[8;80;132t\x1b[11t\x1b[13t",
    )).state_changed);
    try std.testing.expectEqual(@as(u8, 4), terminal.consequenceCount());
    var occurrence = terminal.consequenceHead().?.window;
    try std.testing.expectEqual(@as(u64, 1), occurrence.generation);
    switch (occurrence.request) {
        .move => |position| {
            try std.testing.expectEqual(@as(u32, 2147483647), position.x);
            try std.testing.expectEqual(@as(u32, 42), position.y);
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectError(error.StaleConsequence, terminal.consumeConsequence(2));
    try std.testing.expectError(
        error.WindowReplyMismatch,
        terminal.replyWindow(1, .{ .position = .{ .x = 1, .y = 2 } }),
    );
    try terminal.consumeConsequence(1);

    occurrence = terminal.consequenceHead().?.window;
    try std.testing.expectEqual(@as(u64, 2), occurrence.generation);
    switch (occurrence.request) {
        .resize_cells => |size| {
            try std.testing.expectEqual(@as(u32, 80), size.rows);
            try std.testing.expectEqual(@as(u32, 132), size.cols);
        },
        else => return error.TestUnexpectedResult,
    }
    try terminal.consumeConsequence(2);
    try std.testing.expectError(error.ReplyRequired, terminal.consumeConsequence(3));
    try terminal.replyWindow(3, .{ .state = .normal });
    try consumeReplies(&terminal);
    occurrence = terminal.consequenceHead().?.window;
    try std.testing.expectEqual(@as(u64, 4), occurrence.generation);
    try std.testing.expectEqual(.report_position, std.meta.activeTag(occurrence.request));
    try std.testing.expectEqual(@as(u8, 1), terminal.consequenceCount());
    try terminal.replyWindow(4, .{ .position = .{ .x = 9, .y = 7 } });
    try consumeReplies(&terminal);
    try std.testing.expect(terminal.consequenceHead() == null);

    // Consume enough entries to wrap the fixed ring, then fill it exactly.
    for (0..20) |_| {
        try std.testing.expect((try terminal.feed("\x1b[1t")).state_changed);
        try terminal.consumeConsequence(terminal.consequenceHead().?.window.generation);
    }
    for (0..expected_window_request_capacity) |index| {
        const x: u32 = @intCast(index + 1);
        var bytes: [32]u8 = undefined;
        const request = try std.fmt.bufPrint(&bytes, "\x1b[3;{d};{d}t", .{ x, x + 100 });
        try std.testing.expect((try terminal.feed(request)).state_changed);
    }
    try std.testing.expectEqual(expected_window_request_capacity, terminal.consequenceCount());
    const head_before_full = terminal.consequenceHead().?.window;
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed("\x1b[2t"));
    try std.testing.expectEqual(
        head_before_full.generation,
        terminal.consequenceHead().?.window.generation,
    );
    for (0..expected_window_request_capacity) |index| {
        occurrence = terminal.consequenceHead().?.window;
        const x: u32 = @intCast(index + 1);
        switch (occurrence.request) {
            .move => |position| {
                try std.testing.expectEqual(x, position.x);
                try std.testing.expectEqual(x + 100, position.y);
            },
            else => return error.TestUnexpectedResult,
        }
        try terminal.consumeConsequence(occurrence.generation);
    }
    try std.testing.expect(terminal.consequenceHead() == null);

    try std.testing.expect(
        !(try terminal.feed("\x1b[4;10t\x1b[8;10;20;30t\x1b[3;-1;2t")).state_changed,
    );
    try std.testing.expect(!(try terminal.feed("\x1b[4;10")).state_changed);
    try std.testing.expect((try terminal.feed("\x18;20t")).state_changed);
    try std.testing.expect(terminal.consequenceHead() == null);

    try std.testing.expect((try terminal.feed("\x1b[2t")).state_changed);
    try std.testing.expect((try terminal.feed("\x1bc\x1b[?1049h\x1b[?1049l")).state_changed);
    try terminal.resize(4, 7);
    occurrence = terminal.consequenceHead().?.window;
    try std.testing.expectEqual(.iconify, std.meta.activeTag(occurrence.request));
}

test "iTerm2 window operations retain exact bounded host intent" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 5);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    const first = "\x1b[1t\x9b2t\x1b[3;2147483647;";
    const second = "0t\x1b[4;42;84t\x1b[5t\x9b6t\x1b[8;100;200t\x1b[3t";
    try stream.nextSlice(first);
    try std.testing.expectEqual(@as(u8, 2), terminal.consequenceCount());
    try stream.nextSlice(second);

    const expected = [_]terminal_mod.WindowRequest{
        .deiconify,
        .iconify,
        .{ .move = .{ .x = 2147483647, .y = 0 } },
        .{ .resize_pixels = .{ .height = 42, .width = 84 } },
        .raise,
        .lower,
        .{ .resize_cells = .{ .rows = 100, .cols = 200 } },
        .{ .move = .{ .x = 0, .y = 0 } },
    };
    try std.testing.expectEqual(@as(u8, expected.len), terminal.consequenceCount());

    // Repetition creates new ordered occurrences; terminal-state lifetime never consumes host intent.
    try stream.nextSlice(first);
    try stream.nextSlice(second);
    try std.testing.expectEqual(@as(u8, expected.len * 2), terminal.consequenceCount());
    try std.testing.expect((try terminal.feed("\x1bc\x1b[?1049h\x1b[?1049l")).state_changed);
    try terminal.resize(4, 7);
    for (0..2) |repetition| {
        for (expected, 1..) |request, offset| {
            const occurrence = terminal.consequenceHead().?.window;
            const generation = repetition * expected.len + offset;
            try std.testing.expectEqual(@as(u64, @intCast(generation)), occurrence.generation);
            try std.testing.expectEqualDeep(request, occurrence.request);
            try terminal.consumeConsequence(occurrence.generation);
        }
    }

    // The shared FIFO bound rejects the whole next occurrence without changing identity or queue state.
    for (0..expected_window_request_capacity) |_| try stream.nextSlice("\x1b[1t");
    const count_before_rejection = terminal.consequenceCount();
    const head_before_rejection = terminal.consequenceHead().?.window;
    const sequence_before_rejection = terminal.semanticSequence();
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed("\x1b[6t"));
    try std.testing.expectEqual(count_before_rejection, terminal.consequenceCount());
    try std.testing.expectEqualDeep(head_before_rejection, terminal.consequenceHead().?.window);
    try std.testing.expectEqual(sequence_before_rejection, terminal.semanticSequence());
    for (0..expected_window_request_capacity) |_| {
        const occurrence = terminal.consequenceHead().?.window;
        try std.testing.expectEqual(.deiconify, std.meta.activeTag(occurrence.request));
        try terminal.consumeConsequence(occurrence.generation);
    }

    try std.testing.expect(!(try terminal.feed(
        "\x1b[1;0t\x1b[2;0t\x1b[3;-1;2t\x1b[5;0t\x1b[6;0t\x1b[8;1t",
    )).state_changed);
    try std.testing.expect(terminal.consequenceHead() == null);
}

test "application resize requests retain exact ordered host intent" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 24, 80);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b[4;2147483647;");
    try std.testing.expect(terminal.consequenceHead() == null);
    try stream.nextSlice("0t\x9b8;0;2147483647t\x1b[4;7;9t");
    try std.testing.expectEqual(@as(u8, 3), terminal.consequenceCount());

    const expected = [_]terminal_mod.WindowRequest{
        .{ .resize_pixels = .{ .height = 2147483647, .width = 0 } },
        .{ .resize_cells = .{ .rows = 0, .cols = 2147483647 } },
        .{ .resize_pixels = .{ .height = 7, .width = 9 } },
    };
    for (expected, 1..) |request, generation| {
        const occurrence = terminal.consequenceHead().?.window;
        try std.testing.expectEqual(@as(u64, @intCast(generation)), occurrence.generation);
        try std.testing.expectEqualDeep(request, occurrence.request);
        try terminal.consumeConsequence(occurrence.generation);
    }
    try std.testing.expect(terminal.consequenceHead() == null);

    // Repeated occurrences remain distinct, and terminal state lifetime does not consume host intent.
    try stream.nextSlice("\x1b[8;12;34t\x1b[8;12;34t");
    try std.testing.expectEqual(@as(u8, 2), terminal.consequenceCount());
    try std.testing.expect((try terminal.feed("\x1bc\x1b[?1049h\x1b[?1049l")).state_changed);
    try terminal.resize(30, 100);
    for (4..6) |generation| {
        const occurrence = terminal.consequenceHead().?.window;
        try std.testing.expectEqual(@as(u64, @intCast(generation)), occurrence.generation);
        try std.testing.expectEqual(@as(u32, 12), occurrence.request.resize_cells.rows);
        try std.testing.expectEqual(@as(u32, 34), occurrence.request.resize_cells.cols);
        try terminal.consumeConsequence(occurrence.generation);
    }

    try std.testing.expect(!(try terminal.feed(
        "\x1b[4;1t\x1b[4;-1;2t\x1b[4;1;2;3t\x1b[8;1t\x1b[8;1;-2t\x1b[8;1;2;3t",
    )).state_changed);
    try std.testing.expect(terminal.consequenceHead() == null);
}

test "DEC cell dimension requests retain exact ordered host intent" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 24, 80);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b[40*");
    try stream.nextSlice("|\x9b132$|\x1b[$|\x1b[0$|\x1b[80$|\x1b[255*|");
    try std.testing.expectEqual(@as(u8, 6), terminal.consequenceCount());

    const expected = [_]terminal_mod.WindowRequest{
        .{ .resize_rows = 40 },
        .{ .resize_columns = .columns_132 },
        .{ .resize_columns = .columns_80 },
        .{ .resize_columns = .columns_80 },
        .{ .resize_columns = .columns_80 },
        .{ .resize_rows = 255 },
    };
    for (expected, 1..) |wanted, generation| {
        const occurrence = terminal.consequenceHead().?.window;
        try std.testing.expectEqual(@as(u64, @intCast(generation)), occurrence.generation);
        try std.testing.expectEqualDeep(wanted, occurrence.request);
        try terminal.consumeConsequence(occurrence.generation);
    }
    try std.testing.expect(terminal.consequenceHead() == null);

    try std.testing.expect(!(try terminal.feed(
        "\x1b[*|\x1b[0*|\x1b[256*|\x1b[42;1*|\x1b[81$|\x1b[80;1$|",
    )).state_changed);
    try std.testing.expect(terminal.consequenceHead() == null);
}

test "window query replies require matching live intent and serialize transactionally" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 5);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b[11t\x1b[13t")).state_changed);
    try std.testing.expectEqual(@as(u8, 2), terminal.consequenceCount());
    try std.testing.expectError(
        error.StaleWindowRequest,
        terminal.replyWindow(2, .{ .state = .normal }),
    );
    try std.testing.expectError(
        error.WindowReplyMismatch,
        terminal.replyWindow(1, .{ .position = .{ .x = 1, .y = 2 } }),
    );
    try std.testing.expectEqualStrings("", pendingOutput(&terminal));
    const sequence_before_reply = terminal.semanticSequence();
    try terminal.replyWindow(1, .{ .state = .iconified });
    try std.testing.expectEqualStrings("\x1b[2t", pendingOutput(&terminal));
    try std.testing.expect(terminal.semanticSequence() != sequence_before_reply);
    try std.testing.expectEqual(@as(u64, 2), terminal.consequenceHead().?.window.generation);
    try std.testing.expectEqual(@as(u8, 1), terminal.consequenceCount());
    try std.testing.expectError(
        error.StaleWindowRequest,
        terminal.replyWindow(1, .{ .state = .normal }),
    );

    try consumeReplies(&terminal);
    try terminal.replyWindow(2, .{ .position = .{ .x = std.math.maxInt(u32), .y = 42 } });
    try std.testing.expectEqualStrings("\x1b[3;4294967295;42t", pendingOutput(&terminal));

    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed("\x1b G\x1b[19t")).state_changed);
    try terminal.replyWindow(3, .{ .screen_cells = .{ .rows = 2160, .cols = 3840 } });
    try std.testing.expectEqualStrings("\x1b[9;2160;3840t", pendingOutput(&terminal));

    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed("\x1b[20t")).state_changed);
    try terminal.replyWindow(4, .{ .icon_title = "build" });
    try std.testing.expectEqualStrings("\x1b]Lbuild\x1b\\", pendingOutput(&terminal));

    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed("\x1b[19t")).state_changed);
    const fill = try reply_fill.fill(&terminal, allocator, expected_reply_bytes - 1, false);
    defer allocator.free(fill);
    try std.testing.expectError(
        error.ConsequenceLimit,
        terminal.replyWindow(5, .{ .screen_cells = .{ .rows = 1, .cols = 1 } }),
    );
    try std.testing.expectEqualSlices(u8, fill, pendingOutput(&terminal));
    try std.testing.expectEqual(@as(u64, 5), terminal.consequenceHead().?.window.generation);

    try consumeReplies(&terminal);
    try terminal.replyWindow(5, .{ .screen_cells = .{ .rows = 1, .cols = 1 } });
    try consumeReplies(&terminal);
    const oversized = try allocator.alloc(u8, expected_metadata_bytes + 1);
    defer allocator.free(oversized);
    @memset(oversized, 'x');
    try std.testing.expect((try terminal.feed("\x1b[20t")).state_changed);
    try std.testing.expectError(
        error.ConsequenceLimit,
        terminal.replyWindow(6, .{ .icon_title = oversized }),
    );
    try std.testing.expectEqualStrings("", pendingOutput(&terminal));
    try std.testing.expectEqual(@as(u64, 6), terminal.consequenceHead().?.window.generation);

    try terminal.replyWindow(6, .{ .icon_title = "ok" });
}

test "in-band resize mode emits transactional iTerm2 and Kitty reports" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 5);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b[?20")).state_changed == false);
    try std.testing.expect((try terminal.feed("48h")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b[?2048h")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?2048$p")).state_changed);
    try std.testing.expectEqualStrings("\x1b[?2048;1$y", pendingOutput(&terminal));
    try consumeReplies(&terminal);

    try terminal.setCellPixelSize(9, 17);
    try terminal.resize(4, 7);
    try std.testing.expectEqualStrings("\x1b[48;4;7;68;63t", pendingOutput(&terminal));

    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed("\x1b G")).state_changed);
    try terminal.resize(2, 3);
    try std.testing.expectEqualStrings("\x9b48;2;3;34;27t", pendingOutput(&terminal));

    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed("\x1b[?2048s\x1b[?2048l")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?2048r")).state_changed);
    try terminal.resize(3, 4);
    try std.testing.expectEqualStrings("\x9b48;3;4;51;36t", pendingOutput(&terminal));

    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed("\x1b[!p")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?2048$p")).state_changed);
    try std.testing.expectEqualStrings("\x1b[?2048;2$y", pendingOutput(&terminal));
    try consumeReplies(&terminal);
    try terminal.resize(4, 5);
    try std.testing.expectEqualStrings("", pendingOutput(&terminal));
}

test "in-band resize report saturation preserves dimensions and pending output" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 5);
    defer terminal.deinit();
    try terminal.setCellPixelSize(std.math.maxInt(u32), std.math.maxInt(u32));
    try std.testing.expect((try terminal.feed("\x1b[?2048h")).state_changed);

    const fill = try reply_fill.fill(&terminal, allocator, expected_reply_bytes - 1, false);
    defer allocator.free(fill);
    try std.testing.expectError(error.ConsequenceLimit, terminal.resize(std.math.maxInt(u16), std.math.maxInt(u16)));
    try std.testing.expectEqual(@as(u16, 3), terminal.screen_state.primary.rows);
    try std.testing.expectEqual(@as(u16, 5), terminal.screen_state.primary.cols);
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
    try std.testing.expectEqualStrings("two", terminal.title().?);

    try stream.nextSlice("\x1bc");
    const pop_first = try terminal.feed("\x1b[23t");
    try std.testing.expect(pop_first.state_changed and pop_first.title_changed);
    try std.testing.expectEqualStrings("one", terminal.title().?);
    try std.testing.expect(!(try terminal.feed("\x1b[23t")).state_changed);

    try consumeReplies(&terminal);
    try stream.nextSlice("\x1b G\x9b2");
    try stream.nextSlice("1t");
    try std.testing.expectEqualStrings("\x1b]lone\x1b\\", pendingOutput(&terminal));

    try consumeReplies(&terminal);
    const fill = try reply_fill.fill(&terminal, allocator, expected_reply_bytes - 2, false);
    defer allocator.free(fill);
    try std.testing.expectError(error.ConsequenceLimit, stream.nextSlice("\x9b21t"));
    try std.testing.expectEqualSlices(u8, fill, pendingOutput(&terminal));
}

test "eight-bit multipart reply limit rolls back every framing byte" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    write(&stream, "\x1b G\x1b[1;3;38;5;200m");

    const fill_len = expected_reply_bytes - 2;
    const fill = try reply_fill.fill(&terminal, allocator, fill_len, true);
    defer allocator.free(fill);

    try std.testing.expectError(error.ConsequenceLimit, stream.nextSlice("\x1bP$qm\x1b\\"));
    try std.testing.expectEqual(fill_len, pendingOutput(&terminal).len);
    try std.testing.expectEqualSlices(u8, fill, pendingOutput(&terminal));
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

    try consumeReplies(&terminal);
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

    try consumeReplies(&terminal);
    write(&stream, "\x1b[1;0'z");
    _ = encodeMouse(&terminal, .{ .kind = .move, .button = .none, .row = 2, .col = 3, .mod = .{}, .buttons_down = 1 });
    write(&stream, "\x1b[0'|");
    try std.testing.expectEqualStrings("\x1b[1;4;3;4;0&w", pendingOutput(&terminal));

    try consumeReplies(&terminal);
    write(&stream, "\x1b[2;0'z\x1b[0'|");
    try std.testing.expectEqualStrings("\x1b[1;4;3;4;0&w", pendingOutput(&terminal));
    try consumeReplies(&terminal);
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

    try consumeReplies(&terminal);
    _ = encodeMouse(&terminal, .{ .kind = .release, .button = .left, .row = 1, .col = 2, .mod = .{}, .buttons_down = 0 });
    try std.testing.expectEqualStrings("\x1b[3;0;2;3;0&w", pendingOutput(&terminal));

    try consumeReplies(&terminal);
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

    try consumeReplies(&terminal);
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

    const fill = try reply_fill.fill(&terminal, allocator, expected_reply_bytes, false);
    defer allocator.free(fill);

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
    try std.testing.expectEqual(@as(usize, expected_reply_bytes), pendingOutput(&terminal).len);

    try consumeReplies(&terminal);
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

    try terminal.resize(2, 6);
    try std.testing.expect(active.tabStopAt(2));
    try terminal.resize(2, 18);
    try std.testing.expect(active.tabStopAt(2));
    try std.testing.expect(!active.tabStopAt(10));

    try std.testing.expect((try terminal.feed("\x1bP2$t3/11/999/bad/0/3\x1b\\")).state_changed);
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

    try consumeReplies(&terminal);
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

    try consumeReplies(&terminal);
    write(
        &stream,
        "\x1b[1 q\x90$q q\x9c\x1b[2 q\x90$q q\x9c\x1b[3 q\x90$q q\x9c" ++
            "\x1b[4 q\x90$q q\x9c\x1b[5 q\x90$q q\x9c\x1b[6 q\x90$q q\x9c",
    );
    try std.testing.expectEqualStrings(
        "\x901$r1 q\x9c\x901$r2 q\x9c\x901$r3 q\x9c\x901$r4 q\x9c\x901$r5 q\x9c\x901$r6 q\x9c",
        pendingOutput(&terminal),
    );

    try consumeReplies(&terminal);
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

    try consumeReplies(&terminal);
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

    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed("\x1bP+Q6E616D65\x1b\\")).state_changed);
    try std.testing.expectEqualStrings("\x1bP0+R6E616D65\x1b\\", pendingOutput(&terminal));

    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed("\x1b G\x90+q436f;5463\x9c")).state_changed);
    try std.testing.expectEqualStrings("\x901+r436f=323536\x9c\x901+r5463\x9c", pendingOutput(&terminal));
}

test "XTGETTCAP response capacity failure rolls back every requested reply" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    const fill = try reply_fill.fill(&terminal, allocator, expected_reply_bytes - 8, false);
    defer allocator.free(fill);

    try std.testing.expectError(
        error.ConsequenceLimit,
        terminal.feed("\x1bP+q436F;5463\x1b\\"),
    );
    try std.testing.expectEqualSlices(u8, fill, pendingOutput(&terminal));
}

test "DCS configuration commands retain bounded cross-family order" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1bP+p436F=");
    try stream.nextSlice("7661\x1b\\\x90" ++ "0;1|keys\x9c\x1bP0!uA\x1b\\");
    const expected = [_]struct { kind: dcs_payload.DcsPayloadKind, payload: []const u8 }{
        .{ .kind = .xtsettcap, .payload = "436F=7661" },
        .{ .kind = .decudk, .payload = "0;1|keys" },
        .{ .kind = .decaupss, .payload = "0!uA" },
    };
    try std.testing.expectEqual(@as(u8, expected.len), terminal.consequenceCount());
    for (expected, 1..) |wanted, generation| {
        const occurrence = terminal.consequenceHead().?.dcs;
        try std.testing.expectEqual(@as(u64, @intCast(generation)), occurrence.generation);
        try std.testing.expectEqual(wanted.kind, occurrence.kind);
        try std.testing.expectEqualStrings(wanted.payload, occurrence.payload);
        try terminal.consumeConsequence(occurrence.generation);
    }
    try std.testing.expect(terminal.consequenceHead() == null);
}

test "iTerm2 DCS transports retain bounded unescaped occurrences in order" {
    var terminal = try Terminal.init(std.testing.allocator, 4, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1bP1000pdiscard\x18")).state_changed);

    const commands = [_]struct {
        introducer: []const u8,
        payload: []const u8,
        terminator: []const u8,
    }{
        .{ .introducer = "\x1bP1000p", .payload = "tmux-client", .terminator = "\x1b\\" },
        .{ .introducer = "\x90" ++ "2000p", .payload = "ssh-client", .terminator = "\x9c" },
        .{ .introducer = "\x1bPt", .payload = "tmux;wrapped\x1b\x1b[31m", .terminator = "\x1b\\" },
    };
    for (commands) |command| {
        try std.testing.expect(!(try terminal.feed(command.introducer)).state_changed);
        const split = command.payload.len / 2;
        try std.testing.expect(!(try terminal.feed(command.payload[0..split])).state_changed);
        try std.testing.expect(!(try terminal.feed(command.payload[split..])).state_changed);
        try std.testing.expect((try terminal.feed(command.terminator)).state_changed);
    }

    const expected = [_]struct { kind: dcs_payload.DcsPayloadKind, payload: []const u8 }{
        .{ .kind = .iterm_tmux_hook, .payload = "tmux-client" },
        .{ .kind = .iterm_ssh_hook, .payload = "ssh-client" },
        .{ .kind = .iterm_tmux_wrap, .payload = "wrapped\x1b[31m" },
    };
    for (expected, 1..) |wanted, generation| {
        const occurrence = terminal.consequenceHead().?.dcs;
        try std.testing.expectEqual(@as(u64, @intCast(generation)), occurrence.generation);
        try std.testing.expectEqual(wanted.kind, occurrence.kind);
        try std.testing.expectEqualStrings(wanted.payload, occurrence.payload);
        try terminal.consumeConsequence(occurrence.generation);
    }

    const ignored = [_][]const u8{
        "\x1bP999punknown\x1b\\",
        "\x1bP1000;1ptrailing-param\x1b\\",
        "\x1bPtother;payload\x1b\\",
    };
    for (ignored) |bytes| try std.testing.expect(!(try terminal.feed(bytes)).state_changed);
    try std.testing.expect(terminal.consequenceHead() == null);
}

test "Kitty host-directed DCS commands retain exact handler payloads in order" {
    var terminal = try Terminal.init(std.testing.allocator, 4, 8);
    defer terminal.deinit();

    const commands = [_]struct {
        bytes: []const u8,
        kind: dcs_payload.DcsPayloadKind,
        payload: []const u8,
    }{
        .{ .bytes = "kitty-cmd{\"cmd\":\"ls\"}", .kind = .kitty_remote_command, .payload = "{\"cmd\":\"ls\"}" },
        .{ .bytes = "kitty-overlay-ready|ready", .kind = .kitty_overlay_ready, .payload = "ready" },
        .{ .bytes = "kitty-kitten-result|result", .kind = .kitty_result, .payload = "result" },
        .{ .bytes = "kitty-print|cHJpbnQ=", .kind = .kitty_print, .payload = "cHJpbnQ=" },
        .{ .bytes = "kitty-echo|echo", .kind = .kitty_echo, .payload = "echo" },
        .{ .bytes = "kitty-ssh|ssh", .kind = .kitty_ssh, .payload = "ssh" },
        .{ .bytes = "kitty-ask|ask", .kind = .kitty_askpass, .payload = "ask" },
        .{ .bytes = "kitty-clone|clone", .kind = .kitty_clone, .payload = "clone" },
        .{ .bytes = "kitty-edit|edit", .kind = .kitty_edit, .payload = "edit" },
    };
    for (commands) |command| {
        try std.testing.expect(!(try terminal.feed("\x1bP@")).state_changed);
        try std.testing.expect(!(try terminal.feed(command.bytes[0 .. command.bytes.len / 2])).state_changed);
        try std.testing.expect(!(try terminal.feed(command.bytes[command.bytes.len / 2 ..])).state_changed);
        try std.testing.expect((try terminal.feed("\x1b\\")).state_changed);
    }
    try std.testing.expectEqual(@as(u8, commands.len), terminal.consequenceCount());
    for (commands, 1..) |wanted, generation| {
        const occurrence = terminal.consequenceHead().?.dcs;
        try std.testing.expectEqual(@as(u64, @intCast(generation)), occurrence.generation);
        try std.testing.expectEqual(wanted.kind, occurrence.kind);
        try std.testing.expectEqualStrings(wanted.payload, occurrence.payload);
        try terminal.consumeConsequence(occurrence.generation);
    }

    try std.testing.expect(!(try terminal.feed("\x1bP@kitty-unknown|drop\x1b\\")).state_changed);
    try std.testing.expect(terminal.consequenceHead() == null);
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

test "DCS consequence queue proves sixteen-entry saturation and preserves identity" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();

    for (0..5) |_| {
        try std.testing.expect((try terminal.feed("\x1bP+pA\x1b\\")).state_changed);
        try terminal.consumeConsequence(terminal.consequenceHead().?.dcs.generation);
    }
    for (0..16) |_| try std.testing.expect((try terminal.feed("\x1bP+pA\x1b\\")).state_changed);
    try std.testing.expectEqual(@as(u8, 16), terminal.consequenceCount());
    const head = terminal.consequenceHead().?.dcs;
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed("\x1bP+pB\x1b\\"));
    try std.testing.expectEqual(head.generation, terminal.consequenceHead().?.dcs.generation);
    try std.testing.expectEqualStrings("A", terminal.consequenceHead().?.dcs.payload);
    try std.testing.expectError(error.StaleConsequence, terminal.consumeConsequence(head.generation + 1));
}

test "DCS payload bound reports overflow and remains restartable" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();

    const header = "\x1bP+p436F=";
    const half = (parser_mod.max_metadata_control_bytes - 5) / 2;
    const remainder = parser_mod.max_metadata_control_bytes - 5 - half;
    try std.testing.expect(!(try terminal.feed(header)).history_lost);
    try std.testing.expect(!(try terminal.feed(&@as([half]u8, @splat('x')))).history_lost);
    try std.testing.expect(!(try terminal.feed(&@as([remainder]u8, @splat('x')))).history_lost);
    try std.testing.expect(!(try terminal.feed("\x1b\\")).history_lost);
    try std.testing.expectEqual(@as(usize, parser_mod.max_metadata_control_bytes), dcsPayload(&terminal).?.len);

    try std.testing.expect(!(try terminal.feed(header)).history_lost);
    try std.testing.expect(!(try terminal.feed(&@as([half]u8, @splat('y')))).history_lost);
    try std.testing.expect(!(try terminal.feed(&@as([remainder]u8, @splat('y')))).history_lost);
    try std.testing.expectError(error.StringControlLimit, terminal.feed("y"));
    try std.testing.expectEqual(@as(usize, parser_mod.max_metadata_control_bytes), dcsPayload(&terminal).?.len);
    try std.testing.expectEqual(@as(u8, 'x'), dcsPayload(&terminal).?[5]);

    try terminal.consumeConsequence(terminal.consequenceHead().?.dcs.generation);
    try std.testing.expect(!(try terminal.feed("\x1bP+pkeep\x1b\\")).history_lost);
    try std.testing.expectEqualStrings("keep", dcsPayload(&terminal).?);

    try std.testing.expect((try terminal.feed("\x1bc\x1b[?1049h\x1b[?1049l")).state_changed);
    try terminal.resize(5, 9);
    try std.testing.expectEqualStrings("keep", dcsPayload(&terminal).?);
}

test "APC PM and SOS retain bounded ordered fallback payloads" {
    var terminal = try Terminal.init(std.testing.allocator, 4, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b_drop\x18")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b_A")).state_changed);
    try std.testing.expect((try terminal.feed("P\x1b\x1bC\x1b\\\x9ePM\x9c\x1bXSOS\x1b\\")).state_changed);
    const expected = [_]struct { kind: terminal_mod.StringPayloadKind, payload: []const u8 }{
        .{ .kind = .apc, .payload = "AP\x1bC" },
        .{ .kind = .pm, .payload = "PM" },
        .{ .kind = .sos, .payload = "SOS" },
    };
    try terminal.resize(5, 9);
    try std.testing.expect((try terminal.feed("\x1b[?1049h\x1b[?1049l\x1bc")).state_changed);
    try std.testing.expectEqual(@as(u8, expected.len), terminal.consequenceCount());
    for (expected, 1..) |wanted, generation| {
        const occurrence = terminal.consequenceHead().?.string_control;
        try std.testing.expectEqual(@as(u64, @intCast(generation)), occurrence.generation);
        try std.testing.expectEqual(wanted.kind, occurrence.kind);
        try std.testing.expectEqualStrings(wanted.payload, occurrence.payload);
        try terminal.consumeConsequence(occurrence.generation);
    }
    try std.testing.expectEqual(@as(u8, 0), terminal.consequenceCount());
}

test "generic string fallback cancellation overflow and queue saturation preserve identity" {
    var terminal = try Terminal.init(std.testing.allocator, 4, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b_drop\x18")).state_changed);
    try std.testing.expect(terminal.consequenceHead() == null);
    try std.testing.expect(!(try terminal.feed(
        "\x1b_" ++ @as([2049]u8, @splat('x')) ++ "\x1b\\",
    )).state_changed);
    try std.testing.expect(terminal.consequenceHead() == null);

    for (0..5) |_| {
        try std.testing.expect((try terminal.feed("\x1b_A\x1b\\")).state_changed);
        try terminal.consumeConsequence(terminal.consequenceHead().?.string_control.generation);
    }
    for (0..32) |_| try std.testing.expect((try terminal.feed("\x1b^P\x1b\\")).state_changed);
    const head = terminal.consequenceHead().?.string_control;
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed("\x1bXS\x1b\\"));
    try std.testing.expectEqual(head.generation, terminal.consequenceHead().?.string_control.generation);
    try std.testing.expectError(error.StaleConsequence, terminal.consumeConsequence(head.generation + 1));
}

test "generic string aggregate budget rolls back and is reclaimed by consumption" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var sequence = std.ArrayList(u8).empty;
    defer sequence.deinit(allocator);

    try sequence.appendSlice(allocator, "\x1b_");
    try sequence.appendNTimes(allocator, 'a', 1200);
    try sequence.appendSlice(allocator, "\x1b\\");
    try std.testing.expect((try terminal.feed(sequence.items)).state_changed);
    const first = terminal.consequenceHead().?.string_control;
    try std.testing.expectEqual(@as(u64, 1), first.generation);
    try std.testing.expectEqual(@as(usize, 1200), first.payload.len);

    sequence.clearRetainingCapacity();
    try sequence.appendSlice(allocator, "\x1b^");
    try sequence.appendNTimes(allocator, 'b', 900);
    try sequence.appendSlice(allocator, "\x1b\\");
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed(sequence.items));
    try std.testing.expectEqual(@as(u8, 1), terminal.consequenceCount());
    try std.testing.expectEqual(first.generation, terminal.consequenceHead().?.string_control.generation);
    try std.testing.expectEqualStrings(first.payload, terminal.consequenceHead().?.string_control.payload);

    try terminal.consumeConsequence(first.generation);
    try std.testing.expect((try terminal.feed(sequence.items)).state_changed);
    sequence.clearRetainingCapacity();
    try sequence.appendSlice(allocator, "\x1bX");
    try sequence.appendNTimes(allocator, 'c', 1000);
    try sequence.appendSlice(allocator, "\x1b\\");
    try std.testing.expect((try terminal.feed(sequence.items)).state_changed);

    const second = terminal.consequenceHead().?.string_control;
    try std.testing.expectEqual(@as(u64, 2), second.generation);
    try std.testing.expectEqual(terminal_mod.StringPayloadKind.pm, second.kind);
    try std.testing.expectEqual(@as(usize, 900), second.payload.len);
    try terminal.consumeConsequence(second.generation);
    const third = terminal.consequenceHead().?.string_control;
    try std.testing.expectEqual(@as(u64, 3), third.generation);
    try std.testing.expectEqual(terminal_mod.StringPayloadKind.sos, third.kind);
    try std.testing.expectEqual(@as(usize, 1000), third.payload.len);
}

test "legacy Tektronix C0 and ESC controls retain ordered consequences" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed(
        "\x1c\x1d\x1e\x1f\x1b\x17\x1b\x1c\x1bl\x1bs",
    )).state_changed);
    const expected = [_]terminal_mod.LegacyControlKind{
        .tek_point_plot,
        .tek_graph,
        .tek_incremental_plot,
        .tek_alpha,
        .tek_point_plot,
        .hp_memory_lock,
        .tek_write_thru_short_dashed,
    };
    try std.testing.expectEqual(@as(u16, expected.len), terminal.consequenceCount());
    for (expected, 1..) |kind, id| {
        const occurrence = terminal.consequenceHead().?.legacy_control;
        try std.testing.expectEqual(@as(u64, @intCast(id)), occurrence.generation);
        try std.testing.expectEqual(kind, occurrence.kind);
        try terminal.consumeConsequence(occurrence.generation);
    }
    try std.testing.expect(terminal.consequenceHead() == null);
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
        "\x1b[?5h\x1b[?6h\x1b[?7l\x1b[?25l\x1b[3;4H\x1b[4 q\x1b[1m\x1b)0\x0e\x1b[?1048h",
    )).state_changed);
    try std.testing.expect((try terminal.feed(
        "\x1b[?5l\x1b[?6l\x1b[?7h\x1b[?25h\x1b[1;1H\x1b[1 q\x1b[0m\x1b)B\x0f\x1b[?1048l",
    )).state_changed);
    const restored = terminal.screen_state.activeConst();
    try std.testing.expectEqual(@as(u16, 2), restored.cursor.row);
    try std.testing.expectEqual(@as(u16, 3), restored.cursor.col);
    try std.testing.expectEqual(.underline, restored.cursor.effective_shape);
    try std.testing.expect(!restored.cursor.blink_intent);
    try std.testing.expect(restored.current_attrs.bold);
    try std.testing.expect(!terminal.screen_state.primary.cursor.visible);
    try std.testing.expect(!terminal.screen_state.alternate.cursor.visible);
    try std.testing.expect(terminal.modes.reverse_screen_mode);
    try std.testing.expect(restored.origin_mode);
    try std.testing.expect(!restored.auto_wrap);
    try std.testing.expectEqual(@as(u8, 1), terminal.gl_index);
    try std.testing.expectEqual(@as(u8, '0'), terminal.designations[1]);

    try consumeReplies(&terminal);
    const query = try terminal.feed("\x1b[?6$p");
    try std.testing.expect(!query.title_changed and !query.icon_changed);
    try std.testing.expectEqualStrings("\x1b[?6;1$y", pendingOutput(&terminal));

    try std.testing.expect((try terminal.feed("\x1b[?25h\x1b[?1049h\x1b[?25l")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b[?1049h")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?1049l")).state_changed);
    try std.testing.expect(terminal.screen_state.primary.cursor.visible);
    try std.testing.expect(terminal.screen_state.alternate.cursor.visible);
    try std.testing.expect(!(try terminal.feed("\x1b[?1049l")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b[?9999h\x1b[?1049x")).state_changed);

    try std.testing.expect((try terminal.feed("\x1b[?1047hALT")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?1047l")).state_changed);
    try terminal.resize(5, 10);
    try std.testing.expect((try terminal.feed("\x1b[?1047h")).state_changed);
    const alternate = terminal.screen_state.activeConst();
    try std.testing.expectEqual(@as(u16, 5), alternate.rows);
    try std.testing.expectEqual(@as(u16, 10), alternate.cols);
    try std.testing.expectEqual(@as(u21, 'A'), alternate.cellAt(0, 0));
    try std.testing.expectEqual(@as(u16, 0), alternate.cursor.row);
    try std.testing.expectEqual(@as(u16, 0), alternate.cursor.col);
}

test "Kitty alternate-screen modes preserve banks and apply transition effects once" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 6);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("MAIN\x1b[?47hALT\x1b[31m")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?47l")).state_changed);
    try std.testing.expectEqual(@as(u21, 'M'), terminal.screen_state.primary.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'A'), terminal.screen_state.alternate.cellAt(0, 0));

    try std.testing.expect((try terminal.feed("\x1b[?47h")).state_changed);
    try std.testing.expectEqual(@as(u21, 'A'), terminal.screen_state.alternate.cellAt(0, 0));
    try std.testing.expectEqual(@as(u16, 0), terminal.screen_state.alternate.cursor.row);
    try std.testing.expectEqual(@as(u16, 0), terminal.screen_state.alternate.cursor.col);
    try std.testing.expectEqual(Screen.default_cell_attrs, terminal.screen_state.alternate.current_attrs);
    try std.testing.expect(!(try terminal.feed("\x1b[?47h")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?47l")).state_changed);

    try std.testing.expect((try terminal.feed("\x1b[?1047h")).state_changed);
    try std.testing.expectEqual(@as(u21, 'A'), terminal.screen_state.alternate.cellAt(0, 0));
    try std.testing.expectEqual(@as(u16, 0), terminal.screen_state.alternate.cursor.row);
    try std.testing.expectEqual(@as(u16, 0), terminal.screen_state.alternate.cursor.col);
    try std.testing.expect(!(try terminal.feed("\x1b[?1047h")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?1047l")).state_changed);

    try std.testing.expect((try terminal.feed("\x1b[2;3H\x1b[?1049hX")).state_changed);
    try std.testing.expectEqual(@as(u21, 'X'), terminal.screen_state.alternate.cellAt(0, 0));
    try std.testing.expect(!(try terminal.feed("\x1b[?1049h")).state_changed);
    try std.testing.expectEqual(@as(u21, 'X'), terminal.screen_state.alternate.cellAt(0, 0));
    try std.testing.expect((try terminal.feed("\x1b[?1049l")).state_changed);
    try std.testing.expectEqual(@as(u16, 1), terminal.screen_state.primary.cursor.row);
    try std.testing.expectEqual(@as(u16, 2), terminal.screen_state.primary.cursor.col);
    try std.testing.expect(!(try terminal.feed("\x1b[?1049l")).state_changed);

    try std.testing.expect((try terminal.feed("\x1b[?1049h")).state_changed);
    try std.testing.expectEqual(@as(u21, 0), terminal.screen_state.alternate.cellAt(0, 0));
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

test "ignored and unknown DEC modes preserve pending wrap and grid state" {
    const modes = [_]u16{ 2, 4, 20, 42, 7727, std.math.maxInt(u16) };
    const finals = [_]u8{ 'h', 'l' };

    for (modes) |mode| for (finals) |final| {
        var terminal = try Terminal.init(std.testing.allocator, 2, 2);
        defer terminal.deinit();
        try std.testing.expect((try terminal.feed("AB")).state_changed);
        try std.testing.expect(terminal.screen_state.activeConst().wrap_pending);

        var bytes: [16]u8 = undefined;
        const prefix = try std.fmt.bufPrint(bytes[0..], "\x1b[?{d}", .{mode});
        try std.testing.expect(!(try terminal.feed(prefix)).state_changed);
        try std.testing.expect(!(try terminal.feed(&.{final})).state_changed);
        try std.testing.expect(terminal.screen_state.activeConst().wrap_pending);
        try std.testing.expectEqual(@as(u21, 'A'), terminal.screen_state.activeConst().cellAt(0, 0));
        try std.testing.expectEqual(@as(u21, 'B'), terminal.screen_state.activeConst().cellAt(0, 1));

        try std.testing.expect((try terminal.feed("C")).state_changed);
        try std.testing.expectEqual(@as(u21, 'C'), terminal.screen_state.activeConst().cellAt(1, 0));
    };
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
    try std.testing.expectEqualDeep(
        terminal_mod.MediaCopyRequest{ .private = true, .parameter = 5 },
        terminal.consequenceHead().?.media_copy.request,
    );

    write(&stream, "\x1b[?45l\x1b[?1045l");
    try std.testing.expect(!reverseWraparoundMode(&terminal));
    try std.testing.expect(!extendedReverseWraparoundMode(&terminal));
}

test "media-copy commands retain bounded ordered host intent" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b[");
    try stream.nextSlice("i\x9b4i\x1b[5i\x1b[99i\x1b[?5i");
    const expected = [_]terminal_mod.MediaCopyRequest{
        .{ .private = false, .parameter = 0 },
        .{ .private = false, .parameter = 4 },
        .{ .private = false, .parameter = 5 },
        .{ .private = false, .parameter = 99 },
        .{ .private = true, .parameter = 5 },
    };
    try std.testing.expectEqual(@as(u8, expected.len), terminal.consequenceCount());
    for (expected, 1..) |request, generation| {
        const occurrence = terminal.consequenceHead().?.media_copy;
        try std.testing.expectEqual(@as(u64, @intCast(generation)), occurrence.generation);
        try std.testing.expectEqualDeep(request, occurrence.request);
        try terminal.consumeConsequence(occurrence.generation);
    }
    try std.testing.expect(terminal.consequenceHead() == null);

    // Exercise ring wrap before filling the fixed burst bound.
    for (0..5) |_| {
        try std.testing.expect((try terminal.feed("\x1b[5i")).state_changed);
        try terminal.consumeConsequence(terminal.consequenceHead().?.media_copy.generation);
    }
    for (0..8) |parameter| {
        var bytes: [16]u8 = undefined;
        const command = try std.fmt.bufPrint(&bytes, "\x1b[{d}i", .{parameter});
        try std.testing.expect((try terminal.feed(command)).state_changed);
    }
    try std.testing.expectEqual(@as(u8, 8), terminal.consequenceCount());
    const head_before = terminal.consequenceHead().?.media_copy;
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed("\x1b[5i"));
    try std.testing.expectEqualDeep(head_before, terminal.consequenceHead().?.media_copy);

    try std.testing.expectError(error.StaleConsequence, terminal.consumeConsequence(head_before.generation + 1));
    try terminal.consumeConsequence(head_before.generation);
    try std.testing.expect((try terminal.feed("\x1b[?4i")).state_changed);
    while (terminal.consequenceHead()) |occurrence| {
        try terminal.consumeConsequence(occurrence.id());
    }

    try std.testing.expect(!(try terminal.feed("\x1b[1;2i\x1b[-1i\x1b[?1;2i")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[5i\x1bc\x1b[?1049h\x1b[?1049l")).state_changed);
    try terminal.resize(5, 9);
    try std.testing.expectEqualDeep(
        terminal_mod.MediaCopyRequest{ .private = false, .parameter = 5 },
        terminal.consequenceHead().?.media_copy.request,
    );
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

    try consumeReplies(&terminal);
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

test "DEC column modes own permission preservation query save and reset lifetime" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    const primary = &terminal.screen_state.primary;

    try std.testing.expect((try terminal.feed("kept\x1b[2;3H\x1b[?40l")).state_changed);
    const cursor_before_denied = primary.cursor;
    try std.testing.expect(!(try terminal.feed("\x1b[?3h")).state_changed);
    try std.testing.expectEqual(cursor_before_denied, primary.cursor);
    try std.testing.expectEqual(@as(u21, 'k'), primary.cellAt(0, 0));
    try std.testing.expect((try terminal.feed("\x1b[?3$p\x1b[?40$p\x1b[?95$p")).state_changed);
    try std.testing.expectEqualStrings("\x1b[?3;2$y\x1b[?40;2$y\x1b[?95;2$y", pendingOutput(&terminal));
    try consumeReplies(&terminal);

    try std.testing.expect((try terminal.feed("\x1b[?40h\x1b[?95")).state_changed);
    try std.testing.expect((try terminal.feed("h\x1b[?3h")).state_changed);
    try std.testing.expectEqual(@as(u16, 8), primary.cols);
    try std.testing.expectEqual(cursor_before_denied, primary.cursor);
    try std.testing.expectEqual(@as(u21, 'k'), primary.cellAt(0, 0));
    try std.testing.expect(!(try terminal.feed("\x1b[?3h")).state_changed);
    try terminal.resize(4, 10);
    try std.testing.expectEqual(@as(u16, 10), primary.cols);
    try std.testing.expectEqual(@as(u21, 'k'), primary.cellAt(0, 0));

    try std.testing.expect((try terminal.feed("\x1b[?1049h")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?3$p\x1b[?40$p\x1b[?95$p")).state_changed);
    try std.testing.expectEqualStrings("\x1b[?3;1$y\x1b[?40;1$y\x1b[?95;1$y", pendingOutput(&terminal));
    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed("\x1b[?40;95s\x1b[?40;95l\x1b[?3$p")).state_changed);
    try std.testing.expectEqualStrings("\x1b[?3;2$y", pendingOutput(&terminal));
    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed("\x1b[?40;95r")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?1049l")).state_changed);

    try std.testing.expect((try terminal.feed("\x1b[?95l\x1b[?3l")).state_changed);
    try std.testing.expectEqual(@as(u16, 0), primary.cursor.row);
    try std.testing.expectEqual(@as(u16, 0), primary.cursor.col);
    try std.testing.expectEqual(@as(u21, 0), primary.cellAt(0, 0));
    try std.testing.expect(!(try terminal.feed("\x1b[?3l")).state_changed);

    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed("\x1b[?95h\x1b[!p\x1b[?40$p\x1b[?95$p")).state_changed);
    try std.testing.expectEqualStrings("\x1b[?40;1$y\x1b[?95;2$y", pendingOutput(&terminal));
    try std.testing.expect(!(try terminal.feed("\x1b[!p")).state_changed);
    try consumeReplies(&terminal);
    terminal.hardReset();
    try std.testing.expect((try terminal.feed("\x1b[?40$p\x1b[?95$p")).state_changed);
    try std.testing.expectEqualStrings("\x1b[?40;1$y\x1b[?95;2$y", pendingOutput(&terminal));
}

test "DEC more-fix owns pending-wrap tab query save and reset lifetime" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 10);
    defer terminal.deinit();
    const primary = &terminal.screen_state.primary;

    try std.testing.expect((try terminal.feed("0123456789")).state_changed);
    try std.testing.expect(primary.wrap_pending);
    try std.testing.expect((try terminal.feed("\t")).state_changed);
    try std.testing.expectEqual(@as(u16, 0), primary.cursor.row);
    try std.testing.expectEqual(@as(u16, 9), primary.cursor.col);
    try std.testing.expect(!primary.wrap_pending);

    try std.testing.expect((try terminal.feed("\r\x1b[?41")).state_changed);
    try std.testing.expect((try terminal.feed("h0123456789")).state_changed);
    try std.testing.expect(terminal.modes.more_fix);
    try std.testing.expect(primary.wrap_pending);
    try std.testing.expect((try terminal.feed("\t")).state_changed);
    try std.testing.expectEqual(@as(u16, 1), primary.cursor.row);
    try std.testing.expectEqual(@as(u16, 8), primary.cursor.col);
    try std.testing.expectEqual(@as(u21, '0'), primary.cellAt(0, 0));
    try std.testing.expect(!(try terminal.feed("\x1b[?41h")).state_changed);

    try std.testing.expect((try terminal.feed("\x1b[?41$p")).state_changed);
    try std.testing.expectEqualStrings("\x1b[?41;1$y", pendingOutput(&terminal));
    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed("\x1b[?1002h\x1b[?41;1002s\x1b[?41l\x1b[?1000h")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b[?41$p\x1b[?1002$p")).state_changed);
    try std.testing.expectEqualStrings("\x1b[?41;2$y\x1b[?1002;2$y", pendingOutput(&terminal));
    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed("\x1b[?41;1002r\x1b[?1049h\x1b[?41$p\x1b[?1002$p")).state_changed);
    try std.testing.expectEqualStrings("\x1b[?41;1$y\x1b[?1002;1$y", pendingOutput(&terminal));
    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed("\x1b[!p\x1b[?41$p")).state_changed);
    try std.testing.expectEqualStrings("\x1b[?41;2$y", pendingOutput(&terminal));
    try std.testing.expect(!(try terminal.feed("\x1b[!p")).state_changed);

    terminal.hardReset();
    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed("\x1b[?41$p")).state_changed);
    try std.testing.expectEqualStrings("\x1b[?41;2$y", pendingOutput(&terminal));
}
