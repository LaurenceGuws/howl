//! Owns shared bounded pixel geometry for generated terminal glyph families.

const std = @import("std");

/// Configures bounded box lines with heavy geometry at least as wide as light.
pub const BoxDrawingStroke = struct {
    /// Sets the nonzero light-line width in pixels.
    light_stroke_px: u16,
    /// Sets the heavy-line width, which must be at least the light width.
    heavy_stroke_px: u16,
};

/// Stores independently derived Kitty box geometry for both factual axes.
pub const BoxDrawingStrokes = struct {
    /// Uses Y DPI for horizontal box-line thickness at levels zero through three.
    horizontal: [4]u16,
    /// Uses X DPI for vertical box-line thickness at levels zero through three.
    vertical: [4]u16,
    /// Retains independently rounded 4× horizontal curve thicknesses.
    horizontal_supersampled: [4]u16,
    /// Retains independently rounded 4× vertical curve thicknesses.
    vertical_supersampled: [4]u16,
};

/// Carries one internal half-open pixel interval.
pub const Range = struct { start: u16, end: u16 };

/// Divides a pixel extent into stable, gap-free eighths.
pub fn eighthPartitionRange(size: u16, which: u16) Range {
    const thickness = @max(@as(u16, 1), size / 8);
    const block = thickness * 8;
    if (block == size) return .{
        .start = thickness * which,
        .end = thickness * (@as(u16, which) + 1),
    };
    if (block > size) {
        const start = @min(
            @as(u16, which) * thickness,
            saturatingSubU16(size, thickness),
        );
        return .{ .start = start, .end = start + thickness };
    }

    var thicknesses = @as([8]u16, @splat(thickness));
    var extra = size - block;
    const order = [_]u8{ 3, 4, 2, 5, 6, 1, 7, 0 };
    for (order) |index| {
        if (extra == 0) break;
        thicknesses[index] += 1;
        extra -= 1;
    }
    var position: u16 = 0;
    var index: u8 = 0;
    while (index < which) : (index += 1) position += thicknesses[index];
    return .{
        .start = position,
        .end = position + thicknesses[which],
    };
}

/// Carries one internal subpixel geometry point.
pub const PointF = struct { x: f64, y: f64 };

/// Computes deterministic 4×4 alpha coverage for generated curves.
pub fn supersampledCoverage(
    x: u16,
    y: u16,
    comptime Context: type,
    comptime inside: fn (f64, f64, Context) bool,
    context: Context,
) u8 {
    // The callback and context stay compile-time concrete across geometry
    // owners; no runtime type erasure or ownership crosses this boundary.
    const factor = 4;
    var hits: u16 = 0;
    var sample_y: u8 = 0;
    while (sample_y < factor) : (sample_y += 1) {
        var sample_x: u8 = 0;
        while (sample_x < factor) : (sample_x += 1) {
            const px = @as(f64, @floatFromInt(x)) +
                (@as(f64, @floatFromInt(sample_x)) + 0.5) / factor;
            const py = @as(f64, @floatFromInt(y)) +
                (@as(f64, @floatFromInt(sample_y)) + 0.5) / factor;
            if (inside(px, py, context)) hits += 1;
        }
    }
    return @intCast(
        (hits * 255 + (factor * factor / 2)) / (factor * factor),
    );
}

const CoverageTestContext = struct { x: f64, y: f64 };

fn coverageTestInside(px: f64, py: f64, context: CoverageTestContext) bool {
    return px >= context.x and py >= context.y;
}

test "supersampled coverage accepts a typed callback context" {
    const coverage = supersampledCoverage(
        0,
        0,
        CoverageTestContext,
        coverageTestInside,
        .{ .x = 0.0, .y = 0.0 },
    );
    try std.testing.expectEqual(@as(u8, 255), coverage);
}

/// Draws one antialiased generated line into a bounded alpha mask.
pub fn drawLineAlpha(
    pixels: []u8,
    width: u16,
    height: u16,
    x1: f64,
    y1: f64,
    x2: f64,
    y2: f64,
    line_width: f64,
) void {
    const dx = x2 - x1;
    const dy = y2 - y1;
    const length_squared = @max(dx * dx + dy * dy, 1.0);
    const half = @max(line_width, 1.0) / 2.0;
    var y: u16 = 0;
    while (y < height) : (y += 1) {
        var x: u16 = 0;
        while (x < width) : (x += 1) {
            const px = @as(f64, @floatFromInt(x)) + 0.5;
            const py = @as(f64, @floatFromInt(y)) + 0.5;
            const t = std.math.clamp(
                ((px - x1) * dx + (py - y1) * dy) / length_squared,
                0.0,
                1.0,
            );
            const closest_x = x1 + t * dx;
            const closest_y = y1 + t * dy;
            const distance = @sqrt(
                (px - closest_x) * (px - closest_x) +
                    (py - closest_y) * (py - closest_y),
            );
            const coverage = std.math.clamp(
                half - distance + 0.5,
                0.0,
                1.0,
            );
            if (coverage <= 0) continue;
            const offset = pixelOffset(width, x, y);
            pixels[offset] = @max(
                pixels[offset],
                @as(u8, @intFromFloat(@round(coverage * 255.0))),
            );
        }
    }
}

/// Interpolates a generated line at one x coordinate.
pub fn lineY(x1: f64, y1: f64, x2: f64, y2: f64, x: f64) f64 {
    if (x1 == x2) return y1;
    const slope = (y2 - y1) / (x2 - x1);
    return slope * x + y1 - slope * x1;
}

/// Fills one already-clipped rectangle in a generated alpha mask.
pub fn fillRectAlpha(
    pixels: []u8,
    stride: u16,
    x: u16,
    y: u16,
    width: u16,
    height: u16,
    alpha: u8,
) void {
    var yy = y;
    while (yy < y + height) : (yy += 1) {
        var xx = x;
        while (xx < x + width) : (xx += 1) {
            pixels[pixelOffset(stride, xx, yy)] = alpha;
        }
    }
}

/// Subtracts internal pixel extents without wrapping.
pub fn saturatingSubU16(a: u16, b: u16) u16 {
    return if (a > b) a - b else 0;
}

/// Returns one bounded generated-mask offset.
pub fn pixelOffset(width: u16, x: u16, y: u16) u32 {
    return @as(u32, width) * @as(u32, y) + x;
}
