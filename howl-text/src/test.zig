//! Proves the public native text owner with deterministic licensed fonts.

const std = @import("std");
const text = @import("howl_text.zig");
const fonts = @import("test_fonts");

test "public font operations retain exact error sets" {
    const init: *const fn (
        std.mem.Allocator,
        text.Config,
    ) text.InitError!text.FontSet = &text.FontSet.init;
    const shape: *const fn (
        *text.FontSet,
        std.mem.Allocator,
        text.Text,
    ) text.ShapeError!text.Run = &text.FontSet.shape;
    const rasterize: *const fn (
        *text.FontSet,
        std.mem.Allocator,
        u8,
        u32,
        u16,
    ) text.RasterError!text.Raster = &text.FontSet.rasterize;
    try std.testing.expect(init == &text.FontSet.init);
    try std.testing.expect(shape == &text.FontSet.shape);
    try std.testing.expect(rasterize == &text.FontSet.rasterize);
}

test "font set shapes primary and ordered whole-sequence fallback" {
    const fallbacks = [_][]const u8{fonts.symbol_font};
    var set = try text.FontSet.init(std.testing.allocator, .{
        .primary = fonts.primary_font,
        .fallbacks = &fallbacks,
        .pixel_height = 18,
    });
    defer set.deinit();

    const ascii = [_]u32{ 'f', 'i' };
    const clusters = [_]u32{ 3, 3 };
    var primary = try set.shape(std.testing.allocator, .{
        .codepoints = &ascii,
        .clusters = &clusters,
        .cell_span = 2,
    });
    defer primary.deinit();
    try std.testing.expectEqual(@as(u8, 0), primary.face_index);
    try std.testing.expect(primary.glyphs.len > 0);
    try std.testing.expectEqual(@as(u32, 3), primary.glyphs[0].cluster);

    const symbol = [_]u32{0xe0b0};
    const symbol_cluster = [_]u32{9};
    var fallback = try set.shape(std.testing.allocator, .{
        .codepoints = &symbol,
        .clusters = &symbol_cluster,
        .cell_span = 1,
    });
    defer fallback.deinit();
    try std.testing.expectEqual(@as(u8, 1), fallback.face_index);

    // Only the fallback carries the explicit zero + VS1 cmap mapping.
    const variation = [_]u32{ '0', 0xfe00 };
    const variation_clusters = [_]u32{ 10, 10 };
    var variation_fallback = try set.shape(std.testing.allocator, .{
        .codepoints = &variation,
        .clusters = &variation_clusters,
        .cell_span = 1,
    });
    defer variation_fallback.deinit();
    try std.testing.expectEqual(@as(u8, 1), variation_fallback.face_index);
    try std.testing.expect(variation_fallback.glyphs.len > 0);
    for (variation_fallback.glyphs) |glyph| try std.testing.expect(glyph.id != 0);
}

