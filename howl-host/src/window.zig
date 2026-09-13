//! Owns Wayland discovery, dispatch, DMA-BUF wrappers, and presentation.

const std = @import("std");
const wayland = @import("howl_wayland");
const c = wayland.c;
const posix = @import("host_c");
const shared = @import("shared.zig");

const format_limit: usize = 256;
const format_record_size: usize = 16;
const format_table_size_limit: usize = (@as(usize, std.math.maxInt(u16)) + 1) * format_record_size;

const MappedBytes = []align(std.heap.page_size_min) const u8;
const empty_mapped_bytes: [0]u8 align(std.heap.page_size_min) = .{};

const FeedbackMapping = struct {
    fd: i32 = -1,
    bytes: MappedBytes = empty_mapped_bytes[0..],

    fn deinit(self: *FeedbackMapping) void {
        if (self.fd < 0) return;
        std.posix.munmap(self.bytes);
        closeDescriptor(self.fd);
        self.* = .{};
    }
};

fn installFormatTable(state: *State, fd: i32, size: u32) !void {
    if (fd < 0) return error.InvalidDescriptor;
    var descriptor_owned = true;
    defer if (descriptor_owned) closeDescriptor(fd);
    if (size == 0 or size % format_record_size != 0 or size > format_table_size_limit)
        return error.InvalidSize;
    const bytes = std.posix.mmap(
        null,
        size,
        std.posix.PROT{ .READ = true },
        std.posix.MAP{ .TYPE = .PRIVATE },
        fd,
        0,
    ) catch return error.MappingFailed;
    var retiring = state.format_table;
    state.format_table = .{ .fd = fd, .bytes = bytes };
    descriptor_owned = false;
    retiring.deinit();
}

