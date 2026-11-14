//! Optional VT-owned foreign observation projection; no Instance, Server or host runtime.
const std = @import("std");
const vt = @import("howl_vt");
const c = @import("vt_native_types");
const Terminal = vt.Terminal;
const maximum_cell_scalars = vt.scalar.maximum_scalars;
const maximum_search_query_bytes = c.HVT_MAX_SEARCH_QUERY_BYTES;
/// Copied stable match coordinates and exact observation-cut facts.
pub const SearchMatchInfo = c.hvt_search_match;
/// Copied canonical selection endpoints and their geometry context.
pub const SelectionRangeInfo = c.hvt_selection_range;
/// Native observation argument, allocation, context and output-capacity failures.
pub const Error = Terminal.TextError || error{ InvalidArgument, ContextChanged, BufferTooSmall, CoordinateLimit, Overflow };
const selection = vt.selection;
const nativeViewportRow = selection.viewportRow;
const nativeLastContentColumn = selection.lastContentColumn;
const nativeViewForStableRow = selection.viewForStableRow;

fn nativeLastSearchColumn(
    view: *const Terminal.SemanticView,
    row: u16,
) ?u16 {
    if (row >= view.rows) return null;
    var column: usize = view.cols;
    while (column != 0) {
        column -= 1;
        const cell = view.cellInfoAt(row, @intCast(column));
        if (cell.x != 0 or cell.y != 0 or cell.attrs.invisible) continue;
        if (cell.codepoint != 0)
            return @intCast(column);
    }
    return null;
}

/// Expands a word or one visual row into copied stable canonical coordinates.
pub fn expandSelection(
    observation: *const Terminal.Observation,
    kind: u8,
    history_offset: u32,
    target_row: i32,
    target_column: u16,
    expected_columns: u16,
    expected_alternate: bool,
    output: *SelectionRangeInfo,
) Error!void {
    output.* = .{};
    const typed_kind: selection.Kind = switch (kind) {
        c.HVT_SELECTION_WORD => .word,
        c.HVT_SELECTION_VISUAL_ROW => .visual_row,
        else => return error.InvalidArgument,
    };
    const range = try selection.expand(observation, typed_kind, history_offset, .{ .row = target_row, .col = target_column }, .{ .columns = expected_columns, .alternate = expected_alternate }) orelse return;
    output.* = .{
        .start_row = range.text.start.row,
        .end_row = range.text.end.row,
        .start_column = range.text.start.col,
        .end_column = range.text.end.col,
        .columns = range.context.columns,
        .found = 1,
        .alternate_screen = @intFromBool(range.context.alternate),
    };
}

fn nativeSearchRow(
    observation: *const Terminal.Observation,
    allocator: std.mem.Allocator,
    query: []const u8,
    stable_row: i32,
    column_bound: u16,
    reverse: bool,
) Error!?struct { start: u16, end: u16 } {
    const located = nativeViewForStableRow(observation, stable_row) orelse
        return null;
    const view = located.view;
    const row = located.viewport_row;
    const last = nativeLastSearchColumn(&view, row) orelse return null;
    const maximum_bytes = try std.math.mul(
        usize,
        @as(usize, last) + 1,
        maximum_cell_scalars * 4,
    );
    const text = try allocator.alloc(u8, maximum_bytes);
    defer allocator.free(text);
    const columns = try allocator.alloc(u16, maximum_bytes);
    defer allocator.free(columns);

    var used: usize = 0;
    var column: u16 = 0;
    while (column <= last) : (column += 1) {
        const cell = view.cellInfoAt(row, column);
        if (cell.x != 0 or cell.y != 0) continue;
        var scalars: [maximum_cell_scalars]u21 = undefined;
        const values = view.cellScalarsAt(row, column, &scalars);
        if (cell.attrs.invisible or values.len == 0) {
            text[used] = ' ';
            columns[used] = column;
            used += 1;
            continue;
        }
        for (values) |scalar| {
            var encoded: [4]u8 = undefined;
            const count = try std.unicode.utf8Encode(scalar, &encoded);
            @memcpy(text[used .. used + count], encoded[0..count]);
            @memset(columns[used .. used + count], column);
            used += count;
        }
    }
    if (query.len > used) return null;
    const haystack = text[0..used];
    if (reverse) {
        var end_at = haystack.len;
        while (end_at >= query.len) {
            const found = std.mem.lastIndexOf(
                u8,
                haystack[0..end_at],
                query,
            ) orelse return null;
            const start_column = columns[found];
            const end_lead = columns[found + query.len - 1];
            if (end_lead <= column_bound) {
                const cell = view.cellInfoAt(row, end_lead);
                const end_column = @min(
                    @as(u32, view.cols - 1),
                    @as(u32, end_lead) + @max(@as(u32, cell.width), 1) - 1,
                );
                return .{
                    .start = start_column,
                    .end = @intCast(end_column),
                };
            }
            if (found == 0) return null;
            end_at = found;
        }
        return null;
    }

    var start_at: usize = 0;
    while (start_at + query.len <= haystack.len) {
        const relative = std.mem.indexOf(
            u8,
            haystack[start_at..],
            query,
        ) orelse return null;
        const found = start_at + relative;
        const start_column = columns[found];
        if (start_column >= column_bound) {
            const end_lead = columns[found + query.len - 1];
            const cell = view.cellInfoAt(row, end_lead);
            const end_column = @min(
                @as(u32, view.cols - 1),
                @as(u32, end_lead) + @max(@as(u32, cell.width), 1) - 1,
            );
            return .{
                .start = start_column,
                .end = @intCast(end_column),
            };
        }
        start_at = found + 1;
    }
    return null;
}

