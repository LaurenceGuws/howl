//! Encodes typed host input into bounded terminal byte sequences.

const std = @import("std");
const encoded_owner = @import("encoded.zig");

/// Caller-owned fixed storage for nonallocating input encodings.
pub const Scratch = struct {
    buf: [512]u8 = undefined,
};

/// Exact failures while constructing an encoded paste result.
pub const PasteError = error{ LengthOverflow, OutOfMemory };

/// Encode borrowed paste text for the active bracketed-paste mode.
///
/// Plain paste returns a borrowed view of `text` without allocating. Bracketed
/// paste allocates one caller-owned result containing the fixed CSI 200/201
/// pair. Encoded-length overflow is distinct from allocator exhaustion. The
/// caller must call `Encoded.deinit` once for either successful result.
pub fn encodePaste(bracketed_paste: bool, allocator: std.mem.Allocator, text: []const u8) PasteError!encoded_owner.Encoded {
    const start = if (bracketed_paste) "\x1b[200~" else "";
    const end = if (bracketed_paste) "\x1b[201~" else "";
    if (start.len == 0 and end.len == 0) return .{ .bytes = text };

    const encoded_len = try bracketedPasteLength(text.len);
    const out = try allocator.alloc(u8, encoded_len);
    std.debug.assert(out.len == encoded_len);
    @memcpy(out[0..start.len], start);
    @memcpy(out[start.len .. start.len + text.len], text);
    @memcpy(out[start.len + text.len ..], end);
    return .{ .allocator = allocator, .bytes = out };
}

fn bracketedPasteLength(text_len: usize) error{LengthOverflow}!usize {
    const with_start = std.math.add(usize, "\x1b[200~".len, text_len) catch return error.LengthOverflow;
    return std.math.add(usize, with_start, "\x1b[201~".len) catch return error.LengthOverflow;
}

/// Copy fixed protocol bytes into caller scratch storage.
///
/// The returned slice borrows `scratch` until its next use.
pub fn writeScratch(scratch: *Scratch, bytes: []const u8) []const u8 {
    std.debug.assert(bytes.len <= scratch.buf.len);
    @memcpy(scratch.buf[0..bytes.len], bytes);
    return scratch.buf[0..bytes.len];
}

test "bracketed paste length reports arithmetic overflow" {
    try std.testing.expectEqual(@as(usize, 15), try bracketedPasteLength(3));
    try std.testing.expectError(error.LengthOverflow, bracketedPasteLength(std.math.maxInt(usize)));
}
