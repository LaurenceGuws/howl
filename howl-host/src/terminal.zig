//! Owns bounded caller-driven PTY turns for logical terminal lifetimes.

const std = @import("std");
const pty = @import("howl_pty");
const render = @import("howl_render");
const vt = @import("howl_vt");
const wayland = @import("howl_wayland");
const facts = @import("terminal_runtime_facts");
const handoff = @import("terminal_handoff");
const terminal_render = render.terminal;
const terminal_images = render.terminal_images;

/// Maximum logical terminal owners serviced by one runtime thread.
const owner_limit: usize = 64;
/// Maximum child-bound bytes retained per logical terminal.
const write_queue_bytes: usize = 64 * 1024;
/// Maximum bytes accepted from one PTY during one fair turn.
const read_bytes_per_turn: usize = 64 * 1024;
/// Maximum read syscalls issued for one owner during one fair turn.
const read_calls_per_turn: usize = 4;
/// Maximum child-bound bytes attempted during one fair turn.
const write_bytes_per_turn: usize = 64 * 1024;
/// Maximum write syscalls issued for one owner during one fair turn.
const write_calls_per_turn: usize = 4;
const projection_cell_limit: usize = 32_768;
const projection_row_limit: usize = 128;
/// Current one-pane admission shared with PendingSlot and Composer's candidate frame.
const admitted_commands: usize = 4096;
/// Current one-pane resource admission shared with PendingSlot and Composer's candidate frame.
const admitted_resources: usize = 128;
/// Current realistic single-pane geometry bound; sparse output remains subject
/// to the independently checked command/resource limits.
const admitted_cells: usize = 32_768;
const image_limit: usize = 8;
const image_byte_limit: usize = 256 * 1024;

/// Reports exact bounded child-write admission failure.
const WriteQueueError = error{WriteQueueFull};
/// Reports copied reply admission or invalid VT reply-prefix consumption.
const ReplyTransferError = WriteQueueError || vt.Terminal.ReplyConsumeError;
/// Reports bounded input admission or exact mode-directed encoding failure.
const InputError = WriteQueueError || vt.Terminal.InputError ||
    vt.Terminal.ReplyConsumeError || pty.TermiosSignalError;
/// Reports stale routing, invalid keysym scalar identity, or bounded encoding failure.
const ApplyInputError = error{ UnknownPane, InvalidUnicodeScalar } ||
    InputError;
/// Reports construction failure for one complete logical PTY/VT owner.
const LogicalInitError = error{InvalidPane} ||
    error{TerminalCapacity} ||
    pty.InitError || pty.StartError || vt.Terminal.InitError ||
    render.terminal.Content.InitError || terminal_render.Error ||
    terminal_render.Content.RecoverError || terminal_render.Content.ApplyError ||
    terminal_images.Error ||
    handoff.InitError;
/// Reports runtime table or runtime-owned native-font construction failure.
const RuntimeInitError = error{ OutOfMemory, InvalidLimits } ||
    render.terminal_text.FontMapInitError;
/// Reports one bounded PTY/VT service-turn failure.
const ServiceError = pty.ReadError || pty.WriteError || pty.ObserveError ||
    vt.Terminal.FeedError || ReplyTransferError ||
    vt.Terminal.ClipboardReplyError ||
    vt.Terminal.ContainerReplyError ||
    vt.Terminal.ColorPreferenceReplyError ||
    error{ StaleContainerRequest, ContainerReplyMismatch } ||
    terminal_render.Error || terminal_render.Content.RecoverError ||
    terminal_render.Content.ApplyError || terminal_images.Error ||
    handoff.PublishError;
/// Reports a fallible VT candidate or PTY kernel resize before VT commit.
const ResizeError = vt.Terminal.ResizeError || pty.ResizeError;

/// Retains ordered encoded input and VT replies until accepted by one PTY.
const WriteQueue = struct {
    bytes: [write_queue_bytes]u8 = undefined,
    count: usize = 0,

    /// Copies one complete suffix or preserves the existing queue on full.
    fn append(self: *WriteQueue, bytes: []const u8) WriteQueueError!void {
        if (bytes.len > self.bytes.len - self.count) return error.WriteQueueFull;
        @memcpy(self.bytes[self.count..][0..bytes.len], bytes);
        self.count += bytes.len;
    }

    /// Borrows the currently ordered child-bound prefix.
    fn pending(self: *const WriteQueue) []const u8 {
        return self.bytes[0..self.count];
    }

    /// Returns exact unused child-bound capacity.
    fn remaining(self: *const WriteQueue) usize {
        return self.bytes.len - self.count;
    }

    /// Removes one accepted prefix without changing the remaining order.
    fn consume(self: *WriteQueue, count: usize) void {
        std.debug.assert(count <= self.count);
        std.mem.copyForwards(u8, self.bytes[0 .. self.count - count], self.bytes[count..self.count]);
        self.count -= count;
    }
};

/// Records one bounded service turn without exposing mutable terminal state.
const Turn = struct {
    read_bytes: usize = 0,
    read_calls: u8 = 0,
    written_bytes: usize = 0,
    write_calls: u8 = 0,
    end_of_stream: bool = false,
    published_update: bool = false,
};

const VisualState = struct {
    baseline_cells: [projection_cell_limit]terminal_render.Cell = undefined,
    baseline_geometry: [projection_row_limit]terminal_render.LineGeometry = undefined,
    baseline_cursor: terminal_render.Cursor = undefined,
    work_cells: [projection_cell_limit]terminal_render.Cell = undefined,
    work_rows: [projection_row_limit]terminal_render.RowPatch = undefined,
    image_pixels: [image_byte_limit]u8 = undefined,
    image_uploads: [image_limit]terminal_images.ImageUpload = undefined,
    image_removals: [image_limit]u32 = undefined,
    image_placements: [image_limit]terminal_images.ImagePlacement = undefined,
    image_identities: [image_limit]terminal_images.ImageIdentity = undefined,
    image_identity_count: usize = 0,
    image_generation: u64 = 0,
    rows: u16,
    cols: u16,
    initialized: bool = false,

    fn baseline(self: *const VisualState) terminal_render.ProjectionBaseline {
        const cells = @as(usize, self.rows) * self.cols;
        return .{
            .rows = self.rows,
            .cols = self.cols,
            .cursor = self.baseline_cursor,
            .cells = self.baseline_cells[0..cells],
            .geometry = self.baseline_geometry[0..self.rows],
        };
    }

    fn project(
        self: *VisualState,
        machine: *vt.Terminal,
        content: *terminal_render.Content,
    ) (terminal_render.Error || terminal_render.Content.RecoverError ||
        terminal_render.Content.ApplyError || terminal_images.Error)!void {
        const view = machine.semanticView(0);
        const dimensions_match = self.initialized and
            self.rows == view.rows and self.cols == view.cols;
        const projected = try terminal_render.project(
            view,
            machine.presentation(),
            if (dimensions_match)
                .{ .incremental = self.baseline() }
            else
                .full,
            .{ .cells = &self.work_cells, .rows = &self.work_rows },
            null,
            selectionStyle(),
        );
        const image_update = try self.projectImages(machine);
        if (dimensions_match) {
            try content.apply(
                projected,
                if (image_update.generation != self.image_generation)
                    image_update
                else
                    null,
            );
        } else {
            self.rows = view.rows;
            self.cols = view.cols;
            self.commitProjection(projected);
            try content.recover(self.baseline(), image_update);
            self.commitImageIdentities(image_update);
            self.initialized = true;
            return;
        }
        self.commitProjection(projected);
        if (image_update.generation != self.image_generation)
            self.commitImageIdentities(image_update);
    }

    fn commitProjection(self: *VisualState, update: terminal_render.Update) void {
        for (update.row_patches) |patch| {
            if (patch.cell_count != 0) {
                const destination = @as(usize, patch.row) * self.cols + patch.start_col;
                @memcpy(
                    self.baseline_cells[destination..][0..patch.cell_count],
                    update.cells[patch.cell_offset..][0..patch.cell_count],
                );
            }
            self.baseline_geometry[patch.row] = patch.geometry;
        }
        self.baseline_cursor = update.cursor;
    }

    fn projectImages(
        self: *VisualState,
        machine: *const vt.Terminal,
    ) terminal_images.Error!terminal_images.Update {
        return terminal_images.project(machine.images(0), .{
            .retained = self.image_identities[0..self.image_identity_count],
            .pixels = &self.image_pixels,
            .uploads = &self.image_uploads,
            .removals = &self.image_removals,
            .placements = &self.image_placements,
        });
    }

    fn commitImageIdentities(
        self: *VisualState,
        update: terminal_images.Update,
    ) void {
        for (update.removals) |removed| {
            var index: usize = 0;
            while (index < self.image_identity_count) : (index += 1) {
                if (self.image_identities[index].id != removed) continue;
                std.mem.copyForwards(
                    terminal_images.ImageIdentity,
                    self.image_identities[index .. self.image_identity_count - 1],
                    self.image_identities[index + 1 .. self.image_identity_count],
                );
                self.image_identity_count -= 1;
                break;
            }
        }
        for (update.uploads) |upload| {
            var found = false;
            for (self.image_identities[0..self.image_identity_count]) |*identity| {
                if (identity.id != upload.identity.id) continue;
                identity.* = upload.identity;
                found = true;
                break;
            }
            if (!found) {
                std.debug.assert(self.image_identity_count < self.image_identities.len);
                self.image_identities[self.image_identity_count] = upload.identity;
                self.image_identity_count += 1;
            }
        }
        self.image_generation = update.generation;
    }
};

