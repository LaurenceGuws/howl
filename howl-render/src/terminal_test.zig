//! Proves bounded terminal Canvas presentation without terminal truth duplication.

const std = @import("std");
const render = @import("howl_render");
const client = @import("howl_client");
const fonts = @import("test_fonts");
const generated = @import("generated_glyphs");

fn presentation() client.rich.Presentation {
    return .{
        .cursor_age_ns = null,
        .presence_bits = 0,
        .flags = 0,
        .reverse_screen = false,
        .palette = @splat(.{ .r = 0, .g = 0, .b = 0, .a = 0xff }),
        .foreground = .{ .r = 0xee, .g = 0xee, .b = 0xee, .a = 0xff },
        .background = .{ .r = 1, .g = 2, .b = 3, .a = 0xff },
        .cursor = null,
        .cursor_text = null,
        .selection_background = null,
        .selection_foreground = null,
    };
}

fn cell(scalars: []u32, width: u8, x: u8) client.rich.Cell {
    return .{
        .scalars = scalars,
        .width = width,
        .height = 1,
        .x = x,
        .y = 0,
        .subscale_n = 0,
        .subscale_d = 0,
        .vertical_align = 0,
        .horizontal_align = 0,
        .semantic_width = width > 1,
        .font = 0,
        .baseline = 0,
        .underline_style = 0,
        .protection = 0,
        .style_bits = 1,
        .foreground = .{ .kind = .rgb, .value = 0xabcdef },
        .background = .{ .kind = .default, .value = 0 },
        .underline_color = .{ .kind = .default, .value = 0 },
        .link_id = 0,
    };
}

fn sourceSnapshot(rows: []client.rich.Row, columns: u16) client.rich.Snapshot {
    return .{
        .allocator = std.testing.allocator,
        .begin = .{
            .revision = 17,
            .terminal_revision = 11,
            .history_offset = 0,
            .history_count = 0,
            .history_row_base = 0,
            .rows = @intCast(rows.len),
            .columns = columns,
            .cursor_row = 0,
            .cursor_column = 0,
            .cursor_shape = 0,
            .cursor_visible = false,
            .cursor_blink = false,
            .alternate_screen = false,
            .stream_closed = false,
            .child_exited = false,
            .leader_present = false,
            .you_are_leader = false,
        },
        .presentation = presentation(),
        .rows = rows,
        .hyperlinks = &.{},
    };
}

fn contentConfig(command_capacity: usize) render.terminal.ContentConfig {
    return .{
        .cell_size = .{ .width = 10, .height = 20 },
        .box_drawing = .{
            .dpi_x = .{ .numerator = 96, .denominator = 1 },
            .dpi_y = .{ .numerator = 96, .denominator = 1 },
        },
        .shape_cache = .{
            .entry_capacity = 16,
            .scalar_capacity = 32,
            .glyph_capacity = 32,
            .max_sequence_scalars = 8,
        },
        .atlas = .{ .width = 64, .height = 64, .entry_capacity = 16 },
        .shaped_capacity = 16,
        .raster_bytes = 4096,
        .command_capacity = command_capacity,
    };
}

fn contentFont() !*render.text.FontSet {
    return render.text.FontSet.init(std.testing.allocator, .{
        .primary = fonts.primary_font,
        .size = .{ .pixels = 16 },
    });
}

fn firstAlphaResource(commands: []const render.canvas.Input) ?render.canvas.ResourceRef {
    for (commands) |command| switch (command) {
        .alpha_mask => |value| return value.resource.resource,
        else => {},
    };
    return null;
}

fn firstRgba(commands: []const render.canvas.Input) ?@FieldType(render.canvas.Input, "rgba") {
    for (commands) |command| switch (command) {
        .rgba => |value| return value,
        else => {},
    };
    return null;
}

fn constructTerminalContent(allocator: std.mem.Allocator, font: *render.text.FontSet) !void {
    const content = try render.terminal.initContent(allocator, font, contentConfig(64));
    render.terminal.deinitContent(content);
}

test "terminal Canvas emits one Host-bound RGBA image across presentation lattices" {
    var a = [_]u32{'A'};
    var row0_cells = [_]client.rich.Cell{
        cell(&a, 1, 0),
        cell(&.{}, 1, 0),
        cell(&.{}, 1, 0),
        cell(&.{}, 1, 0),
    };
    var row1_cells = [_]client.rich.Cell{
        cell(&.{}, 1, 0),
        cell(&.{}, 1, 0),
        cell(&.{}, 1, 0),
        cell(&.{}, 1, 0),
    };
    var rows = [_]client.rich.Row{
        .{ .wrapped = false, .line_geometry = 0, .cells = &row0_cells },
        .{ .wrapped = false, .line_geometry = 0, .cells = &row1_cells },
    };
    var images = [_]client.view.Image{.{
        .image_id = 7,
        .generation = 9,
        .width = 2,
        .height = 2,
    }};
    var placements = [_]client.view.ImagePlacement{.{
        .image_id = 7,
        .generation = 3,
        .row = 1,
        .column = 2,
        .source_x = 0,
        .source_y = 0,
        .source_width = 2,
        .source_height = 2,
        .cell_x = 0,
        .cell_y = 0,
        .pixel_width = 20,
        .pixel_height = 20,
        .z = 0,
    }};
    var source = sourceSnapshot(&rows, 4);
    source.graphics = .{
        .generation = 11,
        .content_generation = 10,
        .cell_pixel_width = 10,
        .cell_pixel_height = 20,
        .images = &images,
        .placements = &placements,
    };
    const view = try client.view.project(std.testing.allocator, &source);
    defer client.view.deinit(view);
    const font = try contentFont();
    defer font.deinit();
    const image_resource = render.canvas.ResourceRef{
        .resource = try render.canvas.ResourceId.local(2),
        .generation = @fromBackingInt(1),
    };
    const binding = render.terminal.ExternalImageBinding{
        .image_id = 7,
        .generation = 9,
        .resource = image_resource,
    };
    const cases = [_]struct {
        cell_size: render.canvas.Size,
        destination: render.canvas.Rect,
    }{
        .{
            .cell_size = .{ .width = 10, .height = 20 },
            .destination = .{ .x = 20, .y = 20, .width = 20, .height = 20 },
        },
        .{
            .cell_size = .{ .width = 8, .height = 15 },
            .destination = .{ .x = 16, .y = 15, .width = 16, .height = 15 },
        },
        .{
            .cell_size = .{ .width = 6, .height = 12 },
            .destination = .{ .x = 12, .y = 12, .width = 12, .height = 12 },
        },
    };
    for (cases, 0..) |case, case_index| {
        var config = contentConfig(64);
        config.cell_size = case.cell_size;
        const content = try render.terminal.initContent(std.testing.allocator, font, config);
        defer render.terminal.deinitContent(content);
        const update = try render.terminal.takeContentUpdateWithImageBinding(
            content,
            view,
            null,
            binding,
        );
        try std.testing.expectEqual(@as(usize, 1), update.uploads.len);
        try std.testing.expectEqual(@as(usize, 1), update.external_resources.len);
        try std.testing.expectEqual(@as(usize, 0), update.removals.len);
        try std.testing.expectEqualDeep(image_resource, update.external_resources[0].resource);
        try std.testing.expectEqual(render.canvas.ResourceFormat.rgba8, update.external_resources[0].format);
        try std.testing.expectEqualDeep(
            render.canvas.Size{ .width = 2, .height = 2 },
            update.external_resources[0].size,
        );
        try std.testing.expectEqual(@as(usize, 8), update.external_resources[0].stride);
        const rgba = firstRgba(update.commands) orelse return error.MissingCanvasRgbaResource;
        try std.testing.expectEqualDeep(case.destination, rgba.destination);
        try std.testing.expectEqualDeep(
            render.canvas.SourceRect{ .x = 0, .y = 0, .width = 2, .height = 2 },
            rgba.resource.source.?,
        );
        try std.testing.expectEqualDeep(image_resource, rgba.resource.resource);
        try std.testing.expectEqual(
            @as(usize, 2),
            render.terminal.contentUsage(content).resource_high_water,
        );
        switch (update.commands[update.commands.len - 1]) {
            .rgba => {},
            else => return error.ImageNotAboveText,
        }

        if (case_index == 0) {
            var composer = try render.canvas.Composer.init(std.testing.allocator, .{
                .sources = 1,
                .retained_resources = 4,
                .retained_commands = 64,
                .retained_pixel_bytes = 4096,
                .composition_sources = 1,
                .candidate_resources = 4,
                .candidate_commands = 64,
                .candidate_pixel_bytes = 4096,
            });
            defer composer.deinit();
            const producer = try composer.registerSource();
            try composer.apply(producer, update);
            try composer.setComposition(.{
                .surface = .{ .width = 40, .height = 40 },
                .sources = &.{.{
                    .source = producer,
                    .origin = .{ .x = 0, .y = 0 },
                    .clip = .{ .x = 0, .y = 0, .width = 40, .height = 40 },
                }},
            });
            var frame_uploads: [4]render.canvas.FrameResourceUpload = undefined;
            var frame_removals: [4]render.canvas.FrameResourceRef = undefined;
            var frame_commands: [64]render.canvas.Command = undefined;
            var frame_pixels: [4096]u8 = undefined;
            const buffers = render.canvas.Composer.FrameBuffers{
                .uploads = &frame_uploads,
                .removals = &frame_removals,
                .commands = &frame_commands,
                .pixels = &frame_pixels,
            };
            try std.testing.expectError(
                error.MissingExternalResource,
                composer.frame(&.{}, buffers),
            );
            var missing_storage: [1]render.canvas.FrameExternalResource = undefined;
            const missing = try composer.missingExternalResources(&.{}, &missing_storage);
            try std.testing.expectEqual(@as(usize, 1), missing.len);
            try std.testing.expectEqualDeep(image_resource, render.canvas.ResourceRef{
                .resource = missing[0].resource.resource,
                .generation = missing[0].resource.generation,
            });
            const resident = render.canvas.Residency{
                .resource = try render.canvas.FrameResourceRef.local(producer, image_resource),
                .format = .rgba8,
                .size = .{ .width = 2, .height = 2 },
            };
            const frame = try composer.frame(&.{resident}, buffers);
            try std.testing.expectEqual(@as(usize, 1), frame.uploads.len);
            var saw_rgba = false;
            for (frame.commands) |command| switch (command) {
                .rgba => saw_rgba = true,
                else => {},
            };
            try std.testing.expect(saw_rgba);
        }

        const stable = try render.terminal.takeContentUpdateWithImageBinding(
            content,
            view,
            null,
            binding,
        );
        try std.testing.expectEqual(@as(usize, 0), stable.uploads.len);
        try std.testing.expectEqual(@as(usize, 0), stable.external_resources.len);
        try std.testing.expect(firstRgba(stable.commands) != null);
        var without_image = source;
        without_image.graphics = .{};
        const text_view = try client.view.project(std.testing.allocator, &without_image);
        defer client.view.deinit(text_view);
        const image_disabled = try render.terminal.takeContentUpdate(content, text_view, null);
        try std.testing.expectEqual(@as(usize, 1), image_disabled.removals.len);
        try std.testing.expectEqualDeep(image_resource, image_disabled.removals[0].resource);
        try std.testing.expect(firstRgba(image_disabled.commands) == null);
    }
}

