//! Pure ANSI and DEC mode-state classification plus bounded DECRPM serialization.
//!
//! Terminal projects its live owners into these borrowed value views. This module
//! knows no screen, terminal, savepoint, parser, or consequence lifetime.

const std = @import("std");
const input = @import("input.zig");
const replies = @import("replies.zig");

/// Borrows the DEC mode facts required to answer one mode query.
pub const DecView = struct {
    application_cursor_keys: bool = false,
    application_keypad: bool = false,
    column_mode_132: bool = false,
    allow_column_mode: bool = false,
    preserve_screen_on_column_mode: bool = false,
    more_fix: bool = false,
    auto_repeat: bool = false,
    reverse_screen_mode: bool = false,
    origin_mode: bool = false,
    auto_wrap: bool = false,
    left_right_margin_mode: bool = false,
    cursor_blink: bool = false,
    cursor_visible: bool = false,
    alt_active: bool = false,
    mouse_tracking: input.MouseTrackingMode = .off,
    mouse_protocol: input.MouseProtocol = .none,
    focus_reporting: bool = false,
    alternate_scroll: bool = false,
    meta_sends_escape: bool = false,
    report_key_up: bool = false,
    bracketed_paste: bool = false,
    synchronized_output: bool = false,
    inband_resize_notifications: bool = false,
    color_preference_notifications: bool = false,
    paste_events: bool = false,
    reverse_wraparound: bool = false,
    extended_reverse_wraparound: bool = false,
    sixel_display_mode: bool = false,
};

/// Borrows the ANSI mode facts required to answer one mode query.
pub const AnsiView = struct {
    keyboard_action_mode: bool = false,
    insert_mode: bool = false,
    send_receive_mode: bool = false,
    newline_mode: bool = false,
};

/// Returns DEC mode state 1/2 for a supported mode or 0 for unknown mode identity.
pub fn decState(view: DecView, mode: u16) u8 {
    return switch (mode) {
        1 => boolState(view.application_cursor_keys),
        3 => boolState(view.allow_column_mode and view.column_mode_132),
        40 => boolState(view.allow_column_mode),
        41 => boolState(view.more_fix),
        95 => boolState(view.preserve_screen_on_column_mode),
        5 => boolState(view.reverse_screen_mode),
        6 => boolState(view.origin_mode),
        7 => boolState(view.auto_wrap),
        8 => boolState(view.auto_repeat),
        12 => boolState(view.cursor_blink),
        45 => boolState(view.reverse_wraparound),
        69 => boolState(view.left_right_margin_mode),
        80 => boolState(view.sixel_display_mode),
        66 => boolState(view.application_keypad),
        25 => boolState(view.cursor_visible),
        47, 1047, 1049 => boolState(view.alt_active),
        9 => boolState(view.mouse_tracking == .x10),
        1000 => boolState(view.mouse_tracking == .normal),
        1002 => boolState(view.mouse_tracking == .button_event),
        1003 => boolState(view.mouse_tracking == .any_event),
        1004 => boolState(view.focus_reporting),
        1005 => boolState(view.mouse_protocol == .utf8),
        1006 => boolState(view.mouse_protocol == .sgr),
        1007 => boolState(view.alternate_scroll),
        1016 => boolState(view.mouse_protocol == .sgr_pixel),
        1015 => boolState(view.mouse_protocol == .urxvt),
        1036 => boolState(view.meta_sends_escape),
        1337 => boolState(view.report_key_up),
        2004 => boolState(view.bracketed_paste),
        2026 => boolState(view.synchronized_output),
        2048 => boolState(view.inband_resize_notifications),
        2031 => boolState(view.color_preference_notifications),
        5522 => boolState(view.paste_events),
        1045 => boolState(view.extended_reverse_wraparound),
        else => 0,
    };
}

/// Returns ANSI mode state 1/2 for a supported mode or 0 for unknown mode identity.
pub fn ansiState(view: AnsiView, mode: u16) u8 {
    return switch (mode) {
        2 => boolState(view.keyboard_action_mode),
        4 => boolState(view.insert_mode),
        12 => boolState(view.send_receive_mode),
        20 => boolState(view.newline_mode),
        else => 0,
    };
}

/// Appends one DEC private mode report using the output buffer's terminal framing.
pub fn appendDec(
    output: *replies.Buffer,
    encode_buffer: []u8,
    mode: u16,
    state: u8,
) replies.AppendError!void {
    const payload = std.fmt.bufPrint(encode_buffer, "?{d};{d}$y", .{ mode, state }) catch unreachable;
    try output.appendCsi(.terminal, payload);
}

