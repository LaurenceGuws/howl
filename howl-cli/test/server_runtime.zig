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
