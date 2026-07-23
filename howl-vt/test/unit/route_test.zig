const std = @import("std");
const action_route = @import("../../src/terminal.zig");
const erase = @import("../../src/terminal.zig");
const semantic_event = @import("../../src/terminal.zig");
const parser_mod = @import("../../src/parser.zig");
const parsed_events = @import("../../src/parser.zig");

const Event = parsed_events.Event;
const EraseMode = erase.ScreenEraseMode;
const SemanticEvent = semantic_event.SemanticEvent;
const process = action_route.process;
const csi_max_params = parser_mod.max_params;
const empty_params = @as([csi_max_params]i32, @splat(0));
const empty_separators = parser_mod.CsiSeparatorList.empty;
const empty_intermediates = @as([parser_mod.max_intermediates]u8, @splat(0));

fn makeStyleChange(comptime final: u8, comptime p0: i32, comptime p1: i32, comptime count: u8) Event {
    const params = [_]i32{ p0, p1 } ++ @as([(csi_max_params - 2)]i32, @splat(0));
    return Event{ .style_change = .{
        .final = final,
        .params = params[0..],
        .separators = empty_separators,
        .param_count = count,
        .leader = 0,
        .private = false,
        .intermediates = empty_intermediates[0..],
        .intermediates_len = 0,
    } };
}

fn makeStyleChangeWithIntermediate(comptime final: u8, comptime intermediate: u8) Event {
    const params = @as([csi_max_params]i32, @splat(0));
    const intermediates = [_]u8{intermediate} ++ @as([(parser_mod.max_intermediates - 1)]u8, @splat(0));
    return Event{ .style_change = .{
        .final = final,
        .params = params[0..],
        .separators = empty_separators,
        .param_count = 0,
        .leader = 0,
        .private = false,
        .intermediates = intermediates[0..],
        .intermediates_len = 1,
    } };
}

fn makeStyleChangeWithParamAndIntermediate(comptime final: u8, comptime p0: i32, comptime intermediate: u8) Event {
    const params = [_]i32{p0} ++ @as([(csi_max_params - 1)]i32, @splat(0));
    const intermediates = [_]u8{intermediate} ++ @as([(parser_mod.max_intermediates - 1)]u8, @splat(0));
    return Event{ .style_change = .{
        .final = final,
        .params = params[0..],
        .separators = empty_separators,
        .param_count = 1,
        .leader = 0,
        .private = false,
        .intermediates = intermediates[0..],
        .intermediates_len = 1,
    } };
}

fn makePrivateStyleChange(comptime final: u8, comptime params_in: []const i32) Event {
    const params = comptime blk: {
        var out = @as([csi_max_params]i32, @splat(0));
        for (params_in, 0..) |value, idx| out[idx] = value;
        break :blk out;
    };
    return Event{ .style_change = .{
        .final = final,
        .params = params[0..],
        .separators = empty_separators,
        .param_count = @intCast(params_in.len),
        .leader = '?',
        .private = true,
        .intermediates = empty_intermediates[0..],
        .intermediates_len = 0,
    } };
}

fn makeEscFinal(final: u8) Event {
    return Event{ .esc_dispatch = .{
        .final = final,
        .intermediates = @as([4]u8, @splat(0)),
        .intermediates_len = 0,
    } };
}

fn expectDecModes(event: Event, enabled: bool, expected: []const u16) !void {
    const semantic = process(event) orelse return error.NoEvent;
    const modes = switch (semantic) {
        .dec_mode_set => |modes| if (enabled) modes else return error.UnexpectedEvent,
        .dec_mode_reset => |modes| if (!enabled) modes else return error.UnexpectedEvent,
        else => return error.UnexpectedEvent,
    };
    try std.testing.expectEqualSlices(u16, expected, modes.params[0..modes.param_count]);
}

test "actions: text event maps to write_text" {
    const sem = process(Event{ .text = "hello" }) orelse return error.NoEvent;
    try std.testing.expectEqualSlices(u8, "hello", sem.write_text);
}

test "actions: codepoint event maps to write_codepoint" {
    const sem = process(Event{ .codepoint = 0xE9 }) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u21, 0xE9), sem.write_codepoint);
}

