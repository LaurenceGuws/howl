//! Nonblocking HWLM manager listener for one authoritative Session registry.
//!
//! Manager clients may stall or disappear without pacing Session service. Each
//! accepted connection owns one bounded input buffer and at most one bounded
//! materialized response.

const std = @import("std");
const linux = std.os.linux;
const posix = std.posix;
const protocol = @import("howl_server_protocol");
const Registry = @import("registry.zig").Registry;

const maximum_clients: usize = 16;
const input_bytes: usize = protocol.header_bytes + protocol.maximum_request_payload_bytes;
const output_bytes: usize = protocol.header_bytes + protocol.maximum_payload_bytes;
const listen_backlog: u32 = maximum_clients;

pub const ListenerSpec = union(enum) {
    unix: []const u8,
    tcp_loopback: u16,
};

const Listener = struct {
    fd: posix.fd_t,
    unix_path: [108]u8 = @splat(0),
    unix_path_len: u8 = 0,
    tcp_port: ?u16 = null,

    fn init(io: std.Io, spec: ListenerSpec) !Listener {
        return switch (spec) {
            .unix => |path| blk: {
                std.Io.Dir.deleteFileAbsolute(io, path) catch |failure| switch (failure) {
                    error.FileNotFound => {},
                    else => return failure,
                };
                const fd = try listenUnix(path);
                var value = Listener{ .fd = fd, .unix_path_len = @intCast(path.len) };
                @memcpy(value.unix_path[0..path.len], path);
                break :blk value;
            },
            .tcp_loopback => |port| blk: {
                const bound = try listenTcpLoopback(port);
                break :blk .{ .fd = bound.fd, .tcp_port = bound.port };
            },
        };
    }

    fn deinit(self: *Listener) void {
        closeFd(self.fd);
        if (self.unix_path_len != 0) unlinkPath(self.unix_path[0..self.unix_path_len]);
        self.* = undefined;
    }

    fn endpointText(self: *const Listener, output: []u8) ![]const u8 {
        if (self.tcp_port) |port|
            return std.fmt.bufPrint(output, "tcp://127.0.0.1:{d}", .{port});
        return std.fmt.bufPrint(output, "unix:{s}", .{self.unix_path[0..self.unix_path_len]});
    }
};

const Client = struct {
    fd: posix.fd_t,
    input: []u8,
    input_len: usize = 0,
    output: []u8,
    output_len: usize = 0,
    output_offset: usize = 0,
    welcomed: bool = false,
    observe_after: ?u64 = null,

    fn init(allocator: std.mem.Allocator, fd: posix.fd_t) !Client {
        const input = try allocator.alloc(u8, input_bytes);
        errdefer allocator.free(input);
        const output = try allocator.alloc(u8, output_bytes);
        return .{ .fd = fd, .input = input, .output = output };
    }

    fn deinit(self: *Client, allocator: std.mem.Allocator) void {
        closeFd(self.fd);
        allocator.free(self.output);
        allocator.free(self.input);
        self.* = undefined;
    }

    fn outputPending(self: *const Client) bool {
        return self.output_offset < self.output_len;
    }

    fn resetOutput(self: *Client) void {
        self.output_len = 0;
        self.output_offset = 0;
    }
};

