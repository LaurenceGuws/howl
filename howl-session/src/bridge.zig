//! Copies one Howl session protocol stream between stdio and a local Unix socket.
//!
//! This is deliberately protocol-blind. SSH may execute this binary remotely
//! and carry stdin/stdout; authentication, encryption, host selection, and
//! network lifetime remain SSH concerns.

const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;

const buffer_bytes: usize = 64 * 1024;

const Buffer = struct {
    bytes: [buffer_bytes]u8 = undefined,
    start: usize = 0,
    end: usize = 0,

    fn pending(self: *const Buffer) []const u8 {
        return self.bytes[self.start..self.end];
    }

    fn room(self: *Buffer) []u8 {
        if (self.end == self.bytes.len and self.start != 0) self.compact();
        return self.bytes[self.end..];
    }

    fn commit(self: *Buffer, count: usize) void {
        std.debug.assert(count <= self.bytes.len - self.end);
        self.end += count;
    }

    fn consume(self: *Buffer, count: usize) void {
        std.debug.assert(count <= self.end - self.start);
        self.start += count;
        if (self.start == self.end) {
            self.start = 0;
            self.end = 0;
        }
    }

    fn compact(self: *Buffer) void {
        const count = self.end - self.start;
        std.mem.copyForwards(u8, self.bytes[0..count], self.bytes[self.start..self.end]);
        self.start = 0;
        self.end = count;
    }
};

fn run(socket_fd: posix.fd_t, input_fd: posix.fd_t, output_fd: posix.fd_t) !void {
    try setNonBlocking(socket_fd);
    try setNonBlocking(input_fd);
    try setNonBlocking(output_fd);

    var to_socket: Buffer = .{};
    var to_output: Buffer = .{};
    var input_open = true;
    var socket_read_open = true;
    var socket_write_open = true;

    while (true) {
        if (!input_open and to_socket.pending().len == 0 and socket_write_open) {
            const result = linux.shutdown(socket_fd, linux.SHUT.WR);
            switch (linux.errno(result)) {
                .SUCCESS, .NOTCONN => {},
                .INTR => continue,
                else => return error.SocketShutdownFailed,
            }
            socket_write_open = false;
        }
        if (!socket_read_open and to_output.pending().len == 0) return;

        var socket_poll_events: i16 = posix.POLL.HUP | posix.POLL.ERR;
        if (socket_read_open and to_output.room().len != 0) socket_poll_events |= posix.POLL.IN;
        if (socket_write_open and to_socket.pending().len != 0) socket_poll_events |= posix.POLL.OUT;
        var descriptors = [_]posix.pollfd{
            .{
                .fd = if (input_open and to_socket.room().len != 0) input_fd else -1,
                .events = posix.POLL.IN | posix.POLL.HUP | posix.POLL.ERR,
                .revents = 0,
            },
            .{
                .fd = socket_fd,
                .events = socket_poll_events,
                .revents = 0,
            },
            .{
                .fd = if (to_output.pending().len != 0) output_fd else -1,
                .events = posix.POLL.OUT | posix.POLL.HUP | posix.POLL.ERR,
                .revents = 0,
            },
        };
        const ready_count = try posix.poll(&descriptors, -1);
        std.debug.assert(ready_count <= descriptors.len);

        const socket_events = descriptors[1].revents;
        if (socket_events & (posix.POLL.ERR | posix.POLL.NVAL) != 0) return error.SocketFailed;
        if (descriptors[2].revents & (posix.POLL.ERR | posix.POLL.NVAL | posix.POLL.HUP) != 0)
            return error.OutputClosed;

        if (socket_events & posix.POLL.OUT != 0 and to_socket.pending().len != 0) {
            const pending = to_socket.pending();
            const result = linux.write(socket_fd, pending.ptr, pending.len);
            switch (linux.errno(result)) {
                .SUCCESS => {
                    if (result == 0 or result > pending.len) return error.SocketWriteFailed;
                    to_socket.consume(result);
                },
                .AGAIN, .INTR => {},
                .PIPE, .CONNRESET, .NOTCONN => return,
                else => return error.SocketWriteFailed,
            }
        }

        if (descriptors[2].revents & posix.POLL.OUT != 0 and to_output.pending().len != 0) {
            const pending = to_output.pending();
            const result = linux.write(output_fd, pending.ptr, pending.len);
            switch (linux.errno(result)) {
                .SUCCESS => {
                    if (result == 0 or result > pending.len) return error.OutputWriteFailed;
                    to_output.consume(result);
                },
                .AGAIN, .INTR => {},
                .PIPE => return,
                else => return error.OutputWriteFailed,
            }
        }

        const input_events = descriptors[0].revents;
        if (input_events & (posix.POLL.IN | posix.POLL.HUP) != 0 and input_open) {
            const room = to_socket.room();
            const result = linux.read(input_fd, room.ptr, room.len);
            switch (linux.errno(result)) {
                .SUCCESS => if (result == 0) {
                    input_open = false;
                } else {
                    if (result > room.len) return error.InputReadFailed;
                    to_socket.commit(result);
                },
                .AGAIN, .INTR => {},
                else => return error.InputReadFailed,
            }
        }
        if (input_events & (posix.POLL.ERR | posix.POLL.NVAL) != 0) return error.InputReadFailed;

        if (socket_events & (posix.POLL.IN | posix.POLL.HUP) != 0 and socket_read_open) {
            const room = to_output.room();
            const result = linux.read(socket_fd, room.ptr, room.len);
            switch (linux.errno(result)) {
                .SUCCESS => if (result == 0) {
                    socket_read_open = false;
                } else {
                    if (result > room.len) return error.SocketReadFailed;
                    to_output.commit(result);
                },
                .AGAIN, .INTR => {},
                .CONNRESET, .NOTCONN => socket_read_open = false,
                else => return error.SocketReadFailed,
            }
        }
    }
}

