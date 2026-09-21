//! Exact bounded wire contract for managing one Howl server collection.
//!
//! HWLM is deliberately separate from the HWLS Session protocol. A manager
//! owns collection lifecycle; one selected Session continues to own terminal
//! semantics and uses its unchanged Session wire.

const std = @import("std");

pub const framing_version: u8 = 1;
pub const header_bytes: usize = 12;
pub const maximum_request_payload_bytes: usize = 8 * 1024;
pub const maximum_payload_bytes: usize = 16 * 1024;
pub const maximum_sessions: usize = 16;
pub const maximum_name_bytes: usize = 48;
pub const maximum_shell_bytes: usize = 1024;
pub const maximum_command_bytes: usize = 4096;
pub const maximum_cwd_bytes: usize = 1024;
pub const maximum_failure_bytes: usize = 96;

const magic = [4]u8{ 'H', 'W', 'L', 'M' };

pub const Kind = enum(u8) {
    hello = 1,
    welcome = 2,
    status = 3,
    status_snapshot = 4,
    observe_roster = 5,
    roster_snapshot = 6,
    create = 7,
    close = 8,
    attach = 9,
    attach_ready = 10,
    shutdown = 11,
    result = 12,
};

pub const Header = struct {
    kind: Kind,
    payload_len: u32,
};

pub const HeaderError = error{
    InvalidMagic,
    UnsupportedFramingVersion,
    InvalidReservedBits,
    UnknownKind,
    PayloadTooLarge,
};

pub const PayloadError = error{InvalidPayload};
pub const EncodeError = PayloadError || error{OutputTooSmall};

pub const SessionState = enum(u8) {
    running = 1,
    exited = 2,
    failed = 3,
};

pub const ResultCode = enum(u8) {
    ok = 1,
    malformed = 2,
    unsupported = 3,
    not_found = 4,
    name_exists = 5,
    capacity = 6,
    create_failed = 7,
    stale_identity = 8,
    stopping = 9,
    internal = 10,
    unavailable = 11,
};

pub const ServerStatus = struct {
    server_id: u64,
    roster_revision: u64,
    pid: u32,
    session_count: u16,
    capacity: u16,
    stopping: bool,
};

pub const ObserveRoster = struct {
    after_revision: u64,
};

pub const Create = struct {
    name: []const u8,
    shell: ?[]const u8 = null,
    command: ?[]const u8 = null,
    cwd: ?[]const u8 = null,
    rows: u16 = 0,
    columns: u16 = 0,
};

pub const Result = struct {
    request_kind: Kind,
    code: ResultCode,
    session_id: u64 = 0,
    roster_revision: u64 = 0,
};

pub const AttachReady = struct {
    session_id: u64,
    roster_revision: u64,
};

pub const SessionRecord = struct {
    session_id: u64,
    created_sequence: u64,
    state: SessionState,
    name: []const u8,
    failure: []const u8 = "",
};

pub const RosterHeader = struct {
    server_id: u64,
    roster_revision: u64,
    session_count: u16,
    capacity: u16,
    stopping: bool,
};

pub const payload_bytes = struct {
    pub const hello: usize = 0;
    pub const status: usize = 0;
    pub const welcome: usize = 32;
    pub const status_snapshot: usize = 32;
    pub const observe_roster: usize = 8;
    pub const create_header: usize = 12;
    pub const session_identity: usize = 8;
    pub const attach_ready: usize = 16;
    pub const shutdown: usize = 0;
    pub const result: usize = 24;
    pub const roster_header: usize = 24;
    pub const roster_record_header: usize = 20;
};

pub fn encodeHeader(output: *[header_bytes]u8, value: Header) error{PayloadTooLarge}!void {
    if (value.payload_len > maximum_payload_bytes) return error.PayloadTooLarge;
    output.* = @splat(0);
    @memcpy(output[0..4], &magic);
    output[4] = framing_version;
    output[5] = @backingInt(value.kind);
    writeU32(output[8..12], value.payload_len);
}

