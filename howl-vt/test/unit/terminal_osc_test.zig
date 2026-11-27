const std = @import("std");
const terminal_mod = @import("../../src/howl_vt.zig");
const reply_fill = @import("../support/reply_fill.zig");
const parser_mod = @import("../../src/parser.zig");

const Terminal = terminal_mod.Terminal;
const Rgb = Terminal.Rgb;

fn feed(terminal: *Terminal, bytes: []const u8) Terminal.FeedError!void {
    const summary = try terminal.feed(bytes);
    std.debug.assert(!summary.historyLost() or summary.stateChanged());
}

const expected_metadata_bytes: usize = 1024;
// Exact bounded payload ceiling for ordinary string controls in the parser.
const expected_string_control_bytes: usize = 2 * 1024;
const expected_clipboard_reply_bytes: usize = ((64 * 1024 - 12 - 8) / 4) * 3;
const expected_clipboard_request_bytes: usize = 1024 * 1024;
const expected_clipboard_packet_bytes: usize = 8 * 1024;
const expected_clipboard_capacity: u8 = 8;
const expected_file_transfer_bytes: usize = 8 * 1024;
const expected_iterm_file_transfer_bytes: usize = 2 * 1024;
const expected_file_transfer_capacity: u8 = 8;
const expected_notification_capacity: u8 = 8;
const expected_pointer_shape_capacity: u8 = 8;
const expected_drag_drop_payload_bytes: usize = 4096;
const expected_drag_drop_capacity: u8 = 16;
const expected_reply_bytes: usize = 64 * 1024;

fn consumeReplies(terminal: *Terminal) !void {
    try terminal.consumeReplyBytes(terminal.replyBytes().len);
}

test "OSC title updates terminal title under stream path" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try feed(&terminal, "\x1b]0;My Title\x07");
    try std.testing.expectEqualStrings("My Title", terminal.title().?);
}

test "OSC 4 rejects dangling palette pairs without partial mutation or reply" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    const original = terminal.presentation().palette[1];
    try std.testing.expect(!(try terminal.feed("\x1b]4;1;#112233;")).stateChanged());
    try std.testing.expect(!(try terminal.feed("dangling\x07")).stateChanged());
    try std.testing.expectEqualDeep(original, terminal.presentation().palette[1]);
    try std.testing.expectEqualStrings("", terminal.replyBytes());

    // A query preceding a dangling field may not leave a partial response.
    try std.testing.expect(!(try terminal.feed("\x1b]4;1;?;dangling\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings("", terminal.replyBytes());
    try std.testing.expectEqualDeep(original, terminal.presentation().palette[1]);

    // A subsequent complete two-pair command must still commit and query.
    try std.testing.expect((try terminal.feed("\x1b]4;1;#112233;2;#445566\x07")).stateChanged());
    try std.testing.expectEqual(Rgb{ .r = 0x11, .g = 0x22, .b = 0x33 }, terminal.presentation().palette[1]);
    try std.testing.expectEqual(Rgb{ .r = 0x44, .g = 0x55, .b = 0x66 }, terminal.presentation().palette[2]);
}

test "OSC 4 omits replies for out-of-domain palette indexes" {
    // Pinned Kitty window.py:set_color_table_color admits only 0..255
    // and emits no reply for out-of-range query indexes. Howl also
    // supports xterm's 256..260 special slots, but indexes above its
    // entire supported domain must not fabricate an empty OSC 4 reply.
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b]4;999;?\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings("", terminal.replyBytes());
    try std.testing.expect(!(try terminal.feed("\x1b]4;65535;?\x07")).stateChanged());
    try std.testing.expectEqualStrings("", terminal.replyBytes());

    // Valid neighboring requests still commit, reply, and retain order.
    try std.testing.expect((try terminal.feed("\x1b]4;1;#112233;999;?;1;?;2;#445566\x1b\\")).stateChanged());
    try std.testing.expectEqual(Rgb{ .r = 0x11, .g = 0x22, .b = 0x33 }, terminal.presentation().palette[1]);
    try std.testing.expectEqual(Rgb{ .r = 0x44, .g = 0x55, .b = 0x66 }, terminal.presentation().palette[2]);
    try std.testing.expectEqualStrings("\x1b]4;1;rgb:1111/2222/3333\x1b\\", terminal.replyBytes());
    try std.testing.expect(terminal.title() == null);
}

test "OSC 4 accepts one complete Kitty-style 256-color palette transaction" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    var sequence = std.ArrayList(u8).empty;
    defer sequence.deinit(allocator);
    try sequence.appendSlice(allocator, "\x1b]4;");
    const payload_start = sequence.items.len;
    for (0..256) |index| {
        if (index != 0) try sequence.append(allocator, ';');
        var pair: [32]u8 = undefined;
        const encoded = try std.fmt.bufPrint(&pair, "{d};#010203", .{index});
        try sequence.appendSlice(allocator, encoded);
    }
    const payload_len = sequence.items.len - payload_start;
    try std.testing.expectEqual(@as(usize, 2961), payload_len);
    try std.testing.expect(payload_len > expected_string_control_bytes);
    try std.testing.expect(payload_len <= parser_mod.max_palette_control_bytes);
    try sequence.append(allocator, 0x07);

    const summary = try terminal.feed(sequence.items);
    try std.testing.expect(summary.stateChanged());
    const presentation = terminal.presentation();
    try std.testing.expectEqual(Rgb{ .r = 1, .g = 2, .b = 3 }, presentation.palette[0]);
    try std.testing.expectEqual(Rgb{ .r = 1, .g = 2, .b = 3 }, presentation.palette[255]);

    sequence.clearRetainingCapacity();
    try sequence.appendSlice(allocator, "\x1b]4;");
    const oversized = try allocator.alloc(u8, parser_mod.max_palette_control_bytes + 1);
    defer allocator.free(oversized);
    @memset(oversized, 'x');
    try sequence.appendSlice(allocator, oversized);
    try sequence.append(allocator, 0x07);
    try sequence.appendSlice(allocator, "ok");
    const recovered = try terminal.feed(sequence.items);
    try std.testing.expect(recovered.stateChanged());
    const view = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'o'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'k'), view.cellAt(0, 1));
    const after = terminal.presentation();
    try std.testing.expectEqual(Rgb{ .r = 1, .g = 2, .b = 3 }, after.palette[0]);
    try std.testing.expectEqual(Rgb{ .r = 1, .g = 2, .b = 3 }, after.palette[255]);
}

test "GNU Screen title retains bounded title and icon with exact mutation" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b]0;old\x07")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1bknew")).stateChanged());
    const completed = try terminal.feed(" title\x1b\\");
    try std.testing.expect(completed.stateChanged());
    try std.testing.expect(completed.titleChanged());
    try std.testing.expect(completed.iconChanged());
    try std.testing.expectEqualStrings("new title", terminal.title().?);
    try std.testing.expectEqualStrings("new title", terminal.icon().?);

    const repeated = try terminal.feed("\x1bknew title\r");
    try std.testing.expect(!repeated.stateChanged());
    try std.testing.expect(!repeated.titleChanged());
    try std.testing.expect(!repeated.iconChanged());
    try std.testing.expect(!(try terminal.feed("\x1bk\n")).stateChanged());

    const payload = try allocator.alloc(u8, expected_metadata_bytes + 1);
    defer allocator.free(payload);
    @memset(payload, 't');
    var sequence = std.ArrayList(u8).empty;
    defer sequence.deinit(allocator);
    try sequence.appendSlice(allocator, "\x1bk");
    try sequence.appendSlice(allocator, payload[0..expected_metadata_bytes]);
    try sequence.append(allocator, '\r');
    const maximum = try terminal.feed(sequence.items);
    try std.testing.expect(maximum.stateChanged() and maximum.titleChanged() and maximum.iconChanged());
    try std.testing.expectEqual(@as(usize, expected_metadata_bytes), terminal.title().?.len);
    try std.testing.expectEqual(@as(usize, expected_metadata_bytes), terminal.icon().?.len);

    sequence.clearRetainingCapacity();
    try sequence.appendSlice(allocator, "\x1bk");
    try sequence.appendSlice(allocator, payload);
    try sequence.append(allocator, '\r');
    try std.testing.expectError(error.PropertyLimit, terminal.feed(sequence.items));
    try std.testing.expectEqual(@as(usize, expected_metadata_bytes), terminal.title().?.len);
    try std.testing.expectEqual(@as(usize, expected_metadata_bytes), terminal.icon().?.len);
}

test "newer Kitty ConEmu OSC 9;9 reports bounded canonical paths without notification" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    try std.testing.expect(terminal.workingDirectory() == null);

    // Kitty a79f376 vt-parser.c:603-614 routes the 9;9 subcommand to CWD;
    // screen.c:3974-3993 strips one enclosing quote pair, then admits only
    // nonempty absolute paths. Howl keeps the path in its existing CWD owner.
    try std.testing.expect(!(try terminal.feed("\x1b]9;9;\"/var/tes")).stateChanged());
    try std.testing.expect((try terminal.feed("t\"\x07")).stateChanged());
    try std.testing.expect(terminal.workingDirectory() != null);
    var cwd = terminal.workingDirectory().?;
    try std.testing.expect(cwd.kind == .path);
    try std.testing.expectEqualStrings("/var/test", cwd.value);
    try std.testing.expectEqual(@as(u8, 0), terminal.consequenceCount());
    try std.testing.expectEqualStrings("", terminal.replyBytes());

    // A repeated CWD is not a semantic change, and both OSC terminators work.
    try std.testing.expect(!(try terminal.feed("\x1b]9;9;/var/test\x1b\\")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b]9;9;/another/dir\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings("/another/dir", terminal.workingDirectory().?.value);
    try std.testing.expectEqual(@as(u8, 0), terminal.consequenceCount());

    // Malformed ConEmu CWD reports must not fall through as notifications or
    // replace the previous complete directory. A plain OSC 9 still notifies.
    for ([_][]const u8{
        "\x1b]9;9;\x07",                  "\x1b]9;9;relative/path\x1b\\",
        "\x1b]9;9;\"relative/path\"\x07", "\x1b]9;9;\"\"\x07",
    }) |invalid| {
        try std.testing.expect(!(try terminal.feed(invalid)).stateChanged());
        cwd = terminal.workingDirectory().?;
        try std.testing.expectEqualStrings("/another/dir", cwd.value);
        try std.testing.expectEqual(@as(u8, 0), terminal.consequenceCount());
    }
    try std.testing.expect((try terminal.feed("\x1b]9;regular notification\x07")).stateChanged());
    const notification = terminal.consequenceHead().?.notification;
    try std.testing.expectEqual(@as(u16, 9), notification.command);
    try std.testing.expectEqualStrings("regular notification", notification.payload);
    try terminal.consumeConsequence(notification.generation);

    // The existing OSC 7 URI still updates the same canonical directory.
    try std.testing.expect((try terminal.feed("\x1b]7;file://host/work\x1b\\")).stateChanged());
    cwd = terminal.workingDirectory().?;
    try std.testing.expect(cwd.kind == .uri);
    try std.testing.expectEqualStrings("file://host/work", cwd.value);
    try std.testing.expect((try terminal.feed("\x1b[?1049h\x1b[?1049l")).stateChanged());
    try std.testing.expectEqualStrings("file://host/work", terminal.workingDirectory().?.value);
    try std.testing.expect((try terminal.feed("\x1bc")).stateChanged());
    try std.testing.expect(terminal.workingDirectory() == null);
}

test "ConEmu OSC 9;9 directory quota preserves prior path and subsequent recovery" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 2, 8);
    defer terminal.deinit();
    try feed(&terminal, "\x1b]9;9;/stable\x07");
    try std.testing.expectEqualStrings("/stable", terminal.workingDirectory().?.value);

    // One slash plus 1023 bytes is the largest canonical retained metadata
    // path. The parser's larger input ceiling must not bypass that bound.
    const filler = try allocator.alloc(u8, expected_metadata_bytes);
    defer allocator.free(filler);
    @memset(filler, 'p');
    var sequence = std.ArrayList(u8).empty;
    defer sequence.deinit(allocator);
    try sequence.appendSlice(allocator, "\x1b]9;9;/");
    try sequence.appendSlice(allocator, filler[0 .. expected_metadata_bytes - 1]);
    try sequence.appendSlice(allocator, "\x1b\\");
    try std.testing.expect((try terminal.feed(sequence.items)).stateChanged());
    try std.testing.expectEqual(@as(usize, expected_metadata_bytes), terminal.workingDirectory().?.value.len);
    try std.testing.expectEqual(@as(u8, '/'), terminal.workingDirectory().?.value[0]);

    // Over-quota admission is typed and cannot replace the last complete path.
    sequence.clearRetainingCapacity();
    try sequence.appendSlice(allocator, "\x1b]9;9;/");
    try sequence.appendSlice(allocator, filler);
    try sequence.appendSlice(allocator, "\x07");
    try std.testing.expectError(error.PropertyLimit, terminal.feed(sequence.items));
    try std.testing.expectEqual(@as(usize, expected_metadata_bytes), terminal.workingDirectory().?.value.len);
    try std.testing.expectEqual(@as(u8, 0), terminal.consequenceCount());

    // The next complete control works, without a stale parser or directory.
    try std.testing.expect((try terminal.feed("\x1b]9;9;/recovered\x07")).stateChanged());
    try std.testing.expectEqualStrings("/recovered", terminal.workingDirectory().?.value);
}

test "OSC 7 and iTerm CurrentDir retain bounded directory state with exact mutation" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    const prefix = try terminal.feed("\x1b]7;file://host");
    try std.testing.expect(!prefix.stateChanged());
    const uri = try terminal.feed("/work\x1b\\");
    try std.testing.expect(uri.stateChanged());
    var directory = terminal.workingDirectory().?;
    try std.testing.expect(directory.kind == .uri);
    try std.testing.expectEqualStrings("file://host/work", directory.value);

    const repeated_uri = try terminal.feed("\x1b]7;file://host/work\x07");
    try std.testing.expect(!repeated_uri.stateChanged());
    const path = try terminal.feed("\x1b]1337;CurrentDir=file://host/work\x07");
    try std.testing.expect(path.stateChanged());
    directory = terminal.workingDirectory().?;
    try std.testing.expect(directory.kind == .path);
    try std.testing.expectEqualStrings("file://host/work", directory.value);
    try std.testing.expect(!(try terminal.feed("\x1b]1337;CurrentDir=file://host/work\x1b\\")).stateChanged());

    try std.testing.expect(!(try terminal.feed("\x1b]1337;CurrentDir\x07")).stateChanged());
    directory = terminal.workingDirectory().?;
    try std.testing.expect(directory.kind == .path);
    try std.testing.expectEqualStrings("file://host/work", directory.value);

    try std.testing.expect((try terminal.feed("\x1bc")).stateChanged());
    try std.testing.expect(terminal.workingDirectory() == null);
}

test "iTerm RemoteHost retains bounded metadata across terminal screen lifetime" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b]1337;RemoteHost=user@ho")).stateChanged());
    try std.testing.expect((try terminal.feed("st\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings("user@host", terminal.remoteHost().?);
    try std.testing.expect(!(try terminal.feed("\x1b]1337;RemoteHost=user@host\x07")).stateChanged());

    try std.testing.expect((try terminal.feed("\x1b[?1049h")).stateChanged());
    try terminal.resize(4, 10);
    terminal.hardReset();
    try std.testing.expectEqualStrings("user@host", terminal.remoteHost().?);

    const payload = try allocator.alloc(u8, expected_metadata_bytes + 1);
    defer allocator.free(payload);
    @memset(payload, 'h');
    var sequence = std.ArrayList(u8).empty;
    defer sequence.deinit(allocator);
    try sequence.appendSlice(allocator, "\x1b]1337;RemoteHost=");
    try sequence.appendSlice(allocator, payload[0..expected_metadata_bytes]);
    try sequence.append(allocator, 0x07);
    try std.testing.expect((try terminal.feed(sequence.items)).stateChanged());
    try std.testing.expectEqual(@as(usize, expected_metadata_bytes), terminal.remoteHost().?.len);

    sequence.clearRetainingCapacity();
    try sequence.appendSlice(allocator, "\x1b]1337;RemoteHost=");
    try sequence.appendSlice(allocator, payload);
    try sequence.append(allocator, 0x07);
    try std.testing.expectError(error.PropertyLimit, terminal.feed(sequence.items));
    try std.testing.expectEqual(@as(usize, expected_metadata_bytes), terminal.remoteHost().?.len);
}

test "iTerm ClearScrollback clears only active screen state with exact repetition" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 2, 4, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("aaaa\r\nbbbb\r\ncccc")).stateChanged());
    try std.testing.expect(terminal.semanticView(0).history_count > 0);
    const output_before = terminal.logicalOutputRange();

    try std.testing.expect((try terminal.feed("\x1b[?1049halt")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b]1337;ClearScrollback=ignored\x07")).stateChanged());
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expect(!(try terminal.feed("\x1b]1337;ClearScrollback\x1b\\")).stateChanged());

    try std.testing.expect((try terminal.feed("\x1b[?1049l")).stateChanged());
    try std.testing.expect(terminal.semanticView(0).history_count > 0);
    try std.testing.expectEqual(output_before, terminal.logicalOutputRange());
    try std.testing.expect(!(try terminal.feed("\x1b]1337;ClearScro")).stateChanged());
    try std.testing.expect((try terminal.feed("llback\x07")).stateChanged());
    const cleared = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u32, 0), cleared.history_count);
    try std.testing.expectEqual(output_before, terminal.logicalOutputRange());
    try std.testing.expectEqual(@as(u16, 0), cleared.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), cleared.cursor_col);
    for (0..cleared.rows) |row| {
        for (0..cleared.cols) |col| {
            try std.testing.expectEqual(@as(u21, 0), cleared.cellAt(@intCast(row), @intCast(col)));
        }
    }
    try std.testing.expect(!(try terminal.feed("\x1b]1337;ClearScrollback\x07")).stateChanged());
}

test "Kitty ignored OSC selectors remain bounded exact no-ops" {
    const ignored = [_]u32{
        5,   105,  6,    106,  13,   14,   15,   16,    18,
        46,  50,   51,   60,   61,   440,  633,  666,   697,
        701, 7704, 7721, 7750, 7770, 7771, 7777, 77119, 9001,
    };
    var terminal = try Terminal.init(std.testing.allocator, 2, 4);
    defer terminal.deinit();
    const baseline = terminal.semanticSequence();
    const baseline_content = terminal.contentSequence();

    for (ignored) |command| {
        var sequence_buf: [64]u8 = undefined;
        for ([_][]const u8{ "\x07", "\x1b\\" }) |terminator| {
            const sequence = try std.fmt.bufPrint(&sequence_buf, "\x1b]{d};ignored{s}", .{ command, terminator });
            // Exhaustively split every selector/terminator boundary. All 27
            // reference branches are protocol no-ops; logging in Kitty is
            // diagnostic, not a state transition or an OSC reply.
            for (1..sequence.len) |split| {
                try std.testing.expect(!(try terminal.feed(sequence[0..split])).stateChanged());
                try std.testing.expect(!(try terminal.feed(sequence[split..])).stateChanged());
                try std.testing.expectEqual(baseline, terminal.semanticSequence());
                try std.testing.expectEqual(baseline_content, terminal.contentSequence());
                try std.testing.expectEqual(@as(u8, 0), terminal.consequenceCount());
                try std.testing.expectEqual(@as(usize, 0), terminal.replyBytes().len);
            }
        }
    }
    try std.testing.expect(!(try terminal.feed("\x1b]46;canceled\x18")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b]50;restart\x07")).stateChanged());
    try std.testing.expectEqual(@as(?[]const u8, null), terminal.title());
    try std.testing.expectEqual(@as(usize, 0), terminal.replyBytes().len);

    const payload = try std.testing.allocator.alloc(u8, expected_string_control_bytes - 2);
    defer std.testing.allocator.free(payload);
    @memset(payload, 'x');
    var sequence = std.ArrayList(u8).empty;
    defer sequence.deinit(std.testing.allocator);
    try sequence.appendSlice(std.testing.allocator, "\x1b]46;");
    try sequence.appendSlice(std.testing.allocator, payload[0 .. expected_string_control_bytes - 3]);
    try sequence.append(std.testing.allocator, 0x07);
    try std.testing.expect(!(try terminal.feed(sequence.items)).stateChanged());
    sequence.clearRetainingCapacity();
    try sequence.appendSlice(std.testing.allocator, "\x1b]46;");
    try sequence.appendSlice(std.testing.allocator, payload);
    try sequence.append(std.testing.allocator, 0x07);
    try std.testing.expect(!(try terminal.feed(sequence.items)).stateChanged());
    try std.testing.expectEqual(@as(usize, 0), terminal.replyBytes().len);
    try std.testing.expectEqual(baseline, terminal.semanticSequence());
    try std.testing.expectEqual(baseline_content, terminal.contentSequence());
    try std.testing.expectEqual(@as(u8, 0), terminal.consequenceCount());
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(0, 0));

    // Oversized ignored controls must not poison the following valid OSC,
    // visible text, or the caller's next deterministic observation turn.
    try std.testing.expect((try terminal.feed("\x1b]2;continued\x1b\\Z")).stateChanged());
    try std.testing.expectEqualStrings("continued", terminal.title().?);
    try std.testing.expectEqual(@as(u21, 'Z'), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u8, 0), terminal.consequenceCount());
}

test "working-directory report limit preserves the prior complete value" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("\x1b]7;file://host/stable\x07")).stateChanged());

    const payload = try allocator.alloc(u8, expected_metadata_bytes + 1);
    defer allocator.free(payload);
    @memset(payload, 'x');
    var sequence = std.ArrayList(u8).empty;
    defer sequence.deinit(allocator);
    try sequence.appendSlice(allocator, "\x1b]7;");
    try sequence.appendSlice(allocator, payload[0..expected_metadata_bytes]);
    try sequence.append(allocator, 0x07);
    try std.testing.expect((try terminal.feed(sequence.items)).stateChanged());
    var retained = terminal.workingDirectory().?;
    try std.testing.expectEqual(@as(usize, expected_metadata_bytes), retained.value.len);

    sequence.clearRetainingCapacity();
    try sequence.appendSlice(allocator, "\x1b]7;");
    try sequence.appendSlice(allocator, payload);
    try sequence.append(allocator, 0x07);
    try std.testing.expectError(error.PropertyLimit, terminal.feed(sequence.items));

    retained = terminal.workingDirectory().?;
    try std.testing.expect(retained.kind == .uri);
    try std.testing.expectEqual(@as(usize, expected_metadata_bytes), retained.value.len);
}

test "OSC 0 1 and 2 match libvterm title and icon properties" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();

    const both = try terminal.feed("\x1b]0;Both\x07");
    try std.testing.expect(both.stateChanged());
    try std.testing.expect(both.titleChanged());
    try std.testing.expect(both.iconChanged());
    try std.testing.expectEqualStrings("Both", terminal.title().?);
    try std.testing.expectEqualStrings("Both", terminal.icon().?);

    const title = try terminal.feed("\x1b]2;Title\x07");
    try std.testing.expect(title.stateChanged());
    try std.testing.expect(title.titleChanged());
    try std.testing.expect(!title.iconChanged());

    const icon = try terminal.feed("\x1b]1;Icon\x07");
    try std.testing.expect(icon.stateChanged());
    try std.testing.expect(!icon.titleChanged());
    try std.testing.expect(icon.iconChanged());

    try std.testing.expectEqualStrings("Title", terminal.title().?);
    try std.testing.expectEqualStrings("Icon", terminal.icon().?);
}

test "OSC titles and icons remain commit-only against pinned callback and sanitation policies" {
    for ([_]struct { code: u8, changes_title: bool, changes_icon: bool }{
        .{ .code = 0, .changes_title = true, .changes_icon = true },
        .{ .code = 1, .changes_title = false, .changes_icon = true },
        .{ .code = 2, .changes_title = true, .changes_icon = false },
    }) |case| {
        var terminal = try Terminal.init(std.testing.allocator, 3, 8);
        defer terminal.deinit();
        try feed(&terminal, "\x1b]0;old\x07");
        var buf: [48]u8 = undefined;
        const prefix = try std.fmt.bufPrint(&buf, "\x1b]{d};new", .{case.code});
        try std.testing.expect(!(try terminal.feed(prefix)).stateChanged());
        try std.testing.expectEqualStrings("old", terminal.title().?);
        try std.testing.expectEqualStrings("old", terminal.icon().?);
        const completed = try terminal.feed("\x1b\\");
        try std.testing.expect(completed.stateChanged());
        try std.testing.expectEqual(case.changes_title, completed.titleChanged());
        try std.testing.expectEqual(case.changes_icon, completed.iconChanged());
        try std.testing.expectEqualStrings(if (case.changes_title) "new" else "old", terminal.title().?);
        try std.testing.expectEqualStrings(if (case.changes_icon) "new" else "old", terminal.icon().?);
    }

    // Pinned iTerm2 splits 0/1 into title plus subtitle at a newline and
    // truncates 2 at the first newline; Howl drops embedded OSC C0 bytes.
    // The C0 is neither a live cursor motion nor a retained title byte.
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    try feed(&terminal, "\x1b]0;first\nlast\x07");
    try std.testing.expectEqualStrings("firstlast", terminal.title().?);
    try std.testing.expectEqualStrings("firstlast", terminal.icon().?);
    try feed(&terminal, "\x1b]1;icon\nsubtitle\x07");
    try std.testing.expectEqualStrings("iconsubtitle", terminal.icon().?);
    try feed(&terminal, "\x1b]2;title\nsubtitle\x07");
    try std.testing.expectEqualStrings("titlesubtitle", terminal.title().?);

    // Kitty's host substitutes its default title on empty OSC 2, while
    // Howl preserves the exact empty title as canonical terminal metadata.
    try std.testing.expect((try terminal.feed("\x1b]2;\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings("", terminal.title().?);
}

test "pinned Kitty OSC 1 icon host no-op differs from native retained icon" {
    // Frozen Kitty vt-parser.c::dispatch_osc code 1 calls
    // screen.c::set_icon, but kitty/window.py::icon_changed is pass.
    // Native Howl instead retains icon metadata and notifies its caller.
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    try std.testing.expect(!(try terminal.feed("\x1b]1;owl")).stateChanged());
    const result = try terminal.feed("\x1b\\");
    try std.testing.expect(result.stateChanged() and result.iconChanged());
    try std.testing.expect(!result.titleChanged());
    try std.testing.expectEqualStrings("owl", terminal.icon().?);
    try std.testing.expect(terminal.title() == null);
    try std.testing.expect(!(try terminal.feed("\x1b]1;owl\x07")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b]1;\x07")).stateChanged());
    try std.testing.expectEqualStrings("", terminal.icon().?);
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
}

test "OSC metadata reports only committed replacement and survives split cancellation" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();

    const first = try terminal.feed("\x1b]0;stable\x07");
    try std.testing.expect(first.stateChanged() and first.titleChanged() and first.iconChanged());
    const repeated = try terminal.feed("\x1b]0;stable\x1b\\");
    try std.testing.expect(!repeated.stateChanged());
    try std.testing.expect(!repeated.titleChanged() and !repeated.iconChanged());

    try std.testing.expect(!(try terminal.feed("\x1b]2;split")).stateChanged());
    try std.testing.expect(!(try terminal.feed("-title")).stateChanged());
    const completed = try terminal.feed("\x1b\\");
    try std.testing.expect(completed.stateChanged() and completed.titleChanged() and !completed.iconChanged());
    try std.testing.expectEqualStrings("split-title", terminal.title().?);

    try std.testing.expect(!(try terminal.feed("\x1b]1;discarded\x18")).stateChanged());
    try std.testing.expectEqualStrings("stable", terminal.icon().?);
    const cleared = try terminal.feed("\x1b]1;\x07");
    try std.testing.expect(cleared.stateChanged() and cleared.iconChanged());
    try std.testing.expectEqualStrings("", terminal.icon().?);
}

test "raw OSC title updates terminal title through OSC owner path" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try feed(&terminal, "\x1b]Raw Title\x07");
    try std.testing.expectEqualStrings("Raw Title", terminal.title().?);
}

test "OSC title limit fails without dropping current title" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try feed(&terminal, "\x1b]0;ok\x07");

    const title_len = expected_metadata_bytes + 1;
    const payload = try allocator.alloc(u8, title_len);
    defer allocator.free(payload);
    @memset(payload, 'a');

    var seq = std.ArrayList(u8).empty;
    defer seq.deinit(allocator);
    try seq.appendSlice(allocator, "\x1b]0;");
    try seq.appendSlice(allocator, payload);
    try seq.appendSlice(allocator, "\x07");

    try std.testing.expectError(error.PropertyLimit, feed(&terminal, seq.items));
    try std.testing.expectEqualStrings("ok", terminal.title().?);
}

test "OSC icon limit preserves prior title and icon" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    const initial = try terminal.feed("\x1b]2;title\x07\x1b]1;icon\x07");
    try std.testing.expect(initial.titleChanged());
    try std.testing.expect(initial.iconChanged());
    const payload = try allocator.alloc(u8, expected_metadata_bytes + 1);
    defer allocator.free(payload);
    @memset(payload, 'i');
    var sequence = std.ArrayList(u8).empty;
    defer sequence.deinit(allocator);
    try sequence.appendSlice(allocator, "\x1b]1;");
    try sequence.appendSlice(allocator, payload);
    try sequence.append(allocator, 0x07);

    try std.testing.expectError(error.PropertyLimit, terminal.feed(sequence.items));
    try std.testing.expectEqualStrings("title", terminal.title().?);
    try std.testing.expectEqualStrings("icon", terminal.icon().?);
}

test "OSC 0 bound failure preserves both prior metadata values" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    const seeded = try terminal.feed("\x1b]2;old-title\x07\x1b]1;old-icon\x07");
    try std.testing.expect(seeded.stateChanged());
    try std.testing.expect(seeded.titleChanged());
    try std.testing.expect(seeded.iconChanged());
    const payload = try allocator.alloc(u8, expected_metadata_bytes + 1);
    defer allocator.free(payload);
    @memset(payload, 'b');
    var sequence = std.ArrayList(u8).empty;
    defer sequence.deinit(allocator);
    try sequence.appendSlice(allocator, "\x1b]0;");
    try sequence.appendSlice(allocator, payload);
    try sequence.append(allocator, 0x07);

    try std.testing.expectError(error.PropertyLimit, terminal.feed(sequence.items));
    try std.testing.expectEqualStrings("old-title", terminal.title().?);
    try std.testing.expectEqualStrings("old-icon", terminal.icon().?);
}

test "OSC 0 allocation failure preserves both prior metadata values" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        oscZeroAllocation,
        .{},
    );
}

fn oscZeroAllocation(allocator: std.mem.Allocator) !void {
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    const seeded = try terminal.feed("\x1b]2;old-title\x07\x1b]1;old-icon\x07");
    try std.testing.expect(seeded.stateChanged());
    try std.testing.expect(seeded.titleChanged());
    try std.testing.expect(seeded.iconChanged());
    const summary = terminal.feed("\x1b]0;both\x07") catch |err| {
        try std.testing.expectEqualStrings("old-title", terminal.title().?);
        try std.testing.expectEqualStrings("old-icon", terminal.icon().?);
        return err;
    };
    try std.testing.expect(summary.titleChanged());
    try std.testing.expect(summary.iconChanged());
    try std.testing.expectEqualStrings("both", terminal.title().?);
    try std.testing.expectEqualStrings("both", terminal.icon().?);
}

test "pinned Kitty alternate buffer clears active hyperlink unlike Howl bank-local link" {
    // Pinned kitty/screen.c::screen_toggle_screen_buffer unconditionally
    // sets active_hyperlink_id = 0 on both enter and leave. Howl retains
    // current link state independently per bank, so after returning from
    // DEC 47/1047 it can continue the previous primary hyperlink.
    for ([_][]const u8{ "\x1b[?47", "\x1b[?1047" }) |prefix| {
        var terminal = try Terminal.init(std.testing.allocator, 3, 12);
        defer terminal.deinit();
        try std.testing.expect((try terminal.feed("\x1b]8;;https://example.com\x07A")).stateChanged());
        const initial = terminal.semanticView(0).cellInfoAt(0, 0).attrs.link_id;
        try std.testing.expect(initial != 0);
        var cmd: [32]u8 = undefined;
        const enter = try std.fmt.bufPrint(&cmd, "{s}h", .{prefix});
        try std.testing.expect((try terminal.feed(enter)).stateChanged());
        try std.testing.expect((try terminal.feed("ALT")).stateChanged());
        const leave = try std.fmt.bufPrint(&cmd, "{s}l", .{prefix});
        try std.testing.expect((try terminal.feed(leave)).stateChanged());
        try std.testing.expect((try terminal.feed("B")).stateChanged());
        const view = terminal.semanticView(0);
        try std.testing.expectEqual(@as(u21, 'A'), view.cellAt(0, 0));
        try std.testing.expectEqual(@as(u21, 'B'), view.cellAt(0, 1));
        try std.testing.expectEqual(initial, view.cellInfoAt(0, 1).attrs.link_id);
        try std.testing.expectEqualStrings("https://example.com", terminal.hyperlinkUri(initial).?);
    }
}

