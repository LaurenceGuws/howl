//! Native logical-output ownership and canonical-result projection proofs.
const std = @import("std");
const native = @import("howl_vt_native");
const vt = native.owner;
const output = native.logical_output;
const c = native.c;

fn create(rows: u16, columns: u16, history: u16) !*vt.Owner {
    return vt.create(std.testing.allocator, &.{ .rows = rows, .columns = columns, .history_rows = history, .reserved = 0, .cell_width = 8, .cell_height = 16 });
}
fn feed(value: *vt.Owner, bytes: []const u8) !void {
    var at: usize = 0;
    while (at < bytes.len) {
        const progress = try vt.feed(value, bytes[at..@min(bytes.len, at + c.HVT_MAX_INPUT_BYTES)], 17);
        try std.testing.expect(progress.consumed > 0);
        at += progress.consumed;
    }
}
fn spanBytes(pointer: [*c]const u8, count: usize) []const u8 {
    return if (count == 0) "" else pointer[0..count];
}
fn snapshot(value: *const vt.Owner, cursor: u64, entries: u16, budget: usize) !*output.Owner {
    return output.create(std.testing.allocator, vt.observation(value), cursor, entries, budget);
}
fn compare(value: *const vt.Owner, cursor: u64, entries: u16, budget: usize) !c.hvt_output_view {
    const before = vt.observe(value, 0);
    const result = try snapshot(value, cursor, entries, budget);
    defer output.destroy(result);
    const actual = output.read(result);
    const canonical = try vt.observation(value).copyLogicalOutput(std.testing.allocator, cursor, entries, budget);
    switch (canonical) {
        .output => |owned| {
            var expected = owned;
            defer expected.deinit();
            try std.testing.expectEqual(@as(u8, c.HVT_OUTPUT_DATA), actual.kind);
            try std.testing.expectEqualSlices(u8, expected.text, spanBytes(actual.text, actual.text_len));
            try std.testing.expectEqualSlices(u8, expected.open_line, spanBytes(actual.open_line, actual.open_line_len));
            try std.testing.expectEqual(expected.losses.len, actual.loss_count);
            try std.testing.expectEqual(expected.semantic_sequence, actual.terminal_revision);
            try std.testing.expectEqual(expected.oldest, actual.oldest);
            try std.testing.expectEqual(expected.cursor, actual.cursor);
            try std.testing.expectEqual(expected.newest, actual.newest);
            try std.testing.expectEqual(expected.line_count, actual.line_count);
            try std.testing.expectEqual(@intFromBool(expected.more), actual.more);
            try std.testing.expectEqual(@intFromBool(expected.open_line_omitted), actual.open_line_omitted);
            try std.testing.expectEqual(@as(u64, 0), actual.reported_id);
            for (expected.losses, 0..) |loss, index| {
                const copied = actual.losses[index];
                try std.testing.expectEqual(loss.id, copied.id);
                try std.testing.expectEqual(loss.byte_count, copied.byte_count);
                try std.testing.expectEqual(@as(u8, switch (loss.reason) {
                    .line_too_long => c.HVT_OUTPUT_LOSS_LINE_TOO_LONG,
                }), copied.reason);
                try std.testing.expect(std.mem.allEqual(u8, &copied.reserved, 0));
            }
            try std.testing.expect((actual.text_len == 0) == (actual.text == null));
            try std.testing.expect((actual.open_line_len == 0) == (actual.open_line == null));
            try std.testing.expect((actual.loss_count == 0) == (actual.losses == null));
            try std.testing.expect(std.mem.allEqual(u8, &actual.reserved, 0));
        },
        .cursor_stale => |id| try emptyOutcome(actual, c.HVT_OUTPUT_CURSOR_STALE, id),
        .cursor_ahead => |id| try emptyOutcome(actual, c.HVT_OUTPUT_CURSOR_AHEAD, id),
        .line_too_long => |id| try emptyOutcome(actual, c.HVT_OUTPUT_LINE_TOO_LONG, id),
        .open_line_too_long => try emptyOutcome(actual, c.HVT_OUTPUT_OPEN_LINE_TOO_LONG, 0),
    }
    try std.testing.expectEqualDeep(before, vt.observe(value, 0));
    // Only scalar fields from this local copy are returned; test callers never
    // dereference its spans after the owner has been released.
    return actual;
}
fn emptyOutcome(actual: c.hvt_output_view, kind: u8, id: u64) !void {
    var expected = std.mem.zeroes(c.hvt_output_view);
    expected.kind = kind;
    expected.reported_id = id;
    try std.testing.expectEqualDeep(expected, actual);
}

