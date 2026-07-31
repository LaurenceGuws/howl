//! Proves selected one-run terminal text preparation and raster ownership.

const std = @import("std");
const render = @import("howl_render");
const selected = @import("selected_capabilities");
const fonts = if (selected.native_text) @import("test_fonts") else struct {};
const terminal = render.terminal;
const terminal_text = @import("terminal_text_test_capability");
const canvas = render.canvas;
const empty_scalars = terminal.ScalarBaseline.empty(1);
const empty_scalars_2 = terminal.ScalarBaseline.empty(2);
const empty_scalars_3 = terminal.ScalarBaseline.empty(3);
const empty_scalars_4 = terminal.ScalarBaseline.empty(4);

const metrics = terminal_text.CellMetrics{
    .width_px = 8,
    .height_px = 16,
    .baseline_px = 12,
};

fn rowGlyphResources(
    commands: []const canvas.Input,
    row_y: i32,
    row_height: u16,
    output: []canvas.ResourceRef,
) usize {
    var used: usize = 0;
    for (commands) |command| switch (command) {
        .alpha_mask => |mask| {
            if (mask.clip.y < row_y or
                mask.clip.y >= row_y + @as(i32, row_height))
                continue;
            std.debug.assert(used < output.len);
            output[used] = mask.resource.resource;
            used += 1;
        },
        else => {},
    };
    return used;
}

fn contentLimits() terminal.Content.Limits {
    return .{
        .cells = 16,
        .rows = 4,
        .images = 8,
        .placements = 8,
        .image_bytes = 4096,
        .glyphs = 32,
        .masks = 16,
        .commands = 64,
        .resources_per_update = 56,
        .upload_bytes = 8192,
        .raster_bytes = 8192,
        .decoration_bytes = 1024,
    };
}

test "Content rejects removal capacity below glyph mask image retirement floor" {
    var limits = contentLimits();
    limits.resources_per_update -= 1;
    if (comptime selected.native_text) {
        var map = try initMap();
        defer map.deinit();
        try std.testing.expectError(error.InvalidLimits, terminal.Content.init(std.testing.allocator, limits, &map));
    } else {
        try std.testing.expectError(error.InvalidLimits, terminal.Content.init(std.testing.allocator, limits, {}));
    }
}

test "terminal text public surface follows selected sources" {
    try std.testing.expectEqual(selected.native_text, @hasDecl(terminal_text, "FontStyle"));
    try std.testing.expectEqual(selected.native_text, @hasDecl(terminal_text, "FontKey"));
    try std.testing.expectEqual(selected.native_text, @hasDecl(terminal_text, "NativeGlyphKey"));
    try std.testing.expectEqual(selected.native_text, @hasDecl(terminal_text, "NativeScratch"));
    try std.testing.expectEqual(selected.native_text, @hasDecl(terminal_text, "FontMap"));
    try std.testing.expectEqual(selected.native_text, @hasDecl(terminal_text, "FontConfig"));
    try std.testing.expectEqual(
        selected.native_text,
        @hasDecl(terminal_text, "DecorationMetrics"),
    );
    try std.testing.expectEqual(
        selected.native_text,
        @hasDecl(terminal_text, "FontMapInitError"),
    );
    try std.testing.expect(@hasDecl(terminal_text, "GeneratedGlyphKey"));
    try std.testing.expect(@hasDecl(terminal_text, "CellMetrics"));
    try std.testing.expect(@hasDecl(terminal_text, "RowInput"));
    try std.testing.expect(@hasDecl(terminal_text, "LigatureMode"));
    try std.testing.expect(@hasDecl(terminal_text, "GlyphKey"));
    try std.testing.expect(@hasDecl(terminal_text, "PositionedGlyph"));
    try std.testing.expect(@hasDecl(terminal_text, "PreparedGlyphs"));
    try std.testing.expect(@hasDecl(terminal_text, "PreparedRun"));
    try std.testing.expect(@hasDecl(terminal_text, "Raster"));
    try std.testing.expect(@hasDecl(terminal_text, "PrepareError"));
    try std.testing.expect(@hasDecl(terminal_text, "RasterError"));
    try std.testing.expect(@hasDecl(terminal_text, "prepareNextRun"));
    try std.testing.expect(@hasDecl(terminal_text, "rasterizeGlyph"));
    try std.testing.expect(@hasDecl(terminal, "Content"));
    try std.testing.expectEqual(@as(usize, 1), @sizeOf(terminal_text.LigatureMode));
    try std.testing.expectEqual(@as(usize, 1), @sizeOf(terminal.Content.TextPolicy));
    if (comptime selected.native_text) {
        try std.testing.expect(terminal.FontMap == terminal_text.FontMap);
        try std.testing.expect(terminal.FontConfig == terminal_text.FontConfig);
        try std.testing.expect(terminal.Size == terminal_text.Size);
        try std.testing.expect(terminal.PointSize == terminal_text.PointSize);
        try std.testing.expect(terminal.Dpi == terminal_text.Dpi);
        try std.testing.expect(terminal.CellMetrics == terminal_text.CellMetrics);
        try std.testing.expect(terminal.LigatureMode == terminal_text.LigatureMode);
        try std.testing.expect(
            terminal.FontMapInitError == terminal_text.FontMapInitError,
        );
    }
}

test "Content rejects mismatched scalar baseline before candidate mutation" {
    var map = try initMap();
    defer deinitMap(&map);
    var content = try initContent(&map);
    defer content.deinit();
    var work = try terminal.Content.Work.init(std.testing.allocator, content.limits);
    defer work.deinit();
    const cells = [_]terminal.Cell{cell(if (selected.native_text) 'A' else 0x2500)};
    const rows = [_]terminal.LineGeometry{.single_width};
    try content.recover(.{
        .rows = 1,
        .cols = 1,
        .cursor = hiddenCursor(),
        .cells = &cells,
        .geometry = &rows,
    }, emptyImages());
    const revision_before = content.producer_revision;

    try std.testing.expectError(
        error.InvalidProjection,
        content.takeLocalUpdate(
            &work,
            terminal.ScalarBaseline.empty(2),
            contentGeometry(8, 16),
        ),
    );
    try std.testing.expectEqual(revision_before, content.producer_revision);
    const accepted = try content.takeLocalUpdate(
        &work,
        empty_scalars,
        contentGeometry(8, 16),
    );
    try std.testing.expectEqual(
        revision_before + 1,
        @backingInt(accepted.revision),
    );
    try std.testing.expect(accepted.commands.len != 0);
}

test "one larger Work alternates independent Content owners and rejects undersized work" {
    var map = try initMap();
    defer deinitMap(&map);
    var first = try initContent(&map);
    defer first.deinit();
    var second = try initContent(&map);
    defer second.deinit();
    var shared_limits = contentLimits();
    shared_limits.commands += 8;
    shared_limits.raster_bytes += 128;
    var shared = try terminal.Content.Work.init(std.testing.allocator, shared_limits);
    defer shared.deinit();
    var tiny_limits = contentLimits();
    tiny_limits.commands -= 1;
    var tiny = try terminal.Content.Work.init(std.testing.allocator, tiny_limits);
    defer tiny.deinit();

    const first_cells = [_]terminal.Cell{cell(if (selected.native_text) 'A' else 0x2500)};
    const second_cells = [_]terminal.Cell{cell(if (selected.native_text) 'B' else 0x2502)};
    const rows = [_]terminal.LineGeometry{.single_width};
    try first.recover(.{
        .rows = 1,
        .cols = 1,
        .cursor = hiddenCursor(),
        .cells = &first_cells,
        .geometry = &rows,
    }, emptyImages());
    try second.recover(.{
        .rows = 1,
        .cols = 1,
        .cursor = hiddenCursor(),
        .cells = &second_cells,
        .geometry = &rows,
    }, emptyImages());

    const first_update = try first.takeLocalUpdate(&shared, empty_scalars, contentGeometry(8, 16));
    const first_revision = first_update.revision;
    var copied: [8]canvas.Input = undefined;
    try std.testing.expect(first_update.commands.len <= copied.len);
    @memcpy(copied[0..first_update.commands.len], first_update.commands);
    const copied_count = first_update.commands.len;
    const second_update = try second.takeLocalUpdate(&shared, empty_scalars, contentGeometry(8, 16));
    try std.testing.expect(second_update.commands.len != 0);
    try std.testing.expectEqualDeep(
        copied[0..copied_count],
        (try first.takeLocalUpdate(&shared, empty_scalars, contentGeometry(8, 16))).commands,
    );
    try std.testing.expectError(
        error.WorkTooSmall,
        first.takeLocalUpdate(&tiny, empty_scalars, contentGeometry(8, 16)),
    );
    const reused = try first.takeLocalUpdate(&shared, empty_scalars, contentGeometry(8, 16));
    try std.testing.expectEqual(first_revision, reused.revision);
    try std.testing.expectEqualDeep(copied[0..copied_count], reused.commands);
}

test "retained terminal content emits one complete producer update" {
    var map = try initMap();
    defer deinitMap(&map);
    var content = if (selected.native_text)
        try terminal.Content.init(std.testing.allocator, contentLimits(), &map)
    else
        try terminal.Content.init(std.testing.allocator, contentLimits(), {});
    defer content.deinit();
    var work = try terminal.Content.Work.init(std.testing.allocator, content.limits);
    defer work.deinit();

    const cells = [_]terminal.Cell{cell(if (selected.native_text) 'A' else 0x2500)};
    const row_geometry = [_]terminal.LineGeometry{.single_width};
    const baseline = terminal.ProjectionBaseline{
        .rows = 1,
        .cols = 1,
        .cursor = hiddenCursor(),
        .cells = &cells,
        .geometry = &row_geometry,
    };
    try content.recover(baseline, emptyImages());
    const update = try content.takeLocalUpdate(&work, empty_scalars, .{
        .x = 0,
        .y = 0,
        .clip = .{ .x = 0, .y = 0, .width = 8, .height = 16 },
        .metrics = metrics,
        .generated_box = generatedBoxConfig(),
        .underline_y = 14,
        .underline_height = 1,
        .strike_y = 8,
        .strike_height = 1,
    });
    try std.testing.expect(@backingInt(update.revision) != 0);
    try std.testing.expect(update.commands.len >= 1);
    try std.testing.expect(update.commands[0] == .solid);
    const resized = try content.takeLocalUpdate(&work, empty_scalars, contentGeometry(7, 16));
    try std.testing.expectEqual(
        @backingInt(update.revision) + 1,
        @backingInt(resized.revision),
    );
    try std.testing.expectEqual(@as(u16, 7), resized.commands[0].solid.clip.width);
    const resized_revision = @backingInt(resized.revision);
    var resized_commands: [4]canvas.Input = undefined;
    try std.testing.expect(resized.commands.len <= resized_commands.len);
    @memcpy(resized_commands[0..resized.commands.len], resized.commands);
    const resized_command_count = resized.commands.len;
    const drained = try content.takeLocalUpdate(&work, empty_scalars, contentGeometry(7, 16));
    try std.testing.expectEqual(resized_revision, @backingInt(drained.revision));
    try std.testing.expectEqual(@as(usize, 0), drained.uploads.len);
    try std.testing.expectEqual(@as(usize, 0), drained.removals.len);
    try std.testing.expectEqualDeep(
        resized_commands[0..resized_command_count],
        drained.commands,
    );
}

test "retained terminal content accepts the initial empty VT image identity" {
    var map = try initMap();
    defer deinitMap(&map);
    var content = if (selected.native_text)
        try terminal.Content.init(std.testing.allocator, contentLimits(), &map)
    else
        try terminal.Content.init(std.testing.allocator, contentLimits(), {});
    defer content.deinit();
    var work = try terminal.Content.Work.init(std.testing.allocator, content.limits);
    defer work.deinit();
    const cells = [_]terminal.Cell{cell(if (selected.native_text) 'A' else 0x2500)};
    const geometry = [_]terminal.LineGeometry{.single_width};
    try content.recover(.{
        .rows = 1,
        .cols = 1,
        .cursor = hiddenCursor(),
        .cells = &cells,
        .geometry = &geometry,
    }, .{
        .generation = 0,
        .content_generation = 0,
        .pixels = &.{},
        .uploads = &.{},
        .removals = &.{},
        .placements = &.{},
    });
    const update = try content.takeLocalUpdate(&work, empty_scalars, contentGeometry(8, 16));
    try std.testing.expect(update.commands.len != 0);
}

test "retained terminal content applies sparse rows and rejects malformed updates byte-exactly" {
    var map = try initMap();
    defer deinitMap(&map);
    var content = try initContent(&map);
    defer content.deinit();
    var work = try terminal.Content.Work.init(std.testing.allocator, content.limits);
    defer work.deinit();

    var cells = [_]terminal.Cell{ cell(0), cell(0), cell(0), cell(0) };
    cells[0].background.r = 1;
    cells[1].background.r = 2;
    cells[2].background.r = 3;
    cells[3].background.r = 4;
    const row_geometry = [_]terminal.LineGeometry{ .single_width, .double_width };
    try content.recover(.{
        .rows = 2,
        .cols = 2,
        .cursor = hiddenCursor(),
        .cells = &cells,
        .geometry = &row_geometry,
    }, emptyImages());
    const before = try content.takeLocalUpdate(&work, empty_scalars_4, contentGeometry(16, 32));
    const before_revision = @backingInt(before.revision);
    try std.testing.expectEqual(@as(u8, 3), before.commands[2].solid.color.r);

    var changed = cell(0);
    changed.background.r = 9;
    const patches = [_]terminal.RowPatch{.{
        .row = 0,
        .start_col = 1,
        .cell_offset = 0,
        .cell_count = 1,
        .geometry = .single_width,
        .damage_start = 1,
        .damage_end = 1,
    }};
    try content.apply(.{
        .rows = 2,
        .cols = 2,
        .full = false,
        .cells = &.{changed},
        .row_patches = &patches,
        .cursor = hiddenCursor(),
    }, null);
    const after = try content.takeLocalUpdate(&work, empty_scalars_4, contentGeometry(16, 32));
    try std.testing.expectEqual(before_revision + 1, @backingInt(after.revision));
    try std.testing.expectEqual(@as(u8, 1), after.commands[0].solid.color.r);
    try std.testing.expectEqual(@as(u8, 9), after.commands[1].solid.color.r);
    try std.testing.expectEqual(@as(u8, 3), after.commands[2].solid.color.r);
    try std.testing.expectEqual(@as(u8, 4), after.commands[3].solid.color.r);

    const malformed = [_]terminal.RowPatch{.{
        .row = 0,
        .start_col = 0,
        .cell_offset = 1,
        .cell_count = 1,
        .geometry = .single_width,
        .damage_start = 0,
        .damage_end = 0,
    }};
    try std.testing.expectError(error.InvalidUpdate, content.apply(.{
        .rows = 2,
        .cols = 2,
        .full = false,
        .cells = &.{changed},
        .row_patches = &malformed,
        .cursor = hiddenCursor(),
    }, null));
    const overflowing = [_]terminal.RowPatch{.{
        .row = 0,
        .start_col = 0,
        .cell_offset = std.math.maxInt(usize),
        .cell_count = 1,
        .geometry = .single_width,
        .damage_start = 0,
        .damage_end = 0,
    }};
    try std.testing.expectError(error.InvalidUpdate, content.apply(.{
        .rows = 2,
        .cols = 2,
        .full = false,
        .cells = &.{changed},
        .row_patches = &overflowing,
        .cursor = hiddenCursor(),
    }, null));
    const unchanged = try content.takeLocalUpdate(&work, empty_scalars_4, contentGeometry(16, 32));
    try std.testing.expectEqual(@backingInt(after.revision), @backingInt(unchanged.revision));
    try std.testing.expectEqualDeep(after.commands, unchanged.commands);
}

