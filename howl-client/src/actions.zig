//! Canonical client-side session operations.
//!
//! These functions serialize existing howl-session requests only. Terminal input
//! encoding remains owned by howl-vt on the session side.

const std = @import("std");
const protocol = @import("howl_session").protocol;
const client = @import("client.zig");

pub const Error = client.Error || std.mem.Allocator.Error || protocol.PayloadError || error{
    InvalidText,
    InvalidResize,
    RequestTooLarge,
    TypedInputUnsupported,
    ResizeUnsupported,
    UnexpectedFrame,
    ServerRejected,
};

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

pub fn unicodeKey(
    connection: *client.Connection,
    scalar: u32,
    action: protocol.InputKeyAction,
    modifiers: u8,
) Error!void {
    if (connection.features & protocol.feature(.typed_input) == 0)
        return error.TypedInputUnsupported;
    var body_storage: [protocol.typed_input.key_header_bytes]u8 = undefined;
    const body = protocol.encodeKeyInput(&body_storage, .{
        .kind = .unicode,
        .key_value = scalar,
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
