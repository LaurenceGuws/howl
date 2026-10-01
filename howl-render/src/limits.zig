//! Defines bounded limits for maintained terminal-frame production.
//!
//! Session geometry remains generic `u16` protocol state. These bounds are the
//! renderer/client contract for maintained Howl presentations so native and Web
//! cannot drift into different viewport or Canvas-capacity policies.

const std = @import("std");

/// Largest maintained-renderer terminal row count.
pub const maximum_rows: u16 = 192;
/// Largest maintained-renderer terminal column count.
pub const maximum_columns: u16 = 512;
/// Largest maintained-renderer cell lattice.
pub const maximum_cells: usize = @as(usize, maximum_rows) * @as(usize, maximum_columns);
/// Complete terminal-frame command envelope shared by maintained hosts.
///
/// One ordinary dense glyph per cell consumes `maximum_cells`. The remaining
/// 16K commands cover image placements and ordinary non-cell work, with one
/// additional cursor/background slot at the full dense-image boundary.
pub const maximum_canvas_commands: usize = maximum_cells + 16 * 1024 + 1;

comptime {
    if (maximum_rows == 0 or maximum_columns == 0)
        @compileError("terminal-frame geometry limits must be nonzero");
    if (maximum_canvas_commands <= maximum_cells)
        @compileError("terminal-frame command envelope must include non-cell headroom");
    if (maximum_canvas_commands > std.math.maxInt(u32))
        @compileError("terminal-frame command envelope exceeds bounded host counters");
}

test "maintained terminal-frame limits cover 4K-scaled compact desktop" {
    try std.testing.expect(maximum_rows >= 102);
    try std.testing.expect(maximum_columns >= 376);
    try std.testing.expectEqual(@as(usize, 98_304), maximum_cells);
    try std.testing.expectEqual(@as(usize, 114_689), maximum_canvas_commands);
}
