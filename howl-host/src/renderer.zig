//! Exclusively owns Vulkan mutation and DRM release observation.

const std = @import("std");
const c = @import("renderer_c");
const host_presentation = @import("host_presentation");
const host_layout = @import("layout.zig");
const howl_instance = @import("howl_instance");
const published_scene = @import("published_scene.zig");
const shared = @import("shared.zig");
const howl_vk = @import("howl_vk");
const vk = howl_vk.abi;
const surface = howl_vk.surface;

const gpu_memory_limit: u64 = 512 * 1024 * 1024;
const scale_denominator: u32 = 120;
const empty_plan = surface.Plan{
    .vertices = &.{},
    .indices = &.{},
    .commands = &.{},
    .atlas_changed = false,
};

const Ready = union(enum) {
    scene: struct { index: usize, prepared: published_scene.Prepared },
    window_size: shared.WindowSize,
    display_scale: shared.DisplayScale,
};

const PointerProjection = struct {
    display_scale_120: u32,
    mux: *host_layout.Mux,
    scene_panes: *const [2]?host_layout.PaneId,
    scene_count: usize,
    workspace_rows: u16,
    workspace_cols: u16,
    cell_width: u16,
    cell_height: u16,
};

const Slot = struct {
    image: vk.VkImage = null,
    memory: vk.VkDeviceMemory = null,
    release_handle: u32 = 0,
    plane_count: u8 = 0,
    planes: [shared.plane_limit]shared.Plane = undefined,
    external: bool = false,
    release_point: u64 = 0,
    attachment: surface.Attachment = .{},

    fn deinit(self: *Slot, device: vk.VkDevice, drm_fd: i32) void {
        self.attachment.deinit(device);
        if (self.release_handle != 0) destroySyncobj(drm_fd, self.release_handle);
        if (self.image != null) vk.vkDestroyImage(device, self.image, null);
        if (self.memory != null) vk.vkFreeMemory(device, self.memory, null);
        self.* = .{};
    }
};

const OfferedFds = struct {
    dma: i32 = -1,
    acquire: i32 = -1,
    timeline: i32 = -1,
};

const RenderRing = struct {
    revision: u64,
    width: u16,
    height: u16,
    slots: [shared.slot_count]Slot = @splat(.{}),
    slot_index: usize = 0,
    previous_slot: ?usize = null,

    fn deinit(self: *RenderRing, device: vk.VkDevice, drm_fd: i32) void {
        var index = self.slots.len;
        while (index != 0) {
            index -= 1;
            self.slots[index].deinit(device, drm_fd);
        }
        self.* = undefined;
    }
};

/// Runs the sole Vulkan/DRM owner until the bounded ring completes or fails.
/// All operational failures are recorded as the first Render runtime failure.
pub fn run(
    boundary: *shared.Boundary,
    allocator: std.mem.Allocator,
    exchange: *howl_instance.RenderExchange,
    publication_fd: i32,
    logical_cell_size: howl_instance.render.terminal.Size,
    initial_scale: shared.DisplayScale,
    mux: host_layout.Mux,
) void {
    runFallible(
        boundary,
        allocator,
        exchange,
        publication_fd,
        logical_cell_size,
        initial_scale,
        mux,
    ) catch |failure| {
        if (failure == error.Stopping and boundary.shouldStop()) {
            boundary.markStopped(.render);
            return;
        }
        std.debug.print("Render failure: {s}\n", .{@errorName(failure)});
        boundary.requestStop(.render);
    };
    boundary.markStopped(.render);
}