pub fn decodeHeader(input: *const [header_bytes]u8) HeaderError!Header {
    if (!std.mem.eql(u8, input[0..4], &magic)) return error.InvalidMagic;
    if (input[4] != framing_version) return error.UnsupportedFramingVersion;
    if (input[6] != 0 or input[7] != 0) return error.InvalidReservedBits;
    const kind: Kind = switch (input[5]) {
        1 => .hello,
        2 => .welcome,
        3 => .status,
        4 => .status_snapshot,
        5 => .observe_roster,
        6 => .roster_snapshot,
        7 => .create,
        8 => .close,
        9 => .attach,
        10 => .attach_ready,
        11 => .shutdown,
        12 => .result,
        else => return error.UnknownKind,
    };
    const payload_len = readU32(input[8..12]);
    if (payload_len > maximum_payload_bytes) return error.PayloadTooLarge;
    return .{ .kind = kind, .payload_len = payload_len };
}

pub fn encodeServerStatus(output: *[payload_bytes.status_snapshot]u8, value: ServerStatus) void {
    output.* = @splat(0);
    writeU64(output[0..8], value.server_id);
    writeU64(output[8..16], value.roster_revision);
    writeU32(output[16..20], value.pid);
    writeU16(output[20..22], value.session_count);
    writeU16(output[22..24], value.capacity);
    output[24] = @intFromBool(value.stopping);
}

pub fn decodeServerStatus(input: []const u8) PayloadError!ServerStatus {
    if (input.len != payload_bytes.status_snapshot or !allZero(input[25..32]))
        return error.InvalidPayload;
    if (input[24] > 1) return error.InvalidPayload;
    const value = ServerStatus{
        .server_id = readU64(input[0..8]),
        .roster_revision = readU64(input[8..16]),
        .pid = readU32(input[16..20]),
        .session_count = readU16(input[20..22]),
        .capacity = readU16(input[22..24]),
        .stopping = input[24] != 0,
    };
    if (value.server_id == 0 or value.roster_revision == 0 or value.capacity == 0 or
        value.session_count > value.capacity)
        return error.InvalidPayload;
    return value;
}

pub fn encodeObserveRoster(output: *[payload_bytes.observe_roster]u8, value: ObserveRoster) void {
    writeU64(output, value.after_revision);
}

pub fn decodeObserveRoster(input: []const u8) PayloadError!ObserveRoster {
    if (input.len != payload_bytes.observe_roster) return error.InvalidPayload;
    return .{ .after_revision = readU64(input) };
}

pub fn createEncodedBytes(value: Create) PayloadError!usize {
    try validateCreate(value);
    return payload_bytes.create_header + value.name.len +
        (if (value.shell) |text| text.len else 0) +
        (if (value.command) |text| text.len else 0) +
        (if (value.cwd) |text| text.len else 0);
}

pub fn encodeCreate(output: []u8, value: Create) EncodeError![]const u8 {
    const needed = try createEncodedBytes(value);
    if (output.len < needed) return error.OutputTooSmall;
    const encoded = output[0..needed];
    @memset(encoded[0..payload_bytes.create_header], 0);
    writeU16(encoded[0..2], value.rows);
    writeU16(encoded[2..4], value.columns);
    encoded[4] = @intCast(value.name.len);
    writeU16(encoded[5..7], @intCast(if (value.shell) |text| text.len else 0));
    writeU16(encoded[7..9], @intCast(if (value.command) |text| text.len else 0));
    writeU16(encoded[9..11], @intCast(if (value.cwd) |text| text.len else 0));
    var offset: usize = payload_bytes.create_header;
    @memcpy(encoded[offset .. offset + value.name.len], value.name);
    offset += value.name.len;
    if (value.shell) |text| {
        @memcpy(encoded[offset .. offset + text.len], text);
        offset += text.len;
    }
    if (value.command) |text| {
        @memcpy(encoded[offset .. offset + text.len], text);
        offset += text.len;
    }
    if (value.cwd) |text| @memcpy(encoded[offset .. offset + text.len], text);
    return encoded;
}

