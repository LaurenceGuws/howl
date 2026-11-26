//! App-local PTY/VT service, owned exclusively by the terminal worker.
//! No separate scheduler, ABI or second canonical terminal lives here.
const std = @import("std");
const pty = @import("howl_pty");
const vt = @import("howl_vt");

const write_queue_bytes = 64 * 1024;
/// Largest standalone pasted payload, allowing room for its VT delimiters.
pub const input_event_limit = write_queue_bytes - 12;
const read_buffer_bytes = 16 * 1024;
const read_calls_per_turn = 8;
const write_bytes_per_turn = 64 * 1024;
const write_calls_per_turn = 4;
const input_retry_ns: u64 = 100 * std.time.ns_per_ms;

/// Copied shell/program launch and canonical grid initialization.
pub const Launch = struct {
    shell: []const u8,
    command: ?[]const u8 = null,
    arguments: ?[]const []const u8 = null,
    cwd: ?[]const u8 = null,
    rows: u16,
    columns: u16,
    history_rows: u16 = 4096,
    term: []const u8 = "xterm-256color",
    colorterm: ?[]const u8 = "truecolor",
    color_defaults: vt.Terminal.ColorDefaults = .{},
    cursor_style: vt.Terminal.CursorStyle = .{ .shape = .block, .blink = true },
};

/// Exact VT encoding, PTY signal or bounded admission failures.
pub const InputError = vt.Terminal.InputError || pty.TermiosSignalError || error{ WriteQueueFull, ChildClosed };
/// Failure-safe VT/PTY geometry transaction failures.
pub const ResizeError = pty.ResizeError || vt.Terminal.ResizeError;
/// Exact failures of one bounded canonical service turn.
pub const ServiceError = pty.ReadError || pty.WriteError || pty.ObserveError ||
    vt.Terminal.FeedError || vt.Terminal.ClipboardReplyError ||
    vt.Terminal.ColorPreferenceReplyError || vt.Terminal.ContainerReplyError ||
    vt.Terminal.PointerShapeReplyError || error{WriteQueueFull};
/// Only the progress and deadlines consumed by the owning terminal worker.
pub const Service = struct {
    synchronized_output: vt.Terminal.SynchronizedOutputProgress = .{},
    /// Presentation phase advanced, even if canonical text revision did not.
    animation_changed: bool = false,
    stream_closed: bool,
    child_exit: ?pty.ChildExit,
    write_pending: bool,
    animation_wait_ms: ?u32,
    input_retry_wait_ms: ?u32,
};

const WriteQueue = struct {
    bytes: [write_queue_bytes]u8 = undefined,
    count: usize = 0,

    fn remaining(self: *const WriteQueue) usize {
        return self.bytes.len - self.count;
    }
    fn append(self: *WriteQueue, bytes: []const u8) error{WriteQueueFull}!void {
        if (bytes.len > self.remaining()) return error.WriteQueueFull;
        @memcpy(self.bytes[self.count..][0..bytes.len], bytes);
        self.count += bytes.len;
    }
    fn consume(self: *WriteQueue, count: usize) void {
        std.debug.assert(count <= self.count);
        std.mem.copyForwards(u8, self.bytes[0 .. self.count - count], self.bytes[count..self.count]);
        self.count -= count;
    }
};