/// Exclusively owns one logical terminal's PTY, VT, and child-write queue.
const Logical = struct {
    allocator: std.mem.Allocator,
    pane: render.chrome.PaneId,
    transport: pty.Owned,
    machine: vt.Terminal,
    content: render.terminal.Content,
    visual: *VisualState,
    slot: *handoff.PendingSlot,
    geometry: terminal_render.Content.Geometry,
    writes: WriteQueue = .{},
    /// The oldest caller-neutral consequence observed by this owner. Query and
    /// reply-required consequences remain retained by VT under the explicit
    /// Host policy that they do not gate PTY reads; all other families are
    /// consumed by their exact identity after bounded classification.
    consequence: ?vt.Terminal.Consequence = null,
    child_exit: ?pty.ChildExit = null,
    stream_closed: bool = false,
    dirty: bool = true,

    /// Constructs and starts one shell owner transactionally.
    fn init(
        allocator: std.mem.Allocator,
        pane: render.chrome.PaneId,
        shell: []const u8,
        command: ?[]const u8,
        cols: u16,
        rows: u16,
        fonts: *render.terminal_text.FontMap,
        slot: *handoff.PendingSlot,
    ) LogicalInitError!Logical {
        if (@backingInt(pane) == 0) return error.InvalidPane;
        const cell_count = std.math.mul(usize, rows, cols) catch
            return error.TerminalCapacity;
        if (rows > projection_row_limit or cell_count > admitted_cells)
            return error.TerminalCapacity;
        var transport = try pty.Owned.init(
            allocator,
            shell,
            command,
            null,
            .{ .term = "xterm-256color", .colorterm = "truecolor" },
        );
        errdefer transport.deinit();
        try transport.start(cols, rows);
        var machine = try vt.Terminal.init(allocator, rows, cols);
        errdefer machine.deinit();
        var content = try render.terminal.Content.init(
            allocator,
            contentLimits(),
            fonts,
        );
        errdefer content.deinit();
        const visual = try allocator.create(VisualState);
        errdefer allocator.destroy(visual);
        visual.* = .{ .rows = rows, .cols = cols };
        try visual.project(&machine, &content);
        return .{
            .allocator = allocator,
            .pane = pane,
            .transport = transport,
            .machine = machine,
            .content = content,
            .visual = visual,
            .slot = slot,
            .geometry = paneGeometry(cols, rows),
        };
    }

    /// Stops the child and releases VT then PTY ownership in reverse order.
    fn deinit(self: *Logical) void {
        self.allocator.destroy(self.visual);
        self.content.deinit();
        self.machine.deinit();
        self.transport.deinit();
        self.* = undefined;
    }

    /// Returns the borrowed master descriptor for the runtime poll set.
    fn masterFd(self: *const Logical) error{NotStarted}!std.posix.fd_t {
        return self.transport.masterFd();
    }

    /// Resizes the PTY first and commits its completely prepared VT state only afterward.
    fn resize(self: *Logical, cols: u16, rows: u16) ResizeError!void {
        var prepared = try self.machine.prepareResize(rows, cols);
        defer prepared.deinit();
        try self.transport.resize(cols, rows);
        prepared.commit();
        self.visual.rows = rows;
        self.visual.cols = cols;
        self.visual.initialized = false;
        self.geometry = paneGeometry(cols, rows);
        self.dirty = true;
    }

    /// Encodes one caller-owned input fact under current VT modes and retains it in order.
    fn input(self: *Logical, event: vt.Terminal.InputEvent) InputError!void {
        const admission = inputAdmissionBytes(event) catch
            return error.WriteQueueFull;
        const required = std.math.add(
            usize,
            admission,
            self.machine.replyBytes().len,
        ) catch return error.WriteQueueFull;
        if (required > self.writes.remaining()) return error.WriteQueueFull;
        var scratch: vt.Terminal.InputScratch = undefined;
        var encoded = try self.machine.encodeInput(
            self.allocator,
            &scratch,
            event,
        );
        defer encoded.deinit();
        std.debug.assert(encoded.bytes.len <= admission);
        if (encoded.bytes.len == 1 and self.machine.termiosSignals() and
            try self.transport.handleTermiosSignal(encoded.bytes[0]))
        {
            const replies = try collectReplies(&self.machine, &self.writes);
            std.debug.assert(replies <= write_queue_bytes);
            return;
        }
        const replies = try collectReplies(&self.machine, &self.writes);
        std.debug.assert(replies <= write_queue_bytes);
        try self.writes.append(encoded.bytes);
    }

    /// Performs one bounded ready-owner turn without blocking internally.
    fn service(
        self: *Logical,
        work: *render.terminal.Content.Work,
        readable: bool,
        writable: bool,
    ) ServiceError!Turn {
        var result = Turn{};
        if (writable and self.writes.count != 0) {
            const written = try flushWrites(&self.transport, &self.writes);
            result.written_bytes = written.written_bytes;
            result.write_calls = written.write_calls;
        }
        const pending_replies = collectReplies(&self.machine, &self.writes) catch |failure| switch (failure) {
            error.WriteQueueFull => {
                result.published_update = try self.publishIfDirty(work);
                try self.observe();
                return result;
            },
            else => return failure,
        };
        std.debug.assert(pending_replies <= write_queue_bytes);
        try self.disposeConsequence();
        if (!readable) {
            result.published_update = try self.publishIfDirty(work);
            try self.observe();
            return result;
        }
        var buffer: [read_bytes_per_turn / read_calls_per_turn]u8 = undefined;
        while (result.read_calls < read_calls_per_turn and
            result.read_bytes < read_bytes_per_turn)
        {
            result.read_calls += 1;
            const count = self.transport.read(&buffer) catch |failure| switch (failure) {
                error.Interrupted => continue,
                error.WouldBlock => break,
                error.EndOfStream => {
                    result.end_of_stream = true;
                    self.stream_closed = true;
                    break;
                },
                else => return failure,
            };
            const summary = try self.machine.feed(buffer[0..count]);
            self.dirty = self.dirty or summary.state_changed;
            result.read_bytes += count;
            const transferred = collectReplies(&self.machine, &self.writes) catch |failure| switch (failure) {
                error.WriteQueueFull => break,
                else => return failure,
            };
            std.debug.assert(transferred <= write_queue_bytes);
            try self.disposeConsequence();
        }
        result.published_update = try self.publishIfDirty(work);
        try self.observe();
        return result;
    }

    fn publishIfDirty(
        self: *Logical,
        work: *render.terminal.Content.Work,
    ) ServiceError!bool {
        if (!self.dirty) return false;
        self.slot.reserve() catch |failure| switch (failure) {
            error.Pending => return false,
            else => return failure,
        };
        self.visual.project(&self.machine, &self.content) catch |failure| {
            self.slot.cancelReserved();
            switch (failure) {
                error.InsufficientCells,
                error.InsufficientPatches,
                error.InsufficientImagePixels,
                error.InsufficientImageUploads,
                error.InsufficientImageRemovals,
                error.InsufficientImagePlacements,
                error.ImageLimit,
                error.ImagePixelLimit,
                error.PlacementLimit,
                error.ResourceMutationLimit,
                => return false,
                else => return failure,
            }
        };
        self.slot.publishReserved(&self.content, work, self.geometry) catch |failure| switch (failure) {
            error.CommandLimit,
            error.DecorationLimit,
            error.GlyphLimit,
            error.MaskLimit,
            error.ResourceMutationLimit,
            error.UploadByteLimit,
            => return false,
            else => return failure,
        };
        self.dirty = false;
        return true;
    }

    fn observe(self: *Logical) pty.ObserveError!void {
        switch (try self.transport.observeChild()) {
            .running => {},
            .exited => |exit| {
                self.child_exit = exit;
            },
        }
    }

    /// Applies one bounded Host policy to exactly the current consequence.
    ///
    /// Queries receive deterministic caller-neutral replies, so no reply-
    /// required occurrence can retain the VT queue head indefinitely.
    fn disposeConsequence(self: *Logical) ServiceError!void {
        if (self.consequence == null)
            self.consequence = pendingConsequence(&self.machine);
        const current = self.consequence orelse return;
        const identity = current.id();
        switch (current) {
            .clipboard => |request| if (request.kind == .query) {
                const replied = try self.machine.replyClipboard(identity, "");
                std.debug.assert(replied);
                self.consequence = null;
                return;
            },
            .container => |occurrence| switch (occurrence.request) {
                .report_screen_cells => try self.machine.replyContainer(
                    identity,
                    .{ .screen_cells = .{
                        .rows = self.visual.rows,
                        .cols = self.visual.cols,
                    } },
                ),
                .report_state, .report_position, .report_icon_title => try self.machine.declineContainerQuery(identity),
                else => {},
            },
            .color_preference_query => {
                try self.machine.replyColorPreference(identity, .dark);
                self.consequence = null;
                return;
            },
            .notification, .pointer_shape, .file_transfer, .drag_drop, .bell, .legacy_control, .media_copy, .dcs, .string_control => {},
        }
        if (pendingConsequence(&self.machine)) |head| {
            if (head.id() != identity) {
                self.consequence = null;
                return;
            }
        } else {
            self.consequence = null;
            return;
        }
        self.machine.consumeConsequence(identity) catch |failure| switch (failure) {
            error.ReplyRequired => unreachable,
            error.StaleConsequence => {
                self.consequence = null;
                return;
            },
        };
        self.consequence = null;
    }
};

