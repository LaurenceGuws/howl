const std = @import("std");
const canvas = @import("howl_render").canvas;

const red = canvas.Color{ .r = 255, .g = 0, .b = 0, .a = 255 };
const white = canvas.Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
const source: canvas.SourceId = @fromBackingInt(@intCast(11));

fn local(id: u64, generation: u64) !canvas.ResourceRef {
    return .{
        .resource = try canvas.ResourceId.local(id),
        .generation = @fromBackingInt(@intCast(generation)),
    };
}

fn shared(id: u64, generation: u64) !canvas.ResourceRef {
    return .{
        .resource = try canvas.ResourceId.shared(id),
        .generation = @fromBackingInt(@intCast(generation)),
    };
}

fn sharedAlphaCommand(
    resource: canvas.ResourceRef,
    width: u16,
    height: u16,
) canvas.Input {
    return .{ .alpha_mask = .{
        .destination = .{
            .x = 0,
            .y = 0,
            .width = width,
            .height = height,
        },
        .clip = .{
            .x = 0,
            .y = 0,
            .width = width,
            .height = height,
        },
        .resource = .{
            .resource = resource,
            .format = .alpha8,
            .size = .{ .width = width, .height = height },
        },
        .color = white,
    } };
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
                .resource = try local(7, 3),
                .format = .alpha8,
                .size = .{ .width = 4, .height = 2 },
            },
            .color = white,
        } },
        .{ .rgba = .{
            .destination = .{ .x = 14, .y = 8, .width = 4, .height = 4 },
            .clip = .{ .x = 0, .y = 0, .width = 16, .height = 10 },
            .resource = .{
                .resource = try local(9, 5),
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
    try std.testing.expectEqual(source, output[1].alpha_mask.resource.resource.source);
    try std.testing.expectEqual((try local(7, 3)).resource, output[1].alpha_mask.resource.resource.resource);
    try std.testing.expectEqual((try local(7, 3)).generation, output[1].alpha_mask.resource.resource.generation);
    try std.testing.expectEqualDeep(
        canvas.Rect{ .x = 14, .y = 8, .width = 2, .height = 2 },
        output[2].rgba.clip,
    );
    try std.testing.expectEqual(source, output[2].rgba.resource.resource.source);
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
            .resource = try local(1, 0),
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
    mismatch.alpha_mask.resource.resource = try local(1, 1);
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
        .resource = try local(2, 4),
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
        commands[0].rgba.resource.resource.resource,
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

fn alphaInput(resource: canvas.ResourceRef, color: canvas.Color) canvas.Input {
    return .{ .alpha_mask = .{
        .destination = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .clip = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .resource = .{
            .resource = resource,
            .format = .alpha8,
            .size = .{ .width = 1, .height = 1 },
        },
        .color = color,
    } };
}

fn resourceInput(resource: canvas.ResourceRef, width: u16) canvas.Input {
    return .{ .alpha_mask = .{
        .destination = .{ .x = 0, .y = 0, .width = width, .height = 1 },
        .clip = .{ .x = 0, .y = 0, .width = width, .height = 1 },
        .resource = .{
            .resource = resource,
            .format = .alpha8,
            .size = .{ .width = width, .height = 1 },
        },
        .color = white,
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

test "cursor-free source binds one overlay exactly and rejects stale identity" {
    var composer = try canvas.Composer.init(
        std.testing.allocator,
        composerLimits(),
    );
    defer composer.deinit();
    const producer = try composer.registerSource();
    const other = try composer.registerSource();
    const base = solidInput(red);
    const binding = canvas.CursorBinding{
        .pane = 7,
        .source = producer,
        .terminal_sequence = 11,
        .cursor_revision = 13,
        .visible_set_revision = 17,
        .lifecycle_revision = 19,
        .rect = .{ .x = 0, .y = 0, .width = 4, .height = 3 },
        .clip = .{ .x = 0, .y = 0, .width = 16, .height = 8 },
        .visible = true,
    };
    try composer.apply(producer, .{
        .revision = @fromBackingInt(@intCast(1)),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{base},
        .cursor_binding = binding,
    });
    try composer.setComposition(.{
        .surface = .{ .width = 16, .height = 8 },
        .sources = &.{placement(producer, 2)},
        .focused_source = producer,
    });
    var storage: FrameStorage = .{};
    const first = try composer.frame(&.{}, storage.buffers());
    try std.testing.expectEqual(@as(usize, 2), first.commands.len);
    try std.testing.expectEqualDeep(red, first.commands[0].solid.color);
    try std.testing.expectEqualDeep(binding.color, first.commands[1].solid.color);
    const accepted = composer.cursorBinding(producer) orelse
        return error.MissingCursorBinding;
    try std.testing.expectEqual(@as(u64, 7), accepted.pane);
    try std.testing.expectEqual(@as(u64, 2), accepted.frame_revision);

    var stale = binding;
    stale.source = other;
    try std.testing.expectError(
        error.InvalidIdentity,
        composer.apply(producer, .{
            .revision = @fromBackingInt(@intCast(2)),
            .uploads = &.{},
            .removals = &.{},
            .commands = &.{base},
            .cursor_binding = stale,
        }),
    );
    const after = try composer.frame(&.{}, storage.buffers());
    try std.testing.expectEqual(@as(usize, 2), after.commands.len);
    try std.testing.expectEqualDeep(first.commands, after.commands);
    try std.testing.expectEqualDeep(accepted, composer.cursorBinding(producer).?);

    const second_binding = canvas.CursorBinding{
        .pane = 8,
        .source = other,
        .terminal_sequence = 23,
        .cursor_revision = 29,
        .visible_set_revision = 31,
        .lifecycle_revision = 37,
        .rect = .{ .x = 8, .y = 0, .width = 4, .height = 3 },
        .clip = .{ .x = 0, .y = 0, .width = 16, .height = 8 },
        .visible = true,
    };
    try composer.apply(other, .{
        .revision = @fromBackingInt(@intCast(1)),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{base},
        .cursor_binding = second_binding,
    });
    const both = [_]canvas.Composer.Placement{
        placement(producer, 2),
        placement(other, 2),
    };
    try composer.setComposition(.{
        .surface = .{ .width = 16, .height = 8 },
        .sources = &both,
        .focused_source = producer,
    });
    const focused_first = try composer.frame(&.{}, storage.buffers());
    try std.testing.expectEqual(@as(usize, 3), focused_first.commands.len);
    try std.testing.expectEqualDeep(red, focused_first.commands[0].solid.color);
    try std.testing.expectEqualDeep(binding.color, focused_first.commands[1].solid.color);
    try std.testing.expectEqualDeep(red, focused_first.commands[2].solid.color);
    try composer.setComposition(.{
        .surface = .{ .width = 16, .height = 8 },
        .sources = &both,
        .focused_source = other,
    });
    const focused_second = try composer.frame(&.{}, storage.buffers());
    try std.testing.expectEqual(@as(usize, 3), focused_second.commands.len);
    try std.testing.expectEqualDeep(red, focused_second.commands[0].solid.color);
    try std.testing.expectEqualDeep(red, focused_second.commands[1].solid.color);
    try std.testing.expectEqualDeep(second_binding.color, focused_second.commands[2].solid.color);

    const accepted_after_focus = composer.cursorBinding(producer).?;
    stale = binding;
    stale.frame_revision = accepted_after_focus.frame_revision;
    try std.testing.expectError(
        error.InvalidIdentity,
        composer.apply(producer, .{
            .revision = @fromBackingInt(@intCast(2)),
            .uploads = &.{},
            .removals = &.{},
            .commands = &.{base},
            .cursor_binding = stale,
        }),
    );
    try std.testing.expectEqualDeep(accepted_after_focus, composer.cursorBinding(producer).?);

    // A topology/focus candidate can carry a newer visible-set identity
    // without rebuilding either source. Composer must rebind every retained
    // visible target atomically, while preserving the complete frame and its
    // producer revisions.
    const before_rebind = try composer.frame(&.{}, storage.buffers());
    try composer.applyCandidate(.{
        .changes = &.{},
        .cursor_visible_set_revision = 41,
        .composition = .{
            .surface = .{ .width = 16, .height = 8 },
            .sources = &both,
            .focused_source = other,
        },
    });
    const after_rebind = try composer.frame(&.{}, storage.buffers());
    try std.testing.expectEqual(before_rebind.revision, after_rebind.revision);
    try std.testing.expectEqualDeep(before_rebind.commands, after_rebind.commands);
    try std.testing.expectEqual(@as(u64, 41), composer.cursorBinding(producer).?.visible_set_revision);
    try std.testing.expectEqual(@as(u64, 41), composer.cursorBinding(other).?.visible_set_revision);
}

test "composer retains resources and derives partial and full recovery" {
    var composer = try canvas.Composer.init(
        std.testing.allocator,
        composerLimits(),
    );
    defer composer.deinit();
    const producer = try composer.registerSource();
    const pixels = [_]u8{ 1, 2, 3, 4 };
    const resource = try local(3, 1);
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
    try std.testing.expectEqual(producer, recovery.uploads[0].resource.source);

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
        .resource = try local(3, 4),
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
                .resource = try local(2, 1),
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
            .resource = try local(5, 1),
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
            .resource = try local(5, 1),
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
        .resource = try local(1, 1),
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
            .resource = try local(7, 1),
            .format = .alpha8,
            .pixels = upload.pixels,
        },
        .{
            .resource = try local(5, 1),
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
                .resource = try local(6, 1),
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

test "composer reuses retired physical source slots with fresh identities" {
    var composer = try canvas.Composer.init(std.testing.allocator, .{
        .sources = 2,
        .retained_resources = 1,
        .retained_commands = 1,
        .retained_pixel_bytes = 1,
        .composition_sources = 2,
        .candidate_resources = 1,
        .candidate_commands = 1,
        .candidate_pixel_bytes = 1,
    });
    defer composer.deinit();

    const retained = try composer.registerSource();
    var previous: ?canvas.SourceId = null;
    for (0..130) |_| {
        const candidate = try composer.registerSource();
        try std.testing.expect(candidate != retained);
        if (previous) |retired|
            try std.testing.expectError(error.RetiredSource, composer.removeSource(retired));
        try composer.removeSource(candidate);
        previous = candidate;
    }
    try composer.removeSource(retained);
    try std.testing.expectError(error.RetiredSource, composer.removeSource(previous.?));
}

test "composer atomic candidate commits seventeen sources once" {
    var composer = try canvas.Composer.init(std.testing.allocator, .{
        .sources = 17,
        .retained_resources = 34,
        .retained_commands = 34,
        .retained_pixel_bytes = 34,
        .composition_sources = 17,
        .candidate_resources = 2,
        .candidate_commands = 2,
        .candidate_pixel_bytes = 2,
    });
    defer composer.deinit();
    var sources: [17]canvas.SourceId = undefined;
    var old_commands: [34]canvas.Input = undefined;
    var new_commands: [34]canvas.Input = undefined;
    var changes: [17]canvas.Composer.SourceChange = undefined;
    var placements: [17]canvas.Composer.Placement = undefined;
    const shared_ref = try shared(1, 1);
    const shared_byte = [_]u8{0x6d};
    const shared_upload = canvas.ResourceUpload{
        .resource = shared_ref,
        .format = .alpha8,
        .pixels = .{
            .bytes = &shared_byte,
            .width = 1,
            .height = 1,
            .stride = 1,
        },
    };
    var old_offset: usize = 0;
    var new_offset: usize = 0;
    for (&sources, 0..) |*source_id, index| {
        source_id.* = try composer.registerSource();
        const old_count: usize = if (index % 2 == 0) 1 else 2;
        const new_count: usize = if (index % 2 == 0) 2 else 1;
        for (old_commands[old_offset..][0..old_count], 0..) |*command, item|
            command.* = solidInput(.{
                .r = @intCast(index),
                .g = @intCast(item),
                .b = 1,
                .a = 255,
            });
        try composer.apply(source_id.*, .{
            .revision = @fromBackingInt(1),
            .uploads = &.{},
            .removals = &.{},
            .commands = old_commands[old_offset..][0..old_count],
        });
        for (new_commands[new_offset..][0..new_count], 0..) |*command, item|
            command.* = solidInput(.{
                .r = @intCast(index),
                .g = @intCast(item),
                .b = 2,
                .a = 255,
            });
        if (index == 0)
            new_commands[new_offset] =
                sharedAlphaCommand(shared_ref, 1, 1);
        changes[index] = .{
            .source = source_id.*,
            .update = .{
                .revision = @fromBackingInt(2),
                .uploads = if (index == 0)
                    &.{shared_upload}
                else
                    &.{},
                .removals = &.{},
                .commands = new_commands[new_offset..][0..new_count],
            },
        };
        placements[index] = placement(source_id.*, 0);
        old_offset += old_count;
        new_offset += new_count;
    }
    try composer.setComposition(.{
        .surface = .{ .width = 80, .height = 16 },
        .sources = &placements,
    });
    var frame_uploads: [34]canvas.ResourceUploadFact = undefined;
    var frame_removals: [34]canvas.FrameResourceRef = undefined;
    var frame_commands: [34]canvas.Command = undefined;
    var frame_pixels: [34]u8 = undefined;
    const before = try composer.frame(&.{}, .{
        .uploads = &frame_uploads,
        .removals = &frame_removals,
        .commands = &frame_commands,
        .pixels = &frame_pixels,
    });
    try composer.applyCandidate(.{
        .changes = &changes,
        .composition = .{
            .surface = .{ .width = 80, .height = 16 },
            .sources = &placements,
        },
    });
    const after = try composer.frame(&.{}, .{
        .uploads = &frame_uploads,
        .removals = &frame_removals,
        .commands = &frame_commands,
        .pixels = &frame_pixels,
    });
    try std.testing.expectEqual(
        @backingInt(before.revision) + 1,
        @backingInt(after.revision),
    );
    try std.testing.expectEqual(new_offset, after.commands.len);
    var shared_commands: usize = 0;
    for (after.commands) |command| switch (command) {
        .solid => |solid| try std.testing.expectEqual(@as(u8, 2), solid.color.b),
        .alpha_mask => |alpha| {
            shared_commands += 1;
            try std.testing.expect(alpha.resource.resource.resource.isShared());
        },
        .rgba => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(@as(usize, 1), shared_commands);

    const revision = after.revision;
    try composer.applyCandidate(.{
        .changes = &.{},
        .composition = .{
            .surface = .{ .width = 80, .height = 16 },
            .sources = &placements,
        },
    });
    const no_op = try composer.frame(&.{}, .{
        .uploads = &frame_uploads,
        .removals = &frame_removals,
        .commands = &frame_commands,
        .pixels = &frame_pixels,
    });
    try std.testing.expectEqual(revision, no_op.revision);

    var unchanged_changes: [17]canvas.Composer.SourceChange = undefined;
    for (&unchanged_changes, 0..) |*change, index| {
        change.* = .{
            .source = sources[index],
            .update = .{
                .revision = @fromBackingInt(3),
                .uploads = &.{},
                .removals = &.{},
                .commands = changes[index].update.commands,
            },
        };
    }
    try composer.applyCandidate(.{
        .changes = &unchanged_changes,
        .composition = .{
            .surface = .{ .width = 80, .height = 16 },
            .sources = &placements,
        },
    });
    const unchanged = try composer.frame(&.{}, .{
        .uploads = &frame_uploads,
        .removals = &frame_removals,
        .commands = &frame_commands,
        .pixels = &frame_pixels,
    });
    try std.testing.expectEqual(revision, unchanged.revision);
}

test "composer hidden clears fund sixteen incoming sources and changed chrome" {
    var composer = try canvas.Composer.init(std.testing.allocator, .{
        .sources = 33,
        .retained_resources = 16,
        .retained_commands = 17,
        .retained_pixel_bytes = 16,
        .composition_sources = 17,
        .candidate_resources = 1,
        .candidate_commands = 1,
        .candidate_pixel_bytes = 1,
    });
    defer composer.deinit();
    var outgoing: [16]canvas.SourceId = undefined;
    var incoming: [16]canvas.SourceId = undefined;
    var outgoing_placements: [16]canvas.Composer.Placement = undefined;
    var incoming_placements: [17]canvas.Composer.Placement = undefined;
    var outgoing_uploads: [16]canvas.ResourceUpload = undefined;
    var incoming_uploads: [16]canvas.ResourceUpload = undefined;
    var outgoing_commands: [16]canvas.Input = undefined;
    var incoming_commands: [16]canvas.Input = undefined;
    var changes: [17]canvas.Composer.SourceChange = undefined;
    var pixels: [32]u8 = undefined;

    for (0..16) |index| {
        outgoing[index] = try composer.registerSource();
        incoming[index] = try composer.registerSource();
        const outgoing_ref = try local(1, 1);
        pixels[index] = @intCast(index + 1);
        outgoing_uploads[index] = .{
            .resource = outgoing_ref,
            .format = .alpha8,
            .pixels = .{
                .bytes = pixels[index..][0..1],
                .width = 1,
                .height = 1,
                .stride = 1,
            },
        };
        outgoing_commands[index] = sharedAlphaCommand(outgoing_ref, 1, 1);
        try composer.apply(outgoing[index], .{
            .revision = @fromBackingInt(1),
            .uploads = outgoing_uploads[index..][0..1],
            .removals = &.{},
            .commands = outgoing_commands[index..][0..1],
        });
        outgoing_placements[index] = placement(outgoing[index], 0);

        const incoming_ref = try local(1, 1);
        pixels[16 + index] = @intCast(0x80 + index);
        incoming_uploads[index] = .{
            .resource = incoming_ref,
            .format = .alpha8,
            .pixels = .{
                .bytes = pixels[16 + index ..][0..1],
                .width = 1,
                .height = 1,
                .stride = 1,
            },
        };
        incoming_commands[index] = sharedAlphaCommand(incoming_ref, 1, 1);
        changes[index] = .{
            .source = incoming[index],
            .update = .{
                .revision = @fromBackingInt(1),
                .uploads = incoming_uploads[index..][0..1],
                .removals = &.{},
                .commands = incoming_commands[index..][0..1],
            },
        };
        incoming_placements[index] = placement(incoming[index], 0);
    }
    try composer.setComposition(.{
        .surface = .{ .width = 1, .height = 1 },
        .sources = &outgoing_placements,
    });
    const chrome = try composer.registerSource();
    const chrome_command = solidInput(white);
    changes[16] = .{
        .source = chrome,
        .update = .{
            .revision = @fromBackingInt(1),
            .uploads = &.{},
            .removals = &.{},
            .commands = &.{chrome_command},
        },
    };
    incoming_placements[16] = placement(chrome, 0);

    var frame_uploads: [16]canvas.ResourceUploadFact = undefined;
    var frame_removals: [16]canvas.FrameResourceRef = undefined;
    var frame_commands: [17]canvas.Command = undefined;
    var frame_pixels: [16]u8 = undefined;
    const before = try composer.frame(&.{}, .{
        .uploads = &frame_uploads,
        .removals = &frame_removals,
        .commands = &frame_commands,
        .pixels = &frame_pixels,
    });
    try std.testing.expectError(error.ResourceLimit, composer.applyCandidate(.{
        .changes = &changes,
        .composition = .{
            .surface = .{ .width = 1, .height = 1 },
            .sources = &incoming_placements,
        },
    }));
    const rejected = try composer.frame(&.{}, .{
        .uploads = &frame_uploads,
        .removals = &frame_removals,
        .commands = &frame_commands,
        .pixels = &frame_pixels,
    });
    try std.testing.expectEqual(before.revision, rejected.revision);

    try composer.applyCandidate(.{
        .changes = &changes,
        .hidden_source_clears = &outgoing,
        .composition = .{
            .surface = .{ .width = 1, .height = 1 },
            .sources = &incoming_placements,
        },
    });
    const accepted = try composer.frame(&.{}, .{
        .uploads = &frame_uploads,
        .removals = &frame_removals,
        .commands = &frame_commands,
        .pixels = &frame_pixels,
    });
    try std.testing.expectEqual(
        @backingInt(before.revision) + 1,
        @backingInt(accepted.revision),
    );

    const reveal_command = solidInput(red);
    var reveal_placements = incoming_placements;
    reveal_placements[0] = placement(outgoing[0], 0);
    try composer.applyCandidate(.{
        .changes = &.{.{ .source = outgoing[0], .update = .{
            .revision = @fromBackingInt(2),
            .uploads = &.{},
            .removals = &.{},
            .commands = &.{reveal_command},
        } }},
        .hidden_source_clears = &.{incoming[0]},
        .composition = .{
            .surface = .{ .width = 1, .height = 1 },
            .sources = &reveal_placements,
        },
    });
}

test "composer hidden clear validation preserves retained frame and remains reusable" {
    var composer = try canvas.Composer.init(std.testing.allocator, .{
        .sources = 3,
        .retained_resources = 1,
        .retained_commands = 1,
        .retained_pixel_bytes = 1,
        .composition_sources = 1,
        .candidate_resources = 1,
        .candidate_commands = 1,
        .candidate_pixel_bytes = 1,
    });
    defer composer.deinit();
    const visible = try composer.registerSource();
    const hidden = try composer.registerSource();
    const retired = try composer.registerSource();
    const command = solidInput(white);
    try composer.apply(visible, .{
        .revision = @fromBackingInt(1),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{command},
    });
    const visible_placement = placement(visible, 0);
    try composer.setComposition(.{
        .surface = .{ .width = 1, .height = 1 },
        .sources = &.{visible_placement},
    });
    try composer.removeSource(retired);
    var uploads: [1]canvas.ResourceUploadFact = undefined;
    var removals: [1]canvas.FrameResourceRef = undefined;
    var commands: [1]canvas.Command = undefined;
    var pixels: [1]u8 = undefined;
    const before = try composer.frame(&.{}, .{
        .uploads = &uploads,
        .removals = &removals,
        .commands = &commands,
        .pixels = &pixels,
    });

    const invalid = [_]canvas.Composer.Candidate{
        .{
            .changes = &.{},
            .hidden_source_clears = &.{ visible, visible },
            .composition = .{
                .surface = .{ .width = 1, .height = 1 },
                .sources = &.{},
            },
        },
        .{
            .changes = &.{},
            .hidden_source_clears = &.{hidden},
            .composition = .{
                .surface = .{ .width = 1, .height = 1 },
                .sources = &.{},
            },
        },
        .{
            .changes = &.{.{ .source = visible, .update = .{
                .revision = @fromBackingInt(2),
                .uploads = &.{},
                .removals = &.{},
                .commands = &.{command},
            } }},
            .hidden_source_clears = &.{visible},
            .composition = .{
                .surface = .{ .width = 1, .height = 1 },
                .sources = &.{},
            },
        },
        .{
            .changes = &.{},
            .hidden_source_clears = &.{retired},
            .composition = .{
                .surface = .{ .width = 1, .height = 1 },
                .sources = &.{},
            },
        },
        .{
            .changes = &.{},
            .hidden_source_clears = &.{visible},
            .composition = .{
                .surface = .{ .width = 1, .height = 1 },
                .sources = &.{visible_placement},
            },
        },
    };
    const expected = [_]canvas.Composer.Error{
        error.DuplicateSource,
        error.InvalidSource,
        error.DuplicateSource,
        error.RetiredSource,
        error.DuplicateSource,
    };
    for (invalid, expected) |candidate, failure| {
        try std.testing.expectError(failure, composer.applyCandidate(candidate));
        const after = try composer.frame(&.{}, .{
            .uploads = &uploads,
            .removals = &removals,
            .commands = &commands,
            .pixels = &pixels,
        });
        try std.testing.expectEqual(before.revision, after.revision);
        try std.testing.expectEqualDeep(before.commands, after.commands);
    }

    try composer.applyCandidate(.{
        .changes = &.{},
        .hidden_source_clears = &.{visible},
        .composition = .{
            .surface = .{ .width = 1, .height = 1 },
            .sources = &.{},
        },
    });
}

test "composer atomic candidate admits early growth balanced by later shrink at full capacity" {
    var composer = try canvas.Composer.init(std.testing.allocator, .{
        .sources = 2,
        .retained_resources = 1,
        .retained_commands = 2,
        .retained_pixel_bytes = 1,
        .composition_sources = 2,
        .candidate_resources = 1,
        .candidate_commands = 2,
        .candidate_pixel_bytes = 1,
    });
    defer composer.deinit();
    const first = try composer.registerSource();
    const second = try composer.registerSource();
    const red_command = solidInput(red);
    const white_command = solidInput(white);
    try composer.apply(first, .{
        .revision = @fromBackingInt(1),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{red_command},
    });
    try composer.apply(second, .{
        .revision = @fromBackingInt(1),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{white_command},
    });
    const placements = [_]canvas.Composer.Placement{
        placement(first, 0),
        placement(second, 4),
    };
    try composer.setComposition(.{
        .surface = .{ .width = 16, .height = 8 },
        .sources = &placements,
    });
    const changes = [_]canvas.Composer.SourceChange{
        .{ .source = first, .update = .{
            .revision = @fromBackingInt(2),
            .uploads = &.{},
            .removals = &.{},
            .commands = &.{ red_command, white_command },
        } },
        .{ .source = second, .update = .{
            .revision = @fromBackingInt(2),
            .uploads = &.{},
            .removals = &.{},
            .commands = &.{},
        } },
    };
    try composer.applyCandidate(.{
        .changes = &changes,
        .composition = .{
            .surface = .{ .width = 16, .height = 8 },
            .sources = &placements,
        },
    });
    var storage: FrameStorage = .{};
    const frame = try composer.frame(&.{}, storage.buffers());
    try std.testing.expectEqual(@as(usize, 2), frame.commands.len);
    try std.testing.expectEqualDeep(red, frame.commands[0].solid.color);
    try std.testing.expectEqualDeep(white, frame.commands[1].solid.color);
}

test "composer atomic candidate permits overlapping immutable inputs" {
    var composer = try canvas.Composer.init(std.testing.allocator, .{
        .sources = 2,
        .retained_resources = 1,
        .retained_commands = 2,
        .retained_pixel_bytes = 1,
        .composition_sources = 2,
        .candidate_resources = 1,
        .candidate_commands = 1,
        .candidate_pixel_bytes = 1,
    });
    defer composer.deinit();
    const first = try composer.registerSource();
    const second = try composer.registerSource();
    const command = solidInput(red);
    const shared_commands = [_]canvas.Input{command};
    const changes = [_]canvas.Composer.SourceChange{
        .{ .source = first, .update = .{
            .revision = @fromBackingInt(1),
            .uploads = &.{},
            .removals = &.{},
            .commands = &shared_commands,
        } },
        .{ .source = second, .update = .{
            .revision = @fromBackingInt(1),
            .uploads = &.{},
            .removals = &.{},
            .commands = &shared_commands,
        } },
    };
    const placements = [_]canvas.Composer.Placement{
        placement(first, 0),
        placement(second, 4),
    };
    try composer.applyCandidate(.{
        .changes = &changes,
        .composition = .{
            .surface = .{ .width = 16, .height = 8 },
            .sources = &placements,
        },
    });
    var storage: FrameStorage = .{};
    const frame = try composer.frame(&.{}, storage.buffers());
    try std.testing.expectEqual(@as(usize, 2), frame.commands.len);
}

test "composer atomic candidate rejects inline plan alias and remains reusable" {
    var composer = try canvas.Composer.init(std.testing.allocator, .{
        .sources = 1,
        .retained_resources = 1,
        .retained_commands = 1,
        .retained_pixel_bytes = 1,
        .composition_sources = 1,
        .candidate_resources = 1,
        .candidate_commands = 1,
        .candidate_pixel_bytes = 1,
    });
    defer composer.deinit();
    const source_id = try composer.registerSource();
    const baseline = solidInput(red);
    try composer.apply(source_id, .{
        .revision = @fromBackingInt(1),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{baseline},
    });
    const visible = [_]canvas.Composer.Placement{placement(source_id, 0)};
    try composer.setComposition(.{
        .surface = .{ .width = 16, .height = 8 },
        .sources = &visible,
    });
    var storage: FrameStorage = .{};
    const before = try composer.frame(&.{}, storage.buffers());
    const before_commands = storage.commands;
    const composer_bytes = std.mem.asBytes(&composer);
    const aliased_commands: []const canvas.Input = @ptrCast(@alignCast(
        composer_bytes[0..@sizeOf(canvas.Input)],
    ));
    try std.testing.expectError(
        error.AliasedStorage,
        composer.applyCandidate(.{
            .changes = &.{.{ .source = source_id, .update = .{
                .revision = @fromBackingInt(2),
                .uploads = &.{},
                .removals = &.{},
                .commands = aliased_commands,
            } }},
            .composition = .{
                .surface = .{ .width = 16, .height = 8 },
                .sources = &visible,
            },
        }),
    );
    const after = try composer.frame(&.{}, storage.buffers());
    try std.testing.expectEqual(before.revision, after.revision);
    try std.testing.expectEqualSlices(
        canvas.Command,
        before_commands[0..before.commands.len],
        after.commands,
    );
    const replacement = solidInput(white);
    try composer.applyCandidate(.{
        .changes = &.{.{ .source = source_id, .update = .{
            .revision = @fromBackingInt(2),
            .uploads = &.{},
            .removals = &.{},
            .commands = &.{replacement},
        } }},
        .composition = .{
            .surface = .{ .width = 16, .height = 8 },
            .sources = &visible,
        },
    });
}

test "composer atomic candidate commits opposing resource and pixel growth at full capacity" {
    var composer = try canvas.Composer.init(std.testing.allocator, .{
        .sources = 2,
        .retained_resources = 3,
        .retained_commands = 3,
        .retained_pixel_bytes = 5,
        .composition_sources = 2,
        .candidate_resources = 2,
        .candidate_commands = 2,
        .candidate_pixel_bytes = 3,
    });
    defer composer.deinit();
    const first = try composer.registerSource();
    const second = try composer.registerSource();
    const a1 = try local(1, 1);
    const b1 = try local(1, 1);
    const b2 = try local(2, 1);
    const old_pixels = [_]u8{ 1, 2, 3, 4, 5 };
    const old_a = [_]canvas.ResourceUpload{.{
        .resource = a1,
        .format = .alpha8,
        .pixels = .{
            .bytes = old_pixels[0..3],
            .width = 3,
            .height = 1,
            .stride = 3,
        },
    }};
    const old_b = [_]canvas.ResourceUpload{
        .{ .resource = b1, .format = .alpha8, .pixels = .{
            .bytes = old_pixels[3..4],
            .width = 1,
            .height = 1,
            .stride = 1,
        } },
        .{ .resource = b2, .format = .alpha8, .pixels = .{
            .bytes = old_pixels[4..5],
            .width = 1,
            .height = 1,
            .stride = 1,
        } },
    };
    const old_a_command = resourceInput(a1, 3);
    const old_b_commands = [_]canvas.Input{
        resourceInput(b1, 1),
        resourceInput(b2, 1),
    };
    try composer.apply(first, .{
        .revision = @fromBackingInt(1),
        .uploads = &old_a,
        .removals = &.{},
        .commands = &.{old_a_command},
    });
    try composer.apply(second, .{
        .revision = @fromBackingInt(1),
        .uploads = &old_b,
        .removals = &.{},
        .commands = &old_b_commands,
    });
    const placements = [_]canvas.Composer.Placement{
        placement(first, 0),
        placement(second, 4),
    };
    try composer.setComposition(.{
        .surface = .{ .width = 16, .height = 8 },
        .sources = &placements,
    });

    const a1_new = try local(1, 2);
    const a2 = try local(2, 1);
    const b1_new = try local(1, 2);
    const new_pixels = [_]u8{ 10, 11, 20, 21, 22 };
    const a_uploads = [_]canvas.ResourceUpload{
        .{ .resource = a1_new, .format = .alpha8, .pixels = .{
            .bytes = new_pixels[0..1],
            .width = 1,
            .height = 1,
            .stride = 1,
        } },
        .{ .resource = a2, .format = .alpha8, .pixels = .{
            .bytes = new_pixels[1..2],
            .width = 1,
            .height = 1,
            .stride = 1,
        } },
    };
    const b_uploads = [_]canvas.ResourceUpload{.{
        .resource = b1_new,
        .format = .alpha8,
        .pixels = .{
            .bytes = new_pixels[2..5],
            .width = 3,
            .height = 1,
            .stride = 3,
        },
    }};
    const changes = [_]canvas.Composer.SourceChange{
        .{ .source = first, .update = .{
            .revision = @fromBackingInt(2),
            .uploads = &a_uploads,
            .removals = &.{},
            .commands = &.{
                resourceInput(a1_new, 1),
                resourceInput(a2, 1),
            },
        } },
        .{ .source = second, .update = .{
            .revision = @fromBackingInt(2),
            .uploads = &b_uploads,
            .removals = &.{.{ .resource = b2 }},
            .commands = &.{resourceInput(b1_new, 3)},
        } },
    };
    try composer.applyCandidate(.{
        .changes = &changes,
        .composition = .{
            .surface = .{ .width = 16, .height = 8 },
            .sources = &placements,
        },
    });
    var storage: FrameStorage = .{};
    const frame = try composer.frame(&.{}, storage.buffers());
    try std.testing.expectEqual(@as(usize, 3), frame.uploads.len);
    try std.testing.expectEqual(@as(usize, 5), frame.pixels.len);
    try std.testing.expectEqualSlices(u8, &new_pixels, frame.pixels);
}

test "composer atomic candidate late geometry failure preserves frame" {
    var composer = try canvas.Composer.init(
        std.testing.allocator,
        composerLimits(),
    );
    defer composer.deinit();
    const first = try composer.registerSource();
    const second = try composer.registerSource();
    const red_command = solidInput(red);
    const white_command = solidInput(white);
    try composer.apply(first, .{
        .revision = @fromBackingInt(1),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{red_command},
    });
    try composer.apply(second, .{
        .revision = @fromBackingInt(1),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{white_command},
    });
    const visible = [_]canvas.Composer.Placement{
        placement(first, 0),
        placement(second, 4),
    };
    try composer.setComposition(.{
        .surface = .{ .width = 16, .height = 8 },
        .sources = &visible,
    });
    var storage: FrameStorage = .{};
    const before = try composer.frame(&.{}, storage.buffers());
    const before_commands = storage.commands;
    var invalid = visible;
    invalid[1].clip.width = 0;
    const changes = [_]canvas.Composer.SourceChange{
        .{ .source = first, .update = .{
            .revision = @fromBackingInt(2),
            .uploads = &.{},
            .removals = &.{},
            .commands = &.{white_command},
        } },
        .{ .source = second, .update = .{
            .revision = @fromBackingInt(2),
            .uploads = &.{},
            .removals = &.{},
            .commands = &.{red_command},
        } },
    };
    try std.testing.expectError(error.InvalidGeometry, composer.applyCandidate(.{
        .changes = &changes,
        .composition = .{
            .surface = .{ .width = 16, .height = 8 },
            .sources = &invalid,
        },
    }));
    const after = try composer.frame(&.{}, storage.buffers());
    try std.testing.expectEqual(before.revision, after.revision);
    try std.testing.expectEqualSlices(
        canvas.Command,
        before_commands[0..before.commands.len],
        after.commands,
    );
}

test "composer atomic candidate relocates packed local ranges both directions" {
    var composer = try canvas.Composer.init(std.testing.allocator, .{
        .sources = 3,
        .retained_resources = 4,
        .retained_commands = 4,
        .retained_pixel_bytes = 4,
        .composition_sources = 3,
        .candidate_resources = 2,
        .candidate_commands = 2,
        .candidate_pixel_bytes = 2,
    });
    defer composer.deinit();
    const sources = [_]canvas.SourceId{
        try composer.registerSource(),
        try composer.registerSource(),
        try composer.registerSource(),
    };
    const old_pixels = [_]u8{ 11, 22, 33 };
    var old_resources: [3]canvas.ResourceRef = undefined;
    var old_uploads: [3]canvas.ResourceUpload = undefined;
    var old_commands: [3]canvas.Input = undefined;
    for (sources, 0..) |source_id, index| {
        old_resources[index] = try local(1, 1);
        old_uploads[index] = .{
            .resource = old_resources[index],
            .format = .alpha8,
            .pixels = .{
                .bytes = old_pixels[index..][0..1],
                .width = 1,
                .height = 1,
                .stride = 1,
            },
        };
        old_commands[index] = alphaInput(old_resources[index], white);
        try composer.apply(source_id, .{
            .revision = @fromBackingInt(1),
            .uploads = old_uploads[index..][0..1],
            .removals = &.{},
            .commands = old_commands[index..][0..1],
        });
    }
    var placements = [_]canvas.Composer.Placement{
        placement(sources[0], 0),
        placement(sources[1], 1),
        placement(sources[2], 2),
    };
    try composer.setComposition(.{
        .surface = .{ .width = 16, .height = 8 },
        .sources = &placements,
    });

    const replacement_pixel = [_]u8{55};
    const appended_resource = try local(2, 1);
    const replacement_uploads = [_]canvas.ResourceUpload{.{
        .resource = appended_resource,
        .format = .alpha8,
        .pixels = .{
            .bytes = &replacement_pixel,
            .width = 1,
            .height = 1,
            .stride = 1,
        },
    }};
    const replacement_commands = [_]canvas.Input{
        alphaInput(old_resources[2], red),
        alphaInput(appended_resource, white),
    };
    const changes = [_]canvas.Composer.SourceChange{
        .{
            .source = sources[0],
            .update = .{
                .revision = @fromBackingInt(2),
                .uploads = &.{},
                .removals = &.{canvas.ResourceRemoval{
                    .resource = old_resources[0],
                }},
                .commands = &.{},
            },
        },
        .{
            .source = sources[2],
            .update = .{
                .revision = @fromBackingInt(2),
                .uploads = &replacement_uploads,
                .removals = &.{},
                .commands = &replacement_commands,
            },
        },
    };
    placements[0].origin.x = 3;
    try composer.applyCandidate(.{
        .changes = &changes,
        .composition = .{
            .surface = .{ .width = 16, .height = 8 },
            .sources = &placements,
        },
    });
    var uploads: [4]canvas.ResourceUploadFact = undefined;
    var removals: [4]canvas.FrameResourceRef = undefined;
    var commands: [4]canvas.Command = undefined;
    var pixels: [4]u8 = undefined;
    const frame = try composer.frame(&.{}, .{
        .uploads = &uploads,
        .removals = &removals,
        .commands = &commands,
        .pixels = &pixels,
    });
    try std.testing.expectEqual(@as(usize, 3), frame.uploads.len);
    try std.testing.expectEqual(@as(usize, 3), frame.commands.len);
    try std.testing.expectEqualSlices(u8, &.{ 22, 33, 55 }, frame.pixels);
    try std.testing.expectEqual(sources[1], frame.uploads[0].resource.source);
    try std.testing.expectEqual(sources[2], frame.uploads[1].resource.source);
    try std.testing.expectEqual(sources[2], frame.uploads[2].resource.source);
}

test "composer atomic candidate hides and reveals complete local source" {
    var composer = try canvas.Composer.init(
        std.testing.allocator,
        composerLimits(),
    );
    defer composer.deinit();
    const source_id = try composer.registerSource();
    const command = solidInput(red);
    try composer.apply(source_id, .{
        .revision = @fromBackingInt(1),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{command},
    });
    const visible = [_]canvas.Composer.Placement{placement(source_id, 0)};
    try composer.setComposition(.{
        .surface = .{ .width = 16, .height = 8 },
        .sources = &visible,
    });
    try composer.applyCandidate(.{
        .changes = &.{.{ .source = source_id, .update = .{
            .revision = @fromBackingInt(2),
            .uploads = &.{},
            .removals = &.{},
            .commands = &.{},
        } }},
        .composition = .{
            .surface = .{ .width = 16, .height = 8 },
            .sources = &.{},
        },
    });
    var storage: FrameStorage = .{};
    const hidden = try composer.frame(&.{}, storage.buffers());
    try std.testing.expectEqual(@as(usize, 0), hidden.commands.len);

    try composer.applyCandidate(.{
        .changes = &.{.{ .source = source_id, .update = .{
            .revision = @fromBackingInt(3),
            .uploads = &.{},
            .removals = &.{},
            .commands = &.{command},
        } }},
        .composition = .{
            .surface = .{ .width = 16, .height = 8 },
            .sources = &visible,
        },
    });
    const revealed = try composer.frame(&.{}, storage.buffers());
    try std.testing.expectEqual(@as(usize, 1), revealed.commands.len);
    try std.testing.expectEqual(
        @backingInt(hidden.revision) + 1,
        @backingInt(revealed.revision),
    );
}

test "composer atomic candidate rejects duplicate stale and retired sources" {
    var composer = try canvas.Composer.init(
        std.testing.allocator,
        composerLimits(),
    );
    defer composer.deinit();
    const live = try composer.registerSource();
    const retired = try composer.registerSource();
    const command = solidInput(red);
    try composer.apply(live, .{
        .revision = @fromBackingInt(1),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{command},
    });
    try composer.removeSource(retired);
    const placement_value = [_]canvas.Composer.Placement{placement(live, 0)};
    const update = canvas.ProducerUpdate{
        .revision = @fromBackingInt(2),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{command},
    };
    const duplicate_command = [_]canvas.Input{command};
    const duplicate_update = canvas.ProducerUpdate{
        .revision = @fromBackingInt(2),
        .uploads = &.{},
        .removals = &.{},
        .commands = &duplicate_command,
    };
    try std.testing.expectError(error.DuplicateSource, composer.applyCandidate(.{
        .changes = &.{
            .{ .source = live, .update = update },
            .{ .source = live, .update = duplicate_update },
        },
        .composition = .{
            .surface = .{ .width = 16, .height = 8 },
            .sources = &placement_value,
        },
    }));
    var stale = update;
    stale.revision = @fromBackingInt(1);
    try std.testing.expectError(error.InvalidRevision, composer.applyCandidate(.{
        .changes = &.{.{ .source = live, .update = stale }},
        .composition = .{
            .surface = .{ .width = 16, .height = 8 },
            .sources = &placement_value,
        },
    }));
    try std.testing.expectError(error.RetiredSource, composer.applyCandidate(.{
        .changes = &.{.{ .source = retired, .update = update }},
        .composition = .{
            .surface = .{ .width = 16, .height = 8 },
            .sources = &placement_value,
        },
    }));
    try std.testing.expectError(error.DuplicateSource, composer.applyCandidate(.{
        .changes = &.{},
        .composition = .{
            .surface = .{ .width = 16, .height = 8 },
            .sources = &.{ placement(live, 0), placement(live, 1) },
        },
    }));
}

test "composer atomic candidate pressure rolls back and later succeeds" {
    var composer = try canvas.Composer.init(std.testing.allocator, .{
        .sources = 2,
        .retained_resources = 1,
        .retained_commands = 1,
        .retained_pixel_bytes = 1,
        .composition_sources = 1,
        .candidate_resources = 2,
        .candidate_commands = 2,
        .candidate_pixel_bytes = 2,
    });
    defer composer.deinit();
    const first = try composer.registerSource();
    const second = try composer.registerSource();
    const placements = [_]canvas.Composer.Placement{placement(first, 0)};
    const pixels = [_]u8{ 1, 2 };
    const uploads = [_]canvas.ResourceUpload{
        .{
            .resource = try local(1, 1),
            .format = .alpha8,
            .pixels = .{
                .bytes = pixels[0..1],
                .width = 1,
                .height = 1,
                .stride = 1,
            },
        },
        .{
            .resource = try local(2, 1),
            .format = .alpha8,
            .pixels = .{
                .bytes = pixels[1..2],
                .width = 1,
                .height = 1,
                .stride = 1,
            },
        },
    };
    try std.testing.expectError(error.ResourceLimit, composer.applyCandidate(.{
        .changes = &.{.{ .source = first, .update = .{
            .revision = @fromBackingInt(1),
            .uploads = &uploads,
            .removals = &.{},
            .commands = &.{},
        } }},
        .composition = .{
            .surface = .{ .width = 16, .height = 8 },
            .sources = &placements,
        },
    }));
    const wide_upload = [_]canvas.ResourceUpload{.{
        .resource = try local(1, 1),
        .format = .alpha8,
        .pixels = .{
            .bytes = &pixels,
            .width = 2,
            .height = 1,
            .stride = 2,
        },
    }};
    try std.testing.expectError(error.PixelLimit, composer.applyCandidate(.{
        .changes = &.{.{ .source = first, .update = .{
            .revision = @fromBackingInt(1),
            .uploads = &wide_upload,
            .removals = &.{},
            .commands = &.{},
        } }},
        .composition = .{
            .surface = .{ .width = 16, .height = 8 },
            .sources = &placements,
        },
    }));
    const commands = [_]canvas.Input{ solidInput(red), solidInput(white) };
    try std.testing.expectError(error.CommandLimit, composer.applyCandidate(.{
        .changes = &.{.{ .source = first, .update = .{
            .revision = @fromBackingInt(1),
            .uploads = &.{},
            .removals = &.{},
            .commands = &commands,
        } }},
        .composition = .{
            .surface = .{ .width = 16, .height = 8 },
            .sources = &placements,
        },
    }));
    try std.testing.expectError(error.CompositionLimit, composer.applyCandidate(.{
        .changes = &.{},
        .composition = .{
            .surface = .{ .width = 16, .height = 8 },
            .sources = &.{ placement(first, 0), placement(second, 1) },
        },
    }));

    const valid = solidInput(red);
    try composer.applyCandidate(.{
        .changes = &.{.{ .source = first, .update = .{
            .revision = @fromBackingInt(1),
            .uploads = &.{},
            .removals = &.{},
            .commands = &.{valid},
        } }},
        .composition = .{
            .surface = .{ .width = 16, .height = 8 },
            .sources = &placements,
        },
    });
    var storage: FrameStorage = .{};
    const frame = try composer.frame(&.{}, storage.buffers());
    try std.testing.expectEqual(@as(usize, 1), frame.commands.len);
}

test "atomic candidate shares one logical resource across local sources" {
    var composer = try canvas.Composer.init(std.testing.allocator, .{
        .sources = 2,
        .retained_resources = 2,
        .retained_commands = 8,
        .retained_pixel_bytes = 8,
        .composition_sources = 2,
        .candidate_resources = 4,
        .candidate_commands = 4,
        .candidate_pixel_bytes = 4,
    });
    defer composer.deinit();
    const first = try composer.registerSource();
    const second = try composer.registerSource();
    const shared_ref = try shared(1, 1);
    const local_ref = try local(1, 1);
    const shared_bytes = [_]u8{ 0x11, 0x22 };
    const local_bytes = [_]u8{0x33};
    const shared_upload = canvas.ResourceUpload{
        .resource = shared_ref,
        .format = .alpha8,
        .pixels = .{
            .bytes = &shared_bytes,
            .width = 2,
            .height = 1,
            .stride = 2,
        },
    };
    const local_upload = canvas.ResourceUpload{
        .resource = local_ref,
        .format = .alpha8,
        .pixels = .{
            .bytes = &local_bytes,
            .width = 1,
            .height = 1,
            .stride = 1,
        },
    };
    const shared_command = canvas.Input{ .alpha_mask = .{
        .destination = .{ .x = 0, .y = 0, .width = 2, .height = 1 },
        .clip = .{ .x = 0, .y = 0, .width = 2, .height = 1 },
        .resource = .{
            .resource = shared_ref,
            .format = .alpha8,
            .size = .{ .width = 2, .height = 1 },
        },
        .color = white,
    } };
    const local_command = canvas.Input{ .alpha_mask = .{
        .destination = .{ .x = 2, .y = 0, .width = 1, .height = 1 },
        .clip = .{ .x = 2, .y = 0, .width = 1, .height = 1 },
        .resource = .{
            .resource = local_ref,
            .format = .alpha8,
            .size = .{ .width = 1, .height = 1 },
        },
        .color = red,
    } };
    const placements = [_]canvas.Composer.Placement{
        .{
            .source = first,
            .origin = .{ .x = 0, .y = 0 },
            .clip = .{ .x = 0, .y = 0, .width = 3, .height = 1 },
        },
        .{
            .source = second,
            .origin = .{ .x = 0, .y = 1 },
            .clip = .{ .x = 0, .y = 1, .width = 3, .height = 1 },
        },
    };
    try composer.applyCandidate(.{
        .changes = &.{
            .{ .source = first, .update = .{
                .revision = @fromBackingInt(1),
                .uploads = &.{ shared_upload, local_upload },
                .removals = &.{},
                .commands = &.{ shared_command, local_command },
            } },
            .{ .source = second, .update = .{
                .revision = @fromBackingInt(1),
                .uploads = &.{shared_upload},
                .removals = &.{},
                .commands = &.{shared_command},
            } },
        },
        .composition = .{
            .surface = .{ .width = 3, .height = 2 },
            .sources = &placements,
        },
    });
    var uploads: [4]canvas.ResourceUploadFact = undefined;
    var removals: [4]canvas.FrameResourceRef = undefined;
    var commands: [4]canvas.Command = undefined;
    var pixels: [8]u8 = undefined;
    const first_frame = try composer.frame(&.{}, .{
        .uploads = &uploads,
        .removals = &removals,
        .commands = &commands,
        .pixels = &pixels,
    });
    try std.testing.expectEqual(@as(usize, 2), first_frame.uploads.len);
    var shared_uploads: usize = 0;
    var local_uploads: usize = 0;
    for (first_frame.uploads) |upload| {
        if (upload.resource.resource.isShared()) {
            shared_uploads += 1;
            try std.testing.expectEqual(
                @as(u64, 0),
                @backingInt(upload.resource.source),
            );
            try std.testing.expectEqualSlices(
                u8,
                &shared_bytes,
                first_frame.pixels[upload.pixel_offset .. upload.pixel_offset +
                    upload.pixel_count],
            );
        } else {
            local_uploads += 1;
            try std.testing.expectEqual(first, upload.resource.source);
        }
    }
    try std.testing.expectEqual(@as(usize, 1), shared_uploads);
    try std.testing.expectEqual(@as(usize, 1), local_uploads);

    const local_two = try local(2, 1);
    var local_two_upload = local_upload;
    local_two_upload.resource = local_two;
    const local_two_command = sharedAlphaCommand(local_two, 1, 1);
    try std.testing.expectError(
        error.ResourceLimit,
        composer.applyCandidate(.{
            .changes = &.{.{ .source = first, .update = .{
                .revision = @fromBackingInt(2),
                .uploads = &.{local_two_upload},
                .removals = &.{},
                .commands = &.{
                    shared_command,
                    local_command,
                    local_two_command,
                },
            } }},
            .composition = .{
                .surface = .{ .width = 3, .height = 2 },
                .sources = &placements,
            },
        }),
    );
    try composer.applyCandidate(.{
        .changes = &.{.{ .source = first, .update = .{
            .revision = @fromBackingInt(2),
            .uploads = &.{},
            .removals = &.{canvas.ResourceRemoval{ .resource = local_ref }},
            .commands = &.{},
        } }},
        .composition = .{
            .surface = .{ .width = 3, .height = 2 },
            .sources = &placements,
        },
    });
    const shared_residency = canvas.Residency{
        .resource = try canvas.FrameResourceRef.shared(shared_ref),
        .format = .alpha8,
        .size = .{ .width = 2, .height = 1 },
    };
    const retained = try composer.frame(&.{shared_residency}, .{
        .uploads = &uploads,
        .removals = &removals,
        .commands = &commands,
        .pixels = &pixels,
    });
    try std.testing.expectEqual(@as(usize, 0), retained.uploads.len);
    try std.testing.expectEqual(@as(usize, 0), retained.removals.len);

    var conflicting = shared_upload;
    conflicting.pixels.bytes = &.{ 0x11, 0x44 };
    try std.testing.expectError(
        error.ConflictingResourceOperation,
        composer.applyCandidate(.{
            .changes = &.{.{ .source = second, .update = .{
                .revision = @fromBackingInt(2),
                .uploads = &.{conflicting},
                .removals = &.{},
                .commands = &.{shared_command},
            } }},
            .composition = .{
                .surface = .{ .width = 3, .height = 2 },
                .sources = &placements,
            },
        }),
    );
    var conflicting_format = shared_upload;
    conflicting_format.format = .rgba8;
    conflicting_format.pixels.bytes =
        &.{ 0x11, 0x22, 0, 0, 0, 0, 0, 0 };
    conflicting_format.pixels.stride = 8;
    try std.testing.expectError(
        error.FormatMismatch,
        composer.applyCandidate(.{
            .changes = &.{.{ .source = second, .update = .{
                .revision = @fromBackingInt(2),
                .uploads = &.{conflicting_format},
                .removals = &.{},
                .commands = &.{shared_command},
            } }},
            .composition = .{
                .surface = .{ .width = 3, .height = 2 },
                .sources = &placements,
            },
        }),
    );
    var conflicting_extent = shared_upload;
    conflicting_extent.pixels.bytes = &.{0x11};
    conflicting_extent.pixels.width = 1;
    conflicting_extent.pixels.stride = 1;
    try std.testing.expectError(
        error.ExtentMismatch,
        composer.applyCandidate(.{
            .changes = &.{.{ .source = second, .update = .{
                .revision = @fromBackingInt(2),
                .uploads = &.{conflicting_extent},
                .removals = &.{},
                .commands = &.{shared_command},
            } }},
            .composition = .{
                .surface = .{ .width = 3, .height = 2 },
                .sources = &placements,
            },
        }),
    );
    var conflicting_stride = shared_upload;
    conflicting_stride.pixels.stride = 3;
    try std.testing.expectError(
        error.ExtentMismatch,
        composer.applyCandidate(.{
            .changes = &.{.{ .source = second, .update = .{
                .revision = @fromBackingInt(2),
                .uploads = &.{conflicting_stride},
                .removals = &.{},
                .commands = &.{shared_command},
            } }},
            .composition = .{
                .surface = .{ .width = 3, .height = 2 },
                .sources = &placements,
            },
        }),
    );
    var conflicting_generation = shared_upload;
    conflicting_generation.resource.generation = @fromBackingInt(2);
    try std.testing.expectError(
        error.InvalidGeneration,
        composer.applyCandidate(.{
            .changes = &.{.{ .source = second, .update = .{
                .revision = @fromBackingInt(2),
                .uploads = &.{conflicting_generation},
                .removals = &.{},
                .commands = &.{shared_command},
            } }},
            .composition = .{
                .surface = .{ .width = 3, .height = 2 },
                .sources = &placements,
            },
        }),
    );
    const unchanged = try composer.frame(&.{}, .{
        .uploads = &uploads,
        .removals = &removals,
        .commands = &commands,
        .pixels = &pixels,
    });
    try std.testing.expectEqual(@as(usize, 1), unchanged.uploads.len);
    try std.testing.expectEqualSlices(
        u8,
        &shared_bytes,
        unchanged.pixels[0..shared_bytes.len],
    );

    try composer.applyCandidate(.{
        .changes = &.{.{ .source = second, .update = .{
            .revision = @fromBackingInt(2),
            .uploads = &.{},
            .removals = &.{},
            .commands = &.{},
        } }},
        .composition = .{
            .surface = .{ .width = 3, .height = 2 },
            .sources = &placements,
        },
    });
    const retired = try composer.frame(&.{shared_residency}, .{
        .uploads = &uploads,
        .removals = &removals,
        .commands = &commands,
        .pixels = &pixels,
    });
    try std.testing.expectEqual(@as(usize, 1), retired.removals.len);
    try std.testing.expectEqual(
        shared_residency.resource,
        retired.removals[0],
    );
    try std.testing.expectError(
        error.InvalidIdentity,
        composer.applyCandidate(.{
            .changes = &.{.{ .source = second, .update = .{
                .revision = @fromBackingInt(3),
                .uploads = &.{shared_upload},
                .removals = &.{},
                .commands = &.{shared_command},
            } }},
            .composition = .{
                .surface = .{ .width = 3, .height = 2 },
                .sources = &placements,
            },
        }),
    );
}

test "shared entry limit rejects the next identity without mutation" {
    const limit: usize = 2048;
    var composer = try canvas.Composer.init(std.testing.allocator, .{
        .sources = 1,
        .retained_resources = limit,
        .retained_commands = limit + 1,
        .retained_pixel_bytes = 1,
        .composition_sources = 1,
        .candidate_resources = 1,
        .candidate_commands = limit + 1,
        .candidate_pixel_bytes = 1,
    });
    defer composer.deinit();
    const source_id = try composer.registerSource();
    const bytes = try std.testing.allocator.alloc(u8, limit);
    defer std.testing.allocator.free(bytes);
    @memset(bytes, 0x5a);
    const uploads = try std.testing.allocator.alloc(
        canvas.ResourceUpload,
        limit,
    );
    defer std.testing.allocator.free(uploads);
    const commands = try std.testing.allocator.alloc(canvas.Input, limit + 1);
    defer std.testing.allocator.free(commands);
    for (uploads, 0..) |*upload, index| {
        const resource = try shared(index + 1, 1);
        upload.* = .{
            .resource = resource,
            .format = .alpha8,
            .pixels = .{
                .bytes = bytes[index..][0..1],
                .width = 1,
                .height = 1,
                .stride = 1,
            },
        };
        commands[index] = sharedAlphaCommand(resource, 1, 1);
    }
    const placements = [_]canvas.Composer.Placement{.{
        .source = source_id,
        .origin = .{ .x = 0, .y = 0 },
        .clip = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
    }};
    try composer.applyCandidate(.{
        .changes = &.{.{ .source = source_id, .update = .{
            .revision = @fromBackingInt(1),
            .uploads = uploads,
            .removals = &.{},
            .commands = commands[0..limit],
        } }},
        .composition = .{
            .surface = .{ .width = 1, .height = 1 },
            .sources = &placements,
        },
    });
    const extra_ref = try shared(limit + 1, 1);
    const extra_byte = [_]u8{0x7c};
    const extra_upload = canvas.ResourceUpload{
        .resource = extra_ref,
        .format = .alpha8,
        .pixels = .{
            .bytes = &extra_byte,
            .width = 1,
            .height = 1,
            .stride = 1,
        },
    };
    commands[limit] = sharedAlphaCommand(extra_ref, 1, 1);
    try std.testing.expectError(
        error.ResourceLimit,
        composer.applyCandidate(.{
            .changes = &.{.{ .source = source_id, .update = .{
                .revision = @fromBackingInt(2),
                .uploads = &.{extra_upload},
                .removals = &.{},
                .commands = commands,
            } }},
            .composition = .{
                .surface = .{ .width = 1, .height = 1 },
                .sources = &placements,
            },
        }),
    );
    try composer.applyCandidate(.{
        .changes = &.{.{ .source = source_id, .update = .{
            .revision = @fromBackingInt(2),
            .uploads = &.{},
            .removals = &.{},
            .commands = commands[0..limit],
        } }},
        .composition = .{
            .surface = .{ .width = 1, .height = 1 },
            .sources = &placements,
        },
    });
}

test "shared variable ranges reject fragmentation and coalesce completely" {
    const bank_size: usize = 8 * 1024 * 1024;
    const part_size: usize = 2 * 1024 * 1024;
    const large_size: usize = 3 * 1024 * 1024;
    const bytes = try std.testing.allocator.alloc(u8, bank_size);
    defer std.testing.allocator.free(bytes);
    for (bytes, 0..) |*byte, index| byte.* = @truncate(index);
    var composer = try canvas.Composer.init(std.testing.allocator, .{
        .sources = 1,
        .retained_resources = 8,
        .retained_commands = 8,
        .retained_pixel_bytes = 1,
        .composition_sources = 1,
        .candidate_resources = 1,
        .candidate_commands = 8,
        .candidate_pixel_bytes = 1,
    });
    defer composer.deinit();
    const source_id = try composer.registerSource();
    var uploads: [4]canvas.ResourceUpload = undefined;
    var commands: [5]canvas.Input = undefined;
    for (&uploads, 0..) |*upload, index| {
        const resource = try shared(index + 1, 1);
        upload.* = .{
            .resource = resource,
            .format = .alpha8,
            .pixels = .{
                .bytes = bytes[index * part_size ..][0..part_size],
                .width = 32768,
                .height = 64,
                .stride = 32768,
            },
        };
        commands[index] = sharedAlphaCommand(resource, 32768, 64);
    }
    const placements = [_]canvas.Composer.Placement{.{
        .source = source_id,
        .origin = .{ .x = 0, .y = 0 },
        .clip = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
    }};
    try composer.applyCandidate(.{
        .changes = &.{.{ .source = source_id, .update = .{
            .revision = @fromBackingInt(1),
            .uploads = &uploads,
            .removals = &.{},
            .commands = commands[0..4],
        } }},
        .composition = .{
            .surface = .{ .width = 1, .height = 1 },
            .sources = &placements,
        },
    });
    const fragmented_ref = try shared(5, 1);
    const fragmented_upload = canvas.ResourceUpload{
        .resource = fragmented_ref,
        .format = .alpha8,
        .pixels = .{
            .bytes = bytes[0..large_size],
            .width = 32768,
            .height = 96,
            .stride = 32768,
        },
    };
    commands[4] = sharedAlphaCommand(fragmented_ref, 32768, 96);
    const fragmented_commands = [_]canvas.Input{
        commands[0],
        commands[2],
        commands[4],
    };
    try std.testing.expectError(
        error.PixelLimit,
        composer.applyCandidate(.{
            .changes = &.{.{ .source = source_id, .update = .{
                .revision = @fromBackingInt(2),
                .uploads = &.{fragmented_upload},
                .removals = &.{},
                .commands = &fragmented_commands,
            } }},
            .composition = .{
                .surface = .{ .width = 1, .height = 1 },
                .sources = &placements,
            },
        }),
    );
    const coalesced_ref = try shared(6, 1);
    var coalesced_upload = fragmented_upload;
    coalesced_upload.resource = coalesced_ref;
    const coalesced_command = sharedAlphaCommand(coalesced_ref, 32768, 96);
    try composer.applyCandidate(.{
        .changes = &.{.{ .source = source_id, .update = .{
            .revision = @fromBackingInt(2),
            .uploads = &.{coalesced_upload},
            .removals = &.{},
            .commands = &.{ commands[0], coalesced_command },
        } }},
        .composition = .{
            .surface = .{ .width = 1, .height = 1 },
            .sources = &placements,
        },
    });
    try composer.applyCandidate(.{
        .changes = &.{.{ .source = source_id, .update = .{
            .revision = @fromBackingInt(3),
            .uploads = &.{},
            .removals = &.{},
            .commands = &.{},
        } }},
        .composition = .{
            .surface = .{ .width = 1, .height = 1 },
            .sources = &placements,
        },
    });
    const full_ref = try shared(7, 1);
    const full_upload = canvas.ResourceUpload{
        .resource = full_ref,
        .format = .alpha8,
        .pixels = .{
            .bytes = bytes,
            .width = 32768,
            .height = 256,
            .stride = 32768,
        },
    };
    const full_command = sharedAlphaCommand(full_ref, 32768, 256);
    try composer.applyCandidate(.{
        .changes = &.{.{ .source = source_id, .update = .{
            .revision = @fromBackingInt(4),
            .uploads = &.{full_upload},
            .removals = &.{},
            .commands = &.{full_command},
        } }},
        .composition = .{
            .surface = .{ .width = 1, .height = 1 },
            .sources = &placements,
        },
    });
}

test "shared recovery pixel limit preserves the complete accepted bytes" {
    const bank_size: usize = 8 * 1024 * 1024;
    const bytes = try std.testing.allocator.alloc(u8, bank_size);
    defer std.testing.allocator.free(bytes);
    for (bytes, 0..) |*byte, index| byte.* = @truncate(index * 17);
    var composer = try canvas.Composer.init(std.testing.allocator, .{
        .sources = 1,
        .retained_resources = 2,
        .retained_commands = 2,
        .retained_pixel_bytes = 1,
        .composition_sources = 1,
        .candidate_resources = 1,
        .candidate_commands = 2,
        .candidate_pixel_bytes = 1,
    });
    defer composer.deinit();
    const source_id = try composer.registerSource();
    const full_ref = try shared(1, 1);
    const full_upload = canvas.ResourceUpload{
        .resource = full_ref,
        .format = .alpha8,
        .pixels = .{
            .bytes = bytes,
            .width = 32768,
            .height = 256,
            .stride = 32768,
        },
    };
    const full_command = sharedAlphaCommand(full_ref, 32768, 256);
    const placements = [_]canvas.Composer.Placement{.{
        .source = source_id,
        .origin = .{ .x = 0, .y = 0 },
        .clip = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
    }};
    try composer.applyCandidate(.{
        .changes = &.{.{ .source = source_id, .update = .{
            .revision = @fromBackingInt(1),
            .uploads = &.{full_upload},
            .removals = &.{},
            .commands = &.{full_command},
        } }},
        .composition = .{
            .surface = .{ .width = 1, .height = 1 },
            .sources = &placements,
        },
    });
    const extra_ref = try shared(2, 1);
    const extra_byte = [_]u8{0xcc};
    const extra_upload = canvas.ResourceUpload{
        .resource = extra_ref,
        .format = .alpha8,
        .pixels = .{
            .bytes = &extra_byte,
            .width = 1,
            .height = 1,
            .stride = 1,
        },
    };
    const extra_command = sharedAlphaCommand(extra_ref, 1, 1);
    try std.testing.expectError(
        error.PixelLimit,
        composer.applyCandidate(.{
            .changes = &.{.{ .source = source_id, .update = .{
                .revision = @fromBackingInt(2),
                .uploads = &.{extra_upload},
                .removals = &.{},
                .commands = &.{ full_command, extra_command },
            } }},
            .composition = .{
                .surface = .{ .width = 1, .height = 1 },
                .sources = &placements,
            },
        }),
    );
    var uploads: [1]canvas.ResourceUploadFact = undefined;
    var removals: [1]canvas.FrameResourceRef = undefined;
    var commands: [1]canvas.Command = undefined;
    const recovered = try std.testing.allocator.alloc(u8, bank_size);
    defer std.testing.allocator.free(recovered);
    const frame = try composer.frame(&.{}, .{
        .uploads = &uploads,
        .removals = &removals,
        .commands = &commands,
        .pixels = recovered,
    });
    try std.testing.expectEqual(@as(usize, 1), frame.uploads.len);
    try std.testing.expectEqualSlices(u8, bytes, frame.pixels);
}

test "removeSource releases only its exact shared ownership" {
    var composer = try canvas.Composer.init(std.testing.allocator, .{
        .sources = 3,
        .retained_resources = 2,
        .retained_commands = 2,
        .retained_pixel_bytes = 1,
        .composition_sources = 2,
        .candidate_resources = 1,
        .candidate_commands = 1,
        .candidate_pixel_bytes = 1,
    });
    defer composer.deinit();
    const first = try composer.registerSource();
    const second = try composer.registerSource();
    const shared_one = try shared(1, 1);
    const shared_bytes = [_]u8{ 0x41, 0x42 };
    const upload = canvas.ResourceUpload{
        .resource = shared_one,
        .format = .alpha8,
        .pixels = .{
            .bytes = &shared_bytes,
            .width = 2,
            .height = 1,
            .stride = 2,
        },
    };
    const command = sharedAlphaCommand(shared_one, 2, 1);
    const placements = [_]canvas.Composer.Placement{
        .{
            .source = first,
            .origin = .{ .x = 0, .y = 0 },
            .clip = .{ .x = 0, .y = 0, .width = 2, .height = 1 },
        },
        .{
            .source = second,
            .origin = .{ .x = 0, .y = 1 },
            .clip = .{ .x = 0, .y = 1, .width = 2, .height = 1 },
        },
    };
    try composer.applyCandidate(.{
        .changes = &.{
            .{ .source = first, .update = .{
                .revision = @fromBackingInt(1),
                .uploads = &.{upload},
                .removals = &.{},
                .commands = &.{command},
            } },
            .{ .source = second, .update = .{
                .revision = @fromBackingInt(1),
                .uploads = &.{upload},
                .removals = &.{},
                .commands = &.{command},
            } },
        },
        .composition = .{
            .surface = .{ .width = 2, .height = 2 },
            .sources = &placements,
        },
    });
    var uploads: [2]canvas.ResourceUploadFact = undefined;
    var removals: [2]canvas.FrameResourceRef = undefined;
    var commands: [2]canvas.Command = undefined;
    var pixels: [4]u8 = undefined;
    const initial = try composer.frame(&.{}, .{
        .uploads = &uploads,
        .removals = &removals,
        .commands = &commands,
        .pixels = &pixels,
    });
    try std.testing.expectEqual(@as(usize, 1), initial.uploads.len);
    try std.testing.expectEqualSlices(u8, &shared_bytes, initial.pixels);
    const residency = canvas.Residency{
        .resource = try canvas.FrameResourceRef.shared(shared_one),
        .format = .alpha8,
        .size = .{ .width = 2, .height = 1 },
    };

    try composer.removeSource(first);
    const one_owner = try composer.frame(&.{residency}, .{
        .uploads = &uploads,
        .removals = &removals,
        .commands = &commands,
        .pixels = &pixels,
    });
    try std.testing.expectEqual(@as(usize, 0), one_owner.removals.len);
    try std.testing.expectError(error.RetiredSource, composer.removeSource(first));
    const after_failed_remove = try composer.frame(&.{residency}, .{
        .uploads = &uploads,
        .removals = &removals,
        .commands = &commands,
        .pixels = &pixels,
    });
    try std.testing.expectEqual(@as(usize, 0), after_failed_remove.removals.len);

    try composer.removeSource(second);
    const retired = try composer.frame(&.{residency}, .{
        .uploads = &uploads,
        .removals = &removals,
        .commands = &commands,
        .pixels = &pixels,
    });
    try std.testing.expectEqual(@as(usize, 1), retired.removals.len);
    try std.testing.expectEqual(residency.resource, retired.removals[0]);

    const replacement = try composer.registerSource();
    const replacement_placement = [_]canvas.Composer.Placement{.{
        .source = replacement,
        .origin = .{ .x = 0, .y = 0 },
        .clip = .{ .x = 0, .y = 0, .width = 2, .height = 1 },
    }};
    try std.testing.expectError(
        error.InvalidIdentity,
        composer.applyCandidate(.{
            .changes = &.{.{ .source = replacement, .update = .{
                .revision = @fromBackingInt(1),
                .uploads = &.{upload},
                .removals = &.{},
                .commands = &.{command},
            } }},
            .composition = .{
                .surface = .{ .width = 2, .height = 1 },
                .sources = &replacement_placement,
            },
        }),
    );
    const shared_two = try shared(2, 1);
    var replacement_upload = upload;
    replacement_upload.resource = shared_two;
    const replacement_command = sharedAlphaCommand(shared_two, 2, 1);
    try composer.applyCandidate(.{
        .changes = &.{.{ .source = replacement, .update = .{
            .revision = @fromBackingInt(1),
            .uploads = &.{replacement_upload},
            .removals = &.{},
            .commands = &.{replacement_command},
        } }},
        .composition = .{
            .surface = .{ .width = 2, .height = 1 },
            .sources = &replacement_placement,
        },
    });
    const reused = try composer.frame(&.{}, .{
        .uploads = &uploads,
        .removals = &removals,
        .commands = &commands,
        .pixels = &pixels,
    });
    try std.testing.expectEqual(@as(usize, 1), reused.uploads.len);
    try std.testing.expectEqualSlices(u8, &shared_bytes, reused.pixels);
    try std.testing.expect(
        reused.uploads[0].resource.resource !=
            residency.resource.resource,
    );
}
