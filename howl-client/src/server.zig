//! Native client for one explicit Howl server manager endpoint.
//!
//! This speaks HWLM collection management only. Selecting one managed Session
//! later hands the stream to the existing HWLS Session client; terminal semantics
//! never enter this module.

const std = @import("std");
const protocol = @import("howl_server_protocol");
const transport = @import("transport.zig");
const session_client = @import("client.zig");

pub const ConnectStage = transport.ConnectStage;
pub const ConnectDiagnostic = transport.ConnectDiagnostic;
pub const Interrupt = transport.Interrupt;
pub const Cancellation = transport.Cancellation;
pub const ResultCode = protocol.ResultCode;
pub const SessionState = protocol.SessionState;
pub const Create = protocol.Create;
pub const ServerStatus = protocol.ServerStatus;
pub const SessionRecord = protocol.SessionRecord;
pub const RosterHeader = protocol.RosterHeader;
pub const Result = protocol.Result;

pub const AttachOutcome = union(enum) {
    session: session_client.Connection,
    rejected: Result,
};

pub const Error = transport.Error || session_client.Error || protocol.HeaderError || protocol.PayloadError || protocol.EncodeError || error{
    UnexpectedHandshakeFrame,
    UnexpectedResponseFrame,
    MalformedRoster,
    ServerIdentityChanged,
};

/// Opens one socket-only HWLM route, transfers it to the exact managed Session,
/// then completes the unchanged HWLS handshake on that same ordered stream.
pub fn attach(
    allocator: std.mem.Allocator,
    endpoint: []const u8,
    session_id: u64,
    diagnostic: *ConnectDiagnostic,
) Error!AttachOutcome {
    if (session_id == 0) return error.InvalidPayload;
    var manager = try Connection.connect(allocator, endpoint, diagnostic);
    var manager_owned = true;
    defer if (manager_owned) manager.deinit();
    return attachConnected(&manager, &manager_owned, allocator, session_id, diagnostic);
}

/// Opens one short-lived HWLM route, transfers it to the exact managed Session,
/// then completes the unchanged HWLS handshake on that same ordered stream.
pub fn attachNative(
    allocator: std.mem.Allocator,
    io: std.Io,
    endpoint: []const u8,
    session_id: u64,
    diagnostic: *ConnectDiagnostic,
) Error!AttachOutcome {
    return attachNativeCancelable(allocator, io, endpoint, session_id, diagnostic, null);
}

/// Cancelable form of `attachNative`; cancellation spans both manager and HWLS handshakes.
pub fn attachNativeCancelable(
    allocator: std.mem.Allocator,
    io: std.Io,
    endpoint: []const u8,
    session_id: u64,
    diagnostic: *ConnectDiagnostic,
    interrupt: ?*Interrupt,
) Error!AttachOutcome {
    if (session_id == 0) return error.InvalidPayload;
    var manager = try Connection.connectNativeCancelable(allocator, io, endpoint, diagnostic, interrupt);
    var manager_owned = true;
    defer if (manager_owned) manager.deinit();
    return attachConnected(&manager, &manager_owned, allocator, session_id, diagnostic);
}

pub const Roster = struct {
    allocator: std.mem.Allocator,
    payload: []u8,
    header: protocol.RosterHeader,
    records: [protocol.maximum_sessions]protocol.SessionRecord = undefined,
    count: u16 = 0,

    pub fn deinit(self: *Roster) void {
        self.allocator.free(self.payload);
        self.* = undefined;
    }

    pub fn items(self: *const Roster) []const protocol.SessionRecord {
        return self.records[0..self.count];
    }

    pub fn findName(self: *const Roster, name: []const u8) ?protocol.SessionRecord {
        for (self.items()) |record| {
            if (std.mem.eql(u8, record.name, name)) return record;
        }
        return null;
    }
};

