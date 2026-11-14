//! App-owned desktop consequences on the one mutable canonical VT. The SDL
//! worker uses this policy directly, with its FIFO behavior covered by tests.
const std = @import("std");
const vt = @import("howl_vt");
const runtime = @import("canonical.zig");

const clipboard_limit = 1024 * 1024;

/// Only the exact VT reply/consume failures and a bounded clipboard allocation may escape.
pub const Error = vt.Terminal.ConsumeConsequenceError || vt.Terminal.ClipboardReplyError ||
    vt.Terminal.PointerShapeReplyError || vt.Terminal.ColorPreferenceReplyError ||
    vt.Terminal.ContainerReplyError || error{ OutOfMemory, StaleClipboardRequest, StaleContainerRequest, ContainerReplyMismatch };

/// Copied host facts, never borrowed from the mutable VT or returned to the GUI as references.
pub const Applied = struct {
    worked: bool = false,
    attention: bool = false,
    clipboard: ?[]u8 = null,

    /// Releases the latest accepted clipboard payload.
    pub fn deinit(self: *Applied, allocator: std.mem.Allocator) void {
        if (self.clipboard) |bytes| allocator.free(bytes);
        self.* = undefined;
    }
};

/// Applies the existing app's bounded FIFO desktop policy directly to its VT.
/// The canonical service collects serialized reply bytes on its next turn.
pub fn drain(terminal: *vt.Terminal, allocator: std.mem.Allocator, preference: vt.Terminal.ColorSchemePreference) Error!Applied {
    var result: Applied = .{};
    errdefer result.deinit(allocator);
    while (terminal.consequenceHead()) |head| {
        const id = head.id();
        result.worked = true;
        switch (head) {
            .clipboard => |request| switch (request.kind) {
                .query => {
                    const replied = try terminal.replyClipboard(id, "");
                    std.debug.assert(replied);
                    continue;
                },
                .set => if (request.protocol == .osc52) {
                    const copied = terminal.copyClipboard(id, allocator, clipboard_limit) catch |failure| switch (failure) {
                        error.ClipboardLimit => {
                            try terminal.consumeConsequence(id);
                            continue;
                        },
                        else => |err| return err,
                    };
                    if (copied) |bytes| {
                        try terminal.consumeConsequence(id);
                        if (result.clipboard) |previous| allocator.free(previous);
                        result.clipboard = bytes;
                        continue;
                    }
                },
                .packet => {},
            },
            .pointer_shape => |request| if (request.payload.len != 0 and request.payload[0] == '?') {
                try terminal.replyPointerShape(id, "default");
                continue;
            },
            .color_preference_query => {
                try terminal.replyColorPreference(id, preference);
                continue;
            },
            .container => |request| switch (request.request) {
                .report_screen_cells => {
                    const view = terminal.semanticView(0);
                    try terminal.replyContainer(id, .{ .screen_cells = .{ .rows = view.rows, .cols = view.cols } });
                    continue;
                },
                .report_state, .report_position, .report_icon_title => {
                    try terminal.declineContainerQuery(id);
                    continue;
                },
                else => {},
            },
            .bell => result.attention = true,
            .notification => |request| if (request.kind != .message) {
                result.attention = true;
            },
            else => {},
        }
        try terminal.consumeConsequence(id);
    }
    return result;
}

test "direct desktop owns latest clipboard, attention and exact typed reply FIFO" {
    const allocator = std.testing.allocator;
    var terminal: vt.Terminal = undefined;
    try vt.Terminal.initWithHistoryInto(&terminal, allocator, 4, 20, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("\x1b]52;c;T25l\x07\x1b]52;c;VHdv\x07\x1b]52;c;?\x07\x1b]22;?\x07\x1b[?996n\x1b[19t\x1b[11t\x1b[13t\x1b[20t\x1b[5t\x1b]9;message\x07\x07")).stateChanged());
    var result = try drain(&terminal, allocator, .dark);
    defer result.deinit(allocator);
    try std.testing.expect(result.worked);
    try std.testing.expect(result.attention);
    try std.testing.expectEqualStrings("Two", result.clipboard.?);
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
    try std.testing.expectEqualStrings("\x1b]52;c;\x1b\\\x1b]22;default\x1b\\\x1b[?997;1n\x1b[9;4;20t", terminal.replyBytes());
    var idle = try drain(&terminal, allocator, .light);
    defer idle.deinit(allocator);
    try std.testing.expect(!idle.worked);
    try std.testing.expectEqual(@as(?[]u8, null), idle.clipboard);
}