test "actions: DEC private application cursor enable maps true" {
    var params = @as([csi_max_params]i32, @splat(0));
    params[0] = 1;
    const ev = Event{ .style_change = .{
        .final = 'h',
        .params = params[0..],
        .separators = empty_separators,
        .param_count = 1,
        .leader = '?',
        .private = true,
        .intermediates = empty_intermediates[0..],
        .intermediates_len = 0,
    } };
    try expectDecModes(ev, true, &.{1});
}

test "actions: DEC private focus reporting enable maps true" {
    var params = @as([csi_max_params]i32, @splat(0));
    params[0] = 1004;
    const ev = Event{ .style_change = .{
        .final = 'h',
        .params = params[0..],
        .separators = empty_separators,
        .param_count = 1,
        .leader = '?',
        .private = true,
        .intermediates = empty_intermediates[0..],
        .intermediates_len = 0,
    } };
    try expectDecModes(ev, true, &.{1004});
}

test "actions: DEC private bracketed paste disable maps false" {
    var params = @as([csi_max_params]i32, @splat(0));
    params[0] = 2004;
    const ev = Event{ .style_change = .{
        .final = 'l',
        .params = params[0..],
        .separators = empty_separators,
        .param_count = 1,
        .leader = '?',
        .private = true,
        .intermediates = empty_intermediates[0..],
        .intermediates_len = 0,
    } };
    try expectDecModes(ev, false, &.{2004});
}

test "actions: DEC private synchronized output maps enable disable" {
    try expectDecModes(makePrivateStyleChange('h', &.{2026}), true, &.{2026});
    try expectDecModes(makePrivateStyleChange('l', &.{2026}), false, &.{2026});
}

test "actions: DEC private mouse tracking mode mappings" {
    var params = @as([csi_max_params]i32, @splat(0));
    params[0] = 9;
    var ev = Event{ .style_change = .{
        .final = 'h',
        .params = params[0..],
        .separators = empty_separators,
        .param_count = 1,
        .leader = '?',
        .private = true,
        .intermediates = empty_intermediates[0..],
        .intermediates_len = 0,
    } };
    try expectDecModes(ev, true, &.{9});
    params[0] = 1000;
    ev.style_change.params = params[0..];
    try expectDecModes(ev, true, &.{1000});
    params[0] = 1002;
    ev.style_change.params = params[0..];
    try expectDecModes(ev, true, &.{1002});
    params[0] = 1003;
    ev.style_change.params = params[0..];
    try expectDecModes(ev, true, &.{1003});
    params[0] = 1006;
    ev.style_change.params = params[0..];
    try expectDecModes(ev, true, &.{1006});
    params[0] = 1005;
    ev.style_change.params = params[0..];
    try expectDecModes(ev, true, &.{1005});
    params[0] = 1015;
    ev.style_change.params = params[0..];
    try expectDecModes(ev, true, &.{1015});
}

test "actions: low priority DEC private modes and media copy map" {
    var params = @as([csi_max_params]i32, @splat(0));
    var ev = Event{ .style_change = .{
        .final = 'h',
        .params = params[0..],
        .separators = empty_separators,
        .param_count = 1,
        .leader = '?',
        .private = true,
        .intermediates = empty_intermediates[0..],
        .intermediates_len = 0,
    } };

    params[0] = 45;
    ev.style_change.params = params[0..];
    try expectDecModes(ev, true, &.{45});

    params[0] = 1045;
    ev.style_change.params = params[0..];
    try expectDecModes(ev, true, &.{1045});

    params[0] = 5;
    ev.style_change.final = 'i';
    ev.style_change.params = params[0..];
    try std.testing.expectEqualDeep(
        semantic_event.MediaCopyRequest{ .private = true, .parameter = 5 },
        process(ev).?.media_copy_request,
    );
}

