//! Proves deterministic layout and native-owner control flow without opening a window.

const std = @import("std");
const cli = @import("cli.zig");
const layout = @import("layout.zig");
const Window = @import("window.zig").Window;
const terminal = @import("terminal.zig");

test "horizontal first tab and single second tab are exact" {
    var value = try layout.Layout.init(.horizontal, .{ .width = 81, .height = 24 });
    const first = try value.snapshot();
    try std.testing.expectEqual(@as(u2, 2), first.count);
    try std.testing.expectEqual(layout.TerminalId.first, first.placements[0].terminal);
    try std.testing.expectEqual(@as(u16, 40), first.placements[0].rect.width);
    try std.testing.expectEqual(@as(u16, 41), first.placements[1].rect.width);
    try std.testing.expectEqual(@as(u16, 40), first.placements[1].rect.x);

    const second = try value.selectTab(1);
    try std.testing.expectEqual(@as(u2, 1), second.count);
    try std.testing.expectEqual(layout.TerminalId.third, second.placements[0].terminal);
    try std.testing.expectEqual(layout.Rect{
        .x = 0,
        .y = 0,
        .width = 81,
        .height = 24,
    }, second.placements[0].rect);
}

test "vertical split and impossible resize rollback are exact" {
    var value = try layout.Layout.init(.vertical, .{ .width = 80, .height = 25 });
    const snapshot = try value.snapshot();
    try std.testing.expectEqual(@as(u16, 12), snapshot.placements[0].rect.height);
    try std.testing.expectEqual(@as(u16, 13), snapshot.placements[1].rect.height);
    try std.testing.expectEqual(@as(u16, 12), snapshot.placements[1].rect.y);
    try std.testing.expectError(
        error.invalid_size,
        value.resize(.{ .width = 80, .height = 1 }),
    );
    try std.testing.expectEqualDeep(snapshot, try value.snapshot());
}

test "hidden focus, maximum size, generation exhaustion, and reuse are exact" {
    var value = try layout.Layout.init(.horizontal, .{
        .width = std.math.maxInt(u16),
        .height = std.math.maxInt(u16),
    });
    const snapshot = try value.snapshot();
    try std.testing.expectEqual(
        std.math.maxInt(u16),
        snapshot.placements[0].rect.width + snapshot.placements[1].rect.width,
    );
    try std.testing.expectError(error.terminal_hidden, value.focus(.third));
    value.generation = std.math.maxInt(u64);
    try std.testing.expectError(error.generation_exhausted, value.selectTab(1));
    value.generation = 4;
    try std.testing.expectEqual(@as(u1, 1), (try value.selectTab(1)).tab);
}

test "native window owner compiles as a concrete type" {
    try std.testing.expectEqualStrings("font.ttf", try cli.fontPath(&.{ "host", "font.ttf" }));
    try std.testing.expect(@sizeOf(Window) > 0);
    try std.testing.expect(@sizeOf(terminal.Set) > 0);
}
