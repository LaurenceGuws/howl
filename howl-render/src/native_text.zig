//! Owns reusable native font loading, metrics, shaping, and alpha rasterization.

const std = @import("std");

const c = @import("native_c");

// Public bounds, failures, and owned text values.

/// Bounds fallback paths supplied by one construction config.
pub const max_fallbacks: u8 = 24;
/// Bounds each copied font path to 4,096 bytes before native library access.
pub const max_font_path_bytes: usize = 4_096;
/// Bounds one shaping call before native library ingestion.
pub const max_codepoints: u32 = 65_536;
/// Bounds one HarfBuzz result before allocation.
pub const max_glyphs: u32 = 65_536;
/// Bounds one owned alpha mask to sixteen MiB.
pub const max_raster_bytes: usize = 16 * 1024 * 1024;
// Four bytes per output pixel allow ordinary native row padding while keeping
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
    FontState,
    InvalidText,
    TextTooLong,
    GlyphLimit,
    InsufficientShapeBuffer,
    InsufficientGlyphs,
    HarfBuzzBuffer,
    InvalidShapeResult,
    InvalidGlyphIdentity,
    MissingGlyph,
};

/// Names invalid or unavailable reusable native shaping storage.
pub const ShapeBufferInitError = error{ InvalidCapacity, HarfBuzzBuffer };

/// Names failures while producing one owned native glyph alpha mask.
pub const RasterError = error{
    OutOfMemory,
    FontState,
    InvalidRaster,
    InvalidWidth,
    GlyphLoad,
    GlyphRender,
    FontSize,
    UnsupportedPixelMode,
    RasterTooLarge,
    InvalidBitmap,
    InvalidPlacement,
};

/// Names exact failures while measuring one selected glyph for symbol span.
pub const GlyphWidthError = error{
    FontState,
    InvalidRaster,
    GlyphLoad,
    InvalidMetrics,
};

/// Names exact native facts required by Kitty ligature grouping.
pub const GroupError = ShapeError || error{ GlyphLoad, InvalidRaster };

/// Owns one normalized positive rational factual DPI value.
pub const Dpi = struct {
    numerator: u32,
    denominator: u32,

    /// Validates nonzero reduced storage before native conversion.
    pub fn validate(self: Dpi) error{InvalidConfig}!void {
        if (self.numerator == 0 or self.denominator == 0 or
            std.math.gcd(self.numerator, self.denominator) != 1)
            return error.InvalidConfig;
    }
};

/// Preserves one canonical point-size and factual DPI construction identity.
pub const PointSize = struct {
    points: f64,
    dpi_x: Dpi,
    dpi_y: Dpi,

    /// Validates every canonical and derived FreeType/metric input.
    pub fn validate(self: PointSize) error{InvalidConfig}!void {
        const height_26_6 = try pointHeight26Dot6(self);
        const dpi_x = try dpiArgument(self.dpi_x);
        const dpi_y = try dpiArgument(self.dpi_y);
        const nominal_height = try pointNominalPixelHeight(height_26_6, dpi_y);
        std.debug.assert(height_26_6 > 0);
        std.debug.assert(dpi_x > 0);
        std.debug.assert(nominal_height > 0);
    }
};

/// Separates independent pixel-configured users from terminal point/DPI users.
pub const Size = union(enum) {
    pixels: u16,
    points: PointSize,
};

/// Borrows one bounded NUL-free primary path, up to 24 bounded NUL-free
/// fallback paths, and one exact native size during construction.
pub const Config = struct {
    /// Borrows the required primary font path for construction only.
    primary: []const u8,
    /// Borrows ordered fallback font paths for construction only.
    fallbacks: []const []const u8 = &.{},
    /// Selects an independent pixel size or a canonical terminal point/DPI size.
    size: Size,
};

/// Describes validated nonzero font-derived text geometry. Decoration lines
/// use native font facts when valid and bounded configured fallbacks otherwise.
pub const Metrics = struct {
    /// Reports the nonzero nominal horizontal advance in pixels.
    advance_width: u16,
    /// Reports the nonzero nominal line height in pixels.
    line_height: u16,
    /// Locates the baseline from the line's top edge.
    baseline: u16,
    /// Locates the underline from the line's top edge.
    underline_y: u16,
    /// Reports the nonzero underline thickness.
    underline_height: u16,
    /// Locates the strike line from the line's top edge.
    strike_y: u16,
    /// Reports the nonzero strike-line thickness.
    strike_height: u16,
};

/// Borrows 1..65,536 valid Unicode scalars and one source-cluster identifier
/// per scalar.
pub const Text = struct {
    /// Borrows valid Unicode scalar values for the shaping call.
    codepoints: []const u32,
    /// Borrows one caller-owned source identity per codepoint.
    clusters: []const u32,
};

