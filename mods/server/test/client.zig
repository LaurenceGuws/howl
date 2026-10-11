const std = @import("std");
const client = @import("server_client");
const model = @import("server_model");
const server_service = @import("server_service");
const transport = @import("client_transport");

const Pump = struct {
    service: *server_service.Service,
    server: *model.Server,
    stop: std.atomic.Value(bool) = .init(false),
    failed: std.atomic.Value(bool) = .init(false),

    fn run(self: *Pump) void {
        while (!self.stop.load(.acquire)) {
            self.service.turn(1) catch {
                self.failed.store(true, .release);
                return;
            };
            var sessions_storage: [model.maximum_sessions]model.SessionView = undefined;
            const sessions = self.server.snapshotSessions(&sessions_storage);
            for (sessions) |session| {
                var instances_storage: [model.maximum_instances_per_session]model.InstanceView = undefined;
                const instances = self.server.snapshotInstances(session.id, &instances_storage) orelse continue;
                for (instances) |instance| {
                    self.server.turnInstance(session.id, instance.id, 0) catch {
                        self.failed.store(true, .release);
                        return;
                    };
                }
            }
        }
    }
};

fn closeFd(fd: std.posix.fd_t) void {
    const linux = std.os.linux;
    const result = linux.close(fd);
    const status = linux.errno(result);
    std.debug.assert(status == .SUCCESS or status == .INTR);
}

fn adoptedPair(service: *server_service.Service) !transport.Stream {
    var pair: [2]std.posix.fd_t = undefined;
    const result = std.posix.system.socketpair(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0, &pair);
    if (std.posix.errno(result) != .SUCCESS) return error.TestSocketCreateFailed;
    errdefer closeFd(pair[0]);
    errdefer closeFd(pair[1]);
    try service.adoptClient(pair[0], &.{});
    return .{ .fd = pair[1] };
}

