//! Defines and publishes the bounded runtime record for one live Howl session daemon.

const std = @import("std");
const linux = std.os.linux;

/// Maximum bytes accepted for one human session name.
pub const maximum_name_bytes: usize = 64;
/// Maximum bytes accepted for an XDG runtime directory path.
pub const maximum_runtime_dir_bytes: usize = 2048;
/// Maximum encoded bytes in one runtime discovery record.
pub const maximum_record_bytes: usize = 512;
/// Maximum regular record files one daemon startup will inspect.
pub const maximum_record_files: usize = 128;
/// Maximum bytes in one published loopback endpoint.
pub const maximum_endpoint_bytes: usize = 32;

const record_magic = "HOWL_SESSION_V1";
const loopback_prefix = "tcp://127.0.0.1:";
const maximum_path_bytes = maximum_runtime_dir_bytes + 128;

/// One borrowed, validated live-session discovery record.
pub const Record = struct {
    name: []const u8,
    pid: u32,
    endpoint: []const u8,
    rows: u16,
    columns: u16,
};

/// Reports malformed or out-of-bounds runtime discovery data.
pub const RecordError = error{
    InvalidName,
    InvalidPid,
    InvalidEndpoint,
    InvalidRows,
    InvalidColumns,
    InvalidRecord,
    OutputTooSmall,
};

/// Reports bounded runtime-path or publication failure.
pub const PublicationError = RecordError || error{
    RuntimeDirectoryInvalid,
    RuntimeDirectoryFailed,
    RuntimePathTooLong,
    RecordCreateFailed,
    RecordWriteFailed,
    RecordPublishFailed,
    RuntimeCleanupFailed,
    TooManyRuntimeRecords,
};

/// Owns one daemon runtime record until the session daemon exits.
pub const Publication = struct {
    io: std.Io,
    path: [maximum_path_bytes]u8,
    path_len: u16,

    /// Publishes one process-unique session record below XDG_RUNTIME_DIR.
    pub fn init(io: std.Io, runtime_dir: []const u8, record: Record) PublicationError!Publication {
        try validateRecord(record);
        try validateRuntimeDir(runtime_dir);
        var howl_path_buffer: [maximum_path_bytes]u8 = undefined;
        const howl_path = std.fmt.bufPrint(&howl_path_buffer, "{s}/howl", .{runtime_dir}) catch
            return error.RuntimePathTooLong;
        try ensureDirectory(io, howl_path);
        var sessions_path_buffer: [maximum_path_bytes]u8 = undefined;
        const sessions_path = std.fmt.bufPrint(&sessions_path_buffer, "{s}/sessions", .{howl_path}) catch
            return error.RuntimePathTooLong;
        try ensureDirectory(io, sessions_path);
        try scavengeStaleRecords(io, sessions_path);

        var path_buffer: [maximum_path_bytes]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buffer, "{s}/{d}-{s}", .{
            sessions_path,
            record.pid,
            record.name,
        }) catch return error.RuntimePathTooLong;
        var temporary_path_buffer: [maximum_path_bytes]u8 = undefined;
        const temporary_path = std.fmt.bufPrint(&temporary_path_buffer, "{s}/.{d}-{s}.tmp", .{
            sessions_path,
            record.pid,
            record.name,
        }) catch return error.RuntimePathTooLong;
        var encoded: [maximum_record_bytes]u8 = undefined;
        const bytes = try encodeRecord(&encoded, record);
        var file = std.Io.Dir.createFileAbsolute(io, temporary_path, .{
            .permissions = .fromMode(0o600),
        }) catch return error.RecordCreateFailed;
        file.writePositionalAll(io, bytes, 0) catch {
            file.close(io);
            try deleteInitPath(io, temporary_path);
            return error.RecordWriteFailed;
        };
        file.close(io);
        std.Io.Dir.renameAbsolute(temporary_path, path, io) catch {
            try deleteInitPath(io, temporary_path);
            return error.RecordPublishFailed;
        };

        var publication = Publication{
            .io = io,
            .path = undefined,
            .path_len = @intCast(path.len),
        };
        @memcpy(publication.path[0..path.len], path);
        return publication;
    }

    /// Removes only this process-unique runtime record.
    pub fn deinit(self: *Publication) void {
        deleteRecordFile(self.io, self.path[0..self.path_len]);
        self.* = undefined;
    }
};

