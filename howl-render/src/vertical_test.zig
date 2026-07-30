//! Proves the capable Render root can feed terminal and chrome producers into one Composer.

const std = @import("std");
const render = @import("howl_render");
const fonts = @import("test_fonts");
const selected = @import("selected_capabilities");

const terminal = render.terminal;
const empty_scalars = terminal.ScalarBaseline.empty(1);
const terminal_images = render.terminal_images;
const chrome = render.chrome;
const canvas = render.canvas;

fn terminalLimits() terminal.Content.Limits {
    return .{
        .cells = 4,
        .rows = 2,
        .images = 2,
        .placements = 2,
        .image_bytes = 128,
        .glyphs = 16,
        .masks = 8,
        .commands = 32,
        .resources_per_update = 26,
        .upload_bytes = 4096,
        .raster_bytes = 4096,
        .decoration_bytes = 512,
    };
}

fn chromeLimits() chrome.Content.Limits {
    return .{
        .primitives = 8,
        .text_bytes = 32,
        .label_scalars = 16,
        .shaped_glyphs = 16,
        .glyphs = 16,
        .commands = 32,
        .resources_per_update = 16,
        .upload_bytes = 4096,
        .raster_bytes = 4096,
    };
}

fn fontConfig() render.terminal_text.FontConfig {
    return .{
        .key = .{ .slot = 0, .style = .normal },
        .native = .{ .primary = fonts.primary_font, .size = .{ .pixels = 16 } },
    };
}

fn fontConfigs(pixel_height: u16) [4]render.terminal_text.FontConfig {
    return .{
        .{ .key = .{ .slot = 0, .style = .normal }, .native = .{ .primary = fonts.primary_font, .size = .{ .pixels = pixel_height } } },
        .{ .key = .{ .slot = 0, .style = .bold }, .native = .{ .primary = fonts.primary_font, .size = .{ .pixels = pixel_height } } },
        .{ .key = .{ .slot = 0, .style = .italic }, .native = .{ .primary = fonts.primary_font, .size = .{ .pixels = pixel_height } } },
        .{ .key = .{ .slot = 0, .style = .bold_italic }, .native = .{ .primary = fonts.primary_font, .size = .{ .pixels = pixel_height } } },
    };
}

fn pointFontConfigs(points: f64) [4]render.terminal_text.FontConfig {
    const size = render.terminal_text.Size{ .points = .{
        .points = points,
        .dpi_x = .{ .numerator = 96, .denominator = 1 },
        .dpi_y = .{ .numerator = 96, .denominator = 1 },
    } };
    return .{
        .{ .key = .{ .slot = 0, .style = .normal }, .native = .{ .primary = fonts.primary_font, .size = size } },
        .{ .key = .{ .slot = 0, .style = .bold }, .native = .{ .primary = fonts.primary_font, .size = size } },
        .{ .key = .{ .slot = 0, .style = .italic }, .native = .{ .primary = fonts.primary_font, .size = size } },
        .{ .key = .{ .slot = 0, .style = .bold_italic }, .native = .{ .primary = fonts.primary_font, .size = size } },
    };
}

fn commandHasResource(command: canvas.Command, source: canvas.SourceId, local: canvas.ResourceId, generation: canvas.ResourceGeneration) bool {
    return switch (command) {
        .solid => false,
        .alpha_mask => |value| value.resource.resource.source == source and
            value.resource.resource.resource == local and
            value.resource.resource.generation == generation,
        .rgba => |value| value.resource.resource.source == source and
            value.resource.resource.resource == local and
            value.resource.resource.generation == generation,
    };
}

fn frameHasUpload(frame: canvas.Composer.Frame, resource: canvas.FrameResourceRef) bool {
    for (frame.uploads) |upload| if (std.meta.eql(upload.resource, resource)) return true;
    for (frame.commands) |command| if (commandHasResource(command, resource.source, resource.resource, resource.generation)) return true;
    return false;
}

fn frameHasCommandResource(frame: canvas.Composer.Frame, source: canvas.SourceId, local: canvas.ResourceRef) bool {
    for (frame.commands) |command| if (commandHasResource(command, source, local.resource, local.generation)) return true;
    return false;
}

fn uploadCount(frame: canvas.Composer.Frame, resource: canvas.FrameResourceRef) usize {
    var count: usize = 0;
    for (frame.uploads) |upload| {
        if (std.meta.eql(upload.resource, resource)) count += 1;
    }
    return count;
}

fn updateCommandHasResource(update: canvas.ProducerUpdate, local: canvas.ResourceRef) bool {
    for (update.commands) |command| switch (command) {
        .solid => {},
        .alpha_mask => |value| if (std.meta.eql(value.resource.resource, local)) return true,
        .rgba => |value| if (std.meta.eql(value.resource.resource, local)) return true,
    };
    return false;
}

