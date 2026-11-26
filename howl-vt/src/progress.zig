//! Retained OSC 9;4 task progress, independent of notifications and UI clocks.
const std = @import("std");

/// Numeric values follow the ConEmu/Windows Terminal progress sequence.
pub const Kind = enum(u8) { none = 0, normal = 1, failure = 2, indeterminate = 3, paused = 4 };
/// Copies the complete current task indicator. No timer or process ownership.
pub const State = struct { kind: Kind = .none, value: ?u8 = null };
/// One parsed transition. Only paused retains a prior omitted percentage.
pub const Update = struct { kind: Kind, value: ?u8 = null };

/// Parses the OSC 9 payload including its `4;` subcommand. No allocation.
/// Malformed or out-of-range progress is ignored, not turned into a notification.
pub fn parse(payload: []const u8) ?Update {
    var parts = std.mem.splitScalar(u8, payload, ';');
    if (!std.mem.eql(u8, parts.next() orelse return null, "4")) return null;
    const state = parts.next() orelse return .{ .kind = .none };
    if (state.len != 1 or state[0] < '0' or state[0] > '4') return null;
    const kind: Kind = @fromBackingInt(@intCast(state[0] - '0'));
    var value: ?u8 = null;
    if (parts.next()) |raw| {
        if (raw.len != 0) {
            if (raw.len > 3) return null;
            for (raw) |byte| if (!std.ascii.isDigit(byte)) return null;
            value = std.fmt.parseInt(u8, raw, 10) catch return null;
            if (value.? > 100) return null;
        }
    }
    if (parts.next() != null or (kind == .normal and value == null)) return null;
    return .{ .kind = kind, .value = value };
}

/// Applies one valid transition without a publication policy or allocation.
pub fn apply(previous: State, update: Update) State {
    return .{ .kind = update.kind, .value = switch (update.kind) {
        .none, .indeterminate => null,
        .normal, .failure => update.value,
        .paused => update.value orelse previous.value,
    } };
}

test "task progress parses all states and rejects malformed fields" {
    const invalid = [_][]const u8{ "", "4;", "4;5;50", "4;1", "4;1;", "4;1;101", "4;1;-1", "4;1;+1", "4;1; 1", "4;1;1;", "4;11;1", "4;1;999999", "4;1;abc", "4;1;1.0" };
    for (invalid) |value| try std.testing.expect(parse(value) == null);
    try std.testing.expectEqualDeep(Update{ .kind = .none }, parse("4").?);
    try std.testing.expectEqualDeep(Update{ .kind = .normal, .value = 0 }, parse("4;1;0").?);
    try std.testing.expectEqualDeep(Update{ .kind = .normal, .value = 100 }, parse("4;1;100").?);
    try std.testing.expectEqualDeep(Update{ .kind = .failure }, parse("4;2").?);
    try std.testing.expectEqualDeep(Update{ .kind = .paused }, parse("4;4;").?);
    try std.testing.expectEqualDeep(State{}, apply(.{ .kind = .normal, .value = 65 }, parse("4;0").?));
    try std.testing.expectEqualDeep(State{ .kind = .paused, .value = 65 }, apply(.{ .kind = .normal, .value = 65 }, parse("4;4").?));
    try std.testing.expectEqualDeep(State{ .kind = .indeterminate }, apply(.{}, parse("4;3;55").?));
}

test "OSC 9 progress preserves numeric presence through the complete percentage domain" {
    const previous_states = [_]State{
        .{},                   .{ .kind = .normal, .value = 0 },   .{ .kind = .normal, .value = 100 },
        .{ .kind = .failure }, .{ .kind = .failure, .value = 63 }, .{ .kind = .indeterminate },
        .{ .kind = .paused },  .{ .kind = .paused, .value = 39 },
    };
    for (previous_states) |previous| {
        for ([_][]const u8{ "4;4", "4;4;" }) |body|
            try std.testing.expectEqualDeep(State{ .kind = .paused, .value = previous.value }, apply(previous, parse(body).?));
        for ([_][]const u8{ "4;2", "4;2;" }) |body|
            try std.testing.expectEqualDeep(State{ .kind = .failure }, apply(previous, parse(body).?));
        for ([_][]const u8{ "4", "4;0", "4;0;" }) |body|
            try std.testing.expectEqualDeep(State{}, apply(previous, parse(body).?));
        try std.testing.expectEqualDeep(State{ .kind = .indeterminate }, apply(previous, parse("4;3").?));
        for ([_]Kind{ .normal, .failure, .paused }) |kind| {
            for (0..101) |value| {
                var body: [16]u8 = undefined;
                const wire = try std.fmt.bufPrint(&body, "4;{d};{d}", .{ @backingInt(kind), value });
                const expected = State{ .kind = kind, .value = @intCast(value) };
                try std.testing.expectEqualDeep(expected, apply(previous, parse(wire).?));
            }
        }
    }
}
