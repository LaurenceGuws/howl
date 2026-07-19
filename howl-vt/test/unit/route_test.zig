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
const empty_params = [_]i32{0} ** csi_max_params;
const empty_separators = parser_mod.CsiSeparatorList.initEmpty();
const empty_intermediates = [_]u8{0} ** parser_mod.max_intermediates;

fn makeStyleChange(comptime final: u8, comptime p0: i32, comptime p1: i32, comptime count: u8) Event {
    const params = [_]i32{ p0, p1 } ++ [_]i32{0} ** (csi_max_params - 2);
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
    const params = [_]i32{0} ** csi_max_params;
    const intermediates = [_]u8{intermediate} ++ [_]u8{0} ** (parser_mod.max_intermediates - 1);
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
    const params = [_]i32{p0} ++ [_]i32{0} ** (csi_max_params - 1);
    const intermediates = [_]u8{intermediate} ++ [_]u8{0} ** (parser_mod.max_intermediates - 1);
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
        var out = [_]i32{0} ** csi_max_params;
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
        .intermediates = [_]u8{0} ** 4,
        .intermediates_len = 0,
    } };
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
    var params = [_]i32{0} ** csi_max_params;
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
    try std.testing.expect(process(ev).?.application_cursor_keys);
}

test "actions: DEC private focus reporting enable maps true" {
    var params = [_]i32{0} ** csi_max_params;
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
    try std.testing.expect(process(ev).?.focus_reporting);
}

test "actions: DEC private bracketed paste disable maps false" {
    var params = [_]i32{0} ** csi_max_params;
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
    try std.testing.expect(!process(ev).?.bracketed_paste);
}

test "actions: DEC private synchronized output maps enable disable" {
    try std.testing.expect(process(makePrivateStyleChange('h', &.{2026})).?.synchronized_output);
    try std.testing.expect(!process(makePrivateStyleChange('l', &.{2026})).?.synchronized_output);
}

test "actions: DEC private mouse tracking mode mappings" {
    var params = [_]i32{0} ** csi_max_params;
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
    try std.testing.expect(process(ev).? == .mouse_tracking_x10);
    params[0] = 1000;
    ev.style_change.params = params[0..];
    try std.testing.expect(process(ev).? == .mouse_tracking_normal);
    params[0] = 1002;
    ev.style_change.params = params[0..];
    try std.testing.expect(process(ev).? == .mouse_tracking_button_event);
    params[0] = 1003;
    ev.style_change.params = params[0..];
    try std.testing.expect(process(ev).? == .mouse_tracking_any_event);
    params[0] = 1006;
    ev.style_change.params = params[0..];
    try std.testing.expect(process(ev).?.mouse_protocol_sgr);
    params[0] = 1005;
    ev.style_change.params = params[0..];
    try std.testing.expect(process(ev).?.mouse_protocol_utf8);
    params[0] = 1015;
    ev.style_change.params = params[0..];
    try std.testing.expect(process(ev).?.mouse_protocol_urxvt);
}

test "actions: low priority DEC private modes and media copy map" {
    var params = [_]i32{0} ** csi_max_params;
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
    try std.testing.expect(process(ev).?.reverse_wraparound_mode);

    params[0] = 1045;
    ev.style_change.params = params[0..];
    try std.testing.expect(process(ev).?.extended_reverse_wraparound_mode);

    params[0] = 5;
    ev.style_change.final = 'i';
    ev.style_change.params = params[0..];
    try std.testing.expectEqual(@as(u16, 5), process(ev).?.media_copy_request);
}

test "actions: application keypad and modifyOtherKeys mappings" {
    try std.testing.expect(process(makeEscFinal('=')).?.application_keypad);
    try std.testing.expect(!process(makeEscFinal('>')).?.application_keypad);

    var params = [_]i32{0} ** csi_max_params;
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
    try std.testing.expect(process(ev).?.application_keypad);

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
    var params = [_]i32{0} ** csi_max_params;
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
    var params = [_]i32{0} ** csi_max_params;
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
    var params = [_]i32{0} ** csi_max_params;
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
    var params = [_]i32{0} ** csi_max_params;
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
    var params = [_]i32{0} ** csi_max_params;
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

    var params = [_]i32{0} ** csi_max_params;
    params[0] = 4;
    var intermediates = [_]u8{0} ** 4;
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
    var params = [_]i32{0} ** csi_max_params;
    params[0] = 2;
    params[1] = 1;
    var intermediates = [_]u8{0} ** 4;
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

    params = [_]i32{0} ** csi_max_params;
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

    params = [_]i32{0} ** csi_max_params;
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
    params = [_]i32{0} ** csi_max_params;
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
