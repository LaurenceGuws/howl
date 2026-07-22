//! Proves selected one-run terminal text preparation and raster ownership.

const std = @import("std");
const render = @import("howl_render");
const selected = @import("selected_capabilities");
const fonts = if (selected.native_text) @import("test_fonts") else struct {};
const terminal = render.terminal;
const terminal_text = render.terminal_text;

const metrics = terminal_text.CellMetrics{
    .width_px = 8,
    .height_px = 16,
    .baseline_px = 12,
};

test "terminal text public surface follows selected sources" {
    try std.testing.expectEqual(selected.native_text, @hasDecl(terminal_text, "FontStyle"));
    try std.testing.expectEqual(selected.native_text, @hasDecl(terminal_text, "FontKey"));
    try std.testing.expectEqual(selected.native_text, @hasDecl(terminal_text, "NativeGlyphKey"));
    try std.testing.expectEqual(selected.native_text, @hasDecl(terminal_text, "NativeGlyphs"));
    try std.testing.expectEqual(selected.native_text, @hasDecl(terminal_text, "FontMap"));
    try std.testing.expectEqual(selected.native_text, @hasDecl(terminal_text, "FontConfig"));
    try std.testing.expectEqual(
        selected.native_text,
        @hasDecl(terminal_text, "FontMapInitError"),
    );
    try std.testing.expectEqual(
        selected.generated_glyphs,
        @hasDecl(terminal_text, "GeneratedGlyphKey"),
    );
    try std.testing.expect(@hasDecl(terminal_text, "CellMetrics"));
    try std.testing.expect(@hasDecl(terminal_text, "RowInput"));
    try std.testing.expect(@hasDecl(terminal_text, "GlyphKey"));
    try std.testing.expect(@hasDecl(terminal_text, "PositionedGlyph"));
    try std.testing.expect(@hasDecl(terminal_text, "PreparedGlyphs"));
    try std.testing.expect(@hasDecl(terminal_text, "PreparedRun"));
    try std.testing.expect(@hasDecl(terminal_text, "Raster"));
    try std.testing.expect(@hasDecl(terminal_text, "PrepareError"));
    try std.testing.expect(@hasDecl(terminal_text, "RasterError"));
    try std.testing.expect(@hasDecl(terminal_text, "prepareNextRun"));
    try std.testing.expect(@hasDecl(terminal_text, "rasterizeGlyph"));
}

test "generated and no-glyph runs retain exact coverage without allocation" {
    if (comptime !selected.generated_glyphs) return error.SkipZigTest;
    var map = try initMap();
    defer deinitMap(&map);
    var cells = [_]terminal.Cell{
        cell(0),
        cell(0),
        cell(0x2500),
        cell('A'),
    };
    cells[1].invisible = true;
    var first = try prepare(&map, input(&cells, 1, 3), 1);
    defer first.deinit();
    try std.testing.expectEqual(@as(u16, 0), first.first_cell);
    try std.testing.expectEqual(@as(u16, 2), first.end_cell);
    try std.testing.expect(first.glyphs == .none);
    var second = try prepare(&map, input(&cells, 1, 3), first.end_cell);
    defer second.deinit();
    try std.testing.expectEqual(@as(u16, 2), second.first_cell);
    try std.testing.expectEqual(@as(u16, 3), second.end_cell);
    try std.testing.expect(second.glyphs == .generated);
    const glyph = second.glyphs.generated;
    try std.testing.expectEqual(@as(u16, 2), glyph.source_start);
    try std.testing.expectEqual(@as(u16, 3), glyph.source_end);
    try std.testing.expectEqual(terminal.LineGeometry.double_height_top, second.geometry);
    try std.testing.expectEqual(terminal.CellBaseline.normal, second.baseline);

    if (comptime !selected.native_text) {
        var third = try prepare(&map, input(&cells, 1, 3), second.end_cell);
        defer third.deinit();
        try std.testing.expectEqual(@as(u16, 3), third.first_cell);
        try std.testing.expectEqual(@as(u16, 4), third.end_cell);
        try std.testing.expect(third.glyphs == .none);
    }
}