fn runFallible(
    boundary: *shared.Boundary,
    allocator: std.mem.Allocator,
    exchange: *howl_instance.RenderExchange,
    publication_fd: i32,
    logical_cell_size: howl_instance.render.terminal.Size,
    initial_scale: shared.DisplayScale,
    initial_mux: host_layout.Mux,
) !void {
    var mux = initial_mux;
    const feedback = try waitFeedback(boundary);
    var display_scale_120 = initial_scale.scale_120;
    const scene_count: usize = 1;
    var scenes: [2]?published_scene.Scene = .{ null, null };
    scenes[0] = try published_scene.Scene.init(
        allocator,
        exchange,
        publication_fd,
        boundary.stopFd(),
    );
    defer scenes[0].?.deinit();
    var prepared: [2]published_scene.Prepared = undefined;
    var render_revisions: [2]u64 = @splat(0);
    for (0..scene_count) |scene_index| {
        prepared[scene_index] = try scenes[scene_index].?.prepare();
        render_revisions[scene_index] = prepared[scene_index].render_revision;
    }
    const initial_logical_width = std.math.mul(u16, prepared[0].cols, logical_cell_size.width) catch
        return error.InvalidGeometry;
    const initial_logical_height = std.math.mul(u16, prepared[0].rows, logical_cell_size.height) catch
        return error.InvalidGeometry;
    var surface_logical_width = initial_logical_width;
    var surface_logical_height = initial_logical_height;
    var surface_width = try scaledExtent(surface_logical_width, display_scale_120);
    var surface_height = try scaledExtent(surface_logical_height, display_scale_120);
    var cell_size = prepared[0].cell_size;
    var workspace_cols: u16 = @max(2, surface_width / cell_size.width);
    var workspace_rows: u16 = @max(1, surface_height / cell_size.height);

    var scene_panes: [2]?host_layout.PaneId = .{ null, null };
    var initial_pane_storage: [host_layout.max_panes_per_tab]host_layout.Placement = undefined;
    const initial_panes = try mux.activeLayout(
        .{ .width = workspace_cols, .height = workspace_rows },
        &initial_pane_storage,
    );
    if (initial_panes.len != scene_count) return error.SceneTopologyMismatch;
    for (initial_panes, 0..) |placement, scene_index| scene_panes[scene_index] = placement.pane;
    var projected_layout: [host_layout.max_panes_per_tab]host_layout.Placement = undefined;
    const established = try establishInitialGeometry(
        boundary,
        &scenes[0].?,
        mux,
        &prepared[0],
        workspace_rows,
        workspace_cols,
        surface_width,
        surface_height,
        &projected_layout,
    );
    if (established.surface_width != surface_width or established.surface_height != surface_height or
        established.grid_rows != workspace_rows or established.grid_cols != workspace_cols)
        return error.ResizeResultMismatch;
    if (feedback.device == 0 or feedback.fourcc != 0x34324241) return error.UnsupportedFeedback;

    var application = std.mem.zeroes(vk.VkApplicationInfo);
    application.sType = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO;
    application.pApplicationName = "howl-host";
    application.applicationVersion = vk.VK_MAKE_VERSION(0, 1, 3);
    application.pEngineName = "none";
    application.engineVersion = 0;
    application.apiVersion = vk.VK_API_VERSION_1_3;
    var instance_info = std.mem.zeroes(vk.VkInstanceCreateInfo);
    instance_info.sType = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    instance_info.pApplicationInfo = &application;
    var instance: vk.VkInstance = undefined;
    if (vk.vkCreateInstance(&instance_info, null, &instance) != vk.VK_SUCCESS) return error.VulkanInstance;
    defer vk.vkDestroyInstance(instance, null);

    const selected = try selectPhysical(instance, feedback.device);
    const physical = selected.device;
    try requireExtensions(physical);
    var synchronization2 = std.mem.zeroes(vk.VkPhysicalDeviceSynchronization2Features);
    synchronization2.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES;
    var timeline = std.mem.zeroes(vk.VkPhysicalDeviceTimelineSemaphoreFeatures);
    timeline.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TIMELINE_SEMAPHORE_FEATURES;
    synchronization2.pNext = @ptrCast(&timeline);
    var features = std.mem.zeroes(vk.VkPhysicalDeviceFeatures2);
    features.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
    features.pNext = @ptrCast(&synchronization2);
    vk.vkGetPhysicalDeviceFeatures2(physical, &features);
    if (synchronization2.synchronization2 == 0 or timeline.timelineSemaphore == 0) return error.RequiredFeature;

    const dedicated_only = try queryFormat(physical, feedback.modifier);
    const family = try graphicsFamily(physical);
    const priority: f32 = 1;
    var queue_info = std.mem.zeroes(vk.VkDeviceQueueCreateInfo);
    queue_info.sType = vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    queue_info.queueFamilyIndex = family;
    queue_info.queueCount = 1;
    queue_info.pQueuePriorities = &priority;
    const names = [_][*:0]const u8{
        "VK_EXT_external_memory_dma_buf",
        "VK_EXT_image_drm_format_modifier",
        "VK_KHR_external_memory_fd",
        "VK_KHR_external_semaphore_fd",
        "VK_KHR_timeline_semaphore",
        "VK_KHR_synchronization2",
    };
    synchronization2.synchronization2 = vk.VK_TRUE;
    timeline.timelineSemaphore = vk.VK_TRUE;
    var device_info = std.mem.zeroes(vk.VkDeviceCreateInfo);
    device_info.sType = vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    device_info.pNext = @ptrCast(&synchronization2);
    device_info.queueCreateInfoCount = 1;
    device_info.pQueueCreateInfos = &queue_info;
    device_info.enabledExtensionCount = names.len;
    device_info.ppEnabledExtensionNames = @ptrCast(&names);
    var device: vk.VkDevice = undefined;
    if (vk.vkCreateDevice(physical, &device_info, null, &device) != vk.VK_SUCCESS) return error.VulkanDevice;
    defer vk.vkDestroyDevice(device, null);
    var queue: vk.VkQueue = undefined;
    vk.vkGetDeviceQueue(device, family, 0, &queue);
    if (queue == null) return error.VulkanDevice;

    const drm_fd = try openRenderNode(selected.render_major, selected.render_minor);
    defer closeDescriptor(drm_fd);
    const get_memory_fd: vk.PFN_vkGetMemoryFdKHR = @ptrCast(vk.vkGetDeviceProcAddr(device, "vkGetMemoryFdKHR"));
    const get_modifier: vk.PFN_vkGetImageDrmFormatModifierPropertiesEXT = @ptrCast(vk.vkGetDeviceProcAddr(device, "vkGetImageDrmFormatModifierPropertiesEXT"));
    const get_semaphore_fd: vk.PFN_vkGetSemaphoreFdKHR = @ptrCast(vk.vkGetDeviceProcAddr(device, "vkGetSemaphoreFdKHR"));
    const import_semaphore_fd: vk.PFN_vkImportSemaphoreFdKHR = @ptrCast(vk.vkGetDeviceProcAddr(device, "vkImportSemaphoreFdKHR"));
    if (get_memory_fd == null or get_modifier == null or get_semaphore_fd == null or import_semaphore_fd == null) return error.FunctionLoad;

    var memory_properties: vk.VkPhysicalDeviceMemoryProperties = undefined;
    vk.vkGetPhysicalDeviceMemoryProperties(physical, &memory_properties);
    var gpu_bytes: u64 = 0;
    var graphics = try surface.Context.init(device, memory_properties, &gpu_bytes, gpu_memory_limit);
    defer graphics.deinit(device, &gpu_bytes);
    const plane_count = try modifierPlaneCount(physical, feedback.modifier);
    var acquire_handle: u32 = 0;
    if (c.drmSyncobjCreate(drm_fd, 0, &acquire_handle) != 0) return error.Syncobj;
    defer destroySyncobj(drm_fd, acquire_handle);
    var ring = try createRenderRing(
        boundary,
        &graphics,
        device,
        memory_properties,
        feedback.modifier,
        dedicated_only,
        plane_count,
        surface_width,
        surface_height,
        surface_logical_width,
        surface_logical_height,
        get_memory_fd.?,
        get_modifier.?,
        drm_fd,
        acquire_handle,
        1,
    );
    defer ring.deinit(device, drm_fd);
    var retiring_ring: ?RenderRing = null;
    defer if (retiring_ring) |*value| value.deinit(device, drm_fd);

    var pool_info = std.mem.zeroes(vk.VkCommandPoolCreateInfo);
    pool_info.sType = vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    pool_info.flags = vk.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    pool_info.queueFamilyIndex = family;
    var pool: vk.VkCommandPool = undefined;
    if (vk.vkCreateCommandPool(device, &pool_info, null, &pool) != vk.VK_SUCCESS) return error.Command;
    defer vk.vkDestroyCommandPool(device, pool, null);
    var command_info = std.mem.zeroes(vk.VkCommandBufferAllocateInfo);
    command_info.sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    command_info.commandPool = pool;
    command_info.level = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    command_info.commandBufferCount = 1;
    var command: vk.VkCommandBuffer = undefined;
    if (vk.vkAllocateCommandBuffers(device, &command_info, &command) != vk.VK_SUCCESS) return error.Command;
    var queue_active = false;
    defer if (queue_active) {
        if (vk.vkDeviceWaitIdle(device) != vk.VK_SUCCESS) @panic("Render failed to quiesce Vulkan during cleanup");
    };

    queue_active = true;
    var present_revision: u64 = 0;
    var acquire_point: u64 = 0;
    var changed: [2]bool = .{ true, false };
    var generic_draw_count_total: u64 = 0;

    while (!boundary.shouldStop()) {
        var wait_semaphore: ?vk.VkSemaphore = null;
        defer if (wait_semaphore) |value| vk.vkDestroySemaphore(device, value, null);
        const slot = &ring.slots[ring.slot_index];
        if (slot.external) {
            try waitTimeline(drm_fd, slot.release_handle, slot.release_point);
            wait_semaphore = try importRelease(
                device,
                drm_fd,
                slot.release_handle,
                slot.release_point,
                import_semaphore_fd.?,
            );
        }

        acquire_point = std.math.add(u64, acquire_point, 1) catch return error.RevisionOverflow;
        present_revision = std.math.add(u64, present_revision, 1) catch return error.RevisionOverflow;
        slot.release_point = std.math.add(u64, slot.release_point, 1) catch return error.RevisionOverflow;
        const visible = try projectActivePixels(
            &mux,
            workspace_rows,
            workspace_cols,
            cell_size.width,
            cell_size.height,
            &projected_layout,
        );
        if (visible.len != 1 or scene_count != 1) return error.SceneTopologyMismatch;
        const scene_index = sceneIndexForPane(
            &scene_panes,
            scene_count,
            visible[0].pane,
        ) orelse return error.SceneTopologyMismatch;
        if (scene_index != 0) return error.SceneTopologyMismatch;

        const plan = prepared[0].plan;
        generic_draw_count_total += 1;
        errdefer if (changed[0]) discardPending(&scenes[0].?, prepared[0]);
        try render(
            &graphics,
            plan,
            scenes[0].?.builder.alpha_pixels,
            scenes[0].?.builder.rgba_pixels,
            device,
            queue,
            family,
            command,
            slot,
            .{ 0, 0, 0, 1 },
            wait_semaphore,
            get_semaphore_fd.?,
            drm_fd,
            acquire_handle,
            acquire_point,
            surface_width,
            surface_height,
        );
        if (changed[0]) {
            try scenes[0].?.complete();
            changed[0] = false;
        }
        if (wait_semaphore) |value| {
            vk.vkDestroySemaphore(device, value, null);
            wait_semaphore = null;
        }
        try boundary.publishCompletion(.{
            .ring_revision = ring.revision,
            .revision = present_revision,
            .slot = @intCast(ring.slot_index),
            .acquire_point = acquire_point,
            .release_point = slot.release_point,
        });

        // The first commit from a replacement ring lets KWin release every
        // buffer from its predecessor. Retire that whole generation before
        // reusing ordinary per-ring slot pacing.
        if (retiring_ring) |*retiring| {
            try waitRenderRingReleased(retiring, drm_fd);
            const retiring_revision = retiring.revision;
            retiring.deinit(device, drm_fd);
            retiring_ring = null;
            try boundary.publishRingRetired(retiring_revision);
        }

        // Publishing the next slot lets KWin retire the previous one. Waiting
        // here bounds presentation backlog without pacing canonical Instance
        // progress: Instance continues independently while this observer waits.
        if (ring.previous_slot) |prior| {
            try waitTimeline(drm_fd, ring.slots[prior].release_handle, ring.slots[prior].release_point);
        }
        ring.previous_slot = ring.slot_index;
        ring.slot_index = (ring.slot_index + 1) % shared.slot_count;

        const ready = waitReady(
            boundary,
            &scenes,
            scene_count,
            .{
                .display_scale_120 = display_scale_120,
                .mux = &mux,
                .scene_panes = &scene_panes,
                .scene_count = scene_count,
                .workspace_rows = workspace_rows,
                .workspace_cols = workspace_cols,
                .cell_width = cell_size.width,
                .cell_height = cell_size.height,
            },
        ) catch |failure| {
            if (boundary.shouldStop()) break;
            return failure;
        };
        switch (ready) {
            .scene => |received| {
                if (received.index != 0) return error.SceneTopologyMismatch;
                const next = received.prepared;
                if (next.width != prepared[0].width or
                    next.height != prepared[0].height or
                    !std.meta.eql(next.cell_size, cell_size))
                {
                    try scenes[0].?.discardPrepared(next);
                    return error.GeometryChanged;
                }
                prepared[0] = next;
                render_revisions[0] = next.render_revision;
                changed[0] = true;
            },
            .display_scale => |scale| {
                if (scale.scale_120 == display_scale_120) continue;
                const next_font_pixels = try scaledFontPixels(scale.scale_120);
                const next_surface_width = try scaledExtent(
                    surface_logical_width,
                    scale.scale_120,
                );
                const next_surface_height = try scaledExtent(
                    surface_logical_height,
                    scale.scale_120,
                );
                const geometry_changed = try requestSceneSurface(
                    boundary,
                    &scenes[0].?,
                    &prepared[0],
                    next_surface_width,
                    next_surface_height,
                    next_font_pixels,
                );
                changed[0] = geometry_changed;
                errdefer if (geometry_changed)
                    discardPending(&scenes[0].?, prepared[0]);
                render_revisions[0] = prepared[0].render_revision;
                workspace_rows = prepared[0].rows;
                workspace_cols = prepared[0].cols;
                cell_size = prepared[0].cell_size;

                if (retiring_ring != null) return error.RingRetirementPending;
                const next_revision = std.math.add(u64, ring.revision, 1) catch
                    return error.RevisionOverflow;
                var replacement = try createRenderRing(
                    boundary,
                    &graphics,
                    device,
                    memory_properties,
                    feedback.modifier,
                    dedicated_only,
                    plane_count,
                    next_surface_width,
                    next_surface_height,
                    surface_logical_width,
                    surface_logical_height,
                    get_memory_fd.?,
                    get_modifier.?,
                    drm_fd,
                    acquire_handle,
                    next_revision,
                );
                retiring_ring = ring;
                ring = replacement;
                replacement = undefined;
                display_scale_120 = scale.scale_120;
                surface_width = next_surface_width;
                surface_height = next_surface_height;
            },
            .window_size => |requested| {
                if (requested.width == surface_logical_width and
                    requested.height == surface_logical_height)
                    continue;
                const requested_physical_width = try scaledExtent(
                    requested.width,
                    display_scale_120,
                );
                const requested_physical_height = try scaledExtent(
                    requested.height,
                    display_scale_120,
                );
                const geometry_changed = try requestSceneSurface(
                    boundary,
                    &scenes[0].?,
                    &prepared[0],
                    requested_physical_width,
                    requested_physical_height,
                    null,
                );
                if (geometry_changed) {
                    changed[0] = true;
                    errdefer discardPending(&scenes[0].?, prepared[0]);
                    render_revisions[0] = prepared[0].render_revision;
                    workspace_rows = prepared[0].rows;
                    workspace_cols = prepared[0].cols;
                    cell_size = prepared[0].cell_size;
                }

                if (retiring_ring != null) return error.RingRetirementPending;
                const next_revision = std.math.add(u64, ring.revision, 1) catch
                    return error.RevisionOverflow;
                var replacement = try createRenderRing(
                    boundary,
                    &graphics,
                    device,
                    memory_properties,
                    feedback.modifier,
                    dedicated_only,
                    plane_count,
                    requested_physical_width,
                    requested_physical_height,
                    requested.width,
                    requested.height,
                    get_memory_fd.?,
                    get_modifier.?,
                    drm_fd,
                    acquire_handle,
                    next_revision,
                );
                retiring_ring = ring;
                ring = replacement;
                replacement = undefined;
                surface_width = requested_physical_width;
                surface_height = requested_physical_height;
                surface_logical_width = requested.width;
                surface_logical_height = requested.height;
            },
        }
    }
    if (vk.vkDeviceWaitIdle(device) != vk.VK_SUCCESS) return error.DeviceIdle;
    queue_active = false;
    try waitWindowStopped(boundary);
    std.debug.print(
        "Render live loop retired at present={d} render={d} generic_draws={d}\n",
        .{
            present_revision,
            render_revisions[0],
            generic_draw_count_total,
        },
    );
}

