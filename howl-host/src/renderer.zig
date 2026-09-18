//! Exclusively owns Vulkan mutation and DRM release observation.

const std = @import("std");
const c = @import("renderer_c");
const client = @import("howl_client");
const host_layout = @import("layout.zig");
const shared = @import("shared.zig");
const session_process = @import("session_process.zig");
const terminal_scene = @import("terminal_scene.zig");
const terminal_fast = @import("terminal_fast.zig");
const howl_vk = @import("howl_vk");
const vk = howl_vk.abi;
const surface = howl_vk.surface;

const gpu_memory_limit: u64 = 512 * 1024 * 1024;
const base_font_pixels: u16 = 16;
const scale_denominator: u32 = 120;
const empty_plan = surface.Plan{
    .vertices = &.{},
    .indices = &.{},
    .commands = &.{},
    .atlas_changed = false,
};

const CancellationRegistry = struct {
    io: std.Io,
    mutex: std.Io.Mutex = .init,
    slots: [2]?client.Cancellation = .{ null, null },

    fn set(self: *CancellationRegistry, index: usize, cancellation: client.Cancellation) !void {
        if (index >= self.slots.len) return error.CancellationSlot;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.slots[index] != null) return error.CancellationSlot;
        self.slots[index] = cancellation;
    }

    fn clear(self: *CancellationRegistry, index: usize) void {
        if (index >= self.slots.len) return;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.slots[index]) |*value| value.deinit();
        self.slots[index] = null;
    }

    fn cancelAll(self: *CancellationRegistry, boundary: *shared.Boundary) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        for (&self.slots) |*slot| if (slot.*) |value|
            value.cancel() catch boundary.requestStop(.render);
    }

    fn deinit(self: *CancellationRegistry) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        for (&self.slots) |*slot| {
            if (slot.*) |*value| value.deinit();
            slot.* = null;
        }
    }
};

const FastDraw = struct {
    gpu: *terminal_fast.Gpu,
    frame: terminal_fast.Prepared,
    placement: terminal_fast.Placement,
    changed: bool,
};

const DuetReady = union(enum) {
    scene: usize,
    command: shared.HostCommand,
    window_size: shared.WindowSize,
    display_scale: shared.DisplayScale,
    pointer: shared.PointerEvent,
};

const GenericDraw = struct {
    context: *surface.Context,
    plan: surface.Plan,
    placement: surface.Placement,
    alpha_pixels: []const u8,
    image_pixels: []const u8,
    residency: *surface.ResidencyStore,
    stage: bool,
    residency_changed: bool,
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
    endpoint: []const u8,
    endpoint_right: ?[]const u8,
    font_path: []const u8,
    mux: host_layout.Mux,
    runtime_dir: ?[]const u8,
    shell: []const u8,
    environ_map: *const std.process.Environ.Map,
) void {
    runFallible(
        boundary,
        allocator,
        endpoint,
        endpoint_right,
        font_path,
        mux,
        runtime_dir,
        shell,
        environ_map,
    ) catch |failure| {
        std.debug.print("Render failure: {s}\n", .{@errorName(failure)});
        boundary.requestStop(.render);
    };
    boundary.markStopped(.render);
}

