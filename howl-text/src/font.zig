//! Owns explicit font paths, native FT/HB faces, shaping, metrics, and alpha rasters.

const std = @import("std");

const c = @cImport({
    @cInclude("ft2build.h");
    @cInclude("freetype/freetype.h");
    @cInclude("freetype/tttables.h");
    @cInclude("harfbuzz/hb.h");
    @cInclude("harfbuzz/hb-ft.h");
});

/// Bounds ordered fallback ownership independently of host input.
pub const max_fallbacks: u8 = 24;
/// Bounds each copied font path to 4,096 bytes before native library access.
pub const max_font_path_bytes: usize = 4_096;
/// Bounds one shaping call before native library ingestion.
pub const max_codepoints: u32 = 65_536;
/// Bounds one HarfBuzz result before allocation.
pub const max_glyphs: u32 = 65_536;
/// Bounds one owned alpha mask to sixteen MiB.
pub const max_raster_bytes: usize = 16 * 1024 * 1024;
// Four bytes per output pixel admit ordinary native row padding while keeping
// the external bitmap finite before its pointer becomes a slice.
const max_source_bitmap_bytes: usize = max_raster_bytes * 4;
const PixelMode = @TypeOf(@as(c.FT_Bitmap, undefined).pixel_mode);

/// Names construction failures before a complete native font set exists.
pub const InitError = error{
    OutOfMemory,
    InvalidConfig,
    FreeTypeInit,
    FontOpen,
    UnicodeCharmap,
    FontSize,
    HarfBuzzFont,
    InvalidMetrics,
};

/// Names failures while shaping one borrowed Unicode sequence.
pub const ShapeError = error{
    OutOfMemory,
    FontState,
    InvalidText,
    TextTooLong,
    GlyphLimit,
    HarfBuzzBuffer,
    InvalidShapeResult,
    MissingGlyph,
};

/// Names failures while producing one owned native glyph alpha mask.
pub const RasterError = error{
    OutOfMemory,
    FontState,
    InvalidRaster,
    InvalidCellSpan,
    GlyphLoad,
    GlyphRender,
    FontSize,
    UnsupportedPixelMode,
    RasterTooLarge,
    InvalidBitmap,
    InvalidPlacement,
};

/// Borrows one bounded NUL-free primary path, up to 24 bounded NUL-free
/// fallback paths, and a nonzero pixel height during construction.
pub const Config = struct {
    primary: []const u8,
    fallbacks: []const []const u8 = &.{},
    pixel_height: u16,
};

/// Describes validated nonzero font-derived cell geometry. Decoration lines
/// use native font facts when valid and bounded terminal fallbacks otherwise.
pub const Metrics = struct {
    cell_width: u16,
    cell_height: u16,
    baseline: u16,
    underline_y: u16,
    underline_height: u16,
    strike_y: u16,
    strike_height: u16,
};

/// Borrows 1..65,536 valid Unicode scalars and one source-cluster identifier
/// per scalar; `cell_span` describes the nonzero terminal width of the run.
pub const Text = struct {
    codepoints: []const u32,
    clusters: []const u32,
    cell_span: u16,
};

/// Records one exact HarfBuzz glyph, source cluster, and 26.6-position facts.
pub const Glyph = struct {
    id: u32,
    cluster: u32,
    x_advance: i32,
    y_advance: i32,
    x_offset: i32,
    y_offset: i32,
};

/// Owns at most 65,536 glyphs and identifies the selected configured face.
pub const Run = struct {
    allocator: std.mem.Allocator,
    face_index: u8,
    cell_span: u16,
    glyphs: []Glyph,

    /// Releases the owned glyph slice exactly once.
    pub fn deinit(self: *Run) void {
        self.allocator.free(self.glyphs);
        self.* = undefined;
    }
};

/// Owns one tightly packed alpha mask of at most sixteen MiB and validated
/// signed placement relative to the baseline.
pub const Raster = struct {
    allocator: std.mem.Allocator,
    width: u16,
    height: u16,
    left: i16,
    top: i16,
    pixels: []u8,

    /// Releases the owned alpha mask exactly once.
    pub fn deinit(self: *Raster) void {
        self.allocator.free(self.pixels);
        self.* = undefined;
    }
};

const Face = struct {
    path: [:0]u8,
    ft: c.FT_Face,
    hb: *c.hb_font_t,
};

