//! Maintained minimal Vulkan 1.4.357 ABI for external images and semaphores.
//! SPDX-License-Identifier: Apache-2.0 OR MIT
//! Source: KhronosGroup/Vulkan-Headers v1.4.357,
//! commit e3b1eec08173d6b825cd3ac88c885a63b621504a.
//! Input vulkan_core.h SHA-256:
//! a7ac0d7e35e77f642c175af5d36729cfdae2d626d2aaa9145c030a42bd44edc6.
//! Derived from the official C header through pinned Zig translate-C, then
//! reduced to the declarations consumed by renderer.zig.

pub const VkBool32 = u32;

pub const VkDeviceSize = u64;

pub const VkFlags = u32;

pub const struct_VkInstance_T = opaque {};

pub const VkInstance = ?*struct_VkInstance_T;

pub const struct_VkPhysicalDevice_T = opaque {};

pub const VkPhysicalDevice = ?*struct_VkPhysicalDevice_T;

pub const struct_VkDevice_T = opaque {};

pub const VkDevice = ?*struct_VkDevice_T;

pub const struct_VkQueue_T = opaque {};

pub const VkQueue = ?*struct_VkQueue_T;

pub const struct_VkSemaphore_T = opaque {};

pub const VkSemaphore = ?*struct_VkSemaphore_T;

pub const struct_VkCommandBuffer_T = opaque {};

pub const VkCommandBuffer = ?*struct_VkCommandBuffer_T;

pub const struct_VkFence_T = opaque {};

pub const VkFence = ?*struct_VkFence_T;

pub const struct_VkDeviceMemory_T = opaque {};

pub const VkDeviceMemory = ?*struct_VkDeviceMemory_T;

pub const struct_VkBuffer_T = opaque {};

pub const VkBuffer = ?*struct_VkBuffer_T;

pub const struct_VkImage_T = opaque {};

pub const VkImage = ?*struct_VkImage_T;

pub const struct_VkCommandPool_T = opaque {};

pub const VkCommandPool = ?*struct_VkCommandPool_T;

pub const struct_VkRenderPass_T = opaque {};

pub const VkRenderPass = ?*struct_VkRenderPass_T;

pub const struct_VkFramebuffer_T = opaque {};

pub const VkFramebuffer = ?*struct_VkFramebuffer_T;
pub const struct_VkImageView_T = opaque {};
pub const VkImageView = ?*struct_VkImageView_T;
pub const struct_VkShaderModule_T = opaque {};
pub const VkShaderModule = ?*struct_VkShaderModule_T;
pub const struct_VkPipeline_T = opaque {};
pub const VkPipeline = ?*struct_VkPipeline_T;
pub const struct_VkPipelineLayout_T = opaque {};
pub const VkPipelineLayout = ?*struct_VkPipelineLayout_T;
pub const struct_VkPipelineCache_T = opaque {};
pub const VkPipelineCache = ?*struct_VkPipelineCache_T;
pub const struct_VkDescriptorSetLayout_T = opaque {};
pub const VkDescriptorSetLayout = ?*struct_VkDescriptorSetLayout_T;
pub const struct_VkSampler_T = opaque {};
pub const VkSampler = ?*struct_VkSampler_T;
pub const struct_VkDescriptorSet_T = opaque {};
pub const VkDescriptorSet = ?*struct_VkDescriptorSet_T;
pub const struct_VkDescriptorPool_T = opaque {};
pub const VkDescriptorPool = ?*struct_VkDescriptorPool_T;
pub const struct_VkBufferView_T = opaque {};
pub const VkBufferView = ?*struct_VkBufferView_T;

pub const VK_SUCCESS: c_int = 0;

pub const enum_VkResult = c_int;

pub const VkResult = enum_VkResult;

pub const VK_STRUCTURE_TYPE_APPLICATION_INFO: c_int = 0;

pub const VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO: c_int = 1;

pub const VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO: c_int = 2;

pub const VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO: c_int = 3;

pub const VK_STRUCTURE_TYPE_SUBMIT_INFO: c_int = 4;

pub const VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO: c_int = 5;

pub const VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO: c_int = 9;

pub const VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO: c_int = 14;
pub const VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO: c_int = 12;
pub const VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO: c_int = 15;
pub const VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO: c_int = 16;
pub const VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO: c_int = 18;
pub const VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO: c_int = 19;
pub const VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO: c_int = 20;
pub const VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO: c_int = 22;
pub const VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO: c_int = 23;
pub const VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO: c_int = 24;
pub const VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO: c_int = 26;
pub const VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO: c_int = 27;
pub const VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO: c_int = 28;
pub const VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO: c_int = 30;
pub const VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO: c_int = 31;
pub const VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO: c_int = 32;
pub const VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO: c_int = 33;
pub const VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO: c_int = 34;
pub const VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET: c_int = 35;
pub const VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO: c_int = 37;
pub const VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO: c_int = 38;
pub const VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO: c_int = 43;

pub const VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO: c_int = 39;

pub const VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO: c_int = 40;

pub const VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO: c_int = 42;

pub const VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER: c_int = 45;
pub const VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER: c_int = 44;

pub const VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO: c_int = 1000127001;

pub const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2: c_int = 1000059000;

pub const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2: c_int = 1000059001;

pub const VK_STRUCTURE_TYPE_FORMAT_PROPERTIES_2: c_int = 1000059002;

pub const VK_STRUCTURE_TYPE_IMAGE_FORMAT_PROPERTIES_2: c_int = 1000059003;

pub const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_FORMAT_INFO_2: c_int = 1000059004;

pub const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTERNAL_IMAGE_FORMAT_INFO: c_int = 1000071000;

pub const VK_STRUCTURE_TYPE_EXTERNAL_IMAGE_FORMAT_PROPERTIES: c_int = 1000071001;

pub const VK_STRUCTURE_TYPE_EXTERNAL_MEMORY_IMAGE_CREATE_INFO: c_int = 1000072001;

pub const VK_STRUCTURE_TYPE_EXPORT_MEMORY_ALLOCATE_INFO: c_int = 1000072002;

pub const VK_STRUCTURE_TYPE_EXPORT_SEMAPHORE_CREATE_INFO: c_int = 1000077000;

pub const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TIMELINE_SEMAPHORE_FEATURES: c_int = 1000207000;

pub const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES: c_int = 1000314007;

pub const VK_STRUCTURE_TYPE_MEMORY_GET_FD_INFO_KHR: c_int = 1000074002;

pub const VK_STRUCTURE_TYPE_IMPORT_SEMAPHORE_FD_INFO_KHR: c_int = 1000079000;

pub const VK_STRUCTURE_TYPE_SEMAPHORE_GET_FD_INFO_KHR: c_int = 1000079001;

pub const VK_STRUCTURE_TYPE_DRM_FORMAT_MODIFIER_PROPERTIES_LIST_EXT: c_int = 1000158000;

pub const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_DRM_FORMAT_MODIFIER_INFO_EXT: c_int = 1000158002;

pub const VK_STRUCTURE_TYPE_IMAGE_DRM_FORMAT_MODIFIER_LIST_CREATE_INFO_EXT: c_int = 1000158003;

pub const VK_STRUCTURE_TYPE_IMAGE_DRM_FORMAT_MODIFIER_PROPERTIES_EXT: c_int = 1000158005;

pub const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRM_PROPERTIES_EXT: c_int = 1000353000;

pub const enum_VkStructureType = c_uint;

pub const VkStructureType = enum_VkStructureType;

pub const VkBaseInStructure = extern struct {
    sType: VkStructureType,
    pNext: ?*const VkBaseInStructure,
};

pub const VkBaseOutStructure = extern struct {
    sType: VkStructureType,
    pNext: ?*VkBaseOutStructure,
};

pub const VK_FORMAT_R8G8B8A8_UNORM: c_int = 37;
pub const VK_FORMAT_R8_UNORM: c_int = 9;
pub const VK_FORMAT_R32G32_SFLOAT: c_int = 103;
pub const VK_FORMAT_R32G32B32A32_SFLOAT: c_int = 109;

pub const enum_VkFormat = c_uint;

pub const VkFormat = enum_VkFormat;

pub const VK_IMAGE_TILING_DRM_FORMAT_MODIFIER_EXT: c_int = 1000158000;

pub const enum_VkImageTiling = c_uint;

pub const VkImageTiling = enum_VkImageTiling;

pub const VK_IMAGE_TYPE_2D: c_int = 1;

pub const enum_VkImageType = c_uint;

pub const VkImageType = enum_VkImageType;

pub const enum_VkPhysicalDeviceType = c_uint;

pub const VkPhysicalDeviceType = enum_VkPhysicalDeviceType;

pub const VK_SHARING_MODE_EXCLUSIVE: c_int = 0;

pub const enum_VkSharingMode = c_uint;

pub const VkSharingMode = enum_VkSharingMode;

pub const VK_IMAGE_LAYOUT_UNDEFINED: c_int = 0;

pub const VK_IMAGE_LAYOUT_GENERAL: c_int = 1;

pub const VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL: c_int = 7;
pub const VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL: c_int = 5;
pub const VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL: c_int = 2;

pub const enum_VkImageLayout = c_uint;

pub const VkImageLayout = enum_VkImageLayout;

pub const VK_COMMAND_BUFFER_LEVEL_PRIMARY: c_int = 0;

pub const enum_VkCommandBufferLevel = c_uint;

pub const VkCommandBufferLevel = enum_VkCommandBufferLevel;

pub const VkFormatFeatureFlags = VkFlags;

pub const VkImageCreateFlags = VkFlags;

pub const VK_SAMPLE_COUNT_1_BIT: c_int = 1;

pub const enum_VkSampleCountFlagBits = c_uint;

pub const VkSampleCountFlagBits = enum_VkSampleCountFlagBits;

pub const VkSampleCountFlags = VkFlags;

pub const VK_IMAGE_USAGE_TRANSFER_DST_BIT: c_int = 2;
pub const VK_IMAGE_USAGE_SAMPLED_BIT: c_int = 4;
pub const VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT: c_int = 16;

pub const VkImageUsageFlags = VkFlags;

pub const VkInstanceCreateFlags = VkFlags;

pub const VkMemoryHeapFlags = VkFlags;

