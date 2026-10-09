//! Private bounded text-shape and alpha-atlas caches for terminal presentation.
//!
//! This module consumes only howl-text. It owns no terminal/client semantics,
//! renderer resources, host topology, or backend state.

const std = @import("std");
const text = @import("howl_text");
const generated = text.generated;

/// Selects one caller-owned font face variant without owning terminal style policy.
pub const FontVariant = enum(u2) {
    regular,
    italic,
    bold,
    bold_italic,
};

const font_variant_count: usize = 4;

/// Borrows one required regular face plus optional style variants.
///
/// Missing variants fall back deterministically without font discovery:
/// bold-italic prefers bold, then italic, then regular.
pub const FontFaces = struct {
    regular: *text.FontSet,
    italic: ?*text.FontSet = null,
    bold: ?*text.FontSet = null,
    bold_italic: ?*text.FontSet = null,

    /// Constructs one face family whose missing style variants resolve to regular.
    pub fn single(regular: *text.FontSet) FontFaces {
        return .{ .regular = regular };
    }

    /// Selects the caller-owned FontSet after deterministic variant fallback.
    pub fn select(self: FontFaces, variant: FontVariant) *text.FontSet {
        return switch (self.resolveVariant(variant)) {
            .regular => self.regular,
            .italic => self.italic.?,
            .bold => self.bold.?,
            .bold_italic => self.bold_italic.?,
        };
    }

    /// Returns the concrete available variant used for one requested style.
    pub fn resolveVariant(self: FontFaces, variant: FontVariant) FontVariant {
        return switch (variant) {
            .regular => .regular,
            .italic => if (self.italic != null) .italic else .regular,
            .bold => if (self.bold != null) .bold else .regular,
            .bold_italic => if (self.bold_italic != null)
                .bold_italic
            else if (self.bold != null)
                .bold
            else if (self.italic != null)
                .italic
            else
                .regular,
        };
    }

    /// Returns the canonical terminal metrics fixed by the required regular face.
    pub fn metrics(self: FontFaces) text.Metrics {
        return self.regular.metrics();
    }

    /// Reports whether every supplied style variant preserves identical terminal metrics.
    pub fn terminalMetricsCompatible(self: FontFaces) bool {
        const regular = self.regular.metrics();
        if (self.italic) |value| if (!std.meta.eql(regular, value.metrics())) return false;
        if (self.bold) |value| if (!std.meta.eql(regular, value.metrics())) return false;
        if (self.bold_italic) |value| if (!std.meta.eql(regular, value.metrics())) return false;
        return true;
    }
};

/// Caller-selected memory and packing bounds for one terminal glyph atlas.
///
/// These values are presentation policy, not terminal state or a stable ABI. The
/// font faces supplied at initialization must outlive the atlas and fix every
/// native face/raster size used by cached keys until deinitialization.
pub const AtlasConfig = struct {
    width: u16,
    height: u16,
    entry_capacity: usize,
    /// Empty alpha pixels left after each packed raster on both shelf axes.
    gap: u16 = 1,
};

/// Caller-selected retained-shaping bounds for one fixed howl-text face family.
///
/// Exact scalar sequences are the cache key. Retained glyph clusters are relative
/// to that sequence and are rebased to each immutable view during projection.
pub const ShapeCacheConfig = struct {
    entry_capacity: usize,
    scalar_capacity: usize,
    glyph_capacity: usize,
    max_sequence_scalars: u32,
};

/// Opaque explicitly owned shaped-run cache.
///
/// No returned frame borrows this storage. `resetShapeCache` may therefore forget
/// retained runs without invalidating atlas generations or prior frame placements.
// zig-audit: acknowledge opaque_type
// reason: The public handle intentionally hides the allocator-owned ShapeCacheImpl layout so callers cannot bypass bounded cache operations.
pub const ShapeCache = opaque {};

/// Reports exact retained shaped-run storage currently occupied by one cache.
pub const ShapeCacheUsage = struct {
    entries: usize,
    scalars: usize,
    glyphs: usize,
};

/// Opaque explicitly owned glyph-atlas cache.
///
/// The cache never evicts or recycles storage implicitly. `resetAtlas` is the
/// only operation that invalidates atlas references returned by prior frames.
// zig-audit: acknowledge opaque_type
// reason: The public handle intentionally hides the allocator-owned AtlasImpl layout so callers cannot mutate packing or generation state directly.
pub const Atlas = opaque {};

/// Read-only borrowed atlas image for one cache generation.
pub const AtlasView = struct {
    generation: u64,
    width: u16,
    height: u16,
    /// Complete row-major alpha image. Unused pixels are deterministically zero.
    pixels: []const u8,
};

/// Reports allocation or configuration failure before an Atlas owner exists.
pub const AtlasInitError = std.mem.Allocator.Error || error{InvalidAtlasConfig};

