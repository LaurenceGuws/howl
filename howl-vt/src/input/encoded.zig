//! Owns encoded input bytes that may borrow scratch storage or hold an allocation.

const std = @import("std");

/// Holds encoded bytes that either borrow caller scratch or own one allocation.
pub const Encoded = struct {
    allocator: ?std.mem.Allocator = null,
    bytes: []const u8 = "",

    /// Release owned bytes, or only clear a borrowed result.
    ///
    /// Every successful input encoding result accepts one call. The value is
    /// reset afterward so it retains neither ownership nor a borrowed slice.
    pub fn deinit(self: *Encoded) void {
        if (self.allocator) |allocator| allocator.free(self.bytes);
        self.* = .{};
    }
};

test "encoded owner deinit releases owned buffer" {
    const allocator = std.testing.allocator;
    const bytes = try allocator.dupe(u8, "payload");
    var encoded: Encoded = .{ .allocator = allocator, .bytes = bytes };

    encoded.deinit();

    try std.testing.expectEqual(@as(?std.mem.Allocator, null), encoded.allocator);
    try std.testing.expectEqualStrings("", encoded.bytes);
}
