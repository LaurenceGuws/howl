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

/// Opaque handle to one canonical PTY + VT lifetime owner.
pub const Session = opaque {};
/// Canonical terminal engine type owned by one Session.
pub const Terminal = vt.Terminal;
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
/// Maximum scalars retained by one bounded terminal grapheme.
pub const maximum_cell_scalars = vt.scalar.maximum_scalars;
/// Fixed process-group signal vocabulary.
pub const Signal = pty.Signal;
/// Exact process-group signal delivery outcome.
pub const SignalResult = pty.SignalResult;
/// One ordered host-facing consequence retained by the canonical VT.
pub const Consequence = vt.Terminal.Consequence;
/// Reports stale occurrence identity or a consequence requiring a typed reply.
pub const ConsumeConsequenceError = vt.Terminal.ConsumeConsequenceError;
/// Reports clipboard reply admission failure without consuming a stale query.
pub const ClipboardReplyError = vt.Terminal.ClipboardReplyError;
/// Reports pointer-shape reply admission or identity failure.
pub const PointerShapeReplyError = vt.Terminal.PointerShapeReplyError;
/// Terminal-owned light/dark color preference vocabulary.
pub const ColorSchemePreference = vt.Terminal.ColorSchemePreference;
/// Reports color-preference reply admission or identity failure.
pub const ColorPreferenceReplyError = vt.Terminal.ColorPreferenceReplyError;
/// Typed container/window query reply vocabulary.
pub const ContainerReply = vt.Terminal.ContainerReply;
/// Reports container reply admission, identity, or type mismatch.
pub const ContainerReplyError = vt.Terminal.ContainerReplyError;
/// Selects whether a service turn applies deterministic headless host policy or retains host consequences.
pub const ConsequencePolicy = enum { headless, retain };
/// Exact child-process termination observation.
pub const ChildExit = pty.ChildExit;

