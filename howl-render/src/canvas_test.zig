const std = @import("std");
const canvas = @import("howl_render").canvas;

const red = canvas.Color{ .r = 255, .g = 0, .b = 0, .a = 255 };
const white = canvas.Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
const source: canvas.SourceId = @fromBackingInt(@intCast(11));

fn local(id: u64, generation: u64) canvas.LocalResourceRef {
    return .{
        .resource = @fromBackingInt(@intCast(id)),
        .generation = @fromBackingInt(@intCast(generation)),
    };
}

test "editor-like facts preserve clipped deterministic order and qualify resources" {
    const inputs = [_]canvas.Input{
        .{ .solid = .{
            .rect = .{ .x = -4, .y = 1, .width = 20, .height = 8 },
            .clip = .{ .x = 2, .y = 0, .width = 12, .height = 10 },
            .color = red,
        } },
        .{ .alpha_mask = .{
            .destination = .{ .x = 4, .y = 2, .width = 8, .height = 4 },
            .clip = .{ .x = 0, .y = 0, .width = 16, .height = 10 },
            .resource = .{
                .resource = local(7, 3),
                .format = .alpha8,
                .size = .{ .width = 4, .height = 2 },
            },
            .color = white,
        } },
        .{ .rgba = .{
            .destination = .{ .x = 14, .y = 8, .width = 4, .height = 4 },
            .clip = .{ .x = 0, .y = 0, .width = 16, .height = 10 },
            .resource = .{
                .resource = local(9, 5),
                .format = .rgba8,
                .size = .{ .width = 2, .height = 2 },
            },
        } },
    };
    var storage: [3]canvas.Command = undefined;
    const output = try canvas.project(
        .{ .width = 16, .height = 10 },
        source,
        &inputs,
        &storage,
    );
    try std.testing.expectEqual(@as(usize, 3), output.len);
    try std.testing.expectEqualDeep(
        canvas.Rect{ .x = 2, .y = 1, .width = 12, .height = 8 },
        output[0].solid.rect,
    );
    try std.testing.expectEqualDeep(
        canvas.Rect{ .x = 4, .y = 2, .width = 8, .height = 4 },
        output[1].alpha_mask.clip,
    );
    try std.testing.expectEqual(source, output[1].alpha_mask.resource.resource.key.source);
    try std.testing.expectEqual(local(7, 3).resource, output[1].alpha_mask.resource.resource.key.resource);
    try std.testing.expectEqual(local(7, 3).generation, output[1].alpha_mask.resource.resource.generation);
    try std.testing.expectEqualDeep(
        canvas.Rect{ .x = 14, .y = 8, .width = 2, .height = 2 },
        output[2].rgba.clip,
    );
    try std.testing.expectEqual(source, output[2].rgba.resource.resource.key.source);
}

test "fully clipped valid facts consume no output" {
    const inputs = [_]canvas.Input{.{ .solid = .{
        .rect = .{ .x = -10, .y = -10, .width = 2, .height = 2 },
        .clip = .{ .x = 0, .y = 0, .width = 4, .height = 4 },
        .color = red,
    } }};
    var storage: [1]canvas.Command = undefined;
    const output = try canvas.project(
        .{ .width = 4, .height = 4 },
        source,
        &inputs,
        &storage,
    );
    try std.testing.expectEqual(@as(usize, 0), output.len);
}