/// Records one exact HarfBuzz glyph, source cluster, and 26.6-position facts.
pub const Glyph = struct {
    /// Identifies the selected native face glyph.
    id: u32,
    /// Retains the caller's source identity for this glyph.
    cluster: u32,
    /// Retains HarfBuzz's exact scalar index before caller cluster mapping.
    scalar_index: u32 = 0,
    /// Reports horizontal pen movement in FreeType 26.6 units.
    x_advance: i32,
    /// Reports vertical pen movement in FreeType 26.6 units.
    y_advance: i32,
    /// Reports horizontal placement offset in FreeType 26.6 units.
    x_offset: i32,
    /// Reports vertical placement offset in FreeType 26.6 units.
    y_offset: i32,
};

/// Owns one bounded reusable HarfBuzz buffer for synchronous shaping.
pub const ShapeBuffer = struct {
    /// Owns the nonempty native buffer until `deinit`.
    handle: *c.hb_buffer_t,
    /// Bounds accepted input scalars and retained shaping output.
    capacity: u32,

    /// Requests native storage once for up to `capacity` shaped glyphs.
    /// HarfBuzz owns its internal allocation behavior; Howl rejects input or
    /// output beyond this accepted ceiling.
    pub fn init(capacity: u32) ShapeBufferInitError!ShapeBuffer {
        if (capacity == 0 or capacity > max_glyphs) return error.InvalidCapacity;
        const handle = try createHbBuffer();
        errdefer c.hb_buffer_destroy(handle);
        if (c.hb_buffer_pre_allocate(handle, capacity) == 0)
            return error.HarfBuzzBuffer;
        return .{ .handle = handle, .capacity = capacity };
    }

    /// Releases the sole native buffer and invalidates the owner.
    pub fn deinit(self: *ShapeBuffer) void {
        c.hb_buffer_destroy(self.handle);
        self.* = undefined;
    }
};

/// Borrows caller storage containing one complete bounded shaping result.
pub const Run = struct {
    /// Identifies the primary or ordered fallback face used for the whole run.
    face_index: u8,
    /// Borrows the initialized prefix of caller-owned glyph storage.
    glyphs: []const Glyph,
};

/// Owns one tightly packed alpha mask of at most sixteen MiB and validated
/// signed placement relative to the baseline.
pub const Raster = struct {
    /// Retains the allocator that owns `pixels`.
    allocator: std.mem.Allocator,
    /// Reports tightly packed mask width in pixels.
    width: u16,
    /// Reports tightly packed mask height in pixels.
    height: u16,
    /// Places the mask left edge relative to the shaped pen.
    left: i16,
    /// Places the mask top edge relative to the text baseline.
    top: i16,
    /// Owns `width × height` alpha bytes.
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
    spacer_strategy: SpacerStrategy = .unknown,
};

/// Identifies Kitty's detected empty-glyph placement convention.
pub const SpacerStrategy = enum {
    unknown,
    before,
    after,
    iosevka,
};

/// Classifies variable-length ligature glyph-name components.
pub const LigatureType = enum {
    unknown,
    start,
    middle,
    end,
};

// Native font construction, shaping, and rasterization.