test "terminal Canvas places Kitty z phases around cell backgrounds and foreground" {
    var a = [_]u32{'A'};
    var cells = [_]client.rich.Cell{cell(&a, 1, 0)};
    cells[0].background = .{ .kind = .rgb, .value = 0x112233 };
    cells[0].underline_color = .{ .kind = .rgb, .value = 0x445566 };
    cells[0].style_bits |= (1 << 7) | (1 << 8);
    var rows = [_]client.rich.Row{.{
        .wrapped = false,
        .line_geometry = 0,
        .cells = &cells,
    }};
    var images = [_]client.view.Image{.{
        .image_id = 7,
        .generation = 9,
        .width = 1,
        .height = 1,
    }};
    var placements = [_]client.view.ImagePlacement{.{
        .image_id = 7,
        .generation = 3,
        .row = 0,
        .column = 0,
        .source_x = 0,
        .source_y = 0,
        .source_width = 1,
        .source_height = 1,
        .cell_x = 0,
        .cell_y = 0,
        .pixel_width = 10,
        .pixel_height = 20,
        .z = 0,
    }};
    var source = sourceSnapshot(&rows, 1);
    source.graphics = .{
        .generation = 11,
        .content_generation = 10,
        .cell_pixel_width = 10,
        .cell_pixel_height = 20,
        .images = &images,
        .placements = &placements,
    };
    const image_resource = render.canvas.ResourceRef{
        .resource = try render.canvas.ResourceId.local(2),
        .generation = @fromBackingInt(1),
    };
    const binding = render.terminal.ExternalImageBinding{
        .image_id = 7,
        .generation = 9,
        .resource = image_resource,
    };
    const default_background = render.canvas.Color{ .r = 1, .g = 2, .b = 3, .a = 255 };
    const cell_background = render.canvas.Color{ .r = 0x11, .g = 0x22, .b = 0x33, .a = 255 };
    const decoration = render.canvas.Color{ .r = 0x44, .g = 0x55, .b = 0x66, .a = 255 };
    const threshold: i32 = std.math.minInt(i32) / 2;
    const cases = [_]struct {
        z: i32,
        phase: enum { below_cell_background, below_foreground, above_foreground },
    }{
        .{ .z = threshold - 1, .phase = .below_cell_background },
        .{ .z = threshold, .phase = .below_foreground },
        .{ .z = -1, .phase = .below_foreground },
        .{ .z = 0, .phase = .above_foreground },
    };

    for (cases) |case| {
        placements[0].z = case.z;
        const view = try client.view.project(std.testing.allocator, &source);
        defer client.view.deinit(view);
        const font = try contentFont();
        defer font.deinit();
        const content = try render.terminal.initContent(
            std.testing.allocator,
            font,
            contentConfig(16),
        );
        defer render.terminal.deinitContent(content);
        const update = try render.terminal.takeContentUpdateWithImageBinding(
            content,
            view,
            null,
            binding,
        );

        var default_index: ?usize = null;
        var cell_background_index: ?usize = null;
        var first_decoration_index: ?usize = null;
        var first_glyph_index: ?usize = null;
        var image_index: ?usize = null;
        for (update.commands, 0..) |command, index| switch (command) {
            .solid => |solid| {
                if (std.meta.eql(solid.color, default_background) and default_index == null)
                    default_index = index;
                if (std.meta.eql(solid.color, cell_background) and cell_background_index == null)
                    cell_background_index = index;
                if (std.meta.eql(solid.color, decoration) and first_decoration_index == null)
                    first_decoration_index = index;
            },
            .alpha_mask => {
                if (first_glyph_index == null) first_glyph_index = index;
            },
            .rgba => {
                image_index = index;
            },
        };
        const default_at = default_index orelse return error.MissingDefaultBackground;
        const cell_background_at = cell_background_index orelse return error.MissingCellBackground;
        const decoration_at = first_decoration_index orelse return error.MissingDecoration;
        const glyph_at = first_glyph_index orelse return error.MissingCanvasAlphaResource;
        const image_at = image_index orelse return error.MissingCanvasRgbaResource;
        try std.testing.expect(default_at < cell_background_at);
        try std.testing.expect(cell_background_at < decoration_at);
        try std.testing.expect(decoration_at < glyph_at);
        switch (case.phase) {
            .below_cell_background => {
                try std.testing.expect(default_at < image_at);
                try std.testing.expect(image_at < cell_background_at);
            },
            .below_foreground => {
                try std.testing.expect(cell_background_at < image_at);
                try std.testing.expect(image_at < decoration_at);
            },
            .above_foreground => try std.testing.expect(glyph_at < image_at),
        }
    }
}

