//! Owns native-host keyboard, mouse, focus delivery and host-local pane focus.
//!
//! Window copies interpreted Wayland/xkb facts into Boundary. This owner alone
//! performs potentially blocking Session action round trips so compositor
//! dispatch never waits on endpoint I/O. In duet mode it owns one connection
//! per pane. F6 toggles focus, F7/F8 move the focused divider, and F9 owns
//! bounded left/right or top/bottom split canary, and F10 closes only that
//! host-created second pane; these keys never enter a PTY.

const std = @import("std");
const client = @import("howl_client");
const protocol = @import("howl_session").protocol;
const wayland = @import("howl_wayland");
const c = @import("host_c");
const layout = @import("layout.zig");
const local_terminal = @import("local_terminal");
const session = @import("howl_session");
const scrollback = @import("scrollback.zig");
const shared = @import("shared.zig");

const next_tab_keysym: u32 = 0xffc2; // F5
const focus_toggle_keysym: u32 = 0xffc3; // F6
const grow_pane_keysym: u32 = 0xffc4; // F7
const shrink_pane_keysym: u32 = 0xffc5; // F8
const split_pane_keysym: u32 = 0xffc6; // F9
const close_pane_keysym: u32 = 0xffc7; // F10
const split_vertical_keysym: u32 = 0xffc8; // F11
const new_tab_keysym: u32 = 0xffc9; // F12