/// Advances a stable cursor across a fixed logical-owner index domain.
const RoundRobin = struct {
    cursor: u8 = 0,

    /// Returns each index exactly once per round, beginning after the prior turn.
    fn order(self: *RoundRobin, count: u8, output: *[owner_limit]u8) []const u8 {
        if (count == 0) return output[0..0];
        for (0..count) |offset| {
            output[offset] = @intCast((@as(usize, self.cursor) + offset) % count);
        }
        self.cursor = @intCast((@as(usize, self.cursor) + 1) % count);
        return output[0..count];
    }
};

/// Reports exact logical-owner admission and identity failures.
const RuntimeError = error{
    OwnerLimit,
    DuplicatePane,
    UnknownPane,
} || LogicalInitError;
/// Reports exact owner service or native poll failure for one runtime round.
const PollError = ServiceError || error{PollFailed};

const OwnerPollSet = struct {
    descriptors: [owner_limit]std.posix.pollfd = undefined,
    owner_indices: [owner_limit]u8 = undefined,
    count: usize = 0,
};

const PollRound = struct {
    serviced: usize = 0,
    published: usize = 0,
};

/// Reports exact typed lifecycle application and slot-retirement contention.
const LifecycleError = RuntimeError || ResizeError || error{UnknownPane};

/// Creates the process-root terminal exchange with the runtime's exact Content limits.
pub fn initBoundary(
    io: std.Io,
    allocator: std.mem.Allocator,
) error{Signal}!handoff.Boundary {
    return handoff.Boundary.init(io, allocator, contentLimits());
}

/// Runs the sole terminal owner until a typed shutdown lifecycle fact arrives.
pub fn run(
    boundary: *handoff.Boundary,
    allocator: std.mem.Allocator,
    font_path: []const u8,
    shell: []const u8,
) void {
    runFallible(boundary, allocator, font_path, shell) catch |failure| {
        std.debug.print("Terminal runtime failure: {s}\n", .{@errorName(failure)});
        boundary.markStopped(true);
        return;
    };
    boundary.markStopped(false);
}

fn runFallible(
    boundary: *handoff.Boundary,
    allocator: std.mem.Allocator,
    font_path: []const u8,
    shell: []const u8,
) !void {
    var runtime = try Runtime.init(allocator, font_path);
    defer runtime.deinit();
    while (true) {
        var owner_set = try runtime.buildPollSet();
        var descriptors: [owner_limit + 1]std.posix.pollfd = undefined;
        descriptors[0] = .{
            .fd = boundary.terminalFd(),
            .events = std.posix.POLL.IN,
            .revents = 0,
        };
        const descriptor_count = owner_set.count + 1;
        @memcpy(descriptors[1..descriptor_count], owner_set.descriptors[0..owner_set.count]);
        const ready = std.posix.poll(descriptors[0..descriptor_count], -1) catch
            return error.PollFailed;
        std.debug.assert(ready <= descriptor_count);
        if (descriptors[0].revents & std.posix.POLL.IN != 0) {
            try boundary.drainTerminalWake();
            if (boundary.isStopping()) break;
            try runtime.retryPendingClose(boundary);
            var operation_count: u8 = 0;
            while (operation_count < 8) : (operation_count += 1) {
                if (runtime.pending_close != null) break;
                const operation = boundary.takeLifecycle() orelse break;
                try runtime.applyLifecycle(boundary, operation, shell);
            }
            var input_count: u8 = 0;
            while (input_count < 8) : (input_count += 1) {
                const input = boundary.takeInput() orelse break;
                try runtime.applyInput(input);
            }
            boundary.rearmTerminalWork();
            if (try runtime.servicePending() != 0) boundary.publishReady();
        }
        for (owner_set.descriptors[0..owner_set.count], descriptors[1..descriptor_count]) |*owner_descriptor, descriptor| {
            owner_descriptor.revents = descriptor.revents;
        }
        const owner_round = try runtime.servicePollSet(&owner_set);
        if (owner_round.published != 0) boundary.publishReady();
    }
    for (runtime.owners) |*maybe_owner| {
        const owner = if (maybe_owner.*) |*value| value else continue;
        const discarded = try owner.slot.retire();
        if (discarded) {}
    }
}

