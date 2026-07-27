//! Proves the capable Render root can feed terminal and chrome producers into one Composer.

const std = @import("std");
const render = @import("howl_render");
const fonts = @import("test_fonts");

const terminal = render.terminal;
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
        .resources_per_update = 16,
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
        .native = .{ .primary = fonts.primary_font, .pixel_height = 16 },
    };
}

fn commandHasResource(command: canvas.Command, source: canvas.SourceId, local: canvas.LocalResourceId, generation: canvas.ResourceGeneration) bool {
    return switch (command) {
        .solid => false,
        .alpha_mask => |value| value.resource.resource.key.source == source and
            value.resource.resource.key.resource == local and
            value.resource.resource.generation == generation,
        .rgba => |value| value.resource.resource.key.source == source and
            value.resource.resource.key.resource == local and
            value.resource.resource.generation == generation,
    };
}

fn frameHasUpload(frame: canvas.Composer.Frame, resource: canvas.FrameResourceRef) bool {
    for (frame.uploads) |upload| if (std.meta.eql(upload.resource, resource)) return true;
    for (frame.commands) |command| if (commandHasResource(command, resource.key.source, resource.key.resource, resource.generation)) return true;
    return false;
}

fn frameHasCommandResource(frame: canvas.Composer.Frame, source: canvas.SourceId, local: canvas.LocalResourceRef) bool {
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

fn updateCommandHasResource(update: canvas.ProducerUpdate, local: canvas.LocalResourceRef) bool {
    for (update.commands) |command| switch (command) {
        .solid => {},
        .alpha_mask => |value| if (std.meta.eql(value.resource.resource, local)) return true,
        .rgba => |value| if (std.meta.eql(value.resource.resource, local)) return true,
    };
    return false;
}

fn updateHasResource(update: canvas.ProducerUpdate, local: canvas.LocalResourceRef) bool {
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
    const terminal_update = try terminal_content.takeUpdate(.{
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
        .{ .primary = fonts.primary_font, .pixel_height = 16 },
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
        if (upload.resource.key.source == terminal_source)
            terminal_qualified = true;
        if (upload.resource.key.source == chrome_source)
            chrome_qualified = true;
    }
    try std.testing.expect(terminal_qualified and chrome_qualified);
    var saw_chrome_command = false;
    var saw_terminal_after_chrome = false;
    for (frame.commands) |command| switch (command) {
        .solid => {},
        .alpha_mask => |value| {
            if (value.resource.resource.key.source == chrome_source)
                saw_chrome_command = true;
            if (saw_chrome_command and
                value.resource.resource.key.source == terminal_source)
                saw_terminal_after_chrome = true;
        },
        .rgba => |value| {
            if (value.resource.resource.key.source == chrome_source)
                saw_chrome_command = true;
            if (saw_chrome_command and
                value.resource.resource.key.source == terminal_source)
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
        const qualified = canvas.FrameResourceRef{
            .key = .{ .source = chrome_source, .resource = upload.resource.resource },
            .generation = upload.resource.generation,
        };
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
        .alpha_mask => |value| if (value.resource.resource.key.source == chrome_source)
            try std.testing.expect(updateHasResource(hidden_update, .{ .resource = value.resource.resource.key.resource, .generation = value.resource.resource.generation })),
        .rgba => |value| if (value.resource.resource.key.source == chrome_source)
            try std.testing.expect(updateHasResource(hidden_update, .{ .resource = value.resource.resource.key.resource, .generation = value.resource.resource.generation })),
    };
    for (chrome_update.uploads) |upload| {
        if (!updateCommandHasResource(hidden_update, upload.resource))
            try std.testing.expect(!frameHasUpload(revealed_newest, .{ .key = .{ .source = chrome_source, .resource = upload.resource.resource }, .generation = upload.resource.generation }));
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
