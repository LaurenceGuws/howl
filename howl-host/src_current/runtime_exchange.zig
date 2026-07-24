//! Owns the bounded state-and-wake boundary between Wayland and runtime threads.
//!
//! Window publishes copied latest state and ordered physical occurrences.
//! Render publishes only completion of newer revisions on the established GPU
//! surface. Neither side sends operations, borrows the other owner, or waits
//! for a reply.

const std = @import("std");
const c = @import("renderer_c");

pub const occurrence_limit: u16 = 256;
pub const key_text_limit: u8 = 64;

/// Copied coalescible Wayland truth interpreted only by Render.
pub const WindowState = struct {
    width: u32,
    height: u32,
    configured: bool,
    focused: bool,
    pointer_valid: bool,
    pointer_x: i32,
    pointer_y: i32,
    modifiers: u8,
    clipboard_mimes: u8,
    selection_serial: u32,
};

/// Preserves physical input and protocol occurrences that cannot coalesce.
pub const Occurrence = union(enum) {
    key: struct {
        code: u32,
        pressed: bool,
        repeated: bool,
        modifiers: u8,
        text: [key_text_limit]u8,
        text_len: u8,
    },
    pointer_button: struct {
        code: u32,
        pressed: bool,
        x: i32,
        y: i32,
        modifiers: u8,
    },
    pointer_wheel: struct {
        steps: i16,
        x: i32,
        y: i32,
        modifiers: u8,
    },
    close,
};

/// One complete inbound observation copied into caller-owned occurrence storage.
pub const Ingress = struct {
    state: WindowState,
    state_revision: u64,
    occurrences: []const Occurrence,
    shutdown: bool,
};

/// Identifies only completion state for the already-established GPU surface.
pub const SurfaceCompletion = struct {
    rendered_revision: u64,
    presented_revision: u64,
    shutdown: bool,
};

/// Owns two coalesced wake directions and the fixed ordered ingress ring.
pub const Exchange = struct {
    io: std.Io,
    mutex: std.Io.Mutex = .init,
    render_fd: c_int,
    window_fd: c_int,
    window_state: WindowState,
    window_revision: u64 = 1,
    ingress_pending: bool = true,
    occurrences: [occurrence_limit]Occurrence = undefined,
    occurrence_head: u16 = 0,
    occurrence_count: u16 = 0,
    rendered_revision: u64 = 0,
    presented_revision: u64 = 0,
    surface_dirty: bool = false,
    shutdown_requested: bool = false,

    /// Construct both nonblocking event descriptors and retain initial state.
    pub fn init(io: std.Io, initial: WindowState) error{Signal}!Exchange {
        const render_fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
        if (render_fd < 0) return error.Signal;
        errdefer closeFd(render_fd);
        const window_fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
        if (window_fd < 0) return error.Signal;
        errdefer closeFd(window_fd);
        const result = Exchange{
            .io = io,
            .render_fd = render_fd,
            .window_fd = window_fd,
            .window_state = initial,
        };
        try signalFd(result.render_fd);
        return result;
    }

    /// Release both descriptors after both owners have stopped.
    pub fn deinit(self: *Exchange) void {
        closeFd(self.window_fd);
        closeFd(self.render_fd);
        self.* = undefined;
    }

    /// Return the descriptor that wakes the Render owner.
    pub fn renderFd(self: *const Exchange) c_int {
        return self.render_fd;
    }

    /// Return the descriptor that wakes the Window owner.
    pub fn windowFd(self: *const Exchange) c_int {
        return self.window_fd;
    }

    /// Replace coalescible Wayland facts and preserve one pending wake.
    pub fn publishWindowState(
        self: *Exchange,
        state: WindowState,
    ) error{ Stopping, Signal }!void {
        self.mutex.lockUncancelable(self.io);
        if (self.shutdown_requested) {
            self.mutex.unlock(self.io);
            return error.Stopping;
        }
        self.window_state = state;
        self.window_revision = nextRevision(self.window_revision);
        const wake = !self.ingress_pending;
        self.ingress_pending = true;
        self.mutex.unlock(self.io);
        if (wake) try signalFd(self.render_fd);
    }

    /// Append one ordered occurrence or reject without changing the queue.
    pub fn pushOccurrence(
        self: *Exchange,
        occurrence: Occurrence,
    ) error{ Stopping, OccurrenceLimit, Signal }!void {
        self.mutex.lockUncancelable(self.io);
        if (self.shutdown_requested) {
            self.mutex.unlock(self.io);
            return error.Stopping;
        }
        if (self.occurrence_count == occurrence_limit) {
            self.mutex.unlock(self.io);
            return error.OccurrenceLimit;
        }
        const tail = (self.occurrence_head + self.occurrence_count) % occurrence_limit;
        self.occurrences[tail] = occurrence;
        self.occurrence_count += 1;
        const wake = !self.ingress_pending;
        self.ingress_pending = true;
        self.mutex.unlock(self.io);
        if (wake) try signalFd(self.render_fd);
    }

    /// Drain one wake and atomically take newest state plus every occurrence.
    pub fn takeIngress(
        self: *Exchange,
        storage: *[occurrence_limit]Occurrence,
    ) error{Signal}!Ingress {
        try drainFd(self.render_fd);
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        for (0..self.occurrence_count) |index| {
            const source = (self.occurrence_head + @as(u16, @intCast(index))) % occurrence_limit;
            storage[index] = self.occurrences[source];
        }
        const count = self.occurrence_count;
        self.occurrence_head = 0;
        self.occurrence_count = 0;
        self.ingress_pending = false;
        return .{
            .state = self.window_state,
            .state_revision = self.window_revision,
            .occurrences = storage[0..count],
            .shutdown = self.shutdown_requested,
        };
    }

    /// Publish completion of a newer revision on the existing GPU surface.
    pub fn publishRendered(
        self: *Exchange,
        revision: u64,
    ) error{ Stopping, StaleRevision, Signal }!void {
        self.mutex.lockUncancelable(self.io);
        if (self.shutdown_requested) {
            self.mutex.unlock(self.io);
            return error.Stopping;
        }
        if (revision <= self.rendered_revision) {
            self.mutex.unlock(self.io);
            return error.StaleRevision;
        }
        self.rendered_revision = revision;
        const wake = !self.surface_dirty;
        self.surface_dirty = true;
        self.mutex.unlock(self.io);
        if (wake) try signalFd(self.window_fd);
    }

    /// Observe the newest complete GPU revision without receiving frame data.
    pub fn takeSurfaceCompletion(self: *Exchange) error{Signal}!SurfaceCompletion {
        try drainFd(self.window_fd);
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.surface_dirty = false;
        return .{
            .rendered_revision = self.rendered_revision,
            .presented_revision = self.presented_revision,
            .shutdown = self.shutdown_requested,
        };
    }

    /// Acknowledge only a revision that Render has completed.
    pub fn acknowledgePresented(
        self: *Exchange,
        revision: u64,
    ) error{StaleRevision}!void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (revision < self.presented_revision or revision > self.rendered_revision)
            return error.StaleRevision;
        self.presented_revision = revision;
    }

    /// Revoke new publication and wake both owners out of blocking polls.
    pub fn shutdown(self: *Exchange) error{Signal}!void {
        self.mutex.lockUncancelable(self.io);
        const first = !self.shutdown_requested;
        self.shutdown_requested = true;
        self.ingress_pending = true;
        self.surface_dirty = true;
        self.mutex.unlock(self.io);
        if (!first) return;
        try signalFd(self.render_fd);
        try signalFd(self.window_fd);
    }
};

