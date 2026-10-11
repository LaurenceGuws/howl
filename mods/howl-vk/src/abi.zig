//! Maintained minimal Vulkan 1.4.357 ABI for external images and semaphores.
//! SPDX-License-Identifier: Apache-2.0 OR MIT
//! Source: KhronosGroup/Vulkan-Headers v1.4.357,
//! commit e3b1eec08173d6b825cd3ac88c885a63b621504a.
//! Input vulkan_core.h SHA-256:
//! a7ac0d7e35e77f642c175af5d36729cfdae2d626d2aaa9145c030a42bd44edc6.
//! Derived from the official C header through pinned Zig translate-C, then
//! reduced to the declarations consumed by renderer.zig.

/// Khronos VkBool32 ABI type.
pub const VkBool32 = u32;

/// Khronos VkDeviceSize ABI type.
pub const VkDeviceSize = u64;

/// Khronos VkFlags ABI type.
pub const VkFlags = u32;

/// Vulkan-owned VkInstance handle tag; its object layout stays outside Howl.
// zig-audit: acknowledge opaque_type
// reason: Khronos defines struct_VkInstance_T as a Vulkan-managed handle tag; Howl neither dereferences nor assumes its object layout.
pub const struct_VkInstance_T = opaque {};

/// Khronos VkInstance ABI type.
pub const VkInstance = ?*struct_VkInstance_T;

/// Vulkan-owned VkPhysicalDevice handle tag; its object layout stays outside Howl.
// zig-audit: acknowledge opaque_type
// reason: Khronos defines struct_VkPhysicalDevice_T as a Vulkan-managed handle tag; Howl neither dereferences nor assumes its object layout.
pub const struct_VkPhysicalDevice_T = opaque {};

/// Khronos VkPhysicalDevice ABI type.
pub const VkPhysicalDevice = ?*struct_VkPhysicalDevice_T;

/// Vulkan-owned VkDevice handle tag; its object layout stays outside Howl.
// zig-audit: acknowledge opaque_type
// reason: Khronos defines struct_VkDevice_T as a Vulkan-managed handle tag; Howl neither dereferences nor assumes its object layout.
pub const struct_VkDevice_T = opaque {};

/// Khronos VkDevice ABI type.
pub const VkDevice = ?*struct_VkDevice_T;

/// Vulkan-owned VkQueue handle tag; its object layout stays outside Howl.
// zig-audit: acknowledge opaque_type
// reason: Khronos defines struct_VkQueue_T as a Vulkan-managed handle tag; Howl neither dereferences nor assumes its object layout.
pub const struct_VkQueue_T = opaque {};

/// Khronos VkQueue ABI type.
pub const VkQueue = ?*struct_VkQueue_T;

/// Vulkan-owned VkSemaphore handle tag; its object layout stays outside Howl.
// zig-audit: acknowledge opaque_type
// reason: Khronos defines struct_VkSemaphore_T as a Vulkan-managed handle tag; Howl neither dereferences nor assumes its object layout.
pub const struct_VkSemaphore_T = opaque {};

/// Khronos VkSemaphore ABI type.
pub const VkSemaphore = ?*struct_VkSemaphore_T;

/// Vulkan-owned VkCommandBuffer handle tag; its object layout stays outside Howl.
// zig-audit: acknowledge opaque_type
// reason: Khronos defines struct_VkCommandBuffer_T as a Vulkan-managed handle tag; Howl neither dereferences nor assumes its object layout.
pub const struct_VkCommandBuffer_T = opaque {};

/// Khronos VkCommandBuffer ABI type.
pub const VkCommandBuffer = ?*struct_VkCommandBuffer_T;

/// Vulkan-owned VkFence handle tag; its object layout stays outside Howl.
// zig-audit: acknowledge opaque_type
// reason: Khronos defines struct_VkFence_T as a Vulkan-managed handle tag; Howl neither dereferences nor assumes its object layout.
pub const struct_VkFence_T = opaque {};

/// Khronos VkFence ABI type.
pub const VkFence = ?*struct_VkFence_T;

/// Vulkan-owned VkDeviceMemory handle tag; its object layout stays outside Howl.
// zig-audit: acknowledge opaque_type
// reason: Khronos defines struct_VkDeviceMemory_T as a Vulkan-managed handle tag; Howl neither dereferences nor assumes its object layout.
pub const struct_VkDeviceMemory_T = opaque {};

/// Khronos VkDeviceMemory ABI type.
pub const VkDeviceMemory = ?*struct_VkDeviceMemory_T;

/// Vulkan-owned VkBuffer handle tag; its object layout stays outside Howl.
// zig-audit: acknowledge opaque_type
// reason: Khronos defines struct_VkBuffer_T as a Vulkan-managed handle tag; Howl neither dereferences nor assumes its object layout.
pub const struct_VkBuffer_T = opaque {};

/// Khronos VkBuffer ABI type.
pub const VkBuffer = ?*struct_VkBuffer_T;

/// Vulkan-owned VkImage handle tag; its object layout stays outside Howl.
// zig-audit: acknowledge opaque_type
// reason: Khronos defines struct_VkImage_T as a Vulkan-managed handle tag; Howl neither dereferences nor assumes its object layout.
pub const struct_VkImage_T = opaque {};

/// Khronos VkImage ABI type.
pub const VkImage = ?*struct_VkImage_T;

/// Vulkan-owned VkCommandPool handle tag; its object layout stays outside Howl.
// zig-audit: acknowledge opaque_type
// reason: Khronos defines struct_VkCommandPool_T as a Vulkan-managed handle tag; Howl neither dereferences nor assumes its object layout.
pub const struct_VkCommandPool_T = opaque {};

/// Khronos VkCommandPool ABI type.
pub const VkCommandPool = ?*struct_VkCommandPool_T;

/// Vulkan-owned VkRenderPass handle tag; its object layout stays outside Howl.
// zig-audit: acknowledge opaque_type
// reason: Khronos defines struct_VkRenderPass_T as a Vulkan-managed handle tag; Howl neither dereferences nor assumes its object layout.
pub const struct_VkRenderPass_T = opaque {};

/// Khronos VkRenderPass ABI type.
pub const VkRenderPass = ?*struct_VkRenderPass_T;

/// Vulkan-owned VkFramebuffer handle tag; its object layout stays outside Howl.
// zig-audit: acknowledge opaque_type
// reason: Khronos defines struct_VkFramebuffer_T as a Vulkan-managed handle tag; Howl neither dereferences nor assumes its object layout.
pub const struct_VkFramebuffer_T = opaque {};

/// Khronos VkFramebuffer ABI type.
pub const VkFramebuffer = ?*struct_VkFramebuffer_T;
/// Vulkan-owned VkImageView handle tag; its object layout stays outside Howl.
// zig-audit: acknowledge opaque_type
// reason: Khronos defines struct_VkImageView_T as a Vulkan-managed handle tag; Howl neither dereferences nor assumes its object layout.
pub const struct_VkImageView_T = opaque {};
/// Khronos VkImageView ABI type.
pub const VkImageView = ?*struct_VkImageView_T;
/// Vulkan-owned VkShaderModule handle tag; its object layout stays outside Howl.
// zig-audit: acknowledge opaque_type
// reason: Khronos defines struct_VkShaderModule_T as a Vulkan-managed handle tag; Howl neither dereferences nor assumes its object layout.
pub const struct_VkShaderModule_T = opaque {};
/// Khronos VkShaderModule ABI type.
pub const VkShaderModule = ?*struct_VkShaderModule_T;
/// Vulkan-owned VkPipeline handle tag; its object layout stays outside Howl.
// zig-audit: acknowledge opaque_type
// reason: Khronos defines struct_VkPipeline_T as a Vulkan-managed handle tag; Howl neither dereferences nor assumes its object layout.
pub const struct_VkPipeline_T = opaque {};
/// Khronos VkPipeline ABI type.
pub const VkPipeline = ?*struct_VkPipeline_T;
/// Vulkan-owned VkPipelineLayout handle tag; its object layout stays outside Howl.
// zig-audit: acknowledge opaque_type
// reason: Khronos defines struct_VkPipelineLayout_T as a Vulkan-managed handle tag; Howl neither dereferences nor assumes its object layout.
pub const struct_VkPipelineLayout_T = opaque {};
/// Khronos VkPipelineLayout ABI type.
pub const VkPipelineLayout = ?*struct_VkPipelineLayout_T;
/// Vulkan-owned VkPipelineCache handle tag; its object layout stays outside Howl.
// zig-audit: acknowledge opaque_type
// reason: Khronos defines struct_VkPipelineCache_T as a Vulkan-managed handle tag; Howl neither dereferences nor assumes its object layout.
pub const struct_VkPipelineCache_T = opaque {};
/// Khronos VkPipelineCache ABI type.
pub const VkPipelineCache = ?*struct_VkPipelineCache_T;
/// Vulkan-owned VkDescriptorSetLayout handle tag; its object layout stays outside Howl.
// zig-audit: acknowledge opaque_type
// reason: Khronos defines struct_VkDescriptorSetLayout_T as a Vulkan-managed handle tag; Howl neither dereferences nor assumes its object layout.
pub const struct_VkDescriptorSetLayout_T = opaque {};
/// Khronos VkDescriptorSetLayout ABI type.
pub const VkDescriptorSetLayout = ?*struct_VkDescriptorSetLayout_T;
/// Vulkan-owned VkSampler handle tag; its object layout stays outside Howl.
// zig-audit: acknowledge opaque_type
// reason: Khronos defines struct_VkSampler_T as a Vulkan-managed handle tag; Howl neither dereferences nor assumes its object layout.
pub const struct_VkSampler_T = opaque {};
/// Khronos VkSampler ABI type.
pub const VkSampler = ?*struct_VkSampler_T;
/// Vulkan-owned VkDescriptorSet handle tag; its object layout stays outside Howl.
// zig-audit: acknowledge opaque_type
// reason: Khronos defines struct_VkDescriptorSet_T as a Vulkan-managed handle tag; Howl neither dereferences nor assumes its object layout.
pub const struct_VkDescriptorSet_T = opaque {};
/// Khronos VkDescriptorSet ABI type.
pub const VkDescriptorSet = ?*struct_VkDescriptorSet_T;
/// Vulkan-owned VkDescriptorPool handle tag; its object layout stays outside Howl.
// zig-audit: acknowledge opaque_type
// reason: Khronos defines struct_VkDescriptorPool_T as a Vulkan-managed handle tag; Howl neither dereferences nor assumes its object layout.
pub const struct_VkDescriptorPool_T = opaque {};
/// Khronos VkDescriptorPool ABI type.
pub const VkDescriptorPool = ?*struct_VkDescriptorPool_T;
/// Vulkan-owned VkBufferView handle tag; its object layout stays outside Howl.
// zig-audit: acknowledge opaque_type
// reason: Khronos defines struct_VkBufferView_T as a Vulkan-managed handle tag; Howl neither dereferences nor assumes its object layout.
pub const struct_VkBufferView_T = opaque {};
/// Khronos VkBufferView ABI type.
pub const VkBufferView = ?*struct_VkBufferView_T;

/// Khronos VK_SUCCESS numeric constant.
pub const VK_SUCCESS: c_int = 0;

/// C integer representation of the Khronos VkResult domain.
pub const enum_VkResult = c_int;

/// Khronos VkResult ABI type.
pub const VkResult = enum_VkResult;

/// Khronos VK_STRUCTURE_TYPE_APPLICATION_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_APPLICATION_INFO: c_int = 0;

/// Khronos VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO: c_int = 1;

/// Khronos VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO: c_int = 2;

/// Khronos VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO: c_int = 3;

/// Khronos VK_STRUCTURE_TYPE_SUBMIT_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_SUBMIT_INFO: c_int = 4;

/// Khronos VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO: c_int = 5;

/// Khronos VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO: c_int = 9;

