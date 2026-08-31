//! Proves atlas-backed native terminal text projection without terminal truth duplication.

const std = @import("std");
const render = @import("howl_render");
const client = @import("howl_client");
const fonts = @import("test_fonts");

fn presentation() client.rich.Presentation {
    return .{
        .cursor_age_ns = null,
        .presence_bits = 0,
        .flags = 0,
        .reverse_screen = false,
        .palette = @splat(.{ .r = 0, .g = 0, .b = 0, .a = 0xff }),
        .foreground = .{ .r = 0xee, .g = 0xee, .b = 0xee, .a = 0xff },
        .background = .{ .r = 1, .g = 2, .b = 3, .a = 0xff },
        .cursor = null,
        .cursor_text = null,
        .selection_background = null,
        .selection_foreground = null,
    };
}

fn cell(scalars: []u32, width: u8, x: u8) client.rich.Cell {
    return .{
        .scalars = scalars,
        .width = width,
        .height = 1,
        .x = x,
        .y = 0,
        .subscale_n = 1,
        .subscale_d = 1,
        .vertical_align = 0,
        .horizontal_align = 0,
        .semantic_width = width > 1,
        .font = 0,
        .baseline = 0,
        .underline_style = 0,
        .protection = 0,
        .style_bits = 1,
        .foreground = .{ .kind = .rgb, .value = 0xabcdef },
        .background = .{ .kind = .default, .value = 0 },
        .underline_color = .{ .kind = .default, .value = 0 },
        .link_id = 0,
    };
}

fn sourceSnapshot(rows: []client.rich.Row, columns: u16) client.rich.Snapshot {
    return .{
        .allocator = std.testing.allocator,
        .begin = .{
            .revision = 17,
            .terminal_revision = 11,
            .format = .text_v1,
            .history_offset = 0,
            .history_count = 0,
            .history_row_base = 0,
            .rows = @intCast(rows.len),
            .columns = columns,
            .cursor_row = 0,
            .cursor_column = 0,
            .cursor_shape = 0,
            .cursor_visible = false,
            .cursor_blink = false,
            .alternate_screen = false,
            .stream_closed = false,
            .child_exited = false,
            .leader_present = false,
            .you_are_leader = false,
        },
        .presentation = presentation(),
        .rows = rows,
        .hyperlinks = &.{},
    };
}

fn singleCellSource(
    scalar: u32,
    rows: *[1]client.rich.Row,
    cells: *[1]client.rich.Cell,
    storage: *[1]u32,
) client.rich.Snapshot {
    storage[0] = scalar;
    cells[0] = cell(storage, 1, 0);
    rows[0] = .{ .wrapped = false, .line_geometry = 0, .cells = cells };
    return sourceSnapshot(rows, 1);
}

fn defaultShapeCacheConfig() render.terminal.ShapeCacheConfig {
    return .{
        .entry_capacity = 16,
        .scalar_capacity = 64,
        .glyph_capacity = 64,
        .max_sequence_scalars = 16,
    };
}

const TestContext = struct {
    view: *client.view.Snapshot,
    font: *render.text.FontSet,
    shape_cache: *render.terminal.ShapeCache,
    atlas: *render.terminal.Atlas,
    clusters: [16]u32 = undefined,
    shaped: [32]render.text.Glyph = undefined,
    glyphs: [32]render.terminal.Glyph = undefined,
    raster: [4096]u8 = undefined,

    fn init(
        source: *const client.rich.Snapshot,
        config: render.terminal.AtlasConfig,
    ) !TestContext {
        return initWith(
            source,
            config,
            defaultShapeCacheConfig(),
            .{ .primary = fonts.primary_font, .size = .{ .pixels = 16 } },
        );
    }

    fn initWith(
        source: *const client.rich.Snapshot,
        atlas_config: render.terminal.AtlasConfig,
        shape_config: render.terminal.ShapeCacheConfig,
        font_config: render.text.Config,
    ) !TestContext {
        const view = try client.view.project(std.testing.allocator, source);
        errdefer client.view.deinit(view);
        const font = try render.text.FontSet.init(std.testing.allocator, font_config);
        errdefer font.deinit();
        const shape_cache = try render.terminal.initShapeCache(
            std.testing.allocator,
            font,
            shape_config,
        );
        errdefer render.terminal.deinitShapeCache(shape_cache);
        const atlas = try render.terminal.initAtlas(std.testing.allocator, font, atlas_config);
        errdefer render.terminal.deinitAtlas(atlas);
        return .{
            .view = view,
            .font = font,
            .shape_cache = shape_cache,
            .atlas = atlas,
        };
    }

    fn deinit(self: *TestContext) void {
        render.terminal.deinitAtlas(self.atlas);
        render.terminal.deinitShapeCache(self.shape_cache);
        self.font.deinit();
        client.view.deinit(self.view);
        self.* = undefined;
    }

    fn project(self: *TestContext, glyph_capacity: usize) !render.terminal.Frame {
        return render.terminal.project(self.view, self.atlas, self.shape_cache, .{
            .clusters = &self.clusters,
            .shaped = &self.shaped,
            .glyphs = self.glyphs[0..glyph_capacity],
            .raster = &self.raster,
        });
    }
};