pub const VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT: c_int = 1;
pub const VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT: c_int = 2;
pub const VK_MEMORY_PROPERTY_HOST_COHERENT_BIT: c_int = 4;

pub const VkMemoryPropertyFlags = VkFlags;

pub const VK_BUFFER_USAGE_TRANSFER_SRC_BIT: c_int = 1;
pub const VK_BUFFER_USAGE_TRANSFER_DST_BIT: c_int = 2;
pub const VK_BUFFER_USAGE_STORAGE_BUFFER_BIT: c_int = 32;
pub const VK_BUFFER_USAGE_INDEX_BUFFER_BIT: c_int = 64;
pub const VK_BUFFER_USAGE_VERTEX_BUFFER_BIT: c_int = 128;
pub const VkBufferUsageFlags = VkFlags;
pub const VkBufferCreateFlags = VkFlags;

pub const VK_QUEUE_GRAPHICS_BIT: c_int = 1;

pub const VkQueueFlags = VkFlags;

pub const VkDeviceCreateFlags = VkFlags;

pub const VkDeviceQueueCreateFlags = VkFlags;

pub const VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT: c_int = 1;

pub const VK_PIPELINE_STAGE_VERTEX_SHADER_BIT: c_int = 8;

pub const VK_PIPELINE_STAGE_TRANSFER_BIT: c_int = 4096;

pub const VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT: c_int = 8192;
pub const VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT: c_int = 128;
pub const VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT: c_int = 1024;

pub const VkPipelineStageFlags = VkFlags;

pub const VK_IMAGE_ASPECT_COLOR_BIT: c_int = 1;

pub const VK_IMAGE_ASPECT_MEMORY_PLANE_0_BIT_EXT: c_int = 128;

pub const VK_IMAGE_ASPECT_MEMORY_PLANE_1_BIT_EXT: c_int = 256;

pub const VK_IMAGE_ASPECT_MEMORY_PLANE_2_BIT_EXT: c_int = 512;

pub const VK_IMAGE_ASPECT_MEMORY_PLANE_3_BIT_EXT: c_int = 1024;

pub const VkImageAspectFlags = VkFlags;

pub const VkSemaphoreCreateFlags = VkFlags;

pub const VkQueryPipelineStatisticFlags = VkFlags;

pub const VK_ACCESS_TRANSFER_WRITE_BIT: c_int = 4096;
pub const VK_ACCESS_SHADER_READ_BIT: c_int = 32;
pub const VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT: c_int = 256;

pub const VK_IMAGE_VIEW_TYPE_2D: c_int = 1;
pub const VK_COMPONENT_SWIZZLE_IDENTITY: c_int = 0;
pub const VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST: c_int = 3;
pub const VK_POLYGON_MODE_FILL: c_int = 0;
pub const VK_CULL_MODE_NONE: c_int = 0;
pub const VK_FRONT_FACE_COUNTER_CLOCKWISE: c_int = 0;
pub const VK_COLOR_COMPONENT_R_BIT: c_int = 1;
pub const VK_COLOR_COMPONENT_G_BIT: c_int = 2;
pub const VK_COLOR_COMPONENT_B_BIT: c_int = 4;
pub const VK_COLOR_COMPONENT_A_BIT: c_int = 8;
pub const VK_SHADER_STAGE_VERTEX_BIT: c_int = 1;
pub const VK_SHADER_STAGE_FRAGMENT_BIT: c_int = 16;
pub const VK_DYNAMIC_STATE_VIEWPORT: c_int = 0;
pub const VK_DYNAMIC_STATE_SCISSOR: c_int = 1;
pub const VK_PIPELINE_BIND_POINT_GRAPHICS: c_int = 0;
pub const VK_BLEND_FACTOR_ZERO: c_int = 0;
pub const VK_BLEND_FACTOR_ONE: c_int = 1;
pub const VK_BLEND_FACTOR_SRC_ALPHA: c_int = 6;
pub const VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA: c_int = 7;
pub const VK_BLEND_OP_ADD: c_int = 0;
pub const VK_INDEX_TYPE_UINT32: c_int = 1;
pub const VK_ATTACHMENT_LOAD_OP_CLEAR: c_int = 1;
pub const VK_ATTACHMENT_LOAD_OP_DONT_CARE: c_int = 2;
pub const VK_ATTACHMENT_STORE_OP_STORE: c_int = 0;
pub const VK_ATTACHMENT_STORE_OP_DONT_CARE: c_int = 1;
pub const VK_SUBPASS_CONTENTS_INLINE: c_int = 0;
pub const VK_SUBPASS_EXTERNAL: u32 = ~@as(u32, 0);
pub const VK_FILTER_NEAREST: c_int = 0;
pub const VK_FILTER_LINEAR: c_int = 1;
pub const VK_SAMPLER_MIPMAP_MODE_NEAREST: c_int = 0;
pub const VK_SAMPLER_MIPMAP_MODE_LINEAR: c_int = 1;
pub const VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE: c_int = 2;
pub const VK_BORDER_COLOR_FLOAT_TRANSPARENT_BLACK: c_int = 0;
pub const VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER: c_int = 1;
pub const VK_DESCRIPTOR_TYPE_STORAGE_BUFFER: c_int = 7;

pub const VkAccessFlags = VkFlags;

pub const VkDependencyFlags = VkFlags;

pub const VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT: c_int = 2;

pub const VkCommandPoolCreateFlags = VkFlags;

pub const VkQueryControlFlags = VkFlags;

pub const VkCommandBufferUsageFlags = VkFlags;

pub const VkCommandBufferResetFlags = VkFlags;

pub const VkImageViewCreateFlags = VkFlags;
pub const VkShaderModuleCreateFlags = VkFlags;
pub const VkPipelineShaderStageCreateFlags = VkFlags;
pub const VkPipelineVertexInputStateCreateFlags = VkFlags;
pub const VkPipelineInputAssemblyStateCreateFlags = VkFlags;
pub const VkPipelineViewportStateCreateFlags = VkFlags;
pub const VkPipelineRasterizationStateCreateFlags = VkFlags;
pub const VkPipelineMultisampleStateCreateFlags = VkFlags;
pub const VkPipelineColorBlendStateCreateFlags = VkFlags;
pub const VkPipelineDynamicStateCreateFlags = VkFlags;
pub const VkPipelineLayoutCreateFlags = VkFlags;
pub const VkPipelineCreateFlags = VkFlags;
pub const VkAttachmentDescriptionFlags = VkFlags;
pub const VkSubpassDescriptionFlags = VkFlags;
pub const VkRenderPassCreateFlags = VkFlags;
pub const VkFramebufferCreateFlags = VkFlags;
pub const VkSamplerCreateFlags = VkFlags;
pub const VkDescriptorSetLayoutCreateFlags = VkFlags;
pub const VkDescriptorPoolCreateFlags = VkFlags;
pub const VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT: c_int = 1;
pub const VkCullModeFlags = VkFlags;
pub const VkColorComponentFlags = VkFlags;
pub const VkShaderStageFlags = VkFlags;
pub const VkShaderStageFlagBits = c_uint;
pub const VkSampleMask = u32;
pub const VkImageViewType = c_uint;
pub const VkComponentSwizzle = c_uint;
pub const VkVertexInputRate = c_uint;
pub const VkPrimitiveTopology = c_uint;
pub const VkPolygonMode = c_uint;
pub const VkFrontFace = c_uint;
pub const VkBlendFactor = c_uint;
pub const VkBlendOp = c_uint;
pub const VkLogicOp = c_uint;
pub const VkDynamicState = c_uint;
pub const VkPipelineBindPoint = c_uint;
pub const VkAttachmentLoadOp = c_uint;
pub const VkAttachmentStoreOp = c_uint;
pub const VkSubpassContents = c_uint;
pub const VkFilter = c_uint;
pub const VkSamplerMipmapMode = c_uint;
pub const VkSamplerAddressMode = c_uint;
pub const VkCompareOp = c_uint;
pub const VkBorderColor = c_uint;
pub const VkDescriptorType = c_uint;
pub const VkIndexType = c_uint;

pub const struct_VkExtent3D = extern struct {
    width: u32 = 0,
    height: u32 = 0,
    depth: u32 = 0,
};

pub const VkExtent3D = struct_VkExtent3D;

pub const VkExtent2D = extern struct { width: u32 = 0, height: u32 = 0 };
pub const VkOffset2D = extern struct { x: i32 = 0, y: i32 = 0 };
pub const VkRect2D = extern struct { offset: VkOffset2D = .{}, extent: VkExtent2D = .{} };
pub const VkComponentMapping = extern struct {
    r: VkComponentSwizzle = VK_COMPONENT_SWIZZLE_IDENTITY,
    g: VkComponentSwizzle = VK_COMPONENT_SWIZZLE_IDENTITY,
    b: VkComponentSwizzle = VK_COMPONENT_SWIZZLE_IDENTITY,
    a: VkComponentSwizzle = VK_COMPONENT_SWIZZLE_IDENTITY,
};
pub const VkClearDepthStencilValue = extern struct { depth: f32, stencil: u32 };
pub const VkClearValue = extern union {
    color: VkClearColorValue,
    depthStencil: VkClearDepthStencilValue,
};

