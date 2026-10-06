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