test "terminal Canvas retains bounded images and sorts placements by z then generation" {
    var cells: [4]client.rich.Cell = undefined;
    for (&cells) |*value| value.* = cell(&.{}, 1, 0);
    var rows = [_]client.rich.Row{.{
        .wrapped = false,
        .line_geometry = 0,
        .cells = &cells,
    }};
    var images = [_]client.view.Image{
        .{ .image_id = 7, .generation = 9, .width = 1, .height = 1 },
        .{ .image_id = 8, .generation = 10, .width = 1, .height = 1 },
    };
    var placements = [_]client.view.ImagePlacement{
        .{
            .image_id = 7,
            .generation = 30,
            .row = 0,
            .column = 0,
            .source_x = 0,
            .source_y = 0,
            .source_width = 1,
            .source_height = 1,
            .cell_x = 0,
            .cell_y = 0,
            .pixel_width = 10,
            .pixel_height = 20,
            .z = 0,
        },
        .{
            .image_id = 8,
            .generation = 20,
            .row = 0,
            .column = 1,
            .source_x = 0,
            .source_y = 0,
            .source_width = 1,
            .source_height = 1,
            .cell_x = 0,
            .cell_y = 0,
            .pixel_width = 10,
            .pixel_height = 20,
            .z = -1,
        },
        .{
            .image_id = 7,
            .generation = 10,
            .row = 0,
            .column = 2,
            .source_x = 0,
            .source_y = 0,
            .source_width = 1,
            .source_height = 1,
            .cell_x = 0,
            .cell_y = 0,
            .pixel_width = 10,
            .pixel_height = 20,
            .z = -1,
        },
        .{
            .image_id = 8,
            .generation = 40,
            .row = 0,
            .column = 3,
            .source_x = 0,
            .source_y = 0,
            .source_width = 1,
            .source_height = 1,
            .cell_x = 0,
            .cell_y = 0,
            .pixel_width = 10,
            .pixel_height = 20,
            .z = 0,
        },
    };
    var source = sourceSnapshot(&rows, 4);
    source.graphics = .{
        .generation = 50,
        .content_generation = 40,
        .cell_pixel_width = 10,
        .cell_pixel_height = 20,
        .images = &images,
        .placements = &placements,
    };
    const font = try contentFont();
    defer font.deinit();
    const content = try render.terminal.initContent(
        std.testing.allocator,
        font,
        contentConfig(16),
    );
    defer render.terminal.deinitContent(content);
    const resource_one = render.canvas.ResourceRef{
        .resource = try render.canvas.ResourceId.local(1),
        .generation = @fromBackingInt(1),
    };
    const resource_two = render.canvas.ResourceRef{
        .resource = try render.canvas.ResourceId.local(2),
        .generation = @fromBackingInt(1),
    };
    var bindings = [_]render.terminal.ExternalImageBinding{
        .{ .image_id = 7, .generation = 9, .resource = resource_one },
        .{ .image_id = 8, .generation = 10, .resource = resource_two },
    };

    const view = try client.view.project(std.testing.allocator, &source);
    defer client.view.deinit(view);
    const first = try render.terminal.takeContentUpdateWithImageBindings(
        content,
        view,
        null,
        &bindings,
    );
    try std.testing.expectEqual(@as(usize, 2), first.external_resources.len);
    try std.testing.expectEqual(@as(usize, 0), first.removals.len);
    try std.testing.expectEqual(@as(usize, 2), render.terminal.contentUsage(content).resource_high_water);
    var rgba_destinations: [4]render.canvas.Rect = undefined;
    var rgba_resources: [4]render.canvas.ResourceRef = undefined;
    var rgba_count: usize = 0;
    for (first.commands) |command| switch (command) {
        .rgba => |rgba| {
            rgba_destinations[rgba_count] = rgba.destination;
            rgba_resources[rgba_count] = rgba.resource.resource;
            rgba_count += 1;
        },
        else => {},
    };
    try std.testing.expectEqual(@as(usize, 4), rgba_count);
    try std.testing.expectEqualDeep(
        [4]render.canvas.Rect{
            .{ .x = 20, .y = 0, .width = 10, .height = 20 },
            .{ .x = 10, .y = 0, .width = 10, .height = 20 },
            .{ .x = 0, .y = 0, .width = 10, .height = 20 },
            .{ .x = 30, .y = 0, .width = 10, .height = 20 },
        },
        rgba_destinations,
    );
    try std.testing.expectEqualDeep(
        [4]render.canvas.ResourceRef{ resource_one, resource_two, resource_one, resource_two },
        rgba_resources,
    );

    const stable = try render.terminal.takeContentUpdateWithImageBindings(
        content,
        view,
        null,
        &bindings,
    );
    try std.testing.expectEqual(@as(usize, 0), stable.external_resources.len);
    try std.testing.expectEqual(@as(usize, 0), stable.removals.len);

    images[0].generation = 11;
    bindings[0].generation = 11;
    bindings[0].resource.generation = @fromBackingInt(2);
    const replacement_view = try client.view.project(std.testing.allocator, &source);
    defer client.view.deinit(replacement_view);
    const replaced = try render.terminal.takeContentUpdateWithImageBindings(
        content,
        replacement_view,
        null,
        &bindings,
    );
    try std.testing.expectEqual(@as(usize, 1), replaced.external_resources.len);
    try std.testing.expectEqual(@as(usize, 0), replaced.removals.len);
    try std.testing.expectEqual(bindings[0].resource, replaced.external_resources[0].resource);

    source.graphics.images = images[0..1];
    var one_placement = [_]client.view.ImagePlacement{placements[2]};
    source.graphics.placements = &one_placement;
    const one_view = try client.view.project(std.testing.allocator, &source);
    defer client.view.deinit(one_view);
    const removed = try render.terminal.takeContentUpdateWithImageBindings(
        content,
        one_view,
        null,
        bindings[0..1],
    );
    try std.testing.expectEqual(@as(usize, 1), removed.removals.len);
    try std.testing.expectEqual(resource_two, removed.removals[0].resource);

    source.graphics.images = &images;
    source.graphics.placements = &placements;
    var bad_bindings = bindings;
    bad_bindings[1].resource = resource_two;
    const restored_view = try client.view.project(std.testing.allocator, &source);
    defer client.view.deinit(restored_view);
    try std.testing.expectError(
        error.InvalidImageBinding,
        render.terminal.takeContentUpdateWithImageBindings(
            content,
            restored_view,
            null,
            &bad_bindings,
        ),
    );
    const resource_three = render.canvas.ResourceRef{
        .resource = try render.canvas.ResourceId.local(3),
        .generation = @fromBackingInt(1),
    };
    bindings[1].resource = resource_three;
    const restored = try render.terminal.takeContentUpdateWithImageBindings(
        content,
        restored_view,
        null,
        &bindings,
    );
    try std.testing.expectEqual(@as(usize, 1), restored.external_resources.len);
    try std.testing.expectEqual(@as(usize, 0), restored.removals.len);
    try std.testing.expectEqual(resource_three, restored.external_resources[0].resource);
    try std.testing.expectEqual(@as(usize, 3), render.terminal.contentUsage(content).resource_high_water);
}

test "terminal Canvas admits seven image resources and rejects the eighth transactionally" {
    const count = render.terminal.maximum_external_images + 1;
    var glyph = [_]u32{'A'};
    var cells: [count]client.rich.Cell = undefined;
    for (&cells) |*value| value.* = cell(&.{}, 1, 0);
    cells[0] = cell(&glyph, 1, 0);
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    var images: [count]client.view.Image = undefined;
    var placements: [count]client.view.ImagePlacement = undefined;
    var bindings: [count]render.terminal.ExternalImageBinding = undefined;
    for (0..count) |index| {
        const image_id: u32 = @intCast(index + 1);
        const generation: u64 = @intCast(index + 10);
        images[index] = .{ .image_id = image_id, .generation = generation, .width = 1, .height = 1 };
        placements[index] = .{
            .image_id = image_id,
            .generation = @intCast(index + 20),
            .row = 0,
            .column = @intCast(index),
            .source_x = 0,
            .source_y = 0,
            .source_width = 1,
            .source_height = 1,
            .cell_x = 0,
            .cell_y = 0,
            .pixel_width = 10,
            .pixel_height = 20,
            .z = 0,
        };
        bindings[index] = .{
            .image_id = image_id,
            .generation = generation,
            .resource = .{
                .resource = try render.canvas.ResourceId.local(index + 2),
                .generation = @fromBackingInt(@intCast(generation)),
            },
        };
    }
    var source = sourceSnapshot(&rows, @intCast(count));
    source.graphics = .{
        .generation = 40,
        .content_generation = 30,
        .cell_pixel_width = 10,
        .cell_pixel_height = 20,
        .images = images[0..render.terminal.maximum_external_images],
        .placements = placements[0..render.terminal.maximum_external_images],
    };
    const font = try contentFont();
    defer font.deinit();
    const content = try render.terminal.initContent(
        std.testing.allocator,
        font,
        contentConfig(16),
    );
    defer render.terminal.deinitContent(content);
    const accepted_view = try client.view.project(std.testing.allocator, &source);
    defer client.view.deinit(accepted_view);
    const accepted = try render.terminal.takeContentUpdateWithImageBindings(
        content,
        accepted_view,
        null,
        bindings[0..render.terminal.maximum_external_images],
    );
    try std.testing.expectEqual(@as(usize, 1), accepted.uploads.len);
    try std.testing.expectEqual(render.terminal.maximum_external_images, accepted.external_resources.len);
    try std.testing.expectEqual(
        @as(usize, 8),
        render.terminal.contentUsage(content).resource_high_water,
    );
    const usage = render.terminal.contentUsage(content);

    source.graphics.images = &images;
    source.graphics.placements = &placements;
    const rejected_view = try client.view.project(std.testing.allocator, &source);
    defer client.view.deinit(rejected_view);
    try std.testing.expectError(
        error.ImageLimit,
        render.terminal.takeContentUpdateWithImageBindings(
            content,
            rejected_view,
            null,
            &bindings,
        ),
    );
    try std.testing.expectEqualDeep(usage, render.terminal.contentUsage(content));
    const stable = try render.terminal.takeContentUpdateWithImageBindings(
        content,
        accepted_view,
        null,
        bindings[0..render.terminal.maximum_external_images],
    );
    try std.testing.expectEqual(@as(usize, 0), stable.external_resources.len);
    try std.testing.expectEqual(@as(usize, 0), stable.removals.len);
}

