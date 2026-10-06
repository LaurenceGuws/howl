//! Host-local owner for one in-process Howl Instance.
//!
//! Main owns the lifetime. Input is the sole terminal thread: it services PTY,
//! mutates Instance/VT/Render state, applies geometry/history policy, and publishes
//! immutable Render frames. The GPU thread receives only the exchange and wake fd.

const std = @import("std");
const c = @import("host_c");
const instance = @import("howl_instance");
const presentation = @import("host_presentation");
const scrollback = @import("host_scrollback");

const synchronized_output_timeout_ns: u64 = std.time.ns_per_s;

const Publication = struct {
    revision: u64,
    // A lifecycle edge releases only this exact cut, not later descendant output.
    lifecycle_revision: ?u64 = null,
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
};

pub const PollState = struct {
    descriptor: i32,
    stream_closed: bool,
    write_pending: bool,
    read_pending: bool,
    animation_wait_ms: ?u32,
};

/// Reports canonical service or Instance-owned Render publication failure.
pub const ServiceError = instance.ServiceError || instance.PublishError;
/// Copies only terminal-thread interaction facts needed to route pointer input.
pub const PointerContext = struct {
    history_active: bool,
    alternate_screen: bool,
    interaction: instance.Terminal.InteractionState,
};

pub const Owner = struct {
    value: *instance.Instance,
    descriptor: i32,
    publication_fd: i32,
    stream_closed: bool = false,
    child_exit: ?instance.ChildExit = null,
    write_pending: bool = false,
    animation_wait_ms: ?u32 = null,
    publication: Publication,
    font: ?presentation.FontPaths = null,
    history: scrollback.State = .{},

    pub fn init(
        allocator: std.mem.Allocator,
        inherited_environment: std.process.Environ,
        launch: instance.Launch,
    ) !Owner {
        const value = try instance.init(allocator, inherited_environment, launch);
        errdefer instance.deinit(value);
        const descriptor = try instance.descriptor(value);
        const initial_revision = instance.terminal(value).semanticSequence();
        const publication_fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
        if (publication_fd < 0) return error.Signal;
        return .{
            .value = value,
            .descriptor = descriptor,
            .publication_fd = publication_fd,
            .publication = .{ .revision = initial_revision },
        };
    }

    /// Creates one presented Instance and publishes its initial immutable frame.
    pub fn initPresented(
        allocator: std.mem.Allocator,
        inherited_environment: std.process.Environ,
        launch: instance.Launch,
        font: presentation.FontPaths,
        font_pixels: u16,
    ) !Owner {
        const value = try instance.initPresented(
            allocator,
            inherited_environment,
            launch,
            presentation.config(font, font_pixels),
        );
        errdefer instance.deinit(value);
        const descriptor = try instance.descriptor(value);
        const initial_revision = instance.terminal(value).semanticSequence();
        const publication_fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
        if (publication_fd < 0) return error.Signal;
        errdefer closeDescriptor(publication_fd);
        try instance.publishRender(value);
        signal(publication_fd);
        return .{
            .value = value,
            .descriptor = descriptor,
            .publication_fd = publication_fd,
            .publication = .{ .revision = initial_revision },
            .font = font,
        };
    }

    pub fn deinit(self: *Owner) void {
        closeDescriptor(self.publication_fd);
        instance.deinit(self.value);
        self.* = undefined;
    }

    pub fn pollState(self: *const Owner) PollState {
        return .{
            .descriptor = if (self.stream_closed and !self.write_pending) -1 else self.descriptor,
            .stream_closed = self.stream_closed,
            .write_pending = self.write_pending,
            .read_pending = instance.bufferedOutputPending(self.value),
            .animation_wait_ms = self.animation_wait_ms,
        };
    }

    /// Services one canonical PTY/VT turn on the sole terminal thread.
    pub fn service(
        self: *Owner,
        readable: bool,
        writable: bool,
        timestamp_ns: u64,
    ) ServiceError!instance.Service {
        const serviced = try instance.service(
            self.value,
            readable,
            writable,
            timestamp_ns,
        );
        const current_revision = instance.terminal(self.value).semanticSequence();
        const synchronized = instance.terminal(self.value).synchronizedOutput();
        // A complete end/begin in this turn starts a new hold, even when the
        // previous frame had already earned timeout permission.
        if (serviced.synchronized_output.ended) {
            self.publication.synchronized_started_ns = null;
            self.publication.synchronized_timed_out = false;
        }
        const publish = self.publication.note(
            current_revision,
            synchronized,
            timestamp_ns,
        );

        const lifecycle_changed =
            serviced.stream_closed != self.stream_closed or
            (serviced.child_exit != null and self.child_exit == null);
        if (lifecycle_changed) {
            self.publication.revision = current_revision;
            self.publication.lifecycle_revision = current_revision;
        }
        self.stream_closed = serviced.stream_closed;
        if (serviced.child_exit) |value| self.child_exit = value;
        self.write_pending = serviced.write_pending;
        self.animation_wait_ms = serviced.animation_wait_ms;
        if ((publish or lifecycle_changed) and
            instance.presented(self.value) and
            !self.history.active())
        {
            try instance.publishRender(self.value);
        }
        if (publish or lifecycle_changed) signal(self.publication_fd);
        return serviced;
    }

    pub fn publicationFd(self: *const Owner) i32 {
        return self.publication_fd;
    }

    /// Borrows the backend-only Render exchange from a presented local Instance.
    pub fn renderExchange(self: *const Owner) error{PresentationUnavailable}!*instance.RenderExchange {
        return instance.renderExchange(self.value);
    }

    /// Applies one copied font-scale to a physical terminal surface.
    pub fn reconfigurePresentationSurface(
        self: *Owner,
        font_pixels: u16,
        width: u16,
        height: u16,
    ) !instance.PresentationGeometry {
        const font = self.font orelse return error.PresentationUnavailable;
        const geometry = try instance.reconfigurePresentationSurface(
            self.value,
            presentation.config(font, font_pixels),
            .{ .width = width, .height = height },
        );
        self.history.reset();
        self.publication.revision = instance.terminal(self.value).semanticSequence();
        try instance.publishRender(self.value);
        signal(self.publication_fd);
        return geometry;
    }

    /// Derives rows/columns from the current cell lattice and physical surface.
    pub fn resizeSurface(
        self: *Owner,
        width: u16,
        height: u16,
    ) !instance.PresentationGeometry {
        const cell = instance.terminal(self.value).cellPixelSize().?;
        const rows_u32 = @as(u32, height) / cell.height;
        const columns_u32 = @as(u32, width) / cell.width;
        if (rows_u32 == 0 or columns_u32 < 2 or
            rows_u32 > std.math.maxInt(u16) or
            columns_u32 > std.math.maxInt(u16))
            return error.InvalidDimensions;
        const rows: u16 = @intCast(rows_u32);
        const columns: u16 = @intCast(columns_u32);
        try instance.resize(self.value, rows, columns);
        self.history.reset();
        self.publication.revision = instance.terminal(self.value).semanticSequence();
        if (instance.presented(self.value)) {
            try instance.publishRender(self.value);
        }
        signal(self.publication_fd);
        return .{
            .cell_size = .{
                .width = @intCast(cell.width),
                .height = @intCast(cell.height),
            },
            .rows = rows,
            .columns = columns,
        };
    }

    /// Applies one wheel history delta on the terminal thread and publishes that cut.
    pub fn scrollHistory(self: *Owner, amount: i16) !bool {
        if (amount == 0) return false;
        if (!instance.presented(self.value) or self.presentationHeld())
            return false;
        const observation = instance.terminal(self.value);
        const live = observation.semanticView(0);
        var candidate = self.history;
        if (candidate.active())
            candidate.follow(
                live.history_count,
                live.history_row_base,
                live.is_alternate_screen,
            );
        const before = candidate.offset;
        candidate.scroll(
            amount,
            live.history_count,
            live.history_row_base,
            live.is_alternate_screen,
        );
        if (candidate.offset == before) {
            self.history = candidate;
            return false;
        }
        const accepted = observation.semanticView(candidate.offset);
        candidate.accept(
            accepted.history_offset,
            accepted.history_count,
            accepted.history_row_base,
            accepted.is_alternate_screen,
        );
        self.history = candidate;
        try instance.publishRenderAt(self.value, candidate.offset);
        signal(self.publication_fd);
        return true;
    }

    /// Copies current pointer-routing facts while Input owns the terminal thread.
    pub fn pointerContext(self: *Owner) PointerContext {
        const observation = instance.terminal(self.value);
        return .{
            .history_active = self.history.active(),
            .alternate_screen = observation.semanticView(0).is_alternate_screen,
            .interaction = observation.interactionState(),
        };
    }

    /// True while synchronized output intentionally withholds a live publication.
    fn presentationHeld(self: *const Owner) bool {
        return instance.terminal(self.value).synchronizedOutput() and
            !self.publication.synchronized_timed_out and
            self.publication.lifecycle_revision !=
                instance.terminal(self.value).semanticSequence();
    }

    /// Delivers one canonical input event on the sole terminal thread.
    pub fn input(self: *Owner, event: instance.Input) instance.InputError!void {
        return instance.input(self.value, event);
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
    var owner = try Owner.init(std.testing.allocator, std.testing.environ, .{
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
        const title = instance.terminal(owner.value).title();
        const ready_title = if (title) |value| std.mem.eql(u8, value, "READY") else false;
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
        const title = instance.terminal(owner.value).title();
        const acknowledged = if (title) |value| std.mem.eql(u8, value, "ACK") else false;
        if (acknowledged) return;
    }
    return error.Timeout;
}

test "local publication withholds synchronized output until release or timeout" {
    var publication = Publication{ .revision = 10 };
    try std.testing.expect(!publication.note(11, true, 100));
    try std.testing.expectEqual(@as(u64, 10), publication.revision);
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

fn testServiceCut(owner: *Owner, title: ?[]const u8, timestamp_ns: u64) !instance.Service {
    for (0..2000) |_| {
        const state = owner.pollState();
        var descriptor = c.pollfd{
            .fd = state.descriptor,
            .events = @intCast(c.POLLIN | c.POLLHUP | (if (state.write_pending) c.POLLOUT else 0)),
            .revents = 0,
        };
        const ready = c.poll(&descriptor, 1, if (state.read_pending and !state.write_pending) 0 else 1);
        if (ready < 0) {
            if (std.c.errno(ready) == .INTR) continue;
            return error.Poll;
        }
        const serviced = try owner.service(
            descriptor.revents & (c.POLLIN | c.POLLHUP) != 0,
            state.write_pending or descriptor.revents & c.POLLOUT != 0,
            timestamp_ns,
        );
        try std.testing.expect(!serviced.stream_closed and serviced.child_exit == null);
        const observation = instance.terminal(owner.value);
        const matched = if (title) |expected|
            (if (observation.title()) |value| std.mem.eql(u8, value, expected) else false)
        else
            serviced.synchronized_output.ended;
        if (matched) return serviced;
    }
    return error.Timeout;
}

test "local owner yields a released cut before renewing synchronized timeout protection" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    var owner = try Owner.init(std.testing.allocator, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf '\\033[?2026hA\\033]0;FIRST\\007'; read step; " ++
            "printf '\\033[?2026l\\033[?2026hB\\033]0;SECOND\\007'; read step; " ++
            "printf '\\033[?2026l\\033]0;DONE\\007'; read step",
        .rows = 2,
        .columns = 8,
        .history_rows = 8,
    });
    defer owner.deinit();
    try std.testing.expect((try testServiceCut(&owner, "FIRST", 10)).changed);
    try std.testing.expect(owner.publication.synchronized_pending);
    try std.testing.expect(!(try owner.service(false, false, 10 + synchronized_output_timeout_ns)).changed);
    try std.testing.expect(owner.publication.synchronized_timed_out);
    const published = owner.publication.revision;
    try owner.input(.{ .bytes = "go\n" });
    try std.testing.expect((try testServiceCut(&owner, null, 11 + synchronized_output_timeout_ns)).synchronized_output.ended);
    const released = owner.publication.revision;
    try std.testing.expect(released > published);
    const complete = instance.terminal(owner.value);
    try std.testing.expect(!complete.synchronizedOutput());
    try std.testing.expectEqual(
        @as(u21, 'A'),
        complete.semanticView(0).cellAt(0, 0),
    );
    const reopened = try testServiceCut(&owner, "SECOND", 11 + synchronized_output_timeout_ns);
    try std.testing.expect(!reopened.synchronized_output.ended);
    const current_observation = instance.terminal(owner.value);
    const synchronized = current_observation.synchronizedOutput();
    const current = current_observation.semanticSequence();
    try std.testing.expect(synchronized and current > published);
    try std.testing.expectEqual(released, owner.publication.revision);
    try std.testing.expect(!owner.publication.synchronized_timed_out);
    try std.testing.expect(owner.publication.synchronized_pending);
    try owner.input(.{ .bytes = "go\n" });
    try std.testing.expect((try testServiceCut(&owner, "DONE", 12 + synchronized_output_timeout_ns)).changed);
    try std.testing.expect(owner.publication.revision > current);
}

test "local owner new pending frame gets a fresh deadline but repeated begin does not" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    var owner = try Owner.init(std.testing.allocator, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf '\\033[?2026hA\\033]0;FIRST\\007'; read step; " ++
            "printf '\\033[?2026l\\033[?2026hB\\033]0;SECOND\\007'; read step; " ++
            "printf '\\033[?2026hC\\033]0;REPEATED\\007'; read step",
        .rows = 2,
        .columns = 8,
        .history_rows = 8,
    });
    defer owner.deinit();
    try std.testing.expect((try testServiceCut(&owner, "FIRST", 10)).changed);
    const old = owner.publication.revision;
    try owner.input(.{ .bytes = "go\n" });
    try std.testing.expect((try testServiceCut(&owner, null, 500)).synchronized_output.ended);
    const released = owner.publication.revision;
    try std.testing.expect(released > old);
    const second = try testServiceCut(&owner, "SECOND", 500);
    try std.testing.expect(!second.synchronized_output.ended);
    try std.testing.expectEqual(@as(?u64, 500), owner.publication.synchronized_started_ns);
    try std.testing.expectEqual(released, owner.publication.revision);
    try owner.input(.{ .bytes = "go\n" });
    const repeated = try testServiceCut(&owner, "REPEATED", 700);
    try std.testing.expect(!repeated.synchronized_output.ended);
    try std.testing.expectEqual(@as(?u64, 500), owner.publication.synchronized_started_ns);
    try std.testing.expect(!(try owner.service(false, false, 10 + synchronized_output_timeout_ns)).changed);
    try std.testing.expect(!owner.publication.synchronized_timed_out);
    try std.testing.expect(!(try owner.service(false, false, 500 + synchronized_output_timeout_ns)).changed);
    try std.testing.expect(owner.publication.synchronized_timed_out);
    try std.testing.expect(owner.publication.revision > old);
}
