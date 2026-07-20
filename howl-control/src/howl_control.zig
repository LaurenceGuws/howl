//! Owns one native PTY child and its concurrent, host-neutral Howl terminal state.

const std = @import("std");
const howl_pty = @import("howl_pty");
const howl_vt = @import("howl_vt");

/// Bounds one terminal surface width before model or PTY construction.
pub const max_cols: u16 = 512;
/// Bounds one terminal surface height before model or PTY construction.
pub const max_rows: u16 = 256;
/// Bounds retained semantic history independently from the active surface.
pub const max_history_rows: u16 = 16_384;
/// Bounds each complete input or terminal-reply transfer.
pub const max_transfer_bytes: usize = 64 * 1024;
const transport_buffer_bytes: usize = 4096;
const default_transfer_timeout_ms: u32 = 2000;

/// Supplies copied child launch values and bounded terminal dimensions.
pub const Config = struct {
    /// Names the executable copied into PTY launch ownership.
    shell: []const u8 = "/bin/sh",
    /// Runs one optional shell command; null starts an interactive shell.
    command: ?[]const u8 = null,
    /// Selects an optional child working directory.
    cwd: ?[]const u8 = null,
    /// Sets the initial nonzero bounded PTY and model width.
    cols: u16 = 80,
    /// Sets the initial nonzero bounded PTY and model height.
    rows: u16 = 24,
    /// Sets retained scrollback rows within `max_history_rows`.
    history_rows: u16 = 2000,
    /// Bounds each PTY input and terminal-reply transfer.
    transfer_timeout_ms: u32 = default_transfer_timeout_ms,
};

/// Delivers coalesced terminal mutation, stop, or failure notifications.
pub const Wake = struct {
    /// Borrows embedder state for the lifetime of the terminal.
    context: ?*anyopaque = null,
    /// Receives a coalesced notification from the reader thread.
    notify: *const fn (?*anyopaque) void = ignoreWake,
};

/// Reports invalid bounds or failure before terminal ownership transfers.
pub const InitError = howl_vt.Terminal.InitError || std.mem.Allocator.Error ||
    std.Thread.SpawnError || error{
    InvalidDimensions,
    InvalidHistory,
    InvalidTransferTimeout,
    ChildCwdFailed,
    ChildExecFailed,
    ChildSessionFailed,
    ChildStdioFailed,
    ForkFailed,
    MasterConfigureFailed,
    LaunchStatusFailed,
    LaunchStatusPipeFailed,
    OpenPtyFailed,
    ShellUnavailable,
    UnsupportedPlatform,
    WakePipeFailed,
};

/// Reports input encoding or transfer-bound rejection before PTY admission.
pub const InputError = howl_vt.Terminal.InputError || error{InputLimit};
/// Retains complete or exact partial PTY input transfer truth.
pub const InputTransfer = howl_pty.Transfer;
/// Uses Howl VT's bounded finalized-output copy and cursor outcomes.
pub const LogicalOutputResult = howl_vt.Terminal.LogicalOutputResult;
/// Reports invalid output-copy limits or allocation failure.
pub const LogicalOutputError = howl_vt.Terminal.LogicalOutputError;
/// Bounds one retained finalized logical line.
pub const logical_output_line_max_bytes = howl_vt.Terminal.logical_output_line_max_bytes;
/// Bounds aggregate retained output and one complete logical-output result.
pub const logical_output_max_bytes = howl_vt.Terminal.logical_output_max_bytes;
/// Selects one supported signal for the owned child process group.
pub const ControlSignal = howl_pty.ControlSignal;
/// Reports exact child probing and process-group signal outcomes.
pub const ControlResult = howl_pty.ControlResult;

/// Reports a resize rejected by the model or native PTY.
pub const ResizeError = howl_vt.Terminal.ResizeError || error{
    InvalidDimensions,
    NotStarted,
    PtyResizeFailed,
    ResizeRollbackFailed,
};

/// Reports the exact terminal-reader boundary that stopped making progress.
pub const ReaderError = error{
    ConsequenceLimit,
    ModelAllocationFailed,
    ParsedEventLimit,
    PtyReadFailed,
    PtyReplyCanceled,
    PtyReplyChildClosed,
    PtyReplyTimedOut,
    PtyReplyWaitFailed,
    PtyReplyWriteFailed,
    PtyWaitFailed,
    ReplyAllocationFailed,
    StringControlLimit,
};

