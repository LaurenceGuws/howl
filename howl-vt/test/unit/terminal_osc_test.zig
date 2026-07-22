const std = @import("std");
const host_state = @import("../../src/terminal.zig");
const terminal_mod = @import("../../src/terminal.zig");
const parser_mod = @import("../../src/parser.zig");
const screen_mod = @import("../../src/terminal.zig");
const stream_harness = @import("../support/stream_harness.zig");

const HostState = host_state;
const Terminal = terminal_mod.Terminal;
const Screen = screen_mod.Screen;
const Grid = Screen;
const Rgb = Screen.Rgb;
const StreamHarness = stream_harness.Harness;

test "OSC title updates terminal title under stream path" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]0;My Title\x07");
    try std.testing.expectEqualStrings("My Title", terminal.host.current_title.?);
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
    try std.testing.expectEqualStrings("new title", terminal.host.current_title.?);
    try std.testing.expectEqualStrings("new title", terminal.host.current_icon.?);

    const repeated = try terminal.feed("\x1bknew title\r");
    try std.testing.expect(!repeated.state_changed);
    try std.testing.expect(!repeated.title_changed);
    try std.testing.expect(!repeated.icon_changed);
    try std.testing.expect(!(try terminal.feed("\x1bk\n")).state_changed);

    const payload = try allocator.alloc(u8, HostState.max_metadata_bytes + 1);
    defer allocator.free(payload);
    @memset(payload, 't');
    var sequence = std.ArrayList(u8).empty;
    defer sequence.deinit(allocator);
    try sequence.appendSlice(allocator, "\x1bk");
    try sequence.appendSlice(allocator, payload[0..HostState.max_metadata_bytes]);
    try sequence.append(allocator, '\r');
    const maximum = try terminal.feed(sequence.items);
    try std.testing.expect(maximum.state_changed and maximum.title_changed and maximum.icon_changed);
    try std.testing.expectEqual(@as(usize, HostState.max_metadata_bytes), terminal.host.current_title.?.len);
    try std.testing.expectEqual(@as(usize, HostState.max_metadata_bytes), terminal.host.current_icon.?.len);

    sequence.clearRetainingCapacity();
    try sequence.appendSlice(allocator, "\x1bk");
    try sequence.appendSlice(allocator, payload);
    try sequence.append(allocator, '\r');
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed(sequence.items));
    try std.testing.expectEqual(@as(usize, HostState.max_metadata_bytes), terminal.host.current_title.?.len);
    try std.testing.expectEqual(@as(usize, HostState.max_metadata_bytes), terminal.host.current_icon.?.len);
}

test "OSC 7 and iTerm CurrentDir retain bounded directory facts with exact mutation" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    const prefix = try terminal.feed("\x1b]7;file://host");
    try std.testing.expect(!prefix.state_changed);
    const uri = try terminal.feed("/work\x1b\\");
    try std.testing.expect(uri.state_changed);
    var directory = terminal.stateSnapshot().working_directory.?;
    try std.testing.expect(directory.kind == .uri);
    try std.testing.expectEqualStrings("file://host/work", directory.value);

    const repeated_uri = try terminal.feed("\x1b]7;file://host/work\x07");
    try std.testing.expect(!repeated_uri.state_changed);
    const path = try terminal.feed("\x1b]1337;CurrentDir=file://host/work\x07");
    try std.testing.expect(path.state_changed);
    directory = terminal.stateSnapshot().working_directory.?;
    try std.testing.expect(directory.kind == .path);
    try std.testing.expectEqualStrings("file://host/work", directory.value);
    try std.testing.expect(!(try terminal.feed("\x1b]1337;CurrentDir=file://host/work\x1b\\")).state_changed);

    try std.testing.expect(!(try terminal.feed("\x1b]1337;CurrentDir\x07")).state_changed);
    directory = terminal.stateSnapshot().working_directory.?;
    try std.testing.expect(directory.kind == .path);
    try std.testing.expectEqualStrings("file://host/work", directory.value);

    try std.testing.expect((try terminal.feed("\x1bc")).state_changed);
    try std.testing.expect(terminal.stateSnapshot().working_directory == null);
}

test "iTerm RemoteHost retains bounded metadata across terminal screen lifetime" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b]1337;RemoteHost=user@ho")).state_changed);
    try std.testing.expect((try terminal.feed("st\x1b\\")).state_changed);
    try std.testing.expectEqualStrings("user@host", terminal.stateSnapshot().remote_host.?);
    try std.testing.expect(!(try terminal.feed("\x1b]1337;RemoteHost=user@host\x07")).state_changed);

    try std.testing.expect((try terminal.feed("\x1b[?1049h")).state_changed);
    try terminal.resize(4, 10);
    terminal.hardReset();
    try std.testing.expectEqualStrings("user@host", terminal.stateSnapshot().remote_host.?);

    const payload = try allocator.alloc(u8, Terminal.remote_host_max_bytes + 1);
    defer allocator.free(payload);
    @memset(payload, 'h');
    var sequence = std.ArrayList(u8).empty;
    defer sequence.deinit(allocator);
    try sequence.appendSlice(allocator, "\x1b]1337;RemoteHost=");
    try sequence.appendSlice(allocator, payload[0..Terminal.remote_host_max_bytes]);
    try sequence.append(allocator, 0x07);
    try std.testing.expect((try terminal.feed(sequence.items)).state_changed);
    try std.testing.expectEqual(@as(usize, Terminal.remote_host_max_bytes), terminal.stateSnapshot().remote_host.?.len);

    sequence.clearRetainingCapacity();
    try sequence.appendSlice(allocator, "\x1b]1337;RemoteHost=");
    try sequence.appendSlice(allocator, payload);
    try sequence.append(allocator, 0x07);
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed(sequence.items));
    try std.testing.expectEqual(@as(usize, Terminal.remote_host_max_bytes), terminal.stateSnapshot().remote_host.?.len);
}

test "iTerm ClearScrollback clears only active screen state with exact repetition" {
    var terminal = try Terminal.initWithHistory(std.testing.allocator, 2, 4, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("aaaa\r\nbbbb\r\ncccc")).state_changed);
    try std.testing.expect(terminal.screen_state.primary.historyCount() > 0);
    try std.testing.expect(terminal.scrollViewport(.top));
    const output_before = terminal.logicalOutputRange();

    try std.testing.expect((try terminal.feed("\x1b[?1049halt")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b]1337;ClearScrollback=ignored\x07")).state_changed);
    try std.testing.expectEqual(@as(u21, 0), terminal.screen_state.alternate.cellAt(0, 0));
    try std.testing.expect(!(try terminal.feed("\x1b]1337;ClearScrollback\x1b\\")).state_changed);

    try std.testing.expect((try terminal.feed("\x1b[?1049l")).state_changed);
    try std.testing.expect(terminal.screen_state.primary.historyCount() > 0);
    try std.testing.expectEqual(output_before, terminal.logicalOutputRange());
    terminal.startSelection(0, 0);
    try std.testing.expect(terminal.selectionState() != null);
    try std.testing.expect(!(try terminal.feed("\x1b]1337;ClearScro")).state_changed);
    try std.testing.expect((try terminal.feed("llback\x07")).state_changed);
    try std.testing.expectEqual(@as(u32, 0), terminal.screen_state.primary.historyCount());
    try std.testing.expectEqual(output_before, terminal.logicalOutputRange());
    try std.testing.expectEqual(@as(u32, 0), terminal.scrollback_offset);
    try std.testing.expectEqual(@as(u16, 0), terminal.screen_state.primary.cursor.row);
    try std.testing.expectEqual(@as(u16, 0), terminal.screen_state.primary.cursor.col);
    try std.testing.expect(terminal.selectionState() == null);
    for (0..terminal.screen_state.primary.rows) |row| {
        for (0..terminal.screen_state.primary.cols) |col| {
            try std.testing.expectEqual(
                @as(u21, 0),
                terminal.screen_state.primary.cellAt(@intCast(row), @intCast(col)),
            );
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
    try std.testing.expectEqual(@as(?[]const u8, null), terminal.stateSnapshot().title);
    try std.testing.expectEqual(@as(usize, 0), terminal.host.pendingOutput().len);

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
    try std.testing.expectEqual(@as(usize, 0), terminal.host.pendingOutput().len);
}

test "working-directory report limit preserves the prior complete fact" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("\x1b]7;file://host/stable\x07")).state_changed);

    const payload = try allocator.alloc(u8, HostState.max_metadata_bytes + 1);
    defer allocator.free(payload);
    @memset(payload, 'x');
    var sequence = std.ArrayList(u8).empty;
    defer sequence.deinit(allocator);
    try sequence.appendSlice(allocator, "\x1b]7;");
    try sequence.appendSlice(allocator, payload[0..HostState.max_metadata_bytes]);
    try sequence.append(allocator, 0x07);
    try std.testing.expect((try terminal.feed(sequence.items)).state_changed);
    var retained = terminal.stateSnapshot().working_directory.?;
    try std.testing.expectEqual(@as(usize, HostState.max_metadata_bytes), retained.value.len);

    sequence.clearRetainingCapacity();
    try sequence.appendSlice(allocator, "\x1b]7;");
    try sequence.appendSlice(allocator, payload);
    try sequence.append(allocator, 0x07);
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed(sequence.items));

    retained = terminal.stateSnapshot().working_directory.?;
    try std.testing.expect(retained.kind == .uri);
    try std.testing.expectEqual(@as(usize, HostState.max_metadata_bytes), retained.value.len);
}

