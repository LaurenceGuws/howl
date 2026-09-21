//! Optional orchestration owner: Server -> Sessions -> Instances.
//!
//! Server owns Session identity/lifetime only. Session creation never creates an
//! Instance; concrete terminal launch belongs to explicit Instance creation.

const std = @import("std");
const session_mod = @import("session.zig");
const howl_instance = @import("howl_instance");

pub const SessionId = u64;
pub const maximum_sessions: usize = 16;
pub const maximum_instances_per_session: usize = session_mod.maximum_instances;
pub const InstanceView = session_mod.InstanceView;

pub const SessionView = struct {
    id: SessionId,
    name: []const u8,
    instance_count: u16,
};

const SessionRecord = struct {
    value: session_mod.Session,

    fn deinit(self: *SessionRecord) void {
        self.value.deinit();
        self.* = undefined;
    }
};

pub const CreateSessionError = std.mem.Allocator.Error || error{
    InvalidName,
    NameExists,
    Capacity,
    IdentityExhausted,
};

pub const Server = struct {
    allocator: std.mem.Allocator,
    id: u64,
    next_session_id: SessionId = 1,
    revision: u64 = 1,
    sessions: [maximum_sessions]?SessionRecord = @splat(null),
    count: u16 = 0,

    pub fn init(allocator: std.mem.Allocator, id: u64) error{InvalidServerIdentity}!Server {
        if (id == 0) return error.InvalidServerIdentity;
        return .{ .allocator = allocator, .id = id };
    }

    pub fn deinit(self: *Server) void {
        var index = self.sessions.len;
        while (index != 0) {
            index -= 1;
            if (self.sessions[index]) |*record| {
                record.deinit();
                self.sessions[index] = null;
            }
        }
        self.count = 0;
    }

    pub fn sessionCount(self: *const Server) u16 {
        return self.count;
    }

    pub fn treeRevision(self: *const Server) u64 {
        return self.revision;
    }

    pub fn instanceCountTotal(self: *const Server) u16 {
        var total: u16 = 0;
        for (self.sessions) |maybe_record| {
            const record = maybe_record orelse continue;
            total += record.value.instanceCount();
        }
        return total;
    }

    /// Borrows Session names until the next Server mutation; scalar fields are copied.
    pub fn snapshotSessions(self: *const Server, output: *[maximum_sessions]SessionView) []const SessionView {
        var count: usize = 0;
        for (self.sessions) |maybe_record| {
            const record = maybe_record orelse continue;
            var insert = count;
            while (insert != 0 and output[insert - 1].id > record.value.id) : (insert -= 1)
                output[insert] = output[insert - 1];
            output[insert] = .{
                .id = record.value.id,
                .name = record.value.name,
                .instance_count = record.value.instanceCount(),
            };
            count += 1;
        }
        std.debug.assert(count == self.count);
        return output[0..count];
    }

    pub fn snapshotInstances(
        self: *const Server,
        session_id: SessionId,
        output: *[session_mod.maximum_instances]session_mod.InstanceView,
    ) ?[]const session_mod.InstanceView {
        const index = self.findSessionIndex(session_id) orelse return null;
        return self.sessions[index].?.value.snapshotInstances(output);
    }

    pub fn createSession(self: *Server, name: []const u8) CreateSessionError!SessionId {
        if (name.len == 0 or name.len > 64) return error.InvalidName;
        if (self.findSessionByName(name) != null) return error.NameExists;
        if (self.count == self.sessions.len) return error.Capacity;
        if (self.next_session_id == 0) return error.IdentityExhausted;
        const slot = self.freeSlot() orelse unreachable;
        const id = self.next_session_id;
        var value = session_mod.Session.init(self.allocator, id, name) catch |failure| switch (failure) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidName => return error.InvalidName,
        };
        errdefer value.deinit();
        self.next_session_id = advanceIdentity(id) catch return error.IdentityExhausted;
        self.sessions[slot] = .{ .value = value };
        self.count += 1;
        self.bumpRevision();
        return id;
    }

    pub fn closeSession(self: *Server, id: SessionId) bool {
        const index = self.findSessionIndex(id) orelse return false;
        if (self.sessions[index]) |*record| record.deinit();
        self.sessions[index] = null;
        self.count -= 1;
        self.bumpRevision();
        return true;
    }

    pub const CreateInstanceError = session_mod.CreateInstanceError || error{SessionNotFound};

    pub fn createInstance(
        self: *Server,
        session_id: SessionId,
        io: std.Io,
        inherited_environment: std.process.Environ,
        launch: howl_instance.Launch,
    ) CreateInstanceError!session_mod.InstanceId {
        const index = self.findSessionIndex(session_id) orelse return error.SessionNotFound;
        const instance_id = try self.sessions[index].?.value.createInstance(io, inherited_environment, launch);
        self.bumpRevision();
        return instance_id;
    }

    pub fn closeInstance(self: *Server, session_id: SessionId, instance_id: session_mod.InstanceId) bool {
        const index = self.findSessionIndex(session_id) orelse return false;
        const closed = self.sessions[index].?.value.closeInstance(instance_id);
        if (closed) self.bumpRevision();
        return closed;
    }

    pub fn instanceCount(self: *const Server, session_id: SessionId) ?u16 {
        const index = self.findSessionIndex(session_id) orelse return null;
        return self.sessions[index].?.value.instanceCount();
    }

    pub fn instanceState(self: *const Server, session_id: SessionId, instance_id: session_mod.InstanceId) ?session_mod.InstanceState {
        const index = self.findSessionIndex(session_id) orelse return null;
        return self.sessions[index].?.value.instanceState(instance_id);
    }

    pub const AdoptClientError = session_mod.Session.AdoptClientError || error{SessionNotFound};

    pub fn adoptClient(
        self: *Server,
        session_id: SessionId,
        instance_id: session_mod.InstanceId,
        fd: std.posix.fd_t,
        initial_input: []const u8,
        preface_output: []const u8,
    ) AdoptClientError!void {
        const index = self.findSessionIndex(session_id) orelse return error.SessionNotFound;
        return self.sessions[index].?.value.adoptClient(instance_id, fd, initial_input, preface_output);
    }

    pub const TurnInstanceError = session_mod.Session.TurnInstanceError || error{SessionNotFound};

    pub fn turnInstance(
        self: *Server,
        session_id: SessionId,
        instance_id: session_mod.InstanceId,
        timeout_ms: i32,
    ) TurnInstanceError!void {
        const index = self.findSessionIndex(session_id) orelse return error.SessionNotFound;
        const outcome = try self.sessions[index].?.value.turnInstance(instance_id, timeout_ms);
        if (outcome.state_changed) self.bumpRevision();
    }

    pub fn findSessionByName(self: *const Server, name: []const u8) ?SessionId {
        for (self.sessions) |maybe_record| {
            const record = maybe_record orelse continue;
            if (std.mem.eql(u8, record.value.name, name)) return record.value.id;
        }
        return null;
    }

    fn bumpRevision(self: *Server) void {
        self.revision +%= 1;
        if (self.revision == 0) self.revision = 1;
    }

    fn freeSlot(self: *const Server) ?usize {
        for (self.sessions, 0..) |record, index| if (record == null) return index;
        return null;
    }

    fn findSessionIndex(self: *const Server, id: SessionId) ?usize {
        for (self.sessions, 0..) |maybe_record, index| {
            const record = maybe_record orelse continue;
            if (record.value.id == id) return index;
        }
        return null;
    }
};

