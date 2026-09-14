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
    /// One decoded-row scalar bank. Hand-built rows may leave this empty and
    /// retain independently owned cell scalar slices.
    scalar_storage: []u32 = &.{},
};

pub const Hyperlink = struct {
    link_id: u32,
    uri_bytes: []u8,
};

pub const Graphics = struct {
    generation: u64 = 0,
    content_generation: u64 = 0,
    cell_pixel_width: u32 = 0,
    cell_pixel_height: u32 = 0,
    images: []protocol.SnapshotImage = &.{},
    placements: []protocol.SnapshotImagePlacement = &.{},

    fn deinit(self: *Graphics, allocator: std.mem.Allocator) void {
        if (self.images.len != 0) allocator.free(self.images);
        if (self.placements.len != 0) allocator.free(self.placements);
        self.* = undefined;
    }
};

pub const Snapshot = struct {
    allocator: std.mem.Allocator,
    begin: protocol.SnapshotBegin,
    presentation: Presentation,
    rows: []Row,
    hyperlinks: []Hyperlink,
    graphics: Graphics = .{},

    pub fn view(self: *const Snapshot) View {
        return .{
            .begin = self.begin,
            .presentation = self.presentation,
            .rows = self.rows,
            .hyperlinks = self.hyperlinks,
            .graphics = self.graphics,
        };
    }

    pub fn deinit(self: *Snapshot) void {
        for (self.rows) |row| {
            if (row.scalar_storage.len != 0) {
                self.allocator.free(row.scalar_storage);
            } else {
                for (row.cells) |cell| if (cell.scalars.len != 0) self.allocator.free(cell.scalars);
            }
            self.allocator.free(row.cells);
        }
        self.allocator.free(self.rows);
        for (self.hyperlinks) |link| self.allocator.free(link.uri_bytes);
        self.allocator.free(self.hyperlinks);
        self.graphics.deinit(self.allocator);
        self.* = undefined;
    }
};


/// Borrows one complete decoded rich snapshot from a reusable raw-observation cache.
///
/// Every slice remains valid only until the owning `RawCache` receives again or
/// is deinitialized. Session remains canonical; `changed_rows` reports only
/// exact encoded-row record inequality against the cache's previous accepted cut.
pub const View = struct {
    begin: protocol.SnapshotBegin,
    presentation: Presentation,
    rows: []const Row,
    hyperlinks: []const Hyperlink,
    graphics: Graphics,
};

const CachedRowRecord = struct {
    encoded: []u8 = &.{},
    link_ids: []u16 = &.{},
};