test "actions: application keypad and modifyOtherKeys mappings" {
    try std.testing.expect(process(makeEscFinal('=')).?.application_keypad);
    try std.testing.expect(!process(makeEscFinal('>')).?.application_keypad);

    var params = @as([csi_max_params]i32, @splat(0));
    params[0] = 66;
    var ev = Event{ .style_change = .{
        .final = 'h',
        .params = params[0..],
        .separators = empty_separators,
        .param_count = 1,
        .leader = '?',
        .private = true,
        .intermediates = empty_intermediates[0..],
        .intermediates_len = 0,
    } };
    try expectDecModes(ev, true, &.{66});

    params[0] = 4;
    params[1] = 2;
    ev = Event{ .style_change = .{
        .final = 'm',
        .params = params[0..],
        .separators = empty_separators,
        .param_count = 2,
        .leader = '>',
        .private = false,
        .intermediates = empty_intermediates[0..],
        .intermediates_len = 0,
    } };
    try std.testing.expectEqual(@as(i8, 2), process(ev).?.modify_other_keys_set);

    ev.style_change.final = 'n';
    try std.testing.expect(process(ev).? == .modify_other_keys_disable);

    ev.style_change.final = 'm';
    ev.style_change.leader = '?';
    ev.style_change.private = true;
    ev.style_change.param_count = 1;
    try std.testing.expect(process(ev).? == .modify_other_keys_query);
}

test "actions: xterm key format set reset and query mappings" {
    var params = @as([csi_max_params]i32, @splat(0));
    params[0] = 4;
    params[1] = 1;
    var ev = Event{ .style_change = .{
        .final = 'f',
        .params = params[0..],
        .separators = empty_separators,
        .param_count = 2,
        .leader = '>',
        .private = false,
        .intermediates = empty_intermediates[0..],
        .intermediates_len = 0,
    } };

    var change = process(ev).?.key_format_change;
    try std.testing.expectEqual(@as(?u8, 4), change.resource);
    try std.testing.expectEqual(@as(?u16, 1), change.value);

    ev.style_change.param_count = 1;
    change = process(ev).?.key_format_change;
    try std.testing.expectEqual(@as(?u8, 4), change.resource);
    try std.testing.expectEqual(@as(?u16, null), change.value);

    ev.style_change.param_count = 0;
    change = process(ev).?.key_format_change;
    try std.testing.expectEqual(@as(?u8, null), change.resource);
    try std.testing.expectEqual(@as(?u16, null), change.value);

    ev.style_change.final = 'g';
    ev.style_change.param_count = 1;
    ev.style_change.leader = '?';
    ev.style_change.private = true;
    try std.testing.expectEqual(@as(u8, 4), process(ev).?.key_format_query);
}

test "actions: xterm key format resource saturates above 255" {
    var params = @as([csi_max_params]i32, @splat(0));
    params[0] = 300;
    const ev = Event{ .style_change = .{
        .final = 'f',
        .params = params[0..],
        .separators = empty_separators,
        .param_count = 1,
        .leader = '>',
        .private = false,
        .intermediates = empty_intermediates[0..],
        .intermediates_len = 0,
    } };

    try std.testing.expectEqual(@as(?u8, 255), process(ev).?.key_format_change.resource);
}

test "actions: xterm key format query saturates above 255" {
    var params = @as([csi_max_params]i32, @splat(0));
    params[0] = 300;
    const ev = Event{ .style_change = .{
        .final = 'g',
        .params = params[0..],
        .separators = empty_separators,
        .param_count = 1,
        .leader = '?',
        .private = true,
        .intermediates = empty_intermediates[0..],
        .intermediates_len = 0,
    } };

    try std.testing.expectEqual(@as(u8, 255), process(ev).?.key_format_query);
}

test "actions: xterm key format non-positive params normalize to 0" {
    var params = @as([csi_max_params]i32, @splat(0));
    params[0] = -7;
    var ev = Event{ .style_change = .{
        .final = 'f',
        .params = params[0..],
        .separators = empty_separators,
        .param_count = 1,
        .leader = '>',
        .private = false,
        .intermediates = empty_intermediates[0..],
        .intermediates_len = 0,
    } };

    try std.testing.expectEqual(@as(?u8, 0), process(ev).?.key_format_change.resource);

    params[0] = 0;
    ev.style_change.final = 'g';
    ev.style_change.leader = '?';
    ev.style_change.private = true;
    try std.testing.expectEqual(@as(u8, 0), process(ev).?.key_format_query);
}

