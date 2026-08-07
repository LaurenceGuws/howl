//! Package-level ABI, signature, and used-closure proofs.

const std = @import("std");
const vk = @import("howl_vk");
const surface = vk.surface;
const terminal_cells = vk.terminal_cells;

fn local(
    source: u64,
    resource: u64,
    generation: u64,
) !surface.ResourceGeneration {
    return surface.ResourceGeneration.init(source, resource, generation);
}

test "retained terminal-cell capability is part of the curated package" {
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(terminal_cells.Instance));
}

test "surface contract is analyzed with generic draw storage" {
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(surface.ResourceGeneration));
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(surface.Vertex));
    try std.testing.expect(surface.max_vertices >= surface.max_quads);
    const clip = surface.Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    const command = surface.Command{ .kind = .solid, .first_index = 0, .index_count = 0, .clip = clip };
    const plan = surface.Plan{ .vertices = &.{}, .indices = &.{}, .commands = &.{command}, .atlas_changed = false };
    try std.testing.expectEqual(@as(usize, 1), plan.commands.len);
}

test "surface compact namespaces reject malformed source combinations" {
    const local_value = try surface.ResourceGeneration.local(4, 7, 2);
    const shared_value = try surface.ResourceGeneration.shared(7, 2);
    try std.testing.expect(!local_value.isShared());
    try std.testing.expect(shared_value.isShared());
    try std.testing.expectEqual(@as(u64, 7), try local_value.identity());
    try std.testing.expectEqual(@as(u64, 7), try shared_value.identity());
    try std.testing.expect(!std.meta.eql(local_value, shared_value));
    try std.testing.expectError(
        error.InvalidIdentity,
        surface.ResourceGeneration.init(0, 7, 2),
    );
    try std.testing.expectError(
        error.InvalidIdentity,
        surface.ResourceGeneration.init(4, shared_value.resource, 2),
    );
    try std.testing.expectError(
        error.InvalidIdentity,
        surface.ResourceGeneration.init(4, 0, 2),
    );
    try std.testing.expectError(
        error.InvalidGeneration,
        surface.ResourceGeneration.init(4, 7, 0),
    );
    var store = try surface.ResidencyStore.init(
        std.testing.allocator,
        .{ .resources = 1, .pixel_bytes = 4 },
    );
    defer store.deinit();
    const malformed = surface.ResourceGeneration{
        .source = 0,
        .resource = 7,
        .generation = 2,
    };
    const pixels = [_]u8{ 1, 2, 3, 4 };
    try std.testing.expectError(
        error.InvalidFrame,
        store.stage(frame(
            1,
            &.{upload(malformed, &pixels)},
            &.{},
            &.{},
        )),
    );
    var residency: [1]surface.Residency = undefined;
    try std.testing.expectEqual(
        @as(usize, 0),
        (try store.enumerate(&residency)).len,
    );
}

test "surface residency stages and commits transactionally" {
    var store = try surface.ResidencyStore.init(std.testing.allocator, .{ .resources = 2, .pixel_bytes = 32 });
    defer store.deinit();
    const key = try local(1, 1, 1);
    const pixels = [_]u8{ 1, 2, 3, 4 };
    try store.stage(.{ .revision = 1, .uploads = &.{
        .{ .resource = key, .kind = .alpha_mask, .width = 2, .height = 2, .stride = 2, .pixels = &pixels },
    }, .removals = &.{}, .commands = &.{} });
    var output: [2]surface.Residency = undefined;
    try std.testing.expectEqual(@as(usize, 0), (try store.enumerate(&output)).len);
    try store.complete();
    const resident = try store.enumerate(&output);
    try std.testing.expectEqual(@as(usize, 1), resident.len);
    try std.testing.expectEqual(key, resident[0].resource);
}

test "surface residency rejects malformed uploads without active mutation" {
    var store = try surface.ResidencyStore.init(std.testing.allocator, .{ .resources = 1, .pixel_bytes = 8 });
    defer store.deinit();
    const bad = surface.Upload{ .resource = try local(1, 1, 1), .kind = .alpha_mask, .width = 2, .height = 2, .stride = 1, .pixels = &.{ 1, 2, 3, 4 } };
    try std.testing.expectError(error.InvalidFrame, store.stage(.{ .revision = 1, .uploads = &.{bad}, .removals = &.{}, .commands = &.{} }));
    var output: [1]surface.Residency = undefined;
    try std.testing.expectEqual(@as(usize, 0), (try store.enumerate(&output)).len);
}

test "surface residency replaces and removes exact generations" {
    var store = try surface.ResidencyStore.init(std.testing.allocator, .{ .resources = 2, .pixel_bytes = 32 });
    defer store.deinit();
    const first = try local(1, 7, 1);
    const second = try local(first.source, first.resource, 2);
    const pixels = [_]u8{ 1, 2, 3, 4 };
    try store.stage(frame(1, &.{upload(first, &pixels)}, &.{}, &.{}));
    try store.complete();
    try store.stage(frame(2, &.{upload(second, &pixels)}, &.{}, &.{}));
    try store.complete();
    var output: [2]surface.Residency = undefined;
    var resident = try store.enumerate(&output);
    try std.testing.expectEqual(@as(usize, 1), resident.len);
    try std.testing.expectEqual(second, resident[0].resource);
    try store.stage(frame(3, &.{}, &.{.{ .resource = second }}, &.{}));
    try store.complete();
    resident = try store.enumerate(&output);
    try std.testing.expectEqual(@as(usize, 0), resident.len);
}

