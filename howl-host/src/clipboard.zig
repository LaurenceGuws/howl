//! Owns bounded UTF-8 clipboard bytes and nonblocking transfer progress.

const std = @import("std");
const control = @import("howl_control");

const c = @cImport({
    @cDefine("_FORTIFY_SOURCE", "0");
    @cDefine("_GNU_SOURCE", "1");
    @cInclude("errno.h");
    @cInclude("fcntl.h");
    @cInclude("sys/random.h");
    @cInclude("unistd.h");
});

/// Bounds clipboard text for both bracketed-paste admission and exact OSC 52 replies.
pub const max_bytes: usize = @min(control.max_input_bytes - 12, control.clipboard_reply_max_bytes);
/// Bounds simultaneous compositor requests for the current clipboard source.
pub const max_sends: usize = 2;
/// Bounds one Kitty paste-event grant string before metadata base64 encoding.
pub const grant_bytes: usize = 32;
/// Bounds one Kitty OSC 5522 read response below Control's complete-transfer ceiling.
pub const kitty_read_max_bytes: usize = 32 * 1024;
const paste_name_encoded = "UGFzdGUgZXZlbnQ=";
const targets_mime_encoded = "Lg==";
const mime_list = "text/plain;charset=utf-8 text/plain\n";
/// Names the read/write operation echoed in one Kitty policy response.
pub const KittyOperation = enum { read, write };
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

/// Retains one operator-created OSC 5522 read grant without owning clipboard bytes.
pub const PasteGrant = struct {
    /// Stores lowercase hexadecimal random bytes compared after metadata decoding.
    password: [grant_bytes]u8,

    /// Encodes one random 128-bit value into the retained fixed password.
    pub fn fromRandom(random: [grant_bytes / 2]u8) PasteGrant {
        var result: PasteGrant = undefined;
        const encoded = std.fmt.bufPrint(&result.password, "{x}", .{random}) catch
            @panic("fixed hexadecimal grant buffer was mis-sized");
        std.debug.assert(encoded.len == result.password.len);
        return result;
    }
};

/// Classifies the bounded Kitty OSC 5522 request subset owned by the Wayland host.
pub const KittyRequest = union(enum) {
    /// Requests one advertised clipboard representation using an operator grant.
    read: struct {
        password: []const u8,
        name: []const u8,
        id: []const u8,
        mime: Mime,
    },
    /// Names a syntactically valid request outside current clipboard policy.
    denied: struct { id: []const u8, operation: KittyOperation },
    /// Reports malformed metadata or base64 without retaining packet borrows.
    malformed,
};

/// Reports whether one parsed read exactly consumes this operator-created grant.
pub fn grantAllows(grant: PasteGrant, offer: Offer, request: KittyRequest) bool {
    const read = switch (request) {
        .read => |value| value,
        .denied, .malformed => return false,
    };
    return std.mem.eql(u8, read.password, &grant.password) and
        std.mem.eql(u8, read.name, "Paste event") and
        switch (read.mime) {
            .plain => offer.plain,
            .utf8 => offer.utf8,
        };
}

/// Parses one retained Kitty packet while borrowing its bytes.
pub fn parseKittyRequest(packet: []const u8, scratch: []u8) KittyRequest {
    const separator = std.mem.indexOfScalar(u8, packet, ';');
    const metadata = if (separator) |index| packet[0..index] else packet;
    const payload = if (separator) |index| packet[index + 1 ..] else "";
    var operation: ?KittyOperation = null;
    var location_primary = false;
    var password_encoded: []const u8 = "";
    var name_encoded: []const u8 = "";
    var id: []const u8 = "";
    var fields = std.mem.splitScalar(u8, metadata, ':');
    while (fields.next()) |field| {
        const equals = std.mem.indexOfScalar(u8, field, '=') orelse return .malformed;
        const key = field[0..equals];
        const value = field[equals + 1 ..];
        if (std.mem.eql(u8, key, "type")) {
            operation = if (std.mem.eql(u8, value, "read"))
                .read
            else if (std.mem.eql(u8, value, "write"))
                .write
            else
                return .malformed;
        } else if (std.mem.eql(u8, key, "loc")) {
            location_primary = std.mem.eql(u8, value, "primary");
        } else if (std.mem.eql(u8, key, "pw")) {
            password_encoded = value;
        } else if (std.mem.eql(u8, key, "name")) {
            name_encoded = value;
        } else if (std.mem.eql(u8, key, "id")) {
            id = sanitizeId(value, scratch);
        }
    }
    const selected = operation orelse return .malformed;
    if (selected == .write or location_primary) return .{ .denied = .{
        .id = id,
        .operation = selected,
    } };
    const password = decodeMetadata(password_encoded, scratch[id.len..]) orelse return .malformed;
    const name_offset = id.len + password.len;
    const name = decodeMetadata(name_encoded, scratch[name_offset..]) orelse return .malformed;
    const mime_offset = name_offset + name.len;
    const mime_bytes = decodeMetadata(payload, scratch[mime_offset..]) orelse return .malformed;
    var requested = std.mem.tokenizeScalar(u8, mime_bytes, ' ');
    const first = requested.next() orelse return .malformed;
    if (requested.next() != null) return .{ .denied = .{ .id = id, .operation = .read } };
    const mime: Mime = if (std.mem.eql(u8, first, Mime.utf8.bytes()))
        .utf8
    else if (std.mem.eql(u8, first, Mime.plain.bytes()))
        .plain
    else
        return .{ .denied = .{ .id = id, .operation = .read } };
    return .{ .read = .{
        .password = password,
        .name = name,
        .id = id,
        .mime = mime,
    } };
}

