const std = @import("std");
const screen_mod = @import("../../../src/screen.zig");
const history_mod = @import("../../../src/screen/history.zig");
const resize_mod = @import("../../../src/screen/resize.zig");
const semantic_event = @import("../../../src/semantic_event.zig");

const Grid = screen_mod.Screen;
const SemanticEvent = semantic_event.SemanticEvent;

fn apply(screen: *Grid, event: SemanticEvent) void {
    screen.applyScreen(event);
}

fn canonicalLogicalStream(allocator: std.mem.Allocator, screen: *const Grid) ![]u21 {
    var snapshot = try screen.collectLogicalSnapshot(allocator);
    defer snapshot.deinit(allocator);

    var lines: std.ArrayList(u21) = .empty;
    defer lines.deinit(allocator);

    for (snapshot.logical_lines.items) |line| {
        try lines.append(allocator, 0);
        for (line.cells.items) |cell| {
            try lines.append(allocator, @intCast(cell.codepoint));
        }
    }

    return try lines.toOwnedSlice(allocator);
}

test "screen resize is transactional at every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, resizeScreenTransaction, .{});
}

test "screen resize allocation owners have exact contracts and reusable failure paths" {
    const collect: *const fn (*const Grid, std.mem.Allocator) std.mem.Allocator.Error!history_mod.LogicalSnapshot = Grid.collectLogicalSnapshot;
    const reflow: *const fn (std.mem.Allocator, history_mod.LogicalSnapshot, u16) std.mem.Allocator.Error!resize_mod.ReflowState = resize_mod.reflowLogicalLines;
    const allocate: *const fn (std.mem.Allocator, u16, u16, ?[]bool) std.mem.Allocator.Error!resize_mod.ResizeBuffers = resize_mod.allocResizeBuffers;
    try std.testing.checkAllAllocationFailures(std.testing.allocator, collectSnapshotAllocation, .{collect});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, reflowAllocation, .{reflow});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, resizeBuffersAllocation, .{allocate});
}

fn collectSnapshotAllocation(
    allocator: std.mem.Allocator,
    collect: *const fn (*const Grid, std.mem.Allocator) std.mem.Allocator.Error!history_mod.LogicalSnapshot,
) !void {
    var screen = try Grid.initWithCellsAndHistory(std.testing.allocator, 2, 4, 8);
    defer screen.deinit(std.testing.allocator);
    apply(&screen, .{ .write_text = "ABCDEFGHIJ" });

    var snapshot = collect(&screen, allocator) catch |err| {
        var retry = try collect(&screen, std.testing.allocator);
        retry.deinit(std.testing.allocator);
        return err;
    };
    snapshot.deinit(allocator);
}

fn reflowAllocation(
    allocator: std.mem.Allocator,
    reflow: *const fn (std.mem.Allocator, history_mod.LogicalSnapshot, u16) std.mem.Allocator.Error!resize_mod.ReflowState,
) !void {
    var screen = try Grid.initWithCellsAndHistory(std.testing.allocator, 2, 4, 8);
    defer screen.deinit(std.testing.allocator);
    apply(&screen, .{ .write_text = "ABCDEFGHIJ" });
    var snapshot = try screen.collectLogicalSnapshot(std.testing.allocator);
    defer snapshot.deinit(std.testing.allocator);

    var state = reflow(allocator, snapshot, 3) catch |err| {
        var retry = try reflow(std.testing.allocator, snapshot, 3);
        retry.deinit(std.testing.allocator);
        return err;
    };
    state.deinit(allocator);
}

fn resizeBuffersAllocation(
    allocator: std.mem.Allocator,
    allocate: *const fn (std.mem.Allocator, u16, u16, ?[]bool) std.mem.Allocator.Error!resize_mod.ResizeBuffers,
) !void {
    var buffers = allocate(allocator, 3, 5, null) catch |err| {
        var retry = try allocate(std.testing.allocator, 3, 5, null);
        retry.deinit(std.testing.allocator);
        return err;
    };
    buffers.deinit(allocator);
}

fn resizeScreenTransaction(allocator: std.mem.Allocator) !void {
    var screen = try Grid.initWithCellsAndHistory(allocator, 2, 4, 8);
    defer screen.deinit(allocator);
    apply(&screen, .{ .write_text = "ABCDEFGHIJ" });
    const history_cell = screen.historyRowAt(0, 0);
    const visible_cell = screen.cellAt(0, 0);

    screen.resize(allocator, 3, 3) catch |err| {
        try std.testing.expectEqual(@as(u16, 2), screen.rows);
        try std.testing.expectEqual(@as(u16, 4), screen.cols);
        try std.testing.expectEqual(history_cell, screen.historyRowAt(0, 0));
        try std.testing.expectEqual(visible_cell, screen.cellAt(0, 0));
        apply(&screen, .{ .write_text = "Z" });
        return err;
    };

    try std.testing.expectEqual(@as(u16, 3), screen.rows);
    try std.testing.expectEqual(@as(u16, 3), screen.cols);
}