test "OSC 0 1 and 2 match libvterm title and icon properties" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();

    const both = try terminal.feed("\x1b]0;Both\x07");
    try std.testing.expect(both.state_changed);
    try std.testing.expect(both.title_changed);
    try std.testing.expect(both.icon_changed);
    var publication = terminal.stateSnapshot();
    try std.testing.expectEqualStrings("Both", publication.title.?);
    try std.testing.expectEqualStrings("Both", publication.icon.?);

    const title = try terminal.feed("\x1b]2;Title\x07");
    try std.testing.expect(title.state_changed);
    try std.testing.expect(title.title_changed);
    try std.testing.expect(!title.icon_changed);

    const icon = try terminal.feed("\x1b]1;Icon\x07");
    try std.testing.expect(icon.state_changed);
    try std.testing.expect(!icon.title_changed);
    try std.testing.expect(icon.icon_changed);

    publication = terminal.stateSnapshot();
    try std.testing.expectEqualStrings("Title", publication.title.?);
    try std.testing.expectEqualStrings("Icon", publication.icon.?);
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
    try std.testing.expectEqualStrings("split-title", terminal.stateSnapshot().title.?);

    try std.testing.expect(!(try terminal.feed("\x1b]1;discarded\x18")).state_changed);
    try std.testing.expectEqualStrings("stable", terminal.stateSnapshot().icon.?);
    const cleared = try terminal.feed("\x1b]1;\x07");
    try std.testing.expect(cleared.state_changed and cleared.icon_changed);
    try std.testing.expectEqualStrings("", terminal.stateSnapshot().icon.?);
}

test "raw OSC title updates terminal title through OSC owner path" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]Raw Title\x07");
    try std.testing.expectEqualStrings("Raw Title", terminal.host.current_title.?);
}

test "OSC title limit fails without dropping current title" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]0;ok\x07");

    const title_len = HostState.max_metadata_bytes + 1;
    const payload = try allocator.alloc(u8, title_len);
    defer allocator.free(payload);
    @memset(payload, 'a');

    var seq = std.ArrayList(u8).empty;
    defer seq.deinit(allocator);
    try seq.appendSlice(allocator, "\x1b]0;");
    try seq.appendSlice(allocator, payload);
    try seq.appendSlice(allocator, "\x07");

    try std.testing.expectError(error.ConsequenceLimit, stream.nextSlice(seq.items));
    try std.testing.expectEqualStrings("ok", terminal.host.current_title.?);
}

test "OSC icon limit preserves prior title and icon" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    const initial = try terminal.feed("\x1b]2;title\x07\x1b]1;icon\x07");
    try std.testing.expect(initial.title_changed);
    try std.testing.expect(initial.icon_changed);
    const payload = try allocator.alloc(u8, HostState.max_metadata_bytes + 1);
    defer allocator.free(payload);
    @memset(payload, 'i');
    var sequence = std.ArrayList(u8).empty;
    defer sequence.deinit(allocator);
    try sequence.appendSlice(allocator, "\x1b]1;");
    try sequence.appendSlice(allocator, payload);
    try sequence.append(allocator, 0x07);

    try std.testing.expectError(error.ConsequenceLimit, terminal.feed(sequence.items));
    const publication = terminal.stateSnapshot();
    try std.testing.expectEqualStrings("title", publication.title.?);
    try std.testing.expectEqualStrings("icon", publication.icon.?);
}

test "OSC 0 bound failure preserves both prior metadata values" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    const seeded = try terminal.feed("\x1b]2;old-title\x07\x1b]1;old-icon\x07");
    try std.testing.expect(seeded.state_changed);
    try std.testing.expect(seeded.title_changed);
    try std.testing.expect(seeded.icon_changed);
    const payload = try allocator.alloc(u8, HostState.max_metadata_bytes + 1);
    defer allocator.free(payload);
    @memset(payload, 'b');
    var sequence = std.ArrayList(u8).empty;
    defer sequence.deinit(allocator);
    try sequence.appendSlice(allocator, "\x1b]0;");
    try sequence.appendSlice(allocator, payload);
    try sequence.append(allocator, 0x07);

    try std.testing.expectError(error.ConsequenceLimit, terminal.feed(sequence.items));
    const publication = terminal.stateSnapshot();
    try std.testing.expectEqualStrings("old-title", publication.title.?);
    try std.testing.expectEqualStrings("old-icon", publication.icon.?);
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
        const publication = terminal.stateSnapshot();
        try std.testing.expectEqualStrings("old-title", publication.title.?);
        try std.testing.expectEqualStrings("old-icon", publication.icon.?);
        return err;
    };
    try std.testing.expect(summary.title_changed);
    try std.testing.expect(summary.icon_changed);
    const publication = terminal.stateSnapshot();
    try std.testing.expectEqualStrings("both", publication.title.?);
    try std.testing.expectEqualStrings("both", publication.icon.?);
}

test "OSC 8 retains explicit identity separately from URI and exact active mutation" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 20);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]8;id=one;https://example.com\x07a");
    try stream.nextSlice("\x1b]8;id=two;https://example.com\x1b\\b");
    try stream.nextSlice("\x1b]8;target=_blank:id=one;https://example.com\x07c");

    const screen = terminal.screen_state.activeConst();
    const first = screen.cellInfoAt(0, 0).attrs.link_id;
    const second = screen.cellInfoAt(0, 1).attrs.link_id;
    const third = screen.cellInfoAt(0, 2).attrs.link_id;
    try std.testing.expect(first != 0);
    try std.testing.expect(first != second);
    try std.testing.expectEqual(first, third);
    try std.testing.expectEqualStrings("https://example.com", terminal.host.hyperlinkUriForId(first).?);
    try std.testing.expectEqualStrings("https://example.com", terminal.host.hyperlinkUriForId(second).?);

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
            "\x1b]8;id=docs;https://example.com\x07",
    )).state_changed);
    const link_id = terminal.screen_state.primary.current_attrs.link_id;
    try std.testing.expect(link_id != 0);

    try std.testing.expect((try terminal.feed("\x1b[?1049h\x1b[?1049l")).state_changed);
    try terminal.resize(3, 10);
    var publication = terminal.stateSnapshot();
    try std.testing.expectEqualStrings("name", publication.title.?);
    try std.testing.expectEqualStrings("name", publication.icon.?);
    try std.testing.expectEqualStrings("file://host/work", publication.working_directory.?.value);
    try std.testing.expectEqualStrings("user@host", publication.remote_host.?);
    try std.testing.expectEqual(@as(u32, 20), publication.shell_integration.?.version);
    try std.testing.expectEqualStrings("bash", publication.shell_integration.?.shell.?);
    try std.testing.expectEqual(@as(u64, 1), publication.shell_mark.generation);
    try std.testing.expectEqual(link_id, terminal.screen_state.primary.current_attrs.link_id);

    try std.testing.expect((try terminal.feed("\x1bc")).state_changed);
    publication = terminal.stateSnapshot();
    try std.testing.expectEqualStrings("name", publication.title.?);
    try std.testing.expectEqualStrings("name", publication.icon.?);
    try std.testing.expect(publication.working_directory == null);
    try std.testing.expectEqualStrings("user@host", publication.remote_host.?);
    try std.testing.expectEqual(@as(u32, 20), publication.shell_integration.?.version);
    try std.testing.expectEqual(@as(u64, 1), publication.shell_mark.generation);
    try std.testing.expectEqual(@as(u32, 0), terminal.screen_state.primary.current_attrs.link_id);
    try std.testing.expectEqualStrings("https://example.com", terminal.host.hyperlinkUriForId(link_id).?);
}

test "OSC 52 produces pending clipboard request" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]52;c;Zm9v\x07");
    try std.testing.expectEqualStrings("c;Zm9v", terminal.host.pendingClipboardSet().?);
    const request = terminal.pendingClipboardRequest().?;
    try std.testing.expect(request.kind == .set);
    try std.testing.expectEqualStrings("c", request.selection);
    const clipboard = (try terminal.drainPendingClipboard(request.generation, allocator)).?;
    defer allocator.free(clipboard);
    try std.testing.expectEqual(@as(?[]const u8, null), terminal.host.pendingClipboardSet());
}

test "OSC 52 decoded clipboard drain clears pending request" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]52;c;SG93bA==\x07");

    const request = terminal.pendingClipboardRequest().?;
    const text = (try terminal.host.drainPendingClipboardSet(request.generation, allocator)).?;
    defer allocator.free(text);
    try std.testing.expectEqualStrings("Howl", text);
    try std.testing.expectEqual(@as(?[]const u8, null), terminal.host.pendingClipboardSet());
}