/// Reports runtime rasterization, packing, or bounded atlas-capacity failures.
pub const AtlasError = text.RasterError || generated.Error || error{
    CacheFull,
    AtlasFull,
    GlyphTooLarge,
    RasterExtentMismatch,
};

/// Reports allocation or configuration failure before a ShapeCache owner exists.
pub const ShapeCacheInitError = std.mem.Allocator.Error || text.ShapeBufferInitError || error{
    InvalidShapeCacheConfig,
};

/// Reports runtime shaping or bounded retained-shape capacity failures.
pub const ShapeCacheError = text.ShapeError || error{
    ShapeSequenceLimit,
    ShapeEntryFull,
    ShapeScalarFull,
    ShapeGlyphFull,
};

const AtlasKey = union(enum) {
    font: struct {
        variant: FontVariant,
        face_index: u8,
        glyph_id: u32,
    },
    smooth_wave: struct {
        width: u16,
        thickness: u16,
        line_height: u16,
    },
    generated: struct {
        codepoint: u32,
        width: u16,
        height: u16,
        sizing: generated.BoxDrawingSizing,
    },
};

const AtlasIdentity = struct { low: u64, high: u64 };

const AtlasEntry = struct {
    key: AtlasIdentity,
    atlas_x: u16,
    atlas_y: u16,
    width: u16,
    height: u16,
    left: i16,
    top: i16,
};

const ShapeEntry = struct {
    hash: u64,
    variant: FontVariant,
    scalar_offset: usize,
    scalar_count: usize,
    glyph_offset: usize,
    glyph_count: usize,
    face_index: u8,
};

const printable_ascii_first: u32 = 0x20;
const printable_ascii_last: u32 = 0x7e;
const printable_ascii_count: usize = printable_ascii_last - printable_ascii_first + 1;

/// Maps one printable single-scalar ASCII sequence to its dense fast-cache slot.
pub fn printableAsciiIndex(sequence: []const u32) ?usize {
    if (sequence.len != 1) return null;
    const scalar = sequence[0];
    if (scalar < printable_ascii_first or scalar > printable_ascii_last) return null;
    return @intCast(scalar - printable_ascii_first);
}

const ShapeCacheImpl = struct {
    allocator: std.mem.Allocator,
    fonts: FontFaces,
    shape: *text.ShapeBuffer,
    entries: []ShapeEntry,
    scalars: []u32,
    glyphs: []text.Glyph,
    max_sequence_scalars: u32,
    ascii_entries: [font_variant_count][printable_ascii_count]?usize = @splat(@splat(null)),
    entry_count: usize = 0,
    scalar_count: usize = 0,
    glyph_count: usize = 0,
};

const AtlasImpl = struct {
    allocator: std.mem.Allocator,
    fonts: FontFaces,
    box_drawing: generated.BoxDrawingConfig,
    entries: []AtlasEntry,
    pixels: []u8,
    config: AtlasConfig,
    ascii_entries: [font_variant_count][printable_ascii_count]?usize = @splat(@splat(null)),
    entry_count: usize = 0,
    next_x: usize = 0,
    shelf_y: usize = 0,
    shelf_height: usize = 0,
    generation: u64 = 1,
};

const AtlasPack = struct {
    x: usize,
    y: usize,
    next_x: usize,
    shelf_y: usize,
    shelf_height: usize,
};

/// Locates one cached alpha raster and its baseline-relative native placement.
pub const AtlasRaster = struct {
    atlas_x: u16,
    atlas_y: u16,
    width: u16,
    height: u16,
    left: i16,
    top: i16,
};

/// Reports the fixed pixel extent of one atlas owner.
pub const AtlasSize = struct {
    width: u16,
    height: u16,
};

/// Allocates one bounded shaped-run owner for one fixed face family.
///
/// All entry/scalar/glyph storage and the reusable HarfBuzz buffer are allocated
/// during construction. Cache hits and misses allocate nothing afterward.
pub fn initShapeCache(
    allocator: std.mem.Allocator,
    fonts: FontFaces,
    config: ShapeCacheConfig,
) ShapeCacheInitError!*ShapeCache {
    if (config.entry_capacity == 0 or config.scalar_capacity == 0 or
        config.glyph_capacity == 0 or config.max_sequence_scalars == 0 or
        config.max_sequence_scalars > text.max_codepoints or
        @as(usize, config.max_sequence_scalars) > config.scalar_capacity)
        return error.InvalidShapeCacheConfig;

    const impl = try allocator.create(ShapeCacheImpl);
    errdefer allocator.destroy(impl);
    const entries = try allocator.alloc(ShapeEntry, config.entry_capacity);
    errdefer allocator.free(entries);
    const scalars = try allocator.alloc(u32, config.scalar_capacity);
    errdefer allocator.free(scalars);
    const glyphs = try allocator.alloc(text.Glyph, config.glyph_capacity);
    errdefer allocator.free(glyphs);
    const shape = try text.ShapeBuffer.init(allocator, config.max_sequence_scalars);
    errdefer shape.deinit();
    impl.* = .{
        .allocator = allocator,
        .fonts = fonts,
        .shape = shape,
        .entries = entries,
        .scalars = scalars,
        .glyphs = glyphs,
        .max_sequence_scalars = config.max_sequence_scalars,
    };
    // zig-audit: acknowledge ptr_cast
    // reason: ShapeCache is the opaque handle for this exact allocator-owned ShapeCacheImpl allocation and preserves its address.
    return @ptrCast(impl);
}

