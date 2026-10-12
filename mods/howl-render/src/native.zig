//! Optional Render-owned native schemas and bulk projection.
//! The renderer and direct local roots never import this foreign-boundary root.
const std = @import("std");
const terminal = @import("renderer");
/// Exact owner header declarations.
pub const c = @import("render_native_types");
/// One fixed native resource-upload metadata record.
pub const ResourceInfo = c.hrc_resource;
/// One exact native resource retirement record.
pub const RemovalInfo = c.hrc_removal;
/// One versioned backend drawing command.
pub const CommandInfo = c.hrc_command;
/// One native resource/pixel borrow.
pub const Upload = c.hrc_upload;
const RenderResourceInfo = ResourceInfo;
const RenderRemovalInfo = RemovalInfo;
const RenderCommandInfo = CommandInfo;
/// Capacity or invalid internal pixel-span failure before output mutation.
pub const Error = error{ BufferTooSmall, InvalidPixelSpan };

/// Copies an exact resource identity without interpreting backend texture handles.
pub fn resourceRef(resource: terminal.ResourceRef, out: *ResourceInfo) void {
    out.resource = @backingInt(resource.resource);
    out.generation = @backingInt(resource.generation);
}
/// Copies one exact resource retirement.
pub fn removalRef(resource: terminal.ResourceRef, out: *RemovalInfo) void {
    out.* = .{ .resource = @backingInt(resource.resource), .generation = @backingInt(resource.generation) };
}
/// Packs canonical RGBA channels into the versioned native integer.
pub fn colorBits(color: terminal.Color) u32 {
    return @as(u32, color.r) |
        (@as(u32, color.g) << 8) |
        (@as(u32, color.b) << 16) |
        (@as(u32, color.a) << 24);
}

fn fillCommandResource(output: *RenderCommandInfo, resource: terminal.ResourceView) void {
    output.resource = @backingInt(resource.resource.resource);
    output.generation = @backingInt(resource.resource.generation);
    output.format = @backingInt(resource.format);
    output.resource_width = resource.size.width;
    output.resource_height = resource.size.height;
    const source = resource.source orelse terminal.SourceRect{
        .x = 0,
        .y = 0,
        .width = resource.size.width,
        .height = resource.size.height,
    };
    output.source_x = source.x;
    output.source_y = source.y;
    output.source_width = source.width;
    output.source_height = source.height;
}

fn fillRectFields(
    destination: terminal.Rect,
    clip: terminal.Rect,
    output: *RenderCommandInfo,
) void {
    output.destination_x = destination.x;
    output.destination_y = destination.y;
    output.destination_width = destination.width;
    output.destination_height = destination.height;
    output.clip_x = clip.x;
    output.clip_y = clip.y;
    output.clip_width = clip.width;
    output.clip_height = clip.height;
}

/// Copies a drawing command into the owned native schema.
pub fn commandInfo(
    command: terminal.Command,
    output: *RenderCommandInfo,
) void {
    output.* = .{};
    switch (command) {
        .solid => |solid| {
            output.tag = c.HRC_SOLID;
            output.color_rgba = colorBits(solid.color);
            fillRectFields(solid.rect, solid.rect, output);
        },
        .alpha_mask => |mask| {
            output.tag = c.HRC_ALPHA_MASK;
            output.color_rgba = colorBits(mask.color);
            output.cursor_component = @intFromBool(mask.cursor_component);
            fillRectFields(mask.destination, mask.clip, output);
            fillCommandResource(output, mask.resource);
        },
        .rgba => |rgba| {
            output.tag = c.HRC_RGBA;
            fillRectFields(rgba.destination, rgba.clip, output);
            fillCommandResource(output, rgba.resource);
        },
    }
}

