//! Owns bounded terminal lifecycle, input, visibility, completion, and retirement handoff.
//!
//! Renderer and the terminal runtime exchange only Host lifecycle state through
//! this owner. Terminal pixels, Canvas updates, Content, GPU work, and frame
//! publication are deliberately outside this boundary.

const std = @import("std");
const wayland = @import("howl_wayland");
const vt = @import("howl_vt");

/// Identifies one never-reused Host terminal pane without Render ownership.
pub const PaneId = enum(u64) { _ };
const owner_limit: usize = 64;
const operation_limit: usize = 128;
const input_limit: usize = 256;
const lifecycle_batch_limit: usize = 128;
const linux = std.os.linux;
const eventfd_flags = linux.EFD.CLOEXEC | linux.EFD.NONBLOCK;

/// Maximum terminal owners in one visible membership.
pub const visible_member_limit: usize = 16;

/// Identifies a never-reused Render-owned terminal source without Canvas ownership.
pub const SourceId = enum(u64) { _ };

/// Stores one nonzero pane pixel extent.
pub const PixelSize = struct { width: u32, height: u32 };

/// Identifies one exact visible terminal owner.
pub const VisibleMember = struct { pane: PaneId, source: SourceId };

/// Stores one resolved cursor color.
pub const CursorColor = packed struct(u32) { r: u8 = 0, g: u8 = 0, b: u8 = 0, a: u8 = 255 };

/// Selects one static cursor shape.
pub const CursorShape = enum(u8) { block, underline, bar, none };

/// Copies one complete static semantic cursor target.
pub const CursorTarget = struct {
    row: u16,
    col: u16,
    visible: bool,
    shape: CursorShape,
    cursor_color: CursorColor,
    text_color: CursorColor,
};

/// Identifies one latest cursor observation for a live source.
pub const CursorPublication = struct {
    pane: PaneId,
    source: SourceId,
    terminal_sequence: u64,
    cursor_revision: u64,
    visible_set_revision: u64,
    lifecycle_revision: LifecycleRevision,
    target: CursorTarget,
};

/// Binds a cursor target to accepted lifecycle and visibility.
pub const CursorPublicationIdentity = struct {
    lifecycle_revision: LifecycleRevision,
    visible_set_revision: u64,
};

/// Reports exact cursor identity rejection.
pub const CursorPublishError = error{
    Stopping,
    InvalidCursorPublication,
    UnknownPane,
    RetiredPane,
    SourceStale,
    LifecycleStale,
    CursorRevisionStale,
};

/// Copies one bounded visible-set request.
pub const VisibleSetRequest = struct {
    revision: u64,
    members: [visible_member_limit]VisibleMember,
    count: u8,
};

/// Identifies one never-reused lifecycle candidate.
pub const LifecycleRevision = enum(u64) { _ };

/// Stores exact child termination.
pub const TerminalTermination = union(enum) { code: u8, signal: u8 };

/// Carries completion after final terminal output has been accepted by Render.
pub const TerminalCompletion = struct {
    pane: PaneId,
    source: SourceId,
    lifecycle_revision: LifecycleRevision,
    render_sequence: u64,
    termination: TerminalTermination,
};

/// Reports completion identity or at-most-once rejection.
pub const CompletionPublishError = error{
    Stopping,
    InvalidCompletion,
    UnknownPane,
    RetiredPane,
    SourceStale,
    LifecycleStale,
    DuplicateCompletion,
};

/// Stores one runtime-derived terminal grid.
pub const DerivedGrid = struct { pane: PaneId, rows: u16, columns: u16 };

/// Classifies lifecycle admission rejection.
pub const AdmissionRejection = enum {
    invalid_pane,
    unknown_pane,
    duplicate_pane,
    invalid_extent,
    terminal_capacity,
    stopping,
};

/// Reports requested visibility progress.
pub const VisibleSetStatus = enum { pending, ready, stale };

/// Copies one terminal lifecycle operation.
pub const Lifecycle = union(enum) {
    create: struct { pane: PaneId, pixels: PixelSize },
    resize: struct { pane: PaneId, pixels: PixelSize },
    close: PaneId,
};

/// Copies one interpreted key for one pane.
pub const KeyInput = struct { pane: PaneId, key: wayland.input.Key };

/// Copies one terminal input occurrence.
pub const TerminalInput = union(enum) {
    key: KeyInput,
    focus: struct { pane: PaneId, event: vt.Terminal.InputEvent },
};

/// Supplies the source identity for one lifecycle create.
pub const Registration = struct { pane: PaneId, source: SourceId };

/// Copies one lifecycle candidate for Runtime validation.
pub const RuntimeAdmissionCopy = struct {
    revision: LifecycleRevision,
    operations: [lifecycle_batch_limit]Lifecycle = undefined,
    operation_count: u8,
    grids: [lifecycle_batch_limit]DerivedGrid = undefined,
    grid_count: u8,
    inputs: [2]TerminalInput = undefined,
    input_count: u8,
    registration: ?Registration,
};

/// Copies one lifecycle admission result.
pub const LifecycleAdmissionResult = union(enum) {
    admitted,
    rejected: AdmissionRejection,
};

/// Couples one dequeued lifecycle operation to its admitted grid.
pub const AdmittedLifecycle = struct {
    revision: LifecycleRevision,
    operation: Lifecycle,
    grid: ?DerivedGrid,
};

/// Reports boundary construction failure.
pub const BoundaryInitError = error{Signal};
/// Preserves the prior construction error alias for current Host callers.
pub const InitError = error{Signal};

