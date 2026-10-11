//! Owns direct keyboard, mouse, focus, PTY service, and Instance input.
//!
//! Window copies interpreted Wayland/xkb facts into Boundary. This owner alone
//! mutates the in-process Instance and services its PTY/VT lifetime so compositor
//! dispatch and presentation never own terminal progress.

const std = @import("std");
const protocol = @import("howl_instance").protocol;
const wayland = @import("howl_wayland");
const c = @import("host_c");
const local_terminal = @import("local_terminal");
const instance = @import("howl_instance");
const scrollback = @import("host_scrollback");
const shared = @import("shared.zig");

pub const Command = union(enum) {
    ignored,
    committed_text: struct {
        len: u8,
        bytes: [wayland.input.key_text_limit]u8,
    },
    named: struct { key: u8, action: u8, modifiers: u8 },
    unicode: struct { scalar: u32, action: u8, modifiers: u8 },
};

/// Owns host input and PTY/VT service for the one direct in-process Instance.
pub fn run(
    boundary: *shared.Boundary,
    owner: *local_terminal.Owner,
) void {
    runFallible(boundary, owner) catch |failure| {
        std.debug.print("Local input failure: {s}\n", .{@errorName(failure)});
        boundary.requestStop(.input);
    };
    boundary.markStopped(.input);
}

fn runFallible(
    boundary: *shared.Boundary,
    owner: *local_terminal.Owner,
) !void {
    var window_focused = false;
    while (!boundary.shouldStop()) {
        const state = owner.pollState();
        var descriptors = [_]c.pollfd{
            .{
                .fd = boundary.inputFd(),
                .events = @intCast(c.POLLIN),
                .revents = 0,
            },
            .{
                .fd = state.descriptor,
                .events = @intCast(if (state.descriptor < 0)
                    0
                else if (state.stream_closed)
                    (if (state.write_pending) c.POLLOUT else 0)
                else
                    c.POLLIN | c.POLLHUP | (if (state.write_pending) c.POLLOUT else 0)),
                .revents = 0,
            },
        };
        const timeout: c_int = @intCast(@min(
            if (state.read_pending and !state.write_pending) 0 else state.animation_wait_ms orelse 100,
            @as(u32, 100),
        ));
        const ready = c.poll(&descriptors, descriptors.len, timeout);
        if (ready < 0) {
            if (std.c.errno(ready) == .INTR) continue;
            return error.Wake;
        }
        if (boundary.shouldStop()) return;

        const input_events = descriptors[0].revents;
        if (input_events & (c.POLLERR | c.POLLHUP | c.POLLNVAL) != 0)
            return error.Wake;
        if (input_events & c.POLLIN != 0) try boundary.drainInputWake();

        const pty_events = descriptors[1].revents;
        if (pty_events & (c.POLLERR | c.POLLNVAL) != 0)
            return error.PtyPoll;
        const readable = state.descriptor >= 0 and
            pty_events & (c.POLLIN | c.POLLHUP) != 0;

        var consumed: usize = 0;
        while (consumed < shared.input_capacity) : (consumed += 1) {
            const event = boundary.takeInput() orelse break;
            switch (event) {
                .focus => |focused| {
                    if (focused != window_focused) {
                        try deliverFocusLocal(owner, focused);
                        window_focused = focused;
                    }
                },
                .mouse => |mouse| {
                    if (mouse.scene_index != 0) return error.InputTopologyMismatch;
                    try deliverMouseLocal(owner, mouse);
                },
                .geometry => |geometry| {
                    if (geometry.width == 0 or geometry.height == 0)
                        return error.InputTopologyMismatch;
                    if (geometry.font_pixels) |pixels| {
                        if (pixels == 0) return error.InputTopologyMismatch;
                        _ = try owner.reconfigurePresentationSurface(
                            pixels,
                            geometry.width,
                            geometry.height,
                        );
                    } else {
                        _ = try owner.resizeSurface(
                            geometry.width,
                            geometry.height,
                        );
                    }
                },
                .key => |key| {
                    try deliverKeyLocal(owner, key);
                },
            }
            if (boundary.shouldStop()) return;
        }

        // Input admission queues bytes but intentionally does not flush them.
        // An input turn may therefore optimistically attempt the nonblocking
        // write; EAGAIN is retained as write_pending for the next POLLOUT turn.
        const writable = state.write_pending or consumed != 0 or
            (state.descriptor >= 0 and pty_events & c.POLLOUT != 0);
        const serviced = try owner.service(
            readable,
            writable,
            try local_terminal.monotonicNs(),
        );
        if (serviced.stream_closed and serviced.child_exit != null and !serviced.write_pending) {
            boundary.requestStop(null);
            return;
        }
    }
}