test "retained terminal content preserves exact image replacement removal and ordering" {
    var map = try initMap();
    defer deinitMap(&map);
    var content = try initContent(&map);
    defer content.deinit();
    var work = try terminal.Content.Work.init(std.testing.allocator, content.limits);
    defer work.deinit();

    const cells = [_]terminal.Cell{cell(0)};
    const row_geometry = [_]terminal.LineGeometry{.single_width};
    const first_pixels = [_]u8{ 1, 2, 3, 255 };
    const first_upload = [_]render.terminal_images.ImageUpload{.{
        .identity = .{ .id = 7, .generation = 1 },
        .width = 1,
        .height = 1,
        .pixel_offset = 0,
        .pixel_count = 4,
    }};
    const first_placement = [_]render.terminal_images.ImagePlacement{.{
        .image_id = 7,
        .generation = 1,
        .row = 0,
        .col = 0,
        .pixel_width = 1,
        .pixel_height = 1,
        .z = -1,
    }};
    try content.recover(.{
        .rows = 1,
        .cols = 1,
        .cursor = hiddenCursor(),
        .cells = &cells,
        .geometry = &row_geometry,
    }, .{
        .generation = 1,
        .content_generation = 1,
        .pixels = &first_pixels,
        .uploads = &first_upload,
        .removals = &.{},
        .placements = &first_placement,
    });
    const first = try content.takeLocalUpdate(&work, empty_scalars, contentGeometry(8, 16));
    try std.testing.expectEqual(@as(usize, 1), first.uploads.len);
    try std.testing.expectEqual(canvas.ResourceFormat.rgba8, first.uploads[0].format);
    try std.testing.expect(first.commands[0] == .solid);
    try std.testing.expect(first.commands[1] == .rgba);
    const resource_id = @backingInt(first.uploads[0].resource.resource);

    const replacement_pixels = [_]u8{ 9, 8, 7, 255 };
    const replacement_upload = [_]render.terminal_images.ImageUpload{.{
        .identity = .{ .id = 7, .generation = 2 },
        .width = 1,
        .height = 1,
        .pixel_offset = 0,
        .pixel_count = 4,
    }};
    var replacement_placement = first_placement;
    replacement_placement[0].generation = 2;
    try content.apply(unchangedProjection(1, 1), .{
        .generation = 2,
        .content_generation = 2,
        .pixels = &replacement_pixels,
        .uploads = &replacement_upload,
        .removals = &.{},
        .placements = &replacement_placement,
    });
    const replacement = try content.takeLocalUpdate(&work, empty_scalars, contentGeometry(8, 16));
    try std.testing.expectEqual(@as(usize, 1), replacement.uploads.len);
    try std.testing.expectEqual(
        resource_id,
        @backingInt(replacement.uploads[0].resource.resource),
    );
    try std.testing.expectEqual(
        @as(u64, 2),
        @backingInt(replacement.uploads[0].resource.generation),
    );
    try std.testing.expectEqualSlices(u8, &replacement_pixels, replacement.uploads[0].pixels.bytes);
    const replacement_revision = @backingInt(replacement.revision);
    try std.testing.expectError(error.StaleUpdate, content.apply(unchangedProjection(1, 1), .{
        .generation = 2,
        .content_generation = 2,
        .pixels = &.{},
        .uploads = &.{},
        .removals = &.{},
        .placements = &replacement_placement,
    }));
    const unknown_placement = [_]render.terminal_images.ImagePlacement{.{
        .image_id = 99,
        .generation = 1,
        .row = 0,
        .col = 0,
        .pixel_width = 1,
        .pixel_height = 1,
    }};
    try std.testing.expectError(error.InvalidUpdate, content.apply(unchangedProjection(1, 1), .{
        .generation = 3,
        .content_generation = 2,
        .pixels = &.{},
        .uploads = &.{},
        .removals = &.{},
        .placements = &unknown_placement,
    }));
    const still_replacement = try content.takeLocalUpdate(&work, empty_scalars, contentGeometry(8, 16));
    try std.testing.expectEqual(
        replacement_revision,
        @backingInt(still_replacement.revision),
    );

    var animated_placement = replacement_placement;
    animated_placement[0].generation = 9;
    animated_placement[0].z = 1;
    try content.apply(unchangedProjection(1, 1), .{
        .generation = 3,
        .content_generation = 2,
        .pixels = &.{},
        .uploads = &.{},
        .removals = &.{},
        .placements = &animated_placement,
    });
    const animated = try content.takeLocalUpdate(&work, empty_scalars, contentGeometry(8, 16));
    try std.testing.expectEqual(@as(usize, 0), animated.uploads.len);
    try std.testing.expect(animated.commands[animated.commands.len - 1] == .rgba);

    try content.apply(unchangedProjection(1, 1), .{
        .generation = 4,
        .content_generation = 3,
        .pixels = &.{},
        .uploads = &.{},
        .removals = &.{7},
        .placements = &.{},
    });
    const removed = try content.takeLocalUpdate(&work, empty_scalars, contentGeometry(8, 16));
    try std.testing.expectEqual(@as(usize, 1), removed.removals.len);
    try std.testing.expectEqual(resource_id, @backingInt(removed.removals[0].resource.resource));
    try std.testing.expectEqual(@as(usize, 0), removed.uploads.len);
}

test "terminal content commits projection and optional images once per transaction" {
    var map = try initMap();
    defer deinitMap(&map);
    var content = try initContent(&map);
    defer content.deinit();
    var work = try terminal.Content.Work.init(std.testing.allocator, content.limits);
    defer work.deinit();

    const original_cells = [_]terminal.Cell{cell(0)};
    const row_geometry = [_]terminal.LineGeometry{.single_width};
    try content.recover(.{
        .rows = 1,
        .cols = 1,
        .cursor = hiddenCursor(),
        .cells = &original_cells,
        .geometry = &row_geometry,
    }, emptyImages());
    const initial = try content.takeLocalUpdate(&work, empty_scalars, contentGeometry(8, 16));

    var changed = cell(0);
    changed.background = .{ .r = 1, .g = 2, .b = 3 };
    const changed_cells = [_]terminal.Cell{changed};
    const patch = [_]terminal.RowPatch{.{
        .row = 0,
        .start_col = 0,
        .cell_offset = 0,
        .cell_count = 1,
        .geometry = .single_width,
        .damage_start = 0,
        .damage_end = 0,
    }};
    try content.apply(.{
        .rows = 1,
        .cols = 1,
        .full = false,
        .cells = &changed_cells,
        .row_patches = &patch,
        .cursor = hiddenCursor(),
    }, null);
    const projection_only = try content.takeLocalUpdate(&work, empty_scalars, contentGeometry(8, 16));
    try std.testing.expectEqual(
        @backingInt(initial.revision) + 1,
        @backingInt(projection_only.revision),
    );

    const pixels = [_]u8{ 7, 8, 9, 255 };
    const upload = [_]render.terminal_images.ImageUpload{.{
        .identity = .{ .id = 41, .generation = 1 },
        .width = 1,
        .height = 1,
        .pixel_offset = 0,
        .pixel_count = 4,
    }};
    try content.apply(unchangedProjection(1, 1), .{
        .generation = 2,
        .content_generation = 2,
        .pixels = &pixels,
        .uploads = &upload,
        .removals = &.{},
        .placements = &.{},
    });
    const image_only = try content.takeLocalUpdate(&work, empty_scalars, contentGeometry(8, 16));
    try std.testing.expectEqual(
        @backingInt(projection_only.revision) + 1,
        @backingInt(image_only.revision),
    );
    try std.testing.expectEqual(@as(usize, 1), image_only.uploads.len);

    try content.apply(.{
        .rows = 1,
        .cols = 1,
        .full = false,
        .cells = &original_cells,
        .row_patches = &patch,
        .cursor = hiddenCursor(),
    }, .{
        .generation = 3,
        .content_generation = 3,
        .pixels = &.{},
        .uploads = &.{},
        .removals = &.{41},
        .placements = &.{},
    });
    const combined = try content.takeLocalUpdate(&work, empty_scalars, contentGeometry(8, 16));
    try std.testing.expectEqual(
        @backingInt(image_only.revision) + 1,
        @backingInt(combined.revision),
    );
    try std.testing.expectEqual(@as(usize, 1), combined.removals.len);
}

test "image deltas require initialization and remove only transferred generations" {
    var map = try initMap();
    defer deinitMap(&map);
    var content = try initContent(&map);
    defer content.deinit();
    var work = try terminal.Content.Work.init(std.testing.allocator, content.limits);
    defer work.deinit();

    try std.testing.expectError(
        error.InvalidUpdate,
        content.apply(unchangedProjection(1, 1), emptyImages()),
    );
    const cells = [_]terminal.Cell{cell(0)};
    const row_geometry = [_]terminal.LineGeometry{.single_width};
    try content.recover(.{
        .rows = 1,
        .cols = 1,
        .cursor = hiddenCursor(),
        .cells = &cells,
        .geometry = &row_geometry,
    }, emptyImages());

    const pixels = [_]u8{ 1, 2, 3, 255 };
    const created = [_]render.terminal_images.ImageUpload{.{
        .identity = .{ .id = 11, .generation = 1 },
        .width = 1,
        .height = 1,
        .pixel_offset = 0,
        .pixel_count = 4,
    }};
    try content.apply(unchangedProjection(1, 1), .{
        .generation = 2,
        .content_generation = 2,
        .pixels = &pixels,
        .uploads = &created,
        .removals = &.{},
        .placements = &.{},
    });
    try content.apply(unchangedProjection(1, 1), .{
        .generation = 3,
        .content_generation = 3,
        .pixels = &.{},
        .uploads = &.{},
        .removals = &.{11},
        .placements = &.{},
    });
    const never_transferred = try content.takeLocalUpdate(&work, empty_scalars, contentGeometry(8, 16));
    try std.testing.expectEqual(@as(usize, 0), never_transferred.uploads.len);
    try std.testing.expectEqual(@as(usize, 0), never_transferred.removals.len);

    const recreated = [_]render.terminal_images.ImageUpload{.{
        .identity = .{ .id = 11, .generation = 2 },
        .width = 1,
        .height = 1,
        .pixel_offset = 0,
        .pixel_count = 4,
    }};
    try content.apply(unchangedProjection(1, 1), .{
        .generation = 4,
        .content_generation = 4,
        .pixels = &pixels,
        .uploads = &recreated,
        .removals = &.{},
        .placements = &.{},
    });
    const transferred = try content.takeLocalUpdate(&work, empty_scalars, contentGeometry(8, 16));
    try std.testing.expectEqual(@as(usize, 1), transferred.uploads.len);
    const transferred_resource = transferred.uploads[0].resource;

    const replacement_pixels = [_]u8{ 9, 8, 7, 255 };
    const replacement = [_]render.terminal_images.ImageUpload{.{
        .identity = .{ .id = 11, .generation = 3 },
        .width = 1,
        .height = 1,
        .pixel_offset = 0,
        .pixel_count = 4,
    }};
    try content.apply(unchangedProjection(1, 1), .{
        .generation = 5,
        .content_generation = 5,
        .pixels = &replacement_pixels,
        .uploads = &replacement,
        .removals = &.{},
        .placements = &.{},
    });
    try content.apply(unchangedProjection(1, 1), .{
        .generation = 6,
        .content_generation = 6,
        .pixels = &.{},
        .uploads = &.{},
        .removals = &.{11},
        .placements = &.{},
    });
    const replacement_never_transferred = try content.takeLocalUpdate(&work, empty_scalars, contentGeometry(8, 16));
    try std.testing.expectEqual(@as(usize, 0), replacement_never_transferred.uploads.len);
    try std.testing.expectEqual(@as(usize, 1), replacement_never_transferred.removals.len);
    try std.testing.expectEqualDeep(
        transferred_resource,
        replacement_never_transferred.removals[0].resource,
    );
}

test "retained terminal glyph resources rasterize once and survive sparse updates" {
    var map = try initMap();
    defer deinitMap(&map);
    var content = try initContent(&map);
    defer content.deinit();
    var work = try terminal.Content.Work.init(std.testing.allocator, content.limits);
    defer work.deinit();

    const codepoint: u21 = if (selected.native_text) 'A' else 0x2500;
    const cells = [_]terminal.Cell{cell(codepoint)};
    const row_geometry = [_]terminal.LineGeometry{.single_width};
    const block_cursor = terminal.Cursor{
        .row = 0,
        .col = 0,
        .visible = true,
        .shape = .block,
        .blink = false,
        .color = .{ .r = 10, .g = 20, .b = 30 },
        .text_color = .{ .r = 40, .g = 50, .b = 60 },
    };
    try content.recover(.{
        .rows = 1,
        .cols = 1,
        .cursor = block_cursor,
        .cells = &cells,
        .geometry = &row_geometry,
    }, emptyImages());
    const first = try content.takeLocalUpdate(&work, empty_scalars, contentGeometry(8, 16));
    var glyph_uploads: usize = 0;
    for (first.uploads) |upload| if (upload.format == .alpha8) {
        glyph_uploads += 1;
    };
    try std.testing.expectEqual(@as(usize, 1), glyph_uploads);
    var cursor_fill = false;
    var recolored_glyph = false;
    for (first.commands) |command| switch (command) {
        .solid => |solid| cursor_fill = cursor_fill or
            std.meta.eql(solid.color, canvas.Color{ .r = 10, .g = 20, .b = 30, .a = 255 }),
        .alpha_mask => |mask| recolored_glyph = recolored_glyph or
            std.meta.eql(mask.color, canvas.Color{ .r = 40, .g = 50, .b = 60, .a = 255 }),
        .rgba => {},
    };
    try std.testing.expect(cursor_fill);
    try std.testing.expect(recolored_glyph);
    const first_revision = @backingInt(first.revision);

    const second = try content.takeLocalUpdate(&work, empty_scalars, contentGeometry(8, 16));
    try std.testing.expectEqual(first_revision, @backingInt(second.revision));
    try std.testing.expectEqual(@as(usize, 0), second.uploads.len);

    var changed = cells[0];
    changed.background.b = 22;
    const patch = [_]terminal.RowPatch{.{
        .row = 0,
        .start_col = 0,
        .cell_offset = 0,
        .cell_count = 1,
        .geometry = .single_width,
        .damage_start = 0,
        .damage_end = 0,
    }};
    try content.apply(.{
        .rows = 1,
        .cols = 1,
        .full = false,
        .cells = &.{changed},
        .row_patches = &patch,
        .cursor = block_cursor,
    }, null);
    const sparse = try content.takeLocalUpdate(&work, empty_scalars, contentGeometry(8, 16));
    try std.testing.expectEqual(@as(usize, 0), sparse.uploads.len);
    try std.testing.expectEqual(@as(u8, 22), sparse.commands[0].solid.color.b);

    changed.codepoint = if (selected.native_text) 'B' else 0x2502;
    try content.apply(.{
        .rows = 1,
        .cols = 1,
        .full = false,
        .cells = &.{changed},
        .row_patches = &patch,
        .cursor = block_cursor,
    }, null);
    const replaced = try content.takeLocalUpdate(&work, empty_scalars, contentGeometry(8, 16));
    try std.testing.expectEqual(@as(usize, 1), replaced.uploads.len);
    try std.testing.expectEqual(@as(usize, 1), replaced.removals.len);
    try std.testing.expect(
        @backingInt(replaced.uploads[0].resource.resource) >
            @backingInt(replaced.removals[0].resource.resource),
    );
}

