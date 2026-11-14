//! Bounded child-directed reply bytes and framing.

const std = @import("std");

/// Selects terminal reply framing for one protocol family.
pub const Protocol = enum { terminal, kitty, iterm };

/// Names one C1 control emitted by a reply family.
pub const Control = enum { csi, dcs, osc, st };

/// Names the string-framing controls accepted by `appendString`.
pub const StringControl = enum { dcs, osc };

/// Exact failures while retaining bounded reply bytes.
pub const AppendError = error{ OutOfMemory, ReplyLimit };

/// Maximum bytes retained for child-directed replies.
pub const max_bytes: u32 = 64 * 1024;

/// Owns one bounded reply byte queue and its framing selection.
pub const Buffer = struct {
    allocator: std.mem.Allocator,
    bytes_storage: std.ArrayList(u8) = .empty,
    eight_bit_controls: bool = false,

    /// Initializes an empty reply queue.
    pub fn init(allocator: std.mem.Allocator) Buffer {
        return .{ .allocator = allocator };
    }

    /// Releases all retained reply bytes through the allocator retained at initialization.
    pub fn deinit(self: *Buffer) void {
        self.bytes_storage.deinit(self.allocator);
        self.* = undefined;
    }

    /// Transfers retained bytes to caller ownership through the initializer allocator and empties the queue.
    pub fn toOwnedSlice(self: *Buffer) std.mem.Allocator.Error![]u8 {
        return self.bytes_storage.toOwnedSlice(self.allocator);
    }

    /// Borrows all retained reply bytes until the next buffer mutation.
    pub fn bytes(self: *const Buffer) []const u8 {
        return self.bytes_storage.items;
    }

    /// Returns the current retained byte count.
    pub fn len(self: *const Buffer) u32 {
        return @intCast(self.bytes_storage.items.len);
    }

    /// Selects whether terminal-family controls use eight-bit C1 framing.
    pub fn setEightBitControls(self: *Buffer, enabled: bool) bool {
        if (self.eight_bit_controls == enabled) return false;
        self.eight_bit_controls = enabled;
        return true;
    }

    /// Returns the current terminal-family framing selection.
    fn usesEightBitControls(self: *const Buffer) bool {
        return self.eight_bit_controls;
    }

    /// Restores the terminal-default seven-bit framing selection.
    pub fn resetFraming(self: *Buffer) void {
        self.eight_bit_controls = false;
    }

    /// Copies only the framing selection from another reply buffer.
    pub fn copyFramingFrom(self: *Buffer, other: *const Buffer) void {
        self.eight_bit_controls = other.eight_bit_controls;
    }

    /// Reserves capacity owned by this buffer without changing retained bytes.
    pub fn ensureUnusedCapacity(self: *Buffer, additional: u32) AppendError!void {
        const next = std.math.add(u32, self.len(), additional) catch return error.ReplyLimit;
        if (next > max_bytes) return error.ReplyLimit;
        self.bytes_storage.ensureUnusedCapacity(self.allocator, @intCast(additional)) catch return error.OutOfMemory;
    }

    /// Appends bytes transactionally within the fixed queue bound.
    pub fn append(self: *Buffer, data: []const u8) AppendError!void {
        const data_len = std.math.cast(u32, data.len) orelse return error.ReplyLimit;
        const next = std.math.add(u32, self.len(), data_len) catch return error.ReplyLimit;
        if (next > max_bytes) return error.ReplyLimit;
        self.bytes_storage.appendSlice(self.allocator, data) catch return error.OutOfMemory;
    }

    /// Appends one protocol framing control through the selected C1 policy.
    pub fn appendControl(
        self: *Buffer,
        protocol: Protocol,
        control: Control,
    ) AppendError!void {
        const eight_bit = protocol == .terminal and self.eight_bit_controls;
        const framed = if (eight_bit) switch (control) {
            .csi => "\x9b",
            .dcs => "\x90",
            .osc => "\x9d",
            .st => "\x9c",
        } else switch (control) {
            .csi => "\x1b[",
            .dcs => "\x1bP",
            .osc => "\x1b]",
            .st => "\x1b\\",
        };
        try self.append(framed);
    }

    /// Appends one complete CSI reply transactionally.
    pub fn appendCsi(
        self: *Buffer,
        protocol: Protocol,
        payload: []const u8,
    ) AppendError!void {
        const start = self.len();
        errdefer self.truncate(start);
        try self.appendControl(protocol, .csi);
        try self.append(payload);
    }

    /// Appends one complete DCS or OSC reply transactionally.
    pub fn appendString(
        self: *Buffer,
        protocol: Protocol,
        control: StringControl,
        payload: []const u8,
    ) AppendError!void {
        const start = self.len();
        errdefer self.truncate(start);
        try self.appendControl(protocol, switch (control) {
            .dcs => .dcs,
            .osc => .osc,
        });
        try self.append(payload);
        try self.appendControl(protocol, .st);
    }

    /// Restores a previously retained prefix length after a failed transaction.
    pub fn truncate(self: *Buffer, length: u32) void {
        std.debug.assert(length <= self.len());
        self.bytes_storage.items.len = @intCast(length);
    }

    /// Consumes one successfully written prefix without allocating.
    pub fn consumePrefix(self: *Buffer, count: usize) error{InvalidReplyCount}!void {
        if (count > self.bytes_storage.items.len) return error.InvalidReplyCount;
        if (count == 0) return;
        const remaining = self.bytes_storage.items.len - count;
        std.mem.copyForwards(u8, self.bytes_storage.items[0..remaining], self.bytes_storage.items[count..]);
        self.bytes_storage.shrinkRetainingCapacity(remaining);
    }
};

