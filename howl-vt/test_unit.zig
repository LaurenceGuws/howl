test {
    _ = @import("src/howl_vt.zig");
    _ = @import("test/unit/terminal_test.zig");
    _ = @import("test/unit/terminal_cursor_test.zig");
    _ = @import("test/unit/terminal_modes_test.zig");
    _ = @import("test/unit/terminal_osc_test.zig");
    _ = @import("test/unit/terminal_surface_test.zig");
    _ = @import("test/unit/screen_test.zig");
    _ = @import("test/unit/route_test.zig");
    _ = @import("test/unit/terminal_snapshot_test.zig");
    _ = @import("test/unit/terminal_end_to_end_test.zig");
    _ = @import("test/unit/screen/cursor_test.zig");
    _ = @import("test/unit/screen/history_test.zig");
    _ = @import("test/unit/screen/resize_test.zig");
    _ = @import("test/unit/screen/tabs_test.zig");
    _ = @import("test/unit/screen/write_test.zig");
    _ = @import("test/unit/report_test.zig");
    _ = @import("test/unit/parser/csi_test.zig");
    _ = @import("test/unit/parser/events_test.zig");
    _ = @import("test/unit/parser/main_test.zig");
    _ = @import("test/unit/parser/string_control_test.zig");
    _ = @import("test/unit/csi_mapping_test.zig");
}
