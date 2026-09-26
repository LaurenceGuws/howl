//! Windows ordered-byte-stream transport for Howl native clients.
//!
//! Windows currently admits numeric-IPv4 TCP only. The public transport
//! contract remains the same as the POSIX backend: bounded construction,
//! TCP_NODELAY, exact diagnostics, and caller-owned interruption. Unix-domain
//! endpoints and raw-socket duplication stay explicit unsupported surfaces.

const std = @import("std");
const windows = std.os.windows;
const ws2 = windows.ws2_32;

const tcp_prefix = "tcp://";
const unix_prefix = "unix:";
const setup_timeout_ms: i64 = 15_000;

const SOCKET = usize;
const invalid_socket = std.math.maxInt(SOCKET);
const socket_error: c_int = -1;
const WSAEVENT = ?windows.HANDLE;

const fd_read: i32 = 1 << 0;
const fd_write: i32 = 1 << 1;
const fd_connect: i32 = 1 << 4;
const fd_close: i32 = 1 << 5;
const fd_all: i32 = fd_read | fd_write | fd_connect | fd_close;
const wsa_wait_event_0: u32 = 0;
const wsa_wait_failed: u32 = 0xFFFF_FFFF;
const wsa_wait_timeout: u32 = 258;
const wsa_infinite: u32 = 0xFFFF_FFFF;
const sd_both: c_int = 2;

const wsaeintr = 10_004;
const wsaewouldblock = 10_035;
const wsaeinprogress = 10_036;
const wsaealready = 10_037;
const wsaeconnreset = 10_054;
const wsaeisconn = 10_056;
const wsaenotconn = 10_057;
const wsaetimedout = 10_060;

const WSADATA = if (@sizeOf(usize) == 8) extern struct {
    version: u16,
    high_version: u16,
    maximum_sockets: u16,
    maximum_datagram: u16,
    vendor_info: ?[*:0]u8,
    description: [257]u8,
    system_status: [129]u8,
} else extern struct {
    version: u16,
    high_version: u16,
    description: [257]u8,
    system_status: [129]u8,
    maximum_sockets: u16,
    maximum_datagram: u16,
    vendor_info: ?[*:0]u8,
};

const NetworkEvents = extern struct {
    events: i32,
    errors: [10]c_int,
};

extern "ws2_32" fn WSAStartup(version: u16, data: *WSADATA) callconv(.winapi) c_int;
extern "ws2_32" fn WSACleanup() callconv(.winapi) c_int;
extern "ws2_32" fn WSAGetLastError() callconv(.winapi) c_int;
extern "ws2_32" fn WSACreateEvent() callconv(.winapi) WSAEVENT;
extern "ws2_32" fn WSACloseEvent(event: WSAEVENT) callconv(.winapi) c_int;
extern "ws2_32" fn WSASetEvent(event: WSAEVENT) callconv(.winapi) c_int;
extern "ws2_32" fn WSAEventSelect(socket_value: SOCKET, event: WSAEVENT, events: i32) callconv(.winapi) c_int;
extern "ws2_32" fn WSAEnumNetworkEvents(socket_value: SOCKET, event: WSAEVENT, events: *NetworkEvents) callconv(.winapi) c_int;
extern "ws2_32" fn WSAWaitForMultipleEvents(
    count: u32,
    events: [*]const WSAEVENT,
    wait_all: c_int,
    timeout_ms: u32,
    alertable: c_int,
) callconv(.winapi) u32;
extern "ws2_32" fn socket(address_family: c_int, socket_type: c_int, protocol: c_int) callconv(.winapi) SOCKET;
extern "ws2_32" fn connect(socket_value: SOCKET, address: *const ws2.sockaddr, address_len: c_int) callconv(.winapi) c_int;
extern "ws2_32" fn recv(socket_value: SOCKET, bytes: [*]u8, length: c_int, flags: c_int) callconv(.winapi) c_int;
extern "ws2_32" fn send(socket_value: SOCKET, bytes: [*]const u8, length: c_int, flags: c_int) callconv(.winapi) c_int;
extern "ws2_32" fn shutdown(socket_value: SOCKET, how: c_int) callconv(.winapi) c_int;
extern "ws2_32" fn closesocket(socket_value: SOCKET) callconv(.winapi) c_int;
extern "ws2_32" fn getsockopt(
    socket_value: SOCKET,
    level: c_int,
    option: c_int,
    value: *c_int,
    length: *c_int,
) callconv(.winapi) c_int;
extern "ws2_32" fn setsockopt(
    socket_value: SOCKET,
    level: c_int,
    option: c_int,
    value: *const c_int,
    length: c_int,
) callconv(.winapi) c_int;

