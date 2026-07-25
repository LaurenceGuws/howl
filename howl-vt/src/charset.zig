//! Owns terminal character-set designation, invocation, and mapping state.

const std = @import("std");

const default_designations: [4]u8 = .{ 'B', 'B', 'B', 'B' };

/// Owns G0-G3 designations, GL/GR selection, and one-shot single shift.
pub const State = struct {
    designations: [4]u8 = default_designations,
    gl_index: u8 = 0,
    gr_index: u8 = 1,
    single_shift: ?u8 = null,

    /// Replaces one designation when the slot and repertoire are supported.
    pub fn configureCharset(self: *State, slot: u8, designation: u8) bool {
        if (slot >= self.designations.len) return false;
        if (!isSupportedDesignation(designation)) return false;
        if (self.designations[slot] == designation) return false;
        self.designations[slot] = designation;
        return true;
    }

    /// Selects one G0-G3 slot as GL and clears pending single shift.
    pub fn selectGl(self: *State, slot: u8) bool {
        if (slot >= self.designations.len) return false;
        if (self.gl_index == slot and self.single_shift == null) return false;
        self.gl_index = slot;
        self.single_shift = null;
        return true;
    }

    /// Selects one G1-G3 slot as GR without disturbing pending single shift.
    pub fn selectGr(self: *State, slot: u8) bool {
        if (slot == 0 or slot >= self.designations.len) return false;
        if (self.gr_index == slot) return false;
        self.gr_index = slot;
        return true;
    }

    /// Selects G2 or G3 for one following GL character.
    pub fn selectSingleShift(self: *State, slot: u8) bool {
        if (slot < 2 or slot > 3) return false;
        if (self.single_shift == slot) return false;
        self.single_shift = slot;
        return true;
    }

    /// Maps one parser codepoint and consumes pending GL single shift once.
    pub fn mapCodepoint(self: *State, codepoint: u21) u21 {
        if (codepoint >= 0x20 and codepoint <= 0x7e) {
            const slot = self.single_shift orelse self.gl_index;
            self.single_shift = null;
            return mapCharset(self.designations[slot], @intCast(codepoint), false);
        }
        if (codepoint >= 0xa0 and codepoint <= 0xfe) {
            return mapCharset(self.designations[self.gr_index], @intCast(codepoint - 0x80), true);
        }
        return codepoint;
    }

    /// Restores ASCII defaults for all designation and invocation state.
    pub fn reset(self: *State) bool {
        const before = self.*;
        self.* = .{};
        return !std.meta.eql(before, self.*);
    }
};

/// Returns whether one designation is implemented by the emulator.
fn isSupportedDesignation(designation: u8) bool {
    return std.mem.indexOfScalar(u8, "0ABUV", designation) != null;
}

fn mapCharset(designation: u8, byte: u8, gr: bool) u21 {
    return switch (designation) {
        '0' => mapDecSpecial(byte),
        'A' => if (byte == '#') 0x00a3 else charsetIdentity(byte, gr),
        'U' => mapCp437(byte, gr),
        'V' => mapVax42(byte, gr),
        else => charsetIdentity(byte, gr),
    };
}

fn charsetIdentity(byte: u8, gr: bool) u21 {
    return if (gr) @as(u21, byte) + 0x80 else byte;
}

// Maps the printable GR range shared by Kitty's CP437 and VAX-42 tables.
// CP437 GL is identity; C0 and C1 remain parser controls rather than glyphs.
const cp437_printable_gr = [95]u21{
    0x00e1, 0x00ed, 0x00f3, 0x00fa, 0x00f1, 0x00d1, 0x00aa, 0x00ba,
    0x00bf, 0x2310, 0x00ac, 0x00bd, 0x00bc, 0x00a1, 0x00ab, 0x00bb,
    0x2591, 0x2592, 0x2593, 0x2502, 0x2524, 0x2561, 0x2562, 0x2556,
    0x2555, 0x2563, 0x2551, 0x2557, 0x255d, 0x255c, 0x255b, 0x2510,
    0x2514, 0x2534, 0x252c, 0x251c, 0x2500, 0x253c, 0x255e, 0x255f,
    0x255a, 0x2554, 0x2569, 0x2566, 0x2560, 0x2550, 0x256c, 0x2567,
    0x2568, 0x2564, 0x2565, 0x2559, 0x2558, 0x2552, 0x2553, 0x256b,
    0x256a, 0x2518, 0x250c, 0x2588, 0x2584, 0x258c, 0x2590, 0x2580,
    0x03b1, 0x00df, 0x0393, 0x03c0, 0x03a3, 0x03c3, 0x00b5, 0x03c4,
    0x03a6, 0x0398, 0x03a9, 0x03b4, 0x221e, 0x03c6, 0x03b5, 0x2229,
    0x2261, 0x00b1, 0x2265, 0x2264, 0x2320, 0x2321, 0x00f7, 0x2248,
    0x00b0, 0x2219, 0x00b7, 0x221a, 0x207f, 0x00b2, 0x25a0,
};

