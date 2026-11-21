//! Terminal color-control protocol grammar and bounded reply application.
//!
//! Persistent color storage/defaults live in `properties.zig`. This owner
//! interprets xterm/Kitty/iTerm color controls, mutates borrowed ColorState,
//! emits exact bounded replies. Terminal projects only committed cursor state.

const std = @import("std");
const properties = @import("properties.zig");
const replies = @import("replies.zig");

const Rgb = properties.Rgb;
const KittyColorState = properties.ColorState;

/// Borrows one terminal color-control command until synchronous application.
pub const Command = union(enum) {
    osc: struct { command: u16, payload: []const u8, reply_bel: bool = false },
    linux_palette: []const u8,
};

fn byteCount(bytes: []const u8) u32 {
    std.debug.assert(bytes.len <= std.math.maxInt(u32));
    return @intCast(bytes.len);
}

/// Applies one xterm/Kitty color command transactionally and reports mutation.
pub fn apply(
    allocator: std.mem.Allocator,
    colors: *properties.ColorState,
    defaults: *const properties.ColorState,
    output: *replies.Buffer,
    encode_buf: []u8,
    command: Command,
) replies.AppendError!bool {
    const osc = switch (command) {
        .linux_palette => |bytes| return applyLinuxPalette(colors, bytes),
        .osc => |value| value,
    };
    // OSC 104 only resets individual ColorState slots. It never allocates
    // or emits replies, so it needs no snapshot/rollback transaction.
    if (osc.command == 104) return resetXtermPalette(colors, osc.payload, defaults);
    const before = colors.*;
    const output_before = output.len();
    errdefer {
        colors.* = before;
        output.truncate(output_before);
    }
    switch (osc.command) {
        21 => try handleKittyControl(colors, output, osc.payload, defaults),
        4 => try handleXtermPaletteControl(allocator, colors, output, encode_buf, osc.payload, osc.reply_bel),
        5 => try handleXtermSpecialPaletteControl(allocator, colors, output, encode_buf, osc.payload, osc.reply_bel),
        10, 11, 12, 13, 14, 15, 16, 17, 18, 19 => try handleXtermDynamicColor(
            allocator,
            colors,
            output,
            encode_buf,
            osc.command,
            osc.payload,
            osc.reply_bel,
        ),
        110, 111, 112, 113, 114, 115, 116, 117, 118, 119 => resetXtermDynamicColor(
            colors,
            osc.command,
            osc.payload,
            defaults,
        ),
        else => {},
    }
    return !std.meta.eql(before, colors.*) or output_before != output.len();
}

// iTerm2's Linux OSC P is exactly seven bytes after P (one selector and
// three hex RGB pairs). It mutates the same canonical ColorState as OSC 4/10.
fn applyLinuxPalette(colors: *properties.ColorState, bytes: []const u8) bool {
    if (bytes.len != 7) return false;
    const index: u8 = switch (bytes[0]) {
        '0'...'9' => bytes[0] - '0',
        'a'...'f' => bytes[0] - 'a' + 10,
        'A'...'F' => bytes[0] - 'A' + 10,
        'g'...'m' => bytes[0] - 'g' + 16,
        else => return false,
    };
    const color: Rgb = .{
        .r = std.fmt.parseUnsigned(u8, bytes[1..3], 16) catch return false,
        .g = std.fmt.parseUnsigned(u8, bytes[3..5], 16) catch return false,
        .b = std.fmt.parseUnsigned(u8, bytes[5..7], 16) catch return false,
    };
    // Map each selector to exactly one canonical color slot. Optional
    // presentation colors remain nullable; palette and defaults do not.
    const Target = union(enum) { required: *Rgb, optional: *?Rgb };
    const target: Target = switch (index) {
        0...15 => .{ .required = &colors.palette[index] },
        16 => .{ .required = &colors.foreground },
        17 => .{ .required = &colors.background },
        18 => .{ .optional = &colors.bold },
        19 => .{ .optional = &colors.selection_background },
        20 => .{ .optional = &colors.selection_foreground },
        21 => .{ .optional = &colors.cursor },
        22 => .{ .optional = &colors.cursor_text },
        else => return false,
    };
    // One seven-byte update can only mutate this slot and cannot fail.
    // Avoid copying all 256 colors just to detect a repeated value.
    return switch (target) {
        .required => |slot| result: {
            if (std.meta.eql(slot.*, color)) break :result false;
            slot.* = color;
            break :result true;
        },
        .optional => |slot| result: {
            if (slot.*) |previous| {
                if (std.meta.eql(previous, color)) break :result false;
            }
            slot.* = color;
            break :result true;
        },
    };
}