test "OSC 52 query is retained for exact transactional host reply" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 16);
    defer terminal.deinit();
    try std.testing.expect(!(try terminal.feed("\x1b]52;cp")).state_changed);
    try std.testing.expect((try terminal.feed(";?\x1b\\")).state_changed);
    var request = terminal.pendingClipboardRequest().?;
    try std.testing.expectEqual(@as(?[]u8, null), try terminal.host.drainPendingClipboardSet(
        request.generation,
        allocator,
    ));
    try std.testing.expect(request.kind == .query);
    try std.testing.expectEqualStrings("cp", request.selection);
    try std.testing.expect((try terminal.feed("\x1bc")).state_changed);
    try std.testing.expectEqualStrings("cp", terminal.pendingClipboardRequest().?.selection);
    try std.testing.expect(try terminal.replyPendingClipboard(request.generation, "A\x00B"));
    try std.testing.expectEqualStrings("\x1b]52;cp;QQBC\x1b\\", terminal.host.pendingOutput());
    try std.testing.expectEqual(@as(?Terminal.ClipboardRequest, null), terminal.pendingClipboardRequest());
    try std.testing.expectError(error.StaleClipboardRequest, terminal.replyPendingClipboard(
        request.generation,
        "unused",
    ));

    terminal.host.clearPendingOutput();
    try std.testing.expect((try terminal.feed("\x1b G\x9d52;;?\x9c")).state_changed);
    request = terminal.pendingClipboardRequest().?;
    try std.testing.expectEqualStrings("", request.selection);
    try std.testing.expect(try terminal.replyPendingClipboard(request.generation, ""));
    try std.testing.expectEqualStrings("\x9d52;;\x9c", terminal.host.pendingOutput());
    try std.testing.expectEqual(@as(?[]const u8, null), terminal.host.pendingClipboardSet());
}

test "OSC 52 rejects malformed selections and base64 without replacing a request" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 16);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b]52;c;b2xk\x07")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b]52;x;bmV3\x07")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b]52;c;!!!!\x07")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b]52;c;?trailing\x07")).state_changed);
    try std.testing.expectEqualStrings("c;b2xk", terminal.host.pendingClipboardSet().?);

    const request = terminal.pendingClipboardRequest().?;
    const decoded = (try terminal.drainPendingClipboard(request.generation, allocator)).?;
    defer allocator.free(decoded);
    try std.testing.expectEqualStrings("old", decoded);
}

test "OSC 52 reply bounds preserve query and prior pending output" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 16);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("\x1b]52;p;?\x07")).state_changed);
    const request = terminal.pendingClipboardRequest().?;

    const fill = try allocator.alloc(u8, HostState.pending_output_max_bytes - 1);
    defer allocator.free(fill);
    @memset(fill, 'x');
    try terminal.host.appendPendingOutput(fill);
    try std.testing.expectError(
        error.ConsequenceLimit,
        terminal.replyPendingClipboard(request.generation, "Howl"),
    );
    try std.testing.expectEqualStrings("p", terminal.pendingClipboardRequest().?.selection);
    try std.testing.expectEqualSlices(u8, fill, terminal.host.pendingOutput());

    terminal.host.clearPendingOutput();
    const oversized = try allocator.alloc(u8, Terminal.clipboard_reply_max_bytes + 1);
    defer allocator.free(oversized);
    @memset(oversized, 'z');
    try std.testing.expectError(
        error.ConsequenceLimit,
        terminal.replyPendingClipboard(request.generation, oversized),
    );
    try std.testing.expectEqualStrings("p", terminal.pendingClipboardRequest().?.selection);
    try std.testing.expectEqualStrings("", terminal.host.pendingOutput());

    try std.testing.expect(try terminal.replyPendingClipboard(
        request.generation,
        oversized[0..Terminal.clipboard_reply_max_bytes],
    ));
    try std.testing.expect(terminal.host.pendingOutput().len <= HostState.pending_output_max_bytes);
    try std.testing.expectEqual(@as(?Terminal.ClipboardRequest, null), terminal.pendingClipboardRequest());
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
    var publication = terminal.stateSnapshot();
    try std.testing.expectEqual(@as(u8, 3), publication.clipboard_request_count);
    var request = publication.clipboard_request.?;
    try std.testing.expectEqual(@as(u64, 1), request.generation);
    try std.testing.expect(request.kind == .set);
    try std.testing.expectEqualStrings("c", request.selection);
    try std.testing.expectError(
        error.StaleClipboardRequest,
        terminal.drainPendingClipboard(2, allocator),
    );

    const first = (try terminal.drainPendingClipboard(request.generation, allocator)).?;
    defer allocator.free(first);
    try std.testing.expectEqualStrings("One", first);
    publication = terminal.stateSnapshot();
    try std.testing.expectEqual(@as(u8, 2), publication.clipboard_request_count);
    request = publication.clipboard_request.?;
    try std.testing.expectEqual(@as(u64, 2), request.generation);
    try std.testing.expect(request.kind == .query);
    try std.testing.expectError(error.ClipboardReplyRequired, terminal.acknowledgeClipboard(2));
    try std.testing.expectError(
        error.StaleClipboardRequest,
        terminal.replyPendingClipboard(3, "wrong"),
    );
    try std.testing.expectEqualStrings("", terminal.host.pendingOutput());
    try std.testing.expect(try terminal.replyPendingClipboard(2, "reply"));
    try std.testing.expectEqualStrings("\x1b]52;p;cmVwbHk=\x1b\\", terminal.host.pendingOutput());

    request = terminal.pendingClipboardRequest().?;
    try std.testing.expectEqual(@as(u64, 3), request.generation);
    const second = (try terminal.drainPendingClipboard(request.generation, allocator)).?;
    defer allocator.free(second);
    try std.testing.expectEqualStrings("Two", second);
    try std.testing.expect(terminal.pendingClipboardRequest() == null);

    try std.testing.expect((try terminal.feed("\x1b]52;c;QQ==\x07")).state_changed);
    try std.testing.expect((try terminal.feed("\x1bc\x1b[?1049h\x1b[?1049l")).state_changed);
    try terminal.resize(4, 20);
    publication = terminal.stateSnapshot();
    try std.testing.expectEqual(@as(u64, 4), publication.clipboard_request.?.generation);
    try std.testing.expectEqual(@as(u8, 1), publication.clipboard_request_count);
}

test "OSC 52 queue and aggregate bounds preserve identity and wrap" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 16);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b]52;c;QQ==\x07")).state_changed);
    try terminal.acknowledgeClipboard(1);
    for (0..Terminal.clipboard_max_count) |_| {
        try std.testing.expect((try terminal.feed("\x1b]52;c;Qg==\x07")).state_changed);
    }
    var publication = terminal.stateSnapshot();
    try std.testing.expectEqual(Terminal.clipboard_max_count, publication.clipboard_request_count);
    try std.testing.expectEqual(@as(u64, 2), publication.clipboard_request.?.generation);
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed("\x1b]52;c;Qw==\x07"));
    publication = terminal.stateSnapshot();
    try std.testing.expectEqual(Terminal.clipboard_max_count, publication.clipboard_request_count);
    try std.testing.expectEqual(@as(u64, 2), publication.clipboard_request.?.generation);

    for (2..10) |generation| try terminal.acknowledgeClipboard(@intCast(generation));
    try std.testing.expect(terminal.pendingClipboardRequest() == null);
    try std.testing.expect((try terminal.feed("\x1b]52;c;RA==\x07")).state_changed);
    try std.testing.expectEqual(@as(u64, 10), terminal.pendingClipboardRequest().?.generation);
    try terminal.acknowledgeClipboard(10);

    const payload = try allocator.alloc(u8, Terminal.clipboard_request_max_bytes);
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
    try std.testing.expectEqual(@as(u64, 11), terminal.pendingClipboardRequest().?.generation);
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed("\x1b]52;c;RQ==\x07"));
    try std.testing.expectEqual(@as(u64, 11), terminal.pendingClipboardRequest().?.generation);
    try std.testing.expectEqual(@as(u8, 1), terminal.stateSnapshot().clipboard_request_count);
    try terminal.acknowledgeClipboard(11);

    terminal.host.clipboard_generation = std.math.maxInt(u64);
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed("\x1b]52;c;Rg==\x07"));
    try std.testing.expect(terminal.pendingClipboardRequest() == null);
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
    var publication = terminal.stateSnapshot();
    try std.testing.expectEqual(@as(u8, 3), publication.clipboard_request_count);

    var request = publication.clipboard_request.?;
    try std.testing.expectEqual(@as(u64, 1), request.generation);
    try std.testing.expect(request.protocol == .kitty_5522);
    try std.testing.expect(request.kind == .packet);
    try std.testing.expectEqualStrings("", request.selection);
    try std.testing.expectEqualStrings("type=write", request.payload);
    try std.testing.expect(!(try terminal.replyPendingClipboard(request.generation, "ignored")));
    try std.testing.expectEqual(@as(?[]u8, null), try terminal.drainPendingClipboard(
        request.generation,
        std.testing.allocator,
    ));
    try std.testing.expectEqual(@as(u8, 3), terminal.stateSnapshot().clipboard_request_count);
    try terminal.acknowledgeClipboard(request.generation);

    request = terminal.pendingClipboardRequest().?;
    try std.testing.expectEqual(@as(u64, 2), request.generation);
    try std.testing.expect(request.protocol == .osc52);
    try std.testing.expect(request.kind == .query);
    try std.testing.expectEqualStrings("c", request.selection);
    try std.testing.expectEqualStrings("c;?", request.payload);
    try std.testing.expect(try terminal.replyPendingClipboard(request.generation, "A\x00B"));
    const reply = try terminal.drainPendingOutput(std.testing.allocator);
    defer std.testing.allocator.free(reply);
    try std.testing.expectEqualStrings("\x1b]52;c;QQBC\x1b\\", reply);

    request = terminal.pendingClipboardRequest().?;
    try std.testing.expectEqual(@as(u64, 3), request.generation);
    try std.testing.expect(request.protocol == .kitty_5522);
    try std.testing.expectEqualStrings("type=read;dGV4dC9wbGFpbg==", request.payload);
    try std.testing.expectError(error.StaleClipboardRequest, terminal.acknowledgeClipboard(2));
    try terminal.acknowledgeClipboard(3);
    try std.testing.expect(terminal.pendingClipboardRequest() == null);

    try std.testing.expect((try terminal.feed("\x9d5522;type=wdata:mime=dGV4dA==;QQ==\x9c")).state_changed);
    try std.testing.expect((try terminal.feed("\x1bc\x1b[?1049h\x1b[?1049l")).state_changed);
    try terminal.resize(4, 20);
    publication = terminal.stateSnapshot();
    try std.testing.expectEqual(@as(u64, 4), publication.clipboard_request.?.generation);
    try std.testing.expectEqualStrings(
        "type=wdata:mime=dGV4dA==;QQ==",
        publication.clipboard_request.?.payload,
    );
}