test "run discovery rejects malformed spans and metrics before ownership" {
    var map = try initMap();
    defer deinitMap(&map);
    var cells = [_]terminal.Cell{cell(0x2500)};
    try std.testing.expectError(
        error.InvalidSpan,
        prepare(&map, input(&cells, 1, 0), 0),
    );
    var invalid = input(&cells, 0, 0);
    invalid.metrics.height_px = 0;
    try std.testing.expectError(
        error.InvalidMetrics,
        prepare(&map, invalid, 0),
    );
    if (comptime selected.generated_glyphs) {
        invalid.metrics.height_px = std.math.maxInt(u16);
        invalid.metrics.baseline_px = 12;
        try std.testing.expectError(
            error.InvalidMetrics,
            prepare(&map, invalid, 0),
        );
    }
}

test "generated extent validation does not reject native or blank mixed runs" {
    if (comptime !(selected.native_text and selected.generated_glyphs))
        return error.SkipZigTest;
    var map = try initMap();
    defer deinitMap(&map);
    var cells = [_]terminal.Cell{ cell('A'), cell(0), cell(0x2500) };
    var oversized = input(&cells, 0, 2);
    oversized.metrics = .{ .width_px = 257, .height_px = 257, .baseline_px = 12 };

    var native_run = try prepare(&map, oversized, 0);
    defer native_run.deinit();
    try std.testing.expect(native_run.glyphs == .native);
    var blank_run = try prepare(&map, oversized, 1);
    defer blank_run.deinit();
    try std.testing.expect(blank_run.glyphs == .none);
    try std.testing.expectError(error.InvalidMetrics, prepare(&map, oversized, 2));
}

test "generated raster owns exact alpha and allocation rollback" {
    if (comptime !selected.generated_glyphs) return error.SkipZigTest;
    var map = try initMap();
    defer deinitMap(&map);
    var cells = [_]terminal.Cell{cell(0x2500)};
    var run = try prepare(&map, input(&cells, 0, 0), 0);
    defer run.deinit();
    const key = run.glyphs.generated.key;
    try std.testing.expectEqual(@as(u16, 12), key.generated.baseline_px);
    try std.testing.expectError(
        error.OutOfMemory,
        rasterize(&map, std.testing.failing_allocator, key),
    );
    var raster = try rasterize(&map, std.testing.allocator, key);
    defer raster.deinit();
    try std.testing.expectEqual(@as(u16, 8), raster.width);
    try std.testing.expectEqual(@as(u16, 16), raster.height);
    try std.testing.expectEqual(@as(i16, 12), raster.top);
    try std.testing.expectEqual(@as(usize, 128), raster.pixels.len);

    var alternate_input = input(&cells, 0, 0);
    alternate_input.metrics.baseline_px = 10;
    var alternate_run = try prepare(&map, alternate_input, 0);
    defer alternate_run.deinit();
    const alternate_key = alternate_run.glyphs.generated.key;
    try std.testing.expect(!std.meta.eql(key, alternate_key));
    var alternate_raster = try rasterize(&map, std.testing.allocator, alternate_key);
    defer alternate_raster.deinit();
    try std.testing.expectEqual(@as(i16, 10), alternate_raster.top);

    var invalid_key = key;
    invalid_key.generated.baseline_px = invalid_key.generated.height_px;
    try std.testing.expectError(
        error.InvalidSize,
        rasterize(&map, std.testing.allocator, invalid_key),
    );
}

