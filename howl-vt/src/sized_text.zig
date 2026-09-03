//! OSC 66 sized-text grammar and bounded cluster admission.
//!
//! Screen owns cell mutation and scalar storage. This module only validates and
//! classifies the borrowed protocol payload before any screen mutation.

const std = @import("std");
const scalar_storage = @import("scalar_storage.zig");

/// Borrows one validated OSC 66 payload and its clamped presentation fields.
pub const Value = struct {
    text: []const u8,
    scale: u8 = 1,
    width: u8 = 0,
    subscale_n: u4 = 0,
    subscale_d: u4 = 0,
    vertical_align: u2 = 0,
    horizontal_align: u2 = 0,
};

/// Parses and validates one complete OSC 66 payload without retaining bytes.
pub fn parse(payload: []const u8) ?Value {
    const separator = std.mem.indexOfScalar(u8, payload, ';') orelse return null;
    var result = Value{ .text = payload[separator + 1 ..] };
    var fields = std.mem.splitScalar(u8, payload[0..separator], ':');
    while (fields.next()) |field| {
        if (field.len == 0) continue;
        if (field.len < 3 or field[1] != '=') return null;
        const value = parseNumber(field[2..]) orelse return null;
        switch (field[0]) {
            's' => result.scale = @intCast(@max(1, @min(value, 7))),
            'w' => result.width = @intCast(@min(value, 7)),
            'n' => result.subscale_n = @intCast(@min(value, 15)),
            'd' => result.subscale_d = @intCast(@min(value, 15)),
            'v' => result.vertical_align = @intCast(@min(value, 3)),
            'h' => result.horizontal_align = @intCast(@min(value, 3)),
            else => return null,
        }
    }
    if (!std.unicode.utf8ValidateSlice(result.text)) return null;
    if (!validText(result)) return null;
    return result;
}

/// Reports controls ignored while projecting OSC 66 text into cell clusters.
pub fn isIgnoredCodepoint(codepoint: u21) bool {
    return codepoint < 0x20 or (codepoint >= 0x7f and codepoint <= 0x9f);
}

/// Reports codepoints retained as trailing marks in OSC 66's bounded cluster model.
pub fn isTrailingCombiningCodepoint(codepoint: u21) bool {
    return switch (codepoint) {
        0x0300...0x036F,
        0x0483...0x0489,
        0x0591...0x05BD,
        0x05BF,
        0x05C1...0x05C2,
        0x05C4...0x05C5,
        0x0610...0x061A,
        0x064B...0x065F,
        0x0670,
        0x06D6...0x06DC,
        0x06DF...0x06E4,
        0x06E7...0x06E8,
        0x06EB...0x06EC,
        0x0730...0x074A,
        0x07EB...0x07F3,
        0x0816...0x0819,
        0x081B...0x0823,
        0x0825...0x0827,
        0x0829...0x082D,
        0x0951...0x0954,
        0x0F82...0x0F83,
        0x0F86...0x0F87,
        0x135D...0x135F,
        0x17DD,
        0x193A,
        0x1A17,
        0x1A75...0x1A7C,
        0x1B6B...0x1B73,
        0x1CD0...0x1CD2,
        0x1CDA...0x1CDB,
        0x1CE0,
        0x1AB0...0x1AFF,
        0x1DC0...0x1DFF,
        0x20D0...0x20FF,
        0x2CEF...0x2CF1,
        0x2DE0...0x2DFF,
        0xA66F,
        0xA67C...0xA67D,
        0xA6F0...0xA6F1,
        0xA8E0...0xA8F1,
        0xAAB0,
        0xAAB2...0xAAB3,
        0xAAB7...0xAAB8,
        0xAABE...0xAABF,
        0xAAC1,
        0x200C...0x200D,
        0xFE00...0xFE0F,
        0xFE20...0xFE2F,
        0x10A0F,
        0x10A38,
        0x1D185...0x1D189,
        0x1D1AA...0x1D1AD,
        0x1D242...0x1D244,
        0xE0100...0xE01EF,
        => true,
        else => false,
    };
}

