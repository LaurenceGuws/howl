//! Owns bounded Vulkan chrome pipelines, shared alpha atlas, and mapped
//! vertex/index/upload staging. It owns no Wayland or presentation facts.

const std = @import("std");
const howl_vk = @import("howl_vk");
const vk = howl_vk.abi;
const draw = @import("chrome_draw");

const vertex_shader align(4) = @embedFile("shaders/chrome.vert.spv").*;
const solid_shader align(4) = @embedFile("shaders/solid.frag.spv").*;
const text_shader align(4) = @embedFile("shaders/text.frag.spv").*;

const vertex_bytes = @sizeOf(draw.Vertex) * draw.max_vertices;
const index_bytes = @sizeOf(u16) * draw.max_indices;
const index_offset = std.mem.alignForward(usize, vertex_bytes, @alignOf(u16));
const atlas_offset = std.mem.alignForward(usize, index_offset + index_bytes, 4);
const staging_bytes = atlas_offset + draw.atlas_bytes;

/// Names exact Vulkan resource, memory, and mapped-staging failures.
pub const Error = error{
    GpuMemoryLimit,
    MemoryType,
    Buffer,
    Image,
    ImageView,
    Shader,
    RenderPass,
    Descriptor,
    Pipeline,
    Framebuffer,
    StagingMap,
};

/// Owns one exported slot's image view and compatible framebuffer.
pub const Attachment = struct {
    view: vk.VkImageView = null,
    framebuffer: vk.VkFramebuffer = null,

    /// Destroys framebuffer then image view before the underlying slot image.
    pub fn deinit(self: *Attachment, device: vk.VkDevice) void {
        if (self.framebuffer != null) vk.vkDestroyFramebuffer(device, self.framebuffer, null);
        if (self.view != null) vk.vkDestroyImageView(device, self.view, null);
        self.* = .{};
    }
};

