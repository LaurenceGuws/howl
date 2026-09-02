//! Proves bounded terminal Canvas presentation without terminal truth duplication.

const std = @import("std");
const render = @import("howl_render");
const client = @import("howl_client");
const fonts = @import("test_fonts");

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
        .subscale_n = 1,
        .subscale_d = 1,
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

fn constructTerminalContent(allocator: std.mem.Allocator, font: *render.text.FontSet) !void {
    const content = try render.terminal.initContent(allocator, font, contentConfig(64));
    render.terminal.deinitContent(content);
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

test "terminal Canvas content retains howl-text fallback presentation" {
    var symbol = [_]u32{0xe0b0};
    var cells = [_]client.rich.Cell{cell(&symbol, 1, 0)};
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
        },
        render.terminal.contentUsage(content),
    );
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
