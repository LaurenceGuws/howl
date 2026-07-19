//! Formats bounded terminal replies from current semantic state.

const std = @import("std");
const screen_mod = @import("screen.zig");
const rect = @import("screen/rect.zig");
const locator = @import("locator.zig");
const mode_mod = @import("mode.zig");
const input_encode = @import("input/encode.zig");
const host_state = @import("host_state.zig");
const semantic_event = @import("semantic_event.zig");
const terminal_mod = @import("terminal.zig");

const Screen = screen_mod.Screen;
const Grid = Screen;
const LocatorNs = locator;
const TerminalModeNs = mode_mod;
const Terminal = terminal_mod.Terminal;
const SemanticEvent = semantic_event.SemanticEvent;

const xtversion_text = "howl-vt dev";
const format_output_max_bytes = 64;

const CursorReportView = struct {
    rows: u16,
    cols: u16,
    cursor_row: u16,
    cursor_col: u16,
};

const RectChecksumRequest = struct {
    request_id: u16,
};

/// Apply one report-directed semantic event to bounded host output.
pub fn apply(vt: *Terminal, event: SemanticEvent) host_state.ApplyError!void {
    var scratch: input_encode.Scratch = .{};
    const allocator = vt.allocator;
    const pending_output = &vt.host.pending_output;
    const encode_buf = scratch.buf[0..];
    const active = vt.screen_state.activeConst();
    const render_view = CursorReportView{
        .rows = active.rows,
        .cols = active.cols,
        .cursor_row = active.cursor.row,
        .cursor_col = active.cursor.col,
    };
    const ansi_modes = TerminalModeNs.AnsiView{
        .keyboard_action_mode = vt.modes.keyboard_action_mode,
        .insert_mode = active.insert_mode,
        .send_receive_mode = vt.modes.send_receive_mode,
        .newline_mode = vt.modes.newline_mode,
    };
    const dec_modes = TerminalModeNs.DecView{
        .application_cursor_keys = vt.modes.application_cursor_keys,
        .application_keypad = vt.modes.application_keypad,
        .reverse_screen_mode = vt.modes.reverse_screen_mode,
        .auto_wrap = active.auto_wrap,
        .left_right_margin_mode = active.left_right_margin_mode,
        .cursor_visible = active.cursor.visible,
        .alt_active = vt.screen_state.alt_active,
        .mouse_tracking = vt.modes.mouse_tracking,
        .mouse_protocol = vt.modes.mouse_protocol,
        .focus_reporting = vt.modes.focus_reporting,
        .bracketed_paste = vt.modes.bracketed_paste,
        .synchronized_output = vt.modes.synchronized_output,
    };
    switch (event) {
        .ansi_mode_query => |mode| try appendAnsiModeReport(allocator, pending_output, encode_buf, mode, TerminalModeNs.ansiModeStateForView(ansi_modes, mode)),
        .modify_other_keys_query => try appendModifyOtherKeysReport(allocator, pending_output, encode_buf, vt.modes.modify_other_keys),
        .key_format_query => |resource| if (isKeyFormatResource(resource)) try appendKeyFormatReport(allocator, pending_output, encode_buf, resource, vt.modes.key_format[resource]),
        .dec_mode_query => |mode| try appendDecModeReport(allocator, pending_output, encode_buf, mode, TerminalModeNs.decModeStateForView(dec_modes, mode)),
        .dcs_request_status => |request| try appendDecrqssReply(allocator, pending_output, encode_buf, active, request),
        .dcs_request_termcap => try appendTermcapInvalidReport(allocator, pending_output),
        .dcs_request_resource => |request| try appendResourceInvalidReport(allocator, pending_output, request),
        .device_status_report => try host_state.appendOutput(pending_output, allocator, "\x1b[0n"),
        .dec_device_status_report => |param| try LocatorNs.appendDeviceStatusReport(allocator, pending_output, encode_buf, param),
        .cursor_position_report => try appendCursorPositionReport(allocator, pending_output, encode_buf, render_view),
        .dec_cursor_position_report => try appendDecCursorPositionReport(allocator, pending_output, encode_buf, render_view),
        .primary_device_attributes => try host_state.appendOutput(pending_output, allocator, "\x1b[?62;22c"),
        .secondary_device_attributes => try host_state.appendOutput(pending_output, allocator, "\x1b[>1;10;0c"),
        .tertiary_device_attributes => try host_state.appendOutput(pending_output, allocator, "\x1bP!|00000000\x1b\\"),
        .xtversion => try appendXtVersionReport(allocator, pending_output),
        .xttitlepos => try appendTitleStackPositionReport(allocator, pending_output, encode_buf, 0, 0),
        .xtchecksum => |flags| vt.xtchecksum_flags = flags,
        .rect_checksum_request => |req| try appendRectChecksumReport(
            allocator,
            pending_output,
            encode_buf,
            .{ .request_id = req.request_id },
            computeRectChecksum(active, vt.xtchecksum_flags, req.page, req.area),
        ),
        .selected_graphic_rendition_report => |area| try appendSelectedGraphicRenditionReport(allocator, pending_output, encode_buf, active, area),
        .screen_extent_report => try appendScreenExtentReport(allocator, pending_output, encode_buf, render_view),
        .parameters_report => |kind| try appendTerminalParametersReport(allocator, pending_output, encode_buf, kind),
        .xtreportcolors => try appendColorStackReport(allocator, pending_output, encode_buf, vt.kitty.color_stack.len),
        .iterm_report_cell_size => try appendItermCellSizeReport(vt, encode_buf),
        else => unreachable,
    }
}

