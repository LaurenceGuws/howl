//! Owns bounded UTF-8 clipboard bytes and nonblocking transfer progress.

const std = @import("std");
const control = @import("howl_control");

const c = @cImport({
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("errno.h");
    @cInclude("fcntl.h");
    @cInclude("unistd.h");
});

/// Bounds clipboard text so bracketed-paste framing still fits one Control admission.
pub const max_bytes: usize = control.max_input_bytes - 12;
/// Bounds simultaneous compositor requests for the current clipboard source.
pub const max_sends: usize = 2;
/// Names the preferred UTF-8 text formats admitted from a Wayland offer.
pub const Mime = enum {
    /// Names plain UTF-8-compatible text.
    plain,
    /// Names explicit UTF-8 plain text.
    utf8,

    /// Returns the exact protocol MIME string.
    pub fn bytes(self: Mime) [:0]const u8 {
        return switch (self) {
            .plain => "text/plain",
            .utf8 => "text/plain;charset=utf-8",
        };
    }
};

/// Retains ranked MIME facts for one compositor offer.
pub const Offer = struct {
    /// Records admission of `text/plain`.
    plain: bool = false,
    /// Records admission of `text/plain;charset=utf-8`.
    utf8: bool = false,

    /// Admits one exact UTF-8 text MIME without retaining compositor strings.
    pub fn admit(self: *Offer, value: []const u8) void {
        if (std.mem.eql(u8, value, Mime.utf8.bytes())) {
            self.utf8 = true;
        } else if (std.mem.eql(u8, value, Mime.plain.bytes())) {
            self.plain = true;
        }
    }

    /// Selects the strongest admitted text representation.
    pub fn preferred(self: Offer) ?Mime {
        if (self.utf8) return .utf8;
        if (self.plain) return .plain;
        return null;
    }
};

/// Reports exact allocation, descriptor, capacity, or transfer failure.
pub const Error = std.mem.Allocator.Error || error{
    ClipboardBusy,
    ClipboardDescriptor,
    ClipboardLimit,
    ClipboardRead,
    ClipboardWrite,
};

/// Creates one close-on-exec nonblocking transfer pipe.
pub fn pipe() error{ClipboardDescriptor}![2]c_int {
    var fds: [2]c_int = undefined;
    if (c.pipe(&fds) != 0) return error.ClipboardDescriptor;
    errdefer closeFd(fds[0]);
    errdefer closeFd(fds[1]);
    try configureDescriptor(fds[0]);
    try configureDescriptor(fds[1]);
    return fds;
}

/// Retains one bounded incoming descriptor and caller-allocator buffer.
pub const Receive = struct {
    /// Owns the nonblocking descriptor.
    fd: c_int,
    /// Owns `max_bytes + 1` bytes so overflow is observable.
    bytes: []u8,
    /// Counts initialized bytes.
    len: usize = 0,
    /// Records observed peer EOF.
    complete: bool = false,
};

/// Retains one independent outgoing descriptor and byte copy.
pub const Send = struct {
    /// Owns the nonblocking descriptor.
    fd: c_int,
    /// Owns source bytes until complete transfer.
    bytes: []const u8,
    /// Counts bytes already written.
    offset: usize = 0,
};

