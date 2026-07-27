//! Exclusively owns Vulkan mutation and DRM release observation.

const std = @import("std");
const c = @import("renderer_c");
const shared = @import("shared.zig");

const terminal_retained_resource_limit: usize = 512 + 128 + 8;
const chrome_retained_resource_limit: usize = 512;
const frame_resource_limit: usize = 2048;
const frame_command_limit: usize = 32_768;
const howl_vk = @import("howl_vk");
const vk = howl_vk.abi;
const render_api = @import("howl_render");
const chrome_state = @import("chrome_state");
const vk_surface = howl_vk.surface;
const input_actions = @import("input_actions");
const terminal_handoff = @import("terminal_handoff");

const chrome_appearance = chrome_state.Appearance{
    .style = .{
        .foreground = .{ .r = 230, .g = 235, .b = 245, .a = 255 },
        .background = .{ .r = 20, .g = 24, .b = 32, .a = 255 },
        .border = .{ .r = 80, .g = 90, .b = 110, .a = 255 },
    },
    .tab_active_background = .{ .r = 48, .g = 72, .b = 112, .a = 255 },
    .tab_inactive_background = .{ .r = 28, .g = 34, .b = 46, .a = 255 },
};

const gpu_memory_limit: u64 = 512 * 1024 * 1024;

const RetiredTerminalSource = struct {
    pane: render_api.chrome.PaneId,
    source: render_api.canvas.SourceId,
};

const CanvasWork = struct {
    composer: *render_api.canvas.Composer,
    content: *render_api.chrome.Content,
    source: render_api.canvas.SourceId,
    producer_revision: u64 = 0,
    frame_uploads: []render_api.canvas.ResourceUploadFact,
    frame_removals: []render_api.canvas.FrameResourceRef,
    frame_commands: []render_api.canvas.Command,
    frame_pixels: []u8,
    surface_uploads: []vk_surface.Upload,
    surface_removals: []vk_surface.Removal,
    surface_commands: []vk_surface.FrameCommand,
    surface_residencies: []vk_surface.Residency,
    canvas_residencies: []render_api.canvas.Residency,
    builder: *vk_surface.FrameBuilder,
    residency: *vk_surface.ResidencyStore,
    terminals: *terminal_handoff.Boundary,
    terminal_rejection_reported: bool = false,
    next_visible_revision: u64 = 1,
    visible_placements: [terminal_handoff.visible_member_limit]render_api.canvas.Composer.Placement = undefined,
    visible_count: u8 = 0,
    pending_visible_revision: ?u64 = null,
    pending_placements: [terminal_handoff.visible_member_limit]render_api.canvas.Composer.Placement = undefined,
    pending_count: u8 = 0,
    retired_sources: [64]RetiredTerminalSource = undefined,
    retired_source_count: u8 = 0,
};

