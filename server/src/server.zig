//! Optional orchestration owner: Server -> Sessions -> Instances.
//!
//! Server owns Session identity/lifetime only. Session creation never creates an
//! Instance; concrete terminal launch belongs to explicit Instance creation.

const std = @import("std");
const session_mod = @import("session.zig");
const howl_instance = @import("howl_instance");

pub const SessionId = u64;
pub const maximum_sessions: usize = 16;

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
    next_session_id: SessionId = 1,
    sessions: [maximum_sessions]?SessionRecord = @splat(null),
    count: u16 = 0,

    pub fn init(allocator: std.mem.Allocator) Server {
        return .{ .allocator = allocator };
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
        return id;
    }

    pub fn closeSession(self: *Server, id: SessionId) bool {
        const index = self.findSessionIndex(id) orelse return false;
        if (self.sessions[index]) |*record| record.deinit();
        self.sessions[index] = null;
        self.count -= 1;
        return true;
    }

    pub const CreateInstanceError = session_mod.CreateInstanceError || error{SessionNotFound};

    pub fn createInstance(
        self: *Server,
        session_id: SessionId,
        inherited_environment: std.process.Environ,
        launch: howl_instance.Launch,
    ) CreateInstanceError!session_mod.InstanceId {
        const index = self.findSessionIndex(session_id) orelse return error.SessionNotFound;
        return self.sessions[index].?.value.createInstance(inherited_environment, launch);
    }

    pub fn closeInstance(self: *Server, session_id: SessionId, instance_id: session_mod.InstanceId) bool {
        const index = self.findSessionIndex(session_id) orelse return false;
        return self.sessions[index].?.value.closeInstance(instance_id);
    }

    pub fn instanceCount(self: *const Server, session_id: SessionId) ?u16 {
        const index = self.findSessionIndex(session_id) orelse return null;
        return self.sessions[index].?.value.instanceCount();
    }

    pub fn findSessionByName(self: *const Server, name: []const u8) ?SessionId {
        for (self.sessions) |maybe_record| {
            const record = maybe_record orelse continue;
            if (std.mem.eql(u8, record.value.name, name)) return record.value.id;
        }
        return null;
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

test "Server routes Instance creation through the selected Session" {
    var server = Server.init(std.testing.allocator);
    defer server.deinit();
    const work = try server.createSession("work");
    const other = try server.createSession("other");
    const instance_id = try server.createInstance(work, std.testing.environ, .{
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
    var server = Server.init(std.testing.allocator);
    defer server.deinit();

    const work = try server.createSession("work");
    try std.testing.expectEqual(@as(SessionId, 1), work);
    try std.testing.expectEqual(@as(u16, 1), server.sessionCount());
    try std.testing.expectEqual(@as(u16, 0), server.instanceCount(work).?);
}

test "Session identity survives Instance-independent CRUD" {
    var server = Server.init(std.testing.allocator);
    defer server.deinit();
    const first = try server.createSession("first");
    const second = try server.createSession("second");
    try std.testing.expect(first != second);
    try std.testing.expect(server.closeSession(first));
    try std.testing.expectEqual(second, server.findSessionByName("second").?);
    try std.testing.expectEqual(@as(u16, 1), server.sessionCount());
}
