//! Public native owner proofs, including injected allocation failures.
const std = @import("std");
const native = @import("howl_vt_native");
const owner = native.owner;
const c = native.c;

fn create(allocator: std.mem.Allocator) !*owner.Owner {
    const config = c.hvt_config{ .rows = 2, .columns = 8, .history_rows = 4, .reserved = 0, .cell_width = 8, .cell_height = 16 };
    return owner.create(allocator, &config);
}
fn feedAll(value: *owner.Owner, bytes: []const u8) !void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        const progress = try owner.feed(value, bytes[offset..], 17);
        try std.testing.expect(progress.consumed > 0 and progress.consumed <= bytes.len - offset);
        offset += progress.consumed;
    }
}
fn pending(value: *const owner.Owner) !usize {
    var required: usize = 0;
    owner.copyReplies(value, &.{}, &required) catch |err| switch (err) {
        error.BufferTooSmall => {},
        else => return err,
    };
    return required;
}

test "opaque native owner constructor unwinds every allocation prefix" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, construction, .{});
}
fn construction(allocator: std.mem.Allocator) !void {
    const value = try create(allocator);
    defer owner.destroy(value);
    const observed = owner.observe(value, 0);
    try std.testing.expect(observed.rows == 2 and observed.columns == 8 and observed.cell_width == 8 and observed.cell_height == 16);
    const Pointer = @typeInfo(@TypeOf(owner.observation(value))).pointer;
    try std.testing.expect(Pointer.attrs.@"const" and @typeInfo(Pointer.child) == .@"opaque");
}

test "native owner rejects malformed geometry and topology ceilings before allocation" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var config = std.mem.zeroes(c.hvt_config);
    try std.testing.expectError(error.InvalidArgument, owner.create(failing.allocator(), &config));
    config.rows = 2;
    config.columns = 8;
    config.reserved = 1;
    try std.testing.expectError(error.InvalidArgument, owner.create(failing.allocator(), &config));
    config.reserved = 0;
    config.cell_height = 16;
    try std.testing.expectError(error.InvalidArgument, owner.create(failing.allocator(), &config));
    config.cell_width = 8;
    config.rows = 1024;
    config.columns = 1024;
    try std.testing.expectError(error.OutOfMemory, owner.create(failing.allocator(), &config));
    config.rows = 1025;
    try std.testing.expectError(error.ResourceLimit, owner.create(failing.allocator(), &config));
    config.rows = 65535;
    config.columns = 65535;
    try std.testing.expectError(error.ResourceLimit, owner.create(failing.allocator(), &config));
    config.rows = 2;
    config.columns = 8;
    config.history_rows = 65535;
    try std.testing.expectError(error.OutOfMemory, owner.create(failing.allocator(), &config));
}

test "native geometry transaction preserves state at every failed allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, geometryCampaign, .{});
}
fn geometryCampaign(allocator: std.mem.Allocator) !void {
    const value = try create(allocator);
    defer owner.destroy(value);
    try feedAll(value, "A\x07\x1b[?2048h");
    const before = owner.observe(value, 0);
    const reply_count = try pending(value);
    const head = owner.observation(value).consequenceHead().?.id();
    owner.resize(value, 3, 10, 12, 24) catch |err| {
        try std.testing.expectEqualDeep(before, owner.observe(value, 0));
        try std.testing.expectEqual(reply_count, try pending(value));
        try std.testing.expectEqual(head, owner.observation(value).consequenceHead().?.id());
        try std.testing.expectEqual(@as(u21, 'A'), owner.observation(value).semanticView(0).cellAt(0, 0));
        return err;
    };
    const changed = owner.observe(value, 0);
    try std.testing.expect(changed.rows == 3 and changed.columns == 10 and changed.cell_width == 12 and changed.cell_height == 24);
    try std.testing.expect(changed.terminal_revision == before.terminal_revision + 1);
}