const CreatedKind = enum { none, split, tab };

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
    var created_kind: CreatedKind = .none;
    var close_pending = false;
    var tab_switch_pending = false;
    while (!boundary.shouldStop()) {
        var consumed = false;
        if (boundary.takePaneFocus()) |focus_index_u8| {
            consumed = true;
            const focus_index: usize = focus_index_u8;
            if (focus_index >= connection_count) return error.InputTopologyMismatch;
            const previous = focusedConnectionIndex(
                &mux,
                pane_ids[0..connection_count],
            ) orelse return error.InputTopologyMismatch;
            const target = pane_ids[focus_index];
            const focus_changed = mux.focusPane(target) catch return error.InputTopologyMismatch;
            if (!focus_changed and mux.focusedPane() != target)
                return error.InputTopologyMismatch;
            if (window_focused and previous != focus_index) {
                try deliverFocus(&connections[previous].?, false);
                try deliverFocus(&connections[focus_index].?, true);
            }
        }
        if (boundary.takePaneRetired()) {
            consumed = true;
            if (connection_count != 2 or connections[1] == null or created_kind == .none)
                return error.InputTopologyMismatch;
            connections[1].?.deinit();
            connections[1] = null;
            initialized_count = 1;
            const target = pane_ids[1];
            switch (created_kind) {
                .split => {
                    const focus_changed = mux.focusPane(target) catch return error.InputTopologyMismatch;
                    if (!focus_changed and mux.focusedPane() != target)
                        return error.InputTopologyMismatch;
                    const retired = try mux.closeFocused();
                    if (retired != target or mux.paneCount() != 1)
                        return error.InputTopologyMismatch;
                },
                .tab => {
                    if (mux.focusedPane() != target or mux.tabCount() != 2)
                        return error.InputTopologyMismatch;
                    try mux.closeActiveTab();
                    if (mux.tabCount() != 1 or mux.paneCount() != 1)
                        return error.InputTopologyMismatch;
                },
                .none => unreachable,
            }
            connection_count = 1;
            created_kind = .none;
            close_pending = false;
            tab_switch_pending = false;
            if (window_focused) try deliverFocus(&connections[0].?, true);
        }
        if (boundary.takePaneEndpoint()) |offered| {
            consumed = true;
            if (connection_count != 1 or connections[1] != null or created_kind != .none)
                return error.InputTopologyMismatch;
            const previous = focusedConnectionIndex(
                &mux,
                pane_ids[0..connection_count],
            ) orelse return error.InputTopologyMismatch;
            connections[1] = try client.Connection.connect(allocator, offered.text());
            initialized_count = 2;
            const new_pane = switch (offered.kind) {
                .split_horizontal => try mux.splitFocused(.horizontal),
                .split_vertical => try mux.splitFocused(.vertical),
                .tab => (try mux.createTab()).pane,
            };
            created_kind = switch (offered.kind) {
                .split_horizontal, .split_vertical => .split,
                .tab => .tab,
            };
            pane_ids[1] = new_pane;
            connection_count = 2;
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
        if (boundary.takeTabSwitched()) {
            consumed = true;
            if (connection_count != 2 or created_kind != .tab or !tab_switch_pending)
                return error.InputTopologyMismatch;
            const previous = focusedConnectionIndex(&mux, pane_ids[0..connection_count]) orelse
                return error.InputTopologyMismatch;
            if (!mux.nextTab()) return error.InputTopologyMismatch;
            const next = focusedConnectionIndex(&mux, pane_ids[0..connection_count]) orelse
                return error.InputTopologyMismatch;
            if (window_focused and previous != next) {
                try deliverFocus(&connections[previous].?, false);
                try deliverFocus(&connections[next].?, true);
            }
            tab_switch_pending = false;
        }
        if (!close_pending and !tab_switch_pending) while (boundary.takeInput()) |event| {
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
                .mouse => |mouse| {
                    const target: usize = mouse.scene_index;
                    if (target >= connection_count or connections[target] == null)
                        return error.InputTopologyMismatch;
                    try deliverMouse(
                        boundary,
                        &connections[target].?,
                        mouse,
                    );
                },
                .key => |key| {
                    const split_topology = connection_count == 2 and mux.tabCount() == 1;
                    const host_resize = if (split_topology) hostResizeCommand(key) else null;
                    if (isClosePane(key)) {
                        if (key.state == .pressed and connection_count == 2 and created_kind != .none) {
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
                    } else if (isNewTab(key)) {
                        if (key.state == .pressed and connection_count == 1) {
                            try boundary.publishHostCommand(.{ .kind = .new_tab, .pane = 0 });
                        }
                    } else if (isNextTab(key)) {
                        if (key.state == .pressed and connection_count == 2 and created_kind == .tab) {
                            try boundary.publishHostCommand(.{ .kind = .next_tab, .pane = 0 });
                            tab_switch_pending = true;
                        }
                    } else if (hostSplitCommand(key)) |split_command| {
                        if (key.state == .pressed and connection_count == 1) {
                            const active = focusedConnectionIndex(
                                &mux,
                                pane_ids[0..connection_count],
                            ) orelse return error.InputTopologyMismatch;
                            try boundary.publishHostCommand(.{
                                .kind = split_command,
                                .pane = @intCast(active),
                            });
                        }
                    } else if (split_topology and isFocusToggle(key)) {
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
            if (close_pending or tab_switch_pending) break;
        };
        if (!consumed) try waitInput(boundary);
    }
}

/// Owns one-pane host input for an in-process Session. The remote multi-pane
/// runner remains unchanged; unsupported local split/tab shortcuts stay
/// reserved rather than spawning an endpoint-backed sibling.
pub fn runLocal(
    boundary: *shared.Boundary,
    owner: *local_terminal.Owner,
    mux: layout.Mux,
) void {
    runLocalFallible(boundary, owner, mux) catch |failure| {
        std.debug.print("Local input failure: {s}\n", .{@errorName(failure)});
        boundary.requestStop(.input);
    };
    boundary.markStopped(.input);
}

fn runLocalFallible(
    boundary: *shared.Boundary,
    owner: *local_terminal.Owner,
    mux: layout.Mux,
) !void {
    if (mux.tabCount() != 1 or mux.paneCount() != 1) return error.InputTopologyMismatch;
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
            state.animation_wait_ms orelse 100,
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
        if (boundary.takePaneFocus()) |focus_index| {
            if (focus_index != 0) return error.InputTopologyMismatch;
        }
        if (boundary.takePaneEndpoint() != null or
            boundary.takePaneRetired() or
            boundary.takeTabSwitched())
            return error.InputTopologyMismatch;

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
                    try deliverMouseLocal(boundary, owner, mouse);
                },
                .key => |key| {
                    // Preserve the host's one-pane shortcut reservation. F6/F7/F8
                    // were never reserved in the one-pane topology and continue
                    // to reach the terminal.
                    if (isClosePane(key) or
                        isNewTab(key) or
                        isNextTab(key) or
                        hostSplitCommand(key) != null)
                    {
                        continue;
                    }
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
    boundary: *shared.Boundary,
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
    var route = scrollback.routeWheel(
        mouse.history_offset != 0,
        force_history,
        false,
        false,
        mouse.alternate_screen,
        false,
    );
    if (route == .interaction_state) {
        const state = owner.interactionState();
        route = scrollback.routeWheel(
            mouse.history_offset != 0,
            force_history,
            true,
            state.mouse_tracking != .off,
            mouse.alternate_screen,
            state.alternate_scroll,
        );
    }
    switch (route) {
        .history => boundary.publishHostCommand(.{
            .kind = .history_scroll,
            .pane = 0,
            .amount = amount,
        }) catch |failure| switch (failure) {
            error.HostCommandLimit => {},
            else => |err| return err,
        },
        .terminal_mouse => try owner.input(.{ .mouse = nativeMouse(mouse.value) }),
        .alternate_scroll => {
            const key: session.KeyName = if (amount > 0) .up else .down;
            try owner.input(.{ .key = .{ .key = .{ .named = key }, .action = .press } });
            try owner.input(.{ .key = .{ .key = .{ .named = key }, .action = .release } });
        },
        .ignore => {},
        .interaction_state => unreachable,
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
                .key = try session.Key.initUnicode(scalar),
                .action = nativeAction(unicode.action) orelse return error.InvalidKey,
                .mods = nativeModifiers(unicode.modifiers),
            } });
        },
    }
}

fn nativeAction(value: u8) ?session.KeyAction {
    return switch (value) {
        1 => .press,
        2 => .repeat,
        3 => .release,
        else => null,
    };
}

