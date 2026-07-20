//! Proves the reusable native terminal owner against bounded live PTY children.

const std = @import("std");
const control = @import("howl_control");

const wait_ms: i64 = 10;
const wait_turns_max: u16 = 500;
const transfer_wait_turns_max: u16 = 2000;

const SendState = enum(u8) { pending, complete, incomplete, failed };

const SendContext = struct {
    terminal: *control.Terminal,
    bytes: []const u8,
    started: std.atomic.Value(bool) = .init(false),
    state: std.atomic.Value(SendState) = .init(.pending),
    transferred: std.atomic.Value(usize) = .init(0),
};

fn sendBytes(context: *SendContext) void {
    context.started.store(true, .release);
    const result = context.terminal.send(&.{.{ .input = .{ .bytes = context.bytes } }}) catch {
        context.state.store(.failed, .release);
        return;
    };
    context.transferred.store(switch (result.outcome) {
        .complete => |count| count,
        .incomplete => |failure| failure.transferred,
        .rejected => |failure| failure.transferred,
    }, .release);
    context.state.store(switch (result.outcome) {
        .complete => .complete,
        .incomplete => .incomplete,
        .rejected => .incomplete,
    }, .release);
}

fn countWake(context: ?*anyopaque) void {
    const count: *std.atomic.Value(u32) = @ptrCast(@alignCast(context.?));
    const previous = count.fetchAdd(1, .monotonic);
    std.debug.assert(previous < std.math.maxInt(u32));
}

fn wait(io: std.Io, terminal: *control.Terminal) !void {
    var turns: u16 = 0;
    while (terminal.state() == .running and turns < wait_turns_max) : (turns += 1) {
        try (std.Io.Clock.Duration{
            .raw = .fromMilliseconds(wait_ms),
            .clock = .awake,
        }).sleep(io);
    }
    if (terminal.readerError()) |failure| return failure;
    if (terminal.state() == .running) return error.TestTimeout;
}

fn rowStartsWith(view: anytype, expected: []const u8) bool {
    if (expected.len > view.cols) return false;
    for (expected, 0..) |byte, col| {
        if (view.cellAt(0, @intCast(col)) != byte) return false;
    }
    return true;
}

fn viewContains(view: anytype, expected: []const u8) bool {
    if (expected.len == 0 or expected.len > view.cols) return false;
    for (0..view.rows) |row| {
        for (0..view.cols - expected.len + 1) |start| {
            for (expected, 0..) |byte, offset| {
                if (view.cellAt(@intCast(row), @intCast(start + offset)) != byte) break;
            } else return true;
        }
    }
    return false;
}

fn testRuntimeDir() ![]u8 {
    var random: [8]u8 = undefined;
    std.testing.io.random(&random);
    return std.fmt.allocPrint(std.testing.allocator, "/tmp/howl-control-{x}", .{random});
}

const ConcurrentInput = struct {
    terminal: ?*control.Terminal = null,
    client: ?*control.Client = null,
    gate: *std.atomic.Value(bool),
    bytes: []const u8,
    sequence: u64 = 0,
    succeeded: bool = false,
};

fn concurrentInput(context: *ConcurrentInput) void {
    while (!context.gate.load(.acquire)) std.atomic.spinLoopHint();
    const result = if (context.terminal) |terminal|
        terminal.send(&.{.{ .input = .{ .bytes = context.bytes } }}) catch return
    else
        context.client.?.send(&.{.{ .input = .{ .bytes = context.bytes } }}) catch return;
    if (result.outcome != .complete) return;
    context.sequence = result.input_sequence;
    context.succeeded = true;
}

fn waitForPrefix(io: std.Io, terminal: *control.Terminal, expected: []const u8) !void {
    var turns: u16 = 0;
    while (turns < wait_turns_max) : (turns += 1) {
        var surface = terminal.surface();
        const found = rowStartsWith(surface.publication.snapshot.view, expected);
        surface.deinit();
        if (found) return;
        if (terminal.readerError()) |failure| return failure;
        try (std.Io.Clock.Duration{
            .raw = .fromMilliseconds(wait_ms),
            .clock = .awake,
        }).sleep(io);
    }
    return error.TestTimeout;
}

test "owner captures one child semantic surface" {
    var wake_count: std.atomic.Value(u32) = .init(0);
    const terminal = try control.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "printf headless" },
        .{ .context = &wake_count, .notify = countWake },
    );
    defer terminal.deinit();
    try wait(std.testing.io, terminal);

    var surface = terminal.surface();
    defer surface.deinit();
    try std.testing.expectEqual(@as(u16, 24), surface.publication.snapshot.view.rows);
    try std.testing.expect(rowStartsWith(surface.publication.snapshot.view, "headless"));
    try std.testing.expect(surface.acknowledge());
    try std.testing.expectEqual(@as(u32, 1), wake_count.load(.monotonic));
    terminal.consumeWake();
}

