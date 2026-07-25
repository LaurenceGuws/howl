const std = @import("std");
const terminal_mod = @import("../../src/terminal.zig");
const parser_mod = @import("../../src/parser.zig");
const reply_fill = @import("../support/reply_fill.zig");
const stream_harness = @import("../support/stream_harness.zig");

const Terminal = terminal_mod.Terminal;
const Rgb = Terminal.Rgb;
const StreamHarness = stream_harness.Harness;

const expected_metadata_bytes: usize = 1024;
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
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]0;My Title\x07");
    try std.testing.expectEqualStrings("My Title", terminal.title().?);
}

test "GNU Screen title retains bounded title and icon with exact mutation" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b]0;old\x07")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1bknew")).state_changed);
    const completed = try terminal.feed(" title\x1b\\");
    try std.testing.expect(completed.state_changed);
    try std.testing.expect(completed.title_changed);
    try std.testing.expect(completed.icon_changed);
    try std.testing.expectEqualStrings("new title", terminal.title().?);
    try std.testing.expectEqualStrings("new title", terminal.icon().?);

    const repeated = try terminal.feed("\x1bknew title\r");
    try std.testing.expect(!repeated.state_changed);
    try std.testing.expect(!repeated.title_changed);
    try std.testing.expect(!repeated.icon_changed);
    try std.testing.expect(!(try terminal.feed("\x1bk\n")).state_changed);

    const payload = try allocator.alloc(u8, expected_metadata_bytes + 1);
    defer allocator.free(payload);
    @memset(payload, 't');
    var sequence = std.ArrayList(u8).empty;
    defer sequence.deinit(allocator);
    try sequence.appendSlice(allocator, "\x1bk");
    try sequence.appendSlice(allocator, payload[0..expected_metadata_bytes]);
    try sequence.append(allocator, '\r');
    const maximum = try terminal.feed(sequence.items);
    try std.testing.expect(maximum.state_changed and maximum.title_changed and maximum.icon_changed);
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

test "OSC 7 and iTerm CurrentDir retain bounded directory facts with exact mutation" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    const prefix = try terminal.feed("\x1b]7;file://host");
    try std.testing.expect(!prefix.state_changed);
    const uri = try terminal.feed("/work\x1b\\");
    try std.testing.expect(uri.state_changed);
    var directory = terminal.workingDirectory().?;
    try std.testing.expect(directory.kind == .uri);
    try std.testing.expectEqualStrings("file://host/work", directory.value);

    const repeated_uri = try terminal.feed("\x1b]7;file://host/work\x07");
    try std.testing.expect(!repeated_uri.state_changed);
    const path = try terminal.feed("\x1b]1337;CurrentDir=file://host/work\x07");
    try std.testing.expect(path.state_changed);
    directory = terminal.workingDirectory().?;
    try std.testing.expect(directory.kind == .path);
    try std.testing.expectEqualStrings("file://host/work", directory.value);
    try std.testing.expect(!(try terminal.feed("\x1b]1337;CurrentDir=file://host/work\x1b\\")).state_changed);

    try std.testing.expect(!(try terminal.feed("\x1b]1337;CurrentDir\x07")).state_changed);
    directory = terminal.workingDirectory().?;
    try std.testing.expect(directory.kind == .path);
    try std.testing.expectEqualStrings("file://host/work", directory.value);

    try std.testing.expect((try terminal.feed("\x1bc")).state_changed);
    try std.testing.expect(terminal.workingDirectory() == null);
}

test "iTerm RemoteHost retains bounded metadata across terminal screen lifetime" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b]1337;RemoteHost=user@ho")).state_changed);
    try std.testing.expect((try terminal.feed("st\x1b\\")).state_changed);
    try std.testing.expectEqualStrings("user@host", terminal.remoteHost().?);
    try std.testing.expect(!(try terminal.feed("\x1b]1337;RemoteHost=user@host\x07")).state_changed);

    try std.testing.expect((try terminal.feed("\x1b[?1049h")).state_changed);
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
    try std.testing.expect((try terminal.feed(sequence.items)).state_changed);
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

    try std.testing.expect((try terminal.feed("aaaa\r\nbbbb\r\ncccc")).state_changed);
    try std.testing.expect(terminal.semanticView(0).history_count > 0);
    const output_before = terminal.logicalOutputRange();

    try std.testing.expect((try terminal.feed("\x1b[?1049halt")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b]1337;ClearScrollback=ignored\x07")).state_changed);
    try std.testing.expectEqual(@as(u21, 0), terminal.semanticView(0).cellAt(0, 0));
    try std.testing.expect(!(try terminal.feed("\x1b]1337;ClearScrollback\x1b\\")).state_changed);

    try std.testing.expect((try terminal.feed("\x1b[?1049l")).state_changed);
    try std.testing.expect(terminal.semanticView(0).history_count > 0);
    try std.testing.expectEqual(output_before, terminal.logicalOutputRange());
    try std.testing.expect(!(try terminal.feed("\x1b]1337;ClearScro")).state_changed);
    try std.testing.expect((try terminal.feed("llback\x07")).state_changed);
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
    try std.testing.expect(!(try terminal.feed("\x1b]1337;ClearScrollback\x07")).state_changed);
}

