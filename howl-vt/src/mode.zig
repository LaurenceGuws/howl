//! Defines terminal mode state, saved DEC modes, and mode-report projections.

const std = @import("std");
const input_mouse = @import("input/mouse.zig");

/// Carries Kitty keyboard flags and the set, add, or remove operation mode.
pub const KeyFormatChange = struct {
    resource: ?u8,
    value: ?u16,
};

const saved_dec_mode_limit = 16;
const SavedDecModeCount = u8;
const SavedDecModeSlot = u8;

/// Stores terminal modes that affect screen mutation, input encoding, and reports.
pub const ModeState = struct {
    keyboard_action_mode: bool = false,
    application_cursor_keys: bool = false,
    application_keypad: bool = false,
    reverse_screen_mode: bool = false,
    send_receive_mode: bool = false,
    newline_mode: bool = false,
    modify_other_keys: i8 = 0,
    key_format: [8]u16 = [_]u16{0} ** 8,
    focus_reporting: bool = false,
    bracketed_paste: bool = false,
    synchronized_output: bool = false,
    reverse_wraparound_mode: bool = false,
    extended_reverse_wraparound_mode: bool = false,
    mouse_tracking: input_mouse.MouseTrackingMode = .off,
    mouse_protocol: input_mouse.MouseProtocol = .none,
    pointer_mode: u2 = 1,
    saved_dec_modes: [saved_dec_mode_limit]SavedDecMode = [_]SavedDecMode{.{ .mode = 0, .state = 0 }} ** saved_dec_mode_limit,
    saved_dec_mode_count: SavedDecModeCount = 0,
};

const SavedDecMode = struct {
    mode: u16,
    state: u8,
};

/// Borrows the DEC mode facts required to answer one mode query.
pub const DecView = struct {
    application_cursor_keys: bool,
    application_keypad: bool,
    reverse_screen_mode: bool,
    auto_wrap: bool,
    left_right_margin_mode: bool,
    cursor_visible: bool,
    alt_active: bool,
    mouse_tracking: input_mouse.MouseTrackingMode,
    mouse_protocol: input_mouse.MouseProtocol,
    focus_reporting: bool,
    bracketed_paste: bool,
    synchronized_output: bool,
};

/// Borrows the ANSI mode facts required to answer one mode query.
pub const AnsiView = struct {
    keyboard_action_mode: bool,
    insert_mode: bool,
    send_receive_mode: bool,
    newline_mode: bool,
};

/// Returns the DEC mode report state for a supported numeric mode.
pub fn decModeStateForView(view: DecView, mode: u16) u8 {
    return switch (mode) {
        1 => boolToDecModeState(view.application_cursor_keys),
        5 => boolToDecModeState(view.reverse_screen_mode),
        7 => boolToDecModeState(view.auto_wrap),
        69 => boolToDecModeState(view.left_right_margin_mode),
        66 => boolToDecModeState(view.application_keypad),
        25 => boolToDecModeState(view.cursor_visible),
        47, 1047, 1049 => boolToDecModeState(view.alt_active),
        9 => if (view.mouse_tracking == .x10) 1 else 2,
        1000 => if (view.mouse_tracking == .normal) 1 else 2,
        1002 => if (view.mouse_tracking == .button_event) 1 else 2,
        1003 => if (view.mouse_tracking == .any_event) 1 else 2,
        1004 => boolToDecModeState(view.focus_reporting),
        1005 => boolToDecModeState(view.mouse_protocol == .utf8),
        1006 => boolToDecModeState(view.mouse_protocol == .sgr),
        1015 => boolToDecModeState(view.mouse_protocol == .urxvt),
        2004 => boolToDecModeState(view.bracketed_paste),
        2026 => boolToDecModeState(view.synchronized_output),
        else => 0,
    };
}

