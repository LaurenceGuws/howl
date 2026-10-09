const std = @import("std");
const instance = @import("howl_instance");
const vt = instance.Terminal;
const limits = instance.render.limits;

/// Copied geometry/retention facts naming one canonical text domain.
pub const Context = struct {
    rows: u16,
    columns: u16,
    history_count: u32,
    history_row_base: u32,
    history_offset: u32,
    alternate: bool,

    /// Copies the current borrowed view's naming context without retaining its backing owner.
    pub fn fromView(view: vt.SemanticView) Context {
        return .{ .rows = view.rows, .columns = view.cols, .history_count = view.history_count, .history_row_base = view.history_row_base, .history_offset = view.history_offset, .alternate = view.is_alternate_screen };
    }
    /// Resolves one accepted immutable frame's lattice and history identity.
    pub fn fromFrame(frame: instance.PublishedFrame) error{InvalidSelection}!Context {
        if (frame.cell_size.width == 0 or frame.cell_size.height == 0) return error.InvalidSelection;
        const rows = frame.surface.height / frame.cell_size.height;
        const columns = frame.surface.width / frame.cell_size.width;
        if (rows == 0 or columns == 0 or rows > limits.maximum_rows or columns > limits.maximum_columns or frame.history_offset > frame.history_count) return error.InvalidSelection;
        return .{ .rows = @intCast(rows), .columns = @intCast(columns), .history_count = frame.history_count, .history_row_base = frame.history_row_base, .history_offset = frame.history_offset, .alternate = frame.alternate_screen };
    }
    /// Maps one displayed row to stable canonical identity with checked signed-coordinate bounds.
    pub fn row(self: Context, viewport: u16) error{InvalidSelection}!i32 {
        if (viewport >= self.rows or self.history_offset > self.history_count) return error.InvalidSelection;
        const absolute = if (self.alternate) @as(u64, viewport) else @as(u64, self.history_row_base) + self.history_count - self.history_offset + viewport;
        if (absolute > std.math.maxInt(i32)) return error.InvalidSelection;
        return @intCast(absolute);
    }
    fn retained(self: Context, value: vt.TextPoint) bool {
        const first: i64 = if (self.alternate) 0 else self.history_row_base;
        const end: i64 = first + (if (self.alternate) @as(i64, 0) else self.history_count) + self.rows;
        return value.col < self.columns and value.row >= first and value.row < end;
    }
};