test "actions: xterm pointer mode maps bounded value" {
    var params = @as([csi_max_params]i32, @splat(0));
    params[0] = 2;
    var ev = Event{ .style_change = .{
        .final = 'p',
        .params = params[0..],
        .separators = empty_separators,
        .param_count = 1,
        .leader = '>',
        .private = false,
        .intermediates = empty_intermediates[0..],
        .intermediates_len = 0,
    } };
    try std.testing.expectEqual(@as(u2, 2), process(ev).?.pointer_mode);

    params[0] = 9;
    ev.style_change.params = params[0..];
    try std.testing.expectEqual(@as(u2, 3), process(ev).?.pointer_mode);

    ev.style_change.param_count = 0;
    try std.testing.expectEqual(@as(u2, 1), process(ev).?.pointer_mode);
}

test "actions: ANSI mode set reset and query map" {
    const set = process(makeStyleChange('h', 4, 20, 2)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u8, 2), set.ansi_mode_set.param_count);
    try std.testing.expectEqual(@as(u16, 4), set.ansi_mode_set.params[0]);
    try std.testing.expectEqual(@as(u16, 20), set.ansi_mode_set.params[1]);

    const reset = process(makeStyleChange('l', 2, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u8, 1), reset.ansi_mode_reset.param_count);
    try std.testing.expectEqual(@as(u16, 2), reset.ansi_mode_reset.params[0]);

    var params = @as([csi_max_params]i32, @splat(0));
    params[0] = 4;
    var intermediates = @as([4]u8, @splat(0));
    intermediates[0] = '$';
    const query = process(Event{ .style_change = .{
        .final = 'p',
        .params = params[0..],
        .separators = empty_separators,
        .param_count = 1,
        .leader = 0,
        .private = false,
        .intermediates = intermediates[0..],
        .intermediates_len = 1,
    } }) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 4), query.ansi_mode_query);
}

test "actions: locator controls map" {
    var params = @as([csi_max_params]i32, @splat(0));
    params[0] = 2;
    params[1] = 1;
    var intermediates = @as([4]u8, @splat(0));
    intermediates[0] = '\'';
    const elr = process(Event{ .style_change = .{
        .final = 'z',
        .params = params[0..],
        .separators = empty_separators,
        .param_count = 2,
        .leader = 0,
        .private = false,
        .intermediates = intermediates[0..],
        .intermediates_len = 1,
    } }) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 2), elr.locator_reporting.mode);
    try std.testing.expectEqual(@as(u16, 1), elr.locator_reporting.unit);

    params = @as([csi_max_params]i32, @splat(0));
    params[0] = 3;
    const req = process(Event{ .style_change = .{
        .final = '|',
        .params = params[0..],
        .separators = empty_separators,
        .param_count = 1,
        .leader = 0,
        .private = false,
        .intermediates = intermediates[0..],
        .intermediates_len = 1,
    } }) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 3), req.locator_request);

    params = @as([csi_max_params]i32, @splat(0));
    params[0] = 2;
    params[1] = 3;
    params[2] = 4;
    params[3] = 5;
    const filter = process(Event{ .style_change = .{
        .final = 'w',
        .params = params[0..],
        .separators = empty_separators,
        .param_count = 4,
        .leader = 0,
        .private = false,
        .intermediates = intermediates[0..],
        .intermediates_len = 1,
    } }) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(?u16, 1), filter.locator_filter.top);
    try std.testing.expectEqual(@as(?u16, 4), filter.locator_filter.right);

    intermediates[1] = '*';
    params = @as([csi_max_params]i32, @splat(0));
    params[0] = 1;
    params[1] = 3;
    const sle = process(Event{ .style_change = .{
        .final = '{',
        .params = params[0..],
        .separators = empty_separators,
        .param_count = 2,
        .leader = 0,
        .private = false,
        .intermediates = intermediates[0..],
        .intermediates_len = 2,
    } }) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u8, 2), sle.locator_events.param_count);
}
