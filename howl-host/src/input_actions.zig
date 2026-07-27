//! Owns the finite physical-key capture and chrome-action policy applied only
//! by Renderer. Wayland facts remain caller-neutral and topology remains the
//! transactional state owner.

const std = @import("std");
const wayland = @import("howl_wayland");
const render = @import("howl_render");
const chrome_state = @import("chrome_state");

const capture_limit: usize = 16;
const primary_button: u32 = 0x110;
const resize_step: i32 = 8;

/// Finite Renderer-owned chrome mutation selected by an exact binding.
pub const Action = enum {
    new_tab,
    split_horizontal,
    split_vertical,
    close_pane,
    close_tab,
    resize_left,
    resize_right,
    resize_up,
    resize_down,
    reorder_left,
    reorder_right,
    next_tab,
    previous_tab,
    focus_left,
    focus_right,
    focus_up,
    focus_down,
};

/// Exact key-capture admission failure.
pub const Error = error{CaptureFull};

/// Exact topology or hit-projection failures from a primary pointer action.
pub const PointerError = chrome_state.Error || render.chrome.Error;

/// Describes whether a key remains unmatched, is consumed without mutation, or
/// selects one action.
pub const Decision = union(enum) {
    unmatched: void,
    consumed: void,
    action: Action,
};

/// Retains only physical keycodes whose releases belong to matched host chords.
pub const State = struct {
    captured: [capture_limit]u32 = undefined,
    count: u8 = 0,

    /// Classifies one exact key occurrence. Matched presses capture before
    /// returning an action; repeated facts and releases for captured keys are
    /// consumed without selecting another action.
    pub fn key(self: *State, event: wayland.input.Key) Error!Decision {
        if (self.find(event.keycode)) |index| {
            return switch (event.state) {
                .released => result: {
                    self.count -= 1;
                    if (index != self.count) self.captured[index] = self.captured[self.count];
                    break :result .{ .consumed = {} };
                },
                .pressed, .repeated => .{ .consumed = {} },
            };
        }
        if (event.state != .pressed) return .{ .unmatched = {} };
        const action = binding(event.keysym, event.semantic_modifiers) orelse return .{ .unmatched = {} };
        if (self.count == capture_limit) return error.CaptureFull;
        self.captured[self.count] = event.keycode;
        self.count += 1;
        return .{ .action = action };
    }

    /// Clears every captured physical key on keyboard leave or keymap reset.
    pub fn clear(self: *State) void {
        self.count = 0;
    }

    /// Returns the number of releases currently captured.
    pub fn capturedCount(self: *const State) u8 {
        return self.count;
    }

    fn find(self: *const State, keycode: u32) ?usize {
        for (self.captured[0..self.count], 0..) |captured, index| {
            if (captured == keycode) return index;
        }
        return null;
    }
};

/// Constructs the complete candidate topology for one action. A null result is
/// a deterministic boundary no-op; failures leave `current` byte-identical.
pub fn candidate(current: *const chrome_state.Topology, action: Action) chrome_state.Error!?chrome_state.Topology {
    var next = current.*;
    switch (action) {
        .new_tab => {
            const created = try next.createTab("tab");
            if (@backingInt(created) == 0) return error.InvalidId;
        },
        .split_horizontal => {
            const created = try next.split(next.focusedPaneId(), .horizontal);
            if (@backingInt(created) == 0) return error.InvalidId;
        },
        .split_vertical => {
            const created = try next.split(next.focusedPaneId(), .vertical);
            if (@backingInt(created) == 0) return error.InvalidId;
        },
        .close_pane => try next.closePane(next.focusedPaneId()),
        .close_tab => try next.closeTab(next.activeTabId()),
        .resize_left => try next.resizeDivider(next.focusedPaneId(), -resize_step, .vertical),
        .resize_right => try next.resizeDivider(next.focusedPaneId(), resize_step, .vertical),
        .resize_up => try next.resizeDivider(next.focusedPaneId(), -resize_step, .horizontal),
        .resize_down => try next.resizeDivider(next.focusedPaneId(), resize_step, .horizontal),
        .focus_left => {
            const previous = next.focusedPaneId();
            const focused = try next.focusDirection(.left);
            if (@backingInt(focused) == 0) return error.InvalidId;
            if (focused == previous) return null;
        },
        .focus_right => {
            const previous = next.focusedPaneId();
            const focused = try next.focusDirection(.right);
            if (@backingInt(focused) == 0) return error.InvalidId;
            if (focused == previous) return null;
        },
        .focus_up => {
            const previous = next.focusedPaneId();
            const focused = try next.focusDirection(.up);
            if (@backingInt(focused) == 0) return error.InvalidId;
            if (focused == previous) return null;
        },
        .focus_down => {
            const previous = next.focusedPaneId();
            const focused = try next.focusDirection(.down);
            if (@backingInt(focused) == 0) return error.InvalidId;
            if (focused == previous) return null;
        },
        .next_tab, .previous_tab => {
            const count = next.tabCount();
            if (count < 2) return null;
            const active = next.activeTabIndex();
            const destination = if (action == .next_tab)
                (active + 1) % count
            else if (active == 0)
                count - 1
            else
                active - 1;
            try next.switchTab(next.tabId(destination).?);
        },
        .reorder_left, .reorder_right => {
            const active = next.activeTabIndex();
            if (action == .reorder_left and active == 0) return null;
            if (action == .reorder_right and active + 1 == next.tabCount()) return null;
            const destination = if (action == .reorder_left) active - 1 else active + 1;
            try next.reorderTab(next.activeTabId(), destination);
        },
    }
    return next;
}