fn updateHasResource(update: canvas.ProducerUpdate, local: canvas.ResourceRef) bool {
    for (update.uploads) |upload| if (std.meta.eql(upload.resource, local)) return true;
    return updateCommandHasResource(update, local);
}

test "capable root composes terminal and chrome producer updates" {
    var map = try render.terminal_text.FontMap.init(
        std.testing.allocator,
        &.{fontConfig()},
    );
    defer map.deinit();
    var terminal_content = try terminal.Content.init(
        std.testing.allocator,
        terminalLimits(),
        &map,
    );
    defer terminal_content.deinit();
    var terminal_work = try terminal.Content.Work.init(std.testing.allocator, terminal_content.limits);
    defer terminal_work.deinit();
    const cells = [_]terminal.Cell{.{
        .codepoint = 'A',
        .combining_len = 0,
        .combining = @splat(0),
        .foreground = .{ .r = 240, .g = 240, .b = 240 },
        .background = .{ .r = 12, .g = 14, .b = 18 },
        .underline_color = .{ .r = 240, .g = 240, .b = 240 },
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
    }};
    try terminal_content.recover(.{
        .rows = 1,
        .cols = 1,
        .cursor = .{
            .row = 0,
            .col = 0,
            .visible = false,
            .shape = .none,
            .blink = false,
            .color = .{ .r = 0, .g = 0, .b = 0 },
            .text_color = .{ .r = 0, .g = 0, .b = 0 },
        },
        .cells = &cells,
        .geometry = &.{.single_width},
    }, .{
        .generation = 1,
        .content_generation = 1,
        .pixels = &.{},
        .uploads = &.{},
        .removals = &.{},
        .placements = &.{},
    });
    const terminal_update = try terminal_content.takeLocalUpdate(&terminal_work, empty_scalars, .{
        .x = 0,
        .y = 0,
        .clip = .{ .x = 0, .y = 0, .width = 32, .height = 24 },
        .metrics = .{ .width_px = 8, .height_px = 16, .baseline_px = 12 },
        .underline_y = 14,
        .underline_height = 1,
        .strike_y = 8,
        .strike_height = 1,
    });
    try std.testing.expect(terminal_update.commands.len != 0);
    try std.testing.expect(terminal_update.uploads.len != 0);

    var chrome_content = try chrome.Content.init(
        std.testing.allocator,
        chromeLimits(),
        .{ .primary = fonts.primary_font, .size = .{ .pixels = 16 } },
    );
    defer chrome_content.deinit();
    const label = "chrome";
    const primitive = [_]chrome.Primitive{.{ .label = .{
        .rect = .{ .x = 0, .y = 0, .width = 48, .height = 16 },
        .text = label,
        .color = .{ .r = 240, .g = 240, .b = 240, .a = 255 },
    } }};
    try chrome_content.apply(.{
        .surface = .{ .width = 64, .height = 24 },
        .primitives = &primitive,
        .text = label,
    });
    const chrome_update = try chrome_content.takeUpdate();
    try std.testing.expect(chrome_update.commands.len != 0);
    try std.testing.expect(chrome_update.uploads.len != 0);
    try std.testing.expectEqual(
        chrome_update.uploads[0].resource.resource,
        terminal_update.uploads[0].resource.resource,
    );

    var composer = try canvas.Composer.init(std.testing.allocator, .{
        .sources = 2,
        .retained_resources = 64,
        .retained_commands = 128,
        .retained_pixel_bytes = 32 * 1024,
        .composition_sources = 2,
        .candidate_resources = 64,
        .candidate_commands = 128,
        .candidate_pixel_bytes = 32 * 1024,
    });
    defer composer.deinit();
    const terminal_source = try composer.registerSource();
    const chrome_source = try composer.registerSource();
    try composer.apply(terminal_source, terminal_update);
    try composer.apply(chrome_source, chrome_update);
    try composer.setComposition(.{
        .surface = .{ .width = 64, .height = 24 },
        .sources = &.{
            .{ .source = chrome_source, .origin = .{ .x = 0, .y = 0 }, .clip = .{ .x = 0, .y = 0, .width = 64, .height = 24 } },
            .{ .source = terminal_source, .origin = .{ .x = 8, .y = 16 }, .clip = .{ .x = 0, .y = 0, .width = 64, .height = 24 } },
        },
    });
    var uploads: [64]canvas.ResourceUploadFact = undefined;
    var removals: [64]canvas.FrameResourceRef = undefined;
    var commands: [128]canvas.Command = undefined;
    var pixels: [32 * 1024]u8 = undefined;
    const frame = try composer.frame(&.{}, .{
        .uploads = &uploads,
        .removals = &removals,
        .commands = &commands,
        .pixels = &pixels,
    });
    try std.testing.expect(frame.commands.len != 0);
    var terminal_qualified = false;
    var chrome_qualified = false;
    for (frame.uploads) |upload| {
        if (upload.resource.source == terminal_source)
            terminal_qualified = true;
        if (upload.resource.source == chrome_source)
            chrome_qualified = true;
    }
    try std.testing.expect(terminal_qualified and chrome_qualified);
    var saw_chrome_command = false;
    var saw_terminal_after_chrome = false;
    for (frame.commands) |command| switch (command) {
        .solid => {},
        .alpha_mask => |value| {
            if (value.resource.resource.source == chrome_source)
                saw_chrome_command = true;
            if (saw_chrome_command and
                value.resource.resource.source == terminal_source)
                saw_terminal_after_chrome = true;
        },
        .rgba => |value| {
            if (value.resource.resource.source == chrome_source)
                saw_chrome_command = true;
            if (saw_chrome_command and
                value.resource.resource.source == terminal_source)
                saw_terminal_after_chrome = true;
        },
    };
    try std.testing.expect(saw_chrome_command and saw_terminal_after_chrome);
    const hidden = [_]canvas.Composer.Placement{.{
        .source = terminal_source,
        .origin = .{ .x = 8, .y = 16 },
        .clip = .{ .x = 0, .y = 0, .width = 64, .height = 24 },
    }};
    try composer.setComposition(.{
        .surface = .{ .width = 64, .height = 24 },
        .sources = &hidden,
    });
    const revealed = try composer.frame(&.{}, .{
        .uploads = &uploads,
        .removals = &removals,
        .commands = &commands,
        .pixels = &pixels,
    });
    try std.testing.expect(revealed.commands.len >= terminal_update.commands.len);
    var hidden_before_uploads: [64]canvas.ResourceUploadFact = undefined;
    var hidden_before_commands: [128]canvas.Command = undefined;
    var hidden_before_pixels: [32 * 1024]u8 = undefined;
    const hidden_before_upload_count = revealed.uploads.len;
    const hidden_before_command_count = revealed.commands.len;
    const hidden_before_pixel_count = revealed.pixels.len;
    @memcpy(hidden_before_uploads[0..hidden_before_upload_count], revealed.uploads);
    @memcpy(hidden_before_commands[0..hidden_before_command_count], revealed.commands);
    @memcpy(hidden_before_pixels[0..hidden_before_pixel_count], revealed.pixels);
    var hidden_uploads: [64]canvas.ResourceUploadFact = undefined;
    var hidden_removals: [64]canvas.FrameResourceRef = undefined;
    var hidden_commands: [128]canvas.Command = undefined;
    var hidden_pixels: [32 * 1024]u8 = undefined;

    // A newer hidden producer update is retained without changing the visible
    // frame.  Revealing that source then advances the derived frame exactly
    // once and exposes the newest producer commands.
    const hidden_label = "revealed";
    const hidden_primitive = [_]chrome.Primitive{.{ .label = .{
        .rect = .{ .x = 0, .y = 0, .width = 48, .height = 16 },
        .text = hidden_label,
        .color = .{ .r = 240, .g = 240, .b = 240, .a = 255 },
    } }};
    try chrome_content.apply(.{
        .surface = .{ .width = 64, .height = 24 },
        .primitives = &hidden_primitive,
        .text = hidden_label,
    });
    const hidden_update = try chrome_content.takeUpdate();
    try composer.apply(chrome_source, hidden_update);
    const hidden_frame = try composer.frame(&.{}, .{
        .uploads = &hidden_uploads,
        .removals = &hidden_removals,
        .commands = &hidden_commands,
        .pixels = &hidden_pixels,
    });
    try std.testing.expectEqual(revealed.revision, hidden_frame.revision);
    try std.testing.expectEqualSlices(canvas.Command, hidden_before_commands[0..hidden_before_command_count], hidden_frame.commands);
    try std.testing.expectEqualSlices(canvas.ResourceUploadFact, hidden_before_uploads[0..hidden_before_upload_count], hidden_frame.uploads);
    try std.testing.expectEqualSlices(u8, hidden_before_pixels[0..hidden_before_pixel_count], hidden_frame.pixels);
    try std.testing.expectEqual(@as(usize, 0), hidden_frame.removals.len);

    try composer.setComposition(.{
        .surface = .{ .width = 64, .height = 24 },
        .sources = &.{
            .{ .source = chrome_source, .origin = .{ .x = 0, .y = 0 }, .clip = .{ .x = 0, .y = 0, .width = 64, .height = 24 } },
            .{ .source = terminal_source, .origin = .{ .x = 8, .y = 16 }, .clip = .{ .x = 0, .y = 0, .width = 64, .height = 24 } },
        },
    });
    const revealed_newest = try composer.frame(&.{}, .{
        .uploads = &uploads,
        .removals = &removals,
        .commands = &commands,
        .pixels = &pixels,
    });
    try std.testing.expectEqual(
        @as(u64, @backingInt(hidden_frame.revision)) + 1,
        @backingInt(revealed_newest.revision),
    );
    for (hidden_update.uploads) |upload| {
        if (!updateCommandHasResource(hidden_update, upload.resource)) continue;
        const qualified = try canvas.FrameResourceRef.local(
            chrome_source,
            upload.resource,
        );
        if (!frameHasCommandResource(revealed_newest, chrome_source, upload.resource)) continue;
        try std.testing.expect(frameHasUpload(revealed_newest, qualified));
    }
    var matched_newest_resources: usize = 0;
    for (hidden_update.commands) |command| switch (command) {
        .solid => {},
        .alpha_mask => |value| {
            if (frameHasCommandResource(revealed_newest, chrome_source, value.resource.resource)) matched_newest_resources += 1;
        },
        .rgba => |value| {
            if (frameHasCommandResource(revealed_newest, chrome_source, value.resource.resource)) matched_newest_resources += 1;
        },
    };
    try std.testing.expect(matched_newest_resources > 0);
    for (revealed_newest.commands) |command| switch (command) {
        .solid => {},
        .alpha_mask => |value| if (value.resource.resource.source == chrome_source)
            try std.testing.expect(updateHasResource(hidden_update, .{ .resource = value.resource.resource.resource, .generation = value.resource.resource.generation })),
        .rgba => |value| if (value.resource.resource.source == chrome_source)
            try std.testing.expect(updateHasResource(hidden_update, .{ .resource = value.resource.resource.resource, .generation = value.resource.resource.generation })),
    };
    for (chrome_update.uploads) |upload| {
        if (!updateCommandHasResource(hidden_update, upload.resource))
            try std.testing.expect(!frameHasUpload(
                revealed_newest,
                try canvas.FrameResourceRef.local(chrome_source, upload.resource),
            ));
    }

    // Supplying only one currently resident resource exercises partial
    // recovery: visible missing resources are uploaded, while the resident
    // one is not redundantly copied.  An empty residency then recovers all.
    const full_upload_count = revealed_newest.uploads.len;
    try std.testing.expect(full_upload_count > 1);
    const full_revision = revealed_newest.revision;
    const full_commands = try std.testing.allocator.alloc(canvas.Command, revealed_newest.commands.len);
    defer std.testing.allocator.free(full_commands);
    @memcpy(full_commands, revealed_newest.commands);
    const full_uploads = try std.testing.allocator.alloc(canvas.ResourceUploadFact, revealed_newest.uploads.len);
    defer std.testing.allocator.free(full_uploads);
    @memcpy(full_uploads, revealed_newest.uploads);
    const full_pixels = try std.testing.allocator.alloc(u8, revealed_newest.pixels.len);
    defer std.testing.allocator.free(full_pixels);
    @memcpy(full_pixels, revealed_newest.pixels);
    const full_residency_resource = revealed_newest.uploads[0].resource;
    var partial_uploads: [64]canvas.ResourceUploadFact = undefined;
    var partial_removals: [64]canvas.FrameResourceRef = undefined;
    var partial_commands: [128]canvas.Command = undefined;
    var partial_pixels: [32 * 1024]u8 = undefined;
    var recovered_uploads: [64]canvas.ResourceUploadFact = undefined;
    var recovered_removals: [64]canvas.FrameResourceRef = undefined;
    var recovered_commands: [128]canvas.Command = undefined;
    var recovered_pixels: [32 * 1024]u8 = undefined;
    var partial_residency: [1]canvas.Residency = .{.{
        .resource = revealed_newest.uploads[0].resource,
        .format = revealed_newest.uploads[0].format,
        .size = revealed_newest.uploads[0].size,
    }};
    const partial = try composer.frame(&partial_residency, .{
        .uploads = &partial_uploads,
        .removals = &partial_removals,
        .commands = &partial_commands,
        .pixels = &partial_pixels,
    });
    try std.testing.expectEqual(full_upload_count - 1, partial.uploads.len);
    try std.testing.expectEqual(@as(usize, 0), partial.removals.len);
    try std.testing.expectEqual(full_revision, partial.revision);
    try std.testing.expectEqualSlices(canvas.Command, full_commands, partial.commands);
    for (full_uploads) |expected| {
        const count = uploadCount(partial, expected.resource);
        if (std.meta.eql(expected.resource, full_residency_resource))
            try std.testing.expectEqual(@as(usize, 0), count)
        else
            try std.testing.expectEqual(@as(usize, 1), count);
    }
    const recovered_full = try composer.frame(&.{}, .{
        .uploads = &recovered_uploads,
        .removals = &recovered_removals,
        .commands = &recovered_commands,
        .pixels = &recovered_pixels,
    });
    try std.testing.expectEqual(full_revision, recovered_full.revision);
    try std.testing.expectEqualSlices(canvas.ResourceUploadFact, full_uploads, recovered_full.uploads);
    try std.testing.expectEqualSlices(canvas.Command, full_commands, recovered_full.commands);
    try std.testing.expectEqualSlices(u8, full_pixels, recovered_full.pixels);
    try std.testing.expectEqual(@as(usize, 0), recovered_full.removals.len);
}

