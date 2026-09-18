//! Rasterizes Kitty's generated U+F5D0-U+F60D branch-drawing family.

const std = @import("std");
const geometry = @import("generated_geometry.zig");
const BoxDrawingStrokes = geometry.BoxDrawingStrokes;

const left: u8 = 1;
const right: u8 = 2;
const top: u8 = 4;
const bottom: u8 = 8;

/// Fills one validated caller-owned alpha raster for an exact branch glyph.
/// All failures precede mutation; success replaces exactly `width * height`
/// bytes and leaves trailing caller storage untouched.
pub fn rasterize(
    pixels: []u8,
    width: u16,
    height: u16,
    codepoint: u32,
    strokes: ?BoxDrawingStrokes,
) error{UnsupportedGlyph}!void {
    if (codepoint < 0xf5d0 or codepoint > 0xf60d)
        return error.UnsupportedGlyph;
    const needs_stroke = codepoint != 0xf5ee;
    if (needs_stroke != (strokes != null)) return error.UnsupportedGlyph;
    @memset(pixels[0 .. @as(usize, width) * height], 0);
    if (codepoint == 0xf5ee) return commit(pixels, width, height, 0, true, null);
    const s = strokes.?;
    switch (codepoint) {
        0xf5d0 => hline(pixels, width, height, s.horizontal[1]),
        0xf5d1 => vline(pixels, width, height, s.vertical[1]),
        0xf5d2 => fadingLine(pixels, width, height, true, false, 4, s.horizontal[1]),
        0xf5d3 => fadingLine(pixels, width, height, true, true, 4, s.horizontal[1]),
        0xf5d4 => fadingLine(pixels, width, height, false, false, 5, s.vertical[1]),
        0xf5d5 => fadingLine(pixels, width, height, false, true, 5, s.vertical[1]),
        0xf5d6...0xf5ed => roundedComposite(pixels, width, height, codepoint, s),
        0xf5ef...0xf60d => {
            const pair = codepoint - 0xf5ee;
            const index = pair / 2;
            const lines = commitLines(index);
            commit(pixels, width, height, lines, pair % 2 == 0, s);
        },
        else => return error.UnsupportedGlyph,
    }
}

fn hline(pixels: []u8, width: u16, height: u16, stroke: u16) void {
    const range = centeredRange(height, height / 2, stroke);
    fill(pixels, width, range[0], range[1], 0, width, 255);
}

fn vline(pixels: []u8, width: u16, height: u16, stroke: u16) void {
    const range = centeredRange(width, width / 2, stroke);
    fill(pixels, width, 0, height, range[0], range[1], 255);
}

fn fadingLine(
    pixels: []u8,
    width: u16,
    height: u16,
    horizontal: bool,
    reverse: bool,
    count: u16,
    stroke: u16,
) void {
    const total = if (horizontal) width else height;
    const step = total / count;
    var position: i32 = if (reverse) total else 0;
    const direction: i32 = if (reverse) -1 else 1;
    var index: u16 = 0;
    while (index < count) : (index += 1) {
        var size = step * (count - index) / (count + 1);
        if (step > 2 and size >= step - 1) size = step - 2;
        const raw_end = @max(position + direction * @as(i32, size), 0);
        const start: u16 = @intCast(@min(position, raw_end));
        const end: u16 = @intCast(@max(position, raw_end));
        if (horizontal) {
            const yr = centeredRange(height, height / 2, stroke);
            fill(pixels, width, yr[0], yr[1], start, end, 255);
        } else {
            const xr = centeredRange(width, width / 2, stroke);
            fill(pixels, width, start, end, xr[0], xr[1], 255);
        }
        position += @as(i32, step) * direction;
    }
}

