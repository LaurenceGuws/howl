//! Clipboard grammar, bounded Base64 codec, and child-directed replies.
//!
//! Terminal composition retains validated occurrences through `consequences.zig`;
//! this owner classifies borrowed OSC 52 payloads and performs exact codec work.

const std = @import("std");
const consequences = @import("consequences.zig");
const replies = @import("replies.zig");
const grammar = @import("vt_clipboard_grammar");

/// OSC 52 names four standard selections and eight numbered cut buffers.
const selection_bytes_max = grammar.maximum_selection_bytes;
/// One query reply fits regardless of selection length and seven-bit framing.
const query_reply_bytes_max: u32 =
    ((replies.max_bytes - selection_bytes_max - 8) / 4) * 3;

/// Borrows one validated OSC 52 occurrence until its parser payload changes.
pub const ParsedRequest = struct {
    selection: []const u8,
    data: []const u8,
    kind: consequences.ClipboardRequestKind,
};

/// Reports malformed syntax, unsupported query input, invalid Base64, or allocation failure.
pub const DecodeError = error{
    InvalidCharacter,
    InvalidOsc52Payload,
    InvalidPadding,
    OutOfMemory,
    UnsupportedOsc52Query,
};

/// Reports malformed syntax or unsupported query input while measuring decoded bytes.
pub const SizeError = error{
    InvalidOsc52Payload,
    InvalidPadding,
    UnsupportedOsc52Query,
};

/// Reports allocation or either exact retained-reply bound.
pub const QueryReplyError = error{ OutOfMemory, ReplyLimit, ConsequenceLimit };

const IntoError = error{
    InvalidCharacter,
    InvalidOsc52Payload,
    InvalidPadding,
    ShortBuffer,
    UnsupportedOsc52Query,
};

comptime {
    std.debug.assert(query_reply_bytes_max < replies.max_bytes);
}

/// Classifies one complete OSC 52 payload and validates replacement Base64.
pub fn parse(raw: []const u8) ?ParsedRequest {
    const request = grammar.parse(raw) orelse return null;
    return projected(request);
}

/// Allocates and decodes one validated OSC 52 replacement into caller ownership.
pub fn decodeSet(allocator: std.mem.Allocator, raw: []const u8) DecodeError![]u8 {
    const decoded_len = try decodedSetSize(raw);
    const output = try allocator.alloc(u8, @intCast(decoded_len));
    errdefer allocator.free(output);
    std.debug.assert(output.len == decoded_len);
    const written = decodeSetInto(raw, output) catch |failure| switch (failure) {
        // zig-audit: acknowledge unreachable
        // reason: decodeSet allocated the exact length measured from these unchanged request bytes before calling decodeSetInto.
        error.ShortBuffer => unreachable,
        error.InvalidCharacter => return error.InvalidCharacter,
        error.InvalidOsc52Payload => return error.InvalidOsc52Payload,
        error.InvalidPadding => return error.InvalidPadding,
        error.UnsupportedOsc52Query => return error.UnsupportedOsc52Query,
    };
    std.debug.assert(written == decoded_len);
    return output;
}

/// Measures decoded replacement bytes without allocating or accepting a query.
pub fn decodedSetSize(raw: []const u8) SizeError!u64 {
    const request = parseEnvelope(raw) orelse return error.InvalidOsc52Payload;
    if (request.kind == .query) return error.UnsupportedOsc52Query;
    return @intCast(try decodedBase64Size(request.data));
}

/// Appends one caller-approved query reply as an atomic OSC transaction.
pub fn appendQueryReply(
    output: *replies.Buffer,
    allocator: std.mem.Allocator,
    selection: []const u8,
    bytes: []const u8,
) QueryReplyError!void {
    if (bytes.len > query_reply_bytes_max) return error.ConsequenceLimit;
    const encoded_len = std.base64.standard.Encoder.calcSize(bytes.len);
    const prefix_len = std.math.add(usize, 4, selection.len) catch
        return error.ConsequenceLimit;
    const payload_len = std.math.add(usize, prefix_len, encoded_len) catch
        return error.ConsequenceLimit;
    if (payload_len > replies.max_bytes) return error.ReplyLimit;
    const payload = try allocator.alloc(u8, payload_len);
    defer allocator.free(payload);
    @memcpy(payload[0..3], "52;");
    @memcpy(payload[3 .. 3 + selection.len], selection);
    payload[prefix_len - 1] = ';';
    const encoded = std.base64.standard.Encoder.encode(payload[prefix_len..], bytes);
    std.debug.assert(encoded.len == encoded_len);
    try output.appendString(.terminal, .osc, payload);
}

/// The two distinct caller-owned clipboard locations.
pub const KittyLocation = enum { clipboard, primary };