test "native resize preserves pixels on zero pair and commits pixel-only identity" {
    const value = try create(std.testing.allocator);
    defer owner.destroy(value);
    const before = owner.observe(value, 0);
    try owner.resize(value, 2, 8, 12, 24);
    const pixels = owner.observe(value, 0);
    try std.testing.expect(pixels.rows == 2 and pixels.columns == 8 and pixels.cell_width == 12 and pixels.cell_height == 24);
    try std.testing.expectEqual(before.terminal_revision + 1, pixels.terminal_revision);
    try owner.resize(value, 3, 10, 0, 0);
    const preserved = owner.observe(value, 0);
    try std.testing.expect(preserved.cell_width == 12 and preserved.cell_height == 24);
    try std.testing.expectError(error.InvalidArgument, owner.resize(value, 3, 10, 0, 24));
    try std.testing.expectEqualDeep(preserved, owner.observe(value, 0));
}

test "native feed allocation prefixes remain observable resettable and destroyable" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, feedCampaign, .{});
}
fn feedCampaign(allocator: std.mem.Allocator) !void {
    const value = try create(allocator);
    defer owner.destroy(value);
    feedAll(value, "A\x1b]0;native allocated title\x07\x1b]52;c;?\x07") catch |err| {
        const before_reset = owner.observe(value, 0);
        owner.reset(value);
        const after_reset = owner.observe(value, 0);
        try std.testing.expectEqual(before_reset.terminal_revision + 1, after_reset.terminal_revision);
        return err;
    };
    try std.testing.expectEqual(@as(u21, 'A'), owner.observation(value).semanticView(0).cellAt(0, 0));
}

test "native feed success yields exact reply and synchronized boundaries" {
    const value = try create(std.testing.allocator);
    defer owner.destroy(value);
    const bytes = "A\x1b[5nTAIL";
    const first = try owner.feed(value, bytes, 17);
    try std.testing.expect(first.consumed == 5 and first.mutations & c.HVT_MUTATION_TEXT != 0);
    try std.testing.expectEqual(@as(usize, 4), try pending(value));
    try feedAll(value, bytes[first.consumed..]);
    const held = try owner.feed(value, "\x1b[?2026hX", 18);
    try std.testing.expect(held.held == 1);
    const released = try owner.feed(value, "\x1b[?2026lY", 19);
    try std.testing.expect(released.synchronized_ended == 1 and released.held == 0 and released.consumed == 8);
    try feedAll(value, "\x1b[?2026lY"[released.consumed..]);
    const empty = try owner.feed(value, "", 20);
    try std.testing.expect(empty.consumed == 0);
}

test "native feed partial error preserves applied prefix and permits explicit work service" {
    const value = try create(std.testing.allocator);
    defer owner.destroy(value);
    var filled: u16 = 0;
    while (filled < 1024) : (filled += 1) {
        // zig-audit: acknowledge discard
        // reason: The pressure proof counts retained bells and checks the failed marked prefix separately.
        _ = owner.feed(value, "\x07", 1) catch |err| switch (err) {
            error.ConsequencePressure => break,
            else => return err,
        };
    }
    try std.testing.expect(filled > 0 and filled < 1024);
    const before = owner.observe(value, 0);
    try std.testing.expectError(error.ConsequencePressure, owner.feed(value, "Z\x07", 2));
    try std.testing.expect(owner.observe(value, 0).terminal_revision > before.terminal_revision);
    try std.testing.expectEqual(@as(u21, 'Z'), owner.observation(value).semanticView(0).cellAt(0, 0));
    owner.reset(value);
    try std.testing.expectEqual(filled, owner.observation(value).consequenceCount());
    while (owner.observation(value).consequenceHead()) |head| try owner.consumeRequest(value, head.id());
    try feedAll(value, "R");
    try std.testing.expectEqual(@as(u21, 'R'), owner.observation(value).semanticView(0).cellAt(0, 0));
}

