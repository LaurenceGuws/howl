//! Joined canonical BG-witness and complete projection proofs.
const std = @import("std");
const render = @import("howl_render");
const RR = render.terminal;
const VT = @import("howl_vt").Terminal;
const allocator = std.testing.allocator;

const Output = struct {
    commands: [32768]RR.Command = undefined,
    pixels: [512 * 512 * 5]u8 = undefined,
    uploads: [RR.maximum_frame_resources]RR.FrameResourceUpload = undefined,
    removals: [RR.maximum_frame_resources]RR.ResourceRef = undefined,

    fn frame(self: *Output, owner: *RR.Renderer) !RR.Frame {
        return RR.frame(owner, &.{}, .{
            .commands = &self.commands,
            .pixels = &self.pixels,
            .uploads = &self.uploads,
            .removals = &self.removals,
        });
    }
};

test "BG witness reuse equals complete projection across skipped writes invalidation and rejected preparation" {
    const font = try render.text.FontSet.init(allocator, .{
        .primary = @import("test_fonts").primary_font,
        .size = .{ .pixels = 12 },
    });
    defer font.deinit();
    const metrics = font.metrics();
    for ([_][2]u16{ .{ 3, 20 }, .{ 7, 40 }, .{ 24, 80 }, .{ 66, 320 } }) |grid| {
        var vt: VT = undefined;
        try VT.initWithHistoryInto(&vt, allocator, grid[0], grid[1], 8);
        defer vt.deinit();
        var cfg: RR.Config = .{
            .cell_size = .{ .width = metrics.advance_width, .height = metrics.line_height },
            .box_drawing = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
            .shape_cache = .{ .entry_capacity = 256, .scalar_capacity = 512, .glyph_capacity = 512, .max_sequence_scalars = 16 },
            .atlas = .{ .width = 512, .height = 512, .entry_capacity = 256 },
            .shaped_capacity = 32,
            .raster_bytes = 512 * 512,
            .command_capacity = 64,
            .command_limit = 32768,
        };
        const full = try RR.initPrivate(allocator, .{ .regular = font }, cfg);
        defer RR.deinit(full);
        cfg.incremental_row_capacity = grid[0];
        cfg.incremental_command_capacity = 32768;
        if (grid[0] == 3) try std.testing.checkAllAllocationFailures(allocator, backgroundConstruction, .{ font, cfg });
        const cached = try RR.initPrivate(allocator, .{ .regular = font }, cfg);
        defer RR.deinit(cached);
        const left = try allocator.create(Output);
        defer allocator.destroy(left);
        const right = try allocator.create(Output);
        defer allocator.destroy(right);
        var previous: ?u64 = null;
        const steps = [_][]const u8{
            "\x1b[44m\x1b[2J\x1b[Hblue",
            "\x1b[H\x1b[31mBLUE", // glyph/FG change while BG is unchanged
            "\x1b[H\x1b[4mblue", // unchanged BG cannot hide new decoration
            "\x1b[H\x1b[24;9mBLUE",
            "\x1b[H\x1b[29;7mreverse\x1b[27m",
            "\x1b[?5h\x1b[H\x1b[32mGREEN", // FG affects BG while global reverse
            "\x1b[H\x1b[33mGREEN",
            "\x1b[?5l\x1b]4;4;rgb:ab/cd/ef\x07",
            "\x1b]10;rgb:20/30/40\x07\x1b]11;rgb:40/30/20\x07",
            "\x1b[0m\x1b[999;1H\n\n\n\n\n\n\n\n", // repeated row-ring recycling
            "\x1b[?1049h\x1b[45m\x1b[2J\x1b[Halternate",
            "\x1b[?1049l",
            "\x1b[H\x1b#6WIDE\x1b[2;1H\x1b#3UPPER\x1b[3;1H\x1b#4lower",
            "\x1b[H\x1b#5normal\x1b[2;1H\x1b#5normal\x1b[3;1H\x1b#5normal",
            "\x1b[H\x1b[0m\x1b[2J\x1b[41mA\x1b[42mB\x1b[43mC\x1b[44mD\x1b[45mE\x1b[46mF\x1b[47mG\x1b[40mH\x1b[41mI\x1b[42mJ",
            "\x1b[H\x1b[0m\x1b[4mA\xcc\x81\xe7\x95\x8c\x1b[0m",
            "\x1b[48;2;11;22;33m\x1b[2J\x1b[Hredraw",
        };
        for (steps, 0..) |bytes, index| {
            // zig-audit: acknowledge discard
            // reason: This projection test asserts each resulting Render frame against the full redraw, not the feed summary.
            _ = try vt.feed(bytes);
            if (index == steps.len - 2) try vt.resize(grid[0] - 1, grid[1] - 3);
            if (index == steps.len - 1) try vt.resize(grid[0], grid[1]);
            const history_offset: u32 = if (index == 9) 2 else 0;
            const obs = vt.observation();
            // No glyph row repair hints: this explicitly tests the broad update path.
            const hint: RR.RowChanges = .{ .base_revision = previous, .rows = null };
            if (index == steps.len - 1) {
                // Fail after BG staging, then retry with the unchanged accepted base.
                const bogus = RR.ExternalImageBinding{
                    .image_id = 1,
                    .generation = 1,
                    .resource = .{ .resource = try RR.ResourceId.init(2), .generation = @fromBackingInt(1) },
                };
                try std.testing.expectError(error.InvalidImageBinding, RR.updateObservationRows(cached, obs, history_offset, hint, &.{bogus}));
            }
            try RR.updateObservationRows(cached, obs, history_offset, hint, &.{});
            try RR.updateObservation(full, obs, history_offset, &.{});
            const expected = try left.frame(full);
            const actual = try right.frame(cached);
            errdefer std.debug.print("BG projection mismatch grid={d}x{d} step={d}\n", .{ grid[0], grid[1], index });
            try std.testing.expectEqualDeep(expected.commands, actual.commands);
            try std.testing.expectEqual(expected.content_command_count, actual.content_command_count);
            try std.testing.expectEqualDeep(expected.uploads, actual.uploads);
            try std.testing.expectEqualSlices(u8, expected.pixels, actual.pixels);
            previous = obs.contentSequence();
        }
        // A source rebind without provenance must rebuild even if counters coincide.
        var rebound: VT = undefined;
        try VT.initWithHistoryInto(&rebound, allocator, grid[0], grid[1], 8);
        defer rebound.deinit();
        // zig-audit: acknowledge discard
        // reason: The source-rebinding proof compares complete frames after attaching the new observation.
        _ = try rebound.feed("\x1b[41m\x1b[2J");
        try RR.updateObservationRows(cached, rebound.observation(), 0, null, &.{});
        try RR.updateObservation(full, rebound.observation(), 0, &.{});
        try std.testing.expectEqualDeep((try left.frame(full)).commands, (try right.frame(cached)).commands);
    }
}

