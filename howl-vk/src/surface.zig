//! Owns bounded generic Vulkan surface pipelines, shared alpha/RGBA textures,
//! and mapped vertex/index/upload staging. It owns no application policy.

const std = @import("std");
const vk = @import("abi.zig");

/// Clipped surface-pixel rectangle supplied by a caller.
pub const Rect = struct { x: i32, y: i32, width: u32, height: u32 };
/// Selects one of the three generic surface pipelines.
pub const Kind = enum { solid, alpha_mask, rgba };
/// Caller-owned vertex in surface-pixel coordinates and normalized texture coordinates.
pub const Vertex = extern struct { position: [2]f32, uv: [2]f32, color: [4]f32 };
/// Ordered indexed draw with an exact clip rectangle.
pub const Command = struct { kind: Kind, first_index: u32, index_count: u32, clip: Rect };
/// Bounded caller-owned geometry and upload-change facts consumed synchronously.
pub const Plan = struct {
    vertices: []const Vertex,
    indices: []const u32,
    commands: []const Command,
    atlas_changed: bool,
    image_atlas_changed: bool = false,
};

/// Records which atlas transitions were included in one submitted command
/// buffer. The flags become factual only when the caller observes completion.
pub const Recording = struct {
    alpha_initialized: bool,
    image_initialized: bool,
};

/// Identifies one exact generic resource generation.
///
/// The resource high bit selects the shared namespace. Local values require a
/// nonzero caller-owned source; shared values require source zero.
pub const ResourceGeneration = struct {
    source: u64,
    resource: u64,
    generation: u64,

    const shared_bit: u64 = @as(u64, 1) << 63;
    /// Largest independently issuable identity in either namespace.
    pub const max_identity: u64 = shared_bit - 1;
    /// Reports malformed namespace, identity, source, or generation facts.
    pub const InitError = error{ InvalidIdentity, InvalidGeneration };

    /// Constructs and validates one generic resource fact mechanically.
    pub fn init(
        source: u64,
        encoded_resource: u64,
        generation: u64,
    ) InitError!ResourceGeneration {
        const identity_value = encoded_resource & max_identity;
        if (identity_value == 0 or ((source == 0) !=
            (encoded_resource & shared_bit != 0)))
            return error.InvalidIdentity;
        if (generation == 0) return error.InvalidGeneration;
        return .{
            .source = source,
            .resource = encoded_resource,
            .generation = generation,
        };
    }

    /// Constructs one source-qualified local resource generation.
    pub fn local(
        source: u64,
        identity_value: u64,
        generation: u64,
    ) InitError!ResourceGeneration {
        if (identity_value == 0 or identity_value > max_identity)
            return error.InvalidIdentity;
        return init(source, identity_value, generation);
    }

    /// Constructs one source-independent shared resource generation.
    pub fn shared(
        identity_value: u64,
        generation: u64,
    ) InitError!ResourceGeneration {
        if (identity_value == 0 or identity_value > max_identity)
            return error.InvalidIdentity;
        return init(0, identity_value | shared_bit, generation);
    }

    /// Reports whether this resource occupies the shared namespace.
    pub fn isShared(self: ResourceGeneration) bool {
        return self.resource & shared_bit != 0;
    }

    /// Returns the nonzero identity without its namespace bit.
    pub fn identity(self: ResourceGeneration) InitError!u64 {
        const value = self.resource & max_identity;
        if (value == 0) return error.InvalidIdentity;
        return value;
    }

    /// Validates the complete namespace and generation relationship.
    pub fn validate(self: ResourceGeneration) InitError!void {
        if (self.resource & max_identity == 0 or
            ((self.source == 0) != self.isShared()))
            return error.InvalidIdentity;
        if (self.generation == 0) return error.InvalidGeneration;
    }
};
/// Borrows one complete upload plane until frame application returns.
pub const Upload = struct {
    resource: ResourceGeneration,
    kind: Kind,
    width: u16,
    height: u16,
    stride: usize,
    pixels: []const u8,
};
/// Removes one exact qualified resource generation.
pub const Removal = struct { resource: ResourceGeneration };
/// Borrows one ordered generic surface command.
pub const FrameCommand = union(enum) {
    solid: struct { rect: Rect, clip: Rect, color: [4]f32 },
    alpha_mask: struct { rect: Rect, clip: Rect, resource: ResourceGeneration, source: ?Rect = null, color: [4]f32 },
    rgba: struct { rect: Rect, clip: Rect, resource: ResourceGeneration, source: ?Rect = null },
};
/// A complete frame plus sparse resource mutations, independent of Render.
pub const Frame = struct {
    revision: u64,
    uploads: []const Upload,
    removals: []const Removal,
    commands: []const FrameCommand,
};
/// Read-only factual residency observation supplied by the caller.
pub const Residency = struct {
    resource: ResourceGeneration,
    kind: Kind,
    width: u16,
    height: u16,
};
/// Edge length of the alpha-mask atlas.
pub const atlas_extent: u16 = 2048;
/// Byte capacity of the alpha-mask atlas.
pub const atlas_bytes: usize = @as(usize, atlas_extent) * atlas_extent;
/// Edge length of the RGBA atlas.
pub const image_atlas_extent: u16 = 1024;
/// Byte capacity of the RGBA atlas.
pub const image_atlas_bytes: usize = @as(usize, image_atlas_extent) * image_atlas_extent * 4;
/// Maximum quads accepted in one plan.
pub const max_quads: usize = 32_768;
/// Maximum vertices accepted in one plan.
pub const max_vertices: usize = max_quads * 4;
/// Maximum indices accepted in one plan.
pub const max_indices: usize = max_quads * 6;
/// Maximum ordered draw commands accepted in one plan.
pub const max_commands: usize = max_quads;

const vertex_shader align(4) = @embedFile("shaders/chrome.vert.spv").*;
const solid_shader align(4) = @embedFile("shaders/solid.frag.spv").*;
const text_shader align(4) = @embedFile("shaders/text.frag.spv").*;
const image_shader align(4) = @embedFile("shaders/image.frag.spv").*;

const vertex_bytes = @sizeOf(Vertex) * max_vertices;
const index_bytes = @sizeOf(u32) * max_indices;
const index_offset = std.mem.alignForward(usize, vertex_bytes, @alignOf(u32));
const atlas_offset = std.mem.alignForward(usize, index_offset + index_bytes, 4);
const image_atlas_offset = std.mem.alignForward(usize, atlas_offset + atlas_bytes, 4);
const staging_bytes = image_atlas_offset + image_atlas_bytes;

