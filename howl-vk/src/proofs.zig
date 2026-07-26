//! Package-level ABI, signature, and used-closure proofs.

const std = @import("std");
const vk = @import("howl_vk");

test "consumed ABI sizes, alignments, constants, and signatures" {
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(vk.abi.VkInstance));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(vk.abi.VkInstance));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(vk.abi.VkDevice));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(vk.abi.VkDevice));
    try std.testing.expectEqual(@as(c_int, 0), vk.abi.VK_SUCCESS);
    try std.testing.expectEqual(@as(c_int, 37), vk.abi.VK_FORMAT_R8G8B8A8_UNORM);
    try std.testing.expectEqual(@as(c_int, 1000158000), vk.abi.VK_IMAGE_TILING_DRM_FORMAT_MODIFIER_EXT);
    try std.testing.expectEqual(@as(c_int, 512), vk.abi.VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT);
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(vk.abi.VkExtent2D));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(vk.abi.VkExtent2D));
    const device: vk.dispatch.ExternalImageDispatch = undefined;
    try std.testing.expect(@TypeOf(device.get_memory_fd) == @typeInfo(vk.abi.PFN_vkGetMemoryFdKHR).optional.child);
    try std.testing.expect(@TypeOf(device.get_modifier) == @typeInfo(vk.abi.PFN_vkGetImageDrmFormatModifierPropertiesEXT).optional.child);
    try std.testing.expect(@TypeOf(device.get_semaphore_fd) == @typeInfo(vk.abi.PFN_vkGetSemaphoreFdKHR).optional.child);
    try std.testing.expect(@TypeOf(device.import_semaphore_fd) == @typeInfo(vk.abi.PFN_vkImportSemaphoreFdKHR).optional.child);
}

test "ABI declaration analysis and layout drift receipt" {
    const declarations = @typeInfo(vk.abi).@"struct".decl_names;
    try std.testing.expectEqual(@as(usize, 515), declarations.len);
    var layout_receipt: usize = 0;
    inline for (declarations) |name| {
        const value = @field(vk.abi, name);
        switch (@typeInfo(@TypeOf(value))) {
            .type => switch (@typeInfo(value)) {
                .@"struct", .@"union" => layout_receipt += @sizeOf(value) + @alignOf(value),
                else => {},
            },
            else => {},
        }
    }
    try std.testing.expectEqual(@as(usize, 12964), layout_receipt);
}