pub fn decodeCreate(input: []const u8) PayloadError!Create {
    if (input.len < payload_bytes.create_header or input[11] != 0) return error.InvalidPayload;
    const name_len: usize = input[4];
    const shell_len: usize = readU16(input[5..7]);
    const command_len: usize = readU16(input[7..9]);
    const cwd_len: usize = readU16(input[9..11]);
    const total = payload_bytes.create_header + name_len + shell_len + command_len + cwd_len;
    if (total != input.len) return error.InvalidPayload;
    var offset: usize = payload_bytes.create_header;
    const name = input[offset .. offset + name_len];
    offset += name_len;
    const shell = input[offset .. offset + shell_len];
    offset += shell_len;
    const command = input[offset .. offset + command_len];
    offset += command_len;
    const cwd = input[offset .. offset + cwd_len];
    const value = Create{
        .name = name,
        .shell = if (shell.len == 0) null else shell,
        .command = if (command.len == 0) null else command,
        .cwd = if (cwd.len == 0) null else cwd,
        .rows = readU16(input[0..2]),
        .columns = readU16(input[2..4]),
    };
    try validateCreate(value);
    return value;
}

pub fn encodeSessionIdentity(output: *[payload_bytes.session_identity]u8, session_id: u64) PayloadError!void {
    if (session_id == 0) return error.InvalidPayload;
    writeU64(output, session_id);
}

pub fn decodeSessionIdentity(input: []const u8) PayloadError!u64 {
    if (input.len != payload_bytes.session_identity) return error.InvalidPayload;
    const session_id = readU64(input);
    if (session_id == 0) return error.InvalidPayload;
    return session_id;
}

pub fn encodeAttachReady(output: *[payload_bytes.attach_ready]u8, value: AttachReady) PayloadError!void {
    if (value.session_id == 0 or value.roster_revision == 0) return error.InvalidPayload;
    writeU64(output[0..8], value.session_id);
    writeU64(output[8..16], value.roster_revision);
}

pub fn decodeAttachReady(input: []const u8) PayloadError!AttachReady {
    if (input.len != payload_bytes.attach_ready) return error.InvalidPayload;
    const value = AttachReady{
        .session_id = readU64(input[0..8]),
        .roster_revision = readU64(input[8..16]),
    };
    if (value.session_id == 0 or value.roster_revision == 0) return error.InvalidPayload;
    return value;
}

pub fn encodeResult(output: *[payload_bytes.result]u8, value: Result) PayloadError!void {
    if (!requestKind(value.request_kind)) return error.InvalidPayload;
    if (value.code == .ok and value.request_kind == .create and value.session_id == 0)
        return error.InvalidPayload;
    output.* = @splat(0);
    output[0] = @backingInt(value.request_kind);
    output[1] = @backingInt(value.code);
    writeU64(output[8..16], value.session_id);
    writeU64(output[16..24], value.roster_revision);
}

pub fn decodeResult(input: []const u8) PayloadError!Result {
    if (input.len != payload_bytes.result or !allZero(input[2..8])) return error.InvalidPayload;
    const request_kind: Kind = switch (input[0]) {
        3 => .status,
        5 => .observe_roster,
        7 => .create,
        8 => .close,
        9 => .attach,
        11 => .shutdown,
        else => return error.InvalidPayload,
    };
    const code: ResultCode = switch (input[1]) {
        1 => .ok,
        2 => .malformed,
        3 => .unsupported,
        4 => .not_found,
        5 => .name_exists,
        6 => .capacity,
        7 => .create_failed,
        8 => .stale_identity,
        9 => .stopping,
        10 => .internal,
        11 => .unavailable,
        else => return error.InvalidPayload,
    };
    const value = Result{
        .request_kind = request_kind,
        .code = code,
        .session_id = readU64(input[8..16]),
        .roster_revision = readU64(input[16..24]),
    };
    if (value.code == .ok and value.request_kind == .create and value.session_id == 0)
        return error.InvalidPayload;
    return value;
}

