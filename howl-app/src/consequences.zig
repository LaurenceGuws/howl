//! Terminal-originated requests and replies. The sole terminal worker drains
//! these consequences without granting the SDL window mutable VT access.
const std = @import("std");
const vt = @import("howl_vt");
const pty_vt = @import("pty_vt.zig");
const host_status = @import("program_status.zig");

const clipboard_limit = 1024 * 1024;

/// Only the exact VT reply/consume failures and a bounded clipboard allocation may escape.
pub const Error = vt.Terminal.ConsumeConsequenceError || vt.Terminal.ClipboardReplyError ||
    vt.Terminal.PointerShapeReplyError || vt.Terminal.ColorPreferenceReplyError ||
    vt.Terminal.ContainerReplyError || error{ OutOfMemory, StaleClipboardRequest, StaleContainerRequest, ContainerReplyMismatch };

/// Copied host facts, never borrowed from the mutable VT or returned to the GUI as references.
pub const Applied = struct {
    worked: bool = false,
    attention: bool = false,
    /// A copied status summary changed; this worker may notify its GUI.
    status_changed: bool = false,
    /// The exact status FIFO head remains owned by VT for a bounded retry.
    status_blocked: bool = false,
    clipboard: ?[]u8 = null,

    /// Releases the latest accepted clipboard payload.
    pub fn deinit(self: *Applied, allocator: std.mem.Allocator) void {
        if (self.clipboard) |bytes| allocator.free(bytes);
        self.* = undefined;
    }
};

/// Applies the existing app's bounded FIFO desktop policy directly to its VT.
/// The canonical service collects serialized reply bytes on its next turn.
pub fn drain(
    terminal: *vt.Terminal,
    allocator: std.mem.Allocator,
    preference: vt.Terminal.ColorSchemePreference,
    statuses: *host_status.Index,
) Error!Applied {
    var result: Applied = .{};
    errdefer result.deinit(allocator);
    // Host owns the reset boundary. Ignore events from earlier VT epochs.
    result.status_changed = statuses.syncReset(terminal.resetSequence());
    const current_reset = terminal.resetSequence();
    while (terminal.consequenceHead()) |head| {
        const id = head.id();
        const previously_worked = result.worked;
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
                .packet => {
                    // The host has not granted MIME clipboard access.
                    // Refusal is a protocol effect, not an OS clipboard call.
                    terminal.declineKittyClipboard(id) catch |failure| switch (failure) {
                        error.ReplyLimit => {
                            result.worked = previously_worked;
                            return result;
                        },
                        else => return failure,
                    };
                    continue;
                },
            },
            .pointer_shape => |request| if (request.payload.len != 0 and request.payload[0] == '?') {
                try terminal.replyPointerShape(id, "default");
                continue;
            },
            .color_preference_query => {
                terminal.replyColorPreference(id, preference) catch |failure| switch (failure) {
                    error.ReplyLimit => {
                        // The exact query remains at the head. Wait for PTY
                        // write progress rather than fabricating a reply or
                        // stopping canonical service.
                        result.worked = previously_worked;
                        return result;
                    },
                    else => return failure,
                };
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
            .program_status => |request| {
                if (request.reset_generation == current_reset) {
                    const changed = statuses.apply(request.action) catch {
                        result.worked = previously_worked;
                        result.status_blocked = true;
                        return result;
                    };
                    result.status_changed = result.status_changed or changed;
                }
            },
            .notification => |request| if (request.kind != .message) {
                result.attention = true;
            },
            else => {},
        }
        try terminal.consumeConsequence(id);
    }
    return result;
}

