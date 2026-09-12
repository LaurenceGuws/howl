//! Owns the bounded maintained-client terminal presentation envelope.
//!
//! Session geometry remains generic `u16` protocol state. These bounds are the
//! renderer/client contract for maintained Howl presentations so native and Web
//! cannot drift into different viewport or Canvas-capacity policies.

const std = @import("std");

/// Largest maintained-client terminal row count.
pub const maximum_rows: u16 = 192;
/// Largest maintained-client terminal column count.
pub const maximum_columns: u16 = 512;
/// Largest maintained-client cell lattice.
pub const maximum_cells: usize = @as(usize, maximum_rows) * @as(usize, maximum_columns);
/// Complete Canvas command envelope shared by maintained native and Web hosts.
///
/// One ordinary dense glyph per cell consumes `maximum_cells`. The remaining
/// 16K commands cover backgrounds, decorations, cursor work, and image
/// placements without making a supported desktop lattice depend on sparsity.
pub const maximum_canvas_commands: usize = maximum_cells + 16 * 1024;

comptime {
    if (maximum_rows == 0 or maximum_columns == 0)
        @compileError("presentation geometry must be nonzero");
    if (maximum_canvas_commands <= maximum_cells)
        @compileError("presentation command envelope must include non-cell headroom");
    if (maximum_canvas_commands > std.math.maxInt(u32))
        @compileError("presentation command envelope exceeds bounded host counters");
}

test "maintained presentation envelope covers 4K-scaled compact desktop" {
    try std.testing.expect(maximum_rows >= 102);
    try std.testing.expect(maximum_columns >= 376);
    try std.testing.expectEqual(@as(usize, 98_304), maximum_cells);
    try std.testing.expectEqual(@as(usize, 114_688), maximum_canvas_commands);
}