test "Kitty OSC 5522 packet and FIFO bounds preserve prior occurrences" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 16);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b]5522;type=write\x1b\\")).state_changed);
    try terminal.acknowledgeClipboard(1);

    const payload = try allocator.alloc(u8, Terminal.kitty_clipboard_packet_max_bytes + 1);
    defer allocator.free(payload);
    @memset(payload, 'x');
    var sequence = std.ArrayList(u8).empty;
    defer sequence.deinit(allocator);
    try sequence.appendSlice(allocator, "\x1b]5522;");
    try sequence.appendSlice(allocator, payload[0..Terminal.kitty_clipboard_packet_max_bytes]);
    try sequence.appendSlice(allocator, "\x1b\\");
    const split = sequence.items.len / 2;
    try std.testing.expect(!(try terminal.feed(sequence.items[0..split])).state_changed);
    try std.testing.expect((try terminal.feed(sequence.items[split..])).state_changed);
    for (0..Terminal.clipboard_max_count - 1) |_| {
        try std.testing.expect((try terminal.feed("\x1b]5522;type=wdata\x1b\\")).state_changed);
    }
    var publication = terminal.stateSnapshot();
    try std.testing.expectEqual(Terminal.clipboard_max_count, publication.clipboard_request_count);
    try std.testing.expectEqual(@as(u64, 2), publication.clipboard_request.?.generation);
    try std.testing.expectEqual(
        @as(usize, Terminal.kitty_clipboard_packet_max_bytes),
        publication.clipboard_request.?.payload.len,
    );
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed("\x1b]52;c;QQ==\x07"));
    publication = terminal.stateSnapshot();
    try std.testing.expectEqual(@as(u64, 2), publication.clipboard_request.?.generation);
    try std.testing.expectEqual(Terminal.clipboard_max_count, publication.clipboard_request_count);

    for (0..Terminal.clipboard_max_count) |_| {
        const head = terminal.pendingClipboardRequest().?;
        try terminal.acknowledgeClipboard(head.generation);
    }
    try std.testing.expect(terminal.pendingClipboardRequest() == null);
    try std.testing.expect((try terminal.feed("\x1b]5522;type=read;Lg==\x1b\\")).state_changed);
    try std.testing.expectEqual(@as(u64, 10), terminal.pendingClipboardRequest().?.generation);
    try terminal.acknowledgeClipboard(10);

    sequence.clearRetainingCapacity();
    try sequence.appendSlice(allocator, "\x1b]5522;");
    try sequence.appendSlice(allocator, payload);
    try sequence.appendSlice(allocator, "\x1b\\");
    try std.testing.expectError(error.StringControlLimit, terminal.feed(sequence.items));
    try std.testing.expect(terminal.pendingClipboardRequest() == null);
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
    try std.testing.expectEqual(@as(u8, 4), terminal.stateSnapshot().file_transfer_count);

    const expected = [_]struct { protocol: terminal_mod.FileTransferProtocol, payload: []const u8 }{
        .{ .protocol = .iterm2_1337, .payload = "MultipartFile=name=ZmlsZQ==" },
        .{ .protocol = .kitty_5113, .payload = "ac=send;id=1;d=QQ==" },
        .{ .protocol = .iterm2_1337, .payload = "FilePart=Qg==" },
        .{ .protocol = .iterm2_1337, .payload = "FileEnd=done" },
    };
    try std.testing.expectError(error.StaleFileTransfer, terminal.acknowledgeFileTransfer(2));
    for (expected, 1..) |item, generation| {
        const packet = terminal.stateSnapshot().file_transfer.?;
        try std.testing.expectEqual(@as(u64, @intCast(generation)), packet.generation);
        try std.testing.expect(packet.protocol == item.protocol);
        try std.testing.expectEqualStrings(item.payload, packet.payload);
        try terminal.acknowledgeFileTransfer(packet.generation);
    }
    try std.testing.expect(terminal.stateSnapshot().file_transfer == null);

    try std.testing.expect((try terminal.feed("\x9d5113;ac=send;id=2\x9c")).state_changed);
    try std.testing.expect((try terminal.feed("\x1bc\x1b[?1049h\x1b[?1049l")).state_changed);
    try terminal.resize(4, 20);
    const retained = terminal.stateSnapshot().file_transfer.?;
    try std.testing.expectEqual(@as(u64, 5), retained.generation);
    try std.testing.expectEqualStrings("ac=send;id=2", retained.payload);
}

test "opaque file-transfer bounds preserve FIFO identity and wrap" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 16);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b]5113;first\x1b\\")).state_changed);
    try terminal.acknowledgeFileTransfer(1);
    const payload = try allocator.alloc(u8, Terminal.file_transfer_max_bytes + 1);
    defer allocator.free(payload);
    @memset(payload, 'x');
    var sequence = std.ArrayList(u8).empty;
    defer sequence.deinit(allocator);
    try sequence.appendSlice(allocator, "\x1b]5113;");
    try sequence.appendSlice(allocator, payload[0..Terminal.file_transfer_max_bytes]);
    try sequence.appendSlice(allocator, "\x1b\\");
    const split = sequence.items.len / 2;
    try std.testing.expect(!(try terminal.feed(sequence.items[0..split])).state_changed);
    try std.testing.expect((try terminal.feed(sequence.items[split..])).state_changed);
    for (0..Terminal.file_transfer_max_count - 1) |_| {
        try std.testing.expect((try terminal.feed("\x1b]1337;FilePart=QQ==\x1b\\")).state_changed);
    }
    var publication = terminal.stateSnapshot();
    try std.testing.expectEqual(Terminal.file_transfer_max_count, publication.file_transfer_count);
    try std.testing.expectEqual(@as(u64, 2), publication.file_transfer.?.generation);
    try std.testing.expectEqual(@as(usize, Terminal.file_transfer_max_bytes), publication.file_transfer.?.payload.len);
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed("\x1b]5113;rejected\x1b\\"));
    publication = terminal.stateSnapshot();
    try std.testing.expectEqual(@as(u64, 2), publication.file_transfer.?.generation);
    try std.testing.expectEqual(Terminal.file_transfer_max_count, publication.file_transfer_count);

    for (0..Terminal.file_transfer_max_count) |_| {
        const packet = terminal.stateSnapshot().file_transfer.?;
        try terminal.acknowledgeFileTransfer(packet.generation);
    }
    try std.testing.expect((try terminal.feed("\x1b]5113;after\x1b\\")).state_changed);
    try std.testing.expectEqual(@as(u64, 10), terminal.stateSnapshot().file_transfer.?.generation);
    try terminal.acknowledgeFileTransfer(10);

    const iterm_payload = try allocator.alloc(u8, Terminal.iterm_file_transfer_max_bytes + 1);
    defer allocator.free(iterm_payload);
    @memset(iterm_payload, 'x');
    @memcpy(iterm_payload[0.."FilePart=".len], "FilePart=");
    sequence.clearRetainingCapacity();
    try sequence.appendSlice(allocator, "\x1b]1337;");
    try sequence.appendSlice(allocator, iterm_payload[0..Terminal.iterm_file_transfer_max_bytes]);
    try sequence.appendSlice(allocator, "\x1b\\");
    try std.testing.expect((try terminal.feed(sequence.items)).state_changed);
    try std.testing.expectEqual(@as(u64, 11), terminal.stateSnapshot().file_transfer.?.generation);
    try terminal.acknowledgeFileTransfer(11);
    sequence.clearRetainingCapacity();
    try sequence.appendSlice(allocator, "\x1b]1337;");
    try sequence.appendSlice(allocator, iterm_payload);
    try sequence.appendSlice(allocator, "\x1b\\");
    try std.testing.expectError(error.StringControlLimit, terminal.feed(sequence.items));
    try std.testing.expect(terminal.stateSnapshot().file_transfer == null);

    sequence.clearRetainingCapacity();
    try sequence.appendSlice(allocator, "\x1b]5113;");
    try sequence.appendSlice(allocator, payload);
    try sequence.appendSlice(allocator, "\x1b\\");
    try std.testing.expectError(error.StringControlLimit, terminal.feed(sequence.items));
    try std.testing.expect(terminal.stateSnapshot().file_transfer == null);
    terminal.host.file_transfer_generation = std.math.maxInt(u64);
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed("\x1b]5113;exhausted\x1b\\"));
    try std.testing.expect(terminal.stateSnapshot().file_transfer == null);
}

test "shell integration OSC 133 records latest mark" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]133;C;cmdline=ls\x07\x1b]133;D;2\x07");

    const mark = terminal.stateSnapshot().shell_mark;
    try std.testing.expectEqual(@as(u64, 2), mark.generation);
    try std.testing.expectEqual(@as(u8, 'D'), mark.kind);
    try std.testing.expectEqual(@as(?i32, 2), mark.status);
    try std.testing.expectEqualStrings("2", mark.metadata);

    try stream.nextSlice("\x1b]133;Z;ignored\x07");
    try std.testing.expectEqual(@as(u64, 2), terminal.stateSnapshot().shell_mark.generation);
}