/// Applies the accepted iTerm SetColors subset and reports retained mutation.
pub fn applyItermSetColors(colors: *properties.ColorState, defaults: *const properties.ColorState, payload: []const u8) bool {
    const before = colors.*;
    handleItermSetColors(colors, defaults, payload);
    return !std.meta.eql(before, colors.*);
}

// Applies one Kitty color control or appends its bounded query reply.
fn handleKittyControl(
    colors: *KittyColorState,
    output: *replies.Buffer,
    payload: []const u8,
    defaults: *const properties.ColorState,
) replies.AppendError!void {
    // Kitty collects every queried key into one OSC 21 response, in input
    // order. The outer apply transaction owns both colour and reply rollback.
    var replying = false;
    var parts = std.mem.splitScalar(u8, payload, ';');
    while (parts.next()) |raw_part| {
        const part = std.mem.trim(u8, raw_part, " \t\r\n");
        if (part.len == 0) continue;
        const eq = std.mem.indexOfScalar(u8, part, '=');
        if (eq) |pos| {
            const key = std.mem.trim(u8, part[0..pos], " \t");
            const value = std.mem.trim(u8, part[pos + 1 ..], " \t");
            if (std.mem.eql(u8, value, "?")) {
                if (!replying) {
                    try output.appendControl(.kitty, .osc);
                    try output.append("21");
                    replying = true;
                }
                try output.append(";");
                try output.append(key);
                try output.append("=");
                if (colorForKey(colors, key)) |color| {
                    try appendKittyColorOsc(output, color);
                } else if (!isKnownColorKey(key)) {
                    try output.append("?");
                }
            } else {
                setColorKey(colors, key, value);
            }
        } else {
            resetColorKey(colors, std.mem.trim(u8, part, " \t"), defaults);
        }
    }
    if (replying) try output.appendControl(.kitty, .st);
}

// Kitty OSC 21 uses two hex digits per RGB component. Other OSC color
// replies intentionally retain their distinct four-digit xterm spelling.
fn appendKittyColorOsc(output: *replies.Buffer, color: Rgb) replies.AppendError!void {
    const digits = "0123456789abcdef";
    var text = "rgb:00/00/00".*;
    text[4] = digits[color.r >> 4];
    text[5] = digits[color.r & 0x0f];
    text[7] = digits[color.g >> 4];
    text[8] = digits[color.g & 0x0f];
    text[10] = digits[color.b >> 4];
    text[11] = digits[color.b & 0x0f];
    try output.append(&text);
}

const color_osc_max_bytes = 18;

const TerminalColorState = properties.ColorState;

const SpecialKey = enum { foreground, background, cursor, cursor_text, selection_background, selection_foreground };
const DynamicKey = enum {
    foreground,
    background,
    cursor,
    pointer_foreground,
    pointer_background,
    tektronix_foreground,
    tektronix_background,
    selection_background,
    tektronix_cursor,
    selection_foreground,
};
// Applies or answers one OSC 4 palette request transactionally.
fn handleXtermPaletteControl(
    allocator: std.mem.Allocator,
    colors: *TerminalColorState,
    output: *replies.Buffer,
    encode_buf: []u8,
    payload: []const u8,
    reply_bel: bool,
) replies.AppendError!void {
    // A dangling index has no color/query operand. Reject the complete
    // malformed command before modifying palette or emitting any reply.
    if (std.mem.count(u8, payload, ";") % 2 == 0) return;
    var parts = std.mem.splitScalar(u8, payload, ';');
    while (parts.next()) |idx_text| {
        const value = parts.next() orelse break;
        const idx = std.fmt.parseUnsigned(u16, idx_text, 10) catch continue;
        // Queries outside both the ordinary and supported xterm special
        // palettes must be ignored, not answered with an empty color.
        if (@as(usize, idx) >= colors.palette.len + colors.special_palette.len) continue;
        if (std.mem.eql(u8, value, "?")) {
            // zig-audit: acknowledge catch_unreachable
            // reason: The destination and encoded value are already bounded to fit; failure would contradict the established capacity/value invariant.
            const text = std.fmt.bufPrint(encode_buf, "4;{d};", .{idx}) catch unreachable;
            const start = byteCount(output.bytes());
            errdefer output.truncate(start);
            try output.appendControl(.terminal, .osc);
            try output.append(text);
            if (paletteTargetColor(colors, idx)) |color| try appendColorOsc(allocator, output, color);
            try appendColorReplyTerminator(output, reply_bel);
        } else if (parseColor(value)) |color| {
            setPaletteTarget(colors, idx, color);
        }
    }
}