fn nextRevision(current: u64) u64 {
    return if (current == std.math.maxInt(u64)) 1 else current + 1;
}

fn signalFd(fd: c_int) error{Signal}!void {
    const value: u64 = 1;
    while (true) {
        const written = c.write(fd, &value, @sizeOf(u64));
        if (written == @sizeOf(u64)) return;
        if (written < 0 and std.posix.errno(written) == .INTR) continue;
        if (written < 0 and std.posix.errno(written) == .AGAIN) return;
        return error.Signal;
    }
}

fn drainFd(fd: c_int) error{Signal}!void {
    var value: u64 = 0;
    while (true) {
        const read = c.read(fd, &value, @sizeOf(u64));
        if (read == @sizeOf(u64)) return;
        if (read < 0 and std.posix.errno(read) == .INTR) continue;
        return error.Signal;
    }
}

fn closeFd(fd: c_int) void {
    std.debug.assert(c.close(fd) == 0);
}

fn initialState() WindowState {
    return .{
        .width = 800,
        .height = 600,
        .configured = true,
        .focused = false,
        .pointer_valid = false,
        .pointer_x = 0,
        .pointer_y = 0,
        .modifiers = 0,
        .clipboard_mimes = 0,
        .selection_serial = 0,
    };
}

const ConcurrentPublication = struct {
    exchange: *Exchange,
    done: std.atomic.Value(bool) = .init(false),
    failed: std.atomic.Value(bool) = .init(false),
};

fn publishConcurrentState(context: *ConcurrentPublication) void {
    var state = initialState();
    for (1..10_001) |revision| {
        state.width = @intCast(revision);
        context.exchange.publishWindowState(state) catch {
            context.failed.store(true, .release);
            break;
        };
    }
    context.done.store(true, .release);
}

test "latest Window state coalesces while ordered occurrences never collapse" {
    var exchange = try Exchange.init(std.testing.io, initialState());
    defer exchange.deinit();
    var storage: [occurrence_limit]Occurrence = undefined;
    const initial = try exchange.takeIngress(&storage);
    try std.testing.expectEqual(@as(u64, 1), initial.state_revision);

    var state = initialState();
    state.width = 900;
    try exchange.publishWindowState(state);
    state.width = 1000;
    try exchange.publishWindowState(state);
    try exchange.pushOccurrence(.{ .key = .{
        .code = 30,
        .pressed = true,
        .repeated = false,
        .modifiers = 1,
        .text = @splat(0),
        .text_len = 0,
    } });
    try exchange.pushOccurrence(.{ .key = .{
        .code = 30,
        .pressed = false,
        .repeated = false,
        .modifiers = 1,
        .text = @splat(0),
        .text_len = 0,
    } });
    const ingress = try exchange.takeIngress(&storage);
    try std.testing.expectEqual(@as(u32, 1000), ingress.state.width);
    try std.testing.expectEqual(@as(usize, 2), ingress.occurrences.len);
    try std.testing.expect(ingress.occurrences[0].key.pressed);
    try std.testing.expect(!ingress.occurrences[1].key.pressed);
}

