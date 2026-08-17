//! Bounded client for the shared Howl session protocol.

const std = @import("std");
const linux = std.os.linux;
const posix = std.posix;
const protocol = @import("howl_session").protocol;

pub const maximum_rows: u16 = 128;
pub const maximum_columns: u16 = 256;
pub const maximum_cells: usize = @as(usize, maximum_rows) * maximum_columns;
pub const maximum_input_bytes: usize = 4096;

const legacy_features = protocol.feature(.grid_snapshot) |
    protocol.feature(.resize_leader) |
    protocol.feature(.history_window);

pub const Cell = struct {
    codepoint: u32,
    width: u8,
    height: u8,
    x: u8,
    y: u8,
};

pub const Snapshot = struct {
    allocator: std.mem.Allocator,
    revision: u64,
    terminal_revision: u64,
    rows: u16,
    columns: u16,
    cursor_row: u16,
    cursor_column: u16,
    cursor_visible: bool,
    stream_closed: bool,
    child_exited: bool,
    cells: []Cell,

    pub fn deinit(self: *Snapshot) void {
        self.allocator.free(self.cells);
        self.* = undefined;
    }

    pub fn cell(self: *const Snapshot, row: u16, column: u16) Cell {
        std.debug.assert(row < self.rows and column < self.columns);
        return self.cells[@as(usize, row) * self.columns + column];
    }
};

const Frame = struct {
    allocator: std.mem.Allocator,
    kind: protocol.Kind,
    payload: []u8,

    fn deinit(self: *Frame) void {
        self.allocator.free(self.payload);
        self.* = undefined;
    }
};

pub const Connection = struct {
    allocator: std.mem.Allocator,
    fd: posix.fd_t,
    client_id: protocol.ClientId,
    features: u64,

    pub fn connect(allocator: std.mem.Allocator, socket_path: []const u8) !Connection {
        const fd = try connectUnix(socket_path);
        errdefer closeFd(fd);

        var hello: [protocol.payload_bytes.hello]u8 = undefined;
        protocol.encodeHello(&hello, .{ .features = legacy_features });
        try writeFrame(fd, .hello, &hello);
        var welcome_frame = try readFrame(allocator, fd);
        defer welcome_frame.deinit();
        if (welcome_frame.kind != .welcome) return error.UnexpectedFrame;
        const welcome = try protocol.decodeWelcome(welcome_frame.payload);
        if (welcome.version != protocol.protocol_max_version or
            welcome.features & protocol.feature(.grid_snapshot) == 0)
            return error.IncompatibleEndpoint;
        return .{
            .allocator = allocator,
            .fd = fd,
            .client_id = welcome.client_id,
            .features = welcome.features,
        };
    }

    pub fn deinit(self: *Connection) void {
        if (self.fd >= 0) closeFd(self.fd);
        self.* = undefined;
    }

    /// Wakes one thread blocked in an observation read so the owner can join it.
    /// The caller must not reuse the connection after this shutdown.
    pub fn interrupt(self: *const Connection) void {
        if (self.fd < 0) return;
        const result = linux.shutdown(self.fd, linux.SHUT.RDWR);
        const err = linux.errno(result);
        std.debug.assert(err == .SUCCESS or err == .NOTCONN or err == .INTR);
    }

    /// Requests one coherent snapshot after the last accepted endpoint revision.
    /// Revision zero forces an immediate current snapshot.
    pub fn observe(self: *Connection, after_revision: u64) !Snapshot {
        var request: [protocol.payload_bytes.observe]u8 = undefined;
        protocol.encodeObserve(&request, .{ .after_revision = after_revision });
        try writeFrame(self.fd, .observe, &request);

        var begin_frame = try readFrame(self.allocator, self.fd);
        defer begin_frame.deinit();
        if (begin_frame.kind != .snapshot_begin) return error.UnexpectedFrame;
        const begin = try protocol.decodeSnapshotBegin(begin_frame.payload);
        try validateDimensions(begin.rows, begin.columns);
        const cell_count = try std.math.mul(usize, begin.rows, begin.columns);
        const cells = try self.allocator.alloc(Cell, cell_count);
        errdefer self.allocator.free(cells);

        var row_count: u16 = 0;
        while (true) {
            var frame = try readFrame(self.allocator, self.fd);
            defer frame.deinit();
            switch (frame.kind) {
                .snapshot_data => try appendSnapshotData(begin, frame.payload, cells, &row_count),
                .snapshot_end => {
                    const end = try protocol.decodeSnapshotEnd(frame.payload);
                    if (end.revision != begin.revision or row_count != begin.rows)
                        return error.MalformedSnapshot;
                    return .{
                        .allocator = self.allocator,
                        .revision = begin.revision,
                        .terminal_revision = begin.terminal_revision,
                        .rows = begin.rows,
                        .columns = begin.columns,
                        .cursor_row = begin.cursor_row,
                        .cursor_column = begin.cursor_column,
                        .cursor_visible = begin.cursor_visible,
                        .stream_closed = begin.stream_closed,
                        .child_exited = begin.child_exited,
                        .cells = cells,
                    };
                },
                else => return error.UnexpectedFrame,
            }
        }
    }

    /// Sends one bounded byte-input event on a control-only connection.
    pub fn input(self: *Connection, bytes: []const u8) !void {
        if (bytes.len == 0 or bytes.len > maximum_input_bytes) return error.InputBounds;
        var payload: [maximum_input_bytes + 1]u8 = undefined;
        payload[0] = @backingInt(protocol.InputKind.bytes);
        @memcpy(payload[1 .. bytes.len + 1], bytes);
        try writeFrame(self.fd, .input, payload[0 .. bytes.len + 1]);
        var result_frame = try readFrame(self.allocator, self.fd);
        defer result_frame.deinit();
        if (result_frame.kind != .result) return error.UnexpectedFrame;
        const result = try protocol.decodeResult(result_frame.payload);
        if (result.request_kind != .input or result.code != .ok) return error.InputRejected;
    }
};

