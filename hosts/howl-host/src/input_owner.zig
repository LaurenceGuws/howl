//! Owns direct keyboard, mouse, focus, PTY service, and Instance input.
//!
//! Window copies interpreted Wayland/xkb facts into Boundary. This owner alone
//! mutates the in-process Instance and services its PTY/VT lifetime so compositor
//! dispatch and presentation never own terminal progress.

const std = @import("std");
const wayland = @import("howl_wayland");
const c = @import("host_c");
const local_terminal = @import("local_terminal");
const instance = @import("howl_instance");
const scrollback = @import("host_scrollback");
const shared = @import("shared.zig");

/// Host input projected into semantic terminal or local layout operations.
pub const Command = union(enum) {
    ignored,
    committed_text: struct {
        len: u8,
        bytes: [wayland.input.key_text_limit]u8,
    },
    named: struct { key: instance.KeyName, action: instance.KeyAction, modifiers: instance.InputModifier },
    unicode: struct { scalar: u21, action: instance.KeyAction, modifiers: instance.InputModifier },
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
                        // zig-audit: acknowledge discard
                        // reason: This input command applies the requested presentation geometry; subsequent observation supplies authoritative dimensions.
                        _ = try owner.reconfigurePresentationSurface(
                            pixels,
                            geometry.width,
                            geometry.height,
                        );
                    } else {
                        // zig-audit: acknowledge discard
                        // reason: This input command applies the requested presentation geometry; subsequent observation supplies authoritative dimensions.
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
        try owner.input(.{ .mouse = mouse.value });
        return;
    }
    const amount: i16 = switch (mouse.value.button) {
        .wheel_up => 3,
        .wheel_down => -3,
        else => return error.InputTopologyMismatch,
    };
    const force_history = mouse.value.mod.shift;
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
        // zig-audit: acknowledge discard
        // reason: Wheel routing applies bounded history movement; the next observation supplies the resulting offset.
        .history => _ = try owner.scrollHistory(amount),
        .terminal_mouse => try owner.input(.{ .mouse = mouse.value }),
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
            .key = .{ .named = named.key },
            .action = named.action,
            .mods = named.modifiers,
        } }),
        .unicode => |unicode| {
            try owner.input(.{ .key = .{
                .key = try instance.Key.initUnicode(unicode.scalar),
                .action = unicode.action,
                .mods = unicode.modifiers,
            } });
        },
    }
}