/// Reuses already-validated row facts across complete v5 raw observations.
///
/// The endpoint still transports a complete snapshot. This owner compares each
/// self-delimiting row record byte-for-byte and decodes only records that changed.
/// Geometry changes invalidate the complete row cache. Invalid input likewise
/// clears cached rows before returning an error, so stale partial facts can never
/// become an accepted borrowed view.
pub const RawCache = struct {
    allocator: std.mem.Allocator,
    text_body: std.ArrayList(u8) = .empty,
    rows: []Row = &.{},
    row_records: []CachedRowRecord = &.{},
    columns: u16 = 0,
    hyperlinks: []Hyperlink = &.{},
    graphics: Graphics = .{},

    pub fn init(allocator: std.mem.Allocator) RawCache {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *RawCache) void {
        self.clearRows();
        self.clearHyperlinks();
        self.graphics.deinit(self.allocator);
        self.text_body.deinit(self.allocator);
        self.* = undefined;
    }

    /// Receives one previously armed `observe_raw` response and returns a
    /// borrowed complete semantic view. Compressed snapshot bodies are rejected.
    pub fn receive(self: *RawCache, connection: *client.Connection) Error!View {
        self.text_body.clearRetainingCapacity();
        var total_bytes: usize = 0;
        var begin_frame = try connection.receive();
        defer begin_frame.deinit();
        try accountFrame(&total_bytes, begin_frame.payload.len);
        if (begin_frame.kind != .snapshot_begin) return error.UnexpectedFrame;
        const begin = try protocol.decodeSnapshotBegin(begin_frame.payload);

        var next_graphics: ?Graphics = null;
        errdefer if (next_graphics) |*value| value.deinit(self.allocator);
        var raw_seen = false;
        while (true) {
            var frame = try connection.receive();
            defer frame.deinit();
            try accountFrame(&total_bytes, frame.payload.len);
            switch (frame.kind) {
                .snapshot_raw_data => {
                    if (next_graphics != null) return error.InvalidSnapshot;
                    raw_seen = true;
                    if (self.text_body.items.len + frame.payload.len > protocol.maximum_text_snapshot_bytes)
                        return error.SnapshotTooLarge;
                    try self.text_body.appendSlice(self.allocator, frame.payload);
                },
                .snapshot_data => return error.UnexpectedFrame,
                .snapshot_graphics => {
                    if (next_graphics != null) return error.InvalidSnapshot;
                    next_graphics = try decodeGraphics(self.allocator, begin, frame.payload);
                },
                .snapshot_end => {
                    if (!raw_seen or next_graphics == null) return error.InvalidSnapshot;
                    const end = try protocol.decodeSnapshotEnd(frame.payload);
                    if (end.revision != begin.revision) return error.InvalidSnapshot;
                    const result = try self.decodeRaw(begin, self.text_body.items, next_graphics.?);
                    next_graphics = null;
                    return result;
                },
                else => return error.UnexpectedFrame,
            }
        }
    }

    fn decodeRaw(
        self: *RawCache,
        begin: protocol.SnapshotBegin,
        encoded: []const u8,
        next_graphics: Graphics,
    ) Error!View {
        if (encoded.len == 0 or encoded.len > protocol.maximum_text_snapshot_bytes)
            return error.SnapshotTooLarge;
        try self.ensureGeometry(begin.rows, begin.columns);
        var cache_mutated = false;
        errdefer if (cache_mutated) self.invalidateRows();

        var referenced: [protocol.text_v1.maximum_hyperlinks + 1]bool = @splat(false);
        var resolved: [protocol.text_v1.maximum_hyperlinks + 1]bool = @splat(false);
        var presentation: Presentation = undefined;
        var presentation_seen = false;
        var row_count: u16 = 0;
        var phase: DecodePhase = .presentation;
        var links: std.ArrayList(Hyperlink) = .empty;
        errdefer {
            for (links.items) |link| self.allocator.free(link.uri_bytes);
            links.deinit(self.allocator);
        }

        var offset: usize = 0;
        while (offset < encoded.len) {
            if (encoded.len - offset < protocol.text_v1.record_header_bytes)
                return error.InvalidSnapshot;
            var encoded_header: [protocol.text_v1.record_header_bytes]u8 = undefined;
            @memcpy(&encoded_header, encoded[offset..][0..protocol.text_v1.record_header_bytes]);
            const header = try protocol.decodeTextRecordHeader(&encoded_header);
            const record_len = std.math.add(
                usize,
                protocol.text_v1.record_header_bytes,
                header.payload_len,
            ) catch return error.InvalidSnapshot;
            if (record_len > encoded.len - offset) return error.InvalidSnapshot;
            const record = encoded[offset..][0..record_len];
            const payload = record[protocol.text_v1.record_header_bytes..];
            switch (header.kind) {
                .presentation => {
                    if (phase != .presentation or presentation_seen) return error.InvalidSnapshot;
                    presentation = try decodePresentation(payload);
                    presentation_seen = true;
                    phase = .rows;
                },
                .row => {
                    if (phase != .rows or !presentation_seen or row_count >= begin.rows)
                        return error.InvalidSnapshot;
                    const row_index: usize = row_count;
                    const cached = self.row_records[row_index].encoded;
                    if (cached.len != 0 and std.mem.eql(u8, cached, record)) {
                        for (self.row_records[row_index].link_ids) |link_id| referenced[link_id] = true;
                    } else {
                        const replacement = try self.decodeCachedRow(begin, payload, record, &referenced);
                        errdefer replacement.deinit(self.allocator);
                        self.replaceRow(row_index, replacement);
                        cache_mutated = true;
                    }
                    row_count += 1;
                    if (row_count == begin.rows) phase = .hyperlinks;
                },
                .hyperlink => {
                    if (phase != .hyperlinks) return error.InvalidSnapshot;
                    try links.append(
                        self.allocator,
                        try decodeHyperlink(self.allocator, payload, &referenced, &resolved),
                    );
                },
            }
            offset += record_len;
        }
        if (!presentation_seen or row_count != begin.rows) return error.InvalidSnapshot;
        for (referenced[1..], resolved[1..]) |needed, seen| if (needed != seen)
            return error.InvalidSnapshot;

        const accepted_links = try links.toOwnedSlice(self.allocator);
        self.clearHyperlinks();
        self.hyperlinks = accepted_links;
        self.graphics.deinit(self.allocator);
        self.graphics = next_graphics;
        return .{
            .begin = begin,
            .presentation = presentation,
            .rows = self.rows,
            .hyperlinks = self.hyperlinks,
            .graphics = self.graphics,
        };
    }

    const RowReplacement = struct {
        row: Row,
        encoded: []u8,
        link_ids: []u16,

        fn deinit(self: RowReplacement, allocator: std.mem.Allocator) void {
            deinitRows(allocator, @as(*const [1]Row, &self.row));
            allocator.free(self.encoded);
            allocator.free(self.link_ids);
        }
    };

    fn decodeCachedRow(
        self: *RawCache,
        begin: protocol.SnapshotBegin,
        payload: []const u8,
        record: []const u8,
        referenced: *[protocol.text_v1.maximum_hyperlinks + 1]bool,
    ) Error!RowReplacement {
        const row = try decodeRow(self.allocator, begin, payload, referenced);
        errdefer deinitRows(self.allocator, @as(*const [1]Row, &row));
        var link_count: usize = 0;
        for (row.cells) |cell| {
            if (cell.link_id != 0) link_count += 1;
        }
        const link_ids = try self.allocator.alloc(u16, link_count);
        errdefer self.allocator.free(link_ids);
        var used: usize = 0;
        for (row.cells) |cell| {
            if (cell.link_id == 0) continue;
            link_ids[used] = @intCast(cell.link_id);
            used += 1;
        }
        const copied = try self.allocator.dupe(u8, record);
        return .{ .row = row, .encoded = copied, .link_ids = link_ids };
    }

    fn replaceRow(self: *RawCache, index: usize, replacement: RowReplacement) void {
        std.debug.assert(index < self.rows.len);
        if (self.row_records[index].encoded.len != 0) {
            deinitRows(self.allocator, self.rows[index .. index + 1]);
            self.allocator.free(self.row_records[index].encoded);
            self.allocator.free(self.row_records[index].link_ids);
        }
        self.rows[index] = replacement.row;
        self.row_records[index] = .{
            .encoded = replacement.encoded,
            .link_ids = replacement.link_ids,
        };
    }

    fn ensureGeometry(self: *RawCache, rows: u16, columns: u16) Error!void {
        if (rows == 0 or columns == 0) return error.InvalidSnapshot;
        if (self.rows.len == rows and self.columns == columns) return;
        self.clearRows();
        self.rows = try self.allocator.alloc(Row, rows);
        errdefer {
            self.allocator.free(self.rows);
            self.rows = &.{};
        }
        self.row_records = try self.allocator.alloc(CachedRowRecord, rows);
        errdefer {
            self.allocator.free(self.row_records);
            self.row_records = &.{};
        }
        for (self.row_records) |*record| record.* = .{};
        self.columns = columns;
    }

    fn invalidateRows(self: *RawCache) void {
        for (self.row_records, 0..) |*record, index| {
            if (record.encoded.len == 0) continue;
            deinitRows(self.allocator, self.rows[index .. index + 1]);
            self.allocator.free(record.encoded);
            self.allocator.free(record.link_ids);
            record.* = .{};
        }
    }

    fn clearRows(self: *RawCache) void {
        self.invalidateRows();
        if (self.row_records.len != 0) self.allocator.free(self.row_records);
        if (self.rows.len != 0) self.allocator.free(self.rows);
        self.rows = &.{};
        self.row_records = &.{};
        self.columns = 0;
    }

    fn clearHyperlinks(self: *RawCache) void {
        for (self.hyperlinks) |link| self.allocator.free(link.uri_bytes);
        if (self.hyperlinks.len != 0) self.allocator.free(self.hyperlinks);
        self.hyperlinks = &.{};
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

/// Sends one raw rich observation request. Framing v5 keeps this lane distinct
/// from ordinary compressed `observe`; text_v1 record bytes are unchanged.
pub fn sendRawRequest(
    connection: *client.Connection,
    after_revision: u64,
    history_offset: u32,
) client.Error!void {
    var payload: [protocol.payload_bytes.observe]u8 = undefined;
    protocol.encodeObserve(&payload, .{
        .after_revision = after_revision,
        .history_offset = history_offset,
    });
    try connection.send(.observe_raw, &payload);
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

/// Requests one raw text_v1 observation. Snapshot ownership is identical to
/// `request`; only the transport envelope skips DEFLATE.
pub fn requestRaw(
    connection: *client.Connection,
    allocator: std.mem.Allocator,
    after_revision: u64,
    history_offset: u32,
) Error!Snapshot {
    try sendRawRequest(connection, after_revision, history_offset);
    return receive(connection, allocator);
}

/// Receives one rich snapshot after the caller has sent `observe` or `observe_raw`.
pub fn receive(connection: *client.Connection, allocator: std.mem.Allocator) Error!Snapshot {
    return receiveFrom(connection, allocator);
}

/// Decodes exactly one complete framed snapshot without a socket or platform I/O.
/// The caller retains `bytes` for this call only; the returned snapshot owns its
/// allocations. Truncation and trailing frames are errors, not partial success.
/// Asynchronous hosts must bound and assemble a complete response before calling.
pub fn decodeFrames(allocator: std.mem.Allocator, bytes: []const u8) Error!Snapshot {
    if (bytes.len > protocol.maximum_observation_bytes) return error.SnapshotTooLarge;
    var reader = BufferedFrames{ .bytes = bytes };
    var snapshot = try receiveFrom(&reader, allocator);
    errdefer snapshot.deinit();
    if (reader.offset != bytes.len) return error.InvalidSnapshot;
    return snapshot;
}

const BufferedFrames = struct {
    bytes: []const u8,
    offset: usize = 0,

    const Frame = struct {
        kind: protocol.Kind,
        payload: []const u8,

        fn deinit(self: *Frame) void {
            // A borrowed view, not an allocation; invalidate only this handle.
            self.* = undefined;
        }
    };

    fn receive(self: *BufferedFrames) Error!Frame {
        const remaining = self.bytes[self.offset..];
        if (remaining.len < protocol.header_bytes) return error.InvalidSnapshot;
        const header = try protocol.decodeHeader(remaining[0..protocol.header_bytes]);
        if (header.payload_len > remaining.len - protocol.header_bytes)
            return error.InvalidSnapshot;
        self.offset += protocol.header_bytes + header.payload_len;
        return .{
            .kind = header.kind,
            .payload = remaining[protocol.header_bytes..][0..header.payload_len],
        };
    }
};

// One decoder body, specialized only for owned socket frames or borrowed bytes.
fn receiveFrom(connection: anytype, allocator: std.mem.Allocator) Error!Snapshot {
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
    var text_body: std.ArrayList(u8) = .empty;
    defer text_body.deinit(allocator);
    const BodyEncoding = enum { none, compressed, raw };
    var body_encoding: BodyEncoding = .none;
    var graphics: ?Graphics = null;
    errdefer if (graphics) |*value| value.deinit(allocator);

    while (true) {
        var frame = try connection.receive();
        defer frame.deinit();
        try accountFrame(&total_bytes, frame.payload.len);
        switch (frame.kind) {
            .snapshot_data, .snapshot_raw_data => {
                if (graphics != null) return error.InvalidSnapshot;
                const encoding: BodyEncoding = if (frame.kind == .snapshot_data)
                    .compressed
                else
                    .raw;
                if (body_encoding != .none and body_encoding != encoding)
                    return error.InvalidSnapshot;
                body_encoding = encoding;
                if (text_body.items.len + frame.payload.len > protocol.maximum_text_snapshot_bytes)
                    return error.SnapshotTooLarge;
                try text_body.appendSlice(allocator, frame.payload);
            },
            .snapshot_graphics => {
                if (graphics != null) return error.InvalidSnapshot;
                graphics = try decodeGraphics(allocator, begin, frame.payload);
            },
            .snapshot_end => {
                if (graphics == null) return error.InvalidSnapshot;
                const end = try protocol.decodeSnapshotEnd(frame.payload);
                if (end.revision != begin.revision) return error.InvalidSnapshot;
                switch (body_encoding) {
                    .compressed => try decodeTextBody(
                        allocator,
                        begin,
                        text_body.items,
                        rows,
                        &initialized_rows,
                        &hyperlinks,
                        &referenced,
                        &resolved,
                        &presentation,
                        &presentation_seen,
                        &row_count,
                        &phase,
                    ),
                    .raw => try decodeRawTextBody(
                        allocator,
                        begin,
                        text_body.items,
                        rows,
                        &initialized_rows,
                        &hyperlinks,
                        &referenced,
                        &resolved,
                        &presentation,
                        &presentation_seen,
                        &row_count,
                        &phase,
                    ),
                    .none => return error.InvalidSnapshot,
                }
                if (!presentation_seen or row_count != begin.rows) return error.InvalidSnapshot;
                for (referenced[1..], resolved[1..]) |needed, seen| if (needed != seen)
                    return error.InvalidSnapshot;
                return .{
                    .allocator = allocator,
                    .begin = begin,
                    .presentation = presentation,
                    .rows = rows,
                    .hyperlinks = try hyperlinks.toOwnedSlice(allocator),
                    .graphics = graphics.?,
                };
            },
            else => return error.UnexpectedFrame,
        }
    }
}

fn decodeGraphics(
    allocator: std.mem.Allocator,
    begin: protocol.SnapshotBegin,
    payload: []const u8,
) Error!Graphics {
    if (payload.len < protocol.graphics_v2.manifest_header_bytes) return error.InvalidSnapshot;
    const header = protocol.decodeSnapshotGraphicsHeader(
        payload[0..protocol.graphics_v2.manifest_header_bytes],
    ) catch return error.InvalidSnapshot;
    const image_bytes = std.math.mul(
        usize,
        header.image_count,
        protocol.graphics_v2.image_bytes,
    ) catch return error.InvalidSnapshot;
    const placement_bytes = std.math.mul(
        usize,
        header.placement_count,
        protocol.graphics_v2.placement_bytes,
    ) catch return error.InvalidSnapshot;
    const expected = std.math.add(
        usize,
        protocol.graphics_v2.manifest_header_bytes + image_bytes,
        placement_bytes,
    ) catch return error.InvalidSnapshot;
    if (payload.len != expected) return error.InvalidSnapshot;

    const images = try allocator.alloc(protocol.SnapshotImage, header.image_count);
    errdefer allocator.free(images);
    const placements = try allocator.alloc(protocol.SnapshotImagePlacement, header.placement_count);
    errdefer allocator.free(placements);

    var offset: usize = protocol.graphics_v2.manifest_header_bytes;
    for (images, 0..) |*image, index| {
        image.* = protocol.decodeSnapshotImage(
            payload[offset..][0..protocol.graphics_v2.image_bytes],
        ) catch return error.InvalidSnapshot;
        for (images[0..index]) |prior| if (prior.image_id == image.image_id)
            return error.InvalidSnapshot;
        offset += protocol.graphics_v2.image_bytes;
    }

    var referenced = try allocator.alloc(bool, images.len);
    defer allocator.free(referenced);
    @memset(referenced, false);
    for (placements) |*placement| {
        placement.* = protocol.decodeSnapshotImagePlacement(
            payload[offset..][0..protocol.graphics_v2.placement_bytes],
        ) catch return error.InvalidSnapshot;
        if (placement.row >= begin.rows or placement.column >= begin.columns)
            return error.InvalidSnapshot;
        const image_index = graphicsImageIndex(images, placement.image_id) orelse
            return error.InvalidSnapshot;
        const image = images[image_index];
        if (placement.source_x > image.width or placement.source_y > image.height or
            placement.source_width > image.width - placement.source_x or
            placement.source_height > image.height - placement.source_y)
            return error.InvalidSnapshot;
        referenced[image_index] = true;
        offset += protocol.graphics_v2.placement_bytes;
    }
    for (referenced) |used| if (!used) return error.InvalidSnapshot;
    if (offset != payload.len) return error.InvalidSnapshot;
    return .{
        .generation = header.generation,
        .content_generation = header.content_generation,
        .cell_pixel_width = header.cell_pixel_width,
        .cell_pixel_height = header.cell_pixel_height,
        .images = images,
        .placements = placements,
    };
}

fn graphicsImageIndex(images: []const protocol.SnapshotImage, image_id: u32) ?usize {
    for (images, 0..) |image, index| if (image.image_id == image_id) return index;
    return null;
}

test "rich graphics owns visible image identities and placements" {
    const begin = protocol.SnapshotBegin{
        .revision = 5,
        .terminal_revision = 6,
        .history_offset = 0,
        .history_count = 0,
        .history_row_base = 0,
        .rows = 2,
        .columns = 3,
        .cursor_row = 0,
        .cursor_column = 0,
        .cursor_shape = 0,
        .cursor_visible = true,
        .cursor_blink = false,
        .alternate_screen = false,
        .stream_closed = false,
        .child_exited = false,
        .leader_present = false,
        .you_are_leader = false,
    };
    var payload: [
        protocol.graphics_v2.manifest_header_bytes +
            protocol.graphics_v2.image_bytes + protocol.graphics_v2.placement_bytes
    ]u8 = undefined;
    var header: [protocol.graphics_v2.manifest_header_bytes]u8 = undefined;
    protocol.encodeSnapshotGraphicsHeader(&header, .{
        .generation = 11,
        .content_generation = 10,
        .cell_pixel_width = 10,
        .cell_pixel_height = 20,
        .image_count = 1,
        .placement_count = 1,
    });
    @memcpy(payload[0..header.len], &header);
    var offset: usize = header.len;
    var image: [protocol.graphics_v2.image_bytes]u8 = undefined;
    protocol.encodeSnapshotImage(&image, .{
        .image_id = 7,
        .generation = 9,
        .width = 4,
        .height = 3,
    });
    @memcpy(payload[offset..][0..image.len], &image);
    offset += image.len;
    var placement: [protocol.graphics_v2.placement_bytes]u8 = undefined;
    protocol.encodeSnapshotImagePlacement(&placement, .{
        .image_id = 7,
        .generation = 12,
        .row = 1,
        .column = 2,
        .source_x = 1,
        .source_y = 1,
        .source_width = 3,
        .source_height = 2,
        .cell_x = 2,
        .cell_y = 3,
        .pixel_width = 30,
        .pixel_height = 20,
        .z = -4,
    });
    @memcpy(payload[offset..][0..placement.len], &placement);

    var graphics = try decodeGraphics(std.testing.allocator, begin, &payload);
    defer graphics.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u64, 11), graphics.generation);
    try std.testing.expectEqual(@as(u64, 10), graphics.content_generation);
    try std.testing.expectEqual(@as(usize, 1), graphics.images.len);
    try std.testing.expectEqual(@as(u32, 7), graphics.images[0].image_id);
    try std.testing.expectEqual(@as(u64, 9), graphics.images[0].generation);
    try std.testing.expectEqual(@as(usize, 1), graphics.placements.len);
    try std.testing.expectEqual(@as(u16, 1), graphics.placements[0].row);
    try std.testing.expectEqual(@as(u16, 2), graphics.placements[0].column);
    try std.testing.expectEqual(@as(i32, -4), graphics.placements[0].z);

    var bad = payload;
    // A source crop extending beyond the advertised image must fail closed.
    bad[protocol.graphics_v2.manifest_header_bytes + protocol.graphics_v2.image_bytes + 27] = 4;
    try std.testing.expectError(
        error.InvalidSnapshot,
        decodeGraphics(std.testing.allocator, begin, &bad),
    );
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
    if (uncompressed_len == 0 or uncompressed_len > protocol.maximum_text_snapshot_bytes)
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
    return decodeTextRecords(
        allocator,
        begin,
        decoded,
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
}

fn decodeRawTextBody(
    allocator: std.mem.Allocator,
    begin: protocol.SnapshotBegin,
    decoded: []const u8,
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
    if (decoded.len == 0 or decoded.len > protocol.maximum_text_snapshot_bytes)
        return error.SnapshotTooLarge;
    return decodeTextRecords(
        allocator,
        begin,
        decoded,
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
}

fn decodeTextRecords(
    allocator: std.mem.Allocator,
    begin: protocol.SnapshotBegin,
    decoded: []const u8,
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
    const fixed_cells_bytes = std.math.mul(
        usize,
        begin.columns,
        protocol.text_v1.cell_header_bytes,
    ) catch return error.InvalidSnapshot;
    const fixed_payload_bytes = std.math.add(
        usize,
        protocol.text_v1.row_header_bytes,
        fixed_cells_bytes,
    ) catch return error.InvalidSnapshot;
    if (payload.len < fixed_payload_bytes) return error.InvalidSnapshot;
    const scalar_bytes_total = payload.len - fixed_payload_bytes;
    if (scalar_bytes_total % @sizeOf(u32) != 0) return error.InvalidSnapshot;
    const scalar_count_total = scalar_bytes_total / @sizeOf(u32);
    const scalar_storage = try allocator.alloc(u32, scalar_count_total);
    errdefer allocator.free(scalar_storage);
    var scalar_used: usize = 0;

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
        if (scalar_count > scalar_storage.len - scalar_used) return error.InvalidSnapshot;
        const scalars = scalar_storage[scalar_used .. scalar_used + scalar_count];
        for (scalars, 0..) |*value, index| {
            value.* = readU32(payload[offset + index * 4 ..][0..4]);
            if (value.* > 0x10ffff or value.* >= 0xd800 and value.* <= 0xdfff)
                return error.InvalidSnapshot;
        }
        scalar_used += scalar_count;
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
        offset += scalar_bytes;
    }
    if (offset != payload.len or scalar_used != scalar_storage.len) return error.InvalidSnapshot;
    return .{
        .wrapped = payload[0] == 1,
        .line_geometry = payload[1],
        .cells = cells,
        .scalar_storage = scalar_storage,
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
    if (total.* > protocol.maximum_observation_bytes) return error.SnapshotTooLarge;
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

fn deinitRows(allocator: std.mem.Allocator, rows: []const Row) void {
    for (rows) |row| {
        if (row.scalar_storage.len != 0) {
            allocator.free(row.scalar_storage);
        } else {
            for (row.cells) |cell| if (cell.scalars.len != 0) allocator.free(cell.scalars);
        }
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
    defer deinitRows(std.testing.allocator, &.{row});
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
    encodeU32(oversized[0..protocol.text_v1.compressed_header_bytes], protocol.maximum_text_snapshot_bytes + 1);
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

fn testFramedSnapshot(allocator: std.mem.Allocator, raw: bool) ![]u8 {
    const begin: protocol.SnapshotBegin = .{
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
        .cursor_blink = false,
        .alternate_screen = false,
        .stream_closed = false,
        .child_exited = false,
        .leader_present = false,
        .you_are_leader = false,
    };
    var body: [protocol.text_v1.record_header_bytes + protocol.text_v1.presentation_bytes]u8 = @splat(0);
    protocol.encodeTextRecordHeader(body[0..protocol.text_v1.record_header_bytes], .{
        .kind = .presentation,
        .payload_len = protocol.text_v1.presentation_bytes,
    });
    const compressed = if (raw) &.{} else try testDeflateBody(allocator, &body);
    defer if (!raw) allocator.free(compressed);
    const text_bytes: []const u8 = if (raw) &body else compressed;
    const graphics_bytes = protocol.graphics_v2.manifest_header_bytes;
    const length = 4 * protocol.header_bytes + protocol.payload_bytes.snapshot_begin +
        text_bytes.len + graphics_bytes + protocol.payload_bytes.snapshot_end;
    const frames = try allocator.alloc(u8, length);
    errdefer allocator.free(frames);
    var at: usize = 0;
    try protocol.encodeHeader(frames[at..][0..protocol.header_bytes], .{
        .kind = .snapshot_begin,
        .payload_len = protocol.payload_bytes.snapshot_begin,
    });
    at += protocol.header_bytes;
    protocol.encodeSnapshotBegin(frames[at..][0..protocol.payload_bytes.snapshot_begin], begin);
    at += protocol.payload_bytes.snapshot_begin;
    try protocol.encodeHeader(frames[at..][0..protocol.header_bytes], .{
        .kind = if (raw) .snapshot_raw_data else .snapshot_data,
        .payload_len = @intCast(text_bytes.len),
    });
    at += protocol.header_bytes;
    @memcpy(frames[at..][0..text_bytes.len], text_bytes);
    at += text_bytes.len;
    try protocol.encodeHeader(frames[at..][0..protocol.header_bytes], .{
        .kind = .snapshot_graphics,
        .payload_len = graphics_bytes,
    });
    at += protocol.header_bytes;
    var graphics_header: [protocol.graphics_v2.manifest_header_bytes]u8 = undefined;
    protocol.encodeSnapshotGraphicsHeader(&graphics_header, .{
        .generation = 0,
        .content_generation = 0,
        .cell_pixel_width = 10,
        .cell_pixel_height = 20,
        .image_count = 0,
        .placement_count = 0,
    });
    @memcpy(frames[at..][0..graphics_header.len], &graphics_header);
    at += graphics_header.len;
    try protocol.encodeHeader(frames[at..][0..protocol.header_bytes], .{
        .kind = .snapshot_end,
        .payload_len = protocol.payload_bytes.snapshot_end,
    });
    at += protocol.header_bytes;
    protocol.encodeSnapshotEnd(frames[at..][0..protocol.payload_bytes.snapshot_end], .{ .revision = begin.revision });
    return frames;
}

fn testDecodeOwned(allocator: std.mem.Allocator, bytes: []const u8) !void {
    var snapshot = try decodeFrames(allocator, bytes);
    defer snapshot.deinit();
    try std.testing.expectEqual(@as(u64, 3), snapshot.begin.revision);
    try std.testing.expectEqual(@as(u64, 9), snapshot.begin.terminal_revision);
    try std.testing.expectEqual(@as(usize, 0), snapshot.rows.len);
    try std.testing.expectEqual(@as(usize, 0), snapshot.graphics.images.len);
    try std.testing.expectEqual(@as(usize, 0), snapshot.graphics.placements.len);
}

test "buffered frames share decoder and clean up at every allocation failure" {
    const frames = try testFramedSnapshot(std.testing.allocator, false);
    defer std.testing.allocator.free(frames);
    try testDecodeOwned(std.testing.allocator, frames);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, testDecodeOwned, .{frames});
}

test "buffered frames decode raw text_v1 snapshot lane" {
    const frames = try testFramedSnapshot(std.testing.allocator, true);
    defer std.testing.allocator.free(frames);
    try testDecodeOwned(std.testing.allocator, frames);
}

test "buffered frames reject truncation trailing data and mismatched revision" {
    const frames = try testFramedSnapshot(std.testing.allocator, false);
    defer std.testing.allocator.free(frames);
    for (0..frames.len) |length| {
        try std.testing.expectError(error.InvalidSnapshot, decodeFrames(std.testing.allocator, frames[0..length]));
    }
    const trailing = try std.testing.allocator.alloc(u8, frames.len + 1);
    defer std.testing.allocator.free(trailing);
    @memcpy(trailing[0..frames.len], frames);
    trailing[frames.len] = 0;
    try std.testing.expectError(error.InvalidSnapshot, decodeFrames(std.testing.allocator, trailing));
    frames[frames.len - 1] ^= 1;
    try std.testing.expectError(error.InvalidSnapshot, decodeFrames(std.testing.allocator, frames));
    frames[frames.len - 1] ^= 1;
    frames[0] = 0;
    try std.testing.expectError(error.InvalidMagic, decodeFrames(std.testing.allocator, frames));
}

test "raw cache reuses byte-identical decoded rows" {
    const allocator = std.testing.allocator;
    var cache = RawCache.init(allocator);
    defer cache.deinit();

    const begin = protocol.SnapshotBegin{
        .revision = 1,
        .terminal_revision = 1,
        .history_offset = 0,
        .history_count = 0,
        .history_row_base = 0,
        .rows = 2,
        .columns = 1,
        .cursor_row = 0,
        .cursor_column = 0,
        .cursor_shape = 0,
        .cursor_visible = true,
        .cursor_blink = false,
        .alternate_screen = false,
        .stream_closed = false,
        .child_exited = false,
        .leader_present = false,
        .you_are_leader = false,
    };
    const first_body = try testRawCacheBody(allocator, 'A', 'Z');
    defer allocator.free(first_body);
    const first = try cache.decodeRaw(begin, first_body, .{});
    try std.testing.expectEqual(@as(u32, 'A'), first.rows[0].cells[0].scalars[0]);
    const first_row_cells = first.rows[0].cells.ptr;
    const second_row_cells = first.rows[1].cells.ptr;

    var second_begin = begin;
    second_begin.revision = 2;
    second_begin.terminal_revision = 2;
    const second = try cache.decodeRaw(second_begin, first_body, .{});
    try std.testing.expectEqual(first_row_cells, second.rows[0].cells.ptr);
    try std.testing.expectEqual(second_row_cells, second.rows[1].cells.ptr);

    const changed_body = try testRawCacheBody(allocator, 'B', 'Z');
    defer allocator.free(changed_body);
    var third_begin = begin;
    third_begin.revision = 3;
    third_begin.terminal_revision = 3;
    const third = try cache.decodeRaw(third_begin, changed_body, .{});
    try std.testing.expectEqual(@as(u32, 'B'), third.rows[0].cells[0].scalars[0]);
    try std.testing.expectEqual(second_row_cells, third.rows[1].cells.ptr);
}

fn testRawCacheBody(allocator: std.mem.Allocator, first: u32, second: u32) ![]u8 {
    const presentation_record = protocol.text_v1.record_header_bytes + protocol.text_v1.presentation_bytes;
    const row_payload = protocol.text_v1.row_header_bytes + protocol.text_v1.cell_header_bytes + @sizeOf(u32);
    const row_record = protocol.text_v1.record_header_bytes + row_payload;
    const body = try allocator.alloc(u8, presentation_record + 2 * row_record);
    @memset(body, 0);

    protocol.encodeTextRecordHeader(body[0..protocol.text_v1.record_header_bytes], .{
        .kind = .presentation,
        .payload_len = protocol.text_v1.presentation_bytes,
    });
    var at = presentation_record;
    for ([_]u32{ first, second }) |scalar| {
        protocol.encodeTextRecordHeader(body[at..][0..protocol.text_v1.record_header_bytes], .{
            .kind = .row,
            .payload_len = row_payload,
        });
        at += protocol.text_v1.record_header_bytes;
        const row = body[at..][0..row_payload];
        encodeU16(row[2..4], 1);
        const cell = row[protocol.text_v1.row_header_bytes..][0..protocol.text_v1.cell_header_bytes];
        cell[0] = 1;
        cell[1] = 1;
        cell[2] = 1;
        var color: [protocol.text_v1.color_bytes]u8 = undefined;
        try protocol.encodeTextColor(&color, .{ .kind = .default, .value = 0 });
        @memcpy(cell[16..21], &color);
        @memcpy(cell[21..26], &color);
        @memcpy(cell[26..31], &color);
        encodeU32(row[row_payload - 4 ..], scalar);
        at += row_payload;
    }
    std.debug.assert(at == body.len);
    return body;
}