test "dedicated attachments preserve separate control and Instance lifetime" {
    const server = try model.Server.init(std.testing.allocator, 0x91);
    defer server.deinit();
    var service = server_service.Service.init(
        std.testing.allocator,
        std.testing.io,
        std.testing.environ,
        server,
    );
    defer service.deinit();

    // Adopt before starting the sole service owner; the peer endpoints remain
    // independently owned until each constructor consumes one.
    var streams: [3]transport.Stream = undefined;
    var streams_live: [3]bool = @splat(false);
    defer for (&streams, streams_live) |*stream, live| {
        if (live) stream.deinit();
    };
    for (&streams, &streams_live) |*stream, *live| {
        stream.* = try adoptedPair(&service);
        live.* = true;
    }

    var pump = Pump{ .service = &service, .server = server };
    const worker = try std.Thread.spawn(.{}, Pump.run, .{&pump});
    defer {
        pump.stop.store(true, .release);
        worker.join();
        std.debug.assert(!pump.failed.load(.acquire));
    }

    var diagnostic: client.ConnectDiagnostic = .{};
    streams_live[0] = false;
    var connection = try client.connectTransport(
        std.testing.allocator,
        streams[0],
        &diagnostic,
    );
    defer connection.deinit();
    try std.testing.expectEqual(@as(u64, 0x91), connection.server_id);
    try std.testing.expectEqual(client.ConnectStage.ready, diagnostic.stage);

    const work = try connection.createSession("work");
    try std.testing.expectEqual(@as(u64, 1), work);

    const identity = try connection.createInstance(.{
        .session_id = work,
        .shell = "/bin/sh",
        .command = "cat",
        .rows = 4,
        .columns = 20,
        .history_rows = 32,
    });
    try std.testing.expectEqual(work, identity.session_id);
    try std.testing.expectEqual(@as(u64, 1), identity.instance_id);

    var tree = try connection.observeTree(0);
    defer tree.deinit();
    try std.testing.expectEqual(@as(u16, 1), tree.status.session_count);
    try std.testing.expectEqual(@as(u16, 1), tree.status.instance_count);
    try std.testing.expectEqual(@as(usize, 1), tree.sessions.len);
    try std.testing.expectEqualStrings("work", tree.sessions[0].name);
    try std.testing.expectEqual(@as(usize, 1), tree.sessions[0].instances.len);
    try std.testing.expectEqual(identity.instance_id, tree.sessions[0].instances[0].instance_id);

    streams_live[1] = false;
    var attachment_control = try client.connectTransport(std.testing.allocator, streams[1], &diagnostic);
    defer attachment_control.deinit();
    var attached = try attachment_control.attachInstance(connection.server_id, identity);
    var attached_live = true;
    defer if (attached_live) attached.deinit();
    try std.testing.expectEqual(connection.server_id, attached.ready.server_id);
    try std.testing.expectEqual(work, attached.ready.session_id);
    try std.testing.expectEqual(identity.instance_id, attached.ready.instance_id);
    try std.testing.expectEqual(attached.ready.client_id, attached.connection.client_id);
    try std.testing.expect(attached.ready.tree_revision >= tree.status.tree_revision);
    try std.testing.expectError(error.ConnectionRetired, attachment_control.status());
    const first_client_id = attached.ready.client_id;
    const initial_state = try client.terminal.state.get(&attached.connection);
    try std.testing.expect(initial_state.terminal_revision != 0);

    try std.testing.expectEqual(@as(u16, 1), (try connection.status()).instance_count);
    attached.deinit();
    attached_live = false;
    try std.testing.expectEqual(@as(u16, 1), (try connection.status()).instance_count);

    streams_live[2] = false;
    var reattachment_control = try client.connectTransport(std.testing.allocator, streams[2], &diagnostic);
    defer reattachment_control.deinit();
    var reattached = try reattachment_control.attachInstance(connection.server_id, identity);
    defer reattached.deinit();
    try std.testing.expectEqual(identity.instance_id, reattached.ready.instance_id);
    try std.testing.expect(reattached.ready.client_id != first_client_id);
    const resumed_state = try client.terminal.state.get(&reattached.connection);
    try std.testing.expect(resumed_state.terminal_revision >= initial_state.terminal_revision);

    try connection.closeInstance(identity);
    try std.testing.expectEqual(@as(u16, 0), (try connection.status()).instance_count);
    try std.testing.expectError(error.ConnectionClosed, reattached.connection.receive());
}

test "typed Server client errors leave control connection usable" {
    const server = try model.Server.init(std.testing.allocator, 0x92);
    defer server.deinit();
    var service = server_service.Service.init(
        std.testing.allocator,
        std.testing.io,
        std.testing.environ,
        server,
    );
    defer service.deinit();
    var pump = Pump{ .service = &service, .server = server };
    const worker = try std.Thread.spawn(.{}, Pump.run, .{&pump});
    defer {
        pump.stop.store(true, .release);
        worker.join();
        std.debug.assert(!pump.failed.load(.acquire));
    }

    var diagnostic: client.ConnectDiagnostic = .{};
    var connection = try client.connectTransport(
        std.testing.allocator,
        try adoptedPair(&service),
        &diagnostic,
    );
    defer connection.deinit();

    const work = try connection.createSession("work");
    try std.testing.expectError(error.NameExists, connection.createSession("work"));
    try std.testing.expectError(error.SessionNotFound, connection.createInstance(.{
        .session_id = work + 100,
        .shell = "/bin/sh",
        .command = "cat",
        .rows = 2,
        .columns = 8,
        .history_rows = 16,
    }));
    const status = try connection.status();
    try std.testing.expectEqual(@as(u16, 1), status.session_count);
    try std.testing.expectEqual(@as(u16, 0), status.instance_count);
}

// Hostile wire proofs use the public clients and owned native socketpairs.
const terminal = client.terminal;
const protocol = client.protocol;
const posix = std.posix;

