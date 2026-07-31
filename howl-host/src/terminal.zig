//! Owns bounded caller-driven PTY turns for logical terminal lifetimes.

const std = @import("std");
const pty = @import("howl_pty");
const render = @import("howl_render");
const vt = @import("howl_vt");
const wayland = @import("howl_wayland");
const facts = @import("terminal_runtime_facts");
const handoff = @import("terminal_handoff");
const terminal_pool = @import("terminal_pool");
const font_owner = render.terminal_font_owner;
const terminal_render = render.terminal;
const terminal_images = render.terminal_images;

const PooledTransfer = struct {
    boundary: *handoff.Boundary,
    member: terminal_pool.Member,
};

const Transfer = union(enum) {
    dedicated: *handoff.PendingSlot,
    pooled: PooledTransfer,
};

const PoolReservation = struct {
    boundary: *handoff.Boundary,
    token: terminal_pool.Token,
    active: bool = true,

    fn publish(
        self: *PoolReservation,
        update: render.canvas.ProducerUpdate,
    ) terminal_pool.PublishError!void {
        try self.boundary.publishUpdate(self.token, update);
        self.active = false;
    }

    fn deinit(self: *PoolReservation) void {
        if (!self.active) return;
        self.boundary.cancelUpdate(self.token) catch
            @panic("pooled terminal reservation cleanup failed");
        self.active = false;
    }
};

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
const admitted_commands: usize = 32_768;
/// Complete one-pane retained-resource turnover shared with PendingSlot and
/// Composer's candidate frame: glyphs, decoration masks, and terminal images.
const admitted_resources: usize = 512 + 128 + image_limit;
/// Current realistic single-pane geometry bound; sparse output remains subject
/// to the independently checked command/resource limits.
const admitted_cells: usize = 32_768;
const image_limit: usize = 8;
const image_byte_limit: usize = 256 * 1024;
const terminal_configuration_generation: u64 = 1;

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
    error{FontCapacity} ||
    pty.InitError || pty.StartError || vt.Terminal.InitError ||
    render.terminal.Content.InitError || terminal_render.Error ||
    terminal_render.Content.RecoverError || terminal_render.Content.ApplyError ||
    terminal_images.Error ||
    handoff.InitError;
/// Reports runtime table or runtime-owned native-font construction failure.
const RuntimeInitError = error{ OutOfMemory, InvalidLimits } ||
    error{InvalidFontPolicy} ||
    render.terminal.FontMapInitError;
/// Reports one bounded PTY/VT service-turn failure.
const ServiceError = pty.ReadError || pty.WriteError || pty.ObserveError ||
    vt.Terminal.FeedError || ReplyTransferError ||
    vt.Terminal.ClipboardReplyError ||
    vt.Terminal.ContainerReplyError ||
    vt.Terminal.ColorPreferenceReplyError ||
    error{ StaleContainerRequest, ContainerReplyMismatch } ||
    terminal_render.Error || terminal_render.Content.RecoverError ||
    terminal_render.Content.ApplyError || terminal_images.Error ||
    font_owner.ResourceError || font_owner.BatchError ||
    handoff.PublishError || terminal_pool.ReserveError ||
    terminal_pool.TransitionError || terminal_pool.PublishError;
/// Reports a fallible VT candidate or PTY kernel resize before VT commit.
const ResizeError = vt.Terminal.ResizeError || pty.ResizeError ||
    error{ InvalidPane, FontCapacity, TerminalCapacity };
/// Reports bounded pane point/DPI replacement and its irreversible PTY boundary.
const FontResizeError = render.terminal.FontMapInitError ||
    font_owner.GroupError ||
    ResizeError || error{
    FontCapacity,
    Busy,
    PostKernelResizeFailure,
};

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
    baseline_scalars: vt.ScalarStorage,
    baseline_geometry: [projection_row_limit]terminal_render.LineGeometry = undefined,
    baseline_cursor: terminal_render.Cursor = undefined,
    work_cells: [projection_cell_limit]terminal_render.Cell = undefined,
    work_scalars: vt.ScalarStorage,
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

    fn init(
        allocator: std.mem.Allocator,
        rows: u16,
        cols: u16,
    ) error{OutOfMemory}!VisualState {
        var baseline_scalars = vt.ScalarStorage.init(
            allocator,
            projection_cell_limit,
        ) catch |failure| switch (failure) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCapacity => unreachable,
        };
        errdefer baseline_scalars.deinit();
        const work_scalars = vt.ScalarStorage.init(
            allocator,
            projection_cell_limit,
        ) catch |failure| switch (failure) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCapacity => unreachable,
        };
        return .{
            .baseline_scalars = baseline_scalars,
            .work_scalars = work_scalars,
            .rows = rows,
            .cols = cols,
        };
    }

    fn deinit(self: *VisualState) void {
        self.work_scalars.deinit();
        self.baseline_scalars.deinit();
        self.* = undefined;
    }

    fn baseline(self: *const VisualState) terminal_render.ProjectionBaseline {
        const cells = @as(usize, self.rows) * self.cols;
        return .{
            .rows = self.rows,
            .cols = self.cols,
            .cursor = self.baseline_cursor,
            .cells = self.baseline_cells[0..cells],
            .scalars = &self.baseline_scalars,
            .geometry = self.baseline_geometry[0..self.rows],
        };
    }

    fn scalarBaseline(self: *const VisualState) terminal_render.ScalarBaseline {
        return .retained(
            &self.baseline_scalars,
            @as(usize, self.rows) * self.cols,
        );
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
            .{
                .cells = &self.work_cells,
                .scalars = &self.work_scalars,
                .rows = &self.work_rows,
            },
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
        std.mem.swap(vt.ScalarStorage, &self.baseline_scalars, &self.work_scalars);
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

    fn requireRecovery(self: *VisualState) void {
        self.initialized = false;
        self.image_identity_count = 0;
        self.image_generation = 0;
    }
};

/// Exclusively owns one logical terminal's PTY, VT, and child-write queue.
const LogicalFontState = struct {
    request_revision: u64,
    base_point_size: f64,
    offset_points: f64,
    scale: ?handoff.ScaleSnapshot,
};