test "real host OSC7501 consumes and publishes status instead of an inert VT event" {
    const allocator = std.testing.allocator;
    var terminal = try vt.Terminal.init(allocator, 2, 8);
    defer terminal.deinit();
    var statuses = host_status.Index.init(std.testing.allocator);
    defer statuses.deinit();
    terminal.setProgramStatusConsumer(true);
    try std.testing.expect((try terminal.feed("\x1b]7501;state=working:id=sync:progress=40\x1b\\")).stateChanged());
    var first = try drain(&terminal, allocator, .dark, &statuses);
    defer first.deinit(allocator);
    try std.testing.expect(first.worked and first.status_changed);
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
    try std.testing.expect(statuses.summary().state.? == .working);
    try std.testing.expectEqual(@as(?u8, 40), statuses.summary().progress);
    try std.testing.expectEqualStrings("", terminal.replyBytes());

    try std.testing.expect((try terminal.feed("\x1b]7501;state=blocked:kind=auth:id=sync\x1b\\")).stateChanged());
    var blocked = try drain(&terminal, allocator, .dark, &statuses);
    defer blocked.deinit(allocator);
    try std.testing.expect(blocked.status_changed);
    try std.testing.expect(statuses.summary().kind.? == .auth);

    try std.testing.expect((try terminal.feed("\x1b]7501;?\x07")).stateChanged());
    try std.testing.expectEqualStrings(
        "\x1b]7501;?:states=idle,working,done,blocked,error:kinds=permission,question,auth\x07",
        terminal.replyBytes(),
    );
    try terminal.consumeReplyBytes(terminal.replyBytes().len);

    try std.testing.expect((try terminal.feed("\x1b]7501;state=done:id=sync\x1b\\")).stateChanged());
    var done = try drain(&terminal, allocator, .dark, &statuses);
    defer done.deinit(allocator);
    try std.testing.expect(done.status_changed);
    try std.testing.expect(statuses.summary().state.? == .done);
    try std.testing.expect(statuses.seenByUser());
    try std.testing.expect(statuses.summary().state == null);
    try std.testing.expect((try terminal.feed("\x1b]7501;state=working:id=other\x1b\\")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1bc")).stateChanged());
    var reset = try drain(&terminal, allocator, .dark, &statuses);
    defer reset.deinit(allocator);
    try std.testing.expect(statuses.summary().state == null);
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
    try std.testing.expect(!statuses.syncReset(terminal.resetSequence()));
}

test "terminal consequences own latest clipboard, attention and typed reply FIFO" {
    var statuses = host_status.Index.init(std.testing.allocator);
    defer statuses.deinit();
    const allocator = std.testing.allocator;
    var terminal: vt.Terminal = undefined;
    try vt.Terminal.initWithHistoryInto(&terminal, allocator, 4, 20, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("\x1b]52;c;T25l\x07\x1b]52;c;VHdv\x07\x1b]52;c;?\x07\x1b]22;?\x07\x1b[?996n\x1b[19t\x1b[11t\x1b[13t\x1b[20t\x1b[5t\x1b]9;message\x07\x07")).stateChanged());
    var result = try drain(&terminal, allocator, .dark, &statuses);
    defer result.deinit(allocator);
    try std.testing.expect(result.worked);
    try std.testing.expect(result.attention);
    try std.testing.expectEqualStrings("Two", result.clipboard.?);
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
    try std.testing.expectEqualStrings("\x1b]52;c;\x1b\\\x1b]22;default\x1b\\\x1b[?997;1n\x1b[9;4;20t", terminal.replyBytes());
    var idle = try drain(&terminal, allocator, .light, &statuses);
    defer idle.deinit(allocator);
    try std.testing.expect(!idle.worked);
    try std.testing.expectEqual(@as(?[]u8, null), idle.clipboard);
}

test "terminal consequences decline container geometry and window mutation without changing VT" {
    var statuses = host_status.Index.init(std.testing.allocator);
    defer statuses.deinit();
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

        var applied = try drain(&terminal, allocator, .dark, &statuses);
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

test "terminal consequences only request attention for focus and attention notifications" {
    var statuses = host_status.Index.init(std.testing.allocator);
    defer statuses.deinit();
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
        var applied = try drain(&terminal, allocator, .dark, &statuses);
        defer applied.deinit(allocator);
        try std.testing.expect(applied.worked);
        try std.testing.expectEqual(case.attention, applied.attention);
        try std.testing.expect(applied.clipboard == null);
        try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
        try std.testing.expectEqualStrings("", terminal.replyBytes());
    }
}

test "terminal consequence replies pass through PTY before subsequent input" {
    var statuses = host_status.Index.init(std.testing.allocator);
    defer statuses.deinit();
    const allocator = std.testing.allocator;
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const core = try allocator.create(pty_vt.Core);
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
        var desktop = try drain(&core.terminal, allocator, .dark, &statuses);
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
    var statuses = host_status.Index.init(std.testing.allocator);
    defer statuses.deinit();
    const allocator = std.testing.allocator;
    var terminal: vt.Terminal = undefined;
    try vt.Terminal.initWithHistoryInto(&terminal, allocator, 4, 20, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("\x1b]52;c;T25l\x07")).stateChanged());
    const original = terminal.consequenceHead().?.id();
    var failing = std.testing.FailingAllocator.init(allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, drain(&terminal, failing.allocator(), .dark, &statuses));
    try std.testing.expectEqual(original, terminal.consequenceHead().?.id());
    var recovered = try drain(&terminal, allocator, .dark, &statuses);
    defer recovered.deinit(allocator);
    try std.testing.expectEqualStrings("One", recovered.clipboard.?);
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
}

