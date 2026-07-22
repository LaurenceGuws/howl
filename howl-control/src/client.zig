//! Owns Howl terminal identity, endpoint facts, private wire codec, and one-shot Linux client.

const builtin = @import("builtin");
const std = @import("std");
const howl_vt = @import("howl_vt");
const howl_pty = @import("howl_pty");

const net = std.Io.net;
const posix = std.posix;
const linux = std.os.linux;

// Protocol bounds and shared domain values.

/// Bounds one exact control input before transport or PTY transfer.
pub const max_transfer_bytes: usize = 64 * 1024;
/// Applies the transfer bound to one admitted remote input batch.
pub const max_input_bytes = max_transfer_bytes;
/// Bounds one copied current viewport response.
pub const max_screen_bytes: usize = 256 * 1024;
/// Bounds one terminal surface width in direct and remote observations.
pub const max_cols: u16 = 512;
/// Bounds one terminal surface height in direct and remote observations.
pub const max_rows: u16 = 256;
/// Bounds retained semantic history and output-loss response records.
pub const max_history_rows: u16 = 16_384;
/// Bounds one admitted input batch.
pub const max_send_events: u16 = 256;
/// Bounds delay before one admitted event.
pub const max_event_delay_ms: u16 = 2000;
/// Bounds scheduled delay retained by one admitted batch.
pub const max_batch_delay_ms: u32 = 10_000;
// Protocol v1 remains byte-for-byte compatible with the first QAgent embedder
// while Howl takes ownership of its native endpoint and transport vocabulary.
const protocol_version: u16 = 1;
/// Fixes the bounded request header consumed by the sibling server owner.
pub const request_header_bytes: usize = 28;
const response_header_bytes: usize = 56;
// An incomplete peer loses admission quickly; complete local transfers get
// scheduler headroom without permitting an indefinitely blocked shutdown.
const transfer_timeout_ms: i32 = 2000;
/// Bounds an incomplete peer before primitive execution begins.
pub const admission_timeout_ms: i32 = 250;
const max_output_response_bytes: usize = howl_vt.Terminal.logical_output_max_bytes +
    @as(usize, max_history_rows) * 17 + 64;
/// Rejects advertised request payloads before stack-buffer admission.
pub const max_request_bytes: usize = 128 * 1024;

/// Host-neutral terminal input accepted by the shared admission owner.
pub const Input = howl_vt.Terminal.InputEvent;
const KeyInput = @FieldType(Input, "key");
const MouseInput = @FieldType(Input, "mouse");
const FocusInput = @FieldType(Input, "focus");
const KeyIdentity = @FieldType(KeyInput, "key");
const NamedKey = @FieldType(KeyIdentity, "named");
const KeyAction = @FieldType(KeyInput, "action");
const Modifiers = @FieldType(KeyInput, "mods");
/// Identifies one process-lifetime Howl terminal and its endpoint.
pub const TerminalId = struct {
    /// Retains the exact 128-bit identity carried by endpoint and wire facts.
    bytes: [16]u8,

    /// Reports whether the identity names a concrete terminal.
    pub fn valid(self: TerminalId) bool {
        return !std.mem.allEqual(u8, &self.bytes, 0);
    }
    /// Writes the canonical lowercase hexadecimal identity.
    pub fn format(self: TerminalId, buffer: *[32]u8) []const u8 {
        return std.fmt.bufPrint(buffer, "{x}", .{self.bytes}) catch unreachable;
    }
    /// Parses one canonical lowercase nonzero identity.
    pub fn parse(text: []const u8) error{InvalidTerminalId}!TerminalId {
        if (text.len != 32) return error.InvalidTerminalId;
        for (text) |byte| switch (byte) {
            '0'...'9', 'a'...'f' => {},
            else => return error.InvalidTerminalId,
        };
        var id: TerminalId = undefined;
        const decoded = std.fmt.hexToBytes(&id.bytes, text) catch
            return error.InvalidTerminalId;
        std.debug.assert(decoded.len == id.bytes.len);
        if (!id.valid()) return error.InvalidTerminalId;
        return id;
    }

    /// Writes the canonical endpoint filename without allocating.
    pub fn formatEndpoint(self: TerminalId, buffer: *[37]u8) []const u8 {
        const text = std.fmt.bufPrint(buffer[0..32], "{x}", .{self.bytes}) catch
            unreachable;
        std.debug.assert(text.len == 32);
        @memcpy(buffer[32..37], ".sock");
        return buffer;
    }

    /// Parses one canonical endpoint filename and rejects unrelated entries.
    pub fn parseEndpoint(filename: []const u8) error{InvalidTerminalId}!TerminalId {
        if (filename.len != 37 or !std.mem.eql(u8, filename[32..], ".sock")) {
            return error.InvalidTerminalId;
        }
        return parse(filename[0..32]);
    }

    /// Generates a random nonzero identity from the caller's I/O authority.
    pub fn random(io: std.Io) TerminalId {
        while (true) {
            var id: TerminalId = undefined;
            io.random(&id.bytes);
            if (id.valid()) return id;
        }
    }
};
/// Names Howl's private endpoint directory beneath `XDG_RUNTIME_DIR`.
pub const endpoint_directory = "howl";
/// Distinguishes live progress, orderly completion, and retained failure.
pub const State = enum(u8) { running, stopped, failed };
/// Reports the exact asynchronous reader failure represented by remote status.
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
    FrameSurfaceBounds,
    FrameInvalidCell,
    FrameInvalidCellPixels,
    FrameInvalidCursor,
    FrameInvalidDamage,
    FrameInvalidSelection,
    FrameGenerationExhausted,
};
/// Copies one bounded real OSC 133 mark and retained shell identity.
pub const ShellMark = struct {
    /// Identifies this accepted mark monotonically within one terminal.
    generation: u64,
    /// Retains exact OSC 133 mark kind A, B, C, or D.
    kind: u8,
    /// Retains an optional parsed status without inference.
    status: ?i32,
    /// Stores the bounded metadata prefix selected by `metadata_len`.
    metadata: [howl_vt.Terminal.shell_mark_metadata_max_bytes]u8,
    /// Bounds meaningful metadata bytes in the fixed buffer.
    metadata_len: u16,
    /// Stores the bounded shell identity prefix selected by `shell_len`.
    shell: [howl_vt.Terminal.shell_name_max_bytes]u8,
    /// Bounds meaningful shell bytes; zero means absent.
    shell_len: u8,

    /// Borrows the meaningful metadata prefix.
    pub fn metadataBytes(self: *const ShellMark) []const u8 {
        return self.metadata[0..self.metadata_len];
    }
    /// Borrows the meaningful shell identity when present.
    pub fn shellBytes(self: *const ShellMark) ?[]const u8 {
        return if (self.shell_len == 0) null else self.shell[0..self.shell_len];
    }
};
/// Reports input encoding or transfer-bound rejection before remote admission.
pub const InputError = howl_vt.Terminal.InputError || error{InputLimit};
/// Retains exact complete or partial PTY transfer truth.
pub const InputTransfer = howl_pty.Transfer;
const TransferIncomplete = @FieldType(InputTransfer, "incomplete");
/// Reports invalid size, borrowed frame storage, model/PTTY failure, or failed rollback.
pub const ResizeError = howl_vt.Terminal.ResizeError || error{
    InvalidDimensions,
    NotStarted,
    PtyResizeFailed,
    ResizeRollbackFailed,
    FrameBorrowed,
    FrameSurfaceBounds,
    FrameInvalidCell,
    FrameInvalidCellPixels,
    FrameInvalidCursor,
    FrameInvalidDamage,
    FrameInvalidSelection,
    FrameGenerationExhausted,
};
/// Uses Howl VT's bounded finalized-output cursor and loss outcomes.
pub const LogicalOutputResult = howl_vt.Terminal.LogicalOutputResult;
const LogicalOutput = @FieldType(LogicalOutputResult, "output");
const LogicalOutputLoss = @typeInfo(@FieldType(LogicalOutput, "losses")).pointer.child;
/// Reports invalid logical-output limits or allocation failure.
pub const LogicalOutputError = howl_vt.Terminal.LogicalOutputError;
/// Selects one fixed process-group signal.
pub const ControlSignal = howl_pty.ControlSignal;
/// Reports exact process-group probing and signal delivery outcomes.
pub const ControlResult = howl_pty.ControlResult;

/// Retains one admitted input batch's complete or partial external effect.
pub const SendResult = struct {
    /// Orders this mutation against operator, resize, signal, and CLI input.
    admission_sequence: u64,
    /// Advances only when every event completed transfer.
    input_sequence: u64,
    /// Counts events whose complete encoded bytes reached the PTY.
    completed_events: u16,
    /// Retains complete delivery, a partial PTY prefix, or event encoding rejection.
    outcome: SendOutcome,
};

/// Couples one host input fact with an optional bounded delay before dispatch.
pub const BatchEvent = struct {
    /// Borrows one host-neutral input until the batch returns.
    input: Input,
    /// Delays this event while preserving batch admission ownership.
    delay_ms: u16 = 0,
};

/// Names exact input preparation failures after a batch acquired admission.
pub const SendFailure = enum {
    consequence_limit,
    input_limit,
    invalid_text,
    invalid_utf8,
    key_text_limit,
    length_overflow,
    out_of_memory,
    delay_shutdown,
    delay_terminal_closed,
    delay_canceled,
    invalid_geometry,
};

/// Retains every externally observable outcome of an admitted input batch.
pub const SendOutcome = union(enum) {
    /// Reports all encoded bytes transferred for every event.
    complete: usize,
    /// Reports the exact PTY prefix and transport reason.
    incomplete: struct { transferred: usize, reason: @FieldType(TransferIncomplete, "reason") },
    /// Reports preparation failure after zero or more complete events.
    rejected: struct { transferred: usize, reason: SendFailure },
};

/// Retains one admitted resize and whether geometry truth changed.
pub const ResizeResult = struct {
    /// Orders this resize against every admitted mutation.
    admission_sequence: u64,
    /// Advances only when PTY and model geometry changed successfully.
    geometry_sequence: u64,
    /// Reports whether this request changed geometry.
    changed: bool,
    /// Reports the admitted terminal width.
    cols: u16,
    /// Reports the admitted terminal height.
    rows: u16,
};

/// Retains one admitted process-group signal and its native outcome.
pub const SignalResult = struct {
    /// Orders this signal against every admitted mutation.
    admission_sequence: u64,
    /// Retains the fixed signal requested by the caller.
    signal: ControlSignal,
    /// Reports kernel delivery or its exact owned failure class.
    outcome: ControlResult,
};

/// Copies coherent terminal, endpoint, and admission facts from one response.
pub const Status = struct {
    /// Identifies the process-lifetime terminal.
    terminal_id: TerminalId,
    /// Reports current terminal progress lifecycle.
    state: State,
    /// Retains the asynchronous reader failure only after failed lifecycle.
    reader_error: ?ReaderError,
    /// Retains an accepted PTY prefix only for a terminal-reply reader failure.
    reply_failure_transferred: ?usize,
    /// Reports failed restoration of PTY geometry after model resize rejection.
    resize_rollback_failed: bool,
    /// Borrows the copied launch cwd, never an inferred live shell cwd.
    child_cwd: ?[]const u8,
    /// Reports current terminal width.
    cols: u16,
    /// Reports current terminal height.
    rows: u16,
    /// Identifies the coherent surface observation.
    publication: u64,
    /// Counts primary history rows dropped after bounded allocation failure.
    history_loss_generation: u64,
    /// Reports whether the current viewport is alternate-screen state.
    alternate_screen: bool,
    /// Identifies the latest admitted mutation.
    admission_sequence: u64,
    /// Identifies the latest completely transferred input batch.
    input_sequence: u64,
    /// Identifies the latest successful changed resize.
    geometry_sequence: u64,
    /// Identifies the oldest retained finalized primary line.
    output_oldest: u64,
    /// Identifies the newest finalized primary line.
    output_newest: u64,
    /// Copies the latest real shell-integration mark, when present.
    shell_mark: ?ShellMark,
};