fn runFallible(
    boundary: *shared.Boundary,
    allocator: std.mem.Allocator,
    endpoint: []const u8,
    endpoint_right: ?[]const u8,
    font_path: []const u8,
    initial_mux: host_layout.Mux,
    runtime_dir: ?[]const u8,
    shell: []const u8,
    environ_map: *const std.process.Environ.Map,
) !void {
    var mux = initial_mux;
    const feedback = try waitFeedback(boundary);
    var display_scale_120 = (try waitDisplayScale(boundary)).scale_120;
    var font_pixels = try scaledFontPixels(display_scale_120);
    const logical_cell_size = try terminal_scene.measureCellSize(allocator, font_path, base_font_pixels);
    var scene_count: usize = if (endpoint_right != null) 2 else 1;
    var spawned_session: ?session_process.SessionProcess = null;
    defer if (spawned_session) |*session| session.deinit();
    var scenes: [2]?terminal_scene.Scene = .{ null, null };
    var initialized_scene_count: usize = 0;
    defer {
        var scene_index = initialized_scene_count;
        while (scene_index != 0) {
            scene_index -= 1;
            scenes[scene_index].?.deinit();
        }
    }
    scenes[0] = try terminal_scene.Scene.init(allocator, endpoint, font_path, font_pixels);
    initialized_scene_count = 1;
    if (endpoint_right) |right| {
        scenes[1] = try terminal_scene.Scene.init(allocator, right, font_path, font_pixels);
        initialized_scene_count = 2;
    }
    var geometry_controls: [2]?client.Connection = .{ null, null };
    var geometry_control_count: usize = 0;
    defer {
        var control_index = geometry_control_count;
        while (control_index != 0) {
            control_index -= 1;
            geometry_controls[control_index].?.deinit();
        }
    }
    geometry_controls[0] = try client.Connection.connect(allocator, endpoint);
    geometry_control_count = 1;
    if (endpoint_right) |right| {
        geometry_controls[1] = try client.Connection.connect(allocator, right);
        geometry_control_count = 2;
    }
    var prepared: [2]terminal_scene.Prepared = undefined;
    var session_revisions: [2]u64 = @splat(0);
    for (0..scene_count) |scene_index| {
        prepared[scene_index] = try scenes[scene_index].?.prepare(0);
        session_revisions[scene_index] = prepared[scene_index].session_revision;
    }
    const initial_logical_width = std.math.mul(u16, prepared[0].cols, logical_cell_size.width) catch
        return error.DuetGeometry;
    const initial_logical_height = std.math.mul(u16, prepared[0].rows, logical_cell_size.height) catch
        return error.DuetGeometry;
    var surface_logical_width = initial_logical_width;
    var surface_logical_height = initial_logical_height;
    var surface_width = try scaledExtent(surface_logical_width, display_scale_120);
    var surface_height = try scaledExtent(surface_logical_height, display_scale_120);
    var cell_size = scenes[0].?.cellSize();
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
    var geometry_owned: [2]bool = @splat(false);
    const established = try establishInitialGeometry(
        &scenes,
        &geometry_controls,
        &geometry_owned,
        scene_count,
        mux,
        &prepared,
        &session_revisions,
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
    var fast_gpus: [2]?terminal_fast.Gpu = .{ null, null };
    defer {
        var gpu_index = initialized_scene_count;
        while (gpu_index != 0) {
            gpu_index -= 1;
            if (fast_gpus[gpu_index]) |*value| value.deinit(device, &gpu_bytes);
        }
    }
    var generic_contexts: [2]?surface.Context = .{ null, null };
    defer {
        var context_index = initialized_scene_count;
        while (context_index != 0) {
            context_index -= 1;
            if (generic_contexts[context_index]) |*value|
                value.deinit(device, &gpu_bytes);
        }
    }
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
    var changed: [2]bool = .{ true, scene_count == 2 };
    var surface_restage = false;
    var retained_draw_count: u64 = 0;
    var generic_draw_count_total: u64 = 0;
    var observation_armed: [2]bool = @splat(false);
    var next_ready_start: usize = 0;

    var cancellation_registry = CancellationRegistry{ .io = boundary.runtimeIo() };
    defer cancellation_registry.deinit();
    for (0..scene_count) |scene_index|
        try cancellation_registry.set(scene_index, try scenes[scene_index].?.cancellation());
    var watcher_done = std.atomic.Value(bool).init(false);
    const watcher = try std.Thread.spawn(.{}, watchStop, .{
        boundary,
        &cancellation_registry,
        &watcher_done,
    });
    defer {
        watcher_done.store(true, .release);
        watcher.join();
    }

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
        if (visible.len == 0 or visible.len > scene_count) return error.SceneTopologyMismatch;
        var plan = empty_plan;
        var clear_color = [4]f32{ 0, 0, 0, 1 };
        var residency_commit: ?*surface.ResidencyStore = null;
        var primary_alpha_pixels = scenes[0].?.builder.alpha_pixels;
        var primary_image_pixels = scenes[0].?.builder.rgba_pixels;
        var fast_draw_storage: [2]FastDraw = undefined;
        var fast_draw_count: usize = 0;
        var generic_draw_storage: [2]GenericDraw = undefined;
        var generic_draw_count: usize = 0;
        if (visible.len == 1) {
            const scene_index = sceneIndexForPane(&scene_panes, scene_count, visible[0].pane) orelse
                return error.SceneTopologyMismatch;
            primary_alpha_pixels = scenes[scene_index].?.builder.alpha_pixels;
            primary_image_pixels = scenes[scene_index].?.builder.rgba_pixels;
            switch (prepared[scene_index].mode) {
                .generic => |generic| {
                    generic_draw_count_total += 1;
                    plan = generic.plan;
                    if (changed[scene_index]) residency_commit = &scenes[scene_index].?.residency;
                },
                .fast => |frame| {
                    retained_draw_count += 1;
                    if (changed[scene_index] and fast_gpus[scene_index] != null and
                        !fast_gpus[scene_index].?.geometryMatches(frame.terminal))
                    {
                        fast_gpus[scene_index].?.deinit(device, &gpu_bytes);
                        fast_gpus[scene_index] = null;
                    }
                    if (fast_gpus[scene_index] == null)
                        fast_gpus[scene_index] = try terminal_fast.Gpu.init(
                            allocator,
                            device,
                            memory_properties,
                            graphics.render_pass,
                            &gpu_bytes,
                            gpu_memory_limit,
                            frame.terminal,
                        );
                    if (changed[scene_index]) try fast_gpus[scene_index].?.prepare(frame.terminal);
                    fast_draw_storage[0] = .{
                        .gpu = &fast_gpus[scene_index].?,
                        .frame = frame.terminal,
                        .placement = fastPlacement(visible[0]),
                        .changed = changed[scene_index],
                    };
                    fast_draw_count = 1;
                    clear_color = frame.terminal.clear_color;
                    plan = frame.plan;
                    if (changed[scene_index] and frame.overlay_pending)
                        residency_commit = &scenes[scene_index].?.overlay_residency;
                },
            }
        } else {
            for (visible) |placed| {
                const scene_index = sceneIndexForPane(&scene_panes, scene_count, placed.pane) orelse
                    return error.SceneTopologyMismatch;
                const placement = surfacePlacement(placed);
                switch (prepared[scene_index].mode) {
                    .generic => |frame| {
                        generic_draw_count_total += 1;
                        if (generic_contexts[scene_index] == null)
                            generic_contexts[scene_index] = try surface.Context.init(
                                device,
                                memory_properties,
                                &gpu_bytes,
                                gpu_memory_limit,
                            );
                        generic_draw_storage[generic_draw_count] = .{
                            .context = &generic_contexts[scene_index].?,
                            .plan = frame.plan,
                            .placement = placement,
                            .alpha_pixels = scenes[scene_index].?.builder.alpha_pixels,
                            .image_pixels = scenes[scene_index].?.builder.rgba_pixels,
                            .residency = &scenes[scene_index].?.residency,
                            .stage = changed[scene_index] or surface_restage,
                            .residency_changed = changed[scene_index],
                        };
                        generic_draw_count += 1;
                    },
                    .fast => |frame| {
                        retained_draw_count += 1;
                        if (changed[scene_index] and fast_gpus[scene_index] != null and
                            !fast_gpus[scene_index].?.geometryMatches(frame.terminal))
                        {
                            fast_gpus[scene_index].?.deinit(device, &gpu_bytes);
                            fast_gpus[scene_index] = null;
                        }
                        if (fast_gpus[scene_index] == null)
                            fast_gpus[scene_index] = try terminal_fast.Gpu.init(
                                allocator,
                                device,
                                memory_properties,
                                graphics.render_pass,
                                &gpu_bytes,
                                gpu_memory_limit,
                                frame.terminal,
                            );
                        if (changed[scene_index]) try fast_gpus[scene_index].?.prepare(frame.terminal);
                        fast_draw_storage[fast_draw_count] = .{
                            .gpu = &fast_gpus[scene_index].?,
                            .frame = frame.terminal,
                            .placement = fastPlacement(placed),
                            .changed = changed[scene_index],
                        };
                        fast_draw_count += 1;
                        if (frame.overlay_pending) {
                            if (generic_contexts[scene_index] == null)
                                generic_contexts[scene_index] = try surface.Context.init(
                                    device,
                                    memory_properties,
                                    &gpu_bytes,
                                    gpu_memory_limit,
                                );
                            generic_draw_storage[generic_draw_count] = .{
                                .context = &generic_contexts[scene_index].?,
                                .plan = frame.plan,
                                .placement = placement,
                                .alpha_pixels = scenes[scene_index].?.builder.alpha_pixels,
                                .image_pixels = scenes[scene_index].?.builder.rgba_pixels,
                                .residency = &scenes[scene_index].?.overlay_residency,
                                .stage = changed[scene_index] or surface_restage,
                                .residency_changed = changed[scene_index],
                            };
                            generic_draw_count += 1;
                        }
                    },
                }
            }
        }
        const fast_draws = fast_draw_storage[0..fast_draw_count];
        const generic_draws = generic_draw_storage[0..generic_draw_count];
        errdefer for (fast_draws) |draw| if (draw.changed) draw.gpu.discard();
        errdefer for (generic_draws) |draw| if (draw.residency_changed) draw.residency.discard();
        try render(
            &graphics,
            plan,
            primary_alpha_pixels,
            primary_image_pixels,
            device,
            queue,
            family,
            command,
            slot,
            clear_color,
            residency_commit,
            fast_draws,
            generic_draws,
            wait_semaphore,
            get_semaphore_fd.?,
            drm_fd,
            acquire_handle,
            acquire_point,
            surface_width,
            surface_height,
        );
        if (wait_semaphore) |value| {
            vk.vkDestroySemaphore(device, value, null);
            wait_semaphore = null;
        }
        surface_restage = false;
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
        // here bounds presentation backlog without pacing canonical Session
        // progress: Session continues independently while this observer waits.
        if (ring.previous_slot) |prior| {
            try waitTimeline(drm_fd, ring.slots[prior].release_handle, ring.slots[prior].release_point);
        }
        ring.previous_slot = ring.slot_index;
        ring.slot_index = (ring.slot_index + 1) % shared.slot_count;
        for (0..scene_count) |scene_index| changed[scene_index] = false;

        var active_grid_storage: [host_layout.max_panes_per_tab]host_layout.Placement = undefined;
        const active_grid = try mux.activeLayout(
            .{ .width = workspace_cols, .height = workspace_rows },
            &active_grid_storage,
        );
        for (0..scene_count) |scene_index| {
            if (!observation_armed[scene_index] and
                sceneIsVisible(&scene_panes, scene_count, active_grid, scene_index))
            {
                try scenes[scene_index].?.arm(session_revisions[scene_index]);
                observation_armed[scene_index] = true;
            }
        }
        const ready = waitDuetReady(
            boundary,
            &scenes,
            scene_count,
            next_ready_start,
        ) catch |failure| {
            if (boundary.shouldStop()) break;
            return failure;
        };
        switch (ready) {
            .scene => |ready_index| {
                next_ready_start = (ready_index + 1) % scene_count;
                const next = scenes[ready_index].?.receivePrepared() catch |failure| {
                    if (boundary.shouldStop()) break;
                    return failure;
                };
                observation_armed[ready_index] = false;
                if (next.width != prepared[ready_index].width or
                    next.height != prepared[ready_index].height)
                    return error.GeometryChanged;
                session_revisions[ready_index] = next.session_revision;
                var current_grid_storage: [host_layout.max_panes_per_tab]host_layout.Placement = undefined;
                const current_grid = try mux.activeLayout(
                    .{ .width = workspace_cols, .height = workspace_rows },
                    &current_grid_storage,
                );
                if (sceneIsVisible(&scene_panes, scene_count, current_grid, ready_index)) {
                    prepared[ready_index] = next;
                    changed[ready_index] = true;
                    try scenes[ready_index].?.arm(session_revisions[ready_index]);
                    observation_armed[ready_index] = true;
                } else {
                    scenes[ready_index].?.discardPrepared(next);
                }
            },
            .command => |host_command| switch (host_command.kind) {
                .grow_focused, .shrink_focused => {
                    if (scene_count != 2) continue;
                    try applyDuetGeometryCommand(
                        host_command,
                        &mux,
                        &geometry_controls,
                        &geometry_owned,
                        &scenes,
                        scene_count,
                        &prepared,
                        &session_revisions,
                        &changed,
                        workspace_rows,
                        workspace_cols,
                        cell_size.width,
                        cell_size.height,
                        &projected_layout,
                    );
                },
                .split_horizontal, .split_vertical => {
                    if (scene_count != 1) continue;
                    const axis: host_layout.SplitAxis = if (host_command.kind == .split_horizontal)
                        .horizontal
                    else
                        .vertical;
                    try addPane(
                        allocator,
                        boundary,
                        runtime_dir orelse return error.MissingRuntimeDirectory,
                        shell,
                        environ_map,
                        font_path,
                        font_pixels,
                        axis,
                        &spawned_session,
                        &mux,
                        &scene_panes,
                        &scenes,
                        &initialized_scene_count,
                        &geometry_controls,
                        &geometry_control_count,
                        &geometry_owned,
                        &prepared,
                        &session_revisions,
                        &changed,
                        &observation_armed,
                        &cancellation_registry,
                        &scene_count,
                        &next_ready_start,
                        workspace_rows,
                        workspace_cols,
                        cell_size.width,
                        cell_size.height,
                        &projected_layout,
                    );
                },
                .new_tab => {
                    if (scene_count != 1) continue;
                    try addTab(
                        allocator,
                        boundary,
                        runtime_dir orelse return error.MissingRuntimeDirectory,
                        shell,
                        environ_map,
                        font_path,
                        font_pixels,
                        &spawned_session,
                        &mux,
                        &scene_panes,
                        &scenes,
                        &initialized_scene_count,
                        &geometry_controls,
                        &geometry_control_count,
                        &prepared,
                        &session_revisions,
                        &changed,
                        &observation_armed,
                        &cancellation_registry,
                        &scene_count,
                        &next_ready_start,
                        &graphics,
                        workspace_rows,
                        workspace_cols,
                    );
                },
                .next_tab => {
                    if (scene_count != 2 or mux.tabCount() != 2) continue;
                    try switchNextTab(
                        boundary,
                        &mux,
                        &scene_panes,
                        &scenes,
                        scene_count,
                        &prepared,
                        &session_revisions,
                        &changed,
                        &observation_armed,
                        &graphics,
                    );
                },
                .close_created => {
                    if (scene_count != 2 or spawned_session == null or host_command.pane != 1)
                        continue;
                    if (mux.tabCount() == 2) {
                        try removeCreatedTab(
                            boundary,
                            &spawned_session,
                            &mux,
                            &scene_panes,
                            &scenes,
                            &initialized_scene_count,
                            &geometry_controls,
                            &geometry_control_count,
                            &geometry_owned,
                            &prepared,
                            &session_revisions,
                            &changed,
                            &observation_armed,
                            &fast_gpus,
                            &generic_contexts,
                            &graphics,
                            &cancellation_registry,
                            &scene_count,
                            &next_ready_start,
                            device,
                            &gpu_bytes,
                        );
                    } else {
                        try removeCreatedPane(
                            boundary,
                            &spawned_session,
                            &mux,
                            &scene_panes,
                            &scenes,
                            &initialized_scene_count,
                            &geometry_controls,
                            &geometry_control_count,
                            &geometry_owned,
                            &prepared,
                            &session_revisions,
                            &changed,
                            &observation_armed,
                            &fast_gpus,
                            &generic_contexts,
                            &graphics,
                            &cancellation_registry,
                            &scene_count,
                            &next_ready_start,
                            device,
                            &gpu_bytes,
                            workspace_rows,
                            workspace_cols,
                            cell_size.width,
                            cell_size.height,
                            &projected_layout,
                        );
                    }
                },
            },
            .pointer => |event| try routePointerEvent(
                boundary,
                event,
                display_scale_120,
                &mux,
                &scene_panes,
                scene_count,
                workspace_rows,
                workspace_cols,
                cell_size.width,
                cell_size.height,
            ),
            .display_scale => |scale| {
                if (scale.scale_120 == display_scale_120) continue;
                const next_font_pixels = try scaledFontPixels(scale.scale_120);
                const next_cell_size = try terminal_scene.measureCellSize(
                    allocator,
                    font_path,
                    next_font_pixels,
                );
                const next_surface_width = try scaledExtent(surface_logical_width, scale.scale_120);
                const next_surface_height = try scaledExtent(surface_logical_height, scale.scale_120);
                const target_cols: u16 = @max(2, next_surface_width / next_cell_size.width);
                const target_rows: u16 = @max(1, next_surface_height / next_cell_size.height);
                if (target_cols != workspace_cols or target_rows != workspace_rows) {
                    const resized = try applyWindowGeometry(
                        &mux,
                        &scene_panes,
                        &geometry_controls,
                        &geometry_owned,
                        &scenes,
                        scene_count,
                        &prepared,
                        &session_revisions,
                        &changed,
                        &observation_armed,
                        workspace_rows,
                        workspace_cols,
                        target_rows,
                        target_cols,
                    );
                    if (!resized) continue;
                    workspace_rows = target_rows;
                    workspace_cols = target_cols;
                }
                try rebuildScenesForScale(
                    allocator,
                    endpoint,
                    endpoint_right,
                    spawned_session,
                    font_path,
                    next_font_pixels,
                    &scenes,
                    scene_count,
                    &prepared,
                    &session_revisions,
                    &observation_armed,
                    &changed,
                    &cancellation_registry,
                    &fast_gpus,
                    &generic_contexts,
                    &graphics,
                    device,
                    &gpu_bytes,
                );
                const rebuilt_cell_size = scenes[0].?.cellSize();
                if (!std.meta.eql(rebuilt_cell_size, next_cell_size)) return error.DuetGeometry;
                for (1..scene_count) |scene_index|
                    if (!std.meta.eql(rebuilt_cell_size, scenes[scene_index].?.cellSize()))
                        return error.DuetGeometry;
                var scale_visible_storage: [host_layout.max_panes_per_tab]host_layout.Placement = undefined;
                const scale_visible = try mux.activeLayout(
                    .{ .width = workspace_cols, .height = workspace_rows },
                    &scale_visible_storage,
                );
                for (0..scene_count) |scene_index| {
                    if (sceneIsVisible(&scene_panes, scene_count, scale_visible, scene_index)) continue;
                    scenes[scene_index].?.discardPrepared(prepared[scene_index]);
                    changed[scene_index] = false;
                    observation_armed[scene_index] = false;
                }
                if (retiring_ring != null) return error.RingRetirementPending;
                const next_revision = std.math.add(u64, ring.revision, 1) catch return error.RevisionOverflow;
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
                font_pixels = next_font_pixels;
                cell_size = rebuilt_cell_size;
                surface_width = next_surface_width;
                surface_height = next_surface_height;
                surface_restage = true;
            },
            .window_size => |requested| {
                if (requested.width == surface_logical_width and requested.height == surface_logical_height) continue;
                const requested_physical_width = try scaledExtent(requested.width, display_scale_120);
                const requested_physical_height = try scaledExtent(requested.height, display_scale_120);
                const target_cols: u16 = @max(2, requested_physical_width / cell_size.width);
                const target_rows: u16 = @max(1, requested_physical_height / cell_size.height);
                if (target_cols != workspace_cols or target_rows != workspace_rows) {
                    const resized = try applyWindowGeometry(
                        &mux,
                        &scene_panes,
                        &geometry_controls,
                        &geometry_owned,
                        &scenes,
                        scene_count,
                        &prepared,
                        &session_revisions,
                        &changed,
                        &observation_armed,
                        workspace_rows,
                        workspace_cols,
                        target_rows,
                        target_cols,
                    );
                    if (!resized) continue;
                    workspace_rows = target_rows;
                    workspace_cols = target_cols;
                }
                if (retiring_ring != null) return error.RingRetirementPending;
                const next_revision = std.math.add(u64, ring.revision, 1) catch return error.RevisionOverflow;
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
                surface_restage = true;
            },
        }
    }
    if (vk.vkDeviceWaitIdle(device) != vk.VK_SUCCESS) return error.DeviceIdle;
    queue_active = false;
    try waitWindowStopped(boundary);
    std.debug.print(
        "Render live loop retired at present={d} sessions={d}/{d} retained_draws={d} generic_draws={d}\n",
        .{
            present_revision,
            session_revisions[0],
            if (scene_count == 2) session_revisions[1] else 0,
            retained_draw_count,
            generic_draw_count_total,
        },
    );
}