/// Returns the ANSI mode report state for a supported numeric mode.
pub fn ansiModeStateForView(view: AnsiView, mode: u16) u8 {
    return switch (mode) {
        2 => boolToDecModeState(view.keyboard_action_mode),
        4 => boolToDecModeState(view.insert_mode),
        12 => boolToDecModeState(view.send_receive_mode),
        20 => boolToDecModeState(view.newline_mode),
        else => 0,
    };
}

fn boolToDecModeState(enabled: bool) u8 {
    return if (enabled) 1 else 2;
}

/// Returns an existing saved-mode slot or appends one within caller capacity.
pub fn savedDecModeSlot(saved_modes: []SavedDecMode, saved_count: *SavedDecModeCount, mode: u16) SavedDecModeSlot {
    const cap = savedDecModeCap(saved_modes);
    var slot: SavedDecModeSlot = 0;
    while (slot < saved_count.*) : (slot += 1) {
        if (saved_modes[savedIndex(slot)].mode == mode) return slot;
    }
    if (saved_count.* < cap) {
        const new_slot = saved_count.*;
        saved_count.* += 1;
        return new_slot;
    }
    return cap - 1;
}

/// Returns a saved DEC mode value when the bounded store contains it.
pub fn savedDecModeState(saved_modes: []const SavedDecMode, saved_count: SavedDecModeCount, mode: u16) ?u8 {
    var slot: SavedDecModeSlot = 0;
    while (slot < saved_count) : (slot += 1) {
        const idx = savedIndex(slot);
        if (saved_modes[idx].mode == mode) return saved_modes[idx].state;
    }
    return null;
}

/// Reports whether a DEC mode has implemented set and reset behavior.
pub fn canSetDecMode(mode: u16) bool {
    return switch (mode) {
        1, 5, 6, 7, 9, 25, 47, 66, 69, 1047, 1049, 1000, 1002, 1003, 1004, 1005, 1006, 1015, 2004, 2026 => true,
        else => false,
    };
}

fn savedIndex(slot: SavedDecModeSlot) usize {
    return @intCast(slot);
}

fn savedDecModeCap(saved_modes: []const SavedDecMode) SavedDecModeCount {
    std.debug.assert(saved_modes.len <= std.math.maxInt(SavedDecModeCount));
    return @intCast(saved_modes.len);
}

test "saved dec mode slot reuses existing entry" {
    var saved = [_]SavedDecMode{.{ .mode = 0, .state = 0 }} ** saved_dec_mode_limit;
    saved[0] = .{ .mode = 7, .state = 1 };
    var count: SavedDecModeCount = 1;
    try std.testing.expectEqual(@as(SavedDecModeSlot, 0), savedDecModeSlot(saved[0..], &count, 7));
    try std.testing.expectEqual(@as(SavedDecModeCount, 1), count);
}

test "saved dec mode slot appends and saturates" {
    var saved = [_]SavedDecMode{.{ .mode = 0, .state = 0 }} ** saved_dec_mode_limit;
    var count: SavedDecModeCount = 0;
    try std.testing.expectEqual(@as(SavedDecModeSlot, 0), savedDecModeSlot(saved[0..], &count, 7));
    try std.testing.expectEqual(@as(SavedDecModeCount, 1), count);
    count = saved_dec_mode_limit;
    try std.testing.expectEqual(@as(SavedDecModeSlot, saved_dec_mode_limit - 1), savedDecModeSlot(saved[0..], &count, 2004));
}

test "saved dec mode state scans only saved entries" {
    var saved = [_]SavedDecMode{.{ .mode = 0, .state = 0 }} ** saved_dec_mode_limit;
    saved[0] = .{ .mode = 7, .state = 1 };
    saved[1] = .{ .mode = 1004, .state = 2 };
    saved[2] = .{ .mode = 2004, .state = 1 };
    try std.testing.expectEqual(@as(?u8, 2), savedDecModeState(saved[0..], 2, 1004));
    try std.testing.expectEqual(@as(?u8, null), savedDecModeState(saved[0..], 2, 2004));
}