test "OSC 133 retains exact metadata and finds positional exit status" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b]133;D;aid=nested;")).state_changed);
    try std.testing.expectEqual(@as(u64, 0), terminal.stateSnapshot().shell_mark.generation);
    try std.testing.expect((try terminal.feed("7;cl=done\x1b\\")).state_changed);
    var mark = terminal.stateSnapshot().shell_mark;
    try std.testing.expectEqual(@as(u64, 1), mark.generation);
    try std.testing.expectEqual(@as(u8, 'D'), mark.kind);
    try std.testing.expectEqual(@as(?i32, 7), mark.status);
    try std.testing.expectEqualStrings("aid=nested;7;cl=done", mark.metadata);

    try std.testing.expect((try terminal.feed("\x9d133;D;;-3;aid=second\x9c")).state_changed);
    mark = terminal.stateSnapshot().shell_mark;
    try std.testing.expectEqual(@as(u64, 2), mark.generation);
    try std.testing.expectEqual(@as(?i32, -3), mark.status);
    try std.testing.expectEqualStrings(";-3;aid=second", mark.metadata);

    try std.testing.expect((try terminal.feed("\x1b]133;D;aid=only;broken\x07")).state_changed);
    mark = terminal.stateSnapshot().shell_mark;
    try std.testing.expectEqual(@as(u64, 3), mark.generation);
    try std.testing.expectEqual(@as(?i32, null), mark.status);
    try std.testing.expectEqualStrings("aid=only;broken", mark.metadata);

    try std.testing.expect((try terminal.feed("\x1b]133;C;cmdline=exit 7\x07")).state_changed);
    mark = terminal.stateSnapshot().shell_mark;
    try std.testing.expectEqual(@as(u64, 4), mark.generation);
    try std.testing.expectEqual(@as(u8, 'C'), mark.kind);
    try std.testing.expectEqual(@as(?i32, null), mark.status);
    try std.testing.expectEqualStrings("cmdline=exit 7", mark.metadata);

    try std.testing.expect((try terminal.feed("\x1bc\x1b[?1049h\x1b[?1049l")).state_changed);
    mark = terminal.stateSnapshot().shell_mark;
    try std.testing.expectEqual(@as(u64, 4), mark.generation);
    try std.testing.expectEqualStrings("cmdline=exit 7", mark.metadata);
}

test "OSC notifications retain ordered bounded host-neutral occurrences" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b]9;hel")).state_changed == false);
    try std.testing.expect(terminal.stateSnapshot().notification == null);
    try std.testing.expect((try terminal.feed("lo\x07")).state_changed);
    var notification = terminal.stateSnapshot().notification.?;
    try std.testing.expectEqual(@as(u64, 1), notification.generation);
    try std.testing.expectEqual(host_state.NotificationKind.message, notification.kind);
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
    try std.testing.expectEqual(@as(u8, 7), terminal.stateSnapshot().notification_count);
    try std.testing.expectError(error.StaleNotification, terminal.acknowledgeNotification(2));

    const expected = [_]struct { kind: host_state.NotificationKind, command: u16, payload: []const u8 }{
        .{ .kind = .message, .command = 9, .payload = "hello" },
        .{ .kind = .message, .command = 99, .payload = "i=one:d=0;body" },
        .{ .kind = .message, .command = 777, .payload = "notify;title;body" },
        .{ .kind = .message, .command = 1337, .payload = "rich body" },
        .{ .kind = .steal_focus, .command = 1337, .payload = "" },
        .{ .kind = .request_attention, .command = 1337, .payload = "fireworks" },
        .{ .kind = .message, .command = 9, .payload = "last" },
    };
    for (expected, 1..) |item, generation| {
        notification = terminal.stateSnapshot().notification.?;
        try std.testing.expectEqual(@as(u64, @intCast(generation)), notification.generation);
        try std.testing.expectEqual(item.kind, notification.kind);
        try std.testing.expectEqual(item.command, notification.command);
        try std.testing.expectEqualStrings(item.payload, notification.payload);
        try terminal.acknowledgeNotification(notification.generation);
    }
    try std.testing.expect(terminal.stateSnapshot().notification == null);

    try std.testing.expect(!(try terminal.feed("\x1b]1337;RequestAtt")).state_changed);
    try std.testing.expect((try terminal.feed("ention=once\x07")).state_changed);
    try std.testing.expect((try terminal.feed("\x1bc\x1b[?1049h\x1b[?1049l")).state_changed);
    notification = terminal.stateSnapshot().notification.?;
    try std.testing.expectEqual(@as(u64, 8), notification.generation);
    try std.testing.expectEqual(host_state.NotificationKind.request_attention, notification.kind);
    try std.testing.expectEqualStrings("once", notification.payload);
}

test "OSC notification bounds preserve the FIFO and wrap without reuse" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b]9;prior\x07")).state_changed);
    const payload = try allocator.alloc(u8, Terminal.notification_max_bytes + 1);
    defer allocator.free(payload);
    @memset(payload, 'x');
    var sequence = std.ArrayList(u8).empty;
    defer sequence.deinit(allocator);
    try sequence.appendSlice(allocator, "\x1b]9;");
    try sequence.appendSlice(allocator, payload[0..Terminal.notification_max_bytes]);
    try sequence.append(allocator, 0x07);

    try std.testing.expect((try terminal.feed(sequence.items)).state_changed);
    var retained = terminal.stateSnapshot().notification.?;
    try std.testing.expectEqual(@as(u64, 1), retained.generation);
    try std.testing.expectEqualStrings("prior", retained.payload);
    try std.testing.expectEqual(@as(u8, 2), terminal.stateSnapshot().notification_count);

    sequence.clearRetainingCapacity();
    try sequence.appendSlice(allocator, "\x1b]9;");
    try sequence.appendSlice(allocator, payload);
    try sequence.append(allocator, 0x07);

    try std.testing.expectError(error.ConsequenceLimit, terminal.feed(sequence.items));
    retained = terminal.stateSnapshot().notification.?;
    try std.testing.expectEqual(@as(u64, 1), retained.generation);
    try std.testing.expectEqualStrings("prior", retained.payload);
    try std.testing.expectEqual(@as(u8, 2), terminal.stateSnapshot().notification_count);

    try terminal.acknowledgeNotification(1);
    retained = terminal.stateSnapshot().notification.?;
    try std.testing.expectEqual(@as(u64, 2), retained.generation);
    try std.testing.expectEqual(Terminal.notification_max_bytes, retained.payload.len);
    for (0..Terminal.notification_max_count - 1) |_| {
        try std.testing.expect((try terminal.feed("\x1b]9;queued\x07")).state_changed);
    }
    const full = terminal.stateSnapshot();
    try std.testing.expectEqual(Terminal.notification_max_count, full.notification_count);
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed("\x1b]9;rejected\x07"));
    try std.testing.expectEqual(@as(u64, 2), terminal.stateSnapshot().notification.?.generation);
    try std.testing.expectEqual(Terminal.notification_max_count, terminal.stateSnapshot().notification_count);

    for (0..Terminal.notification_max_count) |_| {
        retained = terminal.stateSnapshot().notification.?;
        try terminal.acknowledgeNotification(retained.generation);
    }
    try std.testing.expect(terminal.stateSnapshot().notification == null);
    try std.testing.expect((try terminal.feed("\x1b]9;after\x07")).state_changed);
    retained = terminal.stateSnapshot().notification.?;
    try std.testing.expectEqual(@as(u64, 10), retained.generation);
    try std.testing.expectEqualStrings("after", retained.payload);
    try terminal.acknowledgeNotification(10);
    try std.testing.expectError(error.StaleNotification, terminal.acknowledgeNotification(10));
    terminal.host.notification_generation = std.math.maxInt(u64);
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed("\x1b]9;exhausted\x07"));
    try std.testing.expect(terminal.stateSnapshot().notification == null);
}

test "OSC 22 retains ordered bounded host-neutral requests" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b]22;>wait,")).state_changed);
    try std.testing.expect(terminal.stateSnapshot().pointer_shape == null);
    try std.testing.expect((try terminal.feed("pointer\x1b\\")).state_changed);
    var request = terminal.stateSnapshot().pointer_shape.?;
    try std.testing.expectEqual(@as(u64, 1), request.generation);
    try std.testing.expectEqualStrings(">wait,pointer", request.payload);

    try std.testing.expect((try terminal.feed(
        "\x9d22;?default,current\x9c" ++
            "\x1b]22;>crosshair\x07" ++
            "\x1b]22;<1\x07",
    )).state_changed);
    try std.testing.expectEqual(@as(u8, 4), terminal.stateSnapshot().pointer_shape_count);
    try std.testing.expectError(error.StalePointerShape, terminal.acknowledgePointerShape(2));

    const expected = [_][]const u8{
        ">wait,pointer",
        "?default,current",
        ">crosshair",
        "<1",
    };
    for (expected, 1..) |payload, generation| {
        request = terminal.stateSnapshot().pointer_shape.?;
        try std.testing.expectEqual(@as(u64, @intCast(generation)), request.generation);
        try std.testing.expectEqualStrings(payload, request.payload);
        try terminal.acknowledgePointerShape(request.generation);
    }
    try std.testing.expect(terminal.stateSnapshot().pointer_shape == null);

    try std.testing.expect((try terminal.feed("\x1b]22;survives\x07")).state_changed);
    try std.testing.expect((try terminal.feed("\x1bc\x1b[?1049h\x1b[?1049l")).state_changed);
    try terminal.resize(4, 9);
    request = terminal.stateSnapshot().pointer_shape.?;
    try std.testing.expectEqual(@as(u64, 5), request.generation);
    try std.testing.expectEqualStrings("survives", request.payload);
}

