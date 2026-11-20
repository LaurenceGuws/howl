const std = @import("std");
const vt_selection = @import("howl_vt").selection;
const vt = @import("howl_vt").Terminal;
const limits = @import("howl_vt_output_limits");

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
    pub fn fromFrame(frame: @import("frame_info.zig").Info) error{InvalidSelection}!Context {
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
    bits: [limits.maximum_rows][(limits.maximum_columns + 63) / 64]u64 = @splat(@splat(0)),

    /// Adds an inclusive selected run to this immutable-frame overlay.
    pub fn add(self: *Paint, row: u16, first: u16, last: u16) void {
        std.debug.assert(row < limits.maximum_rows and first <= last and last < limits.maximum_columns);
        var col = first;
        while (col <= last) : (col += 1) self.bits[row][col / 64] |= @as(u64, 1) << @as(u6, @intCast(col % 64));
    }
    /// Reports whether a cell belongs to this selected overlay.
    pub fn contains(self: *const Paint, row: usize, col: usize) bool {
        if (row >= self.rows or col >= limits.maximum_columns) return false;
        return self.bits[row][col / 64] & (@as(u64, 1) << @as(u6, @intCast(col % 64))) != 0;
    }
    /// Returns the row bounding span for simple consumers and tests.
    pub fn spanAt(self: *const Paint, row: usize) ?Span {
        var first: ?u16 = null;
        var last: u16 = 0;
        for (0..limits.maximum_columns) |col| if (self.contains(row, col)) {
            if (first == null) first = @intCast(col);
            last = @intCast(col);
        };
        return if (first) |f| .{ .first = f, .last = last } else null;
    }
};
/// Inclusive stable endpoints plus the column/bank context that gives them meaning.
pub const Range = struct {
    anchor: vt.TextPoint,
    focus: vt.TextPoint,
    columns: u16,
    alternate: bool,
    empty: bool = false,
    /// Whole-unit drags retain the initial span even when the pointer reverses direction.
    unit: union(enum) { cell, word: vt.TextRange, row: vt.TextRange } = .cell,

    /// Eviction, reflow or screen-bank changes invalidate explicitly; vertical growth and scrolling do not.
    pub fn validity(self: Range, context: Context) Validity {
        if (self.columns != context.columns or self.alternate != context.alternate) return .context_changed;
        if (!context.retained(self.anchor) or !context.retained(self.focus)) return .evicted;
        switch (self.unit) {
            .cell => {},
            .word, .row => |origin| if (!context.retained(origin.start) or !context.retained(origin.end)) return .evicted,
        }
        return .valid;
    }
    /// Reports whether canonical rows under the selected absolute range were
    /// rewritten since a VT row-generation witness was captured. Stable
    /// history identities allow selections to survive unrelated writes and
    /// scrolls without keeping a second edit or row-damage ledger.
    pub fn rowsModifiedSince(self: Range, observation: *const vt.Observation, floor: u64) bool {
        if (self.empty) return false;
        const live = observation.semanticView(0);
        if (self.validity(Context.fromView(live)) != .valid) return true;
        if (observation.rowMutationFloor() < floor) return true;
        const selected = self.ordered();
        const live_start: i64 = if (live.is_alternate_screen)
            0
        else
            @as(i64, live.history_row_base) + live.history_count;
        var row: i64 = selected.start.row;
        while (row <= selected.end.row) {
            const offset: u32 = if (row >= live_start)
                0
            else
                @intCast(live_start - row);
            const view = observation.semanticView(offset);
            const first: i64 = if (view.is_alternate_screen)
                0
            else
                @as(i64, view.history_row_base) + view.history_count - view.history_offset;
            if (row < first or row >= first + view.rows) return true;
            const remaining = @min(selected.end.row - row + 1, first + view.rows - row);
            const start_row: u16 = @intCast(row - first);
            const count: u16 = @intCast(remaining);
            for (0..count) |index| {
                const generation = view.rowGeneration(start_row + @as(u16, @intCast(index))) orelse return true;
                if (generation >= floor) return true;
            }
            row += remaining;
        }
        return false;
    }
    /// Orders inclusive extraction endpoints while preserving the drag's anchor identity.
    pub fn ordered(self: Range) vt.TextRange {
        if (self.anchor.row < self.focus.row or (self.anchor.row == self.focus.row and self.anchor.col <= self.focus.col))
            return .{ .start = self.anchor, .end = self.focus };
        return .{ .start = self.focus, .end = self.anchor };
    }
    /// Extends a retained range; entering actual text activates an initially empty padding anchor.
    pub fn extend(self: *Range, view: vt.SemanticView, row_index: u16, column: u16) error{InvalidSelection}!void {
        const origin: ?vt.TextRange = switch (self.unit) {
            .cell => null,
            .word, .row => |value| value,
        };
        if (origin) |initial| {
            const target = switch (self.unit) {
                .word => try word(view, row_index, column),
                .row => try visualRow(view, row_index),
                .cell => return error.InvalidSelection,
            };
            const edge = if (target) |range| range.ordered() else blk: {
                const value = try dragPoint(view, row_index, column);
                break :blk vt.TextRange{ .start = value, .end = value };
            };
            if (after(initial.start, edge.start)) {
                self.anchor = initial.end;
                self.focus = edge.start;
            } else {
                self.anchor = initial.start;
                self.focus = if (after(edge.end, initial.end)) edge.end else initial.end;
            }
            return;
        }
        self.focus = try dragPoint(view, row_index, column);
        const raw = try point(view, row_index, column);
        if (!std.meta.eql(self.anchor, self.focus) or
            (std.meta.eql(raw, self.focus) and (try textEnd(view)) != null)) self.empty = false;
    }
    /// Copies canonical text only after validating the current retained domain.
    pub fn copy(self: Range, observation: *const vt.Observation, allocator: std.mem.Allocator, max_bytes: usize) ![]const u8 {
        if (self.empty) return error.NoSelection;
        switch (self.validity(Context.fromView(observation.semanticView(0)))) {
            .valid => {},
            .context_changed => return error.SelectionContextChanged,
            .evicted => return error.SelectionEvicted,
        }
        var range = self.ordered();
        const live = observation.semanticView(0);
        if (!live.is_alternate_screen) {
            const first = try Context.fromView(live).row(0);
            const end = try textEnd(live);
            if (end != null and end.?.row >= first) {
                if (after(range.end, end.?)) range.end = end.?;
            } else if (range.end.row >= first) {
                // A live continuation can point behind newer retained history.
                // A range wholly in history needs no frontier scan.
                if (range.start.row >= first) return &.{};
                const history_end = vt_selection.historyTextEnd(observation) orelse return &.{};
                if (after(range.end, history_end)) range.end = history_end;
            }
            if (after(range.start, range.end)) return &.{};
        }
        return observation.copyText(allocator, range, max_bytes);
    }
    /// Paints text-shaped spans, including a hard newline cell and the complete final wide glyph.
    pub fn paint(self: Range, view: vt.SemanticView, serial: u64) !Paint {
        var result: Paint = .{ .serial = serial, .rows = view.rows };
        if (self.empty) return result;
        if (view.rows > limits.maximum_rows or view.cols > limits.maximum_columns) return error.InvalidSelection;
        const context = Context.fromView(view);
        if (self.validity(context) != .valid) return result;
        var range = self.ordered();
        const end = if (!view.is_alternate_screen and view.history_offset == 0) (try textEnd(view)) else null;
        if (!view.is_alternate_screen and view.history_offset == 0 and end == null) return result;
        if (end) |last| {
            if (after(range.end, last)) range.end = last;
            if (after(range.start, range.end)) return result;
        }
        var row_storage: [limits.maximum_columns]vt_selection.Span = undefined;
        for (0..view.rows) |index| {
            const row_index: u16 = @intCast(index);
            const absolute = try context.row(row_index);
            const spans = try vt_selection.visibleRowSpans(&view, range, row_index, &row_storage);
            var max_col: u16 = view.cols - 1;
            if (absolute <= range.end.row and (absolute == range.end.row or view.rowWrapped(row_index))) {
                const content_end = rowContentEnd(view, row_index);
                if (content_end == 0) continue;
                max_col = content_end - 1;
            } else if (absolute < range.end.row and !view.rowWrapped(row_index)) {
                max_col = @min(rowContentEnd(view, row_index), view.cols - 1);
            }
            for (spans) |span| {
                const last = @min(span.column + span.columns - 1, max_col);
                if (span.column <= last) result.add(row_index, span.column, last);
            }
        }
        return result;
    }
};
fn after(a: vt.TextPoint, b: vt.TextPoint) bool {
    return a.row > b.row or (a.row == b.row and a.col > b.col);
}
/// Last actual glyph in this projected view, independent of the cursor position.
pub fn textEnd(view: vt.SemanticView) error{InvalidSelection}!?vt.TextPoint {
    if (view.rows > limits.maximum_rows or view.cols > limits.maximum_columns) return error.InvalidSelection;
    return vt_selection.textEnd(&view);
}

