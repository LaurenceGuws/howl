//! Owns retained terminal-cell GPU shadows and exact sparse Vulkan commands.
//!
//! The package does not own Render publication or submission policy. It owns
//! one accepted instance and row shadow, bounded sparse candidates, shared
//! font-epoch glyph residency, exact Vulkan resources, sparse transfers, and
//! bounded pane draws. Inputs are already-resolved backend instances and
//! stable glyph slots. The Host adapter owns semantic Cell/Glyph conversion,
//! placement qualification, batching, submission, and publication policy.

const std = @import("std");
const vk = @import("abi.zig");
const maximum_cells: usize = 65_536;
const maximum_panes: usize = 64;
const maximum_instance_staging_bytes: usize = maximum_panes * maximum_cells * @sizeOf(Instance);
const maximum_row_staging_bytes: usize = maximum_panes * 128 * @sizeOf(u32);
const row_staging_offset: usize = maximum_instance_staging_bytes;
const batch_staging_bytes: usize = row_staging_offset + maximum_row_staging_bytes;
const terminal_vertex_shader align(4) = @embedFile("shaders/terminal.vert.spv").*;
const terminal_fragment_shader align(4) = @embedFile("shaders/terminal.frag.spv").*;

/// Maximum stable glyph slots exposed by the retained backend atlas.
pub const glyph_slots: usize = 95 * 4;
/// Exact shared mapped-staging byte capacity consumed by Host batch proofs.
pub const staging_byte_limit: usize = batch_staging_bytes;
/// Number of stable atlas columns used by mechanical slot placement.
pub const glyph_atlas_columns: u16 = 20;
pub const glyph_atlas_rows: u16 = 19;
pub const blank_glyph: u16 = std.math.maxInt(u16);

/// Maps one printable ASCII/style identity to its stable shared-font slot.
pub fn stableGlyphSlot(codepoint: u8, bold: bool, italic: bool) error{InvalidIdentity}!u16 {
    if (codepoint < 0x20 or codepoint > 0x7e) return error.InvalidIdentity;
    const style: u16 = @as(u16, @intFromBool(bold)) |
        (@as(u16, @intFromBool(italic)) << 1);
    return style * 95 + (@as(u16, codepoint) - 0x20);
}

/// Stores shader-ready resolved style flags.
pub const InstanceFlags = packed struct(u16) {
    /// Applies the resolved bold presentation bit.
    bold: bool = false,
    /// Requests dim foreground presentation.
    dim: bool = false,
    /// Applies the resolved italic presentation bit.
    italic: bool = false,
    /// Requests one static underline.
    underline: bool = false,
    /// Requests one static strike line.
    strikethrough: bool = false,
    /// Retains exact packed ABI space for reviewed extensions.
    reserved: u11 = 0,
};

/// Stores one persistent terminal cell consumed by the terminal pipeline.
pub const Instance = extern struct {
    /// Selects one stable glyph slot or the canonical blank sentinel.
    glyph_slot: u16,
    /// Stores shader-visible static style.
    flags: InstanceFlags,
    /// Stores packed RGBA foreground.
    foreground: u32,
    /// Stores packed RGBA background.
    background: u32,
    /// Stores packed RGBA underline color.
    underline_color: u32,
};

/// Selects one static cursor shape in backend draw terms.
pub const CursorShape = enum(u8) { block, underline, bar, hidden };

/// Supplies resolved static cursor draw data without semantic color policy.
pub const CursorDraw = extern struct {
    /// Selects the logical cursor row.
    row: u16 = 0,
    /// Selects the logical cursor column.
    col: u16 = 0,
    /// Stores packed RGBA cursor fill.
    color: u32 = 0,
    /// Stores packed RGBA text beneath a block cursor.
    text_color: u32 = 0,
    /// Selects the backend cursor geometry.
    shape: CursorShape = .hidden,
    /// Reports whether cursor geometry contributes to the draw.
    visible: bool = false,
};

/// Selects the only complete persistent-instance replacement entry points.
pub const ReplacementKind = enum { initialization, resize, alternate_grid };

/// Rotates one contiguous logical-row range over persistent physical rows.
pub const RowRotation = struct {
    /// Selects the first logical row in the rotated range.
    first: u16,
    /// Bounds the contiguous logical-row range.
    count: u16,
    /// Rotates the range by this signed logical-row distance.
    shift: i16,
};

/// Repeats one resolved instance over an exact physical-cell span.
pub const Fill = struct {
    /// Selects the first physical persistent-instance destination.
    first: u32,
    /// Bounds the contiguous physical destination span.
    count: u32,
    /// Supplies the resolved instance repeated over the span.
    instance: Instance,
};

/// Replaces one exact physical cell with one resolved instance.
pub const CellWriteInput = struct {
    /// Selects one physical persistent-instance destination.
    physical_index: u32,
    /// Supplies the resolved replacement instance.
    instance: Instance,
};

/// Borrows complete resolved instances for explicit replacement only.
pub const Replacement = struct {
    /// Classifies the explicit full-state ownership transition.
    kind: ReplacementKind,
    /// Supplies the replacement logical row count.
    rows: u16,
    /// Supplies the replacement logical column count.
    cols: u16,
    /// Borrows exactly `rows * cols` resolved instances.
    instances: []const Instance,
};

/// Borrows one complete backend update prepared by the Host terminal GPU adapter.
pub const Update = struct {
    /// Supplies the retained logical row count after this update.
    rows: u16,
    /// Supplies the retained logical column count after this update.
    cols: u16,
    /// Borrows a complete state only for explicit replacement.
    replacement: ?Replacement,
    /// Borrows ordered row-indirection mutations.
    row_rotations: []const RowRotation,
    /// Borrows ordered contiguous physical instance writes.
    fills: []const Fill,
    /// Borrows ordered individual physical instance writes.
    cells: []const CellWriteInput,
    /// Borrows stable glyph slots required by the candidate instances.
    glyph_slots: []const u16,
    /// Supplies the newest resolved static cursor draw, when changed.
    cursor: ?CursorDraw,
};

comptime {
    std.debug.assert(@sizeOf(Instance) == 16);
    std.debug.assert(@alignOf(Instance) == 4);
}

/// Supplies one completed raster for an exact stable glyph identity.
pub const GlyphRaster = struct {
    /// Qualifies the stable atlas slot.
    slot: u16,
    /// Bounds copied mask columns.
    width: u16,
    /// Bounds copied mask rows.
    height: u16,
    /// Supplies source bytes per row.
    stride: usize,
    /// Borrows exactly `stride * height` alpha bytes.
    pixels: []const u8,
};

/// Identifies one first-use upload copied into the fixed glyph atlas.
pub const GlyphUpload = struct {
    /// Qualifies the first-use raster.
    slot: u16,
    /// Borrows the candidate-owned copied alpha bytes.
    pixels: []const u8,
    /// Supplies the exact Vulkan buffer-to-image region.
    region: vk.VkBufferImageCopy,
};

/// Describes one instanced terminal draw independent of generic Canvas Plan.
pub const Draw = struct {
    /// Uses two triangles generated by the terminal vertex pipeline.
    vertex_count: u32 = 6,
    /// Draws one instance for each active logical cell.
    instance_count: u32,
    /// Keeps the terminal pane as one bounded draw group.
    group_count: u32 = 1,
    /// Supplies static cursor state without generic-plan replay.
    cursor: CursorDraw,
    /// Places the pane in physical attachment pixels.
    origin_x: i32 = 0,
    origin_y: i32 = 0,
    /// Clips the pane in physical attachment pixels.
    clip_x: i32 = 0,
    clip_y: i32 = 0,
    clip_width: u32 = 0,
    clip_height: u32 = 0,
    /// Supplies the exact terminal cell and font-line geometry.
    cell_width: u16 = 0,
    cell_height: u16 = 0,
    baseline: u16 = 0,
    underline_y: u16 = 0,
    underline_height: u16 = 0,
    strike_y: u16 = 0,
    strike_height: u16 = 0,
};

/// Borrows exact candidate transfers until `Store.complete` or `Store.discard`.
pub const Prepared = struct {
    /// Supplies active logical rows.
    rows: u16,
    /// Supplies active logical columns.
    cols: u16,
    /// Names the only path that uploads every active cell, when present.
    replacement: ?ReplacementKind,
    /// Supplies exact mapped instance-staging bytes required by this candidate.
    instance_staging_bytes: usize,
    /// Borrows exact sparse staging-to-persistent buffer regions.
    instance_copies: []const vk.VkBufferCopy,
    /// Borrows a complete small row map only when indirection changes.
    row_map: []const u32,
    /// Supplies the exact row-map buffer copy when present.
    row_copy: ?vk.VkBufferCopy,
    /// Supplies one bounded terminal-pane draw.
    draw: Draw,
};

/// Borrows caller-owned persistently mapped staging partitions.
pub const MappedStaging = struct {
    /// Receives `Prepared.instance_staging_bytes` at offset zero.
    instances: []u8,
    /// Receives the byte representation of `Prepared.row_map` at offset zero.
    rows: []u8,
};

/// Supplies checked byte origins inside the one shared mapped batch staging
/// allocation.
pub const StagingOffsets = struct {
    instances: usize,
    rows: usize,
};

/// Borrows compatible Vulkan handles for sparse terminal commands.
///
/// The caller owns creation, barriers, render-pass compatibility, submission,
/// completion, and destruction. The terminal package owns only exact copies
/// and one instanced draw command over these qualified handles.
pub const CommandBindings = struct {
    /// Supplies the mapped instance staging buffer.
    instance_staging: vk.VkBuffer,
    /// Supplies persistent shader-visible terminal instances.
    instance_storage: vk.VkBuffer,
    /// Supplies the mapped row-map staging buffer.
    row_staging: vk.VkBuffer,
    /// Supplies persistent shader-visible row indirection.
    row_storage: vk.VkBuffer,
    /// Supplies the shared font-epoch glyph atlas.
    glyph_atlas: vk.VkImage,
    /// Supplies the compatible terminal graphics pipeline.
    pipeline: vk.VkPipeline,
    /// Supplies its descriptor-compatible pipeline layout.
    layout: vk.VkPipelineLayout,
    /// Binds persistent instances, row map, and glyph atlas.
    descriptor: vk.VkDescriptorSet,
};

/// Names the exact terminal-only resources written into one pane descriptor.
///
/// This is a construction record, not a Vulkan execution claim. `createPane`
/// consumes it to write bindings 0..2, and `bindings` consumes the same owner
/// tuple before a Store can record its draw.
pub const DescriptorBindingFacts = struct {
    descriptor: vk.VkDescriptorSet,
    instance_buffer: vk.VkBuffer,
    instance_range: vk.VkDeviceSize,
    row_buffer: vk.VkBuffer,
    row_range: vk.VkDeviceSize,
    sampler: vk.VkSampler,
    atlas_view: vk.VkImageView,
    atlas_image: vk.VkImage,
};

/// Fixes retained cells, rows, sparse work, and glyph staging at init.
pub const Limits = struct {
    /// Bounds persistent row indirection.
    rows: u16,
    /// Bounds persistent instances per row.
    cols: u16,
    /// Bounds individual sparse cell transfers.
    sparse_cell_updates: usize,
    /// Bounds fill and row-indirection work.
    structured_updates: usize,
};

/// Returns exact retained CPU bytes requested by one Store configuration.
/// Caller-mapped staging and Host-owned physical GPU allocations are excluded.
pub fn retainedCpuBytes(limits: Limits) Error!usize {
    const cells = try validateLimits(limits);
    const rows: usize = limits.rows;
    const sparse = limits.sparse_cell_updates;
    const structured = limits.structured_updates;
    var total: usize = @sizeOf(Store);
    inline for (.{
        cells * @sizeOf(Instance),
        rows * @sizeOf(u32),
        rows * @sizeOf(u32),
        (sparse + structured + 1) * @sizeOf(vk.VkBufferCopy),
        sparse * @sizeOf(CellWrite),
        structured * @sizeOf(FillWrite),
    }) |bytes| total = std.math.add(usize, total, bytes) catch return error.InvalidLimits;
    return total;
}

/// Returns exact logical payload bytes Host-owned GPU resources must expose.
/// Vulkan allocation padding and device execution remain unclaimed.
pub fn physicalPayloadBytes(limits: Limits) Error!struct {
    instances: usize,
    row_map: usize,
} {
    const cells = try validateLimits(limits);
    return .{
        .instances = std.math.mul(usize, cells, @sizeOf(Instance)) catch return error.InvalidLimits,
        .row_map = std.math.mul(usize, limits.rows, @sizeOf(u32)) catch return error.InvalidLimits,
    };
}

/// Reports exact retained-store construction and candidate preparation errors.
pub const Error = error{
    InvalidLimits,
    InvalidGeometry,
    InvalidIdentity,
    SparseUpdateLimit,
    StructuredUpdateLimit,
    GlyphUnavailable,
    InvalidGlyphRaster,
    GlyphUploadLimit,
    CandidatePending,
    NoCandidate,
    OutOfMemory,
    GpuMemoryLimit,
    MemoryType,
    Buffer,
    Image,
    ImageView,
    Shader,
    Descriptor,
    Pipeline,
    StagingMap,
};

const CellWrite = struct { index: usize, instance: Instance };
const FillWrite = struct { first: usize, count: usize, instance: Instance };

