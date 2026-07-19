//! Owns incremental UTF-8 decoding for ground-state printable input.

const std = @import("std");

/// UTF-8 decode result union.
const Utf8Result = union(enum) {
    codepoint: u21,
    incomplete,
    invalid,
};

/// Incremental UTF-8 decoder state.
pub const Utf8Decoder = struct {
    buf: [4]u8 = undefined,
    len: u8 = 0,
    needed: u8 = 0,

    /// Reset decoder state.
    pub fn reset(self: *Utf8Decoder) void {
        self.len = 0;
        self.needed = 0;
    }

    /// Feed one byte and return decode state.
    pub fn feed(self: *Utf8Decoder, byte: u8) Utf8Result {
        if (self.needed == 0) {
            if (byte < 0x80) {
                return .{ .codepoint = @intCast(byte) };
            }
            const seq_len = std.unicode.utf8ByteSequenceLength(byte) catch return .invalid;
            std.debug.assert(seq_len > 1);
            self.buf[0] = byte;
            self.len = 1;
            self.needed = @intCast(seq_len);
            return .incomplete;
        }

        // Continuation byte required while sequence is incomplete.
        if ((byte & 0xC0) != 0x80) {
            self.reset();
            return .invalid;
        }
        self.buf[self.len] = byte;
        self.len += 1;

        if (self.len < self.needed) return .incomplete;

        const cp = std.unicode.utf8Decode(self.buf[0..self.needed]) catch {
            self.reset();
            return .invalid;
        };
        self.reset();
        return .{ .codepoint = cp };
    }
};

test "UTF8 decoder: ASCII passthrough" {
    var decoder = Utf8Decoder{};
    const result = decoder.feed('A');
    try std.testing.expectEqual(@as(u21, 'A'), result.codepoint);
}

test "UTF8 decoder: multi-byte sequence (€ = U+20AC)" {
    var decoder = Utf8Decoder{};
    var result = decoder.feed(0xE2);
    try std.testing.expect(result == .incomplete);
    result = decoder.feed(0x82);
    try std.testing.expect(result == .incomplete);
    result = decoder.feed(0xAC);
    try std.testing.expectEqual(@as(u21, 0x20AC), result.codepoint);
}

test "UTF8 decoder: invalid start leaves decoder clear" {
    var decoder = Utf8Decoder{};
    var result = decoder.feed(0x80);
    try std.testing.expect(result == .invalid);
    result = decoder.feed('A');
    try std.testing.expectEqual(@as(u21, 'A'), result.codepoint);
}

test "UTF8 decoder: invalid continuation resets partial sequence" {
    var decoder = Utf8Decoder{};
    var result = decoder.feed(0xE2);
    try std.testing.expect(result == .incomplete);
    result = decoder.feed('A');
    try std.testing.expect(result == .invalid);
    result = decoder.feed('B');
    try std.testing.expectEqual(@as(u21, 'B'), result.codepoint);
}
