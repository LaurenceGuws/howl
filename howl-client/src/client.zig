//! Owns one explicit connection to the frozen Howl session byte stream.
//!
//! Endpoint selection is supplied by the caller. There is deliberately no node,
//! session discovery, authentication, or transport policy here.

const std = @import("std");
const posix = std.posix;
const system = posix.system;
const protocol = @import("howl_session").protocol;

const tcp_prefix = "tcp://127.0.0.1:";
const unix_prefix = "unix:";

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
    SocketPathTooLong,
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
    fd: posix.fd_t,
    version: u16,
    features: u64,
    client_id: protocol.ClientId,

    pub fn connect(allocator: std.mem.Allocator, endpoint: []const u8) Error!Connection {
        const fd = if (std.mem.startsWith(u8, endpoint, tcp_prefix))
            try connectTcp(try tcpPort(endpoint))
        else if (std.mem.startsWith(u8, endpoint, unix_prefix))
            try connectUnix(endpoint[unix_prefix.len..])
        else
            return error.InvalidEndpoint;
        return initOwnedFd(allocator, fd);
    }

    pub fn deinit(self: *Connection) void {
        closeFd(self.fd);
        self.* = undefined;
    }

    pub fn send(self: *Connection, kind: protocol.Kind, payload: []const u8) Error!void {
        if (payload.len > protocol.maximum_request_payload_bytes) return error.PayloadTooLarge;
        var header: [protocol.header_bytes]u8 = undefined;
        try protocol.encodeHeader(&header, .{ .kind = kind, .payload_len = @intCast(payload.len) });
        try writeAll(self.fd, &header);
        try writeAll(self.fd, payload);
    }

    pub fn receive(self: *Connection) Error!Frame {
        var header_bytes: [protocol.header_bytes]u8 = undefined;
        try readExact(self.fd, &header_bytes);
        const header = try protocol.decodeHeader(&header_bytes);
        const payload = try self.allocator.alloc(u8, header.payload_len);
        errdefer self.allocator.free(payload);
        try readExact(self.fd, payload);
        return .{ .allocator = self.allocator, .kind = header.kind, .payload = payload };
    }
};

fn initOwnedFd(allocator: std.mem.Allocator, fd: posix.fd_t) Error!Connection {
    errdefer closeFd(fd);
    var connection = Connection{
        .allocator = allocator,
        .fd = fd,
        .version = 0,
        .features = 0,
        .client_id = protocol.no_client,
    };
    var hello: [protocol.payload_bytes.hello]u8 = undefined;
    protocol.encodeHello(&hello, .{});
    try connection.send(.hello, &hello);
    var frame = try connection.receive();
    defer frame.deinit();
    if (frame.kind != .welcome) return error.UnexpectedHandshakeFrame;
    const welcome = try protocol.decodeWelcome(frame.payload);
    if (welcome.features & protocol.feature(.text_snapshot) == 0)
        return error.RequiredFeatureMissing;
    connection.version = welcome.version;
    connection.features = welcome.features;
    connection.client_id = welcome.client_id;
    return connection;
}

fn tcpPort(endpoint: []const u8) error{InvalidEndpoint}!u16 {
    const text = endpoint[tcp_prefix.len..];
    if (text.len == 0 or std.mem.indexOfScalar(u8, text, '/') != null) return error.InvalidEndpoint;
    const port = std.fmt.parseInt(u16, text, 10) catch return error.InvalidEndpoint;
    if (port == 0) return error.InvalidEndpoint;
    return port;
}

fn connectTcp(port: u16) error{ SocketCreateFailed, SocketConnectFailed, SocketOptionFailed }!posix.fd_t {
    const raw = system.socket(posix.AF.INET, posix.SOCK.STREAM, 0);
    if (posix.errno(raw) != .SUCCESS) return error.SocketCreateFailed;
    const fd: posix.fd_t = @intCast(raw);
    errdefer closeFd(fd);
    var address = loopbackAddress(port);
    while (true) {
        const result = system.connect(fd, @ptrCast(&address), @sizeOf(posix.sockaddr.in));
        switch (posix.errno(result)) {
            .SUCCESS => break,
            .INTR => continue,
            else => return error.SocketConnectFailed,
        }
    }
    try setTcpNoDelay(fd);
    return fd;
}

fn connectUnix(path: []const u8) error{ SocketCreateFailed, SocketConnectFailed, SocketPathTooLong }!posix.fd_t {
    var address: posix.sockaddr.un = undefined;
    if (path.len == 0 or path.len >= address.path.len) return error.SocketPathTooLong;
    if (@hasField(posix.sockaddr.un, "len")) address.len = @sizeOf(posix.sockaddr.un);
    address.family = posix.AF.UNIX;
    @memset(&address.path, 0);
    @memcpy(address.path[0..path.len], path);
    const length: posix.socklen_t = @intCast(@sizeOf(posix.sockaddr.un));
    const raw = system.socket(posix.AF.UNIX, posix.SOCK.STREAM, 0);
    if (posix.errno(raw) != .SUCCESS) return error.SocketCreateFailed;
    const fd: posix.fd_t = @intCast(raw);
    errdefer closeFd(fd);
    while (true) {
        const result = system.connect(fd, @ptrCast(&address), length);
        switch (posix.errno(result)) {
            .SUCCESS => return fd,
            .INTR => continue,
            else => return error.SocketConnectFailed,
        }
    }
}

