//! Client-local terminal selection over stable canonical history/screen points.
//!
//! Selection ownership stays with the presentation client. The server owns only
//! canonical text extraction for an inclusive stable range. Viewport scrolling
//! therefore never mutates the selected range, while history eviction, screen-bank
//! switches, and geometry changes are detected explicitly.

const std = @import("std");
const protocol = @import("howl_session").protocol;
const client = @import("client.zig");
const view = @import("view.zig");

pub const Point = protocol.TextPoint;

pub const Error = client.Error || protocol.PayloadError || std.mem.Allocator.Error || error{
    ContextChanged,
    InvalidPoint,
    InvalidUtf8,
    SelectionRejected,
    UnexpectedFrame,
};

pub const Validity = enum { valid, context_changed, evicted };

pub const Span = struct {
    start_column: u16,
    end_column: u16,
};

pub const Range = struct {
    anchor: Point,
    focus: Point,
    columns: u16,
    alternate_screen: bool,

    /// Starts one collapsed selection at a displayed terminal cell.
    pub fn start(snapshot: *const view.Snapshot, viewport_row: u16, column: u16) Error!Range {
        const value = try point(snapshot, viewport_row, column);
        const begin = view.begin(snapshot);
        return .{
            .anchor = value,
            .focus = value,
            .columns = begin.columns,
            .alternate_screen = begin.alternate_screen,
        };
    }

    /// Moves only the focus endpoint. Geometry/bank changes invalidate rather than retarget.
    pub fn extend(self: *Range, snapshot: *const view.Snapshot, viewport_row: u16, column: u16) Error!void {
        if (self.validity(view.begin(snapshot)) == .context_changed) return error.ContextChanged;
        self.focus = try point(snapshot, viewport_row, column);
    }

    /// Classifies whether this stable range can still name the current canonical text domain.
    pub fn validity(self: Range, begin: *const protocol.SnapshotBegin) Validity {
        if (begin.columns != self.columns or begin.alternate_screen != self.alternate_screen)
            return .context_changed;
        const bounds = retainedRows(begin) orelse return .evicted;
        if (!pointRetained(self.anchor, self.columns, bounds) or
            !pointRetained(self.focus, self.columns, bounds))
            return .evicted;
        return .valid;
    }

    /// Returns the inclusive selected column span intersecting one displayed viewport row.
    pub fn viewportSpan(self: Range, begin: *const protocol.SnapshotBegin, viewport_row: u16) ?Span {
        if (self.validity(begin) != .valid or viewport_row >= begin.rows) return null;
        const row = viewportRow(begin, viewport_row) catch return null;
        const bounds = self.ordered();
        if (row < bounds.start.row or row > bounds.end.row) return null;
        return .{
            .start_column = if (row == bounds.start.row) bounds.start.column else 0,
            .end_column = if (row == bounds.end.row) bounds.end.column else self.columns - 1,
        };
    }

    pub fn request(self: Range) protocol.TextExtract {
        return .{
            .start = self.anchor,
            .end = self.focus,
            .columns = self.columns,
            .alternate_screen = self.alternate_screen,
        };
    }

    pub fn ordered(self: Range) struct { start: Point, end: Point } {
        if (pointBeforeOrEqual(self.anchor, self.focus))
            return .{ .start = self.anchor, .end = self.focus };
        return .{ .start = self.focus, .end = self.anchor };
    }
};

/// Resolves one displayed cell to its stable canonical lead-cell identity.
pub fn point(snapshot: *const view.Snapshot, viewport_row: u16, column: u16) Error!Point {
    const begin = view.begin(snapshot);
    if (viewport_row >= begin.rows or column >= begin.columns) return error.InvalidPoint;
    const row = view.rows(snapshot)[viewport_row];
    if (column >= row.cell_count) return error.InvalidPoint;
    const cell = view.cells(snapshot)[@as(usize, row.cell_offset) + column];
    return viewportPoint(begin, viewport_row, column, cell.x, cell.y);
}

/// Requests canonical UTF-8 for one client-local range. The returned allocation belongs to `allocator`.
pub fn extract(connection: *client.Connection, allocator: std.mem.Allocator, range: Range) Error![]u8 {
    var payload: [protocol.payload_bytes.text_extract]u8 = undefined;
    protocol.encodeTextExtract(&payload, range.request());
    try connection.send(.text_extract, &payload);
    var frame = try connection.receive();
    defer frame.deinit();
    switch (frame.kind) {
        .text_extract_data => {
            if (!std.unicode.utf8ValidateSlice(frame.payload)) return error.InvalidUtf8;
            return allocator.dupe(u8, frame.payload);
        },
        .result => {
            const result = try protocol.decodeResult(frame.payload);
            if (result.request_kind != .text_extract) return error.UnexpectedFrame;
            return error.SelectionRejected;
        },
        else => return error.UnexpectedFrame,
    }
}

const RowBounds = struct { first: i32, last: i32 };