/// Khronos VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO: c_int = 14;
/// Khronos VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO: c_int = 12;
/// Khronos VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO: c_int = 15;
/// Khronos VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO: c_int = 16;
/// Khronos VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO: c_int = 18;
/// Khronos VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO: c_int = 19;
/// Khronos VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO: c_int = 20;
/// Khronos VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO: c_int = 22;
/// Khronos VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO: c_int = 23;
/// Khronos VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO: c_int = 24;
/// Khronos VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO: c_int = 26;
/// Khronos VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO: c_int = 27;
/// Khronos VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO: c_int = 28;
/// Khronos VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO: c_int = 30;
/// Khronos VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO: c_int = 31;
/// Khronos VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO: c_int = 32;
/// Khronos VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO: c_int = 33;
/// Khronos VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO: c_int = 34;
/// Khronos VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET numeric constant.
pub const VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET: c_int = 35;
/// Khronos VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO: c_int = 37;
/// Khronos VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO: c_int = 38;
/// Khronos VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO: c_int = 43;

/// Khronos VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO: c_int = 39;

/// Khronos VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO: c_int = 40;

/// Khronos VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO: c_int = 42;

/// Khronos VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER numeric constant.
pub const VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER: c_int = 45;
/// Khronos VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER numeric constant.
pub const VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER: c_int = 44;

/// Khronos VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO: c_int = 1000127001;

/// Khronos VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2 numeric constant.
pub const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2: c_int = 1000059000;

/// Khronos VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2 numeric constant.
pub const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2: c_int = 1000059001;

/// Khronos VK_STRUCTURE_TYPE_FORMAT_PROPERTIES_2 numeric constant.
pub const VK_STRUCTURE_TYPE_FORMAT_PROPERTIES_2: c_int = 1000059002;

/// Khronos VK_STRUCTURE_TYPE_IMAGE_FORMAT_PROPERTIES_2 numeric constant.
pub const VK_STRUCTURE_TYPE_IMAGE_FORMAT_PROPERTIES_2: c_int = 1000059003;

/// Khronos VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_FORMAT_INFO_2 numeric constant.
pub const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_FORMAT_INFO_2: c_int = 1000059004;

/// Khronos VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTERNAL_IMAGE_FORMAT_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTERNAL_IMAGE_FORMAT_INFO: c_int = 1000071000;

/// Khronos VK_STRUCTURE_TYPE_EXTERNAL_IMAGE_FORMAT_PROPERTIES numeric constant.
pub const VK_STRUCTURE_TYPE_EXTERNAL_IMAGE_FORMAT_PROPERTIES: c_int = 1000071001;

/// Khronos VK_STRUCTURE_TYPE_EXTERNAL_MEMORY_IMAGE_CREATE_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_EXTERNAL_MEMORY_IMAGE_CREATE_INFO: c_int = 1000072001;

/// Khronos VK_STRUCTURE_TYPE_EXPORT_MEMORY_ALLOCATE_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_EXPORT_MEMORY_ALLOCATE_INFO: c_int = 1000072002;

/// Khronos VK_STRUCTURE_TYPE_EXPORT_SEMAPHORE_CREATE_INFO numeric constant.
pub const VK_STRUCTURE_TYPE_EXPORT_SEMAPHORE_CREATE_INFO: c_int = 1000077000;

/// Khronos VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TIMELINE_SEMAPHORE_FEATURES numeric constant.
pub const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TIMELINE_SEMAPHORE_FEATURES: c_int = 1000207000;

/// Khronos VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES numeric constant.
pub const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES: c_int = 1000314007;

/// Khronos VK_STRUCTURE_TYPE_MEMORY_GET_FD_INFO_KHR numeric constant.
pub const VK_STRUCTURE_TYPE_MEMORY_GET_FD_INFO_KHR: c_int = 1000074002;

/// Khronos VK_STRUCTURE_TYPE_IMPORT_SEMAPHORE_FD_INFO_KHR numeric constant.
pub const VK_STRUCTURE_TYPE_IMPORT_SEMAPHORE_FD_INFO_KHR: c_int = 1000079000;

/// Khronos VK_STRUCTURE_TYPE_SEMAPHORE_GET_FD_INFO_KHR numeric constant.
pub const VK_STRUCTURE_TYPE_SEMAPHORE_GET_FD_INFO_KHR: c_int = 1000079001;

/// Khronos VK_STRUCTURE_TYPE_DRM_FORMAT_MODIFIER_PROPERTIES_LIST_EXT numeric constant.
pub const VK_STRUCTURE_TYPE_DRM_FORMAT_MODIFIER_PROPERTIES_LIST_EXT: c_int = 1000158000;

/// Khronos VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_DRM_FORMAT_MODIFIER_INFO_EXT numeric constant.
pub const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_DRM_FORMAT_MODIFIER_INFO_EXT: c_int = 1000158002;

/// Khronos VK_STRUCTURE_TYPE_IMAGE_DRM_FORMAT_MODIFIER_LIST_CREATE_INFO_EXT numeric constant.
pub const VK_STRUCTURE_TYPE_IMAGE_DRM_FORMAT_MODIFIER_LIST_CREATE_INFO_EXT: c_int = 1000158003;

/// Khronos VK_STRUCTURE_TYPE_IMAGE_DRM_FORMAT_MODIFIER_PROPERTIES_EXT numeric constant.
pub const VK_STRUCTURE_TYPE_IMAGE_DRM_FORMAT_MODIFIER_PROPERTIES_EXT: c_int = 1000158005;

/// Khronos VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRM_PROPERTIES_EXT numeric constant.
pub const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRM_PROPERTIES_EXT: c_int = 1000353000;

/// C integer representation of the Khronos VkStructureType domain.
pub const enum_VkStructureType = c_uint;

/// Khronos VkStructureType ABI type.
pub const VkStructureType = enum_VkStructureType;

/// Khronos VkBaseInStructure ABI type.
pub const VkBaseInStructure = extern struct {
    sType: VkStructureType,
    pNext: ?*const VkBaseInStructure,
};

/// Khronos VkBaseOutStructure ABI type.
pub const VkBaseOutStructure = extern struct {
    sType: VkStructureType,
    pNext: ?*VkBaseOutStructure,
};

/// Khronos VK_FORMAT_R8G8B8A8_UNORM numeric constant.
pub const VK_FORMAT_R8G8B8A8_UNORM: c_int = 37;
/// Khronos VK_FORMAT_R8_UNORM numeric constant.
pub const VK_FORMAT_R8_UNORM: c_int = 9;
/// Khronos VK_FORMAT_R32G32_SFLOAT numeric constant.
pub const VK_FORMAT_R32G32_SFLOAT: c_int = 103;
/// Khronos VK_FORMAT_R32G32B32A32_SFLOAT numeric constant.
pub const VK_FORMAT_R32G32B32A32_SFLOAT: c_int = 109;

/// C integer representation of the Khronos VkFormat domain.
pub const enum_VkFormat = c_uint;

/// Khronos VkFormat ABI type.
pub const VkFormat = enum_VkFormat;

/// Khronos VK_IMAGE_TILING_DRM_FORMAT_MODIFIER_EXT numeric constant.
pub const VK_IMAGE_TILING_DRM_FORMAT_MODIFIER_EXT: c_int = 1000158000;

/// C integer representation of the Khronos VkImageTiling domain.
pub const enum_VkImageTiling = c_uint;

/// Khronos VkImageTiling ABI type.
pub const VkImageTiling = enum_VkImageTiling;

/// Khronos VK_IMAGE_TYPE_2D numeric constant.
pub const VK_IMAGE_TYPE_2D: c_int = 1;

/// C integer representation of the Khronos VkImageType domain.
pub const enum_VkImageType = c_uint;

/// Khronos VkImageType ABI type.
pub const VkImageType = enum_VkImageType;

/// C integer representation of the Khronos VkPhysicalDeviceType domain.
pub const enum_VkPhysicalDeviceType = c_uint;

/// Khronos VkPhysicalDeviceType ABI type.
pub const VkPhysicalDeviceType = enum_VkPhysicalDeviceType;

/// Khronos VK_SHARING_MODE_EXCLUSIVE numeric constant.
pub const VK_SHARING_MODE_EXCLUSIVE: c_int = 0;

/// C integer representation of the Khronos VkSharingMode domain.
pub const enum_VkSharingMode = c_uint;

/// Khronos VkSharingMode ABI type.
pub const VkSharingMode = enum_VkSharingMode;

/// Khronos VK_IMAGE_LAYOUT_UNDEFINED numeric constant.
pub const VK_IMAGE_LAYOUT_UNDEFINED: c_int = 0;

/// Khronos VK_IMAGE_LAYOUT_GENERAL numeric constant.
pub const VK_IMAGE_LAYOUT_GENERAL: c_int = 1;

/// Khronos VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL numeric constant.
pub const VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL: c_int = 7;
/// Khronos VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL numeric constant.
pub const VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL: c_int = 5;
/// Khronos VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL numeric constant.
pub const VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL: c_int = 2;

/// C integer representation of the Khronos VkImageLayout domain.
pub const enum_VkImageLayout = c_uint;

/// Khronos VkImageLayout ABI type.
pub const VkImageLayout = enum_VkImageLayout;

/// Khronos VK_COMMAND_BUFFER_LEVEL_PRIMARY numeric constant.
pub const VK_COMMAND_BUFFER_LEVEL_PRIMARY: c_int = 0;

/// C integer representation of the Khronos VkCommandBufferLevel domain.
pub const enum_VkCommandBufferLevel = c_uint;

/// Khronos VkCommandBufferLevel ABI type.
pub const VkCommandBufferLevel = enum_VkCommandBufferLevel;

/// Khronos VkFormatFeatureFlags ABI type.
pub const VkFormatFeatureFlags = VkFlags;

/// Khronos VkImageCreateFlags ABI type.
pub const VkImageCreateFlags = VkFlags;

/// Khronos VK_SAMPLE_COUNT_1_BIT numeric constant.
pub const VK_SAMPLE_COUNT_1_BIT: c_int = 1;

/// C integer representation of the Khronos VkSampleCountFlagBits domain.
pub const enum_VkSampleCountFlagBits = c_uint;

/// Khronos VkSampleCountFlagBits ABI type.
pub const VkSampleCountFlagBits = enum_VkSampleCountFlagBits;

/// Khronos VkSampleCountFlags ABI type.
pub const VkSampleCountFlags = VkFlags;

/// Khronos VK_IMAGE_USAGE_TRANSFER_DST_BIT numeric constant.
pub const VK_IMAGE_USAGE_TRANSFER_DST_BIT: c_int = 2;
/// Khronos VK_IMAGE_USAGE_SAMPLED_BIT numeric constant.
pub const VK_IMAGE_USAGE_SAMPLED_BIT: c_int = 4;
/// Khronos VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT numeric constant.
pub const VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT: c_int = 16;

/// Khronos VkImageUsageFlags ABI type.
pub const VkImageUsageFlags = VkFlags;

/// Khronos VkInstanceCreateFlags ABI type.
pub const VkInstanceCreateFlags = VkFlags;

/// Khronos VkMemoryHeapFlags ABI type.
pub const VkMemoryHeapFlags = VkFlags;

/// Khronos VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT numeric constant.
pub const VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT: c_int = 1;
/// Khronos VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT numeric constant.
pub const VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT: c_int = 2;
/// Khronos VK_MEMORY_PROPERTY_HOST_COHERENT_BIT numeric constant.
pub const VK_MEMORY_PROPERTY_HOST_COHERENT_BIT: c_int = 4;

/// Khronos VkMemoryPropertyFlags ABI type.
pub const VkMemoryPropertyFlags = VkFlags;

/// Khronos VK_BUFFER_USAGE_TRANSFER_SRC_BIT numeric constant.
pub const VK_BUFFER_USAGE_TRANSFER_SRC_BIT: c_int = 1;
/// Khronos VK_BUFFER_USAGE_TRANSFER_DST_BIT numeric constant.
pub const VK_BUFFER_USAGE_TRANSFER_DST_BIT: c_int = 2;
/// Khronos VK_BUFFER_USAGE_STORAGE_BUFFER_BIT numeric constant.
pub const VK_BUFFER_USAGE_STORAGE_BUFFER_BIT: c_int = 32;
/// Khronos VK_BUFFER_USAGE_INDEX_BUFFER_BIT numeric constant.
pub const VK_BUFFER_USAGE_INDEX_BUFFER_BIT: c_int = 64;
/// Khronos VK_BUFFER_USAGE_VERTEX_BUFFER_BIT numeric constant.
pub const VK_BUFFER_USAGE_VERTEX_BUFFER_BIT: c_int = 128;
/// Khronos VkBufferUsageFlags ABI type.
pub const VkBufferUsageFlags = VkFlags;
/// Khronos VkBufferCreateFlags ABI type.
pub const VkBufferCreateFlags = VkFlags;