test "local endpoint shares identity operations ordering and owned unlink" {
    const runtime_dir = try testRuntimeDir();
    defer std.testing.allocator.free(runtime_dir);
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, runtime_dir) catch {};
    var terminal = try control.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .runtime_dir = runtime_dir, .command = "stty raw -echo; cat" },
        .{},
    );
    var client = try control.Client.init(
        std.testing.allocator,
        std.testing.io,
        runtime_dir,
        terminal.id(),
    );
    defer client.deinit();
    const endpoint = terminal.endpoint().?;
    const endpoint_stat = try std.Io.Dir.cwd().statFile(std.testing.io, endpoint, .{});
    try std.testing.expectEqual(
        @as(std.posix.mode_t, 0o600),
        endpoint_stat.permissions.toMode() & 0o777,
    );
    const directory_stat = try std.Io.Dir.cwd().statFile(
        std.testing.io,
        std.fs.path.dirname(endpoint).?,
        .{},
    );
    try std.testing.expectEqual(
        @as(std.posix.mode_t, 0o700),
        directory_stat.permissions.toMode() & 0o777,
    );
    const remote = try client.send(&.{.{ .input = .{ .bytes = "a\x00\x1b[b" } }});
    try std.testing.expectEqual(@as(u64, 1), remote.input_sequence);
    const direct = try terminal.send(&.{.{ .input = .{ .bytes = "operator" } }});
    try std.testing.expectEqual(@as(u64, 2), direct.input_sequence);
    var observed = try client.status();
    defer observed.deinit();
    try std.testing.expectEqual(terminal.id(), observed.value.terminal_id);
    try std.testing.expectEqual(@as(u64, 2), observed.value.input_sequence);

    const endpoint_copy = try std.testing.allocator.dupe(u8, endpoint);
    defer std.testing.allocator.free(endpoint_copy);
    terminal.deinit();
    try std.testing.expectError(error.TerminalClosed, client.status());
    try std.testing.expectError(
        error.FileNotFound,
        std.Io.Dir.openFileAbsolute(std.testing.io, endpoint_copy, .{}),
    );
}

test "direct and client primitives return the same control evidence" {
    const runtime_dir = try testRuntimeDir();
    defer std.testing.allocator.free(runtime_dir);
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, runtime_dir) catch {};
    const terminal = try control.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{
            .runtime_dir = runtime_dir,
            .command = "printf 'one\r\nopen'; sleep 30",
        },
        .{},
    );
    defer terminal.deinit();
    try waitForPrefix(std.testing.io, terminal, "one");
    var client = try control.Client.init(
        std.testing.allocator,
        std.testing.io,
        runtime_dir,
        terminal.id(),
    );
    defer client.deinit();

    const resized = try client.resize(81, 25);
    try std.testing.expect(resized.changed);
    try std.testing.expectEqual(@as(u16, 81), resized.cols);
    var screen = try client.screen();
    defer screen.deinit();
    try std.testing.expectEqual(@as(u16, 81), screen.cols);
    try std.testing.expect(std.mem.indexOf(u8, screen.text, "open") != null);
    var output = switch (try client.output(0, 8, 128)) {
        .output => |value| value,
        else => return error.UnexpectedOutputResult,
    };
    defer output.deinit();
    try std.testing.expectEqualStrings("one", output.text);
    try std.testing.expectEqualStrings("open", output.open_line);
    const signaled = try client.signal(.interrupt);
    try std.testing.expectEqual(control.ControlResult.delivered, signaled.outcome);
    var status = try client.status();
    defer status.deinit();
    try std.testing.expectEqual(signaled.admission_sequence, status.value.admission_sequence);
}