/// Retains one exact font epoch's accepted glyph residency and one first-use
/// upload candidate. Pane Stores borrow this owner and never duplicate its
/// atlas state.
pub const FontGpu = struct {
    allocator: std.mem.Allocator,
    limits: FontLimits,
    resident: []u64,
    candidate: []u64,
    pixels: []u8,
    pixel_count: usize = 0,
    uploads: []GlyphUpload,
    upload_count: usize = 0,
    pending: bool = false,
    atlas_initialized: bool = false,
    transfer_recorded: bool = false,
    initialization_recorded: bool = false,
    image: vk.VkImage = null,
    memory: vk.VkDeviceMemory = null,
    view: vk.VkImageView = null,
    staging_buffer: vk.VkBuffer = null,
    staging_memory: vk.VkDeviceMemory = null,
    mapped: ?[*]u8 = null,
    owned_bytes: u64 = 0,

    /// Allocates fixed residency and maximum first-use upload storage.
    pub fn init(allocator: std.mem.Allocator, limits: FontLimits) Error!FontGpu {
        _ = try glyphAtlasExtent(limits);
        const words = (glyph_slots + 63) / 64;
        const tile_bytes = std.math.mul(
            usize,
            limits.glyph_width,
            limits.glyph_height,
        ) catch return error.InvalidLimits;
        const aligned_tile = std.math.add(usize, tile_bytes, 3) catch
            return error.InvalidLimits;
        const pixel_capacity = std.math.mul(usize, glyph_slots, aligned_tile) catch
            return error.InvalidLimits;
        const resident = allocator.alloc(u64, words) catch return error.OutOfMemory;
        errdefer allocator.free(resident);
        const candidate = allocator.alloc(u64, words) catch return error.OutOfMemory;
        errdefer allocator.free(candidate);
        const pixels = allocator.alloc(u8, pixel_capacity) catch return error.OutOfMemory;
        errdefer allocator.free(pixels);
        const uploads = allocator.alloc(GlyphUpload, glyph_slots) catch return error.OutOfMemory;
        @memset(resident, 0);
        @memset(candidate, 0);
        return .{
            .allocator = allocator,
            .limits = limits,
            .resident = resident,
            .candidate = candidate,
            .pixels = pixels,
            .uploads = uploads,
        };
    }

    /// Releases fixed candidate and residency storage in reverse order.
    pub fn deinit(self: *FontGpu) void {
        std.debug.assert(self.image == null and self.memory == null and
            self.view == null and self.staging_buffer == null and
            self.staging_memory == null and self.mapped == null and
            self.owned_bytes == 0);
        self.allocator.free(self.uploads);
        self.allocator.free(self.pixels);
        self.allocator.free(self.candidate);
        self.allocator.free(self.resident);
        self.* = undefined;
    }

    /// Creates one exact atlas and mapped upload buffer under the caller's
    /// checked GPU budget. CPU residency remains unchanged on failure.
    pub fn initPhysical(
        self: *FontGpu,
        device: vk.VkDevice,
        properties: vk.VkPhysicalDeviceMemoryProperties,
        gpu_bytes: *u64,
        limit: u64,
    ) Error!void {
        if (self.image != null or self.memory != null or self.view != null or
            self.staging_buffer != null or self.staging_memory != null or
            self.mapped != null or self.owned_bytes != 0)
            return error.InvalidIdentity;
        errdefer self.deinitPhysical(device, gpu_bytes);
        const extent = try glyphAtlasExtent(self.limits);
        var image_info = vk.VkImageCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .imageType = vk.VK_IMAGE_TYPE_2D,
            .format = vk.VK_FORMAT_R8_UNORM,
            .extent = .{ .width = extent.width, .height = extent.height, .depth = 1 },
            .mipLevels = 1,
            .arrayLayers = 1,
            .samples = vk.VK_SAMPLE_COUNT_1_BIT,
            .tiling = 0,
            .usage = vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.VK_IMAGE_USAGE_SAMPLED_BIT,
            .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
            .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
        };
        if (vk.vkCreateImage(device, &image_info, null, &self.image) != vk.VK_SUCCESS)
            return error.Image;
        var image_requirements: vk.VkMemoryRequirements = undefined;
        vk.vkGetImageMemoryRequirements(device, self.image, &image_requirements);
        try chargeBytes(&self.owned_bytes, gpu_bytes, image_requirements.size, limit);
        var image_allocation = vk.VkMemoryAllocateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .allocationSize = image_requirements.size,
            .memoryTypeIndex = try memoryType(
                properties,
                image_requirements.memoryTypeBits,
                vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
            ),
        };
        if (vk.vkAllocateMemory(device, &image_allocation, null, &self.memory) != vk.VK_SUCCESS or
            vk.vkBindImageMemory(device, self.image, self.memory, 0) != vk.VK_SUCCESS)
            return error.Image;
        var view_info = vk.VkImageViewCreateInfo{
            .image = self.image,
            .format = vk.VK_FORMAT_R8_UNORM,
            .subresourceRange = .{
                .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };
        if (vk.vkCreateImageView(device, &view_info, null, &self.view) != vk.VK_SUCCESS)
            return error.ImageView;

        var buffer_info = vk.VkBufferCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = self.pixels.len,
            .usage = vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
        };
        if (vk.vkCreateBuffer(device, &buffer_info, null, &self.staging_buffer) != vk.VK_SUCCESS)
            return error.Buffer;
        var staging_requirements: vk.VkMemoryRequirements = undefined;
        vk.vkGetBufferMemoryRequirements(device, self.staging_buffer, &staging_requirements);
        try chargeBytes(&self.owned_bytes, gpu_bytes, staging_requirements.size, limit);
        var staging_allocation = vk.VkMemoryAllocateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .allocationSize = staging_requirements.size,
            .memoryTypeIndex = try memoryType(
                properties,
                staging_requirements.memoryTypeBits,
                vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            ),
        };
        if (vk.vkAllocateMemory(device, &staging_allocation, null, &self.staging_memory) != vk.VK_SUCCESS or
            vk.vkBindBufferMemory(device, self.staging_buffer, self.staging_memory, 0) != vk.VK_SUCCESS)
            return error.Buffer;
        var mapped: ?*u8 = null;
        if (vk.vkMapMemory(device, self.staging_memory, 0, staging_requirements.size, 0, &mapped) != vk.VK_SUCCESS or
            mapped == null)
            return error.StagingMap;
        self.mapped = @ptrCast(mapped.?);
    }

    /// Destroys mapped staging then the atlas and removes exact charged bytes.
    pub fn deinitPhysical(self: *FontGpu, device: vk.VkDevice, gpu_bytes: *u64) void {
        if (self.mapped != null and self.staging_memory != null)
            vk.vkUnmapMemory(device, self.staging_memory);
        if (self.staging_buffer != null)
            vk.vkDestroyBuffer(device, self.staging_buffer, null);
        if (self.staging_memory != null)
            vk.vkFreeMemory(device, self.staging_memory, null);
        if (self.view != null) vk.vkDestroyImageView(device, self.view, null);
        if (self.image != null) vk.vkDestroyImage(device, self.image, null);
        if (self.memory != null) vk.vkFreeMemory(device, self.memory, null);
        gpu_bytes.* -= self.owned_bytes;
        self.image = null;
        self.memory = null;
        self.view = null;
        self.staging_buffer = null;
        self.staging_memory = null;
        self.mapped = null;
        self.owned_bytes = 0;
        self.atlas_initialized = false;
    }

    /// Prepares the distinct nonresident slots in one exact batch.
    pub fn prepare(
        self: *FontGpu,
        slots: []const u16,
        rasters: []const GlyphRaster,
    ) Error!void {
        if (self.pending) return error.CandidatePending;
        self.resetCandidate();
        errdefer self.resetCandidate();
        for (slots) |slot| {
            if (slot >= glyph_slots) return error.InvalidIdentity;
            if (bit(self.resident, slot) or bit(self.candidate, slot)) continue;
            const raster = findGlyphRaster(rasters, slot) orelse
                return error.GlyphUnavailable;
            try self.stageGlyph(slot, raster);
        }
        self.pending = true;
    }

    /// Reports whether a slot is accepted or belongs to the current candidate.
    pub fn available(self: *const FontGpu, slot: u16) bool {
        return slot < glyph_slots and
            (bit(self.resident, slot) or bit(self.candidate, slot));
    }

    /// Borrows the exact candidate uploads for batch staging and recording.
    pub fn prepared(self: *const FontGpu) Error!struct {
        pixels: []const u8,
        uploads: []const GlyphUpload,
    } {
        if (!self.pending) return error.NoCandidate;
        return .{
            .pixels = self.pixels[0..self.pixel_count],
            .uploads = self.uploads[0..self.upload_count],
        };
    }

    /// Copies the complete candidate after validating the mapped partition.
    pub fn stageMapped(self: *const FontGpu, mapped: []u8) Error!void {
        const candidate = try self.prepared();
        if (candidate.pixels.len > mapped.len) return error.GlyphUploadLimit;
        @memcpy(mapped[0..candidate.pixels.len], candidate.pixels);
    }

    /// Stages into this font epoch's owned mapped upload buffer.
    pub fn stagePhysical(self: *const FontGpu) Error!void {
        const mapped = self.mapped orelse return error.StagingMap;
        const candidate = try self.prepared();
        try self.stageMapped(mapped[0..candidate.pixels.len]);
    }

    /// Records one font candidate's transitions and first-use atlas copies.
    pub fn recordTransfers(self: *FontGpu, command: vk.VkCommandBuffer) Error!void {
        if (command == null or self.image == null or self.staging_buffer == null)
            return error.InvalidIdentity;
        var recorder = FontCommandRecorder{ .vulkan = command };
        try self.recordTransferCommands(
            &recorder,
            self.staging_buffer,
            self.image,
        );
    }

    fn recordTransferCommands(
        self: *FontGpu,
        recorder: *FontCommandRecorder,
        staging_buffer: vk.VkBuffer,
        image: vk.VkImage,
    ) Error!void {
        const candidate = try self.prepared();
        if (self.transfer_recorded) return error.InvalidIdentity;
        if (self.atlas_initialized and candidate.uploads.len == 0) {
            self.transfer_recorded = true;
            return;
        }
        const range = vk.VkImageSubresourceRange{
            .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        };
        var barrier = vk.VkImageMemoryBarrier{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            .oldLayout = if (self.atlas_initialized)
                vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
            else
                vk.VK_IMAGE_LAYOUT_UNDEFINED,
            .newLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
            .image = image,
            .subresourceRange = range,
            .srcAccessMask = if (self.atlas_initialized) vk.VK_ACCESS_SHADER_READ_BIT else 0,
            .dstAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT,
        };
        if (candidate.uploads.len == 0) {
            barrier.newLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
            barrier.dstAccessMask = vk.VK_ACCESS_SHADER_READ_BIT;
            recorder.barrier(
                vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
                vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
                barrier,
            );
            self.transfer_recorded = true;
            self.initialization_recorded = true;
            return;
        }
        recorder.barrier(
            if (self.atlas_initialized) vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT else vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
            vk.VK_PIPELINE_STAGE_TRANSFER_BIT,
            barrier,
        );
        var regions: [glyph_slots]vk.VkBufferImageCopy = undefined;
        for (candidate.uploads, 0..) |upload, index| regions[index] = upload.region;
        recorder.copyBufferToImage(
            staging_buffer,
            image,
            vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            regions[0..candidate.uploads.len],
        );
        barrier.srcAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.dstAccessMask = vk.VK_ACCESS_SHADER_READ_BIT;
        barrier.oldLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        barrier.newLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        recorder.barrier(
            vk.VK_PIPELINE_STAGE_TRANSFER_BIT,
            vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
            barrier,
        );
        self.transfer_recorded = true;
        self.initialization_recorded = !self.atlas_initialized;
    }

    /// Accepts first-use residency only after observed GPU completion.
    pub fn complete(self: *FontGpu) Error!void {
        if (!self.pending) return error.NoCandidate;
        if (self.image != null and !self.transfer_recorded)
            return error.NoCandidate;
        for (self.candidate, 0..) |word, index| self.resident[index] |= word;
        if (self.initialization_recorded) self.atlas_initialized = true;
        self.pending = false;
        self.resetCandidate();
    }

    /// Rejects first-use uploads without changing accepted residency.
    pub fn discard(self: *FontGpu) Error!void {
        if (!self.pending) return error.NoCandidate;
        self.pending = false;
        self.resetCandidate();
    }

    /// Reports accepted residency for deterministic owner proofs.
    pub fn glyphResident(self: *const FontGpu, slot: u16) bool {
        return slot < glyph_slots and bit(self.resident, slot);
    }

    /// Reports exact candidate ownership for combined completion preflight.
    pub fn candidatePending(self: *const FontGpu) bool {
        return self.pending;
    }

    /// Reports whether physical completion can mutate accepted residency and
    /// layout state without a later fallible transition.
    pub fn completionReady(self: *const FontGpu) bool {
        return self.pending and (self.image == null or self.transfer_recorded);
    }

    fn stageGlyph(self: *FontGpu, slot: usize, raster: GlyphRaster) Error!void {
        if (raster.slot != slot or raster.width == 0 or raster.height == 0 or
            raster.width > self.limits.glyph_width or
            raster.height > self.limits.glyph_height or
            raster.stride < raster.width)
            return error.InvalidGlyphRaster;
        const bytes = std.math.mul(usize, raster.stride, raster.height) catch
            return error.InvalidGlyphRaster;
        if (raster.pixels.len != bytes) return error.InvalidGlyphRaster;
        const offset = std.mem.alignForward(usize, self.pixel_count, 4);
        const next = std.math.add(usize, offset, bytes) catch
            return error.GlyphUploadLimit;
        if (next > self.pixels.len or self.upload_count == self.uploads.len)
            return error.GlyphUploadLimit;
        @memset(self.pixels[self.pixel_count..offset], 0);
        @memcpy(self.pixels[offset..next], raster.pixels);
        const tile = try glyphTile(slot, self.limits);
        self.uploads[self.upload_count] = .{
            .slot = @intCast(slot),
            .pixels = self.pixels[offset..next],
            .region = .{
                .bufferOffset = offset,
                .bufferRowLength = @intCast(raster.stride),
                .bufferImageHeight = raster.height,
                .imageSubresource = .{
                    .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                    .mipLevel = 0,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                },
                .imageOffset = .{
                    .x = @intCast(tile.x),
                    .y = @intCast(tile.y),
                    .z = 0,
                },
                .imageExtent = .{
                    .width = raster.width,
                    .height = raster.height,
                    .depth = 1,
                },
            },
        };
        self.upload_count += 1;
        self.pixel_count = next;
        setBit(self.candidate, slot);
    }

    fn resetCandidate(self: *FontGpu) void {
        @memset(self.candidate, 0);
        self.pixel_count = 0;
        self.upload_count = 0;
        self.transfer_recorded = false;
        self.initialization_recorded = false;
    }
};

const FontBarrierCommand = struct {
    source_stage: vk.VkPipelineStageFlags,
    destination_stage: vk.VkPipelineStageFlags,
    barrier: vk.VkImageMemoryBarrier,
};

const FontTransferProof = struct {
    barriers: [2]FontBarrierCommand = undefined,
    barrier_count: u8 = 0,
    copies: [glyph_slots]vk.VkBufferImageCopy = undefined,
    copy_count: u16 = 0,
};

const FontCommandRecorder = union(enum) {
    vulkan: vk.VkCommandBuffer,
    proof: *FontTransferProof,

    fn barrier(
        self: *FontCommandRecorder,
        source_stage: vk.VkPipelineStageFlags,
        destination_stage: vk.VkPipelineStageFlags,
        barrier_value: vk.VkImageMemoryBarrier,
    ) void {
        switch (self.*) {
            .vulkan => |command| vk.vkCmdPipelineBarrier(
                command,
                source_stage,
                destination_stage,
                0,
                0,
                null,
                0,
                null,
                1,
                &barrier_value,
            ),
            .proof => |receipt| {
                std.debug.assert(receipt.barrier_count < receipt.barriers.len);
                receipt.barriers[receipt.barrier_count] = .{
                    .source_stage = source_stage,
                    .destination_stage = destination_stage,
                    .barrier = barrier_value,
                };
                receipt.barrier_count += 1;
            },
        }
    }

    fn copyBufferToImage(
        self: *FontCommandRecorder,
        staging_buffer: vk.VkBuffer,
        image: vk.VkImage,
        layout: vk.VkImageLayout,
        regions: []const vk.VkBufferImageCopy,
    ) void {
        switch (self.*) {
            .vulkan => |command| vk.vkCmdCopyBufferToImage(
                command,
                staging_buffer,
                image,
                layout,
                @intCast(regions.len),
                regions.ptr,
            ),
            .proof => |receipt| {
                std.debug.assert(receipt.copy_count == 0 and
                    regions.len <= receipt.copies.len);
                @memcpy(receipt.copies[0..regions.len], regions);
                receipt.copy_count = @intCast(regions.len);
            },
        }
    }
};

const BufferCopyCommand = struct {
    source: vk.VkBuffer,
    destination: vk.VkBuffer,
    region: vk.VkBufferCopy,
};

const BufferTransferProof = struct {
    copies: [4]BufferCopyCommand = undefined,
    copy_count: u8 = 0,
    barriers: [2]vk.VkBufferMemoryBarrier = undefined,
    barrier_count: u8 = 0,
};

const BufferCommandRecorder = union(enum) {
    vulkan: vk.VkCommandBuffer,
    proof: *BufferTransferProof,

    fn copyBuffer(
        self: *BufferCommandRecorder,
        source: vk.VkBuffer,
        destination: vk.VkBuffer,
        region: vk.VkBufferCopy,
    ) void {
        switch (self.*) {
            .vulkan => |command| vk.vkCmdCopyBuffer(command, source, destination, 1, &region),
            .proof => |receipt| {
                std.debug.assert(receipt.copy_count < receipt.copies.len);
                receipt.copies[receipt.copy_count] = .{
                    .source = source,
                    .destination = destination,
                    .region = region,
                };
                receipt.copy_count += 1;
            },
        }
    }

    fn barrier(
        self: *BufferCommandRecorder,
        barriers: []const vk.VkBufferMemoryBarrier,
    ) void {
        if (barriers.len == 0) return;
        switch (self.*) {
            .vulkan => |command| vk.vkCmdPipelineBarrier(
                command,
                vk.VK_PIPELINE_STAGE_TRANSFER_BIT,
                vk.VK_PIPELINE_STAGE_VERTEX_SHADER_BIT,
                0,
                0,
                null,
                @intCast(barriers.len),
                barriers.ptr,
                0,
                null,
            ),
            .proof => |receipt| {
                std.debug.assert(receipt.barrier_count == 0 and
                    barriers.len <= receipt.barriers.len);
                @memcpy(receipt.barriers[0..barriers.len], barriers);
                receipt.barrier_count = @intCast(barriers.len);
            },
        }
    }
};

fn findGlyphRaster(rasters: []const GlyphRaster, slot: u16) ?GlyphRaster {
    for (rasters) |raster| if (raster.slot == slot) return raster;
    return null;
}

/// Owns one pane's exact persistent instance/row buffers and descriptor.
pub const PaneResources = struct {
    instance_buffer: vk.VkBuffer = null,
    instance_memory: vk.VkDeviceMemory = null,
    row_buffer: vk.VkBuffer = null,
    row_memory: vk.VkDeviceMemory = null,
    descriptor: vk.VkDescriptorSet = null,
    instance_bytes: usize = 0,
    row_bytes: usize = 0,
    owned_bytes: u64 = 0,
    descriptor_set_identity: vk.VkDescriptorSet = null,
    descriptor_instance_buffer: vk.VkBuffer = null,
    descriptor_row_buffer: vk.VkBuffer = null,
    descriptor_instance_range: vk.VkDeviceSize = 0,
    descriptor_row_range: vk.VkDeviceSize = 0,
    descriptor_sampler: vk.VkSampler = null,
    descriptor_atlas_view: vk.VkImageView = null,
    descriptor_atlas_image: vk.VkImage = null,

    /// Retains the exact terminal resources written into this descriptor once.
    fn retainDescriptorBindings(
        self: *PaneResources,
        facts: DescriptorBindingFacts,
    ) Error!void {
        if (self.descriptor_set_identity != null or
            self.descriptor_instance_buffer != null or
            self.descriptor_row_buffer != null or
            self.descriptor_instance_range != 0 or self.descriptor_row_range != 0 or
            self.descriptor_sampler != null or self.descriptor_atlas_view != null or
            self.descriptor_atlas_image != null)
            return error.InvalidIdentity;
        self.descriptor_set_identity = facts.descriptor;
        self.descriptor_instance_buffer = facts.instance_buffer;
        self.descriptor_row_buffer = facts.row_buffer;
        self.descriptor_instance_range = facts.instance_range;
        self.descriptor_row_range = facts.row_range;
        self.descriptor_sampler = facts.sampler;
        self.descriptor_atlas_view = facts.atlas_view;
        self.descriptor_atlas_image = facts.atlas_image;
    }

    /// Rejects any later tuple that does not describe this exact descriptor.
    fn validateDescriptorBindings(
        self: *const PaneResources,
        facts: DescriptorBindingFacts,
    ) Error!void {
        if (facts.descriptor != self.descriptor_set_identity or
            facts.instance_buffer != self.descriptor_instance_buffer or
            facts.row_buffer != self.descriptor_row_buffer or
            facts.instance_range != self.descriptor_instance_range or
            facts.row_range != self.descriptor_row_range or
            facts.sampler != self.descriptor_sampler or
            facts.atlas_view != self.descriptor_atlas_view or
            facts.atlas_image != self.descriptor_atlas_image)
            return error.InvalidIdentity;
    }

    /// Releases the descriptor and exact buffers in reverse construction order.
    pub fn deinit(
        self: *PaneResources,
        device: vk.VkDevice,
        descriptor_pool: vk.VkDescriptorPool,
        gpu_bytes: *u64,
    ) void {
        if (self.descriptor != null) {
            const result = vk.vkFreeDescriptorSets(device, descriptor_pool, 1, &self.descriptor);
            if (result != vk.VK_SUCCESS) @panic("terminal descriptor release failed");
        }
        if (self.row_buffer != null) vk.vkDestroyBuffer(device, self.row_buffer, null);
        if (self.row_memory != null) vk.vkFreeMemory(device, self.row_memory, null);
        if (self.instance_buffer != null) vk.vkDestroyBuffer(device, self.instance_buffer, null);
        if (self.instance_memory != null) vk.vkFreeMemory(device, self.instance_memory, null);
        gpu_bytes.* -= self.owned_bytes;
        self.* = .{};
    }
};

