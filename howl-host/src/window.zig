//! Owns Wayland discovery, dispatch, DMA-BUF wrappers, and presentation.

const std = @import("std");
const c = @import("howl_wayland").c;
const wayland = @import("howl_wayland");
const window_render_boundary = @import("window_render_boundary.zig");

const format_limit: usize = 64;
const output_limit: usize = 16;
const keymap_size_limit: usize = 1024 * 1024;
const format_record_size: usize = 16;
// Feedback indices are u16 entry indexes into fixed-size records.
const format_table_size_limit: usize = (@as(usize, std.math.maxInt(u16)) + 1) * format_record_size;

const MappedBytes = []align(std.heap.page_size_min) const u8;
const empty_mapped_bytes: [0]u8 align(std.heap.page_size_min) = .{};

const MappingError = error{
    InvalidDescriptor,
    InvalidSize,
    MappingFailed,
};

const NativeMapping = struct {
    fn map(ptr: ?[*]align(std.heap.page_size_min) u8, size: usize, protection: std.posix.PROT, flags: std.posix.MAP, fd: i32, offset: u64) !MappedBytes {
        return std.posix.mmap(ptr, size, protection, flags, fd, offset);
    }

    fn unmap(bytes: MappedBytes) void {
        std.posix.munmap(bytes);
    }

    fn close(fd: i32) void {
        closeDescriptor(fd);
    }
};

fn mapReadOnlyPrivate(comptime Mapping: type, fd: i32, size: u32, size_limit: usize) MappingError!MappedBytes {
    if (fd < 0) return error.InvalidDescriptor;
    if (size == 0 or size > size_limit) return error.InvalidSize;
    return Mapping.map(
        null,
        size,
        std.posix.PROT{ .READ = true },
        std.posix.MAP{ .TYPE = .PRIVATE },
        fd,
        0,
    ) catch error.MappingFailed;
}

const FeedbackMapping = struct {
    fd: i32 = -1,
    bytes: MappedBytes = empty_mapped_bytes[0..],

    fn deinit(self: *FeedbackMapping, comptime Mapping: type) void {
        if (self.fd < 0) return;
        Mapping.unmap(self.bytes);
        Mapping.close(self.fd);
        self.* = .{};
    }
};

const ScaleError = error{
    InvalidScale,
    ArithmeticOverflow,
    RevisionExhausted,
    UnknownOutput,
    Stopping,
    InvalidConfigure,
    GenerationOverflow,
};

const Rational = struct {
    numerator: u32,
    denominator: u32,

    const one = Rational{ .numerator = 1, .denominator = 1 };

    fn init(numerator: u32, denominator: u32) ScaleError!Rational {
        if (numerator == 0 or denominator == 0) return error.InvalidScale;
        const divisor = gcd(numerator, denominator);
        const value = Rational{ .numerator = numerator / divisor, .denominator = denominator / divisor };
        if (@as(u64, value.numerator) >= @as(u64, 24) * value.denominator) return error.InvalidScale;
        return value;
    }

    fn eql(self: Rational, other: Rational) bool {
        return self.numerator == other.numerator and self.denominator == other.denominator;
    }

    fn dpi(self: Rational) ScaleError!Rational {
        const numerator = @as(u128, self.numerator) * 96;
        const denominator = @as(u128, self.denominator);
        const divisor = gcdWide(numerator, denominator);
        const reduced_numerator = numerator / divisor;
        const reduced_denominator = denominator / divisor;
        if (reduced_numerator > std.math.maxInt(u32) or reduced_denominator > std.math.maxInt(u32)) return error.ArithmeticOverflow;
        return Rational{ .numerator = @intCast(reduced_numerator), .denominator = @intCast(reduced_denominator) };
    }
};

fn gcd(left: u32, right: u32) u32 {
    var a = left;
    var b = right;
    while (b != 0) {
        const remainder = a % b;
        a = b;
        b = remainder;
    }
    return a;
}

fn gcdWide(left: u128, right: u128) u128 {
    var a = left;
    var b = right;
    while (b != 0) {
        const remainder = a % b;
        a = b;
        b = remainder;
    }
    return a;
}

const ScaleReadiness = enum(u8) { provisional, awaiting_compositor, accepted };

/// Window-owned scale facts. `effective`, DPI, and `revision` become accepted
/// only after compositor readiness; bootstrap values never cross into Runtime.
const ScaleFacts = struct {
    deduced: Rational = .one,
    preferred_integer: ?Rational = null,
    preferred_fractional_120: ?u32 = null,
    fractional_capable: bool = false,
    effective: Rational = .one,
    dpi_x: Rational = .{ .numerator = 96, .denominator = 1 },
    dpi_y: Rational = .{ .numerator = 96, .denominator = 1 },
    accepted_effective: Rational = .one,
    accepted_dpi_x: Rational = .{ .numerator = 96, .denominator = 1 },
    accepted_dpi_y: Rational = .{ .numerator = 96, .denominator = 1 },
    accepted_valid: bool = false,
    expect_preferred: bool = false,
    bootstrap_ready: bool = false,
    configure_ready: bool = false,
    readiness: ScaleReadiness = .provisional,
    revision: u64 = 0,

    fn recompute(self: *ScaleFacts, highest_entered: ?Rational) ScaleError!void {
        var next = self.*;
        if (highest_entered) |value| next.deduced = value;
        const selected = if (next.fractional_capable and next.preferred_fractional_120 != null)
            try Rational.init(next.preferred_fractional_120.?, 120)
        else
            next.preferred_integer orelse highest_entered;
        const ready = next.bootstrap_ready and selected != null and
            (!next.expect_preferred or (next.configure_ready and
                (next.preferred_integer != null or next.preferred_fractional_120 != null)));
        if (selected) |value| {
            next.effective = value;
            next.dpi_x = try next.effective.dpi();
            next.dpi_y = next.dpi_x;
        }
        next.readiness = if (ready) .accepted else if (selected == null and !self.accepted_valid) .provisional else .awaiting_compositor;
        const accepted_change = ready and (!self.accepted_valid or !self.accepted_effective.eql(next.effective) or !self.accepted_dpi_x.eql(next.dpi_x) or !self.accepted_dpi_y.eql(next.dpi_y));
        if (accepted_change) {
            if (self.revision == std.math.maxInt(u64)) return error.RevisionExhausted;
            next.revision = self.revision + 1;
            next.accepted_effective = next.effective;
            next.accepted_dpi_x = next.dpi_x;
            next.accepted_dpi_y = next.dpi_y;
            next.accepted_valid = true;
        }
        self.* = next;
    }

    fn effectiveScale120(self: *const ScaleFacts) ScaleError!u32 {
        if (self.fractional_capable and self.preferred_fractional_120 != null) return self.preferred_fractional_120.?;
        if (self.effective.denominator != 1) return error.InvalidScale;
        return std.math.mul(u32, self.effective.numerator, 120) catch error.ArithmeticOverflow;
    }
};

const OutputFact = struct {
    object: ?*c.wl_output = null,
    global_name: u32 = 0,
    scale: u32 = 1,
    entered: bool = false,
};

// No output registry fact is accepted as surface membership. Until enter or a
// preferred compositor scale arrives, the scale remains provisional.

const Ring = struct {
    generation: u64 = 0,
    width: u32 = 0,
    height: u32 = 0,
    logical_width: u32 = 0,
    logical_height: u32 = 0,
    buffer_scale: u32 = 1,
    use_viewport: bool = false,
    buffers: [window_render_boundary.slot_count]?*c.wl_buffer = .{ null, null, null },
    acquire_timelines: [window_render_boundary.slot_count]?*c.wp_linux_drm_syncobj_timeline_v1 = .{ null, null, null },
    release_timelines: [window_render_boundary.slot_count]?*c.wp_linux_drm_syncobj_timeline_v1 = .{ null, null, null },
    presented_mask: u8 = 0,
    release_points: [window_render_boundary.slot_count]u64 = .{ 0, 0, 0 },

    fn deinit(self: *Ring) void {
        var index = window_render_boundary.slot_count;
        while (index > 0) {
            index -= 1;
            if (self.buffers[index]) |value| c.wl_buffer_destroy(value);
            if (self.release_timelines[index]) |value| c.wp_linux_drm_syncobj_timeline_v1_destroy(value);
            if (self.acquire_timelines[index]) |value| c.wp_linux_drm_syncobj_timeline_v1_destroy(value);
        }
        self.* = .{};
    }
};

const State = struct {
    boundary: *window_render_boundary.Boundary,
    compositor: ?*c.wl_compositor = null,
    xdg: ?*c.xdg_wm_base = null,
    dmabuf: ?*c.zwp_linux_dmabuf_v1 = null,
    syncobj: ?*c.wp_linux_drm_syncobj_manager_v1 = null,
    fractional_manager: ?*c.wp_fractional_scale_manager_v1 = null,
    viewporter: ?*c.wp_viewporter = null,
    fractional_scale: ?*c.wp_fractional_scale_v1 = null,
    viewport: ?*c.wp_viewport = null,
    fractional_retire_pending: bool = false,
    seat: ?*c.wl_seat = null,
    keyboard: ?*c.wl_keyboard = null,
    pointer: ?*c.wl_pointer = null,
    surface: ?*c.wl_surface = null,
    xdg_surface: ?*c.xdg_surface = null,
    toplevel: ?*c.xdg_toplevel = null,
    sync_surface: ?*c.wp_linux_drm_syncobj_surface_v1 = null,
    compositor_name: u32 = 0,
    xdg_name: u32 = 0,
    dmabuf_name: u32 = 0,
    syncobj_name: u32 = 0,
    fractional_manager_name: u32 = 0,
    viewporter_name: u32 = 0,
    seat_name: u32 = 0,
    outputs: [output_limit]OutputFact = .{ OutputFact{}, OutputFact{}, OutputFact{}, OutputFact{}, OutputFact{}, OutputFact{}, OutputFact{}, OutputFact{}, OutputFact{}, OutputFact{}, OutputFact{}, OutputFact{}, OutputFact{}, OutputFact{}, OutputFact{}, OutputFact{} },
    output_count: u8 = 0,
    scale: ScaleFacts = .{},
    configured: bool = false,
    configured_width: u32 = 0,
    configured_height: u32 = 0,
    toplevel_configured: bool = false,
    feedback_complete: bool = false,
    feedback_device: u64 = 0,
    tranche_device: u64 = 0,
    format_table: FeedbackMapping = .{},
    formats: [format_limit]struct { fourcc: u32, modifier: u64, device: u64 } = undefined,
    format_count: u8 = 0,
    ring: Ring = .{},
    retiring: ?Ring = null,
    frame_callback: ?*c.wl_callback = null,
    presented_generation: u64 = 0,
    presented: u64 = 0,
    input_ready: bool = false,
    xkb_context: ?wayland.xkb.Context = null,
    xkb_keymap: ?wayland.xkb.Keymap = null,
    xkb_state: ?wayland.xkb.State = null,
    keyboard_modifiers: wayland.input.Modifiers = .{ .serial = 0, .depressed = 0, .latched = 0, .locked = 0, .group = 0 },
    keyboard_semantic_modifiers: wayland.input.SemanticModifiers = .{},
    pointer_motion: ?wayland.input.Motion = null,
    pointer_axis_motion: ?wayland.input.Motion = null,

    fn deinit(self: *State) void {
        if (self.xkb_state) |*value| value.deinit();
        if (self.xkb_keymap) |*value| value.deinit();
        if (self.xkb_context) |*value| value.deinit();
        if (self.keyboard) |value| c.wl_keyboard_destroy(value);
        if (self.pointer) |value| c.wl_pointer_destroy(value);
        if (self.seat) |value| c.wl_seat_destroy(value);
        for (self.outputs[0..self.output_count]) |output| if (output.object) |value| c.wl_output_destroy(value);
        if (self.frame_callback) |value| c.wl_callback_destroy(value);
        if (self.sync_surface) |value| c.wp_linux_drm_syncobj_surface_v1_destroy(value);
        const retired = if (self.ring.generation == 0) null else window_render_boundary.RetiredRing{
            .generation = self.ring.generation,
            .presented_mask = self.ring.presented_mask,
            .release_points = self.ring.release_points,
        };
        self.ring.deinit();
        if (retired) |fact| self.boundary.markWindowRingRetired(fact);
        if (self.retiring) |*old| {
            const fact = window_render_boundary.RetiredRing{ .generation = old.generation, .presented_mask = old.presented_mask, .release_points = old.release_points };
            old.deinit();
            self.boundary.markWindowRingRetired(fact);
            self.retiring = null;
        }
        if (self.toplevel) |value| c.xdg_toplevel_destroy(value);
        if (self.xdg_surface) |value| c.xdg_surface_destroy(value);
        if (self.viewport) |value| c.wp_viewport_destroy(value);
        if (self.fractional_scale) |value| c.wp_fractional_scale_v1_destroy(value);
        if (self.surface) |value| c.wl_surface_destroy(value);
        if (self.viewporter) |value| c.wp_viewporter_destroy(value);
        if (self.fractional_manager) |value| c.wp_fractional_scale_manager_v1_destroy(value);
        if (self.syncobj) |value| c.wp_linux_drm_syncobj_manager_v1_destroy(value);
        if (self.dmabuf) |value| c.zwp_linux_dmabuf_v1_destroy(value);
        if (self.xdg) |value| c.xdg_wm_base_destroy(value);
        if (self.compositor) |value| c.wl_compositor_destroy(value);
        self.format_table.deinit(NativeMapping);
    }
};

