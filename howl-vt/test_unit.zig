test {
    _ = @import("src/howl_vt.zig");
    _ = @import("test/unit/terminal_test.zig");
    _ = @import("test/unit/terminal_cursor_test.zig");
    _ = @import("test/unit/terminal_modes_test.zig");
    _ = @import("test/unit/terminal_osc_test.zig");
    _ = @import("src/screen/main_test.zig");
    _ = @import("test/unit/terminal_snapshot_test.zig");
    _ = @import("test/unit/terminal_end_to_end_test.zig");
    _ = @import("src/screen/cursor_test.zig");
    _ = @import("src/screen/history_test.zig");
    _ = @import("src/screen/resize_test.zig");
    _ = @import("src/screen/tabs_test.zig");
    _ = @import("src/screen/write_test.zig");
    _ = @import("test/unit/parser/csi_test.zig");
    _ = @import("test/unit/parser/events_test.zig");
    _ = @import("test/unit/parser/main_test.zig");
    _ = @import("test/unit/parser/string_control_test.zig");
}