// One-shot endpoint client and owned response values.

/// Reports exact local construction, transport, identity, or remote rejection failure.
pub const ClientError = std.mem.Allocator.Error || error{
    BadMagic,
    ConnectFailed,
    EndpointPathTooLong,
    InputLimit,
    ConsequenceLimit,
    InvalidText,
    InvalidUtf8,
    KeyTextLimit,
    LengthOverflow,
    InvalidPayload,
    InvalidResponse,
    ReadFailed,
    FrameBorrowed,
    RemoteRejected,
    ResizeRollbackFailed,
    ResponseLimit,
    TerminalClosed,
    Timeout,
    Unauthorized,
    WriteFailed,
    WrongTerminal,
    WrongVersion,
};

/// Owns one bounded coherent current terminal viewport copy.
pub const Screen = struct {
    /// Owns the viewport text allocation.
    allocator: std.mem.Allocator,
    /// Contains bounded right-trimmed rows for the current viewport.
    text: []u8,
    /// Identifies the coherent surface observation.
    publication: u64,
    /// Reports viewport width.
    cols: u16,
    /// Reports viewport height.
    rows: u16,
    /// Reports whether this is alternate-screen state.
    alternate_screen: bool,
    /// Reports whether the cursor is visible in terminal truth.
    cursor_visible: bool,
    /// Reports the zero-based cursor column.
    cursor_col: u16,
    /// Reports the zero-based cursor row.
    cursor_row: u16,

    /// Releases copied viewport text exactly once.
    pub fn deinit(self: *Screen) void {
        self.allocator.free(self.text);
        self.* = undefined;
    }
};

/// Owns one local endpoint path used for one-shot control requests.
pub const Client = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    terminal_id: TerminalId,
    endpoint_path: []u8,

    /// Resolves one terminal identity beneath the caller's runtime directory.
    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        runtime_dir: []const u8,
        terminal_id: TerminalId,
    ) (std.mem.Allocator.Error || error{EndpointPathTooLong})!Client {
        var filename: [37]u8 = undefined;
        const endpoint_path = try std.fs.path.join(
            allocator,
            &.{ runtime_dir, endpoint_directory, terminal_id.formatEndpoint(&filename) },
        );
        errdefer allocator.free(endpoint_path);
        if (endpoint_path.len >= net.UnixAddress.max_len) return error.EndpointPathTooLong;
        return .{
            .allocator = allocator,
            .io = io,
            .terminal_id = terminal_id,
            .endpoint_path = endpoint_path,
        };
    }

    /// Releases the resolved endpoint path.
    pub fn deinit(self: *Client) void {
        self.allocator.free(self.endpoint_path);
        self.* = undefined;
    }

    /// Requests current lifecycle, geometry, and independent sequence values.
    pub fn status(self: *Client) ClientError!ClientStatus {
        var response = try self.request(.status, &.{}, transfer_timeout_ms);
        defer response.deinit();
        return decodeStatus(self.allocator, self.terminal_id, response.payload);
    }

    /// Sends one nonempty atomic event batch through shared mutation admission.
    pub fn send(self: *Client, events: []const BatchEvent) ClientError!SendResult {
        const payload = try encodeBatch(self.allocator, events);
        defer self.allocator.free(payload);
        const response_timeout = std.math.add(
            i32,
            transfer_timeout_ms,
            @intCast(try scheduledDelay(events)),
        ) catch return error.InputLimit;
        var response = try self.request(.send, payload, response_timeout);
        defer response.deinit();
        return decodeSendResult(response.payload, @intCast(events.len));
    }

    /// Requests one coherent bounded current terminal viewport.
    pub fn screen(self: *Client) ClientError!Screen {
        var response = try self.request(.screen, &.{}, transfer_timeout_ms);
        defer response.deinit();
        return decodeScreen(self.allocator, response.payload);
    }

    /// Requests bounded finalized primary output after `cursor`.
    pub fn output(
        self: *Client,
        cursor: u64,
        max_lines: u16,
        max_bytes: u32,
    ) ClientError!LogicalOutputResult {
        var payload: [14]u8 = undefined;
        std.mem.writeInt(u64, payload[0..8], cursor, .big);
        std.mem.writeInt(u16, payload[8..10], max_lines, .big);
        std.mem.writeInt(u32, payload[10..14], max_bytes, .big);
        var response = try self.request(.output, &payload, transfer_timeout_ms);
        defer response.deinit();
        return decodeOutput(self.allocator, response.payload);
    }

    /// Admits one terminal geometry and reports whether it changed.
    pub fn resize(self: *Client, cols: u16, rows: u16) ClientError!ResizeResult {
        var payload: [4]u8 = undefined;
        std.mem.writeInt(u16, payload[0..2], cols, .big);
        std.mem.writeInt(u16, payload[2..4], rows, .big);
        var response = try self.request(.resize, &payload, transfer_timeout_ms);
        defer response.deinit();
        return decodeResize(response.payload, cols, rows);
    }

    /// Delivers one fixed signal to the owned child process group.
    pub fn signal(self: *Client, value: ControlSignal) ClientError!SignalResult {
        var response = try self.request(.signal, &.{encodeControlSignal(value)}, transfer_timeout_ms);
        defer response.deinit();
        return decodeSignal(response.payload, value);
    }

    fn request(
        self: *Client,
        operation: Operation,
        payload: []const u8,
        response_timeout_ms: i32,
    ) ClientError!RawResponse {
        var stream = try connectLinux(self.io, self.endpoint_path);
        defer stream.close(self.io);
        var request_header: [request_header_bytes]u8 = undefined;
        encodeRequestHeader(&request_header, operation, self.terminal_id, payload.len);
        const request_started = std.Io.Clock.awake.now(self.io);
        writeExact(
            self.io,
            stream.socket.handle,
            &request_header,
            request_started,
            transfer_timeout_ms,
        ) catch |failure| return transportClientError(failure, error.WriteFailed);
        writeExact(
            self.io,
            stream.socket.handle,
            payload,
            request_started,
            transfer_timeout_ms,
        ) catch |failure| return transportClientError(failure, error.WriteFailed);

        var response_header: [response_header_bytes]u8 = undefined;
        const response_started = std.Io.Clock.awake.now(self.io);
        readExact(
            self.io,
            stream.socket.handle,
            &response_header,
            response_started,
            response_timeout_ms,
        ) catch |failure| return transportClientError(failure, error.ReadFailed);
        const decoded = try decodeResponseHeader(&response_header, self.terminal_id, operation);
        const owned = try self.allocator.alloc(u8, decoded.payload_len);
        errdefer self.allocator.free(owned);
        readExact(
            self.io,
            stream.socket.handle,
            owned,
            response_started,
            response_timeout_ms,
        ) catch |failure| return transportClientError(failure, error.ReadFailed);
        return .{
            .allocator = self.allocator,
            .payload = owned,
        };
    }
};

/// Owns one decoded status response, including optional copied launch cwd.
pub const ClientStatus = struct {
    allocator: std.mem.Allocator,
    value: Status,

    /// Releases the copied cwd exactly once.
    pub fn deinit(self: *ClientStatus) void {
        if (self.value.child_cwd) |cwd| self.allocator.free(cwd);
        self.* = undefined;
    }
};

const RawResponse = struct {
    allocator: std.mem.Allocator,
    payload: []u8,

    fn deinit(self: *RawResponse) void {
        self.allocator.free(self.payload);
        self.* = undefined;
    }
};

// Typed payload validation and result codecs.

/// Proves a batch's encoded and scheduled bounds before mutation admission.
pub fn validateBatchBound(events: []const BatchEvent) error{InputLimit}!void {
    var encoded_max: usize = 0;
    var delay_total: u32 = 0;
    for (events) |event| {
        if (event.delay_ms > max_event_delay_ms) return error.InputLimit;
        delay_total = std.math.add(u32, delay_total, event.delay_ms) catch return error.InputLimit;
        if (delay_total > max_batch_delay_ms) return error.InputLimit;
        const event_max: usize = switch (event.input) {
            .bytes => |bytes| bytes.len,
            .paste => |text| std.math.add(usize, text.len, 12) catch return error.InputLimit,
            // Kitty text reports can expand each UTF-8 source byte into decimal
            // protocol fields; this bound deliberately precedes any PTY effect.
            .key => |key| try keyEncodedMax(key.legacy_text.len, key.text.len),
            .mouse => 64,
            .focus => 8,
        };
        encoded_max = std.math.add(usize, encoded_max, event_max) catch return error.InputLimit;
        if (encoded_max > max_input_bytes) return error.InputLimit;
    }
}

fn scheduledDelay(events: []const BatchEvent) error{InputLimit}!u32 {
    var total: u32 = 0;
    for (events) |event| {
        if (event.delay_ms > max_event_delay_ms) return error.InputLimit;
        total = std.math.add(u32, total, event.delay_ms) catch return error.InputLimit;
        if (total > max_batch_delay_ms) return error.InputLimit;
    }
    return total;
}

fn keyEncodedMax(legacy_bytes: usize, text_bytes: usize) error{InputLimit}!usize {
    const source_bytes = std.math.add(usize, legacy_bytes, text_bytes) catch return error.InputLimit;
    const expanded = std.math.mul(usize, source_bytes, 4) catch return error.InputLimit;
    return std.math.add(usize, 64, expanded) catch return error.InputLimit;
}

/// Maps one exact input preparation failure into admitted batch evidence.
pub fn sendFailure(failure: InputError) SendFailure {
    return switch (failure) {
        error.ConsequenceLimit => .consequence_limit,
        error.InputLimit => .input_limit,
        error.InvalidText => .invalid_text,
        error.InvalidUtf8 => .invalid_utf8,
        error.KeyTextLimit => .key_text_limit,
        error.LengthOverflow => .length_overflow,
        error.OutOfMemory => .out_of_memory,
    };
}

/// Encodes one exact process-group control outcome for protocol v1.
pub fn encodeControlResult(result: ControlResult) u8 {
    return switch (result) {
        .delivered => 1,
        .target_missing => 2,
        .state_probe_failed => 3,
        .permission_denied => 4,
        .native_signal_failed => 5,
    };
}

fn encodeReaderError(failure: ?ReaderError) u8 {
    const value = failure orelse return 0;
    return switch (value) {
        error.ConsequenceLimit => 1,
        error.ModelAllocationFailed => 2,
        error.ParsedEventLimit => 3,
        error.PtyReadFailed => 4,
        error.PtyReplyCanceled => 5,
        error.PtyReplyChildClosed => 6,
        error.PtyReplyTimedOut => 7,
        error.PtyReplyWaitFailed => 8,
        error.PtyReplyWriteFailed => 9,
        error.PtyWaitFailed => 10,
        error.ReplyAllocationFailed => 11,
        error.StringControlLimit => 12,
        error.FrameSurfaceBounds => 13,
        error.FrameInvalidCell => 14,
        error.FrameInvalidCellPixels => 15,
        error.FrameInvalidCursor => 16,
        error.FrameInvalidDamage => 17,
        error.FrameInvalidSelection => 18,
        error.FrameGenerationExhausted => 19,
    };
}

