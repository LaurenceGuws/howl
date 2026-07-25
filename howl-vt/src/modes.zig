//! Owns terminal mode state and per-screen Kitty keyboard stacks.

const std = @import("std");
const input = @import("input.zig");

/// Enumerates DEC modes whose state participates in parameterized XTSAVE and XTRESTORE.
const savable_dec_modes = [_]u16{
    1,    3,    5,    6,    7,    8,    9,    12,   25,   40,
    41,   45,   47,   66,   69,   80,   95,   1045, 1047, 1049,
    1000, 1002, 1003, 1004, 1005, 1006, 1015, 1016, 2004, 2026,
    2031, 2048, 5522,
};

/// Stores modes that affect screen mutation, input encoding, and reports.
pub const State = struct {
    keyboard_action_mode: bool = false,
    application_cursor_keys: bool = false,
    application_keypad: bool = false,
    column_mode_132: bool = false,
    // Howl historically admits DECCOLM while the embedding caller owns physical geometry.
    allow_column_mode: bool = true,
    preserve_screen_on_column_mode: bool = false,
    more_fix: bool = false,
    auto_repeat: bool = true,
    reverse_screen_mode: bool = false,
    send_receive_mode: bool = false,
    newline_mode: bool = false,
    modify_other_keys: i8 = 0,
    key_format: [8]u16 = @as([8]u16, @splat(0)),
    focus_reporting: bool = false,
    alternate_scroll: bool = false,
    meta_sends_escape: bool = false,
    report_key_up: bool = false,
    bracketed_paste: bool = false,
    synchronized_output: bool = false,
    inband_resize_notifications: bool = false,
    color_preference_notifications: bool = false,
    paste_events: bool = false,
    termios_signals: bool = false,
    sixel_display_mode: bool = false,
    reverse_wraparound_mode: bool = false,
    extended_reverse_wraparound_mode: bool = false,
    mouse_tracking: input.MouseTrackingMode = .off,
    mouse_protocol: input.MouseProtocol = .none,
    pointer_mode: u2 = 1,
    saved_dec_modes: [savable_dec_modes.len]u8 = @as([savable_dec_modes.len]u8, @splat(2)),
};

/// Resolves one implemented DEC mode to its fixed saved-state slot.
pub fn savedDecModeIndex(mode: u16) ?usize {
    for (savable_dec_modes, 0..) |supported, index| {
        if (supported == mode) return index;
    }
    return null;
}

test "saved DEC mode slots cover each reviewed savable mode exactly once" {
    for (savable_dec_modes, 0..) |mode, index| {
        try std.testing.expectEqual(@as(?usize, index), savedDecModeIndex(mode));
        for (savable_dec_modes[index + 1 ..]) |later| {
            try std.testing.expect(later != mode);
        }
    }
    try std.testing.expectEqual(@as(?usize, null), savedDecModeIndex(9999));
}

/// Masks Kitty keyboard flags to the protocol's seven-bit flag domain.
pub const kitty_keyboard_flag_mask: u8 = 0x7f;
const kitty_keyboard_stack_capacity = 8;

/// Stores Kitty's current keyboard flags and seven predecessors.
const KittyKeyStack = struct {
    flags: u8 = 0,
    stack: [kitty_keyboard_stack_capacity - 1]u8 =
        @as([(kitty_keyboard_stack_capacity - 1)]u8, @splat(0)),
    len: u8 = 0,

    /// Replaces, sets, or clears the current seven-bit Kitty flag set.
    pub fn set(self: *KittyKeyStack, requested: u8, mode: u8) bool {
        const before = self.flags;
        const flags = requested & kitty_keyboard_flag_mask;
        switch (mode) {
            1 => self.flags = flags,
            2 => self.flags |= flags,
            3 => self.flags &= ~flags,
            else => return false,
        }
        return self.flags != before;
    }

    /// Pushes flags into Kitty's eight-slot stack, dropping the oldest at capacity.
    pub fn push(self: *KittyKeyStack, requested: u8) bool {
        const before = self.*;
        const flags = requested & kitty_keyboard_flag_mask;
        if (self.len == self.stack.len) {
            std.mem.copyForwards(u8, self.stack[0 .. self.stack.len - 1], self.stack[1..self.stack.len]);
            self.len -= 1;
        }
        self.stack[self.len] = self.flags;
        self.len += 1;
        self.flags = flags;
        return !std.meta.eql(before, self.*);
    }

    /// Pops up to count active slots; exhausting the stack restores zero flags.
    pub fn pop(self: *KittyKeyStack, count: u16) bool {
        const before = self.*;
        var remaining = count;
        while (remaining > 0 and self.len > 0) : (remaining -= 1) {
            self.len -= 1;
            self.flags = self.stack[self.len];
        }
        if (remaining > 0) self.flags = 0;
        return !std.meta.eql(before, self.*);
    }
};

