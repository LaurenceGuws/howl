//! Exposes the small non-GUI operator and agent surface for shared Howl sessions.

const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;
const howl = @import("howl_cli");
const session_protocol = howl.protocol;

const Exit = enum(u8) { ok = 0, usage = 2, failure = 1 };
const maximum_stdin_bytes: usize = howl.input.maximum_sequence_bytes;

/// Runs the maintained Howl CLI and maps bounded failures to stable process exits.
pub fn main(init: std.process.Init) void {
    const exit = run(init) catch |failure| {
        writeStderr("howl: ") catch return std.process.exit(@backingInt(Exit.failure));
        writeStderr(@errorName(failure)) catch return std.process.exit(@backingInt(Exit.failure));
        writeStderr("\n") catch return std.process.exit(@backingInt(Exit.failure));
        return std.process.exit(@backingInt(Exit.failure));
    };
    if (exit != .ok) std.process.exit(@backingInt(exit));
}

fn run(init: std.process.Init) !Exit {
    const argv = init.minimal.args.vector;
    if (argv.len < 2) return usage();
    const command = std.mem.span(argv[1]);
    if (std.mem.eql(u8, command, "sessions")) return sessionsCommand(init);
    if (std.mem.eql(u8, command, "paste")) return pasteCommand(init);
    if (std.mem.eql(u8, command, "key")) return keyCommand(init);
    if (std.mem.eql(u8, command, "chord")) return chordCommand(init);
    if (std.mem.eql(u8, command, "hold")) return holdCommand(init);
    if (std.mem.eql(u8, command, "sequence")) return sequenceCommand(init);
    if (std.mem.eql(u8, command, "signal")) return signalCommand(init);
    if (std.mem.eql(u8, command, "resize")) return resizeCommand(init);
    return usage();
}

fn usage() error{OutputFailed}!Exit {
    try writeStderr(
        "usage:\n" ++
            "  howl sessions [--json]\n" ++
            "  howl paste SESSION TEXT|--stdin\n" ++
            "  howl key SESSION KEY [press|repeat|release] [--mods MODS]\n" ++
            "  howl chord SESSION MOD+KEY\n" ++
            "  howl hold SESSION KEY --for DURATION\n" ++
            "  howl sequence SESSION --stdin\n" ++
            "  howl signal SESSION hangup|interrupt|resize|kill|terminate\n" ++
            "  howl resize SESSION ROWS COLUMNS\n",
    );
    return .usage;
}

fn sessionsCommand(init: std.process.Init) !Exit {
    const argv = init.minimal.args.vector;
    if (argv.len == 2) return sessions(init, false);
    if (argv.len == 3 and std.mem.eql(u8, std.mem.span(argv[2]), "--json"))
        return sessions(init, true);
    return usage();
}

fn pasteCommand(init: std.process.Init) !Exit {
    const argv = init.minimal.args.vector;
    if (argv.len != 4) return usage();
    var connection = try connectNamed(init, std.mem.span(argv[2]));
    defer connection.deinit();
    const argument = std.mem.span(argv[3]);
    if (std.mem.eql(u8, argument, "--stdin")) {
        var input_buffer: [maximum_stdin_bytes + 1]u8 = undefined;
        const input = try readStdin(&input_buffer);
        if (input.len == 0) return error.InvalidInput;
        try expectOk(try connection.paste(input));
    } else {
        try expectOk(try connection.paste(argument));
    }
    return .ok;
}