/// Validates one safe human session name for use as runtime record metadata.
pub fn validateName(name: []const u8) error{InvalidName}!void {
    if (name.len == 0 or name.len > maximum_name_bytes) return error.InvalidName;
    for (name) |byte| switch (byte) {
        'a'...'z', 'A'...'Z', '0'...'9', '.', '_', '-' => {},
        else => return error.InvalidName,
    };
}

/// Parses the only accepted loopback TCP endpoint form and returns its nonzero port.
pub fn endpointPort(endpoint: []const u8) error{InvalidEndpoint}!u16 {
    if (endpoint.len > maximum_endpoint_bytes or !std.mem.startsWith(u8, endpoint, loopback_prefix))
        return error.InvalidEndpoint;
    const text = endpoint[loopback_prefix.len..];
    if (text.len == 0 or std.mem.indexOfScalar(u8, text, '/') != null) return error.InvalidEndpoint;
    const port = std.fmt.parseInt(u16, text, 10) catch return error.InvalidEndpoint;
    if (port == 0) return error.InvalidEndpoint;
    return port;
}

/// Builds the bounded user-runtime directory containing live session records.
pub fn sessionsPath(
    output: []u8,
    runtime_dir: []const u8,
) error{ RuntimeDirectoryInvalid, OutputTooSmall }![]const u8 {
    try validateRuntimeDir(runtime_dir);
    return std.fmt.bufPrint(output, "{s}/howl/sessions", .{runtime_dir}) catch
        return error.OutputTooSmall;
}

/// Reports whether one record filename exactly matches its validated PID and name.
pub fn filenameMatches(filename: []const u8, record: Record) bool {
    var expected_buffer: [maximum_name_bytes + 16]u8 = undefined;
    const expected = std.fmt.bufPrint(&expected_buffer, "{d}-{s}", .{ record.pid, record.name }) catch
        return false;
    return std.mem.eql(u8, filename, expected);
}

/// Encodes one strict line-oriented discovery record into caller-owned storage.
pub fn encodeRecord(output: []u8, record: Record) RecordError![]const u8 {
    try validateRecord(record);
    return std.fmt.bufPrint(
        output,
        record_magic ++ "\nname={s}\npid={d}\nendpoint={s}\nrows={d}\ncolumns={d}\n",
        .{ record.name, record.pid, record.endpoint, record.rows, record.columns },
    ) catch return error.OutputTooSmall;
}

/// Decodes one strict line-oriented discovery record while borrowing its input bytes.
pub fn decodeRecord(input: []const u8) RecordError!Record {
    if (input.len == 0 or input.len > maximum_record_bytes) return error.InvalidRecord;
    var lines = std.mem.splitScalar(u8, input, '\n');
    if (!std.mem.eql(u8, lines.next() orelse return error.InvalidRecord, record_magic))
        return error.InvalidRecord;
    const name = try field(lines.next() orelse return error.InvalidRecord, "name=");
    const pid_text = try field(lines.next() orelse return error.InvalidRecord, "pid=");
    const endpoint = try field(lines.next() orelse return error.InvalidRecord, "endpoint=");
    const rows_text = try field(lines.next() orelse return error.InvalidRecord, "rows=");
    const columns_text = try field(lines.next() orelse return error.InvalidRecord, "columns=");
    if ((lines.next() orelse return error.InvalidRecord).len != 0 or lines.next() != null)
        return error.InvalidRecord;
    const record = Record{
        .name = name,
        .pid = std.fmt.parseInt(u32, pid_text, 10) catch return error.InvalidPid,
        .endpoint = endpoint,
        .rows = std.fmt.parseInt(u16, rows_text, 10) catch return error.InvalidRows,
        .columns = std.fmt.parseInt(u16, columns_text, 10) catch return error.InvalidColumns,
    };
    try validateRecord(record);
    return record;
}

fn validateRecord(record: Record) RecordError!void {
    try validateName(record.name);
    if (record.pid == 0 or std.math.cast(std.posix.pid_t, record.pid) == null)
        return error.InvalidPid;
    const port = endpointPort(record.endpoint) catch return error.InvalidEndpoint;
    std.debug.assert(port != 0);
    if (record.rows == 0) return error.InvalidRows;
    if (record.columns == 0) return error.InvalidColumns;
}

