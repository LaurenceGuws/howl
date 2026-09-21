//! Foreground Server runtime: one listener, one Server tree, many Instances.
//!
//! Runtime owns listener/scheduling only. Server owns orchestration state; Session
//! remains lifecycle identity/labeling; each Instance owns its own PTY/VT geometry
//! and HWLS interaction service. Runtime owns no terminal grid or client layout.

const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;
const model = @import("server_model");
const control = @import("server_service");

const maximum_accepts_per_turn: usize = 16;
pub const scheduler_wait_ms: i32 = 20;
const idle_wait_ms: i32 = 1000;

pub const ListenerSpec = union(enum) {
    unix: []const u8,
    tcp_loopback: u16,
};

pub const ParseError = error{InvalidListener};

pub fn parseListener(text: []const u8) ParseError!ListenerSpec {
    if (std.mem.startsWith(u8, text, "unix:")) {
        const path = text["unix:".len..];
        if (path.len < 2 or path[0] != '/') return error.InvalidListener;
        return .{ .unix = path };
    }
    if (std.mem.startsWith(u8, text, "tcp:")) {
        const port_text = text["tcp:".len..];
        if (port_text.len == 0) return error.InvalidListener;
        const port = std.fmt.parseInt(u16, port_text, 10) catch return error.InvalidListener;
        return .{ .tcp_loopback = port };
    }
    return error.InvalidListener;
}

pub fn freshServerId(io: std.Io) u64 {
    while (true) {
        var bytes: [8]u8 = undefined;
        std.Io.random(io, &bytes);
        const value = std.mem.readInt(u64, &bytes, .little);
        if (value != 0) return value;
    }
}

