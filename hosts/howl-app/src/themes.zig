//! Static host-owned palettes. Pinned terminal sources and chrome adaptations: ../THEMES.md.
const std = @import("std");

/// Explicit application roles; these never replace terminal cell colours.
pub const Chrome = struct {
    window: u24,
    title: u24,
    active: u24,
    idle: u24,
    panel: u24,
    border: u24,
    text: u24,
    muted: u24,
    accent: u24,
};
/// One family variant, shared only as configuration data.
pub const Preset = struct {
    id: []const u8,
    label: []const u8,
    foreground: u24,
    background: u24,
    cursor: u24,
    cursor_text: u24,
    ansi: [16]u24,
    app: Chrome,
};
/// Familiar families in stable selector order; saved ids do not depend on that order.
pub const presets = [_]Preset{
    .{
        .id = "catppuccin_latte",
        .label = "Catppuccin Latte",
        .foreground = 0x4c4f69,
        .background = 0xeff1f5,
        .cursor = 0xdc8a78,
        .cursor_text = 0xeff1f5,
        .ansi = .{ 0x5c5f77, 0xd20f39, 0x40a02b, 0xdf8e1d, 0x1e66f5, 0xea76cb, 0x179299, 0xacb0be, 0x6c6f85, 0xd20f39, 0x40a02b, 0xdf8e1d, 0x1e66f5, 0xea76cb, 0x179299, 0xbcc0cc },
        .app = .{ .window = 0xeff1f5, .title = 0xe6e9ef, .active = 0xccd0da, .idle = 0xdce0e8, .panel = 0xeff1f5, .border = 0x9ca0b0, .text = 0x4c4f69, .muted = 0x6c6f85, .accent = 0x8839ef },
    },
    .{
        .id = "catppuccin_frappe",
        .label = "Catppuccin Frappé",
        .foreground = 0xc6d0f5,
        .background = 0x303446,
        .cursor = 0xf2d5cf,
        .cursor_text = 0x303446,
        .ansi = .{ 0x51576d, 0xe78284, 0xa6d189, 0xe5c890, 0x8caaee, 0xf4b8e4, 0x81c8be, 0xb5bfe2, 0x626880, 0xe78284, 0xa6d189, 0xe5c890, 0x8caaee, 0xf4b8e4, 0x81c8be, 0xa5adce },
        .app = .{ .window = 0x303446, .title = 0x292c3c, .active = 0x51576d, .idle = 0x292c3c, .panel = 0x232634, .border = 0x626880, .text = 0xc6d0f5, .muted = 0x949cbb, .accent = 0xca9ee6 },
    },
    .{
        .id = "catppuccin_macchiato",
        .label = "Catppuccin Macchiato",
        .foreground = 0xcad3f5,
        .background = 0x24273a,
        .cursor = 0xf4dbd6,
        .cursor_text = 0x24273a,
        .ansi = .{ 0x494d64, 0xed8796, 0xa6da95, 0xeed49f, 0x8aadf4, 0xf5bde6, 0x8bd5ca, 0xb8c0e0, 0x5b6078, 0xed8796, 0xa6da95, 0xeed49f, 0x8aadf4, 0xf5bde6, 0x8bd5ca, 0xa5adcb },
        .app = .{ .window = 0x24273a, .title = 0x1e2030, .active = 0x494d64, .idle = 0x1e2030, .panel = 0x181926, .border = 0x5b6078, .text = 0xcad3f5, .muted = 0x939ab7, .accent = 0xc6a0f6 },
    },
    .{
        .id = "catppuccin_mocha",
        .label = "Catppuccin Mocha",
        .foreground = 0xcdd6f4,
        .background = 0x1e1e2e,
        .cursor = 0xf5e0dc,
        .cursor_text = 0x1e1e2e,
        .ansi = .{ 0x45475a, 0xf38ba8, 0xa6e3a1, 0xf9e2af, 0x89b4fa, 0xf5c2e7, 0x94e2d5, 0xbac2de, 0x585b70, 0xf38ba8, 0xa6e3a1, 0xf9e2af, 0x89b4fa, 0xf5c2e7, 0x94e2d5, 0xa6adc8 },
        .app = .{ .window = 0x1e1e2e, .title = 0x181825, .active = 0x45475a, .idle = 0x181825, .panel = 0x11111b, .border = 0x585b70, .text = 0xcdd6f4, .muted = 0x9399b2, .accent = 0xcba6f7 },
    },
    .{
        .id = "dracula",
        .label = "Dracula",
        .foreground = 0xf8f8f2,
        .background = 0x282a36,
        .cursor = 0xf8f8f2,
        .cursor_text = 0x282a36,
        .ansi = .{ 0x21222c, 0xff5555, 0x50fa7b, 0xf1fa8c, 0xbd93f9, 0xff79c6, 0x8be9fd, 0xf8f8f2, 0x6272a4, 0xff6e6e, 0x69ff94, 0xffffa5, 0xd6acff, 0xff92df, 0xa4ffff, 0xffffff },
        .app = .{ .window = 0x282a36, .title = 0x21222c, .active = 0x44475a, .idle = 0x282a36, .panel = 0x21222c, .border = 0x6272a4, .text = 0xf8f8f2, .muted = 0x98a3cb, .accent = 0xbd93f9 },
    },
    .{
        .id = "nord",
        .label = "Nord",
        .foreground = 0xd8dee9,
        .background = 0x2e3440,
        .cursor = 0xd8dee9,
        .cursor_text = 0x2e3440,
        .ansi = .{ 0x3b4252, 0xbf616a, 0xa3be8c, 0xebcb8b, 0x81a1c1, 0xb48ead, 0x88c0d0, 0xe5e9f0, 0x4c566a, 0xbf616a, 0xa3be8c, 0xebcb8b, 0x81a1c1, 0xb48ead, 0x8fbcbb, 0xeceff4 },
        .app = .{ .window = 0x2e3440, .title = 0x3b4252, .active = 0x4c566a, .idle = 0x434c5e, .panel = 0x2e3440, .border = 0x4c566a, .text = 0xd8dee9, .muted = 0xa5abb6, .accent = 0x88c0d0 },
    },
    .{
        .id = "gruvbox_dark",
        .label = "Gruvbox Dark",
        .foreground = 0xebdbb2,
        .background = 0x282828,
        .cursor = 0xbdae93,
        .cursor_text = 0x665c54,
        .ansi = .{ 0x3c3836, 0xcc241d, 0x98971a, 0xd79921, 0x458588, 0xb16286, 0x689d6a, 0xa89984, 0x928374, 0xfb4934, 0xb8bb26, 0xfabd2f, 0x83a598, 0xd3869b, 0x8ec07c, 0xfbf1c7 },
        .app = .{ .window = 0x282828, .title = 0x1d2021, .active = 0x504945, .idle = 0x3c3836, .panel = 0x282828, .border = 0x665c54, .text = 0xebdbb2, .muted = 0xbdae93, .accent = 0xfabd2f },
    },
    .{
        .id = "gruvbox_light",
        .label = "Gruvbox Light",
        .foreground = 0x3c3836,
        .background = 0xfbf1c7,
        .cursor = 0x665c54,
        .cursor_text = 0xbdae93,
        .ansi = .{ 0xebdbb2, 0xcc241d, 0x98971a, 0xd79921, 0x458588, 0xb16286, 0x689d6a, 0x7c6f64, 0x928374, 0x9d0006, 0x79740e, 0xb57614, 0x076678, 0x8f3f71, 0x427b58, 0x282828 },
        .app = .{ .window = 0xfbf1c7, .title = 0xf2e5bc, .active = 0xd5c4a1, .idle = 0xebdbb2, .panel = 0xfbf1c7, .border = 0xa89984, .text = 0x3c3836, .muted = 0x665c54, .accent = 0x9d0006 },
    },
    .{
        .id = "solarized_dark",
        .label = "Solarized Dark",
        .foreground = 0x839496,
        .background = 0x002b36,
        .cursor = 0x93a1a1,
        .cursor_text = 0x002b36,
        .ansi = .{ 0x073642, 0xdc322f, 0x859900, 0xb58900, 0x268bd2, 0xd33682, 0x2aa198, 0xeee8d5, 0x002b36, 0xcb4b16, 0x586e75, 0x657b83, 0x839496, 0x6c71c4, 0x93a1a1, 0xfdf6e3 },
        .app = .{ .window = 0x002b36, .title = 0x073642, .active = 0x073642, .idle = 0x002b36, .panel = 0x002b36, .border = 0x586e75, .text = 0x839496, .muted = 0x657b83, .accent = 0x268bd2 },
    },
    .{
        .id = "solarized_light",
        .label = "Solarized Light",
        .foreground = 0x657b83,
        .background = 0xfdf6e3,
        .cursor = 0x586e75,
        .cursor_text = 0xfdf6e3,
        .ansi = .{ 0xeee8d5, 0xdc322f, 0x859900, 0xb58900, 0x268bd2, 0xd33682, 0x2aa198, 0x073642, 0xfdf6e3, 0xcb4b16, 0x93a1a1, 0x839496, 0x657b83, 0x6c71c4, 0x586e75, 0x002b36 },
        .app = .{ .window = 0xfdf6e3, .title = 0xeee8d5, .active = 0xeee8d5, .idle = 0xfdf6e3, .panel = 0xfdf6e3, .border = 0x93a1a1, .text = 0x657b83, .muted = 0x839496, .accent = 0x268bd2 },
    },
    .{
        .id = "tokyo_night",
        .label = "Tokyo Night",
        .foreground = 0xc0caf5,
        .background = 0x1a1b26,
        .cursor = 0xc0caf5,
        .cursor_text = 0x1a1b26,
        .ansi = .{ 0x15161e, 0xf7768e, 0x9ece6a, 0xe0af68, 0x7aa2f7, 0xbb9af7, 0x7dcfff, 0xa9b1d6, 0x414868, 0xff899d, 0x9fe044, 0xfaba4a, 0x8db0ff, 0xc7a9ff, 0xa4daff, 0xc0caf5 },
        .app = .{ .window = 0x1a1b26, .title = 0x16161e, .active = 0x283457, .idle = 0x292e42, .panel = 0x16161e, .border = 0x414868, .text = 0xc0caf5, .muted = 0x9aa5ce, .accent = 0x7aa2f7 },
    },
    .{
        .id = "tokyo_night_storm",
        .label = "Tokyo Night Storm",
        .foreground = 0xc0caf5,
        .background = 0x24283b,
        .cursor = 0xc0caf5,
        .cursor_text = 0x24283b,
        .ansi = .{ 0x1d202f, 0xf7768e, 0x9ece6a, 0xe0af68, 0x7aa2f7, 0xbb9af7, 0x7dcfff, 0xa9b1d6, 0x414868, 0xff899d, 0x9fe044, 0xfaba4a, 0x8db0ff, 0xc7a9ff, 0xa4daff, 0xc0caf5 },
        .app = .{ .window = 0x24283b, .title = 0x1f2335, .active = 0x2e3c64, .idle = 0x292e42, .panel = 0x1f2335, .border = 0x414868, .text = 0xc0caf5, .muted = 0x9aa5ce, .accent = 0x7aa2f7 },
    },
    .{
        .id = "tokyo_night_moon",
        .label = "Tokyo Night Moon",
        .foreground = 0xc8d3f5,
        .background = 0x222436,
        .cursor = 0xc8d3f5,
        .cursor_text = 0x222436,
        .ansi = .{ 0x1b1d2b, 0xff757f, 0xc3e88d, 0xffc777, 0x82aaff, 0xc099ff, 0x86e1fc, 0x828bb8, 0x444a73, 0xff8d94, 0xc7fb6d, 0xffd8ab, 0x9ab8ff, 0xcaabff, 0xb2ebff, 0xc8d3f5 },
        .app = .{ .window = 0x222436, .title = 0x1e2030, .active = 0x2d3f76, .idle = 0x2f334d, .panel = 0x1e2030, .border = 0x444a73, .text = 0xc8d3f5, .muted = 0x828bb8, .accent = 0x82aaff },
    },
    .{
        .id = "tokyo_night_day",
        .label = "Tokyo Night Day",
        .foreground = 0x3760bf,
        .background = 0xe1e2e7,
        .cursor = 0x3760bf,
        .cursor_text = 0xe1e2e7,
        .ansi = .{ 0xb4b5b9, 0xf52a65, 0x587539, 0x8c6c3e, 0x2e7de9, 0x9854f1, 0x007197, 0x6172b0, 0xa1a6c5, 0xff4774, 0x5c8524, 0xa27629, 0x358aff, 0xa463ff, 0x007ea8, 0x3760bf },
        .app = .{ .window = 0xe1e2e7, .title = 0xd0d5e3, .active = 0xb7c1e3, .idle = 0xc4c8da, .panel = 0xd0d5e3, .border = 0xa1a6c5, .text = 0x3760bf, .muted = 0x6172b0, .accent = 0x2e7de9 },
    },
};

