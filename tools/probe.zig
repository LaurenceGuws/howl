//! Owns one removable bounded development probe worker and fixed JSONL records.

const std = @import("std");

const c = @cImport({
    @cInclude("time.h");
    @cInclude("unistd.h");
});

/// Selects the worker-backed development implementation at compile time.
pub const enabled = true;
/// Bounds retained producer events independently of output speed.
pub const queue_capacity: usize = 4_096;
/// Samples process and owned-thread Linux facts at ten hertz.
pub const sample_interval_ms: u32 = 100;
const max_owned_threads: usize = 16;
const poll_interval_us: c_uint = 5_000;
const sample_interval_ns: u64 = sample_interval_ms * std.time.ns_per_ms;
const admission_active: u64 = 1 << 63;
const admission_count_bits = 20;
const admission_count_mask: u64 = (1 << admission_count_bits) - 1;
const admission_epoch_mask: u64 = ~(admission_active | admission_count_mask);
const admission_epoch_step: u64 = 1 << admission_count_bits;

/// Gives each measured logical actor stable identity independent of Linux TID.
pub const Owner = enum(u8) {
    scenario,
    window,
    render,
    probe,
};

/// Names the complete fixed high-level event vocabulary.
pub const Kind = enum(u8) {
    thread_start,
    producer_baseline,
    pty_read,
    vt_feed,
    frame_publish,
    frame_saturated,
    frame_borrow_release,
    mailbox,
    render_prepare,
    draw,
    present,
    process_sample,
    thread_sample,
    summary,
};

/// Carries one compact high-level measurement. Field meaning is fixed by Kind:
/// duration is elapsed work or CPU ns; bytes is transferred, retained, or RSS;
/// count is sequences, cells, quads, or threads; generation is publication;
/// auxiliary and detail carry paired counters; flags carry mutation or state.
pub const Values = struct {
    /// Stores elapsed work or sampled CPU nanoseconds.
    duration_ns: u64 = 0,
    /// Stores transferred, retained, uploaded, backing, or RSS bytes.
    bytes: u64 = 0,
    /// Stores sequence, cell, quad, event, or thread count.
    count: u64 = 0,
    /// Stores the relevant publication identity or fault count.
    generation: u64 = 0,
    /// Stores the first kind-specific paired counter.
    auxiliary: u64 = 0,
    /// Stores the second counter or two packed bounded u32 counters.
    detail: u64 = 0,
    /// Stores exact mutation bits or sampled Linux task state.
    flags: u16 = 0,
};

/// Reports exact worker admission, loss, queue, output, and sampling totals.
pub const Summary = struct {
    /// Counts events drained from the producer queue.
    accepted: u64,
    /// Counts events rejected before queue ownership transferred.
    dropped: u64,
    /// Reports the maximum observed retained queue depth.
    high_water: u32,
    /// Counts JSONL records written, including samples and summary.
    records: u64,
    /// Counts fixed-rate passes plus the final post-drain sample.
    samples: u64,
};

/// Reports the exact failed construction phase before the worker is active.
pub const StartError = error{
    AlreadyStarted,
    GenerationExhausted,
    OpenFailed,
    ThreadSpawnFailed,
    ThreadNameFailed,
};
/// Reports missing ownership or a worker-side output failure after drain.
pub const StopError = error{ NotStarted, WriteFailed };

const Event = struct {
    timestamp_ns: u64,
    values: Values,
    tid: u32,
    owner: Owner,
    kind: Kind,
};

const Slot = struct {
    sequence: std.atomic.Value(usize),
    event: Event = undefined,
};

