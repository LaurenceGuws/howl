//! Stateless terminal identity, status, geometry, and checksum reply encoding.
//!
//! Callers project live state into small values and retain all state ownership.

const std = @import("std");
const replies = @import("replies.zig");

/// Howl's VT220-class DEC conformance identity for DA1 and DECSCL.
pub const dec_conformance_level: u8 = 62;

/// Carries the geometry and origin facts needed by cursor and extent reports.
pub const CursorView = struct {
    rows: u16,
    cols: u16,
    cursor_row: u16,
    cursor_col: u16,
    origin_mode: bool = false,
    origin_top: u16 = 0,
    origin_left: u16 = 0,
};

/// Appends the standard ready device-status reply.
pub fn appendDeviceStatus(output: *replies.Buffer) replies.AppendError!void {
    try output.appendCsi(.terminal, "0n");
}

/// Appends Howl's VT220-class primary device attributes.
pub fn appendPrimaryDeviceAttributes(
    output: *replies.Buffer,
    encode_buffer: []u8,
) replies.AppendError!void {
    const payload = std.fmt.bufPrint(
        encode_buffer,
        "?{d};22c",
        .{dec_conformance_level},
    ) catch unreachable;
    try output.appendCsi(.terminal, payload);
}

/// Appends Howl's fixed secondary device attributes.
pub fn appendSecondaryDeviceAttributes(output: *replies.Buffer) replies.AppendError!void {
    try output.appendCsi(.terminal, ">1;10;0c");
}

/// Appends Howl's fixed tertiary unit identity.
pub fn appendTertiaryDeviceAttributes(output: *replies.Buffer) replies.AppendError!void {
    try output.appendString(.terminal, .dcs, "!|00000000");
}

/// Appends one XTerm title-stack position report.
pub fn appendTitleStackPosition(
    output: *replies.Buffer,
    encode_buffer: []u8,
    current: u16,
    maximum: u16,
) replies.AppendError!void {
    const payload = std.fmt.bufPrint(
        encode_buffer,
        "{d};{d}#S",
        .{ current, maximum },
    ) catch unreachable;
    try output.appendCsi(.terminal, payload);
}

/// Appends one ANSI cursor-position report.
pub fn appendCursorPosition(
    output: *replies.Buffer,
    encode_buffer: []u8,
    view: CursorView,
) replies.AppendError!void {
    try appendCursor(output, encode_buffer, view, false);
}

/// Appends one DEC extended cursor-position report.
pub fn appendDecCursorPosition(
    output: *replies.Buffer,
    encode_buffer: []u8,
    view: CursorView,
) replies.AppendError!void {
    try appendCursor(output, encode_buffer, view, true);
}

/// Appends one DECRQDE rectangular screen-extent report.
pub fn appendScreenExtent(
    output: *replies.Buffer,
    encode_buffer: []u8,
    view: CursorView,
) replies.AppendError!void {
    const payload = std.fmt.bufPrint(
        encode_buffer,
        "{d};{d};1;1;1\"w",
        .{ view.rows, view.cols },
    ) catch unreachable;
    try output.appendCsi(.terminal, payload);
}

/// Appends one DECREPTPARM reply for request kind zero or one.
pub fn appendTerminalParameters(
    output: *replies.Buffer,
    encode_buffer: []u8,
    kind: u16,
) replies.AppendError!void {
    if (kind > 1) return;
    const payload = std.fmt.bufPrint(
        encode_buffer,
        "{d};1;1;128;128;1;0x",
        .{kind + 2},
    ) catch unreachable;
    try output.appendCsi(.terminal, payload);
}

/// Appends one DECCKSR checksum reply from caller-computed state.
pub fn appendRectChecksum(
    output: *replies.Buffer,
    encode_buffer: []u8,
    request_id: u16,
    checksum: u16,
) replies.AppendError!void {
    const payload = std.fmt.bufPrint(
        encode_buffer,
        "{d}!~{X:0>4}",
        .{ request_id, checksum },
    ) catch unreachable;
    try output.appendString(.terminal, .dcs, payload);
}