test "terminal Canvas multi-placement command exhaustion preserves published resources" {
    var cells = [_]client.rich.Cell{
        cell(&.{}, 1, 0),
        cell(&.{}, 1, 0),
    };
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    var images = [_]client.view.Image{.{
        .image_id = 7,
        .generation = 9,
        .width = 1,
        .height = 1,
    }};
    var placements = [_]client.view.ImagePlacement{
        .{
            .image_id = 7,
            .generation = 10,
            .row = 0,
            .column = 0,
            .source_x = 0,
            .source_y = 0,
            .source_width = 1,
            .source_height = 1,
            .cell_x = 0,
            .cell_y = 0,
            .pixel_width = 10,
            .pixel_height = 20,
            .z = 0,
        },
        .{
            .image_id = 7,
            .generation = 11,
            .row = 0,
            .column = 1,
            .source_x = 0,
            .source_y = 0,
            .source_width = 1,
            .source_height = 1,
            .cell_x = 0,
            .cell_y = 0,
            .pixel_width = 10,
            .pixel_height = 20,
            .z = 0,
        },
    };
    var source = sourceSnapshot(&rows, 2);
    source.graphics = .{
        .generation = 20,
        .content_generation = 19,
        .cell_pixel_width = 10,
        .cell_pixel_height = 20,
        .images = &images,
        .placements = placements[0..1],
    };
    const font = try contentFont();
    defer font.deinit();
    const content = try render.terminal.initContent(
        std.testing.allocator,
        font,
        contentConfig(2),
    );
    defer render.terminal.deinitContent(content);
    const binding = render.terminal.ExternalImageBinding{
        .image_id = 7,
        .generation = 9,
        .resource = .{
            .resource = try render.canvas.ResourceId.local(1),
            .generation = @fromBackingInt(1),
        },
    };
    const accepted_view = try client.view.project(std.testing.allocator, &source);
    defer client.view.deinit(accepted_view);
    const accepted = try render.terminal.takeContentUpdateWithImageBinding(
        content,
        accepted_view,
        null,
        binding,
    );
    try std.testing.expectEqual(@as(usize, 1), accepted.external_resources.len);
    const usage = render.terminal.contentUsage(content);

    source.graphics.placements = &placements;
    const rejected_view = try client.view.project(std.testing.allocator, &source);
    defer client.view.deinit(rejected_view);
    try std.testing.expectError(
        error.CommandLimit,
        render.terminal.takeContentUpdateWithImageBinding(
            content,
            rejected_view,
            null,
            binding,
        ),
    );
    try std.testing.expectEqualDeep(usage, render.terminal.contentUsage(content));
    const stable = try render.terminal.takeContentUpdateWithImageBinding(
        content,
        accepted_view,
        null,
        binding,
    );
    try std.testing.expectEqual(@as(usize, 0), stable.external_resources.len);
    try std.testing.expectEqual(@as(usize, 0), stable.removals.len);
}

test "terminal Canvas keeps image-first and later atlas identities monotonic" {
    var empty_cells = [_]client.rich.Cell{cell(&.{}, 1, 0)};
    var empty_rows = [_]client.rich.Row{.{
        .wrapped = false,
        .line_geometry = 0,
        .cells = &empty_cells,
    }};
    var images = [_]client.view.Image{.{
        .image_id = 4,
        .generation = 8,
        .width = 1,
        .height = 1,
    }};
    var placements = [_]client.view.ImagePlacement{.{
        .image_id = 4,
        .generation = 2,
        .row = 0,
        .column = 0,
        .source_x = 0,
        .source_y = 0,
        .source_width = 1,
        .source_height = 1,
        .cell_x = 0,
        .cell_y = 0,
        .pixel_width = 10,
        .pixel_height = 20,
        .z = 0,
    }};
    var image_source = sourceSnapshot(&empty_rows, 1);
    image_source.graphics = .{
        .generation = 3,
        .content_generation = 2,
        .cell_pixel_width = 10,
        .cell_pixel_height = 20,
        .images = &images,
        .placements = &placements,
    };
    const image_view = try client.view.project(std.testing.allocator, &image_source);
    defer client.view.deinit(image_view);

    var a = [_]u32{'A'};
    var text_cells = [_]client.rich.Cell{cell(&a, 1, 0)};
    var text_rows = [_]client.rich.Row{.{
        .wrapped = false,
        .line_geometry = 0,
        .cells = &text_cells,
    }};
    const text_source = sourceSnapshot(&text_rows, 1);
    const text_view = try client.view.project(std.testing.allocator, &text_source);
    defer client.view.deinit(text_view);

    const font = try contentFont();
    defer font.deinit();
    const content = try render.terminal.initContent(
        std.testing.allocator,
        font,
        contentConfig(16),
    );
    defer render.terminal.deinitContent(content);
    var composer = try render.canvas.Composer.init(std.testing.allocator, .{
        .sources = 1,
        .retained_resources = 4,
        .retained_commands = 16,
        .retained_pixel_bytes = 4096,
        .composition_sources = 1,
        .candidate_resources = 4,
        .candidate_commands = 16,
        .candidate_pixel_bytes = 4096,
    });
    defer composer.deinit();
    const producer = try composer.registerSource();

    const image_one = render.canvas.ResourceRef{
        .resource = try render.canvas.ResourceId.local(1),
        .generation = @fromBackingInt(1),
    };
    const first = try render.terminal.takeContentUpdateWithImageBinding(
        content,
        image_view,
        null,
        .{ .image_id = 4, .generation = 8, .resource = image_one },
    );
    try std.testing.expectEqual(@as(usize, 0), first.uploads.len);
    try std.testing.expectEqual(@as(usize, 1), first.external_resources.len);
    try std.testing.expectEqual(@as(u64, 1), render.terminal.contentUsage(content).resource_high_water);
    try composer.apply(producer, first);

    const second = try render.terminal.takeContentUpdate(content, text_view, null);
    try std.testing.expectEqual(@as(usize, 1), second.removals.len);
    try std.testing.expectEqualDeep(image_one, second.removals[0].resource);
    try std.testing.expectEqual(@as(usize, 1), second.uploads.len);
    const atlas_resource = firstAlphaResource(second.commands) orelse
        return error.MissingCanvasAlphaResource;
    try std.testing.expectEqual(@as(u64, 2), try atlas_resource.resource.identity());
    try std.testing.expectEqual(@as(u64, 2), render.terminal.contentUsage(content).resource_high_water);
    try composer.apply(producer, second);

    try std.testing.expectError(
        error.InvalidImageBinding,
        render.terminal.takeContentUpdateWithImageBinding(
            content,
            image_view,
            null,
            .{ .image_id = 4, .generation = 8, .resource = image_one },
        ),
    );
    const image_three = render.canvas.ResourceRef{
        .resource = try render.canvas.ResourceId.local(3),
        .generation = @fromBackingInt(1),
    };
    const third = try render.terminal.takeContentUpdateWithImageBinding(
        content,
        image_view,
        null,
        .{ .image_id = 4, .generation = 8, .resource = image_three },
    );
    try std.testing.expectEqual(@as(usize, 1), third.external_resources.len);
    try std.testing.expectEqualDeep(image_three, third.external_resources[0].resource);
    try std.testing.expectEqual(@as(u64, 3), render.terminal.contentUsage(content).resource_high_water);
    try composer.apply(producer, third);
}

test "terminal Canvas content reuses exact combining runs" {
    var first = [_]u32{ 'e', 0x0301 };
    var second = [_]u32{ 'e', 0x0301 };
    var cells = [_]client.rich.Cell{
        cell(&first, 1, 0),
        cell(&second, 1, 0),
    };
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    const source = sourceSnapshot(&rows, 2);
    const view = try client.view.project(std.testing.allocator, &source);
    defer client.view.deinit(view);
    const font = try contentFont();
    defer font.deinit();
    const content = try render.terminal.initContent(std.testing.allocator, font, contentConfig(64));
    defer render.terminal.deinitContent(content);

    const first_update = try render.terminal.takeContentUpdate(content, view, null);
    try std.testing.expect(firstAlphaResource(first_update.commands) != null);
    const usage = render.terminal.contentUsage(content);
    try std.testing.expectEqual(@as(usize, 1), usage.shape.entries);
    try std.testing.expectEqual(@as(usize, 2), usage.shape.scalars);
    try std.testing.expect(usage.shape.glyphs != 0);

    const second_update = try render.terminal.takeContentUpdate(content, view, null);
    try std.testing.expectEqual(@as(usize, 0), second_update.uploads.len);
    try std.testing.expectEqualDeep(usage.shape, render.terminal.contentUsage(content).shape);
}

test "terminal Canvas contextually shapes bounded primary operators without collapsing cells" {
    var dash = [_]u32{'-'};
    var greater = [_]u32{'>'};
    var contextual_cells = [_]client.rich.Cell{
        cell(&dash, 1, 0),
        cell(&greater, 1, 0),
    };
    var contextual_rows = [_]client.rich.Row{.{
        .wrapped = false,
        .line_geometry = 0,
        .cells = &contextual_cells,
    }};
    const contextual_source = sourceSnapshot(&contextual_rows, 2);
    const contextual_view = try client.view.project(std.testing.allocator, &contextual_source);
    defer client.view.deinit(contextual_view);
    const font = try render.text.FontSet.init(std.testing.allocator, .{
        .primary = fonts.normal_ligature_font,
        .size = .{ .pixels = 16 },
    });
    defer font.deinit();
    const contextual = try render.terminal.initContent(
        std.testing.allocator,
        font,
        contentConfig(64),
    );
    defer render.terminal.deinitContent(contextual);

    const contextual_update = try render.terminal.takeContentUpdate(
        contextual,
        contextual_view,
        null,
    );
    try std.testing.expectEqual(@as(usize, 1), contextual_update.uploads.len);
    try std.testing.expectEqualDeep(
        render.terminal.ShapeCacheUsage{ .entries = 0, .scalars = 0, .glyphs = 0 },
        render.terminal.contentUsage(contextual).shape,
    );

    var split_cells = contextual_cells;
    split_cells[1].style_bits |= 1 << 2;
    var split_rows = [_]client.rich.Row{.{
        .wrapped = false,
        .line_geometry = 0,
        .cells = &split_cells,
    }};
    const split_source = sourceSnapshot(&split_rows, 2);
    const split_view = try client.view.project(std.testing.allocator, &split_source);
    defer client.view.deinit(split_view);
    const split = try render.terminal.initContent(
        std.testing.allocator,
        font,
        contentConfig(64),
    );
    defer render.terminal.deinitContent(split);
    const split_update = try render.terminal.takeContentUpdate(split, split_view, null);
    try std.testing.expectEqual(@as(usize, 1), split_update.uploads.len);
    try std.testing.expectEqual(@as(usize, 2), render.terminal.contentUsage(split).shape.entries);
    try std.testing.expect(!std.mem.eql(
        u8,
        contextual_update.uploads[0].pixels.bytes,
        split_update.uploads[0].pixels.bytes,
    ));
}

