//! Bounded host controls: UTF-8 editing, stable list viewports and shared row geometry.
const std = @import("std");
const layout = @import("layout.zig");

/// Field syntax checked before mutation; complete values remain configuration policy.
pub const Kind = enum { text, number, color };
/// Byte cursor over caller-owned UTF-8 storage. No allocation or borrowed retained text.
pub const Text = struct {
    cursor: usize = 0,
    scroll: f32 = 0,
    select_all: bool = false,
    kind: Kind = .text,

    /// Inserts a complete commit atomically, replacing an explicit whole-field selection.
    pub fn insert(self: *Text, buffer: []u8, len: *usize, bytes: []const u8) error{ InvalidText, TextLimit }!void {
        if (!std.unicode.utf8ValidateSlice(bytes)) return error.InvalidText;
        for (bytes) |byte| if (byte < 0x20 or byte == 0x7f) return error.InvalidText;
        const start = if (self.select_all) 0 else self.cursor;
        const end = if (self.select_all) len.* else self.cursor;
        const next = len.* - (end - start) + bytes.len;
        if (next > buffer.len) return error.TextLimit;
        switch (self.kind) {
            .text => {},
            .number => for (bytes) |byte| {
                if (!std.ascii.isDigit(byte)) return error.InvalidText;
            },
            .color => {
                if (next > 7) return error.InvalidText;
                var at: usize = 0;
                for ([_][]const u8{ buffer[0..start], bytes, buffer[end..len.*] }) |part| for (part) |byte| {
                    if (if (at == 0) byte != '#' else !std.ascii.isHex(byte)) return error.InvalidText;
                    at += 1;
                };
            },
        }
        std.mem.copyBackwards(u8, buffer[start + bytes.len .. next], buffer[end..len.*]);
        @memcpy(buffer[start..][0..bytes.len], bytes);
        len.* = next;
        self.cursor = start + bytes.len;
        self.select_all = false;
    }
    /// Moves over complete scalars; an existing whole-field selection collapses first.
    pub fn move(self: *Text, bytes: []const u8, direction: i8) void {
        if (self.select_all) {
            self.cursor = if (direction < 0) 0 else bytes.len;
            self.select_all = false;
            return;
        }
        if (direction < 0 and self.cursor > 0) {
            self.cursor -= 1;
            while (self.cursor > 0 and bytes[self.cursor] & 0xc0 == 0x80) self.cursor -= 1;
        } else if (direction > 0 and self.cursor < bytes.len) {
            self.cursor += 1;
            while (self.cursor < bytes.len and bytes[self.cursor] & 0xc0 == 0x80) self.cursor += 1;
        }
    }
    /// Removes one scalar on either side, or the explicitly selected complete field.
    pub fn erase(self: *Text, buffer: []u8, len: *usize, forward: bool) void {
        if (self.select_all) {
            len.* = 0;
            self.* = .{ .kind = self.kind };
            return;
        }
        const old = self.cursor;
        self.move(buffer[0..len.*], if (forward) 1 else -1);
        const start = @min(old, self.cursor);
        const end = @max(old, self.cursor);
        std.mem.copyForwards(u8, buffer[start .. len.* - (end - start)], buffer[end..len.*]);
        len.* -= end - start;
        self.cursor = start;
    }
    /// Keeps the measured caret visible after edits and window resizes.
    pub fn reveal(self: *Text, caret: f32, width: f32, available: f32) f32 {
        const space = @max(1, available);
        self.scroll = @min(self.scroll, @max(0, width - space));
        if (caret < self.scroll) self.scroll = caret;
        if (caret > self.scroll + space) self.scroll = caret - space;
        return self.scroll;
    }
};
/// Selection, hover and viewport are separate; scrolling never leaves Enter off-screen.
pub const List = struct {
    selected: usize = 0,
    first: usize = 0,
    hovered: ?usize = null,

    /// Reconciles keyboard selection with result filtering or a changed visible row count.
    pub fn reveal(self: *List, count: usize, visible: usize) void {
        const rows = @max(1, visible);
        self.selected = @min(self.selected, count -| 1);
        self.first = @min(self.first, count -| rows);
        if (self.selected < self.first) self.first = self.selected;
        if (self.selected >= self.first + rows) self.first = self.selected - rows + 1;
        if (self.hovered) |hover| if (hover < self.first or hover >= @min(count, self.first + rows)) {
            self.hovered = null;
        };
    }
    /// Moves only the viewport until it would hide the keyboard selection.
    pub fn scroll(self: *List, delta: i32, count: usize, visible: usize) void {
        const rows = @max(1, visible);
        self.first = @min(self.first, count -| rows);
        self.first = if (delta < 0) self.first -| @as(usize, @intCast(-@as(i64, delta))) else @min(count -| rows, self.first +| @as(usize, @intCast(delta)));
        self.selected = std.math.clamp(self.selected, self.first, @min(count -| 1, self.first + rows - 1));
        self.hovered = null;
    }
};
/// One geometry owner serves painting, pointer hits and page navigation.
pub const Rows = struct {
    rect: layout.Rect,
    stride: f32,
    gap: f32 = 2,

    /// Number of complete rows, bounded below for tiny windows.
    pub fn visible(self: Rows) usize {
        return @max(1, @as(usize, @intFromFloat(@floor(@max(0, self.rect.height) / self.stride))));
    }
    /// Exact painted row, excluding its gap.
    pub fn row(self: Rows, index: usize) layout.Rect {
        return .{ .x = self.rect.x, .y = self.rect.y + @as(f32, @floatFromInt(index)) * self.stride, .width = self.rect.width, .height = @max(1, self.stride - self.gap) };
    }
    /// Rejects blank remainder and gaps rather than selecting an invisible entry.
    pub fn hit(self: Rows, x: f32, y: f32) ?usize {
        if (!self.rect.contains(x, y)) return null;
        const index: usize = @intFromFloat(@floor((y - self.rect.y) / self.stride));
        return if (index < self.visible() and self.row(index).contains(x, y)) index else null;
    }
};

