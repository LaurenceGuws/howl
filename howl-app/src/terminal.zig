const std = @import("std");
const c = @import("desktop");
const instance = @import("howl_instance");
const policy = @import("publication.zig");
const posix = std.posix;

const queue_limit = 64;
const input_byte_limit = 1024 * 1024;

/// Bounded asynchronous semantic input and presentation-geometry intent.
pub const Task = union(enum) {
    input: instance.Input,
    resize: struct { rows: u16, columns: u16 },
    scroll: i32,
    seek: u32,
    retry_render,
};

/// Exact failures produced by this terminal worker's owned operations.
pub const Failure = instance.InputError || instance.ResizeError ||
    instance.ServiceError || std.posix.PollError;

/// Projection failure stays separate from canonical I/O and never stops PTY/VT service.
pub const PresentationFailure = instance.PublishError || error{SDLNotification};

/// Immutable lease transfer failures; no-frame leaves the previously accepted lease untouched.
pub const FrameError = instance.RenderLease.ReleaseError || error{ WrongExchange, NoPublishedFrame };

/// Exact transactional configuration/admission failures; old presentation survives failure.
pub const ConfigureError = instance.ReconfigurePresentationError || error{ TerminalStopped, InputQueueFull };

const Configuration = struct {
    config: instance.PresentationConfig,
    surface: ?instance.render.terminal.Size,
    result: ?instance.PresentationGeometry = null,
    failure: ?ConfigureError = null,
    complete: bool = false,
};
const Work = union(enum) { intent: Task, configure: *Configuration };

/// Copied interaction/lifecycle facts; contains no borrowed canonical storage.
pub const Status = struct {
    title: [1024]u8 = undefined,
    title_len: usize = 0,
    failure: ?Failure = null,
    presentation_failure: ?PresentationFailure = null,
    revision: u64 = 0,
    closed: bool = false,
    child_exit: ?instance.ChildExit = null,
    interaction: ?instance.Terminal.InteractionState = null,
    cursor_row: u16 = 0,
    cursor_col: u16 = 0,
};

/// Typed ownership boundary. SDL cannot obtain the live canonical Instance.
/// This is ordinary Zig composition; no C ABI, exported symbols or catalogue.
// zig-audit: acknowledge opaque_type
// reason: The terminal worker's canonical Instance and queue ownership must be inaccessible to the graphical consumer.
pub const Terminal = opaque {
    /// Constructs and starts one sole terminal owner; rolls back completed resources on failure.
    pub fn create(
        allocator: std.mem.Allocator,
        io: std.Io,
        environ: std.process.Environ,
        launch: instance.Launch,
        presentation: instance.PresentationConfig,
        event_type: u32,
        initially_visible: bool,
    ) !*Terminal {
        // zig-audit: acknowledge ptr_cast
        // reason: State owns this allocation; the opaque pointer keeps SDL outside canonical mutation authority without changing address or lifetime.
        return @ptrCast(try State.create(allocator, io, environ, launch, presentation, event_type, initially_visible));
    }

    /// Stops/joins the worker and retires its child; all graphical leases must already be retired.
    pub fn destroy(self: *Terminal) void {
        self.state().destroy();
    }
    /// Copies coherent UI routing/lifecycle facts under the bounded metadata lock.
    pub fn snapshot(self: *Terminal) Status {
        return self.state().snapshot();
    }
    /// Admits bounded typed work, copying text before returning and rejecting borrowed key text.
    pub fn submit(self: *Terminal, task: Task) !void {
        return self.state().submit(task);
    }
    /// Borrows a font recipe only until the sole worker completes its transaction.
    /// Waiting is uncancelable, so queued configuration cannot outlive these borrowed paths.
    pub fn reconfigure(self: *Terminal, config: instance.PresentationConfig, surface: ?instance.render.terminal.Size) ConfigureError!instance.PresentationGeometry {
        return self.state().reconfigure(config, surface);
    }
    /// Changes projection visibility without changing canonical service policy.
    pub fn setVisible(self: *Terminal, visible: bool) void {
        self.state().setVisible(visible);
    }
    /// Grants one projection credit after presentation or an explicit reveal.
    pub fn requestFrame(self: *Terminal) void {
        self.state().requestFrame();
    }
    /// Replaces the backend's old lease only when another publication is ready.
    /// A null result preserves the old lease; the short transfer contains no SDL work.
    pub fn replaceFrame(self: *Terminal, previous: ?*instance.RenderLease, residency: []const instance.render.terminal.Residency) FrameError!?instance.RenderLease {
        return self.state().replaceFrame(previous, residency);
    }

    fn state(self: *Terminal) *State {
        // zig-audit: acknowledge ptr_cast
        // reason: This module owns the concrete allocation behind its terminal-worker authority boundary.
        // zig-audit: acknowledge align_cast
        // reason: Only State.create produces Terminal pointers, preserving State alignment for their entire lifetime.
        return @ptrCast(@alignCast(self));
    }
};

