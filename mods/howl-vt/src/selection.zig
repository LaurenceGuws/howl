//! VT-owned selection geometry and extraction for Zig and foreign embedders.
//! No C records, process owner, renderer, or host UI policy enters this module.
const std = @import("std");
const Terminal = @import("terminal.zig").Terminal;
const maximum_cell_scalars = @import("scalar_storage.zig").maximum_scalars;

/// Exact terminal-text extraction and stale-geometry failures.
pub const Error = Terminal.TextError || error{ContextChanged};
/// Canonical expansion choices shared by direct and foreign callers.
pub const Kind = enum { word, visual_row };
/// Context in which saved projected coordinates were selected.
/// Embedders also invalidate their selection on resize/reset; this is no lease.
pub const Context = struct {
    columns: u16,
    alternate: bool,

    /// Copies context from one synchronous canonical view.
    pub fn fromView(view: *const Terminal.SemanticView) Context {
        return .{ .columns = view.cols, .alternate = view.is_alternate_screen };
    }

    fn matches(self: Context, view: *const Terminal.SemanticView) bool {
        return self.columns == view.cols and self.alternate == view.is_alternate_screen;
    }
};

/// Copied projected endpoints qualified by their screen bank and column geometry.
pub const Range = struct {
    text: Terminal.TextRange,
    context: Context,

    /// Validates context and delegates lead normalization/ordering to canonical text authority.
    pub fn normalized(self: Range, observation: *const Terminal.Observation) error{ ContextChanged, InvalidRange }!Range {
        const current = observation.semanticView(0);
        if (!self.context.matches(&current)) return error.ContextChanged;
        return .{ .context = self.context, .text = try observation.normalizeTextRange(self.text) };
    }

    /// Copies bounded UTF-8 through the canonical VT owner; never copies concealed text.
    /// The caller owns the result. Context rejection precedes any allocation.
    pub fn copy(self: Range, observation: *const Terminal.Observation, allocator: std.mem.Allocator, max_bytes: usize) Error![]const u8 {
        const current = observation.semanticView(0);
        if (!self.context.matches(&current)) return error.ContextChanged;
        return observation.copyText(allocator, self.text, max_bytes);
    }
};

/// One semantic lead in synchronous viewport coordinates.
pub const Position = struct {
    row: u16,
    column: u16,
};

/// Converts a viewport row to a retained projected row, bounded by TextPoint.
pub fn stableRow(
    view: *const Terminal.SemanticView,
    viewport_row: u16,
) ?i32 {
    if (viewport_row >= view.rows) return null;
    if (view.is_alternate_screen) return @intCast(viewport_row);
    if (view.history_offset > view.history_count) return null;
    const row = @as(u64, view.history_row_base) +
        view.history_count - view.history_offset + viewport_row;
    if (row > std.math.maxInt(i32)) return null;
    return @intCast(row);
}

/// Finds a retained projected row in this synchronous viewport, or null off-view.
pub fn viewportRow(
    view: *const Terminal.SemanticView,
    stable_row: i32,
) ?u16 {
    if (view.rows == 0) return null;
    if (view.is_alternate_screen) {
        if (stable_row < 0 or stable_row >= view.rows) return null;
        return @intCast(stable_row);
    }
    const top = @as(i64, view.history_row_base) +
        view.history_count - view.history_offset;
    const relative = @as(i64, stable_row) - top;
    if (relative < 0 or relative >= view.rows) return null;
    return @intCast(relative);
}

/// Normalizes occupancy to its semantic lead without traversing outside the view.
pub fn leadPosition(
    view: *const Terminal.SemanticView,
    row: u16,
    column: u16,
) ?Position {
    if (row >= view.rows or column >= view.cols) return null;
    const cell = view.cellInfoAt(row, column);
    if (cell.x > column or cell.y > row) return null;
    return .{
        .row = row - cell.y,
        .column = column - cell.x,
    };
}