/// Caller scratch for decoding the bounded request, never clipboard storage.
pub const KittyReadScratch = [consequences.retained_packet_bytes_max]u8;
/// Borrows decoded requested MIME names from caller scratch.
pub const KittyReadRequest = struct {
    location: KittyLocation,
    mime_types: []const u8,
};
/// One atomic response step. Caller owns all data and retries only the
/// step rejected by reply pressure or allocation failure.
pub const KittyReadReply = union(enum) {
    begin: KittyLocation,
    data: struct { mime: []const u8, bytes: []const u8, last: bool },
    list: struct { names: []const []const u8, last: bool },
    done,
    unavailable,
    denied,
    busy,
};
/// An invalid caller response cannot change the admitted stream.
pub const KittyReadError = replies.AppendError || error{InvalidClipboardResponse};
const max_read_chunk = 4096;
const mime_whitespace = " \t\r\n\x0b\x0c";
const KittyOperation = enum { read, write };
const KittyStatus = enum { OK, DATA, DONE, ENOSYS, EPERM, EBUSY, EINVAL, EIO, EFBIG };
const KittyStart = struct {
    kind: KittyOperation,
    id: []const u8,
    valid: bool,
    location: KittyLocation,
    mime_types: []const u8,
};

// Validate complete encoded strings without repairing malformed wire bytes.
// Write-data fragments are deliberately not decoded here: no write has been
// admitted by the caller that selects this refusal lane.
fn encodedText(data: []const u8, scratch: []u8) ?[]const u8 {
    if (data.len % 4 != 0) return null;
    const decoder = std.base64.standard.Decoder;
    const count = decoder.calcSizeForSlice(data) catch return null;
    if (count > scratch.len) return null;
    decoder.decode(scratch[0..count], data) catch return null;
    const decoded = scratch[0..count];
    if (!std.unicode.utf8ValidateSlice(decoded)) return null;
    return decoded;
}

// Classify only unambiguous known start metadata. A malformed structural
// envelope cannot supply a reliable routing identity; ignore it. A recognized
// write with invalid encoded metadata or unexpected data gets EINVAL.
fn kittyStart(raw: []const u8, scratch: *KittyReadScratch) ?KittyStart {
    const separator = std.mem.indexOfScalar(u8, raw, ';') orelse raw.len;
    const data = if (separator == raw.len) "" else raw[separator + 1 ..];
    var fields = std.mem.splitScalar(u8, raw[0..separator], ':');
    var kind: ?KittyOperation = null;
    var id: []const u8 = "";
    var seen: u8 = 0;
    var valid = true;
    var location: KittyLocation = .clipboard;
    while (fields.next()) |field| {
        const equals = std.mem.indexOfScalar(u8, field, '=') orelse return null;
        const key = field[0..equals];
        const value = field[equals + 1 ..];
        const slot: u3 = if (std.mem.eql(u8, key, "type")) blk: {
            kind = if (std.mem.eql(u8, value, "read")) .read else if (std.mem.eql(u8, value, "write")) .write else return null;
            break :blk 0;
        } else if (std.mem.eql(u8, key, "id")) blk: {
            id = value;
            break :blk 1;
        } else if (std.mem.eql(u8, key, "loc")) blk: {
            if (std.mem.eql(u8, value, "primary"))
                location = .primary
            else
                valid = false;
            break :blk 2;
        } else if (std.mem.eql(u8, key, "name")) blk: {
            if (encodedText(value, scratch) == null) valid = false;
            break :blk 3;
        } else if (std.mem.eql(u8, key, "pw")) blk: {
            if (encodedText(value, scratch) == null) valid = false;
            break :blk 4;
        } else return null;
        const bit = @as(u8, 1) << slot;
        if (seen & bit != 0) return null;
        seen |= bit;
    }
    const operation = kind orelse return null;
    var mime_types: []const u8 = "";
    switch (operation) {
        .read => {
            mime_types = encodedText(data, scratch) orelse return null;
            if (std.mem.trim(u8, mime_types, mime_whitespace).len == 0) return null;
            for (mime_types) |byte| {
                if ((byte < 0x20 and !std.ascii.isWhitespace(byte)) or byte == 0x7f) return null;
            }
        },
        .write => if (data.len != 0) {
            valid = false;
        },
    }
    return .{ .kind = operation, .id = id, .valid = valid, .location = location, .mime_types = mime_types };
}

/// Returns the validated read location and decoded MIME list in caller scratch.
pub fn inspectKittyRead(raw: []const u8, scratch: *KittyReadScratch) ?KittyReadRequest {
    const request = kittyStart(raw, scratch) orelse return null;
    if (request.kind != .read or !request.valid) return null;
    return .{ .location = request.location, .mime_types = request.mime_types };
}

