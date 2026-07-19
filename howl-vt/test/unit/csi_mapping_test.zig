const std = @import("std");
const erase = @import("../../src/screen/erase.zig");
const route = @import("../../src/route.zig");
const semantic_event = @import("../../src/semantic_event.zig");
const parser_mod = @import("../../src/parser.zig");
const parsed_events = @import("../../src/parser/events.zig");

const Event = parsed_events.Event;
const EraseMode = erase.EraseMode;
const SemanticEvent = semantic_event.SemanticEvent;
const Screen = @import("../../src/screen.zig").Screen;
const process = route.process;
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
        for (params_in, 0..) |value, index| out[index] = value;
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

test "csi mapping: cursor motion and tab movement" {
    try std.testing.expectEqual(@as(u16, 3), process(makeStyleChange('A', 3, 0, 1)).?.cursor_up);
    try std.testing.expectEqual(@as(u16, 1), process(makeStyleChange('A', 0, 0, 1)).?.cursor_up);
    try std.testing.expectEqual(@as(u16, 5), process(makeStyleChange('B', 5, 0, 1)).?.cursor_down);
    try std.testing.expectEqual(@as(u16, 5), process(makeStyleChange('e', 5, 0, 1)).?.cursor_down);
    try std.testing.expectEqual(@as(u16, 1), process(makeStyleChange('e', 0, 0, 1)).?.cursor_down);
    try std.testing.expectEqual(@as(u16, 2), process(makeStyleChange('C', 2, 0, 1)).?.cursor_forward);
    try std.testing.expectEqual(@as(u16, 2), process(makeStyleChange('a', 2, 0, 1)).?.cursor_forward);
    try std.testing.expectEqual(@as(u16, 1), process(makeStyleChange('a', 0, 0, 1)).?.cursor_forward);
    try std.testing.expectEqual(@as(u16, 4), process(makeStyleChange('D', 4, 0, 1)).?.cursor_back);
    try std.testing.expectEqual(@as(u16, 3), process(makeStyleChange('E', 3, 0, 1)).?.cursor_next_line);
    try std.testing.expectEqual(@as(u16, 1), process(makeStyleChange('E', 0, 0, 1)).?.cursor_next_line);
    try std.testing.expectEqual(@as(u16, 2), process(makeStyleChange('F', 2, 0, 1)).?.cursor_prev_line);
    try std.testing.expectEqual(@as(u16, 1), process(makeStyleChange('F', 0, 0, 1)).?.cursor_prev_line);
    try std.testing.expectEqual(@as(u16, 6), process(makeStyleChange('G', 7, 0, 1)).?.cursor_horizontal_absolute);
    try std.testing.expectEqual(@as(u16, 0), process(makeStyleChange('G', 0, 0, 1)).?.cursor_horizontal_absolute);
    try std.testing.expectEqual(@as(u16, 6), process(makeStyleChange('`', 7, 0, 1)).?.cursor_horizontal_absolute);
    try std.testing.expectEqual(@as(u16, 0), process(makeStyleChange('`', 0, 0, 1)).?.cursor_horizontal_absolute);
    try std.testing.expectEqual(@as(u16, 8), process(makeStyleChange('d', 9, 0, 1)).?.cursor_vertical_absolute);
    try std.testing.expectEqual(@as(u16, 0), process(makeStyleChange('d', 0, 0, 1)).?.cursor_vertical_absolute);
    try std.testing.expectEqual(@as(u16, 3), process(makeStyleChange('I', 3, 0, 1)).?.horizontal_tab_forward);
    try std.testing.expectEqual(@as(u16, 1), process(makeStyleChange('I', 0, 0, 1)).?.horizontal_tab_forward);
    try std.testing.expectEqual(std.math.maxInt(u16), process(makeStyleChange('I', 999999, 0, 1)).?.horizontal_tab_forward);
    try std.testing.expectEqual(@as(u16, 2), process(makeStyleChange('Z', 2, 0, 1)).?.horizontal_tab_back);
    try std.testing.expectEqual(@as(u16, 1), process(makeStyleChange('Z', 0, 0, 1)).?.horizontal_tab_back);
    try std.testing.expectEqual(std.math.maxInt(u16), process(makeStyleChange('Z', 999999, 0, 1)).?.horizontal_tab_back);
}