const Logical = struct {
    allocator: std.mem.Allocator,
    pane: render.chrome.PaneId,
    transport: pty.Owned,
    machine: vt.Terminal,
    fonts: *render.terminal.FontMap,
    font_group: ?font_owner.GroupRef,
    font_released_hidden: bool = false,
    font_reveal_candidate: bool = false,
    ligature_mode: render.terminal.LigatureMode = .never,
    content: render.terminal.Content,
    visual: *VisualState,
    transfer: Transfer,
    pane_pixels: render.canvas.Size,
    geometry: terminal_render.Content.Geometry,
    font_state: LogicalFontState,
    writes: WriteQueue = .{},
    /// The oldest caller-neutral consequence observed by this owner. Query and
    /// reply-required consequences remain retained by VT under the explicit
    /// Host policy that they do not gate PTY reads; all other families are
    /// consumed by their exact identity after bounded classification.
    consequence: ?vt.Terminal.Consequence = null,
    child_exit: ?pty.ChildExit = null,
    stream_closed: bool = false,
    dirty: bool = true,
    last_published_revision: render.canvas.ProducerRevision = @fromBackingInt(0),
    last_published_geometry: ?terminal_render.Content.Geometry = null,

    /// Constructs and starts one shell owner transactionally.
    fn init(
        allocator: std.mem.Allocator,
        pane: render.chrome.PaneId,
        shell: []const u8,
        command: ?[]const u8,
        pane_pixels: render.canvas.Size,
        fonts: *render.terminal.FontMap,
        font_group: ?font_owner.GroupRef,
        font_state: LogicalFontState,
        transfer: Transfer,
    ) LogicalInitError!Logical {
        if (@backingInt(pane) == 0) return error.InvalidPane;
        const metrics = fonts.cellMetrics(.{ .slot = 0, .style = .normal }) orelse
            return error.FontCapacity;
        const grid = try gridForPixels(pane_pixels, metrics);
        var transport = try pty.Owned.init(
            allocator,
            shell,
            command,
            null,
            .{ .term = "xterm-256color", .colorterm = "truecolor" },
        );
        errdefer transport.deinit();
        try transport.start(grid.cols, grid.rows);
        var machine = try vt.Terminal.init(allocator, grid.rows, grid.cols);
        errdefer machine.deinit();
        machine.setCellPixelSize(metrics.width_px, metrics.height_px) catch
            return error.FontCapacity;
        var content = try render.terminal.Content.init(
            allocator,
            contentLimits(),
            fonts,
        );
        errdefer content.deinit();
        const visual = try allocator.create(VisualState);
        errdefer allocator.destroy(visual);
        visual.* = try VisualState.init(allocator, grid.rows, grid.cols);
        errdefer visual.deinit();
        try visual.project(&machine, &content);
        return .{
            .allocator = allocator,
            .pane = pane,
            .transport = transport,
            .machine = machine,
            .fonts = fonts,
            .font_group = font_group,
            .content = content,
            .visual = visual,
            .transfer = transfer,
            .pane_pixels = pane_pixels,
            .geometry = try paneGeometry(pane_pixels, fonts),
            .font_state = font_state,
        };
    }

    /// Stops the child and releases VT then PTY ownership in reverse order.
    fn deinit(self: *Logical) void {
        self.visual.deinit();
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

    /// Replaces this pane's ligature policy and requires one complete
    /// publication only when the retained mode changes.
    fn setLigatureMode(
        self: *Logical,
        mode: render.terminal.LigatureMode,
    ) void {
        if (self.ligature_mode == mode) return;
        self.ligature_mode = mode;
        self.dirty = true;
    }

    /// Resizes the PTY first and commits its completely prepared VT state only afterward.
    fn resize(self: *Logical, pane_pixels: render.canvas.Size) ResizeError!void {
        const metrics = self.fonts.cellMetrics(.{ .slot = 0, .style = .normal }) orelse
            return error.FontCapacity;
        const grid = try gridForPixels(pane_pixels, metrics);
        const geometry = try paneGeometry(pane_pixels, self.fonts);
        const view = self.machine.semanticView(0);
        if (view.cols == grid.cols and view.rows == grid.rows) {
            self.pane_pixels = pane_pixels;
            self.geometry = geometry;
            self.last_published_geometry = null;
            self.dirty = true;
            return;
        }
        var prepared = try self.machine.prepareResize(grid.rows, grid.cols);
        defer prepared.deinit();
        try self.transport.resize(grid.cols, grid.rows);
        prepared.commit();
        self.visual.rows = grid.rows;
        self.visual.cols = grid.cols;
        self.visual.initialized = false;
        self.pane_pixels = pane_pixels;
        self.geometry = geometry;
        self.last_published_geometry = null;
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
        shared_fonts: *font_owner.Owner,
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
                result.published_update = try self.publishIfDirty(shared_fonts, work);
                try self.observe();
                return result;
            },
            else => return failure,
        };
        std.debug.assert(pending_replies <= write_queue_bytes);
        try self.disposeConsequence();
        if (!readable) {
            result.published_update = try self.publishIfDirty(shared_fonts, work);
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
        result.published_update = try self.publishIfDirty(shared_fonts, work);
        try self.observe();
        return result;
    }

    fn publishIfDirty(
        self: *Logical,
        shared_fonts: *font_owner.Owner,
        work: *render.terminal.Content.Work,
    ) ServiceError!bool {
        if (!self.dirty) return false;
        const published = switch (self.transfer) {
            .dedicated => |slot| try self.publishDedicated(slot, work),
            .pooled => |pooled| try self.publishPooled(shared_fonts, pooled, work),
        };
        if (published) self.dirty = false;
        return published;
    }

    fn publishPooled(
        self: *Logical,
        shared_fonts: *font_owner.Owner,
        pooled: PooledTransfer,
        work: *render.terminal.Content.Work,
    ) ServiceError!bool {
        const accepted = pooled.boundary.acceptedTransferRevision(
            self.pane,
            pooled.member.source_id,
        ) catch return false;
        if (@backingInt(accepted) != 0)
            try shared_fonts.observeAccepted(pooled.member.source_id, accepted);
        const token = pooled.boundary.reserveUpdate(pooled.member) catch |failure| switch (failure) {
            error.Busy, error.NoCapacity, error.GroupPriority => return false,
            else => return failure,
        };
        return self.publishReservedPooled(shared_fonts, pooled, token, work);
    }

    fn publishReservedPooled(
        self: *Logical,
        shared_fonts: *font_owner.Owner,
        pooled: PooledTransfer,
        token: terminal_pool.Token,
        work: *render.terminal.Content.Work,
    ) ServiceError!bool {
        // Close may legitimately move the Boundary entry to closing after
        // reservation and before publication. That exact Stale result cancels
        // the block and forces full recovery below. Malformed counts, pixels,
        // revisions, arithmetic, or pool ownership from canonical Content are
        // invariant failures and remain fatal after the same cleanup.
        var reservation = PoolReservation{
            .boundary = pooled.boundary,
            .token = token,
        };
        defer reservation.deinit();
        var update_consumed = false;
        defer {
            if (update_consumed) self.visual.requireRecovery();
        }
        self.visual.project(&self.machine, &self.content) catch |failure| {
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
        var producer = if (self.font_group) |group|
            try shared_fonts.producer(group)
        else
            null;
        defer if (producer) |*value| value.deinit();
        const update = self.content.takeUpdate(
            work,
            self.visual.scalarBaseline(),
            self.geometry,
            .{ .ligature_mode = self.ligature_mode },
            if (producer) |*value| .{ .shared = value } else .local,
        ) catch |failure| {
            switch (failure) {
                error.CommandLimit,
                error.DecorationLimit,
                error.GlyphLimit,
                error.MaskLimit,
                error.ResourceMutationLimit,
                error.UploadByteLimit,
                => return false,
                else => return failure,
            }
        };
        update_consumed = true;
        const batch_identity = font_owner.BatchIdentity{
            .reservation_id = token.reservation_id,
            .source = token.source_id,
            .producer_revision = update.revision,
        };
        var batch_reserved = false;
        if (self.font_group) |group| {
            shared_fonts.prepareBatch(batch_identity, group, update) catch |failure| switch (failure) {
                error.BatchLimit,
                error.ResourceLimit,
                error.RetirementPending,
                => return false,
                else => return failure,
            };
            batch_reserved = true;
        }
        defer if (batch_reserved)
            shared_fonts.cancelBatchBeforeReady(batch_identity) catch
                @panic("terminal font declaration batch cancellation failed");
        reservation.publish(update) catch |failure| switch (failure) {
            error.Stale => return false,
            error.InvalidCounts,
            error.InvalidPixels,
            error.InvalidProducerRevision,
            error.ArithmeticOverflow,
            error.Busy,
            => return failure,
        };
        if (batch_reserved) {
            try shared_fonts.markBatchReady(batch_identity);
            batch_reserved = false;
        }
        update_consumed = false;
        self.last_published_revision = update.revision;
        self.last_published_geometry = self.geometry;
        return true;
    }

    fn publishDedicated(
        self: *Logical,
        slot: *handoff.PendingSlot,
        work: *render.terminal.Content.Work,
    ) ServiceError!bool {
        slot.reserve() catch |failure| switch (failure) {
            error.Pending => return false,
            else => return failure,
        };
        var reserved = true;
        defer if (reserved) slot.cancelReserved();
        self.visual.project(&self.machine, &self.content) catch |failure| {
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
        const update = self.content.takeUpdate(
            work,
            self.visual.scalarBaseline(),
            self.geometry,
            .{ .ligature_mode = self.ligature_mode },
            .local,
        ) catch |failure| switch (failure) {
            error.CommandLimit,
            error.DecorationLimit,
            error.GlyphLimit,
            error.MaskLimit,
            error.ResourceMutationLimit,
            error.UploadByteLimit,
            => return false,
            else => return failure,
        };
        slot.publishReservedUpdate(update);
        reserved = false;
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
} || LogicalInitError || font_owner.GroupError || terminal_pool.RegisterError ||
    terminal_pool.RetireError;
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

/// Reports exact process-root terminal-boundary construction failures.
pub const BoundaryInitError = handoff.BoundaryInitError;

/// Reports exact typed lifecycle application and slot-retirement contention.
const LifecycleError = RuntimeError || ResizeError || error{UnknownPane};

/// Creates the process-root terminal exchange with the runtime's exact Content limits.
pub fn initBoundary(
    io: std.Io,
    allocator: std.mem.Allocator,
) BoundaryInitError!handoff.Boundary {
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
            try runtime.reconcileAcceptedBatches(boundary);
            try runtime.reconcileAcceptedVisibility(boundary);
            runtime.releaseCancelledLifecycleFont(boundary);
            if (runtime.count == 0) {
                if (boundary.takeFontRequest()) |request| {
                    try runtime.preflightFontRequest(request);
                    runtime.commitFontRequest(request);
                }
            }
            if (runtime.count != 0 or runtime.accepted_scale != null) {
                if (boundary.takeLifecycleAdmission()) |request| {
                    const result = runtime.validateLifecycleAdmission(request);
                    boundary.completeLifecycleAdmission(
                        request.revision,
                        result,
                    ) catch |failure| switch (failure) {
                        error.StaleRevision, error.Stopping => {
                            runtime.releaseLifecycleFont(request.revision);
                        },
                        error.CandidatePhase => return failure,
                    };
                }
            }
            try runtime.retryPendingClose(boundary);
            var operation_count: u8 = 0;
            while (operation_count < 8) : (operation_count += 1) {
                if (runtime.pending_close != null) break;
                const operation = boundary.takeAdmittedLifecycle() orelse break;
                try runtime.applyLifecycle(boundary, operation, shell);
            }
            if (!boundary.lifecycleFontStable()) {
                if (boundary.takeFontRequest()) |request| {
                    runtime.pending_font = request;
                }
            }
            try runtime.retryPendingFont(boundary);
            var input_count: u8 = 0;
            while (input_count < 8) : (input_count += 1) {
                const input = boundary.takeInput() orelse break;
                try runtime.applyInput(input);
            }
            boundary.rearmTerminalWork();
            if (try runtime.prepareVisibleSet(boundary))
                boundary.publishReady();
            if (try runtime.servicePending() != 0) boundary.publishReady();
        }
        for (owner_set.descriptors[0..owner_set.count], descriptors[1..descriptor_count]) |*owner_descriptor, descriptor| {
            owner_descriptor.revents = descriptor.revents;
        }
        const owner_round = try runtime.servicePollSet(&owner_set);
        if (owner_round.published != 0) boundary.publishReady();
    }
}

/// Retains the exact new-pane native group from admission through commit.
const PendingLifecycleFont = struct {
    revision: handoff.LifecycleRevision,
    pane: render.chrome.PaneId,
    group: font_owner.GroupRef,
    map: *render.terminal.FontMap,
};

const ResolvedGroup = struct {
    reference: font_owner.GroupRef,
    map: *render.terminal.FontMap,
};

/// Owns the fixed logical-terminal collection and stable poll scheduling.
const Runtime = struct {
    allocator: std.mem.Allocator,
    font_path: []const u8,
    fonts: *render.terminal.FontMap,
    shared_fonts: font_owner.Owner,
    owners: []?Logical,
    work: render.terminal.Content.Work,
    count: u8 = 0,
    scheduler: RoundRobin = .{},
    /// A dequeued close retained until its slot leaves writing/draining.
    pending_close: ?render.chrome.PaneId = null,
    pending_font: ?handoff.FontRequest = null,
    pending_lifecycle_font: ?PendingLifecycleFont = null,
    accepted_scale: ?handoff.ScaleSnapshot = null,
    accepted_font_policy: handoff.FontPolicy,
    accepted_font_request_revision: u64 = 0,
    accepted_visible_members: [handoff.visible_member_limit]handoff.VisibleMember = undefined,
    accepted_visible_count: u8 = 0,
    accepted_visible_revision: u64 = 0,

    /// Allocates the fixed 64-owner table without constructing children.
    fn init(
        allocator: std.mem.Allocator,
        font_path: []const u8,
    ) RuntimeInitError!Runtime {
        const owners = try allocator.alloc(?Logical, owner_limit);
        errdefer allocator.free(owners);
        @memset(owners, null);
        const fonts = try allocator.create(render.terminal.FontMap);
        errdefer allocator.destroy(fonts);
        fonts.* = try render.terminal.FontMap.init(
            allocator,
            &.{
                .{
                    .key = .{ .slot = 0, .style = .normal },
                    .native = .{ .primary = font_path, .size = .{ .pixels = 16 } },
                },
                .{
                    .key = .{ .slot = 0, .style = .bold },
                    .native = .{ .primary = font_path, .size = .{ .pixels = 16 } },
                },
                .{
                    .key = .{ .slot = 0, .style = .italic },
                    .native = .{ .primary = font_path, .size = .{ .pixels = 16 } },
                },
                .{
                    .key = .{ .slot = 0, .style = .bold_italic },
                    .native = .{ .primary = font_path, .size = .{ .pixels = 16 } },
                },
            },
        );
        errdefer fonts.deinit();
        var shared_fonts = try font_owner.Owner.init(allocator);
        errdefer shared_fonts.deinit();
        const work = try render.terminal.Content.Work.init(allocator, contentLimits());
        const font_policy = try handoff.FontPolicy.init(16.0);
        return .{
            .allocator = allocator,
            .font_path = font_path,
            .fonts = fonts,
            .shared_fonts = shared_fonts,
            .owners = owners,
            .work = work,
            .accepted_font_policy = font_policy,
        };
    }

    /// Constructs the production owner, then explicitly installs the factual
    /// point/DPI fixture required by tests that bypass lifecycle admission.
    fn initTest(
        allocator: std.mem.Allocator,
        font_path: []const u8,
    ) RuntimeInitError!Runtime {
        var result = try Runtime.init(allocator, font_path);
        errdefer result.deinit();
        const factual_size = render.terminal.Size{ .points = .{
            .points = 12.0,
            .dpi_x = .{ .numerator = 96, .denominator = 1 },
            .dpi_y = .{ .numerator = 96, .denominator = 1 },
        } };
        const factual = try render.terminal.FontMap.init(
            allocator,
            &.{
                .{
                    .key = .{ .slot = 0, .style = .normal },
                    .native = .{ .primary = font_path, .size = factual_size },
                },
                .{
                    .key = .{ .slot = 0, .style = .bold },
                    .native = .{ .primary = font_path, .size = factual_size },
                },
                .{
                    .key = .{ .slot = 0, .style = .italic },
                    .native = .{ .primary = font_path, .size = factual_size },
                },
                .{
                    .key = .{ .slot = 0, .style = .bold_italic },
                    .native = .{ .primary = font_path, .size = factual_size },
                },
            },
        );
        result.fonts.deinit();
        result.fonts.* = factual;
        return result;
    }

    /// Stops every live child in reverse table order and releases the table.
    fn deinit(self: *Runtime) void {
        if (self.pending_lifecycle_font) |pending|
            self.shared_fonts.releaseGroup(pending.group) catch
                @panic("terminal lifecycle font cleanup failed");
        var index = self.owners.len;
        while (index != 0) {
            index -= 1;
            if (self.owners[index]) |*owner| {
                const group = owner.font_group;
                if (group) |reference| {
                    var producer = self.shared_fonts.producer(reference) catch
                        @panic("terminal font group missing during cleanup");
                    defer producer.deinit();
                    owner.content.releaseFontResources(.{ .shared = &producer });
                }
                owner.deinit();
                if (group) |reference|
                    self.shared_fonts.releaseGroup(reference) catch
                        @panic("terminal font group cleanup failed");
            }
        }
        self.work.deinit();
        self.shared_fonts.deinit();
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
        pane_pixels: render.canvas.Size,
        transfer: Transfer,
    ) RuntimeError!void {
        return self.addWithGroup(
            pane,
            shell,
            command,
            pane_pixels,
            transfer,
            null,
        );
    }

    /// Constructs one owner using an exact lifecycle-retained native group.
    fn addWithGroup(
        self: *Runtime,
        pane: render.chrome.PaneId,
        shell: []const u8,
        command: ?[]const u8,
        pane_pixels: render.canvas.Size,
        transfer: Transfer,
        prepared_group: ?ResolvedGroup,
    ) RuntimeError!void {
        if (self.find(pane) != null) return error.DuplicatePane;
        if (self.count == owner_limit) return error.OwnerLimit;
        const font_state = self.logicalFontState(pane);
        const group = if (prepared_group) |candidate|
            candidate
        else if (font_state.scale != null)
            try self.pointGroup(font_state)
        else
            null;
        errdefer if (group != null and prepared_group == null) if (group) |candidate|
            self.shared_fonts.releaseGroup(candidate.reference) catch
                @panic("terminal font group construction cleanup failed");
        var owner = try Logical.init(
            self.allocator,
            pane,
            shell,
            command,
            pane_pixels,
            if (group) |candidate| candidate.map else self.fonts,
            if (group) |candidate| candidate.reference else null,
            font_state,
            transfer,
        );
        errdefer owner.deinit();
        const index = self.freeIndex() orelse return error.OwnerLimit;
        self.owners[index] = owner;
        self.count += 1;
    }

    /// Stops and removes one exact logical owner without reusing its PaneId.
    fn remove(self: *Runtime, pane: render.chrome.PaneId) error{UnknownPane}!void {
        const index = self.find(pane) orelse return error.UnknownPane;
        const group = self.owners[index].?.font_group;
        if (group) |reference| {
            var producer = self.shared_fonts.producer(reference) catch
                @panic("terminal font group missing during removal");
            defer producer.deinit();
            self.owners[index].?.content.releaseFontResources(.{ .shared = &producer });
        }
        self.owners[index].?.deinit();
        if (group) |reference|
            self.shared_fonts.releaseGroup(reference) catch
                @panic("terminal font group removal failed");
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
                &self.shared_fonts,
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
            const turn = try owner.service(&self.shared_fonts, &self.work, false, false);
            if (turn.published_update) published += 1;
        }
        return published;
    }

    /// Reconciles every accepted pooled source independently of dirty/visible state.
    fn reconcileAcceptedBatches(
        self: *Runtime,
        boundary: *handoff.Boundary,
    ) font_owner.BatchError!void {
        for (self.owners) |*maybe_owner| {
            const owner = if (maybe_owner.*) |*value| value else continue;
            const pooled = switch (owner.transfer) {
                .pooled => |value| value,
                .dedicated => continue,
            };
            const accepted = boundary.acceptedTransferRevision(
                owner.pane,
                pooled.member.source_id,
            ) catch continue;
            if (@backingInt(accepted) != 0)
                try self.shared_fonts.observeAccepted(
                    pooled.member.source_id,
                    accepted,
                );
        }
    }

    /// Releases font ownership only after Composer accepts the exact hidden set.
    fn reconcileAcceptedVisibility(
        self: *Runtime,
        boundary: *handoff.Boundary,
    ) font_owner.GroupError!void {
        const accepted = boundary.acceptedVisibleSet() orelse return;
        if (accepted.revision <= self.accepted_visible_revision) return;
        for (self.owners) |*maybe_owner| {
            const owner = if (maybe_owner.*) |*value| value else continue;
            var visible = false;
            for (accepted.members[0..accepted.count]) |member| {
                if (member.pane == owner.pane) {
                    visible = true;
                    break;
                }
            }
            if (visible) {
                owner.font_reveal_candidate = false;
                continue;
            }
            const group = owner.font_group orelse continue;
            const source = switch (owner.transfer) {
                .pooled => |pooled| pooled.member.source_id,
                .dedicated => null,
            };
            if (source) |value| self.shared_fonts.cancelSourceBatches(value);
            var producer = try self.shared_fonts.producer(group);
            owner.content.releaseFontResources(.{ .shared = &producer });
            producer.deinit();
            owner.content.rebindFonts(self.fonts, .local);
            try self.shared_fonts.releaseGroup(group);
            owner.font_group = null;
            owner.font_released_hidden = true;
            owner.font_reveal_candidate = false;
            owner.fonts = self.fonts;
            owner.visual.requireRecovery();
            owner.last_published_geometry = null;
            owner.dirty = true;
        }
        @memcpy(
            self.accepted_visible_members[0..accepted.count],
            accepted.members[0..accepted.count],
        );
        self.accepted_visible_count = accepted.count;
        self.accepted_visible_revision = accepted.revision;
    }

    fn paneIsAcceptedVisible(
        self: *const Runtime,
        pane: render.chrome.PaneId,
    ) bool {
        if (self.accepted_visible_revision == 0) return true;
        for (self.accepted_visible_members[0..self.accepted_visible_count]) |member|
            if (member.pane == pane) return true;
        return false;
    }

    fn discardSupersededRevealGroups(
        self: *Runtime,
        request: handoff.VisibleSetRequest,
    ) font_owner.GroupError!void {
        for (self.owners) |*maybe_owner| {
            const owner = if (maybe_owner.*) |*value| value else continue;
            if (!owner.font_reveal_candidate) continue;
            var requested = false;
            for (request.members[0..request.count]) |member| {
                if (member.pane == owner.pane) {
                    requested = true;
                    break;
                }
            }
            if (requested) continue;
            const group = owner.font_group orelse return error.InvalidGroup;
            var producer = try self.shared_fonts.producer(group);
            owner.content.releaseFontResources(.{ .shared = &producer });
            producer.deinit();
            owner.content.rebindFonts(self.fonts, .local);
            try self.shared_fonts.releaseGroup(group);
            owner.font_group = null;
            owner.fonts = self.fonts;
            owner.font_released_hidden = true;
            owner.font_reveal_candidate = false;
            owner.visual.requireRecovery();
            owner.last_published_geometry = null;
            owner.dirty = true;
        }
    }

    /// Attempts the retained latest font request once per external progress wake.
    fn retryPendingFont(
        self: *Runtime,
        boundary: *handoff.Boundary,
    ) (FontResizeError || error{
        InvalidFontPolicy,
        StaleFontRequest,
    })!void {
        const request = self.pending_font orelse return;
        if (boundary.lifecycleFontStable()) return;
        try self.preflightFontRequest(request);
        const completed = self.resizePointFonts(
            boundary,
            request,
        ) catch |failure| switch (failure) {
            error.Busy,
            error.InvalidMetrics,
            error.FontCapacity,
            error.TerminalCapacity,
            => false,
            else => return failure,
        };
        if (completed) self.pending_font = null;
    }

    /// Reconstructs every hidden pane required by one prospective visible set.
    fn prepareRevealGroups(
        self: *Runtime,
        request: handoff.VisibleSetRequest,
    ) FontResizeError!bool {
        var indices: [handoff.visible_member_limit]u8 = undefined;
        var groups: [handoff.visible_member_limit]ResolvedGroup = undefined;
        var prepared: [handoff.visible_member_limit]?vt.Terminal.PreparedResize =
            @splat(null);
        var rows: [handoff.visible_member_limit]u16 = undefined;
        var cols: [handoff.visible_member_limit]u16 = undefined;
        var geometries: [handoff.visible_member_limit]terminal_render.Content.Geometry =
            undefined;
        var count: usize = 0;
        var groups_owned = true;
        defer if (groups_owned) {
            var index = count;
            while (index != 0) {
                index -= 1;
                self.shared_fonts.releaseGroup(groups[index].reference) catch
                    @panic("terminal reveal group rollback failed");
            }
        };
        errdefer for (prepared[0..count]) |*candidate|
            if (candidate.*) |*value| value.deinit();

        for (request.members[0..request.count]) |member| {
            const owner_index = self.find(member.pane) orelse return false;
            const owner = &self.owners[owner_index].?;
            if (!owner.font_released_hidden) continue;
            std.debug.assert(owner.font_group == null);
            if (owner.font_state.scale == null) return false;
            const group = self.pointGroup(owner.font_state) catch |failure| switch (failure) {
                error.GroupLimit, error.RetirementPending => return false,
                else => return failure,
            };
            indices[count] = @intCast(owner_index);
            groups[count] = group;
            count += 1;
            const candidate_index = count - 1;
            const metrics =
                group.map.cellMetrics(.{ .slot = 0, .style = .normal }) orelse
                return error.FontCapacity;
            const grid = try gridForPixels(owner.pane_pixels, metrics);
            prepared[candidate_index] =
                try owner.machine.prepareResize(grid.rows, grid.cols);
            rows[candidate_index] = grid.rows;
            cols[candidate_index] = grid.cols;
            geometries[candidate_index] =
                try paneGeometry(owner.pane_pixels, group.map);
        }
        if (count == 0) return true;

        var kernel_committed = false;
        for (indices[0..count], 0..) |owner_index, index| {
            const owner = &self.owners[owner_index].?;
            owner.transport.resize(cols[index], rows[index]) catch |failure| {
                if (kernel_committed) return error.PostKernelResizeFailure;
                return failure;
            };
            kernel_committed = true;
            prepared[index].?.commit();
            const metrics = geometries[index].metrics;
            owner.machine.setCellPixelSize(
                metrics.width_px,
                metrics.height_px,
            ) catch return error.PostKernelResizeFailure;
        }
        for (indices[0..count], 0..) |owner_index, index| {
            const owner = &self.owners[owner_index].?;
            owner.fonts = groups[index].map;
            owner.font_group = groups[index].reference;
            owner.font_released_hidden = false;
            owner.font_reveal_candidate = true;
            owner.content.rebindFonts(groups[index].map, .local);
            owner.visual.rows = rows[index];
            owner.visual.cols = cols[index];
            owner.visual.requireRecovery();
            owner.geometry = geometries[index];
            owner.last_published_geometry = null;
            owner.dirty = true;
        }
        groups_owned = false;
        return true;
    }

    /// Prepares the latest complete visible set without consuming a partial group.
    fn prepareVisibleSet(
        self: *Runtime,
        boundary: *handoff.Boundary,
    ) (ServiceError || FontResizeError)!bool {
        const request = boundary.visibleSetRequest() orelse return false;
        try self.discardSupersededRevealGroups(request);
        if (!try self.prepareRevealGroups(request)) return false;
        var requirements: [handoff.visible_member_limit]handoff.VisibleRequirement = undefined;
        var needed_members: [handoff.visible_member_limit]terminal_pool.Member = undefined;
        var needed_positions: [handoff.visible_member_limit]u8 = undefined;
        var needed_count: usize = 0;

        for (request.members[0..request.count], 0..) |member, position| {
            const owner_index = self.find(member.pane) orelse return false;
            const owner = &self.owners[owner_index].?;
            const pooled = switch (owner.transfer) {
                .pooled => |value| value,
                .dedicated => return false,
            };
            if (pooled.member.source_id != member.source) return false;
            const fact = boundary.visibleTransferFact(request.revision, member) catch
                return false;
            if (@backingInt(fact.accepted_revision) != 0)
                try self.shared_fonts.observeAccepted(
                    member.source,
                    fact.accepted_revision,
                );
            const geometry_current = owner.last_published_geometry != null and
                std.meta.eql(owner.last_published_geometry.?, owner.geometry);
            if (fact.ready) |token| {
                if (owner.dirty or !geometry_current or
                    token.producer_revision != owner.last_published_revision)
                    return false;
                requirements[position] = .{
                    .member = member,
                    .revision = token.producer_revision,
                };
                continue;
            }
            if (!owner.dirty and geometry_current and
                @backingInt(owner.last_published_revision) != 0 and
                @backingInt(fact.accepted_revision) >=
                    @backingInt(owner.last_published_revision))
            {
                requirements[position] = .{
                    .member = member,
                    .revision = owner.last_published_revision,
                };
                continue;
            }
            needed_members[needed_count] = pooled.member;
            needed_positions[needed_count] = @intCast(position);
            needed_count += 1;
        }

        if (needed_count == 0) {
            boundary.completeVisibleSet(
                request.revision,
                requirements[0..request.count],
                false,
            ) catch return false;
            return true;
        }
        const group = boundary.reserveVisibleGroup(
            request.revision,
            needed_members[0..needed_count],
        ) catch |failure| switch (failure) {
            error.NoCapacity, error.Busy, error.GroupPriority, error.Stale => return false,
            else => return failure,
        };
        var group_active = true;
        defer if (group_active)
            boundary.abortVisibleGroup(request.revision) catch {};
        for (group.tokens[0..group.count], 0..) |token, group_index| {
            const position = needed_positions[group_index];
            const member = request.members[position];
            const owner_index = self.find(member.pane) orelse return false;
            const owner = &self.owners[owner_index].?;
            const pooled = switch (owner.transfer) {
                .pooled => |value| value,
                .dedicated => return false,
            };
            if (!try owner.publishReservedPooled(
                &self.shared_fonts,
                pooled,
                token,
                &self.work,
            ))
                return false;
            owner.dirty = false;
            requirements[position] = .{
                .member = member,
                .revision = owner.last_published_revision,
            };
        }
        boundary.completeVisibleSet(
            request.revision,
            requirements[0..request.count],
            true,
        ) catch |failure| switch (failure) {
            error.Stale, error.Partial => return false,
        };
        group_active = false;
        return true;
    }

    /// Applies one terminal-boundary lifecycle fact under exclusive runtime ownership.
    fn applyLifecycle(
        self: *Runtime,
        boundary: *handoff.Boundary,
        admitted: handoff.AdmittedLifecycle,
        shell: []const u8,
    ) LifecycleError!void {
        switch (admitted.operation) {
            .create => |create| {
                const exact = admitted.grid orelse return error.InvalidPane;
                const pending = self.pending_lifecycle_font orelse
                    return error.FontCapacity;
                if (pending.revision != admitted.revision or
                    pending.pane != create.pane)
                    return error.FontCapacity;
                const derived = gridForPixels(
                    create.pixels,
                    pending.map.cellMetrics(.{
                        .slot = 0,
                        .style = .normal,
                    }) orelse return error.FontCapacity,
                ) catch return error.TerminalCapacity;
                if (exact.pane != create.pane or exact.rows != derived.rows or
                    exact.columns != derived.cols)
                    return error.TerminalCapacity;
                const member = boundary.activateTransfer(create.pane) catch
                    return error.UnknownPane;
                try self.addWithGroup(
                    create.pane,
                    shell,
                    null,
                    create.pixels,
                    .{ .pooled = .{
                        .boundary = boundary,
                        .member = member,
                    } },
                    .{
                        .reference = pending.group,
                        .map = pending.map,
                    },
                );
                self.pending_lifecycle_font = null;
                try boundary.markLive(create.pane);
                return;
            },
            .resize => |resize| {
                const exact = admitted.grid orelse return error.InvalidPane;
                const index = self.find(resize.pane) orelse
                    return error.UnknownPane;
                const owner = &self.owners[index].?;
                const derived = gridForPixels(
                    resize.pixels,
                    owner.fonts.cellMetrics(.{
                        .slot = 0,
                        .style = .normal,
                    }) orelse return error.FontCapacity,
                ) catch return error.TerminalCapacity;
                if (exact.pane != resize.pane or exact.rows != derived.rows or
                    exact.columns != derived.cols)
                    return error.TerminalCapacity;
                try owner.resize(resize.pixels);
                return;
            },
            .close => |pane| {
                if (!try self.finishClose(boundary, pane))
                    self.pending_close = pane;
                return;
            },
        }
    }

    /// Derives one exact mutation-free admission result from current metrics.
    fn validateLifecycleAdmission(
        self: *Runtime,
        request: handoff.RuntimeAdmissionCopy,
    ) handoff.LifecycleAdmissionResult {
        std.debug.assert(self.pending_lifecycle_font == null);
        var candidate_group: ?struct {
            pane: render.chrome.PaneId,
            reference: font_owner.GroupRef,
            map: *render.terminal.FontMap,
        } = null;
        var retained = false;
        defer if (!retained) if (candidate_group) |candidate|
            self.shared_fonts.releaseGroup(candidate.reference) catch
                @panic("terminal lifecycle font admission cleanup failed");
        var seen: [owner_limit + 1]render.chrome.PaneId = undefined;
        var seen_count: usize = 0;
        var result = handoff.LifecycleAdmissionResult{ .admitted = .{
            .count = 0,
        } };
        for (request.operations[0..request.operation_count]) |operation| {
            const pane = switch (operation) {
                .create => |value| value.pane,
                .resize => |value| value.pane,
                .close => |value| value,
            };
            if (@backingInt(pane) == 0)
                return .{ .rejected = .invalid_pane };
            for (seen[0..seen_count]) |prior|
                if (prior == pane) return .{ .rejected = .duplicate_pane };
            seen[seen_count] = pane;
            seen_count += 1;
            switch (operation) {
                .create => |value| {
                    if (self.find(value.pane) != null)
                        return .{ .rejected = .duplicate_pane };
                    if (request.registration == null or
                        request.registration.?.pane != value.pane or
                        @backingInt(request.registration.?.source) == 0)
                        return .{ .rejected = .invalid_pane };
                    const resolved = self.pointGroup(
                        self.logicalFontState(value.pane),
                    ) catch return .{ .rejected = .font_capacity };
                    candidate_group = .{
                        .pane = value.pane,
                        .reference = resolved.reference,
                        .map = resolved.map,
                    };
                    const metrics = resolved.map.cellMetrics(.{
                        .slot = 0,
                        .style = .normal,
                    }) orelse return .{ .rejected = .font_capacity };
                    const grid = gridForPixels(value.pixels, metrics) catch |failure|
                        return .{ .rejected = switch (failure) {
                            error.InvalidPane => .invalid_extent,
                            error.FontCapacity => .font_capacity,
                            error.TerminalCapacity => .terminal_capacity,
                        } };
                    const index = result.admitted.count;
                    result.admitted.grids[index] = .{
                        .pane = value.pane,
                        .rows = grid.rows,
                        .columns = grid.cols,
                    };
                    result.admitted.count += 1;
                },
                .resize => |value| {
                    const owner_index = self.find(value.pane) orelse
                        return .{ .rejected = .unknown_pane };
                    const metrics = self.owners[owner_index].?.fonts.cellMetrics(.{
                        .slot = 0,
                        .style = .normal,
                    }) orelse return .{ .rejected = .font_capacity };
                    const grid = gridForPixels(value.pixels, metrics) catch |failure|
                        return .{ .rejected = switch (failure) {
                            error.InvalidPane => .invalid_extent,
                            error.FontCapacity => .font_capacity,
                            error.TerminalCapacity => .terminal_capacity,
                        } };
                    const index = result.admitted.count;
                    result.admitted.grids[index] = .{
                        .pane = value.pane,
                        .rows = grid.rows,
                        .columns = grid.cols,
                    };
                    result.admitted.count += 1;
                },
                .close => |pane_id| {
                    if (self.find(pane_id) == null)
                        return .{ .rejected = .unknown_pane };
                },
            }
        }
        for (request.inputs[0..request.input_count]) |input| {
            const pane = switch (input) {
                .key => |value| value.pane,
                .focus => |value| value.pane,
            };
            const registered = request.registration != null and
                request.registration.?.pane == pane;
            if (!registered and self.find(pane) == null)
                return .{ .rejected = .unknown_pane };
        }
        if (candidate_group) |candidate| {
            self.pending_lifecycle_font = .{
                .revision = request.revision,
                .pane = candidate.pane,
                .group = candidate.reference,
                .map = candidate.map,
            };
            retained = true;
        }
        return result;
    }

    fn releaseLifecycleFont(
        self: *Runtime,
        revision: handoff.LifecycleRevision,
    ) void {
        const pending = self.pending_lifecycle_font orelse return;
        if (pending.revision != revision) return;
        self.shared_fonts.releaseGroup(pending.group) catch
            @panic("terminal lifecycle font cancellation failed");
        self.pending_lifecycle_font = null;
    }

    fn releaseCancelledLifecycleFont(
        self: *Runtime,
        boundary: *handoff.Boundary,
    ) void {
        const pending = self.pending_lifecycle_font orelse return;
        if (!boundary.retainsLifecycleRevision(pending.revision))
            self.releaseLifecycleFont(pending.revision);
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
        const owner_index = self.find(pane) orelse return error.UnknownPane;
        switch (self.owners[owner_index].?.transfer) {
            .pooled => |pooled| self.shared_fonts.cancelSourceBatches(pooled.member.source_id),
            .dedicated => {},
        }
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

    fn preflightFontRequest(
        self: *const Runtime,
        request: handoff.FontRequest,
    ) error{ InvalidFontPolicy, StaleFontRequest }!void {
        if (request.revision <= self.accepted_font_request_revision)
            return error.StaleFontRequest;
        if (!validFontPolicy(request.policy)) return error.InvalidFontPolicy;
    }

    fn commitFontRequest(self: *Runtime, request: handoff.FontRequest) void {
        std.debug.assert(request.revision > self.accepted_font_request_revision);
        std.debug.assert(validFontPolicy(request.policy));
        for (self.owners) |*maybe_owner| {
            const owner = if (maybe_owner.*) |*value| value else continue;
            owner.font_state = .{
                .request_revision = request.revision,
                .base_point_size = request.policy.base_point_size,
                .offset_points = fontOffsetFor(request.policy, owner.pane),
                .scale = request.scale,
            };
        }
        self.accepted_font_request_revision = request.revision;
        self.accepted_font_policy = request.policy;
        self.accepted_scale = request.scale;
    }

    fn logicalFontState(
        self: *const Runtime,
        pane: render.chrome.PaneId,
    ) LogicalFontState {
        return .{
            .request_revision = self.accepted_font_request_revision,
            .base_point_size = self.accepted_font_policy.base_point_size,
            .offset_points = fontOffsetFor(self.accepted_font_policy, pane),
            .scale = self.accepted_scale,
        };
    }

    fn pointGroup(
        self: *Runtime,
        state: LogicalFontState,
    ) (font_owner.GroupError || error{FontCapacity})!ResolvedGroup {
        const key = try resolvedGroupKey(state);
        const configs = pointGroupConfigs(self.font_path, key);
        const reference = try self.shared_fonts.acquireGroup(key, &configs);
        errdefer self.shared_fonts.releaseGroup(reference) catch
            @panic("terminal font candidate rollback failed");
        return .{
            .reference = reference,
            .map = try self.shared_fonts.mapFor(reference),
        };
    }

    fn stagePointGroup(
        self: *Runtime,
        state: LogicalFontState,
    ) (font_owner.GroupError || error{FontCapacity})!ResolvedGroup {
        const key = try resolvedGroupKey(state);
        const configs = pointGroupConfigs(self.font_path, key);
        const reference = try self.shared_fonts.stageGroup(key, &configs);
        errdefer self.shared_fonts.discardGroup(reference) catch
            @panic("terminal font staged candidate rollback failed");
        return .{
            .reference = reference,
            .map = try self.shared_fonts.stagedMapFor(reference),
        };
    }

    /// Applies one complete factual point/DPI transaction to changed panes.
    fn resizePointFonts(
        self: *Runtime,
        boundary: *handoff.Boundary,
        request: handoff.FontRequest,
    ) FontResizeError!bool {
        if (!boundary.fontQuiescent()) return error.Busy;
        if (request.scale == null) {
            self.commitFontRequest(request);
            return true;
        }
        var groups: [owner_limit]?font_owner.GroupRef = @splat(null);
        var maps: [owner_limit]?*render.terminal.FontMap = @splat(null);
        var old_producers: [owner_limit]?font_owner.Producer = @splat(null);
        defer for (&old_producers) |*producer| if (producer.*) |*value| {
            value.deinit();
            producer.* = null;
        };
        var prepared: [owner_limit]?vt.Terminal.PreparedResize = @splat(null);
        var new_cols: [owner_limit]u16 = undefined;
        var new_rows: [owner_limit]u16 = undefined;
        var new_geometry: [owner_limit]terminal_render.Content.Geometry = undefined;
        var changed_indices: [owner_limit]u8 = undefined;
        var state_indices: [owner_limit]u8 = undefined;
        var candidate_states: [owner_limit]LogicalFontState = undefined;
        var old_group_refs: [owner_limit]font_owner.GroupRef = undefined;
        var staged_group_refs: [owner_limit]font_owner.GroupRef = undefined;
        var changed_count: usize = 0;
        var state_count: usize = 0;
        var transition_count: usize = 0;
        var acquired_groups: [owner_limit]bool = @splat(false);
        var staged_owned = true;
        defer if (staged_owned) {
            var index = transition_count;
            while (index != 0) {
                index -= 1;
                self.shared_fonts.discardGroup(staged_group_refs[index]) catch
                    @panic("terminal font candidate cleanup failed");
            }
        };
        var acquired_owned = true;
        defer if (acquired_owned) for (acquired_groups, 0..) |acquired, index| {
            if (acquired)
                self.shared_fonts.releaseGroup(groups[index].?) catch
                    @panic("terminal font initial-group cleanup failed");
        };
        errdefer for (&prepared) |*candidate| if (candidate.*) |*value| value.deinit();

        for (self.owners, 0..) |*maybe_owner, index| {
            const owner = if (maybe_owner.*) |*value| value else continue;
            const state = LogicalFontState{
                .request_revision = request.revision,
                .base_point_size = request.policy.base_point_size,
                .offset_points = fontOffsetFor(request.policy, owner.pane),
                .scale = request.scale,
            };
            const new_key = try resolvedGroupKey(state);
            if (owner.font_state.base_point_size != state.base_point_size or
                owner.font_state.offset_points != state.offset_points or
                !std.meta.eql(owner.font_state.scale, state.scale))
            {
                state_indices[state_count] = @intCast(index);
                candidate_states[state_count] = state;
                state_count += 1;
            }
            if (!self.paneIsAcceptedVisible(owner.pane)) continue;
            if (owner.font_group) |old_group| {
                const old_key = try self.shared_fonts.keyFor(old_group);
                if (std.meta.eql(new_key, old_key)) continue;
                old_producers[index] = try self.shared_fonts.producer(old_group);
                const group = try self.stagePointGroup(state);
                groups[index] = group.reference;
                maps[index] = group.map;
                old_group_refs[transition_count] = old_group;
                staged_group_refs[transition_count] = group.reference;
                transition_count += 1;
            } else {
                const group = try self.pointGroup(state);
                groups[index] = group.reference;
                maps[index] = group.map;
                acquired_groups[index] = true;
            }
            changed_indices[changed_count] = @intCast(index);
            changed_count += 1;
            const metrics = maps[index].?.cellMetrics(.{ .slot = 0, .style = .normal }) orelse
                return error.FontCapacity;
            const grid = try gridForPixels(owner.pane_pixels, metrics);
            prepared[index] = try owner.machine.prepareResize(grid.rows, grid.cols);
            new_cols[index] = grid.cols;
            new_rows[index] = grid.rows;
            new_geometry[index] = try paneGeometry(
                owner.pane_pixels,
                maps[index].?,
            );
        }
        var group_transition = try self.shared_fonts.prepareGroupTransition(
            old_group_refs[0..transition_count],
            staged_group_refs[0..transition_count],
        );
        staged_owned = false;
        defer group_transition.deinit();
        var kernel_committed = false;
        for (changed_indices[0..changed_count]) |owner_index| {
            const index: usize = owner_index;
            const owner = &self.owners[index].?;
            owner.transport.resize(new_cols[index], new_rows[index]) catch |failure| {
                if (kernel_committed) return error.PostKernelResizeFailure;
                return failure;
            };
            kernel_committed = true;
            prepared[index].?.commit();
            const metrics = new_geometry[index].metrics;
            owner.machine.setCellPixelSize(metrics.width_px, metrics.height_px) catch
                return error.PostKernelResizeFailure;
        }
        group_transition.commit();
        for (changed_indices[0..changed_count]) |owner_index| {
            const index: usize = owner_index;
            const owner = &self.owners[index].?;
            owner.fonts = maps[index].?;
            owner.font_group = groups[index];
            owner.content.rebindFonts(
                maps[index].?,
                if (old_producers[index]) |*producer|
                    .{ .shared = producer }
                else
                    .local,
            );
            owner.visual.rows = new_rows[index];
            owner.visual.cols = new_cols[index];
            owner.visual.initialized = false;
            owner.geometry = new_geometry[index];
            owner.last_published_geometry = null;
            owner.dirty = true;
        }
        for (&old_producers) |*producer| if (producer.*) |*value| {
            value.deinit();
            producer.* = null;
        };
        acquired_owned = false;
        for (state_indices[0..state_count], candidate_states[0..state_count]) |
            owner_index,
            state,
        | self.owners[owner_index].?.font_state = state;
        self.accepted_font_request_revision = request.revision;
        self.accepted_font_policy = request.policy;
        self.accepted_scale = request.scale;
        return true;
    }
};

fn resolvedGroupKey(
    state: LogicalFontState,
) error{FontCapacity}!font_owner.GroupKey {
    const scale = state.scale orelse return error.FontCapacity;
    const dpi_x = render.terminal.Dpi{
        .numerator = scale.dpi_x.numerator,
        .denominator = scale.dpi_x.denominator,
    };
    const dpi_y = render.terminal.Dpi{
        .numerator = scale.dpi_y.numerator,
        .denominator = scale.dpi_y.denominator,
    };
    const factual_x = @as(f64, @floatFromInt(dpi_x.numerator)) /
        @as(f64, @floatFromInt(dpi_x.denominator));
    const factual_y = @as(f64, @floatFromInt(dpi_y.numerator)) /
        @as(f64, @floatFromInt(dpi_y.denominator));
    const floor = @max(72.0 / factual_x, 72.0 / factual_y);
    const raw = state.base_point_size + state.offset_points;
    const point_size = std.math.clamp(
        raw,
        floor,
        16.0 * 10.0,
    );
    return .{
        .configuration_generation = terminal_configuration_generation,
        .point_size = point_size,
        .logical_dpi_x = dpi_x,
        .logical_dpi_y = dpi_y,
    };
}

fn pointGroupConfigs(
    font_path: []const u8,
    key: font_owner.GroupKey,
) [4]render.terminal.FontConfig {
    const size = render.terminal.Size{ .points = .{
        .points = key.point_size,
        .dpi_x = key.logical_dpi_x,
        .dpi_y = key.logical_dpi_y,
    } };
    return .{
        .{ .key = .{ .slot = 0, .style = .normal }, .native = .{ .primary = font_path, .size = size } },
        .{ .key = .{ .slot = 0, .style = .bold }, .native = .{ .primary = font_path, .size = size } },
        .{ .key = .{ .slot = 0, .style = .italic }, .native = .{ .primary = font_path, .size = size } },
        .{ .key = .{ .slot = 0, .style = .bold_italic }, .native = .{ .primary = font_path, .size = size } },
    };
}

fn validFontPolicy(policy: handoff.FontPolicy) bool {
    if (!std.math.isFinite(policy.base_point_size) or
        std.math.isNan(policy.base_point_size) or
        policy.base_point_size <= 0.0 or policy.count > owner_limit)
        return false;
    var previous: u64 = 0;
    for (policy.offsets[0..policy.count]) |offset| {
        const pane = @backingInt(offset.pane);
        if (pane == 0 or pane <= previous or
            !std.math.isFinite(offset.offset_points) or
            std.math.isNan(offset.offset_points) or
            offset.offset_points == 0.0)
            return false;
        previous = pane;
    }
    return true;
}

fn fontOffsetFor(
    policy: handoff.FontPolicy,
    pane: render.chrome.PaneId,
) f64 {
    for (policy.offsets[0..policy.count]) |offset| {
        const retained = @backingInt(offset.pane);
        const requested = @backingInt(pane);
        if (retained == requested) return offset.offset_points;
        if (retained > requested) break;
    }
    return 0.0;
}

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
    var runtime = try Runtime.initTest(std.testing.allocator, facts.font_path);
    defer runtime.deinit();
    const pane: render.chrome.PaneId = @fromBackingInt(@intCast(1));
    try runtime.add(pane, "/bin/sh", "sleep 1", try testPixels(runtime.fonts, 8, 2), .{ .dedicated = &slot });
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
    var runtime = try Runtime.initTest(std.testing.allocator, facts.font_path);
    defer runtime.deinit();
    const pane: render.chrome.PaneId = @fromBackingInt(@intCast(7));
    try runtime.add(pane, "/bin/sh", "sleep 1", try testPixels(runtime.fonts, 8, 2), .{ .dedicated = &slot });
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
    var runtime = try Runtime.initTest(std.testing.allocator, facts.font_path);
    defer runtime.deinit();
    const pane: render.chrome.PaneId = @fromBackingInt(@intCast(70));
    try runtime.add(pane, "/bin/sh", "sleep 1", try testPixels(runtime.fonts, 8, 2), .{ .dedicated = &slot });
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
        gridForPixels(
            .{ .width = std.math.maxInt(u16), .height = std.math.maxInt(u16) },
            .{ .width_px = 1, .height_px = 1, .baseline_px = 0 },
        ),
    );
}

