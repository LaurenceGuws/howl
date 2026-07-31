//! Proves the selected generated terminal-glyph capability.

const std = @import("std");
const generated = @import("howl_render").generated;

test "generated public surface retains exact curated values" {
    try std.testing.expect(!@hasDecl(generated, "Range"));
    try std.testing.expect(!@hasDecl(generated, "PointF"));
    const rasterize: *const fn ([]u8, u16, u16, u32) generated.Error!void =
        &generated.rasterize;
    try std.testing.expect(rasterize == &generated.rasterize);
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(generated.BoxDrawingConfig));
    try std.testing.expectEqual(@as(usize, 2), @sizeOf(generated.BoxDrawingSizing));
    const defaults = generated.BoxDrawingConfig{
        .dpi_x = .{ .numerator = 96, .denominator = 1 },
        .dpi_y = .{ .numerator = 96, .denominator = 1 },
    };
    try std.testing.expectEqual(
        @as(u32, 0x3a83126f),
        @as(u32, @bitCast(defaults.stroke_points[0])),
    );
}

test "generated families classify exact retained ranges and reject neighbors" {
    const cases = .{
        .{ @as(u32, 0x2500), generated.Glyph.box },
        .{ @as(u32, 0x2580), generated.Glyph.block },
        .{ @as(u32, 0x2800), generated.Glyph.braille },
        .{ @as(u32, 0x1fb00), generated.Glyph.sextant },
        .{ @as(u32, 0x1cd00), generated.Glyph.octant },
        .{ @as(u32, 0xe0b0), generated.Glyph.powerline },
    };
    inline for (cases) |case| try std.testing.expectEqual(
        case[1],
        generated.classify(case[0]).?,
    );
    try std.testing.expect(generated.classify(0x1fb3c) == null);
    try std.testing.expect(generated.classify(0xf5d0) == null);

    var family_counts = @as([6]u16, @splat(0));
    var codepoint: u32 = 0;
    while (codepoint <= 0x10ffff) : (codepoint += 1) {
        const family = generated.classify(codepoint) orelse continue;
        family_counts[@backingInt(family)] += 1;
    }
    try std.testing.expectEqualSlices(
        u16,
        &.{ 128, 32, 256, 60, 232, 18 },
        &family_counts,
    );
}

test "generated raster is bounded exact and reusable after rejection" {
    var pixels: [16 * 16]u8 = undefined;
    try std.testing.expectError(
        error.UnsupportedGlyph,
        generated.rasterize(&pixels, 16, 16, 'A'),
    );
    try std.testing.expectError(
        error.BufferTooSmall,
        generated.rasterize(pixels[0..8], 16, 16, 0x2500),
    );
    @memset(&pixels, 0xa5);
    try std.testing.expectError(
        error.InvalidMetrics,
        generated.rasterize(&pixels, 16, 16, 0x2500),
    );
    try std.testing.expect(std.mem.allEqual(u8, &pixels, 0xa5));
    for ([_]u32{
        0x2500,  0x257f,  0x2580,  0x259f,  0x2801, 0x28ff, 0x1fb00,
        0x1fb3b, 0x1cd00, 0x1cde5, 0x1fbe6, 0xe0b0, 0xe0bf, 0xe0d6,
    }) |codepoint| {
        try rasterizeTest(&pixels, 16, 16, codepoint);
        try std.testing.expect(std.mem.indexOfNone(u8, &pixels, &.{0}) != null);
    }
}