/// Main owns lifetime; its terminal worker owns every live Instance mutation.
/// Main sees only immutable frame leases and bounded copied interaction facts.
const State = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    value: *instance.Instance,
    exchange: *instance.RenderExchange,
    wake_fd: posix.fd_t,
    event_type: u32,
    thread: ?std.Thread = null,
    mutex: std.Io.Mutex = .init,
    configured: std.Io.Condition = .init,
    frame_mutex: std.Io.Mutex = .init,
    tasks: [queue_limit]Work = undefined,
    head: usize = 0,
    count: usize = 0,
    input_bytes: usize = 0,
    stopping: bool = false,
    status: Status = .{},
    visible: std.atomic.Value(bool) = .init(true),
    credit: std.atomic.Value(bool) = .init(true),
    new_frame: std.atomic.Value(bool) = .init(false),
    gate: policy.Gate = .{},
    presentation_failure: ?PresentationFailure = null,
    history: policy.History = .{},

    fn create(
        allocator: std.mem.Allocator,
        io: std.Io,
        environ: std.process.Environ,
        launch: instance.Launch,
        presentation: instance.PresentationConfig,
        event_type: u32,
        initially_visible: bool,
    ) !*State {
        const self = try allocator.create(State);
        errdefer allocator.destroy(self);
        const value = try instance.initPresented(allocator, environ, launch, presentation);
        errdefer instance.deinit(value);
        const exchange = try instance.renderExchange(value);
        const fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
        if (fd < 0) return error.WakeFailed;
        errdefer closeWake(fd);
        self.* = .{
            .allocator = allocator,
            .io = io,
            .value = value,
            .exchange = exchange,
            .wake_fd = fd,
            .event_type = event_type,
            .visible = .init(initially_visible),
        };
        self.thread = try std.Thread.spawn(.{}, run, .{self});
        return self;
    }

    /// All backend leases must be retired before destroying this lifetime owner.
    fn destroy(self: *State) void {
        self.mutex.lockUncancelable(self.io);
        self.stopping = true;
        self.mutex.unlock(self.io);
        self.wake();
        if (self.thread) |thread| thread.join();
        self.cancelPending();
        closeWake(self.wake_fd);
        instance.deinit(self.value);
        const allocator = self.allocator;
        allocator.destroy(self);
    }

    fn takeFrame(self: *State) bool {
        return self.new_frame.swap(false, .acq_rel);
    }

    fn replaceFrame(self: *State, previous: ?*instance.RenderLease, residency: []const instance.render.terminal.Residency) FrameError!?instance.RenderLease {
        if (!self.new_frame.load(.acquire)) return null;
        self.frame_mutex.lockUncancelable(self.io);
        defer {
            self.frame_mutex.unlock(self.io);
            // A producer that skipped this short transfer never waits for the GUI.
            if (self.credit.load(.acquire)) self.wake();
        }
        if (!self.new_frame.load(.acquire)) return null;
        if (previous) |lease| {
            if (lease.exchange != self.exchange) return error.WrongExchange;
            try lease.release(residency);
        }
        const lease = instance.acquirePublishedFrame(self.exchange) orelse return error.NoPublishedFrame;
        self.new_frame.store(false, .release);
        return lease;
    }

    fn snapshot(self: *State) Status {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.status;
    }

    fn submit(self: *State, supplied: Task) !void {
        var task = supplied;
        const bytes = taskBytes(task);
        if (bytes.len > input_byte_limit) return error.InputLimit;
        // Key events contain no asynchronous borrowed text in this app.
        if (task == .input and task.input == .key and
            (task.input.key.text.len != 0 or task.input.key.legacy_text.len != 0))
            return error.BorrowedKeyText;
        if (bytes.len != 0) {
            const owned = try self.allocator.dupe(u8, bytes);
            switch (task.input) {
                .bytes => task.input.bytes = owned,
                .paste => task.input.paste = owned,
                // zig-audit: acknowledge unreachable
                // reason: taskBytes can return nonempty bytes only for these two input tags, and no mutation changes the active tag before this switch.
                else => unreachable,
            }
        }
        errdefer self.releaseTask(task);
        try self.admit(.{ .intent = task });
    }

    fn admit(self: *State, work: Work) error{ TerminalStopped, InputQueueFull }!void {
        const bytes = if (work == .intent) taskBytes(work.intent).len else 0;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.stopping or self.status.failure != null) return error.TerminalStopped;
        if (self.count == queue_limit or bytes > input_byte_limit - self.input_bytes) return error.InputQueueFull;
        self.tasks[(self.head + self.count) % queue_limit] = work;
        self.count += 1;
        self.input_bytes += bytes;
        self.wake();
    }

    fn reconfigure(self: *State, config: instance.PresentationConfig, surface: ?instance.render.terminal.Size) ConfigureError!instance.PresentationGeometry {
        var request: Configuration = .{ .config = config, .surface = surface };
        try self.admit(.{ .configure = &request });
        self.mutex.lockUncancelable(self.io);
        while (!request.complete) self.configured.waitUncancelable(self.io, &self.mutex);
        self.mutex.unlock(self.io);
        if (request.failure) |failure| return failure;
        return request.result.?;
    }

    fn completeConfiguration(self: *State, request: *Configuration, result: ConfigureError!instance.PresentationGeometry) void {
        self.mutex.lockUncancelable(self.io);
        if (result) |geometry| request.result = geometry else |failure| request.failure = failure;
        request.complete = true;
        self.configured.broadcast(self.io);
        // No request access follows unlock: the waiting caller can now retire its stack storage.
        self.mutex.unlock(self.io);
    }

    fn applyConfiguration(self: *State, request: *Configuration) void {
        const live = instance.terminal(self.value).semanticView(0);
        const result = if (request.surface) |surface|
            instance.reconfigurePresentationSurface(self.value, request.config, surface)
        else keep_grid: {
            const cell = instance.reconfigurePresentation(self.value, request.config) catch |failure| {
                self.completeConfiguration(request, failure);
                return;
            };
            break :keep_grid instance.PresentationGeometry{ .cell_size = cell, .rows = live.rows, .columns = live.cols };
        };
        if (result) |geometry| {
            if (geometry.columns != live.cols) self.history.reset();
            self.presentation_failure = null;
            self.mutex.lockUncancelable(self.io);
            self.status.presentation_failure = null;
            self.mutex.unlock(self.io);
            self.gate.pending = true;
            self.credit.store(true, .release);
            self.completeConfiguration(request, geometry);
        } else |failure| self.completeConfiguration(request, failure);
    }

    fn cancelPending(self: *State) void {
        while (self.pop()) |work| switch (work) {
            .intent => |task| self.releaseTask(task),
            .configure => |request| self.completeConfiguration(request, error.TerminalStopped),
        };
    }

    fn setVisible(self: *State, visible: bool) void {
        if (self.visible.swap(visible, .acq_rel) != visible) {
            if (visible) self.requestFrame();
            self.wake();
        }
    }

    /// Called only after successful SDL presentation, or an explicit reveal.
    fn requestFrame(self: *State) void {
        if (!self.credit.swap(true, .acq_rel)) self.wake();
    }

    fn pop(self: *State) ?Work {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.count == 0) return null;
        const task = self.tasks[self.head];
        self.head = (self.head + 1) % queue_limit;
        self.count -= 1;
        if (task == .intent) self.input_bytes -= taskBytes(task.intent).len;
        return task;
    }

    fn releaseTask(self: *State, task: Task) void {
        const bytes = taskBytes(task);
        if (bytes.len != 0) self.allocator.free(bytes);
    }

    fn stopRequested(self: *State) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.stopping;
    }

    fn apply(self: *State, task: Task) !void {
        const live = instance.terminal(self.value).semanticView(0);
        switch (task) {
            .input => |input| {
                // Committed input returns this pane to live; focus/mouse do not.
                if (input == .bytes or input == .paste or input == .key) {
                    if (self.history.offset != 0) self.gate.pending = true;
                    self.history.reset();
                }
                try instance.input(self.value, input);
            },
            .resize => |size| {
                if (size.rows != live.rows or size.columns != live.cols) {
                    if (size.columns != live.cols) self.history.reset();
                    try instance.resize(self.value, size.rows, size.columns);
                    self.gate.pending = true;
                }
            },
            .scroll => |delta| {
                self.history.scroll(delta, live.history_count, live.history_row_base, live.is_alternate_screen);
                self.gate.pending = true;
            },
            .seek => |offset| {
                self.history.seek(offset, live.history_count, live.history_row_base, live.is_alternate_screen);
                self.gate.pending = true;
            },
            .retry_render => {
                self.presentation_failure = null;
                self.mutex.lockUncancelable(self.io);
                self.status.presentation_failure = null;
                self.mutex.unlock(self.io);
                self.gate.pending = true;
                self.credit.store(true, .release);
            },
        }
    }

    fn service(self: *State, readable: bool, writable: bool, now: u64) !instance.Service {
        const result = try instance.serviceWithConsequencePolicy(self.value, readable, writable, now, .headless);
        const observation = instance.terminal(self.value);
        const live = observation.semanticView(0);
        self.history.follow(live.history_count, live.history_row_base, live.is_alternate_screen);
        self.gate.note(observation.semanticSequence(), observation.synchronizedOutput(), result.synchronized_output.ended, now);
        self.mutex.lockUncancelable(self.io);
        const lifecycle_changed = self.status.closed != result.stream_closed or
            (self.status.child_exit == null and result.child_exit != null);
        self.status.closed = result.stream_closed;
        self.status.child_exit = result.child_exit;
        self.status.interaction = observation.interactionState();
        self.status.cursor_row = live.cursor_row;
        self.status.cursor_col = live.cursor_col;
        self.status.revision = observation.semanticSequence();
        const title = observation.title() orelse "";
        const title_len = @min(title.len, self.status.title.len);
        const title_changed = title_len != self.status.title_len or
            !std.mem.eql(u8, self.status.title[0..self.status.title_len], title[0..title_len]);
        self.status.title_len = title_len;
        @memcpy(self.status.title[0..self.status.title_len], title[0..self.status.title_len]);
        self.mutex.unlock(self.io);
        if (lifecycle_changed or title_changed) self.notify();
        var published = false;
        if (self.presentation_failure == null and self.gate.pending and self.visible.load(.acquire) and
            self.gate.released(observation.synchronizedOutput()) and self.credit.load(.acquire))
        {
            // Projection may skip a stalled GUI transfer; canonical service never waits for it.
            if (!self.frame_mutex.tryLock()) return result;
            defer self.frame_mutex.unlock(self.io);
            std.debug.assert(self.credit.swap(false, .acq_rel));
            instance.publishRenderAt(self.value, self.history.offset) catch |failure| {
                if (failure == error.PublicationBusy) {
                    self.credit.store(true, .release);
                    return result;
                }
                self.presentation_failure = failure;
                self.mutex.lockUncancelable(self.io);
                self.status.presentation_failure = failure;
                self.mutex.unlock(self.io);
                self.notify();
                return result;
            };
            self.gate.pending = false;
            self.new_frame.store(true, .release);
            published = true;
        }
        if (published) self.notify();
        return result;
    }

    fn run(self: *State) void {
        self.loop() catch |failure| {
            self.mutex.lockUncancelable(self.io);
            self.status.failure = failure;
            self.mutex.unlock(self.io);
            self.cancelPending();
            self.notify();
        };
    }

    fn loop(self: *State) !void {
        var readable = true;
        var writable = true;
        while (!self.stopRequested()) {
            while (self.pop()) |work| switch (work) {
                .intent => |task| {
                    defer self.releaseTask(task);
                    try self.apply(task);
                },
                .configure => |request| self.applyConfiguration(request),
            };
            const now: u64 = @intCast(std.Io.Clock.awake.now(self.io).toNanoseconds());
            const result = try self.service(readable, writable, now);
            var timeout: i32 = if (result.stream_closed and result.child_exit == null) 50 else -1;
            for ([_]?i32{
                self.gate.waitMs(now),
                if (result.animation_wait_ms) |ms| @intCast(@min(ms, std.math.maxInt(i32))) else null,
            }) |deadline| {
                if (deadline) |ms| timeout = if (timeout < 0) ms else @min(timeout, ms);
            }
            if (instance.bufferedOutputPending(self.value)) timeout = 0;
            var fds = [_]posix.pollfd{
                .{
                    .fd = if (result.stream_closed and !result.write_pending) -1 else try instance.descriptor(self.value),
                    .events = posix.POLL.IN | posix.POLL.HUP | if (result.write_pending or instance.writePending(self.value)) @as(i16, posix.POLL.OUT) else 0,
                    .revents = 0,
                },
                .{ .fd = self.wake_fd, .events = posix.POLL.IN, .revents = 0 },
            };
            // zig-audit: acknowledge discard
            // reason: Readiness is consumed from each exact revents mask below; the aggregate ready count adds no authority.
            _ = try posix.poll(&fds, timeout);
            if (fds[1].revents & posix.POLL.IN != 0) self.drainWake();
            readable = fds[0].revents & (posix.POLL.IN | posix.POLL.HUP) != 0 or instance.bufferedOutputPending(self.value);
            writable = fds[0].revents & posix.POLL.OUT != 0;
        }
    }

    fn notify(self: *State) void {
        var event: c.SDL_Event = std.mem.zeroes(c.SDL_Event);
        event.type = self.event_type;
        if (!c.SDL_PushEvent(&event)) {
            self.mutex.lockUncancelable(self.io);
            if (self.status.presentation_failure == null) self.status.presentation_failure = error.SDLNotification;
            self.mutex.unlock(self.io);
        }
    }

    fn wake(self: *State) void {
        const one: u64 = 1;
        while (true) {
            const result = posix.system.write(self.wake_fd, std.mem.asBytes(&one).ptr, 8);
            switch (posix.errno(result)) {
                .INTR => continue,
                .SUCCESS, .AGAIN => return,
                // zig-audit: acknowledge panic
                // reason: The eventfd belongs to this live State until its worker joins; EBADF or any non-EINTR/non-saturation failure is an impossible ownership violation.
                else => @panic("terminal wake descriptor failed"),
            }
        }
    }

    fn drainWake(self: *State) void {
        var value: u64 = undefined;
        while (true) {
            const result = posix.system.read(self.wake_fd, std.mem.asBytes(&value).ptr, 8);
            switch (posix.errno(result)) {
                .INTR => continue,
                .SUCCESS, .AGAIN => return,
                // zig-audit: acknowledge panic
                // reason: The worker exclusively reads its live eventfd, whose lifetime ends only after join; unexpected descriptor errors violate construction/cleanup ownership.
                else => @panic("terminal wake drain failed"),
            }
        }
    }
};

