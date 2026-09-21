//! Authoritative bounded collection of live/retained Howl Session records.
//!
//! The registry owns Session endpoint lifetime and exact manager identity. It
//! never discovers its own state from sockets, the filesystem, or processes.

const std = @import("std");
const endpoint = @import("howl_session_endpoint");
const manager = @import("howl_server_protocol");

pub const Defaults = struct {
    shell: []const u8,
    cwd: ?[]const u8 = null,
    rows: u16 = 24,
    columns: u16 = 80,
};

pub const CreateError = std.mem.Allocator.Error || endpoint.Server.InitError || error{
    InvalidName,
    NameExists,
    Capacity,
    SocketPathTooLong,
    SocketCleanupFailed,
    IdentityExhausted,
};

const Record = struct {
    session_id: u64,
    created_sequence: u64,
    name: []u8,
    socket_path: ?[]u8,
    server: ?*endpoint.Server,
    state: manager.SessionState = .running,
    failure: [manager.maximum_failure_bytes]u8 = undefined,
    failure_len: u8 = 0,

    fn failureText(self: *const Record) []const u8 {
        return self.failure[0..self.failure_len];
    }

    fn deinitEndpoint(self: *Record, allocator: std.mem.Allocator) void {
        if (self.server) |owner| {
            owner.deinit();
            allocator.destroy(owner);
            self.server = null;
        }
        if (self.socket_path) |path| {
            allocator.free(path);
            self.socket_path = null;
        }
    }

    fn deinit(self: *Record, allocator: std.mem.Allocator) void {
        self.deinitEndpoint(allocator);
        allocator.free(self.name);
        self.* = undefined;
    }
};