test "generated work and stroke bounds reject without mutation and permit reuse" {
    const extent = generated.max_extent_px;
    var pixels: [@as(usize, extent) * extent + 1]u8 = undefined;
    @memset(&pixels, 0xa5);
    const overflow = extent + 1;
    try std.testing.expectError(
        error.RasterTooLarge,
        generated.rasterize(&pixels, overflow, extent, 0xe0b5),
    );
    try std.testing.expect(std.mem.allEqual(u8, &pixels, 0xa5));
    try std.testing.expectError(
        error.RasterTooLarge,
        generated.rasterize(&pixels, extent, overflow, 0xe0b5),
    );
    try std.testing.expect(std.mem.allEqual(u8, &pixels, 0xa5));
    try std.testing.expectError(
        error.InvalidStroke,
        generated.rasterizeWithStroke(&pixels, 16, 16, 0x2504, .{
            .light_stroke_px = 0,
            .heavy_stroke_px = 1,
        }),
    );
    try std.testing.expect(std.mem.allEqual(u8, &pixels, 0xa5));
    try std.testing.expectError(
        error.InvalidStroke,
        generated.rasterizeWithStroke(&pixels, 16, 16, 0x2504, .{
            .light_stroke_px = 1,
            .heavy_stroke_px = overflow,
        }),
    );
    try std.testing.expect(std.mem.allEqual(u8, &pixels, 0xa5));
    try std.testing.expectError(
        error.InvalidStroke,
        generated.rasterizeWithStroke(&pixels, 16, 16, 0x2504, .{
            .light_stroke_px = 3,
            .heavy_stroke_px = 2,
        }),
    );
    try std.testing.expect(std.mem.allEqual(u8, &pixels, 0xa5));

    try rasterizeTest(&pixels, 16, 16, 0x2504);
    try rasterizeTest(&pixels, 16, 16, 0x2505);
    @memset(&pixels, 0xa5);
    try generated.rasterize(&pixels, extent, extent, 0x2588);
    try std.testing.expect(std.mem.allEqual(
        u8,
        pixels[0 .. @as(usize, extent) * extent],
        255,
    ));
    try std.testing.expectEqual(
        @as(u8, 0xa5),
        pixels[@as(usize, extent) * extent],
    );

    @memset(&pixels, 0xa5);
    try generated.rasterize(&pixels, 16, 16, 0xe0b5);
    try std.testing.expect(
        std.mem.indexOfNone(u8, pixels[0 .. 16 * 16], &.{0}) != null,
    );
    try std.testing.expectEqual(@as(u8, 0xa5), pixels[16 * 16]);
}

test "box metrics preserve factual axes scale and independent curve derivation" {
    const config = generated.BoxDrawingConfig{
        .dpi_x = .{ .numerator = 768, .denominator = 5 },
        .dpi_y = .{ .numerator = 96, .denominator = 1 },
    };
    var horizontal: [17 * 17]u8 = undefined;
    var vertical: [17 * 17]u8 = undefined;
    try generated.rasterizeBox(&horizontal, 17, 17, 0x2500, config, .{});
    try generated.rasterizeBox(&vertical, 17, 17, 0x2502, config, .{});
    try std.testing.expectEqual(@as(usize, 2), occupiedRows(&horizontal, 17));
    try std.testing.expectEqual(@as(usize, 3), occupiedColumns(&vertical, 17));

    try generated.rasterizeBox(
        &horizontal,
        17,
        17,
        0x2500,
        config,
        .{ .scale = 2 },
    );
    try generated.rasterizeBox(
        &vertical,
        17,
        17,
        0x2502,
        config,
        .{ .scale = 2 },
    );
    try std.testing.expectEqual(@as(usize, 3), occupiedRows(&horizontal, 17));
    try std.testing.expectEqual(@as(usize, 5), occupiedColumns(&vertical, 17));

    var diagonal_a: [17 * 17]u8 = undefined;
    var diagonal_b: [17 * 17]u8 = undefined;
    try generated.rasterizeBox(&diagonal_a, 17, 17, 0x2571, config, .{});
    var distinct_curve = config;
    distinct_curve.stroke_points[1] = 1.2;
    try generated.rasterizeBox(
        &diagonal_b,
        17,
        17,
        0x2571,
        distinct_curve,
        .{},
    );
    // Both direct X thicknesses ceil to three; their independently derived
    // 4× thicknesses ceil to nine and eleven and produce distinct pixels.
    try std.testing.expect(!std.mem.eql(u8, &diagonal_a, &diagonal_b));

    @memset(&horizontal, 0xa5);
    var invalid = config;
    invalid.stroke_points[0] = std.math.nan(f32);
    try std.testing.expectError(
        error.InvalidMetrics,
        generated.rasterizeBox(&horizontal, 17, 17, 0x2500, invalid, .{}),
    );
    try std.testing.expect(std.mem.allEqual(u8, &horizontal, 0xa5));
    try std.testing.expectError(
        error.InvalidMetrics,
        generated.rasterizeBox(
            &horizontal,
            17,
            17,
            0x2500,
            config,
            .{ .scale = 0 },
        ),
    );
    try std.testing.expect(std.mem.allEqual(u8, &horizontal, 0xa5));
    try std.testing.expectError(
        error.UnsupportedGlyph,
        generated.rasterizeBox(&horizontal, 17, 17, 0xe0b0, config, .{}),
    );
    try std.testing.expect(std.mem.allEqual(u8, &horizontal, 0xa5));
}

