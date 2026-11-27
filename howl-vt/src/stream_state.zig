//! Parser storage and bounded fragmented-control capture for one terminal lifetime.
//!
//! Terminal owns semantic application. This module owns only transient parser and
//! capture state, including exact reset, allocation, and overflow behavior.

const std = @import("std");
const consequences = @import("consequences.zig");
const graphics = @import("graphics.zig");
const iterm_control = @import("iterm_control.zig");
const png = @import("png.zig");
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
    /// Reports allocation failure while appending bounded DCS bytes.
    pub const PutError = error{OutOfMemory};
    /// The semantic owner may discard a known reserved payload while the
    /// parser still owns framing and cancellation.
    pub const PayloadPolicy = enum { retain, discard };

    allocator: std.mem.Allocator,
    bytes: std.ArrayList(u8) = .empty,
    params_storage: [parser.max_params]i32 = @splat(0),
    intermediates_storage: [parser.max_intermediates]u8 = @splat(0),
    payload_start: usize = 0,
    final: u8 = 0,
    param_count: u8 = 0,
    intermediates_len: u8 = 0,
    active: bool = false,
    overflowed: bool = false,
    payload_policy: PayloadPolicy = .retain,

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
        self.overflowed = false;
        self.payload_policy = .retain;
        self.bytes.clearRetainingCapacity();
    }

    /// Copies one parser-borrowed hook and materializes its exact DCS body prefix.
    pub fn start(self: *DcsCapture, hook: parser.DcsHook, policy: PayloadPolicy) StartError!void {
        std.debug.assert(hook.count <= parser.max_params);
        std.debug.assert(hook.intermediates_len <= parser.max_intermediates);
        self.reset();
        self.active = true;
        self.payload_policy = policy;
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
            // zig-audit: acknowledge catch_unreachable
            // reason: The destination and encoded value are already bounded to fit; failure would contradict the established capacity/value invariant.
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
    ///
    /// Once the bound is exceeded, retained bytes are released and later payload
    /// bytes are ignored until DCS completion/cancellation. Allocation failure
    /// remains exceptional.
    pub fn put(self: *DcsCapture, byte: u8) PutError!void {
        std.debug.assert(self.active);
        if (self.overflowed or self.payload_policy == .discard) return;
        const limit: usize = if (self.isSixel())
            sixel.max_encoded_bytes
        else
            parser.max_metadata_control_bytes;
        if (self.bytes.items.len - self.payload_start >= limit) {
            self.overflowed = true;
            self.bytes.clearRetainingCapacity();
            self.payload_start = 0;
            return;
        }
        try self.bytes.append(self.allocator, byte);
    }

    /// Reports whether this DCS exceeded its bounded retained payload.
    pub fn didOverflow(self: *const DcsCapture) bool {
        return self.overflowed;
    }

    /// Reports whether the active capture is an unintermediated sixel DCS.
    pub fn isSixel(self: *const DcsCapture) bool {
        return self.active and self.final == 'q' and self.intermediates_len == 0;
    }

    /// Borrows captured payload bytes until the next capture mutation.
    pub fn payload(self: *const DcsCapture) []const u8 {
        std.debug.assert(self.active);
        std.debug.assert(!self.overflowed);
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
        std.debug.assert(!self.overflowed);
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
    kitty_graphics: bool = false,
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
        self.kitty_graphics = false;
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
        if (self.bytes.items.len == 1)
            self.kitty_graphics = self.kind == .apc and byte == 'G';
    }

    /// Appends a parser-qualified payload run under the same byte/prefix bound
    /// as `put`. The first byte still decides anonymous APC versus Kitty data.
    pub fn putSlice(self: *StringCapture, bytes: []const u8) error{OutOfMemory}!void {
        std.debug.assert(self.kind != null);
        if (self.overflowed or bytes.len == 0) return;
        var remaining = bytes;
        if (self.bytes.items.len == 0) {
            try self.put(bytes[0]);
            remaining = bytes[1..];
        }
        const limit: usize = if (self.isKittyGraphics())
            graphics.max_command_bytes + 1
        else
            generic_string_max_bytes;
        if (remaining.len > limit - self.bytes.items.len) {
            self.overflowed = true;
            self.bytes.clearRetainingCapacity();
            return;
        }
        try self.bytes.appendSlice(self.allocator, remaining);
    }

    /// Returns the capture to an inactive reusable state while retaining capacity.
    pub fn reset(self: *StringCapture) void {
        self.bytes.clearRetainingCapacity();
        self.kind = null;
        self.kitty_graphics = false;
        self.overflowed = false;
    }

    /// Reports whether the active payload exceeded its owner-specific byte bound.
    pub fn didOverflow(self: *const StringCapture) bool {
        return self.overflowed;
    }

    /// Reports the initial APC classification even after overflow discards bytes.
    pub fn isKittyGraphics(self: *const StringCapture) bool {
        return self.kitty_graphics;
    }

    /// Returns the active generic string-control classification.
    pub fn payloadKind(self: *const StringCapture) consequences.StringPayloadKind {
        // zig-audit: acknowledge panic
        // reason: This path represents an internal invariant breach with no safe caller recovery; continuing would corrupt owned state.
        return self.kind orelse @panic("string capture is inactive");
    }

    /// Borrows retained payload bytes until the next capture mutation.
    pub fn payload(self: *const StringCapture) []const u8 {
        std.debug.assert(self.kind != null);
        return self.bytes.items;
    }
};

