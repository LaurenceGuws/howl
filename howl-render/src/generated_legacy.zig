//! Rasterizes the implemented Symbols for Legacy Computing sextants and octants.

const std = @import("std");
const geometry = @import("generated_geometry.zig");

const Range = geometry.Range;

/// Rasterizes one classified sextant codepoint, or returns
/// `error.UnsupportedGlyph` for an unclassified codepoint.
pub fn rasterizeGeneratedSextantAlpha(
    pixels: []u8,
    width: u16,
    height: u16,
    codepoint: u32,
) error{UnsupportedGlyph}!void {
    const sextant = switch (codepoint) {
        0x1fb00...0x1fb13 => @as(u8, @intCast(codepoint - 0x1fb00 + 1)),
        0x1fb14...0x1fb27 => @as(u8, @intCast(codepoint - 0x1fb00 + 2)),
        0x1fb28...0x1fb3b => @as(u8, @intCast(codepoint - 0x1fb00 + 3)),
        // The public classifier admits only the complete sextant range.
        else => return error.UnsupportedGlyph,
    };
    rasterizeSextantAlpha(pixels, width, height, sextant);
}

/// Rasterizes one classified octant codepoint or terminal alias, or returns
/// `error.UnsupportedGlyph` for an unclassified codepoint.
pub fn rasterizeGeneratedOctantAlpha(
    pixels: []u8,
    width: u16,
    height: u16,
    codepoint: u32,
) error{UnsupportedGlyph}!void {
    const octant = generatedOctantPattern(codepoint) orelse return error.UnsupportedGlyph;
    rasterizeOctantAlpha(pixels, width, height, octant);
}

fn generatedOctantPattern(codepoint: u32) ?u8 {
    return switch (codepoint) {
        0x1cd00...0x1cde5 => @intCast(codepoint - 0x1cd00),
        0x1fbe6 => 0xe6,
        0x1fbe7 => 0xe7,
        else => null,
    };
}

fn rasterizeOctantAlpha(pixels: []u8, width: u16, height: u16, which: u8) void {
    const mask = octantMask(which);
    if ((mask & 0x01) != 0) fillOctantSegment(pixels, width, height, 0, true);
    if ((mask & 0x02) != 0) fillOctantSegment(pixels, width, height, 1, true);
    if ((mask & 0x04) != 0) fillOctantSegment(pixels, width, height, 2, true);
    if ((mask & 0x08) != 0) fillOctantSegment(pixels, width, height, 3, true);
    if ((mask & 0x10) != 0) fillOctantSegment(pixels, width, height, 0, false);
    if ((mask & 0x20) != 0) fillOctantSegment(pixels, width, height, 1, false);
    if ((mask & 0x40) != 0) fillOctantSegment(pixels, width, height, 2, false);
    if ((mask & 0x80) != 0) fillOctantSegment(pixels, width, height, 3, false);
}

fn fillOctantSegment(pixels: []u8, width: u16, height: u16, which: u8, left: bool) void {
    const y_range = fourthRange(height, which);
    const x0: u16 = if (left) 0 else width / 2;
    const x1: u16 = if (left) width / 2 else width;
    if (x1 > x0 and y_range.end > y_range.start) geometry.fillRectAlpha(pixels, width, x0, y_range.start, x1 - x0, y_range.end - y_range.start, 255);
}

fn fourthRange(size: u16, which: u8) Range {
    const thickness = @max(@as(u16, 1), size / 4);
    const block = thickness * 4;
    if (block == size) return .{ .start = thickness * which, .end = thickness * (@as(u16, which) + 1) };
    if (block > size) {
        const start = @min(@as(u16, which) * thickness, geometry.saturatingSubU16(size, thickness));
        return .{ .start = start, .end = start + thickness };
    }

    var thicknesses = @as([4]u16, @splat(thickness));
    var extra = size - block;
    const order = [_]u8{ 1, 2, 3, 0 };
    for (order) |idx| {
        if (extra == 0) break;
        thicknesses[idx] += 1;
        extra -= 1;
    }
    var pos: u16 = 0;
    var idx: u8 = 0;
    while (idx < which) : (idx += 1) pos += thicknesses[idx];
    return .{ .start = pos, .end = pos + thicknesses[which] };
}

