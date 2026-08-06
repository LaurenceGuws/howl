//! Owns bounded PTY and VT lifetimes and publishes ordered VT visual journals.
//!
//! This owner has no font, raster, glyph, geometry, Canvas, or GPU state.
//! Renderer derives every admitted grid. A terminal applies that exact grid and
//! transfers each complete VT journal to the global visual FIFO before it may
//! process another PTY byte.

const std = @import("std");
const pty = @import("howl_pty");
const vt = @import("howl_vt");
const wayland = @import("howl_wayland");
const handoff = @import("terminal_handoff");
const visual_fifo = @import("terminal_visual_fifo");
const builtin = @import("builtin");

const owner_limit: usize = 64;
const write_queue_bytes: usize = 64 * 1024;
const read_buffer_bytes: usize = 16 * 1024;
const write_bytes_per_turn: usize = 64 * 1024;
const write_calls_per_turn: usize = 4;
const input_turn_limit: usize = 8;
const grid_row_limit: usize = 128;
const grid_cell_limit: usize = 65_536;

/// Reports process-root terminal-boundary construction failure.
pub const BoundaryInitError = handoff.BoundaryInitError;

/// Creates the terminal lifecycle and input boundary.
pub fn initBoundary(io: std.Io, allocator: std.mem.Allocator) BoundaryInitError!handoff.Boundary {
    return handoff.Boundary.init(io, allocator);
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

const Logical = struct {
    allocator: std.mem.Allocator,
    pane: handoff.PaneId,
    source: handoff.SourceId,
    lifecycle_revision: handoff.LifecycleRevision,
    transport: pty.Owned,
    machine: vt.Terminal,
    writes: WriteQueue = .{},
    read_bytes: [read_buffer_bytes]u8 = undefined,
    read_start: usize = 0,
    read_end: usize = 0,
    child_exit: ?pty.ChildExit = null,
    stream_closed: bool = false,
    completion_published: bool = false,
    last_visual_sequence: u64 = 0,
    pending_completion: ?handoff.TerminalCompletion = null,

    fn init(
        allocator: std.mem.Allocator,
        pane: handoff.PaneId,
        source: handoff.SourceId,
        revision: handoff.LifecycleRevision,
        shell: []const u8,
        command: ?[]const u8,
        grid: handoff.DerivedGrid,
    ) !Logical {
        try validateGrid(grid, pane);
        var transport = try pty.Owned.init(
            allocator,
            shell,
            command,
            null,
            .{ .term = "xterm-256color", .colorterm = "truecolor" },
        );
        errdefer transport.deinit();
        try transport.start(grid.columns, grid.rows);
        var machine = try vt.Terminal.init(allocator, grid.rows, grid.columns);
        errdefer machine.deinit();
        try machine.enableRenderJournal();
        return .{
            .allocator = allocator,
            .pane = pane,
            .source = source,
            .lifecycle_revision = revision,
            .transport = transport,
            .machine = machine,
        };
    }

    fn deinit(self: *Logical) void {
        self.machine.deinit();
        self.transport.deinit();
        self.* = undefined;
    }

    fn masterFd(self: *const Logical) !std.posix.fd_t {
        return self.transport.masterFd();
    }

    /// Copies a pending journal into the global FIFO before releasing VT ownership.
    fn flushJournal(self: *Logical, fifo: *visual_fifo.Fifo) !bool {
        const transaction = self.machine.renderTransaction() orelse return true;
        const sequence = fifo.enqueue(.{
            .pane = self.pane,
            .source = self.source,
            .lifecycle_revision = self.lifecycle_revision,
        }, transaction) catch |failure| switch (failure) {
            error.Pressure => return false,
            else => return failure,
        };
        self.machine.consumeRenderTransaction();
        self.last_visual_sequence = sequence;
        return true;
    }

    fn resize(
        self: *Logical,
        revision: handoff.LifecycleRevision,
        grid: handoff.DerivedGrid,
    ) !bool {
        try validateGrid(grid, self.pane);
        if (self.machine.renderTransaction() != null) return false;
        var prepared = self.machine.prepareResize(grid.rows, grid.columns) catch |failure| switch (failure) {
            error.TransactionPending => return false,
            else => return failure,
        };
        defer prepared.deinit();
        try self.transport.resize(grid.columns, grid.rows);
        prepared.commit();
        self.lifecycle_revision = revision;
        return true;
    }

    fn input(self: *Logical, event: vt.Terminal.InputEvent) !void {
        const admission = try inputAdmissionBytes(event);
        const required = std.math.add(usize, admission, self.machine.replyBytes().len) catch
            return error.WriteQueueFull;
        if (required > self.writes.remaining()) return error.WriteQueueFull;
        var scratch: vt.Terminal.InputScratch = undefined;
        var encoded = try self.machine.encodeInput(self.allocator, &scratch, event);
        defer encoded.deinit();
        if (encoded.bytes.len == 1 and self.machine.termiosSignals() and
            try self.transport.handleTermiosSignal(encoded.bytes[0]))
        {
            try collectReplies(&self.machine, &self.writes);
            return;
        }
        try collectReplies(&self.machine, &self.writes);
        try self.writes.append(encoded.bytes);
    }

    fn service(self: *Logical, fifo: *visual_fifo.Fifo, readable: bool, writable: bool) !void {
        if (!try self.flushJournal(fifo)) return;
        if (writable and self.writes.count != 0) try flushWrites(&self.transport, &self.writes);
        collectReplies(&self.machine, &self.writes) catch |failure| switch (failure) {
            error.WriteQueueFull => return,
            else => return failure,
        };
        try self.disposeConsequence();

        if (self.read_start != self.read_end) try self.processBuffered(fifo);
        if (!try self.flushJournal(fifo)) return;
        if (self.read_start != self.read_end or !readable or self.stream_closed) {
            try self.observeAndComplete(fifo);
            return;
        }

        const count = self.transport.read(&self.read_bytes) catch |failure| switch (failure) {
            error.Interrupted, error.WouldBlock => {
                try self.observeAndComplete(fifo);
                return;
            },
            error.EndOfStream => {
                self.stream_closed = true;
                try self.observeAndComplete(fifo);
                return;
            },
            else => return failure,
        };
        self.read_start = 0;
        self.read_end = count;
        try self.processBuffered(fifo);
        try self.observeAndComplete(fifo);
    }

    fn processBuffered(self: *Logical, fifo: *visual_fifo.Fifo) !void {
        while (self.read_start != self.read_end) {
            if (!try self.flushJournal(fifo)) return;
            const byte = self.read_bytes[self.read_start];
            _ = try self.machine.feedRenderByte(byte, try monotonicNanoseconds());
            self.read_start += 1;
            collectReplies(&self.machine, &self.writes) catch |failure| switch (failure) {
                error.WriteQueueFull => return,
                else => return failure,
            };
            try self.disposeConsequence();
            if (!try self.flushJournal(fifo)) return;
        }
        self.read_start = 0;
        self.read_end = 0;
    }

    fn observeAndComplete(self: *Logical, fifo: *visual_fifo.Fifo) !void {
        switch (try self.transport.observeChild()) {
            .running => {},
            .exited => |value| self.child_exit = value,
        }
        try self.stageCompletion(fifo);
    }

    fn stageCompletion(self: *Logical, fifo: *visual_fifo.Fifo) !void {
        if (self.completion_published or !self.stream_closed or self.child_exit == null or
            self.read_start != self.read_end or !try self.flushJournal(fifo) or
            self.last_visual_sequence == 0)
            return;
        const completion = handoff.TerminalCompletion{
            .pane = self.pane,
            .source = self.source,
            .lifecycle_revision = self.lifecycle_revision,
            .render_sequence = self.last_visual_sequence,
            .termination = switch (self.child_exit.?) {
                .code => |value| .{ .code = value },
                .signal => |value| .{ .signal = value },
            },
        };
        // The Boundary is supplied by Runtime so completion publication occurs there.
        self.completion_published = true;
        self.pending_completion = completion;
    }

    fn disposeConsequence(self: *Logical) !void {
        const current = self.machine.consequenceHead() orelse return;
        const identity = current.id();
        switch (current) {
            .clipboard => |request| if (request.kind == .query) {
                if (!try self.machine.replyClipboard(identity, "")) return error.StaleConsequence;
                return;
            },
            .container => |occurrence| switch (occurrence.request) {
                .report_screen_cells => {
                    const view = self.machine.semanticView(0);
                    try self.machine.replyContainer(identity, .{ .screen_cells = .{
                        .rows = view.rows,
                        .cols = view.cols,
                    } });
                    return;
                },
                .report_state, .report_position, .report_icon_title => {
                    try self.machine.declineContainerQuery(identity);
                    return;
                },
                else => {},
            },
            .color_preference_query => {
                try self.machine.replyColorPreference(identity, .dark);
                return;
            },
            else => {},
        }
        self.machine.consumeConsequence(identity) catch |failure| switch (failure) {
            error.ReplyRequired => return,
            error.StaleConsequence => return,
        };
    }
};

const Runtime = struct {
    allocator: std.mem.Allocator,
    fifo: *visual_fifo.Fifo,
    first_command: ?[]const u8,
    owners: [owner_limit]?Logical = @splat(null),
    count: u8 = 0,
    pending_lifecycle: ?handoff.AdmittedLifecycle = null,
    pending_input: ?handoff.TerminalInput = null,
    pending_close: ?handoff.PaneId = null,

    fn deinit(self: *Runtime) void {
        var index: usize = self.owners.len;
        while (index != 0) {
            index -= 1;
            if (self.owners[index]) |*owner| owner.deinit();
        }
        self.* = undefined;
    }

    fn find(self: *const Runtime, pane: handoff.PaneId) ?usize {
        for (self.owners, 0..) |owner, index|
            if (owner != null and owner.?.pane == pane) return index;
        return null;
    }

    fn freeIndex(self: *const Runtime) ?usize {
        for (self.owners, 0..) |owner, index| if (owner == null) return index;
        return null;
    }

    fn validateAdmission(self: *Runtime, request: handoff.RuntimeAdmissionCopy) handoff.LifecycleAdmissionResult {
        var grid_index: usize = 0;
        var seen: [owner_limit]handoff.PaneId = undefined;
        var seen_count: usize = 0;
        for (request.operations[0..request.operation_count]) |operation| {
            const pane = switch (operation) {
                .create => |value| value.pane,
                .resize => |value| value.pane,
                .close => |value| value,
            };
            for (seen[0..seen_count]) |prior| if (prior == pane)
                return .{ .rejected = .duplicate_pane };
            seen[seen_count] = pane;
            seen_count += 1;
            switch (operation) {
                .create => {
                    if (self.find(pane) != null or self.freeIndex() == null)
                        return .{ .rejected = .duplicate_pane };
                    if (grid_index >= request.grid_count or !gridValid(request.grids[grid_index], pane))
                        return .{ .rejected = .terminal_capacity };
                    grid_index += 1;
                },
                .resize => {
                    if (self.find(pane) == null) return .{ .rejected = .unknown_pane };
                    if (grid_index >= request.grid_count or !gridValid(request.grids[grid_index], pane))
                        return .{ .rejected = .terminal_capacity };
                    grid_index += 1;
                },
                .close => if (self.find(pane) == null) return .{ .rejected = .unknown_pane },
            }
        }
        if (grid_index != request.grid_count) return .{ .rejected = .terminal_capacity };
        for (request.inputs[0..request.input_count]) |input| {
            const pane = switch (input) {
                .key => |value| value.pane,
                .focus => |value| value.pane,
            };
            const registering = request.registration != null and request.registration.?.pane == pane;
            if (!registering and self.find(pane) == null) return .{ .rejected = .unknown_pane };
        }
        return .admitted;
    }

    fn flushJournals(self: *Runtime) !bool {
        var complete = true;
        for (&self.owners) |*maybe_owner| if (maybe_owner.*) |*owner| {
            if (!try owner.flushJournal(self.fifo)) complete = false;
        };
        return complete;
    }

    fn applyLifecycle(self: *Runtime, boundary: *handoff.Boundary, shell: []const u8) !bool {
        const admitted = self.pending_lifecycle orelse return true;
        switch (admitted.operation) {
            .create => |create| {
                const grid = admitted.grid orelse return error.InvalidGrid;
                const source = boundary.sourceFor(create.pane) orelse return error.UnknownPane;
                const index = self.freeIndex() orelse return error.OwnerLimit;
                var owner = try Logical.init(
                    self.allocator,
                    create.pane,
                    source,
                    admitted.revision,
                    shell,
                    self.first_command,
                    grid,
                );
                errdefer owner.deinit();
                try boundary.markLive(create.pane);
                self.owners[index] = owner;
                self.count += 1;
                self.first_command = null;
            },
            .resize => |resize| {
                const index = self.find(resize.pane) orelse return error.UnknownPane;
                if (!try self.owners[index].?.resize(admitted.revision, admitted.grid orelse return error.InvalidGrid)) return false;
            },
            .close => |pane| {
                const index = self.find(pane) orelse return error.UnknownPane;
                if (!try self.owners[index].?.flushJournal(self.fifo)) return false;
                if (!try boundary.retireTransfer(pane)) return false;
                self.owners[index].?.deinit();
                self.owners[index] = null;
                self.count -= 1;
                try boundary.markRetired(pane);
            },
        }
        self.pending_lifecycle = null;
        return true;
    }

    fn applyInput(self: *Runtime, input: handoff.TerminalInput) !bool {
        switch (input) {
            .key => |value| {
                const index = self.find(value.pane) orelse return error.UnknownPane;
                const modifiers = value.key.semantic_modifiers;
                self.owners[index].?.input(.{ .key = .{
                    .key = try terminalKey(value.key.keysym),
                    .mods = .{
                        .shift = modifiers.shift,
                        .alt = modifiers.alt,
                        .control = modifiers.control,
                        .super = modifiers.super,
                        .hyper = modifiers.hyper,
                        .meta = modifiers.meta,
                        .caps_lock = modifiers.caps_lock,
                        .num_lock = modifiers.num_lock,
                    },
                    .action = switch (value.key.state) {
                        .pressed => .press,
                        .repeated => .repeat,
                        .released => .release,
                    },
                    .legacy_text = value.key.text[0..value.key.text_len],
                    .text = value.key.text[0..value.key.text_len],
                } }) catch |failure| switch (failure) {
                    error.WriteQueueFull => return false,
                    else => return failure,
                };
            },
            .focus => |value| {
                const index = self.find(value.pane) orelse return error.UnknownPane;
                self.owners[index].?.input(value.event) catch |failure| switch (failure) {
                    error.WriteQueueFull => return false,
                    else => return failure,
                };
            },
        }
        return true;
    }

    /// Retries one retained input before taking later Boundary input.
    /// Returns false only while PTY write capacity still blocks that input.
    fn drainInputs(self: *Runtime, boundary: *handoff.Boundary) !bool {
        var input_count: usize = 0;
        while (input_count < input_turn_limit) : (input_count += 1) {
            if (self.pending_input == null)
                self.pending_input = boundary.takeInput() orelse return true;
            if (!try self.applyInput(self.pending_input.?)) return false;
            self.pending_input = null;
        }
        return true;
    }

    fn publishCompletions(self: *Runtime, boundary: *handoff.Boundary) !void {
        for (&self.owners) |*maybe_owner| {
            const owner = if (maybe_owner.*) |*value| value else continue;
            const completion = owner.pending_completion orelse continue;
            boundary.publishCompletion(completion) catch |failure| switch (failure) {
                error.Stopping, error.UnknownPane, error.RetiredPane, error.SourceStale, error.LifecycleStale, error.DuplicateCompletion => {
                    owner.pending_completion = null;
                    continue;
                },
                else => return failure,
            };
            owner.pending_completion = null;
        }
    }
};

/// Exposes the real Runtime owner only to cross-owner test builds.
pub const testing = if (builtin.is_test) struct {
    /// Names the production Runtime storage used by integration proofs.
    pub const Owner = Runtime;
    const ApplyError = switch (@typeInfo(@typeInfo(@TypeOf(Runtime.applyLifecycle)).@"fn".return_type.?)) {
        .error_union => |info| info.error_set,
        else => unreachable,
    };
    const FlushError = switch (@typeInfo(@typeInfo(@TypeOf(Runtime.flushJournals)).@"fn".return_type.?)) {
        .error_union => |info| info.error_set,
        else => unreachable,
    };

    /// Constructs empty production Runtime ownership without spawning a pane.
    pub fn init(allocator: std.mem.Allocator, fifo: *visual_fifo.Fifo, first_command: ?[]const u8) Owner {
        return .{ .allocator = allocator, .fifo = fifo, .first_command = first_command };
    }

    /// Releases every production Runtime owner retained by the proof.
    pub fn deinit(owner: *Owner) void {
        owner.deinit();
    }

    /// Runs production lifecycle admission validation for one copied request.
    pub fn validate(owner: *Owner, request: handoff.RuntimeAdmissionCopy) handoff.LifecycleAdmissionResult {
        return owner.validateAdmission(request);
    }

    /// Applies one exact admitted lifecycle operation through production Runtime ownership.
    pub fn apply(owner: *Owner, boundary: *handoff.Boundary, admitted: handoff.AdmittedLifecycle, shell: []const u8) ApplyError!bool {
        std.debug.assert(owner.pending_lifecycle == null);
        owner.pending_lifecycle = admitted;
        return owner.applyLifecycle(boundary, shell);
    }

    /// Publishes every pending production VT journal into the shared FIFO.
    pub fn flush(owner: *Owner) FlushError!bool {
        return owner.flushJournals();
    }
} else struct {};

/// Runs the sole PTY/VT owner until the lifecycle boundary stops.
pub fn run(
    boundary: *handoff.Boundary,
    fifo: *visual_fifo.Fifo,
    allocator: std.mem.Allocator,
    shell: []const u8,
    first_command: ?[]const u8,
) void {
    runFallible(boundary, fifo, allocator, shell, first_command) catch |failure| {
        std.debug.print("Terminal runtime failure: {s}\n", .{@errorName(failure)});
        boundary.markStopped(true);
        return;
    };
    boundary.markStopped(false);
}

fn runFallible(
    boundary: *handoff.Boundary,
    fifo: *visual_fifo.Fifo,
    allocator: std.mem.Allocator,
    shell: []const u8,
    first_command: ?[]const u8,
) !void {
    var runtime = Runtime{ .allocator = allocator, .fifo = fifo, .first_command = first_command };
    defer runtime.deinit();
    while (true) {
        _ = try runtime.flushJournals();

        if (boundary.takeLifecycleAdmission()) |request| {
            try boundary.completeLifecycleAdmission(request.revision, runtime.validateAdmission(request));
        }
        if (runtime.pending_lifecycle == null) runtime.pending_lifecycle = boundary.takeAdmittedLifecycle();
        if (runtime.pending_lifecycle != null) _ = try runtime.applyLifecycle(boundary, shell);

        _ = try runtime.drainInputs(boundary);

        // Lifecycle create/resize may have produced an initial or replacement
        // journal after the first flush pass. Publish it before any blocking
        // poll; FIFO pressure is represented by the capacity descriptor.
        _ = try runtime.flushJournals();
        try runtime.publishCompletions(boundary);

        var descriptors: [owner_limit + 2]std.posix.pollfd = undefined;
        var owner_indices: [owner_limit]u8 = undefined;
        descriptors[0] = .{ .fd = boundary.terminalFd(), .events = std.posix.POLL.IN, .revents = 0 };
        descriptors[1] = .{ .fd = fifo.capacityDescriptor(), .events = std.posix.POLL.IN, .revents = 0 };
        var descriptor_count: usize = 2;
        for (&runtime.owners, 0..) |*maybe_owner, index| {
            const owner = if (maybe_owner.*) |*value| value else continue;
            descriptors[descriptor_count] = .{
                .fd = try owner.masterFd(),
                .events = (if (!owner.stream_closed) @as(i16, std.posix.POLL.IN | std.posix.POLL.HUP) else 0) |
                    (if (owner.writes.count != 0) @as(i16, std.posix.POLL.OUT) else 0),
                .revents = 0,
            };
            owner_indices[descriptor_count - 2] = @intCast(index);
            descriptor_count += 1;
        }
        _ = std.posix.poll(descriptors[0..descriptor_count], -1) catch return error.PollFailed;
        if (descriptors[0].revents & std.posix.POLL.IN != 0) {
            try boundary.drainTerminalWake();
            if (boundary.isStopping()) break;
        }
        if (descriptors[1].revents & std.posix.POLL.IN != 0) try fifo.drainCapacityWake();

        for (descriptors[2..descriptor_count], owner_indices[0 .. descriptor_count - 2]) |descriptor, owner_index| {
            if (descriptor.revents == 0) continue;
            const owner = &runtime.owners[owner_index].?;
            try owner.service(
                fifo,
                descriptor.revents & (std.posix.POLL.IN | std.posix.POLL.HUP) != 0,
                descriptor.revents & std.posix.POLL.OUT != 0,
            );
        }
        try runtime.publishCompletions(boundary);
        boundary.rearmTerminalWork();
    }
}

fn validateGrid(grid: handoff.DerivedGrid, pane: handoff.PaneId) error{InvalidGrid}!void {
    if (grid.pane != pane or grid.rows == 0 or grid.columns == 0 or grid.rows > grid_row_limit)
        return error.InvalidGrid;
    const cells = std.math.mul(usize, grid.rows, grid.columns) catch return error.InvalidGrid;
    if (cells > grid_cell_limit) return error.InvalidGrid;
}

fn gridValid(grid: handoff.DerivedGrid, pane: handoff.PaneId) bool {
    validateGrid(grid, pane) catch return false;
    return true;
}

fn collectReplies(machine: *vt.Terminal, queue: *WriteQueue) !void {
    const bytes = machine.replyBytes();
    if (bytes.len == 0) return;
    try queue.append(bytes);
    try machine.consumeReplyBytes(bytes.len);
}

fn flushWrites(owner: *pty.Owned, queue: *WriteQueue) !void {
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
        queue.consume(accepted);
        written += accepted;
    }
}

