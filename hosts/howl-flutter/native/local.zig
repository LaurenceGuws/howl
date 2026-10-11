//! Flutter's direct desktop Instance worker. No wire, streams or Server identity.
//!
//! One worker serializes mutations and synchronous const observation callbacks.
//! Callers retain request/output storage until completion. Waiting observers do
//! not hold the queue mutex or delay canonical PTY/VT service.
const std = @import("std");
const builtin = @import("builtin");
const instance = @import("howl_instance");
const desktop = (builtin.os.tag == .linux and builtin.abi != .android) or builtin.os.tag == .windows;
const maximum_requests: usize = 32;
const service_wait_ms: u32 = 20;

/// Hides the exclusive worker and its canonical Instance.
// zig-audit: acknowledge opaque_type
// reason: Only this host-private module can mutate or retire its worker and canonical Instance.
pub const Owner = opaque {};
/// Exact projection and private packet failures admitted by a synchronous query.
pub const ProjectionError = instance.render.terminal.Error || instance.Terminal.TextError || error{
    BufferTooSmall,
    ResourceLimit,
    MissingResource,
    InvalidFrame,
    IntegerOverflow,
    InvalidResidency,
    InvalidHost,
    ImageRefillRequired,
    LocalRejected,
};
/// Exact construction, canonical mutation, service and request failures.
pub const Error = instance.InitError || instance.InputError || instance.ResizeError ||
    instance.ServiceError || ProjectionError || error{
    LocalUnsupported,
    LocalUnavailable,
    LocalQueueFull,
    LocalCanceled,
    LocalThreadFailed,
};
/// Copied process/presentation revision facts, independent of wire-client identity.
pub const Facts = struct { revision: u64, stream_closed: bool, child_exited: bool };
/// A synchronous observation projection on the terminal worker.
/// Context and any output buffers survive until query returns.
pub const Query = struct {
    // zig-audit: acknowledge anyopaque
    // reason: This synchronous callback context is borrowed only until the matching request completes.
    context: *anyopaque,
    // zig-audit: acknowledge anyopaque
    // reason: The callback recovers only its own live context; no mutable canonical owner or borrow leaves the worker.
    project: *const fn (*anyopaque, *const instance.Terminal.Observation, Facts) ProjectionError!usize,
    after_revision: ?u64 = null,
    presentation: bool = false,
};

