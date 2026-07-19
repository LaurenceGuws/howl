//! Runs one bounded child command and prints its final semantic terminal view.

const std = @import("std");
const howl_pty = @import("howl_pty");
const howl_vt = @import("howl_vt");

const rows: u16 = 24;
const cols: u16 = 80;
const wait_timeout_ms: i32 = 25;
const wait_turns_max: u16 = 200;
const transport_buffer_bytes: usize = 4096;
const DrainError = error{
    ChildTimeout,
    ConsequenceLimit,
    OutOfMemory,
    ParsedEventLimit,
    ReadFailed,
    StringControlLimit,
    WaitFailed,
};

/// Launches one command, drains its bounded PTY output, and writes the final semantic screen.
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) {
        std.log.err("usage: {s} '<shell command>'", .{args[0]});
        return error.InvalidArguments;
    }

    var owned = try howl_pty.Owned.init(init.gpa, "/bin/sh", args[1], null);
    defer owned.deinit();

    var terminal = try howl_vt.Terminal.init(init.gpa, rows, cols);
    defer terminal.deinit();

    try owned.start(cols, rows);
    try drainChild(&owned, &terminal);

    var stdout_buffer: [transport_buffer_bytes]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try writeSnapshot(stdout, terminal.surfaceSnapshot().snapshot.view);
    try stdout.flush();
}

test "native terminal model initializes one bounded cell" {
    var terminal = try howl_vt.Terminal.init(std.testing.allocator, 1, 1);
    defer terminal.deinit();

    const view = terminal.surfaceSnapshot().snapshot.view;
    try std.testing.expectEqual(@as(u16, 1), view.rows);
    try std.testing.expectEqual(@as(u16, 1), view.cols);
}

test "owned PTY launches a child into the bounded terminal model" {
    var owned = try howl_pty.Owned.init(std.testing.allocator, "/bin/sh", "printf headless", null);
    defer owned.deinit();

    var terminal = try howl_vt.Terminal.init(std.testing.allocator, rows, cols);
    defer terminal.deinit();

    try owned.start(cols, rows);
    try drainChild(&owned, &terminal);

    const view = terminal.surfaceSnapshot().snapshot.view;
    try std.testing.expectEqual(rows, view.rows);
    try std.testing.expectEqual(cols, view.cols);
    try std.testing.expect(rowStartsWith(view, "headless"));
}

test "owned PTY cleanup stops a running child" {
    var owned = try howl_pty.Owned.init(std.testing.allocator, "/bin/sh", "sleep 30", null);
    try owned.start(cols, rows);
    owned.deinit();
}

fn rowStartsWith(view: anytype, expected: []const u8) bool {
    if (expected.len > view.cols) return false;
    for (expected, 0..) |byte, col| {
        if (view.cellAt(0, @intCast(col)) != byte) return false;
    }
    return true;
}

fn drainChild(transport: *howl_pty.Owned, terminal: *howl_vt.Terminal) DrainError!void {
    var scratch: [transport_buffer_bytes]u8 = undefined;
    var waits: u16 = 0;
    while (waits < wait_turns_max) : (waits += 1) {
        const outcome = transport.waitReadable(wait_timeout_ms) catch |failure| switch (failure) {
            error.NotStarted => return,
            error.Interrupted, error.WouldBlock => continue,
            error.WaitFailed => return error.WaitFailed,
        };
        switch (outcome) {
            .timeout, .wake => continue,
            .ready => {},
        }
        const count = transport.read(&scratch) catch |failure| switch (failure) {
            error.EndOfStream, error.NotStarted => return,
            error.Interrupted, error.WouldBlock => continue,
            error.ReadFailed => return error.ReadFailed,
        };
        std.debug.assert(count <= scratch.len);
        if (count > 0) _ = try terminal.feed(scratch[0..count]);
    }
    return error.ChildTimeout;
}

fn writeSnapshot(writer: *std.Io.Writer, view: anytype) std.Io.Writer.Error!void {
    var row_count: usize = view.rows;
    while (row_count > 0 and rowContentEnd(view, @intCast(row_count - 1)) == 0) {
        row_count -= 1;
    }
    for (0..row_count) |row| {
        const end = rowContentEnd(view, @intCast(row));
        for (0..end) |col| {
            const codepoint = view.cellAt(@intCast(row), @intCast(col));
            try writer.printUnicodeCodepoint(if (codepoint == 0) ' ' else codepoint);
        }
        try writer.writeByte('\n');
    }
}

fn rowContentEnd(view: anytype, row: u16) u16 {
    var col = view.cols;
    while (col > 0) {
        col -= 1;
        const codepoint = view.cellAt(row, col);
        if (codepoint != 0 and codepoint != ' ') return col + 1;
    }
    return 0;
}