fn appendItermCellSizeReport(vt: *Terminal, scratch: []u8) host_state.ApplyError!void {
    const cell = vt.cellPixelSize() orelse return;
    // The current host supplies logical pixel metrics and owns no output-scale
    // protocol, so points equal pixels and the reported scale is exactly one.
    const reply = std.fmt.bufPrint(
        scratch,
        "\x1b]1337;ReportCellSize={d};{d};1\x1b\\",
        .{ cell.height, cell.width },
    ) catch unreachable;
    try vt.host.appendPendingOutput(reply);
}

fn isKeyFormatResource(resource: u8) bool {
    return resource <= 4 or resource == 6 or resource == 7;
}

fn appendDecrqssReply(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, screen: *const Screen, request: []const u8) host_state.ApplyError!void {
    if (decrqssPayload(encode_buf, screen, request)) |payload| {
        const start = host_state.byteCount(output.items);
        errdefer host_state.restorePendingOutput(output, start);
        try host_state.appendOutput(output, allocator, "\x1bP1$r");
        try host_state.appendOutput(output, allocator, payload);
        try host_state.appendOutput(output, allocator, "\x1b\\");
        return;
    }
    try host_state.appendOutput(output, allocator, "\x1bP0$r\x1b\\");
}

fn decrqssPayload(encode_buf: []u8, screen: *const Screen, request: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, request, "r")) {
        const bottom = if (screen.rows == 0) @as(u16, 0) else @min(screen.scroll_bottom, screen.rows - 1);
        return std.fmt.bufPrint(encode_buf, "{d};{d}r", .{ screen.scroll_top + 1, bottom + 1 }) catch null;
    }
    if (std.mem.eql(u8, request, "s")) {
        const right = if (screen.left_right_margin_mode) screen.right_margin else screen.cols -| 1;
        return std.fmt.bufPrint(encode_buf, "{d};{d}s", .{ screen.left_margin + 1, right + 1 }) catch null;
    }
    if (std.mem.eql(u8, request, " q")) {
        const style = screen.cursor.effectiveStyle();
        const value: u8 = switch (style.shape) {
            .none => 1,
            .block => if (style.blink) 0 else 2,
            .underline => if (style.blink) 3 else 4,
            .bar => if (style.blink) 5 else 6,
        };
        return std.fmt.bufPrint(encode_buf, "{d} q", .{value}) catch null;
    }
    if (std.mem.eql(u8, request, "\"q")) {
        const value: u8 = if (screen.current_attrs.protected) 1 else 0;
        return std.fmt.bufPrint(encode_buf, "{d}\"q", .{value}) catch null;
    }
    if (std.mem.eql(u8, request, "*x")) {
        const value: u8 = if (screen.attr_change_extent_rect) 2 else 0;
        return std.fmt.bufPrint(encode_buf, "{d}*x", .{value}) catch null;
    }
    return null;
}

fn appendModifyOtherKeysReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, value: i8) host_state.ApplyError!void {
    const text = formatOutput(encode_buf, "\x1b[>4;{d}m", .{value});
    try host_state.appendOutput(output, allocator, text);
}

fn appendKeyFormatReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, resource: u8, value: u16) host_state.ApplyError!void {
    const text = formatOutput(encode_buf, "\x1b[>{d};{d}f", .{ resource, value });
    try host_state.appendOutput(output, allocator, text);
}

fn appendXtVersionReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8)) host_state.ApplyError!void {
    try host_state.appendOutput(output, allocator, "\x1bP>|" ++ xtversion_text ++ "\x1b\\");
}

