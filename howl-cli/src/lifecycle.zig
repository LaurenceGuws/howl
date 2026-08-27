//! Starts and gracefully stops named Howl session daemons without owning terminal state.

const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;
const discovery = @import("discovery.zig");

/// Conventional initial geometry before an explicit client claims resize leadership.
pub const default_rows: u16 = 24;
/// Conventional initial geometry before an explicit client claims resize leadership.
pub const default_columns: u16 = 80;

const startup_timeout_ms: u32 = 5000;
const startup_poll_ms: u32 = 50;
const stop_timeout_ms: i32 = 5000;
const detached_marker = "1";

/// One explicit detached session launch requested by the CLI.
pub const StartOptions = struct {
    name: []const u8,
    shell: []const u8 = "/bin/sh",
    rows: u16 = default_rows,
    columns: u16 = default_columns,
    cwd: ?[]const u8 = null,
    command: ?[]const u8 = null,
    sessiond: []const u8 = "howl-sessiond",
};

/// Reports exact launch, discovery, allocation, or bounded startup failure.
pub const StartError = std.process.SpawnError || std.process.Environ.CreateMapError ||
    discovery.FindError || error{
    InvalidDimensions,
    InvalidLaunch,
    SessionExists,
    DaemonPidInvalid,
    DaemonExited,
    ConcurrentSessionName,
    StartWaitFailed,
    StartTimeout,
    ChildWaitFailed,
};

/// Starts one detached named session and returns only after discovery and handshake succeed.
pub fn start(
    allocator: std.mem.Allocator,
    io: std.Io,
    environ: std.process.Environ,
    runtime_dir: []const u8,
    options: StartOptions,
) StartError!discovery.Session {
    if (options.rows == 0 or options.columns == 0) return error.InvalidDimensions;
    try validateLaunchText(options.shell);
    try validateLaunchText(options.sessiond);
    if (options.command) |command| try validateLaunchText(command);
    if (options.cwd) |cwd| try validateLaunchText(cwd);

    if (discovery.find(allocator, io, runtime_dir, options.name)) |_| {
        return error.SessionExists;
    } else |failure| switch (failure) {
        error.NoSuchSession => {},
        else => return failure,
    }

    var rows_buffer: [5]u8 = undefined;
    const rows = std.fmt.bufPrint(&rows_buffer, "{d}", .{options.rows}) catch unreachable;
    var columns_buffer: [5]u8 = undefined;
    const columns = std.fmt.bufPrint(&columns_buffer, "{d}", .{options.columns}) catch unreachable;
    var argv_storage: [6][]const u8 = undefined;
    argv_storage[0] = options.sessiond;
    argv_storage[1] = "tcp:0";
    argv_storage[2] = options.shell;
    argv_storage[3] = rows;
    argv_storage[4] = columns;
    const argv: []const []const u8 = if (options.command) |command| command_args: {
        argv_storage[5] = command;
        break :command_args argv_storage[0..6];
    } else argv_storage[0..5];

    var environment = try std.process.Environ.createMap(environ, allocator);
    defer environment.deinit();
    try environment.put("HOWL_SESSION_NAME", options.name);
    try environment.put("HOWL_SESSION_DETACHED", detached_marker);

    var child = try std.process.spawn(io, .{
        .argv = argv,
        .cwd = if (options.cwd) |cwd| .{ .path = cwd } else .inherit,
        .environ_map = &environment,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    });
    var child_owned = true;
    defer if (child_owned) child.kill(io);
    const native_pid = child.id orelse return error.DaemonPidInvalid;
    const pid = std.math.cast(u32, native_pid) orelse return error.DaemonPidInvalid;

    var elapsed_ms: u32 = 0;
    while (elapsed_ms <= startup_timeout_ms) : (elapsed_ms += startup_poll_ms) {
        const found: ?discovery.Session = discovery.find(
            allocator,
            io,
            runtime_dir,
            options.name,
        ) catch |failure| switch (failure) {
            error.NoSuchSession => null,
            else => return failure,
        };
        if (found) |session| {
            if (session.pid != pid) return error.ConcurrentSessionName;
            if (session.reachable) {
                child_owned = false;
                return session;
            }
        }
        if (try childExited(&child)) {
            child_owned = false;
            return error.DaemonExited;
        }
        if (elapsed_ms == startup_timeout_ms) break;
        std.Io.sleep(io, .fromMilliseconds(startup_poll_ms), .awake) catch
            return error.StartWaitFailed;
    }
    return error.StartTimeout;
}

