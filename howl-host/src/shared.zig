//! Owns the bounded copied facts exchanged by Window and Render.

const std = @import("std");
const c = @import("host_c");
const wayland = @import("howl_wayland");

/// Fixes the number of independently reusable GPU image slots.
pub const slot_count: usize = 3;
/// Minimum compositor-configured surface extent retained by the host.
pub const surface_min: i32 = 64;
/// Bounds the DRM memory-plane facts copied for one slot.
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

/// Identifies one nonzero compositor-configured pixel surface generation.
pub const SurfaceConfig = struct {
    /// Monotonic identity; newer facts supersede older facts.
    generation: u64,
    /// Configured pixel width.
    width: u32,
    /// Configured pixel height.
    height: u32,
};

/// Transfers one slot's duplicated descriptors and immutable plane layout from
/// Render to Window. Boundary owns every descriptor after successful publish;
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

/// Copies one completed Render revision for compositor presentation.
pub const Completion = struct {
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

/// Identifies one runtime owner for retirement facts.
pub const Owner = enum {
    window,
    render,
};

/// Owns copied cross-thread facts, descriptor transfer, directional eventfds,
/// first-failure retention, and final owner-retirement state.
pub const Boundary = struct {
    io: std.Io,
    mutex: std.Io.Mutex = .init,
    feedback: ?Feedback = null,
    configure: ?SurfaceConfig = null,
    latest_generation: u64 = 0,
    latest_width: u32 = 0,
    latest_height: u32 = 0,
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
    completions: [slot_count]Completion = undefined,
    completion_head: u8 = 0,
    completion_count: u8 = 0,
    completion_reserved: u8 = 0,
    stop_requested: bool = false,
    window_stopped: bool = false,
    render_stopped: bool = false,
    failure: ?Failure = null,
    input: wayland.input.State = .{},
    render_fd: i32,
    window_fd: i32,

    /// Creates both directional nonblocking eventfds.
    /// On failure, no descriptor remains owned by the caller.
    pub fn init(io: std.Io) error{Signal}!Boundary {
        const render_fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
        if (render_fd < 0) return error.Signal;
        errdefer closeDescriptor(render_fd);
        const window_fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
        if (window_fd < 0) return error.Signal;
        return .{ .io = io, .render_fd = render_fd, .window_fd = window_fd };
    }

    /// Closes retained offers and both eventfds after Window and Render join.
    pub fn deinit(self: *Boundary) void {
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
    pub fn renderFd(self: *const Boundary) i32 {
        return self.render_fd;
    }

    /// Borrows the Render-to-Window eventfd until `deinit`.
    pub fn windowFd(self: *const Boundary) i32 {
        return self.window_fd;
    }

    /// Drains all pending Render wakes without blocking.
    pub fn drainRenderWake(self: *Boundary) error{Signal}!void {
        try drain(self.render_fd);
    }

    /// Drains all pending Window wakes without blocking.
    pub fn drainWindowWake(self: *Boundary) error{Signal}!void {
        try drain(self.window_fd);
    }

    /// Appends one exact Wayland occurrence for Render without policy.
    pub fn publishInput(self: *Boundary, event: wayland.input.Ordered) error{ Stopping, InputFull, InputRevisionOverflow }!void {
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
    pub fn publishMotion(self: *Boundary, motion: wayland.input.Motion) error{ Stopping, InputRevisionOverflow }!void {
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
    pub fn publishModifiers(self: *Boundary, modifiers: wayland.input.Modifiers) error{ Stopping, InputRevisionOverflow }!void {
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

    /// Replaces keyboard repeat timing and wakes Render with the new fact.
    pub fn publishRepeat(self: *Boundary, repeat: wayland.input.Repeat) error{ Stopping, InputRevisionOverflow }!void {
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

    /// Replaces the newest configure fact, including zero unspecified values.
    pub fn publishInputConfigure(self: *Boundary, width: u32, height: u32) error{ Stopping, InputRevisionOverflow }!void {
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
    pub fn takeInput(self: *Boundary) ?wayland.input.Ordered {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.input.take();
    }

    /// Takes coalesced motion/configure facts and copies the latest masks.
    pub fn takeInputSnapshots(self: *Boundary) wayland.input.Snapshot {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.input.takeSnapshots();
    }

    /// Replaces the copied feedback fact and wakes Render.
    pub fn publishFeedback(self: *Boundary, feedback: Feedback) error{Stopping}!void {
        self.mutex.lockUncancelable(self.io);
        if (self.stop_requested) {
            self.mutex.unlock(self.io);
            return error.Stopping;
        }
        self.feedback = feedback;
        self.mutex.unlock(self.io);
        signal(self.render_fd);
    }

    /// Copies the current feedback fact without transferring ownership.
    pub fn readFeedback(self: *Boundary) ?Feedback {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.feedback;
    }

    /// Publishes the newest nonzero bounded configure fact. Repeated identical
    /// dimensions retain their generation; newer dimensions supersede pending
    /// facts without allowing an older generation to cross the boundary.
    pub fn publishConfigure(self: *Boundary, width: u32, height: u32) error{ Stopping, InvalidConfigure, GenerationOverflow }!void {
        if (width == 0 or height == 0 or width > surface_dimension_limit or height > surface_dimension_limit) return error.InvalidConfigure;
        self.mutex.lockUncancelable(self.io);
        if (self.stop_requested) {
            self.mutex.unlock(self.io);
            return error.Stopping;
        }
        if (self.latest_width == width and self.latest_height == height) {
            self.mutex.unlock(self.io);
            return;
        }
        if (self.latest_generation == std.math.maxInt(u64)) {
            self.mutex.unlock(self.io);
            return error.GenerationOverflow;
        }
        self.latest_generation += 1;
        self.latest_width = width;
        self.latest_height = height;
        self.configure = .{ .generation = self.latest_generation, .width = width, .height = height };
        self.mutex.unlock(self.io);
        signal(self.render_fd);
    }

    /// Takes the newest pending configure fact for Render.
    pub fn takeConfigure(self: *Boundary) ?SurfaceConfig {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const result = self.configure;
        self.configure = null;
        return result;
    }

    /// Reports whether a staged generation is still the newest configure fact.
    pub fn isLatestGeneration(self: *Boundary, generation: u64) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.latest_generation == generation;
    }

    /// Transfers every descriptor in one complete valid ring from Render to
    /// Boundary. Invalid facts, an unconsumed ring, or shutdown leave Boundary
    /// unchanged and every supplied descriptor owned by Render.
    pub fn publishOffers(self: *Boundary, offers: [slot_count]SlotOffer) error{ Stopping, OffersPending, InvalidOffer }!void {
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
        if (generation != self.latest_generation or width == 0 or height == 0) {
            self.mutex.unlock(self.io);
            return error.InvalidOffer;
        }
        for (offers, 0..) |offer, index| self.offers[index] = offer;
        self.offer_count = slot_count;
        self.mutex.unlock(self.io);
        signal(self.window_fd);
    }

    /// Transfers one complete retained ring from Boundary to Window.
    pub fn takeOffers(self: *Boundary) ?[slot_count]SlotOffer {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.offer_count != slot_count) return null;
        var result: [slot_count]SlotOffer = undefined;
        for (&self.offers, 0..) |*offer, index| {
            result[index] = offer.*.?;
            offer.* = null;
        }
        self.offer_count = 0;
        return result;
    }

    /// Publishes completed Window wrapper construction and wakes Render.
    pub fn markWindowRingReady(self: *Boundary, generation: u64) void {
        self.mutex.lockUncancelable(self.io);
        if (self.presented_generation != 0 and self.presented_mask != 0) {
            self.pending_release = .{ .generation = self.presented_generation, .presented_mask = self.presented_mask, .release_points = self.presented_release_points };
        }
        self.window_ring_ready = true;
        self.window_ring_generation = generation;
        self.presented_generation = generation;
        self.presented_mask = 0;
        self.presented_release_points = .{ 0, 0, 0 };
        // A replacement ring supersedes every queued completion from the old
        // generation. Compact in place so a stale queue can never fill the
        // bounded completion transport or strand the new ring.
        var kept: [slot_count]Completion = undefined;
        var kept_count: u8 = 0;
        var index: u8 = 0;
        while (index < self.completion_count) : (index += 1) {
            const completion = self.completions[(self.completion_head + index) % @as(u8, slot_count)];
            if (completion.generation == generation) {
                kept[kept_count] = completion;
                kept_count += 1;
            }
        }
        self.completions = kept;
        self.completion_head = 0;
        self.completion_count = kept_count;
        self.mutex.unlock(self.io);
        signal(self.render_fd);
    }

    /// Records a slot release point while its Window wrapper remains live.
    pub fn recordPresentation(self: *Boundary, generation: u64, slot: u8, release_point: u64) error{InvalidRevision}!void {
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

    /// Copies the currently presented release facts for Render's wait phase.
    pub fn releaseFacts(self: *Boundary, generation: u64) ?RetiredRing {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.pending_release) |pending| if (pending.generation == generation) return pending;
        if (self.presented_generation != generation) return null;
        return .{ .generation = generation, .presented_mask = self.presented_mask, .release_points = self.presented_release_points };
    }

    /// Requests Window to retire wrappers after Render has observed release.
    pub fn requestWindowRingRetirement(self: *Boundary, generation: u64) void {
        self.mutex.lockUncancelable(self.io);
        if (generation > self.retire_request_generation) self.retire_request_generation = generation;
        self.mutex.unlock(self.io);
        signal(self.window_fd);
    }

    /// Copies and consumes the newest wrapper-retirement request.
    pub fn takeWindowRingRetirementRequest(self: *Boundary, generation: u64) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.retire_request_generation >= generation) {
            self.retire_request_generation = 0;
            return true;
        }
        return false;
    }

    /// Copies whether Window completed every slot wrapper.
    pub fn isWindowRingReady(self: *Boundary, generation: u64) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.window_ring_ready and self.window_ring_generation == generation;
    }

    /// Records that Window has destroyed wrappers from an older generation.
    pub fn markWindowRingRetired(self: *Boundary, retired: RetiredRing) void {
        self.mutex.lockUncancelable(self.io);
        if (self.retired == null or retired.generation > self.retired.?.generation) {
            self.retired = retired;
        }
        self.mutex.unlock(self.io);
        signal(self.render_fd);
    }

    /// Copies the wrapper-retirement fact for Renderer cleanup ordering.
    pub fn takeWindowRingRetired(self: *Boundary, generation: u64) ?RetiredRing {
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

    /// Appends one ordered completion and wakes Window transactionally.
    pub fn publishCompletion(self: *Boundary, completion: Completion) error{ Stopping, CompletionLimit, InvalidRevision }!void {
        self.mutex.lockUncancelable(self.io);
        if (self.stop_requested) {
            self.mutex.unlock(self.io);
            return error.Stopping;
        }
        if (completion.generation == 0 or completion.generation != self.window_ring_generation or completion.revision == 0 or completion.slot >= slot_count) {
            self.mutex.unlock(self.io);
            return error.InvalidRevision;
        }
        if (self.completion_count + self.completion_reserved == slot_count) {
            self.mutex.unlock(self.io);
            return error.CompletionLimit;
        }
        if (self.completion_count != 0) {
            const tail = (self.completion_head + self.completion_count - 1) % slot_count;
            if (completion.revision <= self.completions[tail].revision) {
                self.mutex.unlock(self.io);
                return error.InvalidRevision;
            }
        }
        const tail = (self.completion_head + self.completion_count) % slot_count;
        self.completions[tail] = completion;
        self.completion_count += 1;
        self.mutex.unlock(self.io);
        signal(self.window_fd);
    }

    /// Owns one validated completion reservation until exposure or discard.
    pub const PreparedCompletions = struct {
        boundary: *Boundary,
        values: [slot_count]Completion = undefined,
        count: u8,
        completed: bool = false,

        /// Exposes every reserved completion and wakes Window as one infallible step.
        pub fn commit(self: *PreparedCompletions) void {
            if (self.completed) @panic("completion reservation already completed");
            const boundary = self.boundary;
            boundary.mutex.lockUncancelable(boundary.io);
            defer boundary.mutex.unlock(boundary.io);
            std.debug.assert(boundary.completion_reserved >= self.count);
            boundary.completion_reserved -= self.count;
            for (self.values[0..self.count]) |completion| {
                std.debug.assert(boundary.completion_count < slot_count);
                const tail = (boundary.completion_head + boundary.completion_count) %
                    slot_count;
                boundary.completions[tail] = completion;
                boundary.completion_count += 1;
            }
            self.completed = true;
            signal(boundary.window_fd);
        }

        /// Releases reserved capacity without exposing any completion.
        pub fn deinit(self: *PreparedCompletions) void {
            if (self.completed) return;
            const boundary = self.boundary;
            boundary.mutex.lockUncancelable(boundary.io);
            std.debug.assert(boundary.completion_reserved >= self.count);
            boundary.completion_reserved -= self.count;
            boundary.mutex.unlock(boundary.io);
            self.completed = true;
        }
    };

    /// Validates and reserves an ordered completion batch without waking Window.
    pub fn prepareCompletions(
        self: *Boundary,
        completions: []const Completion,
    ) error{ Stopping, CompletionLimit, InvalidRevision }!PreparedCompletions {
        if (completions.len == 0 or completions.len > slot_count)
            return error.CompletionLimit;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.stop_requested) return error.Stopping;
        if (completions.len >
            slot_count - self.completion_count - self.completion_reserved)
            return error.CompletionLimit;
        var prior_revision: u64 = if (self.completion_count == 0)
            0
        else
            self.completions[
                (self.completion_head + self.completion_count - 1) % slot_count
            ].revision;
        for (completions) |completion| {
            if (completion.generation == 0 or
                completion.generation != self.window_ring_generation or
                completion.revision == 0 or completion.slot >= slot_count or
                completion.revision <= prior_revision)
                return error.InvalidRevision;
            prior_revision = completion.revision;
        }
        var prepared = PreparedCompletions{
            .boundary = self,
            .count = @intCast(completions.len),
        };
        @memcpy(prepared.values[0..completions.len], completions);
        self.completion_reserved += @intCast(completions.len);
        return prepared;
    }

    /// Reports whether Render can append one completion for the active Window
    /// ring. Window is the only consumer, so capacity cannot decrease between
    /// this preflight and a same-thread publication.
    pub fn canPublishCompletion(self: *Boundary, generation: u64) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return !self.stop_requested and
            generation != 0 and
            generation == self.window_ring_generation and
            self.completion_count + self.completion_reserved < slot_count;
    }

    /// Removes and copies the oldest completed revision for Window.
    pub fn takeCompletion(self: *Boundary) ?Completion {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.completion_count == 0) return null;
        const result = self.completions[self.completion_head];
        self.completion_head = (self.completion_head + 1) % @as(u8, slot_count);
        self.completion_count -= 1;
        return result;
    }

    /// Makes stop monotonic, preserves the first failure, and wakes both owners.
    pub fn requestStop(self: *Boundary, failure: ?Failure) void {
        self.mutex.lockUncancelable(self.io);
        self.stop_requested = true;
        if (self.failure == null) self.failure = failure;
        self.mutex.unlock(self.io);
        signal(self.window_fd);
        signal(self.render_fd);
    }

    /// Copies the monotonic stop fact.
    pub fn shouldStop(self: *Boundary) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.stop_requested;
    }

    /// Publishes one owner's final retirement and wakes its peer.
    pub fn markStopped(self: *Boundary, owner: Owner) void {
        self.mutex.lockUncancelable(self.io);
        switch (owner) {
            .window => self.window_stopped = true,
            .render => self.render_stopped = true,
        }
        self.mutex.unlock(self.io);
        signal(if (owner == .window) self.render_fd else self.window_fd);
    }

    /// Copies both final owner-retirement facts.
    pub fn stopped(self: *Boundary) struct { window: bool, render: bool } {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return .{ .window = self.window_stopped, .render = self.render_stopped };
    }
};

fn closeDescriptor(descriptor: i32) void {
    if (c.close(descriptor) != 0) @panic("shared descriptor cleanup failed");
}

fn signal(descriptor: i32) void {
    var value: u64 = 1;
    while (true) {
        const result = c.write(descriptor, &value, @sizeOf(u64));
        if (result == @sizeOf(u64)) return;
        if (result < 0 and std.c.errno(result) == .INTR) continue;
        if (result < 0 and std.c.errno(result) == .AGAIN) return;
        @panic("eventfd write violated the live Boundary invariant");
    }
}

fn drain(descriptor: i32) error{Signal}!void {
    var value: u64 = 0;
    while (true) {
        const result = c.read(descriptor, &value, @sizeOf(u64));
        if (result == @sizeOf(u64)) continue;
        if (result < 0 and std.c.errno(result) == .INTR) continue;
        if (result < 0 and std.c.errno(result) == .AGAIN) return;
        return error.Signal;
    }
}