fn discardPending(
    scene: *published_scene.Scene,
    prepared: published_scene.Prepared,
) void {
    scene.discardPrepared(prepared) catch |failure|
        @panic(@errorName(failure));
}

fn routePointerEvent(
    boundary: *shared.Boundary,
    event: shared.PointerEvent,
    scale_120: u32,
    mux: *host_layout.Mux,
    scene_panes: *const [2]?host_layout.PaneId,
    scene_count: usize,
    workspace_rows: u16,
    workspace_cols: u16,
    cell_width: u16,
    cell_height: u16,
) !void {
    if (scale_120 == 0 or cell_width == 0 or cell_height == 0)
        return error.InvalidDisplayScale;
    const x = try scaledPointerCoordinate(event.point.x, scale_120);
    const y = try scaledPointerCoordinate(event.point.y, scale_120);
    var storage: [host_layout.max_panes_per_tab]host_layout.Placement = undefined;
    const visible = try projectActivePixels(
        mux,
        workspace_rows,
        workspace_cols,
        cell_width,
        cell_height,
        &storage,
    );
    for (visible) |placement| {
        const right = std.math.add(u32, placement.rect.x, placement.rect.width) catch
            return error.InvalidGeometry;
        const bottom = std.math.add(u32, placement.rect.y, placement.rect.height) catch
            return error.InvalidGeometry;
        if (x < placement.rect.x or x >= right or y < placement.rect.y or y >= bottom)
            continue;
        const scene_index = sceneIndexForPane(
            scene_panes,
            scene_count,
            placement.pane,
        ) orelse return error.SceneTopologyMismatch;
        const pixel_x = x - placement.rect.x;
        const pixel_y = y - placement.rect.y;
        const row_u32 = pixel_y / cell_height;
        const column_u32 = pixel_x / cell_width;
        if (row_u32 > std.math.maxInt(i32) or
            column_u32 > std.math.maxInt(u16))
            return error.InvalidGeometry;
        try boundary.publishInput(.{ .mouse = .{
            .scene_index = @intCast(scene_index),
            .value = .{
                .kind = event.kind,
                .button = event.button,
                .modifiers = event.modifiers,
                .buttons_down = event.buttons_down,
                .row = @intCast(row_u32),
                .column = @intCast(column_u32),
                .pixel_x = pixel_x,
                .pixel_y = pixel_y,
            },
        } });
        return;
    }
}

