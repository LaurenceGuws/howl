//! One orchestration Session containing zero or more concrete terminal Instances.
//!
//! Session identity survives individual Instance exit/removal. Launch policy belongs
//! to Instance creation; Session itself knows no shell, command, cwd or geometry.

const std = @import("std");
const howl_instance = @import("howl_instance");
const instance_service = @import("howl_instance_service");

pub const InstanceId = u64;
pub const maximum_instances: usize = 16;

pub const InstanceState = enum { running, exited };

pub const TurnOutcome = struct { state_changed: bool = false };

const InstanceRecord = struct {
    id: InstanceId,
    value: *howl_instance.Instance,
    service: instance_service.Service,
    state: InstanceState = .running,

    fn deinit(self: *InstanceRecord) void {
        self.service.deinit();
        howl_instance.deinit(self.value);
        self.* = undefined;
    }
};

pub const CreateInstanceError = std.mem.Allocator.Error || howl_instance.InitError || instance_service.Service.InitError || error{
    Capacity,
    IdentityExhausted,
};

pub const Session = struct {
    allocator: std.mem.Allocator,
    id: u64,
    name: []u8,
    next_instance_id: InstanceId = 1,
    instances: [maximum_instances]?InstanceRecord = @splat(null),
    count: u16 = 0,

    pub fn init(allocator: std.mem.Allocator, id: u64, name: []const u8) !Session {
        std.debug.assert(id != 0);
        if (name.len == 0) return error.InvalidName;
        return .{
            .allocator = allocator,
            .id = id,
            .name = try allocator.dupe(u8, name),
        };
    }

    pub fn deinit(self: *Session) void {
        var index = self.instances.len;
        while (index != 0) {
            index -= 1;
            if (self.instances[index]) |*record| {
                record.deinit();
                self.instances[index] = null;
            }
        }
        self.allocator.free(self.name);
        self.* = undefined;
    }

    pub fn instanceCount(self: *const Session) u16 {
        return self.count;
    }

    pub fn createInstance(
        self: *Session,
        io: std.Io,
        inherited_environment: std.process.Environ,
        launch: howl_instance.Launch,
    ) CreateInstanceError!InstanceId {
        if (self.count == self.instances.len) return error.Capacity;
        if (self.next_instance_id == 0) return error.IdentityExhausted;
        const slot = self.freeSlot() orelse unreachable;
        const owned = try howl_instance.init(self.allocator, inherited_environment, launch);
        errdefer howl_instance.deinit(owned);
        var service = try instance_service.Service.init(self.allocator, io, owned);
        errdefer service.deinit();

        const id = self.next_instance_id;
        self.next_instance_id = advanceIdentity(id) catch return error.IdentityExhausted;
        self.instances[slot] = .{ .id = id, .value = owned, .service = service };
        self.count += 1;
        return id;
    }

    pub fn closeInstance(self: *Session, id: InstanceId) bool {
        const index = self.findInstanceIndex(id) orelse return false;
        if (self.instances[index]) |*record| record.deinit();
        self.instances[index] = null;
        self.count -= 1;
        return true;
    }

    pub fn instanceState(self: *const Session, instance_id: InstanceId) ?InstanceState {
        const index = self.findInstanceIndex(instance_id) orelse return null;
        return self.instances[index].?.state;
    }

    pub const AdoptClientError = instance_service.Service.AdoptError || error{InstanceNotFound};

    pub fn adoptClient(
        self: *Session,
        instance_id: InstanceId,
        fd: std.posix.fd_t,
        initial_input: []const u8,
        preface_output: []const u8,
    ) AdoptClientError!void {
        const index = self.findInstanceIndex(instance_id) orelse return error.InstanceNotFound;
        return self.instances[index].?.service.adoptClient(fd, initial_input, preface_output);
    }

    pub const TurnInstanceError = instance_service.Service.TurnError || error{InstanceNotFound};

    pub fn turnInstance(self: *Session, instance_id: InstanceId, timeout_ms: i32) TurnInstanceError!TurnOutcome {
        const index = self.findInstanceIndex(instance_id) orelse return error.InstanceNotFound;
        const record = &self.instances[index].?;
        try record.service.turn(timeout_ms);
        if (record.state == .running and record.service.lifecycle().child_exited) {
            record.state = .exited;
            return .{ .state_changed = true };
        }
        return .{};
    }

    fn freeSlot(self: *const Session) ?usize {
        for (self.instances, 0..) |record, index| if (record == null) return index;
        return null;
    }

    fn findInstanceIndex(self: *const Session, id: InstanceId) ?usize {
        for (self.instances, 0..) |maybe_record, index| {
            const record = maybe_record orelse continue;
            if (record.id == id) return index;
        }
        return null;
    }
};

test "Instance removal leaves its Session alive and empty" {
    var session = try Session.init(std.testing.allocator, 11, "work");
    defer session.deinit();

    const first = try session.createInstance(std.testing.io, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "exit 0",
        .rows = 4,
        .columns = 12,
    });
    try std.testing.expectEqual(@as(InstanceId, 1), first);
    try std.testing.expectEqual(@as(u16, 1), session.instanceCount());
    try std.testing.expect(session.closeInstance(first));
    try std.testing.expectEqual(@as(u16, 0), session.instanceCount());
    try std.testing.expectEqual(@as(u64, 11), session.id);
    try std.testing.expectEqualStrings("work", session.name);

    const second = try session.createInstance(std.testing.io, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "exit 0",
        .rows = 4,
        .columns = 12,
    });
    try std.testing.expectEqual(@as(InstanceId, 2), second);
}

test "failed Instance construction mutates no Session identity or count" {
    var session = try Session.init(std.testing.allocator, 13, "work");
    defer session.deinit();
    try std.testing.expectError(
        error.InvalidDimensions,
        session.createInstance(std.testing.io, std.testing.environ, .{
            .shell = "/bin/sh",
            .command = "exit 0",
            .rows = 0,
            .columns = 12,
        }),
    );
    try std.testing.expectEqual(@as(u16, 0), session.instanceCount());
    const first = try session.createInstance(std.testing.io, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "exit 0",
        .rows = 4,
        .columns = 12,
    });
    try std.testing.expectEqual(@as(InstanceId, 1), first);
}

fn advanceIdentity(current: u64) error{IdentityExhausted}!u64 {
    if (current == std.math.maxInt(u64)) return error.IdentityExhausted;
    const next = current + 1;
    if (next == 0) return error.IdentityExhausted;
    return next;
}

test "Session creation has zero Instances and no launch policy" {
    var session = try Session.init(std.testing.allocator, 7, "work");
    defer session.deinit();
    try std.testing.expectEqual(@as(u16, 0), session.instanceCount());
    try std.testing.expectEqualStrings("work", session.name);
}