pub const VkImageViewCreateInfo = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
    pNext: ?*const VkBaseInStructure = null,
    flags: VkImageViewCreateFlags = 0,
    image: VkImage = null,
    viewType: VkImageViewType = VK_IMAGE_VIEW_TYPE_2D,
    format: VkFormat = VK_FORMAT_R8G8B8A8_UNORM,
    components: VkComponentMapping = .{},
    subresourceRange: VkImageSubresourceRange = .{},
};
pub const VkShaderModuleCreateInfo = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
    pNext: ?*const VkBaseInStructure = null,
    flags: VkShaderModuleCreateFlags = 0,
    codeSize: usize = 0,
    pCode: [*c]const u32 = null,
};
pub const VkSpecializationInfo = opaque {};
pub const VkPipelineShaderStageCreateInfo = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
    pNext: ?*const VkBaseInStructure = null,
    flags: VkPipelineShaderStageCreateFlags = 0,
    stage: VkShaderStageFlagBits = 0,
    module: VkShaderModule = null,
    pName: [*c]const u8 = null,
    pSpecializationInfo: ?*const VkSpecializationInfo = null,
};
pub const VkVertexInputBindingDescription = extern struct { binding: u32 = 0, stride: u32 = 0, inputRate: VkVertexInputRate = 0 };
pub const VkVertexInputAttributeDescription = extern struct { location: u32 = 0, binding: u32 = 0, format: VkFormat = 0, offset: u32 = 0 };
pub const VkPipelineVertexInputStateCreateInfo = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    pNext: ?*const VkBaseInStructure = null,
    flags: VkPipelineVertexInputStateCreateFlags = 0,
    vertexBindingDescriptionCount: u32 = 0,
    pVertexBindingDescriptions: [*c]const VkVertexInputBindingDescription = null,
    vertexAttributeDescriptionCount: u32 = 0,
    pVertexAttributeDescriptions: [*c]const VkVertexInputAttributeDescription = null,
};
pub const VkPipelineInputAssemblyStateCreateInfo = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
    pNext: ?*const VkBaseInStructure = null,
    flags: VkPipelineInputAssemblyStateCreateFlags = 0,
    topology: VkPrimitiveTopology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
    primitiveRestartEnable: VkBool32 = 0,
};
pub const VkViewport = extern struct { x: f32 = 0, y: f32 = 0, width: f32 = 0, height: f32 = 0, minDepth: f32 = 0, maxDepth: f32 = 1 };
pub const VkPipelineViewportStateCreateInfo = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
    pNext: ?*const VkBaseInStructure = null,
    flags: VkPipelineViewportStateCreateFlags = 0,
    viewportCount: u32 = 0,
    pViewports: [*c]const VkViewport = null,
    scissorCount: u32 = 0,
    pScissors: [*c]const VkRect2D = null,
};
pub const VkPipelineRasterizationStateCreateInfo = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
    pNext: ?*const VkBaseInStructure = null,
    flags: VkPipelineRasterizationStateCreateFlags = 0,
    depthClampEnable: VkBool32 = 0,
    rasterizerDiscardEnable: VkBool32 = 0,
    polygonMode: VkPolygonMode = VK_POLYGON_MODE_FILL,
    cullMode: VkCullModeFlags = VK_CULL_MODE_NONE,
    frontFace: VkFrontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE,
    depthBiasEnable: VkBool32 = 0,
    depthBiasConstantFactor: f32 = 0,
    depthBiasClamp: f32 = 0,
    depthBiasSlopeFactor: f32 = 0,
    lineWidth: f32 = 1,
};
pub const VkPipelineMultisampleStateCreateInfo = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
    pNext: ?*const VkBaseInStructure = null,
    flags: VkPipelineMultisampleStateCreateFlags = 0,
    rasterizationSamples: VkSampleCountFlagBits = VK_SAMPLE_COUNT_1_BIT,
    sampleShadingEnable: VkBool32 = 0,
    minSampleShading: f32 = 0,
    pSampleMask: [*c]const VkSampleMask = null,
    alphaToCoverageEnable: VkBool32 = 0,
    alphaToOneEnable: VkBool32 = 0,
};
pub const VkPipelineColorBlendAttachmentState = extern struct {
    blendEnable: VkBool32 = 0,
    srcColorBlendFactor: VkBlendFactor = VK_BLEND_FACTOR_ONE,
    dstColorBlendFactor: VkBlendFactor = VK_BLEND_FACTOR_ZERO,
    colorBlendOp: VkBlendOp = VK_BLEND_OP_ADD,
    srcAlphaBlendFactor: VkBlendFactor = VK_BLEND_FACTOR_ONE,
    dstAlphaBlendFactor: VkBlendFactor = VK_BLEND_FACTOR_ZERO,
    alphaBlendOp: VkBlendOp = VK_BLEND_OP_ADD,
    colorWriteMask: VkColorComponentFlags = 0,
};
pub const VkPipelineColorBlendStateCreateInfo = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
    pNext: ?*const VkBaseInStructure = null,
    flags: VkPipelineColorBlendStateCreateFlags = 0,
    logicOpEnable: VkBool32 = 0,
    logicOp: VkLogicOp = 0,
    attachmentCount: u32 = 0,
    pAttachments: [*c]const VkPipelineColorBlendAttachmentState = null,
    blendConstants: [4]f32 = .{ 0, 0, 0, 0 },
};
pub const VkPipelineDynamicStateCreateInfo = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
    pNext: ?*const VkBaseInStructure = null,
    flags: VkPipelineDynamicStateCreateFlags = 0,
    dynamicStateCount: u32 = 0,
    pDynamicStates: [*c]const VkDynamicState = null,
};
pub const VkPushConstantRange = extern struct { stageFlags: VkShaderStageFlags = 0, offset: u32 = 0, size: u32 = 0 };
pub const VkPipelineLayoutCreateInfo = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
    pNext: ?*const VkBaseInStructure = null,
    flags: VkPipelineLayoutCreateFlags = 0,
    setLayoutCount: u32 = 0,
    pSetLayouts: [*c]const VkDescriptorSetLayout = null,
    pushConstantRangeCount: u32 = 0,
    pPushConstantRanges: [*c]const VkPushConstantRange = null,
};
pub const VkAttachmentDescription = extern struct {
    flags: VkAttachmentDescriptionFlags = 0,
    format: VkFormat = 0,
    samples: VkSampleCountFlagBits = VK_SAMPLE_COUNT_1_BIT,
    loadOp: VkAttachmentLoadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
    storeOp: VkAttachmentStoreOp = VK_ATTACHMENT_STORE_OP_STORE,
    stencilLoadOp: VkAttachmentLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE,
    stencilStoreOp: VkAttachmentStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
    initialLayout: VkImageLayout = VK_IMAGE_LAYOUT_UNDEFINED,
    finalLayout: VkImageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
};
pub const VkAttachmentReference = extern struct { attachment: u32 = 0, layout: VkImageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL };
pub const VkSubpassDescription = extern struct {
    flags: VkSubpassDescriptionFlags = 0,
    pipelineBindPoint: VkPipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS,
    inputAttachmentCount: u32 = 0,
    pInputAttachments: [*c]const VkAttachmentReference = null,
    colorAttachmentCount: u32 = 0,
    pColorAttachments: [*c]const VkAttachmentReference = null,
    pResolveAttachments: [*c]const VkAttachmentReference = null,
    pDepthStencilAttachment: ?*const opaque {} = null,
    preserveAttachmentCount: u32 = 0,
    pPreserveAttachments: [*c]const u32 = null,
};
pub const VkSubpassDependency = extern struct {
    srcSubpass: u32 = 0,
    dstSubpass: u32 = 0,
    srcStageMask: VkPipelineStageFlags = 0,
    dstStageMask: VkPipelineStageFlags = 0,
    srcAccessMask: VkAccessFlags = 0,
    dstAccessMask: VkAccessFlags = 0,
    dependencyFlags: VkDependencyFlags = 0,
};
pub const VkRenderPassCreateInfo = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
    pNext: ?*const VkBaseInStructure = null,
    flags: VkRenderPassCreateFlags = 0,
    attachmentCount: u32 = 0,
    pAttachments: [*c]const VkAttachmentDescription = null,
    subpassCount: u32 = 0,
    pSubpasses: [*c]const VkSubpassDescription = null,
    dependencyCount: u32 = 0,
    pDependencies: [*c]const VkSubpassDependency = null,
};
pub const VkFramebufferCreateInfo = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
    pNext: ?*const VkBaseInStructure = null,
    flags: VkFramebufferCreateFlags = 0,
    renderPass: VkRenderPass = null,
    attachmentCount: u32 = 0,
    pAttachments: [*c]const VkImageView = null,
    width: u32 = 0,
    height: u32 = 0,
    layers: u32 = 0,
};
pub const VkPipelineTessellationStateCreateInfo = opaque {};
pub const VkPipelineDepthStencilStateCreateInfo = opaque {};
pub const VkGraphicsPipelineCreateInfo = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
    pNext: ?*const VkBaseInStructure = null,
    flags: VkPipelineCreateFlags = 0,
    stageCount: u32 = 0,
    pStages: [*c]const VkPipelineShaderStageCreateInfo = null,
    pVertexInputState: [*c]const VkPipelineVertexInputStateCreateInfo = null,
    pInputAssemblyState: [*c]const VkPipelineInputAssemblyStateCreateInfo = null,
    pTessellationState: ?*const VkPipelineTessellationStateCreateInfo = null,
    pViewportState: [*c]const VkPipelineViewportStateCreateInfo = null,
    pRasterizationState: [*c]const VkPipelineRasterizationStateCreateInfo = null,
    pMultisampleState: [*c]const VkPipelineMultisampleStateCreateInfo = null,
    pDepthStencilState: ?*const VkPipelineDepthStencilStateCreateInfo = null,
    pColorBlendState: [*c]const VkPipelineColorBlendStateCreateInfo = null,
    pDynamicState: [*c]const VkPipelineDynamicStateCreateInfo = null,
    layout: VkPipelineLayout = null,
    renderPass: VkRenderPass = null,
    subpass: u32 = 0,
    basePipelineHandle: VkPipeline = null,
    basePipelineIndex: i32 = 0,
};
pub const VkRenderPassBeginInfo = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
    pNext: ?*const VkBaseInStructure = null,
    renderPass: VkRenderPass = null,
    framebuffer: VkFramebuffer = null,
    renderArea: VkRect2D = .{},
    clearValueCount: u32 = 0,
    pClearValues: [*c]const VkClearValue = null,
};
pub const VkSamplerCreateInfo = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
    pNext: ?*const VkBaseInStructure = null,
    flags: VkSamplerCreateFlags = 0,
    magFilter: VkFilter = VK_FILTER_LINEAR,
    minFilter: VkFilter = VK_FILTER_LINEAR,
    mipmapMode: VkSamplerMipmapMode = VK_SAMPLER_MIPMAP_MODE_LINEAR,
    addressModeU: VkSamplerAddressMode = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
    addressModeV: VkSamplerAddressMode = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
    addressModeW: VkSamplerAddressMode = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
    mipLodBias: f32 = 0,
    anisotropyEnable: VkBool32 = 0,
    maxAnisotropy: f32 = 1,
    compareEnable: VkBool32 = 0,
    compareOp: VkCompareOp = 0,
    minLod: f32 = 0,
    maxLod: f32 = 0,
    borderColor: VkBorderColor = VK_BORDER_COLOR_FLOAT_TRANSPARENT_BLACK,
    unnormalizedCoordinates: VkBool32 = 0,
};
pub const VkDescriptorSetLayoutBinding = extern struct {
    binding: u32 = 0,
    descriptorType: VkDescriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
    descriptorCount: u32 = 0,
    stageFlags: VkShaderStageFlags = 0,
    pImmutableSamplers: [*c]const VkSampler = null,
};
pub const VkDescriptorSetLayoutCreateInfo = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
    pNext: ?*const VkBaseInStructure = null,
    flags: VkDescriptorSetLayoutCreateFlags = 0,
    bindingCount: u32 = 0,
    pBindings: [*c]const VkDescriptorSetLayoutBinding = null,
};
pub const VkDescriptorPoolSize = extern struct { type: VkDescriptorType = 0, descriptorCount: u32 = 0 };
pub const VkDescriptorPoolCreateInfo = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
    pNext: ?*const VkBaseInStructure = null,
    flags: VkDescriptorPoolCreateFlags = 0,
    maxSets: u32 = 0,
    poolSizeCount: u32 = 0,
    pPoolSizes: [*c]const VkDescriptorPoolSize = null,
};
pub const VkDescriptorSetAllocateInfo = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
    pNext: ?*const VkBaseInStructure = null,
    descriptorPool: VkDescriptorPool = null,
    descriptorSetCount: u32 = 0,
    pSetLayouts: [*c]const VkDescriptorSetLayout = null,
};
pub const VkDescriptorImageInfo = extern struct {
    sampler: VkSampler = null,
    imageView: VkImageView = null,
    imageLayout: VkImageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
};
pub const VkDescriptorBufferInfo = extern struct {
    buffer: VkBuffer = null,
    offset: VkDeviceSize = 0,
    range: VkDeviceSize = 0,
};
pub const VkWriteDescriptorSet = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
    pNext: ?*const VkBaseInStructure = null,
    dstSet: VkDescriptorSet = null,
    dstBinding: u32 = 0,
    dstArrayElement: u32 = 0,
    descriptorCount: u32 = 0,
    descriptorType: VkDescriptorType = 0,
    pImageInfo: [*c]const VkDescriptorImageInfo = null,
    pBufferInfo: ?*const VkDescriptorBufferInfo = null,
    pTexelBufferView: [*c]const VkBufferView = null,
};

