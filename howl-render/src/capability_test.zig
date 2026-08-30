//! Proves that the selected public root exposes exactly its selected capabilities.

const std = @import("std");
const render = @import("howl_render");
const selected = @import("selected_capabilities");

test "public namespaces exactly match compile-time selection" {
    try std.testing.expect(@hasDecl(render, "canvas"));
    try std.testing.expect(@hasDecl(render, "chrome"));
    try std.testing.expectEqual(
        selected.native_text,
        @hasDecl(render.chrome, "Content"),
    );
    try std.testing.expectEqual(selected.native_text, @hasDecl(render, "text"));
    try std.testing.expectEqual(selected.native_text, @hasDecl(render, "terminal"));
    try std.testing.expectEqual(
        selected.generated_glyphs,
        @hasDecl(render, "generated"),
    );
}

comptime {
    std.testing.refAllDecls(@import("canvas_test.zig"));
    std.testing.refAllDecls(@import("chrome_test.zig"));
    if (selected.native_text) {
        std.testing.refAllDecls(@import("chrome_reuse_test.zig"));
        std.testing.refAllDecls(@import("terminal_test.zig"));
    }
    if (selected.generated_glyphs) std.testing.refAllDecls(@import("generated_test.zig"));
}
