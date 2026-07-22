//! Verifies the curated native embedding root without repository-local imports.

const std = @import("std");
const howl_vt = @import("howl_vt");

test "native root owns the complete embedding contract" {
    var terminal = try howl_vt.Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();

    const feed = try terminal.feed("ABCD");
    try std.testing.expect(feed.state_changed);

    const publication = terminal.visualView();
    try std.testing.expectEqual(@as(u16, 2), publication.view.rows);
    try std.testing.expectEqual(@as(u16, 8), publication.view.cols);
    try std.testing.expectEqual(@as(u21, 'A'), publication.view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'D'), publication.view.cellAt(0, 3));
    try std.testing.expect(terminal.ackVisual(publication.dirty_token));

    const stale = terminal.visualView();
    _ = try terminal.feed("E");
    try std.testing.expect(!terminal.ackVisual(stale.dirty_token));
    const current = terminal.visualView();
    try std.testing.expect(current.dirty == .rows);
    try std.testing.expect(current.dirty_token != stale.dirty_token);
    try std.testing.expect(terminal.ackVisual(current.dirty_token));
    try std.testing.expect(terminal.visualView().dirty == .none);

    terminal.startSelection(0, 1);
    terminal.updateSelection(0, 2);
    terminal.finishSelection();
    const selected = try terminal.copySelection(std.testing.allocator);
    defer std.testing.allocator.free(selected);
    try std.testing.expectEqualStrings("BC", selected);

    _ = try terminal.feed("\x1b[?2004h");
    var input_scratch: howl_vt.Terminal.InputScratch = .{};
    var named_key = try terminal.encodeInput(
        std.testing.allocator,
        &input_scratch,
        .{ .key = .{ .key = .{ .named = .up } } },
    );
    defer named_key.deinit();
    try std.testing.expectEqualStrings("\x1b[A", named_key.bytes);

    var text = try terminal.encodeInput(
        std.testing.allocator,
        &input_scratch,
        .{ .bytes = "λ" },
    );
    defer text.deinit();
    try std.testing.expectEqualStrings("λ", text.bytes);

    var encoded = try terminal.encodeInput(
        std.testing.allocator,
        &input_scratch,
        .{ .paste = "paste" },
    );
    defer encoded.deinit();
    try std.testing.expectEqualStrings("\x1b[200~paste\x1b[201~", encoded.bytes);

    _ = try terminal.feed("\x1b[5n");
    const output = try terminal.drainPendingOutput(std.testing.allocator);
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings("\x1b[0n", output);

    _ = try terminal.feed("\x1b]52;c;SG93bA==\x07");
    const clipboard_request = terminal.pendingClipboardRequest().?;
    const clipboard = (try terminal.drainPendingClipboard(
        clipboard_request.generation,
        std.testing.allocator,
    )).?;
    defer std.testing.allocator.free(clipboard);
    try std.testing.expectEqualStrings("Howl", clipboard);

    try terminal.resize(3, 10);
    const resized = terminal.visualView().view;
    try std.testing.expectEqual(@as(u16, 3), resized.rows);
    try std.testing.expectEqual(@as(u16, 10), resized.cols);
}
