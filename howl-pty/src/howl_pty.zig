//! Owns one Linux PTY, its child process group, bounded I/O, and cleanup.

const builtin = @import("builtin");
const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;

const c = @import("pty_c");

const linux_nonblock_flag: c_int = @intCast(@as(u32, @bitCast(linux.O{ .NONBLOCK = true })));
const control_character_disabled: posix.cc_t = 0;
const CWinSize = @typeInfo(@typeInfo(@TypeOf(c.openpty)).@"fn".param_types[4].?).pointer.child;
const CTermios = @typeInfo(@typeInfo(@TypeOf(c.openpty)).@"fn".param_types[3].?).pointer.child;
const CTermiosInputSpeed = @TypeOf(@as(CTermios, undefined).unnamed_0);
const CTermiosOutputSpeed = @TypeOf(@as(CTermios, undefined).unnamed_1);
const CTermiosInputSpeedValue = @TypeOf(@as(CTermiosInputSpeed, undefined).c_ispeed);
const CTermiosOutputSpeedValue = @TypeOf(@as(CTermiosOutputSpeed, undefined).c_ospeed);

comptime {
    if (@sizeOf(posix.winsize) != @sizeOf(CWinSize) or
        @alignOf(posix.winsize) != @alignOf(CWinSize) or
        @offsetOf(posix.winsize, "row") != @offsetOf(CWinSize, "ws_row") or
        @offsetOf(posix.winsize, "col") != @offsetOf(CWinSize, "ws_col") or
        @offsetOf(posix.winsize, "xpixel") != @offsetOf(CWinSize, "ws_xpixel") or
        @offsetOf(posix.winsize, "ypixel") != @offsetOf(CWinSize, "ws_ypixel"))
        @compileError("posix.winsize/openpty layout mismatch");
    if (@sizeOf(posix.termios) != @sizeOf(CTermios) or
        @alignOf(posix.termios) != @alignOf(CTermios) or
        @offsetOf(posix.termios, "iflag") != @offsetOf(CTermios, "c_iflag") or
        @offsetOf(posix.termios, "oflag") != @offsetOf(CTermios, "c_oflag") or
        @offsetOf(posix.termios, "cflag") != @offsetOf(CTermios, "c_cflag") or
        @offsetOf(posix.termios, "lflag") != @offsetOf(CTermios, "c_lflag") or
        @offsetOf(posix.termios, "line") != @offsetOf(CTermios, "c_line") or
        @offsetOf(posix.termios, "cc") != @offsetOf(CTermios, "c_cc") or
        @offsetOf(posix.termios, "ispeed") != @offsetOf(CTermios, "unnamed_0") or
        @offsetOf(posix.termios, "ospeed") != @offsetOf(CTermios, "unnamed_1") or
        @sizeOf(CTermiosInputSpeedValue) != @sizeOf(posix.speed_t) or
        @sizeOf(CTermiosOutputSpeedValue) != @sizeOf(posix.speed_t) or
        @alignOf(CTermiosInputSpeedValue) != @alignOf(posix.speed_t) or
        @alignOf(CTermiosOutputSpeedValue) != @alignOf(posix.speed_t) or
        !@hasField(CTermiosInputSpeed, "c_ispeed") or
        !@hasField(CTermiosOutputSpeed, "c_ospeed"))
        @compileError("posix.termios/tcgetattr layout mismatch");
}

const RawIoResult = union(enum) {
    success: usize,
    zero,
    oversized: usize,
    would_block,
    interrupted,
    fatal: linux.E,
};

fn classifyRawIo(result: usize, requested: usize) RawIoResult {
    return switch (linux.errno(result)) {
        .SUCCESS => if (result == 0) .zero else if (result > requested) .{ .oversized = result } else .{ .success = result },
        .AGAIN => .would_block,
        .INTR => .interrupted,
        else => |err| .{ .fatal = err },
    };
}

const FcntlResult = union(enum) {
    success: c_int,
    errno: linux.E,
    out_of_range: usize,
};

fn classifyFcntl(result: usize) FcntlResult {
    if (linux.errno(result) != .SUCCESS) return .{ .errno = linux.errno(result) };
    return .{ .success = std.math.cast(c_int, result) orelse return .{ .out_of_range = result } };
}

fn requireFcntl(result: usize) error{OpenPtyFailed}!c_int {
    return switch (classifyFcntl(result)) {
        .success => |value| value,
        .errno, .out_of_range => error.OpenPtyFailed,
    };
}

fn ensureFcntl(result: usize) error{OpenPtyFailed}!void {
    switch (classifyFcntl(result)) {
        .success => {},
        .errno, .out_of_range => return error.OpenPtyFailed,
    }
}

fn checkedFcntlArgument(value: c_int) ?usize {
    return std.math.cast(usize, value);
}

fn ioctlSucceeded(result: usize) bool {
    return linux.errno(result) == .SUCCESS;
}

const WaitPidResult = enum { zero, expected, interrupted, child, unexpected_success, unexpected_error };

fn classifyWaitPid(result: usize, expected_pid: posix.pid_t) WaitPidResult {
    if (result == 0) return .zero;
    return switch (linux.errno(result)) {
        .SUCCESS => if (result == @as(usize, @intCast(expected_pid))) .expected else .unexpected_success,
        .INTR => .interrupted,
        .CHILD => .child,
        else => .unexpected_error,
    };
}

fn syntheticErrno(err: linux.E) usize {
    const code: isize = -@as(isize, @intCast(@backingInt(err)));
    return @as(usize, @bitCast(code));
}

fn checkedLinuxSignal(value: c_int) ?linux.SIG {
    if (value < 0 or value > 64) return null;
    return @fromBackingInt(@intCast(@as(u32, @intCast(value))));
}

// Public lifecycle failures, signals, and nonblocking write outcomes.

/// Reports copied launch allocation, invalid environment, or a non-Linux build.
pub const InitError = std.mem.Allocator.Error || error{
    EnvironmentByteLimit,
    EnvironmentCountLimit,
    InvalidEnvironment,
    UnsupportedPlatform,
};

/// Selects terminal-owned child identity values copied with the inherited environment.
pub const ChildEnvironment = struct {
    /// Selects one nonempty installed TERM identity without `=` or NUL bytes.
    term: []const u8,
    /// Optionally selects COLORTERM under the same value constraints.
    colorterm: ?[]const u8,
};

/// Reports an invalid lifecycle transition or failed Linux child construction.
pub const StartError = error{
    AlreadyStarted,
    ChildCwdFailed,
    ChildExecFailed,
    ChildSessionFailed,
    ChildStdioFailed,
    ForkFailed,
    LaunchStatusFailed,
    LaunchStatusPipeFailed,
    MasterConfigureFailed,
    OpenPtyFailed,
    ShellUnavailable,
    InvalidDimensions,
};

/// Names signals accepted by the child process-group owner.
pub const Signal = enum(u8) {
    hangup = 1,
    interrupt = 2,
    resize_notify = 3,
    kill = 9,
    terminate = 15,

    fn native(self: Signal) c_int {
        return @intCast(@backingInt(self));
    }
};

/// Reports a nonblocking PTY read failure.
pub const ReadError = error{ EndOfStream, Interrupted, NotStarted, ReadFailed, WouldBlock };

/// Reports invalid dimensions or a failed Linux resize ioctl.
pub const ResizeError = error{ InvalidDimensions, NotStarted, ResizeFailed };

/// Reports unavailable PTY state or failed foreground termios signal delivery.
pub const TermiosSignalError = error{
    ForegroundGroupFailed,
    NotStarted,
    SignalFailed,
    TermiosQueryFailed,
};

/// Reports one nonblocking PTY write failure.
pub const WriteError = error{ ChildClosed, Interrupted, NotStarted, WouldBlock, WriteFailed };

fn mapReadResult(result: usize, requested: usize) ReadError!usize {
    return switch (classifyRawIo(result, requested)) {
        .success => |count| count,
        .zero => error.EndOfStream,
        .oversized => error.ReadFailed,
        .would_block => error.WouldBlock,
        .interrupted => error.Interrupted,
        .fatal => |err| switch (err) {
            .IO => error.EndOfStream,
            else => error.ReadFailed,
        },
    };
}

fn mapWriteResult(result: usize, requested: usize) WriteError!usize {
    return switch (classifyRawIo(result, requested)) {
        .success => |count| count,
        .zero => error.ChildClosed,
        .oversized => error.WriteFailed,
        .would_block => error.WouldBlock,
        .interrupted => error.Interrupted,
        .fatal => |err| switch (err) {
            .IO, .PIPE => error.ChildClosed,
            else => error.WriteFailed,
        },
    };
}

/// Reports the exact normal or signal termination fact returned by waitpid.
pub const ChildExit = union(enum) {
    code: u8,
    signal: u8,
};

/// Reports whether the child remains live or has been reaped.
pub const ChildObservation = union(enum) {
    running,
    exited: ChildExit,
};

/// Reports child observation before start or when waitpid cannot report state.
pub const ObserveError = error{ NotStarted, ObserveFailed };