test "zero-area native glyphs retain metrics without logical resources" {
    if (comptime !selected.native_text) return error.SkipZigTest;
    var map = try initMap();
    defer deinitMap(&map);
    var content = try initContent(&map);
    defer content.deinit();
    var work = try terminal.Content.Work.init(std.testing.allocator, content.limits);
    defer work.deinit();

    const row_geometry = [_]terminal.LineGeometry{.single_width};
    const patch = [_]terminal.RowPatch{.{
        .row = 0,
        .start_col = 0,
        .cell_offset = 0,
        .cell_count = 1,
        .geometry = .single_width,
        .damage_start = 0,
        .damage_end = 0,
    }};
    try content.recover(.{
        .rows = 1,
        .cols = 1,
        .cursor = hiddenCursor(),
        .cells = &.{cell(' ')},
        .geometry = &row_geometry,
    }, emptyImages());
    const blank = try content.takeLocalUpdate(&work, empty_scalars, contentGeometry(8, 16));
    try std.testing.expectEqual(@as(usize, 0), blank.uploads.len);
    try std.testing.expectEqual(@as(usize, 0), blank.removals.len);

    try content.apply(.{
        .rows = 1,
        .cols = 1,
        .full = false,
        .cells = &.{cell('A')},
        .row_patches = &patch,
        .cursor = hiddenCursor(),
    }, null);
    const visible = try content.takeLocalUpdate(&work, empty_scalars, contentGeometry(8, 16));
    try std.testing.expectEqual(@as(usize, 1), visible.uploads.len);

    try content.apply(.{
        .rows = 1,
        .cols = 1,
        .full = false,
        .cells = &.{cell(' ')},
        .row_patches = &patch,
        .cursor = hiddenCursor(),
    }, null);
    const blank_again = try content.takeLocalUpdate(&work, empty_scalars, contentGeometry(8, 16));
    try std.testing.expectEqual(@as(usize, 0), blank_again.uploads.len);
    try std.testing.expectEqual(@as(usize, 1), blank_again.removals.len);

    try content.apply(.{
        .rows = 1,
        .cols = 1,
        .full = false,
        .cells = &.{cell(0)},
        .row_patches = &patch,
        .cursor = hiddenCursor(),
    }, null);
    const retired_blank = try content.takeLocalUpdate(&work, empty_scalars, contentGeometry(8, 16));
    try std.testing.expectEqual(@as(usize, 0), retired_blank.uploads.len);
    try std.testing.expectEqual(@as(usize, 0), retired_blank.removals.len);
}

test "retained terminal content preserves audited decoration placement and color" {
    var map = try initMap();
    defer deinitMap(&map);
    var content = try initContent(&map);
    defer content.deinit();
    var work = try terminal.Content.Work.init(std.testing.allocator, content.limits);
    defer work.deinit();

    var cells = [_]terminal.Cell{ cell(0), cell(0), cell(0) };
    cells[0].underline = true;
    cells[0].underline_style = .double;
    cells[0].underline_color = .{ .r = 1, .g = 2, .b = 3 };
    cells[0].strikethrough = true;
    cells[0].foreground = .{ .r = 4, .g = 5, .b = 6 };
    cells[1].underline = true;
    cells[1].underline_style = .dotted;
    cells[2].underline = true;
    cells[2].underline_style = .curly;
    const row_geometry = [_]terminal.LineGeometry{.single_width};
    try content.recover(.{
        .rows = 1,
        .cols = 3,
        .cursor = hiddenCursor(),
        .cells = &cells,
        .geometry = &row_geometry,
    }, emptyImages());
    const update = try content.takeLocalUpdate(&work, empty_scalars_3, contentGeometry(24, 16));
    try std.testing.expectEqual(@as(usize, 6), update.commands.len);
    try std.testing.expectEqual(@as(i32, 12), update.commands[1].solid.rect.y);
    try std.testing.expectEqual(@as(i32, 14), update.commands[2].solid.rect.y);
    try std.testing.expectEqualDeep(
        canvas.Color{ .r = 4, .g = 5, .b = 6, .a = 255 },
        update.commands[3].solid.color,
    );
    try std.testing.expect(update.commands[4] == .alpha_mask);
    try std.testing.expect(update.commands[5] == .alpha_mask);
    try std.testing.expectEqual(@as(usize, 2), update.uploads.len);
    try std.testing.expectEqual(canvas.ResourceFormat.alpha8, update.uploads[0].format);
    try std.testing.expectEqual(canvas.ResourceFormat.alpha8, update.uploads[1].format);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0, 0, 0, 0, 0, 0, 0, 0, 255, 0, 255, 0, 255, 0, 255, 0 },
        update.uploads[0].pixels.bytes,
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0, 255, 0, 255, 0, 255, 0, 255, 255, 0, 255, 0, 255, 0, 255, 0 },
        update.uploads[1].pixels.bytes,
    );

    const unchanged = try content.takeLocalUpdate(&work, empty_scalars_3, contentGeometry(24, 16));
    try std.testing.expectEqual(@as(usize, 0), unchanged.uploads.len);
    try std.testing.expectEqual(@backingInt(update.revision), @backingInt(unchanged.revision));
}

test "decoration masks retire transactionally across geometry churn" {
    var map = try initMap();
    defer deinitMap(&map);
    var limits = contentLimits();
    limits.masks = 1;
    var content = if (selected.native_text)
        try terminal.Content.init(std.testing.allocator, limits, &map)
    else
        try terminal.Content.init(std.testing.allocator, limits, {});
    defer content.deinit();
    var work = try terminal.Content.Work.init(std.testing.allocator, content.limits);
    defer work.deinit();

    var decorated = cell(0);
    decorated.underline = true;
    decorated.underline_style = .dotted;
    const row_geometry = [_]terminal.LineGeometry{.single_width};
    try content.recover(.{
        .rows = 1,
        .cols = 1,
        .cursor = hiddenCursor(),
        .cells = &.{decorated},
        .geometry = &row_geometry,
    }, emptyImages());
    const first = try content.takeLocalUpdate(&work, empty_scalars, contentGeometry(8, 16));
    try std.testing.expectEqual(@as(usize, 1), first.uploads.len);
    try std.testing.expectEqual(@as(usize, 0), first.removals.len);
    const first_resource = first.uploads[0].resource;

    var seven = contentGeometry(7, 16);
    seven.metrics.width_px = 7;
    const second = try content.takeLocalUpdate(&work, empty_scalars, seven);
    try std.testing.expectEqual(@as(usize, 1), second.uploads.len);
    try std.testing.expectEqual(@as(usize, 1), second.removals.len);
    try std.testing.expectEqualDeep(first_resource, second.removals[0].resource);
    const second_resource = second.uploads[0].resource;

    var six = contentGeometry(6, 16);
    six.metrics.width_px = 6;
    const third = try content.takeLocalUpdate(&work, empty_scalars, six);
    try std.testing.expectEqual(@as(usize, 1), third.uploads.len);
    try std.testing.expectEqual(@as(usize, 1), third.removals.len);
    try std.testing.expectEqualDeep(second_resource, third.removals[0].resource);
    const third_resource = third.uploads[0].resource;

    var conflicting = [_]terminal.Cell{ decorated, decorated };
    conflicting[1].underline_style = .curly;
    try content.recover(.{
        .rows = 1,
        .cols = 2,
        .cursor = hiddenCursor(),
        .cells = &conflicting,
        .geometry = &row_geometry,
    }, .{
        .generation = 2,
        .content_generation = 1,
        .pixels = &.{},
        .uploads = &.{},
        .removals = &.{},
        .placements = &.{},
    });
    try std.testing.expectError(
        error.MaskLimit,
        content.takeLocalUpdate(&work, empty_scalars_2, contentGeometry(12, 16)),
    );
    conflicting[1].underline_style = .dotted;
    const patch = [_]terminal.RowPatch{.{
        .row = 0,
        .start_col = 1,
        .cell_offset = 0,
        .cell_count = 1,
        .geometry = .single_width,
        .damage_start = 1,
        .damage_end = 1,
    }};
    try content.apply(.{
        .rows = 1,
        .cols = 2,
        .full = false,
        .cells = conflicting[1..],
        .row_patches = &patch,
        .cursor = hiddenCursor(),
    }, null);
    const recovered = try content.takeLocalUpdate(&work, empty_scalars_2, contentGeometry(12, 16));
    try std.testing.expectEqual(@as(usize, 1), recovered.uploads.len);
    try std.testing.expectEqual(@as(usize, 1), recovered.removals.len);
    try std.testing.expectEqualDeep(third_resource, recovered.removals[0].resource);
    try std.testing.expectEqual(
        @backingInt(third_resource.resource) + 1,
        @backingInt(recovered.uploads[0].resource.resource),
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0, 0, 0, 0, 0, 0, 0, 0, 255, 0, 255, 0, 255, 0, 255, 0 },
        recovered.uploads[0].pixels.bytes,
    );
}

test "retained terminal content preserves OSC 66 scaling alignment and clipping" {
    var map = try initMap();
    defer deinitMap(&map);
    var content = try initContent(&map);
    defer content.deinit();
    var work = try terminal.Content.Work.init(std.testing.allocator, content.limits);
    defer work.deinit();

    var cells = [_]terminal.Cell{cell(0x2500)};
    cells[0].sizing = .{
        .width = 4,
        .height = 2,
        .subscale_n = 1,
        .subscale_d = 2,
        .vertical_align = 2,
        .horizontal_align = 1,
    };
    const row_geometry = [_]terminal.LineGeometry{.single_width};
    try content.recover(.{
        .rows = 1,
        .cols = 1,
        .cursor = hiddenCursor(),
        .cells = &cells,
        .geometry = &row_geometry,
    }, emptyImages());
    const update = try content.takeLocalUpdate(&work, empty_scalars, .{
        .x = 3,
        .y = 5,
        .clip = .{ .x = 3, .y = 5, .width = 32, .height = 16 },
        .metrics = metrics,
        .generated_box = generatedBoxConfig(),
        .underline_y = 14,
        .underline_height = 1,
        .strike_y = 8,
        .strike_height = 1,
    });
    try std.testing.expectEqual(@as(usize, 2), update.commands.len);
    try std.testing.expectEqualDeep(
        canvas.Rect{ .x = 3, .y = 5, .width = 8, .height = 16 },
        update.commands[0].solid.rect,
    );
    try std.testing.expectEqualDeep(
        canvas.Rect{ .x = 19, .y = 13, .width = 8, .height = 16 },
        update.commands[1].alpha_mask.destination,
    );
    try std.testing.expectEqualDeep(
        canvas.Rect{ .x = 19, .y = 13, .width = 8, .height = 8 },
        update.commands[1].alpha_mask.clip,
    );
}

test "retained terminal content preserves DEC double-width placement" {
    var map = try initMap();
    defer deinitMap(&map);
    var content = try initContent(&map);
    defer content.deinit();
    var work = try terminal.Content.Work.init(std.testing.allocator, content.limits);
    defer work.deinit();
    const cells = [_]terminal.Cell{cell(0x2500)};
    const row_geometry = [_]terminal.LineGeometry{.double_width};
    try content.recover(.{
        .rows = 1,
        .cols = 1,
        .cursor = hiddenCursor(),
        .cells = &cells,
        .geometry = &row_geometry,
    }, emptyImages());
    const update = try content.takeLocalUpdate(&work, empty_scalars, contentGeometry(16, 16));
    try std.testing.expectEqualDeep(
        canvas.Rect{ .x = 0, .y = 0, .width = 16, .height = 16 },
        update.commands[0].solid.rect,
    );
    try std.testing.expectEqualDeep(
        canvas.Rect{ .x = 0, .y = 0, .width = 16, .height = 16 },
        update.commands[1].alpha_mask.destination,
    );
}

test "retained terminal content construction rolls back every owned allocation" {
    var map = try initMap();
    defer deinitMap(&map);
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        constructContent,
        .{&map},
    );
}

test "glyph cache capacity failure rolls back identity and remains reusable" {
    var map = try initMap();
    defer deinitMap(&map);
    var limits = contentLimits();
    limits.glyphs = 1;
    var content = if (selected.native_text)
        try terminal.Content.init(std.testing.allocator, limits, &map)
    else
        try terminal.Content.init(std.testing.allocator, limits, {});
    defer content.deinit();
    var work = try terminal.Content.Work.init(std.testing.allocator, content.limits);
    defer work.deinit();

    const first_codepoint: u21 = if (selected.native_text) 'A' else 0x2500;
    const second_codepoint: u21 = if (selected.native_text) 'B' else 0x2502;
    const cells = [_]terminal.Cell{ cell(first_codepoint), cell(second_codepoint) };
    const row_geometry = [_]terminal.LineGeometry{.single_width};
    try content.recover(.{
        .rows = 1,
        .cols = 2,
        .cursor = hiddenCursor(),
        .cells = &cells,
        .geometry = &row_geometry,
    }, emptyImages());
    try std.testing.expectError(
        error.GlyphLimit,
        content.takeLocalUpdate(&work, empty_scalars_2, contentGeometry(16, 16)),
    );

    const replacement = cell(first_codepoint);
    const patch = [_]terminal.RowPatch{.{
        .row = 0,
        .start_col = 1,
        .cell_offset = 0,
        .cell_count = 1,
        .geometry = .single_width,
        .damage_start = 1,
        .damage_end = 1,
    }};
    try content.apply(.{
        .rows = 1,
        .cols = 2,
        .full = false,
        .cells = &.{replacement},
        .row_patches = &patch,
        .cursor = hiddenCursor(),
    }, null);
    const recovered = try content.takeLocalUpdate(&work, empty_scalars_2, contentGeometry(16, 16));
    try std.testing.expectEqual(@as(usize, 1), recovered.uploads.len);
    try std.testing.expectEqual(
        @as(u64, 1),
        @backingInt(recovered.uploads[0].resource.resource),
    );
}

test "incompatible sparse geometry requires explicit full recovery" {
    var map = try initMap();
    defer deinitMap(&map);
    var content = try initContent(&map);
    defer content.deinit();
    var work = try terminal.Content.Work.init(std.testing.allocator, content.limits);
    defer work.deinit();

    const cells = [_]terminal.Cell{cell(0)};
    const row_geometry = [_]terminal.LineGeometry{.single_width};
    try content.recover(.{
        .rows = 1,
        .cols = 1,
        .cursor = hiddenCursor(),
        .cells = &cells,
        .geometry = &row_geometry,
    }, emptyImages());
    try std.testing.expectError(error.InvalidUpdate, content.apply(.{
        .rows = 1,
        .cols = 2,
        .full = false,
        .cells = &.{},
        .row_patches = &.{},
        .cursor = hiddenCursor(),
    }, null));
    const two_cells = [_]terminal.Cell{ cell(0), cell(0) };
    try content.recover(.{
        .rows = 1,
        .cols = 2,
        .cursor = hiddenCursor(),
        .cells = &two_cells,
        .geometry = &row_geometry,
    }, .{
        .generation = 2,
        .content_generation = 1,
        .pixels = &.{},
        .uploads = &.{},
        .removals = &.{},
        .placements = &.{},
    });
    const recovered = try content.takeLocalUpdate(&work, empty_scalars_2, contentGeometry(16, 16));
    try std.testing.expectEqual(@as(usize, 1), recovered.commands.len);
    try content.recover(.{
        .rows = 1,
        .cols = 2,
        .cursor = hiddenCursor(),
        .cells = &two_cells,
        .geometry = &row_geometry,
    }, .{
        .generation = 2,
        .content_generation = 1,
        .pixels = &.{},
        .uploads = &.{},
        .removals = &.{},
        .placements = &.{},
    });
    const repeated_recovery = try content.takeLocalUpdate(&work, empty_scalars_2, contentGeometry(16, 16));
    try std.testing.expectEqual(@as(usize, 1), repeated_recovery.commands.len);
}