/// Runs the sole Wayland owner until the window/render Boundary requests retirement.
/// All operational failures are recorded as the first Window runtime failure.
pub fn run(boundary: *window_render_boundary.Boundary) void {
    runFallible(boundary) catch |failure| {
        std.debug.print("Window failure: {s}\n", .{@errorName(failure)});
        boundary.requestStop(.window);
    };
    boundary.markStopped(.window);
}

fn runFallible(boundary: *window_render_boundary.Boundary) !void {
    var state = State{ .boundary = boundary };
    state.xkb_context = wayland.xkb.Context.init() catch return error.Xkb;
    const display = c.wl_display_connect(null) orelse return error.WaylandConnect;
    defer c.wl_display_disconnect(display);
    defer state.deinit();
    const registry = c.wl_display_get_registry(display) orelse return error.Registry;
    defer c.wl_registry_destroy(registry);
    if (c.wl_registry_add_listener(registry, &registry_listener, &state) != 0) return error.Listener;
    if (c.wl_display_roundtrip(display) < 0) return error.Dispatch;
    if (state.compositor == null or state.xdg == null or state.dmabuf == null or state.syncobj == null or state.seat == null) return error.RequiredGlobal;
    state.scale.bootstrap_ready = true;
    try recomputeScale(&state);
    if (c.wl_seat_add_listener(state.seat.?, &seat_listener, &state) != 0) return error.Listener;
    if (c.wl_display_roundtrip(display) < 0) return error.Dispatch;
    if (c.xdg_wm_base_add_listener(state.xdg.?, &xdg_listener, &state) != 0) return error.Listener;
    const feedback = c.zwp_linux_dmabuf_v1_get_default_feedback(state.dmabuf.?) orelse return error.Feedback;
    defer c.zwp_linux_dmabuf_feedback_v1_destroy(feedback);
    if (c.zwp_linux_dmabuf_feedback_v1_add_listener(feedback, &feedback_listener, &state) != 0) return error.Listener;
    if (c.wl_display_roundtrip(display) < 0) return error.Dispatch;
    if (!state.feedback_complete) return error.Feedback;
    const selected = selectFeedback(&state) orelse return error.NoFormat;
    try boundary.publishFeedback(selected);

    state.surface = c.wl_compositor_create_surface(state.compositor.?) orelse return error.Surface;
    if (c.wl_surface_add_listener(state.surface.?, &surface_listener, &state) != 0) return error.Listener;
    try prepareFractionalSurface(&state);
    state.xdg_surface = c.xdg_wm_base_get_xdg_surface(state.xdg.?, state.surface.?) orelse return error.Surface;
    if (c.xdg_surface_add_listener(state.xdg_surface.?, &xdg_surface_listener, &state) != 0) return error.Listener;
    state.toplevel = c.xdg_surface_get_toplevel(state.xdg_surface.?) orelse return error.Surface;
    if (c.xdg_toplevel_add_listener(state.toplevel.?, &toplevel_listener, &state) != 0) return error.Listener;
    c.xdg_toplevel_set_title(state.toplevel.?, "Howl Vulkan ring");
    c.xdg_toplevel_set_min_size(state.toplevel.?, window_render_boundary.surface_min, window_render_boundary.surface_min);
    c.wl_surface_commit(state.surface.?);
    if (c.wl_display_roundtrip(display) < 0 or !state.configured or !state.toplevel_configured) return error.Configure;
    if (state.configured_width == 0) state.configured_width = 640;
    if (state.configured_height == 0) state.configured_height = 480;
    try publishCurrentConfigure(&state);
    state.sync_surface = c.wp_linux_drm_syncobj_manager_v1_get_surface(state.syncobj.?, state.surface.?) orelse return error.ExplicitSync;

    const display_fd = c.wl_display_get_fd(display);
    if (display_fd < 0) return error.Dispatch;
    while (!boundary.shouldStop()) {
        if (state.retiring) |*old| if (boundary.takeWindowRingRetirementRequest(old.generation)) {
            const fact = window_render_boundary.RetiredRing{ .generation = old.generation, .presented_mask = old.presented_mask, .release_points = old.release_points };
            old.deinit();
            state.boundary.markWindowRingRetired(fact);
            state.retiring = null;
        };
        if (state.frame_callback == null) if (boundary.takeOffers()) |offer| {
            try constructRing(&state, offer);
            boundary.markWindowRingReady(offer.config.generation);
        };
        if (state.frame_callback == null) {
            if (boundary.takeCompletion()) |completion| {
                if (completion.generation == state.ring.generation) {
                    try present(&state, completion);
                }
            }
        }
        if (c.wl_display_dispatch_pending(display) < 0) return error.Dispatch;
        if (c.wl_display_flush(display) < 0) return error.Dispatch;
        var descriptors = [_]std.posix.pollfd{
            .{ .fd = display_fd, .events = std.posix.POLL.IN, .revents = 0 },
            .{ .fd = boundary.windowFd(), .events = std.posix.POLL.IN, .revents = 0 },
        };
        const poll_result = try waitWindowEvents(WindowPoll, &descriptors);
        const actions = classifyWindowPoll(poll_result, &descriptors);
        if (actions.drain_boundary) try boundary.drainWindowWake();
        if (actions.dispatch_display and c.wl_display_dispatch(display) < 0)
            return error.Dispatch;
        if (c.wl_display_get_error(display) != 0) return error.Protocol;
    }
    if (state.surface) |surface| {
        c.wl_surface_attach(surface, null, 0, 0);
        c.wl_surface_commit(surface);
        if (c.wl_display_flush(display) < 0) return error.Dispatch;
    }
}

const WindowPoll = struct {
    fn poll(descriptors: []std.posix.pollfd, timeout: i32) c_int {
        return std.posix.system.poll(
            descriptors.ptr,
            @intCast(descriptors.len),
            timeout,
        );
    }

    fn errno(result: c_int) std.posix.E {
        return std.posix.errno(result);
    }
};

const WindowPollResult = union(enum) {
    interrupted,
    ready: usize,
};

const WindowPollActions = struct {
    drain_boundary: bool,
    dispatch_display: bool,
};

fn classifyWindowPoll(
    result: WindowPollResult,
    descriptors: *const [2]std.posix.pollfd,
) WindowPollActions {
    return switch (result) {
        .interrupted => .{ .drain_boundary = false, .dispatch_display = false },
        .ready => |ready| .{
            .drain_boundary = ready > 0 and descriptors[1].revents & std.posix.POLL.IN != 0,
            .dispatch_display = ready > 0 and descriptors[0].revents & std.posix.POLL.IN != 0,
        },
    };
}

fn waitWindowEvents(
    comptime Ops: type,
    descriptors: []std.posix.pollfd,
) error{Dispatch}!WindowPollResult {
    for (descriptors) |*descriptor| descriptor.revents = 0;
    const result = Ops.poll(descriptors, -1);
    if (result >= 0) return .{ .ready = std.math.cast(usize, result) orelse return error.Dispatch };
    if (Ops.errno(result) == .INTR) return .interrupted;
    return error.Dispatch;
}

test "Window poll preserves indefinite ownership failure and clean readiness facts" {
    const Ready = struct {
        var timeout: i32 = 0;
        var revents_clean: bool = false;

        fn poll(descriptors: []std.posix.pollfd, value: i32) c_int {
            timeout = value;
            revents_clean = descriptors[0].revents == 0 and descriptors[1].revents == 0;
            descriptors[1].revents = std.posix.POLL.IN;
            return 1;
        }

        fn errno(_: c_int) std.posix.E {
            return .SUCCESS;
        }
    };
    var descriptors = [_]std.posix.pollfd{
        .{ .fd = 11, .events = std.posix.POLL.IN, .revents = std.posix.POLL.HUP },
        .{ .fd = 12, .events = std.posix.POLL.IN, .revents = std.posix.POLL.ERR },
    };
    const ready = try waitWindowEvents(Ready, &descriptors);
    try std.testing.expectEqual(@as(usize, 1), ready.ready);
    try std.testing.expectEqual(@as(i32, -1), Ready.timeout);
    try std.testing.expect(Ready.revents_clean);
    try std.testing.expectEqual(@as(i16, 0), descriptors[0].revents);
    try std.testing.expect(descriptors[1].revents & std.posix.POLL.IN != 0);

    const Failure = struct {
        fn poll(_: []std.posix.pollfd, _: i32) c_int {
            return -1;
        }

        fn errno(_: c_int) std.posix.E {
            return .NOMEM;
        }
    };
    try std.testing.expectError(error.Dispatch, waitWindowEvents(Failure, &descriptors));

    const Interrupted = struct {
        var revents_clean: bool = false;

        fn poll(values: []std.posix.pollfd, timeout: i32) c_int {
            revents_clean = timeout == -1 and values[0].revents == 0 and values[1].revents == 0;
            values[0].revents = std.posix.POLL.IN;
            values[1].revents = std.posix.POLL.IN;
            return -1;
        }

        fn errno(_: c_int) std.posix.E {
            return .INTR;
        }
    };
    descriptors[0].revents = std.posix.POLL.HUP;
    descriptors[1].revents = std.posix.POLL.ERR;
    const interrupted = try waitWindowEvents(Interrupted, &descriptors);
    try std.testing.expect(interrupted == .interrupted);
    try std.testing.expect(Interrupted.revents_clean);

    try std.testing.expectEqual(
        WindowPollActions{ .drain_boundary = false, .dispatch_display = false },
        classifyWindowPoll(interrupted, &descriptors),
    );
    descriptors[0].revents = std.posix.POLL.IN;
    descriptors[1].revents = 0;
    try std.testing.expectEqual(
        WindowPollActions{ .drain_boundary = false, .dispatch_display = true },
        classifyWindowPoll(.{ .ready = 1 }, &descriptors),
    );
    descriptors[0].revents = 0;
    descriptors[1].revents = std.posix.POLL.IN;
    try std.testing.expectEqual(
        WindowPollActions{ .drain_boundary = true, .dispatch_display = false },
        classifyWindowPoll(.{ .ready = 1 }, &descriptors),
    );
    descriptors[0].revents = std.posix.POLL.IN;
    descriptors[1].revents = std.posix.POLL.IN;
    try std.testing.expectEqual(
        WindowPollActions{ .drain_boundary = true, .dispatch_display = true },
        classifyWindowPoll(.{ .ready = 2 }, &descriptors),
    );
    descriptors[0].revents = std.posix.POLL.HUP;
    descriptors[1].revents = std.posix.POLL.ERR;
    try std.testing.expectEqual(
        WindowPollActions{ .drain_boundary = false, .dispatch_display = false },
        classifyWindowPoll(.{ .ready = 1 }, &descriptors),
    );
}

