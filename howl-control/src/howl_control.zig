//! Composes one PTY child, VT model, and optional local control endpoint.

const builtin = @import("builtin");
const std = @import("std");
const howl_pty = @import("howl_pty");
const howl_vt = @import("howl_vt");
const client = @import("client.zig");
const net = std.Io.net;
const posix = std.posix;
const linux = std.os.linux;

// Curated remote and embedded terminal values.

/// Identifies one process-lifetime terminal and its canonical local endpoint.
pub const TerminalId = client.TerminalId;
/// Names Howl's endpoint directory beneath the process runtime directory.
pub const endpoint_directory = client.endpoint_directory;
/// Bounds one exact remote input batch before transport or PTY transfer.
pub const max_input_bytes = client.max_input_bytes;
/// Bounds one copied remote viewport response.
pub const max_screen_bytes = client.max_screen_bytes;
/// Bounds events admitted by one remote input batch.
pub const max_send_events = client.max_send_events;
/// Bounds delay before one remote input event.
pub const max_event_delay_ms = client.max_event_delay_ms;
/// Bounds total scheduled delay held by one remote input batch.
pub const max_batch_delay_ms = client.max_batch_delay_ms;
/// Uses Howl VT's host-neutral input vocabulary for local and remote calls.
pub const Input = client.Input;
/// Sends typed one-shot requests to one local Howl terminal endpoint.
pub const Client = client.Client;
/// Reports exact local construction, transport, decode, or remote rejection failure.
pub const ClientError = client.ClientError;
/// Owns one decoded remote status and its optional copied launch directory.
pub const ClientStatus = client.ClientStatus;
/// Retains one admitted input event and its bounded delay.
pub const BatchEvent = client.BatchEvent;
/// Retains one admitted batch's complete, partial, or rejected outcome.
pub const SendResult = client.SendResult;
/// Names exact preparation failure after remote mutation admission.
pub const SendFailure = client.SendFailure;
/// Retains complete, partial, or rejected remote input evidence.
pub const SendOutcome = client.SendOutcome;
/// Retains one admitted resize and the resulting geometry sequence.
pub const ResizeResult = client.ResizeResult;
/// Retains one admitted signal and its exact native outcome.
pub const SignalResult = client.SignalResult;
/// Owns one bounded remote viewport text observation.
pub const Screen = client.Screen;
/// Copies coherent lifecycle, geometry, sequence, and output facts.
pub const Status = client.Status;
/// Copies one nonzero host-provided terminal cell extent in logical pixels.
pub const CellPixelSize = howl_vt.Terminal.CellPixelSize;

// Construction bounds, copied observations, and exact failures.

/// Copies retained-history projection and terminal mouse-routing facts.
pub const ViewportFacts = struct {
    /// Identifies the oldest retained projected primary row.
    history_row_base: u32 = 0,
    /// Reports retained projected primary rows.
    history_count: u32 = 0,
    /// Reports the applied host-requested offset.
    offset: u32 = 0,
    /// Reports current visible rows.
    rows: u16 = 1,
    /// Reports whether the alternate screen is active.
    alternate_screen: bool = false,
    /// Reports whether terminal mouse tracking owns pointer input.
    mouse_reporting: bool = false,
};

/// Bounds one terminal surface width before model or PTY construction.
pub const max_cols = client.max_cols;
/// Bounds one terminal surface height before model or PTY construction.
pub const max_rows = client.max_rows;
/// Bounds retained semantic history independently from the active surface.
pub const max_history_rows = client.max_history_rows;
/// Bounds each complete input or terminal-reply transfer.
pub const max_transfer_bytes = client.max_transfer_bytes;
const transport_buffer_bytes: usize = 4096;
const default_transfer_timeout_ms: u32 = 2000;

