//! Proves the reusable native terminal owner against bounded live PTY children.

const std = @import("std");
const headless = @import("howl_headless");

const wait_ms: i64 = 10;
const wait_turns_max: u16 = 500;
const transfer_wait_turns_max: u16 = 2000;

const SendState = enum(u8) { pending, complete, incomplete, failed };

const SendContext = struct {
    terminal: *headless.Terminal,
    bytes: []const u8,
    started: std.atomic.Value(bool) = .init(false),
    state: std.atomic.Value(SendState) = .init(.pending),
    transferred: std.atomic.Value(usize) = .init(0),
};

fn sendBytes(context: *SendContext) void {
    context.started.store(true, .release);
    const transfer = context.terminal.send(.{ .bytes = context.bytes }) catch {
        context.state.store(.failed, .release);
        return;
    };
    context.transferred.store(transfer.transferred(), .release);
    context.state.store(switch (transfer) {
        .complete => .complete,
        .incomplete => .incomplete,
    }, .release);
}

fn countWake(context: ?*anyopaque) void {
    const count: *std.atomic.Value(u32) = @ptrCast(@alignCast(context.?));
    const previous = count.fetchAdd(1, .monotonic);
    std.debug.assert(previous < std.math.maxInt(u32));
}

fn wait(io: std.Io, terminal: *headless.Terminal) !void {
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

fn waitForPrefix(io: std.Io, terminal: *headless.Terminal, expected: []const u8) !void {
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
    const terminal = try headless.Terminal.init(
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

test "live input reaches the child and mutates terminal truth" {
    const terminal = try headless.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "read line; printf '%s' \"$line\"" },
        .{},
    );
    defer terminal.deinit();
    const transfer = try terminal.send(.{ .bytes = "hello\n" });
    try std.testing.expectEqual(@as(usize, 6), transfer.transferred());
    try std.testing.expect(transfer == .complete);
    try wait(std.testing.io, terminal);

    var surface = terminal.surface();
    defer surface.deinit();
    try std.testing.expect(rowStartsWith(surface.publication.snapshot.view, "hello"));
}

test "terminal replies return to a querying child" {
    const command = "stty raw -echo; printf '\\033[c'; dd bs=1 count=9 2>/dev/null | od -An -tx1";
    const terminal = try headless.Terminal.init(
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
    const terminal = try headless.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = command },
        .{},
    );
    defer terminal.deinit();
    try waitForPrefix(std.testing.io, terminal, "ready");

    var input: [headless.max_transfer_bytes]u8 = .{'x'} ** headless.max_transfer_bytes;
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
    const terminal = try headless.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "sleep 1" },
        .{},
    );
    defer terminal.deinit();
    try terminal.resize(100, 40);

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

    try terminal.resize(100, 40);
    var unchanged = terminal.surface();
    defer unchanged.deinit();
    try std.testing.expectEqual(snapshot_seq, unchanged.publication.snapshot_seq);
    try std.testing.expectEqual(dirty_generation, unchanged.publication.dirty_generation);
    try std.testing.expect(unchanged.publication.snapshot.dirty == null);
}

test "deinit stops one live child and reader" {
    const terminal = try headless.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "sleep 30" },
        .{},
    );
    terminal.deinit();
}

test "cancellation ends a saturated input transfer before ordered deinit" {
    const terminal = try headless.Terminal.init(
        std.testing.allocator,
        std.testing.io,
        .{ .command = "stty raw -echo; printf ready; kill -STOP $$", .transfer_timeout_ms = 10_000 },
        .{},
    );
    errdefer terminal.deinit();
    try waitForPrefix(std.testing.io, terminal, "ready");

    var input: [headless.max_transfer_bytes]u8 = .{'x'} ** headless.max_transfer_bytes;
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