/// Constructs the candidate selected by one primary pointer press. Coordinates
/// outside the finite signed pixel domain are unmatched.
pub fn pointerCandidate(current: *const chrome_state.Topology, appearance: chrome_state.Appearance, button: wayland.input.Button) PointerError!?chrome_state.Topology {
    if (button.state != .pressed or button.button != primary_button) return null;
    if (!std.math.isFinite(button.point.x) or !std.math.isFinite(button.point.y)) return null;
    if (button.point.x < @as(f64, @floatFromInt(std.math.minInt(i32))) or button.point.x > @as(f64, @floatFromInt(std.math.maxInt(i32))) or
        button.point.y < @as(f64, @floatFromInt(std.math.minInt(i32))) or button.point.y > @as(f64, @floatFromInt(std.math.maxInt(i32))))
        return null;
    const point = render.chrome.Point{
        .x = @intFromFloat(@floor(button.point.x)),
        .y = @intFromFloat(@floor(button.point.y)),
    };
    const hit = try current.hitTest(appearance, point) orelse return null;
    var next = current.*;
    switch (hit) {
        .tab => |id| {
            if (id == next.activeTabId()) return null;
            try next.switchTab(id);
        },
        .pane => |id| {
            if (next.paneLayer(id) == .floating) {
                if (id == next.focusedPaneId() and next.floatingPaneIsTopmost(id)) return null;
                try next.raiseFloatingPane(id);
            } else {
                if (id == next.focusedPaneId()) return null;
                try next.focusPane(id);
            }
        },
    }
    return next;
}

fn binding(symbol: wayland.input.Keysym, modifiers: wayland.input.SemanticModifiers) ?Action {
    if (modifiers.hyper or modifiers.meta or modifiers.super) return null;
    if (modifiers.control and modifiers.shift and !modifiers.alt) return switch (symbol) {
        .t, .t_upper => .new_tab,
        .enter => .split_horizontal,
        .backslash, .bar => .split_vertical,
        .w, .w_upper => .close_pane,
        .q, .q_upper => .close_tab,
        .left => .previous_tab,
        .right => .next_tab,
        .comma, .less => .reorder_left,
        .period, .greater => .reorder_right,
        else => null,
    };
    if (modifiers.control and modifiers.alt and !modifiers.shift) return switch (symbol) {
        .left => .resize_left,
        .right => .resize_right,
        .up => .resize_up,
        .down => .resize_down,
        else => null,
    };
    if (modifiers.alt and modifiers.shift and !modifiers.control) return switch (symbol) {
        .left => .focus_left,
        .right => .focus_right,
        .up => .focus_up,
        .down => .focus_down,
        else => null,
    };
    return null;
}