test "font configuration validates every path before allocation or native access" {
    var overflow: [text.max_fallbacks + 1][]const u8 = undefined;
    @memset(&overflow, fonts.symbol_font);
    try std.testing.expectError(error.InvalidConfig, text.FontSet.init(
        std.testing.failing_allocator,
        .{
            .primary = fonts.primary_font,
            .fallbacks = &overflow,
            .pixel_height = 16,
        },
    ));
    try std.testing.expectError(error.InvalidConfig, text.FontSet.init(
        std.testing.failing_allocator,
        .{ .primary = fonts.primary_font, .pixel_height = 0 },
    ));
    try std.testing.expectError(error.InvalidConfig, text.FontSet.init(
        std.testing.failing_allocator,
        .{ .primary = "", .pixel_height = 16 },
    ));
    const empty_fallback = [_][]const u8{""};
    try std.testing.expectError(error.InvalidConfig, text.FontSet.init(
        std.testing.failing_allocator,
        .{
            .primary = fonts.primary_font,
            .fallbacks = &empty_fallback,
            .pixel_height = 16,
        },
    ));

    var too_long: [text.max_font_path_bytes + 1]u8 = undefined;
    @memset(&too_long, 'x');
    try std.testing.expectError(error.InvalidConfig, text.FontSet.init(
        std.testing.failing_allocator,
        .{ .primary = &too_long, .pixel_height = 16 },
    ));
    const long_fallback = [_][]const u8{&too_long};
    try std.testing.expectError(error.InvalidConfig, text.FontSet.init(
        std.testing.failing_allocator,
        .{
            .primary = fonts.primary_font,
            .fallbacks = &long_fallback,
            .pixel_height = 16,
        },
    ));
    var boundary: [text.max_font_path_bytes]u8 = undefined;
    @memset(&boundary, 'x');
    try std.testing.expectError(error.FontOpen, text.FontSet.init(
        std.testing.allocator,
        .{ .primary = &boundary, .pixel_height = 16 },
    ));
    const boundary_fallback = [_][]const u8{&boundary};
    try std.testing.expectError(error.FontOpen, text.FontSet.init(
        std.testing.allocator,
        .{
            .primary = fonts.primary_font,
            .fallbacks = &boundary_fallback,
            .pixel_height = 16,
        },
    ));

    var embedded_nul: [text.max_font_path_bytes]u8 = undefined;
    const ambiguous = try std.fmt.bufPrint(
        &embedded_nul,
        "{s}{c}ignored",
        .{ fonts.primary_font, @as(u8, 0) },
    );
    try std.testing.expectError(error.InvalidConfig, text.FontSet.init(
        std.testing.failing_allocator,
        .{ .primary = ambiguous, .pixel_height = 16 },
    ));
    const ambiguous_fallback = [_][]const u8{ambiguous};
    try std.testing.expectError(error.InvalidConfig, text.FontSet.init(
        std.testing.failing_allocator,
        .{
            .primary = fonts.primary_font,
            .fallbacks = &ambiguous_fallback,
            .pixel_height = 16,
        },
    ));
}

test "failed fallback loading cleans the transaction before successful reuse" {
    const invalid = [_][]const u8{"/definitely/not/a/font.ttf"};
    try std.testing.expectError(error.FontOpen, text.FontSet.init(
        std.testing.allocator,
        .{
            .primary = fonts.primary_font,
            .fallbacks = &invalid,
            .pixel_height = 16,
        },
    ));
    var set = try text.FontSet.init(std.testing.allocator, .{
        .primary = fonts.primary_font,
        .pixel_height = 16,
    });
    set.deinit();
}

test "shape rejects malformed and over-bound input before HarfBuzz" {
    var set = try text.FontSet.init(std.testing.allocator, .{
        .primary = fonts.primary_font,
        .pixel_height = 16,
    });
    defer set.deinit();
    const codepoints = [_]u32{'A'};
    try std.testing.expectError(error.InvalidText, set.shape(
        std.testing.allocator,
        .{ .codepoints = &codepoints, .clusters = &.{}, .cell_span = 1 },
    ));
    const invalid = [_]u32{0xd800};
    const cluster = [_]u32{0};
    try std.testing.expectError(error.InvalidText, set.shape(
        std.testing.allocator,
        .{ .codepoints = &invalid, .clusters = &cluster, .cell_span = 1 },
    ));
}

test "font set reports missing glyph and remains reusable" {
    const fallbacks = [_][]const u8{fonts.symbol_font};
    var set = try text.FontSet.init(std.testing.allocator, .{
        .primary = fonts.primary_font,
        .fallbacks = &fallbacks,
        .pixel_height = 16,
    });
    defer set.deinit();
    const missing = [_]u32{0x10ffff};
    const cluster = [_]u32{0};
    try std.testing.expectError(error.MissingGlyph, set.shape(std.testing.allocator, .{
        .codepoints = &missing,
        .clusters = &cluster,
        .cell_span = 1,
    }));

    const missing_variation = [_]u32{ '0', 0xfe0f };
    const variation_clusters = [_]u32{ 1, 1 };
    try std.testing.expectError(error.MissingGlyph, set.shape(std.testing.allocator, .{
        .codepoints = &missing_variation,
        .clusters = &variation_clusters,
        .cell_span = 1,
    }));
    const lone_selector = [_]u32{0xfe00};
    try std.testing.expectError(error.MissingGlyph, set.shape(std.testing.allocator, .{
        .codepoints = &lone_selector,
        .clusters = &cluster,
        .cell_span = 1,
    }));

    const valid = [_]u32{'A'};
    var run = try set.shape(std.testing.allocator, .{
        .codepoints = &valid,
        .clusters = &cluster,
        .cell_span = 1,
    });
    defer run.deinit();
    try std.testing.expect(run.glyphs.len == 1);
}