pub const Registry = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    environ: std.process.Environ,
    runtime_dir: []const u8,
    defaults: Defaults,
    server_id: u64,
    roster_revision: u64 = 1,
    next_session_id: u64 = 1,
    next_created_sequence: u64 = 1,
    records: [manager.maximum_sessions]?Record = @splat(null),
    count: u16 = 0,
    blocking_index: usize = 0,

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        environ: std.process.Environ,
        runtime_dir: []const u8,
        defaults: Defaults,
        server_id: u64,
    ) error{InvalidServerIdentity}!Registry {
        if (server_id == 0) return error.InvalidServerIdentity;
        return .{
            .allocator = allocator,
            .io = io,
            .environ = environ,
            .runtime_dir = runtime_dir,
            .defaults = defaults,
            .server_id = server_id,
        };
    }

    pub fn deinit(self: *Registry) void {
        var index = self.records.len;
        while (index != 0) {
            index -= 1;
            if (self.records[index]) |*record| {
                record.deinit(self.allocator);
                self.records[index] = null;
            }
        }
        self.count = 0;
    }

    pub fn create(self: *Registry, request: manager.Create) CreateError!u64 {
        if (!manager.validName(request.name)) return error.InvalidName;
        if (self.findName(request.name) != null) return error.NameExists;
        if (self.count == self.records.len) return error.Capacity;
        if (self.next_session_id == 0 or self.next_created_sequence == 0)
            return error.IdentityExhausted;

        const rows = if (request.rows == 0) self.defaults.rows else request.rows;
        const columns = if (request.columns == 0) self.defaults.columns else request.columns;
        if (rows == 0 or columns == 0) return error.InvalidName;
        const shell = request.shell orelse self.defaults.shell;
        const cwd = request.cwd orelse self.defaults.cwd;

        const owned_name = try self.allocator.dupe(u8, request.name);
        errdefer self.allocator.free(owned_name);
        const socket_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}.sock",
            .{ self.runtime_dir, request.name },
        );
        errdefer self.allocator.free(socket_path);
        if (socket_path.len >= 108) return error.SocketPathTooLong;
        std.Io.Dir.deleteFileAbsolute(self.io, socket_path) catch |failure| switch (failure) {
            error.FileNotFound => {},
            else => return error.SocketCleanupFailed,
        };

        const owner = try self.allocator.create(endpoint.Server);
        errdefer self.allocator.destroy(owner);
        owner.* = try endpoint.Server.init(
            std.heap.page_allocator,
            self.io,
            self.environ,
            .{ .unix = socket_path },
            .{
                .shell = shell,
                .command = request.command,
                .cwd = cwd,
                .rows = rows,
                .columns = columns,
            },
        );
        errdefer owner.deinit();

        const slot = self.freeSlot() orelse unreachable;
        const id = self.next_session_id;
        const created = self.next_created_sequence;
        self.next_session_id = advanceIdentity(self.next_session_id) catch
            return error.IdentityExhausted;
        self.next_created_sequence = advanceIdentity(self.next_created_sequence) catch
            return error.IdentityExhausted;
        self.records[slot] = .{
            .session_id = id,
            .created_sequence = created,
            .name = owned_name,
            .socket_path = socket_path,
            .server = owner,
        };
        self.count += 1;
        advanceRevision(&self.roster_revision);
        return id;
    }

    pub fn close(self: *Registry, session_id: u64) bool {
        const index = self.findId(session_id) orelse return false;
        if (self.records[index]) |*record| record.deinit(self.allocator);
        self.records[index] = null;
        self.count -= 1;
        advanceRevision(&self.roster_revision);
        if (self.blocking_index == index)
            self.blocking_index = (index + 1) % self.records.len;
        return true;
    }

    pub fn findName(self: *const Registry, name: []const u8) ?u64 {
        for (self.records) |maybe_record| {
            const record = maybe_record orelse continue;
            if (std.mem.eql(u8, record.name, name)) return record.session_id;
        }
        return null;
    }

    pub fn hasActiveEndpoint(self: *const Registry) bool {
        for (self.records) |maybe_record| {
            const record = maybe_record orelse continue;
            if (record.server != null) return true;
        }
        return false;
    }

    pub fn noteManagerChange(self: *Registry) void {
        advanceRevision(&self.roster_revision);
    }

    pub fn endpointText(self: *const Registry, session_id: u64, output: []u8) ![]const u8 {
        const index = self.findId(session_id) orelse return error.SessionNotFound;
        const record = self.records[index].?;
        const path = record.socket_path orelse return error.SessionUnavailable;
        return std.fmt.bufPrint(output, "unix:{s}", .{path});
    }

    pub fn serviceTurn(self: *Registry, timeout_ms: i32) ?manager.SessionRecord {
        var index = self.blocking_index;
        var visited: usize = 0;
        var blocked = false;
        while (visited < self.records.len) : (visited += 1) {
            if (self.records[index]) |*record| {
                if (record.server) |owner| {
                    const timeout = if (!blocked) timeout_ms else 0;
                    blocked = true;
                    owner.turn(timeout) catch |failure| {
                        self.markFailed(record, @errorName(failure));
                        self.blocking_index = (index + 1) % self.records.len;
                        return recordView(record);
                    };
                    if (owner.lifecycle().child_exited and record.state == .running) {
                        record.state = .exited;
                        advanceRevision(&self.roster_revision);
                    }
                }
            }
            index = (index + 1) % self.records.len;
        }
        self.blocking_index = (self.blocking_index + 1) % self.records.len;
        return null;
    }

    pub fn rosterPayload(self: *const Registry, stopping: bool, output: []u8) ![]const u8 {
        var ordered: [manager.maximum_sessions]*const Record = undefined;
        var ordered_count: usize = 0;
        for (&self.records) |*maybe_record| {
            if (maybe_record.*) |*record| {
                var insert = ordered_count;
                while (insert != 0 and ordered[insert - 1].created_sequence > record.created_sequence) : (insert -= 1)
                    ordered[insert] = ordered[insert - 1];
                ordered[insert] = record;
                ordered_count += 1;
            }
        }
        var offset: usize = 0;
        if (output.len < manager.payload_bytes.roster_header) return error.OutputTooSmall;
        var header: [manager.payload_bytes.roster_header]u8 = undefined;
        try manager.encodeRosterHeader(&header, .{
            .server_id = self.server_id,
            .roster_revision = self.roster_revision,
            .session_count = self.count,
            .capacity = manager.maximum_sessions,
            .stopping = stopping,
        });
        @memcpy(output[0..header.len], &header);
        offset += header.len;
        for (ordered[0..ordered_count]) |record| {
            const encoded = try manager.encodeRosterRecord(output[offset..], recordView(record));
            offset += encoded.len;
        }
        return output[0..offset];
    }

    fn recordView(record: *const Record) manager.SessionRecord {
        return .{
            .session_id = record.session_id,
            .created_sequence = record.created_sequence,
            .state = record.state,
            .name = record.name,
            .failure = record.failureText(),
        };
    }

    fn markFailed(self: *Registry, record: *Record, failure: []const u8) void {
        record.deinitEndpoint(self.allocator);
        record.state = .failed;
        const count = @min(failure.len, record.failure.len);
        @memcpy(record.failure[0..count], failure[0..count]);
        record.failure_len = @intCast(count);
        advanceRevision(&self.roster_revision);
    }

    fn findId(self: *const Registry, session_id: u64) ?usize {
        if (session_id == 0) return null;
        for (self.records, 0..) |maybe_record, index| {
            const record = maybe_record orelse continue;
            if (record.session_id == session_id) return index;
        }
        return null;
    }

    fn freeSlot(self: *const Registry) ?usize {
        for (self.records, 0..) |record, index| if (record == null) return index;
        return null;
    }
};

