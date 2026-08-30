//! Projects immutable terminal client views through howl-text into bounded native glyph frames.
//!
//! This layer owns presentation derivation only. It neither parses `text_v1` nor
//! retains terminal truth. Every font metric, shape, source-cluster mapping,
//! glyph identity, and alpha raster comes from `howl-text`.

const std = @import("std");
const client = @import("howl_client");
const text = @import("howl_text");

pub const View = client.view;
pub const TextColor = View.TextColor;
pub const Metrics = text.Metrics;

/// Describes one shaped/rasterized glyph while borrowing frame pixel storage.
pub const Glyph = struct {
    /// Identifies the source terminal row.
    row: u16,
    /// Identifies the source terminal column containing the lead cell.
    column: u16,
    /// Preserves the flat source cell identity from the immutable native view.
    cell_index: u32,
    /// Preserves howl-text/HarfBuzz source-cluster identity as the source scalar offset.
    cluster: u32,
    /// Identifies the selected primary/fallback face.
    face_index: u8,
    /// Identifies the exact native glyph in `face_index`.
    glyph_id: u32,
    /// Locates the shaped pen horizontally in FreeType 26.6 units from the surface origin.
    pen_x_26_6: i64,
    /// Locates the shaped baseline vertically in FreeType 26.6 units from the surface origin.
    baseline_y_26_6: i64,
    /// Preserves HarfBuzz horizontal placement offset.
    x_offset_26_6: i32,
    /// Preserves HarfBuzz vertical placement offset.
    y_offset_26_6: i32,
    /// Preserves HarfBuzz horizontal pen movement.
    x_advance_26_6: i32,
    /// Preserves HarfBuzz vertical pen movement.
    y_advance_26_6: i32,
    /// Locates this glyph's copied alpha bytes inside `Frame.pixels`.
    pixel_offset: usize,
    /// Counts this glyph's tightly packed alpha bytes.
    pixel_count: usize,
    /// Reports the natural raster width.
    raster_width: u16,
    /// Reports the natural raster height.
    raster_height: u16,
    /// Places the natural raster left edge relative to the shaped pen.
    raster_left: i16,
    /// Places the natural raster top edge relative to the baseline.
    raster_top: i16,
    /// Preserves terminal style facts for later presentation policy.
    style_bits: u16,
    /// Preserves terminal foreground semantics without resolving them in text.
    foreground: TextColor,
};

/// Borrows one complete projected glyph frame until caller scratch is reused.
pub const Frame = struct {
    revision: u64,
    terminal_revision: u64,
    rows: u16,
    columns: u16,
    metrics: Metrics,
    glyphs: []const Glyph,
    pixels: []const u8,
};

/// Supplies all bounded caller-owned work/output storage for one projection.
///
/// On failure the scratch contents are unspecified and must be discarded; the
/// immutable input view and howl-text owners remain valid and reusable.
pub const Scratch = struct {
    /// Holds one source-cluster id per scalar in the largest shaped cell.
    clusters: []u32,
    /// Holds one synchronous howl-text shaping result.
    shaped: []text.Glyph,
    /// Holds every projected glyph in this frame.
    glyphs: []Glyph,
    /// Holds copied persistent alpha bytes for the returned frame.
    pixels: []u8,
    /// Bounds one temporary natural howl-text raster before it is copied.
    raster: []u8,
};

pub const Error = error{
    InvalidView,
    ClusterLimit,
    GlyphLimit,
    PixelLimit,
    CoordinateOverflow,
} || text.ShapeError || text.RasterError;

