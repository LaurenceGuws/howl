const std = @import("std");
const protocol = @import("howl_session").protocol;
const client = @import("howl_client");

pub const Error = error{
    InvalidKey,
    InvalidKeyAction,
    InvalidModifiers,
    InvalidFocus,
    InvalidSignal,
};

pub const Receipt = struct {
    schema: []const u8 = "howl.action/v1",
    operation: []const u8,
    result: []const u8 = "ok",
};

pub fn emitReceipt(writer: *std.Io.Writer, operation: []const u8) !void {
    try std.json.Stringify.value(Receipt{ .operation = operation }, .{}, writer);
    try writer.writeByte('\n');
}

pub const committedText = client.actions.committedText;
pub const paste = client.actions.paste;
pub const namedKey = client.actions.namedKey;
pub const focus = client.actions.focus;
pub const resize = client.actions.resize;
pub const signal = client.actions.signal;

pub fn parseKey(text: []const u8) Error!protocol.InputKeyName {
    if (text.len == 0 or text.len > 31) return error.InvalidKey;
    var normalized: [32]u8 = undefined;
    for (text, 0..) |byte, index| normalized[index] = if (byte == '-') '_' else byte;
    return std.meta.stringToEnum(protocol.InputKeyName, normalized[0..text.len]) orelse error.InvalidKey;
}

pub fn parseKeyAction(text: []const u8) Error!protocol.InputKeyAction {
    return std.meta.stringToEnum(protocol.InputKeyAction, text) orelse error.InvalidKeyAction;
}

pub fn parseModifiers(text: []const u8) Error!u8 {
    if (text.len == 0) return 0;
    var result: u8 = 0;
    var parts = std.mem.splitScalar(u8, text, '+');
    while (parts.next()) |part| {
        const bit: u8 = if (std.mem.eql(u8, part, "shift"))
            protocol.typed_input.modifiers.shift
        else if (std.mem.eql(u8, part, "alt"))
            protocol.typed_input.modifiers.alt
        else if (std.mem.eql(u8, part, "ctrl") or std.mem.eql(u8, part, "control"))
            protocol.typed_input.modifiers.control
        else if (std.mem.eql(u8, part, "super"))
            protocol.typed_input.modifiers.super
        else if (std.mem.eql(u8, part, "hyper"))
            protocol.typed_input.modifiers.hyper
        else if (std.mem.eql(u8, part, "meta"))
            protocol.typed_input.modifiers.meta
        else if (std.mem.eql(u8, part, "caps-lock") or std.mem.eql(u8, part, "caps_lock"))
            protocol.typed_input.modifiers.caps_lock
        else if (std.mem.eql(u8, part, "num-lock") or std.mem.eql(u8, part, "num_lock"))
            protocol.typed_input.modifiers.num_lock
        else
            return error.InvalidModifiers;
        if (result & bit != 0) return error.InvalidModifiers;
        result |= bit;
    }
    return result;
}

pub fn parseFocus(text: []const u8) Error!protocol.InputFocus {
    if (std.mem.eql(u8, text, "in")) return .in;
    if (std.mem.eql(u8, text, "out")) return .out;
    return error.InvalidFocus;
}

pub fn parseSignal(text: []const u8) Error!protocol.Signal {
    if (std.mem.eql(u8, text, "hangup")) return .hangup;
    if (std.mem.eql(u8, text, "interrupt")) return .interrupt;
    if (std.mem.eql(u8, text, "resize-notify") or std.mem.eql(u8, text, "resize_notify")) return .resize_notify;
    if (std.mem.eql(u8, text, "kill")) return .kill;
    if (std.mem.eql(u8, text, "terminate")) return .terminate;
    return error.InvalidSignal;
}

test "CLI key and modifier names map only to frozen protocol vocabulary" {
    try std.testing.expectEqual(protocol.InputKeyName.page_up, try parseKey("page-up"));
    try std.testing.expectEqual(protocol.InputKeyName.keypad_enter, try parseKey("keypad_enter"));
    try std.testing.expectError(error.InvalidKey, parseKey("c"));
    try std.testing.expectEqual(
        protocol.typed_input.modifiers.control | protocol.typed_input.modifiers.shift,
        try parseModifiers("ctrl+shift"),
    );
    try std.testing.expectError(error.InvalidModifiers, parseModifiers("ctrl+ctrl"));
    try std.testing.expectError(error.InvalidModifiers, parseModifiers("banana"));
}
