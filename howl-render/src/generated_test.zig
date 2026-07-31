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
        .{ @as(u32, 0xee00), generated.Glyph.progress },
    };
    inline for (cases) |case| try std.testing.expectEqual(
        case[1],
        generated.classify(case[0]).?,
    );
    try std.testing.expect(generated.classify(0x1fb3c) == null);
    try std.testing.expect(generated.classify(0xedff) == null);
    try std.testing.expect(generated.classify(0xee0c) == null);
    try std.testing.expect(generated.classify(0xf5d0) == null);

    var family_counts = @as([7]u16, @splat(0));
    var codepoint: u32 = 0;
    while (codepoint <= 0x10ffff) : (codepoint += 1) {
        const family = generated.classify(codepoint) orelse continue;
        family_counts[@backingInt(family)] += 1;
    }
    try std.testing.expectEqualSlices(
        u16,
        &.{ 128, 32, 256, 60, 232, 18, 12 },
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
    try generated.rasterizePowerline(
        &pixels,
        16,
        16,
        0xe0b5,
        .{
            .dpi_x = .{ .numerator = 96, .denominator = 1 },
            .dpi_y = .{ .numerator = 96, .denominator = 1 },
        },
        .{},
    );
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

test "Powerline raster matches Kitty endpoints across factual metric changes" {
    const config = generated.BoxDrawingConfig{
        .dpi_x = .{ .numerator = 96, .denominator = 1 },
        .dpi_y = .{ .numerator = 96, .denominator = 1 },
    };
    const cases = .{
        .{ @as(u32, 0xe0b0), @as(u64, 0x512f830677c1bfd5), Edges{
            .left = 20,
            .right = 2,
            .top = 1,
            .bottom = 1,
        } },
        .{ @as(u32, 0xe0b1), @as(u64, 0xae0ba8cb9f9c5670), Edges{
            .left = 5,
            .right = 5,
            .top = 2,
            .bottom = 2,
        } },
        .{ @as(u32, 0xe0b4), @as(u64, 0xc63a27a5d963eba2), Edges{
            .left = 20,
            .right = 10,
            .top = 4,
            .bottom = 4,
        } },
    };
    var pixels: [8 * 20]u8 = undefined;
    inline for (cases) |case| {
        if (case[0] == 0xe0b1)
            try generated.rasterizePowerline(
                &pixels,
                8,
                20,
                case[0],
                config,
                .{},
            )
        else
            try generated.rasterize(&pixels, 8, 20, case[0]);
        try std.testing.expectEqual(
            case[1],
            std.hash.Wyhash.hash(0, &pixels),
        );
        try std.testing.expectEqualDeep(
            case[2],
            edgeOccupancy(&pixels, 8, 20),
        );
    }

    var unit: [7 * 17]u8 = undefined;
    var integer: [7 * 17]u8 = undefined;
    var fractional: [7 * 17]u8 = undefined;
    try generated.rasterizePowerline(&unit, 7, 17, 0xe0b1, config, .{});
    try generated.rasterizePowerline(
        &integer,
        7,
        17,
        0xe0b1,
        config,
        .{ .scale = 2 },
    );
    try generated.rasterizePowerline(
        &fractional,
        7,
        17,
        0xe0b1,
        config,
        .{ .scale = 3, .subscale_n = 1, .subscale_d = 2 },
    );
    try std.testing.expectEqual(
        @as(u64, 0x64e134e6f01919f9),
        std.hash.Wyhash.hash(0, &unit),
    );
    try std.testing.expectEqual(
        @as(u64, 0xd3ae752e2a69d68d),
        std.hash.Wyhash.hash(0, &integer),
    );
    try std.testing.expectEqual(
        @as(u64, 0x8733d93762f7e1a9),
        std.hash.Wyhash.hash(0, &fractional),
    );

    var asymmetric = config;
    asymmetric.dpi_x = .{ .numerator = 768, .denominator = 5 };
    var x_dpi: [13 * 20]u8 = undefined;
    try generated.rasterizePowerline(
        &x_dpi,
        13,
        20,
        0xe0b1,
        asymmetric,
        .{},
    );
    try std.testing.expectEqual(
        @as(u64, 0xd9d9e3e73f9d9fc6),
        std.hash.Wyhash.hash(0, &x_dpi),
    );
}

test "Powerline metric rejection is transactional and storage is reusable" {
    const config = generated.BoxDrawingConfig{
        .dpi_x = .{ .numerator = 96, .denominator = 1 },
        .dpi_y = .{ .numerator = 96, .denominator = 1 },
    };
    var pixels: [8 * 20]u8 = @splat(0xa5);
    var invalid = config;
    invalid.stroke_points[1] = std.math.nan(f32);
    try std.testing.expectError(
        error.InvalidMetrics,
        generated.rasterizePowerline(
            &pixels,
            8,
            20,
            0xe0b1,
            invalid,
            .{},
        ),
    );
    try std.testing.expect(std.mem.allEqual(u8, &pixels, 0xa5));
    for ([_]u32{ 0xe0b1, 0xe0b3, 0xe0b5, 0xe0b7, 0xe0b9, 0xe0bb, 0xe0bd, 0xe0bf }) |codepoint| {
        try std.testing.expectError(
            error.InvalidMetrics,
            generated.rasterize(&pixels, 8, 20, codepoint),
        );
        try std.testing.expect(std.mem.allEqual(u8, &pixels, 0xa5));
    }
    try std.testing.expectError(
        error.InvalidMetrics,
        generated.rasterize(&pixels, 8, 20, 0xe0b1),
    );
    try std.testing.expect(std.mem.allEqual(u8, &pixels, 0xa5));
    try std.testing.expectError(
        error.UnsupportedGlyph,
        generated.rasterizePowerline(
            &pixels,
            8,
            20,
            0xe0b0,
            config,
            .{},
        ),
    );
    try std.testing.expect(std.mem.allEqual(u8, &pixels, 0xa5));
    try std.testing.expectError(
        error.UnsupportedGlyph,
        generated.rasterizePowerline(
            &pixels,
            8,
            20,
            0xe0b2,
            config,
            .{},
        ),
    );
    try std.testing.expect(std.mem.allEqual(u8, &pixels, 0xa5));
    try std.testing.expectError(
        error.UnsupportedGlyph,
        generated.rasterizePowerline(
            &pixels,
            8,
            20,
            0xe0b4,
            config,
            .{},
        ),
    );
    try std.testing.expect(std.mem.allEqual(u8, &pixels, 0xa5));
    try std.testing.expectError(
        error.InvalidMetrics,
        generated.rasterizePowerline(
            &pixels,
            8,
            20,
            0xe0b1,
            config,
            .{ .scale = 0 },
        ),
    );
    try std.testing.expect(std.mem.allEqual(u8, &pixels, 0xa5));
    try std.testing.expectError(
        error.BufferTooSmall,
        generated.rasterizePowerline(
            pixels[0 .. pixels.len - 1],
            8,
            20,
            0xe0b1,
            config,
            .{},
        ),
    );
    try std.testing.expect(std.mem.allEqual(u8, &pixels, 0xa5));
    try generated.rasterizePowerline(
        &pixels,
        8,
        20,
        0xe0b1,
        config,
        .{},
    );
    try std.testing.expectEqual(
        @as(u64, 0xae0ba8cb9f9c5670),
        std.hash.Wyhash.hash(0, &pixels),
    );
}

test "remaining Powerline family uses exact metric ownership" {
    const config = generated.BoxDrawingConfig{
        .dpi_x = .{ .numerator = 768, .denominator = 5 },
        .dpi_y = .{ .numerator = 96, .denominator = 1 },
    };
    var pixels: [13 * 20]u8 = undefined;
    for ([_]u32{ 0xe0b1, 0xe0b3, 0xe0b5, 0xe0b7, 0xe0b9, 0xe0bb, 0xe0bd, 0xe0bf }) |codepoint| {
        try generated.rasterizePowerline(
            &pixels,
            13,
            20,
            codepoint,
            config,
            .{},
        );
        try std.testing.expect(std.mem.indexOfNone(u8, &pixels, &.{0}) != null);
    }
    for ([_]u32{ 0xe0b0, 0xe0b2, 0xe0b4, 0xe0b6, 0xe0b8, 0xe0ba, 0xe0bc, 0xe0be }) |codepoint| {
        try generated.rasterize(&pixels, 13, 20, codepoint);
        const first = std.hash.Wyhash.hash(0, &pixels);
        try generated.rasterize(&pixels, 13, 20, codepoint);
        try std.testing.expectEqual(first, std.hash.Wyhash.hash(0, &pixels));
        try std.testing.expectError(
            error.UnsupportedGlyph,
            generated.rasterizePowerline(
                &pixels,
                13,
                20,
                codepoint,
                config,
                .{},
            ),
        );
    }
}

test "rounded Powerline keeps floating width separate from integer gap" {
    // Kitty level one at 96 DPI is exactly 4/3 pixels: the curve uses that
    // floating width while its inset gap uses ceil(4/3) == 2.
    const config = generated.BoxDrawingConfig{
        .dpi_x = .{ .numerator = 96, .denominator = 1 },
        .dpi_y = .{ .numerator = 96, .denominator = 1 },
    };
    var left: [8 * 20]u8 = undefined;
    var right: [8 * 20]u8 = undefined;
    try generated.rasterizePowerline(&left, 8, 20, 0xe0b5, config, .{});
    try generated.rasterizePowerline(&right, 8, 20, 0xe0b7, config, .{});
    try std.testing.expectEqual(
        @as(u64, 0xb8bfbc71f33fd1af),
        std.hash.Wyhash.hash(0, &left),
    );
    try std.testing.expectEqual(
        @as(u64, 0x503f8e79ede8dbe3),
        std.hash.Wyhash.hash(0, &right),
    );
}

test "Fira progress and spinner family matches Kitty exact hashes" {
    const config = generated.BoxDrawingConfig{
        .dpi_x = .{ .numerator = 96, .denominator = 1 },
        .dpi_y = .{ .numerator = 96, .denominator = 1 },
    };
    const hashes = [_]u64{
        0x4fc1951496c78a70,
        0xd8baa1dab8f48cc4,
        0x1779877b71b2f248,
        0xef5d857c0baccd0c,
        0xb9c5a0cccce80549,
        0x67914e1d877caa6b,
        0xd1334dff159975a8,
        0xca3ab95c1d542679,
        0xe9df48bc29852b24,
        0x5ddac9f65c975161,
        0xcf7ce5e5f4b66a54,
        0xcccc21c2226ce5d4,
    };
    var pixels: [8 * 20]u8 = undefined;
    for (hashes, 0..) |hash, index| {
        try generated.rasterizeProgress(
            &pixels,
            8,
            20,
            @intCast(0xee00 + index),
            config,
            .{},
        );
        try std.testing.expectEqual(hash, std.hash.Wyhash.hash(0, &pixels));
    }
}

test "progress bars use Kitty screen-axis DPI naming" {
    const config = generated.BoxDrawingConfig{
        .dpi_x = .{ .numerator = 768, .denominator = 5 },
        .dpi_y = .{ .numerator = 96, .denominator = 1 },
    };
    var pixels: [16 * 20]u8 = undefined;
    try generated.rasterizeProgress(
        &pixels,
        16,
        20,
        0xee00,
        config,
        .{},
    );

    // Kitty derives h=3 from X DPI and v=2 from Y DPI, then its frame
    // includes the boundary pixel: four complete top rows and three left
    // columns below them.
    for (0..4) |row|
        try std.testing.expectEqualSlices(
            u8,
            &@as([16]u8, @splat(255)),
            pixels[row * 16 ..][0..16],
        );
    for (4..16) |row| {
        try std.testing.expectEqualSlices(
            u8,
            &@as([3]u8, @splat(255)),
            pixels[row * 16 ..][0..3],
        );
        try std.testing.expectEqual(@as(u8, 0), pixels[row * 16 + 3]);
    }
}

test "Fira progress invalid metrics and output reject transactionally" {
    var pixels: [8 * 20]u8 = @splat(0xa5);
    var invalid = generated.BoxDrawingConfig{
        .dpi_x = .{ .numerator = 96, .denominator = 1 },
        .dpi_y = .{ .numerator = 96, .denominator = 1 },
    };
    invalid.stroke_points[1] = std.math.nan(f32);
    try std.testing.expectError(
        error.InvalidMetrics,
        generated.rasterizeProgress(&pixels, 8, 20, 0xee00, invalid, .{}),
    );
    try std.testing.expect(std.mem.allEqual(u8, &pixels, 0xa5));
    var bounded: [@as(usize, generated.max_extent_px) + 1]u8 = @splat(0xa5);
    try std.testing.expectError(
        error.RasterTooLarge,
        generated.rasterizeProgress(
            &bounded,
            generated.max_extent_px + 1,
            1,
            0xee00,
            .{
                .dpi_x = .{ .numerator = 96, .denominator = 1 },
                .dpi_y = .{ .numerator = 96, .denominator = 1 },
            },
            .{},
        ),
    );
    try std.testing.expect(std.mem.allEqual(u8, &bounded, 0xa5));
    try std.testing.expectError(
        error.BufferTooSmall,
        generated.rasterizeProgress(
            pixels[0 .. pixels.len - 1],
            8,
            20,
            0xee06,
            .{
                .dpi_x = .{ .numerator = 96, .denominator = 1 },
                .dpi_y = .{ .numerator = 96, .denominator = 1 },
            },
            .{},
        ),
    );
    try std.testing.expect(std.mem.allEqual(u8, &pixels, 0xa5));
    try std.testing.expectError(
        error.UnsupportedGlyph,
        generated.rasterizeProgress(
            &pixels,
            8,
            20,
            0xf5d0,
            .{
                .dpi_x = .{ .numerator = 96, .denominator = 1 },
                .dpi_y = .{ .numerator = 96, .denominator = 1 },
            },
            .{},
        ),
    );
    try std.testing.expect(std.mem.allEqual(u8, &pixels, 0xa5));
}

const Edges = struct {
    left: u16,
    right: u16,
    top: u16,
    bottom: u16,
};

fn edgeOccupancy(
    pixels: []const u8,
    width: u16,
    height: u16,
) Edges {
    var result = Edges{ .left = 0, .right = 0, .top = 0, .bottom = 0 };
    for (0..height) |y| {
        if (pixels[y * width] != 0) result.left += 1;
        if (pixels[y * width + width - 1] != 0) result.right += 1;
    }
    for (0..width) |x| {
        if (pixels[x] != 0) result.top += 1;
        if (pixels[@as(usize, height - 1) * width + x] != 0)
            result.bottom += 1;
    }
    return result;
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
    const family = generated.classify(codepoint);
    const config = generated.BoxDrawingConfig{
        .dpi_x = .{ .numerator = 96, .denominator = 1 },
        .dpi_y = .{ .numerator = 96, .denominator = 1 },
    };
    if (family == .box)
        return generated.rasterizeBox(
            pixels,
            width,
            height,
            codepoint,
            config,
            .{},
        );
    if (switch (codepoint) {
        0xe0b1, 0xe0b3, 0xe0b5, 0xe0b7, 0xe0b9, 0xe0bb, 0xe0bd, 0xe0bf => true,
        else => false,
    })
        return generated.rasterizePowerline(
            pixels,
            width,
            height,
            codepoint,
            config,
            .{},
        );
    if (family == .progress)
        return generated.rasterizeProgress(
            pixels,
            width,
            height,
            codepoint,
            config,
            .{},
        );
    return generated.rasterize(pixels, width, height, codepoint);
}