test "identity format extent geometry and capacity failures preserve output" {
    var storage: [2]canvas.Command = undefined;
    @memset(std.mem.asBytes(&storage), 0xa5);
    const before = std.mem.asBytes(&storage).*;
    const valid = canvas.Input{ .solid = .{
        .rect = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .clip = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .color = red,
    } };

    try std.testing.expectError(
        error.InvalidIdentity,
        canvas.project(
            .{ .width = 1, .height = 1 },
            @fromBackingInt(@intCast(0)),
            &.{valid},
            &storage,
        ),
    );
    try std.testing.expectEqualSlices(u8, &before, std.mem.asBytes(&storage));

    const invalid_generation = canvas.Input{ .alpha_mask = .{
        .destination = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .clip = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .resource = .{
            .resource = local(1, 0),
            .format = .alpha8,
            .size = .{ .width = 1, .height = 1 },
        },
        .color = white,
    } };
    try std.testing.expectError(
        error.InvalidGeneration,
        canvas.project(.{ .width = 1, .height = 1 }, source, &.{invalid_generation}, &storage),
    );
    try std.testing.expectEqualSlices(u8, &before, std.mem.asBytes(&storage));

    var mismatch = invalid_generation;
    mismatch.alpha_mask.resource.resource = local(1, 1);
    mismatch.alpha_mask.resource.format = .rgba8;
    try std.testing.expectError(
        error.FormatMismatch,
        canvas.project(.{ .width = 1, .height = 1 }, source, &.{mismatch}, &storage),
    );
    try std.testing.expectEqualSlices(u8, &before, std.mem.asBytes(&storage));

    mismatch.alpha_mask.resource.format = .alpha8;
    mismatch.alpha_mask.resource.source = .{ .x = 1, .y = 0, .width = 1, .height = 1 };
    try std.testing.expectError(
        error.ExtentMismatch,
        canvas.project(.{ .width = 1, .height = 1 }, source, &.{mismatch}, &storage),
    );
    try std.testing.expectEqualSlices(u8, &before, std.mem.asBytes(&storage));

    const malformed = canvas.Input{ .solid = .{
        .rect = .{ .x = 0, .y = 0, .width = 0, .height = 1 },
        .clip = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .color = red,
    } };
    try std.testing.expectError(
        error.InvalidRectangle,
        canvas.project(.{ .width = 1, .height = 1 }, source, &.{ malformed, valid }, &storage),
    );
    try std.testing.expectEqualSlices(u8, &before, std.mem.asBytes(&storage));

    try std.testing.expectError(
        error.InsufficientCommands,
        canvas.project(.{ .width = 1, .height = 1 }, source, &.{ valid, valid, valid }, &storage),
    );
    try std.testing.expectEqualSlices(u8, &before, std.mem.asBytes(&storage));
}

fn aliasInput(bytes: []u8, offset: usize) []canvas.Input {
    return @ptrCast(@alignCast(
        bytes[offset .. offset + @sizeOf(canvas.Input)],
    ));
}

fn aliasCommands(bytes: []u8, offset: usize) []canvas.Command {
    return @ptrCast(@alignCast(
        bytes[offset .. offset + @sizeOf(canvas.Command)],
    ));
}

fn setAliasInput(inputs: []canvas.Input) void {
    inputs[0] = .{ .solid = .{
        .rect = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .clip = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .color = red,
    } };
}

fn expectAliasRejected(input_offset: usize, command_offset: usize) !void {
    var words: [64]usize = @splat(0x5a5a5a5a5a5a5a5a);
    const bytes = std.mem.sliceAsBytes(&words);
    const inputs = aliasInput(bytes, input_offset);
    setAliasInput(inputs);
    const commands = aliasCommands(bytes, command_offset);
    const before = words;
    try std.testing.expectError(
        error.AliasedStorage,
        canvas.project(.{ .width = 1, .height = 1 }, source, inputs, commands),
    );
    try std.testing.expectEqualDeep(before, words);
}

test "input and output alias matrix is exact and transactional" {
    comptime {
        if (@alignOf(canvas.Input) > @alignOf(usize) or
            @alignOf(canvas.Command) > @alignOf(usize))
            @compileError("alias proof backing alignment is insufficient");
        if (@sizeOf(canvas.Input) % @alignOf(canvas.Command) != 0 or
            @sizeOf(canvas.Command) % @alignOf(canvas.Input) != 0)
            @compileError("alias proof adjacency requires naturally aligned sizes");
    }

    try expectAliasRejected(0, 0);
    try expectAliasRejected(0, @alignOf(usize));
    try expectAliasRejected(@alignOf(usize), 0);

    var adjacent_words: [64]usize = @splat(0);
    const adjacent_bytes = std.mem.sliceAsBytes(&adjacent_words);
    const adjacent_input = aliasInput(adjacent_bytes, 0);
    setAliasInput(adjacent_input);
    const adjacent_commands = aliasCommands(
        adjacent_bytes,
        @sizeOf(canvas.Input),
    );
    const adjacent = try canvas.project(
        .{ .width = 1, .height = 1 },
        source,
        adjacent_input,
        adjacent_commands,
    );
    try std.testing.expectEqual(@as(usize, 1), adjacent.len);

    var disjoint_words: [64]usize = @splat(0);
    const disjoint_bytes = std.mem.sliceAsBytes(&disjoint_words);
    const disjoint_input = aliasInput(disjoint_bytes, 0);
    setAliasInput(disjoint_input);
    const disjoint_commands = aliasCommands(
        disjoint_bytes,
        @sizeOf(canvas.Input) + @alignOf(usize),
    );
    const disjoint = try canvas.project(
        .{ .width = 1, .height = 1 },
        source,
        disjoint_input,
        disjoint_commands,
    );
    try std.testing.expectEqual(@as(usize, 1), disjoint.len);
}