fn octantMask(which: u8) u8 {
    const a: u8 = 1;
    const b: u8 = 2;
    const c: u8 = 4;
    const d: u8 = 8;
    const m: u8 = 16;
    const n: u8 = 32;
    const o: u8 = 64;
    const p: u8 = 128;
    const mapping = [_]u8{
        b,                 b | m,             a | b | m,         n,                 a | n,             a | m | n,
        b | n,             a | b | n,         b | m | n,         c,                 a | c,             c | m,
        a | c | m,         a | b | c,         b | c | m,         a | b | c | m,     c | n,             a | c | n,
        c | m | n,         a | c | m | n,     b | c | n,         a | b | c | n,     b | c | m | n,     a | b | c | m | n,
        o,                 a | o,             m | o,             a | m | o,         b | o,             a | b | o,
        b | m | o,         a | b | m | o,     a | n | o,         m | n | o,         a | m | n | o,     b | n | o,
        a | b | n | o,     b | m | n | o,     a | b | m | n | o, c | o,             a | c | o,         c | m | o,
        a | c | m | o,     b | c | o,         a | b | c | o,     b | c | m | o,     a | b | c | m | o, c | n | o,
        a | c | n | o,     c | m | n | o,     a | c | m | n | o, b | c | n | o,     a | b | c | n | o, b | c | m | n | o,
        a | d,             d | m,             a | d | m,         b | d,             a | b | d,         b | d | m,
        a | b | d | m,     d | n,             a | d | n,         d | m | n,         a | d | m | n,     b | d | n,
        a | b | d | n,     b | d | m | n,     a | b | d | m | n, a | c | d,         c | d | m,         a | c | d | m,
        b | c | d,         b | c | d | m,     a | b | c | d | m, c | d | n,         a | c | d | n,     a | c | d | m | n,
        b | c | d | n,     a | b | c | d | n, b | c | d | m | n, d | o,             a | d | o,         d | m | o,
        a | d | m | o,     b | d | o,         a | b | d | o,     b | d | m | o,     a | b | d | m | o, d | n | o,
        a | d | n | o,     d | m | n | o,     a | d | m | n | o, b | d | n | o,     a | b | d | n | o, b | d | m | n | o,
        ~(c | p),          c | d | o,         a | c | d | o,     c | d | m | o,     a | c | d | m | o, b | c | d | o,
        ~(m | n | p),      b | c | d | m | o, ~(n | p),          c | d | n | o,     a | c | d | n | o, c | d | m | n | o,
        ~(b | p),          b | c | d | n | o, ~(m | p),          ~(a | p),          ~p,                a | p,
        m | p,             a | m | p,         b | p,             a | b | p,         b | m | p,         a | b | m | p,
        n | p,             a | n | p,         m | n | p,         a | m | n | p,     b | n | p,         a | b | n | p,
        b | m | n | p,     ~(c | d | o),      c | p,             a | c | p,         c | m | p,         a | c | m | p,
        b | c | p,         a | b | c | p,     b | c | m | p,     ~(d | n | o),      c | n | p,         a | c | n | p,
        c | m | n | p,     ~(b | d | o),      b | c | n | p,     ~(d | m | o),      ~(a | d | o),      ~(d | o),
        a | o | p,         m | o | p,         a | m | o | p,     b | o | p,         b | m | o | p,     a | b | m | o | p,
        n | o | p,         a | n | o | p,     a | m | n | o | p, b | n | o | p,     a | b | n | o | p, b | m | n | o | p,
        c | o | p,         a | c | o | p,     c | m | o | p,     a | c | m | o | p, b | c | o | p,     a | b | c | o | p,
        b | c | m | o | p, ~(n | d),          c | n | o | p,     a | c | n | o | p, c | m | n | o | p, ~(b | d),
        b | c | n | o | p, ~(d | m),          ~(a | d),          ~d,                a | d | p,         d | m | p,
        a | d | m | p,     b | d | p,         a | b | d | p,     b | d | m | p,     a | b | d | m | p, d | n | p,
        a | d | n | p,     d | m | n | p,     a | d | m | n | p, b | d | n | p,     a | b | d | n | p, b | d | m | n | p,
        ~(c | o),          c | d | p,         a | c | d | p,     c | d | m | p,     a | c | d | m | p, b | c | d | p,
        a | b | c | d | p, b | c | d | m | p, ~(n | o),          c | d | n | p,     a | c | d | n | p, c | d | m | n | p,
        ~(b | o),          b | c | d | n | p, ~(m | o),          ~(a | o),          ~o,                d | o | p,
        a | d | o | p,     d | m | o | p,     a | d | m | o | p, b | d | o | p,     a | b | d | o | p, b | d | m | o | p,
        ~(c | n),          d | n | o | p,     a | d | n | o | p, d | m | n | o | p, ~(b | c),          b | d | n | o | p,
        ~(c | m),          ~(a | c),          ~c,                a | c | d | o | p, c | d | m | o | p, ~(b | n),
        b | c | d | o | p, ~(a | n),          ~n,                c | d | n | o | p, ~(b | m),          ~b,
        ~m,                ~a,                b | c,             n | o,
    };
    return mapping[which];
}

