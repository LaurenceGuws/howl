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

/// Borrows one complete retained visual row and selects an inclusive affected span.
pub const RowInput = struct {
    /// Borrows the complete immutable row for the call.
    cells: []const terminal.Cell,
    /// Borrows the accepted complete overflow-scalar cohort synchronously.
    scalars: terminal.ScalarBaseline,
    /// Locates this row's first cell in `scalars`.
    scalar_offset: usize,
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
    /// Stages scalar source cells, then cluster coverage after synchronous shaping.
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

/// Exact normalized factual DPI consumed by terminal native construction.
pub const Dpi = if (features.native_text) native.Dpi else void;
/// Canonical validated terminal point-size and factual DPI identity.
pub const PointSize = if (features.native_text) native.PointSize else void;
/// Selects pixel or canonical point/DPI native construction.
pub const Size = if (features.native_text) native.Size else void;

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

    /// Swaps complete map values without allocation; `replacement` owns the
    /// retired map and later uses ordinary `deinit`. The caller must first
    /// quiesce every synchronous shaping and raster borrow from both maps;
    /// neither map may be borrowed during this swap.
    pub fn replaceWith(self: *@This(), replacement: *@This()) void {
        std.mem.swap(@This(), self, replacement);
    }

    /// Returns ordinary cell metrics for one exact configured font key.
    pub fn cellMetrics(self: *@This(), key: FontKey) ?CellMetrics {
        const set = self.get(key) orelse return null;
        return .{
            .width_px = set.metrics.advance_width,
            .height_px = set.metrics.line_height,
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
    start_cell: u16,
    scratch: NativeScratch,
) PrepareError!PreparedRun {
    comptime std.debug.assert(features.native_text);
    const bounds = try runBounds(input, start_cell);
    return switch (bounds.kind) {
        .none => noGlyphRun(input, bounds),
        .generated => if (features.generated_glyphs)
            try generatedRun(input, bounds)
        else
            noGlyphRun(input, bounds),
        .native => |facts| nativeRun(fonts, input, start_cell, bounds, facts.font, scratch),
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
    start_cell: u16,
    bounds: Bounds,
    font_key: FontKey,
    scratch: NativeScratch,
) PrepareError!PreparedRun {
    const set = fonts.get(font_key) orelse return error.MissingFontConfiguration;
    var selected_bounds = bounds;
    var selected_face: ?u8 = null;
    var selected_end: u16 = undefined;
    while (true) {
        selected_face = null;
        selected_end = selected_bounds.first;
        while (selected_end < bounds.end) : (selected_end += 1) {
            var coverage: [terminal.maximum_scalars]u32 = undefined;
            const sequence = try cellScalars(input, selected_end, &coverage);
            const face = try set.faceFor(sequence);
            if (selected_end == selected_bounds.first) {
                if (face == null) {
                    if (selected_bounds.first < start_cell) {
                        selected_bounds.first = start_cell;
                        break;
                    }
                    selected_bounds.end = selected_bounds.first + 1;
                    return noGlyphRun(input, selected_bounds);
                }
                selected_face = face;
                continue;
            }
            if (face == null or face.? != selected_face.?) break;
        }
        if (selected_end > start_cell) break;
        selected_bounds.first = start_cell;
    }
    selected_bounds.end = selected_end;
    var scalar_count: usize = 0;
    for (input.cells[selected_bounds.first..selected_bounds.end]) |cell| {
        std.debug.assert(cell.codepoint != 0 and !cell.invisible);
        scalar_count += 1 + cell.combining_len;
    }
    if (scalar_count > native.max_codepoints) return error.TextTooLong;
    if (scalar_count > scratch.codepoints.len) return error.InsufficientCodepoints;
    if (scalar_count > scratch.clusters.len) return error.InsufficientClusters;
    const codepoints = scratch.codepoints[0..scalar_count];
    const clusters = scratch.clusters[0..scalar_count];
    var used: usize = 0;
    var col = selected_bounds.first;
    while (col < selected_bounds.end) : (col += 1) {
        var retained: [terminal.maximum_scalars]u32 = undefined;
        const sequence = try cellScalars(input, col, &retained);
        for (sequence) |scalar| {
            codepoints[used] = scalar;
            clusters[used] = col - selected_bounds.first;
            used += 1;
        }
    }
    std.debug.assert(used == scalar_count);

    const shaped = try set.shape(scratch.shaper, .{
        .codepoints = codepoints,
        .clusters = clusters,
    }, scratch.shaped);
    if (shaped.glyphs.len > scratch.positioned.len)
        return error.InsufficientPositionedGlyphs;
    const positioned = scratch.positioned[0..shaped.glyphs.len];
    // Synchronous shaping has released scalar staging; reuse it for unordered cluster coverage.
    const cluster_ends = clusterEnds(
        shaped.glyphs,
        selected_bounds.end - selected_bounds.first,
        scratch.clusters,
    );
    const run_len = selected_bounds.end - selected_bounds.first;
    @memcpy(scratch.codepoints[0..run_len], cluster_ends);
    const retained_ends = scratch.codepoints[0..run_len];
    const cluster_pens = scratch.clusters[0..run_len];
    try positionNativeGlyphs(
        shaped.glyphs,
        run_len,
        selected_bounds.first,
        input.metrics.width_px,
        font_key,
        shaped.face_index,
        retained_ends,
        cluster_pens,
        positioned,
    );
    return .{
        .first_cell = selected_bounds.first,
        .end_cell = selected_bounds.end,
        .baseline = baselineOf(selected_bounds.kind),
        .geometry = input.geometry,
        .sizing = switch (selected_bounds.kind) {
            .native => |facts| facts.sizing,
            else => .{},
        },
        .glyphs = .{ .native = positioned },
    };
}

fn cellScalars(
    input: RowInput,
    cell_index: usize,
    output: *[terminal.maximum_scalars]u32,
) PrepareError![]const u32 {
    if (cell_index >= input.cells.len) return error.InvalidPlacement;
    const cell = input.cells[cell_index];
    if (cell.codepoint == 0) return error.InvalidPlacement;
    const total = std.math.add(usize, 1, cell.combining_len) catch
        return error.InvalidPlacement;
    if (total > terminal.maximum_scalars) return error.InvalidPlacement;
    output[0] = cell.codepoint;
    const direct = @min(@as(usize, cell.combining_len), terminal.max_combining);
    for (cell.combining[0..direct], 0..) |scalar, index|
        output[1 + index] = scalar;
    const scalar_cell = std.math.add(usize, input.scalar_offset, cell_index) catch
        return error.InvalidPlacement;
    if (!input.scalars.validRange(scalar_cell, cell.combining_len))
        return error.InvalidPlacement;
    const tail = input.scalars.tail(
        scalar_cell,
        cell.combining_len,
    ) catch return error.InvalidPlacement;
    for (tail, 0..) |scalar, index| {
        if (scalar > std.math.maxInt(u21)) return error.InvalidPlacement;
        output[1 + direct + index] = scalar;
    }
    return output[0..total];
}

const cluster_seen: u32 = 1 << 31;
const cluster_end_mask: u32 = cluster_seen - 1;

fn checkedClusterPosition(
    pen_x: i64,
    pen_y: i64,
    glyph: native.Glyph,
    cluster_cell: u16,
    cell_width_px: u16,
    cluster_pen_x: i32,
) error{InvalidPlacement}!void {
    const local_x = std.math.sub(
        i64,
        std.math.add(i64, pen_x, glyph.x_offset) catch
            return error.InvalidPlacement,
        cluster_pen_x,
    ) catch return error.InvalidPlacement;
    const cell_origin = std.math.mul(
        i64,
        cluster_cell,
        std.math.mul(i64, cell_width_px, 64) catch
            return error.InvalidPlacement,
    ) catch return error.InvalidPlacement;
    const x = std.math.add(i64, cell_origin, local_x) catch
        return error.InvalidPlacement;
    const y = std.math.add(i64, pen_y, glyph.y_offset) catch
        return error.InvalidPlacement;
    if (std.math.cast(i32, x) == null or std.math.cast(i32, y) == null)
        return error.InvalidPlacement;
}

fn checkedSourceSpan(
    first_cell: u16,
    local_start: u16,
    local_end: u16,
) error{InvalidPlacement}!void {
    const source_start = std.math.add(u16, first_cell, local_start) catch
        return error.InvalidPlacement;
    const source_end = std.math.add(u16, first_cell, local_end) catch
        return error.InvalidPlacement;
    if (source_end <= source_start) return error.InvalidPlacement;
}

fn positionNativeGlyphs(
    glyphs: []const native.Glyph,
    run_len: u16,
    first_cell: u16,
    cell_width_px: u16,
    font_key: FontKey,
    face_index: u8,
    cluster_facts: []u32,
    cluster_pens: []u32,
    output: []PositionedGlyph,
) error{InvalidPlacement}!void {
    if (run_len == 0 or cluster_facts.len < run_len or cluster_pens.len < run_len or
        output.len != glyphs.len)
        return error.InvalidPlacement;
    for (cluster_facts[0..run_len]) |*facts| facts.* &= cluster_end_mask;

    // Discover each cluster's first shaped pen and validate the complete
    // translation before changing caller output.
    var pen_x: i64 = 0;
    var pen_y: i64 = 0;
    for (glyphs) |glyph| {
        if (glyph.cluster >= run_len) return error.InvalidPlacement;
        const local_start: u16 = @intCast(glyph.cluster);
        const facts = &cluster_facts[local_start];
        const local_end = facts.* & cluster_end_mask;
        if (local_end <= local_start or local_end > run_len)
            return error.InvalidPlacement;
        if (facts.* & cluster_seen == 0) {
            const cluster_pen = std.math.cast(i32, pen_x) orelse
                return error.InvalidPlacement;
            cluster_pens[local_start] = @bitCast(cluster_pen);
            facts.* |= cluster_seen;
        }
        try checkedClusterPosition(
            pen_x,
            pen_y,
            glyph,
            local_start,
            cell_width_px,
            @bitCast(cluster_pens[local_start]),
        );
        try checkedSourceSpan(first_cell, local_start, @intCast(local_end));
        pen_x = std.math.add(i64, pen_x, glyph.x_advance) catch
            return error.InvalidPlacement;
        pen_y = std.math.add(i64, pen_y, glyph.y_advance) catch
            return error.InvalidPlacement;
    }

    // Every operation below was checked against these immutable inputs.
    pen_x = 0;
    pen_y = 0;
    for (glyphs, output) |glyph, *positioned| {
        const local_start: u16 = @intCast(glyph.cluster);
        const local_end: u16 = @intCast(cluster_facts[local_start] & cluster_end_mask);
        const source_start = first_cell + local_start;
        const source_end = first_cell + local_end;
        const cluster_pen_x: i32 = @bitCast(cluster_pens[local_start]);
        const local_x = pen_x + glyph.x_offset - cluster_pen_x;
        const cell_origin = @as(i64, local_start) * cell_width_px * 64;
        positioned.* = .{
            .key = .{ .native = .{
                .font = font_key,
                .face_index = face_index,
                .glyph_id = glyph.id,
                .cell_span = source_end - source_start,
            } },
            .source_start = source_start,
            .source_end = source_end,
            .x_26_6 = @intCast(cell_origin + local_x),
            .y_26_6 = @intCast(pen_y + glyph.y_offset),
            .x_advance_26_6 = glyph.x_advance,
            .y_advance_26_6 = glyph.y_advance,
        };
        pen_x += glyph.x_advance;
        pen_y += glyph.y_advance;
    }
}

fn clusterEnds(glyphs: []const native.Glyph, run_len: u16, storage: []u32) []u32 {
    std.debug.assert(run_len > 0);
    std.debug.assert(storage.len >= run_len);
    const ends = storage[0..run_len];
    @memset(ends, std.math.maxInt(u32));
    for (glyphs) |glyph| {
        std.debug.assert(glyph.cluster < run_len);
        ends[glyph.cluster] = run_len;
    }
    var next: u32 = run_len;
    var index: usize = run_len;
    while (index > 0) {
        index -= 1;
        if (ends[index] != std.math.maxInt(u32)) {
            ends[index] = next;
            next = @intCast(index);
        }
    }
    for (glyphs) |glyph| std.debug.assert(ends[glyph.cluster] > glyph.cluster);
    return ends;
}

test "cluster ends are independent of shaped glyph order and repetition" {
    if (comptime !features.native_text) return error.SkipZigTest;
    const empty = native.Glyph{
        .id = 1,
        .cluster = 0,
        .x_advance = 0,
        .y_advance = 0,
        .x_offset = 0,
        .y_offset = 0,
    };
    var storage: [4]u32 = undefined;

    var ascending = [_]native.Glyph{ empty, empty, empty };
    ascending[2].cluster = 2;
    const ascending_ends = clusterEnds(&ascending, 4, &storage);
    try std.testing.expectEqual(@as(u32, 2), ascending_ends[0]);
    try std.testing.expectEqual(@as(u32, 4), ascending_ends[2]);

    var descending = [_]native.Glyph{ empty, empty, empty, empty };
    descending[0].cluster = 3;
    descending[1].cluster = 1;
    descending[2].cluster = 1;
    const descending_ends = clusterEnds(&descending, 4, &storage);
    try std.testing.expectEqual(@as(u32, 4), descending_ends[3]);
    try std.testing.expectEqual(@as(u32, 3), descending_ends[1]);
    try std.testing.expectEqual(@as(u32, 1), descending_ends[0]);

    var unordered = [_]native.Glyph{ empty, empty, empty, empty, empty };
    unordered[0].cluster = 2;
    unordered[2].cluster = 3;
    unordered[4].cluster = 1;
    const unordered_ends = clusterEnds(&unordered, 4, &storage);
    try std.testing.expectEqualSlices(u32, &.{ 1, 2, 3, 4 }, unordered_ends);
}

fn testGlyph(cluster: u32, advance: i32, offset: i32) native.Glyph {
    return .{
        .id = 1,
        .cluster = cluster,
        .x_advance = advance,
        .y_advance = 0,
        .x_offset = offset,
        .y_offset = 0,
    };
}

fn positionTestGlyphs(
    glyphs: []const native.Glyph,
    run_len: u16,
    cell_width_px: u16,
    cluster_facts: []u32,
    cluster_pens: []u32,
    output: []PositionedGlyph,
) !void {
    const ends = clusterEnds(glyphs, run_len, cluster_facts);
    try positionNativeGlyphs(
        glyphs,
        run_len,
        0,
        cell_width_px,
        .{ .style = .normal, .slot = 0 },
        0,
        ends,
        cluster_pens,
        output,
    );
}

test "terminal clusters use the cell lattice without rewriting native advances" {
    if (comptime !features.native_text) return error.SkipZigTest;

    var glyphs: [4]native.Glyph = undefined;
    for (&glyphs, 0..) |*glyph, cell_index|
        glyph.* = testGlyph(@intCast(cell_index), 544, 0);
    var facts: [4]u32 = undefined;
    var pens: [4]u32 = undefined;
    var positioned: [4]PositionedGlyph = undefined;
    try positionTestGlyphs(&glyphs, 4, 9, &facts, &pens, &positioned);
    for (positioned, 0..) |position, cell_index| {
        try std.testing.expectEqual(@as(i32, @intCast(cell_index * 576)), position.x_26_6);
        try std.testing.expectEqual(@as(i32, 544), position.x_advance_26_6);
    }

    for ([_]struct { width: u16, advance: i32 }{
        .{ .width = 8, .advance = 512 },
        .{ .width = 9, .advance = 576 },
    }) |matching_case| {
        const matching = [_]native.Glyph{
            testGlyph(0, matching_case.advance, 0),
            testGlyph(1, matching_case.advance, 0),
        };
        var matching_facts: [2]u32 = undefined;
        var matching_pens: [2]u32 = undefined;
        var matching_output: [2]PositionedGlyph = undefined;
        try positionTestGlyphs(
            &matching,
            2,
            matching_case.width,
            &matching_facts,
            &matching_pens,
            &matching_output,
        );
        try std.testing.expectEqual(matching_case.advance, matching_output[1].x_26_6);
        try std.testing.expectEqual(matching_case.advance, matching_output[1].x_advance_26_6);
    }
}

test "terminal clusters retain one origin across repetition and negative pens" {
    if (comptime !features.native_text) return error.SkipZigTest;

    const unordered = [_]native.Glyph{
        testGlyph(2, 100, 0),
        testGlyph(0, 100, 0),
        testGlyph(2, 0, 0),
    };
    var unordered_facts: [3]u32 = undefined;
    var unordered_pens: [3]u32 = undefined;
    var unordered_output: [3]PositionedGlyph = undefined;
    try positionTestGlyphs(
        &unordered,
        3,
        9,
        &unordered_facts,
        &unordered_pens,
        &unordered_output,
    );
    try std.testing.expectEqual(@as(i32, 1152), unordered_output[0].x_26_6);
    try std.testing.expectEqual(@as(i32, 0), unordered_output[1].x_26_6);
    try std.testing.expectEqual(@as(i32, 1352), unordered_output[2].x_26_6);

    const negative = [_]native.Glyph{
        testGlyph(0, -1, 0),
        testGlyph(1, 100, 0),
        testGlyph(1, 0, 0),
    };
    var negative_facts: [2]u32 = undefined;
    var negative_pens: [2]u32 = undefined;
    var negative_output: [3]PositionedGlyph = undefined;
    try positionTestGlyphs(
        &negative,
        2,
        9,
        &negative_facts,
        &negative_pens,
        &negative_output,
    );
    try std.testing.expectEqual(std.math.maxInt(u32), negative_pens[1]);
    try std.testing.expectEqual(@as(i32, 576), negative_output[1].x_26_6);
    try std.testing.expectEqual(@as(i32, 676), negative_output[2].x_26_6);
}

test "terminal clusters preserve combining placement and ligature coverage" {
    if (comptime !features.native_text) return error.SkipZigTest;

    var combining = [_]native.Glyph{
        testGlyph(0, 300, 10),
        testGlyph(0, 0, -20),
    };
    combining[1].y_offset = -64;
    var combining_facts: [1]u32 = undefined;
    var combining_pens: [1]u32 = undefined;
    var combining_output: [2]PositionedGlyph = undefined;
    try positionTestGlyphs(
        &combining,
        1,
        9,
        &combining_facts,
        &combining_pens,
        &combining_output,
    );
    try std.testing.expectEqual(@as(i32, 10), combining_output[0].x_26_6);
    try std.testing.expectEqual(@as(i32, 280), combining_output[1].x_26_6);
    try std.testing.expectEqual(@as(i32, -64), combining_output[1].y_26_6);

    const ligature = [_]native.Glyph{
        testGlyph(0, 700, 0),
        testGlyph(2, 544, 0),
    };
    var ligature_facts: [3]u32 = undefined;
    var ligature_pens: [3]u32 = undefined;
    var ligature_output: [2]PositionedGlyph = undefined;
    try positionTestGlyphs(
        &ligature,
        3,
        9,
        &ligature_facts,
        &ligature_pens,
        &ligature_output,
    );
    try std.testing.expectEqual(@as(i32, 0), ligature_output[0].x_26_6);
    try std.testing.expectEqual(@as(u16, 0), ligature_output[0].source_start);
    try std.testing.expectEqual(@as(u16, 2), ligature_output[0].source_end);
    try std.testing.expectEqual(@as(u16, 2), switch (ligature_output[0].key) {
        .native => |key| key.cell_span,
        else => return error.TestUnexpectedResult,
    });
}

test "terminal cluster arithmetic failures do not alter caller output" {
    if (comptime !features.native_text) return error.SkipZigTest;

    const glyphs = [_]native.Glyph{
        testGlyph(0, 544, 0),
        testGlyph(1, 0, std.math.maxInt(i32)),
    };
    var facts = [_]u32{ 1, 2 };
    var pens: [2]u32 = undefined;
    var output: [2]PositionedGlyph = undefined;
    @memset(std.mem.asBytes(&output), 0xa5);
    var before: [@sizeOf(@TypeOf(output))]u8 = undefined;
    @memcpy(&before, std.mem.asBytes(&output));
    try std.testing.expectError(
        error.InvalidPlacement,
        positionNativeGlyphs(
            &glyphs,
            2,
            0,
            9,
            .{ .style = .normal, .slot = 0 },
            0,
            &facts,
            &pens,
            &output,
        ),
    );
    try std.testing.expectEqualSlices(u8, &before, std.mem.asBytes(&output));
}

test "generated terminal placement remains cell exact" {
    if (comptime !features.generated_glyphs) return error.SkipZigTest;

    var cells = [_]terminal.Cell{std.mem.zeroes(terminal.Cell)};
    cells[0].codepoint = 0x250c;
    cells[0].baseline = .normal;
    cells[0].sizing = .{};
    const run = try generatedRun(.{
        .cells = &cells,
        .affected_start = 0,
        .affected_end = 0,
        .geometry = .single_width,
        .metrics = .{ .width_px = 9, .height_px = 17, .baseline_px = 13 },
    }, .{
        .first = 0,
        .end = 1,
        .kind = .{ .generated = .{} },
    });
    const positioned = switch (run.glyphs) {
        .generated => |glyph| glyph,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(@as(i32, 0), positioned.x_26_6);
    try std.testing.expectEqual(@as(i32, 576), positioned.x_advance_26_6);
    try std.testing.expectEqual(@as(u16, 0), positioned.source_start);
    try std.testing.expectEqual(@as(u16, 1), positioned.source_end);
}

fn nativeRaster(allocator: std.mem.Allocator, fonts: *FontMap, key: NativeGlyphKey) RasterError!Raster {
    const set = fonts.get(key.font) orelse return error.InvalidRaster;
    const maximum_width = std.math.mul(
        u16,
        set.metrics.advance_width,
        key.cell_span,
    ) catch return error.InvalidWidth;
    if (key.cell_span == 0 or maximum_width == 0) return error.InvalidWidth;
    var raster = try set.rasterize(allocator, key.face_index, key.glyph_id, maximum_width);
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
