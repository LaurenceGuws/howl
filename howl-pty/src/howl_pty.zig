//! Owns one Linux PTY, its child process group, bounded I/O, and cleanup.

const builtin = @import("builtin");
const std = @import("std");
const posix = std.posix;

const c = @cImport({
    @cDefine("_Nonnull", "");
    @cDefine("_Nullable", "");
    @cDefine("_Null_unspecified", "");
    @cDefine("BIONIC_IOCTL_NO_SIGNEDNESS_OVERLOAD", "1");
    @cInclude("unistd.h");
    @cInclude("fcntl.h");
    @cInclude("stdlib.h");
    @cInclude("pty.h");
    @cInclude("signal.h");
    @cInclude("sys/wait.h");
});

/// Reports copied launch allocation or a non-Linux build.
pub const InitError = std.mem.Allocator.Error || error{UnsupportedPlatform};

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
    WakePipeFailed,
};

/// Names signals accepted by the child process-group owner.
pub const ControlSignal = enum(u8) {
    hangup = 1,
    interrupt = 2,
    resize_notify = 3,
    kill = 9,
    terminate = 15,

    fn native(self: ControlSignal) c_int {
        return @intCast(@intFromEnum(self));
    }
};

/// Distinguishes readable transport, elapsed timeout, and cancellation.
pub const WaitReadableResult = enum(u8) { ready, timeout, canceled };

/// Reports a nonblocking PTY read failure.
pub const ReadError = error{ EndOfStream, Interrupted, NotStarted, ReadFailed, WouldBlock };

/// Reports failure while waiting for readable PTY output.
pub const WaitReadableError = error{ NotStarted, WaitFailed };

/// Reports resize before start or a failed Linux ioctl.
pub const ResizeError = error{ NotStarted, ResizeFailed };

/// Names why a bounded PTY input transfer stopped before completion.
pub const TransferFailure = enum(u8) {
    timeout,
    canceled,
    child_closed,
    not_started,
    wait_failed,
    write_failed,
};

/// Carries the exact transferred prefix and terminal outcome of one write.
pub const Transfer = union(enum) {
    complete: usize,
    incomplete: struct {
        transferred: usize,
        reason: TransferFailure,
    },

    /// Returns the exact prefix accepted by the PTY master.
    pub fn transferred(self: Transfer) usize {
        return switch (self) {
            .complete => |count| count,
            .incomplete => |failure| failure.transferred,
        };
    }
};

/// Owns one newly opened master/slave PTY pair until parent or child adoption.
const Open = struct {
    master_fd: posix.fd_t,
    slave_fd: posix.fd_t,
};