/// Owns the shared Vulkan render pass, two pipelines, R8 atlas, descriptors,
/// and one bounded mapped vertex/index/upload buffer.
pub const Context = struct {
    render_pass: vk.VkRenderPass = null,
    layout: vk.VkPipelineLayout = null,
    descriptor_layout: vk.VkDescriptorSetLayout = null,
    descriptor_pool: vk.VkDescriptorPool = null,
    descriptor: vk.VkDescriptorSet = null,
    sampler: vk.VkSampler = null,
    solid_pipeline: vk.VkPipeline = null,
    text_pipeline: vk.VkPipeline = null,
    atlas_image: vk.VkImage = null,
    atlas_memory: vk.VkDeviceMemory = null,
    atlas_view: vk.VkImageView = null,
    staging_buffer: vk.VkBuffer = null,
    staging_memory: vk.VkDeviceMemory = null,
    mapped: ?[*]u8 = null,
    owned_bytes: u64 = 0,
    atlas_initialized: bool = false,

    /// Transactionally creates shared GPU owners and charges exact Vulkan
    /// allocation requirements against `gpu_bytes` and `limit`.
    pub fn init(device: vk.VkDevice, memory: vk.VkPhysicalDeviceMemoryProperties, gpu_bytes: *u64, limit: u64) Error!Context {
        var result = Context{};
        errdefer result.deinit(device, gpu_bytes);
        try result.createRenderPass(device);
        try result.createDescriptors(device);
        try result.createAtlas(device, memory, gpu_bytes, limit);
        try result.createStaging(device, memory, gpu_bytes, limit);
        try result.createPipelines(device);
        return result;
    }

    /// Destroys all shared resources in reverse order and removes their exact
    /// charged allocation bytes.
    pub fn deinit(self: *Context, device: vk.VkDevice, gpu_bytes: *u64) void {
        if (self.mapped != null and self.staging_memory != null) vk.vkUnmapMemory(device, self.staging_memory);
        if (self.staging_buffer != null) vk.vkDestroyBuffer(device, self.staging_buffer, null);
        if (self.staging_memory != null) vk.vkFreeMemory(device, self.staging_memory, null);
        if (self.text_pipeline != null) vk.vkDestroyPipeline(device, self.text_pipeline, null);
        if (self.solid_pipeline != null) vk.vkDestroyPipeline(device, self.solid_pipeline, null);
        if (self.layout != null) vk.vkDestroyPipelineLayout(device, self.layout, null);
        if (self.descriptor_pool != null) vk.vkDestroyDescriptorPool(device, self.descriptor_pool, null);
        if (self.sampler != null) vk.vkDestroySampler(device, self.sampler, null);
        if (self.atlas_view != null) vk.vkDestroyImageView(device, self.atlas_view, null);
        if (self.atlas_image != null) vk.vkDestroyImage(device, self.atlas_image, null);
        if (self.atlas_memory != null) vk.vkFreeMemory(device, self.atlas_memory, null);
        if (self.descriptor_layout != null) vk.vkDestroyDescriptorSetLayout(device, self.descriptor_layout, null);
        if (self.render_pass != null) vk.vkDestroyRenderPass(device, self.render_pass, null);
        gpu_bytes.* -= self.owned_bytes;
        self.* = .{};
    }

    /// Creates one framebuffer owner for a live exported image; failure leaves
    /// no view or framebuffer alive.
    pub fn createAttachment(self: *const Context, device: vk.VkDevice, image: vk.VkImage, width: u32, height: u32) Error!Attachment {
        var result = Attachment{};
        errdefer result.deinit(device);
        var view_info = vk.VkImageViewCreateInfo{
            .image = image,
            .format = vk.VK_FORMAT_R8G8B8A8_UNORM,
            .subresourceRange = .{ .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, .baseMipLevel = 0, .levelCount = 1, .baseArrayLayer = 0, .layerCount = 1 },
        };
        if (vk.vkCreateImageView(device, &view_info, null, &result.view) != vk.VK_SUCCESS) return error.ImageView;
        var framebuffer_info = vk.VkFramebufferCreateInfo{
            .renderPass = self.render_pass,
            .attachmentCount = 1,
            .pAttachments = &result.view,
            .width = width,
            .height = height,
            .layers = 1,
        };
        if (vk.vkCreateFramebuffer(device, &framebuffer_info, null, &result.framebuffer) != vk.VK_SUCCESS) return error.Framebuffer;
        return result;
    }

    /// Copies accepted plan prefixes and, when required, the complete atlas
    /// into persistently mapped bounded storage.
    pub fn stage(self: *Context, plan: draw.Plan, atlas_pixels: []const u8) Error!void {
        const mapped = self.mapped orelse return error.StagingMap;
        const vertices = std.mem.sliceAsBytes(plan.vertices);
        const indices = std.mem.sliceAsBytes(plan.indices);
        if (vertices.len > vertex_bytes or indices.len > index_bytes or atlas_pixels.len != draw.atlas_bytes) return error.Buffer;
        @memcpy(mapped[0..vertices.len], vertices);
        @memcpy(mapped[index_offset .. index_offset + indices.len], indices);
        if (plan.atlas_changed or !self.atlas_initialized)
            @memcpy(mapped[atlas_offset .. atlas_offset + atlas_pixels.len], atlas_pixels);
    }

    /// Records atlas upload barriers, an exact clear, ordered clipped draws,
    /// and no submission or presentation policy.
    pub fn record(self: *Context, command: vk.VkCommandBuffer, attachment: Attachment, width: u32, height: u32, plan: draw.Plan, clear: [4]f32) void {
        if (plan.atlas_changed or !self.atlas_initialized) {
            const atlas_range = vk.VkImageSubresourceRange{ .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, .baseMipLevel = 0, .levelCount = 1, .baseArrayLayer = 0, .layerCount = 1 };
            var atlas_barrier = vk.VkImageMemoryBarrier{
                .sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
                .oldLayout = if (self.atlas_initialized) vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL else vk.VK_IMAGE_LAYOUT_UNDEFINED,
                .newLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
                .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
                .image = self.atlas_image,
                .subresourceRange = atlas_range,
                .srcAccessMask = if (self.atlas_initialized) vk.VK_ACCESS_SHADER_READ_BIT else 0,
                .dstAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT,
            };
            vk.vkCmdPipelineBarrier(command, if (self.atlas_initialized) vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT else vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, vk.VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, null, 0, null, 1, &atlas_barrier);
            var copy = vk.VkBufferImageCopy{
                .bufferOffset = atlas_offset,
                .bufferRowLength = draw.atlas_extent,
                .bufferImageHeight = draw.atlas_extent,
                .imageSubresource = .{ .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, .mipLevel = 0, .baseArrayLayer = 0, .layerCount = 1 },
                .imageOffset = .{},
                .imageExtent = .{ .width = draw.atlas_extent, .height = draw.atlas_extent, .depth = 1 },
            };
            vk.vkCmdCopyBufferToImage(command, self.staging_buffer, self.atlas_image, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &copy);
            atlas_barrier.srcAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT;
            atlas_barrier.dstAccessMask = vk.VK_ACCESS_SHADER_READ_BIT;
            atlas_barrier.oldLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
            atlas_barrier.newLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
            vk.vkCmdPipelineBarrier(command, vk.VK_PIPELINE_STAGE_TRANSFER_BIT, vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, null, 0, null, 1, &atlas_barrier);
            self.atlas_initialized = true;
        }
        const clear_value = vk.VkClearValue{ .color = .{ .float32 = clear } };
        var begin = vk.VkRenderPassBeginInfo{
            .renderPass = self.render_pass,
            .framebuffer = attachment.framebuffer,
            .renderArea = .{ .extent = .{ .width = width, .height = height } },
            .clearValueCount = 1,
            .pClearValues = &clear_value,
        };
        vk.vkCmdBeginRenderPass(command, &begin, vk.VK_SUBPASS_CONTENTS_INLINE);
        var viewport = vk.VkViewport{ .width = @floatFromInt(width), .height = @floatFromInt(height) };
        vk.vkCmdSetViewport(command, 0, 1, &viewport);
        var buffers = [_]vk.VkBuffer{self.staging_buffer};
        var offsets = [_]vk.VkDeviceSize{0};
        vk.vkCmdBindVertexBuffers(command, 0, 1, &buffers, &offsets);
        vk.vkCmdBindIndexBuffer(command, self.staging_buffer, index_offset, vk.VK_INDEX_TYPE_UINT16);
        var bound: ?draw.Kind = null;
        for (plan.commands) |item| {
            if (bound == null or bound.? != item.kind) {
                vk.vkCmdBindPipeline(command, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, if (item.kind == .solid) self.solid_pipeline else self.text_pipeline);
                if (item.kind == .text) vk.vkCmdBindDescriptorSets(command, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.layout, 0, 1, &self.descriptor, 0, null);
                bound = item.kind;
            }
            var scissor = vk.VkRect2D{
                .offset = .{ .x = item.clip.x, .y = item.clip.y },
                .extent = .{ .width = item.clip.width, .height = item.clip.height },
            };
            vk.vkCmdSetScissor(command, 0, 1, &scissor);
            vk.vkCmdDrawIndexed(command, item.index_count, 1, item.first_index, 0, 0);
        }
        vk.vkCmdEndRenderPass(command);
    }

    fn createRenderPass(self: *Context, device: vk.VkDevice) Error!void {
        const attachment = vk.VkAttachmentDescription{
            .format = vk.VK_FORMAT_R8G8B8A8_UNORM,
            .initialLayout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            .finalLayout = vk.VK_IMAGE_LAYOUT_GENERAL,
        };
        const reference = vk.VkAttachmentReference{};
        const subpass = vk.VkSubpassDescription{ .colorAttachmentCount = 1, .pColorAttachments = &reference };
        const dependency = vk.VkSubpassDependency{
            .srcSubpass = vk.VK_SUBPASS_EXTERNAL,
            .dstSubpass = 0,
            .srcStageMask = vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
            .dstStageMask = vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .dstAccessMask = vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        };
        var info = vk.VkRenderPassCreateInfo{ .attachmentCount = 1, .pAttachments = &attachment, .subpassCount = 1, .pSubpasses = &subpass, .dependencyCount = 1, .pDependencies = &dependency };
        if (vk.vkCreateRenderPass(device, &info, null, &self.render_pass) != vk.VK_SUCCESS) return error.RenderPass;
    }

    fn createDescriptors(self: *Context, device: vk.VkDevice) Error!void {
        const binding = vk.VkDescriptorSetLayoutBinding{ .descriptorCount = 1, .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT };
        var layout_info = vk.VkDescriptorSetLayoutCreateInfo{ .bindingCount = 1, .pBindings = &binding };
        if (vk.vkCreateDescriptorSetLayout(device, &layout_info, null, &self.descriptor_layout) != vk.VK_SUCCESS) return error.Descriptor;
        var pipeline_layout = vk.VkPipelineLayoutCreateInfo{ .setLayoutCount = 1, .pSetLayouts = &self.descriptor_layout };
        if (vk.vkCreatePipelineLayout(device, &pipeline_layout, null, &self.layout) != vk.VK_SUCCESS) return error.Pipeline;
        const pool_size = vk.VkDescriptorPoolSize{ .type = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount = 1 };
        var pool_info = vk.VkDescriptorPoolCreateInfo{ .maxSets = 1, .poolSizeCount = 1, .pPoolSizes = &pool_size };
        if (vk.vkCreateDescriptorPool(device, &pool_info, null, &self.descriptor_pool) != vk.VK_SUCCESS) return error.Descriptor;
        var allocate = vk.VkDescriptorSetAllocateInfo{ .descriptorPool = self.descriptor_pool, .descriptorSetCount = 1, .pSetLayouts = &self.descriptor_layout };
        if (vk.vkAllocateDescriptorSets(device, &allocate, &self.descriptor) != vk.VK_SUCCESS) return error.Descriptor;
        var sampler_info = vk.VkSamplerCreateInfo{};
        if (vk.vkCreateSampler(device, &sampler_info, null, &self.sampler) != vk.VK_SUCCESS) return error.Descriptor;
    }

    fn createAtlas(self: *Context, device: vk.VkDevice, memory: vk.VkPhysicalDeviceMemoryProperties, gpu_bytes: *u64, limit: u64) Error!void {
        var info = vk.VkImageCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .imageType = vk.VK_IMAGE_TYPE_2D,
            .format = vk.VK_FORMAT_R8_UNORM,
            .extent = .{ .width = draw.atlas_extent, .height = draw.atlas_extent, .depth = 1 },
            .mipLevels = 1,
            .arrayLayers = 1,
            .samples = vk.VK_SAMPLE_COUNT_1_BIT,
            .tiling = 0,
            .usage = vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.VK_IMAGE_USAGE_SAMPLED_BIT,
            .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
            .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
        };
        if (vk.vkCreateImage(device, &info, null, &self.atlas_image) != vk.VK_SUCCESS) return error.Image;
        var requirements: vk.VkMemoryRequirements = undefined;
        vk.vkGetImageMemoryRequirements(device, self.atlas_image, &requirements);
        try charge(self, gpu_bytes, requirements.size, limit);
        var allocation = vk.VkMemoryAllocateInfo{ .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = requirements.size, .memoryTypeIndex = try memoryType(memory, requirements.memoryTypeBits, vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) };
        if (vk.vkAllocateMemory(device, &allocation, null, &self.atlas_memory) != vk.VK_SUCCESS) return error.Image;
        if (vk.vkBindImageMemory(device, self.atlas_image, self.atlas_memory, 0) != vk.VK_SUCCESS) return error.Image;
        var view_info = vk.VkImageViewCreateInfo{
            .image = self.atlas_image,
            .format = vk.VK_FORMAT_R8_UNORM,
            .subresourceRange = .{ .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, .baseMipLevel = 0, .levelCount = 1, .baseArrayLayer = 0, .layerCount = 1 },
        };
        if (vk.vkCreateImageView(device, &view_info, null, &self.atlas_view) != vk.VK_SUCCESS) return error.ImageView;
        const image_info = vk.VkDescriptorImageInfo{ .sampler = self.sampler, .imageView = self.atlas_view };
        var write = vk.VkWriteDescriptorSet{ .dstSet = self.descriptor, .descriptorCount = 1, .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .pImageInfo = &image_info };
        vk.vkUpdateDescriptorSets(device, 1, &write, 0, null);
    }

    fn createStaging(self: *Context, device: vk.VkDevice, memory: vk.VkPhysicalDeviceMemoryProperties, gpu_bytes: *u64, limit: u64) Error!void {
        var info = vk.VkBufferCreateInfo{ .sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, .size = staging_bytes, .usage = vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT | vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | vk.VK_BUFFER_USAGE_INDEX_BUFFER_BIT, .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE };
        if (vk.vkCreateBuffer(device, &info, null, &self.staging_buffer) != vk.VK_SUCCESS) return error.Buffer;
        var requirements: vk.VkMemoryRequirements = undefined;
        vk.vkGetBufferMemoryRequirements(device, self.staging_buffer, &requirements);
        try charge(self, gpu_bytes, requirements.size, limit);
        var allocation = vk.VkMemoryAllocateInfo{ .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = requirements.size, .memoryTypeIndex = try memoryType(memory, requirements.memoryTypeBits, vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) };
        if (vk.vkAllocateMemory(device, &allocation, null, &self.staging_memory) != vk.VK_SUCCESS) return error.Buffer;
        if (vk.vkBindBufferMemory(device, self.staging_buffer, self.staging_memory, 0) != vk.VK_SUCCESS) return error.Buffer;
        var mapped: ?*u8 = null;
        if (vk.vkMapMemory(device, self.staging_memory, 0, requirements.size, 0, &mapped) != vk.VK_SUCCESS or mapped == null) return error.StagingMap;
        self.mapped = @ptrCast(mapped.?);
    }

    fn createPipelines(self: *Context, device: vk.VkDevice) Error!void {
        const vertex = try shader(device, &vertex_shader);
        defer vk.vkDestroyShaderModule(device, vertex, null);
        const solid = try shader(device, &solid_shader);
        defer vk.vkDestroyShaderModule(device, solid, null);
        const text = try shader(device, &text_shader);
        defer vk.vkDestroyShaderModule(device, text, null);
        self.solid_pipeline = try pipeline(device, self.render_pass, self.layout, vertex, solid, false);
        self.text_pipeline = try pipeline(device, self.render_pass, self.layout, vertex, text, true);
    }
};