/// Owns the fixed logical-terminal collection and stable poll scheduling.
const Runtime = struct {
    allocator: std.mem.Allocator,
    fonts: *render.terminal_text.FontMap,
    owners: []?Logical,
    work: render.terminal.Content.Work,
    count: u8 = 0,
    scheduler: RoundRobin = .{},
    /// A dequeued close retained until its slot leaves writing/draining.
    pending_close: ?render.chrome.PaneId = null,

    /// Allocates the fixed 64-owner table without constructing children.
    fn init(
        allocator: std.mem.Allocator,
        font_path: []const u8,
    ) RuntimeInitError!Runtime {
        const owners = try allocator.alloc(?Logical, owner_limit);
        errdefer allocator.free(owners);
        @memset(owners, null);
        const fonts = try allocator.create(render.terminal_text.FontMap);
        errdefer allocator.destroy(fonts);
        fonts.* = try render.terminal_text.FontMap.init(
            allocator,
            &.{.{
                .key = .{ .slot = 0, .style = .normal },
                .native = .{ .primary = font_path, .pixel_height = 16 },
            }},
        );
        errdefer fonts.deinit();
        const work = try render.terminal.Content.Work.init(allocator, contentLimits());
        return .{
            .allocator = allocator,
            .fonts = fonts,
            .owners = owners,
            .work = work,
        };
    }

    /// Stops every live child in reverse table order and releases the table.
    fn deinit(self: *Runtime) void {
        var index = self.owners.len;
        while (index != 0) {
            index -= 1;
            if (self.owners[index]) |*owner| owner.deinit();
        }
        self.work.deinit();
        self.fonts.deinit();
        self.allocator.destroy(self.fonts);
        self.allocator.free(self.owners);
        self.* = undefined;
    }

    /// Transactionally constructs one never-zero, nonduplicate logical owner.
    fn add(
        self: *Runtime,
        pane: render.chrome.PaneId,
        shell: []const u8,
        command: ?[]const u8,
        cols: u16,
        rows: u16,
        slot: *handoff.PendingSlot,
    ) RuntimeError!void {
        if (self.find(pane) != null) return error.DuplicatePane;
        if (self.count == owner_limit) return error.OwnerLimit;
        var owner = try Logical.init(
            self.allocator,
            pane,
            shell,
            command,
            cols,
            rows,
            self.fonts,
            slot,
        );
        errdefer owner.deinit();
        const index = self.freeIndex() orelse return error.OwnerLimit;
        self.owners[index] = owner;
        self.count += 1;
    }

    /// Stops and removes one exact logical owner without reusing its PaneId.
    fn remove(self: *Runtime, pane: render.chrome.PaneId) error{UnknownPane}!void {
        const index = self.find(pane) orelse return error.UnknownPane;
        self.owners[index].?.deinit();
        self.owners[index] = null;
        self.count -= 1;
    }

    /// Runs one bounded poll round across every live borrowed master descriptor.
    fn pollOnce(self: *Runtime, timeout_ms: i32) PollError!usize {
        var owner_set = try self.buildPollSet();
        if (owner_set.count == 0) return 0;
        const ready = std.posix.poll(owner_set.descriptors[0..owner_set.count], timeout_ms) catch
            return error.PollFailed;
        std.debug.assert(ready <= owner_set.count);
        return (try self.servicePollSet(&owner_set)).serviced;
    }

    fn buildPollSet(self: *Runtime) PollError!OwnerPollSet {
        var result = OwnerPollSet{};
        for (self.owners, 0..) |*maybe_owner, index| {
            const owner = if (maybe_owner.*) |*value| value else continue;
            const write_events: i16 = if (owner.writes.count != 0)
                std.posix.POLL.OUT
            else
                0;
            result.descriptors[result.count] = .{
                .fd = try owner.masterFd(),
                .events = (if (!owner.stream_closed)
                    @as(i16, std.posix.POLL.IN | std.posix.POLL.HUP)
                else
                    0) | write_events,
                .revents = 0,
            };
            result.owner_indices[result.count] = @intCast(index);
            result.count += 1;
        }
        return result;
    }

    fn servicePollSet(self: *Runtime, owner_set: *OwnerPollSet) ServiceError!PollRound {
        var order_storage: [owner_limit]u8 = undefined;
        var serviced: usize = 0;
        var published: usize = 0;
        for (self.scheduler.order(@intCast(owner_set.count), &order_storage)) |descriptor_index| {
            const descriptor = owner_set.descriptors[descriptor_index];
            if (descriptor.revents == 0) continue;
            const owner = &self.owners[owner_set.owner_indices[descriptor_index]].?;
            const turn = try owner.service(
                &self.work,
                descriptor.revents & (std.posix.POLL.IN | std.posix.POLL.HUP) != 0,
                descriptor.revents & std.posix.POLL.OUT != 0,
            );
            std.debug.assert(turn.read_bytes <= read_bytes_per_turn);
            std.debug.assert(turn.written_bytes <= write_bytes_per_turn);
            serviced += 1;
            if (turn.published_update) published += 1;
        }
        return .{ .serviced = serviced, .published = published };
    }

    /// Gives every owner one bounded non-I/O opportunity after a runtime wake.
    fn servicePending(
        self: *Runtime,
    ) ServiceError!usize {
        var order_storage: [owner_limit]u8 = undefined;
        var indices: [owner_limit]u8 = undefined;
        var count: u8 = 0;
        for (self.owners, 0..) |owner, index| {
            if (owner == null) continue;
            indices[count] = @intCast(index);
            count += 1;
        }
        var published: usize = 0;
        for (self.scheduler.order(count, &order_storage)) |position| {
            const owner = &self.owners[indices[position]].?;
            const turn = try owner.service(&self.work, false, false);
            if (turn.published_update) published += 1;
        }
        return published;
    }

    /// Applies one terminal-boundary lifecycle fact under exclusive runtime ownership.
    fn applyLifecycle(
        self: *Runtime,
        boundary: *handoff.Boundary,
        operation: handoff.Lifecycle,
        shell: []const u8,
    ) LifecycleError!void {
        switch (operation) {
            .create => |create| {
                const slot = boundary.terminalSlot(create.pane) orelse
                    return error.UnknownPane;
                try self.add(
                    create.pane,
                    shell,
                    null,
                    create.cols,
                    create.rows,
                    slot,
                );
                try boundary.markLive(create.pane);
                return;
            },
            .resize => |resize| {
                const index = self.find(resize.pane) orelse
                    return error.UnknownPane;
                try self.owners[index].?.resize(resize.cols, resize.rows);
                return;
            },
            .close => |pane| {
                if (!try self.finishClose(boundary, pane))
                    self.pending_close = pane;
                return;
            },
        }
    }

    /// Retries the one dequeued close after Renderer signals slot drainage.
    /// A Busy result is ordinary ownership overlap, not runtime failure.
    fn retryPendingClose(self: *Runtime, boundary: *handoff.Boundary) LifecycleError!void {
        const pane = self.pending_close orelse return;
        if (try self.finishClose(boundary, pane)) self.pending_close = null;
    }

    fn finishClose(
        self: *Runtime,
        boundary: *handoff.Boundary,
        pane: render.chrome.PaneId,
    ) LifecycleError!bool {
        if (self.find(pane) == null) return error.UnknownPane;
        if (!try boundary.retireTransfer(pane)) return false;
        try self.remove(pane);
        try boundary.markRetired(pane);
        return true;
    }

    /// Routes one copied interpreted key to its exact live logical terminal.
    fn applyKey(self: *Runtime, input: handoff.KeyInput) ApplyInputError!void {
        const index = self.find(input.pane) orelse return error.UnknownPane;
        const key = try terminalKey(input.key.keysym);
        const modifiers = input.key.semantic_modifiers;
        const event = vt.Terminal.InputEvent{ .key = .{
            .key = key,
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
            .action = switch (input.key.state) {
                .pressed => .press,
                .repeated => .repeat,
                .released => .release,
            },
            .legacy_text = input.key.text[0..input.key.text_len],
            .text = input.key.text[0..input.key.text_len],
        } };
        try self.owners[index].?.input(event);
    }

    /// Routes one canonical bounded terminal input occurrence by live PaneId.
    fn applyInput(
        self: *Runtime,
        input: handoff.TerminalInput,
    ) ApplyInputError!void {
        switch (input) {
            .key => |key| try self.applyKey(key),
            .focus => |value| {
                const index = self.find(value.pane) orelse
                    return error.UnknownPane;
                try self.owners[index].?.input(value.event);
            },
        }
    }

    fn find(self: *const Runtime, pane: render.chrome.PaneId) ?usize {
        for (self.owners, 0..) |owner, index|
            if (owner != null and owner.?.pane == pane) return index;
        return null;
    }

    fn freeIndex(self: *const Runtime) ?usize {
        for (self.owners, 0..) |owner, index| if (owner == null) return index;
        return null;
    }
};

/// Copies pending VT replies before any subsequent terminal mutation.
fn collectReplies(
    terminal: *vt.Terminal,
    queue: *WriteQueue,
) ReplyTransferError!usize {
    const bytes = terminal.replyBytes();
    if (bytes.len == 0) return 0;
    try queue.append(bytes);
    try terminal.consumeReplyBytes(bytes.len);
    return bytes.len;
}

/// Attempts bounded one-shot writes and preserves every unaccepted suffix.
fn flushWrites(owner: *pty.Owned, queue: *WriteQueue) pty.WriteError!Turn {
    var result = Turn{};
    while (result.write_calls < write_calls_per_turn and
        result.written_bytes < write_bytes_per_turn and
        queue.count != 0)
    {
        result.write_calls += 1;
        const budget = @min(queue.count, write_bytes_per_turn - result.written_bytes);
        const accepted = owner.write(queue.pending()[0..budget]) catch |failure| switch (failure) {
            error.Interrupted => continue,
            error.WouldBlock => return result,
            else => return failure,
        };
        queue.consume(accepted);
        result.written_bytes += accepted;
    }
    return result;
}

/// Copies the current consequence head without consuming protocol state.
fn pendingConsequence(terminal: *const vt.Terminal) ?vt.Terminal.Consequence {
    return terminal.consequenceHead();
}

