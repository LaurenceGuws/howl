//! Native client for the bounded Server -> Sessions -> Instances control wire.

const std = @import("std");
const transport = @import("client_transport");
const protocol = @import("server_protocol");

pub const ConnectStage = transport.ConnectStage;
pub const ConnectDiagnostic = transport.ConnectDiagnostic;
pub const Interrupt = transport.Interrupt;
pub const Cancellation = transport.Cancellation;

pub const Error = std.mem.Allocator.Error || transport.Error || protocol.HeaderError ||
    protocol.PayloadError || error{
    UnexpectedHandshakeFrame,
    UnexpectedFrame,
    Malformed,
    Unsupported,
    SessionNotFound,
    InstanceNotFound,
    NameExists,
    SessionCapacity,
    InstanceCapacity,
    CreateFailed,
    Unavailable,
    Internal,
};

pub const Frame = struct {
    allocator: std.mem.Allocator,
    kind: protocol.Kind,
    payload: []u8,

    pub fn deinit(self: *Frame) void {
        self.allocator.free(self.payload);
        self.* = undefined;
    }
};

pub const Connection = struct {
    allocator: std.mem.Allocator,
    stream: transport.Stream,
    server_id: u64,
    tree_revision: u64,

    pub fn connect(allocator: std.mem.Allocator, endpoint: []const u8) Error!Connection {
        var diagnostic: ConnectDiagnostic = .{};
        return connectDiagnosed(allocator, endpoint, &diagnostic);
    }

    pub fn connectDiagnosed(
        allocator: std.mem.Allocator,
        endpoint: []const u8,
        diagnostic: *ConnectDiagnostic,
    ) Error!Connection {
        const stream = try transport.Stream.connectDiagnosed(endpoint, diagnostic);
        return connectTransport(allocator, stream, diagnostic);
    }

    pub fn deinit(self: *Connection) void {
        self.stream.deinit();
        self.* = undefined;
    }

    pub fn readinessFd(self: *const Connection) std.posix.fd_t {
        return self.stream.readinessFd();
    }

    pub fn cancellation(self: *const Connection) error{ SocketDuplicateFailed, SocketOptionFailed }!Cancellation {
        return self.stream.cancellation();
    }

    pub fn status(self: *Connection) Error!protocol.Status {
        try self.send(.status, &.{});
        var frame = try self.receive();
        defer frame.deinit();
        if (frame.kind != .status_snapshot) return error.UnexpectedFrame;
        const value = try protocol.decodeStatus(frame.payload);
        try self.acceptServer(value.server_id, value.tree_revision);
        return value;
    }

    pub fn observeTree(self: *Connection, after_revision: u64) Error!Tree {
        var payload: [protocol.payload_bytes.observe_tree]u8 = undefined;
        protocol.encodeObserveTree(&payload, .{ .after_revision = after_revision });
        try self.send(.observe_tree, &payload);
        var frame = try self.receive();
        defer frame.deinit();
        if (frame.kind != .tree_snapshot) return error.UnexpectedFrame;
        var tree = try Tree.decode(self.allocator, frame.payload);
        errdefer tree.deinit();
        try self.acceptServer(tree.status.server_id, tree.status.tree_revision);
        return tree;
    }

    pub fn createSession(self: *Connection, name: []const u8) Error!u64 {
        var payload: [protocol.payload_bytes.create_session_header + protocol.maximum_session_name_bytes]u8 = undefined;
        const encoded = protocol.encodeCreateSession(&payload, .{ .name = name }) catch |failure| switch (failure) {
            error.OutputTooSmall => unreachable,
            else => |err| return err,
        };
        const result = try self.requestResult(.create_session, encoded);
        return result.session_id;
    }

    pub fn closeSession(self: *Connection, session_id: u64) Error!void {
        var payload: [protocol.payload_bytes.session_identity]u8 = undefined;
        try protocol.encodeSessionIdentity(&payload, session_id);
        const result = try self.requestResult(.close_session, &payload);
        if (result.session_id != session_id or result.instance_id != 0) return error.UnexpectedFrame;
    }

    pub const InstanceLaunch = struct {
        session_id: u64,
        shell: []const u8,
        command: ?[]const u8 = null,
        cwd: ?[]const u8 = null,
        rows: u16,
        columns: u16,
        history_rows: u16,
    };

    pub fn createInstance(self: *Connection, launch: InstanceLaunch) Error!protocol.InstanceIdentity {
        var payload: [protocol.maximum_request_payload_bytes]u8 = undefined;
        const encoded = protocol.encodeCreateInstance(&payload, .{
            .session_id = launch.session_id,
            .shell = launch.shell,
            .command = launch.command,
            .cwd = launch.cwd,
            .rows = launch.rows,
            .columns = launch.columns,
            .history_rows = launch.history_rows,
        }) catch |failure| switch (failure) {
            error.OutputTooSmall => unreachable,
            else => |err| return err,
        };
        const result = try self.requestResult(.create_instance, encoded);
        return .{ .session_id = result.session_id, .instance_id = result.instance_id };
    }

    pub fn closeInstance(self: *Connection, identity: protocol.InstanceIdentity) Error!void {
        var payload: [protocol.payload_bytes.instance_identity]u8 = undefined;
        try protocol.encodeInstanceIdentity(&payload, identity);
        const result = try self.requestResult(.close_instance, &payload);
        if (result.session_id != identity.session_id or result.instance_id != identity.instance_id)
            return error.UnexpectedFrame;
    }

    /// Successful attach consumes this Connection and returns the same raw stream.
    /// Failure leaves the control Connection usable.
    pub fn attachInstance(self: *Connection, identity: protocol.InstanceIdentity) Error!Attached {
        var payload: [protocol.payload_bytes.instance_identity]u8 = undefined;
        try protocol.encodeInstanceIdentity(&payload, identity);
        try self.send(.attach_instance, &payload);
        var frame = try self.receive();
        defer frame.deinit();
        if (frame.kind == .result) {
            const result = try protocol.decodeResult(frame.payload);
            if (result.request_kind != .attach_instance) return error.UnexpectedFrame;
            try self.acceptRevision(result.tree_revision);
            try resultError(result.code);
            return error.UnexpectedFrame;
        }
        if (frame.kind != .attach_ready) return error.UnexpectedFrame;
        const ready = try protocol.decodeAttachReady(frame.payload);
        if (ready.session_id != identity.session_id or ready.instance_id != identity.instance_id)
            return error.UnexpectedFrame;
        try self.acceptRevision(ready.tree_revision);
        const stream = self.stream;
        self.* = undefined;
        return .{ .ready = ready, .stream = stream };
    }

    fn requestResult(self: *Connection, kind: protocol.Kind, payload: []const u8) Error!protocol.Result {
        try self.send(kind, payload);
        var frame = try self.receive();
        defer frame.deinit();
        if (frame.kind != .result) return error.UnexpectedFrame;
        const result = try protocol.decodeResult(frame.payload);
        if (result.request_kind != kind) return error.UnexpectedFrame;
        try self.acceptRevision(result.tree_revision);
        try resultError(result.code);
        return result;
    }

    fn send(self: *Connection, kind: protocol.Kind, payload: []const u8) Error!void {
        if (payload.len > protocol.maximum_request_payload_bytes) return error.PayloadTooLarge;
        var header: [protocol.header_bytes]u8 = undefined;
        try protocol.encodeHeader(&header, .{ .kind = kind, .payload_len = @intCast(payload.len) });
        try self.stream.write(&header);
        try self.stream.write(payload);
    }

    fn receive(self: *Connection) Error!Frame {
        var header_bytes: [protocol.header_bytes]u8 = undefined;
        try self.stream.read(&header_bytes);
        const header = try protocol.decodeHeader(&header_bytes);
        const payload = try self.allocator.alloc(u8, header.payload_len);
        errdefer self.allocator.free(payload);
        try self.stream.read(payload);
        return .{ .allocator = self.allocator, .kind = header.kind, .payload = payload };
    }

    fn acceptServer(self: *Connection, server_id: u64, revision: u64) Error!void {
        if (server_id != self.server_id or revision == 0) return error.UnexpectedFrame;
        self.tree_revision = revision;
    }

    fn acceptRevision(self: *Connection, revision: u64) Error!void {
        if (revision == 0) return error.UnexpectedFrame;
        self.tree_revision = revision;
    }
};