pub const PFN_vkVoidFunction = ?*const fn () callconv(.c) void;

pub const VkAllocationCallbacks = opaque {};

pub const struct_VkApplicationInfo = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    pApplicationName: [*c]const u8 = null,
    applicationVersion: u32 = 0,
    pEngineName: [*c]const u8 = null,
    engineVersion: u32 = 0,
    apiVersion: u32 = 0,
};

pub const VkApplicationInfo = struct_VkApplicationInfo;

pub const struct_VkFormatProperties = extern struct {
    linearTilingFeatures: VkFormatFeatureFlags = 0,
    optimalTilingFeatures: VkFormatFeatureFlags = 0,
    bufferFeatures: VkFormatFeatureFlags = 0,
};

pub const VkFormatProperties = struct_VkFormatProperties;

pub const struct_VkImageFormatProperties = extern struct {
    maxExtent: VkExtent3D = @import("std").mem.zeroes(VkExtent3D),
    maxMipLevels: u32 = 0,
    maxArrayLayers: u32 = 0,
    sampleCounts: VkSampleCountFlags = 0,
    maxResourceSize: VkDeviceSize = 0,
};

pub const VkImageFormatProperties = struct_VkImageFormatProperties;

pub const struct_VkInstanceCreateInfo = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    flags: VkInstanceCreateFlags = 0,
    pApplicationInfo: [*c]const VkApplicationInfo = null,
    enabledLayerCount: u32 = 0,
    ppEnabledLayerNames: [*c]const [*c]const u8 = null,
    enabledExtensionCount: u32 = 0,
    ppEnabledExtensionNames: [*c]const [*c]const u8 = null,
};

pub const VkInstanceCreateInfo = struct_VkInstanceCreateInfo;

pub const struct_VkMemoryHeap = extern struct {
    size: VkDeviceSize = 0,
    flags: VkMemoryHeapFlags = 0,
};

pub const VkMemoryHeap = struct_VkMemoryHeap;

pub const struct_VkMemoryType = extern struct {
    propertyFlags: VkMemoryPropertyFlags = 0,
    heapIndex: u32 = 0,
};

pub const VkMemoryType = struct_VkMemoryType;

pub const struct_VkPhysicalDeviceFeatures = extern struct {
    robustBufferAccess: VkBool32 = 0,
    fullDrawIndexUint32: VkBool32 = 0,
    imageCubeArray: VkBool32 = 0,
    independentBlend: VkBool32 = 0,
    geometryShader: VkBool32 = 0,
    tessellationShader: VkBool32 = 0,
    sampleRateShading: VkBool32 = 0,
    dualSrcBlend: VkBool32 = 0,
    logicOp: VkBool32 = 0,
    multiDrawIndirect: VkBool32 = 0,
    drawIndirectFirstInstance: VkBool32 = 0,
    depthClamp: VkBool32 = 0,
    depthBiasClamp: VkBool32 = 0,
    fillModeNonSolid: VkBool32 = 0,
    depthBounds: VkBool32 = 0,
    wideLines: VkBool32 = 0,
    largePoints: VkBool32 = 0,
    alphaToOne: VkBool32 = 0,
    multiViewport: VkBool32 = 0,
    samplerAnisotropy: VkBool32 = 0,
    textureCompressionETC2: VkBool32 = 0,
    textureCompressionASTC_LDR: VkBool32 = 0,
    textureCompressionBC: VkBool32 = 0,
    occlusionQueryPrecise: VkBool32 = 0,
    pipelineStatisticsQuery: VkBool32 = 0,
    vertexPipelineStoresAndAtomics: VkBool32 = 0,
    fragmentStoresAndAtomics: VkBool32 = 0,
    shaderTessellationAndGeometryPointSize: VkBool32 = 0,
    shaderImageGatherExtended: VkBool32 = 0,
    shaderStorageImageExtendedFormats: VkBool32 = 0,
    shaderStorageImageMultisample: VkBool32 = 0,
    shaderStorageImageReadWithoutFormat: VkBool32 = 0,
    shaderStorageImageWriteWithoutFormat: VkBool32 = 0,
    shaderUniformBufferArrayDynamicIndexing: VkBool32 = 0,
    shaderSampledImageArrayDynamicIndexing: VkBool32 = 0,
    shaderStorageBufferArrayDynamicIndexing: VkBool32 = 0,
    shaderStorageImageArrayDynamicIndexing: VkBool32 = 0,
    shaderClipDistance: VkBool32 = 0,
    shaderCullDistance: VkBool32 = 0,
    shaderFloat64: VkBool32 = 0,
    shaderInt64: VkBool32 = 0,
    shaderInt16: VkBool32 = 0,
    shaderResourceResidency: VkBool32 = 0,
    shaderResourceMinLod: VkBool32 = 0,
    sparseBinding: VkBool32 = 0,
    sparseResidencyBuffer: VkBool32 = 0,
    sparseResidencyImage2D: VkBool32 = 0,
    sparseResidencyImage3D: VkBool32 = 0,
    sparseResidency2Samples: VkBool32 = 0,
    sparseResidency4Samples: VkBool32 = 0,
    sparseResidency8Samples: VkBool32 = 0,
    sparseResidency16Samples: VkBool32 = 0,
    sparseResidencyAliased: VkBool32 = 0,
    variableMultisampleRate: VkBool32 = 0,
    inheritedQueries: VkBool32 = 0,
};

pub const VkPhysicalDeviceFeatures = struct_VkPhysicalDeviceFeatures;