fn inputAdmissionBytes(event: vt.Terminal.InputEvent) error{WriteQueueFull}!usize {
    return switch (event) {
        .bytes => |bytes| bytes.len,
        .paste => |bytes| std.math.add(usize, bytes.len, 12) catch return error.WriteQueueFull,
        .key, .mouse, .focus => @sizeOf(vt.Terminal.InputScratch),
    };
}

fn terminalKey(keysym: wayland.input.Keysym) error{InvalidUnicodeScalar}!vt.Terminal.Key {
    return switch (@backingInt(keysym)) {
        0xff08 => .{ .named = .backspace },
        0xff09, 0xfe20 => .{ .named = .tab },
        0xff0d => .{ .named = .enter },
        0xff1b => .{ .named = .escape },
        0xff50 => .{ .named = .home },
        0xff51 => .{ .named = .left },
        0xff52 => .{ .named = .up },
        0xff53 => .{ .named = .right },
        0xff54 => .{ .named = .down },
        0xff55 => .{ .named = .page_up },
        0xff56 => .{ .named = .page_down },
        0xff57 => .{ .named = .end },
        0xff7f => .{ .named = .num_lock },
        0xffe1 => .{ .named = .left_shift },
        0xffe2 => .{ .named = .right_shift },
        0xffe3 => .{ .named = .left_control },
        0xffe4 => .{ .named = .right_control },
        0xffe5 => .{ .named = .caps_lock },
        0xffe7 => .{ .named = .left_meta },
        0xffe8 => .{ .named = .right_meta },
        0xffe9 => .{ .named = .left_alt },
        0xffea => .{ .named = .right_alt },
        0xffeb => .{ .named = .left_super },
        0xffec => .{ .named = .right_super },
        0xffed => .{ .named = .left_hyper },
        0xffee => .{ .named = .right_hyper },
        0xffff => .{ .named = .delete },
        else => |value| vt.Terminal.Key.initUnicode(
            std.math.cast(u21, value) orelse return error.InvalidUnicodeScalar,
        ),
    };
}