test "OSC 22 bounds preserve the FIFO and wrap without reuse" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    const payload = try allocator.alloc(u8, Terminal.pointer_shape_max_bytes + 1);
    defer allocator.free(payload);
    @memset(payload, 'x');
    var sequence = std.ArrayList(u8).empty;
    defer sequence.deinit(allocator);

    try std.testing.expect((try terminal.feed("\x1b]22;prior\x07")).state_changed);
    try sequence.appendSlice(allocator, "\x1b]22;");
    try sequence.appendSlice(allocator, payload[0..Terminal.pointer_shape_max_bytes]);
    try sequence.append(allocator, 0x07);
    try std.testing.expect((try terminal.feed(sequence.items)).state_changed);
    var retained = terminal.stateSnapshot().pointer_shape.?;
    try std.testing.expectEqual(@as(u64, 1), retained.generation);
    try std.testing.expectEqualStrings("prior", retained.payload);
    try std.testing.expectEqual(@as(u8, 2), terminal.stateSnapshot().pointer_shape_count);

    sequence.clearRetainingCapacity();
    try sequence.appendSlice(allocator, "\x1b]22;");
    try sequence.appendSlice(allocator, payload);
    try sequence.append(allocator, 0x07);
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed(sequence.items));
    retained = terminal.stateSnapshot().pointer_shape.?;
    try std.testing.expectEqual(@as(u64, 1), retained.generation);
    try std.testing.expectEqualStrings("prior", retained.payload);
    try std.testing.expectEqual(@as(u8, 2), terminal.stateSnapshot().pointer_shape_count);

    try terminal.acknowledgePointerShape(1);
    retained = terminal.stateSnapshot().pointer_shape.?;
    try std.testing.expectEqual(@as(u64, 2), retained.generation);
    try std.testing.expectEqual(Terminal.pointer_shape_max_bytes, retained.payload.len);
    for (0..Terminal.pointer_shape_max_count - 1) |_| {
        try std.testing.expect((try terminal.feed("\x1b]22;queued\x07")).state_changed);
    }
    try std.testing.expectEqual(
        Terminal.pointer_shape_max_count,
        terminal.stateSnapshot().pointer_shape_count,
    );
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed("\x1b]22;rejected\x07"));
    try std.testing.expectEqual(@as(u64, 2), terminal.stateSnapshot().pointer_shape.?.generation);
    try std.testing.expectEqual(
        Terminal.pointer_shape_max_count,
        terminal.stateSnapshot().pointer_shape_count,
    );

    for (0..Terminal.pointer_shape_max_count) |_| {
        retained = terminal.stateSnapshot().pointer_shape.?;
        try terminal.acknowledgePointerShape(retained.generation);
    }
    try std.testing.expect(terminal.stateSnapshot().pointer_shape == null);
    try std.testing.expect((try terminal.feed("\x1b]22;after\x07")).state_changed);
    retained = terminal.stateSnapshot().pointer_shape.?;
    try std.testing.expectEqual(@as(u64, 10), retained.generation);
    try std.testing.expectEqualStrings("after", retained.payload);
    try terminal.acknowledgePointerShape(10);
    try std.testing.expectError(error.StalePointerShape, terminal.acknowledgePointerShape(10));
    terminal.host.pointer_shape_generation = std.math.maxInt(u64);
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed("\x1b]22;exhausted\x07"));
    try std.testing.expect(terminal.stateSnapshot().pointer_shape == null);
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
    const state = terminal.stateSnapshot();
    const visual = terminal.visualView();
    try std.testing.expectEqual(Screen.CursorShape.bar, visual.view.cursor_shape);
    try std.testing.expectEqual(@as(u32, 20), state.shell_integration.?.version);
    try std.testing.expectEqualStrings("bash", state.shell_integration.?.shell.?);
    try std.testing.expectEqual(Rgb{ .r = 0xaa, .g = 0xbb, .b = 0xcc }, visual.presentation.foreground);
    try std.testing.expectEqual(Rgb{ .r = 0x10, .g = 0x20, .b = 0x30 }, visual.presentation.background);
    try std.testing.expectEqual(Rgb{ .r = 0xff, .g = 0, .b = 0 }, visual.presentation.palette[1]);
    try std.testing.expectEqual(Rgb{ .r = 1, .g = 2, .b = 3 }, visual.presentation.cursor.?);
    try std.testing.expectEqual(Rgb{ .r = 4, .g = 5, .b = 6 }, visual.presentation.cursor_text.?);
    try std.testing.expectEqual(Rgb{ .r = 0xee, .g = 0xee, .b = 0xee }, visual.presentation.palette[15]);
    try std.testing.expectEqualStrings(
        "\x1b]1337;ReportCellSize=18;9;1\x1b\\",
        terminal.host.pendingOutput(),
    );
    const first_reply = try terminal.drainPendingOutput(std.testing.allocator);
    defer std.testing.allocator.free(first_reply);
    const valued_request = try terminal.feed(
        "\x1b]1337;ReportCellSize=ignored-by-iterm\x07",
    );
    try std.testing.expect(valued_request.state_changed);
    try std.testing.expectEqualStrings(
        "\x1b]1337;ReportCellSize=18;9;1\x1b\\",
        terminal.host.pendingOutput(),
    );

    const osc_50 = try terminal.feed("\x1b]50;CursorShape=2\x07");
    try std.testing.expect(osc_50.state_changed);
    try std.testing.expectEqual(
        Screen.CursorShape.underline,
        terminal.visualView().view.cursor_shape,
    );
    try std.testing.expect(!(try terminal.feed("\x1b]1337;CursorShape=2\x07")).state_changed);
    try std.testing.expect(!(try terminal.feed(
        "\x1b]1337;CursorShape=\x07\x1b]1337;CursorShape=x\x1b\\",
    )).state_changed);
    try std.testing.expectEqual(
        Screen.CursorShape.underline,
        terminal.visualView().view.cursor_shape,
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
    terminal.host.clearPendingOutput();

    const rejected = try terminal.feed(
        "\x1b]50;SetColors=fg=abcdef\x07" ++
            "\x1b]50;ShellIntegrationVersion=21;shell=zsh\x07" ++
            "\x1b]50;ReportCellSize\x07",
    );
    try std.testing.expect(!rejected.state_changed);
    const publication = terminal.stateSnapshot();
    try std.testing.expectEqual(
        Rgb{ .r = 0x11, .g = 0x22, .b = 0x33 },
        terminal.visualView().presentation.foreground,
    );
    try std.testing.expectEqual(@as(u32, 20), publication.shell_integration.?.version);
    try std.testing.expectEqualStrings("bash", publication.shell_integration.?.shell.?);
    try std.testing.expectEqual(@as(usize, 0), terminal.host.pendingOutput().len);

    const accepted = try terminal.feed("\x1b]50;CursorShape=1\x07");
    try std.testing.expect(accepted.state_changed);
    try std.testing.expectEqual(
        Screen.CursorShape.bar,
        terminal.visualView().view.cursor_shape,
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

test "iTerm metadata replacement preserves prior state on allocation failure" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    var state = HostState.HostState.init(failing.allocator());
    defer state.deinit();
    try std.testing.expect(try state.replaceShellIntegration(.{ .version = 19, .shell = "bash" }));
    try std.testing.expect(!(try state.replaceShellIntegration(.{ .version = 19, .shell = "bash" })));
    try std.testing.expectError(
        error.OutOfMemory,
        state.replaceShellIntegration(.{ .version = 20, .shell = "zsh" }),
    );
    try std.testing.expectEqual(@as(u32, 19), state.shell_integration.?.version);
    try std.testing.expectEqualStrings("bash", state.shell_integration.?.shell.?);
}

test "unsupported SetMark and Kitty context metadata remain exact no-ops" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b]1337;SetMark=lab")).state_changed);
    try std.testing.expect(!(try terminal.feed("el\x1b\\")).state_changed);
    try std.testing.expectEqual(@as(u64, 0), terminal.stateSnapshot().shell_mark.generation);
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
    try std.testing.expectEqual(@as(u64, 0), terminal.stateSnapshot().shell_mark.generation);
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
        const integration = terminal.stateSnapshot().shell_integration.?;
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
    const presentation = terminal.visualView().presentation;
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
    try std.testing.expectEqual(@as(usize, 0), terminal.host.pendingOutput().len);

    const changed = try terminal.feed("\x1b]4;1;#010203\x07");
    try std.testing.expect(changed.state_changed);
    const repeated = try terminal.feed("\x1b]4;1;#010203\x1b\\");
    try std.testing.expect(!repeated.state_changed);

    const query = try terminal.feed("\x1b]4;1;?\x07");
    try std.testing.expect(query.state_changed);
    try std.testing.expectEqualStrings("\x1b]4;1;rgb:0101/0202/0303\x1b\\", terminal.host.pendingOutput());

    terminal.host.clearPendingOutput();
    const iterm_malformed = try terminal.feed("\x1b]1337;SetColors=fg=bogus,missing,p3=x\x07");
    try std.testing.expect(!iterm_malformed.state_changed);
}

