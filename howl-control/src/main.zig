//! Runs the reusable terminal control owner and prints one final semantic surface.

const std = @import("std");
const howl_control = @import("howl_control");

const output_buffer_bytes: usize = 4096;

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) {
        std.log.err("usage: {s} '<shell command>'", .{args[0]});
        return error.InvalidArguments;
    }

    const terminal = try howl_control.Terminal.init(
        init.gpa,
        init.io,
        .{ .command = args[1] },
        .{},
    );
    defer terminal.deinit();
    while (terminal.state() == .running) {
        try (std.Io.Clock.Duration{
            .raw = .fromMilliseconds(10),
            .clock = .awake,
        }).sleep(init.io);
    }
    if (terminal.readerError()) |failure| return failure;

    var surface = terminal.surface();
    defer surface.deinit();
    var stdout_buffer: [output_buffer_bytes]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    try writeSnapshot(&stdout_writer.interface, surface.publication.snapshot.view);
    try stdout_writer.interface.flush();
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
