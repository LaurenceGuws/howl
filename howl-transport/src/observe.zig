//! Lossless semantic observation of one existing Howl session.
//!
//! `text_v1` is decoded into ordered JSON records without collapsing the
//! canonical terminal into rendered/plain text. Every transported cell fact,
//! presentation value, grapheme scalar, and hyperlink identity remains visible.

const std = @import("std");
const protocol = @import("howl_session").protocol;
const wire = @import("wire.zig");

pub const Error = wire.Error || std.mem.Allocator.Error || protocol.PayloadError || error{
    UnexpectedFrame,
    SnapshotTooLarge,
    InvalidSnapshot,
    UnsupportedSnapshotFormat,
};

const Rgba = struct { r: u8, g: u8, b: u8, a: u8 };
const SemanticColor = struct { kind: []const u8, value: u32 };
const Style = struct {
    bits: u16,
    bold: bool,
    dim: bool,
    italic: bool,
    blink: bool,
    blink_fast: bool,
    reverse: bool,
    invisible: bool,
    underline: bool,
    strikethrough: bool,
};

const BeginRecord = struct {
    record: []const u8 = "snapshot_begin",
    revision: u64,
    terminal_revision: u64,
    format: []const u8 = "text_v1",
    history_offset: u32,
    history_count: u32,
    history_row_base: u32,
    rows: u16,
    columns: u16,
    cursor_row: u16,
    cursor_column: u16,
    cursor_shape: u8,
    cursor_visible: bool,
    cursor_blink: bool,
    alternate_screen: bool,
    stream_closed: bool,
    child_exited: bool,
    leader_present: bool,
    you_are_leader: bool,
};

const PresentationRecord = struct {
    record: []const u8 = "presentation",
    cursor_age_ns: ?u64,
    presence_bits: u8,
    flags: u8,
    reverse_screen: bool,
    palette: [256]Rgba,
    foreground: Rgba,
    background: Rgba,
    cursor: ?Rgba,
    cursor_text: ?Rgba,
    selection_background: ?Rgba,
    selection_foreground: ?Rgba,
};

const CellRecord = struct {
    scalars: []const u32,
    width: u8,
    height: u8,
    x: u8,
    y: u8,
    subscale_n: u8,
    subscale_d: u8,
    vertical_align: u8,
    horizontal_align: u8,
    semantic_width: bool,
    font: u8,
    baseline: u8,
    underline_style: u8,
    protection: u8,
    style: Style,
    foreground: SemanticColor,
    background: SemanticColor,
    underline_color: SemanticColor,
    link_id: u32,
};

const RowRecord = struct {
    record: []const u8 = "row",
    row: u16,
    wrapped: bool,
    line_geometry: u8,
    columns: u16,
    cells: []const CellRecord,
};

const HyperlinkRecord = struct {
    record: []const u8 = "hyperlink",
    link_id: u32,
    uri_bytes_hex: []const u8,
};

const EndRecord = struct {
    record: []const u8 = "snapshot_end",
    revision: u64,
};

const DecodedRow = struct {
    allocator: std.mem.Allocator,
    value: RowRecord,

    fn deinit(self: *DecodedRow) void {
        for (self.value.cells) |cell| {
            if (cell.scalars.len != 0) self.allocator.free(cell.scalars);
        }
        self.allocator.free(self.value.cells);
        self.* = undefined;
    }
};

pub fn emitSnapshot(
    connection: *wire.Connection,
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    history_offset: u32,
) !void {
    var observe_payload: [protocol.payload_bytes.observe]u8 = undefined;
    protocol.encodeObserve(&observe_payload, .{ .after_revision = 0, .history_offset = history_offset });
    try connection.send(.observe, &observe_payload);
    return receiveAndEmitSnapshot(connection, allocator, writer);
}

