//! Owns one explicit connection to the frozen Howl Instance byte stream.
//!
//! Endpoint selection is supplied by the caller. Ordered-stream mechanics are
//! shared with other Howl protocols while HWLS framing stays Instance-specific.

const std = @import("std");
const posix = std.posix;
const protocol = @import("howl_instance_protocol");
const transport = @import("client_transport");

pub const ConnectStage = transport.ConnectStage;
pub const ConnectDiagnostic = transport.ConnectDiagnostic;
pub const Cancellation = transport.Cancellation;
pub const Interrupt = transport.Interrupt;
pub const Error = std.mem.Allocator.Error || transport.Error || protocol.HeaderError || protocol.PayloadError || error{
    UnexpectedHandshakeFrame,
};

pub const Frame = struct {
    allocator: std.mem.Allocator,
    kind: protocol.Kind,
    payload: []u8,

    pub fn deinit(self: *Frame) void {
        self.allocator.free(self.payload);
        self.* = undefined;
    }
};

pub const Connection = struct {
    allocator: std.mem.Allocator,
    stream: transport.Stream,
    client_id: protocol.ClientId,

    pub fn connect(allocator: std.mem.Allocator, endpoint: []const u8) Error!Connection {
        var diagnostic: ConnectDiagnostic = .{};
        return connectDiagnosed(allocator, endpoint, &diagnostic);
    }

    pub fn connectDiagnosed(
        allocator: std.mem.Allocator,
        endpoint: []const u8,
        diagnostic: *ConnectDiagnostic,
    ) Error!Connection {
        const stream = try transport.Stream.connectDiagnosed(endpoint, diagnostic);
        return connectTransport(allocator, stream, diagnostic);
    }

    pub fn connectCancelable(
        allocator: std.mem.Allocator,
        endpoint: []const u8,
        diagnostic: *ConnectDiagnostic,
        interrupt: ?*Interrupt,
    ) Error!Connection {
        const stream = try transport.Stream.connectCancelable(endpoint, diagnostic, interrupt);
        return connectTransport(allocator, stream, diagnostic);
    }

    pub fn deinit(self: *Connection) void {
        self.stream.deinit();
        self.* = undefined;
    }

    /// Borrows the ordered stream descriptor for readiness polling only.
    pub fn readinessFd(self: *const Connection) transport.Handle {
        return self.stream.readinessFd();
    }

    /// Creates an independently owned duplicate which may wake a blocked receive.
    pub fn cancellation(self: *const Connection) error{ SocketDuplicateFailed, SocketOptionFailed }!Cancellation {
        return self.stream.cancellation();
    }

    pub fn send(self: *Connection, kind: protocol.Kind, payload: []const u8) Error!void {
        if (payload.len > protocol.maximum_request_payload_bytes) return error.PayloadTooLarge;
        var header: [protocol.header_bytes]u8 = undefined;
        try protocol.encodeHeader(&header, .{ .kind = kind, .payload_len = @intCast(payload.len) });
        try self.stream.write(&header);
        try self.stream.write(payload);
    }

    /// Receives one nonempty frame of the expected kind into caller storage.
    /// Any error retires the stream; a partial body may already be consumed.
    pub fn receiveInto(self: *Connection, expected_kind: protocol.Kind, destination: []u8) Error!usize {
        var header_bytes: [protocol.header_bytes]u8 = undefined;
        try self.stream.read(&header_bytes);
        const header = try protocol.decodeHeader(&header_bytes);
        if (header.kind != expected_kind or header.payload_len == 0 or
            header.payload_len > destination.len)
            return error.InvalidPayload;
        try self.stream.read(destination[0..header.payload_len]);
        return header.payload_len;
    }

    pub fn receive(self: *Connection) Error!Frame {
        var header_bytes: [protocol.header_bytes]u8 = undefined;
        try self.stream.read(&header_bytes);
        const header = try protocol.decodeHeader(&header_bytes);
        const payload = try self.allocator.alloc(u8, header.payload_len);
        errdefer self.allocator.free(payload);
        try self.stream.read(payload);
        return .{ .allocator = self.allocator, .kind = header.kind, .payload = payload };
    }
};