/// Platform-native ordered-stream handle used only by callers that integrate
/// transport readiness into an external event loop.
pub const Handle = SOCKET;

pub const Error = error{
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
};

pub const ConnectDiagnostic = struct {
    stage: ConnectStage = .start,
    os_error: i32 = 0,
    poll_interrupts: u16 = 0,
    route_message: [512]u8 = undefined,
    route_message_len: usize = 0,
};

/// Windows does not expose the POSIX duplicate-fd cancellation helper in this
/// checkpoint. Odin uses Interrupt; callers requiring duplicated readiness
/// ownership receive an explicit construction error.
pub const Cancellation = struct {
    pub fn cancel(_: *const Cancellation) error{SocketShutdownFailed}!void {
        return error.SocketShutdownFailed;
    }

    pub fn deinit(self: *Cancellation) void {
        self.* = undefined;
    }
};

/// Single-use caller-owned wake token. Every blocking Windows transport wait
/// includes this event, so cancellation never depends on a polling interval.
pub const Interrupt = opaque {
    pub fn init(allocator: std.mem.Allocator) (std.mem.Allocator.Error || error{ SocketCreateFailed, SocketOptionFailed })!*Interrupt {
        try startWinsock();
        errdefer stopWinsock();
        const event = WSACreateEvent() orelse return error.SocketCreateFailed;
        errdefer closeEvent(event);
        const value = try allocator.create(InterruptState);
        value.* = .{ .allocator = allocator, .event = event };
        return @ptrCast(value);
    }

    pub fn cancel(self: *Interrupt) error{SocketShutdownFailed}!void {
        const value = self.state();
        value.canceled.store(true, .release);
        if (WSASetEvent(value.event) == 0) return error.SocketShutdownFailed;
    }

    pub fn deinit(self: *Interrupt) void {
        const value = self.state();
        closeEvent(value.event);
        stopWinsock();
        value.allocator.destroy(value);
    }

    fn state(self: *Interrupt) *InterruptState {
        return @ptrCast(@alignCast(self));
    }
};

const InterruptState = struct {
    allocator: std.mem.Allocator,
    event: WSAEVENT,
    canceled: std.atomic.Value(bool) = .init(false),
};

fn checkInterrupted(interrupt: ?*Interrupt) error{ConnectionCanceled}!void {
    if (interrupt) |token| if (token.state().canceled.load(.acquire))
        return error.ConnectionCanceled;
}