/// Names exact Vulkan resource, memory, and mapped-staging failures.
pub const Error = error{
    InvalidPlan,
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

/// Owns the shared Vulkan render pass, generic pipelines, R8 atlas, descriptors,
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
    image_pipeline: vk.VkPipeline = null,
    atlas_image: vk.VkImage = null,
    atlas_memory: vk.VkDeviceMemory = null,
    atlas_view: vk.VkImageView = null,
    image_atlas_image: vk.VkImage = null,
    image_atlas_memory: vk.VkDeviceMemory = null,
    image_atlas_view: vk.VkImageView = null,
    staging_buffer: vk.VkBuffer = null,
    staging_memory: vk.VkDeviceMemory = null,
    mapped: ?[*]u8 = null,
    owned_bytes: u64 = 0,
    atlas_initialized: bool = false,
    image_atlas_initialized: bool = false,

    /// Transactionally creates shared GPU owners and charges exact Vulkan
    /// allocation requirements against `gpu_bytes` and `limit`.
    pub fn init(device: vk.VkDevice, memory: vk.VkPhysicalDeviceMemoryProperties, gpu_bytes: *u64, limit: u64) Error!Context {
        var result = Context{};
        errdefer result.deinit(device, gpu_bytes);
        try result.createRenderPass(device);
        try result.createDescriptors(device);
        try result.createAtlas(device, memory, gpu_bytes, limit);
        try result.createImageAtlas(device, memory, gpu_bytes, limit);
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
        if (self.image_pipeline != null) vk.vkDestroyPipeline(device, self.image_pipeline, null);
        if (self.solid_pipeline != null) vk.vkDestroyPipeline(device, self.solid_pipeline, null);
        if (self.layout != null) vk.vkDestroyPipelineLayout(device, self.layout, null);
        if (self.descriptor_pool != null) vk.vkDestroyDescriptorPool(device, self.descriptor_pool, null);
        if (self.sampler != null) vk.vkDestroySampler(device, self.sampler, null);
        if (self.atlas_view != null) vk.vkDestroyImageView(device, self.atlas_view, null);
        if (self.atlas_image != null) vk.vkDestroyImage(device, self.atlas_image, null);
        if (self.atlas_memory != null) vk.vkFreeMemory(device, self.atlas_memory, null);
        if (self.image_atlas_view != null) vk.vkDestroyImageView(device, self.image_atlas_view, null);
        if (self.image_atlas_image != null) vk.vkDestroyImage(device, self.image_atlas_image, null);
        if (self.image_atlas_memory != null) vk.vkFreeMemory(device, self.image_atlas_memory, null);
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
    /// into persistently mapped bounded storage. Vertex positions and clips
    /// are validated and normalized in the caller's logical coordinate extent.
    pub fn stage(self: *Context, plan: Plan, atlas_pixels: []const u8, image_atlas_pixels: []const u8, coordinate_width: u32, coordinate_height: u32) Error!void {
        try validatePlan(plan, coordinate_width, coordinate_height);
        const mapped = self.mapped orelse return error.StagingMap;
        const vertices = std.mem.sliceAsBytes(plan.vertices);
        const indices = std.mem.sliceAsBytes(plan.indices);
        if (coordinate_width == 0 or coordinate_height == 0 or vertices.len > vertex_bytes or indices.len > index_bytes or atlas_pixels.len != atlas_bytes or image_atlas_pixels.len != image_atlas_bytes) return error.Buffer;
        const staged = std.mem.bytesAsSlice(Vertex, mapped[0..vertex_bytes]);
        for (plan.vertices, 0..) |vertex, index| {
            staged[index] = vertex;
            staged[index].position = try pixelToNdc(vertex.position, coordinate_width, coordinate_height);
        }
        @memcpy(mapped[index_offset .. index_offset + indices.len], indices);
        if (plan.atlas_changed or !self.atlas_initialized)
            @memcpy(mapped[atlas_offset .. atlas_offset + atlas_pixels.len], atlas_pixels);
        if (plan.image_atlas_changed or !self.image_atlas_initialized)
            @memcpy(mapped[image_atlas_offset .. image_atlas_offset + image_atlas_pixels.len], image_atlas_pixels);
    }

    /// Records atlas upload barriers, a physical-attachment clear, and ordered
    /// draws whose logical clips are projected mechanically to that attachment.
    /// It owns no submission, presentation, or scale policy.
    pub fn record(
        self: *Context,
        command: vk.VkCommandBuffer,
        attachment: Attachment,
        attachment_width: u32,
        attachment_height: u32,
        coordinate_width: u32,
        coordinate_height: u32,
        plan: Plan,
        clear: [4]f32,
    ) Error!Recording {
        const recording = try self.preflightRecording(
            plan,
            coordinate_width,
            coordinate_height,
            attachment_width,
            attachment_height,
        );
        if (recording.alpha_initialized) {
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
                .bufferRowLength = atlas_extent,
                .bufferImageHeight = atlas_extent,
                .imageSubresource = .{ .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, .mipLevel = 0, .baseArrayLayer = 0, .layerCount = 1 },
                .imageOffset = .{},
                .imageExtent = .{ .width = atlas_extent, .height = atlas_extent, .depth = 1 },
            };
            vk.vkCmdCopyBufferToImage(command, self.staging_buffer, self.atlas_image, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &copy);
            atlas_barrier.srcAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT;
            atlas_barrier.dstAccessMask = vk.VK_ACCESS_SHADER_READ_BIT;
            atlas_barrier.oldLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
            atlas_barrier.newLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
            vk.vkCmdPipelineBarrier(command, vk.VK_PIPELINE_STAGE_TRANSFER_BIT, vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, null, 0, null, 1, &atlas_barrier);
        }
        if (recording.image_initialized) {
            self.uploadAtlas(command, self.image_atlas_image, image_atlas_extent, image_atlas_offset, self.image_atlas_initialized);
        }
        const clear_value = vk.VkClearValue{ .color = .{ .float32 = clear } };
        var begin = vk.VkRenderPassBeginInfo{
            .renderPass = self.render_pass,
            .framebuffer = attachment.framebuffer,
            .renderArea = .{ .extent = .{ .width = attachment_width, .height = attachment_height } },
            .clearValueCount = 1,
            .pClearValues = &clear_value,
        };
        vk.vkCmdBeginRenderPass(command, &begin, vk.VK_SUBPASS_CONTENTS_INLINE);
        var viewport = vk.VkViewport{
            .y = @floatFromInt(attachment_height),
            .width = @floatFromInt(attachment_width),
            .height = -@as(f32, @floatFromInt(attachment_height)),
        };
        vk.vkCmdSetViewport(command, 0, 1, &viewport);
        var buffers = [_]vk.VkBuffer{self.staging_buffer};
        var offsets = [_]vk.VkDeviceSize{0};
        vk.vkCmdBindVertexBuffers(command, 0, 1, &buffers, &offsets);
        vk.vkCmdBindIndexBuffer(command, self.staging_buffer, index_offset, vk.VK_INDEX_TYPE_UINT32);
        var bound: ?Kind = null;
        for (plan.commands) |item| {
            if (bound == null or bound.? != item.kind) {
                vk.vkCmdBindPipeline(command, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, switch (item.kind) {
                    .solid => self.solid_pipeline,
                    .alpha_mask => self.text_pipeline,
                    .rgba => self.image_pipeline,
                });
                if (item.kind != .solid) vk.vkCmdBindDescriptorSets(command, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.layout, 0, 1, &self.descriptor, 0, null);
                bound = item.kind;
            }
            var scissor = physicalScissorValidated(
                item.clip,
                coordinate_width,
                coordinate_height,
                attachment_width,
                attachment_height,
            );
            vk.vkCmdSetScissor(command, 0, 1, &scissor);
            vk.vkCmdDrawIndexed(command, item.index_count, 1, item.first_index, 0, 0);
        }
        vk.vkCmdEndRenderPass(command);
        return recording;
    }

    /// Commits atlas layout facts after the caller has observed GPU completion.
    pub fn complete(self: *Context, recording: Recording) void {
        if (recording.alpha_initialized) self.atlas_initialized = true;
        if (recording.image_initialized) self.image_atlas_initialized = true;
    }

    fn recordingFor(self: *const Context, plan: Plan) Recording {
        return .{
            .alpha_initialized = plan.atlas_changed or !self.atlas_initialized,
            .image_initialized = plan.image_atlas_changed or !self.image_atlas_initialized,
        };
    }

    fn preflightRecording(
        self: *const Context,
        plan: Plan,
        coordinate_width: u32,
        coordinate_height: u32,
        attachment_width: u32,
        attachment_height: u32,
    ) Error!Recording {
        try validatePlan(plan, coordinate_width, coordinate_height);
        if (attachment_width == 0 or attachment_height == 0 or
            attachment_width > std.math.maxInt(i32) or
            attachment_height > std.math.maxInt(i32))
            return error.InvalidPlan;
        for (plan.commands) |item| {
            const projected = try physicalScissor(
                item.clip,
                coordinate_width,
                coordinate_height,
                attachment_width,
                attachment_height,
            );
            if (projected.extent.width == 0 or projected.extent.height == 0)
                return error.InvalidPlan;
        }
        return self.recordingFor(plan);
    }

    /// Validates every plan relationship before mapped staging or command
    /// recording. No caller bytes or context facts are touched on failure.
    fn validatePlan(plan: Plan, width: u32, height: u32) Error!void {
        if (width == 0 or height == 0) return error.InvalidPlan;
        if (plan.vertices.len > max_vertices or plan.indices.len > max_indices or plan.commands.len > max_commands) return error.InvalidPlan;
        if (plan.commands.len == 0) {
            if (plan.vertices.len != 0 or plan.indices.len != 0) return error.InvalidPlan;
        } else if (plan.vertices.len == 0 or plan.indices.len == 0) {
            return error.InvalidPlan;
        }
        for (plan.indices) |index| {
            if (@as(usize, index) >= plan.vertices.len) return error.InvalidPlan;
        }
        for (plan.commands) |item| {
            if (item.index_count == 0) return error.InvalidPlan;
            const end = std.math.add(u64, item.first_index, item.index_count) catch return error.InvalidPlan;
            if (end > plan.indices.len) return error.InvalidPlan;
            if (item.clip.x < 0 or item.clip.y < 0 or item.clip.width == 0 or item.clip.height == 0) return error.InvalidPlan;
            const right = std.math.add(u64, @intCast(item.clip.x), item.clip.width) catch return error.InvalidPlan;
            const bottom = std.math.add(u64, @intCast(item.clip.y), item.clip.height) catch return error.InvalidPlan;
            if (right > width or bottom > height) return error.InvalidPlan;
        }
    }

    fn uploadAtlas(self: *Context, command: vk.VkCommandBuffer, image: vk.VkImage, extent: u16, offset: usize, initialized: bool) void {
        const range = vk.VkImageSubresourceRange{ .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, .baseMipLevel = 0, .levelCount = 1, .baseArrayLayer = 0, .layerCount = 1 };
        var barrier = vk.VkImageMemoryBarrier{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            .oldLayout = if (initialized) vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL else vk.VK_IMAGE_LAYOUT_UNDEFINED,
            .newLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
            .image = image,
            .subresourceRange = range,
            .srcAccessMask = if (initialized) vk.VK_ACCESS_SHADER_READ_BIT else 0,
            .dstAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT,
        };
        vk.vkCmdPipelineBarrier(command, if (initialized) vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT else vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, vk.VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, null, 0, null, 1, &barrier);
        var copy = vk.VkBufferImageCopy{
            .bufferOffset = offset,
            .bufferRowLength = extent,
            .bufferImageHeight = extent,
            .imageSubresource = .{ .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, .mipLevel = 0, .baseArrayLayer = 0, .layerCount = 1 },
            .imageOffset = .{},
            .imageExtent = .{ .width = extent, .height = extent, .depth = 1 },
        };
        vk.vkCmdCopyBufferToImage(command, self.staging_buffer, image, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &copy);
        barrier.srcAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.dstAccessMask = vk.VK_ACCESS_SHADER_READ_BIT;
        barrier.oldLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        barrier.newLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        vk.vkCmdPipelineBarrier(command, vk.VK_PIPELINE_STAGE_TRANSFER_BIT, vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, null, 0, null, 1, &barrier);
    }

    fn createRenderPass(self: *Context, device: vk.VkDevice) Error!void {
        const attachment = vk.VkAttachmentDescription{
            .format = vk.VK_FORMAT_R8G8B8A8_UNORM,
            .initialLayout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            .finalLayout = vk.VK_IMAGE_LAYOUT_GENERAL,
        };
        const reference = vk.VkAttachmentReference{ .layout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL };
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
        const bindings = [_]vk.VkDescriptorSetLayoutBinding{
            .{ .binding = 0, .descriptorCount = 1, .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT },
            .{ .binding = 1, .descriptorCount = 1, .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT },
        };
        var layout_info = vk.VkDescriptorSetLayoutCreateInfo{ .bindingCount = bindings.len, .pBindings = &bindings };
        if (vk.vkCreateDescriptorSetLayout(device, &layout_info, null, &self.descriptor_layout) != vk.VK_SUCCESS) return error.Descriptor;
        var pipeline_layout = vk.VkPipelineLayoutCreateInfo{ .setLayoutCount = 1, .pSetLayouts = &self.descriptor_layout };
        if (vk.vkCreatePipelineLayout(device, &pipeline_layout, null, &self.layout) != vk.VK_SUCCESS) return error.Pipeline;
        const pool_size = vk.VkDescriptorPoolSize{ .type = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount = 2 };
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
            .extent = .{ .width = atlas_extent, .height = atlas_extent, .depth = 1 },
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

    fn createImageAtlas(self: *Context, device: vk.VkDevice, memory: vk.VkPhysicalDeviceMemoryProperties, gpu_bytes: *u64, limit: u64) Error!void {
        var info = vk.VkImageCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .imageType = vk.VK_IMAGE_TYPE_2D,
            .format = vk.VK_FORMAT_R8G8B8A8_UNORM,
            .extent = .{ .width = image_atlas_extent, .height = image_atlas_extent, .depth = 1 },
            .mipLevels = 1,
            .arrayLayers = 1,
            .samples = vk.VK_SAMPLE_COUNT_1_BIT,
            .tiling = 0,
            .usage = vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.VK_IMAGE_USAGE_SAMPLED_BIT,
            .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
            .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
        };
        if (vk.vkCreateImage(device, &info, null, &self.image_atlas_image) != vk.VK_SUCCESS) return error.Image;
        var requirements: vk.VkMemoryRequirements = undefined;
        vk.vkGetImageMemoryRequirements(device, self.image_atlas_image, &requirements);
        try charge(self, gpu_bytes, requirements.size, limit);
        var allocation = vk.VkMemoryAllocateInfo{ .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = requirements.size, .memoryTypeIndex = try memoryType(memory, requirements.memoryTypeBits, vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) };
        if (vk.vkAllocateMemory(device, &allocation, null, &self.image_atlas_memory) != vk.VK_SUCCESS) return error.Image;
        if (vk.vkBindImageMemory(device, self.image_atlas_image, self.image_atlas_memory, 0) != vk.VK_SUCCESS) return error.Image;
        var view_info = vk.VkImageViewCreateInfo{
            .image = self.image_atlas_image,
            .format = vk.VK_FORMAT_R8G8B8A8_UNORM,
            .subresourceRange = .{ .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, .baseMipLevel = 0, .levelCount = 1, .baseArrayLayer = 0, .layerCount = 1 },
        };
        if (vk.vkCreateImageView(device, &view_info, null, &self.image_atlas_view) != vk.VK_SUCCESS) return error.ImageView;
        const image_info = vk.VkDescriptorImageInfo{ .sampler = self.sampler, .imageView = self.image_atlas_view };
        var write = vk.VkWriteDescriptorSet{ .dstSet = self.descriptor, .dstBinding = 1, .descriptorCount = 1, .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .pImageInfo = &image_info };
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
        const image = try shader(device, &image_shader);
        defer vk.vkDestroyShaderModule(device, image, null);
        self.solid_pipeline = try pipeline(device, self.render_pass, self.layout, vertex, solid, false);
        self.text_pipeline = try pipeline(device, self.render_pass, self.layout, vertex, text, true);
        self.image_pipeline = try pipeline(device, self.render_pass, self.layout, vertex, image, true);
    }
};

