//! Runs the first-party terminal and inspects endpoint-backed Howl Control terminals.

const std = @import("std");
const control = @import("howl_control");
const window = @import("window.zig");

const terminal_limit: usize = 256;
const fallback_shell = "/bin/sh";
const default_output_lines: u16 = 256;
const default_output_bytes: u32 = 1024 * 1024;
const usage =
    \\usage: howl-host window <font-path> [command]
    \\       howl-host serve [command]
    \\       howl-host list
    \\       howl-host status <terminal-id>
    \\       howl-host screen <terminal-id>
    \\       howl-host output <terminal-id> [cursor [max-lines [max-bytes]]]
    \\       howl-host send <terminal-id> <text>
    \\       howl-host resize <terminal-id> <cols> <rows>
    \\       howl-host signal <terminal-id> <hangup|interrupt|terminate|kill>
    \\
;

/// Dispatches one first-party window or one endpoint-backed control command.
pub fn main(init: std.process.Init) !void {
    run(init) catch |failure| {
        var buffer: [512]u8 = undefined;
        var stderr = std.Io.File.stderr().writer(init.io, &buffer);
        if (failure == error.InvalidArguments or failure == error.InvalidTerminalId) {
            stderr.interface.writeAll(usage) catch {};
        } else {
            stderr.interface.print("howl-host: {s}\n", .{@errorName(failure)}) catch {};
        }
        stderr.interface.flush() catch {};
        return failure;
    };
}

fn run(init: std.process.Init) !void {
    const arguments = try init.minimal.args.toSlice(init.gpa);
    defer init.gpa.free(arguments);
    if (arguments.len < 2) return error.InvalidArguments;
    var environment = try init.minimal.environ.createMap(init.gpa);
    defer environment.deinit();
    const runtime_dir = environment.get("XDG_RUNTIME_DIR") orelse
        return error.MissingRuntimeDirectory;
    const shell = selectShell(init.io, environment.get("SHELL"));
    const command = arguments[1];
    if (std.mem.eql(u8, command, "window")) {
        if (arguments.len < 3 or arguments.len > 4) return error.InvalidArguments;
        return window.run(
            init.gpa,
            init.io,
            runtime_dir,
            arguments[2],
            shell,
            if (arguments.len == 4) arguments[3] else null,
        );
    }
    if (std.mem.eql(u8, command, "serve")) {
        if (arguments.len > 3) return error.InvalidArguments;
        return serve(init, runtime_dir, shell, if (arguments.len == 3) arguments[2] else null);
    }
    if (std.mem.eql(u8, command, "list")) {
        if (arguments.len != 2) return error.InvalidArguments;
        return list(init, runtime_dir);
    }
    if (arguments.len < 3) return error.InvalidArguments;
    const terminal_id = control.TerminalId.parse(arguments[2]) catch
        return error.InvalidTerminalId;
    const output_request = if (std.mem.eql(u8, command, "output"))
        try parseOutputArguments(arguments[3..])
    else
        null;
    var client = try control.Client.init(init.gpa, init.io, runtime_dir, terminal_id);
    defer client.deinit();
    if (std.mem.eql(u8, command, "status") and arguments.len == 3)
        return status(init, &client, terminal_id);
    if (std.mem.eql(u8, command, "screen") and arguments.len == 3)
        return screen(init, &client);
    if (output_request) |request| return output(init, &client, request);
    if (std.mem.eql(u8, command, "send") and arguments.len == 4)
        return send(init, &client, arguments[3]);
    if (std.mem.eql(u8, command, "resize") and arguments.len == 5)
        return resize(init, &client, arguments[3], arguments[4]);
    if (std.mem.eql(u8, command, "signal") and arguments.len == 4)
        return signal(init, &client, arguments[3]);
    return error.InvalidArguments;
}

