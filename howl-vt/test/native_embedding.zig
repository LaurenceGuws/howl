//! Verifies the curated native embedding root without repository-local imports.

const std = @import("std");
const howl_vt = @import("howl_vt");

test "native root owns the complete embedding contract" {
    var terminal = try howl_vt.Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();

    const feed = try terminal.feed("ABCD");
    try std.testing.expect(feed.stateChanged());

    const view = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u16, 2), view.rows);
    try std.testing.expectEqual(@as(u16, 8), view.cols);
    try std.testing.expectEqual(@as(u21, 'A'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'D'), view.cellAt(0, 3));

    const selected = try terminal.copyText(
        std.testing.allocator,
        .{ .start = .{ .row = 0, .col = 1 }, .end = .{ .row = 0, .col = 2 } },
        std.math.maxInt(usize),
    );
    defer std.testing.allocator.free(selected);
    try std.testing.expectEqualStrings("BC", selected);

    try std.testing.expect((try terminal.feed("\x1b[?2004h")).stateChanged());
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

    try std.testing.expect((try terminal.feed("\x1b[5n")).stateChanged());
    try std.testing.expectEqualStrings("\x1b[0n", terminal.replyBytes());
    try terminal.consumeReplyBytes(terminal.replyBytes().len);

    try std.testing.expect((try terminal.feed("\x1b]52;c;SG93bA==\x07")).stateChanged());
    const clipboard_request = terminal.consequenceHead().?.clipboard;
    const clipboard = (try terminal.takeClipboard(
        clipboard_request.generation,
        std.testing.allocator,
    )).?;
    defer std.testing.allocator.free(clipboard);
    try std.testing.expectEqualStrings("Howl", clipboard);

    try terminal.resize(3, 10);
    const resized = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u16, 3), resized.rows);
    try std.testing.expectEqual(@as(u16, 10), resized.cols);
}

test "native observation capability hides retained owners" {
    var terminal = try howl_vt.Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();

    const observation = terminal.observation();
    try std.testing.expectEqual(terminal.semanticSequence(), observation.semanticSequence());

    const observation_pointer = @typeInfo(@TypeOf(observation)).pointer;
    try std.testing.expect(observation_pointer.attrs.@"const");
    try std.testing.expect(@typeInfo(observation_pointer.child) == .@"opaque");

    const view = observation.semanticView(0);
    const screen_pointer = @typeInfo(@TypeOf(view.screen)).pointer;
    try std.testing.expect(screen_pointer.attrs.@"const");
    try std.testing.expect(@typeInfo(screen_pointer.child) == .@"opaque");

    const images = observation.images(0);
    const image_pointer = @typeInfo(@TypeOf(images.plane)).pointer;
    try std.testing.expect(image_pointer.attrs.@"const");
    try std.testing.expect(@typeInfo(image_pointer.child) == .@"opaque");

    const mark_pointer = @typeInfo(@TypeOf(observation.shellMark().metadata)).pointer;
    try std.testing.expect(mark_pointer.attrs.@"const");
}


test "wrapped history offset advances exactly one physical row" {
    var terminal = try howl_vt.Terminal.initWithHistory(std.testing.allocator, 6, 24, 128);
    defer terminal.deinit();

    const replay =
        "/projects/device-reader-integration/requirements/source/\r\n" ++
        "./workspace/docs/projects/resident-booking/requirements/source/Resident Facility Booking module specification and acceptance notes.docx\r\n" ++
        "./workspace/docs/projects/product-catalogue/reference/product-and-feature-catalogue-with-long-descriptive-filename.pdf\r\n" ++
        "./workspace/docs/projects/scanner-replatform/architecture/source/scanner_replatform_architecture_and_migration_notes.pdf\r\n" ++
        "./workspace/docs/projects/secure-device-control/requirements/source/Secure Device Control Solution for Smart Access Hardware.docx\r\n" ++
        "./workspace/docs/projects/third-party-integration/guides/gateway-client-installation-and-troubleshooting-guide.md\r\n" ++
        "./workspace/docs/scripts/environment-refresh/restore-and-validate-after-refresh.sh\r\n";
    try std.testing.expect((try terminal.feed(replay)).stateChanged());

    const live = terminal.semanticView(0);
    try std.testing.expect(live.history_count > 10);
    const max_offset = @min(live.history_count, 20);
    var previous: [6][24]u21 = undefined;
    var previous_wrapped: [6]bool = undefined;
    {
        const view = terminal.semanticView(0);
        for (0..view.rows) |row| {
            previous_wrapped[row] = view.rowWrapped(@intCast(row));
            for (0..view.cols) |col| previous[row][col] = view.cellAt(@intCast(row), @intCast(col));
        }
    }
    var offset: u32 = 1;
    while (offset <= max_offset) : (offset += 1) {
        const view = terminal.semanticView(offset);
        for (1..view.rows) |row| {
            try std.testing.expectEqual(previous_wrapped[row - 1], view.rowWrapped(@intCast(row)));
            for (0..view.cols) |col| {
                try std.testing.expectEqual(previous[row - 1][col], view.cellAt(@intCast(row), @intCast(col)));
            }
        }
        for (0..view.rows) |row| {
            previous_wrapped[row] = view.rowWrapped(@intCast(row));
            for (0..view.cols) |col| previous[row][col] = view.cellAt(@intCast(row), @intCast(col));
        }
    }
}
