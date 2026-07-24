//! Prepares one terminal visual run into positioned native or generated glyph facts.

const std = @import("std");
const terminal = @import("terminal_projection");
const features = @import("terminal_text_features");
const native = if (features.native_text) @import("native_text") else struct {};
const generated = if (features.generated_glyphs) @import("generated_glyphs") else struct {};

/// Selects the exact native font style retained by terminal cells.
pub const FontStyle = enum(u2) { normal, bold, italic, bold_italic };

/// Identifies one of 64 exact terminal font-slot and style configurations.
pub const FontKey = packed struct(u6) {
    /// Selects normal, bold, italic, or bold-italic native configuration.
    style: FontStyle,
    /// Selects terminal font slot 0 through 15.
    slot: u4,

    fn index(self: FontKey) usize {
        return @as(usize, self.slot) * 4 + @backingInt(self.style);
    }
};

/// Supplies validated normal cell metrics without pane or backend geometry.
pub const CellMetrics = struct {
    /// Reports the nonzero ordinary cell width.
    width_px: u16,
    /// Reports the nonzero ordinary cell height.
    height_px: u16,
    /// Locates the ordinary baseline within the cell height.
    baseline_px: u16,
};

/// Copies native decoration placement for later backend draw preparation.
pub const DecorationMetrics = struct {
    /// Locates the underline from the cell's top edge.
    underline_y: u16,
    /// Reports the nonzero underline thickness.
    underline_height: u16,
    /// Locates the strike line from the cell's top edge.
    strike_y: u16,
    /// Reports the nonzero strike-line thickness.
    strike_height: u16,
};

/// Borrows one complete retained visual row and selects an inclusive dirty span.
pub const RowInput = struct {
    /// Borrows the complete immutable row for the call.
    cells: []const terminal.Cell,
    /// Identifies the first affected cell.
    affected_start: u16,
    /// Identifies the last affected cell.
    affected_end: u16,
    /// Preserves unresolved DEC row presentation for later render preparation.
    geometry: terminal.LineGeometry,
    /// Supplies normal text metrics; line geometry and baseline do not alter them.
    metrics: CellMetrics,
};

/// Identifies one native raster within the lifetime of its exact font map.
pub const NativeGlyphKey = struct {
    /// Selects the exact map-owned font slot and style.
    font: FontKey,
    /// Selects the exact primary or fallback face within that map entry.
    face_index: u8,
    /// Selects the native face glyph.
    glyph_id: u32,
    /// Bounds raster fitting to the glyph's nonzero source-cell coverage.
    cell_span: u16,
};

/// Identifies one generated raster and its reproducible normal placement.
pub const GeneratedGlyphKey = struct {
    /// Selects an implemented generated terminal glyph.
    codepoint: u21,
    /// Sets the bounded normal cell width.
    width_px: u16,
    /// Sets the bounded normal cell height.
    height_px: u16,
    /// Places the full-cell mask relative to the ordinary baseline.
    baseline_px: u16,
};

/// Identifies a selected native or generated raster without cache residency.
pub const GlyphKey = if (features.native_text and features.generated_glyphs)
    union(enum) { native: NativeGlyphKey, generated: GeneratedGlyphKey }
else if (features.native_text)
    union(enum) { native: NativeGlyphKey }
else
    union(enum) { generated: GeneratedGlyphKey };

/// Places one selected glyph relative to its run's ordinary baseline.
pub const PositionedGlyph = struct {
    /// Identifies exact raster input under the selected capability graph.
    key: GlyphKey,
    /// Identifies the first covered source cell.
    source_start: u16,
    /// Identifies the exclusive covered source cell end.
    source_end: u16,
    /// Places the glyph horizontally in signed 26.6 units.
    x_26_6: i32,
    /// Places the glyph vertically in signed 26.6 units.
    y_26_6: i32,
    /// Retains shaped horizontal pen movement.
    x_advance_26_6: i32,
    /// Retains shaped vertical pen movement.
    y_advance_26_6: i32,
};

/// Stores the exact ownership form of one homogeneous prepared run.
pub const PreparedGlyphs = if (features.native_text and features.generated_glyphs)
    union(enum) { native: []const PositionedGlyph, generated: PositionedGlyph, none }
else if (features.native_text)
    union(enum) { native: []const PositionedGlyph, none }
