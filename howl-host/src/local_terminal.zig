//! Host-local owner for one in-process Howl Session.
//!
//! Main owns the lifetime. Input owns the PTY service schedule. Render may resize
//! or borrow the opaque VT observation only while holding this owner's mutex.
//! No observation survives a mutation, and no GPU/display wait holds the lock.

const std = @import("std");
const c = @import("host_c");
const session = @import("howl_session");

pub const PollState = struct {
    descriptor: i32,
    stream_closed: bool,
    write_pending: bool,
    animation_wait_ms: ?u32,
};

pub const Owner = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    value: *session.Session,
    mutex: std.Io.Mutex = .init,
    descriptor: i32,
    observation_fd: i32,
    stream_closed: bool = false,
    child_exit: ?session.ChildExit = null,
    write_pending: bool = false,
    animation_wait_ms: ?u32 = null,

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        inherited_environment: std.process.Environ,
        launch: session.Launch,
    ) !Owner {
        const value = try session.init(allocator, inherited_environment, launch);
        errdefer session.deinit(value);
        const descriptor = try session.descriptor(value);
        const observation_fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
        if (observation_fd < 0) return error.Signal;
        return .{
            .allocator = allocator,
            .io = io,
            .value = value,
            .descriptor = descriptor,
            .observation_fd = observation_fd,
        };
    }

    pub fn deinit(self: *Owner) void {
        closeDescriptor(self.observation_fd);
        session.deinit(self.value);
        self.* = undefined;
    }

    pub fn pollState(self: *const Owner) PollState {
        return .{
            .descriptor = if (self.stream_closed and !self.write_pending) -1 else self.descriptor,
            .stream_closed = self.stream_closed,
            .write_pending = self.write_pending,
            .animation_wait_ms = self.animation_wait_ms,
        };
    }

    /// Services one canonical PTY/VT turn. Polling remains Input-owned and never
    /// holds this mutex.
    pub fn service(
        self: *Owner,
        readable: bool,
        writable: bool,
        timestamp_ns: u64,
    ) session.ServiceError!session.Service {
        self.mutex.lockUncancelable(self.io);
        const serviced = session.service(
            self.value,
            readable,
            writable,
            timestamp_ns,
        ) catch |failure| {
            self.mutex.unlock(self.io);
            return failure;
        };
        self.mutex.unlock(self.io);

        const lifecycle_changed =
            serviced.stream_closed != self.stream_closed or
            (serviced.child_exit != null and self.child_exit == null);
        self.stream_closed = serviced.stream_closed;
        if (serviced.child_exit) |value| self.child_exit = value;
        self.write_pending = serviced.write_pending;
        self.animation_wait_ms = serviced.animation_wait_ms;
        if (serviced.changed or lifecycle_changed) signal(self.observation_fd);
        return serviced;
    }

    pub fn observationFd(self: *const Owner) i32 {
        return self.observation_fd;
    }

    pub fn drainObservationWake(self: *Owner) error{Signal}!void {
        try drain(self.observation_fd);
    }

    /// Ensures Render observes a semantic mutation which raced its arm operation.
    pub fn armObservation(self: *Owner, after_revision: u64) void {
        self.mutex.lockUncancelable(self.io);
        const current = session.terminal(self.value).semanticSequence();
        self.mutex.unlock(self.io);
        if (current != after_revision) signal(self.observation_fd);
    }

    pub const ObservationGuard = struct {
        owner: *Owner,
        value: *const session.Terminal.Observation,

        pub fn deinit(self: *ObservationGuard) void {
            self.owner.mutex.unlock(self.owner.io);
            self.* = undefined;
        }
    };

    /// Holds Session mutation serialization for one synchronous observation use.
    pub fn observe(self: *Owner) ObservationGuard {
        self.mutex.lockUncancelable(self.io);
        return .{ .owner = self, .value = session.terminal(self.value) };
    }

    pub fn input(self: *Owner, event: session.Input) session.InputError!void {
        self.mutex.lockUncancelable(self.io);
        session.input(self.value, event) catch |failure| {
            self.mutex.unlock(self.io);
            return failure;
        };
        self.mutex.unlock(self.io);
    }

    pub fn resizeGeometry(
        self: *Owner,
        rows: u16,
        columns: u16,
        cell_width: u16,
        cell_height: u16,
    ) session.ResizeError!void {
        self.mutex.lockUncancelable(self.io);
        session.resizeGeometry(
            self.value,
            rows,
            columns,
            cell_width,
            cell_height,
        ) catch |failure| {
            self.mutex.unlock(self.io);
            return failure;
        };
        self.mutex.unlock(self.io);
        signal(self.observation_fd);
    }

    pub fn interactionState(self: *Owner) session.Terminal.InteractionState {
        var guard = self.observe();
        defer guard.deinit();
        return guard.value.interactionState();
    }
};

