//! Owns bounded copied facts exchanged by Window, Input, and Render.

const std = @import("std");
const c = @import("host_c");
const wayland = @import("howl_wayland");

/// Fixes the number of independently reusable GPU image slots.
pub const slot_count: usize = 3;
/// Bounds copied keyboard/focus occurrences awaiting Session delivery.
pub const input_capacity: usize = 128;
/// Bounds host-local control requests awaiting Render ownership.
pub const host_command_capacity: usize = 16;
/// Bounds one copied private Unix endpoint handed from Render to Input.
pub const pane_endpoint_capacity: usize = 108;

pub const HostCommandKind = enum {
    grow_focused,
    shrink_focused,
    split_horizontal,
    close_created,
};

pub const HostCommand = struct {
    kind: HostCommandKind,
    pane: u8,
};

pub const PaneEndpoint = struct {
    len: u8,
    bytes: [pane_endpoint_capacity]u8,

    pub fn text(self: *const PaneEndpoint) []const u8 {
        return self.bytes[0..self.len];
    }
};

pub const InputEvent = union(enum) {
    key: wayland.input.Key,
    focus: bool,
};
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
    /// Pixel width of the exported image.
    width: u16,
    /// Pixel height of the exported image.
    height: u16,
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
    input,
};

/// Identifies one runtime owner for retirement facts.
pub const Owner = enum {
    window,
    render,
    input,
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
    inputs: [input_capacity]InputEvent = undefined,
    input_head: u16 = 0,
    input_count: u16 = 0,
    host_commands: [host_command_capacity]HostCommand = undefined,
    host_command_head: u8 = 0,
    host_command_count: u8 = 0,
    pane_endpoint: ?PaneEndpoint = null,
    pane_retired_pending: bool = false,
    stop_requested: bool = false,
    window_stopped: bool = false,
    render_stopped: bool = false,
    input_stopped: bool = false,
    failure: ?Failure = null,
    render_fd: i32,
    window_fd: i32,
    input_fd: i32,
    control_fd: i32,

    /// Creates the three owner-specific nonblocking eventfds.
    /// On failure, no descriptor remains owned by the caller.
    pub fn init(io: std.Io) error{Signal}!Boundary {
        const render_fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
        if (render_fd < 0) return error.Signal;
        errdefer closeDescriptor(render_fd);
        const window_fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
        if (window_fd < 0) return error.Signal;
        errdefer closeDescriptor(window_fd);
        const input_fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
        if (input_fd < 0) return error.Signal;
        errdefer closeDescriptor(input_fd);
        const control_fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
        if (control_fd < 0) return error.Signal;
        return .{
            .io = io,
            .render_fd = render_fd,
            .window_fd = window_fd,
            .input_fd = input_fd,
            .control_fd = control_fd,
        };
    }

    /// Closes retained offers and eventfds after every owner joins.
    pub fn deinit(self: *Boundary) void {
        for (&self.offers) |*offer| {
            if (offer.*) |owned| {
                closeDescriptor(owned.dma_fd);
                closeDescriptor(owned.acquire_timeline_fd);
                closeDescriptor(owned.release_timeline_fd);
                offer.* = null;
            }
        }
        closeDescriptor(self.control_fd);
        closeDescriptor(self.input_fd);
        closeDescriptor(self.window_fd);
        closeDescriptor(self.render_fd);
        self.* = undefined;
    }

    /// Borrows the process runtime IO used by Host-owned lifecycle helpers.
    pub fn runtimeIo(self: *const Boundary) std.Io {
        return self.io;
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

    /// Borrows the Window-to-Input eventfd until `deinit`.
    pub fn inputFd(self: *const Boundary) i32 {
        return self.input_fd;
    }

    /// Drains all pending Input wakes without blocking.
    pub fn drainInputWake(self: *Boundary) error{Signal}!void {
        try drain(self.input_fd);
    }

    /// Borrows the Input-to-Render host-control eventfd until `deinit`.
    pub fn controlFd(self: *const Boundary) i32 {
        return self.control_fd;
    }

    /// Drains all pending host-control wakes without blocking.
    pub fn drainControlWake(self: *Boundary) error{Signal}!void {
        try drain(self.control_fd);
    }

    /// Appends one bounded host-local command for Render.
    pub fn publishHostCommand(self: *Boundary, command: HostCommand) error{ Stopping, HostCommandLimit }!void {
        self.mutex.lockUncancelable(self.io);
        if (self.stop_requested) {
            self.mutex.unlock(self.io);
            return error.Stopping;
        }
        if (self.host_command_count == host_command_capacity) {
            self.mutex.unlock(self.io);
            return error.HostCommandLimit;
        }
        const tail = (@as(usize, self.host_command_head) + self.host_command_count) % host_command_capacity;
        self.host_commands[tail] = command;
        self.host_command_count += 1;
        self.mutex.unlock(self.io);
        signal(self.control_fd);
    }

    /// Removes and copies the oldest pending host-local Render command.
    pub fn takeHostCommand(self: *Boundary) ?HostCommand {
        self.mutex.lockUncancelable(self.io);
        if (self.host_command_count == 0) {
            self.mutex.unlock(self.io);
            return null;
        }
        const result = self.host_commands[self.host_command_head];
        self.host_command_head = @intCast((@as(usize, self.host_command_head) + 1) % host_command_capacity);
        self.host_command_count -= 1;
        const more = self.host_command_count != 0;
        self.mutex.unlock(self.io);
        if (more) signal(self.control_fd);
        return result;
    }

    /// Publishes one fully committed new-pane endpoint for Input attachment.
    pub fn publishPaneEndpoint(self: *Boundary, endpoint: []const u8) error{ Stopping, PaneEndpointPending, InvalidPaneEndpoint }!void {
        if (endpoint.len == 0 or endpoint.len > pane_endpoint_capacity or endpoint.len > std.math.maxInt(u8))
            return error.InvalidPaneEndpoint;
        var copied = PaneEndpoint{ .len = @intCast(endpoint.len), .bytes = @splat(0) };
        @memcpy(copied.bytes[0..endpoint.len], endpoint);
        self.mutex.lockUncancelable(self.io);
        if (self.stop_requested) {
            self.mutex.unlock(self.io);
            return error.Stopping;
        }
        if (self.pane_endpoint != null) {
            self.mutex.unlock(self.io);
            return error.PaneEndpointPending;
        }
        self.pane_endpoint = copied;
        self.mutex.unlock(self.io);
        signal(self.input_fd);
    }

    /// Transfers one committed new-pane endpoint to Input.
    pub fn takePaneEndpoint(self: *Boundary) ?PaneEndpoint {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const result = self.pane_endpoint orelse return null;
        self.pane_endpoint = null;
        return result;
    }

    /// Publishes the committed retirement of the host-created second pane.
    pub fn publishPaneRetired(self: *Boundary) error{ Stopping, PaneRetiredPending }!void {
        self.mutex.lockUncancelable(self.io);
        if (self.stop_requested) {
            self.mutex.unlock(self.io);
            return error.Stopping;
        }
        if (self.pane_retired_pending) {
            self.mutex.unlock(self.io);
            return error.PaneRetiredPending;
        }
        self.pane_retired_pending = true;
        self.mutex.unlock(self.io);
        signal(self.input_fd);
    }

    /// Consumes one committed dynamic-pane retirement notice.
    pub fn takePaneRetired(self: *Boundary) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (!self.pane_retired_pending) return false;
        self.pane_retired_pending = false;
        return true;
    }

    /// Appends one exact copied keyboard/focus occurrence for Input.
    pub fn publishInput(self: *Boundary, event: InputEvent) error{ Stopping, InputLimit }!void {
        self.mutex.lockUncancelable(self.io);
        if (self.stop_requested) {
            self.mutex.unlock(self.io);
            return error.Stopping;
        }
        if (self.input_count == input_capacity) {
            self.mutex.unlock(self.io);
            return error.InputLimit;
        }
        const tail = (@as(usize, self.input_head) + self.input_count) % input_capacity;
        self.inputs[tail] = event;
        self.input_count += 1;
        self.mutex.unlock(self.io);
        signal(self.input_fd);
    }

    /// Removes and copies the oldest pending keyboard/focus occurrence.
    pub fn takeInput(self: *Boundary) ?InputEvent {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.input_count == 0) return null;
        const result = self.inputs[self.input_head];
        self.input_head = @intCast((@as(usize, self.input_head) + 1) % input_capacity);
        self.input_count -= 1;
        return result;
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
                offer.width == 0 or offer.height == 0 or
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

    /// Makes stop monotonic, preserves the first failure, and wakes every owner.
    pub fn requestStop(self: *Boundary, failure: ?Failure) void {
        self.mutex.lockUncancelable(self.io);
        self.stop_requested = true;
        if (self.failure == null) self.failure = failure;
        self.mutex.unlock(self.io);
        signal(self.window_fd);
        signal(self.render_fd);
        signal(self.input_fd);
        signal(self.control_fd);
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
            .input => self.input_stopped = true,
        }
        self.mutex.unlock(self.io);
        signal(switch (owner) {
            .window => self.render_fd,
            .render => self.window_fd,
            .input => self.window_fd,
        });
    }

    /// Copies all final owner-retirement facts.
    pub fn stopped(self: *Boundary) struct { window: bool, render: bool, input: bool } {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return .{ .window = self.window_stopped, .render = self.render_stopped, .input = self.input_stopped };
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
