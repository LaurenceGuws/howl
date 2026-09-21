const std = @import("std");
const runtime_mod = @import("server_runtime");
const server_client = @import("server_client");
const howl_client = @import("howl_client");

const Pump = struct {
    runtime: *runtime_mod.Runtime,
    stop: std.atomic.Value(bool) = .init(false),
    failed: std.atomic.Value(bool) = .init(false),

    fn run(self: *Pump) void {
        while (!self.stop.load(.acquire)) {
            self.runtime.turn() catch {
                self.failed.store(true, .release);
                return;
            };
        }
    }
};

fn connectServer(endpoint: []const u8) !server_client.Connection {
    return server_client.Connection.connect(std.testing.allocator, endpoint);
}

fn attachInstance(
    endpoint: []const u8,
    identity: server_client.protocol.InstanceIdentity,
) !howl_client.Connection {
    var control = try connectServer(endpoint);
    var control_live = true;
    defer if (control_live) control.deinit();
    var attached = try control.attachInstance(identity);
    control_live = false;
    var diagnostic: howl_client.ConnectDiagnostic = .{};
    const connection = try howl_client.connectTransport(
        std.testing.allocator,
        attached.stream,
        &diagnostic,
    );
    attached = undefined;
    try std.testing.expectEqual(howl_client.ConnectStage.ready, diagnostic.stage);
    return connection;
}

test "one Server hosts independently-sized Instances without owning a shared grid" {
    var runtime = try runtime_mod.Runtime.init(
        std.testing.allocator,
        std.testing.io,
        std.testing.environ,
        .{ .tcp_loopback = 0 },
        0xa11ce,
    );
    defer runtime.deinit();

    var endpoint_storage: [64]u8 = undefined;
    const endpoint = try runtime.endpointText(&endpoint_storage);

    var pump = Pump{ .runtime = &runtime };
    const worker = try std.Thread.spawn(.{}, Pump.run, .{&pump});
    defer {
        pump.stop.store(true, .release);
        worker.join();
        std.debug.assert(!pump.failed.load(.acquire));
    }

    var control = try connectServer(endpoint);
    defer control.deinit();
    const work = try control.createSession("work");
    const logs = try control.createSession("logs");
    const work_instance = try control.createInstance(.{
        .session_id = work,
        .shell = "/bin/sh",
        .command = "cat",
        .rows = 40,
        .columns = 100,
        .history_rows = 128,
    });
    const logs_instance = try control.createInstance(.{
        .session_id = logs,
        .shell = "/bin/sh",
        .command = "cat",
        .rows = 18,
        .columns = 72,
        .history_rows = 64,
    });

    var work_client = try attachInstance(endpoint, work_instance);
    defer work_client.deinit();
    var work_snapshot = try howl_client.snapshot.request(&work_client, std.testing.allocator, 0, 0);
    defer work_snapshot.deinit();
    try std.testing.expectEqual(@as(u16, 40), work_snapshot.begin.rows);
    try std.testing.expectEqual(@as(u16, 100), work_snapshot.begin.columns);

    var logs_client = try attachInstance(endpoint, logs_instance);
    defer logs_client.deinit();
    var logs_snapshot = try howl_client.snapshot.request(&logs_client, std.testing.allocator, 0, 0);
    defer logs_snapshot.deinit();
    try std.testing.expectEqual(@as(u16, 18), logs_snapshot.begin.rows);
    try std.testing.expectEqual(@as(u16, 72), logs_snapshot.begin.columns);

    var tree = try control.observeTree(0);
    defer tree.deinit();
    try std.testing.expectEqual(@as(u16, 2), tree.status.session_count);
    try std.testing.expectEqual(@as(u16, 2), tree.status.instance_count);
    try std.testing.expectEqual(@as(usize, 2), tree.sessions.len);
    // Tree state deliberately contains identity/lifecycle only, never terminal geometry.
    try std.testing.expectEqual(@as(usize, 1), tree.sessions[0].instances.len);
    try std.testing.expectEqual(@as(usize, 1), tree.sessions[1].instances.len);
}

test "quiescent exited Instance reactivates on later exact attach" {
    var runtime = try runtime_mod.Runtime.init(
        std.testing.allocator,
        std.testing.io,
        std.testing.environ,
        .{ .tcp_loopback = 0 },
        0xe71ed,
    );
    defer runtime.deinit();

    var endpoint_storage: [64]u8 = undefined;
    const endpoint = try runtime.endpointText(&endpoint_storage);

    var first_pump = Pump{ .runtime = &runtime };
    const first_worker = try std.Thread.spawn(.{}, Pump.run, .{&first_pump});
    var first_running = true;
    defer if (first_running) {
        first_pump.stop.store(true, .release);
        first_worker.join();
    };

    var control = try connectServer(endpoint);
    const session_id = try control.createSession("retained");
    const identity = try control.createInstance(.{
        .session_id = session_id,
        .shell = "/bin/sh",
        .command = "printf 'EXITED_CANARY\\n'; exit 0",
        .rows = 6,
        .columns = 32,
        .history_rows = 16,
    });

    var exited = false;
    var attempts: usize = 0;
    while (attempts < 1_000 and !exited) : (attempts += 1) {
        var tree = try control.observeTree(0);
        defer tree.deinit();
        if (tree.sessions.len == 1 and tree.sessions[0].instances.len == 1)
            exited = tree.sessions[0].instances[0].state == .exited;
    }
    try std.testing.expect(exited);

    // Each request forces ordinary runtime turns while the control connection is
    // alive, giving trailing PTY/publication work a bounded chance to finish.
    var settle: usize = 0;
    while (settle < 32) : (settle += 1) {
        const status = try control.status();
        try std.testing.expectEqual(@as(u16, 1), status.instance_count);
    }
    control.deinit();

    first_pump.stop.store(true, .release);
    first_worker.join();
    first_running = false;
    try std.testing.expect(!first_pump.failed.load(.acquire));
    try std.testing.expect(runtime.server.instanceRequiresService(session_id, identity.instance_id) == false);

    var second_pump = Pump{ .runtime = &runtime };
    const second_worker = try std.Thread.spawn(.{}, Pump.run, .{&second_pump});
    defer {
        second_pump.stop.store(true, .release);
        second_worker.join();
        std.debug.assert(!second_pump.failed.load(.acquire));
    }

    var retained_client = try attachInstance(endpoint, identity);
    defer retained_client.deinit();
    var snapshot = try howl_client.snapshot.request(
        &retained_client,
        std.testing.allocator,
        0,
        0,
    );
    defer snapshot.deinit();

    var found = false;
    for (snapshot.lines) |line| {
        if (std.mem.indexOf(u8, line, "EXITED_CANARY") != null) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}