const Listener = struct {
    fd: posix.fd_t,
    unix_path: [108]u8 = @splat(0),
    unix_path_len: u8 = 0,
    tcp_port: ?u16 = null,

    fn init(io: std.Io, spec: ListenerSpec) !Listener {
        return switch (spec) {
            .unix => |path| blk: {
                if (path.len == 0 or path.len >= 108) return error.SocketPathTooLong;
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

pub const Runtime = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    listener: Listener,
    server: *model.Server,
    service: control.Service,
    wait_cursor: usize = 0,

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        inherited_environment: std.process.Environ,
        listener_spec: ListenerSpec,
        server_id: u64,
    ) !Runtime {
        const server = try allocator.create(model.Server);
        errdefer allocator.destroy(server);
        server.* = try model.Server.init(allocator, server_id);
        errdefer server.deinit();
        var listener = try Listener.init(io, listener_spec);
        errdefer listener.deinit();
        return .{
            .allocator = allocator,
            .io = io,
            .listener = listener,
            .server = server,
            .service = control.Service.init(allocator, io, inherited_environment, server),
        };
    }

    pub fn initFresh(
        allocator: std.mem.Allocator,
        io: std.Io,
        inherited_environment: std.process.Environ,
        listener_spec: ListenerSpec,
    ) !Runtime {
        return init(allocator, io, inherited_environment, listener_spec, freshServerId(io));
    }

    pub fn deinit(self: *Runtime) void {
        self.service.deinit();
        self.listener.deinit();
        self.server.deinit();
        self.allocator.destroy(self.server);
        self.* = undefined;
    }

    pub fn serverId(self: *const Runtime) u64 {
        return self.server.id;
    }

    pub fn endpointText(self: *const Runtime, output: []u8) ![]const u8 {
        return self.listener.endpointText(output);
    }

    /// One bounded cooperative turn. Dormant running Instances sleep in one
    /// aggregate listener+PTY poll; only clients/timers/writes receive direct turns.
    pub fn turn(self: *Runtime) !void {
        self.acceptClients();
        try self.serviceDormantReadiness(0);

        if (self.service.clientCount() != 0) try self.service.turn(0);
        try self.turnActiveInstances(0);

        const control_active = self.service.clientCount() != 0;
        const instance_count: usize = self.server.turnInstanceCount();
        const owner_count = instance_count + @intFromBool(control_active);
        if (owner_count == 0) {
            try self.serviceDormantReadiness(idle_wait_ms);
            return;
        }

        const target = self.wait_cursor % owner_count;
        self.wait_cursor = (target + 1) % owner_count;
        if (control_active and target == 0) {
            try self.service.turn(scheduler_wait_ms);
        } else {
            const instance_target = target - @intFromBool(control_active);
            try self.turnNthActiveInstance(instance_target, scheduler_wait_ms);
        }
    }

    pub fn run(self: *Runtime) !void {
        while (true) try self.turn();
    }

    const DormantOwner = struct {
        session_id: model.SessionId,
        instance_id: u64,
    };

    fn serviceDormantReadiness(self: *Runtime, timeout_ms: i32) !void {
        const maximum_dormant = model.maximum_sessions * model.maximum_instances_per_session;
        var descriptors: [1 + maximum_dormant]posix.pollfd = undefined;
        var owners: [maximum_dormant]DormantOwner = undefined;
        var descriptor_count: usize = 1;
        var owner_count: usize = 0;

        descriptors[0] = .{
            .fd = self.listener.fd,
            .events = posix.POLL.IN | posix.POLL.HUP | posix.POLL.ERR,
            .revents = 0,
        };

        var sessions_storage: [model.maximum_sessions]model.SessionView = undefined;
        const sessions = self.server.snapshotSessions(&sessions_storage);
        for (sessions) |session| {
            var instances_storage: [model.maximum_instances_per_session]model.InstanceView = undefined;
            const instances = self.server.snapshotInstances(session.id, &instances_storage) orelse continue;
            for (instances) |instance| {
                const fd = try self.server.instanceWaitDescriptor(session.id, instance.id) orelse continue;
                std.debug.assert(owner_count < owners.len);
                std.debug.assert(descriptor_count < descriptors.len);
                owners[owner_count] = .{
                    .session_id = session.id,
                    .instance_id = instance.id,
                };
                descriptors[descriptor_count] = .{
                    .fd = fd,
                    .events = posix.POLL.IN | posix.POLL.HUP | posix.POLL.ERR,
                    .revents = 0,
                };
                owner_count += 1;
                descriptor_count += 1;
            }
        }

        const ready = try posix.poll(descriptors[0..descriptor_count], timeout_ms);
        std.debug.assert(ready <= descriptor_count);
        if (descriptors[0].revents & posix.POLL.NVAL != 0) unreachable;
        if (descriptors[0].revents & posix.POLL.IN != 0) self.acceptClients();

        for (owners[0..owner_count], 0..) |owner, index| {
            const events = descriptors[1 + index].revents;
            if (events == 0) continue;
            std.debug.assert(events & posix.POLL.NVAL == 0);
            try self.server.turnInstance(owner.session_id, owner.instance_id, 0);
        }
    }

    fn acceptClients(self: *Runtime) void {
        var accepted_count: usize = 0;
        while (accepted_count < maximum_accepts_per_turn) : (accepted_count += 1) {
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
            if (self.listener.tcp_port != null) setTcpNoDelay(fd) catch {
                closeFd(fd);
                continue;
            };
            self.service.adoptClient(fd, &.{}) catch {
                closeFd(fd);
                continue;
            };
        }
    }

    fn turnActiveInstances(self: *Runtime, timeout_ms: i32) !void {
        var sessions_storage: [model.maximum_sessions]model.SessionView = undefined;
        const sessions = self.server.snapshotSessions(&sessions_storage);
        for (sessions) |session| {
            var instances_storage: [model.maximum_instances_per_session]model.InstanceView = undefined;
            const instances = self.server.snapshotInstances(session.id, &instances_storage) orelse continue;
            for (instances) |instance| {
                if (self.server.instanceRequiresTurn(session.id, instance.id) != true) continue;
                try self.server.turnInstance(session.id, instance.id, timeout_ms);
            }
        }
    }

    fn turnNthActiveInstance(self: *Runtime, target: usize, timeout_ms: i32) !void {
        var seen: usize = 0;
        var sessions_storage: [model.maximum_sessions]model.SessionView = undefined;
        const sessions = self.server.snapshotSessions(&sessions_storage);
        for (sessions) |session| {
            var instances_storage: [model.maximum_instances_per_session]model.InstanceView = undefined;
            const instances = self.server.snapshotInstances(session.id, &instances_storage) orelse continue;
            for (instances) |instance| {
                if (self.server.instanceRequiresTurn(session.id, instance.id) != true) continue;
                if (seen == target) return self.server.turnInstance(session.id, instance.id, timeout_ms);
                seen += 1;
            }
        }
        std.debug.assert(seen <= target);
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
    if (linux.errno(linux.listen(fd, maximum_accepts_per_turn)) != .SUCCESS)
        return error.SocketListenFailed;

    var bound: linux.sockaddr.in = undefined;
    var length: linux.socklen_t = @sizeOf(linux.sockaddr.in);
    if (linux.errno(linux.getsockname(fd, @ptrCast(&bound), &length)) != .SUCCESS or
        length != @sizeOf(linux.sockaddr.in) or bound.family != linux.AF.INET)
        return error.SocketNameFailed;
    const expected = ipv4Loopback(0);
    if (bound.addr != expected.addr) return error.SocketNameFailed;
    const port = std.mem.bigToNative(u16, bound.port);
    if (port == 0) return error.SocketNameFailed;
    return .{ .fd = fd, .port = port };
}

fn listenUnix(path: []const u8) !posix.fd_t {
    const raw = linux.socket(linux.AF.UNIX, linux.SOCK.STREAM | linux.SOCK.CLOEXEC | linux.SOCK.NONBLOCK, 0);
    if (linux.errno(raw) != .SUCCESS) return error.SocketCreateFailed;
    const fd: posix.fd_t = @intCast(raw);
    errdefer closeFd(fd);

    var address: linux.sockaddr.un = undefined;
    const length = try unixAddress(path, &address);
    if (linux.errno(linux.bind(fd, @ptrCast(&address), length)) != .SUCCESS) return error.SocketBindFailed;
    var path_buffer: [109]u8 = @splat(0);
    @memcpy(path_buffer[0..path.len], path);
    if (linux.errno(linux.chmod(@ptrCast(&path_buffer), 0o600)) != .SUCCESS) return error.SocketModeFailed;
    if (linux.errno(linux.listen(fd, maximum_accepts_per_turn)) != .SUCCESS) return error.SocketListenFailed;
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
    const bytes = [4]u8{ 127, 0, 0, 1 };
    const address: *align(1) const u32 = @ptrCast(&bytes);
    return .{
        .port = std.mem.nativeToBig(u16, port),
        .addr = address.*,
    };
}

fn setTcpNoDelay(fd: posix.fd_t) !void {
    const enabled: c_int = 1;
    if (linux.errno(linux.setsockopt(
        fd,
        linux.IPPROTO.TCP,
        linux.TCP.NODELAY,
        std.mem.asBytes(&enabled).ptr,
        @sizeOf(c_int),
    )) != .SUCCESS) return error.SocketOptionFailed;
}

fn closeFd(fd: posix.fd_t) void {
    const result = linux.close(fd);
    const errno = linux.errno(result);
    std.debug.assert(errno == .SUCCESS or errno == .INTR);
}

fn unlinkPath(path: []const u8) void {
    if (path.len == 0 or path.len >= 108) return;
    var buffer: [109]u8 = @splat(0);
    @memcpy(buffer[0..path.len], path);
    const result = linux.unlink(@ptrCast(&buffer));
    const errno = linux.errno(result);
    std.debug.assert(errno == .SUCCESS or errno == .NOENT);
}

test "listener grammar has no terminal launch vocabulary" {
    try std.testing.expectEqualDeep(ListenerSpec{ .tcp_loopback = 0 }, try parseListener("tcp:0"));
    const unix = try parseListener("unix:/tmp/howl-server.sock");
    try std.testing.expectEqualStrings("/tmp/howl-server.sock", unix.unix);
    try std.testing.expectError(error.InvalidListener, parseListener("unix:relative.sock"));
    try std.testing.expectError(error.InvalidListener, parseListener("tcp:"));
    try std.testing.expectError(error.InvalidListener, parseListener("/tmp/howl.sock"));
}

test "runtime owns one TCP listener and reports its resolved endpoint" {
    var runtime = try Runtime.init(
        std.testing.allocator,
        std.testing.io,
        std.testing.environ,
        .{ .tcp_loopback = 0 },
        0x1234,
    );
    defer runtime.deinit();
    var endpoint_buffer: [64]u8 = undefined;
    const endpoint = try runtime.endpointText(&endpoint_buffer);
    try std.testing.expect(std.mem.startsWith(u8, endpoint, "tcp://127.0.0.1:"));
    try std.testing.expectEqual(@as(u64, 0x1234), runtime.serverId());
    try std.testing.expectEqual(@as(u16, 0), runtime.server.sessionCount());
}
