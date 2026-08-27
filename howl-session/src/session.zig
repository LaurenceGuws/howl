//! Owns one canonical PTY and VT session independently of attached observers.

const std = @import("std");
const pty = @import("howl_pty");
const vt = @import("howl_vt");

/// Shared-session wire and geometry-authority contract.
pub const protocol = @import("protocol.zig");

const write_queue_bytes: usize = 64 * 1024;
const read_buffer_bytes: usize = 16 * 1024;
const write_bytes_per_turn: usize = 64 * 1024;
const write_calls_per_turn: usize = 4;

/// Opaque handle to one canonical terminal-work owner.
pub const Session = opaque {};
/// Host-neutral input accepted by the canonical VT owner.
pub const Input = vt.Terminal.InputEvent;
/// Names physical non-Unicode key identities accepted by canonical input encoding.
pub const KeyName = vt.Terminal.NamedKey;
/// Validates Unicode or named physical-key identity.
pub const Key = vt.Terminal.Key;
/// Names one key press/repeat/release transition.
pub const KeyAction = vt.Terminal.KeyAction;
/// Copies full keyboard/mouse modifier state.
pub const InputModifier = vt.Terminal.InputModifier;
/// Names one mouse event class.
pub const MouseEventKind = vt.Terminal.MouseEventKind;
/// Names one mouse button identity.
pub const MouseButton = vt.Terminal.MouseButton;
/// Bounds committed key text accepted by the canonical VT encoder.
pub const maximum_key_text_bytes = vt.Terminal.maximum_key_text_bytes;
/// Bounds legacy key bytes while leaving canonical Meta prefix headroom.
pub const maximum_legacy_key_bytes = vt.Terminal.maximum_legacy_key_bytes;
/// Copies one complete terminal cell without exposing VT storage.
pub const Cell = vt.Terminal.Cell;
/// Copies one resolved terminal cursor shape.
pub const CursorShape = vt.Terminal.CursorShape;
/// Copies the semantic terminal-color class used by cell attributes.
pub const ColorKind = vt.Terminal.ColorKind;
/// Copies terminal palette and dynamic visual defaults.
pub const Presentation = vt.Terminal.Presentation;
/// Copies one row's DEC presentation geometry.
pub const LineGeometry = vt.Terminal.LineGeometry;
/// Maximum scalars retained by one bounded terminal grapheme.
pub const maximum_cell_scalars = vt.scalar.maximum_scalars;
/// Bounds one retained OSC 8 hyperlink target in bytes.
pub const maximum_hyperlink_uri_bytes = vt.Terminal.maximum_hyperlink_uri_bytes;
/// Bounds stable one-based OSC 8 hyperlink identities.
pub const maximum_hyperlinks = vt.Terminal.maximum_hyperlinks;
/// Fixed process-group signal vocabulary.
pub const Signal = pty.Signal;
/// Exact process-group signal delivery outcome.
pub const SignalResult = pty.SignalResult;
/// Exact child-process termination observation.
pub const ChildExit = pty.ChildExit;

/// Supplies one local shell launch and bounded canonical terminal geometry.
pub const Launch = struct {
    shell: []const u8,
    command: ?[]const u8 = null,
    cwd: ?[]const u8 = null,
    rows: u16,
    columns: u16,
    history_rows: u16 = 4096,
    term: []const u8 = "xterm-256color",
    colorterm: ?[]const u8 = "truecolor",
};

/// Reports construction failure before a session becomes observable.
pub const InitError = pty.InitError || pty.StartError || vt.Terminal.InitError;
/// Reports terminal input encoding, signal, or bounded write admission failure.
pub const InputError = vt.Terminal.InputError || pty.TermiosSignalError || error{WriteQueueFull};
/// Reports atomic PTY and VT geometry transition failure.
pub const ResizeError = pty.ResizeError || vt.Terminal.ResizeError;
/// Reports PTY, VT, reply, or headless environment progress failure.
pub const ServiceError = pty.ReadError || pty.WriteError || pty.ObserveError ||
    vt.Terminal.FeedError || vt.Terminal.ClipboardReplyError ||
    vt.Terminal.ColorPreferenceReplyError || vt.Terminal.ContainerReplyError ||
    vt.Terminal.PointerShapeReplyError || error{WriteQueueFull};