test "host OSC7501 per-pane index remains compact with sparse text storage" {
    try std.testing.expect(@sizeOf(host_status.Index) <= 16 * 1024);
    try std.testing.expect(@sizeOf(host_status.Summary) <= 64);
    try std.testing.expectEqual(@as(usize, 64), host_status.max_records);
}

test "host status snapshot includes only validated app name for toast" {
    var index = host_status.Index.init(std.testing.allocator);
    defer index.deinit();
    const parse = vt.Terminal.ProgramStatus.parse;
    try std.testing.expect(try index.apply(parse("state=working:id=compile:app=zig:progress=32").?));
    const current = index.summary();
    try std.testing.expectEqualStrings("zig", current.appText());
    try std.testing.expectEqual(@as(?u8, 32), current.progress);
    try std.testing.expect(try index.apply(parse("state=working:id=compile:app=cargo:progress=32").?));
    try std.testing.expectEqualStrings("cargo", index.summary().appText());
    try std.testing.expect(@sizeOf(host_status.Index) <= 16 * 1024);
    try std.testing.expect(@sizeOf(host_status.Summary) <= 64);
}

test "host OSC7501 index preserves most urgent program, ties and count" {
    var index = host_status.Index.init(std.testing.allocator);
    defer index.deinit();
    const parse = vt.Terminal.ProgramStatus.parse;
    try std.testing.expect(try index.apply(parse("state=working:id=compile:progress=40").?));
    try std.testing.expect(try index.apply(parse("state=blocked:kind=permission:id=install").?));
    try std.testing.expect(index.summary().state.? == .blocked);
    try std.testing.expect(index.summary().kind.? == .permission);
    try std.testing.expectEqual(@as(u8, 1), index.summary().count);
    try std.testing.expect(try index.apply(parse("state=blocked:kind=question:id=download").?));
    try std.testing.expect(index.summary().kind.? == .question);
    try std.testing.expectEqual(@as(u8, 2), index.summary().count);
    try std.testing.expect(try index.apply(parse("state=done:id=compile").?));
    try std.testing.expect(index.summary().state.? == .blocked);
    try std.testing.expect(!(try index.apply(parse("state=blocked:kind=question:id=download").?)));
    try std.testing.expect(index.summary().state.? == .blocked);
    try std.testing.expectEqual(@as(u8, 2), index.summary().count);
    try std.testing.expectEqual(@as(usize, 3), index.len);
}