pub const struct_VkPhysicalDeviceLimits = extern struct {
    maxImageDimension1D: u32 = 0,
    maxImageDimension2D: u32 = 0,
    maxImageDimension3D: u32 = 0,
    maxImageDimensionCube: u32 = 0,
    maxImageArrayLayers: u32 = 0,
    maxTexelBufferElements: u32 = 0,
    maxUniformBufferRange: u32 = 0,
    maxStorageBufferRange: u32 = 0,
    maxPushConstantsSize: u32 = 0,
    maxMemoryAllocationCount: u32 = 0,
    maxSamplerAllocationCount: u32 = 0,
    bufferImageGranularity: VkDeviceSize = 0,
    sparseAddressSpaceSize: VkDeviceSize = 0,
    maxBoundDescriptorSets: u32 = 0,
    maxPerStageDescriptorSamplers: u32 = 0,
    maxPerStageDescriptorUniformBuffers: u32 = 0,
    maxPerStageDescriptorStorageBuffers: u32 = 0,
    maxPerStageDescriptorSampledImages: u32 = 0,
    maxPerStageDescriptorStorageImages: u32 = 0,
    maxPerStageDescriptorInputAttachments: u32 = 0,
    maxPerStageResources: u32 = 0,
    maxDescriptorSetSamplers: u32 = 0,
    maxDescriptorSetUniformBuffers: u32 = 0,
    maxDescriptorSetUniformBuffersDynamic: u32 = 0,
    maxDescriptorSetStorageBuffers: u32 = 0,
    maxDescriptorSetStorageBuffersDynamic: u32 = 0,
    maxDescriptorSetSampledImages: u32 = 0,
    maxDescriptorSetStorageImages: u32 = 0,
    maxDescriptorSetInputAttachments: u32 = 0,
    maxVertexInputAttributes: u32 = 0,
    maxVertexInputBindings: u32 = 0,
    maxVertexInputAttributeOffset: u32 = 0,
    maxVertexInputBindingStride: u32 = 0,
    maxVertexOutputComponents: u32 = 0,
    maxTessellationGenerationLevel: u32 = 0,
    maxTessellationPatchSize: u32 = 0,
    maxTessellationControlPerVertexInputComponents: u32 = 0,
    maxTessellationControlPerVertexOutputComponents: u32 = 0,
    maxTessellationControlPerPatchOutputComponents: u32 = 0,
    maxTessellationControlTotalOutputComponents: u32 = 0,
    maxTessellationEvaluationInputComponents: u32 = 0,
    maxTessellationEvaluationOutputComponents: u32 = 0,
    maxGeometryShaderInvocations: u32 = 0,
    maxGeometryInputComponents: u32 = 0,
    maxGeometryOutputComponents: u32 = 0,
    maxGeometryOutputVertices: u32 = 0,
    maxGeometryTotalOutputComponents: u32 = 0,
    maxFragmentInputComponents: u32 = 0,
    maxFragmentOutputAttachments: u32 = 0,
    maxFragmentDualSrcAttachments: u32 = 0,
    maxFragmentCombinedOutputResources: u32 = 0,
    maxComputeSharedMemorySize: u32 = 0,
    maxComputeWorkGroupCount: [3]u32 = @import("std").mem.zeroes([3]u32),
    maxComputeWorkGroupInvocations: u32 = 0,
    maxComputeWorkGroupSize: [3]u32 = @import("std").mem.zeroes([3]u32),
    subPixelPrecisionBits: u32 = 0,
    subTexelPrecisionBits: u32 = 0,
    mipmapPrecisionBits: u32 = 0,
    maxDrawIndexedIndexValue: u32 = 0,
    maxDrawIndirectCount: u32 = 0,
    maxSamplerLodBias: f32 = 0,
    maxSamplerAnisotropy: f32 = 0,
    maxViewports: u32 = 0,
    maxViewportDimensions: [2]u32 = @import("std").mem.zeroes([2]u32),
    viewportBoundsRange: [2]f32 = @import("std").mem.zeroes([2]f32),
    viewportSubPixelBits: u32 = 0,
    minMemoryMapAlignment: usize = 0,
    minTexelBufferOffsetAlignment: VkDeviceSize = 0,
    minUniformBufferOffsetAlignment: VkDeviceSize = 0,
    minStorageBufferOffsetAlignment: VkDeviceSize = 0,
    minTexelOffset: i32 = 0,
    maxTexelOffset: u32 = 0,
    minTexelGatherOffset: i32 = 0,
    maxTexelGatherOffset: u32 = 0,
    minInterpolationOffset: f32 = 0,
    maxInterpolationOffset: f32 = 0,
    subPixelInterpolationOffsetBits: u32 = 0,
    maxFramebufferWidth: u32 = 0,
    maxFramebufferHeight: u32 = 0,
    maxFramebufferLayers: u32 = 0,
    framebufferColorSampleCounts: VkSampleCountFlags = 0,
    framebufferDepthSampleCounts: VkSampleCountFlags = 0,
    framebufferStencilSampleCounts: VkSampleCountFlags = 0,
    framebufferNoAttachmentsSampleCounts: VkSampleCountFlags = 0,
    maxColorAttachments: u32 = 0,
    sampledImageColorSampleCounts: VkSampleCountFlags = 0,
    sampledImageIntegerSampleCounts: VkSampleCountFlags = 0,
    sampledImageDepthSampleCounts: VkSampleCountFlags = 0,
    sampledImageStencilSampleCounts: VkSampleCountFlags = 0,
    storageImageSampleCounts: VkSampleCountFlags = 0,
    maxSampleMaskWords: u32 = 0,
    timestampComputeAndGraphics: VkBool32 = 0,
    timestampPeriod: f32 = 0,
    maxClipDistances: u32 = 0,
    maxCullDistances: u32 = 0,
    maxCombinedClipAndCullDistances: u32 = 0,
    discreteQueuePriorities: u32 = 0,
    pointSizeRange: [2]f32 = @import("std").mem.zeroes([2]f32),
    lineWidthRange: [2]f32 = @import("std").mem.zeroes([2]f32),
    pointSizeGranularity: f32 = 0,
    lineWidthGranularity: f32 = 0,
    strictLines: VkBool32 = 0,
    standardSampleLocations: VkBool32 = 0,
    optimalBufferCopyOffsetAlignment: VkDeviceSize = 0,
    optimalBufferCopyRowPitchAlignment: VkDeviceSize = 0,
    nonCoherentAtomSize: VkDeviceSize = 0,
};

pub const VkPhysicalDeviceLimits = struct_VkPhysicalDeviceLimits;

pub const struct_VkPhysicalDeviceMemoryProperties = extern struct {
    memoryTypeCount: u32 = 0,
    memoryTypes: [32]VkMemoryType = @import("std").mem.zeroes([32]VkMemoryType),
    memoryHeapCount: u32 = 0,
    memoryHeaps: [16]VkMemoryHeap = @import("std").mem.zeroes([16]VkMemoryHeap),
};

pub const VkPhysicalDeviceMemoryProperties = struct_VkPhysicalDeviceMemoryProperties;

pub const struct_VkPhysicalDeviceSparseProperties = extern struct {
    residencyStandard2DBlockShape: VkBool32 = 0,
    residencyStandard2DMultisampleBlockShape: VkBool32 = 0,
    residencyStandard3DBlockShape: VkBool32 = 0,
    residencyAlignedMipSize: VkBool32 = 0,
    residencyNonResidentStrict: VkBool32 = 0,
};

pub const VkPhysicalDeviceSparseProperties = struct_VkPhysicalDeviceSparseProperties;

pub const struct_VkPhysicalDeviceProperties = extern struct {
    apiVersion: u32 = 0,
    driverVersion: u32 = 0,
    vendorID: u32 = 0,
    deviceID: u32 = 0,
    deviceType: VkPhysicalDeviceType = @import("std").mem.zeroes(VkPhysicalDeviceType),
    deviceName: [256]u8 = @import("std").mem.zeroes([256]u8),
    pipelineCacheUUID: [16]u8 = @import("std").mem.zeroes([16]u8),
    limits: VkPhysicalDeviceLimits = @import("std").mem.zeroes(VkPhysicalDeviceLimits),
    sparseProperties: VkPhysicalDeviceSparseProperties = @import("std").mem.zeroes(VkPhysicalDeviceSparseProperties),
};

pub const VkPhysicalDeviceProperties = struct_VkPhysicalDeviceProperties;

pub const struct_VkQueueFamilyProperties = extern struct {
    queueFlags: VkQueueFlags = 0,
    queueCount: u32 = 0,
    timestampValidBits: u32 = 0,
    minImageTransferGranularity: VkExtent3D = @import("std").mem.zeroes(VkExtent3D),
};

pub const VkQueueFamilyProperties = struct_VkQueueFamilyProperties;

pub const struct_VkDeviceQueueCreateInfo = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    flags: VkDeviceQueueCreateFlags = 0,
    queueFamilyIndex: u32 = 0,
    queueCount: u32 = 0,
    pQueuePriorities: [*c]const f32 = null,
};

pub const VkDeviceQueueCreateInfo = struct_VkDeviceQueueCreateInfo;

pub const struct_VkDeviceCreateInfo = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    flags: VkDeviceCreateFlags = 0,
    queueCreateInfoCount: u32 = 0,
    pQueueCreateInfos: [*c]const VkDeviceQueueCreateInfo = null,
    enabledLayerCount: u32 = 0,
    ppEnabledLayerNames: [*c]const [*c]const u8 = null,
    enabledExtensionCount: u32 = 0,
    ppEnabledExtensionNames: [*c]const [*c]const u8 = null,
    pEnabledFeatures: [*c]const VkPhysicalDeviceFeatures = null,
};

pub const VkDeviceCreateInfo = struct_VkDeviceCreateInfo;

pub const struct_VkExtensionProperties = extern struct {
    extensionName: [256]u8 = @import("std").mem.zeroes([256]u8),
    specVersion: u32 = 0,
};

pub const VkExtensionProperties = struct_VkExtensionProperties;

pub const struct_VkSubmitInfo = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    waitSemaphoreCount: u32 = 0,
    pWaitSemaphores: [*c]const VkSemaphore = null,
    pWaitDstStageMask: [*c]const VkPipelineStageFlags = null,
    commandBufferCount: u32 = 0,
    pCommandBuffers: [*c]const VkCommandBuffer = null,
    signalSemaphoreCount: u32 = 0,
    pSignalSemaphores: [*c]const VkSemaphore = null,
};

pub const VkSubmitInfo = struct_VkSubmitInfo;

pub const struct_VkMemoryAllocateInfo = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    allocationSize: VkDeviceSize = 0,
    memoryTypeIndex: u32 = 0,
};

pub const VkMemoryAllocateInfo = struct_VkMemoryAllocateInfo;

pub const struct_VkMemoryRequirements = extern struct {
    size: VkDeviceSize = 0,
    alignment: VkDeviceSize = 0,
    memoryTypeBits: u32 = 0,
};

pub const VkMemoryRequirements = struct_VkMemoryRequirements;

pub const struct_VkBufferCreateInfo = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    flags: VkBufferCreateFlags = 0,
    size: VkDeviceSize = 0,
    usage: VkBufferUsageFlags = 0,
    sharingMode: VkSharingMode = @import("std").mem.zeroes(VkSharingMode),
    queueFamilyIndexCount: u32 = 0,
    pQueueFamilyIndices: [*c]const u32 = null,
};
pub const VkBufferCreateInfo = struct_VkBufferCreateInfo;

pub const struct_VkBufferCopy = extern struct {
    srcOffset: VkDeviceSize = 0,
    dstOffset: VkDeviceSize = 0,
    size: VkDeviceSize = 0,
};
pub const VkBufferCopy = struct_VkBufferCopy;

pub const struct_VkBufferImageCopy = extern struct {
    bufferOffset: VkDeviceSize = 0,
    bufferRowLength: u32 = 0,
    bufferImageHeight: u32 = 0,
    imageSubresource: VkImageSubresourceLayers = @import("std").mem.zeroes(VkImageSubresourceLayers),
    imageOffset: VkOffset3D = @import("std").mem.zeroes(VkOffset3D),
    imageExtent: VkExtent3D = @import("std").mem.zeroes(VkExtent3D),
};
pub const VkBufferImageCopy = struct_VkBufferImageCopy;