test "terminal Canvas content routes generated glyphs outside font shaping" {
    var symbol = [_]u32{0xe0b0};
    var cells = [_]client.rich.Cell{cell(&symbol, 1, 0)};
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    const source = sourceSnapshot(&rows, 1);
    const view = try client.view.project(std.testing.allocator, &source);
    defer client.view.deinit(view);
    const font = try contentFont();
    defer font.deinit();
    const content = try render.terminal.initContent(std.testing.allocator, font, contentConfig(64));
    defer render.terminal.deinitContent(content);

    const update = try render.terminal.takeContentUpdate(content, view, null);
    try std.testing.expect(firstAlphaResource(update.commands) != null);
    const usage = render.terminal.contentUsage(content);
    try std.testing.expectEqual(@as(usize, 0), usage.shape.entries);
    try std.testing.expectEqual(@as(usize, 1), usage.atlas_entries);
}

test "terminal Canvas generated box raster matches Kitty-derived cell geometry" {
    var symbol = [_]u32{0x2500};
    var cells = [_]client.rich.Cell{cell(&symbol, 1, 0)};
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    const source = sourceSnapshot(&rows, 1);
    const view = try client.view.project(std.testing.allocator, &source);
    defer client.view.deinit(view);
    const font = try contentFont();
    defer font.deinit();
    const config = contentConfig(64);
    const content = try render.terminal.initContent(std.testing.allocator, font, config);
    defer render.terminal.deinitContent(content);

    const update = try render.terminal.takeContentUpdate(content, view, null);
    try std.testing.expectEqual(@as(usize, 1), update.uploads.len);
    var expected: [10 * 20]u8 = undefined;
    try generated.rasterizeBox(
        &expected,
        10,
        20,
        symbol[0],
        config.box_drawing,
        .{},
    );
    const atlas = update.uploads[0].pixels;
    try std.testing.expectEqual(@as(u16, 64), atlas.width);
    try std.testing.expectEqual(@as(u16, 64), atlas.height);
    for (0..20) |row| {
        try std.testing.expectEqualSlices(
            u8,
            expected[row * 10 ..][0..10],
            atlas.bytes[row * atlas.stride ..][0..10],
        );
    }
    try std.testing.expectEqual(@as(usize, 0), render.terminal.contentUsage(content).shape.entries);
}

test "terminal Canvas projects DEC double width and height as clipped line transforms" {
    var block = [_]u32{0x2588};
    var empty = [_]u32{};
    var row0_cells = [_]client.rich.Cell{
        cell(&block, 1, 0),
        cell(&empty, 1, 0),
    };
    var row1_cells = row0_cells;
    var row2_cells = row0_cells;
    var row3_cells = row0_cells;
    var rows = [_]client.rich.Row{
        .{ .wrapped = false, .line_geometry = 0, .cells = &row0_cells },
        .{ .wrapped = false, .line_geometry = 1, .cells = &row1_cells },
        .{ .wrapped = false, .line_geometry = 2, .cells = &row2_cells },
        .{ .wrapped = false, .line_geometry = 3, .cells = &row3_cells },
    };
    var source = sourceSnapshot(&rows, 2);
    source.begin.cursor_visible = true;
    source.begin.cursor_row = 1;
    source.begin.cursor_column = 0;
    const view = try client.view.project(std.testing.allocator, &source);
    defer client.view.deinit(view);
    const font = try contentFont();
    defer font.deinit();
    const content = try render.terminal.initContent(std.testing.allocator, font, contentConfig(32));
    defer render.terminal.deinitContent(content);

    const update = try render.terminal.takeContentUpdate(content, view, .{
        .pane = 1,
        .source = @fromBackingInt(@intCast(1)),
        .visible_set_revision = 1,
        .lifecycle_revision = 1,
    });
    var destinations: [4]render.canvas.Rect = undefined;
    var clips: [4]render.canvas.Rect = undefined;
    var sources: [4]render.canvas.SourceRect = undefined;
    var alpha_count: usize = 0;
    for (update.commands) |command| switch (command) {
        .alpha_mask => |value| {
            if (alpha_count == destinations.len) return error.TooManyAlphaCommands;
            destinations[alpha_count] = value.destination;
            clips[alpha_count] = value.clip;
            sources[alpha_count] = value.resource.source.?;
            alpha_count += 1;
        },
        else => {},
    };
    try std.testing.expectEqual(destinations.len, alpha_count);
    try std.testing.expectEqualDeep(
        [4]render.canvas.Rect{
            .{ .x = 0, .y = 0, .width = 10, .height = 20 },
            .{ .x = 0, .y = 20, .width = 20, .height = 20 },
            .{ .x = 0, .y = 40, .width = 20, .height = 40 },
            .{ .x = 0, .y = 40, .width = 20, .height = 40 },
        },
        destinations,
    );
    try std.testing.expectEqualDeep(
        [4]render.canvas.Rect{
            .{ .x = 0, .y = 0, .width = 10, .height = 20 },
            .{ .x = 0, .y = 20, .width = 20, .height = 20 },
            .{ .x = 0, .y = 40, .width = 20, .height = 20 },
            .{ .x = 0, .y = 60, .width = 20, .height = 20 },
        },
        clips,
    );
    for (sources) |source_rect| {
        try std.testing.expectEqualDeep(
            render.canvas.SourceRect{ .x = 0, .y = 0, .width = 10, .height = 20 },
            source_rect,
        );
    }
    try std.testing.expectEqualDeep(
        render.canvas.Rect{ .x = 0, .y = 20, .width = 20, .height = 20 },
        update.cursor_binding.?.rect,
    );
    try std.testing.expectEqualDeep(
        render.canvas.Size{ .width = 20, .height = 20 },
        update.cursor_binding.?.cell_size,
    );
    try std.testing.expectEqual(@as(usize, 1), render.terminal.contentUsage(content).atlas_entries);
    try std.testing.expectEqual(@as(usize, 0), render.terminal.contentUsage(content).shape.entries);
}

test "terminal Canvas projects OSC 66 fraction and alignment inside the multicell allocation" {
    var block = [_]u32{0x2588};
    var empty = [_]u32{};
    var lead = cell(&block, 3, 0);
    lead.height = 3;
    lead.semantic_width = false;
    lead.subscale_n = 1;
    lead.subscale_d = 2;
    lead.vertical_align = 1;
    lead.horizontal_align = 2;
    var row0_cells = [_]client.rich.Cell{ lead, lead, lead };
    var row1_cells = row0_cells;
    var row2_cells = row0_cells;
    for (&row0_cells, 0..) |*value, x| {
        value.x = @intCast(x);
        if (x != 0) value.scalars = &empty;
    }
    for (&row1_cells, 0..) |*value, x| {
        value.x = @intCast(x);
        value.y = 1;
        value.scalars = &empty;
    }
    for (&row2_cells, 0..) |*value, x| {
        value.x = @intCast(x);
        value.y = 2;
        value.scalars = &empty;
    }
    var rows = [_]client.rich.Row{
        .{ .wrapped = false, .line_geometry = 0, .cells = &row0_cells },
        .{ .wrapped = false, .line_geometry = 0, .cells = &row1_cells },
        .{ .wrapped = false, .line_geometry = 0, .cells = &row2_cells },
    };
    const source = sourceSnapshot(&rows, 3);
    const view = try client.view.project(std.testing.allocator, &source);
    defer client.view.deinit(view);
    const font = try contentFont();
    defer font.deinit();
    const content = try render.terminal.initContent(std.testing.allocator, font, contentConfig(32));
    defer render.terminal.deinitContent(content);

    const update = try render.terminal.takeContentUpdate(content, view, null);
    var destination: ?render.canvas.Rect = null;
    var clip: ?render.canvas.Rect = null;
    var source_rect: ?render.canvas.SourceRect = null;
    for (update.commands) |command| switch (command) {
        .alpha_mask => |value| {
            if (destination != null) return error.TooManyAlphaCommands;
            destination = value.destination;
            clip = value.clip;
            source_rect = value.resource.source.?;
        },
        else => {},
    };
    try std.testing.expectEqualDeep(
        render.canvas.Rect{ .x = 7, .y = 30, .width = 15, .height = 30 },
        destination orelse return error.MissingCanvasAlphaResource,
    );
    try std.testing.expectEqualDeep(
        render.canvas.Rect{ .x = 0, .y = 0, .width = 30, .height = 60 },
        clip.?,
    );
    try std.testing.expectEqualDeep(
        render.canvas.SourceRect{ .x = 0, .y = 0, .width = 15, .height = 30 },
        source_rect.?,
    );
}