/// Khronos VK_QUEUE_GRAPHICS_BIT numeric constant.
pub const VK_QUEUE_GRAPHICS_BIT: c_int = 1;

/// Khronos VkQueueFlags ABI type.
pub const VkQueueFlags = VkFlags;

/// Khronos VkDeviceCreateFlags ABI type.
pub const VkDeviceCreateFlags = VkFlags;

/// Khronos VkDeviceQueueCreateFlags ABI type.
pub const VkDeviceQueueCreateFlags = VkFlags;

/// Khronos VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT numeric constant.
pub const VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT: c_int = 1;

/// Khronos VK_PIPELINE_STAGE_VERTEX_SHADER_BIT numeric constant.
pub const VK_PIPELINE_STAGE_VERTEX_SHADER_BIT: c_int = 8;

/// Khronos VK_PIPELINE_STAGE_TRANSFER_BIT numeric constant.
pub const VK_PIPELINE_STAGE_TRANSFER_BIT: c_int = 4096;

/// Khronos VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT numeric constant.
pub const VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT: c_int = 8192;
/// Khronos VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT numeric constant.
pub const VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT: c_int = 128;
/// Khronos VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT numeric constant.
pub const VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT: c_int = 1024;

/// Khronos VkPipelineStageFlags ABI type.
pub const VkPipelineStageFlags = VkFlags;

/// Khronos VK_IMAGE_ASPECT_COLOR_BIT numeric constant.
pub const VK_IMAGE_ASPECT_COLOR_BIT: c_int = 1;

/// Khronos VK_IMAGE_ASPECT_MEMORY_PLANE_0_BIT_EXT numeric constant.
pub const VK_IMAGE_ASPECT_MEMORY_PLANE_0_BIT_EXT: c_int = 128;

/// Khronos VK_IMAGE_ASPECT_MEMORY_PLANE_1_BIT_EXT numeric constant.
pub const VK_IMAGE_ASPECT_MEMORY_PLANE_1_BIT_EXT: c_int = 256;

/// Khronos VK_IMAGE_ASPECT_MEMORY_PLANE_2_BIT_EXT numeric constant.
pub const VK_IMAGE_ASPECT_MEMORY_PLANE_2_BIT_EXT: c_int = 512;

/// Khronos VK_IMAGE_ASPECT_MEMORY_PLANE_3_BIT_EXT numeric constant.
pub const VK_IMAGE_ASPECT_MEMORY_PLANE_3_BIT_EXT: c_int = 1024;

/// Khronos VkImageAspectFlags ABI type.
pub const VkImageAspectFlags = VkFlags;

/// Khronos VkSemaphoreCreateFlags ABI type.
pub const VkSemaphoreCreateFlags = VkFlags;

/// Khronos VkQueryPipelineStatisticFlags ABI type.
pub const VkQueryPipelineStatisticFlags = VkFlags;

/// Khronos VK_ACCESS_TRANSFER_WRITE_BIT numeric constant.
pub const VK_ACCESS_TRANSFER_WRITE_BIT: c_int = 4096;
/// Khronos VK_ACCESS_SHADER_READ_BIT numeric constant.
pub const VK_ACCESS_SHADER_READ_BIT: c_int = 32;
/// Khronos VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT numeric constant.
pub const VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT: c_int = 256;

/// Khronos VK_IMAGE_VIEW_TYPE_2D numeric constant.
pub const VK_IMAGE_VIEW_TYPE_2D: c_int = 1;
/// Khronos VK_COMPONENT_SWIZZLE_IDENTITY numeric constant.
pub const VK_COMPONENT_SWIZZLE_IDENTITY: c_int = 0;
/// Khronos VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST numeric constant.
pub const VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST: c_int = 3;
/// Khronos VK_POLYGON_MODE_FILL numeric constant.
pub const VK_POLYGON_MODE_FILL: c_int = 0;
/// Khronos VK_CULL_MODE_NONE numeric constant.
pub const VK_CULL_MODE_NONE: c_int = 0;
/// Khronos VK_FRONT_FACE_COUNTER_CLOCKWISE numeric constant.
pub const VK_FRONT_FACE_COUNTER_CLOCKWISE: c_int = 0;
/// Khronos VK_COLOR_COMPONENT_R_BIT numeric constant.
pub const VK_COLOR_COMPONENT_R_BIT: c_int = 1;
/// Khronos VK_COLOR_COMPONENT_G_BIT numeric constant.
pub const VK_COLOR_COMPONENT_G_BIT: c_int = 2;
/// Khronos VK_COLOR_COMPONENT_B_BIT numeric constant.
pub const VK_COLOR_COMPONENT_B_BIT: c_int = 4;
/// Khronos VK_COLOR_COMPONENT_A_BIT numeric constant.
pub const VK_COLOR_COMPONENT_A_BIT: c_int = 8;
/// Khronos VK_SHADER_STAGE_VERTEX_BIT numeric constant.
pub const VK_SHADER_STAGE_VERTEX_BIT: c_int = 1;
/// Khronos VK_SHADER_STAGE_FRAGMENT_BIT numeric constant.
pub const VK_SHADER_STAGE_FRAGMENT_BIT: c_int = 16;
/// Khronos VK_DYNAMIC_STATE_VIEWPORT numeric constant.
pub const VK_DYNAMIC_STATE_VIEWPORT: c_int = 0;
/// Khronos VK_DYNAMIC_STATE_SCISSOR numeric constant.
pub const VK_DYNAMIC_STATE_SCISSOR: c_int = 1;
/// Khronos VK_PIPELINE_BIND_POINT_GRAPHICS numeric constant.
pub const VK_PIPELINE_BIND_POINT_GRAPHICS: c_int = 0;
/// Khronos VK_BLEND_FACTOR_ZERO numeric constant.
pub const VK_BLEND_FACTOR_ZERO: c_int = 0;
/// Khronos VK_BLEND_FACTOR_ONE numeric constant.
pub const VK_BLEND_FACTOR_ONE: c_int = 1;
/// Khronos VK_BLEND_FACTOR_SRC_ALPHA numeric constant.
pub const VK_BLEND_FACTOR_SRC_ALPHA: c_int = 6;
/// Khronos VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA numeric constant.
pub const VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA: c_int = 7;
/// Khronos VK_BLEND_OP_ADD numeric constant.
pub const VK_BLEND_OP_ADD: c_int = 0;
/// Khronos VK_INDEX_TYPE_UINT32 numeric constant.
pub const VK_INDEX_TYPE_UINT32: c_int = 1;
/// Khronos VK_ATTACHMENT_LOAD_OP_CLEAR numeric constant.
pub const VK_ATTACHMENT_LOAD_OP_CLEAR: c_int = 1;
/// Khronos VK_ATTACHMENT_LOAD_OP_DONT_CARE numeric constant.
pub const VK_ATTACHMENT_LOAD_OP_DONT_CARE: c_int = 2;
/// Khronos VK_ATTACHMENT_STORE_OP_STORE numeric constant.
pub const VK_ATTACHMENT_STORE_OP_STORE: c_int = 0;
/// Khronos VK_ATTACHMENT_STORE_OP_DONT_CARE numeric constant.
pub const VK_ATTACHMENT_STORE_OP_DONT_CARE: c_int = 1;
/// Khronos VK_SUBPASS_CONTENTS_INLINE numeric constant.
pub const VK_SUBPASS_CONTENTS_INLINE: c_int = 0;
/// Khronos VK_SUBPASS_EXTERNAL numeric constant.
pub const VK_SUBPASS_EXTERNAL: u32 = ~@as(u32, 0);
/// Khronos VK_FILTER_NEAREST numeric constant.
pub const VK_FILTER_NEAREST: c_int = 0;
/// Khronos VK_FILTER_LINEAR numeric constant.
pub const VK_FILTER_LINEAR: c_int = 1;
/// Khronos VK_SAMPLER_MIPMAP_MODE_NEAREST numeric constant.
pub const VK_SAMPLER_MIPMAP_MODE_NEAREST: c_int = 0;
/// Khronos VK_SAMPLER_MIPMAP_MODE_LINEAR numeric constant.
pub const VK_SAMPLER_MIPMAP_MODE_LINEAR: c_int = 1;
/// Khronos VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE numeric constant.
pub const VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE: c_int = 2;
/// Khronos VK_BORDER_COLOR_FLOAT_TRANSPARENT_BLACK numeric constant.
pub const VK_BORDER_COLOR_FLOAT_TRANSPARENT_BLACK: c_int = 0;
/// Khronos VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER numeric constant.
pub const VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER: c_int = 1;
/// Khronos VK_DESCRIPTOR_TYPE_STORAGE_BUFFER numeric constant.
pub const VK_DESCRIPTOR_TYPE_STORAGE_BUFFER: c_int = 7;

/// Khronos VkAccessFlags ABI type.
pub const VkAccessFlags = VkFlags;

/// Khronos VkDependencyFlags ABI type.
pub const VkDependencyFlags = VkFlags;

/// Khronos VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT numeric constant.
pub const VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT: c_int = 2;

/// Khronos VkCommandPoolCreateFlags ABI type.
pub const VkCommandPoolCreateFlags = VkFlags;

/// Khronos VkQueryControlFlags ABI type.
pub const VkQueryControlFlags = VkFlags;

/// Khronos VkCommandBufferUsageFlags ABI type.
pub const VkCommandBufferUsageFlags = VkFlags;

/// Khronos VkCommandBufferResetFlags ABI type.
pub const VkCommandBufferResetFlags = VkFlags;

