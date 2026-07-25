//! Proves selected native text capability with deterministic licensed fonts.

const std = @import("std");
const text = @import("howl_render").text;
const fonts = @import("test_fonts");

test "public font operations retain exact error sets" {
    const init: *const fn (
        std.mem.Allocator,
        text.Config,
    ) text.InitError!text.FontSet = &text.FontSet.init;
    const shape: *const fn (
        *text.FontSet,
        *text.ShapeBuffer,
        text.Text,
        []text.Glyph,
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
    var primary = try shapeOwned(&set, std.testing.allocator, .{
        .codepoints = &ascii,
        .clusters = &clusters,
    });
    defer primary.deinit();
    try std.testing.expectEqual(@as(u8, 0), primary.face_index);
    try std.testing.expect(primary.glyphs.len > 0);
    try std.testing.expectEqual(@as(u32, 3), primary.glyphs[0].cluster);

    const symbol = [_]u32{0xe0b0};
    const symbol_cluster = [_]u32{9};
    var fallback = try shapeOwned(&set, std.testing.allocator, .{
        .codepoints = &symbol,
        .clusters = &symbol_cluster,
    });
    defer fallback.deinit();
    try std.testing.expectEqual(@as(u8, 1), fallback.face_index);

    // Only the fallback carries the explicit zero + VS1 cmap mapping.
    const variation = [_]u32{ '0', 0xfe00 };
    const variation_clusters = [_]u32{ 10, 10 };
    var variation_fallback = try shapeOwned(&set, std.testing.allocator, .{
        .codepoints = &variation,
        .clusters = &variation_clusters,
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
    try std.testing.expectError(error.InvalidText, shapeOwned(
        &set,
        std.testing.allocator,
        .{ .codepoints = &codepoints, .clusters = &.{} },
    ));
    const invalid = [_]u32{0xd800};
    const cluster = [_]u32{0};
    try std.testing.expectError(error.InvalidText, shapeOwned(
        &set,
        std.testing.allocator,
        .{ .codepoints = &invalid, .clusters = &cluster },
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
    try std.testing.expectError(error.MissingGlyph, shapeOwned(&set, std.testing.allocator, .{
        .codepoints = &missing,
        .clusters = &cluster,
    }));

    const missing_variation = [_]u32{ '0', 0xfe0f };
    const variation_clusters = [_]u32{ 1, 1 };
    try std.testing.expectError(error.MissingGlyph, shapeOwned(&set, std.testing.allocator, .{
        .codepoints = &missing_variation,
        .clusters = &variation_clusters,
    }));
    const lone_selector = [_]u32{0xfe00};
    try std.testing.expectError(error.MissingGlyph, shapeOwned(&set, std.testing.allocator, .{
        .codepoints = &lone_selector,
        .clusters = &cluster,
    }));

    const valid = [_]u32{'A'};
    var run = try shapeOwned(&set, std.testing.allocator, .{
        .codepoints = &valid,
        .clusters = &cluster,
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
    var run = try shapeOwned(&set, std.testing.allocator, .{
        .codepoints = &cp,
        .clusters = &cluster,
    });
    defer run.deinit();
    try std.testing.expectError(error.InvalidRaster, set.rasterize(
        std.testing.allocator,
        text.max_fallbacks + 1,
        run.glyphs[0].id,
        1,
    ));
    try std.testing.expectError(error.InvalidWidth, set.rasterize(
        std.testing.allocator,
        run.face_index,
        run.glyphs[0].id,
        0,
    ));
    try std.testing.expectError(error.InvalidRaster, set.rasterize(
        std.testing.allocator,
        run.face_index,
        0,
        set.metrics.advance_width,
    ));
    var raster = try set.rasterize(
        std.testing.allocator,
        run.face_index,
        run.glyphs[0].id,
        set.metrics.advance_width,
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
    try std.testing.expectEqual(@as(u16, 25), scalable.metrics.line_height);
    try std.testing.expectEqual(@as(u16, 20), scalable.metrics.baseline);
    try std.testing.expectEqual(@as(u16, 22), scalable.metrics.underline_y);
    try std.testing.expectEqual(@as(u16, 1), scalable.metrics.underline_height);
    try std.testing.expectEqual(@as(u16, 14), scalable.metrics.strike_y);
    try std.testing.expectEqual(@as(u16, 1), scalable.metrics.strike_height);
    try expectMetricsValid(scalable.metrics);

    var ascii_codepoint: u32 = 32;
    while (ascii_codepoint < 127) : (ascii_codepoint += 1) {
        var run = try shapeOwned(&scalable, std.testing.allocator, .{
            .codepoints = &.{ascii_codepoint},
            .clusters = &.{0},
        });
        defer run.deinit();
        try std.testing.expect(run.glyphs.len > 0);
        for (run.glyphs) |glyph|
            try std.testing.expect(
                ceilPositive26Dot6(glyph.x_advance) <=
                    scalable.metrics.advance_width,
            );
    }

    var underscore_run = try shapeOwned(&scalable, std.testing.allocator, .{
        .codepoints = &.{'_'},
        .clusters = &.{0},
    });
    defer underscore_run.deinit();
    var underscore = try scalable.rasterize(
        std.testing.allocator,
        underscore_run.face_index,
        underscore_run.glyphs[0].id,
        scalable.metrics.advance_width,
    );
    defer underscore.deinit();
    const underscore_top =
        @as(i32, scalable.metrics.baseline) - underscore.top;
    try std.testing.expect(underscore_top >= 0);
    try std.testing.expect(
        underscore_top + underscore.height <= scalable.metrics.line_height,
    );

    var bitmap = try text.FontSet.init(std.testing.allocator, .{
        .primary = fonts.mono_font,
        .pixel_height = 16,
    });
    defer bitmap.deinit();
    try std.testing.expectEqual(@as(u16, 8), bitmap.metrics.advance_width);
    try std.testing.expectEqual(@as(u16, 16), bitmap.metrics.line_height);
    try std.testing.expectEqual(@as(u16, 13), bitmap.metrics.baseline);
    try std.testing.expectEqual(@as(u16, 14), bitmap.metrics.underline_y);
    try std.testing.expectEqual(@as(u16, 1), bitmap.metrics.underline_height);
    try std.testing.expectEqual(@as(u16, 8), bitmap.metrics.strike_y);
    try std.testing.expectEqual(@as(u16, 1), bitmap.metrics.strike_height);
    try expectMetricsValid(bitmap.metrics);

    const codepoint = [_]u32{'A'};
    const cluster = [_]u32{0};
    var run = try shapeOwned(&bitmap, std.testing.allocator, .{
        .codepoints = &codepoint,
        .clusters = &cluster,
    });
    defer run.deinit();
    var raster = try bitmap.rasterize(
        std.testing.allocator,
        run.face_index,
        run.glyphs[0].id,
        bitmap.metrics.advance_width,
    );
    defer raster.deinit();
    try std.testing.expectEqual(@as(u16, 8), raster.width);
    try std.testing.expectEqual(@as(u16, 16), raster.height);
    try std.testing.expect(std.mem.indexOfScalar(u8, raster.pixels, 255) != null);
    for (raster.pixels) |alpha| try std.testing.expect(alpha == 0 or alpha == 255);
}

test "monospace glyph origins follow one ordinary ASCII advance" {
    var set = try text.FontSet.init(std.testing.allocator, .{
        .primary = fonts.symbol_font,
        .pixel_height = 18,
    });
    defer set.deinit();
    try std.testing.expectEqual(@as(u16, 9), set.metrics.advance_width);

    const prompt = "bash-5.3$";
    var previous_origin: ?u32 = null;
    for (prompt, 0..) |byte, column| {
        const codepoints = [_]u32{byte};
        const clusters = [_]u32{0};
        var run = try shapeOwned(&set, std.testing.allocator, .{
            .codepoints = &codepoints,
            .clusters = &clusters,
        });
        defer run.deinit();
        try std.testing.expectEqual(@as(usize, 1), run.glyphs.len);
        try std.testing.expectEqual(
            set.metrics.advance_width,
            ceilPositive26Dot6(run.glyphs[0].x_advance),
        );

        const origin: u32 = @as(u32, @intCast(column)) *
            set.metrics.advance_width;
        if (previous_origin) |previous|
            try std.testing.expectEqual(
                @as(u32, set.metrics.advance_width),
                origin - previous,
            );
        previous_origin = origin;
    }
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
    var run = try shapeOwned(&set, std.testing.allocator, .{
        .codepoints = &codepoint,
        .clusters = &cluster,
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

fn expectMetricsValid(metrics: text.Metrics) !void {
    try std.testing.expect(metrics.advance_width > 0);
    try std.testing.expect(metrics.line_height > 0);
    try std.testing.expect(metrics.baseline < metrics.line_height);
    try std.testing.expect(metrics.underline_height > 0);
    try std.testing.expect(
        @as(u32, metrics.underline_y) + metrics.underline_height <=
            metrics.line_height,
    );
    try std.testing.expect(metrics.strike_height > 0);
    try std.testing.expect(
        @as(u32, metrics.strike_y) + metrics.strike_height <=
            metrics.line_height,
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

test "caller glyph capacity is exact and leaves short storage unchanged" {
    try std.testing.expectError(error.InvalidCapacity, text.ShapeBuffer.init(0));
    try std.testing.expectError(
        error.InvalidCapacity,
        text.ShapeBuffer.init(text.max_glyphs + 1),
    );
    var set = try text.FontSet.init(std.testing.allocator, .{
        .primary = fonts.primary_font,
        .pixel_height = 16,
    });
    defer set.deinit();
    var shaper = try text.ShapeBuffer.init(text.max_glyphs);
    defer shaper.deinit();
    const sentinel = text.Glyph{
        .id = 0xaaaaaaaa,
        .cluster = 0xbbbbbbbb,
        .x_advance = -1,
        .y_advance = -2,
        .x_offset = -3,
        .y_offset = -4,
    };
    var output = [_]text.Glyph{sentinel};
    var short_shaper = try text.ShapeBuffer.init(1);
    defer short_shaper.deinit();
    try std.testing.expectError(error.InsufficientShapeBuffer, set.shape(&short_shaper, .{
        .codepoints = &.{ 'A', 'B' },
        .clusters = &.{ 0, 1 },
    }, &output));
    try std.testing.expectEqual(sentinel, output[0]);
    try std.testing.expectError(error.InsufficientGlyphs, set.shape(&shaper, .{
        .codepoints = &.{ 'A', 'B' },
        .clusters = &.{ 0, 1 },
    }, &output));
    try std.testing.expectEqual(sentinel, output[0]);
    var complete: [2]text.Glyph = undefined;
    const run = try set.shape(&shaper, .{
        .codepoints = &.{ 'A', 'B' },
        .clusters = &.{ 0, 1 },
    }, &complete);
    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectEqual(@intFromPtr(complete[0..].ptr), @intFromPtr(run.glyphs.ptr));
}

test "raster allocation failures preserve reusable native faces" {
    var set = try text.FontSet.init(std.testing.allocator, .{
        .primary = fonts.primary_font,
        .pixel_height = 16,
    });
    defer set.deinit();

    const codepoint = [_]u32{'A'};
    const cluster = [_]u32{0};
    var run = try shapeOwned(&set, std.testing.allocator, .{
        .codepoints = &codepoint,
        .clusters = &cluster,
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
        set.metrics.advance_width,
    );
    raster.deinit();

    var symbols = try text.FontSet.init(std.testing.allocator, .{
        .primary = fonts.symbol_font,
        .pixel_height = 18,
    });
    defer symbols.deinit();
    var icon = try shapeOwned(&symbols, std.testing.allocator, .{
        .codepoints = &.{0xf303},
        .clusters = &.{0},
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
        symbols.metrics.advance_width,
    );
    reused.deinit();
}

const OwnedRun = struct {
    allocator: std.mem.Allocator,
    storage: []text.Glyph,
    shaper: text.ShapeBuffer,
    face_index: u8,
    glyphs: []const text.Glyph,

    fn deinit(self: *OwnedRun) void {
        self.shaper.deinit();
        self.allocator.free(self.storage);
        self.* = undefined;
    }
};

fn shapeOwned(
    set: *text.FontSet,
    allocator: std.mem.Allocator,
    value: text.Text,
) (text.ShapeError || text.ShapeBufferInitError || error{OutOfMemory})!OwnedRun {
    const storage = allocator.alloc(text.Glyph, text.max_glyphs) catch
        return error.OutOfMemory;
    errdefer allocator.free(storage);
    var shaper = try text.ShapeBuffer.init(text.max_glyphs);
    errdefer shaper.deinit();
    const run = try set.shape(&shaper, value, storage);
    return .{
        .allocator = allocator,
        .storage = storage,
        .shaper = shaper,
        .face_index = run.face_index,
        .glyphs = run.glyphs,
    };
}

fn rasterAllocation(
    allocator: std.mem.Allocator,
    set: *text.FontSet,
    glyph_id: u32,
) !void {
    var raster = try set.rasterize(allocator, 0, glyph_id, set.metrics.advance_width);
    raster.deinit();
}