pub const Stream = struct {
    socket: SOCKET,
    event: WSAEVENT,
    interrupt: ?*Interrupt = null,
    handshake_deadline_ms: ?i64 = null,

    pub fn connectDiagnosed(endpoint: []const u8, diagnostic: *ConnectDiagnostic) Error!Stream {
        return connectCancelable(endpoint, diagnostic, null);
    }

    pub fn connectCancelable(
        endpoint: []const u8,
        diagnostic: *ConnectDiagnostic,
        interrupt: ?*Interrupt,
    ) Error!Stream {
        diagnostic.* = .{ .stage = .endpoint };
        try checkInterrupted(interrupt);
        if (std.mem.startsWith(u8, endpoint, unix_prefix)) return error.InvalidEndpoint;
        if (!std.mem.startsWith(u8, endpoint, tcp_prefix)) return error.InvalidEndpoint;
        const parsed = try tcpEndpoint(endpoint);
        const deadline = (try monotonicMilliseconds()) + setup_timeout_ms;

        try startWinsock();
        errdefer stopWinsock();

        diagnostic.stage = .socket_create;
        const socket_value = socket(ws2.AF.INET, ws2.SOCK.STREAM, ws2.IPPROTO.TCP);
        if (socket_value == invalid_socket) {
            diagnostic.os_error = WSAGetLastError();
            return error.SocketCreateFailed;
        }
        errdefer closeSocket(socket_value);

        const event = WSACreateEvent() orelse {
            diagnostic.os_error = WSAGetLastError();
            return error.SocketCreateFailed;
        };
        errdefer closeEvent(event);

        diagnostic.stage = .nonblocking_enable;
        if (WSAEventSelect(socket_value, event, fd_all) == socket_error) {
            diagnostic.os_error = WSAGetLastError();
            return error.SocketOptionFailed;
        }

        var address = ws2.sockaddr.in{
            .family = ws2.AF.INET,
            .port = std.mem.nativeToBig(u16, parsed.port),
            .addr = @bitCast(parsed.address),
        };
        diagnostic.stage = .socket_connect;
        const connected = connect(socket_value, @ptrCast(&address), @sizeOf(@TypeOf(address)));
        if (connected == socket_error) {
            const failure = WSAGetLastError();
            switch (failure) {
                wsaewouldblock, wsaeinprogress, wsaealready => {
                    diagnostic.stage = .socket_poll;
                    try waitSocketReady(socket_value, event, fd_connect, deadline, interrupt);
                    diagnostic.stage = .socket_verify;
                    try verifySocketConnected(socket_value, diagnostic);
                },
                wsaeisconn => {},
                else => {
                    diagnostic.os_error = failure;
                    return error.SocketConnectFailed;
                },
            }
        }

        diagnostic.stage = .tcp_nodelay;
        try setTcpNoDelay(socket_value);
        return .{
            .socket = socket_value,
            .event = event,
            .interrupt = interrupt,
            .handshake_deadline_ms = deadline,
        };
    }

    /// Adopts one already-created WinSock stream. This path exists for API
    /// parity but is not used by the Windows Remote product route.
    pub fn adopt(socket_value: Handle, diagnostic: *ConnectDiagnostic, interrupt: ?*Interrupt) Error!Stream {
        try startWinsock();
        errdefer stopWinsock();
        const event = WSACreateEvent() orelse return error.SocketCreateFailed;
        errdefer closeEvent(event);
        diagnostic.stage = .nonblocking_enable;
        if (WSAEventSelect(socket_value, event, fd_all) == socket_error) {
            diagnostic.os_error = WSAGetLastError();
            return error.SocketOptionFailed;
        }
        try checkInterrupted(interrupt);
        return .{
            .socket = socket_value,
            .event = event,
            .interrupt = interrupt,
            .handshake_deadline_ms = (try monotonicMilliseconds()) + setup_timeout_ms,
        };
    }

    pub fn beginHandshake(self: *Stream, diagnostic: *ConnectDiagnostic) Error!void {
        if (self.handshake_deadline_ms != null) return;
        try checkInterrupted(self.interrupt);
        self.handshake_deadline_ms = (try monotonicMilliseconds()) + setup_timeout_ms;
        diagnostic.stage = .nonblocking_enable;
    }

    pub fn deinit(self: *Stream) void {
        closeSocket(self.socket);
        closeEvent(self.event);
        stopWinsock();
        self.* = undefined;
    }

    pub fn readinessFd(self: *const Stream) Handle {
        return self.socket;
    }

    pub fn cancellation(_: *const Stream) error{ SocketDuplicateFailed, SocketOptionFailed }!Cancellation {
        return error.SocketDuplicateFailed;
    }

    pub fn handshakeWrite(self: *Stream, bytes: []const u8) Error!void {
        return writeInterrupt(self, bytes, self.handshake_deadline_ms);
    }

    pub fn handshakeRead(self: *Stream, output: []u8) Error!void {
        return readInterrupt(self, output, self.handshake_deadline_ms);
    }

    pub fn finishHandshake(self: *Stream, diagnostic: *ConnectDiagnostic) Error!void {
        try checkInterrupted(self.interrupt);
        self.handshake_deadline_ms = null;
        diagnostic.stage = .ready;
    }

    pub fn write(self: *Stream, bytes: []const u8) Error!void {
        return writeInterrupt(self, bytes, self.handshake_deadline_ms);
    }

    pub fn read(self: *Stream, output: []u8) Error!void {
        return readInterrupt(self, output, self.handshake_deadline_ms);
    }
};

