//! Proves that child modules retain one type identity through the Howl root.
const std = @import("std");
const vt = @import("howl_vt");

test "standalone VT composes through root exports" {
    var terminal = try vt.Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    // zig-audit: acknowledge discard
    // reason: The proof checks canonical content and public function/type identity; feed summary counters are independently covered by VT proofs.
    _ = try terminal.feed("Howl");
    try std.testing.expectEqual(@as(u21, 'H'), terminal.semanticView(0).cellAt(0, 0));
}

test "root exposes the complete native consumer vocabulary" {
    // zig-audit: acknowledge discard
    // reason: This consumer proof resolves the named public module; it owns no runtime value to retire.
    _ = @import("howl_pty");
    const text = @import("howl_text");
    try std.testing.expect(@hasDecl(text, "FontSet"));
    // zig-audit: acknowledge discard
    // reason: This consumer proof resolves the named public module; it owns no runtime value to retire.
    _ = @import("vt_clipboard_grammar");
    // zig-audit: acknowledge discard
    // reason: This consumer proof resolves the named public module; it owns no runtime value to retire.
    _ = @import("howl_vt_output_limits");
    // zig-audit: acknowledge discard
    // reason: This consumer proof resolves the named public module; it owns no runtime value to retire.
    _ = @import("howl_text_test_fonts");
    const commands = @import("howl_vt_output_commands");
    try std.testing.expect(@hasDecl(commands, "Command"));
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

test "VT exports only its canonical OSC 52 grammar, never a transport codec" {
    const grammar = @import("vt_clipboard_grammar");
    const request = grammar.parse("c;SG93bA==").?;
    try std.testing.expectEqualStrings("c", request.selection);
    try std.testing.expect(request.kind == .set);
    try std.testing.expect(grammar.parse("c;????") == null);
    try std.testing.expect(!@hasDecl(vt, "codec"));
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