/// Owns copied paths, one FT library, and initialized FT/HB faces in fallback
/// order. Its mutable native faces admit one exclusive caller at a time;
/// methods borrow the owner for the call, and returned values retain no owner
/// state. A failed restoration after temporary raster fitting invalidates
/// shaping and rasterization while preserving exact cleanup through deinit.
pub const FontSet = struct {
    allocator: std.mem.Allocator,
    library: c.FT_Library,
    faces: []Face,
    metrics: Metrics,
    pixel_height: u16,
    usable: bool,

    /// Copies and transactionally opens the complete config. Invalid config,
    /// native initialization, metrics, and allocation failures release all
    /// staged state.
    pub fn init(allocator: std.mem.Allocator, config: Config) InitError!FontSet {
        try validateConfig(config);

        var library: c.FT_Library = undefined;
        if (c.FT_Init_FreeType(&library) != 0) return error.FreeTypeInit;
        errdefer doneLibrary(library);

        const count = config.fallbacks.len + 1;
        const faces = allocator.alloc(Face, count) catch return error.OutOfMemory;
        errdefer allocator.free(faces);
        var loaded: usize = 0;
        errdefer {
            for (faces[0..loaded]) |face| {
                c.hb_font_destroy(face.hb);
                doneFace(face.ft);
                allocator.free(face.path);
            }
        }

        while (loaded < count) : (loaded += 1) {
            const source = if (loaded == 0) config.primary else config.fallbacks[loaded - 1];
            const path = allocator.dupeZ(u8, source) catch return error.OutOfMemory;
            errdefer allocator.free(path);
            var ft: c.FT_Face = undefined;
            if (c.FT_New_Face(library, path.ptr, 0, &ft) != 0) return error.FontOpen;
            errdefer doneFace(ft);
            if (c.FT_Select_Charmap(ft, c.FT_ENCODING_UNICODE) != 0) return error.UnicodeCharmap;
            if (c.FT_Set_Pixel_Sizes(ft, 0, config.pixel_height) != 0) return error.FontSize;
            const hb = try createHbFont(ft);
            faces[loaded] = .{ .path = path, .ft = ft, .hb = hb };
        }

        const metrics = try metricsFromFace(faces[0].ft, config.pixel_height);
        return .{
            .allocator = allocator,
            .library = library,
            .faces = faces,
            .metrics = metrics,
            .pixel_height = config.pixel_height,
            .usable = true,
        };
    }

    /// Exclusively releases every HB font, FT face, copied path, and FT
    /// library after all method borrows end. Independent runs and rasters may
    /// outlive this owner.
    pub fn deinit(self: *FontSet) void {
        for (self.faces) |face| {
            c.hb_font_destroy(face.hb);
            doneFace(face.ft);
            self.allocator.free(face.path);
        }
        self.allocator.free(self.faces);
        doneLibrary(self.library);
        self.* = undefined;
    }

    /// Exclusively borrows the native faces to shape one validated sequence
    /// with the first face covering every scalar. The returned run owns its
    /// glyphs; invalid input, missing coverage, malformed or bounded HB output,
    /// and allocation failure are reported exactly.
    pub fn shape(self: *FontSet, allocator: std.mem.Allocator, text: Text) ShapeError!Run {
        if (!self.usable) return error.FontState;
        try validateText(text);
        const face_index = self.selectFace(text.codepoints) orelse return error.MissingGlyph;
        const face = self.faces[face_index];
        const buffer = try createHbBuffer();
        defer c.hb_buffer_destroy(buffer);
        if (c.hb_buffer_pre_allocate(buffer, @intCast(text.codepoints.len)) == 0)
            return error.HarfBuzzBuffer;
        c.hb_buffer_add_utf32(buffer, text.codepoints.ptr, @intCast(text.codepoints.len), 0, @intCast(text.codepoints.len));
        try requireHbBuffer(buffer);
        c.hb_buffer_guess_segment_properties(buffer);
        try requireHbBuffer(buffer);
        c.hb_shape(face.hb, buffer, null, 0);
        try requireHbBuffer(buffer);

        var info_count: c_uint = 0;
        const infos = c.hb_buffer_get_glyph_infos(buffer, &info_count);
        try requireHbBuffer(buffer);
        var position_count: c_uint = 0;
        const positions = c.hb_buffer_get_glyph_positions(buffer, &position_count);
        try requireHbBuffer(buffer);
        if (info_count != position_count) return error.InvalidShapeResult;
        if (info_count > max_glyphs) return error.GlyphLimit;
        if (info_count > 0 and (infos == null or positions == null))
            return error.HarfBuzzBuffer;
        for (0..info_count) |i| {
            try validateGlyphInfo(infos[i], text.clusters.len);
        }
        const glyphs = allocator.alloc(Glyph, info_count) catch
            return error.OutOfMemory;
        errdefer allocator.free(glyphs);
        for (glyphs, 0..) |*glyph, i| {
            const cp_index: usize = infos[i].cluster;
            glyph.* = .{
                .id = infos[i].codepoint,
                .cluster = text.clusters[cp_index],
                .x_advance = positions[i].x_advance,
                .y_advance = positions[i].y_advance,
                .x_offset = positions[i].x_offset,
                .y_offset = positions[i].y_offset,
            };
        }
        return .{
            .allocator = allocator,
            .face_index = @intCast(face_index),
            .cell_span = text.cell_span,
            .glyphs = glyphs,
        };
    }

    /// Exclusively borrows one native face and rasterizes monochrome or gray
    /// coverage into the requested terminal cell span. Scalable glyphs wider
    /// than that span are proportionally rerendered, while fixed bitmaps are
    /// clipped. Invalid identity, span, native rendering, geometry, placement,
    /// bounds, allocation, and native-size restoration fail exactly. Failed
    /// restoration invalidates later shaping and rasterization on this owner.
    pub fn rasterize(
        self: *FontSet,
        allocator: std.mem.Allocator,
        face_index: u8,
        glyph_id: u32,
        cell_span: u16,
    ) RasterError!Raster {
        if (!self.usable) return error.FontState;
        const maximum_width = std.math.mul(
            u16,
            self.metrics.cell_width,
            cell_span,
        ) catch return error.InvalidCellSpan;
        if (cell_span == 0 or maximum_width == 0) return error.InvalidCellSpan;
        if (face_index >= self.faces.len or glyph_id == 0) return error.InvalidRaster;
        const face = self.faces[face_index].ft;
        var raster = try rasterizeFace(allocator, face, glyph_id);
        errdefer raster.deinit();
        if (raster.width <= maximum_width) return raster;

        if (face.*.face_flags & c.FT_FACE_FLAG_SCALABLE != 0) {
            const scaled_height_u32 = @max(
                @as(u32, 1),
                @as(u32, self.pixel_height) * maximum_width / raster.width,
            );
            const scaled_height = std.math.cast(u16, scaled_height_u32) orelse
                return error.FontSize;
            if (c.FT_Set_Pixel_Sizes(face, 0, scaled_height) != 0)
                return error.FontSize;
            const fit_result = rasterizeFace(allocator, face, glyph_id);
            const restore_error =
                c.FT_Set_Pixel_Sizes(face, 0, self.pixel_height);
            const fitted = try self.finishTemporaryRaster(
                fit_result,
                restore_error,
            );
            raster.deinit();
            raster = fitted;
        }
        if (raster.width > maximum_width)
            try cropRaster(&raster, 0, maximum_width);
        if (raster.left < 0) {
            const clipped = @min(
                raster.width,
                std.math.cast(u16, -@as(i32, raster.left)) orelse
                    raster.width,
            );
            try cropRaster(&raster, clipped, raster.width - clipped);
            raster.left = 0;
        }
        const right = @as(u32, @intCast(raster.left)) + raster.width;
        if (right > maximum_width)
            raster.left = @intCast(maximum_width - raster.width);
        return raster;
    }

    fn finishTemporaryRaster(
        self: *FontSet,
        result: RasterError!Raster,
        restore_error: c.FT_Error,
    ) RasterError!Raster {
        if (restore_error == 0) return result;
        if (result) |value| {
            var owned = value;
            owned.deinit();
        } else |_| {}
        self.usable = false;
        return error.FontState;
    }

    fn selectFace(self: *FontSet, codepoints: []const u32) ?usize {
        for (self.faces, 0..) |face, index| {
            if (faceSupportsSequence(face.hb, codepoints)) return index;
        }
        return null;
    }
};