test "font set raster owns a bounded alpha mask" {
    var set = try text.FontSet.init(std.testing.allocator, .{
        .primary = fonts.primary_font,
        .pixel_height = 18,
    });
    defer set.deinit();
    const cp = [_]u32{'A'};
    const cluster = [_]u32{0};
    var run = try set.shape(std.testing.allocator, .{
        .codepoints = &cp,
        .clusters = &cluster,
        .cell_span = 1,
    });
    defer run.deinit();
    try std.testing.expectError(error.InvalidRaster, set.rasterize(
        std.testing.allocator,
        text.max_fallbacks + 1,
        run.glyphs[0].id,
        1,
    ));
    try std.testing.expectError(error.InvalidCellSpan, set.rasterize(
        std.testing.allocator,
        run.face_index,
        run.glyphs[0].id,
        0,
    ));
    try std.testing.expectError(error.InvalidCellSpan, set.rasterize(
        std.testing.allocator,
        run.face_index,
        run.glyphs[0].id,
        std.math.maxInt(u16),
    ));
    try std.testing.expectError(error.InvalidRaster, set.rasterize(
        std.testing.allocator,
        run.face_index,
        0,
        1,
    ));
    var raster = try set.rasterize(
        std.testing.allocator,
        run.face_index,
        run.glyphs[0].id,
        1,
    );
    defer raster.deinit();
    try std.testing.expectEqual(
        @as(usize, raster.width) * raster.height,
        raster.pixels.len,
    );
    try std.testing.expect(raster.pixels.len <= text.max_raster_bytes);
    var has_partial_alpha = false;
    for (raster.pixels) |alpha| {
        if (alpha > 0 and alpha < 255) {
            has_partial_alpha = true;
            break;
        }
    }
    try std.testing.expect(has_partial_alpha);
}