/// Distinguishes active terminal progress from completion or an exact failed boundary.
pub const State = enum(u8) { running, stopped, failed };
/// Matches the VT owner's maximum retained bytes for one OSC 133 mark.
pub const shell_mark_metadata_max_bytes = howl_vt.Terminal.shell_mark_metadata_max_bytes;
/// Matches the VT owner's maximum retained shell-integration identity.
pub const shell_name_max_bytes = howl_vt.Terminal.shell_name_max_bytes;

comptime {
    std.debug.assert(shell_mark_metadata_max_bytes <= std.math.maxInt(u16));
    std.debug.assert(shell_name_max_bytes <= std.math.maxInt(u8));
}

/// Copies the latest real OSC 133 mark and any already-retained shell identity.
pub const ShellMark = struct {
    /// Identifies this accepted mark monotonically within one terminal.
    generation: u64,
    /// Retains the exact OSC 133 A, B, C, or D mark kind.
    kind: u8,
    /// Retains the optional status parsed from the mark without inference.
    status: ?i32,
    /// Stores bounded metadata bytes; only `metadata_len` bytes are meaningful.
    metadata: [shell_mark_metadata_max_bytes]u8,
    /// Bounds the meaningful metadata prefix within the fixed buffer.
    metadata_len: u16,
    /// Stores a retained shell identity; only `shell_len` bytes are meaningful.
    shell: [shell_name_max_bytes]u8,
    /// Bounds the meaningful shell prefix; zero means no shell identity.
    shell_len: u8,

    /// Borrows the copied bounded mark metadata.
    pub fn metadataBytes(self: *const ShellMark) []const u8 {
        return self.metadata[0..self.metadata_len];
    }

    /// Borrows the copied shell identity, when the terminal retained one.
    pub fn shellBytes(self: *const ShellMark) ?[]const u8 {
        if (self.shell_len == 0) return null;
        return self.shell[0..self.shell_len];
    }
};

/// Copies one coherent terminal status observation under the model and lifecycle locks.
pub const Status = struct {
    /// Reports the terminal progress lifecycle observation.
    state: State,
    /// Retains the exact terminal reader failure after a failed state.
    reader_error: ?ReaderError,
    /// Retains the accepted PTY prefix only when a terminal-reply transfer failed.
    reply_failure_transferred: ?usize,
    /// Reports that model resize failed and restoring the prior PTY geometry also failed.
    resize_rollback_failed: bool,
    /// Reports the model and PTY column count.
    cols: u16,
    /// Reports the model and PTY row count.
    rows: u16,
    /// Identifies the surface publication used for terminal metadata.
    publication: u64,
    /// Identifies the latest model mutation represented by the publication.
    dirty_generation: u64,
    /// Counts primary history rows dropped after bounded allocation failure.
    history_loss_generation: u64,
    /// Reports whether the current viewport belongs to the alternate screen.
    alternate_screen: bool,
    /// Identifies the oldest retained finalized primary line.
    output_oldest: u64,
    /// Identifies the newest finalized primary line, or zero before any line.
    output_newest: u64,
    /// Copies the latest accepted OSC 133 mark, or null before any mark.
    shell_mark: ?ShellMark,
};

const ReaderFailure = enum(u8) {
    none,
    consequence_limit,
    model_allocation_failed,
    parsed_event_limit,
    pty_read_failed,
    pty_reply_canceled,
    pty_reply_child_closed,
    pty_reply_timed_out,
    pty_reply_wait_failed,
    pty_reply_write_failed,
    pty_wait_failed,
    reply_allocation_failed,
    string_control_limit,
};

/// Borrows one semantic surface while preventing concurrent terminal mutation.
pub const Surface = struct {
    /// Retains the locked owner until this borrow is released.
    owner: *Terminal,
    /// Borrows Howl's complete semantic publication until `deinit`.
    publication: howl_vt.Terminal.SurfacePublication,

    /// Releases the terminal lock after the publication is consumed.
    pub fn deinit(self: *Surface) void {
        self.owner.lock.unlock(self.owner.io);
        self.* = undefined;
    }

    /// Retires dirty state for this publication while its borrow remains valid.
    pub fn acknowledge(self: *Surface) bool {
        return self.owner.model.ackSurface(self.publication.snapshot_seq);
    }
};