fn appendTermcapInvalidReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8)) host_state.ApplyError!void {
    try host_state.appendOutput(output, allocator, "\x1bP0+r\x1b\\");
}

fn appendResourceInvalidReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), request: []const u8) host_state.ApplyError!void {
    const start = host_state.byteCount(output.items);
    errdefer host_state.restorePendingOutput(output, start);
    try host_state.appendOutput(output, allocator, "\x1bP0+R");
    try host_state.appendOutput(output, allocator, request);
    try host_state.appendOutput(output, allocator, "\x1b\\");
}

fn appendTitleStackPositionReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, current: u16, max: u16) host_state.ApplyError!void {
    const text = formatOutput(encode_buf, "\x1b[{d};{d}#S", .{ current, max });
    try host_state.appendOutput(output, allocator, text);
}

fn appendCursorPositionReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, render_view: CursorReportView) host_state.ApplyError!void {
    const text = formatOutput(encode_buf, "\x1b[{d};{d}R", .{ render_view.cursor_row + 1, render_view.cursor_col + 1 });
    try host_state.appendOutput(output, allocator, text);
}

fn appendDecCursorPositionReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, render_view: CursorReportView) host_state.ApplyError!void {
    const text = formatOutput(encode_buf, "\x1b[?{d};{d}R", .{ render_view.cursor_row + 1, render_view.cursor_col + 1 });
    try host_state.appendOutput(output, allocator, text);
}

fn appendDecModeReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, mode: u16, state: u8) host_state.ApplyError!void {
    const text = formatOutput(encode_buf, "\x1b[?{d};{d}$y", .{ mode, state });
    try host_state.appendOutput(output, allocator, text);
}

fn appendAnsiModeReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, mode: u16, state: u8) host_state.ApplyError!void {
    const text = formatOutput(encode_buf, "\x1b[{d};{d}$y", .{ mode, state });
    try host_state.appendOutput(output, allocator, text);
}

fn appendColorStackReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, depth: u8) host_state.ApplyError!void {
    const text = formatOutput(encode_buf, "\x1b[{d};{d}#Q", .{ depth, depth });
    try host_state.appendOutput(output, allocator, text);
}

fn appendTabStopReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, screen: *const Grid) host_state.ApplyError!void {
    const start = host_state.byteCount(output.items);
    errdefer host_state.restorePendingOutput(output, start);
    try host_state.appendOutput(output, allocator, "\x1bP2$u");
    var first = true;
    var col: u16 = 0;
    while (col < screen.cols) : (col += 1) {
        if (!screen.tabStopAt(col)) continue;
        if (!first) try host_state.appendOutput(output, allocator, "/");
        first = false;
        const text = formatOutput(encode_buf, "{d}", .{col + 1});
        try host_state.appendOutput(output, allocator, text);
    }
    try host_state.appendOutput(output, allocator, "\x1b\\");
}

fn appendScreenExtentReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, render_view: CursorReportView) host_state.ApplyError!void {
    const text = formatOutput(encode_buf, "\x1b[{d};{d};1;1;1\"w", .{ render_view.rows, render_view.cols });
    try host_state.appendOutput(output, allocator, text);
}

fn appendTerminalParametersReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, kind: u16) host_state.ApplyError!void {
    if (kind > 1) return;
    const text = formatOutput(encode_buf, "\x1b[{d};1;1;128;128;1;0x", .{kind + 2});
    try host_state.appendOutput(output, allocator, text);
}

fn appendRectChecksumReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, req: RectChecksumRequest, checksum: u16) host_state.ApplyError!void {
    const text = formatOutput(encode_buf, "\x1bP{d}!~{X:0>4}\x1b\\", .{ req.request_id, checksum });
    try host_state.appendOutput(output, allocator, text);
}