const EntryState = enum(u8) { registered, live, closing, retired, removing };
const Entry = struct { pane: PaneId, source: SourceId, lifecycle_revision: LifecycleRevision, state: EntryState = .registered };
const CursorSlot = struct {
    terminal_sequence_high_water: u64 = 0,
    cursor_revision_high_water: u64 = 0,
    pending: ?CursorPublication = null,
};
const CompletionState = union(enum) { empty, pending: TerminalCompletion, consumed };
const AdmissionPhase = enum(u8) { none, requested, validating, admitted, rejected };
const VisiblePhase = enum(u8) { requested, prepared, committing };
const VisibleRequest = struct { request: VisibleSetRequest, phase: VisiblePhase = .requested };

/// Owns the fixed terminal cross-thread control boundary.
pub const Boundary = struct {
    io: std.Io,
    mutex: std.Io.Mutex = .init,
    terminal_fd: i32,
    renderer_fd: i32,
    entries: [owner_limit]?Entry = @splat(null),
    operations: [operation_limit]Lifecycle = undefined,
    operation_grids: [operation_limit]?DerivedGrid = @splat(null),
    operation_revisions: [operation_limit]LifecycleRevision = @splat(@fromBackingInt(0)),
    operation_head: u8 = 0,
    operation_count: u8 = 0,
    reserved_operations: u8 = 0,
    inputs: [input_limit]TerminalInput = undefined,
    input_head: u8 = 0,
    input_count: u16 = 0,
    reserved_inputs: u16 = 0,
    lifecycle_high_water: u64 = 0,
    candidate_active: bool = false,
    admission_phase: AdmissionPhase = .none,
    admission_revision: LifecycleRevision = @fromBackingInt(0),
    admission_operations: [lifecycle_batch_limit]Lifecycle = undefined,
    admission_operation_count: u8 = 0,
    admission_grids: [lifecycle_batch_limit]DerivedGrid = undefined,
    admission_grid_count: u8 = 0,
    admission_inputs: [2]TerminalInput = undefined,
    admission_input_count: u8 = 0,
    admission_registration: ?Registration = null,
    admission_result: LifecycleAdmissionResult = undefined,
    reserved_entry: ?u8 = null,
    visible_high_water: u64 = 0,
    visible_request: ?VisibleRequest = null,
    prepared_visible: ?VisibleSetRequest = null,
    visible_members: [visible_member_limit]VisibleMember = undefined,
    visible_member_count: u8 = 0,
    visible_revision: u64 = 0,
    visible_initialized: bool = false,
    cursors: [owner_limit]CursorSlot = @splat(.{}),
    completions: [owner_limit]CompletionState = @splat(.empty),
    stopping: bool = false,
    stopped: bool = false,
    failed: bool = false,

    /// Creates two directional nonblocking eventfds.
    pub fn init(io: std.Io, _: std.mem.Allocator) BoundaryInitError!Boundary {
        const pair = try createWakePair(NativeEventfd);
        return .{ .io = io, .terminal_fd = pair.first, .renderer_fd = pair.second };
    }

    /// Closes exact wake ownership after all runtime owners join.
    pub fn deinit(self: *Boundary) void {
        closeDescriptor(self.renderer_fd);
        closeDescriptor(self.terminal_fd);
        self.* = undefined;
    }

    /// Owns one invisible lifecycle candidate until commit or cancellation.
    pub const PreparedLifecycle = struct {
        boundary: *Boundary,
        revision: LifecycleRevision,
        operation_count: u8,
        input_count: u8,
        published: bool = false,
        complete: bool = false,

        /// Publishes this candidate once for Runtime validation.
        pub fn publishAdmission(self: *PreparedLifecycle) error{ Stopping, StaleRevision }!LifecycleRevision {
            const b = self.boundary;
            b.mutex.lockUncancelable(b.io);
            defer b.mutex.unlock(b.io);
            if (b.stopping) return error.Stopping;
            if (self.published or self.complete or !b.candidate_active or b.admission_phase != .none) return error.StaleRevision;
            b.admission_phase = .requested;
            self.published = true;
            signal(b.terminal_fd);
            return self.revision;
        }

        /// Copies the completed validation result without committing it.
        pub fn admissionResult(self: *PreparedLifecycle) ?LifecycleAdmissionResult {
            const b = self.boundary;
            b.mutex.lockUncancelable(b.io);
            defer b.mutex.unlock(b.io);
            if (!self.published or b.admission_revision != self.revision) return null;
            return switch (b.admission_phase) {
                .admitted, .rejected => b.admission_result,
                else => null,
            };
        }

        /// Commits exactly one admitted candidate into the bounded rings.
        pub fn commitAdmitted(self: *PreparedLifecycle) error{ Stopping, NotAdmitted, StaleRevision }!void {
            const b = self.boundary;
            b.mutex.lockUncancelable(b.io);
            defer b.mutex.unlock(b.io);
            if (b.stopping) return error.Stopping;
            if (!b.candidate_active or b.admission_revision != self.revision) return error.StaleRevision;
            if (b.admission_phase != .admitted) return error.NotAdmitted;
            if (b.admission_registration) |registration| {
                const index = b.reserved_entry orelse unreachable;
                b.entries[index] = .{ .pane = registration.pane, .source = registration.source, .lifecycle_revision = self.revision };
            }
            var grid_index: usize = 0;
            for (b.admission_operations[0..self.operation_count]) |operation| {
                const grid: ?DerivedGrid = switch (operation) {
                    .create, .resize => blk: {
                        const value = b.admission_grids[grid_index];
                        grid_index += 1;
                        break :blk value;
                    },
                    .close => null,
                };
                b.pushOperation(operation, grid, self.revision);
                if (operation == .resize)
                    b.entries[b.find(operation.resize.pane).?].?.lifecycle_revision = self.revision;
                if (operation == .close) b.entries[b.find(operation.close).?].?.state = .closing;
            }
            for (b.admission_inputs[0..self.input_count]) |input| b.pushInput(input);
            b.reserved_operations -= self.operation_count;
            b.reserved_inputs -= self.input_count;
            b.clearCandidate();
            self.complete = true;
            signal(b.terminal_fd);
        }

        /// Cancels an uncommitted candidate and releases reserved capacity.
        pub fn deinit(self: *PreparedLifecycle) void {
            if (self.complete) return;
            const b = self.boundary;
            b.mutex.lockUncancelable(b.io);
            std.debug.assert(b.candidate_active);
            std.debug.assert(b.admission_revision == self.revision);
            b.reserved_operations -= self.operation_count;
            b.reserved_inputs -= self.input_count;
            b.clearCandidate();
            b.mutex.unlock(b.io);
            self.complete = true;
            signal(b.renderer_fd);
        }
    };

    /// Reserves one lifecycle candidate without exposing partial work.
    pub fn prepareLifecycle(
        self: *Boundary,
        operations: []const Lifecycle,
        grids: []const DerivedGrid,
        inputs: []const TerminalInput,
        registration: ?Registration,
    ) error{
        InvalidPane,
        DuplicatePane,
        UnknownPane,
        OwnerLimit,
        OperationLimit,
        CandidatePending,
        Stopping,
        RevisionOverflow,
    }!PreparedLifecycle {
        if (operations.len > lifecycle_batch_limit or grids.len > lifecycle_batch_limit or inputs.len > 2) return error.OperationLimit;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.stopping) return error.Stopping;
        if (self.candidate_active) return error.CandidatePending;
        if (operations.len > operation_limit - self.operation_count - self.reserved_operations or
            inputs.len > input_limit - self.input_count - self.reserved_inputs) return error.OperationLimit;
        var new_index: ?usize = null;
        if (registration) |value| {
            if (!validPane(value.pane) or !validSource(value.source)) return error.InvalidPane;
            if (self.find(value.pane) != null) return error.DuplicatePane;
            new_index = self.freeIndex() orelse return error.OwnerLimit;
        }
        var grid_index: usize = 0;
        for (operations) |operation| switch (operation) {
            .create => |value| {
                if (registration == null or registration.?.pane != value.pane or !validPixels(value.pixels)) return error.InvalidPane;
                if (grid_index == grids.len or !validGrid(grids[grid_index], value.pane)) return error.InvalidPane;
                grid_index += 1;
            },
            .resize => |value| {
                if (!validPixels(value.pixels)) return error.InvalidPane;
                if (self.find(value.pane) == null) return error.UnknownPane;
                if (grid_index == grids.len or !validGrid(grids[grid_index], value.pane)) return error.InvalidPane;
                grid_index += 1;
            },
            .close => |pane| if (self.find(pane) == null) return error.UnknownPane,
        };
        if (grid_index != grids.len) return error.InvalidPane;
        for (inputs) |input| {
            const pane = inputPane(input);
            if (self.find(pane) == null and (registration == null or registration.?.pane != pane)) return error.UnknownPane;
        }
        const revision = try self.nextRevision();
        @memcpy(self.admission_operations[0..operations.len], operations);
        @memcpy(self.admission_grids[0..grids.len], grids);
        @memcpy(self.admission_inputs[0..inputs.len], inputs);
        self.admission_operation_count = @intCast(operations.len);
        self.admission_grid_count = @intCast(grids.len);
        self.admission_input_count = @intCast(inputs.len);
        self.admission_registration = registration;
        self.admission_revision = revision;
        self.admission_phase = .none;
        self.candidate_active = true;
        self.reserved_operations += @intCast(operations.len);
        self.reserved_inputs += @intCast(inputs.len);
        self.reserved_entry = if (new_index) |index| @intCast(index) else null;
        return .{ .boundary = self, .revision = revision, .operation_count = @intCast(operations.len), .input_count = @intCast(inputs.len) };
    }

    /// Preflights replacement after accounting for the currently reserved candidate.
    pub fn preflightLifecycleReplacement(
        self: *Boundary,
        operation_count: usize,
        input_count: usize,
        needs_registration: bool,
    ) error{ Stopping, OwnerLimit, OperationLimit }!void {
        if (operation_count > lifecycle_batch_limit or input_count > 2) return error.OperationLimit;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.stopping) return error.Stopping;
        const available_operations = operation_limit - self.operation_count -
            (if (self.candidate_active) 0 else self.reserved_operations);
        const available_inputs = input_limit - self.input_count -
            (if (self.candidate_active) 0 else self.reserved_inputs);
        if (operation_count > available_operations or input_count > available_inputs)
            return error.OperationLimit;
        if (needs_registration and self.reserved_entry == null and self.freeIndex() == null)
            return error.OwnerLimit;
    }

    /// Copies one requested admission for Runtime validation.
    pub fn takeLifecycleAdmission(self: *Boundary) ?RuntimeAdmissionCopy {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.admission_phase != .requested) return null;
        var result = RuntimeAdmissionCopy{ .revision = self.admission_revision, .operation_count = self.admission_operation_count, .grid_count = self.admission_grid_count, .input_count = self.admission_input_count, .registration = self.admission_registration };
        @memcpy(result.operations[0..result.operation_count], self.admission_operations[0..result.operation_count]);
        @memcpy(result.grids[0..result.grid_count], self.admission_grids[0..result.grid_count]);
        @memcpy(result.inputs[0..result.input_count], self.admission_inputs[0..result.input_count]);
        self.admission_phase = .validating;
        return result;
    }

    /// Completes one exact lifecycle validation without committing it.
    pub fn completeLifecycleAdmission(self: *Boundary, revision: LifecycleRevision, result: LifecycleAdmissionResult) error{ StaleRevision, CandidatePhase, Stopping }!void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.stopping) return error.Stopping;
        if (revision != self.admission_revision) return error.StaleRevision;
        if (self.admission_phase != .validating) return error.CandidatePhase;
        self.admission_result = result;
        self.admission_phase = if (result == .admitted) .admitted else .rejected;
        signal(self.renderer_fd);
    }

    /// Dequeues one admitted lifecycle operation and wakes Renderer after capacity frees.
    pub fn takeAdmittedLifecycle(self: *Boundary) ?AdmittedLifecycle {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.operation_count == 0) return null;
        const index = self.operation_head;
        const result = AdmittedLifecycle{ .revision = self.operation_revisions[index], .operation = self.operations[index], .grid = self.operation_grids[index] };
        self.operation_head = @intCast((@as(usize, self.operation_head) + 1) % operation_limit);
        self.operation_count -= 1;
        signal(self.renderer_fd);
        return result;
    }

    /// Dequeues the oldest terminal input and publishes freed capacity.
    pub fn takeInput(self: *Boundary) ?TerminalInput {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.input_count == 0) return null;
        const result = self.inputs[self.input_head];
        self.input_head = @intCast((@as(usize, self.input_head) + 1) % input_limit);
        self.input_count -= 1;
        signal(self.renderer_fd);
        return result;
    }

    /// Appends one interpreted key for an exact live or registered pane.
    pub fn publishKey(self: *Boundary, pane: PaneId, key: wayland.input.Key) error{ UnknownPane, OperationLimit }!void {
        try self.publishInput(.{ .key = .{ .pane = pane, .key = key } });
    }
    /// Appends one canonical focus transition for an exact pane.
    pub fn publishFocus(self: *Boundary, pane: PaneId, event: vt.Terminal.InputEvent) error{ InvalidPane, UnknownPane, OperationLimit }!void {
        if (std.meta.activeTag(event) != .focus) return error.InvalidPane;
        try self.publishInput(.{ .focus = .{ .pane = pane, .event = event } });
    }

    /// Re-signals retained terminal work after one bounded turn.
    pub fn rearmTerminalWork(self: *Boundary) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.operation_count != 0 or self.input_count != 0 or self.admission_phase == .requested) signal(self.terminal_fd);
    }

    /// Owns one invisible visible-set candidate.
    pub const PreparedVisibleSet = struct {
        boundary: *Boundary,
        revision: u64,
        complete: bool = false,
        /// Commits this invisible membership atomically.
        pub fn commit(self: *PreparedVisibleSet) void {
            const b = self.boundary;
            b.mutex.lockUncancelable(b.io);
            const request = b.prepared_visible.?;
            std.debug.assert(request.revision == self.revision);
            @memcpy(b.visible_members[0..request.count], request.members[0..request.count]);
            b.visible_member_count = request.count;
            b.visible_revision = request.revision;
            b.visible_initialized = true;
            b.visible_request = null;
            b.prepared_visible = null;
            b.mutex.unlock(b.io);
            self.complete = true;
            signal(b.terminal_fd);
        }
        /// Cancels this membership while retaining its issued revision.
        pub fn deinit(self: *PreparedVisibleSet) void {
            if (self.complete) return;
            const b = self.boundary;
            b.mutex.lockUncancelable(b.io);
            if (b.prepared_visible != null and b.prepared_visible.?.revision == self.revision) b.prepared_visible = null;
            b.mutex.unlock(b.io);
            self.complete = true;
        }
    };

    /// Validates and retains one invisible membership candidate.
    pub fn prepareVisibleSet(self: *Boundary, revision: u64, members: []const VisibleMember) error{ InvalidCandidateRevision, InvalidPane, DuplicatePane, CandidatePending, Stopping }!PreparedVisibleSet {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        try self.validateVisibleLocked(revision, members);
        if (self.prepared_visible != null or self.visible_request != null)
            return error.CandidatePending;
        const request = copyVisible(revision, members);
        self.prepared_visible = request;
        self.visible_high_water = revision;
        return .{ .boundary = self, .revision = revision };
    }

    /// Publishes the newest Runtime-prepared membership request.
    pub fn publishVisibleSet(self: *Boundary, revision: u64, members: []const VisibleMember) error{ InvalidCandidateRevision, InvalidPane, DuplicatePane, CandidatePending, Stopping }!void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        try self.validateVisibleLocked(revision, members);
        if (self.prepared_visible != null or self.visible_request != null)
            return error.CandidatePending;
        self.visible_request = .{ .request = copyVisible(revision, members) };
        self.visible_high_water = revision;
        signal(self.terminal_fd);
    }

    /// Copies the current unclaimed membership request.
    pub fn visibleSetRequest(self: *Boundary) ?VisibleSetRequest {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const request = self.visible_request orelse return null;
        return if (request.phase == .requested) request.request else null;
    }

    /// Runtime marks membership preparation complete without render payload ownership.
    pub fn completeVisibleSet(self: *Boundary, revision: u64) error{Stale}!void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const request = if (self.visible_request) |*value| value else return error.Stale;
        if (request.request.revision != revision or request.phase != .requested) return error.Stale;
        request.phase = .prepared;
        signal(self.renderer_fd);
    }

    /// Classifies one exact membership revision.
    pub fn visibleSetStatus(self: *Boundary, revision: u64) VisibleSetStatus {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const request = self.visible_request orelse return .stale;
        if (request.request.revision != revision) return .stale;
        return if (request.phase == .requested) .pending else .ready;
    }
    /// Claims one prepared membership for Renderer commit.
    pub fn claimVisibleSet(self: *Boundary, revision: u64) error{Stale}!void {
        self.setVisiblePhase(revision, .prepared, .committing) catch return error.Stale;
    }
    /// Restores one failed membership claim for retry.
    pub fn releaseVisibleSetClaim(self: *Boundary, revision: u64) error{Stale}!void {
        self.setVisiblePhase(revision, .committing, .prepared) catch return error.Stale;
    }
    /// Makes one exclusively claimed membership accepted.
    ///
    /// Publication cannot replace a retained request in any phase, so the sole
    /// Renderer claimant makes this transition infallibly after Composer commit.
    pub fn commitVisibleSet(self: *Boundary, revision: u64) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const state = self.visible_request orelse unreachable;
        std.debug.assert(state.request.revision == revision);
        std.debug.assert(state.phase == .committing);
        @memcpy(self.visible_members[0..state.request.count], state.request.members[0..state.request.count]);
        self.visible_member_count = state.request.count;
        self.visible_revision = revision;
        self.visible_initialized = true;
        self.visible_request = null;
    }
    /// Copies the currently accepted membership.
    pub fn acceptedVisibleSet(self: *Boundary) ?VisibleSetRequest {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (!self.visible_initialized) return null;
        var result = VisibleSetRequest{ .revision = self.visible_revision, .members = undefined, .count = self.visible_member_count };
        @memcpy(result.members[0..result.count], self.visible_members[0..result.count]);
        return result;
    }

    /// Records successful terminal-owner construction.
    pub fn markLive(self: *Boundary, pane: PaneId) error{UnknownPane}!void {
        self.setEntryState(pane, .registered, .live) catch return error.UnknownPane;
    }

    /// Returns the exact source for one registered lifecycle owner.
    pub fn sourceFor(self: *Boundary, pane: PaneId) ?SourceId {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const index = self.find(pane) orelse return null;
        return self.entries[index].?.source;
    }
    /// Returns the accepted static-cursor identity for one visible live source.
    pub fn cursorPublicationIdentity(self: *Boundary, pane: PaneId, source: SourceId) CursorPublishError!?CursorPublicationIdentity {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const index = self.find(pane) orelse return error.UnknownPane;
        const entry = self.entries[index].?;
        if (entry.source != source) return error.SourceStale;
        if (entry.state != .live) return error.RetiredPane;
        if (!self.isVisible(pane, source)) return null;
        return .{ .lifecycle_revision = entry.lifecycle_revision, .visible_set_revision = self.visible_revision };
    }
    /// Replaces one pane's pending cursor after monotonic validation.
    pub fn publishCursor(self: *Boundary, publication: CursorPublication) CursorPublishError!void {
        if (publication.terminal_sequence == 0 or publication.cursor_revision == 0) return error.InvalidCursorPublication;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.stopping) return error.Stopping;
        const index = self.find(publication.pane) orelse return error.UnknownPane;
        const entry = self.entries[index].?;
        if (entry.source != publication.source) return error.SourceStale;
        if (entry.state != .live) return error.RetiredPane;
        if (entry.lifecycle_revision != publication.lifecycle_revision) return error.LifecycleStale;
        const slot = &self.cursors[index];
        if (publication.cursor_revision <= slot.cursor_revision_high_water or publication.terminal_sequence < slot.terminal_sequence_high_water) return error.CursorRevisionStale;
        slot.cursor_revision_high_water = publication.cursor_revision;
        slot.terminal_sequence_high_water = publication.terminal_sequence;
        slot.pending = publication;
        signal(self.renderer_fd);
    }
    /// Takes one pane's newest pending cursor.
    pub fn takeCursor(self: *Boundary, pane: PaneId) ?CursorPublication {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const index = self.find(pane) orelse return null;
        const result = self.cursors[index].pending;
        self.cursors[index].pending = null;
        return result;
    }

    /// Publishes one at-most-once child completion for a live identity.
    pub fn publishCompletion(self: *Boundary, completion: TerminalCompletion) CompletionPublishError!void {
        if (completion.render_sequence == 0) return error.InvalidCompletion;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.stopping) return error.Stopping;
        const index = self.find(completion.pane) orelse return error.UnknownPane;
        const entry = self.entries[index].?;
        if (entry.source != completion.source) return error.SourceStale;
        if (entry.state != .live) return error.RetiredPane;
        if (entry.lifecycle_revision != completion.lifecycle_revision) return error.LifecycleStale;
        if (self.completions[index] != .empty) return error.DuplicateCompletion;
        self.completions[index] = .{ .pending = completion };
        signal(self.renderer_fd);
    }
    /// Takes one pending completion while retaining its consumed state.
    pub fn takeCompletion(self: *Boundary) ?TerminalCompletion {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        for (&self.completions) |*slot| if (slot.* == .pending) {
            const result = slot.pending;
            slot.* = .consumed;
            return result;
        };
        return null;
    }
    /// Reports whether any completion awaits Renderer.
    pub fn hasReadyCompletion(self: *Boundary) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        for (self.completions) |slot| if (slot == .pending) return true;
        return false;
    }
    /// Validates a retained completion against current owner identity.
    pub fn completionIsCurrent(self: *Boundary, completion: TerminalCompletion) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const index = self.find(completion.pane) orelse return false;
        const entry = self.entries[index].?;
        return entry.source == completion.source and entry.lifecycle_revision == completion.lifecycle_revision and entry.state == .live;
    }

    /// Terminal confirms no pending byte ownership remains before retirement.
    pub fn retireTransfer(self: *Boundary, pane: PaneId) error{UnknownPane}!bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const index = self.find(pane) orelse return error.UnknownPane;
        return self.entries[index].?.state == .closing;
    }
    /// Records terminal-side retirement and clears pending observations.
    pub fn markRetired(self: *Boundary, pane: PaneId) error{UnknownPane}!void {
        self.setEntryState(pane, .closing, .retired) catch return error.UnknownPane;
    }
    /// Transfers one retired source identity to Renderer.
    pub fn takeRetired(self: *Boundary) ?struct { pane: PaneId, source: SourceId } {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        for (&self.entries) |*maybe| if (maybe.*) |*entry| if (entry.state == .retired) {
            entry.state = .removing;
            return .{ .pane = entry.pane, .source = entry.source };
        };
        return null;
    }
    /// Releases one source slot only after Renderer removal.
    pub fn finishRetired(self: *Boundary, pane: PaneId) error{UnknownPane}!void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const index = self.find(pane) orelse return error.UnknownPane;
        if (self.entries[index].?.state != .removing) return error.UnknownPane;
        self.entries[index] = null;
        self.cursors[index] = .{};
        self.completions[index] = .empty;
        signal(self.renderer_fd);
    }

    /// Borrows the terminal-direction wake descriptor.
    pub fn terminalFd(self: *const Boundary) i32 {
        return self.terminal_fd;
    }
    /// Borrows the Renderer-direction wake descriptor.
    pub fn rendererFd(self: *const Boundary) i32 {
        return self.renderer_fd;
    }
    /// Drains all terminal-direction wake counts.
    pub fn drainTerminalWake(self: *Boundary) error{Signal}!void {
        try drain(self.terminal_fd);
    }
    /// Drains all Renderer-direction wake counts.
    pub fn drainRendererWake(self: *Boundary) error{Signal}!void {
        try drain(self.renderer_fd);
    }
    /// Begins monotonic terminal shutdown and wakes Runtime.
    pub fn shutdown(self: *Boundary) void {
        self.mutex.lockUncancelable(self.io);
        self.stopping = true;
        self.mutex.unlock(self.io);
        signal(self.terminal_fd);
    }
    /// Reports monotonic shutdown state.
    pub fn isStopping(self: *Boundary) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.stopping;
    }
    /// Records terminal-thread completion and its first failure.
    pub fn markStopped(self: *Boundary, failed: bool) void {
        self.mutex.lockUncancelable(self.io);
        self.stopped = true;
        self.failed = self.failed or failed;
        self.mutex.unlock(self.io);
        signal(self.renderer_fd);
    }
    /// Copies terminal-thread completion state.
    pub fn status(self: *Boundary) struct { stopped: bool, failed: bool } {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return .{ .stopped = self.stopped, .failed = self.failed };
    }

    fn validateVisibleLocked(self: *Boundary, revision: u64, members: []const VisibleMember) error{ InvalidCandidateRevision, InvalidPane, DuplicatePane, Stopping }!void {
        if (revision == 0 or members.len > visible_member_limit) return error.InvalidCandidateRevision;
        if (self.stopping) return error.Stopping;
        if (revision <= self.visible_high_water) return error.InvalidCandidateRevision;
        for (members, 0..) |member, index| {
            const owner = self.find(member.pane) orelse return error.InvalidPane;
            if (self.entries[owner].?.source != member.source) return error.InvalidPane;
            for (members[0..index]) |prior| if (prior.pane == member.pane or prior.source == member.source) return error.DuplicatePane;
        }
    }
    fn setVisiblePhase(self: *Boundary, revision: u64, from: VisiblePhase, to: VisiblePhase) error{Stale}!void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const request = if (self.visible_request) |*value| value else return error.Stale;
        if (request.request.revision != revision or request.phase != from) return error.Stale;
        request.phase = to;
    }
    fn publishInput(self: *Boundary, input: TerminalInput) error{ UnknownPane, OperationLimit }!void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.find(inputPane(input)) == null) return error.UnknownPane;
        if (self.input_count + self.reserved_inputs == input_limit) return error.OperationLimit;
        self.pushInput(input);
        signal(self.terminal_fd);
    }
    fn pushOperation(self: *Boundary, operation: Lifecycle, grid: ?DerivedGrid, revision: LifecycleRevision) void {
        const tail = (@as(usize, self.operation_head) + self.operation_count) % operation_limit;
        self.operations[tail] = operation;
        self.operation_grids[tail] = grid;
        self.operation_revisions[tail] = revision;
        self.operation_count += 1;
    }
    fn pushInput(self: *Boundary, input: TerminalInput) void {
        const tail = (@as(usize, self.input_head) + self.input_count) % input_limit;
        self.inputs[tail] = input;
        self.input_count += 1;
    }
    fn find(self: *const Boundary, pane: PaneId) ?usize {
        for (self.entries, 0..) |entry, index| if (entry != null and entry.?.pane == pane) return index;
        return null;
    }
    fn freeIndex(self: *const Boundary) ?usize {
        for (self.entries, 0..) |entry, index| if (entry == null and (self.reserved_entry == null or self.reserved_entry.? != index)) return index;
        return null;
    }
    fn nextRevision(self: *Boundary) error{RevisionOverflow}!LifecycleRevision {
        self.lifecycle_high_water = std.math.add(u64, self.lifecycle_high_water, 1) catch return error.RevisionOverflow;
        return @fromBackingInt(self.lifecycle_high_water);
    }
    fn clearCandidate(self: *Boundary) void {
        self.candidate_active = false;
        self.admission_phase = .none;
        self.admission_revision = @fromBackingInt(0);
        self.admission_operation_count = 0;
        self.admission_grid_count = 0;
        self.admission_input_count = 0;
        self.admission_registration = null;
        self.reserved_entry = null;
    }
    fn isVisible(self: *const Boundary, pane: PaneId, source: SourceId) bool {
        for (self.visible_members[0..self.visible_member_count]) |member| if (member.pane == pane and member.source == source) return true;
        return false;
    }
    fn setEntryState(self: *Boundary, pane: PaneId, from: EntryState, to: EntryState) error{UnknownPane}!void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const index = self.find(pane) orelse return error.UnknownPane;
        if (self.entries[index].?.state != from) return error.UnknownPane;
        self.entries[index].?.state = to;
        if (to == .retired) {
            self.cursors[index].pending = null;
            self.completions[index] = .empty;
        }
        signal(self.renderer_fd);
    }
};

