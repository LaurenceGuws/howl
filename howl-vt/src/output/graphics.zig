//! Optional VT-native image-to-final-command projection.
//! A cut copies canonical RGBA bytes and owns its final commands; the same
//! output lease pins it while canonical images, animations and banks can mutate.
const std = @import("std");
const VT = @import("howl_vt").Terminal;
const frame = @import("frame");
const limits = @import("limits");

const maximum_images = limits.maximum_output_images;
const maximum_bytes = limits.maximum_output_image_bytes;
const deep_threshold = std.math.minInt(i32) / 2;

/// One exact immutable image resource borrowed from a held output cut.
pub const Image = struct {
    resource: frame.ResourceRef,
    size: frame.Size,
    pixels: []const u8,
};

/// Draw-only, immutable graphics facts; no semantic cells or renderer inputs.
pub const View = struct {
    deep: []const frame.Command = &.{},
    negative: []const frame.Command = &.{},
    positive: []const frame.Command = &.{},
    images: []const Image = &.{},
};

/// One privately owned, lazily allocated cut. Exactly one cut may be pinned.
pub const Cut = struct {
    pixels: []u8 = &.{},
    commands: []frame.Command = &.{},
    images: [maximum_images]Image = undefined,
    image_count: usize = 0,
    deep_end: usize = 0,
    negative_end: usize = 0,
    plane_generation: u64 = 0,
    content_generation: u64 = 0,
    placeholder_revision: u64 = 0,
    visible_start: u64 = 0,
    alternate: bool = false,
    rows: u16 = 0,
    cols: u16 = 0,
    cell_width: u16 = 0,
    cell_height: u16 = 0,

    /// Releases only the pixels and commands privately owned by this cut.
    pub fn deinit(self: *Cut, allocator: std.mem.Allocator) void {
        allocator.free(self.pixels);
        allocator.free(self.commands);
        self.* = .{};
    }

    /// Borrows the final commands and immutable pixels through the owner's lease.
    pub fn view(self: *const Cut) View {
        return .{
            .deep = self.commands[0..self.deep_end],
            .negative = self.commands[self.deep_end..self.negative_end],
            .positive = self.commands[self.negative_end..],
            .images = self.images[0..self.image_count],
        };
    }

    /// Checks every canonical view fact which can change graphics projection.
    pub fn matches(self: *const Cut, images: VT.Images, alternate: bool, rows: u16, cols: u16, cell_width: u16, cell_height: u16, placeholder_revision: u64) bool {
        return self.plane_generation == images.generation and
            self.content_generation == images.content_generation and
            self.placeholder_revision == placeholder_revision and
            self.visible_start == images.visible_row_start and
            self.alternate == alternate and
            self.rows == rows and self.cols == cols and
            self.cell_width == cell_width and self.cell_height == cell_height;
    }
};

/// Exact bounded graphics staging and allocation failures.
pub const BuildError = std.mem.Allocator.Error || error{ ImageLimit, ImageBytesLimit, UnsupportedScene, GenerationOverflow };

fn findImage(images: VT.Images, image_id: u32) ?VT.Image {
    for (0..images.imageCount()) |index| {
        const candidate = images.image(index).?;
        if (candidate.id == image_id) return candidate;
    }
    return null;
}

// Temporary native placement keys; only final frame.Command reaches the lease.
const Ordered = struct { placement: VT.ImagePlacement, top: i32, left: i32, ordinal: u32 };
fn orderLessThan(_: void, left: Ordered, right: Ordered) bool {
    const a = left.placement;
    const b = right.placement;
    if (a.z != b.z) return a.z < b.z;
    if (a.image_id != b.image_id) return a.image_id < b.image_id;
    if (a.generation != b.generation) return a.generation < b.generation;
    return left.ordinal < right.ordinal;
}