test "direct desktop declines container geometry and window mutations without changing VT" {
    const allocator = std.testing.allocator;
    var terminal: vt.Terminal = undefined;
    try vt.Terminal.initWithHistoryInto(&terminal, allocator, 4, 20, 8);
    defer terminal.deinit();
    try terminal.setCellPixelSize(8, 16);

    const cases = [_]struct { sequence: []const u8, request: vt.Terminal.ContainerRequest }{
        .{ .sequence = "\x1b[1t", .request = .deiconify },
        .{ .sequence = "\x1b[2t", .request = .iconify },
        .{ .sequence = "\x1b[3;10;20t", .request = .{ .move = .{ .x = 10, .y = 20 } } },
        .{ .sequence = "\x1b[4;80;160t", .request = .{ .resize_pixels = .{ .height = 80, .width = 160 } } },
        .{ .sequence = "\x1b[5t", .request = .raise },
        .{ .sequence = "\x1b[6t", .request = .lower },
        .{ .sequence = "\x1b[8;12;34t", .request = .{ .resize_cells = .{ .rows = 12, .cols = 34 } } },
        .{ .sequence = "\x1b[12*|", .request = .{ .resize_rows = 12 } },
        .{ .sequence = "\x1b[132$|", .request = .{ .resize_columns = .columns_132 } },
    };
    for (cases) |case| {
        try std.testing.expect((try terminal.feed(case.sequence)).stateChanged());
        const pending = terminal.consequenceHead().?.container;
        try std.testing.expectEqualDeep(case.request, pending.request);
        try std.testing.expectEqual(@as(u16, 1), terminal.consequenceCount());

        var applied = try drain(&terminal, allocator, .dark);
        defer applied.deinit(allocator);
        try std.testing.expect(applied.worked);
        try std.testing.expect(!applied.attention);
        try std.testing.expect(applied.clipboard == null);
        try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
        try std.testing.expectEqualStrings("", terminal.replyBytes());
        const view = terminal.semanticView(0);
        try std.testing.expectEqual(@as(u16, 4), view.rows);
        try std.testing.expectEqual(@as(u16, 20), view.cols);
        const pixels = terminal.cellPixelSize().?;
        try std.testing.expectEqual(@as(u32, 8), pixels.width);
        try std.testing.expectEqual(@as(u32, 16), pixels.height);
    }
}

test "direct desktop only requests attention for focus and attention notifications" {
    const allocator = std.testing.allocator;
    var terminal: vt.Terminal = undefined;
    try vt.Terminal.initWithHistoryInto(&terminal, allocator, 4, 20, 8);
    defer terminal.deinit();

    const cases = [_]struct { sequence: []const u8, kind: vt.Terminal.NotificationKind, attention: bool }{
        .{ .sequence = "\x1b]9;message\x07", .kind = .message, .attention = false },
        .{ .sequence = "\x1b]99;i=one:d=0;body\x1b\\", .kind = .message, .attention = false },
        .{ .sequence = "\x1b]777;notify;title;body\x07", .kind = .message, .attention = false },
        .{ .sequence = "\x1b]1337;Notification=rich body\x07", .kind = .message, .attention = false },
        .{ .sequence = "\x1b]1337;StealFocus\x07", .kind = .steal_focus, .attention = true },
        .{ .sequence = "\x1b]1337;RequestAttention=fireworks\x07", .kind = .request_attention, .attention = true },
    };
    for (cases) |case| {
        try std.testing.expect((try terminal.feed(case.sequence)).stateChanged());
        try std.testing.expectEqual(@as(u16, 1), terminal.consequenceCount());
        const before = terminal.consequenceHead().?.notification;
        try std.testing.expectEqual(case.kind, before.kind);
        var applied = try drain(&terminal, allocator, .dark);
        defer applied.deinit(allocator);
        try std.testing.expect(applied.worked);
        try std.testing.expectEqual(case.attention, applied.attention);
        try std.testing.expect(applied.clipboard == null);
        try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
        try std.testing.expectEqualStrings("", terminal.replyBytes());
    }
}

test "direct desktop replies pass through canonical PTY before subsequent input" {
    const allocator = std.testing.allocator;
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const core = try allocator.create(runtime.Core);
    defer allocator.destroy(core);
    try core.initInto(allocator, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty raw -echo; printf '\\033]52;c;?\\007\\033]22;?\\007\\033[?996n\\033[19t\\033]0;WAITING\\007'; actual=$(dd bs=1 count=45 2>/dev/null | od -An -v -tx1 | tr -d ' \\n'); if [ \"$actual\" = '1b5d35323b633b1b5c1b5d32323b64656661756c741b5c1b5b3f3939373b316e1b5b393b343b3230744c415445' ]; then printf '\\033]0;REPLIED\\007'; else printf '\\033]0;WRONG\\007'; fi; sleep 2",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, .{ .width = 8, .height = 16 });
    defer core.deinit();
    var success = false;
    var sent_later_input = false;
    for (0..5000) |_| {
        const now: u64 = @intCast(std.Io.Clock.awake.now(threaded.io()).toNanoseconds());
        const result = try core.service(true, true, now);
        var desktop = try drain(&core.terminal, allocator, .dark);
        desktop.deinit(allocator);
        if (core.terminal.title()) |title| {
            if (std.mem.eql(u8, title, "WAITING") and !sent_later_input) {
                try core.input(.{ .bytes = "LATE" });
                sent_later_input = true;
            }
            if (std.mem.eql(u8, title, "REPLIED")) {
                success = true;
                break;
            }
            if (std.mem.eql(u8, title, "WRONG")) return error.WrongReply;
        }
        if (result.stream_closed and result.child_exit != null) break;
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(success);
    try std.testing.expect(sent_later_input);
    try std.testing.expectEqual(@as(u16, 0), core.terminal.consequenceCount());
}

test "clipboard allocation pressure retains the exact FIFO head until successful direct retry" {
    const allocator = std.testing.allocator;
    var terminal: vt.Terminal = undefined;
    try vt.Terminal.initWithHistoryInto(&terminal, allocator, 4, 20, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("\x1b]52;c;T25l\x07")).stateChanged());
    const original = terminal.consequenceHead().?.id();
    var failing = std.testing.FailingAllocator.init(allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, drain(&terminal, failing.allocator(), .dark));
    try std.testing.expectEqual(original, terminal.consequenceHead().?.id());
    var recovered = try drain(&terminal, allocator, .dark);
    defer recovered.deinit(allocator);
    try std.testing.expectEqualStrings("One", recovered.clipboard.?);
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
}
