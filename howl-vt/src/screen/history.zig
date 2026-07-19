//! Owns logical history lines, reflow snapshots, and row-count arithmetic.

const std = @import("std");
const cell = @import("cell.zig");

const Cell = cell.Cell;

/// Convert a checked standard-library length to the history/reflow domain.
pub fn count32(len: usize) u32 {
    std.debug.assert(len <= std.math.maxInt(u32));
    return @intCast(len);
}

/// Return rows needed for `cell_count`, or zero when no columns exist.
pub fn rowCountForCells(cell_count: u32, cols: u16) u32 {
    if (cols == 0) return 0;
    return @max(@as(u32, 1), std.math.divCeil(u32, cell_count, cols) catch unreachable);
}

/// Owned logical terminal line used while reflowing retained content.
pub const LogicalLine = struct {
    cells: std.ArrayListUnmanaged(Cell) = .empty,
    cursor_offset: ?u32 = null,

    /// Release cloned cells and reset the line.
    pub fn deinit(self: *LogicalLine, allocator: std.mem.Allocator) void {
        self.cells.deinit(allocator);
        self.* = .{};
    }
};

/// Owned logical-content snapshot and cursor location used by resize.
pub const LogicalSnapshot = struct {
    logical_lines: std.ArrayListUnmanaged(LogicalLine) = .empty,
    cursor_found: bool = false,
    cursor_line_index: u32 = 0,
    cursor_offset: u32 = 0,

    /// Release every cloned line and reset the snapshot.
    pub fn deinit(self: *LogicalSnapshot, allocator: std.mem.Allocator) void {
        for (self.logical_lines.items) |*line| line.deinit(allocator);
        self.logical_lines.deinit(allocator);
        self.* = .{};
    }
};

/// Owns one logical history line’s cells until deinit.
pub const HistoryLine = struct {
    cells: std.ArrayListUnmanaged(Cell) = .empty,

    /// Releases a history line’s cell allocation.
    pub fn deinit(self: *HistoryLine, allocator: std.mem.Allocator) void {
        self.cells.deinit(allocator);
        self.* = .{};
    }
};

/// Borrows one row window from a reflowed logical line.
pub const RewrappedRow = struct {
    start: u32,
    len: u16,
    wrapped: bool,
};

/// Finds the logical line containing a projected row within parallel bounded arrays.
pub fn firstLineForRowBounded(line_row_starts: []const u32, line_row_counts: []const u16, row_index: u32) ?u32 {
    std.debug.assert(line_row_starts.len == line_row_counts.len);
    for (line_row_starts, line_row_counts, 0..) |row_start, row_count, line_idx| {
        if (row_count == 0) continue;
        if (row_index < row_start + row_count) return @intCast(line_idx);
    }
    return null;
}