fn mapCp437(byte: u8, gr: bool) u21 {
    if (!gr) return byte;
    if (byte < 0x20 or byte > 0x7e) return charsetIdentity(byte, true);
    return cp437_printable_gr[byte - 0x20];
}

fn mapVax42(byte: u8, gr: bool) u21 {
    if (gr) return mapCp437(byte, true);
    return switch (byte) {
        '!' => 0x043b,
        '?' => 0x0435,
        'a' => 0x0441,
        'h' => 0x0435,
        'o' => 0x043a,
        'r' => 0x0442,
        't' => 0x043b,
        'u' => 0x0435,
        else => byte,
    };
}

fn mapDecSpecial(byte: u8) u21 {
    return switch (byte) {
        '+' => 0x2192,
        ',' => 0x2190,
        '-' => 0x2191,
        '.' => 0x2193,
        '0' => 0x2588,
        '_' => 0x00a0,
        '`' => 0x25c6,
        'a' => 0x2592,
        'b' => 0x2409,
        'c' => 0x240c,
        'd' => 0x240d,
        'e' => 0x240a,
        'f' => 0x00b0,
        'g' => 0x00b1,
        'h' => 0x2591,
        'i' => 0x240b,
        'j' => 0x2518,
        'k' => 0x2510,
        'l' => 0x250c,
        'm' => 0x2514,
        'n' => 0x253c,
        'o' => 0x23ba,
        'p' => 0x23bb,
        'q' => 0x2500,
        'r' => 0x23bc,
        's' => 0x23bd,
        't' => 0x251c,
        'u' => 0x2524,
        'v' => 0x2534,
        'w' => 0x252c,
        'x' => 0x2502,
        'y' => 0x2264,
        'z' => 0x2265,
        '{' => 0x03c0,
        '|' => 0x2260,
        '}' => 0x00a3,
        '~' => 0x00b7,
        else => byte,
    };
}

test "charset accepts every designation and rejects hostile values unchanged" {
    var state: State = .{};
    for ("0ABUV") |designation| {
        for (0..state.designations.len) |slot| {
            try std.testing.expect(state.configureCharset(@intCast(slot), designation));
            try std.testing.expectEqual(designation, state.designations[slot]);
            try std.testing.expect(!state.configureCharset(@intCast(slot), designation));
        }
    }
    const before = state;
    try std.testing.expect(!state.configureCharset(4, 'B'));
    try std.testing.expect(!state.configureCharset(0, 'X'));
    try std.testing.expectEqualDeep(before, state);
    try std.testing.expect(!isSupportedDesignation(' '));
    try std.testing.expect(!isSupportedDesignation(0xff));
}

test "charset selection covers GL GR and one-shot SS2 SS3" {
    var state: State = .{};
    try std.testing.expect(state.selectGl(3));
    try std.testing.expectEqual(@as(u8, 3), state.gl_index);
    try std.testing.expect(state.selectGr(2));
    try std.testing.expectEqual(@as(u8, 2), state.gr_index);
    try std.testing.expect(state.selectSingleShift(2));
    try std.testing.expectEqual(@as(u21, 'A'), state.mapCodepoint('A'));
    try std.testing.expectEqual(@as(?u8, null), state.single_shift);
    try std.testing.expect(state.selectSingleShift(3));
    try std.testing.expectEqual(@as(u21, 'B'), state.mapCodepoint('B'));
    try std.testing.expectEqual(@as(?u8, null), state.single_shift);
    try std.testing.expect(state.selectSingleShift(2));
    try std.testing.expect(!state.selectSingleShift(2));
    try std.testing.expect(state.selectGr(1));
    try std.testing.expectEqual(@as(?u8, 2), state.single_shift);
    try std.testing.expectEqual(@as(u8, 1), state.gr_index);
    try std.testing.expectEqual(@as(u21, 0xa1), state.mapCodepoint(0xa1));
    try std.testing.expectEqual(@as(?u8, 2), state.single_shift);
    try std.testing.expectEqual(@as(u21, 'A'), state.mapCodepoint('A'));
    try std.testing.expectEqual(@as(?u8, null), state.single_shift);
}