fn rasterizeFace(
    allocator: std.mem.Allocator,
    face: c.FT_Face,
    glyph_id: u32,
) RasterError!Raster {
    if (c.FT_Load_Glyph(face, glyph_id, c.FT_LOAD_RENDER) != 0) return error.GlyphLoad;
    const slot = face.*.glyph orelse return error.GlyphRender;
    const bitmap = slot.*.bitmap;
    const geometry = try bitmapGeometry(bitmap);
    const placement = try bitmapPlacement(slot.*.bitmap_left, slot.*.bitmap_top);
    const byte_count = try rasterByteCount(geometry.width, geometry.height);
    const pixels = allocator.alloc(u8, byte_count) catch return error.OutOfMemory;
    errdefer allocator.free(pixels);
    if (byte_count > 0) {
        // FreeType owns exactly pitch × rows bytes for a rendered bitmap.
        // `bitmapGeometry` validates and bounds that external extent first.
        const source = geometry.source.?[0..geometry.source_bytes];
        for (0..geometry.height) |y| for (0..geometry.width) |x| {
            pixels[y * geometry.width + x] = try bitmapAlpha(
                source,
                geometry,
                @intCast(x),
                @intCast(y),
            );
        };
    }
    return .{
        .allocator = allocator,
        .width = geometry.width,
        .height = geometry.height,
        .left = placement.left,
        .top = placement.top,
        .pixels = pixels,
    };
}

fn cropRaster(raster: *Raster, source_x: u16, width: u16) RasterError!void {
    const count = try rasterByteCount(width, raster.height);
    const pixels = raster.allocator.alloc(u8, count) catch
        return error.OutOfMemory;
    errdefer raster.allocator.free(pixels);
    for (0..raster.height) |row|
        std.mem.copyForwards(
            u8,
            pixels[row * width ..][0..width],
            raster.pixels[row * raster.width + source_x ..][0..width],
        );
    raster.allocator.free(raster.pixels);
    raster.pixels = pixels;
    raster.width = width;
}

fn validateConfig(config: Config) error{InvalidConfig}!void {
    if (config.pixel_height == 0 or config.fallbacks.len > max_fallbacks)
        return error.InvalidConfig;
    try validatePath(config.primary);
    for (config.fallbacks) |path| try validatePath(path);
}

fn validatePath(path: []const u8) error{InvalidConfig}!void {
    if (path.len == 0 or path.len > max_font_path_bytes or
        std.mem.indexOfScalar(u8, path, 0) != null)
        return error.InvalidConfig;
}

fn faceSupportsSequence(font: *c.hb_font_t, codepoints: []const u32) bool {
    var index: usize = 0;
    while (index < codepoints.len) {
        const base = codepoints[index];
        if (isVariationSelector(base)) return false;
        const selector = if (index + 1 < codepoints.len and
            isVariationSelector(codepoints[index + 1]))
            codepoints[index + 1]
        else
            0;
        var glyph: c.hb_codepoint_t = 0;
        if (c.hb_font_get_glyph(font, base, selector, &glyph) == 0 or glyph == 0)
            return false;
        index += if (selector == 0) 1 else 2;
    }
    return true;
}

fn validateGlyphInfo(
    info: c.hb_glyph_info_t,
    cluster_count: usize,
) error{ MissingGlyph, InvalidShapeResult }!void {
    if (info.codepoint == 0) return error.MissingGlyph;
    if (info.cluster >= cluster_count) return error.InvalidShapeResult;
}