/// Finds an exact UTF-8 match within one row across bounded retained history.
pub fn search(
    observation: *const Terminal.Observation,
    allocator: std.mem.Allocator,
    query: []const u8,
    reverse: bool,
    origin_present: bool,
    origin_row: i32,
    origin_column: u16,
    output: *SearchMatchInfo,
) Error!void {
    output.* = .{};
    if (query.len == 0 or query.len > maximum_search_query_bytes or
        !std.unicode.utf8ValidateSlice(query))
        return error.InvalidArgument;

    const live = observation.semanticView(0);
    output.cut_revision = observation.semanticSequence();
    output.columns = live.cols;
    output.alternate_screen = @intFromBool(live.is_alternate_screen);
    output.complete = 1;
    if (live.rows == 0 or live.cols == 0) return;
    if (origin_present and origin_column >= live.cols) return error.ContextChanged;

    const first: i64 = if (live.is_alternate_screen)
        0
    else
        live.history_row_base;
    const last: i64 = if (live.is_alternate_screen)
        live.rows - 1
    else
        @as(i64, live.history_row_base) + live.history_count + live.rows - 1;

    if (first > std.math.maxInt(i32) or last > std.math.maxInt(i32)) return error.CoordinateLimit;
    var row: i64 = if (origin_present)
        origin_row
    else if (reverse)
        last
    else
        first;
    var column: u16 = if (origin_present)
        origin_column
    else if (reverse)
        live.cols - 1
    else
        0;

    if (origin_present) {
        if (reverse) {
            if (column == 0) {
                row -= 1;
                column = live.cols - 1;
            } else column -= 1;
        } else if (column + 1 >= live.cols) {
            row += 1;
            column = 0;
        } else column += 1;
    }

    while (row >= first and row <= last) {
        output.scanned_snapshots += 1;
        const found = try nativeSearchRow(
            observation,
            allocator,
            query,
            @intCast(row),
            column,
            reverse,
        );
        if (found) |match| {
            output.found = 1;
            output.row = @intCast(row);
            output.start_column = match.start;
            output.end_column = match.end;
            return;
        }
        if (reverse) {
            row -= 1;
            column = live.cols - 1;
        } else {
            row += 1;
            column = 0;
        }
    }
    return;
}

/// Copies the full canonical selected text without truncation or a mutable terminal escape.
pub fn copySelection(observation: *const Terminal.Observation, allocator: std.mem.Allocator, start_row: i32, start_column: u16, end_row: i32, end_column: u16, expected_columns: u16, expected_alternate: bool, output: []u8) Error!usize {
    if (expected_columns == 0) return error.InvalidArgument;
    const current = observation.semanticView(0);
    if (current.cols != expected_columns or current.is_alternate_screen != expected_alternate) return error.ContextChanged;
    const text = try observation.copyText(allocator, .{ .start = .{ .row = start_row, .col = start_column }, .end = .{ .row = end_row, .col = end_column } }, output.len);
    defer allocator.free(text);
    @memcpy(output[0..text.len], text);
    return text.len;
}