fn taskBytes(task: Task) []const u8 {
    if (task != .input) return "";
    return switch (task.input) {
        .bytes => |bytes| bytes,
        .paste => |bytes| bytes,
        else => "",
    };
}

fn testPresentation() instance.PresentationConfig {
    return .{
        .fonts = .{ .regular = .{ .path = .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 15 } } } },
        .box_drawing = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
        .shape_cache = .{ .entry_capacity = 32, .scalar_capacity = 128, .glyph_capacity = 128, .max_sequence_scalars = 16 },
        .atlas = .{ .width = 256, .height = 256, .entry_capacity = 128 },
        .shaped_capacity = 128,
        .raster_bytes = 256 * 256,
        .command_capacity = 256,
        .command_limit = instance.render.limits.maximum_frame_commands,
    };
}

fn waitTitle(owner: *Terminal, title: []const u8) !void {
    var attempt: u16 = 0;
    while (attempt < 5000) : (attempt += 1) {
        const status = owner.snapshot();
        if (status.failure) |failure| return failure;
        if (std.mem.eql(u8, status.title[0..status.title_len], title)) return;
        try std.Io.sleep(owner.state().io, .fromMilliseconds(1), .awake);
    }
    return error.Timeout;
}

test "hidden presentation still drains one MiB and semantic input to the sole canonical owner" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "printf '\\033]0;READY\\007'; read line; dd if=/dev/zero bs=1024 count=1024 2>/dev/null | tr '\\000' x; printf '\\033]0;%s\\007' \"$line\"; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, testPresentation(), c.SDL_RegisterEvents(1), false);
    defer owner.destroy();
    try waitTitle(owner, "READY");
    const submitted = try std.testing.allocator.dupe(u8, "DONE\n");
    try owner.submit(.{ .input = .{ .bytes = submitted } });
    @memset(submitted, '?');
    std.testing.allocator.free(submitted);
    try waitTitle(owner, "DONE");
    try std.testing.expect(!owner.state().takeFrame());
    try std.testing.expect(instance.acquirePublishedFrame(owner.state().exchange) == null);
    // Oversized input and borrowed key text are rejected without mutation.
    const oversized = try std.testing.allocator.alloc(u8, input_byte_limit + 1);
    defer std.testing.allocator.free(oversized);
    try std.testing.expectError(error.InputLimit, owner.submit(.{ .input = .{ .paste = oversized } }));
    try std.testing.expectError(error.BorrowedKeyText, owner.submit(.{ .input = .{ .key = .{ .key = .{ .named = .enter }, .text = "borrowed" } } }));
}