fn validateText(text: Text) error{ InvalidText, TextTooLong }!void {
    if (text.codepoints.len == 0 or text.codepoints.len != text.clusters.len or text.cell_span == 0)
        return error.InvalidText;
    if (text.codepoints.len > max_codepoints) return error.TextTooLong;
    for (text.codepoints) |codepoint| {
        if (codepoint > 0x10ffff or codepoint >= 0xd800 and codepoint <= 0xdfff)
            return error.InvalidText;
    }
}

fn isVariationSelector(codepoint: u32) bool {
    return codepoint >= 0xfe00 and codepoint <= 0xfe0f or
        codepoint >= 0xe0100 and codepoint <= 0xe01ef;
}

fn metricsFromFace(face: c.FT_Face, fallback_height: u16) error{InvalidMetrics}!Metrics {
    const size = face.*.size orelse return error.InvalidMetrics;
    const raw = @field(size.*, "metrics");
    // A face-wide maximum includes patched icon advances; terminal columns
    // follow Kitty's measured printable-ASCII width instead.
    var max_advance: c.FT_Pos = 0;
    var codepoint: u32 = 32;
    while (codepoint < 127) : (codepoint += 1) {
        const id = c.FT_Get_Char_Index(face, codepoint);
        if (id == 0 or c.FT_Load_Glyph(face, id, c.FT_LOAD_DEFAULT) != 0) continue;
        if (face.*.glyph) |slot| max_advance = @max(max_advance, @field(slot.*, "metrics").horiAdvance);
    }
    if (max_advance == 0) max_advance = raw.max_advance;
    if ((face.*.face_flags & c.FT_FACE_FLAG_SCALABLE) == 0)
        return metricsFromExternal(
            raw.height,
            raw.ascender,
            max_advance,
            fallback_height,
        );
    const y_scale = raw.y_scale;
    if (y_scale <= 0) return error.InvalidMetrics;
    const scaled_height = c.FT_MulFix(face.*.height, y_scale);
    const scaled_ascender = c.FT_MulFix(face.*.ascender, y_scale);
    var metrics = try metricsFromExternal(
        scaled_height,
        scaled_ascender,
        max_advance,
        0,
    );
    metrics.cell_height = accommodateUnderscore(
        metrics.cell_height,
        try underscoreBottom(face, metrics.baseline),
    );
    if (lineFromFontUnits(
        face.*.underline_position,
        face.*.underline_thickness,
        y_scale,
        metrics.baseline,
        metrics.cell_height,
    )) |line| {
        metrics.underline_y = line.y;
        metrics.underline_height = line.height;
    }
    if (c.FT_Get_Sfnt_Table(face, c.FT_SFNT_OS2)) |raw_os2| {
        const os2: *const c.TT_OS2 = @ptrCast(@alignCast(raw_os2));
        if (lineFromFontUnits(
            os2.yStrikeoutPosition,
            os2.yStrikeoutSize,
            y_scale,
            metrics.baseline,
            metrics.cell_height,
        )) |line| {
            metrics.strike_y = line.y;
            metrics.strike_height = line.height;
        }
    }
    return metrics;
}

fn accommodateUnderscore(cell_height: u16, underscore_bottom: u16) u16 {
    // A terminal row includes the primary font's underscore even when the
    // font declares a shorter line box.
    return @max(cell_height, underscore_bottom);
}

fn underscoreBottom(
    face: c.FT_Face,
    baseline: u16,
) error{InvalidMetrics}!u16 {
    const id = c.FT_Get_Char_Index(face, '_');
    if (id == 0 or c.FT_Load_Glyph(face, id, c.FT_LOAD_DEFAULT) != 0)
        return 0;
    const slot = face.*.glyph orelse return error.InvalidMetrics;
    const rows = slot.*.bitmap.rows;
    const top = slot.*.bitmap_top;
    if (rows == 0 or top > 0 and top >= baseline) return 0;
    const bottom = std.math.add(
        i64,
        std.math.sub(i64, baseline, top) catch
            return error.InvalidMetrics,
        rows,
    ) catch return error.InvalidMetrics;
    if (bottom < 0 or bottom > std.math.maxInt(u16))
        return error.InvalidMetrics;
    return @intCast(bottom);
}

fn metricsFromExternal(
    raw_height: c.FT_Pos,
    raw_ascender: c.FT_Pos,
    raw_advance: c.FT_Pos,
    fallback_height: u16,
) error{InvalidMetrics}!Metrics {
    const measured_height = try positiveCeil26Dot6(raw_height);
    const height = @max(measured_height, fallback_height);
    if (height == 0) return error.InvalidMetrics;
    const measured_ascender = try nonnegativeCeil26Dot6(raw_ascender);
    if (measured_ascender >= height) return error.InvalidMetrics;
    const width = try positiveCeil26Dot6(raw_advance);
    const thickness: u16 = @max(@min(height / 12, 2), 1);
    return .{
        .cell_width = width,
        .cell_height = height,
        .baseline = measured_ascender,
        .underline_y = @min(measured_ascender + 1, height - 1),
        .underline_height = thickness,
        .strike_y = if (height == 1) 0 else @max(
            @as(u16, @intCast(@as(u32, measured_ascender) * 2 / 3)),
            1,
        ),
        .strike_height = thickness,
    };
}