/// Copies one exact hyperlink URI; insufficient capacity reports required length without writing bytes.
pub fn copyHyperlink(observation: *const Terminal.Observation, history_offset: u32, target_row: i32, target_column: u16, expected_columns: u16, expected_alternate: bool, output: []u8, required: *usize) Error!void {
    required.* = 0;
    if (expected_columns == 0) return error.InvalidArgument;
    const view = observation.semanticView(history_offset);
    if (view.cols != expected_columns or view.is_alternate_screen != expected_alternate) return error.ContextChanged;
    const row = nativeViewportRow(&view, target_row) orelse return error.ContextChanged;
    if (target_column >= view.cols) return error.ContextChanged;
    const id = view.cellInfoAt(row, target_column).attrs.link_id;
    const uri = observation.hyperlinkUri(id) orelse return;
    required.* = uri.len;
    if (uri.len > output.len) return error.BufferTooSmall;
    @memcpy(output[0..uri.len], uri);
}

/// Copies one visual-row shape from a synchronous const viewport.
/// Rejects an out-of-viewport row; no terminal or presentation storage is retained.
pub fn rowShape(view: *const Terminal.SemanticView, row: u16) error{InvalidArgument}!c.hvt_row_shape {
    if (row >= view.rows) return error.InvalidArgument;
    const last = nativeLastContentColumn(view, row);
    return .{ .content_end_exclusive = if (last) |column| @intCast(@min(@as(u32, view.cols), @as(u32, column) + 1)) else 0, .wrapped = @intFromBool(view.rowWrapped(row)) };
}

/// Copies canonical visual-row shapes; a capacity failure writes no records.
pub fn copyRowShapes(observation: *const Terminal.Observation, history_offset: u32, output: []c.hvt_row_shape) Error!usize {
    const view = observation.semanticView(history_offset);
    if (view.rows > output.len) return error.BufferTooSmall;
    for (0..view.rows) |index| output[index] = try rowShape(&view, @intCast(index));
    return view.rows;
}

/// Caller-owned UTF-8 prefix and whether the complete viewport text fitted.
pub const TextProjection = struct { bytes_written: usize, truncated: bool };

/// Copies visible text without allocation or retaining observation storage.
/// Untouched trailing blanks/rows are trimmed; printed spaces and visual row
/// breaks (including soft wraps) remain. Concealed cells become interior blanks;
/// multicell fragments do not repeat. Exhaustion stops at a UTF-8 scalar boundary,
/// which may split a grapheme. Output beyond bytes_written is untouched.
pub fn writeVisibleText(view: *const Terminal.SemanticView, output: []u8) error{InvalidScalar}!TextProjection {
    var last_row = view.rows;
    while (last_row > 0 and nativeLastSearchColumn(view, last_row - 1) == null) last_row -= 1;
    var used: usize = 0;
    for (0..last_row) |row_index| {
        const row: u16 = @intCast(row_index);
        if (row > 0) {
            if (used == output.len) return .{ .bytes_written = used, .truncated = true };
            output[used] = '\n';
            used += 1;
        }
        const last = nativeLastSearchColumn(view, row) orelse continue;
        for (0..@as(usize, last) + 1) |column_index| {
            const column: u16 = @intCast(column_index);
            const cell = view.cellInfoAt(row, column);
            if (cell.x != 0 or cell.y != 0) continue;
            var storage: [maximum_cell_scalars]u21 = undefined;
            const scalars = view.cellScalarsAt(row, column, &storage);
            if (cell.attrs.invisible or scalars.len == 0) {
                if (used == output.len) return .{ .bytes_written = used, .truncated = true };
                output[used] = ' ';
                used += 1;
            } else for (scalars) |scalar| {
                var encoded: [4]u8 = undefined;
                const count = std.unicode.utf8Encode(scalar, &encoded) catch return error.InvalidScalar;
                if (count > output.len - used) return .{ .bytes_written = used, .truncated = true };
                @memcpy(output[used..][0..count], encoded[0..count]);
                used += count;
            }
        }
    }
    return .{ .bytes_written = used, .truncated = false };
}

