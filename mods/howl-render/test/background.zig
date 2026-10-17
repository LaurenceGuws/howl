//! Joined canonical BG-witness and complete projection proofs.
const std = @import("std");
const render = @import("howl_render");
const RR = render.terminal;
const VT = @import("howl_vt").Terminal;
const allocator = std.testing.allocator;

const Output = struct {
    commands: [32768]RR.Command = undefined,
    pixels: [512 * 512]u8 = undefined,
    uploads: [8]RR.FrameResourceUpload = undefined,
    removals: [8]RR.ResourceRef = undefined,

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