/// Supplies one local shell launch and bounded canonical terminal geometry.
pub const Launch = struct {
    shell: []const u8,
    command: ?[]const u8 = null,
    cwd: ?[]const u8 = null,
    rows: u16,
    columns: u16,
    /// Stable canonical terminal pixel lattice used by graphics/window queries.
    cell_pixel_width: u32 = 10,
    cell_pixel_height: u32 = 20,
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

/// Summarizes one bounded service turn without exposing PTY or VT ownership.
pub const Service = struct {
    changed: bool,
    /// True when this service turn changed visible-row or scroll/history state.
    viewport_changed: bool,
    /// True when retained caller work exceeded its bounded queue and Session
    /// applied deterministic headless policy to at least one older consequence.
    retained_consequence_fallback: bool = false,
    stream_closed: bool,
    child_exit: ?ChildExit,
    write_pending: bool,
    /// Milliseconds until the next retained terminal-animation boundary.
    animation_wait_ms: ?u32,
};

/// Constructs one PTY and VT owner from an explicit inherited environment.
pub fn init(
    allocator: std.mem.Allocator,
    inherited_environment: std.process.Environ,
    launch: Launch,
) InitError!*Session {
    const state = try allocator.create(State);
    errdefer allocator.destroy(state);
    try state.initInto(allocator, inherited_environment, launch);
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

/// Borrows the canonical VT observation capability until the next Session mutation.
///
/// Mutation remains Session-owned so PTY writes, replies, resize and child
/// lifetime cannot be bypassed through this embedder observation seam.
pub fn terminal(session: *const Session) *const Terminal.Observation {
    return stateConst(session).terminal.observation();
}

/// Borrows the oldest retained host consequence until canonical terminal mutation.
pub fn consequenceHead(session: *const Session) ?Consequence {
    return terminal(session).consequenceHead();
}

/// Returns the bounded count of retained host consequences.
pub fn consequenceCount(session: *const Session) u16 {
    return terminal(session).consequenceCount();
}

/// Consumes one non-reply consequence by exact global FIFO identity.
pub fn consumeConsequence(session: *Session, id: u64) ConsumeConsequenceError!void {
    return stateMut(session).terminal.consumeConsequence(id);
}

/// Replies to one exact pending OSC 52 clipboard query.
pub fn replyClipboard(session: *Session, id: u64, bytes: []const u8) ClipboardReplyError!bool {
    return stateMut(session).terminal.replyClipboard(id, bytes);
}

/// Replies to one exact pending OSC 22 pointer-shape query.
pub fn replyPointerShape(session: *Session, id: u64, payload: []const u8) PointerShapeReplyError!void {
    return stateMut(session).terminal.replyPointerShape(id, payload);
}

/// Replies to one exact pending color-preference query.
pub fn replyColorPreference(
    session: *Session,
    id: u64,
    preference: ColorSchemePreference,
) ColorPreferenceReplyError!void {
    return stateMut(session).terminal.replyColorPreference(id, preference);
}

/// Replies to one exact pending container query.
pub fn replyContainer(session: *Session, id: u64, reply: ContainerReply) ContainerReplyError!void {
    return stateMut(session).terminal.replyContainer(id, reply);
}

/// Declines one exact pending container query without fabricating host state.
pub fn declineContainerQuery(
    session: *Session,
    id: u64,
) error{ StaleContainerRequest, ContainerReplyMismatch }!void {
    return stateMut(session).terminal.declineContainerQuery(id);
}

/// Encodes and admits one input event in canonical session order.
pub fn input(session: *Session, event: Input) InputError!void {
    return stateMut(session).input(event);
}

/// Atomically applies one explicit canonical PTY and VT geometry.
pub fn resize(session: *Session, rows: u16, columns: u16) ResizeError!void {
    return stateMut(session).resize(rows, columns);
}

/// Applies explicit cell-pixel metrics with canonical rows/columns and PTY size.
/// A zero pair preserves the previously accepted pixel lattice.
pub fn resizeGeometry(session: *Session, rows: u16, columns: u16, cell_width: u16, cell_height: u16) ResizeError!void {
    const state = stateMut(session);
    if ((cell_width == 0) != (cell_height == 0)) return error.InvalidDimensions;
    const cell = if (cell_width == 0) state.terminal.cellPixelSize().? else vt.Terminal.CellPixelSize{ .width = cell_width, .height = cell_height };
    return state.resizeGeometry(rows, columns, cell);
}

fn ptyPixelExtent(cells: u16, pixels: u32) error{InvalidDimensions}!u16 {
    if (cells == 0 or pixels == 0) return error.InvalidDimensions;
    return std.math.cast(u16, @as(u64, cells) * pixels) orelse error.InvalidDimensions;
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
    return serviceWithConsequencePolicy(session, readable, writable, timestamp_ns, .headless);
}

/// Services one turn while explicitly selecting host-consequence policy.
///
/// `.retain` leaves canonical VT consequences queued for an external authority;
/// `.headless` applies the existing deterministic fallback policy. Switching a
/// retained session back to `.headless` drains already-pending consequences on
/// that same service turn, so authority loss cannot strand a terminal query.
pub fn serviceWithConsequencePolicy(
    session: *Session,
    readable: bool,
    writable: bool,
    timestamp_ns: u64,
    policy: ConsequencePolicy,
) ServiceError!Service {
    return stateMut(session).service(readable, writable, timestamp_ns, policy);
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

    fn initInto(
        self: *State,
        allocator: std.mem.Allocator,
        inherited_environment: std.process.Environ,
        launch: Launch,
    ) InitError!void {
        if (launch.rows == 0 or launch.columns == 0 or
            launch.cell_pixel_width == 0 or launch.cell_pixel_height == 0)
            return error.InvalidDimensions;
        var transport = try pty.Owned.init(
            allocator,
            inherited_environment,
            launch.shell,
            launch.command,
            launch.cwd,
            .{ .term = launch.term, .colorterm = launch.colorterm },
        );
        errdefer transport.deinit();
        const pixel_width = try ptyPixelExtent(launch.columns, launch.cell_pixel_width);
        const pixel_height = try ptyPixelExtent(launch.rows, launch.cell_pixel_height);
        try transport.startWithPixels(launch.columns, launch.rows, pixel_width, pixel_height);

        self.allocator = allocator;
        self.transport = transport;
        self.writes = .{};
        self.read_start = 0;
        self.read_end = 0;
        self.child_exit = null;
        self.stream_closed = false;
        try vt.Terminal.initWithHistoryInto(
            &self.terminal,
            allocator,
            launch.rows,
            launch.columns,
            launch.history_rows,
        );
        errdefer self.terminal.deinit();
        try self.terminal.setCellPixelSize(launch.cell_pixel_width, launch.cell_pixel_height);
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
        return self.resizeGeometry(rows, columns, self.terminal.cellPixelSize().?);
    }

    fn resizeGeometry(self: *State, rows: u16, columns: u16, cell: vt.Terminal.CellPixelSize) ResizeError!void {
        const width = try ptyPixelExtent(columns, cell.width);
        const height = try ptyPixelExtent(rows, cell.height);
        var prepared = try self.terminal.prepareResizeGeometry(rows, columns, cell);
        defer prepared.deinit();
        try self.transport.resizeWithPixels(columns, rows, width, height);
        prepared.commit();
    }

    fn service(
        self: *State,
        readable: bool,
        writable: bool,
        timestamp_ns: u64,
        consequence_policy: ConsequencePolicy,
    ) ServiceError!Service {
        const revision_before = self.terminal.semanticSequence();
        var viewport_changed = false;
        var retained_consequence_fallback = false;
        if (consequence_policy == .headless) try self.drainConsequences();
        if (writable and self.writes.count != 0) try flushWrites(&self.transport, &self.writes);
        collectReplies(&self.terminal, &self.writes) catch |failure| switch (failure) {
            error.WriteQueueFull => return self.serviceResult(
                revision_before,
                timestamp_ns,
                viewport_changed,
                retained_consequence_fallback,
            ),
        };
        try self.processBuffered(
            timestamp_ns,
            consequence_policy,
            &viewport_changed,
            &retained_consequence_fallback,
        );
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
            try self.processBuffered(
                timestamp_ns,
                consequence_policy,
                &viewport_changed,
                &retained_consequence_fallback,
            );
        }
        switch (try self.transport.observeChild()) {
            .running => {},
            .exited => |value| self.child_exit = value,
        }
        return self.serviceResult(
            revision_before,
            timestamp_ns,
            viewport_changed,
            retained_consequence_fallback,
        );
    }

    fn processBuffered(
        self: *State,
        timestamp_ns: u64,
        consequence_policy: ConsequencePolicy,
        viewport_changed: *bool,
        retained_consequence_fallback: *bool,
    ) ServiceError!void {
        while (self.read_start < self.read_end) {
            collectReplies(&self.terminal, &self.writes) catch |failure| switch (failure) {
                error.WriteQueueFull => return,
            };
            const progress = if (consequence_policy == .retain)
                try self.terminal.feedAtServiceBoundaryRelievingConsequences(
                    self.reads[self.read_start..self.read_end],
                    timestamp_ns,
                    relieveConsequencePressure,
                )
            else
                try self.terminal.feedAtServiceBoundary(
                    self.reads[self.read_start..self.read_end],
                    timestamp_ns,
                );
            std.debug.assert(progress.consumed > 0);
            std.debug.assert(progress.consumed <= self.read_end - self.read_start);
            self.read_start += progress.consumed;
            viewport_changed.* = viewport_changed.* or progress.summary.mutations.viewport;
            retained_consequence_fallback.* =
                retained_consequence_fallback.* or progress.consequence_pressure_relieved;
            std.debug.assert(!progress.summary.titleChanged() or progress.summary.stateChanged());
            if (consequence_policy == .headless) try self.drainConsequences();
            collectReplies(&self.terminal, &self.writes) catch |failure| switch (failure) {
                error.WriteQueueFull => return,
            };
        }
        self.read_start = 0;
        self.read_end = 0;
    }

    fn drainConsequences(self: *State) ServiceError!void {
        while (self.terminal.consequenceHead() != null)
            try relieveConsequencePressure(&self.terminal);
        std.debug.assert(self.terminal.consequenceHead() == null);
    }

    fn serviceResult(
        self: *State,
        revision_before: u64,
        timestamp_ns: u64,
        viewport_changed: bool,
        retained_consequence_fallback: bool,
    ) Service {
        const animation = self.terminal.serviceAnimations(timestamp_ns);
        return .{
            .changed = self.terminal.semanticSequence() != revision_before,
            .viewport_changed = viewport_changed,
            .retained_consequence_fallback = retained_consequence_fallback,
            .stream_closed = self.stream_closed,
            .child_exit = self.child_exit,
            .write_pending = self.writes.count != 0,
            .animation_wait_ms = animation.next_ms,
        };
    }
};

/// Applies one deterministic headless fallback to the global consequence head.
/// Service-boundary VT feeds use this only when a valid new consequence cannot
/// fit because already-retained caller work exhausted its bounded family.
fn relieveConsequencePressure(machine: *vt.Terminal) vt.Terminal.FeedError!void {
    const current = machine.consequenceHead() orelse return error.ConsequencePressure;
    const identity = current.id();
    switch (current) {
        .clipboard => |request| if (request.kind == .query) {
            const replied = machine.replyClipboard(identity, "") catch |failure| switch (failure) {
                error.StaleClipboardRequest => unreachable,
                else => |err| return err,
            };
            std.debug.assert(replied);
            return;
        },
        .pointer_shape => |request| if (request.payload.len != 0 and request.payload[0] == '?') {
            machine.replyPointerShape(identity, "default") catch |failure| switch (failure) {
                error.StalePointerShape, error.PointerShapeReplyMismatch => unreachable,
                else => |err| return err,
            };
            return;
        },
        .container => |occurrence| switch (occurrence.request) {
            .report_screen_cells => {
                const terminal_view = machine.semanticView(0);
                machine.replyContainer(identity, .{ .screen_cells = .{
                    .rows = terminal_view.rows,
                    .cols = terminal_view.cols,
                } }) catch |failure| switch (failure) {
                    error.StaleContainerRequest, error.ContainerReplyMismatch => unreachable,
                    else => |err| return err,
                };
                return;
            },
            .report_state, .report_position, .report_icon_title => {
                machine.declineContainerQuery(identity) catch unreachable;
                return;
            },
            else => {},
        },
        .color_preference_query => {
            machine.replyColorPreference(identity, .dark) catch |failure| switch (failure) {
                error.StaleColorPreferenceQuery => unreachable,
                else => |err| return err,
            };
            return;
        },
        else => {},
    }
    machine.consumeConsequence(identity) catch |failure| switch (failure) {
        error.StaleConsequence, error.ReplyRequired => unreachable,
    };
}

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
    const current = terminal(session).semanticView(0);
    if (current.cols > 512) return error.SnapshotLimit;
    var offset: usize = 0;
    var row: u16 = 0;
    while (row < current.rows) : (row += 1) {
        const cells = current.rowCells(row);
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

fn testTerminalImage(machine: *const Terminal.Observation, image_id: u32, generation: u64) ?Terminal.Image {
    var images = machine.images(0);
    var index: usize = 0;
    while (index < images.imageCount()) : (index += 1) {
        const candidate = images.image(index) orelse continue;
        if (candidate.id == image_id and candidate.generation == generation) return candidate;
    }
    return null;
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

    const before = terminal(session).semanticView(0);
    const prepared = try state.terminal.feed(
        "\x1b]22;?__current__\x1b\\" ++
            "\x1b]52;c;?\x07" ++
            "\x1b]9;notice\x07" ++
            "\x1b[8;12;34t" ++
            "\x1b[?2031h\x1b[?996n",
    );
    try std.testing.expect(prepared.stateChanged());
    try state.drainConsequences();
    const after = terminal(session).semanticView(0);
    try std.testing.expectEqual(before.rows, after.rows);
    try std.testing.expectEqual(before.cols, after.cols);
    try std.testing.expect(state.terminal.consequenceHead() == null);
    try std.testing.expect(std.mem.indexOf(u8, state.terminal.replyBytes(), "default") != null);
}

test "service separates in-place text from viewport mutation" {
    const session = try init(std.testing.allocator, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "sleep 30",
        .rows = 2,
        .columns = 4,
        .history_rows = 8,
    });
    defer deinit(session);
    const state = stateMut(session);

    state.reads[0] = 'A';
    state.read_start = 0;
    state.read_end = 1;
    const text = try state.service(false, false, 1, .headless);
    try std.testing.expect(text.changed);
    try std.testing.expect(!text.viewport_changed);

    @memcpy(state.reads[0..2], "\n\n");
    state.read_start = 0;
    state.read_end = 2;
    const scroll = try state.service(false, false, 2, .headless);
    try std.testing.expect(scroll.changed);
    try std.testing.expect(scroll.viewport_changed);
}

test "session services terminal animation without PTY readiness" {
    const session = try init(std.testing.allocator, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "cat",
        .rows = 3,
        .columns = 8,
        .history_rows = 8,
    });
    defer deinit(session);
    const state = stateMut(session);

    try std.testing.expect((try state.terminal.feed(
        "\x1b_Ga=T,f=32,s=1,v=1,i=20,C=1,q=2;/wAA/w==\x1b\\",
    )).stateChanged());
    try std.testing.expect((try state.terminal.feed(
        "\x1b_Ga=f,f=32,i=20,s=1,v=1,r=2,z=50,C=1,q=2;AAD/gA==\x1b\\",
    )).stateChanged());
    try std.testing.expect((try state.terminal.feed(
        "\x1b_Ga=a,i=20,s=3,r=1,z=40,q=2\x1b\\",
    )).stateChanged());

    var initial_images = terminal(session).images(0);
    const initial = initial_images.image(0) orelse return error.MissingImage;
    const image_id = initial.id;
    const initial_generation = initial.generation;
    const started_revision = terminal(session).semanticSequence();

    const started = try service(session, false, false, 100 * std.time.ns_per_ms);
    try std.testing.expect(!started.changed);
    try std.testing.expectEqual(@as(?u32, 40), started.animation_wait_ms);
    try std.testing.expectEqual(started_revision, terminal(session).semanticSequence());

    const advanced = try service(session, false, false, 140 * std.time.ns_per_ms);
    try std.testing.expect(advanced.changed);
    try std.testing.expectEqual(@as(?u32, 50), advanced.animation_wait_ms);
    try std.testing.expectEqual(started_revision + 1, terminal(session).semanticSequence());
    var advanced_images = terminal(session).images(0);
    const current = advanced_images.image(0) orelse return error.MissingImage;
    try std.testing.expect(current.generation > initial_generation);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 128 }, current.pixels);
    try std.testing.expect(testTerminalImage(terminal(session), image_id, initial_generation) == null);
    try std.testing.expect(testTerminalImage(terminal(session), image_id, current.generation) != null);
}