test "terminal atlas preserves source clusters style and natural rasters" {
    var first_scalars = [_]u32{ 'e', 0x0301 };
    var second_scalars = [_]u32{'A'};
    var cells = [_]client.rich.Cell{
        cell(&first_scalars, 1, 0),
        cell(&second_scalars, 1, 0),
    };
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    const source = sourceSnapshot(&rows, 2);
    var context = try TestContext.init(&source, .{ .width = 64, .height = 64, .entry_capacity = 8 });
    defer context.deinit();
    const frame = try context.project(32);

    try std.testing.expectEqual(@as(u64, 17), frame.revision);
    try std.testing.expectEqual(@as(u64, 11), frame.terminal_revision);
    try std.testing.expectEqual(@as(u16, 1), frame.rows);
    try std.testing.expectEqual(@as(u16, 2), frame.columns);
    try std.testing.expect(frame.metrics.advance_width > 0);
    try std.testing.expect(frame.glyphs.len >= 2);
    try std.testing.expectEqual(@as(u32, 0), frame.glyphs[0].cluster);
    try std.testing.expect(frame.glyphs[frame.glyphs.len - 1].cluster >= 2);
    try std.testing.expectEqual(@as(u16, 1), frame.glyphs[frame.glyphs.len - 1].column);
    try std.testing.expectEqual(@as(u16, 1), frame.glyphs[0].style_bits);
    try std.testing.expectEqual(@as(u32, 0xabcdef), frame.glyphs[0].foreground.value);
    try std.testing.expect(render.terminal.atlasEntryCount(context.atlas) != 0);
    try std.testing.expect(std.hash.Wyhash.hash(0, frame.atlas.pixels) != 0);
}

test "terminal atlas ignores empty continuation cells" {
    var wide = [_]u32{'W'};
    var cells = [_]client.rich.Cell{
        cell(&wide, 2, 0),
        cell(&.{}, 2, 1),
    };
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    const source = sourceSnapshot(&rows, 2);
    var context = try TestContext.init(&source, .{ .width = 64, .height = 64, .entry_capacity = 8 });
    defer context.deinit();
    const frame = try context.project(32);
    try std.testing.expect(frame.glyphs.len != 0);
    for (frame.glyphs) |glyph| {
        try std.testing.expectEqual(@as(u16, 0), glyph.column);
        try std.testing.expectEqual(@as(u32, 0), glyph.cell_index);
    }
}

test "terminal atlas rejects insufficient placement output without touching terminal truth" {
    var text_scalars = [_]u32{'A'};
    var cells = [_]client.rich.Cell{cell(&text_scalars, 1, 0)};
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    const source = sourceSnapshot(&rows, 1);
    var context = try TestContext.init(&source, .{ .width = 64, .height = 64, .entry_capacity = 8 });
    defer context.deinit();
    try std.testing.expectError(error.GlyphLimit, context.project(0));
    try std.testing.expectEqual(@as(u64, 17), source.begin.revision);
    try std.testing.expectEqual(@as(u32, 'A'), text_scalars[0]);
}

