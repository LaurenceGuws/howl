//! Bounded transport-neutral control wire for Server -> Sessions -> Instances.
//!
//! This protocol owns orchestration vocabulary only. HWLS remains the interaction
//! protocol of one concrete Instance after exact Session+Instance attachment.
//! Session creation contains no shell, command, cwd or terminal geometry.

const std = @import("std");

pub const framing_version: u8 = 1;
pub const header_bytes: usize = 12;
pub const maximum_request_payload_bytes: usize = 8 * 1024;
pub const maximum_payload_bytes: usize = 8 * 1024;
pub const maximum_sessions: u16 = 16;
pub const maximum_instances_per_session: u16 = 16;
pub const maximum_session_name_bytes: usize = 64;
pub const maximum_shell_bytes: usize = 1024;
pub const maximum_command_bytes: usize = 4096;
pub const maximum_cwd_bytes: usize = 1024;

const magic = [4]u8{ 'S', 'R', 'V', 'R' };

pub const Kind = enum(u8) {
    hello = 1,
    welcome = 2,
    status = 3,
    status_snapshot = 4,
    observe_tree = 5,
    tree_snapshot = 6,
    create_session = 7,
    close_session = 8,
    create_instance = 9,
    close_instance = 10,
    attach_instance = 11,
    attach_ready = 12,
    result = 13,
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

pub const InstanceState = enum(u8) {
    running = 1,
    exited = 2,
};

pub const ResultCode = enum(u8) {
    ok = 1,
    malformed = 2,
    unsupported = 3,
    session_not_found = 4,
    instance_not_found = 5,
    name_exists = 6,
    session_capacity = 7,
    instance_capacity = 8,
    create_failed = 9,
    unavailable = 10,
    internal = 11,
};

pub const Status = struct {
    server_id: u64,
    tree_revision: u64,
    session_count: u16,
    instance_count: u16,
    session_capacity: u16 = maximum_sessions,
    instances_per_session: u16 = maximum_instances_per_session,
};

pub const ObserveTree = struct {
    after_revision: u64,
};

pub const CreateSession = struct {
    name: []const u8,
};

pub const InstanceIdentity = struct {
    session_id: u64,
    instance_id: u64,
};

pub const CreateInstance = struct {
    session_id: u64,
    shell: []const u8,
    command: ?[]const u8 = null,
    cwd: ?[]const u8 = null,
    rows: u16,
    columns: u16,
    history_rows: u16,
};

pub const Result = struct {
    request_kind: Kind,
    code: ResultCode,
    session_id: u64 = 0,
    instance_id: u64 = 0,
    tree_revision: u64 = 0,
};

pub const AttachReady = struct {
    session_id: u64,
    instance_id: u64,
    tree_revision: u64,
};

pub const SessionRecord = struct {
    session_id: u64,
    name: []const u8,
    instances: []const InstanceRecord,
};

pub const InstanceRecord = struct {
    instance_id: u64,
    state: InstanceState,
};

pub const TreeHeader = Status;

pub const payload_bytes = struct {
    pub const hello: usize = 0;
    pub const welcome: usize = 32;
    pub const status: usize = 0;
    pub const status_snapshot: usize = 32;
    pub const observe_tree: usize = 8;
    pub const create_session_header: usize = 8;
    pub const session_identity: usize = 8;
    pub const create_instance_header: usize = 24;
    pub const instance_identity: usize = 16;
    pub const attach_ready: usize = 24;
    pub const result: usize = 32;
    pub const tree_header: usize = 32;
    pub const session_record_header: usize = 16;
    pub const instance_record: usize = 16;
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
    const kind = enumFromInt(Kind, input[5]) orelse return error.UnknownKind;
    const payload_len = readU32(input[8..12]);
    if (payload_len > maximum_payload_bytes) return error.PayloadTooLarge;
    return .{ .kind = kind, .payload_len = payload_len };
}

pub fn encodeStatus(output: *[payload_bytes.status_snapshot]u8, value: Status) PayloadError!void {
    try validateStatus(value);
    output.* = @splat(0);
    writeU64(output[0..8], value.server_id);
    writeU64(output[8..16], value.tree_revision);
    writeU16(output[16..18], value.session_count);
    writeU16(output[18..20], value.instance_count);
    writeU16(output[20..22], value.session_capacity);
    writeU16(output[22..24], value.instances_per_session);
}

pub fn decodeStatus(input: []const u8) PayloadError!Status {
    if (input.len != payload_bytes.status_snapshot or !allZero(input[24..32]))
        return error.InvalidPayload;
    const value = Status{
        .server_id = readU64(input[0..8]),
        .tree_revision = readU64(input[8..16]),
        .session_count = readU16(input[16..18]),
        .instance_count = readU16(input[18..20]),
        .session_capacity = readU16(input[20..22]),
        .instances_per_session = readU16(input[22..24]),
    };
    try validateStatus(value);
    return value;
}

pub fn encodeObserveTree(output: *[payload_bytes.observe_tree]u8, value: ObserveTree) void {
    writeU64(output, value.after_revision);
}

pub fn decodeObserveTree(input: []const u8) PayloadError!ObserveTree {
    if (input.len != payload_bytes.observe_tree) return error.InvalidPayload;
    return .{ .after_revision = readU64(input) };
}

pub fn createSessionEncodedBytes(value: CreateSession) PayloadError!usize {
    try validateSessionName(value.name);
    return payload_bytes.create_session_header + value.name.len;
}

pub fn encodeCreateSession(output: []u8, value: CreateSession) EncodeError![]const u8 {
    const needed = try createSessionEncodedBytes(value);
    if (output.len < needed) return error.OutputTooSmall;
    const encoded = output[0..needed];
    @memset(encoded[0..payload_bytes.create_session_header], 0);
    encoded[0] = @intCast(value.name.len);
    @memcpy(encoded[payload_bytes.create_session_header..], value.name);
    return encoded;
}

pub fn decodeCreateSession(input: []const u8) PayloadError!CreateSession {
    if (input.len < payload_bytes.create_session_header or !allZero(input[1..payload_bytes.create_session_header]))
        return error.InvalidPayload;
    const name_len: usize = input[0];
    if (input.len != payload_bytes.create_session_header + name_len) return error.InvalidPayload;
    const value = CreateSession{ .name = input[payload_bytes.create_session_header..] };
    try validateSessionName(value.name);
    return value;
}

pub fn encodeSessionIdentity(output: *[payload_bytes.session_identity]u8, session_id: u64) PayloadError!void {
    if (session_id == 0) return error.InvalidPayload;
    writeU64(output, session_id);
}

pub fn decodeSessionIdentity(input: []const u8) PayloadError!u64 {
    if (input.len != payload_bytes.session_identity) return error.InvalidPayload;
    const value = readU64(input);
    if (value == 0) return error.InvalidPayload;
    return value;
}

pub fn createInstanceEncodedBytes(value: CreateInstance) PayloadError!usize {
    try validateCreateInstance(value);
    return payload_bytes.create_instance_header + value.shell.len +
        (if (value.command) |text| text.len else 0) +
        (if (value.cwd) |text| text.len else 0);
}

pub fn encodeCreateInstance(output: []u8, value: CreateInstance) EncodeError![]const u8 {
    const needed = try createInstanceEncodedBytes(value);
    if (output.len < needed) return error.OutputTooSmall;
    const encoded = output[0..needed];
    @memset(encoded[0..payload_bytes.create_instance_header], 0);
    writeU64(encoded[0..8], value.session_id);
    writeU16(encoded[8..10], value.rows);
    writeU16(encoded[10..12], value.columns);
    writeU16(encoded[12..14], value.history_rows);
    writeU16(encoded[14..16], @intCast(value.shell.len));
    writeU16(encoded[16..18], @intCast(if (value.command) |text| text.len else 0));
    writeU16(encoded[18..20], @intCast(if (value.cwd) |text| text.len else 0));
    var offset: usize = payload_bytes.create_instance_header;
    @memcpy(encoded[offset .. offset + value.shell.len], value.shell);
    offset += value.shell.len;
    if (value.command) |text| {
        @memcpy(encoded[offset .. offset + text.len], text);
        offset += text.len;
    }
    if (value.cwd) |text| @memcpy(encoded[offset .. offset + text.len], text);
    return encoded;
}

pub fn decodeCreateInstance(input: []const u8) PayloadError!CreateInstance {
    if (input.len < payload_bytes.create_instance_header or !allZero(input[20..24]))
        return error.InvalidPayload;
    const shell_len: usize = readU16(input[14..16]);
    const command_len: usize = readU16(input[16..18]);
    const cwd_len: usize = readU16(input[18..20]);
    const total = payload_bytes.create_instance_header + shell_len + command_len + cwd_len;
    if (total != input.len) return error.InvalidPayload;
    var offset: usize = payload_bytes.create_instance_header;
    const shell = input[offset .. offset + shell_len];
    offset += shell_len;
    const command = input[offset .. offset + command_len];
    offset += command_len;
    const cwd = input[offset .. offset + cwd_len];
    const value = CreateInstance{
        .session_id = readU64(input[0..8]),
        .rows = readU16(input[8..10]),
        .columns = readU16(input[10..12]),
        .history_rows = readU16(input[12..14]),
        .shell = shell,
        .command = if (command.len == 0) null else command,
        .cwd = if (cwd.len == 0) null else cwd,
    };
    try validateCreateInstance(value);
    return value;
}

pub fn encodeInstanceIdentity(output: *[payload_bytes.instance_identity]u8, value: InstanceIdentity) PayloadError!void {
    try validateInstanceIdentity(value);
    writeU64(output[0..8], value.session_id);
    writeU64(output[8..16], value.instance_id);
}

pub fn decodeInstanceIdentity(input: []const u8) PayloadError!InstanceIdentity {
    if (input.len != payload_bytes.instance_identity) return error.InvalidPayload;
    const value = InstanceIdentity{
        .session_id = readU64(input[0..8]),
        .instance_id = readU64(input[8..16]),
    };
    try validateInstanceIdentity(value);
    return value;
}

pub fn encodeAttachReady(output: *[payload_bytes.attach_ready]u8, value: AttachReady) PayloadError!void {
    try validateInstanceIdentity(.{ .session_id = value.session_id, .instance_id = value.instance_id });
    if (value.tree_revision == 0) return error.InvalidPayload;
    writeU64(output[0..8], value.session_id);
    writeU64(output[8..16], value.instance_id);
    writeU64(output[16..24], value.tree_revision);
}

pub fn decodeAttachReady(input: []const u8) PayloadError!AttachReady {
    if (input.len != payload_bytes.attach_ready) return error.InvalidPayload;
    const value = AttachReady{
        .session_id = readU64(input[0..8]),
        .instance_id = readU64(input[8..16]),
        .tree_revision = readU64(input[16..24]),
    };
    try validateInstanceIdentity(.{ .session_id = value.session_id, .instance_id = value.instance_id });
    if (value.tree_revision == 0) return error.InvalidPayload;
    return value;
}

pub fn encodeResult(output: *[payload_bytes.result]u8, value: Result) PayloadError!void {
    if (!resultRequestKind(value.request_kind) or value.tree_revision == 0) return error.InvalidPayload;
    if (value.code == .ok) switch (value.request_kind) {
        .create_session => if (value.session_id == 0 or value.instance_id != 0) return error.InvalidPayload,
        .create_instance => if (value.session_id == 0 or value.instance_id == 0) return error.InvalidPayload,
        .close_session => if (value.session_id == 0 or value.instance_id != 0) return error.InvalidPayload,
        .close_instance => if (value.session_id == 0 or value.instance_id == 0) return error.InvalidPayload,
        .attach_instance => return error.InvalidPayload,
        else => unreachable,
    };
    output.* = @splat(0);
    output[0] = @backingInt(value.request_kind);
    output[1] = @backingInt(value.code);
    writeU64(output[8..16], value.session_id);
    writeU64(output[16..24], value.instance_id);
    writeU64(output[24..32], value.tree_revision);
}

pub fn decodeResult(input: []const u8) PayloadError!Result {
    if (input.len != payload_bytes.result or !allZero(input[2..8])) return error.InvalidPayload;
    const request_kind = enumFromInt(Kind, input[0]) orelse return error.InvalidPayload;
    if (!resultRequestKind(request_kind)) return error.InvalidPayload;
    const code = enumFromInt(ResultCode, input[1]) orelse return error.InvalidPayload;
    const value = Result{
        .request_kind = request_kind,
        .code = code,
        .session_id = readU64(input[8..16]),
        .instance_id = readU64(input[16..24]),
        .tree_revision = readU64(input[24..32]),
    };
    var encoded: [payload_bytes.result]u8 = undefined;
    try encodeResult(&encoded, value);
    return value;
}

pub fn treeEncodedBytes(status: Status, sessions: []const SessionRecord) PayloadError!usize {
    try validateTree(status, sessions);
    var total: usize = payload_bytes.tree_header;
    for (sessions) |session| {
        total += payload_bytes.session_record_header + session.name.len;
        total += session.instances.len * payload_bytes.instance_record;
    }
    if (total > maximum_payload_bytes) return error.InvalidPayload;
    return total;
}

pub fn encodeTreeSnapshot(output: []u8, status: Status, sessions: []const SessionRecord) EncodeError![]const u8 {
    const needed = try treeEncodedBytes(status, sessions);
    if (output.len < needed) return error.OutputTooSmall;
    var header: [payload_bytes.tree_header]u8 = undefined;
    try encodeStatus(&header, status);
    @memcpy(output[0..header.len], &header);
    var offset: usize = header.len;
    for (sessions) |session| {
        const header_slice = output[offset..][0..payload_bytes.session_record_header];
        @memset(header_slice, 0);
        writeU64(header_slice[0..8], session.session_id);
        writeU16(header_slice[8..10], @intCast(session.instances.len));
        header_slice[10] = @intCast(session.name.len);
        offset += header_slice.len;
        @memcpy(output[offset .. offset + session.name.len], session.name);
        offset += session.name.len;
        for (session.instances) |instance| {
            const encoded = output[offset..][0..payload_bytes.instance_record];
            @memset(encoded, 0);
            writeU64(encoded[0..8], instance.instance_id);
            encoded[8] = @backingInt(instance.state);
            offset += encoded.len;
        }
    }
    std.debug.assert(offset == needed);
    return output[0..needed];
}

pub const TreeDecoder = struct {
    input: []const u8,
    header: TreeHeader,
    offset: usize = payload_bytes.tree_header,
    sessions_seen: u16 = 0,
    instances_seen: u16 = 0,
    pending_instances: u16 = 0,

    pub const DecodedSession = struct {
        session_id: u64,
        name: []const u8,
        instance_count: u16,
    };

    pub fn init(input: []const u8) PayloadError!TreeDecoder {
        if (input.len < payload_bytes.tree_header) return error.InvalidPayload;
        const header = try decodeStatus(input[0..payload_bytes.tree_header]);
        return .{ .input = input, .header = header };
    }

    pub fn nextSession(self: *TreeDecoder) PayloadError!?DecodedSession {
        if (self.pending_instances != 0) return error.InvalidPayload;
        if (self.sessions_seen == self.header.session_count) {
            if (self.instances_seen != self.header.instance_count or self.offset != self.input.len)
                return error.InvalidPayload;
            return null;
        }
        if (self.offset + payload_bytes.session_record_header > self.input.len) return error.InvalidPayload;
        const encoded = self.input[self.offset..][0..payload_bytes.session_record_header];
        if (!allZero(encoded[11..16])) return error.InvalidPayload;
        const session_id = readU64(encoded[0..8]);
        const instance_count = readU16(encoded[8..10]);
        const name_len: usize = encoded[10];
        if (session_id == 0 or instance_count > maximum_instances_per_session or
            name_len == 0 or name_len > maximum_session_name_bytes)
            return error.InvalidPayload;
        self.offset += encoded.len;
        if (self.offset + name_len > self.input.len) return error.InvalidPayload;
        const name = self.input[self.offset .. self.offset + name_len];
        try validateSessionName(name);
        self.offset += name_len;
        self.sessions_seen += 1;
        self.pending_instances = instance_count;
        return .{ .session_id = session_id, .name = name, .instance_count = instance_count };
    }

    pub fn nextInstance(self: *TreeDecoder) PayloadError!InstanceRecord {
        if (self.pending_instances == 0) return error.InvalidPayload;
        if (self.offset + payload_bytes.instance_record > self.input.len) return error.InvalidPayload;
        const encoded = self.input[self.offset..][0..payload_bytes.instance_record];
        if (!allZero(encoded[9..16])) return error.InvalidPayload;
        const instance_id = readU64(encoded[0..8]);
        const state = enumFromInt(InstanceState, encoded[8]) orelse return error.InvalidPayload;
        if (instance_id == 0) return error.InvalidPayload;
        self.offset += encoded.len;
        self.instances_seen += 1;
        self.pending_instances -= 1;
        if (self.instances_seen > self.header.instance_count) return error.InvalidPayload;
        return .{ .instance_id = instance_id, .state = state };
    }
};

fn validateStatus(value: Status) PayloadError!void {
    if (value.server_id == 0 or value.tree_revision == 0 or
        value.session_capacity != maximum_sessions or
        value.instances_per_session != maximum_instances_per_session or
        value.session_count > value.session_capacity or
        value.instance_count > value.session_capacity * value.instances_per_session)
        return error.InvalidPayload;
}

/// Model and wire share this exact bounded ASCII name contract.
pub fn validateSessionName(name: []const u8) PayloadError!void {
    if (name.len == 0 or name.len > maximum_session_name_bytes) return error.InvalidPayload;
    for (name) |byte| if (!((byte >= 'a' and byte <= 'z') or
        (byte >= 'A' and byte <= 'Z') or
        (byte >= '0' and byte <= '9') or byte == '.' or byte == '_' or byte == '-'))
        return error.InvalidPayload;
}

fn validateCreateInstance(value: CreateInstance) PayloadError!void {
    if (value.session_id == 0 or value.rows == 0 or value.columns == 0 or value.history_rows == 0 or
        value.shell.len == 0 or value.shell.len > maximum_shell_bytes or
        std.mem.indexOfScalar(u8, value.shell, 0) != null or
        (value.command != null and (value.command.?.len == 0 or
            value.command.?.len > maximum_command_bytes or
            std.mem.indexOfScalar(u8, value.command.?, 0) != null)) or
        (value.cwd != null and (value.cwd.?.len == 0 or
            value.cwd.?.len > maximum_cwd_bytes or
            std.mem.indexOfScalar(u8, value.cwd.?, 0) != null)))
        return error.InvalidPayload;
}

fn validateInstanceIdentity(value: InstanceIdentity) PayloadError!void {
    if (value.session_id == 0 or value.instance_id == 0) return error.InvalidPayload;
}

fn validateTree(status: Status, sessions: []const SessionRecord) PayloadError!void {
    try validateStatus(status);
    if (sessions.len != status.session_count or sessions.len > maximum_sessions) return error.InvalidPayload;
    var instances: usize = 0;
    var previous_session_id: u64 = 0;
    for (sessions) |session| {
        if (session.session_id == 0 or session.session_id <= previous_session_id) return error.InvalidPayload;
        previous_session_id = session.session_id;
        try validateSessionName(session.name);
        if (session.instances.len > maximum_instances_per_session) return error.InvalidPayload;
        var previous_instance_id: u64 = 0;
        for (session.instances) |instance| {
            if (instance.instance_id == 0 or instance.instance_id <= previous_instance_id) return error.InvalidPayload;
            previous_instance_id = instance.instance_id;
            instances += 1;
        }
    }
    if (instances != status.instance_count) return error.InvalidPayload;
}

fn resultRequestKind(kind: Kind) bool {
    return switch (kind) {
        .create_session, .close_session, .create_instance, .close_instance, .attach_instance => true,
        else => false,
    };
}

fn enumFromInt(comptime E: type, value: @typeInfo(E).@"enum".tag_type) ?E {
    const info = @typeInfo(E).@"enum";
    inline for (info.field_values) |field_value| {
        if (value == field_value) return @fromBackingInt(@intCast(value));
    }
    return null;
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

fn writeU32(output: []u8, value: u32) void {
    std.debug.assert(output.len == 4);
    output[0] = @truncate(value >> 24);
    output[1] = @truncate(value >> 16);
    output[2] = @truncate(value >> 8);
    output[3] = @truncate(value);
}

fn writeU64(output: []u8, value: u64) void {
    std.debug.assert(output.len == 8);
    var shift: u6 = 56;
    for (output) |*byte| {
        byte.* = @truncate(value >> shift);
        shift -|= 8;
    }
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

fn readU64(input: []const u8) u64 {
    std.debug.assert(input.len == 8);
    var value: u64 = 0;
    for (input) |byte| value = (value << 8) | byte;
    return value;
}

test "Session create wire cannot carry Instance launch policy" {
    var storage: [128]u8 = undefined;
    const encoded = try encodeCreateSession(&storage, .{ .name = "work" });
    try std.testing.expectEqual(@as(usize, payload_bytes.create_session_header + 4), encoded.len);
    const decoded = try decodeCreateSession(encoded);
    try std.testing.expectEqualStrings("work", decoded.name);
    try std.testing.expectError(error.InvalidPayload, decodeCreateSession(&.{ 0, 0, 0, 0, 0, 0, 0, 0 }));
}

test "Instance create wire carries launch policy under exact Session identity" {
    var storage: [maximum_request_payload_bytes]u8 = undefined;
    const encoded = try encodeCreateInstance(&storage, .{
        .session_id = 7,
        .shell = "/bin/sh",
        .command = "printf hi",
        .cwd = "/tmp",
        .rows = 24,
        .columns = 80,
        .history_rows = 4096,
    });
    const decoded = try decodeCreateInstance(encoded);
    try std.testing.expectEqual(@as(u64, 7), decoded.session_id);
    try std.testing.expectEqualStrings("/bin/sh", decoded.shell);
    try std.testing.expectEqualStrings("printf hi", decoded.command.?);
    try std.testing.expectEqualStrings("/tmp", decoded.cwd.?);
    try std.testing.expectEqual(@as(u16, 24), decoded.rows);
    try std.testing.expectEqual(@as(u16, 80), decoded.columns);
    try std.testing.expectEqual(@as(u16, 4096), decoded.history_rows);
}

test "Instance create wire rejects noncanonical optional process text" {
    var storage: [maximum_request_payload_bytes]u8 = undefined;
    try std.testing.expectError(error.InvalidPayload, encodeCreateInstance(&storage, .{
        .session_id = 1,
        .shell = "/bin/sh",
        .command = "",
        .rows = 2,
        .columns = 8,
        .history_rows = 16,
    }));
    try std.testing.expectError(error.InvalidPayload, encodeCreateInstance(&storage, .{
        .session_id = 1,
        .shell = "/bin/sh",
        .cwd = "",
        .rows = 2,
        .columns = 8,
        .history_rows = 16,
    }));
}

test "attach failure result is legal while attach success stays attach_ready" {
    var encoded: [payload_bytes.result]u8 = undefined;
    try encodeResult(&encoded, .{
        .request_kind = .attach_instance,
        .code = .instance_not_found,
        .session_id = 7,
        .instance_id = 99,
        .tree_revision = 4,
    });
    const decoded = try decodeResult(&encoded);
    try std.testing.expectEqual(Kind.attach_instance, decoded.request_kind);
    try std.testing.expectEqual(ResultCode.instance_not_found, decoded.code);
    try std.testing.expectError(error.InvalidPayload, encodeResult(&encoded, .{
        .request_kind = .attach_instance,
        .code = .ok,
        .session_id = 7,
        .instance_id = 1,
        .tree_revision = 4,
    }));
}

test "tree snapshot preserves Server Session Instance hierarchy" {
    const work_instances = [_]InstanceRecord{
        .{ .instance_id = 1, .state = .running },
        .{ .instance_id = 2, .state = .exited },
    };
    const logs_instances = [_]InstanceRecord{
        .{ .instance_id = 1, .state = .running },
    };
    const sessions = [_]SessionRecord{
        .{ .session_id = 4, .name = "work", .instances = &work_instances },
        .{ .session_id = 9, .name = "logs", .instances = &logs_instances },
    };
    const status = Status{
        .server_id = 99,
        .tree_revision = 12,
        .session_count = 2,
        .instance_count = 3,
    };
    var storage: [maximum_payload_bytes]u8 = undefined;
    const encoded = try encodeTreeSnapshot(&storage, status, &sessions);
    var decoder = try TreeDecoder.init(encoded);
    const work = (try decoder.nextSession()).?;
    try std.testing.expectEqual(@as(u64, 4), work.session_id);
    try std.testing.expectEqualStrings("work", work.name);
    try std.testing.expectEqual(@as(u16, 2), work.instance_count);
    var sequence_probe = decoder;
    try std.testing.expectError(error.InvalidPayload, sequence_probe.nextSession());
    try std.testing.expectEqual(InstanceState.running, (try decoder.nextInstance()).state);
    try std.testing.expectEqual(InstanceState.exited, (try decoder.nextInstance()).state);
    const logs = (try decoder.nextSession()).?;
    try std.testing.expectEqual(@as(u64, 9), logs.session_id);
    try std.testing.expectEqual(@as(u16, 1), logs.instance_count);
    try std.testing.expectEqual(InstanceState.running, (try decoder.nextInstance()).state);
    try std.testing.expect((try decoder.nextSession()) == null);
}

test "tree and identity codecs reject ambiguity" {
    var identity: [payload_bytes.instance_identity]u8 = undefined;
    try encodeInstanceIdentity(&identity, .{ .session_id = 3, .instance_id = 5 });
    try std.testing.expectEqualDeep(
        InstanceIdentity{ .session_id = 3, .instance_id = 5 },
        try decodeInstanceIdentity(&identity),
    );
    identity[0..8].* = @splat(0);
    try std.testing.expectError(error.InvalidPayload, decodeInstanceIdentity(&identity));

    var header: [header_bytes]u8 = undefined;
    try encodeHeader(&header, .{ .kind = .create_session, .payload_len = 9 });
    try std.testing.expectEqual(Kind.create_session, (try decodeHeader(&header)).kind);
    header[6] = 1;
    try std.testing.expectError(error.InvalidReservedBits, decodeHeader(&header));
}