/// Completes the HWLS handshake over one already-owned native transport stream.
pub fn connectTransport(
    allocator: std.mem.Allocator,
    stream_value: transport.Stream,
    diagnostic: *ConnectDiagnostic,
) Error!Connection {
    var stream = stream_value;
    errdefer stream.deinit();
    try stream.beginHandshake(diagnostic);
    diagnostic.stage = .hello_write;
    var hello: [protocol.header_bytes]u8 = undefined;
    try protocol.encodeHeader(&hello, .{ .kind = .hello, .payload_len = 0 });
    try stream.handshakeWrite(&hello);
    diagnostic.stage = .welcome_read;
    var header_bytes: [protocol.header_bytes]u8 = undefined;
    try stream.handshakeRead(&header_bytes);
    const header = try protocol.decodeHeader(&header_bytes);
    if (header.kind != .welcome) {
        diagnostic.stage = .welcome_kind;
        return error.UnexpectedHandshakeFrame;
    }
    diagnostic.stage = .welcome_payload;
    if (header.payload_len != protocol.payload_bytes.welcome) return error.InvalidPayload;
    var payload: [protocol.payload_bytes.welcome]u8 = undefined;
    try stream.handshakeRead(&payload);
    const welcome = try protocol.decodeWelcome(&payload);
    try stream.finishHandshake(diagnostic);
    return .{ .allocator = allocator, .stream = stream, .client_id = welcome.client_id };
}

test "diagnosed connect retains the failing endpoint stage" {
    var diagnostic: ConnectDiagnostic = .{};
    try std.testing.expectError(
        error.InvalidEndpoint,
        Connection.connectDiagnosed(std.testing.allocator, "tcp://named-host:43127", &diagnostic),
    );
    try std.testing.expectEqual(ConnectStage.endpoint, diagnostic.stage);
    try std.testing.expectEqual(@as(i32, 0), diagnostic.os_error);
}

test "unsupported route schemes are rejected" {
    var diagnostic: ConnectDiagnostic = .{};
    try std.testing.expectError(
        error.InvalidEndpoint,
        Connection.connectDiagnosed(std.testing.allocator, "https://example.invalid/a", &diagnostic),
    );
    try std.testing.expectEqual(ConnectStage.endpoint, diagnostic.stage);
}

fn testSocketPair() [2]posix.fd_t {
    var pair: [2]posix.fd_t = undefined;
    const result = posix.system.socketpair(posix.AF.UNIX, posix.SOCK.STREAM, 0, &pair);
    if (posix.errno(result) != .SUCCESS) @panic("test socketpair failed");
    return pair;
}

fn testClose(fd: posix.fd_t) void {
    const result = posix.system.close(fd);
    const status = posix.errno(result);
    std.debug.assert(status == .SUCCESS or status == .INTR);
}

fn testReadExact(fd: posix.fd_t, output: []u8) !void {
    var offset: usize = 0;
    while (offset < output.len) {
        const result = posix.system.read(fd, output[offset..].ptr, output.len - offset);
        switch (posix.errno(result)) {
            .SUCCESS => {
                if (result == 0 or result > output.len - offset) return error.TestReadFailed;
                offset += result;
            },
            .INTR => continue,
            else => return error.TestReadFailed,
        }
    }
}

fn testWriteAll(fd: posix.fd_t, bytes: []const u8) !void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        const result = posix.system.write(fd, bytes[offset..].ptr, bytes.len - offset);
        switch (posix.errno(result)) {
            .SUCCESS => {
                if (result == 0 or result > bytes.len - offset) return error.TestWriteFailed;
                offset += result;
            },
            .INTR => continue,
            else => return error.TestWriteFailed,
        }
    }
}

fn testHandshakePeer(fd: posix.fd_t) void {
    defer testClose(fd);
    var header: [protocol.header_bytes]u8 = undefined;
    testReadExact(fd, &header) catch @panic("hello header");
    const decoded = protocol.decodeHeader(&header) catch @panic("hello frame");
    if (decoded.kind != .hello or decoded.payload_len != 0) @panic("wrong hello");
    var welcome: [protocol.payload_bytes.welcome]u8 = undefined;
    protocol.encodeWelcome(&welcome, .{ .client_id = 71 });
    var response: [protocol.header_bytes]u8 = undefined;
    protocol.encodeHeader(&response, .{ .kind = .welcome, .payload_len = welcome.len }) catch @panic("welcome header");
    testWriteAll(fd, &response) catch @panic("welcome header write");
    testWriteAll(fd, &welcome) catch @panic("welcome write");
}