test "host OSC7501 clear only exact ID descendants and retains neighboring records" {
    var index = host_status.Index.init(std.testing.allocator);
    defer index.deinit();
    const parse = vt.Terminal.ProgramStatus.parse;
    for ([_][]const u8{
        "state=working:id=sync",
        "state=blocked:id=sync/setup:kind=auth",
        "state=done:id=sync/setup/key",
        "state=error:id=synchronize",
        "state=idle:id=other",
    }) |body| try std.testing.expect(try index.apply(parse(body).?));
    try std.testing.expectEqual(@as(usize, 5), index.len);
    try std.testing.expect(try index.apply(parse("state=clear:id=sync/setup").?));
    try std.testing.expectEqual(@as(usize, 3), index.len);
    try std.testing.expect(try index.apply(parse("state=clear:id=sync").?));
    try std.testing.expectEqual(@as(usize, 2), index.len);
    try std.testing.expect(index.summary().state.? == .@"error");
    try std.testing.expect(!(try index.apply(parse("state=clear:id=sync").?)));
    try std.testing.expect(try index.apply(parse("state=clear").?));
    try std.testing.expectEqual(@as(usize, 0), index.len);
    try std.testing.expect(index.summary().state == null);
}

test "host OSC7501 process exit, user-seen and reset lifetimes are independent" {
    var index = host_status.Index.init(std.testing.allocator);
    defer index.deinit();
    const parse = vt.Terminal.ProgramStatus.parse;
    try std.testing.expect(!index.syncReset(1));
    try std.testing.expect(try index.apply(parse("state=working:id=active:progress=25").?));
    try std.testing.expect(try index.apply(parse("state=blocked:id=waiting:kind=question").?));
    try std.testing.expect(try index.apply(parse("state=done:id=finished").?));
    try std.testing.expect(try index.apply(parse("state=error:id=failed").?));
    try std.testing.expect(index.processExited());
    try std.testing.expectEqual(@as(usize, 2), index.len);
    try std.testing.expect(index.summary().state.? == .@"error");
    try std.testing.expect(index.seenByUser());
    try std.testing.expect(index.summary().state == null);
    try std.testing.expect(try index.apply(parse("state=working:id=new").?));
    try std.testing.expect(index.syncReset(2));
    try std.testing.expect(!index.syncReset(2));
    try std.testing.expectEqual(@as(usize, 0), index.len);
}

test "host OSC7501 fixed index evicts least recently reported records" {
    var index = host_status.Index.init(std.testing.allocator);
    defer index.deinit();
    for (0..host_status.max_records) |i| {
        var buffer: [70]u8 = undefined;
        const text = try std.fmt.bufPrint(&buffer, "state=working:id=job{d}", .{i});
        try std.testing.expect(try index.apply(vt.Terminal.ProgramStatus.parse(text).?));
    }
    try std.testing.expectEqual(host_status.max_records, index.len);
    // Re-report unchanged job0, refreshing its eviction recency only.
    try std.testing.expect(!(try index.apply(vt.Terminal.ProgramStatus.parse("state=working:id=job0").?)));
    try std.testing.expect(try index.apply(vt.Terminal.ProgramStatus.parse("state=blocked:id=new:kind=auth").?));
    try std.testing.expectEqual(host_status.max_records, index.len);
    try std.testing.expect(!(try index.apply(vt.Terminal.ProgramStatus.parse("state=clear:id=job1").?)));
    try std.testing.expect(try index.apply(vt.Terminal.ProgramStatus.parse("state=clear:id=job0").?));
    try std.testing.expectEqual(host_status.max_records - 1, index.len);
}