pub fn receiveAndEmitSnapshot(
    connection: *wire.Connection,
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
) !void {
    var total_bytes: usize = 0;
    var begin_frame = try connection.receive();
    defer begin_frame.deinit();
    try accountFrame(&total_bytes, begin_frame.payload.len);
    if (begin_frame.kind != .snapshot_begin) return error.UnexpectedFrame;
    const begin = try protocol.decodeSnapshotBegin(begin_frame.payload);
    if (begin.format != .text_v1) return error.UnsupportedSnapshotFormat;
    try emitJson(writer, BeginRecord{
        .revision = begin.revision,
        .terminal_revision = begin.terminal_revision,
        .history_offset = begin.history_offset,
        .history_count = begin.history_count,
        .history_row_base = begin.history_row_base,
        .rows = begin.rows,
        .columns = begin.columns,
        .cursor_row = begin.cursor_row,
        .cursor_column = begin.cursor_column,
        .cursor_shape = begin.cursor_shape,
        .cursor_visible = begin.cursor_visible,
        .cursor_blink = begin.cursor_blink,
        .alternate_screen = begin.alternate_screen,
        .stream_closed = begin.stream_closed,
        .child_exited = begin.child_exited,
        .leader_present = begin.leader_present,
        .you_are_leader = begin.you_are_leader,
    });

    var referenced: [protocol.text_v1.maximum_hyperlinks + 1]bool = @splat(false);
    var resolved: [protocol.text_v1.maximum_hyperlinks + 1]bool = @splat(false);
    var presentation_seen = false;
    var row_count: u16 = 0;
    var phase: enum { presentation, rows, hyperlinks } = .presentation;

    while (true) {
        var frame = try connection.receive();
        defer frame.deinit();
        try accountFrame(&total_bytes, frame.payload.len);
        switch (frame.kind) {
            .snapshot_data => {
                if (frame.payload.len < protocol.text_v1.record_header_bytes) return error.InvalidSnapshot;
                var encoded_header: [protocol.text_v1.record_header_bytes]u8 = undefined;
                @memcpy(&encoded_header, frame.payload[0..protocol.text_v1.record_header_bytes]);
                const header = try protocol.decodeTextRecordHeader(&encoded_header);
                if (header.payload_len != frame.payload.len - protocol.text_v1.record_header_bytes)
                    return error.InvalidSnapshot;
                const payload = frame.payload[protocol.text_v1.record_header_bytes..];
                switch (header.kind) {
                    .presentation => {
                        if (phase != .presentation or presentation_seen) return error.InvalidSnapshot;
                        try emitJson(writer, try decodePresentation(payload));
                        presentation_seen = true;
                        phase = .rows;
                    },
                    .row => {
                        if (phase != .rows or !presentation_seen or row_count >= begin.rows)
                            return error.InvalidSnapshot;
                        var row = try decodeRow(allocator, row_count, begin, payload, &referenced);
                        defer row.deinit();
                        try emitJson(writer, row.value);
                        row_count += 1;
                        if (row_count == begin.rows) phase = .hyperlinks;
                    },
                    .hyperlink => {
                        if (phase != .hyperlinks) return error.InvalidSnapshot;
                        const link = try decodeHyperlink(allocator, payload, &referenced, &resolved);
                        defer allocator.free(link.uri_bytes_hex);
                        try emitJson(writer, link);
                    },
                }
            },
            .snapshot_end => {
                const end = try protocol.decodeSnapshotEnd(frame.payload);
                if (end.revision != begin.revision or !presentation_seen or row_count != begin.rows)
                    return error.InvalidSnapshot;
                for (referenced[1..], resolved[1..]) |needed, seen| {
                    if (needed != seen) return error.InvalidSnapshot;
                }
                try emitJson(writer, EndRecord{ .revision = end.revision });
                return;
            },
            else => return error.UnexpectedFrame,
        }
    }
}

fn accountFrame(total: *usize, payload_len: usize) error{SnapshotTooLarge}!void {
    total.* = std.math.add(usize, total.*, protocol.header_bytes + payload_len) catch
        return error.SnapshotTooLarge;
    if (total.* > protocol.maximum_snapshot_bytes) return error.SnapshotTooLarge;
}

fn emitJson(writer: *std.Io.Writer, value: anytype) !void {
    try std.json.Stringify.value(value, .{}, writer);
    try writer.writeByte('\n');
}