test "upload pixels remain producer-owned and are not copied per draw" {
    var pixels = [_]u8{ 1, 2, 3, 4 };
    const upload = canvas.ResourceUpload{
        .resource = local(2, 4),
        .format = .rgba8,
        .pixels = .{
            .bytes = &pixels,
            .width = 1,
            .height = 1,
            .stride = 4,
        },
    };
    const input = canvas.Input{ .rgba = .{
        .destination = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .clip = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .resource = .{
            .resource = upload.resource,
            .format = upload.format,
            .size = .{ .width = upload.pixels.width, .height = upload.pixels.height },
        },
    } };
    var commands: [1]canvas.Command = undefined;
    const projected = try canvas.project(
        .{ .width = 1, .height = 1 },
        source,
        &.{input},
        &commands,
    );
    try std.testing.expectEqual(@as(usize, 1), projected.len);
    pixels[0] = 9;
    try std.testing.expectEqual(@as(u8, 9), upload.pixels.bytes[0]);
    try std.testing.expectEqual(
        upload.resource.resource,
        commands[0].rgba.resource.resource.key.resource,
    );
    try std.testing.expectEqual(
        upload.resource.generation,
        commands[0].rgba.resource.resource.generation,
    );
}

fn composerLimits() canvas.Composer.Limits {
    return .{
        .sources = 4,
        .retained_resources = 8,
        .retained_commands = 16,
        .retained_pixel_bytes = 64,
        .composition_sources = 4,
        .candidate_resources = 8,
        .candidate_commands = 16,
        .candidate_pixel_bytes = 64,
    };
}

const FrameStorage = struct {
    uploads: [8]canvas.ResourceUploadFact = undefined,
    removals: [8]canvas.FrameResourceRef = undefined,
    commands: [16]canvas.Command = undefined,
    pixels: [64]u8 = undefined,

    fn buffers(self: *FrameStorage) canvas.Composer.FrameBuffers {
        return .{
            .uploads = &self.uploads,
            .removals = &self.removals,
            .commands = &self.commands,
            .pixels = &self.pixels,
        };
    }
};

fn solidInput(color: canvas.Color) canvas.Input {
    return .{ .solid = .{
        .rect = .{ .x = 0, .y = 0, .width = 4, .height = 3 },
        .clip = .{ .x = 0, .y = 0, .width = 4, .height = 3 },
        .color = color,
    } };
}

fn placement(source_id: canvas.SourceId, x: i32) canvas.Composer.Placement {
    return .{
        .source = source_id,
        .origin = .{ .x = x, .y = 1 },
        .clip = .{ .x = 0, .y = 0, .width = 16, .height = 8 },
    };
}

