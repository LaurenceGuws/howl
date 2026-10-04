//! Proves local-only package exports without importing a client or wire service.
const std = @import("std");
const instance = @import("howl_instance");
const vt = @import("howl_vt");
const render = @import("howl_render");
const terminal = render.terminal;
const fonts = @import("test_fonts");

test "local exports exclude transport and keep exact VT type identity" {
    try std.testing.expect(!@hasDecl(instance, "protocol"));
    try std.testing.expect(!@hasDecl(terminal, "View"));
    try std.testing.expect(!@hasDecl(terminal, "updateRich"));
    try std.testing.expect(instance.Terminal == vt.Terminal);
}

test "local VT observation produces materializable glyph resources" {
    const allocator = std.testing.allocator;
    const font = try render.text.FontSet.init(allocator, .{
        .primary = fonts.primary_font,
        .size = .{ .pixels = 16 },
    });
    defer font.deinit();
    const owner = try terminal.init(allocator, terminal.FontFaces.single(font), .{
        .cell_size = .{ .width = 10, .height = 20 },
        .box_drawing = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
        .shape_cache = .{ .entry_capacity = 32, .scalar_capacity = 128, .glyph_capacity = 128, .max_sequence_scalars = 16 },
        .atlas = .{ .width = 128, .height = 128, .entry_capacity = 32 },
        .shaped_capacity = 64,
        .raster_bytes = 4096,
        .command_capacity = 128,
    });
    defer terminal.deinit(owner);
    var value = try vt.Terminal.init(allocator, 2, 16);
    defer value.deinit();
    _ = try value.feed("local \x1b[31mVT");
    try terminal.updateObservation(owner, value.observation(), 0, &.{});
    var uploads: [8]terminal.FrameResourceUpload = undefined;
    var removals: [8]terminal.ResourceRef = undefined;
    var commands: [128]terminal.Command = undefined;
    var pixels: [128 * 128]u8 = undefined;
    const frame = try terminal.frame(owner, &.{}, .{
        .uploads = &uploads,
        .removals = &removals,
        .commands = &commands,
        .pixels = &pixels,
    });
    try std.testing.expect(frame.commands.len > 0);
    try std.testing.expectEqual(@as(usize, 1), frame.uploads.len);
    try std.testing.expectEqual(terminal.ResourceFormat.alpha8, frame.uploads[0].format);
    try std.testing.expect(frame.pixels.len > 0);
}
