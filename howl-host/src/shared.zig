//! Owns the bounded copied facts exchanged by Window and Render.

const std = @import("std");
const c = @import("host_c");

/// Fixes the number of independently reusable GPU image slots.
pub const slot_count: usize = 3;
/// Bounds the DRM memory-plane facts copied for one slot.
pub const plane_limit: usize = 4;

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

/// Transfers one slot's duplicated descriptors and immutable plane layout from
/// Render to Window. Boundary owns every descriptor after successful publish;
/// `takeOffers` transfers all three descriptors to Window.
pub const SlotOffer = struct {
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
    /// Nonzero globally increasing render revision.
    revision: u64,
    /// Slot identity within the fixed ring.
    slot: u8,
    /// Acquire timeline point completed by Render.
    acquire_point: u64,
    /// Per-slot release point reserved for Window's commit.
    release_point: u64,
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
    offers: [slot_count]?SlotOffer = .{ null, null, null },
    offer_count: u8 = 0,
    window_ring_ready: bool = false,
    completions: [slot_count]Completion = undefined,
    completion_head: u8 = 0,
    completion_count: u8 = 0,
    stop_requested: bool = false,
    window_stopped: bool = false,
    render_stopped: bool = false,
    failure: ?Failure = null,
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

    /// Transfers every descriptor in one complete valid ring from Render to
    /// Boundary. Invalid facts, an unconsumed ring, or shutdown leave Boundary
    /// unchanged and every supplied descriptor owned by Render.
    pub fn publishOffers(self: *Boundary, offers: [slot_count]SlotOffer) error{ Stopping, OffersPending, InvalidOffer }!void {
        for (offers) |offer| {
            if (offer.dma_fd < 0 or
                offer.acquire_timeline_fd < 0 or
                offer.release_timeline_fd < 0 or
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
    pub fn markWindowRingReady(self: *Boundary) void {
        self.mutex.lockUncancelable(self.io);
        self.window_ring_ready = true;
        self.mutex.unlock(self.io);
        signal(self.render_fd);
    }

    /// Copies whether Window completed every slot wrapper.
    pub fn isWindowRingReady(self: *Boundary) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.window_ring_ready;
    }

    /// Appends one ordered completion and wakes Window transactionally.
    pub fn publishCompletion(self: *Boundary, completion: Completion) error{ Stopping, CompletionLimit, InvalidRevision }!void {
        self.mutex.lockUncancelable(self.io);
        if (self.stop_requested) {
            self.mutex.unlock(self.io);
            return error.Stopping;
        }
        if (completion.revision == 0 or completion.slot >= slot_count) {
            self.mutex.unlock(self.io);
            return error.InvalidRevision;
        }
        if (self.completion_count == slot_count) {
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
