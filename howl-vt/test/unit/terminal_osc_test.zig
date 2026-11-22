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
        "\x1b]21;foreground=rgb:11/22/33;background=rgb:44/55/66;cursor=;no_such=?\x1b\\",
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
        "\x1b]21;foreground=rgb:12/34/56;background=rgb:ab/cd/ef;cursor=;unsupported=?\x1b\\",
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