fn backgroundConstruction(a: std.mem.Allocator, font: *render.text.FontSet, config: RR.Config) !void {
    const owner = try RR.initPrivate(a, .{ .regular = font }, config);
    defer RR.deinit(owner);
}

test "compact backgrounds remain between deepest images and negative images and glyphs" {
    const font = try render.text.FontSet.init(allocator, .{
        .primary = @import("test_fonts").primary_font,
        .size = .{ .pixels = 12 },
    });
    defer font.deinit();
    const metrics = font.metrics();
    const core = try RR.initPrivate(allocator, .{ .regular = font }, .{
        .cell_size = .{ .width = metrics.advance_width, .height = metrics.line_height },
        .box_drawing = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
        .shape_cache = .{ .entry_capacity = 32, .scalar_capacity = 128, .glyph_capacity = 128, .max_sequence_scalars = 16 },
        .atlas = .{ .width = 512, .height = 512, .entry_capacity = 128 },
        .shaped_capacity = 32,
        .raster_bytes = 512 * 512,
        .command_capacity = 256,
        .incremental_row_capacity = 3,
        .incremental_command_capacity = 256,
    });
    defer RR.deinit(core);
    var vt: VT = undefined;
    try VT.initWithHistoryInto(&vt, allocator, 3, 20, 0);
    defer vt.deinit();
    try vt.setCellPixelSize(metrics.advance_width, metrics.line_height);
    // zig-audit: acknowledge discard
    // reason: This constructs the glyph and image scene; subsequent bindings and command order are explicitly asserted.
    _ = try vt.feed("\x1b[44m\x1b[2J\x1b[H\x1b[4mA" ++
        "\x1b[H\x1b_Ga=T,f=32,s=1,v=1,i=1,z=-1073741825,C=1,q=2;/wAA/w==\x1b\\" ++
        "\x1b[H\x1b_Ga=T,f=32,s=1,v=1,i=2,z=-1,C=1,q=2;AP8A/w==\x1b\\" ++
        "\x1b[H\x1b_Ga=T,f=32,s=1,v=1,i=3,z=1,C=1,q=2;AAD//w==\x1b\\");
    var stage: []const u8 = "binding plan";
    errdefer std.debug.print("image ordering proof failed at {s}\n", .{stage});
    var bindings: [RR.maximum_external_images]RR.ExternalImageBinding = undefined;
    const selected = try RR.planObservationImageBindings(&.{}, RR.usage(core), vt.observation(), 0, &bindings);
    try std.testing.expectEqual(@as(usize, 3), selected.len);
    var residency: [3]RR.Residency = undefined;
    for (selected, 0..) |binding, i| residency[i] = .{
        .resource = binding.resource,
        .format = .rgba8,
        .size = .{ .width = 1, .height = 1 },
    };
    const output = try allocator.create(Output);
    defer allocator.destroy(output);
    var base: ?u64 = null;
    for (0..2) |step| {
        // zig-audit: acknowledge discard
        // reason: The second frame deliberately changes foreground ink, then verifies stable image depth ordering.
        if (step == 1) _ = try vt.feed("\x1b[H\x1b[31mB");
        const obs = vt.observation();
        stage = "update";
        try RR.updateObservationRows(core, obs, 0, .{ .base_revision = base }, selected);
        stage = "frame";
        const frame = try RR.frame(core, &residency, .{
            .commands = &output.commands,
            .pixels = &output.pixels,
            .uploads = &output.uploads,
            .removals = &output.removals,
        });
        var at: [3]?usize = @splat(null);
        for (frame.commands[0..frame.content_command_count], 0..) |cmd, index| if (cmd == .rgba) {
            for (selected, 0..) |binding, i| if (cmd.rgba.resource.resource.resource == binding.resource.resource) {
                at[i] = index;
            };
        };
        const deep = at[0] orelse return error.MissingDeepImage;
        const negative = at[1] orelse return error.MissingNegativeImage;
        const positive = at[2] orelse return error.MissingPositiveImage;
        try std.testing.expect(deep < negative and negative < positive);
        // Default background, deepest image, three compact row BGs, negative image.
        try std.testing.expectEqual(@as(usize, 1), deep);
        try std.testing.expectEqual(@as(usize, 5), negative);
        for (frame.commands[deep + 1 .. negative]) |cmd| {
            try std.testing.expect(cmd == .solid);
            try std.testing.expectEqual(@as(u16, 20 * metrics.advance_width), cmd.solid.rect.width);
            try std.testing.expectEqual(metrics.line_height, cmd.solid.rect.height);
        }
        var has_glyph = false;
        for (frame.commands[negative + 1 .. positive]) |cmd| has_glyph = has_glyph or cmd == .alpha_mask;
        try std.testing.expect(has_glyph);
        base = obs.contentSequence();
    }
}