test "a held immutable publication cannot pace canonical progress or prevent cleanup" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "printf '\\033]0;READY\\007'; read line; dd if=/dev/zero bs=1024 count=1024 2>/dev/null | tr '\\000' x; printf '\\033]0;DONE\\007'; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, testPresentation(), c.SDL_RegisterEvents(1), true);
    defer owner.destroy();
    try waitTitle(owner, "READY");
    try waitFrame(owner);
    var lease = instance.acquirePublishedFrame(owner.state().exchange) orelse return error.MissingFrame;
    defer lease.abandon();
    const before = lease.value.terminal_revision;
    const first = lease.value.commands[0];
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "DONE");
    try std.testing.expectEqual(before, lease.value.terminal_revision);
    try std.testing.expectEqualDeep(first, lease.value.commands[0]);
    try std.testing.expectEqual(@as(?Failure, null), owner.snapshot().failure);
}

fn waitFrame(owner: *Terminal) !void {
    var attempt: u16 = 0;
    while (attempt < 5000) : (attempt += 1) {
        if (owner.state().takeFrame()) return;
        if (owner.snapshot().failure) |failure| return failure;
        try std.Io.sleep(owner.state().io, .fromMilliseconds(1), .awake);
    }
    return error.Timeout;
}

test "synchronized hold releases a new frame after one second without further child output" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf '\\033]0;READY\\007'; read line; printf '\\033[?2026hX'; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, testPresentation(), c.SDL_RegisterEvents(1), true);
    defer owner.destroy();
    try waitTitle(owner, "READY");
    try waitFrame(owner);
    var initial = instance.acquirePublishedFrame(owner.state().exchange) orelse return error.MissingFrame;
    const ready_revision = owner.snapshot().revision;
    if (initial.value.terminal_revision < ready_revision) {
        try initial.release(&.{});
        owner.requestFrame();
        try waitFrame(owner);
        initial = instance.acquirePublishedFrame(owner.state().exchange) orelse return error.MissingFrame;
    }
    try std.testing.expectEqual(ready_revision, initial.value.terminal_revision);
    const revision = initial.value.terminal_revision;
    try initial.release(&.{});
    const start = std.Io.Clock.awake.now(owner.state().io);
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    owner.requestFrame();
    try waitFrame(owner);
    const elapsed = start.durationTo(std.Io.Clock.awake.now(owner.state().io)).toMilliseconds();
    if (elapsed < 800) {
        std.debug.print("hold published too early: {d}ms after input, initial revision {d}, canonical revision {d}\n", .{ elapsed, revision, owner.snapshot().revision });
        return error.EarlyPublication;
    }
    var released = instance.acquirePublishedFrame(owner.state().exchange) orelse return error.MissingFrame;
    defer released.abandon();
    try std.testing.expect(released.value.terminal_revision > revision);
}