/// Bounds and owns generic qualified-resource residency independently of any
/// presentation or producer policy. GPU-backed implementations may use the
/// same candidate/commit protocol around physical allocations.
pub const ResidencyStore = struct {
    pub const Limits = struct { resources: usize, pixel_bytes: usize };
    pub const StoreError = error{ OutOfMemory, InvalidFrame, Capacity, GenerationMismatch, ArithmeticOverflow, Pending };
    const Entry = struct { resource: ResourceGeneration, kind: Kind, width: u16, height: u16, stride: usize, pixel_start: usize, pixel_count: usize };
    allocator: std.mem.Allocator,
    limits: Limits,
    active: []Entry,
    candidate: []Entry,
    active_pixels: []u8,
    candidate_pixels: []u8,
    active_count: usize = 0,
    candidate_count: usize = 0,
    candidate_pixel_count: usize = 0,
    pending: bool = false,

    /// Allocates all bounded residency and candidate storage up front.
    pub fn init(allocator: std.mem.Allocator, limits: Limits) StoreError!ResidencyStore {
        const active = allocator.alloc(Entry, limits.resources) catch return error.OutOfMemory;
        errdefer allocator.free(active);
        const candidate = allocator.alloc(Entry, limits.resources) catch return error.OutOfMemory;
        errdefer allocator.free(candidate);
        const active_pixels = allocator.alloc(u8, limits.pixel_bytes) catch return error.OutOfMemory;
        errdefer allocator.free(active_pixels);
        const candidate_pixels = allocator.alloc(u8, limits.pixel_bytes) catch return error.OutOfMemory;
        return .{
            .allocator = allocator,
            .limits = limits,
            .active = active,
            .candidate = candidate,
            .active_pixels = active_pixels,
            .candidate_pixels = candidate_pixels,
        };
    }

    /// Releases active, candidate, and pixel storage in reverse order.
    pub fn deinit(self: *ResidencyStore) void {
        self.allocator.free(self.candidate_pixels);
        self.allocator.free(self.active_pixels);
        self.allocator.free(self.candidate);
        self.allocator.free(self.active);
        self.* = undefined;
    }

    /// Builds a complete candidate without changing active residency.
    pub fn stage(self: *ResidencyStore, frame: Frame) StoreError!void {
        if (frame.revision == 0) return error.InvalidFrame;
        if (self.pending) return error.Pending;
        if (frame.uploads.len > self.limits.resources or frame.removals.len > self.limits.resources) return error.Capacity;
        self.candidate_count = 0;
        self.candidate_pixel_count = 0;
        errdefer {
            self.candidate_count = 0;
            self.candidate_pixel_count = 0;
        }

        for (frame.uploads, 0..) |upload, index| {
            try validateUpload(upload);
            for (frame.uploads[0..index]) |prior| {
                if (sameIdentity(prior.resource, upload.resource)) return error.InvalidFrame;
            }
            for (frame.removals) |removal| {
                if (sameIdentity(removal.resource, upload.resource)) return error.InvalidFrame;
            }
        }
        for (frame.removals, 0..) |removal, index| {
            try validateResource(removal.resource);
            for (frame.removals[0..index]) |prior| {
                if (sameIdentity(prior.resource, removal.resource)) return error.InvalidFrame;
            }
        }

        for (self.active[0..self.active_count]) |entry| {
            if (findRemoval(frame.removals, entry.resource)) |removal| {
                if (removal.resource.generation != entry.resource.generation) return error.GenerationMismatch;
                continue;
            }
            if (findUpload(frame.uploads, entry.resource)) |upload| {
                if (upload.resource.generation <= entry.resource.generation) return error.GenerationMismatch;
                try self.appendCandidate(upload.resource, upload.kind, upload.width, upload.height, upload.stride, upload.pixels);
                continue;
            }
            try self.appendCandidate(
                entry.resource,
                entry.kind,
                entry.width,
                entry.height,
                entry.stride,
                self.active_pixels[entry.pixel_start .. entry.pixel_start + entry.pixel_count],
            );
        }

        for (frame.removals) |removal| {
            if (findEntry(self.active[0..self.active_count], removal.resource) == null) return error.GenerationMismatch;
        }
        for (frame.uploads) |upload| {
            if (findEntry(self.active[0..self.active_count], upload.resource) != null) continue;
            try self.appendCandidate(upload.resource, upload.kind, upload.width, upload.height, upload.stride, upload.pixels);
        }
        try self.validateCommands(frame.commands);
        self.pending = true;
    }

    /// Commits a successfully completed candidate; failures before this call
    /// leave active enumeration unchanged.
    pub fn complete(self: *ResidencyStore) StoreError!void {
        if (!self.pending) return error.Pending;
        const entries = self.active;
        self.active = self.candidate;
        self.candidate = entries;
        const pixels = self.active_pixels;
        self.active_pixels = self.candidate_pixels;
        self.candidate_pixels = pixels;
        self.active_count = self.candidate_count;
        self.candidate_count = 0;
        self.candidate_pixel_count = 0;
        self.pending = false;
    }

    /// Discards candidate ownership after recording or submission failure.
    pub fn discard(self: *ResidencyStore) void {
        self.candidate_count = 0;
        self.candidate_pixel_count = 0;
        self.pending = false;
    }

    /// Enumerates the factual active residency without mutating it.
    pub fn enumerate(self: *const ResidencyStore, output: []Residency) StoreError![]const Residency {
        if (output.len < self.active_count) return error.Capacity;
        for (self.active[0..self.active_count], 0..) |entry, index| output[index] = .{ .resource = entry.resource, .kind = entry.kind, .width = entry.width, .height = entry.height };
        return output[0..self.active_count];
    }

    fn appendCandidate(
        self: *ResidencyStore,
        resource: ResourceGeneration,
        kind: Kind,
        width: u16,
        height: u16,
        stride: usize,
        pixels: []const u8,
    ) StoreError!void {
        if (self.candidate_count == self.candidate.len) return error.Capacity;
        const end = std.math.add(usize, self.candidate_pixel_count, pixels.len) catch return error.ArithmeticOverflow;
        if (end > self.candidate_pixels.len) return error.Capacity;
        self.candidate[self.candidate_count] = .{
            .resource = resource,
            .kind = kind,
            .width = width,
            .height = height,
            .stride = stride,
            .pixel_start = self.candidate_pixel_count,
            .pixel_count = pixels.len,
        };
        @memcpy(self.candidate_pixels[self.candidate_pixel_count..end], pixels);
        self.candidate_count += 1;
        self.candidate_pixel_count = end;
    }

    fn validateCommands(self: *const ResidencyStore, commands: []const FrameCommand) StoreError!void {
        if (commands.len > max_commands) return error.Capacity;
        for (commands) |command| switch (command) {
            .solid => |value| {
                try validateRect(value.rect);
                try validateRect(value.clip);
            },
            .alpha_mask => |value| try self.validateResourceCommand(value.rect, value.clip, value.resource, value.source, .alpha_mask),
            .rgba => |value| try self.validateResourceCommand(value.rect, value.clip, value.resource, value.source, .rgba),
        };
    }

    fn validateResourceCommand(
        self: *const ResidencyStore,
        rect: Rect,
        clip: Rect,
        resource: ResourceGeneration,
        source: ?Rect,
        kind: Kind,
    ) StoreError!void {
        try validateRect(rect);
        try validateRect(clip);
        const entry = findExactEntry(self.candidate[0..self.candidate_count], resource) orelse return error.GenerationMismatch;
        if (entry.kind != kind) return error.InvalidFrame;
        if (source) |region| {
            try validateRect(region);
            if (region.x < 0 or region.y < 0) return error.InvalidFrame;
            const right = std.math.add(u64, @intCast(region.x), region.width) catch return error.ArithmeticOverflow;
            const bottom = std.math.add(u64, @intCast(region.y), region.height) catch return error.ArithmeticOverflow;
            if (right > entry.width or bottom > entry.height) return error.InvalidFrame;
        }
    }
};