/// Khronos VkImageViewCreateFlags ABI type.
pub const VkImageViewCreateFlags = VkFlags;
/// Khronos VkShaderModuleCreateFlags ABI type.
pub const VkShaderModuleCreateFlags = VkFlags;
/// Khronos VkPipelineShaderStageCreateFlags ABI type.
pub const VkPipelineShaderStageCreateFlags = VkFlags;
/// Khronos VkPipelineVertexInputStateCreateFlags ABI type.
pub const VkPipelineVertexInputStateCreateFlags = VkFlags;
/// Khronos VkPipelineInputAssemblyStateCreateFlags ABI type.
pub const VkPipelineInputAssemblyStateCreateFlags = VkFlags;
/// Khronos VkPipelineViewportStateCreateFlags ABI type.
pub const VkPipelineViewportStateCreateFlags = VkFlags;
/// Khronos VkPipelineRasterizationStateCreateFlags ABI type.
pub const VkPipelineRasterizationStateCreateFlags = VkFlags;
/// Khronos VkPipelineMultisampleStateCreateFlags ABI type.
pub const VkPipelineMultisampleStateCreateFlags = VkFlags;
/// Khronos VkPipelineColorBlendStateCreateFlags ABI type.
pub const VkPipelineColorBlendStateCreateFlags = VkFlags;
/// Khronos VkPipelineDynamicStateCreateFlags ABI type.
pub const VkPipelineDynamicStateCreateFlags = VkFlags;
/// Khronos VkPipelineLayoutCreateFlags ABI type.
pub const VkPipelineLayoutCreateFlags = VkFlags;
/// Khronos VkPipelineCreateFlags ABI type.
pub const VkPipelineCreateFlags = VkFlags;
/// Khronos VkAttachmentDescriptionFlags ABI type.
pub const VkAttachmentDescriptionFlags = VkFlags;
/// Khronos VkSubpassDescriptionFlags ABI type.
pub const VkSubpassDescriptionFlags = VkFlags;
/// Khronos VkRenderPassCreateFlags ABI type.
pub const VkRenderPassCreateFlags = VkFlags;
/// Khronos VkFramebufferCreateFlags ABI type.
pub const VkFramebufferCreateFlags = VkFlags;
/// Khronos VkSamplerCreateFlags ABI type.
pub const VkSamplerCreateFlags = VkFlags;
/// Khronos VkDescriptorSetLayoutCreateFlags ABI type.
pub const VkDescriptorSetLayoutCreateFlags = VkFlags;
/// Khronos VkDescriptorPoolCreateFlags ABI type.
pub const VkDescriptorPoolCreateFlags = VkFlags;
/// Khronos VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT numeric constant.
pub const VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT: c_int = 1;
/// Khronos VkCullModeFlags ABI type.
pub const VkCullModeFlags = VkFlags;
/// Khronos VkColorComponentFlags ABI type.
pub const VkColorComponentFlags = VkFlags;
/// Khronos VkShaderStageFlags ABI type.
pub const VkShaderStageFlags = VkFlags;
/// Khronos VkShaderStageFlagBits ABI type.
pub const VkShaderStageFlagBits = c_uint;
/// Khronos VkSampleMask ABI type.
pub const VkSampleMask = u32;
/// Khronos VkImageViewType ABI type.
pub const VkImageViewType = c_uint;
/// Khronos VkComponentSwizzle ABI type.
pub const VkComponentSwizzle = c_uint;
/// Khronos VkVertexInputRate ABI type.
pub const VkVertexInputRate = c_uint;
/// Khronos VkPrimitiveTopology ABI type.
pub const VkPrimitiveTopology = c_uint;
/// Khronos VkPolygonMode ABI type.
pub const VkPolygonMode = c_uint;
/// Khronos VkFrontFace ABI type.
pub const VkFrontFace = c_uint;
/// Khronos VkBlendFactor ABI type.
pub const VkBlendFactor = c_uint;
/// Khronos VkBlendOp ABI type.
pub const VkBlendOp = c_uint;
/// Khronos VkLogicOp ABI type.
pub const VkLogicOp = c_uint;
/// Khronos VkDynamicState ABI type.
pub const VkDynamicState = c_uint;
/// Khronos VkPipelineBindPoint ABI type.
pub const VkPipelineBindPoint = c_uint;
/// Khronos VkAttachmentLoadOp ABI type.
pub const VkAttachmentLoadOp = c_uint;
/// Khronos VkAttachmentStoreOp ABI type.
pub const VkAttachmentStoreOp = c_uint;
/// Khronos VkSubpassContents ABI type.
pub const VkSubpassContents = c_uint;
/// Khronos VkFilter ABI type.
pub const VkFilter = c_uint;
/// Khronos VkSamplerMipmapMode ABI type.
pub const VkSamplerMipmapMode = c_uint;
/// Khronos VkSamplerAddressMode ABI type.
pub const VkSamplerAddressMode = c_uint;
/// Khronos VkCompareOp ABI type.
pub const VkCompareOp = c_uint;
/// Khronos VkBorderColor ABI type.
pub const VkBorderColor = c_uint;
/// Khronos VkDescriptorType ABI type.
pub const VkDescriptorType = c_uint;
/// Khronos VkIndexType ABI type.
pub const VkIndexType = c_uint;

/// Khronos VkExtent3D C structure layout.
pub const struct_VkExtent3D = extern struct {
    width: u32 = 0,
    height: u32 = 0,
    depth: u32 = 0,
};

/// Khronos VkExtent3D ABI type.
pub const VkExtent3D = struct_VkExtent3D;

/// Khronos VkExtent2D ABI type.
pub const VkExtent2D = extern struct { width: u32 = 0, height: u32 = 0 };
/// Khronos VkOffset2D ABI type.
pub const VkOffset2D = extern struct { x: i32 = 0, y: i32 = 0 };
/// Khronos VkRect2D ABI type.
pub const VkRect2D = extern struct { offset: VkOffset2D = .{}, extent: VkExtent2D = .{} };
/// Khronos VkComponentMapping ABI type.
pub const VkComponentMapping = extern struct {
    r: VkComponentSwizzle = VK_COMPONENT_SWIZZLE_IDENTITY,
    g: VkComponentSwizzle = VK_COMPONENT_SWIZZLE_IDENTITY,
    b: VkComponentSwizzle = VK_COMPONENT_SWIZZLE_IDENTITY,
    a: VkComponentSwizzle = VK_COMPONENT_SWIZZLE_IDENTITY,
};
/// Khronos VkClearDepthStencilValue ABI type.
pub const VkClearDepthStencilValue = extern struct { depth: f32, stencil: u32 };
/// Khronos VkClearValue ABI type.
pub const VkClearValue = extern union {
    color: VkClearColorValue,
    depthStencil: VkClearDepthStencilValue,
};

/// Khronos VkImageViewCreateInfo ABI type.
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
/// Khronos VkShaderModuleCreateInfo ABI type.
pub const VkShaderModuleCreateInfo = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
    pNext: ?*const VkBaseInStructure = null,
    flags: VkShaderModuleCreateFlags = 0,
    codeSize: usize = 0,
    pCode: [*c]const u32 = null,
};
/// Khronos VkSpecializationInfo ABI type.
// zig-audit: acknowledge opaque_type
// reason: Khronos defines VkSpecializationInfo as a Vulkan-managed handle tag; Howl neither dereferences nor assumes its object layout.
pub const VkSpecializationInfo = opaque {};
/// Khronos VkPipelineShaderStageCreateInfo ABI type.
pub const VkPipelineShaderStageCreateInfo = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
    pNext: ?*const VkBaseInStructure = null,
    flags: VkPipelineShaderStageCreateFlags = 0,
    stage: VkShaderStageFlagBits = 0,
    module: VkShaderModule = null,
    pName: [*c]const u8 = null,
    pSpecializationInfo: ?*const VkSpecializationInfo = null,
};
/// Khronos VkVertexInputBindingDescription ABI type.
pub const VkVertexInputBindingDescription = extern struct { binding: u32 = 0, stride: u32 = 0, inputRate: VkVertexInputRate = 0 };
/// Khronos VkVertexInputAttributeDescription ABI type.
pub const VkVertexInputAttributeDescription = extern struct { location: u32 = 0, binding: u32 = 0, format: VkFormat = 0, offset: u32 = 0 };
/// Khronos VkPipelineVertexInputStateCreateInfo ABI type.
pub const VkPipelineVertexInputStateCreateInfo = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    pNext: ?*const VkBaseInStructure = null,
    flags: VkPipelineVertexInputStateCreateFlags = 0,
    vertexBindingDescriptionCount: u32 = 0,
    pVertexBindingDescriptions: [*c]const VkVertexInputBindingDescription = null,
    vertexAttributeDescriptionCount: u32 = 0,
    pVertexAttributeDescriptions: [*c]const VkVertexInputAttributeDescription = null,
};
/// Khronos VkPipelineInputAssemblyStateCreateInfo ABI type.
pub const VkPipelineInputAssemblyStateCreateInfo = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
    pNext: ?*const VkBaseInStructure = null,
    flags: VkPipelineInputAssemblyStateCreateFlags = 0,
    topology: VkPrimitiveTopology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
    primitiveRestartEnable: VkBool32 = 0,
};
/// Khronos VkViewport ABI type.
pub const VkViewport = extern struct { x: f32 = 0, y: f32 = 0, width: f32 = 0, height: f32 = 0, minDepth: f32 = 0, maxDepth: f32 = 1 };
/// Khronos VkPipelineViewportStateCreateInfo ABI type.
pub const VkPipelineViewportStateCreateInfo = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
    pNext: ?*const VkBaseInStructure = null,
    flags: VkPipelineViewportStateCreateFlags = 0,
    viewportCount: u32 = 0,
    pViewports: [*c]const VkViewport = null,
    scissorCount: u32 = 0,
    pScissors: [*c]const VkRect2D = null,
};
/// Khronos VkPipelineRasterizationStateCreateInfo ABI type.
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
/// Khronos VkPipelineMultisampleStateCreateInfo ABI type.
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
/// Khronos VkPipelineColorBlendAttachmentState ABI type.
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
/// Khronos VkPipelineColorBlendStateCreateInfo ABI type.
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
/// Khronos VkPipelineDynamicStateCreateInfo ABI type.
pub const VkPipelineDynamicStateCreateInfo = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
    pNext: ?*const VkBaseInStructure = null,
    flags: VkPipelineDynamicStateCreateFlags = 0,
    dynamicStateCount: u32 = 0,
    pDynamicStates: [*c]const VkDynamicState = null,
};
/// Khronos VkPushConstantRange ABI type.
pub const VkPushConstantRange = extern struct { stageFlags: VkShaderStageFlags = 0, offset: u32 = 0, size: u32 = 0 };
/// Khronos VkPipelineLayoutCreateInfo ABI type.
pub const VkPipelineLayoutCreateInfo = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
    pNext: ?*const VkBaseInStructure = null,
    flags: VkPipelineLayoutCreateFlags = 0,
    setLayoutCount: u32 = 0,
    pSetLayouts: [*c]const VkDescriptorSetLayout = null,
    pushConstantRangeCount: u32 = 0,
    pPushConstantRanges: [*c]const VkPushConstantRange = null,
};
/// Khronos VkAttachmentDescription ABI type.
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
/// Khronos VkAttachmentReference ABI type.
pub const VkAttachmentReference = extern struct { attachment: u32 = 0, layout: VkImageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL };
/// Khronos VkSubpassDescription ABI type.
pub const VkSubpassDescription = extern struct {
    flags: VkSubpassDescriptionFlags = 0,
    pipelineBindPoint: VkPipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS,
    inputAttachmentCount: u32 = 0,
    pInputAttachments: [*c]const VkAttachmentReference = null,
    colorAttachmentCount: u32 = 0,
    pColorAttachments: [*c]const VkAttachmentReference = null,
    pResolveAttachments: [*c]const VkAttachmentReference = null,
    // zig-audit: acknowledge opaque_type
    // reason: This unused Vulkan C parameter/field keeps only the borrowed pointer ABI; Howl never dereferences or supplies a concrete object of this omitted layout.
    pDepthStencilAttachment: ?*const opaque {} = null,
    preserveAttachmentCount: u32 = 0,
    pPreserveAttachments: [*c]const u32 = null,
};
/// Khronos VkSubpassDependency ABI type.
pub const VkSubpassDependency = extern struct {
    srcSubpass: u32 = 0,
    dstSubpass: u32 = 0,
    srcStageMask: VkPipelineStageFlags = 0,
    dstStageMask: VkPipelineStageFlags = 0,
    srcAccessMask: VkAccessFlags = 0,
    dstAccessMask: VkAccessFlags = 0,
    dependencyFlags: VkDependencyFlags = 0,
};
/// Khronos VkRenderPassCreateInfo ABI type.
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
/// Khronos VkFramebufferCreateInfo ABI type.
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
/// Khronos VkPipelineTessellationStateCreateInfo ABI type.
// zig-audit: acknowledge opaque_type
// reason: Khronos defines VkPipelineTessellationStateCreateInfo as a Vulkan-managed handle tag; Howl neither dereferences nor assumes its object layout.
pub const VkPipelineTessellationStateCreateInfo = opaque {};
/// Khronos VkPipelineDepthStencilStateCreateInfo ABI type.
// zig-audit: acknowledge opaque_type
// reason: Khronos defines VkPipelineDepthStencilStateCreateInfo as a Vulkan-managed handle tag; Howl neither dereferences nor assumes its object layout.
pub const VkPipelineDepthStencilStateCreateInfo = opaque {};
/// Khronos VkGraphicsPipelineCreateInfo ABI type.
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
/// Khronos VkRenderPassBeginInfo ABI type.
pub const VkRenderPassBeginInfo = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
    pNext: ?*const VkBaseInStructure = null,
    renderPass: VkRenderPass = null,
    framebuffer: VkFramebuffer = null,
    renderArea: VkRect2D = .{},
    clearValueCount: u32 = 0,
    pClearValues: [*c]const VkClearValue = null,
};
/// Khronos VkSamplerCreateInfo ABI type.
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
/// Khronos VkDescriptorSetLayoutBinding ABI type.
pub const VkDescriptorSetLayoutBinding = extern struct {
    binding: u32 = 0,
    descriptorType: VkDescriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
    descriptorCount: u32 = 0,
    stageFlags: VkShaderStageFlags = 0,
    pImmutableSamplers: [*c]const VkSampler = null,
};
/// Khronos VkDescriptorSetLayoutCreateInfo ABI type.
pub const VkDescriptorSetLayoutCreateInfo = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
    pNext: ?*const VkBaseInStructure = null,
    flags: VkDescriptorSetLayoutCreateFlags = 0,
    bindingCount: u32 = 0,
    pBindings: [*c]const VkDescriptorSetLayoutBinding = null,
};
/// Khronos VkDescriptorPoolSize ABI type.
pub const VkDescriptorPoolSize = extern struct { type: VkDescriptorType = 0, descriptorCount: u32 = 0 };
/// Khronos VkDescriptorPoolCreateInfo ABI type.
pub const VkDescriptorPoolCreateInfo = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
    pNext: ?*const VkBaseInStructure = null,
    flags: VkDescriptorPoolCreateFlags = 0,
    maxSets: u32 = 0,
    poolSizeCount: u32 = 0,
    pPoolSizes: [*c]const VkDescriptorPoolSize = null,
};
/// Khronos VkDescriptorSetAllocateInfo ABI type.
pub const VkDescriptorSetAllocateInfo = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
    pNext: ?*const VkBaseInStructure = null,
    descriptorPool: VkDescriptorPool = null,
    descriptorSetCount: u32 = 0,
    pSetLayouts: [*c]const VkDescriptorSetLayout = null,
};
/// Khronos VkDescriptorImageInfo ABI type.
pub const VkDescriptorImageInfo = extern struct {
    sampler: VkSampler = null,
    imageView: VkImageView = null,
    imageLayout: VkImageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
};
/// Khronos VkDescriptorBufferInfo ABI type.
pub const VkDescriptorBufferInfo = extern struct {
    buffer: VkBuffer = null,
    offset: VkDeviceSize = 0,
    range: VkDeviceSize = 0,
};
/// Khronos VkWriteDescriptorSet ABI type.
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