test "terminal atlas reuses stable storage until explicit reset" {
    var scalars = [_]u32{'A'};
    var cells = [_]client.rich.Cell{ cell(&scalars, 1, 0), cell(&scalars, 1, 0) };
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    const source = sourceSnapshot(&rows, 2);
    var context = try TestContext.init(&source, .{ .width = 64, .height = 64, .entry_capacity = 8 });
    defer context.deinit();

    const first = try context.project(32);
    try std.testing.expectEqual(@as(usize, 1), render.terminal.atlasEntryCount(context.atlas));
    const first_x = first.glyphs[0].atlas_x;
    const first_y = first.glyphs[0].atlas_y;
    const generation = first.atlas.generation;
    const hash = std.hash.Wyhash.hash(0, first.atlas.pixels);

    const second = try context.project(32);
    try std.testing.expectEqual(generation, second.atlas.generation);
    try std.testing.expectEqual(@as(usize, 1), render.terminal.atlasEntryCount(context.atlas));
    try std.testing.expectEqual(hash, std.hash.Wyhash.hash(0, second.atlas.pixels));
    try std.testing.expectEqual(first_x, second.glyphs[0].atlas_x);
    try std.testing.expectEqual(first_y, second.glyphs[0].atlas_y);

    try render.terminal.resetAtlas(context.atlas);
    const reset = render.terminal.atlasView(context.atlas);
    try std.testing.expectEqual(generation + 1, reset.generation);
    try std.testing.expectEqual(@as(usize, 0), render.terminal.atlasEntryCount(context.atlas));
    try std.testing.expect(std.mem.allEqual(u8, reset.pixels, 0));
    const third = try context.project(32);
    try std.testing.expectEqual(reset.generation, third.atlas.generation);
}

test "terminal atlas cache full never evicts a live generation" {
    var rows_a: [1]client.rich.Row = undefined;
    var cells_a: [1]client.rich.Cell = undefined;
    var scalar_a: [1]u32 = undefined;
    const source_a = singleCellSource('A', &rows_a, &cells_a, &scalar_a);
    var context = try TestContext.init(&source_a, .{ .width = 64, .height = 64, .entry_capacity = 1 });
    defer context.deinit();
    const first = try context.project(32);
    const generation = first.atlas.generation;
    const hash = std.hash.Wyhash.hash(0, first.atlas.pixels);

    var rows_b: [1]client.rich.Row = undefined;
    var cells_b: [1]client.rich.Cell = undefined;
    var scalar_b: [1]u32 = undefined;
    const source_b = singleCellSource('B', &rows_b, &cells_b, &scalar_b);
    const view_b = try client.view.project(std.testing.allocator, &source_b);
    defer client.view.deinit(view_b);
    try std.testing.expectError(
        error.CacheFull,
        render.terminal.project(view_b, context.atlas, context.shape_cache, .{
            .clusters = &context.clusters,
            .shaped = &context.shaped,
            .glyphs = &context.glyphs,
            .raster = &context.raster,
        }),
    );
    try std.testing.expectEqual(generation, render.terminal.atlasView(context.atlas).generation);
    try std.testing.expectEqual(@as(usize, 1), render.terminal.atlasEntryCount(context.atlas));
    try std.testing.expectEqual(hash, std.hash.Wyhash.hash(0, render.terminal.atlasView(context.atlas).pixels));

    try render.terminal.resetAtlas(context.atlas);
    const after_reset = try render.terminal.project(view_b, context.atlas, context.shape_cache, .{
        .clusters = &context.clusters,
        .shaped = &context.shaped,
        .glyphs = &context.glyphs,
        .raster = &context.raster,
    });
    try std.testing.expectEqual(generation + 1, after_reset.atlas.generation);
}

test "terminal atlas reports too-small geometry without hidden reset" {
    var rows: [1]client.rich.Row = undefined;
    var cells: [1]client.rich.Cell = undefined;
    var scalar: [1]u32 = undefined;
    const source = singleCellSource('A', &rows, &cells, &scalar);
    var context = try TestContext.init(&source, .{ .width = 1, .height = 1, .entry_capacity = 4 });
    defer context.deinit();
    const generation = render.terminal.atlasView(context.atlas).generation;
    try std.testing.expectError(error.GlyphTooLarge, context.project(32));
    try std.testing.expectEqual(generation, render.terminal.atlasView(context.atlas).generation);
    try std.testing.expectEqual(@as(usize, 0), render.terminal.atlasEntryCount(context.atlas));
    try std.testing.expect(std.mem.allEqual(u8, render.terminal.atlasView(context.atlas).pixels, 0));
}