fn retainedRows(begin: *const protocol.SnapshotBegin) ?RowBounds {
    if (begin.rows == 0) return null;
    if (begin.alternate_screen) return .{ .first = 0, .last = @intCast(begin.rows - 1) };
    const first: u64 = begin.history_row_base;
    const last = first + @as(u64, begin.history_count) + @as(u64, begin.rows) - 1;
    if (last > std.math.maxInt(i32)) return null;
    return .{ .first = @intCast(first), .last = @intCast(last) };
}

fn pointRetained(value: Point, columns: u16, bounds: RowBounds) bool {
    return value.column < columns and value.row >= bounds.first and value.row <= bounds.last;
}

fn viewportRow(begin: *const protocol.SnapshotBegin, viewport_row: u16) error{InvalidPoint}!i32 {
    if (viewport_row >= begin.rows) return error.InvalidPoint;
    if (begin.alternate_screen) return @intCast(viewport_row);
    if (begin.history_offset > begin.history_count) return error.InvalidPoint;
    const row = @as(u64, begin.history_row_base) + begin.history_count - begin.history_offset + viewport_row;
    if (row > std.math.maxInt(i32)) return error.InvalidPoint;
    return @intCast(row);
}

fn viewportPoint(
    begin: *const protocol.SnapshotBegin,
    viewport_row: u16,
    column: u16,
    continuation_x: u8,
    continuation_y: u8,
) error{InvalidPoint}!Point {
    if (column >= begin.columns or continuation_x > column) return error.InvalidPoint;
    const row = try viewportRow(begin, viewport_row);
    if (@as(i64, row) < continuation_y) return error.InvalidPoint;
    return .{
        .row = row - @as(i32, continuation_y),
        .column = column - continuation_x,
    };
}

fn pointBeforeOrEqual(left: Point, right: Point) bool {
    return left.row < right.row or left.row == right.row and left.column <= right.column;
}

test "viewport points retain stable row identity while history offset changes" {
    var begin = testBegin();
    try std.testing.expectEqual(Point{ .row = 104, .column = 7 }, try viewportPoint(&begin, 1, 7, 0, 0));
    begin.history_offset = 3;
    try std.testing.expectEqual(Point{ .row = 101, .column = 7 }, try viewportPoint(&begin, 1, 7, 0, 0));
    try std.testing.expectEqual(Point{ .row = 100, .column = 5 }, try viewportPoint(&begin, 1, 7, 2, 1));
}

test "selection survives scroll movement and exposes deterministic viewport spans" {
    var begin = testBegin();
    const range = Range{
        .anchor = .{ .row = 101, .column = 3 },
        .focus = .{ .row = 105, .column = 5 },
        .columns = begin.columns,
        .alternate_screen = false,
    };
    try std.testing.expectEqual(Validity.valid, range.validity(&begin));
    try std.testing.expectEqual(@as(?Span, .{ .start_column = 0, .end_column = 5 }), range.viewportSpan(&begin, 2));
    begin.history_offset = 3;
    try std.testing.expectEqual(@as(?Span, .{ .start_column = 3, .end_column = 7 }), range.viewportSpan(&begin, 1));
    try std.testing.expectEqual(@as(?Span, .{ .start_column = 0, .end_column = 7 }), range.viewportSpan(&begin, 2));
}

test "selection invalidates on eviction bank change or geometry change" {
    var begin = testBegin();
    var range = Range{
        .anchor = .{ .row = 100, .column = 0 },
        .focus = .{ .row = 102, .column = 2 },
        .columns = begin.columns,
        .alternate_screen = false,
    };
    try std.testing.expectEqual(Validity.valid, range.validity(&begin));
    begin.history_row_base = 101;
    try std.testing.expectEqual(Validity.evicted, range.validity(&begin));
    begin = testBegin();
    begin.columns += 1;
    try std.testing.expectEqual(Validity.context_changed, range.validity(&begin));
    begin = testBegin();
    begin.alternate_screen = true;
    try std.testing.expectEqual(Validity.context_changed, range.validity(&begin));

    range = .{
        .anchor = .{ .row = 2, .column = 2 },
        .focus = .{ .row = 0, .column = 1 },
        .columns = 8,
        .alternate_screen = true,
    };
    begin = testBegin();
    begin.alternate_screen = true;
    begin.history_count = 0;
    begin.history_offset = 0;
    try std.testing.expectEqual(Validity.valid, range.validity(&begin));
    const ordered = range.ordered();
    try std.testing.expectEqual(Point{ .row = 0, .column = 1 }, ordered.start);
    try std.testing.expectEqual(Point{ .row = 2, .column = 2 }, ordered.end);
}

fn testBegin() protocol.SnapshotBegin {
    return .{
        .revision = 10,
        .terminal_revision = 9,
        .history_offset = 0,
        .history_count = 3,
        .history_row_base = 100,
        .rows = 4,
        .columns = 8,
        .cursor_row = 0,
        .cursor_column = 0,
        .cursor_shape = 0,
        .cursor_visible = true,
        .cursor_blink = false,
        .alternate_screen = false,
        .stream_closed = false,
        .child_exited = false,
        .leader_present = false,
        .you_are_leader = false,
    };
}
