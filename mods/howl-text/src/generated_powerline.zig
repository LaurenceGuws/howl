//! Rasterizes the implemented Powerline separator ranges.

const std = @import("std");
const geometry = @import("generated_geometry.zig");
const special_box = @import("generated_box.zig");
const BoxDrawingStroke = geometry.BoxDrawingStroke;
const BoxDrawingStrokes = geometry.BoxDrawingStrokes;

/// Rasterizes the proven metric-independent Kitty-exact Powerline subset.
pub fn rasterizeGeneratedPowerlineAlphaMetricFree(
    pixels: []u8,
    width: u16,
    height: u16,
    codepoint: u32,
) error{UnsupportedGlyph}!void {
    switch (codepoint) {
        0xe0b0 => rasterizeKittyTriangle(pixels, width, height),
        0xe0b2 => {
            rasterizeKittyTriangle(pixels, width, height);
            mirrorPixels(pixels, width, height);
        },
        0xe0b4 => rasterizeKittyFilledD(pixels, width, height),
        0xe0b6 => {
            rasterizeKittyFilledD(pixels, width, height);
            mirrorPixels(pixels, width, height);
        },
        0xe0b8 => rasterizeKittyCornerTriangle(pixels, width, height, .bottom_left),
        0xe0ba => rasterizeKittyCornerTriangle(pixels, width, height, .bottom_right),
        0xe0bc => rasterizeKittyCornerTriangle(pixels, width, height, .top_left),
        0xe0be => rasterizeKittyCornerTriangle(pixels, width, height, .top_right),
        else => return error.UnsupportedGlyph,
    }
}

/// Rasterizes the proven metric-sensitive Kitty-exact Powerline subset.
pub fn rasterizeGeneratedPowerlineAlphaWithStrokes(
    pixels: []u8,
    width: u16,
    height: u16,
    codepoint: u32,
    strokes: BoxDrawingStrokes,
    vertical_line_width: f64,
) error{UnsupportedGlyph}!void {
    switch (codepoint) {
        0xe0b1 => rasterizeKittyHalfCross(
            pixels,
            width,
            height,
            strokes.vertical_supersampled[1],
            true,
        ),
        0xe0b3 => rasterizeKittyHalfCross(pixels, width, height, strokes.vertical_supersampled[1], false),
        0xe0b5 => rasterizeKittyRoundedSeparator(
            pixels,
            width,
            height,
            strokes.vertical[1],
            vertical_line_width,
            true,
        ),
        0xe0b7 => rasterizeKittyRoundedSeparator(
            pixels,
            width,
            height,
            strokes.vertical[1],
            vertical_line_width,
            false,
        ),
        0xe0b9, 0xe0bf => rasterizeKittyCrossLine(pixels, width, height, strokes.vertical_supersampled[1], true),
        0xe0bb, 0xe0bd => rasterizeKittyCrossLine(pixels, width, height, strokes.vertical_supersampled[1], false),
        else => return error.UnsupportedGlyph,
    }
}

