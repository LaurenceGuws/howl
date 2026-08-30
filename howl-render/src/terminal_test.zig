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

const TestContext = struct {
    view: *client.view.Snapshot,
    font: *render.text.FontSet,
    shape: *render.text.ShapeBuffer,
    atlas: *render.terminal.Atlas,
    clusters: [16]u32 = undefined,
    shaped: [32]render.text.Glyph = undefined,
    glyphs: [32]render.terminal.Glyph = undefined,
    raster: [4096]u8 = undefined,

    fn init(
        source: *const client.rich.Snapshot,
        config: render.terminal.AtlasConfig,
    ) !TestContext {
        const view = try client.view.project(std.testing.allocator, source);
        errdefer client.view.deinit(view);
        const font = try render.text.FontSet.init(std.testing.allocator, .{
            .primary = fonts.primary_font,
            .size = .{ .pixels = 16 },
        });
        errdefer font.deinit();
        const shape = try render.text.ShapeBuffer.init(std.testing.allocator, 32);
        errdefer shape.deinit();
        const atlas = try render.terminal.initAtlas(std.testing.allocator, font, config);
        errdefer render.terminal.deinitAtlas(atlas);
        return .{ .view = view, .font = font, .shape = shape, .atlas = atlas };
    }

    fn deinit(self: *TestContext) void {
        render.terminal.deinitAtlas(self.atlas);
        self.shape.deinit();
        self.font.deinit();
        client.view.deinit(self.view);
        self.* = undefined;
    }

    fn project(self: *TestContext, glyph_capacity: usize) !render.terminal.Frame {
        return render.terminal.project(self.view, self.atlas, self.shape, .{
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
        render.terminal.project(view_b, context.atlas, context.shape, .{
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
    const after_reset = try render.terminal.project(view_b, context.atlas, context.shape, .{
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
        render.terminal.project(view_b, context.atlas, context.shape, .{
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