test "terminal Canvas scales the ordinary OSC 66 font raster instead of constructing a second font" {
    var a = [_]u32{'A'};
    var empty = [_]u32{};
    var lead = cell(&a, 2, 0);
    lead.height = 2;
    lead.semantic_width = false;
    var row0_cells = [_]client.rich.Cell{ lead, lead };
    var row1_cells = row0_cells;
    row0_cells[1].x = 1;
    row0_cells[1].scalars = &empty;
    row1_cells[0].y = 1;
    row1_cells[0].scalars = &empty;
    row1_cells[1].x = 1;
    row1_cells[1].y = 1;
    row1_cells[1].scalars = &empty;
    var rows = [_]client.rich.Row{
        .{ .wrapped = false, .line_geometry = 0, .cells = &row0_cells },
        .{ .wrapped = false, .line_geometry = 0, .cells = &row1_cells },
    };
    const source = sourceSnapshot(&rows, 2);
    const view = try client.view.project(std.testing.allocator, &source);
    defer client.view.deinit(view);
    const font = try contentFont();
    defer font.deinit();
    const content = try render.terminal.initContent(std.testing.allocator, font, contentConfig(32));
    defer render.terminal.deinitContent(content);

    const update = try render.terminal.takeContentUpdate(content, view, null);
    var destination: ?render.canvas.Rect = null;
    var clip: ?render.canvas.Rect = null;
    var source_rect: ?render.canvas.SourceRect = null;
    for (update.commands) |command| switch (command) {
        .alpha_mask => |value| {
            if (destination != null) return error.TooManyAlphaCommands;
            destination = value.destination;
            clip = value.clip;
            source_rect = value.resource.source.?;
        },
        else => {},
    };
    const alpha_destination = destination orelse return error.MissingCanvasAlphaResource;
    const alpha_source = source_rect.?;
    try std.testing.expectEqual(
        @as(u16, alpha_source.width * 2),
        alpha_destination.width,
    );
    try std.testing.expectEqual(
        @as(u16, alpha_source.height * 2),
        alpha_destination.height,
    );
    try std.testing.expectEqualDeep(
        render.canvas.Rect{ .x = 0, .y = 0, .width = 20, .height = 40 },
        clip.?,
    );
    try std.testing.expectEqual(@as(usize, 1), render.terminal.contentUsage(content).shape.entries);
}

test "terminal Canvas preserves ordinary font overhang across neighboring cells" {
    var empty = [_]u32{};
    var symbol = [_]u32{0xf303};
    var cells = [_]client.rich.Cell{
        cell(&empty, 1, 0),
        cell(&symbol, 1, 0),
        cell(&empty, 1, 0),
    };
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    const source = sourceSnapshot(&rows, 3);
    const view = try client.view.project(std.testing.allocator, &source);
    defer client.view.deinit(view);
    const font = try render.text.FontSet.init(std.testing.allocator, .{
        .primary = fonts.symbol_font,
        .size = .{ .pixels = 18 },
    });
    defer font.deinit();
    const content = try render.terminal.initContent(std.testing.allocator, font, contentConfig(16));
    defer render.terminal.deinitContent(content);

    const update = try render.terminal.takeContentUpdate(content, view, null);
    var glyph: ?@FieldType(render.canvas.Input, "alpha_mask") = null;
    for (update.commands) |command| switch (command) {
        .alpha_mask => |value| glyph = value,
        else => {},
    };
    const alpha = glyph orelse return error.MissingCanvasAlphaResource;
    const cell_left: i64 = 10;
    const cell_right: i64 = 20;
    const destination_right = @as(i64, alpha.destination.x) + alpha.destination.width;
    try std.testing.expect(alpha.destination.x < cell_left or destination_right > cell_right);
    try std.testing.expectEqualDeep(
        render.canvas.Rect{ .x = 0, .y = 0, .width = 30, .height = 20 },
        alpha.clip,
    );
}

test "terminal Canvas content retains howl-text whole-sequence fallback" {
    var variation = [_]u32{ '0', 0xfe00 };
    var cells = [_]client.rich.Cell{cell(&variation, 1, 0)};
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    const source = sourceSnapshot(&rows, 1);
    const view = try client.view.project(std.testing.allocator, &source);
    defer client.view.deinit(view);
    const fallbacks = [_][]const u8{fonts.symbol_font};
    const font = try render.text.FontSet.init(std.testing.allocator, .{
        .primary = fonts.primary_font,
        .fallbacks = &fallbacks,
        .size = .{ .pixels = 16 },
    });
    defer font.deinit();
    const content = try render.terminal.initContent(std.testing.allocator, font, contentConfig(64));
    defer render.terminal.deinitContent(content);

    const update = try render.terminal.takeContentUpdate(content, view, null);
    try std.testing.expect(firstAlphaResource(update.commands) != null);
    try std.testing.expectEqual(@as(usize, 1), render.terminal.contentUsage(content).shape.entries);
}

test "terminal Canvas shape entry exhaustion preserves published state" {
    var a = [_]u32{'A'};
    var a_cells = [_]client.rich.Cell{cell(&a, 1, 0)};
    var a_rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &a_cells }};
    const a_source = sourceSnapshot(&a_rows, 1);
    const a_view = try client.view.project(std.testing.allocator, &a_source);
    defer client.view.deinit(a_view);

    var b = [_]u32{'B'};
    var b_cells = [_]client.rich.Cell{cell(&b, 1, 0)};
    var b_rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &b_cells }};
    const b_source = sourceSnapshot(&b_rows, 1);
    const b_view = try client.view.project(std.testing.allocator, &b_source);
    defer client.view.deinit(b_view);

    const font = try contentFont();
    defer font.deinit();
    var config = contentConfig(64);
    config.shape_cache.entry_capacity = 1;
    const content = try render.terminal.initContent(std.testing.allocator, font, config);
    defer render.terminal.deinitContent(content);

    const accepted_update = try render.terminal.takeContentUpdate(content, a_view, null);
    try std.testing.expect(accepted_update.commands.len != 0);
    const accepted = render.terminal.contentUsage(content);
    try std.testing.expectError(
        error.ShapeEntryFull,
        render.terminal.takeContentUpdate(content, b_view, null),
    );
    try std.testing.expectEqualDeep(accepted, render.terminal.contentUsage(content));

    try render.terminal.resetContentCaches(content);
    const recovered = try render.terminal.takeContentUpdate(content, b_view, null);
    try std.testing.expect(firstAlphaResource(recovered.commands) != null);
}

test "terminal Canvas missing glyph degrades to replacement and remains reusable" {
    var missing = [_]u32{0x10ffff};
    var missing_cells = [_]client.rich.Cell{cell(&missing, 1, 0)};
    var missing_rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &missing_cells }};
    const missing_source = sourceSnapshot(&missing_rows, 1);
    const missing_view = try client.view.project(std.testing.allocator, &missing_source);
    defer client.view.deinit(missing_view);

    const font = try contentFont();
    defer font.deinit();
    const content = try render.terminal.initContent(std.testing.allocator, font, contentConfig(64));
    defer render.terminal.deinitContent(content);
    const missing_update = try render.terminal.takeContentUpdate(content, missing_view, null);
    try std.testing.expect(firstAlphaResource(missing_update.commands) != null);
    const missing_usage = render.terminal.contentUsage(content);
    try std.testing.expectEqual(@as(usize, 1), missing_usage.shape.entries);
    try std.testing.expectEqual(@as(usize, 1), missing_usage.shape.scalars);
    try std.testing.expect(missing_usage.shape.glyphs != 0);
    try std.testing.expect(missing_usage.atlas_entries != 0);
    try std.testing.expect(missing_usage.producer_revision != 0);

    var a = [_]u32{'A'};
    var a_cells = [_]client.rich.Cell{cell(&a, 1, 0)};
    var a_rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &a_cells }};
    const a_source = sourceSnapshot(&a_rows, 1);
    const a_view = try client.view.project(std.testing.allocator, &a_source);
    defer client.view.deinit(a_view);
    const update = try render.terminal.takeContentUpdate(content, a_view, null);
    try std.testing.expect(firstAlphaResource(update.commands) != null);
}

test "terminal Canvas atlas geometry failure never publishes" {
    var a = [_]u32{'A'};
    var cells = [_]client.rich.Cell{cell(&a, 1, 0)};
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    const source = sourceSnapshot(&rows, 1);
    const view = try client.view.project(std.testing.allocator, &source);
    defer client.view.deinit(view);
    const font = try contentFont();
    defer font.deinit();
    var config = contentConfig(64);
    config.atlas.width = 1;
    config.atlas.height = 1;
    const content = try render.terminal.initContent(std.testing.allocator, font, config);
    defer render.terminal.deinitContent(content);

    try std.testing.expectError(
        error.GlyphTooLarge,
        render.terminal.takeContentUpdate(content, view, null),
    );
    const usage = render.terminal.contentUsage(content);
    try std.testing.expectEqual(@as(u64, 0), usage.producer_revision);
    try std.testing.expectEqual(@as(u64, 0), usage.resource_generation);
    try std.testing.expectEqual(@as(usize, 0), usage.atlas_entries);
}