fn copyVisible(revision: u64, members: []const VisibleMember) VisibleSetRequest {
    var result = VisibleSetRequest{ .revision = revision, .members = undefined, .count = @intCast(members.len) };
    @memcpy(result.members[0..members.len], members);
    return result;
}
fn inputPane(input: TerminalInput) PaneId {
    return switch (input) {
        .key => |v| v.pane,
        .focus => |v| v.pane,
    };
}
fn validPane(pane: PaneId) bool {
    return @backingInt(pane) != 0;
}
fn validSource(source: SourceId) bool {
    return @backingInt(source) != 0;
}
fn validPixels(pixels: PixelSize) bool {
    return pixels.width != 0 and pixels.height != 0;
}
fn validGrid(grid: DerivedGrid, pane: PaneId) bool {
    if (grid.pane != pane or grid.rows == 0 or grid.columns == 0) return false;
    if (grid.rows > 128) return false;
    const cells = std.math.mul(usize, grid.rows, grid.columns) catch return false;
    return cells <= 65_536;
}
const WakePair = struct { first: i32, second: i32 };
const NativeEventfd = struct {
    fn create(flags: u32) usize {
        return linux.eventfd(0, flags);
    }
    fn close(fd: i32) void {
        closeDescriptor(fd);
    }
};
fn createEventfd(comptime Ops: type) error{Signal}!i32 {
    const result = Ops.create(eventfd_flags);
    if (linux.errno(result) != .SUCCESS) return error.Signal;
    return std.math.cast(i32, result) orelse error.Signal;
}
fn createWakePair(comptime Ops: type) error{Signal}!WakePair {
    const first = try createEventfd(Ops);
    errdefer Ops.close(first);
    return .{ .first = first, .second = try createEventfd(Ops) };
}
fn closeDescriptor(fd: i32) void {
    if (std.posix.system.close(fd) != 0) @panic("terminal handoff descriptor cleanup failed");
}
fn signal(fd: i32) void {
    const one: u64 = 1;
    const bytes = std.mem.asBytes(&one);
    while (true) {
        const result = std.posix.system.write(fd, bytes.ptr, bytes.len);
        if (result == bytes.len) return;
        if (result < 0 and std.posix.errno(result) == .INTR) continue;
        if (result < 0 and std.posix.errno(result) == .AGAIN) return;
        @panic("terminal handoff wake failed");
    }
}
fn drain(fd: i32) error{Signal}!void {
    var value: u64 = 0;
    while (true) {
        const count = std.posix.read(fd, std.mem.asBytes(&value)) catch |failure| switch (failure) {
            error.WouldBlock => return,
            else => return error.Signal,
        };
        if (count != @sizeOf(u64)) return error.Signal;
    }
}