fn constructRing(state: *State, offered: window_render_boundary.OfferedRing) !void {
    const config = offered.config;
    var offers = offered.slots;
    defer for (&offers) |*offer| {
        if (offer.dma_fd >= 0) closeDescriptor(offer.dma_fd);
        if (offer.acquire_timeline_fd >= 0) closeDescriptor(offer.acquire_timeline_fd);
        if (offer.release_timeline_fd >= 0) closeDescriptor(offer.release_timeline_fd);
    };
    if (config.generation != offers[0].generation or
        config.physical_width != offers[0].width or
        config.physical_height != offers[0].height)
        return error.StaleOffer;
    var next = Ring{
        .generation = offers[0].generation,
        .width = offers[0].width,
        .height = offers[0].height,
        .logical_width = config.logical_width,
        .logical_height = config.logical_height,
        .buffer_scale = config.buffer_scale,
        .use_viewport = config.use_viewport,
    };
    errdefer next.deinit();
    for (0..offers.len) |slot| {
        const offer = &offers[slot];
        if (offer.plane_count == 0 or offer.plane_count > window_render_boundary.plane_limit) return error.InvalidPlane;
        const params = c.zwp_linux_dmabuf_v1_create_params(state.dmabuf.?) orelse return error.Buffer;
        defer c.zwp_linux_buffer_params_v1_destroy(params);
        for (0..offer.plane_count) |plane| {
            const layout = offer.planes[plane];
            const modifier = state.boundary.readFeedback().?.modifier;
            c.zwp_linux_buffer_params_v1_add(params, offer.dma_fd, @intCast(plane), layout.offset, layout.stride, @intCast(modifier >> 32), @intCast(modifier & 0xffff_ffff));
        }
        next.buffers[slot] = c.zwp_linux_buffer_params_v1_create_immed(params, @intCast(next.width), @intCast(next.height), state.boundary.readFeedback().?.fourcc, 0) orelse return error.Buffer;
        next.acquire_timelines[slot] = c.wp_linux_drm_syncobj_manager_v1_import_timeline(state.syncobj.?, offer.acquire_timeline_fd) orelse return error.ExplicitSync;
        next.release_timelines[slot] = c.wp_linux_drm_syncobj_manager_v1_import_timeline(state.syncobj.?, offer.release_timeline_fd) orelse return error.ExplicitSync;
        closeDescriptor(offer.dma_fd);
        offer.dma_fd = -1;
        closeDescriptor(offer.acquire_timeline_fd);
        offer.acquire_timeline_fd = -1;
        closeDescriptor(offer.release_timeline_fd);
        offer.release_timeline_fd = -1;
    }
    const old = state.ring;
    state.ring = next;
    next = .{};
    if (old.generation != 0) state.retiring = old;
}

fn present(state: *State, completion: window_render_boundary.Completion) !void {
    if (completion.slot >= window_render_boundary.slot_count or completion.revision <= state.presented) {
        return error.InvalidCompletion;
    }
    if (state.frame_callback != null) return error.PresentationPaced;
    if (completion.generation != state.ring.generation) return error.InvalidCompletion;
    const viewport = if (state.ring.use_viewport or state.fractional_retire_pending)
        state.viewport orelse return error.PresentationPaced
    else
        null;
    const retiring_fractional = if (!state.ring.use_viewport and state.fractional_retire_pending)
        state.fractional_scale orelse return error.PresentationPaced
    else
        null;
    const slot: usize = completion.slot;
    c.wp_linux_drm_syncobj_surface_v1_set_acquire_point(state.sync_surface.?, state.ring.acquire_timelines[slot].?, 0, @intCast(completion.acquire_point));
    c.wp_linux_drm_syncobj_surface_v1_set_release_point(state.sync_surface.?, state.ring.release_timelines[slot].?, 0, @intCast(completion.release_point));
    state.frame_callback = c.wl_surface_frame(state.surface.?) orelse return error.Frame;
    if (c.wl_callback_add_listener(state.frame_callback.?, &frame_listener, state) != 0) return error.Listener;
    const retire_fractional = !state.ring.use_viewport and state.fractional_retire_pending;
    if (state.ring.use_viewport) {
        c.wl_surface_set_buffer_scale(state.surface.?, 1);
        c.wp_viewport_set_destination(viewport.?, @intCast(state.ring.logical_width), @intCast(state.ring.logical_height));
    } else {
        // Removing the viewport request immediately before this commit makes
        // the integer ring and the surface attachment mode one transaction.
        if (retire_fractional) {
            c.wp_viewport_destroy(viewport.?);
            state.viewport = null;
        }
        c.wl_surface_set_buffer_scale(state.surface.?, @intCast(state.ring.buffer_scale));
    }
    c.wl_surface_attach(state.surface.?, state.ring.buffers[slot].?, 0, 0);
    c.wl_surface_damage_buffer(state.surface.?, 0, 0, @intCast(state.ring.width), @intCast(state.ring.height));
    c.wl_surface_commit(state.surface.?);
    if (retire_fractional) {
        c.wp_fractional_scale_v1_destroy(retiring_fractional.?);
        state.fractional_scale = null;
        state.fractional_retire_pending = false;
    }
    state.presented_generation = completion.generation;
    state.presented = completion.revision;
    state.input_ready = true;
    state.ring.presented_mask |= @as(u8, 1) << @intCast(completion.slot);
    state.ring.release_points[slot] = completion.release_point;
    try state.boundary.recordPresentation(completion.generation, completion.slot, completion.release_point);
    if (retire_fractional and state.fractional_manager != null and state.viewporter != null)
        try prepareFractionalSurface(state);
}

fn selectFeedback(state: *const State) ?window_render_boundary.Feedback {
    for (state.formats[0..state.format_count]) |format| {
        if (format.device == state.feedback_device and format.fourcc == 0x34324241) return .{
            .device = state.feedback_device,
            .fourcc = format.fourcc,
            .modifier = format.modifier,
        };
    }
    return null;
}

fn globalAdd(data: ?*anyopaque, registry: ?*c.wl_registry, name: u32, interface: [*c]const u8, version: u32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    const value = std.mem.span(interface);
    if (std.mem.eql(u8, value, "wl_compositor")) {
        const bound_version = @min(version, 6);
        state.compositor = @ptrCast(c.wl_registry_bind(registry, name, &c.wl_compositor_interface, bound_version));
        state.compositor_name = name;
        state.scale.expect_preferred = bound_version >= 6;
    }
    if (std.mem.eql(u8, value, "xdg_wm_base")) {
        state.xdg = @ptrCast(c.wl_registry_bind(registry, name, &c.xdg_wm_base_interface, @min(version, 7)));
        state.xdg_name = name;
    }
    if (std.mem.eql(u8, value, "zwp_linux_dmabuf_v1")) {
        state.dmabuf = @ptrCast(c.wl_registry_bind(registry, name, &c.zwp_linux_dmabuf_v1_interface, @min(version, 5)));
        state.dmabuf_name = name;
    }
    if (std.mem.eql(u8, value, "wp_linux_drm_syncobj_manager_v1")) {
        state.syncobj = @ptrCast(c.wl_registry_bind(registry, name, &c.wp_linux_drm_syncobj_manager_v1_interface, 1));
        state.syncobj_name = name;
    }
    if (std.mem.eql(u8, value, "wp_fractional_scale_manager_v1")) {
        if (state.fractional_manager != null) return;
        state.fractional_manager = @ptrCast(c.wl_registry_bind(registry, name, &c.wp_fractional_scale_manager_v1_interface, @min(version, 1)));
        state.fractional_manager_name = name;
        if (state.surface != null and state.viewporter != null and state.fractional_scale == null)
            prepareFractionalSurface(state) catch state.boundary.requestStop(.window);
    }
    if (std.mem.eql(u8, value, "wp_viewporter")) {
        if (state.viewporter != null) return;
        state.viewporter = @ptrCast(c.wl_registry_bind(registry, name, &c.wp_viewporter_interface, @min(version, 1)));
        state.viewporter_name = name;
        if (state.surface != null and state.fractional_manager != null and state.fractional_scale == null)
            prepareFractionalSurface(state) catch state.boundary.requestStop(.window);
    }
    if (std.mem.eql(u8, value, "wl_seat")) {
        state.seat = @ptrCast(c.wl_registry_bind(registry, name, &c.wl_seat_interface, @min(version, 10)));
        state.seat_name = name;
    }
    if (std.mem.eql(u8, value, "wl_output")) {
        if (state.output_count == output_limit) return state.boundary.requestStop(.window);
        const index = state.output_count;
        const bound = c.wl_registry_bind(registry, name, &c.wl_output_interface, @min(version, 4)) orelse return state.boundary.requestStop(.window);
        state.outputs[index] = .{
            .object = @ptrCast(bound),
            .global_name = name,
        };
        state.output_count += 1;
        if (c.wl_output_add_listener(state.outputs[index].object.?, &output_listener, state) != 0) state.boundary.requestStop(.window);
    }
}
fn globalRemove(data: ?*anyopaque, _: ?*c.wl_registry, name: u32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (name == state.fractional_manager_name) {
        dropFractionalCapability(state);
        if (state.fractional_manager) |value| c.wp_fractional_scale_manager_v1_destroy(value);
        state.fractional_manager = null;
        state.fractional_manager_name = 0;
        return;
    }
    if (name == state.viewporter_name) {
        dropFractionalCapability(state);
        if (state.viewporter) |value| c.wp_viewporter_destroy(value);
        state.viewporter = null;
        state.viewporter_name = 0;
        return;
    }
    if (name == state.compositor_name or name == state.xdg_name or name == state.dmabuf_name or name == state.syncobj_name or name == state.seat_name) {
        state.boundary.requestStop(.window);
        return;
    }
    removeOutput(state, name) catch scaleFailure(state);
}
const registry_listener = c.wl_registry_listener{ .global = globalAdd, .global_remove = globalRemove };

fn removeOutput(state: *State, name: u32) ScaleError!void {
    var index: ?usize = null;
    for (state.outputs[0..state.output_count], 0..) |output, candidate| {
        if (output.global_name == name) {
            index = candidate;
            break;
        }
    }
    const removed_index = index orelse return;
    const old_scale = state.scale;
    const old_count = state.output_count;
    const last_index = old_count - 1;
    const removed = state.outputs[removed_index];
    const moved = state.outputs[last_index];
    if (removed_index != last_index) state.outputs[removed_index] = state.outputs[last_index];
    state.output_count -= 1;
    recomputeScale(state) catch |failure| {
        state.output_count = old_count;
        state.outputs[removed_index] = removed;
        if (removed_index != last_index) state.outputs[last_index] = moved;
        state.scale = old_scale;
        return failure;
    };
    if (removed.object) |output| c.wl_output_destroy(output);
}

fn highestEntered(state: *const State) ScaleError!?Rational {
    var highest: ?Rational = null;
    for (state.outputs[0..state.output_count]) |output| {
        if (!output.entered) continue;
        const scale = try Rational.init(output.scale, 1);
        if (highest == null or @as(u64, scale.numerator) * highest.?.denominator > @as(u64, highest.?.numerator) * scale.denominator) highest = scale;
    }
    return highest;
}