test "write queue saturation and prefix consumption are transactional" {
    var queue = WriteQueue{};
    var fill: [write_queue_bytes]u8 = undefined;
    @memset(&fill, 0xaa);
    try queue.append(&fill);
    const before = queue.bytes;
    try std.testing.expectError(error.WriteQueueFull, queue.append("x"));
    try std.testing.expectEqualSlices(u8, &before, &queue.bytes);
    queue.consume(3);
    try std.testing.expectEqual(write_queue_bytes - 3, queue.pending().len);
    try std.testing.expectEqual(@as(u8, 0xaa), queue.pending()[0]);
}

test "stable round robin gives every owner one opportunity" {
    var scheduler = RoundRobin{};
    var storage: [owner_limit]u8 = undefined;
    try std.testing.expectEqualSlices(u8, &.{ 0, 1, 2, 3 }, scheduler.order(4, &storage));
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 0 }, scheduler.order(4, &storage));
    try std.testing.expectEqualSlices(u8, &.{ 2, 3, 0, 1 }, scheduler.order(4, &storage));
    try std.testing.expectEqualSlices(u8, &.{ 3, 0, 1, 2 }, scheduler.order(4, &storage));
}

test "reply collection preserves bytes on queue saturation" {
    var terminal = try vt.Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    const summary = try terminal.feed("\x1b[5n");
    try std.testing.expect(summary.state_changed);
    try std.testing.expectEqualStrings("\x1b[0n", terminal.replyBytes());
    var queue = WriteQueue{};
    queue.count = queue.bytes.len;
    try std.testing.expectError(error.WriteQueueFull, collectReplies(&terminal, &queue));
    try std.testing.expectEqualStrings("\x1b[0n", terminal.replyBytes());
    queue.count = 0;
    try std.testing.expectEqual(@as(usize, 4), try collectReplies(&terminal, &queue));
    try std.testing.expectEqualStrings("\x1b[0n", queue.pending());
    try std.testing.expectEqualStrings("", terminal.replyBytes());
}

test "older VT replies remain ordered before newly encoded input" {
    var slot = try handoff.PendingSlot.init(
        std.testing.allocator,
        contentLimits(),
    );
    defer {
        retireTestSlot(&slot);
        slot.deinit();
    }
    var runtime = try Runtime.init(std.testing.allocator, facts.font_path);
    defer runtime.deinit();
    const pane: render.chrome.PaneId = @fromBackingInt(@intCast(1));
    try runtime.add(pane, "/bin/sh", "sleep 1", 8, 2, &slot);
    const owner = &runtime.owners[runtime.find(pane).?].?;
    const summary = try owner.machine.feed("\x1b[5n");
    try std.testing.expect(summary.state_changed);
    try owner.input(.{ .bytes = "x" });
    try std.testing.expectEqualStrings("\x1b[0nx", owner.writes.pending());
    try std.testing.expectEqualStrings("", owner.machine.replyBytes());
}

test "all consequence variants are exhaustively classified without consumption" {
    comptime {
        const fields = @typeInfo(vt.Terminal.Consequence).@"union".field_names;
        std.debug.assert(fields.len == 12);
        const expected = [_][]const u8{
            "clipboard",
            "notification",
            "pointer_shape",
            "file_transfer",
            "drag_drop",
            "container",
            "color_preference_query",
            "bell",
            "legacy_control",
            "media_copy",
            "dcs",
            "string_control",
        };
        for (fields, expected) |field, name| std.debug.assert(std.mem.eql(u8, field, name));
    }
}

test "repeated consequences are consumed by exact identity without stalling progress" {
    var slot = try handoff.PendingSlot.init(std.testing.allocator, contentLimits());
    defer {
        retireTestSlot(&slot);
        slot.deinit();
    }
    var runtime = try Runtime.init(std.testing.allocator, facts.font_path);
    defer runtime.deinit();
    const pane: render.chrome.PaneId = @fromBackingInt(@intCast(7));
    try runtime.add(pane, "/bin/sh", "sleep 1", 8, 2, &slot);
    const owner = &runtime.owners[runtime.find(pane).?].?;
    try std.testing.expect((try owner.machine.feed("\x07\x07")).state_changed);
    const first = owner.machine.consequenceHead().?;
    try std.testing.expectError(
        error.StaleConsequence,
        owner.machine.consumeConsequence(first.id() + 1),
    );
    try owner.disposeConsequence();
    try std.testing.expect(owner.machine.consequenceHead() != null);
    try owner.disposeConsequence();
    try std.testing.expect(owner.machine.consequenceHead() == null);
    try std.testing.expect((try owner.machine.feed("x")).state_changed);
    try std.testing.expectEqual(@as(u21, 'x'), owner.machine.semanticView(0).cellAt(0, 0));
}

test "reply-required consequences receive bounded Host replies and clear the head" {
    var slot = try handoff.PendingSlot.init(std.testing.allocator, contentLimits());
    defer {
        retireTestSlot(&slot);
        slot.deinit();
    }
    var runtime = try Runtime.init(std.testing.allocator, facts.font_path);
    defer runtime.deinit();
    const pane: render.chrome.PaneId = @fromBackingInt(@intCast(70));
    try runtime.add(pane, "/bin/sh", "sleep 1", 8, 2, &slot);
    const owner = &runtime.owners[runtime.find(pane).?].?;

    try std.testing.expect((try owner.machine.feed("\x1b]52;c;?\x07")).state_changed);
    try owner.disposeConsequence();
    try std.testing.expect(owner.machine.consequenceHead() == null);
    try std.testing.expect(owner.machine.replyBytes().len != 0);
    const transferred = try collectReplies(&owner.machine, &owner.writes);
    try std.testing.expect(transferred != 0);

    try std.testing.expect((try owner.machine.feed("\x1b[?996n")).state_changed);
    try owner.disposeConsequence();
    try std.testing.expect(owner.machine.consequenceHead() == null);
    try std.testing.expect(owner.machine.replyBytes().len != 0);
}

test "production terminal admission matches the Composer candidate boundary" {
    const limits = contentLimits();
    try std.testing.expectEqual(admitted_commands, limits.commands);
    try std.testing.expectEqual(admitted_resources, limits.resources_per_update);
    try std.testing.expectError(
        error.TerminalCapacity,
        Logical.init(
            std.testing.allocator,
            @as(render.chrome.PaneId, @fromBackingInt(@intCast(8))),
            "/bin/sh",
            "sleep 1",
            257,
            128,
            undefined,
            undefined,
        ),
    );
}

test "realistic configured sparse terminal fits the production Composer candidate" {
    var slot = try handoff.PendingSlot.init(std.testing.allocator, contentLimits());
    defer {
        retireTestSlot(&slot);
        slot.deinit();
    }
    var runtime = try Runtime.init(std.testing.allocator, facts.font_path);
    defer runtime.deinit();
    const pane: render.chrome.PaneId = @fromBackingInt(@intCast(10));
    try runtime.add(pane, "/bin/sh", "sleep 1", 240, 100, &slot);
    const owner = &runtime.owners[runtime.find(pane).?].?;
    try std.testing.expect((try owner.machine.feed(
        "\x1b[4mHowl terminal runtime\x1b[0m\r\n$ ",
    )).state_changed);
    try owner.visual.project(&owner.machine, &owner.content);
    var work = try render.terminal.Content.Work.init(
        std.testing.allocator,
        contentLimits(),
    );
    defer work.deinit();
    const update = try owner.content.takeUpdate(&work, owner.geometry);
    try std.testing.expect(update.commands.len <= admitted_commands);
    try std.testing.expect(update.uploads.len <= admitted_resources);
    var composer = try render.canvas.Composer.init(std.testing.allocator, .{
        .sources = 1,
        .retained_resources = 128,
        .retained_commands = 4096,
        .retained_pixel_bytes = 4 * 1024 * 1024,
        .composition_sources = 1,
        .candidate_resources = admitted_resources,
        .candidate_commands = admitted_commands,
        .candidate_pixel_bytes = 4 * 1024 * 1024,
    });
    defer composer.deinit();
    const source = try composer.registerSource();
    try composer.apply(source, update);
}