test "retained host query falls back headlessly when external authority disappears" {
    const session = try init(std.testing.allocator, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo -icanon min 1 time 0; " ++
            "printf '\\033]52;c;?\\007'; " ++
            "bytes=$(dd bs=1 count=9 2>/dev/null | od -An -tx1 -v | tr -d '[:space:]'); " ++
            "printf 'RESULT:%s\n' \"$bytes\"; cat",
        .rows = 4,
        .columns = 40,
        .history_rows = 16,
    });
    defer deinit(session);

    var attempts: u16 = 0;
    while (consequenceHead(session) == null and attempts < 2000) : (attempts += 1) {
        const serviced = try serviceWithConsequencePolicy(session, true, true, 0, .retain);
        try std.testing.expect(!serviced.stream_closed);
        sleepOneMillisecond();
    }
    const pending = consequenceHead(session) orelse return error.Timeout;
    try std.testing.expectEqual(@as(u16, 1), consequenceCount(session));
    try std.testing.expect(std.meta.activeTag(pending) == .clipboard);
    try std.testing.expectEqualStrings("c", pending.clipboard.selection);
    try std.testing.expect(pending.clipboard.kind == .query);

    var text: [4096]u8 = undefined;
    try std.testing.expect(std.mem.indexOf(u8, try snapshotAscii(session, &text), "RESULT:") == null);

    // Losing explicit external authority restores today's deterministic
    // headless reply policy on the next turn, without waiting for new PTY bytes.
    const fallback = try serviceWithConsequencePolicy(session, false, true, 0, .headless);
    try std.testing.expect(fallback.write_pending);
    try std.testing.expect(consequenceHead(session) == null);
    try serviceUntilContains(session, "RESULT:1b5d35323b633b1b5c");
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

    const before = terminal(session).semanticSequence();
    try input(session, .{ .bytes = "SHARED-LINE\n" });
    try serviceUntilContains(session, "SHARED-LINE");
    try std.testing.expect(terminal(session).semanticSequence() > before);

    var first: [4096]u8 = undefined;
    var second: [4096]u8 = undefined;
    const first_view = try snapshotAscii(session, &first);
    const second_view = try snapshotAscii(session, &second);
    try std.testing.expectEqualSlices(u8, first_view, second_view);
}