/// Converts a complete generic frame into bounded Vulkan-ready geometry and
/// full alpha/RGBA atlas candidates without naming producer domains.
pub const FrameBuilder = struct {
    pub const BuildError = error{ OutOfMemory, Capacity, InvalidFrame, ArithmeticOverflow };
    const Packed = struct { resource: ResourceGeneration, kind: Kind, x: u16, y: u16, width: u16, height: u16 };
    // Linear filtering may sample one texel beyond a resource when a logical
    // quad is magnified onto a fractional physical attachment. Each resource
    // therefore owns an extruded edge texel instead of sampling its neighbor.
    const atlas_gutter: u32 = 1;
    allocator: std.mem.Allocator,
    alpha_pixels: []u8,
    rgba_pixels: []u8,
    entries: []Packed,
    packed_count: usize = 0,
    vertices: []Vertex,
    vertex_count: usize = 0,
    indices: []u32,
    index_count: usize = 0,
    commands: []Command,
    command_count: usize = 0,

    /// Allocates complete bounded atlas and geometry candidates once.
    pub fn init(allocator: std.mem.Allocator) BuildError!FrameBuilder {
        const alpha = allocator.alloc(u8, atlas_bytes) catch return error.OutOfMemory;
        errdefer allocator.free(alpha);
        const rgba = allocator.alloc(u8, image_atlas_bytes) catch return error.OutOfMemory;
        errdefer allocator.free(rgba);
        const entries = allocator.alloc(Packed, max_quads) catch return error.OutOfMemory;
        errdefer allocator.free(entries);
        const vertices = allocator.alloc(Vertex, max_vertices) catch return error.OutOfMemory;
        errdefer allocator.free(vertices);
        const indices = allocator.alloc(u32, max_indices) catch return error.OutOfMemory;
        errdefer allocator.free(indices);
        const commands = allocator.alloc(Command, max_commands) catch return error.OutOfMemory;
        return .{
            .allocator = allocator,
            .alpha_pixels = alpha,
            .rgba_pixels = rgba,
            .entries = entries,
            .vertices = vertices,
            .indices = indices,
            .commands = commands,
        };
    }

    pub fn deinit(self: *FrameBuilder) void {
        self.allocator.free(self.commands);
        self.allocator.free(self.indices);
        self.allocator.free(self.vertices);
        self.allocator.free(self.entries);
        self.allocator.free(self.rgba_pixels);
        self.allocator.free(self.alpha_pixels);
        self.* = undefined;
    }

    /// Builds complete candidate atlases with isolated filtering gutters
    /// and ordered geometry transactionally.
    pub fn build(self: *FrameBuilder, store: *const ResidencyStore, frame: Frame) BuildError!Plan {
        if (!store.pending or frame.revision == 0 or frame.commands.len > max_commands or store.candidate_count > self.entries.len) return error.InvalidFrame;
        var alpha_x: u32 = 0;
        var alpha_y: u32 = 0;
        var alpha_h: u32 = 0;
        var rgba_x: u32 = 0;
        var rgba_y: u32 = 0;
        var rgba_h: u32 = 0;
        var packed_count: usize = 0;
        for (store.candidate[0..store.candidate_count]) |entry| {
            const is_alpha = entry.kind == .alpha_mask;
            if (!is_alpha and entry.kind != .rgba) return error.InvalidFrame;
            const extent: u32 = if (is_alpha) atlas_extent else image_atlas_extent;
            const bpp: usize = if (is_alpha) 1 else 4;
            if (entry.width == 0 or entry.height == 0 or entry.width > extent or entry.height > extent) return error.InvalidFrame;
            const row = std.math.mul(usize, entry.width, bpp) catch return error.ArithmeticOverflow;
            if (entry.stride < row or entry.pixel_count != std.math.mul(usize, entry.stride, entry.height) catch return error.ArithmeticOverflow) return error.InvalidFrame;
            var x = if (is_alpha) alpha_x else rgba_x;
            var y = if (is_alpha) alpha_y else rgba_y;
            var shelf = if (is_alpha) alpha_h else rgba_h;
            const packed_width = std.math.add(u32, entry.width, atlas_gutter * 2) catch
                return error.ArithmeticOverflow;
            const packed_height = std.math.add(u32, entry.height, atlas_gutter * 2) catch
                return error.ArithmeticOverflow;
            if (packed_width > extent or packed_height > extent) return error.Capacity;
            const packed_right = std.math.add(u32, x, packed_width) catch
                return error.ArithmeticOverflow;
            if (packed_right > extent) {
                x = 0;
                y = std.math.add(u32, y, shelf) catch return error.ArithmeticOverflow;
                shelf = 0;
            }
            const packed_bottom = std.math.add(u32, y, packed_height) catch
                return error.ArithmeticOverflow;
            if (packed_bottom > extent)
                return error.Capacity;
            const target = if (is_alpha) self.alpha_pixels else self.rgba_pixels;
            const source_pixels = store.candidate_pixels[entry.pixel_start .. entry.pixel_start + entry.pixel_count];
            const packed_x = x + atlas_gutter;
            const packed_y = y + atlas_gutter;
            const outer_row_bytes = std.math.mul(usize, packed_width, bpp) catch
                return error.ArithmeticOverflow;
            for (0..entry.height) |row_index| {
                const source_start = row_index * entry.stride;
                const target_start = ((packed_y + row_index) * extent + packed_x) * bpp;
                @memcpy(target[target_start .. target_start + row], source_pixels[source_start .. source_start + row]);
                @memcpy(
                    target[target_start - bpp .. target_start],
                    target[target_start .. target_start + bpp],
                );
                @memcpy(
                    target[target_start + row .. target_start + row + bpp],
                    target[target_start + row - bpp .. target_start + row],
                );
            }
            const top_start = (y * extent + x) * bpp;
            const first_row = (packed_y * extent + x) * bpp;
            const last_row = ((packed_y + entry.height - 1) * extent + x) * bpp;
            const bottom_start = ((y + packed_height - 1) * extent + x) * bpp;
            @memcpy(
                target[top_start .. top_start + outer_row_bytes],
                target[first_row .. first_row + outer_row_bytes],
            );
            @memcpy(
                target[bottom_start .. bottom_start + outer_row_bytes],
                target[last_row .. last_row + outer_row_bytes],
            );
            self.entries[packed_count] = .{
                .resource = entry.resource,
                .kind = entry.kind,
                .x = @intCast(packed_x),
                .y = @intCast(packed_y),
                .width = entry.width,
                .height = entry.height,
            };
            packed_count += 1;
            x += packed_width;
            shelf = @max(shelf, packed_height);
            if (is_alpha) {
                alpha_x = x;
                alpha_y = y;
                alpha_h = shelf;
            } else {
                rgba_x = x;
                rgba_y = y;
                rgba_h = shelf;
            }
        }
        var vertex_count: usize = 0;
        var index_count: usize = 0;
        var command_count: usize = 0;
        for (frame.commands) |item| {
            const kind: Kind, const rect: Rect, const clip: Rect, const color: [4]f32, const packed_entry = switch (item) {
                .solid => |v| .{ .solid, v.rect, v.clip, v.color, @as(?Packed, null) },
                .alpha_mask => |v| .{ .alpha_mask, v.rect, v.clip, v.color, findPacked(self.entries[0..packed_count], v.resource) },
                .rgba => |v| .{ .rgba, v.rect, v.clip, .{ 1, 1, 1, 1 }, findPacked(self.entries[0..packed_count], v.resource) },
            };
            if (kind != .solid and packed_entry == null) return error.InvalidFrame;
            if (vertex_count + 4 > self.vertices.len or index_count + 6 > self.indices.len or command_count == self.commands.len) return error.Capacity;
            const source = switch (item) {
                .solid => null,
                .alpha_mask => |value| value.source,
                .rgba => |value| value.source,
            };
            const uv = if (packed_entry) |p| uvRect(p, source) else [4]f32{ 0, 0, 0, 0 };
            self.vertices[vertex_count + 0] = .{ .position = .{ @floatFromInt(rect.x), @floatFromInt(rect.y) }, .uv = .{ uv[0], uv[1] }, .color = color };
            self.vertices[vertex_count + 1] = .{ .position = .{ @floatFromInt(@as(i64, rect.x) + rect.width), @floatFromInt(rect.y) }, .uv = .{ uv[2], uv[1] }, .color = color };
            self.vertices[vertex_count + 2] = .{ .position = .{ @floatFromInt(@as(i64, rect.x) + rect.width), @floatFromInt(@as(i64, rect.y) + rect.height) }, .uv = .{ uv[2], uv[3] }, .color = color };
            self.vertices[vertex_count + 3] = .{ .position = .{ @floatFromInt(rect.x), @floatFromInt(@as(i64, rect.y) + rect.height) }, .uv = .{ uv[0], uv[3] }, .color = color };
            const base: u32 = @intCast(vertex_count);
            @memcpy(self.indices[index_count .. index_count + 6], &[_]u32{ base, base + 1, base + 2, base, base + 2, base + 3 });
            self.commands[command_count] = .{ .kind = kind, .first_index = @intCast(index_count), .index_count = 6, .clip = clip };
            vertex_count += 4;
            index_count += 6;
            command_count += 1;
        }
        self.packed_count = packed_count;
        self.vertex_count = vertex_count;
        self.index_count = index_count;
        self.command_count = command_count;
        return .{ .vertices = self.vertices[0..vertex_count], .indices = self.indices[0..index_count], .commands = self.commands[0..command_count], .atlas_changed = true, .image_atlas_changed = true };
    }
};