/// Releases the shaping buffer and every fixed retained-shape allocation.
pub fn deinitShapeCache(cache: *ShapeCache) void {
    const impl = shapeCacheImpl(cache);
    const allocator = impl.allocator;
    const shape = impl.shape;
    const entries = impl.entries;
    const scalars = impl.scalars;
    const glyphs = impl.glyphs;
    impl.* = undefined;
    shape.deinit();
    allocator.free(glyphs);
    allocator.free(scalars);
    allocator.free(entries);
    allocator.destroy(impl);
}

/// Forgets retained shaped runs without changing the fixed FontSet or atlas.
pub fn resetShapeCache(cache: *ShapeCache) void {
    const impl = shapeCacheImpl(cache);
    impl.entry_count = 0;
    impl.scalar_count = 0;
    impl.glyph_count = 0;
    impl.ascii_entries = @splat(@splat(null));
}

/// Reports current retained shape/scalar/glyph counts without exposing cache storage.
pub fn shapeCacheUsage(cache: *const ShapeCache) ShapeCacheUsage {
    const impl = constShapeCacheImpl(cache);
    return .{
        .entries = impl.entry_count,
        .scalars = impl.scalar_count,
        .glyphs = impl.glyph_count,
    };
}

/// Allocates one bounded atlas owner. There are no allocations on cache hits or
/// misses after initialization; misses rasterize through caller scratch.
pub fn initAtlas(
    allocator: std.mem.Allocator,
    fonts: FontFaces,
    box_drawing: generated.BoxDrawingConfig,
    config: AtlasConfig,
) AtlasInitError!*Atlas {
    if (config.width == 0 or config.height == 0 or config.entry_capacity == 0)
        return error.InvalidAtlasConfig;
    const pixel_count = std.math.mul(
        usize,
        @as(usize, config.width),
        @as(usize, config.height),
    ) catch return error.InvalidAtlasConfig;

    const impl = try allocator.create(AtlasImpl);
    errdefer allocator.destroy(impl);
    const entries = try allocator.alloc(AtlasEntry, config.entry_capacity);
    errdefer allocator.free(entries);
    const pixels = try allocator.alloc(u8, pixel_count);
    errdefer allocator.free(pixels);
    @memset(pixels, 0);
    impl.* = .{
        .allocator = allocator,
        .fonts = fonts,
        .box_drawing = box_drawing,
        .entries = entries,
        .pixels = pixels,
        .config = config,
    };
    // zig-audit: acknowledge ptr_cast
    // reason: Atlas is the opaque handle for this exact allocator-owned AtlasImpl allocation and preserves its address.
    return @ptrCast(impl);
}

/// Releases the atlas. Every prior atlas view and frame becomes invalid.
pub fn deinitAtlas(atlas: *Atlas) void {
    const impl = atlasImpl(atlas);
    const allocator = impl.allocator;
    const entries = impl.entries;
    const pixels = impl.pixels;
    impl.* = undefined;
    allocator.free(pixels);
    allocator.free(entries);
    allocator.destroy(impl);
}

/// Explicitly invalidates every cached glyph and begins a new zeroed generation.
pub fn resetAtlas(atlas: *Atlas) error{GenerationOverflow}!void {
    const impl = atlasImpl(atlas);
    if (impl.generation == std.math.maxInt(u64)) return error.GenerationOverflow;
    impl.generation += 1;
    impl.entry_count = 0;
    impl.ascii_entries = @splat(@splat(null));
    impl.next_x = 0;
    impl.shelf_y = 0;
    impl.shelf_height = 0;
    @memset(impl.pixels, 0);
}

/// Borrows the complete alpha image and private reset epoch until atlas mutation.
pub fn atlasView(atlas: *const Atlas) AtlasView {
    const impl = constAtlasImpl(atlas);
    return .{
        .generation = impl.generation,
        .width = impl.config.width,
        .height = impl.config.height,
        .pixels = impl.pixels,
    };
}

/// Returns the number of currently retained atlas entries.
pub fn atlasEntryCount(atlas: *const Atlas) usize {
    return constAtlasImpl(atlas).entry_count;
}

/// Returns the fixed caller-owned font family shared by this atlas.
pub fn fontFaces(atlas: *const Atlas) FontFaces {
    return constAtlasImpl(atlas).fonts;
}