/// Appends one ANSI mode report using the output buffer's terminal framing.
pub fn appendAnsi(
    output: *replies.Buffer,
    encode_buffer: []u8,
    mode: u16,
    state: u8,
) replies.AppendError!void {
    const payload = std.fmt.bufPrint(encode_buffer, "{d};{d}$y", .{ mode, state }) catch unreachable;
    try output.appendCsi(.terminal, payload);
}

fn boolState(enabled: bool) u8 {
    return if (enabled) 1 else 2;
}

test "DEC report inventory distinguishes reset set and unsupported modes" {
    const boolean_modes = [_]u16{
        1,  3,    40,   41,   95,   5,    6,    7,    8,    12,   45,   69,   80,   66, 25,
        47, 1047, 1049, 1004, 1007, 1036, 1337, 2004, 2026, 2048, 2031, 5522, 1045,
    };
    for (boolean_modes) |mode| try std.testing.expectEqual(@as(u8, 2), decState(.{}, mode));
    try std.testing.expectEqual(@as(u8, 0), decState(.{}, 65535));

    const enabled = DecView{
        .application_cursor_keys = true,
        .application_keypad = true,
        .column_mode_132 = true,
        .allow_column_mode = true,
        .preserve_screen_on_column_mode = true,
        .more_fix = true,
        .auto_repeat = true,
        .reverse_screen_mode = true,
        .origin_mode = true,
        .auto_wrap = true,
        .left_right_margin_mode = true,
        .cursor_blink = true,
        .cursor_visible = true,
        .alt_active = true,
        .focus_reporting = true,
        .alternate_scroll = true,
        .meta_sends_escape = true,
        .report_key_up = true,
        .bracketed_paste = true,
        .synchronized_output = true,
        .inband_resize_notifications = true,
        .color_preference_notifications = true,
        .paste_events = true,
        .reverse_wraparound = true,
        .extended_reverse_wraparound = true,
        .sixel_display_mode = true,
    };
    for (boolean_modes) |mode| try std.testing.expectEqual(@as(u8, 1), decState(enabled, mode));

    var gated = enabled;
    gated.allow_column_mode = false;
    try std.testing.expectEqual(@as(u8, 2), decState(gated, 3));
    try std.testing.expectEqual(@as(u8, 2), decState(gated, 40));
}

test "DEC mouse reports name exactly one active tracking and protocol mode" {
    const tracking = [_]struct { mode: u16, value: input.MouseTrackingMode }{
        .{ .mode = 9, .value = .x10 },
        .{ .mode = 1000, .value = .normal },
        .{ .mode = 1002, .value = .button_event },
        .{ .mode = 1003, .value = .any_event },
    };
    for (tracking) |expected| {
        const view = DecView{ .mouse_tracking = expected.value };
        for (tracking) |candidate| try std.testing.expectEqual(
            @as(u8, if (candidate.mode == expected.mode) 1 else 2),
            decState(view, candidate.mode),
        );
    }

    const protocols = [_]struct { mode: u16, value: input.MouseProtocol }{
        .{ .mode = 1005, .value = .utf8 },
        .{ .mode = 1006, .value = .sgr },
        .{ .mode = 1016, .value = .sgr_pixel },
        .{ .mode = 1015, .value = .urxvt },
    };
    for (protocols) |expected| {
        const view = DecView{ .mouse_protocol = expected.value };
        for (protocols) |candidate| try std.testing.expectEqual(
            @as(u8, if (candidate.mode == expected.mode) 1 else 2),
            decState(view, candidate.mode),
        );
    }
}

test "ANSI report inventory is closed and exact" {
    const modes = [_]u16{ 2, 4, 12, 20 };
    for (modes) |mode| try std.testing.expectEqual(@as(u8, 2), ansiState(.{}, mode));
    const enabled = AnsiView{
        .keyboard_action_mode = true,
        .insert_mode = true,
        .send_receive_mode = true,
        .newline_mode = true,
    };
    for (modes) |mode| try std.testing.expectEqual(@as(u8, 1), ansiState(enabled, mode));
    try std.testing.expectEqual(@as(u8, 0), ansiState(enabled, 1));
}

test "ANSI and DEC serialization follows terminal C1 framing" {
    var output = replies.Buffer.init(std.testing.allocator);
    defer output.deinit();
    var scratch: [32]u8 = undefined;

    try appendAnsi(&output, &scratch, 4, 1);
    try appendDec(&output, &scratch, 2004, 2);
    try std.testing.expectEqualStrings("\x1b[4;1$y\x1b[?2004;2$y", output.bytes());
    output.truncate(0);

    try std.testing.expect(output.setEightBitControls(true));
    try appendDec(&output, &scratch, 1006, 1);
    try std.testing.expectEqualStrings("\x9b?1006;1$y", output.bytes());
}