// Serialize the response through one bounded owner for both positive and
// negative paths. A caller-selected MIME token comes from the original
// request (or the special period), so encoded metadata is also bounded.
fn appendKittyResponse(output: *replies.Buffer, request: KittyStart, status: KittyStatus, mime: []const u8, data: []const u8) replies.AppendError!void {
    const encoder = std.base64.standard.Encoder;
    var response: [consequences.retained_packet_bytes_max + 128 + encoder.calcSize(consequences.retained_packet_bytes_max) + encoder.calcSize(max_read_chunk)]u8 = undefined;
    const header = std.fmt.bufPrint(&response, "5522;type={s}:status={s}{s}", .{
        @tagName(request.kind),
        @tagName(status),
        if (request.kind == .read and status == .OK and request.location == .primary) ":loc=primary" else "",
    }) catch return error.ReplyLimit;
    const id_start = header.len + ":id=".len;
    var end = id_start;
    for (request.id) |byte| switch (byte) {
        'a'...'z', 'A'...'Z', '0'...'9', '-', '_', '+', '.' => {
            response[end] = byte;
            end += 1;
        },
        else => {},
    };
    if (end == id_start)
        end = header.len
    else
        @memcpy(response[header.len..id_start], ":id=");
    if (mime.len != 0) {
        @memcpy(response[end..][0..6], ":mime=");
        end += 6;
        end += encoder.encode(response[end..], mime).len;
    }
    if (data.len != 0) {
        response[end] = ';';
        end += 1;
        end += encoder.encode(response[end..], data).len;
    }
    try output.appendString(.kitty, .osc, response[0..end]);
}

/// Serializes the caller's refusal of an OSC 5522 packet. No clipboard
/// data, permission token, or host action is accepted. Invalid reads and
/// unassociated write continuations are silent; valid starts receive EPERM.
/// The original packet is bounded by the canonical consequence owner.
pub fn appendKittyRefusal(output: *replies.Buffer, raw: []const u8) replies.AppendError!void {
    std.debug.assert(raw.len <= consequences.retained_packet_bytes_max);
    var scratch: KittyReadScratch = undefined;
    const request = kittyStart(raw, &scratch) orelse return;
    if (request.kind == .read and !request.valid) return;
    try appendKittyResponse(output, request, if (request.valid) .EPERM else .EINVAL, "", "");
}

// Select the next requested MIME in order. Unavailable ordinary types can
// be skipped; an open type must finish before any later type is sent.
// A period requests an inventory, which must not be silently skipped.
fn selectReadMime(request: KittyStart, cursor: consequences.KittyReadCursor, mime: []const u8, last: bool) error{InvalidClipboardResponse}!consequences.KittyReadCursor {
    var names = std.mem.tokenizeAny(u8, request.mime_types, mime_whitespace);
    var ordinal: u16 = 0;
    while (names.next()) |name| : (ordinal += 1) {
        if (ordinal < cursor.next_mime) continue;
        if (std.mem.eql(u8, name, mime))
            return .{ .next_mime = ordinal + @intFromBool(last), .open = !last };
        if (cursor.open or std.mem.eql(u8, name, ".")) return error.InvalidClipboardResponse;
    }
    return error.InvalidClipboardResponse;
}

fn readCanFinish(request: KittyStart, cursor: consequences.KittyReadCursor) bool {
    if (cursor.open) return false;
    var names = std.mem.tokenizeAny(u8, request.mime_types, mime_whitespace);
    var ordinal: u16 = 0;
    while (names.next()) |name| : (ordinal += 1) {
        if (ordinal >= cursor.next_mime and std.mem.eql(u8, name, ".")) return false;
    }
    return true;
}

fn validMimeName(name: []const u8) bool {
    if (name.len == 0 or std.mem.eql(u8, name, ".") or !std.unicode.utf8ValidateSlice(name)) return false;
    for (name) |byte| {
        if (byte <= 0x20 or byte == 0x7f) return false;
    }
    return true;
}

/// Appends one complete caller-approved read step. Return null only when
/// the exact request can retire (opening error or DONE). No cursor or
/// caller borrows are changed until a complete reply fits the queue.
pub fn appendKittyRead(output: *replies.Buffer, raw: []const u8, progress: ?consequences.KittyReadCursor, reply: KittyReadReply) KittyReadError!?consequences.KittyReadCursor {
    std.debug.assert(raw.len <= consequences.retained_packet_bytes_max);
    var scratch: KittyReadScratch = undefined;
    const request = kittyStart(raw, &scratch) orelse return error.InvalidClipboardResponse;
    if (request.kind != .read or !request.valid) return error.InvalidClipboardResponse;
    switch (reply) {
        .begin => |location| {
            if (progress != null or location != request.location) return error.InvalidClipboardResponse;
            try appendKittyResponse(output, request, .OK, "", "");
            return .{};
        },
        .unavailable, .denied, .busy => {
            if (progress != null) return error.InvalidClipboardResponse;
            const status: KittyStatus = switch (reply) {
                .unavailable => .ENOSYS,
                .denied => .EPERM,
                .busy => .EBUSY,
                else => return error.InvalidClipboardResponse,
            };
            try appendKittyResponse(output, request, status, "", "");
            return null;
        },
        .data => |chunk| {
            const cursor = progress orelse return error.InvalidClipboardResponse;
            if (chunk.bytes.len > max_read_chunk or (chunk.bytes.len == 0 and !chunk.last) or
                std.mem.eql(u8, chunk.mime, ".")) return error.InvalidClipboardResponse;
            const next = try selectReadMime(request, cursor, chunk.mime, chunk.last);
            try appendKittyResponse(output, request, .DATA, chunk.mime, chunk.bytes);
            return next;
        },
        .list => |listing| {
            const cursor = progress orelse return error.InvalidClipboardResponse;
            if (listing.names.len == 0 and !listing.last) return error.InvalidClipboardResponse;
            const next = try selectReadMime(request, cursor, ".", listing.last);
            var bytes: [max_read_chunk]u8 = undefined;
            var used: usize = 0;
            for (listing.names) |name| {
                if (name.len >= bytes.len - used or !validMimeName(name)) return error.InvalidClipboardResponse;
                @memcpy(bytes[used..][0..name.len], name);
                used += name.len;
                bytes[used] = ' ';
                used += 1;
            }
            if (used != 0) bytes[used - 1] = '\n';
            try appendKittyResponse(output, request, .DATA, ".", bytes[0..used]);
            return next;
        },
        .done => {
            const cursor = progress orelse return error.InvalidClipboardResponse;
            if (!readCanFinish(request, cursor)) return error.InvalidClipboardResponse;
            try appendKittyResponse(output, request, .DONE, "", "");
            return null;
        },
    }
}