pub const Manager = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    listener: Listener,
    clients: [maximum_clients]?Client = @splat(null),
    stopping: bool = false,

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        spec: ListenerSpec,
    ) !Manager {
        return .{
            .allocator = allocator,
            .io = io,
            .listener = try Listener.init(io, spec),
        };
    }

    pub fn deinit(self: *Manager) void {
        for (&self.clients) |*maybe_client| {
            if (maybe_client.*) |*client| client.deinit(self.allocator);
            maybe_client.* = null;
        }
        self.listener.deinit();
    }

    pub fn endpointText(self: *const Manager, output: []u8) ![]const u8 {
        return self.listener.endpointText(output);
    }

    pub fn hasPendingOutput(self: *const Manager) bool {
        for (self.clients) |maybe_client| {
            const client = maybe_client orelse continue;
            if (client.outputPending()) return true;
        }
        return false;
    }

    pub fn turn(self: *Manager, registry: *Registry, timeout_ms: i32) !void {
        var descriptors: [1 + maximum_clients]posix.pollfd = undefined;
        descriptors[0] = .{ .fd = self.listener.fd, .events = posix.POLL.IN, .revents = 0 };
        for (self.clients, 0..) |maybe_client, index| {
            descriptors[index + 1] = if (maybe_client) |client| .{
                .fd = client.fd,
                .events = if (client.outputPending()) posix.POLL.OUT else if (client.observe_after == null) posix.POLL.IN else 0,
                .revents = 0,
            } else .{ .fd = -1, .events = 0, .revents = 0 };
        }
        const ready = try posix.poll(&descriptors, timeout_ms);
        if (ready == 0) {
            self.materializeRosterObservers(registry);
            return;
        }

        if (descriptors[0].revents & posix.POLL.IN != 0) self.acceptClients();
        var index: usize = 0;
        while (index < self.clients.len) : (index += 1) {
            if (self.clients[index] == null) continue;
            const events = descriptors[index + 1].revents;
            if (events & (posix.POLL.HUP | posix.POLL.ERR | posix.POLL.NVAL) != 0) {
                self.closeClient(index);
                continue;
            }
            if (events & posix.POLL.OUT != 0) self.writeClient(index);
            if (self.clients[index] != null and events & posix.POLL.IN != 0) self.readClient(index);
        }
        self.processBufferedRequests(registry);
        self.materializeRosterObservers(registry);
    }

    fn acceptClients(self: *Manager) void {
        var admitted: usize = 0;
        while (admitted < maximum_clients) : (admitted += 1) {
            const raw = linux.accept4(
                self.listener.fd,
                null,
                null,
                linux.SOCK.CLOEXEC | linux.SOCK.NONBLOCK,
            );
            switch (linux.errno(raw)) {
                .SUCCESS => {},
                .AGAIN => return,
                .INTR => continue,
                else => return,
            }
            const fd: posix.fd_t = @intCast(raw);
            errdefer closeFd(fd);
            if (self.listener.tcp_port != null) setTcpNoDelay(fd) catch {
                closeFd(fd);
                continue;
            };
            const slot = self.freeClientSlot() orelse {
                closeFd(fd);
                continue;
            };
            self.clients[slot] = Client.init(self.allocator, fd) catch {
                closeFd(fd);
                continue;
            };
        }
    }

    fn freeClientSlot(self: *const Manager) ?usize {
        for (self.clients, 0..) |client, index| if (client == null) return index;
        return null;
    }

    fn closeClient(self: *Manager, index: usize) void {
        if (self.clients[index]) |*client| client.deinit(self.allocator);
        self.clients[index] = null;
    }

    fn readClient(self: *Manager, index: usize) void {
        const client = if (self.clients[index]) |*value| value else return;
        if (client.outputPending() or client.observe_after != null or client.input_len == client.input.len) return;
        const room = client.input[client.input_len..];
        const result = linux.read(client.fd, room.ptr, room.len);
        switch (linux.errno(result)) {
            .SUCCESS => {
                if (result == 0 or result > room.len) return self.closeClient(index);
                client.input_len += result;
            },
            .AGAIN, .INTR => {},
            else => self.closeClient(index),
        }
    }

    fn writeClient(self: *Manager, index: usize) void {
        const client = if (self.clients[index]) |*value| value else return;
        if (!client.outputPending()) return;
        const bytes = client.output[client.output_offset..client.output_len];
        const result = linux.write(client.fd, bytes.ptr, bytes.len);
        switch (linux.errno(result)) {
            .SUCCESS => {
                if (result == 0 or result > bytes.len) return self.closeClient(index);
                client.output_offset += result;
                if (!client.outputPending()) client.resetOutput();
            },
            .AGAIN, .INTR => {},
            .PIPE, .CONNRESET => self.closeClient(index),
            else => self.closeClient(index),
        }
    }

    fn processBufferedRequests(self: *Manager, registry: *Registry) void {
        var index: usize = 0;
        while (index < self.clients.len) : (index += 1) {
            while (self.clients[index]) |*client| {
                if (client.outputPending() or client.observe_after != null or
                    client.input_len < protocol.header_bytes)
                    break;
                var header_bytes: [protocol.header_bytes]u8 = undefined;
                @memcpy(&header_bytes, client.input[0..protocol.header_bytes]);
                const header = protocol.decodeHeader(&header_bytes) catch {
                    self.closeClient(index);
                    break;
                };
                if (header.payload_len > protocol.maximum_request_payload_bytes) {
                    self.closeClient(index);
                    break;
                }
                const frame_bytes = protocol.header_bytes + @as(usize, header.payload_len);
                if (frame_bytes > client.input.len) {
                    self.closeClient(index);
                    break;
                }
                if (client.input_len < frame_bytes) break;
                const payload = client.input[protocol.header_bytes..frame_bytes];
                const keep = self.handleFrame(index, client, registry, header.kind, payload);
                if (!keep or self.clients[index] == null) break;
                const remaining = client.input_len - frame_bytes;
                std.mem.copyForwards(u8, client.input[0..remaining], client.input[frame_bytes..client.input_len]);
                client.input_len = remaining;
            }
        }
    }

    fn handleFrame(
        self: *Manager,
        index: usize,
        client: *Client,
        registry: *Registry,
        kind: protocol.Kind,
        payload: []const u8,
    ) bool {
        if (!client.welcomed) {
            if (kind != .hello or payload.len != protocol.payload_bytes.hello) {
                self.closeClient(index);
                return false;
            }
            client.welcomed = true;
            self.queueStatus(client, registry, .welcome) catch {
                self.closeClient(index);
                return false;
            };
            return true;
        }

        switch (kind) {
            .status => {
                if (payload.len != 0) return self.queueMalformed(index, client, kind, registry);
                self.queueStatus(client, registry, .status_snapshot) catch {
                    self.closeClient(index);
                    return false;
                };
            },
            .observe_roster => {
                const request = protocol.decodeObserveRoster(payload) catch
                    return self.queueMalformed(index, client, kind, registry);
                if (request.after_revision > registry.roster_revision)
                    return self.queueMalformed(index, client, kind, registry);
                if (request.after_revision == 0 or registry.roster_revision > request.after_revision) {
                    self.queueRoster(client, registry) catch {
                        self.closeClient(index);
                        return false;
                    };
                } else client.observe_after = request.after_revision;
            },
            .create => {
                if (self.stopping) return self.queueCode(index, client, kind, .stopping, 0, registry.roster_revision);
                const request = protocol.decodeCreate(payload) catch
                    return self.queueMalformed(index, client, kind, registry);
                const id = registry.create(request) catch |failure| {
                    const code: protocol.ResultCode = switch (failure) {
                        error.InvalidName => .malformed,
                        error.NameExists => .name_exists,
                        error.Capacity => .capacity,
                        else => .create_failed,
                    };
                    return self.queueCode(index, client, kind, code, 0, registry.roster_revision);
                };
                return self.queueCode(index, client, kind, .ok, id, registry.roster_revision);
            },
            .close => {
                if (self.stopping) return self.queueCode(index, client, kind, .stopping, 0, registry.roster_revision);
                const id = protocol.decodeSessionIdentity(payload) catch
                    return self.queueMalformed(index, client, kind, registry);
                const closed = registry.close(id);
                return self.queueCode(
                    index,
                    client,
                    kind,
                    if (closed) .ok else .not_found,
                    if (closed) id else 0,
                    registry.roster_revision,
                );
            },
            .attach => return self.queueCode(index, client, kind, .unsupported, 0, registry.roster_revision),
            .shutdown => {
                if (payload.len != 0) return self.queueMalformed(index, client, kind, registry);
                if (!self.stopping) {
                    self.stopping = true;
                    registry.noteManagerChange();
                }
                return self.queueCode(index, client, kind, .ok, 0, registry.roster_revision);
            },
            else => return self.queueCode(index, client, kind, .unsupported, 0, registry.roster_revision),
        }
        return true;
    }

    fn queueMalformed(
        self: *Manager,
        index: usize,
        client: *Client,
        kind: protocol.Kind,
        registry: *const Registry,
    ) bool {
        return self.queueCode(index, client, kind, .malformed, 0, registry.roster_revision);
    }

    fn queueCode(
        self: *Manager,
        index: usize,
        client: *Client,
        kind: protocol.Kind,
        code: protocol.ResultCode,
        session_id: u64,
        revision: u64,
    ) bool {
        var payload: [protocol.payload_bytes.result]u8 = undefined;
        protocol.encodeResult(&payload, .{
            .request_kind = kind,
            .code = code,
            .session_id = session_id,
            .roster_revision = revision,
        }) catch {
            self.closeClient(index);
            return false;
        };
        queueFrame(client, .result, &payload) catch {
            self.closeClient(index);
            return false;
        };
        return true;
    }

    fn queueStatus(self: *Manager, client: *Client, registry: *const Registry, kind: protocol.Kind) !void {
        var payload: [protocol.payload_bytes.status_snapshot]u8 = undefined;
        protocol.encodeServerStatus(&payload, .{
            .server_id = registry.server_id,
            .roster_revision = registry.roster_revision,
            .pid = @intCast(linux.getpid()),
            .session_count = registry.count,
            .capacity = protocol.maximum_sessions,
            .stopping = self.stopping,
        });
        try queueFrame(client, kind, &payload);
    }

    fn queueRoster(self: *Manager, client: *Client, registry: *const Registry) !void {
        var payload: [protocol.maximum_payload_bytes]u8 = undefined;
        const encoded = try registry.rosterPayload(self.stopping, &payload);
        try queueFrame(client, .roster_snapshot, encoded);
        client.observe_after = null;
    }

    fn queueFrame(client: *Client, kind: protocol.Kind, payload: []const u8) !void {
        if (client.outputPending() or payload.len > protocol.maximum_payload_bytes)
            return error.OutputBusy;
        const total = protocol.header_bytes + payload.len;
        if (total > client.output.len) return error.OutputTooSmall;
        var header: [protocol.header_bytes]u8 = undefined;
        try protocol.encodeHeader(&header, .{ .kind = kind, .payload_len = @intCast(payload.len) });
        @memcpy(client.output[0..protocol.header_bytes], &header);
        @memcpy(client.output[protocol.header_bytes..total], payload);
        client.output_len = total;
        client.output_offset = 0;
    }

    fn materializeRosterObservers(self: *Manager, registry: *const Registry) void {
        for (&self.clients, 0..) |*maybe_client, index| {
            const client = if (maybe_client.*) |*value| value else continue;
            const after = client.observe_after orelse continue;
            if (registry.roster_revision <= after or client.outputPending()) continue;
            self.queueRoster(client, registry) catch {
                self.closeClient(index);
                continue;
            };
        }
    }
};

