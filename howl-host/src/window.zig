//! Owns Wayland discovery, dispatch, DMA-BUF wrappers, and presentation.

const std = @import("std");
const c = @import("howl_wayland").c;
const wayland = @import("howl_wayland");
const posix = @import("host_c");
const shared = @import("shared.zig");

const format_limit: usize = 64;

const Ring = struct {
    generation: u64 = 0,
    width: u32 = 0,
    height: u32 = 0,
    buffers: [shared.slot_count]?*c.wl_buffer = .{ null, null, null },
    acquire_timelines: [shared.slot_count]?*c.wp_linux_drm_syncobj_timeline_v1 = .{ null, null, null },
    release_timelines: [shared.slot_count]?*c.wp_linux_drm_syncobj_timeline_v1 = .{ null, null, null },
    presented_mask: u8 = 0,
    release_points: [shared.slot_count]u64 = .{ 0, 0, 0 },

    fn deinit(self: *Ring) void {
        var index = shared.slot_count;
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
    boundary: *shared.Boundary,
    compositor: ?*c.wl_compositor = null,
    xdg: ?*c.xdg_wm_base = null,
    dmabuf: ?*c.zwp_linux_dmabuf_v1 = null,
    syncobj: ?*c.wp_linux_drm_syncobj_manager_v1 = null,
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
    seat_name: u32 = 0,
    configured: bool = false,
    configured_width: u32 = 0,
    configured_height: u32 = 0,
    toplevel_configured: bool = false,
    feedback_complete: bool = false,
    feedback_device: u64 = 0,
    tranche_device: u64 = 0,
    table_fd: i32 = -1,
    table_size: usize = 0,
    table_map: ?[*]const u8 = null,
    formats: [format_limit]struct { fourcc: u32, modifier: u64, device: u64 } = undefined,
    format_count: u8 = 0,
    ring: Ring = .{},
    retiring: ?Ring = null,
    frame_callback: ?*c.wl_callback = null,
    presented_generation: u64 = 0,
    presented: u64 = 0,
    xkb_context: ?wayland.xkb.Context = null,
    xkb_keymap: ?wayland.xkb.Keymap = null,
    xkb_state: ?wayland.xkb.State = null,
    keyboard_modifiers: wayland.input.Modifiers = .{ .serial = 0, .depressed = 0, .latched = 0, .locked = 0, .group = 0 },
    pointer_motion: ?wayland.input.Motion = null,

    fn deinit(self: *State) void {
        if (self.xkb_state) |*value| value.deinit();
        if (self.xkb_keymap) |*value| value.deinit();
        if (self.xkb_context) |*value| value.deinit();
        if (self.keyboard) |value| c.wl_keyboard_destroy(value);
        if (self.pointer) |value| c.wl_pointer_destroy(value);
        if (self.seat) |value| c.wl_seat_destroy(value);
        if (self.frame_callback) |value| c.wl_callback_destroy(value);
        if (self.sync_surface) |value| c.wp_linux_drm_syncobj_surface_v1_destroy(value);
        const retired = if (self.ring.generation == 0) null else shared.RetiredRing{
            .generation = self.ring.generation,
            .presented_mask = self.ring.presented_mask,
            .release_points = self.ring.release_points,
        };
        self.ring.deinit();
        if (retired) |fact| self.boundary.markWindowRingRetired(fact);
        if (self.retiring) |*old| {
            const fact = shared.RetiredRing{ .generation = old.generation, .presented_mask = old.presented_mask, .release_points = old.release_points };
            old.deinit();
            self.boundary.markWindowRingRetired(fact);
            self.retiring = null;
        }
        if (self.toplevel) |value| c.xdg_toplevel_destroy(value);
        if (self.xdg_surface) |value| c.xdg_surface_destroy(value);
        if (self.surface) |value| c.wl_surface_destroy(value);
        if (self.syncobj) |value| c.wp_linux_drm_syncobj_manager_v1_destroy(value);
        if (self.dmabuf) |value| c.zwp_linux_dmabuf_v1_destroy(value);
        if (self.xdg) |value| c.xdg_wm_base_destroy(value);
        if (self.compositor) |value| c.wl_compositor_destroy(value);
        if (self.table_map) |value| {
            if (posix.munmap(@ptrCast(@constCast(value)), self.table_size) != 0) @panic("feedback mapping cleanup failed");
        }
        if (self.table_fd >= 0) closeDescriptor(self.table_fd);
    }
};

/// Runs the sole Wayland owner until the shared Boundary requests retirement.
/// All operational failures are recorded as the first Window runtime failure.
pub fn run(boundary: *shared.Boundary) void {
    runFallible(boundary) catch |failure| {
        std.debug.print("Window failure: {s}\n", .{@errorName(failure)});
        boundary.requestStop(.window);
    };
    boundary.markStopped(.window);
}

fn runFallible(boundary: *shared.Boundary) !void {
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
    state.xdg_surface = c.xdg_wm_base_get_xdg_surface(state.xdg.?, state.surface.?) orelse return error.Surface;
    if (c.xdg_surface_add_listener(state.xdg_surface.?, &xdg_surface_listener, &state) != 0) return error.Listener;
    state.toplevel = c.xdg_surface_get_toplevel(state.xdg_surface.?) orelse return error.Surface;
    if (c.xdg_toplevel_add_listener(state.toplevel.?, &toplevel_listener, &state) != 0) return error.Listener;
    c.xdg_toplevel_set_title(state.toplevel.?, "Howl Vulkan ring");
    c.wl_surface_commit(state.surface.?);
    if (c.wl_display_roundtrip(display) < 0 or !state.configured or !state.toplevel_configured) return error.Configure;
    try boundary.publishConfigure(if (state.configured_width == 0) 640 else state.configured_width, if (state.configured_height == 0) 480 else state.configured_height);
    state.sync_surface = c.wp_linux_drm_syncobj_manager_v1_get_surface(state.syncobj.?, state.surface.?) orelse return error.ExplicitSync;

    const display_fd = c.wl_display_get_fd(display);
    if (display_fd < 0) return error.Dispatch;
    while (!boundary.shouldStop()) {
        if (state.retiring) |*old| if (boundary.takeWindowRingRetirementRequest(old.generation)) {
            const fact = shared.RetiredRing{ .generation = old.generation, .presented_mask = old.presented_mask, .release_points = old.release_points };
            old.deinit();
            state.boundary.markWindowRingRetired(fact);
            state.retiring = null;
        };
        if (state.frame_callback == null) if (boundary.takeOffers()) |offers| {
            try constructRing(&state, offers);
            boundary.markWindowRingReady(offers[0].generation);
        };
        if (state.frame_callback == null) {
            if (boundary.takeCompletion()) |completion| {
                if (completion.generation == state.ring.generation) try present(&state, completion);
            }
        }
        if (c.wl_display_dispatch_pending(display) < 0) return error.Dispatch;
        if (c.wl_display_flush(display) < 0) return error.Dispatch;
        var descriptors = [_]posix.pollfd{
            .{ .fd = display_fd, .events = posix.POLLIN, .revents = 0 },
            .{ .fd = boundary.windowFd(), .events = posix.POLLIN, .revents = 0 },
        };
        const ready = posix.poll(&descriptors, descriptors.len, -1);
        if (ready < 0 and std.posix.errno(ready) != .INTR) return error.Dispatch;
        if (ready > 0 and (descriptors[1].revents & posix.POLLIN) != 0) try boundary.drainWindowWake();
        if (ready > 0 and (descriptors[0].revents & posix.POLLIN) != 0 and c.wl_display_dispatch(display) < 0) return error.Dispatch;
        if (c.wl_display_get_error(display) != 0) return error.Protocol;
    }
    if (state.surface) |surface| {
        c.wl_surface_attach(surface, null, 0, 0);
        c.wl_surface_commit(surface);
        if (c.wl_display_flush(display) < 0) return error.Dispatch;
    }
}

fn constructRing(state: *State, initial_offers: [shared.slot_count]shared.SlotOffer) !void {
    var offers = initial_offers;
    defer for (&offers) |*offer| {
        if (offer.dma_fd >= 0) closeDescriptor(offer.dma_fd);
        if (offer.acquire_timeline_fd >= 0) closeDescriptor(offer.acquire_timeline_fd);
        if (offer.release_timeline_fd >= 0) closeDescriptor(offer.release_timeline_fd);
    };
    var next = Ring{ .generation = offers[0].generation, .width = offers[0].width, .height = offers[0].height };
    errdefer next.deinit();
    for (0..offers.len) |slot| {
        const offer = &offers[slot];
        if (offer.plane_count == 0 or offer.plane_count > shared.plane_limit) return error.InvalidPlane;
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

fn present(state: *State, completion: shared.Completion) !void {
    if (completion.slot >= shared.slot_count or completion.revision <= state.presented) return error.InvalidCompletion;
    if (state.frame_callback != null) return error.PresentationPaced;
    if (completion.generation != state.ring.generation) return error.InvalidCompletion;
    const slot: usize = completion.slot;
    c.wp_linux_drm_syncobj_surface_v1_set_acquire_point(state.sync_surface.?, state.ring.acquire_timelines[slot].?, 0, @intCast(completion.acquire_point));
    c.wp_linux_drm_syncobj_surface_v1_set_release_point(state.sync_surface.?, state.ring.release_timelines[slot].?, 0, @intCast(completion.release_point));
    state.frame_callback = c.wl_surface_frame(state.surface.?) orelse return error.Frame;
    if (c.wl_callback_add_listener(state.frame_callback.?, &frame_listener, state) != 0) return error.Listener;
    c.wl_surface_attach(state.surface.?, state.ring.buffers[slot].?, 0, 0);
    c.wl_surface_damage_buffer(state.surface.?, 0, 0, @intCast(state.ring.width), @intCast(state.ring.height));
    c.wl_surface_commit(state.surface.?);
    state.presented_generation = completion.generation;
    state.presented = completion.revision;
    state.ring.presented_mask |= @as(u8, 1) << @intCast(completion.slot);
    state.ring.release_points[slot] = completion.release_point;
    try state.boundary.recordPresentation(completion.generation, completion.slot, completion.release_point);
    std.debug.print("Window commit generation={d} revision={d} slot={d} acquire={d} release={d}\n", .{ completion.generation, completion.revision, completion.slot, completion.acquire_point, completion.release_point });
}

fn selectFeedback(state: *const State) ?shared.Feedback {
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
    if (std.mem.eql(u8, value, "wl_compositor")) state.compositor = @ptrCast(c.wl_registry_bind(registry, name, &c.wl_compositor_interface, @min(version, 6)));
    if (std.mem.eql(u8, value, "wl_compositor")) state.compositor_name = name;
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
    if (std.mem.eql(u8, value, "wl_seat")) {
        state.seat = @ptrCast(c.wl_registry_bind(registry, name, &c.wl_seat_interface, @min(version, 10)));
        state.seat_name = name;
    }
}
fn globalRemove(data: ?*anyopaque, _: ?*c.wl_registry, name: u32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (name == state.compositor_name or name == state.xdg_name or name == state.dmabuf_name or name == state.syncobj_name or name == state.seat_name) state.boundary.requestStop(.window);
}
const registry_listener = c.wl_registry_listener{ .global = globalAdd, .global_remove = globalRemove };
fn ping(data: ?*anyopaque, wm: ?*c.xdg_wm_base, serial: u32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (wm != state.xdg) state.boundary.requestStop(.window);
    c.xdg_wm_base_pong(state.xdg.?, serial);
}
const xdg_listener = c.xdg_wm_base_listener{ .ping = ping };
fn surfaceConfigure(data: ?*anyopaque, _: ?*c.xdg_surface, serial: u32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    state.configured = true;
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
        state.boundary.publishConfigure(@intCast(width), @intCast(height)) catch state.boundary.requestStop(.window);
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
    std.debug.print("Window frame generation={d} revision={d}\n", .{ state.presented_generation, state.presented });
}
const frame_listener = c.wl_callback_listener{ .done = frameDone };

fn fixedPoint(value: c.wl_fixed_t) f64 {
    return @as(f64, @floatFromInt(value)) / 256.0;
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
    if (keyboard != state.keyboard) return state.boundary.requestStop(.window);
    if (fd < 0) return state.boundary.requestStop(.window);
    defer if (posix.close(fd) != 0) @panic("keyboard keymap descriptor cleanup failed");
    if (format != 1 or size == 0 or size > 1024 * 1024) return state.boundary.requestStop(.window);
    const mapped = posix.mmap(null, size, posix.PROT_READ, posix.MAP_PRIVATE, fd, 0);
    if (mapped == posix.MAP_FAILED) return state.boundary.requestStop(.window);
    defer if (posix.munmap(mapped, size) != 0) @panic("keyboard keymap mapping cleanup failed");
    const bytes: []const u8 = @as([*]const u8, @ptrCast(mapped))[0..size];
    var keymap = if (state.xkb_context) |*context| wayland.xkb.Keymap.fromBuffer(context, bytes) catch return state.boundary.requestStop(.window) else return state.boundary.requestStop(.window);
    const keyboard_state = wayland.xkb.State.init(&keymap) catch {
        keymap.deinit();
        return state.boundary.requestStop(.window);
    };
    if (state.xkb_state) |*old| old.deinit();
    if (state.xkb_keymap) |*old| old.deinit();
    state.xkb_keymap = keymap;
    state.xkb_state = keyboard_state;
}

fn keyboardEnter(data: ?*anyopaque, keyboard: ?*c.wl_keyboard, serial: u32, surface: ?*c.wl_surface, keys: [*c]c.wl_array) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (keyboard != state.keyboard or surface != state.surface) return state.boundary.requestStop(.window);
    if (keys == null) return state.boundary.requestStop(.window);
    const key_array: *allowzero c.wl_array = &keys[0];
    if (key_array.alloc < key_array.size or key_array.size % @sizeOf(u32) != 0 or key_array.size / @sizeOf(u32) > wayland.input.pressed_key_limit or (key_array.size != 0 and key_array.data == null) or (key_array.size != 0 and @intFromPtr(key_array.data) % @alignOf(u32) != 0)) return state.boundary.requestStop(.window);
    var pressed = std.mem.zeroes([wayland.input.pressed_key_limit]u32);
    const bytes: [*]const u8 = @ptrCast(key_array.data);
    for (0..key_array.size / @sizeOf(u32)) |index| {
        var value: u32 = 0;
        @memcpy(std.mem.asBytes(&value), bytes[index * @sizeOf(u32) ..][0..@sizeOf(u32)]);
        pressed[index] = value;
    }
    state.boundary.publishInput(.{ .keyboard_enter = .{ .serial = serial, .pressed_count = @intCast(key_array.size / @sizeOf(u32)), .pressed = pressed } }) catch inputFailure(state);
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
    state.boundary.publishInput(.{ .key = .{ .keycode = key, .time = time, .state = key_state, .serial = serial, .modifiers = state.keyboard_modifiers, .keysym = keysym, .text_len = @intCast(text_len), .text = text } }) catch inputFailure(state);
}

fn keyboardModifiers(data: ?*anyopaque, keyboard: ?*c.wl_keyboard, serial: u32, depressed: u32, latched: u32, locked: u32, group: u32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (keyboard != state.keyboard) return state.boundary.requestStop(.window);
    state.keyboard_modifiers = .{ .serial = serial, .depressed = depressed, .latched = latched, .locked = locked, .group = group };
    if (state.xkb_state) |*keyboard_state| {
        if (keyboard_state.updateModifiers(.{ .depressed = depressed, .latched = latched, .locked = locked, .group = group })) {}
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
    const point = wayland.input.Point{ .x = fixedPoint(x), .y = fixedPoint(y) };
    state.pointer_motion = .{ .time = 0, .point = point };
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
    state.pointer_motion = .{ .time = time, .point = .{ .x = fixedPoint(x), .y = fixedPoint(y) } };
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
    state.boundary.publishInput(.{ .button = .{ .button = button, .time = time, .state = button_state, .serial = serial, .point = motion.point } }) catch inputFailure(state);
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
    state.boundary.publishInput(.{ .axis = .{ .event = .{ .value = .{ .axis = direction, .time = time, .value = fixedPoint(value) } }, .point = point.point } }) catch inputFailure(state);
}

fn pointerFrame(data: ?*anyopaque, pointer: ?*c.wl_pointer) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (pointer != state.pointer) return state.boundary.requestStop(.window);
    state.boundary.publishInput(.{ .axis = .{ .event = .{ .frame = {} }, .point = null } }) catch inputFailure(state);
}

fn pointerSource(data: ?*anyopaque, pointer: ?*c.wl_pointer, source: u32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (pointer != state.pointer) return state.boundary.requestStop(.window);
    const value: wayland.input.AxisSource = switch (source) {
        0 => .wheel,
        1 => .finger,
        2 => .continuous,
        3 => .wheel_tilt,
        else => return state.boundary.requestStop(.window),
    };
    state.boundary.publishInput(.{ .axis = .{ .event = .{ .source = value }, .point = null } }) catch inputFailure(state);
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
    state.boundary.publishInput(.{ .axis = .{ .event = .{ .stop = .{ .axis = direction, .time = time } }, .point = point.point } }) catch inputFailure(state);
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
    state.boundary.publishInput(.{ .axis = .{ .event = .{ .discrete = .{ .axis = direction, .value = value } }, .point = point.point } }) catch inputFailure(state);
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
    state.boundary.publishInput(.{ .axis = .{ .event = .{ .value120 = .{ .axis = direction, .value = value } }, .point = point.point } }) catch inputFailure(state);
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
    state.boundary.publishInput(.{ .axis = .{ .event = .{ .relative_direction = .{ .axis = value, .direction = relative } }, .point = point.point } }) catch inputFailure(state);
}

const pointer_listener = c.wl_pointer_listener{ .enter = pointerEnter, .leave = pointerLeave, .motion = pointerMotion, .button = pointerButton, .axis = pointerAxis, .frame = pointerFrame, .axis_source = pointerSource, .axis_stop = pointerStop, .axis_discrete = pointerDiscrete, .axis_value120 = pointerValue120, .axis_relative_direction = pointerRelativeDirection };

fn feedbackDone(data: ?*anyopaque, _: ?*c.zwp_linux_dmabuf_feedback_v1) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    state.feedback_complete = true;
}
fn formatTable(data: ?*anyopaque, _: ?*c.zwp_linux_dmabuf_feedback_v1, fd: i32, size: u32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    state.table_fd = fd;
    state.table_size = size;
    if (size != 0) {
        const mapped = posix.mmap(null, size, posix.PROT_READ, posix.MAP_PRIVATE, fd, 0);
        if (mapped != posix.MAP_FAILED) state.table_map = @ptrCast(mapped);
    }
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
    const table = state.table_map orelse return;
    const array = indices orelse return;
    if (array.size % 2 != 0) return;
    const bytes: [*]const u8 = @ptrCast(array.data);
    for (0..array.size / 2) |index| {
        if (state.format_count == format_limit) return;
        var encoded: [2]u8 = undefined;
        @memcpy(&encoded, bytes[index * 2 ..][0..2]);
        const table_index = std.mem.bytesToValue(u16, &encoded);
        const offset = @as(usize, table_index) * 16;
        if (offset + 16 > state.table_size) continue;
        state.formats[state.format_count] = .{
            .fourcc = std.mem.bytesToValue(u32, table[offset..][0..4]),
            .modifier = std.mem.bytesToValue(u64, table[offset + 8 ..][0..8]),
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
    if (posix.close(descriptor) != 0) @panic("Window descriptor cleanup failed");
}
