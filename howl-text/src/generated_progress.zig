//! Rasterizes Kitty's generated Fira Code progress and spinner family.

const std = @import("std");
const geometry = @import("generated_geometry.zig");
const BoxDrawingStrokes = geometry.BoxDrawingStrokes;

/// Fills exactly `width × height` caller-owned alpha bytes for one classified
/// U+EE00-U+EE0B glyph. Inputs must carry validated nonzero extents, exact
/// Kitty stroke geometry, and finite positive vertical line width. Failure
/// occurs before mutation; success replaces the complete bounded output.
pub fn rasterize(
    pixels: []u8,
    width: u16,
    height: u16,
    codepoint: u32,
    strokes: BoxDrawingStrokes,
    vertical_line_width: f64,
) error{UnsupportedGlyph}!void {
    switch (codepoint) {
        0xee00...0xee05 => rasterizeProgress(
            pixels,
            width,
            height,
            codepoint,
            // Kitty's progress-bar names are screen-axis coordinates: its
            // horizontal value uses X DPI and its vertical value uses Y DPI.
            strokes.vertical[1],
            strokes.horizontal[1],
        ),
        0xee06 => rasterizeSpinner(pixels, width, height, vertical_line_width, 235, 305),
        0xee07 => rasterizeSpinner(pixels, width, height, vertical_line_width, 270, 390),
        0xee08 => rasterizeSpinner(pixels, width, height, vertical_line_width, 315, 470),
        0xee09 => rasterizeSpinner(pixels, width, height, vertical_line_width, 360, 540),
        0xee0a => rasterizeSpinner(pixels, width, height, vertical_line_width, 80, 220),
        0xee0b => rasterizeSpinner(pixels, width, height, vertical_line_width, 170, 270),
        else => return error.UnsupportedGlyph,
    }
}

fn rasterizeProgress(
    pixels: []u8,
    width: u16,
    height: u16,
    codepoint: u32,
    horizontal: u16,
    vertical: u16,
) void {
    const index = codepoint - 0xee00;
    const segment = index % 3;
    const filled = index >= 3;
    const top_end = @min(height, horizontal + 1);
    const bottom_start = height -| (horizontal + 1);
    fillRect(pixels, width, 0, top_end, 0, width);
    fillRect(pixels, width, bottom_start, height, 0, width);
    if (segment == 0)
        fillRect(pixels, width, 0, height, 0, @min(width, vertical + 1));
    if (segment == 2)
        fillRect(
            pixels,
            width,
            0,
            height,
            width -| (vertical + 1),
            width,
        );
    if (!filled) return;
    const y_start = @min(height, 3 * horizontal);
    const y_end = height -| (3 * horizontal);
    const x_start: u16 = if (segment == 0) @min(width, 3 * vertical) else 0;
    const x_end: u16 = if (segment == 2) width -| (3 * vertical) else width;
    fillRect(pixels, width, y_start, y_end, x_start, x_end);
}

fn fillRect(
    pixels: []u8,
    width: u16,
    y_start: u16,
    y_end: u16,
    x_start: u16,
    x_end: u16,
) void {
    var y = y_start;
    while (y < y_end) : (y += 1)
        @memset(pixels[@as(usize, y) * width + x_start .. @as(usize, y) * width + x_end], 255);
}

fn rasterizeSpinner(
    pixels: []u8,
    width: u16,
    height: u16,
    line_width_raw: f64,
    start_degrees: f64,
    end_degrees: f64,
) void {
    const center_x = @as(f64, @floatFromInt(width)) / 2.0;
    const center_y = @as(f64, @floatFromInt(height)) / 2.0;
    const line_width = @max(1.0, line_width_raw);
    const half_real_line_width = @max(0.5, line_width_raw / 2.0);
    const radius = @max(
        0.0,
        @min(center_x, center_y) - half_real_line_width,
    );
    const radians = std.math.pi / 180.0;
    const start = start_degrees * radians;
    const amount = (end_degrees - start_degrees) * radians;
    const occupied: u16 = @intFromFloat(
        @ceil(radius) + half_real_line_width,
    );
    const leftover = (height -| (2 * occupied + 1)) / 2;
    const y_end = height - leftover;
    const max_step = 1.0 / @as(f64, @floatFromInt(@max(width, height)));
    const min_step = max_step / 1000.0;
    var y = leftover;
    while (y < y_end) : (y += 1) for (0..width) |x| {
        const pixel_x = @as(f64, @floatFromInt(x)) + 0.5;
        const pixel_y = @as(f64, @floatFromInt(y)) + 0.5;
        var minimum = std.math.floatMax(f64);
        var t: f64 = 0;
        while (true) {
            if (t >= 1.0) break;
            const angle = start + amount * t;
            const sample_x = center_x + radius * @cos(angle);
            const sample_y = center_y + radius * @sin(angle);
            const dx = sample_x - pixel_x;
            const dy = sample_y - pixel_y;
            minimum = @min(minimum, dx * dx + dy * dy);
            // Kitty's circle derivatives intentionally omit the arc amount.
            const derivative_x = -radius * @sin(angle);
            const derivative_y = radius * @cos(angle);
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
            line_width / 2.0 - @sqrt(minimum) + 0.5,
            0.0,
            1.0,
        );
        pixels[@as(usize, y) * width + x] = @intFromFloat(alpha * 255.0);
    };
}