fn positiveCeil26Dot6(value: c.FT_Pos) error{InvalidMetrics}!u16 {
    if (value <= 0) return error.InvalidMetrics;
    const pixels = try nonnegativeCeil26Dot6(value);
    if (pixels == 0) return error.InvalidMetrics;
    return pixels;
}

fn nonnegativeCeil26Dot6(value: c.FT_Pos) error{InvalidMetrics}!u16 {
    if (value < 0) return error.InvalidMetrics;
    if (value > std.math.maxInt(c.FT_Pos) - 63)
        return error.InvalidMetrics;
    const pixels = @divTrunc(value + 63, 64);
    if (pixels > std.math.maxInt(u16)) return error.InvalidMetrics;
    return @intCast(pixels);
}

const DecorationLine = struct { y: u16, height: u16 };

fn lineFromFontUnits(
    position: c.FT_Short,
    thickness: c.FT_Short,
    y_scale: c.FT_Fixed,
    baseline: u16,
    cell_height: u16,
) ?DecorationLine {
    if (thickness <= 0 or y_scale <= 0) return null;
    const scaled_position = c.FT_MulFix(position, y_scale);
    const scaled_thickness = c.FT_MulFix(thickness, y_scale);
    if (scaled_thickness <= 0) return null;
    const position_px = round26Dot6(scaled_position) orelse return null;
    const thickness_px = ceilPositive26Dot6(scaled_thickness) orelse return null;
    const center = std.math.sub(i64, baseline, position_px) catch return null;
    const top = std.math.sub(
        i64,
        center,
        @divTrunc(thickness_px, 2),
    ) catch return null;
    const bottom = std.math.add(i64, top, thickness_px) catch return null;
    if (top < 0 or bottom > cell_height) return null;
    return .{ .y = @intCast(top), .height = @intCast(thickness_px) };
}

fn round26Dot6(value: c.FT_Long) ?i64 {
    const rounded = std.math.add(
        c.FT_Long,
        value,
        if (value >= 0) 32 else -32,
    ) catch return null;
    return @divTrunc(rounded, 64);
}

fn ceilPositive26Dot6(value: c.FT_Long) ?i64 {
    if (value <= 0 or value > std.math.maxInt(c.FT_Long) - 63) return null;
    return @divTrunc(value + 63, 64);
}

fn rasterByteCount(width: u16, height: u16) error{RasterTooLarge}!usize {
    const byte_count = std.math.mul(usize, width, height) catch
        return error.RasterTooLarge;
    if (byte_count > max_raster_bytes) return error.RasterTooLarge;
    return byte_count;
}

const BitmapGeometry = struct {
    mode: PixelMode,
    num_grays: u16,
    source_height: u16,
    width: u16,
    height: u16,
    pitch: usize,
    negative_pitch: bool,
    source_bytes: usize,
    source: ?[*]const u8,
};

const BitmapGeometryError = error{
    UnsupportedPixelMode,
    RasterTooLarge,
    InvalidBitmap,
};

fn bitmapGeometry(bitmap: c.FT_Bitmap) BitmapGeometryError!BitmapGeometry {
    const mode = bitmap.pixel_mode;
    if (bitmap.width > std.math.maxInt(u16) or bitmap.rows > std.math.maxInt(u16))
        return error.RasterTooLarge;
    const source_width: u16 = @intCast(bitmap.width);
    const source_height: u16 = @intCast(bitmap.rows);
    if (bitmap.buffer == null) {
        if (source_width != 0 and source_height != 0 and bitmap.pitch != 0)
            return error.InvalidBitmap;
        return .{
            .mode = mode,
            .num_grays = bitmap.num_grays,
            .source_height = 0,
            .width = 0,
            .height = 0,
            .pitch = 0,
            .negative_pitch = false,
            .source_bytes = 0,
            .source = null,
        };
    }
    if (source_width == 0 or source_height == 0 or bitmap.pitch == 0) {
        return .{
            .mode = mode,
            .num_grays = bitmap.num_grays,
            .source_height = 0,
            .width = 0,
            .height = 0,
            .pitch = 0,
            .negative_pitch = false,
            .source_bytes = 0,
            .source = null,
        };
    }
    const pitch = try pitchMagnitude(bitmap.pitch);
    const minimum_pitch = try minimumPitch(mode, source_width);
    if (pitch < minimum_pitch) return error.InvalidBitmap;
    const source_bytes = std.math.mul(usize, pitch, source_height) catch
        return error.RasterTooLarge;
    if (source_bytes > max_source_bitmap_bytes) return error.RasterTooLarge;
    if (mode == c.FT_PIXEL_MODE_GRAY and
        (bitmap.num_grays < 2 or bitmap.num_grays > 256))
        return error.InvalidBitmap;
    const buffer_address = @intFromPtr(bitmap.buffer);
    const preceding_bytes = if (bitmap.pitch < 0)
        std.math.mul(usize, pitch, source_height - 1) catch
            return error.RasterTooLarge
    else
        0;
    if (buffer_address <= preceding_bytes) return error.InvalidBitmap;
    const source_address = buffer_address - preceding_bytes;
    if (source_bytes > std.math.maxInt(usize) - source_address)
        return error.InvalidBitmap;
    const source: [*]const u8 = @ptrFromInt(source_address);
    return .{
        .mode = mode,
        .num_grays = bitmap.num_grays,
        .source_height = source_height,
        .width = source_width,
        .height = source_height,
        .pitch = pitch,
        .negative_pitch = bitmap.pitch < 0,
        .source_bytes = source_bytes,
        .source = source,
    };
}