/// Copies one coherent semantic observation without exposing VT storage.
pub const Status = struct {
    revision: u64,
    rows: u16,
    columns: u16,
    cursor_row: u16,
    cursor_column: u16,
    cursor_visible: bool,
    cursor_shape: CursorShape,
    cursor_blink: bool,
    cursor_movement_timestamp_ns: u64,
    alternate_screen: bool,
    history_offset: u32,
    history_count: u32,
    history_row_base: u32,
};

/// Reports invalid row selection or insufficient caller-owned cell storage.
pub const CopyRowError = error{ InvalidRow, OutputTooSmall };
/// Summarizes one bounded service turn without exposing PTY or VT ownership.
pub const Service = struct {
    changed: bool,
    stream_closed: bool,
    child_exit: ?ChildExit,
    write_pending: bool,
};

/// Constructs one PTY and VT owner from an explicit inherited environment.
pub fn init(
    allocator: std.mem.Allocator,
    inherited_environment: std.process.Environ,
    launch: Launch,
) InitError!*Session {
    const state = try allocator.create(State);
    errdefer allocator.destroy(state);
    state.* = try State.init(allocator, inherited_environment, launch);
    return @ptrCast(state);
}

/// Stops the child, releases VT state, and destroys the opaque owner.
pub fn deinit(session: *Session) void {
    const state = stateMut(session);
    const allocator = state.allocator;
    state.deinit();
    allocator.destroy(state);
}

/// Returns the PTY descriptor for caller-owned poll integration.
pub fn descriptor(session: *const Session) error{NotStarted}!std.posix.fd_t {
    return stateConst(session).transport.masterFd();
}

/// Returns the monotonic canonical VT semantic revision.
pub fn revision(session: *const Session) u64 {
    return stateConst(session).terminal.semanticSequence();
}

/// Copies coherent history, geometry, and cursor facts for one requested viewport.
pub fn status(session: *const Session, history_offset: u32) Status {
    const terminal_view = stateConst(session).terminal.semanticView(history_offset);
    return .{
        .revision = stateConst(session).terminal.semanticSequence(),
        .rows = terminal_view.rows,
        .columns = terminal_view.cols,
        .cursor_row = terminal_view.cursor_row,
        .cursor_column = terminal_view.cursor_col,
        .cursor_visible = terminal_view.cursor_visible,
        .cursor_shape = terminal_view.cursor_shape,
        .cursor_blink = terminal_view.cursor_blink,
        .cursor_movement_timestamp_ns = terminal_view.cursor_movement_timestamp_ns,
        .alternate_screen = terminal_view.is_alternate_screen,
        .history_offset = terminal_view.history_offset,
        .history_count = terminal_view.history_count,
        .history_row_base = terminal_view.history_row_base,
    };
}

/// Copies one complete visible row into caller-owned storage.
pub fn copyRow(
    session: *const Session,
    history_offset: u32,
    row: u16,
    output: []Cell,
) CopyRowError![]const Cell {
    const terminal_view = stateConst(session).terminal.semanticView(history_offset);
    if (row >= terminal_view.rows) return error.InvalidRow;
    if (output.len < terminal_view.cols) return error.OutputTooSmall;
    const cells = terminal_view.rowCells(row);
    @memcpy(output[0..cells.len], cells);
    return output[0..cells.len];
}

/// Copies one complete grapheme scalar sequence into fixed caller storage.
pub fn copyCellScalars(
    session: *const Session,
    history_offset: u32,
    row: u16,
    column: u16,
    output: *[maximum_cell_scalars]u21,
) []const u21 {
    return stateConst(session).terminal.semanticView(history_offset).cellScalarsAt(
        row,
        column,
        output,
    );
}

