//! VT-owned native input vocabulary and copied observation projection.
//! Optional root: the live VT imports neither this root nor its C declarations.
const std = @import("std");
const vt = @import("howl_vt");
/// Exact C declarations owned by this VT artifact boundary.
pub const c = @import("vt_native_types");
/// Canonical terminal semantic authority.
pub const Terminal = vt.Terminal;
/// Bounded copied query operations over canonical const observation.
pub const queries = @import("native_queries.zig");
/// Allocation-free copied graphics over canonical const observation.
pub const graphics = @import("native_graphics.zig");
/// Copied exact-head request facts, independent of transport framing.
pub const requests = @import("native_requests.zig");
/// Optional stable bare VT owner for caller-driven foreign embedding.
pub const owner = @import("native_owner.zig");
/// Optional retired-safe source capability for synchronous module composition.
pub const observation = @import("native_observation.zig");
test {
    // zig-audit: acknowledge discard
    // reason: Include this optional root's sibling query proofs in the exact native-contract test artifact.
    _ = queries;
    // zig-audit: acknowledge discard
    // reason: Include the optional request projection proofs in this exact native-contract test root.
    _ = requests;
    // zig-audit: acknowledge discard
    // reason: Include exact optional owner proofs without adding this owner to the live VT root.
    _ = owner;
}
comptime {
    if (vt.scalar.maximum_scalars != c.HVT_MAXIMUM_CELL_SCALARS)
        @compileError("VT scalar capacity changed: review the native record and ABI version");
}
/// Invalid native tags or out-of-range semantic coordinates.
pub const Error = error{InvalidArgument};