pub const Attached = struct {
    ready: protocol.AttachReady,
    stream: transport.Stream,

    pub fn deinit(self: *Attached) void {
        self.stream.deinit();
        self.* = undefined;
    }
};

pub const Tree = struct {
    allocator: std.mem.Allocator,
    status: protocol.Status,
    sessions: []Session,

    pub const Session = struct {
        id: u64,
        name: []u8,
        instances: []protocol.InstanceRecord,
    };

    pub fn deinit(self: *Tree) void {
        for (self.sessions) |session| {
            self.allocator.free(session.instances);
            self.allocator.free(session.name);
        }
        self.allocator.free(self.sessions);
        self.* = undefined;
    }

    fn decode(allocator: std.mem.Allocator, bytes: []const u8) Error!Tree {
        var decoder = try protocol.TreeDecoder.init(bytes);
        const sessions = try allocator.alloc(Session, decoder.header.session_count);
        var initialized: usize = 0;
        errdefer {
            for (sessions[0..initialized]) |session| {
                allocator.free(session.instances);
                allocator.free(session.name);
            }
            allocator.free(sessions);
        }
        while (initialized < sessions.len) : (initialized += 1) {
            const decoded = (try decoder.nextSession()) orelse return error.UnexpectedFrame;
            const name = try allocator.dupe(u8, decoded.name);
            errdefer allocator.free(name);
            const instances = try allocator.alloc(protocol.InstanceRecord, decoded.instance_count);
            errdefer allocator.free(instances);
            for (instances) |*instance| instance.* = try decoder.nextInstance();
            sessions[initialized] = .{
                .id = decoded.session_id,
                .name = name,
                .instances = instances,
            };
        }
        if ((try decoder.nextSession()) != null) return error.UnexpectedFrame;
        return .{ .allocator = allocator, .status = decoder.header, .sessions = sessions };
    }
};

pub fn connectTransport(
    allocator: std.mem.Allocator,
    stream_value: transport.Stream,
    diagnostic: *ConnectDiagnostic,
) Error!Connection {
    var stream = stream_value;
    errdefer stream.deinit();
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
    const status = try protocol.decodeStatus(&payload);
    try stream.finishHandshake(diagnostic);
    return .{
        .allocator = allocator,
        .stream = stream,
        .server_id = status.server_id,
        .tree_revision = status.tree_revision,
    };
}

fn resultError(code: protocol.ResultCode) Error!void {
    return switch (code) {
        .ok => {},
        .malformed => error.Malformed,
        .unsupported => error.Unsupported,
        .session_not_found => error.SessionNotFound,
        .instance_not_found => error.InstanceNotFound,
        .name_exists => error.NameExists,
        .session_capacity => error.SessionCapacity,
        .instance_capacity => error.InstanceCapacity,
        .create_failed => error.CreateFailed,
        .unavailable => error.Unavailable,
        .internal => error.Internal,
    };
}