/// Copies stable interaction tags field by field; no Zig enum layout is exported.
pub fn interaction(observation: *const Terminal.Observation) c.hvt_interaction {
    const value = observation.interactionState();
    return .{
        .terminal_revision = observation.semanticSequence(),
        .flags = (if (value.alternate_scroll) @as(u32, c.HVT_INTERACTION_ALTERNATE_SCROLL) else 0) | (if (value.focus_reporting) @as(u32, c.HVT_INTERACTION_FOCUS_REPORTING) else 0),
        .mouse_tracking = switch (value.mouse_tracking) {
            .off => c.HVT_TRACK_OFF,
            .x10 => c.HVT_TRACK_X10,
            .normal => c.HVT_TRACK_NORMAL,
            .button_event => c.HVT_TRACK_BUTTON_EVENT,
            .any_event => c.HVT_TRACK_ANY_EVENT,
        },
        .mouse_protocol = switch (value.mouse_protocol) {
            .none => c.HVT_MOUSE_NONE_PROTOCOL,
            .utf8 => c.HVT_MOUSE_UTF8,
            .sgr => c.HVT_MOUSE_SGR,
            .sgr_pixel => c.HVT_MOUSE_SGR_PIXEL,
            .urxvt => c.HVT_MOUSE_URXVT,
        },
        .pointer_mode = @intCast(value.pointer_mode),
    };
}

test "native queries preserve Unicode coordinates, hide concealed text and copy stable selection" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("A界é\r\n\x1b[8mSECRET\x1b[0m")).stateChanged());
    const observation = terminal.observation();
    var match: SearchMatchInfo = undefined;
    try search(observation, std.testing.allocator, "界", false, false, 0, 0, &match);
    try std.testing.expect(match.found == 1 and match.row == 0 and match.start_column == 1 and match.end_column == 2);
    try search(observation, std.testing.allocator, "é", true, false, 0, 0, &match);
    try std.testing.expect(match.found == 1 and match.start_column == 3 and match.end_column == 3);
    try search(observation, std.testing.allocator, "SECRET", false, false, 0, 0, &match);
    try std.testing.expect(match.found == 0 and match.complete == 1);
    var range: SelectionRangeInfo = undefined;
    try expandSelection(observation, c.HVT_SELECTION_WORD, 0, 0, 2, 8, false, &range);
    try std.testing.expect(range.found == 1 and range.start_column == 0 and range.end_column == 3);
    var text: [32]u8 = undefined;
    const length = try copySelection(observation, std.testing.allocator, range.start_row, range.start_column, range.end_row, range.end_column, 8, false, &text);
    try std.testing.expectEqualStrings("A界é", text[0..length]);
    text[0] = 99;
    try std.testing.expectError(error.TextLimit, copySelection(observation, std.testing.allocator, 0, 0, 0, 3, 8, false, text[0..1]));
    try std.testing.expectEqual(@as(u8, 99), text[0]);
    try std.testing.expectError(error.ContextChanged, copySelection(observation, std.testing.allocator, 0, 0, 0, 3, 7, false, &text));
    try std.testing.expectEqual(@as(u8, 99), text[0]);
    try std.testing.expectError(error.InvalidArgument, expandSelection(observation, 0, 0, 0, 0, 8, false, &range));
}