const TcpEndpoint = struct {
    address: [4]u8,
    port: u16,
};

fn tcpEndpoint(endpoint: []const u8) error{InvalidEndpoint}!TcpEndpoint {
    const text = endpoint[tcp_prefix.len..];
    if (text.len == 0 or std.mem.indexOfAny(u8, text, "/?#") != null)
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

fn waitSocketReady(
    socket_value: SOCKET,
    socket_event: WSAEVENT,
    desired_events: i32,
    deadline_ms: ?i64,
    interrupt: ?*Interrupt,
) Error!void {
    while (true) {
        try checkInterrupted(interrupt);
        const timeout_ms: u32 = if (deadline_ms) |deadline| blk: {
            const remaining = deadline - try monotonicMilliseconds();
            if (remaining <= 0) return error.SocketConnectTimedOut;
            break :blk @intCast(@min(remaining, @as(i64, std.math.maxInt(u32) - 1)));
        } else wsa_infinite;

        var events = [2]WSAEVENT{
            socket_event,
            if (interrupt) |token| token.state().event else null,
        };
        const event_count: u32 = if (interrupt == null) 1 else 2;
        const result = WSAWaitForMultipleEvents(event_count, &events, 0, timeout_ms, 0);
        if (result == wsa_wait_timeout) return error.SocketConnectTimedOut;
        if (result == wsa_wait_failed) return error.SocketReadFailed;
        if (result == wsa_wait_event_0 + 1 and interrupt != null) {
            try checkInterrupted(interrupt);
            return error.ConnectionCanceled;
        }
        if (result != wsa_wait_event_0) return error.SocketReadFailed;

        var network_events: NetworkEvents = undefined;
        if (WSAEnumNetworkEvents(socket_value, socket_event, &network_events) == socket_error)
            return error.SocketReadFailed;
        try checkInterrupted(interrupt);
        if (network_events.events & (desired_events | fd_close) != 0) return;
    }
}

fn readInterrupt(stream: *Stream, output: []u8, deadline_ms: ?i64) Error!void {
    var offset: usize = 0;
    while (offset < output.len) {
        try checkInterrupted(stream.interrupt);
        if (deadline_ms) |deadline| if (try monotonicMilliseconds() >= deadline)
            return error.SocketConnectTimedOut;
        const chunk: c_int = @intCast(@min(output.len - offset, @as(usize, std.math.maxInt(c_int))));
        const count = recv(stream.socket, output[offset..].ptr, chunk, 0);
        if (count > 0) {
            offset += @intCast(count);
            continue;
        }
        if (count == 0) return error.ConnectionClosed;
        const failure = WSAGetLastError();
        switch (failure) {
            wsaeintr => continue,
            wsaewouldblock => try waitSocketReady(stream.socket, stream.event, fd_read, deadline_ms, stream.interrupt),
            wsaeconnreset, wsaenotconn => return error.ConnectionClosed,
            wsaetimedout => return error.SocketConnectTimedOut,
            else => return error.SocketReadFailed,
        }
    }
}

fn writeInterrupt(stream: *Stream, bytes: []const u8, deadline_ms: ?i64) Error!void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        try checkInterrupted(stream.interrupt);
        if (deadline_ms) |deadline| if (try monotonicMilliseconds() >= deadline)
            return error.SocketConnectTimedOut;
        const chunk: c_int = @intCast(@min(bytes.len - offset, @as(usize, std.math.maxInt(c_int))));
        const count = send(stream.socket, bytes[offset..].ptr, chunk, 0);
        if (count > 0) {
            offset += @intCast(count);
            continue;
        }
        if (count == 0) return error.ConnectionClosed;
        const failure = WSAGetLastError();
        switch (failure) {
            wsaeintr => continue,
            wsaewouldblock => try waitSocketReady(stream.socket, stream.event, fd_write, deadline_ms, stream.interrupt),
            wsaeconnreset, wsaenotconn => return error.ConnectionClosed,
            wsaetimedout => return error.SocketConnectTimedOut,
            else => return error.SocketWriteFailed,
        }
    }
}