fn nativeModifiers(value: u8) session.InputModifier {
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

fn nativeMouse(value: protocol.MouseInput) @FieldType(session.Input, "mouse") {
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

fn nativeNamedKey(value: u8) ?session.KeyName {
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

fn deliverMouse(
    boundary: *shared.Boundary,
    connection: *client.Connection,
    mouse: shared.RoutedMouse,
) !void {
    if (mouse.value.kind != .wheel) {
        try client.actions.mouse(connection, mouse.value);
        return;
    }
    const amount: i16 = switch (mouse.value.button) {
        .wheel_up => 3,
        .wheel_down => -3,
        else => return error.InputTopologyMismatch,
    };
    const force_history =
        mouse.value.modifiers & protocol.typed_input.modifiers.shift != 0;
    var route = scrollback.routeWheel(
        mouse.history_offset != 0,
        force_history,
        false,
        false,
        mouse.alternate_screen,
        false,
    );
    var state: protocol.InteractionStateSnapshot = undefined;
    if (route == .interaction_state) {
        state = try client.state.get(connection);
        route = scrollback.routeWheel(
            mouse.history_offset != 0,
            force_history,
            true,
            state.mouse_tracking != .off,
            mouse.alternate_screen,
            state.alternate_scroll,
        );
    }
    switch (route) {
        .history => boundary.publishHostCommand(.{
            .kind = .history_scroll,
            .pane = mouse.scene_index,
            .amount = amount,
        }) catch |failure| switch (failure) {
            // Wheel intent is safely coalescible at the UX boundary. If the
            // bounded host-control queue is full, newer pointer input will
            // provide another opportunity instead of retiring Input.
            error.HostCommandLimit => {},
            else => |err| return err,
        },
        .terminal_mouse => try client.actions.mouse(connection, mouse.value),
        .alternate_scroll => {
            const key: protocol.InputKeyName = if (amount > 0) .up else .down;
            try client.actions.namedKey(connection, key, .press, 0);
            try client.actions.namedKey(connection, key, .release, 0);
        },
        .ignore => {},
        .interaction_state => unreachable,
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

fn isNextTab(key: wayland.input.Key) bool {
    return @backingInt(key.keysym) == next_tab_keysym;
}

fn isNewTab(key: wayland.input.Key) bool {
    return @backingInt(key.keysym) == new_tab_keysym;
}

fn isFocusToggle(key: wayland.input.Key) bool {
    return @backingInt(key.keysym) == focus_toggle_keysym;
}

fn isClosePane(key: wayland.input.Key) bool {
    return @backingInt(key.keysym) == close_pane_keysym;
}

fn hostSplitCommand(key: wayland.input.Key) ?shared.HostCommandKind {
    return switch (@backingInt(key.keysym)) {
        split_pane_keysym => .split_horizontal,
        split_vertical_keysym => .split_vertical,
        else => null,
    };
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

test "F5 and F12 are exact tab canary keys" {
    try std.testing.expect(isNextTab(makeKey(next_tab_keysym, .pressed, "", .{})));
    try std.testing.expect(!isNextTab(makeKey(focus_toggle_keysym, .pressed, "", .{})));
    try std.testing.expect(isNewTab(makeKey(new_tab_keysym, .pressed, "", .{})));
    try std.testing.expect(!isNewTab(makeKey(split_vertical_keysym, .pressed, "", .{})));
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
    try std.testing.expect(hostSplitCommand(makeKey(split_pane_keysym, .pressed, "", .{})) == .split_horizontal);
    try std.testing.expect(hostSplitCommand(makeKey(split_pane_keysym, .released, "", .{})) == .split_horizontal);
    try std.testing.expect(hostSplitCommand(makeKey(split_vertical_keysym, .pressed, "", .{})) == .split_vertical);
    try std.testing.expect(hostSplitCommand(makeKey(shrink_pane_keysym, .pressed, "", .{})) == null);
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
    try std.testing.expectEqual(session.KeyName.up, nativeNamedKey(5).?);
    try std.testing.expectEqual(session.KeyName.f12, nativeNamedKey(40).?);
    try std.testing.expectEqual(session.KeyName.keypad_enter, nativeNamedKey(58).?);
    try std.testing.expect(nativeNamedKey(0) == null);
    try std.testing.expectEqual(session.KeyAction.press, nativeAction(1).?);
    try std.testing.expectEqual(session.KeyAction.repeat, nativeAction(2).?);
    try std.testing.expectEqual(session.KeyAction.release, nativeAction(3).?);
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
    try std.testing.expectEqual(session.MouseEventKind.wheel, value.kind);
    try std.testing.expectEqual(session.MouseButton.wheel_up, value.button);
    try std.testing.expectEqual(@as(u16, 7), value.row);
    try std.testing.expectEqual(@as(u16, 9), value.col);
    try std.testing.expectEqual(@as(u16, 13), value.pixel_x);
    try std.testing.expectEqual(@as(u16, 17), value.pixel_y);
    try std.testing.expect(value.mod.control);
    try std.testing.expect(value.mod.shift);
    try std.testing.expectEqual(@as(u8, 1), value.buttons_down);
}