test "xterm pointer mode stores bounded resource value" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try std.testing.expectEqual(@as(u2, 1), terminal.modes.pointer_mode);
    try stream.nextSlice("\x1b[>2p");
    try std.testing.expectEqual(@as(u2, 2), terminal.modes.pointer_mode);

    try stream.nextSlice("\x1b[>9p");
    try std.testing.expectEqual(@as(u2, 3), terminal.modes.pointer_mode);

    try stream.nextSlice("\x1b[>p");
    try std.testing.expectEqual(@as(u2, 1), terminal.modes.pointer_mode);
}

test "kitty color stack OSC 30001 and 30101 track depth" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]30001\x1b\\\x1b]30001\x1b\\\x1b]30101\x1b\\");
    try std.testing.expectEqual(@as(u8, 1), terminal.kitty.color_stack.len);
}

test "kitty OSC 21 sets queries and resets terminal colors" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]21;foreground=#112233;background=rgb:44/55/66;cursor=\x1b\\");
    try stream.nextSlice("\x1b]21;foreground=?;background=?;cursor=?;no_such=?\x1b\\");

    const colors = terminal.host.terminalColorState();
    try std.testing.expectEqual(Rgb{ .r = 0x11, .g = 0x22, .b = 0x33 }, colors.foreground);
    try std.testing.expectEqual(Rgb{ .r = 0x44, .g = 0x55, .b = 0x66 }, colors.background);
    try std.testing.expectEqual(@as(?Rgb, null), colors.cursor);
    try std.testing.expectEqualStrings(
        "\x1b]21;foreground=rgb:1111/2222/3333\x1b\\" ++
            "\x1b]21;background=rgb:4444/5555/6666\x1b\\" ++
            "\x1b]21;cursor=\x1b\\" ++
            "\x1b]21;no_such=?\x1b\\",
        terminal.host.pendingOutput(),
    );

    try stream.nextSlice("\x1b]21;foreground;background\x1b\\");
    try std.testing.expectEqual(Rgb{ .r = 220, .g = 220, .b = 220 }, terminal.host.terminalColorState().foreground);
    try std.testing.expectEqual(Rgb{ .r = 24, .g = 25, .b = 33 }, terminal.host.terminalColorState().background);
}

test "xterm OSC colors set query and reset palette and dynamic colors" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]4;1;#010203\x1b\\\x1b]10;#aabbcc\x1b\\\x1b]11;rgb:0d/0e/0f\x1b\\\x1b]12;red\x1b\\");
    try stream.nextSlice("\x1b]4;1;?\x1b\\\x1b]10;?\x1b\\\x1b]11;?\x1b\\\x1b]12;?\x1b\\");

    try std.testing.expectEqual(Rgb{ .r = 1, .g = 2, .b = 3 }, terminal.host.terminalColorState().palette[1]);
    try std.testing.expectEqualStrings(
        "\x1b]4;1;rgb:0101/0202/0303\x1b\\" ++
            "\x1b]10;rgb:aaaa/bbbb/cccc\x1b\\" ++
            "\x1b]11;rgb:0d0d/0e0e/0f0f\x1b\\" ++
            "\x1b]12;rgb:ffff/0000/0000\x1b\\",
        terminal.host.pendingOutput(),
    );

    try stream.nextSlice("\x1b]104;1\x1b\\\x1b]110\x1b\\\x1b]111\x1b\\\x1b]112\x1b\\");
    try std.testing.expectEqual(Rgb{ .r = 205, .g = 49, .b = 49 }, terminal.host.terminalColorState().palette[1]);
    try std.testing.expectEqual(Rgb{ .r = 220, .g = 220, .b = 220 }, terminal.host.terminalColorState().foreground);
    try std.testing.expectEqual(Rgb{ .r = 24, .g = 25, .b = 33 }, terminal.host.terminalColorState().background);
    try std.testing.expectEqual(@as(?Rgb, null), terminal.host.terminalColorState().cursor);
}

test "OSC color grammar scales short components and rejects trailing components" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect(!(try terminal.feed("\x1b]4;1;#123;2;rgb:1/22/333/4")).state_changed);
    try std.testing.expect((try terminal.feed("44;3;rgb:1/22/333\x1b\\")).state_changed);
    var colors = terminal.host.terminalColorState();
    try std.testing.expectEqual(Rgb{ .r = 0x11, .g = 0x22, .b = 0x33 }, colors.palette[1]);
    try std.testing.expectEqual(Terminal.default_presentation.palette[2], colors.palette[2]);
    try std.testing.expectEqual(Rgb{ .r = 0x11, .g = 0x22, .b = 0x33 }, colors.palette[3]);

    try std.testing.expect(!(try terminal.feed("\x1b]4;1;#123;2;rgb:1/22/333/444\x07")).state_changed);
    colors = terminal.host.terminalColorState();
    try std.testing.expectEqual(Rgb{ .r = 0x11, .g = 0x22, .b = 0x33 }, colors.palette[1]);
    try std.testing.expectEqual(Terminal.default_presentation.palette[2], colors.palette[2]);

    try std.testing.expect((try terminal.feed("\x1b]4;1;?\x1b\\")).state_changed);
    try std.testing.expectEqualStrings(
        "\x1b]4;1;rgb:1111/2222/3333\x1b\\",
        terminal.host.pendingOutput(),
    );
}

test "xterm extra dynamic colors set query and reset host-neutral state" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]13;#010203\x1b\\\x1b]14;#040506\x1b\\\x1b]15;#070809\x1b\\\x1b]16;#0a0b0c\x1b\\\x1b]17;#0d0e0f\x1b\\\x1b]18;#101112\x1b\\\x1b]19;#131415\x1b\\");
    try stream.nextSlice("\x1b]13;?\x1b\\\x1b]14;?\x1b\\\x1b]15;?\x1b\\\x1b]16;?\x1b\\\x1b]17;?\x1b\\\x1b]18;?\x1b\\\x1b]19;?\x1b\\");

    const colors = terminal.host.terminalColorState();
    try std.testing.expectEqual(Rgb{ .r = 1, .g = 2, .b = 3 }, colors.pointer_foreground.?);
    try std.testing.expectEqual(Rgb{ .r = 4, .g = 5, .b = 6 }, colors.pointer_background.?);
    try std.testing.expectEqual(Rgb{ .r = 7, .g = 8, .b = 9 }, colors.tektronix_foreground.?);
    try std.testing.expectEqual(Rgb{ .r = 10, .g = 11, .b = 12 }, colors.tektronix_background.?);
    try std.testing.expectEqual(Rgb{ .r = 13, .g = 14, .b = 15 }, colors.selection_background.?);
    try std.testing.expectEqual(Rgb{ .r = 16, .g = 17, .b = 18 }, colors.tektronix_cursor.?);
    try std.testing.expectEqual(Rgb{ .r = 19, .g = 20, .b = 21 }, colors.selection_foreground.?);
    try std.testing.expectEqualStrings(
        "\x1b]13;rgb:0101/0202/0303\x1b\\" ++
            "\x1b]14;rgb:0404/0505/0606\x1b\\" ++
            "\x1b]15;rgb:0707/0808/0909\x1b\\" ++
            "\x1b]16;rgb:0a0a/0b0b/0c0c\x1b\\" ++
            "\x1b]17;rgb:0d0d/0e0e/0f0f\x1b\\" ++
            "\x1b]18;rgb:1010/1111/1212\x1b\\" ++
            "\x1b]19;rgb:1313/1414/1515\x1b\\",
        terminal.host.pendingOutput(),
    );

    terminal.host.clearPendingOutput();
    try stream.nextSlice("\x1b]113\x1b\\\x1b]114\x1b\\\x1b]115\x1b\\\x1b]116\x1b\\\x1b]117\x1b\\\x1b]118\x1b\\\x1b]119\x1b\\");
    const reset = terminal.host.terminalColorState();
    try std.testing.expectEqual(@as(?Rgb, null), reset.pointer_foreground);
    try std.testing.expectEqual(@as(?Rgb, null), reset.pointer_background);
    try std.testing.expectEqual(@as(?Rgb, null), reset.tektronix_foreground);
    try std.testing.expectEqual(@as(?Rgb, null), reset.tektronix_background);
    try std.testing.expectEqual(@as(?Rgb, null), reset.selection_background);
    try std.testing.expectEqual(@as(?Rgb, null), reset.tektronix_cursor);
    try std.testing.expectEqual(@as(?Rgb, null), reset.selection_foreground);
}