const TcpListener = struct {
    fd: posix.fd_t,
    port: u16,
};

fn listenTcpLoopback(requested_port: u16) !TcpListener {
    const raw = linux.socket(linux.AF.INET, linux.SOCK.STREAM | linux.SOCK.CLOEXEC | linux.SOCK.NONBLOCK, 0);
    if (linux.errno(raw) != .SUCCESS) return error.SocketCreateFailed;
    const fd: posix.fd_t = @intCast(raw);
    errdefer closeFd(fd);
    const enabled: c_int = 1;
    if (linux.errno(linux.setsockopt(
        fd,
        linux.SOL.SOCKET,
        linux.SO.REUSEADDR,
        @ptrCast(&enabled),
        @sizeOf(c_int),
    )) != .SUCCESS) return error.SocketOptionFailed;
    var address = ipv4Loopback(requested_port);
    if (linux.errno(linux.bind(fd, @ptrCast(&address), @sizeOf(linux.sockaddr.in))) != .SUCCESS)
        return error.SocketBindFailed;
    if (linux.errno(linux.listen(fd, listen_backlog)) != .SUCCESS) return error.SocketListenFailed;
    var bound: linux.sockaddr.in = undefined;
    var length: linux.socklen_t = @sizeOf(linux.sockaddr.in);
    if (linux.errno(linux.getsockname(fd, @ptrCast(&bound), &length)) != .SUCCESS or
        length != @sizeOf(linux.sockaddr.in))
        return error.SocketNameFailed;
    const port = std.mem.bigToNative(u16, bound.port);
    if (port == 0 or bound.addr != ipv4Loopback(0).addr) return error.SocketNameFailed;
    return .{ .fd = fd, .port = port };
}

