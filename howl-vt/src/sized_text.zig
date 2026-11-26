//! OSC 66 sized-text grammar and bounded cluster admission.
//!
//! Screen owns cell mutation and scalar storage. This module only validates and
//! classifies the borrowed protocol payload before any screen mutation.

const std = @import("std");
const scalar_storage = @import("scalar_storage.zig");
const unicode = @import("unicode_17.zig");

/// Largest OSC 66 cell height admitted by this grammar.
pub const maximum_scale: u8 = 7;

/// Author wire bound applies to text bytes, not the metadata prefix.
pub const maximum_text_bytes: usize = 4096;

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
    if (result.text.len > maximum_text_bytes) return null;
    var fields = std.mem.splitScalar(u8, payload[0..separator], ':');
    while (fields.next()) |field| {
        if (field.len == 0) continue;
        if (field.len < 3 or field[1] != '=') return null;
        const value = parseNumber(field[2..]) orelse return null;
        switch (field[0]) {
            's' => result.scale = @intCast(@max(1, @min(value, maximum_scale))),
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

/// One bounded, complete block and its original text-byte offset.
pub const Cluster = struct {
    start: usize = 0,
    width: u8 = 0,
    count: u8 = 0,
    scalars: [scalar_storage.maximum_scalars]u21 = undefined,

    /// Borrows the admitted scalar sequence of this complete block.
    pub fn text(self: *const Cluster) []const u21 {
        return self.scalars[0..self.count];
    }
};

/// Shared admission and emission iterator. Natural width uses the same
/// generated properties and UAX29 state machine as ordinary terminal text.
pub const Clusters = struct {
    utf8: std.unicode.Utf8Iterator,
    explicit_width: u8,
    grapheme: unicode.GraphemeState = .{},

    /// Reports a cluster exceeding the canonical scalar-storage bound.
    pub const Error = error{ScalarLimit};

    /// Input is a validated UTF-8 slice, bounded by parse().
    pub fn init(value: Value) Clusters {
        return .{
            .utf8 = std.unicode.Utf8View.initUnchecked(value.text).iterator(),
            .explicit_width = value.width,
        };
    }

    /// Returns one block; at a boundary the next scalar remains unread.
    /// State is retained across boundaries (including regional indicators).
    pub fn next(self: *Clusters) Error!?Cluster {
        var cluster: Cluster = .{};
        var previous: ?unicode.Properties = null;
        while (true) {
            const start = self.utf8.i;
            const cp = self.utf8.nextCodepoint() orelse break;
            // The explicit-width lane preserves its existing safe-text
            // filtering; its application-supplied width always wins.
            if (isControl(cp)) continue;
            if (self.explicit_width == 0) {
                const props = unicode.properties(cp);
                if (props.isInvalid()) continue;
                const stepped = self.grapheme.step(props);
                const width = props.width();
                if (cluster.count != 0 and width != 0 and !stepped.joinsCurrent()) {
                    self.utf8.i = start;
                    break;
                }
                self.grapheme = stepped;
                if (cluster.count == 0) {
                    if (width == 0) continue;
                    cluster.width = if (width == 2) 2 else 1;
                } else if (stepped.joinsCurrent()) {
                    // Measure the completed grapheme before scaling it,
                    // as the author does for an in-command natural block.
                    if (cp == 0xfe0f and cluster.width == 1 and previous.?.isEmojiPresentationBase()) {
                        cluster.width = 2;
                    } else if (cp == 0xfe0e and cluster.width == 2 and previous.?.isEmojiPresentationBase()) {
                        cluster.width = 1;
                    } else if (props.isSpacingMark() and width > 0 and cluster.width == 1) {
                        cluster.width = 2;
                    }
                }
                previous = props;
            } else {
                cluster.width = self.explicit_width;
            }
            if (cluster.count == 0) cluster.start = start;
            if (cluster.count == scalar_storage.maximum_scalars) return error.ScalarLimit;
            cluster.scalars[cluster.count] = cp;
            cluster.count += 1;
        }
        return if (cluster.count == 0) null else cluster;
    }
};

fn isControl(codepoint: u21) bool {
    return codepoint < 0x20 or (codepoint >= 0x7f and codepoint <= 0x9f);
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
    var clusters = Clusters.init(value);
    var found = false;
    while (clusters.next() catch return false) |_| found = true;
    return found;
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

test "OSC 66 natural cluster iteration retains exact offsets and rejects overflowing clusters" {
    const value = parse(";\u{301}A\u{200b}界\u{ffff}B").?;
    var clusters = Clusters.init(value);
    const first = (try clusters.next()).?;
    try std.testing.expectEqual(@as(usize, 2), first.start);
    try std.testing.expectEqual(@as(u8, 1), first.width);
    try std.testing.expectEqualSlices(u21, &.{ 'A', 0x200b }, first.text());
    const second = (try clusters.next()).?;
    try std.testing.expectEqual(@as(usize, 6), second.start);
    try std.testing.expectEqual(@as(u8, 2), second.width);
    try std.testing.expectEqualSlices(u21, &.{0x754c}, second.text());
    const third = (try clusters.next()).?;
    try std.testing.expectEqual(@as(usize, 12), third.start);
    try std.testing.expectEqualSlices(u21, &.{'B'}, third.text());
    try std.testing.expect((try clusters.next()) == null);
    try std.testing.expect(parse(";\u{301}\u{200b}\u{ffff}") == null);

    const prefix = ";A";
    var payload: [prefix.len + 2 * scalar_storage.maximum_scalars]u8 = undefined;
    @memcpy(payload[0..prefix.len], prefix);
    for (0..scalar_storage.maximum_scalars) |index| {
        @memcpy(payload[prefix.len + 2 * index ..][0..2], "\u{301}");
    }
    try std.testing.expect(parse(payload[0 .. payload.len - 2]) != null);
    try std.testing.expect(parse(&payload) == null);
}