/// Allocates the exact three-packet paste event advertising Howl's UTF-8 MIME set.
pub fn pasteEvent(
    allocator: std.mem.Allocator,
    grant: PasteGrant,
    offer: Offer,
) std.mem.Allocator.Error![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    var password_encoded: [std.base64.standard.Encoder.calcSize(grant.password.len)]u8 = undefined;
    const password = std.base64.standard.Encoder.encode(&password_encoded, &grant.password);
    try appendKittyResponse(allocator, &output, "", "OK", "", password, "");
    const available: []const u8 = if (offer.utf8 and offer.plain)
        mime_list
    else if (offer.utf8)
        "text/plain;charset=utf-8\n"
    else if (offer.plain)
        "text/plain\n"
    else
        "";
    if (available.len != 0) {
        var payload_encoded: [std.base64.standard.Encoder.calcSize(mime_list.len)]u8 = undefined;
        const payload = std.base64.standard.Encoder.encode(
            payload_encoded[0..std.base64.standard.Encoder.calcSize(available.len)],
            available,
        );
        try appendKittyResponse(allocator, &output, "", "DATA", targets_mime_encoded, password, payload);
    }
    try appendKittyResponse(allocator, &output, "", "DONE", "", password, "");
    return output.toOwnedSlice(allocator);
}

/// Allocates one complete Kitty read transaction for copied UTF-8 clipboard bytes.
pub fn kittyReadReply(
    allocator: std.mem.Allocator,
    id: []const u8,
    mime: Mime,
    bytes: []const u8,
) (std.mem.Allocator.Error || error{ClipboardLimit})![]u8 {
    if (bytes.len > kitty_read_max_bytes) return error.ClipboardLimit;
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    try appendKittyResponse(allocator, &output, id, "OK", "", "", "");
    const encoded_len = std.base64.standard.Encoder.calcSize(bytes.len);
    const encoded = try allocator.alloc(u8, encoded_len);
    defer allocator.free(encoded);
    const encoded_bytes = std.base64.standard.Encoder.encode(encoded, bytes);
    std.debug.assert(encoded_bytes.len == encoded.len);
    var mime_encoded: [std.base64.standard.Encoder.calcSize(Mime.utf8.bytes().len)]u8 = undefined;
    const encoded_mime = std.base64.standard.Encoder.encode(
        mime_encoded[0..std.base64.standard.Encoder.calcSize(mime.bytes().len)],
        mime.bytes(),
    );
    try appendKittyResponse(allocator, &output, id, "DATA", encoded_mime, "", encoded);
    try appendKittyResponse(allocator, &output, id, "DONE", "", "", "");
    if (output.items.len > control.max_transfer_bytes) return error.ClipboardLimit;
    return output.toOwnedSlice(allocator);
}

/// Allocates one exact Kitty policy rejection for a read or write packet.
pub fn kittyDeniedReply(
    allocator: std.mem.Allocator,
    id: []const u8,
    operation: KittyOperation,
) std.mem.Allocator.Error![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    try output.appendSlice(allocator, "\x1b]5522;type=");
    try output.appendSlice(allocator, @tagName(operation));
    try output.appendSlice(allocator, ":status=EPERM");
    if (id.len != 0) {
        try output.appendSlice(allocator, ":id=");
        try output.appendSlice(allocator, id);
    }
    try output.appendSlice(allocator, "\x1b\\");
    return output.toOwnedSlice(allocator);
}