/// Maximum owned decoded bytes across all direct MIME entries. Aliases
/// never consume this budget a second time.
pub const max_write_bytes: usize = 64 * 1024 * 1024;
const max_write_mimes = 256;
const max_mime_name_bytes = 4096;

/// Terminal write completion is chosen by the authorized embedding caller.
pub const KittyWriteStatus = enum { DONE, EIO, EINVAL, ENOSYS, EPERM, EBUSY, EFBIG };
/// Failure status for a write which has not published data.
pub const KittyWriteFailure = enum { EIO, EINVAL, ENOSYS, EPERM, EBUSY, EFBIG };
/// Staging result: only ready permits observing or transferring the complete data.
pub const KittyWriteProgress = enum { ignored, staged, ready, aborted };
const WriteStageError = error{ InvalidClipboardResponse, ClipboardLimit, OutOfMemory };
/// Reports an invalid selected write start or allocation failure.
pub const KittyWriteInitError = error{ InvalidClipboardResponse, OutOfMemory };

const MimeRange = struct { start: usize, len: usize };
const MimeEntry = struct {
    name: []const u8,
    range: ?MimeRange = null,
    alias: ?u16 = null,
};

/// Borrows one completed immutable MIME inventory until its owner mutates.
pub const KittyWriteView = struct {
    location: KittyLocation,
    bytes: []const u8,
    entries: []const MimeEntry,

    /// Count of direct and aliased names.
    pub fn count(self: KittyWriteView) usize {
        return self.entries.len;
    }

    /// Borrow a name and its shared payload by inventory index.
    pub fn entry(self: KittyWriteView, index: usize) ?struct { mime: []const u8, bytes: []const u8 } {
        if (index >= self.entries.len) return null;
        const item = self.entries[index];
        const target = if (item.alias) |alias| self.entries[alias] else item;
        const range = target.range orelse return null;
        return .{ .mime = item.name, .bytes = self.bytes[range.start..][0..range.len] };
    }

    /// Borrow the direct or aliased payload of a named MIME.
    pub fn get(self: KittyWriteView, name: []const u8) ?[]const u8 {
        for (self.entries, 0..) |item, index| {
            if (std.mem.eql(u8, item.name, name)) return if (self.entry(index)) |value| value.bytes else null;
        }
        return null;
    }
};

/// Caller-owned completed clipboard bytes. The transaction owner moves
/// these allocations once, before external publication is acknowledged.
pub const KittyWriteData = struct {
    allocator: std.mem.Allocator,
    location: KittyLocation,
    bytes: std.ArrayList(u8) = .empty,
    entries: std.ArrayList(MimeEntry) = .empty,

    /// Releases every unique allocation, never freeing an alias payload twice.
    pub fn deinit(self: *KittyWriteData) void {
        for (self.entries.items) |item| self.allocator.free(item.name);
        self.entries.deinit(self.allocator);
        self.bytes.deinit(self.allocator);
        self.* = .{ .allocator = self.allocator, .location = self.location };
    }

    /// Borrows the completed inventory from caller ownership.
    pub fn view(self: *const KittyWriteData) KittyWriteView {
        return .{ .location = self.location, .bytes = self.bytes.items, .entries = self.entries.items };
    }

    fn indexOf(self: *const KittyWriteData, name: []const u8) ?u16 {
        for (self.entries.items, 0..) |item, index| {
            if (std.mem.eql(u8, item.name, name)) return @intCast(index);
        }
        return null;
    }

    fn ensureName(self: *KittyWriteData, name: []const u8) WriteStageError!u16 {
        if (name.len > max_mime_name_bytes or !validMimeName(name)) return error.InvalidClipboardResponse;
        if (self.indexOf(name)) |index| return index;
        if (self.entries.items.len == max_write_mimes) return error.ClipboardLimit;
        const owned = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned);
        const index: u16 = @intCast(self.entries.items.len);
        if (self.entries.items.len == self.entries.capacity)
            try self.entries.ensureTotalCapacityPrecise(self.allocator, @min(max_write_mimes, @max(8, self.entries.capacity * 2)));
        self.entries.appendAssumeCapacity(.{ .name = owned });
        return index;
    }

    fn appendBytes(self: *KittyWriteData, bytes: []const u8) WriteStageError!void {
        if (bytes.len > max_write_bytes - self.bytes.items.len) return error.ClipboardLimit;
        const required = self.bytes.items.len + bytes.len;
        if (required > self.bytes.capacity)
            try self.bytes.ensureTotalCapacityPrecise(self.allocator, @min(max_write_bytes, @max(required, self.bytes.capacity * 2)));
        self.bytes.appendSliceAssumeCapacity(bytes);
    }
};