test "screen resize: row-only resize preserves live bottom and restores from history" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCellsAndHistory(gpa, 4, 4, 8);
    defer s.deinit(gpa);

    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 0, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "AAAA" });
    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 1, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "BBBB" });
    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 2, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "CCCC" });
    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 3, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "PROM" });
    s.cursor.setPositionByClient(3, 3);

    try s.resize(gpa, 2, 4);

    try std.testing.expectEqual(@as(u32, 2), s.historyCount());
    try std.testing.expectEqual(@as(u21, 'B'), s.historyRowAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'A'), s.historyRowAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'C'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'P'), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u16, 1), s.cursor.row);

    try s.resize(gpa, 4, 4);

    try std.testing.expectEqual(@as(u32, 0), s.historyCount());
    try std.testing.expectEqual(@as(u16, 8), s.historyCapacity());
    try std.testing.expectEqual(@as(u21, 'A'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'C'), s.cellAt(2, 0));
    try std.testing.expectEqual(@as(u21, 'P'), s.cellAt(3, 0));
    try std.testing.expectEqual(@as(u16, 3), s.cursor.row);
}

test "screen resize: column resize reflows wrapped content into history and viewport" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCellsAndHistory(gpa, 2, 4, 8);
    defer s.deinit(gpa);

    apply(&s, SemanticEvent{ .write_text = "ABCDEFGHIJ" });

    try std.testing.expectEqual(@as(u32, 1), s.historyCount());
    try std.testing.expectEqual(@as(u21, 'A'), s.historyRowAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'D'), s.historyRowAt(0, 3));

    try s.resize(gpa, 1, 5);

    try std.testing.expectEqual(@as(u32, 1), s.historyCount());
    try std.testing.expectEqual(@as(u16, 8), s.historyCapacity());
    try std.testing.expectEqual(@as(u21, 'A'), s.historyRowAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'E'), s.historyRowAt(0, 4));
    try std.testing.expectEqual(@as(u21, 'F'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'J'), s.cellAt(0, 4));

    try s.resize(gpa, 2, 4);

    try std.testing.expectEqual(@as(u32, 1), s.historyCount());
    try std.testing.expectEqual(@as(u21, 'A'), s.historyRowAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'D'), s.historyRowAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'E'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'H'), s.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'I'), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'J'), s.cellAt(1, 1));
}

test "screen resize: column resize preserves exact-fill cursor wrap state" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCellsAndHistory(gpa, 1, 4, 4);
    defer s.deinit(gpa);

    apply(&s, SemanticEvent{ .write_text = "ABCD" });

    try std.testing.expect(s.wrap_pending);
    try std.testing.expectEqual(@as(u16, 0), s.cursor.row);
    try std.testing.expectEqual(@as(u16, 3), s.cursor.col);
    try std.testing.expectEqual(@as(u64, 3), s.cursor.position_changed_by_client_at);

    try s.resize(gpa, 1, 2);

    try std.testing.expectEqual(@as(u32, 1), s.historyCount());
    try std.testing.expectEqual(@as(u21, 'A'), s.historyRowAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), s.historyRowAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'C'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'D'), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u16, 0), s.cursor.row);
    try std.testing.expectEqual(@as(u16, 1), s.cursor.col);
    try std.testing.expect(s.wrap_pending);
    try std.testing.expectEqual(@as(u64, 3), s.cursor.position_changed_by_client_at);
}

test "screen resize: canonical logical content survives reflow when projected history saturates" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCellsAndHistory(gpa, 2, 6, 4);
    defer s.deinit(gpa);

    apply(&s, SemanticEvent{ .write_text = "AAAAAA\nBBBBBB\nCCCCCC\nDDDDDD\nEEEEEE" });
    const before = try canonicalLogicalStream(gpa, &s);
    defer gpa.free(before);

    try s.resize(gpa, 5, 3);
    try std.testing.expectEqual(@as(u32, 4), s.historyCount());

    const after = try canonicalLogicalStream(gpa, &s);
    defer gpa.free(after);

    try std.testing.expectEqualSlices(u21, before, after);
}

test "screen resize: projected history keeps the bounded tail of a hidden partial line" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCellsAndHistory(gpa, 2, 4, 2);
    defer s.deinit(gpa);

    apply(&s, SemanticEvent{ .write_text = "ABCDEFGHIJ" });
    try s.resize(gpa, 1, 3);

    try std.testing.expectEqual(@as(u32, 2), s.historyCount());
    try std.testing.expectEqual(@as(u21, 'G'), s.historyRowAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'I'), s.historyRowAt(0, 2));
    try std.testing.expectEqual(@as(u21, 'D'), s.historyRowAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'F'), s.historyRowAt(1, 2));
    try std.testing.expectEqual(@as(u21, 'J'), s.cellAt(0, 0));
}
