const std = @import("std");
const host_state = @import("../../src/terminal.zig");
const terminal_mod = @import("../../src/terminal.zig");
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

test "OSC 0 1 and 2 match libvterm title and icon properties" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();

    const both = try terminal.feed("\x1b]0;Both\x07");
    try std.testing.expect(both.state_changed);
    try std.testing.expect(both.title_changed);
    try std.testing.expect(both.icon_changed);
    var publication = terminal.surfaceSnapshot();
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

    publication = terminal.surfaceSnapshot();
    try std.testing.expectEqualStrings("Title", publication.title.?);
    try std.testing.expectEqualStrings("Icon", publication.icon.?);
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
    const publication = terminal.surfaceSnapshot();
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
    const publication = terminal.surfaceSnapshot();
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
        const publication = terminal.surfaceSnapshot();
        try std.testing.expectEqualStrings("old-title", publication.title.?);
        try std.testing.expectEqualStrings("old-icon", publication.icon.?);
        return err;
    };
    try std.testing.expect(summary.title_changed);
    try std.testing.expect(summary.icon_changed);
    const publication = terminal.surfaceSnapshot();
    try std.testing.expectEqualStrings("both", publication.title.?);
    try std.testing.expectEqualStrings("both", publication.icon.?);
}

test "OSC 8 assigns link ids and preserves URI lookup" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]8;;https://example.com\x07abc\x1b]8;;\x07z");

    const screen = terminal.screen_state.activeConst();
    const first = screen.cellInfoAt(0, 0).attrs.link_id;
    const second = screen.cellInfoAt(0, 1).attrs.link_id;
    const third = screen.cellInfoAt(0, 2).attrs.link_id;
    const trailing = screen.cellInfoAt(0, 3).attrs.link_id;
    try std.testing.expect(first != 0);
    try std.testing.expectEqual(first, second);
    try std.testing.expectEqual(first, third);
    try std.testing.expectEqual(@as(u32, 0), trailing);
    try std.testing.expectEqualStrings("https://example.com", terminal.host.hyperlinkUriForId(first).?);
}

test "OSC 52 produces pending clipboard request" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]52;c;Zm9v\x07");
    try std.testing.expectEqualStrings("c;Zm9v", terminal.host.pendingClipboardSet().?);
    terminal.host.clearPendingClipboardSet();
    try std.testing.expectEqual(@as(?[]const u8, null), terminal.host.pendingClipboardSet());
}

test "OSC 52 decoded clipboard drain clears pending request" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]52;c;SG93bA==\x07");

    const text = (try terminal.host.drainPendingClipboardSet(allocator)).?;
    defer allocator.free(text);
    try std.testing.expectEqualStrings("Howl", text);
    try std.testing.expectEqual(@as(?[]const u8, null), terminal.host.pendingClipboardSet());
}

test "OSC 52 query clipboard drain clears without request" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]52;c;?\x07");

    try std.testing.expectEqual(@as(?[]u8, null), try terminal.host.drainPendingClipboardSet(allocator));
    try std.testing.expectEqual(@as(?[]const u8, null), terminal.host.pendingClipboardSet());
}

