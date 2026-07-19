//! Decodes private CSI mode and report commands.

const events = @import("semantic_event.zig");
const erase = @import("screen/erase.zig");
const params_mod = @import("csi_params.zig");

const SemanticEvent = events.SemanticEvent;

/// Decodes one private CSI sequence; unsupported forms return null.
pub fn process(final: u8, params: []const i32, leader: u8, intermediates: []const u8) ?SemanticEvent {
    if (leader != '?') return null;
    if (directQuery(final, params)) |event| return event;
    if (params.len == 0) return null;
    if (modeReport(final, params, intermediates)) |event| return event;
    if (saveRestore(final, params, intermediates)) |event| return event;
    if (report(final, params)) |event| return event;
    return modeToggle(final, params[0]);
}

fn directQuery(final: u8, params: []const i32) ?SemanticEvent {
    switch (final) {
        'u' => return SemanticEvent.kitty_keyboard_query,
        'g' => return SemanticEvent{ .key_format_query = params_mod.keyFormatParamAtOrDefault0(params, 0) },
        'J' => return eraseDisplayEvent(params_mod.eraseMode(params_mod.paramAtOrDefault0(params, 0)), true),
        'K' => return SemanticEvent{ .selective_erase_line = params_mod.eraseMode(params_mod.paramAtOrDefault0(params, 0)) },
        'W' => if (params_mod.paramAtOrDefault0(params, 0) == 5) return SemanticEvent.reset_default_tab_stops,
        else => {},
    }
    return null;
}

fn eraseDisplayEvent(mode: erase.EraseMode, protected: bool) SemanticEvent {
    return switch (mode) {
        .cursor_to_end => SemanticEvent{ .erase_display_below = protected },
        .start_to_cursor => SemanticEvent{ .erase_display_above = protected },
        .all => SemanticEvent{ .erase_display_complete = protected },
        .scrollback => SemanticEvent{ .erase_display_scrollback = protected },
    };
}

fn modeReport(final: u8, params: []const i32, intermediates: []const u8) ?SemanticEvent {
    if (final == 'm' and params_mod.paramAtOrDefault0(params, 0) == 4) return SemanticEvent.modify_other_keys_query;
    if (final == 'p' and params_mod.intermediatesHas(intermediates, '$')) {
        return SemanticEvent{ .dec_mode_query = params_mod.paramAtOrDefault0(params, 0) };
    }
    return null;
}

fn saveRestore(final: u8, params: []const i32, intermediates: []const u8) ?SemanticEvent {
    if (intermediates.len != 0) return null;
    return switch (final) {
        's' => SemanticEvent{ .dec_mode_save = params_mod.collectParams(params) },
        'r' => SemanticEvent{ .dec_mode_restore = params_mod.collectParams(params) },
        else => null,
    };
}

fn report(final: u8, params: []const i32) ?SemanticEvent {
    const param = params_mod.paramAtOrDefault0(params, 0);
    return switch (final) {
        'i' => SemanticEvent{ .media_copy_request = param },
        'n' => switch (param) {
            6 => SemanticEvent.dec_cursor_position_report,
            55, 56 => |status| SemanticEvent{ .dec_device_status_report = status },
            else => null,
        },
        else => null,
    };
}

fn modeToggle(final: u8, mode: i32) ?SemanticEvent {
    if (basicModeToggle(final, mode)) |event| return event;
    if (mouseModeToggle(final, mode)) |event| return event;
    return altScreenToggle(final, mode);
}

fn basicModeToggle(final: u8, mode: i32) ?SemanticEvent {
    return switch (mode) {
        5 => boolEvent(final, .{ .reverse_screen_mode = true }, .{ .reverse_screen_mode = false }),
        25 => boolEvent(final, .{ .cursor_visible = true }, .{ .cursor_visible = false }),
        7 => boolEvent(final, .{ .auto_wrap = true }, .{ .auto_wrap = false }),
        6 => boolEvent(final, .{ .origin_mode = true }, .{ .origin_mode = false }),
        1 => boolEvent(final, .{ .application_cursor_keys = true }, .{ .application_cursor_keys = false }),
        66 => boolEvent(final, .{ .application_keypad = true }, .{ .application_keypad = false }),
        69 => boolEvent(final, .{ .left_right_margin_mode = true }, .{ .left_right_margin_mode = false }),
        45 => boolEvent(final, .{ .reverse_wraparound_mode = true }, .{ .reverse_wraparound_mode = false }),
        1004 => boolEvent(final, .{ .focus_reporting = true }, .{ .focus_reporting = false }),
        2004 => boolEvent(final, .{ .bracketed_paste = true }, .{ .bracketed_paste = false }),
        2026 => boolEvent(final, .{ .synchronized_output = true }, .{ .synchronized_output = false }),
        1045 => boolEvent(final, .{ .extended_reverse_wraparound_mode = true }, .{ .extended_reverse_wraparound_mode = false }),
        else => null,
    };
}

fn mouseModeToggle(final: u8, mode: i32) ?SemanticEvent {
    return switch (mode) {
        9 => boolEvent(final, SemanticEvent.mouse_tracking_x10, SemanticEvent.mouse_tracking_off),
        1000 => boolEvent(final, SemanticEvent.mouse_tracking_normal, SemanticEvent.mouse_tracking_off),
        1002 => boolEvent(final, SemanticEvent.mouse_tracking_button_event, SemanticEvent.mouse_tracking_off),
        1003 => boolEvent(final, SemanticEvent.mouse_tracking_any_event, SemanticEvent.mouse_tracking_off),
        1005 => boolEvent(final, .{ .mouse_protocol_utf8 = true }, .{ .mouse_protocol_utf8 = false }),
        1006 => boolEvent(final, .{ .mouse_protocol_sgr = true }, .{ .mouse_protocol_sgr = false }),
        1015 => boolEvent(final, .{ .mouse_protocol_urxvt = true }, .{ .mouse_protocol_urxvt = false }),
        else => null,
    };
}

fn altScreenToggle(final: u8, mode: i32) ?SemanticEvent {
    return switch (mode) {
        47 => boolEvent(final, .{ .enter_alt_screen = .{ .clear = false, .save_cursor = false } }, .{ .exit_alt_screen = .{ .restore_cursor = false } }),
        1047 => boolEvent(final, .{ .enter_alt_screen = .{ .clear = true, .save_cursor = false } }, .{ .exit_alt_screen = .{ .restore_cursor = false } }),
        1049 => boolEvent(final, .{ .enter_alt_screen = .{ .clear = true, .save_cursor = true } }, .{ .exit_alt_screen = .{ .restore_cursor = true } }),
        else => null,
    };
}

fn boolEvent(final: u8, on: SemanticEvent, off: SemanticEvent) ?SemanticEvent {
    return switch (final) {
        'h' => on,
        'l' => off,
        else => null,
    };
}