/// Reports exact validated-daemon targeting or graceful-stop failure.
pub const StopError = discovery.FindError || error{
    PidfdUnavailable,
    PidfdOpenFailed,
    SessionReplaced,
    StopSignalFailed,
    StopWaitFailed,
    StopTimeout,
};

/// Gracefully stops one validated daemon through a stable Linux pidfd without SIGKILL escalation.
pub fn stop(
    allocator: std.mem.Allocator,
    io: std.Io,
    runtime_dir: []const u8,
    name: []const u8,
) StopError!void {
    const target = try discovery.find(allocator, io, runtime_dir, name);
    const native_pid = std.math.cast(posix.pid_t, target.pid) orelse return error.PidfdOpenFailed;
    const opened = linux.pidfd_open(native_pid, 0);
    const pidfd: posix.fd_t = switch (linux.errno(opened)) {
        .SUCCESS => @intCast(opened),
        .NOSYS => return error.PidfdUnavailable,
        .SRCH => return,
        else => return error.PidfdOpenFailed,
    };
    defer closeFd(pidfd);

    const current = discovery.find(allocator, io, runtime_dir, name) catch |failure| switch (failure) {
        error.NoSuchSession => return,
        else => return failure,
    };
    if (current.pid != target.pid or !std.mem.eql(u8, current.endpoint(), target.endpoint()))
        return error.SessionReplaced;

    const signaled = linux.pidfd_send_signal(pidfd, .TERM, null, 0);
    switch (linux.errno(signaled)) {
        .SUCCESS, .SRCH => {},
        .NOSYS => return error.PidfdUnavailable,
        else => return error.StopSignalFailed,
    }

    var descriptors = [_]posix.pollfd{.{
        .fd = pidfd,
        .events = posix.POLL.IN | posix.POLL.HUP,
        .revents = 0,
    }};
    const ready = posix.poll(&descriptors, stop_timeout_ms) catch return error.StopWaitFailed;
    if (ready == 0) return error.StopTimeout;
    if (descriptors[0].revents & posix.POLL.NVAL != 0 or
        descriptors[0].revents & (posix.POLL.IN | posix.POLL.HUP) == 0)
        return error.StopWaitFailed;
}

fn validateLaunchText(text: []const u8) error{InvalidLaunch}!void {
    if (text.len == 0 or std.mem.indexOfScalar(u8, text, 0) != null) return error.InvalidLaunch;
}

fn childExited(child: *std.process.Child) error{ChildWaitFailed}!bool {
    const pid = child.id orelse return true;
    var status: i32 = 0;
    while (true) {
        const result = linux.waitpid(pid, &status, linux.W.NOHANG);
        switch (linux.errno(result)) {
            .SUCCESS => {
                if (result == 0) return false;
                if (result != @as(usize, @intCast(pid))) return error.ChildWaitFailed;
                child.id = null;
                return true;
            },
            .INTR => continue,
            .CHILD => {
                child.id = null;
                return true;
            },
            else => return error.ChildWaitFailed,
        }
    }
}

fn closeFd(fd: posix.fd_t) void {
    const result = linux.close(fd);
    const errno = linux.errno(result);
    std.debug.assert(errno == .SUCCESS or errno == .INTR);
}

test "launch validation and defaults are explicit" {
    const options = StartOptions{ .name = "dev" };
    try std.testing.expectEqual(default_rows, options.rows);
    try std.testing.expectEqual(default_columns, options.columns);
    try std.testing.expectEqualStrings("/bin/sh", options.shell);
    try validateLaunchText("/usr/bin/bash");
    try std.testing.expectError(error.InvalidLaunch, validateLaunchText(""));
    try std.testing.expectError(error.InvalidLaunch, validateLaunchText("bad\x00command"));
}
