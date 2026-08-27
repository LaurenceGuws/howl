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
    if (std.mem.eql(u8, command, "start")) return startCommand(init);
    if (std.mem.eql(u8, command, "stop")) return stopCommand(init);
    if (std.mem.eql(u8, command, "sessions")) return sessionsCommand(init);
    if (std.mem.eql(u8, command, "observe")) return observeCommand(init);
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
            "  howl start NAME [--rows ROWS] [--columns COLUMNS] [--cwd PATH] [--shell PATH] [--command COMMAND] [--json]\n" ++
            "  howl stop NAME [--json]\n" ++
            "  howl sessions [--json]\n" ++
            "  howl observe SESSION [--json]\n" ++
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

fn startCommand(init: std.process.Init) !Exit {
    const argv = init.minimal.args.vector;
    if (argv.len < 3) return usage();
    const runtime_dir = std.process.Environ.getPosix(init.minimal.environ, "XDG_RUNTIME_DIR") orelse
        return error.RuntimeDirectoryUnavailable;
    var options = howl.lifecycle.StartOptions{
        .name = std.mem.span(argv[2]),
        .shell = std.process.Environ.getPosix(init.minimal.environ, "SHELL") orelse "/bin/sh",
    };
    var json = false;
    var rows_seen = false;
    var columns_seen = false;
    var cwd_seen = false;
    var shell_seen = false;
    var command_seen = false;
    var index: usize = 3;
    while (index < argv.len) {
        const argument = std.mem.span(argv[index]);
        if (std.mem.eql(u8, argument, "--json")) {
            if (json) return usage();
            json = true;
            index += 1;
            continue;
        }
        if (index + 1 >= argv.len) return usage();
        const value = std.mem.span(argv[index + 1]);
        if (std.mem.eql(u8, argument, "--rows")) {
            if (rows_seen) return usage();
            options.rows = std.fmt.parseInt(u16, value, 10) catch return error.InvalidGeometry;
            rows_seen = true;
        } else if (std.mem.eql(u8, argument, "--columns")) {
            if (columns_seen) return usage();
            options.columns = std.fmt.parseInt(u16, value, 10) catch return error.InvalidGeometry;
            columns_seen = true;
        } else if (std.mem.eql(u8, argument, "--cwd")) {
            if (cwd_seen) return usage();
            options.cwd = value;
            cwd_seen = true;
        } else if (std.mem.eql(u8, argument, "--shell")) {
            if (shell_seen) return usage();
            options.shell = value;
            shell_seen = true;
        } else if (std.mem.eql(u8, argument, "--command")) {
            if (command_seen) return usage();
            options.command = value;
            command_seen = true;
        } else return usage();
        index += 2;
    }
    const session = try howl.lifecycle.start(
        std.heap.page_allocator,
        init.io,
        init.minimal.environ,
        runtime_dir,
        options,
    );
    if (json) {
        var buffer: [320]u8 = undefined;
        const encoded = std.fmt.bufPrint(
            &buffer,
            "{{\"name\":\"{s}\",\"pid\":{d},\"endpoint\":\"{s}\",\"rows\":{d},\"columns\":{d}}}\n",
            .{ session.name(), session.pid, session.endpoint(), session.rows, session.columns },
        ) catch return error.OutputFailed;
        try writeStdout(encoded);
    } else {
        var buffer: [256]u8 = undefined;
        const line = std.fmt.bufPrint(
            &buffer,
            "started {s} pid={d} size={d}x{d} endpoint={s}\n",
            .{ session.name(), session.pid, session.rows, session.columns, session.endpoint() },
        ) catch return error.OutputFailed;
        try writeStdout(line);
    }
    return .ok;
}

fn stopCommand(init: std.process.Init) !Exit {
    const argv = init.minimal.args.vector;
    if (argv.len != 3 and argv.len != 4) return usage();
    const json = argv.len == 4 and std.mem.eql(u8, std.mem.span(argv[3]), "--json");
    if (argv.len == 4 and !json) return usage();
    const runtime_dir = std.process.Environ.getPosix(init.minimal.environ, "XDG_RUNTIME_DIR") orelse
        return error.RuntimeDirectoryUnavailable;
    const name = std.mem.span(argv[2]);
    try howl.lifecycle.stop(std.heap.page_allocator, init.io, runtime_dir, name);
    if (json) {
        try writeStdout("{\"stopped\":true,\"name\":");
        try writeJsonString(name);
        try writeStdout("}\n");
    } else {
        try writeStdout("stopped ");
        try writeStdout(name);
        try writeStdout("\n");
    }
    return .ok;
}

fn sessionsCommand(init: std.process.Init) !Exit {
    const argv = init.minimal.args.vector;
    if (argv.len == 2) return sessions(init, false);
    if (argv.len == 3 and std.mem.eql(u8, std.mem.span(argv[2]), "--json"))
        return sessions(init, true);
    return usage();
}