/// Reports whether the shape cache and atlas borrow the same fixed font family.
pub fn sameFontFaces(shape_cache: *const ShapeCache, atlas: *const Atlas) bool {
    return std.meta.eql(constShapeCacheImpl(shape_cache).fonts, constAtlasImpl(atlas).fonts);
}

/// Returns the caller-fixed maximum scalar sequence accepted by the shape cache.
pub fn maximumSequenceScalars(shape_cache: *const ShapeCache) u32 {
    return constShapeCacheImpl(shape_cache).max_sequence_scalars;
}

/// Returns the fixed atlas pixel extent.
pub fn atlasSize(atlas: *const Atlas) AtlasSize {
    const impl = constAtlasImpl(atlas);
    return .{ .width = impl.config.width, .height = impl.config.height };
}

/// Shapes one short multi-scalar operator run without retaining it in ShapeCache.
/// Returns null when the sequence is ineligible, exceeds caller scratch, or does
/// not resolve wholly through the selected variant's primary face.
pub fn shapeContextualPrimary(
    cache: *ShapeCache,
    variant: FontVariant,
    sequence: []const u32,
    cluster_scratch: []u32,
    glyph_scratch: []text.Glyph,
) ShapeCacheError!?text.Run {
    const impl = shapeCacheImpl(cache);
    const resolved_variant = impl.fonts.resolveVariant(variant);
    const fonts = impl.fonts.select(resolved_variant);
    if (sequence.len < 2 or sequence.len > @as(usize, impl.max_sequence_scalars) or
        sequence.len > cluster_scratch.len)
        return null;
    if ((try fonts.faceFor(sequence)) != 0) return null;
    for (cluster_scratch[0..sequence.len], 0..) |*cluster, index|
        cluster.* = @intCast(index);
    return try fonts.shape(
        impl.shape,
        .{ .codepoints = sequence, .clusters = cluster_scratch[0..sequence.len] },
        glyph_scratch,
    );
}

fn shapeEntryRun(impl: *const ShapeCacheImpl, entry_index: usize) text.Run {
    std.debug.assert(entry_index < impl.entry_count);
    const entry = impl.entries[entry_index];
    return .{
        .face_index = entry.face_index,
        .glyphs = impl.glyphs[entry.glyph_offset .. entry.glyph_offset + entry.glyph_count],
    };
}

/// Resolves one exact scalar sequence through deterministic style fallback and
/// retains the resulting shape for allocation-free reuse until cache reset.
/// Missing glyphs are retried as one U+FFFD replacement while preserving the
/// original sequence as the cache identity.
pub fn resolveShape(
    cache: *ShapeCache,
    variant: FontVariant,
    sequence: []const u32,
    cluster_scratch: []u32,
    glyph_scratch: []text.Glyph,
) ShapeCacheError!text.Run {
    const impl = shapeCacheImpl(cache);
    const resolved_variant = impl.fonts.resolveVariant(variant);
    const fonts = impl.fonts.select(resolved_variant);
    const variant_index = fontVariantIndex(resolved_variant);
    if (sequence.len == 0 or sequence.len > @as(usize, impl.max_sequence_scalars))
        return error.ShapeSequenceLimit;
    const ascii_index = printableAsciiIndex(sequence);
    if (ascii_index) |index| {
        if (impl.ascii_entries[variant_index][index]) |entry_index| {
            const entry = impl.entries[entry_index];
            std.debug.assert(entry.scalar_count == 1);
            std.debug.assert(entry.variant == resolved_variant);
            std.debug.assert(impl.scalars[entry.scalar_offset] == sequence[0]);
            return shapeEntryRun(impl, entry_index);
        }
    }
    const hash = std.hash.Wyhash.hash(
        0x9e3779b97f4a7c15,
        std.mem.sliceAsBytes(sequence),
    );
    for (impl.entries[0..impl.entry_count], 0..) |entry, entry_index| {
        if (entry.variant != resolved_variant or entry.hash != hash or entry.scalar_count != sequence.len) continue;
        const retained = impl.scalars[entry.scalar_offset .. entry.scalar_offset + entry.scalar_count];
        if (!std.mem.eql(u32, retained, sequence)) continue;
        if (ascii_index) |index| impl.ascii_entries[variant_index][index] = entry_index;
        return shapeEntryRun(impl, entry_index);
    }

    if (impl.entry_count == impl.entries.len) return error.ShapeEntryFull;
    if (sequence.len > impl.scalars.len - impl.scalar_count) return error.ShapeScalarFull;
    if (sequence.len > cluster_scratch.len) return error.ShapeSequenceLimit;
    for (cluster_scratch[0..sequence.len], 0..) |*cluster, index| cluster.* = @intCast(index);
    const shaped = fonts.shape(
        impl.shape,
        .{ .codepoints = sequence, .clusters = cluster_scratch[0..sequence.len] },
        glyph_scratch,
    ) catch |failure| switch (failure) {
        error.MissingGlyph => replacement: {
            const replacement_codepoints = [_]u32{0xfffd};
            cluster_scratch[0] = 0;
            break :replacement try fonts.shape(
                impl.shape,
                .{ .codepoints = &replacement_codepoints, .clusters = cluster_scratch[0..1] },
                glyph_scratch,
            );
        },
        else => return failure,
    };
    if (shaped.glyphs.len > impl.glyphs.len - impl.glyph_count)
        return error.ShapeGlyphFull;

    const scalar_offset = impl.scalar_count;
    const glyph_offset = impl.glyph_count;
    @memcpy(impl.scalars[scalar_offset .. scalar_offset + sequence.len], sequence);
    @memcpy(impl.glyphs[glyph_offset .. glyph_offset + shaped.glyphs.len], shaped.glyphs);
    impl.scalar_count += sequence.len;
    impl.glyph_count += shaped.glyphs.len;
    const entry_index = impl.entry_count;
    impl.entries[entry_index] = .{
        .hash = hash,
        .variant = resolved_variant,
        .scalar_offset = scalar_offset,
        .scalar_count = sequence.len,
        .glyph_offset = glyph_offset,
        .glyph_count = shaped.glyphs.len,
        .face_index = shaped.face_index,
    };
    impl.entry_count += 1;
    if (ascii_index) |index| impl.ascii_entries[variant_index][index] = entry_index;
    return shapeEntryRun(impl, entry_index);
}