test "terminal Canvas content emits sparse atlas generations and Composer state" {
    var scalars = [_]u32{'A'};
    var cells = [_]client.rich.Cell{cell(&scalars, 1, 0)};
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    var source = sourceSnapshot(&rows, 1);
    source.begin.cursor_visible = true;
    source.begin.cursor_row = 0;
    source.begin.cursor_column = 0;
    const view = try client.view.project(std.testing.allocator, &source);
    defer client.view.deinit(view);

    const font = try contentFont();
    defer font.deinit();
    const content = try render.terminal.initContent(std.testing.allocator, font, contentConfig(64));
    defer render.terminal.deinitContent(content);

    var composer = try render.canvas.Composer.init(std.testing.allocator, .{
        .sources = 1,
        .retained_resources = 4,
        .retained_commands = 64,
        .retained_pixel_bytes = 4096,
        .composition_sources = 1,
        .candidate_resources = 4,
        .candidate_commands = 64,
        .candidate_pixel_bytes = 4096,
    });
    defer composer.deinit();
    const producer = try composer.registerSource();
    const cursor = render.terminal.CursorContext{
        .pane = 9,
        .source = producer,
        .visible_set_revision = 13,
        .lifecycle_revision = 15,
    };

    const first = try render.terminal.takeContentUpdate(content, view, cursor);
    try std.testing.expectEqual(@as(u64, 1), @backingInt(first.revision));
    try std.testing.expectEqual(@as(usize, 1), first.uploads.len);
    try std.testing.expect(first.commands.len >= 2);
    const first_resource = firstAlphaResource(first.commands) orelse
        return error.MissingCanvasAlphaResource;
    try std.testing.expectEqual(first.uploads[0].resource, first_resource);
    try std.testing.expectEqual(@as(u64, 9), first.cursor_binding.?.pane);
    try std.testing.expectEqual(producer, first.cursor_binding.?.source);
    try std.testing.expectEqual(@as(u64, 11), first.cursor_binding.?.terminal_sequence);
    try std.testing.expectEqual(@as(u64, 17), first.cursor_binding.?.cursor_revision);
    try std.testing.expectEqual(render.canvas.Size{ .width = 10, .height = 20 }, first.cursor_binding.?.cell_size);
    const first_generation = @backingInt(first_resource.generation);

    try composer.apply(producer, first);
    const placement = render.canvas.Composer.Placement{
        .source = producer,
        .origin = .{ .x = 0, .y = 0 },
        .clip = .{ .x = 0, .y = 0, .width = 10, .height = 20 },
    };
    try composer.setComposition(.{
        .surface = .{ .width = 10, .height = 20 },
        .sources = &.{placement},
        .focused_source = producer,
    });
    var frame_uploads: [4]render.canvas.FrameResourceUpload = undefined;
    var frame_removals: [4]render.canvas.FrameResourceRef = undefined;
    var frame_commands: [64]render.canvas.Command = undefined;
    var frame_pixels: [4096]u8 = undefined;
    const composed = try composer.frame(&.{}, .{
        .uploads = &frame_uploads,
        .removals = &frame_removals,
        .commands = &frame_commands,
        .pixels = &frame_pixels,
    });
    try std.testing.expectEqual(@as(usize, 1), composed.uploads.len);
    try std.testing.expect(composed.commands.len >= first.commands.len);

    const second = try render.terminal.takeContentUpdate(content, view, cursor);
    try std.testing.expectEqual(@as(u64, 2), @backingInt(second.revision));
    try std.testing.expectEqual(@as(usize, 0), second.uploads.len);
    const second_resource = firstAlphaResource(second.commands) orelse
        return error.MissingCanvasAlphaResource;
    try std.testing.expectEqual(first_generation, @backingInt(second_resource.generation));
    try composer.apply(producer, second);

    try render.terminal.resetContentCaches(content);
    const third = try render.terminal.takeContentUpdate(content, view, cursor);
    try std.testing.expectEqual(@as(usize, 1), third.uploads.len);
    const third_resource = firstAlphaResource(third.commands) orelse
        return error.MissingCanvasAlphaResource;
    try std.testing.expectEqual(first_generation + 1, @backingInt(third_resource.generation));
    try std.testing.expectEqualDeep(
        render.terminal.ContentUsage{
            .shape = .{ .entries = 1, .scalars = 1, .glyphs = 1 },
            .atlas_entries = 1,
            .producer_revision = 3,
            .resource_generation = first_generation + 1,
            .resource_high_water = 1,
        },
        render.terminal.contentUsage(content),
    );
}

test "terminal Canvas suppresses Kitty Unicode placeholder glyphs only" {
    var placeholder_scalars = [_]u32{ 0x10eeee, 0x0305, 0x0305 };
    var ordinary_scalars = [_]u32{'A'};
    var cells = [_]client.rich.Cell{
        cell(&placeholder_scalars, 1, 0),
        cell(&ordinary_scalars, 1, 0),
    };
    cells[0].background = .{ .kind = .rgb, .value = 0x112233 };
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    const source = sourceSnapshot(&rows, 2);
    const view = try client.view.project(std.testing.allocator, &source);
    defer client.view.deinit(view);
    const font = try contentFont();
    defer font.deinit();
    const content = try render.terminal.initContent(std.testing.allocator, font, contentConfig(32));
    defer render.terminal.deinitContent(content);
    const update = try render.terminal.takeContentUpdate(content, view, null);

    var alpha_count: usize = 0;
    var placeholder_background = false;
    for (update.commands) |command| switch (command) {
        .alpha_mask => |value| {
            alpha_count += 1;
            try std.testing.expect(value.destination.x >= 10);
        },
        .solid => |value| {
            if (value.rect.x == 0 and value.rect.width == 10 and
                std.meta.eql(value.color, render.canvas.Color{
                    .r = 0x11,
                    .g = 0x22,
                    .b = 0x33,
                    .a = 255,
                })) placeholder_background = true;
        },
        else => {},
    };
    try std.testing.expectEqual(@as(usize, 1), alpha_count);
    try std.testing.expect(placeholder_background);
}

test "terminal Canvas content resolves style color decoration and invisibility once" {
    var a = [_]u32{'A'};
    var b = [_]u32{'B'};
    var c = [_]u32{'C'};
    var cells = [_]client.rich.Cell{
        cell(&a, 1, 0),
        cell(&b, 1, 0),
        cell(&c, 1, 0),
    };
    cells[0].foreground = .{ .kind = .indexed, .value = 1 };
    cells[0].background = .{ .kind = .rgb, .value = 0x040506 };
    cells[0].style_bits = 1 << 1;
    cells[1].style_bits = (1 << 5) | (1 << 7) | (1 << 8);
    cells[1].underline_style = 3;
    cells[1].underline_color = .{ .kind = .rgb, .value = 0x445566 };
    cells[2].style_bits = 1 << 6;
    cells[2].background = .{ .kind = .indexed, .value = 4 };
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    var source = sourceSnapshot(&rows, 3);
    source.presentation.palette[1] = .{ .r = 205, .g = 49, .b = 49, .a = 255 };
    source.presentation.palette[4] = .{ .r = 36, .g = 114, .b = 200, .a = 255 };
    const view = try client.view.project(std.testing.allocator, &source);
    defer client.view.deinit(view);
    const font = try contentFont();
    defer font.deinit();
    const content = try render.terminal.initContent(std.testing.allocator, font, contentConfig(64));
    defer render.terminal.deinitContent(content);
    const update = try render.terminal.takeContentUpdate(content, view, null);

    var alpha_count: usize = 0;
    var saw_dim_red = false;
    var saw_reverse_foreground = false;
    var saw_a_background = false;
    var saw_b_background = false;
    var saw_invisible_background = false;
    var decoration_count: usize = 0;
    for (update.commands) |command| switch (command) {
        .alpha_mask => |value| {
            alpha_count += 1;
            if (value.destination.x < 10) {
                saw_dim_red = std.meta.eql(value.color, render.canvas.Color{
                    .r = 205,
                    .g = 49,
                    .b = 49,
                    .a = 140,
                });
            } else if (value.destination.x < 20) {
                saw_reverse_foreground = std.meta.eql(value.color, render.canvas.Color{
                    .r = 1,
                    .g = 2,
                    .b = 3,
                    .a = 255,
                });
            }
        },
        .solid => |value| {
            if (value.rect.x == 0 and value.rect.width == 10 and
                std.meta.eql(value.color, render.canvas.Color{ .r = 4, .g = 5, .b = 6, .a = 255 }))
                saw_a_background = true;
            if (value.rect.x == 10 and value.rect.width == 10 and
                std.meta.eql(value.color, render.canvas.Color{ .r = 0xab, .g = 0xcd, .b = 0xef, .a = 255 }))
                saw_b_background = true;
            if (value.rect.x == 20 and value.rect.width == 10 and
                std.meta.eql(value.color, render.canvas.Color{ .r = 36, .g = 114, .b = 200, .a = 255 }))
                saw_invisible_background = true;
            if (std.meta.eql(value.color, render.canvas.Color{ .r = 0x44, .g = 0x55, .b = 0x66, .a = 255 }))
                decoration_count += 1;
        },
        else => {},
    };
    try std.testing.expectEqual(@as(usize, 2), alpha_count);
    try std.testing.expect(saw_dim_red);
    try std.testing.expect(saw_reverse_foreground);
    try std.testing.expect(saw_a_background);
    try std.testing.expect(saw_b_background);
    try std.testing.expect(saw_invisible_background);
    try std.testing.expect(decoration_count >= 6);
}