/// Validated write start location, without a permission grant.
pub fn inspectKittyWrite(raw: []const u8) ?KittyLocation {
    var scratch: KittyReadScratch = undefined;
    const request = kittyStart(raw, &scratch) orelse return null;
    return if (request.kind == .write and request.valid) request.location else null;
}

/// Reject a validated write start with an explicit caller-selected failure.
pub fn appendKittyWriteStartFailure(output: *replies.Buffer, raw: []const u8, failure: KittyWriteFailure) KittyReadError!void {
    var scratch: KittyReadScratch = undefined;
    const request = kittyStart(raw, &scratch) orelse return error.InvalidClipboardResponse;
    if (request.kind != .write or !request.valid) return error.InvalidClipboardResponse;
    try appendKittyResponse(output, request, switch (failure) {
        .EIO => .EIO,
        .EINVAL => .EINVAL,
        .ENOSYS => .ENOSYS,
        .EPERM => .EPERM,
        .EBUSY => .EBUSY,
        .EFBIG => .EFBIG,
    }, "", "");
}

/// Whether the exact packet is a structurally recognized start, including
/// an invalid encoded write. Continuations use the separate grammar below.
pub fn isKittyWriteStart(raw: []const u8) bool {
    var scratch: KittyReadScratch = undefined;
    const request = kittyStart(raw, &scratch) orelse return false;
    return request.kind == .write;
}

const WritePacketKind = enum { data, alias, end };
const WritePacket = struct {
    kind: WritePacketKind,
    mime: []const u8,
    data: []const u8,
};

fn parseWritePacket(raw: []const u8, route: []const u8, scratch: *KittyReadScratch) ?WritePacket {
    const separator = std.mem.indexOfScalar(u8, raw, ';') orelse raw.len;
    const data = if (separator == raw.len) "" else raw[separator + 1 ..];
    var fields = std.mem.splitScalar(u8, raw[0..separator], ':');
    var kind: ?WritePacketKind = null;
    var mime: ?[]const u8 = null;
    var seen_id = false;
    while (fields.next()) |field| {
        const equals = std.mem.indexOfScalar(u8, field, '=') orelse return null;
        const key = field[0..equals];
        const value = field[equals + 1 ..];
        if (std.mem.eql(u8, key, "type")) {
            if (kind != null) return null;
            kind = if (std.mem.eql(u8, value, "wdata")) .data else if (std.mem.eql(u8, value, "walias")) .alias else return null;
        } else if (std.mem.eql(u8, key, "mime")) {
            if (mime != null) return null;
            mime = encodedText(value, scratch) orelse return null;
            if (!validMimeName(mime.?) or mime.?.len > max_mime_name_bytes) return null;
        } else if (std.mem.eql(u8, key, "id")) {
            if (seen_id or !std.mem.eql(u8, value, route)) return null;
            seen_id = true;
        } else return null;
    }
    const operation = kind orelse return null;
    if (mime == null) {
        if (operation != .data or data.len != 0) return null;
        return .{ .kind = .end, .mime = "", .data = "" };
    }
    return .{ .kind = operation, .mime = mime.?, .data = data };
}

fn alphabetByte(byte: u8) bool {
    return switch (byte) {
        'A'...'Z', 'a'...'z', '0'...'9', '+', '/' => true,
        else => false,
    };
}