test "native pasted output unwinds every bracketed allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, pasteCampaign, .{});
}
fn pasteCampaign(allocator: std.mem.Allocator) !void {
    const value = try create(allocator);
    defer owner.destroy(value);
    try feedAll(value, "\x1b[?2004h");
    var bytes: [32]u8 = @splat(0xa5);
    const written = owner.encode(value, .{ .paste = "paste" }, &bytes) catch |err| {
        try std.testing.expect(std.mem.allEqual(u8, &bytes, 0xa5));
        return err;
    };
    try std.testing.expectEqualSlices(u8, "\x1b[200~paste\x1b[201~", bytes[0..written]);
    try std.testing.expect(bytes[written] == 0xa5);
}

test "native plain paste and ordinary keys need no allocator after construction" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const value = try create(failing.allocator());
    defer owner.destroy(value);
    failing.fail_index = failing.alloc_index;
    var output_bytes: [c.HVT_INPUT_BUFFER_BYTES + 1]u8 = @splat(0xa5);
    const plain = try owner.encode(value, .{ .paste = "plain" }, &output_bytes);
    try std.testing.expectEqualSlices(u8, "plain", output_bytes[0..plain]);
    const key = try native.namedInput(c.HVT_KEY_UP, c.HVT_PRESS, 0);
    const count = try owner.encode(value, key, &output_bytes);
    try std.testing.expectEqualSlices(u8, "\x1b[A", output_bytes[0..count]);
    try std.testing.expect(output_bytes[c.HVT_INPUT_BUFFER_BYTES] == 0xa5);
}

test "native paste overlap rejects while adjacent and unused tail ranges remain valid" {
    const value = try create(std.testing.allocator);
    defer owner.destroy(value);
    var bytes: [64]u8 = @splat(0xa5);
    @memcpy(bytes[20..23], "abc");
    const count = try owner.encode(value, .{ .paste = bytes[20..23] }, &bytes);
    try std.testing.expectEqualSlices(u8, "abc", bytes[0..count]);
    try std.testing.expectError(error.InvalidArgument, owner.encode(value, .{ .paste = bytes[0..3] }, bytes[0..15]));
    @memcpy(bytes[15..18], "xyz");
    try std.testing.expectEqual(@as(usize, 3), try owner.encode(value, .{ .paste = bytes[15..18] }, bytes[0..15]));
    try std.testing.expectEqualSlices(u8, "xyz", bytes[0..3]);
    var short: [14]u8 = @splat(0xa5);
    try std.testing.expectError(error.BufferTooSmall, owner.encode(value, .{ .paste = "abc" }, &short));
    try std.testing.expect(std.mem.allEqual(u8, &short, 0xa5));
}

test "native mouse mask and capacity admission precede stateful locator effects" {
    const value = try create(std.testing.allocator);
    defer owner.destroy(value);
    try feedAll(value, "\x1b[1;0'z\x1b[1;1;1;1'w");
    const event = try native.mouseInput(c.HVT_MOUSE_PRESS, c.HVT_BUTTON_LEFT, 0, 1, 2, 3, 0, 0xffffffff, 0xffffffff);
    var bytes: [c.HVT_INPUT_BUFFER_BYTES]u8 = @splat(0xa5);
    const before = owner.observe(value, 0);
    try std.testing.expectError(error.BufferTooSmall, owner.encode(value, event, bytes[0 .. bytes.len - 1]));
    try std.testing.expectEqualDeep(before, owner.observe(value, 0));
    try std.testing.expectEqual(@as(usize, 0), try pending(value));
    try std.testing.expect(std.mem.allEqual(u8, &bytes, 0xa5));
    for (0..256) |mask| {
        const bits: u8 = @intCast(mask);
        if (mask > 7) try std.testing.expectError(error.InvalidArgument, native.mouseInput(c.HVT_MOUSE_PRESS, c.HVT_BUTTON_LEFT, 0xff, bits, 2, 3, 0, 0xffffffff, 0xffffffff)) else {
            const valid = try native.mouseInput(c.HVT_MOUSE_PRESS, c.HVT_BUTTON_LEFT, 0xff, bits, 2, 3, 0, 0xffffffff, 0xffffffff);
            try std.testing.expect(valid.mouse.pixel_x == null and valid.mouse.pixel_y == null);
        }
    }
    // zig-audit: acknowledge discard
    // reason: Locator-only reporting legitimately returns zero ordinary mouse bytes; the proof checks its queued canonical report.
    _ = try owner.encode(value, event, &bytes);
    var required: usize = 0;
    try owner.copyReplies(value, &bytes, &required);
    try std.testing.expectEqualSlices(u8, "\x1b[10;4;3;4;0&w", bytes[0..required]);
}