/// Owns one PTY child, reader thread, terminal model, and wake lifecycle.
/// The embedder serializes `deinit` against borrowed surfaces and public calls.
pub const Terminal = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    transport: howl_pty.Owned,
    model: howl_vt.Terminal,
    reader: std.Thread,
    lock: std.Io.Mutex = .init,
    write_lock: std.Io.Mutex = .init,
    // Lifecycle publication stays independent from the model lock used by hot surfaces.
    lifecycle_lock: std.Io.Mutex = .init,
    state_value: std.atomic.Value(State) = .init(.running),
    reader_failure: std.atomic.Value(ReaderFailure) = .init(.none),
    reply_failure_transferred: std.atomic.Value(usize) = .init(0),
    wake_generation: std.atomic.Value(u64) = .init(0),
    wake_consumed: std.atomic.Value(u64) = .init(0),
    wake_announced: std.atomic.Value(u64) = .init(0),
    resize_rollback_failed: std.atomic.Value(bool) = .init(false),
    wake: Wake,
    cols: u16,
    rows: u16,
    transfer_timeout_ms: u32,

    /// Constructs and starts every owned resource before returning a stable pointer.
    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        config: Config,
        wake: Wake,
    ) InitError!*Terminal {
        try validateSize(config.cols, config.rows);
        if (config.history_rows > max_history_rows) return error.InvalidHistory;
        if (config.transfer_timeout_ms == 0) return error.InvalidTransferTimeout;

        var transport = try howl_pty.Owned.init(
            allocator,
            config.shell,
            config.command,
            config.cwd,
        );
        errdefer transport.deinit();
        var model = try howl_vt.Terminal.initWithHistory(
            allocator,
            config.rows,
            config.cols,
            config.history_rows,
        );
        errdefer model.deinit();
        transport.start(config.cols, config.rows) catch |failure| switch (failure) {
            error.AlreadyStarted => @panic("fresh PTY owner reported already started"),
            else => |expected| return expected,
        };

        const self = try allocator.create(Terminal);
        errdefer allocator.destroy(self);
        self.* = .{
            .allocator = allocator,
            .io = io,
            .transport = transport,
            .model = model,
            .reader = undefined,
            .wake = wake,
            .cols = config.cols,
            .rows = config.rows,
            .transfer_timeout_ms = config.transfer_timeout_ms,
        };
        self.reader = try .spawn(.{}, readLoop, .{self});
        return self;
    }

    /// Stops the reader and child before releasing model and allocation ownership.
    pub fn deinit(self: *Terminal) void {
        self.cancel();
        self.reader.join();
        self.transport.deinit();
        self.model.deinit();
        const allocator = self.allocator;
        self.* = undefined;
        allocator.destroy(self);
    }

    /// Returns the current lifecycle state without blocking the caller.
    pub fn state(self: *const Terminal) State {
        return self.state_value.load(.acquire);
    }

    /// Returns the reader failure after state becomes `failed`.
    pub fn readerError(self: *Terminal) ?ReaderError {
        self.lifecycle_lock.lockUncancelable(self.io);
        defer self.lifecycle_lock.unlock(self.io);
        return decodeReaderFailure(self.reader_failure.load(.monotonic));
    }

    /// Acknowledges every mutation published before this call.
    /// A concurrent later mutation is announced before this call returns or by its producer.
    pub fn consumeWake(self: *Terminal) void {
        const observed = self.wake_generation.load(.acquire);
        self.acknowledgeWake(observed);
    }

    /// Concurrently stops terminal progress and wakes active PTY reads or writes.
    /// The embedder still serializes destructive `deinit` after public calls return.
    pub fn cancel(self: *Terminal) void {
        self.lifecycle_lock.lockUncancelable(self.io);
        const changed = self.state_value.load(.monotonic) == .running;
        if (changed) self.state_value.store(.stopped, .release);
        self.lifecycle_lock.unlock(self.io);
        if (changed) self.notify();
        self.transport.cancel();
    }

    /// Encodes one input event and retains complete or partial PTY transfer truth.
    pub fn send(self: *Terminal, event: howl_vt.Terminal.InputEvent) InputError!InputTransfer {
        if (self.state_value.load(.acquire) != .running) {
            return .{ .incomplete = .{ .transferred = 0, .reason = .not_started } };
        }
        self.lock.lockUncancelable(self.io);
        var scratch: howl_vt.Terminal.InputScratch = .{};
        var encoded = self.model.encodeInput(self.allocator, &scratch, event) catch |failure| {
            self.lock.unlock(self.io);
            return failure;
        };
        self.lock.unlock(self.io);
        defer encoded.deinit();
        if (encoded.bytes.len > max_transfer_bytes) return error.InputLimit;
        self.write_lock.lockUncancelable(self.io);
        defer self.write_lock.unlock(self.io);
        return self.transport.transfer(self.io, encoded.bytes, self.transfer_timeout_ms);
    }

    /// Applies one bounded size and reports whether terminal geometry changed.
    pub fn resize(self: *Terminal, cols: u16, rows: u16) ResizeError!bool {
        try validateSize(cols, rows);
        if (self.state_value.load(.acquire) != .running) return error.NotStarted;
        self.lock.lockUncancelable(self.io);
        var announce_failure = false;
        defer {
            self.lock.unlock(self.io);
            if (announce_failure) self.notify();
        }
        if (self.cols == cols and self.rows == rows) return false;
        self.transport.resize(cols, rows) catch |failure| switch (failure) {
            error.NotStarted => return error.NotStarted,
            error.ResizeFailed => return error.PtyResizeFailed,
        };
        self.model.resize(rows, cols) catch |failure| {
            // The model preserves its old surface on failure; restore the PTY
            // dimensions. This catch is the sole route into the failed split-
            // geometry transition when the compensating ioctl also fails.
            self.transport.resize(self.cols, self.rows) catch {
                self.stopAfterResizeRollbackFailure();
                announce_failure = true;
                return error.ResizeRollbackFailed;
            };
            return failure;
        };
        self.cols = cols;
        self.rows = rows;
        return true;
    }

    /// Copies finalized primary output and its publication-scoped open line.
    pub fn copyLogicalOutput(
        self: *Terminal,
        allocator: std.mem.Allocator,
        cursor: u64,
        max_lines: u16,
        max_bytes: usize,
    ) LogicalOutputError!LogicalOutputResult {
        self.lock.lockUncancelable(self.io);
        defer self.lock.unlock(self.io);
        return self.model.copyLogicalOutput(allocator, cursor, max_lines, max_bytes);
    }

    /// Copies lifecycle, geometry, publication, output, and shell-mark facts coherently.
    pub fn status(self: *Terminal) Status {
        self.lock.lockUncancelable(self.io);
        defer self.lock.unlock(self.io);
        self.lifecycle_lock.lockUncancelable(self.io);
        defer self.lifecycle_lock.unlock(self.io);
        const publication = self.model.surfaceSnapshot();
        const output = self.model.logicalOutputRange();
        var shell_mark: ?ShellMark = null;
        if (publication.shell_mark.generation != 0) {
            var mark = ShellMark{
                .generation = publication.shell_mark.generation,
                .kind = publication.shell_mark.kind,
                .status = publication.shell_mark.status,
                .metadata = @splat(0),
                .metadata_len = @intCast(publication.shell_mark.metadata.len),
                .shell = @splat(0),
                .shell_len = 0,
            };
            @memcpy(mark.metadata[0..mark.metadata_len], publication.shell_mark.metadata);
            if (publication.shell_integration) |integration| if (integration.shell) |shell| {
                mark.shell_len = @intCast(shell.len);
                @memcpy(mark.shell[0..mark.shell_len], shell);
            };
            shell_mark = mark;
        }
        const reader_error = decodeReaderFailure(self.reader_failure.load(.monotonic));
        return .{
            .state = self.state_value.load(.monotonic),
            .reader_error = reader_error,
            .reply_failure_transferred = replyFailureTransferred(
                reader_error,
                self.reply_failure_transferred.load(.monotonic),
            ),
            .resize_rollback_failed = self.resize_rollback_failed.load(.monotonic),
            .cols = self.cols,
            .rows = self.rows,
            .publication = publication.snapshot_seq,
            .dirty_generation = publication.dirty_generation,
            .history_loss_generation = publication.history_loss_generation,
            .alternate_screen = publication.is_alternate_screen,
            .output_oldest = output.oldest,
            .output_newest = output.newest,
            .shell_mark = shell_mark,
        };
    }

    /// Delivers one supported signal to the owned child process group.
    /// Process-group control remains available after terminal progress fails.
    pub fn control(self: *Terminal, signal: ControlSignal) ControlResult {
        self.write_lock.lockUncancelable(self.io);
        defer self.write_lock.unlock(self.io);
        return self.transport.control(signal);
    }

    /// Locks and borrows one complete semantic surface publication.
    pub fn surface(self: *Terminal) Surface {
        self.lock.lockUncancelable(self.io);
        return .{ .owner = self, .publication = self.model.surfaceSnapshot() };
    }

    fn readLoop(self: *Terminal) void {
        var bytes: [transport_buffer_bytes]u8 = undefined;
        while (self.state_value.load(.acquire) == .running) {
            const wait = self.transport.waitReadable(-1) catch |failure| switch (failure) {
                error.NotStarted => return self.finish(.stopped, .none),
                error.WaitFailed => return self.finish(.failed, .pty_wait_failed),
            };
            switch (wait) {
                .timeout => continue,
                .canceled => return self.finish(.stopped, .none),
                .ready => {},
            }
            const count = self.transport.read(&bytes) catch |failure| switch (failure) {
                error.Interrupted, error.WouldBlock => continue,
                error.EndOfStream, error.NotStarted => return self.finish(.stopped, .none),
                error.ReadFailed => return self.finish(.failed, .pty_read_failed),
            };
            self.consume(bytes[0..count]) catch |failure| {
                if (self.state_value.load(.acquire) != .running) return;
                return self.finish(.failed, readerFailure(failure));
            };
        }
    }

    fn consume(self: *Terminal, bytes: []const u8) ReaderError!void {
        self.lock.lockUncancelable(self.io);
        const summary = self.model.feed(bytes) catch |failure| {
            self.lock.unlock(self.io);
            return switch (failure) {
                error.OutOfMemory => error.ModelAllocationFailed,
                error.ConsequenceLimit => error.ConsequenceLimit,
                error.ParsedEventLimit => error.ParsedEventLimit,
                error.StringControlLimit => error.StringControlLimit,
            };
        };
        const reply = self.model.drainPendingOutput(self.allocator) catch {
            self.lock.unlock(self.io);
            return error.ReplyAllocationFailed;
        };
        self.lock.unlock(self.io);
        std.debug.assert(reply.len <= max_transfer_bytes);
        if (reply.len != 0) {
            self.write_lock.lockUncancelable(self.io);
            const transfer = self.transport.transfer(self.io, reply, self.transfer_timeout_ms);
            self.write_lock.unlock(self.io);
            switch (transfer) {
                .complete => {},
                .incomplete => |failure| {
                    self.allocator.free(reply);
                    return self.retainReplyTransferFailure(
                        failure.transferred,
                        failure.reason,
                    );
                },
            }
        }
        self.allocator.free(reply);
        if (summary.state_changed or
            summary.title_changed or
            summary.icon_changed or
            summary.history_lost) self.notify();
    }

    fn finish(self: *Terminal, state_value: State, failure: ReaderFailure) void {
        std.debug.assert(
            (state_value == .stopped and failure == .none) or
                (state_value == .failed and failure != .none),
        );
        self.lifecycle_lock.lockUncancelable(self.io);
        if (self.state_value.load(.monotonic) != .running) {
            self.lifecycle_lock.unlock(self.io);
            return;
        }
        if (failure != .none) self.reader_failure.store(failure, .monotonic);
        self.state_value.store(state_value, .release);
        self.lifecycle_lock.unlock(self.io);
        self.notify();
    }

    fn notify(self: *Terminal) void {
        const previous = self.wake_generation.fetchAdd(1, .acq_rel);
        if (previous == std.math.maxInt(u64)) @panic("terminal wake generation exhausted");
        if (self.wake_consumed.load(.acquire) == previous) self.announceWake(previous + 1);
    }

    fn acknowledgeWake(self: *Terminal, observed: u64) void {
        self.wake_consumed.store(observed, .release);
        const published = self.wake_generation.load(.acquire);
        if (published != observed) self.announceWake(published);
    }

    fn announceWake(self: *Terminal, generation: u64) void {
        var announced = self.wake_announced.load(.acquire);
        while (announced < generation) {
            announced = self.wake_announced.cmpxchgWeak(
                announced,
                generation,
                .acq_rel,
                .acquire,
            ) orelse {
                self.wake.notify(self.wake.context);
                return;
            };
        }
    }

    fn stopAfterResizeRollbackFailure(self: *Terminal) void {
        self.lifecycle_lock.lockUncancelable(self.io);
        if (self.state_value.load(.monotonic) == .running) {
            self.resize_rollback_failed.store(true, .monotonic);
            self.state_value.store(.failed, .release);
        }
        self.lifecycle_lock.unlock(self.io);
        self.transport.cancel();
    }

    fn retainReplyTransferFailure(
        self: *Terminal,
        transferred: usize,
        reason: howl_pty.TransferFailure,
    ) ReaderError {
        self.reply_failure_transferred.store(transferred, .release);
        return switch (reason) {
            .canceled => error.PtyReplyCanceled,
            .child_closed, .not_started => error.PtyReplyChildClosed,
            .timeout => error.PtyReplyTimedOut,
            .wait_failed => error.PtyReplyWaitFailed,
            .write_failed => error.PtyReplyWriteFailed,
        };
    }
};