/// Owns copied paths, one FT library, and initialized FT/HB faces in fallback
/// order. Its mutable native faces support one exclusive caller at a time;
/// methods borrow the owner for the call, and returned values retain no owner
/// state. A failed restoration after temporary raster fitting invalidates
/// shaping and rasterization while preserving exact cleanup through deinit.
pub const FontSet = struct {
    /// Owns all Zig allocations retained by this font set.
    allocator: std.mem.Allocator,
    /// Owns the initialized FreeType library until `deinit`.
    library: c.FT_Library,
    /// Owns ordered copied paths and initialized FreeType/HarfBuzz faces.
    faces: []Face,
    /// Retains validated font metrics for the configured size.
    metrics: Metrics,
    /// Retains the exact accepted construction identity for restoration.
    size: Size,
    /// Prevents native reuse after an unrecoverable size-restoration failure.
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
            const path = allocator.dupeSentinel(u8, source, 0) catch return error.OutOfMemory;
            errdefer allocator.free(path);
            var ft: c.FT_Face = undefined;
            if (c.FT_New_Face(library, path.ptr, 0, &ft) != 0) return error.FontOpen;
            errdefer doneFace(ft);
            if (c.FT_Select_Charmap(ft, c.FT_ENCODING_UNICODE) != 0) return error.UnicodeCharmap;
            try setConfiguredSize(ft, config.size);
            const hb = try createHbFont(ft);
            faces[loaded] = .{ .path = path, .ft = ft, .hb = hb };
        }

        const nominal_height_px = try nominalPixelHeight(config.size);
        const metrics = try metricsFromFace(faces[0].ft, nominal_height_px);
        return .{
            .allocator = allocator,
            .library = library,
            .faces = faces,
            .metrics = metrics,
            .size = config.size,
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
    /// with the first face covering every scalar. The returned run borrows the
    /// initialized prefix of `glyph_storage`; insufficient storage leaves that
    /// destination unchanged.
    pub fn shape(
        self: *FontSet,
        buffer: *ShapeBuffer,
        text: Text,
        glyph_storage: []Glyph,
    ) ShapeError!Run {
        if (!self.usable) return error.FontState;
        try validateText(text);
        if (text.codepoints.len > buffer.capacity)
            return error.InsufficientShapeBuffer;
        const face_index = self.selectFace(text.codepoints) orelse
            return error.MissingGlyph;
        return self.shapeFace(
            buffer,
            text,
            glyph_storage,
            @intCast(face_index),
            false,
        );
    }

    /// Shapes one complete sequence on an already selected face and optionally
    /// disables contextual alternates exactly as Kitty does.
    pub fn shapeFace(
        self: *FontSet,
        buffer: *ShapeBuffer,
        text: Text,
        glyph_storage: []Glyph,
        face_index: u8,
        disable_contextual: bool,
    ) ShapeError!Run {
        if (!self.usable) return error.FontState;
        try validateText(text);
        if (text.codepoints.len > buffer.capacity)
            return error.InsufficientShapeBuffer;
        if (face_index >= self.faces.len) return error.MissingGlyph;
        const face = self.faces[face_index];
        c.hb_buffer_clear_contents(buffer.handle);
        try requireHbBuffer(buffer.handle);
        c.hb_buffer_add_utf32(
            buffer.handle,
            text.codepoints.ptr,
            @intCast(text.codepoints.len),
            0,
            @intCast(text.codepoints.len),
        );
        try requireHbBuffer(buffer.handle);
        c.hb_buffer_guess_segment_properties(buffer.handle);
        try requireHbBuffer(buffer.handle);
        var feature: c.hb_feature_t = undefined;
        const features: [*c]const c.hb_feature_t = if (disable_contextual) blk: {
            if (c.hb_feature_from_string("-calt", -1, &feature) == 0)
                return error.HarfBuzzBuffer;
            break :blk &feature;
        } else null;
        c.hb_shape(face.hb, buffer.handle, features, @intFromBool(disable_contextual));
        try requireHbBuffer(buffer.handle);

        var info_count: c_uint = 0;
        const infos = c.hb_buffer_get_glyph_infos(buffer.handle, &info_count);
        try requireHbBuffer(buffer.handle);
        var position_count: c_uint = 0;
        const positions = c.hb_buffer_get_glyph_positions(buffer.handle, &position_count);
        try requireHbBuffer(buffer.handle);
        if (info_count != position_count) return error.InvalidShapeResult;
        if (info_count > 0 and (infos == null or positions == null))
            return error.HarfBuzzBuffer;
        for (0..info_count) |i| {
            try validateGlyphInfo(infos[i], text.clusters.len);
        }
        const glyphs = try shapeDestination(
            info_count,
            buffer.capacity,
            glyph_storage,
        );
        for (glyphs, 0..) |*glyph, i| {
            const cp_index: usize = infos[i].cluster;
            glyph.* = .{
                .id = infos[i].codepoint,
                .cluster = text.clusters[cp_index],
                .scalar_index = @intCast(cp_index),
                .x_advance = positions[i].x_advance,
                .y_advance = positions[i].y_advance,
                .x_offset = positions[i].x_offset,
                .y_offset = positions[i].y_offset,
            };
        }
        return .{
            .face_index = face_index,
            .glyphs = glyphs,
        };
    }

    /// Returns the first configured face covering one complete valid sequence.
    ///
    /// A null result identifies optional font coverage absence. Invalid Unicode
    /// remains an exact caller error and cannot be normalized as a missing glyph.
    pub fn faceFor(
        self: *FontSet,
        codepoints: []const u32,
    ) error{ InvalidText, TextTooLong }!?u8 {
        try validateCodepoints(codepoints);
        const index = self.selectFace(codepoints) orelse return null;
        return @intCast(index);
    }

    /// Returns Kitty-compatible loaded bitmap width when present, otherwise
    /// the truncated horizontal glyph metric width in pixels.
    pub fn glyphWidth(
        self: *FontSet,
        face_index: u8,
        glyph_id: u32,
    ) GlyphWidthError!u16 {
        if (!self.usable) return error.FontState;
        if (face_index >= self.faces.len or glyph_id == 0)
            return error.InvalidRaster;
        const face = self.faces[face_index].ft;
        if (c.FT_Load_Glyph(face, glyph_id, c.FT_LOAD_DEFAULT) != 0)
            return error.GlyphLoad;
        const slot = face.*.glyph orelse return error.InvalidMetrics;
        const width = if (slot.*.bitmap.width != 0)
            slot.*.bitmap.width
        else blk: {
            const metric_width = @field(slot.*, "metrics").width;
            if (metric_width < 0) return error.InvalidMetrics;
            break :blk @divTrunc(metric_width, 64);
        };
        if (width < 0 or width > std.math.maxInt(u16))
            return error.InvalidMetrics;
        return @intCast(width);
    }

    /// Returns the exact selected-face glyph for one Unicode scalar.
    pub fn glyphForCodepoint(
        self: *FontSet,
        face_index: u8,
        codepoint: u21,
    ) GlyphWidthError!u32 {
        if (!self.usable) return error.FontState;
        if (face_index >= self.faces.len) return error.InvalidRaster;
        const glyph = c.FT_Get_Char_Index(self.faces[face_index].ft, codepoint);
        if (glyph == 0) return error.InvalidRaster;
        return glyph;
    }

    /// Returns whether one shaped glyph differs from the selected face's
    /// direct glyph for the exact current scalar.
    pub fn glyphIsSpecial(
        self: *FontSet,
        face_index: u8,
        glyph_id: u32,
        codepoint: u32,
    ) error{InvalidRaster}!bool {
        if (!self.usable or face_index >= self.faces.len or glyph_id == 0 or
            codepoint > std.math.maxInt(u21))
            return error.InvalidRaster;
        // Kitty removes VS15/VS16 from current-codepoint classification by
        // passing zero. Zero is a sentinel here, never a cmap comparison.
        if (codepoint == 0) return false;
        return glyph_id != c.FT_Get_Char_Index(
            self.faces[face_index].ft,
            @intCast(codepoint),
        );
    }

    /// Returns Kitty's exact zero-horizontal-metric empty-glyph fact.
    pub fn glyphIsEmpty(
        self: *FontSet,
        face_index: u8,
        glyph_id: u32,
    ) error{ GlyphLoad, InvalidRaster }!bool {
        if (!self.usable or face_index >= self.faces.len or glyph_id == 0)
            return error.InvalidRaster;
        const face = self.faces[face_index].ft;
        if (c.FT_Load_Glyph(face, glyph_id, c.FT_LOAD_DEFAULT) != 0)
            return error.GlyphLoad;
        const slot = face.*.glyph orelse return error.InvalidRaster;
        return @field(slot.*, "metrics").width == 0;
    }

    /// Classifies Kitty's normal or Iosevka variable-ligature glyph suffix.
    pub fn glyphLigatureType(
        self: *FontSet,
        face_index: u8,
        glyph_id: u32,
        strategy: SpacerStrategy,
    ) error{InvalidRaster}!LigatureType {
        if (!self.usable or face_index >= self.faces.len or glyph_id == 0)
            return error.InvalidRaster;
        var name: [128]u8 = @splat(0);
        c.hb_font_glyph_to_string(
            self.faces[face_index].hb,
            glyph_id,
            &name,
            name.len - 1,
        );
        const text = std.mem.sliceTo(&name, 0);
        const separator: u8 = if (strategy == .iosevka) '.' else '_';
        const suffix = if (std.mem.lastIndexOfScalar(u8, text, separator)) |index|
            text[index..]
        else
            return .unknown;
        if (strategy == .iosevka) {
            if (std.mem.eql(u8, suffix, ".join-l")) return .start;
            if (std.mem.eql(u8, suffix, ".join-m")) return .middle;
            if (std.mem.eql(u8, suffix, ".join-r")) return .end;
        } else {
            if (std.mem.eql(u8, suffix, "_start.seq")) return .start;
            if (std.mem.eql(u8, suffix, "_middle.seq")) return .middle;
            if (std.mem.eql(u8, suffix, "_end.seq")) return .end;
        }
        return .unknown;
    }

    /// Detects and retains Kitty's per-face spacer convention using the same
    /// bounded probe set and caller-owned shaping scratch.
    pub fn spacerStrategy(
        self: *FontSet,
        buffer: *ShapeBuffer,
        glyph_storage: []Glyph,
        face_index: u8,
    ) GroupError!SpacerStrategy {
        if (!self.usable or face_index >= self.faces.len)
            return error.InvalidRaster;
        if (self.faces[face_index].spacer_strategy != .unknown)
            return self.faces[face_index].spacer_strategy;
        const probes = [_][]const u8{ "==", "->", "<-", "<<=", "<==>" };
        var strategy: SpacerStrategy = .before;
        if (try self.probeEndsEmpty(
            buffer,
            glyph_storage,
            face_index,
            "===",
        )) strategy = .after;
        for (probes) |probe| {
            const run = try self.shapeAsciiProbe(
                buffer,
                glyph_storage,
                face_index,
                probe,
            );
            for (run.glyphs) |glyph| {
                const kind = try self.glyphLigatureType(
                    face_index,
                    glyph.id,
                    .iosevka,
                );
                if (kind != .unknown) {
                    strategy = .iosevka;
                    break;
                }
            }
            if (strategy == .iosevka) break;
        }
        if (strategy == .before and try self.probeEndsEmpty(
            buffer,
            glyph_storage,
            face_index,
            "###",
        )) strategy = .after;
        self.faces[face_index].spacer_strategy = strategy;
        return strategy;
    }

    fn probeEndsEmpty(
        self: *FontSet,
        buffer: *ShapeBuffer,
        glyph_storage: []Glyph,
        face_index: u8,
        probe: []const u8,
    ) GroupError!bool {
        const run = try self.shapeAsciiProbe(
            buffer,
            glyph_storage,
            face_index,
            probe,
        );
        if (run.glyphs.len <= 1) return false;
        const last = run.glyphs[run.glyphs.len - 1];
        const scalar_index: usize = @intCast(last.scalar_index);
        if (scalar_index >= probe.len) return error.InvalidShapeResult;
        const special = try self.glyphIsSpecial(
            face_index,
            last.id,
            probe[scalar_index],
        );
        return special and try self.glyphIsEmpty(face_index, last.id);
    }

    fn shapeAsciiProbe(
        self: *FontSet,
        buffer: *ShapeBuffer,
        glyph_storage: []Glyph,
        face_index: u8,
        probe: []const u8,
    ) ShapeError!Run {
        var codepoints: [5]u32 = undefined;
        var clusters: [5]u32 = undefined;
        if (probe.len > codepoints.len) return error.TextTooLong;
        for (probe, 0..) |value, index| {
            codepoints[index] = value;
            clusters[index] = @intCast(index);
        }
        return self.shapeFace(
            buffer,
            .{
                .codepoints = codepoints[0..probe.len],
                .clusters = clusters[0..probe.len],
            },
            glyph_storage,
            face_index,
            false,
        );
    }

    /// Exclusively borrows one native face and rasterizes monochrome or gray
    /// coverage into the requested pixel width. Scalable glyphs wider than
    /// that width are proportionally rerendered, while fixed bitmaps are
    /// clipped. Invalid identity, width, native rendering, geometry, placement,
    /// bounds, allocation, and native-size restoration fail exactly. Failed
    /// restoration invalidates later shaping and rasterization on this owner.
    pub fn rasterize(
        self: *FontSet,
        allocator: std.mem.Allocator,
        face_index: u8,
        glyph_id: u32,
        maximum_width_px: u16,
    ) RasterError!Raster {
        return self.rasterizeBounded(
            allocator,
            face_index,
            glyph_id,
            maximum_width_px,
            true,
        );
    }

    /// Rasterizes one glyph for later placement inside a complete multi-cell
    /// group canvas. Width fitting remains bounded by the group, while native
    /// bearings and overhang remain intact for group-level clipping.
    pub fn rasterizeGroup(
        self: *FontSet,
        allocator: std.mem.Allocator,
        face_index: u8,
        glyph_id: u32,
        maximum_width_px: u16,
    ) RasterError!Raster {
        return self.rasterizeBounded(
            allocator,
            face_index,
            glyph_id,
            maximum_width_px,
            false,
        );
    }

    fn rasterizeBounded(
        self: *FontSet,
        allocator: std.mem.Allocator,
        face_index: u8,
        glyph_id: u32,
        maximum_width_px: u16,
        normalize_to_canvas: bool,
    ) RasterError!Raster {
        if (!self.usable) return error.FontState;
        if (maximum_width_px == 0) return error.InvalidWidth;
        if (face_index >= self.faces.len or glyph_id == 0) return error.InvalidRaster;
        const face = self.faces[face_index].ft;
        var raster = try rasterizeFace(allocator, face, glyph_id);
        errdefer raster.deinit();

        if (raster.width > maximum_width_px and
            face.*.face_flags & c.FT_FACE_FLAG_SCALABLE != 0)
        {
            try setFittedSize(face, self.size, maximum_width_px, raster.width);
            const fit_result = rasterizeFace(allocator, face, glyph_id);
            const restore_error = restoreConfiguredSize(face, self.size);
            const fitted = try self.finishTemporaryRaster(
                fit_result,
                restore_error,
            );
            raster.deinit();
            raster = fitted;
        }
        if (raster.width > maximum_width_px)
            try cropRaster(&raster, 0, maximum_width_px);
        if (!normalize_to_canvas) return raster;
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
        if (right > maximum_width_px)
            raster.left = @intCast(maximum_width_px - raster.width);
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

// Native raster, font metrics, and external-library validation.

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

fn pointHeight26Dot6(value: PointSize) error{InvalidConfig}!c.FT_F26Dot6 {
    if (!std.math.isFinite(value.points) or std.math.isNan(value.points) or
        value.points <= 0.0)
        return error.InvalidConfig;
    try value.dpi_x.validate();
    try value.dpi_y.validate();
    const scaled = @ceil(value.points * 64.0);
    if (!std.math.isFinite(scaled) or scaled <= 0.0 or
        scaled > @as(f64, @floatFromInt(std.math.maxInt(c.FT_F26Dot6))))
        return error.InvalidConfig;
    return @intFromFloat(scaled);
}

fn dpiArgument(value: Dpi) error{InvalidConfig}!c.FT_UInt {
    try value.validate();
    const result = value.numerator / value.denominator;
    if (result == 0) return error.InvalidConfig;
    return result;
}

fn nominalPixelHeight(size: Size) error{InvalidConfig}!u16 {
    return switch (size) {
        .pixels => |height| if (height == 0)
            error.InvalidConfig
        else
            height,
        .points => |value| blk: {
            const height_26_6 = try pointHeight26Dot6(value);
            const dpi_y = try dpiArgument(value.dpi_y);
            break :blk try pointNominalPixelHeight(height_26_6, dpi_y);
        },
    };
}

fn pointNominalPixelHeight(
    height_26_6: c.FT_F26Dot6,
    dpi_y: c.FT_UInt,
) error{InvalidConfig}!u16 {
    if (height_26_6 <= 0 or dpi_y == 0) return error.InvalidConfig;
    const product = std.math.mul(
        u64,
        @intCast(height_26_6),
        dpi_y,
    ) catch return error.InvalidConfig;
    const denominator: u64 = 64 * 72;
    const adjusted = std.math.add(
        u64,
        product,
        denominator - 1,
    ) catch return error.InvalidConfig;
    const pixels = adjusted / denominator;
    if (pixels == 0 or pixels > std.math.maxInt(u16))
        return error.InvalidConfig;
    return @intCast(pixels);
}

fn setConfiguredSize(face: c.FT_Face, size: Size) InitError!void {
    const result = switch (size) {
        .pixels => |height| c.FT_Set_Pixel_Sizes(face, 0, height),
        .points => |value| c.FT_Set_Char_Size(
            face,
            0,
            try pointHeight26Dot6(value),
            try dpiArgument(value.dpi_x),
            try dpiArgument(value.dpi_y),
        ),
    };
    if (result != 0) return error.FontSize;
}

fn restoreConfiguredSize(face: c.FT_Face, size: Size) c.FT_Error {
    return switch (size) {
        .pixels => |height| c.FT_Set_Pixel_Sizes(face, 0, height),
        .points => |value| c.FT_Set_Char_Size(
            face,
            0,
            pointHeight26Dot6(value) catch return 1,
            dpiArgument(value.dpi_x) catch return 1,
            dpiArgument(value.dpi_y) catch return 1,
        ),
    };
}

fn setFittedSize(
    face: c.FT_Face,
    size: Size,
    maximum_width_px: u16,
    raster_width: u16,
) RasterError!void {
    const result = switch (size) {
        .pixels => |height| blk: {
            const scaled = @max(
                @as(u32, 1),
                @as(u32, height) * maximum_width_px / raster_width,
            );
            const fitted = std.math.cast(u16, scaled) orelse
                return error.FontSize;
            break :blk c.FT_Set_Pixel_Sizes(face, 0, fitted);
        },
        .points => |value| blk: {
            const accepted = pointHeight26Dot6(value) catch
                return error.FontSize;
            const product = std.math.mul(
                i64,
                accepted,
                maximum_width_px,
            ) catch return error.FontSize;
            const scaled = @max(
                @as(i64, 1),
                @divTrunc(product, raster_width),
            );
            break :blk c.FT_Set_Char_Size(
                face,
                0,
                scaled,
                dpiArgument(value.dpi_x) catch return error.FontSize,
                dpiArgument(value.dpi_y) catch return error.FontSize,
            );
        },
    };
    if (result != 0) return error.FontSize;
}

fn validateConfig(config: Config) error{InvalidConfig}!void {
    if (config.fallbacks.len > max_fallbacks)
        return error.InvalidConfig;
    const nominal_height = try nominalPixelHeight(config.size);
    std.debug.assert(nominal_height > 0);
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
) error{ InvalidGlyphIdentity, InvalidShapeResult }!void {
    if (info.codepoint == 0) return error.InvalidGlyphIdentity;
    if (info.cluster >= cluster_count) return error.InvalidShapeResult;
}

fn shapeDestination(
    count: usize,
    capacity: u32,
    glyph_storage: []Glyph,
) error{ GlyphLimit, InsufficientShapeBuffer, InsufficientGlyphs }![]Glyph {
    if (count > max_glyphs) return error.GlyphLimit;
    if (count > capacity) return error.InsufficientShapeBuffer;
    if (count > glyph_storage.len) return error.InsufficientGlyphs;
    return glyph_storage[0..count];
}

test "shape output ceiling rejects before caller storage" {
    const sentinel = Glyph{
        .id = 0xaaaaaaaa,
        .cluster = 0xbbbbbbbb,
        .x_advance = -1,
        .y_advance = -2,
        .x_offset = -3,
        .y_offset = -4,
    };
    var output = [_]Glyph{ sentinel, sentinel };
    try std.testing.expectError(
        error.InsufficientShapeBuffer,
        shapeDestination(2, 1, &output),
    );
    try std.testing.expectEqualSlices(Glyph, &.{ sentinel, sentinel }, &output);
}

fn validateText(text: Text) error{ InvalidText, TextTooLong }!void {
    if (text.codepoints.len == 0 or text.codepoints.len != text.clusters.len)
        return error.InvalidText;
    try validateCodepoints(text.codepoints);
}

fn validateCodepoints(codepoints: []const u32) error{ InvalidText, TextTooLong }!void {
    if (codepoints.len == 0) return error.InvalidText;
    if (codepoints.len > max_codepoints) return error.TextTooLong;
    for (codepoints) |codepoint| {
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
    // A face-wide maximum includes patched icon advances; printable ASCII
    // supplies a stable nominal advance for callers that need one.
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
    metrics.line_height = accommodateUnderscore(
        metrics.line_height,
        try underscoreBottom(face, metrics.baseline),
    );
    if (lineFromFontUnits(
        face.*.underline_position,
        face.*.underline_thickness,
        y_scale,
        metrics.baseline,
        metrics.line_height,
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
            metrics.line_height,
        )) |line| {
            metrics.strike_y = line.y;
            metrics.strike_height = line.height;
        }
    }
    return metrics;
}

fn accommodateUnderscore(line_height: u16, underscore_bottom: u16) u16 {
    return @max(line_height, underscore_bottom);
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
        .advance_width = width,
        .line_height = height,
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
    line_height: u16,
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
    if (top < 0 or bottom > line_height) return null;
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
        else => error.InvalidBitmap,
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

test "bitmap alpha rejects unsupported modes with InvalidBitmap" {
    const geometry = BitmapGeometry{
        .mode = c.FT_PIXEL_MODE_NONE,
        .num_grays = 0,
        .source_height = 1,
        .width = 1,
        .height = 1,
        .pitch = 1,
        .negative_pitch = false,
        .source_bytes = 1,
        .source = null,
    };
    try std.testing.expectError(
        error.InvalidBitmap,
        bitmapAlpha(&.{0}, geometry, 0, 0),
    );
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
    try std.testing.expectEqual(@as(u16, 20), metrics.line_height);
    const rounded = try metricsFromExternal(64 + 1, 1, 64 + 1, 1);
    try std.testing.expectEqual(@as(u16, 2), rounded.line_height);
    try std.testing.expectEqual(@as(u16, 1), rounded.baseline);
    try std.testing.expectEqual(@as(u16, 2), rounded.advance_width);
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
        .size = .{ .pixels = 18 },
    });
    defer set.deinit();
    const first = try metricsFromFace(set.faces[0].ft, 18);
    const second = try metricsFromFace(set.faces[0].ft, 18);
    try std.testing.expectEqualDeep(set.metrics, first);
    try std.testing.expectEqualDeep(first, second);
}

test "point and factual DPI conversion is exact and separately derived" {
    const value = PointSize{
        .points = 10.1,
        .dpi_x = .{ .numerator = 768, .denominator = 5 },
        .dpi_y = .{ .numerator = 192, .denominator = 1 },
    };
    try std.testing.expectEqual(@as(c.FT_F26Dot6, 647), try pointHeight26Dot6(value));
    try std.testing.expectEqual(@as(c.FT_UInt, 153), try dpiArgument(value.dpi_x));
    try std.testing.expectEqual(@as(c.FT_UInt, 192), try dpiArgument(value.dpi_y));
    try std.testing.expectEqual(@as(u16, 27), try nominalPixelHeight(.{ .points = value }));
    try std.testing.expectEqual(@as(u16, 34), try nominalPixelHeight(.{ .points = .{
        .points = 16.0,
        .dpi_x = .{ .numerator = 768, .denominator = 5 },
        .dpi_y = .{ .numerator = 768, .denominator = 5 },
    } }));
    try std.testing.expectError(
        error.InvalidConfig,
        dpiArgument(.{ .numerator = 192, .denominator = 2 }),
    );
    try std.testing.expectError(
        error.InvalidConfig,
        pointHeight26Dot6(.{
            .points = std.math.inf(f64),
            .dpi_x = .{ .numerator = 96, .denominator = 1 },
            .dpi_y = .{ .numerator = 96, .denominator = 1 },
        }),
    );
}

test "factual DPI changes terminal metrics and raster while fitting restores exact size" {
    const fonts = @import("test_fonts");
    const low = PointSize{
        .points = 12.0,
        .dpi_x = .{ .numerator = 96, .denominator = 1 },
        .dpi_y = .{ .numerator = 96, .denominator = 1 },
    };
    const high = PointSize{
        .points = 12.0,
        .dpi_x = .{ .numerator = 192, .denominator = 1 },
        .dpi_y = .{ .numerator = 192, .denominator = 1 },
    };
    var low_set = try FontSet.init(std.testing.allocator, .{
        .primary = fonts.symbol_font,
        .size = .{ .points = low },
    });
    defer low_set.deinit();
    var high_set = try FontSet.init(std.testing.allocator, .{
        .primary = fonts.symbol_font,
        .size = .{ .points = high },
    });
    defer high_set.deinit();
    try std.testing.expect(high_set.metrics.line_height > low_set.metrics.line_height);
    const low_glyph_id = c.FT_Get_Char_Index(low_set.faces[0].ft, 0xf303);
    const high_glyph_id = c.FT_Get_Char_Index(high_set.faces[0].ft, 0xf303);
    var low_raster = try low_set.rasterize(
        std.testing.allocator,
        0,
        low_glyph_id,
        low_set.metrics.advance_width,
    );
    defer low_raster.deinit();
    var high_raster = try high_set.rasterize(
        std.testing.allocator,
        0,
        high_glyph_id,
        high_set.metrics.advance_width,
    );
    defer high_raster.deinit();
    try std.testing.expect(
        low_raster.width != high_raster.width or
            low_raster.height != high_raster.height or
            !std.mem.eql(u8, low_raster.pixels, high_raster.pixels),
    );
    const before = @field(high_set.faces[0].ft.*.size.?.*, "metrics");
    const fitted_width = @max(@as(u16, 1), high_set.metrics.advance_width / 2);
    var raw = try rasterizeFace(
        std.testing.allocator,
        high_set.faces[0].ft,
        high_glyph_id,
    );
    defer raw.deinit();
    try std.testing.expect(raw.width > fitted_width);
    var raster = try high_set.rasterize(
        std.testing.allocator,
        0,
        high_glyph_id,
        fitted_width,
    );
    defer raster.deinit();
    const after = @field(high_set.faces[0].ft.*.size.?.*, "metrics");
    try std.testing.expectEqual(before.x_ppem, after.x_ppem);
    try std.testing.expectEqual(before.y_ppem, after.y_ppem);
    try std.testing.expectEqual(before.x_scale, after.x_scale);
    try std.testing.expectEqual(before.y_scale, after.y_scale);
    try std.testing.expect(raster.pixels.len != 0);
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
            .size = .{ .pixels = if (case[1] == c.FT_PIXEL_MODE_MONO) 16 else 18 },
        });
        defer set.deinit();
        const glyph_id = c.FT_Get_Char_Index(set.faces[0].ft, 'A');
        var raster = try set.rasterize(
            std.testing.allocator,
            0,
            glyph_id,
            set.metrics.advance_width,
        );
        raster.deinit();
        const slot = set.faces[0].ft.*.glyph orelse return error.TestUnexpectedResult;
        try std.testing.expectEqual(@as(PixelMode, case[1]), slot.*.bitmap.pixel_mode);
    }
}