/// Resolves one native font glyph into the fixed alpha atlas, rasterizing into
/// caller scratch only on cache miss. `ascii_index` is an optional dense lookup
/// hint derived from the source scalar and never changes atlas identity.
pub fn resolveFontAtlas(
    atlas: *Atlas,
    variant: FontVariant,
    face_index: u8,
    glyph_id: u32,
    raster_scratch: []u8,
    ascii_index: ?usize,
) AtlasError!AtlasRaster {
    const impl = atlasImpl(atlas);
    const resolved_variant = impl.fonts.resolveVariant(variant);
    const fonts = impl.fonts.select(resolved_variant);
    const variant_index = fontVariantIndex(resolved_variant);
    const key = AtlasKey{ .font = .{
        .variant = resolved_variant,
        .face_index = face_index,
        .glyph_id = glyph_id,
    } };
    if (ascii_index) |index| {
        if (impl.ascii_entries[variant_index][index]) |entry_index| {
            std.debug.assert(entry_index < impl.entry_count);
            const entry = impl.entries[entry_index];
            std.debug.assert(std.meta.eql(entry.key, atlasIdentity(key)));
            return atlasRaster(entry);
        }
    }
    if (findAtlasIndex(impl, key)) |entry_index| {
        if (ascii_index) |index| impl.ascii_entries[variant_index][index] = entry_index;
        return atlasRaster(impl.entries[entry_index]);
    }

    var raster_allocator = std.heap.FixedBufferAllocator.init(raster_scratch);
    var raster = try fonts.rasterize(
        raster_allocator.allocator(),
        face_index,
        glyph_id,
    );
    defer raster.deinit();
    const expected = std.math.mul(
        usize,
        @as(usize, raster.width),
        @as(usize, raster.height),
    ) catch return error.RasterExtentMismatch;
    if (expected != raster.pixels.len) return error.RasterExtentMismatch;
    const result = try cacheAtlas(
        impl,
        key,
        raster.width,
        raster.height,
        raster.left,
        raster.top,
        raster.pixels,
    );
    if (ascii_index) |index| {
        std.debug.assert(impl.entry_count != 0);
        impl.ascii_entries[variant_index][index] = impl.entry_count - 1;
    }
    return result;
}