test "image capacity rejection preserves retained bytes and generation" {
    var map = try initMap();
    defer deinitMap(&map);
    var limits = contentLimits();
    limits.image_bytes = 4;
    var content = if (selected.native_text)
        try terminal.Content.init(std.testing.allocator, limits, &map)
    else
        try terminal.Content.init(std.testing.allocator, limits, {});
    defer content.deinit();
    var work = try terminal.Content.Work.init(std.testing.allocator, content.limits);
    defer work.deinit();

    const cells = [_]terminal.Cell{cell(0)};
    const row_geometry = [_]terminal.LineGeometry{.single_width};
    const original_pixels = [_]u8{ 1, 2, 3, 4 };
    const upload = [_]render.terminal_images.ImageUpload{.{
        .identity = .{ .id = 1, .generation = 1 },
        .width = 1,
        .height = 1,
        .pixel_offset = 0,
        .pixel_count = 4,
    }};
    const placement = [_]render.terminal_images.ImagePlacement{.{
        .image_id = 1,
        .generation = 1,
        .row = 0,
        .col = 0,
        .pixel_width = 1,
        .pixel_height = 1,
    }};
    try content.recover(.{
        .rows = 1,
        .cols = 1,
        .cursor = hiddenCursor(),
        .cells = &cells,
        .geometry = &row_geometry,
    }, .{
        .generation = 1,
        .content_generation = 1,
        .pixels = &original_pixels,
        .uploads = &upload,
        .removals = &.{},
        .placements = &placement,
    });
    const accepted = try content.takeLocalUpdate(&work, empty_scalars, contentGeometry(8, 16));
    const accepted_revision = @backingInt(accepted.revision);
    var accepted_commands: [4]canvas.Input = undefined;
    try std.testing.expect(accepted.commands.len <= accepted_commands.len);
    @memcpy(accepted_commands[0..accepted.commands.len], accepted.commands);
    const accepted_command_count = accepted.commands.len;

    const oversized_pixels = [_]u8{ 9, 9, 9, 9, 8, 8, 8, 8 };
    const oversized = [_]render.terminal_images.ImageUpload{.{
        .identity = .{ .id = 1, .generation = 2 },
        .width = 2,
        .height = 1,
        .pixel_offset = 0,
        .pixel_count = 8,
    }};
    var oversized_placement = placement;
    oversized_placement[0].generation = 2;
    var changed_cell = cell(0);
    changed_cell.background = .{ .r = 90, .g = 80, .b = 70 };
    const changed_cells = [_]terminal.Cell{changed_cell};
    const changed_patch = [_]terminal.RowPatch{.{
        .row = 0,
        .start_col = 0,
        .cell_offset = 0,
        .cell_count = 1,
        .geometry = .single_width,
        .damage_start = 0,
        .damage_end = 0,
    }};
    try std.testing.expectError(error.ImagePixelLimit, content.apply(.{
        .rows = 1,
        .cols = 1,
        .full = false,
        .cells = &changed_cells,
        .row_patches = &changed_patch,
        .cursor = hiddenCursor(),
    }, .{
        .generation = 2,
        .content_generation = 2,
        .pixels = &oversized_pixels,
        .uploads = &oversized,
        .removals = &.{},
        .placements = &oversized_placement,
    }));
    const unchanged = try content.takeLocalUpdate(&work, empty_scalars, contentGeometry(8, 16));
    try std.testing.expectEqual(accepted_revision, @backingInt(unchanged.revision));
    try std.testing.expectEqual(@as(usize, 0), unchanged.uploads.len);
    try std.testing.expectEqualDeep(
        accepted_commands[0..accepted_command_count],
        unchanged.commands,
    );
    try std.testing.expect(unchanged.commands[unchanged.commands.len - 1] == .rgba);
    try std.testing.expectEqual(
        @as(u64, 1),
        @backingInt(unchanged.commands[unchanged.commands.len - 1].rgba.resource.resource.generation),
    );
}

test "generated and no-glyph runs retain exact coverage without allocation" {
    var map = try initMap();
    defer deinitMap(&map);
    var scratch = try TestScratch.init();
    defer scratch.deinit();
    var cells = [_]terminal.Cell{
        cell(0),
        cell(0),
        cell(0x2500),
        cell('A'),
    };
    cells[1].invisible = true;
    const first = try prepare(&scratch, &map, input(&cells, 1, 3), 1);
    try std.testing.expectEqual(@as(u16, 0), first.first_cell);
    try std.testing.expectEqual(@as(u16, 2), first.end_cell);
    try std.testing.expect(first.glyphs == .none);
    const second = try prepare(&scratch, &map, input(&cells, 1, 3), first.end_cell);
    try std.testing.expectEqual(@as(u16, 2), second.first_cell);
    try std.testing.expectEqual(@as(u16, 3), second.end_cell);
    try std.testing.expect(second.glyphs == .generated);
    const glyph = second.glyphs.generated;
    try std.testing.expectEqual(@as(u16, 2), glyph.source_start);
    try std.testing.expectEqual(@as(u16, 3), glyph.source_end);
    try std.testing.expectEqual(terminal.LineGeometry.double_height_top, second.geometry);
    try std.testing.expectEqual(terminal.CellBaseline.normal, second.baseline);

    if (comptime !selected.native_text) {
        const third = try prepare(&scratch, &map, input(&cells, 1, 3), second.end_cell);
        try std.testing.expectEqual(@as(u16, 3), third.first_cell);
        try std.testing.expectEqual(@as(u16, 4), third.end_cell);
        try std.testing.expect(third.glyphs == .none);
    }
}

test "generated metric identity retains exact configuration axes and sizing" {
    try std.testing.expectEqual(
        @as(usize, 64),
        @sizeOf(terminal_text.GeneratedGlyphKey),
    );
    try std.testing.expectEqual(
        @as(usize, if (selected.native_text) 72 else 64),
        @sizeOf(terminal_text.GlyphKey),
    );
    try std.testing.expectEqual(
        @as(usize, 72),
        @sizeOf(terminal.Content.Geometry),
    );
    var map = try initMap();
    defer deinitMap(&map);
    var scratch = try TestScratch.init();
    defer scratch.deinit();
    var cells = [_]terminal.Cell{cell(0x2500)};

    const first = try prepare(&scratch, &map, input(&cells, 0, 0), 0);
    const first_key = first.glyphs.generated.key.generated;
    var changed_dpi = input(&cells, 0, 0);
    changed_dpi.generated_box.dpi_x = .{ .numerator = 768, .denominator = 5 };
    const second = try prepare(&scratch, &map, changed_dpi, 0);
    const second_key = second.glyphs.generated.key.generated;
    try std.testing.expect(!std.meta.eql(first_key, second_key));

    cells[0].sizing.height = 2;
    const scaled = try prepare(&scratch, &map, input(&cells, 0, 0), 0);
    try std.testing.expect(!std.meta.eql(
        first_key,
        scaled.glyphs.generated.key.generated,
    ));

    cells[0].sizing = .{};
    var changed_points = input(&cells, 0, 0);
    changed_points.generated_box.stroke_points[0] =
        @bitCast(@as(u32, 0x3a831270));
    const fourth = try prepare(&scratch, &map, changed_points, 0);
    try std.testing.expect(!std.meta.eql(
        first_key,
        fourth.glyphs.generated.key.generated,
    ));

    cells[0] = cell(0xe0b1);
    const powerline = try prepare(&scratch, &map, input(&cells, 0, 0), 0);
    const powerline_key = powerline.glyphs.generated.key.generated;
    try std.testing.expect(powerline_key.stroke != null);
    cells[0] = cell(0xe0b0);
    const metric_free = try prepare(&scratch, &map, input(&cells, 0, 0), 0);
    try std.testing.expect(metric_free.glyphs.generated.key.generated.stroke == null);
    var irrelevant_metrics = input(&cells, 0, 0);
    irrelevant_metrics.generated_box.dpi_x =
        .{ .numerator = 768, .denominator = 5 };
    cells[0].sizing.height = 2;
    const metric_free_changed = try prepare(&scratch, &map, irrelevant_metrics, 0);
    try std.testing.expectEqualDeep(
        metric_free.glyphs.generated.key.generated,
        metric_free_changed.glyphs.generated.key.generated,
    );
    cells[0].sizing = .{};
    cells[0] = cell(0xe0b4);
    const metric_free_d = try prepare(&scratch, &map, input(&cells, 0, 0), 0);
    try std.testing.expect(metric_free_d.glyphs.generated.key.generated.stroke == null);
    for ([_]u21{ 0xe0b3, 0xe0b5, 0xe0b7, 0xe0b9, 0xe0bb, 0xe0bd, 0xe0bf }) |codepoint| {
        cells[0] = cell(codepoint);
        const prepared = try prepare(&scratch, &map, input(&cells, 0, 0), 0);
        try std.testing.expect(
            prepared.glyphs.generated.key.generated.stroke != null,
        );
    }
    for (0xee00..0xee0c) |codepoint| {
        cells[0] = cell(@intCast(codepoint));
        const prepared = try prepare(&scratch, &map, input(&cells, 0, 0), 0);
        try std.testing.expect(
            prepared.glyphs.generated.key.generated.stroke != null,
        );
    }
    for ([_]u21{ 0xe0b2, 0xe0b6, 0xe0b8, 0xe0ba, 0xe0bc, 0xe0be }) |codepoint| {
        cells[0] = cell(codepoint);
        const prepared = try prepare(&scratch, &map, input(&cells, 0, 0), 0);
        try std.testing.expect(
            prepared.glyphs.generated.key.generated.stroke == null,
        );
    }
    cells[0] = cell(0xe0b1);
    var changed_powerline = input(&cells, 0, 0);
    changed_powerline.generated_box.dpi_x =
        .{ .numerator = 768, .denominator = 5 };
    const powerline_dpi = try prepare(&scratch, &map, changed_powerline, 0);
    try std.testing.expect(!std.meta.eql(
        powerline_key,
        powerline_dpi.glyphs.generated.key.generated,
    ));
}

test "multicell anchor prepares once and continuations are no-glyph coverage" {
    var map = try initMap();
    defer deinitMap(&map);
    var scratch = try TestScratch.init();
    defer scratch.deinit();
    const codepoint: u21 = if (selected.native_text) 'A' else 0x2500;
    var cells = [_]terminal.Cell{ cell(codepoint), cell(codepoint), cell(codepoint), cell(codepoint) };
    const sizing = terminal.TextSizing{
        .width = 4,
        .height = 2,
        .subscale_n = 1,
        .subscale_d = 2,
        .vertical_align = 2,
        .horizontal_align = 1,
    };
    cells[0].sizing = sizing;
    for (cells[1..], 1..) |*continuation, x| {
        continuation.sizing = sizing;
        continuation.sizing.x = @intCast(x);
    }
    const anchor = try prepare(&scratch, &map, input(&cells, 0, 3), 0);
    try std.testing.expectEqual(@as(u16, 0), anchor.first_cell);
    try std.testing.expectEqual(@as(u16, 1), anchor.end_cell);
    try std.testing.expectEqual(sizing, anchor.sizing);
    if (comptime selected.native_text) {
        try std.testing.expect(anchor.glyphs == .native);
    } else {
        try std.testing.expect(anchor.glyphs == .generated);
    }
    const continuation = try prepare(&scratch, &map, input(&cells, 0, 3), 1);
    try std.testing.expectEqual(@as(u16, 1), continuation.first_cell);
    try std.testing.expectEqual(@as(u16, 4), continuation.end_cell);
    try std.testing.expect(continuation.glyphs == .none);
}

test "run discovery rejects malformed spans and metrics before ownership" {
    var map = try initMap();
    defer deinitMap(&map);
    var scratch = try TestScratch.init();
    defer scratch.deinit();
    var cells = [_]terminal.Cell{cell(0x2500)};
    try std.testing.expectError(
        error.InvalidSpan,
        prepare(&scratch, &map, input(&cells, 1, 0), 0),
    );
    var invalid = input(&cells, 0, 0);
    invalid.metrics.height_px = 0;
    try std.testing.expectError(
        error.InvalidMetrics,
        prepare(&scratch, &map, invalid, 0),
    );
    invalid.metrics.height_px = std.math.maxInt(u16);
    invalid.metrics.baseline_px = 12;
    try std.testing.expectError(
        error.InvalidMetrics,
        prepare(&scratch, &map, invalid, 0),
    );
}

test "generated extent validation does not reject native or blank mixed runs" {
    if (comptime !selected.native_text) return error.SkipZigTest;
    var map = try initMap();
    defer deinitMap(&map);
    var scratch = try TestScratch.init();
    defer scratch.deinit();
    var cells = [_]terminal.Cell{ cell('A'), cell(0), cell(0x2500) };
    var oversized = input(&cells, 0, 2);
    oversized.metrics = .{ .width_px = 257, .height_px = 257, .baseline_px = 12 };

    const native_run = try prepare(&scratch, &map, oversized, 0);
    try std.testing.expect(native_run.glyphs == .native);
    const blank_run = try prepare(&scratch, &map, oversized, 1);
    try std.testing.expect(blank_run.glyphs == .none);
    try std.testing.expectError(error.InvalidMetrics, prepare(&scratch, &map, oversized, 2));
}

test "native terminal graph cannot exclude generated box selection" {
    if (comptime !selected.native_text) return error.SkipZigTest;
    var map = try initMap();
    defer deinitMap(&map);
    var scratch = try TestScratch.init();
    defer scratch.deinit();
    const cells = [_]terminal.Cell{
        cell('A'),
        cell(0x2500),
        cell(0x2502),
    };
    const row = input(&cells, 0, cells.len - 1);
    const ordinary = try prepare(&scratch, &map, row, 0);
    try std.testing.expect(ordinary.glyphs == .native);
    const horizontal = try prepare(&scratch, &map, row, 1);
    try std.testing.expect(horizontal.glyphs == .generated);
    try std.testing.expectEqual(
        @as(u21, 0x2500),
        horizontal.glyphs.generated.key.generated.codepoint,
    );
    const vertical = try prepare(&scratch, &map, row, 2);
    try std.testing.expect(vertical.glyphs == .generated);
    try std.testing.expectEqual(
        @as(u21, 0x2502),
        vertical.glyphs.generated.key.generated.codepoint,
    );
}

