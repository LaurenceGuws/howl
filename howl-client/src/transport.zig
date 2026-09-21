//! Native ordered-byte-stream transport shared by Howl protocols.
//!
//! Owns explicit Unix/TCP connection mechanics, optional installed-OpenSSH
//! carriage, cancellation and descriptor lifetime. It knows no HWLS/HWLM framing.

const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const system = posix.system;
const ssh = @import("ssh.zig");

const tcp_prefix = "tcp://";
const unix_prefix = "unix:";

pub const Error = ssh.Error || error{
    RouteUnavailable,
    ConnectionCanceled,
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

// A single-use cancellation lifetime, created before connection setup. The
// native caller retains it until every borrowing connection/worker has stopped.
// Its private wake stream can interrupt a partial handshake, a full write buffer
// or an idle observation without a periodic polling timer or FD-reuse race.
pub const Interrupt = opaque {
    pub fn init(allocator: std.mem.Allocator) Error!*Interrupt {
        var pair: [2]posix.fd_t = undefined;
        if (posix.errno(system.socketpair(posix.AF.UNIX, posix.SOCK.STREAM, 0, &pair)) != .SUCCESS)
            return error.SocketCreateFailed;
        errdefer closeFd(pair[0]);
        errdefer closeFd(pair[1]);
        try setCloseOnExec(pair[0]);
        try setCloseOnExec(pair[1]);
        const value = try allocator.create(InterruptState);
        value.* = .{ .allocator = allocator, .pair = pair };
        return @ptrCast(value);
    }

    pub fn cancel(self: *Interrupt) error{SocketShutdownFailed}!void {
        const value = self.state();
        value.canceled.store(true, .release);
        try shutdownFd(value.pair[1]);
    }

    pub fn deinit(self: *Interrupt) void {
        const value = self.state();
        closeFd(value.pair[1]);
        closeFd(value.pair[0]);
        value.allocator.destroy(value);
    }

    fn state(self: *Interrupt) *InterruptState {
        return @ptrCast(@alignCast(self));
    }
};

const InterruptState = struct {
    allocator: std.mem.Allocator,
    pair: [2]posix.fd_t,
    canceled: std.atomic.Value(bool) = .init(false),
};

fn checkInterrupted(interrupt: ?*Interrupt) error{ConnectionCanceled}!void {
    if (interrupt) |token| if (token.state().canceled.load(.acquire))
        return error.ConnectionCanceled;
}

pub const Stream = struct {
    fd: posix.fd_t,
    ssh_process: ?*ssh.Process = null,
    interrupt: ?*Interrupt = null,
    handshake_deadline_ms: ?i64 = null,
    original_flags: usize = 0,
    restore_flags_after_handshake: bool = false,

    pub fn connectDiagnosed(endpoint: []const u8, diagnostic: *ConnectDiagnostic) Error!Stream {
        diagnostic.* = .{ .stage = .endpoint };
        const fd = if (std.mem.startsWith(u8, endpoint, tcp_prefix))
            try connectTcp(try tcpEndpoint(endpoint), diagnostic, null)
        else if (std.mem.startsWith(u8, endpoint, unix_prefix))
            try connectUnix(endpoint[unix_prefix.len..], null)
        else
            return error.InvalidEndpoint;
        return initOwnedFd(fd, diagnostic, null, null);
    }

    pub fn connectNative(
        allocator: std.mem.Allocator,
        io: std.Io,
        endpoint: []const u8,
        diagnostic: *ConnectDiagnostic,
    ) Error!Stream {
        return connectNativeCancelable(allocator, io, endpoint, diagnostic, null);
    }

    pub fn connectNativeCancelable(
        allocator: std.mem.Allocator,
        io: std.Io,
        endpoint: []const u8,
        diagnostic: *ConnectDiagnostic,
        interrupt: ?*Interrupt,
    ) Error!Stream {
        diagnostic.* = .{ .stage = .endpoint };
        try checkInterrupted(interrupt);
        const deadline = (try monotonicMilliseconds()) + tcp_connect_timeout_ms;
        if (!std.mem.startsWith(u8, endpoint, "ssh://")) {
            const fd = if (std.mem.startsWith(u8, endpoint, tcp_prefix))
                try connectTcp(try tcpEndpoint(endpoint), diagnostic, interrupt)
            else if (std.mem.startsWith(u8, endpoint, unix_prefix))
                try connectUnix(endpoint[unix_prefix.len..], interrupt)
            else
                return error.InvalidEndpoint;
            return initOwnedFd(fd, diagnostic, deadline, interrupt);
        }
        if (comptime !ssh.supported) return error.RouteUnavailable;
        const route = try ssh.parse(endpoint);
        diagnostic.stage = .ssh_launch;
        const opened = try ssh.Process.open(allocator, io, route);
        errdefer diagnostic.route_message_len = opened.process.deinit(&diagnostic.route_message);
        var value = try initOwnedFd(opened.fd, diagnostic, deadline, interrupt);
        value.ssh_process = opened.process;
        return value;
    }

    pub fn deinit(self: *Stream) void {
        closeFd(self.fd);
        if (comptime ssh.supported) {
            if (self.ssh_process) |process| {
                var ignored: [ssh.diagnostic_bytes]u8 = undefined;
                const ignored_len = process.deinit(&ignored);
                std.debug.assert(ignored_len <= ignored.len);
            }
        }
        self.* = undefined;
    }

    /// Releases the stream while preserving bounded SSH carrier diagnostics.
    pub fn deinitDiagnosed(self: *Stream, diagnostic: *ConnectDiagnostic) void {
        closeFd(self.fd);
        if (comptime ssh.supported) {
            if (self.ssh_process) |process| {
                diagnostic.route_message_len = process.deinit(&diagnostic.route_message);
            }
        }
        self.* = undefined;
    }

    pub fn readinessFd(self: *const Stream) posix.fd_t {
        return self.fd;
    }

    pub fn cancellation(self: *const Stream) error{ SocketDuplicateFailed, SocketOptionFailed }!Cancellation {
        const raw = system.dup(self.fd);
        if (posix.errno(raw) != .SUCCESS) return error.SocketDuplicateFailed;
        const fd: posix.fd_t = @intCast(raw);
        errdefer closeFd(fd);
        try setCloseOnExec(fd);
        return .{ .fd = fd };
    }

    pub fn handshakeWrite(self: *Stream, bytes: []const u8) Error!void {
        return writeInterrupt(self.fd, bytes, self.handshake_deadline_ms, self.interrupt);
    }

    pub fn handshakeRead(self: *Stream, output: []u8) Error!void {
        return readInterrupt(self.fd, output, self.handshake_deadline_ms, self.interrupt);
    }

    pub fn finishHandshake(self: *Stream, diagnostic: *ConnectDiagnostic) Error!void {
        if (self.restore_flags_after_handshake) {
            diagnostic.stage = .blocking_restore;
            try setFileStatusFlags(self.fd, self.original_flags);
            self.restore_flags_after_handshake = false;
        }
        self.handshake_deadline_ms = null;
        diagnostic.stage = .ready;
    }

    pub fn write(self: *Stream, bytes: []const u8) Error!void {
        return writeInterrupt(self.fd, bytes, null, self.interrupt);
    }

    pub fn read(self: *Stream, output: []u8) Error!void {
        return readInterrupt(self.fd, output, null, self.interrupt);
    }
};

fn initOwnedFd(
    fd: posix.fd_t,
    diagnostic: *ConnectDiagnostic,
    deadline_ms: ?i64,
    interrupt: ?*Interrupt,
) Error!Stream {
    errdefer closeFd(fd);
    diagnostic.stage = .close_on_exec;
    try setCloseOnExec(fd);
    try checkInterrupted(interrupt);
    diagnostic.stage = .file_status_read;
    const flags = try fileStatusFlags(fd);
    const needs_nonblocking = deadline_ms != null or interrupt != null;
    if (needs_nonblocking) {
        diagnostic.stage = .nonblocking_enable;
        try setFileStatusFlags(fd, flags | nonblockingFlag());
    }
    return .{
        .fd = fd,
        .interrupt = interrupt,
        .handshake_deadline_ms = deadline_ms,
        .original_flags = flags,
        .restore_flags_after_handshake = needs_nonblocking and interrupt == null,
    };
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
    interrupt: ?*Interrupt,
) Error!posix.fd_t {
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
        try waitReady(fd, posix.POLL.OUT, deadline_ms, interrupt, &diagnostic.poll_interrupts);
        diagnostic.stage = .socket_verify;
        try verifySocketConnected(fd, diagnostic);
    }

    diagnostic.stage = .blocking_restore;
    try setFileStatusFlags(fd, original_flags);
    diagnostic.stage = .tcp_nodelay;
    try setTcpNoDelay(fd);
    return fd;
}

