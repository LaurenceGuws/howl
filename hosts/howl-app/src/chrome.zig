//! Shared caption geometry and native window hit policy.
const std = @import("std");
const c = @import("desktop");
const Rect = @import("layout.zig").Rect;

/// Explicit client header: four pixels above the 30-pixel chips; canvas starts immediately below.
pub const height: f32 = 34;
/// Window caption control identity.
pub const Button = enum { none, minimize, maximize, close };
/// Compact Settings entry beside the caption controls.
pub fn settings(width: f32) Rect {
    return .{ .x = width - 166, .y = 4, .width = 32, .height = 30 };
}
/// Bounded tab stride leaving room for header controls.
pub fn step(count: u8, width: f32) f32 {
    return std.math.clamp((width - 266) / @as(f32, @floatFromInt(@max(1, count))), 20, 200);
}
/// One bounded strip used by painting, pointer actions and native caption hit tests.
pub const Tabs = struct {
    count: u8,
    window_width: f32,
    strides: [8]f32 = @splat(0),

    /// Fixed chips preserve the current policy; fitted titles share overflow proportionally.
    pub fn init(count: u8, width: f32, desired: ?[]const f32) Tabs {
        std.debug.assert(count <= 8);
        var result: Tabs = .{ .count = count, .window_width = width };
        if (desired) |sizes| {
            std.debug.assert(sizes.len == count);
            var extra: f32 = 0;
            for (sizes) |size| extra += std.math.clamp(size, 48, 400) - 20;
            const available = @max(0, width - 266 - @as(f32, @floatFromInt(count)) * 20);
            const ratio = if (extra == 0) 0 else @min(1, available / extra);
            for (sizes, 0..) |size, i| result.strides[i] = 20 + (std.math.clamp(size, 48, 400) - 20) * ratio;
        } else for (result.strides[0..count]) |*stride| stride.* = step(count, width);
        return result;
    }
    /// Chip geometry including the shared three-pixel gap.
    pub fn tab(self: Tabs, index: u8) Rect {
        var x: f32 = 8;
        for (self.strides[0..index]) |stride| x += stride;
        return .{ .x = x, .y = 4, .width = self.strides[index] - 3, .height = 30 };
    }
    /// New-tab button immediately follows the occupied strip.
    pub fn plus(self: Tabs) Rect {
        var x: f32 = 8;
        for (self.strides[0..self.count]) |stride| x += stride;
        return .{ .x = x, .y = 4, .width = 32, .height = 30 };
    }
    /// Profile-menu button beside New Tab.
    pub fn profiles(self: Tabs) Rect {
        var rect = self.plus();
        rect.x += rect.width;
        return rect;
    }
    /// Only unused caption space belongs to compositor dragging.
    pub fn caption(self: Tabs) Rect {
        const left = self.profiles().x + 32;
        return .{ .x = left, .y = 4, .width = @max(0, settings(self.window_width).x - left - 4), .height = height - 4 };
    }
};
/// Fixed chip geometry for callers without fitted title measurements.
pub fn tab(index: u8, count: u8, width: f32) Rect {
    return Tabs.init(count, width, null).tab(index);
}
/// New-tab button for the fixed strip.
pub fn plus(count: u8, width: f32) Rect {
    return Tabs.init(count, width, null).plus();
}
/// Profile button for the fixed strip.
pub fn profiles(count: u8, width: f32) Rect {
    return Tabs.init(count, width, null).profiles();
}
/// Unoccupied fixed caption.
pub fn caption(count: u8, width: f32) Rect {
    return Tabs.init(count, width, null).caption();
}
/// One caption button; none has no hit area.
pub fn control(button: Button, width: f32) Rect {
    if (button == .none) return .{ .x = 0, .y = 0, .width = 0, .height = 0 };
    return .{ .x = width - @as(f32, @floatFromInt(4 - @as(u8, @backingInt(button)))) * 42, .y = 4, .width = 42, .height = 30 };
}
/// Resolves a caption control with the same painted geometry.
pub fn buttonAt(x: f32, y: f32, width: f32) Button {
    for ([_]Button{ .minimize, .maximize, .close }) |button| if (control(button, width).contains(x, y)) return button;
    return .none;
}
/// Native drag/resize policy; compositor flags remain authoritative.
pub fn hit(x: f32, y: f32, width: f32, tall: f32, tabs: Tabs, flags: c.SDL_WindowFlags, visible: bool) c.SDL_HitTestResult {
    if (flags & c.SDL_WINDOW_FULLSCREEN != 0 or x < 0 or y < 0 or x >= width or y >= tall) return c.SDL_HITTEST_NORMAL;
    if (flags & c.SDL_WINDOW_MAXIMIZED == 0) {
        const left = x < 4;
        const right = x >= width - 4;
        const top = y < 4;
        const bottom = y >= tall - 4;
        if (top and left) return c.SDL_HITTEST_RESIZE_TOPLEFT;
        if (top and right) return c.SDL_HITTEST_RESIZE_TOPRIGHT;
        if (bottom and left) return c.SDL_HITTEST_RESIZE_BOTTOMLEFT;
        if (bottom and right) return c.SDL_HITTEST_RESIZE_BOTTOMRIGHT;
        if (top) return c.SDL_HITTEST_RESIZE_TOP;
        if (bottom) return c.SDL_HITTEST_RESIZE_BOTTOM;
        if (left) return c.SDL_HITTEST_RESIZE_LEFT;
        if (right) return c.SDL_HITTEST_RESIZE_RIGHT;
    }
    return if (visible and tabs.caption().contains(x, y)) c.SDL_HITTEST_DRAGGABLE else c.SDL_HITTEST_NORMAL;
}
/// Pointer-relative chip drag with bounded reorder geometry.
pub const Drag = struct {
    x: f32,
    grab: f32,
    /// Retains the exact pointer grab offset inside the chip.
    pub fn begin(rect: Rect, pointer: f32) Drag {
        return .{ .x = rect.x, .grab = std.math.clamp(pointer - rect.x, 0, rect.width) };
    }
    /// Moves the chip and selects its midpoint reorder destination.
    pub fn move(self: *Drag, pointer: f32, tabs: Tabs) u8 {
        self.x = std.math.clamp(pointer - self.grab, 8, tabs.tab(tabs.count - 1).x);
        var destination: u8 = 0;
        while (destination + 1 < tabs.count) {
            const midpoint = (tabs.tab(destination).x + tabs.tab(destination + 1).x) / 2;
            if (self.x < midpoint) break;
            destination += 1;
        }
        return destination;
    }
};
test "custom caption excludes controls and tabs; maximized/fullscreen never resize" {
    try std.testing.expectEqual(@as(c.SDL_HitTestResult, c.SDL_HITTEST_RESIZE_TOPLEFT), hit(1, 1, 1000, 650, Tabs.init(2, 1000, null), 0, true));
    try std.testing.expectEqual(@as(c.SDL_HitTestResult, c.SDL_HITTEST_NORMAL), hit(1, 1, 1000, 650, Tabs.init(2, 1000, null), c.SDL_WINDOW_MAXIMIZED, true));
    try std.testing.expectEqual(@as(c.SDL_HitTestResult, c.SDL_HITTEST_NORMAL), hit(400, 20, 1000, 650, Tabs.init(2, 1000, null), c.SDL_WINDOW_FULLSCREEN, true));
    const drag = caption(2, 1000);
    try std.testing.expectEqual(@as(c.SDL_HitTestResult, c.SDL_HITTEST_DRAGGABLE), hit(drag.x + 1, 20, 1000, 650, Tabs.init(2, 1000, null), 0, true));
    try std.testing.expectEqual(@as(c.SDL_HitTestResult, c.SDL_HITTEST_NORMAL), hit(settings(1000).x + 1, 20, 1000, 650, Tabs.init(2, 1000, null), 0, true));
    try std.testing.expectEqual(@as(c.SDL_HitTestResult, c.SDL_HITTEST_NORMAL), hit(20, 20, 1000, 650, Tabs.init(2, 1000, null), 0, true));
}
test "dragged chip preserves grab offset, reorders at midpoint and clamps outside header" {
    const rect = tab(0, 3, 1000);
    var dragging = Drag.begin(rect, rect.x + 20);
    try std.testing.expectEqual(@as(u8, 0), dragging.move(28, Tabs.init(3, 1000, null)));
    try std.testing.expectEqual(@as(u8, 1), dragging.move(28 + step(3, 1000), Tabs.init(3, 1000, null)));
    try std.testing.expectEqual(@as(f32, 8 + step(3, 1000)), dragging.x);
    try std.testing.expectEqual(@as(u8, 2), dragging.move(4000, Tabs.init(3, 1000, null)));
    try std.testing.expectEqual(@as(u8, 0), dragging.move(-100, Tabs.init(3, 1000, null)));
}

