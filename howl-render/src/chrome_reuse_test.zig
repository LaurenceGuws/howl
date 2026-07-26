//! Proves editor-like native text and chrome reuse through the curated root.

const std = @import("std");
const render = @import("howl_render");
const fonts = @import("test_fonts");

test "editor-like frame shapes text and projects selection without terminal facts" {
    var font = try render.text.FontSet.init(std.testing.allocator, .{
        .primary = fonts.primary_font,
        .pixel_height = 16,
    });
    defer font.deinit();
    var scratch = try render.text.ShapeBuffer.init(16);
    defer scratch.deinit();
    const codepoints = [_]u32{ 'e', 'd', 'i', 't' };
    const clusters = [_]u32{ 0, 1, 2, 3 };
    var glyphs: [16]render.text.Glyph = undefined;
    const run = try font.shape(&scratch, .{ .codepoints = &codepoints, .clusters = &clusters }, &glyphs);
    try std.testing.expect(run.glyphs.len != 0);

    const frame = render.chrome.Input{
        .surface = .{ .width = 96, .height = 48 },
        .tab_bar_height = 12,
        .tabs = &.{.{ .id = @fromBackingInt(@intCast(1)), .label = "edit", .active = true }},
        .panes = &.{.{ .id = @fromBackingInt(@intCast(1)), .rect = .{ .x = 0, .y = 12, .width = 96, .height = 36 }, .label = "buffer", .focused = true, .scroll = null, .layer = .tiled }},
        .selections = &.{.{ .pane = @fromBackingInt(@intCast(1)), .rect = .{ .x = 8, .y = 20, .width = 24, .height = 12 }, .color = .{ .r = 40, .g = 70, .b = 110, .a = 255 } }},
        .style = .{ .foreground = .{ .r = 240, .g = 240, .b = 240, .a = 255 }, .background = .{ .r = 16, .g = 18, .b = 22, .a = 255 }, .border = .{ .r = 80, .g = 84, .b = 92, .a = 255 } },
        .tab_active_background = .{ .r = 36, .g = 42, .b = 54, .a = 255 },
        .tab_inactive_background = .{ .r = 24, .g = 28, .b = 34, .a = 255 },
        .scrollbar_width = 4,
        .scrollbar_min_thumb = 8,
    };
    var primitives: [8]render.chrome.Primitive = undefined;
    var text: [16]u8 = undefined;
    const output = try render.chrome.project(frame, &primitives, &text);
    try std.testing.expectEqualStrings("editbuffer", output.text);
    try std.testing.expect(output.primitives[3] == .fill);
    try std.testing.expectEqual(@as(render.chrome.PaneId, @fromBackingInt(@intCast(1))), frame.selections[0].pane);
    try std.testing.expect((try render.chrome.hitTest(frame, .{ .x = 50, .y = 30 })).? == .pane);
}
