//! Proves editor-like native text and chrome reuse through the curated root.

const std = @import("std");
const render = @import("howl_render");
const fonts = @import("test_fonts");

fn limits() render.chrome.Content.Limits {
    return .{
        .primitives = 32,
        .text_bytes = 128,
        .label_scalars = 64,
        .shaped_glyphs = 64,
        .glyphs = 64,
        .commands = 128,
        .resources_per_update = 64,
        .upload_bytes = 8192,
        .raster_bytes = 4096,
    };
}

fn content() !render.chrome.Content {
    return render.chrome.Content.init(std.testing.allocator, limits(), .{
        .primary = fonts.primary_font,
        .size = .{ .pixels = 16 },
    });
}

test "editor-like frame shapes text and projects selection without terminal facts" {
    var font = try render.text.FontSet.init(std.testing.allocator, .{
        .primary = fonts.primary_font,
        .size = .{ .pixels = 16 },
    });
    defer font.deinit();
    var scratch = try render.text.ShapeBuffer.init(16);
    defer scratch.deinit();
    const codepoints = [_]u32{ 'e', 'd', 'i', 't' };
    const clusters = [_]u32{ 0, 1, 2, 3 };
    var glyphs: [16]render.text.Glyph = undefined;
    const run = try font.shape(&scratch, .{ .codepoints = &codepoints, .clusters = &clusters }, &glyphs);
    try std.testing.expect(run.glyphs.len != 0);

    const frame = render.chrome.Input{
        .surface = .{ .width = 96, .height = 48 },
        .tab_bar_height = 12,
        .tabs = &.{.{ .id = @fromBackingInt(@intCast(1)), .label = "edit", .active = true }},
        .panes = &.{.{ .id = @fromBackingInt(@intCast(1)), .rect = .{ .x = 0, .y = 12, .width = 96, .height = 36 }, .label = "buffer", .focused = true, .scroll = null, .layer = .tiled }},
        .selections = &.{.{ .pane = @fromBackingInt(@intCast(1)), .rect = .{ .x = 8, .y = 20, .width = 24, .height = 12 }, .color = .{ .r = 40, .g = 70, .b = 110, .a = 255 } }},
        .style = .{ .foreground = .{ .r = 240, .g = 240, .b = 240, .a = 255 }, .background = .{ .r = 16, .g = 18, .b = 22, .a = 255 }, .border = .{ .r = 80, .g = 84, .b = 92, .a = 255 } },
        .tab_active_background = .{ .r = 36, .g = 42, .b = 54, .a = 255 },
        .tab_inactive_background = .{ .r = 24, .g = 28, .b = 34, .a = 255 },
        .scrollbar_width = 4,
        .scrollbar_min_thumb = 8,
    };
    var primitives: [8]render.chrome.Primitive = undefined;
    var text: [16]u8 = undefined;
    const output = try render.chrome.project(frame, &primitives, &text);
    try std.testing.expectEqualStrings("editbuffer", output.text);
    try std.testing.expect(output.primitives[3] == .fill);
    try std.testing.expectEqual(@as(render.chrome.PaneId, @fromBackingInt(@intCast(1))), frame.selections[0].pane);
    try std.testing.expect((try render.chrome.hitTest(frame, .{ .x = 50, .y = 30 })).? == .pane);
}

