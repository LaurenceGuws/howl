//! Bounded tab-local display overrides; terminal OSC titles remain canonical.
const std = @import("std");

/// Maximum bytes in one manually supplied UTF-8 tab name.
pub const limit = 256;

/// A manual display name belongs to a tab, never its process or saved recipe.
pub const Title = struct {
    bytes: [limit]u8 = undefined,
    len: usize = 0,

    /// Validates a whole replacement before changing the accepted name.
    pub fn set(self: *Title, supplied: []const u8) error{ InvalidTabName, TabNameLimit }!void {
        const text = std.mem.trim(u8, supplied, " ");
        if (text.len > limit) return error.TabNameLimit;
        if (!valid(text)) return error.InvalidTabName;
        @memcpy(self.bytes[0..text.len], text);
        self.len = text.len;
    }
    /// Empty input restores the latest automatic title rather than a frozen copy.
    pub fn resolve(self: *const Title, automatic: []const u8) []const u8 {
        return if (self.len == 0) automatic else self.bytes[0..self.len];
    }
    /// Removes only the display override.
    pub fn clear(self: *Title) void {
        self.len = 0;
    }
};

/// A label is complete UTF-8 with no ASCII control bytes.
pub fn valid(text: []const u8) bool {
    if (!std.unicode.utf8ValidateSlice(text)) return false;
    for (text) |byte| if (byte < 0x20 or byte == 0x7f) return false;
    return true;
}

test "tab override survives automatic changes and clears to the latest title" {
    var title: Title = .{};
    try std.testing.expectEqualStrings("shell", title.resolve("shell"));
    try title.set("  Hannes — 界  ");
    try std.testing.expectEqualStrings("Hannes — 界", title.resolve("vim"));
    try title.set("   ");
    try std.testing.expectEqualStrings("latest", title.resolve("latest"));
    try title.set("build");
    title.clear();
    try std.testing.expectEqualStrings("ssh", title.resolve("ssh"));
}

test "tab name limits and invalid text preserve the accepted override" {
    var title: Title = .{};
    try title.set("safe");
    for ([_][]const u8{ "bad\nname", "\x1b]0;bad", "\xff", "\x7f" }) |text| {
        try std.testing.expectError(error.InvalidTabName, title.set(text));
        try std.testing.expectEqualStrings("safe", title.resolve("automatic"));
    }
    const huge: [limit + 1]u8 = @splat('x');
    try std.testing.expectError(error.TabNameLimit, title.set(&huge));
    try std.testing.expectEqualStrings("safe", title.resolve("automatic"));
    try title.set(huge[0..limit]);
    try std.testing.expectEqual(@as(usize, limit), title.len);
}