test "hostile admitted command pressure remains recoverable and retryable" {
    var slot = try handoff.PendingSlot.init(std.testing.allocator, contentLimits());
    defer {
        retireTestSlot(&slot);
        slot.deinit();
    }
    var runtime = try Runtime.init(std.testing.allocator, facts.font_path);
    defer runtime.deinit();
    const pane: render.chrome.PaneId = @fromBackingInt(@intCast(71));
    try runtime.add(pane, "/bin/sh", "sleep 1", 100, 50, &slot);
    const owner = &runtime.owners[runtime.find(pane).?].?;
    const transcript = try std.testing.allocator.alloc(u8, 5_000 * 6);
    defer std.testing.allocator.free(transcript);
    for (0..5_000) |index| {
        const sequence = if (index % 2 == 0) "\x1b[40m " else "\x1b[41m ";
        @memcpy(transcript[index * 6 ..][0..6], sequence);
    }
    try std.testing.expect((try owner.machine.feed(transcript)).state_changed);
    try std.testing.expect(!try owner.publishIfDirty(&runtime.work));
    try std.testing.expect(owner.dirty);
    try std.testing.expect(!try owner.publishIfDirty(&runtime.work));
    try slot.reserve();
    slot.cancelReserved();
}

test "close racing an occupied slot retries and retires exactly once" {
    var boundary = try initBoundary(std.testing.io, std.testing.allocator);
    defer boundary.deinit();
    var runtime = try Runtime.init(std.testing.allocator, facts.font_path);
    defer runtime.deinit();
    const pane: render.chrome.PaneId = @fromBackingInt(@intCast(9));
    const source = try render.canvas.Composer.init(std.testing.allocator, .{
        .sources = 1,
        .retained_resources = 128,
        .retained_commands = 1024,
        .retained_pixel_bytes = 4 * 1024 * 1024,
        .composition_sources = 1,
        .candidate_resources = 128,
        .candidate_commands = 1024,
        .candidate_pixel_bytes = 4 * 1024 * 1024,
    });
    var composer = source;
    defer composer.deinit();
    const source_id = try composer.registerSource();
    try boundary.register(pane, source_id, 8, 2);
    const slot = boundary.terminalSlot(pane).?;
    try runtime.add(pane, "/bin/sh", "sleep 1", 8, 2, slot);
    try boundary.close(pane);
    try slot.reserve();
    const create = boundary.takeLifecycle().?;
    try std.testing.expect(std.meta.activeTag(create) == .create);
    try runtime.applyLifecycle(&boundary, boundary.takeLifecycle().?, "/bin/sh");
    try std.testing.expect(runtime.pending_close == pane);
    slot.cancelReserved();
    try runtime.retryPendingClose(&boundary);
    try std.testing.expect(runtime.pending_close == null);
    const retired = boundary.takeRetired().?;
    try std.testing.expectEqual(pane, retired.pane);
    try composer.removeSource(retired.source);
    try boundary.finishRetired(pane);
    try std.testing.expect(runtime.find(pane) == null);
}

test "two-owner renderer drainage retires one source without stale drainage" {
    var boundary = try initBoundary(std.testing.io, std.testing.allocator);
    defer boundary.deinit();
    var composer = try render.canvas.Composer.init(std.testing.allocator, .{
        .sources = 2,
        .retained_resources = 128,
        .retained_commands = 1024,
        .retained_pixel_bytes = 4 * 1024 * 1024,
        .composition_sources = 2,
        .candidate_resources = 128,
        .candidate_commands = 1024,
        .candidate_pixel_bytes = 4 * 1024 * 1024,
    });
    defer composer.deinit();
    var runtime = try Runtime.init(std.testing.allocator, facts.font_path);
    defer runtime.deinit();
    const first: render.chrome.PaneId = @fromBackingInt(@intCast(11));
    const second: render.chrome.PaneId = @fromBackingInt(@intCast(12));
    const first_source = try composer.registerSource();
    const second_source = try composer.registerSource();
    try boundary.register(first, first_source, 8, 2);
    try boundary.register(second, second_source, 8, 2);
    try runtime.add(first, "/bin/sh", "sleep 1", 8, 2, boundary.terminalSlot(first).?);
    try runtime.add(second, "/bin/sh", "sleep 1", 8, 2, boundary.terminalSlot(second).?);
    try boundary.markLive(first);
    try boundary.markLive(second);
    try std.testing.expect(std.meta.activeTag(boundary.takeLifecycle().?) == .create);
    try std.testing.expect(std.meta.activeTag(boundary.takeLifecycle().?) == .create);
    try std.testing.expect(try runtime.servicePending() == 2);
    try std.testing.expectEqual(@as(usize, 2), try boundary.drainReady(&composer));
    var wake = std.posix.pollfd{ .fd = boundary.terminalFd(), .events = std.posix.POLL.IN, .revents = 0 };
    try std.testing.expectEqual(@as(usize, 1), @as(usize, @intCast(try std.posix.poll((&wake)[0..1], 0))));
    try boundary.drainTerminalWake();
    try boundary.close(first);
    try runtime.applyLifecycle(&boundary, boundary.takeLifecycle().?, "/bin/sh");
    const retired = boundary.takeRetired().?;
    try std.testing.expectEqual(first, retired.pane);
    try composer.removeSource(retired.source);
    try boundary.finishRetired(first);
    try std.testing.expectEqual(@as(usize, 0), try boundary.drainReady(&composer));
    try std.testing.expect(runtime.find(first) == null);
    try std.testing.expect(runtime.find(second) != null);
}

test "multiple real PTYs share one bounded poll set without noisy starvation" {
    var noisy = try testPty("i=0; while [ $i -lt 20000 ]; do printf x; i=$((i+1)); done; exit 0");
    defer noisy.deinit();
    var quiet = try testPty("printf quiet; exit 7");
    defer quiet.deinit();

    var descriptors = [_]std.posix.pollfd{
        .{ .fd = try noisy.masterFd(), .events = std.posix.POLL.IN | std.posix.POLL.HUP, .revents = 0 },
        .{ .fd = try quiet.masterFd(), .events = std.posix.POLL.IN | std.posix.POLL.HUP, .revents = 0 },
    };
    var totals = [_]usize{ 0, 0 };
    var quiet_bytes: [5]u8 = undefined;
    var quiet_count: usize = 0;
    var scheduler = RoundRobin{};
    var order_storage: [owner_limit]u8 = undefined;
    var rounds: usize = 0;
    while (quiet_count < quiet_bytes.len and rounds < 1024) : (rounds += 1) {
        const ready = try std.posix.poll(&descriptors, 20);
        try std.testing.expect(ready <= descriptors.len);
        for (scheduler.order(2, &order_storage)) |owner_index| {
            const index: usize = owner_index;
            if (descriptors[index].revents & (std.posix.POLL.IN | std.posix.POLL.HUP) == 0)
                continue;
            var buffer: [1024]u8 = undefined;
            const count = switch (index) {
                0 => noisy.read(&buffer),
                1 => quiet.read(&buffer),
                else => unreachable,
            } catch |failure| switch (failure) {
                error.WouldBlock, error.Interrupted, error.EndOfStream => continue,
                else => return failure,
            };
            totals[index] += count;
            if (index == 1) {
                const copy_count = @min(count, quiet_bytes.len - quiet_count);
                @memcpy(quiet_bytes[quiet_count..][0..copy_count], buffer[0..copy_count]);
                quiet_count += copy_count;
            }
        }
        for (&descriptors) |*descriptor| descriptor.revents = 0;
    }
    try std.testing.expectEqualStrings("quiet", quiet_bytes[0..quiet_count]);
    try std.testing.expect(totals[0] <= rounds * 1024);

    var quiet_exit: ?pty.ChildExit = null;
    for (0..1024) |_| {
        switch (try quiet.observeChild()) {
            .running => {
                const ready = try std.posix.poll(descriptors[1..2], 20);
                try std.testing.expect(ready <= 1);
                descriptors[1].revents = 0;
            },
            .exited => |value| {
                quiet_exit = value;
                break;
            },
        }
    }
    try std.testing.expectEqual(pty.ChildExit{ .code = 7 }, quiet_exit.?);
    try std.testing.expectEqual(pty.ChildObservation{ .exited = .{ .code = 7 } }, try quiet.observeChild());
}