test "OSC 8 retains explicit identity separately from URI and exact active mutation" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 20);
    defer terminal.deinit();

    try feed(&terminal, "\x1b]8;id=one;https://example.com\x07a");
    try feed(&terminal, "\x1b]8;id=two;https://example.com\x1b\\b");
    try feed(&terminal, "\x1b]8;target=_blank:id=one;https://example.com\x07c");

    const view = terminal.semanticView(0);
    const first = view.cellInfoAt(0, 0).attrs.link_id;
    const second = view.cellInfoAt(0, 1).attrs.link_id;
    const third = view.cellInfoAt(0, 2).attrs.link_id;
    try std.testing.expect(first != 0);
    try std.testing.expect(first != second);
    try std.testing.expectEqual(first, third);
    try std.testing.expectEqualStrings("https://example.com", terminal.hyperlinkUri(first).?);
    try std.testing.expectEqualStrings("https://example.com", terminal.hyperlinkUri(second).?);

    try std.testing.expect(!(try terminal.feed("\x1b]8;id=one;https://example.com\x07")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b]8;;\x07")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b]8;;\x07")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b]8;missing-separator\x07")).stateChanged());
}

test "OSC 8 hyperlink remains active through SGR reset until explicit close" {
    for ([_][]const u8{ "\x1b[0m", "\x1b[m" }) |reset_sgr| {
        var terminal = try Terminal.init(std.testing.allocator, 2, 12);
        defer terminal.deinit();
        try feed(&terminal, "\x1b]8;id=guide;https://example.com\x1b\\\x1b[1\"q\x1b[31;1mA");
        const first = terminal.semanticView(0).cellInfoAt(0, 0);
        try std.testing.expect(first.attrs.link_id != 0);
        try std.testing.expect(first.attrs.bold);
        try std.testing.expect(first.attrs.protected == .dec);
        try feed(&terminal, reset_sgr);
        try feed(&terminal, "B\x1b]8;;\x1b\\C");
        const view = terminal.semanticView(0);
        const second = view.cellInfoAt(0, 1);
        const third = view.cellInfoAt(0, 2);
        try std.testing.expectEqual(first.attrs.link_id, second.attrs.link_id);
        try std.testing.expectEqual(@as(u32, 0), third.attrs.link_id);
        try std.testing.expect(second.attrs.protected == .dec);
        try std.testing.expect(!second.attrs.bold);
        try std.testing.expect(second.attrs.fg.kind == .default);
        try std.testing.expectEqualStrings("https://example.com", terminal.hyperlinkUri(second.attrs.link_id).?);
    }
}

test "terminal metadata owns exact screen resize and reset lifetime" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed(
        "\x1b]0;name\x07" ++
            "\x1b]7;file://host/work\x1b\\" ++
            "\x1b]1337;RemoteHost=user@host\x07" ++
            "\x1b]1337;ShellIntegrationVersion=20;shell=bash\x1b\\" ++
            "\x1b]133;A;prompt\x07" ++
            "\x1b]8;id=docs;https://example.com\x07X",
    )).stateChanged());
    const link_id = terminal.semanticView(0).cellInfoAt(0, 0).attrs.link_id;
    try std.testing.expect(link_id != 0);

    try std.testing.expect((try terminal.feed("\x1b[?1049h\x1b[?1049l")).stateChanged());
    try terminal.resize(3, 10);
    try std.testing.expectEqualStrings("name", terminal.title().?);
    try std.testing.expectEqualStrings("name", terminal.icon().?);
    try std.testing.expectEqualStrings("file://host/work", terminal.workingDirectory().?.value);
    try std.testing.expectEqualStrings("user@host", terminal.remoteHost().?);
    try std.testing.expectEqual(@as(u32, 20), terminal.shellIntegration().?.version);
    try std.testing.expectEqualStrings("bash", terminal.shellIntegration().?.shell.?);
    try std.testing.expectEqual(@as(u64, 1), terminal.shellMark().generation);
    try std.testing.expectEqual(link_id, terminal.semanticView(0).cellInfoAt(0, 0).attrs.link_id);

    try std.testing.expect((try terminal.feed("\x1bc")).stateChanged());
    try std.testing.expectEqualStrings("name", terminal.title().?);
    try std.testing.expectEqualStrings("name", terminal.icon().?);
    try std.testing.expect(terminal.workingDirectory() == null);
    try std.testing.expectEqualStrings("user@host", terminal.remoteHost().?);
    try std.testing.expectEqual(@as(u32, 20), terminal.shellIntegration().?.version);
    try std.testing.expectEqual(@as(u64, 1), terminal.shellMark().generation);
    try std.testing.expectEqual(@as(u32, 0), terminal.semanticView(0).cellInfoAt(0, 0).attrs.link_id);
    try std.testing.expectEqualStrings("https://example.com", terminal.hyperlinkUri(link_id).?);
}

test "Windows Terminal OSC 52 selectors and queries differ from bounded Howl clipboard policy" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    // WT ignores arbitrary selector text; Howl validates and bounds it.
    try std.testing.expect(!(try terminal.feed("\x1b]52;anything;Zm9v\x07")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b]52;c;Zm9v===\x07")).stateChanged());
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());

    // Accepted queries are retained for explicit caller policy; the direct
    // app chooses an empty reply. Pinned WT remains silent instead.
    try std.testing.expect((try terminal.feed("\x1b]52;c;?\x1b\\")).stateChanged());
    const query = terminal.consequenceHead().?.clipboard;
    try std.testing.expect(query.kind == .query);
    try std.testing.expectEqualStrings("c", query.selection);
    try std.testing.expect(try terminal.replyClipboard(query.generation, ""));
    try std.testing.expectEqualStrings("\x1b]52;c;\x1b\\", terminal.replyBytes());
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());

    // Ordinary WT-compatible replacement remains bounded and caller-owned.
    try std.testing.expect((try terminal.feed("\x1b]52;c;Zm9v\x07")).stateChanged());
    const request = terminal.consequenceHead().?.clipboard;
    try std.testing.expect(request.kind == .set);
    const copied = (try terminal.takeClipboard(request.generation, std.testing.allocator)).?;
    defer std.testing.allocator.free(copied);
    try std.testing.expectEqualStrings("foo", copied);
}

test "Ghostty and newer Kitty OSC 7501 status family is not advertised by Howl" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    try feed(&terminal, "A");
    const original = terminal.semanticSequence();
    // No opt-in status capability callback, status index, or status lifecycle.
    // The parser still consumes an unknown OSC control without printing it.
    for ([_][]const u8{
        "\x1b]7501;?\x1b\\",
        "\x1b]7501;state=working:id=sync:progress=40\x07",
        "\x1b]7501;state=clear:id=sync\x1b\\",
    }) |sequence| {
        try std.testing.expect(!(try terminal.feed(sequence)).stateChanged());
        try std.testing.expectEqual(original, terminal.semanticSequence());
        try std.testing.expectEqualStrings("", terminal.replyBytes());
        try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
    }
    try std.testing.expectEqual(@as(u21, 'A'), terminal.semanticView(0).cellAt(0, 0));
}

test "OSC 7501 opt-in status reports are typed FIFO and queries advertise only with a consumer" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    // With no explicit host effect this family must remain silent, including
    // queries and even otherwise valid reports.
    try std.testing.expect(!(try terminal.feed("\x1b]7501;?\x07")).stateChanged());
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
    try std.testing.expectEqualStrings("", terminal.replyBytes());

    terminal.setProgramStatusConsumer(true);
    const response = "\x1b]7501;?:states=idle,working,done,blocked,error:kinds=permission,question,auth";
    try std.testing.expect(!(try terminal.feed("\x1b]7501;?")).stateChanged());
    try std.testing.expect((try terminal.feed("\x07")).stateChanged());
    try std.testing.expectEqualStrings(response ++ "\x07", terminal.replyBytes());
    try consumeReplies(&terminal);
    try std.testing.expect((try terminal.feed("\x1b]7501;?\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings(response ++ "\x1b\\", terminal.replyBytes());
    try consumeReplies(&terminal);

    try std.testing.expect((try terminal.feed(
        "\x1b]7501;state=blocked:kind=permission:id=tf/plan:app=terraform:progress=42:msg=QXBwbHk=\x1b\\",
    )).stateChanged());
    try std.testing.expectEqual(@as(u16, 1), terminal.consequenceCount());
    const first = terminal.consequenceHead().?.program_status;
    const record = first.action.report;
    try std.testing.expect(record.state == .blocked);
    try std.testing.expect(record.kind.? == .permission);
    try std.testing.expectEqualStrings("tf/plan", record.id);
    try std.testing.expectEqual(@as(?u8, 42), record.progress);
    var decoded: [Terminal.ProgramStatus.max_msg_bytes]u8 = undefined;
    try std.testing.expectEqualStrings("Apply", record.messageText(&decoded).?);
    try terminal.consumeConsequence(first.generation);
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());

    try std.testing.expect((try terminal.feed("\x1b]7501;state=clear:id=tf\x07")).stateChanged());
    const clear = terminal.consequenceHead().?.program_status;
    try std.testing.expectEqualStrings("tf", clear.action.clear);
    try terminal.consumeConsequence(clear.generation);
    try std.testing.expect(!(try terminal.feed("\x1b]7501;process-exited\x07")).stateChanged());
    try std.testing.expect(terminal.consequenceHead() == null);

    // Invalid id does not turn into a root clear, and unknown OSC bytes
    // cannot acquire a host effect even with status consumption enabled.
    try std.testing.expect(!(try terminal.feed("\x1b]7501;state=clear:id=a//b\x1b\\")).stateChanged());
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
    terminal.setProgramStatusConsumer(false);
    try std.testing.expect(!(try terminal.feed("\x1b]7501;?\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings("", terminal.replyBytes());
}

test "OSC 7501 bounded status FIFO preserves exact head under pressure" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    terminal.setProgramStatusConsumer(true);
    for (0..8) |_| try feed(&terminal, "\x1b]7501;state=working:id=one\x1b\\");
    try std.testing.expectEqual(@as(u16, 8), terminal.consequenceCount());
    const old = terminal.consequenceHead().?.program_status;
    try std.testing.expectEqualStrings("one", old.action.report.id);
    try std.testing.expectError(error.ConsequencePressure, terminal.feed("\x1b]7501;state=done:id=other\x1b\\"));
    try std.testing.expectEqual(@as(u16, 8), terminal.consequenceCount());
    try std.testing.expectEqualStrings("one", terminal.consequenceHead().?.program_status.action.report.id);
    try terminal.consumeConsequence(old.generation);
    try feed(&terminal, "\x1b]7501;state=done:id=other\x1b\\");
    try std.testing.expectEqual(@as(u16, 8), terminal.consequenceCount());
    for (0..8) |_| {
        const next = terminal.consequenceHead().?.program_status;
        try terminal.consumeConsequence(next.generation);
    }
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
}

test "OSC 7501 host consumer observes reset generation without claiming a UI" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    terminal.setProgramStatusConsumer(true);
    try feed(&terminal, "\x1b]7501;state=working:id=job:progress=70\x1b\\");
    const old = terminal.consequenceHead().?.program_status;
    const old_generation = old.reset_generation;
    const old_id = old.generation;
    try feed(&terminal, "\x1bc");
    try std.testing.expect(terminal.resetSequence() > old_generation);
    try std.testing.expectEqual(old_id, terminal.consequenceHead().?.program_status.generation);
    try std.testing.expectEqual(old_generation, terminal.consequenceHead().?.program_status.reset_generation);
    try terminal.consumeConsequence(old_id);
    try feed(&terminal, "\x1b]7501;state=blocked:id=job:kind=auth\x1b\\");
    const fresh = terminal.consequenceHead().?.program_status;
    try std.testing.expect(fresh.generation > old_id);
    try std.testing.expect(fresh.reset_generation > old_generation);
    try std.testing.expect(fresh.action.report.kind.? == .auth);
}

test "OSC 7501 feature query reply quota rolls back without changing pending statuses" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 2, 8);
    defer terminal.deinit();
    terminal.setProgramStatusConsumer(true);
    try feed(&terminal, "\x1b]7501;state=working:id=job\x1b\\");
    const id = terminal.consequenceHead().?.program_status.generation;
    const reply = "\x1b]7501;?:states=idle,working,done,blocked,error:kinds=permission,question,auth\x1b\\";
    const before = try reply_fill.fill(&terminal, allocator, 64 * 1024 - reply.len + 1, false);
    defer allocator.free(before);
    try std.testing.expectError(error.ReplyLimit, terminal.feed("\x1b]7501;?\x1b\\"));
    try std.testing.expectEqualSlices(u8, before, terminal.replyBytes());
    try std.testing.expectEqual(id, terminal.consequenceHead().?.program_status.generation);
    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    try feed(&terminal, "\x1b]7501;?\x1b\\");
    try std.testing.expectEqualStrings(reply, terminal.replyBytes());
    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    try terminal.consumeConsequence(id);
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
}

test "OSC 52 produces pending clipboard request" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 16);
    defer terminal.deinit();

    try feed(&terminal, "\x1b]52;c;Zm9v\x07");
    const request = terminal.consequenceHead().?.clipboard;
    try std.testing.expect(request.kind == .set);
    try std.testing.expectEqualStrings("c", request.selection);
    try std.testing.expectEqualStrings("c;Zm9v", request.payload);
    const clipboard = (try terminal.takeClipboard(request.generation, allocator)).?;
    defer allocator.free(clipboard);
    try std.testing.expect(terminal.consequenceHead() == null);
}

test "OSC 52 decoded clipboard drain clears pending request" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 16);
    defer terminal.deinit();

    try feed(&terminal, "\x1b]52;c;SG93bA==\x07");

    const request = terminal.consequenceHead().?.clipboard;
    const text = (try terminal.takeClipboard(request.generation, allocator)).?;
    defer allocator.free(text);
    try std.testing.expectEqualStrings("Howl", text);
    try std.testing.expect(terminal.consequenceHead() == null);
}

test "OSC 52 query is retained for exact transactional caller reply" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 16);
    defer terminal.deinit();
    try std.testing.expect(!(try terminal.feed("\x1b]52;cp")).stateChanged());
    try std.testing.expect((try terminal.feed(";?\x1b\\")).stateChanged());
    var request = terminal.consequenceHead().?.clipboard;
    try std.testing.expectEqual(@as(?[]u8, null), try terminal.takeClipboard(
        request.generation,
        allocator,
    ));
    try std.testing.expect(request.kind == .query);
    try std.testing.expectEqualStrings("cp", request.selection);
    try std.testing.expect((try terminal.feed("\x1bc")).stateChanged());
    try std.testing.expectEqualStrings("cp", terminal.consequenceHead().?.clipboard.selection);
    try std.testing.expect(try terminal.replyClipboard(request.generation, "A\x00B"));
    try std.testing.expectEqualStrings("\x1b]52;cp;QQBC\x1b\\", terminal.replyBytes());
    try std.testing.expect(terminal.consequenceHead() == null);
    try std.testing.expectError(error.StaleClipboardRequest, terminal.replyClipboard(
        request.generation,
        "unused",
    ));

    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    try std.testing.expect((try terminal.feed("\x1b G\x9d52;;?\x9c")).stateChanged());
    request = terminal.consequenceHead().?.clipboard;
    try std.testing.expectEqualStrings("", request.selection);
    try std.testing.expect(try terminal.replyClipboard(request.generation, ""));
    try std.testing.expectEqualStrings("\x9d52;;\x9c", terminal.replyBytes());
    try std.testing.expect(terminal.consequenceHead() == null);
}

test "OSC 52 caller copy preserves FIFO until exact consumption" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 16);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed(
        "\x1b]52;c;T25l\x07" ++
            "\x1b]52;c;?\x1b\\",
    )).stateChanged());

    const request = terminal.consequenceHead().?.clipboard;
    const copied = (try terminal.copyClipboard(
        request.generation,
        allocator,
        3,
    )).?;
    defer allocator.free(copied);
    try std.testing.expectEqualStrings("One", copied);
    try std.testing.expectEqual(request.generation, terminal.consequenceHead().?.clipboard.generation);
    try std.testing.expectError(
        error.ClipboardLimit,
        terminal.copyClipboard(request.generation, allocator, 2),
    );
    try std.testing.expectEqual(request.generation, terminal.consequenceHead().?.clipboard.generation);
    try terminal.consumeConsequence(request.generation);
}

test "OSC 52 rejects malformed selections and base64 without replacing a request" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 16);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b]52;c;b2xk\x07")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b]52;x;bmV3\x07")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b]52;c;!!!!\x07")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b]52;c;?trailing\x07")).stateChanged());
    const request = terminal.consequenceHead().?.clipboard;
    try std.testing.expectEqualStrings("c;b2xk", request.payload);
    const decoded = (try terminal.takeClipboard(request.generation, allocator)).?;
    defer allocator.free(decoded);
    try std.testing.expectEqualStrings("old", decoded);
}

test "OSC 52 reply bounds preserve query and prior pending output" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 16);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("\x1b]52;p;?\x07")).stateChanged());
    const request = terminal.consequenceHead().?.clipboard;

    const fill = try reply_fill.fill(&terminal, allocator, expected_reply_bytes - 1, false);
    defer allocator.free(fill);
    try std.testing.expectError(
        error.ReplyLimit,
        terminal.replyClipboard(request.generation, "Howl"),
    );
    try std.testing.expectEqualStrings("p", terminal.consequenceHead().?.clipboard.selection);
    try std.testing.expectEqualSlices(u8, fill, terminal.replyBytes());

    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    const oversized = try allocator.alloc(u8, expected_clipboard_reply_bytes + 1);
    defer allocator.free(oversized);
    @memset(oversized, 'z');
    try std.testing.expectError(
        error.ConsequenceLimit,
        terminal.replyClipboard(request.generation, oversized),
    );
    try std.testing.expectEqualStrings("p", terminal.consequenceHead().?.clipboard.selection);
    try std.testing.expectEqualStrings("", terminal.replyBytes());

    try std.testing.expect(try terminal.replyClipboard(
        request.generation,
        oversized[0..expected_clipboard_reply_bytes],
    ));
    try std.testing.expect(terminal.replyBytes().len <= expected_reply_bytes);
    try std.testing.expect(terminal.consequenceHead() == null);
}

test "OSC 52 retains ordered sets and queries until exact head consumption" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 16);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b]52;c;")).stateChanged());
    try std.testing.expect((try terminal.feed(
        "T25l\x07" ++
            "\x1b]52;p;?\x1b\\" ++
            "\x9d52;c;VHdv\x9c",
    )).stateChanged());
    try std.testing.expectEqual(@as(u8, 3), terminal.consequenceCount());
    var request = terminal.consequenceHead().?.clipboard;
    try std.testing.expectEqual(@as(u64, 1), request.generation);
    try std.testing.expect(request.kind == .set);
    try std.testing.expectEqualStrings("c", request.selection);
    try std.testing.expectError(
        error.StaleClipboardRequest,
        terminal.takeClipboard(2, allocator),
    );

    const first = (try terminal.takeClipboard(request.generation, allocator)).?;
    defer allocator.free(first);
    try std.testing.expectEqualStrings("One", first);
    try std.testing.expectEqual(@as(u8, 2), terminal.consequenceCount());
    request = terminal.consequenceHead().?.clipboard;
    try std.testing.expectEqual(@as(u64, 2), request.generation);
    try std.testing.expect(request.kind == .query);
    try std.testing.expectError(error.ReplyRequired, terminal.consumeConsequence(2));
    try std.testing.expectError(
        error.StaleClipboardRequest,
        terminal.replyClipboard(3, "wrong"),
    );
    try std.testing.expectEqualStrings("", terminal.replyBytes());
    try std.testing.expect(try terminal.replyClipboard(2, "reply"));
    try std.testing.expectEqualStrings("\x1b]52;p;cmVwbHk=\x1b\\", terminal.replyBytes());

    request = terminal.consequenceHead().?.clipboard;
    try std.testing.expectEqual(@as(u64, 3), request.generation);
    const second = (try terminal.takeClipboard(request.generation, allocator)).?;
    defer allocator.free(second);
    try std.testing.expectEqualStrings("Two", second);
    try std.testing.expect(terminal.consequenceHead() == null);

    try std.testing.expect((try terminal.feed("\x1b]52;c;QQ==\x07")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1bc\x1b[?1049h\x1b[?1049l")).stateChanged());
    try terminal.resize(4, 20);
    try std.testing.expectEqual(@as(u64, 4), terminal.consequenceHead().?.clipboard.generation);
    try std.testing.expectEqual(@as(u8, 1), terminal.consequenceCount());
}

test "OSC 52 queue and aggregate bounds preserve identity and wrap" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 16);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b]52;c;QQ==\x07")).stateChanged());
    try terminal.consumeConsequence(1);
    for (0..expected_clipboard_capacity) |_| {
        try std.testing.expect((try terminal.feed("\x1b]52;c;Qg==\x07")).stateChanged());
    }
    try std.testing.expectEqual(expected_clipboard_capacity, terminal.consequenceCount());
    try std.testing.expectEqual(@as(u64, 2), terminal.consequenceHead().?.clipboard.generation);
    try std.testing.expectError(error.ConsequencePressure, terminal.feed("\x1b]52;c;Qw==\x07"));
    try std.testing.expectEqual(expected_clipboard_capacity, terminal.consequenceCount());
    try std.testing.expectEqual(@as(u64, 2), terminal.consequenceHead().?.clipboard.generation);

    for (2..10) |generation| try terminal.consumeConsequence(@intCast(generation));
    try std.testing.expect(terminal.consequenceHead() == null);
    try std.testing.expect((try terminal.feed("\x1b]52;c;RA==\x07")).stateChanged());
    try std.testing.expectEqual(@as(u64, 10), terminal.consequenceHead().?.clipboard.generation);
    try terminal.consumeConsequence(10);

    const payload = try allocator.alloc(u8, expected_clipboard_request_bytes);
    defer allocator.free(payload);
    @memset(payload, 'A');
    payload[0] = 'c';
    payload[1] = 'p';
    payload[2] = 'q';
    payload[3] = ';';
    var sequence = std.ArrayList(u8).empty;
    defer sequence.deinit(allocator);
    try sequence.appendSlice(allocator, "\x1b]52;");
    try sequence.appendSlice(allocator, payload);
    try sequence.append(allocator, 0x07);
    try std.testing.expect((try terminal.feed(sequence.items)).stateChanged());
    try std.testing.expectEqual(@as(u64, 11), terminal.consequenceHead().?.clipboard.generation);
    try std.testing.expectError(error.ConsequencePressure, terminal.feed("\x1b]52;c;RQ==\x07"));
    try std.testing.expectEqual(@as(u64, 11), terminal.consequenceHead().?.clipboard.generation);
    try std.testing.expectEqual(@as(u8, 1), terminal.consequenceCount());
    try terminal.consumeConsequence(11);
}

test "Kitty OSC 5522 shares ordered clipboard admission without caller policy" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 16);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b]5522;type=wr")).stateChanged());
    try std.testing.expect((try terminal.feed("ite\x1b\\")).stateChanged());
    try std.testing.expect((try terminal.feed(
        "\x1b]52;c;?\x07" ++
            "\x1b]5522;type=read;dGV4dC9wbGFpbg==\x07",
    )).stateChanged());
    try std.testing.expectEqual(@as(u8, 3), terminal.consequenceCount());

    var request = terminal.consequenceHead().?.clipboard;
    try std.testing.expectEqual(@as(u64, 1), request.generation);
    try std.testing.expect(request.protocol == .kitty_5522);
    try std.testing.expect(request.kind == .packet);
    try std.testing.expectEqualStrings("", request.selection);
    try std.testing.expectEqualStrings("type=write", request.payload);
    try std.testing.expect(!(try terminal.replyClipboard(request.generation, "ignored")));
    try std.testing.expectEqual(@as(?[]u8, null), try terminal.takeClipboard(
        request.generation,
        std.testing.allocator,
    ));
    try std.testing.expectEqual(@as(u8, 3), terminal.consequenceCount());
    try terminal.consumeConsequence(request.generation);

    request = terminal.consequenceHead().?.clipboard;
    try std.testing.expectEqual(@as(u64, 2), request.generation);
    try std.testing.expect(request.protocol == .osc52);
    try std.testing.expect(request.kind == .query);
    try std.testing.expectEqualStrings("c", request.selection);
    try std.testing.expectEqualStrings("c;?", request.payload);
    try std.testing.expect(try terminal.replyClipboard(request.generation, "A\x00B"));
    try std.testing.expectEqualStrings("\x1b]52;c;QQBC\x1b\\", terminal.replyBytes());
    try consumeReplies(&terminal);

    request = terminal.consequenceHead().?.clipboard;
    try std.testing.expectEqual(@as(u64, 3), request.generation);
    try std.testing.expect(request.protocol == .kitty_5522);
    try std.testing.expectEqualStrings("type=read;dGV4dC9wbGFpbg==", request.payload);
    try std.testing.expectError(error.StaleConsequence, terminal.consumeConsequence(2));
    try terminal.consumeConsequence(3);
    try std.testing.expect(terminal.consequenceHead() == null);

    try std.testing.expect((try terminal.feed("\x9d5522;type=wdata:mime=dGV4dA==;QQ==\x9c")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1bc\x1b[?1049h\x1b[?1049l")).stateChanged());
    try terminal.resize(4, 20);
    try std.testing.expectEqual(@as(u64, 4), terminal.consequenceHead().?.clipboard.generation);
    try std.testing.expectEqualStrings(
        "type=wdata:mime=dGV4dA==;QQ==",
        terminal.consequenceHead().?.clipboard.payload,
    );
}

test "Kitty OSC 5522 packet and FIFO bounds preserve prior occurrences" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 16);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b]5522;type=write\x1b\\")).stateChanged());
    try terminal.consumeConsequence(1);

    const payload = try allocator.alloc(u8, expected_clipboard_packet_bytes + 1);
    defer allocator.free(payload);
    @memset(payload, 'x');
    var sequence = std.ArrayList(u8).empty;
    defer sequence.deinit(allocator);
    try sequence.appendSlice(allocator, "\x1b]5522;");
    try sequence.appendSlice(allocator, payload[0..expected_clipboard_packet_bytes]);
    try sequence.appendSlice(allocator, "\x1b\\");
    const split = sequence.items.len / 2;
    try std.testing.expect(!(try terminal.feed(sequence.items[0..split])).stateChanged());
    try std.testing.expect((try terminal.feed(sequence.items[split..])).stateChanged());
    for (0..expected_clipboard_capacity - 1) |_| {
        try std.testing.expect((try terminal.feed("\x1b]5522;type=wdata\x1b\\")).stateChanged());
    }
    try std.testing.expectEqual(expected_clipboard_capacity, terminal.consequenceCount());
    try std.testing.expectEqual(@as(u64, 2), terminal.consequenceHead().?.clipboard.generation);
    try std.testing.expectEqual(
        @as(usize, expected_clipboard_packet_bytes),
        terminal.consequenceHead().?.clipboard.payload.len,
    );
    try std.testing.expectError(error.ConsequencePressure, terminal.feed("\x1b]52;c;QQ==\x07"));
    try std.testing.expectEqual(@as(u64, 2), terminal.consequenceHead().?.clipboard.generation);
    try std.testing.expectEqual(expected_clipboard_capacity, terminal.consequenceCount());

    for (0..expected_clipboard_capacity) |_| {
        const head = terminal.consequenceHead().?.clipboard;
        try terminal.consumeConsequence(head.generation);
    }
    try std.testing.expect(terminal.consequenceHead() == null);
    try std.testing.expect((try terminal.feed("\x1b]5522;type=read;Lg==\x1b\\")).stateChanged());
    try std.testing.expectEqual(@as(u64, 10), terminal.consequenceHead().?.clipboard.generation);
    try terminal.consumeConsequence(10);

    sequence.clearRetainingCapacity();
    try sequence.appendSlice(allocator, "\x1b]5522;");
    try sequence.appendSlice(allocator, payload);
    try sequence.appendSlice(allocator, "\x1b\\");
    try std.testing.expect(!(try terminal.feed(sequence.items)).stateChanged());
    try std.testing.expect(terminal.consequenceHead() == null);
}

test "iTerm and Kitty file transfers retain one opaque ordered stream" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 16);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b]1337;MultipartFi")).stateChanged());
    try std.testing.expect((try terminal.feed(
        "le=name=ZmlsZQ==\x1b\\" ++
            "\x1b]5113;ac=send;id=1;d=QQ==\x1b\\" ++
            "\x1b]1337;FilePart=Qg==\x07" ++
            "\x1b]1337;FileEnd=done\x1b\\",
    )).stateChanged());
    try std.testing.expectEqual(@as(u8, 4), terminal.consequenceCount());

    const expected = [_]struct { protocol: Terminal.FileTransferProtocol, payload: []const u8 }{
        .{ .protocol = .iterm2_1337, .payload = "MultipartFile=name=ZmlsZQ==" },
        .{ .protocol = .kitty_5113, .payload = "ac=send;id=1;d=QQ==" },
        .{ .protocol = .iterm2_1337, .payload = "FilePart=Qg==" },
        .{ .protocol = .iterm2_1337, .payload = "FileEnd=done" },
    };
    try std.testing.expectError(error.StaleConsequence, terminal.consumeConsequence(2));
    for (expected, 1..) |item, generation| {
        const packet = terminal.consequenceHead().?.file_transfer;
        try std.testing.expectEqual(@as(u64, @intCast(generation)), packet.generation);
        try std.testing.expect(packet.protocol == item.protocol);
        try std.testing.expectEqualStrings(item.payload, packet.payload);
        try terminal.consumeConsequence(packet.generation);
    }
    try std.testing.expect(terminal.consequenceHead() == null);

    try std.testing.expect((try terminal.feed("\x9d5113;ac=send;id=2\x9c")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1bc\x1b[?1049h\x1b[?1049l")).stateChanged());
    try terminal.resize(4, 20);
    const retained = terminal.consequenceHead().?.file_transfer;
    try std.testing.expectEqual(@as(u64, 5), retained.generation);
    try std.testing.expectEqualStrings("ac=send;id=2", retained.payload);
}

test "opaque file-transfer bounds preserve FIFO identity and wrap" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 16);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b]5113;first\x1b\\")).stateChanged());
    try terminal.consumeConsequence(1);
    const payload = try allocator.alloc(u8, expected_file_transfer_bytes + 1);
    defer allocator.free(payload);
    @memset(payload, 'x');
    var sequence = std.ArrayList(u8).empty;
    defer sequence.deinit(allocator);
    try sequence.appendSlice(allocator, "\x1b]5113;");
    try sequence.appendSlice(allocator, payload[0..expected_file_transfer_bytes]);
    try sequence.appendSlice(allocator, "\x1b\\");
    const split = sequence.items.len / 2;
    try std.testing.expect(!(try terminal.feed(sequence.items[0..split])).stateChanged());
    try std.testing.expect((try terminal.feed(sequence.items[split..])).stateChanged());
    for (0..expected_file_transfer_capacity - 1) |_| {
        try std.testing.expect((try terminal.feed("\x1b]1337;FilePart=QQ==\x1b\\")).stateChanged());
    }
    try std.testing.expectEqual(expected_file_transfer_capacity, terminal.consequenceCount());
    try std.testing.expectEqual(@as(u64, 2), terminal.consequenceHead().?.file_transfer.generation);
    try std.testing.expectEqual(@as(usize, expected_file_transfer_bytes), terminal.consequenceHead().?.file_transfer.payload.len);
    try std.testing.expectError(error.ConsequencePressure, terminal.feed("\x1b]5113;rejected\x1b\\"));
    try std.testing.expectEqual(@as(u64, 2), terminal.consequenceHead().?.file_transfer.generation);
    try std.testing.expectEqual(expected_file_transfer_capacity, terminal.consequenceCount());

    for (0..expected_file_transfer_capacity) |_| {
        const packet = terminal.consequenceHead().?.file_transfer;
        try terminal.consumeConsequence(packet.generation);
    }
    try std.testing.expect((try terminal.feed("\x1b]5113;after\x1b\\")).stateChanged());
    try std.testing.expectEqual(@as(u64, 10), terminal.consequenceHead().?.file_transfer.generation);
    try terminal.consumeConsequence(10);

    const iterm_payload = try allocator.alloc(u8, expected_iterm_file_transfer_bytes + 1);
    defer allocator.free(iterm_payload);
    @memset(iterm_payload, 'x');
    @memcpy(iterm_payload[0.."FilePart=".len], "FilePart=");
    sequence.clearRetainingCapacity();
    try sequence.appendSlice(allocator, "\x1b]1337;");
    try sequence.appendSlice(allocator, iterm_payload[0..expected_iterm_file_transfer_bytes]);
    try sequence.appendSlice(allocator, "\x1b\\");
    try std.testing.expect((try terminal.feed(sequence.items)).stateChanged());
    try std.testing.expectEqual(@as(u64, 11), terminal.consequenceHead().?.file_transfer.generation);
    try terminal.consumeConsequence(11);
    sequence.clearRetainingCapacity();
    try sequence.appendSlice(allocator, "\x1b]1337;");
    try sequence.appendSlice(allocator, iterm_payload);
    try sequence.appendSlice(allocator, "\x1b\\");
    try std.testing.expect(!(try terminal.feed(sequence.items)).stateChanged());
    try std.testing.expect(terminal.consequenceHead() == null);

    sequence.clearRetainingCapacity();
    try sequence.appendSlice(allocator, "\x1b]5113;");
    try sequence.appendSlice(allocator, payload);
    try sequence.appendSlice(allocator, "\x1b\\");
    try std.testing.expect(!(try terminal.feed(sequence.items)).stateChanged());
    try std.testing.expect(terminal.consequenceHead() == null);
}

