//! Parser storage and bounded fragmented-control capture for one terminal lifetime.
//!
//! Terminal owns semantic application. This module owns only transient parser and
//! capture state, including exact reset, allocation, and overflow behavior.

const std = @import("std");
const consequences = @import("consequences.zig");
const graphics = @import("graphics.zig");
const parser = @import("parser.zig");
const sixel = @import("sixel.zig");

/// Generic APC, PM, and SOS capture uses the same metadata ceiling as parser-owned controls.
const generic_string_max_bytes: usize = 2 * 1024;

comptime {
    std.debug.assert(generic_string_max_bytes == parser.max_metadata_control_bytes);
}

/// Owns one fragmented DCS hook, body, and payload until completion or cancellation.
pub const DcsCapture = struct {
    /// Reports allocation failure while materializing one DCS hook prefix.
    pub const StartError = error{OutOfMemory};
    /// Reports allocation or the exact payload bound while appending DCS bytes.
    pub const PutError = error{ OutOfMemory, StringControlLimit };

    allocator: std.mem.Allocator,
    bytes: std.ArrayList(u8) = .empty,
    params_storage: [parser.max_params]i32 = @splat(0),
    intermediates_storage: [parser.max_intermediates]u8 = @splat(0),
    payload_start: usize = 0,
    final: u8 = 0,
    param_count: u8 = 0,
    intermediates_len: u8 = 0,
    active: bool = false,

    /// Initializes one inactive capture with caller-owned allocation policy.
    pub fn init(allocator: std.mem.Allocator) DcsCapture {
        return .{ .allocator = allocator };
    }

    /// Releases retained DCS bytes through the initializer allocator.
    pub fn deinit(self: *DcsCapture) void {
        self.bytes.deinit(self.allocator);
        self.* = undefined;
    }

    /// Returns the capture to an inactive reusable state while retaining capacity.
    pub fn reset(self: *DcsCapture) void {
        self.active = false;
        self.payload_start = 0;
        self.final = 0;
        self.param_count = 0;
        self.intermediates_len = 0;
        self.bytes.clearRetainingCapacity();
    }

    /// Copies one parser-borrowed hook and materializes its exact DCS body prefix.
    pub fn start(self: *DcsCapture, hook: parser.DcsHook) StartError!void {
        std.debug.assert(hook.count <= parser.max_params);
        std.debug.assert(hook.intermediates_len <= parser.max_intermediates);
        self.reset();
        self.active = true;
        self.final = hook.final;
        self.param_count = hook.count;
        self.intermediates_len = hook.intermediates_len;
        std.mem.copyForwards(i32, self.params_storage[0..hook.count], hook.params[0..hook.count]);
        std.mem.copyForwards(
            u8,
            self.intermediates_storage[0..hook.intermediates_len],
            hook.intermediates[0..hook.intermediates_len],
        );

        errdefer self.reset();
        var index: u8 = 0;
        while (index < hook.count) : (index += 1) {
            if (index > 0) try self.bytes.append(self.allocator, ';');
            var text_buffer: [32]u8 = undefined;
            const text = std.fmt.bufPrint(&text_buffer, "{d}", .{hook.params[index]}) catch unreachable;
            try self.bytes.appendSlice(self.allocator, text);
        }
        try self.bytes.appendSlice(
            self.allocator,
            self.intermediates_storage[0..hook.intermediates_len],
        );
        try self.bytes.append(self.allocator, hook.final);
        self.payload_start = self.bytes.items.len;
    }

    /// Appends one payload byte within the sixel or metadata-specific bound.
    pub fn put(self: *DcsCapture, byte: u8) PutError!void {
        std.debug.assert(self.active);
        const limit: usize = if (self.isSixel())
            sixel.max_encoded_bytes
        else
            parser.max_metadata_control_bytes;
        if (self.bytes.items.len - self.payload_start >= limit)
            return error.StringControlLimit;
        try self.bytes.append(self.allocator, byte);
    }

    /// Reports whether the active capture is an unintermediated sixel DCS.
    pub fn isSixel(self: *const DcsCapture) bool {
        return self.active and self.final == 'q' and self.intermediates_len == 0;
    }

    /// Borrows captured payload bytes until the next capture mutation.
    pub fn payload(self: *const DcsCapture) []const u8 {
        std.debug.assert(self.active);
        return self.bytes.items[self.payload_start..];
    }

    /// Borrows copied DCS parameters until the next capture mutation.
    pub fn parameters(self: *const DcsCapture) []const i32 {
        std.debug.assert(self.active);
        return self.params_storage[0..self.param_count];
    }

    /// Borrows one complete parser event until the next capture mutation.
    pub fn event(self: *const DcsCapture) parser.Event {
        std.debug.assert(self.active);
        return .{ .dcs = .{
            .body = self.bytes.items,
            .payload = self.payload(),
            .final = self.final,
            .params = self.parameters(),
            .param_count = self.param_count,
            .intermediates = self.intermediates_storage[0..self.intermediates_len],
            .intermediates_len = self.intermediates_len,
        } };
    }
};

