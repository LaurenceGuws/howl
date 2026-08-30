const std = @import("std");
const cli = @import("howl_cli");
const client = @import("howl_client");
const protocol = @import("howl_session").protocol;

pub fn main(init: std.process.Init) !void {
    const argv = init.minimal.args.vector;
    if (argv.len < 2) return usage();
    const operation = std.mem.span(argv[1]);
    if (std.mem.eql(u8, operation, "version")) {
        if (argv.len != 2) return usage();
        return versionCommand(init);
    }
    if (argv.len < 3) return usage();
    const endpoint = std.mem.span(argv[2]);

    if (std.mem.eql(u8, operation, "snapshot")) return snapshotCommand(init, endpoint, argv[3..]);
    if (std.mem.eql(u8, operation, "state")) return stateCommand(init, endpoint, argv[3..]);
    if (std.mem.eql(u8, operation, "type")) return bytesCommand(init, endpoint, argv[3..], false);
    if (std.mem.eql(u8, operation, "paste")) return bytesCommand(init, endpoint, argv[3..], true);
    if (std.mem.eql(u8, operation, "key")) return keyCommand(init, endpoint, argv[3..]);
    if (std.mem.eql(u8, operation, "focus")) return focusCommand(init, endpoint, argv[3..]);
    if (std.mem.eql(u8, operation, "resize")) return resizeCommand(init, endpoint, argv[3..]);
    if (std.mem.eql(u8, operation, "signal")) return signalCommand(init, endpoint, argv[3..]);
    return usage();
}

fn versionCommand(init: std.process.Init) !void {
    const Version = struct {
        schema: []const u8 = cli.version_schema,
        name: []const u8 = "howl",
        version: []const u8 = cli.version,
    };
    var output_buffer: [256]u8 = undefined;
    var stdout = stdoutWriter(init, &output_buffer);
    try std.json.Stringify.value(Version{}, .{}, &stdout.interface);
    try stdout.interface.writeByte('\n');
    try stdout.interface.flush();
}

fn connect(init: std.process.Init, endpoint: []const u8) !client.Connection {
    return client.Connection.connect(init.gpa, endpoint);
}

fn stdoutWriter(init: std.process.Init, buffer: []u8) std.Io.File.Writer {
    return std.Io.File.stdout().writerStreaming(init.io, buffer);
}

fn snapshotCommand(init: std.process.Init, endpoint: []const u8, args: []const [*:0]const u8) !void {
    var after_revision: u64 = 0;
    var history_offset: u32 = 0;
    var format: enum { compact, text, rich } = .compact;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = std.mem.span(args[index]);
        if (std.mem.eql(u8, arg, "--text")) {
            if (format != .compact) return usage();
            format = .text;
        } else if (std.mem.eql(u8, arg, "--rich")) {
            if (format != .compact) return usage();
            format = .rich;
        } else if (std.mem.eql(u8, arg, "--after")) {
            index += 1;
            if (index == args.len) return usage();
            after_revision = std.fmt.parseInt(u64, std.mem.span(args[index]), 10) catch return usage();
        } else if (std.mem.eql(u8, arg, "--history-offset")) {
            index += 1;
            if (index == args.len) return usage();
            history_offset = std.fmt.parseInt(u32, std.mem.span(args[index]), 10) catch return usage();
        } else return usage();
    }
    var connection = try connect(init, endpoint);
    defer connection.deinit();
    var output_buffer: [16 * 1024]u8 = undefined;
    var stdout = stdoutWriter(init, &output_buffer);
    if (format == .rich) {
        try cli.snapshot.requestRich(&connection, &stdout.interface, after_revision, history_offset);
    } else {
        var value = try cli.snapshot.request(&connection, init.gpa, after_revision, history_offset);
        defer value.deinit();
        if (format == .text)
            try cli.snapshot.emitText(&stdout.interface, &value)
        else
            try cli.snapshot.emitCompact(&stdout.interface, &value);
    }
    try stdout.interface.flush();
}

fn stateCommand(init: std.process.Init, endpoint: []const u8, args: []const [*:0]const u8) !void {
    if (args.len != 0) return usage();
    var connection = try connect(init, endpoint);
    defer connection.deinit();
    var output_buffer: [4096]u8 = undefined;
    var stdout = stdoutWriter(init, &output_buffer);
    try cli.state.emit(&connection, &stdout.interface);
    try stdout.interface.flush();
}