test "shell integration OSC 133 records latest mark" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try feed(&terminal, "\x1b]133;C;cmdline=ls\x07\x1b]133;D;2\x07");

    const mark = terminal.shellMark();
    try std.testing.expectEqual(@as(u64, 2), mark.generation);
    try std.testing.expectEqual(@as(u8, 'D'), mark.kind);
    try std.testing.expectEqual(@as(?i32, 2), mark.status);
    try std.testing.expectEqualStrings("2", mark.metadata);

    try feed(&terminal, "\x1b]133;Z;ignored\x07");
    try std.testing.expectEqual(@as(u64, 2), terminal.shellMark().generation);
}

test "OSC 133 retains exact metadata and finds positional exit status" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b]133;D;aid=nested;")).stateChanged());
    try std.testing.expectEqual(@as(u64, 0), terminal.shellMark().generation);
    try std.testing.expect((try terminal.feed("7;cl=done\x1b\\")).stateChanged());
    var mark = terminal.shellMark();
    try std.testing.expectEqual(@as(u64, 1), mark.generation);
    try std.testing.expectEqual(@as(u8, 'D'), mark.kind);
    try std.testing.expectEqual(@as(?i32, 7), mark.status);
    try std.testing.expectEqualStrings("aid=nested;7;cl=done", mark.metadata);

    try std.testing.expect((try terminal.feed("\x9d133;D;;-3;aid=second\x9c")).stateChanged());
    mark = terminal.shellMark();
    try std.testing.expectEqual(@as(u64, 2), mark.generation);
    try std.testing.expectEqual(@as(?i32, -3), mark.status);
    try std.testing.expectEqualStrings(";-3;aid=second", mark.metadata);

    try std.testing.expect((try terminal.feed("\x1b]133;D;aid=only;broken\x07")).stateChanged());
    mark = terminal.shellMark();
    try std.testing.expectEqual(@as(u64, 3), mark.generation);
    try std.testing.expectEqual(@as(?i32, null), mark.status);
    try std.testing.expectEqualStrings("aid=only;broken", mark.metadata);

    try std.testing.expect((try terminal.feed("\x1b]133;C;cmdline=exit 7\x07")).stateChanged());
    mark = terminal.shellMark();
    try std.testing.expectEqual(@as(u64, 4), mark.generation);
    try std.testing.expectEqual(@as(u8, 'C'), mark.kind);
    try std.testing.expectEqual(@as(?i32, null), mark.status);
    try std.testing.expectEqualStrings("cmdline=exit 7", mark.metadata);

    try std.testing.expect((try terminal.feed("\x1bc\x1b[?1049h\x1b[?1049l")).stateChanged());
    mark = terminal.shellMark();
    try std.testing.expectEqual(@as(u64, 4), mark.generation);
    try std.testing.expectEqualStrings("cmdline=exit 7", mark.metadata);
}

test "OSC notifications retain ordered bounded caller-neutral occurrences" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b]9;hel")).stateChanged() == false);
    try std.testing.expect(terminal.consequenceHead() == null);
    try std.testing.expect((try terminal.feed("lo\x07")).stateChanged());
    var notification = terminal.consequenceHead().?.notification;
    try std.testing.expectEqual(@as(u64, 1), notification.generation);
    try std.testing.expectEqual(Terminal.NotificationKind.message, notification.kind);
    try std.testing.expectEqual(@as(u16, 9), notification.command);
    try std.testing.expectEqualStrings("hello", notification.payload);

    try std.testing.expect((try terminal.feed(
        "\x1b]99;i=one:d=0;body\x1b\\" ++
            "\x9d777;notify;title;body\x9c" ++
            "\x1b]1337;Notification=rich body\x07" ++
            "\x1b]1337;StealFocus\x1b\\" ++
            "\x1b]1337;RequestAttention=fireworks\x07" ++
            "\x1b]9;last\x07",
    )).stateChanged());
    try std.testing.expectEqual(@as(u8, 7), terminal.consequenceCount());
    try std.testing.expectError(error.StaleConsequence, terminal.consumeConsequence(2));

    const expected = [_]struct { kind: Terminal.NotificationKind, command: u16, payload: []const u8 }{
        .{ .kind = .message, .command = 9, .payload = "hello" },
        .{ .kind = .message, .command = 99, .payload = "i=one:d=0;body" },
        .{ .kind = .message, .command = 777, .payload = "notify;title;body" },
        .{ .kind = .message, .command = 1337, .payload = "rich body" },
        .{ .kind = .steal_focus, .command = 1337, .payload = "" },
        .{ .kind = .request_attention, .command = 1337, .payload = "fireworks" },
        .{ .kind = .message, .command = 9, .payload = "last" },
    };
    for (expected, 1..) |item, generation| {
        notification = terminal.consequenceHead().?.notification;
        try std.testing.expectEqual(@as(u64, @intCast(generation)), notification.generation);
        try std.testing.expectEqual(item.kind, notification.kind);
        try std.testing.expectEqual(item.command, notification.command);
        try std.testing.expectEqualStrings(item.payload, notification.payload);
        try terminal.consumeConsequence(notification.generation);
    }
    try std.testing.expect(terminal.consequenceHead() == null);

    try std.testing.expect(!(try terminal.feed("\x1b]1337;RequestAtt")).stateChanged());
    try std.testing.expect((try terminal.feed("ention=once\x07")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1bc\x1b[?1049h\x1b[?1049l")).stateChanged());
    notification = terminal.consequenceHead().?.notification;
    try std.testing.expectEqual(@as(u64, 8), notification.generation);
    try std.testing.expectEqual(Terminal.NotificationKind.request_attention, notification.kind);
    try std.testing.expectEqualStrings("once", notification.payload);
}

test "OSC notification bounds preserve the FIFO and wrap without reuse" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b]9;prior\x07")).stateChanged());
    const payload = try allocator.alloc(u8, expected_metadata_bytes + 1);
    defer allocator.free(payload);
    @memset(payload, 'x');
    var sequence = std.ArrayList(u8).empty;
    defer sequence.deinit(allocator);
    try sequence.appendSlice(allocator, "\x1b]9;");
    try sequence.appendSlice(allocator, payload[0..expected_metadata_bytes]);
    try sequence.append(allocator, 0x07);

    try std.testing.expect((try terminal.feed(sequence.items)).stateChanged());
    var retained = terminal.consequenceHead().?.notification;
    try std.testing.expectEqual(@as(u64, 1), retained.generation);
    try std.testing.expectEqualStrings("prior", retained.payload);
    try std.testing.expectEqual(@as(u8, 2), terminal.consequenceCount());

    sequence.clearRetainingCapacity();
    try sequence.appendSlice(allocator, "\x1b]9;");
    try sequence.appendSlice(allocator, payload);
    try sequence.append(allocator, 0x07);

    try std.testing.expectError(error.ConsequenceLimit, terminal.feed(sequence.items));
    retained = terminal.consequenceHead().?.notification;
    try std.testing.expectEqual(@as(u64, 1), retained.generation);
    try std.testing.expectEqualStrings("prior", retained.payload);
    try std.testing.expectEqual(@as(u8, 2), terminal.consequenceCount());

    try terminal.consumeConsequence(1);
    retained = terminal.consequenceHead().?.notification;
    try std.testing.expectEqual(@as(u64, 2), retained.generation);
    try std.testing.expectEqual(expected_metadata_bytes, retained.payload.len);
    for (0..expected_notification_capacity - 1) |_| {
        try std.testing.expect((try terminal.feed("\x1b]9;queued\x07")).stateChanged());
    }
    try std.testing.expectEqual(expected_notification_capacity, terminal.consequenceCount());
    try std.testing.expectError(error.ConsequencePressure, terminal.feed("\x1b]9;rejected\x07"));
    try std.testing.expectEqual(@as(u64, 2), terminal.consequenceHead().?.notification.generation);
    try std.testing.expectEqual(expected_notification_capacity, terminal.consequenceCount());
    // Reserved unsupported commands do not even enter the full notification FIFO.
    const before = terminal.semanticSequence();
    try std.testing.expect(!(try terminal.feed("\x1b]9;1;5000\x07\x1b]9;7;ignored\x1b\\\x1b]9;9\x07\x1b]9;12\x07")).stateChanged());
    try std.testing.expectEqual(before, terminal.semanticSequence());
    try std.testing.expectEqual(@as(u64, 2), terminal.consequenceHead().?.notification.generation);
    try std.testing.expectEqual(expected_notification_capacity, terminal.consequenceCount());

    for (0..expected_notification_capacity) |_| {
        retained = terminal.consequenceHead().?.notification;
        try terminal.consumeConsequence(retained.generation);
    }
    try std.testing.expect(terminal.consequenceHead() == null);
    try std.testing.expect((try terminal.feed("\x1b]9;after\x07")).stateChanged());
    retained = terminal.consequenceHead().?.notification;
    try std.testing.expectEqual(@as(u64, 10), retained.generation);
    try std.testing.expectEqualStrings("after", retained.payload);
    try terminal.consumeConsequence(10);
    try std.testing.expectError(error.StaleConsequence, terminal.consumeConsequence(10));
}

test "OSC 22 retains ordered bounded caller-neutral requests" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b]22;>wait,")).stateChanged());
    try std.testing.expect(terminal.consequenceHead() == null);
    try std.testing.expect((try terminal.feed("pointer\x1b\\")).stateChanged());
    var request = terminal.consequenceHead().?.pointer_shape;
    try std.testing.expectEqual(@as(u64, 1), request.generation);
    try std.testing.expect(!request.alternate_screen);
    try std.testing.expectEqualStrings(">wait,pointer", request.payload);

    try std.testing.expect((try terminal.feed(
        "\x9d22;?default,current\x9c" ++
            "\x1b[?1049h" ++
            "\x1b]22;>crosshair\x07" ++
            "\x1b[?1049l" ++
            "\x1b]22;<1\x07",
    )).stateChanged());
    try std.testing.expectEqual(@as(u8, 4), terminal.consequenceCount());
    try std.testing.expectError(error.StaleConsequence, terminal.consumeConsequence(2));

    const expected = [_][]const u8{
        ">wait,pointer",
        "?default,current",
        ">crosshair",
        "<1",
    };
    for (expected, 1..) |payload, generation| {
        request = terminal.consequenceHead().?.pointer_shape;
        try std.testing.expectEqual(@as(u64, @intCast(generation)), request.generation);
        try std.testing.expectEqual(generation == 3, request.alternate_screen);
        try std.testing.expectEqualStrings(payload, request.payload);
        try terminal.consumeConsequence(request.generation);
    }
    try std.testing.expect(terminal.consequenceHead() == null);

    try std.testing.expect((try terminal.feed("\x1b]22;survives\x07")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1bc\x1b[?1049h\x1b[?1049l")).stateChanged());
    try terminal.resize(4, 9);
    request = terminal.consequenceHead().?.pointer_shape;
    try std.testing.expectEqual(@as(u64, 5), request.generation);
    try std.testing.expectEqual(@as(u64, 1), request.reset_generation);
    try std.testing.expectEqual(
        @as(u64, 2),
        terminal.pointerShapeResetSequence(),
    );
    try std.testing.expectEqualStrings("survives", request.payload);
}

test "OSC 22 bounds preserve the FIFO and wrap without reuse" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    const payload = try allocator.alloc(u8, expected_metadata_bytes + 1);
    defer allocator.free(payload);
    @memset(payload, 'x');
    var sequence = std.ArrayList(u8).empty;
    defer sequence.deinit(allocator);

    try std.testing.expect((try terminal.feed("\x1b]22;prior\x07")).stateChanged());
    try sequence.appendSlice(allocator, "\x1b]22;");
    try sequence.appendSlice(allocator, payload[0..expected_metadata_bytes]);
    try sequence.append(allocator, 0x07);
    try std.testing.expect((try terminal.feed(sequence.items)).stateChanged());
    var retained = terminal.consequenceHead().?.pointer_shape;
    try std.testing.expectEqual(@as(u64, 1), retained.generation);
    try std.testing.expectEqualStrings("prior", retained.payload);
    try std.testing.expectEqual(@as(u8, 2), terminal.consequenceCount());

    sequence.clearRetainingCapacity();
    try sequence.appendSlice(allocator, "\x1b]22;");
    try sequence.appendSlice(allocator, payload);
    try sequence.append(allocator, 0x07);
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed(sequence.items));
    retained = terminal.consequenceHead().?.pointer_shape;
    try std.testing.expectEqual(@as(u64, 1), retained.generation);
    try std.testing.expectEqualStrings("prior", retained.payload);
    try std.testing.expectEqual(@as(u8, 2), terminal.consequenceCount());

    try terminal.consumeConsequence(1);
    retained = terminal.consequenceHead().?.pointer_shape;
    try std.testing.expectEqual(@as(u64, 2), retained.generation);
    try std.testing.expectEqual(expected_metadata_bytes, retained.payload.len);
    for (0..expected_pointer_shape_capacity - 1) |_| {
        try std.testing.expect((try terminal.feed("\x1b]22;queued\x07")).stateChanged());
    }
    try std.testing.expectEqual(
        expected_pointer_shape_capacity,
        terminal.consequenceCount(),
    );
    try std.testing.expectError(error.ConsequencePressure, terminal.feed("\x1b]22;rejected\x07"));
    try std.testing.expectEqual(@as(u64, 2), terminal.consequenceHead().?.pointer_shape.generation);
    try std.testing.expectEqual(
        expected_pointer_shape_capacity,
        terminal.consequenceCount(),
    );

    for (0..expected_pointer_shape_capacity) |_| {
        retained = terminal.consequenceHead().?.pointer_shape;
        try terminal.consumeConsequence(retained.generation);
    }
    try std.testing.expect(terminal.consequenceHead() == null);
    try std.testing.expect((try terminal.feed("\x1b]22;after\x07")).stateChanged());
    retained = terminal.consequenceHead().?.pointer_shape;
    try std.testing.expectEqual(@as(u64, 10), retained.generation);
    try std.testing.expectEqualStrings("after", retained.payload);
    try terminal.consumeConsequence(10);
    try std.testing.expectError(error.StaleConsequence, terminal.consumeConsequence(10));
}

test "OSC 22 query reply is one direct transactional operation" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 4);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("\x1b]22;pointer\x1b\\")).stateChanged());
    try std.testing.expectError(
        error.PointerShapeReplyMismatch,
        terminal.replyPointerShape(1, "pointer"),
    );
    try std.testing.expectEqual(@as(u64, 1), terminal.consequenceHead().?.pointer_shape.generation);
    try terminal.consumeConsequence(1);
    try std.testing.expect((try terminal.feed("\x1b]22;?__current__\x1b\\")).stateChanged());
    const token = terminal.semanticSequence();
    try std.testing.expectError(
        error.StalePointerShape,
        terminal.replyPointerShape(3, "default"),
    );
    try std.testing.expectEqual(token, terminal.semanticSequence());
    try std.testing.expectEqual(@as(u64, 2), terminal.consequenceHead().?.pointer_shape.generation);
    try terminal.replyPointerShape(2, "default");
    try std.testing.expectEqualStrings("\x1b]22;default\x1b\\", terminal.replyBytes());
    try std.testing.expect(token != terminal.semanticSequence());
    try std.testing.expect(terminal.consequenceHead() == null);
}

test "iTerm safe controls mutate presentation metadata and exact replies" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    try terminal.setCellPixelSize(9, 18);

    const summary = try terminal.feed(
        "\x1b]1337;CursorShape=1\x07" ++
            "\x1b]1337;ShellIntegrationVersion=20;shell=bash\x07" ++
            "\x1b]1337;SetColors=fg=abc,bg=srgb:102030,curbg=010203," ++
            "curfg=040506,red=ff0000,br_white=eeeeee,bg=p3:ffffff\x07" ++
            "\x1b]1337;ReportCellSize\x07",
    );
    try std.testing.expect(summary.stateChanged());
    const view = terminal.semanticView(0);
    const presentation = terminal.presentation();
    try std.testing.expectEqual(Terminal.CursorShape.bar, view.cursor_shape);
    try std.testing.expectEqual(@as(u32, 20), terminal.shellIntegration().?.version);
    try std.testing.expectEqualStrings("bash", terminal.shellIntegration().?.shell.?);
    try std.testing.expectEqual(Rgb{ .r = 0xaa, .g = 0xbb, .b = 0xcc }, presentation.foreground);
    try std.testing.expectEqual(Rgb{ .r = 0x10, .g = 0x20, .b = 0x30 }, presentation.background);
    try std.testing.expectEqual(Rgb{ .r = 0xff, .g = 0, .b = 0 }, presentation.palette[1]);
    try std.testing.expectEqual(Rgb{ .r = 1, .g = 2, .b = 3 }, presentation.cursor.?);
    try std.testing.expectEqual(Rgb{ .r = 4, .g = 5, .b = 6 }, presentation.cursor_text.?);
    try std.testing.expectEqual(Rgb{ .r = 0xee, .g = 0xee, .b = 0xee }, presentation.palette[15]);
    try std.testing.expectEqualStrings(
        "\x1b]1337;ReportCellSize=18;9;1\x1b\\",
        terminal.replyBytes(),
    );
    try consumeReplies(&terminal);
    const valued_request = try terminal.feed(
        "\x1b]1337;ReportCellSize=ignored-by-iterm\x07",
    );
    try std.testing.expect(valued_request.stateChanged());
    try std.testing.expectEqualStrings(
        "\x1b]1337;ReportCellSize=18;9;1\x1b\\",
        terminal.replyBytes(),
    );

    const osc_50 = try terminal.feed("\x1b]50;CursorShape=2\x07");
    try std.testing.expect(osc_50.stateChanged());
    try std.testing.expectEqual(
        Terminal.CursorShape.underline,
        terminal.semanticView(0).cursor_shape,
    );
    try std.testing.expect(!(try terminal.feed("\x1b]1337;CursorShape=2\x07")).stateChanged());
    try std.testing.expect(!(try terminal.feed(
        "\x1b]1337;CursorShape=\x07\x1b]1337;CursorShape=x\x1b\\",
    )).stateChanged());
    try std.testing.expectEqual(
        Terminal.CursorShape.underline,
        terminal.semanticView(0).cursor_shape,
    );
}

test "pinned iTerm2 Linux OSC P commits seven bytes without title mutation" {
    // Pinned iTerm2 VT100XtermParser.m:parsePFromContext consumes seven
    // bytes after P and finishes immediately, without requiring BEL/ST.
    var terminal = try Terminal.init(std.testing.allocator, 2, 12);
    defer terminal.deinit();
    const original = terminal.presentation().palette[1];
    try std.testing.expect(!(try terminal.feed("\x1b]P11223")).stateChanged());
    try std.testing.expectEqual(original, terminal.presentation().palette[1]);
    try std.testing.expect(terminal.title() == null);
    try std.testing.expect((try terminal.feed("34")).stateChanged());
    try std.testing.expectEqual(Rgb{ .r = 0x12, .g = 0x23, .b = 0x34 }, terminal.presentation().palette[1]);
    try std.testing.expect(terminal.title() == null);
    try std.testing.expectEqualStrings("", terminal.replyBytes());
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());

    // A trailing BEL is a *new* ground-state bell, not the P terminator.
    try std.testing.expect((try terminal.feed("\x07")).stateChanged());
    try std.testing.expectEqual(@as(u16, 1), terminal.consequenceCount());
    const bell = terminal.consequenceHead().?;
    try std.testing.expect(bell == .bell);
    try terminal.consumeConsequence(bell.id());

    // Repeated values are idempotent; the next byte after seven is text.
    try std.testing.expect(!(try terminal.feed("\x1b]P1122334")).stateChanged());
    try std.testing.expect((try terminal.feed("Z")).stateChanged());
    try std.testing.expectEqual(@as(u21, 'Z'), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expect(terminal.title() == null);

    // Ordinary OSC 4 shares the actual palette owner and remains functional.
    try std.testing.expect((try terminal.feed("\x1b]4;1;#010203\x1b\\")).stateChanged());
    try std.testing.expectEqual(Rgb{ .r = 1, .g = 2, .b = 3 }, terminal.presentation().palette[1]);
}

test "pinned iTerm2 Linux OSC P uses special colors and rejects malformed values" {
    // Pinned VT100Terminal.m maps g-m to color indices 16-22:
    // foreground, background, bold, selection, selection text, cursor,
    // cursor text. Ordinary 0-f uses the canonical indexed palette.
    var terminal = try Terminal.init(std.testing.allocator, 2, 12);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("\x1b]Pg102030")).stateChanged());
    try std.testing.expectEqual(Rgb{ .r = 0x10, .g = 0x20, .b = 0x30 }, terminal.presentation().foreground);
    try std.testing.expect((try terminal.feed("\x1b]Ph112233")).stateChanged());
    try std.testing.expectEqual(Rgb{ .r = 0x11, .g = 0x22, .b = 0x33 }, terminal.presentation().background);
    try std.testing.expect((try terminal.feed("\x1b]Pi445566")).stateChanged());
    try std.testing.expectEqual(@as(?Rgb, .{ .r = 0x44, .g = 0x55, .b = 0x66 }), terminal.presentation().bold);
    try std.testing.expect((try terminal.feed("\x1b]Pj778899")).stateChanged());
    try std.testing.expectEqual(@as(?Rgb, .{ .r = 0x77, .g = 0x88, .b = 0x99 }), terminal.presentation().selection_background);
    try std.testing.expect((try terminal.feed("\x1b]PkA1B2C3")).stateChanged());
    try std.testing.expectEqual(@as(?Rgb, .{ .r = 0xa1, .g = 0xb2, .b = 0xc3 }), terminal.presentation().selection_foreground);
    try std.testing.expect((try terminal.feed("\x1b]Pl102030")).stateChanged());
    try std.testing.expectEqual(@as(?Rgb, .{ .r = 0x10, .g = 0x20, .b = 0x30 }), terminal.presentation().cursor);
    try std.testing.expect((try terminal.feed("\x1b]Pm112233")).stateChanged());
    try std.testing.expectEqual(@as(?Rgb, .{ .r = 0x11, .g = 0x22, .b = 0x33 }), terminal.presentation().cursor_text);
    try std.testing.expect(terminal.title() == null);

    const original = terminal.presentation();
    for ([_][]const u8{
        "\x1b]Pz112233", // invalid palette selector
        "\x1b]P1GGGGGG", // invalid color
        "\x1b]P1\x07AAAAA", // BEL is an invalid raw payload byte
    }) |packet| {
        try std.testing.expect(!(try terminal.feed(packet)).stateChanged());
    }
    try std.testing.expectEqual(original.palette[1], terminal.presentation().palette[1]);
    try std.testing.expectEqual(original.background, terminal.presentation().background);
    try std.testing.expectEqual(original.bold, terminal.presentation().bold);
    try std.testing.expectEqual(original.selection_background, terminal.presentation().selection_background);
    try std.testing.expectEqual(original.selection_foreground, terminal.presentation().selection_foreground);
    // An uppercase index and uppercase RGB digits must also be accepted.
    try std.testing.expect((try terminal.feed("\x1b]PAABCDEF")).stateChanged());
    try std.testing.expectEqual(Rgb{ .r = 0xab, .g = 0xcd, .b = 0xef }, terminal.presentation().palette[10]);
    try std.testing.expectEqual(original.foreground, terminal.presentation().foreground);
    try std.testing.expect(terminal.title() == null);
    try std.testing.expectEqualStrings("", terminal.replyBytes());
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
}

test "pinned iTerm2 OSC 9 notification retains a bounded host-neutral consequence" {
    // Pinned VT100XtermParser.m::tokenTypeForMode maps OSC 9 to
    // ITERM_USER_NOTIFICATION, then VT100Terminal.m calls its macOS
    // terminalPostUserNotification delegate. Howl retains an ordinary
    // notification request, but the app deliberately declines visual UI.
    var terminal = try Terminal.init(std.testing.allocator, 2, 12);
    defer terminal.deinit();
    try std.testing.expect(!(try terminal.feed("\x1b]9;notice")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b\\")).stateChanged());
    try std.testing.expectEqual(@as(u16, 1), terminal.consequenceCount());
    const msg = terminal.consequenceHead().?.notification;
    try std.testing.expectEqual(Terminal.NotificationKind.message, msg.kind);
    try std.testing.expectEqual(@as(u16, 9), msg.command);
    try std.testing.expectEqualStrings("notice", msg.payload);
    try std.testing.expectEqualStrings("", terminal.replyBytes());
}

test "pinned iTerm2 OSC 6 134 and 21337 host controls are absent from Howl" {
    // Pinned iTerm2 VT100XtermParser.m tokenTypeForMode dispatches 6
    // to executeXtermProprietaryEtermExtension (proxy icon and tab color),
    // 134 to XTERMCC_FRAMER_WRAPPER (SSH recovery), and 21337 to
    // executeSetTabStatus (per-tab key/value metadata). Howl's OSC
    // decoder supports none of these product-owned consequences.
    var terminal = try Terminal.init(std.testing.allocator, 3, 12);
    defer terminal.deinit();
    const baseline = terminal.semanticSequence();
    for ([_][]const u8{
        "\x1b]6;1;bg;red;brightness;255\x07",
        "\x1b]6;1;bg;*;default\x1b\\",
        "\x1b]134;framer-payload\x07",
        "\x1b]21337;status=working;progress=1\x1b\\",
    }) |control| {
        for (control[0 .. control.len - 1]) |byte| {
            const one = [_]u8{byte};
            try std.testing.expect(!(try terminal.feed(&one)).stateChanged());
        }
        try std.testing.expect(!(try terminal.feed(control[control.len - 1 ..])).stateChanged());
        try std.testing.expectEqual(baseline, terminal.semanticSequence());
        try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
        try std.testing.expectEqualStrings("", terminal.replyBytes());
    }
    // The unsupported controls leave subsequent text and supported OSC
    // cursor-shape subset functional, with no uncommitted state.
    try std.testing.expect((try terminal.feed("Q")).stateChanged());
    try std.testing.expectEqual(@as(u21, 'Q'), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expect((try terminal.feed("\x1b]50;CursorShape=1\x07")).stateChanged());
    try std.testing.expectEqual(Terminal.CursorShape.bar, terminal.semanticView(0).cursor_shape);
}

test "OSC 50 accepts only cursor shape without 1337 consequences" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    try terminal.setCellPixelSize(9, 18);
    const seeded = try terminal.feed(
        "\x1b]1337;SetColors=fg=112233\x07" ++
            "\x1b]1337;ShellIntegrationVersion=20;shell=bash\x07",
    );
    try std.testing.expect(seeded.stateChanged());
    try terminal.consumeReplyBytes(terminal.replyBytes().len);

    const rejected = try terminal.feed(
        "\x1b]50;SetColors=fg=abcdef\x07" ++
            "\x1b]50;ShellIntegrationVersion=21;shell=zsh\x07" ++
            "\x1b]50;ReportCellSize\x07",
    );
    try std.testing.expect(!rejected.stateChanged());
    try std.testing.expectEqual(
        Rgb{ .r = 0x11, .g = 0x22, .b = 0x33 },
        terminal.presentation().foreground,
    );
    try std.testing.expectEqual(@as(u32, 20), terminal.shellIntegration().?.version);
    try std.testing.expectEqualStrings("bash", terminal.shellIntegration().?.shell.?);
    try std.testing.expectEqual(@as(usize, 0), terminal.replyBytes().len);

    const accepted = try terminal.feed("\x1b]50;CursorShape=1\x07");
    try std.testing.expect(accepted.stateChanged());
    try std.testing.expectEqual(
        Terminal.CursorShape.bar,
        terminal.semanticView(0).cursor_shape,
    );
}

test "cell pixel reports reject zero and preserve configured dimensions" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    try terminal.setCellPixelSize(9, 18);
    try std.testing.expectError(error.InvalidDimensions, terminal.setCellPixelSize(0, 18));
    const cell = terminal.cellPixelSize().?;
    try std.testing.expectEqual(@as(u32, 9), cell.width);
    try std.testing.expectEqual(@as(u32, 18), cell.height);
}

test "pinned iTerm2 deprecated BeginFile and EndFile are deliberate no-ops" {
    // Pinned VT100Terminal.m::executeXtermSetKvp logs unsupported for
    // BeginFile/EndFile and calls no delegate. Howl ignores both, so
    // 'missing' was false for these intentionally retired semantics.
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    const begin = "\x1b]1337;BeginFile=canary\x07";
    const end = "\x1b]1337;EndFile=canary\x1b\\";
    const baseline = terminal.semanticSequence();
    for ([_][]const u8{ begin, end }) |sequence| {
        try std.testing.expect(!(try terminal.feed(sequence[0 .. sequence.len - 1])).stateChanged());
        try std.testing.expect(!(try terminal.feed(sequence[sequence.len - 1 ..])).stateChanged());
        try std.testing.expectEqual(baseline, terminal.semanticSequence());
        try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
        try std.testing.expectEqualStrings("", terminal.replyBytes());
    }
    try std.testing.expect((try terminal.feed("ok")).stateChanged());
    try std.testing.expectEqual(@as(u21, 'o'), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'k'), terminal.semanticView(0).cellAt(0, 1));
}

test "pinned iTerm2 OSC 1337 absent host actions have no native consequences" {
    // Pinned VT100Terminal.m::executeXtermSetKvp owns the external
    // session, UI, SSH and debug consequences listed below. Howl
    // iterm_control.parse1337 intentionally has no matching actions.
    var terminal = try Terminal.init(std.testing.allocator, 3, 12);
    defer terminal.deinit();
    const before = terminal.semanticSequence();
    const presentation = terminal.presentation();
    const samples = [_][]const u8{
        "SetBadgeFormat=YQ==", // set_badge
        "SetMark=checkpoint", // set_mark
        "SetProfile=canary", // set_profile
        "AddNote=hello", // add_note
        "AddAnnotation=hello", // add_annotation
        "AddHiddenNote=hello", // add_hidden_note
        "AddHiddenAnnotation=hello", // add_hidden_annotation
        "HighlightCursorLine=1", // highlight_cursor_line
        "ClearCapturedOutput=1", // clear_captured_output
        "Copy=1", // copy
        "EndCopy", // end_copy
        "CopyToClipboard=clipboard", // copy_to_clipboard
        "Block=id=canary;attr=start;type=command", // block
        "UpdateBlock=id=canary;action=fold", // update_block_fold
        "UpdateBlock=id=canary;action=unfold", // update_block_unfold
        "Button=type=copy;block=canary", // button_copy
        "Button=type=custom;code=1;icon=foo", // button_custom
        "RequestUpload=file", // request_upload
        "SetBackgroundImageFile=test", // background_image
        "SetProfileProperty=foo=YmFy", // profile_property
        "SetUserVar=foo=YmFy", // user_var
        "UnicodeVersion=9", // unicode_set
        "UnicodeVersion=push=9", // unicode_push
        "UnicodeVersion=pop", // unicode_pop
        "SetKeyLabel=foo=bar", // set_key_label
        "PushKeyLabels=foo", // push_key_labels
        "PopKeyLabels=foo", // pop_key_labels
        "Disinter=1", // disinter
        "ReportVariable=Zm9v", // report_variable
        "Custom=foo:bar", // custom
        "Capabilities=1", // capabilities
        "Env=FOO=bar", // env
        "it2ssh=host", // it2ssh
        "SendConductor=data", // send_conductor
        "EndSSH=done", // end_ssh
        "OpenURL=1:aHR0cHM6Ly9leGFtcGxlLmNvbQ==", // open_url
        "wrap=a=start;cmd=YQ==;uid=0123456789abcdef", // wrap_start
        "Debug=QueryFnState", // debug
        "ExecFailed=1", // exec_failed
    };
    for (samples, 0..) |sample, index| {
        var encoded: [256]u8 = undefined;
        const terminator = if (index % 2 == 0) "\x07" else "\x1b\\";
        const sequence = try std.fmt.bufPrint(&encoded, "\x1b]1337;{s}{s}", .{ sample, terminator });
        const split = sequence.len - terminator.len;
        try std.testing.expect(!(try terminal.feed(sequence[0..split])).stateChanged());
        try std.testing.expect(!(try terminal.feed(sequence[split..])).stateChanged());
        try std.testing.expectEqual(before, terminal.semanticSequence());
        try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
        try std.testing.expectEqualStrings("", terminal.replyBytes());
        try std.testing.expectEqualDeep(presentation, terminal.presentation());
    }
    try std.testing.expect((try terminal.feed("Q")).stateChanged());
    try std.testing.expectEqual(@as(u21, 'Q'), terminal.semanticView(0).cellAt(0, 0));
}