fn fontConfig(font: *render.text.FontSet) RR.Config {
    const metrics = font.metrics();
    return .{
        .cell_size = .{ .width = metrics.advance_width, .height = metrics.line_height },
        .box_drawing = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
        .shape_cache = .{ .entry_capacity = 256, .scalar_capacity = 512, .glyph_capacity = 512, .max_sequence_scalars = 16 },
        .atlas = .{ .width = 512, .height = 512, .entry_capacity = 256 },
        .shaped_capacity = 32,
        .raster_bytes = 512 * 512,
        .command_capacity = 64,
        .command_limit = 32768,
    };
}

test "full row contextual operators equal one native shaping run beyond retained cluster capacity" {
    const font = try render.text.FontSet.init(allocator, .{
        .primary = @import("test_fonts").normal_ligature_font,
        .size = .{ .pixels = 18 },
    });
    defer font.deinit();
    const buffer = try render.text.ShapeBuffer.init(allocator, 1024);
    defer buffer.deinit();
    const output = try allocator.create(Output);
    defer allocator.destroy(output);
    const scalars: [512]u32 = @splat('#');
    const bytes: [512]u8 = @splat('#');
    var clusters: [512]u32 = undefined;
    for (&clusters, 0..) |*value, i| value.* = @intCast(i);
    var shaped: [1024]render.text.Glyph = undefined;
    for ([_]u16{ 8, 31, 512 }) |count| {
        var vt: VT = undefined;
        try VT.initWithHistoryInto(&vt, allocator, 2, count, 0);
        defer vt.deinit();
        // zig-audit: acknowledge discard
        // reason: Native glyph rasters and final positions below prove the complete output, independent of the feed summary.
        _ = try vt.feed("\x1b[?25l");
        // zig-audit: acknowledge discard
        // reason: The shaped native run below is compared against every published glyph for these exact bytes.
        _ = try vt.feed(bytes[0..count]);
        const owner = try RR.initPrivate(allocator, .{ .regular = font }, fontConfig(font));
        defer RR.deinit(owner);
        try RR.updateObservation(owner, vt.observation(), 0, &.{});
        const frame = try output.frame(owner);
        const native = try font.shape(buffer, .{ .codepoints = scalars[0..count], .clusters = clusters[0..count] }, &shaped);
        var command_index: usize = 0;
        for (native.glyphs) |glyph| {
            var raster = try font.rasterize(allocator, native.face_index, glyph.id);
            defer raster.deinit();
            if (raster.width == 0 or raster.height == 0) continue;
            while (command_index < frame.commands.len and frame.commands[command_index] != .alpha_mask) command_index += 1;
            try std.testing.expect(command_index < frame.commands.len);
            const mask = frame.commands[command_index].alpha_mask;
            command_index += 1;
            const x = @as(i64, glyph.cluster) * font.metrics().advance_width * 64 + glyph.x_offset + @as(i64, raster.left) * 64;
            try std.testing.expectEqual(@as(i32, @intCast(@divFloor(x, 64))), mask.destination.x);
            try std.testing.expectEqual(raster.width, mask.resource.source.?.width);
            try std.testing.expectEqual(raster.height, mask.resource.source.?.height);
            const upload = frame.uploads[0];
            for (0..raster.height) |row| {
                const start = upload.pixel_offset + (@as(usize, mask.resource.source.?.y) + row) * upload.stride + mask.resource.source.?.x;
                try std.testing.expectEqualSlices(u8, raster.pixels[row * raster.width ..][0..raster.width], frame.pixels[start..][0..raster.width]);
            }
        }
        for (frame.commands[command_index..]) |command| try std.testing.expect(command != .alpha_mask);
    }
}