test "csi mapping: editing and scrolling" {
    try std.testing.expectEqual(@as(u16, 3), process(makeStyleChange('L', 3, 0, 1)).?.insert_lines);
    try std.testing.expectEqual(@as(u16, 1), process(makeStyleChange('M', 0, 0, 0)).?.delete_lines);
    try std.testing.expectEqual(@as(u16, 3), process(makeStyleChange('P', 3, 0, 1)).?.delete_chars);
    try std.testing.expectEqual(@as(u16, 1), process(makeStyleChange('P', 0, 0, 0)).?.delete_chars);
    try std.testing.expectEqual(@as(u16, 4), process(makeStyleChange('@', 4, 0, 1)).?.insert_chars);
    try std.testing.expectEqual(@as(u16, 1), process(makeStyleChange('@', 0, 0, 0)).?.insert_chars);
    try std.testing.expectEqual(@as(u16, 4), process(makeStyleChange('b', 4, 0, 1)).?.repeat_preceding);
    try std.testing.expectEqual(@as(u16, 1), process(makeStyleChange('b', 0, 0, 0)).?.repeat_preceding);
    try std.testing.expectEqual(@as(u16, 2), process(makeStyleChange('S', 2, 0, 1)).?.scroll_up_lines);
    try std.testing.expectEqual(@as(u16, 1), process(makeStyleChange('T', 0, 0, 0)).?.scroll_down_lines);

    var intermediates = [_]u8{0} ** 4;
    intermediates[0] = '+';
    const params = [_]i32{3} ++ [_]i32{0} ** (csi_max_params - 1);
    try std.testing.expectEqual(@as(u16, 3), process(Event{ .style_change = .{
        .final = 'T',
        .params = params[0..],
        .separators = empty_separators,
        .param_count = 1,
        .leader = 0,
        .private = false,
        .intermediates = intermediates[0..],
        .intermediates_len = 1,
    } }).?.scroll_down_lines);
}