/// Copies the terminal palette and dynamic visual defaults.
pub fn presentation(session: *const Session) Presentation {
    return stateConst(session).terminal.presentation();
}

/// Borrows the URI interned for one nonzero terminal-cell hyperlink identity.
pub fn hyperlinkUri(session: *const Session, link_id: u32) ?[]const u8 {
    return stateConst(session).terminal.hyperlinkUri(link_id);
}

/// Copies one visible row's DEC presentation geometry.
pub fn lineGeometry(session: *const Session, history_offset: u32, row: u16) LineGeometry {
    return stateConst(session).terminal.semanticView(history_offset).lineGeometry(row);
}

/// Reports whether one visible row is a soft continuation of its predecessor.
pub fn rowWrapped(session: *const Session, history_offset: u32, row: u16) bool {
    return stateConst(session).terminal.semanticView(history_offset).rowWrapped(row);
}

/// Encodes and admits one input event in canonical session order.
pub fn input(session: *Session, event: Input) InputError!void {
    return stateMut(session).input(event);
}

/// Atomically applies one explicit canonical PTY and VT geometry.
pub fn resize(session: *Session, rows: u16, columns: u16) ResizeError!void {
    return stateMut(session).resize(rows, columns);
}

/// Delivers one fixed signal to the canonical child process group.
pub fn signal(session: *Session, requested: Signal) SignalResult {
    return stateMut(session).transport.signal(requested);
}

/// Services bounded PTY read/write progress and canonical VT consequences.
pub fn service(
    session: *Session,
    readable: bool,
    writable: bool,
    timestamp_ns: u64,
) ServiceError!Service {
    return stateMut(session).service(readable, writable, timestamp_ns);
}

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

