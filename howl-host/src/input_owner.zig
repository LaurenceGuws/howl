//! Owns native-host keyboard delivery and host-local pane focus.
//!
//! Window copies interpreted Wayland/xkb facts into Boundary. This owner alone
//! performs potentially blocking Session action round trips so compositor
//! dispatch never waits on endpoint I/O. In duet mode it owns one connection
//! per pane. F6 toggles focus, F7/F8 move the focused divider, and F9 owns
//! the bounded one-to-two-pane split canary, and F10 closes only that
//! host-created second pane; these keys never enter a PTY.

const std = @import("std");
const client = @import("howl_client");
const wayland = @import("howl_wayland");
const c = @import("host_c");
const layout = @import("layout.zig");
const shared = @import("shared.zig");

const focus_toggle_keysym: u32 = 0xffc3; // F6
const grow_pane_keysym: u32 = 0xffc4; // F7
const shrink_pane_keysym: u32 = 0xffc5; // F8
const split_pane_keysym: u32 = 0xffc6; // F9
const close_pane_keysym: u32 = 0xffc7; // F10

pub const Command = union(enum) {
    ignored,
    committed_text: struct {
        len: u8,
        bytes: [wayland.input.key_text_limit]u8,
    },
    named: struct { key: u8, action: u8, modifiers: u8 },
    unicode: struct { scalar: u32, action: u8, modifiers: u8 },
};

pub fn run(
    boundary: *shared.Boundary,
    allocator: std.mem.Allocator,
    endpoint: []const u8,
    endpoint_right: ?[]const u8,
    mux: layout.Mux,
) void {
    runFallible(boundary, allocator, endpoint, endpoint_right, mux) catch |failure| {
        std.debug.print("Input failure: {s}\n", .{@errorName(failure)});
        boundary.requestStop(.input);
    };
    boundary.markStopped(.input);
}

