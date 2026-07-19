//! Defines mouse input values and encodes enabled terminal mouse protocols.

const std = @import("std");
const keyboard = @import("keyboard.zig");

/// Mouse button values.
const MouseButton = enum(u8) {
    none = 0,
    left = 1,
    middle = 2,
    right = 3,
    wheel_up = 4,
    wheel_down = 5,
};

/// Mouse event kinds.
const MouseEventKind = enum(u8) {
    press,
    release,
    move,
    wheel,
};

/// Host mouse event payload.
pub const MouseEvent = struct {
    kind: MouseEventKind,
    button: MouseButton,
    row: i32,
    col: u16,
    pixel_x: ?u32 = null,
    pixel_y: ?u32 = null,
    mod: keyboard.Modifier,
    buttons_down: u8,
};

/// Selects which host mouse events the terminal has requested.
pub const MouseTrackingMode = enum(u8) {
    off,
    x10,
    normal,
    button_event,
    any_event,
};

/// Selects the negotiated byte encoding for mouse reports.
pub const MouseProtocol = enum(u8) {
    none,
    utf8,
    sgr,
    urxvt,
};

fn wouldEncodeMouse(event: MouseEvent, tracking: MouseTrackingMode, protocol: MouseProtocol) bool {
    if (tracking == .off) return false;

    const emit = switch (event.kind) {
        .press, .wheel => true,
        .release => tracking != .x10 and event.button != .wheel_up and event.button != .wheel_down,
        .move => switch (tracking) {
            .button_event => event.buttons_down != 0,
            .any_event => true,
            else => false,
        },
    };
    if (!emit) return false;

    if (protocol == .sgr or protocol == .urxvt or protocol == .utf8) return true;
    const row1 = if (event.row < 0) 1 else event.row + 1;
    const col1 = @as(u32, event.col) + 1;
    const cb = mouseCode(event, tracking);
    return cb <= 223 and col1 <= 223 and @as(u32, @intCast(row1)) <= 223;
}

/// Encode one host mouse event for the active terminal mouse protocol.
pub fn encodeMouse(buf: []u8, event: MouseEvent, tracking: MouseTrackingMode, protocol: MouseProtocol) []const u8 {
    if (!wouldEncodeMouse(event, tracking, protocol)) return buf[0..0];

    const row1 = if (event.row < 0) 1 else event.row + 1;
    const col1 = @as(u32, event.col) + 1;
    const cb = mouseCode(event, tracking);
    return switch (protocol) {
        .sgr => encodeSgrMouse(buf, cb, col1, @intCast(row1), event.kind == .release),
        .urxvt => encodeUrxvtMouse(buf, cb, col1, @intCast(row1)),
        .utf8 => encodeCsiMMouse(buf, cb, col1, @intCast(row1), true),
        .none => encodeCsiMMouse(buf, cb, col1, @intCast(row1), false),
    };
}

fn mouseCode(event: MouseEvent, tracking: MouseTrackingMode) u16 {
    var code: u16 = switch (event.kind) {
        .press => pressButtonCode(event.button),
        .release => 3,
        .wheel => wheelButtonCode(event.button),
        .move => moveBaseCode(event),
    };
    if (tracking != .x10) {
        if (event.mod.shift) code += 4;
        if (event.mod.alt) code += 8;
        if (event.mod.control) code += 16;
    }
    if (event.kind == .move) code += 32;
    return code;
}

fn encodeSgrMouse(buf: []u8, cb: u16, col1: u32, row1: u32, release: bool) []const u8 {
    const final: u8 = if (release) 'm' else 'M';
    return std.fmt.bufPrint(buf, "\x1b[<{d};{d};{d}{c}", .{ cb, col1, row1, final }) catch buf[0..0];
}

fn encodeUrxvtMouse(buf: []u8, cb: u16, col1: u32, row1: u32) []const u8 {
    return std.fmt.bufPrint(buf, "\x1b[{d};{d};{d}M", .{ cb + 32, col1, row1 }) catch buf[0..0];
}

fn encodeCsiMMouse(buf: []u8, cb: u16, col1: u32, row1: u32, utf8: bool) []const u8 {
    if (!utf8 and (cb > 223 or col1 > 223 or row1 > 223)) return buf[0..0];
    var idx: u8 = 0;
    buf[idx] = '\x1b';
    idx += 1;
    buf[idx] = '[';
    idx += 1;
    buf[idx] = 'M';
    idx += 1;
    idx += encodeMouseNumber(buf[idx..], cb + 32, utf8);
    idx += encodeMouseNumber(buf[idx..], col1 + 32, utf8);
    idx += encodeMouseNumber(buf[idx..], row1 + 32, utf8);
    return buf[0..idx];
}

fn encodeMouseNumber(out: []u8, value: u32, utf8: bool) u8 {
    if (!utf8 or value < 128) {
        out[0] = @intCast(value);
        return 1;
    }
    return @intCast(std.unicode.utf8Encode(@intCast(value), out) catch 0);
}

fn pressButtonCode(button: MouseButton) u16 {
    return switch (button) {
        .left => 0,
        .middle => 1,
        .right => 2,
        .wheel_up => 64,
        .wheel_down => 65,
        .none => 3,
    };
}

fn wheelButtonCode(button: MouseButton) u16 {
    return switch (button) {
        .wheel_up => 64,
        .wheel_down => 65,
        else => pressButtonCode(button),
    };
}

fn moveBaseCode(event: MouseEvent) u16 {
    if ((event.buttons_down & 0x01) != 0) return 0;
    if ((event.buttons_down & 0x02) != 0) return 1;
    if ((event.buttons_down & 0x04) != 0) return 2;
    return 3;
}