fn minimumPitch(mode: PixelMode, width: u16) error{UnsupportedPixelMode}!usize {
    return switch (mode) {
        c.FT_PIXEL_MODE_MONO => (@as(usize, width) + 7) / 8,
        c.FT_PIXEL_MODE_GRAY => width,
        else => error.UnsupportedPixelMode,
    };
}

fn pitchMagnitude(pitch: c_int) error{InvalidBitmap}!usize {
    if (pitch == std.math.minInt(c_int)) return error.InvalidBitmap;
    const magnitude = if (pitch < 0) -pitch else pitch;
    return @intCast(magnitude);
}

const Placement = struct { left: i16, top: i16 };

fn bitmapPlacement(left: c_int, top: c_int) error{InvalidPlacement}!Placement {
    if (left < std.math.minInt(i16) or left > std.math.maxInt(i16) or
        top < std.math.minInt(i16) or top > std.math.maxInt(i16))
        return error.InvalidPlacement;
    return .{ .left = @intCast(left), .top = @intCast(top) };
}

fn bitmapAlpha(
    bytes: []const u8,
    geometry: BitmapGeometry,
    x: u16,
    y: u16,
) error{InvalidBitmap}!u8 {
    std.debug.assert(bytes.len == geometry.source_bytes);
    std.debug.assert(x < geometry.width and y < geometry.height);
    const source_y = y;
    const row_y = if (geometry.negative_pitch)
        geometry.source_height - 1 - source_y
    else
        source_y;
    const row = bytes[@as(usize, row_y) * geometry.pitch ..][0..geometry.pitch];
    return switch (geometry.mode) {
        c.FT_PIXEL_MODE_MONO => if ((row[x / 8] &
            (@as(u8, 0x80) >> @intCast(x & 7))) != 0) 255 else 0,
        c.FT_PIXEL_MODE_GRAY => grayAlpha(row[x], geometry.num_grays),
        // `bitmapGeometry` rejects every other external pixel mode.
        else => unreachable,
    };
}

fn grayAlpha(value: u8, levels: u16) error{InvalidBitmap}!u8 {
    if (levels < 2 or levels > 256 or value >= levels)
        return error.InvalidBitmap;
    return @intCast((@as(u16, value) * 255) / (levels - 1));
}

fn createHbFont(face: c.FT_Face) error{HarfBuzzFont}!*c.hb_font_t {
    return requireNewHbFont(c.hb_ft_font_create_referenced(face));
}

fn requireNewHbFont(candidate: ?*c.hb_font_t) error{HarfBuzzFont}!*c.hb_font_t {
    const font = candidate orelse return error.HarfBuzzFont;
    if (font == c.hb_font_get_empty()) {
        c.hb_font_destroy(font);
        return error.HarfBuzzFont;
    }
    return font;
}

fn createHbBuffer() error{HarfBuzzBuffer}!*c.hb_buffer_t {
    return requireNewHbBuffer(c.hb_buffer_create());
}

fn requireNewHbBuffer(candidate: ?*c.hb_buffer_t) error{HarfBuzzBuffer}!*c.hb_buffer_t {
    const buffer = candidate orelse return error.HarfBuzzBuffer;
    if (buffer == c.hb_buffer_get_empty() or
        c.hb_buffer_allocation_successful(buffer) == 0)
    {
        c.hb_buffer_destroy(buffer);
        return error.HarfBuzzBuffer;
    }
    return buffer;
}

fn requireHbBuffer(buffer: *c.hb_buffer_t) error{HarfBuzzBuffer}!void {
    if (c.hb_buffer_allocation_successful(buffer) == 0)
        return error.HarfBuzzBuffer;
}

fn doneFace(face: c.FT_Face) void {
    if (c.FT_Done_Face(face) != 0)
        @panic("FreeType rejected an owned face during cleanup");
}

fn doneLibrary(library: c.FT_Library) void {
    if (c.FT_Done_FreeType(library) != 0)
        @panic("FreeType rejected an owned library during cleanup");
}

test "pixel modes decode exact alpha including negative pitch" {
    try expectSyntheticAlpha(&.{0b1000_0000}, c.FT_PIXEL_MODE_MONO, 1, 1, 1, 0, 0, 255);
    try expectSyntheticAlpha(&.{127}, c.FT_PIXEL_MODE_GRAY, 1, 1, 1, 0, 0, 127);
    try expectSyntheticAlpha(&.{ 11, 22 }, c.FT_PIXEL_MODE_GRAY, 1, 2, -1, 0, 0, 22);
}

test "nonstandard gray levels normalize or reject exact samples" {
    try std.testing.expectEqual(@as(u8, 255), try grayAlpha(15, 16));
    try std.testing.expectEqual(@as(u8, 136), try grayAlpha(8, 16));
    try std.testing.expectError(error.InvalidBitmap, grayAlpha(16, 16));
    try std.testing.expectError(error.InvalidBitmap, grayAlpha(0, 1));
}

