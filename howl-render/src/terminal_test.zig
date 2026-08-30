//! Proves native terminal-view text projection without Flutter or terminal truth duplication.

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
        .semantic_width = false,
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

const TestContext = struct {
    view: *client.view.Snapshot,
    font: *render.text.FontSet,
    shape: *render.text.ShapeBuffer,
    clusters: [16]u32 = undefined,
    shaped: [32]render.text.Glyph = undefined,
    glyphs: [32]render.terminal.Glyph = undefined,
    pixels: [16 * 1024]u8 = undefined,
    raster: [4096]u8 = undefined,

    fn init(source: *const client.rich.Snapshot) !TestContext {
        const view = try client.view.project(std.testing.allocator, source);
        errdefer client.view.deinit(view);
        const font = try render.text.FontSet.init(std.testing.allocator, .{
            .primary = fonts.primary_font,
            .size = .{ .pixels = 16 },
        });
        errdefer font.deinit();
        const shape = try render.text.ShapeBuffer.init(std.testing.allocator, 32);
        errdefer shape.deinit();
        return .{ .view = view, .font = font, .shape = shape };
    }

    fn deinit(self: *TestContext) void {
        self.shape.deinit();
        self.font.deinit();
        client.view.deinit(self.view);
        self.* = undefined;
    }

    fn project(self: *TestContext, glyph_capacity: usize) !render.terminal.Frame {
        return render.terminal.project(self.view, self.font, self.shape, .{
            .clusters = &self.clusters,
            .shaped = &self.shaped,
            .glyphs = self.glyphs[0..glyph_capacity],
            .pixels = &self.pixels,
            .raster = &self.raster,
        });
    }
};

test "terminal view shapes source clusters and rasterizes through howl-text" {
    var first = [_]u32{ 'e', 0x0301 };
    var second = [_]u32{'A'};
    var cells = [_]client.rich.Cell{
        cell(&first, 1, 0),
        cell(&second, 1, 0),
    };
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    const source = sourceSnapshot(&rows, 2);
    var context = try TestContext.init(&source);
    defer context.deinit();
    const frame = try context.project(32);

    try std.testing.expectEqual(@as(u64, 17), frame.revision);
    try std.testing.expectEqual(@as(u64, 11), frame.terminal_revision);
    try std.testing.expectEqual(@as(u16, 1), frame.rows);
    try std.testing.expectEqual(@as(u16, 2), frame.columns);
    try std.testing.expect(frame.metrics.advance_width > 0);
    try std.testing.expect(frame.metrics.line_height > 0);
    try std.testing.expect(frame.glyphs.len >= 2);
    try std.testing.expect(frame.pixels.len != 0);
    try std.testing.expectEqual(@as(u32, 0), frame.glyphs[0].cluster);
    try std.testing.expect(frame.glyphs[frame.glyphs.len - 1].cluster >= 2);
    try std.testing.expectEqual(@as(u16, 1), frame.glyphs[frame.glyphs.len - 1].column);
    try std.testing.expectEqual(@as(u16, 1), frame.glyphs[0].style_bits);
    try std.testing.expectEqual(@as(u32, 0xabcdef), frame.glyphs[0].foreground.value);
}

test "terminal view ignores empty continuation cells" {
    var wide = [_]u32{'W'};
    var cells = [_]client.rich.Cell{
        cell(&wide, 2, 0),
        cell(&.{}, 2, 1),
    };
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    const source = sourceSnapshot(&rows, 2);
    var context = try TestContext.init(&source);
    defer context.deinit();
    const frame = try context.project(32);
    try std.testing.expect(frame.glyphs.len != 0);
    for (frame.glyphs) |glyph| {
        try std.testing.expectEqual(@as(u16, 0), glyph.column);
        try std.testing.expectEqual(@as(u32, 0), glyph.cell_index);
    }
}

test "terminal view rejects insufficient glyph output without touching terminal truth" {
    var text_scalars = [_]u32{'A'};
    var cells = [_]client.rich.Cell{cell(&text_scalars, 1, 0)};
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    const source = sourceSnapshot(&rows, 1);
    var context = try TestContext.init(&source);
    defer context.deinit();
    try std.testing.expectError(error.GlyphLimit, context.project(0));
    try std.testing.expectEqual(@as(u64, 17), source.begin.revision);
    try std.testing.expectEqual(@as(u32, 'A'), text_scalars[0]);
}
