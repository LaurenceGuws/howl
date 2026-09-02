//! Lossless native `text_v1` snapshot model for Howl clients.
//!
//! This decoder preserves every transported terminal fact without choosing a
//! renderer, CLI schema, JSON representation, font, or platform presentation.

const std = @import("std");
const protocol = @import("howl_session").protocol;
const client = @import("client.zig");

pub const Error = client.Error || std.mem.Allocator.Error || protocol.PayloadError || error{
    UnexpectedFrame,
    SnapshotTooLarge,
    InvalidSnapshot,
};

pub const Rgba = struct { r: u8, g: u8, b: u8, a: u8 };

pub const Presentation = struct {
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

pub const Cell = struct {
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
    style_bits: u16,
    foreground: protocol.TextColor,
    background: protocol.TextColor,
    underline_color: protocol.TextColor,
    link_id: u32,
};

pub const Row = struct {
    wrapped: bool,
    line_geometry: u8,
    cells: []Cell,
};

pub const Hyperlink = struct {
    link_id: u32,
    uri_bytes: []u8,
};

pub const Snapshot = struct {
    allocator: std.mem.Allocator,
    begin: protocol.SnapshotBegin,
    presentation: Presentation,
    rows: []Row,
    hyperlinks: []Hyperlink,

    pub fn deinit(self: *Snapshot) void {
        for (self.rows) |row| {
            for (row.cells) |cell| if (cell.scalars.len != 0) self.allocator.free(cell.scalars);
            self.allocator.free(row.cells);
        }
        self.allocator.free(self.rows);
        for (self.hyperlinks) |link| self.allocator.free(link.uri_bytes);
        self.allocator.free(self.hyperlinks);
        self.* = undefined;
    }
};

/// Sends one ordinary request-driven rich observation without receiving it yet.
///
/// The caller must pair every successful call with exactly one `receive` on the
/// same connection before sending another request.
pub fn sendRequest(
    connection: *client.Connection,
    after_revision: u64,
    history_offset: u32,
) client.Error!void {
    var payload: [protocol.payload_bytes.observe]u8 = undefined;
    protocol.encodeObserve(&payload, .{
        .after_revision = after_revision,
        .history_offset = history_offset,
    });
    try connection.send(.observe, &payload);
}

pub fn request(
    connection: *client.Connection,
    allocator: std.mem.Allocator,
    after_revision: u64,
    history_offset: u32,
) Error!Snapshot {
    try sendRequest(connection, after_revision, history_offset);
    return receive(connection, allocator);
}

/// Receives one rich snapshot after the caller has already sent `observe`.
pub fn receive(connection: *client.Connection, allocator: std.mem.Allocator) Error!Snapshot {
    var total_bytes: usize = 0;
    var begin_frame = try connection.receive();
    defer begin_frame.deinit();
    try accountFrame(&total_bytes, begin_frame.payload.len);
    if (begin_frame.kind != .snapshot_begin) return error.UnexpectedFrame;
    const begin = try protocol.decodeSnapshotBegin(begin_frame.payload);

    const rows = try allocator.alloc(Row, begin.rows);
    errdefer allocator.free(rows);
    var initialized_rows: usize = 0;
    errdefer deinitRows(allocator, rows[0..initialized_rows]);

    var hyperlinks: std.ArrayList(Hyperlink) = .empty;
    errdefer {
        for (hyperlinks.items) |link| allocator.free(link.uri_bytes);
        hyperlinks.deinit(allocator);
    }

    var referenced: [protocol.text_v1.maximum_hyperlinks + 1]bool = @splat(false);
    var resolved: [protocol.text_v1.maximum_hyperlinks + 1]bool = @splat(false);
    var presentation: Presentation = undefined;
    var presentation_seen = false;
    var row_count: u16 = 0;
    var phase: DecodePhase = .presentation;
    var compressed_body: std.ArrayList(u8) = .empty;
    defer compressed_body.deinit(allocator);

    while (true) {
        var frame = try connection.receive();
        defer frame.deinit();
        try accountFrame(&total_bytes, frame.payload.len);
        switch (frame.kind) {
            .snapshot_data => {
                if (compressed_body.items.len + frame.payload.len > protocol.maximum_snapshot_bytes)
                    return error.SnapshotTooLarge;
                try compressed_body.appendSlice(allocator, frame.payload);
            },
            .snapshot_end => {
                const end = try protocol.decodeSnapshotEnd(frame.payload);
                if (end.revision != begin.revision) return error.InvalidSnapshot;
                try decodeTextBody(
                    allocator,
                    begin,
                    compressed_body.items,
                    rows,
                    &initialized_rows,
                    &hyperlinks,
                    &referenced,
                    &resolved,
                    &presentation,
                    &presentation_seen,
                    &row_count,
                    &phase,
                );
                if (!presentation_seen or row_count != begin.rows) return error.InvalidSnapshot;
                for (referenced[1..], resolved[1..]) |needed, seen| if (needed != seen)
                    return error.InvalidSnapshot;
                return .{
                    .allocator = allocator,
                    .begin = begin,
                    .presentation = presentation,
                    .rows = rows,
                    .hyperlinks = try hyperlinks.toOwnedSlice(allocator),
                };
            },
            else => return error.UnexpectedFrame,
        }
    }
}

const DecodePhase = enum { presentation, rows, hyperlinks };

fn decodeTextRecord(
    allocator: std.mem.Allocator,
    begin: protocol.SnapshotBegin,
    encoded_record: []const u8,
    rows: []Row,
    initialized_rows: *usize,
    hyperlinks: *std.ArrayList(Hyperlink),
    referenced: *[protocol.text_v1.maximum_hyperlinks + 1]bool,
    resolved: *[protocol.text_v1.maximum_hyperlinks + 1]bool,
    presentation: *Presentation,
    presentation_seen: *bool,
    row_count: *u16,
    phase: *DecodePhase,
) Error!void {
    if (encoded_record.len < protocol.text_v1.record_header_bytes) return error.InvalidSnapshot;
    var encoded_header: [protocol.text_v1.record_header_bytes]u8 = undefined;
    @memcpy(&encoded_header, encoded_record[0..protocol.text_v1.record_header_bytes]);
    const header = try protocol.decodeTextRecordHeader(&encoded_header);
    if (header.payload_len != encoded_record.len - protocol.text_v1.record_header_bytes)
        return error.InvalidSnapshot;
    const payload = encoded_record[protocol.text_v1.record_header_bytes..];
    switch (header.kind) {
        .presentation => {
            if (phase.* != .presentation or presentation_seen.*) return error.InvalidSnapshot;
            presentation.* = try decodePresentation(payload);
            presentation_seen.* = true;
            phase.* = .rows;
        },
        .row => {
            if (phase.* != .rows or !presentation_seen.* or row_count.* >= begin.rows)
                return error.InvalidSnapshot;
            rows[row_count.*] = try decodeRow(allocator, begin, payload, referenced);
            initialized_rows.* += 1;
            row_count.* += 1;
            if (row_count.* == begin.rows) phase.* = .hyperlinks;
        },
        .hyperlink => {
            if (phase.* != .hyperlinks) return error.InvalidSnapshot;
            try hyperlinks.append(allocator, try decodeHyperlink(allocator, payload, referenced, resolved));
        },
    }
}

fn decodeTextBody(
    allocator: std.mem.Allocator,
    begin: protocol.SnapshotBegin,
    encoded: []const u8,
    rows: []Row,
    initialized_rows: *usize,
    hyperlinks: *std.ArrayList(Hyperlink),
    referenced: *[protocol.text_v1.maximum_hyperlinks + 1]bool,
    resolved: *[protocol.text_v1.maximum_hyperlinks + 1]bool,
    presentation: *Presentation,
    presentation_seen: *bool,
    row_count: *u16,
    phase: *DecodePhase,
) Error!void {
    if (encoded.len <= protocol.text_v1.compressed_header_bytes) return error.InvalidSnapshot;
    const uncompressed_len = readU32(encoded[0..protocol.text_v1.compressed_header_bytes]);
    if (uncompressed_len == 0 or uncompressed_len > protocol.maximum_snapshot_bytes)
        return error.SnapshotTooLarge;
    const decoded = try allocator.alloc(u8, uncompressed_len);
    defer allocator.free(decoded);
    var output: std.Io.Writer = .fixed(decoded);
    var input: std.Io.Reader = .fixed(encoded[protocol.text_v1.compressed_header_bytes..]);
    const work = try allocator.alloc(u8, std.compress.flate.max_window_len);
    defer allocator.free(work);
    var decompressor: std.compress.flate.Decompress = .init(&input, .zlib, work);
    const decoded_count = decompressor.reader.streamRemaining(&output) catch return error.InvalidSnapshot;
    if (decoded_count != uncompressed_len or output.buffered().len != uncompressed_len or input.seek != input.end)
        return error.InvalidSnapshot;

    var offset: usize = 0;
    while (offset < decoded.len) {
        if (decoded.len - offset < protocol.text_v1.record_header_bytes) return error.InvalidSnapshot;
        var encoded_header: [protocol.text_v1.record_header_bytes]u8 = undefined;
        @memcpy(&encoded_header, decoded[offset..][0..protocol.text_v1.record_header_bytes]);
        const header = try protocol.decodeTextRecordHeader(&encoded_header);
        const record_len = std.math.add(
            usize,
            protocol.text_v1.record_header_bytes,
            header.payload_len,
        ) catch return error.InvalidSnapshot;
        if (record_len > decoded.len - offset) return error.InvalidSnapshot;
        try decodeTextRecord(
            allocator,
            begin,
            decoded[offset..][0..record_len],
            rows,
            initialized_rows,
            hyperlinks,
            referenced,
            resolved,
            presentation,
            presentation_seen,
            row_count,
            phase,
        );
        offset += record_len;
    }
}

fn decodePresentation(payload: []const u8) Error!Presentation {
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
    begin: protocol.SnapshotBegin,
    payload: []const u8,
    referenced: *[protocol.text_v1.maximum_hyperlinks + 1]bool,
) Error!Row {
    if (payload.len < protocol.text_v1.row_header_bytes or payload[0] > 1 or
        payload[1] > 3 or readU16(payload[2..4]) != begin.columns)
        return error.InvalidSnapshot;
    const cells = try allocator.alloc(Cell, begin.columns);
    errdefer allocator.free(cells);
    var initialized: usize = 0;
    errdefer for (cells[0..initialized]) |cell| if (cell.scalars.len != 0) allocator.free(cell.scalars);

    var offset: usize = protocol.text_v1.row_header_bytes;
    var column: u16 = 0;
    while (column < begin.columns) : (column += 1) {
        if (payload.len - offset < protocol.text_v1.cell_header_bytes) return error.InvalidSnapshot;
        const encoded = payload[offset..][0..protocol.text_v1.cell_header_bytes];
        const scalar_count = encoded[0];
        if (scalar_count > protocol.text_v1.maximum_cell_scalars or
            encoded[1] == 0 or encoded[2] == 0 or encoded[3] >= encoded[1] or encoded[4] >= encoded[2] or
            encoded[5] > 15 or encoded[6] > 15 or encoded[7] > 3 or encoded[8] > 3 or
            encoded[9] > 1 or encoded[10] > 15 or encoded[11] > 2 or encoded[12] > 4 or encoded[13] > 2)
            return error.InvalidSnapshot;
        const style_bits = readU16(encoded[14..16]);
        if (style_bits & ~protocol.text_v1.style.known != 0) return error.InvalidSnapshot;
        const foreground = try decodeColor(encoded[16..21]);
        const background = try decodeColor(encoded[21..26]);
        const underline_color = try decodeColor(encoded[26..31]);
        const link_id = readU32(encoded[31..35]);
        if (link_id > protocol.text_v1.maximum_hyperlinks) return error.InvalidSnapshot;
        if (link_id != 0) referenced[link_id] = true;

        offset += protocol.text_v1.cell_header_bytes;
        const scalar_bytes = @as(usize, scalar_count) * 4;
        if (payload.len - offset < scalar_bytes) return error.InvalidSnapshot;
        if ((encoded[3] != 0 or encoded[4] != 0) and scalar_count != 0) return error.InvalidSnapshot;
        const scalars: []const u32 = if (scalar_count == 0)
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
            .width = encoded[1],
            .height = encoded[2],
            .x = encoded[3],
            .y = encoded[4],
            .subscale_n = encoded[5],
            .subscale_d = encoded[6],
            .vertical_align = encoded[7],
            .horizontal_align = encoded[8],
            .semantic_width = encoded[9] == 1,
            .font = encoded[10],
            .baseline = encoded[11],
            .underline_style = encoded[12],
            .protection = encoded[13],
            .style_bits = style_bits,
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
        .wrapped = payload[0] == 1,
        .line_geometry = payload[1],
        .cells = cells,
    };
}

fn decodeHyperlink(
    allocator: std.mem.Allocator,
    payload: []const u8,
    referenced: *[protocol.text_v1.maximum_hyperlinks + 1]bool,
    resolved: *[protocol.text_v1.maximum_hyperlinks + 1]bool,
) Error!Hyperlink {
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
        .uri_bytes = try allocator.dupe(u8, payload[protocol.text_v1.hyperlink_header_bytes..]),
    };
}