fn validateSize(cols: u16, rows: u16) error{InvalidDimensions}!void {
    if (cols == 0 or rows == 0 or cols > max_cols or rows > max_rows) {
        return error.InvalidDimensions;
    }
}

fn readerFailure(failure: ReaderError) ReaderFailure {
    return switch (failure) {
        error.ConsequenceLimit => .consequence_limit,
        error.ModelAllocationFailed => .model_allocation_failed,
        error.ParsedEventLimit => .parsed_event_limit,
        error.PtyReadFailed => .pty_read_failed,
        error.PtyReplyCanceled => .pty_reply_canceled,
        error.PtyReplyChildClosed => .pty_reply_child_closed,
        error.PtyReplyTimedOut => .pty_reply_timed_out,
        error.PtyReplyWaitFailed => .pty_reply_wait_failed,
        error.PtyReplyWriteFailed => .pty_reply_write_failed,
        error.PtyWaitFailed => .pty_wait_failed,
        error.ReplyAllocationFailed => .reply_allocation_failed,
        error.StringControlLimit => .string_control_limit,
    };
}

fn decodeReaderFailure(failure: ReaderFailure) ?ReaderError {
    return switch (failure) {
        .none => null,
        .consequence_limit => error.ConsequenceLimit,
        .model_allocation_failed => error.ModelAllocationFailed,
        .parsed_event_limit => error.ParsedEventLimit,
        .pty_read_failed => error.PtyReadFailed,
        .pty_reply_canceled => error.PtyReplyCanceled,
        .pty_reply_child_closed => error.PtyReplyChildClosed,
        .pty_reply_timed_out => error.PtyReplyTimedOut,
        .pty_reply_wait_failed => error.PtyReplyWaitFailed,
        .pty_reply_write_failed => error.PtyReplyWriteFailed,
        .pty_wait_failed => error.PtyWaitFailed,
        .reply_allocation_failed => error.ReplyAllocationFailed,
        .string_control_limit => error.StringControlLimit,
    };
}