fn recomputeScale(state: *State) ScaleError!void {
    var next = state.scale;
    try next.recompute(try highestEntered(state));
    if (state.configured_width != 0 and
        scaleTransportChanged(state.scale, next))
    {
        try publishConfigureForScale(state, next);
    }
    state.scale = next;
}

fn scaleTransportChanged(current: ScaleFacts, next: ScaleFacts) bool {
    return (current.readiness == .accepted) !=
        (next.readiness == .accepted) or
        next.revision != current.revision or
        !next.accepted_effective.eql(current.accepted_effective);
}

fn physicalExtent(logical: u32, scale_120: u32) ScaleError!u32 {
    if (logical == 0 or scale_120 == 0) return error.InvalidScale;
    const product = std.math.mul(u128, @as(u128, logical), @as(u128, scale_120)) catch return error.ArithmeticOverflow;
    const rounded = std.math.add(u128, product, 60) catch return error.ArithmeticOverflow;
    const value = rounded / 120;
    if (value == 0 or value > window_render_boundary.surface_dimension_limit) return error.ArithmeticOverflow;
    return @intCast(value);
}

fn publishConfigureForScale(state: *State, facts: ScaleFacts) ScaleError!void {
    const scale_120 = try facts.effectiveScale120();
    const physical_width = try physicalExtent(state.configured_width, scale_120);
    const physical_height = try physicalExtent(state.configured_height, scale_120);
    const use_viewport = facts.fractional_capable and facts.preferred_fractional_120 != null;
    const integer_scale = if (use_viewport) 1 else if (scale_120 % 120 == 0) scale_120 / 120 else return error.InvalidScale;
    try state.boundary.publishConfigure(
        state.configured_width,
        state.configured_height,
        physical_width,
        physical_height,
        facts.revision,
        if (facts.readiness == .accepted) .{
            .numerator = facts.accepted_dpi_x.numerator,
            .denominator = facts.accepted_dpi_x.denominator,
        } else null,
        if (facts.readiness == .accepted) .{
            .numerator = facts.accepted_dpi_y.numerator,
            .denominator = facts.accepted_dpi_y.denominator,
        } else null,
        integer_scale,
        use_viewport,
    );
}

fn publishCurrentConfigure(state: *State) ScaleError!void {
    if (state.configured_width == 0 or state.configured_height == 0) return;
    try publishConfigureForScale(state, state.scale);
}

fn outputIndex(state: *const State, output: ?*c.wl_output) ScaleError!usize {
    for (state.outputs[0..state.output_count], 0..) |fact, index| if (fact.object == output) return index;
    return error.UnknownOutput;
}

fn outputScale(state: *State, output: ?*c.wl_output, factor: i32) ScaleError!void {
    if (factor <= 0) return error.InvalidScale;
    const index = try outputIndex(state, output);
    const old_output = state.outputs[index];
    const old_scale = state.scale;
    state.outputs[index].scale = @intCast(factor);
    recomputeScale(state) catch |failure| {
        state.outputs[index] = old_output;
        state.scale = old_scale;
        return failure;
    };
}

fn outputEnter(state: *State, output: ?*c.wl_output) ScaleError!void {
    const index = try outputIndex(state, output);
    if (state.outputs[index].entered) return;
    const old_scale = state.scale;
    state.outputs[index].entered = true;
    recomputeScale(state) catch |failure| {
        state.outputs[index].entered = false;
        state.scale = old_scale;
        return failure;
    };
}

fn outputLeave(state: *State, output: ?*c.wl_output) ScaleError!void {
    const index = try outputIndex(state, output);
    if (!state.outputs[index].entered) return error.UnknownOutput;
    const old_scale = state.scale;
    state.outputs[index].entered = false;
    recomputeScale(state) catch |failure| {
        state.outputs[index].entered = true;
        state.scale = old_scale;
        return failure;
    };
}

fn preferredInteger(state: *State, factor: i32) ScaleError!void {
    if (factor <= 0) return error.InvalidScale;
    const value = try Rational.init(@intCast(factor), 1);
    var next = state.scale;
    next.preferred_integer = value;
    try next.recompute(try highestEntered(state));
    if (state.configured_width != 0 and scaleTransportChanged(state.scale, next))
        try publishConfigureForScale(state, next);
    state.scale = next;
}

fn configureScale(state: *State) ScaleError!void {
    var next = state.scale;
    next.configure_ready = true;
    try next.recompute(try highestEntered(state));
    if (state.configured_width != 0 and scaleTransportChanged(state.scale, next))
        try publishConfigureForScale(state, next);
    state.scale = next;
}

fn scaleFailure(state: *State) void {
    state.boundary.requestStop(.window);
}

const FractionalDrop = enum {
    absent,
    destroy_now,
    retire_after_integer_commit,
};

fn classifyFractionalDrop(
    has_pair: bool,
    ring_uses_viewport: bool,
    offered_ring_uses_viewport: bool,
    retirement_pending: bool,
) FractionalDrop {
    if (!has_pair) return .absent;
    if (ring_uses_viewport or offered_ring_uses_viewport or retirement_pending)
        return .retire_after_integer_commit;
    return .destroy_now;
}

fn dropFractionalCapability(state: *State) void {
    state.scale.fractional_capable = false;
    state.scale.preferred_fractional_120 = null;
    recomputeScale(state) catch scaleFailure(state);
    switch (classifyFractionalDrop(
        state.fractional_scale != null,
        state.ring.use_viewport,
        state.boundary.pendingOffersUseViewport(),
        state.fractional_retire_pending,
    )) {
        .absent => return,
        .retire_after_integer_commit => {
            state.fractional_retire_pending = true;
            return;
        },
        .destroy_now => {},
    }
    if (state.viewport) |value| c.wp_viewport_destroy(value);
    c.wp_fractional_scale_v1_destroy(state.fractional_scale.?);
    state.viewport = null;
    state.fractional_scale = null;
}

fn prepareFractionalSurface(state: *State) !void {
    if (state.fractional_manager == null or state.viewporter == null or state.fractional_scale != null) return;
    const fractional = c.wp_fractional_scale_manager_v1_get_fractional_scale(state.fractional_manager.?, state.surface.?) orelse return;
    errdefer c.wp_fractional_scale_v1_destroy(fractional);
    const viewport = c.wp_viewporter_get_viewport(state.viewporter.?, state.surface.?) orelse return;
    errdefer c.wp_viewport_destroy(viewport);
    if (c.wp_fractional_scale_v1_add_listener(fractional, &fractional_listener, state) != 0) return error.Listener;
    const old_scale = state.scale;
    state.scale.fractional_capable = true;
    recomputeScale(state) catch |failure| {
        state.scale = old_scale;
        return failure;
    };
    state.fractional_scale = fractional;
    state.viewport = viewport;
}

fn surfaceEnter(data: ?*anyopaque, _: ?*c.wl_surface, output: ?*c.wl_output) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    outputEnter(state, output) catch scaleFailure(state);
}

fn surfaceLeave(data: ?*anyopaque, _: ?*c.wl_surface, output: ?*c.wl_output) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    outputLeave(state, output) catch scaleFailure(state);
}

fn surfacePreferredScale(data: ?*anyopaque, _: ?*c.wl_surface, factor: i32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    preferredInteger(state, factor) catch scaleFailure(state);
}

fn surfacePreferredTransform(_: ?*anyopaque, _: ?*c.wl_surface, _: u32) callconv(.c) void {}

fn fractionalPreferredScale(data: ?*anyopaque, object: ?*c.wp_fractional_scale_v1, scale_120: u32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (object != state.fractional_scale or !state.scale.fractional_capable) return;
    if (scale_120 == 0) return scaleFailure(state);
    const old = state.scale;
    state.scale.preferred_fractional_120 = scale_120;
    recomputeScale(state) catch {
        state.scale = old;
        scaleFailure(state);
    };
}

const fractional_listener = c.wp_fractional_scale_v1_listener{ .preferred_scale = fractionalPreferredScale };

const surface_listener = c.wl_surface_listener{
    .enter = surfaceEnter,
    .leave = surfaceLeave,
    .preferred_buffer_scale = surfacePreferredScale,
    .preferred_buffer_transform = surfacePreferredTransform,
};

fn outputGeometry(_: ?*anyopaque, _: ?*c.wl_output, _: i32, _: i32, _: i32, _: i32, _: i32, _: [*c]const u8, _: [*c]const u8, _: i32) callconv(.c) void {}
fn outputMode(_: ?*anyopaque, _: ?*c.wl_output, _: u32, _: i32, _: i32, _: i32) callconv(.c) void {}
fn outputDone(_: ?*anyopaque, _: ?*c.wl_output) callconv(.c) void {}
fn outputScaleEvent(data: ?*anyopaque, output: ?*c.wl_output, factor: i32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    outputScale(state, output, factor) catch scaleFailure(state);
}
fn outputName(_: ?*anyopaque, _: ?*c.wl_output, _: [*c]const u8) callconv(.c) void {}
fn outputDescription(_: ?*anyopaque, _: ?*c.wl_output, _: [*c]const u8) callconv(.c) void {}

const output_listener = c.wl_output_listener{
    .geometry = outputGeometry,
    .mode = outputMode,
    .done = outputDone,
    .scale = outputScaleEvent,
    .name = outputName,
    .description = outputDescription,
};

fn ping(data: ?*anyopaque, wm: ?*c.xdg_wm_base, serial: u32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (wm != state.xdg) state.boundary.requestStop(.window);
    c.xdg_wm_base_pong(state.xdg.?, serial);
}
const xdg_listener = c.xdg_wm_base_listener{ .ping = ping };
fn surfaceConfigure(data: ?*anyopaque, _: ?*c.xdg_surface, serial: u32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    state.configured = true;
    configureScale(state) catch scaleFailure(state);
    if (state.xdg_surface) |surface| c.xdg_surface_ack_configure(surface, serial);
}
const xdg_surface_listener = c.xdg_surface_listener{ .configure = surfaceConfigure };
fn topConfigure(data: ?*anyopaque, _: ?*c.xdg_toplevel, width: i32, height: i32, _: ?*c.wl_array) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (width < 0 or height < 0) {
        state.boundary.requestStop(.window);
        return;
    }
    state.toplevel_configured = true;
    state.boundary.publishInputConfigure(@intCast(width), @intCast(height)) catch inputFailure(state);
    if (width > 0 and height > 0) {
        state.configured_width = @intCast(width);
        state.configured_height = @intCast(height);
        publishCurrentConfigure(state) catch state.boundary.requestStop(.window);
    }
}
fn topClose(data: ?*anyopaque, _: ?*c.xdg_toplevel) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    state.boundary.requestStop(null);
}
fn topBounds(data: ?*anyopaque, _: ?*c.xdg_toplevel, width: i32, height: i32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    // (0, 0) means the compositor has no bound. A single zero is malformed.
    if (width < 0 or height < 0 or ((width == 0) != (height == 0))) state.boundary.requestStop(.window);
}
fn topCaps(data: ?*anyopaque, _: ?*c.xdg_toplevel, capabilities: ?*c.wl_array) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (capabilities) |value| {
        if (value.size % @sizeOf(u32) != 0) state.boundary.requestStop(.window);
    }
}
const toplevel_listener = c.xdg_toplevel_listener{ .configure = topConfigure, .close = topClose, .configure_bounds = topBounds, .wm_capabilities = topCaps };
fn frameDone(data: ?*anyopaque, callback: ?*c.wl_callback, _: u32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (callback) |value| c.wl_callback_destroy(value);
    state.frame_callback = null;
}
const frame_listener = c.wl_callback_listener{ .done = frameDone };

fn fixedPoint(value: c.wl_fixed_t) f64 {
    return @as(f64, @floatFromInt(value)) / 256.0;
}

fn logicalPoint(state: *const State, x: c.wl_fixed_t, y: c.wl_fixed_t) ?wayland.input.Point {
    if (!state.input_ready) return null;
    return .{
        .x = fixedPoint(x),
        .y = fixedPoint(y),
    };
}