/// Owns one newly opened master/slave PTY pair until parent or child adoption.
const Open = struct {
    master_fd: posix.fd_t,
    slave_fd: posix.fd_t,
};

const LaunchStatus = struct {
    read_fd: posix.fd_t,
    write_fd: posix.fd_t,
};

const ChildLaunchFailure = enum(u8) {
    session = 1,
    stdio = 2,
    cwd = 3,
    exec = 4,
};

/// Reports exact process-group probing and signal-delivery outcomes.
pub const SignalResult = enum {
    /// The kernel accepted delivery to the live child process group.
    delivered,
    /// The target was already reaped or no process group remained.
    target_missing,
    /// The kernel rejected signal delivery for process ownership permissions.
    permission_denied,
    /// Native signal delivery failed for another reason.
    native_signal_failed,
};

const stop_hangup_grace_ns = 50 * std.time.ns_per_ms;
const stop_terminate_grace_ns = 50 * std.time.ns_per_ms;
const stop_wait_slice_ns = std.time.ns_per_ms;
const environment_max_entries: usize = 1024;
const environment_max_bytes: usize = 1024 * 1024;

fn timespecFromMicroseconds(microseconds: u128) ?linux.timespec {
    const seconds = microseconds / std.time.us_per_s;
    const remainder = (microseconds % std.time.us_per_s) * std.time.ns_per_us;
    return .{
        .sec = std.math.cast(isize, seconds) orelse return null,
        .nsec = std.math.cast(isize, remainder) orelse return null,
    };
}

const SleepResult = enum { success, interrupted, failure };

fn classifySleepResult(result: usize) SleepResult {
    return switch (linux.errno(result)) {
        .SUCCESS => .success,
        .INTR => .interrupted,
        else => .failure,
    };
}

fn consumeSleepResult(result: usize) void {
    switch (classifySleepResult(result)) {
        .success, .interrupted => return,
        .failure => @panic("PTY cleanup clock wait failed"),
    }
}

const LaunchEnvironment = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,
    entries: []?[*:0]u8,

    fn init(
        allocator: std.mem.Allocator,
        inherited: []const []const u8,
        selected: ChildEnvironment,
    ) InitError!LaunchEnvironment {
        try validateEnvironmentValue(selected.term);
        if (selected.colorterm) |value| try validateEnvironmentValue(value);

        var retained_count: usize = 0;
        var byte_count: usize = 0;
        for (inherited) |entry| {
            const separator = std.mem.indexOfScalar(u8, entry, '=') orelse
                return error.InvalidEnvironment;
            if (separator == 0 or std.mem.indexOfScalar(u8, entry, 0) != null)
                return error.InvalidEnvironment;
            if (environmentVariable(entry, "TERM") or environmentVariable(entry, "COLORTERM")) continue;
            retained_count = std.math.add(usize, retained_count, 1) catch
                return error.EnvironmentCountLimit;
            byte_count = environmentBytes(byte_count, entry.len) catch |failure| return failure;
        }
        const override_count: usize = 1 + @as(usize, @intFromBool(selected.colorterm != null));
        const entry_count = std.math.add(usize, retained_count, override_count) catch
            return error.EnvironmentCountLimit;
        if (entry_count > environment_max_entries) return error.EnvironmentCountLimit;
        byte_count = try environmentBytes(byte_count, "TERM=".len + selected.term.len);
        if (selected.colorterm) |value|
            byte_count = try environmentBytes(byte_count, "COLORTERM=".len + value.len);
        if (byte_count > environment_max_bytes) return error.EnvironmentByteLimit;

        const bytes = try allocator.alloc(u8, byte_count);
        errdefer allocator.free(bytes);
        const entries = try allocator.alloc(?[*:0]u8, entry_count + 1);
        errdefer allocator.free(entries);
        var offset: usize = 0;
        var index: usize = 0;
        for (inherited) |entry| {
            if (environmentVariable(entry, "TERM") or environmentVariable(entry, "COLORTERM")) continue;
            copyEnvironmentEntry(bytes, entries, &offset, &index, entry);
        }
        copyEnvironmentOverride(bytes, entries, &offset, &index, "TERM", selected.term);
        if (selected.colorterm) |value|
            copyEnvironmentOverride(bytes, entries, &offset, &index, "COLORTERM", value);
        std.debug.assert(offset == bytes.len and index == entry_count);
        entries[index] = null;
        return .{ .allocator = allocator, .bytes = bytes, .entries = entries };
    }

    fn deinit(self: *LaunchEnvironment) void {
        self.allocator.free(self.entries);
        self.allocator.free(self.bytes);
        self.* = undefined;
    }
};

fn environmentBytes(current: usize, entry_len: usize) error{EnvironmentByteLimit}!usize {
    const with_entry = std.math.add(usize, current, entry_len) catch
        return error.EnvironmentByteLimit;
    const total = std.math.add(usize, with_entry, 1) catch return error.EnvironmentByteLimit;
    if (total > environment_max_bytes) return error.EnvironmentByteLimit;
    return total;
}

fn environmentVariable(entry: []const u8, name: []const u8) bool {
    return entry.len > name.len and entry[name.len] == '=' and std.mem.eql(u8, entry[0..name.len], name);
}

fn validateEnvironmentValue(value: []const u8) error{InvalidEnvironment}!void {
    if (value.len == 0 or std.mem.indexOfAny(u8, value, "=\x00") != null)
        return error.InvalidEnvironment;
}

fn copyEnvironmentEntry(
    bytes: []u8,
    entries: []?[*:0]u8,
    offset: *usize,
    index: *usize,
    entry: []const u8,
) void {
    entries[index.*] = @ptrCast(bytes[offset.*..].ptr);
    @memcpy(bytes[offset.* .. offset.* + entry.len], entry);
    offset.* += entry.len;
    bytes[offset.*] = 0;
    offset.* += 1;
    index.* += 1;
}

fn copyEnvironmentOverride(
    bytes: []u8,
    entries: []?[*:0]u8,
    offset: *usize,
    index: *usize,
    name: []const u8,
    value: []const u8,
) void {
    entries[index.*] = @ptrCast(bytes[offset.*..].ptr);
    @memcpy(bytes[offset.* .. offset.* + name.len], name);
    offset.* += name.len;
    bytes[offset.*] = '=';
    offset.* += 1;
    @memcpy(bytes[offset.* .. offset.* + value.len], value);
    offset.* += value.len;
    bytes[offset.*] = 0;
    offset.* += 1;
    index.* += 1;
}

// Construction primitives used by the PTY owner.

fn childLaunchError(value: u8) StartError {
    return switch (value) {
        @backingInt(ChildLaunchFailure.session) => error.ChildSessionFailed,
        @backingInt(ChildLaunchFailure.stdio) => error.ChildStdioFailed,
        @backingInt(ChildLaunchFailure.cwd) => error.ChildCwdFailed,
        @backingInt(ChildLaunchFailure.exec) => error.ChildExecFailed,
        else => error.LaunchStatusFailed,
    };
}

fn openTransport(cols: u16, rows: u16) StartError!Open {
    var master_fd: c_int = -1;
    var slave_fd: c_int = -1;
    var winsize = posix.winsize{
        .row = rows,
        .col = cols,
        .xpixel = 0,
        .ypixel = 0,
    };
    if (c.openpty(&master_fd, &slave_fd, null, null, @ptrCast(&winsize)) != 0) {
        return error.OpenPtyFailed;
    }
    return .{ .master_fd = @intCast(master_fd), .slave_fd = @intCast(slave_fd) };
}

