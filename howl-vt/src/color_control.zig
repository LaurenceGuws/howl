//! Terminal color-control protocol grammar and bounded reply application.
//!
//! Persistent color storage/defaults live in `properties.zig`. This owner
//! interprets xterm/Kitty/iTerm color controls, mutates borrowed ColorState,
//! emits exact bounded replies, and projects cursor-color Screen actions.

const std = @import("std");
const properties = @import("properties.zig");
const replies = @import("replies.zig");
const Screen = @import("screen.zig").Screen;

const Rgb = properties.Rgb;
const KittyColorState = properties.ColorState;

/// Borrows one terminal color-control command until synchronous application.
pub const Command = struct {
    command: u16,
    payload: []const u8,
};

fn byteCount(bytes: []const u8) u32 {
    std.debug.assert(bytes.len <= std.math.maxInt(u32));
    return @intCast(bytes.len);
}

/// Applies one xterm/Kitty color command transactionally and reports mutation.
pub fn apply(
    allocator: std.mem.Allocator,
    colors: *properties.ColorState,
    output: *replies.Buffer,
    encode_buf: []u8,
    command: Command,
) replies.AppendError!bool {
    const before = colors.*;
    const output_before = output.len();
    errdefer {
        colors.* = before;
        output.truncate(output_before);
    }
    switch (command.command) {
        21 => try handleKittyControl(allocator, colors, output, command.payload),
        4 => try handleXtermPaletteControl(allocator, colors, output, encode_buf, command.payload),
        5 => try handleXtermSpecialPaletteControl(allocator, colors, output, encode_buf, command.payload),
        10, 11, 12, 13, 14, 15, 16, 17, 18, 19 => try handleXtermDynamicColor(
            allocator,
            colors,
            output,
            encode_buf,
            command.command,
            command.payload,
        ),
        104 => resetXtermPalette(colors, command.payload),
        110, 111, 112, 113, 114, 115, 116, 117, 118, 119 => resetXtermDynamicColor(
            colors,
            command.command,
            command.payload,
        ),
        else => {},
    }
    return !std.meta.eql(before, colors.*) or output_before != output.len();
}

/// Applies the accepted iTerm SetColors subset and reports retained mutation.
pub fn applyItermSetColors(colors: *properties.ColorState, payload: []const u8) bool {
    const before = colors.*;
    handleItermSetColors(colors, payload);
    return !std.meta.eql(before, colors.*);
}

// Applies one Kitty color control or appends its bounded query reply.
fn handleKittyControl(
    allocator: std.mem.Allocator,
    colors: *KittyColorState,
    output: *replies.Buffer,
    payload: []const u8,
) replies.AppendError!void {
    var parts = std.mem.splitScalar(u8, payload, ';');
    while (parts.next()) |raw_part| {
        const part = std.mem.trim(u8, raw_part, " \t\r\n");
        if (part.len == 0) continue;
        const eq = std.mem.indexOfScalar(u8, part, '=');
        if (eq) |pos| {
            const key = std.mem.trim(u8, part[0..pos], " \t");
            const value = std.mem.trim(u8, part[pos + 1 ..], " \t");
            if (std.mem.eql(u8, value, "?")) {
                try appendKittyQueryReply(allocator, output, key, colors.*);
            } else {
                setColorKey(colors, key, value);
            }
        } else {
            resetColorKey(colors, std.mem.trim(u8, part, " \t"));
        }
    }
}
fn appendKittyQueryReply(
    allocator: std.mem.Allocator,
    output: *replies.Buffer,
    key: []const u8,
    colors: KittyColorState,
) replies.AppendError!void {
    const start = byteCount(output.bytes());
    errdefer output.truncate(start);
    try output.appendControl(.kitty, .osc);
    try output.append("21;");
    try output.append(key);
    try output.append("=");
    if (colorForKey(colors, key)) |color| {
        try appendColorOsc(allocator, output, color);
    } else if (isKnownColorKey(key)) {
        // Empty value means dynamic/undefined for Kitty color control.
    } else {
        try output.append("?");
    }
    try output.appendControl(.kitty, .st);
}

const color_osc_max_bytes = 18;