// Native waits share the same data-plane framing; only their caller-owned wake
// descriptor differs. A canceled scope remains canceled through partial frames.
fn waitReady(fd: posix.fd_t, events: i16, deadline_ms: ?i64, interrupt: ?*Interrupt, poll_interrupts: ?*u16) Error!void {
    while (true) {
        try checkInterrupted(interrupt);
        const timeout: i32 = if (deadline_ms) |end| blk: {
            const remaining = end - try monotonicMilliseconds();
            if (remaining <= 0) return error.SocketConnectTimedOut;
            break :blk @intCast(@min(remaining, std.math.maxInt(i32)));
        } else -1;
        var fds = [_]posix.pollfd{
            .{ .fd = fd, .events = events, .revents = 0 },
            .{ .fd = if (interrupt) |token| token.state().pair[0] else -1, .events = posix.POLL.IN, .revents = 0 },
        };
        const ready = system.poll(&fds, if (interrupt != null) 2 else 1, timeout);
        switch (posix.errno(ready)) {
            .INTR => {
                if (poll_interrupts) |count| count.* +|= 1;
                continue;
            },
            .SUCCESS => if (ready == 0) {
                return error.SocketConnectTimedOut;
            },
            else => return error.SocketReadFailed,
        }
        try checkInterrupted(interrupt);
        if (fds[1].revents != 0) return error.ConnectionCanceled;
        if (fds[0].revents & posix.POLL.NVAL != 0) return error.SocketReadFailed;
        if (fds[0].revents & (events | posix.POLL.HUP | posix.POLL.ERR) != 0) return;
    }
}

