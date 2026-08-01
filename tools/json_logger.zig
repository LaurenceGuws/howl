//! Writes bounded structured debug events to one JSONL file per process run.

const std = @import("std");

/// Maximum encoded bytes retained for one trace event.
pub const max_record_bytes: usize = 65_536;
/// Maximum encoded bytes retained for one process run.
pub const max_file_bytes: u64 = 16 * 1024 * 1024;

/// Exact failures from trace construction and append.
pub const Error = error{ OpenFailed, WriteFailed, RecordTooLarge, FileTooLarge };

/// Logger serializes concurrent debug events into one bounded per-run file.
pub const Logger = struct {
    io: std.Io,
    file: ?std.Io.File,
    mutex: std.Io.Mutex,
    started: std.Io.Timestamp,
    length: u64,
    terminal_failure: ?Error,

    /// Creates and truncates the configured trace file for this process run.
    pub fn init(io: std.Io, path: []const u8, enabled: bool) Error!Logger {
        if (!enabled) return .{
            .io = io,
            .file = null,
            .mutex = .init,
            .started = std.Io.Clock.awake.now(io),
            .length = 0,
            .terminal_failure = null,
        };
        const file = std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true }) catch {
            return error.OpenFailed;
        };
        return .{
            .io = io,
            .file = file,
            .mutex = .init,
            .started = std.Io.Clock.awake.now(io),
            .length = 0,
            .terminal_failure = null,
        };
    }

    /// Adds one run-relative debugger timestamp and appends a complete JSON object.
    pub fn write(self: *Logger, value: anytype) Error!void {
        const file = self.file orelse return;
        const field_names = switch (@typeInfo(@TypeOf(value))) {
            .@"struct" => |info| info.field_names,
            else => @compileError("trace records must be structs"),
        };
        inline for (field_names) |field_name| comptime if (std.mem.eql(u8, field_name, "debug_time"))
            @compileError("debug_time is owned by trace.Logger");
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.terminal_failure) |failure| return failure;

        var buffer: [max_record_bytes]u8 = undefined;
        var writer: std.Io.Writer = .fixed(&buffer);
        var time_buffer: [32]u8 = undefined;
        const elapsed: u64 = @intCast(
            self.started.durationTo(std.Io.Clock.awake.now(self.io)).toMilliseconds(),
        );
        const debug_time = std.fmt.bufPrint(
            &time_buffer,
            "{d:0>2}:{d:0>2}:{d:0>3}",
            .{ elapsed / 60_000, elapsed / 1_000 % 60, elapsed % 1_000 },
        ) catch unreachable;
        writer.writeAll("{\"debug_time\":") catch return error.RecordTooLarge;
        std.json.Stringify.value(debug_time, .{}, &writer) catch return error.RecordTooLarge;
        inline for (field_names) |field_name| {
            writer.writeByte(',') catch return error.RecordTooLarge;
            std.json.Stringify.value(field_name, .{}, &writer) catch return error.RecordTooLarge;
            writer.writeByte(':') catch return error.RecordTooLarge;
            std.json.Stringify.value(@field(value, field_name), .{}, &writer) catch
                return error.RecordTooLarge;
        }
        writer.writeAll("}\n") catch return error.RecordTooLarge;
        const record = writer.buffered();
        if (record.len > max_file_bytes - self.length) {
            self.terminal_failure = error.FileTooLarge;
            return error.FileTooLarge;
        }
        file.writePositionalAll(self.io, record, self.length) catch {
            self.terminal_failure = error.WriteFailed;
            return error.WriteFailed;
        };
        self.length += record.len;
    }

    /// Returns the first terminal append failure after concurrent writers have joined.
    pub fn terminalFailure(self: *const Logger) ?Error {
        return self.terminal_failure;
    }

    /// Closes the per-run file after all writers have joined.
    pub fn deinit(self: *Logger) void {
        if (self.file) |file| file.close(self.io);
        self.* = undefined;
    }
};