pub const struct_VkImageSubresource = extern struct {
    aspectMask: VkImageAspectFlags = 0,
    mipLevel: u32 = 0,
    arrayLayer: u32 = 0,
};

pub const VkImageSubresource = struct_VkImageSubresource;

pub const struct_VkImageSubresourceLayers = extern struct {
    aspectMask: VkImageAspectFlags = 0,
    mipLevel: u32 = 0,
    baseArrayLayer: u32 = 0,
    layerCount: u32 = 0,
};
pub const VkImageSubresourceLayers = struct_VkImageSubresourceLayers;

pub const struct_VkOffset3D = extern struct { x: i32 = 0, y: i32 = 0, z: i32 = 0 };
pub const VkOffset3D = struct_VkOffset3D;

pub const struct_VkSemaphoreCreateInfo = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    flags: VkSemaphoreCreateFlags = 0,
};

pub const VkSemaphoreCreateInfo = struct_VkSemaphoreCreateInfo;

pub const struct_VkImageCreateInfo = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    flags: VkImageCreateFlags = 0,
    imageType: VkImageType = @import("std").mem.zeroes(VkImageType),
    format: VkFormat = @import("std").mem.zeroes(VkFormat),
    extent: VkExtent3D = @import("std").mem.zeroes(VkExtent3D),
    mipLevels: u32 = 0,
    arrayLayers: u32 = 0,
    samples: VkSampleCountFlagBits = @import("std").mem.zeroes(VkSampleCountFlagBits),
    tiling: VkImageTiling = @import("std").mem.zeroes(VkImageTiling),
    usage: VkImageUsageFlags = 0,
    sharingMode: VkSharingMode = @import("std").mem.zeroes(VkSharingMode),
    queueFamilyIndexCount: u32 = 0,
    pQueueFamilyIndices: [*c]const u32 = null,
    initialLayout: VkImageLayout = @import("std").mem.zeroes(VkImageLayout),
};

pub const VkImageCreateInfo = struct_VkImageCreateInfo;

pub const struct_VkSubresourceLayout = extern struct {
    offset: VkDeviceSize = 0,
    size: VkDeviceSize = 0,
    rowPitch: VkDeviceSize = 0,
    arrayPitch: VkDeviceSize = 0,
    depthPitch: VkDeviceSize = 0,
};

pub const VkSubresourceLayout = struct_VkSubresourceLayout;

pub const struct_VkImageSubresourceRange = extern struct {
    aspectMask: VkImageAspectFlags = 0,
    baseMipLevel: u32 = 0,
    levelCount: u32 = 0,
    baseArrayLayer: u32 = 0,
    layerCount: u32 = 0,
};

pub const VkImageSubresourceRange = struct_VkImageSubresourceRange;

pub const struct_VkCommandPoolCreateInfo = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    flags: VkCommandPoolCreateFlags = 0,
    queueFamilyIndex: u32 = 0,
};

pub const VkCommandPoolCreateInfo = struct_VkCommandPoolCreateInfo;

pub const struct_VkCommandBufferAllocateInfo = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    commandPool: VkCommandPool = null,
    level: VkCommandBufferLevel = @import("std").mem.zeroes(VkCommandBufferLevel),
    commandBufferCount: u32 = 0,
};

pub const VkCommandBufferAllocateInfo = struct_VkCommandBufferAllocateInfo;

pub const struct_VkCommandBufferInheritanceInfo = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    renderPass: VkRenderPass = null,
    subpass: u32 = 0,
    framebuffer: VkFramebuffer = null,
    occlusionQueryEnable: VkBool32 = 0,
    queryFlags: VkQueryControlFlags = 0,
    pipelineStatistics: VkQueryPipelineStatisticFlags = 0,
};

pub const VkCommandBufferInheritanceInfo = struct_VkCommandBufferInheritanceInfo;

pub const struct_VkCommandBufferBeginInfo = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    flags: VkCommandBufferUsageFlags = 0,
    pInheritanceInfo: [*c]const VkCommandBufferInheritanceInfo = null,
};

pub const VkCommandBufferBeginInfo = struct_VkCommandBufferBeginInfo;

pub const struct_VkBufferMemoryBarrier = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    srcAccessMask: VkAccessFlags = 0,
    dstAccessMask: VkAccessFlags = 0,
    srcQueueFamilyIndex: u32 = 0,
    dstQueueFamilyIndex: u32 = 0,
    buffer: VkBuffer = null,
    offset: VkDeviceSize = 0,
    size: VkDeviceSize = 0,
};

pub const VkBufferMemoryBarrier = struct_VkBufferMemoryBarrier;

pub const struct_VkImageMemoryBarrier = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    srcAccessMask: VkAccessFlags = 0,
    dstAccessMask: VkAccessFlags = 0,
    oldLayout: VkImageLayout = @import("std").mem.zeroes(VkImageLayout),
    newLayout: VkImageLayout = @import("std").mem.zeroes(VkImageLayout),
    srcQueueFamilyIndex: u32 = 0,
    dstQueueFamilyIndex: u32 = 0,
    image: VkImage = null,
    subresourceRange: VkImageSubresourceRange = @import("std").mem.zeroes(VkImageSubresourceRange),
};

pub const VkImageMemoryBarrier = struct_VkImageMemoryBarrier;

pub const struct_VkMemoryBarrier = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    srcAccessMask: VkAccessFlags = 0,
    dstAccessMask: VkAccessFlags = 0,
};

pub const VkMemoryBarrier = struct_VkMemoryBarrier;

pub const union_VkClearColorValue = extern union {
    float32: [4]f32,
    int32: [4]i32,
    uint32: [4]u32,
};

pub const VkClearColorValue = union_VkClearColorValue;

pub extern fn vkCreateInstance(pCreateInfo: [*c]const VkInstanceCreateInfo, pAllocator: ?*const VkAllocationCallbacks, pInstance: [*c]VkInstance) VkResult;

pub extern fn vkDestroyInstance(instance: VkInstance, pAllocator: ?*const VkAllocationCallbacks) void;

pub extern fn vkEnumeratePhysicalDevices(instance: VkInstance, pPhysicalDeviceCount: [*c]u32, pPhysicalDevices: [*c]VkPhysicalDevice) VkResult;

pub extern fn vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice: VkPhysicalDevice, pQueueFamilyPropertyCount: [*c]u32, pQueueFamilyProperties: [*c]VkQueueFamilyProperties) void;

pub extern fn vkGetPhysicalDeviceMemoryProperties(physicalDevice: VkPhysicalDevice, pMemoryProperties: [*c]VkPhysicalDeviceMemoryProperties) void;

pub extern fn vkGetDeviceProcAddr(device: VkDevice, pName: [*c]const u8) PFN_vkVoidFunction;

pub extern fn vkCreateDevice(physicalDevice: VkPhysicalDevice, pCreateInfo: [*c]const VkDeviceCreateInfo, pAllocator: ?*const VkAllocationCallbacks, pDevice: [*c]VkDevice) VkResult;

pub extern fn vkDestroyDevice(device: VkDevice, pAllocator: ?*const VkAllocationCallbacks) void;

pub extern fn vkEnumerateDeviceExtensionProperties(physicalDevice: VkPhysicalDevice, pLayerName: [*c]const u8, pPropertyCount: [*c]u32, pProperties: [*c]VkExtensionProperties) VkResult;

pub extern fn vkGetDeviceQueue(device: VkDevice, queueFamilyIndex: u32, queueIndex: u32, pQueue: [*c]VkQueue) void;

pub extern fn vkQueueSubmit(queue: VkQueue, submitCount: u32, pSubmits: [*c]const VkSubmitInfo, fence: VkFence) VkResult;

pub extern fn vkDeviceWaitIdle(device: VkDevice) VkResult;

pub extern fn vkAllocateMemory(device: VkDevice, pAllocateInfo: [*c]const VkMemoryAllocateInfo, pAllocator: ?*const VkAllocationCallbacks, pMemory: [*c]VkDeviceMemory) VkResult;

pub extern fn vkFreeMemory(device: VkDevice, memory: VkDeviceMemory, pAllocator: ?*const VkAllocationCallbacks) void;

pub extern fn vkBindImageMemory(device: VkDevice, image: VkImage, memory: VkDeviceMemory, memoryOffset: VkDeviceSize) VkResult;

pub extern fn vkGetImageMemoryRequirements(device: VkDevice, image: VkImage, pMemoryRequirements: [*c]VkMemoryRequirements) void;

pub extern fn vkCreateBuffer(device: VkDevice, pCreateInfo: [*c]const VkBufferCreateInfo, pAllocator: ?*const VkAllocationCallbacks, pBuffer: [*c]VkBuffer) VkResult;
pub extern fn vkDestroyBuffer(device: VkDevice, buffer: VkBuffer, pAllocator: ?*const VkAllocationCallbacks) void;
pub extern fn vkGetBufferMemoryRequirements(device: VkDevice, buffer: VkBuffer, pMemoryRequirements: [*c]VkMemoryRequirements) void;
pub extern fn vkBindBufferMemory(device: VkDevice, buffer: VkBuffer, memory: VkDeviceMemory, memoryOffset: VkDeviceSize) VkResult;
pub extern fn vkMapMemory(device: VkDevice, memory: VkDeviceMemory, offset: VkDeviceSize, size: VkDeviceSize, flags: VkFlags, ppData: [*c]?*u8) VkResult;
pub extern fn vkUnmapMemory(device: VkDevice, memory: VkDeviceMemory) void;

pub extern fn vkCreateSemaphore(device: VkDevice, pCreateInfo: [*c]const VkSemaphoreCreateInfo, pAllocator: ?*const VkAllocationCallbacks, pSemaphore: [*c]VkSemaphore) VkResult;

pub extern fn vkDestroySemaphore(device: VkDevice, semaphore: VkSemaphore, pAllocator: ?*const VkAllocationCallbacks) void;

pub extern fn vkCreateImage(device: VkDevice, pCreateInfo: [*c]const VkImageCreateInfo, pAllocator: ?*const VkAllocationCallbacks, pImage: [*c]VkImage) VkResult;

pub extern fn vkDestroyImage(device: VkDevice, image: VkImage, pAllocator: ?*const VkAllocationCallbacks) void;