/// Owns a single admitted transient write. No allocation occurs for a
/// terminal without an explicitly authorized start; no host I/O occurs here.
pub const KittyWrite = struct {
    contents: KittyWriteData,
    route: []u8,
    current: ?u16 = null,
    tail: [3]u8 = undefined,
    tail_len: u2 = 0,
    padded: bool = false,
    ready: bool = false,
    transferred: bool = false,
    failure: ?KittyWriteStatus = null,

    /// Allocates the small owner and route only after caller selection.
    pub fn init(allocator: std.mem.Allocator, raw: []const u8, location: KittyLocation) KittyWriteInitError!*KittyWrite {
        var scratch: KittyReadScratch = undefined;
        const request = kittyStart(raw, &scratch) orelse return error.InvalidClipboardResponse;
        if (request.kind != .write or !request.valid or request.location != location)
            return error.InvalidClipboardResponse;
        const value = try allocator.create(KittyWrite);
        errdefer allocator.destroy(value);
        value.* = .{
            .contents = .{ .allocator = allocator, .location = location },
            .route = try allocator.dupe(u8, request.id),
        };
        return value;
    }

    /// Releases staging and route. Completed data may already have moved.
    pub fn deinit(self: *KittyWrite) void {
        const allocator = self.contents.allocator;
        self.contents.deinit();
        allocator.free(self.route);
        allocator.destroy(self);
    }

    /// Release all staged bytes on first failure; retain only routing and
    /// status until that error can be admitted into the bounded reply queue.
    pub fn fail(self: *KittyWrite, status: KittyWriteStatus) void {
        if (self.failure != null) return;
        std.debug.assert(status != .DONE);
        self.contents.deinit();
        self.current = null;
        self.tail_len = 0;
        self.padded = false;
        self.ready = false;
        self.failure = status;
    }

    /// Serialize status with the original start identity, not the last chunk.
    pub fn appendStatus(self: *const KittyWrite, output: *replies.Buffer, status: KittyWriteStatus) replies.AppendError!void {
        try appendKittyResponse(output, .{
            .kind = .write,
            .id = self.route,
            .valid = true,
            .location = self.contents.location,
            .mime_types = "",
        }, switch (status) {
            .DONE => KittyStatus.DONE,
            .EIO => KittyStatus.EIO,
            .EINVAL => KittyStatus.EINVAL,
            .ENOSYS => KittyStatus.ENOSYS,
            .EPERM => KittyStatus.EPERM,
            .EBUSY => KittyStatus.EBUSY,
            .EFBIG => KittyStatus.EFBIG,
        }, "", "");
    }

    // Close the previous group before a new direct MIME begins.
    fn closeGroup(self: *KittyWrite) WriteStageError!void {
        if (self.tail_len != 0) return error.InvalidClipboardResponse;
        self.current = null;
        self.padded = false;
    }

    fn appendData(self: *KittyWrite, mime: []const u8, data: []const u8) WriteStageError!void {
        const index = try self.contents.ensureName(mime);
        if (self.current != index) {
            try self.closeGroup();
            const item = &self.contents.entries.items[index];
            if (item.alias != null or item.range != null) return error.InvalidClipboardResponse;
            item.range = .{ .start = self.contents.bytes.items.len, .len = 0 };
            self.current = index;
        }
        if (self.padded and data.len != 0) return error.InvalidClipboardResponse;
        var encoded: [consequences.retained_packet_bytes_max + 3]u8 = undefined;
        const prefix: usize = self.tail_len;
        @memcpy(encoded[0..prefix], self.tail[0..prefix]);
        @memcpy(encoded[prefix..][0..data.len], data);
        const all = encoded[0 .. prefix + data.len];
        const complete_len = all.len - all.len % 4;
        const complete = all[0..complete_len];
        const tail = all[complete_len..];
        const padded = std.mem.endsWith(u8, complete, "=");
        if (padded and tail.len != 0) return error.InvalidClipboardResponse;
        for (tail, 0..) |byte, position| {
            if (!alphabetByte(byte) and !(byte == '=' and position == 2)) return error.InvalidClipboardResponse;
        }
        const decoder = std.base64.standard.Decoder;
        const size = decoder.calcSizeForSlice(complete) catch return error.InvalidClipboardResponse;
        if (size > max_read_chunk) return error.InvalidClipboardResponse;
        var decoded: [max_read_chunk]u8 = undefined;
        decoder.decode(decoded[0..size], complete) catch return error.InvalidClipboardResponse;
        try self.contents.appendBytes(decoded[0..size]);
        self.contents.entries.items[index].range.?.len += size;
        @memcpy(self.tail[0..tail.len], tail);
        self.tail_len = @intCast(tail.len);
        self.padded = self.padded or padded;
    }

    fn addAliases(self: *KittyWrite, target_name: []const u8, encoded: []const u8) WriteStageError!void {
        var scratch: KittyReadScratch = undefined;
        const names = encodedText(encoded, &scratch) orelse return error.InvalidClipboardResponse;
        const target = try self.contents.ensureName(target_name);
        if (self.contents.entries.items[target].alias != null) return error.InvalidClipboardResponse;
        var tokens = std.mem.tokenizeAny(u8, names, mime_whitespace);
        if (tokens.peek() == null) return error.InvalidClipboardResponse;
        while (tokens.next()) |name| {
            const alias = try self.contents.ensureName(name);
            if (alias == target) return error.InvalidClipboardResponse;
            const item = &self.contents.entries.items[alias];
            if (item.range != null) return error.InvalidClipboardResponse;
            if (item.alias) |prior| {
                if (prior != target) return error.InvalidClipboardResponse;
                continue;
            }
            // A forward target is reserved by aliases already pointing at
            // it. It cannot later become an alias or form a cycle.
            for (self.contents.entries.items) |entry_value| {
                if (entry_value.alias == alias) return error.InvalidClipboardResponse;
            }
            item.alias = target;
        }
    }

    /// Stages one bounded packet. Failure invalidates the whole transaction
    /// at the terminal owner, not just this fragment.
    pub fn stage(self: *KittyWrite, raw: []const u8) WriteStageError!KittyWriteProgress {
        std.debug.assert(self.failure == null and !self.ready and raw.len <= consequences.retained_packet_bytes_max);
        var scratch: KittyReadScratch = undefined;
        const packet = parseWritePacket(raw, self.route, &scratch) orelse return error.InvalidClipboardResponse;
        switch (packet.kind) {
            .data => try self.appendData(packet.mime, packet.data),
            .alias => try self.addAliases(packet.mime, packet.data),
            .end => {
                try self.closeGroup();
                for (self.contents.entries.items) |item| {
                    const direct = if (item.alias) |target| self.contents.entries.items[target] else item;
                    if (direct.range == null) return error.InvalidClipboardResponse;
                }
                self.ready = true;
                return .ready;
            },
        }
        return .staged;
    }

    /// Move completed allocations to the caller without copying bytes.
    pub fn take(self: *KittyWrite) KittyWriteData {
        std.debug.assert(self.ready and self.failure == null and !self.transferred);
        self.transferred = true;
        const result = self.contents;
        self.contents = .{ .allocator = result.allocator, .location = result.location };
        return result;
    }
};