const WindowRing = struct {
    revision: u64 = 0,
    buffers: [shared.slot_count]?*c.wl_buffer = .{ null, null, null },
    acquire_timelines: [shared.slot_count]?*c.wp_linux_drm_syncobj_timeline_v1 = .{ null, null, null },
    timelines: [shared.slot_count]?*c.wp_linux_drm_syncobj_timeline_v1 = .{ null, null, null },
    width: u16 = 0,
    height: u16 = 0,

    fn live(self: *const WindowRing) bool {
        return self.revision != 0;
    }

    fn deinit(self: *WindowRing) void {
        var index = shared.slot_count;
        while (index > 0) {
            index -= 1;
            if (self.buffers[index]) |value| c.wl_buffer_destroy(value);
            if (self.timelines[index]) |value| c.wp_linux_drm_syncobj_timeline_v1_destroy(value);
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
    configure_serial: u32 = 0,
    toplevel_configured: bool = false,
    feedback_complete: bool = false,
    feedback_device: u64 = 0,
    tranche_device: u64 = 0,
    format_table: FeedbackMapping = .{},
    formats: [format_limit]struct { fourcc: u32, modifier: u64, device: u64 } = undefined,
    format_count: u16 = 0,
    active_ring: WindowRing = .{},
    pending_ring: WindowRing = .{},
    retired_ring: WindowRing = .{},
    frame_callback: ?*c.wl_callback = null,
    presented: u64 = 0,
    xkb_context: ?wayland.xkb.Context = null,
    xkb_keymap: ?wayland.xkb.Keymap = null,
    xkb_state: ?wayland.xkb.State = null,
    keyboard_modifiers: wayland.input.Modifiers = .{ .serial = 0, .depressed = 0, .latched = 0, .locked = 0, .group = 0 },
    keyboard_semantic_modifiers: wayland.input.SemanticModifiers = .{},

    fn deinit(self: *State) void {
        if (self.xkb_state) |*value| value.deinit();
        if (self.xkb_keymap) |*value| value.deinit();
        if (self.xkb_context) |*value| value.deinit();
        if (self.keyboard) |value| c.wl_keyboard_destroy(value);
        if (self.seat) |value| c.wl_seat_destroy(value);
        if (self.frame_callback) |value| c.wl_callback_destroy(value);
        if (self.sync_surface) |value| c.wp_linux_drm_syncobj_surface_v1_destroy(value);
        self.pending_ring.deinit();
        self.retired_ring.deinit();
        self.active_ring.deinit();
        if (self.toplevel) |value| c.xdg_toplevel_destroy(value);
        if (self.xdg_surface) |value| c.xdg_surface_destroy(value);
        if (self.surface) |value| c.wl_surface_destroy(value);
        if (self.syncobj) |value| c.wp_linux_drm_syncobj_manager_v1_destroy(value);
        if (self.dmabuf) |value| c.zwp_linux_dmabuf_v1_destroy(value);
        if (self.xdg) |value| c.xdg_wm_base_destroy(value);
        if (self.compositor) |value| c.wl_compositor_destroy(value);
        self.format_table.deinit();
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
    c.xdg_toplevel_set_title(state.toplevel.?, "Howl Vulkan canary");
    c.wl_surface_commit(state.surface.?);
    if (c.wl_display_roundtrip(display) < 0 or !state.configured or !state.toplevel_configured) return error.Configure;
    state.sync_surface = c.wp_linux_drm_syncobj_manager_v1_get_surface(state.syncobj.?, state.surface.?) orelse return error.ExplicitSync;

    const display_fd = c.wl_display_get_fd(display);
    if (display_fd < 0) return error.Dispatch;
    while (!boundary.shouldStop()) {
        if (boundary.takeRingRetired()) |revision| {
            if (!state.retired_ring.live() or state.retired_ring.revision != revision)
                return error.InvalidRingRetirement;
            state.retired_ring.deinit();
        }
        if (boundary.takeOffers()) |offers| {
            if (state.pending_ring.live()) return error.RingPending;
            state.pending_ring = try constructRing(&state, offers);
            boundary.markWindowRingReady(state.pending_ring.revision);
        }
        if (state.frame_callback == null) {
            if (boundary.takeCompletion()) |completion| try present(&state, completion);
        }
        if (c.wl_display_dispatch_pending(display) < 0) return error.Dispatch;
        if (c.wl_display_flush(display) < 0) return error.Dispatch;
        var descriptors = [_]posix.pollfd{
            .{ .fd = display_fd, .events = posix.POLLIN, .revents = 0 },
            .{ .fd = boundary.windowFd(), .events = posix.POLLIN, .revents = 0 },
        };
        const ready = posix.poll(&descriptors, descriptors.len, -1);
        if (ready < 0 and std.c.errno(ready) != .INTR) return error.Dispatch;
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

fn constructRing(state: *State, initial_offers: [shared.slot_count]shared.SlotOffer) !WindowRing {
    var offers = initial_offers;
    defer for (&offers) |*offer| {
        if (offer.dma_fd >= 0) closeDescriptor(offer.dma_fd);
        if (offer.acquire_timeline_fd >= 0) closeDescriptor(offer.acquire_timeline_fd);
        if (offer.release_timeline_fd >= 0) closeDescriptor(offer.release_timeline_fd);
    };
    const revision = offers[0].ring_revision;
    const width = offers[0].width;
    const height = offers[0].height;
    if (revision == 0 or width == 0 or height == 0) return error.InvalidPlane;
    var ring = WindowRing{ .revision = revision, .width = width, .height = height };
    errdefer ring.deinit();
    for (0..offers.len) |slot| {
        const offer = &offers[slot];
        if (offer.ring_revision != revision or offer.width != width or offer.height != height)
            return error.InvalidPlane;
        if (offer.plane_count == 0 or offer.plane_count > shared.plane_limit) return error.InvalidPlane;
        const params = c.zwp_linux_dmabuf_v1_create_params(state.dmabuf.?) orelse return error.Buffer;
        defer c.zwp_linux_buffer_params_v1_destroy(params);
        for (0..offer.plane_count) |plane| {
            const layout = offer.planes[plane];
            const modifier = state.boundary.readFeedback().?.modifier;
            c.zwp_linux_buffer_params_v1_add(params, offer.dma_fd, @intCast(plane), layout.offset, layout.stride, @intCast(modifier >> 32), @intCast(modifier & 0xffff_ffff));
        }
        ring.buffers[slot] = c.zwp_linux_buffer_params_v1_create_immed(params, width, height, state.boundary.readFeedback().?.fourcc, 0) orelse return error.Buffer;
        ring.acquire_timelines[slot] = c.wp_linux_drm_syncobj_manager_v1_import_timeline(state.syncobj.?, offer.acquire_timeline_fd) orelse return error.ExplicitSync;
        ring.timelines[slot] = c.wp_linux_drm_syncobj_manager_v1_import_timeline(state.syncobj.?, offer.release_timeline_fd) orelse return error.ExplicitSync;
        closeDescriptor(offer.dma_fd);
        offer.dma_fd = -1;
        closeDescriptor(offer.acquire_timeline_fd);
        offer.acquire_timeline_fd = -1;
        closeDescriptor(offer.release_timeline_fd);
        offer.release_timeline_fd = -1;
    }
    return ring;
}

fn present(state: *State, completion: shared.Completion) !void {
    if (completion.ring_revision == 0 or completion.slot >= shared.slot_count or
        completion.revision <= state.presented) return error.InvalidCompletion;
    if (state.frame_callback != null) return error.PresentationPaced;
    const promote = state.pending_ring.live() and
        state.pending_ring.revision == completion.ring_revision;
    const ring: *WindowRing = if (promote)
        &state.pending_ring
    else if (state.active_ring.live() and state.active_ring.revision == completion.ring_revision)
        &state.active_ring
    else
        return error.InvalidCompletion;
    const slot: usize = completion.slot;
    c.wp_linux_drm_syncobj_surface_v1_set_acquire_point(state.sync_surface.?, ring.acquire_timelines[slot].?, 0, @intCast(completion.acquire_point));
    c.wp_linux_drm_syncobj_surface_v1_set_release_point(state.sync_surface.?, ring.timelines[slot].?, 0, @intCast(completion.release_point));
    state.frame_callback = c.wl_surface_frame(state.surface.?) orelse return error.Frame;
    if (c.wl_callback_add_listener(state.frame_callback.?, &frame_listener, state) != 0) return error.Listener;
    c.wl_surface_attach(state.surface.?, ring.buffers[slot].?, 0, 0);
    c.wl_surface_damage_buffer(state.surface.?, 0, 0, ring.width, ring.height);
    c.wl_surface_commit(state.surface.?);
    state.presented = completion.revision;
    if (promote) {
        if (state.retired_ring.live()) return error.RingRetirementPending;
        state.retired_ring = state.active_ring;
        state.active_ring = state.pending_ring;
        state.pending_ring = .{};
    }
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

fn inputFailure(state: *State) void {
    state.boundary.requestStop(.window);
}

fn seatCapabilities(data: ?*anyopaque, seat: ?*c.wl_seat, capabilities: u32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (seat != state.seat) return state.boundary.requestStop(.window);
    const keyboard_capability = (@as(u32, @intCast(c.WL_SEAT_CAPABILITY_KEYBOARD)) & capabilities) != 0;
    if (keyboard_capability and state.keyboard == null) {
        state.keyboard = c.wl_seat_get_keyboard(seat) orelse return state.boundary.requestStop(.window);
        if (c.wl_keyboard_add_listener(state.keyboard.?, &keyboard_listener, state) != 0)
            return state.boundary.requestStop(.window);
    } else if (!keyboard_capability and state.keyboard != null) {
        c.wl_keyboard_destroy(state.keyboard.?);
        state.keyboard = null;
        if (state.xkb_state) |*value| value.deinit();
        state.xkb_state = null;
        if (state.xkb_keymap) |*value| value.deinit();
        state.xkb_keymap = null;
        state.keyboard_semantic_modifiers = .{};
    }
}

fn seatName(data: ?*anyopaque, seat: ?*c.wl_seat, name: [*c]const u8) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (seat != state.seat or name == null) return state.boundary.requestStop(.window);
    if (std.mem.span(name).len > 64) state.boundary.requestStop(.window);
}

const seat_listener = c.wl_seat_listener{ .capabilities = seatCapabilities, .name = seatName };

fn keyboardKeymap(data: ?*anyopaque, keyboard_value: ?*c.wl_keyboard, format: u32, fd: i32, size: u32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (keyboard_value != state.keyboard or fd < 0) return state.boundary.requestStop(.window);
    defer closeDescriptor(fd);
    if (format != 1 or size == 0 or size > 1024 * 1024) return state.boundary.requestStop(.window);
    const bytes = std.posix.mmap(
        null,
        size,
        std.posix.PROT{ .READ = true },
        std.posix.MAP{ .TYPE = .PRIVATE },
        fd,
        0,
    ) catch return state.boundary.requestStop(.window);
    defer std.posix.munmap(bytes);
    var keymap = if (state.xkb_context) |*context|
        wayland.xkb.Keymap.fromBuffer(context, bytes) catch return state.boundary.requestStop(.window)
    else
        return state.boundary.requestStop(.window);
    const keyboard_state = wayland.xkb.State.init(&keymap) catch {
        keymap.deinit();
        return state.boundary.requestStop(.window);
    };
    if (state.xkb_state) |*old| old.deinit();
    if (state.xkb_keymap) |*old| old.deinit();
    state.xkb_keymap = keymap;
    state.xkb_state = keyboard_state;
    state.keyboard_semantic_modifiers = .{};
}

fn keyboardEnter(data: ?*anyopaque, keyboard_value: ?*c.wl_keyboard, serial: u32, surface: ?*c.wl_surface, keys: [*c]c.wl_array) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (keyboard_value != state.keyboard or surface != state.surface or keys == null)
        return state.boundary.requestStop(.window);
    const key_array: *allowzero c.wl_array = &keys[0];
    if (key_array.size != 0 and key_array.data == null) return state.boundary.requestStop(.window);
    const bytes: []const u8 = if (key_array.size == 0)
        &.{}
    else
        @as([*]const u8, @ptrCast(key_array.data))[0..key_array.size];
    const entered = wayland.input.keyboardEnter(serial, bytes) catch return state.boundary.requestStop(.window);
    if (entered.serial != serial) return state.boundary.requestStop(.window);
    state.boundary.publishInput(.{ .focus = true }) catch inputFailure(state);
}

fn keyboardLeave(data: ?*anyopaque, keyboard_value: ?*c.wl_keyboard, _: u32, surface: ?*c.wl_surface) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (keyboard_value != state.keyboard or surface != state.surface)
        return state.boundary.requestStop(.window);
    state.boundary.publishInput(.{ .focus = false }) catch inputFailure(state);
}

fn keyboardKey(data: ?*anyopaque, keyboard_value: ?*c.wl_keyboard, serial: u32, time: u32, key_value: u32, state_value: u32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (keyboard_value != state.keyboard) return state.boundary.requestStop(.window);
    const key_state: wayland.input.KeyState = switch (state_value) {
        c.WL_KEYBOARD_KEY_STATE_PRESSED => .pressed,
        c.WL_KEYBOARD_KEY_STATE_RELEASED => .released,
        c.WL_KEYBOARD_KEY_STATE_REPEATED => .repeated,
        else => return state.boundary.requestStop(.window),
    };
    if (key_value > std.math.maxInt(u32) - 8) return state.boundary.requestStop(.window);
    const xkb_key = key_value + 8;
    var text: [wayland.input.key_text_limit]u8 = @splat(0);
    const keysym = if (state.xkb_state) |*keyboard_state|
        keyboard_state.keySym(xkb_key)
    else
        return state.boundary.requestStop(.window);
    const text_len = if (state.xkb_state) |*keyboard_state|
        keyboard_state.keyUtf8(xkb_key, &text) catch return state.boundary.requestStop(.window)
    else
        return state.boundary.requestStop(.window);
    state.boundary.publishInput(.{ .key = .{
        .keycode = key_value,
        .time = time,
        .state = key_state,
        .serial = serial,
        .modifiers = state.keyboard_modifiers,
        .semantic_modifiers = state.keyboard_semantic_modifiers,
        .keysym = @fromBackingInt(@intCast(keysym)),
        .text_len = @intCast(text_len),
        .text = text,
    } }) catch inputFailure(state);
}

fn keyboardModifiers(data: ?*anyopaque, keyboard_value: ?*c.wl_keyboard, serial: u32, depressed: u32, latched: u32, locked: u32, group: u32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (keyboard_value != state.keyboard) return state.boundary.requestStop(.window);
    state.keyboard_modifiers = .{ .serial = serial, .depressed = depressed, .latched = latched, .locked = locked, .group = group };
    if (state.xkb_state) |*keyboard_state| {
        if (keyboard_state.updateModifiers(.{ .depressed = depressed, .latched = latched, .locked = locked, .group = group })) {}
        state.keyboard_semantic_modifiers = keyboard_state.semanticModifiers();
    }
}

fn keyboardRepeat(data: ?*anyopaque, keyboard_value: ?*c.wl_keyboard, rate: i32, delay: i32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (keyboard_value != state.keyboard or rate < 0 or delay < 0)
        state.boundary.requestStop(.window);
}

const keyboard_listener = c.wl_keyboard_listener{
    .keymap = keyboardKeymap,
    .enter = keyboardEnter,
    .leave = keyboardLeave,
    .key = keyboardKey,
    .modifiers = keyboardModifiers,
    .repeat_info = keyboardRepeat,
};

fn ping(data: ?*anyopaque, wm: ?*c.xdg_wm_base, serial: u32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (wm != state.xdg) state.boundary.requestStop(.window);
    c.xdg_wm_base_pong(state.xdg.?, serial);
}
const xdg_listener = c.xdg_wm_base_listener{ .ping = ping };
fn surfaceConfigure(data: ?*anyopaque, _: ?*c.xdg_surface, serial: u32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    c.xdg_surface_ack_configure(state.xdg_surface.?, serial);
    state.configured = true;
    state.configure_serial = serial;
}
const xdg_surface_listener = c.xdg_surface_listener{ .configure = surfaceConfigure };
fn topConfigure(data: ?*anyopaque, _: ?*c.xdg_toplevel, width: i32, height: i32, _: ?*c.wl_array) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (width < 0 or height < 0 or width > std.math.maxInt(u16) or height > std.math.maxInt(u16)) {
        state.boundary.requestStop(.window);
        return;
    }
    if (width != 0 and height != 0) {
        state.boundary.publishWindowSize(.{
            .width = @intCast(width),
            .height = @intCast(height),
        }) catch state.boundary.requestStop(.window);
    }
    state.toplevel_configured = true;
}
fn topClose(data: ?*anyopaque, _: ?*c.xdg_toplevel) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    state.boundary.requestStop(null);
}
fn topBounds(data: ?*anyopaque, _: ?*c.xdg_toplevel, width: i32, height: i32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (width <= 0 or height <= 0) state.boundary.requestStop(.window);
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
fn feedbackDone(data: ?*anyopaque, _: ?*c.zwp_linux_dmabuf_feedback_v1) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    state.feedback_complete = true;
}
fn formatTable(data: ?*anyopaque, _: ?*c.zwp_linux_dmabuf_feedback_v1, fd: i32, size: u32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    installFormatTable(state, fd, size) catch state.boundary.requestStop(.window);
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
    if (table.fd < 0 or indices.len % 2 != 0) return;
    for (0..indices.len / 2) |index| {
        if (state.format_count == format_limit) return;
        var encoded: [2]u8 = undefined;
        @memcpy(&encoded, indices[index * 2 ..][0..2]);
        const table_index = std.mem.bytesToValue(u16, &encoded);
        const offset = @as(usize, table_index) * format_record_size;
        if (offset > table.bytes.len or table.bytes.len - offset < format_record_size) continue;
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
    if (posix.close(descriptor) != 0) @panic("Window descriptor cleanup failed");
}