fn roundedComposite(
    pixels: []u8,
    width: u16,
    height: u16,
    codepoint: u32,
    strokes: BoxDrawingStrokes,
) void {
    const corners: []const u8 = switch (codepoint) {
        0xf5d6 => &.{top | left},
        0xf5d7 => &.{top | right},
        0xf5d8 => &.{bottom | left},
        0xf5d9 => &.{bottom | right},
        0xf5da => &.{bottom | left},
        0xf5db => &.{top | left},
        0xf5dc => &.{ bottom | left, top | left },
        0xf5dd => &.{bottom | right},
        0xf5de => &.{top | right},
        0xf5df => &.{ top | right, bottom | right },
        0xf5e0 => &.{top | right},
        0xf5e1 => &.{top | left},
        0xf5e2 => &.{ top | left, top | right },
        0xf5e3 => &.{bottom | right},
        0xf5e4 => &.{bottom | left},
        0xf5e5 => &.{ bottom | left, bottom | right },
        0xf5e6 => &.{ bottom | left, bottom | right },
        0xf5e7 => &.{ top | left, top | right },
        0xf5e8 => &.{ top | right, bottom | right },
        0xf5e9 => &.{ bottom | left, top | left },
        0xf5ea => &.{ top | left, bottom | right },
        0xf5eb => &.{ top | right, bottom | left },
        0xf5ec => &.{ top | left, bottom | right },
        0xf5ed => &.{ top | right, bottom | left },
        else => unreachable,
    };
    if (switch (codepoint) {
        0xf5da, 0xf5db, 0xf5dd, 0xf5de, 0xf5e6, 0xf5e7, 0xf5ea, 0xf5eb => true,
        else => false,
    }) vline(pixels, width, height, strokes.vertical[1]);
    if (switch (codepoint) {
        0xf5e0, 0xf5e1, 0xf5e3, 0xf5e4, 0xf5e8, 0xf5e9, 0xf5ec, 0xf5ed => true,
        else => false,
    }) hline(pixels, width, height, strokes.horizontal[1]);
    for (corners) |corner| roundedCorner(pixels, width, height, corner, strokes);
}

fn roundedCorner(
    pixels: []u8,
    width: u16,
    height: u16,
    corner: u8,
    strokes: BoxDrawingStrokes,
) void {
    const hr = centeredRange(height, height / 2, strokes.horizontal[1]);
    const vr = centeredRange(width, width / 2, strokes.vertical[1]);
    const hx = @as(f64, @floatFromInt(vr[0])) + @as(f64, @floatFromInt(vr[1] - vr[0])) / 2.0;
    const hy = @as(f64, @floatFromInt(hr[0])) + @as(f64, @floatFromInt(hr[1] - hr[0])) / 2.0;
    const stroke = @as(f64, @floatFromInt(@max(hr[1] - hr[0], vr[1] - vr[0])));
    const radius = @min(hx, hy);
    const bx = hx - radius;
    const by = hy - radius;
    const x_shift = if (corner & right != 0) hx else -hx;
    const y_shift = if (corner & top != 0) -hy else hy;
    for (0..height) |y| for (0..width) |x| {
        const px = @as(f64, @floatFromInt(x)) + x_shift + 0.5 - hx;
        const py = @as(f64, @floatFromInt(y)) + y_shift + 0.5 - hy;
        const qx = @abs(px) - bx;
        const qy = @abs(py) - by;
        const dx = @max(qx, 0.0);
        const dy = @max(qy, 0.0);
        const dist = @sqrt(dx * dx + dy * dy) + @min(@max(qx, qy), 0.0) - radius;
        const aa: f64 = if (qx > 1e-7 and qy > 1e-7) 0.5 else 0;
        const alpha = smoothstep(-aa, aa, stroke / 2.0 - dist) -
            smoothstep(-aa, aa, -stroke / 2.0 - dist);
        if (alpha <= 0) continue;
        const value: u8 = @intFromFloat(@round(std.math.clamp(alpha, 0, 1) * 255));
        const offset = y * width + x;
        pixels[offset] = @max(pixels[offset], value);
    };
}