// Applies or answers one OSC 5 special-palette request transactionally.
fn handleXtermSpecialPaletteControl(
    allocator: std.mem.Allocator,
    colors: *TerminalColorState,
    output: *replies.Buffer,
    encode_buf: []u8,
    payload: []const u8,
    reply_bel: bool,
) replies.AppendError!void {
    var parts = std.mem.splitScalar(u8, payload, ';');
    while (parts.next()) |idx_text| {
        const value = parts.next() orelse break;
        const idx = std.fmt.parseUnsigned(u3, idx_text, 10) catch continue;
        // zig-audit: acknowledge catch_unreachable
        // reason: The destination and encoded value are already bounded to fit; failure would contradict the established capacity/value invariant.
        const text = std.fmt.bufPrint(encode_buf, "5;{d};", .{idx}) catch unreachable;
        if (std.mem.eql(u8, value, "?")) {
            const start = byteCount(output.bytes());
            errdefer output.truncate(start);
            try output.appendControl(.terminal, .osc);
            try output.append(text);
            if (colors.special_palette[idx]) |color| try appendColorOsc(allocator, output, color);
            try appendColorReplyTerminator(output, reply_bel);
        } else if (parseColor(value)) |color| {
            colors.special_palette[idx] = color;
        }
    }
}

// Applies or answers one dynamic-color command transactionally.
fn handleXtermDynamicColor(
    allocator: std.mem.Allocator,
    colors: *TerminalColorState,
    output: *replies.Buffer,
    encode_buf: []u8,
    command: u16,
    payload: []const u8,
    reply_bel: bool,
) replies.AppendError!void {
    var key = dynamicKeyForCommand(command) orelse return;
    var parts = std.mem.splitScalar(u8, payload, ';');
    while (parts.next()) |value| {
        if (std.mem.eql(u8, value, "?")) {
            try appendXtermDynamicColorReply(allocator, output, encode_buf, colors, key, reply_bel);
        } else if (parseColor(value)) |color| {
            setDynamicColor(colors, key, color);
        }
        key = nextDynamicKey(key) orelse return;
    }
}

// OSC 104 resets only canonical palette entries. Return actual mutation
// without a redundant complete ColorState copy or any reply transaction.
fn resetXtermPalette(colors: *TerminalColorState, payload: []const u8, defaults: *const TerminalColorState) bool {
    var changed = false;
    if (payload.len == 0) {
        for (0..colors.palette.len) |index| {
            if (!std.meta.eql(colors.palette[index], defaults.palette[index])) {
                colors.palette[index] = defaults.palette[index];
                changed = true;
            }
        }
        return changed;
    }
    var parts = std.mem.splitScalar(u8, payload, ';');
    while (parts.next()) |idx_text| {
        // The originating xterm OSC104, Kitty, and iTerm2 disagree on
        // whitespace-only and numeric-prefix-junk spellings. The index
        // adjudicates the conflicting exact bytes; do not parse prefixes.
        const trimmed = std.mem.trim(u8, idx_text, " \t\r\n");
        const index = std.fmt.parseInt(i64, trimmed, 10) catch continue;
        if (index < 0 or index > 255) continue;
        const slot: usize = @intCast(index);
        if (!std.meta.eql(colors.palette[slot], defaults.palette[slot])) {
            colors.palette[slot] = defaults.palette[slot];
            changed = true;
        }
    }
    return changed;
}

// Resets one dynamic color selected by its OSC command.
fn resetXtermDynamicColor(colors: *TerminalColorState, command: u16, payload: []const u8, defaults: *const TerminalColorState) void {
    if (payload.len != 0) return;
    const key = dynamicKeyForResetCommand(command) orelse return;
    resetDynamicColor(colors, key, defaults);
}