fn registerForTest(
    boundary: *Boundary,
    pane: PaneId,
    source: SourceId,
) !AdmittedLifecycle {
    const operations = [_]Lifecycle{.{ .create = .{ .pane = pane, .pixels = .{ .width = 80, .height = 24 } } }};
    const grids = [_]DerivedGrid{.{ .pane = pane, .rows = 1, .columns = 1 }};
    var prepared = try boundary.prepareLifecycle(&operations, &grids, &.{}, .{ .pane = pane, .source = source });
    defer prepared.deinit();
    const revision = try prepared.publishAdmission();
    _ = boundary.takeLifecycleAdmission().?;
    try boundary.completeLifecycleAdmission(revision, .admitted);
    try prepared.commitAdmitted();
    return boundary.takeAdmittedLifecycle().?;
}

test "boundary layout is bounded and contains no payload bank" {
    try std.testing.expectEqual(@as(usize, 55_448), @sizeOf(Boundary));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(Boundary));
}

test "registration input visibility cursor completion and retirement preserve identity" {
    var b = try Boundary.init(std.testing.io, std.testing.allocator);
    defer b.deinit();
    const pane: PaneId = @fromBackingInt(1);
    const source: SourceId = @fromBackingInt(1);
    _ = try registerForTest(&b, pane, source);
    try b.markLive(pane);
    var visible = try b.prepareVisibleSet(1, &.{.{ .pane = pane, .source = source }});
    visible.commit();
    const identity = (try b.cursorPublicationIdentity(pane, source)).?;
    try b.publishCursor(.{ .pane = pane, .source = source, .terminal_sequence = 1, .cursor_revision = 1, .visible_set_revision = identity.visible_set_revision, .lifecycle_revision = identity.lifecycle_revision, .target = .{ .row = 0, .col = 0, .visible = true, .shape = .block, .cursor_color = .{}, .text_color = .{} } });
    try std.testing.expect(b.takeCursor(pane) != null);
    try b.publishCompletion(.{ .pane = pane, .source = source, .lifecycle_revision = identity.lifecycle_revision, .render_sequence = 1, .termination = .{ .code = 0 } });
    const completion = b.takeCompletion().?;
    try std.testing.expect(b.completionIsCurrent(completion));
    var close = try b.prepareLifecycle(&.{.{ .close = pane }}, &.{}, &.{}, null);
    defer close.deinit();
    const close_revision = try close.publishAdmission();
    _ = b.takeLifecycleAdmission().?;
    try b.completeLifecycleAdmission(close_revision, .admitted);
    try close.commitAdmitted();
    try std.testing.expect(b.takeAdmittedLifecycle() != null);
    try std.testing.expect(try b.retireTransfer(pane));
    try b.markRetired(pane);
    const retired = b.takeRetired().?;
    try std.testing.expectEqual(source, retired.source);
    try b.finishRetired(pane);
    try std.testing.expectError(error.UnknownPane, b.markLive(pane));
}