/// Qualifies the one descriptor owner from its terminal Resources, pane
/// storage, and matching font epoch. Generic Canvas resources are not inputs
/// to this construction boundary.
fn descriptorBindingFacts(
    resources: *const Resources,
    pane: *const PaneResources,
    font: *const FontGpu,
) Error!DescriptorBindingFacts {
    if (pane.descriptor == null or pane.instance_buffer == null or
        pane.row_buffer == null or pane.instance_bytes == 0 or pane.row_bytes == 0 or
        resources.sampler == null or font.view == null or font.image == null)
        return error.InvalidIdentity;
    const instance_range = std.math.cast(vk.VkDeviceSize, pane.instance_bytes) orelse
        return error.InvalidGeometry;
    const row_range = std.math.cast(vk.VkDeviceSize, pane.row_bytes) orelse
        return error.InvalidGeometry;
    return .{
        .descriptor = pane.descriptor,
        .instance_buffer = pane.instance_buffer,
        .instance_range = instance_range,
        .row_buffer = pane.row_buffer,
        .row_range = row_range,
        .sampler = resources.sampler,
        .atlas_view = font.view,
        .atlas_image = font.image,
    };
}

/// Supplies one combined terminal draw's physical attachment extent.
pub const DrawTarget = struct {
    physical_width: u32,
    physical_height: u32,
};

/// Reports the exact terminal command values consumed by `recordDraw`.
pub const RecordingFacts = struct {
    surface: [2]u32,
    origin: [2]i32,
    grid: [2]u32,
    cell: [2]u32,
    atlas: [2]u32,
    lines: [4]u32,
    cursor: [4]u32,
    cursor_colors: [2]u32,
    scissor: vk.VkRect2D,
    vertex_count: u32,
    instance_count: u32,
};

/// Reports the exact fixed terminal pipeline state consumed at construction.
pub const FixedState = struct {
    topology: vk.VkPrimitiveTopology,
    blend_enable: vk.VkBool32,
    src_color_blend_factor: vk.VkBlendFactor,
    dst_color_blend_factor: vk.VkBlendFactor,
    color_blend_op: vk.VkBlendOp,
    src_alpha_blend_factor: vk.VkBlendFactor,
    dst_alpha_blend_factor: vk.VkBlendFactor,
    alpha_blend_op: vk.VkBlendOp,
    color_write_mask: vk.VkColorComponentFlags,
};

/// Returns the terminal pipeline state used by production construction.
pub fn fixedState() FixedState {
    return .{
        .topology = vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .blend_enable = 0,
        .src_color_blend_factor = vk.VK_BLEND_FACTOR_ONE,
        .dst_color_blend_factor = vk.VK_BLEND_FACTOR_ZERO,
        .color_blend_op = vk.VK_BLEND_OP_ADD,
        .src_alpha_blend_factor = vk.VK_BLEND_FACTOR_ONE,
        .dst_alpha_blend_factor = vk.VK_BLEND_FACTOR_ZERO,
        .alpha_blend_op = vk.VK_BLEND_OP_ADD,
        .color_write_mask = vk.VK_COLOR_COMPONENT_R_BIT |
            vk.VK_COLOR_COMPONENT_G_BIT |
            vk.VK_COLOR_COMPONENT_B_BIT |
            vk.VK_COLOR_COMPONENT_A_BIT,
    };
}

const PushConstants = extern struct {
    surface: [2]u32,
    origin: [2]i32,
    grid: [2]u32,
    cell: [2]u32,
    atlas: [2]u32,
    padding_before_lines: [2]u32 = .{ 0, 0 },
    lines: [4]u32,
    cursor: [4]u32,
    cursor_colors: [2]u32,
};

comptime {
    std.debug.assert(@sizeOf(DrawTarget) == 8);
    std.debug.assert(@alignOf(DrawTarget) == 4);
    std.debug.assert(@offsetOf(PushConstants, "surface") == 0);
    std.debug.assert(@offsetOf(PushConstants, "origin") == 8);
    std.debug.assert(@offsetOf(PushConstants, "grid") == 16);
    std.debug.assert(@offsetOf(PushConstants, "cell") == 24);
    std.debug.assert(@offsetOf(PushConstants, "atlas") == 32);
    std.debug.assert(@offsetOf(PushConstants, "padding_before_lines") == 40);
    std.debug.assert(@offsetOf(PushConstants, "lines") == 48);
    std.debug.assert(@offsetOf(PushConstants, "cursor") == 64);
    std.debug.assert(@offsetOf(PushConstants, "cursor_colors") == 80);
    std.debug.assert(@sizeOf(PushConstants) == 88);
    std.debug.assert(@alignOf(PushConstants) == 4);
}

/// Owns one terminal pipeline, descriptor backing, sampler, and the single
/// checked aggregate mapped staging allocation shared by every pane Store.
pub const Resources = struct {
    render_pass: vk.VkRenderPass = null,
    descriptor_layout: vk.VkDescriptorSetLayout = null,
    descriptor_pool: vk.VkDescriptorPool = null,
    pipeline_layout: vk.VkPipelineLayout = null,
    pipeline: vk.VkPipeline = null,
    sampler: vk.VkSampler = null,
    staging_buffer: vk.VkBuffer = null,
    staging_memory: vk.VkDeviceMemory = null,
    mapped: ?[*]u8 = null,
    owned_bytes: u64 = 0,

    /// Creates all shared terminal physical ownership transactionally.
    pub fn init(
        device: vk.VkDevice,
        properties: vk.VkPhysicalDeviceMemoryProperties,
        render_pass: vk.VkRenderPass,
        gpu_bytes: *u64,
        limit: u64,
    ) Error!Resources {
        if (device == null or render_pass == null) return error.InvalidIdentity;
        var result = Resources{ .render_pass = render_pass };
        errdefer result.deinit(device, gpu_bytes);
        const descriptor_bindings = [_]vk.VkDescriptorSetLayoutBinding{
            .{
                .binding = 0,
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                .descriptorCount = 1,
                .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT,
            },
            .{
                .binding = 1,
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                .descriptorCount = 1,
                .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT,
            },
            .{
                .binding = 2,
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .descriptorCount = 1,
                .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
            },
        };
        var layout_info = vk.VkDescriptorSetLayoutCreateInfo{
            .bindingCount = descriptor_bindings.len,
            .pBindings = &descriptor_bindings,
        };
        if (vk.vkCreateDescriptorSetLayout(device, &layout_info, null, &result.descriptor_layout) != vk.VK_SUCCESS)
            return error.Descriptor;
        const push_range = vk.VkPushConstantRange{
            .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT | vk.VK_SHADER_STAGE_FRAGMENT_BIT,
            .size = @sizeOf(PushConstants),
        };
        var pipeline_layout_info = vk.VkPipelineLayoutCreateInfo{
            .setLayoutCount = 1,
            .pSetLayouts = &result.descriptor_layout,
            .pushConstantRangeCount = 1,
            .pPushConstantRanges = &push_range,
        };
        if (vk.vkCreatePipelineLayout(device, &pipeline_layout_info, null, &result.pipeline_layout) != vk.VK_SUCCESS)
            return error.Pipeline;
        const pool_sizes = [_]vk.VkDescriptorPoolSize{
            .{ .type = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = maximum_panes * 4 },
            .{ .type = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount = maximum_panes * 2 },
        };
        var pool_info = vk.VkDescriptorPoolCreateInfo{
            .flags = vk.VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
            .maxSets = maximum_panes * 2,
            .poolSizeCount = pool_sizes.len,
            .pPoolSizes = &pool_sizes,
        };
        if (vk.vkCreateDescriptorPool(device, &pool_info, null, &result.descriptor_pool) != vk.VK_SUCCESS)
            return error.Descriptor;
        var sampler_info = terminalSamplerInfo();
        if (vk.vkCreateSampler(device, &sampler_info, null, &result.sampler) != vk.VK_SUCCESS)
            return error.Descriptor;
        try result.createStaging(device, properties, gpu_bytes, limit);
        result.pipeline = try createTerminalPipeline(
            device,
            render_pass,
            result.pipeline_layout,
        );
        return result;
    }

    /// Releases shared staging, pipeline, descriptors, and layout in reverse.
    pub fn deinit(self: *Resources, device: vk.VkDevice, gpu_bytes: *u64) void {
        if (self.mapped != null and self.staging_memory != null)
            vk.vkUnmapMemory(device, self.staging_memory);
        if (self.staging_buffer != null) vk.vkDestroyBuffer(device, self.staging_buffer, null);
        if (self.staging_memory != null) vk.vkFreeMemory(device, self.staging_memory, null);
        if (self.pipeline != null) vk.vkDestroyPipeline(device, self.pipeline, null);
        if (self.sampler != null) vk.vkDestroySampler(device, self.sampler, null);
        if (self.descriptor_pool != null)
            vk.vkDestroyDescriptorPool(device, self.descriptor_pool, null);
        if (self.pipeline_layout != null)
            vk.vkDestroyPipelineLayout(device, self.pipeline_layout, null);
        if (self.descriptor_layout != null)
            vk.vkDestroyDescriptorSetLayout(device, self.descriptor_layout, null);
        gpu_bytes.* -= self.owned_bytes;
        self.* = .{};
    }

    /// Creates one exact-grid persistent buffer and descriptor owner.
    pub fn createPane(
        self: *Resources,
        device: vk.VkDevice,
        properties: vk.VkPhysicalDeviceMemoryProperties,
        limits: Limits,
        font: *const FontGpu,
        gpu_bytes: *u64,
        limit: u64,
    ) Error!PaneResources {
        const payload = try physicalPayloadBytes(limits);
        if (font.view == null or font.image == null) return error.InvalidIdentity;
        var result = PaneResources{
            .instance_bytes = payload.instances,
            .row_bytes = payload.row_map,
        };
        errdefer result.deinit(device, self.descriptor_pool, gpu_bytes);
        try createStorageBuffer(
            device,
            properties,
            payload.instances,
            &result.instance_buffer,
            &result.instance_memory,
            &result.owned_bytes,
            gpu_bytes,
            limit,
        );
        try createStorageBuffer(
            device,
            properties,
            payload.row_map,
            &result.row_buffer,
            &result.row_memory,
            &result.owned_bytes,
            gpu_bytes,
            limit,
        );
        var allocate = vk.VkDescriptorSetAllocateInfo{
            .descriptorPool = self.descriptor_pool,
            .descriptorSetCount = 1,
            .pSetLayouts = &self.descriptor_layout,
        };
        if (vk.vkAllocateDescriptorSets(device, &allocate, &result.descriptor) != vk.VK_SUCCESS)
            return error.Descriptor;
        const facts = try descriptorBindingFacts(self, &result, font);
        const buffer_infos = [_]vk.VkDescriptorBufferInfo{
            .{ .buffer = facts.instance_buffer, .range = facts.instance_range },
            .{ .buffer = facts.row_buffer, .range = facts.row_range },
        };
        const image_info = vk.VkDescriptorImageInfo{
            .sampler = facts.sampler,
            .imageView = facts.atlas_view,
            .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        };
        const writes = [_]vk.VkWriteDescriptorSet{
            .{
                .dstSet = facts.descriptor,
                .dstBinding = 0,
                .descriptorCount = 1,
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                .pBufferInfo = &buffer_infos[0],
            },
            .{
                .dstSet = facts.descriptor,
                .dstBinding = 1,
                .descriptorCount = 1,
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                .pBufferInfo = &buffer_infos[1],
            },
            .{
                .dstSet = facts.descriptor,
                .dstBinding = 2,
                .descriptorCount = 1,
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .pImageInfo = &image_info,
            },
        };
        vk.vkUpdateDescriptorSets(device, writes.len, &writes, 0, null);
        try result.retainDescriptorBindings(facts);
        return result;
    }

    /// Stages one Store candidate into checked aggregate byte partitions.
    pub fn stagePane(
        self: *Resources,
        store: *const Store,
        offsets: StagingOffsets,
    ) Error!void {
        const prepared = store.prepared();
        const row_bytes = std.mem.sliceAsBytes(prepared.row_map);
        try store.stageMapped(try self.mappedPane(
            offsets,
            prepared.instance_staging_bytes,
            row_bytes.len,
        ));
    }

    /// Borrows one checked pane partition so the Host adapter can translate a
    /// complete replacement directly into its final shared staging bytes.
    pub fn mappedPane(
        self: *Resources,
        offsets: StagingOffsets,
        instance_bytes: usize,
        row_bytes: usize,
    ) Error!MappedStaging {
        const mapped = self.mapped orelse return error.StagingMap;
        const instance_end = std.math.add(usize, offsets.instances, instance_bytes) catch
            return error.InvalidGeometry;
        const row_start = std.math.add(usize, row_staging_offset, offsets.rows) catch
            return error.InvalidGeometry;
        const row_end = std.math.add(usize, row_start, row_bytes) catch
            return error.InvalidGeometry;
        if (instance_end > row_staging_offset or row_end > batch_staging_bytes)
            return error.InvalidGeometry;
        return .{
            .instances = mapped[offsets.instances..instance_end],
            .rows = mapped[row_start..row_end],
        };
    }

    /// Returns exact compatible bindings for one pane/font owner tuple.
    pub fn bindings(
        self: *const Resources,
        pane: *const PaneResources,
        font: *const FontGpu,
    ) Error!CommandBindings {
        const facts = try descriptorBindingFacts(self, pane, font);
        try pane.validateDescriptorBindings(facts);
        if (self.staging_buffer == null or self.pipeline == null or
            self.pipeline_layout == null)
            return error.InvalidIdentity;
        return .{
            .instance_staging = self.staging_buffer,
            .instance_storage = facts.instance_buffer,
            .row_staging = self.staging_buffer,
            .row_storage = facts.row_buffer,
            .glyph_atlas = facts.atlas_image,
            .pipeline = self.pipeline,
            .layout = self.pipeline_layout,
            .descriptor = facts.descriptor,
        };
    }

    /// Returns the exact retained descriptor tuple accepted for one draw.
    pub fn bindingFacts(
        self: *const Resources,
        pane: *const PaneResources,
        font: *const FontGpu,
    ) Error!DescriptorBindingFacts {
        const facts = try descriptorBindingFacts(self, pane, font);
        try pane.validateDescriptorBindings(facts);
        return facts;
    }

    fn createStaging(
        self: *Resources,
        device: vk.VkDevice,
        properties: vk.VkPhysicalDeviceMemoryProperties,
        gpu_bytes: *u64,
        limit: u64,
    ) Error!void {
        var info = vk.VkBufferCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = batch_staging_bytes,
            .usage = vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
        };
        if (vk.vkCreateBuffer(device, &info, null, &self.staging_buffer) != vk.VK_SUCCESS)
            return error.Buffer;
        var requirements: vk.VkMemoryRequirements = undefined;
        vk.vkGetBufferMemoryRequirements(device, self.staging_buffer, &requirements);
        try chargeBytes(&self.owned_bytes, gpu_bytes, requirements.size, limit);
        var allocation = vk.VkMemoryAllocateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .allocationSize = requirements.size,
            .memoryTypeIndex = try memoryType(
                properties,
                requirements.memoryTypeBits,
                vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            ),
        };
        if (vk.vkAllocateMemory(device, &allocation, null, &self.staging_memory) != vk.VK_SUCCESS or
            vk.vkBindBufferMemory(device, self.staging_buffer, self.staging_memory, 0) != vk.VK_SUCCESS)
            return error.Buffer;
        var mapped: ?*u8 = null;
        if (vk.vkMapMemory(device, self.staging_memory, 0, requirements.size, 0, &mapped) != vk.VK_SUCCESS or
            mapped == null)
            return error.StagingMap;
        self.mapped = @ptrCast(mapped.?);
    }
};

