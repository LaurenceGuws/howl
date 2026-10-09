//! Shell palettes; terminal colours remain owned by canonical presentation.
const c = @import("desktop");
const std = @import("std");

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
/// Resolves the three compatible saved theme ids; unknown ids fail rather than falling back.
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
    return error.InvalidTheme;
}
fn rgb(r: u8, g: u8, b: u8) c.SDL_Color {
    return .{ .r = r, .g = g, .b = b, .a = 255 };
}