/// Owns copied launch values, one Linux PTY, and its child process group.
/// `start`, `read`, `write`, `observeChild`, `resize`, `signal`, and `stop`
/// are externally serialized. `stop` and `deinit` require every caller to
/// have returned.
pub const Owned = struct {
    allocator: std.mem.Allocator,
    shell_path: [:0]u8,
    command: ?[:0]u8,
    command_ptr: ?[*:0]u8,
    start_path: ?[:0]u8,
    start_path_ptr: ?[*:0]u8,
    environment: LaunchEnvironment,
    started: bool,
    master_fd: ?posix.fd_t,
    child: Child,
    last_cols: u16,
    last_rows: u16,

    const Self = @This();
    const Child = union(enum) {
        none,
        pending_session: posix.pid_t,
        live: posix.pid_t,
        reaped: struct { pid: posix.pid_t, exit: ChildExit },
    };

    const StartPipes = struct {
        launch_status: LaunchStatus,
    };

    /// Copies launch strings and initializes an idle PTY owner.
    pub fn init(
        allocator: std.mem.Allocator,
        shell_path: []const u8,
        command: ?[]const u8,
        start_path: ?[]const u8,
        child_environment: ChildEnvironment,
    ) InitError!Self {
        if (builtin.os.tag != .linux) return error.UnsupportedPlatform;

        var inherited: [environment_max_entries][]const u8 = undefined;
        var inherited_count: usize = 0;
        var cursor = std.c.environ;
        while (cursor[0]) |entry| : (cursor += 1) {
            if (inherited_count == inherited.len) return error.EnvironmentCountLimit;
            inherited[inherited_count] = std.mem.span(entry);
            inherited_count += 1;
        }
        return initInherited(
            allocator,
            shell_path,
            command,
            start_path,
            child_environment,
            inherited[0..inherited_count],
        );
    }

    fn initInherited(
        allocator: std.mem.Allocator,
        shell_path: []const u8,
        command: ?[]const u8,
        start_path: ?[]const u8,
        child_environment: ChildEnvironment,
        inherited: []const []const u8,
    ) InitError!Self {
        const shell_path_z = try allocator.dupeSentinel(u8, shell_path, 0);
        errdefer allocator.free(shell_path_z);

        const command_z = if (command) |bytes| try allocator.dupeSentinel(u8, bytes, 0) else null;
        errdefer if (command_z) |bytes| allocator.free(bytes);

        const start_path_z = if (start_path) |bytes| try allocator.dupeSentinel(u8, bytes, 0) else null;
        errdefer if (start_path_z) |bytes| allocator.free(bytes);

        var environment = try LaunchEnvironment.init(allocator, inherited, child_environment);
        errdefer environment.deinit();

        return .{
            .allocator = allocator,
            .shell_path = shell_path_z,
            .command = command_z,
            .command_ptr = optionalZPtr(command_z),
            .start_path = start_path_z,
            .start_path_ptr = optionalZPtr(start_path_z),
            .environment = environment,
            .started = false,
            .master_fd = null,
            .child = .none,
            .last_cols = 0,
            .last_rows = 0,
        };
    }

    /// Stops the child group, closes descriptors, and releases copied launch strings.
    pub fn deinit(self: *Self) void {
        self.stop();
        self.allocator.free(self.shell_path);
        if (self.command) |bytes| self.allocator.free(bytes);
        if (self.start_path) |bytes| self.allocator.free(bytes);
        self.environment.deinit();
        self.* = undefined;
    }

    /// Starts one child at the supplied nonzero terminal dimensions.
    pub fn start(self: *Self, cols: u16, rows: u16) StartError!void {
        if (self.started) return error.AlreadyStarted;
        if (cols == 0 or rows == 0) return error.InvalidDimensions;

        try requireExecutable(self.shell_path);
        const transport = try openTransport(cols, rows);
        var transport_owned = true;
        errdefer if (transport_owned) closeTransport(transport);

        const pipes = try openStartPipes();
        var pipes_owned = true;
        errdefer if (pipes_owned) closeStartPipes(pipes);

        try configureMaster(transport.master_fd);
        const pid = try self.forkChild(transport, pipes);
        self.adoptParentTransport(transport, pipes, pid, cols, rows);
        transport_owned = false;
        pipes_owned = false;
        errdefer self.stop();

        try awaitChildLaunch(pipes.launch_status.read_fd);
        self.child = .{ .live = pid };
        self.assertStarted();
    }

    fn openStartPipes() StartError!StartPipes {
        const launch_status = try openLaunchStatusPipe();
        errdefer closeLaunchStatusPipe(launch_status);

        return .{ .launch_status = launch_status };
    }

    fn closeStartPipes(pipes: StartPipes) void {
        closeLaunchStatusPipe(pipes.launch_status);
    }

    fn configureMaster(master_fd: posix.fd_t) StartError!void {
        setCloseOnExec(master_fd) catch return error.MasterConfigureFailed;
        setNonBlocking(master_fd) catch return error.MasterConfigureFailed;
    }

    fn forkChild(self: *Self, transport: Open, pipes: StartPipes) StartError!posix.pid_t {
        const pid = posix.system.fork();
        if (pid < 0) return error.ForkFailed;
        if (pid == 0) {
            if (!closeChildFdIfNeeded(pipes.launch_status.read_fd)) {
                childLaunchExit(pipes.launch_status.write_fd, .stdio);
            }
            childProcess(
                transport.master_fd,
                transport.slave_fd,
                pipes.launch_status.write_fd,
                self.shell_path,
                self.command_ptr,
                self.start_path_ptr,
                self.environment.entries.ptr,
            );
        }
        return pid;
    }

    fn adoptParentTransport(
        self: *Self,
        transport: Open,
        pipes: StartPipes,
        pid: posix.pid_t,
        cols: u16,
        rows: u16,
    ) void {
        closeOwned(transport.slave_fd);
        closeOwned(pipes.launch_status.write_fd);
        self.master_fd = transport.master_fd;
        self.child = .{ .pending_session = pid };
        self.last_cols = cols;
        self.last_rows = rows;
        self.started = true;
    }

    fn assertStarted(self: *const Self) void {
        std.debug.assert(self.master_fd != null);
        std.debug.assert(self.childPid() != null);
    }

    /// Stops and reaps the child process group and closes every descriptor.
    pub fn stop(self: *Self) void {
        if (!self.started) return;

        self.stopChild();

        if (self.master_fd) |fd| closeOwned(fd);
        self.child = .none;
        self.master_fd = null;
        self.started = false;

        std.debug.assert(self.master_fd == null);
        std.debug.assert(self.childPid() == null);
    }

    fn childPid(self: *const Self) ?posix.pid_t {
        return switch (self.child) {
            .none => null,
            .pending_session => |pid| pid,
            .live => |pid| pid,
            .reaped => |state| state.pid,
        };
    }

    /// Returns the live master descriptor for caller-managed poll sets.
    pub fn masterFd(self: *const Self) error{NotStarted}!posix.fd_t {
        return self.master_fd orelse error.NotStarted;
    }

    /// Observes child state without blocking and without closing the master.
    pub fn observeChild(self: *Self) ObserveError!ChildObservation {
        if (!self.started) return error.NotStarted;
        if (self.child == .reaped) return .{ .exited = self.child.reaped.exit };
        const pid = self.childPid() orelse return error.ObserveFailed;
        var status: c_int = 0;
        const result = while (true) {
            const waited = linux.waitpid(pid, &status, linux.W.NOHANG);
            if (classifyWaitPid(waited, pid) == .interrupted) continue;
            break waited;
        };
        return switch (classifyWaitPid(result, pid)) {
            .zero => .running,
            .expected => blk: {
                const exit = childObservation(status);
                self.child = .{ .reaped = .{ .pid = pid, .exit = exit.exited } };
                break :blk exit;
            },
            .child, .interrupted, .unexpected_success, .unexpected_error => error.ObserveFailed,
        };
    }

    fn awaitChildLaunch(status_fd: posix.fd_t) StartError!void {
        defer closeOwned(status_fd);
        var status: [1]u8 = undefined;
        while (true) {
            const n = linux.read(status_fd, &status, status.len);
            switch (classifyRawIo(n, status.len)) {
                // CLOEXEC closes the child writer atomically with successful exec.
                .zero => return,
                .success => |count| if (count == 1) return childLaunchError(status[0]) else return error.LaunchStatusFailed,
                .interrupted => continue,
                .oversized, .would_block, .fatal => return error.LaunchStatusFailed,
            }
        }
    }

    fn stopChild(self: *Self) void {
        switch (self.child) {
            .none => {},
            .pending_session => |pid| stopPendingChild(self, pid),
            .live => |pid| stopLiveChild(self, pid),
            .reaped => |state| stopLiveChild(self, state.pid),
        }
    }

    fn stopPendingChild(self: *Self, pid: posix.pid_t) void {
        std.debug.assert(pid > 0);
        requireCleanupSignal(sendSignal(pid, .terminate));
        if (waitChildWithDeadline(pid, stop_terminate_grace_ns)) {
            self.child = .none;
            return;
        }
        requireCleanupSignal(sendSignal(pid, .kill));
        waitChildBlocking(pid);
        self.child = .none;
    }

    fn stopLiveChild(self: *Self, pid: posix.pid_t) void {
        std.debug.assert(pid > 0);
        requireCleanupSignal(sendGroupSignal(pid, .hangup));
        if (waitChildWithDeadline(pid, stop_hangup_grace_ns) and
            waitProcessGroupMissing(pid, stop_hangup_grace_ns))
        {
            self.child = .none;
            return;
        }
        requireCleanupSignal(sendGroupSignal(pid, .terminate));
        if (waitChildWithDeadline(pid, stop_terminate_grace_ns) and
            waitProcessGroupMissing(pid, stop_terminate_grace_ns))
        {
            self.child = .none;
            return;
        }
        requireCleanupSignal(sendGroupSignal(pid, .kill));
        waitChildBlocking(pid);
        if (!waitProcessGroupMissing(pid, stop_terminate_grace_ns)) {
            @panic("PTY child process group survived SIGKILL");
        }
        self.child = .none;
    }

    /// Attempts one nonblocking write. The caller owns polling, retries,
    /// deadlines, and the unaccepted suffix.
    pub fn write(self: *Self, bytes: []const u8) WriteError!usize {
        const master = self.master_fd orelse return error.NotStarted;
        if (bytes.len == 0) return 0;
        return mapWriteResult(linux.write(master, bytes.ptr, bytes.len), bytes.len);
    }

    /// Reads available transport bytes into caller-owned storage.
    pub fn read(self: *Self, buf: []u8) ReadError!usize {
        if (!self.started) return error.NotStarted;
        const master_fd = self.master_fd orelse return error.NotStarted;
        if (buf.len == 0) return 0;

        return mapReadResult(linux.read(master_fd, buf.ptr, buf.len), buf.len);
    }

    /// Applies nonzero terminal dimensions to the active PTY.
    pub fn resize(self: *Self, cols: u16, rows: u16) ResizeError!void {
        if (self.master_fd == null) return error.NotStarted;
        if (cols == 0 or rows == 0) return error.InvalidDimensions;

        var winsize = posix.winsize{
            .row = rows,
            .col = cols,
            .xpixel = 0,
            .ypixel = 0,
        };
        const result = linux.ioctl(@intCast(self.master_fd.?), linux.T.IOCSWINSZ, @intFromPtr(&winsize));
        if (!ioctlSucceeded(result)) {
            return error.ResizeFailed;
        }
        self.last_cols = cols;
        self.last_rows = rows;
    }

    /// Deliver the signal assigned to one byte by the foreground PTY termios state.
    ///
    /// Returns false when ISIG is disabled, the byte has no enabled signal
    /// assignment, or the byte is not VINTR, VQUIT, or VSUSP.
    pub fn handleTermiosSignal(self: *Self, byte: u8) TermiosSignalError!bool {
        const master = self.master_fd orelse return error.NotStarted;
        var attributes: posix.termios = undefined;
        const termios_result = linux.tcgetattr(@intCast(master), @ptrCast(&attributes));
        if (linux.errno(termios_result) != .SUCCESS)
            return error.TermiosQueryFailed;
        if (!attributes.lflag.ISIG) return false;
        const signal_value: c_int = signal: {
            const controls = [_]struct { index: usize, signal: c_int }{
                .{ .index = @backingInt(posix.V.INTR), .signal = @backingInt(posix.SIG.INT) },
                .{ .index = @backingInt(posix.V.QUIT), .signal = @backingInt(posix.SIG.QUIT) },
                .{ .index = @backingInt(posix.V.SUSP), .signal = @backingInt(posix.SIG.TSTP) },
            };
            for (controls) |entry| {
                const assigned: u8 = attributes.cc[entry.index];
                if (assigned != control_character_disabled and assigned == byte)
                    break :signal entry.signal;
            }
            return false;
        };
        var foreground: posix.pid_t = undefined;
        const foreground_result = linux.tcgetpgrp(@intCast(master), &foreground);
        if (linux.errno(foreground_result) != .SUCCESS or foreground <= 0) return error.ForegroundGroupFailed;
        const linux_signal = checkedLinuxSignal(signal_value) orelse return error.SignalFailed;
        const signal_result = linux.kill(-foreground, linux_signal);
        if (linux.errno(signal_result) != .SUCCESS) return error.SignalFailed;
        return true;
    }

    /// Delivers one typed signal to the active child process group.
    pub fn signal(self: *Self, requested: Signal) SignalResult {
        if (self.child != .live) return .target_missing;
        const pid = self.childPid() orelse return .target_missing;
        return switch (sendGroupSignal(pid, requested)) {
            .delivered => .delivered,
            .target_missing => .target_missing,
            .permission_denied => .permission_denied,
            .native_signal_failed => .native_signal_failed,
        };
    }
};

