//! Owns bounded physical-key parsing, held-key state, chords, and timed sequences.

const std = @import("std");
const protocol = @import("howl_session").protocol;
const client = @import("client.zig");

/// Maximum simultaneous physical keys tracked by one CLI process.
pub const maximum_held_keys: usize = 16;
/// Maximum sequence source bytes accepted from stdin.
pub const maximum_sequence_bytes: usize = 64 * 1024;
/// Maximum parsed sequence steps.
pub const maximum_sequence_steps: usize = 256;
/// Maximum one wait duration.
pub const maximum_wait_ms: u32 = 60_000;
/// Maximum aggregate wait duration in one sequence invocation.
pub const maximum_total_wait_ms: u32 = 300_000;

/// One parsed physical key identity plus an optional depressed-modifier bit.
pub const Key = struct {
    kind: protocol.InputKeyKind,
    value: u32,
    modifier_bit: ?u8 = null,

    /// Builds one borrowed protocol key event with the supplied complete modifier state.
    pub fn event(self: Key, action: protocol.InputKeyAction, modifiers: u8) protocol.KeyInput {
        return .{
            .kind = self.kind,
            .key_value = self.value,
            .action = action,
            .modifiers = modifiers,
        };
    }

    fn eql(left: Key, right: Key) bool {
        return left.kind == right.kind and left.value == right.value;
    }
};

/// One bounded sequence operation borrowing no input storage.
pub const Step = union(enum) {
    down: Key,
    repeat: Key,
    up: Key,
    wait_ms: u32,
};

/// Fixed parsed sequence storage.
pub const Sequence = struct {
    steps: [maximum_sequence_steps]Step = undefined,
    count: u16 = 0,
    total_wait_ms: u32 = 0,

    /// Borrows the parsed step prefix.
    pub fn items(self: *const Sequence) []const Step {
        return self.steps[0..self.count];
    }
};

/// Reports physical-key syntax or held-state contract failure.
pub const Error = client.CommandError || error{
    InvalidKey,
    InvalidAction,
    InvalidChord,
    InvalidSequence,
    TooManySteps,
    TooManyHeldKeys,
    KeyAlreadyHeld,
    KeyNotHeld,
    RepeatKeyNotHeld,
    WaitTooLong,
    TotalWaitTooLong,
    ServerRejected,
    WaitFailed,
    CleanupFailed,
};

/// Parses a common named key or exactly one Unicode scalar.
pub fn parseKey(text: []const u8) error{InvalidKey}!Key {
    if (namedKey(text)) |named| return named;
    if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidKey;
    var view = std.unicode.Utf8View.initUnchecked(text);
    var iterator = view.iterator();
    const first = iterator.nextCodepoint() orelse return error.InvalidKey;
    if (iterator.nextCodepoint() != null) return error.InvalidKey;
    return .{ .kind = .unicode, .value = first };
}

/// Parses a comma-separated complete modifier state for one stateless key event.
pub fn parseModifiers(text: []const u8) error{InvalidKey}!u8 {
    if (text.len == 0 or std.ascii.eqlIgnoreCase(text, "none")) return 0;
    var result: u8 = 0;
    var parts = std.mem.splitScalar(u8, text, ',');
    while (parts.next()) |part| {
        const key = try parseKey(part);
        const bit = key.modifier_bit orelse return error.InvalidKey;
        if (result & bit != 0) return error.InvalidKey;
        result |= bit;
    }
    return result;
}

/// Sends one stateless physical key transition with the caller's complete modifier state.
pub fn sendKey(
    connection: *client.Connection,
    key: Key,
    action: protocol.InputKeyAction,
    modifiers: u8,
) Error!void {
    try expectOk(try connection.key(key.event(action, modifiers)));
}

/// Sends one physical press/release pair with modifier transition semantics for the key itself.
pub fn tap(connection: *client.Connection, key: Key, base_modifiers: u8) Error!void {
    const pressed_modifiers = if (key.modifier_bit) |bit| base_modifiers | bit else base_modifiers;
    try sendKey(connection, key, .press, pressed_modifiers);
    const released_modifiers = if (key.modifier_bit) |bit| base_modifiers & ~bit else base_modifiers;
    try sendKey(connection, key, .release, released_modifiers);
}