test "real runtime measures occupied handoff fairness and Renderer drainage" {
    var noisy_slot = try handoff.PendingSlot.init(std.testing.allocator, contentLimits());
    var quiet_slot = try handoff.PendingSlot.init(std.testing.allocator, contentLimits());
    var noisy_reserved = false;
    defer {
        if (noisy_reserved) noisy_slot.cancelReserved();
        retireTestSlot(&noisy_slot);
        retireTestSlot(&quiet_slot);
        noisy_slot.deinit();
        quiet_slot.deinit();
    }
    var runtime = try Runtime.init(std.testing.allocator, facts.font_path);
    defer runtime.deinit();
    const noisy_id: render.chrome.PaneId = @fromBackingInt(@intCast(41));
    const quiet_id: render.chrome.PaneId = @fromBackingInt(@intCast(42));
    try runtime.add(
        noisy_id,
        "/bin/sh",
        "i=0; while [ $i -lt 2000000 ]; do printf x; i=$((i+1)); done; exit 0",
        16,
        16,
        &noisy_slot,
    );
    try runtime.add(
        quiet_id,
        "/bin/sh",
        "while IFS= read -r line; do printf q; done",
        16,
        16,
        &quiet_slot,
    );
    try noisy_slot.reserve();
    noisy_reserved = true;

    var composer = try render.canvas.Composer.init(std.testing.allocator, .{
        .sources = 2,
        .retained_resources = 1024,
        .retained_commands = 8192,
        .retained_pixel_bytes = 4 * 1024 * 1024,
        .composition_sources = 1,
        .candidate_resources = 1024,
        .candidate_commands = 8192,
        .candidate_pixel_bytes = 4 * 1024 * 1024,
    });
    defer composer.deinit();
    const noisy_source = try composer.registerSource();
    const quiet_source = try composer.registerSource();
    const quiet_index = runtime.find(quiet_id).?;
    var drains: usize = 0;
    var quiet_updates: usize = 0;
    var noisy_updates_after_release: usize = 0;
    var scheduler_progressions: usize = 0;
    var prior_cursor = runtime.scheduler.cursor;
    const occupied_rounds: usize = 48;
    const requested_quiet: usize = 12;
    var rounds: usize = 0;
    while (rounds < 512 and
        (quiet_updates < requested_quiet or noisy_updates_after_release == 0)) : (rounds += 1)
    {
        if (rounds % 4 == 0 and rounds / 4 < requested_quiet) {
            const owner = &runtime.owners[quiet_index].?;
            try owner.input(.{ .bytes = "tick\n" });
        }
        if (rounds == occupied_rounds) {
            noisy_slot.cancelReserved();
            noisy_reserved = false;
        }
        const serviced = try runtime.pollOnce(20);
        try std.testing.expect(serviced <= 2);
        if (try quiet_slot.drain(&composer, quiet_source)) {
            quiet_updates += 1;
            drains += 1;
        }
        if (!noisy_reserved and try noisy_slot.drain(&composer, noisy_source))
            noisy_updates_after_release += 1;
        if (runtime.scheduler.cursor != prior_cursor) scheduler_progressions += 1;
        prior_cursor = runtime.scheduler.cursor;
    }
    try std.testing.expect(quiet_updates >= requested_quiet);
    try std.testing.expect(noisy_updates_after_release != 0);
    try std.testing.expect(drains >= requested_quiet);
    try std.testing.expect(scheduler_progressions != 0);
    try std.testing.expect(noisy_updates_after_release == 1);
}

test "runtime admits observes and retires real shell owners transactionally" {
    var first_slot = try handoff.PendingSlot.init(std.testing.allocator, contentLimits());
    var second_slot = try handoff.PendingSlot.init(std.testing.allocator, contentLimits());
    var runtime = try Runtime.init(std.testing.allocator, facts.font_path);
    defer {
        runtime.deinit();
        retireTestSlot(&first_slot);
        retireTestSlot(&second_slot);
        first_slot.deinit();
        second_slot.deinit();
    }
    const first: render.chrome.PaneId = @fromBackingInt(@intCast(1));
    const second: render.chrome.PaneId = @fromBackingInt(@intCast(2));
    try std.testing.expectError(
        error.InvalidPane,
        runtime.add(@fromBackingInt(@intCast(0)), "/bin/sh", "exit 0", 16, 16, &first_slot),
    );
    try runtime.add(first, "/bin/sh", "printf first; exit 0", 16, 16, &first_slot);
    try std.testing.expectError(
        error.DuplicatePane,
        runtime.add(first, "/bin/sh", "exit 0", 16, 16, &first_slot),
    );
    try runtime.add(second, "/bin/sh", "printf second; exit 0", 16, 16, &second_slot);
    var rounds: usize = 0;
    while (rounds < 1024) : (rounds += 1) {
        const serviced = try runtime.pollOnce(20);
        try std.testing.expect(serviced <= 2);
        const first_done = runtime.owners[runtime.find(first).?].?.child_exit != null;
        const second_done = runtime.owners[runtime.find(second).?].?.child_exit != null;
        if (first_done and second_done) break;
    }
    try std.testing.expect(rounds < 1024);
    try runtime.remove(first);
    try std.testing.expectError(error.UnknownPane, runtime.remove(first));
    try runtime.remove(second);
    try std.testing.expectEqual(@as(u8, 0), runtime.count);
}

test "PTY resize failure discards prepared VT and later live resize commits" {
    var transport = try pty.Owned.init(
        std.testing.allocator,
        "/bin/sh",
        "exit 0",
        null,
        .{ .term = "xterm-256color", .colorterm = "truecolor" },
    );
    defer transport.deinit();
    var machine = try vt.Terminal.init(std.testing.allocator, 2, 4);
    defer machine.deinit();
    const fed = try machine.feed("AB");
    try std.testing.expect(fed.state_changed);
    const semantic_sequence = machine.semanticSequence();
    const cell = machine.semanticView(0).cellAt(0, 0);
    {
        var prepared = try machine.prepareResize(3, 5);
        defer prepared.deinit();
        try std.testing.expectError(error.NotStarted, transport.resize(5, 3));
    }
    const unchanged = machine.semanticView(0);
    try std.testing.expectEqual(@as(u16, 2), unchanged.rows);
    try std.testing.expectEqual(@as(u16, 4), unchanged.cols);
    try std.testing.expectEqual(cell, unchanged.cellAt(0, 0));
    try std.testing.expectEqual(semantic_sequence, machine.semanticSequence());

    var runtime = try Runtime.init(std.testing.allocator, facts.font_path);
    var slot = try handoff.PendingSlot.init(std.testing.allocator, contentLimits());
    defer {
        runtime.deinit();
        retireTestSlot(&slot);
        slot.deinit();
    }
    const pane: render.chrome.PaneId = @fromBackingInt(@intCast(1));
    try runtime.add(pane, "/bin/sh", "sleep 1", 4, 2, &slot);
    const owner = &runtime.owners[runtime.find(pane).?].?;
    const before = owner.machine.semanticSequence();
    try owner.resize(7, 3);
    const resized = owner.machine.semanticView(0);
    try std.testing.expectEqual(@as(u16, 3), resized.rows);
    try std.testing.expectEqual(@as(u16, 7), resized.cols);
    try std.testing.expectEqual(before + 1, owner.machine.semanticSequence());
    try std.testing.expect(owner.dirty);
}

test "one runtime thread publishes a real shell through the copied slot" {
    var boundary = try initBoundary(std.testing.io, std.testing.allocator);
    defer boundary.deinit();
    var composer = try render.canvas.Composer.init(std.testing.allocator, .{
        .sources = 2,
        .retained_resources = 128,
        .retained_commands = 4096,
        .retained_pixel_bytes = 4 * 1024 * 1024,
        .composition_sources = 2,
        .candidate_resources = 128,
        .candidate_commands = 4096,
        .candidate_pixel_bytes = 4 * 1024 * 1024,
    });
    defer composer.deinit();
    const pane: render.chrome.PaneId = @fromBackingInt(@intCast(1));
    const source = try composer.registerSource();
    const thread = try std.Thread.spawn(.{}, run, .{
        &boundary,
        std.testing.allocator,
        facts.font_path,
        "/bin/sh",
    });
    try boundary.register(pane, source, 8, 2);
    var drained: usize = 0;
    var descriptor = std.posix.pollfd{
        .fd = boundary.rendererFd(),
        .events = std.posix.POLL.IN,
        .revents = 0,
    };
    for (0..128) |_| {
        const ready = try std.posix.poll((&descriptor)[0..1], 20);
        try std.testing.expect(ready <= 1);
        if (ready != 0) {
            try boundary.drainRendererWake();
            drained += try boundary.drainReady(&composer);
            if (drained != 0) break;
        }
        descriptor.revents = 0;
    }
    try std.testing.expectEqual(@as(usize, 1), drained);
    boundary.shutdown();
    thread.join();
    const status = boundary.status();
    try std.testing.expect(status.stopped);
    try std.testing.expect(!status.failed);
}

