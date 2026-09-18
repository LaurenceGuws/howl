//! Proves one bounded terminal Canvas through the final backend-facing frame.

const std = @import("std");
const render = @import("howl_render");
const client = @import("howl_client");
const fonts = @import("test_fonts");
const text = @import("howl_text");
const generated = text.generated;
const terminal = render.terminal;

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

fn canvasConfig(command_capacity: usize) terminal.CanvasConfig {
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

fn terminalFont() !*text.FontSet {
    return text.FontSet.init(std.testing.allocator, .{
        .primary = fonts.primary_font,
        .size = .{ .pixels = 16 },
    });
}

const Presented = struct {
    frame: terminal.Frame,
    external: []const terminal.FrameExternalResource,
};

const Harness = struct {
    allocator: std.mem.Allocator,
    canvas: *terminal.Canvas,
    uploads: []terminal.FrameResourceUpload,
    removals: []terminal.FrameResourceRef,
    commands: []terminal.Command,
    pixels: []u8,
    residencies: [terminal.maximum_external_images + 1]terminal.Residency = undefined,
    residency_count: usize = 0,
    missing: [terminal.maximum_external_images]terminal.FrameExternalResource = undefined,

    fn init(
        allocator: std.mem.Allocator,
        font: *text.FontSet,
        config: terminal.CanvasConfig,
    ) !Harness {
        const owner = try terminal.initCanvas(allocator, font, config);
        errdefer terminal.deinitCanvas(owner);
        const uploads = try allocator.alloc(terminal.FrameResourceUpload, terminal.maximum_external_images + 1);
        errdefer allocator.free(uploads);
        const removals = try allocator.alloc(terminal.FrameResourceRef, terminal.maximum_external_images + 1);
        errdefer allocator.free(removals);
        const commands = try allocator.alloc(terminal.Command, config.command_capacity + 128);
        errdefer allocator.free(commands);
        const pixel_count = std.math.mul(usize, config.atlas.width, config.atlas.height) catch
            return error.OutOfMemory;
        const pixels = try allocator.alloc(u8, pixel_count);
        return .{
            .allocator = allocator,
            .canvas = owner,
            .uploads = uploads,
            .removals = removals,
            .commands = commands,
            .pixels = pixels,
        };
    }

    fn deinit(self: *Harness) void {
        terminal.deinitCanvas(self.canvas);
        self.allocator.free(self.pixels);
        self.allocator.free(self.commands);
        self.allocator.free(self.removals);
        self.allocator.free(self.uploads);
        self.* = undefined;
    }

    fn present(self: *Harness, view: *const client.view.Snapshot) !Presented {
        return self.presentWithBindings(view, &.{});
    }

    fn presentWithBindings(
        self: *Harness,
        view: *const client.view.Snapshot,
        bindings: []const terminal.ExternalImageBinding,
    ) !Presented {
        try terminal.updateWithImageBindings(self.canvas, view, bindings);
        const external = try terminal.missingExternalResources(
            self.canvas,
            self.residencies[0..self.residency_count],
            &self.missing,
        );
        for (external) |value| try self.upsert(.{
            .resource = value.resource,
            .format = value.format,
            .size = value.size,
        });
        const frame = try terminal.frame(
            self.canvas,
            self.residencies[0..self.residency_count],
            .{
                .uploads = self.uploads,
                .removals = self.removals,
                .commands = self.commands,
                .pixels = self.pixels,
            },
        );
        self.acceptFrame(frame);
        return .{ .frame = frame, .external = external };
    }

    fn upsert(self: *Harness, value: terminal.Residency) !void {
        for (self.residencies[0..self.residency_count]) |*existing| {
            if (existing.resource.resource == value.resource.resource) {
                existing.* = value;
                return;
            }
        }
        if (self.residency_count == self.residencies.len) return error.ResidencyLimit;
        self.residencies[self.residency_count] = value;
        self.residency_count += 1;
    }

    fn acceptFrame(self: *Harness, value: terminal.Frame) void {
        for (value.removals) |removal| {
            var index: usize = 0;
            while (index < self.residency_count) : (index += 1) {
                if (self.residencies[index].resource.resource != removal.resource) continue;
                self.residency_count -= 1;
                self.residencies[index] = self.residencies[self.residency_count];
                break;
            }
        }
        for (value.uploads) |upload| self.upsert(.{
            .resource = upload.resource,
            .format = upload.format,
            .size = upload.size,
        }) catch unreachable;
    }
};

fn firstAlpha(commands: []const terminal.Command) ?@FieldType(terminal.Command, "alpha_mask") {
    for (commands) |command| switch (command) {
        .alpha_mask => |value| return value,
        else => {},
    };
    return null;
}

fn firstRgba(commands: []const terminal.Command) ?@FieldType(terminal.Command, "rgba") {
    for (commands) |command| switch (command) {
        .rgba => |value| return value,
        else => {},
    };
    return null;
}

fn constructTerminalCanvas(allocator: std.mem.Allocator, font: *text.FontSet) !void {
    const owner = try terminal.initCanvas(allocator, font, canvasConfig(64));
    terminal.deinitCanvas(owner);
}

test "terminal Canvas owns final atlas residency and recovers after backend loss" {
    var scalar = [_]u32{'A'};
    var cells = [_]client.rich.Cell{cell(&scalar, 1, 0)};
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    const source = sourceSnapshot(&rows, 1);
    const view = try client.view.project(std.testing.allocator, &source);
    defer client.view.deinit(view);
    const font = try terminalFont();
    defer font.deinit();
    var host = try Harness.init(std.testing.allocator, font, canvasConfig(64));
    defer host.deinit();

    const first = try host.present(view);
    try std.testing.expectEqual(@as(usize, 1), first.frame.uploads.len);
    try std.testing.expect(firstAlpha(first.frame.commands) != null);
    try std.testing.expectEqual(@as(u64, 1), first.frame.revision);
    const first_resource = first.frame.uploads[0].resource;

    const second = try host.present(view);
    try std.testing.expectEqual(@as(usize, 0), second.frame.uploads.len);
    try std.testing.expectEqual(@as(u64, 2), second.frame.revision);
    try std.testing.expectEqual(first_resource, firstAlpha(second.frame.commands).?.resource.resource);

    host.residency_count = 0;
    const replay = try terminal.frame(host.canvas, &.{}, .{
        .uploads = host.uploads,
        .removals = host.removals,
        .commands = host.commands,
        .pixels = host.pixels,
    });
    try std.testing.expectEqual(@as(usize, 1), replay.uploads.len);
    try std.testing.expectEqual(first_resource, replay.uploads[0].resource);

    try terminal.resetCanvasCaches(host.canvas);
    host.residency_count = 1;
    host.residencies[0] = .{ .resource = first_resource, .format = .alpha8, .size = replay.uploads[0].size };
    const regenerated = try host.present(view);
    try std.testing.expectEqual(@as(usize, 1), regenerated.frame.uploads.len);
    try std.testing.expectEqual(@backingInt(first_resource.resource), @backingInt(regenerated.frame.uploads[0].resource.resource));
    try std.testing.expect(@backingInt(regenerated.frame.uploads[0].resource.generation) > @backingInt(first_resource.generation));
}

test "terminal Canvas generated box raster remains exact in the final frame" {
    var symbol = [_]u32{0x2500};
    var cells = [_]client.rich.Cell{cell(&symbol, 1, 0)};
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    const source = sourceSnapshot(&rows, 1);
    const view = try client.view.project(std.testing.allocator, &source);
    defer client.view.deinit(view);
    const font = try terminalFont();
    defer font.deinit();
    const config = canvasConfig(64);
    var host = try Harness.init(std.testing.allocator, font, config);
    defer host.deinit();
    const presented = try host.present(view);
    try std.testing.expectEqual(@as(usize, 1), presented.frame.uploads.len);
    const upload = presented.frame.uploads[0];
    var expected: [10 * 20]u8 = undefined;
    try generated.rasterizeBox(&expected, 10, 20, symbol[0], config.box_drawing, .{});
    for (0..20) |row| {
        const at = upload.pixel_offset + row * upload.stride;
        try std.testing.expectEqualSlices(
            u8,
            expected[row * 10 ..][0..10],
            presented.frame.pixels[at..][0..10],
        );
    }
    const usage = terminal.canvasUsage(host.canvas);
    try std.testing.expectEqual(@as(usize, 1), usage.atlas_entries);
    try std.testing.expectEqual(@as(usize, 0), usage.shape.entries);
}

test "terminal Canvas final commands preserve DEC double width and height" {
    var block = [_]u32{0x2588};
    var empty = [_]u32{};
    var row0_cells = [_]client.rich.Cell{ cell(&block, 1, 0), cell(&empty, 1, 0) };
    var row1_cells = row0_cells;
    var row2_cells = row0_cells;
    var row3_cells = row0_cells;
    var rows = [_]client.rich.Row{
        .{ .wrapped = false, .line_geometry = 0, .cells = &row0_cells },
        .{ .wrapped = false, .line_geometry = 1, .cells = &row1_cells },
        .{ .wrapped = false, .line_geometry = 2, .cells = &row2_cells },
        .{ .wrapped = false, .line_geometry = 3, .cells = &row3_cells },
    };
    const source = sourceSnapshot(&rows, 2);
    const view = try client.view.project(std.testing.allocator, &source);
    defer client.view.deinit(view);
    const font = try terminalFont();
    defer font.deinit();
    var host = try Harness.init(std.testing.allocator, font, canvasConfig(32));
    defer host.deinit();
    const frame = (try host.present(view)).frame;
    var destinations: [4]terminal.Rect = undefined;
    var clips: [4]terminal.Rect = undefined;
    var sources: [4]terminal.SourceRect = undefined;
    var count: usize = 0;
    for (frame.commands) |command| switch (command) {
        .alpha_mask => |value| {
            if (count == destinations.len) return error.TooManyAlphaCommands;
            destinations[count] = value.destination;
            clips[count] = value.clip;
            sources[count] = value.resource.source.?;
            count += 1;
        },
        else => {},
    };
    try std.testing.expectEqual(destinations.len, count);
    try std.testing.expectEqualDeep([4]terminal.Rect{
        .{ .x = 0, .y = 0, .width = 10, .height = 20 },
        .{ .x = 0, .y = 20, .width = 20, .height = 20 },
        .{ .x = 0, .y = 40, .width = 20, .height = 40 },
        .{ .x = 0, .y = 40, .width = 20, .height = 40 },
    }, destinations);
    try std.testing.expectEqualDeep([4]terminal.Rect{
        .{ .x = 0, .y = 0, .width = 10, .height = 20 },
        .{ .x = 0, .y = 20, .width = 20, .height = 20 },
        .{ .x = 0, .y = 40, .width = 20, .height = 20 },
        .{ .x = 0, .y = 60, .width = 20, .height = 20 },
    }, clips);
    for (sources) |source_rect| try std.testing.expectEqualDeep(
        terminal.SourceRect{ .x = 0, .y = 0, .width = 10, .height = 20 },
        source_rect,
    );
}

test "terminal Canvas projects OSC 66 fraction and alignment once" {
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
    const font = try terminalFont();
    defer font.deinit();
    var host = try Harness.init(std.testing.allocator, font, canvasConfig(32));
    defer host.deinit();
    const frame = (try host.present(view)).frame;
    const alpha = firstAlpha(frame.commands) orelse return error.MissingAlpha;
    try std.testing.expectEqualDeep(terminal.Rect{ .x = 7, .y = 30, .width = 15, .height = 30 }, alpha.destination);
    try std.testing.expectEqualDeep(terminal.Rect{ .x = 0, .y = 0, .width = 30, .height = 60 }, alpha.clip);
    try std.testing.expectEqualDeep(terminal.SourceRect{ .x = 0, .y = 0, .width = 15, .height = 30 }, alpha.resource.source.?);
}

test "terminal Canvas resolves style colors decorations and invisibility in final commands" {
    var a = [_]u32{'A'};
    var b = [_]u32{'B'};
    var c = [_]u32{'C'};
    var cells = [_]client.rich.Cell{ cell(&a, 1, 0), cell(&b, 1, 0), cell(&c, 1, 0) };
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
    const font = try terminalFont();
    defer font.deinit();
    var host = try Harness.init(std.testing.allocator, font, canvasConfig(64));
    defer host.deinit();
    const frame = (try host.present(view)).frame;

    var alpha_count: usize = 0;
    var saw_dim_red = false;
    var saw_reverse_foreground = false;
    var saw_a_background = false;
    var saw_b_background = false;
    var saw_invisible_background = false;
    var decoration_count: usize = 0;
    for (frame.commands) |command| switch (command) {
        .alpha_mask => |value| {
            alpha_count += 1;
            if (value.destination.x < 10) saw_dim_red = std.meta.eql(value.color, terminal.Color{
                .r = 205,
                .g = 49,
                .b = 49,
                .a = 140,
            }) else if (value.destination.x < 20) saw_reverse_foreground = std.meta.eql(value.color, terminal.Color{
                .r = 1,
                .g = 2,
                .b = 3,
                .a = 255,
            });
        },
        .solid => |value| {
            if (value.rect.x == 0 and value.rect.width == 10 and
                std.meta.eql(value.color, terminal.Color{ .r = 4, .g = 5, .b = 6, .a = 255 }))
                saw_a_background = true;
            if (value.rect.x == 10 and value.rect.width == 10 and
                std.meta.eql(value.color, terminal.Color{ .r = 0xab, .g = 0xcd, .b = 0xef, .a = 255 }))
                saw_b_background = true;
            if (value.rect.x == 20 and value.rect.width == 10 and
                std.meta.eql(value.color, terminal.Color{ .r = 36, .g = 114, .b = 200, .a = 255 }))
                saw_invisible_background = true;
            if (std.meta.eql(value.color, terminal.Color{ .r = 0x44, .g = 0x55, .b = 0x66, .a = 255 }))
                decoration_count += 1;
        },
        else => {},
    };
    try std.testing.expectEqual(@as(usize, 2), alpha_count);
    try std.testing.expect(saw_dim_red and saw_reverse_foreground);
    try std.testing.expect(saw_a_background and saw_b_background and saw_invisible_background);
    try std.testing.expect(decoration_count >= 6);
}

test "terminal Canvas places image z phases around terminal paint phases" {
    var a = [_]u32{'A'};
    var cells = [_]client.rich.Cell{cell(&a, 1, 0)};
    cells[0].background = .{ .kind = .rgb, .value = 0x112233 };
    cells[0].underline_color = .{ .kind = .rgb, .value = 0x445566 };
    cells[0].style_bits |= (1 << 7) | (1 << 8);
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    var images = [_]client.view.Image{.{ .image_id = 7, .generation = 9, .width = 1, .height = 1 }};
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
    const binding = terminal.ExternalImageBinding{
        .image_id = 7,
        .generation = 9,
        .resource = .{ .resource = try terminal.ResourceId.local(2), .generation = @fromBackingInt(9) },
    };
    const default_background = terminal.Color{ .r = 1, .g = 2, .b = 3, .a = 255 };
    const cell_background = terminal.Color{ .r = 0x11, .g = 0x22, .b = 0x33, .a = 255 };
    const decoration = terminal.Color{ .r = 0x44, .g = 0x55, .b = 0x66, .a = 255 };
    const threshold: i32 = std.math.minInt(i32) / 2;
    const cases = [_]struct { z: i32, phase: enum { below_cell_background, below_foreground, above_foreground } }{
        .{ .z = threshold - 1, .phase = .below_cell_background },
        .{ .z = threshold, .phase = .below_foreground },
        .{ .z = -1, .phase = .below_foreground },
        .{ .z = 0, .phase = .above_foreground },
    };

    for (cases) |case| {
        placements[0].z = case.z;
        const view = try client.view.project(std.testing.allocator, &source);
        defer client.view.deinit(view);
        const font = try terminalFont();
        defer font.deinit();
        var host = try Harness.init(std.testing.allocator, font, canvasConfig(16));
        defer host.deinit();
        const presented = try host.presentWithBindings(view, &.{binding});
        try std.testing.expectEqual(@as(usize, 1), presented.external.len);

        var default_index: ?usize = null;
        var cell_background_index: ?usize = null;
        var first_decoration_index: ?usize = null;
        var first_glyph_index: ?usize = null;
        var image_index: ?usize = null;
        for (presented.frame.commands, 0..) |command, index| switch (command) {
            .solid => |solid| {
                if (std.meta.eql(solid.color, default_background) and default_index == null) default_index = index;
                if (std.meta.eql(solid.color, cell_background) and cell_background_index == null) cell_background_index = index;
                if (std.meta.eql(solid.color, decoration) and first_decoration_index == null) first_decoration_index = index;
            },
            .alpha_mask => if (first_glyph_index == null) {
                first_glyph_index = index;
            },
            .rgba => image_index = index,
        };
        const default_at = default_index orelse return error.MissingDefaultBackground;
        const cell_background_at = cell_background_index orelse return error.MissingCellBackground;
        const decoration_at = first_decoration_index orelse return error.MissingDecoration;
        const glyph_at = first_glyph_index orelse return error.MissingAlpha;
        const image_at = image_index orelse return error.MissingRgba;
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

test "terminal Canvas external image residency is requested once and removed when absent" {
    var a = [_]u32{'A'};
    var cells = [_]client.rich.Cell{cell(&a, 1, 0)};
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    var images = [_]client.view.Image{.{ .image_id = 7, .generation = 9, .width = 2, .height = 2 }};
    var placements = [_]client.view.ImagePlacement{.{
        .image_id = 7,
        .generation = 9,
        .row = 0,
        .column = 0,
        .source_x = 0,
        .source_y = 0,
        .source_width = 2,
        .source_height = 2,
        .cell_x = 0,
        .cell_y = 0,
        .pixel_width = 10,
        .pixel_height = 20,
        .z = 0,
    }};
    var image_source = sourceSnapshot(&rows, 1);
    image_source.graphics = .{
        .generation = 1,
        .content_generation = 1,
        .cell_pixel_width = 10,
        .cell_pixel_height = 20,
        .images = &images,
        .placements = &placements,
    };
    const image_view = try client.view.project(std.testing.allocator, &image_source);
    defer client.view.deinit(image_view);
    const plain_source = sourceSnapshot(&rows, 1);
    const plain_view = try client.view.project(std.testing.allocator, &plain_source);
    defer client.view.deinit(plain_view);
    const font = try terminalFont();
    defer font.deinit();
    var host = try Harness.init(std.testing.allocator, font, canvasConfig(32));
    defer host.deinit();
    const binding = terminal.ExternalImageBinding{
        .image_id = 7,
        .generation = 9,
        .resource = .{ .resource = try terminal.ResourceId.local(2), .generation = @fromBackingInt(9) },
    };

    const with_image = try host.presentWithBindings(image_view, &.{binding});
    try std.testing.expectEqual(@as(usize, 1), with_image.external.len);
    try std.testing.expect(firstRgba(with_image.frame.commands) != null);
    const image_resource = with_image.external[0].resource;

    const same = try host.presentWithBindings(image_view, &.{binding});
    try std.testing.expectEqual(@as(usize, 0), same.external.len);

    const without = try host.present(plain_view);
    var removed = false;
    for (without.frame.removals) |value| if (std.meta.eql(value, image_resource)) removed = true;
    try std.testing.expect(removed);
    try std.testing.expect(firstRgba(without.frame.commands) == null);
}

test "terminal Canvas block cursor is final presentation not compositor topology" {
    var scalar = [_]u32{'A'};
    var cells = [_]client.rich.Cell{cell(&scalar, 1, 0)};
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    var source = sourceSnapshot(&rows, 1);
    source.begin.cursor_visible = true;
    source.presentation.presence_bits = 1;
    source.presentation.cursor = .{ .r = 9, .g = 8, .b = 7, .a = 255 };
    source.presentation.cursor_text = null;
    const view = try client.view.project(std.testing.allocator, &source);
    defer client.view.deinit(view);
    const font = try terminalFont();
    defer font.deinit();
    var host = try Harness.init(std.testing.allocator, font, canvasConfig(32));
    defer host.deinit();
    const frame = (try host.present(view)).frame;
    var cursor_background = false;
    var recolored = false;
    for (frame.commands) |command| switch (command) {
        .solid => |value| if (std.meta.eql(value.color, terminal.Color{ .r = 9, .g = 8, .b = 7, .a = 255 })) {
            cursor_background = true;
        },
        .alpha_mask => |value| if (value.destination.x == 0 and value.destination.y <= 20 and
            std.meta.eql(value.color, terminal.Color{ .r = 1, .g = 2, .b = 3, .a = 255 }))
        {
            recolored = true;
        },
        else => {},
    };
    try std.testing.expect(cursor_background);
    try std.testing.expect(recolored);
}

test "dense 40x120 terminal Canvas is bounded and recovers from command exhaustion" {
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
        row.* = .{ .wrapped = false, .line_geometry = 0, .cells = cells[first .. first + column_count] };
    }
    const source = sourceSnapshot(rows, column_count);
    const view = try client.view.project(std.testing.allocator, &source);
    defer client.view.deinit(view);
    const font = try terminalFont();
    defer font.deinit();

    const limited = try terminal.initCanvas(std.testing.allocator, font, canvasConfig(command_count - 1));
    defer terminal.deinitCanvas(limited);
    try std.testing.expectError(error.CommandLimit, terminal.update(limited, view));
    const failed = terminal.canvasUsage(limited);
    try std.testing.expectEqual(@as(u64, 0), failed.revision);
    try std.testing.expectEqual(@as(u64, 0), failed.resource_generation);

    var host = try Harness.init(std.testing.allocator, font, canvasConfig(command_count));
    defer host.deinit();
    const frame = (try host.present(view)).frame;
    try std.testing.expectEqual(command_count, frame.commands.len);
    try std.testing.expectEqual(@as(u64, 1), frame.revision);
}

test "terminal Canvas incremental rows equal complete final commands" {
    var baseline_scalars = [_][1]u32{ .{'A'}, .{'B'}, .{'C'}, .{'D'}, .{'E'}, .{'F'} };
    var baseline_cells: [6][1]client.rich.Cell = undefined;
    var baseline_rows: [6]client.rich.Row = undefined;
    for (&baseline_cells, &baseline_rows, 0..) |*cells, *row, index| {
        cells.* = .{cell(&baseline_scalars[index], 1, 0)};
        row.* = .{ .wrapped = false, .line_geometry = 0, .cells = cells };
    }
    var baseline_source = sourceSnapshot(&baseline_rows, 1);
    baseline_source.begin.revision = 30;
    baseline_source.begin.terminal_revision = 30;
    const baseline_view = try client.view.project(std.testing.allocator, &baseline_source);
    defer client.view.deinit(baseline_view);
    const font = try terminalFont();
    defer font.deinit();
    var cached_config = canvasConfig(64);
    cached_config.incremental_row_capacity = 6;
    cached_config.incremental_command_capacity = 32;
    var cached = try Harness.init(std.testing.allocator, font, cached_config);
    defer cached.deinit();
    var complete = try Harness.init(std.testing.allocator, font, canvasConfig(64));
    defer complete.deinit();
    const cached_base = try cached.present(baseline_view);
    const complete_base = try complete.present(baseline_view);
    try std.testing.expectEqualDeep(cached_base.frame.commands, complete_base.frame.commands);

    var shifted_scalars = [_][1]u32{ .{'B'}, .{'C'}, .{'D'}, .{'X'}, .{'F'}, .{'G'} };
    var shifted_cells: [6][1]client.rich.Cell = undefined;
    var shifted_rows: [6]client.rich.Row = undefined;
    for (&shifted_cells, &shifted_rows, 0..) |*cells, *row, index| {
        cells.* = .{cell(&shifted_scalars[index], 1, 0)};
        row.* = .{ .wrapped = false, .line_geometry = 0, .cells = cells };
    }
    var shifted_source = sourceSnapshot(&shifted_rows, 1);
    shifted_source.begin.revision = 31;
    shifted_source.begin.terminal_revision = 31;
    var shifted_rich = shifted_source.view();
    var changed = [_]bool{ false, false, false, true, false, true };
    shifted_rich.changed_rows = &changed;
    shifted_rich.row_shift = 1;
    const shifted_view = try client.view.projectView(std.testing.allocator, &shifted_rich);
    defer client.view.deinit(shifted_view);
    const cached_shifted = try cached.present(shifted_view);
    const complete_shifted = try complete.present(shifted_view);
    try std.testing.expectEqualDeep(cached_shifted.frame.commands, complete_shifted.frame.commands);
}

test "terminal Canvas construction releases every staged allocation and validates bounds" {
    const font = try terminalFont();
    defer font.deinit();
    try std.testing.checkAllAllocationFailures(std.testing.allocator, constructTerminalCanvas, .{font});
    var invalid = canvasConfig(64);
    invalid.cell_size.width = 0;
    try std.testing.expectError(error.InvalidCanvasConfig, terminal.initCanvas(std.testing.failing_allocator, font, invalid));
    invalid = canvasConfig(0);
    try std.testing.expectError(error.InvalidCanvasConfig, terminal.initCanvas(std.testing.failing_allocator, font, invalid));
}