fn validateDimensions(rows: u16, columns: u16) !void {
    if (rows == 0 or columns == 0 or rows > maximum_rows or columns > maximum_columns)
        return error.SnapshotDimensions;
    const count = std.math.mul(usize, rows, columns) catch return error.SnapshotDimensions;
    if (count > maximum_cells) return error.SnapshotDimensions;
}

fn appendSnapshotData(
    begin: protocol.SnapshotBegin,
    payload: []const u8,
    cells: []Cell,
    row_count: *u16,
) !void {
    const row_bytes = 4 + @as(usize, begin.columns) * 8;
    if (row_bytes == 0 or payload.len == 0 or payload.len % row_bytes != 0)
        return error.MalformedSnapshot;
    var offset: usize = 0;
    while (offset < payload.len) : (offset += row_bytes) {
        if (row_count.* >= begin.rows) return error.MalformedSnapshot;
        if (payload[offset] > 1 or readU16(payload[offset + 2 .. offset + 4]) != begin.columns)
            return error.MalformedSnapshot;
        var cell_offset = offset + 4;
        var column: u16 = 0;
        while (column < begin.columns) : (column += 1) {
            const destination = @as(usize, row_count.*) * begin.columns + column;
            cells[destination] = .{
                .codepoint = readU32(payload[cell_offset .. cell_offset + 4]),
                .width = payload[cell_offset + 4],
                .height = payload[cell_offset + 5],
                .x = payload[cell_offset + 6],
                .y = payload[cell_offset + 7],
            };
            cell_offset += 8;
        }
        row_count.* += 1;
    }
}

fn connectUnix(path: []const u8) !posix.fd_t {
    var address: linux.sockaddr.un = undefined;
    if (path.len == 0 or path.len >= address.path.len) return error.SocketPath;
    address.family = linux.AF.UNIX;
    @memset(&address.path, 0);
    @memcpy(address.path[0..path.len], path);
    const length: linux.socklen_t = @intCast(@offsetOf(linux.sockaddr.un, "path") + path.len + 1);
    const raw = linux.socket(linux.AF.UNIX, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, 0);
    if (linux.errno(raw) != .SUCCESS) return error.SocketCreate;
    const fd: posix.fd_t = @intCast(raw);
    errdefer closeFd(fd);
    while (true) {
        const result = linux.connect(fd, @ptrCast(&address), length);
        switch (linux.errno(result)) {
            .SUCCESS => return fd,
            .INTR => continue,
            else => return error.SocketConnect,
        }
    }
}