/// Reports retained input awaiting storage or reply capacity.
pub const InputBlock = error{ OutOfMemory, ScalarCapacity, HistoryCapacity, ReplyLimit };
/// Line movement retained as one operation across history admission failure.
pub const LineFeed = enum { index, next_line, next_line_tab };

/// Owns decoded work until it can continue without replaying bytes.
pub const PendingInput = struct {
    // Sized text borrows the OSC parser buffer; kitty_packet uses the
    // completed StringCapture. Neither capture may be reused before recovery.
    work: union(enum) { codepoint: u21, repeat: u16, scroll_up: u16, archive_display: u16, sized_text: struct { payload: []const u8, offset: usize }, line_feed: LineFeed, kitty_packet },
    failure: InputBlock,
};

/// Bounds concatenated Base64 by the shared PNG decoder's encoded file limit.
pub const max_multipart_encoded_bytes = std.base64.standard.Encoder.calcSize(png.max_encoded_bytes);

/// Owns only transient inline-file metadata and concatenated wire bytes.
/// Opaque legacy packets remain caller-owned until an inline start selects
/// this lane; a failed or completed selected transaction never falls back.
pub const Multipart = union(enum) {
    legacy,
    discard,
    selected: struct {
        options: iterm_control.InlineOptions,
        encoded: std.ArrayList(u8) = .empty,
    },
};

