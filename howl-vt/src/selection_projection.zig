//! Projects VT/history selections into visible rows and copied text.

const std = @import("std");
const screen_set = @import("screen_set.zig");
const state = @import("selection.zig");

/// Stores a half-open visible column range for one projected selection row.
pub const Range = struct {
    start: u16,
    end_exclusive: u16,
};

/// Failures produced while copying selected cells into UTF-8 caller storage.
pub const CopyError = error{
    CodepointTooLarge,
    OutOfMemory,
    Utf8CannotEncodeSurrogateHalf,
};

fn rowSource(screen_state: *const screen_set.Set, row: i32) ?screen_set.RowSource {
    if (row < 0) return null;
    const active = screen_state.activeConst();
    const absolute: u32 = std.math.cast(u32, row) orelse return null;
    const history_base = if (screen_state.alt_active) 0 else screen_state.primary.historyRowBase();
    if (absolute < history_base) return null;
    const logical_row = absolute - history_base;
    const history_count = if (screen_state.alt_active) 0 else screen_state.primary.historyCount();
    if (logical_row < history_count) return .{ .history = history_count - 1 - logical_row };
    const screen_row = logical_row - history_count;
    if (screen_row >= active.rows) return null;
    return .{ .screen = @intCast(screen_row) };
}

fn contentEndExclusive(screen_state: *const screen_set.Set, row: i32) u16 {
    const source = rowSource(screen_state, row) orelse return 0;
    const active = screen_state.activeConst();
    var scan = active.cols;
    while (scan > 0) {
        const idx = scan - 1;
        const cell = switch (source) {
            .history => |recency| active.historyCellAt(recency, idx),
            .screen => |screen_row| active.cellInfoAt(screen_row, idx),
        };
        if (cell.codepoint != 0 and cell.codepoint != ' ') return scan;
        scan -= 1;
    }
    return if (active.cols > 0) 1 else 0;
}

fn visibleRow(view: screen_set.View, row: u16) i32 {
    std.debug.assert(row < view.rows or view.rows == 0);
    const absolute = @as(u64, view.history_row_base) + @as(u64, view.start) + @as(u64, row);
    return std.math.cast(i32, absolute) orelse std.math.maxInt(i32);
}

/// Projects an ordered selection onto one visible row, or null outside the selection.
pub fn visibleRange(view: screen_set.View, selected: state.TerminalSelection, row: u16) ?Range {
    std.debug.assert(row < view.rows or view.rows == 0);
    const ordered = state.ordered(selected);
    const selected_row = visibleRow(view, row);
    if (selected_row < ordered.start.row or selected_row > ordered.end.row) return null;

    const row_end = view.contentEndExclusive(row);
    if (row_end == 0) return null;

    const range_start: u16 = if (selected_row == ordered.start.row) ordered.start.col else 0;
    const unclamped_end: u32 = if (selected_row == ordered.end.row)
        @as(u32, ordered.end.col) + 1
    else
        row_end;
    const range_end: u16 = @intCast(@min(unclamped_end, row_end));
    if (range_start >= range_end) return null;
    std.debug.assert(range_end <= view.cols);
    return .{ .start = range_start, .end_exclusive = range_end };
}

/// Copy selected cells into caller-owned UTF-8 memory.
///
/// The caller owns a successful non-empty result. Invalid stored codepoints
/// are reported exactly instead of trapping during integer narrowing.
pub fn copyText(allocator: std.mem.Allocator, screen_state: *const screen_set.Set, selected: ?state.TerminalSelection) CopyError![]const u8 {
    const active_selection = selected orelse return &.{};
    const ordered_selection = state.ordered(active_selection);
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var row = ordered_selection.start.row;
    while (row <= ordered_selection.end.row) : (row += 1) {
        const source = rowSource(screen_state, row) orelse break;
        const row_start = if (row == ordered_selection.start.row) ordered_selection.start.col else 0;
        const row_end = if (row == ordered_selection.end.row)
            @as(u16, @intCast(@min(@as(u32, ordered_selection.end.col) + 1, @as(u32, screen_state.activeConst().cols))))
        else
            contentEndExclusive(screen_state, row);
        if (row_end > row_start) {
            var col = row_start;
            while (col < row_end) : (col += 1) {
                const cell = switch (source) {
                    .history => |recency| screen_state.primary.historyCellAt(recency, col),
                    .screen => |screen_row| screen_state.activeConst().cellInfoAt(screen_row, col),
                };
                if (cell.codepoint == 0) continue;
                var utf8: [4]u8 = undefined;
                const codepoint = std.math.cast(u21, cell.codepoint) orelse return error.CodepointTooLarge;
                const len = try std.unicode.utf8Encode(codepoint, &utf8);
                try out.appendSlice(allocator, utf8[0..len]);
            }
        }
        if (row != ordered_selection.end.row) try out.append(allocator, '\n');
    }
    return out.toOwnedSlice(allocator);
}