test "lifecycle pressure cancellation frees capacity and signals progress" {
    var b = try Boundary.init(std.testing.io, std.testing.allocator);
    defer b.deinit();
    const pane: PaneId = @fromBackingInt(2);
    const source: SourceId = @fromBackingInt(2);
    var prepared = try b.prepareLifecycle(
        &.{.{ .create = .{ .pane = pane, .pixels = .{ .width = 80, .height = 24 } } }},
        &.{.{ .pane = pane, .rows = 24, .columns = 80 }},
        &.{},
        .{ .pane = pane, .source = source },
    );
    try std.testing.expectEqual(prepared.revision, try prepared.publishAdmission());
    const request = b.takeLifecycleAdmission().?;
    try b.completeLifecycleAdmission(request.revision, .admitted);
    try prepared.commitAdmitted();
    const admitted = b.takeAdmittedLifecycle().?;
    try std.testing.expectEqual(pane, admitted.operation.create.pane);
    try std.testing.expectEqual(@as(u16, 24), admitted.grid.?.rows);
}

test "lifecycle admission rejects mismatched derived ownership transactionally" {
    var b = try Boundary.init(std.testing.io, std.testing.allocator);
    defer b.deinit();
    const pane: PaneId = @fromBackingInt(22);
    try std.testing.expectError(
        error.InvalidPane,
        b.prepareLifecycle(
            &.{.{ .create = .{ .pane = pane, .pixels = .{ .width = 80, .height = 24 } } }},
            &.{.{ .pane = @fromBackingInt(23), .rows = 24, .columns = 80 }},
            &.{},
            .{ .pane = pane, .source = @fromBackingInt(22) },
        ),
    );
    try std.testing.expectEqual(@as(?AdmittedLifecycle, null), b.takeAdmittedLifecycle());
}