else
    union(enum) { generated: PositionedGlyph, none };

/// Borrows at most one native scratch prefix and preserves unresolved visual facts.
/// Native glyphs remain valid only until their caller storage is written again.
pub const PreparedRun = struct {
    /// Identifies the first source cell in the complete run.
    first_cell: u16,
    /// Identifies the exclusive source cell end and next iteration position.
    end_cell: u16,
    /// Preserves baseline presentation for later render draw preparation.
    baseline: terminal.CellBaseline,
    /// Preserves DEC row presentation for later render draw preparation.
    geometry: terminal.LineGeometry,
    /// Preserves ordinary or Kitty multicell sizing for draw preparation.
    sizing: terminal.TextSizing,
    /// Borrows native scratch output, stores one generated glyph, or has no glyph.
    glyphs: PreparedGlyphs,
};

/// Borrows all caller-owned storage used by one synchronous native preparation.
/// Every slice must outlive the returned run and may be reused after that run
/// has been consumed.
pub const NativeScratch = if (features.native_text) struct {
    /// Owns native shaping capacity outside this borrowed scratch view.
    shaper: *native.ShapeBuffer,
    /// Stages flattened base and combining Unicode scalars.
    codepoints: []u32,
    /// Stages one run-local source cell for every flattened scalar.
    clusters: []u32,
    /// Receives the complete bounded native shaping result.
    shaped: []native.Glyph,
    /// Receives final terminal-positioned glyph facts.
    positioned: []PositionedGlyph,
} else void;

/// Owns one tightly packed alpha mask produced only after a raster miss.
pub const Raster = struct {
    /// Retains the allocator that owns `pixels`.
    allocator: std.mem.Allocator,
    /// Reports tightly packed mask width.
    width: u16,
    /// Reports tightly packed mask height.
    height: u16,
    /// Places the mask left edge relative to the shaped pen.
    left: i16,
    /// Places the mask top edge relative to the ordinary baseline.
    top: i16,
    /// Owns exactly `width * height` alpha bytes.
    pixels: []u8,

    /// Releases the mask exactly once.
    pub fn deinit(self: *Raster) void {
        self.allocator.free(self.pixels);
        self.* = undefined;
    }
};

/// Names one exact terminal font tuple and its borrowed construction config.
pub const FontConfig = if (features.native_text) struct {
    /// Identifies the exact slot and style.
    key: FontKey,
    /// Borrows native paths for construction only.
    native: native.Config,
} else void;

/// Reports bounded map validation or exact native construction failure.
pub const FontMapInitError = if (features.native_text)
    native.InitError || error{
        TooManyConfigurations,
        DuplicateConfiguration,
        MissingDefaultConfiguration,
    }
else
    error{};

/// Owns up to 64 exact native slot/style configurations without implicit fallback.
pub const FontMap = if (features.native_text) struct {
    /// Owns each configured native tuple at its exact bounded key index.
    sets: [64]?native.FontSet,

    /// Validates every tuple before transactionally constructing native owners.
    pub fn init(
        allocator: std.mem.Allocator,
        configs: []const FontConfig,
    ) FontMapInitError!@This() {
        if (configs.len > 64) return error.TooManyConfigurations;
        var seen: u64 = 0;
        for (configs) |config| {
            const bit = @as(u64, 1) << @intCast(config.key.index());
            if (seen & bit != 0) return error.DuplicateConfiguration;
            seen |= bit;
        }
        const default_key = FontKey{ .slot = 0, .style = .normal };
        if (seen & (@as(u64, 1) << @intCast(default_key.index())) == 0)
            return error.MissingDefaultConfiguration;

        var result = @This(){ .sets = @splat(null) };
        errdefer result.deinit();
        for (configs) |config| {
            result.sets[config.key.index()] = try native.FontSet.init(allocator, config.native);
        }
        return result;
    }

    /// Releases every configured native owner in reverse key order.
    pub fn deinit(self: *@This()) void {
        var index: usize = self.sets.len;
        while (index > 0) {
            index -= 1;
            if (self.sets[index]) |*set| set.deinit();
        }
        self.* = undefined;
    }

    /// Returns ordinary cell metrics for one exact configured font key.
    pub fn cellMetrics(self: *@This(), key: FontKey) ?CellMetrics {
        const set = self.get(key) orelse return null;
        return .{
            .width_px = set.metrics.cell_width,
            .height_px = set.metrics.cell_height,
            .baseline_px = set.metrics.baseline,
        };
    }

    /// Returns native decoration placement for one exact configured font key.
    pub fn decorationMetrics(self: *@This(), key: FontKey) ?DecorationMetrics {
        const set = self.get(key) orelse return null;
        return .{
            .underline_y = set.metrics.underline_y,
            .underline_height = set.metrics.underline_height,
            .strike_y = set.metrics.strike_y,
            .strike_height = set.metrics.strike_height,
        };
    }

    fn get(self: *@This(), key: FontKey) ?*native.FontSet {
        return if (self.sets[key.index()]) |*set| set else null;
    }
} else opaque {};

