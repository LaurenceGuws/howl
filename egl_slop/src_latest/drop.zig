//! Owns bounded Kitty OSC 72 application intent and offered MIME identity.

const std = @import("std");
const control = @import("howl_control");

/// Bounds MIME names retained from one Wayland offer.
pub const max_mimes: usize = 64;
/// Bounds aggregate MIME bytes retained from one Wayland offer.
pub const max_mime_bytes: usize = 8 * 1024;
/// Bounds one chunked application MIME preference list.
pub const max_application_bytes: usize = 32 * 1024;

/// Retains one ordered list of opaque MIME names without allocation.
pub const MimeList = struct {
    bytes: [max_mime_bytes]u8 = @splat(0),
    offsets: [max_mimes + 1]u16 = @splat(0),
    count: u8 = 0,
    len: u16 = 0,

    /// Appends one nonempty MIME exactly or rejects without mutation.
    pub fn append(self: *MimeList, mime: []const u8) error{MimeLimit}!void {
        if (mime.len == 0 or mime.len > std.math.maxInt(u16)) return error.MimeLimit;
        for (mime) |byte| if (byte < 0x21 or byte > 0x7e) return error.MimeLimit;
        if (self.count == max_mimes or self.len + mime.len > self.bytes.len or
            @as(usize, self.len) + mime.len + self.count > control.drag_drop_payload_max_bytes)
            return error.MimeLimit;
        const start = self.len;
        @memcpy(self.bytes[start..][0..mime.len], mime);
        self.len += @intCast(mime.len);
        self.count += 1;
        self.offsets[self.count] = self.len;
    }

    /// Borrows one one-based MIME identity.
    pub fn at(self: *const MimeList, index: u32) ?[]const u8 {
        if (index == 0 or index > self.count) return null;
        const slot: usize = @intCast(index - 1);
        return self.bytes[self.offsets[slot]..self.offsets[slot + 1]];
    }

    /// Returns the one-based identity of an exact offered MIME.
    pub fn find(self: *const MimeList, mime: []const u8) ?u32 {
        var index: u32 = 1;
        while (index <= self.count) : (index += 1)
            if (std.mem.eql(u8, self.at(index).?, mime)) return index;
        return null;
    }

    /// Writes the space-separated protocol payload into caller storage.
    pub fn format(self: *const MimeList, output: []u8) error{MimeLimit}![]const u8 {
        const required = @as(usize, self.len) + if (self.count == 0) 0 else self.count - 1;
        if (output.len < required) return error.MimeLimit;
        var used: usize = 0;
        var index: u32 = 1;
        while (index <= self.count) : (index += 1) {
            if (used != 0) {
                output[used] = ' ';
                used += 1;
            }
            const mime = self.at(index).?;
            @memcpy(output[used..][0..mime.len], mime);
            used += mime.len;
        }
        return output[0..used];
    }
};

/// Selects one complete application command after bounded chunk assembly.
pub const Action = union(enum) {
    enable: struct { client_id: ?u32, mimes: []const u8 },
    disable,
    accept: struct { client_id: ?u32, operation: u2, mimes: []const u8 },
    request: struct { client_id: ?u32, index: u32 },
    complete: struct { client_id: ?u32, operation: u2 },
    query: struct { client_id: ?u32 },
    reject: struct { client_id: ?u32, index: ?u32, remote: bool, command: u8 },
};

const ChunkKind = enum { enable, accept };