const Wake = struct {
    read_fd: posix.fd_t,
    write_fd: posix.fd_t,
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

const SignalResult = enum {
    delivered,
    missing,
    failed,
};

/// Reports whether child process-group signal delivery reached a live target.
pub const ControlResult = enum { delivered, child_missing, failed };

const WriteWait = enum { ready, timeout, canceled, closed, failed };

const stop_hangup_grace_ns = 50 * std.time.ns_per_ms;
const stop_terminate_grace_ns = 50 * std.time.ns_per_ms;
const stop_wait_slice_ns = std.time.ns_per_ms;

fn incomplete(transferred: usize, reason: TransferFailure) Transfer {
    return .{ .incomplete = .{ .transferred = transferred, .reason = reason } };
}

fn childLaunchError(value: u8) StartError {
    return switch (value) {
        @intFromEnum(ChildLaunchFailure.session) => error.ChildSessionFailed,
        @intFromEnum(ChildLaunchFailure.stdio) => error.ChildStdioFailed,
        @intFromEnum(ChildLaunchFailure.cwd) => error.ChildCwdFailed,
        @intFromEnum(ChildLaunchFailure.exec) => error.ChildExecFailed,
        else => error.LaunchStatusFailed,
    };
}

fn deadlineExpired(io: std.Io, started: std.Io.Timestamp, timeout_ms: u32) bool {
    return started.durationTo(std.Io.Clock.awake.now(io)).toMilliseconds() >= timeout_ms;
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

/// Owns copied launch values, one Linux PTY, wake pipe, and child process group.
/// `start`, `read`, `waitReadable`, `transfer`, `resize`, `control`, and `stop`
/// are externally serialized. `cancel` alone is safe concurrently. `stop` and
/// `deinit` require every concurrent caller to have returned.
pub const Owned = struct {
    allocator: std.mem.Allocator,
    shell_path: [:0]u8,
    command: ?[:0]u8,
    command_ptr: ?[*:0]u8,
    start_path: ?[:0]u8,
    start_path_ptr: ?[*:0]u8,
    started: bool,
    master_fd: ?posix.fd_t,
    wake_read_fd: ?posix.fd_t,
    wake_write_fd: ?posix.fd_t,
    child: Child,
    last_cols: u16,
    last_rows: u16,
    canceled: std.atomic.Value(bool),

    const Self = @This();
    const Child = union(enum) {
        none,
        pending_session: posix.pid_t,
        live: posix.pid_t,
    };

    const StartPipes = struct {
        wake: Wake,
        launch_status: LaunchStatus,
    };

    /// Copies launch strings and initializes an idle PTY owner.
    pub fn init(
        allocator: std.mem.Allocator,
        shell_path: []const u8,
        command: ?[]const u8,
        start_path: ?[]const u8,
    ) InitError!Self {
        if (builtin.os.tag != .linux) return error.UnsupportedPlatform;

        const shell_path_z = try allocator.dupeZ(u8, shell_path);
        errdefer allocator.free(shell_path_z);

        const command_z = if (command) |bytes| try allocator.dupeZ(u8, bytes) else null;
        errdefer if (command_z) |bytes| allocator.free(bytes);

        const start_path_z = if (start_path) |bytes| try allocator.dupeZ(u8, bytes) else null;
        errdefer if (start_path_z) |bytes| allocator.free(bytes);

        return .{
            .allocator = allocator,
            .shell_path = shell_path_z,
            .command = command_z,
            .command_ptr = optionalZPtr(command_z),
            .start_path = start_path_z,
            .start_path_ptr = optionalZPtr(start_path_z),
            .started = false,
            .master_fd = null,
            .wake_read_fd = null,
            .wake_write_fd = null,
            .child = .none,
            .last_cols = 0,
            .last_rows = 0,
            .canceled = .init(false),
        };
    }

    /// Stops the child group, closes descriptors, and releases copied launch strings.
    pub fn deinit(self: *Self) void {
        self.stop();
        self.allocator.free(self.shell_path);
        if (self.command) |bytes| self.allocator.free(bytes);
        if (self.start_path) |bytes| self.allocator.free(bytes);
        self.* = undefined;
    }

    /// Starts one child at the supplied nonzero terminal dimensions.
    pub fn start(self: *Self, cols: u16, rows: u16) StartError!void {
        if (self.started) return error.AlreadyStarted;
        std.debug.assert(cols > 0);
        std.debug.assert(rows > 0);

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
        const wake = try openWake();
        errdefer closeWake(wake);

        const launch_status = try openLaunchStatusPipe();
        errdefer closeLaunchStatusPipe(launch_status);

        return .{ .wake = wake, .launch_status = launch_status };
    }

    fn closeStartPipes(pipes: StartPipes) void {
        closeLaunchStatusPipe(pipes.launch_status);
        closeWake(pipes.wake);
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
                pipes.wake.read_fd,
                pipes.wake.write_fd,
                pipes.launch_status.write_fd,
                self.shell_path,
                self.command_ptr,
                self.start_path_ptr,
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
        self.wake_read_fd = pipes.wake.read_fd;
        self.wake_write_fd = pipes.wake.write_fd;
        self.child = .{ .pending_session = pid };
        self.last_cols = cols;
        self.last_rows = rows;
        self.canceled.store(false, .release);
        self.started = true;
    }

    fn assertStarted(self: *const Self) void {
        std.debug.assert(self.master_fd != null);
        std.debug.assert(self.wake_read_fd != null);
        std.debug.assert(self.wake_write_fd != null);
        std.debug.assert(self.childPid() != null);
    }

    /// Stops and reaps the child process group and closes every descriptor.
    pub fn stop(self: *Self) void {
        if (!self.started) return;

        self.cancel();
        self.stopChild();

        if (self.master_fd) |fd| closeOwned(fd);
        if (self.wake_read_fd) |fd| closeOwned(fd);
        if (self.wake_write_fd) |fd| closeOwned(fd);
        self.child = .none;
        self.master_fd = null;
        self.wake_read_fd = null;
        self.wake_write_fd = null;
        self.started = false;

        std.debug.assert(self.master_fd == null);
        std.debug.assert(self.wake_read_fd == null);
        std.debug.assert(self.wake_write_fd == null);
        std.debug.assert(self.childPid() == null);
    }

    fn refreshChildState(self: *Self) enum { live, missing, failed } {
        if (!self.started) return .missing;
        const pid = self.childPid() orelse return .missing;
        return switch (waitChildNoHang(pid)) {
            .alive => .live,
            .reaped => {
                self.child = .none;
                return .missing;
            },
            .failed => .failed,
        };
    }

    fn transportReady(self: *const Self) bool {
        if (!self.started) return false;
        if (self.master_fd == null) return false;
        if (self.child != .live) return false;
        return true;
    }

    fn childPid(self: *const Self) ?posix.pid_t {
        return switch (self.child) {
            .none => null,
            .pending_session => |pid| pid,
            .live => |pid| pid,
        };
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

    /// Concurrently cancels every active and future transport wait.
    /// Destructive cleanup remains serialized after all callers return.
    pub fn cancel(self: *Self) void {
        if (!self.started) return;
        self.canceled.store(true, .release);
        const fd = self.wake_write_fd orelse return;
        var byte: [1]u8 = .{1};
        while (true) {
            const result = c.write(fd, &byte, byte.len);
            if (result == 1) return;
            if (result < 0) switch (posix.errno(result)) {
                .AGAIN => return,
                .INTR => continue,
                .BADF => @panic("PTY cancellation raced destructive cleanup"),
                else => @panic("PTY cancellation pipe write failed"),
            };
            @panic("PTY cancellation pipe accepted an invalid byte count");
        }
    }

    /// Transfers one borrowed slice before its caller-supplied deadline.
    /// The outcome retains the exact accepted prefix on every failure.
    pub fn transfer(
        self: *Self,
        io: std.Io,
        bytes: []const u8,
        timeout_ms: u32,
    ) Transfer {
        if (!self.transportReady()) return incomplete(0, .not_started);
        if (self.canceled.load(.acquire)) return incomplete(0, .canceled);
        if (bytes.len == 0) return .{ .complete = 0 };
        const started = std.Io.Clock.awake.now(io);
        var written: usize = 0;
        while (written < bytes.len) {
            if (self.canceled.load(.acquire)) return incomplete(written, .canceled);
            if (deadlineExpired(io, started, timeout_ms)) return incomplete(written, .timeout);
            const remaining = bytes.len - written;
            const result = c.write(self.master_fd.?, bytes[written..].ptr, remaining);
            if (result > 0) {
                const count: usize = @intCast(result);
                std.debug.assert(count <= remaining);
                if (count > remaining) return incomplete(written, .write_failed);
                written += count;
                continue;
            }
            if (result == 0) return incomplete(written, .child_closed);
            switch (posix.errno(result)) {
                .INTR => continue,
                .AGAIN => switch (self.waitWritable(io, started, timeout_ms)) {
                    .ready => continue,
                    .timeout => return incomplete(written, .timeout),
                    .canceled => return incomplete(written, .canceled),
                    .closed => return incomplete(written, .child_closed),
                    .failed => return incomplete(written, .wait_failed),
                },
                .IO, .PIPE => return incomplete(written, .child_closed),
                else => return incomplete(written, .write_failed),
            }
        }
        return .{ .complete = written };
    }

    fn waitWritable(
        self: *Self,
        io: std.Io,
        started: std.Io.Timestamp,
        timeout_ms: u32,
    ) WriteWait {
        while (true) {
            if (self.canceled.load(.acquire)) return .canceled;
            const master = self.master_fd orelse return .closed;
            const wake = self.wake_read_fd orelse return .closed;
            const elapsed = started.durationTo(std.Io.Clock.awake.now(io)).toMilliseconds();
            if (elapsed >= timeout_ms) return .timeout;
            var descriptors = [_]posix.pollfd{
                .{ .fd = master, .events = posix.POLL.OUT | posix.POLL.HUP, .revents = 0 },
                .{ .fd = wake, .events = posix.POLL.IN | posix.POLL.HUP, .revents = 0 },
            };
            const remaining: i32 = @intCast(timeout_ms - @as(u32, @intCast(elapsed)));
            const ready = posix.poll(&descriptors, remaining) catch return .failed;
            if (ready == 0) return .timeout;
            if (self.canceled.load(.acquire) or
                (descriptors[1].revents & (posix.POLL.IN | posix.POLL.HUP)) != 0) return .canceled;
            if ((descriptors[0].revents & posix.POLL.OUT) != 0) return .ready;
            if ((descriptors[0].revents & posix.POLL.HUP) != 0) return .closed;
            return .failed;
        }
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

    /// Waits for transport readability, timeout, or an explicit wake.
    pub fn waitReadable(self: *Self, timeout_ms: i32) WaitReadableError!WaitReadableResult {
        if (!self.transportReady()) return error.NotStarted;
        std.debug.assert(self.wake_read_fd != null);

        var fds = [_]posix.pollfd{
            .{ .fd = self.master_fd.?, .events = posix.POLL.IN | posix.POLL.HUP, .revents = 0 },
            .{
                .fd = self.wake_read_fd orelse return error.NotStarted,
                .events = posix.POLL.IN | posix.POLL.HUP,
                .revents = 0,
            },
        };
        const poll_timeout: i32 = if (timeout_ms < 0) -1 else timeout_ms;
        const ready = posix.poll(&fds, poll_timeout) catch return error.WaitFailed;
        if (ready <= 0) return .timeout;

        if ((fds[1].revents & (posix.POLL.IN | posix.POLL.HUP)) != 0) {
            return .canceled;
        }
        if ((fds[0].revents & posix.POLL.IN) != 0) return .ready;
        if ((fds[0].revents & posix.POLL.HUP) != 0) return .ready;
        return waitReadablePollResult(fds[0].revents);
    }

    /// Applies nonzero terminal dimensions to the active PTY.
    pub fn resize(self: *Self, cols: u16, rows: u16) ResizeError!void {
        if (!self.transportReady()) return error.NotStarted;
        std.debug.assert(cols > 0);
        std.debug.assert(rows > 0);

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

    /// Delivers one typed signal to the active child process group.
    pub fn control(self: *Self, signal: ControlSignal) ControlResult {
        switch (self.refreshChildState()) {
            .live => {},
            .missing => return .child_missing,
            .failed => return .failed,
        }
        if (!self.transportReady()) return .child_missing;
        const pid = self.childPid() orelse return .child_missing;
        return switch (sendGroupSignal(pid, signal)) {
            .delivered => .delivered,
            .missing => .child_missing,
            .failed => .failed,
        };
    }
};

fn waitReadablePollResult(revents: i16) WaitReadableResult {
    if ((revents & posix.POLL.IN) != 0) return .ready;
    return .timeout;
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
        .delivered, .missing => {},
        .failed => @panic("PTY child cleanup signal failed"),
    }
}

fn closeTransport(transport: Open) void {
    closeOwned(transport.master_fd);
    closeOwned(transport.slave_fd);
}

fn openWake() StartError!Wake {
    var fds = [_]c_int{ -1, -1 };
    if (c.pipe(&fds) != 0) return error.WakePipeFailed;
    errdefer {
        if (fds[0] >= 0) closeOwned(@intCast(fds[0]));
        if (fds[1] >= 0) closeOwned(@intCast(fds[1]));
    }

    setCloseOnExec(@intCast(fds[0])) catch return error.WakePipeFailed;
    setCloseOnExec(@intCast(fds[1])) catch return error.WakePipeFailed;
    setNonBlocking(@intCast(fds[0])) catch return error.WakePipeFailed;
    setNonBlocking(@intCast(fds[1])) catch return error.WakePipeFailed;
    return .{ .read_fd = @intCast(fds[0]), .write_fd = @intCast(fds[1]) };
}

fn closeWake(wake: Wake) void {
    closeOwned(wake.read_fd);
    closeOwned(wake.write_fd);
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
    wake_read_fd: ?posix.fd_t,
    wake_write_fd: ?posix.fd_t,
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
        if (c.sigaction(@intFromEnum(signal), @ptrCast(&sa), null) != 0) return false;
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
        (fds.wake_read_fd != null and !closeChildFdIfNeeded(fds.wake_read_fd.?)) or
        (fds.wake_write_fd != null and !closeChildFdIfNeeded(fds.wake_write_fd.?)) or
        !closeChildFdIfNeeded(fds.slave_fd))
    {
        childLaunchExit(status_fd, .stdio);
    }
}

fn childLaunchExit(status_fd: posix.fd_t, failure: ChildLaunchFailure) noreturn {
    var byte: [1]u8 = .{@intFromEnum(failure)};
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
    wake_read_fd: ?posix.fd_t,
    wake_write_fd: ?posix.fd_t,
    status_fd: posix.fd_t,
    shell_path: [:0]const u8,
    command: ?[*:0]const u8,
    cwd: ?[*:0]const u8,
) noreturn {
    setupChildProcessFds(.{
        .master_fd = master_fd,
        .slave_fd = slave_fd,
        .wake_read_fd = wake_read_fd,
        .wake_write_fd = wake_write_fd,
    }, status_fd);

    if (cwd) |dir| {
        if (c.chdir(dir) != 0) childLaunchExit(status_fd, .cwd);
    }

    if (command) |cmd| {
        const argv = [_:null][*c]u8{ cArg(shell_path.ptr), cArg("-c"), cArg(cmd) };
        const envp: [*c]const [*c]u8 = @ptrCast(@constCast(std.c.environ));
        if (c.execve(shell_path.ptr, argv[0..].ptr, envp) != 0) childLaunchExit(status_fd, .exec);
        childLaunchExit(status_fd, .exec);
    }

    const argv = [_:null][*c]u8{ cArg(shell_path.ptr), cArg("-i") };
    const envp: [*c]const [*c]u8 = @ptrCast(@constCast(std.c.environ));
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

fn sendSignal(pid: posix.pid_t, signal: ControlSignal) SignalResult {
    return sendSignalTarget(pid, signal);
}

fn sendGroupSignal(pid: posix.pid_t, signal: ControlSignal) SignalResult {
    std.debug.assert(pid > 0);
    return sendSignalTarget(-pid, signal);
}

fn sendSignalTarget(target: posix.pid_t, signal: ControlSignal) SignalResult {
    while (true) {
        const res = c.kill(target, signal.native());
        if (res == 0) return .delivered;
        switch (posix.errno(res)) {
            .INTR => continue,
            .SRCH => return .missing,
            else => return .failed,
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

fn expectOutput(owned: *Owned, expected: []const u8) !void {
    var buffer: [512]u8 = undefined;
    var used: usize = 0;
    var waits: u8 = 0;
    while (waits < test_waits_max) : (waits += 1) {
        switch (try owned.waitReadable(test_wait_ms)) {
            .timeout => continue,
            .canceled => return error.TestCanceled,
            .ready => {},
        }
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
    var owned = try Owned.init(allocator, "/bin/sh", "printf allocation", "/tmp");
    owned.deinit();
}

const TransferContext = struct {
    owned: *Owned,
    bytes: []const u8,
    timeout_ms: u32,
    started: std.atomic.Value(bool) = .init(false),
    completed: std.atomic.Value(bool) = .init(false),
    result: Transfer = .{ .incomplete = .{ .transferred = 0, .reason = .not_started } },
};

fn transferThread(context: *TransferContext) void {
    context.started.store(true, .release);
    context.result = context.owned.transfer(std.testing.io, context.bytes, context.timeout_ms);
    context.completed.store(true, .release);
}

test "initialization releases every partial allocation" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    try std.testing.checkAllAllocationFailures(std.testing.allocator, initAllocation, .{});
}

test "idle owner reports exact lifecycle outcomes and remains startable" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    var owned = try Owned.init(std.testing.allocator, "/bin/sh", "cat", null);
    defer owned.deinit();
    var buffer: [16]u8 = undefined;
    try std.testing.expectEqual(
        Transfer{ .incomplete = .{ .transferred = 0, .reason = .not_started } },
        owned.transfer(std.testing.io, "hello", 10),
    );
    try std.testing.expectError(error.NotStarted, owned.read(&buffer));
    try std.testing.expectError(error.NotStarted, owned.waitReadable(0));
    try std.testing.expectError(error.NotStarted, owned.resize(test_cols, test_rows));
    try std.testing.expectEqual(ControlResult.child_missing, owned.control(.interrupt));
    owned.cancel();
    owned.stop();
    try owned.start(test_cols, test_rows);
    try std.testing.expectEqual(Transfer{ .complete = 6 }, owned.transfer(std.testing.io, "hello\n", 100));
}

test "start rejects unavailable and duplicate child transitions without descriptor leaks" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const before = try descriptorCount();
    var unavailable = try Owned.init(std.testing.allocator, "/definitely/missing/howl-shell", null, null);
    try std.testing.expectError(error.ShellUnavailable, unavailable.start(test_cols, test_rows));
    unavailable.deinit();
    try std.testing.expectEqual(before, try descriptorCount());

    var invalid_cwd = try Owned.init(
        std.testing.allocator,
        "/bin/sh",
        null,
        "/definitely/missing/howl-cwd",
    );
    try std.testing.expectError(error.ChildCwdFailed, invalid_cwd.start(test_cols, test_rows));
    invalid_cwd.deinit();
    try std.testing.expectEqual(before, try descriptorCount());

    // A searchable executable directory passes access(X_OK) but cannot execve.
    var unlaunchable = try Owned.init(std.testing.allocator, "/tmp", null, null);
    try std.testing.expectError(error.ChildExecFailed, unlaunchable.start(test_cols, test_rows));
    unlaunchable.deinit();
    try std.testing.expectEqual(before, try descriptorCount());

    var owned = try Owned.init(std.testing.allocator, "/bin/sh", "sleep 30", null);
    defer owned.deinit();
    try owned.start(test_cols, test_rows);
    try std.testing.expectError(error.AlreadyStarted, owned.start(test_cols, test_rows));
}

test "zero deadline rejects nonempty input before the first write" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    var owned = try Owned.init(std.testing.allocator, "/bin/sh", "cat >/dev/null", null);
    defer owned.deinit();
    try owned.start(test_cols, test_rows);
    try std.testing.expectEqual(
        Transfer{ .incomplete = .{ .transferred = 0, .reason = .timeout } },
        owned.transfer(std.testing.io, "must-not-enter-pty", 0),
    );
}

test "deadline stops a continuously accepting transfer with its exact prefix" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    var owned = try Owned.init(
        std.testing.allocator,
        "/bin/sh",
        "stty raw -echo; printf ready; cat >/dev/null",
        null,
    );
    defer owned.deinit();
    try owned.start(test_cols, test_rows);
    try expectOutput(&owned, "ready");
    const bytes = try std.testing.allocator.alloc(u8, 16 * 1024 * 1024);
    defer std.testing.allocator.free(bytes);
    @memset(bytes, 'd');
    const transfer = owned.transfer(std.testing.io, bytes, 1);
    try std.testing.expect(transfer == .incomplete);
    try std.testing.expectEqual(TransferFailure.timeout, transfer.incomplete.reason);
    try std.testing.expect(transfer.incomplete.transferred < bytes.len);
}

test "complete transfer reports every accepted byte" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    var owned = try Owned.init(
        std.testing.allocator,
        "/bin/sh",
        "stty raw -echo; dd bs=1 count=5 2>/dev/null; printf complete",
        null,
    );
    defer owned.deinit();
    try owned.start(test_cols, test_rows);
    try std.testing.expectEqual(Transfer{ .complete = 5 }, owned.transfer(std.testing.io, "hello", 100));
    try expectOutput(&owned, "complete");
}

test "non-reading child saturates with a bounded partial timeout" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const before = try descriptorCount();
    var owned = try Owned.init(
        std.testing.allocator,
        "/bin/sh",
        "stty raw -echo; printf ready; kill -STOP $$",
        null,
    );
    try owned.start(test_cols, test_rows);
    try expectOutput(&owned, "ready");
    var bytes: [64 * 1024]u8 = .{'x'} ** (64 * 1024);
    const started = std.Io.Clock.awake.now(std.testing.io);
    const transfer = owned.transfer(std.testing.io, &bytes, 25);
    const elapsed = started.durationTo(std.Io.Clock.awake.now(std.testing.io)).toMilliseconds();
    try std.testing.expect(transfer == .incomplete);
    try std.testing.expectEqual(TransferFailure.timeout, transfer.incomplete.reason);
    try std.testing.expect(transfer.incomplete.transferred < bytes.len);
    try std.testing.expect(elapsed >= 25 and elapsed < 500);
    owned.deinit();
    try std.testing.expectEqual(before, try descriptorCount());
}

test "child consuming a strict prefix retains the partial timeout count" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    var owned = try Owned.init(
        std.testing.allocator,
        "/bin/sh",
        "stty raw -echo; printf ready; dd bs=1024 count=1 of=/dev/null 2>/dev/null; kill -STOP $$",
        null,
    );
    defer owned.deinit();
    try owned.start(test_cols, test_rows);
    try expectOutput(&owned, "ready");
    var bytes: [64 * 1024]u8 = .{'p'} ** (64 * 1024);
    const transfer = owned.transfer(std.testing.io, &bytes, 50);
    try std.testing.expect(transfer == .incomplete);
    try std.testing.expectEqual(TransferFailure.timeout, transfer.incomplete.reason);
    try std.testing.expect(transfer.incomplete.transferred >= 1024);
    try std.testing.expect(transfer.incomplete.transferred < bytes.len);
}

