const std = @import("std");
const dcs_payload = @import("../../src/dcs_payload.zig");
const host_state = @import("../../src/host_state.zig");
const legacy_control = @import("../../src/legacy_control.zig");
const screen_capture = @import("../support/screen_capture.zig");
const screen_set = @import("../../src/screen_set.zig");
const selection = @import("../../src/selection.zig");
const terminal_mod = @import("../../src/terminal.zig");
const input_encode = @import("../../src/input/encode.zig");
const input_keyboard = @import("../../src/input/keyboard.zig");
const input_mouse = @import("../../src/input/mouse.zig");
const stream_harness = @import("../support/stream_harness.zig");

const Terminal = terminal_mod.Terminal;
const HostState = host_state;
const StreamHarness = stream_harness.Harness;

var encode_scratch: input_encode.Scratch = .{};

fn encodeKey(terminal: *Terminal, key: input_keyboard.Key, mod: input_keyboard.Modifier) []const u8 {
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

    write(&stream, "\x1b[?1003h\x1b[?1005h\x1b[?1003;1005s");
    write(&stream, "\x1b[?1000h\x1b[?1006h");
    write(&stream, "\x1b[?1003;1005r");
    write(&stream, "\x1b[?9$p\x1b[?1000$p\x1b[?1003$p\x1b[?1005$p\x1b[?1006$p\x1b[?1015$p");

    try std.testing.expectEqualStrings("\x1b[?9;2$y\x1b[?1000;2$y\x1b[?1003;1$y\x1b[?1005;1$y\x1b[?1006;2$y\x1b[?1015;2$y", pendingOutput(&terminal));
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

test "kitty keyboard set query push and pop flags" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    write(&stream, "\x1b[=5u\x1b[?u");
    try std.testing.expectEqualStrings("\x1b[?5u", pendingOutput(&terminal));
    clearPendingOutput(&terminal);

    write(&stream, "\x1b[>1u\x1b[?u");
    try std.testing.expectEqualStrings("\x1b[?1u", pendingOutput(&terminal));
    clearPendingOutput(&terminal);

    write(&stream, "\x1b[<u\x1b[?u");
    try std.testing.expectEqualStrings("\x1b[?5u", pendingOutput(&terminal));
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
    try std.testing.expectEqualStrings("\x1b[2;1$y\x1b[4;1$y\x1b[12;1$y\x1b[20;1$y\x1b[1;1#Q", pendingOutput(&terminal));
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
    try std.testing.expectEqualStrings("", encodeKey(&terminal, try input_keyboard.Key.initUnicode('a'), .{}));

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

    write(&stream, "\x1b[2;3r\x1b[?69h\x1b[2;7s\x1b[3 q\x1b[1\"q\x1b[2*x");
    write(&stream, "\x1bP$qr\x1b\\\x1bP$qs\x1b\\\x1bP$q q\x1b\\\x1bP$q\"q\x1b\\\x1bP$q*x\x1b\\\x1bP$qm\x1b\\");

    try std.testing.expectEqualStrings(
        "\x1bP1$r2;3r\x1b\\\x1bP1$r2;7s\x1b\\\x1bP1$r3 q\x1b\\\x1bP1$r1\"q\x1b\\\x1bP1$r2*x\x1b\\\x1bP0$r\x1b\\",
        pendingOutput(&terminal),
    );
}

test "DCS resource queries return conservative invalid replies" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    write(&stream, "\x1bP+q436F\x1b\\\x1bP+Q6E616D65\x1b\\");

    try std.testing.expectEqualStrings("\x1bP0+r\x1b\\\x1bP0+R6E616D65\x1b\\", pendingOutput(&terminal));
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

    try std.testing.expectEqualStrings("a", encodeKey(&terminal, try input_keyboard.Key.initUnicode('a'), .{ .alt = true }));
    write(&stream, "\x1b[>4;2m\x1b[?4m");
    try std.testing.expectEqualStrings("\x1b[>4;2m", pendingOutput(&terminal));
    try std.testing.expectEqualStrings("\x1b[27;3;97~", encodeKey(&terminal, try input_keyboard.Key.initUnicode('a'), .{ .alt = true }));
    try std.testing.expectEqualStrings("a", encodeKey(&terminal, try input_keyboard.Key.initUnicode('a'), .{}));

    write(&stream, "\x1b[>4;3m");
    try std.testing.expectEqualStrings("\x1b[27;1;97~", encodeKey(&terminal, try input_keyboard.Key.initUnicode('a'), .{}));

    write(&stream, "\x1b[>4n");
    try std.testing.expectEqualStrings("a", encodeKey(&terminal, try input_keyboard.Key.initUnicode('a'), .{ .alt = true }));
}

test "xterm key format query reset and other-key encoding" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    write(&stream, "\x1b[>4;1f\x1b[?4g\x1b[>4;1m");
    try std.testing.expectEqualStrings("\x1b[>4;1f", pendingOutput(&terminal));
    try std.testing.expectEqualStrings("\x1b[97;3u", encodeKey(&terminal, try input_keyboard.Key.initUnicode('a'), .{ .alt = true }));

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