fn inputFailure(state: *State) void {
    state.boundary.requestStop(.window);
}

fn seatCapabilities(data: ?*anyopaque, seat: ?*c.wl_seat, capabilities: u32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (seat != state.seat) return state.boundary.requestStop(.window);
    const pointer_capability = (@as(u32, @intCast(c.WL_SEAT_CAPABILITY_POINTER)) & capabilities) != 0;
    if (pointer_capability and state.pointer == null) {
        state.pointer = c.wl_seat_get_pointer(seat) orelse return state.boundary.requestStop(.window);
        if (c.wl_pointer_add_listener(state.pointer.?, &pointer_listener, state) != 0) return state.boundary.requestStop(.window);
    } else if (!pointer_capability and state.pointer != null) {
        c.wl_pointer_destroy(state.pointer.?);
        state.pointer = null;
    }
    const keyboard_capability = (@as(u32, @intCast(c.WL_SEAT_CAPABILITY_KEYBOARD)) & capabilities) != 0;
    if (keyboard_capability and state.keyboard == null) {
        state.keyboard = c.wl_seat_get_keyboard(seat) orelse return state.boundary.requestStop(.window);
        if (c.wl_keyboard_add_listener(state.keyboard.?, &keyboard_listener, state) != 0) return state.boundary.requestStop(.window);
    } else if (!keyboard_capability and state.keyboard != null) {
        c.wl_keyboard_destroy(state.keyboard.?);
        state.keyboard = null;
        if (state.xkb_state) |*value| value.deinit();
        state.xkb_state = null;
        if (state.xkb_keymap) |*value| value.deinit();
        state.xkb_keymap = null;
    }
}

fn seatName(data: ?*anyopaque, seat: ?*c.wl_seat, name: [*c]const u8) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (seat != state.seat or name == null) return state.boundary.requestStop(.window);
    const value = std.mem.span(name);
    if (value.len > 64) return state.boundary.requestStop(.window);
}

const seat_listener = c.wl_seat_listener{ .capabilities = seatCapabilities, .name = seatName };

fn keyboardKeymap(data: ?*anyopaque, keyboard: ?*c.wl_keyboard, format: u32, fd: i32, size: u32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (fd < 0) return state.boundary.requestStop(.window);
    defer if (std.posix.system.close(fd) != 0) @panic("keyboard keymap descriptor cleanup failed");
    if (keyboard != state.keyboard) return state.boundary.requestStop(.window);
    if (format != 1) return state.boundary.requestStop(.window);
    installMappedKeyboardState(NativeMapping, state, fd, size) catch return state.boundary.requestStop(.window);
    state.boundary.publishInput(.{ .keyboard_reset = {} }) catch inputFailure(state);
}

fn installMappedKeyboardState(comptime Mapping: type, state: *State, fd: i32, size: u32) (MappingError || wayland.xkb.Error)!void {
    const mapped = try mapReadOnlyPrivate(Mapping, fd, size, keymap_size_limit);
    defer Mapping.unmap(mapped);
    try replaceKeyboardState(state, mapped);
}

fn replaceKeyboardState(state: *State, bytes: []const u8) wayland.xkb.Error!void {
    var keymap = if (state.xkb_context) |*context| try wayland.xkb.Keymap.fromBuffer(context, bytes) else return error.ContextUnavailable;
    errdefer keymap.deinit();
    const keyboard_state = try wayland.xkb.State.init(&keymap);
    if (state.xkb_state) |*old| old.deinit();
    if (state.xkb_keymap) |*old| old.deinit();
    state.xkb_keymap = keymap;
    state.xkb_state = keyboard_state;
    state.keyboard_semantic_modifiers = .{};
}

fn keyboardEnter(data: ?*anyopaque, keyboard: ?*c.wl_keyboard, serial: u32, surface: ?*c.wl_surface, keys: [*c]c.wl_array) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (keyboard != state.keyboard or surface != state.surface) return state.boundary.requestStop(.window);
    if (keys == null) return state.boundary.requestStop(.window);
    const key_array: *allowzero c.wl_array = &keys[0];
    if (key_array.size != 0 and key_array.data == null) return state.boundary.requestStop(.window);
    const bytes: []const u8 = if (key_array.size == 0)
        &.{}
    else
        @as([*]const u8, @ptrCast(key_array.data))[0..key_array.size];
    const enter = wayland.input.keyboardEnter(serial, bytes) catch return state.boundary.requestStop(.window);
    state.boundary.publishInput(.{ .keyboard_enter = enter }) catch inputFailure(state);
}

fn keyboardLeave(data: ?*anyopaque, keyboard: ?*c.wl_keyboard, serial: u32, surface: ?*c.wl_surface) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (keyboard != state.keyboard or surface != state.surface) return state.boundary.requestStop(.window);
    state.boundary.publishInput(.{ .keyboard_leave = .{ .serial = serial } }) catch inputFailure(state);
}

fn keyboardKey(data: ?*anyopaque, keyboard: ?*c.wl_keyboard, serial: u32, time: u32, key: u32, state_value: u32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (keyboard != state.keyboard) return state.boundary.requestStop(.window);
    const key_state: wayland.input.KeyState = switch (state_value) {
        c.WL_KEYBOARD_KEY_STATE_PRESSED => .pressed,
        c.WL_KEYBOARD_KEY_STATE_RELEASED => .released,
        c.WL_KEYBOARD_KEY_STATE_REPEATED => .repeated,
        else => return state.boundary.requestStop(.window),
    };
    if (key > std.math.maxInt(u32) - 8) return state.boundary.requestStop(.window);
    var text = std.mem.zeroes([wayland.input.key_text_limit]u8);
    const xkb_key = key + 8;
    const keysym = if (state.xkb_state) |*keyboard_state| keyboard_state.keySym(xkb_key) else return state.boundary.requestStop(.window);
    const text_len = if (state.xkb_state) |*keyboard_state| keyboard_state.keyUtf8(xkb_key, &text) catch return state.boundary.requestStop(.window) else return state.boundary.requestStop(.window);
    state.boundary.publishInput(.{ .key = .{ .keycode = key, .time = time, .state = key_state, .serial = serial, .modifiers = state.keyboard_modifiers, .semantic_modifiers = state.keyboard_semantic_modifiers, .keysym = @fromBackingInt(@intCast(keysym)), .text_len = @intCast(text_len), .text = text } }) catch inputFailure(state);
}

fn keyboardModifiers(data: ?*anyopaque, keyboard: ?*c.wl_keyboard, serial: u32, depressed: u32, latched: u32, locked: u32, group: u32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (keyboard != state.keyboard) return state.boundary.requestStop(.window);
    state.keyboard_modifiers = .{ .serial = serial, .depressed = depressed, .latched = latched, .locked = locked, .group = group };
    if (state.xkb_state) |*keyboard_state| {
        if (keyboard_state.updateModifiers(.{ .depressed = depressed, .latched = latched, .locked = locked, .group = group })) {}
        state.keyboard_semantic_modifiers = keyboard_state.semanticModifiers();
    }
    state.boundary.publishModifiers(state.keyboard_modifiers) catch inputFailure(state);
}

fn keyboardRepeat(data: ?*anyopaque, keyboard: ?*c.wl_keyboard, rate: i32, delay: i32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (keyboard != state.keyboard or rate < 0 or delay < 0) return state.boundary.requestStop(.window);
    state.boundary.publishRepeat(.{ .rate = @intCast(rate), .delay = @intCast(delay) }) catch inputFailure(state);
}

const keyboard_listener = c.wl_keyboard_listener{ .keymap = keyboardKeymap, .enter = keyboardEnter, .leave = keyboardLeave, .key = keyboardKey, .modifiers = keyboardModifiers, .repeat_info = keyboardRepeat };

fn pointerEnter(data: ?*anyopaque, pointer: ?*c.wl_pointer, serial: u32, surface: ?*c.wl_surface, x: c.wl_fixed_t, y: c.wl_fixed_t) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (pointer != state.pointer or surface != state.surface) return state.boundary.requestStop(.window);
    state.pointer_motion = null;
    const point = logicalPoint(state, x, y) orelse return;
    state.pointer_motion = .{
        .time = 0,
        .point = point,
        .semantic_modifiers = state.keyboard_semantic_modifiers,
    };
    state.boundary.publishInput(.{ .pointer_enter = .{ .serial = serial, .point = point } }) catch inputFailure(state);
}

fn pointerLeave(data: ?*anyopaque, pointer: ?*c.wl_pointer, serial: u32, surface: ?*c.wl_surface) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (pointer != state.pointer or surface != state.surface) return state.boundary.requestStop(.window);
    state.pointer_motion = null;
    state.boundary.publishInput(.{ .pointer_leave = .{ .serial = serial } }) catch inputFailure(state);
}

fn pointerMotion(data: ?*anyopaque, pointer: ?*c.wl_pointer, time: u32, x: c.wl_fixed_t, y: c.wl_fixed_t) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (pointer != state.pointer) return state.boundary.requestStop(.window);
    state.pointer_motion = .{
        .time = time,
        .point = logicalPoint(state, x, y) orelse return,
        .semantic_modifiers = state.keyboard_semantic_modifiers,
    };
    state.boundary.publishMotion(state.pointer_motion.?) catch inputFailure(state);
}

fn pointerButton(data: ?*anyopaque, pointer: ?*c.wl_pointer, serial: u32, time: u32, button: u32, value: u32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (pointer != state.pointer) return state.boundary.requestStop(.window);
    const button_state: wayland.input.ButtonState = switch (value) {
        c.WL_POINTER_BUTTON_STATE_PRESSED => .pressed,
        c.WL_POINTER_BUTTON_STATE_RELEASED => .released,
        else => return state.boundary.requestStop(.window),
    };
    const motion = state.pointer_motion orelse return state.boundary.requestStop(.window);
    state.boundary.publishInput(.{ .button = .{
        .button = button,
        .time = time,
        .state = button_state,
        .serial = serial,
        .point = motion.point,
        .semantic_modifiers = state.keyboard_semantic_modifiers,
    } }) catch inputFailure(state);
}

fn pointerAxis(data: ?*anyopaque, pointer: ?*c.wl_pointer, time: u32, axis: u32, value: c.wl_fixed_t) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (pointer != state.pointer) return state.boundary.requestStop(.window);
    const point = state.pointer_motion orelse return state.boundary.requestStop(.window);
    const direction: wayland.input.Axis = switch (axis) {
        0 => .vertical,
        1 => .horizontal,
        else => return state.boundary.requestStop(.window),
    };
    state.pointer_axis_motion = point;
    state.boundary.publishInput(.{ .axis = .{ .event = .{ .value = .{ .axis = direction, .time = time, .value = fixedPoint(value) } }, .point = point.point, .semantic_modifiers = state.keyboard_semantic_modifiers } }) catch inputFailure(state);
}

fn pointerFrame(data: ?*anyopaque, pointer: ?*c.wl_pointer) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (pointer != state.pointer) return state.boundary.requestStop(.window);
    const point = takeAxisFramePoint(&state.pointer_axis_motion) orelse return;
    state.boundary.publishInput(.{ .axis = .{ .event = .{ .frame = {} }, .point = point.point, .semantic_modifiers = state.keyboard_semantic_modifiers } }) catch inputFailure(state);
}

fn pointerSource(data: ?*anyopaque, pointer: ?*c.wl_pointer, source: u32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (pointer != state.pointer) return state.boundary.requestStop(.window);
    const point = state.pointer_motion orelse return state.boundary.requestStop(.window);
    const value: wayland.input.AxisSource = switch (source) {
        0 => .wheel,
        1 => .finger,
        2 => .continuous,
        3 => .wheel_tilt,
        else => return state.boundary.requestStop(.window),
    };
    state.pointer_axis_motion = point;
    state.boundary.publishInput(.{ .axis = .{ .event = .{ .source = value }, .point = point.point, .semantic_modifiers = state.keyboard_semantic_modifiers } }) catch inputFailure(state);
}