/// Supplies copied child launch values and bounded terminal dimensions.
pub const Config = struct {
    /// Enables one local endpoint beneath this absolute runtime directory.
    runtime_dir: ?[]const u8 = null,
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
    /// Supplies fixed nonzero cell pixels for terminal reports and mouse input.
    cell_pixels: ?CellPixelSize = null,
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
    std.Thread.SpawnError || net.UnixAddress.InitError || net.UnixAddress.ListenError || error{
    InvalidDimensions,
    InvalidHistory,
    InvalidTransferTimeout,
    RuntimeDirectoryInvalid,
    RuntimeDirectoryCreateFailed,
    RuntimeDirectoryPermissionFailed,
    EndpointPermissionFailed,
    EndpointPathTooLong,
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
pub const InputError = client.InputError;
const InputTransfer = client.InputTransfer;
/// Uses Howl VT's bounded finalized-output copy and cursor outcomes.
pub const LogicalOutputResult = client.LogicalOutputResult;
/// Reports invalid output-copy limits or allocation failure.
pub const LogicalOutputError = client.LogicalOutputError;
/// Bounds one retained finalized logical line.
pub const logical_output_line_max_bytes = howl_vt.Terminal.logical_output_line_max_bytes;
/// Bounds aggregate retained output and one complete logical-output result.
pub const logical_output_max_bytes = howl_vt.Terminal.logical_output_max_bytes;
/// Selects one supported signal for the owned child process group.
pub const ControlSignal = client.ControlSignal;
/// Reports exact child probing and process-group signal outcomes.
pub const ControlResult = client.ControlResult;

/// Reports a resize rejected by the model or native PTY.
pub const ResizeError = client.ResizeError;
/// Reports the exact terminal-reader boundary that stopped making progress.
pub const ReaderError = client.ReaderError;
/// Distinguishes active terminal progress from completion or an exact failed boundary.
pub const State = client.State;
/// Matches the VT owner's maximum retained bytes for one OSC 133 mark.
pub const shell_mark_metadata_max_bytes = howl_vt.Terminal.shell_mark_metadata_max_bytes;
/// Matches the VT owner's maximum retained shell-integration identity.
pub const shell_name_max_bytes = howl_vt.Terminal.shell_name_max_bytes;

comptime {
    std.debug.assert(shell_mark_metadata_max_bytes <= std.math.maxInt(u16));
    std.debug.assert(shell_name_max_bytes <= std.math.maxInt(u8));
}

/// Copies the latest real OSC 133 mark and retained shell identity.
pub const ShellMark = client.ShellMark;

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

/// Owns one PTY child, reader thread, terminal model, and wake lifecycle.
/// The embedder serializes `deinit` against public calls.
pub const Terminal = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    transport: howl_pty.Owned,
    model: howl_vt.Terminal,
    reader: std.Thread,
    terminal_id: TerminalId,
    endpoint_path: ?[]u8,
    server: net.Server,
    control_thread: std.Thread,
    endpoint_enabled: bool,
    // Nested acquisition is admission before model, viewport, or lifecycle
    // state. PTY writes begin only after the model lock is
    // released; the active-peer lock never nests with terminal state locks.
    admission_lock: std.Io.Mutex = .init,
    peer_lock: std.Io.Mutex = .init,
    input_sequence: std.atomic.Value(u64) = .init(0),
    stopping: std.atomic.Value(bool) = .init(false),
    active_peer: posix.fd_t = -1,
    child_cwd: ?[]u8,
    admission_sequence: u64 = 0,
    geometry_sequence: u64 = 0,
    // This brief lock publishes coherent viewport facts without exposing the
    // model lock to callers.
    viewport_lock: std.Io.Mutex = .init,
    viewport_facts: ViewportFacts = .{},
    lock: std.Io.Mutex = .init,
    write_lock: std.Io.Mutex = .init,
    // Lifecycle state stays independent from the model lock used by snapshots.
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
    cell_pixels: ?CellPixelSize,
    transfer_timeout_ms: u32,

    // Construction and externally serialized teardown.

    /// Constructs every PTY, VT, endpoint, and reader resource before return.
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
        if (config.cell_pixels) |pixels|
            model.setCellPixelSize(pixels.width, pixels.height) catch return error.InvalidDimensions;
        transport.start(config.cols, config.rows) catch |failure| switch (failure) {
            error.AlreadyStarted => @panic("fresh PTY owner reported already started"),
            else => |expected| return expected,
        };

        const terminal_id = TerminalId.random(io);
        var endpoint_path: ?[]u8 = null;
        errdefer if (endpoint_path) |path| allocator.free(path);
        var server: net.Server = undefined;
        var endpoint_enabled = false;
        errdefer if (endpoint_enabled) server.deinit(io);
        errdefer if (endpoint_enabled) std.Io.Dir.deleteFileAbsolute(io, endpoint_path.?) catch
            @panic("terminal init rollback could not unlink its endpoint");
        if (config.runtime_dir) |runtime_dir| {
            if (builtin.os.tag != .linux) return error.UnsupportedPlatform;
            if (!std.fs.path.isAbsolute(runtime_dir)) return error.RuntimeDirectoryInvalid;
            const directory = try std.fs.path.join(
                allocator,
                &.{ runtime_dir, endpoint_directory },
            );
            defer allocator.free(directory);
            std.Io.Dir.createDirPath(.cwd(), io, directory) catch
                return error.RuntimeDirectoryCreateFailed;
            std.Io.Dir.cwd().setFilePermissions(
                io,
                directory,
                .fromMode(0o700),
                .{},
            ) catch return error.RuntimeDirectoryPermissionFailed;
            var filename: [37]u8 = undefined;
            endpoint_path = try std.fs.path.join(
                allocator,
                &.{ directory, terminal_id.formatEndpoint(&filename) },
            );
            if (endpoint_path.?.len >= net.UnixAddress.max_len) {
                return error.EndpointPathTooLong;
            }
            const address = try net.UnixAddress.init(endpoint_path.?);
            server = try address.listen(io, .{ .kernel_backlog = 4 });
            endpoint_enabled = true;
            std.Io.Dir.cwd().setFilePermissions(
                io,
                endpoint_path.?,
                .fromMode(0o600),
                .{},
            ) catch return error.EndpointPermissionFailed;
        }

        const child_cwd = if (config.cwd) |cwd| try allocator.dupe(u8, cwd) else null;
        errdefer if (child_cwd) |cwd| allocator.free(cwd);

        const self = try allocator.create(Terminal);
        errdefer allocator.destroy(self);
        self.* = .{
            .allocator = allocator,
            .io = io,
            .transport = transport,
            .model = model,
            .reader = undefined,
            .terminal_id = terminal_id,
            .endpoint_path = endpoint_path,
            .server = server,
            .control_thread = undefined,
            .endpoint_enabled = endpoint_enabled,
            .child_cwd = child_cwd,
            .wake = wake,
            .cols = config.cols,
            .rows = config.rows,
            .cell_pixels = config.cell_pixels,
            .transfer_timeout_ms = config.transfer_timeout_ms,
        };
        self.storeViewportFacts(viewportFactsFrom(&self.model));
        self.reader = try .spawn(.{}, readLoop, .{self});
        errdefer {
            self.cancel();
            self.reader.join();
        }
        if (endpoint_enabled) self.control_thread = try .spawn(.{}, controlLoop, .{self});
        return self;
    }

    /// Stops the reader and child before releasing model and allocation ownership.
    pub fn deinit(self: *Terminal) void {
        self.cancel();
        self.stopping.store(true, .release);
        if (self.endpoint_enabled) {
            client.shutdownSocket(self.server.socket.handle);
            self.peer_lock.lockUncancelable(self.io);
            if (self.active_peer >= 0) client.shutdownSocket(self.active_peer);
            self.peer_lock.unlock(self.io);
            self.control_thread.join();
            self.server.deinit(self.io);
            std.Io.Dir.deleteFileAbsolute(self.io, self.endpoint_path.?) catch |failure| switch (failure) {
                error.FileNotFound => {},
                else => @panic("owned terminal endpoint unlink failed"),
            };
        }
        self.reader.join();
        self.transport.deinit();
        self.model.deinit();
        const allocator = self.allocator;
        if (self.child_cwd) |cwd| allocator.free(cwd);
        if (self.endpoint_path) |path| allocator.free(path);
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

    /// Returns the stable identity carried by direct and endpoint operations.
    pub fn id(self: *const Terminal) TerminalId {
        return self.terminal_id;
    }

    /// Borrows the endpoint path when local control was enabled at construction.
    pub fn endpoint(self: *const Terminal) ?[]const u8 {
        return self.endpoint_path;
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

    // Admitted input, geometry, output, status, and process control.

    /// Admits one bounded delayed event batch as one ordered mutation.
    pub fn send(self: *Terminal, events: []const BatchEvent) InputError!SendResult {
        if (events.len == 0 or events.len > max_send_events) return error.InputLimit;
        try client.validateBatchBound(events);
        self.admission_lock.lockUncancelable(self.io);
        defer self.admission_lock.unlock(self.io);
        for (events) |event| if (!inputGeometryValid(
            event.input,
            self.cols,
            self.rows,
            self.cell_pixels,
        )) return .{
            .admission_sequence = self.admission_sequence,
            .input_sequence = self.input_sequence.load(.acquire),
            .completed_events = 0,
            .outcome = .{ .rejected = .{ .transferred = 0, .reason = .invalid_geometry } },
        };
        const admission = self.nextAdmission();
        var transferred: usize = 0;
        for (events, 0..) |event, index| {
            if (self.delay(event.delay_ms)) |failure| return .{
                .admission_sequence = admission,
                .input_sequence = self.input_sequence.load(.acquire),
                .completed_events = @intCast(index),
                .outcome = .{ .rejected = .{ .transferred = transferred, .reason = failure } },
            };
            const event_transfer = self.transferInput(event.input) catch |failure| return .{
                .admission_sequence = admission,
                .input_sequence = self.input_sequence.load(.acquire),
                .completed_events = @intCast(index),
                .outcome = .{ .rejected = .{
                    .transferred = transferred,
                    .reason = client.sendFailure(failure),
                } },
            };
            switch (event_transfer) {
                .complete => |count| {
                    transferred = std.math.add(usize, transferred, count) catch
                        @panic("validated terminal batch transfer overflowed");
                    std.debug.assert(transferred <= max_input_bytes);
                },
                .incomplete => |failure| {
                    const partial = std.math.add(usize, transferred, failure.transferred) catch
                        @panic("validated terminal batch partial transfer overflowed");
                    std.debug.assert(partial <= max_input_bytes);
                    return .{
                        .admission_sequence = admission,
                        .input_sequence = self.input_sequence.load(.acquire),
                        .completed_events = @intCast(index),
                        .outcome = .{ .incomplete = .{
                            .transferred = partial,
                            .reason = failure.reason,
                        } },
                    };
                },
            }
        }
        return .{
            .admission_sequence = admission,
            .input_sequence = incrementSequence(&self.input_sequence),
            .completed_events = @intCast(events.len),
            .outcome = .{ .complete = transferred },
        };
    }

    /// Encodes one input event and retains complete or partial PTY transfer truth.
    fn transferInput(self: *Terminal, event: Input) InputError!InputTransfer {
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

    /// Admits one resize and advances geometry only after an actual change.
    pub fn resize(self: *Terminal, cols: u16, rows: u16) ResizeError!ResizeResult {
        self.admission_lock.lockUncancelable(self.io);
        defer self.admission_lock.unlock(self.io);
        const admission = self.nextAdmission();
        const changed = try self.resizeModel(cols, rows);
        return .{
            .admission_sequence = admission,
            .geometry_sequence = self.geometry_sequence,
            .changed = changed,
            .cols = cols,
            .rows = rows,
        };
    }

    /// Applies one bounded size and reports whether terminal geometry changed.
    fn resizeModel(self: *Terminal, cols: u16, rows: u16) ResizeError!bool {
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
        self.geometry_sequence = nextSequence(self.geometry_sequence);
        self.storeViewportFacts(viewportFactsFrom(&self.model));
        return true;
    }

    /// Copies bounded finalized primary output from one cursor.
    pub fn output(
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

    /// Copies coherent lifecycle, geometry, ordering, and output facts.
    pub fn status(self: *Terminal) Status {
        self.admission_lock.lockUncancelable(self.io);
        defer self.admission_lock.unlock(self.io);
        self.lock.lockUncancelable(self.io);
        defer self.lock.unlock(self.io);
        self.lifecycle_lock.lockUncancelable(self.io);
        defer self.lifecycle_lock.unlock(self.io);
        const snapshot = self.model.stateSnapshot();
        const output_range = self.model.logicalOutputRange();
        var shell_mark: ?ShellMark = null;
        if (snapshot.shell_mark.generation != 0) {
            var mark = ShellMark{
                .generation = snapshot.shell_mark.generation,
                .kind = snapshot.shell_mark.kind,
                .status = snapshot.shell_mark.status,
                .metadata = @splat(0),
                .metadata_len = @intCast(snapshot.shell_mark.metadata.len),
                .shell = @splat(0),
                .shell_len = 0,
            };
            @memcpy(mark.metadata[0..mark.metadata_len], snapshot.shell_mark.metadata);
            if (snapshot.shell_integration) |integration| if (integration.shell) |shell| {
                mark.shell_len = @intCast(shell.len);
                @memcpy(mark.shell[0..mark.shell_len], shell);
            };
            shell_mark = mark;
        }
        const reader_error = decodeReaderFailure(self.reader_failure.load(.monotonic));
        return .{
            .terminal_id = self.terminal_id,
            .state = self.state_value.load(.monotonic),
            .reader_error = reader_error,
            .reply_failure_transferred = replyFailureTransferred(
                reader_error,
                self.reply_failure_transferred.load(.monotonic),
            ),
            .resize_rollback_failed = self.resize_rollback_failed.load(.monotonic),
            .child_cwd = self.child_cwd,
            .cols = self.cols,
            .rows = self.rows,
            .history_loss_generation = snapshot.history_loss_generation,
            .alternate_screen = snapshot.is_alternate_screen,
            .admission_sequence = self.admission_sequence,
            .input_sequence = self.input_sequence.load(.acquire),
            .geometry_sequence = self.geometry_sequence,
            .output_oldest = output_range.oldest,
            .output_newest = output_range.newest,
            .shell_mark = shell_mark,
        };
    }

    /// Copies the current bounded viewport without retaining model borrows.
    pub fn screen(
        self: *Terminal,
        allocator: std.mem.Allocator,
    ) (std.mem.Allocator.Error || error{ScreenLimit})!Screen {
        var bytes = try allocator.alloc(u8, max_screen_bytes);
        errdefer allocator.free(bytes);
        self.lock.lockUncancelable(self.io);
        defer self.lock.unlock(self.io);
        const visual = self.model.visualView();
        const view = visual.view;
        var writer = std.Io.Writer.fixed(bytes);
        for (0..view.rows) |row_value| {
            const row: u16 = @intCast(row_value);
            var end = view.cols;
            while (end > 0) {
                const codepoint = view.cellAt(row, end - 1);
                if (codepoint != 0 and codepoint != ' ') break;
                end -= 1;
            }
            for (0..end) |col_value| {
                const codepoint = view.cellAt(row, @intCast(col_value));
                writer.printUnicodeCodepoint(if (codepoint == 0) ' ' else codepoint) catch
                    return error.ScreenLimit;
            }
            if (row_value + 1 < view.rows) writer.writeByte('\n') catch
                return error.ScreenLimit;
        }
        bytes = try allocator.realloc(bytes, writer.buffered().len);
        return .{
            .allocator = allocator,
            .text = bytes,
            .cols = view.cols,
            .rows = view.rows,
            .alternate_screen = view.is_alternate_screen,
            .cursor_visible = view.cursor_visible,
            .cursor_col = view.cursor_col,
            .cursor_row = view.cursor_row,
        };
    }

    /// Admits one process-group signal and returns its exact native outcome.
    /// Process-group control remains available after terminal progress fails.
    pub fn signal(self: *Terminal, signal_value: ControlSignal) SignalResult {
        self.admission_lock.lockUncancelable(self.io);
        defer self.admission_lock.unlock(self.io);
        self.write_lock.lockUncancelable(self.io);
        defer self.write_lock.unlock(self.io);
        return .{
            .admission_sequence = self.nextAdmission(),
            .signal = signal_value,
            .outcome = self.transport.control(signal_value),
        };
    }

    fn nextAdmission(self: *Terminal) u64 {
        self.admission_sequence = nextSequence(self.admission_sequence);
        return self.admission_sequence;
    }

    fn delay(self: *Terminal, delay_ms: u16) ?SendFailure {
        if (delay_ms == 0) return null;
        var remaining = delay_ms;
        while (remaining != 0) {
            if (self.stopping.load(.acquire)) return .delay_shutdown;
            if (self.state() != .running) return .delay_terminal_closed;
            const slice_ms: u16 = @min(remaining, 10);
            (std.Io.Clock.Duration{
                .raw = .fromMilliseconds(slice_ms),
                .clock = .awake,
            }).sleep(self.io) catch return .delay_canceled;
            remaining -= slice_ms;
        }
        if (self.stopping.load(.acquire)) return .delay_shutdown;
        if (self.state() != .running) return .delay_terminal_closed;
        return null;
    }

    fn inputGeometryValid(
        input: Input,
        cols: u16,
        rows: u16,
        cell_pixels: ?CellPixelSize,
    ) bool {
        const mouse = switch (input) {
            .mouse => |mouse| mouse,
            else => return true,
        };
        if (mouse.row < 0 or mouse.row >= rows or mouse.col >= cols or
            mouse.buttons_down & ~@as(u8, 0b111) != 0 or
            (mouse.pixel_x == null) != (mouse.pixel_y == null)) return false;
        if (mouse.pixel_x) |x| {
            const pixels = cell_pixels orelse return false;
            if (@as(u64, x) >= @as(u64, cols) * pixels.width or
                @as(u64, mouse.pixel_y.?) >= @as(u64, rows) * pixels.height) return false;
        }
        return switch (mouse.kind) {
            .press => mouseButtonDown(mouse.button, mouse.buttons_down) orelse false,
            .release => if (mouseButtonDown(mouse.button, mouse.buttons_down)) |down| !down else false,
            .wheel => mouse.button == .wheel_up or mouse.button == .wheel_down,
            .move => mouse.button == .none,
        };
    }

    fn mouseButtonDown(button: @FieldType(@FieldType(Input, "mouse"), "button"), buttons: u8) ?bool {
        const mask: u8 = switch (button) {
            .left => 0b001,
            .middle => 0b010,
            .right => 0b100,
            else => return null,
        };
        return buttons & mask != 0;
    }

    // Viewport facts, reader progress, and wake delivery.

    /// Copies the current bounded viewport facts without walking terminal cells.
    pub fn viewportFacts(self: *Terminal) ViewportFacts {
        self.viewport_lock.lockUncancelable(self.io);
        defer self.viewport_lock.unlock(self.io);
        return self.viewport_facts;
    }

    /// Applies one absolute host viewport offset and announces actual change.
    pub fn setViewport(self: *Terminal, offset: u32) ViewportFacts {
        self.lock.lockUncancelable(self.io);
        if (self.state_value.load(.acquire) != .running) {
            const facts = viewportFactsFrom(&self.model);
            self.lock.unlock(self.io);
            return facts;
        }
        const changed = self.model.scrollViewport(.{ .absolute = offset });
        const facts = viewportFactsFrom(&self.model);
        self.storeViewportFacts(facts);
        self.lock.unlock(self.io);
        if (changed) self.notify();
        return facts;
    }

    fn storeViewportFacts(self: *Terminal, facts: ViewportFacts) void {
        self.viewport_lock.lockUncancelable(self.io);
        self.viewport_facts = facts;
        self.viewport_lock.unlock(self.io);
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
        if (summary.state_changed or summary.history_lost)
            self.storeViewportFacts(viewportFactsFrom(&self.model));
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

    // One-shot endpoint admission and primitive execution.

    fn controlLoop(self: *Terminal) void {
        while (!self.stopping.load(.acquire)) {
            var peer = self.server.accept(self.io) catch |failure| switch (failure) {
                error.SocketNotListening, error.Canceled => return,
                error.ConnectionAborted, error.WouldBlock => continue,
                else => {
                    self.stopping.store(true, .release);
                    client.shutdownSocket(self.server.socket.handle);
                    return;
                },
            };
            client.setNonblocking(peer.socket.handle) catch {
                peer.close(self.io);
                self.stopping.store(true, .release);
                client.shutdownSocket(self.server.socket.handle);
                return;
            };
            self.peer_lock.lockUncancelable(self.io);
            if (self.stopping.load(.acquire)) {
                peer.close(self.io);
                self.peer_lock.unlock(self.io);
                return;
            }
            self.active_peer = peer.socket.handle;
            self.peer_lock.unlock(self.io);
            self.handlePeer(&peer);
            self.peer_lock.lockUncancelable(self.io);
            self.active_peer = -1;
            peer.close(self.io);
            self.peer_lock.unlock(self.io);
        }
    }

    fn handlePeer(self: *Terminal, peer: *net.Stream) void {
        if (!client.admitUid(linux.geteuid(), client.peerUid(peer.socket.handle) catch null)) {
            client.writeFailure(self.io, peer, self.terminal_id, null, .unauthorized) catch {};
            return;
        }
        const started = std.Io.Clock.awake.now(self.io);
        var header: [client.request_header_bytes]u8 = undefined;
        client.readExact(
            self.io,
            peer.socket.handle,
            &header,
            started,
            client.admission_timeout_ms,
        ) catch {
            client.writeFailure(self.io, peer, self.terminal_id, null, .truncated) catch {};
            return;
        };
        const request = client.decodeRequestHeader(&header) catch |failure| {
            client.writeFailure(
                self.io,
                peer,
                self.terminal_id,
                null,
                requestFailureStatus(failure),
            ) catch {};
            return;
        };
        if (!std.mem.eql(u8, &request.terminal_id.bytes, &self.terminal_id.bytes)) {
            client.writeFailure(
                self.io,
                peer,
                self.terminal_id,
                request.operation,
                .wrong_terminal,
            ) catch {};
            return;
        }
        var payload: [client.max_request_bytes]u8 = undefined;
        const body = payload[0..request.payload_len];
        client.readExact(
            self.io,
            peer.socket.handle,
            body,
            started,
            client.admission_timeout_ms,
        ) catch {
            client.writeFailure(
                self.io,
                peer,
                self.terminal_id,
                request.operation,
                .truncated,
            ) catch {};
            return;
        };
        self.execute(peer, request.operation, body) catch |failure| {
            client.writeFailure(
                self.io,
                peer,
                self.terminal_id,
                request.operation,
                operationFailureStatus(failure),
            ) catch {};
        };
    }

    fn execute(
        self: *Terminal,
        peer: *net.Stream,
        operation: client.Operation,
        payload: []const u8,
    ) OperationError!void {
        switch (operation) {
            .status => {
                if (payload.len != 0) return error.InvalidPayload;
                const encoded = try client.encodeStatus(self.allocator, self.status());
                defer self.allocator.free(encoded);
                client.writeResponse(self.io, peer, .{
                    .operation = .status,
                    .terminal_id = self.terminal_id,
                    .payload = encoded,
                }) catch return error.ResponseWriteFailed;
            },
            .send => {
                if (payload.len == 0) return error.InvalidPayload;
                var batch = try client.decodeBatch(self.allocator, payload);
                defer batch.deinit();
                const encoded = client.encodeSendResult(try self.send(batch.events));
                client.writeResponse(self.io, peer, .{
                    .operation = .send,
                    .terminal_id = self.terminal_id,
                    .payload = &encoded,
                }) catch return error.ResponseWriteFailed;
            },
            .screen => {
                if (payload.len != 0) return error.InvalidPayload;
                var value = try self.screen(self.allocator);
                defer value.deinit();
                const encoded = try client.encodeScreen(self.allocator, &value);
                defer self.allocator.free(encoded);
                client.writeResponse(self.io, peer, .{
                    .operation = .screen,
                    .terminal_id = self.terminal_id,
                    .payload = encoded,
                }) catch return error.ResponseWriteFailed;
            },
            .output => {
                if (payload.len != 14) return error.InvalidPayload;
                var result = try self.output(
                    self.allocator,
                    std.mem.readInt(u64, payload[0..8], .big),
                    std.mem.readInt(u16, payload[8..10], .big),
                    std.mem.readInt(u32, payload[10..14], .big),
                );
                defer switch (result) {
                    .output => |*value| value.deinit(),
                    else => {},
                };
                const encoded = try client.encodeOutputResult(self.allocator, &result);
                defer self.allocator.free(encoded);
                client.writeResponse(self.io, peer, .{
                    .operation = .output,
                    .terminal_id = self.terminal_id,
                    .payload = encoded,
                }) catch return error.ResponseWriteFailed;
            },
            .resize => {
                if (payload.len != 4) return error.InvalidPayload;
                const result = try self.resize(
                    std.mem.readInt(u16, payload[0..2], .big),
                    std.mem.readInt(u16, payload[2..4], .big),
                );
                var encoded: [21]u8 = @splat(0);
                std.mem.writeInt(u64, encoded[0..8], result.admission_sequence, .big);
                std.mem.writeInt(u64, encoded[8..16], result.geometry_sequence, .big);
                encoded[16] = @intFromBool(result.changed);
                std.mem.writeInt(u16, encoded[17..19], result.cols, .big);
                std.mem.writeInt(u16, encoded[19..21], result.rows, .big);
                client.writeResponse(self.io, peer, .{
                    .operation = .resize,
                    .terminal_id = self.terminal_id,
                    .payload = &encoded,
                }) catch return error.ResponseWriteFailed;
            },
            .signal => {
                if (payload.len != 1) return error.InvalidPayload;
                const signal_value: ControlSignal = switch (payload[0]) {
                    1 => .hangup,
                    2 => .interrupt,
                    15 => .terminate,
                    9 => .kill,
                    else => return error.InvalidPayload,
                };
                const result = self.signal(signal_value);
                var encoded: [10]u8 = @splat(0);
                std.mem.writeInt(u64, encoded[0..8], result.admission_sequence, .big);
                encoded[8] = payload[0];
                encoded[9] = client.encodeControlResult(result.outcome);
                client.writeResponse(self.io, peer, .{
                    .operation = .signal,
                    .terminal_id = self.terminal_id,
                    .payload = &encoded,
                }) catch return error.ResponseWriteFailed;
            },
        }
    }
};

// Exact internal failure translation and bounded sequence support.

const OperationError = InputError || LogicalOutputError || ResizeError || error{
    InvalidPayload,
    ResponseWriteFailed,
    ScreenLimit,
};

fn requestFailureStatus(failure: client.RequestError) client.ResponseStatus {
    return switch (failure) {
        error.BadMagic => .bad_magic,
        error.WrongVersion => .wrong_version,
        error.UnknownOperation => .unknown_operation,
        error.Oversized => .oversized,
        error.InvalidPayload => .invalid_payload,
    };
}

fn operationFailureStatus(failure: OperationError) client.ResponseStatus {
    return switch (failure) {
        error.InvalidPayload, error.InvalidLimit, error.InvalidDimensions => .invalid_payload,
        error.InputLimit => .input_limit,
        error.InvalidUtf8 => .invalid_utf8,
        error.InvalidText => .invalid_text,
        error.KeyTextLimit => .key_text_limit,
        error.LengthOverflow => .length_overflow,
        error.OutOfMemory => .out_of_memory,
        error.ConsequenceLimit => .consequence_limit,
        error.ScreenLimit => .screen_limit,
        error.ResizeRollbackFailed => .resize_rollback_failed,
        error.NotStarted,
        error.PtyResizeFailed,
        error.ResponseWriteFailed,
        => .internal_failure,
    };
}

fn incrementSequence(sequence: *std.atomic.Value(u64)) u64 {
    const previous = sequence.fetchAdd(1, .acq_rel);
    if (previous == std.math.maxInt(u64)) @panic("terminal input sequence exhausted");
    return previous + 1;
}

fn nextSequence(sequence: u64) u64 {
    return std.math.add(u64, sequence, 1) catch @panic("terminal sequence exhausted");
}

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

fn viewportFactsFrom(model: *const howl_vt.Terminal) ViewportFacts {
    const snapshot = model.stateSnapshot();
    return .{
        .history_row_base = snapshot.history_row_base,
        .history_count = snapshot.history_count,
        .offset = snapshot.scrollback_offset,
        .rows = model.visibleMeta().rows,
        .alternate_screen = snapshot.is_alternate_screen,
        .mouse_reporting = snapshot.mouse_reporting,
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

test "host viewport operation retains history and mouse ownership facts" {
    var wake_count: std.atomic.Value(u32) = .init(0);
    const terminal = try Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "sleep 30", .rows = 3, .cols = 5, .history_rows = 8 },
        .{ .context = &wake_count, .notify = countTestWake },
    );
    defer terminal.deinit();

    try terminal.consume("1AAAA\r\n2BBBB\r\n3CCCC\r\n4DDDD");
    terminal.consumeWake();

    const wakes_before = wake_count.load(.acquire);
    const facts = terminal.setViewport(1);
    try std.testing.expectEqual(@as(u32, 1), facts.offset);
    try std.testing.expect(facts.history_count >= 1);
    try std.testing.expect(!facts.alternate_screen);
    try std.testing.expect(!facts.mouse_reporting);
    try std.testing.expectEqual(wakes_before + 1, wake_count.load(.acquire));
    try std.testing.expectEqual(facts.offset, terminal.viewportFacts().offset);

    try terminal.consume("\x1b[?1000h");
    try std.testing.expect(terminal.viewportFacts().mouse_reporting);
}

test "alternate-screen sparse mutation preserves terminal progress" {
    const terminal = try Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "sleep 30", .cols = 4, .rows = 3 },
        .{},
    );
    defer terminal.deinit();

    try terminal.consume("\x1b[?1049h");
    {
        var alternate = try terminal.screen(std.testing.allocator);
        defer alternate.deinit();
        try std.testing.expect(alternate.alternate_screen);
    }

    try terminal.consume("\x1b[1;1HA\x1b[3;4HZ");
    try std.testing.expectEqual(State.running, terminal.state());
    try std.testing.expectEqual(@as(?ReaderError, null), terminal.readerError());
    var screen = try terminal.screen(std.testing.allocator);
    defer screen.deinit();
    try std.testing.expect(std.mem.startsWith(u8, screen.text, "A"));
    try std.testing.expect(std.mem.indexOf(u8, screen.text, "Z") != null);
}

test "cell pixels bound mouse coordinates with exact button state" {
    const pixels = CellPixelSize{ .width = 8, .height = 16 };
    const terminal = try Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "sleep 30", .cols = 4, .rows = 2, .cell_pixels = pixels },
        .{},
    );
    defer terminal.deinit();

    const press: Input = .{ .mouse = .{
        .kind = .press,
        .button = .left,
        .row = 1,
        .col = 3,
        .pixel_x = 31,
        .pixel_y = 31,
        .mod = .{},
        .buttons_down = 0b001,
    } };
    try std.testing.expect(Terminal.inputGeometryValid(press, 4, 2, pixels));
    var invalid = press;
    invalid.mouse.pixel_x = 32;
    try std.testing.expect(!Terminal.inputGeometryValid(invalid, 4, 2, pixels));
    invalid = press;
    invalid.mouse.buttons_down = 0;
    try std.testing.expect(!Terminal.inputGeometryValid(invalid, 4, 2, pixels));
    invalid = press;
    invalid.mouse.pixel_y = null;
    try std.testing.expect(!Terminal.inputGeometryValid(invalid, 4, 2, pixels));

    var released = press;
    released.mouse.kind = .release;
    released.mouse.buttons_down = 0;
    try std.testing.expect(Terminal.inputGeometryValid(released, 4, 2, pixels));
}

test "zero cell pixels reject terminal construction before child launch" {
    try std.testing.expectError(error.InvalidDimensions, Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "sleep 30", .cell_pixels = .{ .width = 0, .height = 16 } },
        .{},
    ));
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
    const transfer = try terminal.send(&.{.{ .input = .{ .bytes = "ignored" } }});
    switch (transfer.outcome) {
        .complete => return error.UnexpectedCompleteTransfer,
        .incomplete => |failure| {
            try std.testing.expectEqual(@as(usize, 0), failure.transferred);
            try std.testing.expectEqual(howl_pty.TransferFailure.not_started, failure.reason);
        },
        .rejected => return error.UnexpectedRejectedTransfer,
    }
    try std.testing.expectEqual(ControlResult.delivered, terminal.signal(.interrupt).outcome);
}

