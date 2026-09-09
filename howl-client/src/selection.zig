//! Client-local terminal selection over stable canonical history/screen points.
//!
//! Selection ownership stays with the presentation client. The server owns only
//! canonical text extraction for an inclusive stable range. Viewport scrolling
//! therefore never mutates the selected range, while history eviction, screen-bank
//! switches, and geometry changes are detected explicitly.

const std = @import("std");
const protocol = @import("howl_session").protocol;
const client = @import("client.zig");
const rich = @import("rich.zig");
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

/// Expands one displayed nonblank terminal cell to the contiguous non-space word,
/// crossing only canonical soft-wrap boundaries. Returns null for blank/concealed cells.
pub fn word(snapshot: *const view.Snapshot, viewport_row: u16, column: u16) Error!?Range {
    const begin = view.begin(snapshot);
    if (viewport_row >= begin.rows or column >= begin.columns) return error.InvalidPoint;
    const start_pos = leadViewportPosition(snapshot, viewport_row, column) orelse return error.InvalidPoint;
    if (!selectableLead(snapshot, start_pos.row, start_pos.column)) return null;

    var first = start_pos;
    while (previousLead(snapshot, first.row, first.column)) |candidate| {
        if (!selectableLead(snapshot, candidate.row, candidate.column)) break;
        first = candidate;
    }

    var last = start_pos;
    while (nextLead(snapshot, last.row, last.column)) |candidate| {
        if (!selectableLead(snapshot, candidate.row, candidate.column)) break;
        last = candidate;
    }
    return .{
        .anchor = try point(snapshot, first.row, first.column),
        .focus = try point(snapshot, last.row, last.column),
        .columns = begin.columns,
        .alternate_screen = begin.alternate_screen,
    };
}

