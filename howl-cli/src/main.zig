//! Exposes the small non-GUI operator and agent surface for shared Howl sessions.

const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;
const howl = @import("howl_cli");

const Exit = enum(u8) { ok = 0, usage = 2, failure = 1 };

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
    if (argv.len == 2 and std.mem.eql(u8, std.mem.span(argv[1]), "sessions"))
        return sessions(init, false);
    if (argv.len == 3 and std.mem.eql(u8, std.mem.span(argv[1]), "sessions") and
        std.mem.eql(u8, std.mem.span(argv[2]), "--json"))
        return sessions(init, true);
    try writeStderr(
        "usage: howl sessions [--json]\n",
    );
    return .usage;
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
                    session.name(),
                    session.pid,
                    session.endpoint(),
                    session.rows,
                    session.columns,
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
            .{
                session.name(),
                session.pid,
                session.rows,
                session.columns,
                if (session.reachable) "yes" else "no",
                session.endpoint(),
            },
        ) catch return error.OutputFailed;
        try writeStdout(line);
    }
    return .ok;
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
