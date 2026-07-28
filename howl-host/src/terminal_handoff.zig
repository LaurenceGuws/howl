//! Owns bounded terminal lifecycle, input, and copied producer transfer facts.

const std = @import("std");
const render = @import("howl_render");
const wayland = @import("howl_wayland");
const vt = @import("howl_vt");
const c = @import("host_c");
const pool_storage = @import("terminal_pool");
const canvas = render.canvas;
const terminal = render.terminal;
const PaneId = render.chrome.PaneId;
const owner_limit: usize = 64;
const operation_limit: usize = 128;
const input_limit: usize = 256;
const lifecycle_batch_limit: usize = 128;
/// Maximum terminal sources admitted by one visible-set transaction.
pub const visible_member_limit: usize = 16;

/// Identifies one exact terminal source required by a visible-set candidate.
pub const VisibleMember = struct {
    /// Identifies the globally non-reused pane.
    pane: PaneId,
    /// Identifies the Composer-issued source owned by that pane.
    source: canvas.SourceId,
};

/// Copies one latest bounded Renderer-owned visible-set request.
pub const VisibleSetRequest = struct {
    /// Identifies a nonzero, monotonically issued candidate.
    revision: u64,
    /// Stores every exact member in caller composition order.
    members: [visible_member_limit]VisibleMember,
    /// Bounds the initialized member prefix.
    count: u8,
};

/// Copies one latest global terminal-font request for runtime coalescing.
pub const FontRequest = struct {
    /// Identifies this request in strict publication order.
    revision: u64,
    /// Selects the bounded terminal content pixel height.
    pixel_height: u16,
};

/// Identifies one never-reused lifecycle admission candidate.
pub const LifecycleRevision = enum(u64) {
    _,
};

/// Copies one runtime-derived terminal grid for an exact pane.
pub const DerivedGrid = struct {
    /// Identifies the pane whose pixel extent produced this grid.
    pane: PaneId,
    /// Records the checked terminal row count.
    rows: u16,
    /// Records the checked terminal column count.
    columns: u16,
};

/// Classifies an exact runtime admission rejection without mutation.
pub const AdmissionRejection = enum {
    invalid_pane,
    unknown_pane,
    duplicate_pane,
    invalid_extent,
    font_capacity,
    terminal_capacity,
    stopping,
};

/// Reports whether an exact visible-set candidate may commit composition.
pub const VisibleSetStatus = enum {
    pending,
    ready,
    stale,
};

/// Copies Host-owned transfer facts used by terminal visible-set classification.
pub const VisibleTransferFact = struct {
    /// Identifies an immutable publication still owned by the pool, if any.
    ready: ?pool_storage.Token,
    /// Records the newest producer revision accepted by Composer.
    accepted_revision: canvas.ProducerRevision,
};

/// Reports fixed pool construction or native wake-descriptor failure.
pub const BoundaryInitError = error{
    ArithmeticOverflow,
    OutOfMemory,
    Signal,
};

/// Reports immutable pool-drain transition failure.
pub const DrainError = pool_storage.TransitionError;

/// Reports one bounded Renderer drainage pass without consuming rejection.
pub const DrainResult = struct {
    /// Counts updates accepted into Composer and released to pool reuse.
    accepted: usize,
    /// Preserves the first exact Composer rejection after restoring ready.
    rejected: ?canvas.Composer.Error,
};

/// Reports stale lifecycle identity or pooled retirement contention.
pub const TransferRetireError = error{UnknownPane} || pool_storage.RetireError;

/// Reports invalid construction limits or allocation failure.
pub const InitError = error{
    InvalidLimits,
    OutOfMemory,
    ArithmeticOverflow,
};

/// Reports producer admission or exact terminal-update production failure.
pub const PublishError = error{
    InvalidContentLimits,
    Pending,
    Retired,
} || terminal.Content.TakeError;

/// Reports concurrent ownership transfer during pane retirement.
pub const RetireError = error{Busy};

const State = enum(u8) {
    free,
    writing,
    ready,
    draining,
    retired,
};

/// Transfers one copied `canvas.ProducerUpdate` between terminal and Renderer.
///
/// Successful initialization performs every allocation. `publish` performs
/// atomic admission before consuming terminal Content. Release/acquire state
/// transitions make copied bytes immutable and visible to exactly one Renderer
/// drain. Retirement may discard a ready update without applying it.
pub const PendingSlot = struct {
    allocator: std.mem.Allocator,
    uploads: []canvas.ResourceUpload,
    removals: []canvas.ResourceRemoval,
    commands: []canvas.Input,
    pixels: []u8,
    upload_count: usize = 0,
    removal_count: usize = 0,
    command_count: usize = 0,
    revision: canvas.ProducerRevision = @fromBackingInt(@intCast(0)),
    state: std.atomic.Value(u8) = .init(@backingInt(State.free)),

    /// Allocates the exact terminal Content transfer capacity transactionally.
    pub fn init(
        allocator: std.mem.Allocator,
        limits: terminal.Content.Limits,
    ) InitError!PendingSlot {
        if (limits.resources_per_update == 0 or limits.commands == 0 or
            limits.upload_bytes == 0)
            return error.InvalidLimits;
        const requested = requiredBytes(limits) catch
            return error.ArithmeticOverflow;
        if (requested == 0) return error.InvalidLimits;
        const uploads = allocator.alloc(
            canvas.ResourceUpload,
            limits.resources_per_update,
        ) catch
            return error.OutOfMemory;
        errdefer allocator.free(uploads);
        const removals = allocator.alloc(
            canvas.ResourceRemoval,
            limits.resources_per_update,
        ) catch
            return error.OutOfMemory;
        errdefer allocator.free(removals);
        const commands = allocator.alloc(canvas.Input, limits.commands) catch
            return error.OutOfMemory;
        errdefer allocator.free(commands);
        const pixels = allocator.alloc(u8, limits.upload_bytes) catch
            return error.OutOfMemory;
        return .{
            .allocator = allocator,
            .uploads = uploads,
            .removals = removals,
            .commands = commands,
            .pixels = pixels,
        };
    }

    /// Releases all copied storage in reverse allocation order.
    pub fn deinit(self: *PendingSlot) void {
        const state = self.loadState(.acquire);
        std.debug.assert(state == .free or state == .retired);
        self.allocator.free(self.pixels);
        self.allocator.free(self.commands);
        self.allocator.free(self.removals);
        self.allocator.free(self.uploads);
        self.* = undefined;
    }

    /// Atomically admits and copies one consumptive terminal Content update.
    ///
    /// Slot admission happens before `takeUpdate`. Pending or retired slots
    /// therefore leave Content untouched. Slot capacity comes from the same
    /// Content limits, making the subsequent copy infallible. A production
    /// failure restores the slot to free while Content performs its own exact
    /// rollback.
    pub fn publish(
        self: *PendingSlot,
        content: *terminal.Content,
        work: *terminal.Content.Work,
        geometry: terminal.Content.Geometry,
    ) PublishError!void {
        try self.reserve();
        try self.publishReserved(content, work, geometry);
    }

    /// Atomically reserves producer ownership before any consumptive projection work.
    pub fn reserve(self: *PendingSlot) error{ Pending, Retired }!void {
        if (self.claim(.free, .writing)) |state| switch (state) {
            .ready, .draining, .writing => return error.Pending,
            .retired => return error.Retired,
            .free => unreachable,
        };
    }

    /// Releases a producer reservation after projection failure without changing bytes.
    pub fn cancelReserved(self: *PendingSlot) void {
        std.debug.assert(self.loadState(.acquire) == .writing);
        self.storeState(.free, .release);
    }

    /// Consumes one Content update only after exact producer reservation.
    pub fn publishReserved(
        self: *PendingSlot,
        content: *terminal.Content,
        work: *terminal.Content.Work,
        geometry: terminal.Content.Geometry,
    ) PublishError!void {
        std.debug.assert(self.loadState(.acquire) == .writing);
        errdefer self.storeState(.free, .release);
        if (content.limits.resources_per_update != self.uploads.len or
            content.limits.commands != self.commands.len or
            content.limits.upload_bytes != self.pixels.len)
            return error.InvalidContentLimits;
        const update = try content.takeUpdate(work, geometry);
        self.copyTaken(update);
        self.storeState(.ready, .release);
    }

    fn copyTaken(self: *PendingSlot, update: canvas.ProducerUpdate) void {
        std.debug.assert(update.uploads.len <= self.uploads.len);
        std.debug.assert(update.removals.len <= self.removals.len);
        std.debug.assert(update.commands.len <= self.commands.len);
        var pixel_offset: usize = 0;
        for (update.uploads, 0..) |upload, index| {
            const bytes = upload.pixels.bytes;
            std.debug.assert(bytes.len <= self.pixels.len - pixel_offset);
            @memcpy(self.pixels[pixel_offset..][0..bytes.len], bytes);
            self.uploads[index] = upload;
            self.uploads[index].pixels.bytes =
                self.pixels[pixel_offset..][0..bytes.len];
            pixel_offset += bytes.len;
        }
        @memcpy(self.removals[0..update.removals.len], update.removals);
        @memcpy(self.commands[0..update.commands.len], update.commands);
        self.upload_count = update.uploads.len;
        self.removal_count = update.removals.len;
        self.command_count = update.commands.len;
        self.revision = update.revision;
    }

    /// Applies one immutable pending update and leaves the slot reusable.
    ///
    /// Acquire ownership observes every producer write. Composer rejection
    /// republishes the same immutable bytes; acceptance releases the slot.
    pub fn drain(
        self: *PendingSlot,
        composer: *canvas.Composer,
        source: canvas.SourceId,
    ) canvas.Composer.Error!bool {
        if (self.claim(.ready, .draining)) |state| switch (state) {
            .free, .writing, .retired => return false,
            .draining => return false,
            .ready => unreachable,
        };
        errdefer self.storeState(.ready, .release);
        try composer.apply(source, self.borrow());
        self.storeState(.free, .release);
        return true;
    }

    /// Retires this pane's transfer ownership, discarding any ready update.
    ///
    /// The caller retires the Composer source separately. A concurrent producer
    /// copy or Renderer drain returns `Busy`; lifecycle coordination must retry
    /// only after that bounded ownership transfer finishes.
    pub fn retire(self: *PendingSlot) RetireError!bool {
        while (true) switch (self.loadState(.acquire)) {
            .free => if (self.claim(.free, .retired) == null) return false,
            .ready => if (self.claim(.ready, .retired) == null) return true,
            .writing, .draining => return error.Busy,
            .retired => return false,
        };
    }

    fn borrow(self: *const PendingSlot) canvas.ProducerUpdate {
        std.debug.assert(self.loadState(.monotonic) == .draining);
        return .{
            .revision = self.revision,
            .uploads = self.uploads[0..self.upload_count],
            .removals = self.removals[0..self.removal_count],
            .commands = self.commands[0..self.command_count],
        };
    }

    fn claim(self: *PendingSlot, from: State, to: State) ?State {
        const actual = self.state.cmpxchgStrong(
            @backingInt(from),
            @backingInt(to),
            .acq_rel,
            .acquire,
        ) orelse return null;
        return @fromBackingInt(@intCast(actual));
    }

    fn loadState(
        self: *const PendingSlot,
        comptime order: std.builtin.AtomicOrder,
    ) State {
        return @fromBackingInt(@intCast(self.state.load(order)));
    }

    fn storeState(
        self: *PendingSlot,
        state: State,
        comptime order: std.builtin.AtomicOrder,
    ) void {
        self.state.store(@backingInt(state), order);
    }
};

fn requiredBytes(
    limits: terminal.Content.Limits,
) error{ArithmeticOverflow}!usize {
    var result = std.math.mul(
        usize,
        limits.resources_per_update,
        @sizeOf(canvas.ResourceUpload),
    ) catch return error.ArithmeticOverflow;
    result = std.math.add(
        usize,
        result,
        std.math.mul(
            usize,
            limits.resources_per_update,
            @sizeOf(canvas.ResourceRemoval),
        ) catch return error.ArithmeticOverflow,
    ) catch return error.ArithmeticOverflow;
    result = std.math.add(
        usize,
        result,
        std.math.mul(
            usize,
            limits.commands,
            @sizeOf(canvas.Input),
        ) catch return error.ArithmeticOverflow,
    ) catch return error.ArithmeticOverflow;
    return std.math.add(usize, result, limits.upload_bytes) catch
        return error.ArithmeticOverflow;
}

/// Copies one terminal-owner lifecycle mutation without visual vocabulary.
pub const Lifecycle = union(enum) {
    /// Constructs one logical terminal from exact Renderer-owned pane pixels.
    create: struct { pane: PaneId, pixels: canvas.Size },
    /// Applies one coherent pane-pixel and PTY/VT geometry transaction.
    resize: struct { pane: PaneId, pixels: canvas.Size },
    /// Retires one logical terminal in reverse ownership order.
    close: PaneId,
};

/// Copies one interpreted unmatched key for one globally live pane.
pub const KeyInput = struct {
    /// Routes the key without borrowing Renderer topology.
    pane: PaneId,
    /// Copies physical identity, causal modifiers, keysym, and bounded UTF-8.
    key: wayland.input.Key,
};

/// Copies canonical focus input or one interpreted key occurrence.
pub const TerminalInput = union(enum) {
    /// Defers key encoding to the terminal owner holding current modes.
    key: KeyInput,
    /// Routes one canonical terminal focus transition.
    focus: struct { pane: PaneId, event: vt.Terminal.InputEvent },
};