fn connectUnix(path: []const u8) !posix.fd_t {
    var address: linux.sockaddr.un = undefined;
    if (path.len == 0 or path.len >= address.path.len) return error.SocketPathTooLong;
    address.family = linux.AF.UNIX;
    @memset(&address.path, 0);
    @memcpy(address.path[0..path.len], path);
    const address_len: linux.socklen_t = @intCast(@offsetOf(linux.sockaddr.un, "path") + path.len + 1);

    const raw = linux.socket(linux.AF.UNIX, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, 0);
    if (linux.errno(raw) != .SUCCESS) return error.SocketCreateFailed;
    const fd: posix.fd_t = @intCast(raw);
    errdefer closeFd(fd);
    while (true) {
        const result = linux.connect(fd, @ptrCast(&address), address_len);
        switch (linux.errno(result)) {
            .SUCCESS => return fd,
            .INTR => continue,
            else => return error.SocketConnectFailed,
        }
    }
}

fn setNonBlocking(fd: posix.fd_t) !void {
    const flags_result = linux.fcntl(fd, linux.F.GETFL, 0);
    if (linux.errno(flags_result) != .SUCCESS) return error.ConfigureFailed;
    const nonblock: usize = @intCast(@as(u32, @bitCast(linux.O{ .NONBLOCK = true })));
    const set_result = linux.fcntl(fd, linux.F.SETFL, flags_result | nonblock);
    if (linux.errno(set_result) != .SUCCESS) return error.ConfigureFailed;
}

fn closeFd(fd: posix.fd_t) void {
    const result = linux.close(fd);
    const errno = linux.errno(result);
    std.debug.assert(errno == .SUCCESS or errno == .INTR);
}

/// Bridges stdin/stdout to one local Howl Unix socket without parsing protocol.
pub fn main(init: std.process.Init) error{
    InvalidArguments,
    SocketConnectFailed,
    BridgeFailed,
}!void {
    const argv = init.minimal.args.vector;
    if (argv.len != 2) return error.InvalidArguments;
    const socket_fd = connectUnix(std.mem.span(argv[1])) catch return error.SocketConnectFailed;
    defer closeFd(socket_fd);
    run(socket_fd, posix.STDIN_FILENO, posix.STDOUT_FILENO) catch return error.BridgeFailed;
}