test "composer separates producer and visible frame revisions" {
    var composer = try canvas.Composer.init(
        std.testing.allocator,
        composerLimits(),
    );
    defer composer.deinit();
    const first = try composer.registerSource();
    const second = try composer.registerSource();
    var frame_storage: FrameStorage = .{};
    const empty = try composer.frame(&.{}, frame_storage.buffers());
    try std.testing.expectEqual(@as(u64, 1), @backingInt(empty.revision));
    try std.testing.expectEqual(@as(usize, 0), empty.commands.len);

    const red_input = solidInput(red);
    try composer.apply(first, .{
        .revision = @fromBackingInt(@intCast(1)),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{red_input},
    });
    const hidden = try composer.frame(&.{}, frame_storage.buffers());
    try std.testing.expectEqual(@as(u64, 1), @backingInt(hidden.revision));
    try std.testing.expectEqual(@as(usize, 0), hidden.commands.len);

    const first_only = [_]canvas.Composer.Placement{placement(first, 2)};
    try composer.setComposition(.{
        .surface = .{ .width = 16, .height = 8 },
        .sources = &first_only,
    });
    const revealed = try composer.frame(&.{}, frame_storage.buffers());
    try std.testing.expectEqual(@as(u64, 2), @backingInt(revealed.revision));
    try std.testing.expectEqual(@as(usize, 1), revealed.commands.len);
    try std.testing.expectEqualDeep(
        canvas.Rect{ .x = 2, .y = 1, .width = 4, .height = 3 },
        revealed.commands[0].solid.rect,
    );
    try composer.apply(first, .{
        .revision = @fromBackingInt(@intCast(2)),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{red_input},
    });
    const byte_identical = try composer.frame(&.{}, frame_storage.buffers());
    try std.testing.expectEqual(
        @backingInt(revealed.revision),
        @backingInt(byte_identical.revision),
    );
    try std.testing.expectError(
        error.InvalidRevision,
        composer.apply(first, .{
            .revision = @fromBackingInt(@intCast(2)),
            .uploads = &.{},
            .removals = &.{},
            .commands = &.{red_input},
        }),
    );

    try composer.setComposition(.{
        .surface = .{ .width = 16, .height = 8 },
        .sources = &first_only,
    });
    const unchanged = try composer.frame(&.{}, frame_storage.buffers());
    try std.testing.expectEqual(@as(u64, 2), @backingInt(unchanged.revision));

    const white_input = solidInput(white);
    try composer.apply(second, .{
        .revision = @fromBackingInt(@intCast(9)),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{white_input},
    });
    const blue = canvas.Color{ .r = 0, .g = 0, .b = 255, .a = 255 };
    const newest_hidden_input = solidInput(blue);
    try composer.apply(second, .{
        .revision = @fromBackingInt(@intCast(10)),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{newest_hidden_input},
    });
    const still_hidden = try composer.frame(&.{}, frame_storage.buffers());
    try std.testing.expectEqual(@as(u64, 2), @backingInt(still_hidden.revision));

    const both = [_]canvas.Composer.Placement{
        placement(first, 2),
        placement(second, 8),
    };
    try composer.setComposition(.{
        .surface = .{ .width = 16, .height = 8 },
        .sources = &both,
    });
    const ordered = try composer.frame(&.{}, frame_storage.buffers());
    try std.testing.expectEqual(@as(u64, 3), @backingInt(ordered.revision));
    try std.testing.expectEqual(@as(usize, 2), ordered.commands.len);
    try std.testing.expectEqualDeep(red, ordered.commands[0].solid.color);
    try std.testing.expectEqualDeep(blue, ordered.commands[1].solid.color);

    try std.testing.expectError(
        error.InvalidRevision,
        composer.apply(first, .{
            .revision = @fromBackingInt(@intCast(1)),
            .uploads = &.{},
            .removals = &.{},
            .commands = &.{red_input},
        }),
    );
    const after_stale = try composer.frame(&.{}, frame_storage.buffers());
    try std.testing.expectEqual(@as(u64, 3), @backingInt(after_stale.revision));
    try std.testing.expectEqualDeep(ordered.commands, after_stale.commands);
}