fn selectableLead(
    view: *const Terminal.SemanticView,
    position: Position,
) bool {
    const cell = view.cellInfoAt(position.row, position.column);
    if (cell.x != 0 or cell.y != 0 or cell.attrs.invisible) return false;
    var scalars: [maximum_cell_scalars]u21 = undefined;
    const values = view.cellScalarsAt(
        position.row,
        position.column,
        &scalars,
    );
    return values.len != 0 and values[0] != ' ';
}

// Traverse semantic leads in row order. Lower-row occupancy repeats an earlier
// cluster; it is not another character and must never resolve traversal backward.
fn previousLead(view: *const Terminal.SemanticView, position: Position) ?Position {
    var row = position.row;
    var column: i32 = @as(i32, position.column) - 1;
    while (true) {
        while (column >= 0) {
            const cell = view.cellInfoAt(row, @intCast(column));
            if (cell.y == 0) {
                const lead = leadPosition(view, row, @intCast(column)) orelse return null;
                if (lead.row < position.row or (lead.row == position.row and lead.column < position.column)) return lead;
            }
            // Skip the remaining left extent of a repeated lower-row cluster.
            // This decreases the physical column even at a malformed empty extent.
            column -= @as(i32, cell.x) + 1;
        }
        if (row == 0 or !view.rowWrapped(row - 1)) return null;
        row -= 1;
        column = @as(i32, view.cols) - 1;
    }
}

fn nextLead(view: *const Terminal.SemanticView, position: Position) ?Position {
    const current = view.cellInfoAt(position.row, position.column);
    var row = position.row;
    var column = @as(u32, position.column) + @max(@as(u32, current.width), 1);
    while (true) {
        while (column < view.cols) {
            const cell = view.cellInfoAt(row, @intCast(column));
            if (cell.y == 0) {
                const lead = leadPosition(view, row, @intCast(column)) orelse return null;
                if (lead.row > position.row or (lead.row == position.row and lead.column > position.column)) return lead;
            }
            // A lower-row continuation belongs to an earlier lead. Skip its
            // remaining physical extent instead of revisiting that earlier word.
            column += @max(@as(u32, cell.width) -| cell.x, 1);
        }
        if (!view.rowWrapped(row) or row + 1 >= view.rows) return null;
        row += 1;
        column = 0;
    }
}

/// Returns the last occupied content column, excluding untouched trailing blanks.
pub fn lastContentColumn(
    view: *const Terminal.SemanticView,
    row: u16,
) ?u16 {
    if (row >= view.rows) return null;
    var column: usize = view.cols;
    while (column != 0) {
        column -= 1;
        const cell = view.cellInfoAt(row, @intCast(column));
        if (cell.x != 0 or cell.y != 0) continue;
        // A lead cell's first scalar is its copied codepoint.
        if (cell.codepoint == 0 or cell.codepoint == ' ') continue;
        const end = @min(
            @as(u32, view.cols - 1),
            @as(u32, @intCast(column)) + @max(@as(u32, cell.width), 1) - 1,
        );
        return @intCast(end);
    }
    return null;
}

/// Locates a retained projected row; the returned view borrows until VT mutation.
pub fn viewForStableRow(
    observation: *const Terminal.Observation,
    stable_row: i32,
) ?struct {
    view: Terminal.SemanticView,
    viewport_row: u16,
} {
    const live = observation.semanticView(0);
    if (live.is_alternate_screen) {
        if (stable_row < 0 or stable_row >= live.rows) return null;
        return .{ .view = live, .viewport_row = @intCast(stable_row) };
    }
    const live_top = @as(i64, live.history_row_base) + live.history_count;
    const last = live_top + live.rows - 1;
    if (stable_row < live.history_row_base or stable_row > last) return null;
    if (stable_row >= live_top)
        return .{
            .view = live,
            .viewport_row = @intCast(@as(i64, stable_row) - live_top),
        };
    const offset: u32 = @intCast(live_top - stable_row);
    return .{
        .view = observation.semanticView(offset),
        .viewport_row = 0,
    };
}