fn bytesCommand(init: std.process.Init, endpoint: []const u8, args: []const [*:0]const u8, is_paste: bool) !void {
    if (args.len != 1) return usage();
    const argument = std.mem.span(args[0]);
    var owned: ?[]u8 = null;
    defer if (owned) |bytes| init.gpa.free(bytes);
    const bytes: []const u8 = if (std.mem.eql(u8, argument, "--stdin")) blk: {
        var input_buffer: [4096]u8 = undefined;
        var stdin = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
        const value = try stdin.interface.allocRemaining(
            init.gpa,
            .limited(protocol.maximum_request_payload_bytes - 1),
        );
        owned = value;
        break :blk value;
    } else argument;

    var connection = try connect(init, endpoint);
    defer connection.deinit();
    if (is_paste)
        try cli.actions.paste(&connection, bytes)
    else
        try cli.actions.committedText(&connection, bytes);
    try emitActionReceipt(init, if (is_paste) "paste" else "type");
}

fn keyCommand(init: std.process.Init, endpoint: []const u8, args: []const [*:0]const u8) !void {
    if (args.len == 0) return usage();
    const key = try cli.actions.parseKey(std.mem.span(args[0]));
    var action: protocol.InputKeyAction = .press;
    var modifiers: u8 = 0;
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = std.mem.span(args[index]);
        if (std.mem.eql(u8, arg, "--action")) {
            index += 1;
            if (index == args.len) return usage();
            action = try cli.actions.parseKeyAction(std.mem.span(args[index]));
        } else if (std.mem.eql(u8, arg, "--mods")) {
            index += 1;
            if (index == args.len) return usage();
            modifiers = try cli.actions.parseModifiers(std.mem.span(args[index]));
        } else return usage();
    }
    var connection = try connect(init, endpoint);
    defer connection.deinit();
    switch (key) {
        .named => |value| try cli.actions.namedKey(&connection, value, action, modifiers),
        .unicode => |value| try cli.actions.unicodeKey(&connection, value, action, modifiers),
    }
    try emitActionReceipt(init, "key");
}

fn focusCommand(init: std.process.Init, endpoint: []const u8, args: []const [*:0]const u8) !void {
    if (args.len != 1) return usage();
    var connection = try connect(init, endpoint);
    defer connection.deinit();
    try cli.actions.focus(&connection, try cli.actions.parseFocus(std.mem.span(args[0])));
    try emitActionReceipt(init, "focus");
}

fn resizeCommand(init: std.process.Init, endpoint: []const u8, args: []const [*:0]const u8) !void {
    if (args.len != 2) return usage();
    const rows = std.fmt.parseInt(u16, std.mem.span(args[0]), 10) catch return usage();
    const columns = std.fmt.parseInt(u16, std.mem.span(args[1]), 10) catch return usage();
    var connection = try connect(init, endpoint);
    defer connection.deinit();
    try cli.actions.resize(&connection, rows, columns);
    try emitActionReceipt(init, "resize");
}

fn signalCommand(init: std.process.Init, endpoint: []const u8, args: []const [*:0]const u8) !void {
    if (args.len != 1) return usage();
    var connection = try connect(init, endpoint);
    defer connection.deinit();
    try cli.actions.signal(&connection, try cli.actions.parseSignal(std.mem.span(args[0])));
    try emitActionReceipt(init, "signal");
}

fn emitActionReceipt(init: std.process.Init, operation: []const u8) !void {
    var output_buffer: [512]u8 = undefined;
    var stdout = stdoutWriter(init, &output_buffer);
    try cli.actions.emitReceipt(&stdout.interface, operation);
    try stdout.interface.flush();
}

fn usage() error{InvalidArguments} {
    std.debug.print(
        \\usage:
        \\  howl snapshot ENDPOINT [--after REVISION] [--history-offset ROWS] [--text|--rich]
        \\  howl state ENDPOINT
        \\  howl type ENDPOINT TEXT|--stdin
        \\  howl paste ENDPOINT TEXT|--stdin
        \\  howl key ENDPOINT KEY|U+XXXX [--action press|repeat|release] [--mods ctrl+shift+...]
        \\  howl focus ENDPOINT in|out
        \\  howl resize ENDPOINT ROWS COLUMNS
        \\  howl signal ENDPOINT hangup|interrupt|resize-notify|kill|terminate
        \\
    , .{});
    return error.InvalidArguments;
}