fn writeFrame(fd: posix.fd_t, kind: protocol.Kind, payload: []const u8) !void {
    if (payload.len > protocol.maximum_payload_bytes) return error.PayloadTooLarge;
    var header: [protocol.header_bytes]u8 = undefined;
    try protocol.encodeHeader(&header, .{ .kind = kind, .payload_len = @intCast(payload.len) });
    try writeAll(fd, &header);
    try writeAll(fd, payload);
}

fn readFrame(allocator: std.mem.Allocator, fd: posix.fd_t) !Frame {
    var header_bytes: [protocol.header_bytes]u8 = undefined;
    try readAll(fd, &header_bytes);
    const header = try protocol.decodeHeader(&header_bytes);
    const payload = try allocator.alloc(u8, header.payload_len);
    errdefer allocator.free(payload);
    try readAll(fd, payload);
    return .{ .allocator = allocator, .kind = header.kind, .payload = payload };
}

fn writeAll(fd: posix.fd_t, bytes: []const u8) !void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        const written = linux.write(fd, bytes[offset..].ptr, bytes.len - offset);
        switch (linux.errno(written)) {
            .SUCCESS => {
                if (written == 0 or written > bytes.len - offset) return error.SocketWrite;
                offset += written;
            },
            .INTR => continue,
            else => return error.SocketWrite,
        }
    }
}

fn readAll(fd: posix.fd_t, bytes: []u8) !void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        const count = linux.read(fd, bytes[offset..].ptr, bytes.len - offset);
        switch (linux.errno(count)) {
            .SUCCESS => {
                if (count == 0 or count > bytes.len - offset) return error.SocketRead;
                offset += count;
            },
            .INTR => continue,
            else => return error.SocketRead,
        }
    }
}

fn closeFd(fd: posix.fd_t) void {
    const result = linux.close(fd);
    const err = linux.errno(result);
    std.debug.assert(err == .SUCCESS or err == .INTR);
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

test "snapshot dimensions are explicitly bounded" {
    try validateDimensions(maximum_rows, maximum_columns);
    try std.testing.expectError(error.SnapshotDimensions, validateDimensions(0, 80));
    try std.testing.expectError(error.SnapshotDimensions, validateDimensions(24, 0));
    try std.testing.expectError(error.SnapshotDimensions, validateDimensions(maximum_rows + 1, 80));
    try std.testing.expectError(error.SnapshotDimensions, validateDimensions(24, maximum_columns + 1));
}

test "byte input is explicitly bounded before transport" {
    var connection = Connection{
        .allocator = std.testing.allocator,
        .fd = -1,
        .client_id = 1,
        .features = 0,
    };
    var oversized: [maximum_input_bytes + 1]u8 = undefined;
    try std.testing.expectError(error.InputBounds, connection.input(""));
    try std.testing.expectError(error.InputBounds, connection.input(&oversized));
}

test "snapshot row parser preserves cell occupancy" {
    const begin = protocol.SnapshotBegin{
        .revision = 1,
        .terminal_revision = 2,
        .history_offset = 0,
        .history_count = 0,
        .history_row_base = 0,
        .rows = 1,
        .columns = 2,
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
    const payload = [_]u8{
        0, 0, 0, 2,
        0, 0, 0, 'A',
        1, 1, 0, 0,
        0, 0, 0, 0,
        2, 1, 1, 0,
    };
    var cells: [2]Cell = undefined;
    var rows: u16 = 0;
    try appendSnapshotData(begin, &payload, &cells, &rows);
    try std.testing.expectEqual(@as(u16, 1), rows);
    try std.testing.expectEqual(@as(u32, 'A'), cells[0].codepoint);
    try std.testing.expectEqual(@as(u8, 2), cells[1].width);
    try std.testing.expectEqual(@as(u8, 1), cells[1].x);
}