test "csi mapping: positioning, tab, erase, and reset semantics" {
    try std.testing.expectEqual(@as(u16, 1), process(makeStyleChange('r', 2, 5, 2)).?.set_scroll_region.top);
    try std.testing.expectEqual(@as(?u16, 4), process(makeStyleChange('r', 2, 5, 2)).?.set_scroll_region.bottom);
    try std.testing.expectEqual(@as(u16, 2), process(makeStyleChange('r', 3, 0, 1)).?.set_scroll_region.top);
    try std.testing.expectEqual(@as(?u16, null), process(makeStyleChange('r', 3, 0, 1)).?.set_scroll_region.bottom);
    try std.testing.expectEqual(@as(u16, 2), process(makeStyleChange('H', 3, 5, 2)).?.cursor_position.row);
    try std.testing.expectEqual(@as(u16, 4), process(makeStyleChange('H', 3, 5, 2)).?.cursor_position.col);
    try std.testing.expectEqual(@as(u16, 0), process(makeStyleChange('H', 0, 0, 0)).?.cursor_position.row);
    try std.testing.expectEqual(@as(u16, 0), process(makeStyleChange('H', 0, 0, 0)).?.cursor_position.col);
    try std.testing.expectEqual(@as(?SemanticEvent, null), process(makeStyleChange('Y', 1, 0, 1)));
    try std.testing.expect(process(makeStyleChangeWithIntermediate('p', '!')).? == .reset_screen);
    try std.testing.expect(process(makeStyleChange('g', 0, 0, 0)).? == .tab_clear_current);
    try std.testing.expect(process(makeStyleChange('g', 3, 0, 1)).? == .tab_clear_all);
    try std.testing.expect(process(makePrivateStyleChange('W', &.{5})).? == .reset_default_tab_stops);
    try std.testing.expect(!process(makeStyleChange('J', 0, 0, 0)).?.erase_display_below);
    try std.testing.expect(!process(makeStyleChange('J', 1, 0, 1)).?.erase_display_above);
    try std.testing.expect(!process(makeStyleChange('J', 2, 0, 1)).?.erase_display_complete);
    try std.testing.expect(!process(makeStyleChange('J', 3, 0, 1)).?.erase_display_scrollback);
    try std.testing.expect(!process(makeStyleChange('J', 5, 0, 1)).?.erase_display_below);
    try std.testing.expectEqual(EraseMode.cursor_to_end, process(makeStyleChange('K', 0, 0, 0)).?.erase_line);
    try std.testing.expectEqual(EraseMode.start_to_cursor, process(makeStyleChange('K', 1, 0, 1)).?.erase_line);
    try std.testing.expectEqual(EraseMode.all, process(makeStyleChange('K', 2, 0, 1)).?.erase_line);
    try std.testing.expectEqual(EraseMode.cursor_to_end, process(makeStyleChange('K', 5, 0, 1)).?.erase_line);
    try std.testing.expectEqual(@as(u16, 6), process(makeStyleChange('X', 6, 0, 1)).?.erase_chars);
    try std.testing.expectEqual(@as(u16, 1), process(makeStyleChange('X', 0, 0, 0)).?.erase_chars);
    try std.testing.expectEqual(@as(u16, 3), process(makeStyleChangeWithParamAndIntermediate('@', 3, ' ')).?.shift_left_columns);
    try std.testing.expectEqual(@as(u16, 1), process(makeStyleChangeWithIntermediate('A', ' ')).?.shift_right_columns);
    try std.testing.expectEqual(Screen.CursorShape.none, process(makeStyleChangeWithParamAndIntermediate('q', 7, ' ')).?.cursor_style.program_override.shape);
}