const Operation = union(enum) {
    input: instance.Input,
    resize: struct { rows: u16, columns: u16 },
    signal: instance.Signal,
    query: Query,
};
const Request = struct {
    operation: Operation,
    canceled: ?*const std.atomic.Value(bool),
    done: std.Io.Event = .unset,
    result: Error!usize = error.LocalUnavailable,
};
const State = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    value: *instance.Instance,
    thread: ?std.Thread = null,
    stop: std.atomic.Value(bool) = .init(false),
    failed: std.atomic.Value(bool) = .init(false),
    mutex: std.Io.Mutex = .init,
    requests: [maximum_requests]*Request = undefined,
    count: usize = 0,
    outstanding: usize = 0,
    presentations: usize = 0,
    facts: Facts = .{ .revision = 1, .stream_closed = false, .child_exited = false },
    semantic_sequence: u64,
    animation_wait_ms: ?u32 = null,
    synchronized_started_ns: ?u64 = null,
    synchronized_timed_out: bool = false,

    fn submit(self: *State, canceled: ?*const std.atomic.Value(bool), operation: Operation) Error!usize {
        var request = Request{ .operation = operation, .canceled = canceled };
        self.mutex.lockUncancelable(self.io);
        if (self.failed.load(.acquire) or self.stop.load(.acquire)) {
            self.mutex.unlock(self.io);
            return error.LocalUnavailable;
        }
        const presentation = switch (operation) {
            .query => |projection| projection.presentation,
            else => false,
        };
        if (self.outstanding == maximum_requests or (presentation and self.presentations == maximum_requests / 2)) {
            self.mutex.unlock(self.io);
            return error.LocalQueueFull;
        }
        self.requests[self.count] = &request;
        self.count += 1;
        self.outstanding += 1;
        if (presentation) self.presentations += 1;
        self.mutex.unlock(self.io);
        request.done.waitUncancelable(self.io);
        return request.result;
    }

    fn finish(self: *State, request: *Request, result: Error!usize) void {
        request.result = result;
        self.mutex.lockUncancelable(self.io);
        std.debug.assert(self.outstanding > 0);
        self.outstanding -= 1;
        if (request.operation == .query and request.operation.query.presentation) {
            std.debug.assert(self.presentations > 0);
            self.presentations -= 1;
        }
        self.mutex.unlock(self.io);
        request.done.set(self.io);
        // No request/context access after completion releases its caller.
    }

    fn execute(self: *State, operation: Operation) Error!usize {
        switch (operation) {
            .input => |event| try instance.input(self.value, event),
            .resize => |geometry| try instance.resize(self.value, geometry.rows, geometry.columns),
            .signal => |requested| if (instance.signal(self.value, requested) != .delivered) return error.LocalRejected,
            .query => |projection| return projection.project(projection.context, instance.terminal(self.value), self.facts),
        }
        const sequence = instance.terminal(self.value).semanticSequence();
        if (sequence != self.semantic_sequence) {
            self.facts.revision = std.math.add(u64, self.facts.revision, 1) catch return error.LocalUnavailable;
            self.semantic_sequence = sequence;
        }
        return 0;
    }

    fn turnRequests(self: *State) Error!void {
        var batch: [maximum_requests]*Request = undefined;
        self.mutex.lockUncancelable(self.io);
        const count = self.count;
        @memcpy(batch[0..count], self.requests[0..count]);
        self.count = 0;
        self.mutex.unlock(self.io);
        for (batch[0..count]) |request| {
            if (request.canceled) |canceled| {
                if (canceled.load(.acquire)) {
                    self.finish(request, error.LocalCanceled);
                    continue;
                }
            }
            const wait = switch (request.operation) {
                .query => |projection| (projection.presentation and self.synchronized_started_ns != null and !self.synchronized_timed_out) or
                    (if (projection.after_revision) |after| after == self.facts.revision else false),
                else => false,
            };
            if (wait) {
                self.mutex.lockUncancelable(self.io);
                std.debug.assert(self.count < maximum_requests);
                self.requests[self.count] = request;
                self.count += 1;
                self.mutex.unlock(self.io);
            } else {
                self.finish(request, self.execute(request.operation));
            }
        }
    }

    fn service(self: *State, maximum_wait_ms: u32) Error!void {
        var wait_ms = @min(maximum_wait_ms, self.animation_wait_ms orelse maximum_wait_ms);
        if (instance.bufferedOutputPending(self.value)) wait_ms = 0;
        var readable = false;
        var writable = instance.writePending(self.value);
        if (comptime builtin.os.tag == .linux) {
            const descriptor = instance.descriptor(self.value) catch return error.LocalUnavailable;
            var pollfds = [_]std.posix.pollfd{.{
                .fd = if (self.facts.stream_closed) -1 else descriptor,
                .events = std.posix.POLL.IN | (if (writable) @as(i16, std.posix.POLL.OUT) else 0),
                .revents = 0,
            }};
            const ready = std.posix.poll(&pollfds, @intCast(wait_ms)) catch return error.LocalUnavailable;
            readable = ready > 0 and (pollfds[0].revents & (std.posix.POLL.IN | std.posix.POLL.HUP)) != 0;
            writable = ready > 0 and (pollfds[0].revents & std.posix.POLL.OUT) != 0;
        } else {
            // ConPTY's output pipe is probed nonblocking by Instance. Retain the
            // same bounded desktop housekeeping/admission cadence as before.
            std.Io.sleep(self.io, .fromMilliseconds(wait_ms), .awake) catch return error.LocalUnavailable;
            readable = !self.facts.stream_closed;
        }
        const now: u64 = @intCast(std.Io.Clock.awake.now(self.io).toNanoseconds());
        const result = try instance.service(self.value, readable, writable, now);
        self.animation_wait_ms = result.animation_wait_ms;
        const synchronized = instance.terminal(self.value).synchronizedOutput();
        if (result.synchronized_output.ended or !synchronized) {
            self.synchronized_started_ns = null;
            self.synchronized_timed_out = false;
        }
        if (synchronized and !self.synchronized_timed_out) {
            if (self.synchronized_started_ns == null) self.synchronized_started_ns = now;
            if (now -| self.synchronized_started_ns.? >= std.time.ns_per_s)
                self.synchronized_timed_out = true;
        }

        const sequence = instance.terminal(self.value).semanticSequence();
        if (sequence != self.semantic_sequence or result.stream_closed != self.facts.stream_closed or
            (result.child_exit != null) != self.facts.child_exited)
        {
            self.facts.revision = std.math.add(u64, self.facts.revision, 1) catch return error.LocalUnavailable;
        }
        self.semantic_sequence = sequence;
        self.facts.stream_closed = result.stream_closed;
        self.facts.child_exited = result.child_exit != null;
    }

    fn run(self: *State) void {
        defer instance.deinit(self.value);
        while (!self.stop.load(.acquire)) {
            self.service(service_wait_ms) catch break;
            self.turnRequests() catch break;
        }
        self.failed.store(true, .release);
        self.mutex.lockUncancelable(self.io);
        const count = self.count;
        var pending: [maximum_requests]*Request = undefined;
        @memcpy(pending[0..count], self.requests[0..count]);
        self.count = 0;
        self.mutex.unlock(self.io);
        for (pending[0..count]) |request| self.finish(request, error.LocalUnavailable);
    }
};