test "failed font construction frees the unobservable terminal owner" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    var presentation = testPresentation();
    presentation.fonts.regular = .{ .path = .{ .primary = "/definitely-missing-howl-font.ttf", .size = .{ .pixels = 15 } } };
    const owner = Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .rows = 4,
        .columns = 20,
    }, presentation, 0, false);
    try std.testing.expectError(error.FontOpen, owner);
}

fn closeWake(fd: posix.fd_t) void {
    const result = posix.system.close(fd);
    const status = posix.errno(result);
    // Linux consumes the descriptor even when close reports EINTR.
    std.debug.assert(status == .SUCCESS or status == .INTR);
}

test "projection failure leaves canonical output and input alive" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    var presentation = testPresentation();
    presentation.command_capacity = 16;
    presentation.command_limit = 16;
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf '\\033]0;READY\\007'; read line; i=0; while [ $i -lt 32 ]; do printf '\\033[41mX\\033[42mY'; i=$((i + 1)); done; printf '\\033[0m'; printf '\\033]0;FIRST\\007'; read line; printf '\\033]0;SECOND\\007'; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, presentation, c.SDL_RegisterEvents(1), true);
    defer owner.destroy();
    try waitTitle(owner, "READY");
    try waitFrame(owner);
    var initial = instance.acquirePublishedFrame(owner.state().exchange) orelse return error.MissingFrame;
    try initial.release(&.{});
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "FIRST");
    owner.requestFrame();
    var attempts: u16 = 0;
    while (owner.snapshot().presentation_failure == null and attempts < 5000) : (attempts += 1)
        try std.Io.sleep(owner.state().io, .fromMilliseconds(1), .awake);
    try std.testing.expect(owner.snapshot().presentation_failure != null);
    try std.testing.expectEqual(@as(?Failure, null), owner.snapshot().failure);
    try owner.submit(.{ .input = .{ .bytes = "CONTINUE\n" } });
    try waitTitle(owner, "SECOND");
    try std.testing.expectEqual(@as(?Failure, null), owner.snapshot().failure);
}

