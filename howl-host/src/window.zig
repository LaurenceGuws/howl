//! Owns Wayland discovery, dispatch, DMA-BUF wrappers, and presentation.

const std = @import("std");
const c = @import("window_c");
const shared = @import("shared.zig");

const format_limit: usize = 64;

const State = struct {
    boundary: *shared.Boundary,
    compositor: ?*c.wl_compositor = null,
    xdg: ?*c.xdg_wm_base = null,
    dmabuf: ?*c.zwp_linux_dmabuf_v1 = null,
    syncobj: ?*c.wp_linux_drm_syncobj_manager_v1 = null,
    surface: ?*c.wl_surface = null,
    xdg_surface: ?*c.xdg_surface = null,
    toplevel: ?*c.xdg_toplevel = null,
    sync_surface: ?*c.wp_linux_drm_syncobj_surface_v1 = null,
    compositor_name: u32 = 0,
    xdg_name: u32 = 0,
    dmabuf_name: u32 = 0,
    syncobj_name: u32 = 0,
    configured: bool = false,
    configure_serial: u32 = 0,
    toplevel_configured: bool = false,
    feedback_complete: bool = false,
    feedback_device: u64 = 0,
    tranche_device: u64 = 0,
    table_fd: i32 = -1,
    table_size: usize = 0,
    table_map: ?[*]const u8 = null,
    formats: [format_limit]struct { fourcc: u32, modifier: u64, device: u64 } = undefined,
    format_count: u8 = 0,
    buffers: [shared.slot_count]?*c.wl_buffer = .{ null, null, null },
    acquire_timelines: [shared.slot_count]?*c.wp_linux_drm_syncobj_timeline_v1 = .{ null, null, null },
    timelines: [shared.slot_count]?*c.wp_linux_drm_syncobj_timeline_v1 = .{ null, null, null },
    frame_callback: ?*c.wl_callback = null,
    presented: u64 = 0,

    fn deinit(self: *State) void {
        if (self.frame_callback) |value| c.wl_callback_destroy(value);
        if (self.sync_surface) |value| c.wp_linux_drm_syncobj_surface_v1_destroy(value);
        var index = shared.slot_count;
        while (index > 0) {
            index -= 1;
            if (self.buffers[index]) |value| c.wl_buffer_destroy(value);
            if (self.timelines[index]) |value| c.wp_linux_drm_syncobj_timeline_v1_destroy(value);
            if (self.acquire_timelines[index]) |value| c.wp_linux_drm_syncobj_timeline_v1_destroy(value);
        }
        if (self.toplevel) |value| c.xdg_toplevel_destroy(value);
        if (self.xdg_surface) |value| c.xdg_surface_destroy(value);
        if (self.surface) |value| c.wl_surface_destroy(value);
        if (self.syncobj) |value| c.wp_linux_drm_syncobj_manager_v1_destroy(value);
        if (self.dmabuf) |value| c.zwp_linux_dmabuf_v1_destroy(value);
        if (self.xdg) |value| c.xdg_wm_base_destroy(value);
        if (self.compositor) |value| c.wl_compositor_destroy(value);
        if (self.table_map) |value| {
            if (c.munmap(@ptrCast(@constCast(value)), self.table_size) != 0) @panic("feedback mapping cleanup failed");
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
    const display = c.wl_display_connect(null) orelse return error.WaylandConnect;
    defer c.wl_display_disconnect(display);
    defer state.deinit();
    const registry = c.wl_display_get_registry(display) orelse return error.Registry;
    defer c.wl_registry_destroy(registry);
    if (c.wl_registry_add_listener(registry, &registry_listener, &state) != 0) return error.Listener;
    if (c.wl_display_roundtrip(display) < 0) return error.Dispatch;
    if (state.compositor == null or state.xdg == null or state.dmabuf == null or state.syncobj == null) return error.RequiredGlobal;
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
    c.xdg_surface_ack_configure(state.xdg_surface.?, state.configure_serial);
    state.sync_surface = c.wp_linux_drm_syncobj_manager_v1_get_surface(state.syncobj.?, state.surface.?) orelse return error.ExplicitSync;

    const display_fd = c.wl_display_get_fd(display);
    if (display_fd < 0) return error.Dispatch;
    while (!boundary.shouldStop()) {
        if (!boundary.isWindowRingReady()) {
            if (boundary.takeOffers()) |offers| {
                try constructRing(&state, offers);
                boundary.markWindowRingReady();
            }
        }
        if (state.frame_callback == null) {
            if (boundary.takeCompletion()) |completion| try present(&state, completion);
        }
        if (c.wl_display_dispatch_pending(display) < 0) return error.Dispatch;
        if (c.wl_display_flush(display) < 0) return error.Dispatch;
        var descriptors = [_]c.pollfd{
            .{ .fd = display_fd, .events = c.POLLIN, .revents = 0 },
            .{ .fd = boundary.windowFd(), .events = c.POLLIN, .revents = 0 },
        };
        const ready = c.poll(&descriptors, descriptors.len, -1);
        if (ready < 0 and std.c.errno(ready) != .INTR) return error.Dispatch;
        if (ready > 0 and (descriptors[1].revents & c.POLLIN) != 0) try boundary.drainWindowWake();
        if (ready > 0 and (descriptors[0].revents & c.POLLIN) != 0 and c.wl_display_dispatch(display) < 0) return error.Dispatch;
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
        state.buffers[slot] = c.zwp_linux_buffer_params_v1_create_immed(params, 64, 64, state.boundary.readFeedback().?.fourcc, 0) orelse return error.Buffer;
        state.acquire_timelines[slot] = c.wp_linux_drm_syncobj_manager_v1_import_timeline(state.syncobj.?, offer.acquire_timeline_fd) orelse return error.ExplicitSync;
        state.timelines[slot] = c.wp_linux_drm_syncobj_manager_v1_import_timeline(state.syncobj.?, offer.release_timeline_fd) orelse return error.ExplicitSync;
        closeDescriptor(offer.dma_fd);
        offer.dma_fd = -1;
        closeDescriptor(offer.acquire_timeline_fd);
        offer.acquire_timeline_fd = -1;
        closeDescriptor(offer.release_timeline_fd);
        offer.release_timeline_fd = -1;
    }
}

fn present(state: *State, completion: shared.Completion) !void {
    if (completion.slot >= shared.slot_count or completion.revision <= state.presented) return error.InvalidCompletion;
    if (state.frame_callback != null) return error.PresentationPaced;
    const slot: usize = completion.slot;
    c.wp_linux_drm_syncobj_surface_v1_set_acquire_point(state.sync_surface.?, state.acquire_timelines[slot].?, 0, @intCast(completion.acquire_point));
    c.wp_linux_drm_syncobj_surface_v1_set_release_point(state.sync_surface.?, state.timelines[slot].?, 0, @intCast(completion.release_point));
    state.frame_callback = c.wl_surface_frame(state.surface.?) orelse return error.Frame;
    if (c.wl_callback_add_listener(state.frame_callback.?, &frame_listener, state) != 0) return error.Listener;
    c.wl_surface_attach(state.surface.?, state.buffers[slot].?, 0, 0);
    c.wl_surface_damage_buffer(state.surface.?, 0, 0, 64, 64);
    c.wl_surface_commit(state.surface.?);
    state.presented = completion.revision;
    std.debug.print("Window commit revision={d} slot={d} acquire={d} release={d}\n", .{ completion.revision, completion.slot, completion.acquire_point, completion.release_point });
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
}
fn globalRemove(data: ?*anyopaque, _: ?*c.wl_registry, name: u32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (name == state.compositor_name or name == state.xdg_name or name == state.dmabuf_name or name == state.syncobj_name) state.boundary.requestStop(.window);
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
    state.configure_serial = serial;
}
const xdg_surface_listener = c.xdg_surface_listener{ .configure = surfaceConfigure };
fn topConfigure(data: ?*anyopaque, _: ?*c.xdg_toplevel, width: i32, height: i32, _: ?*c.wl_array) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    if (width < 0 or height < 0) {
        state.boundary.requestStop(.window);
        return;
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
    std.debug.print("Window frame revision={d}\n", .{state.presented});
    if (state.presented == 4) state.boundary.requestStop(null);
}
const frame_listener = c.wl_callback_listener{ .done = frameDone };
fn feedbackDone(data: ?*anyopaque, _: ?*c.zwp_linux_dmabuf_feedback_v1) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    state.feedback_complete = true;
}
fn formatTable(data: ?*anyopaque, _: ?*c.zwp_linux_dmabuf_feedback_v1, fd: i32, size: u32) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(data.?));
    state.table_fd = fd;
    state.table_size = size;
    if (size != 0) {
        const mapped = c.mmap(null, size, c.PROT_READ, c.MAP_PRIVATE, fd, 0);
        if (mapped != c.MAP_FAILED) state.table_map = @ptrCast(mapped);
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
    if (c.close(descriptor) != 0) @panic("Window descriptor cleanup failed");
}