const Queue = struct {
    slots: [queue_capacity]Slot,
    enqueue_position: std.atomic.Value(usize) = .init(0),
    dequeue_position: std.atomic.Value(usize) = .init(0),
    dropped: std.atomic.Value(u64) = .init(0),
    high_water: std.atomic.Value(u32) = .init(0),

    fn init() Queue {
        var queue: Queue = undefined;
        queue.enqueue_position = .init(0);
        queue.dequeue_position = .init(0);
        queue.dropped = .init(0);
        queue.high_water = .init(0);
        for (&queue.slots, 0..) |*slot, index| {
            slot.sequence = .init(index);
            slot.event = undefined;
        }
        return queue;
    }

    fn push(self: *Queue, event: Event) bool {
        var position = self.enqueue_position.load(.monotonic);
        for (0..16) |_| {
            if (position > std.math.maxInt(usize) - queue_capacity) break;
            const slot = &self.slots[position & (queue_capacity - 1)];
            const sequence = slot.sequence.load(.acquire);
            if (sequence == position) {
                if (self.enqueue_position.cmpxchgWeak(
                    position,
                    position + 1,
                    .monotonic,
                    .monotonic,
                )) |actual| {
                    position = actual;
                    continue;
                }
                slot.event = event;
                slot.sequence.store(position + 1, .release);
                self.raiseHighWater(position + 1);
                return true;
            }
            if (sequence < position) break;
            position = self.enqueue_position.load(.monotonic);
        }
        self.recordDrop();
        return false;
    }

    fn pop(self: *Queue) ?Event {
        const position = self.dequeue_position.load(.monotonic);
        const slot = &self.slots[position & (queue_capacity - 1)];
        if (slot.sequence.load(.acquire) != position + 1) return null;
        const event = slot.event;
        slot.sequence.store(position + queue_capacity, .release);
        self.dequeue_position.store(position + 1, .release);
        return event;
    }

    fn empty(self: *const Queue) bool {
        return self.dequeue_position.load(.acquire) == self.enqueue_position.load(.acquire);
    }

    fn raiseHighWater(self: *Queue, end: usize) void {
        const begin = self.dequeue_position.load(.acquire);
        const depth: u32 = @intCast(@min(queue_capacity, end -| begin));
        var current = self.high_water.load(.monotonic);
        while (depth > current) {
            current = self.high_water.cmpxchgWeak(
                current,
                depth,
                .monotonic,
                .monotonic,
            ) orelse return;
        }
    }

    fn recordDrop(self: *Queue) void {
        const previous = self.dropped.fetchAdd(1, .monotonic);
        std.mem.doNotOptimizeAway(previous);
    }
};

const Admission = struct {
    state: std.atomic.Value(u64) = .init(0),

    fn activate(self: *Admission) StartError!void {
        const prior = self.state.load(.acquire);
        std.debug.assert(prior & (admission_active | admission_count_mask) == 0);
        const epoch = prior & admission_epoch_mask;
        if (epoch == admission_epoch_mask) return error.GenerationExhausted;
        self.state.store(epoch + admission_epoch_step | admission_active, .release);
    }

    fn enter(self: *Admission) bool {
        return self.enterObserved(self.state.load(.acquire));
    }

    fn enterObserved(self: *Admission, first: u64) bool {
        if (first & admission_active == 0) return false;
        const epoch = first & admission_epoch_mask;
        var observed = first;
        for (0..64) |_| {
            if (observed & admission_active == 0 or observed & admission_epoch_mask != epoch)
                return false;
            if (observed & admission_count_mask == admission_count_mask) return false;
            observed = self.state.cmpxchgWeak(
                observed,
                observed + 1,
                .acquire,
                .monotonic,
            ) orelse return true;
        }
        return false;
    }

    fn leave(self: *Admission) void {
        const prior = self.state.fetchSub(1, .release);
        std.debug.assert(prior & admission_count_mask != 0);
    }

    fn revoke(self: *Admission) void {
        const prior = self.state.fetchAnd(~admission_active, .acq_rel);
        std.debug.assert(prior & admission_active != 0);
    }

    fn producerCount(self: *const Admission) u64 {
        return self.state.load(.acquire) & admission_count_mask;
    }
};

/// Reports one retained slot payload size for measurement receipts.
pub const event_bytes: usize = @sizeOf(Event);
/// Reports all fixed queue storage, positions, and counters.
pub const queue_bytes: usize = @sizeOf(Queue);

const ThreadFact = struct {
    owner: Owner,
    tid: u32,
};

const Probe = struct {
    io: std.Io,
    file: std.Io.File,
    queue: Queue,
    stopping: std.atomic.Value(bool) = .init(false),
    write_failed: std.atomic.Value(bool) = .init(false),
    thread: std.Thread,
    started_ns: u64,
    accepted: u64 = 0,
    records: u64 = 0,
    samples: u64 = 0,
    threads: [max_owned_threads]ThreadFact = undefined,
    thread_count: u8 = 0,
};

var instance: Probe = undefined;
var started = std.atomic.Value(bool).init(false);
var admission = Admission{};

