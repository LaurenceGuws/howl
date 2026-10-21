//! App-owned palette names and strict RGB configuration; VT owns resolved terminal colors.
const std = @import("std");
const Terminal = @import("howl_instance").Terminal;
const themes = @import("themes.zig");

/// Optional chrome role overrides; empty strings inherit the selected application theme.
pub const Application = struct {
    window: []const u8 = "",
    title: []const u8 = "",
    active: []const u8 = "",
    idle: []const u8 = "",
    panel: []const u8 = "",
    border: []const u8 = "",
    text: []const u8 = "",
    muted: []const u8 = "",
    accent: []const u8 = "",

    /// Borrows one known role by its stable settings index.
    pub fn get(self: Application, index: usize) error{InvalidColorRole}![]const u8 {
        inline for (@typeInfo(Application).@"struct".field_names, 0..) |field, i| if (i == index) return @field(self, field);
        return error.InvalidColorRole;
    }
    /// Replaces one known role; validation belongs to the complete config transaction.
    pub fn set(self: *Application, index: usize, value: []const u8) error{InvalidColorRole}!void {
        inline for (@typeInfo(Application).@"struct".field_names, 0..) |field, i| if (i == index) {
            @field(self, field) = value;
            return;
        };
        return error.InvalidColorRole;
    }
    /// Rejects malformed overrides before either persistence or presentation changes.
    pub fn validate(self: Application) error{InvalidColor}!void {
        inline for (@typeInfo(Application).@"struct".field_names) |field| try optional(@field(self, field));
    }
};
/// Chrome labels in the exact role order above.
pub const app_labels = [_][]const u8{ "Canvas margin", "Tab bar", "Active item", "Inactive / hover", "Panel", "Border", "Text", "Muted text", "Accent" };
/// Supported terminal presets; these do not select an application theme.
pub const terminal_themes = themes.terminal_ids;
/// Terminal defaults and ANSI overrides; direct RGB cells retain their specified color.
pub const TerminalColors = struct {
    foreground: []const u8 = "",
    background: []const u8 = "",
    cursor: []const u8 = "",
    cursor_text: []const u8 = "",
    ansi: [16][]const u8 = @splat(""),

    /// Reads terminal defaults, sixteen ANSI roles, or the block-cursor text color.
    pub fn get(self: TerminalColors, index: usize) error{InvalidColorRole}![]const u8 {
        return switch (index) {
            0 => self.foreground,
            1 => self.background,
            2 => self.cursor,
            3...18 => self.ansi[index - 3],
            19 => self.cursor_text,
            else => error.InvalidColorRole,
        };
    }
    /// Changes one exact role in a candidate; no effect reaches a live terminal yet.
    pub fn set(self: *TerminalColors, index: usize, value: []const u8) error{InvalidColorRole}!void {
        switch (index) {
            0 => self.foreground = value,
            1 => self.background = value,
            2 => self.cursor = value,
            3...18 => self.ansi[index - 3] = value,
            19 => self.cursor_text = value,
            else => return error.InvalidColorRole,
        }
    }
    /// Resolves one complete VT baseline. The remaining 240 palette entries keep VT defaults.
    pub fn resolve(self: TerminalColors, theme: []const u8) error{ InvalidColor, InvalidTheme }!Terminal.ColorDefaults {
        var result: Terminal.ColorDefaults = .{};
        if (std.mem.eql(u8, theme, "howl_light")) {
            result.foreground = .{ .r = 35, .g = 40, .b = 48 };
            result.background = .{ .r = 246, .g = 244, .b = 239 };
            const palette = [_]u24{ 0x20252b, 0xb42935, 0x28783c, 0x936900, 0x2459a6, 0x833ca2, 0x007c8a, 0xc5c6c8, 0x626b77, 0xd3424c, 0x438e55, 0xab7c11, 0x497cbb, 0xa062b3, 0x238e9d, 0xffffff };
            for (palette, 0..) |value, i| result.palette[i] = unpack(value);
        } else if (themes.find(theme)) |preset| {
            result.foreground = unpack(preset.foreground);
            result.background = unpack(preset.background);
            result.cursor = unpack(preset.cursor);
            result.cursor_text = unpack(preset.cursor_text);
            for (preset.ansi, 0..) |value, i| result.palette[i] = unpack(value);
        } else if (!std.mem.eql(u8, theme, "howl_dark")) return error.InvalidTheme;
        if (self.foreground.len != 0) result.foreground = try parse(self.foreground);
        if (self.background.len != 0) result.background = try parse(self.background);
        if (self.cursor.len != 0) result.cursor = try parse(self.cursor);
        if (self.cursor_text.len != 0) result.cursor_text = try parse(self.cursor_text);
        for (self.ansi, 0..) |value, index| if (value.len != 0) {
            result.palette[index] = try parse(value);
        };
        return result;
    }
};
comptime {
    std.debug.assert(app_labels.len == @typeInfo(Application).@"struct".field_names.len);
}

