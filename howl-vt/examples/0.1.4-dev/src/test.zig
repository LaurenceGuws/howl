//! Proves the 0.1.4 development contract through the public package root.

const std = @import("std");
const howl_vt = @import("howl_vt");

fn feedTyped(
    terminal: *howl_vt.Terminal,
    bytes: []const u8,
) howl_vt.Terminal.FeedError!howl_vt.Terminal.FeedSummary {
    return terminal.feed(bytes);
}

fn encodeTyped(
    terminal: *howl_vt.Terminal,
    allocator: std.mem.Allocator,
    scratch: *howl_vt.Terminal.InputScratch,
    event: howl_vt.Terminal.InputEvent,
) howl_vt.Terminal.InputError!howl_vt.Terminal.EncodedInput {
    return terminal.encodeInput(allocator, scratch, event);
}

test "fragmented output mutates borrowed terminal state and retains replies" {
    var terminal = try howl_vt.Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();

    const text: howl_vt.Terminal.FeedSummary = try feedTyped(&terminal, "Howl\x1b[");
    try std.testing.expect(text.state_changed);
    const reply = try feedTyped(&terminal, "5n");
    try std.testing.expect(reply.state_changed);

    const view = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'H'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'l'), view.cellAt(0, 3));

    try std.testing.expectEqualStrings("\x1b[0n", terminal.replyBytes());
    try terminal.consumeReplyBytes(2);
    try std.testing.expectEqualStrings("0n", terminal.replyBytes());
    try std.testing.expectError(
        error.InvalidReplyCount,
        terminal.consumeReplyBytes(terminal.replyBytes().len + 1),
    );
    try std.testing.expectEqualStrings("0n", terminal.replyBytes());
    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    try std.testing.expectEqualStrings("", terminal.replyBytes());
}

test "ordered consequences are borrowed and consumed by exact identity" {
    var terminal = try howl_vt.Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x07")).state_changed);
    try std.testing.expectEqual(@as(u16, 1), terminal.consequenceCount());

    const consequence = terminal.consequenceHead() orelse
        return error.MissingConsequence;
    const id = switch (consequence) {
        .bell => |bell| bell.id,
        else => return error.UnexpectedConsequence,
    };
    try terminal.consumeConsequence(id);
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
}

test "container request and reply use the typed terminal contract" {
    var terminal = try howl_vt.Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b[11t")).state_changed);
    const consequence = terminal.consequenceHead() orelse
        return error.MissingContainerRequest;
    const request: howl_vt.Terminal.ContainerRequest = switch (consequence) {
        .container => |occurrence| occurrence.request,
        else => return error.UnexpectedContainerRequest,
    };
    try std.testing.expectEqual(.report_state, std.meta.activeTag(request));

    const reply: howl_vt.Terminal.ContainerReply = .{ .state = .normal };
    try terminal.replyContainer(consequence.id(), reply);
    try std.testing.expectEqualStrings("\x1b[1t", terminal.replyBytes());
    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
}

test "terminal modes determine key and paste encoding" {
    var terminal = try howl_vt.Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    var scratch: howl_vt.Terminal.InputScratch = .{};

    const named: howl_vt.Terminal.NamedKey = .up;
    const physical: howl_vt.Terminal.Key = .{ .named = named };
    const event: howl_vt.Terminal.InputEvent = .{ .key = .{ .key = physical } };
    var key: howl_vt.Terminal.EncodedInput = try encodeTyped(
        &terminal,
        std.testing.allocator,
        &scratch,
        event,
    );
    defer key.deinit();
    try std.testing.expectEqualStrings("\x1b[A", key.bytes);

    const focus: howl_vt.Terminal.InputEvent = .{ .focus = .in };
    var focus_result = try encodeTyped(&terminal, std.testing.allocator, &scratch, focus);
    defer focus_result.deinit();
    try std.testing.expectEqualStrings("", focus_result.bytes);

    const mouse: howl_vt.Terminal.InputEvent = .{ .mouse = .{
        .kind = .press,
        .button = .left,
        .row = 0,
        .col = 0,
        .mod = .{},
        .buttons_down = 1,
    } };
    var mouse_result = try encodeTyped(&terminal, std.testing.allocator, &scratch, mouse);
    defer mouse_result.deinit();
    try std.testing.expectEqualStrings("", mouse_result.bytes);

    try std.testing.expect((try terminal.feed("\x1b[?1004h\x1b[?1000h\x1b[?1006h")).state_changed);
    var focused = try encodeTyped(&terminal, std.testing.allocator, &scratch, focus);
    defer focused.deinit();
    try std.testing.expectEqualStrings("\x1b[I", focused.bytes);
    var reported_mouse = try encodeTyped(&terminal, std.testing.allocator, &scratch, mouse);
    defer reported_mouse.deinit();
    try std.testing.expectEqualStrings("\x1b[<0;1;1M", reported_mouse.bytes);

    try std.testing.expectError(
        error.InvalidUtf8,
        encodeTyped(&terminal, std.testing.allocator, &scratch, .{ .key = .{
            .key = .{ .named = named },
            .text = "\xff",
        } }),
    );

    try std.testing.expect((try terminal.feed("\x1b[?2004h")).state_changed);
    var paste = try terminal.encodeInput(
        std.testing.allocator,
        &scratch,
        .{ .paste = "paste" },
    );
    defer paste.deinit();
    try std.testing.expectEqualStrings("\x1b[200~paste\x1b[201~", paste.bytes);

    var no_storage: [0]u8 = .{};
    var fixed = std.heap.FixedBufferAllocator.init(&no_storage);
    try std.testing.expectError(
        error.OutOfMemory,
        encodeTyped(&terminal, fixed.allocator(), &scratch, .{ .paste = "paste" }),
    );
}

test "resize changes emulator geometry and rejects zero dimensions" {
    try std.testing.expectError(
        error.InvalidDimensions,
        howl_vt.Terminal.init(std.testing.allocator, 0, 8),
    );

    var terminal = try howl_vt.Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    try terminal.resize(3, 10);

    const view = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u16, 3), view.rows);
    try std.testing.expectEqual(@as(u16, 10), view.cols);
}

test "semantic row continuation is borrowed terminal state" {
    var terminal = try howl_vt.Terminal.init(std.testing.allocator, 2, 2);
    defer terminal.deinit();

    try std.testing.expect((try feedTyped(&terminal, "abc")).state_changed);
    const view = terminal.semanticView(0);
    try std.testing.expect(view.rowWrapped(0));
    try std.testing.expect(!view.rowWrapped(1));
}
