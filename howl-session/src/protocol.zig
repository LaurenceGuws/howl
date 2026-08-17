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
    semantic_snapshot = 0,
    typed_input = 1,
    resize_leader = 2,
    history_window = 3,
};

/// Returns the negotiated bit mask for one feature.
pub fn feature(feature_value: Feature) u64 {
    return @as(u64, 1) << @backingInt(feature_value);
}

/// Features implemented by the current endpoint contract.
pub const supported_features = feature(.semantic_snapshot) |
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

/// Stable terminal snapshot representation carried by snapshot_data frames.
pub const SnapshotFormat = enum(u16) {
    semantic_cells_v1 = 1,
};

/// Starts one coherent snapshot. All following data/end frames share revision.
pub const SnapshotBegin = struct {
    /// Endpoint observation revision covering VT, lifecycle, and authority state.
    revision: u64,
    /// Canonical VT semantic revision captured inside this observation.
    terminal_revision: u64,
    format: SnapshotFormat = .semantic_cells_v1,
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
    const kind = std.meta.intToEnum(Kind, input[5]) catch return error.UnknownKind;
    const payload_len = readU32(input[8..12]);
    if (payload_len > maximum_payload_bytes) return error.PayloadTooLarge;
    return .{ .kind = kind, .payload_len = payload_len };
}

fn writeU32(output: []u8, value: u32) void {
    std.debug.assert(output.len == 4);
    output[0] = @intCast(value >> 24);
    output[1] = @intCast(value >> 16);
    output[2] = @intCast(value >> 8);
    output[3] = @intCast(value);
}

fn readU32(input: []const u8) u32 {
    std.debug.assert(input.len == 4);
    return (@as(u32, input[0]) << 24) |
        (@as(u32, input[1]) << 16) |
        (@as(u32, input[2]) << 8) |
        @as(u32, input[3]);
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