/// Reports exact span, metric, caller capacity, placement, configuration, or shaping failure.
pub const PrepareError = error{
    InvalidSpan,
    InvalidMetrics,
} || if (features.native_text)
    native.ShapeError || error{
        InvalidPlacement,
        MissingFontConfiguration,
        InsufficientCodepoints,
        InsufficientClusters,
        InsufficientPositionedGlyphs,
    }
else
    error{};

/// Reports exact native/generated raster and allocation failures.
pub const RasterError = error{OutOfMemory} ||
    (if (features.native_text) native.RasterError else error{}) ||
    (if (features.generated_glyphs) generated.Error else error{});

const RunKind = union(enum) {
    none: terminal.CellBaseline,
    native: struct {
        font: FontKey,
        baseline: terminal.CellBaseline,
        sizing: terminal.TextSizing,
    },
    generated: terminal.TextSizing,
};

const Bounds = struct { first: u16, end: u16, kind: RunKind };

/// Discovers one run and prepares it into caller-owned native scratch.
pub fn prepareNextRunNative(
    fonts: *FontMap,
    input: RowInput,
    cell: u16,
    scratch: NativeScratch,
) PrepareError!PreparedRun {
    comptime std.debug.assert(features.native_text);
    const bounds = try runBounds(input, cell);
    return switch (bounds.kind) {
        .none => noGlyphRun(input, bounds),
        .generated => if (features.generated_glyphs)
            try generatedRun(input, bounds)
        else
            noGlyphRun(input, bounds),
        .native => |facts| nativeRun(fonts, input, bounds, facts.font, scratch),
    };
}

/// Discovers and prepares one generated/no-glyph run without native vocabulary.
pub fn prepareNextRunGenerated(input: RowInput, cell: u16) PrepareError!PreparedRun {
    comptime std.debug.assert(!features.native_text and features.generated_glyphs);
    const bounds = try runBounds(input, cell);
    return switch (bounds.kind) {
        .none => noGlyphRun(input, bounds),
        .generated => try generatedRun(input, bounds),
        .native => noGlyphRun(input, bounds),
    };
}

/// Rasterizes one exact native/generated key with render-owned font selection.
pub fn rasterizeGlyphNative(
    allocator: std.mem.Allocator,
    fonts: *FontMap,
    key: GlyphKey,
) RasterError!Raster {
    comptime std.debug.assert(features.native_text);
    if (comptime features.generated_glyphs) {
        return switch (key) {
            .native => |facts| nativeRaster(allocator, fonts, facts),
            .generated => |facts| generatedRaster(allocator, facts),
        };
    }
    return switch (key) {
        .native => |facts| nativeRaster(allocator, fonts, facts),
    };
}

/// Rasterizes one exact generated key without native vocabulary.
pub fn rasterizeGlyphGenerated(
    allocator: std.mem.Allocator,
    key: GlyphKey,
) RasterError!Raster {
    comptime std.debug.assert(!features.native_text and features.generated_glyphs);
    return switch (key) {
        .generated => |facts| generatedRaster(allocator, facts),
    };
}

fn runBounds(input: RowInput, cell: u16) PrepareError!Bounds {
    try validateInput(input, cell);
    const kind = kindAt(input.cells[cell]);
    if (kind == .generated) return .{ .first = cell, .end = cell + 1, .kind = kind };

    var first = cell;
    while (first > 0 and std.meta.eql(kindAt(input.cells[first - 1]), kind)) first -= 1;
    var end: usize = @as(usize, cell) + 1;
    while (end < input.cells.len and std.meta.eql(kindAt(input.cells[end]), kind)) end += 1;
    return .{ .first = first, .end = @intCast(end), .kind = kind };
}

