const std = @import("std");
const owned_actions = @import("../../../src/parser.zig");
const parser_mod = @import("../../../src/parser.zig");
const string_control = @import("../../../src/parser.zig");

const Parser = parser_mod.Parser;
const OscTerminator = parser_mod.OscTerminator;
const OscAction = parser_mod.OscAction;
const Action = parser_mod.Action;
const OscControl = string_control.OscControl;

const Output = struct {
    arena: std.heap.ArenaAllocator,
    actions: std.ArrayList(Action),

    fn init(allocator: std.mem.Allocator) !Output {
        return .{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .actions = try std.ArrayList(Action).initCapacity(allocator, 8),
        };
    }

    fn deinit(self: *Output, allocator: std.mem.Allocator) void {
        self.actions.deinit(allocator);
        self.arena.deinit();
    }

    fn appendPhases(self: *Output, phases: parser_mod.PhaseActions) void {
        owned_actions.appendOwnedPhases(std.testing.allocator, self.arena.allocator(), &self.actions, phases) catch unreachable;
    }
};

fn expectActionCount(actions: []const Action, count: usize) !void {
    try std.testing.expectEqual(count, actions.len);
}

test "parser string controls: OSC with BEL terminator" {
    const gpa = std.testing.allocator;
    var parser = try Parser.init(gpa);
    defer parser.deinit();
    var output = try Output.init(gpa);
    defer output.deinit(gpa);

    for ("\x1b]title\x07") |byte| output.appendPhases(parser.next(byte));
    try expectActionCount(output.actions.items, 1);
    try std.testing.expect(output.actions.items[0] == .osc_dispatch);
    try std.testing.expectEqual(OscTerminator.bel, output.actions.items[0].osc_dispatch.term());
    try std.testing.expectEqual(std.meta.Tag(OscAction).raw_title, std.meta.activeTag(output.actions.items[0].osc_dispatch));
    try std.testing.expectEqual(@as(?u16, null), output.actions.items[0].osc_dispatch.command());
    try std.testing.expectEqualSlices(u8, "title", output.actions.items[0].osc_dispatch.payload());
}

test "parser string controls: OSC with ST terminator" {
    const gpa = std.testing.allocator;
    var parser = try Parser.init(gpa);
    defer parser.deinit();
    var output = try Output.init(gpa);
    defer output.deinit(gpa);

    for ("\x1b]url\x1b\\") |byte| output.appendPhases(parser.next(byte));
    try expectActionCount(output.actions.items, 1);
    try std.testing.expect(output.actions.items[0] == .osc_dispatch);
    try std.testing.expectEqual(OscTerminator.st, output.actions.items[0].osc_dispatch.term());
    try std.testing.expectEqual(std.meta.Tag(OscAction).raw_title, std.meta.activeTag(output.actions.items[0].osc_dispatch));
    try std.testing.expectEqual(@as(?u16, null), output.actions.items[0].osc_dispatch.command());
    try std.testing.expectEqualSlices(u8, "url", output.actions.items[0].osc_dispatch.payload());
}

test "parser string controls: APC with ST terminator" {
    const gpa = std.testing.allocator;
    var parser = try Parser.init(gpa);
    defer parser.deinit();
    var output = try Output.init(gpa);
    defer output.deinit(gpa);

    for ("\x1b_kitty\x1b\\") |byte| output.appendPhases(parser.next(byte));
    try expectActionCount(output.actions.items, 7);
    try std.testing.expect(output.actions.items[0] == .apc_start);
    try std.testing.expectEqual(@as(u8, 'k'), output.actions.items[1].apc_put);
    try std.testing.expectEqual(@as(u8, 'i'), output.actions.items[2].apc_put);
    try std.testing.expectEqual(@as(u8, 't'), output.actions.items[3].apc_put);
    try std.testing.expectEqual(@as(u8, 't'), output.actions.items[4].apc_put);
    try std.testing.expectEqual(@as(u8, 'y'), output.actions.items[5].apc_put);
    try std.testing.expect(output.actions.items[6] == .apc_end);
}

