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

/// A value and an explicit trailing action share one bounded row without hiding either hit target.
/// Painting and pointer routing consume these same rectangles.
pub const InlineAction = struct {
    value: layout.Rect,
    button: layout.Rect,

    /// Splits an available value rectangle using explicit insets and button width.
    pub fn init(right: layout.Rect, preferred_width: f32) InlineAction {
        const inset = @min(3, @max(0, right.width / 10));
        const usable = @max(1, right.width - 2 * inset);
        const button_width = @min(preferred_width, @max(1, usable * 0.44));
        const gap = @min(6, @max(0, usable - button_width - 1));
        const value_width = @max(1, usable - button_width - gap);
        return .{
            .value = .{ .x = right.x + inset, .y = right.y, .width = value_width, .height = right.height },
            .button = .{ .x = right.x + inset + value_width + gap, .y = right.y + 5, .width = button_width, .height = @max(1, right.height - 10) },
        };
    }
};

/// A finite choice menu anchored to its field, opening upward near the form's lower edge.
pub const Dropdown = struct {
    rect: layout.Rect,
    rows: Rows,

    /// Keeps the menu inside a bounded form while showing up to six complete options.
    pub fn init(field: layout.Rect, bounds: layout.Rect, count: usize) Dropdown {
        const stride: f32 = 32;
        const padding: f32 = 4;
        const below = @max(0, bounds.y + bounds.height - (field.y + field.height) - padding);
        const above = @max(0, field.y - bounds.y - padding);
        const available = @max(below, above);
        const wanted = @max(1, @min(count, 6));
        const rows: usize = @max(1, @min(wanted, @as(usize, @intFromFloat(@floor(@max(0, available - 2 * padding) / stride)))));
        const height = @min(@max(1, bounds.height), @as(f32, @floatFromInt(rows)) * stride + 2 * padding);
        const width = @min(@max(1, bounds.width), @max(field.width, 210));
        const x = std.math.clamp(field.x, bounds.x, bounds.x + @max(0, bounds.width - width));
        const opening_down = below >= height or below >= above;
        const desired_y = if (opening_down) field.y + field.height + padding else field.y - height - padding;
        const y = std.math.clamp(desired_y, bounds.y, bounds.y + @max(0, bounds.height - height));
        const rect: layout.Rect = .{ .x = x, .y = y, .width = width, .height = height };
        return .{ .rect = rect, .rows = .{ .rect = .{ .x = x + padding, .y = y + padding, .width = @max(1, width - 2 * padding), .height = @max(1, height - 2 * padding) }, .stride = stride, .gap = 2 } };
    }
};

/// A bounded form viewport. Keyboard focus reveals a field without moving
/// controls independently of their labels or their pointer hit rectangles.
pub const FormViewport = struct {
    bounds: layout.Rect,
    offset: f32,
    content_height: f32,

    /// Pixel-scrolled forms own their position independently of row selection.
    pub fn atOffset(bounds: layout.Rect, content_height: f32, offset: f32) FormViewport {
        return .{ .bounds = bounds, .offset = std.math.clamp(offset, 0, @max(0, content_height - bounds.height)), .content_height = content_height };
    }
    /// Places one immutable form rectangle in the shared scrolled coordinates.
    pub fn place(self: FormViewport, left: f32, top: f32, width: f32, height: f32) layout.Rect {
        return .{ .x = self.bounds.x + left, .y = self.bounds.y + top - self.offset, .width = @max(1, width), .height = @max(1, height) };
    }
    /// Painted track and proportional thumb for clipped forms.
    pub const Scrollbar = struct { track: layout.Rect, thumb: layout.Rect };
    /// A proportional scroll cue whenever part of the form is out of view.
    pub fn scrollbar(self: FormViewport) ?Scrollbar {
        if (self.content_height <= self.bounds.height) return null;
        const track: layout.Rect = .{ .x = self.bounds.x + self.bounds.width - 4, .y = self.bounds.y, .width = 3, .height = self.bounds.height };
        const thumb_height = @min(track.height, @max(18, track.height * track.height / self.content_height));
        const travel = track.height - thumb_height;
        return .{ .track = track, .thumb = .{ .x = track.x, .y = track.y + self.offset / (self.content_height - self.bounds.height) * travel, .width = track.width, .height = thumb_height } };
    }
};

/// A select's label and indicator have separate clipping bounds; the entire
/// surface remains one hit target and cannot lose its arrow to long values.
pub const Select = struct {
    surface: layout.Rect,
    label: layout.Rect,
    arrow: layout.Rect,

    /// Reserves a trailing arrow rectangle no matter how long the label is.
    pub fn init(rect: layout.Rect) Select {
        const inset: f32 = @min(10, @max(1, rect.width / 12));
        const arrow_width: f32 = @min(18, @max(1, rect.width / 8));
        const arrow_x = rect.x + rect.width - inset - arrow_width;
        return .{
            .surface = rect,
            .label = .{ .x = rect.x + inset, .y = rect.y, .width = @max(1, arrow_x - (rect.x + inset) - 6), .height = rect.height },
            .arrow = .{ .x = arrow_x, .y = rect.y, .width = arrow_width, .height = rect.height },
        };
    }
};