test "realistic configured sparse terminal fits the production Composer candidate" {
    var slot = try handoff.PendingSlot.init(std.testing.allocator, contentLimits());
    defer {
        retireTestSlot(&slot);
        slot.deinit();
    }
    var runtime = try Runtime.initTest(std.testing.allocator, facts.font_path);
    defer runtime.deinit();
    const pane: render.chrome.PaneId = @fromBackingInt(@intCast(10));
    try runtime.add(pane, "/bin/sh", "sleep 1", try testPixels(runtime.fonts, 240, 100), .{ .dedicated = &slot });
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
    const update = try owner.content.takeLocalUpdate(
        &work,
        owner.visual.scalarBaseline(),
        owner.geometry,
    );
    try std.testing.expect(update.commands.len <= admitted_commands);
    try std.testing.expect(update.uploads.len <= admitted_resources);
    var composer = try render.canvas.Composer.init(std.testing.allocator, .{
        .sources = 2,
        .retained_resources = admitted_resources,
        .retained_commands = 4096,
        .retained_pixel_bytes = 4 * 1024 * 1024,
        .composition_sources = 2,
        .candidate_resources = admitted_resources,
        .candidate_commands = admitted_commands,
        .candidate_pixel_bytes = 4 * 1024 * 1024,
    });
    defer composer.deinit();
    const source = try composer.registerSource();
    try composer.apply(source, update);
}

