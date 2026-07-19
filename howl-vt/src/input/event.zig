//! Defines the typed keyboard, text, paste, focus, and mouse input vocabulary.

const std = @import("std");
const keyboard = @import("keyboard.zig");
const mouse = @import("mouse.zig");

/// Borrow-free physical key event with typed identity and complete modifiers.
pub const KeyEvent = struct {
    key: keyboard.Key,
    mods: keyboard.Modifier = .{},
    action: keyboard.Action = .press,
    shifted: ?u21 = null,
    alternate: ?u21 = null,
    /// Borrows the exact bytes used only by legacy terminal encoding.
    legacy_text: []const u8 = "",
    /// Borrows committed text for this press/repeat until encoding returns.
    text: []const u8 = "",
};

/// Identifies host focus gained or lost for terminal focus reporting.
pub const FocusEvent = enum {
    in,
    out,
};

/// Host input borrowed by one terminal encoding call.
///
/// `bytes` carries committed text, while `key` carries a named or validated
/// Unicode physical-key event for terminal keyboard protocol encoding. Byte
/// and paste slices must remain valid until `Terminal.encodeInput` returns.
pub const Event = union(enum) {
    bytes: []const u8,
    key: KeyEvent,
    mouse: mouse.MouseEvent,
    focus: FocusEvent,
    paste: []const u8,
};

test "event owner exposes input union tags" {
    const key_event: Event = .{ .key = .{ .key = .{ .named = .enter } } };
    const focus_event: Event = .{ .focus = .in };

    try std.testing.expectEqual(@as(std.meta.Tag(Event), .key), std.meta.activeTag(key_event));
    try std.testing.expectEqual(@as(std.meta.Tag(Event), .focus), std.meta.activeTag(focus_event));
}