/// Converts one visible cell, including a continuation, to its canonical lead.
pub fn point(view: *const Terminal.SemanticView, row: u16, column: u16) ?Terminal.TextPoint {
    const lead = leadPosition(view, row, column) orelse return null;
    return .{ .row = stableRow(view, lead.row) orelse return null, .col = lead.column };
}

/// Expands a nonblank word or one visual row using canonical cluster occupancy.
/// Null means no selectable content; stale bank/columns/retention fail explicitly.
pub fn expand(observation: *const Terminal.Observation, kind: Kind, history_offset: u32, target: Terminal.TextPoint, context: Context) Error!?Range {
    const view = observation.semanticView(history_offset);
    if (!context.matches(&view)) return error.ContextChanged;
    const row = viewportRow(&view, target.row) orelse return error.ContextChanged;
    if (target.col >= view.cols) return error.ContextChanged;
    if (kind == .visual_row) {
        const last = lastContentColumn(&view, row) orelse return null;
        var first: ?u16 = null;
        var column: u16 = 0;
        while (column < view.cols) : (column += 1) {
            const cell = view.cellInfoAt(row, column);
            if (cell.x == 0 and cell.y == 0) {
                first = column;
                break;
            }
        }
        const start = first orelse return null;
        const stable = stableRow(&view, row) orelse return error.ContextChanged;
        return .{ .text = .{ .start = .{ .row = stable, .col = start }, .end = .{ .row = stable, .col = last } }, .context = Context.fromView(&view) };
    }
    const start = leadPosition(&view, row, target.col) orelse return error.ContextChanged;
    if (!selectableLead(&view, start)) return null;
    var first = start;
    while (previousLead(&view, first)) |candidate| {
        if (!selectableLead(&view, candidate)) break;
        first = candidate;
    }
    var last = start;
    while (nextLead(&view, last)) |candidate| {
        if (!selectableLead(&view, candidate)) break;
        last = candidate;
    }
    const first_row = stableRow(&view, first.row) orelse return error.ContextChanged;
    const last_row = stableRow(&view, last.row) orelse return error.ContextChanged;
    const cell = view.cellInfoAt(last.row, last.column);
    const end_column = @min(@as(u32, view.cols - 1), @as(u32, last.column) + @max(@as(u32, cell.width), 1) - 1);
    return .{ .text = .{ .start = .{ .row = first_row, .col = first.column }, .end = .{ .row = last_row, .col = @intCast(end_column) } }, .context = Context.fromView(&view) };
}

/// One contiguous selected run in a visible row's logical text columns.
pub const Span = struct { row: u16, column: u16, columns: u16 };

/// Projects selected semantic leads into visible occupancy runs, including wide/tall
/// continuations. No glyph/pixel/color
/// policy enters VT. Output is caller-owned; SpanLimit retains no canonical effects.
pub fn visibleSpans(observation: *const Terminal.Observation, history_offset: u32, range: Range, output: []Span) error{ ContextChanged, InvalidRange, SpanLimit }![]const Span {
    const selected = try range.normalized(observation);
    const view = observation.semanticView(history_offset);
    var used: usize = 0;
    for (0..view.rows) |row_index| {
        const row: u16 = @intCast(row_index);
        const absolute = stableRow(&view, row) orelse continue;
        const columns = switch (view.lineGeometry(row)) {
            .single_width => view.cols,
            .double_width, .double_height_top, .double_height_bottom => @max(@as(u16, 1), view.cols / 2),
        };
        var start: ?u16 = null;
        var column: u16 = 0;
        while (column < columns) : (column += 1) {
            const cell = view.cellInfoAt(row, column);
            const lead: ?Terminal.TextPoint = if (cell.x <= column and cell.y <= absolute)
                .{ .row = absolute - @as(i32, cell.y), .col = column - cell.x }
            else
                null;
            const included = if (lead) |value|
                !pointBefore(value, selected.text.start) and !pointBefore(selected.text.end, value)
            else
                false;
            if (included) {
                if (start == null) start = column;
            } else if (start) |first| {
                if (used == output.len) return error.SpanLimit;
                output[used] = .{ .row = row, .column = first, .columns = column - first };
                used += 1;
                start = null;
            }
        }
        if (start) |first| {
            if (used == output.len) return error.SpanLimit;
            output[used] = .{ .row = row, .column = first, .columns = columns - first };
            used += 1;
        }
    }
    return output[0..used];
}