pub fn encodeRosterHeader(output: *[payload_bytes.roster_header]u8, value: RosterHeader) PayloadError!void {
    if (value.server_id == 0 or value.roster_revision == 0 or value.capacity == 0 or
        value.session_count > value.capacity or value.capacity > maximum_sessions)
        return error.InvalidPayload;
    output.* = @splat(0);
    writeU64(output[0..8], value.server_id);
    writeU64(output[8..16], value.roster_revision);
    writeU16(output[16..18], value.session_count);
    writeU16(output[18..20], value.capacity);
    output[20] = @intFromBool(value.stopping);
}

pub fn decodeRosterHeader(input: []const u8) PayloadError!RosterHeader {
    if (input.len != payload_bytes.roster_header or !allZero(input[21..24]) or input[20] > 1)
        return error.InvalidPayload;
    const value = RosterHeader{
        .server_id = readU64(input[0..8]),
        .roster_revision = readU64(input[8..16]),
        .session_count = readU16(input[16..18]),
        .capacity = readU16(input[18..20]),
        .stopping = input[20] != 0,
    };
    if (value.server_id == 0 or value.roster_revision == 0 or value.capacity == 0 or
        value.session_count > value.capacity or value.capacity > maximum_sessions)
        return error.InvalidPayload;
    return value;
}

pub fn rosterRecordEncodedBytes(value: SessionRecord) PayloadError!usize {
    try validateSessionRecord(value);
    return payload_bytes.roster_record_header + value.name.len + value.failure.len;
}

pub fn encodeRosterRecord(output: []u8, value: SessionRecord) EncodeError![]const u8 {
    const needed = try rosterRecordEncodedBytes(value);
    if (output.len < needed) return error.OutputTooSmall;
    const encoded = output[0..needed];
    @memset(encoded[0..payload_bytes.roster_record_header], 0);
    writeU64(encoded[0..8], value.session_id);
    writeU64(encoded[8..16], value.created_sequence);
    encoded[16] = @backingInt(value.state);
    encoded[17] = @intCast(value.name.len);
    encoded[18] = @intCast(value.failure.len);
    @memcpy(encoded[20 .. 20 + value.name.len], value.name);
    @memcpy(encoded[20 + value.name.len ..], value.failure);
    return encoded;
}

pub const DecodedRosterRecord = struct {
    record: SessionRecord,
    encoded_bytes: usize,
};

pub fn decodeRosterRecord(input: []const u8) PayloadError!DecodedRosterRecord {
    if (input.len < payload_bytes.roster_record_header or input[19] != 0)
        return error.InvalidPayload;
    const name_len: usize = input[17];
    const failure_len: usize = input[18];
    const total = payload_bytes.roster_record_header + name_len + failure_len;
    if (total > input.len) return error.InvalidPayload;
    const value = SessionRecord{
        .session_id = readU64(input[0..8]),
        .created_sequence = readU64(input[8..16]),
        .state = switch (input[16]) {
            1 => .running,
            2 => .exited,
            3 => .failed,
            else => return error.InvalidPayload,
        },
        .name = input[20 .. 20 + name_len],
        .failure = input[20 + name_len .. total],
    };
    try validateSessionRecord(value);
    return .{ .record = value, .encoded_bytes = total };
}

fn validateCreate(value: Create) PayloadError!void {
    if (!validName(value.name) or (value.rows == 0) != (value.columns == 0))
        return error.InvalidPayload;
    if (value.shell) |text| if (!validText(text, maximum_shell_bytes)) return error.InvalidPayload;
    if (value.command) |text| if (!validText(text, maximum_command_bytes)) return error.InvalidPayload;
    if (value.cwd) |text| if (!validText(text, maximum_cwd_bytes)) return error.InvalidPayload;
}