/// Rasterizes one classified Powerline separator or extended triangle, or
/// returns `error.UnsupportedGlyph` for an unclassified codepoint.
pub fn rasterizeGeneratedPowerlineAlpha(
    pixels: []u8,
    width: u16,
    height: u16,
    codepoint: u32,
    box_drawing: BoxDrawingStroke,
) error{UnsupportedGlyph}!void {
    switch (codepoint) {
        0xe0b0 => rasterizePowerlineTriangle(pixels, width, height, true, false),
        0xe0b2 => rasterizePowerlineTriangle(pixels, width, height, false, false),
        0xe0b1 => rasterizePowerlineHalfDiagonal(pixels, width, height, true, box_drawing),
        0xe0b3 => rasterizePowerlineHalfDiagonal(pixels, width, height, false, box_drawing),
        0xe0b4 => rasterizePowerlineD(pixels, width, height, true, true, box_drawing),
        0xe0b6 => rasterizePowerlineD(pixels, width, height, false, true, box_drawing),
        0xe0b5 => rasterizePowerlineD(pixels, width, height, true, false, box_drawing),
        0xe0b7 => rasterizePowerlineD(pixels, width, height, false, false, box_drawing),
        0xe0b8 => rasterizePowerlineCornerTriangle(pixels, width, height, .bottom_left),
        0xe0b9, 0xe0bf => special_box.rasterizeCrossLine(pixels, width, height, true, box_drawing),
        0xe0ba => rasterizePowerlineCornerTriangle(pixels, width, height, .bottom_right),
        0xe0bb, 0xe0bd => special_box.rasterizeCrossLine(pixels, width, height, false, box_drawing),
        0xe0bc => rasterizePowerlineCornerTriangle(pixels, width, height, .top_left),
        0xe0be => rasterizePowerlineCornerTriangle(pixels, width, height, .top_right),
        0xe0d6 => rasterizePowerlineTriangle(pixels, width, height, false, false),
        0xe0d7 => rasterizePowerlineTriangle(pixels, width, height, true, false),
        // The sole generated classifier accepts only these implemented ranges.
        else => return error.UnsupportedGlyph,
    }
}

fn rasterizeKittyTriangle(pixels: []u8, width: u16, height: u16) void {
    const ss_width = width * 4;
    const ss_height = height * 4;
    const mid = ss_height / 2;
    for (0..height) |y| for (0..width) |x| {
        var hits: u16 = 0;
        for (0..4) |local_y| for (0..4) |local_x| {
            const sample_x = x * 4 + local_x;
            const sample_y = y * 4 + local_y;
            const upper = kittyLineY(0, 0, ss_width - 1, mid, sample_x);
            const lower = kittyLineY(
                0,
                ss_height - 1,
                ss_width - 1,
                mid,
                sample_x,
            );
            if (@as(f64, @floatFromInt(sample_y)) >= upper and
                @as(f64, @floatFromInt(sample_y)) <= lower)
                hits += 1;
        };
        pixels[y * width + x] = @intCast(hits * 255 / 16);
    };
}

fn rasterizeKittyHalfCross(
    pixels: []u8,
    width: u16,
    height: u16,
    base_stroke: u16,
    left: bool,
) void {
    const ss_width = width * 4;
    const ss_height = height * 4;
    const mid = (ss_height - 1) / 2;
    const diagonal = kittyDiagonalThickness(base_stroke, ss_width - 1, mid);
    for (0..height) |y| for (0..width) |x| {
        var hits: u16 = 0;
        for (0..4) |local_y| for (0..4) |local_x| {
            const sample_x: u16 = @intCast(x * 4 + local_x);
            const sample_y: u16 = @intCast(y * 4 + local_y);
            const projected_x = if (left) sample_x else ss_width - 1 - sample_x;
            if (kittyThickLineContains(
                projected_x,
                sample_y,
                0,
                0,
                ss_width - 1,
                mid,
                diagonal,
            ) or kittyThickLineContains(
                projected_x,
                sample_y,
                0,
                ss_height - 1,
                ss_width - 1,
                mid,
                diagonal,
            ))
                hits += 1;
        };
        pixels[y * width + x] = @intCast(hits * 255 / 16);
    };
}

fn rasterizeKittyCrossLine(
    pixels: []u8,
    width: u16,
    height: u16,
    base_stroke: u16,
    left: bool,
) void {
    const ss_width = width * 4;
    const ss_height = height * 4;
    const diagonal = kittyDiagonalThickness(
        base_stroke,
        ss_width - 1,
        ss_height - 1,
    );
    for (0..height) |y| for (0..width) |x| {
        var hits: u16 = 0;
        for (0..4) |local_y| for (0..4) |local_x| {
            const sample_x: u16 = @intCast(x * 4 + local_x);
            const sample_y: u16 = @intCast(y * 4 + local_y);
            const projected_x = if (left) sample_x else ss_width - 1 - sample_x;
            if (kittyThickLineContains(
                projected_x,
                sample_y,
                0,
                0,
                ss_width - 1,
                ss_height - 1,
                diagonal,
            ))
                hits += 1;
        };
        pixels[y * width + x] = @intCast(hits * 255 / 16);
    };
}