/// Owns parser allocation and fragmented-control captures for one terminal lifetime.
pub const State = struct {
    /// Reports parser-storage allocation failure during terminal construction.
    pub const InitError = error{OutOfMemory};

    parser: parser.Parser,
    dcs: DcsCapture,
    string: StringCapture,
    multipart: Multipart = .legacy,
    pending_input: ?PendingInput = null,

    /// Initializes parser storage and inactive fragmented-control captures.
    pub fn init(allocator: std.mem.Allocator) InitError!State {
        return .{
            .parser = try parser.Parser.init(allocator),
            .dcs = DcsCapture.init(allocator),
            .string = StringCapture.init(allocator),
        };
    }

    /// Starts an inline transaction with no eagerly allocated byte buffer.
    pub fn beginMultipart(self: *State, allocator: std.mem.Allocator, options: iterm_control.InlineOptions) void {
        self.discardMultipart(allocator);
        self.multipart = .{ .selected = .{ .options = options } };
        self.parser.setInlineMultipartCapture(true);
    }

    /// Releases selected transfer bytes and suppresses subsequent stale parts.
    pub fn discardMultipart(self: *State, allocator: std.mem.Allocator) void {
        if (self.multipart == .selected) self.multipart.selected.encoded.deinit(allocator);
        self.multipart = .discard;
        self.parser.setInlineMultipartCapture(false);
    }

    /// Cancels an existing inline lane without changing the legacy idle lane.
    pub fn abortMultipart(self: *State, allocator: std.mem.Allocator) void {
        if (self.multipart == .selected) self.discardMultipart(allocator);
    }

    /// An explicit non-inline multipart start restores opaque caller ownership.
    pub fn openOpaqueMultipart(self: *State, allocator: std.mem.Allocator) void {
        self.discardMultipart(allocator);
        self.multipart = .legacy;
    }

    /// Appends a nonempty Base64 fragment; padding is validated across all
    /// parts, with complete quartet validation left to the final decoder.
    /// Invalid data or allocation failure releases the complete transaction.
    pub fn appendMultipart(self: *State, allocator: std.mem.Allocator, part: []const u8) error{OutOfMemory}!void {
        if (self.multipart != .selected) return;
        errdefer self.discardMultipart(allocator);
        const encoded = &self.multipart.selected.encoded;
        if (part.len == 0 or part.len > max_multipart_encoded_bytes - encoded.items.len) {
            self.discardMultipart(allocator);
            return;
        }
        var padding: u2 = if (std.mem.endsWith(u8, encoded.items, "=="))
            2
        else if (std.mem.endsWith(u8, encoded.items, "="))
            1
        else
            0;
        for (part) |byte| {
            switch (byte) {
                'A'...'Z', 'a'...'z', '0'...'9', '+', '/' => {
                    if (padding == 0) continue;
                },
                '=' => {
                    if (padding < 2) {
                        padding += 1;
                        continue;
                    }
                },
                else => {},
            }
            self.discardMultipart(allocator);
            return;
        }
        const required = encoded.items.len + part.len;
        if (required > encoded.capacity) {
            const capacity = @min(max_multipart_encoded_bytes, @max(required, encoded.capacity * 2));
            try encoded.ensureTotalCapacityPrecise(allocator, capacity);
        }
        encoded.appendSliceAssumeCapacity(part);
    }

    /// Releases parser and capture allocations in reverse ownership order.
    pub fn deinit(self: *State) void {
        self.abortMultipart(self.string.allocator);
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
    const start: *const fn (*DcsCapture, parser.DcsHook, DcsCapture.PayloadPolicy) DcsCapture.StartError!void = DcsCapture.start;
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

    try std.testing.expectError(error.OutOfMemory, start(&capture, hook, .retain));
    try std.testing.expect(!capture.active);
    try std.testing.expectEqual(@as(usize, 0), capture.bytes.items.len);

    failing.fail_index = std.math.maxInt(usize);
    try start(&capture, hook, .retain);
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
    try put(&capture, 'z');
    try std.testing.expect(capture.didOverflow());
    try std.testing.expect(capture.active);
    try std.testing.expectEqual(@as(usize, 0), capture.bytes.items.len);
    try put(&capture, 'y');
    try std.testing.expectEqual(@as(usize, 0), capture.bytes.items.len);
    capture.reset();
    try std.testing.expect(!capture.active);
    try start(&capture, hook, .retain);
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

test "string run capture shares generic and Kitty bounds across fragments" {
    const cases = [_]struct { kind: consequences.StringPayloadKind, prefix: u8, limit: usize }{
        .{ .kind = .apc, .prefix = 'G', .limit = graphics.max_command_bytes + 1 },
        .{ .kind = .apc, .prefix = 'x', .limit = generic_string_max_bytes },
        .{ .kind = .pm, .prefix = 'G', .limit = generic_string_max_bytes },
    };
    var bytes: [graphics.max_command_bytes + 2]u8 = @splat('x');
    for (cases) |case| {
        var fast = StringCapture.init(std.testing.allocator);
        defer fast.deinit();
        var scalar = StringCapture.init(std.testing.allocator);
        defer scalar.deinit();
        fast.start(case.kind);
        scalar.start(case.kind);
        bytes[0] = case.prefix;
        try fast.putSlice(bytes[0..1]);
        try fast.putSlice(bytes[1..case.limit]);
        for (bytes[0..case.limit]) |byte| try scalar.put(byte);
        try std.testing.expectEqualSlices(u8, scalar.payload(), fast.payload());
        try std.testing.expect(!fast.didOverflow());
        try fast.putSlice("tail");
        for ("tail") |byte| try scalar.put(byte);
        try std.testing.expectEqual(scalar.didOverflow(), fast.didOverflow());
        const kitty = case.kind == .apc and case.prefix == 'G';
        try std.testing.expectEqual(kitty, scalar.isKittyGraphics());
        try std.testing.expectEqual(kitty, fast.isKittyGraphics());
        try std.testing.expectEqualSlices(u8, scalar.payload(), fast.payload());
        fast.reset();
        fast.start(.apc);
        try fast.putSlice("Gnext");
        try std.testing.expectEqualStrings("Gnext", fast.payload());
    }
}

test "string run allocation failure remains bounded and reusable" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var capture = StringCapture.init(failing.allocator());
    defer capture.deinit();
    capture.start(.apc);
    try std.testing.expectError(error.OutOfMemory, capture.putSlice("Gdata"));
    try std.testing.expectEqual(@as(usize, 0), capture.payload().len);
    failing.fail_index = std.math.maxInt(usize);
    try capture.putSlice("Gdata");
    const before = capture.payload().len;
    failing.fail_index = failing.alloc_index;
    const bytes: [4096]u8 = @splat('x');
    try std.testing.expectError(error.OutOfMemory, capture.putSlice(&bytes));
    try std.testing.expectEqual(before, capture.payload().len);
    capture.reset();
    capture.start(.apc);
    failing.fail_index = std.math.maxInt(usize);
    try capture.putSlice("Gok");
    try std.testing.expectEqualStrings("Gok", capture.payload());
}

test "discarded reserved DCS payload consumes no allocation and leaves ordinary capture reusable" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var capture = DcsCapture.init(failing.allocator());
    defer capture.deinit();
    const hook: parser.DcsHook = .{
        .final = 's',
        .params = &.{1},
        .count = 1,
        .intermediates = "=",
        .intermediates_len = 1,
    };
    try capture.start(hook, .discard);
    const before = failing.alloc_index;
    const prefix_len = capture.bytes.items.len;
    failing.fail_index = before;
    for (0..8192) |_| try capture.put('x');
    try std.testing.expectEqual(before, failing.alloc_index);
    try std.testing.expect(!failing.has_induced_failure);
    try std.testing.expectEqual(prefix_len, capture.bytes.items.len);
    try std.testing.expectEqualStrings("", capture.payload());
    try std.testing.expect(!capture.didOverflow());
    failing.fail_index = std.math.maxInt(usize);
    capture.reset();
    try capture.start(.{
        .final = 'p',
        .params = &.{},
        .count = 0,
        .intermediates = "+",
        .intermediates_len = 1,
    }, .retain);
    try capture.put('A');
    try std.testing.expectEqualStrings("A", capture.payload());
}

