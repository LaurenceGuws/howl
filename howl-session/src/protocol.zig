//! Small transport-neutral contract for attaching to one shared Howl session.
//!
//! The wire is request-driven. A client has at most one outstanding `observe`
//! request. The endpoint answers with one coherent snapshot at a single
//! revision, then the client asks again from that revision. This deliberately
//! avoids a server-side stream queue per observer: slow clients may see a newer
//! snapshot later, but they never pace PTY or VT progress.
//!
//! An endpoint must copy/materialize the requested snapshot before it emits
//! `snapshot_begin`. PTY/VT work may continue while those copied bytes drain to
//! the client. `snapshot_end.revision` closes that exact cut; the client's next
//! `observe.after_revision` starts after it. Revision zero always requests an
//! immediate snapshot, which also gives history scrolling a non-waiting path.

const std = @import("std");

/// Version of the fixed frame header, independent of session protocol versions.
pub const framing_version: u8 = 1;
/// Oldest session protocol this implementation can negotiate.
pub const protocol_min_version: u16 = 1;
/// Newest session protocol this implementation can negotiate.
pub const protocol_max_version: u16 = 1;
/// Exact byte width of every frame header.
pub const header_bytes: usize = 12;
/// Hard upper bound admitted for one frame payload.
pub const maximum_payload_bytes: u32 = 1024 * 1024;
/// Hard upper bound materialized for one observer snapshot response.
pub const maximum_snapshot_bytes: usize = 4 * 1024 * 1024;
/// Sentinel used only where an optional client identity is serialized.
pub const no_client: ClientId = 0;

const magic = [4]u8{ 'H', 'W', 'L', 'S' };

/// Stable connection-local identity. Zero means no client/leader.
pub const ClientId = u64;

/// Frames carried unchanged over a Unix socket or an SSH stdio bridge.
pub const Kind = enum(u8) {
    hello = 1,
    welcome = 2,
    observe = 3,
    snapshot_begin = 4,
    snapshot_data = 5,
    snapshot_end = 6,
    input = 7,
    assign_leader = 8,
    resize = 9,
    signal = 10,
    result = 11,
};

/// Features are negotiated independently of protocol version.
pub const Feature = enum(u6) {
    grid_snapshot = 0,
    typed_input = 1,
    resize_leader = 2,
    history_window = 3,
};

/// Returns the negotiated bit mask for one feature.
pub fn feature(feature_value: Feature) u64 {
    return @as(u64, 1) << @backingInt(feature_value);
}

/// Features implemented by the current endpoint contract.
pub const supported_features = feature(.grid_snapshot) |
    feature(.resize_leader) |
    feature(.history_window);

/// One fixed framing header. Multi-byte integers are big-endian on the wire.
pub const Header = struct {
    kind: Kind,
    payload_len: u32,
};

/// Rejects malformed or unsupported framing before payload allocation/read.
pub const HeaderError = error{
    InvalidMagic,
    UnsupportedFramingVersion,
    InvalidReservedBits,
    UnknownKind,
    PayloadTooLarge,
};

/// Rejects a fixed message payload whose size or enum values are invalid.
pub const PayloadError = error{InvalidPayload};

/// Handshake sent before any session request.
pub const Hello = struct {
    min_version: u16 = protocol_min_version,
    max_version: u16 = protocol_max_version,
    features: u64 = supported_features,
};

/// Handshake response. Clients only learn their own identity by default.
pub const Welcome = struct {
    version: u16,
    features: u64,
    client_id: ClientId,
};

/// Long-poll style observation request. Revision zero means initial attach.
pub const Observe = struct {
    after_revision: u64 = 0,
    history_offset: u32 = 0,
};

/// Input payload family. Structured key/mouse input is capability-gated.
pub const InputKind = enum(u8) {
    bytes = 1,
    paste = 2,
    key = 3,
    mouse = 4,
    focus = 5,
};

/// Signals accepted by the session process-group boundary.
pub const Signal = enum(u8) {
    hangup = 1,
    interrupt = 2,
    resize_notify = 3,
    kill = 9,
    terminate = 15,
};

/// Bounded request outcome without transporting host-specific errno values.
pub const ResultCode = enum(u8) {
    ok = 0,
    malformed = 1,
    unsupported = 2,
    no_such_client = 3,
    not_leader = 4,
    rejected = 5,
};