/// Terminal role labels include the complete normal/bright ANSI set in numeric order.
pub const terminal_labels = [_][]const u8{ "Foreground", "Background", "Cursor", "Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White", "Bright black", "Bright red", "Bright green", "Bright yellow", "Bright blue", "Bright magenta", "Bright cyan", "Bright white", "Cursor text" };

/// Accepts exactly #RRGGBB, with no alpha, whitespace, shell syntax or partial parse.
pub fn parse(text: []const u8) error{InvalidColor}!Terminal.Rgb {
    if (text.len != 7 or text[0] != '#') return error.InvalidColor;
    for (text[1..]) |byte| if (!(byte >= '0' and byte <= '9') and !(byte >= 'a' and byte <= 'f') and !(byte >= 'A' and byte <= 'F')) return error.InvalidColor;
    const value = std.fmt.parseUnsigned(u24, text[1..], 16) catch return error.InvalidColor;
    return unpack(value);
}
fn unpack(value: u24) Terminal.Rgb {
    return .{ .r = @truncate(value >> 16), .g = @truncate(value >> 8), .b = @truncate(value) };
}
fn optional(value: []const u8) error{InvalidColor}!void {
    if (value.len != 0) {
        // zig-audit: acknowledge discard
        // reason: This validation-only path checks parsing; resolved RGB is built separately after complete config acceptance.
        _ = try parse(value);
    }
}

test "palette overrides are strict RGB and leave unrelated colors and app roles independent" {
    for ([_][]const u8{ "#fff", "#12345678", "123456", "#+12345", "#12345g", " #123456", "#123456\n" }) |bad| try std.testing.expectError(error.InvalidColor, parse(bad));
    const rgb = try parse("#aB34Ef");
    try std.testing.expectEqual(@as(u8, 0xab), rgb.r);
    var term: TerminalColors = .{};
    term.ansi[1] = "#123456";
    const resolved = try term.resolve("howl_dark");
    try std.testing.expectEqual(try parse("#123456"), resolved.palette[1]);
    try std.testing.expectEqual((Terminal.ColorDefaults{}).palette[200], resolved.palette[200]);
    var app: Application = .{};
    try app.set(8, "#fedcba");
    try app.validate();
    try std.testing.expectEqual(try parse("#123456"), (try term.resolve("howl_dark")).palette[1]);
    try std.testing.expectError(error.InvalidColorRole, term.get(20));
    try std.testing.expectError(error.InvalidColorRole, app.set(9, "#000000"));
    try std.testing.expectError(error.InvalidTheme, term.resolve("unknown"));
}

test "family terminal defaults resolve completely while explicit roles override and extended slots remain native" {
    const native: Terminal.ColorDefaults = .{};
    for (themes.terminal_ids) |id| {
        const baseline = try (TerminalColors{}).resolve(id);
        var overrides: TerminalColors = .{ .foreground = "#123456", .background = "#654321", .cursor = "#abcdef" };
        overrides.ansi[4] = "#102030";
        const edited = try overrides.resolve(id);
        try std.testing.expectEqual(try parse("#123456"), edited.foreground);
        try std.testing.expectEqual(try parse("#654321"), edited.background);
        try std.testing.expectEqual(try parse("#abcdef"), edited.cursor.?);
        try std.testing.expectEqual(try parse("#102030"), edited.palette[4]);
        try std.testing.expectEqual(baseline.palette[3], edited.palette[3]);
        try std.testing.expectEqualSlices(Terminal.Rgb, native.palette[16..], edited.palette[16..]);
    }
    const solarized = try (TerminalColors{}).resolve("solarized_light");
    try std.testing.expectEqual(try parse("#fdf6e3"), solarized.background);
    try std.testing.expectEqual(try parse("#dc322f"), solarized.palette[1]);
    const gruvbox = try (TerminalColors{}).resolve("gruvbox_dark");
    try std.testing.expectEqual(try parse("#665c54"), gruvbox.cursor_text.?);
    try std.testing.expectError(error.InvalidTheme, (TerminalColors{}).resolve("slate"));
}
