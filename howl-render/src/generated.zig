//! Owns bounded generated terminal-glyph classification and alpha rasterization.

const std = @import("std");
const generated_block = @import("generated_block.zig");
const generated_box = @import("generated_box.zig");
const generated_geometry = @import("generated_geometry.zig");
const generated_legacy = @import("generated_legacy.zig");
const generated_powerline = @import("generated_powerline.zig");

/// Bounds each generated terminal-cell dimension and stroke to 256 pixels,
/// limiting the most expensive rounded glyph to 6,356,992 curve samples.
pub const max_extent_px: u16 = 256;

/// Reports invalid generated-raster geometry, bounds, output, or identity.
pub const Error = error{
    InvalidSize,
    RasterTooLarge,
    InvalidStroke,
    InvalidMetrics,
    BufferTooSmall,
    UnsupportedGlyph,
};

/// Classifies one implemented generated terminal glyph family.
pub const Glyph = enum {
    box,
    block,
    braille,
    sextant,
    octant,
    powerline,
};

/// Configures bounded box lines with heavy geometry at least as wide as light.
pub const BoxDrawingStroke = generated_geometry.BoxDrawingStroke;
const BoxDrawingStrokes = generated_geometry.BoxDrawingStrokes;

/// Owns one normalized exact factual DPI axis for generated geometry.
pub const Dpi = packed struct(u64) {
    /// Retains the positive numerator of one normalized factual DPI axis.
    numerator: u32,
    /// Retains the positive denominator of one normalized factual DPI axis.
    denominator: u32,

    fn validate(self: Dpi) Error!void {
        if (self.numerator == 0 or self.denominator == 0 or
            std.math.gcd(self.numerator, self.denominator) != 1)
            return error.InvalidMetrics;
    }
};

/// Retains Kitty's four canonical binary32 box-stroke point levels.
pub const BoxDrawingConfig = struct {
    /// Matches Kitty's default `box_drawing_scale` configuration.
    stroke_points: [4]f32 = .{ 0.001, 1.0, 1.5, 2.0 },
    /// Supplies factual horizontal DPI.
    dpi_x: Dpi,
    /// Supplies factual vertical DPI.
    dpi_y: Dpi,

    fn validate(self: BoxDrawingConfig) Error!void {
        try self.dpi_x.validate();
        try self.dpi_y.validate();
        for (self.stroke_points) |points| {
            if (!std.math.isFinite(points) or points <= 0)
                return error.InvalidMetrics;
        }
    }
};

/// Copies exact Kitty OSC 66 scale facts into generated-raster identity.
pub const BoxDrawingSizing = packed struct(u16) {
    /// Carries the nonzero integer multicell height scale.
    scale: u8 = 1,
    /// Carries an optional proper fractional numerator.
    subscale_n: u4 = 0,
    /// Carries an optional proper fractional denominator.
    subscale_d: u4 = 0,

    fn validate(self: BoxDrawingSizing) Error!void {
        if (self.scale == 0) return error.InvalidMetrics;
        if ((self.subscale_n == 0) != (self.subscale_d == 0) or
            self.subscale_n > 0 and self.subscale_n >= self.subscale_d)
            return error.InvalidMetrics;
    }
};

/// Returns a family only when its complete local raster implementation exists.
pub fn classify(codepoint: u32) ?Glyph {
    return switch (codepoint) {
        0x2500...0x257f => .box,
        0x2580...0x259f => .block,
        0x2800...0x28ff => .braille,
        0x1fb00...0x1fb3b => .sextant,
        0x1cd00...0x1cde5, 0x1fbe6, 0x1fbe7 => .octant,
        0xe0b0...0xe0bf, 0xe0d6...0xe0d7 => .powerline,
        else => null,
    };
}

/// Fills exactly `width_px × height_px` caller-owned bytes for one implemented
/// non-box glyph and leaves trailing output untouched. Unicode box drawing
/// requires `rasterizeBox` because factual metrics are identity authority.
pub fn rasterize(
    pixels: []u8,
    width_px: u16,
    height_px: u16,
    codepoint: u32,
) Error!void {
    const light: u16 = 2;
    try rasterizeWithStroke(pixels, width_px, height_px, codepoint, .{
        .light_stroke_px = light,
        .heavy_stroke_px = light * 2,
    });
}

