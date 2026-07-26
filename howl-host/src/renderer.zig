//! Exclusively owns Vulkan mutation and DRM release observation.

const std = @import("std");
const c = @import("renderer_c");
const shared = @import("shared.zig");
const vk = @import("vulkan");

const SlotStage = enum { empty, image, memory, offered, live };

const Slot = struct {
    stage: SlotStage = .empty,
    image: vk.VkImage = null,
    memory: vk.VkDeviceMemory = null,
    release_handle: u32 = 0,
    plane_count: u8 = 0,
    planes: [shared.plane_limit]shared.Plane = undefined,
    external: bool = false,

    fn deinit(self: *Slot, device: vk.VkDevice, drm_fd: i32) void {
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

pub fn run(boundary: *shared.Boundary) void {
    runFallible(boundary) catch |failure| {
        std.debug.print("Render failure: {s}\n", .{@errorName(failure)});
        boundary.requestStop(.render);
    };
    boundary.markStopped(.render);
}

fn runFallible(boundary: *shared.Boundary) !void {
    const feedback = try waitFeedback(boundary);
    if (feedback.device == 0 or feedback.fourcc != 0x34324241) return error.UnsupportedFeedback;

    var application = std.mem.zeroes(vk.VkApplicationInfo);
    application.sType = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO;
    application.pApplicationName = "howl-host";
    application.applicationVersion = vk.VK_MAKE_VERSION(0, 1, 4);
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
        try constructSlot(slot, device, memory_properties, feedback.modifier, dedicated_only, plane_count, get_memory_fd.?, get_modifier.?, drm_fd, &offers[index], &offered_fds[index]);
        if (c.drmSyncobjHandleToFD(drm_fd, acquire_handle, &offered_fds[index].acquire) != 0) return error.Syncobj;
        offers[index].acquire_timeline_fd = offered_fds[index].acquire;
    }
    try boundary.publishOffers(offers);
    for (&offered_fds) |*fds| fds.* = .{};
    try waitWindowRing(boundary);
    for (&slots) |*slot| slot.stage = .live;

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
    for (&slots, 0..) |*slot, index| {
        queue_active = true;
        try render(device, queue, family, command, slot, colors[index], null, get_semaphore_fd.?, drm_fd, acquire_handle, index + 1);
        try boundary.publishCompletion(.{ .revision = index + 1, .slot = @intCast(index), .acquire_point = index + 1, .release_point = 1 });
    }
    try waitTimeline(drm_fd, slots[0].release_handle, 1);
    const reuse_wait = try importRelease(device, drm_fd, slots[0].release_handle, 1, import_semaphore_fd.?);
    defer vk.vkDestroySemaphore(device, reuse_wait, null);
    try render(device, queue, family, command, &slots[0], .{ 0.72, 0.16, 0.08, 1 }, reuse_wait, get_semaphore_fd.?, drm_fd, acquire_handle, 4);
    try boundary.publishCompletion(.{ .revision = 4, .slot = 0, .acquire_point = 4, .release_point = 2 });
    try waitTimeline(drm_fd, slots[0].release_handle, 2);
    try waitTimeline(drm_fd, slots[1].release_handle, 1);
    try waitTimeline(drm_fd, slots[2].release_handle, 1);
    if (vk.vkDeviceWaitIdle(device) != vk.VK_SUCCESS) return error.DeviceIdle;
    queue_active = false;
    try waitWindowStopped(boundary);
    std.debug.print("Render ring complete revisions=4 slots=3\n", .{});
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

fn constructSlot(slot: *Slot, device: vk.VkDevice, memory_properties: vk.VkPhysicalDeviceMemoryProperties, modifier: u64, dedicated_only: bool, plane_count: u8, get_memory_fd: vk.PFN_vkGetMemoryFdKHR, get_modifier: vk.PFN_vkGetImageDrmFormatModifierPropertiesEXT, drm_fd: i32, offer: *shared.SlotOffer, offered_fds: *OfferedFds) !void {
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
    info.extent = .{ .width = 64, .height = 64, .depth = 1 };
    info.mipLevels = 1;
    info.arrayLayers = 1;
    info.samples = vk.VK_SAMPLE_COUNT_1_BIT;
    info.tiling = vk.VK_IMAGE_TILING_DRM_FORMAT_MODIFIER_EXT;
    info.usage = vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    info.sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE;
    info.initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED;
    if (vk.vkCreateImage(device, &info, null, &slot.image) != vk.VK_SUCCESS) return error.Image;
    slot.stage = .image;
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
    slot.stage = .memory;
    if (vk.vkBindImageMemory(device, slot.image, slot.memory, 0) != vk.VK_SUCCESS) return error.Memory;
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
    offer.* = .{ .dma_fd = offered_fds.dma, .acquire_timeline_fd = -1, .release_timeline_fd = offered_fds.timeline, .plane_count = plane_count, .planes = slot.planes };
    slot.stage = .offered;
}

fn render(device: vk.VkDevice, queue: vk.VkQueue, family: u32, command: vk.VkCommandBuffer, slot: *Slot, color: [4]f32, wait_semaphore: ?vk.VkSemaphore, get_semaphore_fd: vk.PFN_vkGetSemaphoreFdKHR, drm_fd: i32, acquire_handle: u32, acquire_point: u64) !void {
    if (vk.vkResetCommandBuffer(command, 0) != vk.VK_SUCCESS) return error.Command;
    var begin = std.mem.zeroes(vk.VkCommandBufferBeginInfo);
    begin.sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    if (vk.vkBeginCommandBuffer(command, &begin) != vk.VK_SUCCESS) return error.Command;
    const range = vk.VkImageSubresourceRange{ .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, .baseMipLevel = 0, .levelCount = 1, .baseArrayLayer = 0, .layerCount = 1 };
    var barrier = vk.VkImageMemoryBarrier{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .pNext = null,
        .srcAccessMask = 0,
        .dstAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT,
        .oldLayout = if (slot.external) vk.VK_IMAGE_LAYOUT_GENERAL else vk.VK_IMAGE_LAYOUT_UNDEFINED,
        .newLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        .srcQueueFamilyIndex = if (slot.external) vk.VK_QUEUE_FAMILY_EXTERNAL else vk.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = if (slot.external) family else vk.VK_QUEUE_FAMILY_IGNORED,
        .image = slot.image,
        .subresourceRange = range,
    };
    vk.vkCmdPipelineBarrier(command, vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, vk.VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, null, 0, null, 1, &barrier);
    var clear = std.mem.zeroes(vk.VkClearColorValue);
    clear.float32 = color;
    vk.vkCmdClearColorImage(command, slot.image, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &clear, 1, &range);
    barrier.srcAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT;
    barrier.dstAccessMask = 0;
    barrier.oldLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    barrier.newLayout = vk.VK_IMAGE_LAYOUT_GENERAL;
    barrier.srcQueueFamilyIndex = family;
    barrier.dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_EXTERNAL;
    vk.vkCmdPipelineBarrier(command, vk.VK_PIPELINE_STAGE_TRANSFER_BIT, vk.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0, 0, null, 0, null, 1, &barrier);
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
    const wait_stage: vk.VkPipelineStageFlags = vk.VK_PIPELINE_STAGE_TRANSFER_BIT;
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
    import_info.flags = vk.VK_SEMAPHORE_IMPORT_TEMPORARY_BIT;
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
