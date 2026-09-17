//! Optional Linux/OpenSSH carrier. No PTY, terminal parsing or Session ownership.
//! Embedders explicitly opt into a subprocess environment. Mobile/browser hosts
//! can instead deliver channel bytes to the shared decoder without this owner.
const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const system = posix.system;

pub const supported = builtin.os.tag == .linux;
pub const maximum_endpoint_bytes = 4096;
pub const diagnostic_bytes = 512;
pub const Error = error{ InvalidEndpoint, SshUnavailable, SshSpawnFailed, SshChannelFailed } || std.mem.Allocator.Error;

/// `ssh://[user@]host[:port]/absolute/socket[?bridge=/absolute/executable]`.
/// User's OpenSSH config supplies aliases/keys/jump hosts. No password, unknown
/// query, shell options, implicit Session creation, or endpoint discovery.
pub const Route = struct {
    target: []const u8,
    port: ?u16,
    socket_path: []const u8,
    bridge: []const u8,
};

pub fn parse(endpoint: []const u8) Error!Route {
    if (endpoint.len > maximum_endpoint_bytes or !std.mem.startsWith(u8, endpoint, "ssh://"))
        return error.InvalidEndpoint;
    // This first spelling deliberately admits literal ASCII paths only, without
    // percent escapes. Reject ambiguous syntax rather than silently decoding it.
    for (endpoint) |byte| if (byte < 0x21 or byte > 0x7e or byte == '%' or byte == '#')
        return error.InvalidEndpoint;
    const rest = endpoint[6..];
    const slash = std.mem.indexOfScalar(u8, rest, '/') orelse return error.InvalidEndpoint;
    var target = rest[0..slash];
    var port: ?u16 = null;
    if (std.mem.lastIndexOfScalar(u8, target, ':')) |colon| {
        port = std.fmt.parseInt(u16, target[colon + 1 ..], 10) catch return error.InvalidEndpoint;
        if (port.? == 0) return error.InvalidEndpoint;
        target = target[0..colon];
    }
    if (target.len == 0 or target.len > 255 or target[0] == '-') return error.InvalidEndpoint;
    var at_count: u8 = 0;
    for (target, 0..) |byte, index| {
        if (byte == '@') {
            at_count += 1;
            if (at_count > 1 or index == 0 or index + 1 == target.len or target[index + 1] == '-')
                return error.InvalidEndpoint;
        } else if (!(std.ascii.isAlphanumeric(byte) or byte == '.' or byte == '_' or byte == '-')) {
            return error.InvalidEndpoint;
        }
    }
    const path_and_query = rest[slash..];
    const question = std.mem.indexOfScalar(u8, path_and_query, '?');
    const path = if (question) |index| path_and_query[0..index] else path_and_query;
    if (path.len < 2 or path.len > 1024) return error.InvalidEndpoint;
    var bridge: []const u8 = "howl-session-bridge";
    if (question) |index| {
        const query = path_and_query[index + 1 ..];
        if (!std.mem.startsWith(u8, query, "bridge=/")) return error.InvalidEndpoint;
        bridge = query[7..];
        if (bridge.len < 2 or bridge.len > 1024 or std.mem.indexOfAny(u8, bridge, "?&") != null)
            return error.InvalidEndpoint;
    }
    return .{ .target = target, .port = port, .socket_path = path, .bridge = bridge };
}

fn quoted(writer: *std.Io.Writer, value: []const u8) std.Io.Writer.Error!void {
    try writer.writeByte('\'');
    for (value) |byte| {
        if (byte == '\'') try writer.writeAll("'\\''") else try writer.writeByte(byte);
    }
    try writer.writeByte('\'');
}

pub fn remoteCommand(buffer: []u8, route: Route) error{NoSpaceLeft}![]const u8 {
    var writer: std.Io.Writer = .fixed(buffer);
    writer.writeAll("exec ") catch return error.NoSpaceLeft;
    quoted(&writer, route.bridge) catch return error.NoSpaceLeft;
    writer.writeByte(' ') catch return error.NoSpaceLeft;
    quoted(&writer, route.socket_path) catch return error.NoSpaceLeft;
    return writer.buffered();
}