fn hostilePair() ![2]posix.fd_t {
    var fds: [2]posix.fd_t = undefined;
    if (posix.errno(posix.system.socketpair(posix.AF.UNIX, posix.SOCK.STREAM, 0, &fds)) != .SUCCESS)
        return error.TestSocketCreateFailed;
    return fds;
}

fn frame(peer: *transport.Stream, kind: protocol.Kind, payload: []const u8) !void {
    var header: [protocol.header_bytes]u8 = undefined;
    try protocol.encodeHeader(&header, .{ .kind = kind, .payload_len = @intCast(payload.len) });
    try peer.write(&header);
    try peer.write(payload);
}

fn makeControl(fd: posix.fd_t, allocator: std.mem.Allocator) !client.Connection {
    var diagnostic: client.ConnectDiagnostic = .{};
    return .{ .stream = try transport.Stream.adopt(fd, &diagnostic, null), .allocator = allocator, .server_id = 91, .tree_revision = 1 };
}

fn resultFrame(peer: *transport.Stream, kind: protocol.Kind, code: protocol.ResultCode, session_id: u64) !void {
    var bytes: [protocol.payload_bytes.result]u8 = undefined;
    try protocol.encodeResult(&bytes, .{ .request_kind = kind, .code = code, .session_id = session_id, .instance_id = 4, .tree_revision = 2 });
    try frame(peer, .result, &bytes);
}

test "createInstance success must belong to requested Session or retire" {
    for ([_]u64{ 7, 8 }) |owner| {
        const fds = try hostilePair();
        var peer: transport.Stream = .{ .fd = fds[1] };
        defer peer.deinit();
        var c = try makeControl(fds[0], std.testing.allocator);
        defer c.deinit();
        try resultFrame(&peer, .create_instance, .ok, owner);
        const result = c.createInstance(.{ .session_id = 7, .shell = "/bin/sh", .rows = 2, .columns = 8, .history_rows = 16 });
        if (owner == 7) {
            try std.testing.expectEqual(@as(u64, 7), (try result).session_id);
        } else {
            try std.testing.expectError(error.UnexpectedFrame, result);
            try std.testing.expectError(error.ConnectionRetired, c.status());
        }
    }
}

test "public tree decoder rejects duplicate and backwards Session and Instance identities" {
    for ([_]bool{ false, true }) |session_mutation| {
        for ([_]u64{ 1, 2 }) |second_id| {
            const fds = try hostilePair();
            var peer: transport.Stream = .{ .fd = fds[1] };
            defer peer.deinit();
            var c = try makeControl(fds[0], std.testing.allocator);
            defer c.deinit();
            const instances = [_]protocol.InstanceRecord{ .{ .instance_id = 2, .state = .running }, .{ .instance_id = 3, .state = .exited } };
            const sessions = [_]protocol.SessionRecord{ .{ .session_id = 2, .name = "a", .instances = &instances }, .{ .session_id = 3, .name = "b", .instances = &.{} } };
            var bytes: [256]u8 = undefined;
            const encoded = try protocol.encodeTreeSnapshot(&bytes, .{ .server_id = 91, .tree_revision = 2, .session_count = 2, .instance_count = 2 }, &sessions);
            const offset: usize = if (session_mutation) 32 + 16 + 1 + 32 else 32 + 16 + 1 + 16;
            std.mem.writeInt(u64, bytes[offset..][0..8], second_id, .big);
            try frame(&peer, .tree_snapshot, encoded);
            try std.testing.expectError(error.InvalidPayload, c.observeTree(0));
        }
    }
}

test "attach OOM after header retires rather than reinterpreting unread body" {
    const fds = try hostilePair();
    var peer: transport.Stream = .{ .fd = fds[1] };
    defer peer.deinit();
    var c = try makeControl(fds[0], std.testing.failing_allocator);
    defer c.deinit();
    try resultFrame(&peer, .attach_instance, .instance_not_found, 7);
    try std.testing.expectError(error.OutOfMemory, c.attachInstance(91, .{ .session_id = 7, .instance_id = 4 }));
    c.allocator = std.testing.allocator;
    try std.testing.expectError(error.ConnectionRetired, c.status());
    try std.testing.expectEqual(posix.E.BADF, posix.errno(posix.system.fcntl(fds[0], posix.F.GETFD, @as(usize, 0))));
}

