const std = @import("std");
const instance = @import("howl_instance");
const layout = @import("layout.zig");

/// Desktop wheel policy; terminal encoding remains exclusively VT-owned.
pub const WheelRoute = enum { wait, history, terminal, alternate, ignore };

/// UI routing uses copied interaction facts and the accepted immutable frame.
pub fn wheelRoute(history: bool, shift: bool, state: ?instance.Terminal.InteractionState, alternate: bool) WheelRoute {
    if (history or shift) return .history;
    const known = state orelse return .wait;
    if (known.mouse_tracking != .off) return .terminal;
    if (!alternate) return .history;
    return if (known.alternate_scroll) .alternate else .ignore;
}

/// Fractional deltas remain local and bounded; changing ownership/policy drops the remainder.
pub const Wheel = struct {
    remainder: f32 = 0,
    route: WheelRoute = .ignore,

    /// Produces at most sixteen whole steps and retains only their fractional residue.
    pub fn consume(self: *Wheel, delta: f32, route: WheelRoute) i32 {
        if (route != self.route) self.remainder = 0;
        self.route = route;
        if (!std.math.isFinite(delta) or route == .ignore or route == .wait) return 0;
        const sum = std.math.clamp(self.remainder + delta * @as(f32, if (route == .history) 3 else 1), -16, 16);
        const whole: i32 = @intFromFloat(@trunc(sum));
        self.remainder = sum - @as(f32, @floatFromInt(whole));
        return whole;
    }
};

/// Physical pixels and zero-based canonical cell coordinates derived from an accepted frame.
pub const Location = struct {
    row: i32,
    col: u16,
    pixel_x: u32,
    pixel_y: u32,

    /// Supplies semantic facts without assembling protocol bytes.
    pub fn event(self: Location, kind: instance.MouseEventKind, button: instance.MouseButton, mods: instance.InputModifier, buttons: u8) instance.Input {
        return .{ .mouse = .{
            .kind = kind,
            .button = button,
            .mod = mods,
            .buttons_down = buttons,
            .row = self.row,
            .col = self.col,
            .pixel_x = self.pixel_x,
            .pixel_y = self.pixel_y,
        } };
    }
};

/// Maps only the visible accepted lattice; captured drags clamp to its clipped surface.
pub fn locate(rect: layout.Rect, scale: f32, cell: instance.render.terminal.Size, surface: instance.render.terminal.Size, x: f32, y: f32, captured: bool) ?Location {
    if (!std.math.isFinite(x) or !std.math.isFinite(y) or !std.math.isFinite(scale) or scale <= 0 or
        cell.width == 0 or cell.height == 0 or surface.width == 0 or surface.height == 0) return null;
    const width = @min(@as(f64, @floatFromInt(surface.width)), @floor(@as(f64, rect.width) * scale));
    const height = @min(@as(f64, @floatFromInt(surface.height)), @floor(@as(f64, rect.height) * scale));
    if (width < 1 or height < 1) return null;
    var px = @floor((@as(f64, x) - rect.x) * scale);
    var py = @floor((@as(f64, y) - rect.y) * scale);
    if (captured) {
        px = std.math.clamp(px, 0, width - 1);
        py = std.math.clamp(py, 0, height - 1);
    } else if (px < 0 or py < 0 or px >= width or py >= height) return null;
    const column = @floor(px / @as(f64, @floatFromInt(cell.width)));
    const row = @floor(py / @as(f64, @floatFromInt(cell.height)));
    if (column >= instance.render.limits.maximum_columns or row >= instance.render.limits.maximum_rows) return null;
    return .{ .row = @intFromFloat(row), .col = @intFromFloat(column), .pixel_x = @intFromFloat(px), .pixel_y = @intFromFloat(py) };
}

/// Maps only the three capturable physical buttons to their held-state bits.
pub fn buttonBit(button: instance.MouseButton) u8 {
    return switch (button) {
        .left => 1,
        .middle => 2,
        .right => 4,
        else => 0,
    };
}

test "wheel routing preserves local overrides, negotiated mouse, and alternate scroll" {
    var state = std.mem.zeroes(instance.Terminal.InteractionState);
    try std.testing.expectEqual(WheelRoute.wait, wheelRoute(false, false, null, false));
    try std.testing.expectEqual(WheelRoute.history, wheelRoute(false, true, null, true));
    try std.testing.expectEqual(WheelRoute.history, wheelRoute(true, false, null, true));
    try std.testing.expectEqual(WheelRoute.history, wheelRoute(false, false, state, false));
    state.alternate_scroll = false;
    try std.testing.expectEqual(WheelRoute.ignore, wheelRoute(false, false, state, true));
    state.alternate_scroll = true;
    try std.testing.expectEqual(WheelRoute.alternate, wheelRoute(false, false, state, true));
    state.mouse_tracking = .normal;
    try std.testing.expectEqual(WheelRoute.terminal, wheelRoute(false, false, state, true));
    try std.testing.expectEqual(WheelRoute.history, wheelRoute(true, false, state, true));
}

test "fractional wheel input accumulates without crossing policy ownership or flooding the queue" {
    var wheel: Wheel = .{};
    try std.testing.expectEqual(@as(i32, 0), wheel.consume(0.25, .terminal));
    try std.testing.expectEqual(@as(i32, 1), wheel.consume(0.75, .terminal));
    try std.testing.expectEqual(@as(i32, 0), wheel.consume(0.5, .terminal));
    try std.testing.expectEqual(@as(i32, -1), wheel.consume(-0.5, .history));
    try std.testing.expectEqual(@as(i32, 0), wheel.consume(std.math.nan(f32), .history));
    try std.testing.expectEqual(@as(i32, 16), wheel.consume(100000, .alternate));
    try std.testing.expectEqual(@as(i32, 0), wheel.consume(10, .ignore));
}

test "pointer coordinates honor fractional scale, clipping, capture and hostile bounds" {
    const rect: layout.Rect = .{ .x = 10, .y = 20, .width = 30, .height = 40 };
    const cell: instance.render.terminal.Size = .{ .width = 10, .height = 20 };
    const surface: instance.render.terminal.Size = .{ .width = 100, .height = 100 };
    const point = locate(rect, 1.7, cell, surface, 22, 33, false).?;
    try std.testing.expectEqual(@as(i32, 1), point.row);
    try std.testing.expectEqual(@as(u16, 2), point.col);
    try std.testing.expectEqual(@as(u32, 20), point.pixel_x);
    try std.testing.expectEqual(@as(u32, 22), point.pixel_y);
    try std.testing.expect(locate(rect, 1.7, cell, surface, 40, 33, false) == null);
    const captured = locate(rect, 1.7, cell, surface, 1000, -100, true).?;
    try std.testing.expectEqual(@as(u32, 50), captured.pixel_x);
    try std.testing.expectEqual(@as(u32, 0), captured.pixel_y);
    try std.testing.expect(locate(rect, 1, cell, surface, std.math.nan(f32), 20, true) == null);
    try std.testing.expect(locate(.{ .x = 0, .y = 0, .width = 0.1, .height = 0.1 }, 1, cell, surface, 0, 0, true) == null);
}