test "csi mapping: protection, rectangular ops, and margins" {
    try std.testing.expect(process(makeStyleChangeWithParamAndIntermediate('q', 1, '"')).?.character_protection);
    try std.testing.expect(!process(makeStyleChangeWithParamAndIntermediate('q', 2, '"')).?.character_protection);
    try std.testing.expect(process(makePrivateStyleChange('J', &.{2})).?.erase_display_complete);
    try std.testing.expectEqual(EraseMode.start_to_cursor, process(makePrivateStyleChange('K', &.{1})).?.selective_erase_line);
    try std.testing.expect(process(makePrivateStyleChange('J', &.{5})).?.erase_display_below);
    try std.testing.expectEqual(EraseMode.cursor_to_end, process(makePrivateStyleChange('K', &.{5})).?.selective_erase_line);

    var params = [_]i32{0} ** csi_max_params;
    params[0] = 88;
    params[1] = 1;
    params[2] = 2;
    params[3] = 3;
    params[4] = 4;
    var intermediates = [_]u8{0} ** 4;
    intermediates[0] = '$';
    const fill = process(Event{ .style_change = .{
        .final = 'x',
        .params = params[0..],
        .separators = empty_separators,
        .param_count = 5,
        .leader = 0,
        .private = false,
        .intermediates = intermediates[0..],
        .intermediates_len = 1,
    } }).?;
    try std.testing.expectEqual(@as(u21, 88), fill.rect_fill.ch);
    try std.testing.expectEqual(@as(u16, 0), fill.rect_fill.area.top);
    try std.testing.expectEqual(@as(u16, 1), fill.rect_fill.area.left);

    params = [_]i32{0} ** csi_max_params;
    params[0] = 1;
    params[1] = 1;
    params[2] = 2;
    params[3] = 2;
    params[4] = 1;
    params[5] = 3;
    params[6] = 4;
    params[7] = 1;
    const copy = process(Event{ .style_change = .{
        .final = 'v',
        .params = params[0..],
        .separators = empty_separators,
        .param_count = 8,
        .leader = 0,
        .private = false,
        .intermediates = intermediates[0..],
        .intermediates_len = 1,
    } }).?;
    try std.testing.expectEqual(@as(u16, 2), copy.rect_copy.dest_top);
    try std.testing.expectEqual(@as(u16, 3), copy.rect_copy.dest_left);

    intermediates[0] = '\'';
    const insert_params = [_]i32{2} ++ [_]i32{0} ** (csi_max_params - 1);
    try std.testing.expectEqual(@as(u16, 2), process(Event{ .style_change = .{
        .final = '}',
        .params = insert_params[0..],
        .separators = empty_separators,
        .param_count = 1,
        .leader = 0,
        .private = false,
        .intermediates = intermediates[0..],
        .intermediates_len = 1,
    } }).?.insert_columns);

    const delete_params = [_]i32{3} ++ [_]i32{0} ** (csi_max_params - 1);
    try std.testing.expectEqual(@as(u16, 3), process(Event{ .style_change = .{
        .final = '~',
        .params = delete_params[0..],
        .separators = empty_separators,
        .param_count = 1,
        .leader = 0,
        .private = false,
        .intermediates = intermediates[0..],
        .intermediates_len = 1,
    } }).?.delete_columns);

    params = [_]i32{0} ** csi_max_params;
    params[0] = 1;
    params[1] = 1;
    params[2] = 2;
    params[3] = 2;
    params[4] = 1;
    intermediates[0] = '$';
    const change = process(Event{ .style_change = .{
        .final = 'r',
        .params = params[0..],
        .separators = empty_separators,
        .param_count = 5,
        .leader = 0,
        .private = false,
        .intermediates = intermediates[0..],
        .intermediates_len = 1,
    } }).?;
    try std.testing.expect(!change.rect_attrs_change.reverse);
    try std.testing.expectEqual(@as(u16, 1), change.rect_attrs_change.attrs.params[0]);

    const reverse = process(Event{ .style_change = .{
        .final = 't',
        .params = params[0..],
        .separators = empty_separators,
        .param_count = 5,
        .leader = 0,
        .private = false,
        .intermediates = intermediates[0..],
        .intermediates_len = 1,
    } }).?;
    try std.testing.expect(reverse.rect_attrs_change.reverse);

    intermediates[0] = '*';
    const extent_params = [_]i32{2} ++ [_]i32{0} ** (csi_max_params - 1);
    try std.testing.expect(process(Event{ .style_change = .{
        .final = 'x',
        .params = extent_params[0..],
        .separators = empty_separators,
        .param_count = 1,
        .leader = 0,
        .private = false,
        .intermediates = intermediates[0..],
        .intermediates_len = 1,
    } }).?.attr_change_extent_rect);

    const margins = process(makeStyleChange('s', 2, 4, 2)).?;
    try std.testing.expectEqual(@as(u16, 1), margins.set_left_right_margins.left);
    try std.testing.expectEqual(@as(?u16, 3), margins.set_left_right_margins.right);
    try std.testing.expect(process(makePrivateStyleChange('h', &.{69})).?.left_right_margin_mode);
    try std.testing.expect(!process(makePrivateStyleChange('l', &.{69})).?.left_right_margin_mode);
}