/// Correlates one command response by its request kind.
pub const Result = struct {
    request_kind: Kind,
    code: ResultCode,
};

/// Stable first terminal snapshot representation carried by snapshot_data frames.
///
/// `grid_v1` intentionally freezes only the canonical spatial grid needed by
/// the first shared-session client: row wrap/DEC geometry and each cell's
/// codepoint plus multicell occupancy. Styling, complete grapheme sidecars,
/// images, and presentation defaults remain future negotiated formats.
pub const SnapshotFormat = enum(u16) {
    grid_v1 = 1,
};

/// Starts one coherent snapshot. All following data/end frames share revision.
pub const SnapshotBegin = struct {
    /// Endpoint observation revision covering VT, lifecycle, and authority state.
    revision: u64,
    /// Canonical VT semantic revision captured inside this observation.
    terminal_revision: u64,
    format: SnapshotFormat = .grid_v1,
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

/// Completes one snapshot and makes its revision valid for the next observe.
pub const SnapshotEnd = struct {
    revision: u64,
};

/// Explicit geometry request. The endpoint accepts it only from the leader.
pub const Resize = struct {
    rows: u16,
    columns: u16,
};

/// Explicit leader assignment. `no_client` clears leadership.
pub const AssignLeader = struct {
    client_id: ClientId,
};

/// Exact fixed payload widths for v1 messages.
pub const payload_bytes = struct {
    /// `Hello` payload bytes.
    pub const hello: usize = 12;
    /// `Welcome` payload bytes.
    pub const welcome: usize = 18;
    /// `Observe` payload bytes.
    pub const observe: usize = 12;
    /// `SnapshotBegin` payload bytes.
    pub const snapshot_begin: usize = 40;
    /// `SnapshotEnd` payload bytes.
    pub const snapshot_end: usize = 8;
    /// `AssignLeader` payload bytes.
    pub const assign_leader: usize = 8;
    /// `Resize` payload bytes.
    pub const resize: usize = 4;
    /// `Signal` payload bytes.
    pub const signal: usize = 1;
    /// `Result` payload bytes.
    pub const result: usize = 2;
};

/// Owns only geometry authority. Client discovery/rosters remain endpoint policy.
pub const ResizeAuthority = struct {
    leader_client_id: ClientId = no_client,
    revision: u64 = 1,

    /// Returns the current leader, if explicit geometry authority exists.
    pub fn leader(self: ResizeAuthority) ?ClientId {
        return if (self.leader_client_id == no_client) null else self.leader_client_id;
    }

    /// Replaces or clears the leader and reports whether authority changed.
    pub fn assign(self: *ResizeAuthority, client_id: ClientId) bool {
        if (self.leader_client_id == client_id) return false;
        self.leader_client_id = client_id;
        advance(&self.revision);
        return true;
    }

    /// Clears leadership only when the disconnected client currently owns it.
    pub fn disconnected(self: *ResizeAuthority, client_id: ClientId) bool {
        if (client_id == no_client or self.leader_client_id != client_id) return false;
        self.leader_client_id = no_client;
        advance(&self.revision);
        return true;
    }

    /// Reports whether one attached client may mutate canonical geometry.
    pub fn mayResize(self: ResizeAuthority, client_id: ClientId) bool {
        return client_id != no_client and self.leader_client_id == client_id;
    }
};

/// Selects the highest mutually supported protocol version.
pub fn negotiateVersion(hello: Hello) ?u16 {
    if (hello.min_version > hello.max_version) return null;
    const lower = @max(hello.min_version, protocol_min_version);
    const upper = @min(hello.max_version, protocol_max_version);
    return if (lower <= upper) upper else null;
}

/// Returns the features both peers can use for the negotiated connection.
pub fn negotiateFeatures(hello: Hello) u64 {
    return hello.features & supported_features;
}

/// Encodes one hello payload with explicit endian order.
pub fn encodeHello(output: *[payload_bytes.hello]u8, value: Hello) void {
    writeU16(output[0..2], value.min_version);
    writeU16(output[2..4], value.max_version);
    writeU64(output[4..12], value.features);
}

/// Decodes one exact hello payload.
pub fn decodeHello(input: []const u8) PayloadError!Hello {
    if (input.len != payload_bytes.hello) return error.InvalidPayload;
    return .{
        .min_version = readU16(input[0..2]),
        .max_version = readU16(input[2..4]),
        .features = readU64(input[4..12]),
    };
}

/// Encodes one welcome payload with explicit endian order.
pub fn encodeWelcome(output: *[payload_bytes.welcome]u8, value: Welcome) void {
    writeU16(output[0..2], value.version);
    writeU64(output[2..10], value.features);
    writeU64(output[10..18], value.client_id);
}

/// Decodes one exact welcome payload.
pub fn decodeWelcome(input: []const u8) PayloadError!Welcome {
    if (input.len != payload_bytes.welcome) return error.InvalidPayload;
    return .{
        .version = readU16(input[0..2]),
        .features = readU64(input[2..10]),
        .client_id = readU64(input[10..18]),
    };
}

/// Encodes one observation request.
pub fn encodeObserve(output: *[payload_bytes.observe]u8, value: Observe) void {
    writeU64(output[0..8], value.after_revision);
    writeU32(output[8..12], value.history_offset);
}

/// Decodes one exact observation request.
pub fn decodeObserve(input: []const u8) PayloadError!Observe {
    if (input.len != payload_bytes.observe) return error.InvalidPayload;
    return .{
        .after_revision = readU64(input[0..8]),
        .history_offset = readU32(input[8..12]),
    };
}

/// Encodes one snapshot metadata boundary.
pub fn encodeSnapshotBegin(output: *[payload_bytes.snapshot_begin]u8, value: SnapshotBegin) void {
    output.* = @splat(0);
    writeU64(output[0..8], value.revision);
    writeU64(output[8..16], value.terminal_revision);
    writeU16(output[16..18], @backingInt(value.format));
    writeU32(output[18..22], value.history_offset);
    writeU32(output[22..26], value.history_count);
    writeU32(output[26..30], value.history_row_base);
    writeU16(output[30..32], value.rows);
    writeU16(output[32..34], value.columns);
    writeU16(output[34..36], value.cursor_row);
    writeU16(output[36..38], value.cursor_column);
    output[38] = value.cursor_shape;
    output[39] = (@as(u8, @intFromBool(value.cursor_visible)) << 0) |
        (@as(u8, @intFromBool(value.cursor_blink)) << 1) |
        (@as(u8, @intFromBool(value.alternate_screen)) << 2) |
        (@as(u8, @intFromBool(value.stream_closed)) << 3) |
        (@as(u8, @intFromBool(value.child_exited)) << 4) |
        (@as(u8, @intFromBool(value.leader_present)) << 5) |
        (@as(u8, @intFromBool(value.you_are_leader)) << 6);
}

/// Decodes one exact snapshot metadata boundary.
pub fn decodeSnapshotBegin(input: []const u8) PayloadError!SnapshotBegin {
    if (input.len != payload_bytes.snapshot_begin) return error.InvalidPayload;
    const format = enumFromInt(SnapshotFormat, readU16(input[16..18])) orelse
        return error.InvalidPayload;
    if (input[39] & 0x80 != 0) return error.InvalidPayload;
    return .{
        .revision = readU64(input[0..8]),
        .terminal_revision = readU64(input[8..16]),
        .format = format,
        .history_offset = readU32(input[18..22]),
        .history_count = readU32(input[22..26]),
        .history_row_base = readU32(input[26..30]),
        .rows = readU16(input[30..32]),
        .columns = readU16(input[32..34]),
        .cursor_row = readU16(input[34..36]),
        .cursor_column = readU16(input[36..38]),
        .cursor_shape = input[38],
        .cursor_visible = input[39] & (1 << 0) != 0,
        .cursor_blink = input[39] & (1 << 1) != 0,
        .alternate_screen = input[39] & (1 << 2) != 0,
        .stream_closed = input[39] & (1 << 3) != 0,
        .child_exited = input[39] & (1 << 4) != 0,
        .leader_present = input[39] & (1 << 5) != 0,
        .you_are_leader = input[39] & (1 << 6) != 0,
    };
}

/// Encodes one completed snapshot revision.
pub fn encodeSnapshotEnd(output: *[payload_bytes.snapshot_end]u8, value: SnapshotEnd) void {
    writeU64(output, value.revision);
}

/// Decodes one completed snapshot revision.
pub fn decodeSnapshotEnd(input: []const u8) PayloadError!SnapshotEnd {
    if (input.len != payload_bytes.snapshot_end) return error.InvalidPayload;
    return .{ .revision = readU64(input) };
}

/// Encodes one explicit geometry-leader assignment.
pub fn encodeAssignLeader(output: *[payload_bytes.assign_leader]u8, value: AssignLeader) void {
    writeU64(output, value.client_id);
}

/// Decodes one explicit geometry-leader assignment.
pub fn decodeAssignLeader(input: []const u8) PayloadError!AssignLeader {
    if (input.len != payload_bytes.assign_leader) return error.InvalidPayload;
    return .{ .client_id = readU64(input) };
}

/// Encodes one explicit canonical geometry.
pub fn encodeResize(output: *[payload_bytes.resize]u8, value: Resize) void {
    writeU16(output[0..2], value.rows);
    writeU16(output[2..4], value.columns);
}

/// Decodes one explicit canonical geometry.
pub fn decodeResize(input: []const u8) PayloadError!Resize {
    if (input.len != payload_bytes.resize) return error.InvalidPayload;
    return .{ .rows = readU16(input[0..2]), .columns = readU16(input[2..4]) };
}

/// Encodes one fixed process-group signal.
pub fn encodeSignal(output: *[payload_bytes.signal]u8, value: Signal) void {
    output[0] = @backingInt(value);
}

/// Decodes one fixed process-group signal.
pub fn decodeSignal(input: []const u8) PayloadError!Signal {
    if (input.len != payload_bytes.signal) return error.InvalidPayload;
    return enumFromInt(Signal, input[0]) orelse error.InvalidPayload;
}

/// Encodes one bounded command result.
pub fn encodeResult(output: *[payload_bytes.result]u8, value: Result) void {
    output[0] = @backingInt(value.request_kind);
    output[1] = @backingInt(value.code);
}

/// Decodes one bounded command result.
pub fn decodeResult(input: []const u8) PayloadError!Result {
    if (input.len != payload_bytes.result) return error.InvalidPayload;
    return .{
        .request_kind = enumFromInt(Kind, input[0]) orelse return error.InvalidPayload,
        .code = enumFromInt(ResultCode, input[1]) orelse return error.InvalidPayload,
    };
}

/// Encodes one fixed header without allocation.
pub fn encodeHeader(output: *[header_bytes]u8, header: Header) error{PayloadTooLarge}!void {
    if (header.payload_len > maximum_payload_bytes) return error.PayloadTooLarge;
    output.* = @splat(0);
    @memcpy(output[0..4], &magic);
    output[4] = framing_version;
    output[5] = @backingInt(header.kind);
    writeU32(output[8..12], header.payload_len);
}

/// Decodes and validates one fixed header before any payload is admitted.
pub fn decodeHeader(input: *const [header_bytes]u8) HeaderError!Header {
    if (!std.mem.eql(u8, input[0..4], &magic)) return error.InvalidMagic;
    if (input[4] != framing_version) return error.UnsupportedFramingVersion;
    if (input[6] != 0 or input[7] != 0) return error.InvalidReservedBits;
    const kind = enumFromInt(Kind, input[5]) orelse return error.UnknownKind;
    const payload_len = readU32(input[8..12]);
    if (payload_len > maximum_payload_bytes) return error.PayloadTooLarge;
    return .{ .kind = kind, .payload_len = payload_len };
}

fn writeU32(output: []u8, value: u32) void {
    std.debug.assert(output.len == 4);
    output[0] = @truncate(value >> 24);
    output[1] = @truncate(value >> 16);
    output[2] = @truncate(value >> 8);
    output[3] = @truncate(value);
}

fn writeU16(output: []u8, value: u16) void {
    std.debug.assert(output.len == 2);
    output[0] = @truncate(value >> 8);
    output[1] = @truncate(value);
}

fn writeU64(output: []u8, value: u64) void {
    std.debug.assert(output.len == 8);
    var shift: u6 = 56;
    for (output) |*byte| {
        byte.* = @truncate(value >> shift);
        shift -|= 8;
    }
}

fn readU32(input: []const u8) u32 {
    std.debug.assert(input.len == 4);
    return (@as(u32, input[0]) << 24) |
        (@as(u32, input[1]) << 16) |
        (@as(u32, input[2]) << 8) |
        @as(u32, input[3]);
}

fn readU16(input: []const u8) u16 {
    std.debug.assert(input.len == 2);
    return (@as(u16, input[0]) << 8) | @as(u16, input[1]);
}

fn readU64(input: []const u8) u64 {
    std.debug.assert(input.len == 8);
    var value: u64 = 0;
    for (input) |byte| value = (value << 8) | @as(u64, byte);
    return value;
}

fn enumFromInt(comptime Enum: type, value: @typeInfo(Enum).@"enum".tag_type) ?Enum {
    const info = @typeInfo(Enum).@"enum";
    inline for (info.field_values) |field_value| {
        if (value == field_value) return @fromBackingInt(@intCast(value));
    }
    return null;
}

fn advance(value: *u64) void {
    value.* = std.math.add(u64, value.*, 1) catch @panic("protocol revision exhausted");
}

test "header round trips and rejects framing ambiguity" {
    var bytes: [header_bytes]u8 = undefined;
    try encodeHeader(&bytes, .{ .kind = .observe, .payload_len = 1234 });
    const decoded = try decodeHeader(&bytes);
    try std.testing.expectEqual(Kind.observe, decoded.kind);
    try std.testing.expectEqual(@as(u32, 1234), decoded.payload_len);

    var invalid = bytes;
    invalid[6] = 1;
    try std.testing.expectError(error.InvalidReservedBits, decodeHeader(&invalid));
    invalid = bytes;
    invalid[5] = 0xff;
    try std.testing.expectError(error.UnknownKind, decodeHeader(&invalid));
}

test "wire integers round trip beyond one byte" {
    var header_bytes_out: [header_bytes]u8 = undefined;
    try encodeHeader(&header_bytes_out, .{ .kind = .snapshot_data, .payload_len = 0x00f1_a2b3 });
    const header = try decodeHeader(&header_bytes_out);
    try std.testing.expectEqual(@as(u32, 0x00f1_a2b3), header.payload_len);

    var hello_bytes: [payload_bytes.hello]u8 = undefined;
    const hello = Hello{
        .min_version = 0x0123,
        .max_version = 0x4567,
        .features = 0xf123_4567_89ab_cdef,
    };
    encodeHello(&hello_bytes, hello);
    const decoded_hello = try decodeHello(&hello_bytes);
    try std.testing.expectEqual(hello.min_version, decoded_hello.min_version);
    try std.testing.expectEqual(hello.max_version, decoded_hello.max_version);
    try std.testing.expectEqual(hello.features, decoded_hello.features);

    var resize_bytes: [payload_bytes.resize]u8 = undefined;
    encodeResize(&resize_bytes, .{ .rows = 512, .columns = 1025 });
    const resize = try decodeResize(&resize_bytes);
    try std.testing.expectEqual(@as(u16, 512), resize.rows);
    try std.testing.expectEqual(@as(u16, 1025), resize.columns);
}

test "version negotiation is explicit before protocol v1" {
    try std.testing.expectEqual(@as(?u16, 1), negotiateVersion(.{}));
    try std.testing.expectEqual(@as(?u16, 1), negotiateVersion(.{ .min_version = 0, .max_version = 2 }));
    try std.testing.expectEqual(@as(?u16, null), negotiateVersion(.{ .min_version = 2, .max_version = 3 }));
    try std.testing.expectEqual(@as(?u16, null), negotiateVersion(.{ .min_version = 2, .max_version = 1 }));
    try std.testing.expectEqual(supported_features, negotiateFeatures(.{}));
    try std.testing.expectEqual(feature(.resize_leader), negotiateFeatures(.{
        .features = feature(.resize_leader) | feature(.typed_input),
    }));
}

test "resize leadership is explicit and disappears with its client" {
    var authority: ResizeAuthority = .{};
    try std.testing.expect(authority.leader() == null);
    try std.testing.expect(!authority.mayResize(7));

    const before = authority.revision;
    try std.testing.expect(authority.assign(7));
    try std.testing.expectEqual(before + 1, authority.revision);
    try std.testing.expect(authority.mayResize(7));
    try std.testing.expect(!authority.mayResize(8));
    try std.testing.expect(!authority.assign(7));

    try std.testing.expect(!authority.disconnected(8));
    try std.testing.expect(authority.disconnected(7));
    try std.testing.expect(authority.leader() == null);
    try std.testing.expect(!authority.mayResize(7));
}