test "only pre-send validation and complete typed attach rejection are reusable" {
    const fds = try hostilePair();
    var peer: transport.Stream = .{ .fd = fds[1] };
    defer peer.deinit();
    var c = try makeControl(fds[0], std.testing.allocator);
    defer c.deinit();
    try std.testing.expectError(error.InvalidPayload, c.attachInstance(91, .{ .session_id = 0, .instance_id = 4 }));
    try std.testing.expect(c.live);
    try resultFrame(&peer, .attach_instance, .instance_not_found, 7);
    try std.testing.expectError(error.InstanceNotFound, c.attachInstance(91, .{ .session_id = 7, .instance_id = 4 }));
    try std.testing.expect(c.live);
    try resultFrame(&peer, .create_instance, .ok, 7);
    const created = try c.createInstance(.{ .session_id = 7, .shell = "/bin/sh", .rows = 2, .columns = 8, .history_rows = 16 });
    try std.testing.expectEqual(@as(u64, 4), created.instance_id);
}

fn readyFrame(peer: *transport.Stream, session_id: u64) !void {
    var ready: [protocol.payload_bytes.attach_ready]u8 = undefined;
    try protocol.encodeAttachReady(&ready, .{ .server_id = 91, .session_id = session_id, .instance_id = 3, .tree_revision = 2, .client_id = 71 });
    try frame(peer, .attach_ready, &ready);
}

test "wrong attach identity and malformed frame retire before handoff" {
    for ([_]bool{ false, true }) |malformed| {
        const fds = try hostilePair();
        var peer: transport.Stream = .{ .fd = fds[1] };
        defer peer.deinit();
        var c = try makeControl(fds[0], std.testing.allocator);
        defer c.deinit();
        if (malformed) try peer.write("BAD!00000000") else try readyFrame(&peer, 8);
        const result = c.attachInstance(91, .{ .session_id = 7, .instance_id = 3 });
        if (malformed) try std.testing.expectError(error.InvalidMagic, result) else try std.testing.expectError(error.UnexpectedFrame, result);
        try std.testing.expectError(error.ConnectionRetired, c.status());
    }
}

fn welcomeFrame(peer: *transport.Stream, server_id: u64) !void {
    var bytes: [protocol.payload_bytes.welcome]u8 = undefined;
    try protocol.encodeStatus(&bytes, .{ .server_id = server_id, .tree_revision = 1, .session_count = 1, .instance_count = 1 });
    try frame(peer, .welcome, &bytes);
}

test "new Server incarnation rejects both observer and control before attach send" {
    for (0..2) |_| {
        const fds = try hostilePair();
        var peer: transport.Stream = .{ .fd = fds[1] };
        defer peer.deinit();
        var diagnostic: client.ConnectDiagnostic = .{};
        try welcomeFrame(&peer, 92);
        var c = try client.connectTransport(std.testing.allocator, try transport.Stream.adopt(fds[0], &diagnostic, null), &diagnostic);
        defer c.deinit();
        try std.testing.expectError(error.StaleServerIncarnation, c.attachInstance(91, .{ .session_id = 1, .instance_id = 1 }));
        var hello: [protocol.header_bytes]u8 = undefined;
        try peer.read(&hello);
        try std.testing.expectEqual(protocol.Kind.hello, (try protocol.decodeHeader(&hello)).kind);
        var byte: [1]u8 = undefined;
        // Only hello, never an attach request, crossed the new incarnation.
        try std.testing.expectError(error.ConnectionClosed, peer.read(&byte));
    }
}