fn pointerStop(data: ?*anyopaque, pointer: ?*c.wl_pointer, time: u32, axis: u32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (pointer != state.pointer) return state.boundary.requestStop(.window);
    const point = state.pointer_motion orelse return state.boundary.requestStop(.window);
    const direction: wayland.input.Axis = switch (axis) {
        0 => .vertical,
        1 => .horizontal,
        else => return state.boundary.requestStop(.window),
    };
    state.pointer_axis_motion = point;
    state.boundary.publishInput(.{ .axis = .{ .event = .{ .stop = .{ .axis = direction, .time = time } }, .point = point.point, .semantic_modifiers = state.keyboard_semantic_modifiers } }) catch inputFailure(state);
}

fn pointerDiscrete(data: ?*anyopaque, pointer: ?*c.wl_pointer, axis: u32, value: i32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (pointer != state.pointer) return state.boundary.requestStop(.window);
    const point = state.pointer_motion orelse return state.boundary.requestStop(.window);
    const direction: wayland.input.Axis = switch (axis) {
        0 => .vertical,
        1 => .horizontal,
        else => return state.boundary.requestStop(.window),
    };
    state.pointer_axis_motion = point;
    state.boundary.publishInput(.{ .axis = .{ .event = .{ .discrete = .{ .axis = direction, .value = value } }, .point = point.point, .semantic_modifiers = state.keyboard_semantic_modifiers } }) catch inputFailure(state);
}

fn pointerValue120(data: ?*anyopaque, pointer: ?*c.wl_pointer, axis: u32, value: i32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (pointer != state.pointer) return state.boundary.requestStop(.window);
    const point = state.pointer_motion orelse return state.boundary.requestStop(.window);
    const direction: wayland.input.Axis = switch (axis) {
        0 => .vertical,
        1 => .horizontal,
        else => return state.boundary.requestStop(.window),
    };
    state.pointer_axis_motion = point;
    state.boundary.publishInput(.{ .axis = .{ .event = .{ .value120 = .{ .axis = direction, .value = value } }, .point = point.point, .semantic_modifiers = state.keyboard_semantic_modifiers } }) catch inputFailure(state);
}

fn pointerRelativeDirection(data: ?*anyopaque, pointer: ?*c.wl_pointer, axis: u32, direction: u32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (pointer != state.pointer) return state.boundary.requestStop(.window);
    const point = state.pointer_motion orelse return state.boundary.requestStop(.window);
    const value: wayland.input.Axis = switch (axis) {
        0 => .vertical,
        1 => .horizontal,
        else => return state.boundary.requestStop(.window),
    };
    const relative: wayland.input.RelativeDirection = switch (direction) {
        0 => .identical,
        1 => .inverted,
        else => return state.boundary.requestStop(.window),
    };
    state.pointer_axis_motion = point;
    state.boundary.publishInput(.{ .axis = .{ .event = .{ .relative_direction = .{ .axis = value, .direction = relative } }, .point = point.point, .semantic_modifiers = state.keyboard_semantic_modifiers } }) catch inputFailure(state);
}

fn takeAxisFramePoint(point: *?wayland.input.Motion) ?wayland.input.Motion {
    const result = point.*;
    point.* = null;
    return result;
}

const pointer_listener = c.wl_pointer_listener{ .enter = pointerEnter, .leave = pointerLeave, .motion = pointerMotion, .button = pointerButton, .axis = pointerAxis, .frame = pointerFrame, .axis_source = pointerSource, .axis_stop = pointerStop, .axis_discrete = pointerDiscrete, .axis_value120 = pointerValue120, .axis_relative_direction = pointerRelativeDirection };

test "pointer frame consumes only retained axis occurrence position" {
    var none: ?wayland.input.Motion = null;
    try std.testing.expect(takeAxisFramePoint(&none) == null);
    const expected = wayland.input.Motion{
        .time = 9,
        .point = .{ .x = 4, .y = 7 },
        .semantic_modifiers = .{ .shift = true },
    };
    var retained: ?wayland.input.Motion = expected;
    try std.testing.expectEqual(expected, takeAxisFramePoint(&retained).?);
    try std.testing.expect(retained == null);
    try std.testing.expect(takeAxisFramePoint(&retained) == null);
}

test "Wayland pointer coordinates remain in the active logical surface space" {
    var state = State{ .boundary = undefined };
    try std.testing.expect(logicalPoint(&state, 10 * 256, 10 * 256) == null);

    state.input_ready = true;
    try std.testing.expectEqual(wayland.input.Point{ .x = 100, .y = 80 }, logicalPoint(&state, 100 * 256, 80 * 256).?);

    // Constructing a replacement ring does not change the compositor-logical
    // coordinate space used by accepted topology before its first commit.
    state.ring = .{
        .generation = 2,
        .width = 150,
        .height = 120,
        .logical_width = 100,
        .logical_height = 80,
    };
    try std.testing.expectEqual(wayland.input.Point{ .x = 50, .y = 40 }, logicalPoint(&state, 50 * 256, 40 * 256).?);
}

test "Wayland surface listener handles preferred transform events" {
    try std.testing.expect(surface_listener.preferred_buffer_transform != null);
}

test "Wayland fractional scale gate, precedence, rounding and stale callbacks" {
    try std.testing.expect(fractional_listener.preferred_scale != null);
    try std.testing.expectEqual(@as(u32, 100), try physicalExtent(100, 120));
    try std.testing.expectEqual(@as(u32, 125), try physicalExtent(100, 150));
    try std.testing.expectEqual(@as(u32, 667), try physicalExtent(640, 125));
    try std.testing.expectError(error.InvalidScale, physicalExtent(0, 120));
    try std.testing.expectError(error.ArithmeticOverflow, physicalExtent(window_render_boundary.surface_dimension_limit, 240));

    var facts = ScaleFacts{ .bootstrap_ready = true, .expect_preferred = true, .configure_ready = true, .fractional_capable = true };
    facts.preferred_integer = try Rational.init(2, 1);
    facts.preferred_fractional_120 = 180;
    try facts.recompute(null);
    try std.testing.expectEqual(try Rational.init(3, 2), facts.effective);
    try std.testing.expectEqual(@as(u64, 1), facts.revision);
    facts.preferred_fractional_120 = null;
    try facts.recompute(null);
    try std.testing.expectEqual(try Rational.init(2, 1), facts.effective);
    try std.testing.expectEqual(@as(u64, 2), facts.revision);

    facts.preferred_integer = null;
    facts.configure_ready = true;
    try facts.recompute(null);
    try std.testing.expectEqual(ScaleReadiness.awaiting_compositor, facts.readiness);
    try std.testing.expectEqual(@as(u64, 2), facts.revision);

    var state: State = .{ .boundary = undefined, .fractional_scale = @ptrFromInt(1), .scale = .{ .fractional_capable = true } };
    state.scale.preferred_fractional_120 = 180;
    const before = state.scale;
    fractionalPreferredScale(&state, @ptrFromInt(2), 240);
    try std.testing.expectEqual(before, state.scale);
}

test "fractional capability removal retains a pair required by active or offered rings" {
    try std.testing.expectEqual(FractionalDrop.absent, classifyFractionalDrop(false, false, false, false));
    try std.testing.expectEqual(FractionalDrop.destroy_now, classifyFractionalDrop(true, false, false, false));
    try std.testing.expectEqual(FractionalDrop.retire_after_integer_commit, classifyFractionalDrop(true, true, false, false));
    try std.testing.expectEqual(FractionalDrop.retire_after_integer_commit, classifyFractionalDrop(true, false, true, false));
    try std.testing.expectEqual(FractionalDrop.retire_after_integer_commit, classifyFractionalDrop(true, false, false, true));
}

test "Window publishes integer and fractional logical/physical ring facts" {
    var boundary = try window_render_boundary.Boundary.init(std.testing.io);
    defer boundary.deinit();
    var state = State{
        .boundary = &boundary,
        .configured_width = 100,
        .configured_height = 80,
        .scale = .{
            .effective = try Rational.init(2, 1),
            .accepted_effective = try Rational.init(2, 1),
            .accepted_valid = true,
            .revision = 1,
        },
    };
    try publishCurrentConfigure(&state);
    const integer = boundary.takeConfigure().?;
    try std.testing.expectEqual(@as(u32, 200), integer.physical_width);
    try std.testing.expectEqual(@as(u32, 2), integer.buffer_scale);
    try std.testing.expect(!integer.use_viewport);

    state.scale.fractional_capable = true;
    state.scale.preferred_fractional_120 = 180;
    state.scale.effective = try Rational.init(3, 2);
    state.scale.revision = 2;
    try publishCurrentConfigure(&state);
    const fractional = boundary.takeConfigure().?;
    try std.testing.expectEqual(@as(u32, 150), fractional.physical_width);
    try std.testing.expectEqual(@as(u32, 1), fractional.buffer_scale);
    try std.testing.expect(fractional.use_viewport);
}

test "Wayland scale precedence and accepted revisions are transactional" {
    var facts = ScaleFacts{ .bootstrap_ready = true };
    try facts.recompute(null);
    try std.testing.expectEqual(ScaleReadiness.provisional, facts.readiness);
    try std.testing.expectEqual(@as(u64, 0), facts.revision);

    try facts.recompute(try Rational.init(2, 1));
    try std.testing.expectEqual(try Rational.init(2, 1), facts.effective);
    try std.testing.expectEqual(@as(u64, 1), facts.revision);

    facts.expect_preferred = true;
    facts.configure_ready = false;
    try facts.recompute(null);
    try std.testing.expectEqual(ScaleReadiness.awaiting_compositor, facts.readiness);
    try std.testing.expectEqual(@as(u64, 1), facts.revision);

    facts.preferred_integer = try Rational.init(3, 1);
    try facts.recompute(null);
    try std.testing.expectEqual(ScaleReadiness.awaiting_compositor, facts.readiness);
    facts.configure_ready = true;
    try facts.recompute(null);
    try std.testing.expectEqual(try Rational.init(3, 1), facts.effective);
    try std.testing.expectEqual(Rational{ .numerator = 288, .denominator = 1 }, facts.dpi_x);
    try std.testing.expectEqual(@as(u64, 2), facts.revision);

    const before_deduced = facts;
    try facts.recompute(try Rational.init(4, 1));
    try std.testing.expectEqual(@as(u64, 2), facts.revision);
    try std.testing.expect(!std.mem.eql(u8, std.mem.asBytes(&before_deduced), std.mem.asBytes(&facts)));
}

test "Wayland configure without preferred scale continues awaiting until later callback" {
    var state: State = .{ .boundary = undefined };
    state.output_count = 0;
    state.scale = .{ .bootstrap_ready = true, .expect_preferred = true };

    try configureScale(&state);
    try std.testing.expectEqual(ScaleReadiness.provisional, state.scale.readiness);
    try std.testing.expectEqual(@as(u64, 0), state.scale.revision);

    try preferredInteger(&state, 2);
    try std.testing.expectEqual(ScaleReadiness.accepted, state.scale.readiness);
    try std.testing.expectEqual(@as(u64, 1), state.scale.revision);
    try std.testing.expectEqual(try Rational.init(2, 1), state.scale.effective);
}