test "terminal atlas full preserves the already packed generation" {
    const font = try render.text.FontSet.init(std.testing.allocator, .{
        .primary = fonts.primary_font,
        .size = .{ .pixels = 16 },
    });
    defer font.deinit();
    const shape = try render.text.ShapeBuffer.init(std.testing.allocator, 8);
    defer shape.deinit();
    var clusters = [_]u32{0};
    var shaped: [8]render.text.Glyph = undefined;
    var raster_scratch: [4096]u8 = undefined;

    var a_cp = [_]u32{'A'};
    const a_run = try font.shape(shape, .{ .codepoints = &a_cp, .clusters = &clusters }, &shaped);
    var a_allocator = std.heap.FixedBufferAllocator.init(&raster_scratch);
    var a_raster = try font.rasterize(a_allocator.allocator(), a_run.face_index, a_run.glyphs[0].id);
    defer a_raster.deinit();
    const a_width = a_raster.width;
    const a_height = a_raster.height;

    var b_cp = [_]u32{'B'};
    const b_run = try font.shape(shape, .{ .codepoints = &b_cp, .clusters = &clusters }, &shaped);
    var b_allocator = std.heap.FixedBufferAllocator.init(&raster_scratch);
    var b_raster = try font.rasterize(b_allocator.allocator(), b_run.face_index, b_run.glyphs[0].id);
    defer b_raster.deinit();
    try std.testing.expect(a_width != 0 and a_height != 0 and b_raster.width != 0 and b_raster.height != 0);

    var rows_a: [1]client.rich.Row = undefined;
    var cells_a: [1]client.rich.Cell = undefined;
    var scalar_a: [1]u32 = undefined;
    const source_a = singleCellSource('A', &rows_a, &cells_a, &scalar_a);
    var context = try TestContext.init(&source_a, .{
        .width = @max(a_width, b_raster.width),
        .height = @max(a_height, b_raster.height),
        .entry_capacity = 2,
    });
    defer context.deinit();
    const first = try context.project(32);
    const generation = first.atlas.generation;
    const hash = std.hash.Wyhash.hash(0, first.atlas.pixels);

    var rows_b: [1]client.rich.Row = undefined;
    var cells_b: [1]client.rich.Cell = undefined;
    var scalar_b: [1]u32 = undefined;
    const source_b = singleCellSource('B', &rows_b, &cells_b, &scalar_b);
    const view_b = try client.view.project(std.testing.allocator, &source_b);
    defer client.view.deinit(view_b);
    try std.testing.expectError(
        error.AtlasFull,
        render.terminal.project(view_b, context.atlas, context.shape_cache, .{
            .clusters = &context.clusters,
            .shaped = &context.shaped,
            .glyphs = &context.glyphs,
            .raster = &context.raster,
        }),
    );
    try std.testing.expectEqual(generation, render.terminal.atlasView(context.atlas).generation);
    try std.testing.expectEqual(@as(usize, 1), render.terminal.atlasEntryCount(context.atlas));
    try std.testing.expectEqual(hash, std.hash.Wyhash.hash(0, render.terminal.atlasView(context.atlas).pixels));
}

test "terminal atlas init cleans every failed allocation stage" {
    const font = try render.text.FontSet.init(std.testing.allocator, .{
        .primary = fonts.primary_font,
        .size = .{ .pixels = 16 },
    });
    defer font.deinit();
    for (0..3) |fail_index| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = fail_index });
        try std.testing.expectError(
            error.OutOfMemory,
            render.terminal.initAtlas(failing.allocator(), font, .{
                .width = 64,
                .height = 64,
                .entry_capacity = 8,
            }),
        );
        try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
    }
}