test "visibility affirmation cannot manufacture presentation credits; reveal can" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf '\\033]0;READY\\007'; read line; printf 'X\\033]0;FIRST\\007'; read line; printf '\\033]0;SECOND\\007'; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, testPresentation(), c.SDL_RegisterEvents(1), true);
    defer owner.destroy();
    try waitTitle(owner, "READY");
    try waitFrame(owner);
    var initial = instance.acquirePublishedFrame(owner.state().exchange) orelse return error.MissingFrame;
    try initial.release(&.{});
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "FIRST");
    for (0..16) |_| owner.setVisible(true);
    try owner.submit(.{ .input = .{ .bytes = "END\n" } });
    try waitTitle(owner, "SECOND");
    try std.testing.expect(!owner.state().takeFrame());
    try std.testing.expect(instance.acquirePublishedFrame(owner.state().exchange) == null);
    owner.setVisible(false);
    owner.setVisible(true);
    try waitFrame(owner);
    var revealed = instance.acquirePublishedFrame(owner.state().exchange) orelse return error.MissingFrame;
    defer revealed.abandon();
    try std.testing.expectEqual(owner.snapshot().revision, revealed.value.terminal_revision);
}

test "font configuration rolls back failure and replaces geometry while an older immutable lease stays held" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf '\\033]0;READY\\007'; read line; printf '\\033]0;CONTINUED\\007'; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, testPresentation(), c.SDL_RegisterEvents(1), true);
    defer owner.destroy();
    try waitTitle(owner, "READY");
    try waitFrame(owner);
    var held = instance.acquirePublishedFrame(owner.state().exchange) orelse return error.MissingFrame;
    const old_generation = held.value.presentation_generation;
    const old_size = held.value.cell_size;
    var invalid = testPresentation();
    invalid.fonts.regular = .{ .path = .{ .primary = "/missing-howl-live-font.ttf", .size = .{ .pixels = 18 } } };
    try std.testing.expectError(error.FontOpen, owner.reconfigure(invalid, null));
    try std.testing.expectEqual(old_generation, held.value.presentation_generation);
    try std.testing.expectEqualDeep(old_size, held.value.cell_size);
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "CONTINUED");
    var larger = testPresentation();
    larger.fonts.regular.path.size = .{ .pixels = 18 };
    const surface: instance.render.terminal.Size = .{ .width = 200, .height = 150 };
    const geometry = try owner.reconfigure(larger, surface);
    try std.testing.expectEqual(surface.width / geometry.cell_size.width, geometry.columns);
    try std.testing.expectEqual(surface.height / geometry.cell_size.height, geometry.rows);
    try std.testing.expectEqual(old_generation, held.value.presentation_generation);
    try std.testing.expectEqualDeep(old_size, held.value.cell_size);
    try held.release(&.{});
    try waitFrame(owner);
    var changed = instance.acquirePublishedFrame(owner.state().exchange) orelse return error.MissingFrame;
    defer changed.abandon();
    try std.testing.expect(changed.value.presentation_generation > old_generation);
    try std.testing.expectEqualDeep(geometry.cell_size, changed.value.cell_size);
    try std.testing.expectEqual(@as(?Failure, null), owner.snapshot().failure);
}