test "native link and row copies reject capacity without writes and interaction tags are stable" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("\x1b]8;;https://example.invalid/x\x07界\x1b]8;;\x07\x1b[?1003h\x1b[?1016h\x1b[?1004h\x1b[?1007h")).stateChanged());
    const observation = terminal.observation();
    var uri: [64]u8 = undefined;
    uri[0] = 77;
    var required: usize = 0;
    try std.testing.expectError(error.BufferTooSmall, copyHyperlink(observation, 0, 0, 1, 8, false, uri[0..1], &required));
    try std.testing.expectEqual(@as(usize, "https://example.invalid/x".len), required);
    try std.testing.expectEqual(@as(u8, 77), uri[0]);
    try copyHyperlink(observation, 0, 0, 1, 8, false, &uri, &required);
    try std.testing.expectEqualStrings("https://example.invalid/x", uri[0..required]);
    var rows: [2]c.hvt_row_shape = undefined;
    rows[0].content_end_exclusive = 77;
    try std.testing.expectError(error.BufferTooSmall, copyRowShapes(observation, 0, rows[0..1]));
    try std.testing.expectEqual(@as(u16, 77), rows[0].content_end_exclusive);
    try std.testing.expectEqual(@as(usize, 2), try copyRowShapes(observation, 0, &rows));
    try std.testing.expectEqual(@as(u16, 2), rows[0].content_end_exclusive);
    const facts = interaction(observation);
    try std.testing.expectEqual(@as(u8, c.HVT_TRACK_ANY_EVENT), facts.mouse_tracking);
    try std.testing.expectEqual(@as(u8, c.HVT_MOUSE_SGR_PIXEL), facts.mouse_protocol);
    try std.testing.expectEqual(@as(u32, c.HVT_INTERACTION_ALTERNATE_SCROLL | c.HVT_INTERACTION_FOCUS_REPORTING), facts.flags);
    // The URI copy is independent of subsequent owner mutation.
    try std.testing.expect((try terminal.feed("\x1b[2J")).stateChanged());
    try std.testing.expectEqualStrings("https://example.invalid/x", uri[0..required]);
}

fn allocationQuery(allocator: std.mem.Allocator, observation: *const Terminal.Observation) !void {
    var match: SearchMatchInfo = undefined;
    try search(observation, allocator, "界", false, false, 0, 0, &match);
    try std.testing.expect(match.found == 1);
}
test "native search allocation failures release each completed scratch allocation" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("A界")).stateChanged());
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationQuery, .{terminal.observation()});
}

test "native row bounds preserve scalar semantics for clusters and history" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 4, 12, 6);
    defer terminal.deinit();
    // zig-audit: acknowledge discard
    // reason: This proof checks canonical scalar/history content; feed summary counters are independently covered by VT.
    _ = try terminal.feed("\x1b[1;2HA\xcc\x81\x1b[2;6H\xe4\xb8\xad\x1b[3;9H \xcc\x81\x1b[4;3H\xf0\x9f\x91\xa9\xe2\x80\x8d\xf0\x9f\x92\xbb");
    for (0..2) |_| {
        const view = terminal.semanticView(0);
        for (0..view.rows) |row_index| {
            const row: u16 = @intCast(row_index);
            var expected_content: ?u16 = null;
            var expected_search: ?u16 = null;
            for (0..view.cols) |column_index| {
                const column: u16 = @intCast(column_index);
                const cell = view.cellInfoAt(row, column);
                if (cell.x != 0 or cell.y != 0) continue;
                var storage: [maximum_cell_scalars]u21 = undefined;
                const scalars = view.cellScalarsAt(row, column, &storage);
                if (scalars.len != 0 and scalars[0] != ' ')
                    expected_content = @intCast(@min(@as(u32, view.cols - 1), @as(u32, column) + @max(@as(u32, cell.width), 1) - 1));
                if (scalars.len != 0 and !cell.attrs.invisible) expected_search = column;
            }
            try std.testing.expectEqual(expected_content, nativeLastContentColumn(&view, row));
            try std.testing.expectEqual(expected_search, nativeLastSearchColumn(&view, row));
        }
        // zig-audit: acknowledge discard
        // reason: This proof checks canonical scalar/history content; feed summary counters are independently covered by VT.
        _ = try terminal.feed("\r\n\x1b[8mhidden\x1b[0m\r\n");
    }
    const history = terminal.semanticView(1);
    try std.testing.expect(history.history_count != 0);
    for (0..history.rows) |row_index| {
        const row: u16 = @intCast(row_index);
        var expected: ?u16 = null;
        for (0..history.cols) |column_index| {
            const column: u16 = @intCast(column_index);
            const cell = history.cellInfoAt(row, column);
            if (cell.x != 0 or cell.y != 0) continue;
            var storage: [maximum_cell_scalars]u21 = undefined;
            const scalars = history.cellScalarsAt(row, column, &storage);
            if (scalars.len != 0 and scalars[0] != ' ')
                expected = @intCast(@min(@as(u32, history.cols - 1), @as(u32, column) + @max(@as(u32, cell.width), 1) - 1));
        }
        try std.testing.expectEqual(expected, nativeLastContentColumn(&history, row));
    }
}