/// Preserves the existing bounded stroke pair for non-box generated families.
/// Unicode box drawing rejects here and requires `rasterizeBox`.
pub fn rasterizeWithStroke(
    pixels: []u8,
    width_px: u16,
    height_px: u16,
    codepoint: u32,
    box_drawing: BoxDrawingStroke,
) Error!void {
    if (width_px == 0 or height_px == 0) return error.InvalidSize;
    if (width_px > max_extent_px or height_px > max_extent_px)
        return error.RasterTooLarge;
    if (box_drawing.light_stroke_px == 0 or box_drawing.heavy_stroke_px == 0 or
        box_drawing.light_stroke_px > max_extent_px or
        box_drawing.heavy_stroke_px > max_extent_px or
        box_drawing.heavy_stroke_px < box_drawing.light_stroke_px)
        return error.InvalidStroke;
    const required = @as(usize, width_px) * height_px;
    if (pixels.len < required) return error.BufferTooSmall;
    const family = classify(codepoint) orelse return error.UnsupportedGlyph;
    if (family == .box) return error.InvalidMetrics;
    if (codepoint == 0xe0b1) return error.InvalidMetrics;
    @memset(pixels[0..required], 0);
    switch (family) {
        .box => unreachable,
        .powerline => switch (codepoint) {
            0xe0b0, 0xe0b4 => try generated_powerline
                .rasterizeGeneratedPowerlineAlphaMetricFree(
                pixels,
                width_px,
                height_px,
                codepoint,
            ),
            0xe0b1 => unreachable,
            else => try generated_powerline.rasterizeGeneratedPowerlineAlpha(
                pixels,
                width_px,
                height_px,
                codepoint,
                box_drawing,
            ),
        },
        .block => try generated_block.rasterizeGeneratedBlockAlpha(
            pixels,
            width_px,
            height_px,
            codepoint,
        ),
        .braille => try generated_block.rasterizeGeneratedBrailleAlpha(
            pixels,
            width_px,
            height_px,
            codepoint,
        ),
        .sextant => try generated_legacy.rasterizeGeneratedSextantAlpha(
            pixels,
            width_px,
            height_px,
            codepoint,
        ),
        .octant => try generated_legacy.rasterizeGeneratedOctantAlpha(
            pixels,
            width_px,
            height_px,
            codepoint,
        ),
    }
}

/// Rasterizes only Unicode box drawing from exact Kitty point, DPI, and
/// multicell scale facts. All validation and derivation precede output mutation.
pub fn rasterizeBox(
    pixels: []u8,
    width_px: u16,
    height_px: u16,
    codepoint: u32,
    config: BoxDrawingConfig,
    sizing: BoxDrawingSizing,
) Error!void {
    if (width_px == 0 or height_px == 0) return error.InvalidSize;
    if (width_px > max_extent_px or height_px > max_extent_px)
        return error.RasterTooLarge;
    if (codepoint < 0x2500 or codepoint > 0x257f)
        return error.UnsupportedGlyph;
    const required = @as(usize, width_px) * height_px;
    if (pixels.len < required) return error.BufferTooSmall;
    const strokes = try deriveBoxDrawingStrokes(config, sizing);
    @memset(pixels[0..required], 0);
    try generated_box.rasterizeGeneratedBoxAlphaExact(
        pixels,
        width_px,
        height_px,
        codepoint,
        strokes,
    );
}

/// Rasterizes the proven metric-sensitive Kitty Powerline glyph from exact
/// point, DPI, and multicell scale facts. Other Powerline glyphs reject.
pub fn rasterizePowerline(
    pixels: []u8,
    width_px: u16,
    height_px: u16,
    codepoint: u32,
    config: BoxDrawingConfig,
    sizing: BoxDrawingSizing,
) Error!void {
    if (width_px == 0 or height_px == 0) return error.InvalidSize;
    if (width_px > max_extent_px or height_px > max_extent_px)
        return error.RasterTooLarge;
    if (codepoint != 0xe0b1) return error.UnsupportedGlyph;
    const required = @as(usize, width_px) * height_px;
    if (pixels.len < required) return error.BufferTooSmall;
    const strokes = try deriveBoxDrawingStrokes(config, sizing);
    @memset(pixels[0..required], 0);
    try generated_powerline.rasterizeGeneratedPowerlineAlphaWithStrokes(
        pixels,
        width_px,
        height_px,
        codepoint,
        strokes,
    );
}

fn deriveBoxDrawingStrokes(
    config: BoxDrawingConfig,
    sizing: BoxDrawingSizing,
) Error!BoxDrawingStrokes {
    try config.validate();
    try sizing.validate();
    var scale: f32 = @floatFromInt(sizing.scale);
    if (sizing.subscale_n > 0) {
        scale *= @as(f32, @floatFromInt(sizing.subscale_n)) /
            @as(f32, @floatFromInt(sizing.subscale_d));
    }
    var result: BoxDrawingStrokes = undefined;
    for (config.stroke_points, 0..) |points, level| {
        result.horizontal[level] = try thickness(points, config.dpi_y, scale, 1);
        result.vertical[level] = try thickness(points, config.dpi_x, scale, 1);
        result.horizontal_supersampled[level] =
            try thickness(points, config.dpi_y, scale, 4);
        result.vertical_supersampled[level] =
            try thickness(points, config.dpi_x, scale, 4);
    }
    return result;
}

fn thickness(points: f32, dpi: Dpi, scale: f32, supersample: u8) Error!u16 {
    const value = @ceil(
        @as(f64, @floatFromInt(supersample)) *
            @as(f64, scale) *
            @as(f64, points) *
            @as(f64, @floatFromInt(dpi.numerator)) /
            @as(f64, @floatFromInt(dpi.denominator)) /
            72.0,
    );
    if (!std.math.isFinite(value) or value <= 0 or value > max_extent_px * 4)
        return error.InvalidStroke;
    return @intFromFloat(value);
}