test "parser string controls: DCS hook metadata and payload with ST terminator" {
    const gpa = std.testing.allocator;
    var parser = try Parser.init(gpa);
    defer parser.deinit();
    var output = try Output.init(gpa);
    defer output.deinit(gpa);

    for ("\x1bP1$qdata\x1b\\") |byte| output.appendPhases(parser.next(byte));
    try expectActionCount(output.actions.items, 6);
    try std.testing.expect(output.actions.items[0] == .dcs_hook);
    try std.testing.expectEqual(@as(u8, 'q'), output.actions.items[0].dcs_hook.final);
    try std.testing.expectEqual(@as(u8, 1), output.actions.items[0].dcs_hook.count);
    try std.testing.expectEqual(@as(i32, 1), output.actions.items[0].dcs_hook.params[0]);
    try std.testing.expectEqual(@as(u8, 1), output.actions.items[0].dcs_hook.intermediates_len);
    try std.testing.expectEqual(@as(u8, '$'), output.actions.items[0].dcs_hook.intermediates[0]);
    try std.testing.expectEqual(@as(u8, 'd'), output.actions.items[1].dcs_put);
    try std.testing.expectEqual(@as(u8, 'a'), output.actions.items[2].dcs_put);
    try std.testing.expectEqual(@as(u8, 't'), output.actions.items[3].dcs_put);
    try std.testing.expectEqual(@as(u8, 'a'), output.actions.items[4].dcs_put);
    try std.testing.expect(output.actions.items[5] == .dcs_unhook);
}

test "parser string controls: PM with ST terminator" {
    const gpa = std.testing.allocator;
    var parser = try Parser.init(gpa);
    defer parser.deinit();
    var output = try Output.init(gpa);
    defer output.deinit(gpa);

    for ("\x1b^ignored\x1b\\") |byte| output.appendPhases(parser.next(byte));
    try expectActionCount(output.actions.items, 9);
    try std.testing.expect(output.actions.items[0] == .pm_start);
    try std.testing.expectEqual(@as(u8, 'i'), output.actions.items[1].pm_put);
    try std.testing.expectEqual(@as(u8, 'g'), output.actions.items[2].pm_put);
    try std.testing.expectEqual(@as(u8, 'n'), output.actions.items[3].pm_put);
    try std.testing.expectEqual(@as(u8, 'o'), output.actions.items[4].pm_put);
    try std.testing.expectEqual(@as(u8, 'r'), output.actions.items[5].pm_put);
    try std.testing.expectEqual(@as(u8, 'e'), output.actions.items[6].pm_put);
    try std.testing.expectEqual(@as(u8, 'd'), output.actions.items[7].pm_put);
    try std.testing.expect(output.actions.items[8] == .pm_end);
}

test "parser string controls: SOS forms remain distinct and terminate" {
    const gpa = std.testing.allocator;
    var parser = try Parser.init(gpa);
    defer parser.deinit();
    var output = try Output.init(gpa);
    defer output.deinit(gpa);

    for ("\x1bXs\x1b\\") |byte| output.appendPhases(parser.next(byte));
    try expectActionCount(output.actions.items, 3);
    try std.testing.expect(output.actions.items[0] == .sos_start);
    try std.testing.expectEqual(@as(u8, 's'), output.actions.items[1].sos_put);
    try std.testing.expect(output.actions.items[2] == .sos_end);

    output.actions.clearRetainingCapacity();
    for ("\x1bPq\x98t\x9c") |byte| output.appendPhases(parser.next(byte));
    try expectActionCount(output.actions.items, 5);
    try std.testing.expect(output.actions.items[0] == .dcs_hook);
    try std.testing.expect(output.actions.items[1] == .dcs_unhook);
    try std.testing.expect(output.actions.items[2] == .sos_start);
    try std.testing.expectEqual(@as(u8, 't'), output.actions.items[3].sos_put);
    try std.testing.expect(output.actions.items[4] == .sos_end);
}