/// Owns one fragmented APC, PM, or SOS payload until completion or cancellation.
pub const StringCapture = struct {
    allocator: std.mem.Allocator,
    bytes: std.ArrayList(u8) = .empty,
    kind: ?consequences.StringPayloadKind = null,
    overflowed: bool = false,

    /// Initializes one inactive generic string capture.
    pub fn init(allocator: std.mem.Allocator) StringCapture {
        return .{ .allocator = allocator };
    }

    /// Releases retained string bytes through the initializer allocator.
    pub fn deinit(self: *StringCapture) void {
        self.bytes.deinit(self.allocator);
        self.* = undefined;
    }

    /// Starts one APC, PM, or SOS capture and discards any prior transient bytes.
    pub fn start(self: *StringCapture, kind: consequences.StringPayloadKind) void {
        self.bytes.clearRetainingCapacity();
        self.kind = kind;
        self.overflowed = false;
    }

    /// Appends one byte or records bounded overflow while retaining no rejected payload.
    pub fn put(self: *StringCapture, byte: u8) error{OutOfMemory}!void {
        std.debug.assert(self.kind != null);
        if (self.overflowed) return;
        const limit: usize = if (self.isKittyGraphics())
            graphics.max_command_bytes + 1
        else
            generic_string_max_bytes;
        if (self.bytes.items.len >= limit) {
            self.overflowed = true;
            self.bytes.clearRetainingCapacity();
            return;
        }
        try self.bytes.append(self.allocator, byte);
    }

    /// Returns the capture to an inactive reusable state while retaining capacity.
    pub fn reset(self: *StringCapture) void {
        self.bytes.clearRetainingCapacity();
        self.kind = null;
        self.overflowed = false;
    }

    /// Reports whether the active payload exceeded its owner-specific byte bound.
    pub fn didOverflow(self: *const StringCapture) bool {
        return self.overflowed;
    }

    /// Reports whether retained bytes begin one Kitty graphics APC packet.
    pub fn isKittyGraphics(self: *const StringCapture) bool {
        return self.kind == .apc and self.bytes.items.len != 0 and self.bytes.items[0] == 'G';
    }

    /// Returns the active generic string-control classification.
    pub fn payloadKind(self: *const StringCapture) consequences.StringPayloadKind {
        return self.kind orelse @panic("string capture is inactive");
    }

    /// Borrows retained payload bytes until the next capture mutation.
    pub fn payload(self: *const StringCapture) []const u8 {
        std.debug.assert(self.kind != null);
        return self.bytes.items;
    }
};

/// Owns parser allocation and both fragmented-control captures for one terminal lifetime.
pub const State = struct {
    /// Reports parser-storage allocation failure during terminal construction.
    pub const InitError = error{OutOfMemory};

    parser: parser.Parser,
    dcs: DcsCapture,
    string: StringCapture,

    /// Initializes parser storage and inactive fragmented-control captures.
    pub fn init(allocator: std.mem.Allocator) InitError!State {
        return .{
            .parser = try parser.Parser.init(allocator),
            .dcs = DcsCapture.init(allocator),
            .string = StringCapture.init(allocator),
        };
    }

    /// Releases parser and capture allocations in reverse ownership order.
    pub fn deinit(self: *State) void {
        self.dcs.deinit();
        self.string.deinit();
        self.parser.deinit();
        self.* = undefined;
    }
};

test "stream state initialization reports parser allocation failure" {
    const init: *const fn (std.mem.Allocator) State.InitError!State = State.init;
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, init(failing.allocator()));
    try std.testing.expect(failing.has_induced_failure);
}

test "DCS capture start and put report exact failures and remain reusable" {
    const start: *const fn (*DcsCapture, parser.DcsHook) DcsCapture.StartError!void = DcsCapture.start;
    const put: *const fn (*DcsCapture, u8) DcsCapture.PutError!void = DcsCapture.put;
    const hook: parser.DcsHook = .{
        .final = 'q',
        .params = &.{1},
        .count = 1,
        .intermediates = "$",
        .intermediates_len = 1,
    };

    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var capture = DcsCapture.init(failing.allocator());
    defer capture.deinit();

    try std.testing.expectError(error.OutOfMemory, start(&capture, hook));
    try std.testing.expect(!capture.active);
    try std.testing.expectEqual(@as(usize, 0), capture.bytes.items.len);

    failing.fail_index = std.math.maxInt(usize);
    try start(&capture, hook);
    const payload_start = capture.payload_start;
    failing.fail_index = failing.alloc_index;

    var put_count: u32 = 0;
    while (!failing.has_induced_failure) : (put_count += 1) {
        try std.testing.expect(put_count < parser.max_metadata_control_bytes);
        put(&capture, 'x') catch |failure| {
            try std.testing.expectEqual(error.OutOfMemory, failure);
            break;
        };
    }
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expect(capture.active);
    try std.testing.expectEqual(payload_start + put_count, capture.bytes.items.len);

    failing.fail_index = std.math.maxInt(usize);
    try put(&capture, 'y');
    while (capture.payload().len < parser.max_metadata_control_bytes)
        try put(&capture, 'z');
    try std.testing.expectError(error.StringControlLimit, put(&capture, 'z'));
    capture.reset();
    try std.testing.expect(!capture.active);
    try start(&capture, hook);
}

test "string capture bounds generic controls and discards overflow storage" {
    var capture = StringCapture.init(std.testing.allocator);
    defer capture.deinit();
    capture.start(.pm);
    for (0..generic_string_max_bytes) |_| try capture.put('x');
    try std.testing.expect(!capture.didOverflow());
    try capture.put('x');
    try std.testing.expect(capture.didOverflow());
    try std.testing.expectEqual(@as(usize, 0), capture.payload().len);
    try capture.put('y');
    try std.testing.expectEqual(@as(usize, 0), capture.payload().len);
    capture.reset();
    capture.start(.sos);
    try capture.put('z');
    try std.testing.expectEqualStrings("z", capture.payload());
}

test "string capture distinguishes Kitty graphics by exact APC prefix" {
    var capture = StringCapture.init(std.testing.allocator);
    defer capture.deinit();
    capture.start(.apc);
    try std.testing.expect(!capture.isKittyGraphics());
    try capture.put('G');
    try std.testing.expect(capture.isKittyGraphics());
    capture.reset();
    capture.start(.pm);
    try capture.put('G');
    try std.testing.expect(!capture.isKittyGraphics());
}