test "terminal Canvas content failure preserves published revision and recovers" {
    var empty_cells = [_]client.rich.Cell{cell(&.{}, 1, 0)};
    var empty_rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &empty_cells }};
    const empty_source = sourceSnapshot(&empty_rows, 1);
    const empty_view = try client.view.project(std.testing.allocator, &empty_source);
    defer client.view.deinit(empty_view);

    var a = [_]u32{'A'};
    var a_cells = [_]client.rich.Cell{cell(&a, 1, 0)};
    var a_rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &a_cells }};
    const a_source = sourceSnapshot(&a_rows, 1);
    const a_view = try client.view.project(std.testing.allocator, &a_source);
    defer client.view.deinit(a_view);

    const font = try contentFont();
    defer font.deinit();
    const content = try render.terminal.initContent(std.testing.allocator, font, contentConfig(1));
    defer render.terminal.deinitContent(content);
    const first = try render.terminal.takeContentUpdate(content, empty_view, null);
    try std.testing.expectEqual(@as(u64, 1), @backingInt(first.revision));
    try std.testing.expectError(
        error.CommandLimit,
        render.terminal.takeContentUpdate(content, a_view, null),
    );
    const after_failure = render.terminal.contentUsage(content);
    try std.testing.expectEqual(@as(u64, 1), after_failure.producer_revision);
    try std.testing.expectEqual(@as(u64, 0), after_failure.resource_generation);
    try std.testing.expect(after_failure.atlas_entries != 0);
    const recovered = try render.terminal.takeContentUpdate(content, empty_view, null);
    try std.testing.expectEqual(@as(u64, 2), @backingInt(recovered.revision));
    try std.testing.expectEqual(@as(usize, 0), recovered.uploads.len);
}

test "dense 40x120 terminal Canvas presentation is bounded and transactional" {
    const row_count: usize = 40;
    const column_count: usize = 120;
    const cell_count = row_count * column_count;
    const command_count = cell_count + 1;

    var scalar = [_]u32{'A'};
    const cells = try std.testing.allocator.alloc(client.rich.Cell, cell_count);
    defer std.testing.allocator.free(cells);
    for (cells) |*value| value.* = cell(&scalar, 1, 0);

    const rows = try std.testing.allocator.alloc(client.rich.Row, row_count);
    defer std.testing.allocator.free(rows);
    for (rows, 0..) |*row, index| {
        const first = index * column_count;
        row.* = .{
            .wrapped = false,
            .line_geometry = 0,
            .cells = cells[first .. first + column_count],
        };
    }

    const source = sourceSnapshot(rows, column_count);
    const view = try client.view.project(std.testing.allocator, &source);
    defer client.view.deinit(view);
    const font = try contentFont();
    defer font.deinit();

    const limited = try render.terminal.initContent(
        std.testing.allocator,
        font,
        contentConfig(command_count - 1),
    );
    defer render.terminal.deinitContent(limited);
    try std.testing.expectError(
        error.CommandLimit,
        render.terminal.takeContentUpdate(limited, view, null),
    );
    const failed = render.terminal.contentUsage(limited);
    try std.testing.expectEqual(@as(u64, 0), failed.producer_revision);
    try std.testing.expectEqual(@as(u64, 0), failed.resource_generation);

    const exact = try render.terminal.initContent(
        std.testing.allocator,
        font,
        contentConfig(command_count),
    );
    defer render.terminal.deinitContent(exact);
    const update = try render.terminal.takeContentUpdate(exact, view, null);
    try std.testing.expectEqual(command_count, update.commands.len);
    try std.testing.expectEqual(@as(u64, 1), @backingInt(update.revision));
}

test "terminal Canvas cursor context is host-owned and transactional" {
    var scalars = [_]u32{'A'};
    var cells = [_]client.rich.Cell{cell(&scalars, 1, 0)};
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    var source = sourceSnapshot(&rows, 1);
    source.begin.cursor_visible = true;
    const view = try client.view.project(std.testing.allocator, &source);
    defer client.view.deinit(view);
    const font = try contentFont();
    defer font.deinit();
    const content = try render.terminal.initContent(std.testing.allocator, font, contentConfig(32));
    defer render.terminal.deinitContent(content);

    try std.testing.expectError(
        error.InvalidCursorContext,
        render.terminal.takeContentUpdate(content, view, .{
            .pane = 0,
            .source = @fromBackingInt(@intCast(1)),
            .visible_set_revision = 3,
            .lifecycle_revision = 5,
        }),
    );
    const failed = render.terminal.contentUsage(content);
    try std.testing.expectEqual(@as(u64, 0), failed.producer_revision);
    try std.testing.expectEqual(@as(u64, 0), failed.resource_generation);

    const update = try render.terminal.takeContentUpdate(content, view, .{
        .pane = 7,
        .source = @fromBackingInt(@intCast(11)),
        .visible_set_revision = 13,
        .lifecycle_revision = 17,
    });
    try std.testing.expectEqual(@as(u64, 7), update.cursor_binding.?.pane);
    try std.testing.expectEqual(@as(u64, 11), @backingInt(update.cursor_binding.?.source));
    try std.testing.expectEqual(@as(u64, 13), update.cursor_binding.?.visible_set_revision);
    try std.testing.expectEqual(@as(u64, 17), update.cursor_binding.?.lifecycle_revision);
    try std.testing.expectEqual(@as(u64, 1), render.terminal.contentUsage(content).producer_revision);
    try std.testing.expectEqual(@as(u64, 1), render.terminal.contentUsage(content).resource_generation);
}

test "terminal Canvas content construction releases every staged allocation" {
    const font = try contentFont();
    defer font.deinit();
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        constructTerminalContent,
        .{font},
    );
}

test "terminal Canvas content validates fixed presentation bounds before allocation" {
    const font = try contentFont();
    defer font.deinit();
    var invalid = contentConfig(64);
    invalid.cell_size.width = 0;
    try std.testing.expectError(
        error.InvalidContentConfig,
        render.terminal.initContent(std.testing.failing_allocator, font, invalid),
    );
    invalid = contentConfig(0);
    try std.testing.expectError(
        error.InvalidContentConfig,
        render.terminal.initContent(std.testing.failing_allocator, font, invalid),
    );
}

test "terminal Canvas failed richer frame publishes warmed atlas only on recovery" {
    var a = [_]u32{'A'};
    var a_cells = [_]client.rich.Cell{cell(&a, 1, 0)};
    var a_rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &a_cells }};
    const a_source = sourceSnapshot(&a_rows, 1);
    const a_view = try client.view.project(std.testing.allocator, &a_source);
    defer client.view.deinit(a_view);

    var b = [_]u32{'B'};
    var b_cells = [_]client.rich.Cell{cell(&b, 1, 0)};
    b_cells[0].background = .{ .kind = .rgb, .value = 0x040506 };
    var b_rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &b_cells }};
    const b_source = sourceSnapshot(&b_rows, 1);
    const b_view = try client.view.project(std.testing.allocator, &b_source);
    defer client.view.deinit(b_view);

    const font = try contentFont();
    defer font.deinit();
    const content = try render.terminal.initContent(std.testing.allocator, font, contentConfig(2));
    defer render.terminal.deinitContent(content);

    const first = try render.terminal.takeContentUpdate(content, a_view, null);
    try std.testing.expectEqual(@as(usize, 1), first.uploads.len);
    const first_generation = render.terminal.contentUsage(content).resource_generation;
    try std.testing.expectEqual(@as(u64, 1), first_generation);

    try std.testing.expectError(
        error.CommandLimit,
        render.terminal.takeContentUpdate(content, b_view, null),
    );
    const failed = render.terminal.contentUsage(content);
    try std.testing.expectEqual(@as(u64, 1), failed.producer_revision);
    try std.testing.expectEqual(first_generation, failed.resource_generation);
    try std.testing.expectEqual(@as(usize, 2), failed.atlas_entries);

    const recovered = try render.terminal.takeContentUpdate(content, a_view, null);
    try std.testing.expectEqual(@as(usize, 1), recovered.uploads.len);
    try std.testing.expectEqual(first_generation + 1, render.terminal.contentUsage(content).resource_generation);
    try std.testing.expectEqual(@as(u64, 2), render.terminal.contentUsage(content).producer_revision);
}