test "parser string controls: stray ESC in OSC appends byte to payload" {
    const gpa = std.testing.allocator;
    var parser = try Parser.init(gpa);
    defer parser.deinit();
    var output = try Output.init(gpa);
    defer output.deinit(gpa);

    for ("\x1b]ab\x1bcd\x1b\\") |byte| output.appendPhases(parser.next(byte));
    try expectActionCount(output.actions.items, 1);
    try std.testing.expect(output.actions.items[0] == .osc_dispatch);
    try std.testing.expectEqualSlices(u8, "abcd", output.actions.items[0].osc_dispatch.payload());
}

test "parser string controls: OSC invalid command with separator stays raw other payload" {
    const gpa = std.testing.allocator;
    var parser = try Parser.init(gpa);
    defer parser.deinit();
    var output = try Output.init(gpa);
    defer output.deinit(gpa);

    for ("\x1b]foo;bar\x07") |byte| output.appendPhases(parser.next(byte));
    try expectActionCount(output.actions.items, 1);
    try std.testing.expect(output.actions.items[0] == .osc_dispatch);
    try std.testing.expectEqual(std.meta.Tag(OscAction).raw_other, std.meta.activeTag(output.actions.items[0].osc_dispatch));
    try std.testing.expectEqual(@as(?u16, null), output.actions.items[0].osc_dispatch.command());
    try std.testing.expectEqualSlices(u8, "foo;bar", output.actions.items[0].osc_dispatch.payload());
}

test "parser string controls: OSC invalid numeric prefix without separator stays raw title payload" {
    const gpa = std.testing.allocator;
    var parser = try Parser.init(gpa);
    defer parser.deinit();
    var output = try Output.init(gpa);
    defer output.deinit(gpa);

    for ("\x1b]12x\x07") |byte| output.appendPhases(parser.next(byte));
    try expectActionCount(output.actions.items, 1);
    try std.testing.expect(output.actions.items[0] == .osc_dispatch);
    try std.testing.expectEqual(std.meta.Tag(OscAction).raw_title, std.meta.activeTag(output.actions.items[0].osc_dispatch));
    try std.testing.expectEqual(@as(?u16, null), output.actions.items[0].osc_dispatch.command());
    try std.testing.expectEqualSlices(u8, "12x", output.actions.items[0].osc_dispatch.payload());
}

test "parser string controls: OSC overlong numeric prefix stays raw payload" {
    const gpa = std.testing.allocator;
    var parser = try Parser.init(gpa);
    defer parser.deinit();
    var output = try Output.init(gpa);
    defer output.deinit(gpa);

    for ("\x1b]999999999;abc\x07") |byte| output.appendPhases(parser.next(byte));
    try expectActionCount(output.actions.items, 1);
    try std.testing.expect(output.actions.items[0] == .osc_dispatch);
    try std.testing.expectEqual(std.meta.Tag(OscAction).raw_other, std.meta.activeTag(output.actions.items[0].osc_dispatch));
    try std.testing.expectEqual(@as(?u16, null), output.actions.items[0].osc_dispatch.command());
    try std.testing.expectEqualSlices(u8, "999999999;abc", output.actions.items[0].osc_dispatch.payload());
}

