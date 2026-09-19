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