fn rasterizeKittyFilledD(pixels: []u8, width: u16, height: u16) void {
    const ss_width = width * 4;
    const ss_height = height * 4;
    const control = kittyDControl(ss_width);
    var start_t: f64 = 0;
    const max_x: usize = @intFromFloat(kittyBezierX(control, 0.5));
    for (0..max_x + 1) |sample_x| {
        if (sample_x > 0)
            start_t = kittyFindT(control, @floatFromInt(sample_x), start_t);
        const upper = kittyBezierY(ss_height, start_t);
        const lower = kittyBezierY(ss_height, 1.0 - start_t);
        if (@abs(upper - lower) <= 2.0) break;
        var sample_y: usize = 0;
        while (sample_y < ss_height) : (sample_y += 1) {
            if (@as(f64, @floatFromInt(sample_y)) < upper or
                @as(f64, @floatFromInt(sample_y)) > lower)
                continue;
            pixels[(sample_y / 4) * width + sample_x / 4] += 1;
        }
    }
    for (pixels[0 .. @as(usize, width) * height]) |*value|
        value.* = @intCast(@as(u16, value.*) * 255 / 16);
}

fn rasterizeKittyCornerTriangle(
    pixels: []u8,
    width: u16,
    height: u16,
    corner: PowerlineCorner,
) void {
    const ss_width = width * 4;
    const ss_height = height * 4;
    for (0..height) |y| for (0..width) |x| {
        var hits: u16 = 0;
        for (0..4) |local_y| for (0..4) |local_x| {
            const sample_x = x * 4 + local_x;
            const sample_y = y * 4 + local_y;
            const down = kittyLineY(0, 0, ss_width - 1, ss_height - 1, sample_x);
            const up = kittyLineY(ss_width - 1, 0, 0, ss_height - 1, sample_x);
            const inside = switch (corner) {
                .top_left => @as(f64, @floatFromInt(sample_y)) <= up,
                .top_right => @as(f64, @floatFromInt(sample_y)) <= down,
                .bottom_left => @as(f64, @floatFromInt(sample_y)) >= down,
                .bottom_right => @as(f64, @floatFromInt(sample_y)) >= up,
            };
            if (inside) hits += 1;
        };
        pixels[y * width + x] = @intCast(hits * 255 / 16);
    };
}

fn rasterizeKittyRoundedSeparator(
    pixels: []u8,
    width: u16,
    height: u16,
    gap: u16,
    line_width: f64,
    left: bool,
) void {
    const curve_width = @max(width -| gap, 1);
    const control = kittyDControl(curve_width);
    const half_gap = gap / 2;
    const end_y = height -| (1 + half_gap);
    const sample_limit = @max(width, height);
    const max_step = 1.0 / @as(f64, @floatFromInt(sample_limit));
    const min_step = max_step / 1000.0;
    for (0..height) |y| for (0..width) |x| {
        const pixel_x =
            @as(f64, @floatFromInt(if (left) x else width - 1 - x)) + 0.5;
        const pixel_y = @as(f64, @floatFromInt(y)) + 0.5;
        var minimum = std.math.floatMax(f64);
        var t: f64 = 0;
        while (true) {
            // Kitty stores the terminal t=1 sample but excludes it through
            // num_samples=i; preserve that generic curve-walker behavior.
            if (t >= 1.0) break;
            const sample_x = kittyBezierX(control, t);
            const sample_y =
                kittyBezierYForEnd(end_y, t) + @as(f64, @floatFromInt(half_gap));
            const dx = sample_x - pixel_x;
            const dy = sample_y - pixel_y;
            minimum = @min(minimum, dx * dx + dy * dy);
            const derivative_x = kittyBezierPrimeX(control, t);
            const derivative_y = kittyBezierPrimeY(end_y, t);
            const distance = @sqrt(
                derivative_x * derivative_x + derivative_y * derivative_y,
            );
            t = @min(
                t + std.math.clamp(
                    1.0 / @max(1e-6, distance),
                    min_step,
                    max_step,
                ),
                1.0,
            );
        }
        const alpha = std.math.clamp(
            @max(line_width, 1.0) / 2.0 -
                @sqrt(minimum) + 0.5,
            0.0,
            1.0,
        );
        pixels[y * width + x] = @intFromFloat(alpha * 255.0);
    };
}

