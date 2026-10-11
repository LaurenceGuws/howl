//! Owns Kitty-equivalent generated Unicode 17 width and grapheme properties.
//!
//! Provenance: Kitty d4106ef2db687579a69fefc949a6dc1b662f3ca8
//! `kitty/char-props-data.h` SHA-256
//! b93c81a8c54e2cfaa7b62585f0dc93172bbe2a4e21cec6def23065720c4bfdb4.
//! `kitty_tests/GraphemeBreakTest.json` SHA-256
//! 680e34a2773ab34d2ee0b4f3ee9a362cb95115ef54b1ad155cf746914f27c4d1.
//! Regenerate or check with the two `tools/generate_unicode_17*.py` tools.

const std = @import("std");

const data = @embedFile("unicode_17.bin");
const grapheme_tests = @embedFile("unicode_17_graphemes.bin");
const char_page_count = 4352;
const char_value_count = 46592;
const char_property_count = 106;
const grapheme_page_count = 4096;
const char_page_offset = 0;
const char_value_offset = char_page_offset + char_page_count;
const char_property_offset = char_value_offset + char_value_count;
const grapheme_page_offset = char_property_offset + char_property_count * 4;
const grapheme_value_offset = grapheme_page_offset + grapheme_page_count;

comptime {
    if (data.len != 61224) @compileError("invalid Unicode 17 table extent");
}

/// Borrows the generated Unicode 17 properties for one validated scalar.
pub const Properties = struct {
    value: u32,

    /// Returns Kitty's generated semantic terminal width.
    pub fn width(self: Properties) i4 {
        return @as(i4, @intCast((self.value >> 9) & 0x7)) - 4;
    }

    /// Reports a generated invalid/control scalar.
    pub fn isInvalid(self: Properties) bool {
        return self.value & (@as(u32, 1) << 19) != 0;
    }

    /// Reports a base whose width may be changed by VS15 or VS16.
    pub fn isEmojiPresentationBase(self: Properties) bool {
        return self.value & (@as(u32, 1) << 18) != 0;
    }

    /// Reports Kitty's generated broad emoji classification.
    pub fn isEmoji(self: Properties) bool {
        return self.value & (@as(u32, 1) << 12) != 0;
    }

    /// Reports a Unicode symbol-category scalar.
    pub fn isSymbol(self: Properties) bool {
        return self.value & (@as(u32, 1) << 21) != 0;
    }

    /// Reports a Unicode private-use scalar.
    pub fn isPrivateUse(self: Properties) bool {
        return (self.value >> 13) & 0x1f == 29;
    }

    fn graphemeProperty(self: Properties) u7 {
        return @intCast(self.value >> 25);
    }
};

/// Retains Kitty's generated bounded grapheme-transition state.
pub const GraphemeState = struct {
    value: u16 = 0,

    /// Advances the generated transition machine by one scalar property.
    pub fn step(self: GraphemeState, char_properties: Properties) GraphemeState {
        const key = (@as(usize, self.value >> 7) << 7) |
            char_properties.graphemeProperty();
        const page = data[grapheme_page_offset + (key >> 4)];
        const index = (@as(usize, page) << 4) | (key & 0xf);
        return .{ .value = readU16(grapheme_value_offset + index * 2) };
    }

    /// Reports whether the most recent transition joins the current grapheme.
    pub fn joinsCurrent(self: GraphemeState) bool {
        return self.value & (@as(u16, 1) << 6) != 0;
    }
};

/// Returns generated Unicode 17 properties for one scalar.
pub fn properties(codepoint: u21) Properties {
    const value: usize = codepoint;
    const page = data[char_page_offset + (value >> 8)];
    const index = (@as(usize, page) << 8) | (value & 0xff);
    const property_index: usize = data[char_value_offset + index];
    return .{ .value = readU32(char_property_offset + property_index * 4) };
}

fn readU16(offset: usize) u16 {
    return std.mem.readInt(u16, data[offset..][0..2], .little);
}

fn readU32(offset: usize) u32 {
    return std.mem.readInt(u32, data[offset..][0..4], .little);
}

test "Unicode 17 generated properties preserve width and presentation values" {
    try std.testing.expectEqual(@as(i4, 1), properties('A').width());
    try std.testing.expectEqual(@as(i4, 0), properties(0x0301).width());
    try std.testing.expectEqual(@as(i4, 2), properties(0x754c).width());
    try std.testing.expect(properties(0x263a).isEmojiPresentationBase());
    try std.testing.expect(properties(0x263a).isEmoji());
    try std.testing.expect(properties(0x2605).isSymbol());
    try std.testing.expect(properties(0xe0c1).isPrivateUse());
    try std.testing.expect(properties(0xd800).isInvalid());
}

test "Unicode 17 generated grapheme transitions preserve cluster boundaries" {
    var state = GraphemeState{};
    state = state.step(properties('a'));
    try std.testing.expect(state.joinsCurrent());
    state = state.step(properties(0x0301));
    try std.testing.expect(state.joinsCurrent());
    state = state.step(properties('b'));
    try std.testing.expect(!state.joinsCurrent());
}

test "Unicode 17 generated transitions pass Kitty's complete grapheme proof" {
    var offset: usize = 0;
    const test_count = readTestU16(&offset);
    for (0..test_count) |_| {
        const grapheme_count = grapheme_tests[offset];
        offset += 1;
        var state = GraphemeState{};
        for (0..grapheme_count) |grapheme_index| {
            const scalar_count = grapheme_tests[offset];
            offset += 1;
            for (0..scalar_count) |scalar_index| {
                const codepoint = readTestU32(&offset);
                state = state.step(properties(@intCast(codepoint)));
                if (scalar_index == 0 and grapheme_index != 0) {
                    try std.testing.expect(!state.joinsCurrent());
                } else {
                    try std.testing.expect(state.joinsCurrent());
                }
            }
        }
    }
    try std.testing.expectEqual(grapheme_tests.len, offset);
}

fn readTestU16(offset: *usize) u16 {
    const result = std.mem.readInt(
        u16,
        grapheme_tests[offset.*..][0..2],
        .little,
    );
    offset.* += 2;
    return result;
}

fn readTestU32(offset: *usize) u32 {
    const result = std.mem.readInt(
        u32,
        grapheme_tests[offset.*..][0..4],
        .little,
    );
    offset.* += 4;
    return result;
}