test "colour glyph frame retains intrinsic ink through cursor residency eviction reset and failed frame scratch" {
    const font = try render.text.FontSet.init(allocator, .{
        .primary = @import("test_fonts").primary_font,
        .fallbacks = &.{@import("test_fonts").colour_font},
        .size = .{ .pixels = 20 },
    });
    defer font.deinit();
    var vt: VT = undefined;
    try VT.initWithHistoryInto(&vt, allocator, 2, 12, 0);
    defer vt.deinit();
    const owner = try RR.initPrivate(allocator, .{ .regular = font }, fontConfig(font));
    defer RR.deinit(owner);
    // zig-audit: acknowledge discard
    // reason: The resulting two atlas planes, cursor replay, exact residency and recovery are asserted below.
    _ = try vt.feed("M\xf0\x9f\x98\x80\x1b[2G");
    try RR.updateObservation(owner, vt.observation(), 0, &.{});
    const output = try allocator.create(Output);
    defer allocator.destroy(output);
    const frame = try output.frame(owner);
    try std.testing.expectEqual(@as(usize, 2), frame.uploads.len);
    var residency: [2]RR.Residency = undefined;
    var color_id: RR.ResourceRef = undefined;
    for (frame.uploads, 0..) |upload, index| {
        residency[index] = .{ .resource = upload.resource, .format = upload.format, .size = upload.size };
        if (upload.format == .rgba8) {
            color_id = upload.resource;
            var red = false;
            var blue = false;
            for (0..upload.pixel_count / 4) |pixel| {
                const rgba = frame.pixels[upload.pixel_offset + pixel * 4 ..][0..4];
                red = red or (rgba[0] > 240 and rgba[2] == 0 and rgba[3] > 240);
                blue = blue or (rgba[0] == 0 and rgba[2] > 240 and rgba[3] >= 120 and rgba[3] <= 136);
            }
            try std.testing.expect(red and blue);
        }
    }
    var rgba_commands: usize = 0;
    for (frame.commands) |command| if (command == .rgba) {
        rgba_commands += 1;
        const value = command.rgba;
        try std.testing.expectEqual(color_id, value.resource.resource);
        try std.testing.expect(value.destination.width <= font.metrics().advance_width * 2);
        try std.testing.expect(value.destination.height <= font.metrics().line_height);
    };
    try std.testing.expectEqual(@as(usize, 2), rgba_commands); // content + untinted cursor replay
    const cached = try RR.frame(owner, &residency, .{ .commands = &output.commands, .pixels = &.{}, .uploads = &.{}, .removals = &output.removals });
    try std.testing.expectEqual(@as(usize, 0), cached.uploads.len);
    @memset(output.pixels[0..16], 0xa5);
    try std.testing.expectError(error.PixelLimit, RR.frame(owner, &.{}, .{
        .commands = &output.commands,
        .pixels = output.pixels[0..16],
        .uploads = &output.uploads,
        .removals = &output.removals,
    }));
    try std.testing.expectEqualSlices(u8, &@as([16]u8, @splat(0xa5)), output.pixels[0..16]);
    try RR.resetCaches(owner);
    try RR.updateObservation(owner, vt.observation(), 0, &.{});
    const reset = try RR.frame(owner, &residency, .{ .commands = &output.commands, .pixels = &output.pixels, .uploads = &output.uploads, .removals = &output.removals });
    try std.testing.expectEqual(@as(usize, 2), reset.uploads.len);
    try std.testing.expectEqual(@as(usize, 0), reset.removals.len);
    for (reset.uploads) |upload| if (upload.format == .rgba8) {
        try std.testing.expectEqual(color_id.resource, upload.resource.resource);
        try std.testing.expect(@backingInt(upload.resource.generation) > @backingInt(color_id.generation));
    };
}

