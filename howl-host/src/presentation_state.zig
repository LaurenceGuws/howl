//! Owns bounded cross-thread state and one latest ready frame shared by Window and Render.

const std = @import("std");
const wayland = @import("howl_wayland");

const linux = std.os.linux;
const eventfd_flags = linux.EFD.CLOEXEC | linux.EFD.NONBLOCK;

/// Fixes the number of independently reusable GPU image slots.
pub const slot_count: usize = 3;
/// Minimum compositor-configured surface extent retained by the host.
pub const surface_min: i32 = 64;
/// Bounds the DRM memory-plane descriptions copied for one slot.
pub const plane_limit: usize = 4;
/// Bounds one compositor-selected pixel dimension for this bounded host.
pub const surface_dimension_limit: u32 = 8192;

/// Copies one Wayland DMA-BUF plane layout without owning storage.
pub const Plane = struct {
    /// Byte offset from the start of the exported allocation.
    offset: u32,
    /// Bytes between consecutive rows.
    stride: u32,
};

/// Copies the compositor device and selected image tuple from Window to Render.
pub const Feedback = struct {
    /// Native `dev_t` value received through DMA-BUF feedback.
    device: u64,
    /// DRM fourcc selected from compositor feedback.
    fourcc: u32,
    /// DRM format modifier paired with `fourcc`.
    modifier: u64,
};

/// Copies one normalized positive rational value without interpreting its
/// domain. Equality is exact after the issuing owner canonicalizes it.
pub const ExactRational = struct {
    numerator: u32,
    denominator: u32,
};

/// Identifies one nonzero compositor-configured surface generation with
/// independent logical coordinates and physical attachment dimensions.
pub const SurfaceConfig = struct {
    /// Monotonic identity; newer configurations supersede older configurations.
    generation: u64,
    /// Window-logical width used by Canvas topology and Wayland destination.
    logical_width: u32,
    /// Window-logical height used by Canvas topology and Wayland destination.
    logical_height: u32,
    /// Checked physical width allocated by Render/Vulkan.
    physical_width: u32,
    /// Checked physical height allocated by Render/Vulkan.
    physical_height: u32,
    /// Accepted Window scale revision; zero identifies provisional bootstrap.
    scale_revision: u64,
    /// Accepted logical DPI, absent while Window is provisional or
    /// awaiting new compositor scale state.
    dpi_x: ?ExactRational = null,
    dpi_y: ?ExactRational = null,
    /// Buffer scale applied by Window for this generation.
    buffer_scale: u32,
    /// Whether Window applies a viewport destination for this generation.
    use_viewport: bool,
};

/// Transfers one slot's duplicated descriptors and immutable plane layout from
/// Render to Window. State owns every descriptor after successful publish;
/// `takeOffers` transfers all three descriptors to Window.
pub const SlotOffer = struct {
    /// Surface generation owning the image and wrappers.
    generation: u64,
    /// Pixel width of the offered image.
    width: u32,
    /// Pixel height of the offered image.
    height: u32,
    /// Exported DMA-BUF descriptor.
    dma_fd: i32,
    /// Duplicated acquire-timeline syncobj descriptor.
    acquire_timeline_fd: i32,
    /// Duplicated per-slot release-timeline syncobj descriptor.
    release_timeline_fd: i32,
    /// Number of initialized entries in `planes`.
    plane_count: u8,
    /// Fixed storage containing the initialized plane prefix.
    planes: [plane_limit]Plane,
};

/// Transfers one exact configuration with all three image-slot offers.
///
/// State retains this pair atomically until Window takes it; a newer
/// configure or offer cannot rewrite the config belonging to borrowed slots.
pub const OfferedRing = struct {
    /// Exact logical, physical, scale, and attachment configuration for `slots`.
    config: SurfaceConfig,
    /// Complete fixed ring whose descriptors transfer to Window.
    slots: [slot_count]SlotOffer,
};

/// Copies one newest completed Render revision eligible for Window presentation.
pub const ReadyFrame = struct {
    /// Surface generation owning the completed slot.
    generation: u64,
    /// Nonzero globally increasing render revision.
    revision: u64,
    /// Slot identity within the fixed ring.
    slot: u8,
    /// Acquire timeline point completed by Render.
    acquire_point: u64,
    /// Per-slot release point reserved for Window's commit.
    release_point: u64,
};

