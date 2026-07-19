const std = @import("std");
const screen_mod = @import("../../../src/screen.zig");
const semantic_event = @import("../../../src/semantic_event.zig");

const Grid = screen_mod.Screen;
const SemanticEvent = semantic_event.SemanticEvent;

fn apply(screen: *Grid, event: SemanticEvent) void {
    screen.applyScreen(event);
}

test "screen history: initWithCells has no history by default" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    try std.testing.expectEqual(@as(u16, 0), s.history_capacity);
    try std.testing.expect(s.history == null);
}

test "screen history: initWithCellsAndHistory allocates bounded history" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCellsAndHistory(gpa, 4, 10, 100);
    defer s.deinit(gpa);
    try std.testing.expectEqual(@as(u16, 100), s.history_capacity);
    try std.testing.expect(s.history != null);
    try std.testing.expectEqual(@as(u32, 0), s.history_count);
}

test "screen history: scrollUp captures row to history" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCellsAndHistory(gpa, 2, 10, 10);
    defer s.deinit(gpa);
    apply(&s, SemanticEvent{ .write_text = "abc" });
    s.cursor.setPositionByClient(1, 0);
    apply(&s, SemanticEvent{ .write_text = "xyz" });
    s.cursor.setColByClient(0);
    apply(&s, SemanticEvent.line_feed);
    try std.testing.expectEqual(@as(u32, 1), s.history_count);
    const h = s.history.?;
    try std.testing.expectEqual(@as(u21, 'a'), @as(u21, @intCast(h[0].codepoint)));
    try std.testing.expectEqual(@as(u21, 'b'), @as(u21, @intCast(h[1].codepoint)));
    try std.testing.expectEqual(@as(u21, 'c'), @as(u21, @intCast(h[2].codepoint)));
    try std.testing.expectEqual(@as(u21, 'x'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'y'), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'z'), s.cellAt(0, 2));
}

test "screen history: capacity limits with wraparound" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCellsAndHistory(gpa, 2, 2, 2);
    defer s.deinit(gpa);
    var row_num: u21 = '1';
    var i: u16 = 0;
    while (i < 5) : (i += 1) {
        s.cursor.setPositionByClient(0, 0);
        for (0..2) |_| apply(&s, SemanticEvent{ .write_codepoint = row_num });
        if (i < 4) {
            s.cursor.setRowByClient(1);
            apply(&s, SemanticEvent.line_feed);
        }
        row_num += 1;
    }
    try std.testing.expectEqual(@as(u32, 2), s.history_count);
    try std.testing.expectEqual(@as(u21, '4'), s.historyRowAt(0, 0));
    try std.testing.expectEqual(@as(u21, '4'), s.historyRowAt(0, 1));
    try std.testing.expectEqual(@as(u21, '3'), s.historyRowAt(1, 0));
    try std.testing.expectEqual(@as(u21, '3'), s.historyRowAt(1, 1));
}

test "screen history: reset does not truncate history" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCellsAndHistory(gpa, 2, 5, 10);
    defer s.deinit(gpa);
    apply(&s, SemanticEvent{ .write_text = "test1" });
    s.cursor.setRowByClient(1);
    apply(&s, SemanticEvent.line_feed);
    try std.testing.expectEqual(@as(u32, 1), s.history_count);
    s.reset();
    try std.testing.expectEqual(@as(u32, 1), s.history_count);
}

test "screen history: ED 3 clears scrollback history" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCellsAndHistory(gpa, 2, 4, 8);
    defer s.deinit(gpa);
    apply(&s, SemanticEvent{ .write_text = "AAAA\nBBBB\nCCCC" });
    try std.testing.expect(s.historyCount() > 0);
    apply(&s, SemanticEvent{ .erase_display_scrollback = false });
    try std.testing.expectEqual(@as(u32, 0), s.historyCount());
}