fn verifySocketConnected(socket_value: SOCKET, diagnostic: *ConnectDiagnostic) Error!void {
    var socket_failure: c_int = 0;
    var length: c_int = @sizeOf(c_int);
    if (getsockopt(
        socket_value,
        ws2.SOL.SOCKET,
        ws2.SO.ERROR,
        &socket_failure,
        &length,
    ) == socket_error or length != @sizeOf(c_int)) {
        diagnostic.os_error = WSAGetLastError();
        return error.SocketOptionFailed;
    }
    if (socket_failure != 0) {
        diagnostic.os_error = socket_failure;
        return error.SocketConnectFailed;
    }
}

fn setTcpNoDelay(socket_value: SOCKET) error{SocketOptionFailed}!void {
    const enabled: c_int = 1;
    if (setsockopt(
        socket_value,
        ws2.IPPROTO.TCP,
        ws2.TCP.NODELAY,
        &enabled,
        @sizeOf(c_int),
    ) == socket_error) return error.SocketOptionFailed;
}

fn startWinsock() error{SocketCreateFailed}!void {
    var data: WSADATA = undefined;
    const result = WSAStartup(0x0202, &data);
    if (result != 0) return error.SocketCreateFailed;
}

fn stopWinsock() void {
    std.debug.assert(WSACleanup() == 0);
}

fn closeSocket(socket_value: SOCKET) void {
    std.debug.assert(closesocket(socket_value) == 0);
}

fn closeEvent(event: WSAEVENT) void {
    std.debug.assert(WSACloseEvent(event) != 0);
}

fn monotonicMilliseconds() error{SocketConnectFailed}!i64 {
    var counter: windows.LARGE_INTEGER = 0;
    var frequency: windows.LARGE_INTEGER = 0;
    if (!windows.ntdll.RtlQueryPerformanceCounter(&counter).toBool() or
        !windows.ntdll.RtlQueryPerformanceFrequency(&frequency).toBool() or
        frequency <= 0)
        return error.SocketConnectFailed;
    return @intCast(@divFloor(@as(i128, counter) * std.time.ms_per_s, frequency));
}

test "Windows endpoint parser accepts numeric IPv4 only" {
    const endpoint = try tcpEndpoint("tcp://100.96.0.4:43150");
    try std.testing.expectEqual([4]u8{ 100, 96, 0, 4 }, endpoint.address);
    try std.testing.expectEqual(@as(u16, 43150), endpoint.port);
    try std.testing.expectError(error.InvalidEndpoint, tcpEndpoint("tcp://home:43150"));
    try std.testing.expectError(error.InvalidEndpoint, tcpEndpoint("tcp://0.0.0.0:43150"));
}

test "Windows interruption is sticky before transport construction" {
    const interrupt = try Interrupt.init(std.testing.allocator);
    defer interrupt.deinit();
    try interrupt.cancel();
    try std.testing.expectError(error.ConnectionCanceled, checkInterrupted(interrupt));
}