fn validateSessionRecord(value: SessionRecord) PayloadError!void {
    if (value.session_id == 0 or value.created_sequence == 0 or !validName(value.name) or
        value.failure.len > maximum_failure_bytes or
        std.mem.indexOfScalar(u8, value.failure, 0) != null or
        !std.unicode.utf8ValidateSlice(value.failure))
        return error.InvalidPayload;
    if (value.state == .failed and value.failure.len == 0) return error.InvalidPayload;
    if (value.state != .failed and value.failure.len != 0) return error.InvalidPayload;
}

pub fn validName(name: []const u8) bool {
    if (name.len == 0 or name.len > maximum_name_bytes) return false;
    for (name) |byte| {
        if (std.ascii.isAlphanumeric(byte) or byte == '-' or byte == '_' or byte == '.') continue;
        return false;
    }
    return true;
}

fn validText(text: []const u8, maximum: usize) bool {
    return text.len != 0 and text.len <= maximum and std.mem.indexOfScalar(u8, text, 0) == null and
        std.unicode.utf8ValidateSlice(text);
}

fn requestKind(kind: Kind) bool {
    return switch (kind) {
        .status, .observe_roster, .create, .close, .attach, .shutdown => true,
        else => false,
    };
}

fn allZero(bytes: []const u8) bool {
    for (bytes) |byte| if (byte != 0) return false;
    return true;
}

fn writeU16(output: []u8, value: u16) void {
    std.debug.assert(output.len == 2);
    output[0] = @truncate(value >> 8);
    output[1] = @truncate(value);
}

fn readU16(input: []const u8) u16 {
    std.debug.assert(input.len == 2);
    return @as(u16, input[0]) << 8 | input[1];
}

fn writeU32(output: []u8, value: u32) void {
    std.debug.assert(output.len == 4);
    output[0] = @truncate(value >> 24);
    output[1] = @truncate(value >> 16);
    output[2] = @truncate(value >> 8);
    output[3] = @truncate(value);
}

fn readU32(input: []const u8) u32 {
    std.debug.assert(input.len == 4);
    return @as(u32, input[0]) << 24 | @as(u32, input[1]) << 16 |
        @as(u32, input[2]) << 8 | input[3];
}

fn writeU64(output: []u8, value: u64) void {
    std.debug.assert(output.len == 8);
    var shift: u6 = 56;
    for (output) |*byte| {
        byte.* = @truncate(value >> shift);
        shift -|= 8;
    }
}

fn readU64(input: []const u8) u64 {
    std.debug.assert(input.len == 8);
    var value: u64 = 0;
    for (input) |byte| value = value << 8 | byte;
    return value;
}

test "header rejects wrong wire identity reserved bits and bounds" {
    var encoded: [header_bytes]u8 = undefined;
    try encodeHeader(&encoded, .{ .kind = .observe_roster, .payload_len = 8 });
    const decoded = try decodeHeader(&encoded);
    try std.testing.expectEqual(Kind.observe_roster, decoded.kind);
    try std.testing.expectEqual(@as(u32, 8), decoded.payload_len);

    var wrong_magic = encoded;
    wrong_magic[0] = 'X';
    try std.testing.expectError(error.InvalidMagic, decodeHeader(&wrong_magic));
    var wrong_version = encoded;
    wrong_version[4] +%= 1;
    try std.testing.expectError(error.UnsupportedFramingVersion, decodeHeader(&wrong_version));
    var reserved = encoded;
    reserved[6] = 1;
    try std.testing.expectError(error.InvalidReservedBits, decodeHeader(&reserved));
    try std.testing.expectError(
        error.PayloadTooLarge,
        encodeHeader(&encoded, .{ .kind = .create, .payload_len = maximum_payload_bytes + 1 }),
    );
}

