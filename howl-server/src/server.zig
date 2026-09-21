//! Foreground owner for one bounded dynamically managed Howl Session collection.
//!
//! The process stays alive with zero Sessions. HWLM owns collection lifecycle;
//! every Session keeps its existing HWLS endpoint until managed attach replaces
//! the temporary per-session Unix endpoint in the next slice.

const std = @import("std");
const linux = std.os.linux;
const protocol = @import("howl_server_protocol");
const Manager = @import("manager.zig").Manager;
const ListenerSpec = @import("manager.zig").ListenerSpec;
const Registry = @import("registry.zig").Registry;
const Defaults = @import("registry.zig").Defaults;

const shutdown_flush_turns: usize = 10;
const shutdown_flush_poll_ms: i32 = 10;

pub const Error = error{
    InvalidArguments,
    InvalidRuntimeDirectory,
    SocketPathTooLong,
    ServerAlreadyRunning,
};

pub const RunOutcome = enum {
    shutdown,
};

const ListenerChoice = union(enum) {
    unix,
    tcp: u16,
};

const Config = struct {
    runtime_dir: []const u8,
    listener: ListenerChoice = .unix,
    defaults: Defaults,
};

pub fn run(init: std.process.Init, args: []const [*:0]const u8) !RunOutcome {
    const config = try parse(init, args);
    try std.Io.Dir.createDirPath(.cwd(), init.io, config.runtime_dir);

    const lock_path = try std.fmt.allocPrint(init.gpa, "{s}/server.lock", .{config.runtime_dir});
    defer init.gpa.free(lock_path);
    var lock = std.Io.Dir.createFileAbsolute(init.io, lock_path, .{
        .read = true,
        .truncate = false,
        .lock = .exclusive,
        .lock_nonblocking = true,
    }) catch |failure| switch (failure) {
        error.WouldBlock => return error.ServerAlreadyRunning,
        else => return failure,
    };
    defer lock.close(init.io);

    const server_id = try randomServerId();
    var registry = try Registry.init(
        init.gpa,
        init.io,
        init.minimal.environ,
        config.runtime_dir,
        config.defaults,
        server_id,
    );
    defer registry.deinit();

    var manager_socket: ?[]u8 = null;
    defer if (manager_socket) |path| init.gpa.free(path);
    const listener: ListenerSpec = switch (config.listener) {
        .unix => blk: {
            const path = try std.fmt.allocPrint(init.gpa, "{s}/manager.sock", .{config.runtime_dir});
            if (path.len >= 108) {
                init.gpa.free(path);
                return error.SocketPathTooLong;
            }
            manager_socket = path;
            break :blk .{ .unix = path };
        },
        .tcp => |port| .{ .tcp_loopback = port },
    };
    var manager = try Manager.init(init.gpa, init.io, listener);
    defer manager.deinit();

    try emitStartup(init, &manager, &registry);

    while (!manager.stopping) {
        if (registry.hasActiveEndpoint()) {
            try manager.turn(&registry, 0);
            if (registry.serviceTurn(10)) |failed| try emitSessionFailure(init, failed);
        } else {
            try manager.turn(&registry, 10);
        }
    }

    var flush_turn: usize = 0;
    while (manager.hasPendingOutput() and flush_turn < shutdown_flush_turns) : (flush_turn += 1)
        try manager.turn(&registry, shutdown_flush_poll_ms);

    return .shutdown;
}

fn parse(init: std.process.Init, args: []const [*:0]const u8) Error!Config {
    return parseArgs(args, init.environ_map.get("SHELL") orelse "/bin/sh");
}

