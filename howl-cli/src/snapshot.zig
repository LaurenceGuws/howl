const std = @import("std");
const protocol = @import("howl_session").protocol;
const transport = @import("howl_transport");

pub const Error = transport.wire.Error || std.mem.Allocator.Error || protocol.PayloadError || error{
    UnexpectedFrame,
    SnapshotTooLarge,
    InvalidSnapshot,
    UnsupportedSnapshotFormat,
};

pub const Detail = struct {
    styled_cells: u32 = 0,
    linked_cells: u32 = 0,
    multicell_cells: u32 = 0,
    hyperlinks: u32 = 0,
};

pub const LineGeometry = struct {
    row: u16,
    value: []const u8,
    value_id: u8,
};

pub const Snapshot = struct {
    allocator: std.mem.Allocator,
    begin: protocol.SnapshotBegin,
    lines: [][]const u8,
    wrapped_rows: []u16,
    line_geometry: []LineGeometry,
    detail: Detail,

    pub fn deinit(self: *Snapshot) void {
        for (self.lines) |line| self.allocator.free(line);
        self.allocator.free(self.lines);
        self.allocator.free(self.wrapped_rows);
        self.allocator.free(self.line_geometry);
        self.* = undefined;
    }
};

const Geometry = struct { rows: u16, columns: u16 };
const Viewport = struct {
    screen: []const u8,
    history_offset: u32,
    history_count: u32,
    history_row_base: u32,
};
const Cursor = struct {
    row: u16,
    column: u16,
    shape: []const u8,
    shape_id: u8,
    visible: bool,
    blink: bool,
};
const Lifecycle = struct { stream_closed: bool, child_exited: bool };
const Resize = struct { leader_present: bool, you_are_leader: bool };
const Compact = struct {
    schema: []const u8 = "howl.snapshot/v1",
    revision: u64,
    terminal_revision: u64,
    geometry: Geometry,
    viewport: Viewport,
    cursor: Cursor,
    lifecycle: Lifecycle,
    resize: Resize,
    lines: [][]const u8,
    wrapped_rows: []u16,
    line_geometry: []LineGeometry,
    detail: Detail,
};

pub fn request(
    connection: *transport.wire.Connection,
    allocator: std.mem.Allocator,
    after_revision: u64,
    history_offset: u32,
) Error!Snapshot {
    var payload: [protocol.payload_bytes.observe]u8 = undefined;
    protocol.encodeObserve(&payload, .{
        .after_revision = after_revision,
        .history_offset = history_offset,
    });
    try connection.send(.observe, &payload);
    return receive(connection, allocator);
}

pub fn emitCompact(writer: *std.Io.Writer, value: *const Snapshot) !void {
    const begin = value.begin;
    try std.json.Stringify.value(Compact{
        .revision = begin.revision,
        .terminal_revision = begin.terminal_revision,
        .geometry = .{ .rows = begin.rows, .columns = begin.columns },
        .viewport = .{
            .screen = if (begin.alternate_screen) "alternate" else "primary",
            .history_offset = begin.history_offset,
            .history_count = begin.history_count,
            .history_row_base = begin.history_row_base,
        },
        .cursor = .{
            .row = begin.cursor_row,
            .column = begin.cursor_column,
            .shape = cursorShape(begin.cursor_shape),
            .shape_id = begin.cursor_shape,
            .visible = begin.cursor_visible,
            .blink = begin.cursor_blink,
        },
        .lifecycle = .{
            .stream_closed = begin.stream_closed,
            .child_exited = begin.child_exited,
        },
        .resize = .{
            .leader_present = begin.leader_present,
            .you_are_leader = begin.you_are_leader,
        },
        .lines = value.lines,
        .wrapped_rows = value.wrapped_rows,
        .line_geometry = value.line_geometry,
        .detail = value.detail,
    }, .{}, writer);
    try writer.writeByte('\n');
}

pub fn emitText(writer: *std.Io.Writer, value: *const Snapshot) !void {
    for (value.lines) |line| {
        try writer.writeAll(line);
        try writer.writeByte('\n');
    }
}

pub fn requestRich(
    connection: *transport.wire.Connection,
    writer: *std.Io.Writer,
    after_revision: u64,
    history_offset: u32,
) !void {
    var payload: [protocol.payload_bytes.observe]u8 = undefined;
    protocol.encodeObserve(&payload, .{
        .after_revision = after_revision,
        .history_offset = history_offset,
    });
    try connection.send(.observe, &payload);
    try transport.observe.receiveAndEmitSnapshot(connection, connection.allocator, writer);
}