/// C calling convention for the vkVoidFunction Vulkan procedure.
pub const PFN_vkVoidFunction = ?*const fn () callconv(.c) void;

/// Khronos VkAllocationCallbacks ABI type.
// zig-audit: acknowledge opaque_type
// reason: Khronos defines VkAllocationCallbacks as a Vulkan-managed handle tag; Howl neither dereferences nor assumes its object layout.
pub const VkAllocationCallbacks = opaque {};

/// Khronos VkApplicationInfo C structure layout.
pub const struct_VkApplicationInfo = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    pApplicationName: [*c]const u8 = null,
    applicationVersion: u32 = 0,
    pEngineName: [*c]const u8 = null,
    engineVersion: u32 = 0,
    apiVersion: u32 = 0,
};

/// Khronos VkApplicationInfo ABI type.
pub const VkApplicationInfo = struct_VkApplicationInfo;

/// Khronos VkFormatProperties C structure layout.
pub const struct_VkFormatProperties = extern struct {
    linearTilingFeatures: VkFormatFeatureFlags = 0,
    optimalTilingFeatures: VkFormatFeatureFlags = 0,
    bufferFeatures: VkFormatFeatureFlags = 0,
};

/// Khronos VkFormatProperties ABI type.
pub const VkFormatProperties = struct_VkFormatProperties;

/// Khronos VkImageFormatProperties C structure layout.
pub const struct_VkImageFormatProperties = extern struct {
    maxExtent: VkExtent3D = @import("std").mem.zeroes(VkExtent3D),
    maxMipLevels: u32 = 0,
    maxArrayLayers: u32 = 0,
    sampleCounts: VkSampleCountFlags = 0,
    maxResourceSize: VkDeviceSize = 0,
};

/// Khronos VkImageFormatProperties ABI type.
pub const VkImageFormatProperties = struct_VkImageFormatProperties;

/// Khronos VkInstanceCreateInfo C structure layout.
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

/// Khronos VkInstanceCreateInfo ABI type.
pub const VkInstanceCreateInfo = struct_VkInstanceCreateInfo;

/// Khronos VkMemoryHeap C structure layout.
pub const struct_VkMemoryHeap = extern struct {
    size: VkDeviceSize = 0,
    flags: VkMemoryHeapFlags = 0,
};

/// Khronos VkMemoryHeap ABI type.
pub const VkMemoryHeap = struct_VkMemoryHeap;

/// Khronos VkMemoryType C structure layout.
pub const struct_VkMemoryType = extern struct {
    propertyFlags: VkMemoryPropertyFlags = 0,
    heapIndex: u32 = 0,
};

/// Khronos VkMemoryType ABI type.
pub const VkMemoryType = struct_VkMemoryType;

/// Khronos VkPhysicalDeviceFeatures C structure layout.
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

/// Khronos VkPhysicalDeviceFeatures ABI type.
pub const VkPhysicalDeviceFeatures = struct_VkPhysicalDeviceFeatures;

/// Khronos VkPhysicalDeviceLimits C structure layout.
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

/// Khronos VkPhysicalDeviceLimits ABI type.
pub const VkPhysicalDeviceLimits = struct_VkPhysicalDeviceLimits;

/// Khronos VkPhysicalDeviceMemoryProperties C structure layout.
pub const struct_VkPhysicalDeviceMemoryProperties = extern struct {
    memoryTypeCount: u32 = 0,
    memoryTypes: [32]VkMemoryType = @import("std").mem.zeroes([32]VkMemoryType),
    memoryHeapCount: u32 = 0,
    memoryHeaps: [16]VkMemoryHeap = @import("std").mem.zeroes([16]VkMemoryHeap),
};

/// Khronos VkPhysicalDeviceMemoryProperties ABI type.
pub const VkPhysicalDeviceMemoryProperties = struct_VkPhysicalDeviceMemoryProperties;

/// Khronos VkPhysicalDeviceSparseProperties C structure layout.
pub const struct_VkPhysicalDeviceSparseProperties = extern struct {
    residencyStandard2DBlockShape: VkBool32 = 0,
    residencyStandard2DMultisampleBlockShape: VkBool32 = 0,
    residencyStandard3DBlockShape: VkBool32 = 0,
    residencyAlignedMipSize: VkBool32 = 0,
    residencyNonResidentStrict: VkBool32 = 0,
};

/// Khronos VkPhysicalDeviceSparseProperties ABI type.
pub const VkPhysicalDeviceSparseProperties = struct_VkPhysicalDeviceSparseProperties;

/// Khronos VkPhysicalDeviceProperties C structure layout.
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

/// Khronos VkPhysicalDeviceProperties ABI type.
pub const VkPhysicalDeviceProperties = struct_VkPhysicalDeviceProperties;

/// Khronos VkQueueFamilyProperties C structure layout.
pub const struct_VkQueueFamilyProperties = extern struct {
    queueFlags: VkQueueFlags = 0,
    queueCount: u32 = 0,
    timestampValidBits: u32 = 0,
    minImageTransferGranularity: VkExtent3D = @import("std").mem.zeroes(VkExtent3D),
};

/// Khronos VkQueueFamilyProperties ABI type.
pub const VkQueueFamilyProperties = struct_VkQueueFamilyProperties;

/// Khronos VkDeviceQueueCreateInfo C structure layout.
pub const struct_VkDeviceQueueCreateInfo = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    flags: VkDeviceQueueCreateFlags = 0,
    queueFamilyIndex: u32 = 0,
    queueCount: u32 = 0,
    pQueuePriorities: [*c]const f32 = null,
};

/// Khronos VkDeviceQueueCreateInfo ABI type.
pub const VkDeviceQueueCreateInfo = struct_VkDeviceQueueCreateInfo;

/// Khronos VkDeviceCreateInfo C structure layout.
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

/// Khronos VkDeviceCreateInfo ABI type.
pub const VkDeviceCreateInfo = struct_VkDeviceCreateInfo;

/// Khronos VkExtensionProperties C structure layout.
pub const struct_VkExtensionProperties = extern struct {
    extensionName: [256]u8 = @import("std").mem.zeroes([256]u8),
    specVersion: u32 = 0,
};

/// Khronos VkExtensionProperties ABI type.
pub const VkExtensionProperties = struct_VkExtensionProperties;

/// Khronos VkSubmitInfo C structure layout.
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

/// Khronos VkSubmitInfo ABI type.
pub const VkSubmitInfo = struct_VkSubmitInfo;

/// Khronos VkMemoryAllocateInfo C structure layout.
pub const struct_VkMemoryAllocateInfo = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    allocationSize: VkDeviceSize = 0,
    memoryTypeIndex: u32 = 0,
};

/// Khronos VkMemoryAllocateInfo ABI type.
pub const VkMemoryAllocateInfo = struct_VkMemoryAllocateInfo;

/// Khronos VkMemoryRequirements C structure layout.
pub const struct_VkMemoryRequirements = extern struct {
    size: VkDeviceSize = 0,
    alignment: VkDeviceSize = 0,
    memoryTypeBits: u32 = 0,
};

/// Khronos VkMemoryRequirements ABI type.
pub const VkMemoryRequirements = struct_VkMemoryRequirements;

/// Khronos VkBufferCreateInfo C structure layout.
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
/// Khronos VkBufferCreateInfo ABI type.
pub const VkBufferCreateInfo = struct_VkBufferCreateInfo;

/// Khronos VkBufferCopy C structure layout.
pub const struct_VkBufferCopy = extern struct {
    srcOffset: VkDeviceSize = 0,
    dstOffset: VkDeviceSize = 0,
    size: VkDeviceSize = 0,
};
/// Khronos VkBufferCopy ABI type.
pub const VkBufferCopy = struct_VkBufferCopy;

/// Khronos VkBufferImageCopy C structure layout.
pub const struct_VkBufferImageCopy = extern struct {
    bufferOffset: VkDeviceSize = 0,
    bufferRowLength: u32 = 0,
    bufferImageHeight: u32 = 0,
    imageSubresource: VkImageSubresourceLayers = @import("std").mem.zeroes(VkImageSubresourceLayers),
    imageOffset: VkOffset3D = @import("std").mem.zeroes(VkOffset3D),
    imageExtent: VkExtent3D = @import("std").mem.zeroes(VkExtent3D),
};
/// Khronos VkBufferImageCopy ABI type.
pub const VkBufferImageCopy = struct_VkBufferImageCopy;

/// Khronos VkImageSubresource C structure layout.
pub const struct_VkImageSubresource = extern struct {
    aspectMask: VkImageAspectFlags = 0,
    mipLevel: u32 = 0,
    arrayLayer: u32 = 0,
};

/// Khronos VkImageSubresource ABI type.
pub const VkImageSubresource = struct_VkImageSubresource;

/// Khronos VkImageSubresourceLayers C structure layout.
pub const struct_VkImageSubresourceLayers = extern struct {
    aspectMask: VkImageAspectFlags = 0,
    mipLevel: u32 = 0,
    baseArrayLayer: u32 = 0,
    layerCount: u32 = 0,
};
/// Khronos VkImageSubresourceLayers ABI type.
pub const VkImageSubresourceLayers = struct_VkImageSubresourceLayers;

/// Khronos VkOffset3D C structure layout.
pub const struct_VkOffset3D = extern struct { x: i32 = 0, y: i32 = 0, z: i32 = 0 };
/// Khronos VkOffset3D ABI type.
pub const VkOffset3D = struct_VkOffset3D;

/// Khronos VkSemaphoreCreateInfo C structure layout.
pub const struct_VkSemaphoreCreateInfo = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    flags: VkSemaphoreCreateFlags = 0,
};

/// Khronos VkSemaphoreCreateInfo ABI type.
pub const VkSemaphoreCreateInfo = struct_VkSemaphoreCreateInfo;

/// Khronos VkImageCreateInfo C structure layout.
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

/// Khronos VkImageCreateInfo ABI type.
pub const VkImageCreateInfo = struct_VkImageCreateInfo;

/// Khronos VkSubresourceLayout C structure layout.
pub const struct_VkSubresourceLayout = extern struct {
    offset: VkDeviceSize = 0,
    size: VkDeviceSize = 0,
    rowPitch: VkDeviceSize = 0,
    arrayPitch: VkDeviceSize = 0,
    depthPitch: VkDeviceSize = 0,
};