/// Projects one compositor key into a bounded host command.
pub fn projectKey(key: wayland.input.Key) Command {
    const action: instance.KeyAction = switch (key.state) {
        .pressed => .press,
        .repeated => .repeat,
        .released => .release,
    };
    const modifiers = shared.semanticModifiers(key.semantic_modifiers);
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

fn namedKey(keysym: u32) ?instance.KeyName {
    return switch (keysym) {
        0xff0d => .enter, // Return
        0xff09, 0xfe20 => .tab, // Tab / ISO Left Tab
        0xff08 => .backspace, // Backspace
        0xff1b => .escape, // Escape
        0xff52 => .up,
        0xff54 => .down,
        0xff51 => .left,
        0xff53 => .right,
        0xff63 => .insert, // Insert
        0xffff => .delete, // Delete
        0xff50 => .home,
        0xff57 => .end,
        0xff55 => .page_up,
        0xff56 => .page_down,
        0xffe1 => .left_shift,
        0xffe2 => .right_shift,
        0xffe3 => .left_control,
        0xffe4 => .right_control,
        0xffe9 => .left_alt,
        0xffea => .right_alt,
        0xffeb => .left_super,
        0xffec => .right_super,
        0xffed => .left_hyper,
        0xffee => .right_hyper,
        0xffe7 => .left_meta,
        0xffe8 => .right_meta,
        0xffe5 => .caps_lock,
        0xff7f => .num_lock,
        0xffbe => .f1,
        0xffbf => .f2,
        0xffc0 => .f3,
        0xffc1 => .f4,
        0xffc2 => .f5,
        0xffc3 => .f6,
        0xffc4 => .f7,
        0xffc5 => .f8,
        0xffc6 => .f9,
        0xffc7 => .f10,
        0xffc8 => .f11,
        0xffc9 => .f12,
        0xffb0 => .keypad_0,
        0xffb1 => .keypad_1,
        0xffb2 => .keypad_2,
        0xffb3 => .keypad_3,
        0xffb4 => .keypad_4,
        0xffb5 => .keypad_5,
        0xffb6 => .keypad_6,
        0xffb7 => .keypad_7,
        0xffb8 => .keypad_8,
        0xffb9 => .keypad_9,
        0xffae => .keypad_decimal, // KP decimal
        0xffab => .keypad_add,
        0xffad => .keypad_subtract,
        0xffaa => .keypad_multiply,
        0xffaf => .keypad_divide,
        0xffac => .keypad_separator, // KP separator
        0xffbd => .keypad_equal, // KP equal
        0xff8d => .keypad_enter, // KP enter
        else => null,
    };
}

fn unicodeKeysym(keysym: u32) ?u21 {
    if ((keysym >= 0x20 and keysym <= 0x7e) or
        (keysym >= 0xa0 and keysym <= 0xff)) return @intCast(keysym);
    if (keysym >= 0x01000100 and keysym <= 0x0110ffff) {
        const scalar = keysym & 0x00ffffff;
        if (scalar >= 0xd800 and scalar <= 0xdfff) return null;
        return @intCast(scalar);
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
    try std.testing.expectEqual(@as(u21, 'c'), projected.unicode.scalar);
    try std.testing.expectEqual(instance.KeyAction.press, projected.unicode.action);
    try std.testing.expectEqualDeep(instance.InputModifier{ .control = true, .num_lock = true }, projected.unicode.modifiers);
}

test "named keys preserve release identity without relying on text" {
    const projected = projectKey(makeKey(0xff51, .released, "", .{ .alt = true }));
    try std.testing.expectEqual(instance.KeyName.left, projected.named.key);
    try std.testing.expectEqual(instance.KeyAction.release, projected.named.action);
    try std.testing.expectEqualDeep(instance.InputModifier{ .alt = true }, projected.named.modifiers);
}

test "unicode encoded keysym maps to scalar for modified chords" {
    const projected = projectKey(makeKey(0x010003bb, .pressed, "λ", .{ .alt = true }));
    try std.testing.expectEqual(@as(u21, 0x03bb), projected.unicode.scalar);
}

test "semantic modifiers preserve every canonical flag" {
    const projected = projectKey(makeKey('x', .repeated, "", .{
        .shift = true,
        .alt = true,
        .control = true,
        .super = true,
        .hyper = true,
        .meta = true,
        .caps_lock = true,
        .num_lock = true,
    }));
    try std.testing.expectEqual(instance.KeyAction.repeat, projected.unicode.action);
    try std.testing.expectEqualDeep(instance.InputModifier{
        .shift = true,
        .alt = true,
        .control = true,
        .super = true,
        .hyper = true,
        .meta = true,
        .caps_lock = true,
        .num_lock = true,
    }, projected.unicode.modifiers);
}

test "named input preserves function and keypad keys without wire identities" {
    try std.testing.expectEqual(instance.KeyName.f1, projectKey(makeKey(0xffbe, .pressed, "", .{})).named.key);
    try std.testing.expectEqual(instance.KeyName.f12, projectKey(makeKey(0xffc9, .pressed, "", .{})).named.key);
    try std.testing.expectEqual(instance.KeyName.keypad_0, projectKey(makeKey(0xffb0, .pressed, "", .{})).named.key);
    try std.testing.expectEqual(instance.KeyName.keypad_enter, projectKey(makeKey(0xff8d, .pressed, "", .{})).named.key);
}

test "invalid Unicode keysyms do not become terminal input" {
    try std.testing.expect(std.meta.activeTag(projectKey(makeKey(0x0100d800, .pressed, "", .{ .control = true }))) == .ignored);
    try std.testing.expect(std.meta.activeTag(projectKey(makeKey(0x01110000, .pressed, "", .{ .alt = true }))) == .ignored);
}