test "native search and copied selection unwind all temporary allocation prefixes" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, queryCampaign, .{});
}
fn queryCampaign(allocator: std.mem.Allocator) !void {
    const value = try create(allocator);
    defer owner.destroy(value);
    try feedAll(value, "foo bar");
    var match: c.hvt_search_match = undefined;
    try owner.search(value, "bar", false, false, 0, 0, &match);
    try std.testing.expect(match.found == 1 and match.start_column == 4);
    var bytes: [16]u8 = @splat(0xa5);
    const count = try owner.copySelection(value, 0, 0, 0, 6, 8, false, &bytes);
    try std.testing.expectEqualSlices(u8, "foo bar", bytes[0..count]);
    try std.testing.expect(bytes[count] == 0xa5);
}

const Reply = enum { clipboard, pointer, color, container };
test "native typed replies preserve exact head at every allocation prefix" {
    inline for (.{ Reply.clipboard, Reply.pointer, Reply.color, Reply.container }) |kind|
        try std.testing.checkAllAllocationFailures(std.testing.allocator, replyCampaign, .{kind});
}
fn replyCampaign(allocator: std.mem.Allocator, kind: Reply) !void {
    const value = try create(allocator);
    defer owner.destroy(value);
    const query = switch (kind) {
        .clipboard => "\x1b]52;c;?\x07",
        .pointer => "\x1b]22;?default\x07",
        .color => "\x1b[?996n",
        .container => "\x1b[19t",
    };
    try feedAll(value, query);
    const id = owner.observation(value).consequenceHead().?.id();
    const before = owner.observe(value, 0);
    const result = switch (kind) {
        .clipboard => owner.replyClipboard(value, id, "approved"),
        .pointer => owner.replyPointerShape(value, id, "default"),
        .color => owner.replyColorPreference(value, id, .dark),
        .container => owner.replyContainer(value, id, .{ .screen_cells = .{ .rows = 2, .cols = 8 } }),
    };
    result catch |err| {
        try std.testing.expectEqual(id, owner.observation(value).consequenceHead().?.id());
        try std.testing.expectEqualDeep(before, owner.observe(value, 0));
        try std.testing.expectEqual(@as(usize, 0), try pending(value));
        return err;
    };
    try std.testing.expect(owner.observation(value).consequenceHead() == null and try pending(value) != 0);
}

test "native reply saturation preserves request geometry and exact prefix consumption" {
    const value = try create(std.testing.allocator);
    defer owner.destroy(value);
    try feedAll(value, "\x1b[?2048h");
    try owner.consumeReplies(value, try pending(value));
    for (0..16384) |_| try feedAll(value, "\x1b[5n");
    try std.testing.expectEqual(@as(usize, 65536), try pending(value));
    try feedAll(value, "\x1b]52;c;?\x07");
    const head = owner.observation(value).consequenceHead().?.id();
    const before = owner.observe(value, 0);
    try std.testing.expectError(error.ReplyLimit, owner.replyClipboard(value, head, ""));
    try std.testing.expectEqual(head, owner.observation(value).consequenceHead().?.id());
    try std.testing.expectEqualDeep(before, owner.observe(value, 0));
    try std.testing.expectError(error.ReplyLimit, owner.resize(value, 3, 10, 12, 24));
    try std.testing.expectEqualDeep(before, owner.observe(value, 0));
    try std.testing.expectError(error.InvalidReplyCount, owner.consumeReplies(value, std.math.maxInt(usize)));
    try owner.consumeReplies(value, 0);
    try std.testing.expectEqualDeep(before, owner.observe(value, 0));
    try owner.consumeReplies(value, 7);
    try std.testing.expectEqual(@as(usize, 65529), try pending(value));
    try owner.consumeReplies(value, 65529);
    try owner.replyClipboard(value, head, "");
    try std.testing.expect(owner.observation(value).consequenceHead() == null);
}