/// The app-local worker is the sole mutable authority for both members.
/// Its address must remain stable while borrowed VT output points at terminal.
pub const Core = struct {
    allocator: std.mem.Allocator,
    transport: pty.Owned,
    terminal: vt.Terminal,
    writes: WriteQueue = .{},
    reads: [read_buffer_bytes]u8 = undefined,
    read_start: usize = 0,
    read_end: usize = 0,
    input_retry_at: ?u64 = null,
    child_exit: ?pty.ChildExit = null,
    stream_closed: bool = false,
    write_closed: bool = false,
    undelivered_bytes: usize = 0,

    /// Launches the PTY and initializes the one VT in this stable caller-owned allocation.
    pub fn initInto(self: *Core, allocator: std.mem.Allocator, environ: std.process.Environ, launch: Launch, cell: vt.Terminal.CellPixelSize) !void {
        if (launch.rows == 0 or launch.columns == 0 or cell.width == 0 or cell.height == 0)
            return error.InvalidDimensions;
        var transport = if (launch.arguments) |arguments| blk: {
            if (launch.command != null) return error.InvalidArgument;
            break :blk try pty.Owned.initProgram(allocator, environ, launch.shell, arguments, launch.cwd, .{
                .term = launch.term,
                .colorterm = launch.colorterm,
            });
        } else try pty.Owned.init(allocator, environ, launch.shell, launch.command, launch.cwd, .{
            .term = launch.term,
            .colorterm = launch.colorterm,
        });
        errdefer transport.deinit();
        const width = try pixelExtent(launch.columns, cell.width);
        const height = try pixelExtent(launch.rows, cell.height);
        try transport.startWithPixels(launch.columns, launch.rows, width, height);
        self.allocator = allocator;
        self.transport = transport;
        self.writes = .{};
        self.read_start = 0;
        self.read_end = 0;
        self.input_retry_at = null;
        self.child_exit = null;
        self.stream_closed = false;
        self.write_closed = false;
        self.undelivered_bytes = 0;
        try vt.Terminal.initWithHistoryInto(&self.terminal, allocator, launch.rows, launch.columns, launch.history_rows);
        errdefer self.terminal.deinit();
        self.terminal.setColorDefaults(launch.color_defaults);
        self.terminal.setDefaultCursorStyle(launch.cursor_style);
        try self.terminal.setCellPixelSize(cell.width, cell.height);
    }

    /// Borrowed output must be destroyed before this canonical owner.
    pub fn deinit(self: *Core) void {
        self.terminal.deinit();
        self.transport.deinit();
        self.* = undefined;
    }

    /// Retains the current cell-pixel lattice while changing the canonical grid.
    pub fn resize(self: *Core, rows: u16, columns: u16) ResizeError!void {
        return self.resizeGeometry(rows, columns, self.terminal.cellPixelSize().?);
    }
    /// Validates and prepares VT before PTY ioctl, then infallibly commits VT.
    pub fn resizeGeometry(self: *Core, rows: u16, columns: u16, cell: vt.Terminal.CellPixelSize) ResizeError!void {
        return self.resizeGeometryWith(&self.transport, rows, columns, cell);
    }

    // zig-audit: acknowledge anytype
    // reason: The real PTY and a fault-injected ioctl share the exact prepared-VT transaction.
    fn resizeGeometryWith(self: *Core, transport: anytype, rows: u16, columns: u16, cell: vt.Terminal.CellPixelSize) ResizeError!void {
        if (self.terminal.inputBlocked()) return error.InputPending;
        const width = try pixelExtent(columns, cell.width);
        const height = try pixelExtent(rows, cell.height);
        var prepared = try self.terminal.prepareResizeGeometry(rows, columns, cell);
        defer prepared.deinit();
        try transport.resizeWithPixels(columns, rows, width, height);
        prepared.commit();
    }

    /// Preserve the existing app's ordinary input contract. Segmented-paste
    /// machinery is not copied because the app has no streaming paste caller.
    pub fn input(self: *Core, event: vt.Terminal.InputEvent) InputError!void {
        if (self.write_closed) return error.ChildClosed;
        const admission = try inputAdmissionBytes(event);
        const required = std.math.add(usize, admission, self.terminal.replyBytes().len) catch
            return error.WriteQueueFull;
        if (required > self.writes.remaining()) return error.WriteQueueFull;
        var scratch: vt.Terminal.InputScratch = undefined;
        var encoded = try self.terminal.encodeInput(self.allocator, &scratch, event);
        defer encoded.deinit();
        if (encoded.bytes.len == 1 and self.terminal.termiosSignals() and
            try self.transport.handleTermiosSignal(encoded.bytes[0]))
        {
            try self.collectReplies();
            return;
        }
        try self.collectReplies();
        try self.writes.append(encoded.bytes);
    }

    /// PTY descriptor for the existing app worker's poll loop.
    pub fn descriptor(self: *const Core) error{NotStarted}!pty.Descriptor {
        return self.transport.masterFd();
    }
    /// Canonical scalar storage is retaining unfinished input.
    pub fn inputBlocked(self: *const Core) bool {
        return self.terminal.inputBlocked();
    }
    /// Accepted input or replies await PTY writability.
    pub fn writePending(self: *const Core) bool {
        return !self.write_closed and self.writes.count != 0;
    }

    /// Capacity reclaimed by PTY writes lets the worker retry its retained FIFO head.
    pub fn writeRoom(self: *const Core) usize {
        return self.writes.remaining();
    }
    /// Retained bytes can advance without a new PTY readiness event.
    pub fn bufferedOutputRunnable(self: *const Core) bool {
        const replies = self.terminal.replyBytes().len;
        return self.input_retry_at == null and !self.terminal.hasPendingProgramStatus() and self.read_start < self.read_end and
            (replies == 0 or replies <= self.writes.remaining());
    }

    /// Whether new PTY readability can cause progress. Polling POLLIN while a
    /// retained reply cannot fit the outbox wakes indefinitely on unchanged data.
    /// A buffered tail progresses through the existing zero-timeout service path.
    pub fn readAdmissible(self: *const Core) bool {
        if (self.stream_closed or self.terminal.inputBlocked() or self.input_retry_at != null or self.terminal.hasPendingProgramStatus() or
            self.read_start != self.read_end) return false;
        return self.write_closed or self.terminal.replyBytes().len <= self.writes.remaining();
    }

    fn collectReplies(self: *Core) error{WriteQueueFull}!void {
        const bytes = self.terminal.replyBytes();
        if (bytes.len == 0) return;
        if (self.write_closed) {
            self.undelivered_bytes +|= bytes.len;
            // zig-audit: acknowledge catch_unreachable
            // reason: A closed PTY cannot consume replies; retire exactly its existing VT buffer.
            self.terminal.consumeReplyBytes(bytes.len) catch unreachable;
            return;
        }
        try self.writes.append(bytes);
        // zig-audit: acknowledge catch_unreachable
        // reason: Only the exact accepted byte count is retired from VT after an atomic append.
        self.terminal.consumeReplyBytes(bytes.len) catch unreachable;
    }

    fn markWriteClosed(self: *Core) void {
        self.write_closed = true;
        self.undelivered_bytes +|= self.writes.count;
        self.writes.count = 0;
        // Final child output can still arrive. Mandatory replies are no longer
        // deliverable, so account for them without blocking its read-side drain.
        // zig-audit: acknowledge catch_unreachable
        // reason: The closed-write branch retires replies without attempting bounded outbox admission.
        self.collectReplies() catch unreachable;
    }

    // zig-audit: acknowledge anytype
    // reason: The production PTY and deterministic error-scripted writer use identical bounded flush logic.
    fn flushWriteTurn(self: *Core, writer: anytype) pty.WriteError!void {
        if (self.write_closed) return;
        flushWrites(writer, &self.writes) catch |failure| switch (failure) {
            error.ChildClosed => self.markWriteClosed(),
            else => return failure,
        };
    }

    /// One bounded service turn, retaining host consequences for desktop policy.
    pub fn service(self: *Core, readable: bool, writable: bool, timestamp_ns: u64) ServiceError!Service {
        var synchronized_output: vt.Terminal.SynchronizedOutputProgress = .{};
        if (writable and self.writePending()) try self.flushWriteTurn(&self.transport);
        if (!self.terminal.inputBlocked()) {
            self.collectReplies() catch |failure| switch (failure) {
                error.WriteQueueFull => return self.result(timestamp_ns, synchronized_output),
            };
        }
        try self.processBuffered(timestamp_ns, &synchronized_output);
        if (self.input_retry_at == null and self.terminal.replyBytes().len == 0 and
            !self.terminal.hasPendingProgramStatus() and
            self.read_start == self.read_end and readable and !self.stream_closed)
        {
            var read_calls: u8 = 0;
            while (read_calls < read_calls_per_turn and self.read_start == self.read_end and
                !self.stream_closed and !synchronized_output.ended)
            {
                const count = self.transport.read(&self.reads) catch |failure| switch (failure) {
                    error.Interrupted, error.WouldBlock => 0,
                    error.EndOfStream => closed: {
                        self.stream_closed = true;
                        break :closed 0;
                    },
                    else => return failure,
                };
                if (count == 0) break;
                read_calls += 1;
                self.read_start = 0;
                self.read_end = count;
                try self.processBuffered(timestamp_ns, &synchronized_output);
                if (self.read_start != self.read_end or self.writes.count != 0) break;
                if (self.terminal.consequenceHead() != null) break;
            }
        }
        switch (try self.transport.observeChild()) {
            .running => {},
            .exited => |value| self.child_exit = value,
        }
        return self.result(timestamp_ns, synchronized_output);
    }

    fn processBuffered(self: *Core, timestamp_ns: u64, synced: *vt.Terminal.SynchronizedOutputProgress) ServiceError!void {
        if (self.input_retry_at) |deadline| if (timestamp_ns < deadline) return;
        while (self.read_start < self.read_end or self.terminal.inputBlocked()) {
            // The worker drains ordered status/prompt events between prefixes.
            // Unlike disposable attention, these reports cannot be dropped.
            if (self.terminal.hasPendingProgramStatus()) return;
            const blocked = self.terminal.inputBlocked();
            if (!blocked) {
                self.collectReplies() catch |failure| switch (failure) {
                    error.WriteQueueFull => return,
                };
            }
            const bytes = if (blocked) &.{} else self.reads[self.read_start..self.read_end];
            const progress = try self.terminal.feedAtServiceBoundaryRelievingConsequences(bytes, timestamp_ns, relieveConsequencePressure);
            std.debug.assert(progress.consumed <= self.read_end - self.read_start);
            self.read_start += progress.consumed;
            synced.merge(progress.summary.synchronized_output);
            std.debug.assert(!progress.summary.titleChanged() or progress.summary.stateChanged());
            if (progress.input_blocked) |failure| {
                if (failure == error.ScalarCapacity) return error.ScalarCapacity;
                if (failure == error.HistoryCapacity) return error.HistoryCapacity;
                self.input_retry_at = timestamp_ns +| input_retry_ns;
                return;
            }
            self.input_retry_at = null;
            self.collectReplies() catch |failure| switch (failure) {
                error.WriteQueueFull => return,
            };
            if (progress.summary.synchronized_output.ended and self.read_start < self.read_end) return;
        }
        self.read_start = 0;
        self.read_end = 0;
    }

    fn result(self: *Core, now: u64, synced: vt.Terminal.SynchronizedOutputProgress) Service {
        const animation = self.terminal.serviceAnimations(now);
        return .{
            .synchronized_output = synced,
            .animation_changed = animation.changed,
            .stream_closed = self.stream_closed,
            .child_exit = self.child_exit,
            .write_pending = self.writePending(),
            .animation_wait_ms = animation.next_ms,
            .input_retry_wait_ms = if (self.input_retry_at) |deadline| retry: {
                const remaining = deadline -| now;
                const ms = remaining / std.time.ns_per_ms + @intFromBool(remaining % std.time.ns_per_ms != 0);
                break :retry @intCast(@min(ms, std.math.maxInt(u32)));
            } else null,
        };
    }
};

