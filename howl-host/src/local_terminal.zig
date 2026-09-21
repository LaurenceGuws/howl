//! Host-local owner for one in-process Howl Instance.
//!
//! Main owns the lifetime. Input owns the PTY service schedule. Render may resize
//! or borrow the opaque VT observation only while holding this owner's mutex.
//! No observation survives a mutation, and no GPU/display wait holds the lock.

const std = @import("std");
const c = @import("host_c");
const instance = @import("howl_instance");

const synchronized_output_timeout_ns: u64 = std.time.ns_per_s;

const Publication = struct {
    revision: u64,
    synchronized_started_ns: ?u64 = null,
    synchronized_pending: bool = false,
    synchronized_timed_out: bool = false,

    fn note(
        self: *Publication,
        current_revision: u64,
        synchronized: bool,
        now_ns: u64,
    ) bool {
        if (!synchronized) {
            const release_pending = self.synchronized_pending;
            self.synchronized_started_ns = null;
            self.synchronized_pending = false;
            self.synchronized_timed_out = false;
            if (current_revision == self.revision and !release_pending) return false;
            self.revision = current_revision;
            return true;
        }

        if (self.synchronized_timed_out) {
            if (current_revision == self.revision) return false;
            self.revision = current_revision;
            return true;
        }

        if (self.synchronized_started_ns == null)
            self.synchronized_started_ns = now_ns;
        const elapsed_ns = now_ns -| self.synchronized_started_ns.?;
        if (elapsed_ns < synchronized_output_timeout_ns) {
            self.synchronized_pending =
                self.synchronized_pending or current_revision != self.revision;
            return false;
        }

        self.synchronized_started_ns = null;
        self.synchronized_timed_out = true;
        const publish = self.synchronized_pending or current_revision != self.revision;
        self.synchronized_pending = false;
        if (publish) self.revision = current_revision;
        return publish;
    }

    fn arm(self: *const Publication, after_revision: u64) bool {
        return self.revision != after_revision;
    }
};

pub const PollState = struct {
    descriptor: i32,
    stream_closed: bool,
    write_pending: bool,
    animation_wait_ms: ?u32,
};

pub const Owner = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    value: *instance.Instance,
    mutex: std.Io.Mutex = .init,
    descriptor: i32,
    observation_fd: i32,
    stream_closed: bool = false,
    child_exit: ?instance.ChildExit = null,
    write_pending: bool = false,
    animation_wait_ms: ?u32 = null,
    publication: Publication,

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        inherited_environment: std.process.Environ,
        launch: instance.Launch,
    ) !Owner {
        const value = try instance.init(allocator, inherited_environment, launch);
        errdefer instance.deinit(value);
        const descriptor = try instance.descriptor(value);
        const initial_revision = instance.terminal(value).semanticSequence();
        const observation_fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
        if (observation_fd < 0) return error.Signal;
        return .{
            .allocator = allocator,
            .io = io,
            .value = value,
            .descriptor = descriptor,
            .observation_fd = observation_fd,
            .publication = .{ .revision = initial_revision },
        };
    }

    pub fn deinit(self: *Owner) void {
        closeDescriptor(self.observation_fd);
        instance.deinit(self.value);
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
    ) instance.ServiceError!instance.Service {
        self.mutex.lockUncancelable(self.io);
        const serviced = instance.service(
            self.value,
            readable,
            writable,
            timestamp_ns,
        ) catch |failure| {
            self.mutex.unlock(self.io);
            return failure;
        };
        const current_revision = instance.terminal(self.value).semanticSequence();
        const synchronized = instance.terminal(self.value).synchronizedOutput();
        const publish = self.publication.note(
            current_revision,
            synchronized,
            timestamp_ns,
        );
        self.mutex.unlock(self.io);

        const lifecycle_changed =
            serviced.stream_closed != self.stream_closed or
            (serviced.child_exit != null and self.child_exit == null);
        self.stream_closed = serviced.stream_closed;
        if (serviced.child_exit) |value| self.child_exit = value;
        self.write_pending = serviced.write_pending;
        self.animation_wait_ms = serviced.animation_wait_ms;
        if (publish or lifecycle_changed) signal(self.observation_fd);
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
        const ready = self.publication.arm(after_revision);
        self.mutex.unlock(self.io);
        if (ready) signal(self.observation_fd);
    }

    pub const ObservationGuard = struct {
        owner: *Owner,
        value: *const instance.Terminal.Observation,

        pub fn deinit(self: *ObservationGuard) void {
            self.owner.mutex.unlock(self.owner.io);
            self.* = undefined;
        }
    };

    /// Holds Instance mutation serialization for one synchronous observation use.
    pub fn observe(self: *Owner) ObservationGuard {
        self.mutex.lockUncancelable(self.io);
        return .{ .owner = self, .value = instance.terminal(self.value) };
    }

    pub fn input(self: *Owner, event: instance.Input) instance.InputError!void {
        self.mutex.lockUncancelable(self.io);
        instance.input(self.value, event) catch |failure| {
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
    ) instance.ResizeError!void {
        self.mutex.lockUncancelable(self.io);
        instance.resizeGeometry(
            self.value,
            rows,
            columns,
            cell_width,
            cell_height,
        ) catch |failure| {
            self.mutex.unlock(self.io);
            return failure;
        };
        self.publication.revision = instance.terminal(self.value).semanticSequence();
        self.mutex.unlock(self.io);
        signal(self.observation_fd);
    }

    pub fn interactionState(self: *Owner) instance.Terminal.InteractionState {
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

test "local publication withholds synchronized output until release or timeout" {
    var publication = Publication{ .revision = 10 };
    try std.testing.expect(!publication.note(11, true, 100));
    try std.testing.expectEqual(@as(u64, 10), publication.revision);
    try std.testing.expect(!publication.arm(10));
    try std.testing.expect(publication.synchronized_pending);

    try std.testing.expect(!publication.note(
        12,
        true,
        100 + synchronized_output_timeout_ns - 1,
    ));
    try std.testing.expectEqual(@as(u64, 10), publication.revision);

    try std.testing.expect(publication.note(
        12,
        false,
        100 + synchronized_output_timeout_ns - 1,
    ));
    try std.testing.expectEqual(@as(u64, 12), publication.revision);
    try std.testing.expect(!publication.synchronized_pending);

    try std.testing.expect(!publication.note(13, true, 500));
    try std.testing.expect(publication.note(
        13,
        true,
        500 + synchronized_output_timeout_ns,
    ));
    try std.testing.expectEqual(@as(u64, 13), publication.revision);
    try std.testing.expect(publication.synchronized_timed_out);

    try std.testing.expect(publication.note(
        14,
        true,
        500 + synchronized_output_timeout_ns + 1,
    ));
    try std.testing.expectEqual(@as(u64, 14), publication.revision);
}