fn key(keycode: u32, symbol: wayland.input.Keysym, modifiers: wayland.input.SemanticModifiers, state: wayland.input.KeyState) wayland.input.Key {
    return .{
        .keycode = keycode,
        .time = 1,
        .state = state,
        .serial = 2,
        .modifiers = .{ .serial = 3, .depressed = 0, .latched = 0, .locked = 0, .group = 0 },
        .semantic_modifiers = modifiers,
        .keysym = symbol,
        .text_len = 0,
        .text = std.mem.zeroes([wayland.input.key_text_limit]u8),
    };
}

test "exact bindings ignore locks and reject every extra non-lock modifier" {
    const Case = struct { symbol: wayland.input.Keysym, modifiers: wayland.input.SemanticModifiers, action: Action };
    const control_shift = wayland.input.SemanticModifiers{ .control = true, .shift = true };
    const control_alt = wayland.input.SemanticModifiers{ .control = true, .alt = true };
    const shift_alt = wayland.input.SemanticModifiers{ .shift = true, .alt = true };
    const cases = [_]Case{
        .{ .symbol = .t, .modifiers = control_shift, .action = .new_tab },
        .{ .symbol = .t_upper, .modifiers = control_shift, .action = .new_tab },
        .{ .symbol = .enter, .modifiers = control_shift, .action = .split_horizontal },
        .{ .symbol = .backslash, .modifiers = control_shift, .action = .split_vertical },
        .{ .symbol = .bar, .modifiers = control_shift, .action = .split_vertical },
        .{ .symbol = .w, .modifiers = control_shift, .action = .close_pane },
        .{ .symbol = .w_upper, .modifiers = control_shift, .action = .close_pane },
        .{ .symbol = .q, .modifiers = control_shift, .action = .close_tab },
        .{ .symbol = .q_upper, .modifiers = control_shift, .action = .close_tab },
        .{ .symbol = .left, .modifiers = control_shift, .action = .previous_tab },
        .{ .symbol = .right, .modifiers = control_shift, .action = .next_tab },
        .{ .symbol = .comma, .modifiers = control_shift, .action = .reorder_left },
        .{ .symbol = .less, .modifiers = control_shift, .action = .reorder_left },
        .{ .symbol = .period, .modifiers = control_shift, .action = .reorder_right },
        .{ .symbol = .greater, .modifiers = control_shift, .action = .reorder_right },
        .{ .symbol = .left, .modifiers = control_alt, .action = .resize_left },
        .{ .symbol = .right, .modifiers = control_alt, .action = .resize_right },
        .{ .symbol = .up, .modifiers = control_alt, .action = .resize_up },
        .{ .symbol = .down, .modifiers = control_alt, .action = .resize_down },
        .{ .symbol = .left, .modifiers = shift_alt, .action = .focus_left },
        .{ .symbol = .right, .modifiers = shift_alt, .action = .focus_right },
        .{ .symbol = .up, .modifiers = shift_alt, .action = .focus_up },
        .{ .symbol = .down, .modifiers = shift_alt, .action = .focus_down },
    };
    for (cases, 0..) |case, index| {
        var state = State{};
        const decision = try state.key(key(@intCast(index), case.symbol, case.modifiers, .pressed));
        try std.testing.expectEqual(case.action, decision.action);
        var locks = case.modifiers;
        locks.caps_lock = true;
        locks.num_lock = true;
        state.clear();
        try std.testing.expectEqual(case.action, (try state.key(key(@intCast(index), case.symbol, locks, .pressed))).action);
        inline for ([_]enum { shift, control, alt, super, hyper, meta }{ .shift, .control, .alt, .super, .hyper, .meta }) |extra| {
            if (!@field(case.modifiers, @tagName(extra))) {
                var augmented = case.modifiers;
                @field(augmented, @tagName(extra)) = true;
                state.clear();
                const augmented_decision = try state.key(key(@intCast(index), case.symbol, augmented, .pressed));
                try std.testing.expect(augmented_decision == .unmatched);
            }
        }
    }
    for ([_]wayland.input.Keysym{ .left, .right, .up, .down }) |symbol| {
        var reserved = State{};
        try std.testing.expect((try reserved.key(key(90, symbol, .{ .alt = true }, .pressed))) == .unmatched);
    }
    var reserved = State{};
    try std.testing.expect((try reserved.key(key(91, .tab, .{ .control = true }, .pressed))) == .unmatched);
    try std.testing.expect((try reserved.key(key(92, .iso_left_tab, control_shift, .pressed))) == .unmatched);
    try std.testing.expect((try reserved.key(key(93, .up, control_shift, .pressed))) == .unmatched);
    try std.testing.expect((try reserved.key(key(94, .down, control_shift, .pressed))) == .unmatched);
}

