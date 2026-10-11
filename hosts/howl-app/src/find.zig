const std = @import("std");
const instance = @import("howl_instance");
const selection = @import("selection.zig");
const vt = instance.Terminal;

/// Maximum owned literal query bytes.
pub const query_limit = 255;
/// Maximum retained copied matches before explicit incomplete status.
pub const match_limit = 512;
const rows_per_turn = 4;
const row_byte_limit = instance.render.limits.maximum_columns * 24 * 4;
/// Exact local literal query and canonical row/context failures.
pub const Error = error{ InvalidQuery, InvalidSearchContext, RowTooLarge };
/// Query bytes are copied inline at FIFO admission; no text borrow escapes the caller.
pub const Request = struct {
    serial: u64,
    kind: enum { query, next, previous, close },
    bytes: [query_limit]u8 = undefined,
    len: u16 = 0,

    /// Validates and copies one exact UTF-8 literal query.
    pub fn query(serial: u64, text: []const u8) Error!Request {
        if (text.len > query_limit or !std.unicode.utf8ValidateSlice(text)) return error.InvalidQuery;
        var result: Request = .{ .serial = serial, .kind = .query, .len = @intCast(text.len) };
        @memcpy(result.bytes[0..text.len], text);
        return result;
    }
};
/// Incomplete means the match cap was reached; stale never claims current canonical results.
pub const Phase = enum { idle, scanning, complete, incomplete, stale, failed };
/// Copied query progress and navigation facts; no result-array or row borrow.
pub const Status = struct {
    serial: u64 = 0,
    phase: Phase = .idle,
    count: u16 = 0,
    current: ?u16 = null,
    scanned: u32 = 0,
    total: u32 = 0,
    failure: ?Error = null,
};
/// Worker-local bounded incremental search over one canonical revision and retained domain.
pub const Find = struct {
    request: Request = .{ .serial = 0, .kind = .close },
    status: Status = .{},
    context: selection.Context = undefined,
    revision: u64 = 0,
    matches: [match_limit]selection.Range = undefined,

    /// Starts fresh without allocating or retaining the observation.
    pub fn begin(self: *Find, observation: *const vt.Observation, request: Request) Error!void {
        self.status = .{ .serial = request.serial };
        if (request.len > request.bytes.len or !std.unicode.utf8ValidateSlice(request.bytes[0..request.len])) return error.InvalidQuery;
        self.request = request;
        const context = selection.Context.fromView(observation.semanticView(0));
        const total = @as(u64, if (context.alternate) 0 else context.history_count) + context.rows;
        const first: u64 = if (context.alternate) 0 else context.history_row_base;
        if (total == 0 or first + total - 1 > std.math.maxInt(i32) or context.columns == 0 or context.columns > instance.render.limits.maximum_columns) return error.InvalidSearchContext;
        self.context = context;
        self.revision = observation.semanticSequence();
        self.status = .{ .serial = request.serial, .phase = if (request.len == 0) .idle else .scanning, .total = @intCast(total) };
    }
    /// Names a stopped query's exact error without faulting canonical service.
    pub fn fail(self: *Find, failure: Error) void {
        self.status.phase = .failed;
        self.status.failure = failure;
    }
    /// Services at most four rows; a changed canonical cut invalidates instead of mixing results.
    pub fn step(self: *Find, observation: *const vt.Observation) Error!bool {
        if (self.status.phase == .idle or self.status.phase == .failed or self.status.phase == .stale) return false;
        if (self.revision != observation.semanticSequence()) {
            self.status.phase = .stale;
            return true;
        }
        if (self.status.phase != .scanning) return false;
        const first: i64 = if (self.context.alternate) 0 else self.context.history_row_base;
        const top = first + (if (self.context.alternate) @as(i64, 0) else self.context.history_count);
        var served: u8 = 0;
        while (self.status.scanned < self.status.total and served < rows_per_turn) : (served += 1) {
            const absolute = first + self.status.scanned;
            const view = observation.semanticView(@intCast(@max(0, top - absolute)));
            const row: u16 = @intCast(@max(0, absolute - top));
            if (row >= view.rows) return error.InvalidSearchContext;
            try self.scanRow(view, row);
            self.status.scanned += 1;
            if (self.status.phase == .incomplete) return true;
        }
        if (self.status.scanned == self.status.total) self.status.phase = .complete;
        return true;
    }
    fn scanRow(self: *Find, view: vt.SemanticView, row: u16) Error!void {
        var last: u16 = view.cols;
        while (last != 0) {
            const cell = view.cellInfoAt(row, last - 1);
            if (cell.x == 0 and cell.y == 0 and cell.codepoint != 0 and !cell.attrs.invisible) break;
            last -= 1;
        }
        if (last == 0) return;
        var bytes: [row_byte_limit]u8 = undefined;
        var columns: [row_byte_limit]u16 = undefined;
        var len: usize = 0;
        for (0..last) |index| {
            const column: u16 = @intCast(index);
            const cell = view.cellInfoAt(row, column);
            if (cell.x != 0 or cell.y != 0) continue;
            var storage: [24]u21 = undefined;
            const scalars = if (cell.attrs.invisible) &.{} else view.cellScalarsAt(row, column, &storage);
            if (scalars.len == 0) {
                if (len == bytes.len) return error.RowTooLarge;
                bytes[len] = ' ';
                columns[len] = column;
                len += 1;
            } else for (scalars) |scalar| {
                var encoded: [4]u8 = undefined;
                const count = std.unicode.utf8Encode(scalar, &encoded) catch return error.InvalidSearchContext;
                if (count > bytes.len - len) return error.RowTooLarge;
                @memcpy(bytes[len..][0..count], encoded[0..count]);
                @memset(columns[len..][0..count], column);
                len += count;
            }
        }
        const query = self.request.bytes[0..self.request.len];
        var cursor: usize = 0;
        while (cursor + query.len <= len) {
            const relative = std.mem.indexOf(u8, bytes[cursor..len], query) orelse break;
            const found = cursor + relative;
            var range = selection.start(view, row, columns[found]) catch return error.InvalidSearchContext;
            range.focus = selection.point(view, row, columns[found + query.len - 1]) catch return error.InvalidSearchContext;
            if (self.status.count == 0 or !std.meta.eql(self.matches[self.status.count - 1], range)) {
                if (self.status.count == match_limit) {
                    self.status.phase = .incomplete;
                    return;
                }
                self.matches[self.status.count] = range;
                self.status.count += 1;
            }
            cursor = found + 1;
        }
    }
    /// Moves within retained results, wrapping only through known matches.
    pub fn navigate(self: *Find, serial: u64, reverse: bool) ?selection.Range {
        self.status.serial = serial;
        self.request.serial = serial;
        if (self.status.count == 0 or self.status.phase == .stale or self.status.phase == .failed) return null;
        const current = self.status.current;
        const next: u16 = if (current) |index|
            if (reverse) (if (index == 0) self.status.count - 1 else index - 1) else (if (index + 1 == self.status.count) 0 else index + 1)
        else if (reverse) self.status.count - 1 else 0;
        self.status.current = next;
        return self.matches[next];
    }
};