test "parser string controls: explicit OSC ladder recognizes full command list" {
    const gpa = std.testing.allocator;
    const cases = [_]struct {
        seq: []const u8,
        command: ?u16,
    }{
        .{ .seq = "\x1b]0;title\x07", .command = 0 },
        .{ .seq = "\x1b]1;icon\x07", .command = 1 },
        .{ .seq = "\x1b]2;title\x07", .command = 2 },
        .{ .seq = "\x1b]4;1;#ff0000\x1b\\", .command = 4 },
        .{ .seq = "\x1b]5;0;#ff0000\x1b\\", .command = 5 },
        .{ .seq = "\x1b]7;file:///tmp\x1b\\", .command = 7 },
        .{ .seq = "\x1b]8;;https://example.com\x07", .command = 8 },
        .{ .seq = "\x1b]9;i=1:p=body;Hi\x1b\\", .command = 9 },
        .{ .seq = "\x1b]10;#010203\x1b\\", .command = 10 },
        .{ .seq = "\x1b]11;#010203\x1b\\", .command = 11 },
        .{ .seq = "\x1b]12;#010203\x1b\\", .command = 12 },
        .{ .seq = "\x1b]13;#010203\x1b\\", .command = 13 },
        .{ .seq = "\x1b]14;#010203\x1b\\", .command = 14 },
        .{ .seq = "\x1b]15;#010203\x1b\\", .command = 15 },
        .{ .seq = "\x1b]16;#010203\x1b\\", .command = 16 },
        .{ .seq = "\x1b]17;#010203\x1b\\", .command = 17 },
        .{ .seq = "\x1b]18;#010203\x1b\\", .command = 18 },
        .{ .seq = "\x1b]19;#010203\x1b\\", .command = 19 },
        .{ .seq = "\x1b]21;foreground=?\x1b\\", .command = 21 },
        .{ .seq = "\x1b]22;pointer\x1b\\", .command = 22 },
        .{ .seq = "\x1b]50;CursorShape=1\x07", .command = 50 },
        .{ .seq = "\x1b]52;c;AAAA\x1b\\", .command = 52 },
        .{ .seq = "\x1b]66;s=2;Hi\x1b\\", .command = 66 },
        .{ .seq = "\x1b]99;i=1:p=body;Hello\x1b\\", .command = 99 },
        .{ .seq = "\x1b]104;1\x1b\\", .command = 104 },
        .{ .seq = "\x1b]110\x1b\\", .command = 110 },
        .{ .seq = "\x1b]111\x1b\\", .command = 111 },
        .{ .seq = "\x1b]112\x1b\\", .command = 112 },
        .{ .seq = "\x1b]113\x1b\\", .command = 113 },
        .{ .seq = "\x1b]114\x1b\\", .command = 114 },
        .{ .seq = "\x1b]115\x1b\\", .command = 115 },
        .{ .seq = "\x1b]116\x1b\\", .command = 116 },
        .{ .seq = "\x1b]117\x1b\\", .command = 117 },
        .{ .seq = "\x1b]118\x1b\\", .command = 118 },
        .{ .seq = "\x1b]119\x1b\\", .command = 119 },
        .{ .seq = "\x1b]133;D;7\x07", .command = 133 },
        .{ .seq = "\x1b]777;notify;body\x1b\\", .command = 777 },
        .{ .seq = "\x1b]1337;File=name=test;AAAA\x1b\\", .command = 1337 },
        .{ .seq = "\x1b]3008;mark\x1b\\", .command = 3008 },
        .{ .seq = "\x1b]30001\x1b\\", .command = 30001 },
        .{ .seq = "\x1b]30101\x1b\\", .command = 30101 },
        .{ .seq = "\x1b]5113;cmd=data;AAAA\x1b\\", .command = 5113 },
        .{ .seq = "\x1b]5522;type=write;AAAA\x1b\\", .command = 5522 },
    };

    for (cases) |case| {
        var parser = try Parser.init(gpa);
        defer parser.deinit();
        var output = try Output.init(gpa);
        defer output.deinit(gpa);

        for (case.seq) |byte| output.appendPhases(parser.next(byte));
        try expectActionCount(output.actions.items, 1);
        try std.testing.expect(output.actions.items[0] == .osc_dispatch);
        try std.testing.expectEqual(case.command, output.actions.items[0].osc_dispatch.command());
    }
}

fn putOscBytes(osc: *OscControl, bytes: []const u8) !void {
    for (bytes) |byte| {
        const result = osc.feed(byte) orelse return error.MissingFeedResult;
        try std.testing.expect(result == .put);
    }
}

fn finishOscBel(osc: *OscControl) !void {
    const result = osc.feed(0x07) orelse return error.MissingFeedResult;
    try std.testing.expectEqual(string_control.Finish.bel, result.finish);
}