/// Shapes and rasterizes every text-bearing lead cell in one immutable view.
///
/// Cell occupancy, styles, colors, and canonical revision remain owned by the
/// view. This function derives only font presentation facts. Empty and
/// continuation cells produce no glyphs.
pub fn project(
    snapshot: *const View.Snapshot,
    fonts: *text.FontSet,
    shape: *text.ShapeBuffer,
    scratch: Scratch,
) Error!Frame {
    const begin = View.begin(snapshot);
    const rows = View.rows(snapshot);
    const cells = View.cells(snapshot);
    const scalars = View.scalars(snapshot);
    if (rows.len != begin.rows) return error.InvalidView;

    const metrics = fonts.metrics();
    var glyph_used: usize = 0;
    var pixel_used: usize = 0;

    for (rows, 0..) |row, row_index| {
        const first = @as(usize, row.cell_offset);
        const count = @as(usize, row.cell_count);
        const end = std.math.add(usize, first, count) catch return error.InvalidView;
        if (end > cells.len or count != begin.columns) return error.InvalidView;

        for (cells[first..end], 0..) |cell, column| {
            if (cell.scalar_count == 0) continue;
            if (cell.x != 0 or cell.y != 0) return error.InvalidView;

            const scalar_first = @as(usize, cell.scalar_offset);
            const scalar_count = @as(usize, cell.scalar_count);
            const scalar_end = std.math.add(usize, scalar_first, scalar_count) catch
                return error.InvalidView;
            if (scalar_end > scalars.len) return error.InvalidView;
            if (scalar_count > scratch.clusters.len) return error.ClusterLimit;

            for (scratch.clusters[0..scalar_count], 0..) |*cluster, index| {
                const source = std.math.add(usize, scalar_first, index) catch
                    return error.InvalidView;
                if (source > std.math.maxInt(u32)) return error.InvalidView;
                cluster.* = @intCast(source);
            }

            const run = try fonts.shape(
                shape,
                .{
                    .codepoints = scalars[scalar_first..scalar_end],
                    .clusters = scratch.clusters[0..scalar_count],
                },
                scratch.shaped,
            );
            if (run.glyphs.len > scratch.glyphs.len -| glyph_used)
                return error.GlyphLimit;

            const cell_x_px = std.math.mul(
                i64,
                @as(i64, @intCast(column)),
                @as(i64, metrics.advance_width),
            ) catch return error.CoordinateOverflow;
            const line_top_px = std.math.mul(
                i64,
                @as(i64, @intCast(row_index)),
                @as(i64, metrics.line_height),
            ) catch return error.CoordinateOverflow;
            const baseline_px = std.math.add(
                i64,
                line_top_px,
                @as(i64, metrics.baseline),
            ) catch return error.CoordinateOverflow;
            const cell_x_26_6 = std.math.mul(i64, cell_x_px, 64) catch
                return error.CoordinateOverflow;
            const baseline_y_26_6 = std.math.mul(i64, baseline_px, 64) catch
                return error.CoordinateOverflow;

            var pen_x_26_6: i64 = cell_x_26_6;
            var pen_y_26_6: i64 = 0;
            for (run.glyphs) |shaped| {
                var raster_allocator = std.heap.FixedBufferAllocator.init(scratch.raster);
                var raster = try fonts.rasterize(
                    raster_allocator.allocator(),
                    run.face_index,
                    shaped.id,
                );
                defer raster.deinit();

                const pixel_end = std.math.add(usize, pixel_used, raster.pixels.len) catch
                    return error.PixelLimit;
                if (pixel_end > scratch.pixels.len) return error.PixelLimit;
                @memcpy(scratch.pixels[pixel_used..pixel_end], raster.pixels);

                const cell_index = std.math.add(usize, first, column) catch
                    return error.InvalidView;
                if (cell_index > std.math.maxInt(u32)) return error.InvalidView;
                scratch.glyphs[glyph_used] = .{
                    .row = @intCast(row_index),
                    .column = @intCast(column),
                    .cell_index = @intCast(cell_index),
                    .cluster = shaped.cluster,
                    .face_index = run.face_index,
                    .glyph_id = shaped.id,
                    .pen_x_26_6 = pen_x_26_6,
                    .baseline_y_26_6 = std.math.add(i64, baseline_y_26_6, pen_y_26_6) catch
                        return error.CoordinateOverflow,
                    .x_offset_26_6 = shaped.x_offset,
                    .y_offset_26_6 = shaped.y_offset,
                    .x_advance_26_6 = shaped.x_advance,
                    .y_advance_26_6 = shaped.y_advance,
                    .pixel_offset = pixel_used,
                    .pixel_count = raster.pixels.len,
                    .raster_width = raster.width,
                    .raster_height = raster.height,
                    .raster_left = raster.left,
                    .raster_top = raster.top,
                    .style_bits = cell.style_bits,
                    .foreground = cell.foreground,
                };
                glyph_used += 1;
                pixel_used = pixel_end;
                pen_x_26_6 = std.math.add(i64, pen_x_26_6, shaped.x_advance) catch
                    return error.CoordinateOverflow;
                pen_y_26_6 = std.math.add(i64, pen_y_26_6, shaped.y_advance) catch
                    return error.CoordinateOverflow;
            }
        }
    }

    return .{
        .revision = begin.revision,
        .terminal_revision = begin.terminal_revision,
        .rows = begin.rows,
        .columns = begin.columns,
        .metrics = metrics,
        .glyphs = scratch.glyphs[0..glyph_used],
        .pixels = scratch.pixels[0..pixel_used],
    };
}
