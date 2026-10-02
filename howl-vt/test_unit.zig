test {
    // zig-audit: acknowledge discard
    // reason: The test root imports this module only to register its tests; the imported namespace itself is intentionally unused.
    _ = @import("src/howl_vt.zig");
    // zig-audit: acknowledge discard
    // reason: The test root imports this private owner only to register its storage proofs.
    _ = @import("src/history_store.zig");
    // zig-audit: acknowledge discard
    // reason: The test root imports this module only to register its tests; the imported namespace itself is intentionally unused.
    _ = @import("test/unit/terminal_test.zig");
    // zig-audit: acknowledge discard
    // reason: The test root imports this module only to register its tests; the imported namespace itself is intentionally unused.
    _ = @import("test/unit/terminal_cursor_test.zig");
    // zig-audit: acknowledge discard
    // reason: The test root imports this module only to register its tests; the imported namespace itself is intentionally unused.
    _ = @import("test/unit/terminal_modes_test.zig");
    // zig-audit: acknowledge discard
    // reason: The test root imports this module only to register its tests; the imported namespace itself is intentionally unused.
    _ = @import("test/unit/terminal_osc_test.zig");
    // zig-audit: acknowledge discard
    // reason: The test root imports this module only to register its tests; the imported namespace itself is intentionally unused.
    _ = @import("src/screen/main_test.zig");
    // zig-audit: acknowledge discard
    // reason: The test root imports this module only to register its tests; the imported namespace itself is intentionally unused.
    _ = @import("test/unit/terminal_snapshot_test.zig");
    // zig-audit: acknowledge discard
    // reason: The test root imports this module only to register its tests; the imported namespace itself is intentionally unused.
    _ = @import("test/unit/terminal_end_to_end_test.zig");
    // zig-audit: acknowledge discard
    // reason: The test root imports this module only to register its tests; the imported namespace itself is intentionally unused.
    _ = @import("test/unit/terminal_poison_test.zig");
    // zig-audit: acknowledge discard
    // reason: The test root imports this module only to register its tests; the imported namespace itself is intentionally unused.
    _ = @import("src/screen/cursor_test.zig");
    // zig-audit: acknowledge discard
    // reason: The test root imports this module only to register its tests; the imported namespace itself is intentionally unused.
    _ = @import("src/screen/history_test.zig");
    // zig-audit: acknowledge discard
    // reason: The test root imports this module only to register its tests; the imported namespace itself is intentionally unused.
    _ = @import("src/screen/resize_test.zig");
    // zig-audit: acknowledge discard
    // reason: The test root imports this module only to register its tests; the imported namespace itself is intentionally unused.
    _ = @import("src/screen/tabs_test.zig");
    // zig-audit: acknowledge discard
    // reason: The test root imports this module only to register its tests; the imported namespace itself is intentionally unused.
    _ = @import("src/screen/write_test.zig");
    // zig-audit: acknowledge discard
    // reason: The test root imports this module only to register its tests; the imported namespace itself is intentionally unused.
    _ = @import("test/unit/parser/csi_test.zig");
    // zig-audit: acknowledge discard
    // reason: The test root imports this module only to register its tests; the imported namespace itself is intentionally unused.
    _ = @import("test/unit/parser/main_test.zig");
    // zig-audit: acknowledge discard
    // reason: The test root imports this module only to register its tests; the imported namespace itself is intentionally unused.
    _ = @import("test/unit/parser/string_control_test.zig");
}