fn decodePresentation(payload: []const u8) Error!PresentationRecord {
    if (payload.len != protocol.text_v1.presentation_bytes) return error.InvalidSnapshot;
    const presence = payload[8];
    const flags = payload[9];
    if (presence & ~protocol.text_v1.presentation_presence.known != 0 or
        flags & ~protocol.text_v1.presentation_flags.known != 0 or
        payload[10] != 0 or payload[11] != 0)
        return error.InvalidSnapshot;

    var palette: [256]Rgba = undefined;
    var offset: usize = 12;
    for (&palette) |*slot| {
        slot.* = rgba(payload[offset..][0..4]);
        offset += 4;
    }
    const foreground = rgba(payload[offset..][0..4]);
    offset += 4;
    const background = rgba(payload[offset..][0..4]);
    offset += 4;
    const cursor_raw = rgba(payload[offset..][0..4]);
    offset += 4;
    const cursor_text_raw = rgba(payload[offset..][0..4]);
    offset += 4;
    const selection_background_raw = rgba(payload[offset..][0..4]);
    offset += 4;
    const selection_foreground_raw = rgba(payload[offset..][0..4]);
    offset += 4;
    if (offset != payload.len) return error.InvalidSnapshot;

    const age = readU64(payload[0..8]);
    return .{
        .cursor_age_ns = if (age == protocol.text_v1.no_cursor_movement_age_ns) null else age,
        .presence_bits = presence,
        .flags = flags,
        .reverse_screen = flags & protocol.text_v1.presentation_flags.reverse_screen != 0,
        .palette = palette,
        .foreground = foreground,
        .background = background,
        .cursor = if (presence & protocol.text_v1.presentation_presence.cursor != 0) cursor_raw else null,
        .cursor_text = if (presence & protocol.text_v1.presentation_presence.cursor_text != 0) cursor_text_raw else null,
        .selection_background = if (presence & protocol.text_v1.presentation_presence.selection_background != 0) selection_background_raw else null,
        .selection_foreground = if (presence & protocol.text_v1.presentation_presence.selection_foreground != 0) selection_foreground_raw else null,
    };
}

fn decodeRow(
    allocator: std.mem.Allocator,
    row_index: u16,
    begin: protocol.SnapshotBegin,
    payload: []const u8,
    referenced: *[protocol.text_v1.maximum_hyperlinks + 1]bool,
) Error!DecodedRow {
    if (payload.len < protocol.text_v1.row_header_bytes or payload[0] > 1 or
        payload[1] > 3 or readU16(payload[2..4]) != begin.columns)
        return error.InvalidSnapshot;
    const cells = try allocator.alloc(CellRecord, begin.columns);
    errdefer allocator.free(cells);
    var initialized: usize = 0;
    errdefer {
        for (cells[0..initialized]) |cell| if (cell.scalars.len != 0) allocator.free(cell.scalars);
    }

    var offset: usize = protocol.text_v1.row_header_bytes;
    var column: u16 = 0;
    while (column < begin.columns) : (column += 1) {
        if (payload.len - offset < protocol.text_v1.cell_header_bytes) return error.InvalidSnapshot;
        const cell = payload[offset..][0..protocol.text_v1.cell_header_bytes];
        const scalar_count = cell[0];
        if (scalar_count > protocol.text_v1.maximum_cell_scalars or
            cell[1] == 0 or cell[2] == 0 or cell[3] >= cell[1] or cell[4] >= cell[2] or
            cell[5] > 15 or cell[6] > 15 or cell[7] > 3 or cell[8] > 3 or
            cell[9] > 1 or cell[10] > 15 or cell[11] > 2 or cell[12] > 4 or cell[13] > 2)
            return error.InvalidSnapshot;
        const style_bits = readU16(cell[14..16]);
        if (style_bits & ~protocol.text_v1.style.known != 0) return error.InvalidSnapshot;
        const foreground = try decodeColor(cell[16..21]);
        const background = try decodeColor(cell[21..26]);
        const underline_color = try decodeColor(cell[26..31]);
        const link_id = readU32(cell[31..35]);
        if (link_id > protocol.text_v1.maximum_hyperlinks) return error.InvalidSnapshot;
        if (link_id != 0) referenced[link_id] = true;

        offset += protocol.text_v1.cell_header_bytes;
        const scalar_bytes = @as(usize, scalar_count) * 4;
        if (payload.len - offset < scalar_bytes) return error.InvalidSnapshot;
        if ((cell[3] != 0 or cell[4] != 0) and scalar_count != 0) return error.InvalidSnapshot;
        const scalars = if (scalar_count == 0)
            &.{}
        else blk: {
            const values = try allocator.alloc(u32, scalar_count);
            errdefer allocator.free(values);
            for (values, 0..) |*value, index| {
                value.* = readU32(payload[offset + index * 4 ..][0..4]);
                if (value.* > 0x10ffff or value.* >= 0xd800 and value.* <= 0xdfff)
                    return error.InvalidSnapshot;
            }
            break :blk values;
        };
        cells[column] = .{
            .scalars = scalars,
            .width = cell[1],
            .height = cell[2],
            .x = cell[3],
            .y = cell[4],
            .subscale_n = cell[5],
            .subscale_d = cell[6],
            .vertical_align = cell[7],
            .horizontal_align = cell[8],
            .semantic_width = cell[9] == 1,
            .font = cell[10],
            .baseline = cell[11],
            .underline_style = cell[12],
            .protection = cell[13],
            .style = style(style_bits),
            .foreground = foreground,
            .background = background,
            .underline_color = underline_color,
            .link_id = link_id,
        };
        initialized += 1;
        offset += scalar_bytes;
    }
    if (offset != payload.len) return error.InvalidSnapshot;
    return .{
        .allocator = allocator,
        .value = .{
            .row = row_index,
            .wrapped = payload[0] == 1,
            .line_geometry = payload[1],
            .columns = begin.columns,
            .cells = cells,
        },
    };
}

