//! Canonical client-side Instance operations.
//!
//! These functions serialize existing Howl Instance requests only. Terminal input
//! encoding remains owned by howl-vt on the Instance side.

const std = @import("std");
const protocol = @import("howl_instance_protocol");
const client = @import("client.zig");

/// Reports local validation, transport, framing, and server action failures.
pub const Error = client.Error || std.mem.Allocator.Error || protocol.PayloadError || error{
    InvalidText,
    InvalidResize,
    RequestTooLarge,
    UnexpectedFrame,
    ServerRejected,
    NotGeometryLeader,
};

/// Sends one validated committed UTF-8 text input event.
pub fn committedText(connection: *client.Connection, bytes: []const u8) Error!void {
    if (bytes.len == 0 or !std.unicode.utf8ValidateSlice(bytes)) return error.InvalidText;
    try sendBytesInput(connection, .bytes, bytes);
    try expectOk(connection, .input);
}

/// Sends one nonempty paste payload for terminal-side paste semantics.
pub fn paste(connection: *client.Connection, bytes: []const u8) Error!void {
    if (bytes.len == 0) return error.InvalidText;
    try sendBytesInput(connection, .paste, bytes);
    try expectOk(connection, .input);
}

/// Sends one named physical-key transition with exact modifier bits.
pub fn namedKey(
    connection: *client.Connection,
    key: protocol.InputKeyName,
    action: protocol.InputKeyAction,
    modifiers: u8,
) Error!void {
    return keyInput(connection, .{ .kind = .named, .key_value = @backingInt(key), .action = action, .modifiers = modifiers });
}

/// Sends one Unicode physical-key transition with exact modifier bits.
pub fn unicodeKey(connection: *client.Connection, scalar: u32, action: protocol.InputKeyAction, modifiers: u8) Error!void {
    return keyInput(connection, .{ .kind = .unicode, .key_value = scalar, .action = action, .modifiers = modifiers });
}

/// Sends one complete bounded typed physical-key event, including alternate identities and text.
pub fn keyInput(connection: *client.Connection, value: protocol.KeyInput) Error!void {
    var payload: [
        1 + protocol.typed_input.key_header_bytes +
            protocol.typed_input.maximum_legacy_key_bytes + protocol.typed_input.maximum_key_text_bytes
    ]u8 = undefined;
    const body = protocol.encodeKeyInput(payload[1..], value) catch |failure| switch (failure) {
        // zig-audit: acknowledge unreachable
        // reason: The scratch includes the fixed header and both independently bounded text maxima; validated input always fits.
        error.OutputTooSmall => unreachable,
        else => |err| return err,
    };
    payload[0] = @backingInt(protocol.InputKind.key);
    try connection.send(.input, payload[0 .. 1 + body.len]);
    try expectOk(connection, .input);
}

/// Sends one canonical terminal mouse input event.
pub fn mouse(connection: *client.Connection, value: protocol.MouseInput) Error!void {
    var body: [protocol.typed_input.mouse_bytes]u8 = undefined;
    try protocol.encodeMouseInput(&body, value);
    var payload: [1 + protocol.typed_input.mouse_bytes]u8 = undefined;
    payload[0] = @backingInt(protocol.InputKind.mouse);
    @memcpy(payload[1..], &body);
    try connection.send(.input, &payload);
    try expectOk(connection, .input);
}

/// Sends one canonical terminal focus transition.
pub fn focus(connection: *client.Connection, value: protocol.InputFocus) Error!void {
    var body: [protocol.typed_input.focus_bytes]u8 = undefined;
    protocol.encodeFocusInput(&body, value);
    var payload: [1 + protocol.typed_input.focus_bytes]u8 = undefined;
    payload[0] = @backingInt(protocol.InputKind.focus);
    @memcpy(payload[1..], &body);
    try connection.send(.input, &payload);
    try expectOk(connection, .input);
}

/// Acquires geometry authority and applies rows/columns with unchanged cell pixels.
pub fn resize(connection: *client.Connection, rows: u16, columns: u16) Error!void {
    return resizeGeometry(connection, .{ .rows = rows, .columns = columns });
}

/// Explicitly acquires geometry authority, then applies cell/pixel dimensions.
pub fn resizeGeometry(connection: *client.Connection, geometry: protocol.Resize) Error!void {
    if (geometry.rows == 0 or geometry.columns == 0 or
        (geometry.cell_pixel_width == 0) != (geometry.cell_pixel_height == 0))
        return error.InvalidResize;
    try acquireGeometry(connection);
    try resizeGeometryOwned(connection, geometry);
}

/// Explicitly takes geometry authority without changing the canonical grid.
pub fn acquireGeometry(connection: *client.Connection) Error!void {
    var leader_payload: [protocol.payload_bytes.assign_leader]u8 = undefined;
    protocol.encodeAssignLeader(&leader_payload, .{ .client_id = connection.client_id });
    try connection.send(.assign_leader, &leader_payload);
    try expectOk(connection, .assign_leader);
}

/// Resizes only while this exact connection already owns geometry authority.
/// Unlike `resize`, this never assigns or steals leadership first.
pub fn resizeOwned(connection: *client.Connection, rows: u16, columns: u16) Error!void {
    return resizeGeometryOwned(connection, .{ .rows = rows, .columns = columns });
}

/// Applies v8 cell/pixel geometry without acquiring or stealing leadership.
pub fn resizeGeometryOwned(connection: *client.Connection, geometry: protocol.Resize) Error!void {
    if (geometry.rows == 0 or geometry.columns == 0 or
        (geometry.cell_pixel_width == 0) != (geometry.cell_pixel_height == 0))
        return error.InvalidResize;
    var resize_payload: [protocol.payload_bytes.resize]u8 = undefined;
    protocol.encodeResize(&resize_payload, geometry);
    try connection.send(.resize, &resize_payload);
    try expectOk(connection, .resize);
}