fn scaledPointerCoordinate(logical: u16, scale_120: u32) !u32 {
    const numerator = std.math.mul(u32, logical, scale_120) catch
        return error.InvalidDisplayScale;
    return numerator / scale_denominator;
}

fn scaledFontPixels(scale_120: u32) !u16 {
    return host_presentation.fontPixels(scale_120);
}

fn scaledExtent(logical: u16, scale_120: u32) !u16 {
    if (logical == 0 or scale_120 == 0) return error.InvalidDisplayScale;
    const numerator = std.math.mul(u32, logical, scale_120) catch
        return error.InvalidDisplayScale;
    const rounded = std.math.add(u32, numerator, scale_denominator - 1) catch
        return error.InvalidDisplayScale;
    const value = rounded / scale_denominator;
    if (value == 0 or value > std.math.maxInt(u16))
        return error.InvalidDisplayScale;
    return @intCast(value);
}

const InitialGeometry = struct {
    surface_width: u16,
    surface_height: u16,
    grid_rows: u16,
    grid_cols: u16,
};

fn establishInitialGeometry(
    boundary: *shared.Boundary,
    scene: *published_scene.Scene,
    mux: host_layout.Mux,
    prepared: *published_scene.Prepared,
    total_rows: u16,
    total_cols: u16,
    surface_width: u16,
    surface_height: u16,
    pixel_storage: *[host_layout.max_panes_per_tab]host_layout.Placement,
) !InitialGeometry {
    if (total_rows == 0 or total_cols == 0 or
        surface_width == 0 or surface_height == 0)
        return error.InvalidGeometry;
    var grid_storage: [host_layout.max_panes_per_tab]host_layout.Placement = undefined;
    const grid = try mux.activeLayout(
        .{ .width = total_cols, .height = total_rows },
        &grid_storage,
    );
    if (grid.len != 1) return error.InvalidGeometry;
    const target = grid[0].rect;
    if (target.width == 0 or target.height == 0 or
        target.width > std.math.maxInt(u16) or
        target.height > std.math.maxInt(u16))
        return error.InvalidGeometry;
    const rows: u16 = @intCast(target.height);
    const cols: u16 = @intCast(target.width);
    const cell_size = prepared.cell_size;
    if (!published_scene.preparedMatchesGeometry(
        prepared.*,
        rows,
        cols,
        cell_size,
    )) {
        try scene.discardPrepared(prepared.*);
        _ = try requestSceneSurface(
            boundary,
            scene,
            prepared,
            surface_width,
            surface_height,
            null,
        );
    }
    const width = std.math.mul(u32, target.width, cell_size.width) catch
        return error.InvalidGeometry;
    const height = std.math.mul(u32, target.height, cell_size.height) catch
        return error.InvalidGeometry;
    pixel_storage[0] = .{
        .pane = grid[0].pane,
        .rect = .{ .x = 0, .y = 0, .width = width, .height = height },
        .focused = grid[0].focused,
    };
    if (prepared.width != width or prepared.height != height)
        return error.ResizeResultMismatch;
    return .{
        .surface_width = surface_width,
        .surface_height = surface_height,
        .grid_rows = total_rows,
        .grid_cols = total_cols,
    };
}

fn requestSceneSurface(
    boundary: *shared.Boundary,
    scene: *published_scene.Scene,
    prepared: *published_scene.Prepared,
    width: u16,
    height: u16,
    font_pixels: ?u16,
) !bool {
    if (width == 0 or height == 0) return error.InvalidGeometry;
    const previous_generation = prepared.presentation_generation;
    if (font_pixels == null and preparedFitsSurface(prepared.*, width, height))
        return false;

    try boundary.publishInput(.{ .geometry = .{
        .width = width,
        .height = height,
        .font_pixels = font_pixels,
    } });
    var attempts: u8 = 0;
    while (attempts < 8) : (attempts += 1) {
        const next = try scene.prepare();
        const generation_matches = if (font_pixels != null)
            next.presentation_generation != previous_generation
        else
            next.presentation_generation == previous_generation;
        if (generation_matches and preparedFitsSurface(next, width, height)) {
            prepared.* = next;
            return true;
        }
        try scene.discardPrepared(next);
    }
    return error.GeometryObservationTimeout;
}

fn preparedFitsSurface(
    prepared: published_scene.Prepared,
    width: u16,
    height: u16,
) bool {
    if (prepared.cell_size.width == 0 or prepared.cell_size.height == 0)
        return false;
    const rows = height / prepared.cell_size.height;
    const columns = width / prepared.cell_size.width;
    if (rows == 0 or columns < 2) return false;
    return prepared.rows == rows and
        prepared.cols == columns and
        prepared.width == columns * prepared.cell_size.width and
        prepared.height == rows * prepared.cell_size.height;
}

fn sceneIndexForPane(
    scene_panes: *const [2]?host_layout.PaneId,
    scene_count: usize,
    pane: host_layout.PaneId,
) ?usize {
    for (scene_panes[0..scene_count], 0..) |candidate, index|
        if (candidate != null and candidate.? == pane) return index;
    return null;
}