fn sceneEndpoint(
    index: usize,
    primary: []const u8,
    external_right: ?[]const u8,
    spawned: ?session_process.SessionProcess,
) ![]const u8 {
    return switch (index) {
        0 => primary,
        1 => if (spawned) |session| session.endpoint else external_right orelse error.SceneEndpointMissing,
        else => error.SceneEndpointMissing,
    };
}

fn rebuildScenesForScale(
    allocator: std.mem.Allocator,
    primary_endpoint: []const u8,
    external_right: ?[]const u8,
    spawned_session: ?session_process.SessionProcess,
    font_path: []const u8,
    font_pixels: u16,
    scenes: *[2]?terminal_scene.Scene,
    scene_count: usize,
    prepared: *[2]terminal_scene.Prepared,
    session_revisions: *[2]u64,
    observation_armed: *[2]bool,
    changed: *[2]bool,
    cancellations: *CancellationRegistry,
    fast_gpus: *[2]?terminal_fast.Gpu,
    generic_contexts: *[2]?surface.Context,
    primary_graphics: *surface.Context,
    device: vk.VkDevice,
    gpu_bytes: *u64,
) !void {
    if (scene_count == 0 or scene_count > scenes.len or font_pixels == 0)
        return error.SceneTopologyMismatch;
    var replacements: [2]?terminal_scene.Scene = .{ null, null };
    var replacement_count: usize = 0;
    errdefer {
        var index = replacement_count;
        while (index != 0) {
            index -= 1;
            replacements[index].?.deinit();
        }
    }
    var next_prepared: [2]terminal_scene.Prepared = undefined;
    var next_revisions: [2]u64 = @splat(0);
    for (0..scene_count) |index| {
        const endpoint = try sceneEndpoint(index, primary_endpoint, external_right, spawned_session);
        replacements[index] = try terminal_scene.Scene.init(allocator, endpoint, font_path, font_pixels);
        replacement_count = index + 1;
        next_prepared[index] = try replacements[index].?.prepare(0);
        next_revisions[index] = next_prepared[index].session_revision;
    }

    for (0..scene_count) |index| {
        cancellations.clear(index);
        if (fast_gpus[index]) |*value| value.deinit(device, gpu_bytes);
        fast_gpus[index] = null;
        if (generic_contexts[index]) |*value| value.deinit(device, gpu_bytes);
        generic_contexts[index] = null;
        scenes[index].?.deinit();
        scenes[index] = replacements[index];
        replacements[index] = null;
        prepared[index] = next_prepared[index];
        session_revisions[index] = next_revisions[index];
        observation_armed[index] = false;
        changed[index] = true;
        try cancellations.set(index, try scenes[index].?.cancellation());
    }
    replacement_count = 0;
    primary_graphics.invalidateAtlases();
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
    if (scale_120 == 0 or cell_width == 0 or cell_height == 0) return error.InvalidDisplayScale;
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
            return error.DuetGeometry;
        const bottom = std.math.add(u32, placement.rect.y, placement.rect.height) catch
            return error.DuetGeometry;
        if (x < placement.rect.x or x >= right or y < placement.rect.y or y >= bottom) continue;
        const scene_index = sceneIndexForPane(scene_panes, scene_count, placement.pane) orelse
            return error.SceneTopologyMismatch;
        if (event.kind == .press and event.button == .left) {
            const changed = mux.focusPane(placement.pane) catch return error.SceneTopologyMismatch;
            if (changed) try boundary.publishPaneFocus(@intCast(scene_index));
        }
        const pixel_x = x - placement.rect.x;
        const pixel_y = y - placement.rect.y;
        const row_u32 = pixel_y / cell_height;
        const column_u32 = pixel_x / cell_width;
        if (row_u32 > std.math.maxInt(i32) or column_u32 > std.math.maxInt(u16))
            return error.DuetGeometry;
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
    if (scale_120 == 0) return error.InvalidDisplayScale;
    const numerator = std.math.mul(u32, base_font_pixels, scale_120) catch
        return error.InvalidDisplayScale;
    const rounded = std.math.add(u32, numerator, scale_denominator / 2) catch
        return error.InvalidDisplayScale;
    const pixels = rounded / scale_denominator;
    if (pixels == 0 or pixels > std.math.maxInt(u16)) return error.InvalidDisplayScale;
    return @intCast(pixels);
}