fn serve(
    init: std.process.Init,
    runtime_dir: []const u8,
    shell: []const u8,
    command: ?[]const u8,
) !void {
    var wake_pending: std.atomic.Value(bool) = .init(true);
    const terminal = try control.Terminal.init(
        init.gpa,
        init.io,
        .{ .runtime_dir = runtime_dir, .shell = shell, .command = command },
        .{ .context = &wake_pending, .notify = terminalWake },
    );
    defer terminal.deinit();
    var id_buffer: [32]u8 = undefined;
    var output_buffer: [128]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &output_buffer);
    try stdout.interface.print("{s}\n", .{terminal.id().format(&id_buffer)});
    try stdout.interface.flush();
    while (terminal.state() == .running) {
        if (wake_pending.swap(false, .acq_rel)) {
            terminal.consumeWake();
        }
        try (std.Io.Clock.Duration{
            .raw = .fromMilliseconds(10),
            .clock = .awake,
        }).sleep(init.io);
    }
    terminal.consumeWake();
    if (terminal.readerError()) |failure| return failure;
}

fn selectShell(io: std.Io, candidate: ?[]const u8) []const u8 {
    const path = candidate orelse return fallback_shell;
    if (path.len == 0 or !std.fs.path.isAbsolute(path) or
        std.mem.indexOfScalar(u8, path, 0) != null) return fallback_shell;
    const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch return fallback_shell;
    if (stat.kind != .file) return fallback_shell;
    std.Io.Dir.accessAbsolute(io, path, .{ .execute = true }) catch return fallback_shell;
    return path;
}

const OutputRequest = struct {
    cursor: u64,
    max_lines: u16,
    max_bytes: u32,
};

fn parseOutputArguments(arguments: []const []const u8) error{InvalidArguments}!OutputRequest {
    if (arguments.len > 3) return error.InvalidArguments;
    const result = OutputRequest{
        .cursor = if (arguments.len > 0) try parseUnsigned(u64, arguments[0]) else 0,
        .max_lines = if (arguments.len > 1) try parseUnsigned(u16, arguments[1]) else default_output_lines,
        .max_bytes = if (arguments.len > 2) try parseUnsigned(u32, arguments[2]) else default_output_bytes,
    };
    if (result.max_lines == 0 or result.max_bytes == 0 or result.max_bytes > default_output_bytes)
        return error.InvalidArguments;
    return result;
}

fn parseUnsigned(comptime T: type, bytes: []const u8) error{InvalidArguments}!T {
    return std.fmt.parseUnsigned(T, bytes, 10) catch error.InvalidArguments;
}

fn terminalWake(context: ?*anyopaque) void {
    const pending: *std.atomic.Value(bool) = @ptrCast(@alignCast(context.?));
    pending.store(true, .release);
}

fn list(init: std.process.Init, runtime_dir: []const u8) !void {
    var ids: [terminal_limit]control.TerminalId = undefined;
    const count = try collectIds(init.gpa, init.io, runtime_dir, &ids);
    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    try stdout.interface.writeAll("{\"terminals\":[");
    for (ids[0..count], 0..) |terminal_id, index| {
        if (index != 0) try stdout.interface.writeByte(',');
        var id_buffer: [32]u8 = undefined;
        try stdout.interface.print("\"{s}\"", .{terminal_id.format(&id_buffer)});
    }
    try stdout.interface.writeAll("]}\n");
    try stdout.interface.flush();
}

fn collectIds(
    allocator: std.mem.Allocator,
    io: std.Io,
    runtime_dir: []const u8,
    destination: *[terminal_limit]control.TerminalId,
) !usize {
    const path = try std.fs.path.join(allocator, &.{ runtime_dir, control.endpoint_directory });
    defer allocator.free(path);
    var directory = std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch |failure| switch (failure) {
        error.FileNotFound => return 0,
        else => return failure,
    };
    defer directory.close(io);
    var count: usize = 0;
    var iterator = directory.iterate();
    while (try iterator.next(io)) |entry| {
        const terminal_id = control.TerminalId.parseEndpoint(entry.name) catch continue;
        if (count == destination.len) return error.EndpointLimit;
        destination[count] = terminal_id;
        count += 1;
    }
    std.mem.sort(control.TerminalId, destination[0..count], {}, lessTerminalId);
    return count;
}