fn projectActivePixels(
    mux: *const host_layout.Mux,
    workspace_rows: u16,
    workspace_cols: u16,
    cell_width: u16,
    cell_height: u16,
    output: *[host_layout.max_panes_per_tab]host_layout.Placement,
) ![]const host_layout.Placement {
    var grid_storage: [host_layout.max_panes_per_tab]host_layout.Placement = undefined;
    const grid = try mux.activeLayout(
        .{ .width = workspace_cols, .height = workspace_rows },
        &grid_storage,
    );
    for (grid, output[0..grid.len]) |placed, *pixel| {
        pixel.* = .{
            .pane = placed.pane,
            .rect = .{
                .x = try std.math.mul(u32, placed.rect.x, cell_width),
                .y = try std.math.mul(u32, placed.rect.y, cell_height),
                .width = try std.math.mul(u32, placed.rect.width, cell_width),
                .height = try std.math.mul(u32, placed.rect.height, cell_height),
            },
            .focused = placed.focused,
        };
    }
    return output[0..grid.len];
}

fn waitReady(
    boundary: *shared.Boundary,
    scenes: *[2]?published_scene.Scene,
    scene_count: usize,
    pointer: PointerProjection,
) !Ready {
    if (scene_count != 1 or scenes[0] == null) return error.InvalidGeometry;
    var descriptors = [_]c.pollfd{
        .{ .fd = scenes[0].?.readinessFd(), .events = c.POLLIN, .revents = 0 },
        .{ .fd = boundary.controlFd(), .events = c.POLLIN, .revents = 0 },
    };
    var prefer_scene = false;
    while (true) {
        for (&descriptors) |*descriptor| descriptor.revents = 0;
        const ready = c.poll(&descriptors, descriptors.len, -1);
        if (ready < 0) {
            if (std.c.errno(ready) == .INTR) continue;
            return error.ScenePoll;
        }
        if (boundary.shouldStop()) return error.Stopping;
        if (descriptors[0].revents &
            (c.POLLERR | c.POLLHUP | c.POLLNVAL) != 0 or
            descriptors[1].revents &
                (c.POLLERR | c.POLLHUP | c.POLLNVAL) != 0)
            return error.ScenePoll;

        if (prefer_scene and descriptors[0].revents & c.POLLIN != 0) {
            if (try scenes[0].?.tryReceivePrepared()) |prepared|
                return .{ .scene = .{ .index = 0, .prepared = prepared } };
        }
        if (descriptors[1].revents & c.POLLIN != 0) {
            try boundary.drainControlWake();
            if (boundary.takeWindowSize()) |size| return .{ .window_size = size };
            if (boundary.takeDisplayScale()) |scale| return .{ .display_scale = scale };
            if (boundary.takePointer()) |event| {
                try routePointerEvent(
                    boundary,
                    event,
                    pointer.display_scale_120,
                    pointer.mux,
                    pointer.scene_panes,
                    pointer.scene_count,
                    pointer.workspace_rows,
                    pointer.workspace_cols,
                    pointer.cell_width,
                    pointer.cell_height,
                );
                prefer_scene = true;
                continue;
            }
        }
        if (descriptors[0].revents & c.POLLIN != 0) {
            if (try scenes[0].?.tryReceivePrepared()) |prepared|
                return .{ .scene = .{ .index = 0, .prepared = prepared } };
        }
    }
}

fn waitFeedback(boundary: *shared.Boundary) !shared.Feedback {
    var wakes: u8 = 0;
    while (wakes < 8) : (wakes += 1) {
        if (boundary.readFeedback()) |value| return value;
        if (boundary.shouldStop()) return error.Stopping;
        try waitRenderWake(boundary);
    }
    return error.FeedbackTimeout;
}

fn waitWindowRing(boundary: *shared.Boundary, ring_revision: u64) !void {
    var wakes: u8 = 0;
    while (wakes < 8) : (wakes += 1) {
        if (boundary.isWindowRingReady(ring_revision)) return;
        if (boundary.shouldStop()) return error.Stopping;
        try waitRenderWake(boundary);
    }
    return error.WindowRingTimeout;
}

fn waitWindowStopped(boundary: *shared.Boundary) !void {
    var wakes: u8 = 0;
    while (wakes < 8) : (wakes += 1) {
        if (boundary.stopped().window) return;
        try waitRenderWake(boundary);
    }
    return error.WindowRetirementTimeout;
}

fn waitRenderWake(boundary: *shared.Boundary) !void {
    var descriptor = c.pollfd{ .fd = boundary.renderFd(), .events = c.POLLIN, .revents = 0 };
    while (true) {
        const result = c.poll(&descriptor, 1, 2_000);
        if (result > 0) return boundary.drainRenderWake();
        if (result == 0) return error.WakeTimeout;
        if (std.c.errno(result) != .INTR) return error.Wake;
    }
}

const Physical = struct {
    device: vk.VkPhysicalDevice,
    render_major: i64,
    render_minor: i64,
};

fn selectPhysical(instance: vk.VkInstance, feedback_device: u64) !Physical {
    const feedback_major = c.major(feedback_device);
    const feedback_minor = c.minor(feedback_device);
    var count: u32 = 0;
    if (vk.vkEnumeratePhysicalDevices(instance, &count, null) != vk.VK_SUCCESS or count == 0 or count > 8) return error.PhysicalDevice;
    var devices: [8]vk.VkPhysicalDevice = undefined;
    if (vk.vkEnumeratePhysicalDevices(instance, &count, &devices) != vk.VK_SUCCESS) return error.PhysicalDevice;
    for (devices[0..count]) |device| {
        var drm = std.mem.zeroes(vk.VkPhysicalDeviceDrmPropertiesEXT);
        drm.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRM_PROPERTIES_EXT;
        var properties = std.mem.zeroes(vk.VkPhysicalDeviceProperties2);
        properties.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2;
        properties.pNext = @ptrCast(&drm);
        vk.vkGetPhysicalDeviceProperties2(device, &properties);
        const render_match = drm.hasRender != 0 and drm.renderMajor == feedback_major and drm.renderMinor == feedback_minor;
        const primary_match = drm.hasPrimary != 0 and drm.primaryMajor == feedback_major and drm.primaryMinor == feedback_minor;
        if (render_match or primary_match) {
            if (drm.hasRender == 0) return error.PhysicalDevice;
            return .{ .device = device, .render_major = drm.renderMajor, .render_minor = drm.renderMinor };
        }
    }
    return error.PhysicalDevice;
}

fn openRenderNode(major: i64, minor: i64) !i32 {
    var path: [64]u8 = undefined;
    for (128..256) |index| {
        const name_bytes = std.fmt.bufPrint(path[0 .. path.len - 1], "/dev/dri/renderD{d}", .{index}) catch return error.DrmOpen;
        path[name_bytes.len] = 0;
        const name: [*:0]const u8 = @ptrCast(&path);
        var status: c.struct_stat = undefined;
        if (c.stat(name, &status) != 0) continue;
        if (c.major(status.st_rdev) != major or c.minor(status.st_rdev) != minor) continue;
        const descriptor = c.open(name, c.O_RDWR | c.O_CLOEXEC);
        if (descriptor >= 0) return descriptor;
        return error.DrmOpen;
    }
    return error.DrmOpen;
}