test "pinned Kitty OSC 1337 notification dispatch differs from Howl named iTerm keys" {
    // Frozen Kitty vt-parser.c::dispatch_osc treats every OSC 1337
    // payload as desktop_notify with the whole raw data. Howl parses
    // only explicitly owned iTerm2 keys and emits a notification
    // consequence solely for a recognized Notification= command.
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    const initial = terminal.semanticSequence();
    try std.testing.expect(!(try terminal.feed("\x1b]1337;arbitrary-host-message\x1b\\")).stateChanged());
    try std.testing.expectEqual(initial, terminal.semanticSequence());
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
    try std.testing.expectEqualStrings("", terminal.replyBytes());
    try std.testing.expect((try terminal.feed("\x1b]1337;Notification=notice\x07")).stateChanged());
    try std.testing.expectEqual(@as(u16, 1), terminal.consequenceCount());
    const msg = terminal.consequenceHead().?.notification;
    try std.testing.expectEqual(Terminal.NotificationKind.message, msg.kind);
    try std.testing.expectEqual(@as(u16, 1337), msg.command);
    try std.testing.expectEqualStrings("notice", msg.payload);
    try terminal.consumeConsequence(msg.generation);
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
}

test "pinned Kitty OSC 3008 is an exact ignored host context across streaming overflow" {
    // Pinned Kitty vt-parser.c::dispatch_osc code 3008 calls
    // screen.c::osc_context, and kitty/window.py::osc_context is pass.
    // Howl recognizes the same no-op and silently discards an oversized
    // metadata payload through BEL/ST without a pending consequence or
    // state error. Parsing resumes normally after the closed OSC.
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    const before = terminal.semanticSequence();
    try std.testing.expect(!(try terminal.feed("\x1b]3008;ignored\x07")).stateChanged());
    try std.testing.expectEqual(before, terminal.semanticSequence());
    const oversized = try std.testing.allocator.alloc(u8, expected_metadata_bytes * 16);
    defer std.testing.allocator.free(oversized);
    @memset(oversized, 'a');
    var sequence = std.ArrayList(u8).empty;
    defer sequence.deinit(std.testing.allocator);
    try sequence.appendSlice(std.testing.allocator, "\x1b]3008;");
    try sequence.appendSlice(std.testing.allocator, oversized);
    try sequence.appendSlice(std.testing.allocator, "\x1b\\");
    try std.testing.expect(!(try terminal.feed(sequence.items)).stateChanged());
    try std.testing.expectEqual(before, terminal.semanticSequence());
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
    try std.testing.expectEqualStrings("", terminal.replyBytes());
    try std.testing.expect((try terminal.feed("Q")).stateChanged());
    try std.testing.expectEqual(@as(u21, 'Q'), terminal.semanticView(0).cellAt(0, 0));
}

test "unsupported SetMark and Kitty context metadata remain exact no-ops" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b]1337;SetMark=lab")).stateChanged());
    try std.testing.expect(!(try terminal.feed("el\x1b\\")).stateChanged());
    try std.testing.expectEqual(@as(u64, 0), terminal.shellMark().generation);
    try std.testing.expect(!(try terminal.feed("\x9d3008;key=value\x9c")).stateChanged());

    const payload = try std.testing.allocator.alloc(u8, expected_metadata_bytes);
    defer std.testing.allocator.free(payload);
    @memset(payload, 'm');
    var sequence = std.ArrayList(u8).empty;
    defer sequence.deinit(std.testing.allocator);
    try sequence.appendSlice(std.testing.allocator, "\x1b]3008;");
    try sequence.appendSlice(std.testing.allocator, payload);
    try sequence.append(std.testing.allocator, 0x07);
    try std.testing.expect(!(try terminal.feed(sequence.items)).stateChanged());
    try std.testing.expectEqual(@as(u64, 0), terminal.shellMark().generation);
}

test "iTerm shell integration rejects malformed duplicate and oversized metadata" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    const accepted = try terminal.feed(
        "\x1b]1337;ShellIntegrationVersion=20;shell=bash\x07",
    );
    try std.testing.expect(accepted.stateChanged());

    const rejected = [_][]const u8{
        "\x1b]1337;ShellIntegrationVersion=broken;shell=bash\x07",
        "\x1b]1337;ShellIntegrationVersion=20;shell=bash;shell=zsh\x07",
        "\x1b]1337;ShellIntegrationVersion=20;unknown=value\x07",
        "\x1b]1337;ShellIntegrationVersion=20;shell=abcdefghijklmnopqrstuvwxyz1234567\x07",
    };
    for (rejected) |sequence| {
        const summary = try terminal.feed(sequence);
        try std.testing.expect(!summary.stateChanged());
        const integration = terminal.shellIntegration().?;
        try std.testing.expectEqual(@as(u32, 20), integration.version);
        try std.testing.expectEqualStrings("bash", integration.shell.?);
    }
}

test "iTerm SetColors resets represented domains and ignores malformed pairs independently" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    const set = try terminal.feed(
        "\x1b]1337;SetColors=fg=111111,bg=222222,curbg=333333," ++
            "curfg=444444,red=555555\x07",
    );
    try std.testing.expect(set.stateChanged());

    const mixed = try terminal.feed(
        "\x1b]1337;SetColors=fg=default,bg=bogus,missing," ++
            "curbg=default,curfg=default,red=default,bg=666666\x07",
    );
    try std.testing.expect(mixed.stateChanged());
    const presentation = terminal.presentation();
    try std.testing.expectEqual(Terminal.default_presentation.foreground, presentation.foreground);
    try std.testing.expectEqual(Rgb{ .r = 0x66, .g = 0x66, .b = 0x66 }, presentation.background);
    try std.testing.expectEqual(@as(?Rgb, null), presentation.cursor);
    try std.testing.expectEqual(@as(?Rgb, null), presentation.cursor_text);
    try std.testing.expectEqual(Terminal.default_presentation.palette[1], presentation.palette[1]);
}

test "OSC colors distinguish mutation query and malformed no-op" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();

    const malformed = try terminal.feed("\x1b]4;1;bogus\x07\x1b]10;no-color\x1b\\");
    try std.testing.expect(!malformed.stateChanged());
    try std.testing.expectEqual(@as(usize, 0), terminal.replyBytes().len);

    const changed = try terminal.feed("\x1b]4;1;#010203\x07");
    try std.testing.expect(changed.stateChanged());
    const repeated = try terminal.feed("\x1b]4;1;#010203\x1b\\");
    try std.testing.expect(!repeated.stateChanged());

    const query = try terminal.feed("\x1b]4;1;?\x07");
    try std.testing.expect(query.stateChanged());
    // xterm mirrors the BEL request terminator in OSC color replies.
    try std.testing.expectEqualStrings("\x1b]4;1;rgb:0101/0202/0303\x07", terminal.replyBytes());

    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    const iterm_malformed = try terminal.feed("\x1b]1337;SetColors=fg=bogus,missing,p3=x\x07");
    try std.testing.expect(!iterm_malformed.stateChanged());
}

test "kitty color stack OSC 30001 and 30101 restore colors" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try feed(
        &terminal,
        "\x1b]21;foreground=#010203\x1b\\\x1b]30001\x1b\\" ++
            "\x1b]21;foreground=#040506\x1b\\\x1b]30101\x1b\\",
    );
    try std.testing.expectEqual(Rgb{ .r = 1, .g = 2, .b = 3 }, terminal.presentation().foreground);
}

test "kitty OSC 21 sets queries and resets terminal colors" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try feed(&terminal, "\x1b]21;foreground=#112233;background=rgb:44/55/66;cursor=\x1b\\");
    try feed(&terminal, "\x1b]21;foreground=?;background=?;cursor=?;no_such=?\x1b\\");

    const colors = terminal.presentation();
    try std.testing.expectEqual(Rgb{ .r = 0x11, .g = 0x22, .b = 0x33 }, colors.foreground);
    try std.testing.expectEqual(Rgb{ .r = 0x44, .g = 0x55, .b = 0x66 }, colors.background);
    try std.testing.expectEqual(@as(?Rgb, null), colors.cursor);
    try std.testing.expectEqualStrings(
        "\x1b]21;foreground=rgb:11/22/33;background=rgb:44/55/66;cursor=;unknown=bm9fc3VjaA\x1b\\",
        terminal.replyBytes(),
    );

    try feed(&terminal, "\x1b]21;foreground;background\x1b\\");
    try std.testing.expectEqual(Rgb{ .r = 220, .g = 220, .b = 220 }, terminal.presentation().foreground);
    try std.testing.expectEqual(Rgb{ .r = 24, .g = 25, .b = 33 }, terminal.presentation().background);
}

test "Kitty OSC 21 strips non-ASCII across split VT input before replying" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();

    // Both pinned and newer Kitty remove nonprintable bytes before OSC 21
    // interpretation. The VT transport must preserve enough input for the
    // single ColorControl owner to sanitize even across separate writes.
    try std.testing.expect(!(try terminal.feed("\x1b]21;fore\xc3")).stateChanged());
    try std.testing.expectEqualStrings("", terminal.replyBytes());
    try feed(&terminal, "\xa9ground=#112233;fore\xc3\xa9ground=?\x1b\\");
    try std.testing.expectEqual(Rgb{ .r = 0x11, .g = 0x22, .b = 0x33 }, terminal.presentation().foreground);
    try std.testing.expectEqualStrings("\x1b]21;foreground=rgb:11/22/33\x1b\\", terminal.replyBytes());
}

test "kitty OSC 21 groups ordered queries with eight bit RGB and one reply" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 12);
    defer terminal.deinit();

    // Preserve wire order while mixing updates and queries. Only a fully
    // terminated OSC may expose a response, regardless of feed boundaries.
    try std.testing.expect(!(try terminal.feed("\x1b]21;foreground=#123456;foreground=?;background=#abcdef;")).stateChanged());
    try std.testing.expectEqualStrings("", terminal.replyBytes());
    try feed(&terminal, "background=?;cursor=?;unsupported=?\x1b\\");
    try std.testing.expectEqualStrings(
        "\x1b]21;foreground=rgb:12/34/56;background=rgb:ab/cd/ef;cursor=;unknown=dW5zdXBwb3J0ZWQ\x1b\\",
        terminal.replyBytes(),
    );
    try std.testing.expectEqual(Rgb{ .r = 0x12, .g = 0x34, .b = 0x56 }, terminal.presentation().foreground);
    try std.testing.expectEqual(Rgb{ .r = 0xab, .g = 0xcd, .b = 0xef }, terminal.presentation().background);
    try terminal.consumeReplyBytes(terminal.replyBytes().len);

    // Queries alone never commit new color state.
    try std.testing.expect((try terminal.feed("\x1b]21;foreground=?;background=?\x07")).stateChanged());
    try std.testing.expectEqualStrings(
        "\x1b]21;foreground=rgb:12/34/56;background=rgb:ab/cd/ef\x1b\\",
        terminal.replyBytes(),
    );
}

test "current Kitty OSC 21 preserves duplicate query chronology and encodes unknown names" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 12);
    defer terminal.deinit();

    // Current Kitty window.py::color_control uses an ordered list, not the
    // frozen reference's insertion-ordered response dictionary. Unknown
    // fields are returned only inside base64-encoded unknown= values.
    try std.testing.expect(!(try terminal.feed(
        "\x1b]21;foreground=#112233;foreground=?;bad=?;" ++
            "foreground=#445566;foreground=?;bad=?; 5 =?;bad=red;" ++
            "unsupported-setter;cursor=?;visual_bell=?\x1b",
    )).stateChanged());
    try feed(&terminal, "\\");
    try std.testing.expectEqualStrings(
        "\x1b]21;foreground=rgb:11/22/33;unknown=YmFk;" ++
            "foreground=rgb:44/55/66;unknown=YmFk;unknown=IDUg;" ++
            "unknown=YmFk;unknown=dW5zdXBwb3J0ZWQtc2V0dGVy;" ++
            "cursor=;visual_bell=\x1b\\",
        terminal.replyBytes(),
    );
    try std.testing.expectEqual(Rgb{ .r = 0x44, .g = 0x55, .b = 0x66 }, terminal.presentation().foreground);
    try std.testing.expectEqual(@as(?Rgb, null), terminal.presentation().cursor);
    try terminal.consumeReplyBytes(terminal.replyBytes().len);

    // The known-name query is still one response; an invalid value for a
    // known key does not manufacture an unknown-key report.
    try feed(&terminal, "\x1b]21;foreground=#not-a-color;foreground=?\x07");
    try std.testing.expectEqualStrings("\x1b]21;foreground=rgb:44/55/66\x1b\\", terminal.replyBytes());
}

test "current Kitty OSC 21 unknown control names never echo attacker text" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();

    // Unrecognized names are never emitted verbatim, including a bare
    // setter/reset command. Empty records are ignored, not echoed.
    try feed(&terminal, "\x1b]21;;evil]21=X;;transparent_background_color9=?\x1b\\");
    try std.testing.expectEqualStrings(
        "\x1b]21;unknown=ZXZpbF0yMQ;unknown=dHJhbnNwYXJlbnRfYmFja2dyb3VuZF9jb2xvcjk\x1b\\",
        terminal.replyBytes(),
    );
    try std.testing.expect(std.mem.indexOf(u8, terminal.replyBytes(), "evil]") == null);
    try terminal.consumeReplyBytes(terminal.replyBytes().len);

    // A valid transparent-background slot is recognized even though Howl
    // currently has no host alpha state. Its initial query is unset, not an
    // unknown field. This does not claim full alpha-setting compatibility.
    try feed(&terminal, "\x1b]21;transparent_background_color2=?\x1b\\");
    try std.testing.expectEqualStrings("\x1b]21;transparent_background_color2=\x1b\\", terminal.replyBytes());
}

test "current Kitty OSC 21 retains eight opacity-aware transparent background slots" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();

    // Current Kitty has eight color-profile slots. An opacity of 0.5 is
    // quantized to alpha byte 127, and the reply reports 127/255 to four
    // decimal places, not the unquantized input float.
    try feed(&terminal, "\x1b]21;transparent_background_color1=#112233@0.5;" ++
        "transparent_background_color2=red@0.2;transparent_background_color8=rgb:aa/bb/cc@1.5\x1b\\");
    try feed(&terminal, "\x1b]21;transparent_background_color1=?;" ++
        "transparent_background_color2=?;transparent_background_color8=?\x1b\\");
    try std.testing.expectEqualStrings(
        "\x1b]21;transparent_background_color1=rgb:11/22/33@0.4980;" ++
            "transparent_background_color2=rgb:ff/00/00@0.2000;" ++
            "transparent_background_color8=rgb:aa/bb/cc@1.0000\x1b\\",
        terminal.replyBytes(),
    );
    try terminal.consumeReplyBytes(terminal.replyBytes().len);

    // Bare reset clears only the addressed program override. Malformed
    // colors cannot replace previously retained values.
    try feed(&terminal, "\x1b]21;transparent_background_color1;" ++
        "transparent_background_color2=not-a-color@0.75;" ++
        "transparent_background_color3=#040506@bogus\x1b\\");
    try feed(&terminal, "\x1b]21;transparent_background_color1=?;" ++
        "transparent_background_color2=?;transparent_background_color3=?\x1b\\");
    try std.testing.expectEqualStrings(
        "\x1b]21;transparent_background_color1=;" ++
            "transparent_background_color2=rgb:ff/00/00@0.2000;" ++
            "transparent_background_color3=rgb:04/05/06@1.0000\x1b\\",
        terminal.replyBytes(),
    );
    try terminal.consumeReplyBytes(terminal.replyBytes().len);

    // The existing bounded Kitty color stack must snapshot opacity too.
    try feed(&terminal, "\x1b]30001\x1b\\");
    try feed(&terminal, "\x1b]21;transparent_background_color2=#070809@0.8\x1b\\");
    try feed(&terminal, "\x1b]30101\x1b\\");
    try feed(&terminal, "\x1b]21;transparent_background_color2=?\x1b\\");
    try std.testing.expectEqualStrings(
        "\x1b]21;transparent_background_color2=rgb:ff/00/00@0.2000\x1b\\",
        terminal.replyBytes(),
    );
}

test "transparent color host defaults copy to presentation but renderer policy stays separate" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    var defaults: Terminal.ColorDefaults = .{};
    defaults.transparent_background[3] = .{
        .rgb = .{ .r = 0x11, .g = 0x22, .b = 0x33 },
        .opacity = 0.8,
    };
    terminal.setColorDefaults(defaults);
    const accepted = terminal.presentation();
    try std.testing.expectEqualDeep(
        defaults.transparent_background[3].?,
        accepted.transparent_background[3].?,
    );
    try feed(&terminal, "\x1b]21;transparent_background_color4=?\x1b\\");
    try std.testing.expectEqualStrings(
        "\x1b]21;transparent_background_color4=rgb:11/22/33@0.8000\x1b\\",
        terminal.replyBytes(),
    );
    try terminal.consumeReplyBytes(terminal.replyBytes().len);

    try feed(&terminal, "\x1b]21;transparent_background_color4=#abcdef@0.25\x1b\\");
    try std.testing.expectEqualDeep(
        defaults.transparent_background[3].?,
        accepted.transparent_background[3].?,
    );
    try std.testing.expectEqual(Rgb{ .r = 0xab, .g = 0xcd, .b = 0xef }, terminal.presentation().transparent_background[3].?.rgb);

    // Reset only removes the program override; the configured baseline is
    // still reportable. No renderer change is implied by this VT metadata.
    try feed(&terminal, "\x1b]21;transparent_background_color4\x1b\\");
    try feed(&terminal, "\x1b]21;transparent_background_color4=?\x1b\\");
    try std.testing.expectEqualStrings(
        "\x1b]21;transparent_background_color4=rgb:11/22/33@0.8000\x1b\\",
        terminal.replyBytes(),
    );
    try terminal.consumeReplyBytes(terminal.replyBytes().len);

    // Hard reset clears program alpha overrides and restores the host default.
    try feed(&terminal, "\x1b]21;transparent_background_color8=#010203@0\x1b\\");
    try feed(&terminal, "\x1bc");
    try std.testing.expectEqual(@as(?@import("../../src/properties.zig").TransparentBackgroundColor, null), terminal.presentation().transparent_background[7]);
    try std.testing.expectEqualDeep(
        defaults.transparent_background[3].?,
        terminal.presentation().transparent_background[3].?,
    );
}

test "transparent slot queries clamp hostile host defaults without floating traps" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    var defaults: Terminal.ColorDefaults = .{};
    defaults.transparent_background[0] = .{
        .rgb = .{ .r = 1, .g = 2, .b = 3 },
        .opacity = std.math.nan(f32),
    };
    defaults.transparent_background[1] = .{
        .rgb = .{ .r = 4, .g = 5, .b = 6 },
        .opacity = std.math.inf(f32),
    };
    defaults.transparent_background[2] = .{
        .rgb = .{ .r = 7, .g = 8, .b = 9 },
        .opacity = -3,
    };
    terminal.setColorDefaults(defaults);
    try feed(&terminal, "\x1b]21;transparent_background_color1=?;" ++
        "transparent_background_color2=?;transparent_background_color3=?\x1b\\");
    try std.testing.expectEqualStrings(
        "\x1b]21;transparent_background_color1=rgb:01/02/03@1.0000;" ++
            "transparent_background_color2=rgb:04/05/06@1.0000;" ++
            "transparent_background_color3=rgb:07/08/09@1.0000\x1b\\",
        terminal.replyBytes(),
    );
}

test "current Kitty transparent color query quota rolls back set and reply" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 2, 8);
    defer terminal.deinit();
    try feed(&terminal, "\x1b]21;transparent_background_color1=#010203@0.4\x1b\\");
    const query = "\x1b]21;transparent_background_color1=#aabbcc@0.3;transparent_background_color1=?\x1b\\";
    const response = "\x1b]21;transparent_background_color1=rgb:aa/bb/cc@0.2980\x1b\\";
    const filler = try @import("../support/reply_fill.zig").fill(
        &terminal,
        allocator,
        64 * 1024 - response.len + 1,
        false,
    );
    defer allocator.free(filler);
    try std.testing.expectError(error.ReplyLimit, terminal.feed(query));
    try std.testing.expectEqualSlices(u8, filler, terminal.replyBytes());
    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    try feed(&terminal, "\x1b]21;transparent_background_color1=?\x1b\\");
    try std.testing.expectEqualStrings(
        "\x1b]21;transparent_background_color1=rgb:01/02/03@0.4000\x1b\\",
        terminal.replyBytes(),
    );
}

test "Kitty OSC 21 multiple cursor keys refresh both banks from committed colors" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();

    try feed(&terminal, "\x1b]12;#112233\x1b\\\x1b]21;cursor_text=#445566\x1b\\");
    try std.testing.expectEqual(@as(?Rgb, .{ .r = 0x11, .g = 0x22, .b = 0x33 }), terminal.presentation().cursor);
    try std.testing.expectEqual(@as(?Rgb, .{ .r = 0x44, .g = 0x55, .b = 0x66 }), terminal.presentation().cursor_text);

    // The canonical OSC 21 parser sees every key; the old separate cursor
    // action parser only sees the first key and leaves stale Screen shadows.
    try feed(&terminal, "\x1b]21;foreground=#010203;cursor=#778899;cursor_text=#aabbcc\x1b\\");
    try std.testing.expectEqual(Rgb{ .r = 1, .g = 2, .b = 3 }, terminal.presentation().foreground);
    try std.testing.expectEqual(@as(?Rgb, .{ .r = 0x77, .g = 0x88, .b = 0x99 }), terminal.presentation().cursor);
    try std.testing.expectEqual(@as(?Rgb, .{ .r = 0xaa, .g = 0xbb, .b = 0xcc }), terminal.presentation().cursor_text);

    try feed(&terminal, "\x1b[?1049h");
    try std.testing.expectEqual(@as(?Rgb, .{ .r = 0x77, .g = 0x88, .b = 0x99 }), terminal.presentation().cursor);
    try std.testing.expectEqual(@as(?Rgb, .{ .r = 0xaa, .g = 0xbb, .b = 0xcc }), terminal.presentation().cursor_text);

    // Reapplying identical values and querying them must not turn a stale
    // cursor projection into a semantic update.
    try std.testing.expect(!(try terminal.feed("\x1b]21;cursor=#778899;cursor_text=#aabbcc\x1b\\")).stateChanged());
    const stable_cursor = terminal.presentation().cursor;
    try feed(&terminal, "\x1b]21;cursor=?;cursor_text=?\x1b\\");
    try std.testing.expectEqual(stable_cursor, terminal.presentation().cursor);
    try terminal.consumeReplyBytes(terminal.replyBytes().len);

    try feed(&terminal, "\x1b]21;cursor;cursor_text\x1b\\");
    try std.testing.expectEqual(@as(?Rgb, null), terminal.presentation().cursor);
    try std.testing.expectEqual(@as(?Rgb, null), terminal.presentation().cursor_text);
    try feed(&terminal, "\x1b[?1049l");
    try std.testing.expectEqual(@as(?Rgb, null), terminal.presentation().cursor);
    try std.testing.expectEqual(@as(?Rgb, null), terminal.presentation().cursor_text);
    try feed(&terminal, "\x1b]12;#0a0b0c\x1b\\");
    try std.testing.expectEqual(@as(?Rgb, .{ .r = 10, .g = 11, .b = 12 }), terminal.presentation().cursor);
    try feed(&terminal, "\x1b]112\x1b\\");
    try std.testing.expectEqual(@as(?Rgb, null), terminal.presentation().cursor);
}

test "unset dynamic cursor and selection queries never invent RGB or empty OSC replies" {
    // VT has no configured RGB to report for an automatic cursor or
    // unset selection. Do not send a malformed empty color field or
    // pretend that the visual auto-contrast cursor is always black.
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    for ([_]u16{ 12, 17, 19 }) |command| {
        var buffer: [64]u8 = undefined;
        const query = try std.fmt.bufPrint(&buffer, "\x1b]{d};?\x1b\\", .{command});
        try std.testing.expect(!(try terminal.feed(query)).stateChanged());
        try std.testing.expectEqualStrings("", terminal.replyBytes());
    }

    // A missing cursor or selection value must not block neighboring
    // known colors, change retained presentation or emit ghost replies.
    const before = terminal.presentation();
    try std.testing.expect((try terminal.feed("\x1b]10;?;?;?;?\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings(
        "\x1b]10;rgb:dcdc/dcdc/dcdc\x1b\\" ++
            "\x1b]11;rgb:1818/1919/2121\x1b\\",
        terminal.replyBytes(),
    );
    try std.testing.expectEqualDeep(before, terminal.presentation());
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
}

test "configured cursor and selection colors query exactly and reset to host baseline" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    var defaults: Terminal.ColorDefaults = .{};
    defaults.cursor = .{ .r = 0x12, .g = 0x34, .b = 0x56 };
    defaults.selection_background = .{ .r = 0x23, .g = 0x45, .b = 0x67 };
    defaults.selection_foreground = .{ .r = 0x34, .g = 0x56, .b = 0x78 };
    terminal.setColorDefaults(defaults);

    try std.testing.expect((try terminal.feed(
        "\x1b]12;?\x1b\\\x1b]17;?\x07\x1b]19;?\x1b\\",
    )).stateChanged());
    try std.testing.expectEqualStrings(
        "\x1b]12;rgb:1212/3434/5656\x1b\\" ++
            "\x1b]17;rgb:2323/4545/6767\x07" ++
            "\x1b]19;rgb:3434/5656/7878\x1b\\",
        terminal.replyBytes(),
    );
    try consumeReplies(&terminal);

    // Programs override the configured baseline, and resets restore
    // it without a second synthetic selection/default color owner.
    try std.testing.expect((try terminal.feed(
        "\x1b]12;#aabbcc\x1b\\\x1b]17;#ccddee\x1b\\\x1b]19;#ddeeff\x1b\\",
    )).stateChanged());
    try std.testing.expect((try terminal.feed(
        "\x1b]112\x1b\\\x1b]117\x07\x1b]119\x1b\\",
    )).stateChanged());
    const presentation = terminal.presentation();
    try std.testing.expectEqual(defaults.cursor, presentation.cursor);
    try std.testing.expectEqual(defaults.selection_background, presentation.selection_background);
    try std.testing.expectEqual(defaults.selection_foreground, presentation.selection_foreground);

    // A host preference replacement takes effect in the same owner.
    defaults.cursor = null;
    defaults.selection_background = null;
    defaults.selection_foreground = null;
    terminal.setColorDefaults(defaults);
    try std.testing.expect(!(try terminal.feed(
        "\x1b]12;?\x1b\\\x1b]17;?\x1b\\\x1b]19;?\x1b\\",
    )).stateChanged());
    try std.testing.expectEqualStrings("", terminal.replyBytes());
    try std.testing.expectEqual(@as(?Rgb, null), terminal.presentation().cursor);
    try std.testing.expectEqual(@as(?Rgb, null), terminal.presentation().selection_background);
    try std.testing.expectEqual(@as(?Rgb, null), terminal.presentation().selection_foreground);
}

test "Kitty invalid dynamic color clears override but Howl preserves last valid color" {
    for ([_]u16{ 10, 11, 12, 17, 19 }) |command| {
        var terminal = try Terminal.init(std.testing.allocator, 2, 8);
        defer terminal.deinit();
        var buf: [72]u8 = undefined;
        const set = try std.fmt.bufPrint(&buf, "\x1b]{d};#112233\x1b\\", .{command});
        try std.testing.expect((try terminal.feed(set)).stateChanged());
        const before = terminal.presentation();
        const expected: ?Rgb = .{ .r = 0x11, .g = 0x22, .b = 0x33 };
        const selected: ?Rgb = switch (command) {
            10 => before.foreground,
            11 => before.background,
            12 => before.cursor,
            17 => before.selection_background,
            19 => before.selection_foreground,
            else => return error.UnexpectedColorCommand,
        };
        try std.testing.expectEqual(expected, selected);
        const invalid = try std.fmt.bufPrint(&buf, "\x1b]{d};not-a-color\x07", .{command});
        try std.testing.expect(!(try terminal.feed(invalid)).stateChanged());
        try std.testing.expectEqualDeep(before, terminal.presentation());
    }

    // Pinned Kitty sends rgb:0000/0000/0000 when a nullable override
    // has no value. Howl cannot truthfully report an auto-derived
    // host color as a known RGB, so an unset query emits no response.
    for ([_]u16{ 12, 17, 19 }) |command| {
        var terminal = try Terminal.init(std.testing.allocator, 2, 8);
        defer terminal.deinit();
        var buf: [48]u8 = undefined;
        const query = try std.fmt.bufPrint(&buf, "\x1b]{d};?\x1b\\", .{command});
        try std.testing.expect(!(try terminal.feed(query)).stateChanged());
        try std.testing.expectEqualStrings("", terminal.replyBytes());
    }
}

test "xterm dynamic OSC 10 11 12 17 19 ignores invalid colors unlike Kitty" {
    // Originating xterm misc.c:ChangeColorsRequest uses AllocateTermColor;
    // failed XParseColor leaves previously configured colors untouched.
    // Pinned Kitty window.py:set_dynamic_color instead removes the
    // current override for the same invalid bytes. iTerm2 rejects too.
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();

    for ([_]u16{ 10, 11, 12, 17, 19 }) |command| {
        var set_buf: [64]u8 = undefined;
        const set = try std.fmt.bufPrint(&set_buf, "\x1b]{d};#345678\x1b\\", .{command});
        try std.testing.expect((try terminal.feed(set)).stateChanged());
    }
    const retained = terminal.presentation();

    // Mix both framing forms and preserve all five independent overrides.
    for ([_]u16{ 10, 11, 12, 17, 19 }, 0..) |command, index| {
        var bad_buf: [64]u8 = undefined;
        const end = if (index % 2 == 0) "\x07" else "\x1b\\";
        const invalid = try std.fmt.bufPrint(&bad_buf, "\x1b]{d};not-a-color{s}", .{ command, end });
        try std.testing.expect(!(try terminal.feed(invalid)).stateChanged());
        try std.testing.expectEqualDeep(retained, terminal.presentation());
    }
    try std.testing.expectEqualStrings("", terminal.replyBytes());
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());

    // The selected xterm values remain queryable and match BEL exactly.
    for ([_]u16{ 10, 11, 12, 17, 19 }) |command| {
        var query_buf: [32]u8 = undefined;
        const query = try std.fmt.bufPrint(&query_buf, "\x1b]{d};?\x07", .{command});
        try feed(&terminal, query);
        var expected_buf: [72]u8 = undefined;
        const expected = try std.fmt.bufPrint(&expected_buf, "\x1b]{d};rgb:3434/5656/7878\x07", .{command});
        try std.testing.expectEqualStrings(expected, terminal.replyBytes());
        try consumeReplies(&terminal);
    }
    try std.testing.expectEqualDeep(retained, terminal.presentation());
}

test "BEL-terminated color query overflow rolls back the exact reply packet" {
    // The last BEL byte is part of the xterm color reply transaction.
    // If it exceeds the 64-KiB queue bound, no incomplete reply, color
    // mutation or cursor side effect may escape the failed feed.
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 2, 8);
    defer terminal.deinit();
    try feed(&terminal, "\x1b]10;#112233\x1b\\");
    const before = terminal.presentation();
    const response = "\x1b]10;rgb:1111/2222/3333\x07";
    const fill = try reply_fill.fill(&terminal, allocator, expected_reply_bytes - response.len + 1, false);
    defer allocator.free(fill);

    try std.testing.expectError(error.ReplyLimit, terminal.feed("\x1b]10;?\x07"));
    try std.testing.expectEqualSlices(u8, fill, terminal.replyBytes());
    try std.testing.expectEqualDeep(before, terminal.presentation());
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
}

test "xterm color query replies preserve BEL or ST request termination" {
    // xterm charproc.c passes the OSC terminator to misc.c:do_osc,
    // then ChangeColorsRequest/ChangeAnsiColorRequest report with that
    // exact final byte. The color owner must not invent an ST reply for
    // a BEL-terminated request.
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();

    try feed(&terminal, "\x1b]4;1;#010203\x1b\\" ++
        "\x1b]10;#112233\x1b\\" ++
        "\x1b]12;#445566\x1b\\" ++
        "\x1b]17;#778899\x1b\\");
    const before = terminal.presentation();

    // Query and answer both terminated by BEL, including mixed palette
    // and cursor/selection dynamic colors, in exact admission order.
    try feed(&terminal, "\x1b]4;1;?\x07" ++
        "\x1b]10;?\x07" ++
        "\x1b]12;?\x07" ++
        "\x1b]17;?\x07");
    try std.testing.expectEqualStrings(
        "\x1b]4;1;rgb:0101/0202/0303\x07" ++
            "\x1b]10;rgb:1111/2222/3333\x07" ++
            "\x1b]12;rgb:4444/5555/6666\x07" ++
            "\x1b]17;rgb:7777/8888/9999\x07",
        terminal.replyBytes(),
    );
    try std.testing.expectEqualDeep(before, terminal.presentation());
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
    try consumeReplies(&terminal);

    // ST-terminated queries must keep existing exact ST reply behavior.
    try feed(&terminal, "\x1b]4;1;?\x1b\\\x1b]11;?\x1b\\");
    try std.testing.expectEqualStrings(
        "\x1b]4;1;rgb:0101/0202/0303\x1b\\" ++
            "\x1b]11;rgb:1818/1919/2121\x1b\\",
        terminal.replyBytes(),
    );
    try std.testing.expectEqualDeep(before, terminal.presentation());
    try consumeReplies(&terminal);

    // OSC 5 is another xterm color query using the same exact final-byte
    // rule. Preserve both its special index and the BEL terminator.
    try feed(&terminal, "\x1b]5;0;#abcdef\x1b\\");
    try feed(&terminal, "\x1b]5;0;?\x07");
    try std.testing.expectEqualStrings(
        "\x1b]5;0;rgb:abab/cdcd/efef\x07",
        terminal.replyBytes(),
    );
}