fn findPacked(values: []const FrameBuilder.Packed, resource: ResourceGeneration) ?FrameBuilder.Packed {
    for (values) |value| if (std.meta.eql(value.resource, resource)) return value;
    return null;
}

fn pixelToNdc(position: [2]f32, width: u32, height: u32) Error![2]f32 {
    if (width == 0 or height == 0) return error.Buffer;
    return .{
        position[0] * 2.0 / @as(f32, @floatFromInt(width)) - 1.0,
        1.0 - position[1] * 2.0 / @as(f32, @floatFromInt(height)),
    };
}

fn physicalScissor(
    logical: Rect,
    logical_width: u32,
    logical_height: u32,
    physical_width: u32,
    physical_height: u32,
) Error!vk.VkRect2D {
    if (logical.x < 0 or logical.y < 0 or
        logical_width == 0 or logical_height == 0 or
        physical_width == 0 or physical_height == 0)
        return error.InvalidPlan;
    const left: u64 = @intCast(logical.x);
    const top: u64 = @intCast(logical.y);
    const right = std.math.add(u64, left, logical.width) catch
        return error.InvalidPlan;
    const bottom = std.math.add(u64, top, logical.height) catch
        return error.InvalidPlan;
    if (right > logical_width or bottom > logical_height)
        return error.InvalidPlan;
    if (physical_width > std.math.maxInt(i32) or
        physical_height > std.math.maxInt(i32))
        return error.InvalidPlan;
    const result = physicalScissorValidated(
        logical,
        logical_width,
        logical_height,
        physical_width,
        physical_height,
    );
    if (result.extent.width == 0 or result.extent.height == 0)
        return error.InvalidPlan;
    return result;
}