fn replyFailureTransferred(failure: ?ReaderError, transferred: usize) ?usize {
    return if (failure) |reader_error| switch (reader_error) {
        error.PtyReplyCanceled,
        error.PtyReplyChildClosed,
        error.PtyReplyTimedOut,
        error.PtyReplyWaitFailed,
        error.PtyReplyWriteFailed,
        => transferred,
        else => null,
    } else null;
}

fn ignoreWake(_: ?*anyopaque) void {}

test "bounds reject invalid terminal ownership" {
    try std.testing.expectError(error.InvalidDimensions, validateSize(0, 24));
    try std.testing.expectError(error.InvalidDimensions, validateSize(80, 0));
    try std.testing.expectError(error.InvalidDimensions, validateSize(max_cols + 1, 24));
    try std.testing.expectError(error.InvalidDimensions, validateSize(80, max_rows + 1));
}

test "reader allocation failures preserve their owner boundary" {
    try std.testing.expectEqual(
        ReaderFailure.model_allocation_failed,
        readerFailure(error.ModelAllocationFailed),
    );
    try std.testing.expectEqual(
        ReaderFailure.reply_allocation_failed,
        readerFailure(error.ReplyAllocationFailed),
    );
    try std.testing.expectEqual(
        @as(?ReaderError, error.ModelAllocationFailed),
        decodeReaderFailure(.model_allocation_failed),
    );
    try std.testing.expectEqual(
        @as(?ReaderError, error.ReplyAllocationFailed),
        decodeReaderFailure(.reply_allocation_failed),
    );
}