/// A drag into unused live rows stops at the last actual glyph.
pub fn dragPoint(view: vt.SemanticView, row_index: u16, column: u16) error{InvalidSelection}!vt.TextPoint {
    const value = try point(view, row_index, column);
    if (!view.is_alternate_screen and view.history_offset == 0) {
        if (try textEnd(view)) |end| if (after(value, end)) return end;
    }
    return value;
}
/// Resolves one visible cell or continuation to stable canonical lead identity.
pub fn point(view: vt.SemanticView, row_index: u16, column: u16) error{InvalidSelection}!vt.TextPoint {
    return vt_selection.point(&view, row_index, column) orelse error.InvalidSelection;
}
/// Starts at canonical text, retaining an empty end anchor when the pointer is in live padding.
pub fn start(view: vt.SemanticView, row_index: u16, column: u16) !Range {
    const raw = try point(view, row_index, column);
    const value = try dragPoint(view, row_index, column);
    const empty = !view.is_alternate_screen and view.history_offset == 0 and
        ((try textEnd(view)) == null or !std.meta.eql(raw, value));
    return .{ .anchor = value, .focus = value, .columns = view.cols, .alternate = view.is_alternate_screen, .empty = empty };
}
/// Selects one projected visual row's text, deliberately without inventing logical-line search.
pub fn visualRow(view: vt.SemanticView, row_index: u16) !?Range {
    if (row_index >= view.rows or view.cols == 0) return error.InvalidSelection;
    const text = vt_selection.visualRowRange(&view, row_index) orelse return null;
    return .{ .anchor = text.start, .focus = text.end, .columns = view.cols, .alternate = view.is_alternate_screen, .unit = .{ .row = text } };
}
/// Expands a non-space word using VT's canonical text semantics.
pub fn word(view: vt.SemanticView, row_index: u16, column: u16) !?Range {
    if (view.rows > limits.maximum_rows or view.cols > limits.maximum_columns or row_index >= view.rows or column >= view.cols) return error.InvalidSelection;
    const text = vt_selection.wordRange(&view, row_index, column) orelse return null;
    return .{ .anchor = text.start, .focus = text.end, .columns = view.cols, .alternate = view.is_alternate_screen, .unit = .{ .word = text } };
}
fn rowContentEnd(view: vt.SemanticView, row_index: u16) u16 {
    const last = vt_selection.lastContentColumn(&view, row_index) orelse return 0;
    return last + 1;
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

test "selected row mutation witness survives history admission but detects rewrite and eviction" {
    var terminal = try vt.initWithHistory(std.testing.allocator, 3, 8, 4);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("alpha\x1b[2;1Hbravo\x1b[3;1Hcharlie")).stateChanged());
    const selected = (try word(terminal.semanticView(0), 0, 2)).?;
    const baseline = terminal.observation().rowMutationFloor();
    try std.testing.expect(!selected.rowsModifiedSince(terminal.observation(), baseline));

    // A different row's rewrite does not invalidate the selected one.
    try std.testing.expect((try terminal.feed("\x1b[2;1H\x1b[2K")).stateChanged());
    try std.testing.expect(!selected.rowsModifiedSince(terminal.observation(), baseline));

    // Full-screen scrolling preserves the selected row's absolute identity
    // and its immutable generation when it moves into retained history.
    try std.testing.expect((try terminal.feed("\x1b[3;1H\n")).stateChanged());
    try std.testing.expectEqual(@as(u32, 1), terminal.semanticView(0).history_count);
    try std.testing.expect(!selected.rowsModifiedSince(terminal.observation(), baseline));

    // Mutation of another live row is still unrelated after that move.
    try std.testing.expect((try terminal.feed("\x1b[2;1HZ")).stateChanged());
    try std.testing.expect(!selected.rowsModifiedSince(terminal.observation(), baseline));

    // Eventually evicting the selected history row must fail closed.
    for (0..5) |_| try std.testing.expect((try terminal.feed("\x1b[3;1H\n")).stateChanged());
    try std.testing.expect(selected.rowsModifiedSince(terminal.observation(), baseline));
}

