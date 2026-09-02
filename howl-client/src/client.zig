//! Owns one explicit connection to the frozen Howl session byte stream.
//!
//! Endpoint selection is supplied by the caller. There is deliberately no node,
//! session discovery, authentication, or transport policy here.

const std = @import("std");
const posix = std.posix;
const system = posix.system;
const protocol = @import("howl_session").protocol;

const tcp_prefix = "tcp://";
const unix_prefix = "unix:";

pub const Error = std.mem.Allocator.Error || protocol.HeaderError || protocol.PayloadError || error{
    InvalidEndpoint,
    SocketCreateFailed,
    SocketConnectFailed,
    SocketConnectTimedOut,
    SocketOptionFailed,
    SocketReadFailed,
    SocketWriteFailed,
    ConnectionClosed,
    UnexpectedHandshakeFrame,
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
    client_id: protocol.ClientId,

    pub fn connect(allocator: std.mem.Allocator, endpoint: []const u8) Error!Connection {
        const fd = if (std.mem.startsWith(u8, endpoint, tcp_prefix))
            try connectTcp(try tcpEndpoint(endpoint))
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
    try setCloseOnExec(fd);
    var connection = Connection{
        .allocator = allocator,
        .fd = fd,
        .client_id = protocol.no_client,
    };
    try connection.send(.hello, &.{});
    var frame = try connection.receive();
    defer frame.deinit();
    if (frame.kind != .welcome) return error.UnexpectedHandshakeFrame;
    const welcome = try protocol.decodeWelcome(frame.payload);
    connection.client_id = welcome.client_id;
    return connection;
}

const TcpEndpoint = struct {
    address: [4]u8,
    port: u16,
};

fn tcpEndpoint(endpoint: []const u8) error{InvalidEndpoint}!TcpEndpoint {
    const text = endpoint[tcp_prefix.len..];
    if (text.len == 0 or
        std.mem.indexOfAny(u8, text, "/?#") != null)
        return error.InvalidEndpoint;
    const colon = std.mem.lastIndexOfScalar(u8, text, ':') orelse return error.InvalidEndpoint;
    if (colon == 0 or colon + 1 >= text.len or std.mem.indexOfScalar(u8, text[0..colon], ':') != null)
        return error.InvalidEndpoint;

    const host = text[0..colon];
    const port = std.fmt.parseInt(u16, text[colon + 1 ..], 10) catch return error.InvalidEndpoint;
    if (port == 0) return error.InvalidEndpoint;

    var address: [4]u8 = undefined;
    var parts = std.mem.splitScalar(u8, host, '.');
    var index: usize = 0;
    while (parts.next()) |part| : (index += 1) {
        if (index >= address.len or part.len == 0) return error.InvalidEndpoint;
        address[index] = std.fmt.parseInt(u8, part, 10) catch return error.InvalidEndpoint;
    }
    if (index != address.len or std.mem.eql(u8, &address, &.{ 0, 0, 0, 0 }))
        return error.InvalidEndpoint;
    return .{ .address = address, .port = port };
}

const tcp_connect_timeout_ms = 15_000;

fn connectTcp(endpoint: TcpEndpoint) error{ SocketCreateFailed, SocketConnectFailed, SocketConnectTimedOut, SocketOptionFailed }!posix.fd_t {
    const raw = system.socket(posix.AF.INET, posix.SOCK.STREAM, 0);
    if (posix.errno(raw) != .SUCCESS) return error.SocketCreateFailed;
    const fd: posix.fd_t = @intCast(raw);
    errdefer closeFd(fd);

    const original_flags = try fileStatusFlags(fd);
    try setFileStatusFlags(fd, original_flags | nonblockingFlag());

    var address = ipv4Address(endpoint.address, endpoint.port);
    var connected = false;
    while (true) {
        const result = system.connect(fd, @ptrCast(&address), @sizeOf(posix.sockaddr.in));
        switch (posix.errno(result)) {
            .SUCCESS, .ISCONN => {
                connected = true;
                break;
            },
            .INTR => continue,
            .INPROGRESS, .ALREADY, .AGAIN => break,
            else => return error.SocketConnectFailed,
        }
    }

    if (!connected) {
        var fds = [_]posix.pollfd{.{
            .fd = fd,
            .events = posix.POLL.OUT,
            .revents = 0,
        }};
        const ready = posix.poll(&fds, tcp_connect_timeout_ms) catch
            return error.SocketConnectFailed;
        if (ready == 0) return error.SocketConnectTimedOut;
        if (fds[0].revents & (posix.POLL.ERR | posix.POLL.HUP | posix.POLL.NVAL | posix.POLL.OUT) == 0)
            return error.SocketConnectFailed;
        try verifySocketConnected(fd);
    }

    try setFileStatusFlags(fd, original_flags);
    try setTcpNoDelay(fd);
    return fd;
}

fn nonblockingFlag() usize {
    return @as(usize, 1) << @bitOffsetOf(posix.O, "NONBLOCK");
}

fn fileStatusFlags(fd: posix.fd_t) error{SocketOptionFailed}!usize {
    while (true) {
        const result = system.fcntl(fd, posix.F.GETFL, @as(usize, 0));
        switch (posix.errno(result)) {
            .SUCCESS => return @intCast(result),
            .INTR => continue,
            else => return error.SocketOptionFailed,
        }
    }
}

fn setFileStatusFlags(fd: posix.fd_t, flags: usize) error{SocketOptionFailed}!void {
    while (true) {
        const result = system.fcntl(fd, posix.F.SETFL, flags);
        switch (posix.errno(result)) {
            .SUCCESS => return,
            .INTR => continue,
            else => return error.SocketOptionFailed,
        }
    }
}

fn verifySocketConnected(fd: posix.fd_t) error{ SocketConnectFailed, SocketOptionFailed }!void {
    var socket_error: c_int = 0;
    var length: posix.socklen_t = @sizeOf(c_int);
    const result = system.getsockopt(
        fd,
        posix.SOL.SOCKET,
        posix.SO.ERROR,
        @ptrCast(&socket_error),
        &length,
    );
    if (posix.errno(result) != .SUCCESS or length != @sizeOf(c_int))
        return error.SocketOptionFailed;
    if (socket_error != 0) return error.SocketConnectFailed;
}

fn connectUnix(path: []const u8) error{ SocketCreateFailed, SocketConnectFailed, SocketPathTooLong }!posix.fd_t {
    var address: posix.sockaddr.un = undefined;
    if (path.len == 0 or path.len >= address.path.len) return error.SocketPathTooLong;
    const length: posix.socklen_t = @intCast(@offsetOf(posix.sockaddr.un, "path") + path.len + 1);
    if (@hasField(posix.sockaddr.un, "len")) address.len = @intCast(length);
    address.family = posix.AF.UNIX;
    @memset(&address.path, 0);
    @memcpy(address.path[0..path.len], path);
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

fn ipv4Address(bytes: [4]u8, port: u16) posix.sockaddr.in {
    const address: *align(1) const u32 = @ptrCast(&bytes);
    var result: posix.sockaddr.in = undefined;
    if (@hasField(posix.sockaddr.in, "len")) result.len = @sizeOf(posix.sockaddr.in);
    result.family = posix.AF.INET;
    result.port = std.mem.nativeToBig(u16, port);
    result.addr = address.*;
    if (@hasField(posix.sockaddr.in, "zero")) result.zero = @splat(0);
    return result;
}

fn setCloseOnExec(fd: posix.fd_t) error{SocketOptionFailed}!void {
    const result = system.fcntl(fd, posix.F.SETFD, @as(usize, posix.FD_CLOEXEC));
    if (posix.errno(result) != .SUCCESS) return error.SocketOptionFailed;
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
    if (decoded_header.payload_len != protocol.payload_bytes.hello) @panic("hello payload");
    var welcome: [protocol.payload_bytes.welcome]u8 = undefined;
    protocol.encodeWelcome(&welcome, .{ .client_id = 71 });
    var response: [protocol.header_bytes]u8 = undefined;
    protocol.encodeHeader(&response, .{ .kind = .welcome, .payload_len = welcome.len }) catch @panic("welcome header");
    writeAll(fd, &response) catch @panic("welcome header write");
    writeAll(fd, &welcome) catch @panic("welcome write");
}

test "handshake establishes client identity without transport policy" {
    const pair = testSocketPair();
    const thread = try std.Thread.spawn(.{}, testHandshakePeer, .{pair[1]});
    var connection = try initOwnedFd(std.testing.allocator, pair[0]);
    defer connection.deinit();
    thread.join();
    const fd_flags = system.fcntl(connection.fd, posix.F.GETFD, @as(usize, 0));
    try std.testing.expectEqual(posix.E.SUCCESS, posix.errno(fd_flags));
    try std.testing.expect(fd_flags & posix.FD_CLOEXEC != 0);
    try std.testing.expectEqual(@as(protocol.ClientId, 71), connection.client_id);
}

test "endpoint parser accepts explicit numeric IPv4 and refuses ambiguous TCP" {
    const loopback = try tcpEndpoint("tcp://127.0.0.1:43127");
    try std.testing.expectEqualSlices(u8, &.{ 127, 0, 0, 1 }, &loopback.address);
    try std.testing.expectEqual(@as(u16, 43127), loopback.port);
    const remote = try tcpEndpoint("tcp://100.96.0.2:43128");
    try std.testing.expectEqualSlices(u8, &.{ 100, 96, 0, 2 }, &remote.address);
    try std.testing.expectEqual(@as(u16, 43128), remote.port);
    for ([_][]const u8{
        "tcp://localhost:43127",
        "tcp://0.0.0.0:43127",
        "tcp://127.0.0.1:0",
        "tcp://127.0.0.1:43127/x",
        "tcp://127.0.0.1",
        "tcp://127.0.0.999:43127",
    }) |bad| {
        try std.testing.expectError(error.InvalidEndpoint, tcpEndpoint(bad));
    }
}