test "native map and one-run preparation preserve exact tuple and coverage" {
    if (comptime !selected.native_text) return error.SkipZigTest;
    const configs = [_]terminal_text.FontConfig{
        .{
            .key = .{ .slot = 0, .style = .normal },
            .native = .{ .primary = fonts.primary_font, .pixel_height = 16 },
        },
        .{
            .key = .{ .slot = 3, .style = .bold_italic },
            .native = .{ .primary = fonts.primary_font, .pixel_height = 16 },
        },
    };
    var map = try terminal_text.FontMap.init(std.testing.allocator, &configs);
    defer map.deinit();
    var cells = [_]terminal.Cell{cell(0)} ** 12;
    cells[8] = cell('f');
    cells[9] = cell('i');
    cells[10] = cell('A');
    cells[10].combining_len = 1;
    cells[10].combining[0] = 0x0301;
    for (cells[8..11]) |*value| {
        value.font = 3;
        value.bold = true;
        value.italic = true;
        value.baseline = .raised;
    }
    var run = try terminal_text.prepareNextRun(
        std.testing.allocator,
        &map,
        input(&cells, 9, 10),
        9,
    );
    defer run.deinit();
    try std.testing.expectEqual(@as(u16, 8), run.first_cell);
    try std.testing.expectEqual(@as(u16, 11), run.end_cell);
    try std.testing.expectEqual(terminal.CellBaseline.raised, run.baseline);
    try std.testing.expectEqual(terminal.LineGeometry.double_height_top, run.geometry);
    try std.testing.expect(run.glyphs == .native);
    try std.testing.expect(run.glyphs.native.values.len > 0);
    var joined_cells = false;
    var combined_cell = false;
    for (run.glyphs.native.values) |glyph| {
        try std.testing.expect(glyph.key == .native);
        try std.testing.expectEqual(@as(u4, 3), glyph.key.native.font.slot);
        try std.testing.expectEqual(terminal_text.FontStyle.bold_italic, glyph.key.native.font.style);
        try std.testing.expect(glyph.source_start < glyph.source_end);
        try std.testing.expect(glyph.source_start >= 8);
        try std.testing.expect(glyph.source_end <= run.end_cell);
        try std.testing.expectEqual(
            glyph.source_end - glyph.source_start,
            glyph.key.native.cell_span,
        );
        joined_cells = joined_cells or glyph.key.native.cell_span == 2;
        combined_cell = combined_cell or
            (glyph.source_start == 10 and glyph.source_end == 11);
    }
    try std.testing.expect(joined_cells);
    try std.testing.expect(combined_cell);
    const key = run.glyphs.native.values[0].key;
    var raster = try terminal_text.rasterizeGlyph(std.testing.allocator, &map, key);
    defer raster.deinit();
    try std.testing.expect(raster.pixels.len <= render.text.max_raster_bytes);

    var default_map = try initMap();
    defer default_map.deinit();
    try std.testing.expectError(
        error.InvalidRaster,
        terminal_text.rasterizeGlyph(std.testing.allocator, &default_map, key),
    );
}

test "native missing tuple glyph and allocation failure are transactional" {
    if (comptime !selected.native_text) return error.SkipZigTest;
    var map = try initMap();
    defer deinitMap(&map);
    var styled = [_]terminal.Cell{cell('A')};
    styled[0].bold = true;
    try std.testing.expectError(
        error.MissingFontConfiguration,
        terminal_text.prepareNextRun(
            std.testing.allocator,
            &map,
            input(&styled, 0, 0),
            0,
        ),
    );
    var missing = [_]terminal.Cell{cell(0x10ffff)};
    try std.testing.expectError(
        error.MissingGlyph,
        terminal_text.prepareNextRun(
            std.testing.allocator,
            &map,
            input(&missing, 0, 0),
            0,
        ),
    );
    var ordinary = [_]terminal.Cell{cell('A')};
    try std.testing.expectError(
        error.OutOfMemory,
        terminal_text.prepareNextRun(
            std.testing.failing_allocator,
            &map,
            input(&ordinary, 0, 0),
            0,
        ),
    );
    var reusable = try terminal_text.prepareNextRun(
        std.testing.allocator,
        &map,
        input(&ordinary, 0, 0),
        0,
    );
    reusable.deinit();
}