test "Kitty ignored OSC selectors remain bounded exact no-ops" {
    const ignored = [_]u32{
        5,   105,  6,    106,  13,   14,   15,   16,    18,
        46,  50,   51,   60,   61,   440,  633,  666,   697,
        701, 7704, 7721, 7750, 7770, 7771, 7777, 77119, 9001,
    };
    var terminal = try Terminal.init(std.testing.allocator, 2, 4);
    defer terminal.deinit();

    for (ignored, 0..) |command, index| {
        var sequence_buf: [64]u8 = undefined;
        const terminator = if (index % 2 == 0) "\x07" else "\x1b\\";
        const sequence = try std.fmt.bufPrint(&sequence_buf, "\x1b]{d};ignored{s}", .{ command, terminator });
        const split = sequence.len / 2;
        try std.testing.expect(!(try terminal.feed(sequence[0..split])).state_changed);
        try std.testing.expect(!(try terminal.feed(sequence[split..])).state_changed);
    }
    try std.testing.expect(!(try terminal.feed("\x1b]46;canceled\x18")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b]50;restart\x07")).state_changed);
    try std.testing.expectEqual(@as(?[]const u8, null), terminal.title());
    try std.testing.expectEqual(@as(usize, 0), terminal.replyBytes().len);

    const payload = try std.testing.allocator.alloc(u8, parser_mod.max_metadata_control_bytes - 2);
    defer std.testing.allocator.free(payload);
    @memset(payload, 'x');
    var sequence = std.ArrayList(u8).empty;
    defer sequence.deinit(std.testing.allocator);
    try sequence.appendSlice(std.testing.allocator, "\x1b]46;");
    try sequence.appendSlice(std.testing.allocator, payload[0 .. parser_mod.max_metadata_control_bytes - 3]);
    try sequence.append(std.testing.allocator, 0x07);
    try std.testing.expect(!(try terminal.feed(sequence.items)).state_changed);
    sequence.clearRetainingCapacity();
    try sequence.appendSlice(std.testing.allocator, "\x1b]46;");
    try sequence.appendSlice(std.testing.allocator, payload);
    try sequence.append(std.testing.allocator, 0x07);
    try std.testing.expectError(error.StringControlLimit, terminal.feed(sequence.items));
    try std.testing.expectEqual(@as(usize, 0), terminal.replyBytes().len);
}

test "working-directory report limit preserves the prior complete fact" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("\x1b]7;file://host/stable\x07")).state_changed);

    const payload = try allocator.alloc(u8, expected_metadata_bytes + 1);
    defer allocator.free(payload);
    @memset(payload, 'x');
    var sequence = std.ArrayList(u8).empty;
    defer sequence.deinit(allocator);
    try sequence.appendSlice(allocator, "\x1b]7;");
    try sequence.appendSlice(allocator, payload[0..expected_metadata_bytes]);
    try sequence.append(allocator, 0x07);
    try std.testing.expect((try terminal.feed(sequence.items)).state_changed);
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
    try std.testing.expect(both.state_changed);
    try std.testing.expect(both.title_changed);
    try std.testing.expect(both.icon_changed);
    try std.testing.expectEqualStrings("Both", terminal.title().?);
    try std.testing.expectEqualStrings("Both", terminal.icon().?);

    const title = try terminal.feed("\x1b]2;Title\x07");
    try std.testing.expect(title.state_changed);
    try std.testing.expect(title.title_changed);
    try std.testing.expect(!title.icon_changed);

    const icon = try terminal.feed("\x1b]1;Icon\x07");
    try std.testing.expect(icon.state_changed);
    try std.testing.expect(!icon.title_changed);
    try std.testing.expect(icon.icon_changed);

    try std.testing.expectEqualStrings("Title", terminal.title().?);
    try std.testing.expectEqualStrings("Icon", terminal.icon().?);
}

test "OSC metadata reports only committed replacement and survives split cancellation" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();

    const first = try terminal.feed("\x1b]0;stable\x07");
    try std.testing.expect(first.state_changed and first.title_changed and first.icon_changed);
    const repeated = try terminal.feed("\x1b]0;stable\x1b\\");
    try std.testing.expect(!repeated.state_changed);
    try std.testing.expect(!repeated.title_changed and !repeated.icon_changed);

    try std.testing.expect(!(try terminal.feed("\x1b]2;split")).state_changed);
    try std.testing.expect(!(try terminal.feed("-title")).state_changed);
    const completed = try terminal.feed("\x1b\\");
    try std.testing.expect(completed.state_changed and completed.title_changed and !completed.icon_changed);
    try std.testing.expectEqualStrings("split-title", terminal.title().?);

    try std.testing.expect(!(try terminal.feed("\x1b]1;discarded\x18")).state_changed);
    try std.testing.expectEqualStrings("stable", terminal.icon().?);
    const cleared = try terminal.feed("\x1b]1;\x07");
    try std.testing.expect(cleared.state_changed and cleared.icon_changed);
    try std.testing.expectEqualStrings("", terminal.icon().?);
}

test "raw OSC title updates terminal title through OSC owner path" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]Raw Title\x07");
    try std.testing.expectEqualStrings("Raw Title", terminal.title().?);
}

test "OSC title limit fails without dropping current title" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]0;ok\x07");

    const title_len = expected_metadata_bytes + 1;
    const payload = try allocator.alloc(u8, title_len);
    defer allocator.free(payload);
    @memset(payload, 'a');

    var seq = std.ArrayList(u8).empty;
    defer seq.deinit(allocator);
    try seq.appendSlice(allocator, "\x1b]0;");
    try seq.appendSlice(allocator, payload);
    try seq.appendSlice(allocator, "\x07");

    try std.testing.expectError(error.PropertyLimit, stream.nextSlice(seq.items));
    try std.testing.expectEqualStrings("ok", terminal.title().?);
}

test "OSC icon limit preserves prior title and icon" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    const initial = try terminal.feed("\x1b]2;title\x07\x1b]1;icon\x07");
    try std.testing.expect(initial.title_changed);
    try std.testing.expect(initial.icon_changed);
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
    try std.testing.expect(seeded.state_changed);
    try std.testing.expect(seeded.title_changed);
    try std.testing.expect(seeded.icon_changed);
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
    try std.testing.expect(seeded.state_changed);
    try std.testing.expect(seeded.title_changed);
    try std.testing.expect(seeded.icon_changed);
    const summary = terminal.feed("\x1b]0;both\x07") catch |err| {
        try std.testing.expectEqualStrings("old-title", terminal.title().?);
        try std.testing.expectEqualStrings("old-icon", terminal.icon().?);
        return err;
    };
    try std.testing.expect(summary.title_changed);
    try std.testing.expect(summary.icon_changed);
    try std.testing.expectEqualStrings("both", terminal.title().?);
    try std.testing.expectEqualStrings("both", terminal.icon().?);
}

test "OSC 8 retains explicit identity separately from URI and exact active mutation" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 20);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]8;id=one;https://example.com\x07a");
    try stream.nextSlice("\x1b]8;id=two;https://example.com\x1b\\b");
    try stream.nextSlice("\x1b]8;target=_blank:id=one;https://example.com\x07c");

    const view = terminal.semanticView(0);
    const first = view.cellInfoAt(0, 0).attrs.link_id;
    const second = view.cellInfoAt(0, 1).attrs.link_id;
    const third = view.cellInfoAt(0, 2).attrs.link_id;
    try std.testing.expect(first != 0);
    try std.testing.expect(first != second);
    try std.testing.expectEqual(first, third);
    try std.testing.expectEqualStrings("https://example.com", terminal.hyperlinkUri(first).?);
    try std.testing.expectEqualStrings("https://example.com", terminal.hyperlinkUri(second).?);

    try std.testing.expect(!(try terminal.feed("\x1b]8;id=one;https://example.com\x07")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b]8;;\x07")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b]8;;\x07")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b]8;missing-separator\x07")).state_changed);
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
    )).state_changed);
    const link_id = terminal.semanticView(0).cellInfoAt(0, 0).attrs.link_id;
    try std.testing.expect(link_id != 0);

    try std.testing.expect((try terminal.feed("\x1b[?1049h\x1b[?1049l")).state_changed);
    try terminal.resize(3, 10);
    try std.testing.expectEqualStrings("name", terminal.title().?);
    try std.testing.expectEqualStrings("name", terminal.icon().?);
    try std.testing.expectEqualStrings("file://host/work", terminal.workingDirectory().?.value);
    try std.testing.expectEqualStrings("user@host", terminal.remoteHost().?);
    try std.testing.expectEqual(@as(u32, 20), terminal.shellIntegration().?.version);
    try std.testing.expectEqualStrings("bash", terminal.shellIntegration().?.shell.?);
    try std.testing.expectEqual(@as(u64, 1), terminal.shellMark().generation);
    try std.testing.expectEqual(link_id, terminal.semanticView(0).cellInfoAt(0, 0).attrs.link_id);

    try std.testing.expect((try terminal.feed("\x1bc")).state_changed);
    try std.testing.expectEqualStrings("name", terminal.title().?);
    try std.testing.expectEqualStrings("name", terminal.icon().?);
    try std.testing.expect(terminal.workingDirectory() == null);
    try std.testing.expectEqualStrings("user@host", terminal.remoteHost().?);
    try std.testing.expectEqual(@as(u32, 20), terminal.shellIntegration().?.version);
    try std.testing.expectEqual(@as(u64, 1), terminal.shellMark().generation);
    try std.testing.expectEqual(@as(u32, 0), terminal.semanticView(0).cellInfoAt(0, 0).attrs.link_id);
    try std.testing.expectEqualStrings("https://example.com", terminal.hyperlinkUri(link_id).?);
}