fn runFallible(
    boundary: *shared.Boundary,
    allocator: std.mem.Allocator,
    endpoint: []const u8,
    endpoint_right: ?[]const u8,
    initial_mux: layout.Mux,
) !void {
    var connection_count: usize = if (endpoint_right != null) 2 else 1;
    var connections: [2]?client.Connection = .{ null, null };
    var initialized_count: usize = 0;
    defer {
        var index = initialized_count;
        while (index != 0) {
            index -= 1;
            connections[index].?.deinit();
        }
    }
    connections[0] = try client.Connection.connect(allocator, endpoint);
    initialized_count = 1;
    if (endpoint_right) |right| {
        connections[1] = try client.Connection.connect(allocator, right);
        initialized_count = 2;
    }

    var mux = initial_mux;
    var projection_storage: [layout.max_panes_per_tab]layout.Placement = undefined;
    const projected = try mux.activeLayout(.{ .width = 1024, .height = 1024 }, &projection_storage);
    if (projected.len != connection_count) return error.InputTopologyMismatch;
    var pane_ids: [2]layout.PaneId = undefined;
    for (projected, 0..) |placement, index| pane_ids[index] = placement.pane;
    const initial_focus_index = focusedConnectionIndex(
        &mux,
        pane_ids[0..connection_count],
    ) orelse return error.InputTopologyMismatch;
    if (initial_focus_index >= connection_count) return error.InputTopologyMismatch;

    var window_focused = false;
    var created_pane = false;
    var close_pending = false;
    while (!boundary.shouldStop()) {
        var consumed = false;
        if (boundary.takePaneRetired()) {
            consumed = true;
            if (connection_count != 2 or connections[1] == null)
                return error.InputTopologyMismatch;
            connections[1].?.deinit();
            connections[1] = null;
            initialized_count = 1;
            const target = pane_ids[1];
            const focus_changed = mux.focusPane(target) catch return error.InputTopologyMismatch;
            if (!focus_changed and mux.focusedPane() != target)
                return error.InputTopologyMismatch;
            const retired = try mux.closeFocused();
            if (retired != target or mux.paneCount() != 1)
                return error.InputTopologyMismatch;
            connection_count = 1;
            created_pane = false;
            close_pending = false;
            if (window_focused) try deliverFocus(&connections[0].?, true);
        }
        if (boundary.takePaneEndpoint()) |offered| {
            consumed = true;
            if (connection_count != 1 or connections[1] != null)
                return error.InputTopologyMismatch;
            const previous = focusedConnectionIndex(
                &mux,
                pane_ids[0..connection_count],
            ) orelse return error.InputTopologyMismatch;
            connections[1] = try client.Connection.connect(allocator, offered.text());
            initialized_count = 2;
            const new_pane = try mux.splitFocused(.horizontal);
            pane_ids[1] = new_pane;
            connection_count = 2;
            created_pane = true;
            const next = focusedConnectionIndex(
                &mux,
                pane_ids[0..connection_count],
            ) orelse return error.InputTopologyMismatch;
            if (next != 1) return error.InputTopologyMismatch;
            if (window_focused and previous != next) {
                try deliverFocus(&connections[previous].?, false);
                try deliverFocus(&connections[next].?, true);
            }
        }
        while (boundary.takeInput()) |event| {
            consumed = true;
            switch (event) {
                .focus => |focused| {
                    if (focused != window_focused) {
                        const active = focusedConnectionIndex(
                            &mux,
                            pane_ids[0..connection_count],
                        ) orelse return error.InputTopologyMismatch;
                        try deliverFocus(&connections[active].?, focused);
                        window_focused = focused;
                    }
                },
                .key => |key| {
                    if (close_pending) continue;
                    const host_resize = if (connection_count == 2) hostResizeCommand(key) else null;
                    if (isClosePane(key)) {
                        if (key.state == .pressed and connection_count == 2 and created_pane) {
                            const active = focusedConnectionIndex(
                                &mux,
                                pane_ids[0..connection_count],
                            ) orelse return error.InputTopologyMismatch;
                            if (active == 1) {
                                try boundary.publishHostCommand(.{
                                    .kind = .close_created,
                                    .pane = 1,
                                });
                                close_pending = true;
                            }
                        }
                    } else if (isSplitPane(key)) {
                        if (key.state == .pressed and connection_count == 1) {
                            const active = focusedConnectionIndex(
                                &mux,
                                pane_ids[0..connection_count],
                            ) orelse return error.InputTopologyMismatch;
                            try boundary.publishHostCommand(.{
                                .kind = .split_horizontal,
                                .pane = @intCast(active),
                            });
                        }
                    } else if (connection_count == 2 and isFocusToggle(key)) {
                        if (key.state == .pressed) {
                            const previous = focusedConnectionIndex(
                                &mux,
                                pane_ids[0..connection_count],
                            ) orelse return error.InputTopologyMismatch;
                            const next_pane = mux.focusNext();
                            const next = connectionIndexForPane(
                                pane_ids[0..connection_count],
                                next_pane,
                            ) orelse return error.InputTopologyMismatch;
                            if (window_focused and previous != next) {
                                try deliverFocus(&connections[previous].?, false);
                                try deliverFocus(&connections[next].?, true);
                            }
                        }
                    } else if (host_resize) |kind| {
                        if (key.state == .pressed) {
                            const active = focusedConnectionIndex(
                                &mux,
                                pane_ids[0..connection_count],
                            ) orelse return error.InputTopologyMismatch;
                            try boundary.publishHostCommand(.{
                                .kind = kind,
                                .pane = @intCast(active),
                            });
                        }
                    } else {
                        const active = focusedConnectionIndex(
                            &mux,
                            pane_ids[0..connection_count],
                        ) orelse return error.InputTopologyMismatch;
                        try deliverKey(&connections[active].?, key);
                    }
                },
            }
            if (boundary.shouldStop()) return;
        }
        if (!consumed) try waitInput(boundary);
    }
}

fn deliverFocus(connection: *client.Connection, focused: bool) !void {
    try client.actions.focus(
        connection,
        @fromBackingInt(@as(u8, if (focused) 1 else 2)),
    );
}

fn focusedConnectionIndex(mux: *const layout.Mux, pane_ids: []const layout.PaneId) ?usize {
    return connectionIndexForPane(pane_ids, mux.focusedPane());
}

fn connectionIndexForPane(pane_ids: []const layout.PaneId, pane: layout.PaneId) ?usize {
    for (pane_ids, 0..) |candidate, index| if (candidate == pane) return index;
    return null;
}