test "Server identity is explicit and nonzero" {
    try std.testing.expectError(error.InvalidServerIdentity, Server.init(std.testing.allocator, 0));
    var server = try Server.init(std.testing.allocator, 99);
    defer server.deinit();
    try std.testing.expectEqual(@as(u64, 99), server.id);
}

test "Server observations are sorted after slot reuse and expose no mutable Session" {
    var server = try Server.init(std.testing.allocator, 42);
    defer server.deinit();
    const first = try server.createSession("first");
    const second = try server.createSession("second");
    try std.testing.expect(server.closeSession(first));
    const third = try server.createSession("third");
    try std.testing.expect(third > second);

    var sessions_storage: [maximum_sessions]SessionView = undefined;
    const sessions = server.snapshotSessions(&sessions_storage);
    try std.testing.expectEqual(@as(usize, 2), sessions.len);
    try std.testing.expectEqual(second, sessions[0].id);
    try std.testing.expectEqual(third, sessions[1].id);
    try std.testing.expectEqualStrings("second", sessions[0].name);
    try std.testing.expectEqualStrings("third", sessions[1].name);
}

test "Server routes Instance creation through the selected Session" {
    var server = try Server.init(std.testing.allocator, 41);
    defer server.deinit();
    const work = try server.createSession("work");
    const other = try server.createSession("other");
    const instance_id = try server.createInstance(work, std.testing.io, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "exit 0",
        .rows = 4,
        .columns = 12,
    });
    try std.testing.expectEqual(@as(session_mod.InstanceId, 1), instance_id);
    try std.testing.expectEqual(@as(u16, 1), server.instanceCount(work).?);
    try std.testing.expectEqual(@as(u16, 0), server.instanceCount(other).?);
    try std.testing.expect(server.closeInstance(work, instance_id));
    try std.testing.expectEqual(@as(u16, 0), server.instanceCount(work).?);
    try std.testing.expectEqual(work, server.findSessionByName("work").?);
}