fn rasterizeSextantAlpha(pixels: []u8, width: u16, height: u16, which: u8) void {
    // Unicode numbers the three left cells before the three right cells.
    if ((which & 0x01) != 0) fillSextantCell(pixels, width, height, 0, 0);
    if ((which & 0x02) != 0) fillSextantCell(pixels, width, height, 1, 0);
    if ((which & 0x04) != 0) fillSextantCell(pixels, width, height, 2, 0);
    if ((which & 0x08) != 0) fillSextantCell(pixels, width, height, 0, 1);
    if ((which & 0x10) != 0) fillSextantCell(pixels, width, height, 1, 1);
    if ((which & 0x20) != 0) fillSextantCell(pixels, width, height, 2, 1);
}

fn fillSextantCell(pixels: []u8, width: u16, height: u16, row: u16, col: u16) void {
    const y0: u16 = @intCast(@as(u32, height) * @as(u32, row) / 3);
    const y1: u16 = @intCast(@as(u32, height) * @as(u32, row + 1) / 3);
    const x0: u16 = if (col == 0) 0 else width / 2;
    const x1: u16 = if (col == 0) width / 2 else width;
    if (x1 > x0 and y1 > y0) geometry.fillRectAlpha(pixels, width, x0, y0, x1 - x0, y1 - y0, 255);
}

test "every sextant codepoint maps its exact six-cell occupancy" {
    var pixels: [2 * 3]u8 = undefined;
    var codepoint: u32 = 0x1fb00;
    while (codepoint <= 0x1fb3b) : (codepoint += 1) {
        const expected: u8 = @intCast(codepoint - 0x1fb00 + 1 +
            @as(u32, @intFromBool(codepoint >= 0x1fb14)) +
            @as(u32, @intFromBool(codepoint >= 0x1fb28)));
        @memset(&pixels, 0);
        try rasterizeGeneratedSextantAlpha(&pixels, 2, 3, codepoint);
        var actual: u8 = 0;
        const bit_at = [_]u8{ 0, 3, 1, 4, 2, 5 };
        for (bit_at, 0..) |bit, offset| {
            if (pixels[offset] != 0)
                actual |= @as(u8, 1) << @intCast(bit);
        }
        try std.testing.expectEqual(expected, actual);
    }
}

test "every octant codepoint maps its exact eight-cell occupancy" {
    var pixels: [2 * 4]u8 = undefined;
    var codepoint: u32 = 0x1cd00;
    while (codepoint <= 0x1cde5) : (codepoint += 1) {
        try expectOctantOccupancy(
            &pixels,
            codepoint,
            @intCast(codepoint - 0x1cd00),
        );
    }
    try expectOctantOccupancy(&pixels, 0x1fbe6, 0xe6);
    try expectOctantOccupancy(&pixels, 0x1fbe7, 0xe7);
}

fn expectOctantOccupancy(
    pixels: *[2 * 4]u8,
    codepoint: u32,
    pattern: u8,
) !void {
    @memset(pixels, 0);
    try rasterizeGeneratedOctantAlpha(pixels, 2, 4, codepoint);
    var actual: u8 = 0;
    for (0..4) |row| {
        if (pixels[row * 2] != 0) actual |= @as(u8, 1) << @intCast(row);
        if (pixels[row * 2 + 1] != 0)
            actual |= @as(u8, 1) << @intCast(row + 4);
    }
    try std.testing.expectEqual(octantMask(pattern), actual);
}