/// Encodes one coherent status into the private bounded protocol payload.
pub fn encodeStatus(allocator: std.mem.Allocator, value: Status) std.mem.Allocator.Error![]u8 {
    const cwd = value.child_cwd orelse "";
    const mark_metadata = if (value.shell_mark) |*mark| mark.metadataBytes() else "";
    const shell = if (value.shell_mark) |*mark| mark.shellBytes() orelse "" else "";
    const bytes = try allocator.alloc(u8, 90 + cwd.len + mark_metadata.len + shell.len);
    bytes[0] = encodeWireState(value.state);
    bytes[1] = encodeReaderError(value.reader_error);
    std.mem.writeInt(u16, bytes[2..4], value.cols, .big);
    std.mem.writeInt(u16, bytes[4..6], value.rows, .big);
    std.mem.writeInt(u64, bytes[6..14], value.publication, .big);
    bytes[14] = @intFromBool(value.alternate_screen);
    std.mem.writeInt(u64, bytes[15..23], value.admission_sequence, .big);
    std.mem.writeInt(u64, bytes[23..31], value.input_sequence, .big);
    std.mem.writeInt(u64, bytes[31..39], value.geometry_sequence, .big);
    std.mem.writeInt(u64, bytes[39..47], value.output_oldest, .big);
    std.mem.writeInt(u64, bytes[47..55], value.output_newest, .big);
    bytes[55] = @intFromBool(value.shell_mark != null);
    if (value.shell_mark) |mark| {
        std.mem.writeInt(u64, bytes[56..64], mark.generation, .big);
        bytes[64] = mark.kind;
        bytes[65] = @intFromBool(mark.status != null);
        std.mem.writeInt(i32, bytes[66..70], mark.status orelse 0, .big);
    } else @memset(bytes[56..70], 0);
    std.mem.writeInt(u16, bytes[70..72], @intCast(mark_metadata.len), .big);
    bytes[72] = @intCast(shell.len);
    std.mem.writeInt(u32, bytes[73..77], @intCast(cwd.len), .big);
    bytes[77] = @intFromBool(value.resize_rollback_failed);
    std.mem.writeInt(
        u32,
        bytes[78..82],
        if (value.reply_failure_transferred) |count| @intCast(count) else std.math.maxInt(u32),
        .big,
    );
    std.mem.writeInt(u64, bytes[82..90], value.history_loss_generation, .big);
    var offset: usize = 90;
    @memcpy(bytes[offset..][0..cwd.len], cwd);
    offset += cwd.len;
    @memcpy(bytes[offset..][0..mark_metadata.len], mark_metadata);
    offset += mark_metadata.len;
    @memcpy(bytes[offset..][0..shell.len], shell);
    return bytes;
}

/// Encodes one owned viewport observation into a bounded response payload.
pub fn encodeScreen(allocator: std.mem.Allocator, value: *const Screen) std.mem.Allocator.Error![]u8 {
    const bytes = try allocator.alloc(u8, 22 + value.text.len);
    std.mem.writeInt(u64, bytes[0..8], value.publication, .big);
    std.mem.writeInt(u16, bytes[8..10], value.cols, .big);
    std.mem.writeInt(u16, bytes[10..12], value.rows, .big);
    bytes[12] = @intFromBool(value.alternate_screen);
    bytes[13] = @intFromBool(value.cursor_visible);
    std.mem.writeInt(u16, bytes[14..16], value.cursor_col, .big);
    std.mem.writeInt(u16, bytes[16..18], value.cursor_row, .big);
    std.mem.writeInt(u32, bytes[18..22], @intCast(value.text.len), .big);
    @memcpy(bytes[22..], value.text);
    return bytes;
}

/// Encodes finalized output, stale cursors, and bounded loss evidence.
pub fn encodeOutputResult(
    allocator: std.mem.Allocator,
    result: *const LogicalOutputResult,
) std.mem.Allocator.Error![]u8 {
    return switch (result.*) {
        .cursor_stale => |oldest| encodeOutputCursor(allocator, 1, oldest),
        .cursor_ahead => |newest| encodeOutputCursor(allocator, 2, newest),
        .line_too_long => |id| encodeOutputCursor(allocator, 3, id),
        .open_line_too_long => allocator.dupe(u8, &.{4}),
        .output => |output_value| blk: {
            const losses_bytes = std.math.mul(usize, output_value.losses.len, 17) catch
                return error.OutOfMemory;
            var length = std.math.add(usize, 49, losses_bytes) catch return error.OutOfMemory;
            length = std.math.add(usize, length, output_value.text.len) catch return error.OutOfMemory;
            length = std.math.add(usize, length, output_value.open_line.len) catch return error.OutOfMemory;
            std.debug.assert(length <= max_output_response_bytes);
            const bytes = try allocator.alloc(u8, length);
            bytes[0] = 0;
            std.mem.writeInt(u64, bytes[1..9], output_value.oldest, .big);
            std.mem.writeInt(u64, bytes[9..17], output_value.cursor, .big);
            std.mem.writeInt(u64, bytes[17..25], output_value.newest, .big);
            std.mem.writeInt(u64, bytes[25..33], output_value.publication, .big);
            std.mem.writeInt(u16, bytes[33..35], output_value.line_count, .big);
            bytes[35] = @intFromBool(output_value.more);
            bytes[36] = @intFromBool(output_value.open_line_omitted);
            std.mem.writeInt(u32, bytes[37..41], @intCast(output_value.text.len), .big);
            std.mem.writeInt(u32, bytes[41..45], @intCast(output_value.open_line.len), .big);
            std.mem.writeInt(u32, bytes[45..49], @intCast(output_value.losses.len), .big);
            var offset: usize = 49;
            @memcpy(bytes[offset .. offset + output_value.text.len], output_value.text);
            offset += output_value.text.len;
            @memcpy(bytes[offset .. offset + output_value.open_line.len], output_value.open_line);
            offset += output_value.open_line.len;
            for (output_value.losses) |loss| {
                std.mem.writeInt(u64, bytes[offset..][0..8], loss.id, .big);
                std.mem.writeInt(u64, bytes[offset + 8 ..][0..8], loss.byte_count, .big);
                bytes[offset + 16] = switch (loss.reason) {
                    .line_too_long => 1,
                };
                offset += 17;
            }
            std.debug.assert(offset == bytes.len);
            break :blk bytes;
        },
    };
}

fn encodeOutputCursor(allocator: std.mem.Allocator, tag: u8, cursor: u64) std.mem.Allocator.Error![]u8 {
    const bytes = try allocator.alloc(u8, 9);
    bytes[0] = tag;
    std.mem.writeInt(u64, bytes[1..9], cursor, .big);
    return bytes;
}

/// Encodes one admitted input result without allocation.
pub fn encodeSendResult(result: SendResult) [28]u8 {
    var bytes: [28]u8 = @splat(0);
    std.mem.writeInt(u64, bytes[0..8], result.admission_sequence, .big);
    std.mem.writeInt(u64, bytes[8..16], result.input_sequence, .big);
    std.mem.writeInt(u16, bytes[16..18], result.completed_events, .big);
    switch (result.outcome) {
        .complete => |count| {
            bytes[18] = 0;
            std.mem.writeInt(u64, bytes[19..27], count, .big);
        },
        .incomplete => |failure| {
            bytes[18] = 1;
            std.mem.writeInt(u64, bytes[19..27], failure.transferred, .big);
            bytes[27] = encodeTransferReason(failure.reason);
        },
        .rejected => |failure| {
            bytes[18] = 2;
            std.mem.writeInt(u64, bytes[19..27], failure.transferred, .big);
            bytes[27] = encodeSendFailure(failure.reason);
        },
    }
    return bytes;
}

fn decodeSendResult(payload: []const u8, expected_events: u16) ClientError!SendResult {
    if (payload.len != 28) return error.InvalidResponse;
    const transferred = std.math.cast(usize, std.mem.readInt(u64, payload[19..27], .big)) orelse
        return error.InvalidResponse;
    const completed_events = std.mem.readInt(u16, payload[16..18], .big);
    if (completed_events > expected_events or transferred > max_input_bytes) return error.InvalidResponse;
    if (payload[18] == 0 and completed_events != expected_events) return error.InvalidResponse;
    return .{
        .admission_sequence = std.mem.readInt(u64, payload[0..8], .big),
        .input_sequence = std.mem.readInt(u64, payload[8..16], .big),
        .completed_events = completed_events,
        .outcome = switch (payload[18]) {
            0 => if (payload[27] == 0) .{ .complete = transferred } else return error.InvalidResponse,
            1 => .{ .incomplete = .{
                .transferred = transferred,
                .reason = decodeTransferReason(payload[27]) orelse return error.InvalidResponse,
            } },
            2 => .{ .rejected = .{
                .transferred = transferred,
                .reason = decodeSendFailure(payload[27]) orelse return error.InvalidResponse,
            } },
            else => return error.InvalidResponse,
        },
    };
}

fn encodeTransferReason(reason: @FieldType(TransferIncomplete, "reason")) u8 {
    return switch (reason) {
        .timeout => 1,
        .canceled => 2,
        .child_closed => 3,
        .not_started => 4,
        .wait_failed => 5,
        .write_failed => 6,
    };
}

fn decodeTransferReason(value: u8) ?@FieldType(TransferIncomplete, "reason") {
    return switch (value) {
        1 => .timeout,
        2 => .canceled,
        3 => .child_closed,
        4 => .not_started,
        5 => .wait_failed,
        6 => .write_failed,
        else => null,
    };
}

fn encodeSendFailure(reason: SendFailure) u8 {
    return switch (reason) {
        .consequence_limit => 1,
        .input_limit => 2,
        .invalid_text => 3,
        .invalid_utf8 => 4,
        .key_text_limit => 5,
        .length_overflow => 6,
        .out_of_memory => 7,
        .delay_shutdown => 8,
        .delay_terminal_closed => 9,
        .delay_canceled => 10,
        .invalid_geometry => 11,
    };
}

fn decodeSendFailure(value: u8) ?SendFailure {
    return switch (value) {
        1 => .consequence_limit,
        2 => .input_limit,
        3 => .invalid_text,
        4 => .invalid_utf8,
        5 => .key_text_limit,
        6 => .length_overflow,
        7 => .out_of_memory,
        8 => .delay_shutdown,
        9 => .delay_terminal_closed,
        10 => .delay_canceled,
        11 => .invalid_geometry,
        else => null,
    };
}