test "bounded input pressure preserves order and dequeue signals progress" {
    var b = try Boundary.init(std.testing.io, std.testing.allocator);
    defer b.deinit();
    const pane: PaneId = @fromBackingInt(3);
    const admitted = try registerForTest(&b, pane, @fromBackingInt(3));
    try std.testing.expectEqual(pane, admitted.operation.create.pane);
    for (0..input_limit) |index| try b.publishFocus(
        pane,
        .{ .focus = if (index % 2 == 0) .in else .out },
    );
    try std.testing.expectError(
        error.OperationLimit,
        b.publishFocus(pane, .{ .focus = .in }),
    );
    for (0..input_limit) |index| {
        const input = b.takeInput().?;
        const expected: vt.Terminal.InputEvent = .{
            .focus = if (index % 2 == 0) .in else .out,
        };
        try std.testing.expectEqual(expected, input.focus.event);
    }
}

test "published visibility follows requested prepared committing accepted phases" {
    var b = try Boundary.init(std.testing.io, std.testing.allocator);
    defer b.deinit();
    const pane: PaneId = @fromBackingInt(31);
    const source: SourceId = @fromBackingInt(31);
    _ = try registerForTest(&b, pane, source);
    try b.markLive(pane);
    try b.publishVisibleSet(1, &.{.{ .pane = pane, .source = source }});
    try std.testing.expectEqual(VisibleSetStatus.pending, b.visibleSetStatus(1));
    try std.testing.expectEqual(@as(u64, 1), b.visibleSetRequest().?.revision);
    try std.testing.expectError(
        error.CandidatePending,
        b.publishVisibleSet(2, &.{.{ .pane = pane, .source = source }}),
    );
    try b.completeVisibleSet(1);
    try std.testing.expectEqual(VisibleSetStatus.ready, b.visibleSetStatus(1));
    try std.testing.expectError(
        error.CandidatePending,
        b.publishVisibleSet(2, &.{.{ .pane = pane, .source = source }}),
    );
    try b.claimVisibleSet(1);
    try std.testing.expectError(
        error.CandidatePending,
        b.publishVisibleSet(2, &.{.{ .pane = pane, .source = source }}),
    );
    try b.releaseVisibleSetClaim(1);
    try std.testing.expectEqual(VisibleSetStatus.ready, b.visibleSetStatus(1));
    try b.claimVisibleSet(1);
    b.commitVisibleSet(1);
    const accepted = b.acceptedVisibleSet().?;
    try std.testing.expectEqual(@as(u64, 1), accepted.revision);
    try std.testing.expectEqual(@as(u8, 1), accepted.count);
    try std.testing.expectEqual(pane, accepted.members[0].pane);
    try std.testing.expectEqual(source, accepted.members[0].source);
}

