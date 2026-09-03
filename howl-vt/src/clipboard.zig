//! OSC 52 clipboard grammar, bounded Base64 codec, and child-directed replies.
//!
//! Terminal composition retains validated occurrences through `consequences.zig`;
//! this owner classifies borrowed OSC 52 payloads and performs exact codec work.

const std = @import("std");
const consequences = @import("consequences.zig");
const replies = @import("replies.zig");

/// OSC 52 names four standard selections and eight numbered cut buffers.
const selection_bytes_max: u8 = 12;
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
    const request = parseEnvelope(raw) orelse return null;
    if (request.kind == .set and !validBase64(request.data)) return null;
    return request;
}

/// Allocates and decodes one validated OSC 52 replacement into caller ownership.
pub fn decodeSet(allocator: std.mem.Allocator, raw: []const u8) DecodeError![]u8 {
    const decoded_len = try decodedSetSize(raw);
    const output = try allocator.alloc(u8, @intCast(decoded_len));
    errdefer allocator.free(output);
    std.debug.assert(output.len == decoded_len);
    const written = decodeSetInto(raw, output) catch |failure| switch (failure) {
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

fn decodeSetInto(raw: []const u8, output: []u8) IntoError!u64 {
    const request = parseEnvelope(raw) orelse return error.InvalidOsc52Payload;
    if (request.kind == .query) return error.UnsupportedOsc52Query;
    const decoded_len = try decodedBase64Size(request.data);
    if (output.len < decoded_len) return error.ShortBuffer;
    std.debug.assert(output.len >= decoded_len);
    std.base64.standard.Decoder.decode(output[0..decoded_len], request.data) catch |failure| switch (failure) {
        error.InvalidCharacter => return error.InvalidCharacter,
        error.InvalidPadding => return error.InvalidPadding,
        error.NoSpaceLeft => unreachable,
    };
    return @intCast(decoded_len);
}

fn decodedBase64Size(data: []const u8) error{InvalidPadding}!usize {
    // Size calculation cannot inspect alphabet bytes or consume destination space.
    return std.base64.standard.Decoder.calcSizeForSlice(data) catch |failure| switch (failure) {
        error.InvalidPadding => return error.InvalidPadding,
        error.InvalidCharacter, error.NoSpaceLeft => unreachable,
    };
}

fn parseEnvelope(raw: []const u8) ?ParsedRequest {
    const separator = std.mem.indexOfScalar(u8, raw, ';') orelse return null;
    const selection = raw[0..separator];
    if (selection.len > selection_bytes_max) return null;
    for (selection) |byte| switch (byte) {
        'c', 'p', 'q', 's', '0'...'7' => {},
        else => return null,
    };
    const data = raw[separator + 1 ..];
    return .{
        .selection = selection,
        .data = data,
        .kind = if (std.mem.eql(u8, data, "?")) .query else .set,
    };
}

fn validBase64(data: []const u8) bool {
    if (data.len % 4 != 0) return false;
    var padding: u2 = 0;
    for (data, 0..) |byte, index| switch (byte) {
        'A'...'Z', 'a'...'z', '0'...'9', '+', '/' => if (padding != 0) return false,
        '=' => {
            if (index < data.len -| 2 or padding == 2) return false;
            padding += 1;
        },
        else => return false,
    };
    return true;
}

test "OSC 52 grammar preserves selection and operation identity" {
    const replacement = parse("cp07;SG93bA==").?;
    try std.testing.expectEqualStrings("cp07", replacement.selection);
    try std.testing.expectEqualStrings("SG93bA==", replacement.data);
    try std.testing.expect(replacement.kind == .set);

    const query = parse(";?").?;
    try std.testing.expectEqualStrings("", query.selection);
    try std.testing.expect(query.kind == .query);

    try std.testing.expect(parse("x;SG93bA==") == null);
    try std.testing.expect(parse("c;!!!!") == null);
    try std.testing.expect(parse("c;?trailing") == null);
    try std.testing.expect(parse("ccccccccccccc;") == null);
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