test "Rex retains at least 64 independent records and refreshes eviction recency" {
    var index = host_status.Index.init(std.testing.allocator);
    defer index.deinit();
    const parse = vt.Terminal.ProgramStatus.parse;
    for (0..64) |i| {
        var buffer: [64]u8 = undefined;
        const body = try std.fmt.bufPrint(&buffer, "state=working:id=job{d}", .{i});
        try std.testing.expect(try index.apply(parse(body).?));
    }
    try std.testing.expectEqual(@as(usize, 64), index.len);
    try std.testing.expectEqual(@as(u8, 64), index.summary().count);
    try std.testing.expect(!(try index.apply(parse("state=working:id=job0").?)));
    try std.testing.expect(try index.apply(parse("state=working:id=job64").?));
    try std.testing.expectEqual(@as(usize, 64), index.len);
    try std.testing.expect(!(try index.apply(parse("state=clear:id=job1").?)));
    try std.testing.expect(try index.apply(parse("state=clear:id=job0").?));
    try std.testing.expect(try index.apply(parse("state=clear:id=job63").?));
}

test "Rex app replacement and nearest ancestor inheritance are live" {
    var index = host_status.Index.init(std.testing.allocator);
    defer index.deinit();
    const parse = vt.Terminal.ProgramStatus.parse;
    try std.testing.expect(try index.apply(parse("state=blocked:id=build/test/child:app=local:kind=permission:progress=42").?));
    try std.testing.expectEqualStrings("local", index.summary().appText());
    try std.testing.expect(try index.apply(parse("state=blocked:id=build/test/child:kind=permission:progress=42").?));
    try std.testing.expectEqualStrings("", index.summary().appText());
    try std.testing.expect(try index.apply(parse("state=idle:app=root").?));
    try std.testing.expectEqualStrings("root", index.summary().appText());
    try std.testing.expect(try index.apply(parse("state=idle:id=build:app=build").?));
    try std.testing.expectEqualStrings("build", index.summary().appText());
    try std.testing.expect(try index.apply(parse("state=idle:id=build/test:app=nearest").?));
    try std.testing.expectEqualStrings("nearest", index.summary().appText());
    try std.testing.expect(try index.apply(parse("state=idle:id=build/test").?));
    try std.testing.expectEqualStrings("build", index.summary().appText());
    try std.testing.expect(try index.apply(parse("state=idle:id=build:app=other").?));
    try std.testing.expectEqualStrings("other", index.summary().appText());
    try std.testing.expect(try index.apply(parse("state=blocked:id=build/test/child:app=override").?));
    try std.testing.expectEqualStrings("override", index.summary().appText());
    try std.testing.expect(index.summary().kind == null and index.summary().progress == null);
    try std.testing.expect(try index.apply(parse("state=blocked:id=build/test/child:app=invalid/name").?));
    try std.testing.expectEqualStrings("other", index.summary().appText());
}

test "Rex fragmented rejected reports preserve the real host index and reply lane" {
    const allocator = std.testing.allocator;
    const segment = "abcdefghijklmnopqrstuvwxyz123456";
    const id = segment ++ "/" ++ segment ++ "/" ++ segment ++ "/abcdefghijklmnopqrstuvwxyz123";
    comptime std.debug.assert(id.len == 128);
    for ([_][]const u8{ "\x07", "\x1b\\" }) |term| {
        const invalid_bodies = [_][]const u8{
            "state=clear:id=" ++ id ++ "4",
            "state=clear:title=AA==:title=QQ==",
            "state=done:id=" ++ id ++ ":msg=////:msg=QQ==",
        };
        for (invalid_bodies) |body| {
            var wire_buffer: [512]u8 = undefined;
            const wire = try std.fmt.bufPrint(&wire_buffer, "\x1b]7501;{s}{s}", .{ body, term });
            for (0..wire.len + 1) |split| {
                var terminal = try vt.Terminal.init(allocator, 2, 8);
                defer terminal.deinit();
                var index = host_status.Index.init(std.testing.allocator);
                defer index.deinit();
                terminal.setProgramStatusConsumer(true);
                const seed = "\x1b]7501;state=working:app=root\x07" ++
                    "\x1b]7501;state=blocked:id=" ++ id ++ ":kind=auth\x1b\\";
                try std.testing.expect((try terminal.feed(seed)).stateChanged());
                var initial = try drain(&terminal, allocator, .dark, &index);
                defer initial.deinit(allocator);
                const before = index.summary();
                try std.testing.expectEqual(@as(usize, 2), index.len);
                try std.testing.expectEqualStrings("root", before.appText());
                try std.testing.expect(before.state.? == .blocked and before.kind.? == .auth);
                const identity = terminal.semanticSequence();
                try std.testing.expect(!(try terminal.feed(wire[0..split])).stateChanged());
                try std.testing.expect(!(try terminal.feed(wire[split..])).stateChanged());
                var rejected = try drain(&terminal, allocator, .dark, &index);
                defer rejected.deinit(allocator);
                try std.testing.expect(!rejected.worked and !rejected.status_changed);
                try std.testing.expectEqual(@as(usize, 2), index.len);
                try std.testing.expectEqualDeep(before, index.summary());
                try std.testing.expectEqual(identity, terminal.semanticSequence());
                try std.testing.expectEqualStrings("", terminal.replyBytes());
                try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
            }
        }
    }
}