fn advanceIdentity(current: u64) error{IdentityExhausted}!u64 {
    if (current == std.math.maxInt(u64)) return error.IdentityExhausted;
    const next = current + 1;
    if (next == 0) return error.IdentityExhausted;
    return next;
}

test "Server creates empty Sessions without constructing Instances" {
    var server = try Server.init(std.testing.allocator, 41);
    defer server.deinit();

    const work = try server.createSession("work");
    try std.testing.expectEqual(@as(SessionId, 1), work);
    try std.testing.expectEqual(@as(u16, 1), server.sessionCount());
    try std.testing.expectEqual(@as(u16, 0), server.instanceCount(work).?);
}

test "Session identity survives Instance-independent CRUD" {
    var server = try Server.init(std.testing.allocator, 41);
    defer server.deinit();
    const first = try server.createSession("first");
    const second = try server.createSession("second");
    try std.testing.expect(first != second);
    try std.testing.expect(server.closeSession(first));
    try std.testing.expectEqual(second, server.findSessionByName("second").?);
    try std.testing.expectEqual(@as(u16, 1), server.sessionCount());
}

fn testSetNonblocking(fd: std.posix.fd_t) !void {
    const linux = std.os.linux;
    const current = linux.fcntl(fd, linux.F.GETFL, @as(usize, 0));
    if (linux.errno(current) != .SUCCESS) return error.TestSocketConfigureFailed;
    const nonblocking: usize = @intCast(@as(u32, @bitCast(linux.O{ .NONBLOCK = true })));
    const updated = linux.fcntl(fd, linux.F.SETFL, @as(usize, @intCast(current)) | nonblocking);
    if (linux.errno(updated) != .SUCCESS) return error.TestSocketConfigureFailed;
}

fn testCloseFd(fd: std.posix.fd_t) void {
    const linux = std.os.linux;
    const result = linux.close(fd);
    const errno = linux.errno(result);
    std.debug.assert(errno == .SUCCESS or errno == .INTR);
}

fn testReadExact(
    server: *Server,
    session_id: SessionId,
    instance_id: session_mod.InstanceId,
    fd: std.posix.fd_t,
    output: []u8,
) !void {
    const linux = std.os.linux;
    var offset: usize = 0;
    var turns: usize = 0;
    while (offset < output.len and turns < 10_000) : (turns += 1) {
        const result = linux.read(fd, output[offset..].ptr, output.len - offset);
        switch (linux.errno(result)) {
            .SUCCESS => {
                if (result == 0 or result > output.len - offset) return error.TestSocketReadFailed;
                offset += result;
            },
            .INTR => continue,
            .AGAIN => try server.turnInstance(session_id, instance_id, 1),
            else => return error.TestSocketReadFailed,
        }
    }
    if (offset != output.len) return error.TestTimeout;
}