test "logical snapshots preserve canonical Unicode resize primary alternate and source-independent lifetime" {
    var retained: ?*output.Owner = null;
    defer if (retained) |value| output.destroy(value);
    {
        const value = try create(3, 8, 8);
        defer vt.destroy(value);
        const grapheme = "e\u{0301}\u{0302}\u{0303}\u{0304}\u{0305}\u{0306}\u{0307}\u{0308}";
        try feed(value, grapheme ++ "\r\nsecond\r\nopen");
        retained = try snapshot(value, 0, 8, 256);
        const first = output.read(retained.?);
        try std.testing.expectEqualSlices(u8, grapheme ++ "\nsecond", spanBytes(first.text, first.text_len));
        try std.testing.expectEqualSlices(u8, "open", spanBytes(first.open_line, first.open_line_len));
        // zig-audit: acknowledge discard
        // reason: This equivalence helper asserts every canonical output field, span and source revision.
        _ = try compare(value, 0, 8, 256);
        try vt.resize(value, 4, 4, 0, 0);
        const resized = try snapshot(value, 0, 8, 256);
        defer output.destroy(resized);
        const resized_view = output.read(resized);
        try std.testing.expectEqualSlices(u8, spanBytes(first.text, first.text_len), spanBytes(resized_view.text, resized_view.text_len));
        try std.testing.expectEqual(first.cursor, resized_view.cursor);
        try feed(value, "\x1b[?1049halt-a\r\nalt-b\r\nalt-c");
        const alternate = try snapshot(value, 0, 8, 256);
        defer output.destroy(alternate);
        const alternate_view = output.read(alternate);
        try std.testing.expect(vt.observe(value, 0).alternate_screen == 1);
        try std.testing.expectEqualSlices(u8, spanBytes(first.text, first.text_len), spanBytes(alternate_view.text, alternate_view.text_len));
        try std.testing.expectEqualSlices(u8, "open", spanBytes(alternate_view.open_line, alternate_view.open_line_len));
        // zig-audit: acknowledge discard
        // reason: Verify the same primary-output cut while alternate is actively selected.
        _ = try compare(value, 0, 8, 256);
        try feed(value, "\x1b[?1049l-new");
        try std.testing.expectEqualSlices(u8, "open", spanBytes(output.read(retained.?).open_line, first.open_line_len));
    }
    const after = output.read(retained.?);
    try std.testing.expectEqualSlices(u8, "open", spanBytes(after.open_line, after.open_line_len));
    try std.testing.expect(after.line_count == 2 and after.cursor == 2 and after.loss_count == 0);
}

test "logical result kinds preserve exact cursor and byte budget outcomes" {
    const value = try create(2, 8, 3);
    defer vt.destroy(value);
    const empty = try compare(value, 0, 1, 1);
    try std.testing.expect(empty.kind == c.HVT_OUTPUT_DATA and empty.text_len == 0 and empty.open_line_len == 0 and empty.oldest == 1 and empty.newest == 0);
    try feed(value, "one\r\ntwo\r\nopen");
    const limited = try compare(value, 0, 1, 64);
    try std.testing.expect(limited.kind == c.HVT_OUTPUT_DATA and limited.cursor == 1 and limited.line_count == 1 and limited.more == 1);
    const byte_limited = try compare(value, 0, 4, 3);
    try std.testing.expect(byte_limited.kind == c.HVT_OUTPUT_DATA and byte_limited.cursor == 1 and byte_limited.more == 1 and byte_limited.open_line_omitted == 1);
    try emptyOutcome(try compare(value, 0, 4, 2), c.HVT_OUTPUT_LINE_TOO_LONG, 1);
    try emptyOutcome(try compare(value, 2, 4, 3), c.HVT_OUTPUT_OPEN_LINE_TOO_LONG, 0);
    try emptyOutcome(try compare(value, 999, 4, 64), c.HVT_OUTPUT_CURSOR_AHEAD, 2);
    const open_only = try compare(value, 2, 4, 4);
    try std.testing.expect(open_only.kind == c.HVT_OUTPUT_DATA and open_only.text_len == 0 and open_only.open_line_len == 4 and open_only.more == 0 and open_only.open_line_omitted == 0);
    try feed(value, "\r\nfour\r\nfive\r\nsix");
    const oldest = vt.observation(value).logicalOutputRange().oldest;
    try std.testing.expect(oldest > 1);
    try emptyOutcome(try compare(value, 0, 4, 64), c.HVT_OUTPUT_CURSOR_STALE, oldest);
}

fn appendOversizedLine(value: *vt.Owner) !usize {
    const chunk: [c.HVT_MAX_INPUT_BYTES]u8 = @splat('x');
    const count = c.HVT_MAX_COPY_BYTES / chunk.len + 1;
    for (0..count) |_| try feed(value, &chunk);
    return count * chunk.len;
}