/// Retains accepted GPU shadows separately from one fixed candidate.
pub const Store = struct {
    allocator: std.mem.Allocator,
    limits: Limits,
    accepted_instances: []Instance,
    accepted_rows: []u32,
    candidate_rows: []u32,
    candidate_instance_count: usize = 0,
    buffer_copies: []vk.VkBufferCopy,
    buffer_copy_count: usize = 0,
    cell_writes: []CellWrite,
    cell_write_count: usize = 0,
    fill_writes: []FillWrite,
    fill_write_count: usize = 0,
    rows: u16 = 0,
    cols: u16 = 0,
    candidate_rows_count: u16 = 0,
    candidate_cols_count: u16 = 0,
    first_replacement: ReplacementKind,
    accepted_cursor: CursorDraw = .{},
    candidate_cursor: CursorDraw = .{},
    candidate_replacement: ?ReplacementKind = null,
    candidate_replacement_instances: []const Instance = &.{},
    candidate_row_changed: bool = false,
    candidate_pending: bool = false,

    /// Allocates all accepted and candidate storage transactionally.
    pub fn init(
        allocator: std.mem.Allocator,
        limits: Limits,
        first_replacement: ReplacementKind,
    ) Error!Store {
        const cells = try validateLimits(limits);
        const accepted_instances = allocator.alloc(Instance, cells) catch return error.OutOfMemory;
        errdefer allocator.free(accepted_instances);
        const accepted_rows = allocator.alloc(u32, limits.rows) catch return error.OutOfMemory;
        errdefer allocator.free(accepted_rows);
        const candidate_rows = allocator.alloc(u32, limits.rows) catch return error.OutOfMemory;
        errdefer allocator.free(candidate_rows);
        const buffer_copies = allocator.alloc(
            vk.VkBufferCopy,
            limits.sparse_cell_updates + limits.structured_updates + 1,
        ) catch return error.OutOfMemory;
        errdefer allocator.free(buffer_copies);
        const cell_writes = allocator.alloc(CellWrite, limits.sparse_cell_updates) catch return error.OutOfMemory;
        errdefer allocator.free(cell_writes);
        const fill_writes = allocator.alloc(FillWrite, limits.structured_updates) catch return error.OutOfMemory;
        errdefer allocator.free(fill_writes);
        @memset(accepted_instances, blankInstance());
        @memset(accepted_rows, 0);
        @memset(candidate_rows, 0);
        return .{
            .allocator = allocator,
            .limits = limits,
            .accepted_instances = accepted_instances,
            .accepted_rows = accepted_rows,
            .candidate_rows = candidate_rows,
            .buffer_copies = buffer_copies,
            .cell_writes = cell_writes,
            .fill_writes = fill_writes,
            .first_replacement = first_replacement,
        };
    }

    /// Releases every fixed allocation in reverse construction order.
    pub fn deinit(self: *Store) void {
        self.allocator.free(self.fill_writes);
        self.allocator.free(self.cell_writes);
        self.allocator.free(self.buffer_copies);
        self.allocator.free(self.candidate_rows);
        self.allocator.free(self.accepted_rows);
        self.allocator.free(self.accepted_instances);
        self.* = undefined;
    }

    /// Prepares one resolved backend update without changing accepted GPU
    /// shadows or generic Canvas/Vulkan Plan storage.
    pub fn prepare(
        self: *Store,
        update: Update,
        font: *const FontGpu,
    ) Error!Prepared {
        if (self.candidate_pending) return error.CandidatePending;
        self.resetCandidate();
        errdefer self.resetCandidate();
        const cells = try validateUpdate(self.limits, update);
        if (update.replacement) |replacement| {
            if (self.rows == 0) {
                if (replacement.kind != self.first_replacement or
                    replacement.kind == .alternate_grid)
                    return error.InvalidIdentity;
            } else if (replacement.kind == .initialization) {
                return error.InvalidIdentity;
            }
        }
        self.candidate_rows_count = update.rows;
        self.candidate_cols_count = update.cols;
        self.candidate_cursor = update.cursor orelse self.accepted_cursor;
        for (update.glyph_slots) |slot|
            if (!font.available(slot)) return error.GlyphUnavailable;

        if (update.replacement) |replacement| {
            self.candidate_replacement = replacement.kind;
            self.candidate_replacement_instances = replacement.instances;
            for (replacement.instances) |instance| try self.requireInstance(instance);
            self.candidate_instance_count = cells;
            try self.appendCopy(0, 0, cells);
            for (self.candidate_rows[0..update.rows], 0..) |*row, index|
                row.* = @intCast(index);
            self.candidate_row_changed = true;
        } else {
            if (self.rows != update.rows or self.cols != update.cols)
                return error.InvalidGeometry;
            @memcpy(self.candidate_rows[0..self.rows], self.accepted_rows[0..self.rows]);
            for (update.row_rotations) |rotation| {
                try applyRotation(self.candidate_rows[0..self.rows], rotation);
                self.candidate_row_changed = true;
            }
            for (update.fills) |fill_update| try self.stageFill(fill_update);
            for (update.cells) |cell_update| try self.stageCell(cell_update);
        }

        self.candidate_pending = true;
        return self.prepared();
    }

    fn prepared(self: *const Store) Prepared {
        std.debug.assert(self.candidate_pending);
        return .{
            .rows = self.candidate_rows_count,
            .cols = self.candidate_cols_count,
            .replacement = self.candidate_replacement,
            .instance_staging_bytes = self.candidate_instance_count * @sizeOf(Instance),
            .instance_copies = self.buffer_copies[0..self.buffer_copy_count],
            .row_map = if (self.candidate_row_changed)
                self.candidate_rows[0..self.candidate_rows_count]
            else
                &.{},
            .row_copy = if (self.candidate_row_changed) .{
                .srcOffset = 0,
                .dstOffset = 0,
                .size = @as(u64, self.candidate_rows_count) * @sizeOf(u32),
            } else null,
            .draw = .{
                .instance_count = @intCast(
                    @as(usize, self.candidate_rows_count) * self.candidate_cols_count,
                ),
                .cursor = self.candidate_cursor,
            },
        };
    }

    /// Accepts one prepared sparse candidate after its physical GPU work has
    /// completed successfully. This operation is infallible and allocation-free.
    pub fn complete(self: *Store) Error!void {
        if (!self.candidate_pending) return error.NoCandidate;
        if (self.candidate_replacement != null) {
            const cells: usize = @as(usize, self.candidate_rows_count) * self.candidate_cols_count;
            @memcpy(
                self.accepted_instances[0..cells],
                self.candidate_replacement_instances[0..cells],
            );
        } else {
            for (self.fill_writes[0..self.fill_write_count]) |fill_write|
                @memset(
                    self.accepted_instances[fill_write.first .. fill_write.first + fill_write.count],
                    fill_write.instance,
                );
            for (self.cell_writes[0..self.cell_write_count]) |cell_write|
                self.accepted_instances[cell_write.index] = cell_write.instance;
        }
        if (self.candidate_row_changed)
            @memcpy(
                self.accepted_rows[0..self.candidate_rows_count],
                self.candidate_rows[0..self.candidate_rows_count],
            );
        self.rows = self.candidate_rows_count;
        self.cols = self.candidate_cols_count;
        self.accepted_cursor = self.candidate_cursor;
        self.candidate_pending = false;
        self.resetCandidate();
    }

    /// Discards candidate ownership without changing any accepted shadow.
    pub fn discard(self: *Store) Error!void {
        if (!self.candidate_pending) return error.NoCandidate;
        self.candidate_pending = false;
        self.resetCandidate();
    }

    /// Returns one accepted physical instance for deterministic owner proofs.
    pub fn accepted(self: *const Store, physical_index: usize) Error!Instance {
        const count = @as(usize, self.rows) * self.cols;
        if (physical_index >= count) return error.InvalidGeometry;
        return self.accepted_instances[physical_index];
    }

    /// Returns the exact candidate or accepted draw-count and cursor state;
    /// the Host adapter supplies placement and font geometry per opportunity.
    pub fn currentDraw(self: *const Store) Error!Draw {
        if (self.candidate_pending) return self.prepared().draw;
        const cells = std.math.mul(usize, self.rows, self.cols) catch
            return error.InvalidGeometry;
        if (cells == 0) return error.InvalidGeometry;
        return .{
            .instance_count = std.math.cast(u32, cells) orelse
                return error.InvalidGeometry,
            .cursor = self.accepted_cursor,
        };
    }

    /// Reports exact candidate ownership for combined completion preflight.
    pub fn candidatePending(self: *const Store) bool {
        return self.candidate_pending;
    }

    /// Copies the internally owned candidate into caller-mapped staging only
    /// after every partition and candidate fact passes preflight.
    pub fn stageMapped(self: *const Store, staging: MappedStaging) Error!void {
        try self.validateCandidate();
        const candidate = self.prepared();
        const row_bytes = std.mem.sliceAsBytes(candidate.row_map);
        if (candidate.instance_staging_bytes > staging.instances.len)
            return error.SparseUpdateLimit;
        if (row_bytes.len > staging.rows.len) return error.StructuredUpdateLimit;

        var byte_offset: usize = 0;
        if (self.candidate_replacement != null) {
            const source = std.mem.sliceAsBytes(self.candidate_replacement_instances);
            if (source.ptr == staging.instances.ptr) {
                byte_offset = source.len;
            } else {
                for (self.candidate_replacement_instances) |instance| {
                    const bytes = std.mem.asBytes(&instance);
                    @memcpy(staging.instances[byte_offset..][0..bytes.len], bytes);
                    byte_offset += bytes.len;
                }
            }
        } else {
            for (self.fill_writes[0..self.fill_write_count]) |fill_write| {
                const bytes = std.mem.asBytes(&fill_write.instance);
                for (0..fill_write.count) |_| {
                    @memcpy(staging.instances[byte_offset..][0..bytes.len], bytes);
                    byte_offset += bytes.len;
                }
            }
            for (self.cell_writes[0..self.cell_write_count]) |cell_write| {
                const bytes = std.mem.asBytes(&cell_write.instance);
                @memcpy(staging.instances[byte_offset..][0..bytes.len], bytes);
                byte_offset += bytes.len;
            }
        }
        std.debug.assert(byte_offset == candidate.instance_staging_bytes);
        @memcpy(staging.rows[0..row_bytes.len], row_bytes);
    }

    /// Records exact candidate transfers after complete validation. Failure
    /// occurs before the first Vulkan command.
    pub fn recordTransfers(
        self: *const Store,
        command: vk.VkCommandBuffer,
        bindings: CommandBindings,
        offsets: StagingOffsets,
    ) Error!void {
        try validateCommandBindings(command, bindings);
        var recorder = BufferCommandRecorder{ .vulkan = command };
        try self.recordTransfersWithRecorder(bindings, offsets, &recorder);
    }

    fn recordTransfersWithRecorder(
        self: *const Store,
        bindings: CommandBindings,
        offsets: StagingOffsets,
        recorder: *BufferCommandRecorder,
    ) Error!void {
        try validateBindingHandles(bindings);
        try self.validateCandidate();
        const candidate = self.prepared();
        const instance_end = std.math.add(
            usize,
            offsets.instances,
            candidate.instance_staging_bytes,
        ) catch return error.InvalidGeometry;
        if (instance_end > row_staging_offset)
            return error.InvalidGeometry;
        const row_bytes = std.mem.sliceAsBytes(candidate.row_map);
        const row_source_origin = std.math.add(
            usize,
            row_staging_offset,
            offsets.rows,
        ) catch return error.InvalidGeometry;
        const row_source_end = std.math.add(
            usize,
            row_source_origin,
            row_bytes.len,
        ) catch return error.InvalidGeometry;
        if (row_source_end > batch_staging_bytes)
            return error.InvalidGeometry;
        for (candidate.instance_copies) |source| {
            const source_offset = std.math.add(
                u64,
                source.srcOffset,
                offsets.instances,
            ) catch return error.InvalidGeometry;
            const source_end = std.math.add(u64, source_offset, source.size) catch
                return error.InvalidGeometry;
            if (source_end > instance_end) return error.InvalidGeometry;
        }
        var absolute_row_copy: ?vk.VkBufferCopy = null;
        if (candidate.row_copy) |source| {
            var row_copy = source;
            row_copy.srcOffset = std.math.add(
                u64,
                source.srcOffset,
                row_source_origin,
            ) catch return error.InvalidGeometry;
            const source_end = std.math.add(u64, row_copy.srcOffset, row_copy.size) catch
                return error.InvalidGeometry;
            if (source_end > row_source_end) return error.InvalidGeometry;
            absolute_row_copy = row_copy;
        }
        var barriers: [2]vk.VkBufferMemoryBarrier = undefined;
        var barrier_count: u32 = 0;
        if (candidate.instance_copies.len != 0) {
            barriers[barrier_count] = .{
                .sType = vk.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
                .srcAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT,
                .dstAccessMask = vk.VK_ACCESS_SHADER_READ_BIT,
                .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
                .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
                .buffer = bindings.instance_storage,
                .size = std.math.mul(
                    u64,
                    self.limits.rows,
                    std.math.mul(u64, self.limits.cols, @sizeOf(Instance)) catch
                        return error.InvalidGeometry,
                ) catch return error.InvalidGeometry,
            };
            barrier_count += 1;
        }
        if (candidate.row_copy != null) {
            barriers[barrier_count] = .{
                .sType = vk.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
                .srcAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT,
                .dstAccessMask = vk.VK_ACCESS_SHADER_READ_BIT,
                .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
                .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
                .buffer = bindings.row_storage,
                .size = @as(u64, self.limits.rows) * @sizeOf(u32),
            };
            barrier_count += 1;
        }
        for (candidate.instance_copies) |source| {
            var copy = source;
            copy.srcOffset = std.math.add(u64, copy.srcOffset, offsets.instances) catch
                return error.InvalidGeometry;
            recorder.copyBuffer(
                bindings.instance_staging,
                bindings.instance_storage,
                copy,
            );
        }
        if (absolute_row_copy) |row_copy| recorder.copyBuffer(
            bindings.row_staging,
            bindings.row_storage,
            row_copy,
        );
        recorder.barrier(barriers[0..barrier_count]);
    }

    /// Records one bounded terminal draw after candidate and count validation.
    /// Resource creation, barriers, render-pass compatibility, submission, and
    /// physical execution remain owned by the Host renderer.
    pub fn recordDraw(
        self: *const Store,
        command: vk.VkCommandBuffer,
        bindings: CommandBindings,
        draw: Draw,
        target: DrawTarget,
    ) Error!void {
        try validateCommandBindings(command, bindings);
        const facts = try self.recordingFacts(draw, target);
        const push = PushConstants{
            .surface = facts.surface,
            .origin = facts.origin,
            .grid = facts.grid,
            .cell = facts.cell,
            .atlas = facts.atlas,
            .lines = facts.lines,
            .cursor = facts.cursor,
            .cursor_colors = facts.cursor_colors,
        };
        vk.vkCmdBindPipeline(command, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, bindings.pipeline);
        vk.vkCmdBindDescriptorSets(
            command,
            vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
            bindings.layout,
            0,
            1,
            &bindings.descriptor,
            0,
            null,
        );
        var physical_clip = facts.scissor;
        vk.vkCmdSetScissor(command, 0, 1, &physical_clip);
        vk.vkCmdPushConstants(
            command,
            bindings.layout,
            vk.VK_SHADER_STAGE_VERTEX_BIT | vk.VK_SHADER_STAGE_FRAGMENT_BIT,
            0,
            @sizeOf(PushConstants),
            &push,
        );
        vk.vkCmdDraw(command, facts.vertex_count, facts.instance_count, 0, 0);
    }

    /// Computes the exact values used by the production terminal draw recorder.
    pub fn recordingFacts(
        self: *const Store,
        draw: Draw,
        target: DrawTarget,
    ) Error!RecordingFacts {
        if (self.candidate_pending) try self.validateCandidate();
        const rows = if (self.candidate_pending) self.candidate_rows_count else self.rows;
        const cols = if (self.candidate_pending) self.candidate_cols_count else self.cols;
        const cells = std.math.mul(usize, rows, cols) catch return error.InvalidGeometry;
        if (cells == 0 or draw.vertex_count != 6 or draw.group_count != 1 or
            draw.instance_count != cells or draw.cell_width == 0 or
            draw.cell_height == 0 or draw.clip_width == 0 or draw.clip_height == 0 or
            draw.baseline >= draw.cell_height or draw.underline_y >= draw.cell_height or
            draw.strike_y >= draw.cell_height or draw.underline_height == 0 or
            draw.strike_height == 0)
            return error.InvalidGeometry;
        const scissor = try drawScissor(draw, target, rows, cols);
        const atlas = try glyphAtlasExtent(.{
            .glyph_width = draw.cell_width,
            .glyph_height = draw.cell_height,
        });
        return .{
            .surface = .{ target.physical_width, target.physical_height },
            .origin = .{ draw.origin_x, draw.origin_y },
            .grid = .{ rows, cols },
            .cell = .{ draw.cell_width, draw.cell_height },
            .atlas = .{ atlas.width, atlas.height },
            .lines = .{
                draw.underline_y,
                draw.underline_height,
                draw.strike_y,
                draw.strike_height,
            },
            .cursor = .{
                draw.cursor.col,
                draw.cursor.row,
                @backingInt(draw.cursor.shape),
                @intFromBool(draw.cursor.visible),
            },
            .cursor_colors = .{ draw.cursor.color, draw.cursor.text_color },
            .scissor = scissor,
            .vertex_count = draw.vertex_count,
            .instance_count = draw.instance_count,
        };
    }

    fn validateCandidate(self: *const Store) Error!void {
        if (!self.candidate_pending) return error.NoCandidate;
        const cells = std.math.mul(
            usize,
            self.candidate_rows_count,
            self.candidate_cols_count,
        ) catch return error.InvalidGeometry;
        const persistent_cells = std.math.mul(usize, self.limits.rows, self.limits.cols) catch
            return error.InvalidGeometry;
        if (cells == 0 or cells > persistent_cells) return error.InvalidGeometry;
        const staging_bytes = std.math.mul(usize, self.candidate_instance_count, @sizeOf(Instance)) catch
            return error.InvalidGeometry;
        const persistent_bytes = std.math.mul(usize, persistent_cells, @sizeOf(Instance)) catch
            return error.InvalidGeometry;
        if (self.buffer_copy_count > self.buffer_copies.len)
            return error.InvalidGeometry;

        var covered_bytes: usize = 0;
        for (self.buffer_copies[0..self.buffer_copy_count]) |copy| {
            if (copy.size == 0 or copy.srcOffset % @alignOf(Instance) != 0 or
                copy.dstOffset % @alignOf(Instance) != 0 or
                copy.size % @sizeOf(Instance) != 0)
                return error.InvalidGeometry;
            const source_end = std.math.add(u64, copy.srcOffset, copy.size) catch
                return error.InvalidGeometry;
            const destination_end = std.math.add(u64, copy.dstOffset, copy.size) catch
                return error.InvalidGeometry;
            if (copy.srcOffset != covered_bytes or source_end > staging_bytes or
                destination_end > persistent_bytes)
                return error.InvalidGeometry;
            covered_bytes = std.math.add(usize, covered_bytes, @intCast(copy.size)) catch
                return error.InvalidGeometry;
        }
        if (covered_bytes != staging_bytes) return error.InvalidGeometry;

        if (self.candidate_replacement != null) {
            if (self.candidate_replacement_instances.len != cells or
                self.candidate_instance_count != cells or self.buffer_copy_count != 1)
                return error.InvalidGeometry;
            for (self.candidate_replacement_instances) |instance|
                try self.requireInstance(instance);
        } else {
            var staged: usize = self.cell_write_count;
            for (self.fill_writes[0..self.fill_write_count]) |fill_write|
                staged = std.math.add(usize, staged, fill_write.count) catch
                    return error.InvalidGeometry;
            if (staged != self.candidate_instance_count or
                self.buffer_copy_count != self.fill_write_count + self.cell_write_count or
                staged > self.limits.sparse_cell_updates)
                return error.InvalidGeometry;
        }

        const row_bytes = std.math.mul(usize, self.candidate_rows_count, @sizeOf(u32)) catch
            return error.InvalidGeometry;
        if (self.candidate_row_changed) {
            if (self.candidate_rows_count > self.candidate_rows.len) return error.InvalidGeometry;
            var seen_rows: [1024]u64 = @splat(0);
            for (self.candidate_rows[0..self.candidate_rows_count]) |row| {
                if (row >= self.candidate_rows_count or bit(&seen_rows, row))
                    return error.InvalidGeometry;
                setBit(&seen_rows, row);
            }
            const copy = self.prepared().row_copy orelse return error.InvalidGeometry;
            if (copy.srcOffset != 0 or copy.dstOffset != 0 or copy.size != row_bytes)
                return error.InvalidGeometry;
        } else if (self.prepared().row_copy != null) return error.InvalidGeometry;

        const draw_count = std.math.cast(u32, cells) orelse return error.InvalidGeometry;
        const draw = self.prepared().draw;
        if (draw.vertex_count != 6 or draw.group_count != 1 or draw.instance_count != draw_count)
            return error.InvalidGeometry;
    }

    fn stageFill(self: *Store, update: Fill) Error!void {
        if (self.fill_write_count == self.fill_writes.len)
            return error.StructuredUpdateLimit;
        const first: usize = @intCast(update.first);
        const count: usize = @intCast(update.count);
        const maximum: usize = @as(usize, self.rows) * self.cols;
        if (count == 0 or first > maximum or count > maximum - first)
            return error.InvalidGeometry;
        try self.requireInstance(update.instance);
        if (count > self.limits.sparse_cell_updates -| self.candidate_instance_count)
            return error.SparseUpdateLimit;
        const transfer_first = self.candidate_instance_count;
        self.candidate_instance_count += count;
        try self.appendCopy(transfer_first, first, count);
        self.fill_writes[self.fill_write_count] = .{
            .first = first,
            .count = count,
            .instance = update.instance,
        };
        self.fill_write_count += 1;
    }

    fn stageCell(self: *Store, update: CellWriteInput) Error!void {
        if (self.cell_write_count == self.cell_writes.len)
            return error.SparseUpdateLimit;
        const index: usize = @intCast(update.physical_index);
        const maximum: usize = @as(usize, self.rows) * self.cols;
        if (index >= maximum) return error.InvalidGeometry;
        if (self.candidate_instance_count == self.limits.sparse_cell_updates)
            return error.SparseUpdateLimit;
        try self.requireInstance(update.instance);
        const transfer_index = self.candidate_instance_count;
        self.candidate_instance_count += 1;
        try self.appendCopy(transfer_index, index, 1);
        self.cell_writes[self.cell_write_count] = .{ .index = index, .instance = update.instance };
        self.cell_write_count += 1;
    }

    fn appendCopy(self: *Store, source: usize, destination: usize, count: usize) Error!void {
        if (self.buffer_copy_count == self.buffer_copies.len)
            return error.StructuredUpdateLimit;
        self.buffer_copies[self.buffer_copy_count] = .{
            .srcOffset = @as(u64, source) * @sizeOf(Instance),
            .dstOffset = @as(u64, destination) * @sizeOf(Instance),
            .size = @as(u64, count) * @sizeOf(Instance),
        };
        self.buffer_copy_count += 1;
    }

    fn requireInstance(_: *const Store, instance: Instance) Error!void {
        try validateInstance(instance);
    }

    fn resetCandidate(self: *Store) void {
        self.candidate_instance_count = 0;
        self.buffer_copy_count = 0;
        self.cell_write_count = 0;
        self.fill_write_count = 0;
        self.candidate_replacement = null;
        self.candidate_replacement_instances = &.{};
        self.candidate_row_changed = false;
        self.candidate_rows_count = 0;
        self.candidate_cols_count = 0;
    }
};

