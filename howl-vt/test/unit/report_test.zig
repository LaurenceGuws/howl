const std = @import("std");
const route = @import("../../src/route.zig");
const parser_mod = @import("../../src/parser.zig");
const parsed_events = @import("../../src/parser/events.zig");

const Event = parsed_events.Event;
const process = route.process;
const csi_max_params = parser_mod.max_params;
const empty_params = [_]i32{0} ** csi_max_params;
const empty_separators = parser_mod.CsiSeparatorList.initEmpty();
const empty_intermediates = [_]u8{0} ** parser_mod.max_intermediates;

fn makeStyleChange(comptime final: u8, comptime p0: i32, comptime p1: i32, comptime count: u8) Event {
    const params = [_]i32{ p0, p1 } ++ [_]i32{0} ** (csi_max_params - 2);
    return Event{ .style_change = .{ .final = final, .params = params[0..], .separators = empty_separators, .param_count = count, .leader = 0, .private = false, .intermediates = empty_intermediates[0..], .intermediates_len = 0 } };
}

fn makePrivateStyleChange(comptime final: u8, comptime params_in: []const i32) Event {
    const params = comptime blk: {
        var out = [_]i32{0} ** csi_max_params;
        for (params_in, 0..) |value, index| out[index] = value;
        break :blk out;
    };
    return Event{ .style_change = .{ .final = final, .params = params[0..], .separators = empty_separators, .param_count = @intCast(params_in.len), .leader = '?', .private = true, .intermediates = empty_intermediates[0..], .intermediates_len = 0 } };
}

test "report mapping: DSR DECXCPR and DEC locator status map" {
    try std.testing.expect(process(makeStyleChange('n', 5, 0, 1)).? == .device_status_report);
    try std.testing.expect(process(makeStyleChange('n', 6, 0, 1)).? == .cursor_position_report);
    try std.testing.expect(process(makePrivateStyleChange('n', &.{6})).? == .dec_cursor_position_report);
    try std.testing.expectEqual(@as(u16, 55), process(makePrivateStyleChange('n', &.{55})).?.dec_device_status_report);
    try std.testing.expectEqual(@as(u16, 56), process(makePrivateStyleChange('n', &.{56})).?.dec_device_status_report);
}

test "report mapping: device attributes and title reports" {
    try std.testing.expect(process(makeStyleChange('c', 0, 0, 0)).? == .primary_device_attributes);
    const da2 = Event{ .style_change = .{ .final = 'c', .params = empty_params[0..], .separators = empty_separators, .param_count = 0, .leader = '>', .private = false, .intermediates = empty_intermediates[0..], .intermediates_len = 0 } };
    try std.testing.expect(process(da2).? == .secondary_device_attributes);
    var params = [_]i32{0} ** csi_max_params;
    params[0] = 0;
    const xtversion = Event{ .style_change = .{ .final = 'q', .params = params[0..], .separators = empty_separators, .param_count = 1, .leader = '>', .private = false, .intermediates = empty_intermediates[0..], .intermediates_len = 0 } };
    try std.testing.expect(process(xtversion).? == .xtversion);
    var intermediates = [_]u8{0} ** 4;
    intermediates[0] = '#';
    const xttitlepos = Event{ .style_change = .{ .final = 'S', .params = empty_params[0..], .separators = empty_separators, .param_count = 0, .leader = 0, .private = false, .intermediates = intermediates[0..], .intermediates_len = 1 } };
    try std.testing.expect(process(xttitlepos).? == .xttitlepos);
    const da3 = Event{ .style_change = .{ .final = 'c', .params = empty_params[0..], .separators = empty_separators, .param_count = 0, .leader = '=', .private = false, .intermediates = empty_intermediates[0..], .intermediates_len = 0 } };
    try std.testing.expect(process(da3).? == .tertiary_device_attributes);
}

test "report mapping: checksum and report request families" {
    var intermediates = [_]u8{0} ** 4;
    var params = [_]i32{0} ** csi_max_params;
    intermediates[0] = '"';
    try std.testing.expect(process(Event{ .style_change = .{ .final = 'v', .params = params[0..], .separators = empty_separators, .param_count = 0, .leader = 0, .private = false, .intermediates = intermediates[0..], .intermediates_len = 1 } }).? == .screen_extent_report);
    intermediates[0] = '#';
    params[0] = 3;
    try std.testing.expectEqual(@as(u16, 3), process(Event{ .style_change = .{ .final = 'y', .params = params[0..], .separators = empty_separators, .param_count = 1, .leader = 0, .private = false, .intermediates = intermediates[0..], .intermediates_len = 1 } }).?.xtchecksum);
    intermediates[0] = '*';
    params = [_]i32{0} ** csi_max_params;
    params[0] = 7;
    params[1] = 1;
    params[2] = 2;
    params[3] = 3;
    params[4] = 4;
    params[5] = 5;
    const crc = process(Event{ .style_change = .{ .final = 'y', .params = params[0..], .separators = empty_separators, .param_count = 6, .leader = 0, .private = false, .intermediates = intermediates[0..], .intermediates_len = 1 } }).?.rect_checksum_request;
    try std.testing.expectEqual(@as(u16, 7), crc.request_id);
    try std.testing.expectEqual(@as(u16, 1), crc.page);
    try std.testing.expectEqual(@as(u16, 1), process(makeStyleChange('x', 1, 0, 1)).?.parameters_report);
    intermediates[0] = '#';
    try std.testing.expect(process(Event{ .style_change = .{ .final = 'R', .params = empty_params[0..], .separators = empty_separators, .param_count = 0, .leader = 0, .private = false, .intermediates = intermediates[0..], .intermediates_len = 1 } }).? == .xtreportcolors);
}

test "report mapping: XTREPORTSGR maps selected graphic rendition report" {
    var intermediates = [_]u8{0} ** 4;
    intermediates[0] = '#';
    var params = [_]i32{0} ** csi_max_params;
    params[0] = 1;
    params[1] = 2;
    params[2] = 3;
    params[3] = 4;
    const sgr = process(Event{ .style_change = .{ .final = '|', .params = params[0..], .separators = empty_separators, .param_count = 4, .leader = 0, .private = false, .intermediates = intermediates[0..], .intermediates_len = 1 } }).?.selected_graphic_rendition_report;
    try std.testing.expectEqual(@as(u16, 0), sgr.top);
    try std.testing.expectEqual(@as(u16, 1), sgr.left);
    try std.testing.expectEqual(@as(?u16, 2), sgr.bottom);
    try std.testing.expectEqual(@as(?u16, 3), sgr.right);
}