test "selected span detects edits to middle row and keeps historical projections aligned" {
    var terminal = try vt.initWithHistory(std.testing.allocator, 4, 8, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("top\x1b[2;1Hmid\x1b[3;1Htail")).stateChanged());
    const view = terminal.semanticView(0);
    const first = try point(view, 0, 0);
    const last = try point(view, 2, 2);
    const range: Range = .{
        .anchor = first,
        .focus = last,
        .columns = view.cols,
        .alternate = view.is_alternate_screen,
    };
    const baseline = terminal.observation().rowMutationFloor();
    try std.testing.expect(!range.rowsModifiedSince(terminal.observation(), baseline));
    try std.testing.expect((try terminal.feed("\x1b[4;1Hfar")).stateChanged());
    try std.testing.expect(!range.rowsModifiedSince(terminal.observation(), baseline));
    try std.testing.expect((try terminal.feed("\x1b[2;1H\x1b[2K")).stateChanged());
    try std.testing.expect(range.rowsModifiedSince(terminal.observation(), baseline));
}

test "selected row rewritten then archived in one feed still invalidates" {
    var terminal = try vt.initWithHistory(std.testing.allocator, 3, 8, 4);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("alpha\x1b[2;1Hbeta\x1b[3;1Hgamma")).stateChanged());
    const selected = (try word(terminal.semanticView(0), 0, 2)).?;
    const baseline = terminal.observation().rowMutationFloor();
    try std.testing.expect((try terminal.feed("\x1b[1;1HZ\x1b[3;1H\n")).stateChanged());
    try std.testing.expectEqual(@as(u32, 1), terminal.semanticView(0).history_count);
    try std.testing.expect(selected.rowsModifiedSince(terminal.observation(), baseline));
    try std.testing.expect(selected.rowsModifiedSince(terminal.observation(), std.math.maxInt(u64)));
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
    try std.testing.expectEqual(@as(?Span, .{ .first = 2, .last = 3 }), paint.spanAt(1));
    try std.testing.expectEqual(@as(u64, 7), paint.serial);
    const line = (try visualRow(view, 1)).?;
    const line_text = try line.copy(terminal.observation(), std.testing.allocator, 128);
    defer std.testing.allocator.free(line_text);
    try std.testing.expectEqualStrings("r \xe7\x95\x8cz", line_text);
    try std.testing.expect((try word(view, 0, 3)) == null);
    try std.testing.expect((try visualRow(view, 3)) == null);
}