test "headless service drains consequence bursts at VT service boundaries" {
    const session = try init(std.testing.allocator, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "i=0; while [ $i -lt 64 ]; do printf '\\007'; i=$((i+1)); done; printf 'BOUNDARY-DONE\\n'; cat",
        .rows = 4,
        .columns = 32,
        .history_rows = 16,
    });
    defer deinit(session);

    try serviceUntilContains(session, "BOUNDARY-DONE");
    try std.testing.expectEqual(@as(u16, 0), consequenceCount(session));
}

test "Session pixel geometry agrees with PTY reports and rejects overflow transactionally" {
    const session = try init(std.testing.allocator, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "sleep 30",
        .rows = 3,
        .columns = 8,
        .history_rows = 8,
    });
    defer deinit(session);
    const state = stateMut(session);
    const fd = try descriptor(session);
    var size: std.posix.winsize = undefined;
    const linux = std.os.linux;
    try std.testing.expectEqual(linux.E.SUCCESS, linux.errno(linux.ioctl(fd, linux.T.IOCGWINSZ, @intFromPtr(&size))));
    try std.testing.expectEqual(@as(u16, 80), size.xpixel);
    try std.testing.expectEqual(@as(u16, 60), size.ypixel);
    const before = terminal(session).semanticSequence();
    try resizeGeometry(session, 3, 8, 11, 24);
    try std.testing.expect(terminal(session).semanticSequence() > before);
    try std.testing.expectEqual(linux.E.SUCCESS, linux.errno(linux.ioctl(fd, linux.T.IOCGWINSZ, @intFromPtr(&size))));
    try std.testing.expectEqual(@as(u16, 88), size.xpixel);
    try std.testing.expectEqual(@as(u16, 72), size.ypixel);
    const queried = try state.terminal.feed("\x1b[14t\x1b[16t");
    try std.testing.expect(queried.stateChanged());
    try std.testing.expectEqualStrings("\x1b[4;72;88t\x1b[6;24;11t", state.terminal.replyBytes());
    try resize(session, 4, 9);
    try std.testing.expectEqual(@as(u32, 11), state.terminal.cellPixelSize().?.width);
    const accepted = terminal(session).semanticView(0);
    try std.testing.expectEqual(linux.E.SUCCESS, linux.errno(linux.ioctl(fd, linux.T.IOCGWINSZ, @intFromPtr(&size))));
    const accepted_pty = size;
    try std.testing.expectError(error.InvalidDimensions, resizeGeometry(session, 4, 9, 11, 0));
    try std.testing.expectError(error.InvalidDimensions, resizeGeometry(session, 4, 9, 65535, 24));
    try std.testing.expectEqualDeep(accepted, terminal(session).semanticView(0));
    try std.testing.expectEqual(linux.E.SUCCESS, linux.errno(linux.ioctl(fd, linux.T.IOCGWINSZ, @intFromPtr(&size))));
    try std.testing.expectEqualDeep(accepted_pty, size);
    state.transport.stop();
    try std.testing.expectError(error.NotStarted, resizeGeometry(session, 5, 10, 12, 26));
    try std.testing.expectEqualDeep(accepted, terminal(session).semanticView(0));
    try std.testing.expectEqual(@as(u32, 11), state.terminal.cellPixelSize().?.width);
}