test "alternate-screen exit publishes complete retained resource turnover" {
    var slot = try handoff.PendingSlot.init(std.testing.allocator, contentLimits());
    defer {
        retireTestSlot(&slot);
        slot.deinit();
    }
    var runtime = try Runtime.initTest(std.testing.allocator, facts.font_path);
    defer runtime.deinit();
    const pane: render.chrome.PaneId = @fromBackingInt(72);
    try runtime.add(pane, "/bin/sh", "sleep 1", try testPixels(runtime.fonts, 100, 5), .{ .dedicated = &slot });
    const owner = &runtime.owners[runtime.find(pane).?].?;
    var composer = try render.canvas.Composer.init(std.testing.allocator, .{
        .sources = 1,
        .retained_resources = admitted_resources,
        .retained_commands = admitted_commands,
        .retained_pixel_bytes = 4 * 1024 * 1024,
        .composition_sources = 1,
        .candidate_resources = admitted_resources,
        .candidate_commands = admitted_commands,
        .candidate_pixel_bytes = 4 * 1024 * 1024,
    });
    defer composer.deinit();
    const source = try composer.registerSource();

    try owner.visual.project(&owner.machine, &owner.content);
    try composer.apply(
        source,
        try owner.content.takeLocalUpdate(
            &runtime.work,
            owner.visual.scalarBaseline(),
            owner.geometry,
        ),
    );

    try std.testing.expect((try owner.machine.feed("\x1b[?1049h")).state_changed);
    const styles = [_][]const u8{ "\x1b[0m", "\x1b[1m", "\x1b[3m", "\x1b[1;3m" };
    var position: [16]u8 = undefined;
    var alternate_changed = false;
    for (styles, 0..) |style, row| {
        const move = try std.fmt.bufPrint(&position, "\x1b[{d};1H", .{row + 1});
        alternate_changed = (try owner.machine.feed(move)).state_changed or
            alternate_changed;
        alternate_changed = (try owner.machine.feed(style)).state_changed or
            alternate_changed;
        var scalar: u8 = 33;
        while (scalar <= 126) : (scalar += 1) {
            const byte = [_]u8{scalar};
            alternate_changed = (try owner.machine.feed(&byte)).state_changed or
                alternate_changed;
        }
    }
    try std.testing.expect(alternate_changed);
    try owner.visual.project(&owner.machine, &owner.content);
    const alternate = try owner.content.takeLocalUpdate(
        &runtime.work,
        owner.visual.scalarBaseline(),
        owner.geometry,
    );
    try std.testing.expect(alternate.uploads.len > 128);
    try composer.apply(source, alternate);

    try std.testing.expect((try owner.machine.feed("\x1b[?1049l")).state_changed);
    try owner.visual.project(&owner.machine, &owner.content);
    const primary = try owner.content.takeLocalUpdate(
        &runtime.work,
        owner.visual.scalarBaseline(),
        owner.geometry,
    );
    try std.testing.expect(primary.removals.len > 128);
    try std.testing.expect(primary.removals.len <= admitted_resources);
    try composer.apply(source, primary);
}

test "hostile admitted command pressure remains recoverable and retryable" {
    var slot = try handoff.PendingSlot.init(std.testing.allocator, contentLimits());
    defer {
        retireTestSlot(&slot);
        slot.deinit();
    }
    var runtime = try Runtime.initTest(std.testing.allocator, facts.font_path);
    defer runtime.deinit();
    const pane: render.chrome.PaneId = @fromBackingInt(@intCast(71));
    try runtime.add(pane, "/bin/sh", "sleep 1", try testPixels(runtime.fonts, 256, 128), .{ .dedicated = &slot });
    const owner = &runtime.owners[runtime.find(pane).?].?;
    const transcript = try std.testing.allocator.alloc(u8, admitted_cells * 6);
    defer std.testing.allocator.free(transcript);
    for (0..admitted_cells) |index| {
        const sequence = if (index % 2 == 0) "\x1b[40m " else "\x1b[41m ";
        @memcpy(transcript[index * 6 ..][0..6], sequence);
    }
    try std.testing.expect((try owner.machine.feed(transcript)).state_changed);
    try std.testing.expect(!try owner.publishIfDirty(&runtime.shared_fonts, &runtime.work));
    try std.testing.expect(owner.dirty);
    try std.testing.expect(!try owner.publishIfDirty(&runtime.shared_fonts, &runtime.work));
    try slot.reserve();
    slot.cancelReserved();
}

test "close racing an occupied slot retries and retires exactly once" {
    var boundary = try initBoundary(std.testing.io, std.testing.allocator);
    defer boundary.deinit();
    var runtime = try Runtime.initTest(std.testing.allocator, facts.font_path);
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
    try boundary.register(pane, source_id, try testPixels(runtime.fonts, 8, 2));
    try runtime.applyLifecycle(
        &boundary,
        try testAdmittedLifecycle(&runtime, boundary.takeLifecycle().?),
        "/bin/sh",
    );
    const owner_index = runtime.find(pane).?;
    const pooled = runtime.owners[owner_index].?.transfer.pooled;
    const reserved = try boundary.reserveUpdate(pooled.member);
    try boundary.close(pane);
    try runtime.applyLifecycle(
        &boundary,
        try testAdmittedLifecycle(&runtime, boundary.takeLifecycle().?),
        "/bin/sh",
    );
    try std.testing.expect(runtime.pending_close == pane);
    try boundary.cancelUpdate(reserved);
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
    var runtime = try Runtime.initTest(std.testing.allocator, facts.font_path);
    defer runtime.deinit();
    const first: render.chrome.PaneId = @fromBackingInt(@intCast(11));
    const second: render.chrome.PaneId = @fromBackingInt(@intCast(12));
    const first_source = try composer.registerSource();
    const second_source = try composer.registerSource();
    try boundary.register(first, first_source, try testPixels(runtime.fonts, 8, 2));
    try boundary.register(second, second_source, try testPixels(runtime.fonts, 8, 2));
    try runtime.applyLifecycle(
        &boundary,
        try testAdmittedLifecycle(&runtime, boundary.takeLifecycle().?),
        "/bin/sh",
    );
    try runtime.applyLifecycle(
        &boundary,
        try testAdmittedLifecycle(&runtime, boundary.takeLifecycle().?),
        "/bin/sh",
    );
    try std.testing.expect(try runtime.servicePending() == 2);
    try std.testing.expectEqual(
        @as(usize, 2),
        (try boundary.drainReady(&composer)).accepted,
    );
    var wake = std.posix.pollfd{ .fd = boundary.terminalFd(), .events = std.posix.POLL.IN, .revents = 0 };
    try std.testing.expectEqual(@as(usize, 1), @as(usize, @intCast(try std.posix.poll((&wake)[0..1], 0))));
    try boundary.drainTerminalWake();
    try boundary.close(first);
    try runtime.applyLifecycle(
        &boundary,
        try testAdmittedLifecycle(&runtime, boundary.takeLifecycle().?),
        "/bin/sh",
    );
    const retired = boundary.takeRetired().?;
    try std.testing.expectEqual(first, retired.pane);
    try composer.removeSource(retired.source);
    try boundary.finishRetired(first);
    try std.testing.expectEqual(
        @as(usize, 0),
        (try boundary.drainReady(&composer)).accepted,
    );
    try std.testing.expect(runtime.find(first) == null);
    try std.testing.expect(runtime.find(second) != null);
}