/// Supplies the Composer source for one lifecycle create operation.
pub const Registration = struct {
    /// Identifies the globally non-reused pane.
    pane: PaneId,
    /// Identifies the already-registered Composer source.
    source: canvas.SourceId,
};

/// Owns one complete copied lifecycle request during a runtime validation turn.
///
/// No field borrows Boundary or Renderer storage. The value is bounded by the
/// existing lifecycle candidate limits and may remain valid after cancellation.
pub const RuntimeAdmissionCopy = struct {
    /// Identifies the exact candidate that supplied the copied bytes.
    revision: LifecycleRevision,
    /// Copies every candidate lifecycle operation in caller order.
    operations: [lifecycle_batch_limit]Lifecycle = undefined,
    /// Bounds the initialized operation prefix.
    operation_count: u8,
    /// Copies every candidate terminal input in caller order.
    inputs: [2]TerminalInput = undefined,
    /// Bounds the initialized input prefix.
    input_count: u8,
    /// Copies the sole optional registration identity.
    registration: ?Registration,
};

/// Copies the exact result for one lifecycle admission revision.
pub const LifecycleAdmissionResult = union(enum) {
    /// Retains every checked grid in lifecycle-operation order.
    admitted: struct {
        grids: [lifecycle_batch_limit]DerivedGrid = undefined,
        count: u8,
    },
    /// Reports one finite rejection without producer mutation.
    rejected: AdmissionRejection,
};

/// Couples one committed lifecycle operation to its admitted grid sidecar.
pub const AdmittedLifecycle = struct {
    /// Retains the original pixel-authority lifecycle fact.
    operation: Lifecycle,
    /// Exists only for create and resize operations.
    grid: ?DerivedGrid,
};

const EntryState = enum {
    registered,
    live,
    closing,
    retired,
    removing,
};

const Entry = struct {
    pane: PaneId,
    source: canvas.SourceId,
    descriptor_index: u8,
    ready: ?pool_storage.Token = null,
    draining: bool = false,
    accepted_revision: canvas.ProducerRevision = @fromBackingInt(0),
    retry_wake_issued: bool = false,
    pool_active: bool = false,
    pool_retiring: bool = false,
    state: EntryState = .registered,
};

const VisiblePhase = enum {
    requested,
    prepared,
    committing,
};

const LifecycleAdmissionPhase = enum {
    none,
    requested,
    validating,
    admitted,
    rejected,
};

/// Associates one requested source with its actual extracted producer revision.
pub const VisibleRequirement = struct {
    /// Identifies the exact requested pane and source.
    member: VisibleMember,
    /// Identifies the update Composer must accept before reveal.
    revision: canvas.ProducerRevision,
};

const VisibleRequestState = struct {
    request: VisibleSetRequest,
    requirements: [visible_member_limit]VisibleRequirement = undefined,
    requirement_count: u8 = 0,
    phase: VisiblePhase = .requested,
};

const DrainClaim = struct {
    pool: *pool_storage.Pool,
    token: pool_storage.Token,
    active: bool = true,

    fn update(self: *DrainClaim) canvas.ProducerUpdate {
        return self.pool.drainingUpdate(self.token) catch
            @panic("claimed terminal pool block metadata became invalid");
    }

    fn reject(self: *DrainClaim) void {
        self.pool.retryDrain(self.token) catch
            @panic("claimed terminal pool block could not return to ready");
        self.active = false;
    }

    fn complete(self: *DrainClaim) void {
        self.pool.completeDrain(self.token) catch
            @panic("claimed terminal pool block could not complete");
        self.active = false;
    }

    fn deinit(self: *DrainClaim) void {
        if (!self.active) return;
        self.reject();
    }
};