test "keyboard stack retains seven-bit flags and reports exact mutation" {
    var stack: KittyKeyStack = .{};
    try std.testing.expect(stack.set(0x7f, 1));
    try std.testing.expectEqual(@as(u8, 0x7f), stack.flags);
    try std.testing.expect(stack.push(8));
    try std.testing.expectEqual(@as(u8, 8), stack.flags);
    try std.testing.expect(stack.pop(1));
    try std.testing.expectEqual(@as(u8, 0x7f), stack.flags);
    try std.testing.expect(stack.set(8, 3));
    try std.testing.expectEqual(@as(u8, 0x77), stack.flags);
    try std.testing.expect(!stack.set(0, 4));
    try std.testing.expectEqual(@as(u8, 0x77), stack.flags);
    try std.testing.expect(stack.pop(1));
    try std.testing.expectEqual(@as(u8, 0), stack.flags);
}

test "keyboard stack drops oldest predecessor at exact saturation" {
    var stack: KittyKeyStack = .{};
    for (0..kitty_keyboard_stack_capacity + 1) |index| {
        try std.testing.expect(stack.push(@intCast(index + 1)));
    }
    try std.testing.expectEqual(@as(u8, kitty_keyboard_stack_capacity - 1), stack.len);
    try std.testing.expect(stack.pop(kitty_keyboard_stack_capacity - 1));
    try std.testing.expectEqual(@as(u8, 2), stack.flags);
    try std.testing.expectEqual(@as(u8, 0), stack.len);
}

/// Per-screen keyboard state retained while Terminal switches primary/alternate screens.
const KeyboardScreenState = struct {
    keyboard: KittyKeyStack = .{},
};

/// Retains the independent Kitty keyboard stack for each terminal screen.
pub const KeyboardState = struct {
    main: KeyboardScreenState = .{},
    alt: KeyboardScreenState = .{},

    /// Returns mutable keyboard state for the currently selected screen.
    pub fn activeScreen(self: *KeyboardState, alt_active: bool) *KeyboardScreenState {
        return if (alt_active) &self.alt else &self.main;
    }

    /// Returns borrowed keyboard state for the selected screen.
    pub fn activeScreenConst(self: *const KeyboardState, alt_active: bool) *const KeyboardScreenState {
        return if (alt_active) &self.alt else &self.main;
    }

    /// Resets both per-screen keyboard stacks during terminal hard reset.
    pub fn resetTerminalState(self: *KeyboardState) void {
        self.main = .{};
        self.alt = .{};
    }
};

test "keyboard state keeps primary and alternate stacks independent" {
    var state: KeyboardState = .{};
    try std.testing.expect(state.activeScreen(false).keyboard.set(1, 1));
    try std.testing.expect(state.activeScreen(true).keyboard.set(2, 1));

    try std.testing.expectEqual(@as(u8, 1), state.activeScreenConst(false).keyboard.flags);
    try std.testing.expectEqual(@as(u8, 2), state.activeScreenConst(true).keyboard.flags);

    try std.testing.expect(state.activeScreen(false).keyboard.push(3));
    try std.testing.expectEqual(@as(u8, 3), state.activeScreenConst(false).keyboard.flags);
    try std.testing.expectEqual(@as(u8, 2), state.activeScreenConst(true).keyboard.flags);

    state.resetTerminalState();
    try std.testing.expectEqual(@as(u8, 0), state.activeScreenConst(false).keyboard.flags);
    try std.testing.expectEqual(@as(u8, 0), state.activeScreenConst(true).keyboard.flags);
    try std.testing.expectEqual(@as(u8, 0), state.activeScreenConst(false).keyboard.len);
    try std.testing.expectEqual(@as(u8, 0), state.activeScreenConst(true).keyboard.len);
}
