//! Exposes terminal run preparation with native text only.

const impl = @import("terminal_text_impl");

/// Selects one exact normal/bold/italic native configuration.
pub const FontStyle = impl.FontStyle;
/// Identifies one terminal font slot and style configuration.
pub const FontKey = impl.FontKey;
/// Supplies ordinary cell metrics without resolving presentation effects.
pub const CellMetrics = impl.CellMetrics;
/// Copies native underline and strike placement for backend draw preparation.
pub const DecorationMetrics = impl.DecorationMetrics;
/// Borrows one complete retained row and affected cell span.
pub const RowInput = impl.RowInput;
/// Identifies one native raster within an exact font map.
pub const NativeGlyphKey = impl.NativeGlyphKey;
/// Identifies exact native raster input.
pub const GlyphKey = impl.GlyphKey;
/// Places one glyph and records its source-cell coverage.
pub const PositionedGlyph = impl.PositionedGlyph;
/// Borrows caller-owned native staging, shaping, and positioned output storage.
pub const NativeScratch = impl.NativeScratch;
/// Stores a borrowed native glyph slice or absent glyph output.
pub const PreparedGlyphs = impl.PreparedGlyphs;
/// Borrows one homogeneous run and preserves its unresolved visual facts.
pub const PreparedRun = impl.PreparedRun;
/// Owns one tightly packed alpha mask.
pub const Raster = impl.Raster;
/// Configures one exact native font tuple.
pub const FontConfig = impl.FontConfig;
/// Retains one normalized factual DPI axis.
pub const Dpi = impl.Dpi;
/// Canonical validated terminal point-size and factual DPI identity.
pub const PointSize = impl.PointSize;
/// Selects pixel or canonical point/DPI native construction.
pub const Size = impl.Size;
/// Reports exact native map validation and construction failure.
pub const FontMapInitError = impl.FontMapInitError;
/// Owns the bounded terminal font tuple map.
pub const FontMap = impl.FontMap;
/// Reports exact run discovery and preparation failure.
pub const PrepareError = impl.PrepareError;
/// Reports exact rasterization failure.
pub const RasterError = impl.RasterError;
/// Discovers and prepares one complete homogeneous native run.
pub const prepareNextRun = impl.prepareNextRunNative;
/// Rasterizes one exact selected native glyph key.
pub const rasterizeGlyph = impl.rasterizeGlyphNative;
