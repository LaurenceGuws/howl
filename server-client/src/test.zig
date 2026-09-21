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

test "Server client preserves Session Instance hierarchy and exact attach stream" {
    var server = try model.Server.init(std.testing.allocator, 0x91);
    defer server.deinit();
    var service = server_service.Service.init(
        std.testing.allocator,
        std.testing.io,
        std.testing.environ,
        &server,
    );
    defer service.deinit();

    var pump = Pump{ .service = &service, .server = &server };
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
    var connection_live = true;
    defer if (connection_live) connection.deinit();
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

    var attached = try connection.attachInstance(identity);
    connection_live = false;
    defer attached.deinit();
    try std.testing.expectEqual(work, attached.ready.session_id);
    try std.testing.expectEqual(identity.instance_id, attached.ready.instance_id);
    try std.testing.expect(attached.ready.tree_revision >= tree.status.tree_revision);
}

test "typed Server client errors leave control connection usable" {
    var server = try model.Server.init(std.testing.allocator, 0x92);
    defer server.deinit();
    var service = server_service.Service.init(
        std.testing.allocator,
        std.testing.io,
        std.testing.environ,
        &server,
    );
    defer service.deinit();
    var pump = Pump{ .service = &service, .server = &server };
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