fn appendSelectedGraphicRenditionReport(
    allocator: std.mem.Allocator,
    output: *std.ArrayList(u8),
    encode_buf: []u8,
    screen: *const Grid,
    area: rect.RectArea,
) host_state.ApplyError!void {
    const common = commonAttrsForRect(screen, area) orelse {
        try host_state.appendOutput(output, allocator, "\x1b[0m");
        return;
    };

    const start = host_state.byteCount(output.items);
    errdefer host_state.restorePendingOutput(output, start);
    try host_state.appendOutput(output, allocator, "\x1b[");
    var first = true;
    try appendSgrParam(allocator, output, &first, "0");
    if (common.bold) try appendSgrParam(allocator, output, &first, "1");
    if (common.dim) try appendSgrParam(allocator, output, &first, "2");
    if (common.italic) try appendSgrParam(allocator, output, &first, "3");
    if (common.underline) try appendSgrParam(allocator, output, &first, underlineStyleParam(common.underline_style));
    if (common.blink) try appendSgrParam(allocator, output, &first, "5");
    if (common.reverse) try appendSgrParam(allocator, output, &first, "7");
    if (common.invisible) try appendSgrParam(allocator, output, &first, "8");
    if (common.strikethrough) try appendSgrParam(allocator, output, &first, "9");
    try appendColorParam(allocator, output, encode_buf, &first, true, common.fg, Grid.default_cell_attrs.fg);
    try appendColorParam(allocator, output, encode_buf, &first, false, common.bg, Grid.default_cell_attrs.bg);
    if (common.underline and !colorEq(common.underline_color, Grid.default_underline_color)) {
        try appendExtendedColorParam(allocator, output, encode_buf, &first, 58, common.underline_color);
    }
    try host_state.appendOutput(output, allocator, "m");
}

fn computeRectChecksum(screen: *const Grid, xtchecksum_flags: u16, page: u16, area: rect.RectArea) u16 {
    if (page != 1) return 0;
    const bounds = screen.rectBounds(area) orelse return 0;
    var sum: u16 = 0;
    var row = bounds.top;
    while (row <= bounds.bottom) : (row += 1) {
        var col = bounds.left;
        while (col <= bounds.right) : (col += 1) {
            const cell = screen.cellInfoAt(row, col);
            const is_blank = cell.codepoint == 0;
            if (is_blank and (xtchecksum_flags & (1 << 2)) == 0) continue;
            var cp: u32 = cell.codepoint;
            if ((xtchecksum_flags & (1 << 4)) == 0) cp &= 0xff;
            sum +%= @intCast(cp & 0xffff);
            if ((xtchecksum_flags & (1 << 1)) == 0) {
                sum +%= if (cell.attrs.bold) 1 else 0;
                sum +%= if (cell.attrs.underline) 2 else 0;
                sum +%= if (cell.attrs.blink) 4 else 0;
                sum +%= if (cell.attrs.reverse) 8 else 0;
            }
        }
    }
    if ((xtchecksum_flags & (1 << 0)) == 0) sum = ~sum;
    return sum;
}

const CommonAttrs = struct {
    bold: bool,
    dim: bool,
    italic: bool,
    underline: bool,
    underline_style: Grid.UnderlineStyle,
    underline_color: Grid.Color,
    blink: bool,
    reverse: bool,
    invisible: bool,
    strikethrough: bool,
    fg: Grid.Color,
    bg: Grid.Color,
};

fn commonAttrsForRect(screen: *const Grid, area: rect.RectArea) ?CommonAttrs {
    const bounds = screen.rectBounds(area) orelse return null;
    const first_cell = screen.cellInfoAt(bounds.top, bounds.left);
    var common = CommonAttrs{
        .bold = first_cell.attrs.bold,
        .dim = first_cell.attrs.dim,
        .italic = first_cell.attrs.italic,
        .underline = first_cell.attrs.underline,
        .underline_style = first_cell.attrs.underline_style,
        .underline_color = first_cell.attrs.underline_color,
        .blink = first_cell.attrs.blink,
        .reverse = first_cell.attrs.reverse,
        .invisible = first_cell.attrs.invisible,
        .strikethrough = first_cell.attrs.strikethrough,
        .fg = first_cell.attrs.fg,
        .bg = first_cell.attrs.bg,
    };

    var row = bounds.top;
    while (row <= bounds.bottom) : (row += 1) {
        var col = bounds.left;
        while (col <= bounds.right) : (col += 1) {
            const attrs = screen.cellInfoAt(row, col).attrs;
            if (attrs.bold != common.bold) common.bold = false;
            if (attrs.dim != common.dim) common.dim = false;
            if (attrs.italic != common.italic) common.italic = false;
            if (attrs.underline != common.underline) common.underline = false;
            if (attrs.blink != common.blink) common.blink = false;
            if (attrs.reverse != common.reverse) common.reverse = false;
            if (attrs.invisible != common.invisible) common.invisible = false;
            if (attrs.strikethrough != common.strikethrough) common.strikethrough = false;
            if (attrs.underline_style != common.underline_style) common.underline_style = .straight;
            if (!colorEq(attrs.fg, common.fg)) common.fg = Grid.default_cell_attrs.fg;
            if (!colorEq(attrs.bg, common.bg)) common.bg = Grid.default_cell_attrs.bg;
            if (!colorEq(attrs.underline_color, common.underline_color)) common.underline_color = Grid.default_underline_color;
        }
    }
    if (!common.underline) {
        common.underline_style = .straight;
        common.underline_color = Grid.default_underline_color;
    }
    return common;
}