/// Fixes one exact font-epoch glyph tile.
pub const FontLimits = struct {
    glyph_width: u16,
    glyph_height: u16,
};

const GlyphTile = struct {
    x: u32,
    y: u32,
    width: u32,
    height: u32,
};

fn glyphTile(slot: usize, limits: FontLimits) Error!GlyphTile {
    if (slot >= glyph_slots) return error.InvalidIdentity;
    const atlas = try glyphAtlasExtent(limits);
    const tile = GlyphTile{
        .x = @as(u32, @intCast(slot % glyph_atlas_columns)) * limits.glyph_width,
        .y = @as(u32, @intCast(slot / glyph_atlas_columns)) * limits.glyph_height,
        .width = limits.glyph_width,
        .height = limits.glyph_height,
    };
    if (tile.x + tile.width > atlas.width or tile.y + tile.height > atlas.height)
        return error.InvalidIdentity;
    return tile;
}

/// Returns the fixed atlas extent required by one exact font epoch.
pub fn glyphAtlasExtent(limits: FontLimits) Error!struct { width: u32, height: u32 } {
    if (limits.glyph_width == 0 or limits.glyph_height == 0)
        return error.InvalidLimits;
    return .{
        .width = @as(u32, limits.glyph_width) * glyph_atlas_columns,
        .height = @as(u32, limits.glyph_height) * glyph_atlas_rows,
    };
}

fn terminalSamplerInfo() vk.VkSamplerCreateInfo {
    return .{
        .magFilter = vk.VK_FILTER_NEAREST,
        .minFilter = vk.VK_FILTER_NEAREST,
        .mipmapMode = vk.VK_SAMPLER_MIPMAP_MODE_NEAREST,
    };
}

fn validateLimits(limits: Limits) Error!usize {
    if (limits.rows == 0 or limits.cols == 0 or
        limits.sparse_cell_updates == 0 or limits.structured_updates == 0 or
        limits.sparse_cell_updates > maximum_cells or
        limits.structured_updates > maximum_cells)
        return error.InvalidLimits;
    const cells = std.math.mul(usize, limits.rows, limits.cols) catch
        return error.InvalidLimits;
    if (cells > maximum_cells)
        return error.InvalidLimits;
    const copy_capacity = std.math.add(
        usize,
        limits.sparse_cell_updates,
        limits.structured_updates,
    ) catch return error.InvalidLimits;
    if (copy_capacity < limits.sparse_cell_updates) return error.InvalidLimits;
    return cells;
}

fn validateCommandBindings(
    command: vk.VkCommandBuffer,
    bindings: CommandBindings,
) Error!void {
    if (command == null) return error.InvalidIdentity;
    try validateBindingHandles(bindings);
}

fn validateBindingHandles(bindings: CommandBindings) Error!void {
    if (bindings.instance_staging == null or bindings.instance_storage == null or
        bindings.row_staging == null or
        bindings.row_storage == null or bindings.glyph_atlas == null or
        bindings.pipeline == null or
        bindings.layout == null or bindings.descriptor == null)
        return error.InvalidIdentity;
}

fn drawScissor(draw: Draw, target: DrawTarget, rows: u16, cols: u16) Error!vk.VkRect2D {
    if (target.physical_width == 0 or target.physical_height == 0 or
        target.physical_width > std.math.maxInt(i32) or
        target.physical_height > std.math.maxInt(i32) or
        draw.clip_x < 0 or draw.clip_y < 0)
        return error.InvalidGeometry;
    const clip_left: u64 = @intCast(draw.clip_x);
    const clip_top: u64 = @intCast(draw.clip_y);
    const clip_right = std.math.add(u64, clip_left, draw.clip_width) catch
        return error.InvalidGeometry;
    const clip_bottom = std.math.add(u64, clip_top, draw.clip_height) catch
        return error.InvalidGeometry;
    if (clip_right > target.physical_width or
        clip_bottom > target.physical_height)
        return error.InvalidGeometry;
    const left: i64 = draw.origin_x;
    const top: i64 = draw.origin_y;
    const right = std.math.add(
        i64,
        left,
        std.math.mul(i64, draw.cell_width, cols) catch
            return error.InvalidGeometry,
    ) catch return error.InvalidGeometry;
    const bottom = std.math.add(
        i64,
        top,
        std.math.mul(i64, draw.cell_height, rows) catch
            return error.InvalidGeometry,
    ) catch return error.InvalidGeometry;
    if (left != @as(i64, @intCast(clip_left)) or
        top != @as(i64, @intCast(clip_top)) or
        right > @as(i64, @intCast(clip_right)) or
        bottom > @as(i64, @intCast(clip_bottom)) or
        @as(i64, @intCast(clip_right)) - right >= draw.cell_width or
        @as(i64, @intCast(clip_bottom)) - bottom >= draw.cell_height)
        return error.InvalidGeometry;
    return .{
        .offset = .{
            .x = @intCast(clip_left),
            .y = @intCast(clip_top),
        },
        .extent = .{
            .width = draw.clip_width,
            .height = draw.clip_height,
        },
    };
}

fn validateUpdate(limits: Limits, update: Update) Error!usize {
    if (update.rows == 0 or update.cols == 0 or
        update.rows > limits.rows or update.cols > limits.cols)
        return error.InvalidGeometry;
    const cells = std.math.mul(usize, update.rows, update.cols) catch
        return error.InvalidGeometry;
    if (update.replacement) |replacement| {
        if (replacement.rows != update.rows or replacement.cols != update.cols or
            replacement.instances.len != cells or update.row_rotations.len != 0 or
            update.fills.len != 0 or update.cells.len != 0)
            return error.InvalidGeometry;
    }
    if (update.row_rotations.len > limits.structured_updates or
        update.fills.len > limits.structured_updates)
        return error.StructuredUpdateLimit;
    if (update.cells.len > limits.sparse_cell_updates)
        return error.SparseUpdateLimit;
    if (update.cursor) |cursor| {
        if (cursor.visible and (cursor.shape == .hidden or
            cursor.row >= update.rows or cursor.col >= update.cols))
            return error.InvalidGeometry;
        if (!cursor.visible and !std.meta.eql(cursor, CursorDraw{}))
            return error.InvalidIdentity;
    }
    return cells;
}

fn applyRotation(rows: []u32, rotation: RowRotation) Error!void {
    if (rotation.count == 0 or rotation.first >= rows.len or
        @as(usize, rotation.count) > rows.len - rotation.first or
        rotation.shift == 0 or @abs(rotation.shift) >= rotation.count)
        return error.InvalidGeometry;
    const region = rows[rotation.first .. rotation.first + rotation.count];
    if (rotation.shift < 0) {
        std.mem.rotate(u32, region, @intCast(-rotation.shift));
    } else {
        std.mem.rotate(u32, region, region.len - @as(usize, @intCast(rotation.shift)));
    }
}

fn blankInstance() Instance {
    return .{
        .glyph_slot = blank_glyph,
        .flags = .{},
        .foreground = 0,
        .background = 0,
        .underline_color = 0,
    };
}

fn validateInstance(instance: Instance) Error!void {
    if (instance.flags.reserved != 0 or
        (instance.glyph_slot != blank_glyph and instance.glyph_slot >= glyph_slots))
        return error.InvalidIdentity;
}

fn bit(words: []const u64, index: usize) bool {
    return words[index / 64] & (@as(u64, 1) << @intCast(index % 64)) != 0;
}

fn setBit(words: []u64, index: usize) void {
    words[index / 64] |= @as(u64, 1) << @intCast(index % 64);
}

fn chargeBytes(
    owner_bytes: *u64,
    gpu_bytes: *u64,
    bytes: u64,
    limit: u64,
) Error!void {
    const total = std.math.add(u64, gpu_bytes.*, bytes) catch
        return error.GpuMemoryLimit;
    if (total > limit) return error.GpuMemoryLimit;
    gpu_bytes.* = total;
    owner_bytes.* = std.math.add(u64, owner_bytes.*, bytes) catch unreachable;
}

fn memoryType(
    properties: vk.VkPhysicalDeviceMemoryProperties,
    bits: u32,
    required: vk.VkMemoryPropertyFlags,
) Error!u32 {
    for (0..properties.memoryTypeCount) |index| {
        if (bits & (@as(u32, 1) << @intCast(index)) != 0 and
            properties.memoryTypes[index].propertyFlags & required == required)
            return @intCast(index);
    }
    return error.MemoryType;
}

fn createStorageBuffer(
    device: vk.VkDevice,
    properties: vk.VkPhysicalDeviceMemoryProperties,
    bytes: usize,
    buffer: *vk.VkBuffer,
    memory: *vk.VkDeviceMemory,
    owner_bytes: *u64,
    gpu_bytes: *u64,
    limit: u64,
) Error!void {
    if (bytes == 0 or buffer.* != null or memory.* != null)
        return error.InvalidLimits;
    var info = vk.VkBufferCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = bytes,
        .usage = vk.VK_BUFFER_USAGE_TRANSFER_DST_BIT |
            vk.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
        .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
    };
    if (vk.vkCreateBuffer(device, &info, null, buffer) != vk.VK_SUCCESS)
        return error.Buffer;
    var requirements: vk.VkMemoryRequirements = undefined;
    vk.vkGetBufferMemoryRequirements(device, buffer.*, &requirements);
    try chargeBytes(owner_bytes, gpu_bytes, requirements.size, limit);
    var allocation = vk.VkMemoryAllocateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = requirements.size,
        .memoryTypeIndex = try memoryType(
            properties,
            requirements.memoryTypeBits,
            vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        ),
    };
    if (vk.vkAllocateMemory(device, &allocation, null, memory) != vk.VK_SUCCESS or
        vk.vkBindBufferMemory(device, buffer.*, memory.*, 0) != vk.VK_SUCCESS)
        return error.Buffer;
}

fn createTerminalShader(
    device: vk.VkDevice,
    bytes: []align(4) const u8,
) Error!vk.VkShaderModule {
    var info = vk.VkShaderModuleCreateInfo{
        .codeSize = bytes.len,
        .pCode = @ptrCast(bytes.ptr),
    };
    var result: vk.VkShaderModule = null;
    if (vk.vkCreateShaderModule(device, &info, null, &result) != vk.VK_SUCCESS)
        return error.Shader;
    return result;
}

fn createTerminalPipeline(
    device: vk.VkDevice,
    render_pass: vk.VkRenderPass,
    layout: vk.VkPipelineLayout,
) Error!vk.VkPipeline {
    const vertex = try createTerminalShader(device, &terminal_vertex_shader);
    defer vk.vkDestroyShaderModule(device, vertex, null);
    const fragment = try createTerminalShader(device, &terminal_fragment_shader);
    defer vk.vkDestroyShaderModule(device, fragment, null);
    const stages = [_]vk.VkPipelineShaderStageCreateInfo{
        .{ .stage = vk.VK_SHADER_STAGE_VERTEX_BIT, .module = vertex, .pName = "main" },
        .{ .stage = vk.VK_SHADER_STAGE_FRAGMENT_BIT, .module = fragment, .pName = "main" },
    };
    var vertex_input = vk.VkPipelineVertexInputStateCreateInfo{};
    const fixed = fixedState();
    var assembly = vk.VkPipelineInputAssemblyStateCreateInfo{
        .topology = fixed.topology,
    };
    var viewport = vk.VkPipelineViewportStateCreateInfo{
        .viewportCount = 1,
        .scissorCount = 1,
    };
    var raster = vk.VkPipelineRasterizationStateCreateInfo{};
    var multisample = vk.VkPipelineMultisampleStateCreateInfo{};
    const attachment = vk.VkPipelineColorBlendAttachmentState{
        .blendEnable = fixed.blend_enable,
        .srcColorBlendFactor = fixed.src_color_blend_factor,
        .dstColorBlendFactor = fixed.dst_color_blend_factor,
        .colorBlendOp = fixed.color_blend_op,
        .srcAlphaBlendFactor = fixed.src_alpha_blend_factor,
        .dstAlphaBlendFactor = fixed.dst_alpha_blend_factor,
        .alphaBlendOp = fixed.alpha_blend_op,
        .colorWriteMask = fixed.color_write_mask,
    };
    var color = vk.VkPipelineColorBlendStateCreateInfo{
        .attachmentCount = 1,
        .pAttachments = &attachment,
    };
    const dynamic_values = [_]vk.VkDynamicState{
        vk.VK_DYNAMIC_STATE_VIEWPORT,
        vk.VK_DYNAMIC_STATE_SCISSOR,
    };
    var dynamic = vk.VkPipelineDynamicStateCreateInfo{
        .dynamicStateCount = dynamic_values.len,
        .pDynamicStates = &dynamic_values,
    };
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
    if (vk.vkCreateGraphicsPipelines(device, null, 1, &info, null, &result) != vk.VK_SUCCESS)
        return error.Pipeline;
    return result;
}

fn testSlot(codepoint: u8, bold: bool, italic: bool) u16 {
    return stableGlyphSlot(codepoint, bold, italic) catch unreachable;
}

fn testInstance(codepoint: u8) Instance {
    return .{
        .glyph_slot = if (codepoint == ' ') blank_glyph else testSlot(codepoint, false, false),
        .flags = .{},
        .foreground = 0xffeeeeee,
        .background = 0xff111111,
        .underline_color = 0xff888888,
    };
}

fn testLimits(rows: u16, cols: u16) Limits {
    return .{
        .rows = rows,
        .cols = cols,
        .sparse_cell_updates = @as(usize, rows) * cols,
        .structured_updates = rows,
    };
}

