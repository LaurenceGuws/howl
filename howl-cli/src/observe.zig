//! Decodes one bounded renderer-neutral text snapshot into agent-friendly semantic rows.

const std = @import("std");
const protocol = @import("howl_session").protocol;
const client = @import("client.zig");

const Phase = enum { presentation, rows, hyperlinks };

/// Owns one coherent semantic observation and its compact UTF-8 row projection.
pub const Snapshot = struct {
    allocator: std.mem.Allocator,
    begin: protocol.SnapshotBegin,
    row_offsets: []u32,
    text: []u8,

    /// Releases all materialized row metadata and UTF-8 text.
    pub fn deinit(self: *Snapshot) void {
        self.allocator.free(self.text);
        self.allocator.free(self.row_offsets);
        self.* = undefined;
    }

    /// Borrows one projected canonical row by zero-based row index.
    pub fn row(self: *const Snapshot, index: u16) []const u8 {
        std.debug.assert(index < self.begin.rows);
        const start = self.row_offsets[index];
        const end = self.row_offsets[@as(usize, index) + 1];
        return self.text[start..end];
    }
};

/// Reports capability, framing, snapshot grammar, allocation, or bound failure.
pub const Error = client.Error || error{
    MissingTextSnapshotFeature,
    ObserveRejected,
    UnexpectedFrame,
    MalformedSnapshot,
    SnapshotTooLarge,
};

/// Requests one coherent current `text_v1` snapshot from a negotiated connection.
pub fn current(connection: *client.Connection) Error!Snapshot {
    if (connection.features & protocol.feature(.text_snapshot) == 0)
        return error.MissingTextSnapshotFeature;
    var request: [protocol.payload_bytes.observe]u8 = undefined;
    protocol.encodeObserve(&request, .{ .after_revision = 0 });
    try connection.send(.observe, &request);

    var begin_frame = try connection.receive();
    defer begin_frame.deinit();
    if (begin_frame.kind == .result) {
        const result = try protocol.decodeResult(begin_frame.payload);
        if (result.request_kind == .observe and result.code != .ok) return error.ObserveRejected;
        return error.UnexpectedFrame;
    }
    if (begin_frame.kind != .snapshot_begin) return error.UnexpectedFrame;
    const begin = try protocol.decodeSnapshotBegin(begin_frame.payload);
    if (begin.format != .text_v1 or begin.rows == 0 or begin.columns == 0)
        return error.MalformedSnapshot;

    const row_offset_count = std.math.add(usize, begin.rows, 1) catch return error.MalformedSnapshot;
    const row_offsets = try connection.allocator.alloc(u32, row_offset_count);
    errdefer connection.allocator.free(row_offsets);
    row_offsets[0] = 0;
    var text: std.ArrayList(u8) = .empty;
    errdefer text.deinit(connection.allocator);
    var referenced: [protocol.text_v1.maximum_hyperlinks + 1]bool = @splat(false);
    var resolved: [protocol.text_v1.maximum_hyperlinks + 1]bool = @splat(false);
    var phase: Phase = .presentation;
    var row_count: u16 = 0;
    var total_bytes = protocol.header_bytes + begin_frame.payload.len;

    while (true) {
        var frame = try connection.receive();
        defer frame.deinit();
        total_bytes = std.math.add(usize, total_bytes, protocol.header_bytes + frame.payload.len) catch
            return error.SnapshotTooLarge;
        if (total_bytes > protocol.maximum_snapshot_bytes) return error.SnapshotTooLarge;
        switch (frame.kind) {
            .snapshot_data => try appendData(
                begin,
                frame.payload,
                &phase,
                &row_count,
                row_offsets,
                &text,
                connection.allocator,
                &referenced,
                &resolved,
            ),
            .snapshot_end => {
                const end = try protocol.decodeSnapshotEnd(frame.payload);
                if (end.revision != begin.revision or phase != .hyperlinks or row_count != begin.rows)
                    return error.MalformedSnapshot;
                for (referenced, resolved) |needed, present| if (needed != present)
                    return error.MalformedSnapshot;
                return .{
                    .allocator = connection.allocator,
                    .begin = begin,
                    .row_offsets = row_offsets,
                    .text = try text.toOwnedSlice(connection.allocator),
                };
            },
            else => return error.UnexpectedFrame,
        }
    }
}

fn appendData(
    begin: protocol.SnapshotBegin,
    frame_payload: []const u8,
    phase: *Phase,
    row_count: *u16,
    row_offsets: []u32,
    text: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    referenced: *[protocol.text_v1.maximum_hyperlinks + 1]bool,
    resolved: *[protocol.text_v1.maximum_hyperlinks + 1]bool,
) Error!void {
    if (frame_payload.len < protocol.text_v1.record_header_bytes) return error.MalformedSnapshot;
    var header_bytes: [protocol.text_v1.record_header_bytes]u8 = undefined;
    @memcpy(&header_bytes, frame_payload[0..protocol.text_v1.record_header_bytes]);
    const record = protocol.decodeTextRecordHeader(&header_bytes) catch return error.MalformedSnapshot;
    if (record.payload_len != frame_payload.len - protocol.text_v1.record_header_bytes)
        return error.MalformedSnapshot;
    const payload = frame_payload[protocol.text_v1.record_header_bytes..];
    switch (record.kind) {
        .presentation => {
            if (phase.* != .presentation) return error.MalformedSnapshot;
            try validatePresentation(payload);
            phase.* = .rows;
        },
        .row => {
            if (phase.* != .rows or row_count.* >= begin.rows) return error.MalformedSnapshot;
            try appendRow(begin, payload, text, allocator, referenced);
            row_count.* += 1;
            row_offsets[row_count.*] = std.math.cast(u32, text.items.len) orelse
                return error.SnapshotTooLarge;
            if (row_count.* == begin.rows) phase.* = .hyperlinks;
        },
        .hyperlink => {
            if (phase.* != .hyperlinks) return error.MalformedSnapshot;
            try validateHyperlink(payload, resolved);
        },
    }
}