fn occupiedRows(pixels: []const u8, width: usize) usize {
    var count: usize = 0;
    var offset: usize = 0;
    while (offset < pixels.len) : (offset += width) {
        if (std.mem.indexOfNone(u8, pixels[offset..][0..width], &.{0}) != null)
            count += 1;
    }
    return count;
}

fn occupiedColumns(pixels: []const u8, width: usize) usize {
    var count: usize = 0;
    for (0..width) |x| {
        var occupied = false;
        var y: usize = 0;
        while (y < pixels.len / width) : (y += 1) {
            if (pixels[y * width + x] != 0) {
                occupied = true;
                break;
            }
        }
        if (occupied) count += 1;
    }
    return count;
}

test "generated geometry preserves representative family facts" {
    var pixels: [16 * 16]u8 = undefined;
    try rasterizeTest(&pixels, 16, 16, 0x2500);
    try std.testing.expect(std.mem.allEqual(u8, pixels[7 * 16 .. 9 * 16], 255));

    try generated.rasterize(&pixels, 16, 16, 0x2588);
    try std.testing.expect(std.mem.allEqual(u8, &pixels, 255));

    try generated.rasterize(&pixels, 16, 16, 0x2801);
    try std.testing.expect(std.mem.indexOfNone(u8, &pixels, &.{0}) != null);
    try std.testing.expect(std.mem.indexOfScalar(u8, &pixels, 0) != null);

    try generated.rasterize(&pixels, 16, 16, 0xe0b0);
    try std.testing.expect(pixels[8 * 16] == 255);
    try std.testing.expect(std.mem.indexOfScalar(u8, &pixels, 0) != null);
}

test "every classified glyph rasterizes at hostile small dimensions" {
    var codepoint: u32 = 0;
    var pixels: [17 * 17 + 1]u8 = undefined;
    while (codepoint <= 0x10ffff) : (codepoint += 1) {
        if (generated.classify(codepoint) == null) continue;
        for ([_]u16{ 1, 2, 7, 17 }) |size| {
            @memset(&pixels, 0xaa);
            try rasterizeTest(&pixels, size, size, codepoint);
            try std.testing.expectEqual(
                @as(u8, 0xaa),
                pixels[@as(usize, size) * size],
            );
        }
    }
}

fn rasterizeTest(
    pixels: []u8,
    width: u16,
    height: u16,
    codepoint: u32,
) generated.Error!void {
    if (generated.classify(codepoint) == .box) {
        return generated.rasterizeBox(
            pixels,
            width,
            height,
            codepoint,
            .{
                .dpi_x = .{ .numerator = 96, .denominator = 1 },
                .dpi_y = .{ .numerator = 96, .denominator = 1 },
            },
            .{},
        );
    }
    return generated.rasterize(pixels, width, height, codepoint);
}
