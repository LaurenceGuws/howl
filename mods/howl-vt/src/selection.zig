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