/// Opens one output and starts one named worker before product producers exist.
pub fn start(io: std.Io, path: []const u8) StartError!void {
    if (started.swap(true, .acq_rel)) return error.AlreadyStarted;
    errdefer started.store(false, .release);
    const file = std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true }) catch
        return error.OpenFailed;
    errdefer file.close(io);
    instance = .{
        .io = io,
        .file = file,
        .queue = .init(),
        .thread = undefined,
        .started_ns = monotonicNs() orelse 0,
    };
    try admission.activate();
    errdefer admission.revoke();
    instance.thread = std.Thread.spawn(.{}, workerMain, .{&instance}) catch
        return error.ThreadSpawnFailed;
    instance.thread.setName(io, "howl-probe") catch {
        instance.stopping.store(true, .release);
        instance.thread.join();
        return error.ThreadNameFailed;
    };
    emit(.scenario, .thread_start, .{});
}

/// Revokes producers, drains admitted events, joins, closes, and reports loss.
pub fn stop() StopError!Summary {
    if (!started.load(.acquire)) return error.NotStarted;
    admission.revoke();
    while (admission.producerCount() != 0) {
        const result = c.usleep(50);
        std.mem.doNotOptimizeAway(result);
    }
    instance.stopping.store(true, .release);
    instance.thread.join();
    const summary = Summary{
        .accepted = instance.accepted,
        .dropped = instance.queue.dropped.load(.acquire),
        .high_water = instance.queue.high_water.load(.acquire),
        .records = instance.records,
        .samples = instance.samples,
    };
    instance.file.close(instance.io);
    started.store(false, .release);
    if (instance.write_failed.load(.acquire)) return error.WriteFailed;
    return summary;
}

/// Timestamps and attempts one allocation-free bounded queue transfer.
pub inline fn emit(owner: Owner, kind: Kind, values: Values) void {
    if (!admission.enter()) return;
    defer admission.leave();
    const timestamp = monotonicNs() orelse {
        instance.queue.recordDrop();
        return;
    };
    const tid = std.math.cast(u32, std.Thread.getCurrentId()) orelse {
        instance.queue.recordDrop();
        return;
    };
    if (!instance.queue.push(.{
        .timestamp_ns = timestamp,
        .values = values,
        .tid = tid,
        .owner = owner,
        .kind = kind,
    })) return;
}

/// Returns Linux monotonic nanoseconds, or zero if the native clock fails.
pub inline fn now() u64 {
    return monotonicNs() orelse 0;
}

fn workerMain(self: *Probe) void {
    const tid: u32 = @intCast(std.Thread.getCurrentId());
    retainThread(self, .probe, tid);
    writeEvent(self, .{
        .timestamp_ns = monotonicNs() orelse self.started_ns,
        .values = .{},
        .tid = tid,
        .owner = .probe,
        .kind = .thread_start,
    });
    var next_sample = (monotonicNs() orelse self.started_ns) + sample_interval_ns;
    sample(self, monotonicNs() orelse self.started_ns);
    while (!self.stopping.load(.acquire) or !self.queue.empty()) {
        var progressed = false;
        while (self.queue.pop()) |event| {
            progressed = true;
            self.accepted += 1;
            if (event.kind == .thread_start) retainThread(self, event.owner, event.tid);
            writeEvent(self, event);
        }
        const timestamp = monotonicNs() orelse next_sample;
        if (timestamp >= next_sample) {
            sample(self, timestamp);
            const intervals = (timestamp - next_sample) / sample_interval_ns + 1;
            next_sample +|= intervals *| sample_interval_ns;
        }
        if (!progressed) {
            const result = c.usleep(poll_interval_us);
            std.mem.doNotOptimizeAway(result);
        }
    }
    sample(self, monotonicNs() orelse next_sample);
    writeEvent(self, .{
        .timestamp_ns = monotonicNs() orelse next_sample,
        .values = .{
            .count = self.accepted,
            .generation = self.queue.dropped.load(.acquire),
            .auxiliary = self.queue.high_water.load(.acquire),
        },
        .tid = tid,
        .owner = .probe,
        .kind = .summary,
    });
}

fn retainThread(self: *Probe, owner: Owner, tid: u32) void {
    for (self.threads[0..self.thread_count]) |thread|
        if (thread.owner == owner and thread.tid == tid) return;
    if (self.thread_count == self.threads.len) return;
    self.threads[self.thread_count] = .{ .owner = owner, .tid = tid };
    self.thread_count += 1;
}