test "prompt selection excludes unused live padding but retains interior blank rows and wide glyphs" {
    var terminal = try vt.init(std.testing.allocator, 6, 20);
    defer terminal.deinit();
    // zig-audit: acknowledge discard
    // reason: This selection proof checks canonical text and overlay spans instead of parser progress counters.
    _ = try terminal.feed("first\r\n\r\nwide: 界\r\nprompt> ");
    const view = terminal.semanticView(0);
    try std.testing.expect((try start(view, 5, 0)).empty);
    try std.testing.expect((try start(view, 3, 19)).empty);
    try std.testing.expect(!(try start(view, 1, 0)).empty);
    var selected = try start(view, 0, 0);
    selected.focus = try point(view, 5, 19);
    const text = try selected.copy(terminal.observation(), std.testing.allocator, 128);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("first\n\nwide: 界\nprompt>", text);
    const paint = try selected.paint(view, 1);
    try std.testing.expect(paint.spanAt(1) != null);
    try std.testing.expect(paint.spanAt(4) == null and paint.spanAt(5) == null);
    try std.testing.expectEqual(try textEnd(view), try dragPoint(view, 5, 19));
    // A prompt cursor at the top does not hide real text farther down.
    // zig-audit: acknowledge discard
    // reason: The assertions inspect content after cursor-only movement, not parser counters.
    _ = try terminal.feed("\x1b[H");
    try std.testing.expect(!(try start(terminal.semanticView(0), 3, 0)).empty);
}