fn monotonicNanoseconds() error{ Clock, ArithmeticOverflow }!u64 {
    var value: std.os.linux.timespec = undefined;
    if (std.os.linux.clock_gettime(.MONOTONIC, &value) != 0) return error.Clock;
    const seconds: u64 = @intCast(value.sec);
    const nanoseconds: u64 = @intCast(value.nsec);
    const whole = std.math.mul(u64, seconds, std.time.ns_per_s) catch return error.ArithmeticOverflow;
    return std.math.add(u64, whole, nanoseconds) catch return error.ArithmeticOverflow;
}

fn registerForTest(
    boundary: *handoff.Boundary,
    pane: handoff.PaneId,
    source: handoff.SourceId,
) !handoff.AdmittedLifecycle {
    const operations = [_]handoff.Lifecycle{.{ .create = .{ .pane = pane, .pixels = .{ .width = 1, .height = 1 } } }};
    const grids = [_]handoff.DerivedGrid{.{ .pane = pane, .rows = 1, .columns = 1 }};
    var prepared = try boundary.prepareLifecycle(
        &operations,
        &grids,
        &.{},
        .{ .pane = pane, .source = source },
    );
    defer prepared.deinit();
    const revision = try prepared.publishAdmission();
    _ = boundary.takeLifecycleAdmission().?;
    try boundary.completeLifecycleAdmission(revision, .admitted);
    try prepared.commitAdmitted();
    return boundary.takeAdmittedLifecycle().?;
}