fn parseColor(value: []const u8) ?Rgb {
    const color_text = stripAlpha(std.mem.trim(u8, value, " \t\r\n"));
    if (color_text.len == 0) return null;
    if (std.mem.startsWith(u8, color_text, "#")) return parseHashColor(color_text[1..]);
    if (std.mem.startsWith(u8, color_text, "rgb:")) return parseRgbColor(color_text[4..]);
    if (std.ascii.eqlIgnoreCase(color_text, "black")) return .{ .r = 0, .g = 0, .b = 0 };
    if (std.ascii.eqlIgnoreCase(color_text, "red")) return .{ .r = 255, .g = 0, .b = 0 };
    if (std.ascii.eqlIgnoreCase(color_text, "green")) return .{ .r = 0, .g = 255, .b = 0 };
    if (std.ascii.eqlIgnoreCase(color_text, "blue")) return .{ .r = 0, .g = 0, .b = 255 };
    if (std.ascii.eqlIgnoreCase(color_text, "white")) return .{ .r = 255, .g = 255, .b = 255 };
    return null;
}

// Applies the iTerm SetColors subset represented by terminal presentation state.
//
// Bare and `srgb:` three- or six-digit values are accepted. Display-P3 and
// caller-only selection, tab, badge, link, match, preset, and face-policy keys
// are intentionally left to an embedder with those domains. Matching iTerm's
// command loop, each valid pair commits independently while malformed or
// unsupported pairs are ignored without affecting their valid neighbors;
// `default` restores the corresponding configured terminal default.
fn handleItermSetColors(colors: *TerminalColorState, defaults: *const TerminalColorState, payload: []const u8) void {
    var parts = std.mem.splitScalar(u8, payload, ',');
    while (parts.next()) |part| {
        const separator = std.mem.indexOfScalar(u8, part, '=') orelse continue;
        if (separator == 0 or separator + 1 == part.len) continue;
        const name = part[0..separator];
        const target = parseItermColorTarget(name) orelse continue;
        var value = part[separator + 1 ..];
        if (std.mem.eql(u8, value, "default")) {
            resetItermColor(colors, defaults.*, target);
            continue;
        }
        if (std.mem.startsWith(u8, value, "srgb:")) value = value[5..];
        if (std.mem.indexOfScalar(u8, value, ':') != null) continue;
        const rgb = parseItermHex(value) orelse continue;
        setItermColor(colors, target, rgb);
    }
}

const ItermColorTarget = union(enum) {
    foreground,
    background,
    cursor,
    cursor_text,
    palette: u8,
};

fn parseItermColorTarget(name: []const u8) ?ItermColorTarget {
    if (std.mem.eql(u8, name, "fg")) return .foreground;
    if (std.mem.eql(u8, name, "bg")) return .background;
    if (std.mem.eql(u8, name, "curbg")) return .cursor;
    if (std.mem.eql(u8, name, "curfg")) return .cursor_text;
    if (parseItermPaletteIndex(name)) |index| return .{ .palette = index };
    return null;
}

fn setItermColor(colors: *TerminalColorState, target: ItermColorTarget, rgb: Rgb) void {
    switch (target) {
        .foreground => colors.foreground = rgb,
        .background => colors.background = rgb,
        .cursor => colors.cursor = rgb,
        .cursor_text => colors.cursor_text = rgb,
        .palette => |index| colors.palette[index] = rgb,
    }
}

fn resetItermColor(
    colors: *TerminalColorState,
    defaults: TerminalColorState,
    target: ItermColorTarget,
) void {
    switch (target) {
        .foreground => colors.foreground = defaults.foreground,
        .background => colors.background = defaults.background,
        .cursor => colors.cursor = defaults.cursor,
        .cursor_text => colors.cursor_text = defaults.cursor_text,
        .palette => |index| colors.palette[index] = defaults.palette[index],
    }
}

fn parseItermHex(value: []const u8) ?Rgb {
    if (value.len != 3 and value.len != 6) return null;
    var expanded: [6]u8 = undefined;
    const hex = if (value.len == 3) blk: {
        for (value, 0..) |digit, index| {
            expanded[index * 2] = digit;
            expanded[index * 2 + 1] = digit;
        }
        break :blk expanded[0..];
    } else value;
    const rgb_value = std.fmt.parseUnsigned(u24, hex, 16) catch return null;
    return .{
        .r = @intCast(rgb_value >> 16),
        .g = @intCast((rgb_value >> 8) & 0xff),
        .b = @intCast(rgb_value & 0xff),
    };
}

fn parseItermPaletteIndex(name: []const u8) ?u8 {
    const names = [_][]const u8{
        "black",    "red",    "green",    "yellow",    "blue",    "magenta",    "cyan",    "white",
        "br_black", "br_red", "br_green", "br_yellow", "br_blue", "br_magenta", "br_cyan", "br_white",
    };
    for (names, 0..) |candidate, index|
        if (std.mem.eql(u8, name, candidate)) return @intCast(index);
    return null;
}