test "reply buffer framing, bounds, and prefix consumption are exact" {
    var buffer = Buffer.init(std.testing.allocator);
    defer buffer.deinit();

    try buffer.appendCsi(.terminal, "5n");
    try std.testing.expectEqualStrings("\x1b[5n", buffer.bytes());
    try buffer.consumePrefix(2);
    try std.testing.expectEqualStrings("5n", buffer.bytes());
    try std.testing.expectError(error.InvalidReplyCount, buffer.consumePrefix(3));
    try std.testing.expectEqualStrings("5n", buffer.bytes());

    buffer.resetFraming();
    try buffer.appendString(.terminal, .osc, "0;ok");
    try std.testing.expectEqualStrings("5n\x1b]0;ok\x1b\\", buffer.bytes());

    const before = buffer.bytes().len;
    const oversized = try std.testing.allocator.alloc(u8, max_bytes + 1);
    defer std.testing.allocator.free(oversized);
    try std.testing.expectError(
        error.ReplyLimit,
        buffer.append(oversized),
    );
    try std.testing.expectEqual(before, buffer.bytes().len);
}

test "reply buffer uses C1 controls only for terminal protocol" {
    var buffer = Buffer.init(std.testing.allocator);
    defer buffer.deinit();
    try std.testing.expect(buffer.setEightBitControls(true));
    try buffer.appendControl(.terminal, .csi);
    try buffer.appendControl(.kitty, .osc);
    try std.testing.expectEqualStrings("\x9b\x1b]", buffer.bytes());
}

test "reply buffer transfers ownership through its initializer allocator" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    try buffer.append("owned");
    const transferred = try buffer.toOwnedSlice();
    defer allocator.free(transferred);
    try std.testing.expectEqualStrings("owned", transferred);
    try std.testing.expectEqual(@as(u32, 0), buffer.len());

    try buffer.append("reusable");
    try std.testing.expectEqualStrings("reusable", buffer.bytes());
}

test "CSI transaction allocation failure rolls back framing and remains reusable" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        csiTransactionAllocationFailure,
        .{},
    );
}

fn csiTransactionAllocationFailure(allocator: std.mem.Allocator) !void {
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();
    try buffer.append("keep");
    try buffer.ensureUnusedCapacity(2);

    var before: [4]u8 = undefined;
    @memcpy(&before, buffer.bytes());
    const framing = buffer.usesEightBitControls();
    buffer.appendCsi(.terminal, "payload") catch |err| {
        if (err != error.OutOfMemory) return err;
        try std.testing.expectEqualSlices(u8, &before, buffer.bytes());
        try std.testing.expectEqual(framing, buffer.usesEightBitControls());
        try buffer.append("reuse");
        return err;
    };
    try std.testing.expectEqualStrings("keep\x1b[payload", buffer.bytes());
}

test "string transaction allocation failure rolls back all framing and remains reusable" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        stringTransactionAllocationFailure,
        .{},
    );
}

fn stringTransactionAllocationFailure(allocator: std.mem.Allocator) !void {
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();
    try buffer.append("keep");
    try buffer.ensureUnusedCapacity(2);

    var before: [4]u8 = undefined;
    @memcpy(&before, buffer.bytes());
    const framing = buffer.usesEightBitControls();
    buffer.appendString(.terminal, .osc, "payload") catch |err| {
        if (err != error.OutOfMemory) return err;
        try std.testing.expectEqualSlices(u8, &before, buffer.bytes());
        try std.testing.expectEqual(framing, buffer.usesEightBitControls());
        try buffer.append("reuse");
        return err;
    };
    try std.testing.expectEqualStrings("keep\x1b]payload\x1b\\", buffer.bytes());
}