const State = struct {
    allocator: std.mem.Allocator,
    transport: pty.Owned,
    terminal: vt.Terminal,
    writes: WriteQueue = .{},
    reads: [read_buffer_bytes]u8 = undefined,
    read_start: usize = 0,
    read_end: usize = 0,
    child_exit: ?ChildExit = null,
    stream_closed: bool = false,

    fn init(
        allocator: std.mem.Allocator,
        inherited_environment: std.process.Environ,
        launch: Launch,
    ) InitError!State {
        if (launch.rows == 0 or launch.columns == 0) return error.InvalidDimensions;
        var transport = try pty.Owned.init(
            allocator,
            inherited_environment,
            launch.shell,
            launch.command,
            launch.cwd,
            .{ .term = launch.term, .colorterm = launch.colorterm },
        );
        errdefer transport.deinit();
        try transport.start(launch.columns, launch.rows);
        var terminal = try vt.Terminal.initWithHistory(
            allocator,
            launch.rows,
            launch.columns,
            launch.history_rows,
        );
        errdefer terminal.deinit();
        return .{ .allocator = allocator, .transport = transport, .terminal = terminal };
    }

    fn deinit(self: *State) void {
        self.terminal.deinit();
        self.transport.deinit();
        self.* = undefined;
    }

    fn input(self: *State, event: Input) InputError!void {
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
            try collectReplies(&self.terminal, &self.writes);
            return;
        }
        try collectReplies(&self.terminal, &self.writes);
        try self.writes.append(encoded.bytes);
    }

    fn resize(self: *State, rows: u16, columns: u16) ResizeError!void {
        var prepared = try self.terminal.prepareResize(rows, columns);
        defer prepared.deinit();
        try self.transport.resize(columns, rows);
        prepared.commit();
    }

    fn service(self: *State, readable: bool, writable: bool, timestamp_ns: u64) ServiceError!Service {
        const revision_before = self.terminal.semanticSequence();
        if (writable and self.writes.count != 0) try flushWrites(&self.transport, &self.writes);
        collectReplies(&self.terminal, &self.writes) catch |failure| switch (failure) {
            error.WriteQueueFull => return self.serviceResult(revision_before),
        };
        try self.processBuffered(timestamp_ns);
        if (self.read_start == self.read_end and readable and !self.stream_closed) {
            const count = self.transport.read(&self.reads) catch |failure| switch (failure) {
                error.Interrupted, error.WouldBlock => 0,
                error.EndOfStream => closed: {
                    self.stream_closed = true;
                    break :closed 0;
                },
                else => return failure,
            };
            self.read_start = 0;
            self.read_end = count;
            try self.processBuffered(timestamp_ns);
        }
        switch (try self.transport.observeChild()) {
            .running => {},
            .exited => |value| self.child_exit = value,
        }
        return self.serviceResult(revision_before);
    }

    fn processBuffered(self: *State, timestamp_ns: u64) ServiceError!void {
        while (self.read_start < self.read_end) {
            collectReplies(&self.terminal, &self.writes) catch |failure| switch (failure) {
                error.WriteQueueFull => return,
            };
            const byte = self.reads[self.read_start];
            self.read_start += 1;
            const summary = try self.terminal.feedAt(&.{byte}, timestamp_ns);
            std.debug.assert(!summary.titleChanged() or summary.stateChanged());
            try self.drainConsequences();
            collectReplies(&self.terminal, &self.writes) catch |failure| switch (failure) {
                error.WriteQueueFull => return,
            };
        }
        self.read_start = 0;
        self.read_end = 0;
    }

    fn drainConsequences(self: *State) ServiceError!void {
        var remaining = self.terminal.consequenceCount();
        while (remaining > 0) : (remaining -= 1) {
            const current = self.terminal.consequenceHead() orelse return;
            const identity = current.id();
            switch (current) {
                .clipboard => |request| if (request.kind == .query) {
                    const replied = try self.terminal.replyClipboard(identity, "");
                    std.debug.assert(replied);
                    continue;
                },
                .pointer_shape => |request| if (request.payload.len != 0 and request.payload[0] == '?') {
                    try self.terminal.replyPointerShape(identity, "default");
                    continue;
                },
                .container => |occurrence| switch (occurrence.request) {
                    .report_screen_cells => {
                        const terminal_view = self.terminal.semanticView(0);
                        try self.terminal.replyContainer(identity, .{ .screen_cells = .{
                            .rows = terminal_view.rows,
                            .cols = terminal_view.cols,
                        } });
                        continue;
                    },
                    .report_state, .report_position, .report_icon_title => {
                        self.terminal.declineContainerQuery(identity) catch unreachable;
                        continue;
                    },
                    else => {},
                },
                .color_preference_query => {
                    try self.terminal.replyColorPreference(identity, .dark);
                    continue;
                },
                else => {},
            }
            self.terminal.consumeConsequence(identity) catch |failure| switch (failure) {
                error.StaleConsequence, error.ReplyRequired => unreachable,
            };
        }
        std.debug.assert(self.terminal.consequenceHead() == null);
    }

    fn serviceResult(self: *const State, revision_before: u64) Service {
        return .{
            .changed = self.terminal.semanticSequence() != revision_before,
            .stream_closed = self.stream_closed,
            .child_exit = self.child_exit,
            .write_pending = self.writes.count != 0,
        };
    }
};

fn stateMut(session: *Session) *State {
    return @ptrCast(@alignCast(session));
}

fn stateConst(session: *const Session) *const State {
    return @ptrCast(@alignCast(session));
}

fn collectReplies(machine: *vt.Terminal, queue: *WriteQueue) error{WriteQueueFull}!void {
    const bytes = machine.replyBytes();
    if (bytes.len == 0) return;
    try queue.append(bytes);
    machine.consumeReplyBytes(bytes.len) catch unreachable;
}

fn flushWrites(owner: *pty.Owned, queue: *WriteQueue) pty.WriteError!void {
    var calls: usize = 0;
    var written: usize = 0;
    while (calls < write_calls_per_turn and written < write_bytes_per_turn and queue.count != 0) {
        calls += 1;
        const budget = @min(queue.count, write_bytes_per_turn - written);
        const accepted = owner.write(queue.bytes[0..budget]) catch |failure| switch (failure) {
            error.Interrupted => continue,
            error.WouldBlock => return,
            else => return failure,
        };
        std.debug.assert(accepted <= budget);
        queue.consume(accepted);
        written += accepted;
    }
}