fn advanceIdentity(value: u64) error{IdentityExhausted}!u64 {
    if (value == std.math.maxInt(u64)) return error.IdentityExhausted;
    return value + 1;
}

fn advanceRevision(value: *u64) void {
    value.* +%= 1;
    if (value.* == 0) value.* = 1;
}

test "registry creates closes and never reuses session identity" {
    var path_buffer: [96]u8 = undefined;
    const runtime = try std.fmt.bufPrint(&path_buffer, "/tmp/howl-registry-{d}", .{std.os.linux.getpid()});
    std.Io.Dir.createDirPath(.cwd(), std.testing.io, runtime) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, runtime) catch {};

    var registry = try Registry.init(
        std.testing.allocator,
        std.testing.io,
        std.testing.environ,
        runtime,
        .{ .shell = "/bin/sh", .rows = 4, .columns = 40 },
        77,
    );
    defer registry.deinit();

    const one = try registry.create(.{ .name = "one", .command = "printf one" });
    const two = try registry.create(.{ .name = "two", .command = "printf two" });
    try std.testing.expectEqual(@as(u64, 1), one);
    try std.testing.expectEqual(@as(u64, 2), two);
    try std.testing.expectEqual(@as(u16, 2), registry.count);
    try std.testing.expectEqual(@as(u64, 3), registry.roster_revision);
    try std.testing.expect(registry.close(one));
    const three = try registry.create(.{ .name = "three", .command = "printf three" });
    try std.testing.expectEqual(@as(u64, 3), three);
    try std.testing.expect(!registry.close(one));
    try std.testing.expectEqual(two, registry.findName("two").?);
}

test "registry retains exited session and encodes deterministic roster" {
    var path_buffer: [96]u8 = undefined;
    const runtime = try std.fmt.bufPrint(&path_buffer, "/tmp/howl-registry-exit-{d}", .{std.os.linux.getpid()});
    std.Io.Dir.createDirPath(.cwd(), std.testing.io, runtime) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, runtime) catch {};

    var registry = try Registry.init(
        std.testing.allocator,
        std.testing.io,
        std.testing.environ,
        runtime,
        .{ .shell = "/bin/sh", .rows = 4, .columns = 40 },
        88,
    );
    defer registry.deinit();
    const done = try registry.create(.{ .name = "done", .command = "exit 0" });
    const stay = try registry.create(.{ .name = "stay", .command = "sleep 5" });
    try std.testing.expect(done != stay);

    var attempts: usize = 0;
    while (attempts < 200) : (attempts += 1) {
        try std.testing.expect(registry.serviceTurn(10) == null);
        const id = registry.findName("done").?;
        const index = registry.findId(id).?;
        if (registry.records[index].?.state == .exited) break;
    }
    const done_index = registry.findId(registry.findName("done").?).?;
    try std.testing.expectEqual(manager.SessionState.exited, registry.records[done_index].?.state);

    var payload: [manager.maximum_payload_bytes]u8 = undefined;
    const encoded = try registry.rosterPayload(false, &payload);
    const header = try manager.decodeRosterHeader(encoded[0..manager.payload_bytes.roster_header]);
    try std.testing.expectEqual(@as(u16, 2), header.session_count);
    var offset: usize = manager.payload_bytes.roster_header;
    const first = try manager.decodeRosterRecord(encoded[offset..]);
    offset += first.encoded_bytes;
    const second = try manager.decodeRosterRecord(encoded[offset..]);
    try std.testing.expectEqualStrings("done", first.record.name);
    try std.testing.expectEqual(manager.SessionState.exited, first.record.state);
    try std.testing.expectEqualStrings("stay", second.record.name);
}