test "generated raster owns exact alpha and allocation rollback" {
    var map = try initMap();
    defer deinitMap(&map);
    var scratch = try TestScratch.init();
    defer scratch.deinit();
    var cells = [_]terminal.Cell{cell(0x2500)};
    const run = try prepare(&scratch, &map, input(&cells, 0, 0), 0);
    const key = run.glyphs.generated.key;
    try std.testing.expectEqual(@as(u16, 12), key.generated.baseline_px);
    try std.testing.expectError(
        error.OutOfMemory,
        rasterize(&map, std.testing.failing_allocator, key),
    );
    var raster = try rasterize(&map, std.testing.allocator, key);
    defer raster.deinit();
    try std.testing.expectEqual(@as(u16, 8), raster.width);
    try std.testing.expectEqual(@as(u16, 16), raster.height);
    try std.testing.expectEqual(@as(i16, 12), raster.top);
    try std.testing.expectEqual(@as(usize, 128), raster.pixels.len);

    var alternate_input = input(&cells, 0, 0);
    alternate_input.metrics.baseline_px = 10;
    const alternate_run = try prepare(&scratch, &map, alternate_input, 0);
    const alternate_key = alternate_run.glyphs.generated.key;
    try std.testing.expect(!std.meta.eql(key, alternate_key));
    var alternate_raster = try rasterize(&map, std.testing.allocator, alternate_key);
    defer alternate_raster.deinit();
    try std.testing.expectEqual(@as(i16, 10), alternate_raster.top);

    var invalid_key = key;
    invalid_key.generated.baseline_px = invalid_key.generated.height_px;
    try std.testing.expectError(
        error.InvalidSize,
        rasterize(&map, std.testing.allocator, invalid_key),
    );
}

test "native map and one-run preparation preserve exact tuple and coverage" {
    if (comptime !selected.native_text) return error.SkipZigTest;
    const configs = [_]terminal_text.FontConfig{
        .{
            .key = .{ .slot = 0, .style = .normal },
            .native = .{ .primary = fonts.primary_font, .size = .{ .pixels = 16 } },
        },
        .{
            .key = .{ .slot = 3, .style = .bold_italic },
            .native = .{ .primary = fonts.primary_font, .size = .{ .pixels = 16 } },
        },
    };
    var map = try terminal_text.FontMap.init(std.testing.allocator, &configs);
    defer map.deinit();
    var scratch = try TestScratch.init();
    defer scratch.deinit();
    const configured_metrics = map.cellMetrics(.{ .slot = 0, .style = .normal }).?;
    try std.testing.expect(configured_metrics.width_px > 0);
    try std.testing.expect(configured_metrics.height_px > 0);
    try std.testing.expect(configured_metrics.baseline_px < configured_metrics.height_px);
    const decorations = map.decorationMetrics(.{ .slot = 0, .style = .normal }).?;
    try std.testing.expect(decorations.underline_y < configured_metrics.height_px);
    try std.testing.expect(decorations.underline_height > 0);
    try std.testing.expect(decorations.strike_y < configured_metrics.height_px);
    try std.testing.expect(decorations.strike_height > 0);
    try std.testing.expect(map.cellMetrics(.{ .slot = 1, .style = .normal }) == null);
    try std.testing.expect(map.decorationMetrics(.{ .slot = 1, .style = .normal }) == null);
    var cells = @as([12]terminal.Cell, @splat(cell(0)));
    cells[8] = cell('f');
    cells[9] = cell('i');
    cells[10] = cell('A');
    cells[10].combining_len = 1;
    cells[10].combining[0] = 0x0301;
    for (cells[8..11]) |*value| {
        value.font = 3;
        value.bold = true;
        value.italic = true;
        value.baseline = .raised;
    }
    const run = try terminal_text.prepareNextRun(
        &map,
        input(&cells, 9, 10),
        9,
        scratch.borrow(),
    );
    try std.testing.expectEqual(@as(u16, 8), run.first_cell);
    try std.testing.expect(run.first_cell > 4);
    try std.testing.expectEqual(@as(u16, 11), run.end_cell);
    try std.testing.expectEqual(terminal.CellBaseline.raised, run.baseline);
    try std.testing.expectEqual(terminal.LineGeometry.double_height_top, run.geometry);
    try std.testing.expect(run.glyphs == .native);
    try std.testing.expect(run.glyphs.native.len > 0);
    var joined_cells = false;
    var combined_cell = false;
    for (run.glyphs.native) |glyph| {
        try std.testing.expect(glyph.key == .native);
        try std.testing.expectEqual(@as(u4, 3), glyph.key.native.font.slot);
        try std.testing.expectEqual(terminal_text.FontStyle.bold_italic, glyph.key.native.font.style);
        try std.testing.expect(glyph.source_start < glyph.source_end);
        try std.testing.expect(glyph.source_start >= 8);
        try std.testing.expect(glyph.source_end <= run.end_cell);
        try std.testing.expectEqual(
            glyph.source_end - glyph.source_start,
            glyph.key.native.cell_span,
        );
        joined_cells = joined_cells or glyph.key.native.cell_span == 2;
        combined_cell = combined_cell or
            (glyph.source_start == 10 and glyph.source_end == 11);
    }
    try std.testing.expect(joined_cells);
    try std.testing.expect(combined_cell);
    const key = run.glyphs.native[0].key;
    var raster = try terminal_text.rasterizeGlyph(std.testing.allocator, &map, key);
    defer raster.deinit();
    try std.testing.expect(raster.pixels.len <= render.text.max_raster_bytes);
    var overflow_key = key;
    overflow_key.native.cell_span = std.math.maxInt(u16);
    try std.testing.expectError(
        error.InvalidWidth,
        terminal_text.rasterizeGlyph(std.testing.allocator, &map, overflow_key),
    );
    var zero_key = key;
    zero_key.native.cell_span = 0;
    try std.testing.expectError(
        error.InvalidWidth,
        terminal_text.rasterizeGlyph(std.testing.allocator, &map, zero_key),
    );

    var default_map = try initMap();
    defer default_map.deinit();
    try std.testing.expectError(
        error.InvalidRaster,
        terminal_text.rasterizeGlyph(std.testing.allocator, &default_map, key),
    );
}

test "Iosevka contextual ligature policy shapes exact cursor group" {
    if (comptime !selected.native_text) return error.SkipZigTest;
    const configs = [_]terminal_text.FontConfig{.{
        .key = .{ .slot = 0, .style = .normal },
        .native = .{ .primary = fonts.symbol_font, .size = .{ .pixels = 32 } },
    }};
    var map = try terminal_text.FontMap.init(std.testing.allocator, &configs);
    defer map.deinit();
    var scratch = try TestScratch.init();
    defer scratch.deinit();
    var cells = [_]terminal.Cell{
        cell('A'),
        cell('!'),
        cell('='),
        cell('B'),
    };
    cells[0].combining_len = 1;
    cells[0].combining[0] = 0x0301;
    var row = input(&cells, 0, cells.len - 1);
    row.geometry = .single_width;
    row.metrics = map.cellMetrics(.{ .slot = 0, .style = .normal }).?;

    row.ligature_mode = .never;
    const enabled = try prepare(&scratch, &map, row, 0);
    const enabled_glyphs = enabled.glyphs.native;
    var enabled_ids: [8]u32 = @splat(0);
    for (enabled_glyphs, 0..) |glyph, index| enabled_ids[index] = glyph.key.native.glyph_id;
    const enabled_len = enabled_glyphs.len;
    var enabled_group_members: usize = 0;
    var preserved_group_overhang = false;
    for (enabled_glyphs) |glyph| {
        if (glyph.source_start != 1 or glyph.source_end != 3) continue;
        try std.testing.expectEqual(@as(u16, 2), glyph.key.native.cell_span);
        var raster = try terminal_text.rasterizeGlyph(
            std.testing.allocator,
            &map,
            glyph.key,
        );
        defer raster.deinit();
        preserved_group_overhang = preserved_group_overhang or raster.left < 0;
        enabled_group_members += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), enabled_group_members);
    try std.testing.expect(preserved_group_overhang);

    row.ligature_mode = .always;
    const disabled = try prepare(&scratch, &map, row, 0);
    const disabled_glyphs = disabled.glyphs.native;
    var disabled_ids: [8]u32 = @splat(0);
    for (disabled_glyphs, 0..) |glyph, index|
        disabled_ids[index] = glyph.key.native.glyph_id;
    const disabled_len = disabled_glyphs.len;
    try std.testing.expectEqual(enabled_len, disabled_len);
    try std.testing.expect(!std.mem.eql(
        u32,
        enabled_ids[0..enabled_len],
        disabled_ids[0..disabled_len],
    ));

    row.ligature_mode = .cursor;
    row.cursor_col = 0;
    const before = try prepare(&scratch, &map, row, 0);
    for (before.glyphs.native, 0..) |glyph, index|
        try std.testing.expectEqual(enabled_ids[index], glyph.key.native.glyph_id);
    row.cursor_col = 1;
    const inside = try prepare(&scratch, &map, row, 0);
    for (inside.glyphs.native, 0..) |glyph, index|
        try std.testing.expectEqual(disabled_ids[index], glyph.key.native.glyph_id);
    row.cursor_col = 3;
    const after = try prepare(&scratch, &map, row, 0);
    for (after.glyphs.native, 0..) |glyph, index|
        try std.testing.expectEqual(enabled_ids[index], glyph.key.native.glyph_id);

    const triple_cells = [_]terminal.Cell{
        cell('='),
        cell('='),
        cell('='),
    };
    var triple = input(&triple_cells, 0, triple_cells.len - 1);
    triple.geometry = .single_width;
    triple.metrics = row.metrics;
    triple.ligature_mode = .never;
    const triple_enabled = try prepare(&scratch, &map, triple, 0);
    var triple_ids: [8]u32 = @splat(0);
    for (triple_enabled.glyphs.native, 0..) |glyph, index|
        triple_ids[index] = glyph.key.native.glyph_id;
    const triple_len = triple_enabled.glyphs.native.len;
    try std.testing.expectEqual(@as(usize, 3), triple_len);
    for (triple_enabled.glyphs.native, 0..) |glyph, index| {
        try std.testing.expectEqual(@as(u16, 0), glyph.source_start);
        try std.testing.expectEqual(@as(u16, 3), glyph.source_end);
        try std.testing.expectEqual(@as(u16, 3), glyph.key.native.cell_span);
        try std.testing.expectEqual(
            @as(i32, @intCast(index * triple.metrics.width_px * 64)),
            glyph.x_26_6,
        );
    }
    triple.ligature_mode = .always;
    const triple_disabled = try prepare(&scratch, &map, triple, 0);
    try std.testing.expectEqual(triple_len, triple_disabled.glyphs.native.len);
    for (triple_disabled.glyphs.native, 0..) |glyph, index|
        try std.testing.expect(triple_ids[index] != glyph.key.native.glyph_id);
}

test "Iosevka operator groups retain complete Kitty spans" {
    if (comptime !selected.native_text) return error.SkipZigTest;
    const configs = [_]terminal_text.FontConfig{.{
        .key = .{ .slot = 0, .style = .normal },
        .native = .{ .primary = fonts.symbol_font, .size = .{ .pixels = 32 } },
    }};
    var map = try terminal_text.FontMap.init(std.testing.allocator, &configs);
    defer map.deinit();
    var scratch = try TestScratch.init();
    defer scratch.deinit();
    const operators = [_][]const u8{ "<->", "<=>", "!=", ">=", "<=" };
    for (operators) |operator| {
        var cells: [3]terminal.Cell = undefined;
        for (operator, 0..) |scalar, index| cells[index] = cell(scalar);
        var row = input(
            cells[0..operator.len],
            0,
            @intCast(operator.len - 1),
        );
        row.geometry = .single_width;
        row.metrics = map.cellMetrics(.{ .slot = 0, .style = .normal }).?;
        const run = try prepare(&scratch, &map, row, 0);
        try std.testing.expectEqual(@as(u16, 0), run.first_cell);
        try std.testing.expectEqual(@as(u16, @intCast(operator.len)), run.end_cell);
        for (run.glyphs.native) |glyph| {
            try std.testing.expectEqual(@as(u16, 0), glyph.source_start);
            try std.testing.expectEqual(
                @as(u16, @intCast(operator.len)),
                glyph.source_end,
            );
            try std.testing.expectEqual(
                @as(u16, @intCast(operator.len)),
                glyph.key.native.cell_span,
            );
        }
    }
}

test "Content mode and cursor transitions mutate only exact ligature resources" {
    if (comptime !selected.native_text) return error.SkipZigTest;
    const configs = [_]terminal_text.FontConfig{.{
        .key = .{ .slot = 0, .style = .normal },
        .native = .{ .primary = fonts.symbol_font, .size = .{ .pixels = 32 } },
    }};
    var map = try terminal_text.FontMap.init(std.testing.allocator, &configs);
    defer map.deinit();
    var content = try terminal.Content.init(
        std.testing.allocator,
        contentLimits(),
        &map,
    );
    defer content.deinit();
    var work = try terminal.Content.Work.init(
        std.testing.allocator,
        content.limits,
    );
    defer work.deinit();
    const configured = map.cellMetrics(.{ .slot = 0, .style = .normal }).?;
    const geometry = terminal.Content.Geometry{
        .x = 0,
        .y = 0,
        .clip = .{
            .x = 0,
            .y = 0,
            .width = configured.width_px * 4,
            .height = configured.height_px,
        },
        .metrics = configured,
        .generated_box = generatedBoxConfig(),
        .underline_y = configured.height_px - 2,
        .underline_height = 1,
        .strike_y = configured.height_px / 2,
        .strike_height = 1,
    };
    const cells = [_]terminal.Cell{
        cell('A'),
        cell('!'),
        cell('='),
        cell('B'),
    };
    const row_geometry = [_]terminal.LineGeometry{.single_width};
    var cursor = hiddenCursor();
    cursor.visible = true;
    cursor.shape = .block;
    cursor.col = 1;
    try content.recover(.{
        .rows = 1,
        .cols = cells.len,
        .cursor = cursor,
        .cells = &cells,
        .geometry = &row_geometry,
    }, emptyImages());
    const scalars = terminal.ScalarBaseline.empty(cells.len);
    const enabled = try content.takeUpdate(
        &work,
        scalars,
        geometry,
        .{ .ligature_mode = .never },
        .local,
    );
    try std.testing.expect(enabled.uploads.len != 0);

    cursor.col = 2;
    try content.apply(.{
        .rows = 1,
        .cols = cells.len,
        .full = false,
        .cells = &.{},
        .row_patches = &.{},
        .cursor = cursor,
    }, null);
    const never_moved = try content.takeUpdate(
        &work,
        scalars,
        geometry,
        .{ .ligature_mode = .never },
        .local,
    );
    try std.testing.expectEqual(@as(usize, 0), never_moved.uploads.len);
    try std.testing.expectEqual(@as(usize, 0), never_moved.removals.len);

    const always = try content.takeUpdate(
        &work,
        scalars,
        geometry,
        .{ .ligature_mode = .always },
        .local,
    );
    try std.testing.expect(always.uploads.len != 0);
    try std.testing.expect(always.removals.len != 0);
    const always_revision = @backingInt(always.revision);

    cursor.col = 0;
    try content.apply(.{
        .rows = 1,
        .cols = cells.len,
        .full = false,
        .cells = &.{},
        .row_patches = &.{},
        .cursor = cursor,
    }, null);
    const always_moved = try content.takeUpdate(
        &work,
        scalars,
        geometry,
        .{ .ligature_mode = .always },
        .local,
    );
    try std.testing.expectEqual(@as(usize, 0), always_moved.uploads.len);
    try std.testing.expectEqual(@as(usize, 0), always_moved.removals.len);
    try std.testing.expectEqual(always_revision + 1, @backingInt(always_moved.revision));

    const cursor_before = try content.takeUpdate(
        &work,
        scalars,
        geometry,
        .{ .ligature_mode = .cursor },
        .local,
    );
    try std.testing.expect(cursor_before.uploads.len != 0);
    cursor.col = 1;
    try content.apply(.{
        .rows = 1,
        .cols = cells.len,
        .full = false,
        .cells = &.{},
        .row_patches = &.{},
        .cursor = cursor,
    }, null);
    const cursor_inside = try content.takeUpdate(
        &work,
        scalars,
        geometry,
        .{ .ligature_mode = .cursor },
        .local,
    );
    try std.testing.expect(cursor_inside.uploads.len != 0);
    try std.testing.expect(cursor_inside.removals.len != 0);
}