fn testFont() !FontGpu {
    return FontGpu.init(std.testing.allocator, .{
        .glyph_width = 1,
        .glyph_height = 1,
    });
}

fn prepareWithFont(
    store: *Store,
    font: *FontGpu,
    update: Update,
    rasters: []const GlyphRaster,
) !Prepared {
    try font.prepare(update.glyph_slots, rasters);
    errdefer font.discard() catch @panic("test font discard failed");
    return store.prepare(update, font);
}

fn completeWithFont(store: *Store, font: *FontGpu) !void {
    try font.complete();
    try store.complete();
}

fn testRaster(slot: u16, pixels: []const u8) GlyphRaster {
    return .{ .slot = slot, .width = 1, .height = 1, .stride = 1, .pixels = pixels };
}

fn testCommandBindings() CommandBindings {
    return .{
        .instance_staging = @ptrFromInt(1),
        .instance_storage = @ptrFromInt(1),
        .row_staging = @ptrFromInt(1),
        .row_storage = @ptrFromInt(1),
        .glyph_atlas = @ptrFromInt(1),
        .pipeline = @ptrFromInt(1),
        .layout = @ptrFromInt(1),
        .descriptor = @ptrFromInt(1),
    };
}

fn testDraw(rows: u16, cols: u16) Draw {
    return .{
        .instance_count = @as(u32, rows) * cols,
        .cursor = .{},
        .clip_width = @as(u32, cols) * 8,
        .clip_height = @as(u32, rows) * 16,
        .cell_width = 8,
        .cell_height = 16,
        .baseline = 12,
        .underline_y = 14,
        .underline_height = 1,
        .strike_y = 8,
        .strike_height = 1,
    };
}

fn testDrawTarget(rows: u16, cols: u16) DrawTarget {
    return .{
        .physical_width = @as(u32, cols) * 8,
        .physical_height = @as(u32, rows) * 16,
    };
}

const SpirvAbiError = error{InvalidSpirv};
const spirv_magic: u32 = 0x0723_0203;
const spirv_op_name: u16 = 5;
const spirv_op_member_name: u16 = 6;
const spirv_op_member_decorate: u16 = 72;
const spirv_op_constant: u16 = 43;
const spirv_op_access_chain: u16 = 65;
const spirv_op_in_bounds_access_chain: u16 = 66;
const spirv_decoration_offset: u32 = 35;

const PushAbiMember = struct {
    name: []const u8,
    offset: usize,
    bytes: usize,
};

const push_abi_members = [_]PushAbiMember{
    .{ .name = "surface", .offset = 0, .bytes = 8 },
    .{ .name = "origin", .offset = 8, .bytes = 8 },
    .{ .name = "grid", .offset = 16, .bytes = 8 },
    .{ .name = "cell", .offset = 24, .bytes = 8 },
    .{ .name = "atlas", .offset = 32, .bytes = 8 },
    .{ .name = "lines", .offset = 48, .bytes = 16 },
    .{ .name = "cursor", .offset = 64, .bytes = 16 },
    .{ .name = "cursor_colors", .offset = 80, .bytes = 8 },
};

const push_abi_zig_offsets = [_]usize{
    @offsetOf(PushConstants, "surface"),
    @offsetOf(PushConstants, "origin"),
    @offsetOf(PushConstants, "grid"),
    @offsetOf(PushConstants, "cell"),
    @offsetOf(PushConstants, "atlas"),
    @offsetOf(PushConstants, "lines"),
    @offsetOf(PushConstants, "cursor"),
    @offsetOf(PushConstants, "cursor_colors"),
};

const OraclePixel = struct { x: u32, y: u32 };
const OracleFraction = struct { numerator: i64, denominator: u32 };
const OracleNdc = struct { x: OracleFraction, y: OracleFraction };
const OracleUv = struct { x: OracleFraction, y: OracleFraction };
const OracleAtlasBounds = struct { minimum: OracleUv, maximum: OracleUv };
const OracleShaderValue = struct {
    packed_word: u32,
    foreground: u32,
    background: u32,
    underline_color: u32,
};

const oracle_corners = [_]OraclePixel{
    .{ .x = 0, .y = 0 },
    .{ .x = 1, .y = 0 },
    .{ .x = 1, .y = 1 },
    .{ .x = 0, .y = 0 },
    .{ .x = 1, .y = 1 },
    .{ .x = 0, .y = 1 },
};

fn spirvWord(module: []const u8, word_index: usize) SpirvAbiError!u32 {
    if (module.len % 4 != 0) return error.InvalidSpirv;
    const byte_index = std.math.mul(usize, word_index, 4) catch return error.InvalidSpirv;
    if (byte_index > module.len or module.len - byte_index < 4) return error.InvalidSpirv;
    return std.mem.readInt(u32, module[byte_index..][0..4], .little);
}

fn spirvInstructionEnd(module: []const u8, first_word: usize) SpirvAbiError!struct {
    opcode: u16,
    end: usize,
} {
    const instruction = try spirvWord(module, first_word);
    const word_count: usize = instruction >> 16;
    if (word_count == 0) return error.InvalidSpirv;
    const end = std.math.add(usize, first_word, word_count) catch return error.InvalidSpirv;
    if (end > module.len / 4) return error.InvalidSpirv;
    return .{ .opcode = @truncate(instruction), .end = end };
}

fn spirvStringEquals(
    module: []const u8,
    first_word: usize,
    word_count: usize,
    expected: []const u8,
) SpirvAbiError!bool {
    var expected_index: usize = 0;
    for (0..word_count) |offset| {
        const word = try spirvWord(module, first_word + offset);
        for (0..4) |byte_offset| {
            const byte: u8 = @truncate(word >> @intCast(byte_offset * 8));
            if (expected_index == expected.len) return byte == 0;
            if (byte != expected[expected_index]) return false;
            expected_index += 1;
        }
    }
    return false;
}

fn spirvNamedId(module: []const u8, expected_name: []const u8) SpirvAbiError!u32 {
    if (module.len < 20 or try spirvWord(module, 0) != spirv_magic) return error.InvalidSpirv;
    var found: ?u32 = null;
    var first_word: usize = 5;
    while (first_word < module.len / 4) {
        const instruction = try spirvInstructionEnd(module, first_word);
        if (instruction.opcode == spirv_op_name and instruction.end - first_word >= 3 and
            try spirvStringEquals(module, first_word + 2, instruction.end - first_word - 2, expected_name))
        {
            if (found != null) return error.InvalidSpirv;
            found = try spirvWord(module, first_word + 1);
        }
        first_word = instruction.end;
    }
    return found orelse error.InvalidSpirv;
}

fn spirvConstantValue(module: []const u8, id: u32) SpirvAbiError!?u32 {
    var first_word: usize = 5;
    while (first_word < module.len / 4) {
        const instruction = try spirvInstructionEnd(module, first_word);
        if (instruction.opcode == spirv_op_constant and instruction.end - first_word == 4 and
            try spirvWord(module, first_word + 2) == id)
            return try spirvWord(module, first_word + 3);
        first_word = instruction.end;
    }
    return null;
}

fn verifyPushConstantSpirv(
    module: []const u8,
    atlas_name: []const u8,
    expected_accesses: [8]bool,
    expected_accessed_range: usize,
) SpirvAbiError!void {
    const push_type_id = try spirvNamedId(module, "Push");
    const push_variable_id = try spirvNamedId(module, "push");
    var names: [push_abi_members.len]bool = @splat(false);
    var offsets: [push_abi_members.len]bool = @splat(false);
    var accesses: [push_abi_members.len]bool = @splat(false);
    var first_word: usize = 5;
    while (first_word < module.len / 4) {
        const instruction = try spirvInstructionEnd(module, first_word);
        const operands = instruction.end - first_word - 1;
        if (instruction.opcode == spirv_op_member_name and operands >= 3 and
            try spirvWord(module, first_word + 1) == push_type_id)
        {
            const member: usize = @intCast(try spirvWord(module, first_word + 2));
            if (member >= push_abi_members.len or names[member]) return error.InvalidSpirv;
            const expected_name = if (member == 4) atlas_name else push_abi_members[member].name;
            if (!try spirvStringEquals(module, first_word + 3, operands - 2, expected_name))
                return error.InvalidSpirv;
            names[member] = true;
        }
        if (instruction.opcode == spirv_op_member_decorate and operands == 4 and
            try spirvWord(module, first_word + 1) == push_type_id and
            try spirvWord(module, first_word + 3) == spirv_decoration_offset)
        {
            const member: usize = @intCast(try spirvWord(module, first_word + 2));
            if (member >= push_abi_members.len or offsets[member] or
                try spirvWord(module, first_word + 4) != push_abi_members[member].offset)
                return error.InvalidSpirv;
            offsets[member] = true;
        }
        if ((instruction.opcode == spirv_op_access_chain or
            instruction.opcode == spirv_op_in_bounds_access_chain) and operands >= 4 and
            try spirvWord(module, first_word + 3) == push_variable_id)
        {
            const member_id = try spirvWord(module, first_word + 4);
            const member: usize = @intCast((try spirvConstantValue(module, member_id)) orelse
                return error.InvalidSpirv);
            if (member >= push_abi_members.len) return error.InvalidSpirv;
            accesses[member] = true;
        }
        first_word = instruction.end;
    }

    var maximum_end: usize = 0;
    for (push_abi_members, 0..) |member, index| {
        if (!names[index] or !offsets[index] or accesses[index] != expected_accesses[index])
            return error.InvalidSpirv;
        const end = std.math.add(usize, member.offset, member.bytes) catch return error.InvalidSpirv;
        if (expected_accesses[index] and end > maximum_end) maximum_end = end;
        if (end > @sizeOf(PushConstants) or push_abi_zig_offsets[index] != member.offset)
            return error.InvalidSpirv;
    }
    if (maximum_end != expected_accessed_range or maximum_end > @sizeOf(PushConstants))
        return error.InvalidSpirv;
}

fn oraclePhysicalIndex(instance: u32, columns: u32, rows: []const u32) usize {
    const logical_row = instance / columns;
    const logical_col = instance % columns;
    return rows[logical_row] * columns + logical_col;
}

fn oraclePixel(
    origin: OraclePixel,
    cell: OraclePixel,
    logical_row: u32,
    logical_col: u32,
    corner: OraclePixel,
) OraclePixel {
    return .{
        .x = origin.x + logical_col * cell.x + corner.x * cell.x,
        .y = origin.y + logical_row * cell.y + corner.y * cell.y,
    };
}

fn oracleNdc(pixel: OraclePixel, surface: OraclePixel) OracleNdc {
    return .{
        .x = .{
            .numerator = @as(i64, pixel.x) * 2 - surface.x,
            .denominator = surface.x,
        },
        .y = .{
            .numerator = @as(i64, surface.y) - @as(i64, pixel.y) * 2,
            .denominator = surface.y,
        },
    };
}

fn oracleGlyphUv(slot: u16, corner: OraclePixel) OracleUv {
    return .{
        .x = .{
            .numerator = @as(i64, slot % glyph_atlas_columns) + corner.x,
            .denominator = glyph_atlas_columns,
        },
        .y = .{
            .numerator = @as(i64, slot / glyph_atlas_columns) + corner.y,
            .denominator = glyph_atlas_rows,
        },
    };
}

fn oracleAtlasBounds(slot: u16, cell: OraclePixel) OracleAtlasBounds {
    const column: u32 = slot % glyph_atlas_columns;
    const row: u32 = slot / glyph_atlas_columns;
    const extent = OraclePixel{
        .x = glyph_atlas_columns * cell.x,
        .y = glyph_atlas_rows * cell.y,
    };
    return .{
        .minimum = .{
            .x = .{ .numerator = @as(i64, column * cell.x * 2 + 1), .denominator = extent.x * 2 },
            .y = .{ .numerator = @as(i64, row * cell.y * 2 + 1), .denominator = extent.y * 2 },
        },
        .maximum = .{
            .x = .{ .numerator = @as(i64, (column + 1) * cell.x * 2 - 1), .denominator = extent.x * 2 },
            .y = .{ .numerator = @as(i64, (row + 1) * cell.y * 2 - 1), .denominator = extent.y * 2 },
        },
    };
}

fn oracleShaderValue(instance: Instance) OracleShaderValue {
    const flags: u16 = @bitCast(instance.flags);
    return .{
        .packed_word = @as(u32, instance.glyph_slot) | (@as(u32, flags) << 16),
        .foreground = instance.foreground,
        .background = instance.background,
        .underline_color = instance.underline_color,
    };
}

fn acceptInitial(
    store: *Store,
    font: *FontGpu,
    rows: u16,
    cols: u16,
    instances: []const Instance,
    slots: []const u16,
    rasters: []const GlyphRaster,
) !void {
    const prepared = try prepareWithFont(store, font, .{
        .rows = rows,
        .cols = cols,
        .replacement = .{ .kind = .initialization, .rows = rows, .cols = cols, .instances = instances },
        .row_rotations = &.{},
        .fills = &.{},
        .cells = &.{},
        .glyph_slots = slots,
        .cursor = null,
    }, rasters);
    try std.testing.expectEqual(ReplacementKind.initialization, prepared.replacement.?);
    try completeWithFont(store, font);
}

fn storeAllocationFailure(allocator: std.mem.Allocator) !void {
    var store = try Store.init(allocator, testLimits(2, 2), .initialization);
    defer store.deinit();
}

test "terminal shader push constant ABI has exact tracked SPIR-V layout" {
    try verifyPushConstantSpirv(
        terminal_vertex_shader[0..],
        "atlas",
        .{ true, true, true, true, false, false, false, false },
        32,
    );
    try verifyPushConstantSpirv(
        terminal_fragment_shader[0..],
        "atlas_extent",
        .{ false, false, false, true, true, true, true, true },
        88,
    );
    try std.testing.expectEqual(@as(usize, 88), @sizeOf(PushConstants));
    try std.testing.expectEqualSlices(usize, &.{ 0, 8, 16, 24, 32, 48, 64, 80 }, &push_abi_zig_offsets);
}