fn readInterrupt(fd: posix.fd_t, output: []u8, deadline_ms: ?i64, interrupt: ?*Interrupt) Error!void {
    if (deadline_ms == null and interrupt == null) return readExact(fd, output);
    var offset: usize = 0;
    while (offset < output.len) {
        try checkInterrupted(interrupt);
        if (deadline_ms) |end| if (try monotonicMilliseconds() >= end) return error.SocketConnectTimedOut;
        const count = system.read(fd, output[offset..].ptr, output.len - offset);
        switch (posix.errno(count)) {
            .INTR => continue,
            .AGAIN => try waitReady(fd, posix.POLL.IN, deadline_ms, interrupt, null),
            .SUCCESS => {
                if (count == 0) return error.ConnectionClosed;
                offset += @intCast(count);
            },
            .CONNRESET, .NOTCONN => return error.ConnectionClosed,
            else => return error.SocketReadFailed,
        }
    }
}

fn writeInterrupt(fd: posix.fd_t, bytes: []const u8, deadline_ms: ?i64, interrupt: ?*Interrupt) Error!void {
    if (deadline_ms == null and interrupt == null) return writeAll(fd, bytes);
    var offset: usize = 0;
    while (offset < bytes.len) {
        try checkInterrupted(interrupt);
        const count = if (builtin.os.tag == .linux)
            system.sendto(fd, bytes[offset..].ptr, bytes.len - offset, posix.MSG.NOSIGNAL, null, 0)
        else
            system.write(fd, bytes[offset..].ptr, bytes.len - offset);
        switch (posix.errno(count)) {
            .INTR => continue,
            .AGAIN => try waitReady(fd, posix.POLL.OUT, deadline_ms, interrupt, null),
            .SUCCESS => {
                if (count == 0) return error.ConnectionClosed;
                offset += @intCast(count);
            },
            .PIPE, .CONNRESET, .NOTCONN => return error.ConnectionClosed,
            else => return error.SocketWriteFailed,
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

fn connectUnix(path: []const u8, interrupt: ?*Interrupt) Error!posix.fd_t {
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
    if (interrupt != null) try setFileStatusFlags(fd, (try fileStatusFlags(fd)) | nonblockingFlag());
    try checkInterrupted(interrupt);
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

const InterruptProbe = struct {
    fd: posix.fd_t,
    interrupt: *Interrupt,
    write: bool,
    canceled: bool = false,
};

fn testInterruptedIo(probe: *InterruptProbe) void {
    var byte = [_]u8{'x'};
    const result = if (probe.write)
        writeInterrupt(probe.fd, &byte, null, probe.interrupt)
    else
        readInterrupt(probe.fd, &byte, null, probe.interrupt);
    result catch |failure| {
        probe.canceled = failure == error.ConnectionCanceled;
    };
}

fn testSocketPair() [2]posix.fd_t {
    var pair: [2]posix.fd_t = undefined;
    const result = system.socketpair(posix.AF.UNIX, posix.SOCK.STREAM, 0, &pair);
    if (posix.errno(result) != .SUCCESS) @panic("test socketpair failed");
    return pair;
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
    }) |bad| try std.testing.expectError(error.InvalidEndpoint, tcpEndpoint(bad));
}

test "native handshake deadline is bounded and preserves caller close" {
    const pair = testSocketPair();
    defer closeFd(pair[0]);
    defer closeFd(pair[1]);
    try writeAll(pair[1], "H");
    var header: [12]u8 = undefined;
    try setFileStatusFlags(pair[0], (try fileStatusFlags(pair[0])) | nonblockingFlag());
    try std.testing.expectError(
        error.SocketConnectTimedOut,
        readInterrupt(pair[0], &header, (try monotonicMilliseconds()) + 20, null),
    );
}

test "closed stream write reports failure without process-wide SIGPIPE policy" {
    if (builtin.os.tag != .linux) return;
    const pair = testSocketPair();
    defer closeFd(pair[0]);
    closeFd(pair[1]);
    try std.testing.expectError(error.ConnectionClosed, writeAll(pair[0], "not replayable"));
}

test "native cancellation is single use and preempts connection creation" {
    const interrupt = try Interrupt.init(std.testing.allocator);
    defer interrupt.deinit();
    try interrupt.cancel();
    try interrupt.cancel();
    var diagnostic: ConnectDiagnostic = .{};
    try std.testing.expectError(
        error.ConnectionCanceled,
        Stream.connectNativeCancelable(
            std.testing.allocator,
            std.testing.io,
            "ssh://unused.invalid/a",
            &diagnostic,
            interrupt,
        ),
    );
    try std.testing.expectEqual(ConnectStage.endpoint, diagnostic.stage);
}

test "native cancellation wakes idle read without closing unrelated descriptors" {
    const pair = testSocketPair();
    defer closeFd(pair[0]);
    defer closeFd(pair[1]);
    try setFileStatusFlags(pair[0], (try fileStatusFlags(pair[0])) | nonblockingFlag());
    const interrupt = try Interrupt.init(std.testing.allocator);
    defer interrupt.deinit();
    var probe = InterruptProbe{ .fd = pair[0], .interrupt = interrupt, .write = false };
    const worker = try std.Thread.spawn(.{}, testInterruptedIo, .{&probe});
    try std.Io.sleep(std.testing.io, .fromMilliseconds(20), .awake);
    try interrupt.cancel();
    worker.join();
    try std.testing.expect(probe.canceled);
    try writeAll(pair[1], "z");
    var byte: [1]u8 = undefined;
    try readExact(pair[0], &byte);
    try std.testing.expectEqual(@as(u8, 'z'), byte[0]);
}

test "native cancellation wakes backpressured write without consuming peer data" {
    const pair = testSocketPair();
    defer closeFd(pair[0]);
    defer closeFd(pair[1]);
    try setFileStatusFlags(pair[0], (try fileStatusFlags(pair[0])) | nonblockingFlag());
    const payload: [4096]u8 = @splat('q');
    var total: usize = 0;
    while (true) {
        const n = system.write(pair[0], &payload, payload.len);
        if (posix.errno(n) == .AGAIN) break;
        try std.testing.expectEqual(posix.E.SUCCESS, posix.errno(n));
        total += n;
        try std.testing.expect(total <= 4 * 1024 * 1024);
    }
    const interrupt = try Interrupt.init(std.testing.allocator);
    defer interrupt.deinit();
    var probe = InterruptProbe{ .fd = pair[0], .interrupt = interrupt, .write = true };
    const worker = try std.Thread.spawn(.{}, testInterruptedIo, .{&probe});
    try std.Io.sleep(std.testing.io, .fromMilliseconds(20), .awake);
    try interrupt.cancel();
    worker.join();
    try std.testing.expect(probe.canceled);
    var byte: [1]u8 = undefined;
    try readExact(pair[1], &byte);
    try std.testing.expectEqual(@as(u8, 'q'), byte[0]);
}

test "native cancellation wins over already-readable buffered bytes" {
    const pair = testSocketPair();
    defer closeFd(pair[0]);
    defer closeFd(pair[1]);
    try setFileStatusFlags(pair[0], (try fileStatusFlags(pair[0])) | nonblockingFlag());
    const interrupt = try Interrupt.init(std.testing.allocator);
    defer interrupt.deinit();
    try writeAll(pair[1], "old");
    try interrupt.cancel();
    var bytes: [3]u8 = undefined;
    try std.testing.expectError(error.ConnectionCanceled, readInterrupt(pair[0], &bytes, null, interrupt));
    try readExact(pair[0], &bytes);
    try std.testing.expectEqualStrings("old", &bytes);
}