fn status(init: std.process.Init, client: *control.Client, terminal_id: control.TerminalId) !void {
    var result = try client.status();
    defer result.deinit();
    var id_buffer: [32]u8 = undefined;
    var buffer: [512]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &buffer);
    try stdout.interface.print(
        "{{\"terminal_id\":\"{s}\",\"state\":\"{s}\",\"cols\":{d},\"rows\":{d}}}\n",
        .{
            terminal_id.format(&id_buffer),
            @tagName(result.value.state),
            result.value.cols,
            result.value.rows,
        },
    );
    try stdout.interface.flush();
}

fn screen(init: std.process.Init, client: *control.Client) !void {
    var value = try client.screen();
    defer value.deinit();
    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    try stdout.interface.writeAll(value.text);
    try stdout.interface.writeByte('\n');
    try stdout.interface.flush();
}

fn output(init: std.process.Init, client: *control.Client, request: OutputRequest) !void {
    var result = try client.output(request.cursor, request.max_lines, request.max_bytes);
    defer deinitOutput(&result);
    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    try writeOutput(&stdout.interface, &result);
    try stdout.interface.writeByte('\n');
    try stdout.interface.flush();
}

fn writeOutput(writer: *std.Io.Writer, result: *const control.LogicalOutputResult) !void {
    switch (result.*) {
        .cursor_stale => |oldest| try std.json.Stringify.value(.{
            .outcome = "cursor_stale",
            .oldest = oldest,
        }, .{}, writer),
        .cursor_ahead => |newest| try std.json.Stringify.value(.{
            .outcome = "cursor_ahead",
            .newest = newest,
        }, .{}, writer),
        .line_too_long => |line| try std.json.Stringify.value(.{
            .outcome = "line_too_long",
            .line = line,
        }, .{}, writer),
        .open_line_too_long => try std.json.Stringify.value(.{
            .outcome = "open_line_too_long",
        }, .{}, writer),
        .output => |value| try std.json.Stringify.value(.{
            .outcome = "output",
            .oldest = value.oldest,
            .cursor = value.cursor,
            .newest = value.newest,
            .semantic_sequence = value.semantic_sequence,
            .line_count = value.line_count,
            .more = value.more,
            .text = value.text,
            .open_line = value.open_line,
            .open_line_omitted = value.open_line_omitted,
            .losses = value.losses,
        }, .{}, writer),
    }
}

fn deinitOutput(result: *control.LogicalOutputResult) void {
    switch (result.*) {
        .output => |*value| value.deinit(),
        .cursor_stale, .cursor_ahead, .line_too_long, .open_line_too_long => {},
    }
}

fn send(init: std.process.Init, client: *control.Client, text: []const u8) !void {
    const result = try client.send(&.{.{ .input = .{ .bytes = text } }});
    var buffer: [192]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &buffer);
    switch (result.outcome) {
        .complete => |transferred| try stdout.interface.print(
            "{{\"outcome\":\"complete\",\"input_sequence\":{d},\"transferred\":{d}}}\n",
            .{ result.input_sequence, transferred },
        ),
        .incomplete => |failure| try stdout.interface.print(
            "{{\"outcome\":\"incomplete\",\"input_sequence\":{d},\"transferred\":{d},\"reason\":\"{s}\"}}\n",
            .{ result.input_sequence, failure.transferred, @tagName(failure.reason) },
        ),
        .rejected => |failure| try stdout.interface.print(
            "{{\"outcome\":\"rejected\",\"input_sequence\":{d},\"transferred\":{d},\"reason\":\"{s}\"}}\n",
            .{ result.input_sequence, failure.transferred, @tagName(failure.reason) },
        ),
    }
    try stdout.interface.flush();
}

fn resize(init: std.process.Init, client: *control.Client, cols_text: []const u8, rows_text: []const u8) !void {
    const cols = std.fmt.parseUnsigned(u16, cols_text, 10) catch return error.InvalidArguments;
    const rows = std.fmt.parseUnsigned(u16, rows_text, 10) catch return error.InvalidArguments;
    const result = try client.resize(cols, rows);
    var buffer: [128]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &buffer);
    try stdout.interface.print(
        "{{\"changed\":{},\"cols\":{d},\"rows\":{d}}}\n",
        .{ result.changed, result.cols, result.rows },
    );
    try stdout.interface.flush();
}