test "Session lends only the opaque VT observation capability" {
    const return_type = @typeInfo(@TypeOf(terminal)).@"fn".return_type.?;
    const pointer = @typeInfo(return_type).pointer;
    try std.testing.expect(pointer.attrs.@"const");
    try std.testing.expect(pointer.child == Terminal.Observation);
    try std.testing.expect(@typeInfo(pointer.child) == .@"opaque");
}

test "retained consequence pressure preserves canonical progress within fixed bounds" {
    const session = try init(std.testing.allocator, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "sleep 30",
        .rows = 2,
        .columns = 8,
        .history_rows = 8,
    });
    defer deinit(session);
    const state = stateMut(session);

    var bytes: [66]u8 = undefined;
    bytes[0] = 'X';
    @memset(bytes[1..65], 0x07);
    bytes[65] = 'Y';
    @memcpy(state.reads[0..bytes.len], &bytes);
    state.read_start = 0;
    state.read_end = bytes.len;

    const serviced = try state.service(false, false, 1, .retain);
    try std.testing.expect(serviced.changed);
    try std.testing.expect(serviced.retained_consequence_fallback);
    try std.testing.expectEqual(@as(u16, 32), state.terminal.consequenceCount());
    const view = state.terminal.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'X'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'Y'), view.cellAt(0, 1));
    try std.testing.expectEqual(@as(usize, 0), state.read_start);
    try std.testing.expectEqual(@as(usize, 0), state.read_end);
}