const TerminalColorState = properties.ColorState;
const default_terminal_foreground = properties.default_foreground;
const default_terminal_background = properties.default_background;

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
) replies.AppendError!void {
    var parts = std.mem.splitScalar(u8, payload, ';');
    while (parts.next()) |idx_text| {
        const value = parts.next() orelse break;
        const idx = std.fmt.parseUnsigned(u16, idx_text, 10) catch continue;
        if (std.mem.eql(u8, value, "?")) {
            const text = std.fmt.bufPrint(encode_buf, "4;{d};", .{idx}) catch unreachable;
            const start = byteCount(output.bytes());
            errdefer output.truncate(start);
            try output.appendControl(.terminal, .osc);
            try output.append(text);
            if (paletteTargetColor(colors.*, idx)) |color| try appendColorOsc(allocator, output, color);
            try output.appendControl(.terminal, .st);
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
) replies.AppendError!void {
    var parts = std.mem.splitScalar(u8, payload, ';');
    while (parts.next()) |idx_text| {
        const value = parts.next() orelse break;
        const idx = std.fmt.parseUnsigned(u3, idx_text, 10) catch continue;
        const text = std.fmt.bufPrint(encode_buf, "5;{d};", .{idx}) catch unreachable;
        if (std.mem.eql(u8, value, "?")) {
            const start = byteCount(output.bytes());
            errdefer output.truncate(start);
            try output.appendControl(.terminal, .osc);
            try output.append(text);
            if (colors.special_palette[idx]) |color| try appendColorOsc(allocator, output, color);
            try output.appendControl(.terminal, .st);
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
) replies.AppendError!void {
    var key = dynamicKeyForCommand(command) orelse return;
    var parts = std.mem.splitScalar(u8, payload, ';');
    while (parts.next()) |value| {
        if (std.mem.eql(u8, value, "?")) {
            try appendXtermDynamicColorReply(allocator, output, encode_buf, colors.*, key);
        } else if (parseColor(value)) |color| {
            setDynamicColor(colors, key, color);
        }
        key = nextDynamicKey(key) orelse return;
    }
}

// Resets selected OSC 104 palette entries or the complete palette.
fn resetXtermPalette(colors: *TerminalColorState, payload: []const u8) void {
    if (payload.len == 0) {
        colors.palette = (TerminalColorState{}).palette;
        return;
    }
    var parts = std.mem.splitScalar(u8, payload, ';');
    while (parts.next()) |idx_text| {
        const idx = std.fmt.parseUnsigned(u8, idx_text, 10) catch continue;
        resetPaletteTarget(colors, idx);
    }
}

// Resets one dynamic color selected by its OSC command.
fn resetXtermDynamicColor(colors: *TerminalColorState, command: u16, payload: []const u8) void {
    if (payload.len != 0) return;
    const key = dynamicKeyForResetCommand(command) orelse return;
    resetDynamicColor(colors, key);
}

// Converts a cursor color-control request into a semantic event when applicable.
/// Projects cursor-specific color controls into canonical Screen actions.
pub fn cursorAction(command: Command) ?Screen.Action {
    if (command.command == 12) return cursorColorEventFromDynamicPayload(command.payload, .cursor);
    if (command.command == 112 and command.payload.len == 0) return .{ .cursor_color = null };
    if (command.command == 21) return cursorColorEventFromKittyPayload(command.payload);
    return null;
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
// `default` restores the corresponding native TerminalColorState default.
fn handleItermSetColors(colors: *TerminalColorState, payload: []const u8) void {
    const defaults = TerminalColorState{};
    var parts = std.mem.splitScalar(u8, payload, ',');
    while (parts.next()) |part| {
        const separator = std.mem.indexOfScalar(u8, part, '=') orelse continue;
        if (separator == 0 or separator + 1 == part.len) continue;
        const name = part[0..separator];
        const target = parseItermColorTarget(name) orelse continue;
        var value = part[separator + 1 ..];
        if (std.mem.eql(u8, value, "default")) {
            resetItermColor(colors, defaults, target);
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
fn colorForKey(colors: TerminalColorState, key: []const u8) ?Rgb {
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

fn paletteTargetColor(colors: TerminalColorState, idx: u16) ?Rgb {
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

fn resetPaletteTarget(colors: *TerminalColorState, idx: u8) void {
    colors.palette[idx] = properties.defaultPaletteColor(idx);
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

fn cursorColorEventFromDynamicPayload(payload: []const u8, key: SpecialKey) ?Screen.Action {
    var parts = std.mem.splitScalar(u8, payload, ';');
    const value = parts.next() orelse return null;
    if (std.mem.eql(u8, value, "?")) return null;
    return cursorColorEventForValue(key, value);
}

fn cursorColorEventFromKittyPayload(payload: []const u8) ?Screen.Action {
    const split = std.mem.indexOfScalar(u8, payload, '=') orelse return null;
    const key_text = payload[0..split];
    const value = payload[split + 1 ..];
    const key = specialColorKey(key_text) orelse return null;
    switch (key) {
        .cursor, .cursor_text => return cursorColorEventForValue(key, value),
        .foreground, .background, .selection_background, .selection_foreground => return null,
    }
}

fn cursorColorEventForValue(key: SpecialKey, value: []const u8) ?Screen.Action {
    if (std.mem.eql(u8, value, "?")) return null;
    if (value.len == 0) return switch (key) {
        .cursor => .{ .cursor_color = null },
        .cursor_text => .{ .cursor_text_color = null },
        else => null,
    };
    const rgb = parseColor(value) orelse return null;
    return switch (key) {
        .cursor => .{ .cursor_color = rgb },
        .cursor_text => .{ .cursor_text_color = rgb },
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

fn dynamicColor(colors: TerminalColorState, key: DynamicKey) ?Rgb {
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

fn resetDynamicColor(colors: *TerminalColorState, key: DynamicKey) void {
    switch (key) {
        .foreground => colors.foreground = default_terminal_foreground,
        .background => colors.background = default_terminal_background,
        .cursor => colors.cursor = null,
        .pointer_foreground => colors.pointer_foreground = null,
        .pointer_background => colors.pointer_background = null,
        .tektronix_foreground => colors.tektronix_foreground = null,
        .tektronix_background => colors.tektronix_background = null,
        .selection_background => colors.selection_background = null,
        .tektronix_cursor => colors.tektronix_cursor = null,
        .selection_foreground => colors.selection_foreground = null,
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
fn resetColorKey(colors: *TerminalColorState, key: []const u8) void {
    if (std.fmt.parseUnsigned(u8, key, 10)) |idx| {
        colors.palette[idx] = properties.defaultPaletteColor(idx);
        return;
    } else |_| {}
    if (specialColorKey(key)) |special| switch (special) {
        .foreground => colors.foreground = default_terminal_foreground,
        .background => colors.background = default_terminal_background,
        .cursor => colors.cursor = null,
        .cursor_text => colors.cursor_text = null,
        .selection_background => colors.selection_background = null,
        .selection_foreground => colors.selection_foreground = null,
    };
}

fn appendXtermDynamicColorReply(
    allocator: std.mem.Allocator,
    output: *replies.Buffer,
    encode_buf: []u8,
    colors: TerminalColorState,
    key: DynamicKey,
) replies.AppendError!void {
    const text = std.fmt.bufPrint(encode_buf, "{d};", .{dynamicCommandForKey(key)}) catch unreachable;
    const start = byteCount(output.bytes());
    errdefer output.truncate(start);
    try output.appendControl(.terminal, .osc);
    try output.append(text);
    if (dynamicColor(colors, key)) |color| try appendColorOsc(allocator, output, color);
    try output.appendControl(.terminal, .st);
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
        &output,
        &scratch,
        .{ .command = 4, .payload = "1;#123;1;?" },
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
            &output,
            &scratch,
            .{ .command = 4, .payload = "2;#010203;3;?" },
        ),
    );
    try std.testing.expectEqual(before, colors);
    try std.testing.expectEqual(@as(u32, replies.max_bytes - 1), output.len());
}

test "cursor color action mutates canonical cursor owner" {
    var screen = Screen.init(2, 2);

    const cursor_event = cursorAction(.{ .command = 12, .payload = "#010203" }).?;
    screen.applyScreen(.{ .cursor_color = cursor_event.cursor_color });
    try std.testing.expectEqual(@as(?Rgb, .{ .r = 1, .g = 2, .b = 3 }), screen.cursor.cursor_color);

    const cursor_text_event = cursorAction(.{ .command = 21, .payload = "cursor_text=#040506" }).?;
    screen.applyScreen(.{ .cursor_text_color = cursor_text_event.cursor_text_color });
    try std.testing.expectEqual(@as(?Rgb, .{ .r = 4, .g = 5, .b = 6 }), screen.cursor.cursor_text_color);

    const reset_event = cursorAction(.{ .command = 112, .payload = "" }).?;
    screen.applyScreen(.{ .cursor_color = reset_event.cursor_color });
    try std.testing.expectEqual(@as(?Rgb, null), screen.cursor.cursor_color);
}

test "iTerm SetColors remains presentation-state only" {
    var colors: properties.ColorState = .{};
    try std.testing.expect(applyItermSetColors(&colors, "fg=123,bg=srgb:010203,curbg=default,red=abcdef"));
    try std.testing.expectEqual(Rgb{ .r = 0x11, .g = 0x22, .b = 0x33 }, colors.foreground);
    try std.testing.expectEqual(Rgb{ .r = 1, .g = 2, .b = 3 }, colors.background);
    try std.testing.expectEqual(@as(?Rgb, null), colors.cursor);
    try std.testing.expectEqual(Rgb{ .r = 0xab, .g = 0xcd, .b = 0xef }, colors.palette[1]);
}