fn field(line: []const u8, prefix: []const u8) error{InvalidRecord}![]const u8 {
    if (!std.mem.startsWith(u8, line, prefix) or line.len == prefix.len)
        return error.InvalidRecord;
    return line[prefix.len..];
}

fn scavengeStaleRecords(
    io: std.Io,
    sessions_path: []const u8,
) error{ RuntimeDirectoryFailed, RuntimeCleanupFailed, TooManyRuntimeRecords }!void {
    var directory = std.Io.Dir.openDirAbsolute(io, sessions_path, .{ .iterate = true }) catch
        return error.RuntimeDirectoryFailed;
    defer directory.close(io);
    var iterator = directory.iterateAssumeFirstIteration();
    var inspected: usize = 0;
    while (iterator.next(io) catch return error.RuntimeDirectoryFailed) |entry| {
        if (entry.kind != .file) continue;
        if (temporaryFilenamePid(entry.name)) |pid| {
            inspected += 1;
            if (inspected > maximum_record_files) return error.TooManyRuntimeRecords;
            if (!processAlive(pid)) try deleteStaleFile(io, directory, entry.name);
            continue;
        }
        if (!ownedFilename(entry.name)) continue;
        inspected += 1;
        if (inspected > maximum_record_files) return error.TooManyRuntimeRecords;
        var buffer: [maximum_record_bytes + 1]u8 = undefined;
        const bytes = readRuntimeRecord(io, directory, entry.name, &buffer) catch {
            try deleteStaleFile(io, directory, entry.name);
            continue;
        };
        const record = decodeRecord(bytes) catch {
            try deleteStaleFile(io, directory, entry.name);
            continue;
        };
        if (!filenameMatches(entry.name, record) or !processAlive(record.pid))
            try deleteStaleFile(io, directory, entry.name);
    }
}

fn ownedFilename(filename: []const u8) bool {
    const separator = std.mem.indexOfScalar(u8, filename, '-') orelse return false;
    if (separator == 0 or separator + 1 >= filename.len) return false;
    const pid = std.fmt.parseInt(u32, filename[0..separator], 10) catch return false;
    if (pid == 0 or std.math.cast(std.posix.pid_t, pid) == null) return false;
    validateName(filename[separator + 1 ..]) catch return false;
    return true;
}

fn temporaryFilenamePid(filename: []const u8) ?u32 {
    if (filename.len < 7 or filename[0] != '.' or !std.mem.endsWith(u8, filename, ".tmp"))
        return null;
    const body = filename[1 .. filename.len - ".tmp".len];
    const separator = std.mem.indexOfScalar(u8, body, '-') orelse return null;
    if (separator == 0 or separator + 1 >= body.len) return null;
    const pid = std.fmt.parseInt(u32, body[0..separator], 10) catch return null;
    if (pid == 0 or std.math.cast(std.posix.pid_t, pid) == null) return null;
    validateName(body[separator + 1 ..]) catch return null;
    return pid;
}

fn readRuntimeRecord(
    io: std.Io,
    directory: std.Io.Dir,
    filename: []const u8,
    output: *[maximum_record_bytes + 1]u8,
) error{RuntimeDirectoryFailed}![]const u8 {
    var file = directory.openFile(io, filename, .{}) catch return error.RuntimeDirectoryFailed;
    defer file.close(io);
    const count = file.readStreaming(io, &.{output[0..]}) catch return error.RuntimeDirectoryFailed;
    if (count > maximum_record_bytes) return error.RuntimeDirectoryFailed;
    return output[0..count];
}

fn processAlive(pid: u32) bool {
    const native_pid = std.math.cast(std.posix.pid_t, pid) orelse return false;
    const probe_signal: linux.SIG = @fromBackingInt(@intCast(0));
    return switch (linux.errno(linux.kill(native_pid, probe_signal))) {
        .SUCCESS, .PERM => true,
        else => false,
    };
}

fn deleteStaleFile(
    io: std.Io,
    directory: std.Io.Dir,
    filename: []const u8,
) error{RuntimeCleanupFailed}!void {
    directory.deleteFile(io, filename) catch |failure| switch (failure) {
        error.FileNotFound => return,
        else => return error.RuntimeCleanupFailed,
    };
}