test "terminal shape cache reuses one combining run and rebases clusters per cell" {
    var first = [_]u32{ 'e', 0x0301 };
    var second = [_]u32{ 'e', 0x0301 };
    var cells = [_]client.rich.Cell{
        cell(&first, 1, 0),
        cell(&second, 1, 0),
    };
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    const source = sourceSnapshot(&rows, 2);
    var context = try TestContext.init(&source, .{ .width = 64, .height = 64, .entry_capacity = 8 });
    defer context.deinit();

    const frame = try context.project(32);
    const usage = render.terminal.shapeCacheUsage(context.shape_cache);
    try std.testing.expectEqual(@as(usize, 1), usage.entries);
    try std.testing.expectEqual(@as(usize, 2), usage.scalars);
    try std.testing.expect(usage.glyphs != 0);

    var first_glyphs: [8]render.terminal.Glyph = undefined;
    var second_glyphs: [8]render.terminal.Glyph = undefined;
    var first_count: usize = 0;
    var second_count: usize = 0;
    for (frame.glyphs) |glyph| switch (glyph.column) {
        0 => {
            first_glyphs[first_count] = glyph;
            first_count += 1;
            try std.testing.expect(glyph.cluster < 2);
        },
        1 => {
            second_glyphs[second_count] = glyph;
            second_count += 1;
            try std.testing.expect(glyph.cluster >= 2 and glyph.cluster < 4);
        },
        else => return error.UnexpectedColumn,
    };
    try std.testing.expectEqual(first_count, second_count);
    try std.testing.expect(first_count != 0);
    for (first_glyphs[0..first_count], second_glyphs[0..second_count]) |left, right| {
        try std.testing.expectEqual(left.glyph_id, right.glyph_id);
        try std.testing.expectEqual(left.face_index, right.face_index);
        try std.testing.expectEqual(left.cluster + 2, right.cluster);
        try std.testing.expectEqual(left.x_offset_26_6, right.x_offset_26_6);
        try std.testing.expectEqual(left.y_offset_26_6, right.y_offset_26_6);
        try std.testing.expectEqual(left.x_advance_26_6, right.x_advance_26_6);
        try std.testing.expectEqual(left.y_advance_26_6, right.y_advance_26_6);
    }
}

test "terminal shape cache retains fallback face identity" {
    var first = [_]u32{0xe0b0};
    var second = [_]u32{0xe0b0};
    var cells = [_]client.rich.Cell{
        cell(&first, 1, 0),
        cell(&second, 1, 0),
    };
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    const source = sourceSnapshot(&rows, 2);
    const fallbacks = [_][]const u8{fonts.symbol_font};
    var context = try TestContext.initWith(
        &source,
        .{ .width = 64, .height = 64, .entry_capacity = 8 },
        defaultShapeCacheConfig(),
        .{
            .primary = fonts.primary_font,
            .fallbacks = &fallbacks,
            .size = .{ .pixels = 16 },
        },
    );
    defer context.deinit();

    const frame = try context.project(32);
    try std.testing.expectEqual(@as(usize, 1), render.terminal.shapeCacheUsage(context.shape_cache).entries);
    try std.testing.expect(frame.glyphs.len != 0);
    for (frame.glyphs) |glyph| try std.testing.expectEqual(@as(u8, 1), glyph.face_index);
}

test "terminal shape cache reset is independent from atlas generation" {
    var scalars = [_]u32{'A'};
    var cells = [_]client.rich.Cell{cell(&scalars, 1, 0)};
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    const source = sourceSnapshot(&rows, 1);
    var context = try TestContext.init(&source, .{ .width = 64, .height = 64, .entry_capacity = 8 });
    defer context.deinit();

    const first = try context.project(32);
    const generation = first.atlas.generation;
    const atlas_entries = render.terminal.atlasEntryCount(context.atlas);
    const atlas_hash = std.hash.Wyhash.hash(0, first.atlas.pixels);
    try std.testing.expectEqual(@as(usize, 1), render.terminal.shapeCacheUsage(context.shape_cache).entries);

    render.terminal.resetShapeCache(context.shape_cache);
    try std.testing.expectEqualDeep(
        render.terminal.ShapeCacheUsage{ .entries = 0, .scalars = 0, .glyphs = 0 },
        render.terminal.shapeCacheUsage(context.shape_cache),
    );
    try std.testing.expectEqual(generation, render.terminal.atlasView(context.atlas).generation);
    try std.testing.expectEqual(atlas_entries, render.terminal.atlasEntryCount(context.atlas));
    try std.testing.expectEqual(atlas_hash, std.hash.Wyhash.hash(0, render.terminal.atlasView(context.atlas).pixels));

    const second = try context.project(32);
    try std.testing.expectEqual(generation, second.atlas.generation);
    try std.testing.expectEqual(atlas_entries, render.terminal.atlasEntryCount(context.atlas));
    try std.testing.expectEqual(@as(usize, 1), render.terminal.shapeCacheUsage(context.shape_cache).entries);
}

