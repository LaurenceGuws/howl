const std = @import("std");
const terminal_mod = @import("../../src/howl_vt.zig");

const Terminal = terminal_mod.Terminal;

const fixture = @embedFile("../fixtures/tui_zoo_poison_v1.bin");
const fixture_sha256 = "4be2ede6490bce2549f48fe00f04ab801bc1f1d942cda576a929031a96cfb117";
const expected_cell_sha256 = "81f8de1f5abad183b0d31d42c0280ba95dcc4f67e336e73d0eba5972778e8ff4";

const FeedPattern = enum {
    whole,
    bytewise,
    hostile,
};

const Result = struct {
    cells: [32]u8,
    probe_cells: [32]u8,
    cursor_row: u16,
    cursor_col: u16,
};

test "TUI Zoo poison oracle survives hostile feed fragmentation" {
    // Frozen from TUI Zoo 477d9d1:
    //
    // tui-zoo poison
    //   --dose 64 --fps 1000 --frames 16 --seed 0x5eedc0de
    //   --glyph-set printable --cols 17 --rows 9
    //   --synchronized-output --no-alt-screen --oracle
    //
    // stdout is the fixture. stderr independently reported expected_cell_sha256.
    var expected_fixture: [32]u8 = undefined;
    const decoded_fixture = try std.fmt.hexToBytes(&expected_fixture, fixture_sha256);
    try std.testing.expectEqual(@as(usize, expected_fixture.len), decoded_fixture.len);
    var observed_fixture: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(fixture, &observed_fixture, .{});
    try std.testing.expectEqualSlices(u8, &expected_fixture, &observed_fixture);

    var expected_cells: [32]u8 = undefined;
    const decoded_cells = try std.fmt.hexToBytes(&expected_cells, expected_cell_sha256);
    try std.testing.expectEqual(@as(usize, expected_cells.len), decoded_cells.len);

    const whole = try runFixture(.whole);
    try std.testing.expectEqualSlices(u8, &expected_cells, &whole.cells);

    const bytewise = try runFixture(.bytewise);
    try std.testing.expectEqualSlices(u8, &expected_cells, &bytewise.cells);
    try std.testing.expectEqualSlices(u8, &whole.probe_cells, &bytewise.probe_cells);
    try std.testing.expectEqual(whole.cursor_row, bytewise.cursor_row);
    try std.testing.expectEqual(whole.cursor_col, bytewise.cursor_col);

    const hostile = try runFixture(.hostile);
    try std.testing.expectEqualSlices(u8, &expected_cells, &hostile.cells);
    try std.testing.expectEqualSlices(u8, &whole.probe_cells, &hostile.probe_cells);
    try std.testing.expectEqual(whole.cursor_row, hostile.cursor_row);
    try std.testing.expectEqual(whole.cursor_col, hostile.cursor_col);
}

fn runFixture(pattern: FeedPattern) !Result {
    var terminal = try Terminal.init(std.testing.allocator, 9, 17);
    defer terminal.deinit();

    switch (pattern) {
        .whole => try feed(&terminal, fixture),
        .bytewise => {
            for (fixture) |byte| {
                const one = [1]u8{byte};
                try feed(&terminal, &one);
            }
        },
        .hostile => {
            const chunks = [_]usize{ 1, 2, 3, 5, 8, 13, 21, 34 };
            var offset: usize = 0;
            var chunk_index: usize = 0;
            while (offset < fixture.len) : (chunk_index += 1) {
                const count = @min(chunks[chunk_index % chunks.len], fixture.len - offset);
                try feed(&terminal, fixture[offset..][0..count]);
                offset += count;
            }
        },
    }

    try std.testing.expectEqual(@as(usize, 0), terminal.replyBytes().len);
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());

    const cells = try cellDigest(&terminal);

    // A literal printable after the frozen stream pressures hidden cursor/pending-wrap
    // state that the cell oracle itself deliberately does not encode.
    try feed(&terminal, "\x1b[38;5;42mQ");
    const probe_cells = try cellDigest(&terminal);
    const view = terminal.semanticView(0);

    return .{
        .cells = cells,
        .probe_cells = probe_cells,
        .cursor_row = view.cursor_row,
        .cursor_col = view.cursor_col,
    };
}

fn feed(terminal: *Terminal, bytes: []const u8) !void {
    const summary = try terminal.feed(bytes);
    std.debug.assert(!summary.historyLost() or summary.stateChanged());
}

fn cellDigest(terminal: *const Terminal) ![32]u8 {
    const view = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u16, 9), view.rows);
    try std.testing.expectEqual(@as(u16, 17), view.cols);

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("tui-zoo.poison.oracle/v1");

    var geometry: [4]u8 = undefined;
    std.mem.writeInt(u16, geometry[0..2], view.cols, .big);
    std.mem.writeInt(u16, geometry[2..4], view.rows, .big);
    hasher.update(&geometry);

    var encoded: [3]u8 = undefined;
    var row: u16 = 0;
    while (row < view.rows) : (row += 1) {
        for (view.rowCells(row)) |cell| {
            if (cell.codepoint == 0) {
                encoded = .{ 0, 0, 0 };
            } else {
                try std.testing.expect(cell.codepoint <= std.math.maxInt(u8));
                try std.testing.expectEqual(Terminal.ColorKind.indexed, cell.attrs.fg.colorKind());
                try std.testing.expect(cell.attrs.fg.colorValue() <= std.math.maxInt(u8));
                encoded = .{
                    1,
                    @intCast(cell.codepoint),
                    @intCast(cell.attrs.fg.colorValue()),
                };
            }
            hasher.update(&encoded);
        }
    }

    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}