test "font metrics use native lines and bitmap fonts use bounded fallbacks" {
    var scalable = try text.FontSet.init(std.testing.allocator, .{
        .primary = fonts.primary_font,
        .pixel_height = 18,
    });
    defer scalable.deinit();
    try std.testing.expectEqual(@as(u16, 25), scalable.metrics.cell_height);
    try std.testing.expectEqual(@as(u16, 20), scalable.metrics.baseline);
    try std.testing.expectEqual(@as(u16, 22), scalable.metrics.underline_y);
    try std.testing.expectEqual(@as(u16, 1), scalable.metrics.underline_height);
    try std.testing.expectEqual(@as(u16, 14), scalable.metrics.strike_y);
    try std.testing.expectEqual(@as(u16, 1), scalable.metrics.strike_height);
    try expectMetricsInsideCell(scalable.metrics);

    var ascii_codepoint: u32 = 32;
    while (ascii_codepoint < 127) : (ascii_codepoint += 1) {
        var run = try scalable.shape(std.testing.allocator, .{
            .codepoints = &.{ascii_codepoint},
            .clusters = &.{0},
            .cell_span = 1,
        });
        defer run.deinit();
        try std.testing.expect(run.glyphs.len > 0);
        for (run.glyphs) |glyph|
            try std.testing.expect(
                ceilPositive26Dot6(glyph.x_advance) <=
                    scalable.metrics.cell_width,
            );
    }

    var underscore_run = try scalable.shape(std.testing.allocator, .{
        .codepoints = &.{'_'},
        .clusters = &.{0},
        .cell_span = 1,
    });
    defer underscore_run.deinit();
    var underscore = try scalable.rasterize(
        std.testing.allocator,
        underscore_run.face_index,
        underscore_run.glyphs[0].id,
        1,
    );
    defer underscore.deinit();
    const underscore_top =
        @as(i32, scalable.metrics.baseline) - underscore.top;
    try std.testing.expect(underscore_top >= 0);
    try std.testing.expect(
        underscore_top + underscore.height <= scalable.metrics.cell_height,
    );

    var bitmap = try text.FontSet.init(std.testing.allocator, .{
        .primary = fonts.mono_font,
        .pixel_height = 16,
    });
    defer bitmap.deinit();
    try std.testing.expectEqual(@as(u16, 8), bitmap.metrics.cell_width);
    try std.testing.expectEqual(@as(u16, 16), bitmap.metrics.cell_height);
    try std.testing.expectEqual(@as(u16, 13), bitmap.metrics.baseline);
    try std.testing.expectEqual(@as(u16, 14), bitmap.metrics.underline_y);
    try std.testing.expectEqual(@as(u16, 1), bitmap.metrics.underline_height);
    try std.testing.expectEqual(@as(u16, 8), bitmap.metrics.strike_y);
    try std.testing.expectEqual(@as(u16, 1), bitmap.metrics.strike_height);
    try expectMetricsInsideCell(bitmap.metrics);

    const codepoint = [_]u32{'A'};
    const cluster = [_]u32{0};
    var run = try bitmap.shape(std.testing.allocator, .{
        .codepoints = &codepoint,
        .clusters = &cluster,
        .cell_span = 1,
    });
    defer run.deinit();
    var raster = try bitmap.rasterize(
        std.testing.allocator,
        run.face_index,
        run.glyphs[0].id,
        1,
    );
    defer raster.deinit();
    try std.testing.expectEqual(@as(u16, 8), raster.width);
    try std.testing.expectEqual(@as(u16, 16), raster.height);
    try std.testing.expect(std.mem.indexOfScalar(u8, raster.pixels, 255) != null);
    for (raster.pixels) |alpha| try std.testing.expect(alpha == 0 or alpha == 255);
}

test "terminal monospace cell origins follow one ordinary ASCII advance" {
    var set = try text.FontSet.init(std.testing.allocator, .{
        .primary = fonts.symbol_font,
        .pixel_height = 18,
    });
    defer set.deinit();
    try std.testing.expectEqual(@as(u16, 9), set.metrics.cell_width);

    const prompt = "bash-5.3$";
    var previous_origin: ?u32 = null;
    for (prompt, 0..) |byte, column| {
        const codepoints = [_]u32{byte};
        const clusters = [_]u32{0};
        var run = try set.shape(std.testing.allocator, .{
            .codepoints = &codepoints,
            .clusters = &clusters,
            .cell_span = 1,
        });
        defer run.deinit();
        try std.testing.expectEqual(@as(usize, 1), run.glyphs.len);
        try std.testing.expectEqual(
            set.metrics.cell_width,
            ceilPositive26Dot6(run.glyphs[0].x_advance),
        );

        const origin: u32 = @as(u32, @intCast(column)) *
            set.metrics.cell_width;
        if (previous_origin) |previous|
            try std.testing.expectEqual(
                @as(u32, set.metrics.cell_width),
                origin - previous,
            );
        previous_origin = origin;
    }
}