fn keyCommand(init: std.process.Init) !Exit {
    const argv = init.minimal.args.vector;
    if (argv.len < 4 or argv.len > 7) return usage();
    var connection = try connectNamed(init, std.mem.span(argv[2]));
    defer connection.deinit();
    const key = try howl.input.parseKey(std.mem.span(argv[3]));
    var action: ?session_protocol.InputKeyAction = null;
    var modifiers: u8 = 0;
    var index: usize = 4;
    if (index < argv.len and !std.mem.eql(u8, std.mem.span(argv[index]), "--mods")) {
        action = parseKeyAction(std.mem.span(argv[index])) orelse return usage();
        index += 1;
    }
    if (index < argv.len) {
        if (index + 2 != argv.len or !std.mem.eql(u8, std.mem.span(argv[index]), "--mods"))
            return usage();
        modifiers = try howl.input.parseModifiers(std.mem.span(argv[index + 1]));
    }
    if (action) |explicit| {
        try howl.input.sendKey(&connection, key, explicit, modifiers);
    } else {
        try howl.input.tap(&connection, key, modifiers);
    }
    return .ok;
}

fn chordCommand(init: std.process.Init) !Exit {
    const argv = init.minimal.args.vector;
    if (argv.len != 4) return usage();
    var connection = try connectNamed(init, std.mem.span(argv[2]));
    defer connection.deinit();
    try howl.input.chord(&connection, std.mem.span(argv[3]));
    return .ok;
}

fn holdCommand(init: std.process.Init) !Exit {
    const argv = init.minimal.args.vector;
    if (argv.len != 6 or !std.mem.eql(u8, std.mem.span(argv[4]), "--for")) return usage();
    var connection = try connectNamed(init, std.mem.span(argv[2]));
    defer connection.deinit();
    const key = try howl.input.parseKey(std.mem.span(argv[3]));
    const duration = try howl.input.parseDuration(std.mem.span(argv[5]));
    try howl.input.hold(&connection, init.io, key, duration);
    return .ok;
}

fn sequenceCommand(init: std.process.Init) !Exit {
    const argv = init.minimal.args.vector;
    if (argv.len != 4 or !std.mem.eql(u8, std.mem.span(argv[3]), "--stdin")) return usage();
    var source_buffer: [howl.input.maximum_sequence_bytes + 1]u8 = undefined;
    const source = try readStdin(&source_buffer);
    const sequence = try howl.input.parseSequence(source);
    var connection = try connectNamed(init, std.mem.span(argv[2]));
    defer connection.deinit();
    try howl.input.executeSequence(&connection, init.io, &sequence);
    return .ok;
}

fn signalCommand(init: std.process.Init) !Exit {
    const argv = init.minimal.args.vector;
    if (argv.len != 4) return usage();
    const value = parseSignal(std.mem.span(argv[3])) orelse return usage();
    var connection = try connectNamed(init, std.mem.span(argv[2]));
    defer connection.deinit();
    try expectOk(try connection.signal(value));
    return .ok;
}

fn resizeCommand(init: std.process.Init) !Exit {
    const argv = init.minimal.args.vector;
    if (argv.len != 5) return usage();
    const rows = std.fmt.parseInt(u16, std.mem.span(argv[3]), 10) catch return error.InvalidGeometry;
    const columns = std.fmt.parseInt(u16, std.mem.span(argv[4]), 10) catch return error.InvalidGeometry;
    if (rows == 0 or columns == 0) return error.InvalidGeometry;
    var connection = try connectNamed(init, std.mem.span(argv[2]));
    defer connection.deinit();
    try expectOk(try connection.claimResize());
    try expectOk(try connection.resize(rows, columns));
    return .ok;
}

fn connectNamed(init: std.process.Init, name: []const u8) !howl.client.Connection {
    const runtime_dir = std.process.Environ.getPosix(init.minimal.environ, "XDG_RUNTIME_DIR") orelse
        return error.RuntimeDirectoryUnavailable;
    const session = try howl.discovery.resolve(std.heap.page_allocator, init.io, runtime_dir, name);
    return howl.client.Connection.connect(std.heap.page_allocator, session.endpoint());
}

