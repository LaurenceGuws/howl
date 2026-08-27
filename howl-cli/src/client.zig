//! Owns one bounded client connection to the frozen Howl session byte stream.

const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;
const session = @import("howl_session");
const protocol = session.protocol;
const discovery = session.discovery;

/// Reports endpoint parsing, connection, framing, allocation, or negotiation failure.
pub const Error = std.mem.Allocator.Error || protocol.HeaderError || protocol.PayloadError || error{
    InvalidEndpoint,
    SocketCreateFailed,
    SocketConnectFailed,
    SocketOptionFailed,
    SocketReadFailed,
    SocketWriteFailed,
    ConnectionClosed,
    UnexpectedHandshakeFrame,
    RequiredFeatureMissing,
};

/// Reports a negotiated command capability, encoding, or bounded response failure.
pub const CommandError = Error || protocol.InputEncodeError || error{
    MissingFeature,
    UnexpectedResponse,
};

/// Owns one received frame payload until deinitialized.
pub const Frame = struct {
    allocator: std.mem.Allocator,
    kind: protocol.Kind,
    payload: []u8,

    /// Releases the bounded payload copied from the byte stream.
    pub fn deinit(self: *Frame) void {
        self.allocator.free(self.payload);
        self.* = undefined;
    }
};

/// Owns one negotiated client socket and connection-local session identity.
pub const Connection = struct {
    allocator: std.mem.Allocator,
    fd: posix.fd_t,
    version: u16,
    features: u64,
    client_id: protocol.ClientId,

    /// Connects only to the Howl node-local IPv4 loopback endpoint form.
    pub fn connect(allocator: std.mem.Allocator, endpoint: []const u8) Error!Connection {
        const port = discovery.endpointPort(endpoint) catch return error.InvalidEndpoint;
        const raw = linux.socket(linux.AF.INET, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, 0);
        if (linux.errno(raw) != .SUCCESS) return error.SocketCreateFailed;
        const fd: posix.fd_t = @intCast(raw);
        errdefer closeFd(fd);
        var address = loopbackAddress(port);
        while (true) {
            const result = linux.connect(fd, @ptrCast(&address), @sizeOf(linux.sockaddr.in));
            switch (linux.errno(result)) {
                .SUCCESS => break,
                .INTR => continue,
                else => return error.SocketConnectFailed,
            }
        }
        try setTcpNoDelay(fd);
        return initOwnedFd(allocator, fd);
    }

    /// Closes the negotiated socket and invalidates its connection-local identity.
    pub fn deinit(self: *Connection) void {
        closeFd(self.fd);
        self.* = undefined;
    }

    /// Sends one bounded protocol frame in exact stream order.
    pub fn send(self: *Connection, kind: protocol.Kind, payload: []const u8) Error!void {
        if (payload.len > protocol.maximum_request_payload_bytes) return error.PayloadTooLarge;
        var header: [protocol.header_bytes]u8 = undefined;
        try protocol.encodeHeader(&header, .{ .kind = kind, .payload_len = @intCast(payload.len) });
        try writeAll(self.fd, &header);
        try writeAll(self.fd, payload);
    }

    /// Receives exactly one bounded protocol frame from the stream.
    pub fn receive(self: *Connection) Error!Frame {
        var header_bytes: [protocol.header_bytes]u8 = undefined;
        try readExact(self.fd, &header_bytes);
        const header = try protocol.decodeHeader(&header_bytes);
        const payload = try self.allocator.alloc(u8, header.payload_len);
        errdefer self.allocator.free(payload);
        try readExact(self.fd, payload);
        return .{ .allocator = self.allocator, .kind = header.kind, .payload = payload };
    }

    /// Sends one semantic paste event and returns the endpoint's exact bounded result.
    pub fn paste(self: *Connection, bytes: []const u8) CommandError!protocol.ResultCode {
        if (bytes.len == 0 or bytes.len >= protocol.maximum_request_payload_bytes)
            return error.InvalidPayload;
        const payload = try self.allocator.alloc(u8, bytes.len + 1);
        defer self.allocator.free(payload);
        payload[0] = @backingInt(protocol.InputKind.paste);
        @memcpy(payload[1..], bytes);
        try self.send(.input, payload);
        return self.receiveResult(.input);
    }

    /// Sends one exact physical key transition without synthesizing terminal bytes.
    pub fn key(self: *Connection, value: protocol.KeyInput) CommandError!protocol.ResultCode {
        try self.requireFeature(.typed_input);
        var payload: [
            1 + protocol.typed_input.key_header_bytes +
                protocol.typed_input.maximum_legacy_key_bytes +
                protocol.typed_input.maximum_key_text_bytes
        ]u8 = undefined;
        payload[0] = @backingInt(protocol.InputKind.key);
        const encoded = try protocol.encodeKeyInput(payload[1..], value);
        try self.send(.input, payload[0 .. encoded.len + 1]);
        return self.receiveResult(.input);
    }

    /// Assigns this connection as canonical resize leader.
    pub fn claimResize(self: *Connection) CommandError!protocol.ResultCode {
        try self.requireFeature(.resize_leader);
        var payload: [protocol.payload_bytes.assign_leader]u8 = undefined;
        protocol.encodeAssignLeader(&payload, .{ .client_id = self.client_id });
        try self.send(.assign_leader, &payload);
        return self.receiveResult(.assign_leader);
    }

    /// Sends one explicit canonical geometry mutation after leadership is claimed.
    pub fn resize(self: *Connection, rows: u16, columns: u16) CommandError!protocol.ResultCode {
        try self.requireFeature(.resize_leader);
        var payload: [protocol.payload_bytes.resize]u8 = undefined;
        protocol.encodeResize(&payload, .{ .rows = rows, .columns = columns });
        try self.send(.resize, &payload);
        return self.receiveResult(.resize);
    }

    /// Sends one fixed process-group signal request.
    pub fn signal(self: *Connection, value: protocol.Signal) CommandError!protocol.ResultCode {
        var payload: [protocol.payload_bytes.signal]u8 = undefined;
        protocol.encodeSignal(&payload, value);
        try self.send(.signal, &payload);
        return self.receiveResult(.signal);
    }

    fn requireFeature(self: *const Connection, feature_value: protocol.Feature) error{MissingFeature}!void {
        if (self.features & protocol.feature(feature_value) == 0) return error.MissingFeature;
    }

    fn receiveResult(self: *Connection, request_kind: protocol.Kind) CommandError!protocol.ResultCode {
        var frame = try self.receive();
        defer frame.deinit();
        if (frame.kind != .result) return error.UnexpectedResponse;
        const result = try protocol.decodeResult(frame.payload);
        if (result.request_kind != request_kind) return error.UnexpectedResponse;
        return result.code;
    }
};

