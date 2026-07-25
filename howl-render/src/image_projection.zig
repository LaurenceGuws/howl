//! Projects frozen VT image facts into caller-owned backend-neutral deltas.

const std = @import("std");
const howl_vt = @import("howl_vt");

const VtTerminal = howl_vt.Terminal;

/// Identifies one decoded terminal image already retained by the caller.
pub const ImageIdentity = struct {
    /// Matches the application-selected Kitty image identity.
    id: u32,
    /// Distinguishes replacement content under the same identity.
    generation: u64,
};

/// Locates one newly required RGBA upload in caller pixel storage.
pub const ImageUpload = struct {
    /// Supplies identity and replacement generation.
    identity: ImageIdentity,
    /// Supplies decoded pixel width.
    width: u32,
    /// Supplies decoded pixel height.
    height: u32,
    /// Locates exact RGBA8 bytes in `Update.pixels`.
    pixel_offset: usize,
    /// Counts exact RGBA8 bytes.
    pixel_count: usize,
};

/// Copies one visible ordinary terminal image placement.
pub const ImagePlacement = struct {
    /// Resolves retained image content.
    image_id: u32,
    /// Distinguishes placement churn independently of image content.
    generation: u64,
    /// Identifies the visible semantic row.
    row: u16,
    /// Identifies the physical terminal column.
    col: u16,
    /// Selects the first decoded source column.
    source_x: u32 = 0,
    /// Selects the first decoded source row.
    source_y: u32 = 0,
    /// Counts selected decoded source columns.
    source_width: u32 = 0,
    /// Counts selected decoded source rows.
    source_height: u32 = 0,
    /// Offsets the destination within its anchor cell horizontally.
    cell_x: u32 = 0,
    /// Offsets the destination within its anchor cell vertically.
    cell_y: u32 = 0,
    /// Counts destination pixels horizontally.
    pixel_width: u32 = 0,
    /// Counts destination pixels vertically.
    pixel_height: u32 = 0,
    /// Orders the image relative to terminal text.
    z: i32 = 0,
};

/// Supplies caller-owned storage for one stateless image-plane projection.
pub const Buffers = struct {
    /// Lists images retained by the caller before this projection.
    retained: []const ImageIdentity,
    /// Receives only new or replaced RGBA8 bytes.
    pixels: []u8,
    /// Receives only new or replaced image descriptions.
    uploads: []ImageUpload,
    /// Receives retained identities absent from the current VT plane.
    removals: []u32,
    /// Receives the complete current visible placement list.
    placements: []ImagePlacement,
};

/// Borrows initialized image delta prefixes from caller storage.
pub const Update = struct {
    /// Reports the source plane identity represented by this delta.
    generation: u64,
    /// Reports the retained decoded image-content identity.
    content_generation: u64,
    /// Borrows packed RGBA8 bytes for `uploads`.
    pixels: []const u8,
    /// Borrows new or replaced images.
    uploads: []const ImageUpload,
    /// Borrows removed image identities.
    removals: []const u32,
    /// Borrows the complete visible placement snapshot.
    placements: []const ImagePlacement,
};

/// Reports storage aliasing or exact caller image-delta capacity failures.
pub const Error = error{
    AliasedStorage,
    InsufficientImagePixels,
    InsufficientImageUploads,
    InsufficientImageRemovals,
    InsufficientImagePlacements,
};