fn physicalScissorValidated(
    logical: Rect,
    logical_width: u32,
    logical_height: u32,
    physical_width: u32,
    physical_height: u32,
) vk.VkRect2D {
    const left: u64 = @intCast(logical.x);
    const top: u64 = @intCast(logical.y);
    const right = left + logical.width;
    const bottom = top + logical.height;
    const physical_left = scaleBoundary(left, physical_width, logical_width);
    const physical_top = scaleBoundary(top, physical_height, logical_height);
    const physical_right = scaleBoundary(right, physical_width, logical_width);
    const physical_bottom = scaleBoundary(bottom, physical_height, logical_height);
    return .{
        .offset = .{
            .x = @intCast(physical_left),
            .y = @intCast(physical_top),
        },
        .extent = .{
            .width = @intCast(physical_right - physical_left),
            .height = @intCast(physical_bottom - physical_top),
        },
    };
}

fn scaleBoundary(value: u64, physical: u32, logical: u32) u64 {
    const doubled_value = value * 2;
    const product = doubled_value * physical;
    const adjusted = product + logical;
    return adjusted / (@as(u64, logical) * 2);
}

test "logical scissors cover exact integer and fractional physical edges" {
    const full = Rect{ .x = 0, .y = 0, .width = 100, .height = 80 };
    try std.testing.expectEqual(
        vk.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = .{ .width = 200, .height = 160 },
        },
        try physicalScissor(full, 100, 80, 200, 160),
    );
    try std.testing.expectEqual(
        vk.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = .{ .width = 160, .height = 128 },
        },
        try physicalScissor(full, 100, 80, 160, 128),
    );
    const adjacent_left = try physicalScissor(
        .{ .x = 0, .y = 0, .width = 33, .height = 80 },
        100,
        80,
        160,
        128,
    );
    const adjacent_right = try physicalScissor(
        .{ .x = 33, .y = 0, .width = 67, .height = 80 },
        100,
        80,
        160,
        128,
    );
    try std.testing.expectEqual(
        @as(u32, @intCast(adjacent_left.offset.x)) + adjacent_left.extent.width,
        @as(u32, @intCast(adjacent_right.offset.x)),
    );
    try std.testing.expectEqual(
        @as(u32, 160),
        @as(u32, @intCast(adjacent_right.offset.x)) + adjacent_right.extent.width,
    );
    const adjacent_top = try physicalScissor(
        .{ .x = 0, .y = 0, .width = 100, .height = 27 },
        100,
        80,
        160,
        128,
    );
    const adjacent_bottom = try physicalScissor(
        .{ .x = 0, .y = 27, .width = 100, .height = 53 },
        100,
        80,
        160,
        128,
    );
    try std.testing.expectEqual(
        @as(u32, @intCast(adjacent_top.offset.y)) + adjacent_top.extent.height,
        @as(u32, @intCast(adjacent_bottom.offset.y)),
    );

    // Geometry may overhang its logical clip, but the physical command
    // scissor remains the exact shared-boundary projection above.
    const vertices = [_]Vertex{
        .{ .position = .{ 20, 0 }, .uv = .{ 0, 0 }, .color = .{ 1, 1, 1, 1 } },
        .{ .position = .{ 70, 0 }, .uv = .{ 0, 0 }, .color = .{ 1, 1, 1, 1 } },
        .{ .position = .{ 70, 80 }, .uv = .{ 0, 0 }, .color = .{ 1, 1, 1, 1 } },
    };
    const indices = [_]u16{ 0, 1, 2 };
    try Context.validatePlan(.{
        .vertices = &vertices,
        .indices = &indices,
        .commands = &.{.{
            .kind = .solid,
            .first_index = 0,
            .index_count = 3,
            .clip = .{ .x = 33, .y = 0, .width = 67, .height = 80 },
        }},
    }, 100, 80);
}

fn uvRect(value: FrameBuilder.Packed, source: ?Rect) [4]f32 {
    const extent: f32 = @floatFromInt(if (value.kind == .alpha_mask) atlas_extent else image_atlas_extent);
    const region = source orelse Rect{ .x = 0, .y = 0, .width = value.width, .height = value.height };
    const left: u32 = @intCast(region.x);
    const top: u32 = @intCast(region.y);
    return .{
        @as(f32, @floatFromInt(@as(u32, value.x) + left)) / extent,
        @as(f32, @floatFromInt(@as(u32, value.y) + top)) / extent,
        @as(f32, @floatFromInt(@as(u32, value.x) + left + region.width)) / extent,
        @as(f32, @floatFromInt(@as(u32, value.y) + top + region.height)) / extent,
    };
}

test "atlas resources retain isolated edge-extrusion gutters" {
    var store = try ResidencyStore.init(
        std.testing.allocator,
        .{ .resources = 3, .pixel_bytes = 24 },
    );
    defer store.deinit();
    var builder = try FrameBuilder.init(std.testing.allocator);
    defer builder.deinit();
    @memset(builder.alpha_pixels, 0xa5);
    @memset(builder.rgba_pixels, 0xa5);

    const first = try ResourceGeneration.local(1, 1, 1);
    const second = try ResourceGeneration.local(1, 2, 1);
    const image = try ResourceGeneration.local(1, 3, 1);
    const first_pixels = [_]u8{ 0x11, 0x12, 0x13, 0x14 };
    const second_pixels = [_]u8{ 0x21, 0x22, 0x23, 0x24 };
    const image_pixels = [_]u8{
        1, 2,  3,  4,  5,  6,  7,  8,
        9, 10, 11, 12, 13, 14, 15, 16,
    };
    const uploads = [_]Upload{
        .{
            .resource = first,
            .kind = .alpha_mask,
            .width = 2,
            .height = 2,
            .stride = 2,
            .pixels = &first_pixels,
        },
        .{
            .resource = second,
            .kind = .alpha_mask,
            .width = 2,
            .height = 2,
            .stride = 2,
            .pixels = &second_pixels,
        },
        .{
            .resource = image,
            .kind = .rgba,
            .width = 2,
            .height = 2,
            .stride = 8,
            .pixels = &image_pixels,
        },
    };
    const frame = Frame{
        .revision = 1,
        .uploads = &uploads,
        .removals = &.{},
        .commands = &.{},
    };
    try store.stage(frame);
    const plan = try builder.build(&store, frame);
    try std.testing.expectEqual(@as(usize, 0), plan.commands.len);

    try std.testing.expectEqual(
        FrameBuilder.Packed{
            .resource = first,
            .kind = .alpha_mask,
            .x = 1,
            .y = 1,
            .width = 2,
            .height = 2,
        },
        builder.entries[0],
    );
    try std.testing.expectEqual(
        FrameBuilder.Packed{
            .resource = second,
            .kind = .alpha_mask,
            .x = 5,
            .y = 1,
            .width = 2,
            .height = 2,
        },
        builder.entries[1],
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0x11, 0x11, 0x12, 0x12, 0x21, 0x21, 0x22, 0x22 },
        builder.alpha_pixels[0..8],
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0x11, 0x11, 0x12, 0x12, 0x21, 0x21, 0x22, 0x22 },
        builder.alpha_pixels[atlas_extent .. atlas_extent + 8],
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0x13, 0x13, 0x14, 0x14, 0x23, 0x23, 0x24, 0x24 },
        builder.alpha_pixels[atlas_extent * 2 .. atlas_extent * 2 + 8],
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0x13, 0x13, 0x14, 0x14, 0x23, 0x23, 0x24, 0x24 },
        builder.alpha_pixels[atlas_extent * 3 .. atlas_extent * 3 + 8],
    );

    const image_row = @as(usize, image_atlas_extent) * 4;
    try std.testing.expectEqualSlices(
        u8,
        &.{ 1, 2, 3, 4, 1, 2, 3, 4, 5, 6, 7, 8, 5, 6, 7, 8 },
        builder.rgba_pixels[0..16],
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 1, 2, 3, 4, 1, 2, 3, 4, 5, 6, 7, 8, 5, 6, 7, 8 },
        builder.rgba_pixels[image_row .. image_row + 16],
    );

    const uv = uvRect(builder.entries[0], null);
    try std.testing.expectEqual(@as(f32, 1.0 / 2048.0), uv[0]);
    try std.testing.expectEqual(@as(f32, 3.0 / 2048.0), uv[2]);
    // At 1.6x magnification the first physical fragment center maps before
    // the first source texel center, so linear filtering necessarily reads
    // one texel outside the resource. That texel now repeats the resource's
    // own edge rather than reading another resource or undefined atlas bytes.
    const first_source_coordinate = (0.5 / 3.2) * 2.0 - 0.5;
    try std.testing.expect(first_source_coordinate > -1.0);
    try std.testing.expect(first_source_coordinate < 0.0);
    try std.testing.expectEqual(@as(u8, 0x11), builder.alpha_pixels[atlas_extent]);
    try store.complete();
}