test "server status round trips and rejects malformed reserved state" {
    const expected = ServerStatus{
        .server_id = 91,
        .roster_revision = 7,
        .pid = 1234,
        .session_count = 3,
        .capacity = 16,
        .stopping = true,
    };
    var encoded: [payload_bytes.status_snapshot]u8 = undefined;
    encodeServerStatus(&encoded, expected);
    try std.testing.expectEqualDeep(expected, try decodeServerStatus(&encoded));
    encoded[31] = 1;
    try std.testing.expectError(error.InvalidPayload, decodeServerStatus(&encoded));
}

test "create request round trips optional launch fields and validates names" {
    const expected = Create{
        .name = "work.2",
        .shell = "/bin/bash",
        .command = "printf ready",
        .cwd = "/srv/work",
        .rows = 32,
        .columns = 120,
    };
    var storage: [maximum_request_payload_bytes]u8 = undefined;
    const encoded = try encodeCreate(&storage, expected);
    const decoded = try decodeCreate(encoded);
    try std.testing.expectEqualStrings(expected.name, decoded.name);
    try std.testing.expectEqualStrings(expected.shell.?, decoded.shell.?);
    try std.testing.expectEqualStrings(expected.command.?, decoded.command.?);
    try std.testing.expectEqualStrings(expected.cwd.?, decoded.cwd.?);
    try std.testing.expectEqual(expected.rows, decoded.rows);
    try std.testing.expectEqual(expected.columns, decoded.columns);

    const defaults = try decodeCreate(try encodeCreate(&storage, .{ .name = "main" }));
    try std.testing.expect(defaults.shell == null and defaults.command == null and defaults.cwd == null);
    try std.testing.expectError(error.InvalidPayload, createEncodedBytes(.{ .name = "../escape" }));
    try std.testing.expectError(error.InvalidPayload, createEncodedBytes(.{ .name = "bad", .rows = 24 }));
}

test "result requires exact request kind and create identity" {
    var encoded: [payload_bytes.result]u8 = undefined;
    try encodeResult(&encoded, .{
        .request_kind = .create,
        .code = .ok,
        .session_id = 42,
        .roster_revision = 9,
    });
    try std.testing.expectEqualDeep(
        Result{ .request_kind = .create, .code = .ok, .session_id = 42, .roster_revision = 9 },
        try decodeResult(&encoded),
    );
    try std.testing.expectError(
        error.InvalidPayload,
        encodeResult(&encoded, .{ .request_kind = .create, .code = .ok, .roster_revision = 9 }),
    );
}

test "attach ready binds one exact session identity and roster cut" {
    var encoded: [payload_bytes.attach_ready]u8 = undefined;
    try encodeAttachReady(&encoded, .{ .session_id = 17, .roster_revision = 42 });
    try std.testing.expectEqualDeep(
        AttachReady{ .session_id = 17, .roster_revision = 42 },
        try decodeAttachReady(&encoded),
    );
    try std.testing.expectError(
        error.InvalidPayload,
        encodeAttachReady(&encoded, .{ .session_id = 0, .roster_revision = 42 }),
    );
}

test "roster records are bounded borrowed facts with explicit failed state" {
    const expected = SessionRecord{
        .session_id = 44,
        .created_sequence = 3,
        .state = .failed,
        .name = "logs",
        .failure = "AcceptFailed",
    };
    var storage: [256]u8 = undefined;
    const encoded = try encodeRosterRecord(&storage, expected);
    const decoded = try decodeRosterRecord(encoded);
    try std.testing.expectEqual(encoded.len, decoded.encoded_bytes);
    try std.testing.expectEqual(expected.session_id, decoded.record.session_id);
    try std.testing.expectEqual(expected.created_sequence, decoded.record.created_sequence);
    try std.testing.expectEqual(expected.state, decoded.record.state);
    try std.testing.expectEqualStrings(expected.name, decoded.record.name);
    try std.testing.expectEqualStrings(expected.failure, decoded.record.failure);
    try std.testing.expectError(
        error.InvalidPayload,
        rosterRecordEncodedBytes(.{
            .session_id = 1,
            .created_sequence = 1,
            .state = .running,
            .name = "ok",
            .failure = "should-not-exist",
        }),
    );
}