fn decodeStatus(
    allocator: std.mem.Allocator,
    terminal_id: TerminalId,
    payload: []const u8,
) ClientError!ClientStatus {
    if (payload.len < 90) return error.InvalidResponse;
    const metadata_len = std.mem.readInt(u16, payload[70..72], .big);
    const shell_len = payload[72];
    const cwd_len = std.mem.readInt(u32, payload[73..77], .big);
    const variable_len = std.math.add(usize, cwd_len, metadata_len) catch
        return error.InvalidResponse;
    const expected_len = std.math.add(usize, variable_len, shell_len) catch
        return error.InvalidResponse;
    if (expected_len != payload.len - 90 or
        metadata_len > howl_vt.Terminal.shell_mark_metadata_max_bytes or
        shell_len > howl_vt.Terminal.shell_name_max_bytes or
        payload[14] > 1 or payload[55] > 1 or payload[65] > 1 or payload[77] > 1 or
        (payload[65] == 0 and !std.mem.allEqual(u8, payload[66..70], 0)))
        return error.InvalidResponse;
    const state = decodeWireState(payload[0]) orelse return error.InvalidResponse;
    const reader_error = try decodeReaderError(payload[1]);
    const resize_rollback_failed = payload[77] == 1;
    const reply_count_raw = std.mem.readInt(u32, payload[78..82], .big);
    const reply_failure_transferred: ?usize = if (reply_count_raw == std.math.maxInt(u32))
        null
    else
        reply_count_raw;
    if (reply_failure_transferred) |count| {
        if (count > 64 * 1024 or !isReplyTransferError(reader_error)) {
            return error.InvalidResponse;
        }
    } else if (isReplyTransferError(reader_error)) return error.InvalidResponse;
    if (!validLifecycleStatus(state, reader_error, resize_rollback_failed)) {
        return error.InvalidResponse;
    }
    const cols = std.mem.readInt(u16, payload[2..4], .big);
    const rows = std.mem.readInt(u16, payload[4..6], .big);
    if (cols == 0 or rows == 0 or cols > max_cols or rows > max_rows) {
        return error.InvalidResponse;
    }
    var offset: usize = 90;
    const cwd = if (cwd_len == 0) null else try allocator.dupe(u8, payload[offset..][0..cwd_len]);
    errdefer if (cwd) |owned| allocator.free(owned);
    offset += cwd_len;
    var shell_mark: ?ShellMark = null;
    if (payload[55] == 1) {
        const generation = std.mem.readInt(u64, payload[56..64], .big);
        if (generation == 0) return error.InvalidResponse;
        var mark = ShellMark{
            .generation = generation,
            .kind = payload[64],
            .status = if (payload[65] == 1) std.mem.readInt(i32, payload[66..70], .big) else null,
            .metadata = @splat(0),
            .metadata_len = metadata_len,
            .shell = @splat(0),
            .shell_len = shell_len,
        };
        @memcpy(mark.metadata[0..metadata_len], payload[offset..][0..metadata_len]);
        offset += metadata_len;
        @memcpy(mark.shell[0..shell_len], payload[offset..][0..shell_len]);
        shell_mark = mark;
    } else if (metadata_len != 0 or shell_len != 0 or
        !std.mem.allEqual(u8, payload[56..70], 0)) return error.InvalidResponse;
    return .{ .allocator = allocator, .value = .{
        .terminal_id = terminal_id,
        .state = state,
        .reader_error = reader_error,
        .reply_failure_transferred = reply_failure_transferred,
        .resize_rollback_failed = resize_rollback_failed,
        .child_cwd = cwd,
        .cols = cols,
        .rows = rows,
        .publication = std.mem.readInt(u64, payload[6..14], .big),
        .history_loss_generation = std.mem.readInt(u64, payload[82..90], .big),
        .alternate_screen = payload[14] == 1,
        .admission_sequence = std.mem.readInt(u64, payload[15..23], .big),
        .input_sequence = std.mem.readInt(u64, payload[23..31], .big),
        .geometry_sequence = std.mem.readInt(u64, payload[31..39], .big),
        .output_oldest = std.mem.readInt(u64, payload[39..47], .big),
        .output_newest = std.mem.readInt(u64, payload[47..55], .big),
        .shell_mark = shell_mark,
    } };
}

fn isReplyTransferError(failure: ?ReaderError) bool {
    const reader_error = failure orelse return false;
    return switch (reader_error) {
        error.PtyReplyCanceled,
        error.PtyReplyChildClosed,
        error.PtyReplyTimedOut,
        error.PtyReplyWaitFailed,
        error.PtyReplyWriteFailed,
        => true,
        else => false,
    };
}

fn validLifecycleStatus(
    state: State,
    reader_error: ?ReaderError,
    resize_rollback_failed: bool,
) bool {
    // Failed lifecycle has exactly one owner: reader progress or resize rollback.
    return switch (state) {
        .running, .stopped => reader_error == null and !resize_rollback_failed,
        .failed => (reader_error != null) != resize_rollback_failed,
    };
}

fn decodeReaderError(value: u8) error{InvalidResponse}!?ReaderError {
    return switch (value) {
        0 => null,
        1 => @as(?ReaderError, error.ConsequenceLimit),
        2 => @as(?ReaderError, error.ModelAllocationFailed),
        3 => @as(?ReaderError, error.ParsedEventLimit),
        4 => @as(?ReaderError, error.PtyReadFailed),
        5 => @as(?ReaderError, error.PtyReplyCanceled),
        6 => @as(?ReaderError, error.PtyReplyChildClosed),
        7 => @as(?ReaderError, error.PtyReplyTimedOut),
        8 => @as(?ReaderError, error.PtyReplyWaitFailed),
        9 => @as(?ReaderError, error.PtyReplyWriteFailed),
        10 => @as(?ReaderError, error.PtyWaitFailed),
        11 => @as(?ReaderError, error.ReplyAllocationFailed),
        12 => @as(?ReaderError, error.StringControlLimit),
        13 => @as(?ReaderError, error.FrameSurfaceBounds),
        14 => @as(?ReaderError, error.FrameInvalidCell),
        15 => @as(?ReaderError, error.FrameInvalidCellPixels),
        16 => @as(?ReaderError, error.FrameInvalidCursor),
        17 => @as(?ReaderError, error.FrameInvalidDamage),
        18 => @as(?ReaderError, error.FrameInvalidSelection),
        19 => @as(?ReaderError, error.FrameGenerationExhausted),
        else => return error.InvalidResponse,
    };
}

test "frame publication failure survives status wire encoding" {
    try std.testing.expectEqual(
        @as(?ReaderError, error.FrameGenerationExhausted),
        try decodeReaderError(encodeReaderError(error.FrameGenerationExhausted)),
    );
    try std.testing.expectError(error.InvalidResponse, decodeReaderError(20));
}

fn decodeScreen(allocator: std.mem.Allocator, payload: []const u8) ClientError!Screen {
    if (payload.len < 22 or payload[12] > 1 or payload[13] > 1) return error.InvalidResponse;
    const text_len = std.mem.readInt(u32, payload[18..22], .big);
    if (text_len != payload.len - 22) return error.InvalidResponse;
    const cols = std.mem.readInt(u16, payload[8..10], .big);
    const rows = std.mem.readInt(u16, payload[10..12], .big);
    const cursor_col = std.mem.readInt(u16, payload[14..16], .big);
    const cursor_row = std.mem.readInt(u16, payload[16..18], .big);
    if (cols == 0 or rows == 0 or cols > max_cols or rows > max_rows) {
        return error.InvalidResponse;
    }
    if (payload[13] == 1 and (cursor_col >= cols or cursor_row >= rows)) return error.InvalidResponse;
    return .{
        .allocator = allocator,
        .text = try allocator.dupe(u8, payload[22..]),
        .publication = std.mem.readInt(u64, payload[0..8], .big),
        .cols = cols,
        .rows = rows,
        .alternate_screen = payload[12] == 1,
        .cursor_visible = payload[13] == 1,
        .cursor_col = cursor_col,
        .cursor_row = cursor_row,
    };
}

fn decodeResize(payload: []const u8, requested_cols: u16, requested_rows: u16) ClientError!ResizeResult {
    if (payload.len != 21 or payload[16] > 1) return error.InvalidResponse;
    const result = ResizeResult{
        .admission_sequence = std.mem.readInt(u64, payload[0..8], .big),
        .geometry_sequence = std.mem.readInt(u64, payload[8..16], .big),
        .changed = payload[16] == 1,
        .cols = std.mem.readInt(u16, payload[17..19], .big),
        .rows = std.mem.readInt(u16, payload[19..21], .big),
    };
    if (result.cols == 0 or result.rows == 0 or
        result.cols > max_cols or result.rows > max_rows or
        result.cols != requested_cols or result.rows != requested_rows)
    {
        return error.InvalidResponse;
    }
    return result;
}

fn encodeControlSignal(value: ControlSignal) u8 {
    return switch (value) {
        .hangup => 1,
        .interrupt => 2,
        .terminate => 15,
        .kill => 9,
        .resize_notify => unreachable,
    };
}

fn decodeSignal(payload: []const u8, requested: ControlSignal) ClientError!SignalResult {
    if (payload.len != 10) return error.InvalidResponse;
    const result = SignalResult{
        .admission_sequence = std.mem.readInt(u64, payload[0..8], .big),
        .signal = switch (payload[8]) {
            1 => .hangup,
            2 => .interrupt,
            15 => .terminate,
            9 => .kill,
            else => return error.InvalidResponse,
        },
        .outcome = switch (payload[9]) {
            1 => .delivered,
            2 => .target_missing,
            3 => .state_probe_failed,
            4 => .permission_denied,
            5 => .native_signal_failed,
            else => return error.InvalidResponse,
        },
    };
    if (result.signal != requested) return error.InvalidResponse;
    return result;
}

fn decodeOutput(allocator: std.mem.Allocator, payload: []const u8) ClientError!LogicalOutputResult {
    if (payload.len == 0) return error.InvalidResponse;
    if (payload[0] != 0) {
        return switch (payload[0]) {
            1, 2, 3 => if (payload.len == 9) switch (payload[0]) {
                1 => .{ .cursor_stale = std.mem.readInt(u64, payload[1..9], .big) },
                2 => .{ .cursor_ahead = std.mem.readInt(u64, payload[1..9], .big) },
                3 => .{ .line_too_long = std.mem.readInt(u64, payload[1..9], .big) },
                else => unreachable,
            } else error.InvalidResponse,
            4 => if (payload.len == 1) .open_line_too_long else error.InvalidResponse,
            else => error.InvalidResponse,
        };
    }
    if (payload.len < 49 or payload[35] > 1 or payload[36] > 1) return error.InvalidResponse;
    const text_len = std.mem.readInt(u32, payload[37..41], .big);
    const open_len = std.mem.readInt(u32, payload[41..45], .big);
    const loss_count = std.mem.readInt(u32, payload[45..49], .big);
    const loss_bytes = std.math.mul(usize, loss_count, 17) catch return error.InvalidResponse;
    const content = std.math.add(usize, text_len, open_len) catch return error.InvalidResponse;
    const expected = std.math.add(usize, 49 + loss_bytes, content) catch return error.InvalidResponse;
    if (expected != payload.len) return error.InvalidResponse;
    const text = try allocator.dupe(u8, payload[49..][0..text_len]);
    errdefer allocator.free(text);
    const open_start = 49 + text_len;
    const open_line = try allocator.dupe(u8, payload[open_start..][0..open_len]);
    errdefer allocator.free(open_line);
    const losses = try allocator.alloc(LogicalOutputLoss, loss_count);
    errdefer allocator.free(losses);
    var offset = open_start + open_len;
    for (losses) |*loss| {
        if (payload[offset + 16] != 1) return error.InvalidResponse;
        loss.* = .{
            .id = std.mem.readInt(u64, payload[offset..][0..8], .big),
            .byte_count = std.math.cast(
                usize,
                std.mem.readInt(u64, payload[offset + 8 ..][0..8], .big),
            ) orelse return error.InvalidResponse,
            .reason = .line_too_long,
        };
        offset += 17;
    }
    return .{ .output = .{
        .allocator = allocator,
        .text = text,
        .open_line = open_line,
        .open_line_omitted = payload[36] == 1,
        .losses = losses,
        .oldest = std.mem.readInt(u64, payload[1..9], .big),
        .cursor = std.mem.readInt(u64, payload[9..17], .big),
        .newest = std.mem.readInt(u64, payload[17..25], .big),
        .publication = std.mem.readInt(u64, payload[25..33], .big),
        .line_count = std.mem.readInt(u16, payload[33..35], .big),
        .more = payload[35] == 1,
    } };
}

// Bounded input-batch wire codec.