fn requireExtensions(physical: vk.VkPhysicalDevice) !void {
    var count: u32 = 0;
    if (vk.vkEnumerateDeviceExtensionProperties(physical, null, &count, null) != vk.VK_SUCCESS or count > 512) return error.Extensions;
    var properties: [512]vk.VkExtensionProperties = undefined;
    if (vk.vkEnumerateDeviceExtensionProperties(physical, null, &count, &properties) != vk.VK_SUCCESS) return error.Extensions;
    const required = [_][]const u8{
        "VK_EXT_external_memory_dma_buf",
        "VK_EXT_image_drm_format_modifier",
        "VK_KHR_external_memory_fd",
        "VK_KHR_external_semaphore_fd",
        "VK_KHR_timeline_semaphore",
        "VK_KHR_synchronization2",
    };
    for (required) |name| {
        for (properties[0..count]) |property| {
            if (std.mem.eql(u8, std.mem.sliceTo(&property.extensionName, 0), name)) break;
        } else return error.Extensions;
    }
}

fn queryFormat(physical: vk.VkPhysicalDevice, modifier: u64) !bool {
    var modifier_info = std.mem.zeroes(vk.VkPhysicalDeviceImageDrmFormatModifierInfoEXT);
    modifier_info.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_DRM_FORMAT_MODIFIER_INFO_EXT;
    modifier_info.drmFormatModifier = modifier;
    modifier_info.sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE;
    var external_info = std.mem.zeroes(vk.VkPhysicalDeviceExternalImageFormatInfo);
    external_info.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTERNAL_IMAGE_FORMAT_INFO;
    external_info.handleType = vk.VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT;
    external_info.pNext = @ptrCast(&modifier_info);
    var info = std.mem.zeroes(vk.VkPhysicalDeviceImageFormatInfo2);
    info.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_FORMAT_INFO_2;
    info.format = vk.VK_FORMAT_R8G8B8A8_UNORM;
    info.type = vk.VK_IMAGE_TYPE_2D;
    info.tiling = vk.VK_IMAGE_TILING_DRM_FORMAT_MODIFIER_EXT;
    info.usage = vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    info.pNext = @ptrCast(&external_info);
    var external = std.mem.zeroes(vk.VkExternalImageFormatProperties);
    external.sType = vk.VK_STRUCTURE_TYPE_EXTERNAL_IMAGE_FORMAT_PROPERTIES;
    var properties = std.mem.zeroes(vk.VkImageFormatProperties2);
    properties.sType = vk.VK_STRUCTURE_TYPE_IMAGE_FORMAT_PROPERTIES_2;
    properties.pNext = @ptrCast(&external);
    if (vk.vkGetPhysicalDeviceImageFormatProperties2(physical, &info, &properties) != vk.VK_SUCCESS) return error.ImageFormat;
    const value = external.externalMemoryProperties;
    if ((value.externalMemoryFeatures & vk.VK_EXTERNAL_MEMORY_FEATURE_EXPORTABLE_BIT) == 0 or (value.compatibleHandleTypes & vk.VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT) == 0) return error.ImageFormat;
    return (value.externalMemoryFeatures & vk.VK_EXTERNAL_MEMORY_FEATURE_DEDICATED_ONLY_BIT) != 0;
}

fn graphicsFamily(physical: vk.VkPhysicalDevice) !u32 {
    var count: u32 = 0;
    vk.vkGetPhysicalDeviceQueueFamilyProperties(physical, &count, null);
    if (count == 0 or count > 32) return error.Queue;
    var properties: [32]vk.VkQueueFamilyProperties = undefined;
    vk.vkGetPhysicalDeviceQueueFamilyProperties(physical, &count, &properties);
    for (properties[0..count], 0..) |property, index| {
        if ((property.queueFlags & vk.VK_QUEUE_GRAPHICS_BIT) != 0) return @intCast(index);
    }
    return error.Queue;
}

fn modifierPlaneCount(physical: vk.VkPhysicalDevice, modifier: u64) !u8 {
    var list = std.mem.zeroes(vk.VkDrmFormatModifierPropertiesListEXT);
    list.sType = vk.VK_STRUCTURE_TYPE_DRM_FORMAT_MODIFIER_PROPERTIES_LIST_EXT;
    var properties = std.mem.zeroes(vk.VkFormatProperties2);
    properties.sType = vk.VK_STRUCTURE_TYPE_FORMAT_PROPERTIES_2;
    properties.pNext = @ptrCast(&list);
    vk.vkGetPhysicalDeviceFormatProperties2(physical, vk.VK_FORMAT_R8G8B8A8_UNORM, &properties);
    if (list.drmFormatModifierCount == 0 or list.drmFormatModifierCount > 64) return error.Modifier;
    var values: [64]vk.VkDrmFormatModifierPropertiesEXT = undefined;
    list.pDrmFormatModifierProperties = &values;
    vk.vkGetPhysicalDeviceFormatProperties2(physical, vk.VK_FORMAT_R8G8B8A8_UNORM, &properties);
    for (values[0..list.drmFormatModifierCount]) |value| {
        if (value.drmFormatModifier == modifier and value.drmFormatModifierPlaneCount > 0 and value.drmFormatModifierPlaneCount <= shared.plane_limit) return @intCast(value.drmFormatModifierPlaneCount);
    }
    return error.Modifier;
}

fn createRenderRing(
    boundary: *shared.Boundary,
    graphics: *const surface.Context,
    device: vk.VkDevice,
    memory_properties: vk.VkPhysicalDeviceMemoryProperties,
    modifier: u64,
    dedicated_only: bool,
    plane_count: u8,
    width: u16,
    height: u16,
    logical_width: u16,
    logical_height: u16,
    get_memory_fd: vk.PFN_vkGetMemoryFdKHR,
    get_modifier: vk.PFN_vkGetImageDrmFormatModifierPropertiesEXT,
    drm_fd: i32,
    acquire_handle: u32,
    revision: u64,
) !RenderRing {
    if (revision == 0 or width == 0 or height == 0 or logical_width == 0 or logical_height == 0)
        return error.InvalidRing;
    var result = RenderRing{ .revision = revision, .width = width, .height = height };
    errdefer result.deinit(device, drm_fd);
    var offers: [shared.slot_count]shared.SlotOffer = undefined;
    var offered_fds = [_]OfferedFds{ .{}, .{}, .{} };
    errdefer for (&offered_fds) |*fds| {
        if (fds.dma >= 0) closeDescriptor(fds.dma);
        if (fds.acquire >= 0) closeDescriptor(fds.acquire);
        if (fds.timeline >= 0) closeDescriptor(fds.timeline);
    };
    for (&result.slots, 0..) |*slot, index| {
        try constructSlot(
            slot,
            graphics,
            device,
            memory_properties,
            modifier,
            dedicated_only,
            plane_count,
            width,
            height,
            get_memory_fd,
            get_modifier,
            drm_fd,
            &offers[index],
            &offered_fds[index],
        );
        offers[index].ring_revision = revision;
        offers[index].logical_width = logical_width;
        offers[index].logical_height = logical_height;
        if (c.drmSyncobjHandleToFD(drm_fd, acquire_handle, &offered_fds[index].acquire) != 0)
            return error.Syncobj;
        offers[index].acquire_timeline_fd = offered_fds[index].acquire;
    }
    try boundary.publishOffers(offers);
    for (&offered_fds) |*fds| fds.* = .{};
    try waitWindowRing(boundary, revision);
    return result;
}