test "physical capture acts once consumes release and clears exactly" {
    var state = State{};
    const modifiers = wayland.input.SemanticModifiers{ .control = true, .shift = true };
    try std.testing.expect((try state.key(key(10, .t, modifiers, .pressed))) == .action);
    try std.testing.expect((try state.key(key(10, .t, modifiers, .pressed))) == .consumed);
    try std.testing.expect((try state.key(key(10, .t, modifiers, .repeated))) == .consumed);
    try std.testing.expect((try state.key(key(10, .t, .{}, .released))) == .consumed);
    try std.testing.expect((try state.key(key(10, .t, .{}, .released))) == .unmatched);
    for (0..capture_limit) |index| {
        try std.testing.expect((try state.key(key(@intCast(index + 20), .t, modifiers, .pressed))) == .action);
    }
    const before = state;
    try std.testing.expectError(error.CaptureFull, state.key(key(100, .t, modifiers, .pressed)));
    try std.testing.expectEqualDeep(before, state);
    state.clear();
    try std.testing.expectEqual(@as(u8, 0), state.capturedCount());
}

test "topology candidates cover tabs splits focus resize close and boundaries" {
    var topology = try chrome_state.Topology.init(.{ .width = 320, .height = 240 }, 24);
    topology = (try candidate(&topology, .new_tab)).?;
    try std.testing.expectEqual(@as(usize, 2), topology.tabCount());
    topology = (try candidate(&topology, .previous_tab)).?;
    try std.testing.expectEqual(@as(usize, 0), topology.activeTabIndex());
    topology = (try candidate(&topology, .next_tab)).?;
    try std.testing.expectEqual(@as(usize, 1), topology.activeTabIndex());
    try std.testing.expect((try candidate(&topology, .reorder_right)) == null);
    topology = (try candidate(&topology, .reorder_left)).?;
    try std.testing.expectEqual(@as(usize, 0), topology.activeTabIndex());
    topology = (try candidate(&topology, .split_vertical)).?;
    try std.testing.expectEqual(@as(usize, 2), topology.paneCount(0));
    topology = (try candidate(&topology, .focus_left)).?;
    topology = (try candidate(&topology, .resize_right)).?;
    topology = (try candidate(&topology, .close_pane)).?;
    try std.testing.expectEqual(@as(usize, 1), topology.paneCount(0));
    topology = (try candidate(&topology, .split_horizontal)).?;
    topology = (try candidate(&topology, .focus_up)).?;
    topology = (try candidate(&topology, .resize_down)).?;
    try topology.validate();
}

test "failed action preserves topology and stable identity issuance" {
    var topology = try chrome_state.Topology.init(.{ .width = 320, .height = 240 }, 24);
    while (topology.tabCount() < chrome_state.max_tabs) {
        topology = (try candidate(&topology, .new_tab)).?;
    }
    const before = topology;
    try std.testing.expectError(error.Capacity, candidate(&topology, .new_tab));
    try std.testing.expectEqualDeep(before, topology);
    topology = (try candidate(&topology, .close_tab)).?;
    const created = (try candidate(&topology, .new_tab)).?;
    try std.testing.expect(created.activeTabId() != before.activeTabId());
    try created.validate();
}

test "directional resize grows the focused pane toward the requested boundary" {
    var topology = try chrome_state.Topology.init(.{ .width = 320, .height = 240 }, 24);
    const left = topology.paneId(0, 0).?;
    const right = try topology.split(left, .vertical);
    topology = (try candidate(&topology, .focus_left)).?;
    const appearance = chrome_state.Appearance{
        .style = .{ .foreground = .{ .r = 1, .g = 2, .b = 3, .a = 255 }, .background = .{ .r = 4, .g = 5, .b = 6, .a = 255 }, .border = .{ .r = 7, .g = 8, .b = 9, .a = 255 } },
        .tab_active_background = .{ .r = 10, .g = 11, .b = 12, .a = 255 },
        .tab_inactive_background = .{ .r = 13, .g = 14, .b = 15, .a = 255 },
    };
    try std.testing.expectEqual(right, (try topology.hitTest(appearance, .{ .x = 164, .y = 40 })).?.pane);
    topology = (try candidate(&topology, .resize_right)).?;
    try std.testing.expectEqual(left, (try topology.hitTest(appearance, .{ .x = 164, .y = 40 })).?.pane);
}