fn decodeHyperlink(
    allocator: std.mem.Allocator,
    payload: []const u8,
    referenced: *[protocol.text_v1.maximum_hyperlinks + 1]bool,
    resolved: *[protocol.text_v1.maximum_hyperlinks + 1]bool,
) Error!HyperlinkRecord {
    if (payload.len < protocol.text_v1.hyperlink_header_bytes) return error.InvalidSnapshot;
    const link_id = readU32(payload[0..4]);
    const uri_len = readU16(payload[4..6]);
    if (link_id == 0 or link_id > protocol.text_v1.maximum_hyperlinks or
        uri_len == 0 or uri_len > protocol.text_v1.maximum_hyperlink_uri_bytes or
        payload.len != protocol.text_v1.hyperlink_header_bytes + uri_len or
        !referenced[link_id] or resolved[link_id])
        return error.InvalidSnapshot;
    resolved[link_id] = true;
    return .{
        .link_id = link_id,
        .uri_bytes_hex = try hexBytes(allocator, payload[protocol.text_v1.hyperlink_header_bytes..]),
    };
}

fn decodeColor(bytes: []const u8) Error!SemanticColor {
    if (bytes.len != protocol.text_v1.color_bytes) return error.InvalidSnapshot;
    var encoded: [protocol.text_v1.color_bytes]u8 = undefined;
    @memcpy(&encoded, bytes);
    const color = try protocol.decodeTextColor(&encoded);
    return .{ .kind = @tagName(color.kind), .value = color.value };
}

fn style(bits: u16) Style {
    return .{
        .bits = bits,
        .bold = bits & protocol.text_v1.style.bold != 0,
        .dim = bits & protocol.text_v1.style.dim != 0,
        .italic = bits & protocol.text_v1.style.italic != 0,
        .blink = bits & protocol.text_v1.style.blink != 0,
        .blink_fast = bits & protocol.text_v1.style.blink_fast != 0,
        .reverse = bits & protocol.text_v1.style.reverse != 0,
        .invisible = bits & protocol.text_v1.style.invisible != 0,
        .underline = bits & protocol.text_v1.style.underline != 0,
        .strikethrough = bits & protocol.text_v1.style.strikethrough != 0,
    };
}

fn rgba(bytes: []const u8) Rgba {
    std.debug.assert(bytes.len == 4);
    return .{ .r = bytes[0], .g = bytes[1], .b = bytes[2], .a = bytes[3] };
}