test "grid validation is independent of font and pixel ownership" {
    const pane: handoff.PaneId = @fromBackingInt(1);
    try validateGrid(.{ .pane = pane, .rows = 128, .columns = 512 }, pane);
    try std.testing.expectError(error.InvalidGrid, validateGrid(.{ .pane = pane, .rows = 129, .columns = 1 }, pane));
}

test "FIFO pressure preserves pending VT state before any later byte mutation" {
    var fifo = try visual_fifo.Fifo.init(std.testing.io, std.testing.allocator);
    defer fifo.deinit();
    var machine = try vt.Terminal.init(std.testing.allocator, 1, 1);
    defer machine.deinit();
    try machine.enableRenderJournal();
    const initial = machine.renderTransaction() orelse return error.TestUnexpectedResult;

    const cursor_operation = [_]vt.render_journal.Operation{.{ .cursor = .{
        .row = 0,
        .col = 0,
        .visible = false,
    } }};
    for (0..visual_fifo.queue_capacity) |_| {
        _ = try fifo.enqueue(.{
            .pane = @fromBackingInt(9),
            .source = @fromBackingInt(19),
            .lifecycle_revision = @fromBackingInt(1),
        }, .{ .operations = &cursor_operation });
    }
    try std.testing.expectError(error.Pressure, fifo.enqueue(.{
        .pane = @fromBackingInt(1),
        .source = @fromBackingInt(11),
        .lifecycle_revision = @fromBackingInt(1),
    }, initial));
    try std.testing.expect(machine.renderTransaction() != null);
    try std.testing.expectError(
        error.TransactionPending,
        machine.feedRenderByte('x', 1),
    );

    const released = fifo.take().?;
    try fifo.complete(released.handle);
    _ = try fifo.enqueue(.{
        .pane = @fromBackingInt(1),
        .source = @fromBackingInt(11),
        .lifecycle_revision = @fromBackingInt(1),
    }, initial);
    machine.consumeRenderTransaction();
    try std.testing.expect(machine.renderTransaction() == null);
}