test "find exact visual-row literals preserve Unicode columns conceal filtering and multiple matches" {
    var terminal = try vt.init(std.testing.allocator, 4, 24);
    defer terminal.deinit();
    // zig-audit: acknowledge discard
    // reason: The proof checks copied matches and canonical extraction; parser counters do not affect these assertions.
    _ = try terminal.feed("alpha alpha\r\nwide: \xe7\x95\x8c e\xcc\x81\r\n\x1b[8msecret\x1b[0m visible");
    var find: Find = .{};
    try find.begin(terminal.observation(), try Request.query(1, "alpha"));
    try std.testing.expect(try find.step(terminal.observation()));
    try std.testing.expectEqual(Phase.complete, find.status.phase);
    try std.testing.expectEqual(@as(u16, 2), find.status.count);
    try std.testing.expectEqual(@as(u16, 0), find.navigate(2, false).?.anchor.col);
    try std.testing.expectEqual(@as(u16, 6), find.navigate(3, false).?.anchor.col);
    try std.testing.expectEqual(@as(u16, 0), find.navigate(4, false).?.anchor.col);
    try find.begin(terminal.observation(), try Request.query(5, "\xe7\x95\x8c e\xcc\x81"));
    try std.testing.expect(try find.step(terminal.observation()));
    const selected = find.navigate(6, true).?;
    const text = try selected.copy(terminal.observation(), std.testing.allocator, 128);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("\xe7\x95\x8c e\xcc\x81", text);
    try find.begin(terminal.observation(), try Request.query(7, "secret"));
    try std.testing.expect(try find.step(terminal.observation()));
    try std.testing.expectEqual(@as(u16, 0), find.status.count);
    try std.testing.expectError(error.InvalidQuery, Request.query(8, "\xff"));
    const too_long: [query_limit + 1]u8 = @splat('x');
    try std.testing.expectError(error.InvalidQuery, Request.query(9, &too_long));
    try find.begin(terminal.observation(), try Request.query(10, "alpha\nwide"));
    try std.testing.expect(try find.step(terminal.observation()));
    try std.testing.expectEqual(@as(u16, 0), find.status.count);
}
test "incremental find bounds work and retained results then marks canonical mutation stale" {
    var terminal = try vt.init(std.testing.allocator, 8, 80);
    defer terminal.deinit();
    // zig-audit: acknowledge discard
    // reason: Find owns only copied query/result facts; the assertions inspect exact scan bounds and staleness.
    _ = try terminal.feed("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\r\nxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\r\nxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\r\nxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\r\nxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\r\nxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\r\nxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\r\nxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx");
    var find: Find = .{};
    try find.begin(terminal.observation(), try Request.query(1, "x"));
    try std.testing.expect(try find.step(terminal.observation()));
    try std.testing.expectEqual(@as(u32, 4), find.status.scanned);
    try std.testing.expectEqual(Phase.scanning, find.status.phase);
    try std.testing.expect(try find.step(terminal.observation()));
    try std.testing.expectEqual(Phase.incomplete, find.status.phase);
    try std.testing.expectEqual(@as(u16, match_limit), find.status.count);
    // zig-audit: acknowledge discard
    // reason: One canonical write is enough to invalidate the old search cut; its parser counters are not search authority.
    _ = try terminal.feed("\rchanged");
    try std.testing.expect(try find.step(terminal.observation()));
    try std.testing.expectEqual(Phase.stale, find.status.phase);
    try std.testing.expect(find.navigate(2, false) == null);
}
