//! Foreground owner for a small collection of named Howl terminals.
//!
//! Each terminal keeps the existing byte-stream attach protocol and owns one
//! Unix socket, but all PTY+VT instances live in this one process. This is the
//! first session-manager canary; it deliberately owns no discovery database,
//! daemonization, or second attach protocol.

const std = @import("std");
const linux = std.os.linux;
const posix = std.posix;
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

pub const RunOutcome = enum {
    all_terminals_failed,
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

pub fn run(init: std.process.Init, args: []const [*:0]const u8) !RunOutcome {
    const config = try parse(init, args);
    try std.Io.Dir.createDirPath(.cwd(), init.io, config.runtime_dir);

    var instances: [maximum_terminals]?Instance = @splat(null);
    var count: usize = 0;
    defer {
        var index = count;
        while (index != 0) {
            index -= 1;
            if (instances[index]) |*instance| {
                instance.deinit(init.gpa);
                instances[index] = null;
            }
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
    var live_count = count;
    var blocking_index: usize = 0;
    while (live_count != 0) {
        const result = serviceCollectionTurn(
            Instance,
            std.mem.Allocator,
            endpoint.Server.TurnError,
            init.gpa,
            instances[0..count],
            live_count,
            blocking_index,
            turnInstance,
            deinitInstance,
        );
        live_count = result.live_count;
        blocking_index = result.next_blocking_index;
    }
    return .all_terminals_failed;
}

const CollectionFailure = struct {
    name: []const u8,
    failure: []const u8,
};

const CollectionTurn = struct {
    live_count: usize,
    next_blocking_index: usize,
    failed: ?CollectionFailure,
};

fn serviceCollectionTurn(
    comptime T: type,
    comptime Context: type,
    comptime TurnError: type,
    context: Context,
    instances: []?T,
    live_count: usize,
    blocking_index: usize,
    comptime turn: fn (Context, *T, i32) TurnError!void,
    comptime deinit: fn (Context, *T) void,
) CollectionTurn {
    std.debug.assert(instances.len != 0);
    std.debug.assert(live_count != 0);
    std.debug.assert(live_count <= instances.len);
    std.debug.assert(blocking_index < instances.len);

    var index = blocking_index;
    var visited: usize = 0;
    var blocked = false;
    while (visited < instances.len) : (visited += 1) {
        if (instances[index]) |*instance| {
            const timeout = if (!blocked) idle_poll_ms else 0;
            blocked = true;
            turn(context, instance, timeout) catch |failure| {
                const name = instance.name;
                const failure_name = @errorName(failure);
                deinit(context, instance);
                instances[index] = null;
                const next = (index + 1) % instances.len;
                return .{
                    .live_count = live_count - 1,
                    .next_blocking_index = nextLiveIndex(T, instances, next),
                    .failed = .{ .name = name, .failure = failure_name },
                };
            };
        }
        index = (index + 1) % instances.len;
    }

    return .{
        .live_count = live_count,
        .next_blocking_index = nextLiveIndex(
            T,
            instances,
            (blocking_index + 1) % instances.len,
        ),
        .failed = null,
    };
}

fn nextLiveIndex(comptime T: type, instances: []?T, start: usize) usize {
    if (instances.len == 0) return 0;
    var index = start;
    var visited: usize = 0;
    while (visited < instances.len) : (visited += 1) {
        if (instances[index] != null) return index;
        index = (index + 1) % instances.len;
    }
    return start;
}

fn turnInstance(
    _: std.mem.Allocator,
    instance: *Instance,
    timeout_ms: i32,
) endpoint.Server.TurnError!void {
    return instance.server.turn(timeout_ms);
}

fn deinitInstance(allocator: std.mem.Allocator, instance: *Instance) void {
    instance.deinit(allocator);
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

const TestInstance = struct {
    name: []const u8,
    id: usize,
    fail: bool = false,
    turns: usize = 0,
    last_timeout_ms: ?i32 = null,
};

const TestCollectionContext = struct {
    deinit_counts: [4]usize = @splat(0),
};

fn turnTestInstance(_: *TestCollectionContext, instance: *TestInstance, timeout_ms: i32) error{InjectedFailure}!void {
    instance.turns += 1;
    instance.last_timeout_ms = timeout_ms;
    if (instance.fail) return error.InjectedFailure;
}

fn deinitTestInstance(context: *TestCollectionContext, instance: *TestInstance) void {
    context.deinit_counts[instance.id] += 1;
}

test "collection retires one failed slot and continues healthy siblings" {
    var context: TestCollectionContext = .{};
    var instances: [3]?TestInstance = .{
        .{ .name = "one", .id = 0, .fail = true },
        .{ .name = "two", .id = 1 },
        .{ .name = "three", .id = 2 },
    };

    const first = serviceCollectionTurn(
        TestInstance,
        *TestCollectionContext,
        error{InjectedFailure},
        &context,
        &instances,
        3,
        0,
        turnTestInstance,
        deinitTestInstance,
    );
    try std.testing.expectEqual(@as(usize, 2), first.live_count);
    try std.testing.expect(first.failed != null);
    try std.testing.expectEqualStrings("one", first.failed.?.name);
    try std.testing.expectEqualStrings("InjectedFailure", first.failed.?.failure);
    try std.testing.expect(instances[0] == null);
    try std.testing.expectEqual(@as(usize, 1), context.deinit_counts[0]);
    try std.testing.expectEqual(@as(usize, 0), instances[1].?.turns);
    try std.testing.expectEqual(@as(usize, 0), instances[2].?.turns);

    const second = serviceCollectionTurn(
        TestInstance,
        *TestCollectionContext,
        error{InjectedFailure},
        &context,
        &instances,
        first.live_count,
        first.next_blocking_index,
        turnTestInstance,
        deinitTestInstance,
    );
    try std.testing.expectEqual(@as(usize, 2), second.live_count);
    try std.testing.expect(second.failed == null);
    try std.testing.expectEqual(@as(usize, 1), context.deinit_counts[0]);
    try std.testing.expectEqual(@as(usize, 1), instances[1].?.turns);
    try std.testing.expectEqual(@as(usize, 1), instances[2].?.turns);
    try std.testing.expectEqual(@as(?i32, idle_poll_ms), instances[1].?.last_timeout_ms);
    try std.testing.expectEqual(@as(?i32, 0), instances[2].?.last_timeout_ms);

    const third = serviceCollectionTurn(
        TestInstance,
        *TestCollectionContext,
        error{InjectedFailure},
        &context,
        &instances,
        second.live_count,
        second.next_blocking_index,
        turnTestInstance,
        deinitTestInstance,
    );
    try std.testing.expectEqual(@as(usize, 2), third.live_count);
    try std.testing.expect(third.failed == null);
    try std.testing.expectEqual(@as(?i32, 0), instances[1].?.last_timeout_ms);
    try std.testing.expectEqual(@as(?i32, idle_poll_ms), instances[2].?.last_timeout_ms);

    const fourth = serviceCollectionTurn(
        TestInstance,
        *TestCollectionContext,
        error{InjectedFailure},
        &context,
        &instances,
        third.live_count,
        third.next_blocking_index,
        turnTestInstance,
        deinitTestInstance,
    );
    try std.testing.expectEqual(@as(usize, 2), fourth.live_count);
    try std.testing.expect(fourth.failed == null);
    try std.testing.expectEqual(@as(?i32, idle_poll_ms), instances[1].?.last_timeout_ms);
    try std.testing.expectEqual(@as(?i32, 0), instances[2].?.last_timeout_ms);
}

test "collection skips holes and reports final survivor failure" {
    var context: TestCollectionContext = .{};
    var instances: [4]?TestInstance = .{
        null,
        .{ .name = "last", .id = 1, .fail = true },
        null,
        null,
    };

    const result = serviceCollectionTurn(
        TestInstance,
        *TestCollectionContext,
        error{InjectedFailure},
        &context,
        &instances,
        1,
        3,
        turnTestInstance,
        deinitTestInstance,
    );
    try std.testing.expectEqual(@as(usize, 0), result.live_count);
    try std.testing.expectEqualStrings("last", result.failed.?.name);
    try std.testing.expect(instances[1] == null);
    try std.testing.expectEqual(@as(usize, 1), context.deinit_counts[1]);
}

const RealCollectionTestContext = struct {
    allocator: std.mem.Allocator,
    fail_name: ?[]const u8,
};

const RealCollectionTurnError = endpoint.Server.TurnError || error{InjectedFailure};

fn turnRealCollectionTest(
    context: *RealCollectionTestContext,
    instance: *Instance,
    timeout_ms: i32,
) RealCollectionTurnError!void {
    if (context.fail_name) |name| {
        if (std.mem.eql(u8, instance.name, name)) {
            try instance.server.turn(timeout_ms);
            return error.InjectedFailure;
        }
    }
    try instance.server.turn(timeout_ms);
}

fn deinitRealCollectionTest(context: *RealCollectionTestContext, instance: *Instance) void {
    instance.deinit(context.allocator);
}

fn initRealTestInstance(
    allocator: std.mem.Allocator,
    name: []const u8,
    socket_path: []const u8,
) !Instance {
    std.Io.Dir.deleteFileAbsolute(std.testing.io, socket_path) catch |failure| switch (failure) {
        error.FileNotFound => {},
        else => return failure,
    };
    const owned_path = try allocator.dupe(u8, socket_path);
    errdefer allocator.free(owned_path);
    const owner = try allocator.create(endpoint.Server);
    errdefer allocator.destroy(owner);
    owner.* = try endpoint.Server.init(
        allocator,
        std.testing.io,
        std.testing.environ,
        .{ .unix = socket_path },
        .{
            .shell = "/bin/sh",
            .command = "stty raw -echo; cat",
            .rows = 4,
            .columns = 40,
            .history_rows = 16,
        },
    );
    return .{
        .name = name,
        .socket_path = owned_path,
        .server = owner,
    };
}

fn unixSocketAccepts(path: []const u8) bool {
    var address: linux.sockaddr.un = undefined;
    if (path.len == 0 or path.len >= address.path.len) return false;
    address.family = linux.AF.UNIX;
    @memset(&address.path, 0);
    @memcpy(address.path[0..path.len], path);
    const length: linux.socklen_t =
        @intCast(@offsetOf(linux.sockaddr.un, "path") + path.len + 1);
    const raw = linux.socket(
        linux.AF.UNIX,
        linux.SOCK.STREAM | linux.SOCK.CLOEXEC | linux.SOCK.NONBLOCK,
        0,
    );
    if (linux.errno(raw) != .SUCCESS) return false;
    const fd: posix.fd_t = @intCast(raw);
    defer {
        const result = linux.close(@intCast(fd));
        switch (linux.errno(result)) {
            .SUCCESS, .INTR => {},
            else => @panic("test Unix probe descriptor close failed"),
        }
    }
    const connected = linux.connect(fd, @ptrCast(&address), length);
    return switch (linux.errno(connected)) {
        .SUCCESS, .INPROGRESS, .AGAIN => true,
        else => false,
    };
}

test "real endpoint failure retires one instance while sibling listener survives" {
    var a_path_buffer: [108]u8 = undefined;
    const a_path = try std.fmt.bufPrint(
        &a_path_buffer,
        "/tmp/howl-cli-server-{d}-real-a.sock",
        .{linux.getpid()},
    );
    var b_path_buffer: [108]u8 = undefined;
    const b_path = try std.fmt.bufPrint(
        &b_path_buffer,
        "/tmp/howl-cli-server-{d}-real-b.sock",
        .{linux.getpid()},
    );

    var instances: [2]?Instance = @splat(null);
    instances[0] = try initRealTestInstance(std.testing.allocator, "a", a_path);
    errdefer {
        if (instances[0]) |*instance| instance.deinit(std.testing.allocator);
        instances[0] = null;
    }
    instances[1] = try initRealTestInstance(std.testing.allocator, "b", b_path);
    defer {
        for (&instances) |*maybe_instance| {
            if (maybe_instance.*) |*instance| instance.deinit(std.testing.allocator);
            maybe_instance.* = null;
        }
    }

    var context = RealCollectionTestContext{
        .allocator = std.testing.allocator,
        .fail_name = "a",
    };
    var live_count: usize = 2;
    var blocking_index: usize = 0;
    const failed = serviceCollectionTurn(
        Instance,
        *RealCollectionTestContext,
        RealCollectionTurnError,
        &context,
        &instances,
        live_count,
        blocking_index,
        turnRealCollectionTest,
        deinitRealCollectionTest,
    );
    live_count = failed.live_count;
    blocking_index = failed.next_blocking_index;
    try std.testing.expectEqual(@as(usize, 1), live_count);
    try std.testing.expectEqualStrings("a", failed.failed.?.name);
    try std.testing.expect(instances[0] == null);

    try std.testing.expect(!unixSocketAccepts(a_path));

    try std.testing.expect(unixSocketAccepts(b_path));
    context.fail_name = null;
    const survivor = serviceCollectionTurn(
        Instance,
        *RealCollectionTestContext,
        RealCollectionTurnError,
        &context,
        &instances,
        live_count,
        blocking_index,
        turnRealCollectionTest,
        deinitRealCollectionTest,
    );
    try std.testing.expect(survivor.failed == null);
    live_count = survivor.live_count;
    blocking_index = survivor.next_blocking_index;
    try std.testing.expectEqual(@as(usize, 1), live_count);

    context.fail_name = "b";
    const final = serviceCollectionTurn(
        Instance,
        *RealCollectionTestContext,
        RealCollectionTurnError,
        &context,
        &instances,
        live_count,
        blocking_index,
        turnRealCollectionTest,
        deinitRealCollectionTest,
    );
    try std.testing.expectEqual(@as(usize, 0), final.live_count);
    try std.testing.expectEqualStrings("b", final.failed.?.name);
    try std.testing.expect(instances[1] == null);
}