test "Nerd icon native bitmap exposes bounded source coverage" {
    const fonts = @import("test_fonts");
    var set = try FontSet.init(std.testing.allocator, .{
        .primary = fonts.symbol_font,
        .size = .{ .pixels = 18 },
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
            @as(i32, native.left) + native.width > set.metrics.advance_width,
    );
}

test "native raster honors an arbitrary pixel bound" {
    const fonts = @import("test_fonts");
    var set = try FontSet.init(std.testing.allocator, .{
        .primary = fonts.symbol_font,
        .size = .{ .pixels = 18 },
    });
    defer set.deinit();
    const glyph_id = c.FT_Get_Char_Index(set.faces[0].ft, 0xf303);
    var raster = try set.rasterize(std.testing.allocator, 0, glyph_id, 7);
    defer raster.deinit();
    try std.testing.expect(raster.width <= 7);
    try std.testing.expect(raster.left >= 0);
    try std.testing.expect(
        @as(u32, @intCast(raster.left)) + raster.width <= 7,
    );
}

test "one-cell native raster shifts a positive bearing inside its canvas" {
    const fonts = @import("test_fonts");
    var set = try FontSet.init(std.testing.allocator, .{
        .primary = fonts.symbol_font,
        .size = .{ .points = .{
            .points = 16.0,
            .dpi_x = .{ .numerator = 768, .denominator = 5 },
            .dpi_y = .{ .numerator = 768, .denominator = 5 },
        } },
    });
    defer set.deinit();
    const glyph_id = c.FT_Get_Char_Index(set.faces[0].ft, 0xf460);
    var native = try rasterizeFace(
        std.testing.allocator,
        set.faces[0].ft,
        glyph_id,
    );
    defer native.deinit();
    try std.testing.expectEqual(@as(u16, 13), native.width);
    try std.testing.expectEqual(@as(i16, 12), native.left);
    try std.testing.expectEqual(@as(u16, 17), set.metrics.advance_width);

    var placed = try set.rasterize(
        std.testing.allocator,
        0,
        glyph_id,
        set.metrics.advance_width,
    );
    defer placed.deinit();
    try std.testing.expectEqual(native.width, placed.width);
    try std.testing.expectEqual(@as(i16, 4), placed.left);
    try std.testing.expectEqual(
        set.metrics.advance_width,
        @as(u16, @intCast(placed.left)) + placed.width,
    );
}

test "failed size restoration invalidates native use and preserves cleanup" {
    const fonts = @import("test_fonts");
    var set = try FontSet.init(std.testing.allocator, .{
        .primary = fonts.symbol_font,
        .size = .{ .pixels = 18 },
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
    var shaper = try ShapeBuffer.init(1);
    defer shaper.deinit();
    var glyphs: [1]Glyph = undefined;
    try std.testing.expectError(error.FontState, set.shape(
        &shaper,
        .{
            .codepoints = &.{'A'},
            .clusters = &.{0},
        },
        &glyphs,
    ));
    try std.testing.expectError(
        error.FontState,
        set.rasterize(std.testing.allocator, 0, 1, set.metrics.advance_width),
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
    try std.testing.expectError(error.InvalidGlyphIdentity, validateGlyphInfo(info, 1));
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