/// Retains only application registration and one bounded chunk chain.
pub const State = struct {
    enabled: bool = false,
    client_id: ?u32 = null,
    chunk_kind: ?ChunkKind = null,
    chunk_client_id: ?u32 = null,
    chunk_operation: ?u2 = null,
    chunk_bytes: [max_application_bytes]u8 = @splat(0),
    chunk_len: u16 = 0,

    /// Applies one parsed FIFO command and returns complete host work.
    ///
    /// Limit and chain failures preserve registration and prior chunk bytes.
    pub fn consume(
        self: *State,
        head: *const control.DragDropHead,
    ) error{ ChunkLimit, InvalidChain }!?Action {
        if (head.kind == .query) return .{ .query = .{ .client_id = head.client_id } };
        if (head.kind == .continuation) return try self.continueChunk(head);
        if (self.chunk_kind != null) return error.InvalidChain;
        if (head.kind != .enable and
            (!self.enabled or head.client_id != self.client_id))
            return .{ .reject = .{
                .client_id = head.client_id,
                .index = head.index,
                .remote = head.remote,
                .command = head.command,
            } };
        return switch (head.kind) {
            .enable => self.startChunk(.enable, head),
            .disable => disable: {
                self.enabled = false;
                self.client_id = null;
                break :disable .disable;
            },
            .accept => self.startChunk(.accept, head),
            .request => .{ .request = .{
                .client_id = head.client_id,
                .index = head.index orelse return error.InvalidChain,
            } },
            .complete => .{ .complete = .{
                .client_id = head.client_id,
                .operation = head.operation orelse return error.InvalidChain,
            } },
            .unsupported => .{ .reject = .{
                .client_id = head.client_id,
                .index = head.index,
                .remote = head.remote,
                .command = head.command,
            } },
            .query, .continuation => unreachable,
        };
    }

    fn startChunk(
        self: *State,
        kind: ChunkKind,
        head: *const control.DragDropHead,
    ) error{ChunkLimit}!?Action {
        if (!head.more) return self.complete(kind, head.client_id, head.operation, head.payloadBytes());
        if (head.payload_len > self.chunk_bytes.len) return error.ChunkLimit;
        @memcpy(self.chunk_bytes[0..head.payload_len], head.payloadBytes());
        self.chunk_len = head.payload_len;
        self.chunk_kind = kind;
        self.chunk_client_id = head.client_id;
        self.chunk_operation = head.operation;
        return null;
    }

    fn continueChunk(
        self: *State,
        head: *const control.DragDropHead,
    ) error{ ChunkLimit, InvalidChain }!?Action {
        const kind = self.chunk_kind orelse return error.InvalidChain;
        if (head.client_id != self.chunk_client_id) return error.InvalidChain;
        const next = std.math.add(usize, self.chunk_len, head.payload_len) catch
            return error.ChunkLimit;
        if (next > self.chunk_bytes.len) return error.ChunkLimit;
        @memcpy(self.chunk_bytes[self.chunk_len..next], head.payloadBytes());
        self.chunk_len = @intCast(next);
        if (head.more) return null;
        const action = self.complete(
            kind,
            self.chunk_client_id,
            self.chunk_operation,
            self.chunk_bytes[0..self.chunk_len],
        );
        self.clearChunk();
        return action;
    }

    fn complete(
        self: *State,
        kind: ChunkKind,
        client_id: ?u32,
        operation: ?u2,
        payload: []const u8,
    ) Action {
        return switch (kind) {
            .enable => enable: {
                self.enabled = true;
                self.client_id = client_id;
                break :enable .{ .enable = .{ .client_id = client_id, .mimes = payload } };
            },
            .accept => .{ .accept = .{
                .client_id = client_id,
                .operation = operation orelse 0,
                .mimes = payload,
            } },
        };
    }

    /// Clears registration and incomplete protocol state on terminal shutdown.
    pub fn reset(self: *State) void {
        self.* = .{};
    }

    /// Cancels only an invalid chunk chain while preserving application registration.
    pub fn cancelChunk(self: *State) void {
        self.chunk_kind = null;
        self.chunk_client_id = null;
        self.chunk_operation = null;
        self.chunk_len = 0;
    }

    fn clearChunk(self: *State) void {
        self.cancelChunk();
    }
};

/// Returns the one-based first exact offered MIME named by a preference payload.
pub fn preferred(offered: *const MimeList, preferences: []const u8) ?u32 {
    var tokens = std.mem.tokenizeScalar(u8, preferences, ' ');
    while (tokens.next()) |mime| if (offered.find(mime)) |index| return index;
    return null;
}

test "MIME identity preserves opaque order and exact bounds" {
    var list: MimeList = .{};
    try list.append("text/plain");
    try list.append("text/uri-list");
    try std.testing.expectEqualStrings("text/uri-list", list.at(2).?);
    try std.testing.expectEqual(@as(?u32, 1), list.find("text/plain"));
    var bytes: [64]u8 = undefined;
    try std.testing.expectEqualStrings("text/plain text/uri-list", try list.format(&bytes));
    const before = list;
    try std.testing.expectError(error.MimeLimit, list.append(""));
    try std.testing.expectEqualDeep(before, list);
}

test "chunk chain is ordered bounded and registration commits on completion" {
    var state: State = .{};
    var first = testHead(.enable, 1, true, "text/");
    try std.testing.expect(try state.consume(&first) == null);
    try std.testing.expect(!state.enabled);
    var query = testHead(.query, 2, false, "");
    try std.testing.expectEqual(@as(?u32, 2), (try state.consume(&query)).?.query.client_id);
    var last = testHead(.continuation, 1, false, "uri-list");
    const enabled = (try state.consume(&last)).?.enable;
    try std.testing.expectEqualStrings("text/uri-list", enabled.mimes);
    try std.testing.expect(state.enabled);
    var wrong = testHead(.request, 9, false, "");
    wrong.index = 1;
    try std.testing.expect((try state.consume(&wrong)).? == .reject);
    var stale = testHead(.continuation, 1, false, "x");
    try std.testing.expectError(error.InvalidChain, state.consume(&stale));
}

fn testHead(
    kind: @FieldType(control.DragDropHead, "kind"),
    client_id: ?u32,
    more: bool,
    payload: []const u8,
) control.DragDropHead {
    var result = control.DragDropHead{
        .generation = 1,
        .kind = kind,
        .command = 0,
        .client_id = client_id,
        .more = more,
        .operation = if (kind == .accept) 1 else null,
        .index = null,
        .remote = false,
        .payload = @splat(0),
        .payload_len = @intCast(payload.len),
    };
    @memcpy(result.payload[0..payload.len], payload);
    return result;
}
