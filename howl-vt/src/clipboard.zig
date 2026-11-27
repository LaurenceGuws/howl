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
const KittyStatus = enum { OK, DATA, DONE, ENOSYS, EPERM, EBUSY, EINVAL };
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
