//! Proves optional encoding against the public live VT and codec roots.
const std = @import("std");
const vt = @import("howl_vt");
const codec = @import("howl_vt_codec");
const Encoder = codec.encoder.Encoder(vt.Terminal.Observation);

fn fixture(allocator: std.mem.Allocator) !vt.Terminal {
    var terminal = try vt.Terminal.init(allocator, 2, 8);
    errdefer terminal.deinit();
    try std.testing.expect((try terminal.feed("\x1b]2;copybook\x07\x1b[31m\x1b]8;;https://example.invalid/\x07A\xcc\x81\x1b]8;;\x07B")).stateChanged());
    return terminal;
}

test "optional encoder preserves VT facts and never advances canonical state" {
    var terminal = try fixture(std.testing.allocator);
    defer terminal.deinit();
    const sequence = terminal.semanticSequence();
    const semantic = terminal.observation().semanticView(0);
    const metadata = Encoder.metadata(semantic, sequence);
    try std.testing.expectEqual(sequence, metadata.revision);
    try std.testing.expectEqual(semantic.rows, metadata.rows);
    try std.testing.expectEqual(semantic.cols, metadata.columns);
    try std.testing.expectEqual(semantic.cursor_row, metadata.cursor_row);
    try std.testing.expectEqual(semantic.cursor_col, metadata.cursor_column);
    try std.testing.expectEqual(semantic.history_count, metadata.history_count);
    try std.testing.expectEqual(semantic.history_row_base, metadata.history_row_base);
    try std.testing.expectEqual(semantic.cursor_visible, metadata.cursor_visible);
    try std.testing.expectEqual(semantic.cursor_blink, metadata.cursor_blink);
    try std.testing.expectEqual(semantic.is_alternate_screen, metadata.alternate_screen);
    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(std.testing.allocator);
    const geometry = try Encoder.appendText(std.testing.allocator, &body, terminal.observation(), 0, 42);
    try std.testing.expectEqual(sequence, terminal.semanticSequence());
    var text = try codec.text.decode(std.testing.allocator, geometry, .raw, body.items);
    defer text.deinit();
    try std.testing.expectEqual(@as(?u64, 42), text.presentation.cursor_age_ns);
    try std.testing.expectEqualSlices(u32, &.{ 'A', 0x0301 }, text.rows[0].cells[0].scalars);
    try std.testing.expectEqual(codec.TextColorKind.indexed, text.rows[0].cells[0].foreground.kind);
    try std.testing.expectEqual(@as(u32, 1), text.rows[0].cells[0].foreground.value);
    try std.testing.expectEqual(@as(usize, 1), text.hyperlinks.len);
    try std.testing.expectEqualStrings("https://example.invalid/", text.hyperlinks[0].uri_bytes);
    try std.testing.expectEqual(@as(u32, 'B'), text.rows[0].cells[1].scalars[0]);
    try std.testing.expectEqual(@as(u32, 0), text.rows[0].cells[1].link_id);
    const properties = Encoder.properties(terminal.observation());
    var packet: [codec.properties.maximum_bytes]u8 = undefined;
    const size = try codec.properties.encode(&packet, properties);
    const decoded = try codec.properties.decode(packet[0..size]);
    try std.testing.expectEqualStrings("copybook", decoded.title.?);
}

fn testEncodeAllocation(allocator: std.mem.Allocator, observation: *const vt.Terminal.Observation) !void {
    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(allocator);
    try body.appendSlice(allocator, "prefix");
    const sequence = observation.semanticSequence();
    const geometry = Encoder.appendText(allocator, &body, observation, 0, 42) catch |err| {
        try std.testing.expectEqualStrings("prefix", body.items);
        try std.testing.expectEqual(sequence, observation.semanticSequence());
        return err;
    };
    try std.testing.expect(body.items.len > "prefix".len);
    try std.testing.expectEqual(@as(u16, 2), geometry.rows);
    try std.testing.expectEqual(@as(u16, 8), geometry.columns);
    try std.testing.expectEqual(sequence, observation.semanticSequence());
}

fn testRowAllocation(allocator: std.mem.Allocator, observation: *const vt.Terminal.Observation) !void {
    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(allocator);
    try body.appendSlice(allocator, "prefix");
    var links: codec.encoder.Links = @splat(0);
    try codec.encoder.noteLink(4096, &links);
    const before = links;
    Encoder.appendRow(allocator, &body, observation.semanticView(0), 0, &links) catch |err| {
        try std.testing.expectEqualStrings("prefix", body.items);
        try std.testing.expectEqualSlices(u64, &before, &links);
        return err;
    };
    try std.testing.expect(links[0] != before[0]);
}

test "encoding allocation failures restore prefixes and row link membership" {
    var terminal = try fixture(std.testing.allocator);
    defer terminal.deinit();
    try std.testing.checkAllAllocationFailures(std.testing.allocator, testEncodeAllocation, .{terminal.observation()});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, testRowAllocation, .{terminal.observation()});
}

