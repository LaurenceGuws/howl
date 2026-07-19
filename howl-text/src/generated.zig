//! Classifies and rasterizes the implemented generated terminal glyph families.

const std = @import("std");
const special_block_braille = @import("generated_block.zig");
const special_box = @import("generated_box.zig");
const geometry = @import("generated_geometry.zig");
const special_legacy_computing = @import("generated_legacy.zig");
const special_powerline = @import("generated_powerline.zig");

/// Bounds each generated terminal-cell dimension and stroke to 256 pixels,
/// limiting the most expensive rounded glyph to 6,356,992 curve samples.
pub const max_extent_px: u16 = 256;

/// Reports invalid raster geometry, bounded extent or stroke, insufficient
/// output, or a font-owned glyph.
pub const Error = error{
    InvalidSize,
    RasterTooLarge,
    InvalidStroke,
    BufferTooSmall,
    UnsupportedGlyph,
};

/// Selects the exact generated family implemented for one codepoint.
pub const Glyph = enum {
    box,
    block,
    braille,
    sextant,
    octant,
    powerline,
};

/// Configures bounded box lines with heavy geometry at least as wide as light.
pub const BoxDrawingStroke = geometry.BoxDrawingStroke;

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
/// glyph within the 256-pixel extent bound and leaves trailing output
/// untouched.
pub fn rasterize(pixels: []u8, width_px: u16, height_px: u16, codepoint: u32) Error!void {
    const light = @as(u16, 2);
    try rasterizeWithStroke(pixels, width_px, height_px, codepoint, .{
        .light_stroke_px = light,
        .heavy_stroke_px = light * 2,
    });
}

/// Rasterizes with ordered, bounded light and heavy box-drawing strokes,
/// rejecting invalid input before changing caller-owned output.
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
    @memset(pixels[0..required], 0);
    rasterizeClassified(
        pixels,
        width_px,
        height_px,
        codepoint,
        box_drawing,
        family,
    );
}

fn rasterizeClassified(
    pixels: []u8,
    width: u16,
    height: u16,
    codepoint: u32,
    box_drawing: BoxDrawingStroke,
    family: Glyph,
) void {
    switch (family) {
        .box => special_box.rasterizeGeneratedBoxAlpha(pixels, width, height, codepoint, box_drawing),
        .powerline => special_powerline.rasterizeGeneratedPowerlineAlpha(pixels, width, height, codepoint, box_drawing),
        .block => special_block_braille.rasterizeGeneratedBlockAlpha(pixels, width, height, codepoint),
        .braille => special_block_braille.rasterizeGeneratedBrailleAlpha(pixels, width, height, codepoint),
        .sextant => special_legacy_computing.rasterizeGeneratedSextantAlpha(pixels, width, height, codepoint),
        .octant => special_legacy_computing.rasterizeGeneratedOctantAlpha(pixels, width, height, codepoint),
    }
}