fn testHandshakePeerUntilClosed(fd: posix.fd_t) void {
    defer testClose(fd);
    var header: [protocol.header_bytes]u8 = undefined;
    testReadExact(fd, &header) catch @panic("hello header");
    const decoded = protocol.decodeHeader(&header) catch @panic("hello frame");
    if (decoded.kind != .hello or decoded.payload_len != 0) @panic("wrong hello");
    var welcome: [protocol.payload_bytes.welcome]u8 = undefined;
    protocol.encodeWelcome(&welcome, .{ .client_id = 72 });
    var response: [protocol.header_bytes]u8 = undefined;
    protocol.encodeHeader(&response, .{ .kind = .welcome, .payload_len = welcome.len }) catch @panic("welcome header");
    testWriteAll(fd, &response) catch @panic("welcome header write");
    testWriteAll(fd, &welcome) catch @panic("welcome write");
    var byte: [1]u8 = undefined;
    testReadExact(fd, &byte) catch return;
    @panic("peer unexpectedly received data");
}

const CancelReceiveProbe = struct {
    connection: *Connection,
    closed: bool = false,
};

fn testBlockedReceive(probe: *CancelReceiveProbe) void {
    var frame = probe.connection.receive() catch |failure| {
        probe.closed = failure == error.ConnectionClosed;
        return;
    };
    frame.deinit();
}

test "handshake establishes client identity over shared transport" {
    const pair = testSocketPair();
    const thread = try std.Thread.spawn(.{}, testHandshakePeer, .{pair[1]});
    var diagnostic: ConnectDiagnostic = .{};
    var connection = try connectTransport(std.testing.allocator, .{ .fd = pair[0] }, &diagnostic);
    defer connection.deinit();
    thread.join();
    try std.testing.expectEqual(@as(protocol.ClientId, 71), connection.client_id);
    try std.testing.expectEqual(ConnectStage.ready, diagnostic.stage);
}

test "connection cancellation wakes blocked Instance receive while owner retains close" {
    const pair = testSocketPair();
    const peer = try std.Thread.spawn(.{}, testHandshakePeerUntilClosed, .{pair[1]});
    var diagnostic: ConnectDiagnostic = .{};
    var connection = try connectTransport(std.testing.allocator, .{ .fd = pair[0] }, &diagnostic);
    defer connection.deinit();
    var probe = CancelReceiveProbe{ .connection = &connection };
    const reader = try std.Thread.spawn(.{}, testBlockedReceive, .{&probe});
    var cancellation = try connection.cancellation();
    defer cancellation.deinit();
    try cancellation.cancel();
    reader.join();
    peer.join();
    try std.testing.expect(probe.closed);
}

test "receiveInto rejects headers before touching caller storage" {
    const cases = [_]struct { kind: protocol.Kind, size: u32 }{
        .{ .kind = .image_end, .size = 4 },
        .{ .kind = .image_data, .size = 0 },
        .{ .kind = .image_data, .size = 9 },
        .{ .kind = .image_data, .size = protocol.graphics_v2.data_chunk_bytes + 1 },
    };
    for (cases) |case| {
        const pair = testSocketPair();
        defer testClose(pair[1]);
        var connection = Connection{
            .allocator = std.testing.failing_allocator,
            .stream = .{ .fd = pair[0] },
            .client_id = 1,
        };
        defer connection.deinit();
        var header: [protocol.header_bytes]u8 = undefined;
        try protocol.encodeHeader(&header, .{ .kind = case.kind, .payload_len = case.size });
        try testWriteAll(pair[1], &header);
        var guarded: [10]u8 = @splat(0xa5);
        try std.testing.expectError(error.InvalidPayload, connection.receiveInto(.image_data, guarded[1..9]));
        try std.testing.expectEqualSlices(u8, &@as([10]u8, @splat(0xa5)), &guarded);
    }
}

test "receiveInto preserves protocol header errors without destination writes" {
    for (0..5) |case| {
        const pair = testSocketPair();
        defer testClose(pair[1]);
        var connection = Connection{
            .allocator = std.testing.failing_allocator,
            .stream = .{ .fd = pair[0] },
            .client_id = 1,
        };
        defer connection.deinit();
        var header: [protocol.header_bytes]u8 = undefined;
        try protocol.encodeHeader(&header, .{ .kind = .image_data, .payload_len = 1 });
        const expected: Error = switch (case) {
            0 => value: {
                header[0] = 0;
                break :value error.InvalidMagic;
            },
            1 => value: {
                header[4] = 0;
                break :value error.UnsupportedFramingVersion;
            },
            2 => value: {
                header[6] = 1;
                break :value error.InvalidReservedBits;
            },
            3 => value: {
                header[5] = 255;
                break :value error.UnknownKind;
            },
            else => value: {
                header[8] = 1;
                break :value error.PayloadTooLarge;
            },
        };
        try testWriteAll(pair[1], &header);
        var destination = [_]u8{0xa5};
        try std.testing.expectError(expected, connection.receiveInto(.image_data, &destination));
        try std.testing.expectEqual(@as(u8, 0xa5), destination[0]);
    }
}