test "Wayland output membership selects highest deduced scale and retains last snapshot" {
    var state: State = .{ .boundary = undefined };
    state.output_count = 2;
    const first: *c.wl_output = @ptrFromInt(1);
    const second: *c.wl_output = @ptrFromInt(2);
    state.outputs[0] = .{ .object = first, .scale = 2 };
    state.outputs[1] = .{ .object = second, .scale = 3 };
    state.scale = .{ .bootstrap_ready = true };
    try std.testing.expectEqual(@as(u64, 0), state.scale.revision);
    try outputEnter(&state, first);
    try outputEnter(&state, second);
    try std.testing.expectEqual(try Rational.init(3, 1), state.scale.effective);
    try outputLeave(&state, second);
    try std.testing.expectEqual(try Rational.init(2, 1), state.scale.effective);
    try outputLeave(&state, first);
    try std.testing.expectEqual(ScaleReadiness.awaiting_compositor, state.scale.readiness);
    try std.testing.expectEqual(@as(u64, 3), state.scale.revision);
    try std.testing.expectError(error.UnknownOutput, outputLeave(&state, first));
}

test "Wayland provisional and invalid scale changes preserve bytes" {
    var facts = ScaleFacts{ .bootstrap_ready = true, .expect_preferred = true };
    const before = facts;
    try std.testing.expectError(error.InvalidScale, Rational.init(0, 120));
    try std.testing.expectError(error.InvalidScale, Rational.init(2880, 120));
    try std.testing.expectError(error.InvalidScale, Rational.init(1, 0));
    try std.testing.expectEqual(before, facts);
    try facts.recompute(null);
    try std.testing.expectEqual(ScaleReadiness.provisional, facts.readiness);
    try std.testing.expectEqual(@as(u64, 0), facts.revision);

    facts.bootstrap_ready = true;
    facts.configure_ready = true;
    facts.preferred_integer = try Rational.init(1, 1);
    try facts.recompute(null);
    facts.revision = std.math.maxInt(u64);
    facts.accepted_valid = true;
    facts.accepted_effective = facts.effective;
    const exhausted = facts;
    var state: State = .{ .boundary = undefined };
    state.output_count = 0;
    state.scale = exhausted;
    try std.testing.expectError(error.RevisionExhausted, preferredInteger(&state, 2));
    try std.testing.expectEqual(exhausted, state.scale);
}

test "Wayland invalid callback facts preserve output membership and scale bytes" {
    var state: State = .{ .boundary = undefined };
    const output: *c.wl_output = @ptrFromInt(3);
    state.output_count = 1;
    state.outputs[0] = .{ .object = output, .scale = 2, .entered = true };
    state.scale = .{ .bootstrap_ready = true };
    try recomputeScale(&state);
    const before_output = state.outputs[0];
    const before_scale = state.scale;
    try std.testing.expectError(error.InvalidScale, outputScale(&state, output, 24));
    try std.testing.expectEqual(before_output, state.outputs[0]);
    try std.testing.expectEqual(before_scale, state.scale);
    try std.testing.expectError(error.UnknownOutput, outputEnter(&state, @ptrFromInt(4)));
    try std.testing.expectEqual(before_output, state.outputs[0]);
    try std.testing.expectEqual(before_scale, state.scale);
}

test "Wayland output removal is harmless, recomputes membership, and reuses slots" {
    var state: State = .{ .boundary = undefined };
    state.output_count = 3;
    state.outputs[0] = .{ .global_name = 50, .scale = 2, .entered = true };
    state.outputs[1] = .{ .global_name = 60, .scale = 3, .entered = true };
    state.outputs[2] = .{ .global_name = 70, .scale = 5, .entered = false };
    state.scale = .{ .bootstrap_ready = true };
    try recomputeScale(&state);
    try std.testing.expectEqual(try Rational.init(3, 1), state.scale.effective);

    try removeOutput(&state, 999);
    try std.testing.expectEqual(@as(u8, 3), state.output_count);
    try removeOutput(&state, 70);
    try std.testing.expectEqual(@as(u8, 2), state.output_count);
    try removeOutput(&state, 60);
    try std.testing.expectEqual(@as(u8, 1), state.output_count);
    try std.testing.expectEqual(@as(u32, 50), state.outputs[0].global_name);
    try std.testing.expectEqual(try Rational.init(2, 1), state.scale.effective);

    const accepted_effective = state.scale.accepted_effective;
    const accepted_dpi = state.scale.accepted_dpi_x;
    try removeOutput(&state, 50);
    try std.testing.expectEqual(@as(u8, 0), state.output_count);
    try std.testing.expectEqual(ScaleReadiness.awaiting_compositor, state.scale.readiness);
    try std.testing.expectEqual(accepted_effective, state.scale.accepted_effective);
    try std.testing.expectEqual(accepted_dpi, state.scale.accepted_dpi_x);

    state.outputs[0] = .{ .global_name = 70, .scale = 1 };
    state.output_count = 1;
    try std.testing.expectEqual(@as(u32, 70), state.outputs[0].global_name);
}

test "final output removal publishes absent DPI while retaining accepted scale" {
    var boundary = try window_render_boundary.Boundary.init(std.testing.io);
    defer boundary.deinit();
    var state = State{
        .boundary = &boundary,
        .configured_width = 100,
        .configured_height = 80,
        .output_count = 1,
        .scale = .{ .bootstrap_ready = true },
    };
    state.outputs[0] = .{
        .global_name = 50,
        .scale = 2,
        .entered = true,
    };
    try recomputeScale(&state);
    const accepted = boundary.takeConfigure().?;
    try std.testing.expectEqual(ScaleReadiness.accepted, state.scale.readiness);
    try std.testing.expect(accepted.dpi_x != null);
    try std.testing.expect(accepted.dpi_y != null);
    const accepted_effective = state.scale.accepted_effective;
    const accepted_dpi_x = state.scale.accepted_dpi_x;
    const accepted_revision = state.scale.revision;

    try removeOutput(&state, 50);
    const awaiting = boundary.takeConfigure().?;
    try std.testing.expectEqual(
        ScaleReadiness.awaiting_compositor,
        state.scale.readiness,
    );
    try std.testing.expectEqual(accepted_revision, state.scale.revision);
    try std.testing.expectEqual(
        accepted_effective,
        state.scale.accepted_effective,
    );
    try std.testing.expectEqual(accepted_dpi_x, state.scale.accepted_dpi_x);
    try std.testing.expectEqual(accepted_revision, awaiting.scale_revision);
    try std.testing.expect(awaiting.dpi_x == null);
    try std.testing.expect(awaiting.dpi_y == null);
}

test "Wayland widened DPI reduction succeeds before storage bounds" {
    const reducible = Rational{ .numerator = 4_000_000_001, .denominator = 288_000_000 };
    try std.testing.expectEqual(
        Rational{ .numerator = 4_000_000_001, .denominator = 3_000_000 },
        try reducible.dpi(),
    );

    const unrepresentable = Rational{ .numerator = std.math.maxInt(u32), .denominator = 1 };
    try std.testing.expectError(error.ArithmeticOverflow, unrepresentable.dpi());
}

test "Window mapping preflights external facts and passes exact typed flags" {
    const FakeMapping = struct {
        var calls: usize = 0;
        var fail: bool = false;
        var ptr: ?[*]align(std.heap.page_size_min) u8 = undefined;
        var size: usize = 0;
        var protection: std.posix.PROT = .{};
        var flags: std.posix.MAP = .{ .TYPE = .PRIVATE };
        var fd: i32 = -1;
        var offset: u64 = 1;
        var storage: [32]u8 align(std.heap.page_size_min) = @splat(0);

        fn reset() void {
            calls = 0;
            fail = false;
            ptr = undefined;
            size = 0;
            protection = .{};
            flags = .{ .TYPE = .PRIVATE };
            fd = -1;
            offset = 1;
        }

        fn map(candidate_ptr: ?[*]align(std.heap.page_size_min) u8, candidate_size: usize, candidate_protection: std.posix.PROT, candidate_flags: std.posix.MAP, candidate_fd: i32, candidate_offset: u64) error{Injected}!MappedBytes {
            calls += 1;
            ptr = candidate_ptr;
            size = candidate_size;
            protection = candidate_protection;
            flags = candidate_flags;
            fd = candidate_fd;
            offset = candidate_offset;
            if (fail) return error.Injected;
            return storage[0..candidate_size];
        }
    };

    FakeMapping.reset();
    try std.testing.expectError(error.InvalidDescriptor, mapReadOnlyPrivate(FakeMapping, -1, 16, 32));
    try std.testing.expectError(error.InvalidSize, mapReadOnlyPrivate(FakeMapping, 7, 0, 32));
    try std.testing.expectError(error.InvalidSize, mapReadOnlyPrivate(FakeMapping, 7, 33, 32));
    try std.testing.expectEqual(@as(usize, 0), FakeMapping.calls);

    FakeMapping.fail = true;
    try std.testing.expectError(error.MappingFailed, mapReadOnlyPrivate(FakeMapping, 7, 16, 32));
    try std.testing.expectEqual(@as(usize, 1), FakeMapping.calls);

    FakeMapping.fail = false;
    const mapped = try mapReadOnlyPrivate(FakeMapping, 9, 16, 32);
    try std.testing.expectEqual(@as(usize, 16), mapped.len);
    try std.testing.expect(FakeMapping.ptr == null);
    try std.testing.expectEqual(@as(usize, 16), FakeMapping.size);
    try std.testing.expectEqual(std.posix.PROT{ .READ = true }, FakeMapping.protection);
    try std.testing.expectEqual(std.posix.MAP{ .TYPE = .PRIVATE }, FakeMapping.flags);
    try std.testing.expectEqual(@as(i32, 9), FakeMapping.fd);
    try std.testing.expectEqual(@as(u64, 0), FakeMapping.offset);
}

test "Window retained feedback mapping ownership group remains 24 bytes" {
    const PreviousFeedbackFacts = struct {
        fd: i32 = -1,
        size: usize = 0,
        pointer: ?[*]const u8 = null,
    };
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(MappedBytes));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(MappedBytes));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(FeedbackMapping));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(FeedbackMapping));
    try std.testing.expectEqual(@sizeOf(PreviousFeedbackFacts), @sizeOf(FeedbackMapping));
    try std.testing.expectEqual(@alignOf(PreviousFeedbackFacts), @alignOf(FeedbackMapping));
}