test "xterm OSC colors set query and reset palette and dynamic colors" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try feed(&terminal, "\x1b]4;1;#010203\x1b\\\x1b]10;#aabbcc\x1b\\\x1b]11;rgb:0d/0e/0f\x1b\\\x1b]12;red\x1b\\");
    try feed(&terminal, "\x1b]4;1;?\x1b\\\x1b]10;?\x1b\\\x1b]11;?\x1b\\\x1b]12;?\x1b\\");

    try std.testing.expectEqual(Rgb{ .r = 1, .g = 2, .b = 3 }, terminal.presentation().palette[1]);
    try std.testing.expectEqualStrings(
        "\x1b]4;1;rgb:0101/0202/0303\x1b\\" ++
            "\x1b]10;rgb:aaaa/bbbb/cccc\x1b\\" ++
            "\x1b]11;rgb:0d0d/0e0e/0f0f\x1b\\" ++
            "\x1b]12;rgb:ffff/0000/0000\x1b\\",
        terminal.replyBytes(),
    );

    try feed(&terminal, "\x1b]104;1\x1b\\\x1b]110\x1b\\\x1b]111\x1b\\\x1b]112\x1b\\");
    try std.testing.expectEqual(Rgb{ .r = 205, .g = 49, .b = 49 }, terminal.presentation().palette[1]);
    try std.testing.expectEqual(Rgb{ .r = 220, .g = 220, .b = 220 }, terminal.presentation().foreground);
    try std.testing.expectEqual(Rgb{ .r = 24, .g = 25, .b = 33 }, terminal.presentation().background);
    try std.testing.expectEqual(@as(?Rgb, null), terminal.presentation().cursor);
}

test "OSC color grammar scales short components and rejects trailing components" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b]4;1;#123;2;rgb:1/22/333/4")).stateChanged());
    try std.testing.expect((try terminal.feed("44;3;rgb:1/22/333\x1b\\")).stateChanged());
    var colors = terminal.presentation();
    try std.testing.expectEqual(Rgb{ .r = 0x11, .g = 0x22, .b = 0x33 }, colors.palette[1]);
    try std.testing.expectEqual(Terminal.default_presentation.palette[2], colors.palette[2]);
    try std.testing.expectEqual(Rgb{ .r = 0x11, .g = 0x22, .b = 0x33 }, colors.palette[3]);

    try std.testing.expect(!(try terminal.feed("\x1b]4;1;#123;2;rgb:1/22/333/444\x07")).stateChanged());
    colors = terminal.presentation();
    try std.testing.expectEqual(Rgb{ .r = 0x11, .g = 0x22, .b = 0x33 }, colors.palette[1]);
    try std.testing.expectEqual(Terminal.default_presentation.palette[2], colors.palette[2]);

    try std.testing.expect((try terminal.feed("\x1b]4;1;?\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings(
        "\x1b]4;1;rgb:1111/2222/3333\x1b\\",
        terminal.replyBytes(),
    );
}

test "xterm rgbi intensities support split commands and reject malformed values without mutation" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b]4;7;rgbi:0.5/0.25/")).stateChanged());
    try std.testing.expect((try terminal.feed("1\x1b\\")).stateChanged());
    try feed(&terminal, "\x1b]10;rgbi:1e-1/0/0.75\x07");
    const before = terminal.presentation();
    try std.testing.expectEqual(Rgb{ .r = 128, .g = 64, .b = 255 }, before.palette[7]);
    try std.testing.expectEqual(Rgb{ .r = 26, .g = 0, .b = 191 }, before.foreground);

    // Invalid intensities must not mutate an earlier accepted palette or
    // dynamic color, and an independent valid pair must still commit.
    for ([_][]const u8{
        "rgbi:1.01/0/0", "rgbi:-0.1/0/0",  "rgbi:nan/0/0",
        "rgbi:inf/0/0",  "rgbi:1//0",      "rgbi:1/0/0/0",
        "rgbi:1/blah/0", "rgbi:1e999/0/0",
    }) |invalid| {
        var sequence: [96]u8 = undefined;
        const command = try std.fmt.bufPrint(&sequence, "\x1b]4;7;{s}\x07", .{invalid});
        try std.testing.expect(!(try terminal.feed(command)).stateChanged());
        try std.testing.expectEqualDeep(before, terminal.presentation());
    }

    try feed(&terminal, "\x1b]4;7;rgbi:nan/0/0;8;rgbi:0/0.5/1\x1b\\");
    try std.testing.expectEqual(before.palette[7], terminal.presentation().palette[7]);
    try std.testing.expectEqual(Rgb{ .r = 0, .g = 128, .b = 255 }, terminal.presentation().palette[8]);
    try std.testing.expectEqual(before.foreground, terminal.presentation().foreground);

    try feed(&terminal, "\x1b]4;7;?\x1b\\\x1b]10;?\x07");
    try std.testing.expectEqualStrings(
        "\x1b]4;7;rgb:8080/4040/ffff\x1b\\" ++
            "\x1b]10;rgb:1a1a/0000/bfbf\x07",
        terminal.replyBytes(),
    );
}

test "rgbi grammar reaches all represented palette and dynamic color controls" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    const color = Rgb{ .r = 0, .g = 128, .b = 255 };

    for ([_]u16{ 11, 12, 17, 19 }) |command| {
        var bytes: [64]u8 = undefined;
        const osc = try std.fmt.bufPrint(&bytes, "\x1b]{d};rgbi:0/0.5/1\x1b\\", .{command});
        try feed(&terminal, osc);
    }
    try feed(&terminal, "\x1b]5;0;rgbi:0/0.5/1\x1b\\" ++
        "\x1b]21;foreground=rgbi:0/0.5/1;7=rgbi:0/0.5/1;selection_foreground=rgbi:0/0.5/1\x1b\\");
    const actual = terminal.presentation();
    try std.testing.expectEqual(color, actual.foreground);
    try std.testing.expectEqual(color, actual.background);
    try std.testing.expectEqual(@as(?Rgb, color), actual.cursor);
    try std.testing.expectEqual(@as(?Rgb, color), actual.selection_background);
    try std.testing.expectEqual(@as(?Rgb, color), actual.selection_foreground);
    try std.testing.expectEqual(color, actual.palette[7]);
    try std.testing.expectEqualStrings("", terminal.replyBytes());

    try feed(&terminal, "\x1b]5;0;?\x1b\\\x1b]21;foreground=?;7=?;selection_foreground=?\x1b\\");
    try std.testing.expectEqualStrings(
        "\x1b]5;0;rgb:0000/8080/ffff\x1b\\" ++
            "\x1b]21;foreground=rgb:00/80/ff;7=rgb:00/80/ff;selection_foreground=rgb:00/80/ff\x1b\\",
        terminal.replyBytes(),
    );
}

test "OSC reply RGB precision is an explicit host setting and Kitty 21 remains fixed" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    try feed(&terminal, "\x1b]4;1;#123456\x1b\\\x1b]5;0;#667788\x1b\\" ++
        "\x1b]10;#abcdef\x1b\\\x1b]11;#112233\x1b\\" ++
        "\x1b]12;#445566\x1b\\\x1b]17;#789abc\x1b\\\x1b]19;#778899\x1b\\");
    const colors = terminal.presentation();

    terminal.setColorReplyWidth(.bits8);
    try std.testing.expectEqualDeep(colors, terminal.presentation());
    try feed(&terminal, "\x1b]4;1;?\x1b\\\x1b]5;0;?\x07\x1b]10;?\x07\x1b]11;?\x1b\\" ++
        "\x1b]12;?\x1b\\\x1b]17;?\x1b\\\x1b]19;?\x1b\\\x1b]21;foreground=?\x1b\\");
    try std.testing.expectEqualStrings(
        "\x1b]4;1;rgb:12/34/56\x1b\\" ++
            "\x1b]5;0;rgb:66/77/88\x07" ++
            "\x1b]10;rgb:ab/cd/ef\x07" ++
            "\x1b]11;rgb:11/22/33\x1b\\" ++
            "\x1b]12;rgb:44/55/66\x1b\\" ++
            "\x1b]17;rgb:78/9a/bc\x1b\\" ++
            "\x1b]19;rgb:77/88/99\x1b\\" ++
            "\x1b]21;foreground=rgb:ab/cd/ef\x1b\\",
        terminal.replyBytes(),
    );
    try consumeReplies(&terminal);

    terminal.setColorReplyWidth(.bits16);
    try feed(&terminal, "\x1b]4;1;?\x07\x1b]10;?\x1b\\");
    try std.testing.expectEqualStrings(
        "\x1b]4;1;rgb:1212/3434/5656\x07" ++
            "\x1b]10;rgb:abab/cdcd/efef\x1b\\",
        terminal.replyBytes(),
    );
    try std.testing.expectEqualDeep(colors, terminal.presentation());
    try consumeReplies(&terminal);

    // Changing future encoding may not rewrite responses already queued.
    try feed(&terminal, "\x1b]4;1;?\x1b\\");
    terminal.setColorReplyWidth(.bits8);
    try feed(&terminal, "\x1b]4;1;?\x1b\\");
    try std.testing.expectEqualStrings(
        "\x1b]4;1;rgb:1212/3434/5656\x1b\\" ++
            "\x1b]4;1;rgb:12/34/56\x1b\\",
        terminal.replyBytes(),
    );
    try consumeReplies(&terminal);

    // Resizing prepares an independent reply owner. Its commit must carry
    // caller encoding policy, not silently revert RGB width to 16 bits.
    terminal.setColorReplyWidth(.bits8);
    try terminal.resize(4, 12);
    try consumeReplies(&terminal);
    try feed(&terminal, "\x1b]11;?\x07");
    try std.testing.expectEqualStrings("\x1b]11;rgb:11/22/33\x07", terminal.replyBytes());
    try consumeReplies(&terminal);

    // Host output policy survives RIS even though the existing canonical
    // color override remains owned by VT. Set 8-bit precision before RIS.
    terminal.setColorReplyWidth(.bits8);
    try feed(&terminal, "\x1bc\x1b]10;?\x1b\\");
    try std.testing.expectEqualStrings("\x1b]10;rgb:ab/cd/ef\x1b\\", terminal.replyBytes());
}

test "xterm extra dynamic colors set query and reset caller-neutral state" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try feed(&terminal, "\x1b]13;#010203\x1b\\\x1b]14;#040506\x1b\\\x1b]15;#070809\x1b\\\x1b]16;#0a0b0c\x1b\\\x1b]17;#0d0e0f\x1b\\\x1b]18;#101112\x1b\\\x1b]19;#131415\x1b\\");
    try feed(&terminal, "\x1b]13;?\x1b\\\x1b]14;?\x1b\\\x1b]15;?\x1b\\\x1b]16;?\x1b\\\x1b]17;?\x1b\\\x1b]18;?\x1b\\\x1b]19;?\x1b\\");

    try std.testing.expectEqualStrings(
        "\x1b]13;rgb:0101/0202/0303\x1b\\" ++
            "\x1b]14;rgb:0404/0505/0606\x1b\\" ++
            "\x1b]15;rgb:0707/0808/0909\x1b\\" ++
            "\x1b]16;rgb:0a0a/0b0b/0c0c\x1b\\" ++
            "\x1b]17;rgb:0d0d/0e0e/0f0f\x1b\\" ++
            "\x1b]18;rgb:1010/1111/1212\x1b\\" ++
            "\x1b]19;rgb:1313/1414/1515\x1b\\",
        terminal.replyBytes(),
    );

    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    try std.testing.expect((try terminal.feed(
        "\x1b]113\x1b\\\x1b]114\x1b\\\x1b]115\x1b\\\x1b]116\x1b\\" ++
            "\x1b]117\x1b\\\x1b]118\x1b\\\x1b]119\x1b\\",
    )).stateChanged());
    try std.testing.expect(!(try terminal.feed(
        "\x1b]13;?\x1b\\\x1b]14;?\x1b\\\x1b]15;?\x1b\\\x1b]16;?\x1b\\" ++
            "\x1b]17;?\x1b\\\x1b]18;?\x1b\\\x1b]19;?\x1b\\",
    )).stateChanged());
    // An unset host-neutral pointer, Tektronix or selection color
    // cannot truthfully answer rgb:..., including an empty color field.
    try std.testing.expectEqualStrings("", terminal.replyBytes());
}

test "unset xterm special palette queries cannot fabricate empty RGB packets" {
    // A host-neutral optional special color has no reportable RGB value.
    // Both xterm's OSC 5 index and OSC 4's index+256 alias must stay quiet.
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b]5;0;?\x07\x1b]4;256;?\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings("", terminal.replyBytes());

    // Only representable slots 0..4 exist. Reject 5..7 without indexing
    // beyond the bounded canonical storage or mutating neighboring state.
    try std.testing.expect(!(try terminal.feed("\x1b]5;5;#abcdef;7;?\x1b\\")).stateChanged());
    try std.testing.expectEqualStrings("", terminal.replyBytes());

    try feed(&terminal, "\x1b]5;1;#112233;2;#445566\x1b\\");
    try feed(&terminal, "\x1b]5;0;?;1;?;7;?;2;?\x07" ++
        "\x1b]4;256;?;257;?;258;?;260;?\x1b\\");
    try std.testing.expectEqualStrings(
        "\x1b]5;1;rgb:1111/2222/3333\x07" ++
            "\x1b]5;2;rgb:4444/5555/6666\x07" ++
            "\x1b]4;257;rgb:1111/2222/3333\x1b\\" ++
            "\x1b]4;258;rgb:4444/5555/6666\x1b\\",
        terminal.replyBytes(),
    );
    try std.testing.expect(terminal.title() == null);
}

test "unreportable special colors never consume saturated reply capacity" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 2, 8);
    defer terminal.deinit();
    const fill = try reply_fill.fill(&terminal, allocator, expected_reply_bytes, false);
    defer allocator.free(fill);
    const before = terminal.presentation();

    // No bytes of an absent color reply may be reserved or emitted.
    try std.testing.expect(!(try terminal.feed("\x1b]5;0;?\x07\x1b]4;256;?\x1b\\")).stateChanged());
    try std.testing.expectEqualSlices(u8, fill, terminal.replyBytes());
    try std.testing.expectEqualDeep(before, terminal.presentation());

    // A known color still fails atomically with no corrupt reply prefix.
    try std.testing.expectError(error.ReplyLimit, terminal.feed("\x1b]4;1;?\x07"));
    try std.testing.expectEqualSlices(u8, fill, terminal.replyBytes());
    try std.testing.expectEqualDeep(before, terminal.presentation());
}

test "xterm special colors via OSC 5 and OSC 4 special offsets" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try feed(&terminal, "\x1b]5;0;#010203;1;#040506\x1b\\\x1b]4;258;#070809;260;#0a0b0c\x1b\\");
    try feed(&terminal, "\x1b]5;0;?;1;?\x1b\\\x1b]4;258;?;260;?\x1b\\");

    try std.testing.expectEqualStrings(
        "\x1b]5;0;rgb:0101/0202/0303\x1b\\" ++
            "\x1b]5;1;rgb:0404/0505/0606\x1b\\" ++
            "\x1b]4;258;rgb:0707/0808/0909\x1b\\" ++
            "\x1b]4;260;rgb:0a0a/0b0b/0c0c\x1b\\",
        terminal.replyBytes(),
    );

    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    try std.testing.expect(!(try terminal.feed("\x1b]104;258;260\x1b\\")).stateChanged());
}

test "OSC palette and dynamic resets own exact bounds mutation and lifetime" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed(
        "\x1b]4;0;#010203;255;#040506\x1b\\" ++
            "\x1b]10;#070809;#0a0b0c;#0d0e0f\x1b\\" ++
            "\x1b]17;#101112;;#131415\x1b\\",
    )).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b]104;256;999;bad\x07")).stateChanged());

    try std.testing.expect(!(try terminal.feed("\x1b]104;0;")).stateChanged());
    try std.testing.expect((try terminal.feed("255\x1b\\")).stateChanged());
    var colors = terminal.presentation();
    try std.testing.expectEqual(Terminal.default_presentation.palette[0], colors.palette[0]);
    try std.testing.expectEqual(Terminal.default_presentation.palette[255], colors.palette[255]);

    try std.testing.expect((try terminal.feed(
        "\x1b]110\x07\x1b]111\x1b\\\x1b]112\x07\x1b]117\x1b\\\x1b]119\x07",
    )).stateChanged());
    colors = terminal.presentation();
    try std.testing.expectEqual(Terminal.default_presentation.foreground, colors.foreground);
    try std.testing.expectEqual(Terminal.default_presentation.background, colors.background);
    try std.testing.expectEqual(@as(?Rgb, null), colors.cursor);
    try std.testing.expectEqual(@as(?Rgb, null), colors.selection_background);
    try std.testing.expectEqual(@as(?Rgb, null), colors.selection_foreground);
    try std.testing.expect(!(try terminal.feed(
        "\x1b]110\x07\x1b]111\x1b\\\x1b]112\x07\x1b]117\x1b\\\x1b]119\x07",
    )).stateChanged());

    try std.testing.expect((try terminal.feed("\x1b]4;1;#212223\x1b\\\x1b]10;#313233\x1b\\")).stateChanged());
    try terminal.resize(4, 12);
    try std.testing.expect((try terminal.feed("\x1b[?1049h\x1bc\x1b[?1049l")).stateChanged());
    colors = terminal.presentation();
    try std.testing.expectEqual(Rgb{ .r = 33, .g = 34, .b = 35 }, colors.palette[1]);
    try std.testing.expectEqual(Rgb{ .r = 49, .g = 50, .b = 51 }, colors.foreground);

    try std.testing.expect((try terminal.feed("\x1b]104\x07")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b]104\x07")).stateChanged());
}

test "OSC 104 accepts shared signed padded indexes and preserves unsupported spellings" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();

    try feed(&terminal, "\x1b]4;0;#112233;1;#445566;2;#778899\x1b\\");
    const customized = terminal.presentation();
    try std.testing.expectEqual(Rgb{ .r = 0x11, .g = 0x22, .b = 0x33 }, customized.palette[0]);
    try std.testing.expectEqual(Rgb{ .r = 0x44, .g = 0x55, .b = 0x66 }, customized.palette[1]);
    try std.testing.expectEqual(Rgb{ .r = 0x77, .g = 0x88, .b = 0x99 }, customized.palette[2]);

    // Kitty's Python int and iTerm2's NSString scanner both accept
    // padded, explicitly positive indexes; the old Howl u8 parser did not.
    try std.testing.expect((try terminal.feed("\x1b]104; +1 ; 2 ;bad;256;-1\x07")).stateChanged());
    const reset_two = terminal.presentation();
    try std.testing.expectEqual(customized.palette[0], reset_two.palette[0]);
    try std.testing.expectEqual(Terminal.default_presentation.palette[1], reset_two.palette[1]);
    try std.testing.expectEqual(Terminal.default_presentation.palette[2], reset_two.palette[2]);

    // Signed negative zero also names the first palette index.
    try std.testing.expect((try terminal.feed("\x1b]104; -0 \x1b\\")).stateChanged());
    try std.testing.expectEqual(Terminal.default_presentation.palette[0], terminal.presentation().palette[0]);

    // Cross-reference conflicts remain explicit: pinned Kitty strips an
    // entirely blank OSC 104 payload and resets all; pinned iTerm2 ignores
    // that spelling. iTerm2's scanner accepts a numeric prefix followed
    // by junk, whereas pinned Kitty int rejects the entire field.
    try feed(&terminal, "\x1b]4;1;#010203\x1b\\");
    const before_conflicts = terminal.presentation();
    try std.testing.expect(!(try terminal.feed("\x1b]104;   \x07")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b]104;1junk\x1b\\")).stateChanged());
    try std.testing.expectEqual(before_conflicts, terminal.presentation());
}

test "xterm OSC 104 ignores whitespace-only reset where pinned Kitty resets all" {
    // xterm misc.c:ResetAnsiColorRequest performs reset-all only for
    // an empty payload. With whitespace it takes the selective branch,
    // then fails PartS2L before touching any index. Pinned Kitty
    // window.py:set_color_table_color instead tests not value.strip().
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed(
        "\x1b]4;1;#010203;2;#040506\x1b\\",
    )).stateChanged());
    const changed = terminal.presentation();
    try std.testing.expect(!(try terminal.feed("\x1b]104;  \t \x07")).stateChanged());
    try std.testing.expectEqualDeep(changed, terminal.presentation());
    try std.testing.expectEqualStrings("", terminal.replyBytes());
    try std.testing.expect(terminal.title() == null);
    // The same protocol's genuinely empty body resets all 256 slots.
    try std.testing.expect((try terminal.feed("\x1b]104\x07")).stateChanged());
    try std.testing.expectEqualDeep(
        Terminal.default_presentation.palette,
        terminal.presentation().palette,
    );
    try std.testing.expect(!(try terminal.feed("\x1b]104\x1b\\")).stateChanged());
}

test "xterm OSC 104 rejects numeric-prefix junk unlike pinned iTerm2 scanner" {
    // xterm misc.c:ResetAnsiColorRequest checks the complete decimal
    // token delimiter before mutating. Pinned iTerm2 resetColors and
    // NSStringITerm.integerNumber accept a numeric prefix and ignore
    // the remaining text. Kitty's Python int rejects the whole token.
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed(
        "\x1b]4;1;#010203;2;#040506\x1b\\",
    )).stateChanged());
    const changed = terminal.presentation();
    try std.testing.expect(!(try terminal.feed("\x1b]104;1junk\x1b\\")).stateChanged());
    try std.testing.expectEqualDeep(changed, terminal.presentation());
    try std.testing.expectEqualStrings("", terminal.replyBytes());
    // A complete numeric field is admitted, even when fragmented.
    try std.testing.expect(!(try terminal.feed("\x1b]104;")).stateChanged());
    try std.testing.expect((try terminal.feed("1\x1b\\")).stateChanged());
    try std.testing.expectEqual(
        Terminal.default_presentation.palette[1],
        terminal.presentation().palette[1],
    );
    try std.testing.expectEqual(changed.palette[2], terminal.presentation().palette[2]);
    try std.testing.expect(terminal.title() == null);
}

test "OSC color set and query failure rolls back the complete command" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 2, 4);
    defer terminal.deinit();

    const fill = try reply_fill.fill(&terminal, allocator, expected_reply_bytes - 1, false);
    defer allocator.free(fill);
    const before = terminal.presentation();

    try std.testing.expectError(
        error.ReplyLimit,
        terminal.feed("\x1b]4;1;#010203;2;?\x1b\\"),
    );
    try std.testing.expectEqual(before, terminal.presentation());
    try std.testing.expectEqual(fill.len, terminal.replyBytes().len);
    try std.testing.expectEqualSlices(u8, fill, terminal.replyBytes());

    // Query the known default background after a foreground set.
    // A null cursor/selection query is not a valid reply-overflow probe.
    try std.testing.expectError(error.ReplyLimit, terminal.feed("\x1b]10;#010203;?\x1b\\"));
    try std.testing.expectEqual(fill.len, terminal.replyBytes().len);
}

test "kitty color stack restores terminal color snapshots" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try feed(&terminal, "\x1b]21;foreground=#010203;1=#040506\x1b\\\x1b]30001\x1b\\");
    try feed(&terminal, "\x1b]21;foreground=#aabbcc;1=#ddeeff\x1b\\\x1b]30101\x1b\\");

    try std.testing.expectEqual(Rgb{ .r = 1, .g = 2, .b = 3 }, terminal.presentation().foreground);
    try std.testing.expectEqual(Rgb{ .r = 4, .g = 5, .b = 6 }, terminal.presentation().palette[1]);
}

test "kitty tui CSI save and restore colors use the same stack" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try feed(&terminal, "\x1b]21;foreground=#010203;1=#040506\x1b\\\x1b[#P");
    try feed(&terminal, "\x1b]21;foreground=#aabbcc;1=#ddeeff\x1b\\\x1b[#Q");

    try std.testing.expectEqual(Rgb{ .r = 1, .g = 2, .b = 3 }, terminal.presentation().foreground);
    try std.testing.expectEqual(Rgb{ .r = 4, .g = 5, .b = 6 }, terminal.presentation().palette[1]);
}

test "color stack restores displayed cursor colors in both banks" {
    const cases = [_]struct { push: []const u8, pop: []const u8 }{
        .{ .push = "\x1b[#P", .pop = "\x1b[#Q" },
        .{ .push = "\x1b[3#P", .pop = "\x1b[3#Q" },
        .{ .push = "\x1b]30001\x1b\\", .pop = "\x1b]30101\x1b\\" },
    };
    for (cases) |case| {
        for ([_]bool{ false, true }) |explicit| {
            var terminal = try Terminal.init(std.testing.allocator, 2, 4);
            defer terminal.deinit();
            if (explicit) try feed(&terminal, "\x1b]12;#112233\x1b\\\x1b]21;cursor_text=#445566\x1b\\");
            const before = terminal.presentation();
            try feed(&terminal, case.push);
            try feed(&terminal, "\x1b[?1049h\x1b]10;#d4be98\x1b\\\x1b]11;#282828\x1b\\\x1b]12;#995900\x1b\\\x1b]21;cursor_text=#aabbcc\x1b\\");
            const preview = terminal.presentation();
            try std.testing.expect(!(try terminal.feed("\x1b[11#Q")).stateChanged());
            try std.testing.expectEqual(preview, terminal.presentation());
            // Cancellation can split the cleanup at every control boundary.
            for (case.pop) |byte| {
                try feed(&terminal, &.{byte});
            }
            try std.testing.expectEqual(before, terminal.presentation());
            try feed(&terminal, "\x1b[?1049l");
            try std.testing.expectEqual(before, terminal.presentation());
            // Re-selecting an unchanged indexed snapshot is also a no-op.
            try std.testing.expect(!(try terminal.feed(case.pop)).stateChanged());
        }
    }
}

test "kitty color stack owns indexed sequential bounded and report semantics" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b]21;foreground=#010203\x1b\\\x1b[3")).stateChanged());
    try std.testing.expect((try terminal.feed("#P")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[3#P")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[3#Q")).stateChanged());

    try std.testing.expect((try terminal.feed("\x1b]21;foreground=#111213\x1b\\\x1b[1#Q")).stateChanged());
    try std.testing.expectEqual(Rgb{ .r = 220, .g = 220, .b = 220 }, terminal.presentation().foreground);
    try std.testing.expect((try terminal.feed("\x1b[3#Q")).stateChanged());
    try std.testing.expectEqual(Rgb{ .r = 1, .g = 2, .b = 3 }, terminal.presentation().foreground);

    try std.testing.expect((try terminal.feed("\x1b]21;foreground=#212223\x1b\\\x1b[#P")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b]21;foreground=#313233\x1b\\\x1b[#P")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b]21;foreground=#414243\x1b\\")).stateChanged());
    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    try std.testing.expect((try terminal.feed("\x1b G\x1b[#R")).stateChanged());
    try std.testing.expectEqualStrings("\x1b[1;2#Q", terminal.replyBytes());

    try std.testing.expect((try terminal.feed("\x1b[3#Q\x1b[#Q")).stateChanged());
    try std.testing.expectEqual(Rgb{ .r = 49, .g = 50, .b = 51 }, terminal.presentation().foreground);

    const rejected = try terminal.feed("\x1b[11#P\x1b[11#Q");
    try std.testing.expect(!rejected.stateChanged());

    try std.testing.expect((try terminal.feed(
        "\x1bc" ++
            "\x1b]21;foreground=#000001\x1b\\\x1b]30001\x1b\\" ++
            "\x1b]21;foreground=#000002\x1b\\\x1b]30001\x1b\\" ++
            "\x1b]21;foreground=#000003\x1b\\\x1b]30001\x1b\\" ++
            "\x1b]21;foreground=#000004\x1b\\\x1b]30001\x1b\\" ++
            "\x1b]21;foreground=#000005\x1b\\\x1b]30001\x1b\\" ++
            "\x1b]21;foreground=#000006\x1b\\\x1b]30001\x1b\\" ++
            "\x1b]21;foreground=#000007\x1b\\\x1b]30001\x1b\\" ++
            "\x1b]21;foreground=#000008\x1b\\\x1b]30001\x1b\\" ++
            "\x1b]21;foreground=#000009\x1b\\\x1b]30001\x1b\\" ++
            "\x1b]21;foreground=#00000a\x1b\\\x1b]30001\x1b\\" ++
            "\x1b]21;foreground=#00000b\x1b\\\x1b]30001\x1b\\",
    )).stateChanged());

    try std.testing.expect((try terminal.feed(
        "\x1b]30101\x1b\\\x1b]30101\x1b\\\x1b]30101\x1b\\\x1b]30101\x1b\\\x1b]30101\x1b\\" ++
            "\x1b]30101\x1b\\\x1b]30101\x1b\\\x1b]30101\x1b\\\x1b]30101\x1b\\\x1b]30101\x1b\\",
    )).stateChanged());
    try std.testing.expectEqual(Rgb{ .r = 0, .g = 0, .b = 2 }, terminal.presentation().foreground);

    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    try std.testing.expect((try terminal.feed("\x1bc\x1b[#R")).stateChanged());
    try std.testing.expectEqualStrings("\x1b[0;0#Q", terminal.replyBytes());

    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    const fill = try reply_fill.fill(&terminal, allocator, expected_reply_bytes - 1, false);
    defer allocator.free(fill);
    try std.testing.expectError(error.ReplyLimit, terminal.feed("\x1b[#R"));
    try std.testing.expectEqual(fill.len, terminal.replyBytes().len);
    try std.testing.expectEqualSlices(u8, fill, terminal.replyBytes());
}

test "pinned Kitty indexed color push is always dirty but Howl is idempotent" {
    // Frozen kitty/colors.c::colorprofile_push_colors returns true for
    // each accepted indexed push, including identical contents; screen.c
    // then marks the color profile dirty. Howl State.pushColor declines
    // the same-value indexed repeat without a semantic mutation.
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("\x1b[1#P")).stateChanged());
    const first = terminal.semanticSequence();
    try std.testing.expect(!(try terminal.feed("\x1b[1#P")).stateChanged());
    try std.testing.expectEqual(first, terminal.semanticSequence());
    try std.testing.expect((try terminal.feed("\x1b]21;foreground=#010203\x07")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[1#P")).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b[1#P")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b]21;foreground=#040506\x07")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b[1#Q")).stateChanged());
    try std.testing.expectEqual(Rgb{ .r = 1, .g = 2, .b = 3 }, terminal.presentation().foreground);
    try std.testing.expectEqualStrings("", terminal.replyBytes());
}

test "kitty indexed color stack exposes default-filled slot and reset extent differences" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();

    // Pinned Kitty zero-fills a popped sequential slot but leaves its
    // allocation extent addressable through indexed CSI Ps#Q. Howl restores
    // a complete initialized ColorState rather than zeroed slot bytes.
    try feed(&terminal, "\x1b]21;foreground=#010203;1=#040506\x1b\\\x1b]30001\x1b\\");
    try feed(&terminal, "\x1b]21;foreground=#111213;1=#141516\x1b\\\x1b]30101\x1b\\");
    try std.testing.expectEqual(Rgb{ .r = 1, .g = 2, .b = 3 }, terminal.presentation().foreground);
    try std.testing.expectEqual(Rgb{ .r = 4, .g = 5, .b = 6 }, terminal.presentation().palette[1]);

    try std.testing.expect((try terminal.feed("\x1b[1#Q")).stateChanged());
    try std.testing.expectEqual(Terminal.default_presentation.foreground, terminal.presentation().foreground);
    try std.testing.expectEqual(Terminal.default_presentation.palette[1], terminal.presentation().palette[1]);

    // Frozen Kitty retains the allocated slot extent through RIS and clears
    // its contents. Howl intentionally drops its slot_count on hard reset.
    try feed(&terminal, "\x1b]21;1=#010203\x1b\\\x1b]30001\x1b\\\x1bc");
    const after_reset = terminal.presentation();
    try std.testing.expect(!(try terminal.feed("\x1b[1#Q")).stateChanged());
    try std.testing.expectEqual(after_reset, terminal.presentation());
}

test "OSC 72 parses fragmented ordered commands with exact rejection and consumption" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    const before = terminal.semanticSequence();

    try std.testing.expect(!(try terminal.feed("\x1b]72;t=a:i=7:m=1;text/")).stateChanged());
    try std.testing.expect((try terminal.feed("uri-list\x1b\\\x1b]72;m=0;plain\x1b\\")).stateChanged());
    var head = terminal.consequenceHead().?.drag_drop;
    try std.testing.expectEqual(.enable, head.kind);
    try std.testing.expectEqual(@as(?u32, 7), head.client_id);
    try std.testing.expect(head.more);
    try std.testing.expectEqualStrings("text/uri-list", head.payload);
    const first_generation = head.generation;
    try terminal.consumeConsequence(first_generation);

    head = terminal.consequenceHead().?.drag_drop;
    try std.testing.expectEqual(.continuation, head.kind);
    try std.testing.expect(!head.more);
    try std.testing.expectEqualStrings("plain", head.payload);
    try std.testing.expect(head.generation > first_generation);
    try std.testing.expectError(error.StaleConsequence, terminal.consumeConsequence(first_generation));
    try terminal.consumeConsequence(head.generation);
    try std.testing.expect(terminal.consequenceHead() == null);
    try std.testing.expect(terminal.semanticSequence() > before);

    const stable = terminal.semanticSequence();
    try std.testing.expect((try terminal.feed("\x1b]72;t=r:x=0\x1b\\")).stateChanged());
    const unsupported = terminal.consequenceHead().?.drag_drop;
    try std.testing.expectEqual(.unsupported, unsupported.kind);
    try terminal.consumeConsequence(unsupported.generation);
    const after_rejection = terminal.semanticSequence();
    try std.testing.expect(!(try terminal.feed("\x1b]72;t=m:o=9\x1b\\")).stateChanged());
    try std.testing.expect(after_rejection > stable);
    try std.testing.expectEqual(after_rejection, terminal.semanticSequence());
}

test "OSC 72 queue saturation and aggregate allocation failure preserve exact head" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    for (0..expected_drag_drop_capacity) |index| {
        var bytes: [64]u8 = undefined;
        const command = try std.fmt.bufPrint(&bytes, "\x1b]72;t=q:i={d}\x1b\\", .{index});
        try std.testing.expect((try terminal.feed(command)).stateChanged());
    }
    const head = terminal.consequenceHead().?.drag_drop;
    try std.testing.expectError(error.ConsequencePressure, terminal.feed("\x1b]72;t=q:i=99\x1b\\"));
    try std.testing.expectEqual(head.generation, terminal.consequenceHead().?.drag_drop.generation);
    try std.testing.expectEqual(expected_drag_drop_capacity, terminal.consequenceCount());
}

test "OSC 72 aggregate payload budget rejects a valid ninth chunk transactionally" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    const payload = try std.testing.allocator.alloc(u8, expected_drag_drop_payload_bytes);
    defer std.testing.allocator.free(payload);
    @memset(payload, 'x');
    const prefix = "\x1b]72;t=a:m=1;";
    const suffix = "\x1b\\";
    const packet = try std.testing.allocator.alloc(u8, prefix.len + payload.len + suffix.len);
    defer std.testing.allocator.free(packet);
    @memcpy(packet[0..prefix.len], prefix);
    @memcpy(packet[prefix.len..][0..payload.len], payload);
    @memcpy(packet[prefix.len + payload.len ..], suffix);

    for (0..8) |_| try std.testing.expect((try terminal.feed(packet)).stateChanged());
    const head = terminal.consequenceHead().?.drag_drop;
    const sequence = terminal.semanticSequence();
    try std.testing.expectError(error.ConsequencePressure, terminal.feed(packet));
    try std.testing.expectEqual(head.generation, terminal.consequenceHead().?.drag_drop.generation);
    try std.testing.expectEqual(@as(u8, 8), terminal.consequenceCount());
    try std.testing.expectEqual(sequence, terminal.semanticSequence());
}