fn pixelExtent(cells: u16, pixels: u32) error{InvalidDimensions}!u16 {
    if (cells == 0 or pixels == 0) return error.InvalidDimensions;
    return std.math.cast(u16, @as(u64, cells) * pixels) orelse error.InvalidDimensions;
}

fn inputAdmissionBytes(event: vt.Terminal.InputEvent) error{WriteQueueFull}!usize {
    return switch (event) {
        .bytes => |bytes| bytes.len,
        .paste => |bytes| std.math.add(usize, bytes.len, 12) catch return error.WriteQueueFull,
        .key, .mouse, .focus => @sizeOf(vt.Terminal.InputScratch),
    };
}

// zig-audit: acknowledge anytype
// reason: Production specializes for Owned PTY; scripted writers prove partial and error progress.
fn flushWrites(owner: anytype, queue: *WriteQueue) pty.WriteError!void {
    var calls: usize = 0;
    var written: usize = 0;
    defer if (written != 0) queue.consume(written);
    while (calls < write_calls_per_turn and written < write_bytes_per_turn and written < queue.count) {
        calls += 1;
        const budget = @min(queue.count - written, write_bytes_per_turn - written);
        const accepted = owner.write(queue.bytes[written..][0..budget]) catch |failure| switch (failure) {
            error.Interrupted => continue,
            error.WouldBlock => return,
            else => return failure,
        };
        std.debug.assert(accepted <= budget);
        written += accepted;
    }
}