test "surface residency rejects stale generations and preserves active bytes" {
    var store = try surface.ResidencyStore.init(std.testing.allocator, .{ .resources = 1, .pixel_bytes = 8 });
    defer store.deinit();
    const key = try local(1, 1, 2);
    const pixels = [_]u8{ 1, 2, 3, 4 };
    try store.stage(frame(1, &.{upload(key, &pixels)}, &.{}, &.{}));
    try store.complete();
    const stale = try local(key.source, key.resource, 1);
    try std.testing.expectError(error.GenerationMismatch, store.stage(frame(2, &.{upload(stale, &pixels)}, &.{}, &.{})));
    var output: [1]surface.Residency = undefined;
    const resident = try store.enumerate(&output);
    try std.testing.expectEqual(key, resident[0].resource);
}

test "surface candidate discard models failed GPU application" {
    var store = try surface.ResidencyStore.init(std.testing.allocator, .{ .resources = 2, .pixel_bytes = 16 });
    defer store.deinit();
    const first = try local(1, 1, 1);
    const second = try local(1, 2, 1);
    const pixels = [_]u8{ 1, 2, 3, 4 };
    try store.stage(frame(1, &.{upload(first, &pixels)}, &.{}, &.{}));
    try store.complete();
    try store.stage(frame(2, &.{upload(second, &pixels)}, &.{}, &.{}));
    store.discard();
    var output: [2]surface.Residency = undefined;
    const resident = try store.enumerate(&output);
    try std.testing.expectEqual(@as(usize, 1), resident.len);
    try std.testing.expectEqual(first, resident[0].resource);
    try store.stage(frame(3, &.{upload(second, &pixels)}, &.{}, &.{}));
    try store.complete();
    try std.testing.expectEqual(@as(usize, 2), (try store.enumerate(&output)).len);
}

test "atlas state commits only through the completion boundary" {
    var context = surface.Context{};
    try std.testing.expect(!context.atlas_initialized);
    try std.testing.expect(!context.image_atlas_initialized);
    // A recording or submission failure does not call complete, so both
    // layout state remains at its prior values.
    context.complete(.{ .alpha_initialized = true, .image_initialized = true });
    try std.testing.expect(context.atlas_initialized);
    try std.testing.expect(context.image_atlas_initialized);
    // Later replacement recording can require both transitions again, but a
    // failed operation leaves the established state unchanged.
    context.complete(.{ .alpha_initialized = false, .image_initialized = false });
    try std.testing.expect(context.atlas_initialized);
    try std.testing.expect(context.image_atlas_initialized);
}

test "surface capacity failure rolls back and complete candidate rebuilds geometry" {
    var store = try surface.ResidencyStore.init(std.testing.allocator, .{ .resources = 1, .pixel_bytes = 4 });
    defer store.deinit();
    var builder = try surface.FrameBuilder.init(std.testing.allocator);
    defer builder.deinit();
    const key = try local(1, 1, 1);
    const pixels = [_]u8{ 1, 2, 3, 4 };
    const command = surface.FrameCommand{ .alpha_mask = .{
        .rect = .{ .x = 0, .y = 0, .width = 2, .height = 2 },
        .clip = .{ .x = 0, .y = 0, .width = 2, .height = 2 },
        .resource = key,
        .color = .{ 1, 1, 1, 1 },
    } };
    const too_many = [_]surface.Upload{ upload(key, &pixels), upload(try local(2, 1, 1), &pixels) };
    try std.testing.expectError(error.Capacity, store.stage(frame(1, &too_many, &.{}, &.{command})));
    var output: [1]surface.Residency = undefined;
    try std.testing.expectEqual(@as(usize, 0), (try store.enumerate(&output)).len);
    const accepted = frame(2, &.{upload(key, &pixels)}, &.{}, &.{command});
    try store.stage(accepted);
    const plan = try builder.build(&store, accepted);
    try std.testing.expectEqual(@as(usize, 1), plan.commands.len);
    try store.complete();
}

test "surface sparse frame rebuilds complete physical residency" {
    var store = try surface.ResidencyStore.init(std.testing.allocator, .{ .resources = 2, .pixel_bytes = 32 });
    defer store.deinit();
    var builder = try surface.FrameBuilder.init(std.testing.allocator);
    defer builder.deinit();
    const first = try local(1, 1, 1);
    const second = try local(2, 1, 1);
    const pixels = [_]u8{ 1, 2, 3, 4 };
    try store.stage(frame(1, &.{ upload(first, &pixels), upload(second, &pixels) }, &.{}, &.{}));
    try store.complete();
    const commands = [_]surface.FrameCommand{
        alphaCommand(first, 0),
        alphaCommand(second, 2),
    };
    const sparse = frame(2, &.{}, &.{}, &commands);
    try store.stage(sparse);
    const plan = try builder.build(&store, sparse);
    try std.testing.expectEqual(@as(usize, 2), plan.commands.len);
    try std.testing.expect(plan.atlas_changed);
    try store.complete();
}

