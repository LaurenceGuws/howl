//! Owns bounded generated terminal-glyph classification and alpha rasterization.

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
/// glyph within the extent bound and leaves trailing output untouched. Returns
/// `Error.UnsupportedGlyph` for a codepoint without a generated raster family.
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

/// Rasterizes with ordered, bounded light and heavy box-drawing strokes,
/// rejecting invalid input before changing caller-owned output. Returns the
/// exact `Error` member for invalid geometry, stroke, capacity, or glyph input.
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
    switch (family) {
        .box => try generated_box.rasterizeGeneratedBoxAlpha(
            pixels,
            width_px,
            height_px,
            codepoint,
            box_drawing,
        ),
        .powerline => try generated_powerline.rasterizeGeneratedPowerlineAlpha(
            pixels,
            width_px,
            height_px,
            codepoint,
            box_drawing,
        ),
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