fn listenUnix(path: []const u8) !posix.fd_t {
    var address: linux.sockaddr.un = undefined;
    const length = try unixAddress(path, &address);
    const raw = linux.socket(linux.AF.UNIX, linux.SOCK.STREAM | linux.SOCK.CLOEXEC | linux.SOCK.NONBLOCK, 0);
    if (linux.errno(raw) != .SUCCESS) return error.SocketCreateFailed;
    const fd: posix.fd_t = @intCast(raw);
    errdefer closeFd(fd);
    if (linux.errno(linux.bind(fd, @ptrCast(&address), length)) != .SUCCESS) return error.SocketBindFailed;
    var path_buffer: [108]u8 = @splat(0);
    @memcpy(path_buffer[0..path.len], path);
    if (linux.errno(linux.chmod(@ptrCast(&path_buffer), 0o600)) != .SUCCESS) return error.SocketModeFailed;
    if (linux.errno(linux.listen(fd, listen_backlog)) != .SUCCESS) return error.SocketListenFailed;
    return fd;
}

fn unixAddress(path: []const u8, address: *linux.sockaddr.un) error{SocketPathTooLong}!linux.socklen_t {
    if (path.len == 0 or path.len >= address.path.len) return error.SocketPathTooLong;
    address.family = linux.AF.UNIX;
    @memset(&address.path, 0);
    @memcpy(address.path[0..path.len], path);
    return @intCast(@offsetOf(linux.sockaddr.un, "path") + path.len + 1);
}