/// Holds one physical key for a bounded monotonic duration in a single client process.
pub fn hold(
    connection: *client.Connection,
    io: std.Io,
    key: Key,
    milliseconds: u32,
) Error!void {
    if (milliseconds > maximum_wait_ms) return error.WaitTooLong;
    var state = HeldState{ .connection = connection };
    state.down(key) catch |failure| return failure;
    std.Io.sleep(io, .fromMilliseconds(milliseconds), .awake) catch {
        if (!state.releaseAll()) return error.CleanupFailed;
        return error.WaitFailed;
    };
    if (!state.releaseAll()) return error.CleanupFailed;
}

/// Parses one bounded duration accepted by hold and sequence commands.
pub fn parseDuration(text: []const u8) error{ WaitTooLong, InvalidSequence }!u32 {
    return parseWait(text);
}

/// Executes a convenience chord as modifier-downs, target press/release, and reverse modifier releases.
pub fn chord(connection: *client.Connection, text: []const u8) Error!void {
    var parts = std.mem.splitScalar(u8, text, '+');
    var modifiers: [6]Key = undefined;
    var modifier_count: u8 = 0;
    var target: ?Key = null;
    while (parts.next()) |part| {
        if (part.len == 0 or target != null) return error.InvalidChord;
        const key = try parseKey(part);
        if (key.modifier_bit) |_| {
            if (modifier_count == modifiers.len) return error.InvalidChord;
            modifiers[modifier_count] = key;
            modifier_count += 1;
        } else {
            target = key;
            if (parts.next() != null) return error.InvalidChord;
            break;
        }
    }
    const final_key = target orelse return error.InvalidChord;
    if (modifier_count == 0) return error.InvalidChord;
    var state = HeldState{ .connection = connection };
    runChord(&state, modifiers[0..modifier_count], final_key) catch |failure| {
        if (!state.releaseAll()) return error.CleanupFailed;
        return failure;
    };
    if (!state.releaseAll()) return error.CleanupFailed;
}

fn runChord(state: *HeldState, modifiers: []const Key, final_key: Key) Error!void {
    for (modifiers) |modifier| try state.down(modifier);
    try state.down(final_key);
    try state.up(final_key);
    var index: usize = modifiers.len;
    while (index != 0) {
        index -= 1;
        try state.up(modifiers[index]);
    }
}

/// Parses the deliberately tiny line grammar used by `howl sequence --stdin`.
pub fn parseSequence(input: []const u8) error{
    InvalidKey,
    InvalidAction,
    InvalidSequence,
    TooManySteps,
    WaitTooLong,
    TotalWaitTooLong,
}!Sequence {
    if (input.len == 0 or input.len > maximum_sequence_bytes) return error.InvalidSequence;
    var result: Sequence = .{};
    var lines = std.mem.splitScalar(u8, input, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        if (result.count == maximum_sequence_steps) return error.TooManySteps;
        const separator = std.mem.indexOfAny(u8, trimmed, " \t") orelse return error.InvalidSequence;
        const verb = trimmed[0..separator];
        const argument = std.mem.trim(u8, trimmed[separator..], " \t");
        if (argument.len == 0) return error.InvalidSequence;
        const step: Step = if (std.mem.eql(u8, verb, "down"))
            .{ .down = try parseKey(argument) }
        else if (std.mem.eql(u8, verb, "repeat"))
            .{ .repeat = try parseKey(argument) }
        else if (std.mem.eql(u8, verb, "up"))
            .{ .up = try parseKey(argument) }
        else if (std.mem.eql(u8, verb, "wait")) blk: {
            const wait_ms = try parseWait(argument);
            result.total_wait_ms = std.math.add(u32, result.total_wait_ms, wait_ms) catch
                return error.TotalWaitTooLong;
            if (result.total_wait_ms > maximum_total_wait_ms) return error.TotalWaitTooLong;
            break :blk .{ .wait_ms = wait_ms };
        } else return error.InvalidAction;
        result.steps[result.count] = step;
        result.count += 1;
    }
    if (result.count == 0) return error.InvalidSequence;
    return result;
}

/// Executes one parsed sequence and releases all still-held keys on every controlled exit.
pub fn executeSequence(connection: *client.Connection, io: std.Io, sequence: *const Sequence) Error!void {
    var state = HeldState{ .connection = connection };
    executeSteps(&state, io, sequence) catch |failure| {
        if (!state.releaseAll()) return error.CleanupFailed;
        return failure;
    };
    if (!state.releaseAll()) return error.CleanupFailed;
}