test "canonical failure rejects or releases borrowed configuration before its caller retires" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "sleep 30",
        .rows = 4,
        .columns = 20,
    }, testPresentation(), c.SDL_RegisterEvents(1), false);
    defer owner.destroy();
    try owner.submit(.{ .resize = .{ .rows = 0, .columns = 0 } });
    try std.testing.expectError(error.TerminalStopped, owner.reconfigure(testPresentation(), null));
    try std.testing.expect(owner.snapshot().failure != null);
}

test "a stalled backend lease transfer cannot pace canonical output; no-frame preserves the accepted lease" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf '\\033]0;READY\\007'; read line; dd if=/dev/zero bs=1024 count=1024 2>/dev/null | tr '\\000' x; printf '\\033]0;DONE\\007'; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, testPresentation(), c.SDL_RegisterEvents(1), true);
    defer owner.destroy();
    try waitTitle(owner, "READY");
    var initial: ?instance.RenderLease = null;
    var attempts: u16 = 0;
    while (initial == null and attempts < 5000) : (attempts += 1) {
        initial = try owner.replaceFrame(null, &.{});
        if (initial == null) try std.Io.sleep(owner.state().io, .fromMilliseconds(1), .awake);
    }
    var held = initial orelse return error.MissingFrame;
    defer held.abandon();
    try std.testing.expect(try owner.replaceFrame(&held, &.{}) == null);
    try std.testing.expect(!held.released);
    const sequence = held.value.sequence;
    owner.state().frame_mutex.lockUncancelable(owner.state().io);
    var locked = true;
    defer if (locked) owner.state().frame_mutex.unlock(owner.state().io);
    owner.requestFrame();
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    try waitTitle(owner, "DONE");
    try std.testing.expectEqual(sequence, held.value.sequence);
    owner.state().frame_mutex.unlock(owner.state().io);
    locked = false;
    owner.requestFrame();
    owner.state().wake();
    const other = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "sleep 30",
        .rows = 4,
        .columns = 20,
    }, testPresentation(), c.SDL_RegisterEvents(1), true);
    defer other.destroy();
    var other_frame: ?instance.RenderLease = null;
    attempts = 0;
    while (other_frame == null and attempts < 5000) : (attempts += 1) {
        other_frame = try other.replaceFrame(null, &.{});
        if (other_frame == null) try std.Io.sleep(owner.state().io, .fromMilliseconds(1), .awake);
    }
    var foreign = other_frame orelse return error.MissingFrame;
    defer foreign.abandon();
    attempts = 0;
    while (!owner.state().new_frame.load(.acquire) and attempts < 5000) : (attempts += 1)
        try std.Io.sleep(owner.state().io, .fromMilliseconds(1), .awake);
    if (attempts == 5000) return error.Timeout;
    try std.testing.expectError(error.WrongExchange, owner.replaceFrame(&foreign, &.{}));
    try std.testing.expect(!foreign.released and !held.released);
    var replacement: ?instance.RenderLease = null;
    attempts = 0;
    while (replacement == null and attempts < 5000) : (attempts += 1) {
        replacement = try owner.replaceFrame(&held, &.{});
        if (replacement == null) try std.Io.sleep(owner.state().io, .fromMilliseconds(1), .awake);
    }
    var changed = replacement orelse return error.MissingFrame;
    defer changed.abandon();
    try std.testing.expect(held.released);
    try std.testing.expect(changed.value.sequence > sequence);
    try std.testing.expect(try owner.replaceFrame(&changed, &.{}) == null);
    try std.testing.expect(!changed.released);
}

