//! Optional copied canonical graphics; no Render, codec or runtime policy.
const std = @import("std");
const Terminal = @import("howl_vt").Terminal;
const c = @import("vt_native_types");

/// Native argument, bounded storage and exact observation-context failures.
pub const Error = error{ InvalidArgument, ResourceLimit, BufferTooSmall, ContextChanged };

comptime {
    if (Terminal.maximum_images != c.HVT_MAX_IMAGES or
        Terminal.maximum_image_placements != c.HVT_MAX_IMAGE_PLACEMENTS or
        Terminal.maximum_image_dimension != c.HVT_MAX_IMAGE_DIMENSION or
        Terminal.maximum_image_bytes != c.HVT_MAX_IMAGE_BYTES or
        Terminal.maximum_image_storage_bytes != c.HVT_MAX_IMAGE_STORAGE_BYTES)
        @compileError("Canonical graphics limits changed: review the native contract");
}

fn admitPointer(comptime T: type, pointer: ?[*]T, capacity: usize, maximum: usize) Error!void {
    if (capacity > maximum) return error.ResourceLimit;
    if (capacity != 0 and pointer == null) return error.InvalidArgument;
}
fn prefix(comptime T: type, pointer: ?[*]T, required: usize) Error![]T {
    if (required == 0) return &.{};
    const ptr = pointer orelse return error.InvalidArgument;
    const bytes = std.math.mul(usize, required, @sizeOf(T)) catch return error.InvalidArgument;
    // zig-audit: acknowledge discard
    // reason: Validate the admitted complete required prefix before forming its typed slice.
    _ = std.math.add(usize, @intFromPtr(ptr), bytes) catch return error.InvalidArgument;
    return ptr[0..required];
}

/// Copies all retained image metadata and densely filtered visible placements.
/// Both array prefixes are admitted before either is written; only shortage
/// publishes a fixed manifest on failure. Caller ranges must be disjoint.
pub fn copyManifest(observed: *const Terminal.Observation, history: u32, image_pointer: ?[*]c.hvt_image, image_capacity: usize, placement_pointer: ?[*]c.hvt_image_placement, placement_capacity: usize, out: *c.hvt_graphics) Error!void {
    out.* = std.mem.zeroes(c.hvt_graphics);
    try admitPointer(c.hvt_image, image_pointer, image_capacity, c.HVT_MAX_IMAGES);
    try admitPointer(c.hvt_image_placement, placement_pointer, placement_capacity, c.HVT_MAX_IMAGE_PLACEMENTS);
    const graphics = observed.images(history);
    const slots = graphics.placementCount();
    var visible: usize = 0;
    for (0..slots) |index| {
        if (graphics.placement(index) != null) visible += 1;
    }
    const result: c.hvt_graphics = .{
        .terminal_revision = graphics.semantic_generation,
        .graphics_revision = graphics.generation,
        .content_revision = graphics.content_generation,
        .image_count = @intCast(graphics.imageCount()),
        .placement_count = @intCast(visible),
        .history_offset = graphics.view.history_offset,
        .cell_width = graphics.cell_pixel_width,
        .cell_height = graphics.cell_pixel_height,
        .rows = graphics.view.rows,
        .columns = graphics.view.cols,
        .alternate_screen = @intFromBool(graphics.view.is_alternate_screen),
        .reserved = @splat(0),
    };
    if (image_capacity < result.image_count or placement_capacity < visible) {
        out.* = result;
        return error.BufferTooSmall;
    }
    const images = try prefix(c.hvt_image, image_pointer, result.image_count);
    const placements = try prefix(c.hvt_image_placement, placement_pointer, visible);
    for (images, 0..) |*item, index| {
        // zig-audit: acknowledge orelse_unreachable
        // reason: Canonical imageCount/image define a dense retained image index space during this serialized observation.
        const image = graphics.image(index) orelse unreachable;
        item.* = .{ .generation = image.generation, .image_id = image.id, .width = image.width, .height = image.height, .byte_count = @intCast(image.pixels.len) };
    }
    var copied: usize = 0;
    for (0..slots) |index| {
        const placement = graphics.placement(index) orelse continue;
        placements[copied] = .{
            .generation = placement.generation,
            .image_id = placement.image_id,
            .source_x = placement.source_x,
            .source_y = placement.source_y,
            .source_width = placement.source_width,
            .source_height = placement.source_height,
            .cell_x = placement.cell_x,
            .cell_y = placement.cell_y,
            .pixel_width = placement.pixel_width,
            .pixel_height = placement.pixel_height,
            .z = placement.z,
            .row = placement.row,
            .column = placement.col,
            .reserved = 0,
        };
        copied += 1;
    }
    std.debug.assert(copied == visible);
    out.* = result;
}

/// Copies one exact current RGBA8 image; no source bytes or query state escape.
/// A strict terminal revision rejects every intervening mutation across calls.
pub fn copyPixels(observed: *const Terminal.Observation, revision: u64, id: u32, generation: u64, pointer: ?[*]u8, capacity: usize, out_required: *usize) Error!void {
    out_required.* = 0;
    try admitPointer(u8, pointer, capacity, c.HVT_MAX_IMAGE_BYTES);
    if (id == 0 or generation == 0) return error.InvalidArgument;
    const graphics = observed.images(0);
    if (revision != graphics.semantic_generation) return error.ContextChanged;
    const image = for (0..graphics.imageCount()) |index| {
        const candidate = graphics.image(index) orelse continue;
        if (candidate.id == id and candidate.generation == generation) break candidate;
    } else return error.ContextChanged;
    if (capacity < image.pixels.len) {
        out_required.* = image.pixels.len;
        return error.BufferTooSmall;
    }
    const bytes = try prefix(u8, pointer, image.pixels.len);
    @memcpy(bytes, image.pixels);
    out_required.* = bytes.len;
}
