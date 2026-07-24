//! Owns bounded OSC 22 stack policy and Wayland cursor-shape identities.

const std = @import("std");

const stack_capacity: u8 = 16;

const Shape = enum(u8) {
    default = 1,
    help = 3,
    pointer = 4,
    progress = 5,
    wait = 6,
    cell = 7,
    crosshair = 8,
    text = 9,
    vertical_text = 10,
    alias = 11,
    copy = 12,
    move = 13,
    no_drop = 14,
    not_allowed = 15,
    grab = 16,
    grabbing = 17,
    e_resize = 18,
    n_resize = 19,
    ne_resize = 20,
    nw_resize = 21,
    s_resize = 22,
    se_resize = 23,
    sw_resize = 24,
    w_resize = 25,
    ew_resize = 26,
    ns_resize = 27,
    nesw_resize = 28,
    nwse_resize = 29,
    zoom_in = 33,
    zoom_out = 34,
};

const Outcome = struct {
    reply_len: usize = 0,
};

const Stack = struct {
    values: [stack_capacity]Shape = undefined,
    count: u8 = 0,

    fn current(self: *const Stack) Shape {
        return if (self.count == 0) .default else self.values[self.count - 1];
    }

    fn push(self: *Stack, shape: Shape) void {
        if (self.count == stack_capacity) {
            std.mem.copyForwards(Shape, self.values[0 .. stack_capacity - 1], self.values[1..]);
            self.count -= 1;
        }
        self.values[self.count] = shape;
        self.count += 1;
    }
};

/// Retains two fixed OSC 22 stacks and applies one complete request atomically.
pub const State = struct {
    banks: [2]Stack = .{ .{}, .{} },

    /// Return the Wayland cursor-shape value for one screen bank.
    pub fn current(self: *const State, alternate: bool) u32 {
        return @backingInt(self.banks[@intFromBool(alternate)].current());
    }

    /// Clear both screen-bank stacks after terminal reset.
    pub fn reset(self: *State) void {
        self.* = .{};
    }

    /// Apply one validated set, push, pop, reset, or query into caller reply storage.
    pub fn apply(
        self: *State,
        payload: []const u8,
        alternate: bool,
        reply: []u8,
    ) error{InvalidPayload}!Outcome {
        const bank = &self.banks[@intFromBool(alternate)];
        if (payload.len == 0) {
            bank.* = .{};
            return .{};
        }
        const operation = switch (payload[0]) {
            '=', '>', '<', '?' => payload[0],
            else => '=',
        };
        const names = if (operation == '=') payload[@intFromBool(payload[0] == '=')..] else payload[1..];
        if (operation == '<') {
            if (bank.count != 0) bank.count -= 1;
            return .{};
        }
        if (operation == '?') {
            const len = try query(bank, names, reply);
            return .{ .reply_len = len };
        }

        var next = bank.*;
        var iterator = std.mem.splitScalar(u8, names, ',');
        var found = false;
        while (iterator.next()) |name| {
            const shape = parse(name) orelse return error.InvalidPayload;
            found = true;
            if (operation == '=') {
                if (next.count == 0) next.count = 1;
                next.values[next.count - 1] = shape;
            } else {
                next.push(shape);
            }
        }
        if (!found) return error.InvalidPayload;
        bank.* = next;
        return .{};
    }
};

fn query(stack: *const Stack, names: []const u8, reply: []u8) error{InvalidPayload}!usize {
    if (names.len == 0) return error.InvalidPayload;
    var written: usize = 0;
    var iterator = std.mem.splitScalar(u8, names, ',');
    var found = false;
    while (iterator.next()) |name| {
        if (found) {
            if (written == reply.len) return error.InvalidPayload;
            reply[written] = ',';
            written += 1;
        }
        found = true;
        const value = if (std.mem.eql(u8, name, "__current__"))
            if (stack.count == 0) "0" else shapeName(stack.current())
        else if (std.mem.eql(u8, name, "__default__"))
            "default"
        else if (std.mem.eql(u8, name, "__grabbed__"))
            "grabbing"
        else if (parse(name) != null)
            "1"
        else
            "0";
        if (value.len > reply.len - written) return error.InvalidPayload;
        @memcpy(reply[written..][0..value.len], value);
        written += value.len;
    }
    if (!found) return error.InvalidPayload;
    return written;
}

