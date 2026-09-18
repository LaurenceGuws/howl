//! Proves that the selected public root exposes only drawing/presentation owners.

const std = @import("std");
const render = @import("howl_render");
const selected = @import("selected_capabilities");

test "public namespaces exactly match compile-time selection" {
    try std.testing.expect(@hasDecl(render, "presentation"));
    try std.testing.expect(@hasDecl(render, "canvas"));
    try std.testing.expectEqual(selected.native_text, @hasDecl(render, "terminal"));
    try std.testing.expect(!@hasDecl(render, "chrome"));
    try std.testing.expect(!@hasDecl(render, "generated"));
    try std.testing.expectEqual(selected.native_text, @hasDecl(render, "text"));
}

comptime {
    std.testing.refAllDecls(@import("canvas_test.zig"));
    if (selected.native_text) std.testing.refAllDecls(@import("terminal_test.zig"));
}