test "OSC 72 caller events use exact framing bounds and opaque base64" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    const query = try terminal.encodeDragDropEvent(
        .{ .query = .{ .client_id = 42 } },
        std.testing.allocator,
    );
    defer std.testing.allocator.free(query);
    try std.testing.expectEqualStrings("\x1b]72;t=q:i=42;\x1b\\", query);

    const data = try terminal.encodeDragDropEvent(.{ .data = .{
        .client_id = null,
        .index = 2,
        .more = true,
        .bytes = "file:///tmp/harmless\n",
    } }, std.testing.allocator);
    defer std.testing.allocator.free(data);
    try std.testing.expectEqualStrings(
        "\x1b]72;t=r:x=2:m=1;ZmlsZTovLy90bXAvaGFybWxlc3MK\x1b\\",
        data,
    );
    try std.testing.expectError(error.InvalidArgument, terminal.encodeDragDropEvent(.{ .data = .{
        .client_id = null,
        .index = 0,
        .more = false,
        .bytes = "",
    } }, std.testing.allocator));
}

test "Rex prompt occurrence admission is opt-in and transactional at FIFO capacity" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("\x1b]133;A\x07")).stateChanged());
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
    terminal.setProgramStatusConsumer(true);
    for (0..8) |_| try feed(&terminal, "\x1b]7501;state=working:id=old\x07");
    const before = terminal.shellMark();
    const identity = terminal.semanticSequence();
    const head = terminal.consequenceHead().?.id();
    try std.testing.expectError(error.ConsequencePressure, terminal.feed("\x1b]133;A;fresh\x1b\\"));
    try std.testing.expectEqual(before.generation, terminal.shellMark().generation);
    try std.testing.expectEqual(identity, terminal.semanticSequence());
    try std.testing.expectEqual(head, terminal.consequenceHead().?.id());
    try std.testing.expectEqual(@as(u16, 8), terminal.consequenceCount());
    try terminal.consumeConsequence(head);
    try feed(&terminal, "\x1b]133;A;fresh\x1b\\");
    try std.testing.expectEqual(before.generation + 1, terminal.shellMark().generation);
    try std.testing.expectEqualStrings("fresh", terminal.shellMark().metadata);
    for (0..7) |_| {
        const retained = terminal.consequenceHead().?.program_status;
        try std.testing.expect(retained.action == .report);
        try terminal.consumeConsequence(retained.generation);
    }
    const prompt = terminal.consequenceHead().?.program_status;
    try std.testing.expect(prompt.action == .prompt_started);
    try std.testing.expectEqualStrings("", prompt.payload);
    try terminal.consumeConsequence(prompt.generation);
    try std.testing.expect(!terminal.hasPendingProgramStatus());
    try std.testing.expectEqualStrings("", terminal.replyBytes());
}

test "Rex source message and whole wire bounds reach the typed host occurrence" {
    const allocator = std.testing.allocator;
    const status = Terminal.ProgramStatus;
    var terminal = try Terminal.init(allocator, 2, 8);
    defer terminal.deinit();
    terminal.setProgramStatusConsumer(true);

    const message: [2048]u8 = @splat('m');
    const title: [192]u8 = @splat('t');
    var message_encoded: [2732]u8 = undefined;
    var title_encoded: [256]u8 = undefined;
    const msg = std.base64.standard.Encoder.encode(&message_encoded, &message);
    const heading = std.base64.standard.Encoder.encode(&title_encoded, &title);
    var buffer: [4097]u8 = undefined;
    const report = try std.fmt.bufPrint(&buffer, "\x1b]7501;state=working:app=builder:title={s}:msg={s}\x1b\\", .{ heading, msg });
    try std.testing.expect(report.len > 2048);
    try std.testing.expect((try terminal.feed(report)).stateChanged());
    try std.testing.expect(terminal.consequenceHead() != null);
    const event = terminal.consequenceHead().?.program_status;
    var scratch: [status.max_msg_bytes]u8 = undefined;
    try std.testing.expectEqualStrings(&title, event.action.report.titleText(&scratch).?);
    try std.testing.expectEqualStrings(&message, event.action.report.messageText(&scratch).?);
    try terminal.consumeConsequence(event.generation);

    for ([_][]const u8{ "\x07", "\x1b\\" }) |terminator| {
        const prefix = "\x1b]7501;state=working:unknown=";
        for ([_]usize{ 4096, 4097 }) |length| {
            @memcpy(buffer[0..prefix.len], prefix);
            @memset(buffer[prefix.len .. length - terminator.len], 'x');
            @memcpy(buffer[length - terminator.len .. length], terminator);
            const before = terminal.semanticSequence();
            for (buffer[0 .. length - 1]) |byte| {
                try std.testing.expect(!(try terminal.feed(&.{byte})).stateChanged());
            }
            const completed = try terminal.feed(buffer[length - 1 .. length]);
            if (length == 4096) {
                try std.testing.expect(completed.stateChanged());
                const retained = terminal.consequenceHead().?.program_status;
                try std.testing.expect(retained.action.report.state == .working);
                try terminal.consumeConsequence(retained.generation);
            } else {
                try std.testing.expect(!completed.stateChanged());
                try std.testing.expectEqual(before, terminal.semanticSequence());
                try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
            }
        }
    }
    try feed(&terminal, "X");
    try std.testing.expectEqual(@as(u21, 'X'), terminal.semanticView(0).cellAt(0, 0));
}

test "Rex wire whitespace is trimmed at pair boundaries and never normalized inside values" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    terminal.setProgramStatusConsumer(true);
    try feed(&terminal, "\x1b]7501;\tstate = working\t:app=foo\tbar: progress = 100 \r:future=value\x07");
    const report = terminal.consequenceHead().?.program_status;
    try std.testing.expect(report.action.report.state == .working);
    try std.testing.expectEqualStrings("", report.action.report.app);
    try std.testing.expectEqual(@as(?u8, 100), report.action.report.progress);
    try terminal.consumeConsequence(report.generation);
    const sequence = terminal.semanticSequence();
    for ([_][]const u8{
        "\x1b]75\t01;state=clear\x07",
        "\x1b]75\x1b01;state=clear\x1b\\",
        "\x1b]7501;state=work\x00ing\x07",
        "\x1b]7501;state=clear:id=fo\to\x07",
    }) |invalid| {
        try std.testing.expect(!(try terminal.feed(invalid)).stateChanged());
        try std.testing.expectEqual(sequence, terminal.semanticSequence());
        try std.testing.expect(terminal.consequenceHead() == null);
    }
    // Ignored-control bytes still occupy the source's whole-wire budget.
    var overlong: [4097]u8 = undefined;
    const prefix = "\x1b]7501;state=working:unknown=";
    @memcpy(overlong[0..prefix.len], prefix);
    @memset(overlong[prefix.len .. overlong.len - 1], '\t');
    overlong[overlong.len - 1] = 0x07;
    try std.testing.expect(!(try terminal.feed(&overlong)).stateChanged());
    try std.testing.expect(terminal.consequenceHead() == null);
    try std.testing.expectEqualStrings("", terminal.replyBytes());
}

test "Rex feature reply precedes DA1 at every input split only with an opted in consumer" {
    const response = "\x1b]7501;?:states=idle,working,done,blocked,error:kinds=permission,question,auth";
    const da = "\x1b[?62;22c";
    for ([_][]const u8{ "\x07", "\x1b\\" }) |term| {
        var wire_buffer: [32]u8 = undefined;
        const wire = try std.fmt.bufPrint(&wire_buffer, "\x1b]7501;?{s}\x1b[c", .{term});
        var reply_buffer: [128]u8 = undefined;
        const expected = try std.fmt.bufPrint(&reply_buffer, "{s}{s}{s}", .{ response, term, da });
        for (0..wire.len + 1) |split| {
            var terminal = try Terminal.init(std.testing.allocator, 2, 8);
            defer terminal.deinit();
            for ([_]bool{ false, true, false }) |enabled| {
                terminal.setProgramStatusConsumer(enabled);
                try feed(&terminal, wire[0..split]);
                try feed(&terminal, wire[split..]);
                try std.testing.expectEqualStrings(if (enabled) expected else da, terminal.replyBytes());
                try consumeReplies(&terminal);
                try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
            }
        }
    }
}

test "Rex malformed optional escape pairs terminate without swallowing following bytes" {
    const cases = [_][]const u8{
        "\x1b]7501;state=working:app=bad\x1b\x07",
        "\x1b]7501;state=working:app=bad\x1b\x1b\\",
    };
    for (cases) |wire| {
        for (0..wire.len + 1) |split| {
            var terminal = try Terminal.init(std.testing.allocator, 2, 8);
            defer terminal.deinit();
            terminal.setProgramStatusConsumer(true);
            try feed(&terminal, wire[0..split]);
            try feed(&terminal, wire[split..]);
            try std.testing.expect(terminal.consequenceHead() != null);
            const event = terminal.consequenceHead().?.program_status;
            try std.testing.expect(event.action.report.state == .working);
            try std.testing.expectEqualStrings("", event.action.report.app);
            try terminal.consumeConsequence(event.generation);
            try feed(&terminal, "X");
            try std.testing.expectEqual(@as(u21, 'X'), terminal.semanticView(0).cellAt(0, 0));
            try std.testing.expectEqualStrings("", terminal.replyBytes());
        }
    }
}

test "Rex CAN SUB cancel incomplete reports and recover at every input split" {
    const cases = [_][]const u8{
        "\x1b]7501;state=clear\x18",
        "\x1b]7501;state=clear\x1a",
        "\x1b]7501;state=clear\x1b\x18",
        "\x1b]7501;state=clear\x1b\x1a",
    };
    for (cases) |wire| {
        for (0..wire.len + 1) |split| {
            var terminal = try Terminal.init(std.testing.allocator, 2, 8);
            defer terminal.deinit();
            terminal.setProgramStatusConsumer(true);
            try feed(&terminal, wire[0..split]);
            try feed(&terminal, wire[split..]);
            try std.testing.expect(terminal.consequenceHead() == null);
            try std.testing.expectEqualStrings("", terminal.replyBytes());
            try feed(&terminal, "X\x1b]7501;state=done:id=next\x07");
            try std.testing.expectEqual(@as(u21, 'X'), terminal.semanticView(0).cellAt(0, 0));
            const event = terminal.consequenceHead().?.program_status;
            try std.testing.expect(event.action.report.state == .done);
            try std.testing.expectEqualStrings("next", event.action.report.id);
            try terminal.consumeConsequence(event.generation);
            try std.testing.expect(terminal.consequenceHead() == null);
        }
    }
}

test "Kitty OSC 21 clips finite intensity components without changing legacy rejection" {
    const wire = "\x1b]21;foreground=rgbi:-0.5/+5e-1/1.25;foreground=?;7=rgbi:2/-2/.25;7=?;cursor=rgbi:+.1/-.1/1e+1;cursor=?\x1b\\";
    for (0..wire.len + 1) |split| {
        var terminal = try Terminal.init(std.testing.allocator, 2, 8);
        defer terminal.deinit();
        try feed(&terminal, wire[0..split]);
        try feed(&terminal, wire[split..]);
        try std.testing.expectEqualStrings("\x1b]21;foreground=rgb:00/80/ff;7=rgb:ff/00/40;cursor=rgb:1a/00/ff\x1b\\", terminal.replyBytes());
        const before = terminal.presentation();
        try std.testing.expectEqual(Rgb{ .r = 0, .g = 128, .b = 255 }, before.foreground);
        try std.testing.expectEqual(Rgb{ .r = 255, .g = 0, .b = 64 }, before.palette[7]);
        try std.testing.expectEqual(@as(?Rgb, .{ .r = 26, .g = 0, .b = 255 }), before.cursor);
        try terminal.consumeReplyBytes(terminal.replyBytes().len);
        try std.testing.expect(!(try terminal.feed("\x1b]4;7;rgbi:2/-2/.25\x07\x1b]10;rgbi:-0.5/0.5/1.25\x07")).stateChanged());
        try std.testing.expectEqualDeep(before, terminal.presentation());
        try std.testing.expectEqualStrings("", terminal.replyBytes());
    }
}

test "Kitty OSC 21 validates every hexadecimal digit and decimal intensity operand" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    try feed(&terminal, "\x1b]21;foreground=#123456;7=#abcdef\x07");
    const before = terminal.presentation();
    for ([_][]const u8{
        "#12z456789",     "#123x456789ab", "#123456789abz",
        "#1_2345",        "#+12345",       "rgb:1_2/34/56",
        "rgb:+1/2/3",     "rgb:1/2/3/4",   "rgbi:0x1p-1/0/1",
        "rgbi:1_0/0/1",   "rgbi:nan/0/1",  "rgbi:inf/0/1",
        "rgbi:1e999/0/1", "rgbi:1//0",     "rgbi:1/0/0/0",
    }) |invalid| {
        var bytes: [256]u8 = undefined;
        const command = try std.fmt.bufPrint(&bytes, "\x1b]21;foreground={s};7={s}\x07", .{ invalid, invalid });
        try std.testing.expect(!(try terminal.feed(command)).stateChanged());
        try std.testing.expectEqualDeep(before, terminal.presentation());
        try std.testing.expectEqualStrings("", terminal.replyBytes());
    }
    try feed(&terminal, "\x1b]21;foreground=#123456789;foreground=?;7=rgb:1/234/5678;7=?\x07");
    try std.testing.expectEqualStrings("\x1b]21;foreground=rgb:12/45/78;7=rgb:11/23/56\x1b\\", terminal.replyBytes());
}

test "Kitty OSC 21 transparent dynamic and bare reset remain distinct across the color stack" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    var defaults: Terminal.ColorDefaults = .{};
    defaults.transparent_background[0] = .{ .rgb = .{ .r = 1, .g = 2, .b = 3 }, .opacity = 0.4 };
    defaults.cursor = .{ .r = 4, .g = 5, .b = 6 };
    defaults.palette[7] = .{ .r = 7, .g = 8, .b = 9 };
    terminal.setColorDefaults(defaults);
    try feed(&terminal, "\x1b]21;transparent_background_color1=;transparent_background_color1=?;cursor=;cursor=?;7=;7=?\x07");
    try std.testing.expectEqualStrings("\x1b]21;transparent_background_color1=;cursor=;7=rgb:07/08/09\x1b\\", terminal.replyBytes());
    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    try feed(&terminal, "\x1b]30001\x1b\\\x1b]21;transparent_background_color1;cursor;7=#abcdef;transparent_background_color1=?;cursor=?;7=?\x07");
    try std.testing.expectEqualStrings("\x1b]21;transparent_background_color1=rgb:01/02/03@0.4000;cursor=rgb:04/05/06;7=rgb:ab/cd/ef\x1b\\", terminal.replyBytes());
    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    try feed(&terminal, "\x1b]30101\x1b\\\x1b]21;transparent_background_color1=?;cursor=?;7=?\x07");
    try std.testing.expectEqualStrings("\x1b]21;transparent_background_color1=;cursor=;7=rgb:07/08/09\x1b\\", terminal.replyBytes());
    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    try feed(&terminal, "\x1b]21;transparent_background_color1;cursor;7;transparent_background_color1=?;cursor=?;7=?\x07");
    try std.testing.expectEqualStrings("\x1b]21;transparent_background_color1=rgb:01/02/03@0.4000;cursor=rgb:04/05/06;7=rgb:07/08/09\x1b\\", terminal.replyBytes());
}

test "Kitty colour stack retains all palette and dynamic values independently of later host defaults" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    var expected: [256]Rgb = undefined;
    for (&expected, 0..) |*color, index| {
        const r: u8 = @intCast(index);
        color.* = .{ .r = r, .g = 255 - r, .b = r ^ 0xa5 };
        var bytes: [64]u8 = undefined;
        try feed(&terminal, try std.fmt.bufPrint(&bytes, "\x1b]21;{d}=rgb:{x:0>2}/{x:0>2}/{x:0>2}\x07", .{ index, color.r, color.g, color.b }));
    }
    try feed(&terminal, "\x1b]21;foreground=#112233;background=#445566;cursor=#778899;cursor_text=#aabbcc;selection_background=#ddeeff;selection_foreground=;transparent_background_color8=#123456@0.25\x07");
    const saved = terminal.presentation();
    try std.testing.expectEqualSlices(Rgb, &expected, &saved.palette);
    try std.testing.expectEqual(@as(?Rgb, .{ .r = 0x77, .g = 0x88, .b = 0x99 }), saved.cursor);
    try std.testing.expectEqual(@as(?Rgb, null), saved.selection_foreground);
    try std.testing.expectEqual(@as(?f32, 0.25), saved.transparent_background[7].?.opacity);
    try feed(&terminal, "\x1b]30001\x1b\\\x1b[?1049h");
    var defaults: Terminal.ColorDefaults = .{};
    defaults.foreground = .{ .r = 9, .g = 8, .b = 7 };
    defaults.cursor = .{ .r = 6, .g = 5, .b = 4 };
    defaults.palette[255] = .{ .r = 1, .g = 2, .b = 3 };
    terminal.setColorDefaults(defaults);
    try feed(&terminal, "\x1b]21;foreground=#000000;255=#ffffff;transparent_background_color8=\x07\x1b[#Q");
    try std.testing.expectEqualDeep(saved, terminal.presentation());
    try feed(&terminal, "\x1b[?1049l");
    try std.testing.expectEqualDeep(saved, terminal.presentation());
    try std.testing.expect(!(try terminal.feed("\x1b]30101\x07")).stateChanged());
    try feed(&terminal, "\x1b]21;foreground;cursor;255;transparent_background_color8;foreground=?;cursor=?;255=?;transparent_background_color8=?\x07");
    try std.testing.expectEqualStrings("\x1b]21;foreground=rgb:09/08/07;cursor=rgb:06/05/04;255=rgb:01/02/03;transparent_background_color8=\x1b\\", terminal.replyBytes());
    try std.testing.expectEqual(defaults.foreground, terminal.presentation().foreground);
    try std.testing.expectEqual(defaults.cursor, terminal.presentation().cursor);
    try std.testing.expectEqual(defaults.palette[255], terminal.presentation().palette[255]);
    try std.testing.expectEqual(@as(?@import("../../src/properties.zig").TransparentBackgroundColor, null), terminal.presentation().transparent_background[7]);
}

test "Kitty OSC 21 clipped set and dynamic unset roll back together on reply pressure" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    try feed(&terminal, "\x1b]21;foreground=#123456;transparent_background_color1=#abcdef@0.2\x07");
    const before = terminal.presentation();
    const command = "\x1b]21;foreground=rgbi:-1/0.5/2;foreground=?;transparent_background_color1=;transparent_background_color1=?\x1b\\";
    const response = "\x1b]21;foreground=rgb:00/80/ff;transparent_background_color1=\x1b\\";
    const filler = try reply_fill.fill(&terminal, std.testing.allocator, expected_reply_bytes - response.len + 1, false);
    defer std.testing.allocator.free(filler);
    try std.testing.expectError(error.ReplyLimit, terminal.feed(command));
    try std.testing.expectEqualDeep(before, terminal.presentation());
    try std.testing.expectEqualSlices(u8, filler, terminal.replyBytes());
    try consumeReplies(&terminal);
    try feed(&terminal, command);
    try std.testing.expectEqualStrings(response, terminal.replyBytes());
    try std.testing.expectEqual(Rgb{ .r = 0, .g = 128, .b = 255 }, terminal.presentation().foreground);
    try std.testing.expect(terminal.presentation().transparent_background[0] == null);
}

test "Kitty named colours preserve X11 values and case insensitive aliases" {
    const wire = "\x1b]21;foreground=AliceBlue;foreground=?;background=Dark Slate Gray;background=?;cursor=DebianRed;cursor=?;selection_foreground=GrEy42;selection_foreground=?;17=OrangeRed4;17=?;18=web green;18=?;transparent_background_color1=RebeccaPurple@0.5;transparent_background_color1=?\x07";
    for (0..wire.len + 1) |split| {
        var terminal = try Terminal.init(std.testing.allocator, 2, 8);
        defer terminal.deinit();
        try feed(&terminal, wire[0..split]);
        try feed(&terminal, wire[split..]);
        try std.testing.expectEqualStrings(
            "\x1b]21;foreground=rgb:f0/f8/ff;background=rgb:2f/4f/4f;cursor=rgb:d7/07/51;selection_foreground=rgb:6b/6b/6b;17=rgb:8b/25/00;18=rgb:00/80/00;transparent_background_color1=rgb:66/33/99@0.4980\x1b\\",
            terminal.replyBytes(),
        );
        const before = terminal.presentation();
        try consumeReplies(&terminal);
        try std.testing.expect(!(try terminal.feed("\x1b]21;foreground=aliceblu;17=OrangeRed4x;cursor=not a color\x07")).stateChanged());
        try std.testing.expectEqualDeep(before, terminal.presentation());
        try feed(&terminal, "\x1b]4;19;LightGoldenrodYellow;19;?\x07");
        try std.testing.expectEqualStrings("\x1b]4;19;rgb:fafa/fafa/d2d2\x07", terminal.replyBytes());
    }
}

test "Kitty visual bell colour has exact dynamic reset stack and query lifetime" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    try feed(&terminal, "\x1b]21;visual_bell=?;visual_bell=#123456;visual_bell=?;visual_bell=;visual_bell=?\x07");
    try std.testing.expectEqualStrings("\x1b]21;visual_bell=;visual_bell=rgb:12/34/56;visual_bell=\x1b\\", terminal.replyBytes());
    try consumeReplies(&terminal);
    try feed(&terminal, "\x1b]21;visual_bell=#abcdef\x07\x1b]30001\x1b\\\x1b]21;visual_bell=;visual_bell=?\x07\x1b[?1049h\x1b]30101\x1b\\\x1b]21;visual_bell=?\x07\x1b[?1049l\x1b]21;visual_bell=?\x07");
    try std.testing.expectEqualStrings("\x1b]21;visual_bell=\x1b\\\x1b]21;visual_bell=rgb:ab/cd/ef\x1b\\\x1b]21;visual_bell=rgb:ab/cd/ef\x1b\\", terminal.replyBytes());
    try consumeReplies(&terminal);
    try feed(&terminal, "\x1b]21;visual_bell;visual_bell=?\x07\x1b]21;visual_bell=#123456\x07\x1bc\x1b]21;visual_bell=?\x07");
    try std.testing.expectEqualStrings("\x1b]21;visual_bell=\x1b\\\x1b]21;visual_bell=\x1b\\", terminal.replyBytes());
}

test "visual bell configured colour remains distinct from snapshots and automatic preference" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    var defaults: Terminal.ColorDefaults = .{};
    defaults.visual_bell = .{ .r = 9, .g = 8, .b = 7 };
    terminal.setColorDefaults(defaults);
    try std.testing.expectEqual(defaults.visual_bell, terminal.presentation().visual_bell);
    try feed(&terminal, "\x1b]21;visual_bell=orange\x07\x1b]30001\x1b\\");
    const saved = terminal.presentation();
    try std.testing.expectEqual(@as(?Rgb, .{ .r = 255, .g = 165, .b = 0 }), saved.visual_bell);
    defaults.visual_bell = .{ .r = 1, .g = 2, .b = 3 };
    terminal.setColorDefaults(defaults);
    try feed(&terminal, "\x1b]30101\x1b\\");
    try std.testing.expectEqual(saved.visual_bell, terminal.presentation().visual_bell);
    try feed(&terminal, "\x1b]21;visual_bell=;visual_bell=?\x07");
    try std.testing.expectEqual(@as(?Rgb, null), terminal.presentation().visual_bell);
    try std.testing.expectEqualStrings("\x1b]21;visual_bell=\x1b\\", terminal.replyBytes());
    try consumeReplies(&terminal);
    try feed(&terminal, "\x1b]21;visual_bell;visual_bell=?\x07");
    try std.testing.expectEqual(defaults.visual_bell, terminal.presentation().visual_bell);
    try std.testing.expectEqualStrings("\x1b]21;visual_bell=rgb:01/02/03\x1b\\", terminal.replyBytes());
    // Setting preference does not manufacture a BEL or host flash request.
    try std.testing.expect(terminal.consequenceHead() == null);
    try feed(&terminal, "\x07");
    const bell = terminal.consequenceHead().?.bell;
    try terminal.consumeConsequence(bell.id);
    try std.testing.expect(terminal.consequenceHead() == null);
    try std.testing.expectEqual(defaults.visual_bell, terminal.presentation().visual_bell);
}

test "WezTerm RGBA SGR retains all three colour lanes and reports lossless rendition" {
    const wire = "\x1b[38:6::1:2:3:64;48:6:9:4:5:6:128;58:6:7:8:9:192;4mA\x1bP$qm\x1b\\\x1b[39;49;59mB";
    for (0..wire.len + 1) |split| {
        var terminal = try Terminal.init(std.testing.allocator, 2, 8);
        defer terminal.deinit();
        try feed(&terminal, wire[0..split]);
        try feed(&terminal, wire[split..]);
        const view = terminal.semanticView(0);
        const attrs = view.cellInfoAt(0, 0).attrs;
        const p = terminal.presentation();
        try std.testing.expectEqual(Rgb{ .r = 1, .g = 2, .b = 3, .a = 64 }, attrs.fg.resolve(p.foreground, &p.palette));
        try std.testing.expectEqual(Rgb{ .r = 4, .g = 5, .b = 6, .a = 128 }, attrs.bg.resolve(p.background, &p.palette));
        try std.testing.expectEqual(Rgb{ .r = 7, .g = 8, .b = 9, .a = 192 }, attrs.underline_color.resolve(p.foreground, &p.palette));
        try std.testing.expectEqualStrings("\x1bP1$r0;4;38:6::1:2:3:64;48:6::4:5:6:128;58:6::7:8:9:192m\x1b\\", terminal.replyBytes());
        const reset = view.cellInfoAt(0, 1).attrs;
        try std.testing.expectEqual(Terminal.default_cell_attrs.fg, reset.fg);
        try std.testing.expectEqual(Terminal.default_cell_attrs.bg, reset.bg);
        try std.testing.expectEqual(Terminal.default_cell_attrs.underline_color, reset.underline_color);
        try std.testing.expect(reset.underline);
    }
}

test "WezTerm RGBA malformed groups do not mutate colour or leak channel values into rendition" {
    for ([_][]const u8{ "38", "48", "58" }) |selector| {
        var terminal = try Terminal.init(std.testing.allocator, 2, 8);
        defer terminal.deinit();
        try feed(&terminal, "\x1b[31;44;58:5:2m");
        const before = terminal.semanticSequence();
        for ([_][]const u8{
            ":6::1:2:3", ":6::1:2:3:", ":6::1::3:4", ":6:1:2:3:256", ":6::1:2:3:4:5", ":6:1:2:3:4:", ":6::1:2:3:9999999999999", ";6;1;2;3;4",
        }) |invalid| {
            var command: [96]u8 = undefined;
            try std.testing.expect(!(try terminal.feed(try std.fmt.bufPrint(&command, "\x1b[{s}{s}m", .{ selector, invalid }))).stateChanged());
            try std.testing.expectEqual(before, terminal.semanticSequence());
        }
        try feed(&terminal, "A");
        const attrs = terminal.semanticView(0).cellInfoAt(0, 0).attrs;
        try std.testing.expectEqual(Terminal.Color.indexed(1), attrs.fg);
        try std.testing.expectEqual(Terminal.Color.indexed(4), attrs.bg);
        try std.testing.expectEqual(Terminal.Color.indexed(2), attrs.underline_color);
        try std.testing.expect(!attrs.bold and !attrs.dim and !attrs.italic and !attrs.underline);
    }
}

test "WezTerm RGBA alpha-only history attributes remain distinct through reflow" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 2, 6, 8);
    defer terminal.deinit();
    try feed(&terminal, "\x1b[38:6:1:2:3:0;48:6:4:5:6:64;58:6:7:8:9:128;4mA\x1b[38:6:1:2:3:255;48:6:4:5:6:192;58:6:7:8:9:255mB\x1b[0mC\r\nD\r\nE");
    for ([_]u16{ 6, 4, 6 }) |cols| {
        try terminal.resize(2, cols);
        const view = terminal.semanticView(1);
        const p = terminal.presentation();
        for ([_]u8{ 0, 255 }, [_]u8{ 64, 192 }, [_]u8{ 128, 255 }, 0..) |fg, bg, ul, col| {
            const cell = view.cellInfoAt(0, @intCast(col));
            try std.testing.expectEqual(@as(u32, @intCast('A' + col)), cell.codepoint);
            try std.testing.expectEqual(fg, cell.attrs.fg.resolve(p.foreground, &p.palette).a);
            try std.testing.expectEqual(bg, cell.attrs.bg.resolve(p.background, &p.palette).a);
            try std.testing.expectEqual(ul, cell.attrs.underline_color.resolve(p.foreground, &p.palette).a);
        }
    }
}

test "WezTerm dynamic RGBA admits slash CSS and byte-percent forms at every split" {
    const wire = "\x1b]10;rgba(127,127,127,0.4);rgba:efff/ecff/f4ff/d000;rgba:127 50% 255 64\x07\x1b]10;?;?;?\x1b\\";
    for (0..wire.len + 1) |split| {
        var terminal = try Terminal.init(std.testing.allocator, 2, 8);
        defer terminal.deinit();
        try feed(&terminal, wire[0..split]);
        try feed(&terminal, wire[split..]);
        const p = terminal.presentation();
        try std.testing.expectEqual(Rgb{ .r = 127, .g = 127, .b = 127, .a = 102 }, p.foreground);
        try std.testing.expectEqual(Rgb{ .r = 239, .g = 236, .b = 244, .a = 208 }, p.background);
        try std.testing.expectEqual(@as(?Rgb, .{ .r = 127, .g = 128, .b = 255, .a = 64 }), p.cursor);
        try std.testing.expectEqualStrings("\x1b]10;rgb:7f7f/7f7f/7f7f\x1b\\\x1b]11;rgb:efef/ecec/f4f4\x1b\\\x1b]12;rgb:7f7f/8080/ffff\x1b\\", terminal.replyBytes());
        try consumeReplies(&terminal);
        try feed(&terminal, "\x1b]21;foreground=?;background=?;cursor=?\x07");
        try std.testing.expectEqualStrings("\x1b]21;foreground=rgb:7f/7f/7f;background=rgb:ef/ec/f4;cursor=rgb:7f/80/ff\x1b\\", terminal.replyBytes());
        try std.testing.expectEqualDeep(p, terminal.presentation());
    }
}