const family_ids = blk: {
    var ids: [presets.len][]const u8 = undefined;
    for (presets, 0..) |preset, index| ids[index] = preset.id;
    break :blk ids;
};
/// Existing chrome presets remain available before the shared family variants.
pub const app_ids = [_][]const u8{ "howl_dark", "slate", "high_contrast" } ++ family_ids;
/// Existing terminal presets remain available before the shared family variants.
pub const terminal_ids = [_][]const u8{ "howl_dark", "howl_light" } ++ family_ids;

/// Borrows immutable data for one exact id; unknown names never silently choose another theme.
pub fn find(id: []const u8) ?*const Preset {
    for (&presets) |*preset| if (std.mem.eql(u8, id, preset.id)) return preset;
    return null;
}
/// Checks the exact application selector domain, including its legacy-only presets.
pub fn validApp(id: []const u8) bool {
    for (app_ids) |known| if (std.mem.eql(u8, id, known)) return true;
    return false;
}
/// Human names are display-only; editors and persistence retain the exact id.
pub fn label(id: []const u8) []const u8 {
    if (std.mem.eql(u8, id, "howl_dark")) return "Howl Dark";
    if (std.mem.eql(u8, id, "howl_light")) return "Howl Light";
    if (std.mem.eql(u8, id, "slate")) return "Slate";
    if (std.mem.eql(u8, id, "high_contrast")) return "High Contrast";
    return if (find(id)) |preset| preset.label else id;
}

test "preset ids are unique and legacy selector domains stay distinct" {
    for (presets, 0..) |preset, index| {
        try std.testing.expect(preset.id.len != 0 and preset.label.len != 0);
        try std.testing.expect(validApp(preset.id));
        try std.testing.expectEqualStrings(preset.label, label(preset.id));
        for (presets[0..index]) |other| try std.testing.expect(!std.mem.eql(u8, preset.id, other.id));
    }
    try std.testing.expect(!validApp("howl_light"));
    try std.testing.expect(!validApp("Catppuccin Mocha"));
    try std.testing.expect(find("unknown") == null);
}