test "composer retains resources and derives partial and full recovery" {
    var composer = try canvas.Composer.init(
        std.testing.allocator,
        composerLimits(),
    );
    defer composer.deinit();
    const producer = try composer.registerSource();
    const pixels = [_]u8{ 1, 2, 3, 4 };
    const resource = local(3, 1);
    const upload = canvas.ResourceUpload{
        .resource = resource,
        .format = .rgba8,
        .pixels = .{
            .bytes = &pixels,
            .width = 1,
            .height = 1,
            .stride = 4,
        },
    };
    const draw = canvas.Input{ .rgba = .{
        .destination = .{ .x = 0, .y = 0, .width = 2, .height = 2 },
        .clip = .{ .x = 0, .y = 0, .width = 2, .height = 2 },
        .resource = .{
            .resource = resource,
            .format = .rgba8,
            .size = .{ .width = 1, .height = 1 },
        },
    } };
    try composer.apply(producer, .{
        .revision = @fromBackingInt(@intCast(1)),
        .uploads = &.{upload},
        .removals = &.{},
        .commands = &.{draw},
    });
    const visible = [_]canvas.Composer.Placement{placement(producer, 0)};
    try composer.setComposition(.{
        .surface = .{ .width = 8, .height = 8 },
        .sources = &visible,
    });
    var storage: FrameStorage = .{};
    const recovery = try composer.frame(&.{}, storage.buffers());
    try std.testing.expectEqual(@as(usize, 1), recovery.uploads.len);
    try std.testing.expectEqualSlices(u8, &pixels, recovery.pixels);
    try std.testing.expectEqual(producer, recovery.uploads[0].resource.key.source);

    var limited: FrameStorage = .{};
    @memset(std.mem.asBytes(&limited), 0xa5);
    const limited_before = std.mem.asBytes(&limited).*;
    try std.testing.expectError(
        error.PixelLimit,
        composer.frame(&.{}, .{
            .uploads = &limited.uploads,
            .removals = &limited.removals,
            .commands = &limited.commands,
            .pixels = limited.pixels[0..3],
        }),
    );
    try std.testing.expectEqualSlices(
        u8,
        &limited_before,
        std.mem.asBytes(&limited),
    );

    const resident = canvas.Residency{
        .resource = recovery.uploads[0].resource,
        .format = recovery.uploads[0].format,
        .size = recovery.uploads[0].size,
    };
    const complete = try composer.frame(&.{resident}, storage.buffers());
    try std.testing.expectEqual(@as(usize, 0), complete.uploads.len);
    try std.testing.expectEqual(@as(usize, 0), complete.removals.len);
    try std.testing.expectEqual(@as(usize, 1), complete.commands.len);
    try std.testing.expectEqual(recovery.revision, complete.revision);

    const replacement_pixels = [_]u8{ 5, 6, 7, 8 };
    const replacement = canvas.ResourceUpload{
        .resource = local(3, 4),
        .format = .rgba8,
        .pixels = .{
            .bytes = &replacement_pixels,
            .width = 1,
            .height = 1,
            .stride = 4,
        },
    };
    var replacement_draw = draw;
    replacement_draw.rgba.resource.resource = replacement.resource;
    try composer.apply(producer, .{
        .revision = @fromBackingInt(@intCast(2)),
        .uploads = &.{replacement},
        .removals = &.{},
        .commands = &.{replacement_draw},
    });
    const replaced = try composer.frame(&.{resident}, storage.buffers());
    try std.testing.expectEqual(@as(usize, 1), replaced.uploads.len);
    try std.testing.expectEqual(@as(usize, 0), replaced.removals.len);
    try std.testing.expectEqual(
        replacement.resource.generation,
        replaced.uploads[0].resource.generation,
    );
    try std.testing.expectEqualSlices(u8, &replacement_pixels, replaced.pixels);
    const replacement_residency = canvas.Residency{
        .resource = replaced.uploads[0].resource,
        .format = replaced.uploads[0].format,
        .size = replaced.uploads[0].size,
    };

    try std.testing.expectError(
        error.InvalidIdentity,
        composer.apply(producer, .{
            .revision = @fromBackingInt(@intCast(3)),
            .uploads = &.{canvas.ResourceUpload{
                .resource = local(2, 1),
                .format = .rgba8,
                .pixels = replacement.pixels,
            }},
            .removals = &.{},
            .commands = &.{},
        }),
    );
    const preserved = try composer.frame(&.{resident}, storage.buffers());
    try std.testing.expectEqual(
        replacement.resource.generation,
        preserved.uploads[0].resource.generation,
    );

    try std.testing.expectError(
        error.ReferencedRemoval,
        composer.apply(producer, .{
            .revision = @fromBackingInt(@intCast(3)),
            .uploads = &.{},
            .removals = &.{canvas.ResourceRemoval{ .resource = replacement.resource }},
            .commands = &.{replacement_draw},
        }),
    );
    try composer.apply(producer, .{
        .revision = @fromBackingInt(@intCast(3)),
        .uploads = &.{},
        .removals = &.{canvas.ResourceRemoval{ .resource = replacement.resource }},
        .commands = &.{},
    });
    const removed = try composer.frame(
        &.{replacement_residency},
        storage.buffers(),
    );
    try std.testing.expectEqual(@as(usize, 0), removed.uploads.len);
    try std.testing.expectEqual(@as(usize, 1), removed.removals.len);
    try std.testing.expectEqualDeep(
        replacement_residency.resource,
        removed.removals[0],
    );
    try std.testing.expectError(
        error.InvalidIdentity,
        composer.apply(producer, .{
            .revision = @fromBackingInt(@intCast(4)),
            .uploads = &.{replacement},
            .removals = &.{},
            .commands = &.{replacement_draw},
        }),
    );
}