fn inputAdmissionBytes(event: Input) error{WriteQueueFull}!usize {
    return switch (event) {
        .bytes => |bytes| bytes.len,
        .paste => |bytes| std.math.add(usize, bytes.len, 12) catch return error.WriteQueueFull,
        .key, .mouse, .focus => @sizeOf(vt.Terminal.InputScratch),
    };
}

fn snapshotAscii(session: *const Session, output: []u8) error{SnapshotLimit}![]const u8 {
    const current = status(session, 0);
    var row_cells: [512]Cell = undefined;
    if (current.columns > row_cells.len) return error.SnapshotLimit;
    var offset: usize = 0;
    var row: u16 = 0;
    while (row < current.rows) : (row += 1) {
        const cells = copyRow(session, 0, row, &row_cells) catch return error.SnapshotLimit;
        for (cells) |cell| {
            if (offset == output.len) return error.SnapshotLimit;
            output[offset] = if (cell.x == 0 and cell.y == 0 and cell.codepoint >= 0x20 and cell.codepoint <= 0x7e)
                @intCast(cell.codepoint)
            else
                ' ';
            offset += 1;
        }
        if (offset == output.len) return error.SnapshotLimit;
        output[offset] = '\n';
        offset += 1;
    }
    return output[0..offset];
}

fn sleepOneMillisecond() void {
    const linux = std.os.linux;
    const request = linux.timespec{ .sec = 0, .nsec = std.time.ns_per_ms };
    switch (linux.errno(linux.nanosleep(&request, null))) {
        .SUCCESS, .INTR => {},
        else => @panic("test nanosleep failed"),
    }
}

fn serviceUntilContains(session: *Session, needle: []const u8) !void {
    var text: [4096]u8 = undefined;
    var attempts: u16 = 0;
    while (attempts < 2000) : (attempts += 1) {
        const serviced = try service(session, true, true, 0);
        if (serviced.stream_closed and serviced.child_exit != null) return error.ChildExited;
        if (std.mem.indexOf(u8, try snapshotAscii(session, &text), needle) != null) return;
        sleepOneMillisecond();
    }
    return error.Timeout;
}

test "headless session drains host consequences without an observer" {
    const session = try init(std.testing.allocator, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "cat",
        .rows = 4,
        .columns = 20,
        .history_rows = 16,
    });
    defer deinit(session);
    const state = stateMut(session);

    const before = status(session, 0);
    const prepared = try state.terminal.feed(
        "\x1b]22;?__current__\x1b\\" ++
            "\x1b]52;c;?\x07" ++
            "\x1b]9;notice\x07" ++
            "\x1b[8;12;34t" ++
            "\x1b[?2031h\x1b[?996n",
    );
    try std.testing.expect(prepared.stateChanged());
    try state.drainConsequences();
    const after = status(session, 0);
    try std.testing.expectEqual(before.rows, after.rows);
    try std.testing.expectEqual(before.columns, after.columns);
    try std.testing.expect(state.terminal.consequenceHead() == null);
    try std.testing.expect(std.mem.indexOf(u8, state.terminal.replyBytes(), "default") != null);
}

test "one PTY and VT remain canonical for independent observers" {
    const session = try init(std.testing.allocator, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf 'READY\\n'; cat",
        .rows = 8,
        .columns = 40,
        .history_rows = 64,
    });
    defer deinit(session);
    try serviceUntilContains(session, "READY");

    const before = revision(session);
    try input(session, .{ .bytes = "SHARED-LINE\n" });
    try serviceUntilContains(session, "SHARED-LINE");
    try std.testing.expect(revision(session) > before);

    var first: [4096]u8 = undefined;
    var second: [4096]u8 = undefined;
    const first_view = try snapshotAscii(session, &first);
    const second_view = try snapshotAscii(session, &second);
    try std.testing.expectEqualSlices(u8, first_view, second_view);
}