/// Owns copied clipboard text and every active nonblocking transfer descriptor.
pub const Transfers = struct {
    /// Allocates every retained clipboard byte buffer.
    allocator: std.mem.Allocator,
    /// Owns current clipboard source bytes.
    source: []const u8 = &.{},
    /// Owns at most one incoming paste transfer.
    receive: ?Receive = null,
    /// Owns bounded independent copies for compositor send requests.
    sends: [max_sends]?Send = @splat(null),

    /// Initializes empty clipboard ownership with the caller allocator.
    pub fn init(allocator: std.mem.Allocator) Transfers {
        return .{ .allocator = allocator };
    }

    /// Replaces source bytes by taking caller ownership exactly on success.
    pub fn replaceSource(self: *Transfers, bytes: []const u8) error{ClipboardLimit}!void {
        if (bytes.len > max_bytes) return error.ClipboardLimit;
        self.allocator.free(self.source);
        self.source = bytes;
    }

    /// Clears clipboard ownership while allowing already copied sends to finish.
    pub fn clearSource(self: *Transfers) void {
        self.allocator.free(self.source);
        self.source = &.{};
    }

    /// Starts one bounded incoming transfer and takes its nonblocking descriptor.
    pub fn beginReceive(self: *Transfers, fd: c_int) Error!void {
        if (self.receive != null) return error.ClipboardBusy;
        errdefer closeFd(fd);
        try configureDescriptor(fd);
        const bytes = try self.allocator.alloc(u8, max_bytes + 1);
        self.receive = .{ .fd = fd, .bytes = bytes };
    }

    /// Reports whether one incoming transfer currently owns a descriptor.
    pub fn receiving(self: *const Transfers) bool {
        return self.receive != null;
    }

    /// Starts one outgoing transfer by copying current source ownership.
    pub fn beginSend(self: *Transfers, fd: c_int) Error!void {
        errdefer closeFd(fd);
        const slot = for (&self.sends) |*candidate| {
            if (candidate.* == null) break candidate;
        } else return error.ClipboardBusy;
        try configureDescriptor(fd);
        const bytes = try self.allocator.dupe(u8, self.source);
        slot.* = .{ .fd = fd, .bytes = bytes };
    }

    /// Appends active transfer descriptors and returns the appended count.
    pub fn pollDescriptors(self: *const Transfers, output: []std.posix.pollfd) usize {
        var count: usize = 0;
        if (self.receive) |receive| {
            std.debug.assert(count < output.len);
            output[count] = .{ .fd = receive.fd, .events = std.posix.POLL.IN, .revents = 0 };
            count += 1;
        }
        for (self.sends) |send| if (send) |active| {
            std.debug.assert(count < output.len);
            output[count] = .{ .fd = active.fd, .events = std.posix.POLL.OUT, .revents = 0 };
            count += 1;
        };
        return count;
    }

    /// Advances one ready descriptor without blocking behind its peer.
    pub fn service(self: *Transfers, fd: c_int, revents: i16) Error!void {
        if (self.receive) |*receive| if (receive.fd == fd) {
            if (revents & std.posix.POLL.NVAL != 0) return error.ClipboardRead;
            try readAvailable(receive);
            if (receive.len > max_bytes) return error.ClipboardLimit;
            if (revents & (std.posix.POLL.ERR | std.posix.POLL.HUP) != 0 and !receive.complete) {
                try readAvailable(receive);
                if (!receive.complete) return error.ClipboardRead;
            }
            return;
        };
        for (&self.sends) |*slot| if (slot.*) |*send| {
            if (send.fd != fd) continue;
            if (revents & (std.posix.POLL.ERR | std.posix.POLL.HUP | std.posix.POLL.NVAL) != 0)
                return error.ClipboardWrite;
            try writeAvailable(send);
            if (send.offset == send.bytes.len) self.finishSend(slot);
            return;
        };
    }

    /// Borrows completed incoming text until `finishReceive`.
    pub fn received(self: *const Transfers) ?[]const u8 {
        const receive = self.receive orelse return null;
        if (!receive.complete) return null;
        return receive.bytes[0..receive.len];
    }

    /// Releases the completed or failed incoming transfer.
    pub fn finishReceive(self: *Transfers) void {
        if (self.receive) |receive| {
            closeFd(receive.fd);
            self.allocator.free(receive.bytes);
        }
        self.receive = null;
    }

    /// Releases every descriptor and owned byte buffer.
    pub fn deinit(self: *Transfers) void {
        self.finishReceive();
        for (&self.sends) |*slot| self.finishSend(slot);
        self.allocator.free(self.source);
        self.* = undefined;
    }

    fn finishSend(self: *Transfers, slot: *?Send) void {
        if (slot.*) |send| {
            closeFd(send.fd);
            self.allocator.free(send.bytes);
        }
        slot.* = null;
    }
};

fn readAvailable(receive: *Receive) error{ ClipboardLimit, ClipboardRead }!void {
    while (!receive.complete) {
        if (receive.len == receive.bytes.len) return error.ClipboardLimit;
        const count = c.read(
            receive.fd,
            receive.bytes.ptr + receive.len,
            receive.bytes.len - receive.len,
        );
        if (count > 0) {
            receive.len += @intCast(count);
            continue;
        }
        if (count == 0) {
            receive.complete = true;
            return;
        }
        switch (std.posix.errno(count)) {
            .INTR => continue,
            .AGAIN => return,
            else => return error.ClipboardRead,
        }
    }
}

fn writeAvailable(send: *Send) error{ClipboardWrite}!void {
    while (send.offset < send.bytes.len) {
        const count = c.write(send.fd, send.bytes.ptr + send.offset, send.bytes.len - send.offset);
        if (count > 0) {
            send.offset += @intCast(count);
            continue;
        }
        if (count == 0) return error.ClipboardWrite;
        switch (std.posix.errno(count)) {
            .INTR => continue,
            .AGAIN => return,
            else => return error.ClipboardWrite,
        }
    }
}

fn configureDescriptor(fd: c_int) error{ClipboardDescriptor}!void {
    const flags = c.fcntl(fd, c.F_GETFL);
    const descriptor_flags = c.fcntl(fd, c.F_GETFD);
    if (flags < 0 or descriptor_flags < 0 or
        c.fcntl(fd, c.F_SETFL, flags | c.O_NONBLOCK) < 0 or
        c.fcntl(fd, c.F_SETFD, descriptor_flags | c.FD_CLOEXEC) < 0)
        return error.ClipboardDescriptor;
}

fn closeFd(fd: c_int) void {
    while (c.close(fd) != 0) {
        if (std.posix.errno(-1) != .INTR) break;
    }
}