// Linux descriptor, child-launch, and process-group mechanics.

fn childObservation(status: c_int) ChildObservation {
    const value: u32 = @intCast(status);
    if ((value & 0x7f) == 0) return .{ .exited = .{ .code = @intCast((value >> 8) & 0xff) } };
    return .{ .exited = .{ .signal = @intCast(value & 0x7f) } };
}

fn optionalZPtr(bytes: ?[:0]u8) ?[*:0]u8 {
    if (bytes) |value| {
        return @ptrFromInt(@intFromPtr(value.ptr));
    }
    return null;
}

// Linux releases the descriptor even when close reports EINTR; retrying could
// close a reused descriptor. Every other error denotes an ownership invariant.
fn closeOwned(fd: posix.fd_t) void {
    const result = linux.close(@intCast(fd));
    if (linux.errno(result) == .SUCCESS) return;
    switch (linux.errno(result)) {
        .INTR => {},
        .BADF => @panic("PTY descriptor closed twice"),
        else => @panic("PTY descriptor close failed"),
    }
}

fn requireCleanupSignal(result: SignalResult) void {
    switch (result) {
        .delivered, .target_missing => {},
        .permission_denied => @panic("PTY child cleanup signal permission denied"),
        .native_signal_failed => @panic("PTY child cleanup signal failed"),
    }
}

fn closeTransport(transport: Open) void {
    closeOwned(transport.master_fd);
    closeOwned(transport.slave_fd);
}

fn openLaunchStatusPipe() StartError!LaunchStatus {
    var fds = [_]c_int{ -1, -1 };
    if (linux.errno(linux.pipe(&fds)) != .SUCCESS) return error.LaunchStatusPipeFailed;
    errdefer {
        if (fds[0] >= 0) closeOwned(@intCast(fds[0]));
        if (fds[1] >= 0) closeOwned(@intCast(fds[1]));
    }

    setCloseOnExec(@intCast(fds[0])) catch return error.LaunchStatusPipeFailed;
    setCloseOnExec(@intCast(fds[1])) catch return error.LaunchStatusPipeFailed;
    return .{ .read_fd = @intCast(fds[0]), .write_fd = @intCast(fds[1]) };
}

fn closeLaunchStatusPipe(pipe: LaunchStatus) void {
    closeOwned(pipe.read_fd);
    closeOwned(pipe.write_fd);
}

fn setNonBlocking(fd: posix.fd_t) StartError!void {
    const flags_result = linux.fcntl(fd, linux.F.GETFL, 0);
    const flags = requireFcntl(flags_result) catch return error.OpenPtyFailed;
    const argument = checkedFcntlArgument(flags | linux_nonblock_flag) orelse return error.OpenPtyFailed;
    const set_result = linux.fcntl(fd, linux.F.SETFL, argument);
    ensureFcntl(set_result) catch return error.OpenPtyFailed;
}

fn setCloseOnExec(fd: posix.fd_t) StartError!void {
    const flags_result = linux.fcntl(fd, linux.F.GETFD, 0);
    const flags = requireFcntl(flags_result) catch return error.OpenPtyFailed;
    const argument = checkedFcntlArgument(flags | linux.FD_CLOEXEC) orelse return error.OpenPtyFailed;
    const set_result = linux.fcntl(fd, linux.F.SETFD, argument);
    ensureFcntl(set_result) catch return error.OpenPtyFailed;
}

fn requireExecutable(path: [:0]const u8) StartError!void {
    if (linux.errno(linux.access(path.ptr, linux.X_OK)) != .SUCCESS) return error.ShellUnavailable;
}

fn cArg(path: [*:0]const u8) [*c]u8 {
    return @ptrFromInt(@intFromPtr(path));
}

const ChildProcessFds = struct {
    master_fd: posix.fd_t,
    slave_fd: posix.fd_t,
};

fn resetChildSignalDispositions() bool {
    var sa: posix.Sigaction = .{
        .handler = .{ .handler = posix.SIG.DFL },
        .mask = posix.sigemptyset(),
        .flags = 0,
    };
    inline for (.{
        posix.SIG.ABRT, posix.SIG.ALRM, posix.SIG.BUS,  posix.SIG.CHLD,
        posix.SIG.FPE,  posix.SIG.HUP,  posix.SIG.ILL,  posix.SIG.INT,
        posix.SIG.PIPE, posix.SIG.QUIT, posix.SIG.SEGV, posix.SIG.TERM,
        posix.SIG.TRAP,
    }) |signal| {
        if (posix.system.sigaction(signal, @ptrCast(&sa), null) != 0) return false;
    }
    return true;
}

fn closeChildFdIfNeeded(fd: posix.fd_t) bool {
    if (fd <= 2) return true;
    const result = linux.close(@intCast(fd));
    if (linux.errno(result) == .SUCCESS) return true;
    // Linux has consumed the descriptor even when close reports EINTR.
    return linux.errno(result) == .INTR;
}

fn setupChildProcessFds(fds: ChildProcessFds, status_fd: posix.fd_t) void {
    if (!resetChildSignalDispositions() or linux.errno(linux.setsid()) != .SUCCESS) childLaunchExit(status_fd, .session);
    if (linux.errno(linux.ioctl(@intCast(fds.slave_fd), linux.T.IOCSCTTY, 0)) != .SUCCESS or
        linux.errno(linux.dup2(fds.slave_fd, 0)) != .SUCCESS or linux.errno(linux.dup2(fds.slave_fd, 1)) != .SUCCESS or
        linux.errno(linux.dup2(fds.slave_fd, 2)) != .SUCCESS or !closeChildFdIfNeeded(fds.master_fd) or
        !closeChildFdIfNeeded(fds.slave_fd))
    {
        childLaunchExit(status_fd, .stdio);
    }
}