pub const Connection = struct {
    allocator: std.mem.Allocator,
    stream: transport.Stream,
    server_id: u64,

    pub fn connect(
        allocator: std.mem.Allocator,
        endpoint: []const u8,
        diagnostic: *ConnectDiagnostic,
    ) Error!Connection {
        const stream = try transport.Stream.connectDiagnosed(endpoint, diagnostic);
        return handshake(allocator, stream, diagnostic);
    }

    pub fn connectNative(
        allocator: std.mem.Allocator,
        io: std.Io,
        endpoint: []const u8,
        diagnostic: *ConnectDiagnostic,
    ) Error!Connection {
        return connectNativeCancelable(allocator, io, endpoint, diagnostic, null);
    }

    pub fn connectNativeCancelable(
        allocator: std.mem.Allocator,
        io: std.Io,
        endpoint: []const u8,
        diagnostic: *ConnectDiagnostic,
        interrupt: ?*Interrupt,
    ) Error!Connection {
        const stream = try transport.Stream.connectNativeCancelable(
            allocator,
            io,
            endpoint,
            diagnostic,
            interrupt,
        );
        return handshake(allocator, stream, diagnostic);
    }

    pub fn deinit(self: *Connection) void {
        self.stream.deinit();
        self.* = undefined;
    }

    pub fn cancellation(self: *const Connection) error{ SocketDuplicateFailed, SocketOptionFailed }!Cancellation {
        return self.stream.cancellation();
    }

    pub fn status(self: *Connection) Error!ServerStatus {
        try self.send(.status, &.{});
        var payload: [protocol.payload_bytes.status_snapshot]u8 = undefined;
        try self.receiveFixed(.status_snapshot, &payload);
        const value = try protocol.decodeServerStatus(&payload);
        try self.requireServer(value.server_id);
        return value;
    }

    pub fn observeRoster(self: *Connection, after_revision: u64) Error!Roster {
        var request: [protocol.payload_bytes.observe_roster]u8 = undefined;
        protocol.encodeObserveRoster(&request, .{ .after_revision = after_revision });
        try self.send(.observe_roster, &request);
        var header_bytes: [protocol.header_bytes]u8 = undefined;
        try self.stream.read(&header_bytes);
        const header = try protocol.decodeHeader(&header_bytes);
        if (header.kind != .roster_snapshot or
            header.payload_len < protocol.payload_bytes.roster_header or
            header.payload_len > protocol.maximum_payload_bytes)
            return error.UnexpectedResponseFrame;
        const payload = try self.allocator.alloc(u8, header.payload_len);
        errdefer self.allocator.free(payload);
        try self.stream.read(payload);
        const roster_header = try protocol.decodeRosterHeader(payload[0..protocol.payload_bytes.roster_header]);
        try self.requireServer(roster_header.server_id);
        if (roster_header.session_count > protocol.maximum_sessions) return error.MalformedRoster;

        var result = Roster{
            .allocator = self.allocator,
            .payload = payload,
            .header = roster_header,
            .count = roster_header.session_count,
        };
        var offset: usize = protocol.payload_bytes.roster_header;
        for (0..result.count) |index| {
            if (offset >= payload.len) return error.MalformedRoster;
            const decoded = protocol.decodeRosterRecord(payload[offset..]) catch return error.MalformedRoster;
            result.records[index] = decoded.record;
            offset += decoded.encoded_bytes;
        }
        if (offset != payload.len) return error.MalformedRoster;
        return result;
    }

    pub fn create(self: *Connection, request: Create) Error!Result {
        var storage: [protocol.maximum_request_payload_bytes]u8 = undefined;
        const encoded = try protocol.encodeCreate(&storage, request);
        try self.send(.create, encoded);
        return self.receiveResult(.create);
    }

    pub fn close(self: *Connection, session_id: u64) Error!Result {
        var payload: [protocol.payload_bytes.session_identity]u8 = undefined;
        try protocol.encodeSessionIdentity(&payload, session_id);
        try self.send(.close, &payload);
        return self.receiveResult(.close);
    }

    pub fn shutdown(self: *Connection) Error!Result {
        try self.send(.shutdown, &.{});
        return self.receiveResult(.shutdown);
    }

    fn send(self: *Connection, kind: protocol.Kind, payload: []const u8) Error!void {
        if (payload.len > protocol.maximum_request_payload_bytes) return error.PayloadTooLarge;
        var header: [protocol.header_bytes]u8 = undefined;
        try protocol.encodeHeader(&header, .{ .kind = kind, .payload_len = @intCast(payload.len) });
        try self.stream.write(&header);
        try self.stream.write(payload);
    }

    fn receiveResult(self: *Connection, request_kind: protocol.Kind) Error!Result {
        var payload: [protocol.payload_bytes.result]u8 = undefined;
        try self.receiveFixed(.result, &payload);
        const value = try protocol.decodeResult(&payload);
        if (value.request_kind != request_kind) return error.UnexpectedResponseFrame;
        return value;
    }

    fn receiveFixed(self: *Connection, expected: protocol.Kind, output: []u8) Error!void {
        var header_bytes: [protocol.header_bytes]u8 = undefined;
        try self.stream.read(&header_bytes);
        const header = try protocol.decodeHeader(&header_bytes);
        if (header.kind != expected or header.payload_len != output.len)
            return error.UnexpectedResponseFrame;
        try self.stream.read(output);
    }

    fn requireServer(self: *const Connection, server_id: u64) Error!void {
        if (server_id != self.server_id) return error.ServerIdentityChanged;
    }
};