test "one setup deadline ends at Server attachment-ready" {
    for (0..3) |phase| {
        const fds = try hostilePair();
        var peer: transport.Stream = .{ .fd = fds[1] };
        defer peer.deinit();
        var diagnostic: client.ConnectDiagnostic = .{};
        var stream = try transport.Stream.adopt(fds[0], &diagnostic, null);
        stream.handshake_deadline_ms.? -= 14_980;
        const deadline = stream.handshake_deadline_ms;
        if (phase == 0) {
            try peer.write("S");
            try std.testing.expectError(error.SocketConnectTimedOut, client.connectTransport(std.testing.allocator, stream, &diagnostic));
            continue;
        }
        try welcomeFrame(&peer, 91);
        var c = try client.connectTransport(std.testing.allocator, stream, &diagnostic);
        defer c.deinit();
        try std.testing.expectEqual(deadline, c.stream.handshake_deadline_ms);
        if (phase == 1) {
            // Complete header, partial body: deadline must apply to receive too.
            var header: [protocol.header_bytes]u8 = undefined;
            try protocol.encodeHeader(&header, .{ .kind = .attach_ready, .payload_len = protocol.payload_bytes.attach_ready });
            try peer.write(&header);
            try peer.write(&.{0});
            try std.testing.expectError(error.SocketConnectTimedOut, c.attachInstance(91, .{ .session_id = 7, .instance_id = 3 }));
            try std.testing.expectError(error.ConnectionRetired, c.status());
        } else {
            try readyFrame(&peer, 7);
            var attached = try c.attachInstance(91, .{ .session_id = 7, .instance_id = 3 });
            defer attached.deinit();
            try std.testing.expectEqual(fds[0], attached.connection.stream.fd);
            try std.testing.expect(attached.connection.stream.handshake_deadline_ms == null);
            try std.testing.expectEqual(@as(u64, 71), attached.connection.client_id);
            try std.testing.expectError(error.ConnectionRetired, c.status());
        }
    }
}

const AttachProbe = struct {
    connection: *client.Connection,
    result: ?client.Error = null,
    fn run(self: *AttachProbe) void {
        var attached = self.connection.attachInstance(91, .{ .session_id = 7, .instance_id = 3 }) catch |err| {
            self.result = err;
            return;
        };
        attached.deinit();
    }
};

test "Interrupt cancels partial attach body and retires connection" {
    const fds = try hostilePair();
    var peer: transport.Stream = .{ .fd = fds[1] };
    defer peer.deinit();
    const interrupt = try transport.Interrupt.init(std.testing.allocator);
    defer interrupt.deinit();
    var diagnostic: client.ConnectDiagnostic = .{};
    var c = client.Connection{ .stream = try transport.Stream.adopt(fds[0], &diagnostic, interrupt), .allocator = std.testing.allocator, .server_id = 91, .tree_revision = 1 };
    defer c.deinit();
    var header: [protocol.header_bytes]u8 = undefined;
    try protocol.encodeHeader(&header, .{ .kind = .attach_ready, .payload_len = protocol.payload_bytes.attach_ready });
    try peer.write(&header);
    try peer.write(&.{0});
    var probe: AttachProbe = .{ .connection = &c };
    const worker = try std.Thread.spawn(.{}, AttachProbe.run, .{&probe});
    try std.Io.sleep(std.testing.io, .fromMilliseconds(20), .awake);
    try interrupt.cancel();
    worker.join();
    try std.testing.expectEqual(error.ConnectionCanceled, probe.result.?);
    try std.testing.expectError(error.ConnectionRetired, c.status());
}

const SetupProbe = struct {
    stream: transport.Stream,
    terminal_id: ?u64,
    result: ?(client.Error || terminal.Error) = null,

    fn run(self: *SetupProbe) void {
        if (self.terminal_id) |id| {
            var connection = terminal.Connection{ .allocator = std.testing.allocator, .stream = self.stream, .client_id = id };
            defer connection.deinit();
            var response = connection.receive() catch |err| {
                self.result = err;
                return;
            };
            response.deinit();
        } else {
            var diagnostic: client.ConnectDiagnostic = .{};
            var connection = client.connectTransport(std.testing.allocator, self.stream, &diagnostic) catch |err| {
                self.result = err;
                return;
            };
            connection.deinit();
        }
    }
};