fn validateInput(input: RowInput, cell: u16) PrepareError!void {
    if (input.cells.len == 0 or input.cells.len > std.math.maxInt(u16) or
        input.affected_start > input.affected_end or
        input.affected_end >= input.cells.len or cell < input.affected_start or
        cell > input.affected_end)
        return error.InvalidSpan;
    if (input.metrics.width_px == 0 or input.metrics.height_px == 0 or
        input.metrics.baseline_px >= input.metrics.height_px)
        return error.InvalidMetrics;
}

fn kindAt(cell: terminal.Cell) RunKind {
    if (cell.sizing.x != 0 or cell.sizing.y != 0) return .{ .none = cell.baseline };
    if (cell.invisible or cell.codepoint == 0) return .{ .none = cell.baseline };
    if (features.generated_glyphs and cell.combining_len == 0 and
        generated.classify(cell.codepoint) != null)
        return .{ .generated = cell.sizing };
    if (features.native_text) return .{ .native = .{
        .font = .{
            .slot = cell.font,
            .style = if (cell.bold and cell.italic)
                .bold_italic
            else if (cell.bold)
                .bold
            else if (cell.italic)
                .italic
            else
                .normal,
        },
        .baseline = cell.baseline,
        .sizing = cell.sizing,
    } };
    return .{ .none = cell.baseline };
}

fn noGlyphRun(input: RowInput, bounds: Bounds) PreparedRun {
    return .{
        .first_cell = bounds.first,
        .end_cell = bounds.end,
        .baseline = baselineOf(bounds.kind),
        .geometry = input.geometry,
        .sizing = .{},
        .glyphs = .none,
    };
}

fn generatedRun(input: RowInput, bounds: Bounds) PrepareError!PreparedRun {
    if (input.metrics.width_px > generated.max_extent_px or
        input.metrics.height_px > generated.max_extent_px)
        return error.InvalidMetrics;
    const cell = input.cells[bounds.first];
    return .{
        .first_cell = bounds.first,
        .end_cell = bounds.end,
        .baseline = cell.baseline,
        .geometry = input.geometry,
        .sizing = cell.sizing,
        .glyphs = .{ .generated = .{
            .key = .{ .generated = .{
                .codepoint = cell.codepoint,
                .width_px = input.metrics.width_px,
                .height_px = input.metrics.height_px,
                .baseline_px = input.metrics.baseline_px,
            } },
            .source_start = bounds.first,
            .source_end = bounds.end,
            .x_26_6 = 0,
            .y_26_6 = 0,
            .x_advance_26_6 = @as(i32, input.metrics.width_px) * 64,
            .y_advance_26_6 = 0,
        } },
    };
}