fn attachConnected(
    manager: *Connection,
    manager_owned: *bool,
    allocator: std.mem.Allocator,
    session_id: u64,
    diagnostic: *ConnectDiagnostic,
) Error!AttachOutcome {
    var request: [protocol.payload_bytes.session_identity]u8 = undefined;
    try protocol.encodeSessionIdentity(&request, session_id);
    try manager.send(.attach, &request);

    var header_bytes: [protocol.header_bytes]u8 = undefined;
    try manager.stream.read(&header_bytes);
    const header = try protocol.decodeHeader(&header_bytes);
    if (header.kind == .result) {
        if (header.payload_len != protocol.payload_bytes.result) return error.UnexpectedResponseFrame;
        var result_payload: [protocol.payload_bytes.result]u8 = undefined;
        try manager.stream.read(&result_payload);
        const result = try protocol.decodeResult(&result_payload);
        if (result.request_kind != .attach) return error.UnexpectedResponseFrame;
        return .{ .rejected = result };
    }
    if (header.kind != .attach_ready or header.payload_len != protocol.payload_bytes.attach_ready)
        return error.UnexpectedResponseFrame;
    var ready_payload: [protocol.payload_bytes.attach_ready]u8 = undefined;
    try manager.stream.read(&ready_payload);
    const ready = try protocol.decodeAttachReady(&ready_payload);
    if (ready.session_id != session_id) return error.UnexpectedResponseFrame;

    const stream = manager.stream;
    manager.* = undefined;
    manager_owned.* = false;
    return .{ .session = try session_client.connectTransport(allocator, stream, diagnostic) };
}

fn handshake(
    allocator: std.mem.Allocator,
    stream_value: transport.Stream,
    diagnostic: *ConnectDiagnostic,
) Error!Connection {
    var stream = stream_value;
    errdefer stream.deinitDiagnosed(diagnostic);
    diagnostic.stage = .hello_write;
    var hello: [protocol.header_bytes]u8 = undefined;
    try protocol.encodeHeader(&hello, .{ .kind = .hello, .payload_len = 0 });
    try stream.handshakeWrite(&hello);
    diagnostic.stage = .welcome_read;
    var header_bytes: [protocol.header_bytes]u8 = undefined;
    try stream.handshakeRead(&header_bytes);
    const header = try protocol.decodeHeader(&header_bytes);
    if (header.kind != .welcome) {
        diagnostic.stage = .welcome_kind;
        return error.UnexpectedHandshakeFrame;
    }
    diagnostic.stage = .welcome_payload;
    if (header.payload_len != protocol.payload_bytes.welcome) return error.InvalidPayload;
    var payload: [protocol.payload_bytes.welcome]u8 = undefined;
    try stream.handshakeRead(&payload);
    const welcome = try protocol.decodeServerStatus(&payload);
    try stream.finishHandshake(diagnostic);
    return .{ .allocator = allocator, .stream = stream, .server_id = welcome.server_id };
}

test "roster owns one payload and exact borrowed records" {
    var payload: [protocol.maximum_payload_bytes]u8 = undefined;
    var header: [protocol.payload_bytes.roster_header]u8 = undefined;
    try protocol.encodeRosterHeader(&header, .{
        .server_id = 91,
        .roster_revision = 7,
        .session_count = 2,
        .capacity = protocol.maximum_sessions,
        .stopping = false,
    });
    @memcpy(payload[0..header.len], &header);
    var offset: usize = header.len;
    const one = try protocol.encodeRosterRecord(payload[offset..], .{
        .session_id = 3,
        .created_sequence = 1,
        .state = .running,
        .name = "work",
    });
    offset += one.len;
    const two = try protocol.encodeRosterRecord(payload[offset..], .{
        .session_id = 9,
        .created_sequence = 2,
        .state = .failed,
        .name = "logs",
        .failure = "AcceptFailed",
    });
    offset += two.len;

    const owned = try std.testing.allocator.dupe(u8, payload[0..offset]);
    var roster = Roster{
        .allocator = std.testing.allocator,
        .payload = owned,
        .header = try protocol.decodeRosterHeader(owned[0..header.len]),
        .count = 2,
    };
    defer roster.deinit();
    var cursor: usize = header.len;
    for (0..roster.count) |index| {
        const decoded = try protocol.decodeRosterRecord(owned[cursor..]);
        roster.records[index] = decoded.record;
        cursor += decoded.encoded_bytes;
    }
    try std.testing.expectEqual(@as(usize, offset), cursor);
    try std.testing.expectEqual(@as(u64, 3), roster.findName("work").?.session_id);
    try std.testing.expectEqualStrings("AcceptFailed", roster.findName("logs").?.failure);
    try std.testing.expect(roster.findName("missing") == null);
}

const AttachPeerProbe = struct {
    fd: std.posix.fd_t,
    session_id: u64,
};