fn initOwnedFd(allocator: std.mem.Allocator, fd: posix.fd_t) Error!Connection {
    errdefer closeFd(fd);
    var hello_payload: [protocol.payload_bytes.hello]u8 = undefined;
    protocol.encodeHello(&hello_payload, .{});
    var connection = Connection{
        .allocator = allocator,
        .fd = fd,
        .version = 0,
        .features = 0,
        .client_id = protocol.no_client,
    };
    try connection.send(.hello, &hello_payload);
    var frame = try connection.receive();
    defer frame.deinit();
    if (frame.kind != .welcome) return error.UnexpectedHandshakeFrame;
    const welcome = try protocol.decodeWelcome(frame.payload);
    if (welcome.features & protocol.feature(.grid_snapshot) == 0)
        return error.RequiredFeatureMissing;
    connection.version = welcome.version;
    connection.features = welcome.features;
    connection.client_id = welcome.client_id;
    return connection;
}

fn loopbackAddress(port: u16) linux.sockaddr.in {
    const bytes = [4]u8{ 127, 0, 0, 1 };
    const address: *align(1) const u32 = @ptrCast(&bytes);
    return .{ .port = std.mem.nativeToBig(u16, port), .addr = address.* };
}

fn setTcpNoDelay(fd: posix.fd_t) error{SocketOptionFailed}!void {
    const enabled: c_int = 1;
    const result = linux.setsockopt(
        fd,
        linux.IPPROTO.TCP,
        linux.TCP.NODELAY,
        std.mem.asBytes(&enabled).ptr,
        @sizeOf(c_int),
    );
    if (linux.errno(result) != .SUCCESS) return error.SocketOptionFailed;
}

fn writeAll(fd: posix.fd_t, bytes: []const u8) error{ SocketWriteFailed, ConnectionClosed }!void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        const result = linux.write(fd, bytes[offset..].ptr, bytes.len - offset);
        switch (linux.errno(result)) {
            .SUCCESS => {
                if (result == 0) return error.ConnectionClosed;
                if (result > bytes.len - offset) return error.SocketWriteFailed;
                offset += result;
            },
            .INTR => continue,
            .PIPE, .CONNRESET, .NOTCONN => return error.ConnectionClosed,
            else => return error.SocketWriteFailed,
        }
    }
}

fn readExact(fd: posix.fd_t, output: []u8) error{ SocketReadFailed, ConnectionClosed }!void {
    var offset: usize = 0;
    while (offset < output.len) {
        const result = linux.read(fd, output[offset..].ptr, output.len - offset);
        switch (linux.errno(result)) {
            .SUCCESS => {
                if (result == 0) return error.ConnectionClosed;
                if (result > output.len - offset) return error.SocketReadFailed;
                offset += result;
            },
            .INTR => continue,
            .CONNRESET, .NOTCONN => return error.ConnectionClosed,
            else => return error.SocketReadFailed,
        }
    }
}

fn closeFd(fd: posix.fd_t) void {
    const result = linux.close(fd);
    const errno = linux.errno(result);
    std.debug.assert(errno == .SUCCESS or errno == .INTR);
}

const TestHandshake = enum { welcome_fragmented, wrong_kind, malformed_welcome, missing_feature, close_early };