fn appendCursor(
    output: *replies.Buffer,
    encode_buffer: []u8,
    view: CursorView,
    private: bool,
) replies.AppendError!void {
    const row = cursorCoordinate(view.cursor_row, view.origin_top, view.origin_mode);
    const column = cursorCoordinate(view.cursor_col, view.origin_left, view.origin_mode);
    const payload = if (private)
        std.fmt.bufPrint(encode_buffer, "?{d};{d}R", .{ row, column }) catch unreachable
    else
        std.fmt.bufPrint(encode_buffer, "{d};{d}R", .{ row, column }) catch unreachable;
    try output.appendCsi(.terminal, payload);
}

// A restored cursor may precede current margins. Relative reports clamp that
// valid cross-savepoint state to the first addressable origin coordinate.
fn cursorCoordinate(position: u16, origin: u16, relative: bool) u32 {
    const zero_based: u32 = if (relative) position -| origin else position;
    return zero_based + 1;
}

test "fixed identity and status replies preserve exact framing" {
    var output = replies.Buffer.init(std.testing.allocator);
    defer output.deinit();
    var scratch: [64]u8 = undefined;

    try appendDeviceStatus(&output);
    try appendPrimaryDeviceAttributes(&output, &scratch);
    try appendSecondaryDeviceAttributes(&output);
    try appendTertiaryDeviceAttributes(&output);
    try std.testing.expectEqualStrings(
        "\x1b[0n\x1b[?62;22c\x1b[>1;10;0c\x1bP!|00000000\x1b\\",
        output.bytes(),
    );

    output.truncate(0);
    try std.testing.expect(output.setEightBitControls(true));
    try appendDeviceStatus(&output);
    try appendTertiaryDeviceAttributes(&output);
    try std.testing.expectEqualStrings("\x9b0n\x90!|00000000\x9c", output.bytes());
}

test "cursor reports clamp restored origins and preserve full u16 extent" {
    var output = replies.Buffer.init(std.testing.allocator);
    defer output.deinit();
    var scratch: [64]u8 = undefined;

    try appendCursorPosition(&output, &scratch, .{
        .rows = 24,
        .cols = 80,
        .cursor_row = 2,
        .cursor_col = 4,
    });
    try appendDecCursorPosition(&output, &scratch, .{
        .rows = 24,
        .cols = 80,
        .cursor_row = 2,
        .cursor_col = std.math.maxInt(u16),
        .origin_mode = true,
        .origin_top = 6,
    });
    try std.testing.expectEqualStrings("\x1b[3;5R\x1b[?1;65536R", output.bytes());
}

test "extent parameters title stack and checksum serialize exact payloads" {
    var output = replies.Buffer.init(std.testing.allocator);
    defer output.deinit();
    var scratch: [64]u8 = undefined;

    try appendScreenExtent(&output, &scratch, .{
        .rows = 24,
        .cols = 80,
        .cursor_row = 0,
        .cursor_col = 0,
    });
    try appendTerminalParameters(&output, &scratch, 0);
    try appendTerminalParameters(&output, &scratch, 1);
    try appendTerminalParameters(&output, &scratch, 2);
    try appendTitleStackPosition(&output, &scratch, 3, 7);
    try appendRectChecksum(&output, &scratch, 19, 0x00af);
    try std.testing.expectEqualStrings(
        "\x1b[24;80;1;1;1\"w\x1b[2;1;1;128;128;1;0x" ++
            "\x1b[3;1;1;128;128;1;0x\x1b[3;7#S\x1bP19!~00AF\x1b\\",
        output.bytes(),
    );
}

test "fixed report reply saturation preserves prior output" {
    var output = replies.Buffer.init(std.testing.allocator);
    defer output.deinit();
    const retained = try std.testing.allocator.alloc(u8, replies.max_bytes);
    defer std.testing.allocator.free(retained);
    @memset(retained, 'k');
    try output.append(retained);
    var scratch: [64]u8 = undefined;

    try std.testing.expectError(
        error.ReplyLimit,
        appendPrimaryDeviceAttributes(&output, &scratch),
    );
    try std.testing.expectEqualSlices(u8, retained, output.bytes());
}