const ReceiveIntoProbe = struct {
    connection: *Connection,
    result: ?Error = null,
    received: ?usize = null,
    bytes: [8]u8 = @splat(0xa5),
};

fn testBlockedReceiveInto(probe: *ReceiveIntoProbe) void {
    probe.received = probe.connection.receiveInto(.image_data, &probe.bytes) catch |failure| {
        probe.result = failure;
        return;
    };
}

fn testSetNonblocking(fd: posix.fd_t) !void {
    const current = posix.system.fcntl(fd, posix.F.GETFL, @as(usize, 0));
    if (posix.errno(current) != .SUCCESS) return error.TestFcntlFailed;
    const flag = @as(usize, 1) << @bitOffsetOf(posix.O, "NONBLOCK");
    const updated = posix.system.fcntl(fd, posix.F.SETFL, @as(usize, @intCast(current)) | flag);
    if (posix.errno(updated) != .SUCCESS) return error.TestFcntlFailed;
}

test "receiveInto cancellation wakes blocked body and retains owner cleanup" {
    const pair = testSocketPair();
    defer testClose(pair[1]);
    const interrupt = try Interrupt.init(std.testing.allocator);
    defer interrupt.deinit();
    try testSetNonblocking(pair[0]);
    var connection = Connection{
        .allocator = std.testing.failing_allocator,
        .stream = .{ .fd = pair[0], .interrupt = interrupt },
        .client_id = 1,
    };
    defer connection.deinit();
    var header: [protocol.header_bytes]u8 = undefined;
    try protocol.encodeHeader(&header, .{ .kind = .image_data, .payload_len = 8 });
    try testWriteAll(pair[1], &header);
    var probe = ReceiveIntoProbe{ .connection = &connection };
    const worker = try std.Thread.spawn(.{}, testBlockedReceiveInto, .{&probe});
    defer worker.join();
    try std.Io.sleep(std.testing.io, .fromMilliseconds(20), .awake);
    try interrupt.cancel();
    try std.Io.sleep(std.testing.io, .fromMilliseconds(20), .awake);
    try std.testing.expectEqual(error.ConnectionCanceled, probe.result.?);
    try std.testing.expect(probe.received == null);
    try std.testing.expectEqualSlices(u8, &@as([8]u8, @splat(0xa5)), &probe.bytes);
}

fn testFragmentedFramePeer(fd: posix.fd_t) void {
    defer testClose(fd);
    var header: [protocol.header_bytes]u8 = undefined;
    protocol.encodeHeader(&header, .{ .kind = .image_data, .payload_len = 3 }) catch unreachable;
    for (0..2) |_| {
        for (header) |byte| testWriteAll(fd, &.{byte}) catch return;
        for ("abc") |byte| testWriteAll(fd, &.{byte}) catch return;
    }
}

test "receiveInto accepts fragmented frames without allocation or crossing frame boundary" {
    const pair = testSocketPair();
    var connection = Connection{
        .allocator = std.testing.failing_allocator,
        .stream = .{ .fd = pair[0] },
        .client_id = 1,
    };
    defer connection.deinit();
    const worker = std.Thread.spawn(.{}, testFragmentedFramePeer, .{pair[1]}) catch |failure| {
        testClose(pair[1]);
        return failure;
    };
    defer worker.join();
    for (0..2) |_| {
        var guarded: [10]u8 = @splat(0xa5);
        try std.testing.expectEqual(@as(usize, 3), try connection.receiveInto(.image_data, guarded[1..9]));
        try std.testing.expectEqualStrings("abc", guarded[1..4]);
        try std.testing.expectEqual(@as(u8, 0xa5), guarded[0]);
        for (guarded[4..]) |byte| try std.testing.expectEqual(@as(u8, 0xa5), byte);
    }
    var byte: [1]u8 = undefined;
    try std.testing.expectError(error.ConnectionClosed, connection.receiveInto(.image_data, &byte));
}
