//! Shell palettes; terminal colours remain owned by canonical presentation.
const c = @import("desktop");
const std = @import("std");
const colors = @import("colors.zig");
const themes = @import("themes.zig");

/// Existing application palettes; terminal colours remain canonical VT presentation policy.
pub const Palette = struct {
    window: c.SDL_Color,
    title: c.SDL_Color,
    active: c.SDL_Color,
    idle: c.SDL_Color,
    panel: c.SDL_Color,
    border: c.SDL_Color,
    text: c.SDL_Color,
    muted: c.SDL_Color,
    accent: c.SDL_Color,
};
/// Resolves exact legacy or family ids; unknown ids fail rather than falling back.
pub fn palette(id: []const u8) error{InvalidTheme}!Palette {
    if (std.mem.eql(u8, id, "howl_dark")) return .{
        // Ayu-like charcoal surfaces, with the Howl logo's orange accent.
        .window = rgb(0, 0, 0),
        .title = rgb(11, 14, 20),
        .active = rgb(58, 39, 20),
        .idle = rgb(22, 21, 20),
        .panel = rgb(11, 14, 20),
        .border = rgb(60, 48, 34),
        .text = rgb(191, 189, 182),
        .muted = rgb(138, 145, 155),
        .accent = rgb(254, 140, 1),
    };
    if (std.mem.eql(u8, id, "slate")) return .{
        .window = rgb(21, 23, 28),
        .title = rgb(34, 37, 44),
        .active = rgb(52, 57, 68),
        .idle = rgb(39, 43, 51),
        .panel = rgb(18, 21, 26),
        .border = rgb(76, 84, 98),
        .text = rgb(229, 232, 238),
        .muted = rgb(156, 165, 178),
        .accent = rgb(254, 140, 1),
    };
    if (std.mem.eql(u8, id, "high_contrast")) return .{
        .window = rgb(0, 0, 0),
        .title = rgb(0, 0, 0),
        .active = rgb(32, 32, 32),
        .idle = rgb(8, 8, 8),
        .panel = rgb(0, 0, 0),
        .border = rgb(200, 200, 200),
        .text = rgb(255, 255, 255),
        .muted = rgb(200, 200, 200),
        .accent = rgb(255, 210, 64),
    };
    if (themes.find(id)) |preset| {
        var result: Palette = undefined;
        inline for (@typeInfo(themes.Chrome).@"struct".field_names) |field| {
            const value = @field(preset.app, field);
            @field(result, field) = rgb(@truncate(value >> 16), @truncate(value >> 8), @truncate(value));
        }
        return result;
    }
    return error.InvalidTheme;
}
fn rgb(r: u8, g: u8, b: u8) c.SDL_Color {
    return .{ .r = r, .g = g, .b = b, .a = 255 };
}

/// Resolves chrome overrides independently of every terminal palette and program color.
pub fn resolve(id: []const u8, overrides: colors.Application) error{ InvalidTheme, InvalidColor }!Palette {
    var result = try palette(id);
    inline for (@typeInfo(colors.Application).@"struct".field_names) |field| {
        const value = @field(overrides, field);
        if (value.len != 0) {
            const parsed = try colors.parse(value);
            @field(result, field) = .{ .r = parsed.r, .g = parsed.g, .b = parsed.b, .a = 255 };
        }
    }
    return result;
}

test "every application preset resolves independently and preserves role overrides" {
    for (themes.app_ids) |id| {
        const base = try palette(id);
        const edited = try resolve(id, .{ .accent = "#123456" });
        try std.testing.expectEqual(base.window, edited.window);
        try std.testing.expectEqual(rgb(0x12, 0x34, 0x56), edited.accent);
    }
    try std.testing.expectError(error.InvalidTheme, palette("howl_light"));
    try std.testing.expectError(error.InvalidTheme, palette("unknown"));
}

/// Small neutral light tint shared by pointer-hover surfaces.
pub fn hover(base: c.SDL_Color) c.SDL_Color {
    return .{ .r = @intCast((@as(u16, base.r) * 9 + 255) / 10), .g = @intCast((@as(u16, base.g) * 9 + 255) / 10), .b = @intCast((@as(u16, base.b) * 9 + 255) / 10), .a = 255 };
}
/// Text selection has its own contrasting ink; list-active colors are not text-selection roles.
pub fn selection(value: Palette) struct { background: c.SDL_Color, foreground: c.SDL_Color } {
    const background = value.accent;
    return .{ .background = background, .foreground = if (luminance(background) > 0.179) rgb(0, 0, 0) else rgb(255, 255, 255) };
}
fn luminance(color: c.SDL_Color) f64 {
    var result: f64 = 0;
    for ([_]u8{ color.r, color.g, color.b }, [_]f64{ 0.2126, 0.7152, 0.0722 }) |component, weight| {
        const channel = @as(f64, @floatFromInt(component)) / 255;
        result += weight * (if (channel <= 0.04045) channel / 12.92 else std.math.pow(f64, (channel + 0.055) / 1.055, 2.4));
    }
    return result;
}
test "every theme has contrasting selected text and a neutral brighter hover tint" {
    for (themes.app_ids) |id| {
        const value = try palette(id);
        const selected = selection(value);
        const a = luminance(selected.background);
        const b = luminance(selected.foreground);
        try std.testing.expect((@max(a, b) + 0.05) / (@min(a, b) + 0.05) >= 4.5);
        const tint = hover(value.idle);
        try std.testing.expect(tint.r >= value.idle.r and tint.g >= value.idle.g and tint.b >= value.idle.b);
        try std.testing.expect(luminance(tint) > luminance(value.idle));
    }
}