fn ipv4Loopback(port: u16) linux.sockaddr.in {
    return .{
        .family = linux.AF.INET,
        .port = std.mem.nativeToBig(u16, port),
        .addr = std.mem.nativeToBig(u32, 0x7f000001),
        .zero = @splat(0),
    };
}

fn setTcpNoDelay(fd: posix.fd_t) !void {
    const enabled: c_int = 1;
    if (linux.errno(linux.setsockopt(
        fd,
        linux.IPPROTO.TCP,
        linux.TCP.NODELAY,
        @ptrCast(&enabled),
        @sizeOf(c_int),
    )) != .SUCCESS) return error.SocketOptionFailed;
}

fn unlinkPath(path: []const u8) void {
    var buffer: [108]u8 = @splat(0);
    if (path.len >= buffer.len) return;
    @memcpy(buffer[0..path.len], path);
    const result = linux.unlink(@ptrCast(&buffer));
    switch (linux.errno(result)) {
        .SUCCESS, .NOENT => {},
        else => {},
    }
}

fn closeFd(fd: posix.fd_t) void {
    const result = linux.close(@intCast(fd));
    switch (linux.errno(result)) {
        .SUCCESS, .INTR => {},
        else => {},
    }
}

test "manager listener is loopback only and reports resolved TCP port" {
    var manager = try Manager.init(std.testing.allocator, std.testing.io, .{ .tcp_loopback = 0 });
    defer manager.deinit();
    var endpoint_buffer: [64]u8 = undefined;
    const text = try manager.endpointText(&endpoint_buffer);
    try std.testing.expect(std.mem.startsWith(u8, text, "tcp://127.0.0.1:"));
}