test "MIME ranking is deterministic and ignores unrelated offers" {
    var offer: Offer = .{};
    offer.admit("application/octet-stream");
    try std.testing.expect(offer.preferred() == null);
    offer.admit("text/plain");
    try std.testing.expectEqual(Mime.plain, offer.preferred().?);
    offer.admit("text/plain;charset=utf-8");
    try std.testing.expectEqual(Mime.utf8, offer.preferred().?);
}

test "nonblocking receive is bounded and preserves partial progress" {
    const fds = try pipe();
    var transfers = Transfers.init(std.testing.allocator);
    defer transfers.deinit();
    try transfers.beginReceive(fds[0]);
    try std.posix.writeAll(fds[1], "first");
    try transfers.service(fds[0], std.posix.POLL.IN);
    try std.testing.expect(transfers.received() == null);
    try std.posix.writeAll(fds[1], "-second");
    closeFd(fds[1]);
    try transfers.service(fds[0], std.posix.POLL.IN | std.posix.POLL.HUP);
    try std.testing.expectEqualStrings("first-second", transfers.received().?);
}

test "source replacement and outgoing transfer own independent bytes" {
    const fds = try pipe();
    defer closeFd(fds[0]);
    var transfers = Transfers.init(std.testing.allocator);
    defer transfers.deinit();
    try transfers.replaceSource(try std.testing.allocator.dupe(u8, "old"));
    try transfers.beginSend(fds[1]);
    try transfers.replaceSource(try std.testing.allocator.dupe(u8, "new"));
    var descriptors: [max_sends + 1]std.posix.pollfd = undefined;
    const count = transfers.pollDescriptors(&descriptors);
    try std.testing.expectEqual(@as(usize, 1), count);
    try transfers.service(descriptors[0].fd, std.posix.POLL.OUT);
    var bytes: [3]u8 = undefined;
    try std.posix.readAtLeast(fds[0], &bytes, bytes.len);
    try std.testing.expectEqualStrings("old", &bytes);
}

test "nonblocking send preserves partial progress until peer capacity returns" {
    const fds = try pipe();
    defer closeFd(fds[0]);
    defer closeFd(fds[1]);
    const pipe_capacity = c.fcntl(fds[1], c.F_SETPIPE_SZ, 4096);
    try std.testing.expect(pipe_capacity >= 4096);
    const bytes = try std.testing.allocator.alloc(u8, @intCast(pipe_capacity * 2));
    defer std.testing.allocator.free(bytes);
    @memset(bytes, 'x');
    var send = Send{ .fd = fds[1], .bytes = bytes };
    try writeAvailable(&send);
    try std.testing.expect(send.offset > 0);
    try std.testing.expect(send.offset < send.bytes.len);

    const drained = try std.testing.allocator.alloc(u8, send.offset);
    defer std.testing.allocator.free(drained);
    try std.posix.readAtLeast(fds[0], drained, drained.len);
    try writeAvailable(&send);
    try std.testing.expectEqual(send.bytes.len, send.offset);
}

test "receive allocation failure closes admission and preserves empty ownership" {
    const fds = try pipe();
    defer closeFd(fds[1]);
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var transfers = Transfers.init(failing.allocator());
    defer transfers.deinit();
    try std.testing.expectError(error.OutOfMemory, transfers.beginReceive(fds[0]));
    try std.testing.expect(transfers.receive == null);
    try std.testing.expectEqual(@as(c_int, -1), c.fcntl(fds[0], c.F_GETFL));
}

test "source limit and send saturation preserve prior ownership" {
    var transfers = Transfers.init(std.testing.allocator);
    defer transfers.deinit();
    try transfers.replaceSource(try std.testing.allocator.dupe(u8, "kept"));
    const oversized = try std.testing.allocator.alloc(u8, max_bytes + 1);
    defer std.testing.allocator.free(oversized);
    try std.testing.expectError(error.ClipboardLimit, transfers.replaceSource(oversized));
    try std.testing.expectEqualStrings("kept", transfers.source);

    var read_fds: [max_sends]c_int = undefined;
    for (0..max_sends) |index| {
        const fds = try pipe();
        read_fds[index] = fds[0];
        try transfers.beginSend(fds[1]);
    }
    defer for (read_fds) |fd| closeFd(fd);
    const rejected = try pipe();
    defer closeFd(rejected[0]);
    try std.testing.expectError(error.ClipboardBusy, transfers.beginSend(rejected[1]));
    try std.testing.expectEqual(@as(c_int, -1), c.fcntl(rejected[1], c.F_GETFL));
    try std.testing.expectEqualStrings("kept", transfers.source);
}

test "receive overflow and peer HUP are exact" {
    const fds = try pipe();
    defer closeFd(fds[0]);
    var buffer: [4]u8 = undefined;
    var receive = Receive{ .fd = fds[0], .bytes = &buffer };
    try std.posix.writeAll(fds[1], "12345");
    closeFd(fds[1]);
    try std.testing.expectError(error.ClipboardLimit, readAvailable(&receive));
    try std.testing.expectEqual(@as(usize, 4), receive.len);
}