// No global runtime, key store, background master, auth agent forwarding or
// subprocess support in the portable byte decoder. One explicit native carrier
// owns one process group and one sleeping diagnostic drain, plus two sockets.
pub const Process = if (supported) LinuxProcess else opaque {};
const LinuxProcess = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    child: ?std.process.Child = null,
    stderr_fd: posix.fd_t = -1,
    drain_thread: ?std.Thread = null,
    message: [diagnostic_bytes]u8 = undefined,
    message_len: usize = 0,

    pub const Opened = struct { process: *LinuxProcess, fd: posix.fd_t };

    pub fn open(allocator: std.mem.Allocator, io: std.Io, route: Route) Error!Opened {
        var command_buffer: [8192]u8 = undefined;
        const remote = remoteCommand(&command_buffer, route) catch return error.InvalidEndpoint;
        var port_buffer: [5]u8 = undefined;
        const port_text = if (route.port) |port|
            std.fmt.bufPrint(&port_buffer, "{d}", .{port}) catch unreachable
        else
            "";
        var args: [40][]const u8 = undefined;
        const fixed = [_][]const u8{
            "ssh", "-T",                    "-a", "-x",                         "-S", "none",
            "-o",  "BatchMode=yes",         "-o", "StrictHostKeyChecking=yes",  "-o", "ClearAllForwardings=yes",
            "-o",  "ConnectTimeout=10",     "-o", "ConnectionAttempts=1",       "-o", "ControlMaster=no",
            "-o",  "ControlPersist=no",     "-o", "ForkAfterAuthentication=no", "-o", "StdinNull=no",
            "-o",  "PermitLocalCommand=no", "-o", "RemoteCommand=none",         "-o", "SessionType=default",
        };
        @memcpy(args[0..fixed.len], &fixed);
        var count: usize = fixed.len;
        if (route.port != null) {
            args[count] = "-p";
            args[count + 1] = port_text;
            count += 2;
        }
        args[count] = "--";
        args[count + 1] = route.target;
        args[count + 2] = remote;
        count += 3;
        return openArgv(allocator, io, args[0..count]);
    }

    // Private test seam uses the same spawn/stream/lifetime owner, not a second
    // protocol. There is deliberately no user-configurable arbitrary argv route.
    fn openArgv(allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) Error!Opened {
        var data: [2]posix.fd_t = undefined;
        if (posix.errno(system.socketpair(posix.AF.UNIX, posix.SOCK.STREAM | posix.SOCK.CLOEXEC, 0, &data)) != .SUCCESS)
            return error.SshChannelFailed;
        errdefer close(data[0]);
        defer close(data[1]);
        var errors: [2]posix.fd_t = undefined;
        if (posix.errno(system.socketpair(posix.AF.UNIX, posix.SOCK.STREAM | posix.SOCK.CLOEXEC, 0, &errors)) != .SUCCESS)
            return error.SshChannelFailed;
        errdefer close(errors[0]);
        defer close(errors[1]);
        const self = try allocator.create(LinuxProcess);
        errdefer allocator.destroy(self);
        // The embedder runtime outlives its channels. Per-route Threaded
        // instances would restore process-global signals in the wrong order
        // when independently owned connections close.
        self.* = .{ .allocator = allocator, .io = io };
        self.child = std.process.spawn(io, .{
            .argv = args,
            .stdin = .{ .file = .{ .handle = data[1], .flags = .{ .nonblocking = false } } },
            .stdout = .{ .file = .{ .handle = data[1], .flags = .{ .nonblocking = false } } },
            .stderr = .{ .file = .{ .handle = errors[1], .flags = .{ .nonblocking = false } } },
            .pgid = 0,
        }) catch |failure| return switch (failure) {
            error.FileNotFound => error.SshUnavailable,
            else => error.SshSpawnFailed,
        };
        errdefer self.killChild();
        self.stderr_fd = errors[0];
        self.drain_thread = std.Thread.spawn(.{}, drainErrors, .{self}) catch return error.SshSpawnFailed;
        return .{ .process = self, .fd = data[0] };
    }

    fn killChild(self: *LinuxProcess) void {
        if (self.child) |*child| {
            if (child.id) |pid| {
                // The group is made exclusively for this foreground carrier.
                // Also retire its configured proxy child, never the remote PTY.
                while (true) {
                    const status = posix.errno(system.kill(-pid, .KILL));
                    switch (status) {
                        .SUCCESS, .SRCH => break,
                        .INTR => continue,
                        else => {
                            std.debug.print("Howl SSH process-group cleanup failed: {t}\n", .{status});
                            break;
                        },
                    }
                }
                child.kill(self.io);
            }
            self.child = null;
        }
    }

    /// Data FD belongs to Connection after open; this owner does not close it.
    /// Diagnostic bytes are read only after the drain joins, with no race/lock.
    pub fn deinit(self: *LinuxProcess, diagnostic: []u8) usize {
        self.killChild();
        while (true) {
            const status = posix.errno(system.shutdown(self.stderr_fd, posix.SHUT.RDWR));
            switch (status) {
                .SUCCESS, .NOTCONN => break,
                .INTR => continue,
                else => {
                    std.debug.print("Howl SSH diagnostic cancellation failed: {t}\n", .{status});
                    break;
                },
            }
        }
        if (self.drain_thread) |thread| thread.join();
        close(self.stderr_fd);
        const copied = @min(diagnostic.len, self.message_len);
        @memcpy(diagnostic[0..copied], self.message[self.message_len - copied ..][0..copied]);
        const allocator = self.allocator;
        allocator.destroy(self);
        return copied;
    }

    fn drainErrors(self: *LinuxProcess) void {
        var bytes: [1024]u8 = undefined;
        while (true) {
            const result = system.read(self.stderr_fd, &bytes, bytes.len);
            switch (posix.errno(result)) {
                .SUCCESS => {
                    if (result == 0) return;
                    self.appendDiagnostic(bytes[0..@intCast(result)]);
                },
                .INTR => continue,
                else => return,
            }
        }
    }

    fn appendDiagnostic(self: *LinuxProcess, bytes: []const u8) void {
        const incoming = bytes[bytes.len - @min(bytes.len, self.message.len) ..];
        const keep = @min(self.message_len, self.message.len - incoming.len);
        std.mem.copyForwards(u8, self.message[0..keep], self.message[self.message_len - keep ..][0..keep]);
        for (incoming, 0..) |byte, index|
            self.message[keep + index] = if (byte >= 0x20 and byte < 0x7f) byte else ' ';
        self.message_len = keep + incoming.len;
    }
};