/// Owns fixed terminal lifecycle facts, copied update slots, and directional wakes.
///
/// Renderer registers exact PaneId-to-SourceId mappings and drains ready slots.
/// The terminal thread alone consumes lifecycle operations and publishes slots.
/// Neither wake direction acknowledges presentation or GPU progress.
pub const Boundary = struct {
    io: std.Io,
    limits: terminal.Content.Limits,
    pool: pool_storage.Pool,
    mutex: std.Io.Mutex = .init,
    entries: [owner_limit]?Entry = @splat(null),
    descriptor_issued: [owner_limit]bool = @splat(false),
    operations: [operation_limit]Lifecycle = undefined,
    operation_head: u8 = 0,
    operation_count: u8 = 0,
    reserved_operation_count: u8 = 0,
    inputs: [input_limit]TerminalInput = undefined,
    input_head: u8 = 0,
    input_count: u16 = 0,
    reserved_input_count: u16 = 0,
    lifecycle_candidate_active: bool = false,
    lifecycle_revision_high_water: u64 = 0,
    lifecycle_admission_phase: LifecycleAdmissionPhase = .none,
    lifecycle_admission_revision: LifecycleRevision = @fromBackingInt(0),
    lifecycle_admission_operations: [lifecycle_batch_limit]Lifecycle = undefined,
    lifecycle_admission_operation_count: u8 = 0,
    lifecycle_admission_inputs: [2]TerminalInput = undefined,
    lifecycle_admission_input_count: u8 = 0,
    lifecycle_admission_registration: ?Registration = null,
    lifecycle_admission_result: LifecycleAdmissionResult = undefined,
    operation_grids: [operation_limit]?DerivedGrid = @splat(null),
    operation_font_stable: [operation_limit]bool = @splat(false),
    font_stable_operations: u8 = 0,
    reserved_entry_index: ?u8 = null,
    terminal_fd: i32,
    renderer_fd: i32,
    stopping: bool = false,
    stopped: bool = false,
    failed: bool = false,
    visible_high_water: u64 = 0,
    visible_request: ?VisibleRequestState = null,
    visible_members: [visible_member_limit]VisibleMember = undefined,
    visible_member_count: u8 = 0,
    visible_initialized: bool = false,
    font_request: ?FontRequest = null,
    font_request_high_water: u64 = 0,

    /// Creates directional nonblocking eventfds without allocating pane storage.
    pub fn init(
        io: std.Io,
        allocator: std.mem.Allocator,
        limits: terminal.Content.Limits,
    ) BoundaryInitError!Boundary {
        const terminal_fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
        if (terminal_fd < 0) return error.Signal;
        errdefer closeDescriptor(terminal_fd);
        const renderer_fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
        if (renderer_fd < 0) return error.Signal;
        errdefer closeDescriptor(renderer_fd);
        const pool = try pool_storage.Pool.init(allocator);
        return .{
            .io = io,
            .limits = limits,
            .pool = pool,
            .terminal_fd = terminal_fd,
            .renderer_fd = renderer_fd,
        };
    }

    /// Retires every descriptor and closes both wakes after runtime owners join.
    pub fn deinit(self: *Boundary) void {
        for (&self.entries) |*maybe_entry| if (maybe_entry.*) |*entry| {
            if (entry.pool_active and !entry.pool_retiring)
                self.pool.beginRetire(
                    entry.descriptor_index,
                    entry.pane,
                    entry.source,
                ) catch @panic("terminal pool descriptor cleanup failed");
            if (entry.pool_active)
                self.pool.finishRetire(
                    entry.descriptor_index,
                    entry.pane,
                    entry.source,
                ) catch @panic("terminal pool block remained in transfer during final cleanup");
            maybe_entry.* = null;
        };
        self.pool.deinit();
        closeDescriptor(self.renderer_fd);
        closeDescriptor(self.terminal_fd);
        self.* = undefined;
    }

    /// Registers one never-zero pane and Composer source before topology mutation.
    pub fn register(
        self: *Boundary,
        pane: PaneId,
        source: canvas.SourceId,
        pixels: canvas.Size,
    ) (error{
        InvalidPane,
        DuplicatePane,
        OwnerLimit,
        OperationLimit,
    } || InitError)!void {
        if (@backingInt(pane) == 0 or @backingInt(source) == 0 or
            pixels.width == 0 or pixels.height == 0)
            return error.InvalidPane;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.stopping) return error.OperationLimit;
        if (self.find(pane) != null) return error.DuplicatePane;
        const index = self.freeUnreservedIndex() orelse return error.OwnerLimit;
        if (self.operation_count + self.reserved_operation_count == self.operations.len)
            return error.OperationLimit;
        self.pushReservedLocked(.{ .create = .{ .pane = pane, .pixels = pixels } });
        self.entries[index] = .{
            .pane = pane,
            .source = source,
            .descriptor_index = @intCast(index),
        };
        self.descriptor_issued[index] = true;
        signal(self.terminal_fd);
    }

    /// Handles one Boundary-owned lifecycle candidate until commit or discard.
    ///
    /// Preparation allocates the sole possible new slot and reserves the fixed
    /// lifecycle/input capacity and fills the sole fixed Boundary candidate
    /// bank without exposing any operation to the terminal thread.
    /// `commitAdmitted` is allocation-free but reports concurrent monotonic
    /// shutdown. Deferred `deinit` safely discards an uncommitted candidate and
    /// releases every reservation.
    pub const PreparedLifecycle = struct {
        boundary: *Boundary,
        operation_count: usize,
        input_count: usize,
        revision: LifecycleRevision,
        published: bool = false,
        committed: bool = false,

        /// Publishes one immutable admission request and wakes the runtime.
        pub fn publishAdmission(
            self: *PreparedLifecycle,
        ) error{ Stopping, StaleRevision }!LifecycleRevision {
            if (self.committed or self.published) return error.StaleRevision;
            const boundary = self.boundary;
            boundary.mutex.lockUncancelable(boundary.io);
            defer boundary.mutex.unlock(boundary.io);
            if (boundary.stopping) return error.Stopping;
            if (!boundary.lifecycle_candidate_active or
                boundary.lifecycle_admission_phase != .none)
                return error.StaleRevision;
            boundary.lifecycle_admission_revision = self.revision;
            boundary.lifecycle_admission_phase = .requested;
            self.published = true;
            signal(boundary.terminal_fd);
            return self.revision;
        }

        /// Copies the result for this exact candidate, if Runtime completed it.
        pub fn admissionResult(
            self: *PreparedLifecycle,
        ) ?LifecycleAdmissionResult {
            const boundary = self.boundary;
            boundary.mutex.lockUncancelable(boundary.io);
            defer boundary.mutex.unlock(boundary.io);
            if (!self.published or
                boundary.lifecycle_admission_revision != self.revision)
                return null;
            return switch (boundary.lifecycle_admission_phase) {
                .admitted, .rejected => boundary.lifecycle_admission_result,
                else => null,
            };
        }

        /// Publishes every admitted fact allocation-free, or reports shutdown.
        pub fn commitAdmitted(
            self: *PreparedLifecycle,
        ) error{ Stopping, NotAdmitted, StaleRevision }!void {
            if (self.committed) @panic("terminal lifecycle candidate already completed");
            const boundary = self.boundary;
            boundary.mutex.lockUncancelable(boundary.io);
            defer boundary.mutex.unlock(boundary.io);
            if (boundary.stopping) return error.Stopping;
            if (!boundary.lifecycle_candidate_active or
                boundary.lifecycle_admission_revision != self.revision)
                return error.StaleRevision;
            if (boundary.lifecycle_admission_phase != .admitted)
                return error.NotAdmitted;
            const admitted = boundary.lifecycle_admission_result.admitted;
            std.debug.assert(boundary.reserved_operation_count >= self.operation_count);
            std.debug.assert(boundary.reserved_input_count >= self.input_count);
            if (boundary.lifecycle_admission_registration) |registration| {
                const index = boundary.reserved_entry_index orelse
                    @panic("prepared terminal owner reservation disappeared");
                std.debug.assert(boundary.entries[index] == null);
                boundary.entries[index] = .{
                    .pane = registration.pane,
                    .source = registration.source,
                    .descriptor_index = @intCast(index),
                };
                boundary.descriptor_issued[index] = true;
            }
            boundary.reserved_operation_count -= @intCast(self.operation_count);
            boundary.reserved_input_count -= @intCast(self.input_count);
            var grid_index: usize = 0;
            for (boundary.lifecycle_admission_operations[0..self.operation_count]) |operation| {
                const grid: ?DerivedGrid = switch (operation) {
                    .create, .resize => blk: {
                        std.debug.assert(grid_index < admitted.count);
                        const value = admitted.grids[grid_index];
                        grid_index += 1;
                        break :blk value;
                    },
                    .close => null,
                };
                const tail = (@as(usize, boundary.operation_head) +
                    boundary.operation_count) % boundary.operations.len;
                boundary.operation_grids[tail] = grid;
                boundary.operation_font_stable[tail] = true;
                boundary.pushReservedLocked(operation);
                if (operation == .close) {
                    const index = boundary.find(operation.close) orelse
                        @panic("prepared close owner disappeared");
                    boundary.entries[index].?.state = .closing;
                }
            }
            std.debug.assert(grid_index == admitted.count);
            boundary.font_stable_operations += @intCast(self.operation_count);
            for (boundary.lifecycle_admission_inputs[0..self.input_count]) |input| {
                const tail = (@as(usize, boundary.input_head) + boundary.input_count) %
                    boundary.inputs.len;
                boundary.inputs[tail] = input;
                boundary.input_count += 1;
            }
            boundary.reserved_entry_index = null;
            boundary.lifecycle_candidate_active = false;
            boundary.clearLifecycleAdmissionLocked();
            self.committed = true;
            signal(boundary.terminal_fd);
        }

        /// Releases reservation and new-slot ownership without observable mutation.
        pub fn deinit(self: *PreparedLifecycle) void {
            if (self.committed) return;
            const boundary = self.boundary;
            boundary.mutex.lockUncancelable(boundary.io);
            std.debug.assert(boundary.lifecycle_candidate_active);
            if (boundary.lifecycle_admission_revision == self.revision)
                boundary.clearLifecycleAdmissionLocked();
            boundary.reserved_operation_count -= @intCast(self.operation_count);
            boundary.reserved_input_count -= @intCast(self.input_count);
            boundary.reserved_entry_index = null;
            boundary.lifecycle_candidate_active = false;
            boundary.mutex.unlock(boundary.io);
            self.committed = true;
            signal(boundary.terminal_fd);
        }
    };

    /// Validates and reserves one lifecycle candidate without queue/topology mutation.
    pub fn prepareLifecycle(
        self: *Boundary,
        operations: []const Lifecycle,
        inputs: []const TerminalInput,
        registration: ?Registration,
    ) (error{
        InvalidPane,
        DuplicatePane,
        UnknownPane,
        OwnerLimit,
        OperationLimit,
        CandidatePending,
        Stopping,
        RevisionOverflow,
    } || InitError)!PreparedLifecycle {
        if (operations.len > lifecycle_batch_limit or inputs.len > 2)
            return error.OperationLimit;
        if (registration) |value| {
            if (@backingInt(value.pane) == 0 or @backingInt(value.source) == 0)
                return error.InvalidPane;
        }
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.stopping) return error.Stopping;
        if (self.lifecycle_candidate_active) return error.CandidatePending;
        if (operations.len >
            self.operations.len - self.operation_count - self.reserved_operation_count or
            inputs.len > self.inputs.len - self.input_count - self.reserved_input_count)
            return error.OperationLimit;
        if (registration) |value| {
            if (self.find(value.pane) != null) return error.DuplicatePane;
            if (self.freeUnreservedIndex() == null) return error.OwnerLimit;
        }
        for (operations) |operation| switch (operation) {
            .create => |value| {
                if (registration == null or registration.?.pane != value.pane or
                    value.pixels.width == 0 or value.pixels.height == 0)
                    return error.InvalidPane;
            },
            .resize => |value| {
                if (value.pixels.width == 0 or value.pixels.height == 0)
                    return error.InvalidPane;
                if (self.find(value.pane) == null) return error.UnknownPane;
            },
            .close => |pane| if (self.find(pane) == null) return error.UnknownPane,
        };
        for (inputs) |input| {
            const pane = switch (input) {
                .key => |value| value.pane,
                .focus => |value| value.pane,
            };
            const registered_here = registration != null and registration.?.pane == pane;
            if (!registered_here and self.find(pane) == null) return error.UnknownPane;
        }
        const revision = std.math.add(
            u64,
            self.lifecycle_revision_high_water,
            1,
        ) catch return error.RevisionOverflow;
        const prepared = PreparedLifecycle{
            .boundary = self,
            .operation_count = operations.len,
            .input_count = inputs.len,
            .revision = @fromBackingInt(revision),
        };
        @memcpy(
            self.lifecycle_admission_operations[0..operations.len],
            operations,
        );
        @memcpy(
            self.lifecycle_admission_inputs[0..inputs.len],
            inputs,
        );
        self.lifecycle_admission_operation_count = @intCast(operations.len);
        self.lifecycle_admission_input_count = @intCast(inputs.len);
        self.lifecycle_admission_registration = registration;
        self.reserved_operation_count += @intCast(operations.len);
        self.reserved_input_count += @intCast(inputs.len);
        self.reserved_entry_index = if (registration != null)
            @intCast(self.freeUnreservedIndex().?)
        else
            null;
        self.lifecycle_candidate_active = true;
        self.lifecycle_revision_high_water = revision;
        return prepared;
    }

    /// Preflights replacement capacity after releasing the active candidate.
    ///
    /// Renderer is the sole lifecycle-candidate producer. The terminal thread
    /// may only consume queued facts, so after this check fresh preparation can
    /// lose admission solely to monotonic shutdown.
    pub fn preflightLifecycleReplacement(
        self: *Boundary,
        operation_count: usize,
        input_count: usize,
        needs_registration: bool,
    ) error{ Stopping, OwnerLimit, OperationLimit }!void {
        if (operation_count > lifecycle_batch_limit or input_count > 2)
            return error.OperationLimit;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.stopping) return error.Stopping;
        if (!self.lifecycle_candidate_active) {
            if (operation_count >
                self.operations.len - self.operation_count -
                    self.reserved_operation_count or
                input_count >
                    self.inputs.len - self.input_count -
                        self.reserved_input_count)
                return error.OperationLimit;
            if (needs_registration and self.freeUnreservedIndex() == null)
                return error.OwnerLimit;
            return;
        }
        std.debug.assert(
            self.reserved_operation_count <= self.operations.len,
        );
        std.debug.assert(self.reserved_input_count <= self.inputs.len);
        if (operation_count > self.operations.len - self.operation_count or
            input_count > self.inputs.len - self.input_count)
            return error.OperationLimit;
        if (needs_registration and self.reserved_entry_index == null and
            self.freeUnreservedIndex() == null)
            return error.OwnerLimit;
    }

    /// Queues one exact nonzero pane geometry in caller order.
    pub fn resize(
        self: *Boundary,
        pane: PaneId,
        pixels: canvas.Size,
    ) error{ InvalidPane, UnknownPane, OperationLimit }!void {
        if (pixels.width == 0 or pixels.height == 0) return error.InvalidPane;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.find(pane) == null) return error.UnknownPane;
        try self.pushLocked(.{ .resize = .{ .pane = pane, .pixels = pixels } });
        signal(self.terminal_fd);
    }

    /// Queues exact pane retirement; source removal remains Renderer-owned.
    pub fn close(
        self: *Boundary,
        pane: PaneId,
    ) error{ UnknownPane, OperationLimit }!void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const index = self.find(pane) orelse return error.UnknownPane;
        if (self.entries[index].?.state == .closing) return;
        try self.pushLocked(.{ .close = pane });
        self.entries[index].?.state = .closing;
        signal(self.terminal_fd);
    }

    /// Appends one unmatched focused key without borrowing Wayland storage.
    pub fn publishKey(
        self: *Boundary,
        pane: PaneId,
        key: wayland.input.Key,
    ) error{ UnknownPane, OperationLimit }!void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const index = self.find(pane) orelse return error.UnknownPane;
        const state = self.entries[index].?.state;
        if (state != .registered and state != .live) return error.UnknownPane;
        if (self.input_count + self.reserved_input_count == self.inputs.len)
            return error.OperationLimit;
        const tail = (@as(usize, self.input_head) + self.input_count) %
            self.inputs.len;
        self.inputs[tail] = .{ .key = .{ .pane = pane, .key = key } };
        self.input_count += 1;
        signal(self.terminal_fd);
    }

    /// Stops admission out of band and wakes the terminal owner unconditionally.
    ///
    /// Shutdown cancels every queued lifecycle and input fact. A prepared
    /// candidate retains only its private reservations and slot until its owner
    /// observes `Stopping` and discards it. Repeated calls are idempotent.
    pub fn shutdown(self: *Boundary) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.stopping) return;
        self.stopping = true;
        self.operation_head = 0;
        self.operation_count = 0;
        self.input_head = 0;
        self.input_count = 0;
        signal(self.terminal_fd);
        signal(self.renderer_fd);
    }

    /// Copies the monotonic out-of-band shutdown fact.
    pub fn isStopping(self: *Boundary) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.stopping;
    }

    /// Borrows the terminal-runtime wake descriptor through Boundary lifetime.
    pub fn terminalFd(self: *const Boundary) i32 {
        return self.terminal_fd;
    }

    /// Borrows the Renderer wake descriptor through Boundary lifetime.
    pub fn rendererFd(self: *const Boundary) i32 {
        return self.renderer_fd;
    }

    /// Drains accumulated terminal-runtime wakes.
    pub fn drainTerminalWake(self: *Boundary) error{Signal}!void {
        try drainWake(self.terminal_fd);
    }

    /// Drains accumulated Renderer wakes.
    pub fn drainRendererWake(self: *Boundary) error{Signal}!void {
        try drainWake(self.renderer_fd);
    }

    /// Removes one oldest typed lifecycle operation.
    pub fn takeLifecycle(self: *Boundary) ?Lifecycle {
        const admitted = self.takeAdmittedLifecycle() orelse return null;
        return admitted.operation;
    }

    /// Removes one lifecycle operation with its runtime-admitted grid.
    pub fn takeAdmittedLifecycle(self: *Boundary) ?AdmittedLifecycle {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.operation_count == 0) return null;
        const result = AdmittedLifecycle{
            .operation = self.operations[self.operation_head],
            .grid = self.operation_grids[self.operation_head],
        };
        self.operation_grids[self.operation_head] = null;
        const held_font = self.operation_font_stable[self.operation_head];
        self.operation_font_stable[self.operation_head] = false;
        self.operation_head = @intCast(
            (@as(usize, self.operation_head) + 1) % self.operations.len,
        );
        self.operation_count -= 1;
        if (held_font)
            self.font_stable_operations -= 1;
        return result;
    }

    /// Copies one complete request before Runtime validates outside the mutex.
    pub fn takeLifecycleAdmission(self: *Boundary) ?RuntimeAdmissionCopy {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.lifecycle_admission_phase != .requested) return null;
        var result = RuntimeAdmissionCopy{
            .revision = self.lifecycle_admission_revision,
            .operation_count = self.lifecycle_admission_operation_count,
            .input_count = self.lifecycle_admission_input_count,
            .registration = self.lifecycle_admission_registration,
        };
        @memcpy(
            result.operations[0..result.operation_count],
            self.lifecycle_admission_operations[0..result.operation_count],
        );
        @memcpy(
            result.inputs[0..result.input_count],
            self.lifecycle_admission_inputs[0..result.input_count],
        );
        self.lifecycle_admission_phase = .validating;
        return result;
    }

    /// Publishes the exact result for a still-current validating revision.
    pub fn completeLifecycleAdmission(
        self: *Boundary,
        revision: LifecycleRevision,
        result: LifecycleAdmissionResult,
    ) error{ StaleRevision, CandidatePhase, Stopping }!void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.stopping) return error.Stopping;
        if (self.lifecycle_admission_revision != revision)
            return error.StaleRevision;
        if (self.lifecycle_admission_phase != .validating)
            return error.CandidatePhase;
        switch (result) {
            .admitted => |admitted| {
                var expected: usize = 0;
                for (self.lifecycle_admission_operations[0..self.lifecycle_admission_operation_count]) |operation| switch (operation) {
                    .create, .resize => expected += 1,
                    .close => {},
                };
                if (admitted.count != expected) return error.CandidatePhase;
                var grid_index: usize = 0;
                for (self.lifecycle_admission_operations[0..self.lifecycle_admission_operation_count]) |operation| switch (operation) {
                    .create => |value| {
                        if (admitted.grids[grid_index].pane != value.pane or
                            admitted.grids[grid_index].rows == 0 or
                            admitted.grids[grid_index].columns == 0)
                            return error.CandidatePhase;
                        grid_index += 1;
                    },
                    .resize => |value| {
                        if (admitted.grids[grid_index].pane != value.pane or
                            admitted.grids[grid_index].rows == 0 or
                            admitted.grids[grid_index].columns == 0)
                            return error.CandidatePhase;
                        grid_index += 1;
                    },
                    .close => {},
                };
                self.lifecycle_admission_phase = .admitted;
            },
            .rejected => {
                self.lifecycle_admission_phase = .rejected;
            },
        }
        self.lifecycle_admission_result = result;
        signal(self.renderer_fd);
    }

    /// Reports whether lifecycle admission requires the accepted FontMap.
    pub fn lifecycleFontStable(self: *Boundary) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return switch (self.lifecycle_admission_phase) {
            .requested, .validating, .admitted => true,
            .none, .rejected => self.font_stable_operations != 0,
        };
    }

    /// Removes one oldest terminal input occurrence in O(1).
    pub fn takeInput(self: *Boundary) ?TerminalInput {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.input_count == 0) return null;
        const result = self.inputs[self.input_head];
        self.input_head = @intCast(
            (@as(usize, self.input_head) + 1) % self.inputs.len,
        );
        self.input_count -= 1;
        return result;
    }

    /// Re-signals bounded terminal work left after one runtime turn.
    pub fn rearmTerminalWork(self: *Boundary) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const font_ready = self.font_request != null and
            self.lifecycle_admission_phase != .requested and
            self.lifecycle_admission_phase != .validating and
            self.lifecycle_admission_phase != .admitted and
            self.font_stable_operations == 0;
        if (self.operation_count != 0 or self.input_count != 0 or font_ready)
            signal(self.terminal_fd);
    }

    /// Appends one canonical focus event for an admitted pane.
    pub fn publishFocus(
        self: *Boundary,
        pane: PaneId,
        focus: vt.Terminal.InputEvent,
    ) error{ InvalidPane, UnknownPane, OperationLimit }!void {
        if (std.meta.activeTag(focus) != .focus) return error.InvalidPane;
        try self.pushTerminalInput(.{
            .focus = .{ .pane = pane, .event = focus },
        });
    }

    /// Activates one exact pool descriptor under terminal-thread ownership.
    pub fn activateTransfer(
        self: *Boundary,
        pane: PaneId,
    ) pool_storage.RegisterError!pool_storage.Member {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const index = self.find(pane) orelse return error.InvalidDescriptor;
        const entry = &self.entries[index].?;
        try self.pool.register(
            entry.descriptor_index,
            entry.pane,
            entry.source,
        );
        entry.pool_active = true;
        return .{
            .descriptor_index = entry.descriptor_index,
            .pane_id = entry.pane,
            .source_id = entry.source,
        };
    }

    /// Replaces the latest visible-set request without exposing partial membership.
    pub fn publishVisibleSet(
        self: *Boundary,
        revision: u64,
        members: []const VisibleMember,
    ) (error{
        InvalidCandidateRevision,
        InvalidPane,
        DuplicatePane,
        Stopping,
    })!void {
        if (revision == 0 or members.len > visible_member_limit)
            return error.InvalidCandidateRevision;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.stopping) return error.Stopping;
        if (revision <= self.visible_high_water)
            return error.InvalidCandidateRevision;
        for (members, 0..) |member, member_index| {
            if (@backingInt(member.pane) == 0 or @backingInt(member.source) == 0)
                return error.InvalidPane;
            const index = self.find(member.pane) orelse return error.InvalidPane;
            const entry = self.entries[index].?;
            if (entry.source != member.source or
                (entry.state != .registered and entry.state != .live))
                return error.InvalidPane;
            for (members[0..member_index]) |prior|
                if (prior.pane == member.pane or prior.source == member.source)
                    return error.DuplicatePane;
        }
        if (self.visible_request) |prior| {
            self.pool.cancelGroup(prior.request.revision) catch |failure| switch (failure) {
                error.Stale => {},
            };
        }
        var request = VisibleSetRequest{
            .revision = revision,
            .members = undefined,
            .count = @intCast(members.len),
        };
        @memcpy(request.members[0..members.len], members);
        self.visible_request = .{ .request = request };
        self.visible_high_water = revision;
        signal(self.terminal_fd);
    }

    /// Copies the latest request for exclusive terminal-thread preparation.
    pub fn visibleSetRequest(self: *Boundary) ?VisibleSetRequest {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const state = self.visible_request orelse return null;
        if (state.phase != .requested) return null;
        return state.request;
    }

    /// Copies exact publication and Composer facts for one requested member.
    pub fn visibleTransferFact(
        self: *Boundary,
        revision: u64,
        member: VisibleMember,
    ) error{Stale}!VisibleTransferFact {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const state = self.visible_request orelse return error.Stale;
        if (state.request.revision != revision) return error.Stale;
        const index = self.find(member.pane) orelse return error.Stale;
        const entry = self.entries[index].?;
        if (entry.source != member.source or !entry.pool_active or
            (entry.state != .registered and entry.state != .live))
            return error.Stale;
        return .{
            .ready = entry.ready,
            .accepted_revision = entry.accepted_revision,
        };
    }

    /// Atomically reserves every requested producer requiring fresh extraction.
    pub fn reserveVisibleGroup(
        self: *Boundary,
        revision: u64,
        members: []const pool_storage.Member,
    ) pool_storage.ReserveError!pool_storage.Group {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const state = self.visible_request orelse return error.Stale;
        if (state.request.revision != revision or state.phase != .requested)
            return error.Stale;
        for (members) |member| {
            var requested = false;
            for (state.request.members[0..state.request.count]) |value| {
                if (value.pane == member.pane_id and value.source == member.source_id) {
                    requested = true;
                    break;
                }
            }
            if (!requested) return error.Stale;
            const index = self.find(member.pane_id) orelse return error.Stale;
            const entry = self.entries[index].?;
            if (entry.source != member.source_id or
                entry.descriptor_index != member.descriptor_index or
                !entry.pool_active or entry.pool_retiring or entry.ready != null or
                (entry.state != .registered and entry.state != .live))
                return error.Stale;
        }
        return self.pool.reserveGroup(revision, members);
    }

    /// Marks a completely published visible-set preparation with actual revisions.
    pub fn completeVisibleSet(
        self: *Boundary,
        revision: u64,
        requirements: []const VisibleRequirement,
        group_reserved: bool,
    ) error{ Partial, Stale }!void {
        if (requirements.len > visible_member_limit) return error.Stale;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const state = if (self.visible_request) |*value| value else return error.Stale;
        if (state.request.revision != revision or state.phase != .requested or
            requirements.len != state.request.count)
            return error.Stale;
        for (requirements, 0..) |requirement, index| {
            if (requirement.member.pane != state.request.members[index].pane or
                requirement.member.source != state.request.members[index].source or
                @backingInt(requirement.revision) == 0)
                return error.Stale;
            const entry_index = self.find(requirement.member.pane) orelse
                return error.Stale;
            const entry = self.entries[entry_index].?;
            if (entry.source != requirement.member.source or
                (entry.ready != null and
                    entry.ready.?.producer_revision != requirement.revision) or
                (entry.ready == null and
                    @backingInt(entry.accepted_revision) <
                        @backingInt(requirement.revision)))
                return error.Stale;
        }
        if (group_reserved) try self.pool.completeGroup(revision);
        @memcpy(state.requirements[0..requirements.len], requirements);
        state.requirement_count = @intCast(requirements.len);
        state.phase = .prepared;
        signal(self.renderer_fd);
    }

    /// Releases one incomplete extraction group and cancels its exact request.
    ///
    /// Pool candidate revisions are never reused. Renderer observes the stale
    /// request and may issue a strictly newer candidate for the same desired
    /// visible set.
    pub fn abortVisibleGroup(
        self: *Boundary,
        revision: u64,
    ) error{Stale}!void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const state = self.visible_request orelse return error.Stale;
        if (state.request.revision != revision or state.phase != .requested)
            return error.Stale;
        try self.pool.cancelGroup(revision);
        self.visible_request = null;
        signal(self.renderer_fd);
    }

    /// Reports whether every exact candidate member is accepted by Composer.
    pub fn visibleSetStatus(
        self: *Boundary,
        revision: u64,
    ) VisibleSetStatus {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const state = self.visible_request orelse return .stale;
        if (state.request.revision != revision) return .stale;
        for (state.request.members[0..state.request.count]) |member| {
            const index = self.find(member.pane) orelse return .stale;
            const entry = self.entries[index].?;
            if (entry.source != member.source or
                (entry.state != .registered and entry.state != .live))
                return .stale;
        }
        if (state.phase != .prepared) return .pending;
        for (state.requirements[0..state.requirement_count]) |requirement| {
            const index = self.find(requirement.member.pane) orelse return .stale;
            const entry = self.entries[index].?;
            if (entry.source != requirement.member.source or
                (entry.state != .registered and entry.state != .live))
                return .stale;
            if (@backingInt(entry.accepted_revision) <
                @backingInt(requirement.revision))
                return .pending;
        }
        return .ready;
    }

    /// Exclusively claims one synchronized request for Renderer composition.
    pub fn claimVisibleSet(
        self: *Boundary,
        revision: u64,
    ) error{Stale}!void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const state = if (self.visible_request) |*value| value else return error.Stale;
        if (state.request.revision != revision or state.phase != .prepared)
            return error.Stale;
        for (state.requirements[0..state.requirement_count]) |requirement| {
            const index = self.find(requirement.member.pane) orelse return error.Stale;
            const entry = self.entries[index].?;
            if (entry.source != requirement.member.source or
                (entry.state != .registered and entry.state != .live) or
                @backingInt(entry.accepted_revision) <
                    @backingInt(requirement.revision))
                return error.Stale;
        }
        state.phase = .committing;
    }

    /// Restores a failed Renderer composition claim for exact retry.
    pub fn releaseVisibleSetClaim(
        self: *Boundary,
        revision: u64,
    ) error{Stale}!void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const state = if (self.visible_request) |*value| value else return error.Stale;
        if (state.request.revision != revision or state.phase != .committing)
            return error.Stale;
        state.phase = .prepared;
    }

    /// Retires one synchronized request after successful composition mutation.
    pub fn commitVisibleSet(
        self: *Boundary,
        revision: u64,
    ) error{Stale}!void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const state = self.visible_request orelse return error.Stale;
        if (state.request.revision != revision or state.phase != .committing)
            return error.Stale;
        @memcpy(
            self.visible_members[0..state.request.count],
            state.request.members[0..state.request.count],
        );
        self.visible_member_count = state.request.count;
        self.visible_initialized = true;
        self.visible_request = null;
    }

    /// Reserves one shared block before consumptive terminal update extraction.
    pub fn reserveUpdate(
        self: *Boundary,
        member: pool_storage.Member,
    ) pool_storage.ReserveError!pool_storage.Token {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const index = self.find(member.pane_id) orelse return error.Stale;
        const entry = &self.entries[index].?;
        if (entry.descriptor_index != member.descriptor_index or
            entry.source != member.source_id or
            !entry.pool_active)
            return error.Stale;
        if (entry.state != .registered and entry.state != .live)
            return error.Stale;
        if (entry.pool_retiring) return error.Stale;
        if (entry.ready != null) return error.Busy;
        if (self.visible_request != null) return error.GroupPriority;
        var visible = false;
        for (self.visible_members[0..self.visible_member_count]) |value| {
            if (value.pane == member.pane_id and value.source == member.source_id) {
                visible = true;
                break;
            }
        }
        if (self.visible_initialized and !visible) return error.GroupPriority;
        return self.pool.reserve(member);
    }

    /// Cancels one reserved block after producer construction failure.
    pub fn cancelUpdate(
        self: *Boundary,
        token: pool_storage.Token,
    ) pool_storage.TransitionError!void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        try self.pool.cancel(token);
    }

    /// Copies canonical Canvas facts and release-publishes immutable ownership.
    pub fn publishUpdate(
        self: *Boundary,
        token: pool_storage.Token,
        update: canvas.ProducerUpdate,
    ) pool_storage.PublishError!void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const index = self.find(token.pane_id) orelse return error.Stale;
        const entry = &self.entries[index].?;
        if (entry.descriptor_index != token.descriptor_index or
            entry.source != token.source_id or !entry.pool_active or
            (entry.state != .registered and entry.state != .live) or
            entry.pool_retiring or entry.ready != null)
            return error.Stale;
        const published = try self.pool.publishUpdate(token, update);
        entry.ready = published;
        entry.retry_wake_issued = false;
    }

    /// Copies one admitted Composer source for an exact live or pending pane.
    pub fn sourceFor(self: *Boundary, pane: PaneId) ?canvas.SourceId {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const index = self.find(pane) orelse return null;
        return self.entries[index].?.source;
    }

    /// Applies every pooled immutable update to its exact Composer source.
    pub fn drainReady(
        self: *Boundary,
        composer: *canvas.Composer,
    ) DrainError!DrainResult {
        var tokens: [owner_limit]pool_storage.Token = undefined;
        var count: usize = 0;
        self.mutex.lockUncancelable(self.io);
        for (&self.entries) |*maybe_entry| {
            const entry = if (maybe_entry.*) |*value| value else continue;
            if (entry.state == .retired or entry.state == .removing)
                continue;
            if (entry.ready == null) continue;
            tokens[count] = entry.ready.?;
            count += 1;
        }
        self.mutex.unlock(self.io);
        var drained: usize = 0;
        var rejected: ?canvas.Composer.Error = null;
        for (tokens[0..count]) |token| {
            self.pool.beginDrain(token) catch |failure| switch (failure) {
                error.Busy, error.Stale => continue,
                else => return failure,
            };
            self.mutex.lockUncancelable(self.io);
            if (self.find(token.pane_id)) |index| self.entries[index].?.draining = true;
            self.mutex.unlock(self.io);
            var claim = DrainClaim{ .pool = &self.pool, .token = token };
            defer claim.deinit();
            const update = claim.update();
            composer.apply(token.source_id, update) catch |failure| {
                claim.reject();
                self.mutex.lockUncancelable(self.io);
                if (self.find(token.pane_id)) |index| {
                    const entry = &self.entries[index].?;
                    entry.draining = false;
                    if (entry.ready != null and
                        entry.ready.?.reservation_id == token.reservation_id and
                        !entry.retry_wake_issued)
                    {
                        entry.retry_wake_issued = true;
                        signal(self.renderer_fd);
                    }
                }
                self.mutex.unlock(self.io);
                if (rejected == null) rejected = failure;
                continue;
            };
            claim.complete();
            self.mutex.lockUncancelable(self.io);
            if (self.find(token.pane_id)) |index| {
                const entry = &self.entries[index].?;
                entry.draining = false;
                if (entry.ready != null and
                    entry.ready.?.reservation_id == token.reservation_id)
                {
                    entry.ready = null;
                    entry.retry_wake_issued = false;
                    entry.accepted_revision = token.producer_revision;
                }
            }
            self.mutex.unlock(self.io);
            drained += 1;
        }
        if (drained != 0) self.publishDrained();
        return .{ .accepted = drained, .rejected = rejected };
    }

    /// Attempts terminal-side pooled descriptor retirement for one closing pane.
    ///
    /// A concurrent producer copy or Renderer drain returns false without
    /// changing entry or slot state; the terminal runtime retries after the
    /// directional wake. Success retires the slot exactly once.
    pub fn retireTransfer(
        self: *Boundary,
        pane: PaneId,
    ) TransferRetireError!bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const index = self.find(pane) orelse return error.UnknownPane;
        const entry = &self.entries[index].?;
        if (entry.state != .closing) return error.UnknownPane;
        if (entry.draining) return false;
        if (!entry.pool_retiring) {
            try self.pool.beginRetire(
                entry.descriptor_index,
                entry.pane,
                entry.source,
            );
            entry.pool_retiring = true;
        }
        self.pool.finishRetire(
            entry.descriptor_index,
            entry.pane,
            entry.source,
        ) catch |failure| switch (failure) {
            error.Busy => return false,
            else => return failure,
        };
        entry.ready = null;
        entry.draining = false;
        entry.retry_wake_issued = false;
        return true;
    }

    /// Records successful logical-owner construction and wakes Renderer.
    pub fn markLive(self: *Boundary, pane: PaneId) error{UnknownPane}!void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const index = self.find(pane) orelse return error.UnknownPane;
        if (self.entries[index].?.state != .registered) return error.UnknownPane;
        self.entries[index].?.state = .live;
        signal(self.renderer_fd);
    }

    /// Records completed logical-owner retirement for Renderer source removal.
    pub fn markRetired(self: *Boundary, pane: PaneId) error{UnknownPane}!void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const index = self.find(pane) orelse return error.UnknownPane;
        if (self.entries[index].?.state != .closing) return error.UnknownPane;
        self.entries[index].?.state = .retired;
        signal(self.renderer_fd);
    }

    /// Transfers one retired PaneId-to-SourceId mapping to Renderer.
    pub fn takeRetired(self: *Boundary) ?struct { pane: PaneId, source: canvas.SourceId } {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        for (&self.entries) |*maybe_entry| {
            const entry = if (maybe_entry.*) |*value| value else continue;
            if (entry.state != .retired) continue;
            entry.state = .removing;
            return .{ .pane = entry.pane, .source = entry.source };
        }
        return null;
    }

    /// Releases one descriptor entry after Renderer removes its Composer source.
    pub fn finishRetired(
        self: *Boundary,
        pane: PaneId,
    ) error{UnknownPane}!void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const index = self.find(pane) orelse return error.UnknownPane;
        const entry = &self.entries[index].?;
        if (entry.state != .removing) return error.UnknownPane;
        self.entries[index] = null;
    }

    /// Wakes Renderer after a slot transitions to ready.
    pub fn publishReady(self: *Boundary) void {
        signal(self.renderer_fd);
    }

    /// Wakes terminal runtime after Renderer frees one or more slots.
    pub fn publishDrained(self: *Boundary) void {
        signal(self.terminal_fd);
    }

    /// Replaces the latest bounded terminal-font request without consuming
    /// lifecycle-ring capacity; the runtime observes it on its next wake.
    pub fn requestFontSize(self: *Boundary, pixel_height: u16) error{ InvalidFontSize, Stopping, RevisionOverflow }!void {
        if (pixel_height < 8 or pixel_height > 72) return error.InvalidFontSize;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.stopping) return error.Stopping;
        const revision = std.math.add(u64, self.font_request_high_water, 1) catch
            return error.RevisionOverflow;
        self.font_request_high_water = revision;
        self.font_request = .{ .revision = revision, .pixel_height = pixel_height };
        signal(self.terminal_fd);
    }

    /// Takes the newest request exactly once for terminal-thread preparation.
    pub fn takeFontRequest(self: *Boundary) ?FontRequest {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const request = self.font_request;
        self.font_request = null;
        return request;
    }

    /// Reports whether no producer-owned ready block still contains old-font
    /// bytes. Renderer drainage remains the normal owner of draining blocks.
    pub fn fontQuiescent(self: *Boundary) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        for (self.entries) |entry| {
            if (entry) |value| if (value.ready != null or value.draining) return false;
        }
        return true;
    }

    /// Records terminal-thread retirement and wakes Renderer.
    pub fn markStopped(self: *Boundary, failed: bool) void {
        self.mutex.lockUncancelable(self.io);
        self.stopped = true;
        self.failed = self.failed or failed;
        self.mutex.unlock(self.io);
        signal(self.renderer_fd);
    }

    /// Copies terminal-thread retirement facts.
    pub fn status(self: *Boundary) struct { stopped: bool, failed: bool } {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return .{ .stopped = self.stopped, .failed = self.failed };
    }

    fn pushLocked(self: *Boundary, operation: Lifecycle) error{OperationLimit}!void {
        if (self.operation_count + self.reserved_operation_count == self.operations.len)
            return error.OperationLimit;
        self.pushReservedLocked(operation);
    }

    fn clearLifecycleAdmissionLocked(self: *Boundary) void {
        self.lifecycle_admission_phase = .none;
        self.lifecycle_admission_revision = @fromBackingInt(0);
        self.lifecycle_admission_operation_count = 0;
        self.lifecycle_admission_input_count = 0;
        self.lifecycle_admission_registration = null;
    }

    fn pushReservedLocked(self: *Boundary, operation: Lifecycle) void {
        std.debug.assert(self.operation_count < self.operations.len);
        const tail = (@as(usize, self.operation_head) + self.operation_count) %
            self.operations.len;
        self.operations[tail] = operation;
        self.operation_count += 1;
    }

    fn pushTerminalInput(
        self: *Boundary,
        input: TerminalInput,
    ) error{ UnknownPane, OperationLimit }!void {
        const pane = switch (input) {
            .key => |value| value.pane,
            .focus => |value| value.pane,
        };
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const index = self.find(pane) orelse return error.UnknownPane;
        const state = self.entries[index].?.state;
        if (state != .registered and state != .live) return error.UnknownPane;
        if (self.input_count + self.reserved_input_count == self.inputs.len)
            return error.OperationLimit;
        const tail = (@as(usize, self.input_head) + self.input_count) %
            self.inputs.len;
        self.inputs[tail] = input;
        self.input_count += 1;
        signal(self.terminal_fd);
    }

    fn find(self: *const Boundary, pane: PaneId) ?usize {
        for (self.entries, 0..) |entry, index|
            if (entry != null and entry.?.pane == pane) return index;
        return null;
    }

    fn freeUnreservedIndex(self: *const Boundary) ?usize {
        for (self.entries, 0..) |entry, index| {
            const reserved = if (self.reserved_entry_index) |value|
                @as(usize, value) == index
            else
                false;
            if (entry == null and !reserved and !self.descriptor_issued[index])
                return index;
        }
        return null;
    }
};