fn deliverMouseLocal(
    owner: *local_terminal.Owner,
    mouse: shared.RoutedMouse,
) !void {
    if (mouse.value.kind != .wheel) {
        try owner.input(.{ .mouse = nativeMouse(mouse.value) });
        return;
    }
    const amount: i16 = switch (mouse.value.button) {
        .wheel_up => 3,
        .wheel_down => -3,
        else => return error.InputTopologyMismatch,
    };
    const force_history =
        mouse.value.modifiers & protocol.typed_input.modifiers.shift != 0;
    const context = owner.pointerContext();
    const route = scrollback.routeWheel(
        context.history_active,
        force_history,
        true,
        context.interaction.mouse_tracking != .off,
        context.alternate_screen,
        context.interaction.alternate_scroll,
    );
    switch (route) {
        .history => _ = try owner.scrollHistory(amount),
        .terminal_mouse => try owner.input(.{ .mouse = nativeMouse(mouse.value) }),
        .alternate_scroll => {
            const key: instance.KeyName = if (amount > 0) .up else .down;
            try owner.input(.{ .key = .{ .key = .{ .named = key }, .action = .press } });
            try owner.input(.{ .key = .{ .key = .{ .named = key }, .action = .release } });
        },
        .ignore => {},
        .interaction_state => return error.InputTopologyMismatch,
    }
}

fn deliverFocusLocal(owner: *local_terminal.Owner, focused: bool) !void {
    try owner.input(.{ .focus = if (focused) .in else .out });
}

fn deliverKeyLocal(owner: *local_terminal.Owner, key: wayland.input.Key) !void {
    switch (projectKey(key)) {
        .ignored => {},
        .committed_text => |text| {
            const bytes = text.bytes[0..text.len];
            if (bytes.len == 0 or !std.unicode.utf8ValidateSlice(bytes))
                return error.InvalidText;
            try owner.input(.{ .bytes = bytes });
        },
        .named => |named| try owner.input(.{ .key = .{
            .key = .{ .named = nativeNamedKey(named.key) orelse return error.InvalidKey },
            .action = nativeAction(named.action) orelse return error.InvalidKey,
            .mods = nativeModifiers(named.modifiers),
        } }),
        .unicode => |unicode| {
            const scalar = std.math.cast(u21, unicode.scalar) orelse
                return error.InvalidUnicodeScalar;
            try owner.input(.{ .key = .{
                .key = try instance.Key.initUnicode(scalar),
                .action = nativeAction(unicode.action) orelse return error.InvalidKey,
                .mods = nativeModifiers(unicode.modifiers),
            } });
        },
    }
}

fn nativeAction(value: u8) ?instance.KeyAction {
    return switch (value) {
        1 => .press,
        2 => .repeat,
        3 => .release,
        else => null,
    };
}

fn nativeModifiers(value: u8) instance.InputModifier {
    return .{
        .shift = value & protocol.typed_input.modifiers.shift != 0,
        .alt = value & protocol.typed_input.modifiers.alt != 0,
        .control = value & protocol.typed_input.modifiers.control != 0,
        .super = value & protocol.typed_input.modifiers.super != 0,
        .hyper = value & protocol.typed_input.modifiers.hyper != 0,
        .meta = value & protocol.typed_input.modifiers.meta != 0,
        .caps_lock = value & protocol.typed_input.modifiers.caps_lock != 0,
        .num_lock = value & protocol.typed_input.modifiers.num_lock != 0,
    };
}

fn nativeMouse(value: protocol.MouseInput) @FieldType(instance.Input, "mouse") {
    return .{
        .kind = switch (value.kind) {
            .press => .press,
            .release => .release,
            .move => .move,
            .wheel => .wheel,
        },
        .button = switch (value.button) {
            .none => .none,
            .left => .left,
            .middle => .middle,
            .right => .right,
            .wheel_up => .wheel_up,
            .wheel_down => .wheel_down,
        },
        .row = value.row,
        .col = value.column,
        .pixel_x = value.pixel_x,
        .pixel_y = value.pixel_y,
        .mod = nativeModifiers(value.modifiers),
        .buttons_down = value.buttons_down,
    };
}