test "bitmap geometry rejects hostile external facts before slicing" {
    var byte: u8 = 0;
    const pointer: [*]u8 = @ptrCast(&byte);
    try expectBitmapError(error.UnsupportedPixelMode, 0, 1, 1, 1, pointer);
    try expectBitmapError(error.InvalidBitmap, c.FT_PIXEL_MODE_GRAY, 2, 1, 1, pointer);
    try expectBitmapError(error.UnsupportedPixelMode, c.FT_PIXEL_MODE_GRAY2, 1, 1, 1, pointer);
    try expectBitmapError(error.UnsupportedPixelMode, c.FT_PIXEL_MODE_GRAY4, 1, 1, 1, pointer);
    try expectBitmapError(error.UnsupportedPixelMode, c.FT_PIXEL_MODE_LCD, 3, 1, 3, pointer);
    try expectBitmapError(error.UnsupportedPixelMode, c.FT_PIXEL_MODE_LCD_V, 1, 3, 1, pointer);
    try expectBitmapError(error.UnsupportedPixelMode, c.FT_PIXEL_MODE_BGRA, 1, 1, 4, pointer);
    try expectBitmapError(error.InvalidBitmap, c.FT_PIXEL_MODE_GRAY, 1, 1, std.math.minInt(c_int), pointer);
    try expectBitmapError(error.InvalidBitmap, c.FT_PIXEL_MODE_GRAY, 1, 1, 1, null);
    try expectBitmapError(
        error.RasterTooLarge,
        c.FT_PIXEL_MODE_GRAY,
        std.math.maxInt(u16),
        std.math.maxInt(u16),
        std.math.maxInt(c_int),
        pointer,
    );

    const empty = syntheticBitmap(c.FT_PIXEL_MODE_NONE, 1, 0, 0, null);
    const empty_geometry = try bitmapGeometry(empty);
    try std.testing.expectEqual(@as(usize, 0), empty_geometry.source_bytes);

    var bad_grays = syntheticBitmap(c.FT_PIXEL_MODE_GRAY, 1, 1, 1, pointer);
    bad_grays.num_grays = 1;
    try std.testing.expectError(error.InvalidBitmap, bitmapGeometry(bad_grays));

    const impossible_negative = syntheticBitmap(
        c.FT_PIXEL_MODE_GRAY,
        1,
        2,
        -1,
        @ptrFromInt(1),
    );
    try std.testing.expectError(
        error.InvalidBitmap,
        bitmapGeometry(impossible_negative),
    );

    const impossible_extent = syntheticBitmap(
        c.FT_PIXEL_MODE_GRAY,
        1,
        1,
        1,
        @ptrFromInt(std.math.maxInt(usize)),
    );
    try std.testing.expectError(
        error.InvalidBitmap,
        bitmapGeometry(impossible_extent),
    );
}

test "metrics and placement reject every narrowing boundary" {
    const metrics = try metricsFromExternal(20 * 64, 15 * 64, 9 * 64, 18);
    try std.testing.expectEqual(@as(u16, 20), metrics.cell_height);
    const rounded = try metricsFromExternal(64 + 1, 1, 64 + 1, 1);
    try std.testing.expectEqual(@as(u16, 2), rounded.cell_height);
    try std.testing.expectEqual(@as(u16, 1), rounded.baseline);
    try std.testing.expectEqual(@as(u16, 2), rounded.cell_width);
    const underline = lineFromFontUnits(-125, 50, 75_497, 20, 25).?;
    try std.testing.expectEqual(@as(u16, 22), underline.y);
    try std.testing.expectEqual(@as(u16, 1), underline.height);
    try std.testing.expect(lineFromFontUnits(-125, 0, 75_497, 20, 25) == null);
    try std.testing.expect(lineFromFontUnits(
        std.math.maxInt(c.FT_Short),
        std.math.maxInt(c.FT_Short),
        std.math.maxInt(c.FT_Fixed),
        20,
        25,
    ) == null);
    try std.testing.expectError(error.InvalidMetrics, metricsFromExternal(-1, 0, 64, 18));
    try std.testing.expectError(error.InvalidMetrics, metricsFromExternal(1, 1, 64, 1));
    try std.testing.expectError(error.InvalidMetrics, metricsFromExternal(64, 64, 64, 1));
    try std.testing.expectError(
        error.InvalidMetrics,
        metricsFromExternal(
            @as(c.FT_Pos, std.math.maxInt(u16)) * 64 + 1,
            0,
            64,
            1,
        ),
    );
    try std.testing.expectError(
        error.InvalidMetrics,
        metricsFromExternal(std.math.maxInt(c.FT_Pos), 0, 64, 1),
    );
    try std.testing.expectEqual(
        @as(u16, 25),
        accommodateUnderscore(24, 25),
    );
    try std.testing.expectEqual(
        @as(u16, 24),
        accommodateUnderscore(24, 23),
    );
    try std.testing.expectError(error.InvalidPlacement, bitmapPlacement(
        @as(c_int, std.math.maxInt(i16)) + 1,
        0,
    ));
    try std.testing.expectError(error.InvalidPlacement, bitmapPlacement(
        0,
        @as(c_int, std.math.minInt(i16)) - 1,
    ));
}

test "native metric extraction is stable without allocator input" {
    const fonts = @import("test_fonts");
    var set = try FontSet.init(std.testing.allocator, .{
        .primary = fonts.primary_font,
        .pixel_height = 18,
    });
    defer set.deinit();
    const first = try metricsFromFace(set.faces[0].ft, 18);
    const second = try metricsFromFace(set.faces[0].ft, 18);
    try std.testing.expectEqualDeep(set.metrics, first);
    try std.testing.expectEqualDeep(first, second);
}