test "oversized Nerd glyph fits its assigned cell without widening the grid" {
    var set = try text.FontSet.init(std.testing.allocator, .{
        .primary = fonts.symbol_font,
        .pixel_height = 18,
    });
    defer set.deinit();

    const arch = [_]u32{0xf303};
    var run = try set.shape(std.testing.allocator, .{
        .codepoints = &arch,
        .clusters = &.{0},
        .cell_span = 1,
    });
    defer run.deinit();
    try std.testing.expectEqual(@as(usize, 1), run.glyphs.len);
    try std.testing.expectEqual(
        @as(i32, set.metrics.cell_width) * 64,
        run.glyphs[0].x_advance,
    );
    var raster = try set.rasterize(
        std.testing.allocator,
        run.face_index,
        run.glyphs[0].id,
        run.cell_span,
    );
    defer raster.deinit();
    try std.testing.expect(raster.width <= set.metrics.cell_width);
    try std.testing.expect(raster.left >= 0);
    try std.testing.expect(
        @as(u32, @intCast(raster.left)) + raster.width <=
            set.metrics.cell_width,
    );

    const ascii = [_]u32{'A'};
    var ascii_run = try set.shape(std.testing.allocator, .{
        .codepoints = &ascii,
        .clusters = &.{0},
        .cell_span = 1,
    });
    defer ascii_run.deinit();
    try std.testing.expectEqual(
        @as(i32, set.metrics.cell_width) * 64,
        ascii_run.glyphs[0].x_advance,
    );
}

test "metric extraction is stable across owner reuse" {
    var first = try text.FontSet.init(std.testing.allocator, .{
        .primary = fonts.primary_font,
        .pixel_height = 18,
    });
    const expected = first.metrics;
    first.deinit();

    var reused = try text.FontSet.init(std.testing.allocator, .{
        .primary = fonts.primary_font,
        .pixel_height = 18,
    });
    defer reused.deinit();
    try std.testing.expectEqualDeep(expected, reused.metrics);
}

test "empty FreeType glyph produces an owned empty raster" {
    var set = try text.FontSet.init(std.testing.allocator, .{
        .primary = fonts.primary_font,
        .pixel_height = 18,
    });
    defer set.deinit();
    const codepoint = [_]u32{' '};
    const cluster = [_]u32{0};
    var run = try set.shape(std.testing.allocator, .{
        .codepoints = &codepoint,
        .clusters = &cluster,
        .cell_span = 1,
    });
    defer run.deinit();
    var raster = try set.rasterize(
        std.testing.allocator,
        run.face_index,
        run.glyphs[0].id,
        1,
    );
    defer raster.deinit();
    try std.testing.expectEqual(@as(usize, 0), raster.pixels.len);
}

fn expectMetricsInsideCell(metrics: text.Metrics) !void {
    try std.testing.expect(metrics.cell_width > 0);
    try std.testing.expect(metrics.cell_height > 0);
    try std.testing.expect(metrics.baseline < metrics.cell_height);
    try std.testing.expect(metrics.underline_height > 0);
    try std.testing.expect(
        @as(u32, metrics.underline_y) + metrics.underline_height <=
            metrics.cell_height,
    );
    try std.testing.expect(metrics.strike_height > 0);
    try std.testing.expect(
        @as(u32, metrics.strike_y) + metrics.strike_height <=
            metrics.cell_height,
    );
}

fn ceilPositive26Dot6(value: i32) u16 {
    std.debug.assert(value > 0);
    return @intCast(@divTrunc(value + 63, 64));
}

test "font initialization releases every allocation failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        initFontSet,
        .{},
    );
}

fn initFontSet(allocator: std.mem.Allocator) !void {
    const fallbacks = [_][]const u8{fonts.symbol_font};
    var set = try text.FontSet.init(allocator, .{
        .primary = fonts.primary_font,
        .fallbacks = &fallbacks,
        .pixel_height = 16,
    });
    set.deinit();
}