fn testPeer(mode: TestHandshake, fd: posix.fd_t) void {
    defer closeFd(fd);
    var header_bytes: [protocol.header_bytes]u8 = undefined;
    readExact(fd, &header_bytes) catch @panic("test peer could not read hello header");
    const header = protocol.decodeHeader(&header_bytes) catch @panic("test peer got malformed hello header");
    if (header.kind != .hello or header.payload_len != protocol.payload_bytes.hello)
        @panic("test peer got wrong hello frame");
    var hello: [protocol.payload_bytes.hello]u8 = undefined;
    readExact(fd, &hello) catch @panic("test peer could not read hello payload");
    const decoded = protocol.decodeHello(&hello) catch @panic("test peer got malformed hello payload");
    if (decoded.features & protocol.feature(.grid_snapshot) == 0)
        @panic("client did not request required grid feature");
    if (mode == .close_early) return;

    const kind: protocol.Kind = if (mode == .wrong_kind) .result else .welcome;
    if (mode == .malformed_welcome) {
        const malformed = [1]u8{0};
        var response_header: [protocol.header_bytes]u8 = undefined;
        protocol.encodeHeader(&response_header, .{ .kind = kind, .payload_len = malformed.len }) catch
            @panic("test peer could not encode malformed response header");
        testWriteFragmented(fd, &response_header);
        testWriteFragmented(fd, &malformed);
        return;
    }
    var welcome: [protocol.payload_bytes.welcome]u8 = undefined;
    protocol.encodeWelcome(&welcome, .{
        .version = protocol.protocol_max_version,
        .features = if (mode == .missing_feature) 0 else protocol.supported_features,
        .client_id = 77,
    });
    var response_header: [protocol.header_bytes]u8 = undefined;
    protocol.encodeHeader(&response_header, .{ .kind = kind, .payload_len = welcome.len }) catch
        @panic("test peer could not encode response header");
    testWriteFragmented(fd, &response_header);
    testWriteFragmented(fd, &welcome);
}

fn testWriteFragmented(fd: posix.fd_t, bytes: []const u8) void {
    for (bytes) |byte| {
        const one = [1]u8{byte};
        writeAll(fd, &one) catch @panic("test peer fragmented write failed");
    }
}

fn testSocketPair() [2]posix.fd_t {
    var pair: [2]posix.fd_t = undefined;
    const result = linux.socketpair(linux.AF.UNIX, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, 0, &pair);
    if (linux.errno(result) != .SUCCESS) @panic("test socketpair failed");
    return pair;
}

test "loopback endpoint parser rejects ambiguous or remote forms" {
    try std.testing.expectEqual(@as(u16, 7777), try discovery.endpointPort("tcp://127.0.0.1:7777"));
    try std.testing.expectError(error.InvalidEndpoint, discovery.endpointPort("tcp://0.0.0.0:7777"));
    try std.testing.expectError(error.InvalidEndpoint, discovery.endpointPort("tcp://127.0.0.1:0"));
    try std.testing.expectError(error.InvalidEndpoint, discovery.endpointPort("tcp://127.0.0.1:7777/path"));
    try std.testing.expectError(error.InvalidEndpoint, discovery.endpointPort("/tmp/howl.sock"));
}

test "handshake survives fragmented stream reads and owns negotiated identity" {
    const pair = testSocketPair();
    const thread = try std.Thread.spawn(.{}, testPeer, .{ .welcome_fragmented, pair[1] });
    var connection = try initOwnedFd(std.testing.allocator, pair[0]);
    defer connection.deinit();
    thread.join();
    try std.testing.expectEqual(protocol.protocol_max_version, connection.version);
    try std.testing.expectEqual(protocol.supported_features, connection.features);
    try std.testing.expectEqual(@as(protocol.ClientId, 77), connection.client_id);
}

test "unexpected handshake kind closes the owned descriptor" {
    const pair = testSocketPair();
    const thread = try std.Thread.spawn(.{}, testPeer, .{ .wrong_kind, pair[1] });
    try std.testing.expectError(
        error.UnexpectedHandshakeFrame,
        initOwnedFd(std.testing.allocator, pair[0]),
    );
    thread.join();
}

test "malformed welcome payload is rejected without widening protocol errors" {
    const pair = testSocketPair();
    const thread = try std.Thread.spawn(.{}, testPeer, .{ .malformed_welcome, pair[1] });
    try std.testing.expectError(
        error.InvalidPayload,
        initOwnedFd(std.testing.allocator, pair[0]),
    );
    thread.join();
}

test "welcome without required grid feature is rejected explicitly" {
    const pair = testSocketPair();
    const thread = try std.Thread.spawn(.{}, testPeer, .{ .missing_feature, pair[1] });
    try std.testing.expectError(
        error.RequiredFeatureMissing,
        initOwnedFd(std.testing.allocator, pair[0]),
    );
    thread.join();
}

test "peer disconnect during handshake is an exact closed connection" {
    const pair = testSocketPair();
    const thread = try std.Thread.spawn(.{}, testPeer, .{ .close_early, pair[1] });
    try std.testing.expectError(
        error.ConnectionClosed,
        initOwnedFd(std.testing.allocator, pair[0]),
    );
    thread.join();
}