fn decodeColor(bytes: []const u8) Error!protocol.TextColor {
    if (bytes.len != protocol.text_v1.color_bytes) return error.InvalidSnapshot;
    var encoded: [protocol.text_v1.color_bytes]u8 = undefined;
    @memcpy(&encoded, bytes);
    return protocol.decodeTextColor(&encoded);
}

fn accountFrame(total: *usize, payload_len: usize) error{SnapshotTooLarge}!void {
    total.* = std.math.add(usize, total.*, protocol.header_bytes + payload_len) catch
        return error.SnapshotTooLarge;
    if (total.* > protocol.maximum_snapshot_bytes) return error.SnapshotTooLarge;
}

fn rgba(bytes: []const u8) Rgba {
    std.debug.assert(bytes.len == 4);
    return .{ .r = bytes[0], .g = bytes[1], .b = bytes[2], .a = bytes[3] };
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

fn deinitRows(allocator: std.mem.Allocator, rows: []Row) void {
    for (rows) |row| {
        for (row.cells) |cell| if (cell.scalars.len != 0) allocator.free(cell.scalars);
        allocator.free(row.cells);
    }
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

test "rich row preserves typed style color and grapheme state" {
    const begin = protocol.SnapshotBegin{
        .revision = 3,
        .terminal_revision = 9,
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
    const row = try decodeRow(std.testing.allocator, begin, &payload, &referenced);
    defer {
        for (row.cells) |decoded| if (decoded.scalars.len != 0) std.testing.allocator.free(decoded.scalars);
        std.testing.allocator.free(row.cells);
    }
    const decoded = row.cells[0];
    try std.testing.expect(row.wrapped);
    try std.testing.expectEqual(@as(u8, 2), row.line_geometry);
    try std.testing.expectEqualSlices(u32, &.{ 'e', 0x0301 }, decoded.scalars);
    try std.testing.expect(decoded.style_bits & protocol.text_v1.style.bold != 0);
    try std.testing.expectEqual(protocol.TextColorKind.rgb, decoded.foreground.kind);
    try std.testing.expectEqual(@as(u32, 0x112233), decoded.foreground.value);
    try std.testing.expectEqual(protocol.TextColorKind.indexed, decoded.background.kind);
    try std.testing.expectEqual(@as(u32, 4), decoded.background.value);
    try std.testing.expectEqual(@as(u32, 7), decoded.link_id);
    try std.testing.expect(referenced[7]);
}

test "rich hyperlink preserves arbitrary URI bytes exactly" {
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
    defer std.testing.allocator.free(link.uri_bytes);
    try std.testing.expectEqualSlices(u8, &.{ 'A', 0, 0xff, 'Z' }, link.uri_bytes);
    try std.testing.expect(resolved[2]);
}

fn testDeflateBody(allocator: std.mem.Allocator, body: []const u8) ![]u8 {
    var compressed: std.Io.Writer.Allocating = .init(allocator);
    defer compressed.deinit();
    const work = try allocator.alloc(u8, std.compress.flate.max_window_len);
    defer allocator.free(work);
    const compressor = try allocator.create(std.compress.flate.Compress);
    defer allocator.destroy(compressor);
    compressor.* = try std.compress.flate.Compress.init(
        &compressed.writer,
        work,
        .zlib,
        .fastest,
    );
    try compressor.writer.writeAll(body);
    try compressor.finish();
    const result = try allocator.alloc(
        u8,
        protocol.text_v1.compressed_header_bytes + compressed.written().len,
    );
    encodeU32(result[0..protocol.text_v1.compressed_header_bytes], @intCast(body.len));
    @memcpy(result[protocol.text_v1.compressed_header_bytes..], compressed.written());
    return result;
}

test "deflated rich body reuses the text record decoder" {
    const begin = protocol.SnapshotBegin{
        .revision = 3,
        .terminal_revision = 9,
        .history_offset = 0,
        .history_count = 0,
        .history_row_base = 0,
        .rows = 0,
        .columns = 0,
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
    var body: [protocol.text_v1.record_header_bytes + protocol.text_v1.presentation_bytes]u8 = @splat(0);
    var record_header: [protocol.text_v1.record_header_bytes]u8 = undefined;
    protocol.encodeTextRecordHeader(&record_header, .{
        .kind = .presentation,
        .payload_len = protocol.text_v1.presentation_bytes,
    });
    @memcpy(body[0..protocol.text_v1.record_header_bytes], &record_header);
    const encoded = try testDeflateBody(std.testing.allocator, &body);
    defer std.testing.allocator.free(encoded);

    const rows = try std.testing.allocator.alloc(Row, 0);
    defer std.testing.allocator.free(rows);
    var initialized_rows: usize = 0;
    var hyperlinks: std.ArrayList(Hyperlink) = .empty;
    defer hyperlinks.deinit(std.testing.allocator);
    var referenced: [protocol.text_v1.maximum_hyperlinks + 1]bool = @splat(false);
    var resolved: [protocol.text_v1.maximum_hyperlinks + 1]bool = @splat(false);
    var presentation: Presentation = undefined;
    var presentation_seen = false;
    var row_count: u16 = 0;
    var phase: DecodePhase = .presentation;
    try decodeTextBody(
        std.testing.allocator,
        begin,
        encoded,
        rows,
        &initialized_rows,
        &hyperlinks,
        &referenced,
        &resolved,
        &presentation,
        &presentation_seen,
        &row_count,
        &phase,
    );
    try std.testing.expect(presentation_seen);
    try std.testing.expectEqual(@as(u16, 0), row_count);
    try std.testing.expectEqual(DecodePhase.rows, phase);
}

test "deflated rich body rejects corrupt and oversized streams" {
    const begin = protocol.SnapshotBegin{
        .revision = 3,
        .terminal_revision = 9,
        .history_offset = 0,
        .history_count = 0,
        .history_row_base = 0,
        .rows = 0,
        .columns = 0,
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
    var body: [protocol.text_v1.record_header_bytes + protocol.text_v1.presentation_bytes]u8 = @splat(0);
    var record_header: [protocol.text_v1.record_header_bytes]u8 = undefined;
    protocol.encodeTextRecordHeader(&record_header, .{
        .kind = .presentation,
        .payload_len = protocol.text_v1.presentation_bytes,
    });
    @memcpy(body[0..protocol.text_v1.record_header_bytes], &record_header);
    const encoded = try testDeflateBody(std.testing.allocator, &body);
    defer std.testing.allocator.free(encoded);
    encoded[encoded.len - 1] ^= 0xff;

    const rows = try std.testing.allocator.alloc(Row, 0);
    defer std.testing.allocator.free(rows);
    var initialized_rows: usize = 0;
    var hyperlinks: std.ArrayList(Hyperlink) = .empty;
    defer hyperlinks.deinit(std.testing.allocator);
    var referenced: [protocol.text_v1.maximum_hyperlinks + 1]bool = @splat(false);
    var resolved: [protocol.text_v1.maximum_hyperlinks + 1]bool = @splat(false);
    var presentation: Presentation = undefined;
    var presentation_seen = false;
    var row_count: u16 = 0;
    var phase: DecodePhase = .presentation;
    try std.testing.expectError(error.InvalidSnapshot, decodeTextBody(
        std.testing.allocator,
        begin,
        encoded,
        rows,
        &initialized_rows,
        &hyperlinks,
        &referenced,
        &resolved,
        &presentation,
        &presentation_seen,
        &row_count,
        &phase,
    ));

    var oversized: [protocol.text_v1.compressed_header_bytes + 1]u8 = @splat(0);
    encodeU32(oversized[0..protocol.text_v1.compressed_header_bytes], protocol.maximum_snapshot_bytes + 1);
    initialized_rows = 0;
    presentation_seen = false;
    row_count = 0;
    phase = .presentation;
    try std.testing.expectError(error.SnapshotTooLarge, decodeTextBody(
        std.testing.allocator,
        begin,
        &oversized,
        rows,
        &initialized_rows,
        &hyperlinks,
        &referenced,
        &resolved,
        &presentation,
        &presentation_seen,
        &row_count,
        &phase,
    ));
}