test "shape and raster allocation failures preserve reusable native faces" {
    var set = try text.FontSet.init(std.testing.allocator, .{
        .primary = fonts.primary_font,
        .pixel_height = 16,
    });
    defer set.deinit();
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        shapeAllocation,
        .{&set},
    );

    const codepoint = [_]u32{'A'};
    const cluster = [_]u32{0};
    var run = try set.shape(std.testing.allocator, .{
        .codepoints = &codepoint,
        .clusters = &cluster,
        .cell_span = 1,
    });
    defer run.deinit();
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        rasterAllocation,
        .{ &set, run.glyphs[0].id },
    );
    var raster = try set.rasterize(
        std.testing.allocator,
        0,
        run.glyphs[0].id,
        1,
    );
    raster.deinit();

    var symbols = try text.FontSet.init(std.testing.allocator, .{
        .primary = fonts.symbol_font,
        .pixel_height = 18,
    });
    defer symbols.deinit();
    var icon = try symbols.shape(std.testing.allocator, .{
        .codepoints = &.{0xf303},
        .clusters = &.{0},
        .cell_span = 1,
    });
    defer icon.deinit();
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        rasterAllocation,
        .{ &symbols, icon.glyphs[0].id },
    );
    var reused = try symbols.rasterize(
        std.testing.allocator,
        icon.face_index,
        icon.glyphs[0].id,
        1,
    );
    reused.deinit();
}

fn shapeAllocation(allocator: std.mem.Allocator, set: *text.FontSet) !void {
    const codepoint = [_]u32{'A'};
    const cluster = [_]u32{0};
    var run = try set.shape(allocator, .{
        .codepoints = &codepoint,
        .clusters = &cluster,
        .cell_span = 1,
    });
    run.deinit();
}

fn rasterAllocation(
    allocator: std.mem.Allocator,
    set: *text.FontSet,
    glyph_id: u32,
) !void {
    var raster = try set.rasterize(allocator, 0, glyph_id, 1);
    raster.deinit();
}

test "generated families classify exact retained ranges and reject neighbors" {
    const cases = .{
        .{ @as(u32, 0x2500), text.GeneratedGlyph.box },
        .{ @as(u32, 0x2580), text.GeneratedGlyph.block },
        .{ @as(u32, 0x2800), text.GeneratedGlyph.braille },
        .{ @as(u32, 0x1fb00), text.GeneratedGlyph.sextant },
        .{ @as(u32, 0x1cd00), text.GeneratedGlyph.octant },
        .{ @as(u32, 0xe0b0), text.GeneratedGlyph.powerline },
    };
    inline for (cases) |case| try std.testing.expectEqual(
        case[1],
        text.classifyGenerated(case[0]).?,
    );
    try std.testing.expect(text.classifyGenerated(0x1fb3c) == null);
    try std.testing.expect(text.classifyGenerated(0xf5d0) == null);

    var family_counts = [_]u16{0} ** 6;
    var codepoint: u32 = 0;
    while (codepoint <= 0x10ffff) : (codepoint += 1) {
        const family = text.classifyGenerated(codepoint) orelse continue;
        family_counts[@intFromEnum(family)] += 1;
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
        text.rasterizeGenerated(&pixels, 16, 16, 'A'),
    );
    try std.testing.expectError(
        error.BufferTooSmall,
        text.rasterizeGenerated(pixels[0..8], 16, 16, 0x2500),
    );
    for ([_]u32{ 0x2500, 0x257f, 0x2580, 0x259f, 0x2801, 0x28ff, 0x1fb00, 0x1fb3b, 0x1cd00, 0x1cde5, 0x1fbe6, 0xe0b0, 0xe0bf, 0xe0d6 }) |codepoint| {
        try text.rasterizeGenerated(&pixels, 16, 16, codepoint);
        try std.testing.expect(std.mem.indexOfNone(u8, &pixels, &.{0}) != null);
    }
}