fn sessions(init: std.process.Init, json: bool) !Exit {
    const runtime_dir = std.process.Environ.getPosix(init.minimal.environ, "XDG_RUNTIME_DIR") orelse {
        try writeStderr("howl: XDG_RUNTIME_DIR is unavailable\n");
        return .failure;
    };
    const listed = howl.discovery.list(std.heap.page_allocator, init.io, runtime_dir) catch |failure| {
        try writeStderr("howl: session discovery failed: ");
        try writeStderr(@errorName(failure));
        try writeStderr("\n");
        return .failure;
    };
    if (json) {
        try writeStdout("[");
        for (listed.items(), 0..) |session, index| {
            if (index != 0) try writeStdout(",");
            var buffer: [320]u8 = undefined;
            const encoded = std.fmt.bufPrint(
                &buffer,
                "{{\"name\":\"{s}\",\"pid\":{d},\"endpoint\":\"{s}\",\"rows\":{d},\"columns\":{d},\"reachable\":{s}}}",
                .{
                    session.name(),                             session.pid, session.endpoint(), session.rows, session.columns,
                    if (session.reachable) "true" else "false",
                },
            ) catch return error.OutputFailed;
            try writeStdout(encoded);
        }
        try writeStdout("]\n");
        return .ok;
    }
    try writeStdout("NAME\tPID\tSIZE\tREACHABLE\tENDPOINT\n");
    for (listed.items()) |session| {
        var buffer: [256]u8 = undefined;
        const line = std.fmt.bufPrint(
            &buffer,
            "{s}\t{d}\t{d}x{d}\t{s}\t{s}\n",
            .{ session.name(), session.pid, session.rows, session.columns, if (session.reachable) "yes" else "no", session.endpoint() },
        ) catch return error.OutputFailed;
        try writeStdout(line);
    }
    return .ok;
}

fn parseKeyAction(text: []const u8) ?session_protocol.InputKeyAction {
    if (std.ascii.eqlIgnoreCase(text, "press") or std.ascii.eqlIgnoreCase(text, "down")) return .press;
    if (std.ascii.eqlIgnoreCase(text, "repeat")) return .repeat;
    if (std.ascii.eqlIgnoreCase(text, "release") or std.ascii.eqlIgnoreCase(text, "up")) return .release;
    return null;
}

fn parseSignal(text: []const u8) ?session_protocol.Signal {
    if (std.ascii.eqlIgnoreCase(text, "hangup")) return .hangup;
    if (std.ascii.eqlIgnoreCase(text, "interrupt")) return .interrupt;
    if (std.ascii.eqlIgnoreCase(text, "resize")) return .resize_notify;
    if (std.ascii.eqlIgnoreCase(text, "kill")) return .kill;
    if (std.ascii.eqlIgnoreCase(text, "terminate")) return .terminate;
    return null;
}

fn expectOk(code: session_protocol.ResultCode) error{ServerRejected}!void {
    if (code != .ok) return error.ServerRejected;
}

fn readStdin(output: []u8) error{ InputTooLarge, InputReadFailed }![]const u8 {
    var count: usize = 0;
    while (count < output.len) {
        const result = linux.read(posix.STDIN_FILENO, output[count..].ptr, output.len - count);
        switch (linux.errno(result)) {
            .SUCCESS => {
                if (result == 0) break;
                if (result > output.len - count) return error.InputReadFailed;
                count += result;
            },
            .INTR => continue,
            else => return error.InputReadFailed,
        }
    }
    if (count == output.len) return error.InputTooLarge;
    return output[0..count];
}

fn writeStdout(bytes: []const u8) error{OutputFailed}!void {
    return writeAll(posix.STDOUT_FILENO, bytes);
}

fn writeStderr(bytes: []const u8) error{OutputFailed}!void {
    return writeAll(posix.STDERR_FILENO, bytes);
}

fn writeAll(fd: posix.fd_t, bytes: []const u8) error{OutputFailed}!void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        const result = linux.write(fd, bytes[offset..].ptr, bytes.len - offset);
        switch (linux.errno(result)) {
            .SUCCESS => {
                if (result == 0 or result > bytes.len - offset) return error.OutputFailed;
                offset += result;
            },
            .INTR => continue,
            else => return error.OutputFailed,
        }
    }
}
