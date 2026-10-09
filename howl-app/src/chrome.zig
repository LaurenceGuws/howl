const std = @import("std");
const c = @import("desktop");
const Rect = @import("layout.zig").Rect;

/// Existing client header height in logical pixels.
pub const height: f32 = 46;
/// Window caption control identity.
pub const Button = enum { none, minimize, maximize, close };
/// Existing visible Settings button.
pub fn settings(width: f32) Rect {
    return .{ .x = width - 248, .y = 7, .width = 104, .height = 32 };
}
/// Bounded tab stride leaving room for header controls.
pub fn step(count: u8, width: f32) f32 {
    return @max(16, @min(162, @max(0, settings(width).x - 8 - 108) / @as(f32, @floatFromInt(@max(1, count))) - 4)) + 4;
}
/// Chip geometry shared by paint, drag and hit testing.
pub fn tab(index: u8, count: u8, width: f32) Rect {
    const stride = step(count, width);
    return .{ .x = 8 + @as(f32, @floatFromInt(index)) * stride, .y = 7, .width = stride - 4, .height = 32 };
}
/// New-tab button after the chip strip.
pub fn plus(count: u8, width: f32) Rect {
    return .{ .x = 8 + @as(f32, @floatFromInt(count)) * step(count, width), .y = 7, .width = 34, .height = 32 };
}
/// Profile menu button next to new tab.
pub fn menu(count: u8, width: f32) Rect {
    var rect = plus(count, width);
    rect.x += 38;
    return rect;
}
/// Unoccupied header strip available for compositor dragging.
pub fn caption(count: u8, width: f32) Rect {
    const left = menu(count, width).x + 38;
    return .{ .x = left, .y = 4, .width = @max(0, settings(width).x - left - 4), .height = 42 };
}
/// One caption button; none has no hit area.
pub fn control(button: Button, width: f32) Rect {
    if (button == .none) return .{ .x = 0, .y = 0, .width = 0, .height = 0 };
    return .{ .x = width - @as(f32, @floatFromInt(4 - @as(u8, @backingInt(button)))) * 42, .y = 4, .width = 42, .height = 42 };
}
/// Resolves a caption control with the same painted geometry.
pub fn buttonAt(x: f32, y: f32, width: f32) Button {
    for ([_]Button{ .minimize, .maximize, .close }) |button| if (control(button, width).contains(x, y)) return button;
    return .none;
}
/// Native drag/resize policy; compositor flags remain authoritative.
pub fn hit(x: f32, y: f32, width: f32, tall: f32, count: u8, flags: c.SDL_WindowFlags) c.SDL_HitTestResult {
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
    return if (caption(count, width).contains(x, y)) c.SDL_HITTEST_DRAGGABLE else c.SDL_HITTEST_NORMAL;
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
    pub fn move(self: *Drag, pointer: f32, count: u8, width: f32) u8 {
        self.x = std.math.clamp(pointer - self.grab, 8, tab(count - 1, count, width).x);
        return @intFromFloat(std.math.clamp(@floor((self.x - 8 + step(count, width) / 2) / step(count, width)), 0, @as(f32, @floatFromInt(count - 1))));
    }
};
test "custom caption excludes controls and tabs; maximized/fullscreen never resize" {
    try std.testing.expectEqual(@as(c.SDL_HitTestResult, c.SDL_HITTEST_RESIZE_TOPLEFT), hit(1, 1, 1000, 650, 2, 0));
    try std.testing.expectEqual(@as(c.SDL_HitTestResult, c.SDL_HITTEST_NORMAL), hit(1, 1, 1000, 650, 2, c.SDL_WINDOW_MAXIMIZED));
    try std.testing.expectEqual(@as(c.SDL_HitTestResult, c.SDL_HITTEST_NORMAL), hit(400, 20, 1000, 650, 2, c.SDL_WINDOW_FULLSCREEN));
    const drag = caption(2, 1000);
    try std.testing.expectEqual(@as(c.SDL_HitTestResult, c.SDL_HITTEST_DRAGGABLE), hit(drag.x + 1, 20, 1000, 650, 2, 0));
    try std.testing.expectEqual(@as(c.SDL_HitTestResult, c.SDL_HITTEST_NORMAL), hit(settings(1000).x + 1, 20, 1000, 650, 2, 0));
    try std.testing.expectEqual(@as(c.SDL_HitTestResult, c.SDL_HITTEST_NORMAL), hit(20, 20, 1000, 650, 2, 0));
}
test "dragged chip preserves grab offset, reorders at midpoint and clamps outside header" {
    const rect = tab(0, 3, 1000);
    var dragging = Drag.begin(rect, rect.x + 20);
    try std.testing.expectEqual(@as(u8, 0), dragging.move(28, 3, 1000));
    try std.testing.expectEqual(@as(u8, 1), dragging.move(28 + step(3, 1000), 3, 1000));
    try std.testing.expectEqual(@as(f32, 8 + step(3, 1000)), dragging.x);
    try std.testing.expectEqual(@as(u8, 2), dragging.move(4000, 3, 1000));
    try std.testing.expectEqual(@as(u8, 0), dragging.move(-100, 3, 1000));
}