test "Rex prompt ordering preserves fresh reports and cannot be hidden by later shell marks" {
    const allocator = std.testing.allocator;
    const seed = "\x1b]7501;state=working:id=old\x07" ++
        "\x1b]7501;state=blocked:id=waiting\x07" ++
        "\x1b]7501;state=done:id=done\x07" ++
        "\x1b]7501;state=error:id=failed\x07";
    const wire = "\x1b]133;A\x07\x1b]133;B\x07" ++
        "\x1b]7501;state=blocked:id=new:kind=auth\x1b\\\x1b]133;C\x07";
    for (0..wire.len + 1) |split| {
        var terminal = try vt.Terminal.init(allocator, 2, 8);
        defer terminal.deinit();
        var index = host_status.Index.init(std.testing.allocator);
        defer index.deinit();
        terminal.setProgramStatusConsumer(true);
        try std.testing.expect((try terminal.feed(seed)).stateChanged());
        var initial = try drain(&terminal, allocator, .dark, &index);
        defer initial.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 4), index.len);
        for ([_][]const u8{ wire[0..split], wire[split..] }) |part| {
            const fed = try terminal.feed(part);
            std.debug.assert(!fed.titleChanged());
            var applied = try drain(&terminal, allocator, .dark, &index);
            defer applied.deinit(allocator);
        }
        try std.testing.expectEqual(@as(usize, 3), index.len);
        try std.testing.expectEqual(@as(?vt.Terminal.ProgramStatus.Kind, .auth), index.summary().kind);
        try std.testing.expectEqual(@as(u8, 'C'), terminal.shellMark().kind);
        try std.testing.expect(!(try index.apply(vt.Terminal.ProgramStatus.parse("state=clear:id=old").?)));
        try std.testing.expect(!(try index.apply(vt.Terminal.ProgramStatus.parse("state=clear:id=waiting").?)));
        try std.testing.expect(try index.apply(vt.Terminal.ProgramStatus.parse("state=clear:id=new").?));
        try std.testing.expect(try index.apply(vt.Terminal.ProgramStatus.parse("state=clear:id=done").?));
        try std.testing.expect(try index.apply(vt.Terminal.ProgramStatus.parse("state=clear:id=failed").?));
        try std.testing.expectEqual(@as(usize, 0), index.len);
    }
}

