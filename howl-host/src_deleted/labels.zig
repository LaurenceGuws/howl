//! Owns one bounded, platform-independent tab-label row and its cell hits.

const std = @import("std");
const workspace = @import("workspace.zig");

/// Reports whether every, some, or no terminal in one tab is unavailable.
pub const Availability = enum { available, degraded, unavailable };

/// Borrows the exact workspace and terminal facts needed to format one tab.
pub const Tab = struct {
    /// Identifies the workspace tab selected by this label.
    id: workspace.TabId,
    /// Borrows the retained workspace name for this call only.
    name: []const u8,
    /// Marks the one active workspace tab.
    active: bool,
    /// Reports the nonzero number of panes owned by this tab.
    panes: u8,
    /// Reports how many of those panes have stopped.
    unavailable_panes: u8,
};

/// Carries one presentation cell without choosing pixels, fonts, or policy.
pub const Cell = struct {
    /// Stores one valid Unicode scalar; space is the blank presentation cell.
    codepoint: u21 = ' ',
    /// Selects active or inactive palette treatment.
    active: bool = false,
    /// Retains aggregate terminal availability for visible status marking.
    availability: Availability = .available,
};

/// Maps one contiguous, nonempty cell range to one stable tab identity.
pub const Hit = struct {
    /// Selects the workspace tab without mutating it.
    tab: workspace.TabId,
    /// Identifies the inclusive first label column.
    start: u16,
    /// Identifies the exclusive last label column.
    end: u16,
};

/// Reports one nonempty half-open pixel range owned by a label cell.
pub const PixelBounds = struct {
    /// Identifies the inclusive first pixel.
    start: u32,
    /// Identifies the exclusive last pixel.
    end: u32,
};

/// Owns one complete bounded label row and exact hit ranges.
pub const Row = struct {
    /// Stores the first `cell_count` initialized presentation cells.
    cells: [workspace.max_cols]Cell = undefined,
    /// Reports the admitted nonzero row width.
    cell_count: u16 = 0,
    /// Stores the first `hit_count` initialized tab ranges.
    hits: [workspace.max_tabs]Hit = undefined,
    /// Reports how many tabs are visible in this row.
    hit_count: u8 = 0,

    /// Borrow initialized presentation cells only.
    pub fn cellSlice(self: *const Row) []const Cell {
        return self.cells[0..self.cell_count];
    }

    /// Resolve one zero-based cell column to its visible tab identity.
    pub fn hit(self: *const Row, col: u16) ?workspace.TabId {
        if (col >= self.cell_count) return null;
        for (self.hits[0..self.hit_count]) |value|
            if (col >= value.start and col < value.end) return value.tab;
        return null;
    }
};

/// Resolve one cell's proportional share of the complete pixel row.
pub fn pixelBounds(
    width: u32,
    count: u16,
    col: u16,
) error{InvalidGeometry}!PixelBounds {
    if (width == 0 or count == 0 or count > width or col >= count)
        return error.InvalidGeometry;
    return .{
        .start = width * col / count,
        .end = width * @as(u32, col + 1) / count,
    };
}

/// Map one in-bounds pixel to the exact cell range used for painting.
pub fn pixelColumn(width: u32, count: u16, x: u32) ?u16 {
    if (width == 0 or count == 0 or count > width or x >= width) return null;
    return @intCast(@min(count - 1, ((x + 1) * count - 1) / width));
}

/// Format one complete row without allocation or workspace mutation.
///
/// Every visible tab receives at least one cell. If the row is narrower than
/// the tab count, only the active tab is shown; keyboard tab traversal remains
/// workspace policy. Invalid facts leave caller state untouched.
pub fn format(columns: u16, tabs: []const Tab) error{InvalidFacts}!Row {
    if (columns == 0 or columns > workspace.max_cols or tabs.len == 0 or
        tabs.len > workspace.max_tabs) return error.InvalidFacts;
    var active_index: ?usize = null;
    for (tabs, 0..) |candidate, index| {
        if (@intFromEnum(candidate.id) == 0 or candidate.name.len == 0 or candidate.panes == 0 or
            candidate.unavailable_panes > candidate.panes) return error.InvalidFacts;
        for (tabs[0..index]) |prior| if (prior.id == candidate.id) return error.InvalidFacts;
        if (candidate.active) {
            if (active_index != null) return error.InvalidFacts;
            active_index = index;
        }
    }
    const active = active_index orelse return error.InvalidFacts;
    var row = Row{ .cell_count = columns };
    const shown_count: usize = if (columns < tabs.len) 1 else tabs.len;
    const base = columns / @as(u16, @intCast(shown_count));
    const extra = columns % @as(u16, @intCast(shown_count));
    var start: u16 = 0;
    for (0..shown_count) |shown_index| {
        const tab = tabs[if (shown_count == 1 and tabs.len != 1) active else shown_index];
        const width = base + @intFromBool(shown_index < extra);
        const end = start + width;
        const availability: Availability = if (tab.unavailable_panes == 0)
            .available
        else if (tab.unavailable_panes == tab.panes)
            .unavailable
        else
            .degraded;
        for (row.cells[start..end]) |*cell| cell.* = .{
            .active = tab.active,
            .availability = availability,
        };
        writeLabel(row.cells[start..end], tab.name, availability);
        row.hits[row.hit_count] = .{ .tab = tab.id, .start = start, .end = end };
        row.hit_count += 1;
        start = end;
    }
    std.debug.assert(start == columns);
    return row;
}