test "terminal shader CPU oracle maps a two by two pane exactly" {
    const columns: u32 = 2;
    const row_map = [_]u32{ 1, 0 };
    const expected_physical = [_]usize{ 2, 3, 0, 1 };
    const expected_logical = [_]struct { row: u32, col: u32 }{
        .{ .row = 0, .col = 0 },
        .{ .row = 0, .col = 1 },
        .{ .row = 1, .col = 0 },
        .{ .row = 1, .col = 1 },
    };
    const origin = OraclePixel{ .x = 10, .y = 6 };
    const cell = OraclePixel{ .x = 7, .y = 5 };
    const surface = OraclePixel{ .x = 80, .y = 40 };
    const expected_pixels = [4][6]OraclePixel{
        .{ .{ .x = 10, .y = 6 }, .{ .x = 17, .y = 6 }, .{ .x = 17, .y = 11 }, .{ .x = 10, .y = 6 }, .{ .x = 17, .y = 11 }, .{ .x = 10, .y = 11 } },
        .{ .{ .x = 17, .y = 6 }, .{ .x = 24, .y = 6 }, .{ .x = 24, .y = 11 }, .{ .x = 17, .y = 6 }, .{ .x = 24, .y = 11 }, .{ .x = 17, .y = 11 } },
        .{ .{ .x = 10, .y = 11 }, .{ .x = 17, .y = 11 }, .{ .x = 17, .y = 16 }, .{ .x = 10, .y = 11 }, .{ .x = 17, .y = 16 }, .{ .x = 10, .y = 16 } },
        .{ .{ .x = 17, .y = 11 }, .{ .x = 24, .y = 11 }, .{ .x = 24, .y = 16 }, .{ .x = 17, .y = 11 }, .{ .x = 24, .y = 16 }, .{ .x = 17, .y = 16 } },
    };
    const expected_ndc = [4][6]OracleNdc{
        .{ .{ .x = .{ .numerator = -60, .denominator = 80 }, .y = .{ .numerator = 28, .denominator = 40 } }, .{ .x = .{ .numerator = -46, .denominator = 80 }, .y = .{ .numerator = 28, .denominator = 40 } }, .{ .x = .{ .numerator = -46, .denominator = 80 }, .y = .{ .numerator = 18, .denominator = 40 } }, .{ .x = .{ .numerator = -60, .denominator = 80 }, .y = .{ .numerator = 28, .denominator = 40 } }, .{ .x = .{ .numerator = -46, .denominator = 80 }, .y = .{ .numerator = 18, .denominator = 40 } }, .{ .x = .{ .numerator = -60, .denominator = 80 }, .y = .{ .numerator = 18, .denominator = 40 } } },
        .{ .{ .x = .{ .numerator = -46, .denominator = 80 }, .y = .{ .numerator = 28, .denominator = 40 } }, .{ .x = .{ .numerator = -32, .denominator = 80 }, .y = .{ .numerator = 28, .denominator = 40 } }, .{ .x = .{ .numerator = -32, .denominator = 80 }, .y = .{ .numerator = 18, .denominator = 40 } }, .{ .x = .{ .numerator = -46, .denominator = 80 }, .y = .{ .numerator = 28, .denominator = 40 } }, .{ .x = .{ .numerator = -32, .denominator = 80 }, .y = .{ .numerator = 18, .denominator = 40 } }, .{ .x = .{ .numerator = -46, .denominator = 80 }, .y = .{ .numerator = 18, .denominator = 40 } } },
        .{ .{ .x = .{ .numerator = -60, .denominator = 80 }, .y = .{ .numerator = 18, .denominator = 40 } }, .{ .x = .{ .numerator = -46, .denominator = 80 }, .y = .{ .numerator = 18, .denominator = 40 } }, .{ .x = .{ .numerator = -46, .denominator = 80 }, .y = .{ .numerator = 8, .denominator = 40 } }, .{ .x = .{ .numerator = -60, .denominator = 80 }, .y = .{ .numerator = 18, .denominator = 40 } }, .{ .x = .{ .numerator = -46, .denominator = 80 }, .y = .{ .numerator = 8, .denominator = 40 } }, .{ .x = .{ .numerator = -60, .denominator = 80 }, .y = .{ .numerator = 8, .denominator = 40 } } },
        .{ .{ .x = .{ .numerator = -46, .denominator = 80 }, .y = .{ .numerator = 18, .denominator = 40 } }, .{ .x = .{ .numerator = -32, .denominator = 80 }, .y = .{ .numerator = 18, .denominator = 40 } }, .{ .x = .{ .numerator = -32, .denominator = 80 }, .y = .{ .numerator = 8, .denominator = 40 } }, .{ .x = .{ .numerator = -46, .denominator = 80 }, .y = .{ .numerator = 18, .denominator = 40 } }, .{ .x = .{ .numerator = -32, .denominator = 80 }, .y = .{ .numerator = 8, .denominator = 40 } }, .{ .x = .{ .numerator = -46, .denominator = 80 }, .y = .{ .numerator = 8, .denominator = 40 } } },
    };
    const instances = [_]Instance{
        .{ .glyph_slot = 7, .flags = .{}, .foreground = 0x0102_0304, .background = 0x0506_0708, .underline_color = 0x090a_0b0c },
        .{ .glyph_slot = 19, .flags = .{ .dim = true }, .foreground = 0x1112_1314, .background = 0x1516_1718, .underline_color = 0x191a_1b1c },
        .{ .glyph_slot = 43, .flags = .{ .bold = true, .dim = true, .italic = true, .underline = true }, .foreground = 0x2122_2324, .background = 0x2526_2728, .underline_color = 0x292a_2b2c },
        .{ .glyph_slot = 70, .flags = .{ .italic = true, .strikethrough = true }, .foreground = 0x3132_3334, .background = 0x3536_3738, .underline_color = 0x393a_3b3c },
    };
    const expected_values = [_]OracleShaderValue{
        .{ .packed_word = 0x000f_002b, .foreground = 0x2122_2324, .background = 0x2526_2728, .underline_color = 0x292a_2b2c },
        .{ .packed_word = 0x0014_0046, .foreground = 0x3132_3334, .background = 0x3536_3738, .underline_color = 0x393a_3b3c },
        .{ .packed_word = 0x0000_0007, .foreground = 0x0102_0304, .background = 0x0506_0708, .underline_color = 0x090a_0b0c },
        .{ .packed_word = 0x0002_0013, .foreground = 0x1112_1314, .background = 0x1516_1718, .underline_color = 0x191a_1b1c },
    };

    for (0..4) |instance| {
        const logical = expected_logical[instance];
        const physical = oraclePhysicalIndex(@intCast(instance), columns, &row_map);
        try std.testing.expectEqual(expected_physical[instance], physical);
        try std.testing.expectEqualDeep(expected_values[instance], oracleShaderValue(instances[physical]));
        for (oracle_corners, 0..) |corner, vertex| {
            const pixel = oraclePixel(origin, cell, logical.row, logical.col, corner);
            try std.testing.expectEqualDeep(expected_pixels[instance][vertex], pixel);
            try std.testing.expectEqualDeep(expected_ndc[instance][vertex], oracleNdc(pixel, surface));
        }
    }

    const expected_glyph_uv = [_]OracleUv{
        .{ .x = .{ .numerator = 3, .denominator = 20 }, .y = .{ .numerator = 2, .denominator = 19 } },
        .{ .x = .{ .numerator = 4, .denominator = 20 }, .y = .{ .numerator = 2, .denominator = 19 } },
        .{ .x = .{ .numerator = 4, .denominator = 20 }, .y = .{ .numerator = 3, .denominator = 19 } },
        .{ .x = .{ .numerator = 3, .denominator = 20 }, .y = .{ .numerator = 2, .denominator = 19 } },
        .{ .x = .{ .numerator = 4, .denominator = 20 }, .y = .{ .numerator = 3, .denominator = 19 } },
        .{ .x = .{ .numerator = 3, .denominator = 20 }, .y = .{ .numerator = 3, .denominator = 19 } },
    };
    for (oracle_corners, 0..) |corner, vertex|
        try std.testing.expectEqualDeep(expected_glyph_uv[vertex], oracleGlyphUv(43, corner));
    try std.testing.expectEqualDeep(
        OracleAtlasBounds{
            .minimum = .{
                .x = .{ .numerator = 43, .denominator = 280 },
                .y = .{ .numerator = 21, .denominator = 190 },
            },
            .maximum = .{
                .x = .{ .numerator = 55, .denominator = 280 },
                .y = .{ .numerator = 29, .denominator = 190 },
            },
        },
        oracleAtlasBounds(43, cell),
    );
}

test "resolved sparse input lowers without Plan copies" {
    var store = try Store.init(std.testing.allocator, testLimits(4, 5), .initialization);
    defer store.deinit();
    var font = try testFont();
    defer font.deinit();
    const pixels = [_]u8{0xff};
    const five_slot = testSlot('5', false, false);
    const initial: [20]Instance = @splat(testInstance('5'));
    try acceptInitial(&store, &font, 4, 5, &initial, &.{five_slot}, &.{testRaster(five_slot, &pixels)});

    const four_slot = testSlot('4', false, false);
    const prepared = try prepareWithFont(&store, &font, .{
        .rows = 4,
        .cols = 5,
        .replacement = null,
        .row_rotations = &.{},
        .fills = &.{},
        .cells = &.{.{ .physical_index = 7, .instance = testInstance('4') }},
        .glyph_slots = &.{four_slot},
        .cursor = null,
    }, &.{testRaster(four_slot, &pixels)});
    try std.testing.expectEqual(@as(usize, @sizeOf(Instance)), prepared.instance_staging_bytes);
    try std.testing.expectEqual(@as(usize, 1), prepared.instance_copies.len);
    try std.testing.expectEqual(@as(u64, 0), prepared.instance_copies[0].srcOffset);
    try std.testing.expectEqual(@as(u64, 7 * @sizeOf(Instance)), prepared.instance_copies[0].dstOffset);
    try std.testing.expectEqual(@as(u64, @sizeOf(Instance)), prepared.instance_copies[0].size);
    try std.testing.expectEqual(@as(u32, 1), prepared.draw.group_count);
    try std.testing.expectEqual(@as(u32, 20), prepared.draw.instance_count);
    try completeWithFont(&store, &font);
}

test "maximum-cell retained CPU and physical payload equations are exact" {
    const limits = Limits{
        .rows = 128,
        .cols = 512,
        .sparse_cell_updates = maximum_cells,
        .structured_updates = 128,
    };
    const physical = try physicalPayloadBytes(limits);
    try std.testing.expectEqual(@as(usize, 232), @sizeOf(Store));
    try std.testing.expectEqual(@as(usize, 4_202_752), try retainedCpuBytes(limits));
    try std.testing.expectEqual(@as(usize, 1_048_576), physical.instances);
    try std.testing.expectEqual(@as(usize, 512), physical.row_map);
    const atlas = try glyphAtlasExtent(.{ .glyph_width = 8, .glyph_height = 16 });
    try std.testing.expectEqual(@as(u32, 160), atlas.width);
    try std.testing.expectEqual(@as(u32, 304), atlas.height);
}

test "terminal sampler and fixed glyph tiles exclude adjacent texels" {
    const sampler = terminalSamplerInfo();
    try std.testing.expectEqual(@as(vk.VkFilter, vk.VK_FILTER_NEAREST), sampler.magFilter);
    try std.testing.expectEqual(@as(vk.VkFilter, vk.VK_FILTER_NEAREST), sampler.minFilter);
    try std.testing.expectEqual(
        @as(vk.VkSamplerMipmapMode, vk.VK_SAMPLER_MIPMAP_MODE_NEAREST),
        sampler.mipmapMode,
    );

    const limits = FontLimits{ .glyph_width = 8, .glyph_height = 16 };
    const first = try glyphTile(0, limits);
    const adjacent = try glyphTile(1, limits);
    try std.testing.expectEqual(first.x + first.width, adjacent.x);
    try std.testing.expectEqual(first.y, adjacent.y);

    const row_end = try glyphTile(glyph_atlas_columns - 1, limits);
    const next_row = try glyphTile(glyph_atlas_columns, limits);
    const atlas = try glyphAtlasExtent(limits);
    try std.testing.expectEqual(atlas.width, row_end.x + row_end.width);
    try std.testing.expectEqual(@as(u32, 0), next_row.x);
    try std.testing.expectEqual(row_end.y + row_end.height, next_row.y);
}

test "GPU replacement lifecycle rejects premature and duplicate initialization" {
    var store = try Store.init(std.testing.allocator, testLimits(1, 1), .initialization);
    defer store.deinit();
    var font = try testFont();
    defer font.deinit();
    const blank = [_]Instance{testInstance(' ')};
    const initial = Update{
        .rows = 1,
        .cols = 1,
        .replacement = .{ .kind = .initialization, .rows = 1, .cols = 1, .instances = &blank },
        .row_rotations = &.{},
        .fills = &.{},
        .cells = &.{},
        .glyph_slots = &.{},
        .cursor = null,
    };
    var premature = initial;
    var premature_replacement = premature.replacement.?;
    premature_replacement.kind = .resize;
    premature.replacement = premature_replacement;
    try font.prepare(&.{}, &.{});
    try std.testing.expectError(error.InvalidIdentity, store.prepare(premature, &font));
    try font.discard();

    const prepared = try prepareWithFont(&store, &font, initial, &.{});
    try std.testing.expectEqual(ReplacementKind.initialization, prepared.replacement.?);
    try completeWithFont(&store, &font);
    const before = try store.accepted(0);
    try font.prepare(&.{}, &.{});
    try std.testing.expectError(error.InvalidIdentity, store.prepare(initial, &font));
    try font.discard();
    try std.testing.expectEqualDeep(before, try store.accepted(0));
}

test "T006 one-row scroll uploads row map and exposed row but no moved cells" {
    var store = try Store.init(std.testing.allocator, testLimits(4, 5), .initialization);
    defer store.deinit();
    var font = try testFont();
    defer font.deinit();
    const pixels = [_]u8{0xff};
    const a_slot = testSlot('a', false, false);
    const initial: [20]Instance = @splat(testInstance('a'));
    try acceptInitial(&store, &font, 4, 5, &initial, &.{a_slot}, &.{testRaster(a_slot, &pixels)});
    const prepared = try prepareWithFont(&store, &font, .{
        .rows = 4,
        .cols = 5,
        .replacement = null,
        .row_rotations = &.{.{ .first = 0, .count = 4, .shift = -1 }},
        .fills = &.{.{ .first = 0, .count = 5, .instance = testInstance(' ') }},
        .cells = &.{},
        .glyph_slots = &.{},
        .cursor = null,
    }, &.{});
    try std.testing.expect(prepared.row_copy != null);
    try std.testing.expectEqualSlices(u32, &.{ 1, 2, 3, 0 }, prepared.row_map);
    try std.testing.expectEqual(@as(u64, 4 * @sizeOf(u32)), prepared.row_copy.?.size);
    try std.testing.expectEqual(@as(usize, 5 * @sizeOf(Instance)), prepared.instance_staging_bytes);
    try std.testing.expectEqual(@as(usize, 1), prepared.instance_copies.len);
    try std.testing.expectEqual(@as(u64, 0), prepared.instance_copies[0].dstOffset);
    try std.testing.expectEqual(@as(u64, 5 * @sizeOf(Instance)), prepared.instance_copies[0].size);
    try completeWithFont(&store, &font);
}

test "stable glyph identity uploads only on first use" {
    var font = try testFont();
    defer font.deinit();
    const pixels = [_]u8{0xaa};
    const slot = testSlot('x', false, false);
    try font.prepare(&.{slot}, &.{testRaster(slot, &pixels)});
    const first = try font.prepared();
    try std.testing.expectEqual(@as(usize, 1), first.uploads.len);
    try std.testing.expectEqual(slot, first.uploads[0].slot);
    try font.complete();
    try std.testing.expect(font.glyphResident(slot));

    try font.prepare(&.{slot}, &.{});
    try std.testing.expectEqual(@as(usize, 0), (try font.prepared()).uploads.len);
    try font.complete();
}

test "blank first FontGpu batch initializes atlas only after completion" {
    var font = try testFont();
    defer font.deinit();

    try font.prepare(&.{}, &.{});
    var first_proof = FontTransferProof{};
    var first_recorder = FontCommandRecorder{ .proof = &first_proof };
    try font.recordTransferCommands(
        &first_recorder,
        @ptrFromInt(1),
        @ptrFromInt(2),
    );
    try std.testing.expectEqual(@as(u8, 1), first_proof.barrier_count);
    try std.testing.expectEqual(@as(u16, 0), first_proof.copy_count);
    try std.testing.expectEqual(
        @as(vk.VkPipelineStageFlags, vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT),
        first_proof.barriers[0].source_stage,
    );
    try std.testing.expectEqual(
        @as(vk.VkPipelineStageFlags, vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT),
        first_proof.barriers[0].destination_stage,
    );
    try std.testing.expectEqual(
        @as(vk.VkImageLayout, vk.VK_IMAGE_LAYOUT_UNDEFINED),
        first_proof.barriers[0].barrier.oldLayout,
    );
    try std.testing.expectEqual(
        @as(vk.VkImageLayout, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL),
        first_proof.barriers[0].barrier.newLayout,
    );
    try std.testing.expect(!font.atlas_initialized);
    try font.complete();
    try std.testing.expect(font.atlas_initialized);

    try font.prepare(&.{}, &.{});
    var later_proof = FontTransferProof{};
    var later_recorder = FontCommandRecorder{ .proof = &later_proof };
    try font.recordTransferCommands(
        &later_recorder,
        @ptrFromInt(1),
        @ptrFromInt(2),
    );
    try std.testing.expectEqual(@as(u8, 0), later_proof.barrier_count);
    try std.testing.expectEqual(@as(u16, 0), later_proof.copy_count);
    try font.complete();
}

test "FontGpu atlas transition rollback and fatal ownership remain exact" {
    var font = try testFont();
    defer font.deinit();

    try font.prepare(&.{}, &.{});
    var discarded_proof = FontTransferProof{};
    var discarded_recorder = FontCommandRecorder{ .proof = &discarded_proof };
    try font.recordTransferCommands(
        &discarded_recorder,
        @ptrFromInt(1),
        @ptrFromInt(2),
    );
    try font.discard();
    try std.testing.expect(!font.atlas_initialized);
    try std.testing.expect(!font.candidatePending());

    try font.prepare(&.{}, &.{});
    var retry_proof = FontTransferProof{};
    var retry_recorder = FontCommandRecorder{ .proof = &retry_proof };
    try font.recordTransferCommands(
        &retry_recorder,
        @ptrFromInt(1),
        @ptrFromInt(2),
    );
    try std.testing.expectEqual(@as(u8, 1), retry_proof.barrier_count);
    try std.testing.expectEqual(
        @as(vk.VkImageLayout, vk.VK_IMAGE_LAYOUT_UNDEFINED),
        retry_proof.barriers[0].barrier.oldLayout,
    );
    try font.discard();

    try font.prepare(&.{}, &.{});
    font.image = @ptrFromInt(3);
    try std.testing.expect(!font.completionReady());
    try std.testing.expectError(error.NoCandidate, font.complete());
    try std.testing.expect(font.candidatePending());
    try std.testing.expect(!font.atlas_initialized);
    font.image = null;
    try font.discard();
}

test "mapped staging preflights all partitions before writing" {
    var store = try Store.init(std.testing.allocator, testLimits(1, 1), .initialization);
    defer store.deinit();
    var font = try testFont();
    defer font.deinit();
    const initial = [_]Instance{testInstance(' ')};
    try acceptInitial(&store, &font, 1, 1, &initial, &.{}, &.{});
    const accepted_before = try store.accepted(0);

    const pixels = [_]u8{0x7f};
    const slot = testSlot('x', false, false);
    const prepared = try prepareWithFont(&store, &font, .{
        .rows = 1,
        .cols = 1,
        .replacement = null,
        .row_rotations = &.{},
        .fills = &.{},
        .cells = &.{.{ .physical_index = 0, .instance = testInstance('x') }},
        .glyph_slots = &.{slot},
        .cursor = null,
    }, &.{testRaster(slot, &pixels)});
    var instance_bytes: [@sizeOf(Instance)]u8 = undefined;
    try store.stageMapped(.{
        .instances = &instance_bytes,
        .rows = &.{},
    });
    try std.testing.expectEqual(@as(usize, @sizeOf(Instance)), prepared.instance_staging_bytes);
    var glyph_bytes: [1]u8 = undefined;
    try font.stageMapped(&glyph_bytes);
    try std.testing.expectEqualSlices(u8, &pixels, &glyph_bytes);

    var short_instances: [@sizeOf(Instance) - 1]u8 = @splat(0xaa);
    var untouched_rows: [3]u8 = @splat(0xbb);
    try std.testing.expectError(error.SparseUpdateLimit, store.stageMapped(.{
        .instances = &short_instances,
        .rows = &untouched_rows,
    }));
    for (short_instances) |byte| try std.testing.expectEqual(@as(u8, 0xaa), byte);
    for (untouched_rows) |byte| try std.testing.expectEqual(@as(u8, 0xbb), byte);
    var no_glyph_space: [0]u8 = .{};
    try std.testing.expectError(error.GlyphUploadLimit, font.stageMapped(&no_glyph_space));
    try std.testing.expectEqualDeep(accepted_before, try store.accepted(0));
    try store.discard();
    try font.discard();
}