test "retained reply-required pressure defaults oldest query and admits newest" {
    const session = try init(std.testing.allocator, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "sleep 30",
        .rows = 2,
        .columns = 8,
        .history_rows = 8,
    });
    defer deinit(session);
    const state = stateMut(session);

    for (0..8) |_| {
        try std.testing.expect((try state.terminal.feed("\x1b]52;c;?\x07")).stateChanged());
    }
    try std.testing.expectEqual(@as(u16, 8), state.terminal.consequenceCount());
    try std.testing.expectEqual(@as(u64, 1), state.terminal.consequenceHead().?.id());

    const pressure = "X\x1b]52;c;?\x07Y";
    @memcpy(state.reads[0..pressure.len], pressure);
    state.read_start = 0;
    state.read_end = pressure.len;
    const serviced = try state.service(false, false, 2, .retain);

    try std.testing.expect(serviced.changed);
    try std.testing.expect(serviced.retained_consequence_fallback);
    try std.testing.expect(serviced.write_pending);
    try std.testing.expectEqual(@as(u16, 8), state.terminal.consequenceCount());
    try std.testing.expectEqual(@as(u64, 2), state.terminal.consequenceHead().?.id());
    try std.testing.expectEqualStrings("\x1b]52;c;\x1b\\", state.writes.bytes[0..state.writes.count]);
    const view = state.terminal.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'X'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'Y'), view.cellAt(0, 1));
}