fn pointBefore(left: Terminal.TextPoint, right: Terminal.TextPoint) bool {
    return left.row < right.row or (left.row == right.row and left.col < right.col);
}

test "direct Zig selection preserves wide and combining occupancy without a foreign schema" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("A界é\r\n\x1b[8mSECRET\x1b[0m")).stateChanged());
    const observation = terminal.observation();
    const view = observation.semanticView(0);
    const context = Context.fromView(&view);
    const lead = point(&view, 0, 2).?;
    try std.testing.expectEqual(@as(u16, 1), lead.col);
    const range = (try expand(observation, .word, 0, lead, context)).?;
    const text = try range.copy(observation, std.testing.allocator, 64);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("A界é", text);
    try std.testing.expect((try expand(observation, .word, 0, .{ .row = 1, .col = 2 }, context)) == null);
    const hidden = (try expand(observation, .visual_row, 0, .{ .row = 1, .col = 0 }, context)).?;
    const blanks = try hidden.copy(observation, std.testing.allocator, 64);
    defer std.testing.allocator.free(blanks);
    try std.testing.expect(std.mem.indexOf(u8, blanks, "SECRET") == null);
}

test "direct saved selection rejects a different bank and eviction before allocation" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 1, 4, 2);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("A")).stateChanged());
    const view = terminal.semanticView(0);
    const selected = (try expand(terminal.observation(), .word, 0, .{ .row = 0, .col = 0 }, Context.fromView(&view))).?;
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expect((try terminal.feed("\x1b[?1049h")).stateChanged());
    try std.testing.expectError(error.ContextChanged, selected.copy(terminal.observation(), failing.allocator(), 64));
    try std.testing.expect(!failing.has_induced_failure);
    try std.testing.expect((try terminal.feed("\x1b[?1049l\r\nB\r\nC\r\nD\r\n")).stateChanged());
    try std.testing.expect(viewportRow(&terminal.semanticView(0), 0) == null);
    try std.testing.expectError(error.InvalidRange, selected.copy(terminal.observation(), failing.allocator(), 64));
    try std.testing.expect(!failing.has_induced_failure);
}

test "row mutation identity follows an unchanged live row into history" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 1, 4, 2);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("AB")).stateChanged());
    const live = terminal.semanticView(0);
    const generation = live.rowGeneration(0).?;
    try std.testing.expect((try terminal.feed("\r\n")).stateChanged());
    const history = terminal.semanticView(1);
    try std.testing.expect(history.rowGeneration(0) != null);
    try std.testing.expectEqual(generation, history.rowGeneration(0).?);
    try std.testing.expect(history.rowGeneration(1) == null);
    try std.testing.expectEqual(@as(u21, 'A'), history.cellAt(0, 0));
    try std.testing.expect((try terminal.feed("C\r\n")).stateChanged());
    const retained = terminal.semanticView(2);
    try std.testing.expectEqual(generation, retained.rowGeneration(0).?);
}