test "direct and client input share complete noninterleaved admission" {
    const runtime_dir = try testRuntimeDir();
    defer std.testing.allocator.free(runtime_dir);
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, runtime_dir) catch {};
    const terminal = try control.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{
            .runtime_dir = runtime_dir,
            .command =
            \\stty raw -echo
            \\value=$(dd bs=8 count=1 iflag=fullblock 2>/dev/null)
            \\case "$value" in aaaabbbb|bbbbaaaa) printf serialized;; *) printf interleaved;; esac
            ,
        },
        .{},
    );
    defer terminal.deinit();
    var client = try control.Client.init(
        std.testing.allocator,
        std.testing.io,
        runtime_dir,
        terminal.id(),
    );
    defer client.deinit();
    var gate = std.atomic.Value(bool).init(false);
    var direct = ConcurrentInput{ .terminal = terminal, .gate = &gate, .bytes = "aaaa" };
    var remote = ConcurrentInput{ .client = &client, .gate = &gate, .bytes = "bbbb" };
    const direct_thread = try std.Thread.spawn(.{}, concurrentInput, .{&direct});
    const remote_thread = try std.Thread.spawn(.{}, concurrentInput, .{&remote});
    gate.store(true, .release);
    direct_thread.join();
    remote_thread.join();
    try std.testing.expect(direct.succeeded);
    try std.testing.expect(remote.succeeded);
    try std.testing.expect(direct.sequence != remote.sequence);
    try wait(std.testing.io, terminal);
    var screen = try client.screen();
    defer screen.deinit();
    try std.testing.expect(std.mem.indexOf(u8, screen.text, "serialized") != null);
    try std.testing.expect(std.mem.indexOf(u8, screen.text, "interleaved") == null);
}

test "status and logical output form one coherent control observation" {
    const terminal = try control.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "printf 'one\\r\\ntwo\\r\\nopen'" },
        .{},
    );
    defer terminal.deinit();
    try wait(std.testing.io, terminal);

    const status = terminal.status();
    try std.testing.expectEqual(control.State.stopped, status.state);
    try std.testing.expectEqual(@as(?control.ReaderError, null), status.reader_error);
    try std.testing.expectEqual(@as(?usize, null), status.reply_failure_transferred);
    try std.testing.expectEqual(@as(u64, 0), status.history_loss_generation);
    try std.testing.expectEqual(@as(u64, 1), status.output_oldest);
    try std.testing.expectEqual(@as(u64, 2), status.output_newest);
    try std.testing.expectEqual(@as(?control.ShellMark, null), status.shell_mark);

    var output = switch (try terminal.output(std.testing.allocator, 0, 8, 128)) {
        .output => |value| value,
        else => return error.UnexpectedOutputResult,
    };
    defer output.deinit();
    try std.testing.expectEqualStrings("one\ntwo", output.text);
    try std.testing.expectEqualStrings("open", output.open_line);
    try std.testing.expectEqual(status.publication, output.publication);
}

test "status copies retained shell mark facts and shell identity" {
    const terminal = try control.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "printf '\\033]1337;ShellIntegrationVersion=20;shell=bash\\a" ++
            "\\033]133;D;7\\a'" },
        .{},
    );
    defer terminal.deinit();
    try wait(std.testing.io, terminal);
    const mark = terminal.status().shell_mark.?;
    try std.testing.expectEqual(@as(u64, 1), mark.generation);
    try std.testing.expectEqual(@as(u8, 'D'), mark.kind);
    try std.testing.expectEqual(@as(?i32, 7), mark.status);
    try std.testing.expectEqualStrings("7", mark.metadataBytes());
    try std.testing.expectEqualStrings("bash", mark.shellBytes().?);
}

test "signal forwards exact process-group control outcomes" {
    const terminal = try control.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "printf ready; sleep 30" },
        .{},
    );
    defer terminal.deinit();
    try waitForPrefix(std.testing.io, terminal, "ready");
    try std.testing.expectEqual(control.ControlResult.delivered, terminal.signal(.interrupt).outcome);
    try wait(std.testing.io, terminal);
    try std.testing.expectEqual(
        control.ControlResult.target_missing,
        terminal.signal(.interrupt).outcome,
    );
}

test "live input reaches the child and mutates terminal truth" {
    const terminal = try control.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "read line; printf '%s' \"$line\"" },
        .{},
    );
    defer terminal.deinit();
    const transfer = try terminal.send(&.{.{ .input = .{ .bytes = "hello\n" } }});
    try std.testing.expectEqual(@as(usize, 6), transfer.outcome.complete);
    try wait(std.testing.io, terminal);

    var surface = terminal.surface();
    defer surface.deinit();
    try std.testing.expect(rowStartsWith(surface.publication.snapshot.view, "hello"));
}

test "terminal replies return to a querying child" {
    const command = "stty raw -echo; printf '\\033[c'; dd bs=1 count=9 2>/dev/null | od -An -tx1";
    const terminal = try control.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = command },
        .{},
    );
    defer terminal.deinit();
    try wait(std.testing.io, terminal);

    var surface = terminal.surface();
    defer surface.deinit();
    try std.testing.expect(rowStartsWith(
        surface.publication.snapshot.view,
        " 1b 5b 3f 36 32 3b 32 32 63",
    ));
}