test "composer advances frames only for changed visible contributions" {
    var composer = try canvas.Composer.init(
        std.testing.allocator,
        composerLimits(),
    );
    defer composer.deinit();
    const producer = try composer.registerSource();
    const clipped_a = canvas.Input{ .solid = .{
        .rect = .{ .x = 40, .y = 40, .width = 2, .height = 2 },
        .clip = .{ .x = 40, .y = 40, .width = 2, .height = 2 },
        .color = red,
    } };
    try composer.apply(producer, .{
        .revision = @fromBackingInt(@intCast(1)),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{clipped_a},
    });
    const visible = [_]canvas.Composer.Placement{placement(producer, 0)};
    try composer.setComposition(.{
        .surface = .{ .width = 8, .height = 8 },
        .sources = &visible,
    });
    var storage: FrameStorage = .{};
    const initial = try composer.frame(&.{}, storage.buffers());
    try std.testing.expectEqual(@as(u64, 2), @backingInt(initial.revision));
    try std.testing.expectEqual(@as(usize, 0), initial.commands.len);

    const clipped_b = canvas.Input{ .solid = .{
        .rect = .{ .x = 60, .y = 60, .width = 3, .height = 3 },
        .clip = .{ .x = 60, .y = 60, .width = 3, .height = 3 },
        .color = white,
    } };
    try composer.apply(producer, .{
        .revision = @fromBackingInt(@intCast(2)),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{clipped_b},
    });
    const clipped_change = try composer.frame(&.{}, storage.buffers());
    try std.testing.expectEqual(
        @backingInt(initial.revision),
        @backingInt(clipped_change.revision),
    );

    const unused_pixels = [_]u8{7};
    try composer.apply(producer, .{
        .revision = @fromBackingInt(@intCast(3)),
        .uploads = &.{canvas.ResourceUpload{
            .resource = local(5, 1),
            .format = .alpha8,
            .pixels = .{
                .bytes = &unused_pixels,
                .width = 1,
                .height = 1,
                .stride = 1,
            },
        }},
        .removals = &.{},
        .commands = &.{clipped_b},
    });
    const unused_change = try composer.frame(&.{}, storage.buffers());
    try std.testing.expectEqual(
        @backingInt(initial.revision),
        @backingInt(unused_change.revision),
    );
    try std.testing.expectEqual(@as(usize, 0), unused_change.uploads.len);

    const visible_solid = solidInput(red);
    try composer.apply(producer, .{
        .revision = @fromBackingInt(@intCast(4)),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{visible_solid},
    });
    const command_change = try composer.frame(&.{}, storage.buffers());
    try std.testing.expectEqual(
        @backingInt(initial.revision) + 1,
        @backingInt(command_change.revision),
    );

    const visible_mask = canvas.Input{ .alpha_mask = .{
        .destination = .{ .x = 0, .y = 0, .width = 2, .height = 2 },
        .clip = .{ .x = 0, .y = 0, .width = 2, .height = 2 },
        .resource = .{
            .resource = local(5, 1),
            .format = .alpha8,
            .size = .{ .width = 1, .height = 1 },
        },
        .color = white,
    } };
    try composer.apply(producer, .{
        .revision = @fromBackingInt(@intCast(5)),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{visible_mask},
    });
    const resource_change = try composer.frame(&.{}, storage.buffers());
    try std.testing.expectEqual(
        @backingInt(command_change.revision) + 1,
        @backingInt(resource_change.revision),
    );
    try std.testing.expectEqual(@as(usize, 1), resource_change.uploads.len);
}