test "generated work and stroke bounds reject without mutation and permit reuse" {
    const extent = text.max_generated_extent_px;
    var pixels: [@as(usize, extent) * extent + 1]u8 = undefined;
    @memset(&pixels, 0xa5);
    const overflow = @as(u16, text.max_generated_extent_px) + 1;
    try std.testing.expectError(
        error.RasterTooLarge,
        text.rasterizeGenerated(&pixels, overflow, extent, 0xe0b5),
    );
    try std.testing.expect(std.mem.allEqual(u8, &pixels, 0xa5));
    try std.testing.expectError(
        error.RasterTooLarge,
        text.rasterizeGenerated(&pixels, extent, overflow, 0xe0b5),
    );
    try std.testing.expect(std.mem.allEqual(u8, &pixels, 0xa5));
    try std.testing.expectError(
        error.InvalidStroke,
        text.rasterizeGeneratedWithStroke(&pixels, 16, 16, 0x2504, .{
            .light_stroke_px = 0,
            .heavy_stroke_px = 1,
        }),
    );
    try std.testing.expect(std.mem.allEqual(u8, &pixels, 0xa5));
    try std.testing.expectError(
        error.InvalidStroke,
        text.rasterizeGeneratedWithStroke(&pixels, 16, 16, 0x2504, .{
            .light_stroke_px = 1,
            .heavy_stroke_px = overflow,
        }),
    );
    try std.testing.expect(std.mem.allEqual(u8, &pixels, 0xa5));
    try std.testing.expectError(
        error.InvalidStroke,
        text.rasterizeGeneratedWithStroke(&pixels, 16, 16, 0x2504, .{
            .light_stroke_px = 3,
            .heavy_stroke_px = 2,
        }),
    );
    try std.testing.expect(std.mem.allEqual(u8, &pixels, 0xa5));

    try text.rasterizeGeneratedWithStroke(
        &pixels,
        16,
        16,
        0x2504,
        .{
            .light_stroke_px = 2,
            .heavy_stroke_px = 2,
        },
    );
    try text.rasterizeGeneratedWithStroke(
        &pixels,
        16,
        16,
        0x2505,
        .{
            .light_stroke_px = 2,
            .heavy_stroke_px = 4,
        },
    );
    @memset(&pixels, 0xa5);
    try text.rasterizeGenerated(
        &pixels,
        extent,
        extent,
        0x2588,
    );
    try std.testing.expect(std.mem.allEqual(u8, pixels[0 .. @as(usize, extent) * extent], 255));
    try std.testing.expectEqual(@as(u8, 0xa5), pixels[@as(usize, extent) * extent]);

    @memset(&pixels, 0xa5);
    try text.rasterizeGenerated(&pixels, 16, 16, 0xe0b5);
    try std.testing.expect(std.mem.indexOfNone(u8, pixels[0 .. 16 * 16], &.{0}) != null);
    try std.testing.expectEqual(@as(u8, 0xa5), pixels[16 * 16]);
}

test "generated geometry preserves representative family facts" {
    var pixels: [16 * 16]u8 = undefined;
    try text.rasterizeGenerated(&pixels, 16, 16, 0x2500);
    try std.testing.expect(std.mem.allEqual(u8, pixels[7 * 16 .. 9 * 16], 255));

    try text.rasterizeGenerated(&pixels, 16, 16, 0x2588);
    try std.testing.expect(std.mem.allEqual(u8, &pixels, 255));

    try text.rasterizeGenerated(&pixels, 16, 16, 0x2801);
    try std.testing.expect(std.mem.indexOfNone(u8, &pixels, &.{0}) != null);
    try std.testing.expect(std.mem.indexOfScalar(u8, &pixels, 0) != null);

    try text.rasterizeGenerated(&pixels, 16, 16, 0xe0b0);
    try std.testing.expect(pixels[8 * 16] == 255);
    try std.testing.expect(std.mem.indexOfScalar(u8, &pixels, 0) != null);
}

test "every classified glyph rasterizes at hostile small dimensions" {
    var codepoint: u32 = 0;
    var pixels: [17 * 17 + 1]u8 = undefined;
    while (codepoint <= 0x10ffff) : (codepoint += 1) {
        if (text.classifyGenerated(codepoint) == null) continue;
        for ([_]u16{ 1, 2, 7, 17 }) |size| {
            @memset(&pixels, 0xaa);
            try text.rasterizeGenerated(&pixels, size, size, codepoint);
            try std.testing.expectEqual(@as(u8, 0xaa), pixels[@as(usize, size) * size]);
        }
    }
}