fn scaledExtent(logical: u16, scale_120: u32) !u16 {
    if (logical == 0 or scale_120 == 0) return error.InvalidDisplayScale;
    const numerator = std.math.mul(u32, logical, scale_120) catch
        return error.InvalidDisplayScale;
    const rounded = std.math.add(u32, numerator, scale_denominator - 1) catch
        return error.InvalidDisplayScale;
    const value = rounded / scale_denominator;
    if (value == 0 or value > std.math.maxInt(u16)) return error.InvalidDisplayScale;
    return @intCast(value);
}

const InitialGeometry = struct {
    surface_width: u16,
    surface_height: u16,
    grid_rows: u16,
    grid_cols: u16,
};

fn establishInitialGeometry(
    scenes: *[2]?terminal_scene.Scene,
    controls: *[2]?client.Connection,
    geometry_owned: *[2]bool,
    scene_count: usize,
    mux: host_layout.Mux,
    prepared: *[2]terminal_scene.Prepared,
    session_revisions: *[2]u64,
    total_rows: u16,
    total_cols: u16,
    surface_width: u16,
    surface_height: u16,
    pixel_storage: *[host_layout.max_panes_per_tab]host_layout.Placement,
) !InitialGeometry {
    if (scene_count == 0 or scene_count > scenes.len or total_rows == 0 or total_cols == 0 or
        surface_width == 0 or surface_height == 0) return error.DuetGeometry;
    const cell_size = scenes[0].?.cellSize();
    if (cell_size.width == 0 or cell_size.height == 0) return error.DuetGeometry;
    for (1..scene_count) |scene_index|
        if (!std.meta.eql(cell_size, scenes[scene_index].?.cellSize()))
            return error.DuetGeometry;

    var grid_storage: [host_layout.max_panes_per_tab]host_layout.Placement = undefined;
    const grid = try mux.activeLayout(
        .{ .width = total_cols, .height = total_rows },
        &grid_storage,
    );
    if (grid.len != scene_count) return error.DuetGeometry;

    var old_rows: [2]u16 = undefined;
    var old_cols: [2]u16 = undefined;
    var changed: [2]bool = @splat(false);
    for (0..scene_count) |scene_index| {
        old_rows[scene_index] = prepared[scene_index].rows;
        old_cols[scene_index] = prepared[scene_index].cols;
        const target = grid[scene_index].rect;
        if (target.width == 0 or target.height == 0 or
            target.width > std.math.maxInt(u16) or target.height > std.math.maxInt(u16))
            return error.DuetGeometry;
        const target_rows: u16 = @intCast(target.height);
        const target_cols: u16 = @intCast(target.width);
        if (old_rows[scene_index] == target_rows and old_cols[scene_index] == target_cols)
            continue;
        scenes[scene_index].?.discardPrepared(prepared[scene_index]);
        requestCanonicalGeometry(
            &controls[scene_index].?,
            &geometry_owned[scene_index],
            prepared[scene_index],
            target_rows,
            target_cols,
        ) catch |failure| {
            rollbackInitialGeometry(
                controls,
                changed,
                old_rows,
                old_cols,
                scene_index,
            ) catch return error.ResizeTransactionFailed;
            return failure;
        };
        changed[scene_index] = true;
    }

    for (0..scene_count) |scene_index| {
        if (!changed[scene_index]) continue;
        const next = scenes[scene_index].?.prepare(session_revisions[scene_index]) catch |failure| {
            rollbackInitialGeometry(
                controls,
                changed,
                old_rows,
                old_cols,
                scene_count,
            ) catch return error.ResizeTransactionFailed;
            return failure;
        };
        const target = grid[scene_index].rect;
        if (next.rows != target.height or next.cols != target.width) {
            rollbackInitialGeometry(
                controls,
                changed,
                old_rows,
                old_cols,
                scene_count,
            ) catch return error.ResizeTransactionFailed;
            return error.ResizeResultMismatch;
        }
        prepared[scene_index] = next;
        session_revisions[scene_index] = next.session_revision;
    }

    for (grid, pixel_storage[0..grid.len], 0..) |placed, *pixel, scene_index| {
        const x = std.math.mul(u32, placed.rect.x, cell_size.width) catch return error.DuetGeometry;
        const y = std.math.mul(u32, placed.rect.y, cell_size.height) catch return error.DuetGeometry;
        const width = std.math.mul(u32, placed.rect.width, cell_size.width) catch return error.DuetGeometry;
        const height = std.math.mul(u32, placed.rect.height, cell_size.height) catch return error.DuetGeometry;
        pixel.* = .{
            .pane = placed.pane,
            .rect = .{ .x = x, .y = y, .width = width, .height = height },
            .focused = placed.focused,
        };
        if (prepared[scene_index].width != width or prepared[scene_index].height != height)
            return error.ResizeResultMismatch;
    }
    return .{
        .surface_width = surface_width,
        .surface_height = surface_height,
        .grid_rows = total_rows,
        .grid_cols = total_cols,
    };
}

fn requestCanonicalGeometry(
    control: *client.Connection,
    owned: *bool,
    current: terminal_scene.Prepared,
    rows: u16,
    cols: u16,
) !void {
    if (rows == 0 or cols == 0) return error.DuetGeometry;
    if (current.rows == rows and current.cols == cols) return;
    if (owned.*) {
        client.actions.resizeOwned(control, rows, cols) catch |failure| {
            if (failure == error.ServerRejected or failure == error.NotGeometryLeader) owned.* = false;
            return failure;
        };
        return;
    }
    if (current.leader_present) return error.ResizeAuthorityUnavailable;
    try client.actions.resize(control, rows, cols);
    owned.* = true;
}