test "atlas gutter pressure rejects before reusable candidate completion" {
    var store = try ResidencyStore.init(
        std.testing.allocator,
        .{ .resources = 1, .pixel_bytes = atlas_extent - 1 },
    );
    defer store.deinit();
    var builder = try FrameBuilder.init(std.testing.allocator);
    defer builder.deinit();
    const pixels = try std.testing.allocator.alloc(u8, atlas_extent - 1);
    defer std.testing.allocator.free(pixels);
    @memset(pixels, 0xff);
    const resource = try ResourceGeneration.local(1, 1, 1);
    const too_wide = Frame{
        .revision = 1,
        .uploads = &.{.{
            .resource = resource,
            .kind = .alpha_mask,
            .width = atlas_extent - 1,
            .height = 1,
            .stride = atlas_extent - 1,
            .pixels = pixels,
        }},
        .removals = &.{},
        .commands = &.{},
    };
    try store.stage(too_wide);
    try std.testing.expectError(error.Capacity, builder.build(&store, too_wide));
    store.discard();

    const accepted = Frame{
        .revision = 2,
        .uploads = &.{.{
            .resource = resource,
            .kind = .alpha_mask,
            .width = 1,
            .height = 1,
            .stride = 1,
            .pixels = pixels[0..1],
        }},
        .removals = &.{},
        .commands = &.{},
    };
    try store.stage(accepted);
    const plan = try builder.build(&store, accepted);
    try std.testing.expectEqual(@as(usize, 0), plan.commands.len);
    try std.testing.expectEqual(@as(u16, 1), builder.entries[0].x);
    try std.testing.expectEqual(@as(u16, 1), builder.entries[0].y);
    try std.testing.expectEqual(@as(u8, 0xff), builder.alpha_pixels[0]);
    try std.testing.expectEqual(@as(u8, 0xff), builder.alpha_pixels[atlas_extent + 1]);
    try store.complete();
}

fn validateResource(resource: ResourceGeneration) ResidencyStore.StoreError!void {
    resource.validate() catch return error.InvalidFrame;
}

fn validateUpload(upload: Upload) ResidencyStore.StoreError!void {
    try validateResource(upload.resource);
    if (upload.kind == .solid or upload.width == 0 or upload.height == 0) return error.InvalidFrame;
    const bytes_per_pixel: usize = if (upload.kind == .alpha_mask) 1 else 4;
    const row = std.math.mul(usize, upload.width, bytes_per_pixel) catch return error.ArithmeticOverflow;
    if (upload.stride < row) return error.InvalidFrame;
    const bytes = std.math.mul(usize, upload.stride, upload.height) catch return error.ArithmeticOverflow;
    if (bytes != upload.pixels.len) return error.InvalidFrame;
}

fn validateRect(rect: Rect) ResidencyStore.StoreError!void {
    if (rect.width == 0 or rect.height == 0) return error.InvalidFrame;
}

fn sameIdentity(left: ResourceGeneration, right: ResourceGeneration) bool {
    return left.source == right.source and left.resource == right.resource;
}

fn findEntry(entries: []const ResidencyStore.Entry, key: ResourceGeneration) ?ResidencyStore.Entry {
    for (entries) |entry| if (sameIdentity(entry.resource, key)) return entry;
    return null;
}

fn findExactEntry(entries: []const ResidencyStore.Entry, resource: ResourceGeneration) ?ResidencyStore.Entry {
    for (entries) |entry| if (std.meta.eql(entry.resource, resource)) return entry;
    return null;
}

fn findUpload(uploads: []const Upload, key: ResourceGeneration) ?Upload {
    for (uploads) |upload| if (sameIdentity(upload.resource, key)) return upload;
    return null;
}

