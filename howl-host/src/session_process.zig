//! Owns one host-created canonical Session process and its private Unix socket.
//!
//! Native graphical clients package the exact matching `howl-sessiond` beside
//! themselves.
//! This owner never consults PATH and never changes externally attached Session
//! lifetimes. It exists only for panes the Host itself creates.

const std = @import("std");
const linux = std.os.linux;
const posix = std.posix;
const client = @import("howl_client");

const start_attempts: usize = 250;
const start_retry_ms: i64 = 2;
const shutdown_grace_ms: u64 = 750;
const shutdown_poll_ms: u64 = 5;

pub const SessionProcess = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    child: std.process.Child,
    socket_path: []u8,
    endpoint: []u8,

    pub fn launchSibling(
        allocator: std.mem.Allocator,
        io: std.Io,
        runtime_dir: []const u8,
        shell: []const u8,
        command: ?[]const u8,
        cwd: ?[]const u8,
        environ_map: ?*const std.process.Environ.Map,
        rows: u16,
        cols: u16,
        identity: u32,
    ) !SessionProcess {
        if (runtime_dir.len == 0 or shell.len == 0 or rows == 0 or cols == 0 or identity == 0)
            return error.InvalidSessionLaunch;
        const executable_dir = try std.process.executableDirPathAlloc(io, allocator);
        defer allocator.free(executable_dir);
        const sessiond_path = try std.fs.path.join(allocator, &.{ executable_dir, "howl-sessiond" });
        defer allocator.free(sessiond_path);
        return launch(
            allocator,
            io,
            sessiond_path,
            runtime_dir,
            shell,
            command,
            cwd,
            environ_map,
            rows,
            cols,
            identity,
        );
    }

    fn launch(
        allocator: std.mem.Allocator,
        io: std.Io,
        sessiond_path: []const u8,
        runtime_dir: []const u8,
        shell: []const u8,
        command: ?[]const u8,
        cwd: ?[]const u8,
        environ_map: ?*const std.process.Environ.Map,
        rows: u16,
        cols: u16,
        identity: u32,
    ) !SessionProcess {
        const socket_path = try std.fmt.allocPrint(
            allocator,
            "{s}/howl-host-{d}-{d}.sock",
            .{ runtime_dir, std.os.linux.getpid(), identity },
        );
        errdefer allocator.free(socket_path);
        if (socket_path.len >= 100) return error.SocketPathTooLong;
        std.Io.Dir.deleteFileAbsolute(io, socket_path) catch |failure| switch (failure) {
            error.FileNotFound => {},
            else => return failure,
        };
        errdefer deleteSocket(io, socket_path, "rollback");

        const endpoint = try std.fmt.allocPrint(allocator, "unix:{s}", .{socket_path});
        errdefer allocator.free(endpoint);
        const rows_text = try std.fmt.allocPrint(allocator, "{d}", .{rows});
        defer allocator.free(rows_text);
        const cols_text = try std.fmt.allocPrint(allocator, "{d}", .{cols});
        defer allocator.free(cols_text);
        var argv_storage: [10][]const u8 = undefined;
        var argv_count: usize = 5;
        argv_storage[0] = sessiond_path;
        argv_storage[1] = socket_path;
        argv_storage[2] = shell;
        argv_storage[3] = rows_text;
        argv_storage[4] = cols_text;
        if (command) |value| {
            argv_storage[argv_count] = "--command";
            argv_storage[argv_count + 1] = value;
            argv_count += 2;
        }
        if (cwd) |value| {
            argv_storage[argv_count] = "--cwd";
            argv_storage[argv_count + 1] = value;
            argv_count += 2;
        }
        argv_storage[argv_count] = "--shutdown-stdin";
        argv_count += 1;
        var child = try std.process.spawn(io, .{
            .argv = argv_storage[0..argv_count],
            .environ_map = environ_map,
            .stdin = .pipe,
            .stdout = .ignore,
            .stderr = .inherit,
        });
        errdefer shutdownChild(&child, io);

        var attempt: usize = 0;
        while (attempt < start_attempts) : (attempt += 1) {
            var probe = client.Connection.connect(allocator, endpoint) catch |failure| switch (failure) {
                error.SocketConnectFailed => {
                    try std.Io.sleep(io, .fromMilliseconds(start_retry_ms), .awake);
                    continue;
                },
                else => return failure,
            };
            probe.deinit();
            return .{
                .allocator = allocator,
                .io = io,
                .child = child,
                .socket_path = socket_path,
                .endpoint = endpoint,
            };
        }
        return error.SessionStartTimeout;
    }

    pub fn deinit(self: *SessionProcess) void {
        shutdownChild(&self.child, self.io);
        deleteSocket(self.io, self.socket_path, "cleanup");
        self.allocator.free(self.endpoint);
        self.allocator.free(self.socket_path);
        self.* = undefined;
    }
};