fn isFocusToggle(key: wayland.input.Key) bool {
    return @backingInt(key.keysym) == focus_toggle_keysym;
}

fn isClosePane(key: wayland.input.Key) bool {
    return @backingInt(key.keysym) == close_pane_keysym;
}

fn isSplitPane(key: wayland.input.Key) bool {
    return @backingInt(key.keysym) == split_pane_keysym;
}

fn hostResizeCommand(key: wayland.input.Key) ?shared.HostCommandKind {
    return switch (@backingInt(key.keysym)) {
        grow_pane_keysym => .grow_focused,
        shrink_pane_keysym => .shrink_focused,
        else => null,
    };
}

fn deliverKey(connection: *client.Connection, key: wayland.input.Key) !void {
    switch (projectKey(key)) {
        .ignored => {},
        .committed_text => |text| try client.actions.committedText(
            connection,
            text.bytes[0..text.len],
        ),
        .named => |named| try client.actions.namedKey(
            connection,
            @fromBackingInt(@intCast(named.key)),
            @fromBackingInt(@intCast(named.action)),
            named.modifiers,
        ),
        .unicode => |unicode| try client.actions.unicodeKey(
            connection,
            unicode.scalar,
            @fromBackingInt(@intCast(unicode.action)),
            unicode.modifiers,
        ),
    }
}

pub fn projectKey(key: wayland.input.Key) Command {
    const action: u8 = switch (key.state) {
        .pressed => 1,
        .repeated => 2,
        .released => 3,
    };
    const modifiers = modifierBits(key.semantic_modifiers);
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

fn modifierBits(value: wayland.input.SemanticModifiers) u8 {
    var result: u8 = 0;
    if (value.shift) result |= 1 << 0;
    if (value.alt) result |= 1 << 1;
    if (value.control) result |= 1 << 2;
    if (value.super) result |= 1 << 3;
    if (value.hyper) result |= 1 << 4;
    if (value.meta) result |= 1 << 5;
    if (value.caps_lock) result |= 1 << 6;
    if (value.num_lock) result |= 1 << 7;
    return result;
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

fn waitInput(boundary: *shared.Boundary) !void {
    var descriptor = c.pollfd{ .fd = boundary.inputFd(), .events = c.POLLIN, .revents = 0 };
    while (true) {
        const ready = c.poll(&descriptor, 1, -1);
        if (ready > 0) return boundary.drainInputWake();
        if (ready < 0 and std.c.errno(ready) == .INTR) continue;
        return error.Wake;
    }
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

test "F6 is the exact host focus toggle key" {
    try std.testing.expect(isFocusToggle(makeKey(focus_toggle_keysym, .pressed, "", .{})));
    try std.testing.expect(isFocusToggle(makeKey(focus_toggle_keysym, .released, "", .{})));
    try std.testing.expect(!isFocusToggle(makeKey(0xffc2, .pressed, "", .{})));
}

test "F10 is the exact host-created-pane close key" {
    try std.testing.expect(isClosePane(makeKey(close_pane_keysym, .pressed, "", .{})));
    try std.testing.expect(isClosePane(makeKey(close_pane_keysym, .released, "", .{})));
    try std.testing.expect(!isClosePane(makeKey(split_pane_keysym, .pressed, "", .{})));
}

test "F9 is the exact host split key" {
    try std.testing.expect(isSplitPane(makeKey(split_pane_keysym, .pressed, "", .{})));
    try std.testing.expect(isSplitPane(makeKey(split_pane_keysym, .released, "", .{})));
    try std.testing.expect(!isSplitPane(makeKey(shrink_pane_keysym, .pressed, "", .{})));
}

test "F7 and F8 are exact host divider commands" {
    try std.testing.expectEqual(
        shared.HostCommandKind.grow_focused,
        hostResizeCommand(makeKey(grow_pane_keysym, .pressed, "", .{})).?,
    );
    try std.testing.expectEqual(
        shared.HostCommandKind.shrink_focused,
        hostResizeCommand(makeKey(shrink_pane_keysym, .released, "", .{})).?,
    );
    try std.testing.expect(hostResizeCommand(makeKey(focus_toggle_keysym, .pressed, "", .{})) == null);
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