/// Describes which slots were presented before Window retired their wrappers.
/// Render must wait only these submitted release points before destroying the
/// corresponding Vulkan storage; never wait an unpresented slot.
pub const RetiredRing = struct {
    generation: u64,
    presented_mask: u8,
    release_points: [slot_count]u64,
};

/// Identifies the first runtime owner that failed.
pub const Failure = enum {
    window,
    render,
};

/// Identifies one runtime owner during retirement.
pub const Owner = enum {
    window,
    render,
};

/// Selects which retained latest ready frame Render atomically cancels.
pub const Cancellation = union(enum) {
    generation: u64,
    shutdown,
};

/// Owns copied cross-thread state, descriptor transfer, directional eventfds,
/// first-failure retention, and final owner-retirement state.
pub const State = struct {
    io: std.Io,
    mutex: std.Io.Mutex = .init,
    feedback: ?Feedback = null,
    configure: ?SurfaceConfig = null,
    latest_generation: u64 = 0,
    latest_logical_width: u32 = 0,
    latest_logical_height: u32 = 0,
    latest_physical_width: u32 = 0,
    latest_physical_height: u32 = 0,
    latest_scale_revision: u64 = 0,
    latest_dpi_x: ?ExactRational = null,
    latest_dpi_y: ?ExactRational = null,
    latest_buffer_scale: u32 = 1,
    latest_use_viewport: bool = false,
    offered_config: ?SurfaceConfig = null,
    offers: [slot_count]?SlotOffer = .{ null, null, null },
    offer_count: u8 = 0,
    window_ring_ready: bool = false,
    window_ring_generation: u64 = 0,
    presented_generation: u64 = 0,
    presented_mask: u8 = 0,
    presented_release_points: [slot_count]u64 = .{ 0, 0, 0 },
    pending_release: ?RetiredRing = null,
    retire_request_generation: u64 = 0,
    retired: ?RetiredRing = null,
    latest_ready_frame: ?ReadyFrame = null,
    latest_ready_revision: u64 = 0,
    stop_requested: bool = false,
    window_stopped: bool = false,
    render_stopped: bool = false,
    failure: ?Failure = null,
    input: wayland.input.State = .{},
    render_fd: i32,
    window_fd: i32,

    /// Creates both directional nonblocking eventfds.
    /// On failure, no descriptor remains owned by the caller.
    pub fn init(io: std.Io) error{Signal}!State {
        const pair = try createWakePair(NativeEventfd);
        return .{ .io = io, .render_fd = pair.first, .window_fd = pair.second };
    }

    /// Closes retained offers and both eventfds after Window and Render join.
    pub fn deinit(self: *State) void {
        for (&self.offers) |*offer| {
            if (offer.*) |owned| {
                closeDescriptor(owned.dma_fd);
                closeDescriptor(owned.acquire_timeline_fd);
                closeDescriptor(owned.release_timeline_fd);
                offer.* = null;
            }
        }
        closeDescriptor(self.window_fd);
        closeDescriptor(self.render_fd);
        self.* = undefined;
    }

    /// Borrows the Window-to-Render eventfd until `deinit`.
    pub fn renderFd(self: *const State) i32 {
        return self.render_fd;
    }

    /// Borrows the presentation-state readiness eventfd until `deinit`.
    pub fn frameReadyFd(self: *const State) i32 {
        return self.window_fd;
    }

    /// Drains all pending Render wakes without blocking.
    pub fn drainRenderWake(self: *State) error{Signal}!void {
        try drain(self.render_fd);
    }

    /// Drains stale or current presentation-state readiness without blocking.
    pub fn drainFrameReady(self: *State) error{Signal}!void {
        try drain(self.window_fd);
    }

    /// Appends one exact Wayland occurrence for Render without policy.
    pub fn publishInput(self: *State, event: wayland.input.Ordered) error{ Stopping, InputFull, InputRevisionOverflow }!void {
        self.mutex.lockUncancelable(self.io);
        if (self.stop_requested) {
            self.mutex.unlock(self.io);
            return error.Stopping;
        }
        self.input.push(event) catch |failure| {
            self.mutex.unlock(self.io);
            return switch (failure) {
                error.OrderedFull => error.InputFull,
                error.RevisionOverflow => error.InputRevisionOverflow,
            };
        };
        self.mutex.unlock(self.io);
        signal(self.render_fd);
    }

    /// Replaces the coalesced pointer snapshot and wakes Render.
    pub fn publishMotion(self: *State, motion: wayland.input.Motion) error{ Stopping, InputRevisionOverflow }!void {
        self.mutex.lockUncancelable(self.io);
        if (self.stop_requested) {
            self.mutex.unlock(self.io);
            return error.Stopping;
        }
        self.input.setMotion(motion) catch |failure| {
            self.mutex.unlock(self.io);
            return switch (failure) {
                error.RevisionOverflow => error.InputRevisionOverflow,
                error.OrderedFull => error.InputRevisionOverflow,
            };
        };
        self.mutex.unlock(self.io);
        signal(self.render_fd);
    }

    /// Replaces exact depressed/latched/locked/group masks and wakes Render.
    pub fn publishModifiers(self: *State, modifiers: wayland.input.Modifiers) error{ Stopping, InputRevisionOverflow }!void {
        self.mutex.lockUncancelable(self.io);
        if (self.stop_requested) {
            self.mutex.unlock(self.io);
            return error.Stopping;
        }
        self.input.setModifiers(modifiers) catch |failure| {
            self.mutex.unlock(self.io);
            return switch (failure) {
                error.RevisionOverflow => error.InputRevisionOverflow,
                error.OrderedFull => error.InputRevisionOverflow,
            };
        };
        self.mutex.unlock(self.io);
        signal(self.render_fd);
    }

    /// Replaces keyboard repeat timing and wakes Render with the new values.
    pub fn publishRepeat(self: *State, repeat: wayland.input.Repeat) error{ Stopping, InputRevisionOverflow }!void {
        self.mutex.lockUncancelable(self.io);
        if (self.stop_requested) {
            self.mutex.unlock(self.io);
            return error.Stopping;
        }
        self.input.setRepeat(repeat) catch |failure| {
            self.mutex.unlock(self.io);
            return switch (failure) {
                error.RevisionOverflow => error.InputRevisionOverflow,
                error.OrderedFull => error.InputRevisionOverflow,
            };
        };
        self.mutex.unlock(self.io);
        signal(self.render_fd);
    }

    /// Replaces the newest configuration, including zero unspecified values.
    pub fn publishInputConfigure(self: *State, width: u32, height: u32) error{ Stopping, InputRevisionOverflow }!void {
        self.mutex.lockUncancelable(self.io);
        if (self.stop_requested) {
            self.mutex.unlock(self.io);
            return error.Stopping;
        }
        self.input.setConfigure(width, height) catch |failure| {
            self.mutex.unlock(self.io);
            return switch (failure) {
                error.RevisionOverflow => error.InputRevisionOverflow,
                error.OrderedFull => error.InputRevisionOverflow,
            };
        };
        self.mutex.unlock(self.io);
        signal(self.render_fd);
    }

    /// Removes one oldest input occurrence for Render.
    pub fn takeInput(self: *State) ?wayland.input.Ordered {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.input.take();
    }

    /// Takes coalesced motion and configuration state and copies the latest masks.
    pub fn takeInputSnapshots(self: *State) wayland.input.Snapshot {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.input.takeSnapshots();
    }

    /// Replaces the copied feedback state and wakes Render.
    pub fn publishFeedback(self: *State, feedback: Feedback) error{Stopping}!void {
        self.mutex.lockUncancelable(self.io);
        if (self.stop_requested) {
            self.mutex.unlock(self.io);
            return error.Stopping;
        }
        self.feedback = feedback;
        self.mutex.unlock(self.io);
        signal(self.render_fd);
    }

    /// Copies the current feedback state without transferring ownership.
    pub fn readFeedback(self: *State) ?Feedback {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.feedback;
    }

    /// Publishes the newest bounded Window logical/physical configuration.
    /// Repeated identical configurations retain their generation; newer
    /// dimensions, attachment mode, or accepted scale revision supersede the
    /// pending configuration.
    pub fn publishConfigure(
        self: *State,
        logical_width: u32,
        logical_height: u32,
        physical_width: u32,
        physical_height: u32,
        scale_revision: u64,
        dpi_x: ?ExactRational,
        dpi_y: ?ExactRational,
        buffer_scale: u32,
        use_viewport: bool,
    ) error{ Stopping, InvalidConfigure, GenerationOverflow }!void {
        if (logical_width == 0 or logical_height == 0 or physical_width == 0 or physical_height == 0 or
            logical_width > surface_dimension_limit or logical_height > surface_dimension_limit or
            physical_width > surface_dimension_limit or physical_height > surface_dimension_limit or
            buffer_scale == 0 or (use_viewport and buffer_scale != 1) or
            ((dpi_x == null) != (dpi_y == null)) or
            (dpi_x != null and (scale_revision == 0 or
                !validRational(dpi_x.?) or !validRational(dpi_y.?))))
            return error.InvalidConfigure;
        self.mutex.lockUncancelable(self.io);
        if (self.stop_requested) {
            self.mutex.unlock(self.io);
            return error.Stopping;
        }
        if (self.latest_logical_width == logical_width and self.latest_logical_height == logical_height and
            self.latest_physical_width == physical_width and self.latest_physical_height == physical_height and
            self.latest_scale_revision == scale_revision and
            std.meta.eql(self.latest_dpi_x, dpi_x) and
            std.meta.eql(self.latest_dpi_y, dpi_y) and
            self.latest_buffer_scale == buffer_scale and self.latest_use_viewport == use_viewport)
        {
            self.mutex.unlock(self.io);
            return;
        }
        if (self.latest_generation == std.math.maxInt(u64)) {
            self.mutex.unlock(self.io);
            return error.GenerationOverflow;
        }
        self.latest_generation += 1;
        self.latest_logical_width = logical_width;
        self.latest_logical_height = logical_height;
        self.latest_physical_width = physical_width;
        self.latest_physical_height = physical_height;
        self.latest_scale_revision = scale_revision;
        self.latest_dpi_x = dpi_x;
        self.latest_dpi_y = dpi_y;
        self.latest_buffer_scale = buffer_scale;
        self.latest_use_viewport = use_viewport;
        self.configure = .{
            .generation = self.latest_generation,
            .logical_width = logical_width,
            .logical_height = logical_height,
            .physical_width = physical_width,
            .physical_height = physical_height,
            .scale_revision = scale_revision,
            .dpi_x = dpi_x,
            .dpi_y = dpi_y,
            .buffer_scale = buffer_scale,
            .use_viewport = use_viewport,
        };
        self.mutex.unlock(self.io);
        signal(self.render_fd);
    }

    /// Takes the newest pending configuration for Render.
    pub fn takeConfigure(self: *State) ?SurfaceConfig {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const result = self.configure;
        self.configure = null;
        return result;
    }

    /// Reports whether a staged generation is still the newest configuration.
    pub fn isLatestGeneration(self: *State, generation: u64) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.latest_generation == generation;
    }

    /// Transfers every descriptor in one complete valid ring from Render to
    /// State. Invalid configuration, an unconsumed ring, or shutdown leave State
    /// unchanged and every supplied descriptor owned by Render.
    pub fn publishOffers(self: *State, offers: [slot_count]SlotOffer) error{ Stopping, OffersPending, InvalidOffer }!void {
        const generation = offers[0].generation;
        const width = offers[0].width;
        const height = offers[0].height;
        for (offers) |offer| {
            if (offer.dma_fd < 0 or
                offer.acquire_timeline_fd < 0 or
                offer.release_timeline_fd < 0 or
                offer.generation == 0 or offer.generation != generation or
                offer.width == 0 or offer.height == 0 or
                offer.width > surface_dimension_limit or offer.height > surface_dimension_limit or
                offer.width != width or offer.height != height or
                offer.plane_count == 0 or
                offer.plane_count > plane_limit)
            {
                return error.InvalidOffer;
            }
        }
        self.mutex.lockUncancelable(self.io);
        if (self.stop_requested) {
            self.mutex.unlock(self.io);
            return error.Stopping;
        }
        if (self.offer_count != 0) {
            self.mutex.unlock(self.io);
            return error.OffersPending;
        }
        if (generation != self.latest_generation or width != self.latest_physical_width or height != self.latest_physical_height) {
            self.mutex.unlock(self.io);
            return error.InvalidOffer;
        }
        self.offered_config = .{
            .generation = self.latest_generation,
            .logical_width = self.latest_logical_width,
            .logical_height = self.latest_logical_height,
            .physical_width = self.latest_physical_width,
            .physical_height = self.latest_physical_height,
            .scale_revision = self.latest_scale_revision,
            .dpi_x = self.latest_dpi_x,
            .dpi_y = self.latest_dpi_y,
            .buffer_scale = self.latest_buffer_scale,
            .use_viewport = self.latest_use_viewport,
        };
        for (offers, 0..) |offer, index| self.offers[index] = offer;
        self.offer_count = slot_count;
        self.mutex.unlock(self.io);
        signal(self.window_fd);
    }

    /// Transfers one complete retained ring and its exact configuration from
    /// State to Window under one lock acquisition.
    pub fn takeOffers(self: *State) ?OfferedRing {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.offer_count != slot_count) return null;
        const config = self.offered_config orelse
            @panic("complete ring offers have no configure owner");
        var slots: [slot_count]SlotOffer = undefined;
        for (&self.offers, 0..) |*offer, index| {
            slots[index] = offer.*.?;
            offer.* = null;
        }
        self.offer_count = 0;
        self.offered_config = null;
        return .{ .config = config, .slots = slots };
    }

    /// Reports whether the exact transferred-but-not-yet-taken ring still
    /// requires the Window-owned viewport/fractional-scale pair.
    pub fn pendingOffersUseViewport(self: *State) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.offer_count != slot_count) return false;
        return if (self.offered_config) |config| config.use_viewport else false;
    }

    /// Publishes completed Window wrapper construction and wakes Render.
    pub fn markWindowRingReady(self: *State, generation: u64) void {
        self.mutex.lockUncancelable(self.io);
        if (self.presented_generation != 0 and self.presented_mask != 0) {
            self.pending_release = .{ .generation = self.presented_generation, .presented_mask = self.presented_mask, .release_points = self.presented_release_points };
        }
        self.window_ring_ready = true;
        self.window_ring_generation = generation;
        self.presented_generation = generation;
        self.presented_mask = 0;
        self.presented_release_points = .{ 0, 0, 0 };
        self.mutex.unlock(self.io);
        signal(self.render_fd);
    }

    /// Records a slot release point while its Window wrapper remains live.
    pub fn recordPresentation(self: *State, generation: u64, slot: u8, release_point: u64) error{InvalidRevision}!void {
        if (slot >= slot_count or generation == 0 or release_point == 0) return error.InvalidRevision;
        self.mutex.lockUncancelable(self.io);
        if (self.presented_generation != generation) {
            self.mutex.unlock(self.io);
            return error.InvalidRevision;
        }
        self.presented_mask |= @as(u8, 1) << @intCast(slot);
        self.presented_release_points[slot] = release_point;
        self.mutex.unlock(self.io);
        signal(self.render_fd);
    }

    /// Copies the currently presented ring-release state for Render's wait phase.
    pub fn ringReleaseState(self: *State, generation: u64) ?RetiredRing {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.pending_release) |pending| if (pending.generation == generation) return pending;
        if (self.presented_generation != generation) return null;
        return .{ .generation = generation, .presented_mask = self.presented_mask, .release_points = self.presented_release_points };
    }

    /// Requests Window to retire wrappers after Render has observed release.
    pub fn requestWindowRingRetirement(self: *State, generation: u64) void {
        self.mutex.lockUncancelable(self.io);
        if (generation > self.retire_request_generation) self.retire_request_generation = generation;
        self.mutex.unlock(self.io);
        signal(self.window_fd);
    }

    /// Copies and consumes the newest wrapper-retirement request.
    pub fn takeWindowRingRetirementRequest(self: *State, generation: u64) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.retire_request_generation >= generation) {
            self.retire_request_generation = 0;
            return true;
        }
        return false;
    }

    /// Copies whether Window completed every slot wrapper.
    pub fn isWindowRingReady(self: *State, generation: u64) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.window_ring_ready and self.window_ring_generation == generation;
    }

    /// Records that Window has destroyed wrappers from an older generation.
    pub fn markWindowRingRetired(self: *State, retired: RetiredRing) void {
        self.mutex.lockUncancelable(self.io);
        if (self.retired == null or retired.generation > self.retired.?.generation) {
            self.retired = retired;
        }
        self.mutex.unlock(self.io);
        signal(self.render_fd);
    }

    /// Takes wrapper-retirement state for Renderer cleanup ordering.
    pub fn takeWindowRingRetired(self: *State, generation: u64) ?RetiredRing {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.retired) |retired| {
            if (retired.generation >= generation) {
                self.retired = null;
                if (self.pending_release) |pending| {
                    if (pending.generation == generation) self.pending_release = null;
                }
                return retired;
            }
        }
        return null;
    }

    /// Replaces the latest ready frame and returns the exact superseded frame.
    /// Only an empty-to-ready transition signals presentation-state readiness.
    pub fn updateLatestReadyFrame(
        self: *State,
        frame: ReadyFrame,
    ) error{ Stopping, StaleGeneration, InvalidSlot, InvalidRevision }!?ReadyFrame {
        self.mutex.lockUncancelable(self.io);
        if (self.stop_requested) {
            self.mutex.unlock(self.io);
            return error.Stopping;
        }
        if (frame.generation == 0 or frame.generation != self.window_ring_generation) {
            self.mutex.unlock(self.io);
            return error.StaleGeneration;
        }
        if (frame.slot >= slot_count) {
            self.mutex.unlock(self.io);
            return error.InvalidSlot;
        }
        if (frame.revision == 0 or frame.acquire_point == 0 or
            frame.release_point == 0 or
            frame.revision <= self.latest_ready_revision)
        {
            self.mutex.unlock(self.io);
            return error.InvalidRevision;
        }
        const superseded = self.latest_ready_frame;
        self.latest_ready_frame = frame;
        self.latest_ready_revision = frame.revision;
        self.mutex.unlock(self.io);
        if (superseded == null) signal(self.window_fd);
        return superseded;
    }

    /// Atomically takes the newest Window work. A taken frame cannot be superseded.
    pub fn takeLatestReadyFrame(self: *State) ?ReadyFrame {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const frame = self.latest_ready_frame;
        if (frame) |value| {
            if (value.generation != self.window_ring_generation) return null;
        }
        self.latest_ready_frame = null;
        return frame;
    }

    /// Returns one matching never-taken frame to Render. This operation and
    /// Window take share one lock, so exactly one caller can receive the value.
    pub fn cancelLatestReadyFrame(
        self: *State,
        cancellation: Cancellation,
    ) ?ReadyFrame {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const frame = self.latest_ready_frame orelse return null;
        const matches = switch (cancellation) {
            .generation => |generation| frame.generation == generation,
            .shutdown => true,
        };
        if (!matches) return null;
        self.latest_ready_frame = null;
        return frame;
    }

    /// Copies whether shared Window work currently exists.
    pub fn hasLatestReadyFrame(self: *State) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.latest_ready_frame != null;
    }

    /// Makes stop monotonic, preserves the first failure, and wakes both owners.
    pub fn requestStop(self: *State, failure: ?Failure) void {
        self.mutex.lockUncancelable(self.io);
        const first = !self.stop_requested;
        self.stop_requested = true;
        if (first) self.failure = failure;
        self.mutex.unlock(self.io);
        signal(self.window_fd);
        signal(self.render_fd);
    }

    /// Copies the monotonic stop state.
    pub fn shouldStop(self: *State) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.stop_requested;
    }

    /// Publishes one owner's final retirement and wakes its peer.
    pub fn markStopped(self: *State, owner: Owner) void {
        self.mutex.lockUncancelable(self.io);
        switch (owner) {
            .window => self.window_stopped = true,
            .render => self.render_stopped = true,
        }
        self.mutex.unlock(self.io);
        signal(if (owner == .window) self.render_fd else self.window_fd);
    }

    /// Copies both final owner-retirement states.
    pub fn stopped(self: *State) struct { window: bool, render: bool } {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return .{ .window = self.window_stopped, .render = self.render_stopped };
    }
};