test "directional and pointer no-ops produce no topology candidate" {
    const appearance = chrome_state.Appearance{
        .style = .{ .foreground = .{ .r = 1, .g = 2, .b = 3, .a = 255 }, .background = .{ .r = 4, .g = 5, .b = 6, .a = 255 }, .border = .{ .r = 7, .g = 8, .b = 9, .a = 255 } },
        .tab_active_background = .{ .r = 10, .g = 11, .b = 12, .a = 255 },
        .tab_inactive_background = .{ .r = 13, .g = 14, .b = 15, .a = 255 },
    };
    var topology = try chrome_state.Topology.init(.{ .width = 160, .height = 100 }, 24);
    const before = topology;
    try std.testing.expect((try candidate(&topology, .focus_left)) == null);
    try std.testing.expectEqualDeep(before, topology);
    try std.testing.expect((try pointerCandidate(&topology, appearance, .{ .button = primary_button, .time = 1, .state = .pressed, .serial = 2, .point = .{ .x = 80, .y = 60 } })) == null);
    try std.testing.expectEqualDeep(before, topology);
    const floating = try topology.createFloatingPane(.{ .x = 20, .y = 30, .width = 80, .height = 50 }, "float");
    const floating_before = topology;
    try std.testing.expect((try pointerCandidate(&topology, appearance, .{ .button = primary_button, .time = 1, .state = .pressed, .serial = 2, .point = .{ .x = 30, .y = 40 } })) == null);
    try std.testing.expectEqual(floating, topology.focusedPaneId());
    try std.testing.expectEqualDeep(floating_before, topology);
}

test "primary pointer selects tabs focuses panes and raises floating order" {
    var topology = try chrome_state.Topology.init(.{ .width = 160, .height = 100 }, 24);
    const tiled = topology.paneId(0, 0).?;
    const floating = try topology.createFloatingPane(.{ .x = 20, .y = 30, .width = 80, .height = 50 }, "float");
    const second_tab = try topology.createTab("two");
    try std.testing.expect(@backingInt(second_tab) != 0);
    const appearance = chrome_state.Appearance{
        .style = .{ .foreground = .{ .r = 1, .g = 2, .b = 3, .a = 4 }, .background = .{ .r = 5, .g = 6, .b = 7, .a = 8 }, .border = .{ .r = 9, .g = 10, .b = 11, .a = 12 } },
        .tab_active_background = .{ .r = 13, .g = 14, .b = 15, .a = 16 },
        .tab_inactive_background = .{ .r = 17, .g = 18, .b = 19, .a = 20 },
    };
    topology = (try pointerCandidate(&topology, appearance, .{ .button = primary_button, .time = 1, .state = .pressed, .serial = 2, .point = .{ .x = 10, .y = 10 } })).?;
    try std.testing.expectEqual(@as(usize, 0), topology.activeTabIndex());
    topology = (try pointerCandidate(&topology, appearance, .{ .button = primary_button, .time = 1, .state = .pressed, .serial = 2, .point = .{ .x = 120, .y = 90 } })).?;
    try std.testing.expectEqual(tiled, topology.focusedPaneId());
    topology = (try pointerCandidate(&topology, appearance, .{ .button = primary_button, .time = 1, .state = .pressed, .serial = 2, .point = .{ .x = 30, .y = 40 } })).?;
    try std.testing.expectEqual(floating, topology.focusedPaneId());
    try std.testing.expect((try pointerCandidate(&topology, appearance, .{ .button = 2, .time = 1, .state = .pressed, .serial = 2, .point = .{ .x = 30, .y = 40 } })) == null);
    try std.testing.expect((try pointerCandidate(&topology, appearance, .{ .button = primary_button, .time = 1, .state = .pressed, .serial = 2, .point = .{ .x = -1, .y = 40 } })) == null);
}