fn nativeRun(
    fonts: *FontMap,
    input: RowInput,
    bounds: Bounds,
    font_key: FontKey,
    scratch: NativeScratch,
) PrepareError!PreparedRun {
    const set = fonts.get(font_key) orelse return error.MissingFontConfiguration;
    var scalar_count: usize = 0;
    for (input.cells[bounds.first..bounds.end]) |cell| {
        std.debug.assert(cell.codepoint != 0 and !cell.invisible);
        scalar_count += 1 + cell.combining_len;
    }
    if (scalar_count > native.max_codepoints) return error.TextTooLong;
    if (scalar_count > scratch.codepoints.len) return error.InsufficientCodepoints;
    if (scalar_count > scratch.clusters.len) return error.InsufficientClusters;
    const codepoints = scratch.codepoints[0..scalar_count];
    const clusters = scratch.clusters[0..scalar_count];
    var used: usize = 0;
    var col = bounds.first;
    while (col < bounds.end) : (col += 1) {
        const cell = input.cells[col];
        codepoints[used] = cell.codepoint;
        clusters[used] = col - bounds.first;
        used += 1;
        for (cell.combining[0..cell.combining_len]) |combining| {
            codepoints[used] = combining;
            clusters[used] = col - bounds.first;
            used += 1;
        }
    }
    std.debug.assert(used == scalar_count);

    const shaped = try set.shape(scratch.shaper, .{
        .codepoints = codepoints,
        .clusters = clusters,
        .cell_span = bounds.end - bounds.first,
    }, scratch.shaped);
    if (shaped.glyphs.len > scratch.positioned.len)
        return error.InsufficientPositionedGlyphs;
    const positioned = scratch.positioned[0..shaped.glyphs.len];
    var pen_x: i64 = 0;
    var pen_y: i64 = 0;
    for (shaped.glyphs, positioned) |glyph, *output| {
        const local_start: u16 = @intCast(glyph.cluster);
        const local_end = clusterEnd(shaped.glyphs, glyph.cluster, bounds.end - bounds.first);
        const source_start = bounds.first + local_start;
        const source_end = bounds.first + local_end;
        const x = pen_x + glyph.x_offset;
        const y = pen_y + glyph.y_offset;
        output.* = .{
            .key = .{ .native = .{
                .font = font_key,
                .face_index = shaped.face_index,
                .glyph_id = glyph.id,
                .cell_span = source_end - source_start,
            } },
            .source_start = source_start,
            .source_end = source_end,
            .x_26_6 = std.math.cast(i32, x) orelse return error.InvalidPlacement,
            .y_26_6 = std.math.cast(i32, y) orelse return error.InvalidPlacement,
            .x_advance_26_6 = glyph.x_advance,
            .y_advance_26_6 = glyph.y_advance,
        };
        pen_x = std.math.add(i64, pen_x, glyph.x_advance) catch return error.InvalidPlacement;
        pen_y = std.math.add(i64, pen_y, glyph.y_advance) catch return error.InvalidPlacement;
    }
    return .{
        .first_cell = bounds.first,
        .end_cell = bounds.end,
        .baseline = baselineOf(bounds.kind),
        .geometry = input.geometry,
        .sizing = switch (bounds.kind) {
            .native => |facts| facts.sizing,
            else => .{},
        },
        .glyphs = .{ .native = positioned },
    };
}

fn clusterEnd(glyphs: []const native.Glyph, cluster: u32, run_len: u16) u16 {
    std.debug.assert(run_len > 0);
    std.debug.assert(cluster < run_len);
    for (glyphs) |glyph| std.debug.assert(glyph.cluster < run_len);
    if (glyphs.len == 0) return run_len;
    const ascending = glyphs[0].cluster <= glyphs[glyphs.len - 1].cluster;
    if (ascending) {
        for (glyphs) |glyph| if (glyph.cluster > cluster) return @intCast(glyph.cluster);
        return run_len;
    }
    var previous: ?u32 = null;
    for (glyphs) |glyph| {
        if (glyph.cluster == cluster) return @intCast(previous orelse run_len);
        previous = glyph.cluster;
    }
    std.debug.assert(false);
    return run_len;
}

fn nativeRaster(allocator: std.mem.Allocator, fonts: *FontMap, key: NativeGlyphKey) RasterError!Raster {
    const set = fonts.get(key.font) orelse return error.InvalidRaster;
    var raster = try set.rasterize(allocator, key.face_index, key.glyph_id, key.cell_span);
    const result = Raster{
        .allocator = raster.allocator,
        .width = raster.width,
        .height = raster.height,
        .left = raster.left,
        .top = raster.top,
        .pixels = raster.pixels,
    };
    raster = undefined;
    return result;
}

fn generatedRaster(allocator: std.mem.Allocator, key: GeneratedGlyphKey) RasterError!Raster {
    if (key.width_px == 0 or key.height_px == 0 or
        key.width_px > generated.max_extent_px or key.height_px > generated.max_extent_px or
        key.baseline_px >= key.height_px)
        return error.InvalidSize;
    const count = @as(usize, key.width_px) * key.height_px;
    const pixels = allocator.alloc(u8, count) catch return error.OutOfMemory;
    errdefer allocator.free(pixels);
    try generated.rasterize(pixels, key.width_px, key.height_px, key.codepoint);
    return .{
        .allocator = allocator,
        .width = key.width_px,
        .height = key.height_px,
        .left = 0,
        .top = @intCast(key.baseline_px),
        .pixels = pixels,
    };
}

fn baselineOf(kind: RunKind) terminal.CellBaseline {
    return switch (kind) {
        .none => |baseline| baseline,
        .native => |facts| facts.baseline,
        .generated => .normal,
    };
}
