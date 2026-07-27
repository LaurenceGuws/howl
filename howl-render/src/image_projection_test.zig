//! Proves stateless image projection through frozen VT image observations.

const std = @import("std");
const vt = @import("howl_vt");
const render = @import("howl_render");
const images = render.terminal_images;

const Storage = struct {
    pixels: [64]u8 = undefined,
    uploads: [8]images.ImageUpload = undefined,
    removals: [8]u32 = undefined,
    placements: [8]images.ImagePlacement = undefined,

    fn buffers(self: *Storage) images.Buffers {
        return .{
            .retained = &.{},
            .pixels = &self.pixels,
            .uploads = &self.uploads,
            .removals = &self.removals,
            .placements = &self.placements,
        };
    }
};

fn expectAliased(source: vt.Terminal.Images, buffers: images.Buffers) !void {
    try std.testing.expectError(error.AliasedStorage, images.project(source, buffers));
}

test "image projection uploads, reuses, and removes retained identities" {
    var source = try vt.Terminal.init(std.testing.allocator, 2, 4);
    defer source.deinit();
    try std.testing.expect((try source.feed("\x1b_Ga=T,f=32,s=1,v=1,i=7;AQIDBA==\x1b\\")).state_changed);
    const view = source.images(0);
    var storage: Storage = .{};
    const first = try images.project(view, storage.buffers());
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, first.pixels);
    try std.testing.expectEqual(view.image(0).?.id, first.uploads[0].identity.id);
    try std.testing.expectEqual(@as(usize, 1), first.placements.len);

    const retained = [_]images.ImageIdentity{first.uploads[0].identity};
    var unchanged = storage;
    var reuse_buffers = unchanged.buffers();
    reuse_buffers.retained = &retained;
    const reused = try images.project(view, reuse_buffers);
    try std.testing.expectEqual(@as(usize, 0), reused.uploads.len);
    try std.testing.expectEqual(@as(usize, 0), reused.pixels.len);

    const old_generation = first.uploads[0].identity.generation;
    try std.testing.expect((try source.feed("\x1b_Ga=t,f=32,s=1,v=1,i=7;BQYHCA==\x1b\\")).state_changed);
    const replacement_view = source.images(0);
    var replacement_storage: Storage = .{};
    const replacement = try images.project(replacement_view, .{
        .retained = &retained,
        .pixels = &replacement_storage.pixels,
        .uploads = &replacement_storage.uploads,
        .removals = &replacement_storage.removals,
        .placements = &replacement_storage.placements,
    });
    try std.testing.expectEqualSlices(u8, &.{ 5, 6, 7, 8 }, replacement.pixels);
    try std.testing.expectEqual(retained[0].id, replacement.uploads[0].identity.id);
    try std.testing.expect(replacement.uploads[0].identity.generation != old_generation);
    try std.testing.expectEqual(@as(usize, 0), replacement.removals.len);

    try std.testing.expect((try source.feed("\x1b_Ga=d,d=I,i=7\x1b\\")).state_changed);
    const removed_view = source.images(0);
    var removal_storage: Storage = .{};
    var removal_buffers = removal_storage.buffers();
    removal_buffers.retained = &retained;
    const removed = try images.project(removed_view, removal_buffers);
    try std.testing.expectEqualSlices(u32, &.{retained[0].id}, removed.removals);
    try std.testing.expectEqual(@as(usize, 0), removed.placements.len);
}

test "image projection preserves bytes on every capacity failure" {
    var source = try vt.Terminal.init(std.testing.allocator, 2, 4);
    defer source.deinit();
    try std.testing.expect((try source.feed("\x1b_Ga=T,f=32,s=1,v=1,i=7;AQIDBA==\x1b\\")).state_changed);
    const view = source.images(0);

    var pixels = @as([3]u8, @splat(0xaa));
    var uploads: [1]images.ImageUpload = undefined;
    var removals: [1]u32 = undefined;
    var placements: [1]images.ImagePlacement = undefined;
    const before_pixels = pixels;
    try std.testing.expectError(error.InsufficientImagePixels, images.project(view, .{
        .retained = &.{},
        .pixels = &pixels,
        .uploads = &uploads,
        .removals = &removals,
        .placements = &placements,
    }));
    try std.testing.expectEqualSlices(u8, &before_pixels, &pixels);

    var storage = Storage{};
    @memset(std.mem.asBytes(&storage), 0x5a);
    var before_storage: [@sizeOf(Storage)]u8 = undefined;
    @memcpy(&before_storage, std.mem.asBytes(&storage));
    try std.testing.expectError(error.InsufficientImageUploads, images.project(view, .{
        .retained = &.{},
        .pixels = &storage.pixels,
        .uploads = &[_]images.ImageUpload{},
        .removals = &storage.removals,
        .placements = &storage.placements,
    }));
    try std.testing.expectEqualSlices(u8, &before_storage, std.mem.asBytes(&storage));
    @memcpy(&before_storage, std.mem.asBytes(&storage));
    try std.testing.expectError(error.InsufficientImageRemovals, images.project(view, .{
        .retained = &.{.{ .id = 99, .generation = 1 }},
        .pixels = &storage.pixels,
        .uploads = &storage.uploads,
        .removals = &[_]u32{},
        .placements = &storage.placements,
    }));
    try std.testing.expectEqualSlices(u8, &before_storage, std.mem.asBytes(&storage));
    @memcpy(&before_storage, std.mem.asBytes(&storage));
    try std.testing.expectError(error.InsufficientImagePlacements, images.project(view, .{
        .retained = &.{},
        .pixels = &storage.pixels,
        .uploads = &storage.uploads,
        .removals = &storage.removals,
        .placements = &[_]images.ImagePlacement{},
    }));
    try std.testing.expectEqualSlices(u8, &before_storage, std.mem.asBytes(&storage));
}

