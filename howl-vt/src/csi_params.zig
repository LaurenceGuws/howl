//! Provides bounded CSI parameter access and command-specific parameter decoding.

const std = @import("std");
const parser_mod = @import("parser.zig");
const cursor_mod = @import("screen/cursor.zig");
const erase = @import("screen/erase.zig");
const rect = @import("screen/rect.zig");

const csi_max_params = parser_mod.max_params;

/// Tracks colon separators across the parser-bounded CSI parameter array.
pub const CsiSeparatorList = parser_mod.CsiSeparatorList;

/// Stores at most the parser CSI parameter bound as clamped u16 mode values.
pub const ModeParams = struct {
    params: [csi_max_params]u16,
    param_count: u8,
};

/// Stores a bounded suffix of clamped u16 rectangular attribute values.
pub const AttrParams = struct {
    params: [csi_max_params]u16,
    param_count: u8,
};

fn count32(items: []const i32) u32 {
    std.debug.assert(items.len <= std.math.maxInt(u32));
    return @intCast(items.len);
}

/// Projects positive one-based parameters into optional zero-based rectangle edges.
pub fn optionalRectArea(params: []const i32) rect.OptionalRectArea {
    return .{
        .top = if (params.len >= 1 and params[0] > 0) paramOrDefault1(params[0]) - 1 else null,
        .left = if (params.len >= 2 and params[1] > 0) paramOrDefault1(params[1]) - 1 else null,
        .bottom = if (params.len >= 3 and params[2] > 0) paramOrDefault1(params[2]) - 1 else null,
        .right = if (params.len >= 4 and params[3] > 0) paramOrDefault1(params[3]) - 1 else null,
    };
}

/// Projects a parameter suffix into a zero-based rectangle with open bottom and right defaults.
pub fn rectArea(params: []const i32, start_idx: u8) rect.RectArea {
    const start = @as(u32, start_idx);
    const param_len = count32(params);
    return .{
        .top = if (param_len > start) paramOrDefault1(params[@intCast(start)]) - 1 else 0,
        .left = if (param_len > start + 1) paramOrDefault1(params[@intCast(start + 1)]) - 1 else 0,
        .bottom = if (param_len > start + 2) paramOrDefault1(params[@intCast(start + 2)]) - 1 else null,
        .right = if (param_len > start + 3) paramOrDefault1(params[@intCast(start + 3)]) - 1 else null,
    };
}

/// Copies a bounded parameter suffix into rectangular attribute storage.
pub fn attrParams(params: []const i32, start_idx: u8) AttrParams {
    var out = [_]u16{0} ** csi_max_params;
    const param_len = count32(params);
    var idx: u8 = start_idx;
    var dst: u8 = 0;
    while (idx < param_len and dst < csi_max_params) : ({
        idx += 1;
        dst += 1;
    }) {
        out[@intCast(dst)] = paramOrDefault0(params[@intCast(idx)]);
    }
    return .{ .params = out, .param_count = @intCast(dst) };
}

/// Accepts the ECMA-48 graphic ranges permitted by DECFRA.
pub fn isValidRectFillChar(ch: u16) bool {
    return (ch >= 32 and ch <= 126) or (ch >= 160 and ch <= 255);
}

/// Returns one for absent or nonpositive parameters and clamps positive values to u16.
pub fn paramAtOrDefault1(params: []const i32, idx: u8) u16 {
    return if (count32(params) > idx) paramOrDefault1(params[idx]) else 1;
}

/// Returns zero for absent or nonpositive parameters and clamps positive values to u16.
pub fn paramAtOrDefault0(params: []const i32, idx: u8) u16 {
    return if (count32(params) > idx) paramOrDefault0(params[idx]) else 0;
}

/// Returns an absent-zero key-format parameter clamped to u8.
pub fn keyFormatParamAtOrDefault0(params: []const i32, idx: u8) u8 {
    return @intCast(@min(paramAtOrDefault0(params, idx), std.math.maxInt(u8)));
}

/// Maps a numeric erase parameter to the terminal erase domain.
pub fn eraseMode(v: i32) erase.EraseMode {
    return switch (v) {
        1 => .start_to_cursor,
        2 => .all,
        3 => .scrollback,
        else => .cursor_to_end,
    };
}

/// Maps DECSCUSR parameters to an explicit cursor-style command.
pub fn cursorStyle(param: u16) cursor_mod.CursorStyleCommand {
    return switch (param) {
        0, 1 => .{ .program_override = .{ .shape = .block, .blink = true } },
        2 => .{ .program_override = .{ .shape = .block, .blink = false } },
        3 => .{ .program_override = .{ .shape = .underline, .blink = true } },
        4 => .{ .program_override = .{ .shape = .underline, .blink = false } },
        5 => .{ .program_override = .{ .shape = .bar, .blink = true } },
        6 => .{ .program_override = .{ .shape = .bar, .blink = false } },
        else => .{ .program_override = .{ .shape = .none, .blink = (param & 1) == 1 } },
    };
}

/// Copies parser-bounded mode parameters into clamped u16 storage.
pub fn collectParams(params: []const i32) ModeParams {
    var out = [_]u16{0} ** csi_max_params;
    const n = @min(count32(params), csi_max_params);
    var idx: u8 = 0;
    while (idx < n) : (idx += 1) out[@intCast(idx)] = paramOrDefault0(params[@intCast(idx)]);
    return .{ .params = out, .param_count = @intCast(n) };
}

fn paramOrDefault1(v: i32) u16 {
    if (v <= 0) return 1;
    if (v > std.math.maxInt(u16)) return std.math.maxInt(u16);
    return @intCast(v);
}

fn paramOrDefault0(v: i32) u16 {
    if (v <= 0) return 0;
    if (v > std.math.maxInt(u16)) return std.math.maxInt(u16);
    return @intCast(v);
}

/// Reports whether a borrowed intermediate-byte sequence contains one byte.
pub fn intermediatesHas(intermediates: []const u8, needle: u8) bool {
    return std.mem.indexOfScalar(u8, intermediates, needle) != null;
}