/// Owns decoded borrowed events until request execution finishes.
pub const DecodedBatch = struct {
    allocator: std.mem.Allocator,
    events: []BatchEvent,

    pub fn deinit(self: *DecodedBatch) void {
        self.allocator.free(self.events);
        self.* = undefined;
    }
};

fn encodeBatch(allocator: std.mem.Allocator, events: []const BatchEvent) ClientError![]u8 {
    try validateBatchBound(events);
    if (events.len == 0 or events.len > max_send_events) return error.InvalidPayload;
    var length: usize = 2;
    for (events) |event| {
        length = std.math.add(usize, length, 2) catch return error.InputLimit;
        const body: usize = switch (event.input) {
            .bytes => |bytes| 5 + bytes.len,
            .paste => |bytes| 5 + bytes.len,
            .focus => 2,
            .key => |key| 14 + @tagName(key.key).len + key.legacy_text.len + key.text.len +
                switch (key.key) {
                    .named => |name| 1 + @tagName(name).len,
                    .unicode => 4,
                },
            .mouse => 22,
        };
        length = std.math.add(usize, length, body) catch return error.InputLimit;
    }
    if (length > max_request_bytes) return error.InputLimit;
    const bytes = try allocator.alloc(u8, length);
    errdefer allocator.free(bytes);
    std.mem.writeInt(u16, bytes[0..2], @intCast(events.len), .big);
    var offset: usize = 2;
    for (events) |event| {
        std.mem.writeInt(u16, bytes[offset..][0..2], event.delay_ms, .big);
        offset += 2;
        switch (event.input) {
            .bytes => |value| offset = writeWireBytes(bytes, offset, 1, value),
            .paste => |value| offset = writeWireBytes(bytes, offset, 2, value),
            .focus => |value| {
                bytes[offset] = 3;
                bytes[offset + 1] = if (value == .in) 1 else 0;
                offset += 2;
            },
            .key => |value| offset = encodeWireKey(bytes, offset, value),
            .mouse => |value| offset = encodeWireMouse(bytes, offset, value),
        }
    }
    std.debug.assert(offset == bytes.len);
    return bytes;
}

fn writeWireBytes(buffer: []u8, offset_value: usize, tag: u8, value: []const u8) usize {
    var offset = offset_value;
    buffer[offset] = tag;
    std.mem.writeInt(u32, buffer[offset + 1 ..][0..4], @intCast(value.len), .big);
    @memcpy(buffer[offset + 5 ..][0..value.len], value);
    offset += 5 + value.len;
    return offset;
}

fn encodeWireKey(buffer: []u8, offset_value: usize, value: KeyInput) usize {
    var offset = offset_value;
    buffer[offset] = 4;
    offset += 1;
    const identity_name = @tagName(value.key);
    buffer[offset] = @intCast(identity_name.len);
    offset += 1;
    @memcpy(buffer[offset..][0..identity_name.len], identity_name);
    offset += identity_name.len;
    switch (value.key) {
        .named => |name| {
            const text = @tagName(name);
            buffer[offset] = @intCast(text.len);
            offset += 1;
            @memcpy(buffer[offset..][0..text.len], text);
            offset += text.len;
        },
        .unicode => |scalar| {
            std.mem.writeInt(u32, buffer[offset..][0..4], scalar.value, .big);
            offset += 4;
        },
    }
    buffer[offset] = encodeModifiers(value.mods);
    buffer[offset + 1] = switch (value.action) {
        .press => 1,
        .repeat => 2,
        .release => 3,
    };
    std.mem.writeInt(u32, buffer[offset + 2 ..][0..4], value.shifted orelse std.math.maxInt(u32), .big);
    std.mem.writeInt(u32, buffer[offset + 6 ..][0..4], value.alternate orelse std.math.maxInt(u32), .big);
    buffer[offset + 10] = @intCast(value.legacy_text.len);
    buffer[offset + 11] = @intCast(value.text.len);
    offset += 12;
    @memcpy(buffer[offset..][0..value.legacy_text.len], value.legacy_text);
    offset += value.legacy_text.len;
    @memcpy(buffer[offset..][0..value.text.len], value.text);
    return offset + value.text.len;
}

fn encodeWireMouse(buffer: []u8, offset_value: usize, value: MouseInput) usize {
    const offset = offset_value;
    buffer[offset] = 5;
    buffer[offset + 1] = switch (value.kind) {
        .press => 1,
        .release => 2,
        .move => 3,
        .wheel => 4,
    };
    buffer[offset + 2] = switch (value.button) {
        .none => 0,
        .left => 1,
        .middle => 2,
        .right => 3,
        .wheel_up => 4,
        .wheel_down => 5,
    };
    std.mem.writeInt(i32, buffer[offset + 3 ..][0..4], value.row, .big);
    std.mem.writeInt(u16, buffer[offset + 7 ..][0..2], value.col, .big);
    std.mem.writeInt(u32, buffer[offset + 9 ..][0..4], value.pixel_x orelse std.math.maxInt(u32), .big);
    std.mem.writeInt(u32, buffer[offset + 13 ..][0..4], value.pixel_y orelse std.math.maxInt(u32), .big);
    buffer[offset + 17] = encodeModifiers(value.mod);
    buffer[offset + 18] = value.buttons_down;
    @memset(buffer[offset + 19 .. offset + 22], 0);
    return offset + 22;
}

/// Decodes and validates one complete bounded event batch payload.
pub fn decodeBatch(
    allocator: std.mem.Allocator,
    payload: []const u8,
) (std.mem.Allocator.Error || error{ InvalidPayload, InputLimit })!DecodedBatch {
    if (payload.len < 2) return error.InvalidPayload;
    const count = std.mem.readInt(u16, payload[0..2], .big);
    if (count == 0 or count > max_send_events) return error.InvalidPayload;
    const events = try allocator.alloc(BatchEvent, count);
    errdefer allocator.free(events);
    var offset: usize = 2;
    for (events) |*event| {
        if (offset + 3 > payload.len) return error.InvalidPayload;
        event.delay_ms = std.mem.readInt(u16, payload[offset..][0..2], .big);
        offset += 2;
        event.input = switch (payload[offset]) {
            1 => .{ .bytes = try readWireBytes(payload, &offset) },
            2 => .{ .paste = try readWireBytes(payload, &offset) },
            3 => blk: {
                offset += 1;
                if (offset >= payload.len or payload[offset] > 1) return error.InvalidPayload;
                const value: FocusInput = if (payload[offset] == 1) .in else .out;
                offset += 1;
                break :blk .{ .focus = value };
            },
            4 => .{ .key = try decodeWireKey(payload, &offset) },
            5 => .{ .mouse = try decodeWireMouse(payload, &offset) },
            else => return error.InvalidPayload,
        };
    }
    if (offset != payload.len) return error.InvalidPayload;
    try validateBatchBound(events);
    return .{ .allocator = allocator, .events = events };
}

fn readWireBytes(payload: []const u8, offset: *usize) error{InvalidPayload}![]const u8 {
    offset.* += 1;
    if (offset.* + 4 > payload.len) return error.InvalidPayload;
    const length = std.mem.readInt(u32, payload[offset.*..][0..4], .big);
    offset.* += 4;
    if (length > payload.len - offset.*) return error.InvalidPayload;
    const value = payload[offset.*..][0..length];
    offset.* += length;
    return value;
}

fn decodeWireKey(payload: []const u8, offset: *usize) error{InvalidPayload}!KeyInput {
    offset.* += 1;
    const identity_name = try readTinyString(payload, offset);
    const key: KeyIdentity = if (std.mem.eql(u8, identity_name, "named")) blk: {
        const name = std.meta.stringToEnum(NamedKey, try readTinyString(payload, offset)) orelse
            return error.InvalidPayload;
        break :blk .{ .named = name };
    } else if (std.mem.eql(u8, identity_name, "unicode")) blk: {
        if (offset.* + 4 > payload.len) return error.InvalidPayload;
        const scalar = std.mem.readInt(u32, payload[offset.*..][0..4], .big);
        offset.* += 4;
        break :blk KeyIdentity.initUnicode(std.math.cast(u21, scalar) orelse return error.InvalidPayload) catch
            return error.InvalidPayload;
    } else return error.InvalidPayload;
    if (offset.* + 12 > payload.len) return error.InvalidPayload;
    const mods = decodeModifiers(payload[offset.*]);
    const action: KeyAction = switch (payload[offset.* + 1]) {
        1 => .press,
        2 => .repeat,
        3 => .release,
        else => return error.InvalidPayload,
    };
    const shifted = decodeOptionalScalar(std.mem.readInt(u32, payload[offset.* + 2 ..][0..4], .big)) catch
        return error.InvalidPayload;
    const alternate = decodeOptionalScalar(std.mem.readInt(u32, payload[offset.* + 6 ..][0..4], .big)) catch
        return error.InvalidPayload;
    const legacy_len = payload[offset.* + 10];
    const text_len = payload[offset.* + 11];
    offset.* += 12;
    if (@as(usize, legacy_len) + text_len > payload.len - offset.*) return error.InvalidPayload;
    const legacy = payload[offset.*..][0..legacy_len];
    offset.* += legacy_len;
    const text = payload[offset.*..][0..text_len];
    offset.* += text_len;
    return .{
        .key = key,
        .mods = mods,
        .action = action,
        .shifted = shifted,
        .alternate = alternate,
        .legacy_text = legacy,
        .text = text,
    };
}

fn readTinyString(payload: []const u8, offset: *usize) error{InvalidPayload}![]const u8 {
    if (offset.* >= payload.len) return error.InvalidPayload;
    const length = payload[offset.*];
    offset.* += 1;
    if (length > payload.len - offset.*) return error.InvalidPayload;
    const value = payload[offset.*..][0..length];
    offset.* += length;
    return value;
}

fn decodeOptionalScalar(value: u32) error{InvalidPayload}!?u21 {
    if (value == std.math.maxInt(u32)) return null;
    const scalar = std.math.cast(u21, value) orelse return error.InvalidPayload;
    if (!std.unicode.utf8ValidCodepoint(scalar)) return error.InvalidPayload;
    return scalar;
}

fn decodeWireMouse(payload: []const u8, offset: *usize) error{InvalidPayload}!MouseInput {
    if (offset.* + 22 > payload.len) return error.InvalidPayload;
    const start = offset.*;
    if (!std.mem.allEqual(u8, payload[start + 19 .. start + 22], 0)) return error.InvalidPayload;
    offset.* += 22;
    return .{
        .kind = switch (payload[start + 1]) {
            1 => .press,
            2 => .release,
            3 => .move,
            4 => .wheel,
            else => return error.InvalidPayload,
        },
        .button = switch (payload[start + 2]) {
            0 => .none,
            1 => .left,
            2 => .middle,
            3 => .right,
            4 => .wheel_up,
            5 => .wheel_down,
            else => return error.InvalidPayload,
        },
        .row = std.mem.readInt(i32, payload[start + 3 ..][0..4], .big),
        .col = std.mem.readInt(u16, payload[start + 7 ..][0..2], .big),
        .pixel_x = decodeOptionalU32(std.mem.readInt(u32, payload[start + 9 ..][0..4], .big)),
        .pixel_y = decodeOptionalU32(std.mem.readInt(u32, payload[start + 13 ..][0..4], .big)),
        .mod = decodeModifiers(payload[start + 17]),
        .buttons_down = payload[start + 18],
    };
}

fn decodeOptionalU32(value: u32) ?u32 {
    return if (value == std.math.maxInt(u32)) null else value;
}