pub extern fn vkGetImageSubresourceLayout(device: VkDevice, image: VkImage, pSubresource: [*c]const VkImageSubresource, pLayout: [*c]VkSubresourceLayout) void;

pub extern fn vkCreateCommandPool(device: VkDevice, pCreateInfo: [*c]const VkCommandPoolCreateInfo, pAllocator: ?*const VkAllocationCallbacks, pCommandPool: [*c]VkCommandPool) VkResult;

pub extern fn vkDestroyCommandPool(device: VkDevice, commandPool: VkCommandPool, pAllocator: ?*const VkAllocationCallbacks) void;

pub extern fn vkAllocateCommandBuffers(device: VkDevice, pAllocateInfo: [*c]const VkCommandBufferAllocateInfo, pCommandBuffers: [*c]VkCommandBuffer) VkResult;

pub extern fn vkBeginCommandBuffer(commandBuffer: VkCommandBuffer, pBeginInfo: [*c]const VkCommandBufferBeginInfo) VkResult;

pub extern fn vkEndCommandBuffer(commandBuffer: VkCommandBuffer) VkResult;

pub extern fn vkResetCommandBuffer(commandBuffer: VkCommandBuffer, flags: VkCommandBufferResetFlags) VkResult;

pub extern fn vkCmdPipelineBarrier(commandBuffer: VkCommandBuffer, srcStageMask: VkPipelineStageFlags, dstStageMask: VkPipelineStageFlags, dependencyFlags: VkDependencyFlags, memoryBarrierCount: u32, pMemoryBarriers: [*c]const VkMemoryBarrier, bufferMemoryBarrierCount: u32, pBufferMemoryBarriers: [*c]const VkBufferMemoryBarrier, imageMemoryBarrierCount: u32, pImageMemoryBarriers: [*c]const VkImageMemoryBarrier) void;

pub extern fn vkCmdCopyBuffer(commandBuffer: VkCommandBuffer, srcBuffer: VkBuffer, dstBuffer: VkBuffer, regionCount: u32, pRegions: [*c]const VkBufferCopy) void;
pub extern fn vkCmdCopyBufferToImage(commandBuffer: VkCommandBuffer, srcBuffer: VkBuffer, dstImage: VkImage, dstImageLayout: VkImageLayout, regionCount: u32, pRegions: [*c]const VkBufferImageCopy) void;
pub extern fn vkCreateImageView(device: VkDevice, pCreateInfo: [*c]const VkImageViewCreateInfo, pAllocator: ?*const VkAllocationCallbacks, pView: [*c]VkImageView) VkResult;
pub extern fn vkDestroyImageView(device: VkDevice, imageView: VkImageView, pAllocator: ?*const VkAllocationCallbacks) void;
pub extern fn vkCreateShaderModule(device: VkDevice, pCreateInfo: [*c]const VkShaderModuleCreateInfo, pAllocator: ?*const VkAllocationCallbacks, pShaderModule: [*c]VkShaderModule) VkResult;
pub extern fn vkDestroyShaderModule(device: VkDevice, shaderModule: VkShaderModule, pAllocator: ?*const VkAllocationCallbacks) void;
pub extern fn vkCreatePipelineLayout(device: VkDevice, pCreateInfo: [*c]const VkPipelineLayoutCreateInfo, pAllocator: ?*const VkAllocationCallbacks, pPipelineLayout: [*c]VkPipelineLayout) VkResult;
pub extern fn vkDestroyPipelineLayout(device: VkDevice, pipelineLayout: VkPipelineLayout, pAllocator: ?*const VkAllocationCallbacks) void;
pub extern fn vkCreateGraphicsPipelines(device: VkDevice, pipelineCache: VkPipelineCache, createInfoCount: u32, pCreateInfos: [*c]const VkGraphicsPipelineCreateInfo, pAllocator: ?*const VkAllocationCallbacks, pPipelines: [*c]VkPipeline) VkResult;
pub extern fn vkDestroyPipeline(device: VkDevice, pipeline: VkPipeline, pAllocator: ?*const VkAllocationCallbacks) void;
pub extern fn vkCreateRenderPass(device: VkDevice, pCreateInfo: [*c]const VkRenderPassCreateInfo, pAllocator: ?*const VkAllocationCallbacks, pRenderPass: [*c]VkRenderPass) VkResult;
pub extern fn vkDestroyRenderPass(device: VkDevice, renderPass: VkRenderPass, pAllocator: ?*const VkAllocationCallbacks) void;
pub extern fn vkCreateFramebuffer(device: VkDevice, pCreateInfo: [*c]const VkFramebufferCreateInfo, pAllocator: ?*const VkAllocationCallbacks, pFramebuffer: [*c]VkFramebuffer) VkResult;
pub extern fn vkDestroyFramebuffer(device: VkDevice, framebuffer: VkFramebuffer, pAllocator: ?*const VkAllocationCallbacks) void;
pub extern fn vkCreateSampler(device: VkDevice, pCreateInfo: [*c]const VkSamplerCreateInfo, pAllocator: ?*const VkAllocationCallbacks, pSampler: [*c]VkSampler) VkResult;
pub extern fn vkDestroySampler(device: VkDevice, sampler: VkSampler, pAllocator: ?*const VkAllocationCallbacks) void;
pub extern fn vkCreateDescriptorSetLayout(device: VkDevice, pCreateInfo: [*c]const VkDescriptorSetLayoutCreateInfo, pAllocator: ?*const VkAllocationCallbacks, pSetLayout: [*c]VkDescriptorSetLayout) VkResult;
pub extern fn vkDestroyDescriptorSetLayout(device: VkDevice, descriptorSetLayout: VkDescriptorSetLayout, pAllocator: ?*const VkAllocationCallbacks) void;
pub extern fn vkCreateDescriptorPool(device: VkDevice, pCreateInfo: [*c]const VkDescriptorPoolCreateInfo, pAllocator: ?*const VkAllocationCallbacks, pDescriptorPool: [*c]VkDescriptorPool) VkResult;
pub extern fn vkDestroyDescriptorPool(device: VkDevice, descriptorPool: VkDescriptorPool, pAllocator: ?*const VkAllocationCallbacks) void;
pub extern fn vkAllocateDescriptorSets(device: VkDevice, pAllocateInfo: [*c]const VkDescriptorSetAllocateInfo, pDescriptorSets: [*c]VkDescriptorSet) VkResult;
pub extern fn vkFreeDescriptorSets(device: VkDevice, descriptorPool: VkDescriptorPool, descriptorSetCount: u32, pDescriptorSets: [*c]const VkDescriptorSet) VkResult;
pub extern fn vkUpdateDescriptorSets(device: VkDevice, descriptorWriteCount: u32, pDescriptorWrites: [*c]const VkWriteDescriptorSet, descriptorCopyCount: u32, pDescriptorCopies: ?*const opaque {}) void;
pub extern fn vkCmdBeginRenderPass(commandBuffer: VkCommandBuffer, pRenderPassBegin: [*c]const VkRenderPassBeginInfo, contents: VkSubpassContents) void;
pub extern fn vkCmdEndRenderPass(commandBuffer: VkCommandBuffer) void;
pub extern fn vkCmdBindPipeline(commandBuffer: VkCommandBuffer, pipelineBindPoint: VkPipelineBindPoint, pipeline: VkPipeline) void;
pub extern fn vkCmdBindVertexBuffers(commandBuffer: VkCommandBuffer, firstBinding: u32, bindingCount: u32, pBuffers: [*c]const VkBuffer, pOffsets: [*c]const VkDeviceSize) void;
pub extern fn vkCmdBindIndexBuffer(commandBuffer: VkCommandBuffer, buffer: VkBuffer, offset: VkDeviceSize, indexType: VkIndexType) void;
pub extern fn vkCmdBindDescriptorSets(commandBuffer: VkCommandBuffer, pipelineBindPoint: VkPipelineBindPoint, layout: VkPipelineLayout, firstSet: u32, descriptorSetCount: u32, pDescriptorSets: [*c]const VkDescriptorSet, dynamicOffsetCount: u32, pDynamicOffsets: [*c]const u32) void;
pub extern fn vkCmdDrawIndexed(commandBuffer: VkCommandBuffer, indexCount: u32, instanceCount: u32, firstIndex: u32, vertexOffset: i32, firstInstance: u32) void;
pub extern fn vkCmdDraw(commandBuffer: VkCommandBuffer, vertexCount: u32, instanceCount: u32, firstVertex: u32, firstInstance: u32) void;
pub extern fn vkCmdSetViewport(commandBuffer: VkCommandBuffer, firstViewport: u32, viewportCount: u32, pViewports: [*c]const VkViewport) void;
pub extern fn vkCmdSetScissor(commandBuffer: VkCommandBuffer, firstScissor: u32, scissorCount: u32, pScissors: [*c]const VkRect2D) void;
pub extern fn vkCmdPushConstants(commandBuffer: VkCommandBuffer, layout: VkPipelineLayout, stageFlags: VkShaderStageFlags, offset: u32, size: u32, pValues: ?*const anyopaque) void;

pub const VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT: c_int = 512;

pub const enum_VkExternalMemoryHandleTypeFlagBits = c_uint;

pub const VkExternalMemoryHandleTypeFlagBits = enum_VkExternalMemoryHandleTypeFlagBits;

pub const VkExternalMemoryHandleTypeFlags = VkFlags;

pub const VK_EXTERNAL_MEMORY_FEATURE_DEDICATED_ONLY_BIT: c_int = 1;

pub const VK_EXTERNAL_MEMORY_FEATURE_EXPORTABLE_BIT: c_int = 2;

pub const VkExternalMemoryFeatureFlags = VkFlags;

pub const VkSemaphoreImportFlags = VkFlags;

pub const VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_SYNC_FD_BIT: c_int = 16;

pub const enum_VkExternalSemaphoreHandleTypeFlagBits = c_uint;

pub const VkExternalSemaphoreHandleTypeFlagBits = enum_VkExternalSemaphoreHandleTypeFlagBits;

pub const VkExternalSemaphoreHandleTypeFlags = VkFlags;

pub const struct_VkMemoryDedicatedAllocateInfo = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    image: VkImage = null,
    buffer: VkBuffer = null,
};

pub const VkMemoryDedicatedAllocateInfo = struct_VkMemoryDedicatedAllocateInfo;