test "retained editor chrome copies Unicode and transfers glyphs once" {
    var retained = try content();
    defer retained.deinit();
    var primitives: [16]render.chrome.Primitive = undefined;
    var copied_text: [64]u8 = undefined;
    const projected = try projectEditorFrame(
        "edit λ",
        "buffer β",
        &primitives,
        &copied_text,
    );
    try retained.apply(projected);
    @memset(&copied_text, 0);
    const first = try retained.takeUpdate();
    try std.testing.expect(first.commands.len > projected.primitives.len);
    try std.testing.expect(first.uploads.len > 1);
    try std.testing.expectEqual(@as(usize, 0), first.removals.len);
    try std.testing.expect(first.commands[0] == .solid);
    for (first.commands) |command| if (command == .alpha_mask) {
        try std.testing.expect(command.alpha_mask.clip.x >= 0);
        try std.testing.expect(command.alpha_mask.clip.y >= 0);
        try std.testing.expect(
            @as(i64, command.alpha_mask.clip.x) +
                command.alpha_mask.clip.width <= projected.surface.width,
        );
        try std.testing.expect(
            @as(i64, command.alpha_mask.clip.y) +
                command.alpha_mask.clip.height <= projected.surface.height,
        );
    };
    const revision = @backingInt(first.revision);
    var commands: [128]render.canvas.Input = undefined;
    @memcpy(commands[0..first.commands.len], first.commands);
    const command_count = first.commands.len;

    const repeated = try retained.takeUpdate();
    try std.testing.expectEqual(revision, @backingInt(repeated.revision));
    try std.testing.expectEqual(@as(usize, 0), repeated.uploads.len);
    try std.testing.expectEqual(@as(usize, 0), repeated.removals.len);
    try std.testing.expectEqualDeep(commands[0..command_count], repeated.commands);
}

test "retained chrome glyph churn retires exactly and zero-area glyphs stay logical-free" {
    var retained = try content();
    defer retained.deinit();
    var primitives: [8]render.chrome.Primitive = undefined;
    var copied_text: [32]u8 = undefined;

    var projected = try projectEditorFrame(
        "A",
        "",
        &primitives,
        &copied_text,
    );
    try retained.apply(projected);
    const first = try retained.takeUpdate();
    try std.testing.expectEqual(@as(usize, 1), first.uploads.len);
    const first_resource = first.uploads[0].resource;

    projected = try projectEditorFrame(
        "B",
        "",
        &primitives,
        &copied_text,
    );
    try retained.apply(projected);
    const replaced = try retained.takeUpdate();
    try std.testing.expectEqual(@as(usize, 1), replaced.uploads.len);
    try std.testing.expectEqual(@as(usize, 1), replaced.removals.len);
    try std.testing.expectEqualDeep(first_resource, replaced.removals[0].resource);

    projected = try projectEditorFrame(
        " ",
        "",
        &primitives,
        &copied_text,
    );
    try retained.apply(projected);
    const blank = try retained.takeUpdate();
    try std.testing.expectEqual(@as(usize, 0), blank.uploads.len);
    try std.testing.expectEqual(@as(usize, 1), blank.removals.len);

    projected = try projectEditorFrame(
        "",
        "",
        &primitives,
        &copied_text,
    );
    try retained.apply(projected);
    const removed_blank = try retained.takeUpdate();
    try std.testing.expectEqual(@as(usize, 0), removed_blank.uploads.len);
    try std.testing.expectEqual(@as(usize, 0), removed_blank.removals.len);
}

test "retained chrome state and cache failures preserve accepted output" {
    var tiny_limits = limits();
    tiny_limits.primitives = 1;
    var tiny = try render.chrome.Content.init(std.testing.allocator, tiny_limits, .{
        .primary = fonts.primary_font,
        .size = .{ .pixels = 16 },
    });
    defer tiny.deinit();
    var primitives: [16]render.chrome.Primitive = undefined;
    var copied_text: [64]u8 = undefined;
    const projected = try projectEditorFrame(
        "tab",
        "pane",
        &primitives,
        &copied_text,
    );
    try std.testing.expectError(error.PrimitiveLimit, tiny.apply(projected));
    try std.testing.expectError(error.InvalidState, tiny.takeUpdate());

    var glyph_limits = limits();
    glyph_limits.glyphs = 1;
    var retained = try render.chrome.Content.init(
        std.testing.allocator,
        glyph_limits,
        .{ .primary = fonts.primary_font, .size = .{ .pixels = 16 } },
    );
    defer retained.deinit();
    const accepted = try projectEditorFrame(
        "A",
        "",
        &primitives,
        &copied_text,
    );
    try retained.apply(accepted);
    const before = try retained.takeUpdate();
    const before_revision = @backingInt(before.revision);
    const malformed = render.chrome.Output{
        .surface = .{ .width = 96, .height = 48 },
        .primitives = &.{.{ .label = .{
            .rect = .{ .x = 0, .y = 0, .width = 10, .height = 10 },
            .text = "not copied",
            .color = .{ .r = 1, .g = 2, .b = 3, .a = 255 },
        } }},
        .text = "different",
    };
    try std.testing.expectError(error.InvalidOutput, retained.apply(malformed));
    const conflicting = try projectEditorFrame(
        "AB",
        "",
        &primitives,
        &copied_text,
    );
    try retained.apply(conflicting);
    try std.testing.expectError(error.GlyphLimit, retained.takeUpdate());
    const restored = try projectEditorFrame(
        "A",
        "",
        &primitives,
        &copied_text,
    );
    try retained.apply(restored);
    const recovered = try retained.takeUpdate();
    try std.testing.expect(recovered.uploads.len == 0);
    try std.testing.expect(@backingInt(recovered.revision) > before_revision);
}