fn deleteSocket(io: std.Io, path: []const u8, stage: []const u8) void {
    std.Io.Dir.deleteFileAbsolute(io, path) catch |failure| switch (failure) {
        error.FileNotFound => {},
        else => std.debug.print(
            "Howl Session socket {s} failed: {s}\n",
            .{ stage, @errorName(failure) },
        ),
    };
}

const ChildExitState = enum {
    running,
    exited,
    failed,
};

fn observeChildExitNoReap(pid: posix.pid_t) ChildExitState {
    while (true) {
        var info = std.mem.zeroes(linux.siginfo_t);
        const result = linux.waitid(
            .PID,
            pid,
            &info,
            linux.W.EXITED | linux.W.NOHANG | linux.W.NOWAIT,
            null,
        );
        switch (linux.errno(result)) {
            .SUCCESS => {
                const observed = info.fields.common.first.piduid.pid;
                if (observed == 0) return .running;
                return if (observed == pid) .exited else .failed;
            },
            .INTR => continue,
            else => return .failed,
        }
    }
}

fn monotonicNs() ?u64 {
    var now: linux.timespec = undefined;
    if (linux.errno(linux.clock_gettime(linux.CLOCK.MONOTONIC, &now)) != .SUCCESS)
        return null;
    const seconds = std.math.mul(u64, @intCast(now.sec), std.time.ns_per_s) catch
        return null;
    return std.math.add(u64, seconds, @intCast(now.nsec)) catch null;
}

fn reapObservedChild(child: *std.process.Child, pid: posix.pid_t) bool {
    std.debug.assert(child.id != null);
    std.debug.assert(child.stdin == null);
    std.debug.assert(child.stdout == null);
    std.debug.assert(child.stderr == null);
    var status: c_int = 0;
    while (true) {
        const result = linux.waitpid(pid, &status, 0);
        switch (linux.errno(result)) {
            .SUCCESS => {
                if (result != @as(usize, @intCast(pid))) return false;
                child.id = null;
                return true;
            },
            .INTR => continue,
            else => return false,
        }
    }
}

fn waitGracefulChild(child: *std.process.Child, timeout_ms: u64) bool {
    const pid: posix.pid_t = @intCast(child.id orelse return true);
    const started = monotonicNs() orelse return false;
    const timeout_ns = std.math.mul(u64, timeout_ms, std.time.ns_per_ms) catch
        return false;
    const deadline = std.math.add(u64, started, timeout_ns) catch
        return false;
    while (true) {
        switch (observeChildExitNoReap(pid)) {
            .exited => return reapObservedChild(child, pid),
            .failed => return false,
            .running => {},
        }
        const now = monotonicNs() orelse return false;
        if (now >= deadline) return false;
        const remaining_ns = deadline - now;
        sleepShutdownPoll(@min(
            remaining_ns,
            shutdown_poll_ms * std.time.ns_per_ms,
        ));
    }
}

fn sleepShutdownPoll(duration_ns: u64) void {
    if (duration_ns == 0) return;
    const request = linux.timespec{
        .sec = @intCast(duration_ns / std.time.ns_per_s),
        .nsec = @intCast(duration_ns % std.time.ns_per_s),
    };
    while (true) {
        switch (linux.errno(linux.nanosleep(&request, null))) {
            .SUCCESS => return,
            // Return to the outer wait loop so child state and the absolute
            // monotonic deadline are rechecked after every signal interruption.
            .INTR => return,
            else => return,
        }
    }
}

fn sendDaemonSignal(child: *std.process.Child, signal: linux.SIG) bool {
    const pid: posix.pid_t = @intCast(child.id orelse return true);
    while (true) {
        const result = linux.kill(pid, signal);
        switch (linux.errno(result)) {
            .SUCCESS => return true,
            .INTR => continue,
            .SRCH => return observeChildExitNoReap(pid) == .exited,
            else => return false,
        }
    }
}

fn shutdownChild(child: *std.process.Child, io: std.Io) void {
    if (child.id == null) return;
    if (child.stdin) |shutdown| {
        shutdown.close(io);
        child.stdin = null;
    }
    if (waitGracefulChild(child, shutdown_grace_ms)) return;

    // A stopped sibling cannot observe stdin EOF. Resume it once and grant a
    // second complete cleanup window before emergency containment.
    if (sendDaemonSignal(child, linux.SIG.CONT) and
        waitGracefulChild(child, shutdown_grace_ms))
        return;

    // Emergency containment only. SIGKILL cannot run sessiond's Session/PTy
    // defers, so this is not described as canonical terminal cleanup. It exists
    // solely to keep deinit from becoming an unbounded SIGTERM wait.
    if (!sendDaemonSignal(child, linux.SIG.KILL))
        @panic("Howl Session sibling emergency kill failed");
    if (!waitGracefulChild(child, shutdown_grace_ms))
        @panic("Howl Session sibling survived SIGKILL");
}