/// Stable range validity never depends on a viewport scroll or ordinary new output.
pub const Validity = enum { valid, context_changed, evicted };
/// Inclusive columns painted from the same canonical cut as the leased frame.
pub const Span = struct { first: u16, last: u16 };
/// One immutable publication's copied selection overlay; contains no row or terminal borrow.
pub const Paint = struct {
    serial: u64 = 0,
    rows: u16 = 0,
    spans: [limits.maximum_rows]?Span = @splat(null),
};
/// Inclusive stable endpoints plus the column/bank context that gives them meaning.
pub const Range = struct {
    anchor: vt.TextPoint,
    focus: vt.TextPoint,
    columns: u16,
    alternate: bool,

    /// Eviction, reflow or screen-bank changes invalidate explicitly; vertical growth and scrolling do not.
    pub fn validity(self: Range, context: Context) Validity {
        if (self.columns != context.columns or self.alternate != context.alternate) return .context_changed;
        if (!context.retained(self.anchor) or !context.retained(self.focus)) return .evicted;
        return .valid;
    }
    /// Orders inclusive extraction endpoints while preserving the drag's anchor identity.
    pub fn ordered(self: Range) vt.TextRange {
        if (self.anchor.row < self.focus.row or (self.anchor.row == self.focus.row and self.anchor.col <= self.focus.col))
            return .{ .start = self.anchor, .end = self.focus };
        return .{ .start = self.focus, .end = self.anchor };
    }
    /// Copies canonical text only after validating the current retained domain.
    pub fn copy(self: Range, observation: *const vt.Observation, allocator: std.mem.Allocator, max_bytes: usize) ![]const u8 {
        switch (self.validity(Context.fromView(observation.semanticView(0)))) {
            .valid => {},
            .context_changed => return error.SelectionContextChanged,
            .evicted => return error.SelectionEvicted,
        }
        return observation.copyText(allocator, self.ordered(), max_bytes);
    }
    /// Paints text-shaped spans, including a hard newline cell and the complete final wide glyph.
    pub fn paint(self: Range, view: vt.SemanticView, serial: u64) !Paint {
        var result: Paint = .{ .serial = serial, .rows = view.rows };
        if (view.rows > result.spans.len) return error.InvalidSelection;
        const context = Context.fromView(view);
        if (self.validity(context) != .valid) return result;
        const range = self.ordered();
        for (0..view.rows) |index| {
            const row_index: u16 = @intCast(index);
            const absolute = try context.row(row_index);
            if (absolute < range.start.row or absolute > range.end.row) continue;
            const first = if (absolute == range.start.row) range.start.col else 0;
            var last = if (absolute == range.end.row) range.end.col else view.cols - 1;
            if (absolute == range.end.row) {
                const cell = view.cellInfoAt(row_index, last);
                if (cell.x == 0 and cell.y == 0) last = @intCast(@min(@as(u32, view.cols - 1), @as(u32, last) + @max(cell.width, 1) - 1));
            }
            const content_end = rowContentEnd(view, row_index);
            if (absolute == range.end.row or view.rowWrapped(row_index)) {
                if (content_end == 0) continue;
                last = @min(last, content_end - 1);
                if (last < first) continue;
                result.spans[index] = .{ .first = first, .last = last };
            } else {
                const newline = @min(content_end, view.cols - 1);
                result.spans[index] = .{ .first = @min(first, newline), .last = newline };
            }
        }
        return result;
    }
};
/// Resolves one visible cell or continuation to stable canonical lead identity.
pub fn point(view: vt.SemanticView, row_index: u16, column: u16) error{InvalidSelection}!vt.TextPoint {
    if (row_index >= view.rows or column >= view.cols) return error.InvalidSelection;
    const context = Context.fromView(view);
    const cell = view.cellInfoAt(row_index, column);
    const absolute = try context.row(row_index);
    if (cell.x > column or @as(i64, absolute) < cell.y) return error.InvalidSelection;
    const value: vt.TextPoint = .{ .row = absolute - cell.y, .col = column - cell.x };
    if (!context.retained(value)) return error.InvalidSelection;
    return value;
}
/// Starts a collapsed range from the exact canonical lead cell.
pub fn start(view: vt.SemanticView, row_index: u16, column: u16) !Range {
    const value = try point(view, row_index, column);
    return .{ .anchor = value, .focus = value, .columns = view.cols, .alternate = view.is_alternate_screen };
}
/// Selects one projected visual row's text, deliberately without inventing logical-line search.
pub fn visualRow(view: vt.SemanticView, row_index: u16) !?Range {
    if (row_index >= view.rows or view.cols == 0) return error.InvalidSelection;
    const end = rowContentEnd(view, row_index);
    if (end == 0) return null;
    var first: u16 = 0;
    while (first < end) : (first += 1) {
        const cell = view.cellInfoAt(row_index, first);
        if (cell.x == 0 and cell.y == 0) break;
    }
    if (first == end) return null;
    var result = try start(view, row_index, first);
    result.focus = try point(view, row_index, end - 1);
    return result;
}
const Position = struct { row: u16, col: u16 };
fn lead(view: vt.SemanticView, position: Position) ?Position {
    if (position.row >= view.rows or position.col >= view.cols) return null;
    const cell = view.cellInfoAt(position.row, position.col);
    if (cell.x > position.col or cell.y > position.row) return null;
    return .{ .row = position.row - cell.y, .col = position.col - cell.x };
}
fn selectable(view: vt.SemanticView, position: Position) bool {
    const cell = view.cellInfoAt(position.row, position.col);
    return cell.x == 0 and cell.y == 0 and cell.codepoint != 0 and cell.codepoint != ' ' and !cell.attrs.invisible;
}
fn previous(view: vt.SemanticView, position: Position) ?Position {
    if (position.col != 0) return lead(view, .{ .row = position.row, .col = position.col - 1 });
    if (position.row == 0 or !view.rowWrapped(position.row - 1)) return null;
    return lead(view, .{ .row = position.row - 1, .col = view.cols - 1 });
}
fn next(view: vt.SemanticView, position: Position) ?Position {
    const cell = view.cellInfoAt(position.row, position.col);
    const column = @as(u32, position.col) + @max(cell.width, 1);
    if (column < view.cols) return lead(view, .{ .row = position.row, .col = @intCast(column) });
    if (!view.rowWrapped(position.row) or position.row + 1 >= view.rows) return null;
    return lead(view, .{ .row = position.row + 1, .col = 0 });
}
/// Expands a non-space word across canonical soft wraps within the projected viewport.
pub fn word(view: vt.SemanticView, row_index: u16, column: u16) !?Range {
    if (view.rows > limits.maximum_rows or view.cols > limits.maximum_columns) return error.InvalidSelection;
    const initial = lead(view, .{ .row = row_index, .col = column }) orelse return error.InvalidSelection;
    if (!selectable(view, initial)) return null;
    var first = initial;
    while (previous(view, first)) |position| {
        if (position.row > first.row or (position.row == first.row and position.col >= first.col) or !selectable(view, position)) break;
        first = position;
    }
    var last = initial;
    while (next(view, last)) |position| {
        if (position.row < last.row or (position.row == last.row and position.col <= last.col) or !selectable(view, position)) break;
        last = position;
    }
    var result = try start(view, first.row, first.col);
    result.focus = try point(view, last.row, last.col);
    return result;
}
fn rowContentEnd(view: vt.SemanticView, row_index: u16) u16 {
    var column = view.cols;
    while (column != 0) {
        column -= 1;
        const cell = view.cellInfoAt(row_index, column);
        if (cell.x != 0 or cell.y != 0 or cell.codepoint == 0 or cell.codepoint == ' ') continue;
        return @intCast(@min(@as(u32, view.cols), @as(u32, column) + @max(cell.width, 1)));
    }
    return 0;
}