fn observeCommand(init: std.process.Init) !Exit {
    const argv = init.minimal.args.vector;
    if (argv.len != 3 and argv.len != 4) return usage();
    const json = argv.len == 4 and std.mem.eql(u8, std.mem.span(argv[3]), "--json");
    if (argv.len == 4 and !json) return usage();
    const name = std.mem.span(argv[2]);
    var connection = try connectNamed(init, name);
    defer connection.deinit();
    var snapshot = try howl.observe.current(&connection);
    defer snapshot.deinit();
    if (json) {
        try writeSnapshotJson(name, &snapshot);
    } else {
        for (0..snapshot.begin.rows) |row_index| {
            const row = snapshot.row(@intCast(row_index));
            try writeStdout(std.mem.trimEnd(u8, row, " "));
            try writeStdout("\n");
        }
    }
    return .ok;
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
            const geometry = liveGeometry(session.endpoint()) catch Geometry{
                .rows = session.rows,
                .columns = session.columns,
            };
            var buffer: [320]u8 = undefined;
            const encoded = std.fmt.bufPrint(
                &buffer,
                "{{\"name\":\"{s}\",\"pid\":{d},\"endpoint\":\"{s}\",\"rows\":{d},\"columns\":{d},\"reachable\":{s}}}",
                .{
                    session.name(),                             session.pid, session.endpoint(), geometry.rows, geometry.columns,
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
        const geometry = liveGeometry(session.endpoint()) catch Geometry{
            .rows = session.rows,
            .columns = session.columns,
        };
        var buffer: [256]u8 = undefined;
        const line = std.fmt.bufPrint(
            &buffer,
            "{s}\t{d}\t{d}x{d}\t{s}\t{s}\n",
            .{ session.name(), session.pid, geometry.rows, geometry.columns, if (session.reachable) "yes" else "no", session.endpoint() },
        ) catch return error.OutputFailed;
        try writeStdout(line);
    }
    return .ok;
}

const Geometry = struct { rows: u16, columns: u16 };

fn liveGeometry(endpoint: []const u8) !Geometry {
    var connection = try howl.client.Connection.connect(std.heap.page_allocator, endpoint);
    defer connection.deinit();
    var snapshot = try howl.observe.current(&connection);
    defer snapshot.deinit();
    return .{ .rows = snapshot.begin.rows, .columns = snapshot.begin.columns };
}

fn writeSnapshotJson(name: []const u8, snapshot: *const howl.observe.Snapshot) error{OutputFailed}!void {
    var metadata: [512]u8 = undefined;
    const begin = snapshot.begin;
    const prefix = std.fmt.bufPrint(
        &metadata,
        "{{\"name\":\"{s}\",\"revision\":{d},\"terminal_revision\":{d},\"rows\":{d},\"columns\":{d}," ++
            "\"cursor\":{{\"row\":{d},\"column\":{d},\"shape\":{d},\"visible\":{s},\"blink\":{s}}}," ++
            "\"alternate_screen\":{s},\"stream_closed\":{s},\"child_exited\":{s},\"rows_text\":[",
        .{
            name,
            begin.revision,
            begin.terminal_revision,
            begin.rows,
            begin.columns,
            begin.cursor_row,
            begin.cursor_column,
            begin.cursor_shape,
            jsonBool(begin.cursor_visible),
            jsonBool(begin.cursor_blink),
            jsonBool(begin.alternate_screen),
            jsonBool(begin.stream_closed),
            jsonBool(begin.child_exited),
        },
    ) catch return error.OutputFailed;
    try writeStdout(prefix);
    for (0..begin.rows) |row_index| {
        if (row_index != 0) try writeStdout(",");
        try writeJsonString(snapshot.row(@intCast(row_index)));
    }
    try writeStdout("]}\n");
}

fn writeJsonString(bytes: []const u8) error{OutputFailed}!void {
    try writeStdout("\"");
    var plain_start: usize = 0;
    for (bytes, 0..) |byte, index| {
        const escape: ?[]const u8 = switch (byte) {
            '"' => "\\\"",
            '\\' => "\\\\",
            '\n' => "\\n",
            '\r' => "\\r",
            '\t' => "\\t",
            else => null,
        };
        if (escape == null and byte >= 0x20) continue;
        if (index > plain_start) try writeStdout(bytes[plain_start..index]);
        if (escape) |encoded| {
            try writeStdout(encoded);
        } else {
            var encoded: [6]u8 = .{ '\\', 'u', '0', '0', 0, 0 };
            const hex = "0123456789abcdef";
            encoded[4] = hex[byte >> 4];
            encoded[5] = hex[byte & 0x0f];
            try writeStdout(&encoded);
        }
        plain_start = index + 1;
    }
    if (plain_start < bytes.len) try writeStdout(bytes[plain_start..]);
    try writeStdout("\"");
}

fn jsonBool(value: bool) []const u8 {
    return if (value) "true" else "false";
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