test "concurrent cancellation wakes a saturated writable wait without descriptor race" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const before = try descriptorCount();
    var owned = try Owned.init(
        std.testing.allocator,
        "/bin/sh",
        "stty raw -echo; printf ready; kill -STOP $$",
        null,
    );
    errdefer owned.deinit();
    try owned.start(test_cols, test_rows);
    try expectOutput(&owned, "ready");
    var bytes: [64 * 1024]u8 = .{'c'} ** (64 * 1024);
    var context = TransferContext{ .owned = &owned, .bytes = &bytes, .timeout_ms = 10_000 };
    const thread = try std.Thread.spawn(.{}, transferThread, .{&context});
    while (!context.started.load(.acquire)) std.atomic.spinLoopHint();
    try (std.Io.Clock.Duration{ .raw = .fromMilliseconds(10), .clock = .awake }).sleep(std.testing.io);
    owned.cancel();
    thread.join();
    try std.testing.expect(context.completed.load(.acquire));
    try std.testing.expect(context.result == .incomplete);
    try std.testing.expectEqual(TransferFailure.canceled, context.result.incomplete.reason);
    try std.testing.expect(context.result.incomplete.transferred < bytes.len);
    try std.testing.expectEqual(
        Transfer{ .incomplete = .{ .transferred = 0, .reason = .canceled } },
        owned.transfer(std.testing.io, "later", 100),
    );
    owned.deinit();
    try std.testing.expectEqual(before, try descriptorCount());
}

