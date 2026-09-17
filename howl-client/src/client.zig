//! Owns one explicit connection to the frozen Howl session byte stream.
//!
//! Endpoint selection is supplied by the caller. There is deliberately no node,
//! session discovery or terminal policy here. connectNative explicitly opts into
//! an installed-OpenSSH carrier; connect stays socket-only.

const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const system = posix.system;
const protocol = @import("howl_session").protocol;
const ssh = @import("ssh.zig");

const tcp_prefix = "tcp://";
const unix_prefix = "unix:";

pub const Error = ssh.Error || protocol.HeaderError || protocol.PayloadError || error{
    RouteUnavailable,
    InvalidEndpoint,
    SocketCreateFailed,
    SocketDuplicateFailed,
    SocketConnectFailed,
    SocketConnectTimedOut,
    SocketOptionFailed,
    SocketReadFailed,
    SocketShutdownFailed,
    SocketWriteFailed,
    ConnectionClosed,
    UnexpectedHandshakeFrame,
    SocketPathTooLong,
};

pub const ConnectStage = enum(u8) {
    start,
    endpoint,
    socket_create,
    file_status_read,
    nonblocking_enable,
    socket_connect,
    socket_poll,
    socket_verify,
    blocking_restore,
    tcp_nodelay,
    close_on_exec,
    hello_write,
    welcome_read,
    welcome_kind,
    welcome_payload,
    ready,
    ssh_launch,
};