test "lazy colour identity stays disjoint from same-batch external images" {
    const font = try render.text.FontSet.init(allocator, .{
        .primary = @import("test_fonts").primary_font,
        .fallbacks = &.{@import("test_fonts").colour_font},
        .size = .{ .pixels = 20 },
    });
    defer font.deinit();
    var vt: VT = undefined;
    try VT.initWithHistoryInto(&vt, allocator, 3, 12, 0);
    defer vt.deinit();
    try vt.setCellPixelSize(font.metrics().advance_width, font.metrics().line_height);
    const owner = try RR.initPrivate(allocator, .{ .regular = font }, fontConfig(font));
    defer RR.deinit(owner);
    // zig-audit: acknowledge discard
    // reason: The exact fresh image identities, colour identity and ensuing frame residency are checked below.
    _ = try vt.feed("M\xf0\x9f\x98\x80\x1b[?25l\x1b[H\x1b_Ga=T,f=32,s=1,v=1,i=1,C=1,q=2;/wAA/w==\x1b\\");
    var storage: [RR.maximum_external_images]RR.ExternalImageBinding = undefined;
    const bindings = try RR.planObservationImageBindings(&.{}, RR.usage(owner), vt.observation(), 0, &storage);
    try std.testing.expectEqual(@as(usize, 1), bindings.len);
    try RR.updateObservation(owner, vt.observation(), 0, bindings);
    const residency = [_]RR.Residency{.{ .resource = bindings[0].resource, .format = .rgba8, .size = .{ .width = 1, .height = 1 } }};
    const output = try allocator.create(Output);
    defer allocator.destroy(output);
    const frame = try RR.frame(owner, &residency, .{
        .commands = &output.commands,
        .pixels = &output.pixels,
        .uploads = &output.uploads,
        .removals = &output.removals,
    });
    try std.testing.expectEqual(@as(usize, 2), frame.uploads.len);
    for (frame.uploads) |upload| try std.testing.expect(upload.resource.resource != bindings[0].resource.resource);
    // A later alpha-only miss must not invalidate the retained colour texture.
    var complete: [3]RR.Residency = undefined;
    complete[0] = residency[0];
    for (frame.uploads, 0..) |upload, i| complete[i + 1] = .{ .resource = upload.resource, .format = upload.format, .size = upload.size };
    // zig-audit: acknowledge discard
    // reason: This adds a previously un-rasterized alpha glyph; only the alpha plane may be uploaded.
    _ = try vt.feed("\x1b[2;1HZ");
    try RR.updateObservation(owner, vt.observation(), 0, bindings);
    const changed = try RR.frame(owner, &complete, .{
        .commands = &output.commands,
        .pixels = &output.pixels,
        .uploads = &output.uploads,
        .removals = &output.removals,
    });
    try std.testing.expectEqual(@as(usize, 1), changed.uploads.len);
    try std.testing.expectEqual(RR.ResourceFormat.alpha8, changed.uploads[0].format);
}