fn childLaunchExit(status_fd: posix.fd_t, failure: ChildLaunchFailure) noreturn {
    var byte: [1]u8 = .{@backingInt(failure)};
    while (true) {
        const n = linux.write(status_fd, &byte, byte.len);
        if (linux.errno(n) == .SUCCESS and n == 1) linux.exit(127);
        switch (linux.errno(n)) {
            .INTR => continue,
            else => linux.exit(127),
        }
    }
}

fn childProcess(
    master_fd: posix.fd_t,
    slave_fd: posix.fd_t,
    status_fd: posix.fd_t,
    shell_path: [:0]const u8,
    command: ?[*:0]const u8,
    cwd: ?[*:0]const u8,
    environment: [*]const ?[*:0]u8,
) noreturn {
    setupChildProcessFds(.{
        .master_fd = master_fd,
        .slave_fd = slave_fd,
    }, status_fd);

    if (cwd) |dir| {
        if (linux.errno(linux.chdir(dir)) != .SUCCESS) childLaunchExit(status_fd, .cwd);
    }

    if (command) |cmd| {
        const argv = [_:null][*c]u8{ cArg(shell_path.ptr), cArg("-c"), cArg(cmd) };
        const envp: [*c]const [*c]u8 = @ptrCast(environment);
        if (linux.errno(linux.execve(shell_path.ptr, @ptrCast(argv[0..].ptr), @ptrCast(envp))) != .SUCCESS) childLaunchExit(status_fd, .exec);
        childLaunchExit(status_fd, .exec);
    }

    const argv = [_:null][*c]u8{ cArg(shell_path.ptr), cArg("-i") };
    const envp: [*c]const [*c]u8 = @ptrCast(environment);
    if (linux.errno(linux.execve(shell_path.ptr, @ptrCast(argv[0..].ptr), @ptrCast(envp))) != .SUCCESS) childLaunchExit(status_fd, .exec);
    childLaunchExit(status_fd, .exec);
}

fn waitChildNoHang(pid: posix.pid_t) enum { alive, reaped, failed } {
    std.debug.assert(pid > 0);
    var status: c_int = 0;
    while (true) {
        const res = linux.waitpid(pid, &status, linux.W.NOHANG);
        switch (classifyWaitPid(res, pid)) {
            .zero => return .alive,
            .expected => return .reaped,
            .interrupted => continue,
            .child => return .reaped,
            .unexpected_success, .unexpected_error => return .failed,
        }
    }
}

fn waitChildWithDeadline(pid: posix.pid_t, timeout_ns: u64) bool {
    std.debug.assert(pid > 0);
    const wait_slices = @max(1, timeout_ns / stop_wait_slice_ns);
    var slice_index: u64 = 0;
    while (slice_index < wait_slices) : (slice_index += 1) {
        switch (waitChildNoHang(pid)) {
            .alive => {},
            .reaped => return true,
            .failed => @panic("PTY bounded child wait failed"),
        }
        sleepStopSlice();
    }
    return switch (waitChildNoHang(pid)) {
        .alive => false,
        .reaped => true,
        .failed => @panic("PTY final child wait failed"),
    };
}

fn waitChildBlocking(pid: posix.pid_t) void {
    std.debug.assert(pid > 0);
    var status: c_int = 0;
    while (true) {
        const res = linux.waitpid(pid, &status, 0);
        switch (classifyWaitPid(res, pid)) {
            .expected, .child => return,
            .interrupted => continue,
            .zero, .unexpected_success, .unexpected_error => @panic("PTY child wait failed"),
        }
    }
}

fn waitProcessGroupMissing(pid: posix.pid_t, timeout_ns: u64) bool {
    std.debug.assert(pid > 0);
    return waitSignalTargetMissing(-pid, timeout_ns);
}

fn waitSignalTargetMissing(target: posix.pid_t, timeout_ns: u64) bool {
    const wait_slices = @max(1, timeout_ns / stop_wait_slice_ns);
    var slice_index: u64 = 0;
    while (slice_index < wait_slices) : (slice_index += 1) {
        if (!signalTargetExists(target)) return true;
        sleepStopSlice();
    }
    return !signalTargetExists(target);
}

fn signalTargetExists(target: posix.pid_t) bool {
    while (true) {
        const signal = checkedLinuxSignal(0) orelse return true;
        const res = linux.kill(target, signal);
        if (linux.errno(res) == .SUCCESS) return true;
        switch (linux.errno(res)) {
            .INTR => continue,
            .SRCH => return false,
            else => return true,
        }
    }
}

fn sendSignal(pid: posix.pid_t, signal: Signal) SignalResult {
    return sendSignalTarget(pid, signal);
}

fn sendGroupSignal(pid: posix.pid_t, signal: Signal) SignalResult {
    std.debug.assert(pid > 0);
    return sendSignalTarget(-pid, signal);
}

fn sendSignalTarget(target: posix.pid_t, signal: Signal) SignalResult {
    while (true) {
        const linux_signal = checkedLinuxSignal(signal.native()) orelse return .native_signal_failed;
        const res = linux.kill(target, linux_signal);
        if (linux.errno(res) == .SUCCESS) return .delivered;
        switch (linux.errno(res)) {
            .INTR => continue,
            .SRCH => return .target_missing,
            .PERM => return .permission_denied,
            else => return .native_signal_failed,
        }
    }
}

fn sleepStopSlice() void {
    const microseconds = @as(u128, stop_wait_slice_ns / std.time.ns_per_us);
    const request = timespecFromMicroseconds(microseconds) orelse @panic("PTY cleanup clock duration overflow");
    // Preserve the prior one-shot usleep owner: interruption completes this
    // cleanup slice early instead of extending the stop deadline.
    consumeSleepResult(linux.nanosleep(&request, null));
}

const test_cols: u16 = 80;
const test_rows: u16 = 24;
const test_wait_ms: i32 = 100;
const test_waits_max: u8 = 50;
const test_environment = ChildEnvironment{ .term = "xterm-256color", .colorterm = "truecolor" };

fn expectOutput(owned: *Owned, expected: []const u8) !void {
    var buffer: [512]u8 = undefined;
    var used: usize = 0;
    var waits: u8 = 0;
    while (waits < test_waits_max) : (waits += 1) {
        var descriptor = [_]posix.pollfd{.{ .fd = try owned.masterFd(), .events = posix.POLL.IN | posix.POLL.HUP, .revents = 0 }};
        const ready = try posix.poll(&descriptor, test_wait_ms);
        if (ready == 0) continue;
        const count = owned.read(buffer[used..]) catch |failure| switch (failure) {
            error.EndOfStream, error.NotStarted => break,
            error.Interrupted, error.WouldBlock => continue,
            error.ReadFailed => return failure,
        };
        used += count;
        if (std.mem.indexOf(u8, buffer[0..used], expected) != null) return;
        if (used == buffer.len) return error.TestBufferFull;
    }
    return error.TestTimeout;
}

fn descriptorCount() !usize {
    const directory = try std.Io.Dir.openDirAbsolute(std.testing.io, "/proc/self/fd", .{ .iterate = true });
    defer directory.close(std.testing.io);
    var entries = directory.iterate();
    var count: usize = 0;
    while (try entries.next(std.testing.io)) |_| count += 1;
    return count;
}

fn initAllocation(allocator: std.mem.Allocator) !void {
    var owned = try Owned.init(allocator, "/bin/sh", "printf allocation", "/tmp", test_environment);
    owned.deinit();
}

fn environmentAllocation(allocator: std.mem.Allocator) !void {
    var environment = try LaunchEnvironment.init(
        allocator,
        &.{ "PATH=/bin", "TERM=dumb", "HOWL_RETAINED=yes" },
        test_environment,
    );
    environment.deinit();
}

fn expectEnvironmentEntry(environment: *const LaunchEnvironment, index: usize, expected: []const u8) !void {
    try std.testing.expectEqualStrings(expected, std.mem.span(environment.entries[index].?));
}

test "initialization releases every partial allocation" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    try std.testing.checkAllAllocationFailures(std.testing.allocator, initAllocation, .{});
}

test "launch environment replaces identities and owns one immutable snapshot" {
    var inherited_term = [_]u8{ 'T', 'E', 'R', 'M', '=', 'd', 'u', 'm', 'b' };
    var selected_term = [_]u8{ 'x', 't', 'e', 'r', 'm', '-', '2', '5', '6', 'c', 'o', 'l', 'o', 'r' };
    var environment = try LaunchEnvironment.init(
        std.testing.allocator,
        &.{ "A=one", &inherited_term, "COLORTERM=old", "TERM=duplicate", "B=two" },
        .{ .term = &selected_term, .colorterm = "truecolor" },
    );
    defer environment.deinit();

    @memset(&inherited_term, 'x');
    @memset(&selected_term, 'y');
    try std.testing.expectEqual(@as(usize, 4), environment.entries.len - 1);
    try expectEnvironmentEntry(&environment, 0, "A=one");
    try expectEnvironmentEntry(&environment, 1, "B=two");
    try expectEnvironmentEntry(&environment, 2, "TERM=xterm-256color");
    try expectEnvironmentEntry(&environment, 3, "COLORTERM=truecolor");
    try std.testing.expectEqual(@as(?[*:0]u8, null), environment.entries[4]);
}