test "cursor transition restores old row and disables new row atomically" {
    if (comptime !selected.native_text) return error.SkipZigTest;
    const configs = [_]terminal_text.FontConfig{.{
        .key = .{ .slot = 0, .style = .normal },
        .native = .{ .primary = fonts.symbol_font, .size = .{ .pixels = 32 } },
    }};
    var map = try terminal_text.FontMap.init(std.testing.allocator, &configs);
    defer map.deinit();
    var content = try terminal.Content.init(
        std.testing.allocator,
        contentLimits(),
        &map,
    );
    defer content.deinit();
    var work = try terminal.Content.Work.init(
        std.testing.allocator,
        content.limits,
    );
    defer work.deinit();
    const configured = map.cellMetrics(.{ .slot = 0, .style = .normal }).?;
    const geometry = terminal.Content.Geometry{
        .x = 0,
        .y = 0,
        .clip = .{
            .x = 0,
            .y = 0,
            .width = configured.width_px * 4,
            .height = configured.height_px * 2,
        },
        .metrics = configured,
        .generated_box = generatedBoxConfig(),
        .underline_y = configured.height_px - 2,
        .underline_height = 1,
        .strike_y = configured.height_px / 2,
        .strike_height = 1,
    };
    const cells = [_]terminal.Cell{
        cell('A'),
        cell('!'),
        cell('='),
        cell('B'),
        cell('A'),
        cell('!'),
        cell('='),
        cell('B'),
    };
    const row_geometry = [_]terminal.LineGeometry{
        .single_width,
        .single_width,
    };
    var cursor = hiddenCursor();
    cursor.visible = true;
    cursor.shape = .block;
    cursor.row = 0;
    cursor.col = 1;
    try content.recover(.{
        .rows = 2,
        .cols = 4,
        .cursor = cursor,
        .cells = &cells,
        .geometry = &row_geometry,
    }, emptyImages());
    const scalars = terminal.ScalarBaseline.empty(cells.len);
    const first = try content.takeUpdate(
        &work,
        scalars,
        geometry,
        .{ .ligature_mode = .cursor },
        .local,
    );
    var first_row_zero: [32]canvas.ResourceRef = undefined;
    var first_row_one: [32]canvas.ResourceRef = undefined;
    const first_zero_count = rowGlyphResources(
        first.commands,
        0,
        configured.height_px,
        &first_row_zero,
    );
    const first_one_count = rowGlyphResources(
        first.commands,
        configured.height_px,
        configured.height_px,
        &first_row_one,
    );
    const first_revision = @backingInt(first.revision);

    cursor.row = 1;
    try content.apply(.{
        .rows = 2,
        .cols = 4,
        .full = false,
        .cells = &.{},
        .row_patches = &.{},
        .cursor = cursor,
    }, null);
    const second = try content.takeUpdate(
        &work,
        scalars,
        geometry,
        .{ .ligature_mode = .cursor },
        .local,
    );
    try std.testing.expectEqual(first_revision + 1, @backingInt(second.revision));
    try std.testing.expectEqual(@as(usize, 0), second.uploads.len);
    try std.testing.expectEqual(@as(usize, 0), second.removals.len);
    var second_row_zero: [32]canvas.ResourceRef = undefined;
    var second_row_one: [32]canvas.ResourceRef = undefined;
    const second_zero_count = rowGlyphResources(
        second.commands,
        0,
        configured.height_px,
        &second_row_zero,
    );
    const second_one_count = rowGlyphResources(
        second.commands,
        configured.height_px,
        configured.height_px,
        &second_row_one,
    );
    try std.testing.expectEqual(first_one_count, second_zero_count);
    try std.testing.expectEqual(first_zero_count, second_one_count);
    try std.testing.expectEqualSlices(
        canvas.ResourceRef,
        first_row_one[0..first_one_count],
        second_row_zero[0..second_zero_count],
    );
    try std.testing.expectEqualSlices(
        canvas.ResourceRef,
        first_row_zero[0..first_zero_count],
        second_row_one[0..second_one_count],
    );
}

test "semantic wide continuation bounds Iosevka cursor grouping" {
    if (comptime !selected.native_text) return error.SkipZigTest;
    const configs = [_]terminal_text.FontConfig{.{
        .key = .{ .slot = 0, .style = .normal },
        .native = .{ .primary = fonts.symbol_font, .size = .{ .pixels = 32 } },
    }};
    var map = try terminal_text.FontMap.init(std.testing.allocator, &configs);
    defer map.deinit();
    var scratch = try TestScratch.init();
    defer scratch.deinit();
    var cells = [_]terminal.Cell{
        cell(0x4e00),
        cell(0),
        cell('!'),
        cell('='),
    };
    cells[0].sizing.width = 2;
    cells[1].sizing = .{ .width = 2, .x = 1 };
    var row = input(&cells, 0, cells.len - 1);
    row.geometry = .single_width;
    row.metrics = map.cellMetrics(.{ .slot = 0, .style = .normal }).?;
    row.ligature_mode = .cursor;
    row.cursor_col = 2;

    const wide = try prepare(&scratch, &map, row, 0);
    try std.testing.expectEqual(@as(u16, 1), wide.end_cell);
    const continuation = try prepare(&scratch, &map, row, 1);
    try std.testing.expect(continuation.glyphs == .none);
    try std.testing.expectEqual(@as(u16, 2), continuation.end_cell);
    const ligature = try prepare(&scratch, &map, row, 2);
    try std.testing.expectEqual(@as(u16, 2), ligature.first_cell);
    try std.testing.expectEqual(@as(u16, 4), ligature.end_cell);
    for (ligature.glyphs.native) |glyph| {
        try std.testing.expect(glyph.source_start >= 2);
        try std.testing.expect(glyph.source_end <= 4);
    }
}

test "native FontMap replacement swaps all styles and leaves retired owner" {
    if (comptime !selected.native_text) return error.SkipZigTest;
    const old_configs = [_]terminal_text.FontConfig{
        .{ .key = .{ .slot = 0, .style = .normal }, .native = .{ .primary = fonts.primary_font, .size = .{ .pixels = 16 } } },
        .{ .key = .{ .slot = 0, .style = .bold }, .native = .{ .primary = fonts.primary_font, .size = .{ .pixels = 16 } } },
        .{ .key = .{ .slot = 0, .style = .italic }, .native = .{ .primary = fonts.primary_font, .size = .{ .pixels = 16 } } },
        .{ .key = .{ .slot = 0, .style = .bold_italic }, .native = .{ .primary = fonts.primary_font, .size = .{ .pixels = 16 } } },
    };
    const new_configs = [_]terminal_text.FontConfig{
        .{ .key = .{ .slot = 0, .style = .normal }, .native = .{ .primary = fonts.primary_font, .size = .{ .pixels = 24 } } },
        .{ .key = .{ .slot = 0, .style = .bold }, .native = .{ .primary = fonts.primary_font, .size = .{ .pixels = 24 } } },
        .{ .key = .{ .slot = 0, .style = .italic }, .native = .{ .primary = fonts.primary_font, .size = .{ .pixels = 24 } } },
        .{ .key = .{ .slot = 0, .style = .bold_italic }, .native = .{ .primary = fonts.primary_font, .size = .{ .pixels = 24 } } },
    };
    var map = try terminal_text.FontMap.init(std.testing.allocator, &old_configs);
    defer map.deinit();
    const address = &map;
    const old_metrics = map.cellMetrics(.{ .slot = 0, .style = .normal }).?;
    var replacement = try terminal_text.FontMap.init(std.testing.allocator, &new_configs);
    defer replacement.deinit();
    map.replaceWith(&replacement);
    try std.testing.expectEqual(address, &map);
    try std.testing.expect(map.cellMetrics(.{ .slot = 0, .style = .normal }).?.height_px > old_metrics.height_px);
    try std.testing.expect(map.cellMetrics(.{ .slot = 0, .style = .bold }).?.height_px == map.cellMetrics(.{ .slot = 0, .style = .normal }).?.height_px);
    try std.testing.expect(replacement.cellMetrics(.{ .slot = 0, .style = .normal }).?.height_px == old_metrics.height_px);
}

test "failed replacement construction preserves the accepted FontMap" {
    if (comptime !selected.native_text) return error.SkipZigTest;
    const config = terminal_text.FontConfig{
        .key = .{ .slot = 0, .style = .normal },
        .native = .{ .primary = fonts.primary_font, .size = .{ .pixels = 16 } },
    };
    var map = try terminal_text.FontMap.init(std.testing.allocator, &.{config});
    defer map.deinit();
    const before = map.cellMetrics(config.key).?;
    try std.testing.expectError(
        error.OutOfMemory,
        terminal_text.FontMap.init(std.testing.failing_allocator, &.{config}),
    );
    try std.testing.expectEqual(before, map.cellMetrics(config.key).?);
    var scratch = try TestScratch.init();
    defer scratch.deinit();
    const cells = [_]terminal.Cell{cell('A')};
    const run = try prepare(&scratch, &map, input(&cells, 0, 0), 0);
    try std.testing.expect(run.glyphs == .native);
    var raster = try rasterize(&map, std.testing.allocator, run.glyphs.native[0].key);
    defer raster.deinit();
    try std.testing.expect(raster.width != 0 and raster.height != 0);
}

test "terminal cell span bounds oversized native raster" {
    if (comptime !selected.native_text) return error.SkipZigTest;
    const configs = [_]terminal_text.FontConfig{.{
        .key = .{ .slot = 0, .style = .normal },
        .native = .{ .primary = fonts.symbol_font, .size = .{ .pixels = 18 } },
    }};
    var map = try terminal_text.FontMap.init(std.testing.allocator, &configs);
    defer map.deinit();
    var scratch = try TestScratch.init();
    defer scratch.deinit();
    var cells = [_]terminal.Cell{cell(0xf303)};
    const run = try prepare(&scratch, &map, input(&cells, 0, 0), 0);
    try std.testing.expect(run.glyphs == .native);
    const key = run.glyphs.native[0].key;
    var raster = try rasterize(&map, std.testing.allocator, key);
    defer raster.deinit();
    const configured = map.cellMetrics(.{ .slot = 0, .style = .normal }).?;
    try std.testing.expect(raster.width <= configured.width_px * key.native.cell_span);
}

test "native private-use presentation borrows only immediate blank cells" {
    if (comptime !selected.native_text) return error.SkipZigTest;
    const configs = [_]terminal_text.FontConfig{.{
        .key = .{ .slot = 0, .style = .normal },
        .native = .{ .primary = fonts.symbol_font, .size = .{ .pixels = 18 } },
    }};
    var map = try terminal_text.FontMap.init(std.testing.allocator, &configs);
    defer map.deinit();
    var scratch = try TestScratch.init();
    defer scratch.deinit();

    const cells = [_]terminal.Cell{
        cell(0xf303),
        cell(' '),
        cell(0x2002),
        cell('X'),
    };
    const ordinary_input = input(&cells, 0, 3);
    const run = try prepare(&scratch, &map, ordinary_input, 0);
    try std.testing.expect(run.glyphs == .native);
    try std.testing.expectEqual(@as(u16, 3), run.end_cell);
    for (run.glyphs.native) |glyph| {
        try std.testing.expectEqual(@as(u16, 0), glyph.source_start);
        try std.testing.expectEqual(run.end_cell, glyph.source_end);
        try std.testing.expectEqual(run.end_cell, glyph.key.native.cell_span);
        try std.testing.expect(run.borrowed_blank_span);
    }
    var ordinary_keys: [8]terminal_text.GlyphKey = undefined;
    for (run.glyphs.native, 0..) |glyph, index| ordinary_keys[index] = glyph.key;
    const ordinary_glyph_count = run.glyphs.native.len;
    try std.testing.expectEqual(@as(u21, ' '), cells[1].codepoint);
    try std.testing.expectEqual(@as(u21, 0x2002), cells[2].codepoint);
    var cursor_input = ordinary_input;
    cursor_input.ligature_mode = .cursor;
    cursor_input.cursor_col = 1;
    const cursor_run = try prepare(&scratch, &map, cursor_input, 0);
    try std.testing.expectEqual(run.end_cell, cursor_run.end_cell);
    try std.testing.expect(cursor_run.borrowed_blank_span);
    try std.testing.expectEqual(ordinary_glyph_count, cursor_run.glyphs.native.len);
    for (cursor_run.glyphs.native, 0..) |glyph, index|
        try std.testing.expectEqual(
            ordinary_keys[index],
            glyph.key,
        );

    const blocked = [_]terminal.Cell{ cell(0xf303), cell('X'), cell(' ') };
    const blocked_run = try prepare(&scratch, &map, input(&blocked, 0, 2), 0);
    try std.testing.expectEqual(
        @as(u16, 1),
        blocked_run.glyphs.native[0].key.native.cell_span,
    );
    try std.testing.expect(!blocked_run.borrowed_blank_span);
    const boundary = [_]terminal.Cell{cell(0xf303)};
    const boundary_run = try prepare(&scratch, &map, input(&boundary, 0, 0), 0);
    try std.testing.expectEqual(@as(u16, 1), boundary_run.end_cell);
}

test "ordinary native run stops before an embedded borrowable symbol" {
    if (comptime !selected.native_text) return error.SkipZigTest;
    const configs = [_]terminal_text.FontConfig{.{
        .key = .{ .slot = 0, .style = .normal },
        .native = .{ .primary = fonts.symbol_font, .size = .{ .pixels = 18 } },
    }};
    var map = try terminal_text.FontMap.init(std.testing.allocator, &configs);
    defer map.deinit();
    var scratch = try TestScratch.init();
    defer scratch.deinit();
    const cells = [_]terminal.Cell{
        cell('A'),
        cell(0xf024b),
        cell(' '),
        cell(' '),
        cell('B'),
    };
    const ordinary = try prepare(&scratch, &map, input(&cells, 0, 4), 0);
    try std.testing.expectEqual(@as(u16, 0), ordinary.first_cell);
    try std.testing.expectEqual(@as(u16, 1), ordinary.end_cell);
    const symbol = try prepare(&scratch, &map, input(&cells, 0, 4), ordinary.end_cell);
    try std.testing.expect(symbol.borrowed_blank_span);
    try std.testing.expectEqual(@as(u16, 1), symbol.first_cell);
    try std.testing.expectEqual(@as(u16, 3), symbol.end_cell);
    for (symbol.glyphs.native) |glyph|
        try std.testing.expectEqual(@as(u16, 2), glyph.key.native.cell_span);

    const repeated = try prepare(&scratch, &map, input(&cells, 0, 4), 0);
    try std.testing.expectEqual(ordinary.first_cell, repeated.first_cell);
    try std.testing.expectEqual(ordinary.end_cell, repeated.end_cell);
}