fn closeDescriptor(descriptor: i32) void {
    if (c.close(descriptor) != 0) @panic("terminal boundary descriptor cleanup failed");
}

fn signal(descriptor: i32) void {
    var value: u64 = 1;
    while (true) {
        const result = c.write(descriptor, &value, @sizeOf(u64));
        if (result == @sizeOf(u64)) return;
        if (result < 0 and std.c.errno(result) == .INTR) continue;
        if (result < 0 and std.c.errno(result) == .AGAIN) return;
        @panic("eventfd write violated the live terminal Boundary invariant");
    }
}

fn drainWake(descriptor: i32) error{Signal}!void {
    var value: u64 = 0;
    while (true) {
        const result = c.read(descriptor, &value, @sizeOf(u64));
        if (result == @sizeOf(u64)) continue;
        if (result < 0 and std.c.errno(result) == .INTR) continue;
        if (result < 0 and std.c.errno(result) == .AGAIN) return;
        return error.Signal;
    }
}

test "terminal boundary admits typed lifecycle and directional wakes" {
    var boundary = try Boundary.init(
        std.testing.io,
        std.testing.allocator,
        testLimits(1, 1, 4),
    );
    defer boundary.deinit();
    const pane: PaneId = @fromBackingInt(@intCast(1));
    const source: canvas.SourceId = @fromBackingInt(@intCast(1));
    try boundary.register(pane, source, .{ .width = 16, .height = 16 });
    try boundary.drainTerminalWake();
    try std.testing.expectEqual(
        Lifecycle{ .create = .{ .pane = pane, .pixels = .{ .width = 16, .height = 16 } } },
        boundary.takeLifecycle().?,
    );
    try std.testing.expectError(
        error.DuplicatePane,
        boundary.register(pane, source, .{ .width = 16, .height = 16 }),
    );
    const invalid_pane: PaneId = @fromBackingInt(2);
    const invalid_source: canvas.SourceId = @fromBackingInt(2);
    try std.testing.expectError(
        error.InvalidPane,
        boundary.register(invalid_pane, invalid_source, .{ .width = 0, .height = 16 }),
    );
    try boundary.markLive(pane);
    try boundary.drainRendererWake();
    try boundary.resize(pane, .{ .width = 16, .height = 12 });
    try std.testing.expectError(
        error.InvalidPane,
        boundary.resize(pane, .{ .width = 16, .height = 0 }),
    );
    try boundary.close(pane);
    try boundary.drainTerminalWake();
    try std.testing.expectEqual(
        Lifecycle{ .resize = .{ .pane = pane, .pixels = .{ .width = 16, .height = 12 } } },
        boundary.takeLifecycle().?,
    );
    try std.testing.expectEqual(Lifecycle{ .close = pane }, boundary.takeLifecycle().?);
    try std.testing.expect(boundary.takeLifecycle() == null);
}