fn findRemoval(removals: []const Removal, key: ResourceGeneration) ?Removal {
    for (removals) |removal| if (sameIdentity(removal.resource, key)) return removal;
    return null;
}

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
    const binding = vk.VkVertexInputBindingDescription{ .stride = @sizeOf(Vertex) };
    const attributes = [_]vk.VkVertexInputAttributeDescription{
        .{ .location = 0, .format = vk.VK_FORMAT_R32G32_SFLOAT, .offset = @offsetOf(Vertex, "position") },
        .{ .location = 1, .format = vk.VK_FORMAT_R32G32_SFLOAT, .offset = @offsetOf(Vertex, "uv") },
        .{ .location = 2, .format = vk.VK_FORMAT_R32G32B32A32_SFLOAT, .offset = @offsetOf(Vertex, "color") },
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

test "pixel coordinates convert to Vulkan NDC without inversion drift" {
    try std.testing.expectEqual(@as([2]f32, .{ -1, 1 }), try pixelToNdc(.{ 0, 0 }, 100, 80));
    try std.testing.expectEqual(@as([2]f32, .{ 1, -1 }), try pixelToNdc(.{ 100, 80 }, 100, 80));
    try std.testing.expectEqual(@as([2]f32, .{ 0, 0 }), try pixelToNdc(.{ 50, 40 }, 100, 80));
    try std.testing.expectError(error.Buffer, pixelToNdc(.{ 0, 0 }, 0, 80));
    try std.testing.expectError(error.Buffer, pixelToNdc(.{ 0, 0 }, 100, 0));

    // Logical Canvas coordinates reach the physical framebuffer edges through
    // NDC while the attachment retains its independent physical extent.
    try std.testing.expectEqual(@as([2]f32, .{ 1, -1 }), try pixelToNdc(.{ 100, 80 }, 100, 80));
    const indices = [_]u16{ 0, 1, 2 };
    const integer_vertices = [_]Vertex{
        .{ .position = .{ 0, 0 }, .uv = .{ 0, 0 }, .color = .{ 1, 1, 1, 1 } },
        .{ .position = .{ 100, 0 }, .uv = .{ 0, 0 }, .color = .{ 1, 1, 1, 1 } },
        .{ .position = .{ 100, 80 }, .uv = .{ 0, 0 }, .color = .{ 1, 1, 1, 1 } },
    };
    try Context.validatePlan(.{
        .vertices = &integer_vertices,
        .indices = &indices,
        .commands = &.{.{ .kind = .solid, .first_index = 0, .index_count = 3, .clip = .{ .x = 0, .y = 0, .width = 100, .height = 80 } }},
    }, 100, 80);
    const fractional_vertices = [_]Vertex{
        .{ .position = .{ 0, 0 }, .uv = .{ 0, 0 }, .color = .{ 1, 1, 1, 1 } },
        .{ .position = .{ 100, 0 }, .uv = .{ 0, 0 }, .color = .{ 1, 1, 1, 1 } },
        .{ .position = .{ 100, 80 }, .uv = .{ 0, 0 }, .color = .{ 1, 1, 1, 1 } },
    };
    try Context.validatePlan(.{
        .vertices = &fractional_vertices,
        .indices = &indices,
        .commands = &.{.{ .kind = .solid, .first_index = 0, .index_count = 3, .clip = .{ .x = 0, .y = 0, .width = 100, .height = 80 } }},
    }, 100, 80);
}

test "clear-only plan records pending atlas facts and remains reusable" {
    var context = Context{};
    const plan = Plan{ .vertices = &.{}, .indices = &.{}, .commands = &.{}, .atlas_changed = true, .image_atlas_changed = true };
    const first = try context.preflightRecording(plan, 64, 64, 64, 64);
    try std.testing.expect(!context.atlas_initialized and !context.image_atlas_initialized);
    try std.testing.expect(first.alpha_initialized and first.image_initialized);
    context.complete(first);
    try std.testing.expect(context.atlas_initialized and context.image_atlas_initialized);
    const replacement = try context.preflightRecording(plan, 64, 64, 64, 64);
    try std.testing.expect(replacement.alpha_initialized and replacement.image_initialized);
    // A failed later recording does not call complete and therefore cannot
    // roll back established initialization or claim a new state.
    try std.testing.expect(context.atlas_initialized and context.image_atlas_initialized);
}

test "plan preflight rejects malformed relationships before mutation and permits reuse" {
    const clip = Rect{ .x = 0, .y = 0, .width = 4, .height = 4 };
    const vertices = [_]Vertex{
        .{ .position = .{ 0, 0 }, .uv = .{ 0, 0 }, .color = .{ 1, 1, 1, 1 } },
        .{ .position = .{ 1, 0 }, .uv = .{ 1, 0 }, .color = .{ 1, 1, 1, 1 } },
        .{ .position = .{ 1, 1 }, .uv = .{ 1, 1 }, .color = .{ 1, 1, 1, 1 } },
    };
    const indices = [_]u16{ 0, 1, 2 };
    const valid = Plan{
        .vertices = &vertices,
        .indices = &indices,
        .commands = &.{.{ .kind = .solid, .first_index = 0, .index_count = 3, .clip = clip }},
        .atlas_changed = false,
    };
    try Context.validatePlan(valid, 4, 4);

    var bad_index = indices;
    bad_index[2] = 3;
    try std.testing.expectError(error.InvalidPlan, Context.validatePlan(.{ .vertices = &vertices, .indices = &bad_index, .commands = valid.commands, .atlas_changed = false }, 4, 4));
    try std.testing.expectError(error.InvalidPlan, Context.validatePlan(.{ .vertices = &vertices, .indices = &indices, .commands = &.{.{ .kind = .solid, .first_index = 2, .index_count = 2, .clip = clip }}, .atlas_changed = false }, 4, 4));
    try std.testing.expectError(error.InvalidPlan, Context.validatePlan(.{ .vertices = &vertices, .indices = &indices, .commands = &.{.{ .kind = .solid, .first_index = 0, .index_count = 3, .clip = .{ .x = -1, .y = 0, .width = 1, .height = 1 } }}, .atlas_changed = false }, 4, 4));
    try std.testing.expectError(error.InvalidPlan, Context.validatePlan(.{ .vertices = &vertices, .indices = &indices, .commands = &.{.{ .kind = .solid, .first_index = 0, .index_count = 3, .clip = .{ .x = 3, .y = 0, .width = 2, .height = 1 } }}, .atlas_changed = false }, 4, 4));
    try std.testing.expectError(error.InvalidPlan, Context.validatePlan(.{ .vertices = &vertices, .indices = &indices, .commands = &.{.{ .kind = .solid, .first_index = 0, .index_count = 0, .clip = clip }}, .atlas_changed = false }, 4, 4));
    try std.testing.expectError(error.InvalidPlan, Context.validatePlan(.{ .vertices = &vertices, .indices = &.{}, .commands = &.{}, .atlas_changed = false }, 4, 4));
    try std.testing.expectError(error.InvalidPlan, Context.validatePlan(.{ .vertices = &.{}, .indices = &indices, .commands = &.{}, .atlas_changed = false }, 4, 4));
    try std.testing.expectError(error.InvalidPlan, Context.validatePlan(valid, 0, 4));
    try Context.validatePlan(valid, 4, 4);
}

test "recording preflight rejects a late collapsing physical scissor" {
    var context = Context{};
    const vertices = [_]Vertex{
        .{ .position = .{ 0, 0 }, .uv = .{ 0, 0 }, .color = .{ 1, 1, 1, 1 } },
        .{ .position = .{ 100, 0 }, .uv = .{ 0, 0 }, .color = .{ 1, 1, 1, 1 } },
        .{ .position = .{ 100, 10 }, .uv = .{ 0, 0 }, .color = .{ 1, 1, 1, 1 } },
    };
    const indices = [_]u16{ 0, 1, 2 };
    const commands = [_]Command{
        .{
            .kind = .solid,
            .first_index = 0,
            .index_count = 3,
            .clip = .{ .x = 0, .y = 0, .width = 50, .height = 10 },
        },
        .{
            .kind = .solid,
            .first_index = 0,
            .index_count = 3,
            .clip = .{ .x = 1, .y = 0, .width = 1, .height = 10 },
        },
    };
    const plan = Plan{
        .vertices = &vertices,
        .indices = &indices,
        .commands = &commands,
    };
    try std.testing.expectError(
        error.InvalidPlan,
        context.preflightRecording(plan, 100, 10, 1, 1),
    );
    try std.testing.expectError(
        error.InvalidPlan,
        context.preflightRecording(
            plan,
            100,
            10,
            @as(u32, @intCast(std.math.maxInt(i32))) + 1,
            10,
        ),
    );
    try std.testing.expect(!context.atlas_initialized);
    try std.testing.expect(!context.image_atlas_initialized);
}

test "record rejects malformed plans without changing atlas facts" {
    var context = Context{};
    const before_alpha = context.atlas_initialized;
    const before_image = context.image_atlas_initialized;
    const malformed = Plan{
        .vertices = &.{.{ .position = .{ 0, 0 }, .uv = .{ 0, 0 }, .color = .{ 1, 1, 1, 1 } }},
        .indices = &.{0},
        .commands = &.{.{ .kind = .solid, .first_index = 0, .index_count = 2, .clip = .{ .x = 0, .y = 0, .width = 1, .height = 1 } }},
        .atlas_changed = true,
        .image_atlas_changed = true,
    };
    try std.testing.expectError(error.InvalidPlan, context.record(null, .{}, 1, 1, 1, 1, malformed, .{ 0, 0, 0, 1 }));
    try std.testing.expectEqual(before_alpha, context.atlas_initialized);
    try std.testing.expectEqual(before_image, context.image_atlas_initialized);
    var mapped_bytes = [_]u8{ 0x5a, 0xa5 };
    context.mapped = mapped_bytes[0..].ptr;
    try std.testing.expectError(error.InvalidPlan, context.stage(malformed, &.{}, &.{}, 1, 1));
    try std.testing.expectEqualSlices(u8, &.{ 0x5a, 0xa5 }, &mapped_bytes);
    try std.testing.expectError(error.InvalidPlan, context.record(null, .{}, 1, 1, 1, 1, .{ .vertices = malformed.vertices, .indices = malformed.indices, .commands = &.{.{ .kind = .solid, .first_index = 0, .index_count = 1, .clip = .{ .x = 0, .y = 0, .width = 2, .height = 1 } }}, .atlas_changed = true }, .{ 0, 0, 0, 1 }));
    try Context.validatePlan(.{
        .vertices = &.{
            .{ .position = .{ 0, 0 }, .uv = .{ 0, 0 }, .color = .{ 1, 1, 1, 1 } },
            .{ .position = .{ 1, 0 }, .uv = .{ 1, 0 }, .color = .{ 1, 1, 1, 1 } },
            .{ .position = .{ 1, 1 }, .uv = .{ 1, 1 }, .color = .{ 1, 1, 1, 1 } },
        },
        .indices = &.{ 0, 1, 2 },
        .commands = &.{.{ .kind = .solid, .first_index = 0, .index_count = 3, .clip = .{ .x = 0, .y = 0, .width = 1, .height = 1 } }},
        .atlas_changed = false,
    }, 1, 1);
}