/// Resolves one smooth supersampled wave into the shared alpha atlas.
///
/// The cache owns only pixel geometry. Terminal underline semantics remain with
/// the caller that selects this pattern.
pub fn resolveSmoothWaveAtlas(
    atlas: *Atlas,
    width: u16,
    thickness: u16,
    line_height: u16,
    raster_scratch: []u8,
) AtlasError!AtlasRaster {
    if (width == 0 or line_height == 0) return error.InvalidSize;
    const line_width = @max(@as(f32, @floatFromInt(thickness)), 0.8);
    const amplitude = @max(@as(f32, 1.45), line_width * 1.25);
    const period = @max(@as(f32, 8), @as(f32, @floatFromInt(line_height)) * 0.45);
    const pad = line_width + 1;
    const height_f = @ceil(amplitude * 2 + pad * 2);
    if (height_f <= 0 or height_f > std.math.maxInt(u16)) return error.InvalidSize;
    const height: u16 = @intFromFloat(height_f);
    const required = std.math.mul(usize, @as(usize, width), @as(usize, height)) catch
        return error.RasterTooLarge;
    if (required > raster_scratch.len) return error.BufferTooSmall;

    const impl = atlasImpl(atlas);
    const key = AtlasKey{ .smooth_wave = .{
        .width = width,
        .thickness = thickness,
        .line_height = line_height,
    } };
    if (findAtlas(impl, key)) |entry| return atlasRaster(entry);

    const pixels = raster_scratch[0..required];
    @memset(pixels, 0);
    const samples: usize = 4;
    const sample_count: u16 = samples * samples;
    const half_line = line_width / 2;
    const curve_origin = pad + amplitude;
    for (0..height) |py| {
        for (0..width) |px| {
            var covered: u16 = 0;
            for (0..samples) |sy| {
                for (0..samples) |sx| {
                    const sample_x =
                        @as(f32, @floatFromInt(px)) +
                        (@as(f32, @floatFromInt(sx)) + 0.5) /
                            @as(f32, @floatFromInt(samples));
                    const sample_y =
                        @as(f32, @floatFromInt(py)) +
                        (@as(f32, @floatFromInt(sy)) + 0.5) /
                            @as(f32, @floatFromInt(samples));
                    const curve_y =
                        curve_origin +
                        amplitude *
                            @sin(std.math.tau * sample_x / period);
                    if (@abs(sample_y - curve_y) <= half_line)
                        covered += 1;
                }
            }
            pixels[py * @as(usize, width) + px] =
                @intCast(covered * 255 / sample_count);
        }
    }
    const top = std.math.cast(i16, @as(i32, @intFromFloat(@ceil(pad)))) orelse
        return error.InvalidSize;
    return cacheAtlas(impl, key, width, height, 0, top, pixels);
}

/// Resolves one implemented code-defined glyph into the fixed alpha atlas.
/// The Atlas owns the immutable box-drawing raster policy; per-entry identity is
/// therefore only codepoint, pixel extent, and OSC 66 sizing.
pub fn resolveGeneratedAtlas(
    atlas: *Atlas,
    codepoint: u32,
    width: u16,
    height: u16,
    sizing: generated.BoxDrawingSizing,
    raster_scratch: []u8,
) AtlasError!AtlasRaster {
    const impl = atlasImpl(atlas);
    const key = AtlasKey{ .generated = .{
        .codepoint = codepoint,
        .width = width,
        .height = height,
        .sizing = sizing,
    } };
    if (findAtlas(impl, key)) |entry| return atlasRaster(entry);

    const required = std.math.mul(usize, @as(usize, width), @as(usize, height)) catch
        return error.RasterTooLarge;
    if (required > raster_scratch.len) return error.BufferTooSmall;
    const pixels = raster_scratch[0..required];
    const family = generated.classify(codepoint) orelse return error.UnsupportedGlyph;
    switch (family) {
        .box => try generated.rasterizeBox(
            pixels,
            width,
            height,
            codepoint,
            impl.box_drawing,
            sizing,
        ),
        .progress => try generated.rasterizeProgress(
            pixels,
            width,
            height,
            codepoint,
            impl.box_drawing,
            sizing,
        ),
        .branch => if (codepoint == 0xf5ee)
            try generated.rasterize(pixels, width, height, codepoint)
        else
            try generated.rasterizeBranch(
                pixels,
                width,
                height,
                codepoint,
                impl.box_drawing,
                sizing,
            ),
        .powerline => generated.rasterize(pixels, width, height, codepoint) catch |failure| switch (failure) {
            error.InvalidMetrics => try generated.rasterizePowerline(
                pixels,
                width,
                height,
                codepoint,
                impl.box_drawing,
                sizing,
            ),
            else => return failure,
        },
        .block, .braille, .sextant, .octant => try generated.rasterize(pixels, width, height, codepoint),
    }
    return cacheAtlas(impl, key, width, height, 0, 0, pixels);
}

// Exact identity: low holds glyph/geometry, high holds sizing and key kind.
// Zig 0.17.0-dev.1980+e78ea8f2c lowers u128 shifts to expensive limb loops;
// two u64 words retain every key bit without padding comparisons or hashing.
fn atlasIdentity(key: AtlasKey) AtlasIdentity {
    return switch (key) {
        .font => |v| .{ .low = @as(u64, v.glyph_id) | (@as(u64, v.face_index) << 32) | (@as(u64, @backingInt(v.variant)) << 40), .high = 0 },
        .smooth_wave => |v| .{ .low = @as(u64, v.width) | (@as(u64, v.thickness) << 16) | (@as(u64, v.line_height) << 32), .high = 1 << 16 },
        .generated => |v| .{ .low = @as(u64, v.codepoint) | (@as(u64, v.width) << 32) | (@as(u64, v.height) << 48), .high = (2 << 16) | @as(u64, v.sizing.scale) | (@as(u64, v.sizing.subscale_n) << 8) | (@as(u64, v.sizing.subscale_d) << 12) },
    };
}