test "pool exhaustion preserves PTY progress and shared Work reuse" {
    var boundary = try initBoundary(std.testing.io, std.testing.allocator);
    defer boundary.deinit();
    var composer = try render.canvas.Composer.init(std.testing.allocator, .{
        .sources = 1,
        .retained_resources = 128,
        .retained_commands = 1024,
        .retained_pixel_bytes = 4 * 1024 * 1024,
        .composition_sources = 1,
        .candidate_resources = 128,
        .candidate_commands = 1024,
        .candidate_pixel_bytes = 4 * 1024 * 1024,
    });
    defer composer.deinit();
    var runtime = try Runtime.initTest(std.testing.allocator, facts.font_path);
    defer runtime.deinit();
    const pane: render.chrome.PaneId = @fromBackingInt(@intCast(21));
    const source = try composer.registerSource();
    try boundary.register(pane, source, try testPixels(runtime.fonts, 8, 2));
    try runtime.applyLifecycle(
        &boundary,
        try testAdmittedLifecycle(&runtime, boundary.takeLifecycle().?),
        "/bin/sh",
    );

    var reservations: [16]terminal_pool.Token = undefined;
    for (&reservations, 0..) |*token, index| {
        const identity: u64 = @intCast(index + 100);
        const dummy_pane: render.chrome.PaneId =
            @fromBackingInt(identity);
        const dummy_source: render.canvas.SourceId =
            @fromBackingInt(identity);
        try boundary.register(dummy_pane, dummy_source, .{ .width = 1, .height = 1 });
        try std.testing.expect(
            std.meta.activeTag(boundary.takeLifecycle().?) == .create,
        );
        const member = try boundary.activateTransfer(dummy_pane);
        token.* = try boundary.reserveUpdate(member);
    }
    try std.testing.expectEqual(@as(usize, 0), try runtime.servicePending());

    var progressed = false;
    for (0..128) |_| {
        try std.testing.expect(try runtime.pollOnce(20) <= 1);
        const view = runtime.owners[runtime.find(pane).?].?.machine.semanticView(0);
        if (view.cellAt(0, 0) != 0) {
            progressed = true;
            break;
        }
    }
    try std.testing.expect(progressed);
    try std.testing.expectEqual(@as(usize, 0), try runtime.servicePending());

    try boundary.cancelUpdate(reservations[0]);
    try std.testing.expectEqual(@as(usize, 1), try runtime.servicePending());
    const owner = &runtime.owners[runtime.find(pane).?].?;
    try std.testing.expectEqual(
        @as(usize, 1),
        (try boundary.applyCandidate(
            &composer,
            null,
            .{
                .surface = owner.pane_pixels,
                .sources = &.{.{
                    .source = source,
                    .origin = .{ .x = 0, .y = 0 },
                    .clip = .{
                        .x = 0,
                        .y = 0,
                        .width = owner.pane_pixels.width,
                        .height = owner.pane_pixels.height,
                    },
                }},
            },
            null,
            .ordinary,
        )).accepted,
    );
    for (reservations[1..]) |token| try boundary.cancelUpdate(token);
}