test "semantic mouse reports and copied caret facts survive without a graphical observer" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const owner = try Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty raw -echo; printf '\\033[?1002h\\033[?1006h\\033]0;READY\\007'; bytes=$(dd bs=1 count=18 2>/dev/null | od -An -tx1 | tr -d ' \\n'); printf '\\033[2;5H\\033]0;%s\\007' \"$bytes\"; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, testPresentation(), c.SDL_RegisterEvents(1), false);
    defer owner.destroy();
    try waitTitle(owner, "READY");
    const before = owner.snapshot();
    try std.testing.expectEqual(instance.Terminal.MouseTrackingMode.button_event, before.interaction.?.mouse_tracking);
    try owner.submit(.{ .input = .{ .mouse = .{ .kind = .press, .button = .left, .row = 2, .col = 3, .mod = .{}, .buttons_down = 1 } } });
    try owner.submit(.{ .input = .{ .mouse = .{ .kind = .release, .button = .left, .row = 2, .col = 3, .mod = .{}, .buttons_down = 0 } } });
    try waitTitle(owner, "1b5b3c303b343b334d1b5b3c303b343b336d");
    const after = owner.snapshot();
    try std.testing.expectEqual(@as(u16, 1), after.cursor_row);
    try std.testing.expectEqual(@as(u16, 4), after.cursor_col);
    try std.testing.expect(!owner.state().takeFrame());
}