test "optional encoder retains the complete 24-scalar VT cluster" {
    var terminal = try vt.Terminal.init(std.testing.allocator, 1, 2);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("e")).stateChanged());
    for (0..vt.scalar.maximum_scalars - 1) |_| try std.testing.expect((try terminal.feed("\xcc\x81")).stateChanged());
    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(std.testing.allocator);
    const geometry = try Encoder.appendText(std.testing.allocator, &body, terminal.observation(), 0, 0);
    var text = try codec.text.decode(std.testing.allocator, geometry, .raw, body.items);
    defer text.deinit();
    try std.testing.expectEqual(vt.scalar.maximum_scalars, text.rows[0].cells[0].scalars.len);
    try std.testing.expectEqual(@as(u32, 'e'), text.rows[0].cells[0].scalars[0]);
    for (text.rows[0].cells[0].scalars[1..]) |scalar| try std.testing.expectEqual(@as(u32, 0x0301), scalar);
    var cache = codec.cache.Cache.init(std.testing.allocator);
    defer cache.deinit();
    const cached = try cache.decode(geometry, .full, body.items);
    const metadata = Encoder.metadata(terminal.observation().semanticView(0), terminal.semanticSequence());
    const owned = try codec.view.project(std.testing.allocator, &.{
        .metadata = &metadata,
        .presentation = &cached.presentation,
        .rows = cached.rows,
        .hyperlinks = cached.hyperlinks,
        .changed_rows = cached.changed_rows,
        .row_shift = cached.row_shift,
    });
    defer codec.view.deinit(owned);
    const scalars = cached.rows[0].cells[0].scalars;
    try std.testing.expectEqualSlices(u32, text.rows[0].cells[0].scalars, scalars);
    var delta: std.ArrayList(u8) = .empty;
    defer delta.deinit(std.testing.allocator);
    try delta.appendSlice(std.testing.allocator, body.items[0 .. codec.text_v1.record_header_bytes + codec.text_v1.presentation_bytes]);
    try codec.encoder.appendRowShift(std.testing.allocator, &delta, 0);
    try codec.encoder.appendRowReuse(std.testing.allocator, &delta);
    const reused = try cache.decode(geometry, .delta, delta.items);
    try std.testing.expectEqual(scalars.ptr, reused.rows[0].cells[0].scalars.ptr);
    try std.testing.expectEqualSlices(u32, scalars, reused.rows[0].cells[0].scalars);
    try std.testing.expectEqualSlices(bool, &.{false}, reused.changed_rows);
    cache.invalidate();
    try std.testing.expectEqual(metadata.revision, codec.view.metadata(owned).revision);
    try std.testing.expectEqual(vt.scalar.maximum_scalars, codec.view.scalars(owned).len);
    try std.testing.expectEqual(@as(u32, 'e'), codec.view.scalars(owned)[0]);
    for (codec.view.scalars(owned)[1..]) |scalar| try std.testing.expectEqual(@as(u32, 0x0301), scalar);
    try std.testing.expectEqualSlices(bool, &.{true}, codec.view.changedRows(owned).?);
}

test "optional encoder bounds output without changing its caller's prefix" {
    var terminal = try fixture(std.testing.allocator);
    defer terminal.deinit();
    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(std.testing.allocator);
    try body.appendNTimes(std.testing.allocator, 0x5a, codec.maximum_text_snapshot_bytes);
    try std.testing.expectError(error.SnapshotTooLarge, Encoder.appendText(
        std.testing.allocator,
        &body,
        terminal.observation(),
        0,
        0,
    ));
    try std.testing.expectEqual(codec.maximum_text_snapshot_bytes, body.items.len);
    for (body.items) |byte| try std.testing.expectEqual(@as(u8, 0x5a), byte);
    body.clearRetainingCapacity();
    var links: codec.encoder.Links = @splat(0);
    try std.testing.expectError(error.InvalidSnapshot, Encoder.appendRow(
        std.testing.allocator,
        &body,
        terminal.observation().semanticView(0),
        2,
        &links,
    ));
    try std.testing.expectEqual(@as(usize, 0), body.items.len);
}

test "optional encoder exports a graphics manifest independently of delivery" {
    var terminal = try fixture(std.testing.allocator);
    defer terminal.deinit();
    var images = terminal.observation().images(0);
    try std.testing.expectError(error.InvalidSnapshot, Encoder.countGraphics(&images));
    var missing: [codec.graphics_v2.manifest_header_bytes]u8 = undefined;
    try std.testing.expectError(error.InvalidSnapshot, Encoder.encodeGraphics(
        &images,
        .{ .images = 0, .placements = 0, .payload_bytes = missing.len },
        &missing,
    ));
    try terminal.setCellPixelSize(10, 20);
    images = terminal.observation().images(0);
    const counts = try Encoder.countGraphics(&images);
    const packet = try std.testing.allocator.alloc(u8, counts.payload_bytes);
    defer std.testing.allocator.free(packet);
    var wrong = counts;
    wrong.images = 1;
    try std.testing.expectError(error.InvalidSnapshot, Encoder.encodeGraphics(&images, wrong, packet));
    try Encoder.encodeGraphics(&images, counts, packet);
    var graphics = try codec.decoded.decodeGraphics(
        std.testing.allocator,
        .{ .rows = 2, .columns = 8 },
        packet,
    );
    defer graphics.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), graphics.images.len);
    try std.testing.expectEqual(@as(usize, 0), graphics.placements.len);
}