pub const struct_VkPhysicalDeviceFeatures2 = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*VkBaseOutStructure = null,
    features: VkPhysicalDeviceFeatures = @import("std").mem.zeroes(VkPhysicalDeviceFeatures),
};

pub const VkPhysicalDeviceFeatures2 = struct_VkPhysicalDeviceFeatures2;

pub const struct_VkPhysicalDeviceProperties2 = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*VkBaseOutStructure = null,
    properties: VkPhysicalDeviceProperties = @import("std").mem.zeroes(VkPhysicalDeviceProperties),
};

pub const VkPhysicalDeviceProperties2 = struct_VkPhysicalDeviceProperties2;

pub const struct_VkFormatProperties2 = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*VkBaseOutStructure = null,
    formatProperties: VkFormatProperties = @import("std").mem.zeroes(VkFormatProperties),
};

pub const VkFormatProperties2 = struct_VkFormatProperties2;

pub const struct_VkImageFormatProperties2 = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*VkBaseOutStructure = null,
    imageFormatProperties: VkImageFormatProperties = @import("std").mem.zeroes(VkImageFormatProperties),
};

pub const VkImageFormatProperties2 = struct_VkImageFormatProperties2;

pub const struct_VkPhysicalDeviceImageFormatInfo2 = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    format: VkFormat = @import("std").mem.zeroes(VkFormat),
    type: VkImageType = @import("std").mem.zeroes(VkImageType),
    tiling: VkImageTiling = @import("std").mem.zeroes(VkImageTiling),
    usage: VkImageUsageFlags = 0,
    flags: VkImageCreateFlags = 0,
};

pub const VkPhysicalDeviceImageFormatInfo2 = struct_VkPhysicalDeviceImageFormatInfo2;

pub const struct_VkExternalMemoryProperties = extern struct {
    externalMemoryFeatures: VkExternalMemoryFeatureFlags = 0,
    exportFromImportedHandleTypes: VkExternalMemoryHandleTypeFlags = 0,
    compatibleHandleTypes: VkExternalMemoryHandleTypeFlags = 0,
};

pub const VkExternalMemoryProperties = struct_VkExternalMemoryProperties;

pub const struct_VkPhysicalDeviceExternalImageFormatInfo = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    handleType: VkExternalMemoryHandleTypeFlagBits = @import("std").mem.zeroes(VkExternalMemoryHandleTypeFlagBits),
};

pub const VkPhysicalDeviceExternalImageFormatInfo = struct_VkPhysicalDeviceExternalImageFormatInfo;

pub const struct_VkExternalImageFormatProperties = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*VkBaseOutStructure = null,
    externalMemoryProperties: VkExternalMemoryProperties = @import("std").mem.zeroes(VkExternalMemoryProperties),
};

pub const VkExternalImageFormatProperties = struct_VkExternalImageFormatProperties;

pub const struct_VkExternalMemoryImageCreateInfo = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    handleTypes: VkExternalMemoryHandleTypeFlags = 0,
};

pub const VkExternalMemoryImageCreateInfo = struct_VkExternalMemoryImageCreateInfo;

pub const struct_VkExportMemoryAllocateInfo = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    handleTypes: VkExternalMemoryHandleTypeFlags = 0,
};

pub const VkExportMemoryAllocateInfo = struct_VkExportMemoryAllocateInfo;

pub const struct_VkExportSemaphoreCreateInfo = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    handleTypes: VkExternalSemaphoreHandleTypeFlags = 0,
};

pub const VkExportSemaphoreCreateInfo = struct_VkExportSemaphoreCreateInfo;

pub extern fn vkGetPhysicalDeviceFeatures2(physicalDevice: VkPhysicalDevice, pFeatures: [*c]VkPhysicalDeviceFeatures2) void;

pub extern fn vkGetPhysicalDeviceProperties2(physicalDevice: VkPhysicalDevice, pProperties: [*c]VkPhysicalDeviceProperties2) void;

pub extern fn vkGetPhysicalDeviceFormatProperties2(physicalDevice: VkPhysicalDevice, format: VkFormat, pFormatProperties: [*c]VkFormatProperties2) void;

pub extern fn vkGetPhysicalDeviceImageFormatProperties2(physicalDevice: VkPhysicalDevice, pImageFormatInfo: [*c]const VkPhysicalDeviceImageFormatInfo2, pImageFormatProperties: [*c]VkImageFormatProperties2) VkResult;

pub const struct_VkPhysicalDeviceTimelineSemaphoreFeatures = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*VkBaseOutStructure = null,
    timelineSemaphore: VkBool32 = 0,
};

pub const VkPhysicalDeviceTimelineSemaphoreFeatures = struct_VkPhysicalDeviceTimelineSemaphoreFeatures;

pub const struct_VkPhysicalDeviceSynchronization2Features = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*VkBaseOutStructure = null,
    synchronization2: VkBool32 = 0,
};

pub const VkPhysicalDeviceSynchronization2Features = struct_VkPhysicalDeviceSynchronization2Features;

pub const struct_VkMemoryGetFdInfoKHR = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    memory: VkDeviceMemory = null,
    handleType: VkExternalMemoryHandleTypeFlagBits = @import("std").mem.zeroes(VkExternalMemoryHandleTypeFlagBits),
};

pub const VkMemoryGetFdInfoKHR = struct_VkMemoryGetFdInfoKHR;

pub const PFN_vkGetMemoryFdKHR = ?*const fn (device: VkDevice, pGetFdInfo: [*c]const VkMemoryGetFdInfoKHR, pFd: [*c]c_int) callconv(.c) VkResult;

pub const struct_VkImportSemaphoreFdInfoKHR = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    semaphore: VkSemaphore = null,
    flags: VkSemaphoreImportFlags = 0,
    handleType: VkExternalSemaphoreHandleTypeFlagBits = @import("std").mem.zeroes(VkExternalSemaphoreHandleTypeFlagBits),
    fd: c_int = 0,
};

pub const VkImportSemaphoreFdInfoKHR = struct_VkImportSemaphoreFdInfoKHR;

pub const struct_VkSemaphoreGetFdInfoKHR = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    semaphore: VkSemaphore = null,
    handleType: VkExternalSemaphoreHandleTypeFlagBits = @import("std").mem.zeroes(VkExternalSemaphoreHandleTypeFlagBits),
};

pub const VkSemaphoreGetFdInfoKHR = struct_VkSemaphoreGetFdInfoKHR;

pub const PFN_vkImportSemaphoreFdKHR = ?*const fn (device: VkDevice, pImportSemaphoreFdInfo: [*c]const VkImportSemaphoreFdInfoKHR) callconv(.c) VkResult;

pub const PFN_vkGetSemaphoreFdKHR = ?*const fn (device: VkDevice, pGetFdInfo: [*c]const VkSemaphoreGetFdInfoKHR, pFd: [*c]c_int) callconv(.c) VkResult;

pub const struct_VkDrmFormatModifierPropertiesEXT = extern struct {
    drmFormatModifier: u64 = 0,
    drmFormatModifierPlaneCount: u32 = 0,
    drmFormatModifierTilingFeatures: VkFormatFeatureFlags = 0,
};

pub const VkDrmFormatModifierPropertiesEXT = struct_VkDrmFormatModifierPropertiesEXT;

pub const struct_VkDrmFormatModifierPropertiesListEXT = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*VkBaseOutStructure = null,
    drmFormatModifierCount: u32 = 0,
    pDrmFormatModifierProperties: [*c]VkDrmFormatModifierPropertiesEXT = null,
};

pub const VkDrmFormatModifierPropertiesListEXT = struct_VkDrmFormatModifierPropertiesListEXT;

pub const struct_VkPhysicalDeviceImageDrmFormatModifierInfoEXT = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    drmFormatModifier: u64 = 0,
    sharingMode: VkSharingMode = @import("std").mem.zeroes(VkSharingMode),
    queueFamilyIndexCount: u32 = 0,
    pQueueFamilyIndices: [*c]const u32 = null,
};

pub const VkPhysicalDeviceImageDrmFormatModifierInfoEXT = struct_VkPhysicalDeviceImageDrmFormatModifierInfoEXT;

pub const struct_VkImageDrmFormatModifierListCreateInfoEXT = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    drmFormatModifierCount: u32 = 0,
    pDrmFormatModifiers: [*c]const u64 = null,
};

pub const VkImageDrmFormatModifierListCreateInfoEXT = struct_VkImageDrmFormatModifierListCreateInfoEXT;

pub const struct_VkImageDrmFormatModifierPropertiesEXT = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*VkBaseOutStructure = null,
    drmFormatModifier: u64 = 0,
};

pub const VkImageDrmFormatModifierPropertiesEXT = struct_VkImageDrmFormatModifierPropertiesEXT;

pub const PFN_vkGetImageDrmFormatModifierPropertiesEXT = ?*const fn (device: VkDevice, image: VkImage, pProperties: [*c]VkImageDrmFormatModifierPropertiesEXT) callconv(.c) VkResult;

pub const struct_VkPhysicalDeviceDrmPropertiesEXT = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*VkBaseOutStructure = null,
    hasPrimary: VkBool32 = 0,
    hasRender: VkBool32 = 0,
    primaryMajor: i64 = 0,
    primaryMinor: i64 = 0,
    renderMajor: i64 = 0,
    renderMinor: i64 = 0,
};

pub const VkPhysicalDeviceDrmPropertiesEXT = struct_VkPhysicalDeviceDrmPropertiesEXT;

pub inline fn VK_MAKE_API_VERSION(variant: u32, major: u32, minor: u32, patch: u32) u32 {
    return (variant << 29) | (major << 22) | (minor << 12) | patch;
}

pub inline fn VK_MAKE_VERSION(major: u32, minor: u32, patch: u32) u32 {
    return (major << 22) | (minor << 12) | patch;
}

pub const VK_QUEUE_FAMILY_IGNORED = ~@as(c_uint, 0);

pub const VK_TRUE = @as(c_uint, 1);

pub const VK_QUEUE_FAMILY_EXTERNAL = ~@as(c_uint, 1);

pub const VK_API_VERSION_1_3 = VK_MAKE_API_VERSION(0, 1, 3, 0);