test "charset single shifts select distinct G2 and G3 mappings once" {
    var state: State = .{};
    try std.testing.expect(state.configureCharset(2, '0'));
    try std.testing.expect(state.configureCharset(3, 'A'));

    try std.testing.expect(state.selectSingleShift(2));
    try std.testing.expectEqual(@as(u21, 0x2500), state.mapCodepoint('q'));
    try std.testing.expectEqual(@as(?u8, null), state.single_shift);
    try std.testing.expectEqual(@as(u21, 'q'), state.mapCodepoint('q'));

    try std.testing.expect(state.selectSingleShift(3));
    try std.testing.expectEqual(@as(u21, 0x00a3), state.mapCodepoint('#'));
    try std.testing.expectEqual(@as(?u8, null), state.single_shift);

    try std.testing.expect(state.selectSingleShift(2));
    try std.testing.expectEqual(@as(u21, 0xa1), state.mapCodepoint(0xa1));
    try std.testing.expectEqual(@as(?u8, 2), state.single_shift);
    try std.testing.expectEqual(@as(u21, 0x2500), state.mapCodepoint('q'));
    try std.testing.expectEqual(@as(?u8, null), state.single_shift);
}

test "charset selection invalid slots and repeated defaults are unchanged" {
    var state: State = .{};
    const before = state;
    try std.testing.expect(!state.selectGl(4));
    try std.testing.expect(!state.selectGr(0));
    try std.testing.expect(!state.selectGr(4));
    try std.testing.expect(!state.selectSingleShift(0));
    try std.testing.expect(!state.selectSingleShift(1));
    try std.testing.expect(!state.selectSingleShift(4));
    try std.testing.expect(!state.selectGl(0));
    try std.testing.expect(!state.selectGr(1));
    try std.testing.expectEqualDeep(before, state);
}

test "charset maps DEC special, UK, CP437, VAX42, identity, and hostile bytes" {
    var state: State = .{};
    try std.testing.expectEqual(@as(u21, 'A'), state.mapCodepoint('A'));
    try std.testing.expectEqual(@as(u21, 0xa1), state.mapCodepoint(0xa1));
    try std.testing.expect(state.configureCharset(0, '0'));
    try std.testing.expect(!state.selectGl(0));
    try std.testing.expectEqual(@as(u21, 0x2500), state.mapCodepoint('q'));
    try std.testing.expect(state.configureCharset(0, 'A'));
    try std.testing.expectEqual(@as(u21, 0x00a3), state.mapCodepoint('#'));
    try std.testing.expect(state.configureCharset(0, 'U'));
    try std.testing.expect(!state.selectGl(0));
    try std.testing.expectEqual(@as(u21, 'A'), state.mapCodepoint('A'));
    try std.testing.expect(state.configureCharset(1, 'U'));
    try std.testing.expect(!state.selectGr(1));
    try std.testing.expectEqual(@as(u21, 0x2502), state.mapCodepoint(0xb3));
    try std.testing.expect(state.configureCharset(0, 'V'));
    try std.testing.expectEqual(@as(u21, 0x043b), state.mapCodepoint('!'));
    try std.testing.expectEqual(@as(u21, 0x7f), state.mapCodepoint(0x7f));
    try std.testing.expectEqual(@as(u21, 0x80), state.mapCodepoint(0x80));
    try std.testing.expectEqual(@as(u21, 0xff), state.mapCodepoint(0xff));
}

test "charset reset returns exact ASCII defaults" {
    var state: State = .{};
    try std.testing.expect(state.configureCharset(2, '0'));
    try std.testing.expect(state.selectGl(2));
    try std.testing.expect(state.selectGr(3));
    try std.testing.expect(state.selectSingleShift(3));
    try std.testing.expect(state.reset());
    try std.testing.expectEqualDeep(State{}, state);
    try std.testing.expect(!state.reset());
}
