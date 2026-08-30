const std = @import("std");
const transport = @import("howl_transport");

pub fn main(init: std.process.Init) !void {
    const argv = init.minimal.args.vector;
    if (argv.len < 3) return error.InvalidArguments;
    const operation = std.mem.span(argv[1]);
    const endpoint = std.mem.span(argv[2]);
    var connection = try transport.wire.Connection.connect(init.gpa, endpoint);
    defer connection.deinit();

    if (std.mem.eql(u8, operation, "stream")) {
        if (argv.len != 3) return error.InvalidArguments;
        return transport.stream.run(init, &connection);
    }
    if (std.mem.eql(u8, operation, "observe")) {
        if (argv.len > 4) return error.InvalidArguments;
        const history_offset = if (argv.len == 4)
            std.fmt.parseInt(u32, std.mem.span(argv[3]), 10) catch return error.InvalidArguments
        else
            0;
        var buffer: [16 * 1024]u8 = undefined;
        var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);
        try transport.observe.emitSnapshot(&connection, init.gpa, &stdout.interface, history_offset);
        return stdout.interface.flush();
    }
    return error.InvalidArguments;
}
