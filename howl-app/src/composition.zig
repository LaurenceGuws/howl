const std = @import("std");

/// Client-local bounded preedit; no transient text enters canonical input.
pub const Composition = struct {
    bytes: [1024]u8 = undefined,
    len: usize = 0,
    start: i32 = 0,
    length: i32 = 0,
    accepted_after: u64 = 0,

    /// Retires transient text without changing its input-owner timestamp fence.
    pub fn clear(self: *Composition) void {
        self.len = 0;
        self.start = 0;
        self.length = 0;
    }
    /// Ownership changes discard already queued commits from the previous owner.
    pub fn cancel(self: *Composition, timestamp: u64) void {
        self.clear();
        self.accepted_after = @max(self.accepted_after, timestamp);
    }
    /// Rejects text events queued before the current owner acquired input.
    pub fn accepts(self: *const Composition, timestamp: u64) bool {
        return timestamp >= self.accepted_after;
    }
    /// Copies a complete bounded UTF-8 preedit; rejection clears old transient text.
    pub fn set(self: *Composition, supplied: []const u8, start: i32, length: i32) error{ PreeditLimit, InvalidPreedit }!void {
        self.clear();
        if (supplied.len > self.bytes.len) return error.PreeditLimit;
        if (!std.unicode.utf8ValidateSlice(supplied)) return error.InvalidPreedit;
        @memcpy(self.bytes[0..supplied.len], supplied);
        self.len = supplied.len;
        self.start = start;
        self.length = length;
    }
    /// Borrows only this UI-owned composition for synchronous rendering.
    pub fn text(self: *const Composition) []const u8 {
        return self.bytes[0..self.len];
    }
};

/// SDL editing positions count Unicode characters, not UTF-8 bytes.
pub fn byteOffset(text: []const u8, index: i32) usize {
    if (index <= 0) return 0;
    var characters: i32 = 0;
    for (text, 0..) |byte, offset| {
        if (byte & 0xc0 == 0x80) continue;
        if (characters == index) return offset;
        characters += 1;
    }
    return text.len;
}

test "preedit is bounded, clearable and cannot follow ownership changes" {
    var value: Composition = .{};
    try value.set("compose", 2, 3);
    try std.testing.expectEqualStrings("compose", value.text());
    try std.testing.expectEqual(@as(i32, 2), value.start);
    try std.testing.expectEqual(@as(i32, 3), value.length);
    value.cancel(100);
    try std.testing.expectEqual(@as(usize, 0), value.len);
    try std.testing.expect(!value.accepts(99));
    try std.testing.expect(value.accepts(100));
    const huge: [1025]u8 = @splat('x');
    try std.testing.expectError(error.PreeditLimit, value.set(&huge, 0, 0));
    try std.testing.expectEqual(@as(usize, 0), value.len);
    try std.testing.expectError(error.InvalidPreedit, value.set("\xff", 0, 0));
    try std.testing.expectEqual(@as(usize, 0), value.len);
    try value.set("abc", 1, 1);
    try value.set("", 0, 0);
    try std.testing.expectEqual(@as(usize, 0), value.len);
}

test "composition cursor maps Unicode characters to complete UTF-8 prefixes" {
    const text = "aé界z";
    for ([_]i32{ -1, 0, 1, 2, 3, 99 }, [_]usize{ 0, 0, 1, 3, 6, 7 }) |index, expected|
        try std.testing.expectEqual(expected, byteOffset(text, index));
}