fn writeEvent(self: *Probe, event: Event) void {
    if (self.write_failed.load(.acquire)) return;
    var buffer: [512]u8 = undefined;
    const elapsed_ms = (event.timestamp_ns -| self.started_ns) / std.time.ns_per_ms;
    const record = std.fmt.bufPrint(
        &buffer,
        "{{\"debug_time\":\"{d:0>2}:{d:0>2}:{d:0>3}\",\"timestamp_ns\":{d}," ++
            "\"owner\":\"{s}\",\"tid\":{d},\"kind\":\"{s}\",\"duration_ns\":{d}," ++
            "\"bytes\":{d},\"count\":{d},\"generation\":{d},\"auxiliary\":{d}," ++
            "\"detail\":{d},\"flags\":{d}}}\n",
        .{
            elapsed_ms / 60_000,
            elapsed_ms / 1_000 % 60,
            elapsed_ms % 1_000,
            event.timestamp_ns,
            @tagName(event.owner),
            event.tid,
            @tagName(event.kind),
            event.values.duration_ns,
            event.values.bytes,
            event.values.count,
            event.values.generation,
            event.values.auxiliary,
            event.values.detail,
            event.values.flags,
        },
    ) catch {
        self.write_failed.store(true, .release);
        return;
    };
    self.file.writeStreamingAll(self.io, record) catch {
        self.write_failed.store(true, .release);
        return;
    };
    self.records += 1;
}

fn sample(self: *Probe, timestamp: u64) void {
    const process = readStat(self.io, "/proc/self/stat") orelse return;
    const status = readStatus(self.io, "/proc/self/status") orelse return;
    writeEvent(self, .{
        .timestamp_ns = timestamp,
        .values = .{
            .duration_ns = process.cpu_ns,
            .bytes = status.rss_bytes,
            .count = status.threads,
            .generation = process.minor_faults,
            .auxiliary = process.major_faults,
            .detail = packContexts(status.voluntary, status.involuntary),
            .flags = process.state,
        },
        .tid = 0,
        .owner = .probe,
        .kind = .process_sample,
    });
    for (self.threads[0..self.thread_count]) |thread| {
        var stat_path: [64]u8 = undefined;
        const stat_name = std.fmt.bufPrint(&stat_path, "/proc/self/task/{d}/stat", .{thread.tid}) catch continue;
        const thread_stat = readStat(self.io, stat_name) orelse continue;
        var status_path: [72]u8 = undefined;
        const status_name = std.fmt.bufPrint(&status_path, "/proc/self/task/{d}/status", .{thread.tid}) catch continue;
        const thread_status = readStatus(self.io, status_name) orelse continue;
        writeEvent(self, .{
            .timestamp_ns = timestamp,
            .values = .{
                .duration_ns = thread_stat.cpu_ns,
                .generation = thread_stat.minor_faults,
                .auxiliary = thread_stat.major_faults,
                .detail = packContexts(thread_status.voluntary, thread_status.involuntary),
                .flags = thread_stat.state,
            },
            .tid = thread.tid,
            .owner = thread.owner,
            .kind = .thread_sample,
        });
    }
    self.samples += 1;
}

const Stat = struct {
    state: u16,
    minor_faults: u64,
    major_faults: u64,
    cpu_ns: u64,
};

fn readStat(io: std.Io, path: []const u8) ?Stat {
    var buffer: [8_192]u8 = undefined;
    const bytes = readAbsolute(io, path, &buffer) orelse return null;
    const close = std.mem.lastIndexOfScalar(u8, bytes, ')') orelse return null;
    if (close + 2 >= bytes.len) return null;
    var fields = std.mem.tokenizeScalar(u8, bytes[close + 2 ..], ' ');
    var index: usize = 0;
    var state: u16 = 0;
    var minor: u64 = 0;
    var major: u64 = 0;
    var user_ticks: u64 = 0;
    var system_ticks: u64 = 0;
    while (fields.next()) |field| : (index += 1) switch (index) {
        0 => state = field[0],
        7 => minor = std.fmt.parseInt(u64, field, 10) catch return null,
        9 => major = std.fmt.parseInt(u64, field, 10) catch return null,
        11 => user_ticks = std.fmt.parseInt(u64, field, 10) catch return null,
        12 => system_ticks = std.fmt.parseInt(u64, field, 10) catch return null,
        else => {},
    };
    const ticks = c.sysconf(c._SC_CLK_TCK);
    if (ticks <= 0) return null;
    const total_ticks = std.math.add(u64, user_ticks, system_ticks) catch return null;
    const cpu_ns = std.math.mul(u64, total_ticks, std.time.ns_per_s) catch return null;
    return .{
        .state = state,
        .minor_faults = minor,
        .major_faults = major,
        .cpu_ns = cpu_ns / @as(u64, @intCast(ticks)),
    };
}