test "consumed publication failure releases reservation and forces recovery" {
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
    var runtime = try Runtime.initTest(std.testing.allocator, facts.font_path);
    defer runtime.deinit();
    const pane: render.chrome.PaneId = @fromBackingInt(@intCast(22));
    const source = try composer.registerSource();
    try boundary.register(pane, source, try testPixels(runtime.fonts, 8, 2));
    try runtime.applyLifecycle(
        &boundary,
        try testAdmittedLifecycle(&runtime, boundary.takeLifecycle().?),
        "/bin/sh",
    );
    const owner = &runtime.owners[runtime.find(pane).?].?;
    const pooled = owner.transfer.pooled;
    const token = try boundary.reserveUpdate(pooled.member);
    try boundary.close(pane);
    try std.testing.expect(
        !try owner.publishReservedPooled(
            &runtime.shared_fonts,
            pooled,
            token,
            &runtime.work,
        ),
    );
    try std.testing.expect(!owner.visual.initialized);
    try runtime.applyLifecycle(
        &boundary,
        try testAdmittedLifecycle(&runtime, boundary.takeLifecycle().?),
        "/bin/sh",
    );
    const retired = boundary.takeRetired().?;
    try composer.removeSource(retired.source);
    try boundary.finishRetired(retired.pane);

    const replacement: render.chrome.PaneId =
        @fromBackingInt(@intCast(23));
    const replacement_source = try composer.registerSource();
    try boundary.register(replacement, replacement_source, .{ .width = 1, .height = 1 });
    try std.testing.expect(
        std.meta.activeTag(boundary.takeLifecycle().?) == .create,
    );
    const replacement_member = try boundary.activateTransfer(replacement);
    const replacement_token = try boundary.reserveUpdate(replacement_member);
    try boundary.publishUpdate(replacement_token, .{
        .revision = @fromBackingInt(@intCast(1)),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{},
    });
    const drainage = try boundary.drainReady(&composer);
    try std.testing.expectEqual(@as(usize, 1), drainage.accepted);
    try std.testing.expect(drainage.rejected == null);
    try boundary.close(replacement);
    try std.testing.expect(
        std.meta.activeTag(boundary.takeLifecycle().?) == .close,
    );
    try std.testing.expect(try boundary.retireTransfer(replacement));
    try boundary.markRetired(replacement);
    const replacement_retired = boundary.takeRetired().?;
    try composer.removeSource(replacement_retired.source);
    try boundary.finishRetired(replacement_retired.pane);
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
    var runtime = try Runtime.initTest(std.testing.allocator, facts.font_path);
    defer runtime.deinit();
    const noisy_id: render.chrome.PaneId = @fromBackingInt(@intCast(41));
    const quiet_id: render.chrome.PaneId = @fromBackingInt(@intCast(42));
    try runtime.add(
        noisy_id,
        "/bin/sh",
        "i=0; while [ $i -lt 2000000 ]; do printf x; i=$((i+1)); done; exit 0",
        try testPixels(runtime.fonts, 16, 16),
        .{ .dedicated = &noisy_slot },
    );
    try runtime.add(
        quiet_id,
        "/bin/sh",
        "while IFS= read -r line; do printf q; done",
        try testPixels(runtime.fonts, 16, 16),
        .{ .dedicated = &quiet_slot },
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
    var runtime = try Runtime.initTest(std.testing.allocator, facts.font_path);
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
        runtime.add(@fromBackingInt(@intCast(0)), "/bin/sh", "exit 0", try testPixels(runtime.fonts, 16, 16), .{ .dedicated = &first_slot }),
    );
    try runtime.add(first, "/bin/sh", "printf first; exit 0", try testPixels(runtime.fonts, 16, 16), .{ .dedicated = &first_slot });
    try std.testing.expectError(
        error.DuplicatePane,
        runtime.add(first, "/bin/sh", "exit 0", try testPixels(runtime.fonts, 16, 16), .{ .dedicated = &first_slot }),
    );
    try runtime.add(second, "/bin/sh", "printf second; exit 0", try testPixels(runtime.fonts, 16, 16), .{ .dedicated = &second_slot });
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

test "visible-set preparation publishes hidden newest state through real Content" {
    var boundary = try handoff.Boundary.init(
        std.testing.io,
        std.testing.allocator,
        contentLimits(),
    );
    defer boundary.deinit();
    var runtime = try Runtime.initTest(std.testing.allocator, facts.font_path);
    defer runtime.deinit();
    var composer = try render.canvas.Composer.init(std.testing.allocator, .{
        .sources = 1,
        .retained_resources = 128,
        .retained_commands = 4096,
        .retained_pixel_bytes = 4 * 1024 * 1024,
        .composition_sources = 1,
        .candidate_resources = 128,
        .candidate_commands = 4096,
        .candidate_pixel_bytes = 4 * 1024 * 1024,
    });
    defer composer.deinit();
    const pane: render.chrome.PaneId = @fromBackingInt(81);
    const source = try composer.registerSource();
    try boundary.register(pane, source, try testPixels(runtime.fonts, 8, 2));
    const created = boundary.takeLifecycle().?;
    try std.testing.expect(std.meta.activeTag(created) == .create);
    const pooled = try boundary.activateTransfer(pane);
    try runtime.add(
        pane,
        "/bin/sh",
        "sleep 1",
        try testPixels(runtime.fonts, 8, 2),
        .{ .pooled = .{ .boundary = &boundary, .member = pooled } },
    );
    const visible = handoff.VisibleMember{ .pane = pane, .source = source };
    try boundary.publishVisibleSet(1, &.{visible});
    try std.testing.expect(try runtime.prepareVisibleSet(&boundary));
    try std.testing.expectEqual(@as(usize, 1), (try boundary.drainReady(&composer)).accepted);
    try std.testing.expectEqual(handoff.VisibleSetStatus.ready, boundary.visibleSetStatus(1));
    try boundary.claimVisibleSet(1);
    try boundary.commitVisibleSet(1);
    const first_revision =
        runtime.owners[runtime.find(pane).?].?.last_published_revision;

    try boundary.publishVisibleSet(2, &.{});
    try std.testing.expect(try runtime.prepareVisibleSet(&boundary));
    try boundary.claimVisibleSet(2);
    try boundary.commitVisibleSet(2);
    const owner = &runtime.owners[runtime.find(pane).?].?;
    try std.testing.expect((try owner.machine.feed("newest")).state_changed);
    owner.dirty = true;
    try std.testing.expect(!(try owner.publishIfDirty(
        &runtime.shared_fonts,
        &runtime.work,
    )));
    try std.testing.expect(owner.dirty);

    try boundary.publishVisibleSet(3, &.{visible});
    try std.testing.expect(try runtime.prepareVisibleSet(&boundary));
    try std.testing.expectEqual(@as(usize, 1), (try boundary.drainReady(&composer)).accepted);
    try std.testing.expectEqual(handoff.VisibleSetStatus.ready, boundary.visibleSetStatus(3));
    try boundary.claimVisibleSet(3);
    try boundary.commitVisibleSet(3);
    try std.testing.expect(
        @backingInt(owner.last_published_revision) > @backingInt(first_revision),
    );
}

test "two pooled panes with one factual key share canonical glyph residency" {
    var boundary = try handoff.Boundary.init(
        std.testing.io,
        std.testing.allocator,
        contentLimits(),
    );
    defer boundary.deinit();
    var runtime = try Runtime.initTest(
        std.testing.allocator,
        facts.symbol_font_path,
    );
    defer runtime.deinit();
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
    const first_pane: render.chrome.PaneId = @fromBackingInt(181);
    const second_pane: render.chrome.PaneId = @fromBackingInt(182);
    const first_source = try composer.registerSource();
    const second_source = try composer.registerSource();
    const pixels = try testPixels(runtime.fonts, 8, 2);
    try boundary.register(first_pane, first_source, pixels);
    const first_create = boundary.takeLifecycle().?;
    try std.testing.expect(std.meta.activeTag(first_create) == .create);
    const first_member = try boundary.activateTransfer(first_pane);
    try runtime.add(
        first_pane,
        "/bin/sh",
        "sleep 1",
        pixels,
        .{ .pooled = .{ .boundary = &boundary, .member = first_member } },
    );
    try boundary.register(second_pane, second_source, pixels);
    const second_create = boundary.takeLifecycle().?;
    try std.testing.expect(std.meta.activeTag(second_create) == .create);
    const second_member = try boundary.activateTransfer(second_pane);
    try runtime.add(
        second_pane,
        "/bin/sh",
        "sleep 1",
        pixels,
        .{ .pooled = .{ .boundary = &boundary, .member = second_member } },
    );
    const request = handoff.FontRequest{
        .revision = 1,
        .scale = .{
            .revision = 1,
            .dpi_x = .{ .numerator = 96, .denominator = 1 },
            .dpi_y = .{ .numerator = 96, .denominator = 1 },
        },
        .policy = try handoff.FontPolicy.init(16.0),
    };
    try runtime.preflightFontRequest(request);
    try std.testing.expect(try runtime.resizePointFonts(&boundary, request));
    const first = &runtime.owners[runtime.find(first_pane).?].?;
    const second = &runtime.owners[runtime.find(second_pane).?].?;
    first.dirty = false;
    first.setLigatureMode(.never);
    try std.testing.expect(!first.dirty);
    first.setLigatureMode(.always);
    try std.testing.expect(first.dirty);
    first.setLigatureMode(.never);
    second.setLigatureMode(.cursor);
    try std.testing.expectEqual(
        render.terminal.LigatureMode.never,
        first.ligature_mode,
    );
    try std.testing.expectEqual(
        render.terminal.LigatureMode.cursor,
        second.ligature_mode,
    );
    try std.testing.expect(std.meta.eql(first.font_group.?, second.font_group.?));
    try std.testing.expect((try first.machine.feed("\u{f460}")).state_changed);
    try std.testing.expect((try second.machine.feed("\u{f460}")).state_changed);
    first.dirty = true;
    second.dirty = true;
    const members = [_]handoff.VisibleMember{
        .{ .pane = first_pane, .source = first_source },
        .{ .pane = second_pane, .source = second_source },
    };
    try boundary.publishVisibleSet(1, &members);
    try std.testing.expect(try runtime.prepareVisibleSet(&boundary));
    try boundary.claimVisibleSet(1);
    const composition = render.canvas.Composer.Composition{
        .surface = .{ .width = pixels.width * 2, .height = pixels.height },
        .sources = &.{
            .{ .source = first_source, .origin = .{ .x = 0, .y = 0 }, .clip = .{ .x = 0, .y = 0, .width = pixels.width, .height = pixels.height } },
            .{ .source = second_source, .origin = .{ .x = pixels.width, .y = 0 }, .clip = .{ .x = 0, .y = 0, .width = pixels.width * 2, .height = pixels.height } },
        },
    };
    try std.testing.expectEqual(
        @as(usize, 2),
        (try boundary.applyCandidate(&composer, null, composition, 1, .ordinary)).accepted,
    );
    var uploads: [128]render.canvas.ResourceUploadFact = undefined;
    var removals: [128]render.canvas.FrameResourceRef = undefined;
    var commands: [8192]render.canvas.Command = undefined;
    var frame_pixels: [4 * 1024 * 1024]u8 = undefined;
    const frame = try composer.frame(&.{}, .{
        .uploads = &uploads,
        .removals = &removals,
        .commands = &commands,
        .pixels = &frame_pixels,
    });
    var shared_uploads: usize = 0;
    var first_shared_identity: u64 = 0;
    var first_shared_size: render.canvas.Size = undefined;
    var first_shared_stride: usize = 0;
    var first_shared_hash: u64 = 0;
    for (frame.uploads) |upload| {
        if (!upload.resource.resource.isShared()) continue;
        shared_uploads += 1;
        first_shared_identity = try upload.resource.resource.identity();
        first_shared_size = upload.size;
        first_shared_stride = upload.stride;
        first_shared_hash = std.hash.Wyhash.hash(
            0,
            frame.pixels[upload.pixel_offset .. upload.pixel_offset +
                upload.pixel_count],
        );
    }
    try std.testing.expectEqual(@as(usize, 1), shared_uploads);
    var first_shared = false;
    var second_shared = false;
    for (frame.commands) |command| switch (command) {
        .solid => {},
        .alpha_mask => |value| {
            if (!value.resource.resource.resource.isShared()) continue;
            if (value.destination.x < pixels.width)
                first_shared = true
            else
                second_shared = true;
        },
        .rgba => {},
    };
    try std.testing.expect(first_shared and second_shared);
    try runtime.reconcileAcceptedVisibility(&boundary);
    const second_revision_before_hide = second.last_published_revision;

    try boundary.publishVisibleSet(2, &.{members[0]});
    try std.testing.expect(try runtime.prepareVisibleSet(&boundary));
    try boundary.claimVisibleSet(2);
    const first_only = render.canvas.Composer.Composition{
        .surface = composition.surface,
        .sources = composition.sources[0..1],
    };
    try std.testing.expectEqual(
        @as(usize, 0),
        (try boundary.applyCandidate(
            &composer,
            null,
            first_only,
            2,
            .ordinary,
        )).accepted,
    );
    try runtime.reconcileAcceptedVisibility(&boundary);
    try std.testing.expect(second.font_group == null);
    try std.testing.expect(second.font_released_hidden);
    try std.testing.expectEqual(
        render.terminal.LigatureMode.cursor,
        second.ligature_mode,
    );
    try std.testing.expect(!first.font_released_hidden);
    try std.testing.expect(first.font_group != null);
    try std.testing.expect((try second.machine.feed("hidden")).state_changed);
    second.dirty = true;
    try std.testing.expect(!(try second.publishIfDirty(
        &runtime.shared_fonts,
        &runtime.work,
    )));

    try boundary.publishVisibleSet(3, &members);
    try std.testing.expect(try runtime.prepareVisibleSet(&boundary));
    try std.testing.expect(second.font_group != null);
    try std.testing.expect(second.font_reveal_candidate);
    try std.testing.expect(
        @backingInt(second.last_published_revision) >
            @backingInt(second_revision_before_hide),
    );
    try boundary.claimVisibleSet(3);
    try std.testing.expectEqual(
        @as(usize, 1),
        (try boundary.applyCandidate(
            &composer,
            null,
            composition,
            3,
            .ordinary,
        )).accepted,
    );
    try runtime.reconcileAcceptedVisibility(&boundary);
    try std.testing.expect(!second.font_released_hidden);
    try std.testing.expect(!second.font_reveal_candidate);
    try std.testing.expectEqual(
        render.terminal.LigatureMode.cursor,
        second.ligature_mode,
    );
    try std.testing.expect(std.meta.eql(
        first.font_group.?,
        second.font_group.?,
    ));

    try std.testing.expect((try first.machine.feed("\x1b[2J\x1b[H")).state_changed);
    try std.testing.expect((try second.machine.feed("\x1b[2J\x1b[H")).state_changed);
    first.dirty = true;
    second.dirty = true;
    try std.testing.expect(try first.publishIfDirty(&runtime.shared_fonts, &runtime.work));
    try std.testing.expect(try second.publishIfDirty(&runtime.shared_fonts, &runtime.work));
    try std.testing.expectEqual(
        @as(usize, 2),
        (try boundary.applyCandidate(&composer, null, composition, null, .ordinary)).accepted,
    );

    try std.testing.expect((try first.machine.feed("\u{f460}")).state_changed);
    try std.testing.expect((try second.machine.feed("\u{f460}")).state_changed);
    first.dirty = true;
    second.dirty = true;
    try std.testing.expect(try first.publishIfDirty(&runtime.shared_fonts, &runtime.work));
    try std.testing.expect(try second.publishIfDirty(&runtime.shared_fonts, &runtime.work));
    try std.testing.expectEqual(
        @as(usize, 2),
        (try boundary.applyCandidate(&composer, null, composition, null, .ordinary)).accepted,
    );
    const rebuilt = try composer.frame(&.{}, .{
        .uploads = &uploads,
        .removals = &removals,
        .commands = &commands,
        .pixels = &frame_pixels,
    });
    var rebuilt_shared_uploads: usize = 0;
    for (rebuilt.uploads) |upload| {
        if (!upload.resource.resource.isShared()) continue;
        rebuilt_shared_uploads += 1;
        try std.testing.expect(
            try upload.resource.resource.identity() > first_shared_identity,
        );
        try std.testing.expectEqual(first_shared_size, upload.size);
        try std.testing.expectEqual(first_shared_stride, upload.stride);
        try std.testing.expectEqual(
            first_shared_hash,
            std.hash.Wyhash.hash(
                0,
                rebuilt.pixels[upload.pixel_offset .. upload.pixel_offset +
                    upload.pixel_count],
            ),
        );
    }
    try std.testing.expectEqual(@as(usize, 1), rebuilt_shared_uploads);

    for ([_]*Logical{ first, second }) |owner| {
        try std.testing.expect(
            (try owner.machine.feed("\x1b[?1049h\x1b[3C\u{f460}")).state_changed,
        );
        owner.dirty = true;
        try std.testing.expect(try owner.publishIfDirty(
            &runtime.shared_fonts,
            &runtime.work,
        ));
    }
    try std.testing.expectEqual(
        @as(usize, 2),
        (try boundary.applyCandidate(&composer, null, composition, null, .ordinary)).accepted,
    );
    for ([_]*Logical{ first, second }) |owner| {
        try std.testing.expect(
            (try owner.machine.feed("\x1b[?1049l")).state_changed,
        );
        owner.dirty = true;
        try std.testing.expect(try owner.publishIfDirty(
            &runtime.shared_fonts,
            &runtime.work,
        ));
    }
    try std.testing.expectEqual(
        @as(usize, 2),
        (try boundary.applyCandidate(&composer, null, composition, null, .ordinary)).accepted,
    );
    const after_alternate = try composer.frame(&.{}, .{
        .uploads = &uploads,
        .removals = &removals,
        .commands = &commands,
        .pixels = &frame_pixels,
    });
    var alternate_icon_found = false;
    for (after_alternate.uploads) |upload| {
        if (!upload.resource.resource.isShared() or
            !std.meta.eql(upload.size, first_shared_size) or
            upload.stride != first_shared_stride)
            continue;
        if (std.hash.Wyhash.hash(
            0,
            after_alternate.pixels[upload.pixel_offset .. upload.pixel_offset + upload.pixel_count],
        ) != first_shared_hash) continue;
        alternate_icon_found = true;
    }
    try std.testing.expect(alternate_icon_found);

    for ([_]*Logical{ first, second }) |owner| {
        try std.testing.expect(
            (try owner.machine.feed("\r\n\r\n\r\n")).state_changed,
        );
        owner.dirty = true;
        try std.testing.expect(try owner.publishIfDirty(
            &runtime.shared_fonts,
            &runtime.work,
        ));
    }
    try std.testing.expectEqual(
        @as(usize, 2),
        (try boundary.applyCandidate(&composer, null, composition, null, .ordinary)).accepted,
    );
    for ([_]*Logical{ first, second }) |owner| {
        try std.testing.expect(
            (try owner.machine.feed("\x1b[2J\x1b[H\u{f460}")).state_changed,
        );
        owner.dirty = true;
        try std.testing.expect(try owner.publishIfDirty(
            &runtime.shared_fonts,
            &runtime.work,
        ));
    }
    try std.testing.expectEqual(
        @as(usize, 2),
        (try boundary.applyCandidate(&composer, null, composition, null, .ordinary)).accepted,
    );
    const after_scroll = try composer.frame(&.{}, .{
        .uploads = &uploads,
        .removals = &removals,
        .commands = &commands,
        .pixels = &frame_pixels,
    });
    var scrolled_icon_found = false;
    for (after_scroll.uploads) |upload| {
        if (!upload.resource.resource.isShared() or
            !std.meta.eql(upload.size, first_shared_size) or
            upload.stride != first_shared_stride)
            continue;
        if (std.hash.Wyhash.hash(
            0,
            after_scroll.pixels[upload.pixel_offset .. upload.pixel_offset + upload.pixel_count],
        ) != first_shared_hash) continue;
        scrolled_icon_found = true;
    }
    try std.testing.expect(scrolled_icon_found);

    const second_group_before = second.font_group.?;
    const second_fonts_before = second.fonts;
    const second_state_before = second.font_state;
    const second_geometry_before = second.geometry;
    const second_revision_before = second.last_published_revision;
    const second_geometry_revision_before = second.last_published_geometry;
    second.dirty = false;
    var focused_request = request;
    focused_request.revision = 2;
    focused_request.policy.count = 1;
    focused_request.policy.offsets[0] = .{
        .pane = first_pane,
        .offset_points = 1.0,
    };
    try std.testing.expect(try runtime.resizePointFonts(
        &boundary,
        focused_request,
    ));
    try std.testing.expect(!std.meta.eql(
        first.font_group.?,
        second.font_group.?,
    ));
    try std.testing.expectEqual(second_group_before, second.font_group.?);
    try std.testing.expect(second.fonts == second_fonts_before);
    try std.testing.expectEqual(second_state_before, second.font_state);
    try std.testing.expectEqual(second_geometry_before, second.geometry);
    try std.testing.expectEqual(
        second_revision_before,
        second.last_published_revision,
    );
    try std.testing.expectEqual(
        second_geometry_revision_before,
        second.last_published_geometry,
    );
    try std.testing.expect(!second.dirty);
    try std.testing.expect(!(try second.publishIfDirty(
        &runtime.shared_fonts,
        &runtime.work,
    )));
}

test "factual admission publishes generated joins through shared pool ownership" {
    var boundary = try handoff.Boundary.init(
        std.testing.io,
        std.testing.allocator,
        contentLimits(),
    );
    defer boundary.deinit();
    var runtime = try Runtime.init(std.testing.allocator, facts.font_path);
    defer runtime.deinit();

    // The executable bootstrap remains pixel-sized and carries no accepted
    // factual DPI or generated-raster authority.
    try std.testing.expect(runtime.accepted_scale == null);
    try std.testing.expect(runtime.fonts.generatedBoxConfig() == null);
    try std.testing.expectError(
        error.FontCapacity,
        resolvedGroupKey(runtime.logicalFontState(@fromBackingInt(201))),
    );

    var composer = try render.canvas.Composer.init(std.testing.allocator, .{
        .sources = 1,
        .retained_resources = 64,
        .retained_commands = 256,
        .retained_pixel_bytes = 64 * 1024,
        .composition_sources = 1,
        .candidate_resources = 64,
        .candidate_commands = 256,
        .candidate_pixel_bytes = 64 * 1024,
    });
    defer composer.deinit();
    const pane: render.chrome.PaneId = @fromBackingInt(201);
    const source = try composer.registerSource();
    const pane_pixels = render.canvas.Size{ .width = 80, .height = 128 };
    try boundary.register(pane, source, pane_pixels);
    const lifecycle = boundary.takeLifecycle().?;
    try runtime.applyLifecycle(
        &boundary,
        try testAdmittedLifecycle(&runtime, lifecycle),
        "/bin/sh",
    );
    const owner = &runtime.owners[runtime.find(pane).?].?;
    try std.testing.expect(owner.font_group != null);
    try std.testing.expect(owner.fonts.generatedBoxConfig() != null);
    try std.testing.expect(runtime.accepted_scale != null);
    try std.testing.expect(
        (try owner.machine.feed("\x1b[H\u{2502}\x1b[2;1H\u{2502}")).state_changed,
    );
    owner.dirty = true;
    try std.testing.expect(try owner.publishIfDirty(
        &runtime.shared_fonts,
        &runtime.work,
    ));

    const token = for (boundary.entries) |entry| {
        const retained = entry orelse continue;
        if (retained.pane != pane) continue;
        break retained.ready.?;
    } else return error.TestExpectedEqual;
    try boundary.pool.beginDrain(token);
    var pool_claimed = true;
    defer if (pool_claimed)
        boundary.pool.retryDrain(token) catch
            @panic("test pool claim rollback failed");
    const pooled = try boundary.pool.drainingUpdate(token);
    try std.testing.expectEqual(@as(usize, 1), pooled.uploads.len);
    const declaration = pooled.uploads[0];
    try std.testing.expect(declaration.resource.resource.isShared());
    try std.testing.expectEqual(render.canvas.ResourceFormat.alpha8, declaration.format);
    try std.testing.expectEqual(owner.geometry.metrics.width_px, declaration.pixels.width);
    try std.testing.expectEqual(owner.geometry.metrics.height_px, declaration.pixels.height);

    var joins: [2]render.canvas.Input = undefined;
    var join_count: usize = 0;
    for (pooled.commands) |command| switch (command) {
        .alpha_mask => |mask| {
            if (!std.meta.eql(mask.resource.resource, declaration.resource)) continue;
            try std.testing.expect(join_count < joins.len);
            joins[join_count] = command;
            join_count += 1;
        },
        else => {},
    };
    try std.testing.expectEqual(joins.len, join_count);
    const upper = joins[0].alpha_mask;
    const lower = joins[1].alpha_mask;
    try std.testing.expectEqual(
        upper.destination.y + @as(i32, @intCast(upper.destination.height)),
        lower.destination.y,
    );
    try std.testing.expectEqual(upper.destination.x, lower.destination.x);
    const row_bytes: usize = declaration.pixels.width;
    try std.testing.expect(std.mem.indexOfNone(
        u8,
        declaration.pixels.bytes[0..row_bytes],
        &.{0},
    ) != null);
    const final_row =
        (@as(usize, declaration.pixels.height) - 1) * declaration.pixels.stride;
    try std.testing.expect(std.mem.indexOfNone(
        u8,
        declaration.pixels.bytes[final_row..][0..row_bytes],
        &.{0},
    ) != null);
    try boundary.pool.retryDrain(token);
    pool_claimed = false;

    const visible = handoff.VisibleMember{ .pane = pane, .source = source };
    try boundary.publishVisibleSet(1, &.{visible});
    try std.testing.expect(try runtime.prepareVisibleSet(&boundary));
    try boundary.claimVisibleSet(1);
    const composition = render.canvas.Composer.Composition{
        .surface = pane_pixels,
        .sources = &.{.{
            .source = source,
            .origin = .{ .x = 0, .y = 0 },
            .clip = .{
                .x = 0,
                .y = 0,
                .width = pane_pixels.width,
                .height = pane_pixels.height,
            },
        }},
    };
    try std.testing.expectEqual(
        @as(usize, 1),
        (try boundary.applyCandidate(
            &composer,
            null,
            composition,
            1,
            .ordinary,
        )).accepted,
    );
    try runtime.reconcileAcceptedBatches(&boundary);
    var uploads: [64]render.canvas.ResourceUploadFact = undefined;
    var removals: [64]render.canvas.FrameResourceRef = undefined;
    var commands: [256]render.canvas.Command = undefined;
    var pixels: [64 * 1024]u8 = undefined;
    const frame = try composer.frame(&.{}, .{
        .uploads = &uploads,
        .removals = &removals,
        .commands = &commands,
        .pixels = &pixels,
    });
    try std.testing.expectEqual(@as(usize, 1), frame.uploads.len);
    try std.testing.expect(frame.uploads[0].resource.resource.isShared());
    var frame_join_count: usize = 0;
    for (frame.commands) |command| switch (command) {
        .alpha_mask => |mask| {
            if (!mask.resource.resource.resource.isShared()) continue;
            frame_join_count += 1;
        },
        else => {},
    };
    try std.testing.expectEqual(@as(usize, 2), frame_join_count);
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

    var runtime = try Runtime.initTest(std.testing.allocator, facts.font_path);
    var slot = try handoff.PendingSlot.init(std.testing.allocator, contentLimits());
    defer {
        runtime.deinit();
        retireTestSlot(&slot);
        slot.deinit();
    }
    const pane: render.chrome.PaneId = @fromBackingInt(@intCast(1));
    try runtime.add(pane, "/bin/sh", "sleep 1", try testPixels(runtime.fonts, 4, 2), .{ .dedicated = &slot });
    const owner = &runtime.owners[runtime.find(pane).?].?;
    const before = owner.machine.semanticSequence();
    try owner.resize(try testPixels(owner.fonts, 7, 3));
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
    const operations = [_]handoff.Lifecycle{.{ .create = .{
        .pane = pane,
        .pixels = .{ .width = 64, .height = 40 },
    } }};
    var lifecycle = try boundary.prepareLifecycle(
        &operations,
        &.{},
        .{ .pane = pane, .source = source },
    );
    defer lifecycle.deinit();
    try std.testing.expectEqual(
        lifecycle.revision,
        try lifecycle.publishAdmission(),
    );
    const thread = try std.Thread.spawn(.{}, run, .{
        &boundary,
        std.testing.allocator,
        facts.font_path,
        "/bin/sh",
    });
    var awaiting = std.posix.pollfd{
        .fd = boundary.rendererFd(),
        .events = std.posix.POLL.IN,
        .revents = 0,
    };
    try std.testing.expectEqual(
        @as(usize, 0),
        @as(usize, @intCast(try std.posix.poll((&awaiting)[0..1], 20))),
    );
    try std.testing.expect(lifecycle.admissionResult() == null);
    try boundary.requestFont(.{
        .revision = 1,
        .scale = .{
            .revision = 1,
            .dpi_x = .{ .numerator = 96, .denominator = 1 },
            .dpi_y = .{ .numerator = 96, .denominator = 1 },
        },
        .policy = try handoff.FontPolicy.init(16.0),
    });
    var drained: usize = 0;
    var lifecycle_committed = false;
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
            if (!lifecycle_committed and lifecycle.admissionResult() != null) {
                try lifecycle.commitAdmitted();
                lifecycle_committed = true;
            }
            drained += (try boundary.drainReady(&composer)).accepted;
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
        .pixels = .{ .width = 1, .height = 1 },
    } };
    var candidate = try boundary.prepareLifecycle(
        &operations,
        &.{},
        .{ .pane = pane, .source = source },
    );
    defer candidate.deinit();
    const candidate_revision = try candidate.publishAdmission();
    const copied_candidate = boundary.takeLifecycleAdmission().?;
    try std.testing.expectEqual(candidate_revision, copied_candidate.revision);
    const thread = try std.Thread.spawn(.{}, run, .{
        &boundary,
        std.testing.allocator,
        facts.font_path,
        "/bin/sh",
    });
    boundary.shutdown();
    try std.testing.expectError(error.Stopping, candidate.commitAdmitted());
    try std.testing.expectError(
        error.Stopping,
        boundary.completeLifecycleAdmission(
            copied_candidate.revision,
            .{ .rejected = .stopping },
        ),
    );
    candidate.deinit();
    thread.join();
    const status = boundary.status();
    try std.testing.expect(status.stopped);
    try std.testing.expect(!status.failed);
    try std.testing.expect(boundary.sourceFor(pane) == null);
    try std.testing.expect(boundary.takeLifecycle() == null);
}