fn receive(connection: *transport.wire.Connection, allocator: std.mem.Allocator) Error!Snapshot {
    var total_bytes: usize = 0;
    var begin_frame = try connection.receive();
    defer begin_frame.deinit();
    try accountFrame(&total_bytes, begin_frame.payload.len);
    if (begin_frame.kind != .snapshot_begin) return error.UnexpectedFrame;
    const begin = try protocol.decodeSnapshotBegin(begin_frame.payload);
    if (begin.format != .text_v1) return error.UnsupportedSnapshotFormat;

    const lines = try allocator.alloc([]const u8, begin.rows);
    errdefer allocator.free(lines);
    var initialized_lines: usize = 0;
    errdefer for (lines[0..initialized_lines]) |line| allocator.free(line);

    var wrapped_rows: std.ArrayList(u16) = .empty;
    errdefer wrapped_rows.deinit(allocator);
    var line_geometry: std.ArrayList(LineGeometry) = .empty;
    errdefer line_geometry.deinit(allocator);
    var detail: Detail = .{};
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
                        try validatePresentation(payload);
                        presentation_seen = true;
                        phase = .rows;
                    },
                    .row => {
                        if (phase != .rows or !presentation_seen or row_count >= begin.rows)
                            return error.InvalidSnapshot;
                        const row = try decodeReadableRow(allocator, begin, payload, &detail, &referenced);
                        lines[row_count] = row.text;
                        initialized_lines += 1;
                        if (row.wrapped) try wrapped_rows.append(allocator, row_count);
                        if (row.line_geometry != 0) try line_geometry.append(allocator, .{
                            .row = row_count,
                            .value = lineGeometry(row.line_geometry),
                            .value_id = row.line_geometry,
                        });
                        row_count += 1;
                        if (row_count == begin.rows) phase = .hyperlinks;
                    },
                    .hyperlink => {
                        if (phase != .hyperlinks) return error.InvalidSnapshot;
                        try validateHyperlink(payload, &referenced, &resolved);
                        detail.hyperlinks += 1;
                    },
                }
            },
            .snapshot_end => {
                const end = try protocol.decodeSnapshotEnd(frame.payload);
                if (end.revision != begin.revision or !presentation_seen or row_count != begin.rows)
                    return error.InvalidSnapshot;
                for (referenced[1..], resolved[1..]) |needed, seen| if (needed != seen)
                    return error.InvalidSnapshot;
                const wrapped_owned = try wrapped_rows.toOwnedSlice(allocator);
                errdefer allocator.free(wrapped_owned);
                const geometry_owned = try line_geometry.toOwnedSlice(allocator);
                errdefer allocator.free(geometry_owned);
                return .{
                    .allocator = allocator,
                    .begin = begin,
                    .lines = lines,
                    .wrapped_rows = wrapped_owned,
                    .line_geometry = geometry_owned,
                    .detail = detail,
                };
            },
            else => return error.UnexpectedFrame,
        }
    }
}

fn validatePresentation(payload: []const u8) Error!void {
    if (payload.len != protocol.text_v1.presentation_bytes) return error.InvalidSnapshot;
    if (payload[8] & ~protocol.text_v1.presentation_presence.known != 0 or
        payload[9] & ~protocol.text_v1.presentation_flags.known != 0 or
        payload[10] != 0 or payload[11] != 0)
        return error.InvalidSnapshot;
}

const DecodedRow = struct {
    text: []const u8,
    wrapped: bool,
    line_geometry: u8,
};

fn decodeReadableRow(
    allocator: std.mem.Allocator,
    begin: protocol.SnapshotBegin,
    payload: []const u8,
    detail: *Detail,
    referenced: *[protocol.text_v1.maximum_hyperlinks + 1]bool,
) Error!DecodedRow {
    if (payload.len < protocol.text_v1.row_header_bytes or payload[0] > 1 or
        payload[1] > 3 or readU16(payload[2..4]) != begin.columns)
        return error.InvalidSnapshot;

    var line: std.ArrayList(u8) = .empty;
    errdefer line.deinit(allocator);
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
        if (link_id != 0) {
            referenced[link_id] = true;
            detail.linked_cells += 1;
        }
        if (style_bits != 0 or foreground.kind != .default or background.kind != .default or
            underline_color.kind != .default or cell[5] != 0 or cell[6] != 0 or cell[7] != 0 or
            cell[8] != 0 or cell[9] != 0 or cell[10] != 0 or cell[11] != 0 or cell[12] != 0 or
            cell[13] != 0)
            detail.styled_cells += 1;
        if (cell[1] != 1 or cell[2] != 1 or cell[3] != 0 or cell[4] != 0)
            detail.multicell_cells += 1;

        offset += protocol.text_v1.cell_header_bytes;
        const scalar_bytes = @as(usize, scalar_count) * 4;
        if (payload.len - offset < scalar_bytes) return error.InvalidSnapshot;
        if ((cell[3] != 0 or cell[4] != 0) and scalar_count != 0) return error.InvalidSnapshot;

        if (scalar_count == 0) {
            if (cell[3] == 0 and cell[4] == 0) try line.append(allocator, ' ');
        } else {
            var scalar_index: usize = 0;
            while (scalar_index < scalar_count) : (scalar_index += 1) {
                const scalar = readU32(payload[offset + scalar_index * 4 ..][0..4]);
                if (scalar > 0x10ffff or scalar >= 0xd800 and scalar <= 0xdfff)
                    return error.InvalidSnapshot;
                var encoded: [4]u8 = undefined;
                const length = std.unicode.utf8Encode(@intCast(scalar), &encoded) catch
                    return error.InvalidSnapshot;
                try line.appendSlice(allocator, encoded[0..length]);
            }
        }
        offset += scalar_bytes;
    }
    if (offset != payload.len) return error.InvalidSnapshot;
    while (line.items.len != 0 and line.items[line.items.len - 1] == ' ') line.items.len -= 1;
    return .{
        .text = try line.toOwnedSlice(allocator),
        .wrapped = payload[0] == 1,
        .line_geometry = payload[1],
    };
}

