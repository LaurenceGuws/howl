//! Enumerates validated live Howl daemon records without mutating runtime state.

const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;
const session_discovery = @import("howl_session").discovery;
const client = @import("client.zig");

/// Maximum live sessions one CLI invocation will materialize.
pub const maximum_sessions: usize = 64;
/// Maximum bytes inspected from one process command line.
pub const maximum_cmdline_bytes: usize = 4096;

/// Copies one validated runtime record into fixed CLI-owned storage.
pub const Session = struct {
    name_storage: [session_discovery.maximum_name_bytes]u8 = undefined,
    name_len: u8,
    endpoint_storage: [session_discovery.maximum_endpoint_bytes]u8 = undefined,
    endpoint_len: u8,
    pid: u32,
    rows: u16,
    columns: u16,
    reachable: bool,

    /// Borrows this copied session's human name.
    pub fn name(self: *const Session) []const u8 {
        return self.name_storage[0..self.name_len];
    }

    /// Borrows this copied session's loopback endpoint.
    pub fn endpoint(self: *const Session) []const u8 {
        return self.endpoint_storage[0..self.endpoint_len];
    }
};

/// Fixed result storage plus counts for malformed or stale records skipped during discovery.
pub const List = struct {
    sessions: [maximum_sessions]Session = undefined,
    count: u8 = 0,
    invalid_records: u16 = 0,
    stale_records: u16 = 0,

    /// Borrows the sorted validated session prefix.
    pub fn items(self: *const List) []const Session {
        return self.sessions[0..self.count];
    }
};

/// Reports bounded runtime discovery failure instead of silently truncating session state.
pub const Error = std.mem.Allocator.Error || error{
    RuntimePathTooLong,
    RuntimeOpenFailed,
    RuntimeIterateFailed,
    TooManyRecords,
    TooManySessions,
};

/// Enumerates process-validated records and separately probes current Howl reachability.
pub fn list(
    allocator: std.mem.Allocator,
    io: std.Io,
    runtime_dir: []const u8,
) Error!List {
    var sessions_path_buffer: [session_discovery.maximum_runtime_dir_bytes + 32]u8 = undefined;
    const sessions_path = session_discovery.sessionsPath(&sessions_path_buffer, runtime_dir) catch
        return error.RuntimePathTooLong;
    var directory = std.Io.Dir.openDirAbsolute(io, sessions_path, .{ .iterate = true }) catch |failure| switch (failure) {
        error.FileNotFound => return .{},
        else => return error.RuntimeOpenFailed,
    };
    defer directory.close(io);

    var result: List = .{};
    var iterator = directory.iterateAssumeFirstIteration();
    var inspected: usize = 0;
    while (iterator.next(io) catch return error.RuntimeIterateFailed) |entry| {
        if (entry.kind != .file) continue;
        inspected += 1;
        if (inspected > session_discovery.maximum_record_files) return error.TooManyRecords;
        const bytes = directory.readFileAlloc(
            io,
            entry.name,
            allocator,
            .limited(session_discovery.maximum_record_bytes + 1),
        ) catch |failure| switch (failure) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                result.invalid_records += 1;
                continue;
            },
        };
        defer allocator.free(bytes);
        const record = session_discovery.decodeRecord(bytes) catch {
            result.invalid_records += 1;
            continue;
        };
        if (!session_discovery.filenameMatches(entry.name, record)) {
            result.invalid_records += 1;
            continue;
        }
        if (!processMatchesSessionDaemon(io, record.pid)) {
            result.stale_records += 1;
            continue;
        }
        if (result.count == maximum_sessions) return error.TooManySessions;
        result.sessions[result.count] = copySession(record, try endpointReachable(allocator, record.endpoint));
        result.count += 1;
    }
    std.mem.sort(Session, result.sessions[0..result.count], {}, sessionLessThan);
    return result;
}

fn copySession(record: session_discovery.Record, reachable: bool) Session {
    var session = Session{
        .name_len = @intCast(record.name.len),
        .endpoint_len = @intCast(record.endpoint.len),
        .pid = record.pid,
        .rows = record.rows,
        .columns = record.columns,
        .reachable = reachable,
    };
    @memcpy(session.name_storage[0..record.name.len], record.name);
    @memcpy(session.endpoint_storage[0..record.endpoint.len], record.endpoint);
    return session;
}

fn processMatchesSessionDaemon(
    io: std.Io,
    pid: u32,
) bool {
    const native_pid = std.math.cast(posix.pid_t, pid) orelse return false;
    const probe_signal: linux.SIG = @fromBackingInt(@intCast(0));
    switch (linux.errno(linux.kill(native_pid, probe_signal))) {
        .SUCCESS, .PERM => {},
        else => return false,
    }
    var path_buffer: [64]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buffer, "/proc/{d}/cmdline", .{pid}) catch return false;
    var file = std.Io.Dir.cwd().openFile(io, path, .{}) catch return false;
    defer file.close(io);
    var cmdline: [maximum_cmdline_bytes]u8 = undefined;
    const count = file.readStreaming(io, &.{cmdline[0..]}) catch return false;
    if (count == cmdline.len) {
        var extra: [1]u8 = undefined;
        if ((file.readStreaming(io, &.{extra[0..]}) catch return false) != 0) return false;
    }
    return std.mem.indexOf(u8, cmdline[0..count], "howl-sessiond") != null;
}

fn endpointReachable(allocator: std.mem.Allocator, endpoint: []const u8) std.mem.Allocator.Error!bool {
    var connection = client.Connection.connect(allocator, endpoint) catch |failure| switch (failure) {
        else => return false,
    };
    connection.deinit();
    return true;
}

fn sessionLessThan(_: void, left: Session, right: Session) bool {
    const order = std.mem.order(u8, left.name(), right.name());
    if (order == .lt) return true;
    if (order == .gt) return false;
    return left.pid < right.pid;
}

test "session copy and ordering are fixed and deterministic" {
    const first_record = session_discovery.Record{
        .name = "zeta",
        .pid = 5,
        .endpoint = "tcp://127.0.0.1:40001",
        .rows = 20,
        .columns = 80,
    };
    const second_record = session_discovery.Record{
        .name = "alpha",
        .pid = 9,
        .endpoint = "tcp://127.0.0.1:40002",
        .rows = 30,
        .columns = 100,
    };
    var sessions = [_]Session{
        copySession(first_record, false),
        copySession(second_record, true),
    };
    std.mem.sort(Session, &sessions, {}, sessionLessThan);
    try std.testing.expectEqualStrings("alpha", sessions[0].name());
    try std.testing.expect(sessions[0].reachable);
    try std.testing.expectEqualStrings("zeta", sessions[1].name());
    try std.testing.expect(!sessions[1].reachable);
    try std.testing.expect(session_discovery.filenameMatches("5-zeta", first_record));
    try std.testing.expect(!session_discovery.filenameMatches("6-zeta", first_record));
}