fn encodeModifiers(value: Modifiers) u8 {
    return @as(u8, @intFromBool(value.shift)) |
        (@as(u8, @intFromBool(value.alt)) << 1) |
        (@as(u8, @intFromBool(value.control)) << 2) |
        (@as(u8, @intFromBool(value.super)) << 3) |
        (@as(u8, @intFromBool(value.hyper)) << 4) |
        (@as(u8, @intFromBool(value.meta)) << 5) |
        (@as(u8, @intFromBool(value.caps_lock)) << 6) |
        (@as(u8, @intFromBool(value.num_lock)) << 7);
}

fn decodeModifiers(value: u8) Modifiers {
    return .{
        .shift = value & 1 != 0,
        .alt = value & 2 != 0,
        .control = value & 4 != 0,
        .super = value & 8 != 0,
        .hyper = value & 16 != 0,
        .meta = value & 32 != 0,
        .caps_lock = value & 64 != 0,
        .num_lock = value & 128 != 0,
    };
}

// Fixed request and response framing.

/// Names the six primitive protocol-v1 operations.
pub const Operation = enum(u8) {
    status = 1,
    send = 2,
    screen = 3,
    output = 4,
    resize = 5,
    signal = 6,
};

/// Retains one validated request header before payload admission.
pub const Request = struct {
    operation: Operation,
    terminal_id: TerminalId,
    payload_len: usize,
};

/// Reports exact hostile or unsupported request-header evidence.
pub const RequestError = error{
    BadMagic,
    InvalidPayload,
    Oversized,
    UnknownOperation,
    WrongVersion,
};

/// Fixes every protocol-v1 success and rejection status value.
pub const ResponseStatus = enum(u8) {
    ok = 0,
    bad_magic = 1,
    wrong_version = 2,
    unknown_operation = 3,
    oversized = 4,
    truncated = 5,
    wrong_terminal = 6,
    unauthorized = 7,
    invalid_payload = 8,
    reserved_9 = 9,
    screen_limit = 10,
    internal_failure = 11,
    input_limit = 12,
    invalid_utf8 = 13,
    invalid_text = 14,
    key_text_limit = 15,
    length_overflow = 16,
    out_of_memory = 17,
    consequence_limit = 18,
    resize_rollback_failed = 19,
    frame_borrowed = 20,
};

const WireState = enum(u8) { running = 0, stopped = 1, failed = 2 };

fn encodeWireState(state: State) u8 {
    return @intFromEnum(switch (state) {
        .running => WireState.running,
        .stopped => WireState.stopped,
        .failed => WireState.failed,
    });
}

fn decodeWireState(byte: u8) ?State {
    return switch (byte) {
        @intFromEnum(WireState.running) => .running,
        @intFromEnum(WireState.stopped) => .stopped,
        @intFromEnum(WireState.failed) => .failed,
        else => null,
    };
}

/// Borrows one encoded response payload through a complete transfer.
pub const Response = struct {
    operation: Operation,
    terminal_id: TerminalId,
    payload: []const u8,
};

const DecodedResponse = struct {
    payload_len: usize,
};

/// Decodes one complete fixed request header and rejects reserved values.
pub fn decodeRequestHeader(bytes: *const [request_header_bytes]u8) RequestError!Request {
    if (!std.mem.eql(u8, bytes[0..4], "QTRM")) return error.BadMagic;
    if (std.mem.readInt(u16, bytes[4..6], .big) != protocol_version) return error.WrongVersion;
    const operation: Operation = switch (bytes[6]) {
        1 => .status,
        2 => .send,
        3 => .screen,
        4 => .output,
        5 => .resize,
        6 => .signal,
        else => return error.UnknownOperation,
    };
    if (bytes[7] != 0) return error.InvalidPayload;
    const payload_len = std.mem.readInt(u32, bytes[24..28], .big);
    if (payload_len > max_request_bytes) return error.Oversized;
    return .{
        .operation = operation,
        .terminal_id = .{ .bytes = bytes[8..24].* },
        .payload_len = payload_len,
    };
}

fn encodeRequestHeader(buffer: *[request_header_bytes]u8, operation: Operation, id: TerminalId, len: usize) void {
    @memcpy(buffer[0..4], "QTRM");
    std.mem.writeInt(u16, buffer[4..6], protocol_version, .big);
    buffer[6] = @intFromEnum(operation);
    buffer[7] = 0;
    @memcpy(buffer[8..24], &id.bytes);
    std.mem.writeInt(u32, buffer[24..28], @intCast(len), .big);
}

fn decodeResponseHeader(
    bytes: *const [response_header_bytes]u8,
    expected_id: TerminalId,
    expected_operation: Operation,
) ClientError!DecodedResponse {
    if (!std.mem.eql(u8, bytes[0..4], "QTRS")) return error.BadMagic;
    if (std.mem.readInt(u16, bytes[4..6], .big) != protocol_version) return error.WrongVersion;
    if (!std.mem.eql(u8, bytes[8..24], &expected_id.bytes)) return error.WrongTerminal;
    if (bytes[7] != @intFromEnum(expected_operation) and
        !(bytes[6] != @intFromEnum(ResponseStatus.ok) and bytes[7] == 0))
        return error.InvalidResponse;
    if (!std.mem.allEqual(u8, bytes[24..40], 0) or
        !std.mem.allEqual(u8, bytes[44..56], 0)) return error.InvalidResponse;
    const payload_len = std.mem.readInt(u32, bytes[40..44], .big);
    if (payload_len > max_output_response_bytes) return error.ResponseLimit;
    if (bytes[6] != @intFromEnum(ResponseStatus.ok)) {
        if (payload_len != 0) return error.InvalidResponse;
        return switch (bytes[6]) {
            @intFromEnum(ResponseStatus.wrong_terminal) => error.WrongTerminal,
            @intFromEnum(ResponseStatus.unauthorized) => error.Unauthorized,
            @intFromEnum(ResponseStatus.invalid_payload),
            @intFromEnum(ResponseStatus.truncated),
            @intFromEnum(ResponseStatus.oversized),
            @intFromEnum(ResponseStatus.bad_magic),
            @intFromEnum(ResponseStatus.unknown_operation),
            => error.InvalidPayload,
            @intFromEnum(ResponseStatus.wrong_version) => error.WrongVersion,
            @intFromEnum(ResponseStatus.input_limit) => error.InputLimit,
            @intFromEnum(ResponseStatus.invalid_utf8) => error.InvalidUtf8,
            @intFromEnum(ResponseStatus.invalid_text) => error.InvalidText,
            @intFromEnum(ResponseStatus.key_text_limit) => error.KeyTextLimit,
            @intFromEnum(ResponseStatus.length_overflow) => error.LengthOverflow,
            @intFromEnum(ResponseStatus.out_of_memory) => error.OutOfMemory,
            @intFromEnum(ResponseStatus.consequence_limit) => error.ConsequenceLimit,
            @intFromEnum(ResponseStatus.resize_rollback_failed) => error.ResizeRollbackFailed,
            @intFromEnum(ResponseStatus.frame_borrowed) => error.FrameBorrowed,
            else => error.RemoteRejected,
        };
    }
    return .{ .payload_len = payload_len };
}

fn encodeResponseHeader(
    header: *[response_header_bytes]u8,
    terminal_id: TerminalId,
    operation: ?Operation,
    status: ResponseStatus,
    payload_len: usize,
) void {
    @memcpy(header[0..4], "QTRS");
    std.mem.writeInt(u16, header[4..6], protocol_version, .big);
    header[6] = @intFromEnum(status);
    header[7] = if (operation) |value| @intFromEnum(value) else 0;
    @memcpy(header[8..24], &terminal_id.bytes);
    @memset(header[24..40], 0);
    std.mem.writeInt(u32, header[40..44], @intCast(payload_len), .big);
    @memset(header[44..56], 0);
}

/// Writes one complete success header and payload under a single deadline.
pub fn writeResponse(io: std.Io, peer: *net.Stream, response: Response) !void {
    var header: [response_header_bytes]u8 = undefined;
    encodeResponseHeader(
        &header,
        response.terminal_id,
        response.operation,
        .ok,
        response.payload.len,
    );
    const started = std.Io.Clock.awake.now(io);
    try writeExact(io, peer.socket.handle, &header, started, transfer_timeout_ms);
    try writeExact(io, peer.socket.handle, response.payload, started, transfer_timeout_ms);
}

/// Writes one payload-free rejection carrying the owned terminal identity.
pub fn writeFailure(
    io: std.Io,
    peer: *net.Stream,
    id: TerminalId,
    operation: ?Operation,
    status: ResponseStatus,
) !void {
    var header: [response_header_bytes]u8 = undefined;
    encodeResponseHeader(&header, id, operation, status, 0);
    try writeExact(
        io,
        peer.socket.handle,
        &header,
        std.Io.Clock.awake.now(io),
        transfer_timeout_ms,
    );
}

// Linux local transport, deadlines, and same-user admission.

fn connectLinux(io: std.Io, path: []const u8) ClientError!net.Stream {
    if (builtin.os.tag != .linux) return error.ConnectFailed;
    if (path.len >= net.UnixAddress.max_len) return error.EndpointPathTooLong;
    const socket_result = linux.socket(
        linux.AF.UNIX,
        linux.SOCK.STREAM | linux.SOCK.CLOEXEC | linux.SOCK.NONBLOCK,
        0,
    );
    if (linux.errno(socket_result) != .SUCCESS) return error.ConnectFailed;
    const fd: posix.fd_t = @intCast(socket_result);
    errdefer (std.Io.File{ .handle = fd, .flags = .{ .nonblocking = true } }).close(io);

    var address: linux.sockaddr.un = undefined;
    address.family = linux.AF.UNIX;
    @memset(&address.path, 0);
    @memcpy(address.path[0..path.len], path);
    const address_len: linux.socklen_t = @intCast(@offsetOf(linux.sockaddr.un, "path") + path.len + 1);
    const result = linux.connect(fd, @ptrCast(&address), address_len);
    switch (linux.errno(result)) {
        .SUCCESS => {},
        // Zig 0.16's Unix connector omits ECONNREFUSED and reports a stale
        // pathname as Unexpected. This seam retains both exact closed meanings.
        .NOENT, .CONNREFUSED => return error.TerminalClosed,
        .INPROGRESS, .AGAIN => {
            const started = std.Io.Clock.awake.now(io);
            waitSocket(io, fd, posix.POLL.OUT, started, transfer_timeout_ms) catch |failure|
                return transportClientError(failure, error.ConnectFailed);
            switch (socketError(fd) catch return error.ConnectFailed) {
                .SUCCESS => {},
                .NOENT, .CONNREFUSED => return error.TerminalClosed,
                else => return error.ConnectFailed,
            }
        },
        else => return error.ConnectFailed,
    }
    return .{ .socket = .{ .handle = fd, .address = .{ .ip4 = .loopback(0) } } };
}

/// Enables meaningful bounded EAGAIN handling on one accepted Linux peer.
pub fn setNonblocking(fd: posix.fd_t) !void {
    const get_result = linux.fcntl(fd, linux.F.GETFL, 0);
    if (linux.errno(get_result) != .SUCCESS) return error.GetFlagsFailed;
    const nonblocking: u32 = @bitCast(linux.O{ .NONBLOCK = true });
    const set_result = linux.fcntl(fd, linux.F.SETFL, get_result | nonblocking);
    if (linux.errno(set_result) != .SUCCESS) return error.SetFlagsFailed;
}

fn socketError(fd: posix.fd_t) !linux.E {
    var value: c_int = 0;
    var length: linux.socklen_t = @sizeOf(c_int);
    const result = linux.getsockopt(
        fd,
        linux.SOL.SOCKET,
        linux.SO.ERROR,
        std.mem.asBytes(&value).ptr,
        &length,
    );
    if (linux.errno(result) != .SUCCESS or length != @sizeOf(c_int)) {
        return error.SocketErrorReadFailed;
    }
    return @enumFromInt(value);
}