test "surface admits the complete quad command capacity" {
    var store = try surface.ResidencyStore.init(std.testing.allocator, .{
        .resources = 1,
        .pixel_bytes = 1,
    });
    defer store.deinit();
    var builder = try surface.FrameBuilder.init(std.testing.allocator);
    defer builder.deinit();
    const commands = try std.testing.allocator.alloc(
        surface.FrameCommand,
        surface.max_commands,
    );
    defer std.testing.allocator.free(commands);
    for (commands, 0..) |*command, index| command.* = .{ .solid = .{
        .rect = .{
            .x = @intCast(index % 64),
            .y = @intCast(index / 64),
            .width = 1,
            .height = 1,
        },
        .clip = .{ .x = 0, .y = 0, .width = 64, .height = 64 },
        .color = .{ 1, 1, 1, 1 },
    } };
    const complete = frame(1, &.{}, &.{}, commands);
    try store.stage(complete);
    const plan = try builder.build(&store, complete);
    try std.testing.expectEqual(surface.max_quads, plan.commands.len);
    try std.testing.expectEqual(surface.max_vertices, plan.vertices.len);
    try std.testing.expectEqual(surface.max_indices, plan.indices.len);
    try store.complete();
}

test "surface unknown command resource rejects candidate and remains reusable" {
    var store = try surface.ResidencyStore.init(std.testing.allocator, .{ .resources = 1, .pixel_bytes = 8 });
    defer store.deinit();
    const known = try local(1, 1, 1);
    const unknown = try local(1, 2, 1);
    const pixels = [_]u8{ 1, 2, 3, 4 };
    try std.testing.expectError(
        error.GenerationMismatch,
        store.stage(frame(1, &.{upload(known, &pixels)}, &.{}, &.{alphaCommand(unknown, 0)})),
    );
    try store.stage(frame(2, &.{upload(known, &pixels)}, &.{}, &.{alphaCommand(known, 0)}));
    try store.complete();
}

fn upload(resource: surface.ResourceGeneration, pixels: []const u8) surface.Upload {
    return .{ .resource = resource, .kind = .alpha_mask, .width = 2, .height = 2, .stride = 2, .pixels = pixels };
}

fn alphaCommand(resource: surface.ResourceGeneration, x: i32) surface.FrameCommand {
    return .{ .alpha_mask = .{
        .rect = .{ .x = x, .y = 0, .width = 2, .height = 2 },
        .clip = .{ .x = 0, .y = 0, .width = 8, .height = 8 },
        .resource = resource,
        .color = .{ 1, 1, 1, 1 },
    } };
}

fn frame(
    revision: u64,
    uploads: []const surface.Upload,
    removals: []const surface.Removal,
    commands: []const surface.FrameCommand,
) surface.Frame {
    return .{ .revision = revision, .uploads = uploads, .removals = removals, .commands = commands };
}

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
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(vk.abi.VkDescriptorBufferInfo));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(vk.abi.VkDescriptorBufferInfo));
    try std.testing.expectEqual(@as(usize, 56), @sizeOf(vk.abi.VkBufferMemoryBarrier));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(vk.abi.VkBufferMemoryBarrier));
    const free_descriptor_sets: *const fn (
        vk.abi.VkDevice,
        vk.abi.VkDescriptorPool,
        u32,
        [*c]const vk.abi.VkDescriptorSet,
    ) callconv(.c) vk.abi.VkResult = &vk.abi.vkFreeDescriptorSets;
    try std.testing.expect(@intFromPtr(free_descriptor_sets) != 0);
    const device: vk.dispatch.ExternalImageDispatch = undefined;
    try std.testing.expect(@TypeOf(device.get_memory_fd) == @typeInfo(vk.abi.PFN_vkGetMemoryFdKHR).optional.child);
    try std.testing.expect(@TypeOf(device.get_modifier) == @typeInfo(vk.abi.PFN_vkGetImageDrmFormatModifierPropertiesEXT).optional.child);
    try std.testing.expect(@TypeOf(device.get_semaphore_fd) == @typeInfo(vk.abi.PFN_vkGetSemaphoreFdKHR).optional.child);
    try std.testing.expect(@TypeOf(device.import_semaphore_fd) == @typeInfo(vk.abi.PFN_vkImportSemaphoreFdKHR).optional.child);
}

test "ABI declaration analysis and layout drift receipt" {
    const declarations = @typeInfo(vk.abi).@"struct".decl_names;
    try std.testing.expectEqual(@as(usize, 529), declarations.len);
    try std.testing.expectEqual(@as(c_int, 0), vk.abi.VK_FILTER_NEAREST);
    try std.testing.expectEqual(@as(c_int, 0), vk.abi.VK_SAMPLER_MIPMAP_MODE_NEAREST);
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
    try std.testing.expectEqual(@as(usize, 13060), layout_receipt);
}