const Slot = struct {
    width: u32 = 0,
    height: u32 = 0,
    image: vk.VkImage = null,
    memory: vk.VkDeviceMemory = null,
    release_handle: u32 = 0,
    plane_count: u8 = 0,
    planes: [shared.plane_limit]shared.Plane = undefined,
    external: bool = false,
    attachment: vk_surface.Attachment = .{},
    owned_bytes: u64 = 0,
    release_point: u64 = 0,
    clear_color: [4]f32 = .{ 0, 0, 0, 1 },

    fn deinit(self: *Slot, device: vk.VkDevice, drm_fd: i32, gpu_bytes: *u64) void {
        self.attachment.deinit(device);
        if (self.release_handle != 0) destroySyncobj(drm_fd, self.release_handle);
        if (self.image != null) vk.vkDestroyImage(device, self.image, null);
        if (self.memory != null) vk.vkFreeMemory(device, self.memory, null);
        gpu_bytes.* -= self.owned_bytes;
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
    terminals: *terminal_handoff.Boundary,
    allocator: std.mem.Allocator,
    font_path: []const u8,
) void {
    runFallible(boundary, terminals, allocator, font_path) catch |failure| {
        std.debug.print("Render failure: {s}\n", .{@errorName(failure)});
        boundary.requestStop(.render);
    };
    boundary.markStopped(.render);
}

fn runFallible(
    boundary: *shared.Boundary,
    terminals: *terminal_handoff.Boundary,
    allocator: std.mem.Allocator,
    font_path: []const u8,
) !void {
    const feedback = try waitFeedback(boundary);
    const initial_surface = try waitConfigure(boundary);
    try checkGpuBudget(initial_surface.width, initial_surface.height);
    var chrome = try chrome_state.Topology.init(.{ .width = @intCast(initial_surface.width), .height = @intCast(initial_surface.height) }, chrome_state.default_tab_bar_height);
    var composer = try render_api.canvas.Composer.init(allocator, .{
        .sources = chrome_state.max_live_panes + 1,
        .retained_resources = frame_resource_limit,
        .retained_commands = frame_command_limit,
        .retained_pixel_bytes = 16 * 1024 * 1024,
        .composition_sources = chrome_state.max_live_panes + 1,
        .candidate_resources = 1024,
        .candidate_commands = frame_command_limit,
        .candidate_pixel_bytes = 4 * 1024 * 1024,
    });
    defer composer.deinit();
    const chrome_source = try composer.registerSource();
    var chrome_content = try render_api.chrome.Content.init(allocator, .{
        .primitives = 256,
        .text_bytes = (chrome_state.max_tabs + chrome_state.max_panes_per_tab) * chrome_state.max_label_bytes,
        .label_scalars = 4096,
        .shaped_glyphs = 4096,
        .glyphs = 512,
        .commands = 2048,
        .resources_per_update = 512,
        .upload_bytes = 8 * 1024 * 1024,
        .raster_bytes = 512 * 1024,
    }, .{ .primary = font_path, .pixel_height = 16 });
    defer chrome_content.deinit();
    const frame_uploads = try allocator.alloc(
        render_api.canvas.ResourceUploadFact,
        frame_resource_limit,
    );
    defer allocator.free(frame_uploads);
    const frame_removals = try allocator.alloc(
        render_api.canvas.FrameResourceRef,
        frame_resource_limit,
    );
    defer allocator.free(frame_removals);
    const frame_commands = try allocator.alloc(
        render_api.canvas.Command,
        frame_command_limit,
    );
    defer allocator.free(frame_commands);
    const frame_pixels = try allocator.alloc(u8, 8 * 1024 * 1024);
    defer allocator.free(frame_pixels);
    var surface_uploads: [frame_resource_limit]vk_surface.Upload = undefined;
    var surface_removals: [frame_resource_limit]vk_surface.Removal = undefined;
    const surface_commands = try allocator.alloc(
        vk_surface.FrameCommand,
        frame_command_limit,
    );
    defer allocator.free(surface_commands);
    var surface_residencies: [frame_resource_limit]vk_surface.Residency = undefined;
    var canvas_residencies: [frame_resource_limit]render_api.canvas.Residency = undefined;
    var surface_builder = try vk_surface.FrameBuilder.init(allocator);
    defer surface_builder.deinit();
    var surface_residency = try vk_surface.ResidencyStore.init(allocator, .{
        .resources = frame_resource_limit,
        .pixel_bytes = 8 * 1024 * 1024,
    });
    defer surface_residency.deinit();
    var canvas_work = CanvasWork{
        .composer = &composer,
        .content = &chrome_content,
        .source = chrome_source,
        .frame_uploads = frame_uploads,
        .frame_removals = frame_removals,
        .frame_commands = frame_commands,
        .frame_pixels = frame_pixels,
        .surface_uploads = &surface_uploads,
        .surface_removals = &surface_removals,
        .surface_commands = surface_commands,
        .surface_residencies = &surface_residencies,
        .canvas_residencies = &canvas_residencies,
        .builder = &surface_builder,
        .residency = &surface_residency,
        .terminals = terminals,
    };
    const initial_pane = chrome.paneId(0, 0) orelse return error.InvalidTopology;
    const initial_rect = chrome.paneRect(initial_pane) orelse return error.InvalidTopology;
    const initial_source = try composer.registerSource();
    try terminals.register(
        initial_pane,
        initial_source,
        @max(@as(u16, 1), initial_rect.width / 8),
        @max(@as(u16, 1), initial_rect.height / 16),
    );
    var chrome_primitives: [256]render_api.chrome.Primitive = undefined;
    var chrome_text: [(chrome_state.max_tabs + chrome_state.max_panes_per_tab) * chrome_state.max_label_bytes]u8 = undefined;
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
    const dispatch = howl_vk.dispatch.load(device) catch return error.FunctionLoad;

    var memory_properties: vk.VkPhysicalDeviceMemoryProperties = undefined;
    vk.vkGetPhysicalDeviceMemoryProperties(physical, &memory_properties);
    var gpu_bytes: u64 = 0;
    var graphics = try vk_surface.Context.init(device, memory_properties, &gpu_bytes, gpu_memory_limit);
    defer graphics.deinit(device, &gpu_bytes);
    const plane_count = try modifierPlaneCount(physical, feedback.modifier);
    var acquire_handle: u32 = 0;
    if (c.drmSyncobjCreate(drm_fd, 0, &acquire_handle) != 0) return error.Syncobj;
    defer destroySyncobj(drm_fd, acquire_handle);
    var rings = [_][shared.slot_count]Slot{
        .{ .{}, .{}, .{} },
        .{ .{}, .{}, .{} },
    };
    defer {
        var ring_index = rings.len;
        while (ring_index > 0) {
            ring_index -= 1;
            var index = shared.slot_count;
            while (index > 0) {
                index -= 1;
                rings[ring_index][index].deinit(device, drm_fd, &gpu_bytes);
            }
        }
    }
    var offers: [shared.slot_count]shared.SlotOffer = undefined;
    var offered_fds = [_]OfferedFds{ .{}, .{}, .{} };
    errdefer for (&offered_fds) |*fds| {
        if (fds.dma >= 0) closeDescriptor(fds.dma);
        if (fds.acquire >= 0) closeDescriptor(fds.acquire);
        if (fds.timeline >= 0) closeDescriptor(fds.timeline);
    };
    for (&rings[0], 0..) |*slot, index| {
        try constructSlot(slot, &graphics, device, memory_properties, feedback.modifier, dedicated_only, plane_count, initial_surface, &dispatch, drm_fd, &offers[index], &offered_fds[index], &gpu_bytes);
        if (c.drmSyncobjHandleToFD(drm_fd, acquire_handle, &offered_fds[index].acquire) != 0) return error.Syncobj;
        offers[index].acquire_timeline_fd = offered_fds[index].acquire;
    }
    try boundary.publishOffers(offers);
    for (&offered_fds) |*fds| fds.* = .{};
    try waitWindowRing(boundary, initial_surface.generation);

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

    const colors = [_][4]f32{
        .{ 0.08, 0.16, 0.24, 1 },
        .{ 0.12, 0.48, 0.20, 1 },
        .{ 0.52, 0.16, 0.56, 1 },
    };
    var next_acquire_point: u64 = 4;
    for (&rings[0], 0..) |*slot, index| {
        queue_active = true;
        const composer_plan = try buildCanvasPlan(&canvas_work, &chrome, chrome_appearance, &chrome_primitives, &chrome_text);
        errdefer surface_residency.discard();
        try render(&graphics, device, queue, family, command, slot, colors[index], composer_plan, surface_builder.alpha_pixels, surface_builder.rgba_pixels, &surface_residency, null, &dispatch, drm_fd, acquire_handle, index + 1);
        try boundary.publishCompletion(.{ .generation = initial_surface.generation, .revision = index + 1, .slot = @intCast(index), .acquire_point = index + 1, .release_point = 1 });
        slot.release_point = 1;
    }
    std.debug.print("Render ring submitted revisions=3 slots=3 generation={d}\n", .{initial_surface.generation});

    // The first generation exercises real slot reuse before any resize: once
    // Window has superseded slot 0, import its compositor release fence into
    // a Vulkan wait semaphore, reacquire the image, and publish a fourth clear.
    try waitTimeline(drm_fd, rings[0][0].release_handle, 1);
    var release_sync_fd: i32 = -1;
    if (c.drmSyncobjExportSyncFile(drm_fd, rings[0][0].release_handle, &release_sync_fd) != 0) return error.Syncobj;
    errdefer if (release_sync_fd >= 0) closeDescriptor(release_sync_fd);
    const release_wait = try importReleaseSemaphore(device, &dispatch, &release_sync_fd);
    defer vk.vkDestroySemaphore(device, release_wait, null);
    const reuse_plan = try buildCanvasPlan(&canvas_work, &chrome, chrome_appearance, &chrome_primitives, &chrome_text);
    errdefer surface_residency.discard();
    try render(&graphics, device, queue, family, command, &rings[0][0], .{ 0.72, 0.18, 0.20, 1 }, reuse_plan, surface_builder.alpha_pixels, surface_builder.rgba_pixels, &surface_residency, release_wait, &dispatch, drm_fd, acquire_handle, next_acquire_point);
    try boundary.publishCompletion(.{ .generation = initial_surface.generation, .revision = next_acquire_point, .slot = 0, .acquire_point = next_acquire_point, .release_point = 2 });
    rings[0][0].release_point = 2;
    std.debug.print("Render same-generation reuse slot=0 acquire={d} release=2 generation={d}\n", .{ next_acquire_point, initial_surface.generation });
    next_acquire_point += 1;

    var active_ring: usize = 0;
    var active_generation = initial_surface.generation;
    var actions = input_actions.State{};
    var terminal_redraw_pending = false;
    while (!boundary.shouldStop()) {
        if (boundary.takeConfigure()) |surface| {
            if (surface.generation <= active_generation) continue;
            const prior_chrome = chrome;
            var candidate_chrome = chrome;
            candidate_chrome.resizeSurface(.{ .width = @intCast(surface.width), .height = @intCast(surface.height) }) catch |failure| switch (failure) {
                error.InvalidGeometry => continue,
                else => return failure,
            };
            try validateTerminalTopology(&candidate_chrome);
            try checkGpuBudget(surface.width, surface.height);
            const replacement = 1 - active_ring;
            for (&rings[replacement]) |*slot| slot.* = .{};
            var replacement_offers: [shared.slot_count]shared.SlotOffer = undefined;
            var replacement_fds = [_]OfferedFds{ .{}, .{}, .{} };
            errdefer for (&replacement_fds) |*fds| {
                if (fds.dma >= 0) closeDescriptor(fds.dma);
                if (fds.acquire >= 0) closeDescriptor(fds.acquire);
                if (fds.timeline >= 0) closeDescriptor(fds.timeline);
            };
            var superseded = false;
            for (&rings[replacement], 0..) |*slot, index| {
                try constructSlot(slot, &graphics, device, memory_properties, feedback.modifier, dedicated_only, plane_count, surface, &dispatch, drm_fd, &replacement_offers[index], &replacement_fds[index], &gpu_bytes);
                if (c.drmSyncobjHandleToFD(drm_fd, acquire_handle, &replacement_fds[index].acquire) != 0) return error.Syncobj;
                replacement_offers[index].acquire_timeline_fd = replacement_fds[index].acquire;
                if (!boundary.isLatestGeneration(surface.generation)) {
                    superseded = true;
                    break;
                }
            }
            if (superseded) {
                for (&replacement_fds) |*fds| {
                    if (fds.dma >= 0) closeDescriptor(fds.dma);
                    if (fds.acquire >= 0) closeDescriptor(fds.acquire);
                    if (fds.timeline >= 0) closeDescriptor(fds.timeline);
                    fds.* = .{};
                }
                for (&rings[replacement]) |*slot| slot.deinit(device, drm_fd, &gpu_bytes);
                continue;
            }
            boundary.publishOffers(replacement_offers) catch |failure| switch (failure) {
                error.InvalidOffer => {
                    if (!boundary.isLatestGeneration(surface.generation)) {
                        for (&replacement_fds) |*fds| {
                            if (fds.dma >= 0) closeDescriptor(fds.dma);
                            if (fds.acquire >= 0) closeDescriptor(fds.acquire);
                            if (fds.timeline >= 0) closeDescriptor(fds.timeline);
                            fds.* = .{};
                        }
                        for (&rings[replacement]) |*slot| slot.deinit(device, drm_fd, &gpu_bytes);
                        continue;
                    }
                    return failure;
                },
                else => return failure,
            };
            for (&replacement_fds) |*fds| fds.* = .{};
            try waitWindowRing(boundary, surface.generation);
            var terminal_candidate = try prepareTerminalTopology(
                &canvas_work,
                &prior_chrome,
                &candidate_chrome,
            );
            defer terminal_candidate.deinit();
            var completion_batch: [shared.slot_count]shared.Completion = undefined;
            var candidate_acquire = next_acquire_point;
            for (&rings[replacement], 0..) |*slot, index| {
                const resized_plan = try buildCanvasPlan(&canvas_work, &candidate_chrome, chrome_appearance, &chrome_primitives, &chrome_text);
                errdefer surface_residency.discard();
                try render(&graphics, device, queue, family, command, slot, .{ 0.08 + @as(f32, @floatFromInt(index)) * 0.12, 0.22, 0.44, 1 }, resized_plan, surface_builder.alpha_pixels, surface_builder.rgba_pixels, &surface_residency, null, &dispatch, drm_fd, acquire_handle, candidate_acquire);
                completion_batch[index] = .{
                    .generation = surface.generation,
                    .revision = candidate_acquire,
                    .slot = @intCast(index),
                    .acquire_point = candidate_acquire,
                    .release_point = 1,
                };
                candidate_acquire = std.math.add(u64, candidate_acquire, 1) catch
                    return error.RevisionOverflow;
            }
            var prepared_completions = try boundary.prepareCompletions(&completion_batch);
            defer prepared_completions.deinit();
            try terminal_candidate.commit();
            chrome = candidate_chrome;
            prepared_completions.commit();
            for (&rings[replacement]) |*slot| slot.release_point = 1;
            next_acquire_point = candidate_acquire;
            const old_ring = active_ring;
            const old_generation = active_generation;
            active_ring = replacement;
            active_generation = surface.generation;
            try waitReleasePoints(boundary, old_generation, &rings[old_ring], drm_fd);
            boundary.requestWindowRingRetirement(old_generation);
            try waitWindowRingRetired(boundary, old_generation);
            for (&rings[old_ring]) |*slot| slot.deinit(device, drm_fd, &gpu_bytes);
        }
        try drainInput(
            boundary,
            &actions,
            &canvas_work,
            &chrome,
            chrome_appearance,
            &chrome_primitives,
            &chrome_text,
            &graphics,
            device,
            queue,
            family,
            command,
            &rings[active_ring],
            active_generation,
            &dispatch,
            drm_fd,
            acquire_handle,
            &next_acquire_point,
        );
        terminal_redraw_pending =
            (try waitRenderWakeBlocking(boundary, terminals)) or
            terminal_redraw_pending;
        const terminal_status = terminals.status();
        if (terminal_status.stopped)
            return if (terminal_status.failed)
                error.TerminalRuntime
            else
                error.TerminalStopped;
        if (terminal_redraw_pending) {
            redrawChrome(
                boundary,
                &chrome,
                chrome,
                &canvas_work,
                chrome_appearance,
                &chrome_primitives,
                &chrome_text,
                &graphics,
                device,
                queue,
                family,
                command,
                &rings[active_ring],
                active_generation,
                &dispatch,
                drm_fd,
                acquire_handle,
                &next_acquire_point,
            ) catch |failure| switch (failure) {
                error.NoReleasedSlot => continue,
                else => return failure,
            };
            terminal_redraw_pending = false;
        }
    }
    try waitReleasePoints(boundary, active_generation, &rings[active_ring], drm_fd);
    boundary.requestWindowRingRetirement(active_generation);
    try waitWindowRingRetired(boundary, active_generation);
    if (vk.vkDeviceWaitIdle(device) != vk.VK_SUCCESS) return error.DeviceIdle;
    queue_active = false;
}

fn checkGpuBudget(width: u32, height: u32) !void {
    const pixels = std.math.mul(u64, width, height) catch return error.GpuMemoryLimit;
    // Reject impossible replacement geometry before Vulkan construction. The
    // six exported-image allocations are subsequently charged from their
    // exact VkMemoryRequirements.size alongside the shared atlas/staging.
    const bytes = std.math.mul(u64, pixels, 4 * shared.slot_count * 2) catch return error.GpuMemoryLimit;
    if (bytes > gpu_memory_limit) return error.GpuMemoryLimit;
}

fn buildCanvasPlan(
    work: *CanvasWork,
    topology: *const chrome_state.Topology,
    appearance: chrome_state.Appearance,
    primitives: []render_api.chrome.Primitive,
    text: []u8,
) !vk_surface.Plan {
    while (work.terminals.takeRetired()) |retired| {
        if (work.retired_source_count == work.retired_sources.len)
            return error.InvalidTopology;
        work.retired_sources[work.retired_source_count] = .{
            .pane = retired.pane,
            .source = retired.source,
        };
        work.retired_source_count += 1;
    }
    const output = try topology.project(appearance, &.{}, primitives, text);
    try work.content.apply(output);
    const update = try work.content.takeUpdate();
    const producer_revision = @backingInt(update.revision);
    if (producer_revision < work.producer_revision) return error.InvalidRevision;
    if (producer_revision > work.producer_revision) {
        try work.composer.apply(work.source, update);
        work.producer_revision = producer_revision;
    }
    const drainage = try work.terminals.drainReady(work.composer);
    if (drainage.accepted > chrome_state.max_live_panes)
        return error.InvalidFrame;
    if (drainage.rejected) |failure| {
        if (!work.terminal_rejection_reported) {
            std.debug.print(
                "Terminal Canvas update retained after Composer rejection: {s}\n",
                .{@errorName(failure)},
            );
            work.terminal_rejection_reported = true;
        }
    }
    var desired: [terminal_handoff.visible_member_limit]render_api.canvas.Composer.Placement = undefined;
    var desired_members: [terminal_handoff.visible_member_limit]terminal_handoff.VisibleMember = undefined;
    var desired_count: usize = 0;
    var desired_complete = true;
    const active_tab = topology.activeTabIndex();
    for (0..topology.paneCount(active_tab)) |pane_index| {
        const pane = topology.paneId(active_tab, pane_index) orelse
            return error.InvalidTopology;
        const source = work.terminals.sourceFor(pane) orelse {
            desired_complete = false;
            continue;
        };
        if (desired_count == desired.len) return error.InvalidTopology;
        const rect = topology.paneRect(pane) orelse return error.InvalidTopology;
        desired[desired_count] = .{
            .source = source,
            .origin = .{ .x = rect.x, .y = rect.y },
            .clip = rect,
        };
        desired_members[desired_count] = .{ .pane = pane, .source = source };
        desired_count += 1;
    }
    if (desired_complete)
        try updateVisibleComposition(
            work,
            desired[0..desired_count],
            desired_members[0..desired_count],
        );
    var claimed_visible_revision: ?u64 = null;
    if (work.pending_visible_revision) |revision| {
        if (desired_complete and
            placementsEqual(
                desired[0..desired_count],
                work.pending_placements[0..work.pending_count],
            ) and
            work.terminals.visibleSetStatus(revision) == .ready)
        {
            try work.terminals.claimVisibleSet(revision);
            claimed_visible_revision = revision;
        }
    }
    errdefer if (claimed_visible_revision) |revision|
        work.terminals.releaseVisibleSetClaim(revision) catch
            @panic("visible-set composition claim could not be restored");
    var placements: [terminal_handoff.visible_member_limit + 1]render_api.canvas.Composer.Placement = undefined;
    const terminal_placements = if (claimed_visible_revision != null)
        work.pending_placements[0..work.pending_count]
    else
        work.visible_placements[0..work.visible_count];
    var placement_count: usize = terminal_placements.len;
    @memcpy(placements[0..placement_count], terminal_placements);
    placements[placement_count] = .{
        .source = work.source,
        .origin = .{ .x = 0, .y = 0 },
        .clip = .{ .x = 0, .y = 0, .width = output.surface.width, .height = output.surface.height },
    };
    placement_count += 1;
    try work.composer.setComposition(.{
        .surface = output.surface,
        .sources = placements[0..placement_count],
    });
    if (claimed_visible_revision) |revision| {
        try work.terminals.commitVisibleSet(revision);
        @memcpy(
            work.visible_placements[0..work.pending_count],
            work.pending_placements[0..work.pending_count],
        );
        work.visible_count = work.pending_count;
        work.pending_visible_revision = null;
        work.pending_count = 0;
        claimed_visible_revision = null;
    }
    var retired_index: usize = 0;
    while (retired_index < work.retired_source_count) {
        const retired = work.retired_sources[retired_index];
        if (placementContainsSource(
            work.visible_placements[0..work.visible_count],
            retired.source,
        )) {
            retired_index += 1;
            continue;
        }
        try work.composer.removeSource(retired.source);
        try work.terminals.finishRetired(retired.pane);
        work.retired_source_count -= 1;
        work.retired_sources[retired_index] =
            work.retired_sources[work.retired_source_count];
    }
    const surface_resident = try work.residency.enumerate(work.surface_residencies);
    for (surface_resident, 0..) |value, index| {
        work.canvas_residencies[index] = .{
            .resource = canvasResource(value.resource),
            .format = switch (value.kind) {
                .alpha_mask => .alpha8,
                .rgba => .rgba8,
                .solid => return error.InvalidFrame,
            },
            .size = .{ .width = value.width, .height = value.height },
        };
    }
    const frame = try work.composer.frame(work.canvas_residencies[0..surface_resident.len], .{
        .uploads = work.frame_uploads,
        .removals = work.frame_removals,
        .commands = work.frame_commands,
        .pixels = work.frame_pixels,
    });
    const generic = try adaptCanvasFrame(frame, work.surface_uploads, work.surface_removals, work.surface_commands);
    std.debug.print(
        "Canvas frame rev={d} uploads={d} removals={d} commands={d}\n",
        .{
            generic.revision,
            generic.uploads.len,
            generic.removals.len,
            generic.commands.len,
        },
    );
    try work.residency.stage(generic);
    errdefer work.residency.discard();
    return try work.builder.build(work.residency, generic);
}

fn updateVisibleComposition(
    work: *CanvasWork,
    desired: []const render_api.canvas.Composer.Placement,
    members: []const terminal_handoff.VisibleMember,
) !void {
    std.debug.assert(desired.len == members.len);
    if (work.pending_visible_revision) |revision| {
        if (placementsEqual(
            desired,
            work.pending_placements[0..work.pending_count],
        )) {
            switch (work.terminals.visibleSetStatus(revision)) {
                .pending => return,
                .stale => {
                    work.pending_visible_revision = null;
                    work.pending_count = 0;
                },
                .ready => {
                    return;
                },
            }
        }
    }
    if (placementsEqual(desired, work.visible_placements[0..work.visible_count]))
        return;
    const revision = work.next_visible_revision;
    work.next_visible_revision = std.math.add(u64, revision, 1) catch
        return error.RevisionOverflow;
    try work.terminals.publishVisibleSet(revision, members);
    @memcpy(work.pending_placements[0..desired.len], desired);
    work.pending_count = @intCast(desired.len);
    work.pending_visible_revision = revision;
}

fn placementsEqual(
    left: []const render_api.canvas.Composer.Placement,
    right: []const render_api.canvas.Composer.Placement,
) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| if (!std.meta.eql(a, b)) return false;
    return true;
}