fn validateRuntimeDir(runtime_dir: []const u8) error{RuntimeDirectoryInvalid}!void {
    if (runtime_dir.len == 0 or runtime_dir.len > maximum_runtime_dir_bytes or
        runtime_dir[0] != '/' or std.mem.indexOfScalar(u8, runtime_dir, 0) != null)
        return error.RuntimeDirectoryInvalid;
}

fn ensureDirectory(io: std.Io, path: []const u8) error{RuntimeDirectoryFailed}!void {
    std.Io.Dir.createDirAbsolute(io, path, .fromMode(0o700)) catch |failure| switch (failure) {
        error.PathAlreadyExists => return,
        else => return error.RuntimeDirectoryFailed,
    };
}

fn deleteInitPath(io: std.Io, path: []const u8) error{RuntimeCleanupFailed}!void {
    std.Io.Dir.deleteFileAbsolute(io, path) catch |failure| switch (failure) {
        error.FileNotFound => return,
        else => return error.RuntimeCleanupFailed,
    };
}

fn deleteRecordFile(io: std.Io, path: []const u8) void {
    std.Io.Dir.deleteFileAbsolute(io, path) catch |failure| switch (failure) {
        error.FileNotFound => return,
        else => @panic("Howl runtime discovery record cleanup failed"),
    };
}

test "record grammar rejects unsafe names endpoints dimensions and trailing data" {
    var encoded: [maximum_record_bytes]u8 = undefined;
    const valid = Record{
        .name = "agent.dev-1",
        .pid = 42,
        .endpoint = "tcp://127.0.0.1:43123",
        .rows = 24,
        .columns = 80,
    };
    const bytes = try encodeRecord(&encoded, valid);
    const decoded = try decodeRecord(bytes);
    try std.testing.expectEqualStrings(valid.name, decoded.name);
    try std.testing.expectEqual(valid.pid, decoded.pid);
    try std.testing.expectEqualStrings(valid.endpoint, decoded.endpoint);
    try std.testing.expectEqual(valid.rows, decoded.rows);
    try std.testing.expectEqual(valid.columns, decoded.columns);
    try std.testing.expectError(error.InvalidName, validateName("bad/name"));
    try std.testing.expectError(error.InvalidEndpoint, endpointPort("tcp://0.0.0.0:1"));
    try std.testing.expectError(error.InvalidRecord, decodeRecord("HOWL_SESSION_V1\nname=x\n"));
    var trailing: [maximum_record_bytes]u8 = undefined;
    const with_trailing = try std.fmt.bufPrint(&trailing, "{s}junk\n", .{bytes});
    try std.testing.expectError(error.InvalidRecord, decodeRecord(with_trailing));
}

test "publication scavenges dead process records before publishing" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const runtime_dir = try temporary.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(runtime_dir);
    const stale_record = Record{
        .name = "dead",
        .pid = std.math.maxInt(std.posix.pid_t),
        .endpoint = "tcp://127.0.0.1:41231",
        .rows = 12,
        .columns = 40,
    };
    const stale = try Publication.init(std.testing.io, runtime_dir, stale_record);
    const stale_path = stale.path[0..stale.path_len];
    const live_pid: u32 = @intCast(linux.getpid());
    var live = try Publication.init(std.testing.io, runtime_dir, .{
        .name = "live",
        .pid = live_pid,
        .endpoint = "tcp://127.0.0.1:41232",
        .rows = 12,
        .columns = 40,
    });
    defer live.deinit();
    try std.testing.expectError(
        error.FileNotFound,
        std.Io.Dir.cwd().openFile(std.testing.io, stale_path, .{}),
    );
}

test "publication owns a process-unique runtime file and removes it" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const runtime_dir = try temporary.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(runtime_dir);
    const record = Record{
        .name = "publication",
        .pid = 9001,
        .endpoint = "tcp://127.0.0.1:41234",
        .rows = 12,
        .columns = 40,
    };
    var publication = try Publication.init(std.testing.io, runtime_dir, record);
    const path = publication.path[0..publication.path_len];
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        path,
        std.testing.allocator,
        .limited(maximum_record_bytes + 1),
    );
    defer std.testing.allocator.free(bytes);
    const decoded = try decodeRecord(bytes);
    try std.testing.expectEqualStrings(record.name, decoded.name);
    publication.deinit();
    try std.testing.expectError(
        error.FileNotFound,
        std.Io.Dir.cwd().openFile(std.testing.io, path, .{}),
    );
}