// This process-local classifier preserves timeout across the inferred poll and
// syscall union without restating unrelated transport implementation errors.
fn transportClientError(failure: anyerror, fallback: ClientError) ClientError {
    return if (failure == error.Timeout) error.Timeout else fallback;
}

/// Reconstructs an exact fixed-size or bounded payload across stream fragments.
pub fn readExact(
    io: std.Io,
    fd: posix.fd_t,
    bytes: []u8,
    started: std.Io.Timestamp,
    timeout_ms: i32,
) !void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        try waitSocket(io, fd, posix.POLL.IN, started, timeout_ms);
        const result = linux.recvfrom(fd, bytes[offset..].ptr, bytes.len - offset, 0, null, null);
        switch (linux.errno(result)) {
            .SUCCESS => {
                if (result == 0) return error.EndOfStream;
                offset += result;
            },
            .INTR, .AGAIN => continue,
            else => return error.ReadFailed,
        }
    }
}

/// Transfers a complete bounded frame without blocking beyond its deadline.
pub fn writeExact(
    io: std.Io,
    fd: posix.fd_t,
    bytes: []const u8,
    started: std.Io.Timestamp,
    timeout_ms: i32,
) !void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        try waitSocket(io, fd, posix.POLL.OUT, started, timeout_ms);
        const result = linux.sendto(fd, bytes[offset..].ptr, bytes.len - offset, linux.MSG.NOSIGNAL, null, 0);
        switch (linux.errno(result)) {
            .SUCCESS => {
                if (result == 0) return error.EndOfStream;
                offset += result;
            },
            .INTR, .AGAIN => continue,
            else => return error.WriteFailed,
        }
    }
}

fn waitSocket(
    io: std.Io,
    fd: posix.fd_t,
    event: i16,
    started: std.Io.Timestamp,
    timeout_ms: i32,
) !void {
    const elapsed = started.durationTo(std.Io.Clock.awake.now(io)).toMilliseconds();
    if (elapsed >= timeout_ms) return error.Timeout;
    var descriptor = [_]posix.pollfd{.{
        .fd = fd,
        .events = event | posix.POLL.HUP,
        .revents = 0,
    }};
    const ready = posix.poll(&descriptor, timeout_ms - @as(i32, @intCast(elapsed))) catch
        return error.PollFailed;
    if (ready == 0) return error.Timeout;
    if ((descriptor[0].revents & (event | posix.POLL.HUP)) == 0) return error.PollFailed;
}

const Ucred = extern struct { pid: linux.pid_t, uid: linux.uid_t, gid: linux.gid_t };

/// Reads Linux peer credentials for same-effective-UID admission.
pub fn peerUid(fd: posix.fd_t) !linux.uid_t {
    var credentials: Ucred = undefined;
    var length: linux.socklen_t = @sizeOf(Ucred);
    const result = linux.getsockopt(
        fd,
        linux.SOL.SOCKET,
        linux.SO.PEERCRED,
        std.mem.asBytes(&credentials).ptr,
        &length,
    );
    if (linux.errno(result) != .SUCCESS or length != @sizeOf(Ucred)) {
        return error.PeerCredentialsFailed;
    }
    return credentials.uid;
}

/// Accepts only a present peer identity equal to the process effective user.
pub fn admitUid(owner: linux.uid_t, peer: ?linux.uid_t) bool {
    return peer != null and owner == peer.?;
}

/// Interrupts active socket waits without taking descriptor close ownership.
pub fn shutdownSocket(fd: posix.fd_t) void {
    if (fd < 0) return;
    const result = posix.system.shutdown(fd, posix.SHUT.RDWR);
    switch (posix.errno(result)) {
        .SUCCESS, .NOTCONN, .BADF => {},
        else => {}, // Close remains the owner; shutdown only requests cancellation.
    }
}

test "terminal identity and endpoint filename have one canonical representation" {
    const id = TerminalId{ .bytes = .{0x5a} ** 16 };
    var text: [32]u8 = undefined;
    var filename: [37]u8 = undefined;
    try std.testing.expectEqual(id, try TerminalId.parse(id.format(&text)));
    try std.testing.expectEqual(id, try TerminalId.parseEndpoint(id.formatEndpoint(&filename)));
    try std.testing.expectError(error.InvalidTerminalId, TerminalId.parse("5A" ** 16));
    try std.testing.expectError(error.InvalidTerminalId, TerminalId.parse("00" ** 16));
    try std.testing.expectError(error.InvalidTerminalId, TerminalId.parseEndpoint("unrelated.sock"));

    var client = try Client.init(std.testing.allocator, std.testing.io, "/run/user/1000", id);
    defer client.deinit();
    try std.testing.expectEqualStrings(
        "/run/user/1000/howl/5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a.sock",
        client.endpoint_path,
    );
}

test "request framing survives fragmented assembly and rejects bad bounds" {
    const id = TerminalId{ .bytes = .{0x5a} ** 16 };
    var header: [request_header_bytes]u8 = undefined;
    encodeRequestHeader(&header, .send, id, 3);
    const request = try decodeRequestHeader(&header);
    try std.testing.expectEqual(Operation.send, request.operation);
    try std.testing.expectEqual(id, request.terminal_id);
    try std.testing.expectEqual(3, request.payload_len);

    std.mem.writeInt(u32, header[24..28], max_request_bytes + 1, .big);
    try std.testing.expectError(error.Oversized, decodeRequestHeader(&header));
    std.mem.writeInt(u32, header[24..28], 0, .big);
    std.mem.writeInt(u16, header[4..6], protocol_version + 1, .big);
    try std.testing.expectError(error.WrongVersion, decodeRequestHeader(&header));
    std.mem.writeInt(u16, header[4..6], protocol_version, .big);
    header[0] = 'x';
    try std.testing.expectError(error.BadMagic, decodeRequestHeader(&header));
}

test "binary event batch retains every input family and exact modifiers" {
    const events = [_]BatchEvent{
        .{ .input = .{ .bytes = "a\x00\x1b" } },
        .{ .input = .{ .paste = "paste" }, .delay_ms = 7 },
        .{ .input = .{ .focus = .in } },
        .{ .input = .{ .key = .{
            .key = try KeyIdentity.initUnicode('w'),
            .mods = .{ .control = true, .num_lock = true },
            .action = .repeat,
            .shifted = 'W',
            .alternate = 'w',
            .legacy_text = "",
            .text = "w",
        } } },
        .{ .input = .{ .mouse = .{
            .kind = .press,
            .button = .left,
            .row = 2,
            .col = 3,
            .pixel_x = 20,
            .pixel_y = 30,
            .mod = .{ .alt = true },
            .buttons_down = 1,
        } } },
    };
    const encoded = try encodeBatch(std.testing.allocator, &events);
    defer std.testing.allocator.free(encoded);
    var decoded = try decodeBatch(std.testing.allocator, encoded);
    defer decoded.deinit();
    try std.testing.expectEqual(events.len, decoded.events.len);
    try std.testing.expectEqualStrings("a\x00\x1b", decoded.events[0].input.bytes);
    try std.testing.expectEqual(@as(u16, 7), decoded.events[1].delay_ms);
    try std.testing.expectEqual(FocusInput.in, decoded.events[2].input.focus);
    try std.testing.expect(decoded.events[3].input.key.mods.control);
    try std.testing.expect(decoded.events[3].input.key.mods.num_lock);
    try std.testing.expectEqual(KeyAction.repeat, decoded.events[3].input.key.action);
    try std.testing.expectEqual(@as(i32, 2), decoded.events[4].input.mouse.row);
    try std.testing.expectEqual(@as(?u32, 30), decoded.events[4].input.mouse.pixel_y);
}

test "binary event batch rejects trailing and reserved mouse bytes" {
    const encoded = try encodeBatch(std.testing.allocator, &.{.{ .input = .{ .mouse = .{
        .kind = .move,
        .button = .none,
        .row = 0,
        .col = 0,
        .mod = .{},
        .buttons_down = 0,
    } } }});
    defer std.testing.allocator.free(encoded);
    const trailing = try std.testing.allocator.alloc(u8, encoded.len + 1);
    defer std.testing.allocator.free(trailing);
    @memcpy(trailing[0..encoded.len], encoded);
    trailing[encoded.len] = 0;
    try std.testing.expectError(error.InvalidPayload, decodeBatch(std.testing.allocator, trailing));
    encoded[encoded.len - 1] = 1;
    try std.testing.expectError(error.InvalidPayload, decodeBatch(std.testing.allocator, encoded));
}

test "exact input framing preserves NUL and escape bytes" {
    const id = TerminalId{ .bytes = .{0xa5} ** 16 };
    const payload = "a\x00\x1b[b";
    var bytes: [request_header_bytes + payload.len]u8 = undefined;
    encodeRequestHeader(bytes[0..request_header_bytes], .send, id, payload.len);
    @memcpy(bytes[request_header_bytes..], payload);
    const request = try decodeRequestHeader(bytes[0..request_header_bytes]);
    try std.testing.expectEqualStrings(payload, bytes[request_header_bytes..][0..request.payload_len]);
}

test "request framing rejects nonzero reserved bytes" {
    const id = TerminalId{ .bytes = .{0x31} ** 16 };
    var header: [request_header_bytes]u8 = undefined;
    encodeRequestHeader(&header, .status, id, 0);
    header[7] = 1;
    try std.testing.expectError(error.InvalidPayload, decodeRequestHeader(&header));
}

test "response framing rejects a different terminal identity" {
    const expected = TerminalId{ .bytes = .{1} ** 16 };
    const other = TerminalId{ .bytes = .{2} ** 16 };
    var header: [response_header_bytes]u8 = @splat(0);
    @memcpy(header[0..4], "QTRS");
    std.mem.writeInt(u16, header[4..6], protocol_version, .big);
    @memcpy(header[8..24], &other.bytes);
    try std.testing.expectError(error.WrongTerminal, decodeResponseHeader(&header, expected, .status));
}

test "wire status and lifecycle values remain protocol v1 constants" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(ResponseStatus.ok));
    try std.testing.expectEqual(@as(u8, 11), @intFromEnum(ResponseStatus.internal_failure));
    try std.testing.expectEqual(@as(u8, 19), @intFromEnum(ResponseStatus.resize_rollback_failed));
    try std.testing.expectEqual(@as(u8, 20), @intFromEnum(ResponseStatus.frame_borrowed));
    try std.testing.expectEqual(@as(u8, 0), encodeWireState(.running));
    try std.testing.expectEqual(@as(u8, 1), encodeWireState(.stopped));
    try std.testing.expectEqual(@as(u8, 2), encodeWireState(.failed));
    try std.testing.expectEqual(State.running, decodeWireState(0).?);
    try std.testing.expectEqual(State.stopped, decodeWireState(1).?);
    try std.testing.expectEqual(State.failed, decodeWireState(2).?);
    try std.testing.expectEqual(@as(?State, null), decodeWireState(3));
}

test "wire preserves resize rollback failure as an exact remote error" {
    const id = TerminalId{ .bytes = .{0x19} ** 16 };
    var header: [response_header_bytes]u8 = @splat(0);
    @memcpy(header[0..4], "QTRS");
    std.mem.writeInt(u16, header[4..6], protocol_version, .big);
    header[6] = @intFromEnum(ResponseStatus.resize_rollback_failed);
    header[7] = @intFromEnum(Operation.resize);
    @memcpy(header[8..24], &id.bytes);
    try std.testing.expectError(
        error.ResizeRollbackFailed,
        decodeResponseHeader(&header, id, .resize),
    );
}