fn specialColorKey(key: []const u8) ?SpecialKey {
    if (std.mem.eql(u8, key, "foreground")) return .foreground;
    if (std.mem.eql(u8, key, "background")) return .background;
    if (std.mem.eql(u8, key, "cursor")) return .cursor;
    if (std.mem.eql(u8, key, "cursor_text")) return .cursor_text;
    if (std.mem.eql(u8, key, "selection_background")) return .selection_background;
    if (std.mem.eql(u8, key, "selection_foreground")) return .selection_foreground;
    return null;
}

// Reports whether a borrowed Kitty color key names supported state.
fn isKnownColorKey(key: []const u8) bool {
    if (specialColorKey(key) != null) return true;
    return (std.fmt.parseUnsigned(u8, key, 10) catch null) != null;
}

// Returns the current color for a recognized Kitty key.
fn colorForKey(colors: *const TerminalColorState, key: []const u8) ?Rgb {
    if (std.fmt.parseUnsigned(u8, key, 10)) |idx| return colors.palette[idx] else |_| {}
    if (specialColorKey(key)) |special| return switch (special) {
        .foreground => colors.foreground,
        .background => colors.background,
        .cursor => colors.cursor,
        .cursor_text => colors.cursor_text,
        .selection_background => colors.selection_background,
        .selection_foreground => colors.selection_foreground,
    };
    return null;
}

fn paletteTargetColor(colors: *const TerminalColorState, idx: u16) ?Rgb {
    if (idx < 256) return colors.palette[@intCast(idx)];
    const special_idx = idx - 256;
    if (special_idx >= colors.special_palette.len) return null;
    return colors.special_palette[special_idx];
}

fn setPaletteTarget(colors: *TerminalColorState, idx: u16, color: Rgb) void {
    if (idx < 256) {
        colors.palette[@intCast(idx)] = color;
        return;
    }
    const special_idx = idx - 256;
    if (special_idx >= colors.special_palette.len) return;
    colors.special_palette[special_idx] = color;
}

fn resetPaletteTarget(colors: *TerminalColorState, idx: u8, defaults: *const TerminalColorState) void {
    colors.palette[idx] = defaults.palette[idx];
}

fn dynamicKeyForCommand(command: u16) ?DynamicKey {
    return switch (command) {
        10 => .foreground,
        11 => .background,
        12 => .cursor,
        13 => .pointer_foreground,
        14 => .pointer_background,
        15 => .tektronix_foreground,
        16 => .tektronix_background,
        17 => .selection_background,
        18 => .tektronix_cursor,
        19 => .selection_foreground,
        else => null,
    };
}

fn dynamicKeyForResetCommand(command: u16) ?DynamicKey {
    return switch (command) {
        110 => .foreground,
        111 => .background,
        112 => .cursor,
        113 => .pointer_foreground,
        114 => .pointer_background,
        115 => .tektronix_foreground,
        116 => .tektronix_background,
        117 => .selection_background,
        118 => .tektronix_cursor,
        119 => .selection_foreground,
        else => null,
    };
}

fn nextDynamicKey(key: DynamicKey) ?DynamicKey {
    return switch (key) {
        .foreground => .background,
        .background => .cursor,
        .cursor => .pointer_foreground,
        .pointer_foreground => .pointer_background,
        .pointer_background => .tektronix_foreground,
        .tektronix_foreground => .tektronix_background,
        .tektronix_background => .selection_background,
        .selection_background => .tektronix_cursor,
        .tektronix_cursor => .selection_foreground,
        .selection_foreground => null,
    };
}

fn dynamicCommandForKey(key: DynamicKey) u16 {
    return switch (key) {
        .foreground => 10,
        .background => 11,
        .cursor => 12,
        .pointer_foreground => 13,
        .pointer_background => 14,
        .tektronix_foreground => 15,
        .tektronix_background => 16,
        .selection_background => 17,
        .tektronix_cursor => 18,
        .selection_foreground => 19,
    };
}

fn dynamicColor(colors: *const TerminalColorState, key: DynamicKey) ?Rgb {
    return switch (key) {
        .foreground => colors.foreground,
        .background => colors.background,
        .cursor => colors.cursor,
        .pointer_foreground => colors.pointer_foreground,
        .pointer_background => colors.pointer_background,
        .tektronix_foreground => colors.tektronix_foreground,
        .tektronix_background => colors.tektronix_background,
        .selection_background => colors.selection_background,
        .tektronix_cursor => colors.tektronix_cursor,
        .selection_foreground => colors.selection_foreground,
    };
}

