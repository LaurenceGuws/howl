//! Proves that child modules retain one type identity through the Howl root.
const std = @import("std");
const vt = @import("howl_vt");
const instance = @import("howl_instance");
const render = @import("howl_render");
const text = @import("howl_text");

test "VT and renderer compose through root exports" {
    try std.testing.expect(instance.Terminal == vt.Terminal);
    try std.testing.expect(render.text.FontSet == text.FontSet);
    try std.testing.expect(!@hasDecl(render.terminal, "View"));
    var terminal = try vt.Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    _ = try terminal.feed("Howl");
    try std.testing.expectEqual(@as(u21, 'H'), terminal.semanticView(0).cellAt(0, 0));
    _ = render.terminal.updateObservation;
    _ = instance.terminal;
}

test "root exposes the complete native consumer vocabulary" {
    _ = @import("howl_pty");
    _ = @import("howl_instance_protocol");
    _ = @import("howl_instance_service");
    _ = @import("client_transport");
    _ = @import("howl_client");
    _ = @import("howl_local");
    _ = @import("server_protocol");
    _ = @import("server");
    _ = @import("server_service");
    _ = @import("server_runtime");
    _ = @import("server_client");
    _ = @import("howl_cli");
    _ = @import("howl_render_limits");
    _ = @import("howl_text_test_fonts");
    _ = @import("howl_vk");
    _ = @import("howl_wayland");
}

test "readonly VT accessors retain ordinary function pointers" {
    const View = vt.Terminal.SemanticView;
    const Geometry = @typeInfo(@TypeOf(View.lineGeometry)).@"fn".return_type.?;
    const cell: *const fn (*const View, u16, u16) vt.Terminal.Cell = View.cellInfoAt;
    const scalars: *const fn (*const View, u16, u16, *[24]u21) []const u21 = View.cellScalarsAt;
    const geometry: *const fn (*const View, u16) Geometry = View.lineGeometry;
    var terminal = try vt.Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    _ = try terminal.feed("A\xcc\x81");
    const view = terminal.semanticView(0);
    var output: [24]u21 = undefined;
    try std.testing.expectEqual(@as(u32, 'A'), cell(&view, 0, 0).codepoint);
    try std.testing.expectEqualSlices(u21, &.{ 'A', 0x0301 }, scalars(&view, 0, 0, &output));
    try std.testing.expectEqual(.single_width, geometry(&view, 0));
}