/// Converts stable native key tags without interpreting Server enums.
pub fn namedKey(value: u8) ?Terminal.NamedKey {
    return switch (value) {
        c.HVT_KEY_ENTER => .enter,
        c.HVT_KEY_TAB => .tab,
        c.HVT_KEY_BACKSPACE => .backspace,
        c.HVT_KEY_ESCAPE => .escape,
        c.HVT_KEY_UP => .up,
        c.HVT_KEY_DOWN => .down,
        c.HVT_KEY_LEFT => .left,
        c.HVT_KEY_RIGHT => .right,
        c.HVT_KEY_INSERT => .insert,
        c.HVT_KEY_DELETE => .delete,
        c.HVT_KEY_HOME => .home,
        c.HVT_KEY_END => .end,
        c.HVT_KEY_PAGE_UP => .page_up,
        c.HVT_KEY_PAGE_DOWN => .page_down,
        c.HVT_KEY_LEFT_SHIFT => .left_shift,
        c.HVT_KEY_RIGHT_SHIFT => .right_shift,
        c.HVT_KEY_LEFT_CONTROL => .left_control,
        c.HVT_KEY_RIGHT_CONTROL => .right_control,
        c.HVT_KEY_LEFT_ALT => .left_alt,
        c.HVT_KEY_RIGHT_ALT => .right_alt,
        c.HVT_KEY_LEFT_SUPER => .left_super,
        c.HVT_KEY_RIGHT_SUPER => .right_super,
        c.HVT_KEY_LEFT_HYPER => .left_hyper,
        c.HVT_KEY_RIGHT_HYPER => .right_hyper,
        c.HVT_KEY_LEFT_META => .left_meta,
        c.HVT_KEY_RIGHT_META => .right_meta,
        c.HVT_KEY_CAPS_LOCK => .caps_lock,
        c.HVT_KEY_NUM_LOCK => .num_lock,
        c.HVT_KEY_F1 => .f1,
        c.HVT_KEY_F2 => .f2,
        c.HVT_KEY_F3 => .f3,
        c.HVT_KEY_F4 => .f4,
        c.HVT_KEY_F5 => .f5,
        c.HVT_KEY_F6 => .f6,
        c.HVT_KEY_F7 => .f7,
        c.HVT_KEY_F8 => .f8,
        c.HVT_KEY_F9 => .f9,
        c.HVT_KEY_F10 => .f10,
        c.HVT_KEY_F11 => .f11,
        c.HVT_KEY_F12 => .f12,
        c.HVT_KEY_KEYPAD_0 => .keypad_0,
        c.HVT_KEY_KEYPAD_1 => .keypad_1,
        c.HVT_KEY_KEYPAD_2 => .keypad_2,
        c.HVT_KEY_KEYPAD_3 => .keypad_3,
        c.HVT_KEY_KEYPAD_4 => .keypad_4,
        c.HVT_KEY_KEYPAD_5 => .keypad_5,
        c.HVT_KEY_KEYPAD_6 => .keypad_6,
        c.HVT_KEY_KEYPAD_7 => .keypad_7,
        c.HVT_KEY_KEYPAD_8 => .keypad_8,
        c.HVT_KEY_KEYPAD_9 => .keypad_9,
        c.HVT_KEY_KEYPAD_DECIMAL => .keypad_decimal,
        c.HVT_KEY_KEYPAD_ADD => .keypad_add,
        c.HVT_KEY_KEYPAD_SUBTRACT => .keypad_subtract,
        c.HVT_KEY_KEYPAD_MULTIPLY => .keypad_multiply,
        c.HVT_KEY_KEYPAD_DIVIDE => .keypad_divide,
        c.HVT_KEY_KEYPAD_SEPARATOR => .keypad_separator,
        c.HVT_KEY_KEYPAD_EQUAL => .keypad_equal,
        c.HVT_KEY_KEYPAD_ENTER => .keypad_enter,
        else => null,
    };
}
/// Converts the stable native key transition vocabulary.
pub fn keyAction(value: u8) ?Terminal.KeyAction {
    return switch (value) {
        c.HVT_PRESS => .press,
        c.HVT_REPEAT => .repeat,
        c.HVT_RELEASE => .release,
        else => null,
    };
}
/// Converts every defined modifier bit explicitly.
pub fn modifiers(value: u8) Terminal.InputModifier {
    return .{ .shift = value & c.HVT_SHIFT != 0, .alt = value & c.HVT_ALT != 0, .control = value & c.HVT_CONTROL != 0, .super = value & c.HVT_SUPER != 0, .hyper = value & c.HVT_HYPER != 0, .meta = value & c.HVT_META != 0, .caps_lock = value & c.HVT_CAPS_LOCK != 0, .num_lock = value & c.HVT_NUM_LOCK != 0 };
}
/// Converts the stable native mouse event vocabulary.
pub fn mouseKind(value: u8) ?Terminal.MouseEventKind {
    return switch (value) {
        c.HVT_MOUSE_PRESS => .press,
        c.HVT_MOUSE_RELEASE => .release,
        c.HVT_MOUSE_MOVE => .move,
        c.HVT_MOUSE_WHEEL => .wheel,
        else => null,
    };
}
/// Converts the stable native mouse button vocabulary.
pub fn mouseButton(value: u8) ?Terminal.MouseButton {
    return switch (value) {
        c.HVT_BUTTON_NONE => .none,
        c.HVT_BUTTON_LEFT => .left,
        c.HVT_BUTTON_MIDDLE => .middle,
        c.HVT_BUTTON_RIGHT => .right,
        c.HVT_BUTTON_WHEEL_UP => .wheel_up,
        c.HVT_BUTTON_WHEEL_DOWN => .wheel_down,
        else => null,
    };
}
/// Validates physical key input before any caller mutation.
pub fn namedInput(key: u8, action: u8, mods: u8) Error!Terminal.InputEvent {
    return .{ .key = .{ .key = .{ .named = namedKey(key) orelse return error.InvalidArgument }, .action = keyAction(action) orelse return error.InvalidArgument, .mods = modifiers(mods) } };
}
/// Rejects Unicode surrogates and values beyond the scalar range.
pub fn unicodeInput(scalar: u32, action: u8, mods: u8) Error!Terminal.InputEvent {
    if (scalar > 0x10ffff) return error.InvalidArgument;
    const key = Terminal.Key.initUnicode(@intCast(scalar)) catch return error.InvalidArgument;
    return .{ .key = .{ .key = key, .action = keyAction(action) orelse return error.InvalidArgument, .mods = modifiers(mods) } };
}
/// Validates mouse metadata before any caller mutation.
pub fn mouseInput(kind: u8, button: u8, mods: u8, buttons_down: u8, row: i32, column: u16, pixels_present: u8, pixel_x: u32, pixel_y: u32) Error!Terminal.InputEvent {
    if (pixels_present > 1 or buttons_down & 0xf8 != 0) return error.InvalidArgument;
    return .{ .mouse = .{ .kind = mouseKind(kind) orelse return error.InvalidArgument, .button = mouseButton(button) orelse return error.InvalidArgument, .row = row, .col = column, .pixel_x = if (pixels_present == 1) pixel_x else null, .pixel_y = if (pixels_present == 1) pixel_y else null, .mod = modifiers(mods), .buttons_down = buttons_down } };
}
/// Converts the native focus vocabulary.
pub fn focusInput(value: u8) Error!Terminal.InputEvent {
    return .{ .focus = switch (value) {
        c.HVT_FOCUS_IN => .in,
        c.HVT_FOCUS_OUT => .out,
        else => return error.InvalidArgument,
    } };
}
/// Copies one bounded scalar/occupancy record from a synchronous const observation.
pub fn copyCell(observed: *const Terminal.Observation, history: u32, row: u16, column: u16, out: *c.hvt_cell) Error!void {
    out.* = std.mem.zeroes(c.hvt_cell);
    const view = observed.semanticView(history);
    if (row >= view.rows or column >= view.cols) return error.InvalidArgument;
    var storage: [vt.scalar.maximum_scalars]u21 = undefined;
    const values = view.cellScalarsAt(row, column, &storage);
    for (values, 0..) |scalar, index| out.scalars[index] = scalar;
    out.scalar_count = @intCast(values.len);
    const cell = view.cellInfoAt(row, column);
    out.width = cell.width;
    out.height = cell.height;
    out.x = cell.x;
    out.y = cell.y;
}

