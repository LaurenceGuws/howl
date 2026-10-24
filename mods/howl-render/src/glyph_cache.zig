//! Private bounded text-shape and independently packed glyph-plane caches for terminal presentation.
//!
//! This module consumes only howl-text. It owns no terminal/client semantics,
//! renderer resources, host topology, or backend state.

const std = @import("std");
const text = @import("howl_text");
const generated = text.generated;
const limits = @import("limits");

/// Contextual operators may span the complete bounded terminal row.
pub const maximum_contextual_cells = limits.maximum_columns;

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
    /// Empty pixels left after each packed raster on both shelf axes.
    gap: u16 = 1,
    /// Initial lazy colour-plane height. Width is shared; packing is independent.
    color_height: ?u16 = null,
    /// Optional retained ceilings. Existing pixels never relocate during growth.
    growth: ?Growth = null,

    /// Maximum retained records and independently owned plane heights.
    pub const Growth = struct {
        entry_limit: usize,
        alpha_height_limit: u16,
        color_height_limit: u16,
    };
};

/// Caller-selected retained-shaping bounds for one fixed howl-text face family.
///
/// Exact scalar sequences are the cache key. Retained glyph clusters are relative
/// to that sequence and are rebased to each immutable view during projection.
/// Retention is optional: pressure recycles the cache, never restarts a frame.
pub const ShapeCacheConfig = struct {
    entry_capacity: usize,
    scalar_capacity: usize,
    glyph_capacity: usize,
    max_sequence_scalars: u32,
    /// Optional retained ceilings; pressure beyond them still recycles knowledge.
    growth: ?Growth = null,

    /// Maximum retained shaping records; exceeding them keeps the recycle path.
    pub const Growth = struct {
        entry_limit: usize,
        scalar_limit: usize,
        glyph_limit: usize,
    };
};

/// Opaque explicitly owned shaped-run cache.
///
/// No returned frame borrows this storage. Retention pressure and `resetShapeCache`
/// may therefore forget runs without invalidating atlas generations or prior frame
/// placements. A borrowed run lasts only until the next shape-cache operation.
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

/// Reports runtime shaping or caller scratch/sequence-limit failures.
pub const ShapeCacheError = text.ShapeError || text.ShapeBufferInitError || error{
    ShapeSequenceLimit,
};