test "logical losses count as entries preserve evidence and partition current open bytes" {
    const value = try create(2, std.math.maxInt(u16), 32);
    defer vt.destroy(value);
    const lost_bytes = try appendOversizedLine(value);
    try emptyOutcome(try compare(value, 0, 1, c.HVT_MAX_COPY_BYTES), c.HVT_OUTPUT_OPEN_LINE_TOO_LONG, 0);
    try feed(value, "\r\nok\r\nnext");
    const result = try snapshot(value, 0, 3, c.HVT_MAX_COPY_BYTES);
    defer output.destroy(result);
    const actual = output.read(result);
    try std.testing.expect(actual.kind == c.HVT_OUTPUT_DATA and actual.cursor == 2 and actual.line_count == 1 and actual.loss_count == 1);
    try std.testing.expectEqualSlices(u8, "ok", spanBytes(actual.text, actual.text_len));
    try std.testing.expectEqualSlices(u8, "next", spanBytes(actual.open_line, actual.open_line_len));
    try std.testing.expect(actual.losses[0].id == 1 and actual.losses[0].byte_count == lost_bytes and actual.losses[0].reason == c.HVT_OUTPUT_LOSS_LINE_TOO_LONG);
    // zig-audit: acknowledge discard
    // reason: Compare every successful loss/data field against the canonical result.
    _ = try compare(value, 0, 3, c.HVT_MAX_COPY_BYTES);
    const one = try compare(value, 0, 1, 64);
    try std.testing.expect(one.line_count == 0 and one.cursor == 1 and one.loss_count == 1 and one.more == 1);
    const short_open = try compare(value, 0, 3, 3);
    try std.testing.expect(short_open.line_count == 1 and short_open.open_line_omitted == 1 and short_open.open_line_len == 0);
}

fn allocationCampaign(allocator: std.mem.Allocator, value: *const vt.Owner, expected_losses: usize) !void {
    const before = vt.observe(value, 0);
    const result = output.create(allocator, vt.observation(value), 0, 64, 256) catch |err| {
        try std.testing.expectEqualDeep(before, vt.observe(value, 0));
        return err;
    };
    defer output.destroy(result);
    const actual = output.read(result);
    try std.testing.expect(actual.kind == c.HVT_OUTPUT_DATA and actual.loss_count == expected_losses);
    try std.testing.expectEqualSlices(u8, "ok", spanBytes(actual.text, actual.text_len));
    try std.testing.expectEqualSlices(u8, "next", spanBytes(actual.open_line, actual.open_line_len));
    for (0..actual.loss_count) |index| {
        const entry = actual.losses[index];
        try std.testing.expectEqual(index + 1, entry.id);
        try std.testing.expectEqual(@as(u64, (c.HVT_MAX_COPY_BYTES / c.HVT_MAX_INPUT_BYTES + 1) * c.HVT_MAX_INPUT_BYTES), entry.byte_count);
        try std.testing.expectEqual(@as(u8, c.HVT_OUTPUT_LOSS_LINE_TOO_LONG), entry.reason);
        try std.testing.expect(std.mem.allEqual(u8, &entry.reserved, 0));
    }
    try std.testing.expect(actual.line_count == 1 and actual.cursor == expected_losses + 1);
    try std.testing.expectEqualDeep(before, vt.observe(value, 0));
}
test "logical construction unwinds every allocation including growing canonical and native loss arrays" {
    const value = try create(2, std.math.maxInt(u16), 64);
    defer vt.destroy(value);
    for (0..9) |_| {
        // zig-audit: acknowledge discard
        // reason: Each oversized real line must become one retained canonical loss before the conversion failure campaign.
        _ = try appendOversizedLine(value);
        try feed(value, "\r\n");
    }
    try feed(value, "ok\r\nnext");
    // Number every growth independently of backing resize/remap success.
    var allocation_only = std.testing.FailingAllocator.init(std.testing.allocator, .{ .resize_fail_index = 0 });
    try std.testing.checkAllAllocationFailures(allocation_only.allocator(), allocationCampaign, .{ value, @as(usize, 9) });
}

test "logical invalid limits reject before allocation and preserve source" {
    const value = try create(2, 8, 4);
    defer vt.destroy(value);
    var fail = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    const observed = vt.observation(value);
    const before = vt.observe(value, 0);
    try std.testing.expectError(error.InvalidArgument, output.create(fail.allocator(), observed, 0, 0, 1));
    try std.testing.expectError(error.InvalidArgument, output.create(fail.allocator(), observed, 0, 1, 0));
    try std.testing.expectError(error.InvalidArgument, output.create(fail.allocator(), observed, 0, 1, c.HVT_MAX_COPY_BYTES + 1));
    try std.testing.expectError(error.OutOfMemory, output.create(fail.allocator(), observed, 0, 1, 1));
    try std.testing.expectEqualDeep(before, vt.observe(value, 0));
}