test "bridge buffer preserves order across compaction" {
    var buffer: Buffer = .{};
    const first = buffer.room();
    @memcpy(first[0..6], "abcdef");
    buffer.commit(6);
    buffer.consume(4);
    try std.testing.expectEqualStrings("ef", buffer.pending());

    const tail = buffer.room();
    @memset(tail, 'x');
    buffer.commit(tail.len);
    const room = buffer.room();
    try std.testing.expectEqual(@as(usize, 4), room.len);
    try std.testing.expectEqual(@as(usize, buffer_bytes - 4), buffer.pending().len);
    try std.testing.expectEqualStrings("ef", buffer.pending()[0..2]);
}

const TestPumpResult = struct {
    failed: bool = false,
};

fn testPump(result: *TestPumpResult, socket_fd: posix.fd_t, input_fd: posix.fd_t, output_fd: posix.fd_t) void {
    run(socket_fd, input_fd, output_fd) catch {
        result.failed = true;
    };
}

fn testWriteAll(fd: posix.fd_t, bytes: []const u8) !void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        const written = linux.write(fd, bytes[offset..].ptr, bytes.len - offset);
        switch (linux.errno(written)) {
            .SUCCESS => {
                if (written == 0 or written > bytes.len - offset) return error.TestWriteFailed;
                offset += written;
            },
            .INTR => continue,
            else => return error.TestWriteFailed,
        }
    }
}

fn testReadExact(fd: posix.fd_t, output: []u8) !void {
    var offset: usize = 0;
    while (offset < output.len) {
        const read = linux.read(fd, output[offset..].ptr, output.len - offset);
        switch (linux.errno(read)) {
            .SUCCESS => {
                if (read == 0 or read > output.len - offset) return error.TestReadFailed;
                offset += read;
            },
            .INTR => continue,
            else => return error.TestReadFailed,
        }
    }
}

test "bridge pump is protocol-blind in both directions" {
    var sockets: [2]posix.fd_t = undefined;
    const socketpair_result = linux.socketpair(linux.AF.UNIX, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, 0, &sockets);
    try std.testing.expectEqual(linux.E.SUCCESS, linux.errno(socketpair_result));
    defer if (sockets[0] >= 0) closeFd(sockets[0]);
    defer if (sockets[1] >= 0) closeFd(sockets[1]);

    var to_bridge: [2]posix.fd_t = undefined;
    const input_pipe_result = linux.pipe2(&to_bridge, .{ .CLOEXEC = true });
    try std.testing.expectEqual(linux.E.SUCCESS, linux.errno(input_pipe_result));
    defer if (to_bridge[0] >= 0) closeFd(to_bridge[0]);
    defer if (to_bridge[1] >= 0) closeFd(to_bridge[1]);

    var from_bridge: [2]posix.fd_t = undefined;
    const output_pipe_result = linux.pipe2(&from_bridge, .{ .CLOEXEC = true });
    try std.testing.expectEqual(linux.E.SUCCESS, linux.errno(output_pipe_result));
    defer if (from_bridge[0] >= 0) closeFd(from_bridge[0]);
    defer if (from_bridge[1] >= 0) closeFd(from_bridge[1]);

    var pump_result: TestPumpResult = .{};
    const thread = try std.Thread.spawn(.{}, testPump, .{ &pump_result, sockets[0], to_bridge[0], from_bridge[1] });

    const toward_socket = "opaque-client-frame\x00\xffstill-opaque";
    try testWriteAll(to_bridge[1], toward_socket);
    var received_socket: [toward_socket.len]u8 = undefined;
    try testReadExact(sockets[1], &received_socket);
    try std.testing.expectEqualSlices(u8, toward_socket, &received_socket);

    const toward_stdout = "opaque-server-frame\xfe\x01unchanged";
    try testWriteAll(sockets[1], toward_stdout);
    var received_stdout: [toward_stdout.len]u8 = undefined;
    try testReadExact(from_bridge[0], &received_stdout);
    try std.testing.expectEqualSlices(u8, toward_stdout, &received_stdout);

    closeFd(to_bridge[1]);
    to_bridge[1] = -1;
    closeFd(sockets[1]);
    sockets[1] = -1;
    thread.join();
    try std.testing.expect(!pump_result.failed);
}