test "launch environment handles absent identities and optional color identity" {
    var environment = try LaunchEnvironment.init(
        std.testing.allocator,
        &.{ "PATH=/bin", "COLORTERM=inherited" },
        .{ .term = "xterm-256color", .colorterm = null },
    );
    defer environment.deinit();
    try std.testing.expectEqual(@as(usize, 2), environment.entries.len - 1);
    try expectEnvironmentEntry(&environment, 0, "PATH=/bin");
    try expectEnvironmentEntry(&environment, 1, "TERM=xterm-256color");
}

test "launch environment rejects malformed and bounded input transactionally" {
    try std.testing.expectError(
        error.InvalidEnvironment,
        LaunchEnvironment.init(std.testing.allocator, &.{"BROKEN"}, test_environment),
    );
    try std.testing.expectError(
        error.InvalidEnvironment,
        LaunchEnvironment.init(std.testing.allocator, &.{"=value"}, test_environment),
    );
    try std.testing.expectError(
        error.InvalidEnvironment,
        LaunchEnvironment.init(std.testing.allocator, &.{"BAD=a\x00b"}, test_environment),
    );
    try std.testing.expectError(
        error.InvalidEnvironment,
        LaunchEnvironment.init(
            std.testing.allocator,
            &.{"PATH=/bin"},
            .{ .term = "bad=value", .colorterm = null },
        ),
    );

    const inherited = try std.testing.allocator.alloc([]const u8, environment_max_entries);
    defer std.testing.allocator.free(inherited);
    @memset(inherited, "A=1");
    var count_boundary = try LaunchEnvironment.init(
        std.testing.allocator,
        inherited[0 .. environment_max_entries - 1],
        .{ .term = "xterm-256color", .colorterm = null },
    );
    try std.testing.expectEqual(environment_max_entries + 1, count_boundary.entries.len);
    count_boundary.deinit();
    try std.testing.expectError(
        error.EnvironmentCountLimit,
        LaunchEnvironment.init(std.testing.allocator, inherited, test_environment),
    );

    const term_prefix_bytes = "TERM=".len + 1;
    const byte_boundary = try std.testing.allocator.alloc(u8, environment_max_bytes - term_prefix_bytes);
    defer std.testing.allocator.free(byte_boundary);
    @memset(byte_boundary, 'x');
    var byte_environment = try LaunchEnvironment.init(
        std.testing.allocator,
        &.{},
        .{ .term = byte_boundary, .colorterm = null },
    );
    try std.testing.expectEqual(environment_max_bytes, byte_environment.bytes.len);
    byte_environment.deinit();

    const oversized = try std.testing.allocator.alloc(u8, byte_boundary.len + 1);
    defer std.testing.allocator.free(oversized);
    @memset(oversized, 'x');
    try std.testing.expectError(
        error.EnvironmentByteLimit,
        LaunchEnvironment.init(
            std.testing.allocator,
            &.{},
            .{ .term = oversized, .colorterm = null },
        ),
    );
}

test "launch environment releases both allocations under every failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, environmentAllocation, .{});
}

test "child receives selected identities and retained environment across restart" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    var owned = try Owned.initInherited(
        std.testing.allocator,
        "/bin/sh",
        "printf '%s|%s|%s' \"$TERM\" \"$COLORTERM\" \"$HOWL_RETAINED\"",
        null,
        test_environment,
        &.{ "TERM=dumb", "COLORTERM=old", "HOWL_RETAINED=kept", "PATH=/bin:/usr/bin" },
    );
    defer owned.deinit();
    try owned.start(test_cols, test_rows);
    try expectOutput(&owned, "xterm-256color|truecolor|kept");
    owned.stop();
    try owned.start(test_cols, test_rows);
    try expectOutput(&owned, "xterm-256color|truecolor|kept");
}

test "idle owner rejects descriptors and dimensions before start" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    var owned = try Owned.init(std.testing.allocator, "/bin/sh", "cat", null, test_environment);
    defer owned.deinit();
    var buffer: [16]u8 = undefined;
    try std.testing.expectError(error.NotStarted, owned.masterFd());
    try std.testing.expectError(error.NotStarted, owned.read(&buffer));
    try std.testing.expectError(error.NotStarted, owned.resize(test_cols, test_rows));
    try std.testing.expectEqual(SignalResult.target_missing, owned.signal(.interrupt));
    try std.testing.expectError(error.NotStarted, owned.write("hello"));
    try std.testing.expectError(error.InvalidDimensions, owned.start(0, test_rows));
}

test "start rejects unavailable and duplicate child transitions without descriptor leaks" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const before = try descriptorCount();
    var unavailable = try Owned.init(
        std.testing.allocator,
        "/definitely/missing/howl-shell",
        null,
        null,
        test_environment,
    );
    try std.testing.expectError(error.ShellUnavailable, unavailable.start(test_cols, test_rows));
    unavailable.deinit();
    try std.testing.expectEqual(before, try descriptorCount());

    var invalid_cwd = try Owned.init(
        std.testing.allocator,
        "/bin/sh",
        null,
        "/definitely/missing/howl-cwd",
        test_environment,
    );
    try std.testing.expectError(error.ChildCwdFailed, invalid_cwd.start(test_cols, test_rows));
    invalid_cwd.deinit();
    try std.testing.expectEqual(before, try descriptorCount());

    // A searchable executable directory passes access(X_OK) but cannot execve.
    var unlaunchable = try Owned.init(std.testing.allocator, "/tmp", null, null, test_environment);
    try std.testing.expectError(error.ChildExecFailed, unlaunchable.start(test_cols, test_rows));
    unlaunchable.deinit();
    try std.testing.expectEqual(before, try descriptorCount());

    var owned = try Owned.init(std.testing.allocator, "/bin/sh", "sleep 30", null, test_environment);
    defer owned.deinit();
    try owned.start(test_cols, test_rows);
    try std.testing.expectError(error.AlreadyStarted, owned.start(test_cols, test_rows));
}

test "resize write and process-group signal share one owner" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const command =
        "trap 'printf interrupted; exit 0' INT; printf ready; read line; " ++
        "stty size; printf '%s' \"$line\"; while :; do sleep 1; done";
    var owned = try Owned.init(std.testing.allocator, "/bin/sh", command, null, test_environment);
    defer owned.deinit();
    try owned.start(test_cols, test_rows);
    try expectOutput(&owned, "ready");
    try std.testing.expectError(error.InvalidDimensions, owned.resize(0, test_rows));
    try owned.resize(100, 40);
    try std.testing.expectEqual(@as(usize, 6), try owned.write("hello\n"));
    try expectOutput(&owned, "40 100");
    try std.testing.expectEqual(SignalResult.delivered, owned.signal(.interrupt));
    try expectOutput(&owned, "interrupted");
}

test "foreground termios assignments route exact bytes to process-group signals" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const command =
        "stty intr '^X' quit '^Y' susp '^Z'; " ++
        "trap 'printf interrupt' INT; trap 'printf quit' QUIT; trap 'printf suspend' TSTP; " ++
        "printf ready; while :; do sleep 1; done";
    var owned = try Owned.init(std.testing.allocator, "/bin/sh", command, null, test_environment);
    defer owned.deinit();
    try std.testing.expectError(error.NotStarted, owned.handleTermiosSignal(0x18));
    try owned.start(test_cols, test_rows);
    try expectOutput(&owned, "ready");
    try std.testing.expect(!(try owned.handleTermiosSignal('a')));
    try std.testing.expect(try owned.handleTermiosSignal(0x18));
    try expectOutput(&owned, "interrupt");
    try std.testing.expect(try owned.handleTermiosSignal(0x19));
    try expectOutput(&owned, "quit");
    try std.testing.expect(try owned.handleTermiosSignal(0x1a));
    try expectOutput(&owned, "suspend");

    var disabled = try Owned.init(
        std.testing.allocator,
        "/bin/sh",
        "stty -isig; printf ready; sleep 30",
        null,
        test_environment,
    );
    defer disabled.deinit();
    try disabled.start(test_cols, test_rows);
    try expectOutput(&disabled, "ready");
    try std.testing.expect(!(try disabled.handleTermiosSignal(0x18)));
}