fn setDynamicColor(colors: *TerminalColorState, key: DynamicKey, color: Rgb) void {
    switch (key) {
        .foreground => colors.foreground = color,
        .background => colors.background = color,
        .cursor => colors.cursor = color,
        .pointer_foreground => colors.pointer_foreground = color,
        .pointer_background => colors.pointer_background = color,
        .tektronix_foreground => colors.tektronix_foreground = color,
        .tektronix_background => colors.tektronix_background = color,
        .selection_background => colors.selection_background = color,
        .tektronix_cursor => colors.tektronix_cursor = color,
        .selection_foreground => colors.selection_foreground = color,
    }
}

fn resetDynamicColor(colors: *TerminalColorState, key: DynamicKey, defaults: *const TerminalColorState) void {
    switch (key) {
        .foreground => colors.foreground = defaults.foreground,
        .background => colors.background = defaults.background,
        .cursor => colors.cursor = defaults.cursor,
        .pointer_foreground => colors.pointer_foreground = defaults.pointer_foreground,
        .pointer_background => colors.pointer_background = defaults.pointer_background,
        .tektronix_foreground => colors.tektronix_foreground = defaults.tektronix_foreground,
        .tektronix_background => colors.tektronix_background = defaults.tektronix_background,
        .selection_background => colors.selection_background = defaults.selection_background,
        .tektronix_cursor => colors.tektronix_cursor = defaults.tektronix_cursor,
        .selection_foreground => colors.selection_foreground = defaults.selection_foreground,
    }
}

// xterm's OSC color query replies preserve the requesting BEL or ST final.
// Framing policy stays with the reply owner; the parser only records the byte.
fn appendColorReplyTerminator(output: *replies.Buffer, reply_bel: bool) replies.AppendError!void {
    if (reply_bel) {
        try output.append("\x07");
    } else {
        try output.appendControl(.terminal, .st);
    }
}

// Appends one bounded rgb:RRRR/GGGG/BBBB OSC color reply.
fn appendColorOsc(_: std.mem.Allocator, output: *replies.Buffer, color: Rgb) replies.AppendError!void {
    var buf: [32]u8 = undefined;
    const text = formatColorOsc(buf[0..], color);
    try output.append(text);
}

// Parses and applies a recognized Kitty color key, ignoring invalid values.
fn setColorKey(colors: *TerminalColorState, key: []const u8, value: []const u8) void {
    if (std.fmt.parseUnsigned(u8, key, 10)) |idx| {
        if (parseColor(value)) |color| colors.palette[idx] = color;
        return;
    } else |_| {}
    if (value.len == 0) {
        setSpecialColorDynamic(colors, key);
    } else if (parseColor(value)) |color| {
        if (specialColorKey(key)) |special| setSpecialColor(colors, special, color);
    }
}

// Restores a recognized Kitty color key to its default value.
fn resetColorKey(colors: *TerminalColorState, key: []const u8, defaults: *const TerminalColorState) void {
    if (std.fmt.parseUnsigned(u8, key, 10)) |idx| {
        colors.palette[idx] = defaults.palette[idx];
        return;
    } else |_| {}
    if (specialColorKey(key)) |special| switch (special) {
        .foreground => colors.foreground = defaults.foreground,
        .background => colors.background = defaults.background,
        .cursor => colors.cursor = defaults.cursor,
        .cursor_text => colors.cursor_text = defaults.cursor_text,
        .selection_background => colors.selection_background = defaults.selection_background,
        .selection_foreground => colors.selection_foreground = defaults.selection_foreground,
    };
}

fn appendXtermDynamicColorReply(
    allocator: std.mem.Allocator,
    output: *replies.Buffer,
    encode_buf: []u8,
    colors: *const TerminalColorState,
    key: DynamicKey,
    reply_bel: bool,
) replies.AppendError!void {
    // zig-audit: acknowledge catch_unreachable
    // reason: The destination and encoded value are already bounded to fit; failure would contradict the established capacity/value invariant.
    const text = std.fmt.bufPrint(encode_buf, "{d};", .{dynamicCommandForKey(key)}) catch unreachable;
    const start = byteCount(output.bytes());
    errdefer output.truncate(start);
    try output.appendControl(.terminal, .osc);
    try output.append(text);
    if (dynamicColor(colors, key)) |color| try appendColorOsc(allocator, output, color);
    try appendColorReplyTerminator(output, reply_bel);
}