fn close(fd: posix.fd_t) void {
    const errno = posix.errno(system.close(fd));
    std.debug.assert(errno == .SUCCESS or errno == .INTR);
}

test "SSH route is explicit and rejects option, password and query ambiguity" {
    const value = try parse("ssh://captain@brommer:2222/run/user/1000/howl.sock?bridge=/opt/howl/bin/howl-session-bridge");
    try std.testing.expectEqualStrings("captain@brommer", value.target);
    try std.testing.expectEqual(@as(?u16, 2222), value.port);
    try std.testing.expectEqualStrings("/run/user/1000/howl.sock", value.socket_path);
    try std.testing.expectEqualStrings("/opt/howl/bin/howl-session-bridge", value.bridge);
    try std.testing.expectEqualStrings("howl-session-bridge", (try parse("ssh://alias/a")).bridge);
    for ([_][]const u8{
        "ssh://-oProxyCommand=x/a", "ssh://u@-alias/a",          "ssh://@alias/a",                "ssh://u@@alias/a",
        "ssh://u:password@alias/a", "ssh://alias:0/a",           "ssh://alias:65536/a",           "ssh://alias",
        "ssh://alias/",             "ssh://alias/a?command=bad", "ssh://alias/a?bridge=relative", "ssh://alias/a?bridge=/a&bridge=/b",
        "ssh://alias/a#fragment",   "ssh://alias/a%00b",         "ssh://alias/a b",               "ssh://alias/a\nb",
        "ssh://alias/a\x00b",       "ssh://$(command)/a",        "unix:/a",                       "tcp://127.0.0.1:1",
    }) |bad| try std.testing.expectError(error.InvalidEndpoint, parse(bad));
}