fn kittyBezierYForEnd(end_y: u16, t: f64) f64 {
    const u = 1.0 - t;
    const end: f64 = @floatFromInt(end_y);
    return 3.0 * t * t * u * end + t * t * t * end;
}

fn kittyBezierPrimeX(control: u16, t: f64) f64 {
    const u = 1.0 - t;
    const value: f64 = @floatFromInt(control);
    return 3.0 * u * u * value - 3.0 * t * t * value;
}

fn kittyBezierPrimeY(end_y: u16, t: f64) f64 {
    const u = 1.0 - t;
    const end: f64 = @floatFromInt(end_y);
    return 6.0 * t * u * end;
}

fn mirrorPixels(pixels: []u8, width: u16, height: u16) void {
    for (0..height) |y| for (0..width / 2) |x| {
        const left = y * width + x;
        const right = y * width + width - 1 - x;
        std.mem.swap(u8, &pixels[left], &pixels[right]);
    };
}

fn kittyLineY(
    x1: u16,
    y1: u16,
    x2: u16,
    y2: u16,
    x: usize,
) f64 {
    const slope =
        (@as(f64, @floatFromInt(y2)) - @as(f64, @floatFromInt(y1))) /
        (@as(f64, @floatFromInt(x2)) - @as(f64, @floatFromInt(x1)));
    return slope * (@as(f64, @floatFromInt(x)) -
        @as(f64, @floatFromInt(x1))) + @as(f64, @floatFromInt(y1));
}

fn kittyDiagonalThickness(base: u16, dx: u16, dy: u16) u16 {
    const slope =
        @as(f64, @floatFromInt(dy)) / @as(f64, @floatFromInt(dx));
    return @max(
        @as(u16, 1),
        @as(u16, @intFromFloat(@round(
            @as(f64, @floatFromInt(base)) * @sqrt(1.0 + slope * slope),
        ))),
    );
}

fn kittyThickLineContains(
    x: u16,
    y: u16,
    x1: u16,
    y1: u16,
    x2: u16,
    y2: u16,
    thickness: u16,
) bool {
    if (x < x1 or x > x2) return false;
    const center: i32 = @intFromFloat(kittyLineY(x1, y1, x2, y2, x));
    const delta: i32 = thickness / 2;
    const extra: i32 = thickness % 2;
    return y >= @max(@as(i32, 0), center - delta) and
        y < center + delta + extra;
}

fn kittyDControl(width: u16) u16 {
    var control = width - 1;
    var last = control;
    while (true) : (control += 1) {
        if (kittyBezierX(control, 0.5) > width - 1) return last;
        last = control;
    }
}

fn kittyBezierX(control: u16, t: f64) f64 {
    const u = 1.0 - t;
    return 3.0 * t * u * @as(f64, @floatFromInt(control));
}

fn kittyBezierY(height: u16, t: f64) f64 {
    const u = 1.0 - t;
    const end: f64 = @floatFromInt(height - 1);
    return 3.0 * t * t * u * end + t * t * t * end;
}