fn constructSlot(slot: *Slot, graphics: *const surface.Context, device: vk.VkDevice, memory_properties: vk.VkPhysicalDeviceMemoryProperties, modifier: u64, dedicated_only: bool, plane_count: u8, width: u16, height: u16, get_memory_fd: vk.PFN_vkGetMemoryFdKHR, get_modifier: vk.PFN_vkGetImageDrmFormatModifierPropertiesEXT, drm_fd: i32, offer: *shared.SlotOffer, offered_fds: *OfferedFds) !void {
    var selected_modifier = modifier;
    var modifier_list = std.mem.zeroes(vk.VkImageDrmFormatModifierListCreateInfoEXT);
    modifier_list.sType = vk.VK_STRUCTURE_TYPE_IMAGE_DRM_FORMAT_MODIFIER_LIST_CREATE_INFO_EXT;
    modifier_list.drmFormatModifierCount = 1;
    modifier_list.pDrmFormatModifiers = &selected_modifier;
    var external = std.mem.zeroes(vk.VkExternalMemoryImageCreateInfo);
    external.sType = vk.VK_STRUCTURE_TYPE_EXTERNAL_MEMORY_IMAGE_CREATE_INFO;
    external.handleTypes = vk.VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT;
    external.pNext = @ptrCast(&modifier_list);
    var info = std.mem.zeroes(vk.VkImageCreateInfo);
    info.sType = vk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    info.pNext = @ptrCast(&external);
    info.imageType = vk.VK_IMAGE_TYPE_2D;
    info.format = vk.VK_FORMAT_R8G8B8A8_UNORM;
    info.extent = .{ .width = width, .height = height, .depth = 1 };
    info.mipLevels = 1;
    info.arrayLayers = 1;
    info.samples = vk.VK_SAMPLE_COUNT_1_BIT;
    info.tiling = vk.VK_IMAGE_TILING_DRM_FORMAT_MODIFIER_EXT;
    info.usage = vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    info.sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE;
    info.initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED;
    if (vk.vkCreateImage(device, &info, null, &slot.image) != vk.VK_SUCCESS) return error.Image;
    var requirements: vk.VkMemoryRequirements = undefined;
    vk.vkGetImageMemoryRequirements(device, slot.image, &requirements);
    var memory_type: ?u32 = null;
    for (0..memory_properties.memoryTypeCount) |index| {
        if ((requirements.memoryTypeBits & (@as(u32, 1) << @intCast(index))) != 0 and (memory_properties.memoryTypes[index].propertyFlags & vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) != 0) {
            memory_type = @intCast(index);
            break;
        }
    }
    var export_info = std.mem.zeroes(vk.VkExportMemoryAllocateInfo);
    export_info.sType = vk.VK_STRUCTURE_TYPE_EXPORT_MEMORY_ALLOCATE_INFO;
    export_info.handleTypes = vk.VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT;
    var dedicated = std.mem.zeroes(vk.VkMemoryDedicatedAllocateInfo);
    dedicated.sType = vk.VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO;
    dedicated.image = slot.image;
    export_info.pNext = if (dedicated_only) @ptrCast(&dedicated) else null;
    var allocation = std.mem.zeroes(vk.VkMemoryAllocateInfo);
    allocation.sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    allocation.pNext = @ptrCast(&export_info);
    allocation.allocationSize = requirements.size;
    allocation.memoryTypeIndex = memory_type orelse return error.Memory;
    if (vk.vkAllocateMemory(device, &allocation, null, &slot.memory) != vk.VK_SUCCESS) return error.Memory;
    if (vk.vkBindImageMemory(device, slot.image, slot.memory, 0) != vk.VK_SUCCESS) return error.Memory;
    slot.attachment = try graphics.createAttachment(device, slot.image, width, height);
    var actual = std.mem.zeroes(vk.VkImageDrmFormatModifierPropertiesEXT);
    actual.sType = vk.VK_STRUCTURE_TYPE_IMAGE_DRM_FORMAT_MODIFIER_PROPERTIES_EXT;
    if (get_modifier.?(device, slot.image, &actual) != vk.VK_SUCCESS or actual.drmFormatModifier != modifier) return error.Modifier;
    const aspects = [_]vk.VkImageAspectFlags{ vk.VK_IMAGE_ASPECT_MEMORY_PLANE_0_BIT_EXT, vk.VK_IMAGE_ASPECT_MEMORY_PLANE_1_BIT_EXT, vk.VK_IMAGE_ASPECT_MEMORY_PLANE_2_BIT_EXT, vk.VK_IMAGE_ASPECT_MEMORY_PLANE_3_BIT_EXT };
    slot.plane_count = plane_count;
    for (0..plane_count) |plane| {
        const subresource = vk.VkImageSubresource{ .aspectMask = aspects[plane], .mipLevel = 0, .arrayLayer = 0 };
        var layout: vk.VkSubresourceLayout = undefined;
        vk.vkGetImageSubresourceLayout(device, slot.image, &subresource, &layout);
        if (layout.offset > std.math.maxInt(u32) or layout.rowPitch > std.math.maxInt(u32)) return error.Plane;
        slot.planes[plane] = .{ .offset = @intCast(layout.offset), .stride = @intCast(layout.rowPitch) };
    }
    var fd_info = std.mem.zeroes(vk.VkMemoryGetFdInfoKHR);
    fd_info.sType = vk.VK_STRUCTURE_TYPE_MEMORY_GET_FD_INFO_KHR;
    fd_info.memory = slot.memory;
    fd_info.handleType = vk.VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT;
    if (get_memory_fd.?(device, &fd_info, &offered_fds.dma) != vk.VK_SUCCESS or offered_fds.dma < 0) return error.DmaBuf;
    if (c.drmSyncobjCreate(drm_fd, 0, &slot.release_handle) != 0) return error.Syncobj;
    if (c.drmSyncobjHandleToFD(drm_fd, slot.release_handle, &offered_fds.timeline) != 0) return error.Syncobj;
    offer.* = .{ .ring_revision = 0, .dma_fd = offered_fds.dma, .acquire_timeline_fd = -1, .release_timeline_fd = offered_fds.timeline, .width = width, .height = height, .logical_width = 0, .logical_height = 0, .plane_count = plane_count, .planes = slot.planes };
}