test "WezTerm dynamic RGBA malformed values preserve state and other OSC grammars" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    try feed(&terminal, "\x1b]10;#123456;#abcdef;#fedcba\x07");
    const before = terminal.presentation();
    for ([_][]const u8{
        "rgba:1/2/3",         "rgba:1/2/3/4/5",  "rgba:1/2/3/zz",     "rgba:1/2/3/12345",
        "rgba:1 2 3 256",     "rgba:1 2 3 -1",   "rgba:1 2 3 nan",    "rgba:1 2 3 101%",
        "rgba(1,2,3)",        "rgba(1,2,3,1.1)", "rgba(256,2,3,1)",   "rgba(1,2,3,0.5)x",
        "rgba(1,2,3,0x1p-1)", "rgba(1,2,3,1_0)", "rgba(1,2,3,1e999)", "rgba(1,2,3,)",
    }) |invalid| {
        var bytes: [160]u8 = undefined;
        const command = try std.fmt.bufPrint(&bytes, "\x1b]10;{s}\x07", .{invalid});
        try std.testing.expect(!(try terminal.feed(command)).stateChanged());
        try std.testing.expectEqualDeep(before, terminal.presentation());
    }
    try std.testing.expect(!(try terminal.feed("\x1b]4;1;rgba:1/2/3/4\x07\x1b]21;foreground=rgba:1/2/3/4\x07\x1b]13;rgba:1/2/3/4\x07")).stateChanged());
    try std.testing.expectEqualDeep(before, terminal.presentation());
}

test "WezTerm dynamic alpha stack and reply pressure retain exact configured ownership" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    var defaults: Terminal.ColorDefaults = .{};
    defaults.foreground = .{ .r = 1, .g = 2, .b = 3, .a = 4 };
    defaults.background = .{ .r = 5, .g = 6, .b = 7, .a = 8 };
    defaults.cursor = .{ .r = 9, .g = 10, .b = 11, .a = 12 };
    terminal.setColorDefaults(defaults);
    try feed(&terminal, "\x1b]10;rgba:11/22/33/44;rgba(0,100%,0,50%);rgba:ab/cd/ef/0\x07");
    const saved = terminal.presentation();
    try std.testing.expectEqual(Rgb{ .r = 17, .g = 34, .b = 51, .a = 68 }, saved.foreground);
    try std.testing.expectEqual(Rgb{ .r = 0, .g = 255, .b = 0, .a = 128 }, saved.background);
    try std.testing.expectEqual(@as(?Rgb, .{ .r = 171, .g = 205, .b = 239, .a = 0 }), saved.cursor);
    try feed(&terminal, "\x1b]30001\x1b\\\x1b[?1049h\x1b]10;#ffffff;#000000;#aabbcc\x07\x1b]30101\x1b\\");
    try std.testing.expectEqualDeep(saved, terminal.presentation());
    try feed(&terminal, "\x1b[?1049l");
    try std.testing.expectEqualDeep(saved, terminal.presentation());
    const command = "\x1b]10;rgba:ff/ee/dd/00;?\x07";
    const response = "\x1b]11;rgb:0000/ffff/0000\x07";
    const filler = try reply_fill.fill(&terminal, std.testing.allocator, expected_reply_bytes - response.len + 1, false);
    defer std.testing.allocator.free(filler);
    try std.testing.expectError(error.ReplyLimit, terminal.feed(command));
    try std.testing.expectEqualDeep(saved, terminal.presentation());
    try std.testing.expectEqualSlices(u8, filler, terminal.replyBytes());
    try consumeReplies(&terminal);
    try feed(&terminal, command);
    try std.testing.expectEqualStrings(response, terminal.replyBytes());
    try std.testing.expectEqual(@as(u8, 0), terminal.presentation().foreground.a);
    try consumeReplies(&terminal);
    try feed(&terminal, "\x1b]110\x07\x1b]111\x07\x1b]112\x07");
    try std.testing.expectEqual(defaults.foreground, terminal.presentation().foreground);
    try std.testing.expectEqual(defaults.background, terminal.presentation().background);
    try std.testing.expectEqual(defaults.cursor, terminal.presentation().cursor);
}

test "WezTerm RGBA malformed mixed delimiter groups retire their complete colon suffix" {
    for ([_][]const u8{ "\x1b[", "\x9b" }) |intro| {
        for ([_][]const u8{ "38", "48", "58" }) |selector| {
            for ([_][]const u8{
                ";6:10:20:30:40:5",
                ";6;10:20:30:40:5",
                ";6;10;20;30;40:5",
                ";6:10:20",
            }) |invalid| {
                var storage: [96]u8 = undefined;
                const command = try std.fmt.bufPrint(&storage, "{s}{s}{s};3m", .{ intro, selector, invalid });
                for (0..command.len + 1) |split| {
                    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
                    defer terminal.deinit();
                    try feed(&terminal, "\x1b[31;44;58:5:2m");
                    try feed(&terminal, command[0..split]);
                    try feed(&terminal, command[split..]);
                    try feed(&terminal, "X");
                    const attrs = terminal.semanticView(0).cellInfoAt(0, 0).attrs;
                    var expected = Terminal.default_cell_attrs;
                    expected.fg = .indexed(1);
                    expected.bg = .indexed(4);
                    expected.underline_color = .indexed(2);
                    expected.italic = true;
                    try std.testing.expectEqualDeep(expected, attrs);
                }
            }
        }
    }
}

test "WezTerm RGBA rectangular admission and reports preserve alpha across both C1 profiles" {
    for ([_][]const u8{ "\x1b[", "\x9b" }, 0..) |intro, profile| {
        var storage: [160]u8 = undefined;
        const command = try std.fmt.bufPrint(&storage, "{s}1;1;1;2;38:6:1:2:3:0;48:6::4:5:6:128;58:6:9:7:8:9:192$r", .{intro});
        for (0..command.len + 1) |split| {
            var terminal = try Terminal.init(std.testing.allocator, 3, 8);
            defer terminal.deinit();
            if (profile == 1) try feed(&terminal, "\x1b G");
            try feed(&terminal, "\x1b[31;4m\x1b[1\"qAB\x1b[0\"q\x1b[2;3H\x1b[2*x");
            // Restore an independent indexed pen (SGR does not own protection).
            try feed(&terminal, "\x1b[31m");
            const initial = terminal.semanticView(0).cellInfoAt(0, 0);
            try std.testing.expect(initial.attrs.protected == .dec);
            try feed(&terminal, command[0..split]);
            try feed(&terminal, command[split..]);
            const view = terminal.semanticView(0);
            const p = terminal.presentation();
            for (0..2) |col| {
                const cell = view.cellInfoAt(0, @intCast(col));
                try std.testing.expectEqual(@as(u32, @intCast('A' + col)), cell.codepoint);
                try std.testing.expectEqual(initial.attrs.protected, cell.attrs.protected);
                try std.testing.expectEqual(Rgb{ .r = 1, .g = 2, .b = 3, .a = 0 }, cell.attrs.fg.resolve(p.foreground, &p.palette));
                try std.testing.expectEqual(Rgb{ .r = 4, .g = 5, .b = 6, .a = 128 }, cell.attrs.bg.resolve(p.background, &p.palette));
                try std.testing.expectEqual(Rgb{ .r = 7, .g = 8, .b = 9, .a = 192 }, cell.attrs.underline_color.resolve(p.foreground, &p.palette));
                try std.testing.expect(cell.attrs.underline);
            }
            try std.testing.expectEqual(@as(u16, 1), view.cursor_row);
            try std.testing.expectEqual(@as(u16, 2), view.cursor_col);
            try std.testing.expect(!(try terminal.feed(command)).stateChanged());
            const invalid = if (profile == 0) "\x1b[1;1;1;2;38:6::1::3:4$r" else "\x9b1;1;1;2;38:6::1::3:4$r";
            try std.testing.expect(!(try terminal.feed(invalid)).stateChanged());
            try feed(&terminal, if (profile == 0) "\x1b[1;1;1;2#|\x1b[1;2;1;2;38:6:1:2:3:255$r\x1b[1;1;1;2#|" else "\x9b1;1;1;2#|\x9b1;2;1;2;38:6:1:2:3:255$r\x9b1;1;1;2#|");
            try std.testing.expectEqualStrings(if (profile == 0)
                "\x1b[0;4;38:6::1:2:3:0;48:6::4:5:6:128;58:6::7:8:9:192m\x1b[0;4;48:6::4:5:6:128;58:6::7:8:9:192m"
            else
                "\x9b0;4;38:6::1:2:3:0;48:6::4:5:6:128;58:6::7:8:9:192m\x9b0;4;48:6::4:5:6:128;58:6::7:8:9:192m", terminal.replyBytes());
            try feed(&terminal, "Z");
            try std.testing.expectEqual(Terminal.Color.indexed(1), terminal.semanticView(0).cellInfoAt(1, 2).attrs.fg);
        }
    }
}

test "iTerm2 single inline PNG admits natural pixels only at completed BEL or ST" {
    const png = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVQI12P4z8Dwn4Hh/38AD/kD/XjubY4AAAAASUVORK5CYII=";
    for ([_][]const u8{ "\x07", "\x1b\\" }) |terminator| {
        var packet: [256]u8 = undefined;
        const wire = try std.fmt.bufPrint(&packet, "\x1b]1337;File=name=cHJldmlldy5wbmc=;size=1;width=auto;height=auto;inline=1:{s}{s}", .{ png, terminator });
        for (0..wire.len + 1) |split| {
            var terminal = try Terminal.init(std.testing.allocator, 3, 8);
            defer terminal.deinit();
            try terminal.setCellPixelSize(1, 1);
            try feed(&terminal, "\x1b[2;2H");
            const before = terminal.images(0).generation;
            const first = try terminal.feed(wire[0..split]);
            if (split != wire.len) {
                try std.testing.expect(!first.stateChanged());
                try std.testing.expectEqual(@as(usize, 0), terminal.images(0).imageCount());
            }
            try feed(&terminal, wire[split..]);
            const images = terminal.images(0);
            try std.testing.expectEqual(@as(usize, 1), images.imageCount());
            try std.testing.expectEqual(before + 1, images.generation);
            const image = images.image(0).?;
            try std.testing.expectEqual(@as(u32, 2), image.width);
            try std.testing.expectEqual(@as(u32, 1), image.height);
            try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255, 0, 0, 255, 255 }, image.pixels);
            const placement = images.placement(0).?;
            try std.testing.expectEqual(image.id, placement.image_id);
            try std.testing.expectEqual(@as(u16, 1), placement.row);
            try std.testing.expectEqual(@as(u16, 1), placement.col);
            try std.testing.expectEqual(@as(u32, 2), placement.pixel_width);
            try std.testing.expectEqual(@as(u32, 1), placement.pixel_height);
            try std.testing.expectEqual(@as(u16, 1), terminal.semanticView(0).cursor_row);
            try std.testing.expectEqual(@as(u16, 3), terminal.semanticView(0).cursor_col);
            try std.testing.expectEqual(@as(u8, 0), terminal.consequenceCount());
            try std.testing.expectEqualStrings("", terminal.replyBytes());
        }
    }
}

test "iTerm2 inline refusal never becomes a download consequence and bare FileEnd is retained" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    try terminal.setCellPixelSize(1, 1);
    const png = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVQI12P4z8Dwn4Hh/38AD/kD/XjubY4AAAAASUVORK5CYII=";
    const before = terminal.images(0).generation;
    for ([_][]const u8{
        "\x1b]1337;File=inline=1:!!!!\x07",
        "\x1b]1337;File=inline=1:SGVsbG8=\x1b\\",
        "\x1b]1337;File=inline=1;width=2pt:" ++ png ++ "\x07",
        "\x1b]1337;File=inline=1;inline=0:" ++ png ++ "\x07",
        "\x1b]1337;File=inline=1:" ++ png[0..8] ++ "\x01" ++ png[8..] ++ "\x07",
        "\x1b]1337;File=inli\x01ne=1:" ++ png ++ "\x07",
    }) |wire| {
        try std.testing.expect(!(try terminal.feed(wire)).stateChanged());
        try std.testing.expectEqual(@as(usize, 0), terminal.images(0).imageCount());
        try std.testing.expectEqual(before, terminal.images(0).generation);
        try std.testing.expectEqual(@as(u8, 0), terminal.consequenceCount());
    }
    try feed(&terminal, "\x1b]1337;File=inline=0:" ++ png ++ "\x07");
    const download = terminal.consequenceHead().?.file_transfer;
    try std.testing.expectEqualStrings("File=inline=0:" ++ png, download.payload);
    try terminal.consumeConsequence(download.generation);
    try feed(&terminal, "\x1b]1337;FileEnd\x1b\\");
    const end = terminal.consequenceHead() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("FileEnd", end.file_transfer.payload);
    try terminal.consumeConsequence(end.id());
}

fn inlinePngWithAncillaryText(allocator: std.mem.Allocator, text_bytes: u32) ![]u8 {
    const sample = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVQI12P4z8Dwn4Hh/38AD/kD/XjubY4AAAAASUVORK5CYII=";
    const decoder = std.base64.standard.Decoder;
    const source = try allocator.alloc(u8, try decoder.calcSizeForSlice(sample));
    defer allocator.free(source);
    try decoder.decode(source, sample);
    // A real PNG with a valid ancillary text chunk, not a synthetic length
    // or decoder bypass. The small decoded image remains exactly the same.
    const file = try allocator.alloc(u8, source.len + text_bytes + 12);
    defer allocator.free(file);
    const iend = source.len - 12;
    @memcpy(file[0..iend], source[0..iend]);
    std.mem.writeInt(u32, file[iend..][0..4], text_bytes, .big);
    @memcpy(file[iend + 4 ..][0..4], "tEXt");
    @memcpy(file[iend + 8 ..][0..8], "Comment\x00");
    @memset(file[iend + 16 .. iend + 8 + text_bytes], 'x');
    const crc = std.hash.Crc32.hash(file[iend + 4 .. iend + 8 + text_bytes]);
    std.mem.writeInt(u32, file[iend + 8 + text_bytes ..][0..4], crc, .big);
    @memcpy(file[iend + text_bytes + 12 ..], source[iend..]);
    const encoder = std.base64.standard.Encoder;
    const encoded = try allocator.alloc(u8, encoder.calcSize(file.len));
    const payload = encoder.encode(encoded, file);
    std.debug.assert(encoded.len == payload.len);
    return encoded;
}

test "iTerm2 selected inline capture exceeds metadata bound and recovers from overflow" {
    const allocator = std.testing.allocator;
    const payload = try inlinePngWithAncillaryText(allocator, 4096);
    defer allocator.free(payload);
    try std.testing.expect(payload.len > parser_mod.max_metadata_control_bytes);

    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    try terminal.setCellPixelSize(1, 1);
    try std.testing.expect(!(try terminal.feed("\x1b]1337;File=inline=1:")).stateChanged());
    try std.testing.expect(!(try terminal.feed(payload)).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b\\")).mutations.images);
    const original = terminal.images(0);
    try std.testing.expectEqual(@as(usize, 1), original.imageCount());
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255, 0, 0, 255, 255 }, original.image(0).?.pixels);
    const generation = original.generation;
    const oversized = try allocator.alloc(u8, parser_mod.max_inline_image_control_bytes);
    defer allocator.free(oversized);
    @memset(oversized, 'A');
    try std.testing.expect(!(try terminal.feed("\x1b]1337;File=inline=1:")).stateChanged());
    try std.testing.expect(!(try terminal.feed(oversized)).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x07")).stateChanged());
    try std.testing.expectEqual(generation, terminal.images(0).generation);
    try std.testing.expectEqual(@as(u8, 0), terminal.consequenceCount());
    // An ordinary metadata packet is still subject to its original limit,
    // even after the widened inline-image capture.
    try std.testing.expect(!(try terminal.feed("\x1b]1337;FilePart=")).stateChanged());
    try std.testing.expect(!(try terminal.feed(payload)).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x07")).stateChanged());
    try std.testing.expectEqual(@as(u8, 0), terminal.consequenceCount());
    try feed(&terminal, "\x1b[Hok\x1b]2;Recovered\x07");
    try std.testing.expectEqualStrings("Recovered", terminal.title().?);
    try std.testing.expectEqual(@as(u21, 'o'), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expectEqual(generation, terminal.images(0).generation);
}

test "iTerm2 inline PNG allocation failure preserves prior resource and allows a new request" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var terminal = try Terminal.init(failing.allocator(), 3, 8);
    defer terminal.deinit();
    try terminal.setCellPixelSize(1, 1);
    const png = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVQI12P4z8Dwn4Hh/38AD/kD/XjubY4AAAAASUVORK5CYII=";
    const packet = "\x1b]1337;File=inline=1:" ++ png;
    try feed(&terminal, packet ++ "\x07");
    const before = terminal.images(0);
    const retained = before.image(0).?;
    const placement = before.placement(0).?;
    try std.testing.expect(!(try terminal.feed(packet)).stateChanged());
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, terminal.feed("\x07"));
    const unchanged = terminal.images(0);
    try std.testing.expectEqual(before.generation, unchanged.generation);
    try std.testing.expectEqual(before.content_generation, unchanged.content_generation);
    try std.testing.expectEqual(@as(usize, 1), unchanged.imageCount());
    try std.testing.expectEqualDeep(placement, unchanged.placement(0).?);
    try std.testing.expectEqual(retained.id, unchanged.image(0).?.id);
    try std.testing.expectEqualSlices(u8, retained.pixels, unchanged.image(0).?.pixels);
    try std.testing.expectEqual(@as(u8, 0), terminal.consequenceCount());
    failing.fail_index = std.math.maxInt(usize);
    try feed(&terminal, packet ++ "\x1b\\");
    try std.testing.expectEqual(@as(usize, 2), terminal.images(0).imageCount());
    try std.testing.expectEqual(before.generation + 1, terminal.images(0).generation);
}

test "iTerm2 explicit image dimensions fit or stretch pixels independently of reserved cursor cells" {
    const sample = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVQI12P4z8Dwn4Hh/38AD/kD/XjubY4AAAAASUVORK5CYII=";
    const cases = [_]struct {
        fields: []const u8,
        width: u32,
        height: u32,
        cols: u16,
        rows: u16,
    }{
        .{ .fields = "width=2;height=3", .width = 6, .height = 3, .cols = 2, .rows = 3 },
        .{ .fields = "width=2;height=3;preserveAspectRatio=0", .width = 6, .height = 15, .cols = 2, .rows = 3 },
        .{ .fields = "width=7px;height=auto", .width = 7, .height = 3, .cols = 3, .rows = 1 },
        .{ .fields = "height=6px", .width = 12, .height = 6, .cols = 4, .rows = 2 },
        .{ .fields = "width=50%;height=25%", .width = 12, .height = 6, .cols = 4, .rows = 2 },
        .{ .fields = "width=33%;height=11%", .width = 7, .height = 3, .cols = 3, .rows = 1 },
        .{ .fields = "width=1px;height=1px", .width = 1, .height = 1, .cols = 1, .rows = 1 },
        .{ .fields = "width=auto;height=auto", .width = 2, .height = 1, .cols = 1, .rows = 1 },
        .{ .fields = "width=125%;height=1px", .width = 2, .height = 1, .cols = 8, .rows = 1 },
    };
    for (cases) |case| for ([_][]const u8{ "\x07", "\x1b\\" }) |term| {
        var terminal = try Terminal.init(std.testing.allocator, 8, 8);
        defer terminal.deinit();
        try terminal.setCellPixelSize(3, 5);
        try feed(&terminal, "\x1b[2;2H");
        var packet: [256]u8 = undefined;
        const wire = try std.fmt.bufPrint(&packet, "\x1b]1337;File=inline=1;{s}:{s}{s}", .{ case.fields, sample, term });
        try std.testing.expect(!(try terminal.feed(wire[0 .. wire.len - 1])).stateChanged());
        try std.testing.expect((try terminal.feed(wire[wire.len - 1 ..])).mutations.images);
        const images = terminal.images(0);
        try std.testing.expectEqual(@as(usize, 1), images.imageCount());
        const placed = images.placement(0) orelse return error.TestUnexpectedResult;
        try std.testing.expectEqual(@as(u16, 1), placed.row);
        try std.testing.expectEqual(@as(u16, 1), placed.col);
        try std.testing.expectEqual(@as(u32, 0), placed.cell_x);
        try std.testing.expectEqual(@as(u32, 0), placed.cell_y);
        try std.testing.expectEqual(case.width, placed.pixel_width);
        try std.testing.expectEqual(case.height, placed.pixel_height);
        try std.testing.expectEqual(@as(u32, 2), placed.source_width);
        try std.testing.expectEqual(@as(u32, 1), placed.source_height);
        try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255, 0, 0, 255, 255 }, images.image(0).?.pixels);
        try std.testing.expectEqual(case.rows, terminal.semanticView(0).cursor_row);
        try std.testing.expectEqual(@min(@as(u16, 7), 1 + case.cols), terminal.semanticView(0).cursor_col);
        try std.testing.expectEqual(@as(u8, 0), terminal.consequenceCount());
    };
}

test "iTerm2 automatic oversized natural image shrinks and invalid explicit dimensions are inert" {
    const png = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVQI12P4z8Dwn4Hh/38AD/kD/XjubY4AAAAASUVORK5CYII=";
    var terminal = try Terminal.init(std.testing.allocator, 1, 1);
    defer terminal.deinit();
    try std.testing.expect(!(try terminal.feed("\x1b]1337;File=inline=1:" ++ png ++ "\x07")).stateChanged());
    try terminal.setCellPixelSize(1, 1);
    try std.testing.expect((try terminal.feed("\x1b]1337;File=inline=1:" ++ png ++ "\x07")).mutations.images);
    const before = terminal.images(0);
    const placement = before.placement(0) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u32, 1), placement.pixel_width);
    try std.testing.expectEqual(@as(u32, 1), placement.pixel_height);
    for ([_][]const u8{
        "width=0",          "width=0px",        "width=0%",           "width=-1",   "width=+1",  "width=1.5px",
        "width=4294967296", "width=4294967295", "width=2px",          "height=1px", "height=2",  "height=4294967295px",
        "width=1; width=1", "width=1;width=1",  "width=1%;height=1%", "width=",     "height=px", "preserveAspectRatio=2",
    }) |fields| {
        var packet: [256]u8 = undefined;
        const wire = try std.fmt.bufPrint(&packet, "\x1b]1337;File=inline=1;{s}:{s}\x1b\\", .{ fields, png });
        try std.testing.expect(!(try terminal.feed(wire)).stateChanged());
        const after = terminal.images(0);
        try std.testing.expectEqual(before.generation, after.generation);
        try std.testing.expectEqual(before.content_generation, after.content_generation);
        try std.testing.expectEqual(@as(usize, 1), after.imageCount());
        try std.testing.expectEqualDeep(placement, after.placement(0).?);
        try std.testing.expectEqual(@as(u8, 0), terminal.consequenceCount());
    }
}

test "iTerm2 multipart PNG concatenates every base64 split and publishes only at bare FileEnd" {
    const sample = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVQI12P4z8Dwn4Hh/38AD/kD/XjubY4AAAAASUVORK5CYII=";
    for (1..sample.len) |split| {
        var terminal = try Terminal.init(std.testing.allocator, 4, 8);
        defer terminal.deinit();
        try terminal.setCellPixelSize(3, 5);
        try std.testing.expect(!(try terminal.feed("\x1b]1337;MultipartFile=inline=1;width=6px;height=10px;size=1\x07")).stateChanged());
        try std.testing.expectEqual(@as(u8, 0), terminal.consequenceCount());
        var packet: [192]u8 = undefined;
        const first = try std.fmt.bufPrint(&packet, "\x1b]1337;FilePart={s}\x1b\\", .{sample[0..split]});
        for (first) |byte| try std.testing.expect(!(try terminal.feed(&.{byte})).stateChanged());
        try feed(&terminal, "A\x1b[2;2H");
        try std.testing.expect(!(try terminal.feed("\x1b]1337;MultipartFileUnknown=value\x07")).stateChanged());
        const second = try std.fmt.bufPrint(&packet, "\x1b]1337;FilePart={s}\x07", .{sample[split..]});
        try std.testing.expect(!(try terminal.feed(second)).stateChanged());
        try std.testing.expectEqual(@as(usize, 0), terminal.images(0).imageCount());
        try std.testing.expectEqual(@as(u8, 0), terminal.consequenceCount());
        const before = terminal.images(0).generation;
        try std.testing.expect(!(try terminal.feed("\x1b]1337;FileEnd\x1b")).stateChanged());
        try std.testing.expect((try terminal.feed("\\")).mutations.images);
        const images = terminal.images(0);
        try std.testing.expectEqual(before + 1, images.generation);
        try std.testing.expectEqual(@as(usize, 1), images.imageCount());
        try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255, 0, 0, 255, 255 }, images.image(0).?.pixels);
        const placed = images.placement(0).?;
        try std.testing.expectEqual(@as(u16, 1), placed.row);
        try std.testing.expectEqual(@as(u16, 1), placed.col);
        try std.testing.expectEqual(@as(u32, 6), placed.pixel_width);
        try std.testing.expectEqual(@as(u32, 3), placed.pixel_height);
        try std.testing.expectEqual(@as(u16, 2), terminal.semanticView(0).cursor_row);
        try std.testing.expectEqual(@as(u16, 3), terminal.semanticView(0).cursor_col);
        try std.testing.expectEqual(@as(u21, 'A'), terminal.semanticView(0).cellAt(0, 0));
        try std.testing.expect(!(try terminal.feed("\x1b]1337;FileEnd\x07\x1b]1337;FilePart=AAAA\x07")).stateChanged());
        try std.testing.expectEqual(images.generation, terminal.images(0).generation);
        try std.testing.expectEqual(@as(u8, 0), terminal.consequenceCount());
        try std.testing.expectEqualStrings("", terminal.replyBytes());
    }
}

test "iTerm2 failed inline multipart suppresses stale parts until a fresh start" {
    const sample = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVQI12P4z8Dwn4Hh/38AD/kD/XjubY4AAAAASUVORK5CYII=";
    const start = "\x1b]1337;MultipartFile=inline=1\x07";
    const part = "\x1b]1337;FilePart=" ++ sample ++ "\x07";
    const end = "\x1b]1337;FileEnd\x07";
    for ([_][]const u8{
        "\x1b]1337;FilePart=!!!!\x07",
        "\x1b]1337;FilePart=AA==\x07\x1b]1337;FilePart=AAAA\x07",
        "\x1b]1337;FilePart=AA\x01AA\x07",
        "\x1b]1337;FilePart=AAAA\x18",
        "\x1b]1337;FilePart=AAAA\x1a",
        "\x1b]1337;FilePart=AAAA\x1bX\x07",
        "\x1b]1337;FileEnd=legacy\x07",
        "\x1b]1337;FileEnd\x01\x07",
        "\x1b]1337;FilePart\x07",
        "\x1b]1337;FilePart=\x07",
        "\x1b]1337;MultipartFile=inline=invalid\x07",
        "\x1b]1337;MultipartFile=inline=1;width=0\x07",
        "\x1b]1337;MultipartFile=inline=1;in\x01line=1\x07",
        "\x1b[?47h\x1b[?47l",
        "\x1bc",
    }) |bad| {
        var terminal = try Terminal.init(std.testing.allocator, 4, 8);
        defer terminal.deinit();
        try terminal.setCellPixelSize(3, 5);
        try feed(&terminal, start ++ "\x1b]1337;FilePart=iVBO\x07");
        try feed(&terminal, bad);
        const before = terminal.images(0).generation;
        try std.testing.expect(!(try terminal.feed(part ++ end)).stateChanged());
        try std.testing.expectEqual(before, terminal.images(0).generation);
        try std.testing.expectEqual(@as(usize, 0), terminal.images(0).imageCount());
        try std.testing.expectEqual(@as(u8, 0), terminal.consequenceCount());
        try feed(&terminal, start ++ part ++ end);
        try std.testing.expectEqual(@as(usize, 1), terminal.images(0).imageCount());
        try std.testing.expectEqual(@as(u8, 0), terminal.consequenceCount());
        // An explicit non-inline multipart start reopens the legacy opaque lane.
        try feed(&terminal, "\x1b]1337;MultipartFile=inline=0\x07\x1b]1337;FilePart=QQ==\x07" ++ end);
        try std.testing.expectEqual(@as(u8, 3), terminal.consequenceCount());
    }
}

test "iTerm2 multipart admits a real PNG across the conservative one MiB wire bound" {
    const allocator = std.testing.allocator;
    const encoded = try inlinePngWithAncillaryText(allocator, 800 * 1024);
    defer allocator.free(encoded);
    const max_part = parser_mod.max_inline_part_control_bytes - "FilePart=".len;
    try std.testing.expect(encoded.len > max_part);
    var terminal = try Terminal.init(allocator, 4, 8);
    defer terminal.deinit();
    try terminal.setCellPixelSize(3, 5);
    const start = "\x1b]1337;MultipartFile=inline=1\x07";
    const part = "\x1b]1337;FilePart=";
    const end = "\x1b]1337;FileEnd\x07";
    try std.testing.expect(!(try terminal.feed(start ++ part)).stateChanged());
    try std.testing.expect(!(try terminal.feed(encoded[0..max_part])).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b\\")).stateChanged());
    try std.testing.expect(!(try terminal.feed(part)).stateChanged());
    try std.testing.expect(!(try terminal.feed(encoded[max_part..])).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x07")).stateChanged());
    try std.testing.expectEqual(@as(usize, 0), terminal.images(0).imageCount());
    try std.testing.expect((try terminal.feed(end)).mutations.images);
    try std.testing.expectEqual(@as(usize, 1), terminal.images(0).imageCount());
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255, 0, 0, 255, 255 }, terminal.images(0).image(0).?.pixels);
    const generation = terminal.images(0).generation;
    try std.testing.expect(!(try terminal.feed(start ++ part)).stateChanged());
    try std.testing.expect(!(try terminal.feed(encoded[0 .. max_part + 1])).stateChanged());
    try std.testing.expect(!(try terminal.feed("\x1b\\" ++ end)).stateChanged());
    try std.testing.expectEqual(generation, terminal.images(0).generation);
    try std.testing.expectEqual(@as(u8, 0), terminal.consequenceCount());
    // Fresh alternate-bank transaction is independent of the primary image.
    const primary_id = terminal.images(0).image(0).?.id;
    try feed(&terminal, "\x1b[?47h" ++ start ++ part ++ "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVQI12P4z8Dwn4Hh/38AD/kD/XjubY4AAAAASUVORK5CYII=\x07" ++ end);
    const alternate = terminal.images(0);
    try std.testing.expectEqual(@as(usize, 2), alternate.imageCount());
    var it = alternate.placementIterator();
    const alternate_id = (it.next() orelse return error.TestUnexpectedResult).placement.image_id;
    try std.testing.expect(alternate_id != primary_id);
    try std.testing.expect(it.next() == null);
    try feed(&terminal, "\x1b[?47l");
    const primary = terminal.images(0);
    it = primary.placementIterator();
    try std.testing.expectEqual(primary_id, (it.next() orelse return error.TestUnexpectedResult).placement.image_id);
    try std.testing.expect(it.next() == null);
}

test "iTerm2 multipart allocation failures abort staging and final decode without image mutation" {
    const sample = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVQI12P4z8Dwn4Hh/38AD/kD/XjubY4AAAAASUVORK5CYII=";
    const start = "\x1b]1337;MultipartFile=inline=1\x07";
    const part = "\x1b]1337;FilePart=" ++ sample;
    const end = "\x1b]1337;FileEnd";
    for ([_]bool{ false, true }) |fail_finish| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        var terminal = try Terminal.init(failing.allocator(), 4, 8);
        defer terminal.deinit();
        try terminal.setCellPixelSize(3, 5);
        try feed(&terminal, "\x1b]1337;File=inline=1:" ++ sample ++ "\x07");
        const before = terminal.images(0);
        try std.testing.expect(!(try terminal.feed(start ++ part)).stateChanged());
        if (fail_finish) try std.testing.expect(!(try terminal.feed("\x07" ++ end)).stateChanged());
        failing.fail_index = failing.alloc_index;
        try std.testing.expectError(error.OutOfMemory, terminal.feed("\x07"));
        failing.fail_index = std.math.maxInt(usize);
        try std.testing.expect(!(try terminal.feed(part ++ "\x07" ++ end ++ "\x07")).stateChanged());
        try std.testing.expectEqual(before.generation, terminal.images(0).generation);
        try std.testing.expectEqual(@as(usize, 1), terminal.images(0).imageCount());
        try std.testing.expectEqual(@as(u8, 0), terminal.consequenceCount());
        try feed(&terminal, start ++ part ++ "\x07" ++ end ++ "\x07");
        try std.testing.expectEqual(@as(usize, 2), terminal.images(0).imageCount());
    }
}