test "failed termios query preserves owner state and delivers no signal" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    var owned = try Owned.init(std.testing.allocator, "/bin/sh", "trap 'printf trapped' INT; printf ready; sleep 30", null, test_environment);
    defer owned.deinit();
    try owned.start(test_cols, test_rows);
    try expectOutput(&owned, "ready");

    const master = owned.master_fd.?;
    const child = owned.child;
    var configured_termios: posix.termios = undefined;
    try std.testing.expectEqual(
        linux.E.SUCCESS,
        linux.errno(linux.tcgetattr(@intCast(master), @ptrCast(&configured_termios))),
    );
    const configured_interrupt = configured_termios.cc[@backingInt(posix.V.INTR)];
    try std.testing.expect(configured_interrupt != control_character_disabled);
    var pipe_fds = [_]c_int{ -1, -1 };
    try std.testing.expectEqual(std.os.linux.E.SUCCESS, linux.errno(linux.pipe(&pipe_fds)));
    defer {
        closeOwned(@intCast(pipe_fds[0]));
        closeOwned(@intCast(pipe_fds[1]));
    }
    {
        owned.master_fd = @intCast(pipe_fds[0]);
        defer owned.master_fd = master;
        try std.testing.expectError(error.TermiosQueryFailed, owned.handleTermiosSignal(configured_interrupt));
    }
    try std.testing.expectEqual(child, owned.child);
    var descriptor = [1]posix.pollfd{.{ .fd = master, .events = posix.POLL.IN, .revents = 0 }};
    for (0..8) |_| {
        descriptor[0].revents = 0;
        try std.testing.expectEqual(@as(usize, 0), try posix.poll(&descriptor, 25));
        try std.testing.expectEqual(ChildObservation.running, try owned.observeChild());
    }
}

test "translated syscall census is migrated while openpty remains" {
    var input_speed: CTermiosInputSpeed = undefined;
    var output_speed: CTermiosOutputSpeed = undefined;
    try std.testing.expectEqual(@intFromPtr(&input_speed), @intFromPtr(&input_speed.c_ispeed));
    try std.testing.expectEqual(@intFromPtr(&output_speed), @intFromPtr(&output_speed.c_ospeed));
    const source = @embedFile("howl_pty.zig");
    inline for (.{
        "FD_CLOEXEC", "F_GETFD",    "F_GETFL",         "F_SETFD",        "F_SETFL",        "WNOHANG",   "X_OK",
        "TIOCSCTTY",  "TIOCSWINSZ", "ISIG",            "SIGINT",         "SIGQUIT",        "SIGTSTP",   "VINTR",
        "VQUIT",      "VSUSP",      "_POSIX_VDISABLE", "struct_termios", "struct_winsize", "access",    "chdir",
        "close",      "dup2",       "execve",          "fcntl",          "fork",           "ioctl",     "kill",
        "pipe",       "read",       "setsid",          "sigaction",      "tcgetattr",      "tcgetpgrp", "waitpid",
        "write",
    }) |name| {
        var token: [64]u8 = undefined;
        const rendered = try std.fmt.bufPrint(&token, "c.{s}", .{name});
        try std.testing.expect(std.mem.indexOf(u8, source, rendered) == null);
    }
    var openpty_token: [32]u8 = undefined;
    const rendered_openpty = try std.fmt.bufPrint(&openpty_token, "c.{s}", .{"openpty("});
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, source, rendered_openpty));
}

test "raw syscall classifiers preserve bounded owner dispositions" {
    const LibcFork = *const fn () callconv(.c) c_int;
    const LibcSigaction = *const fn (
        posix.SIG,
        noalias ?*const posix.Sigaction,
        noalias ?*posix.Sigaction,
    ) callconv(.c) c_int;
    const libc_fork_surface: LibcFork = posix.system.fork;
    const libc_sigaction_surface: LibcSigaction = posix.system.sigaction;
    const LinuxExit = *const fn (i32) noreturn;
    const LinuxNanosleep = *const fn (*const linux.timespec, ?*linux.timespec) usize;
    const linux_exit_surface: LinuxExit = linux.exit;
    const linux_nanosleep_surface: LinuxNanosleep = linux.nanosleep;
    try std.testing.expectEqual(@intFromPtr(&posix.system.fork), @intFromPtr(libc_fork_surface));
    try std.testing.expectEqual(@intFromPtr(&posix.system.sigaction), @intFromPtr(libc_sigaction_surface));
    try std.testing.expectEqual(@intFromPtr(&linux.exit), @intFromPtr(linux_exit_surface));
    try std.testing.expectEqual(@intFromPtr(&linux.nanosleep), @intFromPtr(linux_nanosleep_surface));

    try std.testing.expectEqual(@as(usize, 4), try mapReadResult(4, 8));
    try std.testing.expectError(error.EndOfStream, mapReadResult(0, 8));
    try std.testing.expectError(error.ReadFailed, mapReadResult(9, 8));
    try std.testing.expectError(error.WouldBlock, mapReadResult(syntheticErrno(.AGAIN), 8));
    try std.testing.expectError(error.Interrupted, mapReadResult(syntheticErrno(.INTR), 8));
    try std.testing.expectError(error.EndOfStream, mapReadResult(syntheticErrno(.IO), 8));
    try std.testing.expectError(error.ReadFailed, mapReadResult(syntheticErrno(.BADF), 8));

    try std.testing.expectEqual(@as(usize, 4), try mapWriteResult(4, 8));
    try std.testing.expectError(error.ChildClosed, mapWriteResult(0, 8));
    try std.testing.expectError(error.WriteFailed, mapWriteResult(9, 8));
    try std.testing.expectError(error.WouldBlock, mapWriteResult(syntheticErrno(.AGAIN), 8));
    try std.testing.expectError(error.Interrupted, mapWriteResult(syntheticErrno(.INTR), 8));
    try std.testing.expectError(error.ChildClosed, mapWriteResult(syntheticErrno(.IO), 8));
    try std.testing.expectError(error.ChildClosed, mapWriteResult(syntheticErrno(.PIPE), 8));
    try std.testing.expectError(error.WriteFailed, mapWriteResult(syntheticErrno(.BADF), 8));

    try std.testing.expectEqual(RawIoResult{ .success = 4 }, classifyRawIo(4, 8));
    try std.testing.expectEqual(RawIoResult.zero, classifyRawIo(0, 8));
    try std.testing.expectEqual(RawIoResult{ .oversized = 9 }, classifyRawIo(9, 8));

    try std.testing.expectEqual(FcntlResult{ .success = 7 }, classifyFcntl(7));
    try std.testing.expectEqual(FcntlResult{ .errno = .BADF }, classifyFcntl(syntheticErrno(.BADF)));
    try std.testing.expectEqual(FcntlResult{ .out_of_range = @as(usize, std.math.maxInt(c_int)) + 1 }, classifyFcntl(@as(usize, std.math.maxInt(c_int)) + 1));
    try std.testing.expectError(error.OpenPtyFailed, requireFcntl(syntheticErrno(.BADF)));
    try std.testing.expectError(error.OpenPtyFailed, requireFcntl(@as(usize, std.math.maxInt(c_int)) + 1));
    try std.testing.expectEqual(@as(c_int, 7), try requireFcntl(7));
    try ensureFcntl(7);
    try std.testing.expectEqual(@as(?usize, 7), checkedFcntlArgument(7));
    try std.testing.expectEqual(@as(?usize, null), checkedFcntlArgument(-1));
    try std.testing.expectError(error.OpenPtyFailed, ensureFcntl(syntheticErrno(.BADF)));
    try std.testing.expectError(error.OpenPtyFailed, ensureFcntl(@as(usize, std.math.maxInt(c_int)) + 1));

    try std.testing.expect(ioctlSucceeded(0));
    try std.testing.expect(!ioctlSucceeded(syntheticErrno(.BADF)));

    try std.testing.expectEqual(WaitPidResult.zero, classifyWaitPid(0, 42));
    try std.testing.expectEqual(WaitPidResult.expected, classifyWaitPid(42, 42));
    try std.testing.expectEqual(WaitPidResult.interrupted, classifyWaitPid(syntheticErrno(.INTR), 42));
    try std.testing.expectEqual(WaitPidResult.child, classifyWaitPid(syntheticErrno(.CHILD), 42));
    try std.testing.expectEqual(WaitPidResult.unexpected_success, classifyWaitPid(43, 42));
    try std.testing.expectEqual(WaitPidResult.unexpected_error, classifyWaitPid(syntheticErrno(.BADF), 42));

    try std.testing.expectEqual(@as(?linux.SIG, @fromBackingInt(@intCast(0))), checkedLinuxSignal(0));
    try std.testing.expectEqual(@as(?linux.SIG, .INT), checkedLinuxSignal(2));
    try std.testing.expectEqual(@as(?linux.SIG, null), checkedLinuxSignal(-1));
    try std.testing.expectEqual(@as(?linux.SIG, null), checkedLinuxSignal(65));
}