test "normal FreeType owner produces only retained monochrome and gray modes" {
    const fonts = @import("test_fonts");
    const cases = .{
        .{ fonts.primary_font, c.FT_PIXEL_MODE_GRAY },
        .{ fonts.mono_font, c.FT_PIXEL_MODE_MONO },
    };
    inline for (cases) |case| {
        var set = try FontSet.init(std.testing.allocator, .{
            .primary = case[0],
            .pixel_height = if (case[1] == c.FT_PIXEL_MODE_MONO) 16 else 18,
        });
        defer set.deinit();
        const glyph_id = c.FT_Get_Char_Index(set.faces[0].ft, 'A');
        var raster = try set.rasterize(std.testing.allocator, 0, glyph_id, 1);
        raster.deinit();
        const slot = set.faces[0].ft.*.glyph orelse return error.TestUnexpectedResult;
        try std.testing.expectEqual(@as(PixelMode, case[1]), slot.*.bitmap.pixel_mode);
    }
}

test "Nerd icon native bitmap exceeds one cell before bounded reraster" {
    const fonts = @import("test_fonts");
    var set = try FontSet.init(std.testing.allocator, .{
        .primary = fonts.symbol_font,
        .pixel_height = 18,
    });
    defer set.deinit();
    const glyph_id = c.FT_Get_Char_Index(set.faces[0].ft, 0xf303);
    var native = try rasterizeFace(
        std.testing.allocator,
        set.faces[0].ft,
        glyph_id,
    );
    defer native.deinit();
    try std.testing.expect(
        native.left < 0 or
            @as(i32, native.left) + native.width > set.metrics.cell_width,
    );
}

test "failed size restoration invalidates native use and preserves cleanup" {
    const fonts = @import("test_fonts");
    var set = try FontSet.init(std.testing.allocator, .{
        .primary = fonts.symbol_font,
        .pixel_height = 18,
    });
    defer set.deinit();
    const pixels = try std.testing.allocator.alloc(u8, 1);
    const fitted = Raster{
        .allocator = std.testing.allocator,
        .width = 1,
        .height = 1,
        .left = 0,
        .top = 1,
        .pixels = pixels,
    };
    try std.testing.expectError(
        error.FontState,
        set.finishTemporaryRaster(fitted, 1),
    );
    try std.testing.expect(!set.usable);
    try std.testing.expectError(error.FontState, set.shape(
        std.testing.allocator,
        .{
            .codepoints = &.{'A'},
            .clusters = &.{0},
            .cell_span = 1,
        },
    ));
    try std.testing.expectError(
        error.FontState,
        set.rasterize(std.testing.allocator, 0, 1, 1),
    );
}

test "HarfBuzz empty sentinels are rejected as failed owners" {
    try std.testing.expectError(error.HarfBuzzFont, requireNewHbFont(
        c.hb_font_get_empty(),
    ));
    try std.testing.expectError(error.HarfBuzzBuffer, requireNewHbBuffer(
        c.hb_buffer_get_empty(),
    ));
}

test "shaped missing glyph and cluster failures remain distinct" {
    var info = std.mem.zeroes(c.hb_glyph_info_t);
    try std.testing.expectError(error.MissingGlyph, validateGlyphInfo(info, 1));
    info.codepoint = 1;
    info.cluster = 1;
    try std.testing.expectError(error.InvalidShapeResult, validateGlyphInfo(info, 1));
    info.cluster = 0;
    try validateGlyphInfo(info, 1);
}

test "raster byte bound rejects hostile dimensions exactly" {
    try std.testing.expectEqual(@as(usize, 4096), try rasterByteCount(64, 64));
    try std.testing.expectError(error.RasterTooLarge, rasterByteCount(
        std.math.maxInt(u16),
        std.math.maxInt(u16),
    ));
}

fn expectSyntheticAlpha(
    bytes: []const u8,
    mode: PixelMode,
    width: c_uint,
    height: c_uint,
    pitch: c_int,
    x: u16,
    y: u16,
    expected: u8,
) !void {
    const row_offset: usize = if (pitch < 0)
        @as(usize, @intCast(height - 1)) * @as(usize, @intCast(-pitch))
    else
        0;
    const bitmap = syntheticBitmap(
        mode,
        width,
        height,
        pitch,
        @constCast(bytes.ptr + row_offset),
    );
    const geometry = try bitmapGeometry(bitmap);
    try std.testing.expectEqual(@intFromPtr(bytes.ptr), @intFromPtr(geometry.source.?));
    try std.testing.expectEqual(expected, try bitmapAlpha(bytes, geometry, x, y));
}

fn expectBitmapError(
    expected: BitmapGeometryError,
    mode: PixelMode,
    width: c_uint,
    height: c_uint,
    pitch: c_int,
    buffer: ?[*]u8,
) !void {
    const bitmap = syntheticBitmap(mode, width, height, pitch, buffer);
    try std.testing.expectError(expected, bitmapGeometry(bitmap));
}

fn syntheticBitmap(
    mode: PixelMode,
    width: c_uint,
    height: c_uint,
    pitch: c_int,
    buffer: ?[*]u8,
) c.FT_Bitmap {
    var bitmap = std.mem.zeroes(c.FT_Bitmap);
    bitmap.pixel_mode = mode;
    bitmap.width = width;
    bitmap.rows = height;
    bitmap.pitch = pitch;
    bitmap.buffer = buffer;
    bitmap.num_grays = if (mode == c.FT_PIXEL_MODE_GRAY) 256 else 0;
    return bitmap;
}