test "terminal shape entry exhaustion preserves both caches" {
    var rows_a: [1]client.rich.Row = undefined;
    var cells_a: [1]client.rich.Cell = undefined;
    var scalar_a: [1]u32 = undefined;
    const source_a = singleCellSource('A', &rows_a, &cells_a, &scalar_a);
    var context = try TestContext.initWith(
        &source_a,
        .{ .width = 64, .height = 64, .entry_capacity = 8 },
        .{
            .entry_capacity = 1,
            .scalar_capacity = 4,
            .glyph_capacity = 4,
            .max_sequence_scalars = 2,
        },
        .{ .primary = fonts.primary_font, .size = .{ .pixels = 16 } },
    );
    defer context.deinit();
    const first = try context.project(32);
    const atlas_hash = std.hash.Wyhash.hash(0, first.atlas.pixels);
    const atlas_entries = render.terminal.atlasEntryCount(context.atlas);
    const usage = render.terminal.shapeCacheUsage(context.shape_cache);

    var rows_b: [1]client.rich.Row = undefined;
    var cells_b: [1]client.rich.Cell = undefined;
    var scalar_b: [1]u32 = undefined;
    const source_b = singleCellSource('B', &rows_b, &cells_b, &scalar_b);
    const view_b = try client.view.project(std.testing.allocator, &source_b);
    defer client.view.deinit(view_b);
    try std.testing.expectError(error.ShapeEntryFull, render.terminal.project(
        view_b,
        context.atlas,
        context.shape_cache,
        .{
            .clusters = &context.clusters,
            .shaped = &context.shaped,
            .glyphs = &context.glyphs,
            .raster = &context.raster,
        },
    ));
    try std.testing.expectEqualDeep(usage, render.terminal.shapeCacheUsage(context.shape_cache));
    try std.testing.expectEqual(atlas_entries, render.terminal.atlasEntryCount(context.atlas));
    try std.testing.expectEqual(atlas_hash, std.hash.Wyhash.hash(0, render.terminal.atlasView(context.atlas).pixels));

    render.terminal.resetShapeCache(context.shape_cache);
    const after_reset = try render.terminal.project(view_b, context.atlas, context.shape_cache, .{
        .clusters = &context.clusters,
        .shaped = &context.shaped,
        .glyphs = &context.glyphs,
        .raster = &context.raster,
    });
    try std.testing.expect(after_reset.glyphs.len != 0);
    try std.testing.expectEqual(@as(usize, 1), render.terminal.shapeCacheUsage(context.shape_cache).entries);
}