test "same-grid Runtime resize emits one ordered full replacement barrier" {
    var fifo = try visual_fifo.Fifo.init(std.testing.io, std.testing.allocator);
    defer fifo.deinit();
    var machine = try vt.Terminal.init(std.testing.allocator, 2, 3);
    defer machine.deinit();
    try machine.enableRenderJournal();
    _ = try fifo.enqueue(.{
        .pane = @fromBackingInt(1),
        .source = @fromBackingInt(11),
        .lifecycle_revision = @fromBackingInt(1),
    }, machine.renderTransaction().?);
    machine.consumeRenderTransaction();

    var resize = try machine.prepareResize(2, 3);
    defer resize.deinit();
    resize.commit();
    const replacement = machine.renderTransaction() orelse return error.TestUnexpectedResult;
    var observed = false;
    for (replacement.operations) |operation| switch (operation) {
        .replace => |value| {
            try std.testing.expectEqual(vt.render_journal.ReplacementKind.resize, value.kind);
            try std.testing.expectEqual(@as(u16, 2), value.rows);
            try std.testing.expectEqual(@as(u16, 3), value.cols);
            observed = true;
        },
        else => {},
    };
    try std.testing.expect(observed);
    const sequence = try fifo.enqueue(.{
        .pane = @fromBackingInt(1),
        .source = @fromBackingInt(11),
        .lifecycle_revision = @fromBackingInt(2),
    }, replacement);
    try std.testing.expectEqual(@as(u64, 2), sequence);
    machine.consumeRenderTransaction();
}