test "full occurrence storage rejects without overwrite and drains in order" {
    var exchange = try Exchange.init(std.testing.io, initialState());
    defer exchange.deinit();
    var storage: [occurrence_limit]Occurrence = undefined;
    const empty = try exchange.takeIngress(&storage);
    try std.testing.expectEqual(@as(usize, 0), empty.occurrences.len);
    for (0..occurrence_limit) |index| try exchange.pushOccurrence(.{
        .pointer_wheel = .{
            .steps = @intCast(index),
            .x = 0,
            .y = 0,
            .modifiers = 0,
        },
    });
    try std.testing.expectError(
        error.OccurrenceLimit,
        exchange.pushOccurrence(.close),
    );
    const ingress = try exchange.takeIngress(&storage);
    try std.testing.expectEqual(@as(usize, occurrence_limit), ingress.occurrences.len);
    for (ingress.occurrences, 0..) |occurrence, index|
        try std.testing.expectEqual(@as(i16, @intCast(index)), occurrence.pointer_wheel.steps);
}

test "surface completion coalesces to newest revision without visual payload" {
    var exchange = try Exchange.init(std.testing.io, initialState());
    defer exchange.deinit();
    try exchange.publishRendered(1);
    try exchange.publishRendered(2);
    const completion = try exchange.takeSurfaceCompletion();
    try std.testing.expectEqual(@as(u64, 2), completion.rendered_revision);
    try std.testing.expectEqual(@as(u64, 0), completion.presented_revision);
    try exchange.acknowledgePresented(2);
    try std.testing.expectError(error.StaleRevision, exchange.acknowledgePresented(1));
}

test "consumer clear followed by simultaneous publication retains a wake" {
    var exchange = try Exchange.init(std.testing.io, initialState());
    defer exchange.deinit();
    var storage: [occurrence_limit]Occurrence = undefined;
    const empty = try exchange.takeIngress(&storage);
    try std.testing.expectEqual(@as(usize, 0), empty.occurrences.len);
    try exchange.pushOccurrence(.close);
    const first = try exchange.takeIngress(&storage);
    try std.testing.expectEqual(@as(usize, 1), first.occurrences.len);
    var state = initialState();
    state.focused = true;
    try exchange.publishWindowState(state);
    const second = try exchange.takeIngress(&storage);
    try std.testing.expect(second.state.focused);

    try exchange.publishRendered(1);
    const first_completion = try exchange.takeSurfaceCompletion();
    try std.testing.expectEqual(@as(u64, 1), first_completion.rendered_revision);
    try exchange.publishRendered(2);
    const newest = try exchange.takeSurfaceCompletion();
    try std.testing.expectEqual(@as(u64, 2), newest.rendered_revision);
}

test "concurrent latest-state publication and consumption cannot lose final wake" {
    var exchange = try Exchange.init(std.testing.io, initialState());
    defer exchange.deinit();
    var storage: [occurrence_limit]Occurrence = undefined;
    const initial = try exchange.takeIngress(&storage);
    try std.testing.expectEqual(@as(u64, 1), initial.state_revision);
    var context = ConcurrentPublication{ .exchange = &exchange };
    const producer = try std.Thread.spawn(.{}, publishConcurrentState, .{&context});
    var newest_width: u32 = 0;
    while (newest_width != 10_000) {
        var descriptor = [_]std.posix.pollfd{.{
            .fd = exchange.renderFd(),
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};
        const ready = try std.posix.poll(&descriptor, 1000);
        try std.testing.expect(ready != 0);
        const ingress = try exchange.takeIngress(&storage);
        newest_width = ingress.state.width;
    }
    producer.join();
    try std.testing.expect(context.done.load(.acquire));
    try std.testing.expect(!context.failed.load(.acquire));
}

test "shutdown wakes both directions and rejects later publication" {
    var exchange = try Exchange.init(std.testing.io, initialState());
    defer exchange.deinit();
    var storage: [occurrence_limit]Occurrence = undefined;
    const empty = try exchange.takeIngress(&storage);
    try std.testing.expectEqual(@as(usize, 0), empty.occurrences.len);
    try exchange.shutdown();
    const ingress = try exchange.takeIngress(&storage);
    const completion = try exchange.takeSurfaceCompletion();
    try std.testing.expect(ingress.shutdown);
    try std.testing.expect(completion.shutdown);
    try std.testing.expectError(
        error.Stopping,
        exchange.publishWindowState(initialState()),
    );
    try std.testing.expectError(error.Stopping, exchange.pushOccurrence(.close));
    try std.testing.expectError(error.Stopping, exchange.publishRendered(1));
}
