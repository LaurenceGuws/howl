const std = @import("std");
const wayland = @import("howl_wayland");

test "ordered facts retain exact protocol order and saturate transactionally" {
    var state = wayland.input.State{};
    for (0..wayland.input.capacity) |index| {
        try state.push(.{ .key = .{ .keycode = @intCast(index), .time = @intCast(index + 10), .state = .pressed, .serial = @intCast(index), .modifiers = .{ .serial = 0, .depressed = 0, .latched = 0, .locked = 0, .group = 0 }, .keysym = 0, .text_len = 0, .text = std.mem.zeroes([wayland.input.key_text_limit]u8) } });
    }
    const retained = state.take().?.key;
    try std.testing.expectEqual(@as(u32, 0), retained.keycode);
    try state.push(.{ .key = retained });
    try std.testing.expectError(error.OrderedFull, state.push(.{ .key = retained }));
    try std.testing.expectEqual(@as(u16, wayland.input.capacity), state.orderedCount());
    try std.testing.expectEqual(@as(u32, 1), state.take().?.key.keycode);
    while (state.take()) |_| {}
    try std.testing.expectEqual(@as(u16, 0), state.orderedCount());
}

test "coalesced facts preserve exact masks and checked revisions" {
    var state = wayland.input.State{};
    try state.setMotion(.{ .time = 11, .point = .{ .x = 1, .y = 2 } });
    try state.setModifiers(.{ .serial = 7, .depressed = 1, .latched = 2, .locked = 4, .group = 3 });
    try state.setRepeat(.{ .rate = 25, .delay = 500 });
    try state.setConfigure(0, 480);
    try std.testing.expectEqual(@as(u64, 4), state.currentRevision());
    try std.testing.expectEqual(@as(u32, 1), state.modifiersSnapshot().depressed);
    try std.testing.expectEqual(@as(u32, 480), state.configureSnapshot().?.height);
    try std.testing.expectEqual(@as(u32, 0), state.configureSnapshot().?.width);
}

test "ordered pointer facts retain occurrence coordinates under later motion" {
    var state = wayland.input.State{};
    const first = wayland.input.Point{ .x = 3, .y = 4 };
    try state.push(.{ .button = .{ .button = 1, .time = 10, .state = .pressed, .serial = 2, .point = first } });
    try state.setMotion(.{ .time = 11, .point = .{ .x = 90, .y = 91 } });
    const event = state.take().?.button;
    try std.testing.expectEqual(first.x, event.point.x);
    try std.testing.expectEqual(first.y, event.point.y);
    try std.testing.expectEqual(@as(u32, 10), event.time);
}

test "key facts retain causal modifiers and repeated state" {
    var state = wayland.input.State{};
    const modifiers = wayland.input.Modifiers{ .serial = 44, .depressed = 1, .latched = 2, .locked = 4, .group = 3 };
    try state.push(.{ .key = .{ .keycode = 30, .time = 55, .state = .repeated, .serial = 56, .modifiers = modifiers, .keysym = 0x41, .text_len = 1, .text = [_]u8{'A'} ++ std.mem.zeroes([wayland.input.key_text_limit - 1]u8) } });
    const key = state.take().?.key;
    try std.testing.expectEqual(wayland.input.KeyState.repeated, key.state);
    try std.testing.expectEqual(modifiers.serial, key.modifiers.serial);
    try std.testing.expectEqual(@as(u8, 1), key.text_len);
    try std.testing.expectEqual(@as(u8, 'A'), key.text[0]);
}

test "xkb context, keymap, and state release in reverse order" {
    var context = try wayland.xkb.Context.init();
    defer context.deinit();
    const fixture =
        "xkb_keymap {" ++
        " xkb_keycodes \"minimal\" { minimum = 8; maximum = 255; <ESC> = 9; <AE01> = 10; };" ++
        " xkb_types \"minimal\" { virtual_modifiers None; type \"ONE_LEVEL\" { modifiers = none; map[None] = Level1; level_name[Level1] = \"Any\"; }; };" ++
        " xkb_compatibility \"minimal\" { interpret Any+Any { action = NoAction(); }; };" ++
        " xkb_symbols \"minimal\" { key <ESC> { [ Escape ] }; key <AE01> { [ A ] }; };" ++
        " xkb_geometry \"minimal\" { }; };";
    var keymap = try wayland.xkb.Keymap.fromBuffer(&context, fixture);
    defer keymap.deinit();
    var state = try wayland.xkb.State.init(&keymap);
    defer state.deinit();
    try std.testing.expect(state.updateModifiers(.{ .depressed = 1, .latched = 0, .locked = 0, .group = 0 }));
    try std.testing.expectEqual(@as(u32, 0xff1b), state.keySym(9));
    var too_small = [_]u8{0xA5};
    try std.testing.expectError(error.OutputTooSmall, state.keyUtf8(10, &too_small));
    try std.testing.expectEqual(@as(u8, 0xA5), too_small[0]);
    var text = [_]u8{ 0xA5, 0xA5 };
    try std.testing.expectEqual(@as(usize, 1), try state.keyUtf8(10, &text));
    try std.testing.expectEqual(@as(u8, 'A'), text[0]);
}