fn runAttachPeer(probe: AttachPeerProbe) void {
    defer testCloseFd(probe.fd);
    var manager_header_bytes: [protocol.header_bytes]u8 = undefined;
    testReadExact(probe.fd, &manager_header_bytes) catch @panic("attach header read");
    const manager_header = protocol.decodeHeader(&manager_header_bytes) catch @panic("attach header");
    if (manager_header.kind != .attach or manager_header.payload_len != protocol.payload_bytes.session_identity)
        @panic("unexpected attach request");
    var identity: [protocol.payload_bytes.session_identity]u8 = undefined;
    testReadExact(probe.fd, &identity) catch @panic("attach identity read");
    if ((protocol.decodeSessionIdentity(&identity) catch @panic("attach identity")) != probe.session_id)
        @panic("wrong attach identity");

    var ready_payload: [protocol.payload_bytes.attach_ready]u8 = undefined;
    protocol.encodeAttachReady(&ready_payload, .{
        .session_id = probe.session_id,
        .roster_revision = 9,
    }) catch @panic("attach ready payload");
    var ready_header: [protocol.header_bytes]u8 = undefined;
    protocol.encodeHeader(&ready_header, .{
        .kind = .attach_ready,
        .payload_len = ready_payload.len,
    }) catch @panic("attach ready header");
    testWriteAll(probe.fd, &ready_header) catch @panic("attach ready header write");
    testWriteAll(probe.fd, &ready_payload) catch @panic("attach ready payload write");

    const session_protocol = @import("howl_session").protocol;
    var session_header_bytes: [session_protocol.header_bytes]u8 = undefined;
    testReadExact(probe.fd, &session_header_bytes) catch @panic("Session hello read");
    const session_header = session_protocol.decodeHeader(&session_header_bytes) catch @panic("Session hello");
    if (session_header.kind != .hello or session_header.payload_len != 0)
        @panic("unexpected Session hello");
    var welcome_payload: [session_protocol.payload_bytes.welcome]u8 = undefined;
    session_protocol.encodeWelcome(&welcome_payload, .{ .client_id = 73 });
    var welcome_header: [session_protocol.header_bytes]u8 = undefined;
    session_protocol.encodeHeader(&welcome_header, .{
        .kind = .welcome,
        .payload_len = welcome_payload.len,
    }) catch @panic("Session welcome header");
    testWriteAll(probe.fd, &welcome_header) catch @panic("Session welcome header write");
    testWriteAll(probe.fd, &welcome_payload) catch @panic("Session welcome payload write");
}

test "managed attach transitions one stream from HWLM into unchanged HWLS" {
    var pair: [2]std.posix.fd_t = undefined;
    if (std.posix.errno(std.posix.system.socketpair(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0, &pair)) != .SUCCESS)
        return error.TestSocketCreateFailed;
    const worker = try std.Thread.spawn(.{}, runAttachPeer, .{AttachPeerProbe{ .fd = pair[1], .session_id = 17 }});
    defer worker.join();

    var manager = Connection{
        .allocator = std.testing.allocator,
        .stream = .{ .fd = pair[0] },
        .server_id = 91,
    };
    var manager_owned = true;
    defer if (manager_owned) manager.deinit();
    var diagnostic: ConnectDiagnostic = .{ .stage = .ready };
    const outcome = try attachConnected(&manager, &manager_owned, std.testing.allocator, 17, &diagnostic);
    switch (outcome) {
        .rejected => return error.UnexpectedTestRejection,
        .session => |value| {
            var session = value;
            defer session.deinit();
            try std.testing.expectEqual(@as(u64, 73), session.client_id);
            try std.testing.expectEqual(ConnectStage.ready, diagnostic.stage);
        },
    }
    try std.testing.expect(!manager_owned);
}

fn testReadExact(fd: std.posix.fd_t, output: []u8) !void {
    var offset: usize = 0;
    while (offset < output.len) {
        const result = std.posix.system.read(fd, output[offset..].ptr, output.len - offset);
        switch (std.posix.errno(result)) {
            .SUCCESS => {
                if (result == 0 or result > output.len - offset) return error.TestSocketReadFailed;
                offset += result;
            },
            .INTR => continue,
            else => return error.TestSocketReadFailed,
        }
    }
}

fn testWriteAll(fd: std.posix.fd_t, bytes: []const u8) !void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        const result = std.posix.system.write(fd, bytes[offset..].ptr, bytes.len - offset);
        switch (std.posix.errno(result)) {
            .SUCCESS => {
                if (result == 0 or result > bytes.len - offset) return error.TestSocketWriteFailed;
                offset += result;
            },
            .INTR => continue,
            else => return error.TestSocketWriteFailed,
        }
    }
}

fn testCloseFd(fd: std.posix.fd_t) void {
    const result = std.posix.system.close(fd);
    const status = std.posix.errno(result);
    std.debug.assert(status == .SUCCESS or status == .INTR);
}