fn parseNumber(bytes: []const u8) ?u32 {
    if (bytes.len == 0 or bytes.len > 10) return null;
    var value: u64 = 0;
    for (bytes) |byte| {
        if (byte < '0' or byte > '9') return null;
        value = value * 10 + byte - '0';
        if (value > std.math.maxInt(u32)) return null;
    }
    return @intCast(value);
}

fn validText(value: Value) bool {
    var iterator = std.unicode.Utf8View.initUnchecked(value.text).iterator();
    var cluster_len: u8 = 0;
    var cluster_count: usize = 0;
    while (iterator.nextCodepoint()) |codepoint| {
        if (isIgnoredCodepoint(codepoint)) continue;
        if (value.width == 0 and cluster_len != 0 and !isTrailingCombiningCodepoint(codepoint)) {
            cluster_count += 1;
            cluster_len = 0;
        }
        if (cluster_len == scalar_storage.maximum_scalars) return false;
        cluster_len += 1;
    }
    if (cluster_len != 0) cluster_count += 1;
    return cluster_count != 0 and (value.width == 0 or cluster_count == 1);
}

test "OSC 66 fields parse clamp and retain borrowed text exactly" {
    const value = parse("s=0:w=99:n=31:d=16:v=9:h=4;Howl").?;
    try std.testing.expectEqualStrings("Howl", value.text);
    try std.testing.expectEqual(@as(u8, 1), value.scale);
    try std.testing.expectEqual(@as(u8, 7), value.width);
    try std.testing.expectEqual(@as(u4, 15), value.subscale_n);
    try std.testing.expectEqual(@as(u4, 15), value.subscale_d);
    try std.testing.expectEqual(@as(u2, 3), value.vertical_align);
    try std.testing.expectEqual(@as(u2, 3), value.horizontal_align);

    const scaled = parse("s=999;x").?;
    try std.testing.expectEqual(@as(u8, 7), scaled.scale);
}

test "OSC 66 rejects malformed fields numbers UTF8 and empty visible text" {
    try std.testing.expect(parse("missing-separator") == null);
    try std.testing.expect(parse("x=1;text") == null);
    try std.testing.expect(parse("s;text") == null);
    try std.testing.expect(parse("s=;text") == null);
    try std.testing.expect(parse("s=-1;text") == null);
    try std.testing.expect(parse("s=4294967296;text") == null);
    try std.testing.expect(parse(";\x00\x1f\x7f\xc2\x80") == null);
    try std.testing.expect(parse(&.{ ';', 0xff }) == null);
}

test "OSC 66 cluster admission distinguishes implicit and explicit width" {
    try std.testing.expect(parse(";ab") != null);
    try std.testing.expect(parse(";a\xcc\x81") != null);
    try std.testing.expect(parse("w=2;ab") != null);
    try std.testing.expect(parse("w=2;") == null);

    var payload: [1 + scalar_storage.maximum_scalars + 1]u8 = undefined;
    payload[0] = ';';
    @memset(payload[1..], 0x41);
    try std.testing.expect(parse(&payload) != null);

    var explicit: [5 + 2 * scalar_storage.maximum_scalars]u8 = undefined;
    @memcpy(explicit[0..4], "w=1;");
    explicit[4] = 'a';
    for (0..scalar_storage.maximum_scalars) |index| {
        explicit[5 + 2 * index] = 0xcc;
        explicit[6 + 2 * index] = 0x81;
    }
    try std.testing.expect(parse(&explicit) == null);
}

test "OSC 66 trailing-combining classification preserves selected boundaries" {
    try std.testing.expect(isTrailingCombiningCodepoint(0x0301));
    try std.testing.expect(isTrailingCombiningCodepoint(0x200d));
    try std.testing.expect(isTrailingCombiningCodepoint(0xE0100));
    try std.testing.expect(!isTrailingCombiningCodepoint('a'));
    try std.testing.expect(!isTrailingCombiningCodepoint(0x1F600));
    try std.testing.expect(isIgnoredCodepoint(0x1f));
    try std.testing.expect(isIgnoredCodepoint(0x80));
    try std.testing.expect(!isIgnoredCodepoint(' '));
}