fn findAtlasIndex(impl: *const AtlasImpl, key: AtlasKey) ?usize {
    const wanted = atlasIdentity(key);
    for (impl.entries[0..impl.entry_count], 0..) |*entry, index|
        if (entry.key.low == wanted.low and entry.key.high == wanted.high) return index;
    return null;
}

test "atlas lookup matches generic key equality and first match across all variants" {
    const keys = [_]AtlasKey{
        .{ .font = .{ .variant = .regular, .face_index = 0, .glyph_id = 7 } },
        .{ .font = .{ .variant = .italic, .face_index = 0, .glyph_id = 7 } },
        .{ .font = .{ .variant = .bold, .face_index = 0, .glyph_id = 7 } },
        .{ .font = .{ .variant = .bold_italic, .face_index = 0, .glyph_id = 7 } },
        .{ .font = .{ .variant = .regular, .face_index = 1, .glyph_id = 7 } },
        .{ .font = .{ .variant = .regular, .face_index = 0, .glyph_id = 8 } },
        .{ .font = .{ .variant = .regular, .face_index = 255, .glyph_id = std.math.maxInt(u32) } },
        .{ .generated = .{ .codepoint = 0x2500, .width = 10, .height = 20, .sizing = .{} } },
        .{ .generated = .{ .codepoint = 0x2501, .width = 10, .height = 20, .sizing = .{} } },
        .{ .generated = .{ .codepoint = 0x2500, .width = 11, .height = 20, .sizing = .{} } },
        .{ .generated = .{ .codepoint = 0x2500, .width = 10, .height = 21, .sizing = .{} } },
        .{ .generated = .{ .codepoint = 0x2500, .width = 10, .height = 20, .sizing = .{ .scale = 2 } } },
        .{ .generated = .{ .codepoint = 0x2500, .width = 10, .height = 20, .sizing = .{ .subscale_n = 1, .subscale_d = 2 } } },
        .{ .generated = .{ .codepoint = 0x2500, .width = 10, .height = 20, .sizing = .{ .subscale_n = 1, .subscale_d = 3 } } },
        .{ .generated = .{ .codepoint = std.math.maxInt(u32), .width = std.math.maxInt(u16), .height = std.math.maxInt(u16), .sizing = .{ .scale = 255, .subscale_n = 14, .subscale_d = 15 } } },
        .{ .smooth_wave = .{ .width = std.math.maxInt(u16), .thickness = std.math.maxInt(u16), .line_height = std.math.maxInt(u16) } },
        .{ .smooth_wave = .{ .width = 10, .thickness = 1, .line_height = 20 } },
        .{ .smooth_wave = .{ .width = 11, .thickness = 1, .line_height = 20 } },
        .{ .smooth_wave = .{ .width = 10, .thickness = 2, .line_height = 20 } },
        .{ .smooth_wave = .{ .width = 10, .thickness = 1, .line_height = 21 } },
    };
    var entries: [2]AtlasEntry = undefined;
    // Lookup borrows only entries/count: no font or raster owner is invoked.
    var impl = AtlasImpl{ .allocator = std.testing.allocator, .fonts = undefined, .box_drawing = undefined, .entries = &entries, .pixels = &.{}, .config = .{ .width = 1, .height = 1, .entry_capacity = 2 } };
    for (keys) |first| for (keys) |second| {
        const retained = [_]AtlasKey{ first, second };
        for (retained, 0..) |key, index|
            entries[index] = .{ .key = atlasIdentity(key), .atlas_x = 0, .atlas_y = 0, .width = 0, .height = 0, .left = 0, .top = 0 };
        for (0..entries.len + 1) |count| {
            impl.entry_count = count;
            for (keys) |key| {
                var expected: ?usize = null;
                for (retained[0..count], 0..) |entry, index| if (std.meta.eql(entry, key)) {
                    expected = index;
                    break;
                };
                try std.testing.expectEqual(expected, findAtlasIndex(&impl, key));
            }
        }
    };
}

fn findAtlas(impl: *const AtlasImpl, key: AtlasKey) ?AtlasEntry {
    const index = findAtlasIndex(impl, key) orelse return null;
    return impl.entries[index];
}