const AtlasKey = union(enum) {
    font: struct {
        variant: FontVariant,
        face_index: u8,
        glyph_id: u32,
        fit_width: u16 = 0,
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
    format: text.RasterFormat = .alpha8,
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

// Large working sets index retained records; small sets keep their short scan.
// Slots contain entry index + 1, with zero terminating a probe. There are no
// individual deletions, so reset needs no tombstones or retained key copies.
const EntryIndex = struct {
    slots: []u32 = &.{},

    const Probe = struct {
        slots: []const u32,
        at: usize,
        remaining: usize,

        fn next(self: *Probe) ?usize {
            if (self.remaining == 0) return null;
            self.remaining -= 1;
            const value = self.slots[self.at];
            self.at = (self.at + 1) & (self.slots.len - 1);
            if (value == 0) {
                self.remaining = 0;
                return null;
            }
            return value - 1;
        }
    };

    fn probe(self: EntryIndex, hash: u64) Probe {
        std.debug.assert(self.slots.len != 0);
        return .{ .slots = self.slots, .at = @as(usize, @truncate(hash)) & (self.slots.len - 1), .remaining = self.slots.len };
    }

    fn clear(self: *EntryIndex) void {
        @memset(self.slots, 0);
    }

    fn deinit(self: *EntryIndex, allocator: std.mem.Allocator) void {
        allocator.free(self.slots);
        self.* = .{};
    }

    fn add(self: *EntryIndex, hash: u64, index: usize) void {
        if (self.slots.len == 0) return;
        std.debug.assert(index < std.math.maxInt(u32));
        var at = @as(usize, @truncate(hash)) & (self.slots.len - 1);
        for (0..self.slots.len) |_| {
            if (self.slots[at] == 0) {
                self.slots[at] = @intCast(index + 1);
                return;
            }
            at = (at + 1) & (self.slots.len - 1);
        }
        // zig-audit: acknowledge unreachable
        // reason: ensureInsert reserves at least twice the retained count; this bounded insertion must encounter an empty slot.
        unreachable;
    }

    // zig-audit: acknowledge anytype
    // reason: The private index is instantiated only for retained ShapeEntry or AtlasEntry slices, without copying their keys.
    fn ensureInsert(self: *EntryIndex, allocator: std.mem.Allocator, entries: anytype) std.mem.Allocator.Error!void {
        if (entries.len < 64 and self.slots.len == 0) return;
        const count = std.math.add(usize, entries.len, 1) catch return error.OutOfMemory;
        if (count <= self.slots.len / 2) return;
        const needed = std.math.mul(usize, count, 2) catch return error.OutOfMemory;
        const capacity = std.math.ceilPowerOfTwo(usize, needed) catch return error.OutOfMemory;
        var replacement: EntryIndex = .{ .slots = try allocator.alloc(u32, capacity) };
        replacement.clear();
        for (entries, 0..) |entry, index| replacement.add(entryHash(entry), index);
        self.deinit(allocator);
        self.* = replacement;
    }
};

fn shapeIndexHash(hash: u64, variant: FontVariant) u64 {
    return hash ^ (@as(u64, @backingInt(variant)) *% 0x9e3779b97f4a7c15);
}

fn atlasIndexHash(identity: AtlasIdentity) u64 {
    var value = identity.low ^ std.math.rotl(u64, identity.high, 23);
    value = (value ^ (value >> 30)) *% 0xbf58476d1ce4e5b9;
    value = (value ^ (value >> 27)) *% 0x94d049bb133111eb;
    return value ^ (value >> 31);
}

// zig-audit: acknowledge anytype
// reason: The two explicit compile-time cases are the cache-owned retained entry layouts; other types are rejected.
fn entryHash(entry: anytype) u64 {
    if (@TypeOf(entry) == ShapeEntry) {
        return shapeIndexHash(entry.hash, entry.variant);
    } else if (@TypeOf(entry) == AtlasEntry) {
        return atlasIndexHash(entry.key);
    } else {
        @compileError("entry index requires ShapeEntry or AtlasEntry");
    }
}

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
    contextual_shape: ?*text.ShapeBuffer = null,
    entries: []ShapeEntry,
    scalars: []u32,
    glyphs: []text.Glyph,
    max_sequence_scalars: u32,
    // Zero is absent; retained entry references use the same bounded one-based u32 as the index.
    ascii_entries: [font_variant_count][printable_ascii_count]u32 = @splat(@splat(0)),
    entry_count: usize = 0,
    scalar_count: usize = 0,
    glyph_count: usize = 0,
    lookup: EntryIndex = .{},
    bounds: ShapeCacheConfig.Growth = .{ .entry_limit = 0, .scalar_limit = 0, .glyph_limit = 0 },
};

// A raster lookup may additionally retain the placement of one shaped glyph.
// Font/raster coordinates are independent of terminal position and colour.
const AsciiAtlasEntry = struct {
    index: u32 = 0,
    x: i16 = 0,
    y: i16 = 0,
    state: enum { missing, raster, placed } = .missing,
};

const AtlasPacking = struct {
    next_x: usize = 0,
    shelf_y: usize = 0,
    shelf_height: usize = 0,
};

const AtlasPlane = struct {
    pixels: ?[]u8 = null,
    height: u16,
    packing: AtlasPacking = .{},
};

const AtlasImpl = struct {
    allocator: std.mem.Allocator,
    fonts: FontFaces,
    box_drawing: generated.BoxDrawingConfig,
    entries: []AtlasEntry,
    alpha: AtlasPlane,
    color: AtlasPlane,
    color_entries: usize = 0,
    config: AtlasConfig,
    ascii_entries: [font_variant_count][printable_ascii_count]AsciiAtlasEntry = @splat(@splat(.{})),
    entry_count: usize = 0,
    generation: u64 = 1,
    lookup: EntryIndex = .{},
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
    format: text.RasterFormat = .alpha8,
};

/// Reports one current plane extent; growth never changes its width.
pub const AtlasSize = struct {
    width: u16,
    height: u16,
};

/// Allocates one bounded shaped-run owner for one fixed face family.
///
/// Retained-shape storage is allocated during construction. A separate bounded
/// contextual buffer is created lazily only for runs exceeding that capacity.
pub fn initShapeCache(
    allocator: std.mem.Allocator,
    fonts: FontFaces,
    config: ShapeCacheConfig,
) ShapeCacheInitError!*ShapeCache {
    if (config.entry_capacity == 0 or config.entry_capacity > std.math.maxInt(u32) or config.scalar_capacity == 0 or
        config.glyph_capacity == 0 or config.max_sequence_scalars == 0 or
        config.max_sequence_scalars > text.max_codepoints or
        @as(usize, config.max_sequence_scalars) > config.scalar_capacity)
        return error.InvalidShapeCacheConfig;
    const bounds = config.growth orelse ShapeCacheConfig.Growth{
        .entry_limit = config.entry_capacity,
        .scalar_limit = config.scalar_capacity,
        .glyph_limit = config.glyph_capacity,
    };
    if (bounds.entry_limit < config.entry_capacity or bounds.entry_limit > std.math.maxInt(u32) or
        bounds.scalar_limit < config.scalar_capacity or bounds.glyph_limit < config.glyph_capacity)
        return error.InvalidShapeCacheConfig;
    const entry_bytes = std.math.mul(usize, bounds.entry_limit, @sizeOf(ShapeEntry)) catch return error.InvalidShapeCacheConfig;
    const scalar_bytes = std.math.mul(usize, bounds.scalar_limit, @sizeOf(u32)) catch return error.InvalidShapeCacheConfig;
    const glyph_bytes = std.math.mul(usize, bounds.glyph_limit, @sizeOf(text.Glyph)) catch return error.InvalidShapeCacheConfig;
    const retained_bytes = std.math.add(usize, entry_bytes, scalar_bytes) catch return error.InvalidShapeCacheConfig;
    const maximum_bytes = std.math.add(usize, retained_bytes, glyph_bytes) catch return error.InvalidShapeCacheConfig;
    std.debug.assert(maximum_bytes != 0);

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
        .bounds = bounds,
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
    const contextual_shape = impl.contextual_shape;
    const entries = impl.entries;
    const scalars = impl.scalars;
    const glyphs = impl.glyphs;
    impl.lookup.deinit(allocator);
    impl.* = undefined;
    shape.deinit();
    if (contextual_shape) |value| value.deinit();
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
    impl.lookup.clear();
    impl.ascii_entries = @splat(@splat(0));
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

/// Allocates one bounded alpha atlas. Misses rasterize through caller scratch;
/// the bounded colour plane is allocated lazily on the first colour glyph.
pub fn initAtlas(
    allocator: std.mem.Allocator,
    fonts: FontFaces,
    box_drawing: generated.BoxDrawingConfig,
    config: AtlasConfig,
) AtlasInitError!*Atlas {
    if (config.width == 0 or config.height == 0 or config.entry_capacity == 0 or config.entry_capacity > std.math.maxInt(u32))
        return error.InvalidAtlasConfig;
    const color_height = config.color_height orelse config.height;
    const bounds = config.growth orelse AtlasConfig.Growth{
        .entry_limit = config.entry_capacity,
        .alpha_height_limit = config.height,
        .color_height_limit = color_height,
    };
    if (color_height == 0 or bounds.entry_limit < config.entry_capacity or
        bounds.entry_limit > std.math.maxInt(u32) or
        bounds.alpha_height_limit < config.height or bounds.color_height_limit < color_height)
        return error.InvalidAtlasConfig;
    const alpha_bound = std.math.mul(usize, @as(usize, config.width), bounds.alpha_height_limit) catch
        return error.InvalidAtlasConfig;
    const color_area = std.math.mul(usize, @as(usize, config.width), bounds.color_height_limit) catch
        return error.InvalidAtlasConfig;
    const color_bound = std.math.mul(usize, color_area, 4) catch return error.InvalidAtlasConfig;
    // framePixelBytes sums independently resident planes without overflow.
    const combined_bound = std.math.add(usize, alpha_bound, color_bound) catch return error.InvalidAtlasConfig;
    const entry_bound = std.math.mul(usize, bounds.entry_limit, @sizeOf(AtlasEntry)) catch return error.InvalidAtlasConfig;
    const retained_bound = std.math.add(usize, combined_bound, entry_bound) catch return error.InvalidAtlasConfig;
    std.debug.assert(retained_bound >= alpha_bound);
    const pixel_count = @as(usize, config.width) * config.height;

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
        .alpha = .{ .pixels = pixels, .height = config.height },
        .color = .{ .height = color_height },
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
    const pixels = impl.alpha.pixels.?;
    const color_pixels = impl.color.pixels;
    impl.lookup.deinit(allocator);
    impl.* = undefined;
    allocator.free(pixels);
    if (color_pixels) |value| allocator.free(value);
    allocator.free(entries);
    allocator.destroy(impl);
}

/// Explicitly invalidates every cached glyph and begins a new zeroed generation.
pub fn resetAtlas(atlas: *Atlas) error{GenerationOverflow}!void {
    const impl = atlasImpl(atlas);
    if (impl.generation == std.math.maxInt(u64)) return error.GenerationOverflow;
    impl.generation += 1;
    impl.entry_count = 0;
    impl.lookup.clear();
    impl.color_entries = 0;
    impl.ascii_entries = @splat(@splat(.{}));
    impl.alpha.packing = .{};
    impl.color.packing = .{};
    @memset(impl.alpha.pixels.?, 0);
    if (impl.color.pixels) |value| @memset(value, 0);
}

/// Borrows the complete alpha image and private reset epoch until atlas mutation.
pub fn atlasView(atlas: *const Atlas) AtlasView {
    const impl = constAtlasImpl(atlas);
    return .{
        .generation = impl.generation,
        .width = impl.config.width,
        .height = impl.alpha.height,
        .pixels = impl.alpha.pixels.?,
    };
}

/// Returns the number of currently retained atlas entries.
pub fn atlasEntryCount(atlas: *const Atlas) usize {
    return constAtlasImpl(atlas).entry_count;
}

/// Counts alpha entries independently from intrinsic-colour additions.
pub fn alphaAtlasEntryCount(atlas: *const Atlas) usize {
    const impl = constAtlasImpl(atlas);
    return impl.entry_count - impl.color_entries;
}

/// Borrows the independently packed lazy straight-RGBA plane.
pub fn colorAtlasView(atlas: *const Atlas) ?AtlasView {
    const impl = constAtlasImpl(atlas);
    return .{ .generation = impl.generation, .width = impl.config.width, .height = impl.color.height, .pixels = impl.color.pixels orelse return null };
}

/// Counts colour entries independently so alpha misses do not republish colour.
pub fn colorAtlasEntryCount(atlas: *const Atlas) usize {
    return constAtlasImpl(atlas).color_entries;
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

/// Returns the current alpha extent.
pub fn atlasSize(atlas: *const Atlas) AtlasSize {
    const impl = constAtlasImpl(atlas);
    return .{ .width = impl.config.width, .height = impl.alpha.height };
}

/// Returns the current colour extent, including before its first allocation.
pub fn colorAtlasSize(atlas: *const Atlas) AtlasSize {
    const impl = constAtlasImpl(atlas);
    return .{ .width = impl.config.width, .height = impl.color.height };
}

/// Shapes one bounded row of operators without retaining it in ShapeCache.
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
    if (sequence.len < 2 or sequence.len > maximum_contextual_cells or
        sequence.len > cluster_scratch.len)
        return null;
    if ((try fonts.faceFor(sequence)) != 0) return null;
    for (cluster_scratch[0..sequence.len], 0..) |*cluster, index|
        cluster.* = @intCast(index);
    const buffer = if (sequence.len <= impl.max_sequence_scalars) impl.shape else blk: {
        if (impl.contextual_shape == null)
            impl.contextual_shape = try text.ShapeBuffer.init(impl.allocator, maximum_contextual_cells * 2);
        break :blk impl.contextual_shape.?;
    };
    return try fonts.shape(
        buffer,
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
/// retains the resulting shape for allocation-free reuse while capacity permits.
/// A miss recycles retained runs when needed; a run larger than glyph retention
/// uses caller scratch. The returned run lasts until the next cache operation.
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
    const variant_index = fontVariantIndex(resolved_variant);
    if (sequence.len == 0 or sequence.len > @as(usize, impl.max_sequence_scalars))
        return error.ShapeSequenceLimit;
    const ascii_index = printableAsciiIndex(sequence);
    if (ascii_index) |index| {
        const retained = impl.ascii_entries[variant_index][index];
        if (retained != 0) {
            const entry_index: usize = retained - 1;
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
    if (@call(.always_inline, findShapeIndex, .{ impl, resolved_variant, sequence, hash })) |entry_index| {
        if (ascii_index) |index| impl.ascii_entries[variant_index][index] = @intCast(entry_index + 1);
        return shapeEntryRun(impl, entry_index);
    }

    return @call(.never_inline, shapeAndRetain, .{ cache, resolved_variant, sequence, cluster_scratch, glyph_scratch, hash, ascii_index });
}

fn shapeAndRetain(
    cache: *ShapeCache,
    resolved_variant: FontVariant,
    sequence: []const u32,
    cluster_scratch: []u32,
    glyph_scratch: []text.Glyph,
    hash: u64,
    ascii_index: ?usize,
) ShapeCacheError!text.Run {
    const impl = shapeCacheImpl(cache);
    const fonts = impl.fonts.select(resolved_variant);
    const variant_index = fontVariantIndex(resolved_variant);
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
    // Glyph runs are consumed before the next resolve; completed commands own
    // their placements. Reclaiming shape knowledge cannot invalidate atlas ink.
    if (shaped.glyphs.len > impl.bounds.glyph_limit) return shaped;
    if (impl.entry_count == impl.entries.len or
        sequence.len > impl.scalars.len - impl.scalar_count or
        shaped.glyphs.len > impl.glyphs.len - impl.glyph_count)
    {
        if (!try growShapeStorage(impl, sequence.len, shaped.glyphs.len))
            resetShapeCache(cache);
    }

    try impl.lookup.ensureInsert(impl.allocator, impl.entries[0..impl.entry_count]);

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
    impl.lookup.add(shapeIndexHash(hash, resolved_variant), entry_index);
    if (ascii_index) |index| impl.ascii_entries[variant_index][index] = @intCast(entry_index + 1);
    return shapeEntryRun(impl, entry_index);
}

fn growShapeStorage(impl: *ShapeCacheImpl, scalar_count: usize, glyph_count: usize) std.mem.Allocator.Error!bool {
    const entries = std.math.add(usize, impl.entry_count, 1) catch return false;
    const scalars = std.math.add(usize, impl.scalar_count, scalar_count) catch return false;
    const glyphs = std.math.add(usize, impl.glyph_count, glyph_count) catch return false;
    if (entries > impl.bounds.entry_limit or scalars > impl.bounds.scalar_limit or glyphs > impl.bounds.glyph_limit)
        return false;
    const entry_capacity = growthCapacity(impl.entries.len, entries, impl.bounds.entry_limit);
    const scalar_capacity = growthCapacity(impl.scalars.len, scalars, impl.bounds.scalar_limit);
    const glyph_capacity = growthCapacity(impl.glyphs.len, glyphs, impl.bounds.glyph_limit);
    var next_entries: ?[]ShapeEntry = null;
    errdefer if (next_entries) |value| impl.allocator.free(value);
    var next_scalars: ?[]u32 = null;
    errdefer if (next_scalars) |value| impl.allocator.free(value);
    var next_glyphs: ?[]text.Glyph = null;
    errdefer if (next_glyphs) |value| impl.allocator.free(value);
    if (entry_capacity != impl.entries.len) {
        next_entries = try impl.allocator.alloc(ShapeEntry, entry_capacity);
        @memcpy(next_entries.?[0..impl.entry_count], impl.entries[0..impl.entry_count]);
    }
    if (scalar_capacity != impl.scalars.len) {
        next_scalars = try impl.allocator.alloc(u32, scalar_capacity);
        @memcpy(next_scalars.?[0..impl.scalar_count], impl.scalars[0..impl.scalar_count]);
    }
    if (glyph_capacity != impl.glyphs.len) {
        next_glyphs = try impl.allocator.alloc(text.Glyph, glyph_capacity);
        @memcpy(next_glyphs.?[0..impl.glyph_count], impl.glyphs[0..impl.glyph_count]);
    }
    if (next_entries) |value| {
        impl.allocator.free(impl.entries);
        impl.entries = value;
    }
    if (next_scalars) |value| {
        impl.allocator.free(impl.scalars);
        impl.scalars = value;
    }
    if (next_glyphs) |value| {
        impl.allocator.free(impl.glyphs);
        impl.glyphs = value;
    }
    return true;
}

fn shapeEntryMatches(impl: *const ShapeCacheImpl, index: usize, variant: FontVariant, sequence: []const u32, hash: u64) bool {
    const entry = impl.entries[index];
    if (entry.variant != variant or entry.hash != hash or entry.scalar_count != sequence.len) return false;
    return std.mem.eql(u32, impl.scalars[entry.scalar_offset..][0..entry.scalar_count], sequence);
}

fn findIndexedShape(impl: *const ShapeCacheImpl, variant: FontVariant, sequence: []const u32, hash: u64) ?usize {
    var probe = impl.lookup.probe(shapeIndexHash(hash, variant));
    while (probe.next()) |index| {
        std.debug.assert(index < impl.entry_count);
        if (shapeEntryMatches(impl, index, variant, sequence, hash)) return index;
    }
    return null;
}

fn findShapeIndex(impl: *const ShapeCacheImpl, variant: FontVariant, sequence: []const u32, hash: u64) ?usize {
    if (impl.entry_count > 64)
        return @call(.never_inline, findIndexedShape, .{ impl, variant, sequence, hash });
    for (impl.entries[0..impl.entry_count], 0..) |entry, index| {
        if (entry.variant != variant or entry.hash != hash or entry.scalar_count != sequence.len) continue;
        const retained = impl.scalars[entry.scalar_offset..][0..entry.scalar_count];
        if (std.mem.eql(u32, retained, sequence)) return index;
    }
    return null;
}

/// Resolves one native font glyph into its bounded raster-format plane, rasterizing into
/// caller scratch only on cache miss. `ascii_index` is an optional dense lookup
/// hint derived from the source scalar and never changes atlas identity.
pub fn resolveFontAtlas(
    atlas: *Atlas,
    variant: FontVariant,
    face_index: u8,
    glyph_id: u32,
    raster_scratch: []u8,
    ascii_index: ?usize,
    fit_width: u16,
) AtlasError!AtlasRaster {
    const impl = atlasImpl(atlas);
    const resolved_variant = impl.fonts.resolveVariant(variant);
    const variant_index = fontVariantIndex(resolved_variant);
    const key = AtlasKey{ .font = .{
        .variant = resolved_variant,
        .face_index = face_index,
        .glyph_id = glyph_id,
        .fit_width = fit_width,
    } };
    if (ascii_index) |index| {
        const lookup = impl.ascii_entries[variant_index][index];
        if (lookup.state != .missing) {
            const entry_index = lookup.index;
            std.debug.assert(entry_index < impl.entry_count);
            const entry = impl.entries[entry_index];
            std.debug.assert(std.meta.eql(entry.key, atlasIdentity(key)));
            return atlasRaster(entry);
        }
    }
    if (findAtlasIndex(impl, key)) |entry_index| {
        if (ascii_index) |index| impl.ascii_entries[variant_index][index] = .{ .index = @intCast(entry_index), .state = .raster };
        return atlasRaster(impl.entries[entry_index]);
    }

    return @call(.never_inline, rasterizeAndRetain, .{ atlas, key, raster_scratch, ascii_index });
}

fn rasterizeAndRetain(atlas: *Atlas, key: AtlasKey, raster_scratch: []u8, ascii_index: ?usize) AtlasError!AtlasRaster {
    const impl = atlasImpl(atlas);
    const fonts = impl.fonts.select(key.font.variant);
    const variant_index = fontVariantIndex(key.font.variant);
    const face_index = key.font.face_index;
    const glyph_id = key.font.glyph_id;
    const fit_width = key.font.fit_width;
    var raster_allocator = std.heap.FixedBufferAllocator.init(raster_scratch);
    var produced = if (fit_width == 0)
        try fonts.rasterizeGlyph(raster_allocator.allocator(), face_index, glyph_id)
    else
        try fonts.rasterizeGlyphFitted(raster_allocator.allocator(), face_index, glyph_id, fit_width, 2);
    defer produced.deinit();
    const raster = produced.raster;
    const expected_pixels = std.math.mul(
        usize,
        @as(usize, raster.width),
        @as(usize, raster.height),
    ) catch return error.RasterExtentMismatch;
    const expected = std.math.mul(usize, expected_pixels, if (produced.format == .rgba8) 4 else 1) catch return error.RasterExtentMismatch;
    if (expected != raster.pixels.len) return error.RasterExtentMismatch;
    const result = try cacheRaster(
        impl,
        key,
        raster.width,
        raster.height,
        raster.left,
        raster.top,
        raster.pixels,
        produced.format,
    );
    if (ascii_index) |index| {
        std.debug.assert(impl.entry_count != 0);
        impl.ascii_entries[variant_index][index] = .{ .index = @intCast(impl.entry_count - 1), .state = .raster };
    }
    return result;
}

/// Copies a single alpha glyph's atlas locator and integer baseline-relative placement.
pub const AsciiPlacement = struct { raster: AtlasRaster, x: i32, y: i32 };

/// Reuses only placement previously admitted for this immutable font variant and scalar.
pub fn asciiPlacement(atlas: *const Atlas, variant: FontVariant, index: usize) ?AsciiPlacement {
    const impl = constAtlasImpl(atlas);
    const lookup = impl.ascii_entries[fontVariantIndex(impl.fonts.resolveVariant(variant))][index];
    if (lookup.state != .placed) return null;
    return .{ .raster = atlasRaster(impl.entries[lookup.index]), .x = lookup.x, .y = lookup.y };
}

/// Retains one proven single-glyph alpha placement; unrepresentable offsets keep the ordinary path.
pub fn rememberAsciiPlacement(atlas: *Atlas, variant: FontVariant, index: usize, shaped: text.Glyph, raster: AtlasRaster) void {
    if (raster.format != .alpha8 or raster.width == 0 or raster.height == 0) return;
    const position = asciiPlacementOffset(shaped, raster) orelse return;
    const impl = atlasImpl(atlas);
    const lookup = &impl.ascii_entries[fontVariantIndex(impl.fonts.resolveVariant(variant))][index];
    std.debug.assert(lookup.state != .missing);
    lookup.x = position.x;
    lookup.y = position.y;
    lookup.state = .placed;
}

fn asciiPlacementOffset(shaped: text.Glyph, raster: AtlasRaster) ?struct { x: i16, y: i16 } {
    // Narrow cache admission only; the ordinary geometry path keeps its full range.
    return .{
        .x = std.math.cast(i16, @divFloor(@as(i64, shaped.x_offset) + @as(i64, raster.left) * 64, 64)) orelse return null,
        .y = std.math.cast(i16, @divFloor(-@as(i64, shaped.y_offset) - @as(i64, raster.top) * 64, 64)) orelse return null,
    };
}

test "ASCII placement cache floors negative fractions and declines oversized offsets" {
    try std.testing.expect(@sizeOf(AsciiAtlasEntry) <= 12);
    var shaped = std.mem.zeroes(text.Glyph);
    var raster: AtlasRaster = .{ .atlas_x = 0, .atlas_y = 0, .width = 1, .height = 1, .left = -1, .top = 1, .format = .alpha8 };
    shaped.x_offset = -1;
    shaped.y_offset = -1;
    const offset = asciiPlacementOffset(shaped, raster).?;
    try std.testing.expectEqual(@as(i16, -2), offset.x);
    try std.testing.expectEqual(@as(i16, -1), offset.y);
    shaped.x_offset = std.math.maxInt(i32);
    try std.testing.expect(asciiPlacementOffset(shaped, raster) == null);
    shaped.x_offset = 0;
    shaped.y_offset = std.math.minInt(i32);
    try std.testing.expect(asciiPlacementOffset(shaped, raster) == null);
    shaped.y_offset = 0;
    raster.left = std.math.minInt(i16);
    raster.top = std.math.maxInt(i16);
    const edge = asciiPlacementOffset(shaped, raster).?;
    try std.testing.expectEqual(std.math.minInt(i16), edge.x);
    try std.testing.expectEqual(-std.math.maxInt(i16), edge.y);
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
        .font => |v| .{ .low = @as(u64, v.glyph_id) | (@as(u64, v.face_index) << 32) | (@as(u64, @backingInt(v.variant)) << 40), .high = @as(u64, v.fit_width) << 32 },
        .smooth_wave => |v| .{ .low = @as(u64, v.width) | (@as(u64, v.thickness) << 16) | (@as(u64, v.line_height) << 32), .high = 1 << 16 },
        .generated => |v| .{ .low = @as(u64, v.codepoint) | (@as(u64, v.width) << 32) | (@as(u64, v.height) << 48), .high = (2 << 16) | @as(u64, v.sizing.scale) | (@as(u64, v.sizing.subscale_n) << 8) | (@as(u64, v.sizing.subscale_d) << 12) },
    };
}

fn findIndexedAtlas(impl: *const AtlasImpl, wanted: AtlasIdentity) ?usize {
    var probe = impl.lookup.probe(atlasIndexHash(wanted));
    while (probe.next()) |index| {
        std.debug.assert(index < impl.entry_count);
        const entry = impl.entries[index];
        if (entry.key.low == wanted.low and entry.key.high == wanted.high) return index;
    }
    return null;
}

fn findAtlasIndex(impl: *const AtlasImpl, key: AtlasKey) ?usize {
    const wanted = atlasIdentity(key);
    if (impl.entry_count > 64)
        return @call(.never_inline, findIndexedAtlas, .{ impl, wanted });
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
        .{ .font = .{ .variant = .regular, .face_index = 0, .glyph_id = 8, .fit_width = 9 } },
        .{ .font = .{ .variant = .regular, .face_index = 0, .glyph_id = 8, .fit_width = 18 } },
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
    var impl = AtlasImpl{ .allocator = std.testing.allocator, .fonts = undefined, .box_drawing = undefined, .entries = &entries, .alpha = .{ .pixels = &.{}, .height = 1 }, .color = .{ .height = 1 }, .config = .{ .width = 1, .height = 1, .entry_capacity = 2 } };
    var slots: [8]u32 = @splat(0);
    for ([_]bool{ false, true }) |indexed| {
        impl.lookup.slots = if (indexed) &slots else &.{};
        for (keys) |first| for (keys) |second| {
            const retained = [_]AtlasKey{ first, second };
            for (retained, 0..) |key, index|
                entries[index] = .{ .key = atlasIdentity(key), .atlas_x = 0, .atlas_y = 0, .width = 0, .height = 0, .left = 0, .top = 0 };
            for (0..entries.len + 1) |count| {
                impl.entry_count = count;
                impl.lookup.clear();
                for (entries[0..count], 0..) |entry, index| impl.lookup.add(atlasIndexHash(entry.key), index);
                for (keys) |key| {
                    var expected: ?usize = null;
                    for (retained[0..count], 0..) |entry, index| if (std.meta.eql(entry, key)) {
                        expected = index;
                        break;
                    };
                    try std.testing.expectEqual(expected, if (indexed) findIndexedAtlas(&impl, atlasIdentity(key)) else findAtlasIndex(&impl, key));
                }
            }
        };
    }
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
    return @call(.never_inline, cacheRaster, .{ impl, key, width, height, left, top, pixels, .alpha8 });
}

fn cacheRaster(
    impl: *AtlasImpl,
    key: AtlasKey,
    width: u16,
    height: u16,
    left: i16,
    top: i16,
    pixels: []const u8,
    format: text.RasterFormat,
) AtlasError!AtlasRaster {
    const entry_limit = if (impl.config.growth) |value| value.entry_limit else impl.entries.len;
    if (impl.entry_count == entry_limit) return error.CacheFull;
    const channels: usize = if (format == .rgba8) 4 else 1;
    const expected = std.math.mul(usize, @as(usize, width) * height, channels) catch
        return error.RasterExtentMismatch;
    if (pixels.len != expected) return error.RasterExtentMismatch;
    const plane = if (format == .rgba8) &impl.color else &impl.alpha;
    const height_limit = if (impl.config.growth) |value|
        (if (format == .rgba8) value.color_height_limit else value.alpha_height_limit)
    else
        plane.height;
    var next_height = plane.height;
    const pack = while (true) {
        const planned = planAtlas(impl.config.width, next_height, impl.config.gap, plane.packing, width, height) catch |failure| {
            if (width > impl.config.width or next_height == height_limit) return failure;
            next_height = @intCast(growthCapacity(next_height, @as(usize, next_height) + 1, height_limit));
            continue;
        };
        break planned;
    };
    const next_capacity = growthCapacity(impl.entries.len, impl.entry_count + 1, entry_limit);
    try impl.lookup.ensureInsert(impl.allocator, impl.entries[0..impl.entry_count]);

    var replacement_entries: ?[]AtlasEntry = null;
    errdefer if (replacement_entries) |value| impl.allocator.free(value);
    if (next_capacity != impl.entries.len) {
        replacement_entries = try impl.allocator.alloc(AtlasEntry, next_capacity);
        @memcpy(replacement_entries.?[0..impl.entry_count], impl.entries[0..impl.entry_count]);
    }
    var replacement_pixels: ?[]u8 = null;
    errdefer if (replacement_pixels) |value| impl.allocator.free(value);
    if (plane.pixels == null or next_height != plane.height) {
        const bytes = @as(usize, impl.config.width) * next_height * channels;
        replacement_pixels = try impl.allocator.alloc(u8, bytes);
        @memset(replacement_pixels.?, 0);
        if (plane.pixels) |prior| @memcpy(replacement_pixels.?[0..prior.len], prior);
    }
    // Nothing fallible follows admission. Old logical keys and ink survive
    // every allocation failure; growing a plane never moves a raster.
    if (replacement_entries) |value| {
        impl.allocator.free(impl.entries);
        impl.entries = value;
    }
    if (replacement_pixels) |value| {
        if (plane.pixels) |prior| impl.allocator.free(prior);
        plane.pixels = value;
        plane.height = next_height;
    }
    const plane_pixels = plane.pixels.?;
    if (width != 0 and height != 0) {
        const pixel_width = @as(usize, width);
        const pixel_height = @as(usize, height);
        const atlas_width = @as(usize, impl.config.width);
        std.debug.assert(pack.x + pixel_width <= atlas_width);
        std.debug.assert(pack.y + pixel_height <= plane.height);
        for (0..pixel_height) |row| {
            const source_start = row * pixel_width * channels;
            const destination = ((pack.y + row) * atlas_width + pack.x) * channels;
            @memcpy(
                plane_pixels[destination .. destination + pixel_width * channels],
                pixels[source_start .. source_start + pixel_width * channels],
            );
        }
    }
    plane.packing = .{
        .next_x = pack.next_x,
        .shelf_y = pack.shelf_y,
        .shelf_height = pack.shelf_height,
    };
    const entry = AtlasEntry{
        .key = atlasIdentity(key),
        .atlas_x = @intCast(pack.x),
        .atlas_y = @intCast(pack.y),
        .width = width,
        .height = height,
        .left = left,
        .top = top,
        .format = format,
    };
    impl.entries[impl.entry_count] = entry;
    impl.lookup.add(atlasIndexHash(entry.key), impl.entry_count);
    impl.entry_count += 1;
    if (format == .rgba8) impl.color_entries += 1;
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
        .format = entry.format,
    };
}

fn fontVariantIndex(variant: FontVariant) usize {
    return @backingInt(variant);
}

fn growthCapacity(current: usize, needed: usize, limit: usize) usize {
    std.debug.assert(current != 0 and current <= limit and needed <= limit);
    if (needed <= current) return current;
    return @min(limit, @max(needed, std.math.mul(usize, current, 2) catch limit));
}

fn planAtlas(plane_width: u16, plane_height: u16, plane_gap: u16, packing: AtlasPacking, width: u16, height: u16) AtlasError!AtlasPack {
    if (width == 0 or height == 0) {
        return .{
            .x = 0,
            .y = 0,
            .next_x = packing.next_x,
            .shelf_y = packing.shelf_y,
            .shelf_height = packing.shelf_height,
        };
    }
    const atlas_width = @as(usize, plane_width);
    const atlas_height = @as(usize, plane_height);
    const glyph_width = @as(usize, width);
    const glyph_height = @as(usize, height);
    const gap = @as(usize, plane_gap);
    if (glyph_width > atlas_width or glyph_height > atlas_height)
        return error.GlyphTooLarge;

    var x = packing.next_x;
    var y = packing.shelf_y;
    var shelf_height = packing.shelf_height;
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

test "shape index compares exact sequences and variants under a complete hash collision" {
    const allocator = std.testing.allocator;
    var entries: [130]ShapeEntry = undefined;
    var scalars: [130]u32 = undefined;
    var lookup: EntryIndex = .{};
    defer lookup.deinit(allocator);
    for (&entries, &scalars, 0..) |*entry, *scalar, index| {
        scalar.* = @intCast(0x100 + index);
        try lookup.ensureInsert(allocator, entries[0..index]);
        entry.* = .{
            .hash = 7,
            .variant = .regular,
            .scalar_offset = index,
            .scalar_count = 1,
            .glyph_offset = 0,
            .glyph_count = 0,
            .face_index = 0,
        };
        lookup.add(shapeIndexHash(7, .regular), index);
    }
    var impl: ShapeCacheImpl = .{
        .allocator = allocator,
        .fonts = undefined,
        .shape = undefined,
        .entries = &entries,
        .lookup = lookup,
        .scalars = &scalars,
        .glyphs = &.{},
        .max_sequence_scalars = 2,
        .entry_count = entries.len,
        .scalar_count = scalars.len,
    };
    try std.testing.expect(lookup.slots.len >= entries.len * 2);
    for (scalars, 0..) |scalar, index| {
        try std.testing.expectEqual(@as(?usize, index), findShapeIndex(&impl, .regular, &.{scalar}, 7));
        try std.testing.expect(findShapeIndex(&impl, .bold, &.{scalar}, 7) == null);
        try std.testing.expect(findShapeIndex(&impl, .regular, &.{scalar}, 8) == null);
        try std.testing.expect(findShapeIndex(&impl, .regular, &.{ scalar, scalar }, 7) == null);
    }
    try std.testing.expect(findShapeIndex(&impl, .regular, &.{0xffff}, 7) == null);
    impl.lookup.clear();
    try std.testing.expect(findIndexedShape(&impl, .regular, &.{scalars[0]}, 7) == null);
    // A malformed all-occupied synthetic table must still terminate its probe.
    var full = [_]u32{ 1, 1, 1, 1 };
    var probe = (EntryIndex{ .slots = &full }).probe(7);
    for (0..full.len) |_| try std.testing.expectEqual(@as(?usize, 0), probe.next());
    try std.testing.expect(probe.next() == null);
}

fn atlasIndexAllocationProof(allocator: std.mem.Allocator) !void {
    const owner = try initAtlas(allocator, .{ .regular = undefined }, .{
        .dpi_x = .{ .numerator = 96, .denominator = 1 },
        .dpi_y = .{ .numerator = 96, .denominator = 1 },
    }, .{ .width = 32, .height = 32, .entry_capacity = 130 });
    defer deinitAtlas(owner);
    const impl = atlasImpl(owner);
    const pixels = [_]u8{ 255, 255, 255, 255 };
    for (0..130) |index| {
        const key = AtlasKey{ .font = .{ .variant = .regular, .face_index = 0, .glyph_id = @intCast(index) } };
        // zig-audit: acknowledge discard
        // reason: Lookup identity, retained pixels and reset behavior are asserted after packing.
        _ = try cacheRaster(impl, key, 1, 1, 0, 1, pixels[0..if (index == 65) @as(usize, 4) else 1], if (index == 65) .rgba8 else .alpha8);
    }
    try std.testing.expectEqual(@as(usize, 130), impl.entry_count);
    try std.testing.expect(impl.lookup.slots.len >= 260);
    for (0..130) |index| {
        const key = AtlasKey{ .font = .{ .variant = .regular, .face_index = 0, .glyph_id = @intCast(index) } };
        try std.testing.expectEqual(@as(?usize, index), findAtlasIndex(impl, key));
        const entry = impl.entries[index];
        const plane = if (index == 65) impl.color.pixels.? else impl.alpha.pixels.?;
        const stride: usize = if (index == 65) 4 else 1;
        const at = (@as(usize, entry.atlas_y) * impl.config.width + entry.atlas_x) * stride;
        try std.testing.expectEqualSlices(u8, pixels[0..stride], plane[at..][0..stride]);
    }
    const overflow = AtlasKey{ .font = .{ .variant = .regular, .face_index = 0, .glyph_id = 999 } };
    try std.testing.expectError(error.CacheFull, cacheRaster(impl, overflow, 1, 1, 0, 1, pixels[0..1], .alpha8));
    const before = impl.generation;
    try resetAtlas(owner);
    try std.testing.expectEqual(before + 1, impl.generation);
    try std.testing.expectEqual(@as(usize, 0), impl.entry_count);
    try std.testing.expect(findAtlasIndex(impl, overflow) == null);
    // zig-audit: acknowledge discard
    // reason: After reset, the new key must resolve at the first retained entry.
    _ = try cacheRaster(impl, overflow, 1, 1, 0, 1, pixels[0..1], .alpha8);
    try std.testing.expectEqual(@as(?usize, 0), findAtlasIndex(impl, overflow));
}

test "atlas indexing preserves raster identity reset bounds and allocation cleanup" {
    try atlasIndexAllocationProof(std.testing.allocator);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, atlasIndexAllocationProof, .{});
}

test "entry capacity must fit nonzero u32 index records" {
    if (@sizeOf(usize) == 4) return;
    const fonts: FontFaces = .{ .regular = undefined };
    try std.testing.expectError(error.InvalidShapeCacheConfig, initShapeCache(std.testing.allocator, fonts, .{
        .entry_capacity = std.math.maxInt(usize),
        .scalar_capacity = 1,
        .glyph_capacity = 1,
        .max_sequence_scalars = 1,
    }));
    try std.testing.expectError(error.InvalidAtlasConfig, initAtlas(std.testing.allocator, fonts, .{
        .dpi_x = .{ .numerator = 96, .denominator = 1 },
        .dpi_y = .{ .numerator = 96, .denominator = 1 },
    }, .{ .width = 1, .height = 1, .entry_capacity = std.math.maxInt(usize) }));
}

fn expectAdmittedRasters(impl: *const AtlasImpl, count: usize) !void {
    try std.testing.expectEqual(count, impl.entry_count);
    for (0..count) |index| {
        const key = AtlasKey{ .font = .{ .variant = .regular, .face_index = 0, .glyph_id = @intCast(index) } };
        try std.testing.expectEqual(@as(?usize, index), findAtlasIndex(impl, key));
        const entry = impl.entries[index];
        const color = index % 5 == 4;
        try std.testing.expectEqual(if (color) text.RasterFormat.rgba8 else .alpha8, entry.format);
        const plane = if (color) impl.color else impl.alpha;
        const channels: usize = if (color) 4 else 1;
        const pixels = plane.pixels.?;
        for (0..2) |row| for (0..2) |column| {
            const at = ((@as(usize, entry.atlas_y) + row) * impl.config.width + entry.atlas_x + column) * channels;
            for (0..channels) |channel| {
                const expected: u8 = if (color and channel == 3) 255 else @intCast(index + 1);
                try std.testing.expectEqual(expected, pixels[at + channel]);
            }
        };
    }
}

fn atlasGrowthAllocationProof(allocator: std.mem.Allocator) !void {
    const owner = try initAtlas(allocator, .{ .regular = undefined }, .{
        .dpi_x = .{ .numerator = 96, .denominator = 1 },
        .dpi_y = .{ .numerator = 96, .denominator = 1 },
    }, .{
        .width = 8,
        .height = 2,
        .color_height = 1,
        .entry_capacity = 2,
        .gap = 0,
        .growth = .{ .entry_limit = 130, .alpha_height_limit = 64, .color_height_limit = 16 },
    });
    defer deinitAtlas(owner);
    const impl = atlasImpl(owner);
    for (0..130) |index| {
        const color = index % 5 == 4;
        var pixels: [16]u8 = @splat(@intCast(index + 1));
        if (color) for (0..4) |pixel| {
            pixels[pixel * 4 + 3] = 255;
        };
        const key = AtlasKey{ .font = .{ .variant = .regular, .face_index = 0, .glyph_id = @intCast(index) } };
        const placed = cacheRaster(impl, key, 2, 2, -1, 2, pixels[0..if (color) @as(usize, 16) else 4], if (color) .rgba8 else .alpha8) catch |failure| {
            // Every previously admitted key/texel remains usable after any failed
            // entry, index, lazy-colour or height allocation.
            try expectAdmittedRasters(impl, index);
            return failure;
        };
        try std.testing.expectEqual(@as(i16, -1), placed.left);
        if (index == 3) {
            try std.testing.expectEqual(@as(u16, 2), impl.alpha.height);
            try std.testing.expect(impl.color.pixels == null);
        }
        if (index == 4) {
            try std.testing.expectEqual(@as(u16, 2), impl.alpha.height);
            try std.testing.expectEqual(@as(u16, 2), impl.color.height);
            try std.testing.expectEqual(@as(u16, 0), placed.atlas_x);
            try std.testing.expectEqual(@as(u16, 0), placed.atlas_y);
        }
    }
    try expectAdmittedRasters(impl, 130);
    try std.testing.expectEqual(@as(usize, 130), impl.entries.len);
    try std.testing.expectEqual(@as(u16, 64), impl.alpha.height);
    try std.testing.expectEqual(@as(u16, 16), impl.color.height);
    const overflow = AtlasKey{ .font = .{ .variant = .regular, .face_index = 0, .glyph_id = 999 } };
    try std.testing.expectError(error.CacheFull, cacheRaster(impl, overflow, 1, 1, 0, 0, &.{255}, .alpha8));
    const alpha_bytes = impl.alpha.pixels.?.len;
    const color_bytes = impl.color.pixels.?.len;
    const before = impl.generation;
    try resetAtlas(owner);
    try std.testing.expectEqual(before + 1, impl.generation);
    try std.testing.expectEqual(alpha_bytes, impl.alpha.pixels.?.len);
    try std.testing.expectEqual(color_bytes, impl.color.pixels.?.len);
    for (impl.alpha.pixels.?) |value| try std.testing.expectEqual(@as(u8, 0), value);
    for (impl.color.pixels.?) |value| try std.testing.expectEqual(@as(u8, 0), value);
    const raster = try cacheRaster(impl, overflow, 1, 1, 0, 0, &.{255}, .alpha8);
    try std.testing.expectEqual(@as(u16, 0), raster.atlas_x);
    try std.testing.expectEqual(@as(u16, 0), raster.atlas_y);
}

test "atlas admission grows planes independently within ceilings and survives every allocation failure" {
    try atlasGrowthAllocationProof(std.testing.allocator);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, atlasGrowthAllocationProof, .{});
}

fn expectRetainedShapes(impl: *const ShapeCacheImpl, count: usize) !void {
    try std.testing.expectEqual(count, impl.entry_count);
    try std.testing.expectEqual(count * 2, impl.scalar_count);
    try std.testing.expectEqual(count, impl.glyph_count);
    for (0..count) |index| {
        const sequence = [_]u32{ @intCast(index + 0x100), @intCast(index + 0x200) };
        try std.testing.expectEqual(@as(?usize, index), findShapeIndex(impl, .regular, &sequence, index));
        const run = shapeEntryRun(impl, index);
        try std.testing.expectEqual(@as(u32, @intCast(index + 3)), run.glyphs[0].id);
    }
}

fn shapeGrowthAllocationProof(allocator: std.mem.Allocator) !void {
    const entries = try allocator.alloc(ShapeEntry, 2);
    const scalars = allocator.alloc(u32, 4) catch |failure| {
        allocator.free(entries);
        return failure;
    };
    const glyphs = allocator.alloc(text.Glyph, 2) catch |failure| {
        allocator.free(scalars);
        allocator.free(entries);
        return failure;
    };
    var impl: ShapeCacheImpl = .{
        .allocator = allocator,
        .fonts = undefined,
        .shape = undefined,
        .entries = entries,
        .scalars = scalars,
        .glyphs = glyphs,
        .max_sequence_scalars = 2,
        .bounds = .{ .entry_limit = 130, .scalar_limit = 260, .glyph_limit = 130 },
    };
    defer {
        impl.lookup.deinit(allocator);
        allocator.free(impl.glyphs);
        allocator.free(impl.scalars);
        allocator.free(impl.entries);
    }
    for (0..130) |index| {
        const grown = growShapeStorage(&impl, 2, 1) catch |failure| {
            try expectRetainedShapes(&impl, index);
            return failure;
        };
        try std.testing.expect(grown);
        impl.lookup.ensureInsert(allocator, impl.entries[0..impl.entry_count]) catch |failure| {
            try expectRetainedShapes(&impl, index);
            return failure;
        };
        impl.scalars[index * 2 ..][0..2].* = .{ @intCast(index + 0x100), @intCast(index + 0x200) };
        impl.glyphs[index] = std.mem.zeroes(text.Glyph);
        impl.glyphs[index].id = @intCast(index + 3);
        impl.entries[index] = .{ .hash = index, .variant = .regular, .scalar_offset = index * 2, .scalar_count = 2, .glyph_offset = index, .glyph_count = 1, .face_index = 0 };
        impl.entry_count += 1;
        impl.scalar_count += 2;
        impl.glyph_count += 1;
        impl.lookup.add(shapeIndexHash(index, .regular), index);
    }
    try expectRetainedShapes(&impl, 130);
    try std.testing.expect(!try growShapeStorage(&impl, 2, 1));
    try expectRetainedShapes(&impl, 130);
}

test "shape storage growth preserves keys and glyphs atomically through all allocation failures" {
    try shapeGrowthAllocationProof(std.testing.allocator);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, shapeGrowthAllocationProof, .{});
}

test "growth configuration rejects descending limits and zero lazy colour extent" {
    const a = std.testing.allocator;
    const fonts: FontFaces = .{ .regular = undefined };
    const box: generated.BoxDrawingConfig = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } };
    try std.testing.expectError(error.InvalidAtlasConfig, initAtlas(a, fonts, box, .{
        .width = 8,
        .height = 8,
        .entry_capacity = 2,
        .color_height = 0,
    }));
    try std.testing.expectError(error.InvalidAtlasConfig, initAtlas(a, fonts, box, .{
        .width = 8,
        .height = 8,
        .entry_capacity = 2,
        .growth = .{ .entry_limit = 1, .alpha_height_limit = 16, .color_height_limit = 16 },
    }));
    try std.testing.expectError(error.InvalidAtlasConfig, initAtlas(a, fonts, box, .{
        .width = 8,
        .height = 8,
        .entry_capacity = 2,
        .growth = .{ .entry_limit = 4, .alpha_height_limit = 7, .color_height_limit = 16 },
    }));
    try std.testing.expectError(error.InvalidShapeCacheConfig, initShapeCache(a, fonts, .{
        .entry_capacity = 2,
        .scalar_capacity = 4,
        .glyph_capacity = 2,
        .max_sequence_scalars = 2,
        .growth = .{ .entry_limit = 4, .scalar_limit = 3, .glyph_limit = 4 },
    }));
}