test "a drag beginning below or right of the prompt selects backwards without a whitespace tail" {
    var terminal = try vt.init(std.testing.allocator, 6, 20);
    defer terminal.deinit();
    // zig-audit: acknowledge discard
    // reason: This test asserts selection endpoints, exact copied text and spans instead of feed counters.
    _ = try terminal.feed("first\r\n\r\nprompt> ");
    const view = terminal.semanticView(0);
    const TestPosition = struct { row: u16, col: u16 };
    for ([_]TestPosition{ .{ .row = 5, .col = 19 }, .{ .row = 2, .col = 19 } }) |origin| {
        var selected = try start(view, origin.row, origin.col);
        try std.testing.expect(selected.empty);
        try std.testing.expectError(error.NoSelection, selected.copy(terminal.observation(), std.testing.allocator, 128));
        const empty_paint = try selected.paint(view, 1);
        try std.testing.expect(empty_paint.spanAt(2) == null and empty_paint.spanAt(5) == null);
        try selected.extend(view, 0, 0);
        const copied = try selected.copy(terminal.observation(), std.testing.allocator, 128);
        defer std.testing.allocator.free(copied);
        try std.testing.expectEqualStrings("first\n\nprompt>", copied);
        selected = try start(view, origin.row, origin.col);
        try selected.extend(view, 2, 6);
        const last = try selected.copy(terminal.observation(), std.testing.allocator, 8);
        defer std.testing.allocator.free(last);
        try std.testing.expectEqualStrings(">", last);
    }
}

test "word drag retains its original word and expands whole words in either direction" {
    var terminal = try vt.init(std.testing.allocator, 4, 20);
    defer terminal.deinit();
    // zig-audit: acknowledge discard
    // reason: selection assertions consume the canonical text produced by this feed.
    _ = try terminal.feed("one two three");
    const view = terminal.semanticView(0);
    var selected = (try word(view, 0, 5)).?;
    const cases = .{
        .{ @as(u16, 5), "two" },
        .{ @as(u16, 10), "two three" },
        .{ @as(u16, 1), "one two" },
        .{ @as(u16, 6), "two" },
        .{ @as(u16, 3), " two" },
    };
    inline for (cases) |case| {
        try selected.extend(view, 0, case[0]);
        const text = try selected.copy(terminal.observation(), std.testing.allocator, 128);
        defer std.testing.allocator.free(text);
        try std.testing.expectEqualStrings(case[1], text);
    }
}

test "row drag retains the starting row on release and reversal" {
    var terminal = try vt.init(std.testing.allocator, 4, 20);
    defer terminal.deinit();
    // zig-audit: acknowledge discard
    // reason: selection assertions consume the canonical text produced by this feed.
    _ = try terminal.feed("one\r\ntwo\r\nthree");
    const view = terminal.semanticView(0);
    var selected = (try visualRow(view, 1)).?;
    const cases = .{
        .{ @as(u16, 1), "two" },
        .{ @as(u16, 2), "two\nthree" },
        .{ @as(u16, 0), "one\ntwo" },
        .{ @as(u16, 1), "two" },
    };
    inline for (cases) |case| {
        try selected.extend(view, case[0], 1);
        const text = try selected.copy(terminal.observation(), std.testing.allocator, 128);
        defer std.testing.allocator.free(text);
        try std.testing.expectEqualStrings(case[1], text);
    }
}

test "word drag keeps softwrapped wide glyphs whole" {
    var terminal = try vt.init(std.testing.allocator, 4, 6);
    defer terminal.deinit();
    // zig-audit: acknowledge discard
    // reason: selection assertions consume the canonical text produced by this feed.
    _ = try terminal.feed("foo bar 界z");
    const view = terminal.semanticView(0);
    var selected = (try word(view, 0, 4)).?;
    try selected.extend(view, 1, 3);
    const text = try selected.copy(terminal.observation(), std.testing.allocator, 128);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("bar 界z", text);
}

test "selection starts and paints on a visible fragment whose lead is in history" {
    var terminal = try vt.initWithHistory(std.testing.allocator, 3, 8, 4);
    defer terminal.deinit();
    // zig-audit: acknowledge discard
    // reason: The assertions inspect canonical selection after parsed input.
    _ = try terminal.feed("\x1b]66;s=2;X\x07\x1b[S");
    const view = terminal.semanticView(0);
    const selected = try start(view, 0, 1);
    try std.testing.expect(!selected.empty);
    const copied = try selected.copy(terminal.observation(), std.testing.allocator, 16);
    defer std.testing.allocator.free(copied);
    try std.testing.expectEqualStrings("X", copied);
    const word_selected = (try word(view, 0, 1)).?;
    const word_copy = try word_selected.copy(terminal.observation(), std.testing.allocator, 16);
    defer std.testing.allocator.free(word_copy);
    try std.testing.expectEqualStrings("X", word_copy);
    const row_selected = (try visualRow(view, 0)).?;
    const row_copy = try row_selected.copy(terminal.observation(), std.testing.allocator, 16);
    defer std.testing.allocator.free(row_copy);
    try std.testing.expectEqualStrings("X", row_copy);
    const paint = try selected.paint(view, 1);
    try std.testing.expectEqual(@as(?Span, .{ .first = 0, .last = 1 }), paint.spanAt(0));
}