test "osc control: title payload keeps metadata limit" {
    var osc = try OscControl.init(std.testing.allocator, 16, 4, 32, 8);
    defer osc.deinit();
    osc.start();
    try putOscBytes(&osc, "0;hello");
    try finishOscBel(&osc);
    const snapshot = osc.snapshot(.bel);
    try std.testing.expectEqual(@as(?u16, 0), snapshot.command());
    try std.testing.expectEqual(std.meta.Tag(parser_mod.OscAction).title, std.meta.activeTag(snapshot));
    try std.testing.expectEqualStrings("hell", snapshot.payload());
    try std.testing.expectEqual(error.StringControlLimit, osc.takeFailure().?);
}

test "osc control: clipboard payload uses large limit" {
    var osc = try OscControl.init(std.testing.allocator, 16, 4, 32, 8);
    defer osc.deinit();
    osc.start();
    try putOscBytes(&osc, "52;c;abcdefgh");
    try finishOscBel(&osc);
    const snapshot = osc.snapshot(.bel);
    try std.testing.expectEqual(@as(?u16, 52), snapshot.command());
    try std.testing.expectEqual(std.meta.Tag(parser_mod.OscAction).clipboard, std.meta.activeTag(snapshot));
    try std.testing.expectEqualStrings("c;abcdefgh", snapshot.payload());
    try std.testing.expectEqual(@as(?(error{ OutOfMemory, StringControlLimit }), null), osc.takeFailure());
}

test "osc control: clipboard boundary rejects and resets exactly" {
    var osc = try OscControl.init(std.testing.allocator, 16, 4, 4, 4);
    defer osc.deinit();

    const cases = [_]struct {
        body: []const u8,
        payload: []const u8,
        exceeds_limit: bool,
    }{
        .{ .body = "52;abc", .payload = "abc", .exceeds_limit = false },
        .{ .body = "52;abcd", .payload = "abcd", .exceeds_limit = false },
        .{ .body = "52;abcde", .payload = "abcd", .exceeds_limit = true },
        .{ .body = "52;z", .payload = "z", .exceeds_limit = false },
    };

    for (cases) |case| {
        osc.start();
        try putOscBytes(&osc, case.body);
        try finishOscBel(&osc);
        const snapshot = osc.snapshot(.bel);
        try std.testing.expectEqualStrings(case.payload, snapshot.payload());
        if (case.exceeds_limit) {
            try std.testing.expectEqual(error.StringControlLimit, osc.takeFailure().?);
        } else {
            try std.testing.expectEqual(
                @as(?(error{ OutOfMemory, StringControlLimit }), null),
                osc.takeFailure(),
            );
        }
    }
}

test "osc control: chunked protocol boundary rejects and resets exactly" {
    var osc = try OscControl.init(std.testing.allocator, 16, 4, 32, 4);
    defer osc.deinit();

    const cases = [_]struct {
        body: []const u8,
        payload: []const u8,
        exceeds_limit: bool,
    }{
        .{ .body = "5113;abc", .payload = "abc", .exceeds_limit = false },
        .{ .body = "5113;abcd", .payload = "abcd", .exceeds_limit = false },
        .{ .body = "5113;abcde", .payload = "abcd", .exceeds_limit = true },
        .{ .body = "5522;z", .payload = "z", .exceeds_limit = false },
    };

    for (cases) |case| {
        osc.start();
        try putOscBytes(&osc, case.body);
        try finishOscBel(&osc);
        const snapshot = osc.snapshot(.bel);
        try std.testing.expectEqualStrings(case.payload, snapshot.payload());
        if (case.exceeds_limit) {
            try std.testing.expectEqual(error.StringControlLimit, osc.takeFailure().?);
        } else {
            try std.testing.expectEqual(
                @as(?(error{ OutOfMemory, StringControlLimit }), null),
                osc.takeFailure(),
            );
        }
    }
}
