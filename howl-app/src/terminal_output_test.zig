//! Independent terminal ownership tests: one PTY/VT, borrowed Text output,
//! and immutable leases, with no SDL window or redundant canonical owner.
const std = @import("std");
const vt = @import("howl_vt");
const pty = @import("howl_pty");
const output = @import("howl_vt_output");
const Borrowed = @import("output_state").State(false);

test {
    std.testing.refAllDecls(@import("pty_vt.zig"));
    std.testing.refAllDecls(@import("projection.zig"));
    std.testing.refAllDecls(@import("consequences.zig"));
}

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

test "a direct PTY feeds the same canonical VT projected by borrowed output" {
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

    var canonical: vt.Terminal = undefined;
    try vt.Terminal.initWithHistoryInto(&canonical, allocator, 3, 12, 8);
    defer canonical.deinit();
    const cell = output.presentationStoreCellSize(store);
    try canonical.setCellPixelSize(cell.width, cell.height);
    const direct = try Borrowed.initBorrowedShared(allocator, &canonical, store, .{ .history_capacity = 8 });
    defer direct.deinit();

    var transport = try pty.Owned.init(allocator, std.testing.environ, "/bin/sh", "printf HOWL; sleep 2", null, .{
        .term = "xterm-256color",
        .colorterm = "truecolor",
    });
    defer transport.deinit();
    const pixel_width = std.math.cast(u16, @as(u32, 12) * cell.width) orelse return error.InvalidCellExtent;
    const pixel_height = std.math.cast(u16, @as(u32, 3) * cell.height) orelse return error.InvalidCellExtent;
    try transport.startWithPixels(12, 3, pixel_width, pixel_height);

    var buffer: [128]u8 = undefined;
    var received = false;
    for (0..2000) |_| {
        const count = transport.read(&buffer) catch |failure| switch (failure) {
            error.WouldBlock, error.Interrupted => 0,
            else => return failure,
        };
        if (count != 0) {
            const change = try canonical.feed(buffer[0..count]);
            try std.testing.expect(change.stateChanged());
            const view = canonical.semanticView(0);
            received = view.cellAt(0, 0) == 'H' and
                view.cellAt(0, 1) == 'O' and
                view.cellAt(0, 2) == 'W' and
                view.cellAt(0, 3) == 'L';
            if (received) break;
        }
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(received);
    try direct.flush();
    const pinned = try direct.hold();
    defer direct.release();
    try std.testing.expect(pinned.glyphs[0].len != 0);
}