test "inline multipart capture owns the exact decoder-derived aggregate bound and frees failed transactions" {
    const allocator = std.testing.allocator;
    var state = try State.init(allocator);
    defer state.deinit();
    const chunk = try allocator.alloc(u8, 1024 * 1024);
    defer allocator.free(chunk);
    @memset(chunk, 'A');
    state.beginMultipart(allocator, .{});
    var remaining: usize = max_multipart_encoded_bytes;
    while (remaining != 0) {
        const count = @min(chunk.len, remaining);
        try state.appendMultipart(allocator, chunk[0..count]);
        remaining -= count;
        try std.testing.expect(state.multipart == .selected);
        try std.testing.expect(state.multipart.selected.encoded.capacity <= max_multipart_encoded_bytes);
    }
    try std.testing.expectEqual(max_multipart_encoded_bytes, state.multipart.selected.encoded.items.len);
    try std.testing.expectEqual(max_multipart_encoded_bytes, state.multipart.selected.encoded.capacity);
    try state.appendMultipart(allocator, "A");
    try std.testing.expect(state.multipart == .discard);
    state.beginMultipart(allocator, .{});
    try state.appendMultipart(allocator, "QQ=");
    try state.appendMultipart(allocator, "=");
    try std.testing.expectEqualStrings("QQ==", state.multipart.selected.encoded.items);
    try state.appendMultipart(allocator, "A");
    try std.testing.expect(state.multipart == .discard);
    state.beginMultipart(allocator, .{});
    try state.appendMultipart(allocator, "QQ==");
    // Teardown must release a still-open transaction too.
}
