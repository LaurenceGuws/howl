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
    _ = @import("vt_clipboard_grammar");
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

test "Instance API has no remote protocol or client identity" {
    try std.testing.expect(!@hasDecl(instance, "protocol"));
    try std.testing.expect(!@hasDecl(instance, "ClientId"));
    try std.testing.expect(!@hasDecl(instance, "ResizeAuthority"));
}

test "VT exports only its canonical OSC 52 grammar, never a transport codec" {
    const grammar = @import("vt_clipboard_grammar");
    const request = grammar.parse("c;SG93bA==").?;
    try std.testing.expectEqualStrings("c", request.selection);
    try std.testing.expect(request.kind == .set);
    try std.testing.expect(grammar.parse("c;????") == null);
    try std.testing.expect(!@hasDecl(vt, "codec"));
    try std.testing.expect(!@hasDecl(instance, "protocol"));
    try std.testing.expect(!@hasDecl(render, "codec"));
}

extern fn howl_external_instance_abi() c_int;

test "root exposes exact Instance native artifact and VT-owned header" {
    const native = @import("howl_instance_native");
    const native_vt = @import("howl_vt_native");
    try std.testing.expect(native.Instance == instance.Instance);
    try std.testing.expect(native.vt.Terminal == vt.Terminal);
    try std.testing.expect(native_vt.Terminal == vt.Terminal);
    try std.testing.expectEqual(@as(c_int, 0), howl_external_instance_abi());
}

extern fn howl_external_vt_abi() c_int;
test "root forwards exact standalone VT artifact native owner and header" {
    const native = @import("howl_vt_native");
    try std.testing.expect(native.Terminal == vt.Terminal);
    try std.testing.expect(@typeInfo(native.owner.Owner) == .@"opaque");
    try std.testing.expect(native.observation.Reader != native.observation.Controller);
    try std.testing.expect(@TypeOf(native.observation.read) == fn (*const native.observation.Reader) native.observation.ReadError!*const vt.Terminal.Observation);
    try std.testing.expect(@TypeOf(native.owner.observation) == fn (*const native.owner.Owner) *const vt.Terminal.Observation);
    try std.testing.expectEqual(@as(c_int, 0), howl_external_vt_abi());
}

extern fn howl_external_render_abi([*]const u8, usize) c_int;
test "root forwards one Render owner schema and exact source identity through real C composition" {
    const owner = @import("howl_render_owner_native");
    const native = @import("howl_render_native");
    const native_vt = @import("howl_vt_native");
    try std.testing.expect(owner.Reader == native_vt.observation.Reader);
    try std.testing.expect(owner.c.hrc_command == native.c.hrc_command);
    try std.testing.expect(@typeInfo(owner.Owner) == .@"opaque");
    try std.testing.expect(@typeInfo(owner.Buffer) == .@"opaque");
    const font = @import("howl_text_test_fonts").primary_font;
    try std.testing.expectEqual(@as(c_int, 0), howl_external_render_abi(font.ptr, font.len));
}