/// Sends one process-group signal request to the attached Instance.
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
    try checkResult(expected, result);
}

// Authority loss is a completed, nonfatal resize response, not a broken stream.
// Preserve that distinction without weakening other action acknowledgements.
fn checkResult(expected: protocol.Kind, result: protocol.Result) Error!void {
    if (result.request_kind != expected) return error.UnexpectedFrame;
    if (expected == .resize and result.code == .not_leader) return error.NotGeometryLeader;
    if (result.code != .ok) return error.ServerRejected;
}

test "resize distinguishes authority loss from rejection and malformed acknowledgements" {
    try checkResult(.resize, .{ .request_kind = .resize, .code = .ok });
    try std.testing.expectError(error.NotGeometryLeader, checkResult(.resize, .{ .request_kind = .resize, .code = .not_leader }));
    try std.testing.expectError(error.ServerRejected, checkResult(.resize, .{ .request_kind = .resize, .code = .rejected }));
    try std.testing.expectError(error.UnexpectedFrame, checkResult(.resize, .{ .request_kind = .input, .code = .not_leader }));
    try std.testing.expectError(error.ServerRejected, checkResult(.input, .{ .request_kind = .input, .code = .not_leader }));
}

fn testTransfer(fd: std.posix.fd_t, output: ?[]u8, input: ?[]const u8) !void {
    var offset: usize = 0;
    const len = if (output) |value| value.len else input.?.len;
    while (offset < len) {
        const result = if (output) |value| std.posix.system.read(fd, value[offset..].ptr, len - offset) else std.posix.system.write(fd, input.?[offset..].ptr, len - offset);
        switch (std.posix.errno(result)) {
            .SUCCESS => {
                if (result == 0 or result > len - offset) return error.TestTransferFailed;
                offset += result;
            },
            .INTR => continue,
            else => return error.TestTransferFailed,
        }
    }
}
fn testClose(fd: std.posix.fd_t) void {
    const result = std.posix.system.close(fd);
    std.debug.assert(std.posix.errno(result) == .SUCCESS or std.posix.errno(result) == .INTR);
}
test "complete typed physical key preserves alternate identities and maximum text without borrowing caller storage" {
    var pair: [2]std.posix.fd_t = undefined;
    if (std.posix.errno(std.posix.system.socketpair(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0, &pair)) != .SUCCESS) return error.TestSocketFailed;
    defer testClose(pair[1]);
    const transport = @import("client_transport");
    var diagnostic: client.ConnectDiagnostic = .{};
    var connection = client.Connection{ .allocator = std.testing.allocator, .stream = try transport.Stream.adopt(pair[0], &diagnostic, null), .client_id = 9 };
    defer connection.deinit();
    try connection.stream.finishHandshake(&diagnostic);
    var ack_header: [protocol.header_bytes]u8 = undefined;
    var ack: [protocol.payload_bytes.result]u8 = undefined;
    try protocol.encodeHeader(&ack_header, .{ .kind = .result, .payload_len = ack.len });
    protocol.encodeResult(&ack, .{ .request_kind = .input, .code = .ok });
    try testTransfer(pair[1], null, &ack_header);
    try testTransfer(pair[1], null, &ack);
    var legacy: [protocol.typed_input.maximum_legacy_key_bytes]u8 = @splat('L');
    var text: [protocol.typed_input.maximum_key_text_bytes]u8 = @splat('T');
    try keyInput(&connection, .{ .kind = .unicode, .key_value = 'a', .action = .repeat, .modifiers = 0xff, .shifted = 0x754c, .alternate = 0x3bb, .legacy_text = &legacy, .text = &text });
    @memset(&legacy, '?');
    @memset(&text, '?');
    var header_bytes: [protocol.header_bytes]u8 = undefined;
    try testTransfer(pair[1], &header_bytes, null);
    const header = try protocol.decodeHeader(&header_bytes);
    try std.testing.expectEqual(protocol.Kind.input, header.kind);
    var body: [1 + protocol.typed_input.key_header_bytes + protocol.typed_input.maximum_legacy_key_bytes + protocol.typed_input.maximum_key_text_bytes]u8 = undefined;
    try std.testing.expectEqual(body.len, header.payload_len);
    try testTransfer(pair[1], &body, null);
    try std.testing.expectEqual(@backingInt(protocol.InputKind.key), body[0]);
    const decoded = try protocol.decodeKeyInput(body[1..]);
    try std.testing.expectEqual(@as(u32, 'a'), decoded.key_value);
    try std.testing.expectEqual(protocol.InputKeyAction.repeat, decoded.action);
    try std.testing.expectEqual(@as(u8, 0xff), decoded.modifiers);
    try std.testing.expectEqual(@as(?u32, 0x754c), decoded.shifted);
    try std.testing.expectEqual(@as(?u32, 0x3bb), decoded.alternate);
    for (decoded.legacy_text) |byte| try std.testing.expectEqual(@as(u8, 'L'), byte);
    for (decoded.text) |byte| try std.testing.expectEqual(@as(u8, 'T'), byte);
    try std.testing.expectError(error.InvalidPayload, keyInput(&connection, .{ .kind = .unicode, .key_value = 0xd800, .action = .press }));
    var fds = [_]std.posix.pollfd{.{ .fd = pair[1], .events = std.posix.POLL.IN, .revents = 0 }};
    try std.testing.expectEqual(@as(usize, 0), try std.posix.poll(&fds, 0));
}