test "OSC 52 produces pending clipboard request" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]52;c;Zm9v\x07");
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
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]52;c;SG93bA==\x07");

    const request = terminal.consequenceHead().?.clipboard;
    const text = (try terminal.takeClipboard(request.generation, allocator)).?;
    defer allocator.free(text);
    try std.testing.expectEqualStrings("Howl", text);
    try std.testing.expect(terminal.consequenceHead() == null);
}

test "OSC 52 query is retained for exact transactional host reply" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 16);
    defer terminal.deinit();
    try std.testing.expect(!(try terminal.feed("\x1b]52;cp")).state_changed);
    try std.testing.expect((try terminal.feed(";?\x1b\\")).state_changed);
    var request = terminal.consequenceHead().?.clipboard;
    try std.testing.expectEqual(@as(?[]u8, null), try terminal.takeClipboard(
        request.generation,
        allocator,
    ));
    try std.testing.expect(request.kind == .query);
    try std.testing.expectEqualStrings("cp", request.selection);
    try std.testing.expect((try terminal.feed("\x1bc")).state_changed);
    try std.testing.expectEqualStrings("cp", terminal.consequenceHead().?.clipboard.selection);
    try std.testing.expect(try terminal.replyClipboard(request.generation, "A\x00B"));
    try std.testing.expectEqualStrings("\x1b]52;cp;QQBC\x1b\\", terminal.replyBytes());
    try std.testing.expect(terminal.consequenceHead() == null);
    try std.testing.expectError(error.StaleClipboardRequest, terminal.replyClipboard(
        request.generation,
        "unused",
    ));

    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    try std.testing.expect((try terminal.feed("\x1b G\x9d52;;?\x9c")).state_changed);
    request = terminal.consequenceHead().?.clipboard;
    try std.testing.expectEqualStrings("", request.selection);
    try std.testing.expect(try terminal.replyClipboard(request.generation, ""));
    try std.testing.expectEqualStrings("\x9d52;;\x9c", terminal.replyBytes());
    try std.testing.expect(terminal.consequenceHead() == null);
}

test "OSC 52 host copy preserves FIFO until exact consumption" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 16);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed(
        "\x1b]52;c;T25l\x07" ++
            "\x1b]52;c;?\x1b\\",
    )).state_changed);

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

    try std.testing.expect((try terminal.feed("\x1b]52;c;b2xk\x07")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b]52;x;bmV3\x07")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b]52;c;!!!!\x07")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b]52;c;?trailing\x07")).state_changed);
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
    try std.testing.expect((try terminal.feed("\x1b]52;p;?\x07")).state_changed);
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

    try std.testing.expect(!(try terminal.feed("\x1b]52;c;")).state_changed);
    try std.testing.expect((try terminal.feed(
        "T25l\x07" ++
            "\x1b]52;p;?\x1b\\" ++
            "\x9d52;c;VHdv\x9c",
    )).state_changed);
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

    try std.testing.expect((try terminal.feed("\x1b]52;c;QQ==\x07")).state_changed);
    try std.testing.expect((try terminal.feed("\x1bc\x1b[?1049h\x1b[?1049l")).state_changed);
    try terminal.resize(4, 20);
    try std.testing.expectEqual(@as(u64, 4), terminal.consequenceHead().?.clipboard.generation);
    try std.testing.expectEqual(@as(u8, 1), terminal.consequenceCount());
}

test "OSC 52 queue and aggregate bounds preserve identity and wrap" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 16);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b]52;c;QQ==\x07")).state_changed);
    try terminal.consumeConsequence(1);
    for (0..expected_clipboard_capacity) |_| {
        try std.testing.expect((try terminal.feed("\x1b]52;c;Qg==\x07")).state_changed);
    }
    try std.testing.expectEqual(expected_clipboard_capacity, terminal.consequenceCount());
    try std.testing.expectEqual(@as(u64, 2), terminal.consequenceHead().?.clipboard.generation);
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed("\x1b]52;c;Qw==\x07"));
    try std.testing.expectEqual(expected_clipboard_capacity, terminal.consequenceCount());
    try std.testing.expectEqual(@as(u64, 2), terminal.consequenceHead().?.clipboard.generation);

    for (2..10) |generation| try terminal.consumeConsequence(@intCast(generation));
    try std.testing.expect(terminal.consequenceHead() == null);
    try std.testing.expect((try terminal.feed("\x1b]52;c;RA==\x07")).state_changed);
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
    try std.testing.expect((try terminal.feed(sequence.items)).state_changed);
    try std.testing.expectEqual(@as(u64, 11), terminal.consequenceHead().?.clipboard.generation);
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed("\x1b]52;c;RQ==\x07"));
    try std.testing.expectEqual(@as(u64, 11), terminal.consequenceHead().?.clipboard.generation);
    try std.testing.expectEqual(@as(u8, 1), terminal.consequenceCount());
    try terminal.consumeConsequence(11);
}