test "stable selection survives viewport movement and vertical growth but rejects eviction reflow and bank changes" {
    var context: Context = .{ .rows = 20, .columns = 80, .history_count = 100, .history_row_base = 50, .history_offset = 20, .alternate = false };
    const selected: Range = .{ .anchor = .{ .row = 70, .col = 3 }, .focus = .{ .row = 95, .col = 7 }, .columns = 80, .alternate = false };
    try std.testing.expectEqual(@as(i32, 134), try context.row(4));
    try std.testing.expectEqual(Validity.valid, selected.validity(context));
    context.history_offset = 0;
    context.rows = 32;
    context.history_count = 120;
    try std.testing.expectEqual(Validity.valid, selected.validity(context));
    context.history_row_base = 71;
    try std.testing.expectEqual(Validity.evicted, selected.validity(context));
    context.history_row_base = 50;
    context.columns = 79;
    try std.testing.expectEqual(Validity.context_changed, selected.validity(context));
    context.columns = 80;
    context.alternate = true;
    try std.testing.expectEqual(Validity.context_changed, selected.validity(context));
    context.history_row_base = std.math.maxInt(u32);
    context.history_count = std.math.maxInt(u32);
    context.alternate = false;
    try std.testing.expectError(error.InvalidSelection, context.row(0));
}
test "canonical word and visual-row selection preserve graphemes soft wraps and text-shaped painting" {
    var terminal = try vt.init(std.testing.allocator, 4, 6);
    defer terminal.deinit();
    // zig-audit: acknowledge discard
    // reason: The selection proof asserts the resulting canonical view and copied UTF-8; parser progress counters carry no authority for these checks.
    _ = try terminal.feed("foo bar \xe7\x95\x8cz");
    const view = terminal.semanticView(0);
    const selected = (try word(view, 1, 0)).?;
    const text = try selected.copy(terminal.observation(), std.testing.allocator, 128);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("bar", text);
    const wide = try start(view, 1, 3);
    const paint = try wide.paint(view, 7);
    try std.testing.expectEqual(@as(?Span, .{ .first = 2, .last = 3 }), paint.spans[1]);
    try std.testing.expectEqual(@as(u64, 7), paint.serial);
    const line = (try visualRow(view, 1)).?;
    const line_text = try line.copy(terminal.observation(), std.testing.allocator, 128);
    defer std.testing.allocator.free(line_text);
    try std.testing.expectEqualStrings("r \xe7\x95\x8cz", line_text);
    try std.testing.expect((try word(view, 0, 3)) == null);
    try std.testing.expect((try visualRow(view, 3)) == null);
}