fn validateHyperlink(
    payload: []const u8,
    referenced: *[protocol.text_v1.maximum_hyperlinks + 1]bool,
    resolved: *[protocol.text_v1.maximum_hyperlinks + 1]bool,
) Error!void {
    if (payload.len < protocol.text_v1.hyperlink_header_bytes) return error.InvalidSnapshot;
    const link_id = readU32(payload[0..4]);
    const uri_len = readU16(payload[4..6]);
    if (link_id == 0 or link_id > protocol.text_v1.maximum_hyperlinks or
        uri_len == 0 or uri_len > protocol.text_v1.maximum_hyperlink_uri_bytes or
        payload.len != protocol.text_v1.hyperlink_header_bytes + uri_len or
        !referenced[link_id] or resolved[link_id])
        return error.InvalidSnapshot;
    resolved[link_id] = true;
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

fn lineGeometry(value: u8) []const u8 {
    return switch (value) {
        1 => "double_width",
        2 => "double_height_top",
        3 => "double_height_bottom",
        else => "single_width",
    };
}

fn cursorShape(value: u8) []const u8 {
    return switch (value) {
        0 => "block",
        1 => "underline",
        2 => "bar",
        3 => "none",
        else => "unknown",
    };
}

fn readU16(bytes: []const u8) u16 {
    return (@as(u16, bytes[0]) << 8) | bytes[1];
}
fn readU32(bytes: []const u8) u32 {
    return (@as(u32, bytes[0]) << 24) |
        (@as(u32, bytes[1]) << 16) |
        (@as(u32, bytes[2]) << 8) |
        bytes[3];
}

test "compact row keeps readable grapheme and reports omitted style" {
    const begin = protocol.SnapshotBegin{
        .revision = 1,
        .terminal_revision = 2,
        .format = .text_v1,
        .history_offset = 0,
        .history_count = 0,
        .history_row_base = 0,
        .rows = 1,
        .columns = 2,
        .cursor_row = 0,
        .cursor_column = 1,
        .cursor_shape = 0,
        .cursor_visible = true,
        .cursor_blink = true,
        .alternate_screen = false,
        .stream_closed = false,
        .child_exited = false,
        .leader_present = false,
        .you_are_leader = false,
    };
    var payload: [protocol.text_v1.row_header_bytes + protocol.text_v1.cell_header_bytes * 2 + 4]u8 = @splat(0);
    payload[2] = 0;
    payload[3] = 2;
    const first = payload[4 .. 4 + protocol.text_v1.cell_header_bytes];
    first[0] = 1;
    first[1] = 1;
    first[2] = 1;
    first[14] = 0;
    first[15] = protocol.text_v1.style.bold;
    const default_color = [_]u8{ @backingInt(protocol.TextColorKind.default), 0, 0, 0, 0 };
    @memcpy(first[16..21], &default_color);
    @memcpy(first[21..26], &default_color);
    @memcpy(first[26..31], &default_color);
    payload[4 + protocol.text_v1.cell_header_bytes] = 0;
    payload[4 + protocol.text_v1.cell_header_bytes + 1] = 0;
    payload[4 + protocol.text_v1.cell_header_bytes + 2] = 0;
    payload[4 + protocol.text_v1.cell_header_bytes + 3] = 'A';
    const second_offset = 4 + protocol.text_v1.cell_header_bytes + 4;
    const second = payload[second_offset .. second_offset + protocol.text_v1.cell_header_bytes];
    second[1] = 1;
    second[2] = 1;
    @memcpy(second[16..21], &default_color);
    @memcpy(second[21..26], &default_color);
    @memcpy(second[26..31], &default_color);

    var detail: Detail = .{};
    var referenced: [protocol.text_v1.maximum_hyperlinks + 1]bool = @splat(false);
    const row = try decodeReadableRow(std.testing.allocator, begin, &payload, &detail, &referenced);
    defer std.testing.allocator.free(row.text);
    try std.testing.expectEqualStrings("A", row.text);
    try std.testing.expect(!row.wrapped);
    try std.testing.expectEqual(@as(u8, 0), row.line_geometry);
    try std.testing.expectEqual(@as(u32, 1), detail.styled_cells);
}