test "prepared lifecycle discard is byte-silent and commit publishes once" {
    var boundary = try Boundary.init(
        std.testing.io,
        std.testing.allocator,
        testLimits(1, 1, 4),
    );
    defer boundary.deinit();
    const pane: PaneId = @fromBackingInt(@intCast(31));
    const source: canvas.SourceId = @fromBackingInt(@intCast(41));
    const operations = [_]Lifecycle{.{ .create = .{
        .pane = pane,
        .pixels = .{ .width = 16, .height = 16 },
    } }};
    {
        var candidate = try boundary.prepareLifecycle(
            &operations,
            &.{},
            .{ .pane = pane, .source = source },
        );
        candidate.deinit();
    }
    try std.testing.expect(boundary.takeLifecycle() == null);
    try std.testing.expect(boundary.sourceFor(pane) == null);

    var candidate = try boundary.prepareLifecycle(
        &operations,
        &.{},
        .{ .pane = pane, .source = source },
    );
    defer candidate.deinit();
    try std.testing.expectError(
        error.CandidatePending,
        boundary.prepareLifecycle(&operations, &.{}, .{
            .pane = pane,
            .source = source,
        }),
    );
    try admitTestCandidate(&candidate);
    try std.testing.expectEqual(operations[0], boundary.takeLifecycle().?);
    try std.testing.expect(boundary.takeLifecycle() == null);
    try std.testing.expectEqual(source, boundary.sourceFor(pane).?);
}

test "shutdown respects lifecycle reservation and cancels candidate without panic" {
    var boundary = try Boundary.init(
        std.testing.io,
        std.testing.allocator,
        testLimits(1, 1, 4),
    );
    defer boundary.deinit();
    const pane: PaneId = @fromBackingInt(@intCast(33));
    const source: canvas.SourceId = @fromBackingInt(@intCast(43));
    var operations: [lifecycle_batch_limit]Lifecycle = undefined;
    for (&operations) |*operation| operation.* = .{ .create = .{
        .pane = pane,
        .pixels = .{ .width = 1, .height = 1 },
    } };
    const inputs = [_]TerminalInput{
        .{ .focus = .{ .pane = pane, .event = .{ .focus = .in } } },
        .{ .focus = .{ .pane = pane, .event = .{ .focus = .out } } },
    };
    var candidate = try boundary.prepareLifecycle(
        &operations,
        &inputs,
        .{ .pane = pane, .source = source },
    );
    defer candidate.deinit();
    try std.testing.expectEqual(
        @as(u8, lifecycle_batch_limit),
        boundary.reserved_operation_count,
    );
    try std.testing.expectEqual(@as(u16, inputs.len), boundary.reserved_input_count);
    boundary.shutdown();
    boundary.shutdown();
    try std.testing.expect(boundary.isStopping());
    var wake = std.posix.pollfd{
        .fd = boundary.terminalFd(),
        .events = std.posix.POLL.IN,
        .revents = 0,
    };
    try std.testing.expectEqual(
        @as(usize, 1),
        @as(usize, @intCast(try std.posix.poll((&wake)[0..1], 0))),
    );
    try boundary.drainTerminalWake();
    try std.testing.expectError(error.Stopping, candidate.commitAdmitted());
    try std.testing.expect(boundary.sourceFor(pane) == null);
    try std.testing.expect(boundary.takeLifecycle() == null);
    try std.testing.expect(boundary.takeInput() == null);
    candidate.deinit();
    try std.testing.expectEqual(@as(u8, 0), boundary.reserved_operation_count);
    try std.testing.expectEqual(@as(u16, 0), boundary.reserved_input_count);
    try std.testing.expect(boundary.reserved_entry_index == null);
    try std.testing.expectError(
        error.Stopping,
        boundary.prepareLifecycle(&operations, &inputs, .{
            .pane = pane,
            .source = source,
        }),
    );
    try std.testing.expectError(
        error.OperationLimit,
        boundary.register(pane, source, .{ .width = 1, .height = 1 }),
    );
}

