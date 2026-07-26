//! Owns one Linux PTY, its child process group, bounded I/O, and cleanup.

const builtin = @import("builtin");
const std = @import("std");
const posix = std.posix;

const c = @import("pty_c");

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
    var winsize = c.struct_winsize{
        .ws_row = rows,
        .ws_col = cols,
        .ws_xpixel = 0,
        .ws_ypixel = 0,
    };
    if (c.openpty(&master_fd, &slave_fd, null, null, &winsize) != 0) {
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
        const pid = c.fork();
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
            const waited = c.waitpid(pid, &status, c.WNOHANG);
            if (waited < 0 and posix.errno(waited) == .INTR) continue;
            break waited;
        };
        if (result == 0) return .running;
        if (result == pid) {
            const exit = childObservation(status);
            self.child = .{ .reaped = .{ .pid = pid, .exit = exit.exited } };
            return exit;
        }
        if (posix.errno(result) == .CHILD) return error.ObserveFailed;
        return error.ObserveFailed;
    }

    fn awaitChildLaunch(status_fd: posix.fd_t) StartError!void {
        defer closeOwned(status_fd);
        var status: [1]u8 = undefined;
        while (true) {
            const n = c.read(status_fd, &status, status.len);
            // CLOEXEC closes the child writer atomically with successful exec.
            if (n == 0) return;
            if (n == 1) return childLaunchError(status[0]);
            switch (posix.errno(n)) {
                .INTR => continue,
                else => return error.LaunchStatusFailed,
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
        const result = c.write(master, bytes.ptr, bytes.len);
        if (result > 0) {
            const count: usize = @intCast(result);
            if (count > bytes.len) return error.WriteFailed;
            return count;
        }
        if (result == 0) return error.ChildClosed;
        return switch (posix.errno(result)) {
            .AGAIN => error.WouldBlock,
            .INTR => error.Interrupted,
            .IO, .PIPE => error.ChildClosed,
            else => error.WriteFailed,
        };
    }

    /// Reads available transport bytes into caller-owned storage.
    pub fn read(self: *Self, buf: []u8) ReadError!usize {
        if (!self.started) return error.NotStarted;
        const master_fd = self.master_fd orelse return error.NotStarted;
        if (buf.len == 0) return 0;

        const n = c.read(master_fd, buf.ptr, buf.len);
        if (n < 0) {
            return switch (posix.errno(n)) {
                .AGAIN => error.WouldBlock,
                .IO => error.EndOfStream,
                .INTR => error.Interrupted,
                else => error.ReadFailed,
            };
        }
        if (n == 0) {
            return error.EndOfStream;
        }
        return @intCast(n);
    }

    /// Applies nonzero terminal dimensions to the active PTY.
    pub fn resize(self: *Self, cols: u16, rows: u16) ResizeError!void {
        if (self.master_fd == null) return error.NotStarted;
        if (cols == 0 or rows == 0) return error.InvalidDimensions;

        var winsize = c.struct_winsize{
            .ws_row = rows,
            .ws_col = cols,
            .ws_xpixel = 0,
            .ws_ypixel = 0,
        };
        if (c.ioctl(@intCast(self.master_fd.?), c.TIOCSWINSZ, &winsize) != 0) {
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
        var attributes: c.struct_termios = undefined;
        if (c.tcgetattr(@intCast(master), &attributes) != 0)
            return error.TermiosQueryFailed;
        if (attributes.c_lflag & c.ISIG == 0) return false;
        const signal_value: c_int = signal: {
            const controls = [_]struct { index: usize, signal: c_int }{
                .{ .index = c.VINTR, .signal = c.SIGINT },
                .{ .index = c.VQUIT, .signal = c.SIGQUIT },
                .{ .index = c.VSUSP, .signal = c.SIGTSTP },
            };
            for (controls) |entry| {
                const assigned: u8 = attributes.c_cc[entry.index];
                if (assigned != c._POSIX_VDISABLE and assigned == byte)
                    break :signal entry.signal;
            }
            return false;
        };
        const foreground = c.tcgetpgrp(@intCast(master));
        if (foreground <= 0) return error.ForegroundGroupFailed;
        if (c.kill(-foreground, signal_value) != 0) return error.SignalFailed;
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
    const result = c.close(@intCast(fd));
    if (result == 0) return;
    switch (posix.errno(result)) {
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
    if (c.pipe(&fds) != 0) return error.LaunchStatusPipeFailed;
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
    const flags = c.fcntl(fd, c.F_GETFL, @as(c_int, 0));
    if (flags < 0) return error.OpenPtyFailed;
    if (c.fcntl(fd, c.F_SETFL, flags | c.O_NONBLOCK) != 0) return error.OpenPtyFailed;
}

fn setCloseOnExec(fd: posix.fd_t) StartError!void {
    const flags = c.fcntl(fd, c.F_GETFD, @as(c_int, 0));
    if (flags < 0) return error.OpenPtyFailed;
    if (c.fcntl(fd, c.F_SETFD, flags | c.FD_CLOEXEC) != 0) return error.OpenPtyFailed;
}

fn requireExecutable(path: [:0]const u8) StartError!void {
    if (c.access(path.ptr, c.X_OK) != 0) return error.ShellUnavailable;
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
        if (c.sigaction(@backingInt(signal), @ptrCast(&sa), null) != 0) return false;
    }
    return true;
}

fn closeChildFdIfNeeded(fd: posix.fd_t) bool {
    if (fd <= 2) return true;
    const result = c.close(@intCast(fd));
    if (result == 0) return true;
    // Linux has consumed the descriptor even when close reports EINTR.
    return posix.errno(result) == .INTR;
}

fn setupChildProcessFds(fds: ChildProcessFds, status_fd: posix.fd_t) void {
    if (!resetChildSignalDispositions() or c.setsid() < 0) childLaunchExit(status_fd, .session);
    if (c.ioctl(@intCast(fds.slave_fd), c.TIOCSCTTY, @as(c_ulong, 0)) != 0 or
        c.dup2(fds.slave_fd, 0) < 0 or c.dup2(fds.slave_fd, 1) < 0 or
        c.dup2(fds.slave_fd, 2) < 0 or !closeChildFdIfNeeded(fds.master_fd) or
        !closeChildFdIfNeeded(fds.slave_fd))
    {
        childLaunchExit(status_fd, .stdio);
    }
}

fn childLaunchExit(status_fd: posix.fd_t, failure: ChildLaunchFailure) noreturn {
    var byte: [1]u8 = .{@backingInt(failure)};
    while (true) {
        const n = c.write(status_fd, &byte, byte.len);
        if (n == 1) c._exit(127);
        switch (posix.errno(n)) {
            .INTR => continue,
            else => c._exit(127),
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
        if (c.chdir(dir) != 0) childLaunchExit(status_fd, .cwd);
    }

    if (command) |cmd| {
        const argv = [_:null][*c]u8{ cArg(shell_path.ptr), cArg("-c"), cArg(cmd) };
        const envp: [*c]const [*c]u8 = @ptrCast(environment);
        if (c.execve(shell_path.ptr, argv[0..].ptr, envp) != 0) childLaunchExit(status_fd, .exec);
        childLaunchExit(status_fd, .exec);
    }

    const argv = [_:null][*c]u8{ cArg(shell_path.ptr), cArg("-i") };
    const envp: [*c]const [*c]u8 = @ptrCast(environment);
    if (c.execve(shell_path.ptr, argv[0..].ptr, envp) != 0) childLaunchExit(status_fd, .exec);
    childLaunchExit(status_fd, .exec);
}

fn waitChildNoHang(pid: posix.pid_t) enum { alive, reaped, failed } {
    std.debug.assert(pid > 0);
    var status: c_int = 0;
    while (true) {
        const res = c.waitpid(pid, &status, c.WNOHANG);
        if (res == 0) return .alive;
        if (res == pid) return .reaped;
        switch (posix.errno(res)) {
            .INTR => continue,
            .CHILD => return .reaped,
            else => return .failed,
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
        const res = c.waitpid(pid, &status, 0);
        if (res == pid) return;
        switch (posix.errno(res)) {
            .INTR => continue,
            .CHILD => return,
            else => @panic("PTY child wait failed"),
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
        const res = c.kill(target, 0);
        if (res == 0) return true;
        switch (posix.errno(res)) {
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
        const res = c.kill(target, signal.native());
        if (res == 0) return .delivered;
        switch (posix.errno(res)) {
            .INTR => continue,
            .SRCH => return .target_missing,
            .PERM => return .permission_denied,
            else => return .native_signal_failed,
        }
    }
}

fn sleepStopSlice() void {
    const result = c.usleep(@intCast(stop_wait_slice_ns / std.time.ns_per_us));
    if (result == 0) return;
    switch (posix.errno(result)) {
        .INTR => {},
        else => @panic("PTY cleanup clock wait failed"),
    }
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
    try std.testing.expectError(error.WouldBlock, owned.write(bytes[accepted_initial..]));

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