test "Rex host text allocation failure retains the exact FIFO head for retry" {
    const allocator = std.testing.allocator;
    var failing = std.testing.FailingAllocator.init(allocator, .{});
    var index = host_status.Index.init(failing.allocator());
    defer index.deinit();
    var terminal = try vt.Terminal.init(allocator, 2, 8);
    defer terminal.deinit();
    terminal.setProgramStatusConsumer(true);
    try std.testing.expect((try terminal.feed("\x1b]7501;state=working:id=job:title=T2xk\x07")).stateChanged());
    var initial = try drain(&terminal, allocator, .dark, &index);
    defer initial.deinit(allocator);
    const before = index.summary();
    try std.testing.expect((try terminal.feed("\x1b]7501;state=done:id=job:msg=TmV3\x07")).stateChanged());
    const id = terminal.consequenceHead().?.id();
    failing.fail_index = failing.alloc_index;
    var blocked = try drain(&terminal, allocator, .dark, &index);
    defer blocked.deinit(allocator);
    try std.testing.expect(blocked.status_blocked and !blocked.worked and !blocked.status_changed);
    try std.testing.expectEqualDeep(before, index.summary());
    try std.testing.expectEqual(id, terminal.consequenceHead().?.id());
    try std.testing.expectEqualStrings("", terminal.replyBytes());
    failing.fail_index = std.math.maxInt(usize);
    var retried = try drain(&terminal, allocator, .dark, &index);
    defer retried.deinit(allocator);
    try std.testing.expect(retried.status_changed and retried.worked and !retried.status_blocked);
    try std.testing.expect(index.summary().state.? == .done);
    try std.testing.expect(terminal.consequenceHead() == null);
}

test "Rex reset generation and bank changes preserve only the appropriate records" {
    const allocator = std.testing.allocator;
    var index = host_status.Index.init(allocator);
    defer index.deinit();
    var terminal = try vt.Terminal.init(allocator, 2, 8);
    defer terminal.deinit();
    terminal.setProgramStatusConsumer(true);
    try std.testing.expect((try terminal.feed("\x1b]7501;state=working:id=old:title=T2xk\x07")).stateChanged());
    var initial = try drain(&terminal, allocator, .dark, &index);
    defer initial.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), index.len);
    try std.testing.expect((try terminal.feed("\x1b[?1049h\x1b[!p\x1b[?1049l")).stateChanged());
    var unchanged = try drain(&terminal, allocator, .dark, &index);
    defer unchanged.deinit(allocator);
    try std.testing.expect(!unchanged.status_changed);
    try std.testing.expectEqual(@as(usize, 1), index.len);
    try std.testing.expect((try terminal.feed("\x1b]133;A\x07\x1b]7501;state=error:id=stale\x07\x1bc\x1b]7501;state=working:id=fresh:msg=TmV3\x07")).stateChanged());
    var reset = try drain(&terminal, allocator, .dark, &index);
    defer reset.deinit(allocator);
    try std.testing.expect(reset.status_changed);
    try std.testing.expectEqual(@as(usize, 1), index.len);
    try std.testing.expect(index.summary().state.? == .working);
    try std.testing.expect(!(try index.apply(vt.Terminal.ProgramStatus.parse("state=clear:id=old").?)));
    try std.testing.expect(!(try index.apply(vt.Terminal.ProgramStatus.parse("state=clear:id=stale").?)));
    try std.testing.expect(try index.apply(vt.Terminal.ProgramStatus.parse("state=clear:id=fresh").?));
    try std.testing.expectEqual(@as(usize, 0), index.len);
}