test "editing and restoring history cannot reuse a selected row mutation identity" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 1, 4, 2);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("AB")).stateChanged());
    const live_generation = terminal.semanticView(0).rowGeneration(0).?;
    try std.testing.expect((try terminal.feed("\rC\r\n")).stateChanged());
    const before = terminal.semanticView(1);
    try std.testing.expect(before.rowGeneration(0) != null);
    const archived_generation = before.rowGeneration(0).?;
    try std.testing.expect(archived_generation != live_generation);
    try std.testing.expectEqual(@as(u21, 'C'), before.cellAt(0, 0));
    const coordinate = stableRow(&before, 0).?;
    // CSI + T restores the newest history row. Edit and re-archive it in
    // this same feed, ending with identical retained row coordinates/count.
    try std.testing.expect((try terminal.feed("\x1b[+T\rD\r\n")).stateChanged());
    const after = terminal.semanticView(1);
    try std.testing.expectEqual(coordinate, stableRow(&after, 0).?);
    try std.testing.expectEqual(before.history_count, after.history_count);
    try std.testing.expect(after.rowGeneration(0).? != archived_generation);
    try std.testing.expectEqual(@as(u21, 'D'), after.cellAt(0, 0));
}

test "reflow rebuilds history with fresh identities and eviction exposes no retired generation" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 2, 4, 4);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("ABCD\r\nEFGH\r\nIJKL\r\nMNOP")).stateChanged());
    const old = terminal.semanticView(4);
    var maximum: u64 = 0;
    for (0..old.history_count + old.rows) |index| {
        const located = viewForStableRow(terminal.observation(), @intCast(old.history_row_base + index)).?;
        maximum = @max(maximum, located.view.rowGeneration(located.viewport_row).?);
    }
    try terminal.resize(2, 2);
    const resized = terminal.semanticView(0);
    for (0..resized.history_count + resized.rows) |index| {
        const located = viewForStableRow(terminal.observation(), @intCast(resized.history_row_base + index)).?;
        try std.testing.expect(located.view.rowGeneration(located.viewport_row).? > maximum);
    }
    const retired = @as(i32, @intCast(resized.history_row_base));
    try std.testing.expect((try terminal.feed("\r\n1\r\n2\r\n3\r\n4\r\n5\r\n6")).stateChanged());
    try std.testing.expect(viewForStableRow(terminal.observation(), retired) == null);
}

test "hard reset has its own identity while retained history provenance survives" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 1, 4, 2);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("AB\r\n")).stateChanged());
    const before = terminal.observation().resetSequence();
    const history_generation = terminal.semanticView(1).rowGeneration(0).?;
    try std.testing.expect((try terminal.feed("C\x1b[!p")).stateChanged());
    try std.testing.expectEqual(before, terminal.observation().resetSequence());
    terminal.hardReset();
    try std.testing.expectEqual(before + 1, terminal.observation().resetSequence());
    try std.testing.expectEqual(history_generation, terminal.semanticView(1).rowGeneration(0).?);
    try std.testing.expect((try terminal.feed("\x1bc")).stateChanged());
    try std.testing.expectEqual(before + 2, terminal.observation().resetSequence());
    try std.testing.expectEqual(terminal.pointerShapeResetSequence(), terminal.observation().resetSequence());
}

test "copied scalar obeys byte limits smaller than its first UTF8 encoding" {
    var terminal = try Terminal.init(std.testing.allocator, 1, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("😀")).stateChanged());
    const range: Range = .{ .context = Context.fromView(&terminal.semanticView(0)), .text = .{ .start = .{ .row = 0, .col = 0 }, .end = .{ .row = 0, .col = 0 } } };
    for (0..4) |limit| try std.testing.expectError(error.TextLimit, range.copy(terminal.observation(), std.testing.failing_allocator, limit));
    const text = try range.copy(terminal.observation(), std.testing.allocator, 4);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("😀", text);
}

test "normalization and spans select whole wide clusters from a continuation endpoint" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("A界B")).stateChanged());
    const range: Range = .{ .context = Context.fromView(&terminal.semanticView(0)), .text = .{ .start = .{ .row = 0, .col = 2 }, .end = .{ .row = 0, .col = 2 } } };
    const normalized = try range.normalized(terminal.observation());
    try std.testing.expectEqual(@as(u16, 1), normalized.text.start.col);
    var output: [4]Span = undefined;
    const spans = try visibleSpans(terminal.observation(), 0, range, &output);
    try std.testing.expectEqualSlices(Span, &.{.{ .row = 0, .column = 1, .columns = 2 }}, spans);
    try std.testing.expectError(error.SpanLimit, visibleSpans(terminal.observation(), 0, range, &.{}));
    const reversed: Range = .{ .context = range.context, .text = .{ .start = .{ .row = 0, .col = 3 }, .end = .{ .row = 0, .col = 0 } } };
    const full = try visibleSpans(terminal.observation(), 0, reversed, &output);
    try std.testing.expectEqualSlices(Span, &.{.{ .row = 0, .column = 0, .columns = 4 }}, full);
}