fn appendKittyResponse(
    allocator: std.mem.Allocator,
    output: *std.ArrayList(u8),
    id: []const u8,
    status: []const u8,
    mime: []const u8,
    password: []const u8,
    payload: []const u8,
) std.mem.Allocator.Error!void {
    try output.appendSlice(allocator, "\x1b]5522;type=read:status=");
    try output.appendSlice(allocator, status);
    if (id.len != 0) {
        try output.appendSlice(allocator, ":id=");
        try output.appendSlice(allocator, id);
    }
    if (mime.len != 0) {
        try output.appendSlice(allocator, ":mime=");
        try output.appendSlice(allocator, mime);
    }
    if (password.len != 0) {
        try output.appendSlice(allocator, ":pw=");
        try output.appendSlice(allocator, password);
    }
    if (payload.len != 0) {
        try output.append(allocator, ';');
        try output.appendSlice(allocator, payload);
    }
    try output.appendSlice(allocator, "\x1b\\");
}

fn sanitizeId(value: []const u8, output: []u8) []const u8 {
    var len: usize = 0;
    for (value) |byte| if (std.ascii.isAlphanumeric(byte) or
        byte == '-' or byte == '_' or byte == '+' or byte == '.')
    {
        if (len == output.len) break;
        output[len] = byte;
        len += 1;
    };
    return output[0..len];
}

fn decodeMetadata(encoded: []const u8, output: []u8) ?[]const u8 {
    const len = std.base64.standard.Decoder.calcSizeForSlice(encoded) catch return null;
    if (len > output.len) return null;
    std.base64.standard.Decoder.decode(output[0..len], encoded) catch return null;
    return output[0..len];
}

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
    ClipboardRandom,
    ClipboardWrite,
};