test "forward run after a leading borrowed symbol cannot shape it again" {
    if (comptime !selected.native_text) return error.SkipZigTest;
    const configs = [_]terminal_text.FontConfig{.{
        .key = .{ .slot = 0, .style = .normal },
        .native = .{ .primary = fonts.symbol_font, .size = .{ .pixels = 18 } },
    }};
    var map = try terminal_text.FontMap.init(std.testing.allocator, &configs);
    defer map.deinit();
    var scratch = try TestScratch.init();
    defer scratch.deinit();
    const cells = [_]terminal.Cell{
        cell(0xf024b),
        cell(' '),
        cell('B'),
    };
    const symbol = try prepare(&scratch, &map, input(&cells, 0, 2), 0);
    try std.testing.expect(symbol.borrowed_blank_span);
    try std.testing.expectEqual(@as(u16, 0), symbol.first_cell);
    try std.testing.expectEqual(@as(u16, 2), symbol.end_cell);

    const following = try prepare(
        &scratch,
        &map,
        input(&cells, 0, 2),
        symbol.end_cell,
    );
    try std.testing.expect(!following.borrowed_blank_span);
    try std.testing.expectEqual(symbol.end_cell, following.first_cell);
    try std.testing.expectEqual(@as(u16, 3), following.end_cell);
    for (following.glyphs.native) |glyph| {
        try std.testing.expect(glyph.source_start >= symbol.end_cell);
        try std.testing.expect(glyph.key.native.cell_span <= 1);
    }
}

test "borrowed symbol centers raster and substitutes decoration color" {
    if (comptime !selected.native_text) return error.SkipZigTest;
    const fallback_paths = [_][]const u8{fonts.symbol_font};
    const configs = [_]terminal_text.FontConfig{.{
        .key = .{ .slot = 0, .style = .normal },
        .native = .{
            .primary = fonts.primary_font,
            .fallbacks = &fallback_paths,
            .size = .{ .pixels = 18 },
        },
    }};
    var map = try terminal_text.FontMap.init(std.testing.allocator, &configs);
    defer map.deinit();
    var content = try terminal.Content.init(
        std.testing.allocator,
        contentLimits(),
        &map,
    );
    defer content.deinit();
    var work = try terminal.Content.Work.init(std.testing.allocator, content.limits);
    defer work.deinit();
    var cells = [_]terminal.Cell{ cell(0xf303), cell(' '), cell(' ') };
    cells[0].foreground = .{ .r = 7, .g = 8, .b = 9 };
    cells[0].underline_color = .{ .r = 17, .g = 18, .b = 19 };
    for (&cells) |*value| {
        value.underline = true;
        value.underline_style = .single;
    }
    cells[1].underline_color = .{ .r = 27, .g = 28, .b = 29 };
    cells[2].underline_color = .{ .r = 37, .g = 38, .b = 39 };
    const rows = [_]terminal.LineGeometry{.single_width};
    try content.recover(.{
        .rows = 1,
        .cols = cells.len,
        .cursor = hiddenCursor(),
        .cells = &cells,
        .geometry = &rows,
    }, emptyImages());
    const update = try content.takeLocalUpdate(
        &work,
        empty_scalars_3,
        contentGeometry(24, 16),
    );
    var glyph_count: usize = 0;
    var underline_count: usize = 0;
    for (update.commands) |command| switch (command) {
        .alpha_mask => |glyph| {
            if (glyph.destination.height == 0) continue;
            try std.testing.expectEqual(@as(i32, 3), glyph.destination.x);
            try std.testing.expectEqual(@as(u8, 7), glyph.color.r);
            glyph_count += 1;
        },
        .solid => |solid| {
            if (solid.rect.y != 14 or solid.rect.height != 1) continue;
            try std.testing.expectEqual(@as(u8, 17), solid.color.r);
            try std.testing.expectEqual(@as(u8, 18), solid.color.g);
            try std.testing.expectEqual(@as(u8, 19), solid.color.b);
            underline_count += 1;
        },
        else => {},
    };
    try std.testing.expectEqual(@as(usize, 3), glyph_count);
    try std.testing.expectEqual(@as(usize, 3), underline_count);

    var accepted_commands: [16]canvas.Input = undefined;
    try std.testing.expect(update.commands.len <= accepted_commands.len);
    @memcpy(accepted_commands[0..update.commands.len], update.commands);
    const accepted_count = update.commands.len;
    const accepted_revision = update.revision;
    var invalid_geometry = contentGeometry(24, 16);
    invalid_geometry.x = std.math.maxInt(i32);
    invalid_geometry.clip.x = std.math.maxInt(i32);
    try std.testing.expectError(
        error.ArithmeticOverflow,
        content.takeLocalUpdate(&work, empty_scalars_3, invalid_geometry),
    );
    const recovered = try content.takeLocalUpdate(
        &work,
        empty_scalars_3,
        contentGeometry(24, 16),
    );
    try std.testing.expectEqual(accepted_revision, recovered.revision);
    try std.testing.expectEqualDeep(
        accepted_commands[0..accepted_count],
        recovered.commands,
    );
}

test "narrow-symbol normalization is bounded and transactional" {
    if (comptime !selected.native_text) return error.SkipZigTest;
    var compatible: [65]terminal_text.NarrowSymbolRange = undefined;
    for (&compatible, 0..) |*range, index| range.* = .{
        .first = @intCast(0xe000 + compatible.len - 1 - index),
        .last = @intCast(0xe000 + compatible.len - 1 - index),
        .cells = 1,
    };
    const merged_config = terminal_text.FontConfig{
        .key = .{ .slot = 0, .style = .normal },
        .native = .{ .primary = fonts.symbol_font, .size = .{ .pixels = 18 } },
        .narrow_symbols = &compatible,
    };
    var merged = try terminal_text.FontMap.init(
        std.testing.allocator,
        &.{merged_config},
    );
    defer merged.deinit();

    var full: [terminal_text.max_narrow_symbol_ranges]terminal_text.NarrowSymbolRange =
        undefined;
    for (&full, 0..) |*range, index| range.* = .{
        .first = @intCast(0x1000 + index * 2),
        .last = @intCast(0x1000 + index * 2),
        .cells = 1,
    };
    var accepted = try terminal_text.FontMap.init(std.testing.allocator, &.{
        .{
            .key = .{ .slot = 0, .style = .normal },
            .native = .{ .primary = fonts.primary_font, .size = .{ .pixels = 16 } },
            .narrow_symbols = &full,
        },
    });
    defer accepted.deinit();
    const before = accepted.cellMetrics(.{ .slot = 0, .style = .normal }).?;

    var overflow: [65]terminal_text.NarrowSymbolRange = undefined;
    for (&overflow, 0..) |*range, index| range.* = .{
        .first = @intCast(0x2000 + index * 2),
        .last = @intCast(0x2000 + index * 2),
        .cells = 1,
    };
    try std.testing.expectError(
        error.TooManyNarrowSymbolRanges,
        terminal_text.FontMap.init(std.testing.allocator, &.{
            .{
                .key = .{ .slot = 0, .style = .normal },
                .native = .{ .primary = fonts.primary_font, .size = .{ .pixels = 16 } },
                .narrow_symbols = &overflow,
            },
        }),
    );
    try std.testing.expectEqual(
        before,
        accepted.cellMetrics(.{ .slot = 0, .style = .normal }).?,
    );

    const conflict = [_]terminal_text.NarrowSymbolRange{
        .{ .first = 0xe000, .last = 0xe010, .cells = 1 },
        .{ .first = 0xe008, .last = 0xe020, .cells = 2 },
    };
    try std.testing.expectError(
        error.ConflictingNarrowSymbolRange,
        terminal_text.FontMap.init(std.testing.allocator, &.{
            .{
                .key = .{ .slot = 0, .style = .normal },
                .native = .{ .primary = fonts.primary_font, .size = .{ .pixels = 16 } },
                .narrow_symbols = &conflict,
            },
        }),
    );
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(terminal_text.NarrowSymbolRange));
    try std.testing.expectEqual(@as(usize, 520), @sizeOf(terminal_text.FontMap) - 64 * @sizeOf(?render.text.FontSet));
}

test "narrow-symbol cap and generated exclusion preserve one-cell presentation" {
    if (comptime !selected.native_text) return error.SkipZigTest;
    const narrow = [_]terminal_text.NarrowSymbolRange{
        .{ .first = 0xf303, .last = 0xf303, .cells = 1 },
    };
    var map = try terminal_text.FontMap.init(std.testing.allocator, &.{
        .{
            .key = .{ .slot = 0, .style = .normal },
            .native = .{ .primary = fonts.symbol_font, .size = .{ .pixels = 18 } },
            .narrow_symbols = &narrow,
        },
    });
    defer map.deinit();
    var scratch = try TestScratch.init();
    defer scratch.deinit();
    const private_cells = [_]terminal.Cell{ cell(0xf303), cell(' '), cell(' ') };
    const private_run = try prepare(
        &scratch,
        &map,
        input(&private_cells, 0, 2),
        0,
    );
    try std.testing.expectEqual(
        @as(u16, 1),
        private_run.glyphs.native[0].key.native.cell_span,
    );

    const generated_cells = [_]terminal.Cell{ cell(0xe0b0), cell(' '), cell(' ') };
    const generated_run = try prepare(
        &scratch,
        &map,
        input(&generated_cells, 0, 2),
        0,
    );
    try std.testing.expect(generated_run.glyphs == .generated);
    try std.testing.expectEqual(@as(u16, 1), generated_run.end_cell);
}

test "fallback private-use presentation selects and retains the fallback face" {
    if (comptime !selected.native_text) return error.SkipZigTest;
    const fallback_paths = [_][]const u8{fonts.symbol_font};
    var map = try terminal_text.FontMap.init(std.testing.allocator, &.{
        .{
            .key = .{ .slot = 0, .style = .normal },
            .native = .{
                .primary = fonts.primary_font,
                .fallbacks = &fallback_paths,
                .size = .{ .pixels = 18 },
            },
        },
    });
    defer map.deinit();
    var scratch = try TestScratch.init();
    defer scratch.deinit();
    const cells = [_]terminal.Cell{ cell(0xf303), cell(' '), cell(' ') };
    var row = input(&cells, 0, 2);
    row.ligature_mode = .cursor;
    row.cursor_col = 1;
    const run = try prepare(&scratch, &map, row, 0);
    try std.testing.expect(run.glyphs == .native);
    try std.testing.expect(run.glyphs.native[0].key.native.face_index != 0);
    try std.testing.expectEqual(@as(u16, 3), run.end_cell);
}

test "native missing tuple and glyph failures preserve reusable scratch" {
    if (comptime !selected.native_text) return error.SkipZigTest;
    var map = try initMap();
    defer deinitMap(&map);
    var scratch = try TestScratch.init();
    defer scratch.deinit();
    var styled = [_]terminal.Cell{cell('A')};
    styled[0].bold = true;
    try std.testing.expectError(
        error.MissingFontConfiguration,
        terminal_text.prepareNextRun(
            &map,
            input(&styled, 0, 0),
            0,
            scratch.borrow(),
        ),
    );
    var missing = [_]terminal.Cell{cell(0x10ffff)};
    const omitted = try terminal_text.prepareNextRun(
        &map,
        input(&missing, 0, 0),
        0,
        scratch.borrow(),
    );
    try std.testing.expect(omitted.glyphs == .none);
    try std.testing.expectEqual(@as(u16, 0), omitted.first_cell);
    try std.testing.expectEqual(@as(u16, 1), omitted.end_cell);
    var ordinary = [_]terminal.Cell{cell('A')};
    const reusable = try terminal_text.prepareNextRun(
        &map,
        input(&ordinary, 0, 0),
        0,
        scratch.borrow(),
    );
    try std.testing.expect(reusable.glyphs.native.len > 0);
}

test "font map validates complete tuple set before native ownership" {
    if (comptime !selected.native_text) return error.SkipZigTest;
    const normal = terminal_text.FontConfig{
        .key = .{ .slot = 0, .style = .normal },
        .native = .{ .primary = fonts.primary_font, .size = .{ .pixels = 16 } },
    };
    try std.testing.expectError(
        error.MissingDefaultConfiguration,
        terminal_text.FontMap.init(std.testing.failing_allocator, &.{}),
    );
    try std.testing.expectError(
        error.DuplicateConfiguration,
        terminal_text.FontMap.init(std.testing.failing_allocator, &.{ normal, normal }),
    );
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        constructMap,
        .{},
    );
}

test "Fira normal strategy classifies groups and places one exact ligature span" {
    if (comptime !selected.native_text) return error.SkipZigTest;
    const configs = [_]terminal_text.FontConfig{.{
        .key = .{ .slot = 0, .style = .normal },
        .native = .{
            .primary = fonts.normal_ligature_font,
            .size = .{ .pixels = 32 },
        },
    }};
    var map = try terminal_text.FontMap.init(std.testing.allocator, &configs);
    defer map.deinit();
    var scratch = try TestScratch.init();
    defer scratch.deinit();
    var cells = [_]terminal.Cell{ cell('#'), cell('_'), cell('(') };
    var row = input(&cells, 0, 2);
    row.geometry = .single_width;
    row.metrics = map.cellMetrics(.{ .slot = 0, .style = .normal }).?;

    const run = try terminal_text.prepareNextRun(
        &map,
        row,
        0,
        scratch.borrow(),
    );
    try std.testing.expectEqual(@as(u16, 0), run.first_cell);
    try std.testing.expectEqual(@as(u16, 3), run.end_cell);
    try std.testing.expectEqual(@as(usize, 3), run.glyphs.native.len);
    for (run.glyphs.native, 0..) |glyph, index| {
        try std.testing.expectEqual(@as(u16, 0), glyph.source_start);
        try std.testing.expectEqual(@as(u16, 3), glyph.source_end);
        try std.testing.expectEqual(@as(u16, 3), glyph.key.native.cell_span);
        try std.testing.expectEqual(
            @as(i32, @intCast(index * row.metrics.width_px * 64)),
            glyph.x_26_6,
        );
        try std.testing.expectEqual(@as(u16, @intCast(index)), glyph.group_glyph_index);
    }
}

test "native combining clusters reuse caller storage" {
    if (comptime !selected.native_text) return error.SkipZigTest;
    var map = try initMap();
    defer deinitMap(&map);
    var scratch = try TestScratch.init();
    defer scratch.deinit();
    var cells = [_]terminal.Cell{ cell('A'), cell('B') };
    cells[0].combining_len = 2;
    cells[0].combining[0] = 0x0301;
    cells[0].combining[1] = 0x0302;
    const run = try terminal_text.prepareNextRun(
        &map,
        input(&cells, 0, 1),
        0,
        scratch.borrow(),
    );
    try std.testing.expect(run.glyphs.native.len >= 3);
    var repeated_coverage = false;
    var previous_start: ?u16 = null;
    for (run.glyphs.native) |glyph| {
        try std.testing.expect(glyph.source_start < glyph.source_end);
        try std.testing.expect(glyph.source_end <= 2);
        repeated_coverage = repeated_coverage or previous_start == glyph.source_start;
        previous_start = glyph.source_start;
    }
    try std.testing.expect(repeated_coverage);

    const first_pointer = run.glyphs.native.ptr;
    const first_key = run.glyphs.native[0].key;
    cells[0] = cell('C');
    cells[1] = cell('D');
    const reused = try terminal_text.prepareNextRun(
        &map,
        input(&cells, 0, 1),
        0,
        scratch.borrow(),
    );
    try std.testing.expectEqual(first_pointer, reused.glyphs.native.ptr);
    try std.testing.expect(!std.meta.eql(first_key, reused.glyphs.native[0].key));
}