fn loopbackAddress(port: u16) posix.sockaddr.in {
    const bytes = [4]u8{ 127, 0, 0, 1 };
    const address: *align(1) const u32 = @ptrCast(&bytes);
    var result: posix.sockaddr.in = undefined;
    if (@hasField(posix.sockaddr.in, "len")) result.len = @sizeOf(posix.sockaddr.in);
    result.family = posix.AF.INET;
    result.port = std.mem.nativeToBig(u16, port);
    result.addr = address.*;
    if (@hasField(posix.sockaddr.in, "zero")) result.zero = @splat(0);
    return result;
}

fn setTcpNoDelay(fd: posix.fd_t) error{SocketOptionFailed}!void {
    const enabled: c_int = 1;
    const result = system.setsockopt(
        fd,
        posix.IPPROTO.TCP,
        posix.TCP.NODELAY,
        std.mem.asBytes(&enabled).ptr,
        @sizeOf(c_int),
    );
    if (posix.errno(result) != .SUCCESS) return error.SocketOptionFailed;
}

fn writeAll(fd: posix.fd_t, bytes: []const u8) error{ SocketWriteFailed, ConnectionClosed }!void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        const result = system.write(fd, bytes[offset..].ptr, bytes.len - offset);
        switch (posix.errno(result)) {
            .SUCCESS => {
                if (result == 0) return error.ConnectionClosed;
                const count: usize = @intCast(result);
                if (count > bytes.len - offset) return error.SocketWriteFailed;
                offset += count;
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
        const result = system.read(fd, output[offset..].ptr, output.len - offset);
        switch (posix.errno(result)) {
            .SUCCESS => {
                if (result == 0) return error.ConnectionClosed;
                const count: usize = @intCast(result);
                if (count > output.len - offset) return error.SocketReadFailed;
                offset += count;
            },
            .INTR => continue,
            .CONNRESET, .NOTCONN => return error.ConnectionClosed,
            else => return error.SocketReadFailed,
        }
    }
}

fn closeFd(fd: posix.fd_t) void {
    const result = system.close(fd);
    const errno = posix.errno(result);
    std.debug.assert(errno == .SUCCESS or errno == .INTR);
}

fn testSocketPair() [2]posix.fd_t {
    var pair: [2]posix.fd_t = undefined;
    const result = system.socketpair(posix.AF.UNIX, posix.SOCK.STREAM, 0, &pair);
    if (posix.errno(result) != .SUCCESS) @panic("test socketpair failed");
    return pair;
}

fn testHandshakePeer(fd: posix.fd_t) void {
    defer closeFd(fd);
    var header: [protocol.header_bytes]u8 = undefined;
    readExact(fd, &header) catch @panic("hello header");
    const decoded_header = protocol.decodeHeader(&header) catch @panic("hello frame");
    if (decoded_header.kind != .hello) @panic("wrong hello kind");
    var payload: [protocol.payload_bytes.hello]u8 = undefined;
    readExact(fd, &payload) catch @panic("hello payload");
    const hello = protocol.decodeHello(&payload) catch @panic("invalid hello");
    if (hello.features & protocol.feature(.text_snapshot) == 0) @panic("rich observation feature missing");
    var welcome: [protocol.payload_bytes.welcome]u8 = undefined;
    protocol.encodeWelcome(&welcome, .{
        .version = protocol.protocol_max_version,
        .features = protocol.supported_features,
        .client_id = 71,
    });
    var response: [protocol.header_bytes]u8 = undefined;
    protocol.encodeHeader(&response, .{ .kind = .welcome, .payload_len = welcome.len }) catch @panic("welcome header");
    writeAll(fd, &response) catch @panic("welcome header write");
    writeAll(fd, &welcome) catch @panic("welcome write");
}

test "handshake requests the rich frozen wire without transport policy" {
    const pair = testSocketPair();
    const thread = try std.Thread.spawn(.{}, testHandshakePeer, .{pair[1]});
    var connection = try initOwnedFd(std.testing.allocator, pair[0]);
    defer connection.deinit();
    thread.join();
    try std.testing.expectEqual(protocol.protocol_max_version, connection.version);
    try std.testing.expect(connection.features & protocol.feature(.text_snapshot) != 0);
    try std.testing.expectEqual(@as(protocol.ClientId, 71), connection.client_id);
}

test "endpoint parser refuses remote or ambiguous TCP" {
    try std.testing.expectEqual(@as(u16, 43127), try tcpPort("tcp://127.0.0.1:43127"));
    try std.testing.expectError(error.InvalidEndpoint, tcpPort("tcp://127.0.0.1:0"));
    try std.testing.expectError(error.InvalidEndpoint, tcpPort("tcp://127.0.0.1:43127/x"));
}