test "reply failure evidence distinguishes rejection from an accepted prefix" {
    try std.testing.expectEqual(
        @as(?usize, 0),
        replyFailureTransferred(error.PtyReplyTimedOut, 0),
    );
    try std.testing.expectEqual(
        @as(?usize, 7),
        replyFailureTransferred(error.PtyReplyWriteFailed, 7),
    );
    try std.testing.expectEqual(
        @as(?usize, null),
        replyFailureTransferred(error.ReplyAllocationFailed, 7),
    );

    const terminal = try Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "sleep 30" },
        .{},
    );
    defer terminal.deinit();
    const rejected = terminal.retainReplyTransferFailure(0, .timeout);
    terminal.finish(.failed, readerFailure(rejected));
    try std.testing.expectEqual(
        @as(?usize, 0),
        terminal.status().reply_failure_transferred,
    );

    const partial_terminal = try Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "sleep 30" },
        .{},
    );
    defer partial_terminal.deinit();
    const partial = partial_terminal.retainReplyTransferFailure(7, .write_failed);
    partial_terminal.finish(.failed, readerFailure(partial));
    try std.testing.expectEqual(
        @as(?usize, 7),
        partial_terminal.status().reply_failure_transferred,
    );
}

test "cancellation remains terminal after a prepared reader failure" {
    const terminal = try Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "sleep 30" },
        .{},
    );
    defer terminal.deinit();

    const prepared = terminal.retainReplyTransferFailure(7, .write_failed);
    terminal.cancel();
    terminal.finish(.failed, readerFailure(prepared));
    const status_value = terminal.status();
    try std.testing.expectEqual(State.stopped, status_value.state);
    try std.testing.expectEqual(@as(?ReaderError, null), status_value.reader_error);
    try std.testing.expectEqual(@as(?usize, null), status_value.reply_failure_transferred);
    try std.testing.expect(!status_value.resize_rollback_failed);
}