test "real runtime exits when shutdown races a fully reserved lifecycle batch" {
    var boundary = try initBoundary(std.testing.io, std.testing.allocator);
    defer boundary.deinit();
    const pane: render.chrome.PaneId = @fromBackingInt(@intCast(72));
    const source: render.canvas.SourceId = @fromBackingInt(@intCast(82));
    var operations: [128]handoff.Lifecycle = undefined;
    for (&operations) |*operation| operation.* = .{ .create = .{
        .pane = pane,
        .cols = 1,
        .rows = 1,
    } };
    var candidate = try boundary.prepareLifecycle(
        &operations,
        &.{},
        .{ .pane = pane, .source = source },
    );
    defer candidate.deinit();
    const thread = try std.Thread.spawn(.{}, run, .{
        &boundary,
        std.testing.allocator,
        facts.font_path,
        "/bin/sh",
    });
    boundary.shutdown();
    try std.testing.expectError(error.Stopping, candidate.commit());
    candidate.deinit();
    thread.join();
    const status = boundary.status();
    try std.testing.expect(status.stopped);
    try std.testing.expect(!status.failed);
    try std.testing.expect(boundary.terminalSlot(pane) == null);
    try std.testing.expect(boundary.takeLifecycle() == null);
}

test "interpreted unmatched keys route by PaneId under current VT modes" {
    var slot = try handoff.PendingSlot.init(std.testing.allocator, contentLimits());
    defer {
        retireTestSlot(&slot);
        slot.deinit();
    }
    var runtime = try Runtime.init(std.testing.allocator, facts.font_path);
    defer runtime.deinit();
    const pane: render.chrome.PaneId = @fromBackingInt(@intCast(1));
    try runtime.add(pane, "/bin/sh", "sleep 1", 8, 2, &slot);
    var key = std.mem.zeroes(wayland.input.Key);
    key.state = .pressed;
    key.keysym = @fromBackingInt(@intCast('a'));
    key.text[0] = 'a';
    key.text_len = 1;
    try runtime.applyKey(.{ .pane = pane, .key = key });
    try std.testing.expectEqualStrings("a", runtime.owners[runtime.find(pane).?].?.writes.pending());
    try std.testing.expectError(
        error.UnknownPane,
        runtime.applyKey(.{
            .pane = @fromBackingInt(@intCast(2)),
            .key = key,
        }),
    );
    try std.testing.expectEqualStrings("a", runtime.owners[runtime.find(pane).?].?.writes.pending());
}

test "reaped child final output remains drainable without a busy HUP loop" {
    var slot = try handoff.PendingSlot.init(std.testing.allocator, contentLimits());
    defer {
        retireTestSlot(&slot);
        slot.deinit();
    }
    var fonts = try render.terminal_text.FontMap.init(
        std.testing.allocator,
        &.{.{
            .key = .{ .slot = 0, .style = .normal },
            .native = .{ .primary = facts.font_path, .pixel_height = 16 },
        }},
    );
    defer fonts.deinit();
    const pane: render.chrome.PaneId = @fromBackingInt(@intCast(1));
    var owner = try Logical.init(
        std.testing.allocator,
        pane,
        "/bin/sh",
        "printf final",
        8,
        2,
        &fonts,
        &slot,
    );
    defer owner.deinit();
    var work = try render.terminal.Content.Work.init(
        std.testing.allocator,
        contentLimits(),
    );
    defer work.deinit();
    for (0..256) |_| {
        try owner.observe();
        if (owner.child_exit != null) break;
        var descriptor = std.posix.pollfd{
            .fd = try owner.masterFd(),
            .events = std.posix.POLL.IN | std.posix.POLL.HUP,
            .revents = 0,
        };
        const ready = try std.posix.poll((&descriptor)[0..1], 10);
        try std.testing.expect(ready <= 1);
    }
    try std.testing.expect(owner.child_exit != null);
    for (0..256) |_| {
        const turn = try owner.service(&work, true, false);
        if (turn.end_of_stream) break;
    }
    try std.testing.expect(owner.stream_closed);
    const view = owner.machine.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'f'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'l'), view.cellAt(0, 4));
}

test "typed lifecycle creates resizes retires and never reuses pane sources" {
    var boundary = try initBoundary(std.testing.io, std.testing.allocator);
    defer boundary.deinit();
    var composer = try render.canvas.Composer.init(std.testing.allocator, .{
        .sources = 2,
        .retained_resources = 128,
        .retained_commands = 4096,
        .retained_pixel_bytes = 4 * 1024 * 1024,
        .composition_sources = 2,
        .candidate_resources = 128,
        .candidate_commands = 4096,
        .candidate_pixel_bytes = 4 * 1024 * 1024,
    });
    defer composer.deinit();
    var runtime = try Runtime.init(std.testing.allocator, facts.font_path);
    defer runtime.deinit();
    const first: render.chrome.PaneId = @fromBackingInt(@intCast(1));
    const first_source = try composer.registerSource();
    try boundary.register(first, first_source, 8, 2);
    try runtime.applyLifecycle(
        &boundary,
        boundary.takeLifecycle().?,
        "/bin/sh",
    );
    try boundary.resize(first, 10, 3);
    try runtime.applyLifecycle(
        &boundary,
        boundary.takeLifecycle().?,
        "/bin/sh",
    );
    try std.testing.expectEqual(
        @as(u16, 10),
        runtime.owners[runtime.find(first).?].?.machine.semanticView(0).cols,
    );
    try boundary.close(first);
    try runtime.applyLifecycle(
        &boundary,
        boundary.takeLifecycle().?,
        "/bin/sh",
    );
    const retired = boundary.takeRetired().?;
    try std.testing.expectEqual(first, retired.pane);
    try composer.removeSource(retired.source);
    try boundary.finishRetired(first);

    const second: render.chrome.PaneId = @fromBackingInt(@intCast(2));
    const second_source = try composer.registerSource();
    try std.testing.expect(@backingInt(second_source) > @backingInt(first_source));
    try boundary.register(second, second_source, 8, 2);
    try runtime.applyLifecycle(
        &boundary,
        boundary.takeLifecycle().?,
        "/bin/sh",
    );
}

fn contentLimits() render.terminal.Content.Limits {
    return .{
        .cells = admitted_cells,
        .rows = 128,
        .images = 8,
        .placements = 8,
        .image_bytes = 256 * 1024,
        .glyphs = 512,
        .masks = 128,
        .commands = admitted_commands,
        .resources_per_update = admitted_resources,
        .upload_bytes = 4 * 1024 * 1024,
        .raster_bytes = 4 * 1024 * 1024,
        .decoration_bytes = 256 * 1024,
    };
}

fn paneGeometry(cols: u16, rows: u16) terminal_render.Content.Geometry {
    return .{
        .x = 0,
        .y = 0,
        .clip = .{
            .x = 0,
            .y = 0,
            .width = cols * 8,
            .height = rows * 16,
        },
        .metrics = .{ .width_px = 8, .height_px = 16, .baseline_px = 12 },
        .underline_y = 14,
        .underline_height = 1,
        .strike_y = 8,
        .strike_height = 1,
    };
}

fn inputAdmissionBytes(
    event: vt.Terminal.InputEvent,
) error{WriteQueueFull}!usize {
    return switch (event) {
        .bytes => |bytes| bytes.len,
        .paste => |bytes| std.math.add(usize, bytes.len, 12) catch
            return error.WriteQueueFull,
        .key, .mouse, .focus => @sizeOf(vt.Terminal.InputScratch),
    };
}

fn terminalKey(
    keysym: wayland.input.Keysym,
) error{InvalidUnicodeScalar}!vt.Terminal.Key {
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
        0xffff => .{ .named = .delete },
        else => |value| vt.Terminal.Key.initUnicode(
            std.math.cast(u21, value) orelse return error.InvalidUnicodeScalar,
        ),
    };
}

fn selectionStyle() terminal_render.SelectionStyle {
    return .{
        .foreground = .{ .r = 255, .g = 255, .b = 255 },
        .background = .{ .r = 0, .g = 0, .b = 0 },
    };
}

fn testPty(command: []const u8) !pty.Owned {
    var result = try pty.Owned.init(
        std.testing.allocator,
        "/bin/sh",
        command,
        null,
        .{ .term = "xterm-256color", .colorterm = "truecolor" },
    );
    errdefer result.deinit();
    try result.start(80, 24);
    return result;
}

fn retireTestSlot(slot: *handoff.PendingSlot) void {
    const discarded_pending_update = slot.retire() catch unreachable;
    if (discarded_pending_update) return;
}