test "child exit and cleanup sleep retain bounded conversion semantics" {
    try std.testing.expectEqual(SleepResult.success, classifySleepResult(0));
    try std.testing.expectEqual(SleepResult.interrupted, classifySleepResult(syntheticErrno(.INTR)));
    try std.testing.expectEqual(SleepResult.failure, classifySleepResult(syntheticErrno(.BADF)));
    consumeSleepResult(0);
    consumeSleepResult(syntheticErrno(.INTR));
    try std.testing.expectEqual(linux.timespec{ .sec = 0, .nsec = 0 }, timespecFromMicroseconds(0).?);
    try std.testing.expectEqual(linux.timespec{ .sec = 1, .nsec = 500_000_000 }, timespecFromMicroseconds(1_500_000).?);
    const overflowing_seconds = @as(u128, @intCast(std.math.maxInt(isize))) + 1;
    try std.testing.expect(timespecFromMicroseconds(overflowing_seconds * std.time.us_per_s) == null);
    const source = @embedFile("howl_pty.zig");
    var exit_token: [32]u8 = undefined;
    var sleep_token: [32]u8 = undefined;
    const rendered_exit = try std.fmt.bufPrint(&exit_token, "c.{s}", .{"_exit"});
    const rendered_sleep = try std.fmt.bufPrint(&sleep_token, "c.{s}", .{"usleep"});
    try std.testing.expect(std.mem.indexOf(u8, source, rendered_exit) == null);
    try std.testing.expect(std.mem.indexOf(u8, source, rendered_sleep) == null);
}

test "failed ioctl preserves accepted dimensions" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    var owned = try Owned.init(std.testing.allocator, "/bin/sh", null, null, test_environment);
    defer owned.deinit();
    owned.master_fd = -1;
    defer owned.master_fd = null;
    try std.testing.expectError(error.ResizeFailed, owned.resize(test_cols, test_rows));
    try std.testing.expectEqual(@as(u16, 0), owned.last_cols);
    try std.testing.expectEqual(@as(u16, 0), owned.last_rows);
}

test "multiple owners interleave output through one caller poll set" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    var first = try Owned.init(std.testing.allocator, "/bin/sh", "printf first; sleep 1", null, test_environment);
    defer first.deinit();
    var second = try Owned.init(std.testing.allocator, "/bin/sh", "printf second; sleep 1", null, test_environment);
    defer second.deinit();
    try first.start(test_cols, test_rows);
    try second.start(test_cols, test_rows);
    const first_fd = try first.masterFd();
    const second_fd = try second.masterFd();
    try std.testing.expect(first_fd != second_fd);
    var first_seen = false;
    var second_seen = false;
    var first_bytes: [64]u8 = undefined;
    var second_bytes: [64]u8 = undefined;
    var first_len: usize = 0;
    var second_len: usize = 0;
    var rounds: u8 = 0;
    while ((!first_seen or !second_seen) and rounds < test_waits_max) : (rounds += 1) {
        var descriptors = [_]posix.pollfd{
            .{ .fd = first_fd, .events = posix.POLL.IN | posix.POLL.HUP, .revents = 0 },
            .{ .fd = second_fd, .events = posix.POLL.IN | posix.POLL.HUP, .revents = 0 },
        };
        const ready = try posix.poll(&descriptors, test_wait_ms);
        try std.testing.expect(ready >= 0);
        if (descriptors[0].revents != 0) {
            first_len += first.read(first_bytes[first_len..]) catch |failure| switch (failure) {
                error.WouldBlock => 0,
                error.EndOfStream => 0,
                else => return failure,
            };
            first_seen = std.mem.indexOf(u8, first_bytes[0..first_len], "first") != null;
        }
        if (descriptors[1].revents != 0) {
            second_len += second.read(second_bytes[second_len..]) catch |failure| switch (failure) {
                error.WouldBlock => 0,
                error.EndOfStream => 0,
                else => return failure,
            };
            second_seen = std.mem.indexOf(u8, second_bytes[0..second_len], "second") != null;
        }
    }
    try std.testing.expect(first_seen and second_seen);
    first.stop();
    try std.testing.expectError(error.NotStarted, first.masterFd());
}

test "nonblocking write preserves empty and partial outcomes for caller retry" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    var owned = try Owned.init(std.testing.allocator, "/bin/sh", "stty raw -echo; kill -STOP $$", null, test_environment);
    defer owned.deinit();
    try owned.start(test_cols, test_rows);
    try std.testing.expectEqual(@as(usize, 0), try owned.write(""));
    const bytes = try std.testing.allocator.alloc(u8, 8 * 1024 * 1024);
    defer std.testing.allocator.free(bytes);
    @memset(bytes, 'w');
    const accepted_initial = try owned.write(bytes);
    try std.testing.expect(accepted_initial > 0 and accepted_initial < bytes.len);
    var accepted_stopped = accepted_initial;
    var saw_would_block = false;
    for (0..256) |_| {
        const count = owned.write(bytes[accepted_stopped..]) catch |failure| switch (failure) {
            error.WouldBlock => {
                saw_would_block = true;
                break;
            },
            error.Interrupted => continue,
            else => return failure,
        };
        try std.testing.expect(count > 0);
        accepted_stopped += count;
        try std.testing.expect(accepted_stopped < bytes.len);
    }
    try std.testing.expect(saw_would_block);

    var draining = try Owned.init(std.testing.allocator, "/bin/sh", "cat >/dev/null", null, test_environment);
    defer draining.deinit();
    try draining.start(test_cols, test_rows);
    const retry_bytes = bytes[0 .. 64 * 1024];
    var accepted: usize = 0;
    var attempts: u8 = 0;
    while (accepted < retry_bytes.len and attempts < 100) : (attempts += 1) {
        const count = draining.write(retry_bytes[accepted..]) catch |failure| switch (failure) {
            error.WouldBlock, error.Interrupted => 0,
            else => return failure,
        };
        accepted += count;
        if (count == 0) {
            var descriptor = [_]posix.pollfd{.{ .fd = try draining.masterFd(), .events = posix.POLL.OUT | posix.POLL.HUP, .revents = 0 }};
            const ready = try posix.poll(&descriptor, test_wait_ms);
            try std.testing.expect(ready >= 0);
        }
    }
    try std.testing.expectEqual(retry_bytes.len, accepted);
}

test "child observation distinguishes running normal exit and signal exit while draining" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    var normal = try Owned.init(std.testing.allocator, "/bin/sh", "printf final; exit 7", null, test_environment);
    defer normal.deinit();
    try normal.start(test_cols, test_rows);
    var normal_exit: ?ChildObservation = null;
    var rounds: u8 = 0;
    while (normal_exit == null and rounds < test_waits_max) : (rounds += 1) {
        normal_exit = switch (try normal.observeChild()) {
            .running => null,
            .exited => |status| .{ .exited = status },
        };
        if (normal_exit == null) {
            var descriptor = [_]posix.pollfd{.{ .fd = try normal.masterFd(), .events = posix.POLL.IN | posix.POLL.HUP, .revents = 0 }};
            const ready = try posix.poll(&descriptor, 1);
            try std.testing.expect(ready >= 0);
            sleepStopSlice();
        }
    }
    try std.testing.expectEqual(ChildObservation{ .exited = .{ .code = 7 } }, normal_exit.?);
    try std.testing.expectEqual(ChildObservation{ .exited = .{ .code = 7 } }, try normal.observeChild());
    var buffer: [64]u8 = undefined;
    var used: usize = 0;
    var saw_final = false;
    var drain_rounds: u8 = 0;
    while (!saw_final and used < buffer.len and drain_rounds < test_waits_max) : (drain_rounds += 1) {
        const count = normal.read(buffer[used..]) catch |failure| switch (failure) {
            error.WouldBlock, error.Interrupted => {
                var descriptor = [_]posix.pollfd{.{ .fd = try normal.masterFd(), .events = posix.POLL.IN | posix.POLL.HUP, .revents = 0 }};
                const ready = try posix.poll(&descriptor, test_wait_ms);
                try std.testing.expect(ready >= 0);
                continue;
            },
            error.EndOfStream => break,
            else => return failure,
        };
        used += count;
        saw_final = std.mem.indexOf(u8, buffer[0..used], "final") != null;
    }
    try std.testing.expect(saw_final);

    var signaled = try Owned.init(std.testing.allocator, "/bin/sh", "sleep 30", null, test_environment);
    defer signaled.deinit();
    try signaled.start(test_cols, test_rows);
    try std.testing.expectEqual(SignalResult.delivered, signaled.signal(.terminate));
    var signaled_exit: ?ChildObservation = null;
    rounds = 0;
    while (signaled_exit == null and rounds < test_waits_max) : (rounds += 1) {
        signaled_exit = switch (try signaled.observeChild()) {
            .running => null,
            .exited => |status| .{ .exited = status },
        };
        if (signaled_exit == null) {
            var descriptor = [_]posix.pollfd{.{ .fd = try signaled.masterFd(), .events = posix.POLL.HUP, .revents = 0 }};
            const ready = try posix.poll(&descriptor, 1);
            try std.testing.expect(ready >= 0);
            sleepStopSlice();
        }
    }
    try std.testing.expectEqual(ChildObservation{ .exited = .{ .signal = 15 } }, signaled_exit.?);
}