/// Projects all commands in one call into caller-owned native record storage.
/// Capacity rejection leaves the entire output untouched.
pub fn commands(values: []const terminal.Command, output: []CommandInfo) Error![]const CommandInfo {
    if (values.len > output.len) return error.BufferTooSmall;
    for (values, 0..) |command, index| commandInfo(command, &output[index]);
    return output[0..values.len];
}
/// Projects all resource retirements into caller storage.
pub fn removals(values: []const terminal.ResourceRef, output: []RemovalInfo) Error![]const RemovalInfo {
    if (values.len > output.len) return error.BufferTooSmall;
    for (values, 0..) |value, index| removalRef(value, &output[index]);
    return output[0..values.len];
}
/// Projects metadata while borrowing each exact pixel span from the immutable frame.
/// All spans/capacity are validated before any output is modified.
pub fn uploads(values: []const terminal.FrameResourceUpload, pixels: []const u8, output: []Upload) Error![]const Upload {
    if (values.len > output.len) return error.BufferTooSmall;
    for (values) |value| {
        if (value.pixel_offset > pixels.len or value.pixel_count > pixels.len - value.pixel_offset)
            return error.InvalidPixelSpan;
    }
    for (values, 0..) |value, index| {
        output[index] = std.mem.zeroes(Upload);
        resourceRef(value.resource, &output[index].info);
        output[index].info.pixel_count = value.pixel_count;
        output[index].info.stride = value.stride;
        output[index].info.width = value.size.width;
        output[index].info.height = value.size.height;
        output[index].info.format = @backingInt(value.format);
        output[index].pixels = pixels[value.pixel_offset..].ptr;
        output[index].pixel_len = value.pixel_count;
    }
    return output[0..values.len];
}

test "native command bulk projection preserves signed geometry and RGBA identity" {
    const input = [_]terminal.Command{.{ .solid = .{
        .rect = .{ .x = -3, .y = 4, .width = 20, .height = 9 },
        .color = .{ .r = 1, .g = 2, .b = 3, .a = 4 },
    } }};
    var output: [1]CommandInfo = undefined;
    const result = try commands(&input, &output);
    try std.testing.expectEqual(@as(u8, c.HRC_SOLID), result[0].tag);
    try std.testing.expectEqual(@as(i32, -3), result[0].destination_x);
    try std.testing.expectEqual(@as(u32, 0x04030201), result[0].color_rgba);
    try std.testing.expectEqual(@as(u16, 20), result[0].clip_width);
    output[0].tag = 99;
    try std.testing.expectError(error.BufferTooSmall, commands(&input, output[0..0]));
    try std.testing.expectEqual(@as(u8, 99), output[0].tag);
}
test "native record layout preserves the existing accepted drawing vocabulary" {
    try std.testing.expectEqual(@as(usize, 40), @sizeOf(ResourceInfo));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(RemovalInfo));
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(CommandInfo));
    try std.testing.expectEqual(@as(usize, 36), @offsetOf(CommandInfo, "destination_width"));
}

/// Finds the full-surface background in a complete command frame.
pub fn background(commands_value: []const terminal.Command, surface: terminal.Size) u32 {
    for (commands_value) |command| switch (command) {
        .solid => |solid| {
            if (solid.rect.x == 0 and solid.rect.y == 0 and
                solid.rect.width == surface.width and solid.rect.height == surface.height)
                return colorBits(solid.color);
        },
        else => {},
    };
    return 0xff211918;
}

test "native upload projection validates every pixel span before any output write" {
    const values = [_]terminal.FrameResourceUpload{
        .{ .resource = .{ .resource = @fromBackingInt(1), .generation = @fromBackingInt(1) }, .format = .alpha8, .size = .{ .width = 1, .height = 1 }, .stride = 1, .pixel_offset = 0, .pixel_count = 1 },
        .{ .resource = .{ .resource = @fromBackingInt(2), .generation = @fromBackingInt(1) }, .format = .alpha8, .size = .{ .width = 1, .height = 1 }, .stride = 1, .pixel_offset = std.math.maxInt(usize), .pixel_count = 1 },
    };
    var output = [2]Upload{ std.mem.zeroes(Upload), std.mem.zeroes(Upload) };
    output[0].info.resource = 77;
    output[1].info.resource = 78;
    try std.testing.expectError(error.InvalidPixelSpan, uploads(&values, &.{1}, &output));
    try std.testing.expectEqual(@as(u64, 77), output[0].info.resource);
    try std.testing.expectEqual(@as(u64, 78), output[1].info.resource);
    try std.testing.expectError(error.BufferTooSmall, uploads(&values, &.{1}, output[0..1]));
    try std.testing.expectEqual(@as(u64, 77), output[0].info.resource);
}