test "Rex blocked host allocation preserves earlier clipboard attention and report results" {
    const allocator = std.testing.allocator;
    var failing = std.testing.FailingAllocator.init(allocator, .{ .fail_index = 0 });
    var index = host_status.Index.init(failing.allocator());
    defer index.deinit();
    var terminal = try vt.Terminal.init(allocator, 2, 8);
    defer terminal.deinit();
    terminal.setProgramStatusConsumer(true);
    try std.testing.expect((try terminal.feed("\x1b]52;c;T25l\x07\x07" ++
        "\x1b]7501;state=working:id=first\x07" ++
        "\x1b]7501;state=done:id=second:msg=TmV3\x07" ++
        "\x1b]7501;state=clear:id=first\x07")).stateChanged());
    var blocked = try drain(&terminal, allocator, .dark, &index);
    defer blocked.deinit(allocator);
    try std.testing.expect(blocked.status_blocked and blocked.worked and blocked.status_changed and blocked.attention);
    try std.testing.expectEqualStrings("One", blocked.clipboard.?);
    try std.testing.expectEqual(@as(usize, 1), index.len);
    try std.testing.expectEqualStrings("second", terminal.consequenceHead().?.program_status.action.report.id);
    try std.testing.expectEqual(@as(u16, 2), terminal.consequenceCount());
    failing.fail_index = std.math.maxInt(usize);
    var retried = try drain(&terminal, allocator, .dark, &index);
    defer retried.deinit(allocator);
    try std.testing.expect(retried.status_changed and !retried.status_blocked and !retried.attention and retried.clipboard == null);
    try std.testing.expectEqual(@as(usize, 1), index.len);
    try std.testing.expect(index.summary().state.? == .done);
    try std.testing.expect(terminal.consequenceHead() == null);
    try std.testing.expectEqualStrings("", terminal.replyBytes());
}

test "color preference host query retains exact identity under reply saturation" {
    const allocator = std.testing.allocator;
    var terminal = try vt.Terminal.init(allocator, 2, 8);
    defer terminal.deinit();
    var statuses = host_status.Index.init(allocator);
    defer statuses.deinit();
    for (0..16384) |_| try std.testing.expect((try terminal.feed("\x1b[5n")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[?996n")).stateChanged());
    const id = terminal.consequenceHead().?.id();
    const revision = terminal.semanticSequence();
    var blocked = try drain(&terminal, allocator, .light, &statuses);
    defer blocked.deinit(allocator);
    try std.testing.expect(!blocked.worked);
    try std.testing.expectEqual(id, terminal.consequenceHead().?.id());
    try std.testing.expectEqual(revision, terminal.semanticSequence());
    try std.testing.expectEqual(@as(usize, 65536), terminal.replyBytes().len);
    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    var recovered = try drain(&terminal, allocator, .light, &statuses);
    defer recovered.deinit(allocator);
    try std.testing.expect(recovered.worked);
    try std.testing.expect(terminal.consequenceHead() == null);
    try std.testing.expectEqualStrings("\x1b[?997;2n", terminal.replyBytes());
}

test "unsupported MIME clipboard policy returns routed errors without granting host access" {
    var terminal = try vt.Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    var statuses = host_status.Index.init(std.testing.allocator);
    defer statuses.deinit();
    const packets =
        "\x1b]5522;type=read:id=a/b!+._-;dGV4dC9wbGFpbg==\x07" ++
        "\x1b]5522;type=read:id=list;Lg==\x1b\\" ++
        "\x1b]5522;type=read:id=bad;Q\x01Q==\x07" ++
        "\x1b]5522;type=write:id=bad-write:name=!!!!\x07" ++
        "\x1b]5522;type=write:id=write:pw=QQ==:name=QQ==\x1b\\" ++
        "\x1b]5522;type=wdata:mime=dGV4dC9wbGFpbg==;QQ==\x07" ++
        "\x1b]5522;type=walias:mime=dGV4dC9wbGFpbg==;dGV4dC9odG1s\x07" ++
        "\x1b]5522;type=wdata\x07";
    try std.testing.expect((try terminal.feed(packets)).stateChanged());
    var applied = try drain(&terminal, std.testing.allocator, .dark, &statuses);
    defer applied.deinit(std.testing.allocator);
    try std.testing.expect(applied.worked and applied.clipboard == null);
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
    try std.testing.expectEqualStrings(
        "\x1b]5522;type=read:status=EPERM:id=ab+._-\x1b\\" ++
            "\x1b]5522;type=read:status=EPERM:id=list\x1b\\" ++
            "\x1b]5522;type=write:status=EINVAL:id=bad-write\x1b\\" ++
            "\x1b]5522;type=write:status=EPERM:id=write\x1b\\",
        terminal.replyBytes(),
    );
}