fn kittyFindT(control: u16, x: f64, initial: f64) f64 {
    var start = initial;
    if (@abs(kittyBezierX(control, start) - x) < 0.1) return start;
    var increment = 0.5 - start;
    while (true) {
        const value = kittyBezierX(control, start + increment);
        if (@abs(value - x) < 0.1) return start + increment;
        if (value > x) {
            increment /= 2.0;
            if (increment < 1e-6) return start;
        } else {
            start += increment;
            increment = 0.5 - start;
            if (increment <= 0) return start;
        }
    }
}

fn rasterizePowerlineTriangle(pixels: []u8, width: u16, height: u16, left: bool, inverted: bool) void {
    const x1: f64 = if (left) 0 else @floatFromInt(width - 1);
    const x2: f64 = if (left) @floatFromInt(width - 1) else 0;
    const y_mid = @as(f64, @floatFromInt(height - 1)) / 2.0;
    var y: u16 = 0;
    while (y < height) : (y += 1) {
        var x: u16 = 0;
        while (x < width) : (x += 1) {
            const coverage = supersampledTriangleCoverage(x, y, .{ .x1 = x1, .x2 = x2, .y_mid = y_mid, .height = height, .inverted = inverted });
            if (coverage != 0) pixels[geometry.pixelOffset(width, x, y)] = coverage;
        }
    }
}

fn rasterizePowerlineHalfDiagonal(pixels: []u8, width: u16, height: u16, left: bool, box_drawing: BoxDrawingStroke) void {
    const mid = @as(f64, @floatFromInt(height - 1)) / 2.0;
    const line_w = @as(f64, @floatFromInt(box_drawing.light_stroke_px));
    if (left) {
        geometry.drawLineAlpha(pixels, width, height, 0, 0, @floatFromInt(width - 1), mid, line_w);
        geometry.drawLineAlpha(pixels, width, height, @floatFromInt(width - 1), mid, 0, @floatFromInt(height - 1), line_w);
    } else {
        geometry.drawLineAlpha(pixels, width, height, @floatFromInt(width - 1), 0, 0, mid, line_w);
        geometry.drawLineAlpha(pixels, width, height, 0, mid, @floatFromInt(width - 1), @floatFromInt(height - 1), line_w);
    }
}

fn rasterizePowerlineD(pixels: []u8, width: u16, height: u16, left: bool, filled: bool, box_drawing: BoxDrawingStroke) void {
    if (filled) {
        rasterizePowerlineFilledD(pixels, width, height, left);
    } else {
        rasterizePowerlineRoundedD(pixels, width, height, left, box_drawing);
    }
}

const CubicBezier = struct {
    start: geometry.PointF,
    c1: geometry.PointF,
    c2: geometry.PointF,
    end: geometry.PointF,
};

fn rasterizePowerlineFilledD(pixels: []u8, width: u16, height: u16, left: bool) void {
    const max_x = findBezierControlX(width, height);
    const bottom: f64 = @floatFromInt(height);
    const cb = CubicBezier{
        .start = .{ .x = 0, .y = 0 },
        .c1 = .{ .x = @floatFromInt(max_x), .y = 0 },
        .c2 = .{ .x = @floatFromInt(max_x), .y = bottom },
        .end = .{ .x = 0, .y = bottom },
    };

    var y: u16 = 0;
    while (y < height) : (y += 1) {
        var x: u16 = 0;
        while (x < width) : (x += 1) {
            const coverage = supersampledFilledDCoverage(x, y, .{ .cb = cb, .width = width, .left = left });
            if (coverage != 0) pixels[geometry.pixelOffset(width, x, y)] = coverage;
        }
    }
}

const TriangleCoverageCtx = struct { x1: f64, x2: f64, y_mid: f64, height: u16, inverted: bool };
const FilledDCoverageCtx = struct { cb: CubicBezier, width: u16, left: bool };