test "waiting input transfer leaves the model available to drain child output" {
    const command =
        "stty raw -echo; printf ready; " ++
        "dd if=/dev/zero bs=4096 count=16 2>/dev/null; printf '\\033[c'; " ++
        "dd iflag=fullblock of=/dev/null bs=4096 count=16 2>/dev/null; " ++
        "dd iflag=fullblock of=/dev/null bs=1 count=9 2>/dev/null; " ++
        "printf transfer-complete";
    const terminal = try control.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = command },
        .{},
    );
    defer terminal.deinit();
    try waitForPrefix(std.testing.io, terminal, "ready");

    var input: [control.max_transfer_bytes]u8 = .{'x'} ** control.max_transfer_bytes;
    var send_context = SendContext{ .terminal = terminal, .bytes = &input };
    const sender = try std.Thread.spawn(.{}, sendBytes, .{&send_context});

    var turns: u16 = 0;
    while (send_context.state.load(.acquire) == .pending and
        turns < transfer_wait_turns_max) : (turns += 1)
    {
        try (std.Io.Clock.Duration{
            .raw = .fromMilliseconds(wait_ms),
            .clock = .awake,
        }).sleep(std.testing.io);
    }
    const timed_out = send_context.state.load(.acquire) == .pending;
    if (timed_out) terminal.cancel();
    sender.join();
    if (timed_out) return error.TransferDeadlock;
    try std.testing.expectEqual(SendState.complete, send_context.state.load(.acquire));
    try std.testing.expectEqual(input.len, send_context.transferred.load(.acquire));
    try wait(std.testing.io, terminal);

    var surface = terminal.surface();
    defer surface.deinit();
    try std.testing.expect(viewContains(
        surface.publication.snapshot.view,
        "transfer-complete",
    ));
}

test "resize publishes only changed dimensions" {
    const terminal = try control.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "sleep 1" },
        .{},
    );
    defer terminal.deinit();
    try std.testing.expect((try terminal.resize(100, 40)).changed);

    var snapshot_seq: u64 = undefined;
    var dirty_generation: u64 = undefined;
    {
        var surface = terminal.surface();
        defer surface.deinit();
        try std.testing.expectEqual(@as(u16, 100), surface.publication.snapshot.view.cols);
        try std.testing.expectEqual(@as(u16, 40), surface.publication.snapshot.view.rows);
        snapshot_seq = surface.publication.snapshot_seq;
        dirty_generation = surface.publication.dirty_generation;
        try std.testing.expect(surface.acknowledge());
    }

    try std.testing.expect(!(try terminal.resize(100, 40)).changed);
    var unchanged = terminal.surface();
    defer unchanged.deinit();
    try std.testing.expectEqual(snapshot_seq, unchanged.publication.snapshot_seq);
    try std.testing.expectEqual(dirty_generation, unchanged.publication.dirty_generation);
    try std.testing.expect(unchanged.publication.snapshot.dirty == null);
}

test "model resize allocation failure restores prior PTY geometry" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const terminal = try control.Terminal.init(
        failing.allocator(),
        std.testing.io,
        .{ .command = "sleep 30" },
        .{},
    );
    defer terminal.deinit();
    failing.fail_index = failing.alloc_index;

    try std.testing.expectError(error.OutOfMemory, terminal.resize(100, 40));
    try std.testing.expect(failing.has_induced_failure);
    const status = terminal.status();
    try std.testing.expectEqual(control.State.running, status.state);
    try std.testing.expect(!status.resize_rollback_failed);
    try std.testing.expectEqual(@as(u16, 80), status.cols);
    try std.testing.expectEqual(@as(u16, 24), status.rows);
}

test "deinit stops one live child and reader" {
    const terminal = try control.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "sleep 30" },
        .{},
    );
    terminal.deinit();
}

test "cancellation ends a saturated input transfer before ordered deinit" {
    const terminal = try control.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "stty raw -echo; printf ready; kill -STOP $$", .transfer_timeout_ms = 10_000 },
        .{},
    );
    errdefer terminal.deinit();
    try waitForPrefix(std.testing.io, terminal, "ready");

    var input: [control.max_transfer_bytes]u8 = .{'x'} ** control.max_transfer_bytes;
    var send_context = SendContext{ .terminal = terminal, .bytes = &input };
    const sender = try std.Thread.spawn(.{}, sendBytes, .{&send_context});
    while (!send_context.started.load(.acquire)) std.atomic.spinLoopHint();
    try (std.Io.Clock.Duration{
        .raw = .fromMilliseconds(10),
        .clock = .awake,
    }).sleep(std.testing.io);
    terminal.cancel();
    sender.join();
    try std.testing.expectEqual(SendState.incomplete, send_context.state.load(.acquire));
    try std.testing.expect(send_context.transferred.load(.acquire) < input.len);
    terminal.deinit();
}