test "selection overlay excludes unselected tall block crossing a selected row" {
    var terminal = try vt.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    // zig-audit: acknowledge discard
    // reason: The assertions inspect the selected overlay after parsed input.
    _ = try terminal.feed("\x1b[1;4H\x1b]66;s=2:w=1;X\x07\x1b[3;8HZ");
    const view = terminal.semanticView(0);
    const selected: Range = .{ .anchor = .{ .row = 0, .col = 5 }, .focus = .{ .row = 2, .col = 7 }, .columns = 8, .alternate = false };
    const paint = try selected.paint(view, 1);
    try std.testing.expect(paint.contains(1, 0) and paint.contains(1, 2));
    try std.testing.expect(!paint.contains(1, 3) and !paint.contains(1, 4));
    try std.testing.expect(paint.contains(1, 5));
}

test "tall continuation does not hide later text on its lead row" {
    var terminal = try vt.initWithHistory(std.testing.allocator, 3, 8, 4);
    defer terminal.deinit();
    // zig-audit: acknowledge discard
    // reason: The assertions inspect canonical selection after parsed input.
    _ = try terminal.feed("\x1b]66;s=2;X\x07\x1b[1;8HZ");
    const view = terminal.semanticView(0);
    const selected = try start(view, 0, 7);
    try std.testing.expect(!selected.empty);
    const copied = try selected.copy(terminal.observation(), std.testing.allocator, 16);
    defer std.testing.allocator.free(copied);
    try std.testing.expectEqualStrings("Z", copied);
}

test "visual-row selection includes all visible row text beside tall continuation" {
    var terminal = try vt.initWithHistory(std.testing.allocator, 3, 8, 4);
    defer terminal.deinit();
    // zig-audit: acknowledge discard
    // reason: Assertions inspect selection after parsed input.
    _ = try terminal.feed("\x1b[1;4H\x1b]66;s=2;X\x07\x1b[2;1HAB");
    const selected = (try visualRow(terminal.semanticView(0), 1)).?;
    const copied = try selected.copy(terminal.observation(), std.testing.allocator, 64);
    defer std.testing.allocator.free(copied);
    try std.testing.expect(std.mem.indexOf(u8, copied, "AB") != null);
}

test "history text copies when only live content is a taller continuation" {
    var terminal = try vt.initWithHistory(std.testing.allocator, 3, 8, 8);
    defer terminal.deinit();
    // zig-audit: acknowledge discard
    // reason: Assertions inspect canonical history selection after parsed input.
    _ = try terminal.feed("\x1b]66;s=3;X\x07\x1b[2;8HZ\x1b[2S");
    const view = terminal.semanticView(1);
    const selected = (try word(view, 0, 7)).?;
    const copied = try selected.copy(terminal.observation(), std.testing.allocator, 16);
    defer std.testing.allocator.free(copied);
    try std.testing.expectEqualStrings("Z", copied);
}

test "history to live padding never copies an unselected tall block" {
    for ([_]u16{ 1, 8 }) |capacity| {
        var terminal = try vt.initWithHistory(std.testing.allocator, 3, 8, capacity);
        defer terminal.deinit();
        // zig-audit: acknowledge discard
        // reason: The selection assertion checks the accepted screen and history.
        _ = try terminal.feed("\x1b[1;6H\x1b]66;s=3;X\x07\x1b[2;1HZ\x1b[2S");
        const view = terminal.semanticView(1);
        var selected = try start(view, 0, 0);
        try selected.extend(view, 1, 0);
        const copied = try selected.copy(terminal.observation(), std.testing.allocator, 32);
        defer std.testing.allocator.free(copied);
        try std.testing.expectEqualStrings("Z", copied);
    }
}