test "endpoint shutdown interrupts a held partial request" {
    var random: [8]u8 = undefined;
    std.testing.io.random(&random);
    const runtime_dir = try std.fmt.allocPrint(
        std.testing.allocator,
        "/tmp/howl-control-partial-{x}",
        .{random},
    );
    defer std.testing.allocator.free(runtime_dir);
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, runtime_dir) catch {};
    const terminal = try Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .runtime_dir = runtime_dir, .command = "sleep 30" },
        .{},
    );
    const address = try net.UnixAddress.init(terminal.endpoint().?);
    var peer = try address.connect(std.testing.io);
    defer peer.close(std.testing.io);
    var buffer: [1]u8 = undefined;
    var writer = peer.writer(std.testing.io, &buffer);
    try writer.interface.writeByte('Q');
    try writer.interface.flush();
    try waitForConsumedPartialRequest(terminal);
    terminal.deinit();
}

fn waitForConsumedPartialRequest(terminal: *Terminal) !void {
    for (0..100_000) |_| {
        terminal.peer_lock.lockUncancelable(std.testing.io);
        const fd = terminal.active_peer;
        if (fd >= 0) {
            var byte: [1]u8 = undefined;
            const received = linux.recvfrom(
                fd,
                &byte,
                byte.len,
                linux.MSG.PEEK | linux.MSG.DONTWAIT,
                null,
                null,
            );
            const receive_error = linux.errno(received);
            terminal.peer_lock.unlock(std.testing.io);
            switch (receive_error) {
                .AGAIN => return,
                .SUCCESS, .INTR => {},
                else => return error.RequestReadProbeFailed,
            }
        } else {
            terminal.peer_lock.unlock(std.testing.io);
        }
        try std.Thread.yield();
    }
    return error.RequestReadPhaseNotReached;
}

fn countTestWake(context: ?*anyopaque) void {
    const count: *std.atomic.Value(u32) = @ptrCast(@alignCast(context.?));
    const previous = count.fetchAdd(1, .monotonic);
    std.debug.assert(previous < std.math.maxInt(u32));
}
