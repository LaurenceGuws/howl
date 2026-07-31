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
    try std.testing.expectEqual(
        selected.generated_glyphs,
        @hasDecl(render, "generated"),
    );
    try std.testing.expectEqual(selected.terminal, @hasDecl(render, "terminal"));
    try std.testing.expectEqual(selected.terminal, @hasDecl(render, "terminal_images"));
    try std.testing.expect(!@hasDecl(render, "terminal_text"));
    if (selected.terminal) {
        try std.testing.expect(@hasDecl(render.terminal, "Content"));
        try std.testing.expect(@hasDecl(
            render.terminal,
            "GeneratedBoxConfig",
        ));
        try std.testing.expect(@hasDecl(render.terminal, "FontMap"));
        try std.testing.expectEqual(
            selected.native_text,
            @sizeOf(render.terminal.FontMap) != 0,
        );
    }
}

comptime {
    std.testing.refAllDecls(@import("canvas_test.zig"));
    std.testing.refAllDecls(@import("chrome_test.zig"));
    if (selected.native_text) std.testing.refAllDecls(@import("chrome_reuse_test.zig"));
    if (selected.native_text and selected.terminal)
        std.testing.refAllDecls(@import("vertical_test.zig"));
    if (selected.native_text) std.testing.refAllDecls(@import("native_test.zig"));
    if (selected.generated_glyphs) std.testing.refAllDecls(@import("generated_test.zig"));
    if (selected.terminal) std.testing.refAllDecls(@import("terminal_text_test.zig"));
}