fn cacheAtlas(
    impl: *AtlasImpl,
    key: AtlasKey,
    width: u16,
    height: u16,
    left: i16,
    top: i16,
    pixels: []const u8,
) AtlasError!AtlasRaster {
    if (impl.entry_count == impl.entries.len) return error.CacheFull;
    const expected = std.math.mul(usize, @as(usize, width), @as(usize, height)) catch
        return error.RasterExtentMismatch;
    if (pixels.len != expected) return error.RasterExtentMismatch;

    const pack = try planAtlas(impl, width, height);
    if (width != 0 and height != 0) {
        const pixel_width = @as(usize, width);
        const pixel_height = @as(usize, height);
        const atlas_width = @as(usize, impl.config.width);
        const atlas_height = @as(usize, impl.config.height);
        std.debug.assert(pack.x + pixel_width <= atlas_width);
        std.debug.assert(pack.y + pixel_height <= atlas_height);
        for (0..pixel_height) |row| {
            const source_start = row * pixel_width;
            const destination = (pack.y + row) * atlas_width + pack.x;
            @memcpy(
                impl.pixels[destination .. destination + pixel_width],
                pixels[source_start .. source_start + pixel_width],
            );
        }
    }
    impl.next_x = pack.next_x;
    impl.shelf_y = pack.shelf_y;
    impl.shelf_height = pack.shelf_height;
    const entry = AtlasEntry{
        .key = atlasIdentity(key),
        .atlas_x = @intCast(pack.x),
        .atlas_y = @intCast(pack.y),
        .width = width,
        .height = height,
        .left = left,
        .top = top,
    };
    impl.entries[impl.entry_count] = entry;
    impl.entry_count += 1;
    return atlasRaster(entry);
}

fn atlasRaster(entry: AtlasEntry) AtlasRaster {
    return .{
        .atlas_x = entry.atlas_x,
        .atlas_y = entry.atlas_y,
        .width = entry.width,
        .height = entry.height,
        .left = entry.left,
        .top = entry.top,
    };
}

fn fontVariantIndex(variant: FontVariant) usize {
    return @backingInt(variant);
}

fn planAtlas(impl: *const AtlasImpl, width: u16, height: u16) AtlasError!AtlasPack {
    if (width == 0 or height == 0) {
        return .{
            .x = 0,
            .y = 0,
            .next_x = impl.next_x,
            .shelf_y = impl.shelf_y,
            .shelf_height = impl.shelf_height,
        };
    }
    const atlas_width = @as(usize, impl.config.width);
    const atlas_height = @as(usize, impl.config.height);
    const glyph_width = @as(usize, width);
    const glyph_height = @as(usize, height);
    const gap = @as(usize, impl.config.gap);
    if (glyph_width > atlas_width or glyph_height > atlas_height)
        return error.GlyphTooLarge;

    var x = impl.next_x;
    var y = impl.shelf_y;
    var shelf_height = impl.shelf_height;
    const row_end = std.math.add(usize, x, glyph_width) catch return error.AtlasFull;
    if (x != 0 and row_end > atlas_width) {
        x = 0;
        y = std.math.add(usize, y, shelf_height) catch return error.AtlasFull;
        shelf_height = 0;
    }
    const bottom = std.math.add(usize, y, glyph_height) catch return error.AtlasFull;
    if (bottom > atlas_height) return error.AtlasFull;
    const glyph_end = std.math.add(usize, x, glyph_width) catch return error.AtlasFull;
    const next_x = std.math.add(usize, glyph_end, gap) catch return error.AtlasFull;
    const row_height = std.math.add(usize, glyph_height, gap) catch return error.AtlasFull;
    return .{
        .x = x,
        .y = y,
        .next_x = next_x,
        .shelf_y = y,
        .shelf_height = @max(shelf_height, row_height),
    };
}

fn shapeCacheImpl(cache: *ShapeCache) *ShapeCacheImpl {
    // zig-audit: acknowledge ptr_cast
    // reason: Every mutable ShapeCache originates from a ShapeCacheImpl allocation in initShapeCache at the same address.
    // zig-audit: acknowledge align_cast
    // reason: The originating ShapeCacheImpl allocation guarantees the concrete alignment recovered here.
    return @ptrCast(@alignCast(cache));
}

fn constShapeCacheImpl(cache: *const ShapeCache) *const ShapeCacheImpl {
    // zig-audit: acknowledge ptr_cast
    // reason: Every borrowed ShapeCache originates from a ShapeCacheImpl allocation in initShapeCache at the same address.
    // zig-audit: acknowledge align_cast
    // reason: The originating ShapeCacheImpl allocation guarantees the concrete alignment recovered here.
    return @ptrCast(@alignCast(cache));
}

fn atlasImpl(atlas: *Atlas) *AtlasImpl {
    // zig-audit: acknowledge ptr_cast
    // reason: Every mutable Atlas originates from an AtlasImpl allocation in initAtlas at the same address.
    // zig-audit: acknowledge align_cast
    // reason: The originating AtlasImpl allocation guarantees the concrete alignment recovered here.
    return @ptrCast(@alignCast(atlas));
}

fn constAtlasImpl(atlas: *const Atlas) *const AtlasImpl {
    // zig-audit: acknowledge ptr_cast
    // reason: Every borrowed Atlas originates from an AtlasImpl allocation in initAtlas at the same address.
    // zig-audit: acknowledge align_cast
    // reason: The originating AtlasImpl allocation guarantees the concrete alignment recovered here.
    return @ptrCast(@alignCast(atlas));
}