const Status = struct {
    rss_bytes: u64 = 0,
    threads: u64 = 0,
    voluntary: u32 = 0,
    involuntary: u32 = 0,
};

fn readStatus(io: std.Io, path: []const u8) ?Status {
    var buffer: [64 * 1_024]u8 = undefined;
    const bytes = readAbsolute(io, path, &buffer) orelse return null;
    var result = Status{};
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        if (valueAfter(line, "VmRSS:")) |value| result.rss_bytes = value * 1_024;
        if (valueAfter(line, "Threads:")) |value| result.threads = value;
        if (valueAfter(line, "voluntary_ctxt_switches:")) |value|
            result.voluntary = std.math.cast(u32, value) orelse std.math.maxInt(u32);
        if (valueAfter(line, "nonvoluntary_ctxt_switches:")) |value|
            result.involuntary = std.math.cast(u32, value) orelse std.math.maxInt(u32);
    }
    return result;
}

fn readAbsolute(io: std.Io, path: []const u8, buffer: []u8) ?[]const u8 {
    const file = std.Io.Dir.openFileAbsolute(io, path, .{}) catch return null;
    defer file.close(io);
    const count = file.readPositionalAll(io, buffer, 0) catch return null;
    if (count == buffer.len) return null;
    return buffer[0..count];
}

fn valueAfter(line: []const u8, prefix: []const u8) ?u64 {
    if (!std.mem.startsWith(u8, line, prefix)) return null;
    const value = std.mem.trim(u8, line[prefix.len..], " \t");
    const end = std.mem.indexOfAny(u8, value, " \t") orelse value.len;
    return std.fmt.parseInt(u64, value[0..end], 10) catch null;
}

fn packContexts(voluntary: u32, involuntary: u32) u64 {
    return @as(u64, voluntary) << 32 | involuntary;
}

fn monotonicNs() ?u64 {
    var value: c.struct_timespec = undefined;
    if (c.clock_gettime(c.CLOCK_MONOTONIC, &value) != 0 or value.tv_sec < 0 or value.tv_nsec < 0)
        return null;
    const seconds = std.math.mul(u64, @intCast(value.tv_sec), std.time.ns_per_s) catch return null;
    return std.math.add(u64, seconds, @intCast(value.tv_nsec)) catch null;
}

test "bounded queue reports saturation and exact FIFO recovery" {
    var queue = Queue.init();
    for (0..queue_capacity) |index| {
        try std.testing.expect(queue.push(.{
            .timestamp_ns = index,
            .values = .{},
            .tid = 1,
            .owner = .scenario,
            .kind = .vt_feed,
        }));
    }
    try std.testing.expect(!queue.push(.{
        .timestamp_ns = queue_capacity,
        .values = .{},
        .tid = 1,
        .owner = .scenario,
        .kind = .vt_feed,
    }));
    try std.testing.expectEqual(@as(u64, 1), queue.dropped.load(.acquire));
    try std.testing.expectEqual(@as(u32, queue_capacity), queue.high_water.load(.acquire));
    for (0..queue_capacity) |index|
        try std.testing.expectEqual(@as(u64, index), queue.pop().?.timestamp_ns);
    try std.testing.expect(queue.empty());
}

test "proc parsers retain exact bounded resource facts" {
    const stat = readStat(std.testing.io, "/proc/self/stat") orelse return error.TestUnexpectedResult;
    const status = readStatus(std.testing.io, "/proc/self/status") orelse return error.TestUnexpectedResult;
    try std.testing.expect(stat.state != 0);
    try std.testing.expect(status.rss_bytes != 0);
    try std.testing.expect(status.threads != 0);
}

const ProducerContext = struct {
    queue: *Queue,
    producer: u16,
};

fn produceBurst(context: *ProducerContext) void {
    for (0..512) |sequence| {
        if (!context.queue.push(.{
            .timestamp_ns = sequence,
            .values = .{ .generation = context.producer, .count = sequence },
            .tid = context.producer,
            .owner = .scenario,
            .kind = .vt_feed,
        })) @panic("bounded test queue unexpectedly rejected a producer");
    }
}