fn validatePresentation(payload: []const u8) error{MalformedSnapshot}!void {
    if (payload.len != protocol.text_v1.presentation_bytes or
        payload[8] & ~protocol.text_v1.presentation_presence.known != 0 or
        payload[9] & ~protocol.text_v1.presentation_flags.known != 0 or
        payload[10] != 0 or payload[11] != 0)
        return error.MalformedSnapshot;
}

fn appendRow(
    begin: protocol.SnapshotBegin,
    payload: []const u8,
    text: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    referenced: *[protocol.text_v1.maximum_hyperlinks + 1]bool,
) Error!void {
    if (payload.len < protocol.text_v1.row_header_bytes or payload[0] > 1 or
        payload[1] > 3 or readU16(payload[2..4]) != begin.columns)
        return error.MalformedSnapshot;
    var offset: usize = protocol.text_v1.row_header_bytes;
    var column: u16 = 0;
    while (column < begin.columns) : (column += 1) {
        if (payload.len - offset < protocol.text_v1.cell_header_bytes)
            return error.MalformedSnapshot;
        const cell = payload[offset..][0..protocol.text_v1.cell_header_bytes];
        const scalar_count = cell[0];
        if (scalar_count > protocol.text_v1.maximum_cell_scalars or
            cell[1] == 0 or cell[2] == 0 or cell[3] >= cell[1] or cell[4] >= cell[2] or
            cell[5] > 15 or cell[6] > 15 or cell[7] > 3 or cell[8] > 3 or
            cell[9] > 1 or cell[10] > 15 or cell[11] > 2 or cell[12] > 4 or cell[13] > 2)
            return error.MalformedSnapshot;
        const style = readU16(cell[14..16]);
        if (style & ~protocol.text_v1.style.known != 0) return error.MalformedSnapshot;
        try validateColor(cell[16..21]);
        try validateColor(cell[21..26]);
        try validateColor(cell[26..31]);
        const link_id = readU32(cell[31..35]);
        if (link_id > protocol.text_v1.maximum_hyperlinks) return error.MalformedSnapshot;
        if (link_id != 0) referenced[link_id] = true;

        const scalar_bytes = @as(usize, scalar_count) * 4;
        offset += protocol.text_v1.cell_header_bytes;
        if (payload.len - offset < scalar_bytes) return error.MalformedSnapshot;
        const scalars = payload[offset..][0..scalar_bytes];
        const continuation = cell[3] != 0 or cell[4] != 0;
        if (continuation and scalar_count != 0) return error.MalformedSnapshot;
        if (!continuation) {
            if (scalar_count == 0) {
                try appendBounded(text, allocator, " ");
            } else {
                var scalar_index: usize = 0;
                while (scalar_index < scalar_count) : (scalar_index += 1) {
                    const scalar = readU32(scalars[scalar_index * 4 ..][0..4]);
                    if (!validScalar(scalar)) return error.MalformedSnapshot;
                    var encoded: [4]u8 = undefined;
                    const length = std.unicode.utf8Encode(@intCast(scalar), &encoded) catch
                        return error.MalformedSnapshot;
                    try appendBounded(text, allocator, encoded[0..length]);
                }
            }
        }
        offset += scalar_bytes;
    }
    if (offset != payload.len) return error.MalformedSnapshot;
}

fn validateColor(bytes: []const u8) error{MalformedSnapshot}!void {
    if (bytes.len != protocol.text_v1.color_bytes) return error.MalformedSnapshot;
    var encoded: [protocol.text_v1.color_bytes]u8 = undefined;
    @memcpy(&encoded, bytes);
    const color = protocol.decodeTextColor(&encoded) catch return error.MalformedSnapshot;
    switch (color.kind) {
        .default, .indexed, .rgb => {},
    }
}

fn validateHyperlink(
    payload: []const u8,
    resolved: *[protocol.text_v1.maximum_hyperlinks + 1]bool,
) error{MalformedSnapshot}!void {
    if (payload.len < protocol.text_v1.hyperlink_header_bytes) return error.MalformedSnapshot;
    const id = readU32(payload[0..4]);
    const uri_len = readU16(payload[4..6]);
    if (id == 0 or id > protocol.text_v1.maximum_hyperlinks or
        uri_len == 0 or uri_len > protocol.text_v1.maximum_hyperlink_uri_bytes or
        payload.len != protocol.text_v1.hyperlink_header_bytes + uri_len or resolved[id])
        return error.MalformedSnapshot;
    resolved[id] = true;
}

fn appendBounded(
    text: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    bytes: []const u8,
) Error!void {
    const next = std.math.add(usize, text.items.len, bytes.len) catch return error.SnapshotTooLarge;
    if (next > protocol.maximum_snapshot_bytes) return error.SnapshotTooLarge;
    try text.appendSlice(allocator, bytes);
}

fn validScalar(value: u32) bool {
    return value <= 0x10ffff and !(value >= 0xd800 and value <= 0xdfff);
}

fn readU16(input: []const u8) u16 {
    std.debug.assert(input.len == 2);
    return (@as(u16, input[0]) << 8) | input[1];
}

fn readU32(input: []const u8) u32 {
    std.debug.assert(input.len == 4);
    return (@as(u32, input[0]) << 24) |
        (@as(u32, input[1]) << 16) |
        (@as(u32, input[2]) << 8) |
        input[3];
}