fn parse(name: []const u8) ?Shape {
    const names = [_]struct { name: []const u8, shape: Shape }{
        .{ .name = "default", .shape = .default },             .{ .name = "help", .shape = .help },
        .{ .name = "pointer", .shape = .pointer },             .{ .name = "progress", .shape = .progress },
        .{ .name = "wait", .shape = .wait },                   .{ .name = "cell", .shape = .cell },
        .{ .name = "crosshair", .shape = .crosshair },         .{ .name = "text", .shape = .text },
        .{ .name = "vertical-text", .shape = .vertical_text }, .{ .name = "alias", .shape = .alias },
        .{ .name = "copy", .shape = .copy },                   .{ .name = "move", .shape = .move },
        .{ .name = "no-drop", .shape = .no_drop },             .{ .name = "not-allowed", .shape = .not_allowed },
        .{ .name = "grab", .shape = .grab },                   .{ .name = "grabbing", .shape = .grabbing },
        .{ .name = "e-resize", .shape = .e_resize },           .{ .name = "n-resize", .shape = .n_resize },
        .{ .name = "ne-resize", .shape = .ne_resize },         .{ .name = "nw-resize", .shape = .nw_resize },
        .{ .name = "s-resize", .shape = .s_resize },           .{ .name = "se-resize", .shape = .se_resize },
        .{ .name = "sw-resize", .shape = .sw_resize },         .{ .name = "w-resize", .shape = .w_resize },
        .{ .name = "ew-resize", .shape = .ew_resize },         .{ .name = "ns-resize", .shape = .ns_resize },
        .{ .name = "nesw-resize", .shape = .nesw_resize },     .{ .name = "nwse-resize", .shape = .nwse_resize },
        .{ .name = "zoom-in", .shape = .zoom_in },             .{ .name = "zoom-out", .shape = .zoom_out },
    };
    for (names) |entry| if (std.mem.eql(u8, name, entry.name)) return entry.shape;
    return null;
}

fn shapeName(shape: Shape) []const u8 {
    return switch (shape) {
        .vertical_text => "vertical-text",
        .no_drop => "no-drop",
        .not_allowed => "not-allowed",
        .e_resize => "e-resize",
        .n_resize => "n-resize",
        .ne_resize => "ne-resize",
        .nw_resize => "nw-resize",
        .s_resize => "s-resize",
        .se_resize => "se-resize",
        .sw_resize => "sw-resize",
        .w_resize => "w-resize",
        .ew_resize => "ew-resize",
        .ns_resize => "ns-resize",
        .nesw_resize => "nesw-resize",
        .nwse_resize => "nwse-resize",
        .zoom_in => "zoom-in",
        .zoom_out => "zoom-out",
        else => @tagName(shape),
    };
}

test "pointer stacks retain banks eviction queries and rollback" {
    var state = State{};
    var reply: [64]u8 = undefined;
    try std.testing.expectEqual(@as(usize, 0), (try state.apply(">wait,pointer", false, &reply)).reply_len);
    try std.testing.expectEqual(@as(usize, 0), (try state.apply(">crosshair", true, &reply)).reply_len);
    try std.testing.expectEqual(@backingInt(Shape.pointer), state.current(false));
    const result = try state.apply("?__current__,wait,no-such", false, &reply);
    try std.testing.expectEqualStrings("pointer,1,0", reply[0..result.reply_len]);
    const before = state;
    try std.testing.expectError(error.InvalidPayload, state.apply(">wait,bad", false, &reply));
    try std.testing.expect(std.meta.eql(before, state));
    try std.testing.expectEqual(@as(usize, 0), (try state.apply("<", false, &reply)).reply_len);
    try std.testing.expectEqual(@backingInt(Shape.wait), state.current(false));
    for (0..stack_capacity + 2) |_|
        try std.testing.expectEqual(@as(usize, 0), (try state.apply(">cell", false, &reply)).reply_len);
    try std.testing.expectEqual(stack_capacity, state.banks[0].count);
    try std.testing.expectEqual(@backingInt(Shape.cell), state.current(false));
    try std.testing.expectEqual(@as(usize, 0), (try state.apply("", false, &reply)).reply_len);
    try std.testing.expectEqual(@backingInt(Shape.default), state.current(false));
    const empty = try state.apply("?__current__", false, &reply);
    try std.testing.expectEqualStrings("0", reply[0..empty.reply_len]);
}
