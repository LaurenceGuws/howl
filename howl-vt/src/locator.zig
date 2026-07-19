//! Owns DEC locator configuration and locator report generation.

const std = @import("std");
const input_mouse = @import("input/mouse.zig");
const rect = @import("screen/rect.zig");
const host_state = @import("host_state.zig");

const format_output_max_bytes = 40;

const ReportingMode = enum(u2) {
    disabled,
    continuous,
    one_shot,
};

const FilterRect = struct {
    top: u16,
    left: u16,
    bottom: u16,
    right: u16,
};

/// Stores DEC locator reporting mode, filter rectangle, and one-shot event flags.
pub const Locator = struct {
    mode: ReportingMode = .disabled,
    coordinate_unit: u16 = 0,
    report_button_down: bool = false,
    report_button_up: bool = false,
    filter_rect: ?FilterRect = null,
    last_row: ?u16 = null,
    last_col: ?u16 = null,
    last_pixel_x: ?u32 = null,
    last_pixel_y: ?u32 = null,
    last_buttons_down: u8 = 0,
};

/// Sets locator reporting and coordinate units, disabling unsupported values.
pub fn setReporting(state: *Locator, mode: u16, unit: u16) void {
    state.mode = switch (mode) {
        1 => .continuous,
        2 => .one_shot,
        else => .disabled,
    };
    state.coordinate_unit = unit;
}

/// Installs an optional locator filter rectangle and clears its outside latch.
pub fn setFilter(state: *Locator, area: rect.OptionalRectArea) void {
    const row = state.last_row orelse 0;
    const col = state.last_col orelse 0;
    const top = area.top orelse row;
    const left = area.left orelse col;
    const bottom = area.bottom orelse row;
    const right = area.right orelse col;
    if (area.top == null and area.left == null and area.bottom == null and area.right == null) {
        state.filter_rect = null;
        return;
    }
    if (top > bottom or left > right) return;
    state.filter_rect = .{ .top = top, .left = left, .bottom = bottom, .right = right };
}

/// Replaces one-shot locator event flags from borrowed numeric modes.
pub fn setEvents(state: *Locator, modes: []const u16) void {
    for (modes) |mode| switch (mode) {
        0 => {
            state.report_button_down = false;
            state.report_button_up = false;
            state.filter_rect = null;
        },
        1 => state.report_button_down = true,
        2 => state.report_button_down = false,
        3 => state.report_button_up = true,
        4 => state.report_button_up = false,
        else => {},
    };
}

/// Appends a bounded locator status or position reply for one request parameter.
pub fn appendReportForRequest(state: *Locator, allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, param: u16) host_state.ApplyError!void {
    if (param > 1) return;
    if (state.mode == .disabled or state.last_row == null or state.last_col == null) {
        try host_state.appendOutput(output, allocator, "\x1b[0&w");
        return;
    }
    try appendReport(state, allocator, output, encode_buf, 1, state.last_buttons_down, state.last_row.?, state.last_col.?);
}

/// Appends the supported locator device-status reply for parameter 53.
pub fn appendDeviceStatusReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, param: u16) host_state.ApplyError!void {
    const text = switch (param) {
        55 => formatOutput(encode_buf, "\x1b[?50n", .{}),
        56 => formatOutput(encode_buf, "\x1b[?57;1n", .{}),
        else => return,
    };
    try host_state.appendOutput(output, allocator, text);
}

/// Updates representable locator coordinates and appends enabled reports.
///
/// Rows outside the retained `u16` coordinate domain are ignored. Report
/// allocation or capacity failure preserves one-shot and filter latches.
pub fn handleMouseEvent(state: *Locator, allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, event: input_mouse.MouseEvent) host_state.ApplyError!void {
    if (event.row < 0 or event.row > std.math.maxInt(u16)) return;
    const row: u16 = @intCast(event.row);
    const col = event.col;
    state.last_row = row;
    state.last_col = col;
    state.last_pixel_x = event.pixel_x;
    state.last_pixel_y = event.pixel_y;
    state.last_buttons_down = event.buttons_down;

    if (state.mode == .disabled) return;

    if (state.filter_rect) |filter| {
        if (row < filter.top or row > filter.bottom or col < filter.left or col > filter.right) {
            try appendReport(state, allocator, output, encode_buf, 10, event.buttons_down, row, col);
            state.filter_rect = null;
            return;
        }
    }

    const event_code: ?u16 = switch (event.kind) {
        .press => if (state.report_button_down) switch (event.button) {
            .left => 2,
            .middle => 4,
            .right => 6,
            else => null,
        } else null,
        .release => if (state.report_button_up) switch (event.button) {
            .left => 3,
            .middle => 5,
            .right => 7,
            else => null,
        } else null,
        else => null,
    };
    if (event_code) |code| try appendReport(state, allocator, output, encode_buf, code, event.buttons_down, row, col);
}

fn appendReport(state: *Locator, allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, event_code: u16, buttons_down: u8, row: u16, col: u16) host_state.ApplyError!void {
    const button_mask = buttonsMask(buttons_down);
    const coords = coordinates(state, row, col);
    const text = formatOutput(encode_buf, "\x1b[{d};{d};{d};{d};0&w", .{ event_code, button_mask, coords.row + 1, coords.col + 1 });
    try host_state.appendOutput(output, allocator, text);
    if (state.mode == .one_shot) state.mode = .disabled;
}

fn formatOutput(encode_buf: []u8, comptime fmt: []const u8, args: anytype) []const u8 {
    std.debug.assert(encode_buf.len >= format_output_max_bytes);
    return std.fmt.bufPrint(encode_buf, fmt, args) catch unreachable;
}

fn coordinates(state: *const Locator, row: u16, col: u16) struct { row: u32, col: u32 } {
    if (state.coordinate_unit == 1) {
        return .{ .row = state.last_pixel_y orelse row, .col = state.last_pixel_x orelse col };
    }
    return .{ .row = row, .col = col };
}

fn buttonsMask(buttons_down: u8) u16 {
    var mask: u16 = 0;
    if ((buttons_down & 0b001) != 0) mask |= 4;
    if ((buttons_down & 0b010) != 0) mask |= 2;
    if ((buttons_down & 0b100) != 0) mask |= 1;
    return mask;
}