fn decodeSetInto(raw: []const u8, output: []u8) IntoError!u64 {
    const request = parseEnvelope(raw) orelse return error.InvalidOsc52Payload;
    if (request.kind == .query) return error.UnsupportedOsc52Query;
    const decoded_len = try decodedBase64Size(request.data);
    if (output.len < decoded_len) return error.ShortBuffer;
    std.debug.assert(output.len >= decoded_len);
    std.base64.standard.Decoder.decode(output[0..decoded_len], request.data) catch |failure| switch (failure) {
        error.InvalidCharacter => return error.InvalidCharacter,
        error.InvalidPadding => return error.InvalidPadding,
        // zig-audit: acknowledge unreachable
        // reason: The destination is sliced to the exact Base64 size computed from the same unchanged payload; invalid alphabet and padding still return typed errors.
        error.NoSpaceLeft => unreachable,
    };
    return @intCast(decoded_len);
}

fn decodedBase64Size(data: []const u8) error{InvalidPadding}!usize {
    // Size calculation cannot inspect alphabet bytes or consume destination space.
    return std.base64.standard.Decoder.calcSizeForSlice(data) catch |failure| switch (failure) {
        error.InvalidPadding => return error.InvalidPadding,
        // zig-audit: acknowledge unreachable
        // reason: calcSizeForSlice inspects length/padding only and has no destination; the pinned Base64 implementation cannot report alphabet or output-space failures here.
        error.InvalidCharacter, error.NoSpaceLeft => unreachable,
    };
}

fn parseEnvelope(raw: []const u8) ?ParsedRequest {
    const request = grammar.parseEnvelope(raw) orelse return null;
    return projected(request);
}
fn projected(request: grammar.ParsedRequest) ParsedRequest {
    return .{ .selection = request.selection, .data = request.data, .kind = switch (request.kind) {
        .set => .set,
        .query => .query,
    } };
}

test "OSC 52 replacement payload decodes into exact caller ownership" {
    const decoded = try decodeSet(std.testing.allocator, "c;SG93bA==");
    defer std.testing.allocator.free(decoded);
    try std.testing.expectEqualStrings("Howl", decoded);
}

test "OSC 52 query is unsupported for replacement drain" {
    try std.testing.expectError(error.UnsupportedOsc52Query, decodeSet(std.testing.allocator, "c;?"));
}

test "OSC 52 decode reports exact syntax Base64 buffer and allocation failures" {
    const decode: *const fn (std.mem.Allocator, []const u8) DecodeError![]u8 = decodeSet;
    try std.testing.expectError(error.InvalidOsc52Payload, decode(std.testing.allocator, "SG93bA=="));
    try std.testing.expectError(error.InvalidPadding, decode(std.testing.allocator, "c;A"));
    try std.testing.expectError(error.InvalidCharacter, decode(std.testing.allocator, "c;!!!!"));

    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, decode(failing.allocator(), "c;SG93bA=="));
    try std.testing.expect(failing.has_induced_failure);

    var short: [3]u8 = undefined;
    try std.testing.expectError(error.ShortBuffer, decodeSetInto("c;SG93bA==", &short));
}

test "OSC 52 query serialization honors framing and exact bytes" {
    var output = replies.Buffer.init(std.testing.allocator);
    defer output.deinit();

    try appendQueryReply(&output, std.testing.allocator, "cp", "A\x00B");
    try std.testing.expectEqualStrings("\x1b]52;cp;QQBC\x1b\\", output.bytes());
    output.truncate(0);

    try std.testing.expect(output.setEightBitControls(true));
    try appendQueryReply(&output, std.testing.allocator, "", "");
    try std.testing.expectEqualStrings("\x9d52;;\x9c", output.bytes());
}

test "OSC 52 query failures preserve prior reply bytes" {
    var output = replies.Buffer.init(std.testing.allocator);
    defer output.deinit();
    try output.append("kept");

    const oversized = try std.testing.allocator.alloc(u8, query_reply_bytes_max + 1);
    defer std.testing.allocator.free(oversized);
    @memset(oversized, 'x');
    try std.testing.expectError(
        error.ConsequenceLimit,
        appendQueryReply(&output, std.testing.allocator, "c", oversized),
    );
    try std.testing.expectEqualStrings("kept", output.bytes());

    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(
        error.OutOfMemory,
        appendQueryReply(&output, failing.allocator(), "c", "Howl"),
    );
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectEqualStrings("kept", output.bytes());
}