fn writeLabel(cells: []Cell, name: []const u8, availability: Availability) void {
    var destination: usize = 0;
    if (availability != .available) {
        cells[0].codepoint = if (availability == .unavailable) '!' else '~';
        destination = 1;
    }
    var source: usize = 0;
    while (destination < cells.len and source < name.len) : (destination += 1)
        cells[destination].codepoint = nextScalar(name, &source);
    if (source < name.len and destination != 0 and !(cells.len == 1 and availability != .available))
        cells[destination - 1].codepoint = 0x2026;
}

fn nextScalar(bytes: []const u8, index: *usize) u21 {
    const length = std.unicode.utf8ByteSequenceLength(bytes[index.*]) catch {
        index.* += 1;
        return 0xfffd;
    };
    if (length > bytes.len - index.*) {
        index.* += 1;
        return 0xfffd;
    }
    const scalar = std.unicode.utf8Decode(bytes[index.*..][0..length]) catch {
        index.* += 1;
        return 0xfffd;
    };
    index.* += length;
    return scalar;
}

fn makeTab(id: u64, name: []const u8, active: bool, panes: u8, unavailable: u8) Tab {
    return .{
        .id = @enumFromInt(id),
        .name = name,
        .active = active,
        .panes = panes,
        .unavailable_panes = unavailable,
    };
}

test "labels aggregate availability and preserve exact hit geometry" {
    const row = try format(12, &.{
        makeTab(1, "one", true, 2, 0),
        makeTab(2, "two", false, 3, 1),
        makeTab(3, "three", false, 1, 1),
    });
    try std.testing.expectEqual(@as(u16, 12), row.cell_count);
    try std.testing.expectEqual(@as(u8, 3), row.hit_count);
    try std.testing.expectEqual(@as(?workspace.TabId, @enumFromInt(1)), row.hit(0));
    try std.testing.expectEqual(@as(?workspace.TabId, @enumFromInt(2)), row.hit(4));
    try std.testing.expectEqual(@as(?workspace.TabId, @enumFromInt(3)), row.hit(11));
    try std.testing.expectEqual(@as(?workspace.TabId, null), row.hit(12));
    try std.testing.expectEqual(Availability.available, row.cells[0].availability);
    try std.testing.expectEqual(Availability.degraded, row.cells[4].availability);
    try std.testing.expectEqual(@as(u21, '~'), row.cells[4].codepoint);
    try std.testing.expectEqual(Availability.unavailable, row.cells[8].availability);
    try std.testing.expectEqual(@as(u21, '!'), row.cells[8].codepoint);
}

test "narrow rows retain active identity and deterministic truncation" {
    const narrow = try format(2, &.{
        makeTab(1, "first", false, 1, 0),
        makeTab(2, "second", true, 1, 1),
        makeTab(3, "third", false, 1, 0),
    });
    try std.testing.expectEqual(@as(u8, 1), narrow.hit_count);
    try std.testing.expectEqual(@as(?workspace.TabId, @enumFromInt(2)), narrow.hit(0));
    try std.testing.expectEqual(@as(?workspace.TabId, @enumFromInt(2)), narrow.hit(1));
    try std.testing.expectEqual(@as(u21, '!'), narrow.cells[0].codepoint);
    try std.testing.expectEqual(@as(u21, 0x2026), narrow.cells[1].codepoint);

    const unicode = try format(3, &.{makeTab(7, "aéx", true, 1, 0)});
    try std.testing.expectEqual(@as(u21, 'a'), unicode.cells[0].codepoint);
    try std.testing.expectEqual(@as(u21, 0xe9), unicode.cells[1].codepoint);
    try std.testing.expectEqual(@as(u21, 'x'), unicode.cells[2].codepoint);
}

test "invalid label facts reject before returning presentation" {
    try std.testing.expectError(error.InvalidFacts, format(0, &.{makeTab(1, "one", true, 1, 0)}));
    try std.testing.expectError(error.InvalidFacts, format(2, &.{}));
    try std.testing.expectError(error.InvalidFacts, format(2, &.{makeTab(1, "one", false, 1, 0)}));
    try std.testing.expectError(error.InvalidFacts, format(2, &.{
        makeTab(1, "one", true, 1, 0),
        makeTab(1, "two", false, 1, 0),
    }));
    try std.testing.expectError(error.InvalidFacts, format(2, &.{makeTab(1, "one", true, 1, 2)}));
}

test "pixel hits invert proportional paint across surplus and hostile narrow widths" {
    const first_surplus = try pixelBounds(25, 2, 0);
    const second_surplus = try pixelBounds(25, 2, 1);
    try std.testing.expectEqual(PixelBounds{ .start = 0, .end = 12 }, first_surplus);
    try std.testing.expectEqual(PixelBounds{ .start = 12, .end = 25 }, second_surplus);
    try std.testing.expectEqual(@as(?u16, 0), pixelColumn(25, 2, 11));
    try std.testing.expectEqual(@as(?u16, 1), pixelColumn(25, 2, 12));
    try std.testing.expectEqual(@as(?u16, 1), pixelColumn(25, 2, 24));

    const first = try pixelBounds(2, 2, 0);
    const second = try pixelBounds(2, 2, 1);
    try std.testing.expectEqual(PixelBounds{ .start = 0, .end = 1 }, first);
    try std.testing.expectEqual(PixelBounds{ .start = 1, .end = 2 }, second);
    try std.testing.expectEqual(@as(?u16, 0), pixelColumn(2, 2, 0));
    try std.testing.expectEqual(@as(?u16, 1), pixelColumn(2, 2, 1));
    try std.testing.expectEqual(@as(?u16, null), pixelColumn(2, 2, 2));
    try std.testing.expectError(error.InvalidGeometry, pixelBounds(1, 2, 0));
}