test "enabled tracing writes bounded JSONL records" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    const path = try std.fs.path.join(std.testing.allocator, &.{ root, "trace.jsonl" });
    defer std.testing.allocator.free(path);
    var logger = try Logger.init(std.testing.io, path, true);
    const first = try std.Thread.spawn(.{}, writeMany, .{ &logger, "first" });
    const second = try std.Thread.spawn(.{}, writeMany, .{ &logger, "second" });
    first.join();
    second.join();
    const oversized: [max_record_bytes]u8 = @splat('x');
    try std.testing.expectError(error.RecordTooLarge, logger.write(.{ .bytes = oversized }));
    logger.deinit();
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        path,
        std.testing.allocator,
        .limited(max_file_bytes),
    );
    defer std.testing.allocator.free(bytes);
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    var count: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, line, .{});
        defer parsed.deinit();
        const debug_time = parsed.value.object.get("debug_time").?.string;
        try std.testing.expectEqual(@as(usize, 9), debug_time.len);
        try std.testing.expectEqual(':', debug_time[2]);
        try std.testing.expectEqual(':', debug_time[5]);
        try std.testing.expect(parsed.value.object.get("source").?.string.len != 0);
        try std.testing.expect(parsed.value.object.get("sequence").?.integer < 32);
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 64), count);
}

test "disabled tracing performs no file operation" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    const path = try std.fs.path.join(std.testing.allocator, &.{ root, "disabled.jsonl" });
    defer std.testing.allocator.free(path);
    var logger = try Logger.init(std.testing.io, path, false);
    try logger.write(.{ .stage = "disabled" });
    try std.testing.expect(logger.file == null);
    logger.deinit();
    try std.testing.expectError(
        error.FileNotFound,
        std.Io.Dir.cwd().openFile(std.testing.io, path, .{}),
    );
}

test "terminal write failure is sticky and cleanup closes the file" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    const path = try std.fs.path.join(std.testing.allocator, &.{ root, "failure.jsonl" });
    defer std.testing.allocator.free(path);
    var logger = try Logger.init(std.testing.io, path, true);
    const file = logger.file.?;
    file.close(std.testing.io);
    try std.testing.expectError(error.WriteFailed, logger.write(.{ .stage = "closed" }));
    try std.testing.expectEqual(error.WriteFailed, logger.terminalFailure().?);
    try std.testing.expectError(error.WriteFailed, logger.write(.{ .stage = "sticky" }));
    logger.file = null;
    logger.deinit();
    const reopened = try std.Io.Dir.cwd().openFile(std.testing.io, path, .{});
    reopened.close(std.testing.io);
}

test "trace construction reports a system with no file operations" {
    try std.testing.expectError(
        error.OpenFailed,
        Logger.init(std.Io.failing, "trace.jsonl", true),
    );
}

test "enabled tracing stops at its file bound" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    const path = try std.fs.path.join(std.testing.allocator, &.{ root, "bounded.jsonl" });
    defer std.testing.allocator.free(path);
    var logger = try Logger.init(std.testing.io, path, true);
    defer logger.deinit();
    const bytes: [max_record_bytes - 128]u8 = @splat('x');
    var writes: usize = 0;
    while (true) {
        logger.write(.{ .bytes = bytes }) catch |failure| {
            try std.testing.expectEqual(error.FileTooLarge, failure);
            break;
        };
        writes += 1;
    }
    try std.testing.expect(writes > 0);
    try std.testing.expect(logger.length <= max_file_bytes);
    try std.testing.expectEqual(error.FileTooLarge, logger.terminalFailure().?);
    try std.testing.expectError(error.FileTooLarge, logger.write(.{ .bytes = "small" }));
}

fn writeMany(logger: *Logger, source: []const u8) void {
    for (0..32) |sequence| {
        logger.write(.{ .source = source, .sequence = sequence }) catch @panic("trace write failed");
    }
}