test "shell integration OSC 133 records latest mark" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.init(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);

    try stream.nextSlice("\x1b]133;C;cmdline=ls\x07\x1b]133;D;2\x07");

    const mark = terminal.surfaceSnapshot().shell_mark;
    try std.testing.expectEqual(@as(u64, 2), mark.generation);
    try std.testing.expectEqual(@as(u8, 'D'), mark.kind);
    try std.testing.expectEqual(@as(?i32, 2), mark.status);
    try std.testing.expectEqualStrings("2", mark.metadata);

    try stream.nextSlice("\x1b]133;Z;ignored\x07");
    try std.testing.expectEqual(@as(u64, 2), terminal.surfaceSnapshot().shell_mark.generation);
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
    const publication = terminal.surfaceSnapshot();
    try std.testing.expectEqual(Screen.CursorShape.bar, publication.snapshot.view.cursor_shape);
    try std.testing.expectEqual(@as(u32, 20), publication.shell_integration.?.version);
    try std.testing.expectEqualStrings("bash", publication.shell_integration.?.shell.?);
    try std.testing.expectEqual(Rgb{ .r = 0xaa, .g = 0xbb, .b = 0xcc }, publication.presentation.foreground);
    try std.testing.expectEqual(Rgb{ .r = 0x10, .g = 0x20, .b = 0x30 }, publication.presentation.background);
    try std.testing.expectEqual(Rgb{ .r = 0xff, .g = 0, .b = 0 }, publication.presentation.palette[1]);
    try std.testing.expectEqual(Rgb{ .r = 1, .g = 2, .b = 3 }, publication.presentation.cursor.?);
    try std.testing.expectEqual(Rgb{ .r = 4, .g = 5, .b = 6 }, publication.presentation.cursor_text.?);
    try std.testing.expectEqual(Rgb{ .r = 0xee, .g = 0xee, .b = 0xee }, publication.presentation.palette[15]);
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
        terminal.surfaceSnapshot().snapshot.view.cursor_shape,
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
    const publication = terminal.surfaceSnapshot();
    try std.testing.expectEqual(
        Rgb{ .r = 0x11, .g = 0x22, .b = 0x33 },
        publication.presentation.foreground,
    );
    try std.testing.expectEqual(@as(u32, 20), publication.shell_integration.?.version);
    try std.testing.expectEqualStrings("bash", publication.shell_integration.?.shell.?);
    try std.testing.expectEqual(@as(usize, 0), terminal.host.pendingOutput().len);

    const accepted = try terminal.feed("\x1b]50;CursorShape=1\x07");
    try std.testing.expect(accepted.state_changed);
    try std.testing.expectEqual(
        Screen.CursorShape.bar,
        terminal.surfaceSnapshot().snapshot.view.cursor_shape,
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
    try state.replaceShellIntegration(.{ .version = 19, .shell = "bash" });
    try std.testing.expectError(
        error.OutOfMemory,
        state.replaceShellIntegration(.{ .version = 20, .shell = "zsh" }),
    );
    try std.testing.expectEqual(@as(u32, 19), state.shell_integration.?.version);
    try std.testing.expectEqualStrings("bash", state.shell_integration.?.shell.?);
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
        const integration = terminal.surfaceSnapshot().shell_integration.?;
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
    const presentation = terminal.surfaceSnapshot().presentation;
    try std.testing.expectEqual(Terminal.default_presentation.foreground, presentation.foreground);
    try std.testing.expectEqual(Rgb{ .r = 0x66, .g = 0x66, .b = 0x66 }, presentation.background);
    try std.testing.expectEqual(@as(?Rgb, null), presentation.cursor);
    try std.testing.expectEqual(@as(?Rgb, null), presentation.cursor_text);
    try std.testing.expectEqual(Terminal.default_presentation.palette[1], presentation.palette[1]);
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
        "\x1b]21;foreground=rgb:11/22/33\x1b\\" ++
            "\x1b]21;background=rgb:44/55/66\x1b\\" ++
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
    try std.testing.expectEqualStrings("\x1b]4;1;rgb:01/02/03\x1b\\\x1b]10;rgb:aa/bb/cc\x1b\\\x1b]11;rgb:0d/0e/0f\x1b\\\x1b]12;rgb:ff/00/00\x1b\\", terminal.host.pendingOutput());

    try stream.nextSlice("\x1b]104;1\x1b\\\x1b]110\x1b\\\x1b]111\x1b\\\x1b]112\x1b\\");
    try std.testing.expectEqual(Rgb{ .r = 205, .g = 49, .b = 49 }, terminal.host.terminalColorState().palette[1]);
    try std.testing.expectEqual(Rgb{ .r = 220, .g = 220, .b = 220 }, terminal.host.terminalColorState().foreground);
    try std.testing.expectEqual(Rgb{ .r = 24, .g = 25, .b = 33 }, terminal.host.terminalColorState().background);
    try std.testing.expectEqual(@as(?Rgb, null), terminal.host.terminalColorState().cursor);
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
        "\x1b]13;rgb:01/02/03\x1b\\" ++
            "\x1b]14;rgb:04/05/06\x1b\\" ++
            "\x1b]15;rgb:07/08/09\x1b\\" ++
            "\x1b]16;rgb:0a/0b/0c\x1b\\" ++
            "\x1b]17;rgb:0d/0e/0f\x1b\\" ++
            "\x1b]18;rgb:10/11/12\x1b\\" ++
            "\x1b]19;rgb:13/14/15\x1b\\",
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
        "\x1b]5;0;rgb:01/02/03\x1b\\" ++
            "\x1b]5;1;rgb:04/05/06\x1b\\" ++
            "\x1b]4;258;rgb:07/08/09\x1b\\" ++
            "\x1b]4;260;rgb:0a/0b/0c\x1b\\",
        terminal.host.pendingOutput(),
    );

    terminal.host.clearPendingOutput();
    try stream.nextSlice("\x1b]104;258;260\x1b\\");
    const reset = terminal.host.terminalColorState();
    try std.testing.expectEqual(@as(?Rgb, null), reset.special_palette[2]);
    try std.testing.expectEqual(@as(?Rgb, null), reset.special_palette[4]);
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