test "xterm special colors via OSC 5 and OSC 4 special offsets" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]5;0;#010203;1;#040506\x1b\\\x1b]4;258;#070809;260;#0a0b0c\x1b\\");
    try stream.nextSlice("\x1b]5;0;?;1;?\x1b\\\x1b]4;258;?;260;?\x1b\\");

    const colors = terminal.host.terminalColorState();
    try std.testing.expectEqual(Rgb{ .r = 1, .g = 2, .b = 3 }, colors.special_palette[0].?);
    try std.testing.expectEqual(Rgb{ .r = 4, .g = 5, .b = 6 }, colors.special_palette[1].?);
    try std.testing.expectEqual(Rgb{ .r = 7, .g = 8, .b = 9 }, colors.special_palette[2].?);
    try std.testing.expectEqual(Rgb{ .r = 10, .g = 11, .b = 12 }, colors.special_palette[4].?);
    try std.testing.expectEqualStrings(
        "\x1b]5;0;rgb:0101/0202/0303\x1b\\" ++
            "\x1b]5;1;rgb:0404/0505/0606\x1b\\" ++
            "\x1b]4;258;rgb:0707/0808/0909\x1b\\" ++
            "\x1b]4;260;rgb:0a0a/0b0b/0c0c\x1b\\",
        terminal.host.pendingOutput(),
    );

    terminal.host.clearPendingOutput();
    try stream.nextSlice("\x1b]104;258;260\x1b\\");
    const reset = terminal.host.terminalColorState();
    try std.testing.expectEqual(Rgb{ .r = 7, .g = 8, .b = 9 }, reset.special_palette[2].?);
    try std.testing.expectEqual(Rgb{ .r = 10, .g = 11, .b = 12 }, reset.special_palette[4].?);
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
    try std.testing.expectEqual(
        terminal.screen_state.primary.cursor.cursor_color,
        terminal.screen_state.alternate.cursor.cursor_color,
    );
    try std.testing.expect(!(try terminal.feed("\x1b]104;256;999;bad\x07")).state_changed);

    try std.testing.expect(!(try terminal.feed("\x1b]104;0;")).state_changed);
    try std.testing.expect((try terminal.feed("255\x1b\\")).state_changed);
    var colors = terminal.host.terminalColorState();
    try std.testing.expectEqual(Terminal.default_presentation.palette[0], colors.palette[0]);
    try std.testing.expectEqual(Terminal.default_presentation.palette[255], colors.palette[255]);

    try std.testing.expect((try terminal.feed(
        "\x1b]110\x07\x1b]111\x1b\\\x1b]112\x07\x1b]117\x1b\\\x1b]119\x07",
    )).state_changed);
    colors = terminal.host.terminalColorState();
    try std.testing.expectEqual(Terminal.default_presentation.foreground, colors.foreground);
    try std.testing.expectEqual(Terminal.default_presentation.background, colors.background);
    try std.testing.expectEqual(@as(?Rgb, null), colors.cursor);
    try std.testing.expectEqual(@as(?Rgb, null), terminal.screen_state.primary.cursor.cursor_color);
    try std.testing.expectEqual(@as(?Rgb, null), terminal.screen_state.alternate.cursor.cursor_color);
    try std.testing.expectEqual(@as(?Rgb, null), colors.selection_background);
    try std.testing.expectEqual(@as(?Rgb, null), colors.selection_foreground);
    try std.testing.expect(!(try terminal.feed(
        "\x1b]110\x07\x1b]111\x1b\\\x1b]112\x07\x1b]117\x1b\\\x1b]119\x07",
    )).state_changed);

    try std.testing.expect((try terminal.feed("\x1b]4;1;#212223\x1b\\\x1b]10;#313233\x1b\\")).state_changed);
    try terminal.resize(4, 12);
    try std.testing.expect((try terminal.feed("\x1b[?1049h\x1bc\x1b[?1049l")).state_changed);
    colors = terminal.host.terminalColorState();
    try std.testing.expectEqual(Rgb{ .r = 33, .g = 34, .b = 35 }, colors.palette[1]);
    try std.testing.expectEqual(Rgb{ .r = 49, .g = 50, .b = 51 }, colors.foreground);

    try std.testing.expect((try terminal.feed("\x1b]104\x07")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b]104\x07")).state_changed);
}

test "OSC color set and query failure rolls back the complete command" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 2, 4);
    defer terminal.deinit();

    const fill = try allocator.alloc(u8, HostState.pending_output_max_bytes - 1);
    defer allocator.free(fill);
    @memset(fill, 'x');
    try terminal.host.appendPendingOutput(fill);
    const before = terminal.host.terminalColorState();

    try std.testing.expectError(
        error.ConsequenceLimit,
        terminal.feed("\x1b]4;1;#010203;2;?\x1b\\"),
    );
    try std.testing.expectEqual(before, terminal.host.terminalColorState());
    try std.testing.expectEqual(fill.len, terminal.host.pendingOutput().len);
    try std.testing.expectEqual(@as(u8, 'x'), terminal.host.pendingOutput()[fill.len - 1]);

    try std.testing.expectError(error.ConsequenceLimit, terminal.feed("\x1b]12;#010203;?\x1b\\"));
    try std.testing.expectEqual(@as(?Rgb, null), terminal.screen_state.primary.cursor.cursor_color);
    try std.testing.expectEqual(@as(?Rgb, null), terminal.screen_state.alternate.cursor.cursor_color);
    try std.testing.expectEqual(fill.len, terminal.host.pendingOutput().len);
}

test "kitty color stack restores terminal color snapshots" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]21;foreground=#010203;1=#040506\x1b\\\x1b]30001\x1b\\");
    try stream.nextSlice("\x1b]21;foreground=#aabbcc;1=#ddeeff\x1b\\\x1b]30101\x1b\\");

    try std.testing.expectEqual(@as(u8, 0), terminal.kitty.color_stack.len);
    try std.testing.expectEqual(Rgb{ .r = 1, .g = 2, .b = 3 }, terminal.host.terminalColorState().foreground);
    try std.testing.expectEqual(Rgb{ .r = 4, .g = 5, .b = 6 }, terminal.host.terminalColorState().palette[1]);
}

test "kitty tui CSI save and restore colors use the same stack" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]21;foreground=#010203;1=#040506\x1b\\\x1b[#P");
    try stream.nextSlice("\x1b]21;foreground=#aabbcc;1=#ddeeff\x1b\\\x1b[#Q");

    try std.testing.expectEqual(@as(u8, 0), terminal.kitty.color_stack.len);
    try std.testing.expectEqual(Rgb{ .r = 1, .g = 2, .b = 3 }, terminal.host.terminalColorState().foreground);
    try std.testing.expectEqual(Rgb{ .r = 4, .g = 5, .b = 6 }, terminal.host.terminalColorState().palette[1]);
}

test "kitty color stack owns indexed sequential bounded and report semantics" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expect((try terminal.feed("\x1b]21;foreground=#010203\x1b\\\x1b[3")).state_changed);
    try std.testing.expect((try terminal.feed("#P")).state_changed);
    try std.testing.expectEqual(@as(u8, 0), terminal.kitty.color_stack.len);
    try std.testing.expectEqual(@as(u8, 3), terminal.kitty.color_stack.slot_count);
    try std.testing.expect(!(try terminal.feed("\x1b[3#P")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b[3#Q")).state_changed);

    try std.testing.expect((try terminal.feed("\x1b]21;foreground=#111213\x1b\\\x1b[1#Q")).state_changed);
    try std.testing.expectEqual(Rgb{ .r = 220, .g = 220, .b = 220 }, terminal.host.terminalColorState().foreground);
    try std.testing.expect((try terminal.feed("\x1b[3#Q")).state_changed);
    try std.testing.expectEqual(Rgb{ .r = 1, .g = 2, .b = 3 }, terminal.host.terminalColorState().foreground);
    try std.testing.expectEqual(@as(u8, 0), terminal.kitty.color_stack.len);

    try std.testing.expect((try terminal.feed("\x1b]21;foreground=#212223\x1b\\\x1b[#P")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b]21;foreground=#313233\x1b\\\x1b[#P")).state_changed);
    try std.testing.expect((try terminal.feed("\x1b]21;foreground=#414243\x1b\\")).state_changed);
    terminal.host.clearPendingOutput();
    try std.testing.expect((try terminal.feed("\x1b G\x1b[#R")).state_changed);
    try std.testing.expectEqualStrings("\x1b[1;2#Q", terminal.host.pendingOutput());

    try std.testing.expect((try terminal.feed("\x1b[3#Q\x1b[#Q")).state_changed);
    try std.testing.expectEqual(Rgb{ .r = 49, .g = 50, .b = 51 }, terminal.host.terminalColorState().foreground);
    try std.testing.expectEqual(@as(u8, 1), terminal.kitty.color_stack.len);

    const rejected = try terminal.feed("\x1b[11#P\x1b[11#Q");
    try std.testing.expect(!rejected.state_changed);
    try std.testing.expectEqual(@as(u8, 1), terminal.kitty.color_stack.len);

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
    try std.testing.expectEqual(@as(u8, 10), terminal.kitty.color_stack.len);
    try std.testing.expectEqual(@as(u8, 10), terminal.kitty.color_stack.slot_count);

    try std.testing.expect((try terminal.feed(
        "\x1b]30101\x1b\\\x1b]30101\x1b\\\x1b]30101\x1b\\\x1b]30101\x1b\\\x1b]30101\x1b\\" ++
            "\x1b]30101\x1b\\\x1b]30101\x1b\\\x1b]30101\x1b\\\x1b]30101\x1b\\\x1b]30101\x1b\\",
    )).state_changed);
    try std.testing.expectEqual(Rgb{ .r = 0, .g = 0, .b = 2 }, terminal.host.terminalColorState().foreground);

    terminal.host.clearPendingOutput();
    try std.testing.expect((try terminal.feed("\x1bc\x1b[#R")).state_changed);
    try std.testing.expectEqualStrings("\x1b[0;0#Q", terminal.host.pendingOutput());

    terminal.host.clearPendingOutput();
    const fill = try allocator.alloc(u8, HostState.pending_output_max_bytes - 1);
    defer allocator.free(fill);
    @memset(fill, 'x');
    try terminal.host.appendPendingOutput(fill);
    try std.testing.expectError(error.ConsequenceLimit, terminal.feed("\x1b[#R"));
    try std.testing.expectEqual(fill.len, terminal.host.pendingOutput().len);
    try std.testing.expectEqual(@as(u8, 'x'), terminal.host.pendingOutput()[fill.len - 1]);
}
