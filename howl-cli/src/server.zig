//! Foreground owner for a small collection of named Howl terminals.
//!
//! Each terminal keeps the existing byte-stream attach protocol and owns one
//! Unix socket, but all PTY+VT instances live in this one process. This is the
//! first session-manager canary; it deliberately owns no discovery database,
//! daemonization, or second attach protocol.

const std = @import("std");
const linux = std.os.linux;
const endpoint = @import("howl_session_endpoint");
const session = @import("howl_session");

const maximum_terminals: usize = 16;
const idle_poll_ms: i32 = 10;

pub const Error = error{
    InvalidArguments,
    InvalidRuntimeDirectory,
    InvalidTerminalName,
    DuplicateTerminalName,
    TooManyTerminals,
    SocketPathTooLong,
};

const Config = struct {
    runtime_dir: []const u8,
    shell: []const u8,
    command: ?[]const u8 = null,
    cwd: ?[]const u8 = null,
    rows: u16 = 24,
    columns: u16 = 80,
    names: [maximum_terminals][]const u8 = undefined,
    name_count: usize = 0,
};

const Instance = struct {
    name: []const u8,
    socket_path: []u8,
    server: *endpoint.Server,

    fn deinit(self: *Instance, allocator: std.mem.Allocator) void {
        self.server.deinit();
        allocator.destroy(self.server);
        allocator.free(self.socket_path);
        self.* = undefined;
    }
};

pub fn run(init: std.process.Init, args: []const [*:0]const u8) !void {
    const config = try parse(init, args);
    try std.Io.Dir.createDirPath(.cwd(), init.io, config.runtime_dir);

    var instances: [maximum_terminals]?Instance = @splat(null);
    var count: usize = 0;
    defer {
        var index = count;
        while (index != 0) {
            index -= 1;
            instances[index].?.deinit(init.gpa);
            instances[index] = null;
        }
    }

    for (config.names[0..config.name_count]) |name| {
        const socket_path = try std.fmt.allocPrint(
            init.gpa,
            "{s}/{s}.sock",
            .{ config.runtime_dir, name },
        );
        errdefer init.gpa.free(socket_path);
        if (socket_path.len >= 108) return error.SocketPathTooLong;

        std.Io.Dir.deleteFileAbsolute(init.io, socket_path) catch |failure| switch (failure) {
            error.FileNotFound => {},
            else => return failure,
        };

        const owner = try init.gpa.create(endpoint.Server);
        errdefer init.gpa.destroy(owner);
        owner.* = try endpoint.Server.init(
            std.heap.page_allocator,
            init.io,
            init.minimal.environ,
            .{ .unix = socket_path },
            .{
                .shell = config.shell,
                .command = config.command,
                .cwd = config.cwd,
                .rows = config.rows,
                .columns = config.columns,
            },
        );
        instances[count] = .{
            .name = name,
            .socket_path = socket_path,
            .server = owner,
        };
        count += 1;
    }

    try emitManifest(init, instances[0..count]);
    var blocking_index: usize = 0;
    while (true) {
        for (instances[0..count], 0..) |maybe_instance, index| {
            const instance = maybe_instance orelse unreachable;
            try instance.server.turn(if (index == blocking_index) idle_poll_ms else 0);
        }
        blocking_index = (blocking_index + 1) % count;
    }
}

fn parse(init: std.process.Init, args: []const [*:0]const u8) Error!Config {
    if (args.len < 2) return error.InvalidArguments;
    const runtime_dir = std.mem.span(args[0]);
    if (runtime_dir.len == 0 or !std.fs.path.isAbsolute(runtime_dir))
        return error.InvalidRuntimeDirectory;

    var result = Config{
        .runtime_dir = runtime_dir,
        .shell = init.environ_map.get("SHELL") orelse "/bin/sh",
    };
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = std.mem.span(args[index]);
        if (std.mem.eql(u8, arg, "--shell")) {
            index += 1;
            if (index == args.len) return error.InvalidArguments;
            result.shell = std.mem.span(args[index]);
        } else if (std.mem.eql(u8, arg, "--command")) {
            index += 1;
            if (index == args.len) return error.InvalidArguments;
            result.command = std.mem.span(args[index]);
        } else if (std.mem.eql(u8, arg, "--cwd")) {
            index += 1;
            if (index == args.len) return error.InvalidArguments;
            result.cwd = std.mem.span(args[index]);
        } else if (std.mem.eql(u8, arg, "--rows")) {
            index += 1;
            if (index == args.len) return error.InvalidArguments;
            result.rows = std.fmt.parseInt(u16, std.mem.span(args[index]), 10) catch
                return error.InvalidArguments;
            if (result.rows == 0) return error.InvalidArguments;
        } else if (std.mem.eql(u8, arg, "--columns")) {
            index += 1;
            if (index == args.len) return error.InvalidArguments;
            result.columns = std.fmt.parseInt(u16, std.mem.span(args[index]), 10) catch
                return error.InvalidArguments;
            if (result.columns == 0) return error.InvalidArguments;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            return error.InvalidArguments;
        } else {
            try appendName(&result, arg);
        }
    }
    if (result.name_count == 0 or result.shell.len == 0) return error.InvalidArguments;
    return result;
}

fn appendName(config: *Config, name: []const u8) Error!void {
    if (!validName(name)) return error.InvalidTerminalName;
    if (config.name_count == config.names.len) return error.TooManyTerminals;
    for (config.names[0..config.name_count]) |existing| {
        if (std.mem.eql(u8, existing, name)) return error.DuplicateTerminalName;
    }
    config.names[config.name_count] = name;
    config.name_count += 1;
}

fn validName(name: []const u8) bool {
    if (name.len == 0 or name.len > 48) return false;
    for (name) |byte| {
        if (std.ascii.isAlphanumeric(byte) or byte == '-' or byte == '_' or byte == '.')
            continue;
        return false;
    }
    return true;
}

fn emitManifest(init: std.process.Init, instances: []const ?Instance) !void {
    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    const writer = &stdout.interface;
    try writer.print(
        "{{\"schema\":\"howl.server/v1\",\"pid\":{d},\"sessions\":[",
        .{linux.getpid()},
    );
    for (instances, 0..) |maybe_instance, index| {
        const instance = maybe_instance orelse unreachable;
        if (index != 0) try writer.writeByte(',');
        try writer.writeAll("{\"name\":");
        try std.json.Stringify.value(instance.name, .{}, writer);
        try writer.writeAll(",\"endpoint\":");
        const attach = try std.fmt.allocPrint(init.gpa, "unix:{s}", .{instance.socket_path});
        defer init.gpa.free(attach);
        try std.json.Stringify.value(attach, .{}, writer);
        try writer.writeByte('}');
    }
    try writer.writeAll("]}\n");
    try writer.flush();
}

test "terminal manager names are bounded path components" {
    try std.testing.expect(validName("main"));
    try std.testing.expect(validName("dev-2.foo_bar"));
    try std.testing.expect(!validName(""));
    try std.testing.expect(!validName("../escape"));
    try std.testing.expect(!validName("a/b"));
}

test "terminal manager rejects duplicate names" {
    var config = Config{ .runtime_dir = "/tmp/howl", .shell = "/bin/sh" };
    try appendName(&config, "one");
    try std.testing.expectError(error.DuplicateTerminalName, appendName(&config, "one"));
}