const TestPeer = struct {
    fd: posix.fd_t,

    fn connectUnix(path: []const u8) !TestPeer {
        var address: linux.sockaddr.un = undefined;
        const length = try unixAddress(path, &address);
        const raw = linux.socket(linux.AF.UNIX, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, 0);
        if (linux.errno(raw) != .SUCCESS) return error.TestSocketCreateFailed;
        const fd: posix.fd_t = @intCast(raw);
        errdefer closeFd(fd);
        while (true) {
            const result = linux.connect(fd, @ptrCast(&address), length);
            switch (linux.errno(result)) {
                .SUCCESS => break,
                .INTR => continue,
                else => return error.TestSocketConnectFailed,
            }
        }
        return .{ .fd = fd };
    }

    fn deinit(self: *TestPeer) void {
        closeFd(self.fd);
        self.* = undefined;
    }

    fn send(self: *TestPeer, kind: protocol.Kind, payload: []const u8) !void {
        var header: [protocol.header_bytes]u8 = undefined;
        try protocol.encodeHeader(&header, .{ .kind = kind, .payload_len = @intCast(payload.len) });
        try testWriteAll(self.fd, &header);
        try testWriteAll(self.fd, payload);
    }

    fn receive(self: *TestPeer) !TestFrame {
        var header_bytes: [protocol.header_bytes]u8 = undefined;
        try testReadExact(self.fd, &header_bytes);
        const header = try protocol.decodeHeader(&header_bytes);
        var frame = TestFrame{ .kind = header.kind };
        frame.payload_len = @intCast(header.payload_len);
        try testReadExact(self.fd, frame.payload[0..frame.payload_len]);
        return frame;
    }
};

const TestFrame = struct {
    kind: protocol.Kind,
    payload: [protocol.maximum_payload_bytes]u8 = undefined,
    payload_len: usize = 0,

    fn body(self: *const TestFrame) []const u8 {
        return self.payload[0..self.payload_len];
    }
};

fn testWriteAll(fd: posix.fd_t, bytes: []const u8) !void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        const result = linux.write(fd, bytes[offset..].ptr, bytes.len - offset);
        switch (linux.errno(result)) {
            .SUCCESS => {
                if (result == 0 or result > bytes.len - offset) return error.TestSocketWriteFailed;
                offset += result;
            },
            .INTR => continue,
            else => return error.TestSocketWriteFailed,
        }
    }
}

fn testReadExact(fd: posix.fd_t, output: []u8) !void {
    var offset: usize = 0;
    while (offset < output.len) {
        const result = linux.read(fd, output[offset..].ptr, output.len - offset);
        switch (linux.errno(result)) {
            .SUCCESS => {
                if (result == 0 or result > output.len - offset) return error.TestSocketReadFailed;
                offset += result;
            },
            .INTR => continue,
            else => return error.TestSocketReadFailed,
        }
    }
}

fn pump(manager: *Manager, registry: *Registry, turns: usize) !void {
    for (0..turns) |_| try manager.turn(registry, 0);
}