/// A fixed-height switch with a complete pointer target and a thumb inside
/// its track in both states. The caller owns persistence and focus policy.
pub const Switch = struct {
    track: layout.Rect,
    thumb: layout.Rect,

    /// Moves the contained thumb between off and on without changing hit size.
    pub fn init(track: layout.Rect, enabled: bool) Switch {
        const inset = @min(4, @max(1, track.height / 8));
        const diameter = @max(1, @min(track.height - 2 * inset, track.width - 2 * inset));
        return .{
            .track = track,
            .thumb = .{
                .x = track.x + (if (enabled) track.width - diameter - inset else inset),
                .y = track.y + (track.height - diameter) / 2,
                .width = diameter,
                .height = diameter,
            },
        };
    }
};

test "form controls keep their labels, indicators, switches and scrolled fields bounded" {
    const viewport: layout.Rect = .{ .x = 20, .y = 40, .width = 300, .height = 120 };
    const first = FormViewport.atOffset(viewport, 344, 8);
    const last = FormViewport.atOffset(viewport, 344, 218);
    try std.testing.expectEqual(@as(f32, 8), first.offset);
    try std.testing.expectEqual(@as(f32, 218), last.offset);
    const bar = last.scrollbar().?;
    try std.testing.expect(bar.thumb.y >= bar.track.y);
    try std.testing.expect(bar.thumb.y + bar.thumb.height <= bar.track.y + bar.track.height);
    try std.testing.expectEqual(@as(f32, 224), FormViewport.atOffset(viewport, 344, 1000).offset);
    try std.testing.expect(FormViewport.atOffset(viewport, 100, 80).scrollbar() == null);
    const focused = last.place(8, 280, 280, 50);
    try std.testing.expect(focused.y >= viewport.y);
    try std.testing.expect(focused.y + focused.height <= viewport.y + viewport.height);
    for ([_]f32{ 290, 180, 72 }) |width| {
        const selection = Select.init(.{ .x = 10, .y = 20, .width = width, .height = 36 });
        try std.testing.expect(selection.label.x + selection.label.width <= selection.arrow.x);
        try std.testing.expect(selection.arrow.x + selection.arrow.width <= selection.surface.x + selection.surface.width);
    }
    for ([_]bool{ false, true }) |enabled| {
        const toggle = Switch.init(.{ .x = 90, .y = 25, .width = 46, .height = 26 }, enabled);
        try std.testing.expect(toggle.track.contains(toggle.thumb.x, toggle.thumb.y));
        try std.testing.expect(toggle.thumb.x + toggle.thumb.width <= toggle.track.x + toggle.track.width);
    }
    try std.testing.expect(Switch.init(.{ .x = 90, .y = 25, .width = 46, .height = 26 }, true).thumb.x > Switch.init(.{ .x = 90, .y = 25, .width = 46, .height = 26 }, false).thumb.x);
}

test "dropdowns stay in the form and reverse direction near its bottom" {
    const bounds: layout.Rect = .{ .x = 100, .y = 80, .width = 430, .height = 330 };
    const first = Dropdown.init(.{ .x = 300, .y = 105, .width = 210, .height = 36 }, bounds, 20);
    const last = Dropdown.init(.{ .x = 300, .y = 365, .width = 210, .height = 36 }, bounds, 20);
    try std.testing.expect(first.rect.y > 105);
    try std.testing.expect(last.rect.y < 365);
    for ([_]Dropdown{ first, last }) |menu| {
        try std.testing.expect(menu.rect.x >= bounds.x);
        try std.testing.expect(menu.rect.x + menu.rect.width <= bounds.x + bounds.width);
        try std.testing.expect(menu.rect.y >= bounds.y);
        try std.testing.expect(menu.rect.y + menu.rect.height <= bounds.y + bounds.height);
        try std.testing.expect(menu.rows.visible() <= 6);
        try std.testing.expectEqual(@as(?usize, 0), menu.rows.hit(menu.rows.rect.x + 1, menu.rows.rect.y + 1));
    }
}

test "inline actions keep exact value and button hits disjoint at form widths" {
    for ([_]f32{ 300, 160, 72, 24 }) |width| {
        const right: layout.Rect = .{ .x = 10, .y = 30, .width = width, .height = 44 };
        const action = InlineAction.init(right, 76);
        try std.testing.expect(action.value.x >= right.x);
        try std.testing.expect(action.value.x + action.value.width <= action.button.x);
        try std.testing.expect(action.button.x + action.button.width <= right.x + right.width);
        try std.testing.expect(action.button.y >= right.y);
        try std.testing.expect(action.button.y + action.button.height <= right.y + right.height);
        try std.testing.expect(!action.value.contains(action.button.x + action.button.width / 2, action.button.y + action.button.height / 2));
    }
}

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