fn hexBytes(allocator: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error![]u8 {
    const output = try allocator.alloc(u8, bytes.len * 2);
    const alphabet = "0123456789abcdef";
    for (bytes, 0..) |byte, index| {
        output[index * 2] = alphabet[byte >> 4];
        output[index * 2 + 1] = alphabet[byte & 0x0f];
    }
    return output;
}

fn readU16(bytes: []const u8) u16 {
    std.debug.assert(bytes.len >= 2);
    return (@as(u16, bytes[0]) << 8) | bytes[1];
}

fn readU32(bytes: []const u8) u32 {
    std.debug.assert(bytes.len >= 4);
    return (@as(u32, bytes[0]) << 24) |
        (@as(u32, bytes[1]) << 16) |
        (@as(u32, bytes[2]) << 8) |
        bytes[3];
}

fn readU64(bytes: []const u8) u64 {
    std.debug.assert(bytes.len >= 8);
    var value: u64 = 0;
    for (bytes[0..8]) |byte| value = (value << 8) | byte;
    return value;
}

fn encodeU16(bytes: []u8, value: u16) void {
    bytes[0] = @truncate(value >> 8);
    bytes[1] = @truncate(value);
}

fn encodeU32(bytes: []u8, value: u32) void {
    bytes[0] = @truncate(value >> 24);
    bytes[1] = @truncate(value >> 16);
    bytes[2] = @truncate(value >> 8);
    bytes[3] = @truncate(value);
}

test "rich row decoder preserves styled grapheme state instead of flattening text" {
    const begin = protocol.SnapshotBegin{
        .revision = 3,
        .terminal_revision = 9,
        .format = .text_v1,
        .history_offset = 0,
        .history_count = 0,
        .history_row_base = 0,
        .rows = 1,
        .columns = 1,
        .cursor_row = 0,
        .cursor_column = 0,
        .cursor_shape = 0,
        .cursor_visible = true,
        .cursor_blink = true,
        .alternate_screen = false,
        .stream_closed = false,
        .child_exited = false,
        .leader_present = false,
        .you_are_leader = false,
    };
    var payload: [protocol.text_v1.row_header_bytes + protocol.text_v1.cell_header_bytes + 8]u8 = @splat(0);
    payload[0] = 1;
    payload[1] = 2;
    encodeU16(payload[2..4], 1);
    const cell = payload[4 .. 4 + protocol.text_v1.cell_header_bytes];
    cell[0] = 2;
    cell[1] = 1;
    cell[2] = 1;
    cell[5] = 1;
    cell[6] = 2;
    cell[7] = 1;
    cell[8] = 2;
    cell[9] = 1;
    cell[10] = 3;
    cell[11] = 1;
    cell[12] = 2;
    cell[13] = 1;
    encodeU16(cell[14..16], protocol.text_v1.style.bold | protocol.text_v1.style.italic | protocol.text_v1.style.underline);
    var color: [protocol.text_v1.color_bytes]u8 = undefined;
    try protocol.encodeTextColor(&color, .{ .kind = .rgb, .value = 0x112233 });
    @memcpy(cell[16..21], &color);
    try protocol.encodeTextColor(&color, .{ .kind = .indexed, .value = 4 });
    @memcpy(cell[21..26], &color);
    try protocol.encodeTextColor(&color, .{ .kind = .rgb, .value = 0x445566 });
    @memcpy(cell[26..31], &color);
    encodeU32(cell[31..35], 7);
    encodeU32(payload[payload.len - 8 .. payload.len - 4], 'e');
    encodeU32(payload[payload.len - 4 ..], 0x0301);

    var referenced: [protocol.text_v1.maximum_hyperlinks + 1]bool = @splat(false);
    var row = try decodeRow(std.testing.allocator, 0, begin, &payload, &referenced);
    defer row.deinit();
    const decoded = row.value.cells[0];
    try std.testing.expect(row.value.wrapped);
    try std.testing.expectEqual(@as(u8, 2), row.value.line_geometry);
    try std.testing.expectEqualSlices(u32, &.{ 'e', 0x0301 }, decoded.scalars);
    try std.testing.expect(decoded.style.bold and decoded.style.italic and decoded.style.underline);
    try std.testing.expectEqualStrings("rgb", decoded.foreground.kind);
    try std.testing.expectEqual(@as(u32, 0x112233), decoded.foreground.value);
    try std.testing.expectEqualStrings("indexed", decoded.background.kind);
    try std.testing.expectEqual(@as(u32, 4), decoded.background.value);
    try std.testing.expectEqual(@as(u32, 7), decoded.link_id);
    try std.testing.expect(referenced[7]);
}

test "hyperlink transport preserves arbitrary URI bytes exactly" {
    var payload: [protocol.text_v1.hyperlink_header_bytes + 4]u8 = undefined;
    encodeU32(payload[0..4], 2);
    encodeU16(payload[4..6], 4);
    payload[6] = 'A';
    payload[7] = 0;
    payload[8] = 0xff;
    payload[9] = 'Z';
    var referenced: [protocol.text_v1.maximum_hyperlinks + 1]bool = @splat(false);
    var resolved: [protocol.text_v1.maximum_hyperlinks + 1]bool = @splat(false);
    referenced[2] = true;
    const link = try decodeHyperlink(std.testing.allocator, &payload, &referenced, &resolved);
    defer std.testing.allocator.free(link.uri_bytes_hex);
    try std.testing.expectEqualStrings("4100ff5a", link.uri_bytes_hex);
    try std.testing.expect(resolved[2]);
}
