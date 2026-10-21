//! Bounded host controls: UTF-8 editing, stable list viewports and shared row geometry.
const std = @import("std");
const layout = @import("layout.zig");

/// Field syntax checked before mutation; complete values remain configuration policy.
pub const Kind = enum { text, number, color };
/// Byte cursor over caller-owned UTF-8 storage. No allocation or borrowed retained text.
pub const Text = struct {
    cursor: usize = 0,
    scroll: f32 = 0,
    anchor: ?usize = null,
    kind: Kind = .text,

    /// Inserts a complete commit atomically, replacing an explicit whole-field selection.
    pub fn insert(self: *Text, buffer: []u8, len: *usize, bytes: []const u8) error{ InvalidText, TextLimit }!void {
        if (!std.unicode.utf8ValidateSlice(bytes)) return error.InvalidText;
        for (bytes) |byte| if (byte < 0x20 or byte == 0x7f) return error.InvalidText;
        const range = self.selected() orelse Range{ .start = self.cursor, .end = self.cursor };
        const start = range.start;
        const end = range.end;
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
        if (bytes.len > end - start) std.mem.copyBackwards(u8, buffer[start + bytes.len .. next], buffer[end..len.*]) else std.mem.copyForwards(u8, buffer[start + bytes.len .. next], buffer[end..len.*]);
        @memcpy(buffer[start..][0..bytes.len], bytes);
        len.* = next;
        self.cursor = start + bytes.len;
        self.anchor = null;
    }
    /// Byte range in logical order; an empty range has no selected text.
    pub const Range = struct { start: usize, end: usize };
    /// Borrows no bytes and retains an anchor across repeated Shift gestures.
    pub fn selected(self: Text) ?Range {
        const anchor = self.anchor orelse return null;
        return if (anchor == self.cursor) null else .{ .start = @min(anchor, self.cursor), .end = @max(anchor, self.cursor) };
    }
    /// Selects the complete caller-owned field.
    pub fn selectAll(self: *Text, len: usize) void {
        self.anchor = 0;
        self.cursor = len;
    }
    /// Moves to a known scalar boundary, optionally extending an existing selection.
    pub fn jump(self: *Text, point: usize, extend: bool) void {
        if (extend) {
            if (self.anchor == null) self.anchor = self.cursor;
        } else self.anchor = null;
        self.cursor = point;
    }
    /// Plain arrow movement collapses a selection before moving further.
    pub fn move(self: *Text, bytes: []const u8, direction: i8) void {
        self.navigate(bytes, direction, false);
    }
    /// Extends or reverses selection by complete UTF-8 scalars.
    pub fn navigate(self: *Text, bytes: []const u8, direction: i8, extend: bool) void {
        if (!extend) if (self.selected()) |range| {
            self.jump(if (direction < 0) range.start else range.end, false);
            return;
        };
        const old = self.cursor;
        if (direction < 0 and self.cursor > 0) {
            self.cursor -= 1;
            while (self.cursor > 0 and bytes[self.cursor] & 0xc0 == 0x80) self.cursor -= 1;
        } else if (direction > 0 and self.cursor < bytes.len) {
            self.cursor += 1;
            while (self.cursor < bytes.len and bytes[self.cursor] & 0xc0 == 0x80) self.cursor += 1;
        }
        if (extend) {
            if (self.anchor == null) self.anchor = old;
        } else self.anchor = null;
    }
    /// Removes a selected range or one complete scalar beside the caret.
    pub fn erase(self: *Text, buffer: []u8, len: *usize, forward: bool) void {
        const range = self.selected() orelse blk: {
            const old = self.cursor;
            self.move(buffer[0..len.*], if (forward) 1 else -1);
            break :blk Range{ .start = @min(old, self.cursor), .end = @max(old, self.cursor) };
        };
        std.mem.copyForwards(u8, buffer[range.start .. len.* - (range.end - range.start)], buffer[range.end..len.*]);
        len.* -= range.end - range.start;
        self.cursor = range.start;
        self.anchor = null;
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

/// Intersects measured text/hover geometry with its actual content box.
pub fn intersection(a: layout.Rect, b: layout.Rect) ?layout.Rect {
    const x = @max(a.x, b.x);
    const y = @max(a.y, b.y);
    const right = @min(a.x + a.width, b.x + b.width);
    const bottom = @min(a.y + a.height, b.y + b.height);
    return if (right <= x or bottom <= y) null else .{ .x = x, .y = y, .width = right - x, .height = bottom - y };
}
test "selection geometry never paints outside a field even with a scrolled long range" {
    const inner: layout.Rect = .{ .x = 10, .y = 3, .width = 80, .height = 24 };
    try std.testing.expectEqual(inner, intersection(inner, .{ .x = -100, .y = -50, .width = 4000, .height = 4000 }).?);
    try std.testing.expect(intersection(inner, .{ .x = -100, .y = 3, .width = 20, .height = 24 }) == null);
}
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
    text.selectAll(len);
    text.kind = .color;
    try text.insert(&buffer, &len, "#123456");
    try std.testing.expectError(error.InvalidText, text.insert(&buffer, &len, "x"));
    try std.testing.expectEqualStrings("#123456", buffer[0..len]);
    text.selectAll(len);
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

test "Shift selections reverse across UTF8 anchors and replace partial ranges atomically" {
    var bytes: [32]u8 = undefined;
    var len: usize = 0;
    var text: Text = .{};
    try text.insert(&bytes, &len, "aé界z");
    text.navigate(bytes[0..len], -1, true);
    text.navigate(bytes[0..len], -1, true);
    try std.testing.expectEqualStrings("界z", bytes[text.selected().?.start..text.selected().?.end]);
    text.navigate(bytes[0..len], 1, true);
    try std.testing.expectEqualStrings("z", bytes[text.selected().?.start..text.selected().?.end]);
    text.jump(0, true);
    try text.insert(&bytes, &len, "X");
    try std.testing.expectEqualStrings("X", bytes[0..len]);
    try text.insert(&bytes, &len, "é界tail");
    text.jump(1, false);
    text.navigate(bytes[0..len], 1, true);
    text.navigate(bytes[0..len], 1, true);
    try text.insert(&bytes, &len, "!");
    try std.testing.expectEqualStrings("X!tail", bytes[0..len]);
    text.jump(1, false);
    text.navigate(bytes[0..len], 1, true);
    try text.insert(&bytes, &len, "longer");
    try std.testing.expectEqualStrings("Xlongertail", bytes[0..len]);
    text.jump(0, true);
    const before = text;
    try std.testing.expectError(error.InvalidText, text.insert(&bytes, &len, "\xff"));
    const huge: [32]u8 = @splat('a');
    try std.testing.expectError(error.TextLimit, text.insert(&bytes, &len, &huge));
    try std.testing.expectEqualDeep(before, text);
    text.move(bytes[0..len], 1);
    try std.testing.expect(text.selected() == null);
    text.selectAll(len);
    text.erase(&bytes, &len, false);
    try std.testing.expectEqual(@as(usize, 0), len);
}