test "atlas height ceiling rejects impossible ink without discarding admitted pixels" {
    const owner = try initAtlas(std.testing.allocator, .{ .regular = undefined }, .{
        .dpi_x = .{ .numerator = 96, .denominator = 1 },
        .dpi_y = .{ .numerator = 96, .denominator = 1 },
    }, .{ .width = 8, .height = 2, .entry_capacity = 2, .gap = 0, .growth = .{ .entry_limit = 8, .alpha_height_limit = 4, .color_height_limit = 4 } });
    defer deinitAtlas(owner);
    const impl = atlasImpl(owner);
    const pixels: [16]u8 = @splat(77);
    for (0..2) |index| {
        const key = AtlasKey{ .font = .{ .variant = .regular, .face_index = 0, .glyph_id = @intCast(index) } };
        // zig-audit: acknowledge discard
        // reason: The complete retained plane and failure bounds are asserted below.
        _ = try cacheRaster(impl, key, 8, 2, 0, 0, &pixels, .alpha8);
    }
    try std.testing.expectEqual(@as(u16, 4), impl.alpha.height);
    const key = AtlasKey{ .font = .{ .variant = .regular, .face_index = 0, .glyph_id = 99 } };
    try std.testing.expectError(error.AtlasFull, cacheRaster(impl, key, 8, 2, 0, 0, &pixels, .alpha8));
    const too_wide: [9]u8 = @splat(11);
    try std.testing.expectError(error.GlyphTooLarge, cacheRaster(impl, key, 9, 1, 0, 0, &too_wide, .alpha8));
    try std.testing.expectEqual(@as(usize, 2), impl.entry_count);
    try std.testing.expectEqual(@as(u16, 4), impl.alpha.height);
    for (impl.alpha.pixels.?) |value| try std.testing.expectEqual(@as(u8, 77), value);
    try std.testing.expect(impl.color.pixels == null);
    try std.testing.expect(findAtlasIndex(impl, key) == null);
}