fn signal(init: std.process.Init, client: *control.Client, text: []const u8) !void {
    const value: control.ControlSignal = if (std.mem.eql(u8, text, "hangup"))
        .hangup
    else if (std.mem.eql(u8, text, "interrupt"))
        .interrupt
    else if (std.mem.eql(u8, text, "terminate"))
        .terminate
    else if (std.mem.eql(u8, text, "kill"))
        .kill
    else
        return error.InvalidArguments;
    const result = try client.signal(value);
    var buffer: [128]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &buffer);
    try stdout.interface.print("{{\"outcome\":\"{s}\"}}\n", .{@tagName(result.outcome)});
    try stdout.interface.flush();
}

fn lessTerminalId(_: void, left: control.TerminalId, right: control.TerminalId) bool {
    return std.mem.order(u8, &left.bytes, &right.bytes) == .lt;
}

test "endpoint discovery ignores unrelated files and sorts identities" {
    var random: [8]u8 = undefined;
    std.testing.io.random(&random);
    const runtime_dir = try std.fmt.allocPrint(std.testing.allocator, "/tmp/howl-host-{x}", .{random});
    defer std.testing.allocator.free(runtime_dir);
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, runtime_dir) catch {};
    const endpoint_path = try std.fs.path.join(std.testing.allocator, &.{ runtime_dir, control.endpoint_directory });
    defer std.testing.allocator.free(endpoint_path);
    try std.Io.Dir.createDirPath(.cwd(), std.testing.io, endpoint_path);
    const first = control.TerminalId{ .bytes = .{0x22} ** 16 };
    const second = control.TerminalId{ .bytes = .{0x11} ** 16 };
    var filename: [37]u8 = undefined;
    const first_path = try std.fs.path.join(
        std.testing.allocator,
        &.{ endpoint_path, first.formatEndpoint(&filename) },
    );
    defer std.testing.allocator.free(first_path);
    var file = try std.Io.Dir.cwd().createFile(std.testing.io, first_path, .{});
    file.close(std.testing.io);
    var second_filename: [37]u8 = undefined;
    const second_path = try std.fs.path.join(
        std.testing.allocator,
        &.{ endpoint_path, second.formatEndpoint(&second_filename) },
    );
    defer std.testing.allocator.free(second_path);
    file = try std.Io.Dir.cwd().createFile(std.testing.io, second_path, .{});
    file.close(std.testing.io);
    const unrelated = try std.fs.path.join(std.testing.allocator, &.{ endpoint_path, "note" });
    defer std.testing.allocator.free(unrelated);
    file = try std.Io.Dir.cwd().createFile(std.testing.io, unrelated, .{});
    file.close(std.testing.io);

    var ids: [terminal_limit]control.TerminalId = undefined;
    const count = try collectIds(std.testing.allocator, std.testing.io, runtime_dir, &ids);
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expectEqual(second, ids[0]);
    try std.testing.expectEqual(first, ids[1]);
}

test "operator shell selection admits only absolute executable files" {
    try std.testing.expectEqualStrings(fallback_shell, selectShell(std.testing.io, null));
    try std.testing.expectEqualStrings(fallback_shell, selectShell(std.testing.io, ""));
    try std.testing.expectEqualStrings(fallback_shell, selectShell(std.testing.io, "bin/sh"));
    try std.testing.expectEqualStrings(fallback_shell, selectShell(std.testing.io, "/tmp"));
    try std.testing.expectEqualStrings(fallback_shell, selectShell(std.testing.io, "/etc/passwd"));
    try std.testing.expectEqualStrings(fallback_shell, selectShell(std.testing.io, "/missing/howl-shell"));
    try std.testing.expectEqualStrings(fallback_shell, selectShell(std.testing.io, "/bin/bash\x00tail"));
    try std.testing.expectEqualStrings("/bin/bash", selectShell(std.testing.io, "/bin/bash"));
}

test "selected operator shell executes the exact command override" {
    const terminal = try control.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{
            .shell = selectShell(std.testing.io, "/bin/bash"),
            .command = "printf command-override",
        },
        .{},
    );
    defer terminal.deinit();
    for (0..500) |_| {
        if (terminal.state() != .running) break;
        try (std.Io.Clock.Duration{
            .raw = .fromMilliseconds(10),
            .clock = .awake,
        }).sleep(std.testing.io);
    }
    try std.testing.expectEqual(control.State.stopped, terminal.state());
    var screen_value = try terminal.screen(std.testing.allocator);
    defer screen_value.deinit();
    try std.testing.expect(std.mem.startsWith(u8, screen_value.text, "command-override"));
}