fn nativeNamedKey(value: u8) ?instance.KeyName {
    return switch (value) {
        1 => .enter,
        2 => .tab,
        3 => .backspace,
        4 => .escape,
        5 => .up,
        6 => .down,
        7 => .left,
        8 => .right,
        9 => .insert,
        10 => .delete,
        11 => .home,
        12 => .end,
        13 => .page_up,
        14 => .page_down,
        15 => .left_shift,
        16 => .right_shift,
        17 => .left_control,
        18 => .right_control,
        19 => .left_alt,
        20 => .right_alt,
        21 => .left_super,
        22 => .right_super,
        23 => .left_hyper,
        24 => .right_hyper,
        25 => .left_meta,
        26 => .right_meta,
        27 => .caps_lock,
        28 => .num_lock,
        29 => .f1,
        30 => .f2,
        31 => .f3,
        32 => .f4,
        33 => .f5,
        34 => .f6,
        35 => .f7,
        36 => .f8,
        37 => .f9,
        38 => .f10,
        39 => .f11,
        40 => .f12,
        41 => .keypad_0,
        42 => .keypad_1,
        43 => .keypad_2,
        44 => .keypad_3,
        45 => .keypad_4,
        46 => .keypad_5,
        47 => .keypad_6,
        48 => .keypad_7,
        49 => .keypad_8,
        50 => .keypad_9,
        51 => .keypad_decimal,
        52 => .keypad_add,
        53 => .keypad_subtract,
        54 => .keypad_multiply,
        55 => .keypad_divide,
        56 => .keypad_separator,
        57 => .keypad_equal,
        58 => .keypad_enter,
        else => null,
    };
}

pub fn projectKey(key: wayland.input.Key) Command {
    const action: u8 = switch (key.state) {
        .pressed => 1,
        .repeated => 2,
        .released => 3,
    };
    const modifiers = shared.semanticModifierBits(key.semantic_modifiers);
    if (namedKey(@backingInt(key.keysym))) |named|
        return .{ .named = .{ .key = named, .action = action, .modifiers = modifiers } };

    const typed_modifiers = key.semantic_modifiers.control or
        key.semantic_modifiers.alt or
        key.semantic_modifiers.super or
        key.semantic_modifiers.hyper or
        key.semantic_modifiers.meta;
    if (typed_modifiers) {
        const scalar = unicodeKeysym(@backingInt(key.keysym)) orelse return .ignored;
        return .{ .unicode = .{ .scalar = scalar, .action = action, .modifiers = modifiers } };
    }

    if (key.state == .released or key.text_len == 0) return .ignored;
    return .{ .committed_text = .{ .len = key.text_len, .bytes = key.text } };
}

fn namedKey(keysym: u32) ?u8 {
    return switch (keysym) {
        0xff0d => 1, // Return
        0xff09, 0xfe20 => 2, // Tab / ISO Left Tab
        0xff08 => 3, // Backspace
        0xff1b => 4, // Escape
        0xff52 => 5,
        0xff54 => 6,
        0xff51 => 7,
        0xff53 => 8,
        0xff63 => 9, // Insert
        0xffff => 10, // Delete
        0xff50 => 11,
        0xff57 => 12,
        0xff55 => 13,
        0xff56 => 14,
        0xffe1 => 15,
        0xffe2 => 16,
        0xffe3 => 17,
        0xffe4 => 18,
        0xffe9 => 19,
        0xffea => 20,
        0xffeb => 21,
        0xffec => 22,
        0xffed => 23,
        0xffee => 24,
        0xffe7 => 25,
        0xffe8 => 26,
        0xffe5 => 27,
        0xff7f => 28,
        0xffbe...0xffc9 => @intCast(29 + (keysym - 0xffbe)), // F1..F12
        0xffb0...0xffb9 => @intCast(41 + (keysym - 0xffb0)), // KP 0..9
        0xffae => 51, // KP decimal
        0xffab => 52,
        0xffad => 53,
        0xffaa => 54,
        0xffaf => 55,
        0xffac => 56, // KP separator
        0xffbd => 57, // KP equal
        0xff8d => 58, // KP enter
        else => null,
    };
}

fn unicodeKeysym(keysym: u32) ?u32 {
    if ((keysym >= 0x20 and keysym <= 0x7e) or
        (keysym >= 0xa0 and keysym <= 0xff)) return keysym;
    if (keysym >= 0x01000100 and keysym <= 0x0110ffff) {
        const scalar = keysym & 0x00ffffff;
        if (scalar >= 0xd800 and scalar <= 0xdfff) return null;
        return scalar;
    }
    return null;
}

fn makeKey(keysym: u32, state: wayland.input.KeyState, text: []const u8, modifiers: wayland.input.SemanticModifiers) wayland.input.Key {
    var result = wayland.input.Key{
        .keycode = 0,
        .time = 0,
        .state = state,
        .serial = 0,
        .modifiers = .{ .serial = 0, .depressed = 0, .latched = 0, .locked = 0, .group = 0 },
        .semantic_modifiers = modifiers,
        .keysym = @fromBackingInt(keysym),
        .text_len = @intCast(text.len),
        .text = @splat(0),
    };
    @memcpy(result.text[0..text.len], text);
    return result;
}