test "composer source retirement and frame capacity are transactional" {
    var composer = try canvas.Composer.init(
        std.testing.allocator,
        composerLimits(),
    );
    defer composer.deinit();
    const hidden = try composer.registerSource();
    const visible = try composer.registerSource();
    const input = solidInput(red);
    try composer.apply(hidden, .{
        .revision = @fromBackingInt(@intCast(1)),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{input},
    });
    try composer.apply(visible, .{
        .revision = @fromBackingInt(@intCast(1)),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{ input, input },
    });
    const order = [_]canvas.Composer.Placement{placement(visible, 0)};
    try composer.setComposition(.{
        .surface = .{ .width = 8, .height = 8 },
        .sources = &order,
    });
    var storage: FrameStorage = .{};
    const before = try composer.frame(&.{}, storage.buffers());
    const revision = @backingInt(before.revision);

    var short_commands: [1]canvas.Command = undefined;
    @memset(std.mem.asBytes(&short_commands), 0xa5);
    const short_before = std.mem.asBytes(&short_commands).*;
    try std.testing.expectError(
        error.CommandLimit,
        composer.frame(&.{}, .{
            .uploads = &storage.uploads,
            .removals = &storage.removals,
            .commands = &short_commands,
            .pixels = &storage.pixels,
        }),
    );
    try std.testing.expectEqualSlices(
        u8,
        &short_before,
        std.mem.asBytes(&short_commands),
    );

    try composer.removeSource(hidden);
    const after_hidden = try composer.frame(&.{}, storage.buffers());
    try std.testing.expectEqual(revision, @backingInt(after_hidden.revision));
    try std.testing.expectError(error.RetiredSource, composer.apply(hidden, .{
        .revision = @fromBackingInt(@intCast(2)),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{},
    }));
    try composer.removeSource(visible);
    const after_visible = try composer.frame(&.{}, storage.buffers());
    try std.testing.expectEqual(revision + 1, @backingInt(after_visible.revision));
    try std.testing.expectEqual(@as(usize, 0), after_visible.commands.len);
    const next = try composer.registerSource();
    try std.testing.expect(@backingInt(next) > @backingInt(visible));
}

test "composer rejects same-update conflicts and frame aliases transactionally" {
    var composer = try canvas.Composer.init(
        std.testing.allocator,
        composerLimits(),
    );
    defer composer.deinit();
    const producer = try composer.registerSource();
    const pixels = [_]u8{255};
    const upload = canvas.ResourceUpload{
        .resource = local(1, 1),
        .format = .alpha8,
        .pixels = .{
            .bytes = &pixels,
            .width = 1,
            .height = 1,
            .stride = 1,
        },
    };
    try std.testing.expectError(
        error.ConflictingResourceOperation,
        composer.apply(producer, .{
            .revision = @fromBackingInt(@intCast(1)),
            .uploads = &.{upload},
            .removals = &.{canvas.ResourceRemoval{ .resource = upload.resource }},
            .commands = &.{},
        }),
    );
    const skipped = [_]canvas.ResourceUpload{
        .{
            .resource = local(7, 1),
            .format = .alpha8,
            .pixels = upload.pixels,
        },
        .{
            .resource = local(5, 1),
            .format = .alpha8,
            .pixels = upload.pixels,
        },
    };
    try composer.apply(producer, .{
        .revision = @fromBackingInt(@intCast(1)),
        .uploads = &skipped,
        .removals = &.{},
        .commands = &.{},
    });
    try std.testing.expectError(
        error.InvalidIdentity,
        composer.apply(producer, .{
            .revision = @fromBackingInt(@intCast(2)),
            .uploads = &.{canvas.ResourceUpload{
                .resource = local(6, 1),
                .format = .alpha8,
                .pixels = upload.pixels,
            }},
            .removals = &.{},
            .commands = &.{},
        }),
    );
    const input = solidInput(red);
    try composer.apply(producer, .{
        .revision = @fromBackingInt(@intCast(2)),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{input},
    });
    const visible = [_]canvas.Composer.Placement{placement(producer, 0)};
    try composer.setComposition(.{
        .surface = .{ .width = 8, .height = 8 },
        .sources = &visible,
    });

    comptime {
        if (@alignOf(canvas.Command) > @alignOf(u64))
            @compileError("composer alias proof backing alignment is insufficient");
    }
    var backing: [64]u64 = @splat(0x5a5a5a5a5a5a5a5a);
    const before = backing;
    const bytes = std.mem.sliceAsBytes(&backing);
    const commands: []canvas.Command = @ptrCast(@alignCast(
        bytes[0..@sizeOf(canvas.Command)],
    ));
    var storage: FrameStorage = .{};
    try std.testing.expectError(
        error.AliasedStorage,
        composer.frame(&.{}, .{
            .uploads = &storage.uploads,
            .removals = &storage.removals,
            .commands = commands,
            .pixels = bytes[0..1],
        }),
    );
    try std.testing.expectEqualDeep(before, backing);
}

fn constructComposer(allocator: std.mem.Allocator) !void {
    var composer = try canvas.Composer.init(allocator, composerLimits());
    composer.deinit();
}

test "composer initialization releases every staged allocation" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        constructComposer,
        .{},
    );
}