fn closeDescriptor(descriptor: i32) void {
    if (std.posix.system.close(descriptor) != 0)
        @panic("presentation-state descriptor cleanup failed");
}

const WakePair = struct { first: i32, second: i32 };

const NativeEventfd = struct {
    fn create(flags: u32) usize {
        return linux.eventfd(0, flags);
    }

    fn close(descriptor: i32) void {
        closeDescriptor(descriptor);
    }
};

fn createEventfd(comptime Ops: type) error{Signal}!i32 {
    const result = Ops.create(eventfd_flags);
    if (linux.errno(result) != .SUCCESS) return error.Signal;
    return std.math.cast(i32, result) orelse return error.Signal;
}

fn createWakePair(comptime Ops: type) error{Signal}!WakePair {
    const first = try createEventfd(Ops);
    errdefer Ops.close(first);
    return .{ .first = first, .second = try createEventfd(Ops) };
}

fn validRational(value: ExactRational) bool {
    if (value.numerator == 0 or value.denominator == 0) return false;
    var a = value.numerator;
    var b = value.denominator;
    while (b != 0) {
        const remainder = a % b;
        a = b;
        b = remainder;
    }
    return a == 1;
}

fn signal(descriptor: i32) void {
    var value: u64 = 1;
    while (true) {
        const result = std.posix.system.write(
            descriptor,
            std.mem.asBytes(&value).ptr,
            @sizeOf(u64),
        );
        if (result == @sizeOf(u64)) return;
        if (result < 0 and std.posix.errno(result) == .INTR) continue;
        if (result < 0 and std.posix.errno(result) == .AGAIN) return;
        @panic("eventfd write violated the live State invariant");
    }
}