/// Keep VT's bounded consequence-pressure fallback, including mandatory replies.
fn relieveConsequencePressure(machine: *vt.Terminal) vt.Terminal.FeedError!void {
    const current = machine.consequenceHead() orelse return error.ConsequencePressure;
    const id = current.id();
    switch (current) {
        .program_status => return error.ConsequencePressure,
        .clipboard => |request| if (request.kind == .query) {
            const replied = machine.replyClipboard(id, "") catch |failure| switch (failure) {
                // zig-audit: acknowledge unreachable
                // reason: The retained FIFO head was just checked, so identity cannot become stale.
                error.StaleClipboardRequest => unreachable,
                else => |err| return err,
            };
            std.debug.assert(replied);
            return;
        },
        .pointer_shape => |request| if (request.payload.len != 0 and request.payload[0] == '?') {
            machine.replyPointerShape(id, "default") catch |failure| switch (failure) {
                // zig-audit: acknowledge unreachable
                // reason: Valid matching query is still the same unmodified FIFO head.
                error.StalePointerShape, error.PointerShapeReplyMismatch => unreachable,
                else => |err| return err,
            };
            return;
        },
        .container => |request| switch (request.request) {
            .report_screen_cells => {
                const view = machine.semanticView(0);
                machine.replyContainer(id, .{ .screen_cells = .{ .rows = view.rows, .cols = view.cols } }) catch |failure| switch (failure) {
                    // zig-audit: acknowledge unreachable
                    // reason: The inspected exact query and response variant match the retained FIFO head.
                    error.StaleContainerRequest, error.ContainerReplyMismatch => unreachable,
                    else => |err| return err,
                };
                return;
            },
            .report_state, .report_position, .report_icon_title => {
                // zig-audit: acknowledge catch_unreachable
                // reason: An exact pending query is declined on the same serialized VT owner.
                machine.declineContainerQuery(id) catch unreachable;
                return;
            },
            else => {},
        },
        .color_preference_query => {
            machine.replyColorPreference(id, .dark) catch |failure| switch (failure) {
                // zig-audit: acknowledge unreachable
                // reason: The color-preference query identity is checked without intervening mutation.
                error.StaleColorPreferenceQuery => unreachable,
                else => |err| return err,
            };
            return;
        },
        else => {},
    }
    machine.consumeConsequence(id) catch |failure| switch (failure) {
        // zig-audit: acknowledge unreachable
        // reason: The non-reply head was classified and retains its exact identity.
        error.StaleConsequence, error.ReplyRequired => unreachable,
    };
}