fn commit(
    pixels: []u8,
    width: u16,
    height: u16,
    lines: u8,
    solid: bool,
    strokes: ?BoxDrawingStrokes,
) void {
    const sw: u16 = width * 4;
    const sh: u16 = height * 4;
    // Kitty aligns line midpoints to the original cell lattice before its 4×
    // pass, while commit circles retain the supersampled canvas midpoint.
    const line_hw = 4 * (width / 2);
    const line_hh = 4 * (height / 2);
    const circle_x = sw / 2;
    const circle_y = sh / 2;
    const horizontal_stroke = if (lines != 0) strokes.?.horizontal_supersampled[1] else 0;
    const vertical_stroke = if (lines != 0) strokes.?.vertical_supersampled[1] else 0;
    const gap: u16 = if (solid) 0 else strokes.?.vertical_supersampled[1];
    const outer_radius = circleRadius(circle_x, circle_y, 0);
    const inner_radius = circleRadius(circle_x, circle_y, gap);
    for (0..height) |y| for (0..width) |x| {
        var total: u16 = 0;
        for (0..4) |yy| for (0..4) |xx| {
            const sx: u16 = @intCast(x * 4 + xx);
            const sy: u16 = @intCast(y * 4 + yy);
            var value: u8 = 0;
            if (lines & right != 0 and sx >= line_hw and
                inCenteredRange(sy, sh, line_hh, horizontal_stroke)) value = 255;
            if (lines & left != 0 and sx < line_hw and
                inCenteredRange(sy, sh, line_hh, horizontal_stroke)) value = 255;
            if (lines & top != 0 and sy < line_hh and
                inCenteredRange(sx, sw, line_hw, vertical_stroke)) value = 255;
            if (lines & bottom != 0 and sy >= line_hh and
                inCenteredRange(sx, sw, line_hw, vertical_stroke)) value = 255;
            if (inCircle(sx, sy, circle_x, circle_y, outer_radius)) value = 255;
            if (!solid and inCircle(sx, sy, circle_x, circle_y, inner_radius)) value = 0;
            total += value;
        };
        pixels[y * width + x] = @intCast(total / 16);
    };
}

fn commitLines(index: u32) u8 {
    return switch (index) {
        0 => 0,
        1 => right,
        2 => left,
        3 => left | right,
        4 => bottom,
        5 => top,
        6 => bottom | top,
        7 => right | bottom,
        8 => left | bottom,
        9 => right | top,
        10 => left | top,
        11 => top | bottom | right,
        12 => top | bottom | left,
        13 => left | right | bottom,
        14 => left | right | top,
        15 => left | right | top | bottom,
        else => unreachable,
    };
}

fn circleRadius(cx: u16, cy: u16, gap: u16) i32 {
    const radius_value = 0.9 * @as(f64, @floatFromInt(@min(cx, cy))) -
        @as(f64, @floatFromInt(gap)) / 2.0;
    return @intFromFloat(radius_value);
}

fn inCircle(x: u16, y: u16, cx: u16, cy: u16, radius: i32) bool {
    const limit = @as(f64, @floatFromInt(radius * radius));
    const dx = @as(f64, @floatFromInt(x)) - @as(f64, @floatFromInt(cx));
    const dy = @as(f64, @floatFromInt(y)) - @as(f64, @floatFromInt(cy));
    return dx * dx + dy * dy <= limit;
}

fn inCenteredRange(value: u16, size: u16, center: u16, stroke: u16) bool {
    const range = centeredRange(size, center, stroke);
    return value >= range[0] and value < range[1];
}

fn centeredRange(size: u16, center: u16, stroke: u16) [2]u16 {
    const start = center -| stroke / 2;
    return .{ start, @min(size, start + stroke) };
}

fn fill(pixels: []u8, stride: u16, y1: u16, y2: u16, x1: u16, x2: u16, value: u8) void {
    for (y1..@min(y2, @as(u16, @intCast(pixels.len / stride)))) |y|
        @memset(pixels[y * stride + x1 .. y * stride + @min(x2, stride)], value);
}

fn smoothstep(edge0: f64, edge1: f64, value: f64) f64 {
    if (edge0 == edge1) return if (value < edge0) 0 else 1;
    const t = std.math.clamp((value - edge0) / (edge1 - edge0), 0, 1);
    return t * t * (3 - 2 * t);
}