fn appendSgrParam(allocator: std.mem.Allocator, output: *std.ArrayList(u8), first: *bool, text: []const u8) host_state.ApplyError!void {
    if (!first.*) try host_state.appendOutput(output, allocator, ";");
    first.* = false;
    try host_state.appendOutput(output, allocator, text);
}

fn underlineStyleParam(style: Grid.UnderlineStyle) []const u8 {
    return switch (style) {
        .straight => "4",
        .double => "4:2",
        .curly => "4:3",
        .dotted => "4:4",
        .dashed => "4:5",
    };
}

fn appendColorParam(
    allocator: std.mem.Allocator,
    output: *std.ArrayList(u8),
    encode_buf: []u8,
    first: *bool,
    is_fg: bool,
    color: Grid.Color,
    default_color: Grid.Color,
) host_state.ApplyError!void {
    if (colorEq(color, default_color)) return;
    switch (color.kind) {
        .default => return,
        .indexed => {
            const idx: u8 = @truncate(color.value);
            if (idx < 16) {
                const code: u16 = if (is_fg)
                    (if (idx < 8) 30 + idx else 90 + (idx - 8))
                else
                    (if (idx < 8) 40 + idx else 100 + (idx - 8));
                const text = formatOutput(encode_buf, "{d}", .{code});
                try appendSgrParam(allocator, output, first, text);
                return;
            }
            try appendExtendedColorParam(allocator, output, encode_buf, first, if (is_fg) 38 else 48, color);
        },
        .rgb => try appendExtendedColorParam(allocator, output, encode_buf, first, if (is_fg) 38 else 48, color),
    }
}

fn appendExtendedColorParam(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, first: *bool, prefix: u8, color: Grid.Color) host_state.ApplyError!void {
    switch (color.kind) {
        .default => return,
        .indexed => {
            const text = formatOutput(encode_buf, "{d};5;{d}", .{ prefix, color.value });
            try appendSgrParam(allocator, output, first, text);
        },
        .rgb => {
            const text = formatOutput(encode_buf, "{d};2;{d};{d};{d}", .{
                prefix,
                (color.value >> 16) & 0xFF,
                (color.value >> 8) & 0xFF,
                color.value & 0xFF,
            });
            try appendSgrParam(allocator, output, first, text);
        },
    }
}

fn formatOutput(encode_buf: []u8, comptime fmt: []const u8, args: anytype) []const u8 {
    std.debug.assert(encode_buf.len >= format_output_max_bytes);
    return std.fmt.bufPrint(encode_buf, fmt, args) catch unreachable;
}

fn colorEq(a: Grid.Color, b: Grid.Color) bool {
    return a.kind == b.kind and a.value == b.value;
}

test "cursor style report payload reads semantic cursor owner" {
    var screen = Screen.init(2, 2);
    screen.setDefaultCursorStyle(.{ .shape = .underline, .blink = false });
    screen.applyScreen(.{ .cursor_style = .{ .program_override = .{ .shape = .bar, .blink = true } } });

    var encode_buf: [64]u8 = undefined;
    const overridden = decrqssPayload(encode_buf[0..], &screen, " q").?;
    try std.testing.expectEqualStrings("5 q", overridden);

    screen.applyScreen(.{ .cursor_style = .{ .program_override = .{ .shape = .block, .blink = true } } });
    const block_blink = decrqssPayload(encode_buf[0..], &screen, " q").?;
    try std.testing.expectEqualStrings("0 q", block_blink);

    screen.applyScreen(.{ .cursor_style = .{ .program_override = .{ .shape = .none, .blink = false } } });
    const no_shape = decrqssPayload(encode_buf[0..], &screen, " q").?;
    try std.testing.expectEqualStrings("1 q", no_shape);
}

test "cursor position report payload names semantic cursor position" {
    var output = std.ArrayList(u8).empty;
    defer output.deinit(std.testing.allocator);
    var encode_buf: [64]u8 = undefined;

    try appendCursorPositionReport(std.testing.allocator, &output, encode_buf[0..], .{
        .rows = 24,
        .cols = 80,
        .cursor_row = 2,
        .cursor_col = 4,
    });
    try std.testing.expectEqualStrings("\x1b[3;5R", output.items);
}