test "Window feedback mapping owns one slice and tears down in reverse order" {
    const FakeMapping = struct {
        const Event = enum { unmap, close };
        var fail: bool = false;
        var map_calls: usize = 0;
        var events: [4]Event = undefined;
        var event_count: usize = 0;
        var closed_fd: i32 = -1;
        var unmapped_len: usize = 0;
        var even_storage: [32]u8 align(std.heap.page_size_min) = @splat(0);
        var odd_storage: [32]u8 align(std.heap.page_size_min) = @splat(0);

        fn reset() void {
            fail = false;
            map_calls = 0;
            event_count = 0;
            closed_fd = -1;
            unmapped_len = 0;
        }

        fn map(_: ?[*]align(std.heap.page_size_min) u8, size: usize, _: std.posix.PROT, _: std.posix.MAP, fd: i32, _: u64) error{Injected}!MappedBytes {
            map_calls += 1;
            if (fail) return error.Injected;
            return if (@mod(fd, 2) == 0) even_storage[0..size] else odd_storage[0..size];
        }

        fn unmap(bytes: MappedBytes) void {
            events[event_count] = .unmap;
            event_count += 1;
            unmapped_len = bytes.len;
        }

        fn close(fd: i32) void {
            events[event_count] = .close;
            event_count += 1;
            closed_fd = fd;
        }
    };

    var state: State = .{ .boundary = undefined };
    FakeMapping.reset();
    try std.testing.expectError(error.InvalidDescriptor, installFormatTable(FakeMapping, &state, -1, 16));
    try std.testing.expectEqual(@as(usize, 0), FakeMapping.event_count);
    try std.testing.expectError(error.InvalidSize, installFormatTable(FakeMapping, &state, 3, 0));
    try std.testing.expectEqualSlices(FakeMapping.Event, &.{.close}, FakeMapping.events[0..FakeMapping.event_count]);
    try std.testing.expectEqual(@as(i32, 3), FakeMapping.closed_fd);

    FakeMapping.reset();
    try std.testing.expectError(error.InvalidSize, installFormatTable(FakeMapping, &state, 4, 17));
    try std.testing.expectEqual(@as(usize, 0), FakeMapping.map_calls);
    try std.testing.expectEqualSlices(FakeMapping.Event, &.{.close}, FakeMapping.events[0..FakeMapping.event_count]);

    FakeMapping.reset();
    try std.testing.expectError(error.InvalidSize, installFormatTable(FakeMapping, &state, 4, format_table_size_limit + 1));
    try std.testing.expectEqual(@as(usize, 0), FakeMapping.map_calls);
    try std.testing.expectEqualSlices(FakeMapping.Event, &.{.close}, FakeMapping.events[0..FakeMapping.event_count]);

    FakeMapping.reset();
    FakeMapping.fail = true;
    try std.testing.expectError(error.MappingFailed, installFormatTable(FakeMapping, &state, 5, 16));
    try std.testing.expectEqual(@as(usize, 1), FakeMapping.map_calls);
    try std.testing.expectEqualSlices(FakeMapping.Event, &.{.close}, FakeMapping.events[0..FakeMapping.event_count]);

    FakeMapping.reset();
    try installFormatTable(FakeMapping, &state, 6, 16);
    try std.testing.expectEqual(@as(usize, 0), FakeMapping.event_count);
    try std.testing.expectEqual(@as(i32, 6), state.format_table.fd);
    try std.testing.expectEqual(@as(usize, 16), state.format_table.bytes.len);
    const retained = state.format_table;

    FakeMapping.reset();
    try std.testing.expectError(error.InvalidSize, installFormatTable(FakeMapping, &state, 9, 17));
    try std.testing.expectEqual(retained.fd, state.format_table.fd);
    try std.testing.expectEqual(retained.bytes.ptr, state.format_table.bytes.ptr);
    try std.testing.expectEqual(retained.bytes.len, state.format_table.bytes.len);
    try std.testing.expectEqualSlices(FakeMapping.Event, &.{.close}, FakeMapping.events[0..FakeMapping.event_count]);
    try std.testing.expectEqual(@as(i32, 9), FakeMapping.closed_fd);

    FakeMapping.reset();
    FakeMapping.fail = true;
    try std.testing.expectError(error.MappingFailed, installFormatTable(FakeMapping, &state, 7, 16));
    try std.testing.expectEqual(retained.fd, state.format_table.fd);
    try std.testing.expectEqual(retained.bytes.ptr, state.format_table.bytes.ptr);
    try std.testing.expectEqual(retained.bytes.len, state.format_table.bytes.len);
    try std.testing.expectEqualSlices(FakeMapping.Event, &.{.close}, FakeMapping.events[0..FakeMapping.event_count]);
    try std.testing.expectEqual(@as(i32, 7), FakeMapping.closed_fd);

    FakeMapping.reset();
    try installFormatTable(FakeMapping, &state, 7, 16);
    try std.testing.expectEqual(@as(i32, 7), state.format_table.fd);
    try std.testing.expect(state.format_table.bytes.ptr != retained.bytes.ptr);
    try std.testing.expectEqualSlices(FakeMapping.Event, &.{ .unmap, .close }, FakeMapping.events[0..FakeMapping.event_count]);
    try std.testing.expectEqual(@as(i32, 6), FakeMapping.closed_fd);

    FakeMapping.reset();
    try installFormatTable(FakeMapping, &state, 8, 16);
    try std.testing.expectEqual(@as(i32, 8), state.format_table.fd);
    try std.testing.expectEqualSlices(FakeMapping.Event, &.{ .unmap, .close }, FakeMapping.events[0..FakeMapping.event_count]);
    try std.testing.expectEqual(@as(i32, 7), FakeMapping.closed_fd);

    FakeMapping.reset();
    state.format_table.deinit(FakeMapping);
    try std.testing.expectEqualSlices(FakeMapping.Event, &.{ .unmap, .close }, FakeMapping.events[0..FakeMapping.event_count]);
    try std.testing.expectEqual(@as(usize, 16), FakeMapping.unmapped_len);
    try std.testing.expectEqual(@as(i32, 8), FakeMapping.closed_fd);
}

test "Window feedback parsing is bounded by the retained mapped slice" {
    var table_bytes: [32]u8 align(std.heap.page_size_min) = @splat(0);
    std.mem.writeInt(u32, table_bytes[0..4], 0x34325258, .native);
    std.mem.writeInt(u64, table_bytes[8..16], 0x0102030405060708, .native);
    std.mem.writeInt(u32, table_bytes[16..20], 0x34325241, .native);
    std.mem.writeInt(u64, table_bytes[24..32], 0x1112131415161718, .native);
    var state: State = .{
        .boundary = undefined,
        .format_table = .{ .fd = 4, .bytes = table_bytes[0..16] },
        .tranche_device = 99,
    };
    var indices = [_]u8{ 0, 0, 1, 0 };
    retainTrancheFormats(&state, &indices);
    try std.testing.expectEqual(@as(u8, 1), state.format_count);
    try std.testing.expectEqual(@as(u32, 0x34325258), state.formats[0].fourcc);
    try std.testing.expectEqual(@as(u64, 0x0102030405060708), state.formats[0].modifier);
    try std.testing.expectEqual(@as(u64, 99), state.formats[0].device);

    const before = state.formats[0];
    retainTrancheFormats(&state, &.{0});
    try std.testing.expectEqual(@as(u8, 1), state.format_count);
    try std.testing.expectEqual(before, state.formats[0]);
}

test "Window mapped keymap failure unmaps and preserves accepted XKB ownership" {
    const fixture =
        "xkb_keymap {" ++
        " xkb_keycodes \"minimal\" { minimum = 8; maximum = 255; <ESC> = 9; };" ++
        " xkb_types \"minimal\" { virtual_modifiers None; type \"ONE_LEVEL\" { modifiers = none; map[None] = Level1; level_name[Level1] = \"Any\"; }; };" ++
        " xkb_compatibility \"minimal\" { interpret Any+Any { action = NoAction(); }; };" ++
        " xkb_symbols \"minimal\" { key <ESC> { [ Escape ] }; };" ++
        " xkb_geometry \"minimal\" { }; };";
    const FakeMapping = struct {
        var unmap_count: usize = 0;
        var storage: [32]u8 align(std.heap.page_size_min) = @splat(0);

        fn map(_: ?[*]align(std.heap.page_size_min) u8, size: usize, _: std.posix.PROT, _: std.posix.MAP, _: i32, _: u64) !MappedBytes {
            return storage[0..size];
        }

        fn unmap(_: MappedBytes) void {
            unmap_count += 1;
        }
    };

    var context = try wayland.xkb.Context.init();
    var state: State = .{ .boundary = undefined, .xkb_context = context };
    context = undefined;
    defer {
        if (state.xkb_state) |*value| value.deinit();
        if (state.xkb_keymap) |*value| value.deinit();
        if (state.xkb_context) |*value| value.deinit();
    }
    try replaceKeyboardState(&state, fixture);
    var keymap_before: [@sizeOf(?wayland.xkb.Keymap)]u8 = undefined;
    @memcpy(&keymap_before, std.mem.asBytes(&state.xkb_keymap));
    var state_before: [@sizeOf(?wayland.xkb.State)]u8 = undefined;
    @memcpy(&state_before, std.mem.asBytes(&state.xkb_state));
    @memcpy(FakeMapping.storage[0..16], "not a keymap!!!!");
    FakeMapping.unmap_count = 0;
    try std.testing.expectError(error.InvalidKeymap, installMappedKeyboardState(FakeMapping, &state, 8, 16));
    try std.testing.expectEqual(@as(usize, 1), FakeMapping.unmap_count);
    try std.testing.expectEqualSlices(u8, &keymap_before, std.mem.asBytes(&state.xkb_keymap));
    try std.testing.expectEqualSlices(u8, &state_before, std.mem.asBytes(&state.xkb_state));
}

fn feedbackDone(data: ?*anyopaque, _: ?*c.zwp_linux_dmabuf_feedback_v1) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    state.feedback_complete = true;
}
fn formatTable(data: ?*anyopaque, _: ?*c.zwp_linux_dmabuf_feedback_v1, fd: i32, size: u32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    installFormatTable(NativeMapping, state, fd, size) catch state.boundary.requestStop(.window);
}

fn installFormatTable(comptime Mapping: type, state: *State, fd: i32, size: u32) MappingError!void {
    if (fd < 0) return error.InvalidDescriptor;
    var descriptor_owned = true;
    defer if (descriptor_owned) Mapping.close(fd);
    if (size == 0 or size % format_record_size != 0 or size > format_table_size_limit) return error.InvalidSize;
    const bytes = try mapReadOnlyPrivate(Mapping, fd, size, format_table_size_limit);
    var retiring = state.format_table;
    state.format_table = .{ .fd = fd, .bytes = bytes };
    descriptor_owned = false;
    retiring.deinit(Mapping);
}
fn copyDevice(array: ?*c.wl_array) u64 {
    const value = array orelse return 0;
    if (value.size < 8) return 0;
    var bytes: [8]u8 = undefined;
    @memcpy(&bytes, @as([*]const u8, @ptrCast(value.data))[0..8]);
    return std.mem.bytesToValue(u64, &bytes);
}
fn mainDevice(data: ?*anyopaque, _: ?*c.zwp_linux_dmabuf_feedback_v1, device: ?*c.wl_array) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    state.feedback_device = copyDevice(device);
}
fn trancheDone(data: ?*anyopaque, _: ?*c.zwp_linux_dmabuf_feedback_v1) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    state.tranche_device = 0;
}
fn trancheTarget(data: ?*anyopaque, _: ?*c.zwp_linux_dmabuf_feedback_v1, device: ?*c.wl_array) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    state.tranche_device = copyDevice(device);
}
fn trancheFormats(data: ?*anyopaque, _: ?*c.zwp_linux_dmabuf_feedback_v1, indices: ?*c.wl_array) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    const array = indices orelse return;
    if (array.size != 0 and array.data == null) return;
    const bytes: []const u8 = if (array.size == 0) &.{} else @as([*]const u8, @ptrCast(array.data))[0..array.size];
    retainTrancheFormats(state, bytes);
}

fn retainTrancheFormats(state: *State, indices: []const u8) void {
    const table = state.format_table;
    if (table.fd < 0) return;
    if (indices.len % 2 != 0) return;
    for (0..indices.len / 2) |index| {
        if (state.format_count == format_limit) return;
        var encoded: [2]u8 = undefined;
        @memcpy(&encoded, indices[index * 2 ..][0..2]);
        const table_index = std.mem.bytesToValue(u16, &encoded);
        const offset = @as(usize, table_index) * 16;
        if (offset > table.bytes.len or table.bytes.len - offset < 16) continue;
        state.formats[state.format_count] = .{
            .fourcc = std.mem.bytesToValue(u32, table.bytes[offset..][0..4]),
            .modifier = std.mem.bytesToValue(u64, table.bytes[offset + 8 ..][0..8]),
            .device = state.tranche_device,
        };
        state.format_count += 1;
    }
}
fn trancheFlags(data: ?*anyopaque, _: ?*c.zwp_linux_dmabuf_feedback_v1, flags: u32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (state.feedback_complete or flags & ~@as(u32, 1) != 0) state.boundary.requestStop(.window);
}
const feedback_listener = c.zwp_linux_dmabuf_feedback_v1_listener{
    .done = feedbackDone,
    .format_table = formatTable,
    .main_device = mainDevice,
    .tranche_done = trancheDone,
    .tranche_target_device = trancheTarget,
    .tranche_formats = trancheFormats,
    .tranche_flags = trancheFlags,
};

fn closeDescriptor(descriptor: i32) void {
    if (std.posix.system.close(descriptor) != 0) @panic("Window descriptor cleanup failed");
}