test "lifecycle admission cancellation rejects stale validation and never reuses revision" {
    var boundary = try Boundary.init(
        std.testing.io,
        std.testing.allocator,
        testLimits(4, 4, 16),
    );
    defer boundary.deinit();
    const pane: PaneId = @fromBackingInt(41);
    const source: canvas.SourceId = @fromBackingInt(51);
    const operations = [_]Lifecycle{.{ .create = .{
        .pane = pane,
        .pixels = .{ .width = 17, .height = 19 },
    } }};
    var first = try boundary.prepareLifecycle(
        &operations,
        &.{},
        .{ .pane = pane, .source = source },
    );
    const first_revision = try first.publishAdmission();
    const copied = boundary.takeLifecycleAdmission().?;
    try std.testing.expectEqual(first_revision, copied.revision);
    first.deinit();
    try std.testing.expect(!boundary.lifecycle_candidate_active);
    try std.testing.expectEqual(@as(u8, 0), boundary.reserved_operation_count);
    try std.testing.expectError(
        error.StaleRevision,
        boundary.completeLifecycleAdmission(
            copied.revision,
            .{ .admitted = .{ .count = 1, .grids = blk: {
                var grids: [lifecycle_batch_limit]DerivedGrid = undefined;
                grids[0] = .{ .pane = pane, .rows = 1, .columns = 1 };
                break :blk grids;
            } } },
        ),
    );

    var second = try boundary.prepareLifecycle(
        &operations,
        &.{},
        .{ .pane = pane, .source = source },
    );
    defer second.deinit();
    const second_revision = try second.publishAdmission();
    try std.testing.expect(
        @backingInt(second_revision) > @backingInt(first_revision),
    );
    try std.testing.expectError(
        error.StaleRevision,
        boundary.completeLifecycleAdmission(
            copied.revision,
            .{ .rejected = .terminal_capacity },
        ),
    );
    try std.testing.expect(boundary.takeLifecycle() == null);
}

test "lifecycle admission holds fonts while ordinary input remains bounded" {
    var boundary = try Boundary.init(
        std.testing.io,
        std.testing.allocator,
        testLimits(4, 4, 16),
    );
    defer boundary.deinit();
    const pane: PaneId = @fromBackingInt(61);
    const source: canvas.SourceId = @fromBackingInt(71);
    try boundary.register(pane, source, .{ .width = 8, .height = 8 });
    try std.testing.expect(boundary.takeLifecycle().? == .create);
    try boundary.markLive(pane);
    const operations = [_]Lifecycle{.{ .resize = .{
        .pane = pane,
        .pixels = .{ .width = 9, .height = 8 },
    } }};
    var candidate = try boundary.prepareLifecycle(&operations, &.{}, null);
    defer candidate.deinit();
    try std.testing.expectEqual(
        candidate.revision,
        try candidate.publishAdmission(),
    );
    try std.testing.expect(boundary.lifecycleFontStable());
    try boundary.requestFontSize(17);
    try boundary.requestFontSize(18);
    const key = wayland.input.Key{
        .keycode = 30,
        .time = 1,
        .state = .pressed,
        .serial = 2,
        .modifiers = .{
            .serial = 3,
            .depressed = 0,
            .latched = 0,
            .locked = 0,
            .group = 0,
        },
        .semantic_modifiers = .{},
        .keysym = @fromBackingInt('a'),
        .text_len = 1,
        .text = .{'a'} ++ @as(
            [wayland.input.key_text_limit - 1]u8,
            @splat(0),
        ),
    };
    try boundary.publishKey(pane, key);
    try std.testing.expectEqual(pane, boundary.takeInput().?.key.pane);
    candidate.deinit();
    try std.testing.expect(!boundary.lifecycleFontStable());
    const font = boundary.takeFontRequest().?;
    try std.testing.expectEqual(@as(u16, 18), font.pixel_height);
}

test "closing transfer waits for Renderer draining ownership" {
    var boundary = try Boundary.init(
        std.testing.io,
        std.testing.allocator,
        testLimits(1, 1, 4),
    );
    defer boundary.deinit();
    const pane: PaneId = @fromBackingInt(@intCast(32));
    const source: canvas.SourceId = @fromBackingInt(@intCast(42));
    try boundary.register(pane, source, .{ .width = 1, .height = 1 });
    try std.testing.expect(std.meta.activeTag(boundary.takeLifecycle().?) == .create);
    const member = try boundary.activateTransfer(pane);
    const reserved = try boundary.reserveUpdate(member);
    try boundary.publishUpdate(reserved, .{
        .revision = @fromBackingInt(@intCast(1)),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{},
    });
    try boundary.close(pane);
    try std.testing.expect(std.meta.activeTag(boundary.takeLifecycle().?) == .close);
    const ready = boundary.entries[0].?.ready.?;
    try boundary.pool.beginDrain(ready);
    try std.testing.expect(!try boundary.retireTransfer(pane));
    try boundary.pool.completeDrain(ready);
    try std.testing.expect(try boundary.retireTransfer(pane));
    try std.testing.expectError(error.Stale, boundary.retireTransfer(pane));
    try boundary.markRetired(pane);
    try std.testing.expectEqual(pane, boundary.takeRetired().?.pane);
    try boundary.finishRetired(pane);
}

test "pooled publication copies bytes retries rejection and releases acceptance" {
    var boundary = try Boundary.init(
        std.testing.io,
        std.testing.allocator,
        testLimits(4, 4, 16),
    );
    defer boundary.deinit();
    const pane: PaneId = @fromBackingInt(@intCast(33));
    const source: canvas.SourceId = @fromBackingInt(@intCast(1));
    try boundary.register(pane, source, .{ .width = 1, .height = 1 });
    try std.testing.expect(
        std.meta.activeTag(boundary.takeLifecycle().?) == .create,
    );
    const member = try boundary.activateTransfer(pane);
    var pixels = [_]u8{ 1, 2, 3, 4 };
    const upload = canvas.ResourceUpload{
        .resource = .{
            .resource = try canvas.ResourceId.local(1),
            .generation = @fromBackingInt(@intCast(1)),
        },
        .format = .alpha8,
        .pixels = .{
            .bytes = &pixels,
            .width = 2,
            .height = 2,
            .stride = 2,
        },
    };
    const commands = [_]canvas.Input{
        .{ .solid = .{
            .rect = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
            .clip = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
            .color = .{ .r = 1, .g = 2, .b = 3, .a = 255 },
        } },
        .{ .solid = .{
            .rect = .{ .x = 1, .y = 0, .width = 1, .height = 1 },
            .clip = .{ .x = 1, .y = 0, .width = 1, .height = 1 },
            .color = .{ .r = 4, .g = 5, .b = 6, .a = 255 },
        } },
    };
    const reserved = try boundary.reserveUpdate(member);
    try boundary.publishUpdate(reserved, .{
        .revision = @fromBackingInt(@intCast(1)),
        .uploads = &.{upload},
        .removals = &.{},
        .commands = &commands,
    });
    pixels = @splat(9);
    const ready = boundary.entries[0].?.ready.?;
    try boundary.pool.beginDrain(ready);
    var abandoned_claim = DrainClaim{
        .pool = &boundary.pool,
        .token = ready,
    };
    const borrowed = abandoned_claim.update();
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, borrowed.uploads[0].pixels.bytes);
    abandoned_claim.deinit();
    try boundary.pool.beginDrain(ready);
    try boundary.pool.retryDrain(ready);

    var narrow = try canvas.Composer.init(std.testing.allocator, .{
        .sources = 1,
        .retained_resources = 4,
        .retained_commands = 1,
        .retained_pixel_bytes = 16,
        .composition_sources = 1,
        .candidate_resources = 4,
        .candidate_commands = 1,
        .candidate_pixel_bytes = 16,
    });
    defer narrow.deinit();
    try std.testing.expectEqual(source, try narrow.registerSource());
    const rejected = try boundary.drainReady(&narrow);
    try std.testing.expectEqual(@as(usize, 0), rejected.accepted);
    try std.testing.expectEqual(
        @as(?canvas.Composer.Error, error.CommandLimit),
        rejected.rejected,
    );
    var retry_wake = std.posix.pollfd{
        .fd = boundary.rendererFd(),
        .events = std.posix.POLL.IN,
        .revents = 0,
    };
    try std.testing.expectEqual(
        @as(usize, 1),
        @as(usize, @intCast(try std.posix.poll((&retry_wake)[0..1], 0))),
    );
    try boundary.drainRendererWake();
    try boundary.pool.beginDrain(ready);
    try boundary.pool.retryDrain(ready);

    var accepted = try canvas.Composer.init(std.testing.allocator, .{
        .sources = 1,
        .retained_resources = 4,
        .retained_commands = 4,
        .retained_pixel_bytes = 16,
        .composition_sources = 1,
        .candidate_resources = 4,
        .candidate_commands = 4,
        .candidate_pixel_bytes = 16,
    });
    defer accepted.deinit();
    try std.testing.expectEqual(source, try accepted.registerSource());
    const resize_operations = [_]Lifecycle{.{ .resize = .{
        .pane = pane,
        .pixels = .{ .width = 2, .height = 1 },
    } }};
    var lifecycle = try boundary.prepareLifecycle(
        &resize_operations,
        &.{},
        null,
    );
    defer lifecycle.deinit();
    try std.testing.expectEqual(
        lifecycle.revision,
        try lifecycle.publishAdmission(),
    );
    const accepted_result = try boundary.drainReady(&accepted);
    try std.testing.expectEqual(@as(usize, 1), accepted_result.accepted);
    try std.testing.expect(accepted_result.rejected == null);
    try std.testing.expect(boundary.entries[0].?.ready == null);

    try boundary.close(pane);
    try std.testing.expect(
        std.meta.activeTag(boundary.takeLifecycle().?) == .close,
    );
    try std.testing.expect(try boundary.retireTransfer(pane));
    try boundary.markRetired(pane);
    try std.testing.expectEqual(pane, boundary.takeRetired().?.pane);
    try boundary.finishRetired(pane);
}

test "latest visible set waits for exact Composer accepted revisions" {
    var boundary = try Boundary.init(
        std.testing.io,
        std.testing.allocator,
        testLimits(4, 4, 16),
    );
    defer boundary.deinit();
    const pane: PaneId = @fromBackingInt(50);
    const source: canvas.SourceId = @fromBackingInt(1);
    try boundary.register(pane, source, .{ .width = 1, .height = 1 });
    const created = boundary.takeLifecycle().?;
    try std.testing.expect(std.meta.activeTag(created) == .create);
    const pooled = try boundary.activateTransfer(pane);
    const member = VisibleMember{ .pane = pane, .source = source };
    try boundary.publishVisibleSet(1, &.{member});
    const request = boundary.visibleSetRequest().?;
    try std.testing.expectEqual(@as(u64, 1), request.revision);
    const group = try boundary.reserveVisibleGroup(1, &.{pooled});
    const commands = [_]canvas.Input{
        .{ .solid = .{
            .rect = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
            .clip = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
            .color = .{ .r = 1, .g = 2, .b = 3, .a = 255 },
        } },
        .{ .solid = .{
            .rect = .{ .x = 1, .y = 0, .width = 1, .height = 1 },
            .clip = .{ .x = 1, .y = 0, .width = 1, .height = 1 },
            .color = .{ .r = 4, .g = 5, .b = 6, .a = 255 },
        } },
    };
    try boundary.publishUpdate(group.tokens[0], .{
        .revision = @fromBackingInt(7),
        .uploads = &.{},
        .removals = &.{},
        .commands = &commands,
    });
    try boundary.completeVisibleSet(1, &.{.{
        .member = member,
        .revision = @fromBackingInt(7),
    }}, true);
    try std.testing.expectEqual(VisibleSetStatus.pending, boundary.visibleSetStatus(1));

    var narrow = try canvas.Composer.init(std.testing.allocator, .{
        .sources = 1,
        .retained_resources = 4,
        .retained_commands = 1,
        .retained_pixel_bytes = 16,
        .composition_sources = 1,
        .candidate_resources = 4,
        .candidate_commands = 1,
        .candidate_pixel_bytes = 16,
    });
    defer narrow.deinit();
    try std.testing.expectEqual(source, try narrow.registerSource());
    const rejected = try boundary.drainReady(&narrow);
    try std.testing.expectEqual(@as(usize, 0), rejected.accepted);
    try std.testing.expectEqual(
        @as(?canvas.Composer.Error, error.CommandLimit),
        rejected.rejected,
    );
    try std.testing.expectEqual(VisibleSetStatus.pending, boundary.visibleSetStatus(1));

    var composer = try canvas.Composer.init(std.testing.allocator, .{
        .sources = 1,
        .retained_resources = 4,
        .retained_commands = 4,
        .retained_pixel_bytes = 16,
        .composition_sources = 1,
        .candidate_resources = 4,
        .candidate_commands = 4,
        .candidate_pixel_bytes = 16,
    });
    defer composer.deinit();
    try std.testing.expectEqual(source, try composer.registerSource());
    try std.testing.expectEqual(@as(usize, 1), (try boundary.drainReady(&composer)).accepted);
    try std.testing.expectEqual(VisibleSetStatus.ready, boundary.visibleSetStatus(1));
    try boundary.claimVisibleSet(1);
    try boundary.releaseVisibleSetClaim(1);
    try std.testing.expectEqual(VisibleSetStatus.ready, boundary.visibleSetStatus(1));
    try boundary.claimVisibleSet(1);
    try boundary.commitVisibleSet(1);
    try std.testing.expectEqual(VisibleSetStatus.stale, boundary.visibleSetStatus(1));

    try boundary.publishVisibleSet(2, &.{member});
    try boundary.publishVisibleSet(3, &.{member});
    try std.testing.expectEqual(VisibleSetStatus.stale, boundary.visibleSetStatus(2));
    try std.testing.expectEqual(@as(u64, 3), boundary.visibleSetRequest().?.revision);
    try boundary.close(pane);
    try std.testing.expectEqual(VisibleSetStatus.stale, boundary.visibleSetStatus(3));
}