test "plain printable key commits text only on press and repeat" {
    const pressed = projectKey(makeKey('A', .pressed, "A", .{ .shift = true }));
    try std.testing.expectEqualStrings("A", pressed.committed_text.bytes[0..pressed.committed_text.len]);
    const repeated = projectKey(makeKey('a', .repeated, "a", .{}));
    try std.testing.expectEqualStrings("a", repeated.committed_text.bytes[0..repeated.committed_text.len]);
    try std.testing.expect(projectKey(makeKey('a', .released, "a", .{})) == .ignored);
}

test "control printable preserves typed physical transition and modifiers" {
    const projected = projectKey(makeKey('c', .pressed, "\x03", .{ .control = true, .num_lock = true }));
    try std.testing.expectEqual(@as(u32, 'c'), projected.unicode.scalar);
    try std.testing.expectEqual(@as(u8, 1), projected.unicode.action);
    try std.testing.expectEqual(@as(u8, (1 << 2) | (1 << 7)), projected.unicode.modifiers);
}

test "named keys preserve release identity without relying on text" {
    const projected = projectKey(makeKey(0xff51, .released, "", .{ .alt = true }));
    try std.testing.expectEqual(@as(u8, 7), projected.named.key);
    try std.testing.expectEqual(@as(u8, 3), projected.named.action);
    try std.testing.expectEqual(@as(u8, 1 << 1), projected.named.modifiers);
}

test "unicode encoded keysym maps to scalar for modified chords" {
    const projected = projectKey(makeKey(0x010003bb, .pressed, "λ", .{ .alt = true }));
    try std.testing.expectEqual(@as(u32, 0x03bb), projected.unicode.scalar);
}

test "local native modifiers preserve every protocol bit explicitly" {
    const modifiers = nativeModifiers(
        protocol.typed_input.modifiers.shift |
            protocol.typed_input.modifiers.alt |
            protocol.typed_input.modifiers.control |
            protocol.typed_input.modifiers.super |
            protocol.typed_input.modifiers.hyper |
            protocol.typed_input.modifiers.meta |
            protocol.typed_input.modifiers.caps_lock |
            protocol.typed_input.modifiers.num_lock,
    );
    try std.testing.expect(modifiers.shift);
    try std.testing.expect(modifiers.alt);
    try std.testing.expect(modifiers.control);
    try std.testing.expect(modifiers.super);
    try std.testing.expect(modifiers.hyper);
    try std.testing.expect(modifiers.meta);
    try std.testing.expect(modifiers.caps_lock);
    try std.testing.expect(modifiers.num_lock);
}

test "local named-key conversion preserves protocol identities and actions" {
    try std.testing.expectEqual(instance.KeyName.up, nativeNamedKey(5).?);
    try std.testing.expectEqual(instance.KeyName.f12, nativeNamedKey(40).?);
    try std.testing.expectEqual(instance.KeyName.keypad_enter, nativeNamedKey(58).?);
    try std.testing.expect(nativeNamedKey(0) == null);
    try std.testing.expectEqual(instance.KeyAction.press, nativeAction(1).?);
    try std.testing.expectEqual(instance.KeyAction.repeat, nativeAction(2).?);
    try std.testing.expectEqual(instance.KeyAction.release, nativeAction(3).?);
    try std.testing.expect(nativeAction(0) == null);
}

test "local mouse conversion preserves semantic route facts" {
    const value = nativeMouse(.{
        .kind = .wheel,
        .button = .wheel_up,
        .row = 7,
        .column = 9,
        .pixel_x = 13,
        .pixel_y = 17,
        .modifiers = protocol.typed_input.modifiers.control |
            protocol.typed_input.modifiers.shift,
        .buttons_down = 1,
    });
    try std.testing.expectEqual(instance.MouseEventKind.wheel, value.kind);
    try std.testing.expectEqual(instance.MouseButton.wheel_up, value.button);
    try std.testing.expectEqual(@as(u16, 7), value.row);
    try std.testing.expectEqual(@as(u16, 9), value.col);
    try std.testing.expectEqual(@as(u16, 13), value.pixel_x);
    try std.testing.expectEqual(@as(u16, 17), value.pixel_y);
    try std.testing.expect(value.mod.control);
    try std.testing.expect(value.mod.shift);
    try std.testing.expectEqual(@as(u8, 1), value.buttons_down);
}