test "Server routes an adopted HWLS stream by exact Session and Instance identity" {
    const protocol = howl_instance.protocol;
    var server = try Server.init(std.testing.allocator, 41);
    defer server.deinit();
    const work = try server.createSession("work");
    const instance_id = try server.createInstance(work, std.testing.io, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "cat",
        .rows = 4,
        .columns = 20,
    });

    var pair: [2]std.posix.fd_t = undefined;
    const socket_result = std.posix.system.socketpair(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0, &pair);
    try std.testing.expectEqual(std.posix.E.SUCCESS, std.posix.errno(socket_result));
    var service_owns = false;
    defer if (!service_owns) testCloseFd(pair[0]);
    defer testCloseFd(pair[1]);
    try testSetNonblocking(pair[1]);

    var hello: [protocol.header_bytes]u8 = undefined;
    try protocol.encodeHeader(&hello, .{ .kind = .hello, .payload_len = 0 });
    try server.adoptClient(work, instance_id, pair[0], &hello, &.{});
    service_owns = true;

    var header_bytes: [protocol.header_bytes]u8 = undefined;
    try testReadExact(&server, work, instance_id, pair[1], &header_bytes);
    const header = try protocol.decodeHeader(&header_bytes);
    try std.testing.expectEqual(protocol.Kind.welcome, header.kind);
    try std.testing.expectEqual(@as(u32, protocol.payload_bytes.welcome), header.payload_len);
    var welcome_bytes: [protocol.payload_bytes.welcome]u8 = undefined;
    try testReadExact(&server, work, instance_id, pair[1], &welcome_bytes);
    const welcome = try protocol.decodeWelcome(&welcome_bytes);
    try std.testing.expect(welcome.client_id != protocol.no_client);
}

test "identity routing failure retains caller stream ownership" {
    const linux = std.os.linux;
    var server = try Server.init(std.testing.allocator, 41);
    defer server.deinit();
    const work = try server.createSession("work");
    const instance_id = try server.createInstance(work, std.testing.io, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "cat",
        .rows = 2,
        .columns = 8,
    });

    var pair: [2]std.posix.fd_t = undefined;
    const socket_result = std.posix.system.socketpair(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0, &pair);
    try std.testing.expectEqual(std.posix.E.SUCCESS, std.posix.errno(socket_result));
    defer testCloseFd(pair[0]);
    defer testCloseFd(pair[1]);

    try std.testing.expectError(
        error.SessionNotFound,
        server.adoptClient(work + 100, instance_id, pair[0], &.{}, &.{}),
    );
    const session_flags = linux.fcntl(pair[0], linux.F.GETFD, @as(usize, 0));
    try std.testing.expectEqual(linux.E.SUCCESS, linux.errno(session_flags));

    try std.testing.expectError(
        error.InstanceNotFound,
        server.adoptClient(work, instance_id + 100, pair[0], &.{}, &.{}),
    );
    const instance_flags = linux.fcntl(pair[0], linux.F.GETFD, @as(usize, 0));
    try std.testing.expectEqual(linux.E.SUCCESS, linux.errno(instance_flags));
}

test "Instance exit advances tree revision without ending its Session" {
    var server = try Server.init(std.testing.allocator, 41);
    defer server.deinit();
    try std.testing.expectEqual(@as(u64, 1), server.treeRevision());

    const work = try server.createSession("work");
    try std.testing.expectEqual(@as(u64, 2), server.treeRevision());
    const instance_id = try server.createInstance(work, std.testing.io, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "exit 0",
        .rows = 2,
        .columns = 8,
    });
    try std.testing.expectEqual(@as(u64, 3), server.treeRevision());
    try std.testing.expectEqual(session_mod.InstanceState.running, server.instanceState(work, instance_id).?);

    var turns: usize = 0;
    while (turns < 10_000 and server.instanceState(work, instance_id).? == .running) : (turns += 1)
        try server.turnInstance(work, instance_id, 1);
    try std.testing.expectEqual(session_mod.InstanceState.exited, server.instanceState(work, instance_id).?);
    try std.testing.expectEqual(@as(u64, 4), server.treeRevision());
    try std.testing.expectEqual(work, server.findSessionByName("work").?);
    try std.testing.expectEqual(@as(u16, 1), server.sessionCount());
    try std.testing.expectEqual(@as(u16, 1), server.instanceCount(work).?);

    try server.turnInstance(work, instance_id, 0);
    try std.testing.expectEqual(@as(u64, 4), server.treeRevision());
}