const Response = enum { clipboard, pointer, color, container, decline };
fn namedReply(value: *owner.Owner, id: u64, response: Response) owner.Error!void {
    return switch (response) {
        .clipboard => owner.replyClipboard(value, id, "approved"),
        .pointer => owner.replyPointerShape(value, id, "default"),
        .color => owner.replyColorPreference(value, id, .dark),
        .container => owner.replyContainer(value, id, .{ .screen_cells = .{ .rows = 2, .cols = 8 } }),
        .decline => owner.declineContainer(value, id),
    };
}
test "native named replies distinguish exact wrong family from stale identity" {
    for ([_]Reply{ .clipboard, .pointer, .color, .container }) |kind| {
        const value = try create(std.testing.allocator);
        defer owner.destroy(value);
        const query = switch (kind) {
            .clipboard => "\x1b]52;c;?\x07",
            .pointer => "\x1b]22;?default\x07",
            .color => "\x1b[?996n",
            .container => "\x1b[19t",
        };
        try feedAll(value, "\x1b[5n");
        try feedAll(value, query);
        const head = owner.observation(value).consequenceHead().?;
        const before = owner.observe(value, 0);
        var payload: [64]u8 = undefined;
        var payload_len: usize = 0;
        try native.requests.copyPayload(owner.observation(value), head.id(), &payload, &payload_len);
        var replies: [64]u8 = undefined;
        var replies_len: usize = 0;
        try owner.copyReplies(value, &replies, &replies_len);
        for ([_]Response{ .pointer, .clipboard, .color, .container, .decline }) |response| {
            const same_family = switch (response) {
                .clipboard => kind == .clipboard,
                .pointer => kind == .pointer,
                .color => kind == .color,
                .container, .decline => kind == .container,
            };
            if (!same_family) {
                try std.testing.expectError(error.RequestMismatch, namedReply(value, head.id(), response));
                try unchangedReplyHead(value, head, before, payload[0..payload_len], replies[0..replies_len]);
            }
            try std.testing.expectError(error.StaleRequest, namedReply(value, head.id() + 1, response));
            try unchangedReplyHead(value, head, before, payload[0..payload_len], replies[0..replies_len]);
        }
        const correct: Response = switch (kind) {
            .clipboard => .clipboard,
            .pointer => .pointer,
            .color => .color,
            .container => .container,
        };
        try namedReply(value, head.id(), correct);
        try std.testing.expect(owner.observation(value).consequenceHead() == null);
        for ([_]Response{ .clipboard, .pointer, .color, .container, .decline }) |response|
            try std.testing.expectError(error.StaleRequest, namedReply(value, head.id(), response));
    }
}
fn unchangedReplyHead(value: *owner.Owner, head: native.Terminal.Consequence, before: c.hvt_state, payload: []const u8, replies: []const u8) !void {
    try std.testing.expectEqualDeep(head, owner.observation(value).consequenceHead().?);
    try std.testing.expectEqualDeep(before, owner.observe(value, 0));
    var bytes: [64]u8 = undefined;
    var required: usize = 0;
    try native.requests.copyPayload(owner.observation(value), head.id(), &bytes, &required);
    try std.testing.expectEqualSlices(u8, payload, bytes[0..required]);
    try owner.copyReplies(value, &bytes, &required);
    try std.testing.expectEqualSlices(u8, replies, bytes[0..required]);
}
