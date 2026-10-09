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
        .window = rgb(14, 17, 22),
        .title = rgb(26, 30, 38),
        .active = rgb(42, 48, 59),
        .idle = rgb(31, 36, 45),
        .panel = rgb(13, 16, 20),
        .border = rgb(60, 68, 82),
        .text = rgb(220, 226, 234),
        .muted = rgb(137, 148, 164),
        .accent = rgb(96, 165, 250),
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
        .accent = rgb(112, 180, 224),
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