test "Kitty decoded write accepts the full 64 MiB byte budget without alias duplication" {
    const allocator = std.testing.allocator;
    const writer = try KittyWrite.init(allocator, "type=write:id=large", .clipboard);
    defer writer.deinit();
    const prefix = "type=wdata:mime=YXBwbGljYXRpb24vb2N0ZXQtc3RyZWFt;";
    const raw: [4095]u8 = @splat(0xa5);
    const encoder = std.base64.standard.Encoder;
    var packet: [prefix.len + encoder.calcSize(raw.len)]u8 = undefined;
    @memcpy(packet[0..prefix.len], prefix);
    var remaining: usize = max_write_bytes;
    while (remaining != 0) {
        const count = @min(remaining, raw.len);
        const encoded = encoder.encode(packet[prefix.len..], raw[0..count]);
        try std.testing.expectEqual(KittyWriteProgress.staged, try writer.stage(packet[0 .. prefix.len + encoded.len]));
        remaining -= count;
        try std.testing.expect(writer.contents.bytes.capacity <= max_write_bytes);
    }
    try std.testing.expectEqual(max_write_bytes, writer.contents.bytes.items.len);
    try std.testing.expectEqual(max_write_bytes, writer.contents.bytes.capacity);
    try std.testing.expectEqual(KittyWriteProgress.staged, try writer.stage("type=walias:mime=YXBwbGljYXRpb24vb2N0ZXQtc3RyZWFt;YmluYXJ5"));
    try std.testing.expectEqual(KittyWriteProgress.ready, try writer.stage("type=wdata"));
    var completed = writer.take();
    defer completed.deinit();
    const view = completed.view();
    const bytes = view.get("application/octet-stream").?;
    try std.testing.expectEqual(max_write_bytes, bytes.len);
    try std.testing.expectEqual(bytes.ptr, view.get("binary").?.ptr);
    try std.testing.expect(std.mem.allEqual(u8, bytes, 0xa5));
    try std.testing.expectEqual(@as(usize, 0), writer.contents.bytes.capacity);
}

test "Kitty decoded write refuses the first byte beyond its actual 64 MiB budget" {
    const allocator = std.testing.allocator;
    const writer = try KittyWrite.init(allocator, "type=write:id=large", .clipboard);
    defer writer.deinit();
    const prefix = "type=wdata:mime=YQ==;";
    const raw: [4095]u8 = @splat(0x42);
    const encoder = std.base64.standard.Encoder;
    var packet: [prefix.len + encoder.calcSize(raw.len)]u8 = undefined;
    @memcpy(packet[0..prefix.len], prefix);
    var remaining: usize = max_write_bytes;
    while (remaining != 0) {
        const count = @min(remaining, raw.len);
        const encoded = encoder.encode(packet[prefix.len..], raw[0..count]);
        try std.testing.expectEqual(KittyWriteProgress.staged, try writer.stage(packet[0 .. prefix.len + encoded.len]));
        remaining -= count;
    }
    // Use another MIME: the first group's final padding is already complete.
    try std.testing.expectError(error.ClipboardLimit, writer.stage("type=wdata:mime=Yg==;QQ=="));
    try std.testing.expectEqual(max_write_bytes, writer.contents.bytes.items.len);
    writer.fail(.EFBIG);
    try std.testing.expectEqual(@as(usize, 0), writer.contents.bytes.capacity);
    try std.testing.expectEqual(@as(usize, 0), writer.contents.entries.capacity);
    var output = replies.Buffer.init(allocator);
    defer output.deinit();
    try writer.appendStatus(&output, writer.failure.?);
    try std.testing.expectEqualStrings("\x1b]5522;type=write:status=EFBIG:id=large\x1b\\", output.bytes());
}

test "Kitty write MIME metadata count is bounded independently of payload bytes" {
    const writer = try KittyWrite.init(std.testing.allocator, "type=write", .clipboard);
    defer writer.deinit();
    const encoder = std.base64.standard.Encoder;
    for (0..max_write_mimes + 1) |index| {
        var name: [32]u8 = undefined;
        const mime = try std.fmt.bufPrint(&name, "text/x-{d}", .{index});
        var encoded: [44]u8 = undefined;
        const enc = encoder.encode(&encoded, mime);
        var packet: [96]u8 = undefined;
        const raw = try std.fmt.bufPrint(&packet, "type=wdata:mime={s};", .{enc});
        if (index == max_write_mimes) {
            try std.testing.expectError(error.ClipboardLimit, writer.stage(raw));
        } else {
            try std.testing.expectEqual(KittyWriteProgress.staged, try writer.stage(raw));
        }
    }
    try std.testing.expectEqual(max_write_mimes, writer.contents.entries.items.len);
    try std.testing.expectEqual(max_write_mimes, writer.contents.entries.capacity);
    try std.testing.expectEqual(@as(usize, 0), writer.contents.bytes.items.len);
}