test "Kitty OSC 5522 shares ordered clipboard admission without host policy" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 16);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b]5522;type=wr")).state_changed);
    try std.testing.expect((try terminal.feed("ite\x1b\\")).state_changed);
    try std.testing.expect((try terminal.feed(
        "\x1b]52;c;?\x07" ++
            "\x1b]5522;type=read;dGV4dC9wbGFpbg==\x07",
    )).state_changed);
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

    try std.testing.expect((try terminal.feed("\x9d5522;type=wdata:mime=dGV4dA==;QQ==\x9c")).state_changed);
    try std.testing.expect((try terminal.feed("\x1bc\x1b[?1049h\x1b[?1049l")).state_changed);
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

    try std.testing.expect((try terminal.feed("\x1b]5522;type=write\x1b\\")).state_changed);
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
    try std.testing.expect(!(try terminal.feed(sequence.items[0..split])).state_changed);
    try std.testing.expect((try terminal.feed(sequence.items[split..])).state_changed);
    for (0..expected_clipboard_capacity - 1) |_| {
        try std.testing.expect((try terminal.feed("\x1b]5522;type=wdata\x1b\\")).state_changed);
    }
    try std.testing.expectEqual(expected_clipboard_capacity, terminal.consequenceCount());
    try std.testing.expectEqual(@as(u64, 2), terminal.consequenceHead().?.clipboard.generation);
    try std.testing.expectEqual(
        @as(usize, expected_clipboard_packet_bytes),
        terminal.consequenceHead().?.clipboard.payload.len,
    );
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed("\x1b]52;c;QQ==\x07"));
    try std.testing.expectEqual(@as(u64, 2), terminal.consequenceHead().?.clipboard.generation);
    try std.testing.expectEqual(expected_clipboard_capacity, terminal.consequenceCount());

    for (0..expected_clipboard_capacity) |_| {
        const head = terminal.consequenceHead().?.clipboard;
        try terminal.consumeConsequence(head.generation);
    }
    try std.testing.expect(terminal.consequenceHead() == null);
    try std.testing.expect((try terminal.feed("\x1b]5522;type=read;Lg==\x1b\\")).state_changed);
    try std.testing.expectEqual(@as(u64, 10), terminal.consequenceHead().?.clipboard.generation);
    try terminal.consumeConsequence(10);

    sequence.clearRetainingCapacity();
    try sequence.appendSlice(allocator, "\x1b]5522;");
    try sequence.appendSlice(allocator, payload);
    try sequence.appendSlice(allocator, "\x1b\\");
    try std.testing.expectError(error.StringControlLimit, terminal.feed(sequence.items));
    try std.testing.expect(terminal.consequenceHead() == null);
}

test "iTerm and Kitty file transfers retain one opaque ordered stream" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 16);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b]1337;MultipartFi")).state_changed);
    try std.testing.expect((try terminal.feed(
        "le=name=ZmlsZQ==\x1b\\" ++
            "\x1b]5113;ac=send;id=1;d=QQ==\x1b\\" ++
            "\x1b]1337;FilePart=Qg==\x07" ++
            "\x1b]1337;FileEnd=done\x1b\\",
    )).state_changed);
    try std.testing.expectEqual(@as(u8, 4), terminal.consequenceCount());

    const expected = [_]struct { protocol: terminal_mod.FileTransferProtocol, payload: []const u8 }{
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

    try std.testing.expect((try terminal.feed("\x9d5113;ac=send;id=2\x9c")).state_changed);
    try std.testing.expect((try terminal.feed("\x1bc\x1b[?1049h\x1b[?1049l")).state_changed);
    try terminal.resize(4, 20);
    const retained = terminal.consequenceHead().?.file_transfer;
    try std.testing.expectEqual(@as(u64, 5), retained.generation);
    try std.testing.expectEqualStrings("ac=send;id=2", retained.payload);
}

test "opaque file-transfer bounds preserve FIFO identity and wrap" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 16);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b]5113;first\x1b\\")).state_changed);
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
    try std.testing.expect(!(try terminal.feed(sequence.items[0..split])).state_changed);
    try std.testing.expect((try terminal.feed(sequence.items[split..])).state_changed);
    for (0..expected_file_transfer_capacity - 1) |_| {
        try std.testing.expect((try terminal.feed("\x1b]1337;FilePart=QQ==\x1b\\")).state_changed);
    }
    try std.testing.expectEqual(expected_file_transfer_capacity, terminal.consequenceCount());
    try std.testing.expectEqual(@as(u64, 2), terminal.consequenceHead().?.file_transfer.generation);
    try std.testing.expectEqual(@as(usize, expected_file_transfer_bytes), terminal.consequenceHead().?.file_transfer.payload.len);
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed("\x1b]5113;rejected\x1b\\"));
    try std.testing.expectEqual(@as(u64, 2), terminal.consequenceHead().?.file_transfer.generation);
    try std.testing.expectEqual(expected_file_transfer_capacity, terminal.consequenceCount());

    for (0..expected_file_transfer_capacity) |_| {
        const packet = terminal.consequenceHead().?.file_transfer;
        try terminal.consumeConsequence(packet.generation);
    }
    try std.testing.expect((try terminal.feed("\x1b]5113;after\x1b\\")).state_changed);
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
    try std.testing.expect((try terminal.feed(sequence.items)).state_changed);
    try std.testing.expectEqual(@as(u64, 11), terminal.consequenceHead().?.file_transfer.generation);
    try terminal.consumeConsequence(11);
    sequence.clearRetainingCapacity();
    try sequence.appendSlice(allocator, "\x1b]1337;");
    try sequence.appendSlice(allocator, iterm_payload);
    try sequence.appendSlice(allocator, "\x1b\\");
    try std.testing.expectError(error.StringControlLimit, terminal.feed(sequence.items));
    try std.testing.expect(terminal.consequenceHead() == null);

    sequence.clearRetainingCapacity();
    try sequence.appendSlice(allocator, "\x1b]5113;");
    try sequence.appendSlice(allocator, payload);
    try sequence.appendSlice(allocator, "\x1b\\");
    try std.testing.expectError(error.StringControlLimit, terminal.feed(sequence.items));
    try std.testing.expect(terminal.consequenceHead() == null);
}

test "shell integration OSC 133 records latest mark" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]133;C;cmdline=ls\x07\x1b]133;D;2\x07");

    const mark = terminal.shellMark();
    try std.testing.expectEqual(@as(u64, 2), mark.generation);
    try std.testing.expectEqual(@as(u8, 'D'), mark.kind);
    try std.testing.expectEqual(@as(?i32, 2), mark.status);
    try std.testing.expectEqualStrings("2", mark.metadata);

    try stream.nextSlice("\x1b]133;Z;ignored\x07");
    try std.testing.expectEqual(@as(u64, 2), terminal.shellMark().generation);
}

test "OSC 133 retains exact metadata and finds positional exit status" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b]133;D;aid=nested;")).state_changed);
    try std.testing.expectEqual(@as(u64, 0), terminal.shellMark().generation);
    try std.testing.expect((try terminal.feed("7;cl=done\x1b\\")).state_changed);
    var mark = terminal.shellMark();
    try std.testing.expectEqual(@as(u64, 1), mark.generation);
    try std.testing.expectEqual(@as(u8, 'D'), mark.kind);
    try std.testing.expectEqual(@as(?i32, 7), mark.status);
    try std.testing.expectEqualStrings("aid=nested;7;cl=done", mark.metadata);

    try std.testing.expect((try terminal.feed("\x9d133;D;;-3;aid=second\x9c")).state_changed);
    mark = terminal.shellMark();
    try std.testing.expectEqual(@as(u64, 2), mark.generation);
    try std.testing.expectEqual(@as(?i32, -3), mark.status);
    try std.testing.expectEqualStrings(";-3;aid=second", mark.metadata);

    try std.testing.expect((try terminal.feed("\x1b]133;D;aid=only;broken\x07")).state_changed);
    mark = terminal.shellMark();
    try std.testing.expectEqual(@as(u64, 3), mark.generation);
    try std.testing.expectEqual(@as(?i32, null), mark.status);
    try std.testing.expectEqualStrings("aid=only;broken", mark.metadata);

    try std.testing.expect((try terminal.feed("\x1b]133;C;cmdline=exit 7\x07")).state_changed);
    mark = terminal.shellMark();
    try std.testing.expectEqual(@as(u64, 4), mark.generation);
    try std.testing.expectEqual(@as(u8, 'C'), mark.kind);
    try std.testing.expectEqual(@as(?i32, null), mark.status);
    try std.testing.expectEqualStrings("cmdline=exit 7", mark.metadata);

    try std.testing.expect((try terminal.feed("\x1bc\x1b[?1049h\x1b[?1049l")).state_changed);
    mark = terminal.shellMark();
    try std.testing.expectEqual(@as(u64, 4), mark.generation);
    try std.testing.expectEqualStrings("cmdline=exit 7", mark.metadata);
}

