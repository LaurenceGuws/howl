//! Proves that the selected public root exposes exactly its admitted capabilities.

const std = @import("std");
const render = @import("howl_render");
const selected = @import("selected_capabilities");

test "public namespaces exactly match compile-time selection" {
    try std.testing.expectEqual(selected.native_text, @hasDecl(render, "text"));
    try std.testing.expectEqual(
        selected.generated_glyphs,
        @hasDecl(render, "generated"),
    );
}

comptime {
    if (selected.native_text) _ = @import("native_test.zig");
    if (selected.generated_glyphs) _ = @import("generated_test.zig");
}