test "terminal Content emits shared glyph and decoration resources through its producer" {
    var owner = try render.terminal_font_owner.Owner.init(std.testing.allocator);
    defer owner.deinit();
    const configs = pointFontConfigs(12.0);
    const group = try owner.acquireGroup(.{
        .configuration_generation = 1,
        .point_size = 12.0,
        .logical_dpi_x = .{ .numerator = 96, .denominator = 1 },
        .logical_dpi_y = .{ .numerator = 96, .denominator = 1 },
    }, &configs);
    const map = try owner.mapFor(group);
    var content = try terminal.Content.init(std.testing.allocator, terminalLimits(), map);
    var producer = try owner.producer(group);
    defer {
        content.releaseFontResources(.{ .shared = &producer });
        content.deinit();
        producer.deinit();
        owner.releaseGroup(group) catch
            @panic("shared terminal test lost its native group");
    }
    var work = try terminal.Content.Work.init(std.testing.allocator, content.limits);
    defer work.deinit();
    const base = terminal.Cell{
        .codepoint = 'A',
        .combining_len = 0,
        .combining = @splat(0),
        .foreground = .{ .r = 240, .g = 240, .b = 240 },
        .background = .{ .r = 12, .g = 14, .b = 18 },
        .underline_color = .{ .r = 240, .g = 240, .b = 240 },
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
    var cells = [_]terminal.Cell{ base, base, base };
    cells[1].codepoint = 0x2500;
    cells[2].underline = true;
    cells[2].underline_style = .curly;
    try content.recover(.{
        .rows = 1,
        .cols = cells.len,
        .cursor = .{
            .row = 0,
            .col = 0,
            .visible = false,
            .shape = .none,
            .blink = false,
            .color = .{ .r = 0, .g = 0, .b = 0 },
            .text_color = .{ .r = 0, .g = 0, .b = 0 },
        },
        .cells = &cells,
        .geometry = &.{.single_width},
    }, .{
        .generation = 1,
        .content_generation = 1,
        .pixels = &.{},
        .uploads = &.{},
        .removals = &.{},
        .placements = &.{},
    });
    const metrics = map.cellMetrics(.{
        .slot = 0,
        .style = .normal,
    }) orelse return error.TestUnexpectedResult;
    const update = try content.takeUpdate(&work, terminal.ScalarBaseline.empty(cells.len), .{
        .x = 0,
        .y = 0,
        .clip = .{
            .x = 0,
            .y = 0,
            .width = metrics.width_px * @as(u16, @intCast(cells.len)),
            .height = metrics.height_px,
        },
        .metrics = metrics,
        .underline_y = metrics.height_px - 2,
        .underline_height = 1,
        .strike_y = metrics.height_px / 2,
        .strike_height = 1,
    }, .{}, .{ .shared = &producer });
    try std.testing.expect(update.uploads.len >=
        @as(usize, if (selected.generated_glyphs) 3 else 2));
    for (update.uploads) |upload|
        try std.testing.expect(upload.resource.resource.isShared());
    var shared_commands: usize = 0;
    for (update.commands) |command| switch (command) {
        .solid => {},
        .alpha_mask => |value| {
            try std.testing.expect(value.resource.resource.resource.isShared());
            shared_commands += 1;
        },
        .rgba => |value| {
            try std.testing.expect(value.resource.resource.resource.isShared());
            shared_commands += 1;
        },
    };
    try std.testing.expect(shared_commands >= 3);
}

test "late Content failure rolls back shared acquisitions and reraster succeeds" {
    var owner = try render.terminal_font_owner.Owner.init(std.testing.allocator);
    defer owner.deinit();
    const configs = pointFontConfigs(12.0);
    const group = try owner.acquireGroup(.{
        .configuration_generation = 1,
        .point_size = 12.0,
        .logical_dpi_x = .{ .numerator = 96, .denominator = 1 },
        .logical_dpi_y = .{ .numerator = 96, .denominator = 1 },
    }, &configs);
    const map = try owner.mapFor(group);
    var limits = terminalLimits();
    limits.commands = 1;
    var content = try terminal.Content.init(std.testing.allocator, limits, map);
    defer content.deinit();
    var work = try terminal.Content.Work.init(std.testing.allocator, limits);
    defer work.deinit();
    const cells = [_]terminal.Cell{.{
        .codepoint = 'A',
        .combining_len = 0,
        .combining = @splat(0),
        .foreground = .{ .r = 240, .g = 240, .b = 240 },
        .background = .{ .r = 12, .g = 14, .b = 18 },
        .underline_color = .{ .r = 240, .g = 240, .b = 240 },
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
    }};
    try content.recover(
        .{
            .rows = 1,
            .cols = 1,
            .cursor = .{
                .row = 0,
                .col = 0,
                .visible = false,
                .shape = .none,
                .blink = false,
                .color = .{ .r = 0, .g = 0, .b = 0 },
                .text_color = .{ .r = 0, .g = 0, .b = 0 },
            },
            .cells = &cells,
            .geometry = &.{.single_width},
        },
        .{
            .generation = 1,
            .content_generation = 1,
            .pixels = &.{},
            .uploads = &.{},
            .removals = &.{},
            .placements = &.{},
        },
    );
    const metrics = map.cellMetrics(.{ .slot = 0, .style = .normal }) orelse
        return error.TestUnexpectedResult;
    const geometry = terminal.Content.Geometry{
        .x = 0,
        .y = 0,
        .clip = .{ .x = 0, .y = 0, .width = metrics.width_px, .height = metrics.height_px },
        .metrics = metrics,
        .underline_y = metrics.height_px - 2,
        .underline_height = 1,
        .strike_y = metrics.height_px / 2,
        .strike_height = 1,
    };
    var failed = try owner.producer(group);
    try std.testing.expectError(
        error.CommandLimit,
        content.takeUpdate(&work, empty_scalars, geometry, .{}, .{ .shared = &failed }),
    );
    failed.deinit();
    content.deinit();
    work.deinit();
    limits.commands = 4;
    content = try terminal.Content.init(std.testing.allocator, limits, map);
    work = try terminal.Content.Work.init(std.testing.allocator, limits);
    try content.recover(.{
        .rows = 1,
        .cols = 1,
        .cursor = .{
            .row = 0,
            .col = 0,
            .visible = false,
            .shape = .none,
            .blink = false,
            .color = .{ .r = 0, .g = 0, .b = 0 },
            .text_color = .{ .r = 0, .g = 0, .b = 0 },
        },
        .cells = &cells,
        .geometry = &.{.single_width},
    }, .{
        .generation = 1,
        .content_generation = 1,
        .pixels = &.{},
        .uploads = &.{},
        .removals = &.{},
        .placements = &.{},
    });
    var retry = try owner.producer(group);
    const update = try content.takeUpdate(
        &work,
        empty_scalars,
        geometry,
        .{},
        .{ .shared = &retry },
    );
    try std.testing.expectEqual(@as(usize, 1), update.uploads.len);
    try std.testing.expect(update.uploads[0].resource.resource.isShared());
    try std.testing.expect(try update.uploads[0].resource.resource.identity() > 1);
    content.releaseFontResources(.{ .shared = &retry });
    retry.deinit();
    try owner.releaseGroup(group);
}

test "shared FontMap owners invalidate independently without identity reuse" {
    const old_configs = fontConfigs(16);
    const new_configs = fontConfigs(24);
    var map = try render.terminal_text.FontMap.init(std.testing.allocator, &old_configs);
    defer map.deinit();
    var replacement = try render.terminal_text.FontMap.init(std.testing.allocator, &new_configs);
    defer replacement.deinit();
    var first = try terminal.Content.init(std.testing.allocator, terminalLimits(), &map);
    defer first.deinit();
    var second = try terminal.Content.init(std.testing.allocator, terminalLimits(), &map);
    defer second.deinit();
    var first_work = try terminal.Content.Work.init(std.testing.allocator, first.limits);
    defer first_work.deinit();
    var second_work = try terminal.Content.Work.init(std.testing.allocator, second.limits);
    defer second_work.deinit();
    const cells = [_]terminal.Cell{.{
        .codepoint = 'A',
        .combining_len = 0,
        .combining = @splat(0),
        .foreground = .{ .r = 240, .g = 240, .b = 240 },
        .background = .{ .r = 12, .g = 14, .b = 18 },
        .underline_color = .{ .r = 240, .g = 240, .b = 240 },
        .font = 0,
        .baseline = .normal,
        .bold = false,
        .dim = false,
        .italic = false,
        .blink = false,
        .blink_fast = false,
        .invisible = false,
        .underline = true,
        .strikethrough = false,
        .underline_style = .curly,
        .selected = false,
        .link_id = 0,
    }};
    const baseline = terminal.ProjectionBaseline{
        .rows = 1,
        .cols = 1,
        .cells = &cells,
        .geometry = &.{.single_width},
        .cursor = .{ .row = 0, .col = 0, .visible = false, .shape = .none, .blink = false, .color = .{ .r = 0, .g = 0, .b = 0 }, .text_color = .{ .r = 0, .g = 0, .b = 0 } },
    };
    const image_pixels = [_]u8{ 1, 2, 3, 255 };
    const image_upload = [_]terminal_images.ImageUpload{.{
        .identity = .{ .id = 7, .generation = 1 },
        .width = 1,
        .height = 1,
        .pixel_offset = 0,
        .pixel_count = 4,
    }};
    const image_placement = [_]terminal_images.ImagePlacement{.{
        .image_id = 7,
        .generation = 1,
        .row = 0,
        .col = 0,
        .pixel_width = 1,
        .pixel_height = 1,
        .z = -1,
    }};
    const image_update = terminal_images.Update{
        .generation = 1,
        .content_generation = 1,
        .pixels = &image_pixels,
        .uploads = &image_upload,
        .removals = &.{},
        .placements = &image_placement,
    };
    try first.recover(baseline, image_update);
    try second.recover(baseline, image_update);
    const geometry = terminal.Content.Geometry{
        .x = 0,
        .y = 0,
        .clip = .{ .x = 0, .y = 0, .width = 32, .height = 24 },
        .metrics = .{ .width_px = 8, .height_px = 16, .baseline_px = 12 },
        .underline_y = 14,
        .underline_height = 1,
        .strike_y = 8,
        .strike_height = 1,
    };
    first.invalidateFonts();
    second.invalidateFonts();
    const first_update = try first.takeLocalUpdate(&first_work, empty_scalars, geometry);
    const second_update = try second.takeLocalUpdate(&second_work, empty_scalars, geometry);
    try std.testing.expect(first_update.uploads.len > 0 and second_update.uploads.len > 0);
    try std.testing.expectEqual(@as(usize, 0), first_update.removals.len);
    try std.testing.expectEqual(@as(usize, 0), second_update.removals.len);
    var first_old: [16]canvas.ResourceRef = undefined;
    var second_old: [16]canvas.ResourceRef = undefined;
    var first_old_alpha: [16]canvas.ResourceUpload = undefined;
    var second_old_alpha: [16]canvas.ResourceUpload = undefined;
    var first_old_count: usize = 0;
    var second_old_count: usize = 0;
    var first_image: ?canvas.ResourceRef = null;
    var second_image: ?canvas.ResourceRef = null;
    for (first_update.uploads) |upload| {
        if (upload.format == .rgba8) first_image = upload.resource else {
            first_old[first_old_count] = upload.resource;
            first_old_alpha[first_old_count] = upload;
            first_old_count += 1;
        }
    }
    for (second_update.uploads) |upload| {
        if (upload.format == .rgba8) second_image = upload.resource else {
            second_old[second_old_count] = upload.resource;
            second_old_alpha[second_old_count] = upload;
            second_old_count += 1;
        }
    }
    try std.testing.expect(first_image != null and second_image != null);
    const first_revision = first_update.revision;
    map.replaceWith(&replacement);
    const new_metrics = map.cellMetrics(.{ .slot = 0, .style = .normal }).?;
    const new_decoration = map.decorationMetrics(.{ .slot = 0, .style = .normal }).?;
    try std.testing.expect(new_metrics.height_px > 16);
    first.invalidateFonts();
    first.invalidateFonts();
    second.invalidateFonts();
    second.invalidateFonts();
    try std.testing.expectEqual(first_revision, first_update.revision);
    const new_geometry = terminal.Content.Geometry{
        .x = 0,
        .y = 0,
        .clip = .{ .x = 0, .y = 0, .width = 48, .height = 32 },
        .metrics = new_metrics,
        .underline_y = new_decoration.underline_y,
        .underline_height = new_decoration.underline_height,
        .strike_y = new_decoration.strike_y,
        .strike_height = new_decoration.strike_height,
    };
    const first_rebuilt = try first.takeLocalUpdate(&first_work, empty_scalars, new_geometry);
    const second_rebuilt = try second.takeLocalUpdate(&second_work, empty_scalars, new_geometry);
    try std.testing.expectEqual(@as(u64, @backingInt(first_revision)) + 1, @as(u64, @backingInt(first_rebuilt.revision)));
    try std.testing.expectEqual(@as(u64, @backingInt(first_revision)) + 1, @as(u64, @backingInt(second_rebuilt.revision)));
    try std.testing.expect(first_rebuilt.removals.len > 0 and second_rebuilt.removals.len > 0);
    try std.testing.expectEqual(first_old_count, first_rebuilt.removals.len);
    try std.testing.expectEqual(second_old_count, second_rebuilt.removals.len);
    for (first_old[0..first_old_count]) |old| {
        var count: usize = 0;
        for (first_rebuilt.removals) |removal| {
            if (std.meta.eql(old, removal.resource)) count += 1;
        }
        try std.testing.expectEqual(@as(usize, 1), count);
    }
    for (second_old[0..second_old_count]) |old| {
        var count: usize = 0;
        for (second_rebuilt.removals) |removal| {
            if (std.meta.eql(old, removal.resource)) count += 1;
        }
        try std.testing.expectEqual(@as(usize, 1), count);
    }
    for (first_rebuilt.removals) |removal| try std.testing.expect(!std.meta.eql(removal.resource, first_image.?));
    for (second_rebuilt.removals) |removal| try std.testing.expect(!std.meta.eql(removal.resource, second_image.?));
    try std.testing.expect(first_rebuilt.uploads.len > 0 and second_rebuilt.uploads.len > 0);
    var first_old_max: u64 = 0;
    for (first_old[0..first_old_count]) |old| first_old_max = @max(first_old_max, @as(u64, @backingInt(old.resource)));
    var second_old_max: u64 = 0;
    for (second_old[0..second_old_count]) |old| second_old_max = @max(second_old_max, @as(u64, @backingInt(old.resource)));
    var first_mask_old: usize = 0;
    var second_mask_old: usize = 0;
    var first_old_glyph: ?canvas.ResourceUpload = null;
    var second_old_glyph: ?canvas.ResourceUpload = null;
    var first_old_mask: ?canvas.ResourceUpload = null;
    var second_old_mask: ?canvas.ResourceUpload = null;
    for (first_old_alpha[0..first_old_count]) |upload| {
        if (upload.pixels.height <= 4) {
            first_mask_old += 1;
            first_old_mask = upload;
        } else first_old_glyph = upload;
    }
    for (second_old_alpha[0..second_old_count]) |upload| {
        if (upload.pixels.height <= 4) {
            second_mask_old += 1;
            second_old_mask = upload;
        } else second_old_glyph = upload;
    }
    try std.testing.expectEqual(@as(usize, 2), first_old_count);
    try std.testing.expectEqual(@as(usize, 2), second_old_count);
    try std.testing.expectEqual(@as(usize, 1), first_mask_old);
    try std.testing.expectEqual(@as(usize, 1), second_mask_old);
    try std.testing.expect(first_old_glyph != null and first_old_mask != null);
    try std.testing.expect(second_old_glyph != null and second_old_mask != null);
    var first_mask_new: usize = 0;
    var second_mask_new: usize = 0;
    var first_new_glyph: ?canvas.ResourceUpload = null;
    var second_new_glyph: ?canvas.ResourceUpload = null;
    var first_new_mask: ?canvas.ResourceUpload = null;
    var second_new_mask: ?canvas.ResourceUpload = null;
    for (first_rebuilt.uploads) |upload| {
        try std.testing.expect(upload.format == .alpha8);
        try std.testing.expect(@as(u64, @backingInt(upload.resource.resource)) > first_old_max);
        if (upload.pixels.height <= 4) {
            first_mask_new += 1;
            first_new_mask = upload;
        } else first_new_glyph = upload;
    }
    for (second_rebuilt.uploads) |upload| {
        try std.testing.expect(upload.format == .alpha8);
        try std.testing.expect(@as(u64, @backingInt(upload.resource.resource)) > second_old_max);
        if (upload.pixels.height <= 4) {
            second_mask_new += 1;
            second_new_mask = upload;
        } else second_new_glyph = upload;
    }
    try std.testing.expectEqual(@as(usize, 2), first_rebuilt.uploads.len);
    try std.testing.expectEqual(@as(usize, 2), second_rebuilt.uploads.len);
    try std.testing.expectEqual(@as(usize, 1), first_mask_new);
    try std.testing.expectEqual(@as(usize, 1), second_mask_new);
    try std.testing.expect(first_new_glyph != null and first_new_mask != null);
    try std.testing.expect(second_new_glyph != null and second_new_mask != null);
    try std.testing.expect(
        first_old_glyph.?.pixels.width != first_new_glyph.?.pixels.width or
            first_old_glyph.?.pixels.height != first_new_glyph.?.pixels.height,
    );
    try std.testing.expect(
        first_old_mask.?.pixels.width != first_new_mask.?.pixels.width or
            first_old_mask.?.pixels.height != first_new_mask.?.pixels.height,
    );
    try std.testing.expect(
        second_old_glyph.?.pixels.width != second_new_glyph.?.pixels.width or
            second_old_glyph.?.pixels.height != second_new_glyph.?.pixels.height,
    );
    try std.testing.expect(
        second_old_mask.?.pixels.width != second_new_mask.?.pixels.width or
            second_old_mask.?.pixels.height != second_new_mask.?.pixels.height,
    );
    try std.testing.expect(updateCommandHasResource(first_rebuilt, first_image.?));
    try std.testing.expect(updateCommandHasResource(second_rebuilt, second_image.?));
    const second_revision = first_rebuilt.revision;
    first.invalidateFonts();
    const repeated = try first.takeLocalUpdate(&first_work, empty_scalars, new_geometry);
    try std.testing.expect(repeated.removals.len > 0);
    try std.testing.expect(@as(u64, @backingInt(repeated.removals[0].resource.resource)) != @as(u64, @backingInt(first_old[0].resource)));
    try std.testing.expectEqual(@as(u64, @backingInt(second_revision)) + 1, @as(u64, @backingInt(repeated.revision)));
    const second_unchanged = try second.takeLocalUpdate(&second_work, empty_scalars, new_geometry);
    try std.testing.expectEqual(second_rebuilt.revision, second_unchanged.revision);
    try std.testing.expectEqual(@as(usize, 0), second_unchanged.uploads.len);
    try std.testing.expectEqual(@as(usize, 0), second_unchanged.removals.len);
}