test "remote bridge and socket remain two quoted literal arguments" {
    var output: [8192]u8 = undefined;
    const value = try parse("ssh://alias/a'$(touch${IFS}bad);x?bridge=/opt/b'ridge");
    try std.testing.expectEqualStrings("exec '/opt/b'\\''ridge' '/a'\\''$(touch${IFS}bad);x'", try remoteCommand(&output, value));
    try std.testing.expectError(error.NoSpaceLeft, remoteCommand(output[0..3], value));
}

test "SSH subprocess failure releases sockets and allocator state" {
    if (!supported) return;
    try std.testing.expectError(error.SshUnavailable, LinuxProcess.openArgv(std.testing.allocator, std.testing.io, &.{"/howl-test/no-such-ssh"}));
}

test "SSH process keeps binary stdout separate and drains bounded diagnostic flood" {
    if (!supported) return;
    const value = try LinuxProcess.openArgv(std.testing.allocator, std.testing.io, &.{
        "/bin/sh", "-c", "head -c 65536 /dev/zero >&2; printf 'diagnostic-end' >&2; printf '\\000\\377HWLS'; cat",
    });
    defer close(value.fd);
    var output: [6]u8 = undefined;
    var offset: usize = 0;
    while (offset < output.len) {
        const count = system.read(value.fd, output[offset..].ptr, output.len - offset);
        try std.testing.expectEqual(posix.E.SUCCESS, posix.errno(count));
        try std.testing.expect(count > 0);
        offset += count;
    }
    try std.testing.expectEqualSlices(u8, &.{ 0, 255, 'H', 'W', 'L', 'S' }, &output);
    var diagnostic: [diagnostic_bytes]u8 = undefined;
    const length = value.process.deinit(&diagnostic);
    try std.testing.expectEqual(diagnostic.len, length);
    try std.testing.expect(std.mem.endsWith(u8, diagnostic[0..length], "diagnostic-end"));
    for (diagnostic[0..length]) |byte| try std.testing.expect(byte >= 0x20 and byte < 0x7f);
}

test "carrier cleanup does not wait for an inherited stderr writer" {
    if (!supported) return;
    const value = try LinuxProcess.openArgv(std.testing.allocator, std.testing.io, &.{ "/bin/sh", "-c", "sleep 30 & wait" });
    close(value.fd);
    _ = value.process.deinit(&.{});
}

fn expectSignalDispositions(expected: [2]posix.Sigaction) !void {
    const signals = [_]posix.SIG{ .PIPE, .IO };
    for (signals, expected) |signal, before| {
        var current: posix.Sigaction = undefined;
        posix.sigaction(signal, null, &current);
        try std.testing.expectEqual(before.handler.handler, current.handler.handler);
        try std.testing.expectEqual(before.flags, current.flags);
        try std.testing.expectEqualDeep(before.mask, current.mask);
    }
}

test "independent SSH carrier close order never changes embedder signal handlers" {
    if (!supported) return;
    var before: [2]posix.Sigaction = undefined;
    posix.sigaction(.PIPE, null, &before[0]);
    posix.sigaction(.IO, null, &before[1]);
    const first = try LinuxProcess.openArgv(std.testing.allocator, std.testing.io, &.{"/bin/cat"});
    defer close(first.fd);
    const second = try LinuxProcess.openArgv(std.testing.allocator, std.testing.io, &.{"/bin/cat"});
    defer close(second.fd);
    try expectSignalDispositions(before);
    try std.testing.expectEqual(@as(usize, 0), first.process.deinit(&.{}));
    try expectSignalDispositions(before);
    try std.testing.expectEqual(@as(usize, 0), second.process.deinit(&.{}));
    try expectSignalDispositions(before);
}