test "visible group with fifteen free blocks does not partially reserve sixteen" {
    var boundary = try Boundary.init(
        std.testing.io,
        std.testing.allocator,
        testLimits(1, 1, 4),
    );
    defer boundary.deinit();
    var pooled: [17]pool_storage.Member = undefined;
    var requested: [visible_member_limit]VisibleMember = undefined;
    for (0..17) |index| {
        const pane: PaneId = @fromBackingInt(@intCast(index + 1));
        const source: canvas.SourceId = @fromBackingInt(@intCast(index + 1));
        try boundary.register(pane, source, .{ .width = 1, .height = 1 });
        const created = boundary.takeLifecycle().?;
        try std.testing.expect(std.meta.activeTag(created) == .create);
        pooled[index] = try boundary.activateTransfer(pane);
        if (index != 0) requested[index - 1] = .{ .pane = pane, .source = source };
    }
    const unrelated = try boundary.reserveUpdate(pooled[0]);
    try boundary.publishVisibleSet(1, &requested);
    try std.testing.expectError(
        error.NoCapacity,
        boundary.reserveVisibleGroup(1, pooled[1..]),
    );
    try std.testing.expectError(error.Stale, boundary.abortVisibleGroup(1));
    const partial_capacity = try boundary.reserveVisibleGroup(1, pooled[1..16]);
    try std.testing.expectEqual(@as(u8, 15), partial_capacity.count);
    try boundary.abortVisibleGroup(1);
    try std.testing.expectEqual(VisibleSetStatus.stale, boundary.visibleSetStatus(1));
    try boundary.publishVisibleSet(2, &requested);
    const retried = try boundary.reserveVisibleGroup(2, pooled[1..16]);
    try std.testing.expectEqual(@as(u8, 15), retried.count);
    try boundary.abortVisibleGroup(2);
    try boundary.cancelUpdate(unrelated);
}

test "completed token blocks same entry until clear and cannot corrupt reuse" {
    var boundary = try Boundary.init(
        std.testing.io,
        std.testing.allocator,
        testLimits(4, 4, 16),
    );
    defer boundary.deinit();
    const first_pane: PaneId = @fromBackingInt(@intCast(34));
    const first_source: canvas.SourceId = @fromBackingInt(@intCast(1));
    try boundary.register(first_pane, first_source, .{ .width = 1, .height = 1 });
    try std.testing.expect(
        std.meta.activeTag(boundary.takeLifecycle().?) == .create,
    );
    const first = try boundary.activateTransfer(first_pane);
    const first_reserved = try boundary.reserveUpdate(first);
    try boundary.publishUpdate(first_reserved, .{
        .revision = @fromBackingInt(@intCast(1)),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{},
    });
    const completed = boundary.entries[0].?.ready.?;
    try boundary.pool.beginDrain(completed);
    try boundary.pool.completeDrain(completed);
    try std.testing.expectError(error.Busy, boundary.reserveUpdate(first));

    boundary.mutex.lockUncancelable(boundary.io);
    boundary.entries[0].?.ready = null;
    boundary.mutex.unlock(boundary.io);
    const second_reserved = try boundary.reserveUpdate(first);
    try boundary.publishUpdate(second_reserved, .{
        .revision = @fromBackingInt(@intCast(2)),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{},
    });
    const second_completed = boundary.entries[0].?.ready.?;
    try boundary.pool.beginDrain(second_completed);
    try boundary.pool.completeDrain(second_completed);

    const other_pane: PaneId = @fromBackingInt(@intCast(35));
    const other_source: canvas.SourceId = @fromBackingInt(@intCast(2));
    try boundary.register(other_pane, other_source, .{ .width = 1, .height = 1 });
    try std.testing.expect(
        std.meta.activeTag(boundary.takeLifecycle().?) == .create,
    );
    const other = try boundary.activateTransfer(other_pane);
    const other_reserved = try boundary.reserveUpdate(other);
    try boundary.publishUpdate(other_reserved, .{
        .revision = @fromBackingInt(@intCast(1)),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{},
    });
    try std.testing.expectError(
        error.Stale,
        boundary.pool.beginDrain(second_completed),
    );

    var composer = try canvas.Composer.init(std.testing.allocator, .{
        .sources = 2,
        .retained_resources = 4,
        .retained_commands = 4,
        .retained_pixel_bytes = 16,
        .composition_sources = 2,
        .candidate_resources = 4,
        .candidate_commands = 4,
        .candidate_pixel_bytes = 16,
    });
    defer composer.deinit();
    try std.testing.expectEqual(first_source, try composer.registerSource());
    try std.testing.expectEqual(other_source, try composer.registerSource());
    const drainage = try boundary.drainReady(&composer);
    try std.testing.expectEqual(@as(usize, 1), drainage.accepted);
    try std.testing.expect(drainage.rejected == null);

    try boundary.close(first_pane);
    try std.testing.expect(
        std.meta.activeTag(boundary.takeLifecycle().?) == .close,
    );
    try std.testing.expect(try boundary.retireTransfer(first_pane));
    try boundary.markRetired(first_pane);
    try std.testing.expectEqual(first_pane, boundary.takeRetired().?.pane);
    try boundary.finishRetired(first_pane);
    try boundary.close(other_pane);
    try std.testing.expect(
        std.meta.activeTag(boundary.takeLifecycle().?) == .close,
    );
    try std.testing.expect(try boundary.retireTransfer(other_pane));
    try boundary.markRetired(other_pane);
    try std.testing.expectEqual(other_pane, boundary.takeRetired().?.pane);
    try boundary.finishRetired(other_pane);
}

test "retirement releases reserved and ready boundaries without stranded state" {
    var boundary = try Boundary.init(
        std.testing.io,
        std.testing.allocator,
        testLimits(2, 2, 8),
    );
    defer boundary.deinit();
    const reserved_pane: PaneId = @fromBackingInt(@intCast(36));
    const reserved_source: canvas.SourceId = @fromBackingInt(@intCast(1));
    try boundary.register(reserved_pane, reserved_source, .{ .width = 1, .height = 1 });
    try std.testing.expect(
        std.meta.activeTag(boundary.takeLifecycle().?) == .create,
    );
    const reserved_member = try boundary.activateTransfer(reserved_pane);
    const reserved = try boundary.reserveUpdate(reserved_member);
    try boundary.close(reserved_pane);
    try std.testing.expect(
        std.meta.activeTag(boundary.takeLifecycle().?) == .close,
    );
    try std.testing.expect(!try boundary.retireTransfer(reserved_pane));
    try boundary.cancelUpdate(reserved);
    try std.testing.expect(try boundary.retireTransfer(reserved_pane));
    try boundary.markRetired(reserved_pane);
    try std.testing.expectEqual(reserved_pane, boundary.takeRetired().?.pane);
    try boundary.finishRetired(reserved_pane);

    const ready_pane: PaneId = @fromBackingInt(@intCast(37));
    const ready_source: canvas.SourceId = @fromBackingInt(@intCast(2));
    try boundary.register(ready_pane, ready_source, .{ .width = 1, .height = 1 });
    try std.testing.expect(
        std.meta.activeTag(boundary.takeLifecycle().?) == .create,
    );
    const ready_member = try boundary.activateTransfer(ready_pane);
    const ready_reserved = try boundary.reserveUpdate(ready_member);
    try boundary.publishUpdate(ready_reserved, .{
        .revision = @fromBackingInt(@intCast(1)),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{},
    });
    try boundary.close(ready_pane);
    try std.testing.expect(
        std.meta.activeTag(boundary.takeLifecycle().?) == .close,
    );
    try std.testing.expect(try boundary.retireTransfer(ready_pane));
    try std.testing.expect(boundary.entries[1].?.ready == null);
    try boundary.markRetired(ready_pane);
    try std.testing.expectEqual(ready_pane, boundary.takeRetired().?.pane);
    try boundary.finishRetired(ready_pane);
}

test "bounded terminal turn re-arms retained input work" {
    var boundary = try Boundary.init(
        std.testing.io,
        std.testing.allocator,
        testLimits(1, 1, 4),
    );
    defer boundary.deinit();
    const pane: PaneId = @fromBackingInt(@intCast(1));
    const source: canvas.SourceId = @fromBackingInt(@intCast(1));
    try boundary.register(pane, source, .{ .width = 16, .height = 16 });
    try boundary.drainTerminalWake();
    try std.testing.expectEqual(
        Lifecycle{ .create = .{ .pane = pane, .pixels = .{ .width = 16, .height = 16 } } },
        boundary.takeLifecycle().?,
    );
    try boundary.markLive(pane);
    try boundary.drainRendererWake();
    for (0..9) |_| try boundary.publishFocus(
        pane,
        .{ .focus = .in },
    );
    try boundary.drainTerminalWake();
    for (0..8) |_| {
        const input = boundary.takeInput().?;
        try std.testing.expectEqual(
            @as(std.meta.Tag(TerminalInput), .focus),
            std.meta.activeTag(input),
        );
    }
    boundary.rearmTerminalWork();

    var descriptor = std.posix.pollfd{
        .fd = boundary.terminalFd(),
        .events = std.posix.POLL.IN,
        .revents = 0,
    };
    try std.testing.expectEqual(
        @as(usize, 1),
        try std.posix.poll((&descriptor)[0..1], 0),
    );
    try boundary.drainTerminalWake();
    try std.testing.expect(boundary.takeInput() != null);
    try std.testing.expect(boundary.takeInput() == null);
}

test "final admitted lifecycle operation wakes the newest font request" {
    var boundary = try Boundary.init(
        std.testing.io,
        std.testing.allocator,
        testLimits(16, 16, 64),
    );
    defer boundary.deinit();
    var resize_operations: [9]Lifecycle = undefined;
    for (0..resize_operations.len) |index| {
        const pane: PaneId = @fromBackingInt(@intCast(index + 1));
        const source: canvas.SourceId = @fromBackingInt(@intCast(index + 1));
        try boundary.register(pane, source, .{ .width = 16, .height = 16 });
        resize_operations[index] = .{ .resize = .{
            .pane = pane,
            .pixels = .{ .width = 17, .height = 16 },
        } };
    }
    try boundary.drainTerminalWake();
    for (0..resize_operations.len) |_| {
        const create = boundary.takeLifecycle().?.create;
        try boundary.markLive(create.pane);
    }
    try boundary.drainRendererWake();

    var candidate = try boundary.prepareLifecycle(
        &resize_operations,
        &.{},
        null,
    );
    defer candidate.deinit();
    try admitTestCandidate(&candidate);
    try boundary.requestFontSize(17);
    try boundary.requestFontSize(18);
    try boundary.requestFontSize(19);
    try boundary.drainTerminalWake();

    for (0..8) |_| {
        try std.testing.expect(boundary.takeAdmittedLifecycle() != null);
    }
    try std.testing.expect(boundary.lifecycleFontStable());
    boundary.rearmTerminalWork();
    try expectTerminalWake(&boundary);
    try boundary.drainTerminalWake();

    try std.testing.expect(boundary.takeAdmittedLifecycle() != null);
    try std.testing.expect(!boundary.lifecycleFontStable());
    boundary.rearmTerminalWork();
    try expectTerminalWake(&boundary);
    try boundary.drainTerminalWake();
    const newest = boundary.takeFontRequest().?;
    try std.testing.expectEqual(@as(u16, 19), newest.pixel_height);
    try std.testing.expect(boundary.takeFontRequest() == null);
}

test "rejected and cancelled admission release queued font work" {
    var boundary = try Boundary.init(
        std.testing.io,
        std.testing.allocator,
        testLimits(2, 2, 16),
    );
    defer boundary.deinit();
    const pane: PaneId = @fromBackingInt(1);
    const source: canvas.SourceId = @fromBackingInt(1);
    try boundary.register(pane, source, .{ .width = 16, .height = 16 });
    try boundary.drainTerminalWake();
    try std.testing.expect(boundary.takeLifecycle().? == .create);
    try boundary.markLive(pane);
    try boundary.drainRendererWake();
    const operations = [_]Lifecycle{.{ .resize = .{
        .pane = pane,
        .pixels = .{ .width = 17, .height = 16 },
    } }};

    var rejected = try boundary.prepareLifecycle(&operations, &.{}, null);
    defer rejected.deinit();
    const rejected_revision = try rejected.publishAdmission();
    try std.testing.expect(boundary.takeLifecycleAdmission() != null);
    try boundary.requestFontSize(20);
    try boundary.completeLifecycleAdmission(
        rejected_revision,
        .{ .rejected = .terminal_capacity },
    );
    try boundary.drainTerminalWake();
    boundary.rearmTerminalWork();
    try expectTerminalWake(&boundary);
    try boundary.drainTerminalWake();
    try std.testing.expectEqual(
        @as(u16, 20),
        boundary.takeFontRequest().?.pixel_height,
    );
    rejected.deinit();

    var cancelled = try boundary.prepareLifecycle(&operations, &.{}, null);
    const cancelled_revision = try cancelled.publishAdmission();
    try std.testing.expectEqual(
        cancelled_revision,
        boundary.takeLifecycleAdmission().?.revision,
    );
    try boundary.requestFontSize(21);
    try boundary.drainTerminalWake();
    cancelled.deinit();
    boundary.rearmTerminalWork();
    try expectTerminalWake(&boundary);
    try boundary.drainTerminalWake();
    try std.testing.expectEqual(
        @as(u16, 21),
        boundary.takeFontRequest().?.pixel_height,
    );

    var admitted = try boundary.prepareLifecycle(&operations, &.{}, null);
    defer admitted.deinit();
    try admitTestCandidate(&admitted);
    try boundary.requestFontSize(22);
    try boundary.drainTerminalWake();
    try std.testing.expect(boundary.takeAdmittedLifecycle() != null);
    boundary.rearmTerminalWork();
    try expectTerminalWake(&boundary);
    try boundary.drainTerminalWake();
    try std.testing.expectEqual(
        @as(u16, 22),
        boundary.takeFontRequest().?.pixel_height,
    );
}