test "OSC notifications retain ordered bounded host-neutral occurrences" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b]9;hel")).state_changed == false);
    try std.testing.expect(terminal.consequenceHead() == null);
    try std.testing.expect((try terminal.feed("lo\x07")).state_changed);
    var notification = terminal.consequenceHead().?.notification;
    try std.testing.expectEqual(@as(u64, 1), notification.generation);
    try std.testing.expectEqual(terminal_mod.NotificationKind.message, notification.kind);
    try std.testing.expectEqual(@as(u16, 9), notification.command);
    try std.testing.expectEqualStrings("hello", notification.payload);

    try std.testing.expect((try terminal.feed(
        "\x1b]99;i=one:d=0;body\x1b\\" ++
            "\x9d777;notify;title;body\x9c" ++
            "\x1b]1337;Notification=rich body\x07" ++
            "\x1b]1337;StealFocus\x1b\\" ++
            "\x1b]1337;RequestAttention=fireworks\x07" ++
            "\x1b]9;last\x07",
    )).state_changed);
    try std.testing.expectEqual(@as(u8, 7), terminal.consequenceCount());
    try std.testing.expectError(error.StaleConsequence, terminal.consumeConsequence(2));

    const expected = [_]struct { kind: terminal_mod.NotificationKind, command: u16, payload: []const u8 }{
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

    try std.testing.expect(!(try terminal.feed("\x1b]1337;RequestAtt")).state_changed);
    try std.testing.expect((try terminal.feed("ention=once\x07")).state_changed);
    try std.testing.expect((try terminal.feed("\x1bc\x1b[?1049h\x1b[?1049l")).state_changed);
    notification = terminal.consequenceHead().?.notification;
    try std.testing.expectEqual(@as(u64, 8), notification.generation);
    try std.testing.expectEqual(terminal_mod.NotificationKind.request_attention, notification.kind);
    try std.testing.expectEqualStrings("once", notification.payload);
}

test "OSC notification bounds preserve the FIFO and wrap without reuse" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b]9;prior\x07")).state_changed);
    const payload = try allocator.alloc(u8, expected_metadata_bytes + 1);
    defer allocator.free(payload);
    @memset(payload, 'x');
    var sequence = std.ArrayList(u8).empty;
    defer sequence.deinit(allocator);
    try sequence.appendSlice(allocator, "\x1b]9;");
    try sequence.appendSlice(allocator, payload[0..expected_metadata_bytes]);
    try sequence.append(allocator, 0x07);

    try std.testing.expect((try terminal.feed(sequence.items)).state_changed);
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
        try std.testing.expect((try terminal.feed("\x1b]9;queued\x07")).state_changed);
    }
    try std.testing.expectEqual(expected_notification_capacity, terminal.consequenceCount());
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed("\x1b]9;rejected\x07"));
    try std.testing.expectEqual(@as(u64, 2), terminal.consequenceHead().?.notification.generation);
    try std.testing.expectEqual(expected_notification_capacity, terminal.consequenceCount());

    for (0..expected_notification_capacity) |_| {
        retained = terminal.consequenceHead().?.notification;
        try terminal.consumeConsequence(retained.generation);
    }
    try std.testing.expect(terminal.consequenceHead() == null);
    try std.testing.expect((try terminal.feed("\x1b]9;after\x07")).state_changed);
    retained = terminal.consequenceHead().?.notification;
    try std.testing.expectEqual(@as(u64, 10), retained.generation);
    try std.testing.expectEqualStrings("after", retained.payload);
    try terminal.consumeConsequence(10);
    try std.testing.expectError(error.StaleConsequence, terminal.consumeConsequence(10));
}

test "OSC 22 retains ordered bounded host-neutral requests" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b]22;>wait,")).state_changed);
    try std.testing.expect(terminal.consequenceHead() == null);
    try std.testing.expect((try terminal.feed("pointer\x1b\\")).state_changed);
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
    )).state_changed);
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

    try std.testing.expect((try terminal.feed("\x1b]22;survives\x07")).state_changed);
    try std.testing.expect((try terminal.feed("\x1bc\x1b[?1049h\x1b[?1049l")).state_changed);
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

    try std.testing.expect((try terminal.feed("\x1b]22;prior\x07")).state_changed);
    try sequence.appendSlice(allocator, "\x1b]22;");
    try sequence.appendSlice(allocator, payload[0..expected_metadata_bytes]);
    try sequence.append(allocator, 0x07);
    try std.testing.expect((try terminal.feed(sequence.items)).state_changed);
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
        try std.testing.expect((try terminal.feed("\x1b]22;queued\x07")).state_changed);
    }
    try std.testing.expectEqual(
        expected_pointer_shape_capacity,
        terminal.consequenceCount(),
    );
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed("\x1b]22;rejected\x07"));
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
    try std.testing.expect((try terminal.feed("\x1b]22;after\x07")).state_changed);
    retained = terminal.consequenceHead().?.pointer_shape;
    try std.testing.expectEqual(@as(u64, 10), retained.generation);
    try std.testing.expectEqualStrings("after", retained.payload);
    try terminal.consumeConsequence(10);
    try std.testing.expectError(error.StaleConsequence, terminal.consumeConsequence(10));
}

test "OSC 22 query reply is one direct transactional operation" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 4);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("\x1b]22;pointer\x1b\\")).state_changed);
    try std.testing.expectError(
        error.PointerShapeReplyMismatch,
        terminal.replyPointerShape(1, "pointer"),
    );
    try std.testing.expectEqual(@as(u64, 1), terminal.consequenceHead().?.pointer_shape.generation);
    try terminal.consumeConsequence(1);
    try std.testing.expect((try terminal.feed("\x1b]22;?__current__\x1b\\")).state_changed);
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
    try std.testing.expect(summary.state_changed);
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
    try std.testing.expect(valued_request.state_changed);
    try std.testing.expectEqualStrings(
        "\x1b]1337;ReportCellSize=18;9;1\x1b\\",
        terminal.replyBytes(),
    );

    const osc_50 = try terminal.feed("\x1b]50;CursorShape=2\x07");
    try std.testing.expect(osc_50.state_changed);
    try std.testing.expectEqual(
        Terminal.CursorShape.underline,
        terminal.semanticView(0).cursor_shape,
    );
    try std.testing.expect(!(try terminal.feed("\x1b]1337;CursorShape=2\x07")).state_changed);
    try std.testing.expect(!(try terminal.feed(
        "\x1b]1337;CursorShape=\x07\x1b]1337;CursorShape=x\x1b\\",
    )).state_changed);
    try std.testing.expectEqual(
        Terminal.CursorShape.underline,
        terminal.semanticView(0).cursor_shape,
    );
}

