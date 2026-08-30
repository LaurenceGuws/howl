const std = @import("std");
const protocol = @import("howl_session").protocol;
const client = @import("howl_client");

pub const Error = client.Error || std.mem.Allocator.Error || protocol.PayloadError || error{
    InvalidText,
    InvalidKey,
    InvalidKeyAction,
    InvalidModifiers,
    InvalidFocus,
    InvalidResize,
    InvalidSignal,
    RequestTooLarge,
    TypedInputUnsupported,
    ResizeUnsupported,
    UnexpectedFrame,
    ServerRejected,
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

pub fn committedText(connection: *client.Connection, bytes: []const u8) Error!void {
    if (bytes.len == 0 or !std.unicode.utf8ValidateSlice(bytes)) return error.InvalidText;
    try sendBytesInput(connection, .bytes, bytes);
    try expectOk(connection, .input);
}

pub fn paste(connection: *client.Connection, bytes: []const u8) Error!void {
    if (bytes.len == 0) return error.InvalidText;
    try sendBytesInput(connection, .paste, bytes);
    try expectOk(connection, .input);
}

pub fn namedKey(
    connection: *client.Connection,
    key: protocol.InputKeyName,
    action: protocol.InputKeyAction,
    modifiers: u8,
) Error!void {
    if (connection.features & protocol.feature(.typed_input) == 0)
        return error.TypedInputUnsupported;
    var body_storage: [protocol.typed_input.key_header_bytes]u8 = undefined;
    const body = protocol.encodeKeyInput(&body_storage, .{
        .kind = .named,
        .key_value = @backingInt(key),
        .action = action,
        .modifiers = modifiers,
    }) catch |failure| switch (failure) {
        error.OutputTooSmall => unreachable,
        else => |err| return err,
    };
    var payload: [1 + protocol.typed_input.key_header_bytes]u8 = undefined;
    payload[0] = @backingInt(protocol.InputKind.key);
    @memcpy(payload[1 .. 1 + body.len], body);
    try connection.send(.input, payload[0 .. 1 + body.len]);
    try expectOk(connection, .input);
}

pub fn focus(connection: *client.Connection, value: protocol.InputFocus) Error!void {
    if (connection.features & protocol.feature(.typed_input) == 0)
        return error.TypedInputUnsupported;
    var body: [protocol.typed_input.focus_bytes]u8 = undefined;
    protocol.encodeFocusInput(&body, value);
    var payload: [1 + protocol.typed_input.focus_bytes]u8 = undefined;
    payload[0] = @backingInt(protocol.InputKind.focus);
    @memcpy(payload[1..], &body);
    try connection.send(.input, &payload);
    try expectOk(connection, .input);
}

pub fn resize(connection: *client.Connection, rows: u16, columns: u16) Error!void {
    if (rows == 0 or columns == 0) return error.InvalidResize;
    if (connection.features & protocol.feature(.resize_leader) == 0)
        return error.ResizeUnsupported;
    var leader_payload: [protocol.payload_bytes.assign_leader]u8 = undefined;
    protocol.encodeAssignLeader(&leader_payload, .{ .client_id = connection.client_id });
    try connection.send(.assign_leader, &leader_payload);
    try expectOk(connection, .assign_leader);

    var resize_payload: [protocol.payload_bytes.resize]u8 = undefined;
    protocol.encodeResize(&resize_payload, .{ .rows = rows, .columns = columns });
    try connection.send(.resize, &resize_payload);
    try expectOk(connection, .resize);
}

pub fn signal(connection: *client.Connection, value: protocol.Signal) Error!void {
    var payload: [protocol.payload_bytes.signal]u8 = undefined;
    protocol.encodeSignal(&payload, value);
    try connection.send(.signal, &payload);
    try expectOk(connection, .signal);
}

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

fn sendBytesInput(
    connection: *client.Connection,
    kind: protocol.InputKind,
    bytes: []const u8,
) Error!void {
    if (bytes.len + 1 > protocol.maximum_request_payload_bytes) return error.RequestTooLarge;
    const payload = try connection.allocator.alloc(u8, bytes.len + 1);
    defer connection.allocator.free(payload);
    payload[0] = @backingInt(kind);
    @memcpy(payload[1..], bytes);
    try connection.send(.input, payload);
}

fn expectOk(connection: *client.Connection, expected: protocol.Kind) Error!void {
    var frame = try connection.receive();
    defer frame.deinit();
    if (frame.kind != .result) return error.UnexpectedFrame;
    const result = try protocol.decodeResult(frame.payload);
    if (result.request_kind != expected) return error.UnexpectedFrame;
    if (result.code != .ok) return error.ServerRejected;
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