const HeldState = struct {
    connection: *client.Connection,
    held: [maximum_held_keys]Key = undefined,
    count: u8 = 0,
    modifiers: u8 = 0,

    fn down(self: *HeldState, key: Key) Error!void {
        if (self.indexOf(key) != null) return error.KeyAlreadyHeld;
        if (self.count == maximum_held_keys) return error.TooManyHeldKeys;
        const next_modifiers = if (key.modifier_bit) |bit| self.modifiers | bit else self.modifiers;
        try expectOk(try self.connection.key(key.event(.press, next_modifiers)));
        self.held[self.count] = key;
        self.count += 1;
        self.modifiers = next_modifiers;
    }

    fn repeat(self: *HeldState, key: Key) Error!void {
        if (self.indexOf(key) == null) return error.RepeatKeyNotHeld;
        try expectOk(try self.connection.key(key.event(.repeat, self.modifiers)));
    }

    fn up(self: *HeldState, key: Key) Error!void {
        const index = self.indexOf(key) orelse return error.KeyNotHeld;
        const next_modifiers = if (key.modifier_bit) |bit| self.modifiers & ~bit else self.modifiers;
        try expectOk(try self.connection.key(key.event(.release, next_modifiers)));
        self.removeAt(index);
        self.modifiers = next_modifiers;
    }

    fn releaseAll(self: *HeldState) bool {
        var ok = true;
        while (self.count != 0) {
            const index = self.count - 1;
            const key = self.held[index];
            const next_modifiers = if (key.modifier_bit) |bit| self.modifiers & ~bit else self.modifiers;
            const result = self.connection.key(key.event(.release, next_modifiers)) catch {
                ok = false;
                self.removeAt(index);
                self.modifiers = next_modifiers;
                continue;
            };
            if (result != .ok) ok = false;
            self.removeAt(index);
            self.modifiers = next_modifiers;
        }
        return ok;
    }

    fn indexOf(self: *const HeldState, key: Key) ?u8 {
        for (self.held[0..self.count], 0..) |held, index| {
            if (Key.eql(held, key)) return @intCast(index);
        }
        return null;
    }

    fn removeAt(self: *HeldState, index: u8) void {
        std.debug.assert(index < self.count);
        const tail = self.count - index - 1;
        if (tail != 0) std.mem.copyForwards(
            Key,
            self.held[index .. index + tail],
            self.held[index + 1 .. index + 1 + tail],
        );
        self.count -= 1;
    }
};

fn executeSteps(state: *HeldState, io: std.Io, sequence: *const Sequence) Error!void {
    for (sequence.items()) |step| switch (step) {
        .down => |key| try state.down(key),
        .repeat => |key| try state.repeat(key),
        .up => |key| try state.up(key),
        .wait_ms => |milliseconds| std.Io.sleep(
            io,
            .fromMilliseconds(milliseconds),
            .awake,
        ) catch return error.WaitFailed,
    };
}

fn expectOk(code: protocol.ResultCode) error{ServerRejected}!void {
    if (code != .ok) return error.ServerRejected;
}

fn parseWait(text: []const u8) error{ WaitTooLong, InvalidSequence }!u32 {
    const multiplier: u32, const digits: []const u8 = if (std.mem.endsWith(u8, text, "ms"))
        .{ 1, text[0 .. text.len - 2] }
    else if (std.mem.endsWith(u8, text, "s"))
        .{ 1000, text[0 .. text.len - 1] }
    else
        return error.InvalidSequence;
    if (digits.len == 0) return error.InvalidSequence;
    const value = std.fmt.parseInt(u32, digits, 10) catch return error.InvalidSequence;
    const milliseconds = std.math.mul(u32, value, multiplier) catch return error.WaitTooLong;
    if (milliseconds > maximum_wait_ms) return error.WaitTooLong;
    return milliseconds;
}