/// Returns the painted column span for one displayed row, expanding a selected
/// final lead cell across its complete horizontal terminal-cell width.
pub fn visualSpan(snapshot: *const view.Snapshot, range: Range, viewport_row: u16) ?Span {
    const span = range.viewportSpan(view.begin(snapshot), viewport_row) orelse return null;
    const ordered = range.ordered();
    const row_identity = viewportRow(view.begin(snapshot), viewport_row) catch return null;
    if (row_identity != ordered.end.row) return span;
    const row = view.rows(snapshot)[viewport_row];
    if (span.end_column >= row.cell_count) return span;
    const cell = view.cells(snapshot)[@as(usize, row.cell_offset) + span.end_column];
    if (cell.x != 0 or cell.y != 0) return span;
    const expanded = @min(
        @as(u32, range.columns - 1),
        @as(u32, span.end_column) + @as(u32, @max(cell.width, 1)) - 1,
    );
    return .{ .start_column = span.start_column, .end_column = @intCast(expanded) };
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

const ViewportPosition = struct { row: u16, column: u16 };

fn leadViewportPosition(snapshot: *const view.Snapshot, row_index: u16, column: u16) ?ViewportPosition {
    const row = view.rows(snapshot)[row_index];
    if (column >= row.cell_count) return null;
    const cell = view.cells(snapshot)[@as(usize, row.cell_offset) + column];
    if (cell.x > column or cell.y > row_index) return null;
    return .{ .row = row_index - cell.y, .column = column - cell.x };
}

fn selectableLead(snapshot: *const view.Snapshot, row_index: u16, column: u16) bool {
    const row = view.rows(snapshot)[row_index];
    if (column >= row.cell_count) return false;
    const cell = view.cells(snapshot)[@as(usize, row.cell_offset) + column];
    if (cell.x != 0 or cell.y != 0 or cell.scalar_count == 0 or
        cell.style_bits & protocol.text_v1.style.invisible != 0)
        return false;
    const first_scalar = view.scalars(snapshot)[cell.scalar_offset];
    return first_scalar != ' ';
}

fn previousLead(snapshot: *const view.Snapshot, row_index: u16, column: u16) ?ViewportPosition {
    if (column > 0) return leadViewportPosition(snapshot, row_index, column - 1);
    if (row_index == 0) return null;
    const previous_row = view.rows(snapshot)[row_index - 1];
    if (!previous_row.wrapped or previous_row.cell_count == 0) return null;
    return leadViewportPosition(snapshot, row_index - 1, @intCast(previous_row.cell_count - 1));
}

fn nextLead(snapshot: *const view.Snapshot, row_index: u16, column: u16) ?ViewportPosition {
    const rows = view.rows(snapshot);
    const row = rows[row_index];
    if (column >= row.cell_count) return null;
    const cell = view.cells(snapshot)[@as(usize, row.cell_offset) + column];
    const next_column = @as(u32, column) + @as(u32, @max(cell.width, 1));
    if (next_column < row.cell_count) return leadViewportPosition(snapshot, row_index, @intCast(next_column));
    if (!row.wrapped or row_index + 1 >= rows.len) return null;
    return leadViewportPosition(snapshot, row_index + 1, 0);
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

test "word selection crosses soft wrap and visual span covers a wide grapheme" {
    var cells0 = [_]rich.Cell{
        testCell(&.{'f'}, 1), testCell(&.{'o'}, 1), testCell(&.{'o'}, 1),
        testCell(&.{' '}, 1), testCell(&.{'b'}, 1), testCell(&.{'a'}, 1),
    };
    var cells1 = [_]rich.Cell{
        testCell(&.{'r'}, 1), testCell(&.{' '}, 1), testCell(&.{0x754c}, 2),
        testCell(&.{}, 2),    testCell(&.{'z'}, 1), testCell(&.{' '}, 1),
    };
    cells1[3].x = 1;
    var source_rows = [_]rich.Row{
        .{ .wrapped = true, .line_geometry = 0, .cells = &cells0 },
        .{ .wrapped = false, .line_geometry = 0, .cells = &cells1 },
    };
    const palette: [256]rich.Rgba = @splat(.{ .r = 0, .g = 0, .b = 0, .a = 0xff });
    const source = rich.Snapshot{
        .allocator = std.testing.allocator,
        .begin = testBeginForRows(2, 6),
        .presentation = testPresentation(palette),
        .rows = &source_rows,
        .hyperlinks = &.{},
    };
    const snapshot = try view.project(std.testing.allocator, &source);
    defer view.deinit(snapshot);

    const wrapped_word = (try word(snapshot, 1, 0)).?;
    const ordered_word = wrapped_word.ordered();
    try std.testing.expectEqual(Point{ .row = 0, .column = 4 }, ordered_word.start);
    try std.testing.expectEqual(Point{ .row = 1, .column = 0 }, ordered_word.end);
    try std.testing.expect((try word(snapshot, 0, 3)) == null);

    const wide = (try word(snapshot, 1, 2)).?;
    try std.testing.expectEqual(@as(?Span, .{ .start_column = 2, .end_column = 3 }), visualSpan(snapshot, wide, 1));
}

fn testCell(scalars: []const u32, width: u8) rich.Cell {
    return .{
        .scalars = scalars,
        .width = width,
        .height = 1,
        .x = 0,
        .y = 0,
        .subscale_n = 1,
        .subscale_d = 1,
        .vertical_align = 0,
        .horizontal_align = 0,
        .semantic_width = false,
        .font = 0,
        .baseline = 0,
        .underline_style = 0,
        .protection = 0,
        .style_bits = 0,
        .foreground = .{ .kind = .default, .value = 0 },
        .background = .{ .kind = .default, .value = 0 },
        .underline_color = .{ .kind = .default, .value = 0 },
        .link_id = 0,
    };
}

fn testBeginForRows(rows: u16, columns: u16) protocol.SnapshotBegin {
    var value = testBegin();
    value.history_count = 0;
    value.history_row_base = 0;
    value.rows = rows;
    value.columns = columns;
    return value;
}

fn testPresentation(palette: [256]rich.Rgba) rich.Presentation {
    return .{
        .cursor_age_ns = 0,
        .presence_bits = 0,
        .flags = 0,
        .reverse_screen = false,
        .palette = palette,
        .foreground = .{ .r = 0xee, .g = 0xee, .b = 0xee, .a = 0xff },
        .background = .{ .r = 0, .g = 0, .b = 0, .a = 0xff },
        .cursor = null,
        .cursor_text = null,
        .selection_background = null,
        .selection_foreground = null,
    };
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