fn placementContainsSource(
    placements: []const render_api.canvas.Composer.Placement,
    source: render_api.canvas.SourceId,
) bool {
    for (placements) |placement| if (placement.source == source) return true;
    return false;
}

fn adaptCanvasFrame(
    frame: render_api.canvas.Composer.Frame,
    uploads: []vk_surface.Upload,
    removals: []vk_surface.Removal,
    commands: []vk_surface.FrameCommand,
) !vk_surface.Frame {
    if (frame.uploads.len > uploads.len or frame.removals.len > removals.len or frame.commands.len > commands.len) return error.Capacity;
    for (frame.uploads, 0..) |value, index| {
        const end = std.math.add(usize, value.pixel_offset, value.pixel_count) catch return error.ArithmeticOverflow;
        if (end > frame.pixels.len) return error.Capacity;
        uploads[index] = .{
            .resource = surfaceResource(value.resource),
            .kind = switch (value.format) {
                .alpha8 => .alpha_mask,
                .rgba8 => .rgba,
            },
            .width = value.size.width,
            .height = value.size.height,
            .stride = value.stride,
            .pixels = frame.pixels[value.pixel_offset..end],
        };
    }
    for (frame.removals, 0..) |value, index| removals[index] = .{ .resource = surfaceResource(value) };
    for (frame.commands, 0..) |value, index| commands[index] = switch (value) {
        .solid => |solid| .{ .solid = .{ .rect = surfaceRect(solid.rect), .clip = surfaceRect(solid.rect), .color = surfaceColor(solid.color) } },
        .alpha_mask => |mask| .{ .alpha_mask = .{
            .rect = surfaceRect(mask.destination),
            .clip = surfaceRect(mask.clip),
            .resource = surfaceResource(mask.resource.resource),
            .source = if (mask.resource.source) |source| .{ .x = source.x, .y = source.y, .width = source.width, .height = source.height } else null,
            .color = surfaceColor(mask.color),
        } },
        .rgba => |rgba| .{ .rgba = .{
            .rect = surfaceRect(rgba.destination),
            .clip = surfaceRect(rgba.clip),
            .resource = surfaceResource(rgba.resource.resource),
            .source = if (rgba.resource.source) |source| .{ .x = source.x, .y = source.y, .width = source.width, .height = source.height } else null,
        } },
    };
    return .{
        .revision = @backingInt(frame.revision),
        .uploads = uploads[0..frame.uploads.len],
        .removals = removals[0..frame.removals.len],
        .commands = commands[0..frame.commands.len],
    };
}