test "wide symbol font fits complete up and down triangles into narrow terminal cells" {
    const font = try render.text.FontSet.init(allocator, .{
        .primary = @import("test_fonts").primary_font,
        .fallbacks = &.{@import("test_fonts").colour_font},
        .size = .{ .pixels = 20 },
    });
    defer font.deinit();
    var cfg = fontConfig(font);
    cfg.cell_size.width = 9;
    var vt: VT = undefined;
    try VT.initWithHistoryInto(&vt, allocator, 2, 12, 0);
    defer vt.deinit();
    // zig-audit: acknowledge discard
    // reason: Both full raster extents and opposing triangle ink directions are proved below.
    _ = try vt.feed("\x1b[?25l\xe2\x96\xb2\xe2\x96\xbc");
    const owner = try RR.initPrivate(allocator, .{ .regular = font }, cfg);
    defer RR.deinit(owner);
    try RR.updateObservation(owner, vt.observation(), 0, &.{});
    const output = try allocator.create(Output);
    defer allocator.destroy(output);
    const frame = try output.frame(owner);
    var masks: usize = 0;
    for (frame.commands) |command| if (command == .alpha_mask) {
        const mask = command.alpha_mask;
        const src = mask.resource.source.?;
        try std.testing.expectEqual(@as(u16, 9), mask.clip.width);
        try std.testing.expect(mask.destination.x >= @as(i32, @intCast(masks * 9)));
        try std.testing.expect(mask.destination.x + @as(i32, mask.destination.width) <= (masks + 1) * 9);
        try std.testing.expectEqual(src.width, mask.destination.width);
        var top: usize = 0;
        var bottom: usize = 0;
        const upload = frame.uploads[0];
        for (0..src.height) |row| {
            const start = (@as(usize, src.y) + row) * upload.stride + src.x;
            var count: usize = 0;
            for (frame.pixels[start..][0..src.width]) |alpha| if (alpha >= 100) {
                count += 1;
            };
            if (row < src.height / 2) top += count else bottom += count;
        }
        if (masks == 0) try std.testing.expect(bottom > top) else try std.testing.expect(top > bottom);
        masks += 1;
    };
    try std.testing.expectEqual(@as(usize, 2), masks);
}