test "retained chrome style geometry and bounded failures are transactional" {
    var retained = try content();
    defer retained.deinit();
    const label_bytes = "A";
    var primitives = [_]render.chrome.Primitive{
        .{ .fill = .{
            .rect = .{ .x = 0, .y = 0, .width = 20, .height = 20 },
            .color = .{ .r = 1, .g = 2, .b = 3, .a = 255 },
        } },
        .{ .label = .{
            .rect = .{ .x = 1, .y = 1, .width = 18, .height = 18 },
            .text = label_bytes,
            .color = .{ .r = 240, .g = 241, .b = 242, .a = 255 },
        } },
    };
    try retained.apply(.{
        .surface = .{ .width = 40, .height = 20 },
        .primitives = &primitives,
        .text = label_bytes,
    });
    const first = try retained.takeUpdate();
    try std.testing.expectEqual(@as(u8, 1), first.commands[0].solid.color.r);
    const first_revision = @backingInt(first.revision);

    primitives[0].fill.color.r = 9;
    primitives[1].label.rect.x = 4;
    try retained.apply(.{
        .surface = .{ .width = 40, .height = 20 },
        .primitives = &primitives,
        .text = label_bytes,
    });
    const changed = try retained.takeUpdate();
    try std.testing.expectEqual(@as(u8, 9), changed.commands[0].solid.color.r);
    try std.testing.expectEqual(@as(usize, 0), changed.uploads.len);
    try std.testing.expect(@backingInt(changed.revision) > first_revision);

    var command_limits = limits();
    command_limits.commands = 1;
    var command_limited = try render.chrome.Content.init(
        std.testing.allocator,
        command_limits,
        .{ .primary = fonts.primary_font, .size = .{ .pixels = 16 } },
    );
    defer command_limited.deinit();
    try command_limited.apply(.{
        .surface = .{ .width = 40, .height = 20 },
        .primitives = &primitives,
        .text = label_bytes,
    });
    try std.testing.expectError(error.CommandLimit, command_limited.takeUpdate());
    try command_limited.apply(.{
        .surface = .{ .width = 40, .height = 20 },
        .primitives = primitives[1..],
        .text = label_bytes,
    });
    const command_recovered = try command_limited.takeUpdate();
    try std.testing.expectEqual(@as(usize, 1), command_recovered.uploads.len);
    try std.testing.expectEqual(
        @as(u64, 1),
        @backingInt(command_recovered.uploads[0].resource.resource),
    );

    var upload_limits = limits();
    upload_limits.upload_bytes = 1;
    var upload_limited = try render.chrome.Content.init(
        std.testing.allocator,
        upload_limits,
        .{ .primary = fonts.primary_font, .size = .{ .pixels = 16 } },
    );
    defer upload_limited.deinit();
    try upload_limited.apply(.{
        .surface = .{ .width = 40, .height = 20 },
        .primitives = primitives[1..],
        .text = label_bytes,
    });
    try std.testing.expectError(error.UploadByteLimit, upload_limited.takeUpdate());

    var text_limits = limits();
    text_limits.text_bytes = 1;
    var text_limited = try render.chrome.Content.init(
        std.testing.allocator,
        text_limits,
        .{ .primary = fonts.primary_font, .size = .{ .pixels = 16 } },
    );
    defer text_limited.deinit();
    const two_bytes = "AB";
    const two_label = [_]render.chrome.Primitive{.{ .label = .{
        .rect = .{ .x = 0, .y = 0, .width = 20, .height = 20 },
        .text = two_bytes,
        .color = primitives[1].label.color,
    } }};
    try std.testing.expectError(error.TextLimit, text_limited.apply(.{
        .surface = .{ .width = 40, .height = 20 },
        .primitives = &two_label,
        .text = two_bytes,
    }));
}

