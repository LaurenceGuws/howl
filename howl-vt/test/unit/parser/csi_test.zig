const std = @import("std");
const owned_actions = @import("../../../src/parser_owned_actions.zig");
const parser_mod = @import("../../../src/parser.zig");

const CsiAction = parser_mod.CsiAction;
const OwnedCsiAction = struct {
    final: u8,
    params: [parser_mod.max_params]i32,
    separators: parser_mod.CsiSeparatorList,
    count: u8,
    leader: u8,
    private: bool,
    intermediates: [parser_mod.max_intermediates]u8,
    intermediates_len: u8,
};

fn feedCsiBytes(bytes: []const u8) !OwnedCsiAction {
    const gpa = std.testing.allocator;
    var parser = try parser_mod.Parser.init(gpa);
    defer parser.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var actions = try std.ArrayList(parser_mod.Action).initCapacity(gpa, 8);
    defer actions.deinit(gpa);

    try owned_actions.appendOwnedPhases(gpa, arena.allocator(), &actions, parser.next(0x1b));
    try owned_actions.appendOwnedPhases(gpa, arena.allocator(), &actions, parser.next('['));
    for (bytes) |byte| {
        try owned_actions.appendOwnedPhases(gpa, arena.allocator(), &actions, parser.next(byte));
    }

    for (actions.items) |action| {
        if (action == .csi_dispatch) return ownCsiAction(action.csi_dispatch);
    }
    return error.NoAction;
}

fn ownCsiAction(action: CsiAction) OwnedCsiAction {
    var params = [_]i32{0} ** parser_mod.max_params;
    std.mem.copyForwards(i32, params[0..action.count], action.params[0..action.count]);
    var intermediates = [_]u8{0} ** parser_mod.max_intermediates;
    std.mem.copyForwards(u8, intermediates[0..action.intermediates_len], action.intermediates[0..action.intermediates_len]);
    return .{
        .final = action.final,
        .params = params,
        .separators = action.separators,
        .count = action.count,
        .leader = action.leader,
        .private = action.private,
        .intermediates = intermediates,
        .intermediates_len = action.intermediates_len,
    };
}

test "CSI parser captures ansi DECRQM intermediate $" {
    const action = try feedCsiBytes("20$p");
    try std.testing.expectEqual(@as(u8, 'p'), action.final);
    try std.testing.expectEqual(@as(u8, 0), action.leader);
    try std.testing.expect(!action.private);
    try std.testing.expectEqual(@as(u8, 1), action.intermediates_len);
    try std.testing.expectEqual(@as(u8, '$'), action.intermediates[0]);
    try std.testing.expectEqual(@as(i32, 20), action.params[0]);
}

test "CSI parser captures dec private DECRQM intermediate $" {
    const action = try feedCsiBytes("?1004$p");
    try std.testing.expectEqual(@as(u8, 'p'), action.final);
    try std.testing.expectEqual(@as(u8, '?'), action.leader);
    try std.testing.expect(action.private);
    try std.testing.expectEqual(@as(u8, 1), action.intermediates_len);
    try std.testing.expectEqual(@as(u8, '$'), action.intermediates[0]);
    try std.testing.expectEqual(@as(i32, 1004), action.params[0]);
}

test "CSI parser captures DECSTR intermediate !" {
    const action = try feedCsiBytes("!p");
    try std.testing.expectEqual(@as(u8, 'p'), action.final);
    try std.testing.expectEqual(@as(u8, 0), action.leader);
    try std.testing.expect(!action.private);
    try std.testing.expectEqual(@as(u8, 1), action.intermediates_len);
    try std.testing.expectEqual(@as(u8, '!'), action.intermediates[0]);
}

test "CSI parser preserves multiple intermediate bytes in order" {
    const action = try feedCsiBytes("#!p");
    try std.testing.expectEqual(@as(u8, 'p'), action.final);
    try std.testing.expectEqual(@as(u8, 2), action.intermediates_len);
    try std.testing.expectEqual(@as(u8, '#'), action.intermediates[0]);
    try std.testing.expectEqual(@as(u8, '!'), action.intermediates[1]);
}

test "CSI parser: basic ANSI color sequence (31m = red)" {
    const action = try feedCsiBytes("31m");
    try std.testing.expectEqual(@as(u8, 'm'), action.final);
    try std.testing.expectEqual(@as(i32, 31), action.params[0]);
    try std.testing.expectEqual(@as(u8, 1), action.count);
}

test "CSI parser: multi-param sequence (1;31;40m)" {
    const action = try feedCsiBytes("1;31;40m");
    try std.testing.expectEqual(@as(u8, 'm'), action.final);
    try std.testing.expectEqual(@as(i32, 1), action.params[0]);
    try std.testing.expectEqual(@as(i32, 31), action.params[1]);
    try std.testing.expectEqual(@as(i32, 40), action.params[2]);
    try std.testing.expectEqual(@as(u8, 3), action.count);
}

test "CSI parser preserves colon subparameter separators" {
    const action = try feedCsiBytes("4:3m");
    try std.testing.expectEqual(@as(u8, 'm'), action.final);
    try std.testing.expectEqual(@as(u8, 2), action.count);
    try std.testing.expectEqual(@as(i32, 4), action.params[0]);
    try std.testing.expectEqual(@as(i32, 3), action.params[1]);
    try std.testing.expect(action.separators.isSet(0));
    try std.testing.expect(!action.separators.isSet(1));
}

test "CSI parser: empty params stay defaulted after reset" {
    _ = try feedCsiBytes("99m");
    const action = try feedCsiBytes(";H");
    try std.testing.expectEqual(@as(u8, 'H'), action.final);
    try std.testing.expectEqual(@as(u8, 1), action.count);
    try std.testing.expectEqual(@as(i32, 0), action.params[0]);
}

test "CSI parser: cursor position query (6n)" {
    const action = try feedCsiBytes("6n");
    try std.testing.expectEqual(@as(u8, 'n'), action.final);
}

test "CSI parser: private mode (?25h = show cursor)" {
    const action = try feedCsiBytes("?25h");
    try std.testing.expectEqual(@as(u8, 'h'), action.final);
    try std.testing.expect(action.private);
    try std.testing.expectEqual(@as(u8, '?'), action.leader);
    try std.testing.expectEqual(@as(i32, 25), action.params[0]);
}