test "copied pending update is immutable saturated and reusable" {
    var slot = try PendingSlot.init(std.testing.allocator, testLimits(1, 1, 4));
    defer slot.deinit();
    var pixels = [_]u8{ 1, 2, 3, 4 };
    var commands = [_]canvas.Input{.{ .solid = .{
        .rect = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .clip = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .color = .{ .r = 1, .g = 2, .b = 3, .a = 4 },
    } }};
    const update = canvas.ProducerUpdate{
        .revision = @fromBackingInt(@intCast(1)),
        .uploads = &.{.{
            .resource = .{
                .resource = try canvas.ResourceId.local(1),
                .generation = @fromBackingInt(@intCast(1)),
            },
            .format = .rgba8,
            .pixels = .{
                .bytes = &pixels,
                .width = 1,
                .height = 1,
                .stride = 4,
            },
        }},
        .removals = &.{},
        .commands = &commands,
    };
    try std.testing.expectEqual(
        @as(?State, null),
        slot.claim(.free, .writing),
    );
    slot.copyTaken(update);
    slot.storeState(.ready, .release);
    pixels = @splat(0xaa);
    commands[0].solid.color = .{ .r = 9, .g = 9, .b = 9, .a = 9 };
    try std.testing.expectEqual(
        @as(?State, .ready),
        slot.claim(.free, .writing),
    );
    try std.testing.expectEqualSlices(u8, &.{ 0xaa, 0xaa, 0xaa, 0xaa }, &pixels);
    try std.testing.expectEqual(
        canvas.Color{ .r = 9, .g = 9, .b = 9, .a = 9 },
        commands[0].solid.color,
    );
    try std.testing.expectEqual(
        @as(canvas.ProducerRevision, @fromBackingInt(@intCast(1))),
        slot.revision,
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 1, 2, 3, 4 },
        slot.uploads[0].pixels.bytes,
    );

    var composer = try canvas.Composer.init(std.testing.allocator, .{
        .sources = 1,
        .retained_resources = 1,
        .retained_commands = 1,
        .retained_pixel_bytes = 4,
        .composition_sources = 1,
        .candidate_resources = 1,
        .candidate_commands = 1,
        .candidate_pixel_bytes = 4,
    });
    defer composer.deinit();
    const source = try composer.registerSource();
    try std.testing.expectError(
        error.InvalidSource,
        slot.drain(&composer, @fromBackingInt(@intCast(99))),
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 1, 2, 3, 4 },
        slot.uploads[0].pixels.bytes,
    );
    try std.testing.expect(try slot.drain(&composer, source));
    try std.testing.expect(!(try slot.drain(&composer, source)));
    try std.testing.expectEqual(
        @as(?State, null),
        slot.claim(.free, .writing),
    );
    slot.copyTaken(.{
        .revision = @fromBackingInt(@intCast(2)),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{},
    });
    slot.storeState(.ready, .release);
    try std.testing.expect(try slot.retire());
}

test "allocation failure and retirement preserve ownership" {
    var failing = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{ .fail_index = 2 },
    );
    try std.testing.expectError(
        error.OutOfMemory,
        PendingSlot.init(failing.allocator(), testLimits(1, 1, 1)),
    );

    var slot = try PendingSlot.init(std.testing.allocator, testLimits(1, 1, 1));
    defer slot.deinit();
    try std.testing.expectEqual(
        @as(?State, null),
        slot.claim(.free, .writing),
    );
    try std.testing.expectError(error.Busy, slot.retire());
    slot.copyTaken(.{
        .revision = @fromBackingInt(@intCast(1)),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{},
    });
    slot.storeState(.ready, .release);
    try std.testing.expectEqual(
        @as(?State, null),
        slot.claim(.ready, .draining),
    );
    try std.testing.expectError(error.Busy, slot.retire());
    slot.storeState(.ready, .release);
    try std.testing.expect(try slot.retire());
    try std.testing.expectError(error.Retired, slot.publish(
        undefined,
        undefined,
        undefined,
    ));
}

test "terminal receipt slot has exact bounded allocation" {
    var slot = try PendingSlot.init(
        std.testing.allocator,
        testLimits(32, 64, 8192),
    );
    defer slot.deinit();
    try std.testing.expectEqual(
        @as(usize, 15104),
        try requiredBytes(testLimits(32, 64, 8192)),
    );
    try std.testing.expectEqual(@as(usize, 120), @sizeOf(PendingSlot));
    try std.testing.expectEqual(
        @as(usize, 974336),
        (try requiredBytes(testLimits(32, 64, 8192)) +
            @sizeOf(PendingSlot)) * 64,
    );
}

test "release acquire transfers immutable bytes between threads" {
    var slot = try PendingSlot.init(std.testing.allocator, testLimits(1, 1, 4));
    defer slot.deinit();
    var context = ThreadProof{
        .slot = &slot,
        .resource = try canvas.ResourceId.local(1),
    };
    const producer = try std.Thread.spawn(.{}, ThreadProof.publish, .{&context});
    defer producer.join();

    var rounds: usize = 0;
    while (slot.claim(.ready, .draining) != null) : (rounds += 1) {
        if (rounds == 1_000_000) return error.TestExpectedEqual;
        std.atomic.spinLoopHint();
    }
    try std.testing.expectEqualSlices(
        u8,
        &.{ 1, 2, 3, 4 },
        slot.uploads[0].pixels.bytes,
    );
    slot.storeState(.free, .release);
}

test "small PendingSlot fixture copies every configured slice" {
    const limits = testLimits(4, 8, 64);
    var slot = try PendingSlot.init(std.testing.allocator, limits);
    defer slot.deinit();
    var pixels: [64]u8 = undefined;
    @memset(&pixels, 0x5A);
    var uploads: [4]canvas.ResourceUpload = undefined;
    var removals: [4]canvas.ResourceRemoval = undefined;
    for (&uploads, &removals, 0..) |*upload, *removal, index| {
        upload.* = .{
            .resource = .{
                .resource = try canvas.ResourceId.local(index + 1),
                .generation = @fromBackingInt(@intCast(1)),
            },
            .format = .alpha8,
            .pixels = .{
                .bytes = pixels[index * 16 ..][0..16],
                .width = 4,
                .height = 4,
                .stride = 4,
            },
        };
        removal.* = .{ .resource = .{
            .resource = try canvas.ResourceId.local(index + 5),
            .generation = @fromBackingInt(@intCast(1)),
        } };
    }
    var commands: [8]canvas.Input = undefined;
    for (&commands) |*command| command.* = .{ .solid = .{
        .rect = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .clip = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .color = .{ .r = 1, .g = 2, .b = 3, .a = 255 },
    } };
    try slot.reserve();
    slot.copyTaken(.{
        .revision = @fromBackingInt(@intCast(1)),
        .uploads = &uploads,
        .removals = &removals,
        .commands = &commands,
    });
    try std.testing.expectEqual(uploads.len, slot.upload_count);
    try std.testing.expectEqual(removals.len, slot.removal_count);
    try std.testing.expectEqual(commands.len, slot.command_count);
    try std.testing.expectEqualSlices(u8, &pixels, slot.pixels[0..pixels.len]);
    slot.storeState(.ready, .release);
    try std.testing.expect(try slot.retire());
}

test "current Content bounds copy maximum capacity shape" {
    const glyph_limit: usize = 512;
    const mask_limit: usize = 128;
    const image_limit: usize = 8;
    const resource_count = glyph_limit + mask_limit + image_limit;
    const command_count: usize = 4096;
    const pixel_count: usize = 4 * 1024 * 1024;
    const limits = testLimits(1024, command_count, pixel_count);
    var slot = try PendingSlot.init(std.testing.allocator, limits);
    defer slot.deinit();
    const pixels = try std.testing.allocator.alloc(u8, pixel_count);
    defer std.testing.allocator.free(pixels);
    @memset(pixels, 0x5A);
    const uploads = try std.testing.allocator.alloc(canvas.ResourceUpload, resource_count);
    defer std.testing.allocator.free(uploads);
    const removals = try std.testing.allocator.alloc(canvas.ResourceRemoval, resource_count);
    defer std.testing.allocator.free(removals);
    const commands = try std.testing.allocator.alloc(canvas.Input, command_count);
    defer std.testing.allocator.free(commands);
    const base_width = pixel_count / resource_count;
    const remainder = pixel_count % resource_count;
    var offset: usize = 0;
    for (uploads, removals, 0..) |*upload, *removal, index| {
        const width = base_width + @intFromBool(index < remainder);
        upload.* = .{
            .resource = .{
                .resource = try canvas.ResourceId.local(index + 1),
                .generation = @fromBackingInt(@intCast(1)),
            },
            .format = .alpha8,
            .pixels = .{
                .bytes = pixels[offset..][0..width],
                .width = @intCast(width),
                .height = 1,
                .stride = width,
            },
        };
        removal.* = .{ .resource = .{
            .resource = try canvas.ResourceId.local(
                resource_count + index + 1,
            ),
            .generation = @fromBackingInt(@intCast(1)),
        } };
        offset += width;
    }
    for (commands) |*command| command.* = .{ .solid = .{
        .rect = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .clip = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .color = .{ .r = 1, .g = 2, .b = 3, .a = 255 },
    } };
    try slot.reserve();
    slot.copyTaken(.{
        .revision = @fromBackingInt(@intCast(1)),
        .uploads = uploads,
        .removals = removals,
        .commands = commands,
    });
    try std.testing.expectEqual(resource_count, slot.upload_count);
    try std.testing.expectEqual(resource_count, slot.removal_count);
    try std.testing.expectEqual(command_count, slot.command_count);
    try std.testing.expectEqualSlices(u8, pixels, slot.pixels[0..pixel_count]);
    slot.storeState(.ready, .release);
    try std.testing.expect(try slot.retire());
}

const ThreadProof = struct {
    slot: *PendingSlot,
    resource: canvas.ResourceId,

    fn publish(self: *ThreadProof) void {
        var pixels = [_]u8{ 1, 2, 3, 4 };
        std.debug.assert(self.slot.claim(.free, .writing) == null);
        self.slot.copyTaken(.{
            .revision = @fromBackingInt(@intCast(1)),
            .uploads = &.{.{
                .resource = .{
                    .resource = self.resource,
                    .generation = @fromBackingInt(@intCast(1)),
                },
                .format = .rgba8,
                .pixels = .{
                    .bytes = &pixels,
                    .width = 1,
                    .height = 1,
                    .stride = 4,
                },
            }},
            .removals = &.{},
            .commands = &.{},
        });
        pixels = @splat(0xaa);
        self.slot.storeState(.ready, .release);
    }
};

fn testLimits(
    resources: usize,
    commands: usize,
    upload_bytes: usize,
) terminal.Content.Limits {
    return .{
        .cells = 256,
        .rows = 16,
        .images = 1,
        .placements = 1,
        .image_bytes = 1,
        .glyphs = 1,
        .masks = 1,
        .commands = commands,
        .resources_per_update = resources,
        .upload_bytes = upload_bytes,
        .raster_bytes = 1,
        .decoration_bytes = 1,
    };
}

fn admitTestCandidate(candidate: *Boundary.PreparedLifecycle) !void {
    const revision = try candidate.publishAdmission();
    const request = candidate.boundary.takeLifecycleAdmission().?;
    try std.testing.expectEqual(revision, request.revision);
    var result = LifecycleAdmissionResult{ .admitted = .{ .count = 0 } };
    for (request.operations[0..request.operation_count]) |operation| switch (operation) {
        .create => |value| {
            result.admitted.grids[result.admitted.count] = .{
                .pane = value.pane,
                .rows = 1,
                .columns = 1,
            };
            result.admitted.count += 1;
        },
        .resize => |value| {
            result.admitted.grids[result.admitted.count] = .{
                .pane = value.pane,
                .rows = 1,
                .columns = 1,
            };
            result.admitted.count += 1;
        },
        .close => {},
    };
    try candidate.boundary.completeLifecycleAdmission(revision, result);
    try candidate.commitAdmitted();
}

fn expectTerminalWake(boundary: *Boundary) !void {
    var descriptor = std.posix.pollfd{
        .fd = boundary.terminalFd(),
        .events = std.posix.POLL.IN,
        .revents = 0,
    };
    try std.testing.expectEqual(
        @as(usize, 1),
        try std.posix.poll((&descriptor)[0..1], 0),
    );
}