fn state(owner: *Owner) *State {
    // zig-audit: acknowledge ptr_cast
    // reason: Only init produces this opaque owner; deinit/query/mutations recover the matching live State allocation.
    // zig-audit: acknowledge align_cast
    // reason: init preserves the original allocator-owned State alignment.
    return @ptrCast(@alignCast(owner));
}

/// Creates one direct Instance and starts its sole canonical worker.
pub fn init(allocator: std.mem.Allocator, io: std.Io, environ: std.process.Environ, launch: instance.Launch) Error!*Owner {
    if (comptime !desktop) return error.LocalUnsupported;
    const owner = try allocator.create(State);
    errdefer allocator.destroy(owner);
    const value = try instance.init(allocator, environ, launch);
    errdefer instance.deinit(value);
    owner.* = .{ .allocator = allocator, .io = io, .value = value, .semantic_sequence = instance.terminal(value).semanticSequence() };
    owner.thread = std.Thread.spawn(.{}, State.run, .{owner}) catch return error.LocalThreadFailed;
    // zig-audit: acknowledge ptr_cast
    // reason: The opaque Owner preserves this exact allocator-owned State allocation and lifetime.
    return @ptrCast(owner);
}

/// Joins the worker after all callers retire, then releases its private state.
pub fn deinit(owner: *Owner) void {
    if (comptime !desktop) return;
    const self = state(owner);
    self.stop.store(true, .release);
    self.thread.?.join();
    std.debug.assert(self.count == 0 and self.outstanding == 0);
    const allocator = self.allocator;
    allocator.destroy(self);
}