test "child exit closes read and write paths before exact cleanup" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const before = try descriptorCount();
    var owned = try Owned.init(std.testing.allocator, "/bin/sh", "sleep 0.02; exit 0", null);
    errdefer owned.deinit();
    try owned.start(test_cols, test_rows);
    const bytes = try std.testing.allocator.alloc(u8, 1024 * 1024);
    defer std.testing.allocator.free(bytes);
    @memset(bytes, 'e');
    const transfer = owned.transfer(std.testing.io, bytes, 1000);
    try std.testing.expect(transfer == .incomplete);
    try std.testing.expectEqual(TransferFailure.child_closed, transfer.incomplete.reason);
    try std.testing.expect(transfer.incomplete.transferred < bytes.len);
    var buffer: [16]u8 = undefined;
    var closed = false;
    var waits: u8 = 0;
    while (!closed and waits < test_waits_max) : (waits += 1) {
        if (try owned.waitReadable(test_wait_ms) != .ready) continue;
        while (true) {
            const count = owned.read(&buffer) catch |failure| switch (failure) {
                error.EndOfStream => {
                    closed = true;
                    break;
                },
                error.Interrupted => continue,
                error.WouldBlock => break,
                error.NotStarted, error.ReadFailed => return failure,
            };
            try std.testing.expect(count > 0);
        }
    }
    try std.testing.expect(closed);
    owned.deinit();
    try std.testing.expectEqual(before, try descriptorCount());
}

test "wake resize read and process-group signal share one owner" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const command =
        "trap 'printf interrupted; exit 0' INT; printf ready; read line; " ++
        "stty size; printf '%s' \"$line\"; while :; do sleep 1; done";
    var owned = try Owned.init(std.testing.allocator, "/bin/sh", command, null);
    defer owned.deinit();
    try owned.start(test_cols, test_rows);
    try expectOutput(&owned, "ready");
    try owned.resize(100, 40);
    try std.testing.expectEqual(Transfer{ .complete = 6 }, owned.transfer(std.testing.io, "hello\n", 100));
    try expectOutput(&owned, "40 100");
    try std.testing.expectEqual(ControlResult.delivered, owned.control(.interrupt));
    try expectOutput(&owned, "interrupted");
}