test "native word traversal skips tall-cell continuations across a soft wrap in both directions" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("\x1b]66;s=2:w=2:n=1:d=2:v=1:h=2;Hi\x07abcde")).stateChanged());
    var view = terminal.semanticView(0);
    try std.testing.expect(view.rowWrapped(0));
    try std.testing.expectEqual(@as(u8, 1), view.cellInfoAt(1, 0).y);
    try std.testing.expectEqual(@as(u21, 'e'), view.cellAt(1, 4));
    var range: SelectionRangeInfo = undefined;
    try expandSelection(terminal.observation(), c.HVT_SELECTION_WORD, 0, 0, 4, 8, false, &range);
    try std.testing.expect(range.found == 1 and range.start_row == 0 and range.start_column == 0 and range.end_row == 1 and range.end_column == 4);
    var text: [32]u8 = undefined;
    var length = try copySelection(terminal.observation(), std.testing.allocator, range.start_row, range.start_column, range.end_row, range.end_column, 8, false, &text);
    try std.testing.expectEqualStrings("Hiabcde", text[0..length]);
    // The lower-row fragment must not jump backward past a real space boundary.
    try std.testing.expect((try terminal.feed("\x1b[2J\x1b[H\x1b]66;s=2:w=2:n=1:d=2:v=1:h=2;Hi\x07a bcde")).stateChanged());
    view = terminal.semanticView(0);
    try std.testing.expect(view.rowWrapped(0));
    try std.testing.expectEqual(@as(u8, 1), view.cellInfoAt(1, 0).y);
    try expandSelection(terminal.observation(), c.HVT_SELECTION_WORD, 0, 1, 4, 8, false, &range);
    try std.testing.expect(range.found == 1 and range.start_row == 0 and range.start_column == 6 and range.end_row == 1 and range.end_column == 5);
    length = try copySelection(terminal.observation(), std.testing.allocator, range.start_row, range.start_column, range.end_row, range.end_column, 8, false, &text);
    try std.testing.expectEqualStrings("bcde", text[0..length]);
    var forward: SelectionRangeInfo = undefined;
    try expandSelection(terminal.observation(), c.HVT_SELECTION_WORD, 0, 0, 6, 8, false, &forward);
    try std.testing.expectEqualDeep(range, forward);
}

test "native saved selection context rejects another screen bank and evicted history" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 1, 4, 2);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("A")).stateChanged());
    var output: [32]u8 = undefined;
    output[0] = 77;
    try std.testing.expect((try terminal.feed("\x1b[?1049h")).stateChanged());
    try std.testing.expectError(error.ContextChanged, copySelection(terminal.observation(), std.testing.allocator, 0, 0, 0, 0, 4, false, &output));
    try std.testing.expectEqual(@as(u8, 77), output[0]);
    var range: SelectionRangeInfo = undefined;
    try std.testing.expectError(error.ContextChanged, expandSelection(terminal.observation(), c.HVT_SELECTION_WORD, 0, 0, 0, 4, false, &range));
    try std.testing.expect((try terminal.feed("\x1b[?1049l\r\nB\r\nC\r\nD\r\n")).stateChanged());
    try std.testing.expect(terminal.semanticView(0).history_row_base > 0);
    try std.testing.expectError(error.InvalidRange, copySelection(terminal.observation(), std.testing.allocator, 0, 0, 0, 0, 4, false, &output));
    try std.testing.expectEqual(@as(u8, 77), output[0]);
    try std.testing.expectError(error.ContextChanged, expandSelection(terminal.observation(), c.HVT_SELECTION_WORD, 0, 0, 0, 4, false, &range));
}

test "native forward and reverse origins preserve soft-wrapped wide-cell coordinates" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 4);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("a界bX")).stateChanged());
    try std.testing.expect(terminal.semanticView(0).rowWrapped(0));
    var match: SearchMatchInfo = undefined;
    try search(terminal.observation(), std.testing.allocator, "界", false, true, 0, 0, &match);
    try std.testing.expect(match.found == 1 and match.row == 0 and match.start_column == 1 and match.end_column == 2);
    try search(terminal.observation(), std.testing.allocator, "界", true, true, 1, 0, &match);
    try std.testing.expect(match.found == 1 and match.row == 0 and match.start_column == 1 and match.end_column == 2);
    try search(terminal.observation(), std.testing.allocator, "a", false, true, 0, 0, &match);
    try std.testing.expect(match.found == 0 and match.complete == 1);
    try search(terminal.observation(), std.testing.allocator, "b", false, true, 0, 2, &match);
    try std.testing.expect(match.found == 1 and match.start_column == 3 and match.end_column == 3);
    try search(terminal.observation(), std.testing.allocator, "a", true, true, 0, 1, &match);
    try std.testing.expect(match.found == 1 and match.start_column == 0 and match.end_column == 0);
}