pub const ConnectDiagnostic = struct {
    stage: ConnectStage = .start,
    os_error: i32 = 0,
    poll_interrupts: u16 = 0,
    route_message: [ssh.diagnostic_bytes]u8 = undefined,
    route_message_len: usize = 0,
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

/// Independently owned duplicate of one connection socket used only to wake a
/// blocking receive from another thread. It never sends protocol bytes.
pub const Cancellation = struct {
    fd: posix.fd_t,

    pub fn cancel(self: *const Cancellation) error{SocketShutdownFailed}!void {
        return shutdownFd(self.fd);
    }

    pub fn deinit(self: *Cancellation) void {
        closeFd(self.fd);
        self.* = undefined;
    }
};

pub const Connection = struct {
    allocator: std.mem.Allocator,
    fd: posix.fd_t,
    client_id: protocol.ClientId,
    ssh_process: ?*ssh.Process = null,

    pub fn connect(allocator: std.mem.Allocator, endpoint: []const u8) Error!Connection {
        var diagnostic: ConnectDiagnostic = .{};
        return connectDiagnosed(allocator, endpoint, &diagnostic);
    }

    pub fn connectDiagnosed(
        allocator: std.mem.Allocator,
        endpoint: []const u8,
        diagnostic: *ConnectDiagnostic,
    ) Error!Connection {
        diagnostic.* = .{};
        diagnostic.stage = .endpoint;
        const fd = if (std.mem.startsWith(u8, endpoint, tcp_prefix))
            try connectTcp(try tcpEndpoint(endpoint), diagnostic)
        else if (std.mem.startsWith(u8, endpoint, unix_prefix))
            try connectUnix(endpoint[unix_prefix.len..])
        else
            return error.InvalidEndpoint;
        return initOwnedFd(allocator, fd, diagnostic, null);
    }

    /// Opts a native host into its installed OpenSSH carrier. Socket-only and
    /// browser/mobile byte-entry consumers do not gain subprocess requirements.
    /// `io` is embedder-owned and must outlive this connection. The carrier
    /// never installs or restores process-global signal handlers per route.
    /// Opening and protocol I/O block: call from the embedder's I/O worker.
    pub fn connectNative(
        allocator: std.mem.Allocator,
        io: std.Io,
        endpoint: []const u8,
        diagnostic: *ConnectDiagnostic,
    ) Error!Connection {
        if (!std.mem.startsWith(u8, endpoint, "ssh://"))
            return connectDiagnosed(allocator, endpoint, diagnostic);
        diagnostic.* = .{ .stage = .endpoint };
        if (comptime !ssh.supported) return error.RouteUnavailable;
        const route = try ssh.parse(endpoint);
        diagnostic.stage = .ssh_launch;
        const opened = try ssh.Process.open(allocator, io, route);
        errdefer diagnostic.route_message_len = opened.process.deinit(&diagnostic.route_message);
        const deadline = (monotonicMilliseconds() catch {
            closeFd(opened.fd);
            return error.SocketConnectFailed;
        }) + tcp_connect_timeout_ms;
        var connection = try initOwnedFd(allocator, opened.fd, diagnostic, deadline);
        connection.ssh_process = opened.process;
        return connection;
    }

    pub fn deinit(self: *Connection) void {
        closeFd(self.fd);
        if (comptime ssh.supported) {
            if (self.ssh_process) |process| _ = process.deinit(&.{});
        }
        self.* = undefined;
    }

    /// Borrows the ordered stream descriptor for readiness polling only.
    /// Callers must not read, write, close, or change flags through this handle.
    pub fn readinessFd(self: *const Connection) posix.fd_t {
        return self.fd;
    }

    /// Creates an independently owned duplicate which may wake a currently
    /// blocked receive from another thread without releasing this connection.
    pub fn cancellation(self: *const Connection) error{ SocketDuplicateFailed, SocketOptionFailed }!Cancellation {
        const raw = system.dup(self.fd);
        if (posix.errno(raw) != .SUCCESS) return error.SocketDuplicateFailed;
        const fd: posix.fd_t = @intCast(raw);
        errdefer closeFd(fd);
        try setCloseOnExec(fd);
        return .{ .fd = fd };
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

fn initOwnedFd(
    allocator: std.mem.Allocator,
    fd: posix.fd_t,
    diagnostic: *ConnectDiagnostic,
    deadline_ms: ?i64,
) Error!Connection {
    errdefer closeFd(fd);
    diagnostic.stage = .close_on_exec;
    try setCloseOnExec(fd);
    var connection = Connection{
        .allocator = allocator,
        .fd = fd,
        .client_id = protocol.no_client,
    };
    diagnostic.stage = .hello_write;
    try connection.send(.hello, &.{});
    diagnostic.stage = .welcome_read;
    var header_bytes: [protocol.header_bytes]u8 = undefined;
    try readHandshake(fd, &header_bytes, deadline_ms);
    const header = try protocol.decodeHeader(&header_bytes);
    if (header.kind != .welcome) {
        diagnostic.stage = .welcome_kind;
        return error.UnexpectedHandshakeFrame;
    }
    diagnostic.stage = .welcome_payload;
    if (header.payload_len != protocol.payload_bytes.welcome) return error.InvalidPayload;
    var payload: [protocol.payload_bytes.welcome]u8 = undefined;
    try readHandshake(fd, &payload, deadline_ms);
    const welcome = try protocol.decodeWelcome(&payload);
    connection.client_id = welcome.client_id;
    diagnostic.stage = .ready;
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

fn connectTcp(
    endpoint: TcpEndpoint,
    diagnostic: *ConnectDiagnostic,
) error{ SocketCreateFailed, SocketConnectFailed, SocketConnectTimedOut, SocketOptionFailed }!posix.fd_t {
    diagnostic.stage = .socket_create;
    const raw = system.socket(posix.AF.INET, posix.SOCK.STREAM, 0);
    const socket_errno = posix.errno(raw);
    if (socket_errno != .SUCCESS) {
        diagnostic.os_error = errnoCode(socket_errno);
        return error.SocketCreateFailed;
    }
    const fd: posix.fd_t = @intCast(raw);
    errdefer closeFd(fd);

    diagnostic.stage = .file_status_read;
    const original_flags = try fileStatusFlags(fd);
    diagnostic.stage = .nonblocking_enable;
    try setFileStatusFlags(fd, original_flags | nonblockingFlag());

    var address = ipv4Address(endpoint.address, endpoint.port);
    var connected = false;
    diagnostic.stage = .socket_connect;
    while (true) {
        const result = system.connect(fd, @ptrCast(&address), @sizeOf(posix.sockaddr.in));
        const connect_errno = posix.errno(result);
        switch (connect_errno) {
            .SUCCESS, .ISCONN => {
                connected = true;
                break;
            },
            .INTR => continue,
            .INPROGRESS, .ALREADY, .AGAIN => break,
            else => {
                diagnostic.os_error = errnoCode(connect_errno);
                return error.SocketConnectFailed;
            },
        }
    }

    if (!connected) {
        diagnostic.stage = .socket_poll;
        const deadline_ms = std.math.add(
            i64,
            try monotonicMilliseconds(),
            tcp_connect_timeout_ms,
        ) catch return error.SocketConnectFailed;
        while (true) {
            const now_ms = try monotonicMilliseconds();
            if (now_ms >= deadline_ms) return error.SocketConnectTimedOut;
            const remaining_ms: i32 = @intCast(@min(deadline_ms - now_ms, std.math.maxInt(i32)));
            var fds = [_]posix.pollfd{.{
                .fd = fd,
                .events = posix.POLL.OUT,
                .revents = 0,
            }};
            const ready_raw = system.poll(&fds, 1, remaining_ms);
            switch (posix.errno(ready_raw)) {
                .SUCCESS => {
                    if (ready_raw == 0) return error.SocketConnectTimedOut;
                    if (fds[0].revents & (posix.POLL.ERR | posix.POLL.HUP | posix.POLL.NVAL | posix.POLL.OUT) == 0)
                        return error.SocketConnectFailed;
                    break;
                },
                .INTR => {
                    diagnostic.poll_interrupts +|= 1;
                    continue;
                },
                else => return error.SocketConnectFailed,
            }
        }
        diagnostic.stage = .socket_verify;
        try verifySocketConnected(fd, diagnostic);
    }

    diagnostic.stage = .blocking_restore;
    try setFileStatusFlags(fd, original_flags);
    diagnostic.stage = .tcp_nodelay;
    try setTcpNoDelay(fd);
    return fd;
}

// One total SSH handshake deadline, including a peer that drips a partial header.
// Ordinary established long-poll observations remain intentionally unbounded and
// wake via their independently owned Cancellation socket.
fn readHandshake(fd: posix.fd_t, output: []u8, deadline_ms: ?i64) Error!void {
    if (deadline_ms == null) return readExact(fd, output);
    var offset: usize = 0;
    while (offset < output.len) {
        const remaining = deadline_ms.? - try monotonicMilliseconds();
        if (remaining <= 0) return error.SocketConnectTimedOut;
        var descriptors = [_]posix.pollfd{.{ .fd = fd, .events = posix.POLL.IN, .revents = 0 }};
        const ready = system.poll(&descriptors, 1, @intCast(@min(remaining, std.math.maxInt(i32))));
        switch (posix.errno(ready)) {
            .INTR => continue,
            .SUCCESS => if (ready == 0) {
                return error.SocketConnectTimedOut;
            },
            else => return error.SocketReadFailed,
        }
        const count = system.read(fd, output[offset..].ptr, output.len - offset);
        switch (posix.errno(count)) {
            .INTR => continue,
            .SUCCESS => {
                if (count == 0) return error.ConnectionClosed;
                offset += @intCast(count);
            },
            .CONNRESET, .NOTCONN => return error.ConnectionClosed,
            else => return error.SocketReadFailed,
        }
    }
}

fn errnoCode(value: posix.E) i32 {
    return @intCast(@backingInt(value));
}

fn monotonicMilliseconds() error{SocketConnectFailed}!i64 {
    var now: posix.timespec = undefined;
    if (posix.errno(system.clock_gettime(.MONOTONIC, &now)) != .SUCCESS)
        return error.SocketConnectFailed;
    const nanoseconds = @as(i128, now.sec) * std.time.ns_per_s + now.nsec;
    return @intCast(@divFloor(nanoseconds, std.time.ns_per_ms));
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

fn verifySocketConnected(
    fd: posix.fd_t,
    diagnostic: *ConnectDiagnostic,
) error{ SocketConnectFailed, SocketOptionFailed }!void {
    var socket_error: c_int = 0;
    var length: posix.socklen_t = @sizeOf(c_int);
    const result = system.getsockopt(
        fd,
        posix.SOL.SOCKET,
        posix.SO.ERROR,
        @ptrCast(&socket_error),
        &length,
    );
    const option_errno = posix.errno(result);
    if (option_errno != .SUCCESS or length != @sizeOf(c_int)) {
        diagnostic.os_error = errnoCode(option_errno);
        return error.SocketOptionFailed;
    }
    if (socket_error != 0) {
        diagnostic.os_error = socket_error;
        return error.SocketConnectFailed;
    }
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
        // A disconnected SSH channel (or ordinary socket) is an I/O result,
        // never permission to terminate the embedder through process SIGPIPE.
        const result = if (builtin.os.tag == .linux)
            system.sendto(fd, bytes[offset..].ptr, bytes.len - offset, posix.MSG.NOSIGNAL, null, 0)
        else
            system.write(fd, bytes[offset..].ptr, bytes.len - offset);
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

fn shutdownFd(fd: posix.fd_t) error{SocketShutdownFailed}!void {
    while (true) {
        const result = system.shutdown(fd, posix.SHUT.RDWR);
        switch (posix.errno(result)) {
            .SUCCESS, .NOTCONN => return,
            .INTR => continue,
            else => return error.SocketShutdownFailed,
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

fn testHandshakePeerUntilClosed(fd: posix.fd_t) void {
    defer closeFd(fd);
    var header: [protocol.header_bytes]u8 = undefined;
    readExact(fd, &header) catch @panic("hello header");
    const decoded_header = protocol.decodeHeader(&header) catch @panic("hello frame");
    if (decoded_header.kind != .hello or decoded_header.payload_len != protocol.payload_bytes.hello)
        @panic("wrong hello");
    var welcome: [protocol.payload_bytes.welcome]u8 = undefined;
    protocol.encodeWelcome(&welcome, .{ .client_id = 72 });
    var response: [protocol.header_bytes]u8 = undefined;
    protocol.encodeHeader(&response, .{ .kind = .welcome, .payload_len = welcome.len }) catch
        @panic("welcome header");
    writeAll(fd, &response) catch @panic("welcome header write");
    writeAll(fd, &welcome) catch @panic("welcome write");
    var byte: [1]u8 = undefined;
    readExact(fd, &byte) catch |failure| switch (failure) {
        error.ConnectionClosed => return,
        else => @panic("peer wait"),
    };
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

test "handshake establishes client identity without transport policy" {
    const pair = testSocketPair();
    const thread = try std.Thread.spawn(.{}, testHandshakePeer, .{pair[1]});
    var diagnostic: ConnectDiagnostic = .{};
    var connection = try initOwnedFd(std.testing.allocator, pair[0], &diagnostic, null);
    defer connection.deinit();
    thread.join();
    const fd_flags = system.fcntl(connection.fd, posix.F.GETFD, @as(usize, 0));
    try std.testing.expectEqual(posix.E.SUCCESS, posix.errno(fd_flags));
    try std.testing.expect(fd_flags & posix.FD_CLOEXEC != 0);
    try std.testing.expectEqual(@as(protocol.ClientId, 71), connection.client_id);
    try std.testing.expectEqual(ConnectStage.ready, diagnostic.stage);
}

test "connection cancellation wakes a blocked receive while owner retains close" {
    const pair = testSocketPair();
    const peer = try std.Thread.spawn(.{}, testHandshakePeerUntilClosed, .{pair[1]});
    var diagnostic: ConnectDiagnostic = .{};
    var connection = try initOwnedFd(std.testing.allocator, pair[0], &diagnostic, null);
    defer connection.deinit();
    try std.testing.expectEqual(@as(protocol.ClientId, 72), connection.client_id);

    var probe = CancelReceiveProbe{ .connection = &connection };
    const reader = try std.Thread.spawn(.{}, testBlockedReceive, .{&probe});
    var cancellation = try connection.cancellation();
    defer cancellation.deinit();
    try cancellation.cancel();
    reader.join();
    peer.join();
    try std.testing.expect(probe.closed);
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

test "SSH handshake has one bounded total deadline and preserves caller close" {
    const pair = testSocketPair();
    defer closeFd(pair[0]);
    defer closeFd(pair[1]);
    try writeAll(pair[1], "H");
    var header: [protocol.header_bytes]u8 = undefined;
    try std.testing.expectError(error.SocketConnectTimedOut, readHandshake(pair[0], &header, (try monotonicMilliseconds()) + 20));
}

test "socket-only entrypoint never implicitly launches SSH" {
    var diagnostic: ConnectDiagnostic = .{};
    try std.testing.expectError(error.InvalidEndpoint, Connection.connectDiagnosed(std.testing.allocator, "ssh://alias/a", &diagnostic));
    try std.testing.expectEqual(ConnectStage.endpoint, diagnostic.stage);
}

test "closed stream write reports failure without a process-wide SIGPIPE policy" {
    if (builtin.os.tag != .linux) return;
    const pair = testSocketPair();
    defer closeFd(pair[0]);
    closeFd(pair[1]);
    try std.testing.expectError(error.ConnectionClosed, writeAll(pair[0], "not replayable"));
}