test "fragmented retained clipboard pressure preserves exact text and FIFO identity" {
    const session = try init(std.testing.allocator, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "sleep 30",
        .rows = 2,
        .columns = 16,
        .history_rows = 8,
    });
    defer deinit(session);
    const state = stateMut(session);

    for (0..8) |_| {
        try std.testing.expect((try state.terminal.feed("\x1b]52;c;?\x07")).stateChanged());
    }
    try std.testing.expectEqual(@as(u16, 8), state.terminal.consequenceCount());
    try std.testing.expectEqual(@as(u64, 1), state.terminal.consequenceHead().?.id());

    const prefix = "X\x1b]52;c;";
    @memcpy(state.reads[0..prefix.len], prefix);
    state.read_start = 0;
    state.read_end = prefix.len;
    const first = try state.service(false, false, 1, .retain);
    try std.testing.expect(first.changed);
    try std.testing.expect(!first.retained_consequence_fallback);
    try std.testing.expectEqual(@as(u16, 8), state.terminal.consequenceCount());
    try std.testing.expectEqual(@as(u64, 1), state.terminal.consequenceHead().?.id());
    var view = state.terminal.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'X'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), view.cellAt(0, 1));

    const suffix = "?\x07Y";
    @memcpy(state.reads[0..suffix.len], suffix);
    state.read_start = 0;
    state.read_end = suffix.len;
    const second = try state.service(false, false, 2, .retain);
    try std.testing.expect(second.changed);
    try std.testing.expect(second.retained_consequence_fallback);
    try std.testing.expect(second.write_pending);
    try std.testing.expectEqual(@as(u16, 8), state.terminal.consequenceCount());
    try std.testing.expectEqual(@as(u64, 2), state.terminal.consequenceHead().?.id());
    try std.testing.expectEqualStrings("\x1b]52;c;\x1b\\", state.writes.bytes[0..state.writes.count]);

    view = state.terminal.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'X'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'Y'), view.cellAt(0, 1));
    try std.testing.expectEqual(@as(usize, 0), state.read_start);
    try std.testing.expectEqual(@as(usize, 0), state.read_end);

    var expected_id: u64 = 2;
    while (state.terminal.consequenceHead()) |head| : (expected_id += 1) {
        try std.testing.expectEqual(expected_id, head.id());
        const replied = try state.terminal.replyClipboard(head.id(), "");
        try std.testing.expect(replied);
    }
    try std.testing.expectEqual(@as(u64, 10), expected_id);
}