fn inputKey(codepoint: u8) wayland.input.Key {
    var key = std.mem.zeroes(wayland.input.Key);
    key.state = .pressed;
    key.keysym = @fromBackingInt(@intCast(codepoint));
    key.text[0] = codepoint;
    key.text_len = 1;
    return key;
}

test "retained input retries after PTY queue progress before later input" {
    var boundary = try handoff.Boundary.init(std.testing.io, std.testing.allocator);
    defer boundary.deinit();
    var fifo = try visual_fifo.Fifo.init(std.testing.io, std.testing.allocator);
    defer fifo.deinit();
    const pane: handoff.PaneId = @fromBackingInt(1);
    const source: handoff.SourceId = @fromBackingInt(11);
    const owner = try Logical.init(
        std.testing.allocator,
        pane,
        source,
        @fromBackingInt(1),
        "/bin/sh",
        "cat >/dev/null",
        .{ .pane = pane, .rows = 1, .columns = 1 },
    );
    var runtime = Runtime{ .allocator = std.testing.allocator, .fifo = &fifo, .first_command = null };
    runtime.owners[0] = owner;
    runtime.count = 1;
    defer runtime.deinit();
    runtime.owners[0].?.writes.count = write_queue_bytes;
    _ = try registerForTest(&boundary, pane, source);
    try boundary.markLive(pane);
    try boundary.publishKey(pane, inputKey('x'));
    try boundary.publishKey(pane, inputKey('y'));

    try std.testing.expect(!try runtime.drainInputs(&boundary));
    try std.testing.expect(runtime.pending_input != null);
    runtime.owners[0].?.writes.consume(write_queue_bytes);
    try std.testing.expect(try runtime.drainInputs(&boundary));
    try std.testing.expect(runtime.pending_input == null);
    try std.testing.expectEqualStrings("xy", runtime.owners[0].?.writes.bytes[0..2]);
}