fn render(
    graphics: *surface.Context,
    plan: surface.Plan,
    alpha_pixels: []const u8,
    image_pixels: []const u8,
    device: vk.VkDevice,
    queue: vk.VkQueue,
    family: u32,
    command: vk.VkCommandBuffer,
    slot: *Slot,
    clear_color: [4]f32,
    wait_semaphore: ?vk.VkSemaphore,
    get_semaphore_fd: vk.PFN_vkGetSemaphoreFdKHR,
    drm_fd: i32,
    acquire_handle: u32,
    acquire_point: u64,
    width: u16,
    height: u16,
) !void {
    try graphics.stage(plan, alpha_pixels, image_pixels, width, height);

    if (vk.vkResetCommandBuffer(command, 0) != vk.VK_SUCCESS)
        return error.Command;
    var begin = std.mem.zeroes(vk.VkCommandBufferBeginInfo);
    begin.sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    if (vk.vkBeginCommandBuffer(command, &begin) != vk.VK_SUCCESS)
        return error.Command;
    const target = surface.FrameTarget{
        .image = slot.image,
        .attachment = slot.attachment,
        .attachment_width = width,
        .attachment_height = height,
        .coordinate_width = width,
        .coordinate_height = height,
        .source_queue_family = if (slot.external)
            vk.VK_QUEUE_FAMILY_EXTERNAL
        else
            vk.VK_QUEUE_FAMILY_IGNORED,
        .graphics_queue_family = family,
        .destination_queue_family = vk.VK_QUEUE_FAMILY_EXTERNAL,
    };
    const recording = try graphics.recordPrelude(command, target, plan);
    graphics.beginPass(command, target, clear_color);
    graphics.recordGenericDraws(command, target, plan);
    const completed_recording = graphics.endPass(command, target, recording);
    if (vk.vkEndCommandBuffer(command) != vk.VK_SUCCESS) return error.Command;

    var export_info = std.mem.zeroes(vk.VkExportSemaphoreCreateInfo);
    export_info.sType = vk.VK_STRUCTURE_TYPE_EXPORT_SEMAPHORE_CREATE_INFO;
    export_info.handleTypes = vk.VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_SYNC_FD_BIT;
    var semaphore_info = std.mem.zeroes(vk.VkSemaphoreCreateInfo);
    semaphore_info.sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
    semaphore_info.pNext = @ptrCast(&export_info);
    var completion: vk.VkSemaphore = undefined;
    if (vk.vkCreateSemaphore(device, &semaphore_info, null, &completion) !=
        vk.VK_SUCCESS)
        return error.Semaphore;
    defer vk.vkDestroySemaphore(device, completion, null);

    const wait_stage: vk.VkPipelineStageFlags =
        vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    var submit = std.mem.zeroes(vk.VkSubmitInfo);
    submit.sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO;
    if (wait_semaphore) |wait| {
        submit.waitSemaphoreCount = 1;
        submit.pWaitSemaphores = &wait;
        submit.pWaitDstStageMask = &wait_stage;
    }
    submit.commandBufferCount = 1;
    submit.pCommandBuffers = &command;
    submit.signalSemaphoreCount = 1;
    submit.pSignalSemaphores = &completion;
    if (vk.vkQueueSubmit(queue, 1, &submit, null) != vk.VK_SUCCESS)
        return error.Submit;

    var fd_info = std.mem.zeroes(vk.VkSemaphoreGetFdInfoKHR);
    fd_info.sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_GET_FD_INFO_KHR;
    fd_info.semaphore = completion;
    fd_info.handleType = vk.VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_SYNC_FD_BIT;
    var sync_fd: i32 = -1;
    if (get_semaphore_fd.?(device, &fd_info, &sync_fd) != vk.VK_SUCCESS or
        sync_fd < 0)
        return error.Semaphore;
    defer closeDescriptor(sync_fd);

    var temporary: u32 = 0;
    if (c.drmSyncobjCreate(drm_fd, 0, &temporary) != 0)
        return error.Syncobj;
    defer destroySyncobj(drm_fd, temporary);
    if (c.drmSyncobjImportSyncFile(drm_fd, temporary, sync_fd) != 0)
        return error.Syncobj;
    var handles = [_]u32{temporary};
    if (c.drmSyncobjWait(
        drm_fd,
        &handles,
        1,
        try deadline(),
        0,
        null,
    ) != 0) return error.RenderTimeout;

    graphics.complete(completed_recording);
    if (c.drmSyncobjTransfer(
        drm_fd,
        acquire_handle,
        acquire_point,
        temporary,
        0,
        0,
    ) != 0) return error.Syncobj;
    try waitTimeline(drm_fd, acquire_handle, acquire_point);
    slot.external = true;
}

fn importRelease(device: vk.VkDevice, drm_fd: i32, release_handle: u32, point: u64, import_fd: vk.PFN_vkImportSemaphoreFdKHR) !vk.VkSemaphore {
    var temporary: u32 = 0;
    if (c.drmSyncobjCreate(drm_fd, 0, &temporary) != 0) return error.Syncobj;
    defer destroySyncobj(drm_fd, temporary);
    if (c.drmSyncobjTransfer(drm_fd, temporary, 0, release_handle, point, 0) != 0) return error.Syncobj;
    var fd: i32 = -1;
    if (c.drmSyncobjExportSyncFile(drm_fd, temporary, &fd) != 0 or fd < 0) return error.Syncobj;
    var owned = true;
    defer {
        if (owned) closeDescriptor(fd);
    }
    var info = std.mem.zeroes(vk.VkSemaphoreCreateInfo);
    info.sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
    var semaphore: vk.VkSemaphore = undefined;
    if (vk.vkCreateSemaphore(device, &info, null, &semaphore) != vk.VK_SUCCESS) return error.Semaphore;
    errdefer vk.vkDestroySemaphore(device, semaphore, null);
    var import_info = std.mem.zeroes(vk.VkImportSemaphoreFdInfoKHR);
    import_info.sType = vk.VK_STRUCTURE_TYPE_IMPORT_SEMAPHORE_FD_INFO_KHR;
    import_info.semaphore = semaphore;
    // Vulkan 1.x VkSemaphoreImportFlagBits: TEMPORARY_BIT = 0x1.
    import_info.flags = 1;
    import_info.handleType = vk.VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_SYNC_FD_BIT;
    import_info.fd = fd;
    if (import_fd.?(device, &import_info) != vk.VK_SUCCESS) return error.Semaphore;
    owned = false;
    return semaphore;
}

fn waitRenderRingReleased(ring: *const RenderRing, drm_fd: i32) !void {
    for (ring.slots) |slot| {
        if (!slot.external or slot.release_point == 0) continue;
        try waitTimeline(drm_fd, slot.release_handle, slot.release_point);
    }
}

fn waitTimeline(drm_fd: i32, handle: u32, point: u64) !void {
    var handles = [_]u32{handle};
    var points = [_]u64{point};
    const flags = c.DRM_SYNCOBJ_WAIT_FLAGS_WAIT_FOR_SUBMIT | c.DRM_SYNCOBJ_WAIT_FLAGS_WAIT_AVAILABLE;
    if (c.drmSyncobjTimelineWait(drm_fd, &handles, &points, 1, try deadline(), flags, null) != 0) return error.ReleaseAvailability;
    if (c.drmSyncobjTimelineWait(drm_fd, &handles, &points, 1, try deadline(), 0, null) != 0) return error.ReleaseCompletion;
}

fn deadline() !i64 {
    var now: c.timespec = undefined;
    if (c.clock_gettime(c.CLOCK_MONOTONIC, &now) != 0) return error.Clock;
    const seconds = try std.math.mul(u64, @intCast(now.tv_sec), 1_000_000_000);
    const current = try std.math.add(u64, seconds, @intCast(now.tv_nsec));
    return @intCast(try std.math.add(u64, current, 2_000_000_000));
}

fn closeDescriptor(descriptor: i32) void {
    if (c.close(descriptor) != 0) @panic("Render descriptor cleanup failed");
}

fn destroySyncobj(drm_fd: i32, handle: u32) void {
    if (c.drmSyncobjDestroy(drm_fd, handle) != 0) @panic("Render syncobj cleanup failed");
}