fn supersampledTriangleCoverage(x: u16, y: u16, ctx: TriangleCoverageCtx) u8 {
    return geometry.supersampledCoverage(
        x,
        y,
        TriangleCoverageCtx,
        triangleContains,
        ctx,
    );
}

fn supersampledFilledDCoverage(x: u16, y: u16, ctx: FilledDCoverageCtx) u8 {
    return geometry.supersampledCoverage(
        x,
        y,
        FilledDCoverageCtx,
        filledDContains,
        ctx,
    );
}

fn triangleContains(px: f64, py: f64, ctx: TriangleCoverageCtx) bool {
    const upper = geometry.lineY(ctx.x1, 0, ctx.x2, ctx.y_mid, px);
    const lower = geometry.lineY(ctx.x1, @floatFromInt(ctx.height - 1), ctx.x2, ctx.y_mid, px);
    return (py >= upper and py <= lower) != ctx.inverted;
}

fn filledDContains(px_raw: f64, py: f64, ctx: FilledDCoverageCtx) bool {
    const px = if (ctx.left) px_raw else @as(f64, @floatFromInt(ctx.width - 1)) - px_raw;
    const t = findBezierTForX(ctx.cb, px);
    if (bezierX(ctx.cb, t) > @as(f64, @floatFromInt(ctx.width - 1)) + 0.5) return false;
    const upper = bezierY(ctx.cb, t);
    const lower = bezierY(ctx.cb, 1.0 - t);
    return py >= upper and py <= lower;
}

fn rasterizePowerlineRoundedD(pixels: []u8, width: u16, height: u16, left: bool, box_drawing: BoxDrawingStroke) void {
    const gap = box_drawing.light_stroke_px;
    const half_gap = @as(f64, @floatFromInt(gap)) / 2.0;
    const curve_w = if (width > gap) width - gap else width;
    const curve_h = if (height > gap) height - gap else height;
    const max_x = findBezierControlX(curve_w, curve_h);
    const cb = CubicBezier{
        .start = .{ .x = 0, .y = 0 },
        .c1 = .{ .x = @floatFromInt(max_x), .y = 0 },
        .c2 = .{ .x = @floatFromInt(max_x), .y = @floatFromInt(curve_h - 1) },
        .end = .{ .x = 0, .y = @floatFromInt(curve_h - 1) },
    };
    drawCubicStrokeAlpha(pixels, width, height, cb, @floatFromInt(gap), half_gap, left);
}

fn findBezierControlX(width: u16, height: u16) u16 {
    var cx: u16 = width - 1;
    var last = cx;
    while (cx < width * 4) : (cx += 1) {
        const cb = CubicBezier{
            .start = .{ .x = 0, .y = 0 },
            .c1 = .{ .x = @floatFromInt(cx), .y = 0 },
            .c2 = .{ .x = @floatFromInt(cx), .y = @floatFromInt(height - 1) },
            .end = .{ .x = 0, .y = @floatFromInt(height - 1) },
        };
        if (bezierX(cb, 0.5) > @as(f64, @floatFromInt(width - 1))) return last;
        last = cx;
    }
    return last;
}

fn findBezierTForX(cb: CubicBezier, x: f64) f64 {
    var lo: f64 = 0;
    var hi: f64 = 0.5;
    var i: u8 = 0;
    while (i < 24) : (i += 1) {
        const mid = (lo + hi) / 2.0;
        if (bezierX(cb, mid) < x) lo = mid else hi = mid;
    }
    return (lo + hi) / 2.0;
}