pub fn monotonicNs() error{Clock}!u64 {
    var now: std.posix.timespec = undefined;
    if (std.posix.errno(std.posix.system.clock_gettime(std.posix.CLOCK.MONOTONIC, &now)) != .SUCCESS)
        return error.Clock;
    const seconds = std.math.mul(u64, @intCast(now.sec), std.time.ns_per_s) catch
        return error.Clock;
    return std.math.add(u64, seconds, @intCast(now.nsec)) catch error.Clock;
}

fn signal(descriptor: i32) void {
    const value: u64 = 1;
    while (true) {
        const result = c.write(descriptor, &value, @sizeOf(u64));
        if (result == @sizeOf(u64)) return;
        if (result < 0 and std.c.errno(result) == .INTR) continue;
        if (result < 0 and std.c.errno(result) == .AGAIN) return;
        @panic("local terminal eventfd signal failed");
    }
}

fn drain(descriptor: i32) error{Signal}!void {
    var value: u64 = 0;
    while (true) {
        const result = c.read(descriptor, &value, @sizeOf(u64));
        if (result == @sizeOf(u64)) continue;
        if (result < 0 and std.c.errno(result) == .INTR) continue;
        if (result < 0 and std.c.errno(result) == .AGAIN) return;
        return error.Signal;
    }
}

fn closeDescriptor(descriptor: i32) void {
    if (c.close(descriptor) != 0) @panic("local terminal descriptor cleanup failed");
}

test "local terminal owner serializes service input and observation without an endpoint" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    var owner = try Owner.init(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "printf '\\033]0;READY\\007'; read line; printf '\\033]0;%s\\007' \"$line\"",
        .rows = 4,
        .columns = 20,
        .history_rows = 16,
    });
    defer owner.deinit();

    var attempts: u16 = 0;
    while (attempts < 2000) : (attempts += 1) {
        var descriptor = c.pollfd{
            .fd = owner.descriptor,
            .events = @intCast(c.POLLIN | c.POLLHUP),
            .revents = 0,
        };
        const ready = c.poll(&descriptor, 1, 1);
        if (ready < 0 and std.c.errno(ready) != .INTR) return error.Poll;
        const serviced = try owner.service(
            ready > 0 and descriptor.revents & (c.POLLIN | c.POLLHUP) != 0,
            false,
            try monotonicNs(),
        );
        try std.testing.expectEqual(serviced.write_pending, owner.pollState().write_pending);
        var guard = owner.observe();
        const title = guard.value.title();
        const ready_title = if (title) |value| std.mem.eql(u8, value, "READY") else false;
        guard.deinit();
        if (ready_title) break;
    } else return error.Timeout;

    try owner.input(.{ .bytes = "ACK\n" });
    attempts = 0;
    while (attempts < 2000) : (attempts += 1) {
        const state = owner.pollState();
        var descriptor = c.pollfd{
            .fd = state.descriptor,
            .events = @intCast(c.POLLIN | c.POLLHUP | (if (state.write_pending) c.POLLOUT else 0)),
            .revents = 0,
        };
        const ready = c.poll(&descriptor, 1, 1);
        if (ready < 0 and std.c.errno(ready) != .INTR) return error.Poll;
        const serviced = try owner.service(
            ready > 0 and descriptor.revents & (c.POLLIN | c.POLLHUP) != 0,
            state.write_pending or ready > 0 and descriptor.revents & c.POLLOUT != 0,
            try monotonicNs(),
        );
        try std.testing.expectEqual(serviced.write_pending, owner.pollState().write_pending);
        var guard = owner.observe();
        const title = guard.value.title();
        const acknowledged = if (title) |value| std.mem.eql(u8, value, "ACK") else false;
        guard.deinit();
        if (acknowledged) return;
    }
    return error.Timeout;
}