test "app PTY/VT service preserves ordered shell input and terminal output" {
    const allocator = std.testing.allocator;
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const core = try allocator.create(Core);
    defer allocator.destroy(core);
    try core.initInto(allocator, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf '\\033]0;READY\\007'; read answer; printf '\\033]0;%s\\007' \"$answer\"; sleep 2",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, .{ .width = 8, .height = 16 });
    defer core.deinit();

    var ready = false;
    for (0..5000) |_| {
        const now: u64 = @intCast(std.Io.Clock.awake.now(threaded.io()).toNanoseconds());
        const serviced = try core.service(true, true, now);
        if (serviced.stream_closed and serviced.child_exit != null) return error.ChildExited;
        if (core.terminal.title()) |title| if (std.mem.eql(u8, title, "READY")) {
            ready = true;
            break;
        };
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(ready);
    try core.input(.{ .bytes = "DONE\n" });
    var done = false;
    for (0..5000) |_| {
        const now: u64 = @intCast(std.Io.Clock.awake.now(threaded.io()).toNanoseconds());
        const serviced = try core.service(true, true, now);
        if (serviced.stream_closed and serviced.child_exit != null) return error.ChildExited;
        if (core.terminal.title()) |title| if (std.mem.eql(u8, title, "DONE")) {
            done = true;
            break;
        };
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(done);
    try std.testing.expectEqual(@as(usize, 0), core.writes.count);
}

test "bounded app outbox retires exactly written bytes on error" {
    const Writer = struct {
        calls: usize = 0,
        fn write(self: *@This(), _: []const u8) pty.WriteError!usize {
            self.calls += 1;
            return if (self.calls == 1) 2 else error.WouldBlock;
        }
    };
    var queue: WriteQueue = .{};
    try queue.append("abcdef");
    var writer: Writer = .{};
    try flushWrites(&writer, &queue);
    try std.testing.expectEqual(@as(usize, 2), writer.calls);
    try std.testing.expectEqualStrings("cdef", queue.bytes[0..queue.count]);
}

test "canonical service yields the unread suffix on synchronized-output release" {
    const allocator = std.testing.allocator;
    const core = try allocator.create(Core);
    defer allocator.destroy(core);
    core.* = .{ .allocator = allocator, .transport = undefined, .terminal = undefined };
    try vt.Terminal.initWithHistoryInto(&core.terminal, allocator, 3, 12, 0);
    defer core.terminal.deinit();

    const bytes = "\x1b[?2026hA\x1b[?2026lB";
    @memcpy(core.reads[0..bytes.len], bytes);
    core.read_end = bytes.len;
    var synchronized: vt.Terminal.SynchronizedOutputProgress = .{};
    try core.processBuffered(0, &synchronized);
    try std.testing.expect(synchronized.ended);
    try std.testing.expect(core.read_start < core.read_end);
    try std.testing.expect(core.bufferedOutputRunnable());
    try std.testing.expect(!core.readAdmissible());
    try std.testing.expectEqual(@as(u16, 0), core.terminal.consequenceCount());
    synchronized = .{};
    try core.processBuffered(0, &synchronized);
    try std.testing.expectEqual(@as(usize, 0), core.read_start);
    try std.testing.expectEqual(@as(usize, 0), core.read_end);
    try std.testing.expect(core.readAdmissible());
    const visible = core.terminal.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'A'), visible.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), visible.cellAt(0, 1));
}