test "OSC 50 accepts only cursor shape without 1337 consequences" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    try terminal.setCellPixelSize(9, 18);
    const seeded = try terminal.feed(
        "\x1b]1337;SetColors=fg=112233\x07" ++
            "\x1b]1337;ShellIntegrationVersion=20;shell=bash\x07",
    );
    try std.testing.expect(seeded.state_changed);
    try terminal.consumeReplyBytes(terminal.replyBytes().len);

    const rejected = try terminal.feed(
        "\x1b]50;SetColors=fg=abcdef\x07" ++
            "\x1b]50;ShellIntegrationVersion=21;shell=zsh\x07" ++
            "\x1b]50;ReportCellSize\x07",
    );
    try std.testing.expect(!rejected.state_changed);
    try std.testing.expectEqual(
        Rgb{ .r = 0x11, .g = 0x22, .b = 0x33 },
        terminal.presentation().foreground,
    );
    try std.testing.expectEqual(@as(u32, 20), terminal.shellIntegration().?.version);
    try std.testing.expectEqualStrings("bash", terminal.shellIntegration().?.shell.?);
    try std.testing.expectEqual(@as(usize, 0), terminal.replyBytes().len);

    const accepted = try terminal.feed("\x1b]50;CursorShape=1\x07");
    try std.testing.expect(accepted.state_changed);
    try std.testing.expectEqual(
        Terminal.CursorShape.bar,
        terminal.semanticView(0).cursor_shape,
    );
}

test "cell pixel report facts reject zero and preserve configured dimensions" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    try terminal.setCellPixelSize(9, 18);
    try std.testing.expectError(error.InvalidDimensions, terminal.setCellPixelSize(0, 18));
    const cell = terminal.cellPixelSize().?;
    try std.testing.expectEqual(@as(u32, 9), cell.width);
    try std.testing.expectEqual(@as(u32, 18), cell.height);
}

test "unsupported SetMark and Kitty context metadata remain exact no-ops" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b]1337;SetMark=lab")).state_changed);
    try std.testing.expect(!(try terminal.feed("el\x1b\\")).state_changed);
    try std.testing.expectEqual(@as(u64, 0), terminal.shellMark().generation);
    try std.testing.expect(!(try terminal.feed("\x9d3008;key=value\x9c")).state_changed);

    const payload = try std.testing.allocator.alloc(u8, parser_mod.max_metadata_control_bytes);
    defer std.testing.allocator.free(payload);
    @memset(payload, 'm');
    var sequence = std.ArrayList(u8).empty;
    defer sequence.deinit(std.testing.allocator);
    try sequence.appendSlice(std.testing.allocator, "\x1b]3008;");
    try sequence.appendSlice(std.testing.allocator, payload);
    try sequence.append(std.testing.allocator, 0x07);
    try std.testing.expect(!(try terminal.feed(sequence.items)).state_changed);
    try std.testing.expectEqual(@as(u64, 0), terminal.shellMark().generation);
}

test "iTerm shell integration rejects malformed duplicate and oversized metadata" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    const accepted = try terminal.feed(
        "\x1b]1337;ShellIntegrationVersion=20;shell=bash\x07",
    );
    try std.testing.expect(accepted.state_changed);

    const rejected = [_][]const u8{
        "\x1b]1337;ShellIntegrationVersion=broken;shell=bash\x07",
        "\x1b]1337;ShellIntegrationVersion=20;shell=bash;shell=zsh\x07",
        "\x1b]1337;ShellIntegrationVersion=20;unknown=value\x07",
        "\x1b]1337;ShellIntegrationVersion=20;shell=abcdefghijklmnopqrstuvwxyz1234567\x07",
    };
    for (rejected) |sequence| {
        const summary = try terminal.feed(sequence);
        try std.testing.expect(!summary.state_changed);
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
    try std.testing.expect(set.state_changed);

    const mixed = try terminal.feed(
        "\x1b]1337;SetColors=fg=default,bg=bogus,missing," ++
            "curbg=default,curfg=default,red=default,bg=666666\x07",
    );
    try std.testing.expect(mixed.state_changed);
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
    try std.testing.expect(!malformed.state_changed);
    try std.testing.expectEqual(@as(usize, 0), terminal.replyBytes().len);

    const changed = try terminal.feed("\x1b]4;1;#010203\x07");
    try std.testing.expect(changed.state_changed);
    const repeated = try terminal.feed("\x1b]4;1;#010203\x1b\\");
    try std.testing.expect(!repeated.state_changed);

    const query = try terminal.feed("\x1b]4;1;?\x07");
    try std.testing.expect(query.state_changed);
    try std.testing.expectEqualStrings("\x1b]4;1;rgb:0101/0202/0303\x1b\\", terminal.replyBytes());

    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    const iterm_malformed = try terminal.feed("\x1b]1337;SetColors=fg=bogus,missing,p3=x\x07");
    try std.testing.expect(!iterm_malformed.state_changed);
}

test "kitty color stack OSC 30001 and 30101 restore colors" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice(
        "\x1b]21;foreground=#010203\x1b\\\x1b]30001\x1b\\" ++
            "\x1b]21;foreground=#040506\x1b\\\x1b]30101\x1b\\",
    );
    try std.testing.expectEqual(Rgb{ .r = 1, .g = 2, .b = 3 }, terminal.presentation().foreground);
}

test "kitty OSC 21 sets queries and resets terminal colors" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]21;foreground=#112233;background=rgb:44/55/66;cursor=\x1b\\");
    try stream.nextSlice("\x1b]21;foreground=?;background=?;cursor=?;no_such=?\x1b\\");

    const colors = terminal.presentation();
    try std.testing.expectEqual(Rgb{ .r = 0x11, .g = 0x22, .b = 0x33 }, colors.foreground);
    try std.testing.expectEqual(Rgb{ .r = 0x44, .g = 0x55, .b = 0x66 }, colors.background);
    try std.testing.expectEqual(@as(?Rgb, null), colors.cursor);
    try std.testing.expectEqualStrings(
        "\x1b]21;foreground=rgb:1111/2222/3333\x1b\\" ++
            "\x1b]21;background=rgb:4444/5555/6666\x1b\\" ++
            "\x1b]21;cursor=\x1b\\" ++
            "\x1b]21;no_such=?\x1b\\",
        terminal.replyBytes(),
    );

    try stream.nextSlice("\x1b]21;foreground;background\x1b\\");
    try std.testing.expectEqual(Rgb{ .r = 220, .g = 220, .b = 220 }, terminal.presentation().foreground);
    try std.testing.expectEqual(Rgb{ .r = 24, .g = 25, .b = 33 }, terminal.presentation().background);
}