test "coloured background rows retain glyphs through sparse edits overflow and rejected preparation" {
    const font = try render.text.FontSet.init(allocator, .{
        .primary = @import("test_fonts").primary_font,
        .size = .{ .pixels = 12 },
    });
    defer font.deinit();
    const metrics = font.metrics();
    for ([_][2]u16{ .{ 3, 20 }, .{ 7, 40 }, .{ 24, 80 }, .{ 66, 320 } }) |grid| {
        for ([_]usize{ 1, 32768 }) |budget| {
            var vt: VT = undefined;
            try VT.initWithHistoryInto(&vt, allocator, grid[0], grid[1], 8);
            defer vt.deinit();
            var cfg: RR.Config = .{
                .cell_size = .{ .width = metrics.advance_width, .height = metrics.line_height },
                .box_drawing = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
                .shape_cache = .{ .entry_capacity = 256, .scalar_capacity = 512, .glyph_capacity = 512, .max_sequence_scalars = 16 },
                .atlas = .{ .width = 512, .height = 512, .entry_capacity = 256 },
                .shaped_capacity = 32,
                .raster_bytes = 512 * 512,
                .command_capacity = 64,
                .command_limit = 32768,
            };
            const full = try RR.initPrivate(allocator, .{ .regular = font }, cfg);
            defer RR.deinit(full);
            cfg.incremental_row_capacity = grid[0];
            cfg.incremental_command_capacity = budget;
            const cached = try RR.initPrivate(allocator, .{ .regular = font }, cfg);
            defer RR.deinit(cached);
            const left = try allocator.create(Output);
            defer allocator.destroy(left);
            const right = try allocator.create(Output);
            defer allocator.destroy(right);
            var generations: [66]u64 = @splat(0);
            var repairs: [66]bool = @splat(false);
            var previous: ?u64 = null;
            const steps = [_][]const u8{
                "\x1b[44m\x1b[2J\x1b[Hfirst\x1b[2;1Hsecond\x1b[3;1Hthird",
                "\x1b[H\x1b[31mFIRST",
                "\x1b[2;1H\x1b[42mSECOND",
                "\x1b[3;1H\x1b[33mTHIRD",
                "\x1b[H\x1b[41mA\x1b[42mB\x1b[43mC\x1b[44mD\x1b[45mE\x1b[46mF\x1b[47mG\x1b[40mH\x1b[41mI\x1b[42mJ",
                "\x1b[2;1H\x1b[34moverflows remain",
                "\x1b]4;4;rgb:ab/cd/ef\x07",
                "\x1b]10;rgb:20/30/40\x07\x1b]11;rgb:40/30/20\x07",
                "\x1b[3;1H\x1b[4mdecoration",
                "\x1b[24m\x1b[?5h\x1b[Hreverse",
                "\x1b[?5l\x1b[H\x1b[0m\x1b[44mnormal",
                "\x1b[999;1H\n\n\n\n\n\n\n\n",
                "\x1b[2;1Hafter rotation",
                "\x1b[?1049h\x1b[45m\x1b[2J\x1b[Halternate",
                "\x1b[?1049l\x1b[Hrestored",
                "\x1b[2;1Hresize",
                "\x1b[Hretry",
            };
            for (steps, 0..) |bytes, index| {
                // zig-audit: acknowledge discard
                // reason: Each feed's complete projected cells, colours, glyphs and resources are checked against the independent full projection below.
                _ = try vt.feed(bytes);
                if (index == 15) try vt.resize(grid[0] - 1, grid[1] - 3);
                if (index == 16) try vt.resize(grid[0], grid[1]);
                const obs = vt.observation();
                const view = obs.semanticView(0);
                for (0..view.rows) |row| {
                    const generation = view.rowGeneration(@intCast(row)).?;
                    repairs[row] = previous == null or generation != generations[row];
                    generations[row] = generation;
                }
                const hint: RR.RowChanges = .{ .base_revision = previous, .rows = repairs[0..view.rows] };
                if (index == 3) {
                    const bogus: RR.ExternalImageBinding = .{
                        .image_id = 1,
                        .generation = 1,
                        .resource = .{ .resource = try RR.ResourceId.init(2), .generation = @fromBackingInt(1) },
                    };
                    try std.testing.expectError(error.InvalidImageBinding, RR.updateObservationRows(cached, obs, 0, hint, &.{bogus}));
                }
                try RR.updateObservationRows(cached, obs, 0, hint, &.{});
                try RR.updateObservation(full, obs, 0, &.{});
                const expected = try left.frame(full);
                const actual = try right.frame(cached);
                errdefer std.debug.print("coloured glyph mismatch grid={d}x{d} budget={d} step={d}\n", .{ grid[0], grid[1], budget, index });
                try std.testing.expectEqualDeep(expected.commands, actual.commands);
                try std.testing.expectEqualDeep(expected.uploads, actual.uploads);
                try std.testing.expectEqualSlices(u8, expected.pixels, actual.pixels);
                try std.testing.expectEqual(expected.content_command_count, actual.content_command_count);
                // A uniform RowScene may return after scrolling away every BG
                // override; when present, it must cover the complete glyph scene.
                if (RR.rowScene(cached) != null) {
                    for (actual.commands[1..actual.content_command_count]) |command|
                        try std.testing.expect(command != .solid);
                }
                previous = obs.contentSequence();
            }
        }
    }
}