test "app canonical scalar pressure retries the retained input without re-reading PTY bytes" {
    const allocator = std.testing.allocator;
    var failing = std.testing.FailingAllocator.init(allocator, .{});
    const core = try allocator.create(Core);
    defer allocator.destroy(core);
    core.* = .{ .allocator = failing.allocator(), .transport = undefined, .terminal = undefined };
    try vt.Terminal.initWithHistoryInto(&core.terminal, failing.allocator(), 1, 512, 0);
    defer core.terminal.deinit();

    var length: usize = 0;
    const lead = "e";
    const marks = "\xcc\x81\xcc\x82\xcc\x83\xcc\x84\xcc\x85\xcc\x86\xcc\x87\xcc\x88";
    for (0..511) |_| {
        @memcpy(core.reads[length..][0..lead.len], lead);
        length += lead.len;
        @memcpy(core.reads[length..][0..marks.len], marks);
        length += marks.len;
    }
    const tail = "X";
    @memcpy(core.reads[length..][0..tail.len], tail);
    length += tail.len;
    core.read_end = length;
    failing.fail_index = failing.alloc_index;
    var synchronized: vt.Terminal.SynchronizedOutputProgress = .{};
    try core.processBuffered(1, &synchronized);
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expect(core.inputBlocked());
    try std.testing.expect(!core.readAdmissible());
    const unread = core.read_start;
    try std.testing.expect(unread < core.read_end);
    const retry_at = core.input_retry_at.?;
    try core.processBuffered(retry_at - 1, &synchronized);
    try std.testing.expectEqual(unread, core.read_start);
    try std.testing.expect(core.inputBlocked());

    try core.processBuffered(retry_at, &synchronized);
    try std.testing.expect(core.inputBlocked());
    try std.testing.expectEqual(unread, core.read_start);
    const second_retry = core.input_retry_at.?;
    try std.testing.expect(second_retry > retry_at);
    failing.fail_index = std.math.maxInt(usize);
    try core.processBuffered(second_retry, &synchronized);
    try std.testing.expect(!core.inputBlocked());
    try std.testing.expect(core.input_retry_at == null);
    try std.testing.expectEqual(@as(usize, 0), core.read_end);
    try std.testing.expect(core.readAdmissible());
    const view = core.terminal.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'e'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'e'), view.cellAt(0, 510));
    try std.testing.expectEqual(@as(u21, 'X'), view.cellAt(0, 511));
}

test "canonical consequence pressure advances past retained bells without losing output" {
    const allocator = std.testing.allocator;
    const core = try allocator.create(Core);
    defer allocator.destroy(core);
    core.* = .{ .allocator = allocator, .transport = undefined, .terminal = undefined };
    try vt.Terminal.initWithHistoryInto(&core.terminal, allocator, 2, 8, 0);
    defer core.terminal.deinit();

    var bytes: [66]u8 = undefined;
    bytes[0] = 'X';
    @memset(bytes[1..65], 0x07);
    bytes[65] = 'Y';
    @memcpy(core.reads[0..bytes.len], &bytes);
    core.read_end = bytes.len;
    var synchronized: vt.Terminal.SynchronizedOutputProgress = .{};
    try core.processBuffered(1, &synchronized);
    // More bells than the retained consequence capacity plus a final text byte
    // prove pressure relief advanced the feed instead of stalling it.
    try std.testing.expectEqual(@as(u16, 32), core.terminal.consequenceCount());
    const view = core.terminal.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'X'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'Y'), view.cellAt(0, 1));
    try std.testing.expect(core.readAdmissible());
    try std.testing.expectEqual(@as(usize, 0), core.read_end);
}