test "retained chrome construction releases every staged allocation" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        constructContent,
        .{},
    );
}

test "retained chrome preserves empty and hidden-tab projections" {
    var retained = try content();
    defer retained.deinit();
    var primitives: [8]render.chrome.Primitive = undefined;
    var copied_text: [32]u8 = undefined;
    const empty = try render.chrome.project(.{
        .surface = .{ .width = 40, .height = 20 },
        .tab_bar_height = 0,
        .tabs = &.{},
        .panes = &.{},
        .selections = &.{},
        .style = .{
            .foreground = .{ .r = 1, .g = 1, .b = 1, .a = 255 },
            .background = .{ .r = 2, .g = 2, .b = 2, .a = 255 },
            .border = .{ .r = 3, .g = 3, .b = 3, .a = 255 },
        },
        .tab_active_background = .{ .r = 4, .g = 4, .b = 4, .a = 255 },
        .tab_inactive_background = .{ .r = 5, .g = 5, .b = 5, .a = 255 },
        .scrollbar_width = 1,
        .scrollbar_min_thumb = 1,
    }, &primitives, &copied_text);
    try retained.apply(empty);
    const empty_update = try retained.takeUpdate();
    try std.testing.expectEqual(@as(usize, 0), empty_update.commands.len);
    try std.testing.expectEqual(@as(usize, 0), empty_update.uploads.len);

    const hidden_tabs = [_]render.chrome.Tab{.{
        .id = @fromBackingInt(@intCast(1)),
        .label = "hidden",
        .active = true,
    }};
    const hidden = try render.chrome.project(.{
        .surface = .{ .width = 40, .height = 20 },
        .tab_bar_height = 0,
        .tabs = &hidden_tabs,
        .panes = &.{},
        .selections = &.{},
        .style = .{
            .foreground = .{ .r = 1, .g = 1, .b = 1, .a = 255 },
            .background = .{ .r = 2, .g = 2, .b = 2, .a = 255 },
            .border = .{ .r = 3, .g = 3, .b = 3, .a = 255 },
        },
        .tab_active_background = .{ .r = 4, .g = 4, .b = 4, .a = 255 },
        .tab_inactive_background = .{ .r = 5, .g = 5, .b = 5, .a = 255 },
        .scrollbar_width = 1,
        .scrollbar_min_thumb = 1,
    }, &primitives, &copied_text);
    try retained.apply(hidden);
    const hidden_update = try retained.takeUpdate();
    try std.testing.expectEqual(@as(usize, 0), hidden_update.commands.len);
    try std.testing.expectEqual(@as(usize, 0), hidden_update.uploads.len);
}

test "retained chrome expands borders and scrollbars in canonical order" {
    var retained = try content();
    defer retained.deinit();
    const border_color = render.canvas.Color{ .r = 1, .g = 2, .b = 3, .a = 255 };
    const track_color = render.canvas.Color{ .r = 4, .g = 5, .b = 6, .a = 255 };
    const thumb_color = render.canvas.Color{ .r = 7, .g = 8, .b = 9, .a = 255 };
    const primitives = [_]render.chrome.Primitive{
        .{ .border = .{
            .rect = .{ .x = 2, .y = 3, .width = 20, .height = 10 },
            .edges = .{},
            .color = border_color,
        } },
        .{ .scrollbar = .{
            .track = .{ .x = 20, .y = 3, .width = 2, .height = 10 },
            .thumb = .{ .x = 20, .y = 6, .width = 2, .height = 3 },
            .color = track_color,
            .thumb_color = thumb_color,
        } },
    };
    try retained.apply(.{
        .surface = .{ .width = 32, .height = 20 },
        .primitives = &primitives,
        .text = &.{},
    });
    const update = try retained.takeUpdate();
    try std.testing.expectEqual(@as(usize, 6), update.commands.len);
    for (update.commands[0..4]) |command| {
        try std.testing.expect(command == .solid);
        try std.testing.expectEqualDeep(border_color, command.solid.color);
    }
    try std.testing.expectEqualDeep(track_color, update.commands[4].solid.color);
    try std.testing.expectEqualDeep(thumb_color, update.commands[5].solid.color);
}