test "terminal shape scalar exhaustion is transactional" {
    var rows_a: [1]client.rich.Row = undefined;
    var cells_a: [1]client.rich.Cell = undefined;
    var scalar_a: [1]u32 = undefined;
    const source_a = singleCellSource('A', &rows_a, &cells_a, &scalar_a);
    var context = try TestContext.initWith(
        &source_a,
        .{ .width = 64, .height = 64, .entry_capacity = 8 },
        .{
            .entry_capacity = 4,
            .scalar_capacity = 2,
            .glyph_capacity = 8,
            .max_sequence_scalars = 2,
        },
        .{ .primary = fonts.primary_font, .size = .{ .pixels = 16 } },
    );
    defer context.deinit();
    const first = try context.project(32);
    const atlas_hash = std.hash.Wyhash.hash(0, first.atlas.pixels);
    const usage = render.terminal.shapeCacheUsage(context.shape_cache);

    var combined = [_]u32{ 'e', 0x0301 };
    var cells_b = [_]client.rich.Cell{cell(&combined, 1, 0)};
    var rows_b = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells_b }};
    const source_b = sourceSnapshot(&rows_b, 1);
    const view_b = try client.view.project(std.testing.allocator, &source_b);
    defer client.view.deinit(view_b);
    try std.testing.expectError(error.ShapeScalarFull, render.terminal.project(
        view_b,
        context.atlas,
        context.shape_cache,
        .{
            .clusters = &context.clusters,
            .shaped = &context.shaped,
            .glyphs = &context.glyphs,
            .raster = &context.raster,
        },
    ));
    try std.testing.expectEqualDeep(usage, render.terminal.shapeCacheUsage(context.shape_cache));
    try std.testing.expectEqual(atlas_hash, std.hash.Wyhash.hash(0, render.terminal.atlasView(context.atlas).pixels));
}

test "terminal shape glyph exhaustion is transactional" {
    var rows_a: [1]client.rich.Row = undefined;
    var cells_a: [1]client.rich.Cell = undefined;
    var scalar_a: [1]u32 = undefined;
    const source_a = singleCellSource('A', &rows_a, &cells_a, &scalar_a);
    var context = try TestContext.initWith(
        &source_a,
        .{ .width = 64, .height = 64, .entry_capacity = 8 },
        .{
            .entry_capacity = 4,
            .scalar_capacity = 4,
            .glyph_capacity = 1,
            .max_sequence_scalars = 2,
        },
        .{ .primary = fonts.primary_font, .size = .{ .pixels = 16 } },
    );
    defer context.deinit();
    const first = try context.project(32);
    const atlas_hash = std.hash.Wyhash.hash(0, first.atlas.pixels);
    const usage = render.terminal.shapeCacheUsage(context.shape_cache);

    var rows_b: [1]client.rich.Row = undefined;
    var cells_b: [1]client.rich.Cell = undefined;
    var scalar_b: [1]u32 = undefined;
    const source_b = singleCellSource('B', &rows_b, &cells_b, &scalar_b);
    const view_b = try client.view.project(std.testing.allocator, &source_b);
    defer client.view.deinit(view_b);
    try std.testing.expectError(error.ShapeGlyphFull, render.terminal.project(
        view_b,
        context.atlas,
        context.shape_cache,
        .{
            .clusters = &context.clusters,
            .shaped = &context.shaped,
            .glyphs = &context.glyphs,
            .raster = &context.raster,
        },
    ));
    try std.testing.expectEqualDeep(usage, render.terminal.shapeCacheUsage(context.shape_cache));
    try std.testing.expectEqual(atlas_hash, std.hash.Wyhash.hash(0, render.terminal.atlasView(context.atlas).pixels));
}

test "terminal projection rejects a shape cache from another FontSet" {
    var scalars = [_]u32{'A'};
    var cells = [_]client.rich.Cell{cell(&scalars, 1, 0)};
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    const source = sourceSnapshot(&rows, 1);
    var context = try TestContext.init(&source, .{ .width = 64, .height = 64, .entry_capacity = 8 });
    defer context.deinit();

    const other_font = try render.text.FontSet.init(std.testing.allocator, .{
        .primary = fonts.primary_font,
        .size = .{ .pixels = 16 },
    });
    defer other_font.deinit();
    const other_cache = try render.terminal.initShapeCache(
        std.testing.allocator,
        other_font,
        defaultShapeCacheConfig(),
    );
    defer render.terminal.deinitShapeCache(other_cache);
    const before = render.terminal.shapeCacheUsage(other_cache);
    try std.testing.expectError(error.FontSetMismatch, render.terminal.project(
        context.view,
        context.atlas,
        other_cache,
        .{
            .clusters = &context.clusters,
            .shaped = &context.shaped,
            .glyphs = &context.glyphs,
            .raster = &context.raster,
        },
    ));
    try std.testing.expectEqualDeep(before, render.terminal.shapeCacheUsage(other_cache));
}

