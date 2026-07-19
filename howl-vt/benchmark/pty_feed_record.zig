const std = @import("std");
const screen_capture = @import("../test/support/screen_capture.zig");
const terminal_mod = @import("../src/terminal.zig");
const stream_harness = @import("../test/support/stream_harness.zig");

const record_header = "howl-pty-vt-hex-v1";
const Terminal = terminal_mod.Terminal;
const StreamHarness = stream_harness.Harness;

pub const Record = struct {
    allocator: std.mem.Allocator,
    chunks: std.ArrayListUnmanaged([]u8) = .empty,

    pub fn deinit(self: *Record) void {
        for (self.chunks.items) |chunk| self.allocator.free(chunk);
        self.chunks.deinit(self.allocator);
        self.* = undefined;
    }
};

pub fn load(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !Record {
    const text = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(16 * 1024 * 1024));
    defer allocator.free(text);
    return parse(allocator, text);
}

pub fn parse(allocator: std.mem.Allocator, text: []const u8) !Record {
    var record = Record{ .allocator = allocator };
    errdefer record.deinit();

    var lines = std.mem.splitScalar(u8, text, '\n');
    const header = trimCr(lines.next() orelse return error.InvalidRecordHeader);
    if (!std.mem.eql(u8, header, record_header)) return error.InvalidRecordHeader;

    while (lines.next()) |line| {
        const hex = trimCr(line);
        if (hex.len == 0) continue;
        const chunk = try allocator.alloc(u8, hex.len / 2);
        errdefer allocator.free(chunk);
        _ = try std.fmt.hexToBytes(chunk, hex);
        try record.chunks.append(allocator, chunk);
    }
    return record;
}

pub fn replay(terminal: *Terminal, record: *const Record) !void {
    var stream = try StreamHarness.init(terminal);
    for (record.chunks.items) |chunk| try stream.nextSlice(chunk);
}

pub fn byteLen(record: *const Record) u64 {
    var total: u64 = 0;
    for (record.chunks.items) |chunk| total += chunk.len;
    return total;
}

fn trimCr(line: []const u8) []const u8 {
    if (line.len != 0 and line[line.len - 1] == '\r') return line[0 .. line.len - 1];
    return line;
}

fn captureSnapshot(terminal: *const Terminal) !screen_capture.Capture {
    return screen_capture.Capture.captureFromScreen(
        terminal.allocator,
        terminal.screen_state.activeConst(),
        terminal.screen_state.activeSelectionConst().state(),
    );
}

test "pty feed record parses chunk lines" {
    const gpa = std.testing.allocator;
    var record = try parse(
        gpa,
        record_header ++ "\n" ++
            "4142\n" ++
            "434445\n",
    );
    defer record.deinit();

    try std.testing.expectEqual(@as(u32, 2), @as(u32, @intCast(record.chunks.items.len)));
    try std.testing.expectEqualStrings("AB", record.chunks.items[0]);
    try std.testing.expectEqualStrings("CDE", record.chunks.items[1]);
}

test "pty feed replay matches whole feed" {
    const gpa = std.testing.allocator;
    const fixture = "ABC\nDEF\x1b[31mRED\x1b[0m";

    var whole = try Terminal.init(gpa, 4, 16);
    defer whole.deinit();
    var whole_stream = try StreamHarness.init(&whole);
    try whole_stream.nextSlice(fixture);
    var whole_snap = try captureSnapshot(&whole);
    defer whole_snap.deinit();

    var record = try parse(
        gpa,
        record_header ++ "\n" ++
            "4142430a44\n" ++
            "45461b5b33316d52\n" ++
            "45441b5b306d\n",
    );
    defer record.deinit();

    var replayed = try Terminal.init(gpa, 4, 16);
    defer replayed.deinit();
    try replay(&replayed, &record);
    var replay_snap = try captureSnapshot(&replayed);
    defer replay_snap.deinit();

    try std.testing.expectEqual(whole_snap.cursor_row, replay_snap.cursor_row);
    try std.testing.expectEqual(whole_snap.cursor_col, replay_snap.cursor_col);
    try std.testing.expectEqual(whole_snap.cursor_visible, replay_snap.cursor_visible);
    try std.testing.expectEqual(whole_snap.auto_wrap, replay_snap.auto_wrap);
    if (whole_snap.cells != null and replay_snap.cells != null) {
        try std.testing.expectEqualSlices(u21, whole_snap.cells.?, replay_snap.cells.?);
    }
}
