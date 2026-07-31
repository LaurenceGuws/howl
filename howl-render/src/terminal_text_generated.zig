//! Exposes terminal run preparation with generated glyphs only.

const impl = @import("terminal_text_impl");

/// Supplies ordinary cell metrics without resolving presentation effects.
pub const CellMetrics = impl.CellMetrics;
/// Supplies exact generated-box point and DPI configuration.
pub const GeneratedBoxConfig = impl.GeneratedBoxConfig;
/// Copies exact generated-box multicell scale identity.
pub const GeneratedBoxSizing = impl.GeneratedBoxSizing;
/// Retains every byte-affecting generated-box identity fact.
pub const GeneratedStrokeIdentity = impl.GeneratedStrokeIdentity;
/// Borrows one complete retained row and affected cell span.
pub const RowInput = impl.RowInput;
/// Selects pane-local contextual-ligature handling.
pub const LigatureMode = impl.LigatureMode;
/// Identifies one generated raster and ordinary baseline placement.
pub const GeneratedGlyphKey = impl.GeneratedGlyphKey;
/// Identifies exact generated raster input.
pub const GlyphKey = impl.GlyphKey;
/// Places one glyph and records its source-cell coverage.
pub const PositionedGlyph = impl.PositionedGlyph;
/// Stores one inline generated glyph or absent glyph output.
pub const PreparedGlyphs = impl.PreparedGlyphs;
/// Stores one homogeneous run and its unresolved visual facts.
pub const PreparedRun = impl.PreparedRun;
/// Owns one tightly packed alpha mask.
pub const Raster = impl.Raster;
/// Reports exact run discovery and preparation failure.
pub const PrepareError = impl.PrepareError;
/// Reports exact rasterization failure.
pub const RasterError = impl.RasterError;
/// Discovers and prepares one complete homogeneous generated run.
pub const prepareNextRun = impl.prepareNextRunGenerated;
/// Rasterizes one exact selected generated glyph key.
pub const rasterizeGlyph = impl.rasterizeGlyphGenerated;