test "maximum surface right and bottom borders emit exact coordinates" {
    var retained = try content();
    defer retained.deinit();
    const extent = std.math.maxInt(u16);
    const color = render.canvas.Color{ .r = 1, .g = 2, .b = 3, .a = 255 };
    const primitives = [_]render.chrome.Primitive{.{ .border = .{
        .rect = .{ .x = 0, .y = 0, .width = extent, .height = extent },
        .edges = .{
            .top = false,
            .right = true,
            .bottom = true,
            .left = false,
        },
        .color = color,
    } }};
    try retained.apply(.{
        .surface = .{ .width = extent, .height = extent },
        .primitives = &primitives,
        .text = &.{},
    });
    const update = try retained.takeUpdate();
    try std.testing.expectEqual(@as(usize, 2), update.commands.len);
    try std.testing.expectEqualDeep(
        render.canvas.Input{ .solid = .{
            .rect = .{
                .x = extent - 1,
                .y = 0,
                .width = 1,
                .height = extent,
            },
            .clip = .{ .x = 0, .y = 0, .width = extent, .height = extent },
            .color = color,
        } },
        update.commands[0],
    );
    try std.testing.expectEqualDeep(
        render.canvas.Input{ .solid = .{
            .rect = .{
                .x = 0,
                .y = extent - 1,
                .width = extent,
                .height = 1,
            },
            .clip = .{ .x = 0, .y = 0, .width = extent, .height = extent },
            .color = color,
        } },
        update.commands[1],
    );
}

fn constructContent(allocator: std.mem.Allocator) !void {
    var retained = try render.chrome.Content.init(allocator, limits(), .{
        .primary = fonts.primary_font,
        .size = .{ .pixels = 16 },
    });
    retained.deinit();
}

fn projectEditorFrame(
    tab_label: []const u8,
    pane_label: []const u8,
    primitives: []render.chrome.Primitive,
    copied_text: []u8,
) !render.chrome.Output {
    const tabs: []const render.chrome.Tab = if (tab_label.len == 0)
        &.{}
    else
        &.{render.chrome.Tab{
            .id = @fromBackingInt(@intCast(1)),
            .label = tab_label,
            .active = true,
        }};
    const panes = [_]render.chrome.Pane{.{
        .id = @fromBackingInt(@intCast(1)),
        .rect = .{
            .x = 0,
            .y = if (tab_label.len == 0) 0 else 12,
            .width = 96,
            .height = if (tab_label.len == 0) 48 else 36,
        },
        .label = pane_label,
        .focused = true,
        .scroll = null,
        .layer = .tiled,
    }};
    return render.chrome.project(.{
        .surface = .{ .width = 96, .height = 48 },
        .tab_bar_height = if (tab_label.len == 0) 0 else 12,
        .tabs = tabs,
        .panes = &panes,
        .selections = &.{},
        .style = .{
            .foreground = .{ .r = 240, .g = 240, .b = 240, .a = 255 },
            .background = .{ .r = 16, .g = 18, .b = 22, .a = 255 },
            .border = .{ .r = 80, .g = 84, .b = 92, .a = 255 },
        },
        .tab_active_background = .{ .r = 36, .g = 42, .b = 54, .a = 255 },
        .tab_inactive_background = .{ .r = 24, .g = 28, .b = 34, .a = 255 },
        .scrollbar_width = 4,
        .scrollbar_min_thumb = 8,
    }, primitives, copied_text);
}