fn surfaceResource(value: render_api.canvas.FrameResourceRef) vk_surface.ResourceGeneration {
    return .{ .key = .{ .source = @backingInt(value.key.source), .local = @backingInt(value.key.resource) }, .generation = @backingInt(value.generation) };
}

fn canvasResource(value: vk_surface.ResourceGeneration) render_api.canvas.FrameResourceRef {
    return .{
        .key = .{
            .source = @fromBackingInt(@intCast(value.key.source)),
            .resource = @fromBackingInt(@intCast(value.key.local)),
        },
        .generation = @fromBackingInt(@intCast(value.generation)),
    };
}

fn surfaceRect(value: render_api.canvas.Rect) vk_surface.Rect {
    return .{ .x = value.x, .y = value.y, .width = value.width, .height = value.height };
}

fn surfaceColor(value: render_api.canvas.Color) [4]f32 {
    return .{ @as(f32, @floatFromInt(value.r)) / 255.0, @as(f32, @floatFromInt(value.g)) / 255.0, @as(f32, @floatFromInt(value.b)) / 255.0, @as(f32, @floatFromInt(value.a)) / 255.0 };
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

fn waitConfigure(boundary: *shared.Boundary) !shared.SurfaceConfig {
    var wakes: u8 = 0;
    while (wakes < 32) : (wakes += 1) {
        if (boundary.takeConfigure()) |value| return value;
        if (boundary.shouldStop()) return error.Stopping;
        try waitRenderWake(boundary);
    }
    return error.ConfigureTimeout;
}

fn waitWindowRing(boundary: *shared.Boundary, generation: u64) !void {
    const absolute = std.math.add(u64, try monotonicNow(), 2_000_000_000) catch
        return error.Clock;
    while (true) {
        if (boundary.isWindowRingReady(generation)) return;
        if (boundary.shouldStop()) return error.Stopping;
        if (!try waitRenderWakeUntil(boundary, absolute))
            return error.WindowRingTimeout;
    }
}

fn waitReleasePoints(boundary: *shared.Boundary, generation: u64, slots: *[shared.slot_count]Slot, drm_fd: i32) !void {
    if (generation == 0) return;
    var wakes: u8 = 0;
    while (wakes < 32) : (wakes += 1) {
        if (boundary.releaseFacts(generation)) |retired| {
            for (0..shared.slot_count) |index| {
                if ((retired.presented_mask & (@as(u8, 1) << @intCast(index))) != 0) {
                    try waitTimeline(drm_fd, slots[index].release_handle, retired.release_points[index]);
                }
            }
            // Window has made the generation ineligible for any later
            // presentation. Presented slots have completed their release
            // points; unpresented wrappers were never acquired by compositor.
            for (slots) |*slot| slot.external = false;
            return;
        }
        try waitRenderWake(boundary);
    }
    return error.ReleaseObservationTimeout;
}

fn waitWindowRingRetired(boundary: *shared.Boundary, generation: u64) !void {
    if (generation == 0) return;
    var wakes: u8 = 0;
    while (wakes < 32) : (wakes += 1) {
        if (boundary.takeWindowRingRetired(generation)) |_| return;
        try waitRenderWake(boundary);
    }
    return error.WindowRetirementTimeout;
}

fn waitRenderWake(boundary: *shared.Boundary) !void {
    var descriptor = c.pollfd{ .fd = boundary.renderFd(), .events = c.POLLIN, .revents = 0 };
    while (true) {
        const result = c.poll(&descriptor, 1, 2_000);
        if (result > 0) {
            try boundary.drainRenderWake();
            return;
        }
        if (result == 0) return error.WakeTimeout;
        if (std.c.errno(result) != .INTR) return error.Wake;
    }
}

fn waitRenderWakeUntil(boundary: *shared.Boundary, absolute: u64) !bool {
    var descriptor = c.pollfd{
        .fd = boundary.renderFd(),
        .events = c.POLLIN,
        .revents = 0,
    };
    while (true) {
        const now = try monotonicNow();
        if (now >= absolute) return false;
        const remaining = absolute - now;
        const milliseconds = std.math.divCeil(
            u64,
            remaining,
            std.time.ns_per_ms,
        ) catch return error.Clock;
        const timeout: i32 = @intCast(@min(
            milliseconds,
            @as(u64, std.math.maxInt(i32)),
        ));
        const result = c.poll(&descriptor, 1, timeout);
        if (result > 0) {
            try boundary.drainRenderWake();
            return true;
        }
        if (result == 0) return false;
        if (std.c.errno(result) != .INTR) return error.Wake;
    }
}

fn waitRenderWakeBlocking(
    boundary: *shared.Boundary,
    terminals: *terminal_handoff.Boundary,
) !bool {
    var descriptors = [_]c.pollfd{
        .{ .fd = boundary.renderFd(), .events = c.POLLIN, .revents = 0 },
        .{ .fd = terminals.rendererFd(), .events = c.POLLIN, .revents = 0 },
    };
    while (true) {
        const result = c.poll(&descriptors, descriptors.len, -1);
        if (result > 0) {
            if (descriptors[0].revents & c.POLLIN != 0)
                try boundary.drainRenderWake();
            const terminal_dirty = descriptors[1].revents & c.POLLIN != 0;
            if (terminal_dirty) try terminals.drainRendererWake();
            return terminal_dirty;
        }
        if (result < 0 and std.c.errno(result) == .INTR) continue;
        return error.Wake;
    }
}

fn drainInput(
    boundary: *shared.Boundary,
    actions: *input_actions.State,
    canvas_work: *CanvasWork,
    topology: *chrome_state.Topology,
    appearance: chrome_state.Appearance,
    primitives: *[256]render_api.chrome.Primitive,
    text: *[(chrome_state.max_tabs + chrome_state.max_panes_per_tab) * chrome_state.max_label_bytes]u8,
    graphics: *vk_surface.Context,
    device: vk.VkDevice,
    queue: vk.VkQueue,
    family: u32,
    command: vk.VkCommandBuffer,
    slots: *[shared.slot_count]Slot,
    generation: u64,
    dispatch: *const howl_vk.dispatch.ExternalImageDispatch,
    drm_fd: i32,
    acquire_handle: u32,
    next_acquire_point: *u64,
) !void {
    while (boundary.takeInput()) |event| {
        const candidate: ?chrome_state.Topology = switch (event) {
            .key => |key| switch (actions.key(key) catch continue) {
                .action => |action| input_actions.candidate(topology, action) catch continue,
                .consumed => null,
                .unmatched => unmatched: {
                    try canvas_work.terminals.publishKey(
                        topology.focusedPaneId(),
                        key,
                    );
                    break :unmatched null;
                },
            },
            .keyboard_leave => reset: {
                try canvas_work.terminals.publishFocus(
                    topology.focusedPaneId(),
                    .{ .focus = .out },
                );
                actions.clear();
                break :reset null;
            },
            .keyboard_reset => reset: {
                actions.clear();
                break :reset null;
            },
            .button => |button| input_actions.pointerCandidate(topology, appearance, button) catch continue,
            .keyboard_enter => enter: {
                try canvas_work.terminals.publishFocus(
                    topology.focusedPaneId(),
                    .{ .focus = .in },
                );
                break :enter null;
            },
            .axis, .pointer_enter, .pointer_leave => null,
        };
        if (candidate) |next| {
            try redrawChrome(
                boundary,
                topology,
                next,
                canvas_work,
                appearance,
                primitives,
                text,
                graphics,
                device,
                queue,
                family,
                command,
                slots,
                generation,
                dispatch,
                drm_fd,
                acquire_handle,
                next_acquire_point,
            );
        }
    }
}

const PreparedTerminalTopology = struct {
    composer: *render_api.canvas.Composer,
    lifecycle: terminal_handoff.Boundary.PreparedLifecycle,
    new_source: ?render_api.canvas.SourceId,
    committed: bool = false,

    fn commit(self: *PreparedTerminalTopology) error{Stopping}!void {
        try self.lifecycle.commit();
        self.committed = true;
    }

    fn deinit(self: *PreparedTerminalTopology) void {
        if (self.committed) return;
        self.lifecycle.deinit();
        if (self.new_source) |source|
            self.composer.removeSource(source) catch
                @panic("prepared terminal source rollback failed");
    }
};

fn prepareTerminalTopology(
    work: *CanvasWork,
    current: *const chrome_state.Topology,
    candidate: *const chrome_state.Topology,
) !PreparedTerminalTopology {
    var operations: [128]terminal_handoff.Lifecycle = undefined;
    var operation_count: usize = 0;
    var inputs: [2]terminal_handoff.TerminalInput = undefined;
    var input_count: usize = 0;
    var new_panes: usize = 0;
    var registration_pane: ?render_api.chrome.PaneId = null;
    for (0..candidate.tabCount()) |tab_index| {
        for (0..candidate.paneCount(tab_index)) |pane_index| {
            const pane = candidate.paneId(tab_index, pane_index) orelse
                return error.InvalidTopology;
            const rect = candidate.paneRect(pane) orelse
                return error.InvalidTopology;
            const grid = terminalGrid(rect);
            if (!topologyContains(current, pane)) {
                operations[operation_count] = .{ .create = .{
                    .pane = pane,
                    .cols = grid.cols,
                    .rows = grid.rows,
                } };
                operation_count += 1;
                new_panes += 1;
                registration_pane = pane;
            } else {
                const old_rect = current.paneRect(pane) orelse
                    return error.InvalidTopology;
                const old_grid = terminalGrid(old_rect);
                if (old_grid.cols != grid.cols or old_grid.rows != grid.rows) {
                    operations[operation_count] = .{ .resize = .{
                        .pane = pane,
                        .cols = grid.cols,
                        .rows = grid.rows,
                    } };
                    operation_count += 1;
                }
            }
        }
    }
    if (current.focusedPaneId() != candidate.focusedPaneId()) {
        // A closing focused owner is destroyed before copied input is
        // serviced, so it neither needs nor may receive a later focus-out.
        // Surviving owners still receive the exact focus transition.
        if (shouldPublishFocusOut(current, candidate)) {
            inputs[input_count] = .{ .focus = .{
                .pane = current.focusedPaneId(),
                .event = .{ .focus = .out },
            } };
            input_count += 1;
        }
        inputs[input_count] = .{ .focus = .{
            .pane = candidate.focusedPaneId(),
            .event = .{ .focus = .in },
        } };
        input_count += 1;
    }
    for (0..current.tabCount()) |tab_index| {
        for (0..current.paneCount(tab_index)) |pane_index| {
            const pane = current.paneId(tab_index, pane_index) orelse
                return error.InvalidTopology;
            if (!topologyContains(candidate, pane)) {
                operations[operation_count] = .{ .close = pane };
                operation_count += 1;
            }
        }
    }
    // Current Host actions admit at most one new terminal owner per redraw;
    // rejecting a wider candidate before any registration keeps slot/source
    // construction transactional without a second lifecycle pool.
    if (new_panes > 1) return error.TerminalCapacity;
    const source = if (registration_pane != null)
        try work.composer.registerSource()
    else
        null;
    errdefer if (source) |value|
        work.composer.removeSource(value) catch
            @panic("new terminal source rollback failed");
    const registration: ?terminal_handoff.Registration = if (source) |value|
        .{ .pane = registration_pane.?, .source = value }
    else
        null;
    const lifecycle = try work.terminals.prepareLifecycle(
        operations[0..operation_count],
        inputs[0..input_count],
        registration,
    );
    return .{
        .composer = work.composer,
        .lifecycle = lifecycle,
        .new_source = source,
    };
}

fn topologyContains(
    topology: *const chrome_state.Topology,
    pane: render_api.chrome.PaneId,
) bool {
    return topology.paneRect(pane) != null;
}

fn shouldPublishFocusOut(
    current: *const chrome_state.Topology,
    candidate: *const chrome_state.Topology,
) bool {
    return current.focusedPaneId() != candidate.focusedPaneId() and
        topologyContains(candidate, current.focusedPaneId());
}

test "focused close omits stale focus-out while surviving focus change retains it" {
    var current = try chrome_state.Topology.init(
        .{ .width = 320, .height = 240 },
        chrome_state.default_tab_bar_height,
    );
    const first = current.focusedPaneId();
    const second = try current.split(first, .horizontal);
    var surviving = current;
    try surviving.focusPane(first);
    try std.testing.expect(shouldPublishFocusOut(&current, &surviving));
    var closing = current;
    try closing.closePane(second);
    try std.testing.expect(!shouldPublishFocusOut(&current, &closing));
}

test "one complete terminal and Chrome resource set fits every runtime bank" {
    try std.testing.expect(
        terminal_retained_resource_limit <= 1024,
    );
    try std.testing.expect(
        terminal_retained_resource_limit + chrome_retained_resource_limit <=
            frame_resource_limit,
    );
}

fn terminalGrid(rect: render_api.chrome.Rect) struct { cols: u16, rows: u16 } {
    return .{
        .cols = @max(@as(u16, 1), rect.width / 8),
        .rows = @max(@as(u16, 1), rect.height / 16),
    };
}

fn redrawChrome(
    boundary: *shared.Boundary,
    topology: *chrome_state.Topology,
    candidate: chrome_state.Topology,
    canvas_work: *CanvasWork,
    appearance: chrome_state.Appearance,
    primitives: *[256]render_api.chrome.Primitive,
    text: *[(chrome_state.max_tabs + chrome_state.max_panes_per_tab) * chrome_state.max_label_bytes]u8,
    graphics: *vk_surface.Context,
    device: vk.VkDevice,
    queue: vk.VkQueue,
    family: u32,
    command: vk.VkCommandBuffer,
    slots: *[shared.slot_count]Slot,
    generation: u64,
    dispatch: *const howl_vk.dispatch.ExternalImageDispatch,
    drm_fd: i32,
    acquire_handle: u32,
    next_acquire_point: *u64,
) !void {
    const slot_index = try releasedSlot(boundary, generation, slots, drm_fd);
    if (!boundary.canPublishCompletion(generation))
        return error.CompletionUnavailable;
    try validateTerminalTopology(&candidate);
    const composer_plan = try buildCanvasPlan(canvas_work, &candidate, appearance, primitives, text);
    errdefer canvas_work.residency.discard();
    const slot = &slots[slot_index];
    const acquire_point = next_acquire_point.*;
    const following_acquire_point = std.math.add(u64, acquire_point, 1) catch return error.RevisionOverflow;
    const release_point = std.math.add(u64, slot.release_point, 1) catch return error.RevisionOverflow;
    var release_sync_fd: i32 = -1;
    if (c.drmSyncobjExportSyncFile(drm_fd, slot.release_handle, &release_sync_fd) != 0) return error.Syncobj;
    errdefer if (release_sync_fd >= 0) closeDescriptor(release_sync_fd);
    const release_wait = try importReleaseSemaphore(device, dispatch, &release_sync_fd);
    defer vk.vkDestroySemaphore(device, release_wait, null);
    try render(
        graphics,
        device,
        queue,
        family,
        command,
        slot,
        slot.clear_color,
        composer_plan,
        canvas_work.builder.alpha_pixels,
        canvas_work.builder.rgba_pixels,
        canvas_work.residency,
        release_wait,
        dispatch,
        drm_fd,
        acquire_handle,
        acquire_point,
    );
    // Terminal lifecycle admission is the final candidate step. Rendering has
    // completed, but no Window completion is published until every create,
    // resize, and close fact is accepted.
    var terminal_candidate = try prepareTerminalTopology(canvas_work, topology, &candidate);
    defer terminal_candidate.deinit();
    const completion = shared.Completion{
        .generation = generation,
        .revision = acquire_point,
        .slot = @intCast(slot_index),
        .acquire_point = acquire_point,
        .release_point = release_point,
    };
    var prepared_completion = try boundary.prepareCompletions(&.{completion});
    defer prepared_completion.deinit();
    try terminal_candidate.commit();
    topology.* = candidate;
    prepared_completion.commit();
    slot.release_point = release_point;
    next_acquire_point.* = following_acquire_point;
    std.debug.print("Render interactive chrome generation={d} revision={d} slot={d} release={d}\n", .{ generation, acquire_point, slot_index, release_point });
}

fn validateTerminalTopology(candidate: *const chrome_state.Topology) !void {
    for (0..candidate.tabCount()) |tab_index| {
        for (0..candidate.paneCount(tab_index)) |pane_index| {
            const pane = candidate.paneId(tab_index, pane_index) orelse
                return error.InvalidTopology;
            const rect = candidate.paneRect(pane) orelse
                return error.InvalidTopology;
            const grid = terminalGrid(rect);
            const cells = std.math.mul(usize, grid.cols, grid.rows) catch
                return error.TerminalCapacity;
            if (cells > 32_768) return error.TerminalCapacity;
        }
    }
}

fn releasedSlot(
    boundary: *shared.Boundary,
    generation: u64,
    slots: *[shared.slot_count]Slot,
    drm_fd: i32,
) !usize {
    const facts = boundary.releaseFacts(generation) orelse return error.NoReleasedSlot;
    var first_candidate: ?usize = null;
    for (0..shared.slot_count) |index| {
        const presented = (facts.presented_mask & (@as(u8, 1) << @intCast(index))) != 0;
        if (!presented or facts.release_points[index] != slots[index].release_point) continue;
        if (first_candidate == null) first_candidate = index;
        if (try timelineReady(drm_fd, slots[index].release_handle, slots[index].release_point)) return index;
    }
    const index = first_candidate orelse return error.NoReleasedSlot;
    try waitTimeline(drm_fd, slots[index].release_handle, slots[index].release_point);
    return index;
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
    info.usage = vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT;
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

fn constructSlot(slot: *Slot, graphics: *const vk_surface.Context, device: vk.VkDevice, memory_properties: vk.VkPhysicalDeviceMemoryProperties, modifier: u64, dedicated_only: bool, plane_count: u8, surface: shared.SurfaceConfig, dispatch: *const howl_vk.dispatch.ExternalImageDispatch, drm_fd: i32, offer: *shared.SlotOffer, offered_fds: *OfferedFds, gpu_bytes: *u64) !void {
    slot.width = surface.width;
    slot.height = surface.height;
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
    info.extent = .{ .width = surface.width, .height = surface.height, .depth = 1 };
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
    const owned_bytes = requirements.size;
    const total_bytes = std.math.add(u64, gpu_bytes.*, owned_bytes) catch return error.GpuMemoryLimit;
    if (total_bytes > gpu_memory_limit) return error.GpuMemoryLimit;
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
    slot.attachment = try graphics.createAttachment(device, slot.image, surface.width, surface.height);
    slot.owned_bytes = owned_bytes;
    gpu_bytes.* += owned_bytes;
    var actual = std.mem.zeroes(vk.VkImageDrmFormatModifierPropertiesEXT);
    actual.sType = vk.VK_STRUCTURE_TYPE_IMAGE_DRM_FORMAT_MODIFIER_PROPERTIES_EXT;
    if (dispatch.get_modifier(device, slot.image, &actual) != vk.VK_SUCCESS or actual.drmFormatModifier != modifier) return error.Modifier;
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
    if (dispatch.get_memory_fd(device, &fd_info, &offered_fds.dma) != vk.VK_SUCCESS or offered_fds.dma < 0) return error.DmaBuf;
    if (c.drmSyncobjCreate(drm_fd, 0, &slot.release_handle) != 0) return error.Syncobj;
    if (c.drmSyncobjHandleToFD(drm_fd, slot.release_handle, &offered_fds.timeline) != 0) return error.Syncobj;
    offer.* = .{ .generation = surface.generation, .width = surface.width, .height = surface.height, .dma_fd = offered_fds.dma, .acquire_timeline_fd = -1, .release_timeline_fd = offered_fds.timeline, .plane_count = plane_count, .planes = slot.planes };
}

fn render(graphics: *vk_surface.Context, device: vk.VkDevice, queue: vk.VkQueue, family: u32, command: vk.VkCommandBuffer, slot: *Slot, color: [4]f32, surface_plan: vk_surface.Plan, alpha_pixels: []const u8, rgba_pixels: []const u8, residency_commit: *vk_surface.ResidencyStore, wait_semaphore: ?vk.VkSemaphore, dispatch: *const howl_vk.dispatch.ExternalImageDispatch, drm_fd: i32, acquire_handle: u32, acquire_point: u64) !void {
    errdefer residency_commit.discard();
    try graphics.stage(surface_plan, alpha_pixels, rgba_pixels, slot.width, slot.height);
    if (vk.vkResetCommandBuffer(command, 0) != vk.VK_SUCCESS) return error.Command;
    var begin = std.mem.zeroes(vk.VkCommandBufferBeginInfo);
    begin.sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    if (vk.vkBeginCommandBuffer(command, &begin) != vk.VK_SUCCESS) return error.Command;
    const range = vk.VkImageSubresourceRange{ .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, .baseMipLevel = 0, .levelCount = 1, .baseArrayLayer = 0, .layerCount = 1 };
    var barrier = vk.VkImageMemoryBarrier{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .pNext = null,
        .srcAccessMask = 0,
        .dstAccessMask = vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        .oldLayout = if (slot.external) vk.VK_IMAGE_LAYOUT_GENERAL else vk.VK_IMAGE_LAYOUT_UNDEFINED,
        .newLayout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .srcQueueFamilyIndex = if (slot.external) vk.VK_QUEUE_FAMILY_EXTERNAL else vk.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = if (slot.external) family else vk.VK_QUEUE_FAMILY_IGNORED,
        .image = slot.image,
        .subresourceRange = range,
    };
    vk.vkCmdPipelineBarrier(command, vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, 0, 0, null, 0, null, 1, &barrier);
    const recording = try graphics.record(command, slot.attachment, slot.width, slot.height, surface_plan, color);
    barrier.srcAccessMask = vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
    barrier.dstAccessMask = 0;
    barrier.oldLayout = vk.VK_IMAGE_LAYOUT_GENERAL;
    barrier.newLayout = vk.VK_IMAGE_LAYOUT_GENERAL;
    barrier.srcQueueFamilyIndex = family;
    barrier.dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_EXTERNAL;
    vk.vkCmdPipelineBarrier(command, vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, vk.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0, 0, null, 0, null, 1, &barrier);
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
    if (dispatch.get_semaphore_fd(device, &fd_info, &sync_fd) != vk.VK_SUCCESS or sync_fd < 0) return error.Semaphore;
    defer closeDescriptor(sync_fd);
    var temporary: u32 = 0;
    if (c.drmSyncobjCreate(drm_fd, 0, &temporary) != 0) return error.Syncobj;
    defer destroySyncobj(drm_fd, temporary);
    if (c.drmSyncobjImportSyncFile(drm_fd, temporary, sync_fd) != 0) return error.Syncobj;
    var handles = [_]u32{temporary};
    if (c.drmSyncobjWait(drm_fd, &handles, 1, try deadline(), 0, null) != 0) return error.RenderTimeout;
    graphics.complete(recording);
    try residency_commit.complete();
    if (c.drmSyncobjTransfer(drm_fd, acquire_handle, acquire_point, temporary, 0, 0) != 0) return error.Syncobj;
    try waitTimeline(drm_fd, acquire_handle, acquire_point);
    slot.external = true;
    slot.clear_color = color;
}

fn waitTimeline(drm_fd: i32, handle: u32, point: u64) !void {
    var handles = [_]u32{handle};
    var points = [_]u64{point};
    const flags = c.DRM_SYNCOBJ_WAIT_FLAGS_WAIT_FOR_SUBMIT | c.DRM_SYNCOBJ_WAIT_FLAGS_WAIT_AVAILABLE;
    if (c.drmSyncobjTimelineWait(drm_fd, &handles, &points, 1, try deadline(), flags, null) != 0) return error.ReleaseAvailability;
    if (c.drmSyncobjTimelineWait(drm_fd, &handles, &points, 1, try deadline(), 0, null) != 0) return error.ReleaseCompletion;
}

fn timelineReady(drm_fd: i32, handle: u32, point: u64) !bool {
    var handles = [_]u32{handle};
    var points = [_]u64{point};
    const timeout = std.math.cast(i64, try monotonicNow()) orelse return error.Clock;
    const flags = c.DRM_SYNCOBJ_WAIT_FLAGS_WAIT_FOR_SUBMIT | c.DRM_SYNCOBJ_WAIT_FLAGS_WAIT_AVAILABLE;
    const available = c.drmSyncobjTimelineWait(drm_fd, &handles, &points, 1, timeout, flags, null);
    if (available == -c.ETIME) return false;
    if (available != 0) return error.ReleaseAvailability;
    const complete = c.drmSyncobjTimelineWait(drm_fd, &handles, &points, 1, timeout, 0, null);
    if (complete == -c.ETIME) return false;
    if (complete != 0) return error.ReleaseCompletion;
    return true;
}

fn importReleaseSemaphore(device: vk.VkDevice, dispatch: *const howl_vk.dispatch.ExternalImageDispatch, sync_fd: *i32) !vk.VkSemaphore {
    var export_info = std.mem.zeroes(vk.VkExportSemaphoreCreateInfo);
    export_info.sType = vk.VK_STRUCTURE_TYPE_EXPORT_SEMAPHORE_CREATE_INFO;
    export_info.handleTypes = vk.VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_SYNC_FD_BIT;
    var create_info = std.mem.zeroes(vk.VkSemaphoreCreateInfo);
    create_info.sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
    create_info.pNext = @ptrCast(&export_info);
    var semaphore: vk.VkSemaphore = undefined;
    if (vk.vkCreateSemaphore(device, &create_info, null, &semaphore) != vk.VK_SUCCESS) return error.Semaphore;
    errdefer vk.vkDestroySemaphore(device, semaphore, null);
    var import_info = std.mem.zeroes(vk.VkImportSemaphoreFdInfoKHR);
    import_info.sType = vk.VK_STRUCTURE_TYPE_IMPORT_SEMAPHORE_FD_INFO_KHR;
    import_info.semaphore = semaphore;
    import_info.handleType = vk.VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_SYNC_FD_BIT;
    import_info.fd = sync_fd.*;
    if (dispatch.import_semaphore_fd(device, &import_info) != vk.VK_SUCCESS) return error.Semaphore;
    sync_fd.* = -1;
    return semaphore;
}

fn deadline() !i64 {
    return @intCast(try std.math.add(u64, try monotonicNow(), 2_000_000_000));
}

fn monotonicNow() !u64 {
    var now: c.timespec = undefined;
    if (c.clock_gettime(c.CLOCK_MONOTONIC, &now) != 0) return error.Clock;
    const seconds = try std.math.mul(u64, @intCast(now.tv_sec), 1_000_000_000);
    return try std.math.add(u64, seconds, @intCast(now.tv_nsec));
}

fn closeDescriptor(descriptor: i32) void {
    if (c.close(descriptor) != 0) @panic("Render descriptor cleanup failed");
}

fn destroySyncobj(drm_fd: i32, handle: u32) void {
    if (c.drmSyncobjDestroy(drm_fd, handle) != 0) @panic("Render syncobj cleanup failed");
}