fn drain(descriptor: i32) error{Signal}!void {
    var value: u64 = 0;
    while (true) {
        const result = std.posix.read(descriptor, std.mem.asBytes(&value)) catch |failure| switch (failure) {
            error.WouldBlock => return,
            else => return error.Signal,
        };
        if (result == @sizeOf(u64)) continue;
        return error.Signal;
    }
}

test "Window/Render eventfd pair preserves flags rollback and nonblocking wake ownership" {
    const FailingOps = struct {
        var create_count: u8 = 0;
        var close_count: u8 = 0;
        var observed_flags: [2]u32 = .{ 0, 0 };
        var closed_descriptor: i32 = -1;

        fn create(flags: u32) usize {
            observed_flags[create_count] = flags;
            create_count += 1;
            return if (create_count == 1) 41 else std.math.maxInt(usize);
        }

        fn close(descriptor: i32) void {
            close_count += 1;
            closed_descriptor = descriptor;
        }
    };
    FailingOps.create_count = 0;
    FailingOps.close_count = 0;
    FailingOps.observed_flags = .{ 0, 0 };
    FailingOps.closed_descriptor = -1;

    try std.testing.expectError(error.Signal, createWakePair(FailingOps));
    try std.testing.expectEqual(@as(u8, 2), FailingOps.create_count);
    try std.testing.expectEqual(@as(u8, 1), FailingOps.close_count);
    try std.testing.expectEqual(@as(i32, 41), FailingOps.closed_descriptor);
    try std.testing.expectEqual(eventfd_flags, FailingOps.observed_flags[0]);
    try std.testing.expectEqual(eventfd_flags, FailingOps.observed_flags[1]);

    const WideOps = struct {
        fn create(_: u32) usize {
            return @as(usize, std.math.maxInt(i32)) + 1;
        }
    };
    try std.testing.expectError(error.Signal, createEventfd(WideOps));

    const pair = try createWakePair(NativeEventfd);
    defer closeDescriptor(pair.second);
    defer closeDescriptor(pair.first);

    var value: u64 = 0;
    value = std.math.maxInt(u64) - 1;
    try std.testing.expectEqual(
        @as(isize, @sizeOf(u64)),
        std.posix.system.write(
            pair.first,
            std.mem.asBytes(&value).ptr,
            @sizeOf(u64),
        ),
    );
    signal(pair.first);
    try drain(pair.first);
    try std.testing.expectError(
        error.WouldBlock,
        std.posix.read(pair.first, std.mem.asBytes(&value)),
    );
    try std.testing.expectError(error.Signal, drain(-1));
}