/// Submits one canonical semantic input; bytes are borrowed only until return.
pub fn input(owner: *Owner, canceled: ?*const std.atomic.Value(bool), event: instance.Input) Error!void {
    if (comptime !desktop) return error.LocalUnsupported;
    const result = try state(owner).submit(canceled, .{ .input = event });
    std.debug.assert(result == 0);
}
/// Submits one explicit canonical geometry change.
pub fn resize(owner: *Owner, canceled: ?*const std.atomic.Value(bool), rows: u16, columns: u16) Error!void {
    if (comptime !desktop) return error.LocalUnsupported;
    const limits = instance.render.limits;
    if (rows == 0 or columns == 0 or rows > limits.maximum_rows or columns > limits.maximum_columns or
        @as(u32, rows) * columns > limits.maximum_cells) return error.InvalidDimensions;
    const result = try state(owner).submit(canceled, .{ .resize = .{ .rows = rows, .columns = columns } });
    std.debug.assert(result == 0);
}
/// Submits one canonical process signal.
pub fn signal(owner: *Owner, canceled: ?*const std.atomic.Value(bool), requested: instance.Signal) Error!void {
    if (comptime !desktop) return error.LocalUnsupported;
    const result = try state(owner).submit(canceled, .{ .signal = requested });
    std.debug.assert(result == 0);
}
/// Projects const canonical state synchronously on its sole worker.
pub fn query(owner: *Owner, canceled: ?*const std.atomic.Value(bool), request: Query) Error!usize {
    if (comptime !desktop) return error.LocalUnsupported;
    return state(owner).submit(canceled, .{ .query = request });
}

const Probe = struct {
    revision: u64 = 0,
    rows: u16 = 0,
    columns: u16 = 0,
    ready: bool = false,
    found_marker: bool = false,
    called: bool = false,
    closed: bool = false,
    first: u21 = 0,
    second: u21 = 0,
    synchronized: bool = false,
};
// zig-audit: acknowledge anyopaque
// reason: The proof uses its own live Probe context through the synchronous query contract.
fn projectProbe(raw: *anyopaque, observation: *const instance.Terminal.Observation, facts: Facts) ProjectionError!usize {
    // zig-audit: acknowledge ptr_cast
    // reason: The proof passes exactly this Probe allocation as its query context.
    // zig-audit: acknowledge align_cast
    // reason: The caller keeps the correctly aligned Probe alive until completion.
    const probe: *Probe = @ptrCast(@alignCast(raw));
    const view = observation.semanticView(0);
    probe.* = .{
        .revision = facts.revision,
        .rows = view.rows,
        .columns = view.cols,
        .ready = std.mem.eql(u8, observation.title() orelse "", "READY"),
        .called = true,
        .closed = facts.stream_closed,
        .first = view.cellAt(0, 0),
        .second = view.cellAt(0, 1),
        .synchronized = observation.synchronizedOutput(),
    };
    for (0..view.rows) |row| {
        for (0..view.cols) |column| {
            if (view.cellAt(@intCast(row), @intCast(column)) == 'Z') probe.found_marker = true;
        }
    }
    return 0;
}

fn waitProbe(owner: *Owner, io: std.Io, marker: bool) !Probe {
    const started = std.Io.Clock.awake.now(io);
    while (started.durationTo(std.Io.Clock.awake.now(io)).toMilliseconds() < 2000) {
        var probe = Probe{};
        const count = try query(owner, null, .{ .context = &probe, .project = projectProbe });
        std.debug.assert(count == 0);
        if (probe.ready and (!marker or probe.found_marker)) return probe;
    }
    return error.Timeout;
}

const Waiting = struct {
    owner: *Owner,
    canceled: *std.atomic.Value(bool),
    io: std.Io,
    after: u64,
    probe: Probe = .{},
    entered: std.Io.Event = .unset,
    result: Error!usize = error.LocalUnavailable,
    fn run(self: *Waiting) void {
        self.entered.set(self.io);
        self.result = query(self.owner, self.canceled, .{
            .context = &self.probe,
            .project = projectProbe,
            .after_revision = self.after,
            .presentation = true,
        });
    }
};