fn drawCubicStrokeAlpha(pixels: []u8, width: u16, height: u16, cb: CubicBezier, line_width: f64, y_offset: f64, left: bool) void {
    const samples = 96;
    const half = @max(line_width, 1.0) / 2.0;
    var y: u16 = 0;
    while (y < height) : (y += 1) {
        var x: u16 = 0;
        while (x < width) : (x += 1) {
            const px = @as(f64, @floatFromInt(if (left) x else width - 1 - x)) + 0.5;
            const py = @as(f64, @floatFromInt(y)) + 0.5 - y_offset;
            var min_d2 = std.math.floatMax(f64);
            var i: u16 = 0;
            while (i <= samples) : (i += 1) {
                const t = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(samples));
                const sx = bezierX(cb, t);
                const sy = bezierY(cb, t);
                const dx = px - sx;
                const dy = py - sy;
                min_d2 = @min(min_d2, dx * dx + dy * dy);
            }
            const coverage = std.math.clamp(half - @sqrt(min_d2) + 0.5, 0.0, 1.0);
            if (coverage <= 0) continue;
            pixels[geometry.pixelOffset(width, x, y)] = @intFromFloat(@round(coverage * 255.0));
        }
    }
}

fn bezierX(cb: CubicBezier, t: f64) f64 {
    return bezierValue(cb.start.x, cb.c1.x, cb.c2.x, cb.end.x, t);
}

fn bezierY(cb: CubicBezier, t: f64) f64 {
    return bezierValue(cb.start.y, cb.c1.y, cb.c2.y, cb.end.y, t);
}

fn bezierValue(start: f64, c1: f64, c2: f64, end: f64, t: f64) f64 {
    const u = 1.0 - t;
    return u * u * u * start + 3.0 * t * u * (u * c1 + t * c2) + t * t * t * end;
}

const PowerlineCorner = enum { top_left, top_right, bottom_left, bottom_right };

fn rasterizePowerlineCornerTriangle(pixels: []u8, width: u16, height: u16, corner: PowerlineCorner) void {
    var y: u16 = 0;
    while (y < height) : (y += 1) {
        var x: u16 = 0;
        while (x < width) : (x += 1) {
            const xf = @as(f64, @floatFromInt(x)) + 0.5;
            const yf = @as(f64, @floatFromInt(y)) + 0.5;
            const diag_down = geometry.lineY(0, 0, @floatFromInt(width - 1), @floatFromInt(height - 1), xf);
            const diag_up = geometry.lineY(@floatFromInt(width - 1), 0, 0, @floatFromInt(height - 1), xf);
            const inside = switch (corner) {
                .top_left => yf <= diag_up,
                .top_right => yf <= diag_down,
                .bottom_left => yf >= diag_down,
                .bottom_right => yf >= diag_up,
            };
            if (inside) pixels[geometry.pixelOffset(width, x, y)] = 255;
        }
    }
}

test "powerline triangles retain exact aliases and directions" {
    var right: [8 * 8]u8 = undefined;
    var left: [8 * 8]u8 = undefined;
    var extended_right: [8 * 8]u8 = undefined;
    var extended_left: [8 * 8]u8 = undefined;
    const stroke = BoxDrawingStroke{
        .light_stroke_px = 2,
        .heavy_stroke_px = 4,
    };
    @memset(&right, 0);
    @memset(&left, 0);
    @memset(&extended_right, 0);
    @memset(&extended_left, 0);
    try rasterizeGeneratedPowerlineAlpha(&right, 8, 8, 0xe0b0, stroke);
    try rasterizeGeneratedPowerlineAlpha(&left, 8, 8, 0xe0b2, stroke);
    try rasterizeGeneratedPowerlineAlpha(
        &extended_right,
        8,
        8,
        0xe0d7,
        stroke,
    );
    try rasterizeGeneratedPowerlineAlpha(
        &extended_left,
        8,
        8,
        0xe0d6,
        stroke,
    );
    try std.testing.expectEqualSlices(u8, &right, &extended_right);
    try std.testing.expectEqualSlices(u8, &left, &extended_left);
    try std.testing.expect(right[0] != 0);
    try std.testing.expect(right[7] == 0);
    try std.testing.expect(left[0] == 0);
    try std.testing.expect(left[7] != 0);
}