test "native visible text preserves printed spaces, concealment and scalar-bounded prefixes" {
    const Fixture = struct { rows: u16, columns: u16, input: []const u8, expected: []const u8, changed: bool = true };
    const cases = [_]Fixture{
        .{ .rows = 5, .columns = 16, .input = "Á中\x1b[8mSECRET\x1b[0mB\r\n\r\nX", .expected = "Á中      B\n\nX" },
        .{ .rows = 3, .columns = 4, .input = "ABCD E", .expected = "ABCD\n E" },
        .{ .rows = 3, .columns = 8, .input = "A \r\n\x1b[8mhidden\x1b[0m", .expected = "A " },
        .{ .rows = 2, .columns = 8, .input = "\x1b]66;s=2:w=2:n=1:d=2:v=1:h=2;Hi\x07abcde", .expected = "Hiabcd\ne" },
        .{ .rows = 3, .columns = 8, .input = "\x1b[2J", .expected = "", .changed = false },
    };
    for (cases) |fixture| {
        var value = try Terminal.init(std.testing.allocator, fixture.rows, fixture.columns);
        defer value.deinit();
        try std.testing.expectEqual(fixture.changed, (try value.feed(fixture.input)).stateChanged());
        const view = value.semanticView(0);
        const expected = fixture.expected;
        var output: [64]u8 = @splat(0xa5);
        for (0..expected.len + 1) |capacity| {
            @memset(&output, 0xa5);
            const result = try writeVisibleText(&view, output[0..capacity]);
            var prefix: usize = 0;
            while (prefix < expected.len) {
                const count = try std.unicode.utf8ByteSequenceLength(expected[prefix]);
                if (count > capacity - prefix) break;
                prefix += count;
            }
            try std.testing.expectEqual(prefix, result.bytes_written);
            try std.testing.expectEqual(prefix < expected.len, result.truncated);
            try std.testing.expectEqualStrings(expected[0..prefix], output[0..result.bytes_written]);
            try std.testing.expect(std.unicode.utf8ValidateSlice(output[0..result.bytes_written]));
            for (output[result.bytes_written..]) |byte| try std.testing.expectEqual(@as(u8, 0xa5), byte);
        }
        // The completed projection survives canonical mutation.
        try std.testing.expect((try value.feed("\x1b[2JZ")).stateChanged());
        try std.testing.expectEqualStrings(expected, output[0..expected.len]);
    }
}

test "native viewport text and row shapes preserve history, alternate screen and row bounds" {
    var value = try Terminal.initWithHistory(std.testing.allocator, 2, 8, 6);
    defer value.deinit();
    try std.testing.expect((try value.feed("one\r\ntwo\r\nthree")).stateChanged());
    const history = value.semanticView(1);
    const live = value.semanticView(0);
    var output: [64]u8 = undefined;
    var result = try writeVisibleText(&history, &output);
    try std.testing.expectEqualStrings("one\ntwo", output[0..result.bytes_written]);
    result = try writeVisibleText(&live, &output);
    try std.testing.expectEqualStrings("two\nthree", output[0..result.bytes_written]);
    const shape = try rowShape(&history, 0);
    try std.testing.expectEqual(@as(u16, 3), shape.content_end_exclusive);
    try std.testing.expectEqual(@as(u8, 0), shape.wrapped);
    try std.testing.expectError(error.InvalidArgument, rowShape(&live, live.rows));
    try std.testing.expect((try value.feed("\x1b[?1049hALT")).stateChanged());
    const alternate = value.semanticView(6);
    result = try writeVisibleText(&alternate, &output);
    try std.testing.expectEqualStrings("ALT", output[0..result.bytes_written]);
    try std.testing.expect(alternate.is_alternate_screen and alternate.history_offset == 0);
}