/// Font-independent New Tab strokes in the existing 32x30 header box.
pub const plus_icon: []const Rect = &.{
    .{ .x = 10, .y = 14, .width = 11, .height = 1 },
    .{ .x = 15, .y = 9, .width = 1, .height = 11 },
};
/// Font-independent Settings dots in the same header box.
pub const settings_icon: []const Rect = &.{
    .{ .x = 9, .y = 14, .width = 2, .height = 2 },
    .{ .x = 15, .y = 14, .width = 2, .height = 2 },
    .{ .x = 21, .y = 14, .width = 2, .height = 2 },
};

/// Switchyard maximize outline in the standard 42x26 caption box.
pub const maximize_icon: []const Rect = &.{
    .{ .x = 15, .y = 7, .width = 12, .height = 1 },
    .{ .x = 15, .y = 17, .width = 12, .height = 1 },
    .{ .x = 15, .y = 8, .width = 1, .height = 9 },
    .{ .x = 26, .y = 8, .width = 1, .height = 9 },
};
/// Restore glyph with the front window occluding the rear outline.
pub const restore_icon: []const Rect = &.{
    .{ .x = 17, .y = 6, .width = 10, .height = 1 },
    .{ .x = 17, .y = 7, .width = 1, .height = 2 },
    .{ .x = 26, .y = 7, .width = 1, .height = 7 },
    .{ .x = 24, .y = 14, .width = 3, .height = 1 },
    .{ .x = 14, .y = 9, .width = 10, .height = 1 },
    .{ .x = 14, .y = 17, .width = 10, .height = 1 },
    .{ .x = 14, .y = 10, .width = 1, .height = 7 },
    .{ .x = 23, .y = 10, .width = 1, .height = 7 },
};