/// Khronos VkSubresourceLayout ABI type.
pub const VkSubresourceLayout = struct_VkSubresourceLayout;

/// Khronos VkImageSubresourceRange C structure layout.
pub const struct_VkImageSubresourceRange = extern struct {
    aspectMask: VkImageAspectFlags = 0,
    baseMipLevel: u32 = 0,
    levelCount: u32 = 0,
    baseArrayLayer: u32 = 0,
    layerCount: u32 = 0,
};

/// Khronos VkImageSubresourceRange ABI type.
pub const VkImageSubresourceRange = struct_VkImageSubresourceRange;

/// Khronos VkCommandPoolCreateInfo C structure layout.
pub const struct_VkCommandPoolCreateInfo = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    flags: VkCommandPoolCreateFlags = 0,
    queueFamilyIndex: u32 = 0,
};

/// Khronos VkCommandPoolCreateInfo ABI type.
pub const VkCommandPoolCreateInfo = struct_VkCommandPoolCreateInfo;

/// Khronos VkCommandBufferAllocateInfo C structure layout.
pub const struct_VkCommandBufferAllocateInfo = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    commandPool: VkCommandPool = null,
    level: VkCommandBufferLevel = @import("std").mem.zeroes(VkCommandBufferLevel),
    commandBufferCount: u32 = 0,
};

/// Khronos VkCommandBufferAllocateInfo ABI type.
pub const VkCommandBufferAllocateInfo = struct_VkCommandBufferAllocateInfo;

/// Khronos VkCommandBufferInheritanceInfo C structure layout.
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

/// Khronos VkCommandBufferInheritanceInfo ABI type.
pub const VkCommandBufferInheritanceInfo = struct_VkCommandBufferInheritanceInfo;

/// Khronos VkCommandBufferBeginInfo C structure layout.
pub const struct_VkCommandBufferBeginInfo = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    flags: VkCommandBufferUsageFlags = 0,
    pInheritanceInfo: [*c]const VkCommandBufferInheritanceInfo = null,
};

/// Khronos VkCommandBufferBeginInfo ABI type.
pub const VkCommandBufferBeginInfo = struct_VkCommandBufferBeginInfo;

/// Khronos VkBufferMemoryBarrier C structure layout.
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

/// Khronos VkBufferMemoryBarrier ABI type.
pub const VkBufferMemoryBarrier = struct_VkBufferMemoryBarrier;

/// Khronos VkImageMemoryBarrier C structure layout.
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

/// Khronos VkImageMemoryBarrier ABI type.
pub const VkImageMemoryBarrier = struct_VkImageMemoryBarrier;

/// Khronos VkMemoryBarrier C structure layout.
pub const struct_VkMemoryBarrier = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    srcAccessMask: VkAccessFlags = 0,
    dstAccessMask: VkAccessFlags = 0,
};

/// Khronos VkMemoryBarrier ABI type.
pub const VkMemoryBarrier = struct_VkMemoryBarrier;

/// Khronos union_VkClearColorValue ABI type.
pub const union_VkClearColorValue = extern union {
    float32: [4]f32,
    int32: [4]i32,
    uint32: [4]u32,
};

/// Khronos VkClearColorValue ABI type.
pub const VkClearColorValue = union_VkClearColorValue;

/// Khronos vkCreateInstance entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkCreateInstance(pCreateInfo: [*c]const VkInstanceCreateInfo, pAllocator: ?*const VkAllocationCallbacks, pInstance: [*c]VkInstance) VkResult;

/// Khronos vkDestroyInstance entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkDestroyInstance(instance: VkInstance, pAllocator: ?*const VkAllocationCallbacks) void;

/// Khronos vkEnumeratePhysicalDevices entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkEnumeratePhysicalDevices(instance: VkInstance, pPhysicalDeviceCount: [*c]u32, pPhysicalDevices: [*c]VkPhysicalDevice) VkResult;

/// Khronos vkGetPhysicalDeviceQueueFamilyProperties entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice: VkPhysicalDevice, pQueueFamilyPropertyCount: [*c]u32, pQueueFamilyProperties: [*c]VkQueueFamilyProperties) void;

/// Khronos vkGetPhysicalDeviceMemoryProperties entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkGetPhysicalDeviceMemoryProperties(physicalDevice: VkPhysicalDevice, pMemoryProperties: [*c]VkPhysicalDeviceMemoryProperties) void;

/// Khronos vkGetDeviceProcAddr entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkGetDeviceProcAddr(device: VkDevice, pName: [*c]const u8) PFN_vkVoidFunction;

/// Khronos vkCreateDevice entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkCreateDevice(physicalDevice: VkPhysicalDevice, pCreateInfo: [*c]const VkDeviceCreateInfo, pAllocator: ?*const VkAllocationCallbacks, pDevice: [*c]VkDevice) VkResult;

/// Khronos vkDestroyDevice entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkDestroyDevice(device: VkDevice, pAllocator: ?*const VkAllocationCallbacks) void;

/// Khronos vkEnumerateDeviceExtensionProperties entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkEnumerateDeviceExtensionProperties(physicalDevice: VkPhysicalDevice, pLayerName: [*c]const u8, pPropertyCount: [*c]u32, pProperties: [*c]VkExtensionProperties) VkResult;

/// Khronos vkGetDeviceQueue entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkGetDeviceQueue(device: VkDevice, queueFamilyIndex: u32, queueIndex: u32, pQueue: [*c]VkQueue) void;

/// Khronos vkQueueSubmit entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkQueueSubmit(queue: VkQueue, submitCount: u32, pSubmits: [*c]const VkSubmitInfo, fence: VkFence) VkResult;

/// Khronos vkDeviceWaitIdle entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkDeviceWaitIdle(device: VkDevice) VkResult;

/// Khronos vkAllocateMemory entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkAllocateMemory(device: VkDevice, pAllocateInfo: [*c]const VkMemoryAllocateInfo, pAllocator: ?*const VkAllocationCallbacks, pMemory: [*c]VkDeviceMemory) VkResult;

/// Khronos vkFreeMemory entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkFreeMemory(device: VkDevice, memory: VkDeviceMemory, pAllocator: ?*const VkAllocationCallbacks) void;

/// Khronos vkBindImageMemory entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkBindImageMemory(device: VkDevice, image: VkImage, memory: VkDeviceMemory, memoryOffset: VkDeviceSize) VkResult;

/// Khronos vkGetImageMemoryRequirements entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkGetImageMemoryRequirements(device: VkDevice, image: VkImage, pMemoryRequirements: [*c]VkMemoryRequirements) void;

/// Khronos vkCreateBuffer entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkCreateBuffer(device: VkDevice, pCreateInfo: [*c]const VkBufferCreateInfo, pAllocator: ?*const VkAllocationCallbacks, pBuffer: [*c]VkBuffer) VkResult;
/// Khronos vkDestroyBuffer entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkDestroyBuffer(device: VkDevice, buffer: VkBuffer, pAllocator: ?*const VkAllocationCallbacks) void;
/// Khronos vkGetBufferMemoryRequirements entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkGetBufferMemoryRequirements(device: VkDevice, buffer: VkBuffer, pMemoryRequirements: [*c]VkMemoryRequirements) void;
/// Khronos vkBindBufferMemory entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkBindBufferMemory(device: VkDevice, buffer: VkBuffer, memory: VkDeviceMemory, memoryOffset: VkDeviceSize) VkResult;
/// Khronos vkMapMemory entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkMapMemory(device: VkDevice, memory: VkDeviceMemory, offset: VkDeviceSize, size: VkDeviceSize, flags: VkFlags, ppData: [*c]?*u8) VkResult;
/// Khronos vkUnmapMemory entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkUnmapMemory(device: VkDevice, memory: VkDeviceMemory) void;

/// Khronos vkCreateSemaphore entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkCreateSemaphore(device: VkDevice, pCreateInfo: [*c]const VkSemaphoreCreateInfo, pAllocator: ?*const VkAllocationCallbacks, pSemaphore: [*c]VkSemaphore) VkResult;

/// Khronos vkDestroySemaphore entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkDestroySemaphore(device: VkDevice, semaphore: VkSemaphore, pAllocator: ?*const VkAllocationCallbacks) void;

/// Khronos vkCreateImage entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkCreateImage(device: VkDevice, pCreateInfo: [*c]const VkImageCreateInfo, pAllocator: ?*const VkAllocationCallbacks, pImage: [*c]VkImage) VkResult;

/// Khronos vkDestroyImage entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkDestroyImage(device: VkDevice, image: VkImage, pAllocator: ?*const VkAllocationCallbacks) void;

/// Khronos vkGetImageSubresourceLayout entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkGetImageSubresourceLayout(device: VkDevice, image: VkImage, pSubresource: [*c]const VkImageSubresource, pLayout: [*c]VkSubresourceLayout) void;

/// Khronos vkCreateCommandPool entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkCreateCommandPool(device: VkDevice, pCreateInfo: [*c]const VkCommandPoolCreateInfo, pAllocator: ?*const VkAllocationCallbacks, pCommandPool: [*c]VkCommandPool) VkResult;

/// Khronos vkDestroyCommandPool entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkDestroyCommandPool(device: VkDevice, commandPool: VkCommandPool, pAllocator: ?*const VkAllocationCallbacks) void;

/// Khronos vkAllocateCommandBuffers entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkAllocateCommandBuffers(device: VkDevice, pAllocateInfo: [*c]const VkCommandBufferAllocateInfo, pCommandBuffers: [*c]VkCommandBuffer) VkResult;

/// Khronos vkBeginCommandBuffer entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkBeginCommandBuffer(commandBuffer: VkCommandBuffer, pBeginInfo: [*c]const VkCommandBufferBeginInfo) VkResult;

/// Khronos vkEndCommandBuffer entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkEndCommandBuffer(commandBuffer: VkCommandBuffer) VkResult;

/// Khronos vkResetCommandBuffer entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkResetCommandBuffer(commandBuffer: VkCommandBuffer, flags: VkCommandBufferResetFlags) VkResult;

/// Khronos vkCmdPipelineBarrier entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkCmdPipelineBarrier(commandBuffer: VkCommandBuffer, srcStageMask: VkPipelineStageFlags, dstStageMask: VkPipelineStageFlags, dependencyFlags: VkDependencyFlags, memoryBarrierCount: u32, pMemoryBarriers: [*c]const VkMemoryBarrier, bufferMemoryBarrierCount: u32, pBufferMemoryBarriers: [*c]const VkBufferMemoryBarrier, imageMemoryBarrierCount: u32, pImageMemoryBarriers: [*c]const VkImageMemoryBarrier) void;