test "stale cursor and completion identities reject" {
    var b = try Boundary.init(std.testing.io, std.testing.allocator);
    defer b.deinit();
    const pane: PaneId = @fromBackingInt(4);
    const source: SourceId = @fromBackingInt(4);
    _ = try registerForTest(&b, pane, source);
    try b.markLive(pane);
    var visible = try b.prepareVisibleSet(1, &.{.{ .pane = pane, .source = source }});
    visible.commit();
    const identity = (try b.cursorPublicationIdentity(pane, source)).?;
    const cursor = CursorPublication{
        .pane = pane,
        .source = source,
        .terminal_sequence = 1,
        .cursor_revision = 1,
        .visible_set_revision = 1,
        .lifecycle_revision = identity.lifecycle_revision,
        .target = .{ .row = 0, .col = 0, .visible = true, .shape = .bar, .cursor_color = .{}, .text_color = .{} },
    };
    try b.publishCursor(cursor);
    try std.testing.expectError(error.CursorRevisionStale, b.publishCursor(cursor));
    try std.testing.expectError(error.LifecycleStale, b.publishCompletion(.{
        .pane = pane,
        .source = source,
        .lifecycle_revision = @fromBackingInt(@backingInt(identity.lifecycle_revision) + 1),
        .render_sequence = 1,
        .termination = .{ .code = 0 },
    }));
}

test "eventfd pair construction closes the first descriptor when the second fails" {
    const Ops = struct {
        var creates: u8 = 0;
        var closed: [2]i32 = undefined;
        var close_count: u8 = 0;

        fn create(_: u32) usize {
            creates += 1;
            if (creates == 1) return 41;
            return @bitCast(-@as(isize, @backingInt(linux.E.MFILE)));
        }

        fn close(fd: i32) void {
            closed[close_count] = fd;
            close_count += 1;
        }
    };
    Ops.creates = 0;
    Ops.close_count = 0;
    try std.testing.expectError(error.Signal, createWakePair(Ops));
    try std.testing.expectEqual(@as(u8, 1), Ops.close_count);
    try std.testing.expectEqual(@as(i32, 41), Ops.closed[0]);
}