test "HWLM manages a live zero-session registry with revisioned roster wakeup" {
    var runtime_buffer: [96]u8 = undefined;
    const runtime = try std.fmt.bufPrint(
        &runtime_buffer,
        "/tmp/howl-manager-{d}",
        .{linux.getpid()},
    );
    std.Io.Dir.createDirPath(.cwd(), std.testing.io, runtime) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, runtime) catch {};
    var socket_buffer: [108]u8 = undefined;
    const manager_socket = try std.fmt.bufPrint(&socket_buffer, "{s}/manager.sock", .{runtime});

    var registry = try Registry.init(
        std.testing.allocator,
        std.testing.io,
        std.testing.environ,
        runtime,
        .{ .shell = "/bin/sh", .rows = 4, .columns = 40 },
        0xfeed_beef,
    );
    defer registry.deinit();
    var manager = try Manager.init(std.testing.allocator, std.testing.io, .{ .unix = manager_socket });
    defer manager.deinit();

    var observer = try TestPeer.connectUnix(manager_socket);
    defer observer.deinit();
    try observer.send(.hello, &.{});
    try pump(&manager, &registry, 3);
    const welcome = try observer.receive();
    try std.testing.expectEqual(protocol.Kind.welcome, welcome.kind);
    const initial = try protocol.decodeServerStatus(welcome.body());
    try std.testing.expectEqual(@as(u16, 0), initial.session_count);
    try std.testing.expectEqual(@as(u64, 1), initial.roster_revision);

    var observe_bytes: [protocol.payload_bytes.observe_roster]u8 = undefined;
    protocol.encodeObserveRoster(&observe_bytes, .{ .after_revision = 0 });
    try observer.send(.observe_roster, &observe_bytes);
    try pump(&manager, &registry, 2);
    const empty_roster = try observer.receive();
    try std.testing.expectEqual(protocol.Kind.roster_snapshot, empty_roster.kind);
    const empty_header = try protocol.decodeRosterHeader(
        empty_roster.body()[0..protocol.payload_bytes.roster_header],
    );
    try std.testing.expectEqual(@as(u16, 0), empty_header.session_count);

    var control = try TestPeer.connectUnix(manager_socket);
    defer control.deinit();
    try control.send(.hello, &.{});
    try pump(&manager, &registry, 3);
    const control_welcome = try control.receive();
    try std.testing.expectEqual(protocol.Kind.welcome, control_welcome.kind);

    var create_storage: [protocol.maximum_request_payload_bytes]u8 = undefined;
    const create_one = try protocol.encodeCreate(&create_storage, .{
        .name = "one",
        .command = "sleep 5",
    });
    try control.send(.create, create_one);
    try pump(&manager, &registry, 2);
    const created_one = try control.receive();
    try std.testing.expectEqual(protocol.Kind.result, created_one.kind);
    const first_result = try protocol.decodeResult(created_one.body());
    try std.testing.expectEqual(protocol.ResultCode.ok, first_result.code);
    try std.testing.expectEqual(@as(u64, 1), first_result.session_id);
    try std.testing.expectEqual(@as(u64, 2), first_result.roster_revision);

    protocol.encodeObserveRoster(&observe_bytes, .{ .after_revision = first_result.roster_revision });
    try observer.send(.observe_roster, &observe_bytes);
    try pump(&manager, &registry, 2);

    const create_two = try protocol.encodeCreate(&create_storage, .{
        .name = "two",
        .command = "sleep 5",
    });
    try control.send(.create, create_two);
    try pump(&manager, &registry, 3);
    const created_two = try control.receive();
    const second_result = try protocol.decodeResult(created_two.body());
    try std.testing.expectEqual(protocol.ResultCode.ok, second_result.code);
    try std.testing.expectEqual(@as(u64, 2), second_result.session_id);

    const changed_roster = try observer.receive();
    const changed_header = try protocol.decodeRosterHeader(
        changed_roster.body()[0..protocol.payload_bytes.roster_header],
    );
    try std.testing.expectEqual(@as(u16, 2), changed_header.session_count);
    try std.testing.expectEqual(second_result.roster_revision, changed_header.roster_revision);
    var roster_offset: usize = protocol.payload_bytes.roster_header;
    const first_record = try protocol.decodeRosterRecord(changed_roster.body()[roster_offset..]);
    roster_offset += first_record.encoded_bytes;
    const second_record = try protocol.decodeRosterRecord(changed_roster.body()[roster_offset..]);
    try std.testing.expectEqualStrings("one", first_record.record.name);
    try std.testing.expectEqualStrings("two", second_record.record.name);

    var identity: [protocol.payload_bytes.session_identity]u8 = undefined;
    try protocol.encodeSessionIdentity(&identity, first_result.session_id);
    try control.send(.close, &identity);
    try pump(&manager, &registry, 2);
    const closed = try control.receive();
    const close_result = try protocol.decodeResult(closed.body());
    try std.testing.expectEqual(protocol.ResultCode.ok, close_result.code);
    try std.testing.expectEqual(@as(u16, 1), registry.count);

    try control.send(.shutdown, &.{});
    try pump(&manager, &registry, 2);
    const shutdown = try control.receive();
    const shutdown_result = try protocol.decodeResult(shutdown.body());
    try std.testing.expectEqual(protocol.ResultCode.ok, shutdown_result.code);
    try std.testing.expect(manager.stopping);

    try control.send(.create, create_one);
    try pump(&manager, &registry, 2);
    const refused = try control.receive();
    const refused_result = try protocol.decodeResult(refused.body());
    try std.testing.expectEqual(protocol.ResultCode.stopping, refused_result.code);
}