test "image projection rejects every output and retained storage alias class" {
    var source = try vt.Terminal.init(std.testing.allocator, 2, 4);
    defer source.deinit();
    try std.testing.expect((try source.feed("\x1b_Ga=T,f=32,s=1,v=1,i=7;AQIDBA==\x1b\\")).state_changed);
    const view = source.images(0);
    var storage: Storage = .{};
    var alias_bytes: [256]u8 align(@alignOf(images.ImageUpload)) = undefined;
    @memset(&alias_bytes, 0xcc);
    const alias_before = alias_bytes;
    const alias_pixels = alias_bytes[0..64];
    const alias_uploads = @as([*]images.ImageUpload, @ptrCast(&alias_bytes))[0..1];
    const alias_removals = @as([*]u32, @ptrCast(&alias_bytes))[0..1];
    const alias_placements = @as([*]images.ImagePlacement, @ptrCast(&alias_bytes))[0..1];
    const alias_retained = @as([*]images.ImageIdentity, @ptrCast(&alias_bytes))[0..1];

    var buffers = storage.buffers();
    buffers.pixels = alias_pixels;
    buffers.uploads = alias_uploads;
    try expectAliased(view, buffers);
    buffers = storage.buffers();
    buffers.pixels = alias_pixels;
    buffers.removals = alias_removals;
    try expectAliased(view, buffers);
    buffers = storage.buffers();
    buffers.pixels = alias_pixels;
    buffers.placements = alias_placements;
    try expectAliased(view, buffers);
    buffers = storage.buffers();
    buffers.uploads = alias_uploads;
    buffers.removals = alias_removals;
    try expectAliased(view, buffers);
    buffers = storage.buffers();
    buffers.uploads = alias_uploads;
    buffers.placements = alias_placements;
    try expectAliased(view, buffers);
    buffers = storage.buffers();
    buffers.removals = alias_removals;
    buffers.placements = alias_placements;
    try expectAliased(view, buffers);
    buffers = storage.buffers();
    buffers.pixels = alias_pixels;
    buffers.retained = alias_retained;
    try expectAliased(view, buffers);
    buffers = storage.buffers();
    buffers.uploads = alias_uploads;
    buffers.retained = alias_retained;
    try expectAliased(view, buffers);
    buffers = storage.buffers();
    buffers.removals = alias_removals;
    buffers.retained = alias_retained;
    try expectAliased(view, buffers);
    buffers = storage.buffers();
    buffers.placements = alias_placements;
    buffers.retained = alias_retained;
    try expectAliased(view, buffers);
    try std.testing.expectEqualSlices(u8, &alias_before, &alias_bytes);
}

test "image projection retains crop placement z order and generation" {
    var source = try vt.Terminal.init(std.testing.allocator, 4, 8);
    defer source.deinit();
    try source.setCellPixelSize(8, 16);
    try std.testing.expect((try source.feed(
        "\x1b_Ga=t,f=32,s=2,v=2,i=1;AQIDBAUGBwgJCgsMDQ4PEA==\x1b\\",
    )).state_changed);
    try std.testing.expect((try source.feed(
        "\x1b_Ga=p,i=1,p=3,x=1,y=0,w=1,h=2,c=2,r=3,X=2,Y=4,z=-7\x1b\\",
    )).state_changed);
    const view = source.images(0);
    var storage: Storage = .{};
    const update = try images.project(view, storage.buffers());
    try std.testing.expectEqual(@as(usize, 1), update.placements.len);
    const placement = update.placements[0];
    const source_placement = view.placement(0).?;
    try std.testing.expectEqual(@as(u32, 1), source_placement.source_x);
    try std.testing.expectEqual(@as(u32, 0), source_placement.source_y);
    try std.testing.expectEqual(@as(u32, 1), source_placement.source_width);
    try std.testing.expectEqual(@as(u32, 2), source_placement.source_height);
    try std.testing.expectEqual(@as(u32, 2), source_placement.cell_x);
    try std.testing.expectEqual(@as(u32, 4), source_placement.cell_y);
    try std.testing.expectEqual(@as(u32, 14), source_placement.pixel_width);
    try std.testing.expectEqual(@as(u32, 44), source_placement.pixel_height);
    try std.testing.expectEqual(@as(i32, -7), source_placement.z);
    try std.testing.expectEqual(source_placement.source_x, placement.source_x);
    try std.testing.expectEqual(source_placement.source_width, placement.source_width);
    try std.testing.expectEqual(source_placement.cell_x, placement.cell_x);
    try std.testing.expectEqual(source_placement.pixel_width, placement.pixel_width);
    try std.testing.expectEqual(source_placement.z, placement.z);
    try std.testing.expect(update.generation != 0 and update.content_generation != 0);
}