fn rollbackInitialGeometry(
    controls: *[2]?client.Connection,
    changed: [2]bool,
    rows: [2]u16,
    cols: [2]u16,
    end: usize,
) !void {
    var index = @min(end, controls.len);
    while (index != 0) {
        index -= 1;
        if (!changed[index]) continue;
        try client.actions.resizeOwned(&controls[index].?, rows[index], cols[index]);
    }
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

fn sceneIsVisible(
    scene_panes: *const [2]?host_layout.PaneId,
    scene_count: usize,
    visible: []const host_layout.Placement,
    scene_index: usize,
) bool {
    if (scene_index >= scene_count or scene_panes[scene_index] == null) return false;
    const pane = scene_panes[scene_index].?;
    for (visible) |placement| if (placement.pane == pane) return true;
    return false;
}

fn fastPlacement(value: host_layout.Placement) terminal_fast.Placement {
    return .{
        .x = @intCast(value.rect.x),
        .y = @intCast(value.rect.y),
        .width = value.rect.width,
        .height = value.rect.height,
    };
}

fn surfacePlacement(value: host_layout.Placement) surface.Placement {
    return .{
        .x = @intCast(value.rect.x),
        .y = @intCast(value.rect.y),
        .width = value.rect.width,
        .height = value.rect.height,
    };
}

fn removeCreatedPane(
    boundary: *shared.Boundary,
    spawned_session: *?session_process.SessionProcess,
    mux: *host_layout.Mux,
    scene_panes: *[2]?host_layout.PaneId,
    scenes: *[2]?terminal_scene.Scene,
    initialized_scene_count: *usize,
    controls: *[2]?client.Connection,
    geometry_control_count: *usize,
    geometry_owned: *[2]bool,
    prepared: *[2]terminal_scene.Prepared,
    session_revisions: *[2]u64,
    changed: *[2]bool,
    observation_armed: *[2]bool,
    fast_gpus: *[2]?terminal_fast.Gpu,
    generic_contexts: *[2]?surface.Context,
    primary_graphics: *surface.Context,
    cancellations: *CancellationRegistry,
    scene_count: *usize,
    next_ready_start: *usize,
    device: vk.VkDevice,
    gpu_bytes: *u64,
    workspace_rows: u16,
    workspace_cols: u16,
    cell_width: u16,
    cell_height: u16,
    pixel_storage: *[host_layout.max_panes_per_tab]host_layout.Placement,
) !void {
    if (scene_count.* != 2 or spawned_session.* == null or
        initialized_scene_count.* != 2 or geometry_control_count.* != 2)
        return error.CloseStateMismatch;

    var candidate = mux.*;
    var placement_storage: [host_layout.max_panes_per_tab]host_layout.Placement = undefined;
    const current = try candidate.activeLayout(
        .{ .width = workspace_cols, .height = workspace_rows },
        &placement_storage,
    );
    if (current.len != 2) return error.CloseStateMismatch;
    const target = current[1].pane;
    const focus_changed = candidate.focusPane(target) catch return error.CloseStateMismatch;
    if (!focus_changed and candidate.focusedPane() != target)
        return error.CloseStateMismatch;
    const retired = try candidate.closeFocused();
    if (retired != target or candidate.paneCount() != 1)
        return error.CloseStateMismatch;

    const committed = try commitLiveGeometryCandidate(
        candidate,
        mux,
        controls,
        geometry_owned,
        scenes,
        1,
        prepared,
        session_revisions,
        changed,
        workspace_rows,
        workspace_cols,
        cell_width,
        cell_height,
        pixel_storage,
    );
    if (!committed) return;

    if (fast_gpus[1]) |*value| value.deinit(device, gpu_bytes);
    fast_gpus[1] = null;
    for (generic_contexts) |*slot| {
        if (slot.*) |*value| value.deinit(device, gpu_bytes);
        slot.* = null;
    }
    primary_graphics.invalidateAtlases();
    cancellations.clear(1);
    controls[1].?.deinit();
    controls[1] = null;
    geometry_control_count.* = 1;
    geometry_owned[1] = false;
    scenes[1].?.deinit();
    scenes[1] = null;
    initialized_scene_count.* = 1;
    session_revisions[1] = 0;
    changed[1] = false;
    observation_armed[1] = false;
    observation_armed[0] = true;
    scene_panes[1] = null;
    spawned_session.*.?.deinit();
    spawned_session.* = null;
    scene_count.* = 1;
    next_ready_start.* = 0;
    try boundary.publishPaneRetired();
}

fn createSecondSession(
    allocator: std.mem.Allocator,
    boundary: *shared.Boundary,
    runtime_dir: []const u8,
    shell: []const u8,
    environ_map: *const std.process.Environ.Map,
    font_path: []const u8,
    font_pixels: u16,
    spawned_session: *?session_process.SessionProcess,
    scenes: *[2]?terminal_scene.Scene,
    initialized_scene_count: *usize,
    controls: *[2]?client.Connection,
    geometry_control_count: *usize,
    prepared: *[2]terminal_scene.Prepared,
    session_revisions: *[2]u64,
    cancellations: *CancellationRegistry,
    workspace_rows: u16,
    workspace_cols: u16,
) ![]const u8 {
    if (spawned_session.* != null or initialized_scene_count.* != 1 or
        geometry_control_count.* != 1 or runtime_dir.len == 0 or shell.len == 0 or
        workspace_rows == 0 or workspace_cols == 0)
        return error.CreatedSessionStateMismatch;
    spawned_session.* = try session_process.SessionProcess.launchSibling(
        allocator,
        boundary.runtimeIo(),
        runtime_dir,
        shell,
        null,
        null,
        environ_map,
        workspace_rows,
        workspace_cols,
        2,
    );
    const endpoint = spawned_session.*.?.endpoint;
    scenes[1] = try terminal_scene.Scene.init(allocator, endpoint, font_path, font_pixels);
    initialized_scene_count.* = 2;
    controls[1] = try client.Connection.connect(allocator, endpoint);
    geometry_control_count.* = 2;
    prepared[1] = try scenes[1].?.prepare(0);
    session_revisions[1] = prepared[1].session_revision;
    try cancellations.set(1, try scenes[1].?.cancellation());
    return endpoint;
}

fn addPane(
    allocator: std.mem.Allocator,
    boundary: *shared.Boundary,
    runtime_dir: []const u8,
    shell: []const u8,
    environ_map: *const std.process.Environ.Map,
    font_path: []const u8,
    font_pixels: u16,
    axis: host_layout.SplitAxis,
    spawned_session: *?session_process.SessionProcess,
    mux: *host_layout.Mux,
    scene_panes: *[2]?host_layout.PaneId,
    scenes: *[2]?terminal_scene.Scene,
    initialized_scene_count: *usize,
    controls: *[2]?client.Connection,
    geometry_control_count: *usize,
    geometry_owned: *[2]bool,
    prepared: *[2]terminal_scene.Prepared,
    session_revisions: *[2]u64,
    changed: *[2]bool,
    observation_armed: *[2]bool,
    cancellation_registry: *CancellationRegistry,
    scene_count: *usize,
    next_ready_start: *usize,
    workspace_rows: u16,
    workspace_cols: u16,
    cell_width: u16,
    cell_height: u16,
    pixel_storage: *[host_layout.max_panes_per_tab]host_layout.Placement,
) !void {
    if (scene_count.* != 1 or spawned_session.* != null or
        initialized_scene_count.* != 1 or geometry_control_count.* != 1)
        return error.SplitStateMismatch;
    if (runtime_dir.len == 0 or shell.len == 0 or workspace_rows == 0 or workspace_cols < 2)
        return error.SplitStateMismatch;

    const endpoint = try createSecondSession(
        allocator,
        boundary,
        runtime_dir,
        shell,
        environ_map,
        font_path,
        font_pixels,
        spawned_session,
        scenes,
        initialized_scene_count,
        controls,
        geometry_control_count,
        prepared,
        session_revisions,
        cancellation_registry,
        workspace_rows,
        workspace_cols,
    );
    scenes[1].?.discardPrepared(prepared[1]);
    try scenes[1].?.arm(session_revisions[1]);
    observation_armed[1] = true;

    var candidate = mux.*;
    const new_pane = try candidate.splitFocused(axis);
    if (candidate.focusedPane() != new_pane or candidate.paneCount() != 2)
        return error.SplitStateMismatch;

    const committed = try commitLiveGeometryCandidate(
        candidate,
        mux,
        controls,
        geometry_owned,
        scenes,
        2,
        prepared,
        session_revisions,
        changed,
        workspace_rows,
        workspace_cols,
        cell_width,
        cell_height,
        pixel_storage,
    );
    if (!committed) return error.SplitGeometryRejected;

    scene_panes[1] = new_pane;
    observation_armed[0] = true;
    observation_armed[1] = true;
    scene_count.* = 2;
    next_ready_start.* = 0;
    try boundary.publishPaneEndpoint(endpoint, switch (axis) {
        .horizontal => .split_horizontal,
        .vertical => .split_vertical,
    });
}

fn addTab(
    allocator: std.mem.Allocator,
    boundary: *shared.Boundary,
    runtime_dir: []const u8,
    shell: []const u8,
    environ_map: *const std.process.Environ.Map,
    font_path: []const u8,
    font_pixels: u16,
    spawned_session: *?session_process.SessionProcess,
    mux: *host_layout.Mux,
    scene_panes: *[2]?host_layout.PaneId,
    scenes: *[2]?terminal_scene.Scene,
    initialized_scene_count: *usize,
    controls: *[2]?client.Connection,
    geometry_control_count: *usize,
    prepared: *[2]terminal_scene.Prepared,
    session_revisions: *[2]u64,
    changed: *[2]bool,
    observation_armed: *[2]bool,
    cancellations: *CancellationRegistry,
    scene_count: *usize,
    next_ready_start: *usize,
    primary_graphics: *surface.Context,
    workspace_rows: u16,
    workspace_cols: u16,
) !void {
    if (scene_count.* != 1 or mux.tabCount() != 1 or mux.paneCount() != 1)
        return error.TabStateMismatch;
    const endpoint = try createSecondSession(
        allocator,
        boundary,
        runtime_dir,
        shell,
        environ_map,
        font_path,
        font_pixels,
        spawned_session,
        scenes,
        initialized_scene_count,
        controls,
        geometry_control_count,
        prepared,
        session_revisions,
        cancellations,
        workspace_rows,
        workspace_cols,
    );
    var candidate = mux.*;
    const created = try candidate.createTab();
    if (candidate.tabCount() != 2 or candidate.paneCount() != 2 or
        candidate.focusedPane() != created.pane) return error.TabStateMismatch;
    scene_panes[1] = created.pane;
    mux.* = candidate;
    changed[1] = true;
    try scenes[1].?.arm(session_revisions[1]);
    observation_armed[1] = true;
    scene_count.* = 2;
    next_ready_start.* = 0;
    primary_graphics.invalidateAtlases();
    try boundary.publishPaneEndpoint(endpoint, .tab);
}

fn switchNextTab(
    boundary: *shared.Boundary,
    mux: *host_layout.Mux,
    scene_panes: *const [2]?host_layout.PaneId,
    scenes: *[2]?terminal_scene.Scene,
    scene_count: usize,
    prepared: *[2]terminal_scene.Prepared,
    session_revisions: *[2]u64,
    changed: *[2]bool,
    observation_armed: *[2]bool,
    primary_graphics: *surface.Context,
) !void {
    if (scene_count != 2 or mux.tabCount() != 2) return error.TabStateMismatch;
    var candidate = mux.*;
    if (!candidate.nextTab()) return error.TabStateMismatch;
    const target = sceneIndexForPane(scene_panes, scene_count, candidate.focusedPane()) orelse
        return error.SceneTopologyMismatch;
    if (!observation_armed[target]) {
        const next = try scenes[target].?.prepare(0);
        prepared[target] = next;
        session_revisions[target] = next.session_revision;
        changed[target] = true;
        try scenes[target].?.arm(session_revisions[target]);
        observation_armed[target] = true;
    } else {
        changed[target] = false;
    }
    mux.* = candidate;
    primary_graphics.invalidateAtlases();
    try boundary.publishTabSwitched();
}

fn removeCreatedTab(
    boundary: *shared.Boundary,
    spawned_session: *?session_process.SessionProcess,
    mux: *host_layout.Mux,
    scene_panes: *[2]?host_layout.PaneId,
    scenes: *[2]?terminal_scene.Scene,
    initialized_scene_count: *usize,
    controls: *[2]?client.Connection,
    geometry_control_count: *usize,
    geometry_owned: *[2]bool,
    prepared: *[2]terminal_scene.Prepared,
    session_revisions: *[2]u64,
    changed: *[2]bool,
    observation_armed: *[2]bool,
    fast_gpus: *[2]?terminal_fast.Gpu,
    generic_contexts: *[2]?surface.Context,
    primary_graphics: *surface.Context,
    cancellations: *CancellationRegistry,
    scene_count: *usize,
    next_ready_start: *usize,
    device: vk.VkDevice,
    gpu_bytes: *u64,
) !void {
    if (scene_count.* != 2 or spawned_session.* == null or mux.tabCount() != 2 or
        mux.paneCount() != 2 or mux.focusedPane() != scene_panes[1].?)
        return error.CloseStateMismatch;
    var candidate = mux.*;
    try candidate.closeActiveTab();
    if (candidate.tabCount() != 1 or candidate.paneCount() != 1)
        return error.CloseStateMismatch;
    mux.* = candidate;
    if (fast_gpus[1]) |*value| value.deinit(device, gpu_bytes);
    fast_gpus[1] = null;
    for (generic_contexts) |*slot| {
        if (slot.*) |*value| value.deinit(device, gpu_bytes);
        slot.* = null;
    }
    primary_graphics.invalidateAtlases();
    cancellations.clear(1);
    controls[1].?.deinit();
    controls[1] = null;
    geometry_control_count.* = 1;
    geometry_owned[1] = false;
    scenes[1].?.deinit();
    scenes[1] = null;
    initialized_scene_count.* = 1;
    session_revisions[1] = 0;
    if (!observation_armed[0]) {
        const next = try scenes[0].?.prepare(0);
        prepared[0] = next;
        session_revisions[0] = next.session_revision;
        changed[0] = true;
        try scenes[0].?.arm(session_revisions[0]);
        observation_armed[0] = true;
    } else {
        changed[0] = false;
    }
    changed[1] = false;
    observation_armed[1] = false;
    scene_panes[1] = null;
    spawned_session.*.?.deinit();
    spawned_session.* = null;
    scene_count.* = 1;
    next_ready_start.* = 0;
    try boundary.publishPaneRetired();
}

fn settleSceneGeometry(
    scene: *terminal_scene.Scene,
    target_rows: u16,
    target_cols: u16,
    keep_prepared: bool,
    prepared: *terminal_scene.Prepared,
    session_revision: *u64,
    changed: *bool,
    observation_armed: *bool,
) !void {
    if (!observation_armed.*) {
        try scene.arm(session_revision.*);
        observation_armed.* = true;
    }
    var attempts: u8 = 0;
    while (attempts < 8) : (attempts += 1) {
        const next = try scene.receivePrepared();
        observation_armed.* = false;
        session_revision.* = next.session_revision;
        if (next.rows == target_rows and next.cols == target_cols) {
            prepared.* = next;
            if (keep_prepared) {
                changed.* = true;
                try scene.arm(session_revision.*);
                observation_armed.* = true;
            } else {
                scene.discardPrepared(next);
                changed.* = false;
            }
            return;
        }
        scene.discardPrepared(next);
        try scene.arm(session_revision.*);
        observation_armed.* = true;
    }
    return error.GeometryObservationTimeout;
}

fn applyWindowGeometry(
    mux: *const host_layout.Mux,
    scene_panes: *const [2]?host_layout.PaneId,
    controls: *[2]?client.Connection,
    geometry_owned: *[2]bool,
    scenes: *[2]?terminal_scene.Scene,
    scene_count: usize,
    prepared: *[2]terminal_scene.Prepared,
    session_revisions: *[2]u64,
    changed: *[2]bool,
    observation_armed: *[2]bool,
    old_rows: u16,
    old_cols: u16,
    target_rows: u16,
    target_cols: u16,
) !bool {
    if (scene_count == 0 or scene_count > scenes.len or target_rows == 0 or target_cols < 2)
        return error.DuetGeometry;
    const target_surface = host_layout.Surface{ .width = target_cols, .height = target_rows };
    const old_surface = host_layout.Surface{ .width = old_cols, .height = old_rows };
    var old_scene_rows: [2]u16 = undefined;
    var old_scene_cols: [2]u16 = undefined;
    var target_scene_rows: [2]u16 = undefined;
    var target_scene_cols: [2]u16 = undefined;
    var applied: [2]bool = @splat(false);
    for (0..scene_count) |index| {
        const pane = scene_panes[index] orelse return error.SceneTopologyMismatch;
        const target = try mux.paneRect(target_surface, pane);
        old_scene_rows[index] = prepared[index].rows;
        old_scene_cols[index] = prepared[index].cols;
        target_scene_rows[index] = @intCast(target.height);
        target_scene_cols[index] = @intCast(target.width);
        if (old_scene_rows[index] == target_scene_rows[index] and
            old_scene_cols[index] == target_scene_cols[index]) continue;
        requestCanonicalGeometry(
            &controls[index].?,
            &geometry_owned[index],
            prepared[index],
            target_scene_rows[index],
            target_scene_cols[index],
        ) catch |failure| {
            rollbackInitialGeometry(
                controls,
                applied,
                old_scene_rows,
                old_scene_cols,
                index,
            ) catch return error.ResizeTransactionFailed;
            if (failure == error.ServerRejected or failure == error.NotGeometryLeader or failure == error.ResizeAuthorityUnavailable) {
                var old_active_storage: [host_layout.max_panes_per_tab]host_layout.Placement = undefined;
                const old_active = try mux.activeLayout(old_surface, &old_active_storage);
                for (0..index) |rollback_index| {
                    if (!applied[rollback_index]) continue;
                    try settleSceneGeometry(
                        &scenes[rollback_index].?,
                        old_scene_rows[rollback_index],
                        old_scene_cols[rollback_index],
                        sceneIsVisible(scene_panes, scene_count, old_active, rollback_index),
                        &prepared[rollback_index],
                        &session_revisions[rollback_index],
                        &changed[rollback_index],
                        &observation_armed[rollback_index],
                    );
                }
                return false;
            }
            return failure;
        };
        applied[index] = true;
    }

    var target_active_storage: [host_layout.max_panes_per_tab]host_layout.Placement = undefined;
    const target_active = try mux.activeLayout(target_surface, &target_active_storage);
    for (0..scene_count) |index| {
        if (!applied[index]) continue;
        settleSceneGeometry(
            &scenes[index].?,
            target_scene_rows[index],
            target_scene_cols[index],
            sceneIsVisible(scene_panes, scene_count, target_active, index),
            &prepared[index],
            &session_revisions[index],
            &changed[index],
            &observation_armed[index],
        ) catch |failure| {
            rollbackInitialGeometry(
                controls,
                applied,
                old_scene_rows,
                old_scene_cols,
                scene_count,
            ) catch return error.ResizeTransactionFailed;
            return failure;
        };
    }
    return true;
}

fn applyDuetGeometryCommand(
    command: shared.HostCommand,
    mux: *host_layout.Mux,
    controls: *[2]?client.Connection,
    geometry_owned: *[2]bool,
    scenes: *[2]?terminal_scene.Scene,
    scene_count: usize,
    prepared: *[2]terminal_scene.Prepared,
    session_revisions: *[2]u64,
    changed: *[2]bool,
    workspace_rows: u16,
    workspace_cols: u16,
    cell_width: u16,
    cell_height: u16,
    pixel_storage: *[host_layout.max_panes_per_tab]host_layout.Placement,
) !void {
    if (scene_count != 2 or workspace_rows == 0 or workspace_cols < 2 or
        cell_width == 0 or cell_height == 0)
        return error.DuetGeometry;
    var candidate = mux.*;
    var focus_storage: [host_layout.max_panes_per_tab]host_layout.Placement = undefined;
    const focus_layout = try candidate.activeLayout(
        .{ .width = workspace_cols, .height = workspace_rows },
        &focus_storage,
    );
    if (command.pane >= focus_layout.len) return error.DuetGeometry;
    const target_pane = focus_layout[command.pane].pane;
    const focus_changed = candidate.focusPane(target_pane) catch return error.DuetGeometry;
    if (!focus_changed and candidate.focusedPane() != target_pane)
        return error.DuetGeometry;
    const cells: i32 = switch (command.kind) {
        .grow_focused => 1,
        .shrink_focused => -1,
        .split_horizontal, .split_vertical, .new_tab, .next_tab, .close_created => return error.HostCommandUnsupported,
    };
    if (!(try candidate.resizeFocused(
        .{ .width = workspace_cols, .height = workspace_rows },
        cells,
    ))) return;

    const committed = try commitLiveGeometryCandidate(
        candidate,
        mux,
        controls,
        geometry_owned,
        scenes,
        scene_count,
        prepared,
        session_revisions,
        changed,
        workspace_rows,
        workspace_cols,
        cell_width,
        cell_height,
        pixel_storage,
    );
    if (!committed) return;
}

fn commitLiveGeometryCandidate(
    candidate: host_layout.Mux,
    mux: *host_layout.Mux,
    controls: *[2]?client.Connection,
    geometry_owned: *[2]bool,
    scenes: *[2]?terminal_scene.Scene,
    scene_count: usize,
    prepared: *[2]terminal_scene.Prepared,
    session_revisions: *[2]u64,
    changed: *[2]bool,
    workspace_rows: u16,
    workspace_cols: u16,
    cell_width: u16,
    cell_height: u16,
    pixel_storage: *[host_layout.max_panes_per_tab]host_layout.Placement,
) !bool {
    if (scene_count == 0 or scene_count > scenes.len or
        workspace_rows == 0 or workspace_cols == 0 or cell_width == 0 or cell_height == 0)
        return error.DuetGeometry;
    var grid_storage: [host_layout.max_panes_per_tab]host_layout.Placement = undefined;
    const grid = try candidate.activeLayout(
        .{ .width = workspace_cols, .height = workspace_rows },
        &grid_storage,
    );
    if (grid.len != scene_count) return error.DuetGeometry;

    var old_rows: [2]u16 = undefined;
    var old_cols: [2]u16 = undefined;
    var applied: [2]bool = @splat(false);
    for (0..scene_count) |scene_index| {
        old_rows[scene_index] = prepared[scene_index].rows;
        old_cols[scene_index] = prepared[scene_index].cols;
        const target = grid[scene_index].rect;
        if (target.width == 0 or target.height == 0 or
            target.width > std.math.maxInt(u16) or target.height > std.math.maxInt(u16))
            return error.DuetGeometry;
        const target_rows: u16 = @intCast(target.height);
        const target_cols: u16 = @intCast(target.width);
        if (target_rows == old_rows[scene_index] and target_cols == old_cols[scene_index])
            continue;
        requestCanonicalGeometry(
            &controls[scene_index].?,
            &geometry_owned[scene_index],
            prepared[scene_index],
            target_rows,
            target_cols,
        ) catch |failure| {
            rollbackInitialGeometry(
                controls,
                applied,
                old_rows,
                old_cols,
                scene_index,
            ) catch return error.ResizeTransactionFailed;
            if (failure == error.ServerRejected or failure == error.NotGeometryLeader) {
                try settleRolledBackGeometry(
                    scenes,
                    applied,
                    old_rows,
                    old_cols,
                    scene_index,
                    session_revisions,
                    prepared,
                    changed,
                );
                return false;
            }
            return failure;
        };
        applied[scene_index] = true;
    }

    for (0..scene_count) |scene_index| {
        if (!applied[scene_index]) continue;
        const target = grid[scene_index].rect;
        const target_rows: u16 = @intCast(target.height);
        const target_cols: u16 = @intCast(target.width);
        var attempts: u8 = 0;
        while (attempts < 8) : (attempts += 1) {
            const next = scenes[scene_index].?.receivePrepared() catch |failure| {
                rollbackInitialGeometry(
                    controls,
                    applied,
                    old_rows,
                    old_cols,
                    scene_count,
                ) catch return error.ResizeTransactionFailed;
                return failure;
            };
            session_revisions[scene_index] = next.session_revision;
            if (next.rows == target_rows and next.cols == target_cols) {
                prepared[scene_index] = next;
                changed[scene_index] = true;
                break;
            }
            scenes[scene_index].?.discardPrepared(next);
            try scenes[scene_index].?.arm(session_revisions[scene_index]);
        } else {
            rollbackInitialGeometry(
                controls,
                applied,
                old_rows,
                old_cols,
                scene_count,
            ) catch return error.ResizeTransactionFailed;
            return error.GeometryObservationTimeout;
        }
        try scenes[scene_index].?.arm(session_revisions[scene_index]);
    }

    var candidate_pixels: [host_layout.max_panes_per_tab]host_layout.Placement = undefined;
    for (grid, candidate_pixels[0..grid.len], 0..) |placed, *pixel, scene_index| {
        const x = std.math.mul(u32, placed.rect.x, cell_width) catch return error.DuetGeometry;
        const y = std.math.mul(u32, placed.rect.y, cell_height) catch return error.DuetGeometry;
        const width = std.math.mul(u32, placed.rect.width, cell_width) catch return error.DuetGeometry;
        const height = std.math.mul(u32, placed.rect.height, cell_height) catch return error.DuetGeometry;
        if (prepared[scene_index].width != width or prepared[scene_index].height != height)
            return error.ResizeResultMismatch;
        pixel.* = .{
            .pane = placed.pane,
            .rect = .{ .x = x, .y = y, .width = width, .height = height },
            .focused = placed.focused,
        };
    }
    @memcpy(pixel_storage[0..grid.len], candidate_pixels[0..grid.len]);
    mux.* = candidate;
    return true;
}

fn settleRolledBackGeometry(
    scenes: *[2]?terminal_scene.Scene,
    applied: [2]bool,
    rows: [2]u16,
    cols: [2]u16,
    end: usize,
    session_revisions: *[2]u64,
    prepared: *[2]terminal_scene.Prepared,
    changed: *[2]bool,
) !void {
    for (0..@min(end, scenes.len)) |scene_index| {
        if (!applied[scene_index]) continue;
        var attempts: u8 = 0;
        while (attempts < 8) : (attempts += 1) {
            const next = try scenes[scene_index].?.receivePrepared();
            session_revisions[scene_index] = next.session_revision;
            if (next.rows == rows[scene_index] and next.cols == cols[scene_index]) {
                prepared[scene_index] = next;
                changed[scene_index] = true;
                try scenes[scene_index].?.arm(session_revisions[scene_index]);
                break;
            }
            scenes[scene_index].?.discardPrepared(next);
            try scenes[scene_index].?.arm(session_revisions[scene_index]);
        } else return error.GeometryObservationTimeout;
    }
}

fn waitDuetReady(
    boundary: *shared.Boundary,
    scenes: *[2]?terminal_scene.Scene,
    scene_count: usize,
    start: usize,
) !DuetReady {
    if (scene_count == 0 or scene_count > scenes.len or start >= scene_count)
        return error.DuetGeometry;
    var descriptors: [3]c.pollfd = undefined;
    for (0..scene_count) |index| descriptors[index] = .{
        .fd = scenes[index].?.readinessFd(),
        .events = c.POLLIN,
        .revents = 0,
    };
    descriptors[scene_count] = .{
        .fd = boundary.controlFd(),
        .events = c.POLLIN,
        .revents = 0,
    };
    while (true) {
        for (descriptors[0 .. scene_count + 1]) |*descriptor| descriptor.revents = 0;
        const ready = c.poll(&descriptors, scene_count + 1, -1);
        if (ready < 0) {
            if (std.c.errno(ready) == .INTR) continue;
            return error.ScenePoll;
        }
        if (boundary.shouldStop()) return error.Stopping;
        if (ready == 0) continue;
        const control_events = descriptors[scene_count].revents;
        if (control_events & (c.POLLERR | c.POLLHUP | c.POLLNVAL) != 0)
            return error.ScenePoll;
        if (control_events & c.POLLIN != 0) {
            try boundary.drainControlWake();
            if (boundary.takeHostCommand()) |command| return .{ .command = command };
            if (boundary.takeWindowSize()) |size| return .{ .window_size = size };
            if (boundary.takeDisplayScale()) |scale| return .{ .display_scale = scale };
            if (boundary.takePointer()) |event| return .{ .pointer = event };
        }
        for (0..scene_count) |offset| {
            const index = (start + offset) % scene_count;
            if (descriptors[index].revents & (c.POLLIN | c.POLLERR | c.POLLHUP | c.POLLNVAL) != 0)
                return .{ .scene = index };
        }
    }
}

fn watchStop(
    boundary: *shared.Boundary,
    cancellations: *CancellationRegistry,
    done: *std.atomic.Value(bool),
) void {
    var descriptor = c.pollfd{ .fd = boundary.stopFd(), .events = c.POLLIN, .revents = 0 };
    while (!done.load(.acquire)) {
        descriptor.revents = 0;
        const ready = c.poll(&descriptor, 1, 100);
        if (ready == 0) continue;
        if (ready < 0) {
            if (std.c.errno(ready) == .INTR) continue;
            boundary.requestStop(.render);
            return;
        }
        if (boundary.shouldStop()) {
            cancellations.cancelAll(boundary);
            return;
        }
        boundary.drainStopWake() catch {
            boundary.requestStop(.render);
            return;
        };
    }
}

fn waitDisplayScale(boundary: *shared.Boundary) !shared.DisplayScale {
    var wakes: u8 = 0;
    while (wakes < 16) : (wakes += 1) {
        if (boundary.takeDisplayScale()) |value| return value;
        if (boundary.shouldStop()) return error.Stopping;
        try waitRenderWake(boundary);
    }
    return error.DisplayScaleTimeout;
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
    residency_commit: ?*surface.ResidencyStore,
    fast_draws: []const FastDraw,
    generic_draws: []const GenericDraw,
    wait_semaphore: ?vk.VkSemaphore,
    get_semaphore_fd: vk.PFN_vkGetSemaphoreFdKHR,
    drm_fd: i32,
    acquire_handle: u32,
    acquire_point: u64,
    width: u16,
    height: u16,
) !void {
    try graphics.stage(plan, alpha_pixels, image_pixels, width, height);
    for (generic_draws) |draw| if (draw.stage) try draw.context.stagePlaced(
        draw.plan,
        draw.alpha_pixels,
        draw.image_pixels,
        width,
        height,
        draw.placement,
    );

    if (vk.vkResetCommandBuffer(command, 0) != vk.VK_SUCCESS) return error.Command;
    var begin = std.mem.zeroes(vk.VkCommandBufferBeginInfo);
    begin.sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    if (vk.vkBeginCommandBuffer(command, &begin) != vk.VK_SUCCESS) return error.Command;
    const target = surface.FrameTarget{
        .image = slot.image,
        .attachment = slot.attachment,
        .attachment_width = width,
        .attachment_height = height,
        .coordinate_width = width,
        .coordinate_height = height,
        .source_queue_family = if (slot.external) vk.VK_QUEUE_FAMILY_EXTERNAL else vk.VK_QUEUE_FAMILY_IGNORED,
        .graphics_queue_family = family,
        .destination_queue_family = vk.VK_QUEUE_FAMILY_EXTERNAL,
    };
    const recording = try graphics.recordPrelude(command, target, plan);
    var auxiliary_recordings: [2]surface.Recording = undefined;
    var auxiliary_recorded: [2]bool = @splat(false);
    for (generic_draws, 0..) |draw, draw_index| if (draw.stage) {
        auxiliary_recordings[draw_index] = try draw.context.recordAuxiliaryPrelude(
            command,
            target,
            draw.plan,
            draw.placement,
        );
        auxiliary_recorded[draw_index] = true;
    };
    for (fast_draws) |draw| if (draw.changed) try draw.gpu.recordTransfers(command);
    graphics.beginPass(command, target, clear_color);
    for (fast_draws) |draw| try draw.gpu.recordDraw(
        command,
        draw.frame,
        draw.placement,
        width,
        height,
    );
    graphics.recordGenericDraws(command, target, plan);
    for (generic_draws) |draw|
        draw.context.recordGenericDrawsPlaced(command, target, draw.plan, draw.placement);
    const completed_recording = graphics.endPass(command, target, recording);
    if (vk.vkEndCommandBuffer(command) != vk.VK_SUCCESS) return error.Command;

    var export_info = std.mem.zeroes(vk.VkExportSemaphoreCreateInfo);
    export_info.sType = vk.VK_STRUCTURE_TYPE_EXPORT_SEMAPHORE_CREATE_INFO;
    export_info.handleTypes = vk.VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_SYNC_FD_BIT;
    var semaphore_info = std.mem.zeroes(vk.VkSemaphoreCreateInfo);
    semaphore_info.sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
    semaphore_info.pNext = @ptrCast(&export_info);
    var completion: vk.VkSemaphore = undefined;
    if (vk.vkCreateSemaphore(device, &semaphore_info, null, &completion) != vk.VK_SUCCESS) return error.Semaphore;
    defer vk.vkDestroySemaphore(device, completion, null);
    const wait_stage: vk.VkPipelineStageFlags = vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
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
    if (vk.vkQueueSubmit(queue, 1, &submit, null) != vk.VK_SUCCESS) return error.Submit;
    var fd_info = std.mem.zeroes(vk.VkSemaphoreGetFdInfoKHR);
    fd_info.sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_GET_FD_INFO_KHR;
    fd_info.semaphore = completion;
    fd_info.handleType = vk.VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_SYNC_FD_BIT;
    var sync_fd: i32 = -1;
    if (get_semaphore_fd.?(device, &fd_info, &sync_fd) != vk.VK_SUCCESS or sync_fd < 0) return error.Semaphore;
    defer closeDescriptor(sync_fd);
    var temporary: u32 = 0;
    if (c.drmSyncobjCreate(drm_fd, 0, &temporary) != 0) return error.Syncobj;
    defer destroySyncobj(drm_fd, temporary);
    if (c.drmSyncobjImportSyncFile(drm_fd, temporary, sync_fd) != 0) return error.Syncobj;
    var handles = [_]u32{temporary};
    if (c.drmSyncobjWait(drm_fd, &handles, 1, try deadline(), 0, null) != 0) return error.RenderTimeout;
    graphics.complete(completed_recording);
    for (fast_draws) |draw| if (draw.changed) try draw.gpu.complete();
    for (generic_draws, 0..) |draw, draw_index| {
        if (draw.stage) {
            std.debug.assert(auxiliary_recorded[draw_index]);
            draw.context.complete(auxiliary_recordings[draw_index]);
        }
        if (draw.residency_changed) try draw.residency.complete();
    }
    if (residency_commit) |value| try value.complete();
    if (c.drmSyncobjTransfer(drm_fd, acquire_handle, acquire_point, temporary, 0, 0) != 0) return error.Syncobj;
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