test "shared text editing is atomic, scalar safe, bounded and constrained by field syntax" {
    var buffer: [16]u8 = undefined;
    var len: usize = 0;
    var text: Text = .{};
    try text.insert(&buffer, &len, "a界z");
    text.move(buffer[0..len], -1);
    text.move(buffer[0..len], -1);
    try text.insert(&buffer, &len, "é");
    try std.testing.expectEqualStrings("aé界z", buffer[0..len]);
    text.erase(&buffer, &len, true);
    try std.testing.expectEqualStrings("aéz", buffer[0..len]);
    try std.testing.expectError(error.InvalidText, text.insert(&buffer, &len, "\xff"));
    try std.testing.expectError(error.TextLimit, text.insert(&buffer, &len, "0123456789012345"));
    try std.testing.expectEqualStrings("aéz", buffer[0..len]);
    text.select_all = true;
    text.kind = .color;
    try text.insert(&buffer, &len, "#123456");
    try std.testing.expectError(error.InvalidText, text.insert(&buffer, &len, "x"));
    try std.testing.expectEqualStrings("#123456", buffer[0..len]);
    text.select_all = true;
    text.kind = .number;
    try std.testing.expectError(error.InvalidText, text.insert(&buffer, &len, "23x"));
    try text.insert(&buffer, &len, "23");
    try std.testing.expectEqualStrings("23", buffer[0..len]);
}
test "shared rows preserve hit geometry and viewport through filtering, wheel and resize" {
    const rows: Rows = .{ .rect = .{ .x = 10, .y = 20, .width = 300, .height = 150 }, .stride = 48, .gap = 4 };
    try std.testing.expectEqual(@as(usize, 3), rows.visible());
    try std.testing.expectEqual(@as(?usize, 1), rows.hit(20, 70));
    try std.testing.expectEqual(@as(?usize, null), rows.hit(20, 65));
    try std.testing.expectEqual(@as(?usize, null), rows.hit(20, 168));
    var list: List = .{};
    list.selected = 4;
    list.reveal(100, rows.visible());
    try std.testing.expectEqual(@as(usize, 2), list.first);
    list.scroll(30, 100, rows.visible());
    try std.testing.expectEqual(@as(usize, 32), list.selected);
    list.reveal(1, 10);
    try std.testing.expectEqual(@as(usize, 0), list.first);
    try std.testing.expectEqual(@as(usize, 0), list.selected);
}