/// Khronos vkCmdCopyBuffer entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkCmdCopyBuffer(commandBuffer: VkCommandBuffer, srcBuffer: VkBuffer, dstBuffer: VkBuffer, regionCount: u32, pRegions: [*c]const VkBufferCopy) void;
/// Khronos vkCmdCopyBufferToImage entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkCmdCopyBufferToImage(commandBuffer: VkCommandBuffer, srcBuffer: VkBuffer, dstImage: VkImage, dstImageLayout: VkImageLayout, regionCount: u32, pRegions: [*c]const VkBufferImageCopy) void;
/// Khronos vkCreateImageView entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkCreateImageView(device: VkDevice, pCreateInfo: [*c]const VkImageViewCreateInfo, pAllocator: ?*const VkAllocationCallbacks, pView: [*c]VkImageView) VkResult;
/// Khronos vkDestroyImageView entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkDestroyImageView(device: VkDevice, imageView: VkImageView, pAllocator: ?*const VkAllocationCallbacks) void;
/// Khronos vkCreateShaderModule entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkCreateShaderModule(device: VkDevice, pCreateInfo: [*c]const VkShaderModuleCreateInfo, pAllocator: ?*const VkAllocationCallbacks, pShaderModule: [*c]VkShaderModule) VkResult;
/// Khronos vkDestroyShaderModule entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkDestroyShaderModule(device: VkDevice, shaderModule: VkShaderModule, pAllocator: ?*const VkAllocationCallbacks) void;
/// Khronos vkCreatePipelineLayout entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkCreatePipelineLayout(device: VkDevice, pCreateInfo: [*c]const VkPipelineLayoutCreateInfo, pAllocator: ?*const VkAllocationCallbacks, pPipelineLayout: [*c]VkPipelineLayout) VkResult;
/// Khronos vkDestroyPipelineLayout entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkDestroyPipelineLayout(device: VkDevice, pipelineLayout: VkPipelineLayout, pAllocator: ?*const VkAllocationCallbacks) void;
/// Khronos vkCreateGraphicsPipelines entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkCreateGraphicsPipelines(device: VkDevice, pipelineCache: VkPipelineCache, createInfoCount: u32, pCreateInfos: [*c]const VkGraphicsPipelineCreateInfo, pAllocator: ?*const VkAllocationCallbacks, pPipelines: [*c]VkPipeline) VkResult;
/// Khronos vkDestroyPipeline entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkDestroyPipeline(device: VkDevice, pipeline: VkPipeline, pAllocator: ?*const VkAllocationCallbacks) void;
/// Khronos vkCreateRenderPass entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkCreateRenderPass(device: VkDevice, pCreateInfo: [*c]const VkRenderPassCreateInfo, pAllocator: ?*const VkAllocationCallbacks, pRenderPass: [*c]VkRenderPass) VkResult;
/// Khronos vkDestroyRenderPass entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkDestroyRenderPass(device: VkDevice, renderPass: VkRenderPass, pAllocator: ?*const VkAllocationCallbacks) void;
/// Khronos vkCreateFramebuffer entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkCreateFramebuffer(device: VkDevice, pCreateInfo: [*c]const VkFramebufferCreateInfo, pAllocator: ?*const VkAllocationCallbacks, pFramebuffer: [*c]VkFramebuffer) VkResult;
/// Khronos vkDestroyFramebuffer entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkDestroyFramebuffer(device: VkDevice, framebuffer: VkFramebuffer, pAllocator: ?*const VkAllocationCallbacks) void;
/// Khronos vkCreateSampler entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkCreateSampler(device: VkDevice, pCreateInfo: [*c]const VkSamplerCreateInfo, pAllocator: ?*const VkAllocationCallbacks, pSampler: [*c]VkSampler) VkResult;
/// Khronos vkDestroySampler entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkDestroySampler(device: VkDevice, sampler: VkSampler, pAllocator: ?*const VkAllocationCallbacks) void;
/// Khronos vkCreateDescriptorSetLayout entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkCreateDescriptorSetLayout(device: VkDevice, pCreateInfo: [*c]const VkDescriptorSetLayoutCreateInfo, pAllocator: ?*const VkAllocationCallbacks, pSetLayout: [*c]VkDescriptorSetLayout) VkResult;
/// Khronos vkDestroyDescriptorSetLayout entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkDestroyDescriptorSetLayout(device: VkDevice, descriptorSetLayout: VkDescriptorSetLayout, pAllocator: ?*const VkAllocationCallbacks) void;
/// Khronos vkCreateDescriptorPool entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkCreateDescriptorPool(device: VkDevice, pCreateInfo: [*c]const VkDescriptorPoolCreateInfo, pAllocator: ?*const VkAllocationCallbacks, pDescriptorPool: [*c]VkDescriptorPool) VkResult;
/// Khronos vkDestroyDescriptorPool entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkDestroyDescriptorPool(device: VkDevice, descriptorPool: VkDescriptorPool, pAllocator: ?*const VkAllocationCallbacks) void;
/// Khronos vkAllocateDescriptorSets entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkAllocateDescriptorSets(device: VkDevice, pAllocateInfo: [*c]const VkDescriptorSetAllocateInfo, pDescriptorSets: [*c]VkDescriptorSet) VkResult;
/// Khronos vkFreeDescriptorSets entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkFreeDescriptorSets(device: VkDevice, descriptorPool: VkDescriptorPool, descriptorSetCount: u32, pDescriptorSets: [*c]const VkDescriptorSet) VkResult;
/// Khronos vkUpdateDescriptorSets entrypoint; callers retain Vulkan object and synchronization ownership.
// zig-audit: acknowledge opaque_type
// reason: This unused Vulkan C parameter/field keeps only the borrowed pointer ABI; Howl never dereferences or supplies a concrete object of this omitted layout.
pub extern fn vkUpdateDescriptorSets(device: VkDevice, descriptorWriteCount: u32, pDescriptorWrites: [*c]const VkWriteDescriptorSet, descriptorCopyCount: u32, pDescriptorCopies: ?*const opaque {}) void;
/// Khronos vkCmdBeginRenderPass entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkCmdBeginRenderPass(commandBuffer: VkCommandBuffer, pRenderPassBegin: [*c]const VkRenderPassBeginInfo, contents: VkSubpassContents) void;
/// Khronos vkCmdEndRenderPass entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkCmdEndRenderPass(commandBuffer: VkCommandBuffer) void;
/// Khronos vkCmdBindPipeline entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkCmdBindPipeline(commandBuffer: VkCommandBuffer, pipelineBindPoint: VkPipelineBindPoint, pipeline: VkPipeline) void;
/// Khronos vkCmdBindVertexBuffers entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkCmdBindVertexBuffers(commandBuffer: VkCommandBuffer, firstBinding: u32, bindingCount: u32, pBuffers: [*c]const VkBuffer, pOffsets: [*c]const VkDeviceSize) void;
/// Khronos vkCmdBindIndexBuffer entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkCmdBindIndexBuffer(commandBuffer: VkCommandBuffer, buffer: VkBuffer, offset: VkDeviceSize, indexType: VkIndexType) void;
/// Khronos vkCmdBindDescriptorSets entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkCmdBindDescriptorSets(commandBuffer: VkCommandBuffer, pipelineBindPoint: VkPipelineBindPoint, layout: VkPipelineLayout, firstSet: u32, descriptorSetCount: u32, pDescriptorSets: [*c]const VkDescriptorSet, dynamicOffsetCount: u32, pDynamicOffsets: [*c]const u32) void;
/// Khronos vkCmdDrawIndexed entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkCmdDrawIndexed(commandBuffer: VkCommandBuffer, indexCount: u32, instanceCount: u32, firstIndex: u32, vertexOffset: i32, firstInstance: u32) void;
/// Khronos vkCmdDraw entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkCmdDraw(commandBuffer: VkCommandBuffer, vertexCount: u32, instanceCount: u32, firstVertex: u32, firstInstance: u32) void;
/// Khronos vkCmdSetViewport entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkCmdSetViewport(commandBuffer: VkCommandBuffer, firstViewport: u32, viewportCount: u32, pViewports: [*c]const VkViewport) void;
/// Khronos vkCmdSetScissor entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkCmdSetScissor(commandBuffer: VkCommandBuffer, firstScissor: u32, scissorCount: u32, pScissors: [*c]const VkRect2D) void;
/// Khronos vkCmdPushConstants entrypoint; callers retain Vulkan object and synchronization ownership.
// zig-audit: acknowledge anyopaque
// reason: vkCmdPushConstants borrows exactly size bytes through the Vulkan C ABI's untyped const buffer; the caller owns its lifetime and pipeline layout.
pub extern fn vkCmdPushConstants(commandBuffer: VkCommandBuffer, layout: VkPipelineLayout, stageFlags: VkShaderStageFlags, offset: u32, size: u32, pValues: ?*const anyopaque) void;

/// Khronos VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT numeric constant.
pub const VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT: c_int = 512;

/// C integer representation of the Khronos VkExternalMemoryHandleTypeFlagBits domain.
pub const enum_VkExternalMemoryHandleTypeFlagBits = c_uint;

/// Khronos VkExternalMemoryHandleTypeFlagBits ABI type.
pub const VkExternalMemoryHandleTypeFlagBits = enum_VkExternalMemoryHandleTypeFlagBits;

/// Khronos VkExternalMemoryHandleTypeFlags ABI type.
pub const VkExternalMemoryHandleTypeFlags = VkFlags;

/// Khronos VK_EXTERNAL_MEMORY_FEATURE_DEDICATED_ONLY_BIT numeric constant.
pub const VK_EXTERNAL_MEMORY_FEATURE_DEDICATED_ONLY_BIT: c_int = 1;

/// Khronos VK_EXTERNAL_MEMORY_FEATURE_EXPORTABLE_BIT numeric constant.
pub const VK_EXTERNAL_MEMORY_FEATURE_EXPORTABLE_BIT: c_int = 2;

/// Khronos VkExternalMemoryFeatureFlags ABI type.
pub const VkExternalMemoryFeatureFlags = VkFlags;

/// Khronos VkSemaphoreImportFlags ABI type.
pub const VkSemaphoreImportFlags = VkFlags;

/// Khronos VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_SYNC_FD_BIT numeric constant.
pub const VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_SYNC_FD_BIT: c_int = 16;

/// C integer representation of the Khronos VkExternalSemaphoreHandleTypeFlagBits domain.
pub const enum_VkExternalSemaphoreHandleTypeFlagBits = c_uint;

/// Khronos VkExternalSemaphoreHandleTypeFlagBits ABI type.
pub const VkExternalSemaphoreHandleTypeFlagBits = enum_VkExternalSemaphoreHandleTypeFlagBits;

/// Khronos VkExternalSemaphoreHandleTypeFlags ABI type.
pub const VkExternalSemaphoreHandleTypeFlags = VkFlags;

/// Khronos VkMemoryDedicatedAllocateInfo C structure layout.
pub const struct_VkMemoryDedicatedAllocateInfo = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    image: VkImage = null,
    buffer: VkBuffer = null,
};

/// Khronos VkMemoryDedicatedAllocateInfo ABI type.
pub const VkMemoryDedicatedAllocateInfo = struct_VkMemoryDedicatedAllocateInfo;

/// Khronos VkPhysicalDeviceFeatures2 C structure layout.
pub const struct_VkPhysicalDeviceFeatures2 = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*VkBaseOutStructure = null,
    features: VkPhysicalDeviceFeatures = @import("std").mem.zeroes(VkPhysicalDeviceFeatures),
};

/// Khronos VkPhysicalDeviceFeatures2 ABI type.
pub const VkPhysicalDeviceFeatures2 = struct_VkPhysicalDeviceFeatures2;

/// Khronos VkPhysicalDeviceProperties2 C structure layout.
pub const struct_VkPhysicalDeviceProperties2 = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*VkBaseOutStructure = null,
    properties: VkPhysicalDeviceProperties = @import("std").mem.zeroes(VkPhysicalDeviceProperties),
};

/// Khronos VkPhysicalDeviceProperties2 ABI type.
pub const VkPhysicalDeviceProperties2 = struct_VkPhysicalDeviceProperties2;

/// Khronos VkFormatProperties2 C structure layout.
pub const struct_VkFormatProperties2 = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*VkBaseOutStructure = null,
    formatProperties: VkFormatProperties = @import("std").mem.zeroes(VkFormatProperties),
};

/// Khronos VkFormatProperties2 ABI type.
pub const VkFormatProperties2 = struct_VkFormatProperties2;

/// Khronos VkImageFormatProperties2 C structure layout.
pub const struct_VkImageFormatProperties2 = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*VkBaseOutStructure = null,
    imageFormatProperties: VkImageFormatProperties = @import("std").mem.zeroes(VkImageFormatProperties),
};

/// Khronos VkImageFormatProperties2 ABI type.
pub const VkImageFormatProperties2 = struct_VkImageFormatProperties2;

/// Khronos VkPhysicalDeviceImageFormatInfo2 C structure layout.
pub const struct_VkPhysicalDeviceImageFormatInfo2 = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    format: VkFormat = @import("std").mem.zeroes(VkFormat),
    type: VkImageType = @import("std").mem.zeroes(VkImageType),
    tiling: VkImageTiling = @import("std").mem.zeroes(VkImageTiling),
    usage: VkImageUsageFlags = 0,
    flags: VkImageCreateFlags = 0,
};