fn charge(self: *Context, gpu_bytes: *u64, bytes: u64, limit: u64) Error!void {
    const total = std.math.add(u64, gpu_bytes.*, bytes) catch return error.GpuMemoryLimit;
    if (total > limit) return error.GpuMemoryLimit;
    gpu_bytes.* = total;
    self.owned_bytes += bytes;
}

fn memoryType(properties: vk.VkPhysicalDeviceMemoryProperties, bits: u32, required: vk.VkMemoryPropertyFlags) Error!u32 {
    for (0..properties.memoryTypeCount) |index| {
        if (bits & (@as(u32, 1) << @intCast(index)) != 0 and properties.memoryTypes[index].propertyFlags & required == required) return @intCast(index);
    }
    return error.MemoryType;
}

fn shader(device: vk.VkDevice, bytes: []align(4) const u8) Error!vk.VkShaderModule {
    var info = vk.VkShaderModuleCreateInfo{ .codeSize = bytes.len, .pCode = @ptrCast(bytes.ptr) };
    var result: vk.VkShaderModule = null;
    if (vk.vkCreateShaderModule(device, &info, null, &result) != vk.VK_SUCCESS) return error.Shader;
    return result;
}

fn pipeline(device: vk.VkDevice, render_pass: vk.VkRenderPass, layout: vk.VkPipelineLayout, vertex: vk.VkShaderModule, fragment: vk.VkShaderModule, blend: bool) Error!vk.VkPipeline {
    const stages = [_]vk.VkPipelineShaderStageCreateInfo{
        .{ .stage = vk.VK_SHADER_STAGE_VERTEX_BIT, .module = vertex, .pName = "main" },
        .{ .stage = vk.VK_SHADER_STAGE_FRAGMENT_BIT, .module = fragment, .pName = "main" },
    };
    const binding = vk.VkVertexInputBindingDescription{ .stride = @sizeOf(draw.Vertex) };
    const attributes = [_]vk.VkVertexInputAttributeDescription{
        .{ .location = 0, .format = vk.VK_FORMAT_R32G32_SFLOAT, .offset = @offsetOf(draw.Vertex, "position") },
        .{ .location = 1, .format = vk.VK_FORMAT_R32G32_SFLOAT, .offset = @offsetOf(draw.Vertex, "uv") },
        .{ .location = 2, .format = vk.VK_FORMAT_R32G32B32A32_SFLOAT, .offset = @offsetOf(draw.Vertex, "color") },
    };
    var vertex_input = vk.VkPipelineVertexInputStateCreateInfo{ .vertexBindingDescriptionCount = 1, .pVertexBindingDescriptions = &binding, .vertexAttributeDescriptionCount = attributes.len, .pVertexAttributeDescriptions = &attributes };
    var assembly = vk.VkPipelineInputAssemblyStateCreateInfo{};
    var viewport = vk.VkPipelineViewportStateCreateInfo{ .viewportCount = 1, .scissorCount = 1 };
    var raster = vk.VkPipelineRasterizationStateCreateInfo{};
    var multisample = vk.VkPipelineMultisampleStateCreateInfo{};
    const color_mask = vk.VK_COLOR_COMPONENT_R_BIT | vk.VK_COLOR_COMPONENT_G_BIT | vk.VK_COLOR_COMPONENT_B_BIT | vk.VK_COLOR_COMPONENT_A_BIT;
    const attachment = vk.VkPipelineColorBlendAttachmentState{
        .blendEnable = if (blend) vk.VK_TRUE else 0,
        .srcColorBlendFactor = if (blend) vk.VK_BLEND_FACTOR_SRC_ALPHA else vk.VK_BLEND_FACTOR_ONE,
        .dstColorBlendFactor = if (blend) vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA else vk.VK_BLEND_FACTOR_ZERO,
        .srcAlphaBlendFactor = vk.VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = if (blend) vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA else vk.VK_BLEND_FACTOR_ZERO,
        .colorWriteMask = color_mask,
    };
    var color = vk.VkPipelineColorBlendStateCreateInfo{ .attachmentCount = 1, .pAttachments = &attachment };
    const dynamic_values = [_]vk.VkDynamicState{ vk.VK_DYNAMIC_STATE_VIEWPORT, vk.VK_DYNAMIC_STATE_SCISSOR };
    var dynamic = vk.VkPipelineDynamicStateCreateInfo{ .dynamicStateCount = dynamic_values.len, .pDynamicStates = &dynamic_values };
    var info = vk.VkGraphicsPipelineCreateInfo{
        .stageCount = stages.len,
        .pStages = &stages,
        .pVertexInputState = &vertex_input,
        .pInputAssemblyState = &assembly,
        .pViewportState = &viewport,
        .pRasterizationState = &raster,
        .pMultisampleState = &multisample,
        .pColorBlendState = &color,
        .pDynamicState = &dynamic,
        .layout = layout,
        .renderPass = render_pass,
    };
    var result: vk.VkPipeline = null;
    if (vk.vkCreateGraphicsPipelines(device, null, 1, &info, null, &result) != vk.VK_SUCCESS) return error.Pipeline;
    return result;
}