test "csi mapping: cursor style, save restore aliases, and invalid sequence" {
    try std.testing.expectEqual(@as(?SemanticEvent, null), process(Event.invalid_sequence));
    try std.testing.expect(process(makeStyleChange('s', 0, 0, 0)).? == .save_cursor);
    try std.testing.expect(process(makeStyleChange('u', 0, 0, 0)).? == .restore_cursor);
    var sem = process(makeStyleChangeWithParamAndIntermediate('q', 0, ' ')).?;
    try std.testing.expectEqual(Screen.CursorShape.block, sem.cursor_style.program_override.shape);
    try std.testing.expect(sem.cursor_style.program_override.blink);
    sem = process(makeStyleChangeWithParamAndIntermediate('q', 4, ' ')).?;
    try std.testing.expectEqual(Screen.CursorShape.underline, sem.cursor_style.program_override.shape);
    try std.testing.expect(!sem.cursor_style.program_override.blink);
    sem = process(makeStyleChangeWithParamAndIntermediate('q', 5, ' ')).?;
    try std.testing.expectEqual(Screen.CursorShape.bar, sem.cursor_style.program_override.shape);
    try std.testing.expect(sem.cursor_style.program_override.blink);
    sem = process(makeStyleChangeWithParamAndIntermediate('q', 7, ' ')).?;
    try std.testing.expectEqual(Screen.CursorShape.none, sem.cursor_style.program_override.shape);
    try std.testing.expect(sem.cursor_style.program_override.blink);
}

test "csi mapping: mode query, save restore, and erase families" {
    var params = [_]i32{0} ** csi_max_params;
    params[0] = 1004;
    var intermediates = [_]u8{0} ** 4;
    intermediates[0] = '$';
    const decrqm = process(Event{ .style_change = .{
        .final = 'p',
        .params = params[0..],
        .separators = empty_separators,
        .param_count = 1,
        .leader = '?',
        .private = true,
        .intermediates = intermediates[0..],
        .intermediates_len = 1,
    } }).?;
    try std.testing.expectEqual(@as(u16, 1004), decrqm.dec_mode_query);

    const save = process(makePrivateStyleChange('s', &.{ 1, 7, 1004 })).?;
    try std.testing.expectEqual(@as(u8, 3), save.dec_mode_save.param_count);
    try std.testing.expectEqual(@as(u16, 1), save.dec_mode_save.params[0]);
    try std.testing.expectEqual(@as(u16, 7), save.dec_mode_save.params[1]);
    try std.testing.expectEqual(@as(u16, 1004), save.dec_mode_save.params[2]);

    const restore = process(makePrivateStyleChange('r', &.{ 1, 7, 1004 })).?;
    try std.testing.expectEqual(@as(u8, 3), restore.dec_mode_restore.param_count);
    try std.testing.expectEqual(@as(u16, 1004), restore.dec_mode_restore.params[2]);

    try std.testing.expect(!process(makeStyleChange('J', 0, 0, 0)).?.erase_display_below);
    try std.testing.expect(!process(makeStyleChange('J', 1, 0, 1)).?.erase_display_above);
    try std.testing.expect(!process(makeStyleChange('J', 2, 0, 1)).?.erase_display_complete);
    try std.testing.expect(!process(makeStyleChange('J', 3, 0, 1)).?.erase_display_scrollback);
    try std.testing.expect(!process(makeStyleChange('J', 5, 0, 1)).?.erase_display_below);
    try std.testing.expectEqual(EraseMode.cursor_to_end, process(makeStyleChange('K', 0, 0, 0)).?.erase_line);
    try std.testing.expectEqual(EraseMode.start_to_cursor, process(makeStyleChange('K', 1, 0, 1)).?.erase_line);
    try std.testing.expectEqual(EraseMode.all, process(makeStyleChange('K', 2, 0, 1)).?.erase_line);
    try std.testing.expectEqual(EraseMode.cursor_to_end, process(makeStyleChange('K', 5, 0, 1)).?.erase_line);
    try std.testing.expectEqual(@as(u16, 6), process(makeStyleChange('X', 6, 0, 1)).?.erase_chars);
    try std.testing.expectEqual(@as(u16, 1), process(makeStyleChange('X', 0, 0, 0)).?.erase_chars);
    try std.testing.expectEqual(@as(u16, 3), process(makeStyleChangeWithParamAndIntermediate('@', 3, ' ')).?.shift_left_columns);
    try std.testing.expectEqual(@as(u16, 1), process(makeStyleChangeWithIntermediate('A', ' ')).?.shift_right_columns);
    try std.testing.expect(process(makePrivateStyleChange('W', &.{5})).? == .reset_default_tab_stops);
}