/// Khronos VkPhysicalDeviceImageFormatInfo2 ABI type.
pub const VkPhysicalDeviceImageFormatInfo2 = struct_VkPhysicalDeviceImageFormatInfo2;

/// Khronos VkExternalMemoryProperties C structure layout.
pub const struct_VkExternalMemoryProperties = extern struct {
    externalMemoryFeatures: VkExternalMemoryFeatureFlags = 0,
    exportFromImportedHandleTypes: VkExternalMemoryHandleTypeFlags = 0,
    compatibleHandleTypes: VkExternalMemoryHandleTypeFlags = 0,
};

/// Khronos VkExternalMemoryProperties ABI type.
pub const VkExternalMemoryProperties = struct_VkExternalMemoryProperties;

/// Khronos VkPhysicalDeviceExternalImageFormatInfo C structure layout.
pub const struct_VkPhysicalDeviceExternalImageFormatInfo = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    handleType: VkExternalMemoryHandleTypeFlagBits = @import("std").mem.zeroes(VkExternalMemoryHandleTypeFlagBits),
};

/// Khronos VkPhysicalDeviceExternalImageFormatInfo ABI type.
pub const VkPhysicalDeviceExternalImageFormatInfo = struct_VkPhysicalDeviceExternalImageFormatInfo;

/// Khronos VkExternalImageFormatProperties C structure layout.
pub const struct_VkExternalImageFormatProperties = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*VkBaseOutStructure = null,
    externalMemoryProperties: VkExternalMemoryProperties = @import("std").mem.zeroes(VkExternalMemoryProperties),
};

/// Khronos VkExternalImageFormatProperties ABI type.
pub const VkExternalImageFormatProperties = struct_VkExternalImageFormatProperties;

/// Khronos VkExternalMemoryImageCreateInfo C structure layout.
pub const struct_VkExternalMemoryImageCreateInfo = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    handleTypes: VkExternalMemoryHandleTypeFlags = 0,
};

/// Khronos VkExternalMemoryImageCreateInfo ABI type.
pub const VkExternalMemoryImageCreateInfo = struct_VkExternalMemoryImageCreateInfo;

/// Khronos VkExportMemoryAllocateInfo C structure layout.
pub const struct_VkExportMemoryAllocateInfo = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    handleTypes: VkExternalMemoryHandleTypeFlags = 0,
};

/// Khronos VkExportMemoryAllocateInfo ABI type.
pub const VkExportMemoryAllocateInfo = struct_VkExportMemoryAllocateInfo;

/// Khronos VkExportSemaphoreCreateInfo C structure layout.
pub const struct_VkExportSemaphoreCreateInfo = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    handleTypes: VkExternalSemaphoreHandleTypeFlags = 0,
};

/// Khronos VkExportSemaphoreCreateInfo ABI type.
pub const VkExportSemaphoreCreateInfo = struct_VkExportSemaphoreCreateInfo;

/// Khronos vkGetPhysicalDeviceFeatures2 entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkGetPhysicalDeviceFeatures2(physicalDevice: VkPhysicalDevice, pFeatures: [*c]VkPhysicalDeviceFeatures2) void;

/// Khronos vkGetPhysicalDeviceProperties2 entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkGetPhysicalDeviceProperties2(physicalDevice: VkPhysicalDevice, pProperties: [*c]VkPhysicalDeviceProperties2) void;

/// Khronos vkGetPhysicalDeviceFormatProperties2 entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkGetPhysicalDeviceFormatProperties2(physicalDevice: VkPhysicalDevice, format: VkFormat, pFormatProperties: [*c]VkFormatProperties2) void;

/// Khronos vkGetPhysicalDeviceImageFormatProperties2 entrypoint; callers retain Vulkan object and synchronization ownership.
pub extern fn vkGetPhysicalDeviceImageFormatProperties2(physicalDevice: VkPhysicalDevice, pImageFormatInfo: [*c]const VkPhysicalDeviceImageFormatInfo2, pImageFormatProperties: [*c]VkImageFormatProperties2) VkResult;

/// Khronos VkPhysicalDeviceTimelineSemaphoreFeatures C structure layout.
pub const struct_VkPhysicalDeviceTimelineSemaphoreFeatures = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*VkBaseOutStructure = null,
    timelineSemaphore: VkBool32 = 0,
};

/// Khronos VkPhysicalDeviceTimelineSemaphoreFeatures ABI type.
pub const VkPhysicalDeviceTimelineSemaphoreFeatures = struct_VkPhysicalDeviceTimelineSemaphoreFeatures;

/// Khronos VkPhysicalDeviceSynchronization2Features C structure layout.
pub const struct_VkPhysicalDeviceSynchronization2Features = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*VkBaseOutStructure = null,
    synchronization2: VkBool32 = 0,
};

/// Khronos VkPhysicalDeviceSynchronization2Features ABI type.
pub const VkPhysicalDeviceSynchronization2Features = struct_VkPhysicalDeviceSynchronization2Features;

/// Khronos VkMemoryGetFdInfoKHR C structure layout.
pub const struct_VkMemoryGetFdInfoKHR = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    memory: VkDeviceMemory = null,
    handleType: VkExternalMemoryHandleTypeFlagBits = @import("std").mem.zeroes(VkExternalMemoryHandleTypeFlagBits),
};

/// Khronos VkMemoryGetFdInfoKHR ABI type.
pub const VkMemoryGetFdInfoKHR = struct_VkMemoryGetFdInfoKHR;

/// C calling convention for the vkGetMemoryFdKHR Vulkan procedure.
pub const PFN_vkGetMemoryFdKHR = ?*const fn (device: VkDevice, pGetFdInfo: [*c]const VkMemoryGetFdInfoKHR, pFd: [*c]c_int) callconv(.c) VkResult;

/// Khronos VkImportSemaphoreFdInfoKHR C structure layout.
pub const struct_VkImportSemaphoreFdInfoKHR = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    semaphore: VkSemaphore = null,
    flags: VkSemaphoreImportFlags = 0,
    handleType: VkExternalSemaphoreHandleTypeFlagBits = @import("std").mem.zeroes(VkExternalSemaphoreHandleTypeFlagBits),
    fd: c_int = 0,
};

/// Khronos VkImportSemaphoreFdInfoKHR ABI type.
pub const VkImportSemaphoreFdInfoKHR = struct_VkImportSemaphoreFdInfoKHR;

/// Khronos VkSemaphoreGetFdInfoKHR C structure layout.
pub const struct_VkSemaphoreGetFdInfoKHR = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    semaphore: VkSemaphore = null,
    handleType: VkExternalSemaphoreHandleTypeFlagBits = @import("std").mem.zeroes(VkExternalSemaphoreHandleTypeFlagBits),
};

/// Khronos VkSemaphoreGetFdInfoKHR ABI type.
pub const VkSemaphoreGetFdInfoKHR = struct_VkSemaphoreGetFdInfoKHR;

/// C calling convention for the vkImportSemaphoreFdKHR Vulkan procedure.
pub const PFN_vkImportSemaphoreFdKHR = ?*const fn (device: VkDevice, pImportSemaphoreFdInfo: [*c]const VkImportSemaphoreFdInfoKHR) callconv(.c) VkResult;

/// C calling convention for the vkGetSemaphoreFdKHR Vulkan procedure.
pub const PFN_vkGetSemaphoreFdKHR = ?*const fn (device: VkDevice, pGetFdInfo: [*c]const VkSemaphoreGetFdInfoKHR, pFd: [*c]c_int) callconv(.c) VkResult;

/// Khronos VkDrmFormatModifierPropertiesEXT C structure layout.
pub const struct_VkDrmFormatModifierPropertiesEXT = extern struct {
    drmFormatModifier: u64 = 0,
    drmFormatModifierPlaneCount: u32 = 0,
    drmFormatModifierTilingFeatures: VkFormatFeatureFlags = 0,
};

/// Khronos VkDrmFormatModifierPropertiesEXT ABI type.
pub const VkDrmFormatModifierPropertiesEXT = struct_VkDrmFormatModifierPropertiesEXT;

/// Khronos VkDrmFormatModifierPropertiesListEXT C structure layout.
pub const struct_VkDrmFormatModifierPropertiesListEXT = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*VkBaseOutStructure = null,
    drmFormatModifierCount: u32 = 0,
    pDrmFormatModifierProperties: [*c]VkDrmFormatModifierPropertiesEXT = null,
};

/// Khronos VkDrmFormatModifierPropertiesListEXT ABI type.
pub const VkDrmFormatModifierPropertiesListEXT = struct_VkDrmFormatModifierPropertiesListEXT;

/// Khronos VkPhysicalDeviceImageDrmFormatModifierInfoEXT C structure layout.
pub const struct_VkPhysicalDeviceImageDrmFormatModifierInfoEXT = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    drmFormatModifier: u64 = 0,
    sharingMode: VkSharingMode = @import("std").mem.zeroes(VkSharingMode),
    queueFamilyIndexCount: u32 = 0,
    pQueueFamilyIndices: [*c]const u32 = null,
};

/// Khronos VkPhysicalDeviceImageDrmFormatModifierInfoEXT ABI type.
pub const VkPhysicalDeviceImageDrmFormatModifierInfoEXT = struct_VkPhysicalDeviceImageDrmFormatModifierInfoEXT;

/// Khronos VkImageDrmFormatModifierListCreateInfoEXT C structure layout.
pub const struct_VkImageDrmFormatModifierListCreateInfoEXT = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*const VkBaseInStructure = null,
    drmFormatModifierCount: u32 = 0,
    pDrmFormatModifiers: [*c]const u64 = null,
};

/// Khronos VkImageDrmFormatModifierListCreateInfoEXT ABI type.
pub const VkImageDrmFormatModifierListCreateInfoEXT = struct_VkImageDrmFormatModifierListCreateInfoEXT;

/// Khronos VkImageDrmFormatModifierPropertiesEXT C structure layout.
pub const struct_VkImageDrmFormatModifierPropertiesEXT = extern struct {
    sType: VkStructureType = @import("std").mem.zeroes(VkStructureType),
    pNext: ?*VkBaseOutStructure = null,
    drmFormatModifier: u64 = 0,
};

/// Khronos VkImageDrmFormatModifierPropertiesEXT ABI type.
pub const VkImageDrmFormatModifierPropertiesEXT = struct_VkImageDrmFormatModifierPropertiesEXT;

/// C calling convention for the vkGetImageDrmFormatModifierPropertiesEXT Vulkan procedure.
pub const PFN_vkGetImageDrmFormatModifierPropertiesEXT = ?*const fn (device: VkDevice, image: VkImage, pProperties: [*c]VkImageDrmFormatModifierPropertiesEXT) callconv(.c) VkResult;

/// Khronos VkPhysicalDeviceDrmPropertiesEXT C structure layout.
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

/// Khronos VkPhysicalDeviceDrmPropertiesEXT ABI type.
pub const VkPhysicalDeviceDrmPropertiesEXT = struct_VkPhysicalDeviceDrmPropertiesEXT;

/// Packs Vulkan API version components in the Khronos VK_MAKE_API_VERSION bit layout.
pub inline fn VK_MAKE_API_VERSION(variant: u32, major: u32, minor: u32, patch: u32) u32 {
    return (variant << 29) | (major << 22) | (minor << 12) | patch;
}

/// Packs Vulkan API version components in the Khronos VK_MAKE_VERSION bit layout.
pub inline fn VK_MAKE_VERSION(major: u32, minor: u32, patch: u32) u32 {
    return (major << 22) | (minor << 12) | patch;
}

/// Khronos VK_QUEUE_FAMILY_IGNORED numeric constant.
pub const VK_QUEUE_FAMILY_IGNORED = ~@as(c_uint, 0);

/// Khronos VK_TRUE numeric constant.
pub const VK_TRUE = @as(c_uint, 1);

/// Khronos VK_QUEUE_FAMILY_EXTERNAL numeric constant.
pub const VK_QUEUE_FAMILY_EXTERNAL = ~@as(c_uint, 1);

/// Khronos VK_API_VERSION_1_3 numeric constant.
pub const VK_API_VERSION_1_3 = VK_MAKE_API_VERSION(0, 1, 3, 0);
