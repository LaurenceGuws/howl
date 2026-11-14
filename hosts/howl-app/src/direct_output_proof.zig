//! Migration proof: a local host can compose canonical VT, Text and a borrowed
//! direct-output owner without importing Instance or the legacy Renderer.
const std = @import("std");
const vt = @import("howl_vt");
const output = @import("howl_vt_output");
const Borrowed = @import("output_state").State(false);

test "one canonical VT serves borrowed direct output with an independently retained Text store" {
    const allocator = std.testing.allocator;
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const store = try output.initPresentationStore(allocator, threaded.io(), .{
        .regular = .{ .path = .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 12 } } },
    }, .{
        .shape_cache = .{ .entry_capacity = 128, .scalar_capacity = 2048, .glyph_capacity = 1024, .max_sequence_scalars = 80 },
        .shaped_capacity = 160,
        .raster_bytes = 512 * 512,
    });
    defer output.releasePresentationStore(store);

    const canonical = try allocator.create(vt.Terminal);
    defer allocator.destroy(canonical);
    try vt.Terminal.initWithHistoryInto(canonical, allocator, 2, 4, 8);
    defer canonical.deinit();
    const cell = output.presentationStoreCellSize(store);
    try canonical.setCellPixelSize(cell.width, cell.height);
    try std.testing.expectError(error.HistoryCapacityMismatch, Borrowed.initBorrowedShared(allocator, canonical, store, .{}));
    try std.testing.expectEqual(@as(u32, 1), output.presentationStoreReferences(store));

    const direct = try Borrowed.initBorrowedShared(allocator, canonical, store, .{ .history_capacity = 8 });
    defer direct.deinit();
    try std.testing.expectEqual(@as(u32, 2), output.presentationStoreReferences(store));
    try std.testing.expect((try canonical.feed("\x1b[?25lA")).stateChanged());
    try direct.flush();
    const pinned = try direct.hold();
    defer direct.release();
    try std.testing.expectEqual(@as(u16, 2), pinned.rows);
    try std.testing.expect(pinned.glyphs[0].len != 0);
    const original = try allocator.dupe(output.commands.Command, pinned.glyphs[0]);
    defer allocator.free(original);

    // The owner borrows canonical state, never clones it; a previous cut stays
    // immutable while the producer services newer VT output and geometry.
    try canonical.resize(3, 5);
    try std.testing.expect((try canonical.feed("\x1b[3;5HZ")).stateChanged());
    try direct.flush();
    try std.testing.expectEqual(@as(u16, 3), direct.accepted_rows);
    try std.testing.expectEqual(@as(u16, 5), direct.accepted_cols);
    try std.testing.expectEqualDeep(original, pinned.glyphs[0]);
}