fn setSpecialColor(colors: *TerminalColorState, key: SpecialKey, color: Rgb) void {
    switch (key) {
        .foreground => colors.foreground = color,
        .background => colors.background = color,
        .cursor => colors.cursor = color,
        .cursor_text => colors.cursor_text = color,
        .selection_background => colors.selection_background = color,
        .selection_foreground => colors.selection_foreground = color,
    }
}

fn setSpecialColorDynamic(colors: *TerminalColorState, key: []const u8) void {
    if (specialColorKey(key)) |special| switch (special) {
        .foreground => {},
        .background => {},
        .cursor => colors.cursor = null,
        .cursor_text => colors.cursor_text = null,
        .selection_background => colors.selection_background = null,
        .selection_foreground => colors.selection_foreground = null,
    };
}

fn formatColorOsc(buf: []u8, color: Rgb) []const u8 {
    std.debug.assert(buf.len >= color_osc_max_bytes);
    return std.fmt.bufPrint(buf, "rgb:{x:0>4}/{x:0>4}/{x:0>4}", .{
        @as(u16, color.r) * 0x101,
        @as(u16, color.g) * 0x101,
        @as(u16, color.b) * 0x101,
        // zig-audit: acknowledge catch_unreachable
        // reason: The operation runs on state or storage already validated/reserved by this owner; failure would contradict the established invariant.
    }) catch unreachable;
}

fn stripAlpha(value: []const u8) []const u8 {
    const at = std.mem.indexOfScalar(u8, value, '@') orelse return value;
    return value[0..at];
}

fn parseHashColor(hex: []const u8) ?Rgb {
    return switch (hex.len) {
        3 => blk: {
            const r = parseHexNibble(hex[0]) orelse return null;
            const g = parseHexNibble(hex[1]) orelse return null;
            const b = parseHexNibble(hex[2]) orelse return null;
            break :blk .{ .r = r * 0x11, .g = g * 0x11, .b = b * 0x11 };
        },
        6 => .{
            .r = parseHexByte(hex[0..2]) orelse return null,
            .g = parseHexByte(hex[2..4]) orelse return null,
            .b = parseHexByte(hex[4..6]) orelse return null,
        },
        9 => .{
            .r = parseHexByte(hex[0..2]) orelse return null,
            .g = parseHexByte(hex[3..5]) orelse return null,
            .b = parseHexByte(hex[6..8]) orelse return null,
        },
        12 => .{
            .r = parseHexByte(hex[0..2]) orelse return null,
            .g = parseHexByte(hex[4..6]) orelse return null,
            .b = parseHexByte(hex[8..10]) orelse return null,
        },
        else => null,
    };
}

fn parseRgbColor(text: []const u8) ?Rgb {
    var parts = std.mem.splitScalar(u8, text, '/');
    const r = parseRgbComponent(parts.next() orelse return null) orelse return null;
    const g = parseRgbComponent(parts.next() orelse return null) orelse return null;
    const b = parseRgbComponent(parts.next() orelse return null) orelse return null;
    if (parts.next() != null) return null;
    return .{ .r = r, .g = g, .b = b };
}

fn parseRgbComponent(text: []const u8) ?u8 {
    if (text.len == 0 or text.len > 4) return null;
    const value = std.fmt.parseUnsigned(u16, text, 16) catch return null;
    return switch (text.len) {
        1 => @intCast(value * 17),
        2 => @intCast(value),
        3 => @intCast(value >> 4),
        4 => @intCast(value >> 8),
        else => null,
    };
}

fn parseHexByte(text: []const u8) ?u8 {
    if (text.len != 2) return null;
    return std.fmt.parseUnsigned(u8, text, 16) catch null;
}

fn parseHexNibble(byte: u8) ?u8 {
    return switch (byte) {
        '0'...'9' => byte - '0',
        'a'...'f' => byte - 'a' + 10,
        'A'...'F' => byte - 'A' + 10,
        else => null,
    };
}

