//! Exclusively owns Vulkan mutation and DRM release observation.

const std = @import("std");
const c = @import("renderer_c");
const client = @import("howl_client");
const host_layout = @import("layout.zig");
const shared = @import("shared.zig");
const terminal_scene = @import("terminal_scene.zig");
const terminal_fast = @import("terminal_fast.zig");
const howl_vk = @import("howl_vk");
const vk = howl_vk.abi;
const surface = howl_vk.surface;

const gpu_memory_limit: u64 = 512 * 1024 * 1024;
const empty_plan = surface.Plan{
    .vertices = &.{},
    .indices = &.{},
    .commands = &.{},
    .atlas_changed = false,
};

const FastDraw = struct {
    gpu: *terminal_fast.Gpu,
    frame: terminal_fast.Prepared,
    placement: terminal_fast.Placement,
    changed: bool,
};

const GenericDraw = struct {
    context: *surface.Context,
    plan: surface.Plan,
    placement: surface.Placement,
    alpha_pixels: []const u8,
    image_pixels: []const u8,
    residency: *surface.ResidencyStore,
    changed: bool,
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

/// Runs the sole Vulkan/DRM owner until the bounded ring completes or fails.
/// All operational failures are recorded as the first Render runtime failure.
pub fn run(
    boundary: *shared.Boundary,
    allocator: std.mem.Allocator,
    endpoint: []const u8,
    endpoint_right: ?[]const u8,
    font_path: []const u8,
    mux: host_layout.Mux,
) void {
    runFallible(boundary, allocator, endpoint, endpoint_right, font_path, mux) catch |failure| {
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
    mux: host_layout.Mux,
) !void {
    const feedback = try waitFeedback(boundary);
    const scene_count: usize = if (endpoint_right != null) 2 else 1;
    var scenes: [2]?terminal_scene.Scene = .{ null, null };
    var initialized_scene_count: usize = 0;
    defer {
        var scene_index = initialized_scene_count;
        while (scene_index != 0) {
            scene_index -= 1;
            scenes[scene_index].?.deinit();
        }
    }
    scenes[0] = try terminal_scene.Scene.init(allocator, endpoint, font_path);
    initialized_scene_count = 1;
    if (endpoint_right) |right| {
        scenes[1] = try terminal_scene.Scene.init(allocator, right, font_path);
        initialized_scene_count = 2;
    }
    var prepared: [2]terminal_scene.Prepared = undefined;
    var session_revisions: [2]u64 = @splat(0);
    for (0..scene_count) |scene_index| {
        prepared[scene_index] = try scenes[scene_index].?.prepare(0);
        session_revisions[scene_index] = prepared[scene_index].session_revision;
    }
    var surface_width = prepared[0].width;
    const surface_height = prepared[0].height;
    if (scene_count == 2) {
        if (prepared[1].height != surface_height) return error.DuetGeometry;
        surface_width = std.math.add(u16, surface_width, prepared[1].width) catch
            return error.DuetGeometry;
    }
    var projected_layout: [host_layout.max_panes_per_tab]host_layout.Placement = undefined;
    const placements = try mux.activeLayout(
        .{ .width = surface_width, .height = surface_height },
        &projected_layout,
    );
    if (placements.len != scene_count) return error.DuetGeometry;
    for (placements, 0..) |placement, scene_index| {
        if (placement.rect.width != prepared[scene_index].width or
            placement.rect.height != prepared[scene_index].height)
            return error.DuetGeometry;
    }
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
        var gpu_index = scene_count;
        while (gpu_index != 0) {
            gpu_index -= 1;
            if (fast_gpus[gpu_index]) |*value| value.deinit(device, &gpu_bytes);
        }
    }
    var generic_contexts: [2]?surface.Context = .{ null, null };
    defer {
        var context_index = scene_count;
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
    var slots = [_]Slot{ .{}, .{}, .{} };
    defer {
        var index = slots.len;
        while (index > 0) {
            index -= 1;
            slots[index].deinit(device, drm_fd);
        }
    }
    var offers: [shared.slot_count]shared.SlotOffer = undefined;
    var offered_fds = [_]OfferedFds{ .{}, .{}, .{} };
    errdefer for (&offered_fds) |*fds| {
        if (fds.dma >= 0) closeDescriptor(fds.dma);
        if (fds.acquire >= 0) closeDescriptor(fds.acquire);
        if (fds.timeline >= 0) closeDescriptor(fds.timeline);
    };
    for (&slots, 0..) |*slot, index| {
        try constructSlot(slot, &graphics, device, memory_properties, feedback.modifier, dedicated_only, plane_count, surface_width, surface_height, get_memory_fd.?, get_modifier.?, drm_fd, &offers[index], &offered_fds[index]);
        if (c.drmSyncobjHandleToFD(drm_fd, acquire_handle, &offered_fds[index].acquire) != 0) return error.Syncobj;
        offers[index].acquire_timeline_fd = offered_fds[index].acquire;
    }
    try boundary.publishOffers(offers);
    for (&offered_fds) |*fds| fds.* = .{};
    try waitWindowRing(boundary);

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
    var slot_index: usize = 0;
    var previous_slot: ?usize = null;
    var changed: [2]bool = .{ true, scene_count == 2 };
    var retained_draw_count: u64 = 0;
    var generic_draw_count_total: u64 = 0;
    var duet_armed = false;
    var next_ready_start: usize = 0;

    var cancellations: [2]client.Cancellation = undefined;
    var cancellation_count: usize = 0;
    defer {
        var cancellation_index = cancellation_count;
        while (cancellation_index != 0) {
            cancellation_index -= 1;
            cancellations[cancellation_index].deinit();
        }
    }
    for (0..scene_count) |scene_index| {
        cancellations[scene_index] = try scenes[scene_index].?.cancellation();
        cancellation_count += 1;
    }
    var watcher_done = std.atomic.Value(bool).init(false);
    const watcher = try std.Thread.spawn(.{}, watchStop, .{
        boundary,
        cancellations[0..scene_count],
        &watcher_done,
    });
    defer {
        watcher_done.store(true, .release);
        watcher.join();
    }

    while (!boundary.shouldStop()) {
        var wait_semaphore: ?vk.VkSemaphore = null;
        defer if (wait_semaphore) |value| vk.vkDestroySemaphore(device, value, null);
        const slot = &slots[slot_index];
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
        var plan = empty_plan;
        var clear_color = [4]f32{ 0, 0, 0, 1 };
        var residency_commit: ?*surface.ResidencyStore = null;
        var fast_draw_storage: [2]FastDraw = undefined;
        var fast_draw_count: usize = 0;
        var generic_draw_storage: [2]GenericDraw = undefined;
        var generic_draw_count: usize = 0;
        if (scene_count == 1) {
            switch (prepared[0].mode) {
                .generic => |generic| {
                    generic_draw_count_total += 1;
                    plan = generic.plan;
                    residency_commit = &scenes[0].?.residency;
                },
                .fast => |frame| {
                    retained_draw_count += 1;
                    if (fast_gpus[0] == null)
                        fast_gpus[0] = try terminal_fast.Gpu.init(
                            allocator,
                            device,
                            memory_properties,
                            graphics.render_pass,
                            &gpu_bytes,
                            gpu_memory_limit,
                            frame.terminal,
                        );
                    if (changed[0]) try fast_gpus[0].?.prepare(frame.terminal);
                    fast_draw_storage[0] = .{
                        .gpu = &fast_gpus[0].?,
                        .frame = frame.terminal,
                        .placement = fastPlacement(placements[0]),
                        .changed = changed[0],
                    };
                    fast_draw_count = 1;
                    clear_color = frame.terminal.clear_color;
                    plan = frame.plan;
                    if (frame.overlay_pending) residency_commit = &scenes[0].?.overlay_residency;
                },
            }
        } else {
            for (0..scene_count) |scene_index| {
                const placement = surfacePlacement(placements[scene_index]);
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
                            .changed = changed[scene_index],
                        };
                        generic_draw_count += 1;
                    },
                    .fast => |frame| {
                        retained_draw_count += 1;
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
                        if (changed[scene_index])
                            try fast_gpus[scene_index].?.prepare(frame.terminal);
                        fast_draw_storage[fast_draw_count] = .{
                            .gpu = &fast_gpus[scene_index].?,
                            .frame = frame.terminal,
                            .placement = fastPlacement(placements[scene_index]),
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
                                .changed = changed[scene_index],
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
        errdefer for (generic_draws) |draw| if (draw.changed) draw.residency.discard();
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
        try boundary.publishCompletion(.{
            .revision = present_revision,
            .slot = @intCast(slot_index),
            .acquire_point = acquire_point,
            .release_point = slot.release_point,
        });

        // Publishing the next slot lets KWin retire the previous one. Waiting
        // here bounds presentation backlog without pacing canonical Session
        // progress: Session continues independently while this observer waits.
        if (previous_slot) |prior| {
            try waitTimeline(drm_fd, slots[prior].release_handle, slots[prior].release_point);
        }
        previous_slot = slot_index;
        slot_index = (slot_index + 1) % shared.slot_count;
        for (0..scene_count) |scene_index| changed[scene_index] = false;

        if (scene_count == 1) {
            const next = scenes[0].?.prepare(session_revisions[0]) catch |failure| {
                if (boundary.shouldStop()) break;
                return failure;
            };
            if (next.width != prepared[0].width or next.height != prepared[0].height)
                return error.GeometryChanged;
            session_revisions[0] = next.session_revision;
            prepared[0] = next;
            changed[0] = true;
        } else {
            if (!duet_armed) {
                for (0..scene_count) |scene_index|
                    try scenes[scene_index].?.arm(session_revisions[scene_index]);
                duet_armed = true;
            }
            const ready_index = waitSceneReady(
                boundary,
                &scenes,
                scene_count,
                next_ready_start,
            ) catch |failure| {
                if (boundary.shouldStop()) break;
                return failure;
            };
            next_ready_start = (ready_index + 1) % scene_count;
            const next = scenes[ready_index].?.receivePrepared() catch |failure| {
                if (boundary.shouldStop()) break;
                return failure;
            };
            if (next.width != prepared[ready_index].width or
                next.height != prepared[ready_index].height)
                return error.GeometryChanged;
            session_revisions[ready_index] = next.session_revision;
            prepared[ready_index] = next;
            changed[ready_index] = true;
            try scenes[ready_index].?.arm(session_revisions[ready_index]);
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

fn waitSceneReady(
    boundary: *shared.Boundary,
    scenes: *[2]?terminal_scene.Scene,
    scene_count: usize,
    start: usize,
) !usize {
    if (scene_count == 0 or scene_count > scenes.len or start >= scene_count)
        return error.DuetGeometry;
    var descriptors: [2]c.pollfd = undefined;
    for (0..scene_count) |index| descriptors[index] = .{
        .fd = scenes[index].?.readinessFd(),
        .events = c.POLLIN,
        .revents = 0,
    };
    while (true) {
        const ready = c.poll(&descriptors, scene_count, -1);
        if (ready < 0) {
            if (std.c.errno(ready) == .INTR) continue;
            return error.ScenePoll;
        }
        if (boundary.shouldStop()) return error.Stopping;
        if (ready == 0) continue;
        for (0..scene_count) |offset| {
            const index = (start + offset) % scene_count;
            if (descriptors[index].revents & (c.POLLIN | c.POLLERR | c.POLLHUP | c.POLLNVAL) != 0)
                return index;
        }
        return error.ScenePoll;
    }
}

fn watchStop(
    boundary: *shared.Boundary,
    cancellations: []const client.Cancellation,
    done: *std.atomic.Value(bool),
) void {
    var descriptor = c.pollfd{ .fd = boundary.renderFd(), .events = c.POLLIN, .revents = 0 };
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
            for (cancellations) |cancellation|
                cancellation.cancel() catch boundary.requestStop(.render);
            return;
        }
        boundary.drainRenderWake() catch {
            boundary.requestStop(.render);
            return;
        };
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

fn waitWindowRing(boundary: *shared.Boundary) !void {
    var wakes: u8 = 0;
    while (wakes < 8) : (wakes += 1) {
        if (boundary.isWindowRingReady()) return;
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
    offer.* = .{ .dma_fd = offered_fds.dma, .acquire_timeline_fd = -1, .release_timeline_fd = offered_fds.timeline, .width = width, .height = height, .plane_count = plane_count, .planes = slot.planes };
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
    for (generic_draws) |draw| if (draw.changed) try draw.context.stagePlaced(
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
    for (generic_draws, 0..) |draw, draw_index| if (draw.changed) {
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
    for (generic_draws, 0..) |draw, draw_index| if (draw.changed) {
        std.debug.assert(auxiliary_recorded[draw_index]);
        draw.context.complete(auxiliary_recordings[draw_index]);
        try draw.residency.complete();
    };
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