test "native optional coverage omission preserves adjacent terminal glyphs" {
    if (comptime !selected.native_text) return error.SkipZigTest;
    var map = try initMap();
    defer deinitMap(&map);
    var scratch = try TestScratch.init();
    defer scratch.deinit();
    var cells = [_]terminal.Cell{ cell('A'), cell(0x10ffff), cell('B') };
    const row = input(&cells, 0, 2);
    const before = try terminal_text.prepareNextRun(&map, row, 0, scratch.borrow());
    try std.testing.expect(before.glyphs == .native);
    try std.testing.expectEqual(@as(u16, 1), before.end_cell);
    const missing = try terminal_text.prepareNextRun(&map, row, 1, scratch.borrow());
    try std.testing.expect(missing.glyphs == .none);
    try std.testing.expectEqual(@as(u16, 2), missing.end_cell);
    const after = try terminal_text.prepareNextRun(&map, row, 2, scratch.borrow());
    try std.testing.expect(after.glyphs == .native);
    try std.testing.expectEqual(@as(u16, 3), after.end_cell);
}

test "native scratch capacity failures preserve unwritten destinations" {
    if (comptime !selected.native_text) return error.SkipZigTest;
    var map = try initMap();
    defer deinitMap(&map);
    var scratch = try TestScratch.init();
    defer scratch.deinit();
    var cells = [_]terminal.Cell{cell('A')};
    cells[0].combining_len = 1;
    cells[0].combining[0] = 0x0301;
    const row = input(&cells, 0, 0);
    const scalar_sentinel = [_]u32{ 0xaaaaaaaa, 0xbbbbbbbb };
    const glyph_sentinel = render.text.Glyph{
        .id = 0xaaaaaaaa,
        .cluster = 0xbbbbbbbb,
        .x_advance = -1,
        .y_advance = -2,
        .x_offset = -3,
        .y_offset = -4,
    };
    const positioned_sentinel = terminal_text.PositionedGlyph{
        .key = .{ .native = .{
            .font = .{ .slot = 0, .style = .normal },
            .face_index = 7,
            .glyph_id = 0xaaaaaaaa,
            .cell_span = 9,
        } },
        .source_start = 7,
        .source_end = 9,
        .x_26_6 = -1,
        .y_26_6 = -2,
        .x_advance_26_6 = -3,
        .y_advance_26_6 = -4,
    };
    var codepoints = scalar_sentinel;
    var clusters = scalar_sentinel;
    var shaped = [_]render.text.Glyph{glyph_sentinel};
    var positioned = [_]terminal_text.PositionedGlyph{positioned_sentinel};
    try std.testing.expectError(error.InsufficientCodepoints, terminal_text.prepareNextRun(
        &map,
        row,
        0,
        .{
            .shaper = &scratch.shaper,
            .codepoints = codepoints[0..1],
            .clusters = &clusters,
            .shaped = &shaped,
            .positioned = &positioned,
        },
    ));
    try std.testing.expectEqualSlices(u32, &scalar_sentinel, &codepoints);
    try std.testing.expectEqualSlices(u32, &scalar_sentinel, &clusters);
    try std.testing.expectEqual(glyph_sentinel, shaped[0]);
    try std.testing.expectEqual(positioned_sentinel, positioned[0]);

    try std.testing.expectError(error.InsufficientClusters, terminal_text.prepareNextRun(
        &map,
        row,
        0,
        .{
            .shaper = &scratch.shaper,
            .codepoints = &codepoints,
            .clusters = clusters[0..1],
            .shaped = &shaped,
            .positioned = &positioned,
        },
    ));
    try std.testing.expectEqualSlices(u32, &scalar_sentinel, &codepoints);
    try std.testing.expectEqualSlices(u32, &scalar_sentinel, &clusters);
    try std.testing.expectEqual(glyph_sentinel, shaped[0]);
    try std.testing.expectEqual(positioned_sentinel, positioned[0]);

    try std.testing.expectError(error.InsufficientGlyphs, terminal_text.prepareNextRun(
        &map,
        row,
        0,
        .{
            .shaper = &scratch.shaper,
            .codepoints = &codepoints,
            .clusters = &clusters,
            .shaped = shaped[0..0],
            .positioned = &positioned,
        },
    ));
    try std.testing.expectEqual(glyph_sentinel, shaped[0]);
    try std.testing.expectEqual(positioned_sentinel, positioned[0]);

    try std.testing.expectError(error.InsufficientPositionedGlyphs, terminal_text.prepareNextRun(
        &map,
        row,
        0,
        .{
            .shaper = &scratch.shaper,
            .codepoints = &codepoints,
            .clusters = &clusters,
            .shaped = &shaped,
            .positioned = positioned[0..0],
        },
    ));
    try std.testing.expectEqual(positioned_sentinel, positioned[0]);
}

test "undersized strategy scratch rejects before Content output mutation" {
    if (comptime !selected.native_text) return error.SkipZigTest;
    const configs = [_]terminal_text.FontConfig{.{
        .key = .{ .slot = 0, .style = .normal },
        .native = .{ .primary = fonts.symbol_font, .size = .{ .pixels = 32 } },
    }};
    var map = try terminal_text.FontMap.init(std.testing.allocator, &configs);
    defer map.deinit();
    var scratch = try TestScratch.init();
    defer scratch.deinit();
    const cells = [_]terminal.Cell{ cell('!'), cell('=') };
    var row = input(&cells, 0, 1);
    row.geometry = .single_width;
    row.metrics = map.cellMetrics(.{ .slot = 0, .style = .normal }).?;
    const positioned_sentinel = terminal_text.PositionedGlyph{
        .key = .{ .native = .{
            .font = .{ .slot = 0, .style = .normal },
            .face_index = 7,
            .glyph_id = 0xaaaaaaaa,
            .cell_span = 9,
        } },
        .source_start = 7,
        .source_end = 9,
        .x_26_6 = -1,
        .y_26_6 = -2,
        .x_advance_26_6 = -3,
        .y_advance_26_6 = -4,
    };
    const glyph_sentinel = std.mem.zeroes(render.text.Glyph);
    var shaped = [_]render.text.Glyph{ glyph_sentinel, glyph_sentinel };
    var positioned = [_]terminal_text.PositionedGlyph{
        positioned_sentinel,
        positioned_sentinel,
    };
    try std.testing.expectError(
        error.InsufficientGlyphs,
        terminal_text.prepareNextRun(&map, row, 0, .{
            .shaper = &scratch.shaper,
            .codepoints = scratch.codepoints[0..2],
            .clusters = scratch.clusters[0..2],
            .shaped = &shaped,
            .positioned = &positioned,
        }),
    );
    try std.testing.expectEqual(glyph_sentinel, shaped[0]);
    try std.testing.expectEqual(glyph_sentinel, shaped[1]);
    try std.testing.expectEqual(positioned_sentinel, positioned[0]);
    try std.testing.expectEqual(positioned_sentinel, positioned[1]);

    var content = try terminal.Content.init(
        std.testing.allocator,
        contentLimits(),
        &map,
    );
    defer content.deinit();
    var work = try terminal.Content.Work.init(
        std.testing.allocator,
        content.limits,
    );
    defer work.deinit();
    const rows = [_]terminal.LineGeometry{.single_width};
    const initial_cells = [_]terminal.Cell{cell('A')};
    try content.recover(.{
        .rows = 1,
        .cols = 1,
        .cursor = hiddenCursor(),
        .cells = &initial_cells,
        .geometry = &rows,
    }, emptyImages());
    const initial = try content.takeUpdate(
        &work,
        terminal.ScalarBaseline.empty(1),
        contentGeometry(row.metrics.width_px, row.metrics.height_px),
        .{},
        .local,
    );
    try std.testing.expect(initial.commands.len != 0);
    try content.recover(.{
        .rows = 1,
        .cols = 2,
        .cursor = hiddenCursor(),
        .cells = &cells,
        .geometry = &rows,
    }, emptyImages());
    const revision_before = content.producer_revision;
    const glyph_count_before = content.glyph_count;
    const identity_before = content.next_resource_id;
    const original_glyphs = work.native_glyphs;
    const original_positioned = work.native_positioned;
    work.native_glyphs = work.native_glyphs[0..2];
    work.native_positioned = work.native_positioned[0..2];
    defer {
        work.native_glyphs = original_glyphs;
        work.native_positioned = original_positioned;
    }
    try std.testing.expectError(
        error.InsufficientGlyphs,
        content.takeUpdate(
            &work,
            terminal.ScalarBaseline.empty(2),
            .{
                .x = 0,
                .y = 0,
                .clip = .{
                    .x = 0,
                    .y = 0,
                    .width = row.metrics.width_px * 2,
                    .height = row.metrics.height_px,
                },
                .metrics = row.metrics,
                .generated_box = generatedBoxConfig(),
                .underline_y = row.metrics.height_px - 2,
                .underline_height = 1,
                .strike_y = row.metrics.height_px / 2,
                .strike_height = 1,
            },
            .{},
            .local,
        ),
    );
    try std.testing.expectEqual(revision_before, content.producer_revision);
    try std.testing.expectEqual(glyph_count_before, content.glyph_count);
    try std.testing.expectEqual(identity_before, content.next_resource_id);
}

const Map = if (selected.native_text) terminal_text.FontMap else void;
const TestScratch = if (selected.native_text) struct {
    shaper: render.text.ShapeBuffer,
    codepoints: [64]u32 = undefined,
    clusters: [64]u32 = undefined,
    shaped: [64]render.text.Glyph = undefined,
    positioned: [64]terminal_text.PositionedGlyph = undefined,

    fn init() !@This() {
        return .{ .shaper = try render.text.ShapeBuffer.init(64) };
    }

    fn deinit(self: *@This()) void {
        self.shaper.deinit();
        self.* = undefined;
    }

    fn borrow(self: *@This()) terminal_text.NativeScratch {
        return .{
            .shaper = &self.shaper,
            .codepoints = &self.codepoints,
            .clusters = &self.clusters,
            .shaped = &self.shaped,
            .positioned = &self.positioned,
        };
    }
} else struct {
    fn init() !@This() {
        return .{};
    }

    fn deinit(_: *@This()) void {}
};

fn initMap() !Map {
    if (comptime selected.native_text) {
        const configs = [_]terminal_text.FontConfig{.{
            .key = .{ .slot = 0, .style = .normal },
            .native = .{ .primary = fonts.primary_font, .size = .{ .pixels = 16 } },
        }};
        return terminal_text.FontMap.init(std.testing.allocator, &configs);
    }
    return {};
}

fn initContent(map: *Map) !terminal.Content {
    if (comptime selected.native_text)
        return terminal.Content.init(std.testing.allocator, contentLimits(), map);
    return terminal.Content.init(std.testing.allocator, contentLimits(), {});
}

fn constructContent(allocator: std.mem.Allocator, map: *Map) !void {
    var content = if (comptime selected.native_text)
        try terminal.Content.init(allocator, contentLimits(), map)
    else
        try terminal.Content.init(allocator, contentLimits(), {});
    content.deinit();
}

fn contentGeometry(width: u16, height: u16) terminal.Content.Geometry {
    return .{
        .x = 0,
        .y = 0,
        .clip = .{ .x = 0, .y = 0, .width = width, .height = height },
        .metrics = metrics,
        .generated_box = generatedBoxConfig(),
        .underline_y = 14,
        .underline_height = 1,
        .strike_y = 8,
        .strike_height = 1,
    };
}

fn deinitMap(map: *Map) void {
    if (comptime selected.native_text) map.deinit();
}

fn prepare(
    scratch: *TestScratch,
    map: *Map,
    row: terminal_text.RowInput,
    at: u16,
) terminal_text.PrepareError!terminal_text.PreparedRun {
    if (comptime selected.native_text)
        return terminal_text.prepareNextRun(map, row, at, scratch.borrow());
    return terminal_text.prepareNextRun(row, at);
}

fn rasterize(
    map: *Map,
    allocator: std.mem.Allocator,
    key: terminal_text.GlyphKey,
) terminal_text.RasterError!terminal_text.Raster {
    if (comptime selected.native_text)
        return terminal_text.rasterizeGlyph(allocator, map, key);
    return terminal_text.rasterizeGlyph(allocator, key);
}

fn constructMap(allocator: std.mem.Allocator) !void {
    const configs = [_]terminal_text.FontConfig{.{
        .key = .{ .slot = 0, .style = .normal },
        .native = .{ .primary = fonts.primary_font, .size = .{ .pixels = 16 } },
    }};
    var map = try terminal_text.FontMap.init(allocator, &configs);
    map.deinit();
}

fn input(cells: []const terminal.Cell, start: u16, end: u16) terminal_text.RowInput {
    return .{
        .cells = cells,
        .scalars = terminal.ScalarBaseline.empty(cells.len),
        .scalar_offset = 0,
        .affected_start = start,
        .affected_end = end,
        .geometry = .double_height_top,
        .metrics = metrics,
        .generated_box = generatedBoxConfig(),
    };
}

fn generatedBoxConfig() terminal_text.GeneratedBoxConfig {
    return .{
        .dpi_x = .{ .numerator = 96, .denominator = 1 },
        .dpi_y = .{ .numerator = 96, .denominator = 1 },
    };
}

fn cell(codepoint: u21) terminal.Cell {
    return .{
        .codepoint = codepoint,
        .combining_len = 0,
        .combining = @splat(0),
        .foreground = .{ .r = 0, .g = 0, .b = 0 },
        .background = .{ .r = 0, .g = 0, .b = 0 },
        .underline_color = .{ .r = 0, .g = 0, .b = 0 },
        .font = 0,
        .baseline = .normal,
        .bold = false,
        .dim = false,
        .italic = false,
        .blink = false,
        .blink_fast = false,
        .invisible = false,
        .underline = false,
        .strikethrough = false,
        .underline_style = .none,
        .selected = false,
        .link_id = 0,
    };
}

fn hiddenCursor() terminal.Cursor {
    return .{
        .row = 0,
        .col = 0,
        .visible = false,
        .shape = .none,
        .blink = false,
        .color = .{ .r = 0, .g = 0, .b = 0 },
        .text_color = .{ .r = 0, .g = 0, .b = 0 },
    };
}

fn unchangedProjection(rows: u16, cols: u16) terminal.Update {
    return .{
        .rows = rows,
        .cols = cols,
        .full = false,
        .cells = &.{},
        .row_patches = &.{},
        .cursor = hiddenCursor(),
    };
}

fn emptyImages() render.terminal_images.Update {
    return .{
        .generation = 1,
        .content_generation = 1,
        .pixels = &.{},
        .uploads = &.{},
        .removals = &.{},
        .placements = &.{},
    };
}