test "xterm OSC colors set query and reset palette and dynamic colors" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]4;1;#010203\x1b\\\x1b]10;#aabbcc\x1b\\\x1b]11;rgb:0d/0e/0f\x1b\\\x1b]12;red\x1b\\");
    try stream.nextSlice("\x1b]4;1;?\x1b\\\x1b]10;?\x1b\\\x1b]11;?\x1b\\\x1b]12;?\x1b\\");

    try std.testing.expectEqual(Rgb{ .r = 1, .g = 2, .b = 3 }, terminal.presentation().palette[1]);
    try std.testing.expectEqualStrings(
        "\x1b]4;1;rgb:0101/0202/0303\x1b\\" ++
            "\x1b]10;rgb:aaaa/bbbb/cccc\x1b\\" ++
            "\x1b]11;rgb:0d0d/0e0e/0f0f\x1b\\" ++
            "\x1b]12;rgb:ffff/0000/0000\x1b\\",
        terminal.replyBytes(),
    );

    try stream.nextSlice("\x1b]104;1\x1b\\\x1b]110\x1b\\\x1b]111\x1b\\\x1b]112\x1b\\");
    try std.testing.expectEqual(Rgb{ .r = 205, .g = 49, .b = 49 }, terminal.presentation().palette[1]);
    try std.testing.expectEqual(Rgb{ .r = 220, .g = 220, .b = 220 }, terminal.presentation().foreground);
    try std.testing.expectEqual(Rgb{ .r = 24, .g = 25, .b = 33 }, terminal.presentation().background);
    try std.testing.expectEqual(@as(?Rgb, null), terminal.presentation().cursor);
}

test "OSC color grammar scales short components and rejects trailing components" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b]4;1;#123;2;rgb:1/22/333/4")).state_changed);
    try std.testing.expect((try terminal.feed("44;3;rgb:1/22/333\x1b\\")).state_changed);
    var colors = terminal.presentation();
    try std.testing.expectEqual(Rgb{ .r = 0x11, .g = 0x22, .b = 0x33 }, colors.palette[1]);
    try std.testing.expectEqual(Terminal.default_presentation.palette[2], colors.palette[2]);
    try std.testing.expectEqual(Rgb{ .r = 0x11, .g = 0x22, .b = 0x33 }, colors.palette[3]);

    try std.testing.expect(!(try terminal.feed("\x1b]4;1;#123;2;rgb:1/22/333/444\x07")).state_changed);
    colors = terminal.presentation();
    try std.testing.expectEqual(Rgb{ .r = 0x11, .g = 0x22, .b = 0x33 }, colors.palette[1]);
    try std.testing.expectEqual(Terminal.default_presentation.palette[2], colors.palette[2]);

    try std.testing.expect((try terminal.feed("\x1b]4;1;?\x1b\\")).state_changed);
    try std.testing.expectEqualStrings(
        "\x1b]4;1;rgb:1111/2222/3333\x1b\\",
        terminal.replyBytes(),
    );
}

test "xterm extra dynamic colors set query and reset host-neutral state" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]13;#010203\x1b\\\x1b]14;#040506\x1b\\\x1b]15;#070809\x1b\\\x1b]16;#0a0b0c\x1b\\\x1b]17;#0d0e0f\x1b\\\x1b]18;#101112\x1b\\\x1b]19;#131415\x1b\\");
    try stream.nextSlice("\x1b]13;?\x1b\\\x1b]14;?\x1b\\\x1b]15;?\x1b\\\x1b]16;?\x1b\\\x1b]17;?\x1b\\\x1b]18;?\x1b\\\x1b]19;?\x1b\\");

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
    )).state_changed);
    try std.testing.expect((try terminal.feed(
        "\x1b]13;?\x1b\\\x1b]14;?\x1b\\\x1b]15;?\x1b\\\x1b]16;?\x1b\\" ++
            "\x1b]17;?\x1b\\\x1b]18;?\x1b\\\x1b]19;?\x1b\\",
    )).state_changed);
    try std.testing.expectEqualStrings(
        "\x1b]13;\x1b\\\x1b]14;\x1b\\\x1b]15;\x1b\\\x1b]16;\x1b\\" ++
            "\x1b]17;\x1b\\\x1b]18;\x1b\\\x1b]19;\x1b\\",
        terminal.replyBytes(),
    );
}

test "xterm special colors via OSC 5 and OSC 4 special offsets" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]5;0;#010203;1;#040506\x1b\\\x1b]4;258;#070809;260;#0a0b0c\x1b\\");
    try stream.nextSlice("\x1b]5;0;?;1;?\x1b\\\x1b]4;258;?;260;?\x1b\\");

    try std.testing.expectEqualStrings(
        "\x1b]5;0;rgb:0101/0202/0303\x1b\\" ++
            "\x1b]5;1;rgb:0404/0505/0606\x1b\\" ++
            "\x1b]4;258;rgb:0707/0808/0909\x1b\\" ++
            "\x1b]4;260;rgb:0a0a/0b0b/0c0c\x1b\\",
        terminal.replyBytes(),
    );

    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    try std.testing.expect(!(try terminal.feed("\x1b]104;258;260\x1b\\")).state_changed);
}

test "OSC palette and dynamic resets own exact bounds mutation and lifetime" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed(
        "\x1b]4;0;#010203;255;#040506\x1b\\" ++
            "\x1b]10;#070809;#0a0b0c;#0d0e0f\x1b\\" ++
            "\x1b]17;#101112;;#131415\x1b\\",
    )).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b]104;256;999;bad\x07")).state_changed);

    try std.testing.expect(!(try terminal.feed("\x1b]104;0;")).state_changed);
    try std.testing.expect((try terminal.feed("255\x1b\\")).state_changed);
    var colors = terminal.presentation();
    try std.testing.expectEqual(Terminal.default_presentation.palette[0], colors.palette[0]);
    try std.testing.expectEqual(Terminal.default_presentation.palette[255], colors.palette[255]);

    try std.testing.expect((try terminal.feed(
        "\x1b]110\x07\x1b]111\x1b\\\x1b]112\x07\x1b]117\x1b\\\x1b]119\x07",
    )).state_changed);
    colors = terminal.presentation();
    try std.testing.expectEqual(Terminal.default_presentation.foreground, colors.foreground);
    try std.testing.expectEqual(Terminal.default_presentation.background, colors.background);
    try std.testing.expectEqual(@as(?Rgb, null), colors.cursor);
    try std.testing.expectEqual(@as(?Rgb, null), colors.selection_background);
    try std.testing.expectEqual(@as(?Rgb, null), colors.selection_foreground);
    try std.testing.expect(!(try terminal.feed(
        "\x1b]110\x07\x1b]111\x1b\\\x1b]112\x07\x1b]117\x1b\\\x1b]119\x07",
    )).state_changed);

    try std.testing.expect((try terminal.feed("\x1b]4;1;#212223\x1b\\\x1b]10;#313233\x1b\\")).state_changed);
    try terminal.resize(4, 12);
    try std.testing.expect((try terminal.feed("\x1b[?1049h\x1bc\x1b[?1049l")).state_changed);
    colors = terminal.presentation();
    try std.testing.expectEqual(Rgb{ .r = 33, .g = 34, .b = 35 }, colors.palette[1]);
    try std.testing.expectEqual(Rgb{ .r = 49, .g = 50, .b = 51 }, colors.foreground);

    try std.testing.expect((try terminal.feed("\x1b]104\x07")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b]104\x07")).state_changed);
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

    try std.testing.expectError(error.ReplyLimit, terminal.feed("\x1b]12;#010203;?\x1b\\"));
    try std.testing.expectEqual(fill.len, terminal.replyBytes().len);
}