/// Projects one immutable VT image plane into caller-owned upload/removal facts.
///
/// The projection retains no image or GPU identity. All capacities are
/// preflighted before any destination mutation.
pub fn project(
    source: VtTerminal.Images,
    buffers: Buffers,
) Error!Update {
    if (aliases(buffers)) return error.AliasedStorage;
    var pixel_count: usize = 0;
    var upload_count: usize = 0;
    var image_index: usize = 0;
    while (image_index < source.imageCount()) : (image_index += 1) {
        const value = source.image(image_index) orelse continue;
        if (containsImage(buffers.retained, value.id, value.generation)) continue;
        if (pixel_count > std.math.maxInt(usize) - value.pixels.len)
            return error.InsufficientImagePixels;
        pixel_count += value.pixels.len;
        upload_count += 1;
    }
    var removal_count: usize = 0;
    for (buffers.retained) |retained| {
        if (!sourceHasImage(source, retained.id)) removal_count += 1;
    }
    var placement_count: usize = 0;
    var placement_index: usize = 0;
    while (placement_index < source.placementCount()) : (placement_index += 1) {
        if (source.placement(placement_index) != null) placement_count += 1;
    }

    if (buffers.pixels.len < pixel_count) return error.InsufficientImagePixels;
    if (buffers.uploads.len < upload_count) return error.InsufficientImageUploads;
    if (buffers.removals.len < removal_count) return error.InsufficientImageRemovals;
    if (buffers.placements.len < placement_count) return error.InsufficientImagePlacements;

    var pixel_used: usize = 0;
    var upload_used: usize = 0;
    image_index = 0;
    while (image_index < source.imageCount()) : (image_index += 1) {
        const value = source.image(image_index) orelse continue;
        if (containsImage(buffers.retained, value.id, value.generation)) continue;
        @memcpy(buffers.pixels[pixel_used..][0..value.pixels.len], value.pixels);
        buffers.uploads[upload_used] = .{
            .identity = .{ .id = value.id, .generation = value.generation },
            .width = value.width,
            .height = value.height,
            .pixel_offset = pixel_used,
            .pixel_count = value.pixels.len,
        };
        pixel_used += value.pixels.len;
        upload_used += 1;
    }
    var removal_used: usize = 0;
    for (buffers.retained) |retained| {
        if (sourceHasImage(source, retained.id)) continue;
        buffers.removals[removal_used] = retained.id;
        removal_used += 1;
    }
    var placement_used: usize = 0;
    placement_index = 0;
    while (placement_index < source.placementCount()) : (placement_index += 1) {
        const value = source.placement(placement_index) orelse continue;
        buffers.placements[placement_used] = .{
            .image_id = value.image_id,
            .generation = value.generation,
            .row = value.row,
            .col = value.col,
            .source_x = value.source_x,
            .source_y = value.source_y,
            .source_width = value.source_width,
            .source_height = value.source_height,
            .cell_x = value.cell_x,
            .cell_y = value.cell_y,
            .pixel_width = value.pixel_width,
            .pixel_height = value.pixel_height,
            .z = value.z,
        };
        placement_used += 1;
    }
    return .{
        .generation = source.generation,
        .content_generation = source.content_generation,
        .pixels = buffers.pixels[0..pixel_used],
        .uploads = buffers.uploads[0..upload_used],
        .removals = buffers.removals[0..removal_used],
        .placements = buffers.placements[0..placement_used],
    };
}

fn containsImage(values: []const ImageIdentity, id: u32, generation: u64) bool {
    for (values) |value| if (value.id == id and value.generation == generation) return true;
    return false;
}

fn sourceHasImage(source: VtTerminal.Images, id: u32) bool {
    var index: usize = 0;
    while (index < source.imageCount()) : (index += 1)
        if (source.image(index)) |value| if (value.id == id) return true;
    return false;
}

fn aliases(buffers: Buffers) bool {
    const pixels = std.mem.sliceAsBytes(buffers.pixels);
    const uploads = std.mem.sliceAsBytes(buffers.uploads);
    const removals = std.mem.sliceAsBytes(buffers.removals);
    const placements = std.mem.sliceAsBytes(buffers.placements);
    const retained = std.mem.sliceAsBytes(buffers.retained);
    return slicesOverlap(pixels, uploads) or
        slicesOverlap(pixels, removals) or
        slicesOverlap(pixels, placements) or
        slicesOverlap(pixels, retained) or
        slicesOverlap(uploads, removals) or
        slicesOverlap(uploads, placements) or
        slicesOverlap(uploads, retained) or
        slicesOverlap(removals, placements) or
        slicesOverlap(removals, retained) or
        slicesOverlap(placements, retained);
}

fn slicesOverlap(a: []const u8, b: []const u8) bool {
    if (a.len == 0 or b.len == 0) return false;
    const a_start = @intFromPtr(a.ptr);
    const b_start = @intFromPtr(b.ptr);
    return if (a_start <= b_start)
        b_start - a_start < a.len
    else
        a_start - b_start < b.len;
}