fn parseArgs(args: []const [*:0]const u8, default_shell: []const u8) Error!Config {
    if (args.len < 2 or !std.mem.eql(u8, std.mem.span(args[0]), "run"))
        return error.InvalidArguments;
    const runtime_dir = std.mem.span(args[1]);
    if (runtime_dir.len == 0 or !std.fs.path.isAbsolute(runtime_dir))
        return error.InvalidRuntimeDirectory;

    var result = Config{
        .runtime_dir = runtime_dir,
        .defaults = .{ .shell = default_shell },
    };
    var index: usize = 2;
    while (index < args.len) : (index += 1) {
        const arg = std.mem.span(args[index]);
        if (std.mem.eql(u8, arg, "--listen")) {
            index += 1;
            if (index == args.len) return error.InvalidArguments;
            const value = std.mem.span(args[index]);
            if (std.mem.eql(u8, value, "unix")) {
                result.listener = .unix;
            } else if (std.mem.startsWith(u8, value, "tcp:")) {
                const port = std.fmt.parseInt(u16, value["tcp:".len..], 10) catch
                    return error.InvalidArguments;
                result.listener = .{ .tcp = port };
            } else return error.InvalidArguments;
        } else if (std.mem.eql(u8, arg, "--shell")) {
            index += 1;
            if (index == args.len) return error.InvalidArguments;
            const value = std.mem.span(args[index]);
            if (value.len == 0) return error.InvalidArguments;
            result.defaults.shell = value;
        } else if (std.mem.eql(u8, arg, "--cwd")) {
            index += 1;
            if (index == args.len) return error.InvalidArguments;
            const value = std.mem.span(args[index]);
            if (value.len == 0) return error.InvalidArguments;
            result.defaults.cwd = value;
        } else if (std.mem.eql(u8, arg, "--rows")) {
            index += 1;
            if (index == args.len) return error.InvalidArguments;
            result.defaults.rows = std.fmt.parseInt(u16, std.mem.span(args[index]), 10) catch
                return error.InvalidArguments;
            if (result.defaults.rows == 0) return error.InvalidArguments;
        } else if (std.mem.eql(u8, arg, "--columns")) {
            index += 1;
            if (index == args.len) return error.InvalidArguments;
            result.defaults.columns = std.fmt.parseInt(u16, std.mem.span(args[index]), 10) catch
                return error.InvalidArguments;
            if (result.defaults.columns == 0) return error.InvalidArguments;
        } else return error.InvalidArguments;
    }
    return result;
}

fn randomServerId() !u64 {
    var bytes: [8]u8 = undefined;
    var offset: usize = 0;
    while (offset < bytes.len) {
        const result = linux.getrandom(bytes[offset..].ptr, bytes.len - offset, 0);
        switch (linux.errno(result)) {
            .SUCCESS => {
                if (result == 0 or result > bytes.len - offset) return error.RandomIdentityFailed;
                offset += result;
            },
            .INTR => continue,
            else => return error.RandomIdentityFailed,
        }
    }
    var value: u64 = 0;
    for (bytes) |byte| value = value << 8 | byte;
    if (value == 0) return randomServerId();
    return value;
}

fn emitStartup(init: std.process.Init, manager: *const Manager, registry: *const Registry) !void {
    var endpoint_buffer: [160]u8 = undefined;
    const endpoint_text = try manager.endpointText(&endpoint_buffer);
    var output_buffer: [512]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    try stdout.interface.print(
        "{{\"schema\":\"howl.server/v2\",\"server_id\":\"{x}\",\"pid\":{d},\"manager\":",
        .{ registry.server_id, linux.getpid() },
    );
    try std.json.Stringify.value(endpoint_text, .{}, &stdout.interface);
    try stdout.interface.print(
        ",\"capacity\":{d},\"sessions\":0}}\n",
        .{protocol.maximum_sessions},
    );
    try stdout.interface.flush();
}

fn emitSessionFailure(init: std.process.Init, failed: protocol.SessionRecord) !void {
    var output_buffer: [512]u8 = undefined;
    var stderr = std.Io.File.stderr().writerStreaming(init.io, &output_buffer);
    try stderr.interface.writeAll("{\"schema\":\"howl.server.event/v1\",\"event\":\"session_failed\",\"session_id\":");
    try stderr.interface.print("{d},\"name\":", .{failed.session_id});
    try std.json.Stringify.value(failed.name, .{}, &stderr.interface);
    try stderr.interface.writeAll(",\"failure\":");
    try std.json.Stringify.value(failed.failure, .{}, &stderr.interface);
    try stderr.interface.writeAll("}\n");
    try stderr.interface.flush();
}

test "server run parser accepts explicit foreground manager options" {
    const args = [_][*:0]const u8{
        "run",
        "/tmp/howl",
        "--listen",
        "tcp:0",
        "--shell",
        "/bin/bash",
        "--rows",
        "30",
        "--columns",
        "100",
    };
    const config = try parseArgs(&args, "/bin/sh");
    try std.testing.expectEqualStrings("/tmp/howl", config.runtime_dir);
    try std.testing.expectEqualStrings("/bin/bash", config.defaults.shell);
    try std.testing.expectEqual(@as(u16, 30), config.defaults.rows);
    try std.testing.expectEqual(@as(u16, 100), config.defaults.columns);
    try std.testing.expectEqual(@as(u16, 0), config.listener.tcp);
}