test "Interrupt covers partial Server welcome and survives into attached terminal receive" {
    for ([_]bool{ false, true }) |terminal_phase| {
        const fds = try hostilePair();
        var peer: transport.Stream = .{ .fd = fds[1] };
        defer peer.deinit();
        const interrupt = try transport.Interrupt.init(std.testing.allocator);
        defer interrupt.deinit();
        var diagnostic: client.ConnectDiagnostic = .{};
        var stream = try transport.Stream.adopt(fds[0], &diagnostic, interrupt);
        var terminal_id: ?u64 = null;
        if (terminal_phase) {
            try welcomeFrame(&peer, 91);
            var control = try client.connectTransport(std.testing.allocator, stream, &diagnostic);
            defer control.deinit();
            try readyFrame(&peer, 7);
            const attached = try control.attachInstance(91, .{ .session_id = 7, .instance_id = 3 });
            stream = attached.connection.stream;
            terminal_id = attached.connection.client_id;
            try std.testing.expectEqual(interrupt, stream.interrupt.?);
        }
        try peer.write("S");
        var probe: SetupProbe = .{ .stream = stream, .terminal_id = terminal_id };
        const worker = try std.Thread.spawn(.{}, SetupProbe.run, .{&probe});
        try std.Io.sleep(std.testing.io, .fromMilliseconds(20), .awake);
        try interrupt.cancel();
        worker.join();
        try std.testing.expectEqual(error.ConnectionCanceled, probe.result.?);
        try std.testing.expectEqual(posix.E.BADF, posix.errno(posix.system.fcntl(fds[0], posix.F.GETFD, @as(usize, 0))));
    }
}

test "partial attach header EOF retires even when peer closes after request" {
    const fds = try hostilePair();
    var peer: transport.Stream = .{ .fd = fds[1] };
    defer peer.deinit();
    var c = try makeControl(fds[0], std.testing.allocator);
    defer c.deinit();
    try peer.write("SR");
    try std.testing.expectEqual(posix.E.SUCCESS, posix.errno(posix.system.shutdown(peer.fd, posix.SHUT.WR)));
    try std.testing.expectError(error.ConnectionClosed, c.attachInstance(91, .{ .session_id = 7, .instance_id = 3 }));
    try std.testing.expectError(error.ConnectionRetired, c.status());
    try std.testing.expectError(error.ConnectionRetired, c.readinessFd());
    try std.testing.expectError(error.ConnectionRetired, c.cancellation());
}

fn treeAllocationProbe(allocator: std.mem.Allocator) !void {
    const fds = try hostilePair();
    var peer: transport.Stream = .{ .fd = fds[1] };
    defer peer.deinit();
    var c = try makeControl(fds[0], allocator);
    defer c.deinit();
    const instances = [_]protocol.InstanceRecord{.{ .instance_id = 1, .state = .running }};
    const sessions = [_]protocol.SessionRecord{ .{ .session_id = 1, .name = "a", .instances = &instances }, .{ .session_id = 2, .name = "b", .instances = &instances } };
    var bytes: [256]u8 = undefined;
    const encoded = try protocol.encodeTreeSnapshot(&bytes, .{ .server_id = 91, .tree_revision = 2, .session_count = 2, .instance_count = 2 }, &sessions);
    try frame(&peer, .tree_snapshot, encoded);
    var tree = try c.observeTree(0);
    defer tree.deinit();
    try std.testing.expectEqual(@as(usize, 2), tree.sessions.len);
}

test "all tree construction allocation failures free completed resources" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, treeAllocationProbe, .{});
}