fn namedKey(text: []const u8) ?Key {
    const Named = struct { text: []const u8, name: protocol.InputKeyName, modifier: ?u8 = null };
    const names = [_]Named{
        .{ .text = "enter", .name = .enter },
        .{ .text = "tab", .name = .tab },
        .{ .text = "backspace", .name = .backspace },
        .{ .text = "escape", .name = .escape },
        .{ .text = "esc", .name = .escape },
        .{ .text = "up", .name = .up },
        .{ .text = "down", .name = .down },
        .{ .text = "left", .name = .left },
        .{ .text = "right", .name = .right },
        .{ .text = "insert", .name = .insert },
        .{ .text = "delete", .name = .delete },
        .{ .text = "home", .name = .home },
        .{ .text = "end", .name = .end },
        .{ .text = "page-up", .name = .page_up },
        .{ .text = "page-down", .name = .page_down },
        .{ .text = "shift", .name = .left_shift, .modifier = protocol.typed_input.modifiers.shift },
        .{ .text = "left-shift", .name = .left_shift, .modifier = protocol.typed_input.modifiers.shift },
        .{ .text = "right-shift", .name = .right_shift, .modifier = protocol.typed_input.modifiers.shift },
        .{ .text = "ctrl", .name = .left_control, .modifier = protocol.typed_input.modifiers.control },
        .{ .text = "control", .name = .left_control, .modifier = protocol.typed_input.modifiers.control },
        .{ .text = "left-control", .name = .left_control, .modifier = protocol.typed_input.modifiers.control },
        .{ .text = "right-control", .name = .right_control, .modifier = protocol.typed_input.modifiers.control },
        .{ .text = "alt", .name = .left_alt, .modifier = protocol.typed_input.modifiers.alt },
        .{ .text = "left-alt", .name = .left_alt, .modifier = protocol.typed_input.modifiers.alt },
        .{ .text = "right-alt", .name = .right_alt, .modifier = protocol.typed_input.modifiers.alt },
        .{ .text = "super", .name = .left_super, .modifier = protocol.typed_input.modifiers.super },
        .{ .text = "left-super", .name = .left_super, .modifier = protocol.typed_input.modifiers.super },
        .{ .text = "right-super", .name = .right_super, .modifier = protocol.typed_input.modifiers.super },
        .{ .text = "hyper", .name = .left_hyper, .modifier = protocol.typed_input.modifiers.hyper },
        .{ .text = "meta", .name = .left_meta, .modifier = protocol.typed_input.modifiers.meta },
        .{ .text = "caps-lock", .name = .caps_lock },
        .{ .text = "num-lock", .name = .num_lock },
        .{ .text = "f1", .name = .f1 },
        .{ .text = "f2", .name = .f2 },
        .{ .text = "f3", .name = .f3 },
        .{ .text = "f4", .name = .f4 },
        .{ .text = "f5", .name = .f5 },
        .{ .text = "f6", .name = .f6 },
        .{ .text = "f7", .name = .f7 },
        .{ .text = "f8", .name = .f8 },
        .{ .text = "f9", .name = .f9 },
        .{ .text = "f10", .name = .f10 },
        .{ .text = "f11", .name = .f11 },
        .{ .text = "f12", .name = .f12 },
    };
    for (names) |candidate| if (std.ascii.eqlIgnoreCase(text, candidate.text)) return .{
        .kind = .named,
        .value = @backingInt(candidate.name),
        .modifier_bit = candidate.modifier,
    };
    if (std.ascii.eqlIgnoreCase(text, "space")) return .{ .kind = .unicode, .value = ' ' };
    return null;
}

test "key parser distinguishes modifiers named keys and one Unicode scalar" {
    const control = try parseKey("ctrl");
    try std.testing.expectEqual(protocol.InputKeyKind.named, control.kind);
    try std.testing.expectEqual(@as(u32, @backingInt(protocol.InputKeyName.left_control)), control.value);
    try std.testing.expectEqual(protocol.typed_input.modifiers.control, control.modifier_bit.?);
    const c = try parseKey("c");
    try std.testing.expectEqual(protocol.InputKeyKind.unicode, c.kind);
    try std.testing.expectEqual(@as(u32, 'c'), c.value);
    try std.testing.expectEqual(
        protocol.typed_input.modifiers.control | protocol.typed_input.modifiers.shift,
        try parseModifiers("ctrl,shift"),
    );
    try std.testing.expectError(error.InvalidKey, parseModifiers("ctrl,control"));
    try std.testing.expectError(error.InvalidKey, parseKey("ab"));
}

test "sequence parser bounds waits and preserves explicit transitions" {
    const sequence = try parseSequence("down ctrl\nwait 40ms\ndown a\nrepeat a\nup a\nwait 2s\nup ctrl\n");
    try std.testing.expectEqual(@as(usize, 7), sequence.items().len);
    try std.testing.expectEqual(@as(u32, 2040), sequence.total_wait_ms);
    try std.testing.expectError(error.WaitTooLong, parseSequence("wait 61s\n"));
    try std.testing.expectError(error.InvalidAction, parseSequence("tap a\n"));
}