test "app canonical PTY resize failure discards prepared VT without changing geometry" {
    const ResizeTransport = struct {
        calls: usize = 0,
        fail: bool = true,
        cols: u16 = 0,
        rows: u16 = 0,
        width: u16 = 0,
        height: u16 = 0,
        fn resizeWithPixels(self: *@This(), cols: u16, rows: u16, width: u16, height: u16) pty.ResizeError!void {
            self.calls += 1;
            if (self.fail) return error.ResizeFailed;
            self.cols = cols;
            self.rows = rows;
            self.width = width;
            self.height = height;
        }
    };
    const allocator = std.testing.allocator;
    const core = try allocator.create(Core);
    defer allocator.destroy(core);
    core.* = .{ .allocator = allocator, .transport = undefined, .terminal = undefined };
    try vt.Terminal.initWithHistoryInto(&core.terminal, allocator, 2, 4, 8);
    defer core.terminal.deinit();
    try core.terminal.setCellPixelSize(8, 16);
    try std.testing.expect((try core.terminal.feed("A")).stateChanged());
    const before = core.terminal.semanticSequence();
    var transport: ResizeTransport = .{};
    const target: vt.Terminal.CellPixelSize = .{ .width = 9, .height = 17 };

    try std.testing.expectError(error.ResizeFailed, core.resizeGeometryWith(&transport, 3, 5, target));
    try std.testing.expectEqual(@as(usize, 1), transport.calls);
    try std.testing.expectEqual(before, core.terminal.semanticSequence());
    try std.testing.expectEqual(@as(u16, 2), core.terminal.semanticView(0).rows);
    try std.testing.expectEqual(@as(u16, 4), core.terminal.semanticView(0).cols);
    try std.testing.expectEqual(@as(u32, 8), core.terminal.cellPixelSize().?.width);
    try std.testing.expectEqual(@as(u32, 16), core.terminal.cellPixelSize().?.height);
    try std.testing.expectEqual(@as(u21, 'A'), core.terminal.semanticView(0).cellAt(0, 0));

    transport.fail = false;
    try core.resizeGeometryWith(&transport, 3, 5, target);
    try std.testing.expectEqual(@as(usize, 2), transport.calls);
    try std.testing.expectEqual(@as(u16, 5), transport.cols);
    try std.testing.expectEqual(@as(u16, 3), transport.rows);
    try std.testing.expectEqual(@as(u16, 45), transport.width);
    try std.testing.expectEqual(@as(u16, 51), transport.height);
    try std.testing.expectEqual(@as(u16, 3), core.terminal.semanticView(0).rows);
    try std.testing.expectEqual(@as(u16, 5), core.terminal.semanticView(0).cols);
    try std.testing.expectEqual(@as(u32, 9), core.terminal.cellPixelSize().?.width);
    try std.testing.expectEqual(@as(u32, 17), core.terminal.cellPixelSize().?.height);
    try std.testing.expectEqual(@as(u21, 'A'), core.terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectError(error.InvalidDimensions, core.resizeGeometryWith(&transport, 3, 5, .{ .width = 65535, .height = 17 }));
    try std.testing.expectEqual(@as(usize, 2), transport.calls);
}

test "VT reply bytes precede later app input without loss on full outbox" {
    const allocator = std.testing.allocator;
    const core = try allocator.create(Core);
    defer allocator.destroy(core);
    core.* = .{ .allocator = allocator, .transport = undefined, .terminal = undefined };
    try vt.Terminal.initWithHistoryInto(&core.terminal, allocator, 3, 12, 0);
    defer core.terminal.deinit();

    try std.testing.expect((try core.terminal.feed("\x1b]52;c;?\x07")).stateChanged());
    const id = core.terminal.consequenceHead().?.id();
    try std.testing.expect(try core.terminal.replyClipboard(id, ""));
    const reply = try allocator.dupe(u8, core.terminal.replyBytes());
    defer allocator.free(reply);
    try std.testing.expect(reply.len != 0);

    const full: [write_queue_bytes - 1]u8 = @splat('x');
    try core.writes.append(&full);
    try std.testing.expect(!core.readAdmissible());
    try std.testing.expectError(error.WriteQueueFull, core.input(.{ .bytes = "late" }));
    try std.testing.expectEqual(@as(usize, 1), core.writes.remaining());
    try std.testing.expectEqualSlices(u8, reply, core.terminal.replyBytes());
    core.writes = .{};
    try std.testing.expect(core.readAdmissible());
    try core.input(.{ .bytes = "late" });
    try std.testing.expectEqualSlices(u8, reply, core.writes.bytes[0..reply.len]);
    try std.testing.expectEqualStrings("late", core.writes.bytes[reply.len..core.writes.count]);
    try std.testing.expectEqual(@as(usize, 0), core.terminal.replyBytes().len);
}

test "child write closure accounts for undelivered suffix and leaves read-side service available" {
    const Writer = struct {
        calls: usize = 0,
        fn write(self: *@This(), _: []const u8) pty.WriteError!usize {
            self.calls += 1;
            return if (self.calls == 1) 2 else error.ChildClosed;
        }
    };
    const allocator = std.testing.allocator;
    const core = try allocator.create(Core);
    defer allocator.destroy(core);
    core.* = .{ .allocator = allocator, .transport = undefined, .terminal = undefined };
    try vt.Terminal.initWithHistoryInto(&core.terminal, allocator, 3, 12, 0);
    defer core.terminal.deinit();
    try core.writes.append("abcdef");
    var writer: Writer = .{};
    try core.flushWriteTurn(&writer);
    try std.testing.expectEqual(@as(usize, 2), writer.calls);
    try std.testing.expect(core.write_closed);
    try std.testing.expectEqual(@as(usize, 4), core.undelivered_bytes);
    try std.testing.expectEqual(@as(usize, 0), core.writes.count);
    try std.testing.expect(!core.writePending());
    try std.testing.expect(core.readAdmissible());
    try std.testing.expectError(error.ChildClosed, core.input(.{ .bytes = "late" }));

    try std.testing.expect((try core.terminal.feed("\x1b]52;c;?\x07")).stateChanged());
    const id = core.terminal.consequenceHead().?.id();
    try std.testing.expect(try core.terminal.replyClipboard(id, ""));
    const reply_len = core.terminal.replyBytes().len;
    try std.testing.expect(reply_len != 0);
    try core.collectReplies();
    try std.testing.expectEqual(@as(usize, 4) + reply_len, core.undelivered_bytes);
    try std.testing.expectEqual(@as(usize, 0), core.terminal.replyBytes().len);
    try std.testing.expect(core.readAdmissible());
}

test "exited child with queued input still yields final PTY output and exit observation" {
    const allocator = std.testing.allocator;
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const core = try allocator.create(Core);
    defer allocator.destroy(core);
    try core.initInto(allocator, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "printf '\\033]0;LAST\\007'; exit 0",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, .{ .width = 8, .height = 16 });
    defer core.deinit();

    var exited = false;
    for (0..5000) |_| {
        switch (try core.transport.observeChild()) {
            .running => try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake),
            .exited => {
                exited = true;
                break;
            },
        }
    }
    try std.testing.expect(exited);
    try core.input(.{ .bytes = "undeliverable" });
    var saw_final = false;
    var observed_exit = false;
    for (0..5000) |_| {
        const now: u64 = @intCast(std.Io.Clock.awake.now(threaded.io()).toNanoseconds());
        const result = try core.service(true, true, now);
        saw_final = saw_final or if (core.terminal.title()) |title| std.mem.eql(u8, title, "LAST") else false;
        observed_exit = observed_exit or result.child_exit != null;
        if (saw_final and observed_exit and result.stream_closed) break;
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(saw_final);
    try std.testing.expect(observed_exit);
    try std.testing.expect(core.stream_closed);
    // PTY masters may still accept a write after the child has exited; the
    // scripted ChildClosed writer above independently proves that branch.
    if (core.write_closed) try std.testing.expect(core.undelivered_bytes != 0);
}

test "Rex buffered PTY reports reach the host in order without pressure drops" {
    const allocator = std.testing.allocator;
    const core = try allocator.create(Core);
    defer allocator.destroy(core);
    core.* = .{ .allocator = allocator, .transport = undefined, .terminal = undefined };
    try vt.Terminal.initWithHistoryInto(&core.terminal, allocator, 2, 8, 0);
    defer core.terminal.deinit();
    core.terminal.setProgramStatusConsumer(true);
    var used: usize = 0;
    for (0..12) |i| {
        const body = try std.fmt.bufPrint(core.reads[used..], "\x1b]7501;state=working:id=job{d}\x07", .{i});
        used += body.len;
    }
    core.read_end = used;
    var synchronized: vt.Terminal.SynchronizedOutputProgress = .{};
    var seen: usize = 0;
    for (0..13) |_| {
        try core.processBuffered(1, &synchronized);
        while (core.terminal.consequenceHead()) |head| {
            var expected: [16]u8 = undefined;
            const id = try std.fmt.bufPrint(&expected, "job{d}", .{seen});
            try std.testing.expectEqualStrings(id, head.program_status.action.report.id);
            seen += 1;
            try core.terminal.consumeConsequence(head.id());
        }
        if (core.read_end == 0) break;
    }
    try std.testing.expectEqual(@as(usize, 12), seen);
    try std.testing.expectEqual(@as(usize, 0), core.read_end);
}