test "native input vocabulary rejects undefined tags and non-scalars" {
    for (0..256) |v| {
        const value: u8 = @intCast(v);
        try std.testing.expectEqual(value >= 1 and value <= 58, namedKey(value) != null);
        try std.testing.expectEqual(value >= 1 and value <= 3, keyAction(value) != null);
        try std.testing.expectEqual(value >= 1 and value <= 4, mouseKind(value) != null);
        try std.testing.expectEqual(value <= 5, mouseButton(value) != null);
    }
    try std.testing.expectError(error.InvalidArgument, unicodeInput(0xd800, 1, 0));
    try std.testing.expectError(error.InvalidArgument, unicodeInput(0x110000, 1, 0));
    try std.testing.expectError(error.InvalidArgument, focusInput(0));
    try std.testing.expectEqual(@as(u8, 255), @as(u8, @bitCast(modifiers(255))));
}
test "copied native cells retain scalar ownership after terminal mutation" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    // zig-audit: acknowledge discard
    // reason: The proof reads copied cell state rather than the feed summary.
    _ = try terminal.feed("e\xcc\x81");
    var cell: c.hvt_cell = undefined;
    try copyCell(terminal.observation(), 0, 0, 0, &cell);
    // zig-audit: acknowledge discard
    // reason: The proof reads copied cell state rather than the feed summary.
    _ = try terminal.feed("\rX");
    try std.testing.expectEqual(@as(u8, 2), cell.scalar_count);
    try std.testing.expectEqual(@as(u32, 'e'), cell.scalars[0]);
    try std.testing.expectEqual(@as(u32, 0x301), cell.scalars[1]);
}