test "create ownership rolls back when Boundary live transition rejects" {
    var boundary = try handoff.Boundary.init(std.testing.io, std.testing.allocator);
    defer boundary.deinit();
    var fifo = try visual_fifo.Fifo.init(std.testing.io, std.testing.allocator);
    defer fifo.deinit();
    const pane: handoff.PaneId = @fromBackingInt(1);
    const source: handoff.SourceId = @fromBackingInt(11);
    const admitted = try registerForTest(&boundary, pane, source);
    try boundary.markLive(pane);
    var runtime = Runtime{
        .allocator = std.testing.allocator,
        .fifo = &fifo,
        .first_command = "sleep 30",
        .pending_lifecycle = .{
            .revision = admitted.revision,
            .operation = admitted.operation,
            .grid = .{ .pane = pane, .rows = 1, .columns = 1 },
        },
    };
    defer runtime.deinit();
    try std.testing.expectError(error.UnknownPane, runtime.applyLifecycle(&boundary, "/bin/sh"));
    try std.testing.expectEqual(@as(u8, 0), runtime.count);
    try std.testing.expect(runtime.owners[0] == null);
    try std.testing.expectEqualStrings("sleep 30", runtime.first_command.?);
    try std.testing.expect(runtime.pending_lifecycle != null);
}