test "first-use glyph copy offsets satisfy Vulkan alignment" {
    var font = try testFont();
    defer font.deinit();

    const first_pixels = [_]u8{0x11};
    const second_pixels = [_]u8{0x22};
    const x_slot = testSlot('x', false, false);
    const y_slot = testSlot('y', false, false);
    try font.prepare(&.{ x_slot, y_slot }, &.{
        testRaster(x_slot, &first_pixels),
        testRaster(y_slot, &second_pixels),
    });
    const prepared = try font.prepared();
    try std.testing.expectEqual(@as(usize, 2), prepared.uploads.len);
    try std.testing.expectEqual(@as(u64, 0), prepared.uploads[0].region.bufferOffset);
    try std.testing.expectEqual(@as(u64, 4), prepared.uploads[1].region.bufferOffset);
    try std.testing.expectEqualSlices(u8, &.{ 0x11, 0, 0, 0, 0x22 }, prepared.pixels);
    try font.discard();
}

test "cursor update draws without generic base geometry copy" {
    var store = try Store.init(std.testing.allocator, testLimits(2, 2), .initialization);
    defer store.deinit();
    var font = try testFont();
    defer font.deinit();
    const initial: [4]Instance = @splat(testInstance(' '));
    try acceptInitial(&store, &font, 2, 2, &initial, &.{}, &.{});
    const prepared = try prepareWithFont(&store, &font, .{
        .rows = 2,
        .cols = 2,
        .replacement = null,
        .row_rotations = &.{},
        .fills = &.{},
        .cells = &.{},
        .glyph_slots = &.{},
        .cursor = .{ .row = 1, .col = 1, .shape = .block, .visible = true },
    }, &.{});
    try std.testing.expectEqual(@as(usize, 0), prepared.instance_staging_bytes);
    try std.testing.expectEqual(@as(usize, 0), prepared.instance_copies.len);
    try std.testing.expect(prepared.draw.cursor.visible);
    try completeWithFont(&store, &font);
}

test "glyph and sparse preparation failures preserve accepted ownership" {
    var store = try Store.init(std.testing.allocator, .{
        .rows = 1,
        .cols = 2,
        .sparse_cell_updates = 1,
        .structured_updates = 1,
    }, .initialization);
    defer store.deinit();
    var font = try testFont();
    defer font.deinit();
    const initial: [2]Instance = @splat(testInstance(' '));
    try acceptInitial(&store, &font, 1, 2, &initial, &.{}, &.{});
    const before = try store.accepted(0);
    const slot = testSlot('x', false, false);
    const update = Update{
        .rows = 1,
        .cols = 2,
        .replacement = null,
        .row_rotations = &.{},
        .fills = &.{},
        .cells = &.{.{ .physical_index = 0, .instance = testInstance('x') }},
        .glyph_slots = &.{slot},
        .cursor = null,
    };
    try std.testing.expectError(error.GlyphUnavailable, store.prepare(update, &font));
    try std.testing.expectEqualDeep(before, try store.accepted(0));
    const bad_pixels = [_]u8{ 1, 2 };
    try std.testing.expectError(
        error.InvalidGlyphRaster,
        font.prepare(&.{slot}, &.{.{
            .slot = slot,
            .width = 1,
            .height = 1,
            .stride = 1,
            .pixels = &bad_pixels,
        }}),
    );
    try std.testing.expectEqualDeep(before, try store.accepted(0));

    var invalid_geometry = update;
    invalid_geometry.cursor = .{ .row = 1, .col = 0, .shape = .block, .visible = true };
    try font.prepare(&.{slot}, &.{testRaster(slot, bad_pixels[0..1])});
    try std.testing.expectError(error.InvalidGeometry, store.prepare(invalid_geometry, &font));
    try font.discard();
    try std.testing.expectEqualDeep(before, try store.accepted(0));
    const invalid_slots = [_]u16{@intCast(glyph_slots)};
    var invalid_identity = update;
    invalid_identity.glyph_slots = &invalid_slots;
    try std.testing.expectError(error.InvalidIdentity, font.prepare(&invalid_slots, &.{}));
    try std.testing.expectEqualDeep(before, try store.accepted(0));

    var overflow_update = update;
    overflow_update.cells = &.{
        .{ .physical_index = 0, .instance = testInstance('x') },
        .{ .physical_index = 1, .instance = testInstance('x') },
    };
    const pixels = [_]u8{0xaa};
    try std.testing.expectError(
        error.SparseUpdateLimit,
        blk: {
            try font.prepare(&.{slot}, &.{testRaster(slot, &pixels)});
            defer font.discard() catch @panic("test font discard failed");
            break :blk store.prepare(overflow_update, &font);
        },
    );
    try std.testing.expectEqualDeep(before, try store.accepted(0));
}

test "allocation and Vulkan command layouts are exact" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        storeAllocationFailure,
        .{},
    );
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(vk.VkBufferCopy));
    try std.testing.expectEqual(@as(usize, 56), @sizeOf(vk.VkBufferImageCopy));
    try std.testing.expectEqual(@as(usize, 160), @sizeOf(FontGpu));
    try std.testing.expectEqual(@as(usize, 128), @sizeOf(PaneResources));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(PaneResources));
    try std.testing.expectEqual(@as(usize, 80), @sizeOf(Resources));
    try std.testing.expectEqual(@as(usize, 68), @sizeOf(Draw));
    try std.testing.expectEqual(@as(usize, 88), @sizeOf(PushConstants));
    try std.testing.expectEqual(
        @as(usize, 67_141_632),
        staging_byte_limit,
    );
    const copy_command: *const fn (
        vk.VkCommandBuffer,
        vk.VkBuffer,
        vk.VkBuffer,
        u32,
        [*c]const vk.VkBufferCopy,
    ) callconv(.c) void = &vk.vkCmdCopyBuffer;
    const draw_command: *const fn (
        vk.VkCommandBuffer,
        u32,
        u32,
        u32,
        u32,
    ) callconv(.c) void = &vk.vkCmdDraw;
    try std.testing.expect(@intFromPtr(copy_command) != 0);
    try std.testing.expect(@intFromPtr(draw_command) != 0);
    const transfer_owner: *const fn (
        *const Store,
        vk.VkCommandBuffer,
        CommandBindings,
        StagingOffsets,
    ) Error!void = &Store.recordTransfers;
    const draw_owner: *const fn (
        *const Store,
        vk.VkCommandBuffer,
        CommandBindings,
        Draw,
        DrawTarget,
    ) Error!void = &Store.recordDraw;
    try std.testing.expect(@intFromPtr(transfer_owner) != 0);
    try std.testing.expect(@intFromPtr(draw_owner) != 0);
    const invalid = std.mem.zeroes(CommandBindings);
    var store = try Store.init(std.testing.allocator, testLimits(1, 1), .initialization);
    defer store.deinit();
    try std.testing.expectError(error.InvalidIdentity, store.recordTransfers(null, invalid, .{ .instances = 0, .rows = 0 }));
    try std.testing.expectError(error.InvalidIdentity, store.recordDraw(null, invalid, testDraw(1, 1), testDrawTarget(1, 1)));
    const extent = try glyphAtlasExtent(.{ .glyph_width = 8, .glyph_height = 16 });
    try std.testing.expectEqual(@as(u32, 160), extent.width);
    try std.testing.expectEqual(@as(u32, 304), extent.height);
}

test "T017 terminal descriptor construction retains exact pane and font identities" {
    const resources = Resources{
        .sampler = @ptrFromInt(0x101),
        .staging_buffer = @ptrFromInt(0x102),
        .pipeline = @ptrFromInt(0x103),
        .pipeline_layout = @ptrFromInt(0x104),
    };
    var pane = PaneResources{
        .instance_buffer = @ptrFromInt(0x201),
        .row_buffer = @ptrFromInt(0x202),
        .descriptor = @ptrFromInt(0x203),
        .instance_bytes = 672,
        .row_bytes = 20,
    };
    var font = try testFont();
    defer {
        font.image = null;
        font.view = null;
        font.deinit();
    }
    font.image = @ptrFromInt(0x301);
    font.view = @ptrFromInt(0x302);

    const facts = try descriptorBindingFacts(&resources, &pane, &font);
    try pane.retainDescriptorBindings(facts);
    const retained = pane;
    try std.testing.expectError(
        error.InvalidIdentity,
        pane.retainDescriptorBindings(facts),
    );
    try std.testing.expectEqualDeep(retained, pane);
    try std.testing.expectEqual(pane.descriptor, facts.descriptor);
    try std.testing.expectEqual(pane.instance_buffer, facts.instance_buffer);
    try std.testing.expectEqual(@as(vk.VkDeviceSize, pane.instance_bytes), facts.instance_range);
    try std.testing.expectEqual(pane.row_buffer, facts.row_buffer);
    try std.testing.expectEqual(@as(vk.VkDeviceSize, pane.row_bytes), facts.row_range);
    try std.testing.expectEqual(resources.sampler, facts.sampler);
    try std.testing.expectEqual(font.view, facts.atlas_view);
    try std.testing.expectEqual(font.image, facts.atlas_image);

    const bindings = try resources.bindings(&pane, &font);
    try std.testing.expectEqual(facts.descriptor, bindings.descriptor);
    try std.testing.expectEqual(facts.instance_buffer, bindings.instance_storage);
    try std.testing.expectEqual(facts.row_buffer, bindings.row_storage);
    try std.testing.expectEqual(facts.atlas_image, bindings.glyph_atlas);

    var other_resources = resources;
    other_resources.sampler = @ptrFromInt(0x401);
    try std.testing.expectError(
        error.InvalidIdentity,
        other_resources.bindings(&pane, &font),
    );
    try std.testing.expectEqualDeep(retained, pane);

    var other_font = font;
    other_font.view = @ptrFromInt(0x402);
    try std.testing.expectError(
        error.InvalidIdentity,
        resources.bindings(&pane, &other_font),
    );
    try std.testing.expectEqualDeep(retained, pane);

    other_font = font;
    other_font.image = @ptrFromInt(0x403);
    try std.testing.expectError(
        error.InvalidIdentity,
        resources.bindings(&pane, &other_font),
    );
    try std.testing.expectEqualDeep(retained, pane);

    var other_pane = pane;
    other_pane.instance_bytes += @sizeOf(Instance);
    try std.testing.expectError(
        error.InvalidIdentity,
        resources.bindings(&other_pane, &font),
    );
    try std.testing.expectEqualDeep(retained, pane);

    other_pane = pane;
    other_pane.row_bytes += @sizeOf(u32);
    try std.testing.expectError(
        error.InvalidIdentity,
        resources.bindings(&other_pane, &font),
    );
    try std.testing.expectEqualDeep(retained, pane);

    other_pane = pane;
    other_pane.descriptor = @ptrFromInt(0x404);
    try std.testing.expectError(
        error.InvalidIdentity,
        resources.bindings(&other_pane, &font),
    );
    try std.testing.expectEqualDeep(retained, pane);

    other_pane = pane;
    other_pane.instance_buffer = @ptrFromInt(0x405);
    try std.testing.expectError(
        error.InvalidIdentity,
        resources.bindings(&other_pane, &font),
    );
    try std.testing.expectEqualDeep(retained, pane);

    other_pane = pane;
    other_pane.row_buffer = @ptrFromInt(0x406);
    try std.testing.expectError(
        error.InvalidIdentity,
        resources.bindings(&other_pane, &font),
    );
    try std.testing.expectEqualDeep(retained, pane);
}

test "T018 terminal scissor accepts only one physically covered pane" {
    var draw = testDraw(2, 3);
    draw.origin_x = 19;
    draw.origin_y = 12;
    draw.cell_width = 9;
    draw.cell_height = 6;
    draw.clip_x = 19;
    draw.clip_y = 12;
    draw.clip_width = 29;
    draw.clip_height = 14;
    const target = DrawTarget{
        .physical_width = 150,
        .physical_height = 120,
    };
    const first = try drawScissor(draw, target, 2, 3);
    try std.testing.expectEqual(@as(i32, 19), first.offset.x);
    try std.testing.expectEqual(@as(i32, 12), first.offset.y);
    try std.testing.expectEqual(@as(u32, 29), first.extent.width);
    try std.testing.expectEqual(@as(u32, 14), first.extent.height);

    draw.clip_width = 36;
    try std.testing.expectError(error.InvalidGeometry, drawScissor(draw, target, 2, 3));
}

test "malformed retained commands fail before the first Vulkan call" {
    var store = try Store.init(std.testing.allocator, testLimits(1, 1), .initialization);
    defer store.deinit();
    var font = try testFont();
    defer font.deinit();
    const initial = [_]Instance{testInstance(' ')};
    const candidate = try prepareWithFont(&store, &font, .{
        .rows = 1,
        .cols = 1,
        .replacement = .{ .kind = .initialization, .rows = 1, .cols = 1, .instances = &initial },
        .row_rotations = &.{},
        .fills = &.{},
        .cells = &.{},
        .glyph_slots = &.{},
        .cursor = null,
    }, &.{});
    try std.testing.expectEqual(ReplacementKind.initialization, candidate.replacement.?);

    const command: vk.VkCommandBuffer = @ptrFromInt(1);
    const bindings = testCommandBindings();
    store.buffer_copies[0].srcOffset = 1;
    try std.testing.expectError(error.InvalidGeometry, store.recordTransfers(command, bindings, .{ .instances = 0, .rows = 0 }));
    store.buffer_copies[0].srcOffset = 0;

    store.candidate_rows[0] = 1;
    try std.testing.expectError(error.InvalidGeometry, store.recordTransfers(command, bindings, .{ .instances = 0, .rows = 0 }));
    store.candidate_rows[0] = 0;

    store.candidate_instance_count = 0;
    try std.testing.expectError(error.InvalidGeometry, store.recordDraw(command, bindings, testDraw(1, 1), testDrawTarget(1, 1)));
    try font.discard();
}

test "T022 row transfer records the absolute shared staging partition" {
    var store = try Store.init(std.testing.allocator, testLimits(2, 2), .initialization);
    defer store.deinit();
    var font = try testFont();
    defer font.deinit();
    const initial = [_]Instance{
        testInstance('a'),
        testInstance('b'),
        testInstance('c'),
        testInstance('d'),
    };
    const initial_prepared = try prepareWithFont(&store, &font, .{
        .rows = 2,
        .cols = 2,
        .replacement = .{
            .kind = .initialization,
            .rows = 2,
            .cols = 2,
            .instances = &initial,
        },
        .row_rotations = &.{},
        .fills = &.{},
        .cells = &.{},
        .glyph_slots = &.{},
        .cursor = null,
    }, &.{});
    try std.testing.expectEqual(ReplacementKind.initialization, initial_prepared.replacement.?);
    try completeWithFont(&store, &font);
    const prepared = try prepareWithFont(&store, &font, .{
        .rows = 2,
        .cols = 2,
        .replacement = .{
            .kind = .resize,
            .rows = 2,
            .cols = 2,
            .instances = &initial,
        },
        .row_rotations = &.{},
        .fills = &.{},
        .cells = &.{},
        .glyph_slots = &.{},
        .cursor = null,
    }, &.{});
    try std.testing.expectEqual(@as(usize, 8), std.mem.sliceAsBytes(prepared.row_map).len);

    const staging = try std.testing.allocator.alloc(u8, batch_staging_bytes);
    defer std.testing.allocator.free(staging);
    @memset(staging, 0xa5);
    var resources = Resources{ .mapped = staging.ptr };
    const offsets = StagingOffsets{ .instances = 1024, .rows = 12 };
    try resources.stagePane(&store, offsets);
    const absolute_row = row_staging_offset + offsets.rows;
    try std.testing.expectEqualSlices(
        u8,
        std.mem.sliceAsBytes(prepared.row_map),
        staging[absolute_row .. absolute_row + 8],
    );
    const untouched: [8]u8 = @splat(0xa5);
    try std.testing.expectEqualSlices(
        u8,
        &untouched,
        staging[offsets.rows .. offsets.rows + 8],
    );

    const bindings = testCommandBindings();
    var receipt = BufferTransferProof{};
    var recorder = BufferCommandRecorder{ .proof = &receipt };
    try store.recordTransfersWithRecorder(bindings, offsets, &recorder);
    try std.testing.expectEqual(@as(u8, 2), receipt.copy_count);
    try std.testing.expectEqual(@as(u64, offsets.instances), receipt.copies[0].region.srcOffset);
    try std.testing.expectEqual(@as(u64, absolute_row), receipt.copies[1].region.srcOffset);
    try std.testing.expectEqual(@as(u64, 0), receipt.copies[1].region.dstOffset);
    try std.testing.expectEqual(@as(u64, 8), receipt.copies[1].region.size);
    try std.testing.expect(receipt.copies[1].region.srcOffset != offsets.rows);

    const accepted_before = try store.accepted(0);
    const candidate_before = store.prepared();
    var rejected = BufferTransferProof{};
    var rejected_recorder = BufferCommandRecorder{ .proof = &rejected };
    try std.testing.expectError(
        error.InvalidGeometry,
        store.recordTransfersWithRecorder(
            bindings,
            .{ .instances = offsets.instances, .rows = maximum_row_staging_bytes },
            &rejected_recorder,
        ),
    );
    try std.testing.expectEqual(@as(u8, 0), rejected.copy_count);
    try std.testing.expectEqual(@as(u8, 0), rejected.barrier_count);
    try std.testing.expectEqualDeep(accepted_before, try store.accepted(0));
    try std.testing.expectEqualDeep(candidate_before, store.prepared());
    try std.testing.expect(store.candidatePending());

    try std.testing.expectError(
        error.InvalidGeometry,
        store.recordTransfersWithRecorder(
            bindings,
            .{ .instances = offsets.instances, .rows = std.math.maxInt(usize) },
            &rejected_recorder,
        ),
    );
    try std.testing.expectEqual(@as(u8, 0), rejected.copy_count);
    try std.testing.expectEqualDeep(accepted_before, try store.accepted(0));
    try std.testing.expectEqualDeep(candidate_before, store.prepared());
    try font.discard();
}