fn constructShapeCache(allocator: std.mem.Allocator, font: *render.text.FontSet) !void {
    const cache = try render.terminal.initShapeCache(allocator, font, defaultShapeCacheConfig());
    render.terminal.deinitShapeCache(cache);
}

test "terminal shape cache construction cleans every allocation failure" {
    const font = try render.text.FontSet.init(std.testing.allocator, .{
        .primary = fonts.primary_font,
        .size = .{ .pixels = 16 },
    });
    defer font.deinit();
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        constructShapeCache,
        .{font},
    );
}

test "terminal shape cache hit needs no cold-shape glyph scratch" {
    var scalars = [_]u32{'A'};
    var cells = [_]client.rich.Cell{cell(&scalars, 1, 0)};
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    const source = sourceSnapshot(&rows, 1);
    var context = try TestContext.init(&source, .{ .width = 64, .height = 64, .entry_capacity = 8 });
    defer context.deinit();
    const populated = try context.project(32);
    try std.testing.expect(populated.glyphs.len != 0);

    const usage = render.terminal.shapeCacheUsage(context.shape_cache);
    const frame = try render.terminal.project(context.view, context.atlas, context.shape_cache, .{
        .clusters = &context.clusters,
        .shaped = context.shaped[0..0],
        .glyphs = &context.glyphs,
        .raster = &context.raster,
    });
    try std.testing.expect(frame.glyphs.len != 0);
    try std.testing.expectEqualDeep(usage, render.terminal.shapeCacheUsage(context.shape_cache));
}

test "terminal shape failure leaves caches pristine and reusable" {
    var missing = [_]u32{0x10ffff};
    var missing_cells = [_]client.rich.Cell{cell(&missing, 1, 0)};
    var missing_rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &missing_cells }};
    const missing_source = sourceSnapshot(&missing_rows, 1);
    var context = try TestContext.init(&missing_source, .{ .width = 64, .height = 64, .entry_capacity = 8 });
    defer context.deinit();
    try std.testing.expectError(error.MissingGlyph, context.project(32));
    try std.testing.expectEqualDeep(
        render.terminal.ShapeCacheUsage{ .entries = 0, .scalars = 0, .glyphs = 0 },
        render.terminal.shapeCacheUsage(context.shape_cache),
    );
    try std.testing.expectEqual(@as(usize, 0), render.terminal.atlasEntryCount(context.atlas));
    try std.testing.expect(std.mem.allEqual(u8, render.terminal.atlasView(context.atlas).pixels, 0));

    var rows_a: [1]client.rich.Row = undefined;
    var cells_a: [1]client.rich.Cell = undefined;
    var scalar_a: [1]u32 = undefined;
    const source_a = singleCellSource('A', &rows_a, &cells_a, &scalar_a);
    const view_a = try client.view.project(std.testing.allocator, &source_a);
    defer client.view.deinit(view_a);
    const frame = try render.terminal.project(view_a, context.atlas, context.shape_cache, .{
        .clusters = &context.clusters,
        .shaped = &context.shaped,
        .glyphs = &context.glyphs,
        .raster = &context.raster,
    });
    try std.testing.expect(frame.glyphs.len != 0);
    try std.testing.expectEqual(@as(usize, 1), render.terminal.shapeCacheUsage(context.shape_cache).entries);
    try std.testing.expectEqual(@as(usize, 1), render.terminal.atlasEntryCount(context.atlas));
}

test "terminal shape cache validates construction bounds before allocation" {
    const font = try render.text.FontSet.init(std.testing.allocator, .{
        .primary = fonts.primary_font,
        .size = .{ .pixels = 16 },
    });
    defer font.deinit();
    try std.testing.expectError(error.InvalidShapeCacheConfig, render.terminal.initShapeCache(
        std.testing.failing_allocator,
        font,
        .{ .entry_capacity = 0, .scalar_capacity = 1, .glyph_capacity = 1, .max_sequence_scalars = 1 },
    ));
    try std.testing.expectError(error.InvalidShapeCacheConfig, render.terminal.initShapeCache(
        std.testing.failing_allocator,
        font,
        .{ .entry_capacity = 1, .scalar_capacity = 1, .glyph_capacity = 1, .max_sequence_scalars = 2 },
    ));
}