test "four producers retain per-owner order without blocking on a consumer" {
    var queue = Queue.init();
    var contexts = [_]ProducerContext{
        .{ .queue = &queue, .producer = 0 },
        .{ .queue = &queue, .producer = 1 },
        .{ .queue = &queue, .producer = 2 },
        .{ .queue = &queue, .producer = 3 },
    };
    var threads: [contexts.len]std.Thread = undefined;
    for (&threads, &contexts) |*thread, *context|
        thread.* = try std.Thread.spawn(.{}, produceBurst, .{context});
    for (threads) |thread| thread.join();
    var next: [contexts.len]u64 = @splat(0);
    var count: usize = 0;
    while (queue.pop()) |event| {
        const producer: usize = @intCast(event.values.generation);
        try std.testing.expectEqual(next[producer], event.values.count);
        next[producer] += 1;
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, contexts.len * 512), count);
    try std.testing.expectEqual(@as(u64, 0), queue.dropped.load(.acquire));
}

const RevocationContext = struct {
    ready_count: *std.atomic.Value(u8),
    go: *std.atomic.Value(bool),
    run: u64,
};

fn emitAcrossRevocation(context: *RevocationContext) void {
    emit(.scenario, .vt_feed, .{ .generation = context.run });
    const prior = context.ready_count.fetchAdd(1, .release);
    std.mem.doNotOptimizeAway(prior);
    while (!context.go.load(.acquire)) std.Thread.yield() catch
        @panic("test producer yield failed");
    for (0..1_024) |_| emit(.scenario, .vt_feed, .{ .generation = context.run });
}

test "revocation rejects stale entry and repeated runs drain without contamination" {
    var gate = Admission{};
    try gate.activate();
    const stale = gate.state.load(.acquire);
    gate.revoke();
    try gate.activate();
    try std.testing.expect(!gate.enterObserved(stale));
    gate.revoke();

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    for (1..5) |run| {
        var name_buffer: [32]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buffer, "probe-{d}.jsonl", .{run});
        const path = try std.fs.path.join(std.testing.allocator, &.{ root, name });
        defer std.testing.allocator.free(path);
        try start(std.testing.io, path);
        var ready_count = std.atomic.Value(u8).init(0);
        var go = std.atomic.Value(bool).init(false);
        var contexts: [4]RevocationContext = undefined;
        var threads: [contexts.len]std.Thread = undefined;
        for (&contexts, &threads) |*context, *thread| {
            context.* = .{ .ready_count = &ready_count, .go = &go, .run = run };
            thread.* = try std.Thread.spawn(.{}, emitAcrossRevocation, .{context});
        }
        while (ready_count.load(.acquire) != contexts.len) try std.Thread.yield();
        go.store(true, .release);
        const summary = try stop();
        for (threads) |thread| thread.join();
        try std.testing.expect(summary.accepted >= contexts.len + 1);

        const bytes = try std.Io.Dir.cwd().readFileAlloc(
            std.testing.io,
            path,
            std.testing.allocator,
            .limited(2 * 1_024 * 1_024),
        );
        defer std.testing.allocator.free(bytes);
        var expected_buffer: [32]u8 = undefined;
        const expected = try std.fmt.bufPrint(&expected_buffer, "\"generation\":{d}", .{run});
        var retained: usize = 0;
        var lines = std.mem.splitScalar(u8, bytes, '\n');
        while (lines.next()) |line| {
            if (std.mem.indexOf(u8, line, "\"kind\":\"vt_feed\"") == null) continue;
            try std.testing.expect(std.mem.indexOf(u8, line, expected) != null);
            retained += 1;
        }
        try std.testing.expect(retained >= contexts.len);
    }
}

test "stop drains every admitted record before closing output" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    const path = try std.fs.path.join(std.testing.allocator, &.{ root, "probe.jsonl" });
    defer std.testing.allocator.free(path);
    try start(std.testing.io, path);
    for (0..64) |sequence| emit(.scenario, .vt_feed, .{ .count = sequence });
    const summary = try stop();
    try std.testing.expectEqual(@as(u64, 0), summary.dropped);
    try std.testing.expect(summary.accepted >= 65);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        path,
        std.testing.allocator,
        .limited(64 * 1_024),
    );
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.count(u8, bytes, "\n") >= summary.accepted + 2);
}