test "quiet create publishes initial replacement before blocking poll" {
    var boundary = try handoff.Boundary.init(std.testing.io, std.testing.allocator);
    defer boundary.deinit();
    var fifo = try visual_fifo.Fifo.init(std.testing.io, std.testing.allocator);
    defer fifo.deinit();
    const pane: handoff.PaneId = @fromBackingInt(1);
    const source: handoff.SourceId = @fromBackingInt(11);
    const admitted = try registerForTest(&boundary, pane, source);
    var runtime = Runtime{
        .allocator = std.testing.allocator,
        .fifo = &fifo,
        .first_command = "sleep 30",
        .pending_lifecycle = .{
            .revision = admitted.revision,
            .operation = admitted.operation,
            .grid = .{ .pane = pane, .rows = 1, .columns = 1 },
        },
    };
    defer runtime.deinit();
    try std.testing.expect(try runtime.applyLifecycle(&boundary, "/bin/sh"));
    try std.testing.expect(try runtime.flushJournals());
    const initial = fifo.take() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(pane, initial.identity.pane);
    try std.testing.expectEqual(source, initial.identity.source);
    try std.testing.expectEqual(admitted.revision, initial.identity.lifecycle_revision);
    try fifo.complete(initial.handle);
}

test "trailing VT journal enters FIFO before child completion ownership" {
    var fifo = try visual_fifo.Fifo.init(std.testing.io, std.testing.allocator);
    defer fifo.deinit();
    const pane: handoff.PaneId = @fromBackingInt(1);
    const source: handoff.SourceId = @fromBackingInt(11);
    var owner = try Logical.init(
        std.testing.allocator,
        pane,
        source,
        @fromBackingInt(1),
        "/bin/sh",
        "sleep 30",
        .{ .pane = pane, .rows = 1, .columns = 1 },
    );
    defer owner.deinit();
    try std.testing.expect(try owner.flushJournal(&fifo));
    const initial = fifo.take().?;
    try fifo.complete(initial.handle);

    _ = try owner.machine.feedRenderByte('x', 1);
    const filler = [_]vt.render_journal.Operation{.{ .cursor = .{ .row = 0, .col = 0, .visible = false } }};
    for (0..visual_fifo.queue_capacity) |index| _ = try fifo.enqueue(.{
        .pane = @fromBackingInt(100 + index),
        .source = @fromBackingInt(200 + index),
        .lifecycle_revision = @fromBackingInt(1),
    }, .{ .operations = &filler });
    owner.stream_closed = true;
    owner.child_exit = .{ .code = 0 };
    try owner.stageCompletion(&fifo);
    try std.testing.expect(owner.pending_completion == null);
    try std.testing.expect(owner.machine.renderTransaction() != null);

    const released = fifo.take().?;
    try fifo.complete(released.handle);
    try owner.stageCompletion(&fifo);
    try std.testing.expect(owner.machine.renderTransaction() == null);
    const completion = owner.pending_completion.?;
    try std.testing.expectEqual(owner.last_visual_sequence, completion.render_sequence);
    try std.testing.expect(completion.render_sequence > released.sequence);
}