// C tag spelling is checked against canonical names independently of the conversion switch.
fn upper(comptime name: []const u8) [name.len]u8 {
    var result: [name.len]u8 = undefined;
    for (name, 0..) |byte, index| result[index] = std.ascii.toUpper(byte);
    return result;
}
test "every native key tag means its exact canonical key" {
    @setEvalBranchQuota(10000);
    inline for (@typeInfo(Terminal.NamedKey).@"enum".field_names) |name| {
        const c_name = comptime "HVT_KEY_" ++ upper(name);
        const tag: u8 = @intCast(@field(c, c_name));
        try std.testing.expectEqual(@field(Terminal.NamedKey, name), namedKey(tag).?);
    }
    try std.testing.expectEqual(Terminal.KeyAction.press, keyAction(c.HVT_PRESS).?);
    try std.testing.expectEqual(Terminal.KeyAction.repeat, keyAction(c.HVT_REPEAT).?);
    try std.testing.expectEqual(Terminal.KeyAction.release, keyAction(c.HVT_RELEASE).?);
    try std.testing.expectEqual(Terminal.MouseEventKind.press, mouseKind(c.HVT_MOUSE_PRESS).?);
    try std.testing.expectEqual(Terminal.MouseEventKind.release, mouseKind(c.HVT_MOUSE_RELEASE).?);
    try std.testing.expectEqual(Terminal.MouseEventKind.move, mouseKind(c.HVT_MOUSE_MOVE).?);
    try std.testing.expectEqual(Terminal.MouseEventKind.wheel, mouseKind(c.HVT_MOUSE_WHEEL).?);
    inline for (@typeInfo(Terminal.MouseButton).@"enum".field_names) |name| {
        const c_name = comptime "HVT_BUTTON_" ++ upper(name);
        try std.testing.expectEqual(@field(Terminal.MouseButton, name), mouseButton(@intCast(@field(c, c_name))).?);
    }
    const gained = try focusInput(c.HVT_FOCUS_IN);
    const lost = try focusInput(c.HVT_FOCUS_OUT);
    try std.testing.expect(gained.focus == .in and lost.focus == .out);
    try std.testing.expectEqualDeep(Terminal.InputModifier{ .shift = true }, modifiers(c.HVT_SHIFT));
    try std.testing.expectEqualDeep(Terminal.InputModifier{ .alt = true }, modifiers(c.HVT_ALT));
    try std.testing.expectEqualDeep(Terminal.InputModifier{ .control = true }, modifiers(c.HVT_CONTROL));
    try std.testing.expectEqualDeep(Terminal.InputModifier{ .super = true }, modifiers(c.HVT_SUPER));
    try std.testing.expectEqualDeep(Terminal.InputModifier{ .hyper = true }, modifiers(c.HVT_HYPER));
    try std.testing.expectEqualDeep(Terminal.InputModifier{ .meta = true }, modifiers(c.HVT_META));
    try std.testing.expectEqualDeep(Terminal.InputModifier{ .caps_lock = true }, modifiers(c.HVT_CAPS_LOCK));
    try std.testing.expectEqualDeep(Terminal.InputModifier{ .num_lock = true }, modifiers(c.HVT_NUM_LOCK));
}
test "native occupancy distinguishes wide and sized text continuations" {
    var terminal = try Terminal.init(std.testing.allocator, 4, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("界")).stateChanged());
    var lead: c.hvt_cell = undefined;
    var continuation: c.hvt_cell = undefined;
    try copyCell(terminal.observation(), 0, 0, 0, &lead);
    try copyCell(terminal.observation(), 0, 0, 1, &continuation);
    try std.testing.expectEqual(@as(u8, 2), lead.width);
    try std.testing.expectEqual(@as(u8, 0), lead.x);
    try std.testing.expectEqual(@as(u8, 1), continuation.x);
    try std.testing.expectEqualSlices(u32, &lead.scalars, &continuation.scalars);
    try std.testing.expect((try terminal.feed("\x1b[2J\x1b[H\x1b]66;s=2:w=2:n=1:d=2:v=1:h=2;Hi\x1b\\")).stateChanged());
    try copyCell(terminal.observation(), 0, 0, 0, &lead);
    try copyCell(terminal.observation(), 0, 1, 3, &continuation);
    try std.testing.expectEqual(@as(u8, 4), lead.width);
    try std.testing.expectEqual(@as(u8, 2), lead.height);
    try std.testing.expectEqual(@as(u8, 3), continuation.x);
    try std.testing.expectEqual(@as(u8, 1), continuation.y);
    try std.testing.expectEqual(@as(u8, 2), continuation.scalar_count);
    try std.testing.expect((try terminal.feed("\x1b[2J")).stateChanged());
    try std.testing.expectEqual(@as(u32, 'H'), continuation.scalars[0]);
    try std.testing.expectEqual(@as(u32, 'i'), continuation.scalars[1]);
}
