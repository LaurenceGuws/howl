const std = @import("std");
const transport = @import("howl_transport");

pub fn main(init: std.process.Init) !void {
    const argv = init.minimal.args.vector;
    if (argv.len < 3 or argv.len > 4 or !std.mem.eql(u8, std.mem.span(argv[1]), "observe"))
        return error.InvalidArguments;
    const endpoint = std.mem.span(argv[2]);
    const history_offset = if (argv.len == 4)
        std.fmt.parseInt(u32, std.mem.span(argv[3]), 10) catch return error.InvalidArguments
    else
        0;

    var connection = try transport.wire.Connection.connect(init.gpa, endpoint);
    defer connection.deinit();
    var buffer: [16 * 1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    try transport.observe.emitSnapshot(&connection, init.gpa, &stdout.interface, history_offset);
    try stdout.interface.flush();
}