test "wake mutation between observation and acknowledgement is announced" {
    var wake_count: std.atomic.Value(u32) = .init(0);
    const terminal = try Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "sleep 30" },
        .{ .context = &wake_count, .notify = countTestWake },
    );
    defer terminal.deinit();

    terminal.notify();
    try std.testing.expectEqual(@as(u32, 1), wake_count.load(.acquire));
    const observed = terminal.wake_generation.load(.acquire);

    terminal.notify();
    try std.testing.expectEqual(@as(u32, 1), wake_count.load(.acquire));
    terminal.acknowledgeWake(observed);
    try std.testing.expectEqual(@as(u32, 2), wake_count.load(.acquire));
    try std.testing.expectEqual(terminal.wake_generation.load(.acquire), terminal.wake_announced.load(.acquire));
}

test "resize rollback failure transition stops progress and preserves cleanup control" {
    const terminal = try Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "sleep 30" },
        .{},
    );
    defer terminal.deinit();

    terminal.stopAfterResizeRollbackFailure();
    terminal.notify();
    try std.testing.expectEqual(State.failed, terminal.state());
    try std.testing.expect(terminal.status().resize_rollback_failed);
    try std.testing.expectError(error.NotStarted, terminal.resize(81, 24));
    const transfer = try terminal.send(.{ .bytes = "ignored" });
    try std.testing.expectEqual(@as(usize, 0), transfer.transferred());
    switch (transfer) {
        .complete => return error.UnexpectedCompleteTransfer,
        .incomplete => |failure| try std.testing.expectEqual(
            howl_pty.TransferFailure.not_started,
            failure.reason,
        ),
    }
    try std.testing.expectEqual(ControlResult.delivered, terminal.control(.interrupt));
}

fn countTestWake(context: ?*anyopaque) void {
    const count: *std.atomic.Value(u32) = @ptrCast(@alignCast(context.?));
    const previous = count.fetchAdd(1, .monotonic);
    std.debug.assert(previous < std.math.maxInt(u32));
}