/// Stages one complete final-command cut without modifying accepted state.
/// A failed stage deallocates its partial copies and leaves all held cuts intact.
pub fn build(
    allocator: std.mem.Allocator,
    images: VT.Images,
    alternate: bool,
    rows: u16,
    cols: u16,
    cell_width: u16,
    cell_height: u16,
    placeholder_revision: u64,
    generation: u64,
) BuildError!Cut {
    if (generation == 0) return error.GenerationOverflow;
    var result: Cut = .{
        .plane_generation = images.generation,
        .content_generation = images.content_generation,
        .placeholder_revision = placeholder_revision,
        .visible_start = images.visible_row_start,
        .alternate = alternate,
        .rows = rows,
        .cols = cols,
        .cell_width = cell_width,
        .cell_height = cell_height,
    };
    errdefer result.deinit(allocator);
    var order: std.ArrayList(Ordered) = .empty;
    defer order.deinit(allocator);
    var iterator = images.placementIterator();
    while (iterator.next()) |visible| {
        if (order.items.len == limits.maximum_image_placements) return error.ImageLimit;
        // Native geometry uses wide coordinates. Optional draw commands have
        // an i32 viewport vocabulary: reject unrepresentable visible facts.
        const top = std.math.cast(i32, visible.top) orelse return error.UnsupportedScene;
        const left = std.math.cast(i32, visible.left) orelse return error.UnsupportedScene;
        try order.append(allocator, .{ .placement = visible.placement, .top = top, .left = left, .ordinal = @intCast(order.items.len) });
    }
    if (order.items.len == 0) return result;
    std.sort.heap(Ordered, order.items, {}, orderLessThan);

    var selected: [maximum_images]VT.Image = undefined;
    var total_bytes: usize = 0;
    for (order.items) |entry| {
        const placement = entry.placement;
        var found = false;
        for (selected[0..result.image_count]) |image| {
            if (image.id == placement.image_id) {
                found = true;
                break;
            }
        }
        if (found) continue;
        if (result.image_count == maximum_images) return error.ImageLimit;
        const image = findImage(images, placement.image_id) orelse return error.UnsupportedScene;
        if (image.width == 0 or image.height == 0 or image.width > VT.maximum_image_dimension or image.height > VT.maximum_image_dimension) return error.UnsupportedScene;
        const count = std.math.mul(usize, image.width, image.height) catch return error.ImageBytesLimit;
        const byte_count = std.math.mul(usize, count, 4) catch return error.ImageBytesLimit;
        if (byte_count != image.pixels.len or byte_count > VT.maximum_image_bytes) return error.UnsupportedScene;
        total_bytes = std.math.add(usize, total_bytes, byte_count) catch return error.ImageBytesLimit;
        if (total_bytes > maximum_bytes) return error.ImageBytesLimit;
        selected[result.image_count] = image;
        result.image_count += 1;
    }
    result.pixels = try allocator.alloc(u8, total_bytes);
    result.commands = try allocator.alloc(frame.Command, order.items.len);
    var start: usize = 0;
    for (selected[0..result.image_count], 0..) |image, index| {
        const end = start + image.pixels.len;
        @memcpy(result.pixels[start..end], image.pixels);
        result.images[index] = .{
            .resource = .{
                // zig-audit: acknowledge catch_unreachable
                // reason: Seven bounded external slots have fixed nonzero identities 3 through 9.
                .resource = frame.ResourceId.init(3 + index) catch unreachable,
                .generation = @fromBackingInt(generation),
            },
            .size = .{ .width = @intCast(image.width), .height = @intCast(image.height) },
            .pixels = result.pixels[start..end],
        };
        start = end;
    }

    const surface: frame.Rect = .{ .x = 0, .y = 0, .width = cols * cell_width, .height = rows * cell_height };
    var deep: usize = 0;
    var negative: usize = 0;
    for (order.items, 0..) |entry, command_index| {
        const placement = entry.placement;
        var resource_index: usize = 0;
        while (resource_index < result.image_count and selected[resource_index].id != placement.image_id) : (resource_index += 1) {}
        if (resource_index == result.image_count) return error.UnsupportedScene;
        const image = selected[resource_index];
        const source_right = std.math.add(u64, placement.source_x, placement.source_width) catch return error.UnsupportedScene;
        const source_bottom = std.math.add(u64, placement.source_y, placement.source_height) catch return error.UnsupportedScene;
        if (placement.source_width == 0 or placement.source_height == 0 or source_right > image.width or source_bottom > image.height) return error.UnsupportedScene;
        const width = std.math.cast(u16, placement.pixel_width) orelse return error.UnsupportedScene;
        const height = std.math.cast(u16, placement.pixel_height) orelse return error.UnsupportedScene;
        if (width == 0 or height == 0) return error.UnsupportedScene;
        result.commands[command_index] = .{ .rgba = .{
            .destination = .{
                .x = entry.left,
                .y = entry.top,
                .width = width,
                .height = height,
            },
            .clip = surface,
            .resource = .{
                .resource = result.images[resource_index].resource,
                .format = .rgba8,
                .size = result.images[resource_index].size,
                .source = .{
                    .x = @intCast(placement.source_x),
                    .y = @intCast(placement.source_y),
                    .width = @intCast(placement.source_width),
                    .height = @intCast(placement.source_height),
                },
            },
        } };
        if (placement.z < deep_threshold) deep += 1;
        if (placement.z < 0) negative += 1;
    }
    result.deep_end = deep;
    result.negative_end = negative;
    return result;
}
