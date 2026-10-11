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
    // zig-audit: acknowledge discard
    // reason: The proof checks canonical content and public function/type identity; feed summary counters are independently covered by VT proofs.
    _ = try terminal.feed("Howl");
    try std.testing.expectEqual(@as(u21, 'H'), terminal.semanticView(0).cellAt(0, 0));
    // zig-audit: acknowledge discard
    // reason: This consumer proof resolves the exact exported function declaration without invoking a runtime operation.
    _ = render.terminal.updateObservation;
    // zig-audit: acknowledge discard
    // reason: This consumer proof resolves the exact exported function declaration without invoking a runtime operation.
    _ = instance.terminal;
}

test "root exposes the complete native consumer vocabulary" {
    // zig-audit: acknowledge discard
    // reason: This consumer proof resolves the named public module; it owns no runtime value to retire.
    _ = @import("howl_pty");
    // zig-audit: acknowledge discard
    // reason: This consumer proof resolves the named public module; it owns no runtime value to retire.
    _ = @import("server_protocol").terminal;
    // zig-audit: acknowledge discard
    // reason: This consumer proof resolves the named public module; it owns no runtime value to retire.
    _ = @import("server_terminal_service");
    // zig-audit: acknowledge discard
    // reason: This consumer proof resolves the named public module; it owns no runtime value to retire.
    _ = @import("server_protocol");
    // zig-audit: acknowledge discard
    // reason: This consumer proof resolves the named public module; it owns no runtime value to retire.
    _ = @import("server");
    // zig-audit: acknowledge discard
    // reason: This consumer proof resolves the named public module; it owns no runtime value to retire.
    _ = @import("server_service");
    // zig-audit: acknowledge discard
    // reason: This consumer proof resolves the named public module; it owns no runtime value to retire.
    _ = @import("server_runtime");
    // zig-audit: acknowledge discard
    // reason: This consumer proof resolves the named public module; it owns no runtime value to retire.
    _ = @import("server_client");
    // zig-audit: acknowledge discard
    // reason: This consumer proof resolves the named public module; it owns no runtime value to retire.
    _ = @import("howl_cli");
    // zig-audit: acknowledge discard
    // reason: This consumer proof resolves the named public module; it owns no runtime value to retire.
    _ = @import("howl_render_limits");
    // zig-audit: acknowledge discard
    // reason: This consumer proof resolves the named public module; it owns no runtime value to retire.
    _ = @import("howl_text_test_fonts");
    // zig-audit: acknowledge discard
    // reason: This consumer proof resolves the named public module; it owns no runtime value to retire.
    _ = @import("howl_vk");
    // zig-audit: acknowledge discard
    // reason: This consumer proof resolves the named public module; it owns no runtime value to retire.
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
    // zig-audit: acknowledge discard
    // reason: The proof checks canonical content and public function/type identity; feed summary counters are independently covered by VT proofs.
    _ = try terminal.feed("A\xcc\x81");
    const view = terminal.semanticView(0);
    var output: [24]u21 = undefined;
    try std.testing.expectEqual(@as(u32, 'A'), cell(&view, 0, 0).codepoint);
    try std.testing.expectEqualSlices(u21, &.{ 'A', 0x0301 }, scalars(&view, 0, 0, &output));
    try std.testing.expectEqual(.single_width, geometry(&view, 0));
}

test "Server clients share the wire without importing host ownership" {
    const client = @import("server_client");
    const protocol = @import("server_protocol");
    try std.testing.expect(client.protocol == protocol);
    try std.testing.expect(client.terminal.protocol == protocol.terminal);
    try std.testing.expect(!@hasDecl(client.terminal, "instance"));
    try std.testing.expect(!@hasDecl(client, "Runtime"));
    try std.testing.expect(!@hasDecl(protocol, "Server"));
    try std.testing.expect(!@hasDecl(protocol, "Runtime"));
}

test "Instance API has no remote protocol or client identity" {
    try std.testing.expect(!@hasDecl(instance, "protocol"));
    try std.testing.expect(!@hasDecl(instance, "ClientId"));
    try std.testing.expect(!@hasDecl(instance, "ResizeAuthority"));
}

test "optional VT codec has its own root and canonical wire value identity" {
    const codec = @import("howl_vt_codec");
    const wire = @import("server_protocol").terminal;
    try std.testing.expect(codec.TextColor == wire.TextColor);
    try std.testing.expect(codec.SnapshotImage == wire.SnapshotImage);
    try std.testing.expect(codec.properties == wire.properties);
    try std.testing.expect(codec.Metadata == @TypeOf(@as(wire.SnapshotBegin, undefined).terminal));
    try std.testing.expect(!@hasField(codec.Metadata, "stream_closed"));
    try std.testing.expect(!@hasField(codec.Metadata, "leader_present"));
    try std.testing.expect(!@hasField(codec.Metadata, "you_are_leader"));
    try std.testing.expect(codec.Row == @import("server_client").terminal.rich.Row);
    try std.testing.expect(!@hasField(codec.cache.View, "begin"));
    try std.testing.expect(!@hasField(codec.cache.View, "changed_rows_base_revision"));
    try std.testing.expect(!@hasDecl(vt, "codec"));
    try std.testing.expect(!@hasDecl(instance, "codec"));
    try std.testing.expect(!@hasDecl(render, "codec"));
    try std.testing.expect(!@hasDecl(codec, "Terminal"));
    try std.testing.expect(!@hasDecl(codec, "ClientId"));
    try std.testing.expect(!@hasDecl(codec, "ResizeAuthority"));
    const color = codec.TextColor{ .kind = .rgb, .value = 0x123456 };
    var bytes: [codec.text_v1.color_bytes]u8 = undefined;
    try codec.encodeTextColor(&bytes, color);
    try std.testing.expectEqualDeep(color, try codec.decodeTextColor(&bytes));
}