test "font map validates complete tuple set before native ownership" {
    if (comptime !selected.native_text) return error.SkipZigTest;
    const normal = terminal_text.FontConfig{
        .key = .{ .slot = 0, .style = .normal },
        .native = .{ .primary = fonts.primary_font, .pixel_height = 16 },
    };
    try std.testing.expectError(
        error.MissingDefaultConfiguration,
        terminal_text.FontMap.init(std.testing.failing_allocator, &.{}),
    );
    try std.testing.expectError(
        error.DuplicateConfiguration,
        terminal_text.FontMap.init(std.testing.failing_allocator, &.{ normal, normal }),
    );
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        constructMap,
        .{},
    );
}

test "native combining clusters and all three allocations preserve reusable owners" {
    if (comptime !selected.native_text) return error.SkipZigTest;
    var map = try initMap();
    defer deinitMap(&map);
    var cells = [_]terminal.Cell{ cell('A'), cell('B') };
    cells[0].combining_len = 1;
    cells[0].combining[0] = 0x0301;
    var run = try terminal_text.prepareNextRun(
        std.testing.allocator,
        &map,
        input(&cells, 0, 1),
        0,
    );
    defer run.deinit();
    try std.testing.expect(run.glyphs.native.values.len >= 2);
    for (run.glyphs.native.values) |glyph| {
        try std.testing.expect(glyph.source_start < glyph.source_end);
        try std.testing.expect(glyph.source_end <= 2);
    }
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        prepareNative,
        .{&map},
    );
}

const Map = if (selected.native_text) terminal_text.FontMap else void;

fn initMap() !Map {
    if (comptime selected.native_text) {
        const configs = [_]terminal_text.FontConfig{.{
            .key = .{ .slot = 0, .style = .normal },
            .native = .{ .primary = fonts.primary_font, .pixel_height = 16 },
        }};
        return terminal_text.FontMap.init(std.testing.allocator, &configs);
    }
    return {};
}

fn deinitMap(map: *Map) void {
    if (comptime selected.native_text) map.deinit();
}

fn prepare(
    map: *Map,
    row: terminal_text.RowInput,
    at: u16,
) terminal_text.PrepareError!terminal_text.PreparedRun {
    if (comptime selected.native_text)
        return terminal_text.prepareNextRun(std.testing.allocator, map, row, at);
    return terminal_text.prepareNextRun(row, at);
}

fn rasterize(
    map: *Map,
    allocator: std.mem.Allocator,
    key: terminal_text.GlyphKey,
) terminal_text.RasterError!terminal_text.Raster {
    if (comptime selected.native_text)
        return terminal_text.rasterizeGlyph(allocator, map, key);
    return terminal_text.rasterizeGlyph(allocator, key);
}

fn constructMap(allocator: std.mem.Allocator) !void {
    const configs = [_]terminal_text.FontConfig{.{
        .key = .{ .slot = 0, .style = .normal },
        .native = .{ .primary = fonts.primary_font, .pixel_height = 16 },
    }};
    var map = try terminal_text.FontMap.init(allocator, &configs);
    map.deinit();
}

fn prepareNative(allocator: std.mem.Allocator, map: *terminal_text.FontMap) !void {
    var cells = [_]terminal.Cell{ cell('f'), cell('i') };
    var run = try terminal_text.prepareNextRun(
        allocator,
        map,
        input(&cells, 0, 1),
        0,
    );
    run.deinit();
}

fn input(cells: []const terminal.Cell, start: u16, end: u16) terminal_text.RowInput {
    return .{
        .cells = cells,
        .affected_start = start,
        .affected_end = end,
        .geometry = .double_height_top,
        .metrics = metrics,
    };
}

fn cell(codepoint: u21) terminal.Cell {
    return .{
        .codepoint = codepoint,
        .combining_len = 0,
        .combining = .{0} ** terminal.max_combining,
        .foreground = .{ .r = 0, .g = 0, .b = 0 },
        .background = .{ .r = 0, .g = 0, .b = 0 },
        .underline_color = .{ .r = 0, .g = 0, .b = 0 },
        .font = 0,
        .baseline = .normal,
        .bold = false,
        .dim = false,
        .italic = false,
        .blink = false,
        .blink_fast = false,
        .invisible = false,
        .underline = false,
        .strikethrough = false,
        .underline_style = .none,
        .selected = false,
        .link_id = 0,
    };
}
