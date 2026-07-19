//! Curates bounded native font loading, shaping, and alpha rasterization.

const std = @import("std");

const font = @import("font.zig");
const generated = @import("generated.zig");

/// Owns one fully loaded ordered native font set.
pub const FontSet = font.FontSet;
/// Borrows explicit paths and pixel height during font-set construction.
pub const Config = font.Config;
/// Carries font-derived terminal cell geometry.
pub const Metrics = font.Metrics;
/// Borrows one bounded Unicode sequence and source-cluster map.
pub const Text = font.Text;
/// Carries one exact HarfBuzz glyph result.
pub const Glyph = font.Glyph;
/// Owns one bounded shaped glyph run.
pub const Run = font.Run;
/// Owns one bounded glyph alpha mask.
pub const Raster = font.Raster;
/// Classifies one implemented generated terminal glyph family.
pub const GeneratedGlyph = generated.Glyph;
/// Names failures while constructing a complete native font set.
pub const InitError = font.InitError;
/// Names failures while shaping one borrowed Unicode sequence.
pub const ShapeError = font.ShapeError;
/// Names failures while rasterizing one native glyph into owned alpha.
pub const RasterError = font.RasterError;
/// Bounds ordered fallback font ownership.
pub const max_fallbacks = font.max_fallbacks;
/// Bounds each copied primary or fallback font path.
pub const max_font_path_bytes = font.max_font_path_bytes;
/// Bounds Unicode scalars in one shaping call.
pub const max_codepoints = font.max_codepoints;
/// Bounds HarfBuzz glyphs returned by one shaping call.
pub const max_glyphs = font.max_glyphs;
/// Bounds one owned alpha mask.
pub const max_raster_bytes = font.max_raster_bytes;
/// Bounds each generated terminal-cell raster dimension and explicit stroke.
pub const max_generated_extent_px = generated.max_extent_px;
/// Names generated-glyph validation failures.
pub const GeneratedError = generated.Error;
/// Classifies only generated terminal glyphs with complete implementations.
pub const classifyGenerated = generated.classify;
/// Rasterizes one generated glyph into a validated caller-owned alpha mask.
pub const rasterizeGenerated = generated.rasterize;
/// Rasterizes one generated glyph with explicit box-line stroke geometry.
pub const rasterizeGeneratedWithStroke = generated.rasterizeWithStroke;
/// Configures generated light and heavy box-line strokes.
pub const BoxDrawingStroke = generated.BoxDrawingStroke;

test {
    try std.testing.expect(font.max_fallbacks == 24);
    try std.testing.expect(generated.classify(0x2500) == .box);
}
