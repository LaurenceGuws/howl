//! Owns bounded dirty-row and dirty-column publication state.

const std = @import("std");

/// Borrows the dirty row interval and optional per-row column bounds.
pub const DirtyRows = struct {
    start_row: u16,
    end_row: u16,
    dirty_cols_start: []const u16 = &.{},
    dirty_cols_end: []const u16 = &.{},
};

/// Owns dirty publication bounds for one screen allocation.
pub const DirtyState = struct {
    rows: ?DirtyRows = null,
    cols_start: ?[]u16 = null,
    cols_end: ?[]u16 = null,

    /// Marks every row and column dirty using caller-owned column arrays.
    pub fn initFull(row_count: u16, cols_start: ?[]u16, cols_end: ?[]u16) DirtyState {
        return .{
            .rows = rowsForFull(row_count, cols_start, cols_end),
            .cols_start = cols_start,
            .cols_end = cols_end,
        };
    }

    /// Releases optional dirty-column arrays through the screen allocator.
    pub fn deinit(self: *DirtyState, allocator: std.mem.Allocator) void {
        if (self.cols_start) |buf| allocator.free(buf);
        if (self.cols_end) |buf| allocator.free(buf);
        self.* = .{};
    }
};

/// Allocates and initializes one u16 column bound per row when rows are nonzero.
pub fn allocDirtyCols(allocator: std.mem.Allocator, rows: u16, initial: u16) std.mem.Allocator.Error!?[]u16 {
    if (rows == 0) return null;
    const buf = try allocator.alloc(u16, rows);
    @memset(buf, initial);
    return buf;
}

/// Returns a full dirty-row view when the screen has at least one row.
pub fn rowsForFull(rows: u16, dirty_cols_start: ?[]const u16, dirty_cols_end: ?[]const u16) ?DirtyRows {
    if (rows == 0) return null;
    return .{
        .start_row = 0,
        .end_row = rows -| 1,
        .dirty_cols_start = dirty_cols_start orelse &.{},
        .dirty_cols_end = dirty_cols_end orelse &.{},
    };
}
