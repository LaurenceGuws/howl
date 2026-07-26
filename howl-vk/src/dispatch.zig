//! Maintained loader for external image, modifier, and semaphore procedures.

const abi = @import("abi.zig");

/// Names the only loader failure that crosses this package boundary.
pub const Error = error{
    MissingMemoryFd,
    MissingModifier,
    MissingSemaphoreFd,
    MissingImportSemaphoreFd,
};

const GetMemoryFd = @typeInfo(abi.PFN_vkGetMemoryFdKHR).optional.child;
const GetModifier = @typeInfo(abi.PFN_vkGetImageDrmFormatModifierPropertiesEXT).optional.child;
const GetSemaphoreFd = @typeInfo(abi.PFN_vkGetSemaphoreFdKHR).optional.child;
const ImportSemaphoreFd = @typeInfo(abi.PFN_vkImportSemaphoreFdKHR).optional.child;

/// Contains validated, non-null extension procedures. The caller owns the
/// device and must keep it alive while these pointers are used.
pub const ExternalImageDispatch = struct {
    get_memory_fd: GetMemoryFd,
    get_modifier: GetModifier,
    get_semaphore_fd: GetSemaphoreFd,
    import_semaphore_fd: ImportSemaphoreFd,
};

const Raw = struct {
    get_memory_fd: abi.PFN_vkGetMemoryFdKHR,
    get_modifier: abi.PFN_vkGetImageDrmFormatModifierPropertiesEXT,
    get_semaphore_fd: abi.PFN_vkGetSemaphoreFdKHR,
    import_semaphore_fd: abi.PFN_vkImportSemaphoreFdKHR,
};

fn validate(raw: Raw) Error!ExternalImageDispatch {
    return .{
        .get_memory_fd = raw.get_memory_fd orelse return error.MissingMemoryFd,
        .get_modifier = raw.get_modifier orelse return error.MissingModifier,
        .get_semaphore_fd = raw.get_semaphore_fd orelse return error.MissingSemaphoreFd,
        .import_semaphore_fd = raw.import_semaphore_fd orelse return error.MissingImportSemaphoreFd,
    };
}

/// Loads the exact extension procedures used by external image presentation without
/// allocation or global mutable state.
pub fn load(device: abi.VkDevice) Error!ExternalImageDispatch {
    return validate(.{
        .get_memory_fd = @ptrCast(abi.vkGetDeviceProcAddr(device, "vkGetMemoryFdKHR")),
        .get_modifier = @ptrCast(abi.vkGetDeviceProcAddr(device, "vkGetImageDrmFormatModifierPropertiesEXT")),
        .get_semaphore_fd = @ptrCast(abi.vkGetDeviceProcAddr(device, "vkGetSemaphoreFdKHR")),
        .import_semaphore_fd = @ptrCast(abi.vkGetDeviceProcAddr(device, "vkImportSemaphoreFdKHR")),
    });
}

fn dummyMemoryFd(_: abi.VkDevice, _: [*c]const abi.VkMemoryGetFdInfoKHR, _: [*c]c_int) callconv(.c) abi.VkResult {
    return abi.VK_SUCCESS;
}
fn dummyModifier(_: abi.VkDevice, _: abi.VkImage, _: [*c]abi.VkImageDrmFormatModifierPropertiesEXT) callconv(.c) abi.VkResult {
    return abi.VK_SUCCESS;
}
fn dummySemaphoreFd(_: abi.VkDevice, _: [*c]const abi.VkSemaphoreGetFdInfoKHR, _: [*c]c_int) callconv(.c) abi.VkResult {
    return abi.VK_SUCCESS;
}
fn dummyImport(_: abi.VkDevice, _: [*c]const abi.VkImportSemaphoreFdInfoKHR) callconv(.c) abi.VkResult {
    return abi.VK_SUCCESS;
}

test "dispatch success stores non-null typed procedures" {
    const device = try validate(.{
        .get_memory_fd = dummyMemoryFd,
        .get_modifier = dummyModifier,
        .get_semaphore_fd = dummySemaphoreFd,
        .import_semaphore_fd = dummyImport,
    });
    try @import("std").testing.expectEqual(abi.VK_SUCCESS, device.get_memory_fd(null, undefined, undefined));
}

test "each missing procedure is rejected" {
    const complete = Raw{
        .get_memory_fd = dummyMemoryFd,
        .get_modifier = dummyModifier,
        .get_semaphore_fd = dummySemaphoreFd,
        .import_semaphore_fd = dummyImport,
    };
    var missing = complete;
    missing.get_memory_fd = null;
    try @import("std").testing.expectError(error.MissingMemoryFd, validate(missing));
    missing = complete;
    missing.get_modifier = null;
    try @import("std").testing.expectError(error.MissingModifier, validate(missing));
    missing = complete;
    missing.get_semaphore_fd = null;
    try @import("std").testing.expectError(error.MissingSemaphoreFd, validate(missing));
    missing = complete;
    missing.import_semaphore_fd = null;
    try @import("std").testing.expectError(error.MissingImportSemaphoreFd, validate(missing));
}