test "iTerm2 inline images do not acquire opaque file FIFO capacity or advertise FILE" {
    const sample = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVQI12P4z8Dwn4Hh/38AD/kD/XjubY4AAAAASUVORK5CYII=";
    var terminal = try Terminal.init(std.testing.allocator, 4, 8);
    defer terminal.deinit();
    try terminal.setCellPixelSize(3, 5);
    try feed(&terminal, "\x1b[?1004h");
    try consumeReplies(&terminal);
    for (0..expected_file_transfer_capacity) |index| {
        var bytes: [96]u8 = undefined;
        const wire = try std.fmt.bufPrint(&bytes, "\x1b]5113;opaque-{d}\x1b\\", .{index});
        try std.testing.expect((try terminal.feed(wire)).stateChanged());
    }
    try std.testing.expectEqual(expected_file_transfer_capacity, terminal.consequenceCount());
    const sequence = terminal.semanticSequence();
    // Do not advertise even with focus enabled. The author F code collides
    // with FILE, and the complete feature-reporting profile is not selected.
    try std.testing.expect(!(try terminal.feed("\x1b]1337;Capabilities\x1b\\")).stateChanged());
    try std.testing.expectEqual(sequence, terminal.semanticSequence());
    try std.testing.expectEqualStrings("", terminal.replyBytes());

    const single = "\x1b]1337;File=inline=1:" ++ sample ++ "\x07";
    try std.testing.expect((try terminal.feed(single)).mutations.images);
    try std.testing.expect(!(try terminal.feed("\x1b]1337;MultipartFile=inline=1\x07\x1b]1337;FilePart=" ++ sample ++ "\x1b\\")).stateChanged());
    const prior = terminal.semanticSequence();
    const generation = terminal.images(0).generation;
    for ([_][]const u8{
        "\x1b]1337;Capabilities\x07",
        "\x1b]1337;Capabilities\x1b\\",
        "\x9d1337;Capabilities\x9c",
        "\x1b]1337;Capabilities=F\x1b\\",
    }) |query| {
        for (0..query.len + 1) |split| {
            try std.testing.expect(!(try terminal.feed(query[0..split])).stateChanged());
            try std.testing.expect(!(try terminal.feed(query[split..])).stateChanged());
            try std.testing.expectEqual(prior, terminal.semanticSequence());
            try std.testing.expectEqual(generation, terminal.images(0).generation);
            try std.testing.expectEqualStrings("", terminal.replyBytes());
            try std.testing.expectEqual(expected_file_transfer_capacity, terminal.consequenceCount());
        }
    }
    try std.testing.expect((try terminal.feed("\x1b]1337;FileEnd\x1b\\")).mutations.images);
    try std.testing.expectEqual(@as(usize, 2), terminal.images(0).imageCount());
    try std.testing.expect(!(try terminal.feed("\x1b]1337;Capabilities\x07")).stateChanged());
    try std.testing.expectEqualStrings("", terminal.replyBytes());
    try std.testing.expectEqual(expected_file_transfer_capacity, terminal.consequenceCount());
    for (0..expected_file_transfer_capacity) |index| {
        const packet = terminal.consequenceHead().?.file_transfer;
        var text: [32]u8 = undefined;
        try std.testing.expectEqualStrings(try std.fmt.bufPrint(&text, "opaque-{d}", .{index}), packet.payload);
        try std.testing.expectEqual(Terminal.FileTransferProtocol.kitty_5113, packet.protocol);
        try std.testing.expectEqual(@as(u64, index + 1), packet.generation);
        try terminal.consumeConsequence(packet.generation);
    }
    try std.testing.expect(terminal.consequenceHead() == null);
}

test "iTerm2 multipart final validation and replacement leave no partial image" {
    const sample = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVQI12P4z8Dwn4Hh/38AD/kD/XjubY4AAAAASUVORK5CYII=";
    const start = "\x1b]1337;MultipartFile=inline=1\x07";
    const part = "\x1b]1337;FilePart=";
    const end = "\x1b]1337;FileEnd\x1b\\";
    var terminal = try Terminal.init(std.testing.allocator, 4, 8);
    defer terminal.deinit();
    try terminal.setCellPixelSize(3, 5);
    try feed(&terminal, "\x1b]1337;File=inline=1:" ++ sample ++ "\x07");
    const before = terminal.images(0);
    const original = before.placement(0).?;
    const original_id = before.image(0).?.id;
    const cursor_row = terminal.semanticView(0).cursor_row;
    const cursor_col = terminal.semanticView(0).cursor_col;
    for ([_][]const u8{
        "", // no parts
        "Q", // incomplete quartet
        "QR==", // nonzero unused Base64 bits
        "QQ==", // valid Base64, not PNG
        sample[0 .. sample.len - 8], // truncated PNG with complete quartets
        "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVQI12P4z8Dwn4Hh/38AD/kD/XjubY4AAAAASUVORK5CYIA=", // wrong IEND CRC
    }) |encoded| {
        try std.testing.expect(!(try terminal.feed(start)).stateChanged());
        if (encoded.len != 0) {
            var bytes: [192]u8 = undefined;
            const wire = try std.fmt.bufPrint(&bytes, "{s}{s}\x07", .{ part, encoded });
            try std.testing.expect(!(try terminal.feed(wire)).stateChanged());
        }
        try std.testing.expect(!(try terminal.feed(end)).stateChanged());
        try std.testing.expect(!(try terminal.feed(part ++ sample ++ "\x07" ++ end)).stateChanged());
        const after = terminal.images(0);
        try std.testing.expectEqual(before.generation, after.generation);
        try std.testing.expectEqual(before.content_generation, after.content_generation);
        try std.testing.expectEqual(@as(usize, 1), after.imageCount());
        try std.testing.expectEqual(original_id, after.image(0).?.id);
        try std.testing.expectEqualDeep(original, after.placement(0).?);
        try std.testing.expectEqual(cursor_row, terminal.semanticView(0).cursor_row);
        try std.testing.expectEqual(cursor_col, terminal.semanticView(0).cursor_col);
        try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
        try std.testing.expectEqualStrings("", terminal.replyBytes());
    }
    // A new start replaces the old bytes, rather than appending to them.
    try std.testing.expect(!(try terminal.feed(start ++ part ++ "AAAA\x07" ++
        "\x1b]1337;MultipartFile=inline=1;width=50%;height=5px\x07" ++
        part ++ sample ++ "\x07")).stateChanged());
    try terminal.resize(4, 12);
    // Resolve the percentage against the new geometry at completion.
    try std.testing.expect((try terminal.feed(end)).mutations.images);
    const after = terminal.images(0);
    try std.testing.expectEqual(@as(usize, 2), after.imageCount());
    const fitted = after.placement(1).?;
    try std.testing.expectEqual(@as(u32, 10), fitted.pixel_width);
    try std.testing.expectEqual(@as(u32, 5), fitted.pixel_height);
    try std.testing.expectEqualDeep(original, after.placement(0).?);
    // A completed single image also supersedes any staged multipart.
    try std.testing.expect(!(try terminal.feed(start ++ part ++ sample ++ "\x07")).stateChanged());
    try std.testing.expect((try terminal.feed("\x1b]1337;File=inline=1:" ++ sample ++ "\x07")).mutations.images);
    try std.testing.expect(!(try terminal.feed(end)).stateChanged());
    try std.testing.expectEqual(@as(usize, 3), terminal.images(0).imageCount());
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
}

test "iTerm2 single and multipart admission respect full canonical image quota and recover after RIS" {
    const sample = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVQI12P4z8Dwn4Hh/38AD/kD/XjubY4AAAAASUVORK5CYII=";
    const single = "\x1b]1337;File=inline=1:" ++ sample ++ "\x07";
    const multipart = "\x1b]1337;MultipartFile=inline=1\x07\x1b]1337;FilePart=" ++ sample ++ "\x07\x1b]1337;FileEnd\x07";
    var terminal = try Terminal.init(std.testing.allocator, 4, 8);
    defer terminal.deinit();
    try terminal.setCellPixelSize(3, 5);
    for (0..Terminal.maximum_images) |_| {
        try feed(&terminal, "\x1b[H");
        try std.testing.expect((try terminal.feed(single)).mutations.images);
    }
    try feed(&terminal, "\x1b[H");
    const before = terminal.images(0);
    try std.testing.expectEqual(Terminal.maximum_images, before.imageCount());
    try std.testing.expectEqual(Terminal.maximum_images, before.placementCount());
    const first = before.placement(0).?;
    const last = before.placement(Terminal.maximum_images - 1).?;
    for ([_][]const u8{ single, multipart }) |packet| {
        try std.testing.expect(!(try terminal.feed(packet)).stateChanged());
        const after = terminal.images(0);
        try std.testing.expectEqual(before.generation, after.generation);
        try std.testing.expectEqual(before.content_generation, after.content_generation);
        try std.testing.expectEqual(Terminal.maximum_images, after.imageCount());
        try std.testing.expectEqual(Terminal.maximum_images, after.placementCount());
        try std.testing.expectEqualDeep(first, after.placement(0).?);
        try std.testing.expectEqualDeep(last, after.placement(Terminal.maximum_images - 1).?);
        try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_row);
        try std.testing.expectEqual(@as(u16, 0), terminal.semanticView(0).cursor_col);
        try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
    }
    terminal.hardReset();
    try std.testing.expectEqual(@as(usize, 0), terminal.images(0).imageCount());
    try std.testing.expect((try terminal.feed(multipart)).mutations.images);
    try std.testing.expectEqual(@as(usize, 1), terminal.images(0).imageCount());
    try std.testing.expect(terminal.images(0).image(0).?.id > last.image_id);
}

test "decoded inline image erase and refill cycles exceed the canonical slot quota without reset" {
    const sample = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVQI12P4z8Dwn4Hh/38AD/kD/XjubY4AAAAASUVORK5CYII=";
    const packets = [_][]const u8{
        "\x1b]1337;File=inline=1:" ++ sample ++ "\x07",
        "\x1b]1337;MultipartFile=inline=1\x07\x1b]1337;FilePart=" ++ sample ++ "\x07\x1b]1337;FileEnd\x07",
        "\x1bPq\"1;1;1;6#1;2;100;0;0~\x1b\\",
    };
    var terminal = try Terminal.init(std.testing.allocator, 4, 8);
    defer terminal.deinit();
    try terminal.setCellPixelSize(1, 6);
    var prior_id: u32 = 0;
    for (packets) |packet| {
        for (0..Terminal.maximum_images + 1) |_| {
            try feed(&terminal, "\x1b[H");
            try std.testing.expect((try terminal.feed(packet)).mutations.images);
            const admitted = terminal.images(0);
            const placement = admitted.placement(0) orelse return error.TestUnexpectedResult;
            try std.testing.expect(placement.image_id > prior_id);
            prior_id = placement.image_id;
            try std.testing.expectEqual(@as(usize, 1), admitted.placementCount());
            try std.testing.expect((try terminal.feed("\x1b[2J")).mutations.images);
            try std.testing.expectEqual(@as(usize, 0), terminal.images(0).placementCount());
        }
    }
    try std.testing.expectEqual(@as(usize, 0), terminal.images(0).imageCount());
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
}

test "decoded historical images remain owned until their entire retained extent expires" {
    const packets = [_][]const u8{
        "\x1b]1337;File=inline=1;width=1px;height=3;preserveAspectRatio=0:iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVQI12P4z8Dwn4Hh/38AD/kD/XjubY4AAAAASUVORK5CYII=\x07",
        "\x1bPq\"1;1;1;6#1;2;100;0;0~\x1b\\",
    };
    for (packets, 0..) |packet, index| {
        var terminal = try Terminal.initWithHistory(std.testing.allocator, 4, 8, 8);
        defer terminal.deinit();
        try terminal.setCellPixelSize(1, if (index == 0) 1 else 2);
        try feed(&terminal, packet);
        const before = terminal.images(0);
        try std.testing.expectEqual(@as(usize, 1), before.imageCount());
        const id = before.image(0).?.id;
        try feed(&terminal, "\x1b[4;1H\r\n\r\n\r\n");
        const historical = terminal.images(3);
        try std.testing.expectEqual(@as(usize, 1), historical.imageCount());
        var it = historical.placementIterator();
        try std.testing.expectEqual(id, (it.next() orelse return error.TestUnexpectedResult).placement.image_id);
        try std.testing.expect(it.next() == null);
        try feed(&terminal, "\x1b[2J");
        try std.testing.expectEqual(@as(usize, 1), terminal.images(0).imageCount());
        try std.testing.expectEqual(before.content_generation, terminal.images(0).content_generation);
        try std.testing.expect((try terminal.feed("\x1b[3J")).mutations.images);
        try std.testing.expectEqual(@as(usize, 0), terminal.images(0).imageCount());
        try std.testing.expectEqual(@as(usize, 0), terminal.images(0).placementCount());
        try std.testing.expect(terminal.images(0).content_generation > before.content_generation);
        try feed(&terminal, "\x1b[H");
        try std.testing.expect((try terminal.feed(packet)).mutations.images);
        try std.testing.expect(terminal.images(0).image(0).?.id > id);
    }
}

test "Kitty clipboard transport never normalizes malformed request bytes into valid data" {
    for ([_][]const u8{
        "type=read;dGV4\x01dC9wbGFpbg==",
        "type=read;dGV4\x1bXdC9wbGFpbg==",
        "type=write:name=QQ\x02==",
        "type=wdata:mime=dGV4dC9wbGFpbg==;Q\x00Q==",
    }) |payload| for ([_][]const u8{ "\x07", "\x1b\\" }) |term| {
        var terminal = try Terminal.init(std.testing.allocator, 3, 8);
        defer terminal.deinit();
        var bytes: [128]u8 = undefined;
        const wire = try std.fmt.bufPrint(&bytes, "\x1b]5522;{s}{s}", .{ payload, term });
        for (wire[0 .. wire.len - 1]) |byte|
            try std.testing.expect(!(try terminal.feed(&.{byte})).stateChanged());
        try std.testing.expect((try terminal.feed(wire[wire.len - 1 ..])).stateChanged());
        const request = terminal.consequenceHead().?.clipboard;
        try std.testing.expect(request.kind == .packet);
        try std.testing.expectEqualStrings(payload, request.payload);
        try terminal.consumeConsequence(request.generation);
        try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
        try std.testing.expectEqualStrings("", terminal.replyBytes());
    };
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    try std.testing.expect(!(try terminal.feed("\x1b]55\x0122;type=write\x07")).stateChanged());
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
    try std.testing.expect((try terminal.feed("\x1b]5522;type=write\x07")).stateChanged());
    try std.testing.expectEqualStrings("type=write", terminal.consequenceHead().?.clipboard.payload);
}

test "Kitty clipboard refusal preserves exact FIFO head and replies under pressure" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    try feed(&terminal, "\x1b]52;c;QQ==\x07\x1b]5522;type=read:id=a+b;Lg==\x1b\\");
    const first = terminal.consequenceHead().?.clipboard;
    try std.testing.expect(terminal.hasPendingKittyClipboard());
    try std.testing.expectError(error.StaleClipboardRequest, terminal.declineKittyClipboard(first.generation));
    try std.testing.expectError(error.StaleClipboardRequest, terminal.declineKittyClipboard(first.generation + 1));
    try terminal.consumeConsequence(first.generation);
    const request = terminal.consequenceHead().?.clipboard;
    const filled = try reply_fill.fill(&terminal, std.testing.allocator, expected_reply_bytes, false);
    defer std.testing.allocator.free(filled);
    const sequence = terminal.semanticSequence();
    try std.testing.expectError(error.ReplyLimit, terminal.declineKittyClipboard(request.generation));
    try std.testing.expectEqual(sequence, terminal.semanticSequence());
    try std.testing.expectEqualStrings(filled, terminal.replyBytes());
    try std.testing.expectEqual(request.generation, terminal.consequenceHead().?.clipboard.generation);
    try std.testing.expectEqualStrings("type=read:id=a+b;Lg==", terminal.consequenceHead().?.clipboard.payload);
    try consumeReplies(&terminal);
    try feed(&terminal, "\x1b G");
    try terminal.declineKittyClipboard(request.generation);
    // Kitty protocol response framing remains seven-bit.
    try std.testing.expectEqualStrings("\x1b]5522;type=read:status=EPERM:id=a+b\x1b\\", terminal.replyBytes());
    try std.testing.expect(!terminal.hasPendingKittyClipboard());
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
    try std.testing.expectError(error.StaleClipboardRequest, terminal.declineKittyClipboard(request.generation));
}

test "Kitty clipboard refusal allocation failure does not consume a request" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var terminal = try Terminal.init(failing.allocator(), 3, 8);
    defer terminal.deinit();
    try feed(&terminal, "\x1b]5522;type=write:id=keep\x07");
    const request = terminal.consequenceHead().?.clipboard;
    const sequence = terminal.semanticSequence();
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, terminal.declineKittyClipboard(request.generation));
    try std.testing.expectEqual(sequence, terminal.semanticSequence());
    try std.testing.expectEqualStrings("", terminal.replyBytes());
    try std.testing.expectEqual(request.generation, terminal.consequenceHead().?.clipboard.generation);
    failing.fail_index = std.math.maxInt(usize);
    try terminal.declineKittyClipboard(request.generation);
    try std.testing.expectEqualStrings("\x1b]5522;type=write:status=EPERM:id=keep\x1b\\", terminal.replyBytes());
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
}

test "Kitty caller-owned read stream filters MIME order and crosses the bounded reply queue" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    try feed(&terminal, "\x1b G\x1b]5522;type=read:loc=primary:id=a/b+;dGV4dC9wbGFpbiBtaXNzaW5nIGltYWdlL3BuZw==\x07");
    const request = terminal.consequenceHead().?.clipboard;
    var scratch: Terminal.KittyReadScratch = undefined;
    const read = (try terminal.inspectKittyClipboardRead(request.generation, &scratch)) orelse return error.TestUnexpectedResult;
    try std.testing.expect(read.location == .primary);
    try std.testing.expectEqualStrings("text/plain missing image/png", read.mime_types);
    try std.testing.expectError(error.InvalidClipboardResponse, terminal.replyKittyClipboardRead(request.generation, .{ .begin = .clipboard }));
    try terminal.replyKittyClipboardRead(request.generation, .{ .begin = .primary });
    try std.testing.expect(terminal.consequenceHead().?.requiresReply());
    try std.testing.expectError(error.ReplyRequired, terminal.consumeConsequence(request.generation));
    try std.testing.expectError(error.InvalidClipboardResponse, terminal.declineKittyClipboard(request.generation));
    try std.testing.expectError(error.InvalidClipboardResponse, terminal.replyKittyClipboardRead(request.generation, .busy));
    try std.testing.expectError(error.InvalidClipboardResponse, terminal.replyKittyClipboardRead(request.generation, .{ .begin = .primary }));
    try std.testing.expectEqualStrings("\x1b]5522;type=read:status=OK:loc=primary:id=ab+\x1b\\", terminal.replyBytes());
    // Stream more than the entire 64KiB reply queue with binary data,
    // including exact retry of the rejected chunk. Only caller owns data.
    const count = 17 * 4096 + 3;
    const bytes = try allocator.alloc(u8, count);
    defer allocator.free(bytes);
    for (bytes, 0..) |*byte, i| byte.* = @truncate(i);
    var decoded = std.ArrayList(u8).empty;
    defer decoded.deinit(allocator);
    var offset: usize = 0;
    var pressure = false;
    while (offset < bytes.len) {
        const n = @min(@as(usize, 4096), bytes.len - offset);
        const sequence = terminal.semanticSequence();
        const action: Terminal.KittyReadReply = .{ .data = .{ .mime = "text/plain", .bytes = bytes[offset..][0..n], .last = offset + n == bytes.len } };
        terminal.replyKittyClipboardRead(request.generation, action) catch |failure| {
            if (failure != error.ReplyLimit) return failure;
            pressure = true;
            try std.testing.expectEqual(sequence, terminal.semanticSequence());
            try std.testing.expectEqual(request.generation, terminal.consequenceHead().?.id());
            try appendReadPayloads(allocator, &decoded, terminal.replyBytes(), "dGV4dC9wbGFpbg==");
            try consumeReplies(&terminal);
            continue;
        };
        offset += n;
        if (offset < bytes.len) {
            try std.testing.expectError(error.InvalidClipboardResponse, terminal.replyKittyClipboardRead(request.generation, .done));
            try std.testing.expectError(error.InvalidClipboardResponse, terminal.replyKittyClipboardRead(request.generation, .{ .data = .{ .mime = "image/png", .bytes = "premature", .last = true } }));
        }
    }
    try std.testing.expect(pressure);
    try appendReadPayloads(allocator, &decoded, terminal.replyBytes(), "dGV4dC9wbGFpbg==");
    try std.testing.expectEqualSlices(u8, bytes, decoded.items);
    try consumeReplies(&terminal);
    try std.testing.expectError(error.InvalidClipboardResponse, terminal.replyKittyClipboardRead(request.generation, .{ .data = .{ .mime = "text/plain", .bytes = "replayed", .last = true } }));
    try std.testing.expectError(error.InvalidClipboardResponse, terminal.replyKittyClipboardRead(request.generation, .{ .data = .{ .mime = "unrequested/type", .bytes = "secret", .last = true } }));
    try terminal.replyKittyClipboardRead(request.generation, .{ .data = .{ .mime = "image/png", .bytes = &.{ 0, 255, 1 }, .last = true } });
    try terminal.replyKittyClipboardRead(request.generation, .done);
    try std.testing.expectEqualStrings("\x1b]5522;type=read:status=DATA:id=ab+:mime=aW1hZ2UvcG5n;AP8B\x1b\\\x1b]5522;type=read:status=DONE:id=ab+\x1b\\", terminal.replyBytes());
    try std.testing.expect(!terminal.hasPendingKittyClipboard());
    try std.testing.expectError(error.StaleClipboardRequest, terminal.replyKittyClipboardRead(request.generation, .done));
}

fn appendReadPayloads(allocator: std.mem.Allocator, decoded: *std.ArrayList(u8), wire: []const u8, encoded_mime: []const u8) !void {
    var packets = std.mem.splitSequence(u8, wire, "\x1b\\");
    while (packets.next()) |packet| {
        if (packet.len == 0 or std.mem.startsWith(u8, packet, "\x1b]5522;type=read:status=OK")) continue;
        var prefix: [128]u8 = undefined;
        const header = try std.fmt.bufPrint(&prefix, "\x1b]5522;type=read:status=DATA:id=ab+:mime={s};", .{encoded_mime});
        try std.testing.expect(std.mem.startsWith(u8, packet, header));
        const encoded = packet[header.len..];
        const decoder = std.base64.standard.Decoder;
        const size = try decoder.calcSizeForSlice(encoded);
        try std.testing.expect(size <= 4096);
        var scratch: [4096]u8 = undefined;
        try decoder.decode(scratch[0..size], encoded);
        try decoded.appendSlice(allocator, scratch[0..size]);
    }
}

test "Kitty read listing uses typed MIME names and permits only opening failure statuses" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    for ([_]Terminal.KittyReadReply{ .unavailable, .denied, .busy }, [_][]const u8{ "ENOSYS", "EPERM", "EBUSY" }) |action, status| {
        try feed(&terminal, "\x1b]5522;type=read:id=q;Lg==\x07");
        const id = terminal.consequenceHead().?.id();
        try terminal.replyKittyClipboardRead(id, action);
        var expected: [96]u8 = undefined;
        try std.testing.expectEqualStrings(try std.fmt.bufPrint(&expected, "\x1b]5522;type=read:status={s}:id=q\x1b\\", .{status}), terminal.replyBytes());
        try consumeReplies(&terminal);
    }
    try feed(&terminal, "\x1b]5522;type=read:id=q;Lg==\x07");
    const id = terminal.consequenceHead().?.id();
    try terminal.replyKittyClipboardRead(id, .{ .begin = .clipboard });
    try std.testing.expectError(error.InvalidClipboardResponse, terminal.replyKittyClipboardRead(id, .{ .data = .{ .mime = ".", .bytes = "not a listing", .last = true } }));
    try std.testing.expectError(error.InvalidClipboardResponse, terminal.replyKittyClipboardRead(id, .{ .list = .{ .names = &.{"not a MIME token"}, .last = true } }));
    try terminal.replyKittyClipboardRead(id, .{ .list = .{ .names = &.{"text/plain"}, .last = false } });
    try terminal.replyKittyClipboardRead(id, .{ .list = .{ .names = &.{"image/png"}, .last = true } });
    try terminal.replyKittyClipboardRead(id, .done);
    try std.testing.expectEqualStrings("\x1b]5522;type=read:status=OK:id=q\x1b\\\x1b]5522;type=read:status=DATA:id=q:mime=Lg==;dGV4dC9wbGFpbgo=\x1b\\\x1b]5522;type=read:status=DATA:id=q:mime=Lg==;aW1hZ2UvcG5nCg==\x1b\\\x1b]5522;type=read:status=DONE:id=q\x1b\\", terminal.replyBytes());
}

test "Kitty read validation rejects malformed requests and wrong FIFO heads without replies" {
    for ([_][]const u8{
        "type=read;!!!!",
        "type=read;QR==",
        "type=read;AA==",
        "type=read;IA==",
        "type=read;/w==",
        "type=read:loc=invalid;Lg==",
        "type=read:name=!!!!;Lg==",
        "type=read:pw=!!!!;Lg==",
        "type=read:type=write;Lg==",
        "type=write",
        "type=wdata",
    }) |payload| {
        var terminal = try Terminal.init(std.testing.allocator, 3, 8);
        defer terminal.deinit();
        var packet: [128]u8 = undefined;
        try feed(&terminal, try std.fmt.bufPrint(&packet, "\x1b]5522;{s}\x07", .{payload}));
        const id = terminal.consequenceHead().?.id();
        var scratch: Terminal.KittyReadScratch = undefined;
        const before = terminal.semanticSequence();
        try std.testing.expect((try terminal.inspectKittyClipboardRead(id, &scratch)) == null);
        try std.testing.expectError(error.StaleClipboardRequest, terminal.inspectKittyClipboardRead(id + 1, &scratch));
        try std.testing.expectError(error.InvalidClipboardResponse, terminal.replyKittyClipboardRead(id, .{ .begin = .clipboard }));
        try std.testing.expectError(error.InvalidClipboardResponse, terminal.replyKittyClipboardRead(id, .denied));
        try std.testing.expectEqual(before, terminal.semanticSequence());
        try std.testing.expectEqualStrings("", terminal.replyBytes());
        try std.testing.expectEqual(id, terminal.consequenceHead().?.id());
        try terminal.consumeConsequence(id);
    }
}

test "Kitty read begin and data allocation failure preserve exact response state" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var terminal = try Terminal.init(failing.allocator(), 3, 8);
    defer terminal.deinit();
    try feed(&terminal, "\x1b]5522;type=read:id=q;dGV4dC9wbGFpbg==\x07");
    const id = terminal.consequenceHead().?.id();
    const begin: Terminal.KittyReadReply = .{ .begin = .clipboard };
    const initial = terminal.semanticSequence();
    failing.fail_index = failing.alloc_index;
    failing.resize_fail_index = failing.resize_index;
    try std.testing.expectError(error.OutOfMemory, terminal.replyKittyClipboardRead(id, begin));
    try std.testing.expectEqual(initial, terminal.semanticSequence());
    try std.testing.expect(!terminal.consequenceHead().?.requiresReply());
    try std.testing.expectEqualStrings("", terminal.replyBytes());
    failing.fail_index = std.math.maxInt(usize);
    failing.resize_fail_index = std.math.maxInt(usize);
    try terminal.replyKittyClipboardRead(id, begin);
    const accepted = terminal.semanticSequence();
    const large: [4096]u8 = @splat(0x9c);
    const data: Terminal.KittyReadReply = .{ .data = .{ .mime = "text/plain", .bytes = &large, .last = true } };
    failing.fail_index = failing.alloc_index;
    failing.resize_fail_index = failing.resize_index;
    try std.testing.expectError(error.OutOfMemory, terminal.replyKittyClipboardRead(id, data));
    try std.testing.expectEqual(accepted, terminal.semanticSequence());
    try std.testing.expect(terminal.consequenceHead().?.requiresReply());
    try std.testing.expectEqualStrings("\x1b]5522;type=read:status=OK:id=q\x1b\\", terminal.replyBytes());
    failing.fail_index = std.math.maxInt(usize);
    failing.resize_fail_index = std.math.maxInt(usize);
    try terminal.replyKittyClipboardRead(id, data);
    try terminal.replyKittyClipboardRead(id, .done);
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
}

test "Kitty read bounds and completion pressure retain the started request until retry" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    const ok = "\x1b]5522;type=read:status=OK:id=q\x1b\\";
    const data = "\x1b]5522;type=read:status=DATA:id=q:mime=dGV4dC9wbGFpbg==;QQ==\x1b\\";
    const done = "\x1b]5522;type=read:status=DONE:id=q\x1b\\";
    const fill = try reply_fill.fill(&terminal, std.testing.allocator, expected_reply_bytes - ok.len - data.len - done.len + 1, false);
    defer std.testing.allocator.free(fill);
    try feed(&terminal, "\x1b]5522;type=read:id=q;dGV4dC9wbGFpbg==\x07");
    const id = terminal.consequenceHead().?.id();
    try std.testing.expectError(error.InvalidClipboardResponse, terminal.replyKittyClipboardRead(id, .done));
    try terminal.replyKittyClipboardRead(id, .{ .begin = .clipboard });
    const too_large: [4097]u8 = @splat(1);
    try std.testing.expectError(error.InvalidClipboardResponse, terminal.replyKittyClipboardRead(id, .{ .data = .{ .mime = "text/plain", .bytes = &too_large, .last = true } }));
    try std.testing.expectError(error.InvalidClipboardResponse, terminal.replyKittyClipboardRead(id, .{ .data = .{ .mime = "text/plain", .bytes = "", .last = false } }));
    try terminal.replyKittyClipboardRead(id, .{ .data = .{ .mime = "text/plain", .bytes = "A", .last = true } });
    const before = terminal.semanticSequence();
    try std.testing.expectError(error.ReplyLimit, terminal.replyKittyClipboardRead(id, .done));
    try std.testing.expectEqual(before, terminal.semanticSequence());
    try std.testing.expectEqual(id, terminal.consequenceHead().?.id());
    try std.testing.expect(terminal.consequenceHead().?.requiresReply());
    try std.testing.expectEqualStrings(fill, terminal.replyBytes()[0..fill.len]);
    try std.testing.expectEqualStrings(ok ++ data, terminal.replyBytes()[fill.len..]);
    try consumeReplies(&terminal);
    try terminal.replyKittyClipboardRead(id, .done);
    try std.testing.expectEqualStrings(done, terminal.replyBytes());
    try std.testing.expectEqual(@as(u16, 0), terminal.consequenceCount());
}

test "Kitty read inventory bounds and RIS revoke only the started transfer" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    try feed(&terminal, "\x1b]5522;type=read:id=q;Lg==\x07\x1b]5522;type=read:id=next;Lg==\x07");
    const id = terminal.consequenceHead().?.id();
    try terminal.replyKittyClipboardRead(id, .{ .begin = .clipboard });
    const name: [4095]u8 = @splat('x');
    const oversized: [4096]u8 = @splat('x');
    try std.testing.expectError(error.InvalidClipboardResponse, terminal.replyKittyClipboardRead(id, .done));
    try std.testing.expectError(error.InvalidClipboardResponse, terminal.replyKittyClipboardRead(id, .{ .list = .{ .names = &.{&oversized}, .last = true } }));
    try std.testing.expectError(error.InvalidClipboardResponse, terminal.replyKittyClipboardRead(id, .{ .list = .{ .names = &.{ &name, "y" }, .last = true } }));
    try terminal.replyKittyClipboardRead(id, .{ .list = .{ .names = &.{&name}, .last = false } });
    const before = try std.testing.allocator.dupe(u8, terminal.replyBytes());
    defer std.testing.allocator.free(before);
    terminal.hardReset();
    try std.testing.expectEqualStrings(before, terminal.replyBytes());
    try std.testing.expectError(error.StaleClipboardRequest, terminal.replyKittyClipboardRead(id, .{ .list = .{ .names = &.{"secret"}, .last = true } }));
    try std.testing.expectEqual(id + 1, terminal.consequenceHead().?.id());
    try std.testing.expect(!terminal.consequenceHead().?.requiresReply());
    try consumeReplies(&terminal);
    try terminal.replyKittyClipboardRead(id + 1, .{ .begin = .clipboard });
    try terminal.replyKittyClipboardRead(id + 1, .{ .list = .{ .names = &.{}, .last = true } });
    try terminal.replyKittyClipboardRead(id + 1, .done);
    try std.testing.expectEqualStrings("\x1b]5522;type=read:status=OK:id=next\x1b\\\x1b]5522;type=read:status=DATA:id=next:mime=Lg==\x1b\\\x1b]5522;type=read:status=DONE:id=next\x1b\\", terminal.replyBytes());
}