test "direct Local serializes input and resize while a quiet observer waits; cancellation retires all borrows" {
    if (comptime builtin.os.tag != .linux or builtin.abi == .android) return error.SkipZigTest;
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{ .environ = std.testing.environ });
    defer threaded.deinit();
    const io = threaded.io();
    const owner = try init(std.testing.allocator, io, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf '\\033]0;READY\\007'; while IFS= read -r line; do printf '%s\\n' \"$line\"; done",
        .rows = 3,
        .columns = 12,
        .history_rows = 8,
    });
    defer deinit(owner);
    var before = try waitProbe(owner, io, false);
    // Settle the child's startup without retaining a canonical borrow.
    var canceled = std.atomic.Value(bool).init(false);
    var waiting = Waiting{ .owner = owner, .canceled = &canceled, .io = io, .after = before.revision };
    const thread = try std.Thread.spawn(.{}, Waiting.run, .{&waiting});
    waiting.entered.waitUncancelable(io);
    try resize(owner, null, 4, 14);
    thread.join();
    try std.testing.expectEqual(@as(usize, 0), try waiting.result);
    try std.testing.expect(waiting.probe.revision > before.revision);
    try std.testing.expectEqual(@as(u16, 4), waiting.probe.rows);
    try input(owner, null, .{ .bytes = "Zebra\n" });
    before = try waitProbe(owner, io, true);
    waiting = .{ .owner = owner, .canceled = &canceled, .io = io, .after = before.revision };
    const cancel_thread = try std.Thread.spawn(.{}, Waiting.run, .{&waiting});
    waiting.entered.waitUncancelable(io);
    const cancel_start = std.Io.Clock.awake.now(io);
    canceled.store(true, .release);
    cancel_thread.join();
    try std.testing.expectError(error.LocalCanceled, waiting.result);
    try std.testing.expect(!waiting.probe.called);
    try std.testing.expect(cancel_start.durationTo(std.Io.Clock.awake.now(io)).toMilliseconds() < 500);
    try std.testing.expectError(error.LocalCanceled, input(owner, &canceled, .{ .bytes = "discarded" }));
    try std.testing.expectError(error.InvalidDimensions, resize(owner, null, 0, 0));
}

test "direct Local observer capacity leaves canonical control progress available" {
    if (comptime builtin.os.tag != .linux or builtin.abi == .android) return error.SkipZigTest;
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{ .environ = std.testing.environ });
    defer threaded.deinit();
    const io = threaded.io();
    const owner = try init(std.testing.allocator, io, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "printf '\\033]0;READY\\007'; exec sleep 30",
        .rows = 2,
        .columns = 8,
        .history_rows = 8,
    });
    defer deinit(owner);
    const initial = try waitProbe(owner, io, false);
    var canceled = std.atomic.Value(bool).init(false);
    var waiting: [maximum_requests / 2]Waiting = undefined;
    var threads: [maximum_requests / 2]std.Thread = undefined;
    var spawned: usize = 0;
    defer {
        canceled.store(true, .release);
        for (threads[0..spawned]) |thread| thread.join();
    }
    for (&waiting, 0..) |*request, index| {
        request.* = .{ .owner = owner, .canceled = &canceled, .io = io, .after = initial.revision };
        threads[index] = try std.Thread.spawn(.{}, Waiting.run, .{request});
        spawned += 1;
        request.entered.waitUncancelable(io);
    }
    const started = std.Io.Clock.awake.now(io);
    while (true) {
        const self = state(owner);
        self.mutex.lockUncancelable(io);
        const count = self.presentations;
        self.mutex.unlock(io);
        if (count == waiting.len) break;
        if (started.durationTo(std.Io.Clock.awake.now(io)).toMilliseconds() > 2000) return error.Timeout;
        try std.Io.sleep(io, .fromMilliseconds(1), .awake);
    }
    var probe = Probe{};
    try std.testing.expectError(error.LocalQueueFull, query(owner, null, .{
        .context = &probe,
        .project = projectProbe,
        .after_revision = initial.revision,
        .presentation = true,
    }));
    // Pending presentation requests cannot occupy every command slot.
    try resize(owner, null, 3, 10);
    for (threads[0..spawned]) |thread| thread.join();
    spawned = 0;
    for (waiting) |request| {
        try std.testing.expectEqual(@as(usize, 0), try request.result);
        try std.testing.expectEqual(@as(u16, 3), request.probe.rows);
        try std.testing.expectEqual(@as(u16, 10), request.probe.columns);
    }
}