test "copy handles the maximum representable projected row without increment overflow" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 1, 4, 2);
    defer terminal.deinit();
    // A valid synthetic aged frontier avoids billions of irrelevant input rows.
    terminal.screen_state.primary.history_store.?.row_base = std.math.maxInt(i32);
    try std.testing.expect((try terminal.feed("X")).stateChanged());
    const maximum = std.math.maxInt(i32);
    const range: Range = .{ .context = Context.fromView(&terminal.semanticView(0)), .text = .{ .start = .{ .row = maximum, .col = 0 }, .end = .{ .row = maximum, .col = 0 } } };
    const text = try range.copy(terminal.observation(), std.testing.allocator, 1);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("X", text);
}

test "selection spans cover tall occupancy and respect canonical scroll cleanup" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 3, 8, 4);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("\x1b]66;s=2:w=2;Hi\x07")).stateChanged());
    const range: Range = .{ .context = Context.fromView(&terminal.semanticView(0)), .text = .{ .start = .{ .row = 0, .col = 0 }, .end = .{ .row = 0, .col = 0 } } };
    var output: [4]Span = undefined;
    const whole = try visibleSpans(terminal.observation(), 0, range, &output);
    try std.testing.expectEqualSlices(Span, &.{
        .{ .row = 0, .column = 0, .columns = 4 },
        .{ .row = 1, .column = 0, .columns = 4 },
    }, whole);
    try std.testing.expect((try terminal.feed("\x1b[3;1H\r\n")).stateChanged());
    const partial = try visibleSpans(terminal.observation(), 0, range, &output);
    // Canonical scrolling clears non-semantic clusters that would straddle
    // the live/history boundary; the query must not invent a surviving fragment.
    try std.testing.expectEqual(@as(usize, 0), partial.len);
    const text = try range.copy(terminal.observation(), std.testing.allocator, 16);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("", text);
}

test "unselected tall occupancy can split one selected visible row into separate runs" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("\x1b[1;4H\x1b]66;s=2:w=1;X\x07")).stateChanged());
    const range: Range = .{ .context = Context.fromView(&terminal.semanticView(0)), .text = .{ .start = .{ .row = 0, .col = 5 }, .end = .{ .row = 2, .col = 7 } } };
    var output: [4]Span = undefined;
    const spans = try visibleSpans(terminal.observation(), 0, range, &output);
    try std.testing.expectEqualSlices(Span, &.{
        .{ .row = 0, .column = 5, .columns = 3 },
        .{ .row = 1, .column = 0, .columns = 3 },
        .{ .row = 1, .column = 5, .columns = 3 },
        .{ .row = 2, .column = 0, .columns = 8 },
    }, spans);
    const before = terminal.semanticSequence();
    try std.testing.expectError(error.SpanLimit, visibleSpans(terminal.observation(), 0, range, output[0..3]));
    try std.testing.expectEqual(before, terminal.semanticSequence());
}

test "DEC wide-row selection spans stop at its logical text column frontier" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("\x1b#6AB")).stateChanged());
    const range: Range = .{ .context = Context.fromView(&terminal.semanticView(0)), .text = .{ .start = .{ .row = 0, .col = 0 }, .end = .{ .row = 0, .col = 7 } } };
    var output: [2]Span = undefined;
    const spans = try visibleSpans(terminal.observation(), 0, range, &output);
    try std.testing.expectEqualSlices(Span, &.{.{ .row = 0, .column = 0, .columns = 4 }}, spans);
}