test "output arguments retain exact defaults boundaries and rejection" {
    try std.testing.expectEqual(
        OutputRequest{ .cursor = 0, .max_lines = default_output_lines, .max_bytes = default_output_bytes },
        try parseOutputArguments(&.{}),
    );
    try std.testing.expectEqual(
        OutputRequest{ .cursor = std.math.maxInt(u64), .max_lines = 1, .max_bytes = 1 },
        try parseOutputArguments(&.{ "18446744073709551615", "1", "1" }),
    );
    try std.testing.expectError(error.InvalidArguments, parseOutputArguments(&.{"no"}));
    try std.testing.expectError(error.InvalidArguments, parseOutputArguments(&.{ "0", "0" }));
    try std.testing.expectError(error.InvalidArguments, parseOutputArguments(&.{ "0", "1", "0" }));
    try std.testing.expectError(
        error.InvalidArguments,
        parseOutputArguments(&.{ "0", "1", "1048577" }),
    );
    try std.testing.expectError(error.InvalidArguments, parseOutputArguments(&.{ "0", "1", "1", "1" }));
}

test "output JSON escapes copied bytes and represents cursor limits" {
    const Output = @FieldType(control.LogicalOutputResult, "output");
    const Loss = @typeInfo(@FieldType(Output, "losses")).pointer.child;
    var text = [_]u8{ 'a', '\n', '"', '\\' };
    var open_line = [_]u8{'z'};
    var losses: [0]Loss = .{};
    const result = control.LogicalOutputResult{ .output = .{
        .allocator = std.testing.allocator,
        .text = &text,
        .open_line = &open_line,
        .open_line_omitted = false,
        .losses = &losses,
        .oldest = 1,
        .cursor = 2,
        .newest = 3,
        .line_count = 1,
        .more = true,
        .semantic_sequence = 4,
    } };
    var encoded = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer encoded.deinit();
    try writeOutput(&encoded.writer, &result);
    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        encoded.writer.buffered(),
        .{},
    );
    defer parsed.deinit();
    const object = parsed.value.object;
    try std.testing.expectEqualStrings("output", object.get("outcome").?.string);
    try std.testing.expectEqualStrings(&text, object.get("text").?.string);
    try std.testing.expectEqualStrings(&open_line, object.get("open_line").?.string);
    try std.testing.expectEqual(@as(i64, 4), object.get("semantic_sequence").?.integer);

    var empty_text: [0]u8 = .{};
    var empty_open: [0]u8 = .{};
    const cases = [_]struct { result: control.LogicalOutputResult, outcome: []const u8 }{
        .{ .result = .{ .cursor_stale = 5 }, .outcome = "cursor_stale" },
        .{ .result = .{ .cursor_ahead = 6 }, .outcome = "cursor_ahead" },
        .{ .result = .{ .line_too_long = 7 }, .outcome = "line_too_long" },
        .{ .result = .open_line_too_long, .outcome = "open_line_too_long" },
        .{ .result = .{ .output = .{
            .allocator = std.testing.allocator,
            .text = &empty_text,
            .open_line = &empty_open,
            .open_line_omitted = false,
            .losses = &losses,
            .oldest = 1,
            .cursor = 0,
            .newest = 0,
            .line_count = 0,
            .more = false,
            .semantic_sequence = 1,
        } }, .outcome = "output" },
    };
    for (cases) |case| {
        var value = std.Io.Writer.Allocating.init(std.testing.allocator);
        defer value.deinit();
        try writeOutput(&value.writer, &case.result);
        var decoded = try std.json.parseFromSlice(
            std.json.Value,
            std.testing.allocator,
            value.writer.buffered(),
            .{},
        );
        defer decoded.deinit();
        try std.testing.expectEqualStrings(case.outcome, decoded.value.object.get("outcome").?.string);
    }
}