test "kitty color stack restores terminal color snapshots" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]21;foreground=#010203;1=#040506\x1b\\\x1b]30001\x1b\\");
    try stream.nextSlice("\x1b]21;foreground=#aabbcc;1=#ddeeff\x1b\\\x1b]30101\x1b\\");

    try std.testing.expectEqual(Rgb{ .r = 1, .g = 2, .b = 3 }, terminal.presentation().foreground);
    try std.testing.expectEqual(Rgb{ .r = 4, .g = 5, .b = 6 }, terminal.presentation().palette[1]);
}

test "kitty tui CSI save and restore colors use the same stack" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]21;foreground=#010203;1=#040506\x1b\\\x1b[#P");
    try stream.nextSlice("\x1b]21;foreground=#aabbcc;1=#ddeeff\x1b\\\x1b[#Q");

    try std.testing.expectEqual(Rgb{ .r = 1, .g = 2, .b = 3 }, terminal.presentation().foreground);
    try std.testing.expectEqual(Rgb{ .r = 4, .g = 5, .b = 6 }, terminal.presentation().palette[1]);
}

test "kitty color stack owns indexed sequential bounded and report semantics" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b]21;foreground=#010203\x1b\\\x1b[3")).state_changed);
    try std.testing.expect((try terminal.feed("#P")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b[3#P")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b[3#Q")).state_changed);

    try std.testing.expect((try terminal.feed("\x1b]21;foreground=#111213\x1b\\\x1b[1#Q")).state_changed);
    try std.testing.expectEqual(Rgb{ .r = 220, .g = 220, .b = 220 }, terminal.presentation().foreground);
    try std.testing.expect((try terminal.feed("\x1b[3#Q")).state_changed);
    try std.testing.expectEqual(Rgb{ .r = 1, .g = 2, .b = 3 }, terminal.presentation().foreground);

    try std.testing.expect((try terminal.feed("\x1b]21;foreground=#212223\x1b\\\x1b[#P")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b]21;foreground=#313233\x1b\\\x1b[#P")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b]21;foreground=#414243\x1b\\")).state_changed);
    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    try std.testing.expect((try terminal.feed("\x1b G\x1b[#R")).state_changed);
    try std.testing.expectEqualStrings("\x1b[1;2#Q", terminal.replyBytes());

    try std.testing.expect((try terminal.feed("\x1b[3#Q\x1b[#Q")).state_changed);
    try std.testing.expectEqual(Rgb{ .r = 49, .g = 50, .b = 51 }, terminal.presentation().foreground);

    const rejected = try terminal.feed("\x1b[11#P\x1b[11#Q");
    try std.testing.expect(!rejected.state_changed);

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
    )).state_changed);

    try std.testing.expect((try terminal.feed(
        "\x1b]30101\x1b\\\x1b]30101\x1b\\\x1b]30101\x1b\\\x1b]30101\x1b\\\x1b]30101\x1b\\" ++
            "\x1b]30101\x1b\\\x1b]30101\x1b\\\x1b]30101\x1b\\\x1b]30101\x1b\\\x1b]30101\x1b\\",
    )).state_changed);
    try std.testing.expectEqual(Rgb{ .r = 0, .g = 0, .b = 2 }, terminal.presentation().foreground);

    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    try std.testing.expect((try terminal.feed("\x1bc\x1b[#R")).state_changed);
    try std.testing.expectEqualStrings("\x1b[0;0#Q", terminal.replyBytes());

    try terminal.consumeReplyBytes(terminal.replyBytes().len);
    const fill = try reply_fill.fill(&terminal, allocator, expected_reply_bytes - 1, false);
    defer allocator.free(fill);
    try std.testing.expectError(error.ReplyLimit, terminal.feed("\x1b[#R"));
    try std.testing.expectEqual(fill.len, terminal.replyBytes().len);
    try std.testing.expectEqualSlices(u8, fill, terminal.replyBytes());
}

test "OSC 72 parses fragmented ordered commands with exact rejection and consumption" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    const before = terminal.semanticSequence();

    try std.testing.expect(!(try terminal.feed("\x1b]72;t=a:i=7:m=1;text/")).state_changed);
    try std.testing.expect((try terminal.feed("uri-list\x1b\\\x1b]72;m=0;plain\x1b\\")).state_changed);
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
    try std.testing.expect((try terminal.feed("\x1b]72;t=r:x=0\x1b\\")).state_changed);
    const unsupported = terminal.consequenceHead().?.drag_drop;
    try std.testing.expectEqual(.unsupported, unsupported.kind);
    try terminal.consumeConsequence(unsupported.generation);
    const after_rejection = terminal.semanticSequence();
    try std.testing.expect(!(try terminal.feed("\x1b]72;t=m:o=9\x1b\\")).state_changed);
    try std.testing.expect(after_rejection > stable);
    try std.testing.expectEqual(after_rejection, terminal.semanticSequence());
}

test "OSC 72 queue saturation and aggregate allocation failure preserve exact head" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    for (0..expected_drag_drop_capacity) |index| {
        var bytes: [64]u8 = undefined;
        const command = try std.fmt.bufPrint(&bytes, "\x1b]72;t=q:i={d}\x1b\\", .{index});
        try std.testing.expect((try terminal.feed(command)).state_changed);
    }
    const head = terminal.consequenceHead().?.drag_drop;
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed("\x1b]72;t=q:i=99\x1b\\"));
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

    for (0..8) |_| try std.testing.expect((try terminal.feed(packet)).state_changed);
    const head = terminal.consequenceHead().?.drag_drop;
    const sequence = terminal.semanticSequence();
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed(packet));
    try std.testing.expectEqual(head.generation, terminal.consequenceHead().?.drag_drop.generation);
    try std.testing.expectEqual(@as(u8, 8), terminal.consequenceCount());
    try std.testing.expectEqual(sequence, terminal.semanticSequence());
}

test "OSC 72 host events use exact framing bounds and opaque base64" {
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