test "interpreted unmatched keys route by PaneId under current VT modes" {
    var slot = try handoff.PendingSlot.init(std.testing.allocator, contentLimits());
    defer {
        retireTestSlot(&slot);
        slot.deinit();
    }
    var runtime = try Runtime.initTest(std.testing.allocator, facts.font_path);
    defer runtime.deinit();
    const pane: render.chrome.PaneId = @fromBackingInt(@intCast(1));
    try runtime.add(pane, "/bin/sh", "sleep 1", try testPixels(runtime.fonts, 8, 2), .{ .dedicated = &slot });
    var key = std.mem.zeroes(wayland.input.Key);
    key.state = .pressed;
    key.keysym = @fromBackingInt(@intCast('a'));
    key.text[0] = 'a';
    key.text_len = 1;
    try runtime.applyKey(.{ .pane = pane, .key = key });
    try std.testing.expectEqualStrings("a", runtime.owners[runtime.find(pane).?].?.writes.pending());
    for ([_]u32{ 0xffe1, 0xffe3, 0xffe9, 0xffeb }) |keysym| {
        key.keysym = @fromBackingInt(keysym);
        key.text_len = 0;
        key.state = .pressed;
        try runtime.applyKey(.{ .pane = pane, .key = key });
        key.state = .released;
        try runtime.applyKey(.{ .pane = pane, .key = key });
    }
    try std.testing.expectEqualStrings(
        "a",
        runtime.owners[runtime.find(pane).?].?.writes.pending(),
    );
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
    var fonts = try render.terminal.FontMap.init(
        std.testing.allocator,
        &.{.{
            .key = .{ .slot = 0, .style = .normal },
            .native = .{ .primary = facts.font_path, .size = .{ .points = .{
                .points = 12.0,
                .dpi_x = .{ .numerator = 96, .denominator = 1 },
                .dpi_y = .{ .numerator = 96, .denominator = 1 },
            } } },
        }},
    );
    defer fonts.deinit();
    const pane: render.chrome.PaneId = @fromBackingInt(@intCast(1));
    var owner = try Logical.init(
        std.testing.allocator,
        pane,
        "/bin/sh",
        "printf final",
        try testPixels(&fonts, 8, 2),
        &fonts,
        null,
        .{
            .request_revision = 0,
            .base_point_size = 16.0,
            .offset_points = 0.0,
            .scale = null,
        },
        .{ .dedicated = &slot },
    );
    defer owner.deinit();
    var work = try render.terminal.Content.Work.init(
        std.testing.allocator,
        contentLimits(),
    );
    defer work.deinit();
    var shared_fonts = try font_owner.Owner.init(std.testing.allocator);
    defer shared_fonts.deinit();
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
        const turn = try owner.service(&shared_fonts, &work, true, false);
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
    var runtime = try Runtime.initTest(std.testing.allocator, facts.font_path);
    defer runtime.deinit();
    const first: render.chrome.PaneId = @fromBackingInt(@intCast(1));
    const first_source = try composer.registerSource();
    try boundary.register(first, first_source, try testPixels(runtime.fonts, 8, 2));
    try runtime.applyLifecycle(
        &boundary,
        try testAdmittedLifecycle(&runtime, boundary.takeLifecycle().?),
        "/bin/sh",
    );
    try boundary.resize(first, try testPixels(runtime.fonts, 10, 3));
    try runtime.applyLifecycle(
        &boundary,
        try testAdmittedLifecycle(&runtime, boundary.takeLifecycle().?),
        "/bin/sh",
    );
    const resized_owner = &runtime.owners[runtime.find(first).?].?;
    const resized_grid = try gridForPixels(
        resized_owner.pane_pixels,
        resized_owner.fonts.cellMetrics(.{
            .slot = 0,
            .style = .normal,
        }).?,
    );
    try std.testing.expectEqual(
        resized_grid.cols,
        resized_owner.machine.semanticView(0).cols,
    );
    try boundary.close(first);
    try runtime.applyLifecycle(
        &boundary,
        try testAdmittedLifecycle(&runtime, boundary.takeLifecycle().?),
        "/bin/sh",
    );
    const retired = boundary.takeRetired().?;
    try std.testing.expectEqual(first, retired.pane);
    try composer.removeSource(retired.source);
    try boundary.finishRetired(first);

    const second: render.chrome.PaneId = @fromBackingInt(@intCast(2));
    const second_source = try composer.registerSource();
    try std.testing.expect(@backingInt(second_source) > @backingInt(first_source));
    try boundary.register(second, second_source, try testPixels(runtime.fonts, 8, 2));
    try runtime.applyLifecycle(
        &boundary,
        try testAdmittedLifecycle(&runtime, boundary.takeLifecycle().?),
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

const Grid = struct { cols: u16, rows: u16 };

fn gridForPixels(
    pixels: render.canvas.Size,
    metrics: render.terminal.CellMetrics,
) error{ InvalidPane, FontCapacity, TerminalCapacity }!Grid {
    if (pixels.width == 0 or pixels.height == 0) return error.InvalidPane;
    if (metrics.width_px == 0 or metrics.height_px == 0) return error.FontCapacity;
    const cols: u16 = @max(@as(u16, 1), pixels.width / metrics.width_px);
    const rows: u16 = @max(@as(u16, 1), pixels.height / metrics.height_px);
    const cells = std.math.mul(usize, cols, rows) catch
        return error.TerminalCapacity;
    if (rows > projection_row_limit or cells > admitted_cells)
        return error.TerminalCapacity;
    return .{ .cols = cols, .rows = rows };
}

fn paneGeometry(
    pixels: render.canvas.Size,
    fonts: *render.terminal.FontMap,
) error{ InvalidPane, FontCapacity }!terminal_render.Content.Geometry {
    if (pixels.width == 0 or pixels.height == 0) return error.InvalidPane;
    const metrics = fonts.cellMetrics(.{ .slot = 0, .style = .normal }) orelse
        return error.FontCapacity;
    const decoration = fonts.decorationMetrics(.{ .slot = 0, .style = .normal }) orelse
        return error.FontCapacity;
    const generated_box = fonts.generatedBoxConfig() orelse
        return error.FontCapacity;
    return .{
        .x = 0,
        .y = 0,
        .clip = .{
            .x = 0,
            .y = 0,
            .width = pixels.width,
            .height = pixels.height,
        },
        .metrics = metrics,
        .generated_box = generated_box,
        .underline_y = decoration.underline_y,
        .underline_height = decoration.underline_height,
        .strike_y = decoration.strike_y,
        .strike_height = decoration.strike_height,
    };
}

fn testPixels(
    fonts: *render.terminal.FontMap,
    cols: u16,
    rows: u16,
) !render.canvas.Size {
    const metrics = fonts.cellMetrics(.{ .slot = 0, .style = .normal }) orelse
        return error.FontCapacity;
    return .{
        .width = std.math.mul(u16, cols, metrics.width_px) catch
            return error.FontCapacity,
        .height = std.math.mul(u16, rows, metrics.height_px) catch
            return error.FontCapacity,
    };
}

fn testAdmittedLifecycle(
    runtime: *Runtime,
    operation: handoff.Lifecycle,
) !handoff.AdmittedLifecycle {
    const grid: ?handoff.DerivedGrid = switch (operation) {
        .create => |value| blk: {
            if (runtime.accepted_scale == null)
                runtime.accepted_scale = .{
                    .revision = 1,
                    .dpi_x = .{ .numerator = 96, .denominator = 1 },
                    .dpi_y = .{ .numerator = 96, .denominator = 1 },
                };
            const resolved = try runtime.pointGroup(
                runtime.logicalFontState(value.pane),
            );
            runtime.pending_lifecycle_font = .{
                .revision = @fromBackingInt(1),
                .pane = value.pane,
                .group = resolved.reference,
                .map = resolved.map,
            };
            const metrics = resolved.map.cellMetrics(.{
                .slot = 0,
                .style = .normal,
            }) orelse return error.FontCapacity;
            const derived = try gridForPixels(value.pixels, metrics);
            break :blk .{
                .pane = value.pane,
                .rows = derived.rows,
                .columns = derived.cols,
            };
        },
        .resize => |value| blk: {
            const owner_index = runtime.find(value.pane) orelse
                return error.UnknownPane;
            const metrics = runtime.owners[owner_index].?.fonts.cellMetrics(.{
                .slot = 0,
                .style = .normal,
            }) orelse return error.FontCapacity;
            const derived = try gridForPixels(value.pixels, metrics);
            break :blk .{
                .pane = value.pane,
                .rows = derived.rows,
                .columns = derived.cols,
            };
        },
        .close => null,
    };
    return .{
        .revision = @fromBackingInt(1),
        .operation = operation,
        .grid = grid,
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

test "modifier keysyms retain named physical identity instead of fabricated Unicode" {
    const KeyName = @FieldType(vt.Terminal.Key, "named");
    const cases = [_]struct { keysym: u32, expected: KeyName }{
        .{ .keysym = 0xffe1, .expected = .left_shift },
        .{ .keysym = 0xffe2, .expected = .right_shift },
        .{ .keysym = 0xffe3, .expected = .left_control },
        .{ .keysym = 0xffe4, .expected = .right_control },
        .{ .keysym = 0xffe9, .expected = .left_alt },
        .{ .keysym = 0xffea, .expected = .right_alt },
        .{ .keysym = 0xffeb, .expected = .left_super },
        .{ .keysym = 0xffec, .expected = .right_super },
    };
    for (cases) |case| {
        const key = try terminalKey(@fromBackingInt(case.keysym));
        try std.testing.expectEqual(
            vt.Terminal.Key{ .named = case.expected },
            key,
        );
    }
}

test "configured operator font styles and optional missing cells remain renderable" {
    var slot = try handoff.PendingSlot.init(std.testing.allocator, contentLimits());
    defer {
        retireTestSlot(&slot);
        slot.deinit();
    }
    var runtime = try Runtime.initTest(std.testing.allocator, facts.font_path);
    defer runtime.deinit();
    const pane: render.chrome.PaneId = @fromBackingInt(83);
    try runtime.add(
        pane,
        "/bin/sh",
        "sleep 1",
        try testPixels(runtime.fonts, 8, 2),
        .{ .dedicated = &slot },
    );
    const owner = &runtime.owners[runtime.find(pane).?].?;
    try std.testing.expect(
        (try owner.machine.feed("\x1b[1mA\x1b[3mB\x1b[0m\xef\xbf\xa1")).state_changed,
    );
    owner.dirty = true;
    try std.testing.expect(try owner.publishIfDirty(
        &runtime.shared_fonts,
        &runtime.work,
    ));
}

test "factual DPI-only request reaches Runtime without font reconstruction" {
    var runtime = try Runtime.initTest(std.testing.allocator, facts.font_path);
    defer runtime.deinit();
    const before = runtime.fonts.cellMetrics(.{
        .slot = 0,
        .style = .normal,
    }).?;
    const request = handoff.FontRequest{
        .revision = 1,
        .scale = .{
            .revision = 9,
            .dpi_x = .{ .numerator = 768, .denominator = 5 },
            .dpi_y = .{ .numerator = 768, .denominator = 5 },
        },
        .policy = try handoff.FontPolicy.init(16.0),
    };
    try runtime.preflightFontRequest(request);
    runtime.commitFontRequest(request);
    try std.testing.expectEqual(request.scale.?, runtime.accepted_scale.?);
    try std.testing.expectEqual(
        before,
        runtime.fonts.cellMetrics(.{
            .slot = 0,
            .style = .normal,
        }).?,
    );
    var awaiting = request;
    awaiting.revision += 1;
    awaiting.scale = null;
    try runtime.preflightFontRequest(awaiting);
    runtime.commitFontRequest(awaiting);
    try std.testing.expect(runtime.accepted_scale == null);
}

test "pane point policy reaches each Logical atomically and new panes start at zero" {
    try std.testing.expectEqual(@as(usize, 56), @sizeOf(LogicalFontState));
    var boundary = try initBoundary(std.testing.io, std.testing.allocator);
    defer boundary.deinit();
    var first_slot = try handoff.PendingSlot.init(
        std.testing.allocator,
        contentLimits(),
    );
    var second_slot = try handoff.PendingSlot.init(
        std.testing.allocator,
        contentLimits(),
    );
    var new_slot = try handoff.PendingSlot.init(
        std.testing.allocator,
        contentLimits(),
    );
    defer {
        retireTestSlot(&first_slot);
        retireTestSlot(&second_slot);
        retireTestSlot(&new_slot);
        first_slot.deinit();
        second_slot.deinit();
        new_slot.deinit();
    }
    var runtime = try Runtime.initTest(std.testing.allocator, facts.font_path);
    defer runtime.deinit();
    const first: render.chrome.PaneId = @fromBackingInt(101);
    const second: render.chrome.PaneId = @fromBackingInt(102);
    const fresh: render.chrome.PaneId = @fromBackingInt(103);
    const pixels = try testPixels(runtime.fonts, 8, 2);
    try runtime.add(
        first,
        "/bin/sh",
        "sleep 1",
        pixels,
        .{ .dedicated = &first_slot },
    );
    try runtime.add(
        second,
        "/bin/sh",
        "sleep 1",
        pixels,
        .{ .dedicated = &second_slot },
    );

    var policy = try handoff.FontPolicy.init(16.0);
    policy.count = 2;
    policy.offsets[0] = .{ .pane = first, .offset_points = -2.0 };
    policy.offsets[1] = .{ .pane = second, .offset_points = 3.0 };
    const scale = handoff.ScaleSnapshot{
        .revision = 7,
        .dpi_x = .{ .numerator = 96, .denominator = 1 },
        .dpi_y = .{ .numerator = 96, .denominator = 1 },
    };
    const accepted = handoff.FontRequest{
        .revision = 1,
        .scale = scale,
        .policy = policy,
    };
    try runtime.preflightFontRequest(accepted);
    try std.testing.expect(try runtime.resizePointFonts(&boundary, accepted));
    const first_state = runtime.owners[runtime.find(first).?].?.font_state;
    const second_state = runtime.owners[runtime.find(second).?].?.font_state;
    try std.testing.expectEqual(@as(f64, -2.0), first_state.offset_points);
    try std.testing.expectEqual(@as(f64, 3.0), second_state.offset_points);
    try std.testing.expectEqual(scale, first_state.scale.?);
    try std.testing.expectEqual(scale, second_state.scale.?);
    const first_group = runtime.owners[runtime.find(first).?].?.font_group.?;
    const second_group = runtime.owners[runtime.find(second).?].?.font_group.?;
    try std.testing.expect(!std.meta.eql(first_group, second_group));
    const first_metrics = runtime.owners[runtime.find(first).?].?.geometry.metrics;
    const second_metrics = runtime.owners[runtime.find(second).?].?.geometry.metrics;
    try std.testing.expect(second_metrics.height_px > first_metrics.height_px);

    var invalid = accepted;
    invalid.revision = 2;
    invalid.policy.offsets[0] = invalid.policy.offsets[1];
    const retained_policy = runtime.accepted_font_policy;
    try std.testing.expectError(
        error.InvalidFontPolicy,
        runtime.preflightFontRequest(invalid),
    );
    try std.testing.expectEqual(retained_policy, runtime.accepted_font_policy);
    try std.testing.expectEqual(
        first_state,
        runtime.owners[runtime.find(first).?].?.font_state,
    );
    try std.testing.expectEqual(
        second_state,
        runtime.owners[runtime.find(second).?].?.font_state,
    );

    var mutated = accepted;
    mutated.revision = 2;
    mutated.policy.offsets[0].offset_points = -1.0;
    try runtime.preflightFontRequest(mutated);
    try std.testing.expect(try runtime.resizePointFonts(&boundary, mutated));
    try std.testing.expectEqual(
        @as(f64, -1.0),
        runtime.owners[runtime.find(first).?].?.font_state.offset_points,
    );
    try std.testing.expectEqual(
        @as(f64, 3.0),
        runtime.owners[runtime.find(second).?].?.font_state.offset_points,
    );

    const retired_index = runtime.find(first).?;
    runtime.owners[retired_index].?.setLigatureMode(.always);
    try runtime.remove(first);
    try runtime.add(
        fresh,
        "/bin/sh",
        "sleep 1",
        pixels,
        .{ .dedicated = &new_slot },
    );
    const fresh_state = runtime.owners[runtime.find(fresh).?].?.font_state;
    try std.testing.expectEqual(retired_index, runtime.find(fresh).?);
    try std.testing.expectEqual(@as(f64, 0.0), fresh_state.offset_points);
    try std.testing.expectEqual(@as(u64, 2), fresh_state.request_revision);
    try std.testing.expect(runtime.owners[runtime.find(fresh).?].?.font_group != null);
    try std.testing.expectEqual(
        render.terminal.LigatureMode.never,
        runtime.owners[runtime.find(fresh).?].?.ligature_mode,
    );
}

test "pane pixels remain authoritative across equal grids and rejected resize" {
    var slot = try handoff.PendingSlot.init(std.testing.allocator, contentLimits());
    defer {
        retireTestSlot(&slot);
        slot.deinit();
    }
    var runtime = try Runtime.initTest(std.testing.allocator, facts.font_path);
    defer runtime.deinit();
    const pane: render.chrome.PaneId = @fromBackingInt(92);
    const initial = try testPixels(runtime.fonts, 8, 2);
    try runtime.add(pane, "/bin/sh", "sleep 1", initial, .{ .dedicated = &slot });
    const owner = &runtime.owners[runtime.find(pane).?].?;
    const sequence = owner.machine.semanticSequence();
    const same_grid = render.canvas.Size{
        .width = initial.width + 1,
        .height = initial.height + 1,
    };
    try owner.resize(same_grid);
    try std.testing.expectEqual(sequence, owner.machine.semanticSequence());
    try std.testing.expectEqual(same_grid, owner.pane_pixels);
    try std.testing.expectEqual(same_grid.width, owner.geometry.clip.width);
    try std.testing.expectEqual(same_grid.height, owner.geometry.clip.height);

    const retained_pixels = owner.pane_pixels;
    const retained_geometry = owner.geometry;
    const retained_view = owner.machine.semanticView(0);
    try std.testing.expectError(
        error.TerminalCapacity,
        owner.resize(.{
            .width = std.math.maxInt(u16),
            .height = std.math.maxInt(u16),
        }),
    );
    try std.testing.expectEqual(retained_pixels, owner.pane_pixels);
    try std.testing.expectEqual(retained_geometry, owner.geometry);
    try std.testing.expectEqual(retained_view.rows, owner.machine.semanticView(0).rows);
    try std.testing.expectEqual(retained_view.cols, owner.machine.semanticView(0).cols);
    try std.testing.expectError(
        error.InvalidPane,
        owner.resize(.{ .width = 0, .height = 1 }),
    );
    try std.testing.expectEqual(retained_pixels, owner.pane_pixels);
}

test "over-admission point request rolls back before PTY and later request succeeds" {
    var boundary = try initBoundary(std.testing.io, std.testing.allocator);
    defer boundary.deinit();
    var slot = try handoff.PendingSlot.init(std.testing.allocator, contentLimits());
    defer {
        retireTestSlot(&slot);
        slot.deinit();
    }
    var runtime = try Runtime.initTest(std.testing.allocator, facts.font_path);
    defer runtime.deinit();
    const pane: render.chrome.PaneId = @fromBackingInt(151);
    try runtime.add(
        pane,
        "/bin/sh",
        "sleep 1",
        .{ .width = 2390, .height = 1342 },
        .{ .dedicated = &slot },
    );
    const scale = handoff.ScaleSnapshot{
        .revision = 1,
        .dpi_x = .{ .numerator = 96, .denominator = 1 },
        .dpi_y = .{ .numerator = 96, .denominator = 1 },
    };
    const accepted = handoff.FontRequest{
        .revision = 1,
        .scale = scale,
        .policy = try handoff.FontPolicy.init(16.0),
    };
    try std.testing.expect(try runtime.resizePointFonts(&boundary, accepted));
    const owner = &runtime.owners[runtime.find(pane).?].?;
    const old_group = owner.font_group.?;
    const old_state = owner.font_state;
    const old_geometry = owner.geometry;
    const old_rows = owner.machine.semanticView(0).rows;
    const old_cols = owner.machine.semanticView(0).cols;
    const old_policy = runtime.accepted_font_policy;

    var invalid_metrics = accepted;
    invalid_metrics.revision = 2;
    invalid_metrics.policy.count = 1;
    invalid_metrics.policy.offsets[0] = .{
        .pane = pane,
        .offset_points = -15.25,
    };
    try std.testing.expectError(
        error.InvalidMetrics,
        runtime.resizePointFonts(&boundary, invalid_metrics),
    );
    try std.testing.expectEqual(old_group, owner.font_group.?);
    try std.testing.expectEqual(old_state, owner.font_state);
    try std.testing.expectEqual(old_geometry, owner.geometry);
    try std.testing.expectEqual(old_policy, runtime.accepted_font_policy);

    var too_small = accepted;
    too_small.revision = 3;
    too_small.policy.count = 1;
    too_small.policy.offsets[0] = .{
        .pane = pane,
        .offset_points = -10.0,
    };
    runtime.pending_font = too_small;
    try runtime.retryPendingFont(&boundary);
    try std.testing.expectEqual(too_small, runtime.pending_font.?);
    try std.testing.expectEqual(old_group, owner.font_group.?);
    try std.testing.expectEqual(old_state, owner.font_state);
    try std.testing.expectEqual(old_geometry, owner.geometry);
    try std.testing.expectEqual(old_rows, owner.machine.semanticView(0).rows);
    try std.testing.expectEqual(old_cols, owner.machine.semanticView(0).cols);
    try std.testing.expectEqual(old_policy, runtime.accepted_font_policy);

    var recovered = accepted;
    recovered.revision = 4;
    recovered.policy.offsets[0] = .{
        .pane = pane,
        .offset_points = 1.0,
    };
    recovered.policy.count = 1;
    runtime.pending_font = recovered;
    try runtime.retryPendingFont(&boundary);
    try std.testing.expect(runtime.pending_font == null);
    try std.testing.expectEqual(
        @as(f64, 1.0),
        owner.font_state.offset_points,
    );
}

test "hidden clamped offset commits exactly and late visible failure rolls back bytes" {
    var boundary = try initBoundary(std.testing.io, std.testing.allocator);
    defer boundary.deinit();
    var first_slot = try handoff.PendingSlot.init(
        std.testing.allocator,
        contentLimits(),
    );
    var second_slot = try handoff.PendingSlot.init(
        std.testing.allocator,
        contentLimits(),
    );
    defer {
        retireTestSlot(&first_slot);
        retireTestSlot(&second_slot);
        first_slot.deinit();
        second_slot.deinit();
    }
    var runtime = try Runtime.initTest(std.testing.allocator, facts.font_path);
    defer runtime.deinit();
    const hidden_pane: render.chrome.PaneId = @fromBackingInt(801);
    const visible_pane: render.chrome.PaneId = @fromBackingInt(802);
    const pixels = try testPixels(runtime.fonts, 8, 2);
    try runtime.add(
        hidden_pane,
        "/bin/sh",
        "sleep 1",
        pixels,
        .{ .dedicated = &first_slot },
    );
    try runtime.add(
        visible_pane,
        "/bin/sh",
        "sleep 1",
        pixels,
        .{ .dedicated = &second_slot },
    );
    var initial_policy = try handoff.FontPolicy.init(10.0);
    initial_policy.count = 1;
    initial_policy.offsets[0] = .{
        .pane = hidden_pane,
        .offset_points = 150.0,
    };
    const scale = handoff.ScaleSnapshot{
        .revision = 1,
        .dpi_x = .{ .numerator = 72, .denominator = 1 },
        .dpi_y = .{ .numerator = 72, .denominator = 1 },
    };
    const initial = handoff.FontRequest{
        .revision = 1,
        .scale = scale,
        .policy = initial_policy,
    };
    try std.testing.expect(try runtime.resizePointFonts(&boundary, initial));
    const hidden = &runtime.owners[runtime.find(hidden_pane).?].?;
    const visible = &runtime.owners[runtime.find(visible_pane).?].?;
    const clamped_key = try resolvedGroupKey(hidden.font_state);

    const hidden_group = hidden.font_group.?;
    var producer = try runtime.shared_fonts.producer(hidden_group);
    hidden.content.releaseFontResources(.{ .shared = &producer });
    producer.deinit();
    hidden.content.rebindFonts(runtime.fonts, .local);
    try runtime.shared_fonts.releaseGroup(hidden_group);
    hidden.font_group = null;
    hidden.fonts = runtime.fonts;
    hidden.font_released_hidden = true;
    runtime.accepted_visible_revision = 1;
    runtime.accepted_visible_count = 1;
    runtime.accepted_visible_members[0] = .{
        .pane = visible_pane,
        .source = @fromBackingInt(1),
    };

    var equal_key_policy = initial_policy;
    equal_key_policy.offsets[0].offset_points = 151.0;
    const equal_key = handoff.FontRequest{
        .revision = 2,
        .scale = scale,
        .policy = equal_key_policy,
    };
    try std.testing.expect(try runtime.resizePointFonts(&boundary, equal_key));
    try std.testing.expectEqual(clamped_key, try resolvedGroupKey(hidden.font_state));
    try std.testing.expectEqual(@as(f64, 151.0), hidden.font_state.offset_points);
    try std.testing.expectEqual(@as(u64, 2), hidden.font_state.request_revision);

    var retained_state: [@sizeOf(LogicalFontState)]u8 = undefined;
    @memcpy(&retained_state, std.mem.asBytes(&hidden.font_state));
    const retained_policy = runtime.accepted_font_policy;
    const retained_pixels = visible.pane_pixels;
    visible.pane_pixels = .{
        .width = std.math.maxInt(u16),
        .height = std.math.maxInt(u16),
    };
    defer visible.pane_pixels = retained_pixels;
    var rejected_policy = equal_key_policy;
    rejected_policy.count = 2;
    rejected_policy.offsets[0].offset_points = 152.0;
    rejected_policy.offsets[1] = .{
        .pane = visible_pane,
        .offset_points = 1.0,
    };
    const rejected = handoff.FontRequest{
        .revision = 3,
        .scale = scale,
        .policy = rejected_policy,
    };
    try std.testing.expectError(
        error.TerminalCapacity,
        runtime.resizePointFonts(&boundary, rejected),
    );
    try std.testing.expectEqualSlices(
        u8,
        &retained_state,
        std.mem.asBytes(&hidden.font_state),
    );
    try std.testing.expectEqual(retained_policy, runtime.accepted_font_policy);
}

test "tiny and independent pane pixels derive only through current font metrics" {
    const metrics = render.terminal.CellMetrics{
        .width_px = 9,
        .height_px = 22,
        .baseline_px = 17,
    };
    try std.testing.expectEqual(
        Grid{ .cols = 1, .rows = 1 },
        try gridForPixels(.{ .width = 1, .height = 1 }, metrics),
    );

    var first_slot = try handoff.PendingSlot.init(std.testing.allocator, contentLimits());
    var second_slot = try handoff.PendingSlot.init(std.testing.allocator, contentLimits());
    defer {
        retireTestSlot(&first_slot);
        retireTestSlot(&second_slot);
        first_slot.deinit();
        second_slot.deinit();
    }
    var runtime = try Runtime.initTest(std.testing.allocator, facts.font_path);
    defer runtime.deinit();
    const first: render.chrome.PaneId = @fromBackingInt(93);
    const second: render.chrome.PaneId = @fromBackingInt(94);
    const first_pixels = render.canvas.Size{ .width = 101, .height = 51 };
    const second_pixels = render.canvas.Size{ .width = 203, .height = 87 };
    try runtime.add(first, "/bin/sh", "sleep 1", first_pixels, .{ .dedicated = &first_slot });
    try runtime.add(second, "/bin/sh", "sleep 1", second_pixels, .{ .dedicated = &second_slot });
    try std.testing.expectEqual(first_pixels, runtime.owners[runtime.find(first).?].?.pane_pixels);
    try std.testing.expectEqual(second_pixels, runtime.owners[runtime.find(second).?].?.pane_pixels);
}

test "runtime lifecycle admission derives exact grids without owner mutation" {
    var runtime = try Runtime.initTest(std.testing.allocator, facts.font_path);
    defer runtime.deinit();
    runtime.accepted_scale = .{
        .revision = 1,
        .dpi_x = .{ .numerator = 96, .denominator = 1 },
        .dpi_y = .{ .numerator = 96, .denominator = 1 },
    };
    const pane: render.chrome.PaneId = @fromBackingInt(91);
    const source: render.canvas.SourceId = @fromBackingInt(92);
    var request = handoff.RuntimeAdmissionCopy{
        .revision = @fromBackingInt(1),
        .operation_count = 1,
        .input_count = 0,
        .registration = .{ .pane = pane, .source = source },
    };
    request.operations[0] = .{ .create = .{
        .pane = pane,
        .pixels = .{ .width = 1, .height = 1 },
    } };
    const admitted = runtime.validateLifecycleAdmission(request).admitted;
    try std.testing.expectEqual(@as(u8, 1), admitted.count);
    try std.testing.expectEqual(
        handoff.DerivedGrid{ .pane = pane, .rows = 1, .columns = 1 },
        admitted.grids[0],
    );
    try std.testing.expectEqual(@as(u8, 0), runtime.count);
    runtime.releaseLifecycleFont(request.revision);

    request.operations[0].create.pixels = .{ .width = 0, .height = 1 };
    try std.testing.expectEqual(
        handoff.AdmissionRejection.invalid_extent,
        runtime.validateLifecycleAdmission(request).rejected,
    );
    request.operations[0].create.pixels = .{
        .width = std.math.maxInt(u16),
        .height = std.math.maxInt(u16),
    };
    try std.testing.expectEqual(
        handoff.AdmissionRejection.terminal_capacity,
        runtime.validateLifecycleAdmission(request).rejected,
    );
    try std.testing.expectEqual(@as(u8, 0), runtime.count);
}

test "new-pane admission retains exact resolved metrics until commit or cancellation" {
    var boundary = try initBoundary(std.testing.io, std.testing.allocator);
    defer boundary.deinit();
    var runtime = try Runtime.initTest(std.testing.allocator, facts.font_path);
    defer runtime.deinit();
    runtime.accepted_scale = .{
        .revision = 3,
        .dpi_x = .{ .numerator = 144, .denominator = 1 },
        .dpi_y = .{ .numerator = 144, .denominator = 1 },
    };
    runtime.accepted_font_policy = try handoff.FontPolicy.init(21.0);
    runtime.accepted_font_request_revision = 4;
    const pane: render.chrome.PaneId = @fromBackingInt(201);
    const source: render.canvas.SourceId = @fromBackingInt(202);
    const operations = [_]handoff.Lifecycle{.{ .create = .{
        .pane = pane,
        .pixels = .{ .width = 401, .height = 211 },
    } }};
    var cancelled = try boundary.prepareLifecycle(
        &operations,
        &.{},
        .{ .pane = pane, .source = source },
    );
    const cancelled_revision = try cancelled.publishAdmission();
    const copied = boundary.takeLifecycleAdmission().?;
    const result = runtime.validateLifecycleAdmission(copied);
    const retained = runtime.pending_lifecycle_font.?;
    try std.testing.expectEqual(cancelled_revision, retained.revision);
    const metrics = retained.map.cellMetrics(.{
        .slot = 0,
        .style = .normal,
    }).?;
    const exact = try gridForPixels(operations[0].create.pixels, metrics);
    try std.testing.expectEqual(exact.rows, result.admitted.grids[0].rows);
    try std.testing.expectEqual(exact.cols, result.admitted.grids[0].columns);
    try boundary.completeLifecycleAdmission(cancelled_revision, result);
    cancelled.deinit();
    runtime.releaseCancelledLifecycleFont(&boundary);
    try std.testing.expect(runtime.pending_lifecycle_font == null);
    try std.testing.expectEqual(@as(u8, 0), runtime.count);
}

test "runtime admission copy has the pinned fixed storage size" {
    try std.testing.expectEqual(
        @as(usize, 3_352),
        @sizeOf(handoff.RuntimeAdmissionCopy),
    );
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