/// Obtains one Linux-kernel random paste grant without process-global state.
pub fn randomGrant() error{ClipboardRandom}!PasteGrant {
    var random: [grant_bytes / 2]u8 = undefined;
    var offset: usize = 0;
    while (offset < random.len) {
        const count = c.getrandom(random[offset..].ptr, random.len - offset, 0);
        if (count > 0) {
            offset += @intCast(count);
            continue;
        }
        if (count < 0 and std.posix.errno(count) == .INTR) continue;
        return error.ClipboardRandom;
    }
    return PasteGrant.fromRandom(random);
}

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

    /// Borrows current clipboard source bytes until replacement, cancellation, or cleanup.
    pub fn sourceBytes(self: *const Transfers) []const u8 {
        return self.source;
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

test "Kitty paste event and granted read use exact bounded framing" {
    const grant = PasteGrant.fromRandom(@splat(0xab));
    try std.testing.expectEqualStrings(
        "abababababababababababababababab",
        &grant.password,
    );
    const event = try pasteEvent(std.testing.allocator, grant, .{ .plain = true, .utf8 = true });
    defer std.testing.allocator.free(event);
    try std.testing.expectEqualStrings(
        "\x1b]5522;type=read:status=OK:pw=YWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWI=\x1b\\" ++
            "\x1b]5522;type=read:status=DATA:mime=Lg==:pw=YWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWI=;" ++
            "dGV4dC9wbGFpbjtjaGFyc2V0PXV0Zi04IHRleHQvcGxhaW4K\x1b\\" ++
            "\x1b]5522;type=read:status=DONE:pw=YWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWI=\x1b\\",
        event,
    );

    var scratch: [256]u8 = undefined;
    const request = parseKittyRequest(
        "type=read:id=a!b:pw=YWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWJhYmFiYWI=:" ++
            "name=" ++ paste_name_encoded ++ ";dGV4dC9wbGFpbjtjaGFyc2V0PXV0Zi04",
        &scratch,
    );
    switch (request) {
        .read => |read| {
            try std.testing.expectEqualStrings("ab", read.id);
            try std.testing.expectEqualStrings(&grant.password, read.password);
            try std.testing.expectEqualStrings("Paste event", read.name);
            try std.testing.expectEqual(Mime.utf8, read.mime);
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expect(grantAllows(
        grant,
        .{ .utf8 = true },
        request,
    ));
    try std.testing.expect(!grantAllows(
        grant,
        .{ .plain = true },
        request,
    ));
    var wrong = grant;
    wrong.password[0] = '0';
    try std.testing.expect(!grantAllows(
        wrong,
        .{ .utf8 = true },
        request,
    ));
    const reply = try kittyReadReply(std.testing.allocator, "ab", .utf8, "hello");
    defer std.testing.allocator.free(reply);
    try std.testing.expectEqualStrings(
        "\x1b]5522;type=read:status=OK:id=ab\x1b\\" ++
            "\x1b]5522;type=read:status=DATA:id=ab:mime=dGV4dC9wbGFpbjtjaGFyc2V0PXV0Zi04;aGVsbG8=\x1b\\" ++
            "\x1b]5522;type=read:status=DONE:id=ab\x1b\\",
        reply,
    );
}

test "Kitty packet parser denies policy and rejects malformed base64" {
    var scratch: [256]u8 = undefined;
    const primary = parseKittyRequest(
        "type=read:loc=primary:id=x;dGV4dC9wbGFpbg==",
        &scratch,
    );
    try std.testing.expectEqual(KittyOperation.read, primary.denied.operation);
    const write = parseKittyRequest("type=write:id=y", &scratch);
    try std.testing.expectEqual(KittyOperation.write, write.denied.operation);
    try std.testing.expect(parseKittyRequest(
        "type=read:pw=!:name=QQ==;dGV4dC9wbGFpbg==",
        &scratch,
    ) == .malformed);
    const denied = try kittyDeniedReply(std.testing.allocator, "x", .write);
    defer std.testing.allocator.free(denied);
    try std.testing.expectEqualStrings(
        "\x1b]5522;type=write:status=EPERM:id=x\x1b\\",
        denied,
    );
    const empty_event = try pasteEvent(
        std.testing.allocator,
        PasteGrant.fromRandom(@splat(2)),
        .{},
    );
    defer std.testing.allocator.free(empty_event);
    try std.testing.expect(std.mem.indexOf(u8, empty_event, "status=DATA") == null);
}

test "Kitty reply construction is allocation-transactional and bounded" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        kittyReplyAllocation,
        .{},
    );
    const oversized = [_]u8{'x'} ** (kitty_read_max_bytes + 1);
    try std.testing.expectError(
        error.ClipboardLimit,
        kittyReadReply(std.testing.allocator, "", .plain, &oversized),
    );
}

fn kittyReplyAllocation(allocator: std.mem.Allocator) !void {
    const event = try pasteEvent(
        allocator,
        PasteGrant.fromRandom(@splat(1)),
        .{ .utf8 = true },
    );
    defer allocator.free(event);
    const reply = try kittyReadReply(allocator, "id", .plain, "clipboard");
    defer allocator.free(reply);
}

test "nonblocking receive is bounded and preserves partial progress" {
    const fds = try pipe();
    var transfers = Transfers.init(std.testing.allocator);
    defer transfers.deinit();
    try transfers.beginReceive(fds[0]);
    try writeAllFd(fds[1], "first");
    try transfers.service(fds[0], std.posix.POLL.IN);
    try std.testing.expect(transfers.received() == null);
    try writeAllFd(fds[1], "-second");
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
    try std.testing.expectEqualStrings("new", transfers.sourceBytes());
    var descriptors: [max_sends + 1]std.posix.pollfd = undefined;
    const count = transfers.pollDescriptors(&descriptors);
    try std.testing.expectEqual(@as(usize, 1), count);
    try transfers.service(descriptors[0].fd, std.posix.POLL.OUT);
    var bytes: [3]u8 = undefined;
    try readExactFd(fds[0], &bytes);
    try std.testing.expectEqualStrings("old", &bytes);
    transfers.clearSource();
    try std.testing.expectEqualStrings("", transfers.sourceBytes());
}

test "nonblocking send preserves partial progress until peer capacity returns" {
    const fds = try pipe();
    defer closeFd(fds[0]);
    defer closeFd(fds[1]);
    const pipe_capacity = c.fcntl(fds[1], c.F_SETPIPE_SZ, @as(c_int, 4096));
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
    try readExactFd(fds[0], drained);
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
    try writeAllFd(fds[1], "12345");
    closeFd(fds[1]);
    try std.testing.expectError(error.ClipboardLimit, readAvailable(&receive));
    try std.testing.expectEqual(@as(usize, 4), receive.len);
}

fn writeAllFd(fd: c_int, bytes: []const u8) !void {
    var written: usize = 0;
    while (written < bytes.len) {
        const count = c.write(fd, bytes[written..].ptr, bytes.len - written);
        if (count > 0) {
            written += @intCast(count);
            continue;
        }
        if (count < 0 and std.posix.errno(count) == .INTR) continue;
        return error.TestUnexpectedResult;
    }
}

fn readExactFd(fd: c_int, bytes: []u8) !void {
    var read: usize = 0;
    while (read < bytes.len) {
        const count = c.read(fd, bytes[read..].ptr, bytes.len - read);
        if (count > 0) {
            read += @intCast(count);
            continue;
        }
        if (count < 0 and std.posix.errno(count) == .INTR) continue;
        return error.TestUnexpectedResult;
    }
}
