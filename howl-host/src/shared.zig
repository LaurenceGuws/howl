//! Owns the bounded copied facts exchanged by Window and Render.

const std = @import("std");
const c = @import("host_c");

pub const slot_count: usize = 3;
pub const plane_limit: usize = 4;

pub const Plane = struct {
    offset: u32,
    stride: u32,
};

pub const Feedback = struct {
    device: u64,
    fourcc: u32,
    modifier: u64,
};

pub const SlotOffer = struct {
    dma_fd: i32,
    acquire_timeline_fd: i32,
    release_timeline_fd: i32,
    plane_count: u8,
    planes: [plane_limit]Plane,
};

pub const Completion = struct {
    revision: u64,
    slot: u8,
    acquire_point: u64,
    release_point: u64,
};

pub const Failure = enum {
    window,
    render,
    signal,
};

pub const Owner = enum {
    window,
    render,
};

pub const Boundary = struct {
    io: std.Io,
    mutex: std.Io.Mutex = .init,
    feedback: ?Feedback = null,
    feedback_revision: u64 = 0,
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

    pub fn init(io: std.Io) error{Signal}!Boundary {
        const render_fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
        if (render_fd < 0) return error.Signal;
        errdefer closeDescriptor(render_fd);
        const window_fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
        if (window_fd < 0) return error.Signal;
        return .{ .io = io, .render_fd = render_fd, .window_fd = window_fd };
    }

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

    pub fn renderFd(self: *const Boundary) i32 {
        return self.render_fd;
    }

    pub fn windowFd(self: *const Boundary) i32 {
        return self.window_fd;
    }

    pub fn drainRenderWake(self: *Boundary) error{Signal}!void {
        try drain(self.render_fd);
    }

    pub fn drainWindowWake(self: *Boundary) error{Signal}!void {
        try drain(self.window_fd);
    }

    pub fn publishFeedback(self: *Boundary, feedback: Feedback) error{ Stopping, Signal }!void {
        self.mutex.lockUncancelable(self.io);
        if (self.stop_requested) {
            self.mutex.unlock(self.io);
            return error.Stopping;
        }
        self.feedback = feedback;
        self.feedback_revision = next(self.feedback_revision);
        self.mutex.unlock(self.io);
        try signal(self.render_fd);
    }

    pub fn readFeedback(self: *Boundary) ?Feedback {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.feedback;
    }

    pub fn publishOffers(self: *Boundary, offers: [slot_count]SlotOffer) error{ Stopping, Signal }!void {
        self.mutex.lockUncancelable(self.io);
        if (self.stop_requested or self.offer_count != 0) {
            self.mutex.unlock(self.io);
            return error.Stopping;
        }
        for (offers, 0..) |offer, index| self.offers[index] = offer;
        self.offer_count = slot_count;
        self.mutex.unlock(self.io);
        try signal(self.window_fd);
    }

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

    pub fn markWindowRingReady(self: *Boundary) error{Signal}!void {
        self.mutex.lockUncancelable(self.io);
        self.window_ring_ready = true;
        self.mutex.unlock(self.io);
        try signal(self.render_fd);
    }

    pub fn isWindowRingReady(self: *Boundary) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.window_ring_ready;
    }

    pub fn publishCompletion(self: *Boundary, completion: Completion) error{ Stopping, CompletionLimit, InvalidRevision, Signal }!void {
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
        try signal(self.window_fd);
    }

    pub fn takeCompletion(self: *Boundary) ?Completion {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.completion_count == 0) return null;
        const result = self.completions[self.completion_head];
        self.completion_head = (self.completion_head + 1) % @as(u8, slot_count);
        self.completion_count -= 1;
        return result;
    }

    pub fn requestStop(self: *Boundary, failure: ?Failure) void {
        self.mutex.lockUncancelable(self.io);
        self.stop_requested = true;
        if (self.failure == null) self.failure = failure;
        self.mutex.unlock(self.io);
        signal(self.window_fd) catch self.recordFailure(.signal);
        signal(self.render_fd) catch self.recordFailure(.signal);
    }

    pub fn shouldStop(self: *Boundary) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.stop_requested;
    }

    pub fn markStopped(self: *Boundary, owner: Owner) void {
        self.mutex.lockUncancelable(self.io);
        switch (owner) {
            .window => self.window_stopped = true,
            .render => self.render_stopped = true,
        }
        self.mutex.unlock(self.io);
        signal(if (owner == .window) self.render_fd else self.window_fd) catch self.recordFailure(.signal);
    }

    pub fn stopped(self: *Boundary) struct { window: bool, render: bool } {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return .{ .window = self.window_stopped, .render = self.render_stopped };
    }

    fn recordFailure(self: *Boundary, failure: Failure) void {
        self.mutex.lockUncancelable(self.io);
        self.stop_requested = true;
        if (self.failure == null) self.failure = failure;
        self.mutex.unlock(self.io);
    }
};

fn next(current: u64) u64 {
    return if (current == std.math.maxInt(u64)) 1 else current + 1;
}

fn closeDescriptor(descriptor: i32) void {
    if (c.close(descriptor) != 0) @panic("shared descriptor cleanup failed");
}

fn signal(descriptor: i32) error{Signal}!void {
    var value: u64 = 1;
    while (true) {
        const result = c.write(descriptor, &value, @sizeOf(u64));
        if (result == @sizeOf(u64)) return;
        if (result < 0 and std.c.errno(result) == .INTR) continue;
        if (result < 0 and std.c.errno(result) == .AGAIN) return;
        return error.Signal;
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