test "unknown remote response status retains established rejection error" {
    const id = TerminalId{ .bytes = .{0x4a} ** 16 };
    var header: [response_header_bytes]u8 = @splat(0);
    @memcpy(header[0..4], "QTRS");
    std.mem.writeInt(u16, header[4..6], protocol_version, .big);
    header[6] = 0xff;
    header[7] = @intFromEnum(Operation.status);
    @memcpy(header[8..24], &id.bytes);
    try std.testing.expectError(
        error.RemoteRejected,
        decodeResponseHeader(&header, id, .status),
    );
}

test "response framing rejects hostile operation bounds and reserved values" {
    const id = TerminalId{ .bytes = .{0x72} ** 16 };
    var input: [response_header_bytes]u8 = undefined;
    encodeResponseHeader(&input, id, .send, .ok, 0);

    var hostile = input;
    hostile[24] = 1;
    try std.testing.expectError(error.InvalidResponse, decodeResponseHeader(&hostile, id, .send));
    hostile = input;
    hostile[39] = 1;
    try std.testing.expectError(error.InvalidResponse, decodeResponseHeader(&hostile, id, .send));
    hostile = input;
    hostile[44] = 1;
    try std.testing.expectError(error.InvalidResponse, decodeResponseHeader(&hostile, id, .send));
    hostile = input;
    hostile[55] = 1;
    try std.testing.expectError(error.InvalidResponse, decodeResponseHeader(&hostile, id, .send));
}

test "send response rejects impossible event and byte evidence" {
    const valid = encodeSendResult(.{
        .admission_sequence = 4,
        .input_sequence = 2,
        .completed_events = 2,
        .outcome = .{ .complete = 8 },
    });
    const decoded = try decodeSendResult(&valid, 2);
    try std.testing.expect(decoded.outcome == .complete);
    var hostile = valid;
    std.mem.writeInt(u16, hostile[16..18], 1, .big);
    try std.testing.expectError(error.InvalidResponse, decodeSendResult(&hostile, 2));
    hostile = valid;
    std.mem.writeInt(u64, hostile[19..27], max_input_bytes + 1, .big);
    try std.testing.expectError(error.InvalidResponse, decodeSendResult(&hostile, 2));
}

test "hostile status validation releases an already copied cwd" {
    const id = TerminalId{ .bytes = .{0x42} ** 16 };
    const payload = try encodeStatus(std.testing.allocator, .{
        .terminal_id = id,
        .state = .running,
        .reader_error = null,
        .reply_failure_transferred = null,
        .resize_rollback_failed = false,
        .child_cwd = "/tmp",
        .cols = 80,
        .rows = 24,
        .publication = 1,
        .history_loss_generation = 0,
        .alternate_screen = false,
        .admission_sequence = 0,
        .input_sequence = 0,
        .geometry_sequence = 0,
        .output_oldest = 1,
        .output_newest = 0,
        .shell_mark = null,
    });
    defer std.testing.allocator.free(payload);
    payload[56] = 1;
    try std.testing.expectError(
        error.InvalidResponse,
        decodeStatus(std.testing.allocator, id, payload),
    );
}

test "status wire validates lifecycle and bounded loss evidence" {
    const id = TerminalId{ .bytes = .{0x43} ** 16 };
    const payload = try encodeStatus(std.testing.allocator, .{
        .terminal_id = id,
        .state = .failed,
        .reader_error = error.PtyReplyTimedOut,
        .reply_failure_transferred = 7,
        .resize_rollback_failed = false,
        .child_cwd = null,
        .cols = 80,
        .rows = 24,
        .publication = 1,
        .history_loss_generation = 9,
        .alternate_screen = false,
        .admission_sequence = 4,
        .input_sequence = 0,
        .geometry_sequence = 0,
        .output_oldest = 1,
        .output_newest = 0,
        .shell_mark = null,
    });
    defer std.testing.allocator.free(payload);

    var decoded = try decodeStatus(std.testing.allocator, id, payload);
    defer decoded.deinit();
    try std.testing.expect(!decoded.value.resize_rollback_failed);
    try std.testing.expectEqual(@as(?usize, 7), decoded.value.reply_failure_transferred);
    try std.testing.expectEqual(@as(u64, 9), decoded.value.history_loss_generation);

    std.mem.writeInt(u32, payload[78..82], 0, .big);
    var rejected = try decodeStatus(std.testing.allocator, id, payload);
    defer rejected.deinit();
    try std.testing.expectEqual(@as(?usize, 0), rejected.value.reply_failure_transferred);

    payload[77] = 2;
    try std.testing.expectError(
        error.InvalidResponse,
        decodeStatus(std.testing.allocator, id, payload),
    );
    payload[77] = 0;
    std.mem.writeInt(u32, payload[78..82], max_input_bytes + 1, .big);
    try std.testing.expectError(
        error.InvalidResponse,
        decodeStatus(std.testing.allocator, id, payload),
    );
    std.mem.writeInt(u32, payload[78..82], std.math.maxInt(u32), .big);
    try std.testing.expectError(
        error.InvalidResponse,
        decodeStatus(std.testing.allocator, id, payload),
    );
    payload[1] = encodeReaderError(error.ModelAllocationFailed);
    std.mem.writeInt(u32, payload[78..82], 0, .big);
    try std.testing.expectError(
        error.InvalidResponse,
        decodeStatus(std.testing.allocator, id, payload),
    );

    payload[1] = 0;
    payload[77] = 1;
    std.mem.writeInt(u32, payload[78..82], std.math.maxInt(u32), .big);
    var rollback = try decodeStatus(std.testing.allocator, id, payload);
    defer rollback.deinit();
    try std.testing.expect(rollback.value.resize_rollback_failed);

    payload[0] = encodeWireState(.running);
    payload[1] = encodeReaderError(error.PtyReadFailed);
    payload[77] = 0;
    try std.testing.expectError(
        error.InvalidResponse,
        decodeStatus(std.testing.allocator, id, payload),
    );
    payload[0] = encodeWireState(.stopped);
    payload[1] = 0;
    payload[77] = 1;
    try std.testing.expectError(
        error.InvalidResponse,
        decodeStatus(std.testing.allocator, id, payload),
    );
    payload[0] = encodeWireState(.failed);
    payload[77] = 0;
    try std.testing.expectError(
        error.InvalidResponse,
        decodeStatus(std.testing.allocator, id, payload),
    );
    payload[1] = encodeReaderError(error.PtyReadFailed);
    payload[77] = 1;
    try std.testing.expectError(
        error.InvalidResponse,
        decodeStatus(std.testing.allocator, id, payload),
    );
}

test "hostile observations reject dimensions outside the owned surface bounds" {
    const id = TerminalId{ .bytes = .{0x51} ** 16 };
    const status_payload = try encodeStatus(std.testing.allocator, .{
        .terminal_id = id,
        .state = .running,
        .reader_error = null,
        .reply_failure_transferred = null,
        .resize_rollback_failed = false,
        .child_cwd = null,
        .cols = 80,
        .rows = 24,
        .publication = 0,
        .history_loss_generation = 0,
        .alternate_screen = false,
        .admission_sequence = 0,
        .input_sequence = 0,
        .geometry_sequence = 0,
        .output_oldest = 1,
        .output_newest = 0,
        .shell_mark = null,
    });
    defer std.testing.allocator.free(status_payload);
    inline for (.{
        .{ @as(u16, 0), @as(u16, 24) },
        .{ @as(u16, 80), @as(u16, 0) },
        .{ max_cols + 1, @as(u16, 24) },
        .{ @as(u16, 80), max_rows + 1 },
    }) |dimensions| {
        std.mem.writeInt(u16, status_payload[2..4], dimensions[0], .big);
        std.mem.writeInt(u16, status_payload[4..6], dimensions[1], .big);
        try std.testing.expectError(
            error.InvalidResponse,
            decodeStatus(std.testing.allocator, id, status_payload),
        );
    }

    var screen_payload: [22]u8 = @splat(0);
    inline for (.{
        .{ @as(u16, 0), @as(u16, 24) },
        .{ @as(u16, 80), @as(u16, 0) },
        .{ max_cols + 1, @as(u16, 24) },
        .{ @as(u16, 80), max_rows + 1 },
    }) |dimensions| {
        std.mem.writeInt(u16, screen_payload[8..10], dimensions[0], .big);
        std.mem.writeInt(u16, screen_payload[10..12], dimensions[1], .big);
        try std.testing.expectError(
            error.InvalidResponse,
            decodeScreen(std.testing.allocator, &screen_payload),
        );
    }
}

test "hostile mutation responses must match bounded request facts" {
    var resize_payload: [21]u8 = @splat(0);
    std.mem.writeInt(u16, resize_payload[17..19], 80, .big);
    std.mem.writeInt(u16, resize_payload[19..21], 24, .big);
    const resize = try decodeResize(&resize_payload, 80, 24);
    try std.testing.expectEqual(@as(u16, 80), resize.cols);
    try std.testing.expectEqual(@as(u16, 24), resize.rows);
    try std.testing.expectError(error.InvalidResponse, decodeResize(&resize_payload, 81, 24));
    try std.testing.expectError(error.InvalidResponse, decodeResize(&resize_payload, 80, 25));
    std.mem.writeInt(u16, resize_payload[17..19], 0, .big);
    try std.testing.expectError(error.InvalidResponse, decodeResize(&resize_payload, 0, 24));
    std.mem.writeInt(u16, resize_payload[17..19], max_cols + 1, .big);
    try std.testing.expectError(
        error.InvalidResponse,
        decodeResize(&resize_payload, max_cols + 1, 24),
    );
    std.mem.writeInt(u16, resize_payload[17..19], 80, .big);
    std.mem.writeInt(u16, resize_payload[19..21], 0, .big);
    try std.testing.expectError(error.InvalidResponse, decodeResize(&resize_payload, 80, 0));
    std.mem.writeInt(u16, resize_payload[19..21], max_rows + 1, .big);
    try std.testing.expectError(
        error.InvalidResponse,
        decodeResize(&resize_payload, 80, max_rows + 1),
    );

    var signal_payload: [10]u8 = @splat(0);
    signal_payload[8] = encodeControlSignal(.interrupt);
    signal_payload[9] = encodeControlResult(.delivered);
    const signal_result = try decodeSignal(&signal_payload, .interrupt);
    try std.testing.expectEqual(ControlSignal.interrupt, signal_result.signal);
    try std.testing.expectError(
        error.InvalidResponse,
        decodeSignal(&signal_payload, .terminate),
    );
}

test "client maps a stale endpoint pathname to terminal closed" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const runtime_dir = try testRuntimeDir();
    defer std.testing.allocator.free(runtime_dir);
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, runtime_dir) catch {};
    const id = TerminalId{ .bytes = .{0x6b} ** 16 };
    var client = try Client.init(std.testing.allocator, std.testing.io, runtime_dir, id);
    defer client.deinit();
    try std.Io.Dir.createDirPath(
        .cwd(),
        std.testing.io,
        std.fs.path.dirname(client.endpoint_path).?,
    );
    const address = try net.UnixAddress.init(client.endpoint_path);
    var server = try address.listen(std.testing.io, .{});
    server.deinit(std.testing.io);
    try std.testing.expectError(error.TerminalClosed, client.status());
}

fn testRuntimeDir() ![]u8 {
    var random: [8]u8 = undefined;
    std.testing.io.random(&random);
    return std.fmt.allocPrint(std.testing.allocator, "/tmp/howl-control-{x}", .{random});
}