test "direct Local service progresses without observers and constructor failure releases staged ownership" {
    if (comptime builtin.os.tag != .linux or builtin.abi == .android) return error.SkipZigTest;
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{ .environ = std.testing.environ });
    defer threaded.deinit();
    const io = threaded.io();
    try std.testing.expectError(error.InvalidDimensions, init(std.testing.allocator, io, std.testing.environ, .{ .shell = "/bin/sh", .rows = 0, .columns = 1 }));
    const owner = try init(std.testing.allocator, io, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "sleep 0.08; printf 'Z'; printf '\\033]0;READY\\007'",
        .rows = 2,
        .columns = 8,
        .history_rows = 8,
    });
    defer deinit(owner);
    try std.Io.sleep(io, .fromMilliseconds(150), .awake);
    const probe = try waitProbe(owner, io, true);
    try std.testing.expect(probe.found_marker);
}

fn waitPresentations(owner: *Owner, io: std.Io, expected: usize) !void {
    const started = std.Io.Clock.awake.now(io);
    while (true) {
        const self = state(owner);
        self.mutex.lockUncancelable(io);
        const count = self.presentations;
        self.mutex.unlock(io);
        if (count == expected) return;
        if (started.durationTo(std.Io.Clock.awake.now(io)).toMilliseconds() > 2000) return error.Timeout;
        try std.Io.sleep(io, .fromMilliseconds(1), .awake);
    }
}

test "direct Local presents a queued synchronized release before canonical unread tail" {
    if (comptime builtin.os.tag != .linux or builtin.abi == .android) return error.SkipZigTest;
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{ .environ = std.testing.environ });
    defer threaded.deinit();
    const io = threaded.io();
    const owner = try init(std.testing.allocator, io, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf '\\033]0;READY\\007'; IFS= read -r go; printf '\\033[?2026hA\\033[?2026l\\033[?2026hB'; IFS= read -r finish; printf '\\033[?2026l'; exec sleep 30",
        .rows = 2,
        .columns = 8,
        .history_rows = 8,
    });
    defer deinit(owner);
    const initial = try waitProbe(owner, io, false);
    var canceled = std.atomic.Value(bool).init(false);
    var waiting = Waiting{ .owner = owner, .canceled = &canceled, .io = io, .after = initial.revision };
    var active: ?std.Thread = try std.Thread.spawn(.{}, Waiting.run, .{&waiting});
    defer if (active) |thread| {
        canceled.store(true, .release);
        thread.join();
    };
    try waitPresentations(owner, io, 1);
    try input(owner, null, .{ .bytes = "\n" });
    active.?.join();
    active = null;
    try std.testing.expectEqual(@as(usize, 0), try waiting.result);
    try std.testing.expectEqual(@as(u21, 'A'), waiting.probe.first);
    try std.testing.expectEqual(@as(u21, 0), waiting.probe.second);
    var canonical = Probe{};
    const count = try query(owner, null, .{ .context = &canonical, .project = projectProbe });
    std.debug.assert(count == 0);
    try std.testing.expectEqual(@as(u21, 'B'), canonical.second);
    try std.testing.expect(canonical.synchronized);
    waiting = .{ .owner = owner, .canceled = &canceled, .io = io, .after = canonical.revision };
    active = try std.Thread.spawn(.{}, Waiting.run, .{&waiting});
    try waitPresentations(owner, io, 1);
    try input(owner, null, .{ .bytes = "\n" });
    active.?.join();
    active = null;
    try std.testing.expectEqual(@as(usize, 0), try waiting.result);
    try std.testing.expectEqual(@as(u21, 'A'), waiting.probe.first);
    try std.testing.expectEqual(@as(u21, 'B'), waiting.probe.second);
    try std.testing.expect(!waiting.probe.synchronized);
}