test "compact header keeps controls and caption above terminal at fractional widths" {
    for ([_]f32{ 401.25, 1000, 1536.5 }) |width| {
        for ([_]u8{ 1, 8 }) |count| {
            const chip = tab(0, count, width);
            const cap = caption(count, width);
            try std.testing.expect(chip.y + chip.height == height);
            try std.testing.expect(cap.y + cap.height <= height);
            try std.testing.expectEqual(@as(c.SDL_HitTestResult, c.SDL_HITTEST_NORMAL), hit(cap.x + cap.width / 2, height + 0.01, width, 700, Tabs.init(count, width, null), c.SDL_WINDOW_MAXIMIZED, true));
            try std.testing.expect(!chip.contains(chip.x + 1, height));
            try std.testing.expect(!plus(count, width).contains(chip.x + 1, height));
        }
    }
}

/// Font-independent right chevron beside New Tab.
pub const profile_icon: []const Rect = &.{
    .{ .x = 12, .y = 10, .width = 1, .height = 1 },
    .{ .x = 13, .y = 11, .width = 1, .height = 1 },
    .{ .x = 14, .y = 12, .width = 1, .height = 1 },
    .{ .x = 15, .y = 13, .width = 1, .height = 1 },
    .{ .x = 16, .y = 14, .width = 1, .height = 1 },
    .{ .x = 17, .y = 15, .width = 1, .height = 1 },
    .{ .x = 16, .y = 16, .width = 1, .height = 1 },
    .{ .x = 15, .y = 17, .width = 1, .height = 1 },
    .{ .x = 14, .y = 18, .width = 1, .height = 1 },
    .{ .x = 13, .y = 19, .width = 1, .height = 1 },
    .{ .x = 12, .y = 20, .width = 1, .height = 1 },
};

test "profile button never becomes caption; hidden header retains only native edge resizing" {
    for ([_]f32{ 401.25, 1000, 1536.5 }) |width| {
        for ([_]u8{ 1, 8 }) |count| {
            const plus_rect = plus(count, width);
            const menu = profiles(count, width);
            try std.testing.expectEqual(plus_rect.x + plus_rect.width, menu.x);
            try std.testing.expect(menu.x + menu.width <= settings(width).x);
            try std.testing.expectEqual(@as(c.SDL_HitTestResult, c.SDL_HITTEST_NORMAL), hit(menu.x + 16, 20, width, 650, Tabs.init(count, width, null), 0, true));
            const cap = caption(count, width);
            try std.testing.expectEqual(@as(c.SDL_HitTestResult, c.SDL_HITTEST_NORMAL), hit(cap.x + cap.width / 2, 20, width, 650, Tabs.init(count, width, null), 0, false));
            try std.testing.expectEqual(@as(c.SDL_HitTestResult, c.SDL_HITTEST_RESIZE_TOPLEFT), hit(1, 1, width, 650, Tabs.init(count, width, null), 0, false));
        }
    }
}

test "fitted chip geometry preserves controls and reorder targets under compression" {
    const fitted = Tabs.init(3, 1000, &.{ 60, 240, 120 });
    try std.testing.expectEqual(@as(f32, 57), fitted.tab(0).width);
    try std.testing.expectEqual(@as(f32, 237), fitted.tab(1).width);
    try std.testing.expectEqual(@as(f32, 428), fitted.plus().x);
    var dragging = Drag.begin(fitted.tab(0), 28);
    try std.testing.expectEqual(@as(u8, 1), dragging.move(150, fitted));
    const narrow = Tabs.init(3, 450, &.{ 60, 240, 120 });
    try std.testing.expect(narrow.profiles().x + 32 <= settings(450).x);
    for (0..3) |i| try std.testing.expect(narrow.tab(@intCast(i)).width >= 17);
    try std.testing.expectEqual(@as(c.SDL_HitTestResult, c.SDL_HITTEST_NORMAL), hit(90, 20, 1000, 650, fitted, 0, true));
}