test "color control set query and transaction rollback are exact" {
    var colors: properties.ColorState = .{};
    var output = replies.Buffer.init(std.testing.allocator);
    defer output.deinit();
    var scratch: [64]u8 = undefined;

    try std.testing.expect(try apply(
        std.testing.allocator,
        &colors,
        &.{},
        &output,
        &scratch,
        .{ .osc = .{ .command = 4, .payload = "1;#123;1;?" } },
    ));
    try std.testing.expectEqual(Rgb{ .r = 0x11, .g = 0x22, .b = 0x33 }, colors.palette[1]);
    try std.testing.expectEqualStrings("\x1b]4;1;rgb:1111/2222/3333\x1b\\", output.bytes());

    output.truncate(0);
    const before = colors;
    const filler = try std.testing.allocator.alloc(u8, replies.max_bytes - 1);
    defer std.testing.allocator.free(filler);
    @memset(filler, 'x');
    try output.append(filler);
    try std.testing.expectError(
        error.ReplyLimit,
        apply(
            std.testing.allocator,
            &colors,
            &.{},
            &output,
            &scratch,
            .{ .osc = .{ .command = 4, .payload = "2;#010203;3;?" } },
        ),
    );
    try std.testing.expectEqual(before, colors);
    try std.testing.expectEqual(@as(u32, replies.max_bytes - 1), output.len());
}

test "OSC 104 exact slot reset preserves unrelated palette and queued replies" {
    var colors: properties.ColorState = .{};
    const defaults: properties.ColorState = .{};
    var output = replies.Buffer.init(std.testing.allocator);
    defer output.deinit();
    var scratch: [64]u8 = undefined;
    colors.palette[1] = .{ .r = 1, .g = 2, .b = 3 };
    colors.palette[2] = .{ .r = 4, .g = 5, .b = 6 };
    try output.append("retained reply");

    try std.testing.expect(try apply(
        std.testing.allocator,
        &colors,
        &defaults,
        &output,
        &scratch,
        .{ .osc = .{ .command = 104, .payload = "1" } },
    ));
    try std.testing.expectEqual(defaults.palette[1], colors.palette[1]);
    try std.testing.expectEqual(Rgb{ .r = 4, .g = 5, .b = 6 }, colors.palette[2]);
    try std.testing.expectEqualStrings("retained reply", output.bytes());

    try std.testing.expect(!(try apply(
        std.testing.allocator,
        &colors,
        &defaults,
        &output,
        &scratch,
        .{ .osc = .{ .command = 104, .payload = "1junk" } },
    )));
    try std.testing.expect(try apply(
        std.testing.allocator,
        &colors,
        &defaults,
        &output,
        &scratch,
        .{ .osc = .{ .command = 104, .payload = "" } },
    ));
    try std.testing.expectEqualDeep(defaults.palette, colors.palette);
    try std.testing.expect(!(try apply(
        std.testing.allocator,
        &colors,
        &defaults,
        &output,
        &scratch,
        .{ .osc = .{ .command = 104, .payload = "" } },
    )));
    try std.testing.expectEqualStrings("retained reply", output.bytes());
}

test "Kitty OSC 21 multi-query reply capacity failure rolls back colors and all replies" {
    var colors: properties.ColorState = .{};
    var output = replies.Buffer.init(std.testing.allocator);
    defer output.deinit();
    var scratch: [64]u8 = undefined;

    const retained = try std.testing.allocator.alloc(u8, replies.max_bytes - 22);
    defer std.testing.allocator.free(retained);
    @memset(retained, 'k');
    try output.append(retained);
    const before = colors;
    try std.testing.expectError(
        error.ReplyLimit,
        apply(
            std.testing.allocator,
            &colors,
            &.{},
            &output,
            &scratch,
            .{ .osc = .{ .command = 21, .payload = "foreground=#123456;foreground=?;background=?;cursor=?" } },
        ),
    );
    try std.testing.expectEqual(before, colors);
    try std.testing.expectEqualSlices(u8, retained, output.bytes());
}

test "iTerm SetColors remains presentation-state only" {
    var colors: properties.ColorState = .{};
    try std.testing.expect(applyItermSetColors(&colors, &.{}, "fg=123,bg=srgb:010203,curbg=default,red=abcdef"));
    try std.testing.expectEqual(Rgb{ .r = 0x11, .g = 0x22, .b = 0x33 }, colors.foreground);
    try std.testing.expectEqual(Rgb{ .r = 1, .g = 2, .b = 3 }, colors.background);
    try std.testing.expectEqual(@as(?Rgb, null), colors.cursor);
    try std.testing.expectEqual(Rgb{ .r = 0xab, .g = 0xcd, .b = 0xef }, colors.palette[1]);
}
