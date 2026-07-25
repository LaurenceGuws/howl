//! Owns terminal semantic state, byte application, replies, and ordered consequences.

const std = @import("std");
const parser_mod = @import("parser.zig");
const graphics_mod = @import("graphics.zig");
const sixel = @import("sixel.zig");
const replies = @import("replies.zig");
const properties = @import("properties.zig");
const consequences = @import("consequences.zig");
const input = @import("input.zig");
const modes_mod = @import("modes.zig");
const charset_mod = @import("charset.zig");
const screen_mod = @import("screen.zig");
const Screen = screen_mod.Screen;
const copyOpenOutputLine = screen_mod.copyOpenOutputLine;
const CursorStyleCommand = screen_mod.CursorStyleCommand;
const OptionalRectArea = screen_mod.OptionalRectArea;
const OutputLossReason = screen_mod.OutputLossReason;
const RectArea = screen_mod.RectArea;
const RectCopy = screen_mod.RectCopy;
const ScreenCellAttrs = screen_mod.ScreenCellAttrs;
const ScreenCursorShape = screen_mod.ScreenCursorShape;
const ScreenEraseMode = screen_mod.ScreenEraseMode;
const ScreenProtection = screen_mod.ScreenProtection;

comptime {
    if (parser_mod.max_params > Screen.SgrOperands.capacity) {
        @compileError("parser SGR parameter bound exceeds Screen.SgrOperands capacity");
    }
    if (consequences.retained_packet_bytes_max != parser_mod.max_chunk_control_bytes) {
        @compileError("retained packet bound must match parser chunk-control bound");
    }
}

const sgr_stack_capacity = 10;
const sgr_stack_default_selection: u16 = 0b111_1111_1111;

// Retains one bounded selective rendition snapshot for XTPUSHSGR.
const SgrStackEntry = struct {
    attrs: ScreenCellAttrs = Screen.default_cell_attrs,
    selection: u16 = 0,
};

fn advanceIdentity(value: *u64) void {
    value.* = std.math.add(u64, value.*, 1) catch @panic("monotonic identity exhausted");
}
test "terminal resize commits both screen banks or preserves both exactly" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, resizeTerminalTransaction, .{false});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, resizeTerminalTransaction, .{true});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, resizeWithNotificationTransaction, .{});
}

fn resizeWithNotificationTransaction(allocator: std.mem.Allocator) !void {
    var terminal = try Terminal.initWithHistory(allocator, 2, 4, 8);
    defer terminal.deinit();
    try terminal.setCellPixelSize(9, 17);
    const enabled = try terminal.feed("\x1b[?2048h");
    try std.testing.expect(enabled.state_changed);

    terminal.resize(3, 5) catch |failure| {
        try std.testing.expectEqual(@as(u16, 2), terminal.screen_state.primary.rows);
        try std.testing.expectEqual(@as(u16, 4), terminal.screen_state.primary.cols);
        try std.testing.expectEqual(@as(u16, 2), terminal.screen_state.alternate.rows);
        try std.testing.expectEqual(@as(u16, 4), terminal.screen_state.alternate.cols);
        try std.testing.expectEqualStrings("", terminal.replyBytes());
        return failure;
    };
    try std.testing.expectEqualStrings("\x1b[48;3;5;51;45t", terminal.replyBytes());
}

fn resizeTerminalTransaction(allocator: std.mem.Allocator, alternate_active: bool) !void {
    var terminal = try Terminal.initWithHistory(allocator, 2, 4, 8);
    defer terminal.deinit();

    terminal.screen_state.primary.cells.?[0].codepoint = 'P';
    terminal.screen_state.primary.cells.?[1].codepoint = 'R';
    terminal.screen_state.alternate.cells.?[0].codepoint = 'A';
    terminal.screen_state.alternate.cells.?[1].codepoint = 'L';
    terminal.screen_state.alt_active = alternate_active;
    terminal.screen_state.primary.cursor.setDefaultStyle(.{ .shape = .bar, .blink = false });
    terminal.screen_state.alternate.cursor.setDefaultStyle(.{ .shape = .underline, .blink = true });
    terminal.screen_state.primary.left_right_margin_mode = true;
    terminal.screen_state.primary.left_margin = 1;
    terminal.screen_state.primary.right_margin = 2;
    const primary_history_count = terminal.screen_state.primary.historyCount();
    const primary_history_cell = terminal.screen_state.primary.historyRowAt(0, 0);
    const alternate_cell = terminal.screen_state.alternate.cellAt(0, 0);
    const semantic_sequence_before = terminal.semanticSequence();

    terminal.resize(3, 3) catch |err| {
        try std.testing.expectEqual(@as(u16, 2), terminal.screen_state.primary.rows);
        try std.testing.expectEqual(@as(u16, 4), terminal.screen_state.primary.cols);
        try std.testing.expectEqual(@as(u16, 2), terminal.screen_state.alternate.rows);
        try std.testing.expectEqual(@as(u16, 4), terminal.screen_state.alternate.cols);
        try std.testing.expectEqual(primary_history_count, terminal.screen_state.primary.historyCount());
        try std.testing.expectEqual(primary_history_cell, terminal.screen_state.primary.historyRowAt(0, 0));
        try std.testing.expectEqual(alternate_cell, terminal.screen_state.alternate.cellAt(0, 0));
        try std.testing.expectEqual(alternate_active, terminal.screen_state.alt_active);
        try std.testing.expectEqual(semantic_sequence_before, terminal.semanticSequence());
        try std.testing.expect(terminal.screen_state.primary.left_right_margin_mode);
        try std.testing.expectEqual(@as(u16, 1), terminal.screen_state.primary.left_margin);
        try std.testing.expectEqual(@as(u16, 2), terminal.screen_state.primary.right_margin);
        try std.testing.expectEqual(.bar, terminal.screen_state.primary.cursor.default_style.shape);
        try std.testing.expectEqual(.underline, terminal.screen_state.alternate.cursor.default_style.shape);
        terminal.screen_state.active().writeText("Z");
        return err;
    };

    try std.testing.expectEqual(@as(u16, 3), terminal.screen_state.primary.rows);
    try std.testing.expectEqual(@as(u16, 3), terminal.screen_state.primary.cols);
    try std.testing.expectEqual(@as(u16, 3), terminal.screen_state.alternate.rows);
    try std.testing.expectEqual(@as(u16, 3), terminal.screen_state.alternate.cols);
    try std.testing.expectEqual(alternate_active, terminal.screen_state.alt_active);
    try std.testing.expect(!terminal.screen_state.primary.left_right_margin_mode);
    try std.testing.expectEqual(@as(u16, 0), terminal.screen_state.primary.left_margin);
    try std.testing.expectEqual(@as(u16, 2), terminal.screen_state.primary.right_margin);
    try std.testing.expectEqual(.bar, terminal.screen_state.primary.cursor.default_style.shape);
    try std.testing.expectEqual(.underline, terminal.screen_state.alternate.cursor.default_style.shape);
    try std.testing.expectEqual(semantic_sequence_before + 1, terminal.semanticSequence());
}
// Terminal modes, replies, and bounded host-neutral consequences.

// Carries Kitty keyboard flags and the set, add, or remove operation mode.
const KeyFormatChange = struct {
    resource: ?u8,
    value: ?u16,
};

// Retains the exact mode set selected by Kitty's parameterless XTSAVE extension.
const SavedAllModes = struct {
    newline_mode: bool = false,
    insert_mode: bool = false,
    auto_repeat: bool = false,
    bracketed_paste: bool = false,
    focus_reporting: bool = false,
    color_preference_notifications: bool = false,
    paste_events: bool = false,
    inband_resize_notifications: bool = false,
    application_cursor_keys: bool = false,
    cursor_visible: bool = false,
    auto_wrap: bool = false,
    mouse_tracking: input.MouseTrackingMode = .off,
    mouse_protocol: input.MouseProtocol = .none,
    reverse_screen_mode: bool = false,
};

// Borrows the DEC mode facts required to answer one mode query.
const DecView = struct {
    application_cursor_keys: bool,
    application_keypad: bool,
    column_mode_132: bool,
    allow_column_mode: bool,
    preserve_screen_on_column_mode: bool,
    more_fix: bool,
    auto_repeat: bool,
    reverse_screen_mode: bool,
    origin_mode: bool,
    auto_wrap: bool,
    left_right_margin_mode: bool,
    cursor_blink: bool,
    cursor_visible: bool,
    alt_active: bool,
    mouse_tracking: input.MouseTrackingMode,
    mouse_protocol: input.MouseProtocol,
    focus_reporting: bool,
    alternate_scroll: bool,
    meta_sends_escape: bool,
    report_key_up: bool,
    bracketed_paste: bool,
    synchronized_output: bool,
    inband_resize_notifications: bool,
    color_preference_notifications: bool,
    paste_events: bool,
    reverse_wraparound: bool,
    extended_reverse_wraparound: bool,
    sixel_display_mode: bool,
};

// Borrows the ANSI mode facts required to answer one mode query.
const AnsiView = struct {
    keyboard_action_mode: bool,
    insert_mode: bool,
    send_receive_mode: bool,
    newline_mode: bool,
};

// Returns the DEC mode report state for a supported numeric mode.
fn decModeStateForView(view: DecView, mode: u16) u8 {
    return switch (mode) {
        1 => boolToDecModeState(view.application_cursor_keys),
        3 => boolToDecModeState(view.allow_column_mode and view.column_mode_132),
        40 => boolToDecModeState(view.allow_column_mode),
        41 => boolToDecModeState(view.more_fix),
        95 => boolToDecModeState(view.preserve_screen_on_column_mode),
        5 => boolToDecModeState(view.reverse_screen_mode),
        6 => boolToDecModeState(view.origin_mode),
        7 => boolToDecModeState(view.auto_wrap),
        8 => boolToDecModeState(view.auto_repeat),
        12 => boolToDecModeState(view.cursor_blink),
        45 => boolToDecModeState(view.reverse_wraparound),
        69 => boolToDecModeState(view.left_right_margin_mode),
        80 => boolToDecModeState(view.sixel_display_mode),
        66 => boolToDecModeState(view.application_keypad),
        25 => boolToDecModeState(view.cursor_visible),
        47, 1047, 1049 => boolToDecModeState(view.alt_active),
        9 => if (view.mouse_tracking == .x10) 1 else 2,
        1000 => if (view.mouse_tracking == .normal) 1 else 2,
        1002 => if (view.mouse_tracking == .button_event) 1 else 2,
        1003 => if (view.mouse_tracking == .any_event) 1 else 2,
        1004 => boolToDecModeState(view.focus_reporting),
        1005 => boolToDecModeState(view.mouse_protocol == .utf8),
        1006 => boolToDecModeState(view.mouse_protocol == .sgr),
        1007 => boolToDecModeState(view.alternate_scroll),
        1016 => boolToDecModeState(view.mouse_protocol == .sgr_pixel),
        1015 => boolToDecModeState(view.mouse_protocol == .urxvt),
        1036 => boolToDecModeState(view.meta_sends_escape),
        1337 => boolToDecModeState(view.report_key_up),
        2004 => boolToDecModeState(view.bracketed_paste),
        2026 => boolToDecModeState(view.synchronized_output),
        2048 => boolToDecModeState(view.inband_resize_notifications),
        2031 => boolToDecModeState(view.color_preference_notifications),
        5522 => boolToDecModeState(view.paste_events),
        1045 => boolToDecModeState(view.extended_reverse_wraparound),
        else => 0,
    };
}

// Returns the ANSI mode report state for a supported numeric mode.
fn ansiModeStateForView(view: AnsiView, mode: u16) u8 {
    return switch (mode) {
        2 => boolToDecModeState(view.keyboard_action_mode),
        4 => boolToDecModeState(view.insert_mode),
        12 => boolToDecModeState(view.send_receive_mode),
        20 => boolToDecModeState(view.newline_mode),
        else => 0,
    };
}

fn boolToDecModeState(enabled: bool) u8 {
    return if (enabled) 1 else 2;
}

fn replaceBool(target: *bool, value: bool) bool {
    if (target.* == value) return false;
    target.* = value;
    return true;
}

const locator_report_max_bytes = 40;

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

// Stores DEC locator reporting mode, filter rectangle, and one-shot event flags.
const Locator = struct {
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

// Sets locator reporting and coordinate units, disabling unsupported values.
fn setReporting(state: *Locator, mode: u16, unit: u16) void {
    state.mode = switch (mode) {
        1 => .continuous,
        2 => .one_shot,
        else => .disabled,
    };
    state.coordinate_unit = unit;
}

// Installs an optional locator filter rectangle and clears its outside latch.
fn setFilter(state: *Locator, area: OptionalRectArea) void {
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

// Replaces one-shot locator event flags from borrowed numeric modes.
fn setEvents(state: *Locator, modes: []const u16) void {
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

// Appends a bounded locator status or position reply for one request parameter.
fn appendReportForRequest(
    state: *Locator,
    allocator: std.mem.Allocator,
    output: *replies.Buffer,
    encode_buf: []u8,
    param: u16,
) replies.AppendError!void {
    if (param > 1) return;
    if (state.mode == .disabled or state.last_row == null or state.last_col == null) {
        try output.appendCsi(.terminal, "0&w");
        return;
    }
    try appendReport(
        state,
        allocator,
        output,
        encode_buf,
        1,
        state.last_buttons_down,
        state.last_row.?,
        state.last_col.?,
    );
}

// Appends the supported locator device-status reply for parameter 53.
fn appendDeviceStatusReport(
    _: std.mem.Allocator,
    output: *replies.Buffer,
    encode_buf: []u8,
    param: u16,
) replies.AppendError!void {
    const text = switch (param) {
        55 => std.fmt.bufPrint(encode_buf, "?50n", .{}) catch unreachable,
        56 => std.fmt.bufPrint(encode_buf, "?57;1n", .{}) catch unreachable,
        else => return,
    };
    try output.appendCsi(.terminal, text);
}

// Updates representable locator coordinates and appends enabled reports.
//
// Rows outside the retained `u16` coordinate domain are ignored. Report
// allocation or capacity failure preserves one-shot and filter latches.
fn handleMouseEvent(
    state: *Locator,
    allocator: std.mem.Allocator,
    output: *replies.Buffer,
    encode_buf: []u8,
    event: input.MouseEvent,
) replies.AppendError!void {
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

fn appendReport(
    state: *Locator,
    _: std.mem.Allocator,
    output: *replies.Buffer,
    encode_buf: []u8,
    event_code: u16,
    buttons_down: u8,
    row: u16,
    col: u16,
) replies.AppendError!void {
    const button_mask = buttonsMask(buttons_down);
    const coords = coordinates(state, row, col);
    std.debug.assert(encode_buf.len >= locator_report_max_bytes);
    const text = std.fmt.bufPrint(
        encode_buf,
        "{d};{d};{d};{d};0&w",
        .{ event_code, button_mask, coords.row + 1, coords.col + 1 },
    ) catch unreachable;
    try output.appendCsi(.terminal, text);
    if (state.mode == .one_shot) state.mode = .disabled;
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

const ClipboardRequestKind = consequences.ClipboardRequestKind;
const ClipboardProtocol = consequences.ClipboardProtocol;
const ClipboardRequestView = consequences.ClipboardRequestView;

const ParsedClipboardRequest = struct {
    selection: []const u8,
    data: []const u8,
    kind: ClipboardRequestKind,
};

const ClipboardHostReplyError = ApplyError || error{StaleClipboardRequest};

// Reports allocation failure or rejection by a concrete retained-consequence bound.
const ApplyError = error{
    OutOfMemory,
    ConsequenceLimit,
    ReplyLimit,
    PropertyLimit,
};

/// OSC 52 names four standard selections and eight numbered cut buffers.
const clipboard_selection_bytes_max: u8 = 12;
/// One query reply fits regardless of selection length and 7-bit framing.
const clipboard_reply_bytes_max: u32 =
    ((replies.max_bytes - clipboard_selection_bytes_max - 8) / 4) * 3;
/// Bounds aggregate bytes retained across configuration, delegated transport, and host-directed DCS consequences.
const dcs_payload_max_bytes: u32 = 2 * 1024;
/// Bounds one retained consequence payload owned by this composition state.
const consequence_payload_max_bytes: u32 = 1024;
const pointer_shape_reply_max_bytes: u32 = (consequence_payload_max_bytes / 12) * 14 - 1;
// Owns the latest bounded OSC 133 shell mark.
const ShellMark = properties.ShellMark;

/// Projects the consequence owner's notification classification.
pub const NotificationKind = consequences.NotificationKind;
/// Projects the consequence owner's borrowed notification view.
pub const Notification = consequences.Notification;

/// Projects the consequence owner's borrowed pointer-shape request.
pub const PointerShapeRequest = consequences.PointerShapeRequest;

/// Projects the consequence owner's file-transfer protocol identity.
pub const FileTransferProtocol = consequences.FileTransferProtocol;
/// Projects the consequence owner's borrowed file-transfer packet.
pub const FileTransferPacket = consequences.FileTransferPacket;

const drag_drop_capacity: u8 = 16;
const drag_drop_packet_max_bytes: u32 = 4096;
const drag_drop_aggregate_max_bytes: u32 = 32 * 1024;
const drag_drop_data_max_bytes: u32 = 3072;

/// Projects the consequence owner's drag-and-drop classification.
pub const DragDropCommandKind = consequences.DragDropCommandKind;
/// Projects the consequence owner's borrowed drag-and-drop command.
pub const DragDropCommandView = consequences.DragDropCommandView;

/// Selects one bounded Kitty OSC 72 error returned to the child.
pub const DragDropError = enum {
    invalid,
    permission,
    io,
    resource,

    fn bytes(self: DragDropError) []const u8 {
        return switch (self) {
            .invalid => "EINVAL",
            .permission => "EPERM",
            .io => "EIO",
            .resource => "EMFILE",
        };
    }
};

/// Supplies one host fact serialized through Kitty OSC 72 framing.
pub const DragDropEventValue = union(enum) {
    query: struct { client_id: ?u32 },
    move: struct {
        client_id: ?u32,
        cell_x: u16,
        cell_y: u16,
        pixel_x: i32,
        pixel_y: i32,
        operation: u2,
        mimes: []const u8,
        drop: bool,
    },
    leave: struct { client_id: ?u32 },
    data: struct { client_id: ?u32, index: u32, more: bool, bytes: []const u8 },
    failure: struct { client_id: ?u32, index: ?u32, reason: DragDropError },
};

/// Projects the consequence owner's window-request vocabulary.
pub const WindowRequest = consequences.WindowRequest;

/// Projects the consequence owner's borrowed window request.
pub const WindowRequestOccurrence = consequences.WindowRequestOccurrence;

/// Projects the consequence owner's media-copy request.
pub const MediaCopyRequest = consequences.MediaCopyRequest;

/// Projects the consequence owner's borrowed media-copy occurrence.
pub const MediaCopyOccurrence = consequences.MediaCopyOccurrence;

/// Supplies one host-owned fact requested by a retained window query.
pub const WindowReply = union(enum) {
    state: enum { normal, iconified },
    position: struct { x: u32, y: u32 },
    screen_cells: struct { rows: u32, cols: u32 },
    icon_title: []const u8,
};

// Owns validated shell-integration identity until replacement or deinit.
const ShellIntegration = properties.ShellIntegration;

// Borrows one child-reported directory and preserves whether its bytes are a URI or path.
const WorkingDirectoryReport = properties.WorkingDirectory;

const TitleStackEffect = properties.TitleStackEffect;

comptime {
    std.debug.assert(dcs_payload_max_bytes <= replies.max_bytes);
    std.debug.assert(clipboard_reply_bytes_max < replies.max_bytes);
}

// Converts a slice length after asserting it fits the protocol-owned u32 domain.
fn byteCount(bytes: []const u8) u32 {
    std.debug.assert(bytes.len <= std.math.maxInt(u32));
    return @intCast(bytes.len);
}

fn hyperlinkCount(items: []const HyperlinkTarget) u32 {
    std.debug.assert(items.len <= std.math.maxInt(u32));
    return @intCast(items.len);
}

// Borrows one parsed OSC 8 hyperlink until the parser dispatch returns.
const HyperlinkSpec = properties.HyperlinkSpec;
const HyperlinkTarget = properties.HyperlinkTarget;

fn appendClipboardQueryReply(
    output: *replies.Buffer,
    allocator: std.mem.Allocator,
    selection: []const u8,
    bytes: []const u8,
) ApplyError!void {
    if (bytes.len > clipboard_reply_bytes_max) return error.ConsequenceLimit;
    const encoded_len = std.base64.standard.Encoder.calcSize(bytes.len);
    const prefix_len = std.math.add(usize, 4, selection.len) catch
        return error.ConsequenceLimit;
    const payload_len = std.math.add(usize, prefix_len, encoded_len) catch
        return error.ConsequenceLimit;
    if (payload_len > replies.max_bytes) return error.ReplyLimit;
    const payload = try allocator.alloc(u8, payload_len);
    defer allocator.free(payload);
    @memcpy(payload[0..3], "52;");
    @memcpy(payload[3 .. 3 + selection.len], selection);
    payload[prefix_len - 1] = ';';
    const encoded = std.base64.standard.Encoder.encode(payload[prefix_len..], bytes);
    std.debug.assert(encoded.len == encoded_len);
    try output.appendString(.terminal, .osc, payload);
}

fn ensureRetainedBound(len: u32, max_len: u32) ApplyError!void {
    if (len > max_len) return error.ConsequenceLimit;
}

fn optionalBytesEqual(current: ?[]const u8, replacement: []const u8) bool {
    return if (current) |bytes| std.mem.eql(u8, bytes, replacement) else false;
}

// Borrows one parsed OSC 133 shell mark until parser mutation.
const ItermShellMark = struct {
    kind: u8,
    status: ?i32,
    metadata: []const u8,
};

// Borrows a decimal version and optional bounded `shell` identity.
// Duplicate, malformed, or unknown suffix keys reject the complete update.
const ItermShellIntegration = struct {
    version: u32,
    shell: ?[]const u8,
};

// Bounds one shell name without creating a generic metadata namespace.
const max_shell_name_bytes: u8 = 32;

// Names iTerm controls whose effects are safe inside the native terminal contract.
const ItermCommand = union(enum) {
    cursor_shape: ScreenCursorShape,
    report_cell_size,
    set_colors: []const u8,
    shell_integration: ItermShellIntegration,
    current_directory: []const u8,
    remote_host: []const u8,
    clear_scrollback,
    notification: []const u8,
    steal_focus,
    request_attention: []const u8,
    file_transfer: []const u8,
};

// Decodes one borrowed OSC 50 or 1337 payload under its exact command family.
fn parse(osc_command: u16, payload: []const u8) ?ItermCommand {
    return switch (osc_command) {
        50 => parseCursorShape(payload),
        1337 => parse1337(payload),
        else => null,
    };
}

fn parse1337(payload: []const u8) ?ItermCommand {
    const separator = std.mem.indexOfScalar(u8, payload, '=') orelse {
        return if (std.mem.eql(u8, payload, "ReportCellSize"))
            .report_cell_size
        else if (std.mem.eql(u8, payload, "StealFocus"))
            .steal_focus
        else if (std.mem.eql(u8, payload, "ClearScrollback"))
            .clear_scrollback
        else if (std.mem.eql(u8, payload, "RequestAttention"))
            .{ .request_attention = "" }
        else
            null;
    };
    const key = payload[0..separator];
    const value = payload[separator + 1 ..];
    // iTerm ignores the value of this request key.
    if (std.mem.eql(u8, key, "ReportCellSize")) return .report_cell_size;
    if (std.mem.eql(u8, key, "CursorShape")) return parseCursorShape(payload);
    if (std.mem.eql(u8, key, "SetColors")) return .{ .set_colors = value };
    if (std.mem.eql(u8, key, "CurrentDir")) return .{ .current_directory = value };
    if (std.mem.eql(u8, key, "RemoteHost")) return .{ .remote_host = value };
    if (std.mem.eql(u8, key, "ClearScrollback")) return .clear_scrollback;
    if (std.mem.eql(u8, key, "Notification")) return .{ .notification = value };
    // iTerm ignores an optional StealFocus value after recognizing the key.
    if (std.mem.eql(u8, key, "StealFocus")) return .steal_focus;
    if (std.mem.eql(u8, key, "RequestAttention")) return .{ .request_attention = value };
    if (std.mem.eql(u8, key, "File") or
        std.mem.eql(u8, key, "MultipartFile") or
        std.mem.eql(u8, key, "FilePart") or
        std.mem.eql(u8, key, "FileEnd")) return .{ .file_transfer = payload };
    if (std.mem.eql(u8, key, "ShellIntegrationVersion"))
        return .{ .shell_integration = parseShellIntegration(value) orelse return null };
    return null;
}

fn parseCursorShape(payload: []const u8) ?ItermCommand {
    const prefix = "CursorShape=";
    if (!std.mem.startsWith(u8, payload, prefix)) return null;
    const value = payload[prefix.len..];
    if (value.len != 1) return null;
    return .{ .cursor_shape = switch (value[0]) {
        '0' => .block,
        '1' => .bar,
        '2' => .underline,
        else => return null,
    } };
}

fn parseShellIntegration(payload: []const u8) ?ItermShellIntegration {
    var parts = std.mem.splitScalar(u8, payload, ';');
    const version_text = parts.next() orelse return null;
    if (version_text.len == 0) return null;
    const version = std.fmt.parseUnsigned(u32, version_text, 10) catch return null;
    var shell: ?[]const u8 = null;
    while (parts.next()) |part| {
        const separator = std.mem.indexOfScalar(u8, part, '=') orelse return null;
        const key = part[0..separator];
        const value = part[separator + 1 ..];
        if (!std.mem.eql(u8, key, "shell") or shell != null or
            value.len == 0 or value.len > max_shell_name_bytes)
            return null;
        for (value) |byte| if (!isShellNameByte(byte)) return null;
        shell = value;
    }
    return .{ .version = version, .shell = shell };
}

fn isShellNameByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or
        byte == '.' or byte == '_' or byte == '+' or byte == '-';
}

// Parses one OSC 133 mark and the first positional command-exit status.
fn parseShellMark(payload: []const u8) ?ItermShellMark {
    if (payload.len == 0) return null;
    const separator = std.mem.indexOfScalar(u8, payload, ';') orelse payload.len;
    if (separator != 1) return null;
    const kind = payload[0];
    switch (kind) {
        'A', 'B', 'C', 'D' => {},
        else => return null,
    }
    const metadata = if (separator < payload.len) payload[separator + 1 ..] else "";
    const status = if (kind == 'D') parseShellExitStatus(metadata) else null;
    return .{ .kind = kind, .status = status, .metadata = metadata };
}

// Ignores key-value attributes and returns the first complete signed decimal field.
fn parseShellExitStatus(metadata: []const u8) ?i32 {
    var fields = std.mem.splitScalar(u8, metadata, ';');
    while (fields.next()) |field| {
        if (field.len == 0 or std.mem.indexOfScalar(u8, field, '=') != null) continue;
        if (std.fmt.parseInt(i32, field, 10)) |status| return status else |_| {}
    }
    return null;
}

test "iTerm safe controls decode without accepting policy commands" {
    try std.testing.expect(parse(1337, "ReportCellSize").? == .report_cell_size);
    try std.testing.expect(parse(1337, "ReportCellSize=ignored").? == .report_cell_size);
    try std.testing.expectEqual(ScreenCursorShape.bar, parse(50, "CursorShape=1").?.cursor_shape);
    try std.testing.expectEqual(ScreenCursorShape.bar, parse(1337, "CursorShape=1").?.cursor_shape);
    try std.testing.expectEqualStrings("fg=fff", parse(1337, "SetColors=fg=fff").?.set_colors);
    try std.testing.expectEqualStrings("/work/tree", parse(1337, "CurrentDir=/work/tree").?.current_directory);
    try std.testing.expectEqualStrings("hello", parse(1337, "Notification=hello").?.notification);
    try std.testing.expect(parse(1337, "StealFocus").? == .steal_focus);
    try std.testing.expect(parse(1337, "StealFocus=ignored").? == .steal_focus);
    try std.testing.expectEqualStrings("", parse(1337, "RequestAttention").?.request_attention);
    try std.testing.expectEqualStrings("fireworks", parse(1337, "RequestAttention=fireworks").?.request_attention);
    try std.testing.expectEqualStrings("FilePart=QQ==", parse(1337, "FilePart=QQ==").?.file_transfer);
    const integration = parse(1337, "ShellIntegrationVersion=20;shell=bash").?.shell_integration;
    try std.testing.expectEqual(@as(u32, 20), integration.version);
    try std.testing.expectEqualStrings("bash", integration.shell.?);
    try std.testing.expect(parse(1337, "ShellIntegrationVersion=20;shell=bash;shell=zsh") == null);
    try std.testing.expect(parse(1337, "ShellIntegrationVersion=20;unknown=value") == null);
    try std.testing.expect(parse(1337, "ShellIntegrationVersion=broken;shell=bash") == null);
    try std.testing.expect(parse(50, "CursorShape=9") == null);
    try std.testing.expect(parse(50, "SetColors=fg=fff") == null);
    try std.testing.expect(parse(50, "ShellIntegrationVersion=20;shell=bash") == null);
    try std.testing.expect(parse(50, "ReportCellSize") == null);
    try std.testing.expect(parse(49, "CursorShape=1") == null);
}

const KittyColorState = properties.ColorState;

// Selects one terminal-owned Kitty color-stack operation and its zero-based stack convention.
const KittyColorCommand = union(enum) {
    push: u16,
    pop: u16,
};

// Stores Kitty's ten bounded color slots, sequential depth, and initialized slot extent.
const KittyColorStack = properties.ColorStack;

// Applies one Kitty color control or appends its bounded query reply.
fn handleKittyControl(
    allocator: std.mem.Allocator,
    colors: *KittyColorState,
    output: *replies.Buffer,
    payload: []const u8,
) ApplyError!void {
    var parts = std.mem.splitScalar(u8, payload, ';');
    while (parts.next()) |raw_part| {
        const part = std.mem.trim(u8, raw_part, " \t\r\n");
        if (part.len == 0) continue;
        const eq = std.mem.indexOfScalar(u8, part, '=');
        if (eq) |pos| {
            const key = std.mem.trim(u8, part[0..pos], " \t");
            const value = std.mem.trim(u8, part[pos + 1 ..], " \t");
            if (std.mem.eql(u8, value, "?")) {
                try appendKittyQueryReply(allocator, output, key, colors.*);
            } else {
                setColorKey(colors, key, value);
            }
        } else {
            resetColorKey(colors, std.mem.trim(u8, part, " \t"));
        }
    }
}
fn appendKittyQueryReply(
    allocator: std.mem.Allocator,
    output: *replies.Buffer,
    key: []const u8,
    colors: KittyColorState,
) ApplyError!void {
    const start = byteCount(output.bytes());
    errdefer output.truncate(start);
    try output.appendControl(.kitty, .osc);
    try output.append("21;");
    try output.append(key);
    try output.append("=");
    if (colorForKey(colors, key)) |color| {
        try appendColorOsc(allocator, output, color);
    } else if (isKnownColorKey(key)) {
        // Empty value means dynamic/undefined for Kitty color control.
    } else {
        try output.append("?");
    }
    try output.appendControl(.kitty, .st);
}

const key_report_max_bytes = 16;

/// Projects the consequence owner's DCS classification.
pub const DcsPayloadKind = consequences.DcsPayloadKind;
/// Projects the consequence owner's borrowed DCS occurrence.
pub const DcsPayloadOccurrence = consequences.DcsPayloadOccurrence;
/// Projects the consequence owner's generic string-control classification.
pub const StringPayloadKind = consequences.StringPayloadKind;
/// Projects the consequence owner's borrowed string-control occurrence.
pub const StringPayloadOccurrence = consequences.StringPayloadOccurrence;
/// Projects the consequence owner's legacy-control classification.
pub const LegacyControlKind = consequences.LegacyControlKind;
/// Projects the consequence owner's borrowed legacy-control occurrence.
pub const LegacyControlOccurrence = consequences.LegacyControlOccurrence;

// Borrows one terminal color key and optional replacement value.
const TerminalColorControlCommand = struct {
    command: u16,
    payload: []const u8,
};

// Borrows one complete OSC 66 metadata and text payload for synchronous application.
const TextSizeCommand = struct {
    payload: []const u8,
};

// Parser events to canonical terminal semantics.

/// Canonical parser-to-domain event consumed synchronously by terminal state owners.
const SemanticEvent = union(enum) {
    cursor_up: u16,
    cursor_down: u16,
    cursor_forward: u16,
    cursor_back: u16,
    cursor_next_line: u16,
    cursor_prev_line: u16,
    cursor_horizontal_absolute: u16,
    cursor_vertical_absolute: u16,
    cursor_position: struct { row: u16, col: u16 },
    write_text: []const u8,
    write_codepoint: u21,
    repeat_preceding: u16,
    bell,
    line_feed,
    next_line,
    reverse_index,
    forward_index,
    back_index,
    carriage_return,
    backspace,
    horizontal_tab,
    horizontal_tab_forward: u16,
    horizontal_tab_back: u16,
    horizontal_tab_set,
    tab_clear_current,
    tab_clear_all,
    cursor_visible: bool,
    cursor_blink: bool,
    cursor_style: CursorStyleCommand,
    cursor_shape: ScreenCursorShape,
    cursor_color: ?Screen.Rgb,
    cursor_text_color: ?Screen.Rgb,
    reverse_screen_mode: bool,
    eight_bit_controls: bool,
    auto_wrap: bool,
    auto_repeat: bool,
    origin_mode: bool,
    insert_mode: bool,
    application_cursor_keys: bool,
    application_keypad: bool,
    column_mode_132: bool,
    allow_column_mode: bool,
    preserve_screen_on_column_mode: bool,
    more_fix: bool,
    ansi_mode_set: ModeParams,
    ansi_mode_reset: ModeParams,
    ansi_mode_query: u16,
    modify_other_keys_set: i8,
    modify_other_keys_query,
    modify_other_keys_disable,
    key_format_change: KeyFormatChange,
    key_format_query: u8,
    pointer_mode: u2,
    reverse_wraparound_mode: bool,
    extended_reverse_wraparound_mode: bool,
    focus_reporting: bool,
    alternate_scroll: bool,
    meta_sends_escape: bool,
    report_key_up: bool,
    bracketed_paste: bool,
    synchronized_output: bool,
    inband_resize_notifications: bool,
    color_preference_notifications: bool,
    paste_events: bool,
    termios_signals: bool,
    mouse_tracking_off,
    mouse_tracking_x10,
    mouse_tracking_normal,
    mouse_tracking_button_event,
    mouse_tracking_any_event,
    mouse_protocol_utf8: bool,
    mouse_protocol_sgr: bool,
    mouse_protocol_urxvt: bool,
    mouse_protocol_sgr_pixel: bool,
    kitty_keyboard_set: struct { flags: u8, mode: u8 },
    kitty_keyboard_query,
    kitty_keyboard_push: u8,
    kitty_keyboard_pop: u16,
    shell_mark: ItermShellMark,
    notification: struct { kind: NotificationKind, command: u16, payload: []const u8 },
    pointer_shape: []const u8,
    text_size: TextSizeCommand,
    window_request: WindowRequest,
    color_preference_query,
    kitty_color_stack: KittyColorCommand,
    sgr_stack_push: ModeParams,
    sgr_stack_pop,
    title_and_icon_set: []const u8,
    title_set: []const u8,
    icon_set: []const u8,
    shell_integration_set: ItermShellIntegration,
    working_directory_report: WorkingDirectoryReport,
    remote_host_report: []const u8,
    clear_buffer,
    iterm_report_cell_size,
    iterm_set_colors: []const u8,
    color_control: TerminalColorControlCommand,
    hyperlink_set: HyperlinkSpec,
    hyperlink_clear,
    clipboard_set: []const u8,
    kitty_clipboard_packet: []const u8,
    file_transfer_packet: struct { protocol: FileTransferProtocol, payload: []const u8 },
    drag_drop: ParsedDragDrop,
    dec_mode_query: u16,
    dec_mode_set: ModeParams,
    dec_mode_reset: ModeParams,
    dec_mode_save: ModeParams,
    dec_mode_restore: ModeParams,
    dcs_request_status: []const u8,
    dcs_request_termcap: []const u8,
    dcs_request_resource: []const u8,
    restore_cursor_information: []const u8,
    restore_tab_stops: []const u8,
    restore_cursor_appearance,
    dcs_payload: consequences.DcsInput,
    string_payload: consequences.StringInput,
    device_status_report,
    dec_device_status_report: u16,
    cursor_position_report,
    dec_cursor_position_report,
    primary_device_attributes,
    secondary_device_attributes,
    tertiary_device_attributes,
    xtversion,
    xttitlepos,
    xtchecksum: u16,
    rect_checksum_request: struct { request_id: u16, page: u16, area: RectArea },
    selected_graphic_rendition_report: RectArea,
    screen_extent_report,
    parameters_report: u16,
    size_report: SizeReport,
    window_title_report,
    title_stack: struct { command: TitleStackCommand, option: u16 },
    xtreportcolors,
    locator_reporting: struct { mode: u16, unit: u16 },
    locator_filter: OptionalRectArea,
    locator_events: ModeParams,
    locator_request: u16,
    media_copy_request: MediaCopyRequest,
    legacy_control: LegacyControlKind,
    sgr: struct {
        params: []const i32,
        separators: parser_mod.CsiSeparatorList,
    },
    enter_alt_screen: struct { clear: bool, save_cursor: bool },
    exit_alt_screen: struct { restore_cursor: bool },
    save_cursor,
    restore_cursor,
    insert_lines: u16,
    delete_lines: u16,
    insert_chars: u16,
    delete_chars: u16,
    scroll_up_lines: u16,
    scroll_down_lines: u16,
    scroll_down_from_history: u16,
    set_scroll_region: struct {
        top: u16,
        bottom: ?u16,
    },
    hard_reset,
    soft_reset,
    erase_display_below: bool,
    erase_display_above: bool,
    erase_display_complete: bool,
    erase_display_scrollback: bool,
    erase_display_scroll_complete: bool,
    erase_line: ScreenEraseMode,
    selective_erase_line: ScreenEraseMode,
    erase_chars: u16,
    shift_left_columns: u16,
    shift_right_columns: u16,
    character_protection: ScreenProtection,
    rect_erase: RectArea,
    rect_selective_erase: RectArea,
    rect_fill: struct { area: RectArea, ch: u21 },
    rect_copy: RectCopy,
    rect_attrs_change: struct { area: RectArea, attrs: AttrParams, reverse: bool },
    insert_columns: u16,
    delete_columns: u16,
    attr_change_extent_rect: bool,
    left_right_margin_mode: bool,
    set_left_right_margins: struct { left: u16, right: ?u16 },
    reset_default_tab_stops,
};

// Narrows terminal-wide semantic routing to the finite mutations owned by Screen.
fn screenAction(event: SemanticEvent) ?Screen.Action {
    return switch (event) {
        .cursor_up => |value| .{ .cursor_up = value },
        .cursor_down => |value| .{ .cursor_down = value },
        .cursor_forward => |value| .{ .cursor_forward = value },
        .cursor_back => |value| .{ .cursor_back = value },
        .cursor_next_line => |value| .{ .cursor_next_line = value },
        .cursor_prev_line => |value| .{ .cursor_prev_line = value },
        .cursor_horizontal_absolute => |value| .{ .cursor_horizontal_absolute = value },
        .cursor_vertical_absolute => |value| .{ .cursor_vertical_absolute = value },
        .cursor_position => |value| .{ .cursor_position = .{ .row = value.row, .col = value.col } },
        .write_text => |value| .{ .write_text = value },
        .write_codepoint => |value| .{ .write_codepoint = value },
        .line_feed => .line_feed,
        .next_line => .next_line,
        .carriage_return => .carriage_return,
        .backspace => .backspace,
        .horizontal_tab => .horizontal_tab,
        .horizontal_tab_forward => |value| .{ .horizontal_tab_forward = value },
        .horizontal_tab_back => |value| .{ .horizontal_tab_back = value },
        .horizontal_tab_set => .horizontal_tab_set,
        .tab_clear_current => .tab_clear_current,
        .tab_clear_all => .tab_clear_all,
        .reset_default_tab_stops => .reset_default_tab_stops,
        .cursor_visible => |value| .{ .cursor_visible = value },
        .cursor_style => |value| .{ .cursor_style = value },
        .cursor_shape => |value| .{ .cursor_shape = value },
        .cursor_color => |value| .{ .cursor_color = value },
        .cursor_text_color => |value| .{ .cursor_text_color = value },
        .auto_wrap => |value| .{ .auto_wrap = value },
        .origin_mode => |value| .{ .origin_mode = value },
        .insert_mode => |value| .{ .insert_mode = value },
        .left_right_margin_mode => |value| .{ .left_right_margin_mode = value },
        .hard_reset => .hard_reset,
        else => null,
    };
}

fn screenSgrOperands(
    values: []const i32,
    separators: parser_mod.CsiSeparatorList,
) Screen.SgrOperands {
    std.debug.assert(values.len <= parser_mod.max_params);
    var colon_after: u32 = 0;
    for (0..values.len) |index| {
        if (separators.isSet(index)) colon_after |= @as(u32, 1) << @intCast(index);
    }
    return .{ .values = values, .colon_after = colon_after };
}

// Selects one terminal-owned cell or host-supplied pixel size report.
const SizeReport = enum {
    window_pixels,
    cell_pixels,
    text_cells,
};

const TitleStackCommand = enum {
    push,
    pop,
};

const C0Action = enum {
    bell,
    line_feed,
    carriage_return,
    backspace,
    horizontal_tab,
};

const C0 = enum(u8) {
    bell = 0x07,
    backspace = 0x08,
    horizontal_tab = 0x09,
    line_feed = 0x0A,
    vertical_tab = 0x0B,
    form_feed = 0x0C,
    carriage_return = 0x0D,
    file_separator = 0x1C,
    group_separator = 0x1D,
    record_separator = 0x1E,
    unit_separator = 0x1F,
    _,
};

// Classifies one byte as its exact C0 code without rejecting unknown values.
fn fromByte(byte: u8) C0 {
    return @fromBackingInt(@intCast(byte));
}

fn c0Action(control: C0) ?C0Action {
    return switch (control) {
        .bell => .bell,
        .line_feed, .vertical_tab, .form_feed => .line_feed,
        .carriage_return => .carriage_return,
        .backspace => .backspace,
        .horizontal_tab => .horizontal_tab,
        else => null,
    };
}

// Converts a C0 code into its terminal mutation, or null when it is ignored.
fn c0Process(control: C0) ?SemanticEvent {
    switch (control) {
        .file_separator => return SemanticEvent{ .legacy_control = .tek_point_plot },
        .group_separator => return SemanticEvent{ .legacy_control = .tek_graph },
        .record_separator => return SemanticEvent{ .legacy_control = .tek_incremental_plot },
        .unit_separator => return SemanticEvent{ .legacy_control = .tek_alpha },
        else => {},
    }
    const mapped = c0Action(control) orelse return null;
    return switch (mapped) {
        .bell => SemanticEvent.bell,
        .line_feed => SemanticEvent.line_feed,
        .carriage_return => SemanticEvent.carriage_return,
        .backspace => SemanticEvent.backspace,
        .horizontal_tab => SemanticEvent.horizontal_tab,
    };
}

// Selects the 7-bit ESC alias for implemented C1 bytes; all other bytes retain C0 handling.
fn controlProcess(control: u8) ?SemanticEvent {
    return switch (control) {
        0x84 => escProcess('D'),
        0x85 => escProcess('E'),
        0x88 => escProcess('H'),
        0x8D => escProcess('M'),
        0x96 => escProcess('V'),
        0x97 => escProcess('W'),
        else => c0Process(fromByte(control)),
    };
}

test "c0 handled controls keep protocol values" {
    try std.testing.expectEqual(@as(u8, 0x07), @backingInt(C0.bell));
    try std.testing.expectEqual(@as(u8, 0x08), @backingInt(C0.backspace));
    try std.testing.expectEqual(@as(u8, 0x09), @backingInt(C0.horizontal_tab));
    try std.testing.expectEqual(@as(u8, 0x0A), @backingInt(C0.line_feed));
    try std.testing.expectEqual(@as(u8, 0x0B), @backingInt(C0.vertical_tab));
    try std.testing.expectEqual(@as(u8, 0x0C), @backingInt(C0.form_feed));
    try std.testing.expectEqual(@as(u8, 0x0D), @backingInt(C0.carriage_return));
}

test "c0 maps line and cursor stream controls" {
    try std.testing.expect(c0Process(.bell).? == .bell);
    try std.testing.expect(c0Process(.line_feed).? == .line_feed);
    try std.testing.expect(c0Process(.vertical_tab).? == .line_feed);
    try std.testing.expect(c0Process(.form_feed).? == .line_feed);
    try std.testing.expect(c0Process(.carriage_return).? == .carriage_return);
    try std.testing.expect(c0Process(.backspace).? == .backspace);
    try std.testing.expect(c0Process(.horizontal_tab).? == .horizontal_tab);
}

test "c0 legacy controls map host-neutral state" {
    try std.testing.expectEqual(LegacyControlKind.tek_point_plot, c0Process(.file_separator).?.legacy_control);
    try std.testing.expectEqual(LegacyControlKind.tek_graph, c0Process(.group_separator).?.legacy_control);
    try std.testing.expectEqual(LegacyControlKind.tek_incremental_plot, c0Process(.record_separator).?.legacy_control);
    try std.testing.expectEqual(LegacyControlKind.tek_alpha, c0Process(.unit_separator).?.legacy_control);
}

test "c0 ignores unsupported controls" {
    try std.testing.expectEqual(@as(?SemanticEvent, null), c0Process(fromByte(0x00)));
}

// Routes one completed borrowed CSI sequence; unsupported combinations return null.
fn csiProcess(
    final: u8,
    params: []const i32,
    separators: parser_mod.CsiSeparatorList,
    leader_byte: u8,
    is_private: bool,
    intermediates: []const u8,
) ?SemanticEvent {
    if (is_private) return decodePrivateCsi(final, params, leader_byte, intermediates);
    if (leader_byte != 0) return decodeCsiLeader(final, params, leader_byte, intermediates);
    if (decodeCsiIntermediate(final, params, intermediates)) |event| return event;
    return decodeCsi(final, params, separators, intermediates);
}

// Decodes one CSI sequence with intermediates; unsupported forms return null.
fn decodeCsiIntermediate(final: u8, params: []const i32, intermediates: []const u8) ?SemanticEvent {
    if (intermediates.len == 2) return processPair(final, params, intermediates);
    if (intermediates.len != 1) return null;
    return switch (intermediates[0]) {
        '"' => processQuote(final, params),
        '$' => processDollar(final, params),
        '*' => processStar(final, params),
        '+' => processPlus(final, params),
        '#' => processHash(final, params),
        '\'' => processTick(final, params),
        ' ' => processSpace(final, params),
        else => null,
    };
}

fn processPair(final: u8, params: []const i32, intermediates: []const u8) ?SemanticEvent {
    if (intermediates[0] != '\'' or intermediates[1] != '*') return null;
    if (final != '{') return null;
    return SemanticEvent{ .locator_events = collectParams(params) };
}

fn processQuote(final: u8, params: []const i32) ?SemanticEvent {
    if (final == 'q') {
        return switch (paramAtOrDefault0(params, 0)) {
            0, 2 => SemanticEvent{ .character_protection = .none },
            1 => SemanticEvent{ .character_protection = .dec },
            else => null,
        };
    }
    if (final == 'v') return SemanticEvent.screen_extent_report;
    return null;
}

fn processDollar(final: u8, params: []const i32) ?SemanticEvent {
    return switch (final) {
        'p' => if (queryParam(params)) |mode| SemanticEvent{ .ansi_mode_query = mode } else null,
        'r' => rectAttrsChange(params, false),
        't' => rectAttrsChange(params, true),
        'v' => rectCopy(params),
        'x' => rectFill(params),
        'z' => rectErase(params, false),
        '{' => rectErase(params, true),
        '|' => if (params.len <= 1) switch (paramAtOrDefault0(params, 0)) {
            0, 80 => SemanticEvent{ .window_request = .{ .resize_columns = .columns_80 } },
            132 => SemanticEvent{ .window_request = .{ .resize_columns = .columns_132 } },
            else => null,
        } else null,
        else => null,
    };
}

fn processStar(final: u8, params: []const i32) ?SemanticEvent {
    if (final == 'x') {
        return switch (paramAtOrDefault0(params, 0)) {
            0, 1 => SemanticEvent{ .attr_change_extent_rect = false },
            2 => SemanticEvent{ .attr_change_extent_rect = true },
            else => null,
        };
    }
    if (final == '|') {
        if (params.len != 1 or params[0] <= 0 or params[0] >= 256) return null;
        return SemanticEvent{ .window_request = .{ .resize_rows = @intCast(params[0]) } };
    }
    if (final != 'y') return null;
    const area = rectArea(params, 2) orelse return null;
    return SemanticEvent{ .rect_checksum_request = .{
        .request_id = paramAtOrDefault0(params, 0),
        .page = paramAtOrDefault1(params, 1),
        .area = area,
    } };
}

fn processPlus(final: u8, params: []const i32) ?SemanticEvent {
    return switch (final) {
        'T' => SemanticEvent{ .scroll_down_from_history = paramAtOrDefault1(params, 0) },
        else => null,
    };
}

fn processHash(final: u8, params: []const i32) ?SemanticEvent {
    return switch (final) {
        'p', '{' => SemanticEvent{ .sgr_stack_push = collectParams(params) },
        'q', '}' => SemanticEvent.sgr_stack_pop,
        'P' => SemanticEvent{ .kitty_color_stack = .{ .push = queryParam(params) orelse return null } },
        'Q' => SemanticEvent{ .kitty_color_stack = .{ .pop = queryParam(params) orelse return null } },
        'S' => SemanticEvent.xttitlepos,
        'y' => SemanticEvent{ .xtchecksum = paramAtOrDefault0(params, 0) },
        'R' => SemanticEvent.xtreportcolors,
        '|' => if (rectArea(params, 0)) |area|
            SemanticEvent{ .selected_graphic_rendition_report = area }
        else
            null,
        else => null,
    };
}

fn processTick(final: u8, params: []const i32) ?SemanticEvent {
    return switch (final) {
        'w' => SemanticEvent{ .locator_filter = optionalRectArea(params) },
        '}' => SemanticEvent{ .insert_columns = paramAtOrDefault1(params, 0) },
        'z' => SemanticEvent{ .locator_reporting = .{
            .mode = paramAtOrDefault0(params, 0),
            .unit = paramAtOrDefault0(params, 1),
        } },
        '|' => SemanticEvent{ .locator_request = paramAtOrDefault0(params, 0) },
        '~' => SemanticEvent{ .delete_columns = paramAtOrDefault1(params, 0) },
        else => null,
    };
}

fn processSpace(final: u8, params: []const i32) ?SemanticEvent {
    return switch (final) {
        'q' => SemanticEvent{
            .cursor_style = cursorStyle(paramAtOrDefault0(params, 0)) orelse return null,
        },
        '@' => SemanticEvent{ .shift_left_columns = paramAtOrDefault1(params, 0) },
        'A' => SemanticEvent{ .shift_right_columns = paramAtOrDefault1(params, 0) },
        else => null,
    };
}

fn rectAttrsChange(params: []const i32, reverse: bool) ?SemanticEvent {
    if (params.len < 5) return null;
    const area = rectArea(params, 0) orelse return null;
    return .{ .rect_attrs_change = .{
        .area = area,
        .attrs = attrParams(params, 4),
        .reverse = reverse,
    } };
}

fn rectCopy(params: []const i32) ?SemanticEvent {
    const area = rectArea(params, 0) orelse return null;
    return .{ .rect_copy = .{
        .area = area,
        .source_page = paramAtOrDefault1(params, 4),
        .dest_top = paramAtOrDefault1(params, 5) - 1,
        .dest_left = paramAtOrDefault1(params, 6) - 1,
        .dest_page = paramAtOrDefault1(params, 7),
    } };
}

fn rectFill(params: []const i32) ?SemanticEvent {
    const ch = paramAtOrDefault0(params, 0);
    if (!isValidRectFillChar(ch)) return null;
    const area = rectArea(params, 1) orelse return null;
    return .{ .rect_fill = .{ .area = area, .ch = ch } };
}

fn rectErase(params: []const i32, selective: bool) ?SemanticEvent {
    const area = rectArea(params, 0) orelse return null;
    return if (selective)
        SemanticEvent{ .rect_selective_erase = area }
    else
        SemanticEvent{ .rect_erase = area };
}

// Decodes one leader-qualified CSI sequence; unsupported forms return null.
fn decodeCsiLeader(final: u8, params: []const i32, leader: u8, intermediates: []const u8) ?SemanticEvent {
    return switch (leader) {
        '>' => switch (final) {
            'c' => if (intermediates.len == 0 and zeroQuery(params))
                SemanticEvent.secondary_device_attributes
            else
                null,
            'f' => keyFormatChange(params),
            'q' => if (!intermediatesHas(intermediates, ' ') and
                paramAtOrDefault0(params, 0) == 0)
                SemanticEvent.xtversion
            else
                null,
            'm' => if (paramAtOrDefault0(params, 0) == 4)
                SemanticEvent{ .modify_other_keys_set = @intCast(
                    @max(if (params.len >= 2) params[1] else 0, 0),
                ) }
            else
                null,
            'n' => if (paramAtOrDefault0(params, 0) == 4) SemanticEvent.modify_other_keys_disable else null,
            'p' => pointerMode(params),
            'u' => SemanticEvent{ .kitty_keyboard_push = keyboardFlags(params) },
            else => null,
        },
        '=' => switch (final) {
            'c' => if (intermediates.len == 0 and zeroQuery(params))
                SemanticEvent.tertiary_device_attributes
            else
                null,
            'u' => decodeKittyKeyboardSet(params),
            else => null,
        },
        '<' => switch (final) {
            'u' => SemanticEvent{ .kitty_keyboard_pop = paramAtOrDefault1(params, 0) },
            else => null,
        },
        else => null,
    };
}

fn decodeKittyKeyboardSet(params: []const i32) ?SemanticEvent {
    const raw_mode = if (params.len >= 2) params[1] else 1;
    if (raw_mode < 1 or raw_mode > 3) return null;
    return SemanticEvent{ .kitty_keyboard_set = .{
        .flags = keyboardFlags(params),
        .mode = @intCast(raw_mode),
    } };
}

fn keyboardFlags(params: []const i32) u8 {
    const raw: u32 = @intCast(@max(if (params.len != 0) params[0] else 0, 0));
    return @intCast(raw & modes_mod.kitty_keyboard_flag_mask);
}

fn keyFormatChange(params: []const i32) SemanticEvent {
    if (params.len == 0) return SemanticEvent{ .key_format_change = .{ .resource = null, .value = null } };
    const resource = keyFormatParamAtOrDefault0(params, 0);
    if (params.len == 1) return SemanticEvent{ .key_format_change = .{ .resource = resource, .value = null } };
    return SemanticEvent{ .key_format_change = .{ .resource = resource, .value = paramAtOrDefault0(params, 1) } };
}

fn pointerMode(params: []const i32) SemanticEvent {
    const value = if (params.len == 0) 1 else paramAtOrDefault0(params, 0);
    return SemanticEvent{ .pointer_mode = @intCast(@min(value, 3)) };
}

// Stores one parser-bounded parameter list as clamped u16 values.
const ModeParams = struct {
    params: [parser_mod.max_params]u16,
    param_count: u8,
};

fn sgrSelection(params: ModeParams) u16 {
    if (params.param_count == 0) return sgr_stack_default_selection;
    var selection: u16 = 0;
    for (params.params[0..params.param_count]) |param| {
        const bit: ?u4 = switch (param) {
            1 => 0,
            2 => 1,
            3 => 2,
            4 => 3,
            5 => 4,
            7 => 5,
            8 => 6,
            9 => 7,
            21 => 8,
            30 => 9,
            31 => 10,
            else => null,
        };
        if (bit) |value| selection |= @as(u16, 1) << value;
    }
    return selection;
}

fn restoreSelectedSgr(current: *ScreenCellAttrs, entry: SgrStackEntry) void {
    if (entry.selection & (1 << 0) != 0) current.bold = entry.attrs.bold;
    if (entry.selection & (1 << 1) != 0) current.dim = entry.attrs.dim;
    if (entry.selection & (1 << 2) != 0) current.italic = entry.attrs.italic;
    if (entry.selection & (1 << 3) != 0) {
        current.underline = entry.attrs.underline;
        current.underline_style = entry.attrs.underline_style;
    } else if (entry.selection & (1 << 8) != 0) {
        if (!entry.attrs.underline) {
            current.underline = false;
            current.underline_style = .straight;
        } else if (entry.attrs.underline_style == .double) {
            current.underline = true;
            current.underline_style = .double;
        }
    }
    if (entry.selection & (1 << 4) != 0) {
        current.blink = entry.attrs.blink;
        current.blink_fast = entry.attrs.blink_fast;
    }
    if (entry.selection & (1 << 5) != 0) current.reverse = entry.attrs.reverse;
    if (entry.selection & (1 << 6) != 0) current.invisible = entry.attrs.invisible;
    if (entry.selection & (1 << 7) != 0) current.strikethrough = entry.attrs.strikethrough;
    if (entry.selection & (1 << 9) != 0) current.fg = entry.attrs.fg;
    if (entry.selection & (1 << 10) != 0) current.bg = entry.attrs.bg;
}

// Stores a bounded suffix of clamped u16 rectangular attribute values.
const AttrParams = struct {
    params: [parser_mod.max_params]u16,
    param_count: u8,
};

fn paramCount32(items: []const i32) u32 {
    std.debug.assert(items.len <= std.math.maxInt(u32));
    return @intCast(items.len);
}

// Projects positive one-based parameters into optional zero-based rectangle edges.
fn optionalRectArea(params: []const i32) OptionalRectArea {
    return .{
        .top = if (params.len >= 1 and params[0] > 0) paramOrDefault1(params[0]) - 1 else null,
        .left = if (params.len >= 2 and params[1] > 0) paramOrDefault1(params[1]) - 1 else null,
        .bottom = if (params.len >= 3 and params[2] > 0) paramOrDefault1(params[2]) - 1 else null,
        .right = if (params.len >= 4 and params[3] > 0) paramOrDefault1(params[3]) - 1 else null,
    };
}

// Projects a parameter suffix into an ordered zero-based rectangle with open lower defaults.
fn rectArea(params: []const i32, start_idx: u8) ?RectArea {
    const start = @as(u32, start_idx);
    const param_len = paramCount32(params);
    const area: RectArea = .{
        .top = if (param_len > start) paramOrDefault1(params[@intCast(start)]) - 1 else 0,
        .left = if (param_len > start + 1) paramOrDefault1(params[@intCast(start + 1)]) - 1 else 0,
        .bottom = if (param_len > start + 2) paramOrDefault1(params[@intCast(start + 2)]) - 1 else null,
        .right = if (param_len > start + 3) paramOrDefault1(params[@intCast(start + 3)]) - 1 else null,
    };
    if (area.bottom) |bottom| if (area.top > bottom) return null;
    if (area.right) |right| if (area.left > right) return null;
    return area;
}

// Copies a bounded parameter suffix into rectangular attribute storage.
fn attrParams(params: []const i32, start_idx: u8) AttrParams {
    var out = @as([parser_mod.max_params]u16, @splat(0));
    const param_len = paramCount32(params);
    var idx: u8 = start_idx;
    var dst: u8 = 0;
    while (idx < param_len and dst < parser_mod.max_params) : ({
        idx += 1;
        dst += 1;
    }) {
        out[@intCast(dst)] = paramOrDefault0(params[@intCast(idx)]);
    }
    return .{ .params = out, .param_count = @intCast(dst) };
}

// Accepts the ECMA-48 graphic ranges permitted by DECFRA.
fn isValidRectFillChar(ch: u16) bool {
    return (ch >= 32 and ch <= 126) or (ch >= 160 and ch <= 255);
}

// Returns one for absent or nonpositive parameters and clamps positive values to u16.
fn paramAtOrDefault1(params: []const i32, idx: u8) u16 {
    return if (paramCount32(params) > idx) paramOrDefault1(params[idx]) else 1;
}

// Returns zero for absent or nonpositive parameters and clamps positive values to u16.
fn paramAtOrDefault0(params: []const i32, idx: u8) u16 {
    return if (paramCount32(params) > idx) paramOrDefault0(params[idx]) else 0;
}

// Returns an absent-zero key-format parameter clamped to u8.
fn keyFormatParamAtOrDefault0(params: []const i32, idx: u8) u8 {
    return @intCast(@min(paramAtOrDefault0(params, idx), std.math.maxInt(u8)));
}

// Maps a numeric erase parameter to the terminal erase domain.
fn eraseMode(v: i32) ?ScreenEraseMode {
    return switch (v) {
        0 => .cursor_to_end,
        1 => .start_to_cursor,
        2 => .all,
        3 => .scrollback,
        else => null,
    };
}

fn lineEraseMode(v: i32) ?ScreenEraseMode {
    const mode = eraseMode(v) orelse return null;
    return if (mode == .scrollback) null else mode;
}

// Maps DECSCUSR parameters to an explicit cursor-style command.
fn cursorStyle(param: u16) ?CursorStyleCommand {
    return switch (param) {
        0 => .restore_default,
        1 => .{ .program_override = .{ .shape = .block, .blink = true } },
        2 => .{ .program_override = .{ .shape = .block, .blink = false } },
        3 => .{ .program_override = .{ .shape = .underline, .blink = true } },
        4 => .{ .program_override = .{ .shape = .underline, .blink = false } },
        5 => .{ .program_override = .{ .shape = .bar, .blink = true } },
        6 => .{ .program_override = .{ .shape = .bar, .blink = false } },
        else => null,
    };
}

// Copies parser-bounded mode parameters into clamped u16 storage.
fn collectParams(params: []const i32) ModeParams {
    var out = @as([parser_mod.max_params]u16, @splat(0));
    const n = @min(paramCount32(params), parser_mod.max_params);
    var idx: u8 = 0;
    while (idx < n) : (idx += 1) out[@intCast(idx)] = paramOrDefault0(params[@intCast(idx)]);
    return .{ .params = out, .param_count = @intCast(n) };
}

fn paramOrDefault1(v: i32) u16 {
    if (v <= 0) return 1;
    if (v > std.math.maxInt(u16)) return std.math.maxInt(u16);
    return @intCast(v);
}

fn paramOrDefault0(v: i32) u16 {
    if (v <= 0) return 0;
    if (v > std.math.maxInt(u16)) return std.math.maxInt(u16);
    return @intCast(v);
}

// Reports whether a borrowed intermediate-byte sequence contains one byte.
fn intermediatesHas(intermediates: []const u8, needle: u8) bool {
    return std.mem.indexOfScalar(u8, intermediates, needle) != null;
}

// Decodes one ordinary CSI sequence; unsupported forms return null.
fn decodeCsi(
    final: u8,
    params: []const i32,
    separators: parser_mod.CsiSeparatorList,
    intermediates: []const u8,
) ?SemanticEvent {
    switch (final) {
        '@' => return SemanticEvent{ .insert_chars = paramAtOrDefault1(params, 0) },
        'A' => return SemanticEvent{ .cursor_up = paramAtOrDefault1(params, 0) },
        'B', 'e' => return SemanticEvent{ .cursor_down = paramAtOrDefault1(params, 0) },
        'C', 'a' => return SemanticEvent{ .cursor_forward = paramAtOrDefault1(params, 0) },
        'b' => return SemanticEvent{ .repeat_preceding = paramAtOrDefault1(params, 0) },
        'D' => return SemanticEvent{ .cursor_back = paramAtOrDefault1(params, 0) },
        'j' => return SemanticEvent{ .cursor_back = paramAtOrDefault1(params, 0) },
        'k' => return SemanticEvent{ .cursor_up = paramAtOrDefault1(params, 0) },
        'E' => return SemanticEvent{ .cursor_next_line = paramAtOrDefault1(params, 0) },
        'F' => return SemanticEvent{ .cursor_prev_line = paramAtOrDefault1(params, 0) },
        'G', '`' => return SemanticEvent{ .cursor_horizontal_absolute = paramAtOrDefault1(params, 0) - 1 },
        'd' => return SemanticEvent{ .cursor_vertical_absolute = paramAtOrDefault1(params, 0) - 1 },
        'I' => return SemanticEvent{ .horizontal_tab_forward = paramAtOrDefault1(params, 0) },
        'g' => switch (paramAtOrDefault0(params, 0)) {
            0 => return SemanticEvent.tab_clear_current,
            3, 5 => return SemanticEvent.tab_clear_all,
            else => return null,
        },
        'Z' => return SemanticEvent{ .horizontal_tab_back = paramAtOrDefault1(params, 0) },
        'L' => return SemanticEvent{ .insert_lines = paramAtOrDefault1(params, 0) },
        'M' => return SemanticEvent{ .delete_lines = paramAtOrDefault1(params, 0) },
        'P' => return SemanticEvent{ .delete_chars = paramAtOrDefault1(params, 0) },
        'S' => return SemanticEvent{ .scroll_up_lines = paramAtOrDefault1(params, 0) },
        'T' => return SemanticEvent{ .scroll_down_lines = paramAtOrDefault1(params, 0) },
        'h' => return SemanticEvent{ .ansi_mode_set = collectParams(params) },
        'l' => return SemanticEvent{ .ansi_mode_reset = collectParams(params) },
        'm' => return SemanticEvent{ .sgr = .{ .params = params, .separators = separators } },
        's' => if (params.len == 0)
            return SemanticEvent.save_cursor
        else
            return SemanticEvent{ .set_left_right_margins = .{
                .left = paramAtOrDefault1(params, 0) - 1,
                .right = if (params.len >= 2 and params[1] > 0)
                    paramAtOrDefault1(params, 1) - 1
                else
                    null,
            } },
        'u' => return SemanticEvent.restore_cursor,
        'H', 'f' => {
            const row = paramAtOrDefault1(params, 0);
            const col = paramAtOrDefault1(params, 1);
            return SemanticEvent{ .cursor_position = .{ .row = row - 1, .col = col - 1 } };
        },
        'r' => return SemanticEvent{ .set_scroll_region = .{
            .top = paramAtOrDefault1(params, 0) - 1,
            .bottom = if (params.len >= 2 and params[1] > 0) paramAtOrDefault1(params, 1) - 1 else null,
        } },
        'J' => return decodeEraseDisplay(eraseMode(paramAtOrDefault0(params, 0)) orelse return null, false),
        'K' => return SemanticEvent{
            .erase_line = lineEraseMode(paramAtOrDefault0(params, 0)) orelse return null,
        },
        'X' => return SemanticEvent{ .erase_chars = paramAtOrDefault1(params, 0) },
        'i' => {
            if (intermediates.len != 0) return null;
            return SemanticEvent{ .media_copy_request = .{
                .private = false,
                .parameter = queryParam(params) orelse return null,
            } };
        },
        'x' => {
            if (intermediates.len != 0) return null;
            const kind = queryParam(params) orelse return null;
            return SemanticEvent{ .parameters_report = kind };
        },
        't' => {
            if (intermediates.len != 0 or params.len == 0) return null;
            if (params[0] == 22 or params[0] == 23) {
                if (params.len > 3 or (params.len == 3 and params[2] != 0)) return null;
                if (params.len >= 2 and params[1] < 0) return null;
                const command: TitleStackCommand = if (params[0] == 22) .push else .pop;
                return SemanticEvent{ .title_stack = .{
                    .command = command,
                    .option = paramAtOrDefault0(params, 1),
                } };
            }
            if (decodeWindowRequest(params)) |request| return .{ .window_request = request };
            if (params.len > 2) return null;
            if (params.len == 2 and params[1] < 0) return null;
            return switch (params[0]) {
                14 => SemanticEvent{ .size_report = .window_pixels },
                16 => SemanticEvent{ .size_report = .cell_pixels },
                18 => SemanticEvent{ .size_report = .text_cells },
                21 => if (params.len == 1) SemanticEvent.window_title_report else null,
                else => null,
            };
        },
        'n' => {
            if (intermediates.len != 0) return null;
            return switch (queryParam(params) orelse return null) {
                5 => SemanticEvent.device_status_report,
                6 => SemanticEvent.cursor_position_report,
                else => null,
            };
        },
        'c' => {
            if (intermediates.len != 0 or !zeroQuery(params)) return null;
            return SemanticEvent.primary_device_attributes;
        },
        'p' => {
            if (params.len == 0 and intermediates.len == 1 and intermediates[0] == '!') {
                return SemanticEvent.soft_reset;
            }
            return null;
        },
        else => return null,
    }
}

// Decodes only host-directed xterm window operations with complete nonnegative arguments.
fn decodeWindowRequest(params: []const i32) ?WindowRequest {
    if (params.len == 0) return null;
    return switch (params[0]) {
        1 => if (params.len == 1) .deiconify else null,
        2 => if (params.len == 1) .iconify else null,
        3 => blk: {
            if (params.len > 3) break :blk null;
            const x = if (params.len > 1) nonnegativeParam(params[1]) orelse break :blk null else 0;
            const y = if (params.len > 2) nonnegativeParam(params[2]) orelse break :blk null else 0;
            break :blk .{ .move = .{ .x = x, .y = y } };
        },
        4 => if (params.len == 3) .{ .resize_pixels = .{
            .height = nonnegativeParam(params[1]) orelse return null,
            .width = nonnegativeParam(params[2]) orelse return null,
        } } else null,
        5 => if (params.len == 1) .raise else null,
        6 => if (params.len == 1) .lower else null,
        8 => if (params.len == 3) .{ .resize_cells = .{
            .rows = nonnegativeParam(params[1]) orelse return null,
            .cols = nonnegativeParam(params[2]) orelse return null,
        } } else null,
        11 => if (params.len == 1) .report_state else null,
        13 => if (params.len == 1) .report_position else null,
        19 => if (params.len == 1) .report_screen_cells else null,
        20 => if (params.len == 1) .report_icon_title else null,
        else => null,
    };
}

fn nonnegativeParam(param: i32) ?u32 {
    if (param < 0) return null;
    return @intCast(param);
}

fn decodeEraseDisplay(mode: ScreenEraseMode, protected: bool) SemanticEvent {
    return switch (mode) {
        .cursor_to_end => SemanticEvent{ .erase_display_below = protected },
        .start_to_cursor => SemanticEvent{ .erase_display_above = protected },
        .all => SemanticEvent{ .erase_display_complete = protected },
        .scrollback => SemanticEvent{ .erase_display_scrollback = protected },
    };
}

// Decodes one private CSI sequence; unsupported forms return null.
fn decodePrivateCsi(final: u8, params: []const i32, leader: u8, intermediates: []const u8) ?SemanticEvent {
    if (leader != '?') return null;
    if (directQuery(final, params, intermediates)) |event| return event;
    if (saveRestore(final, params, intermediates)) |event| return event;
    if (params.len == 0) return null;
    if (modeReport(final, params, intermediates)) |event| return event;
    if (report(final, params, intermediates)) |event| return event;
    if (intermediates.len != 0) return null;
    if (final == 'h') return SemanticEvent{ .dec_mode_set = collectParams(params) };
    if (final == 'l') return SemanticEvent{ .dec_mode_reset = collectParams(params) };
    return null;
}

fn directQuery(final: u8, params: []const i32, intermediates: []const u8) ?SemanticEvent {
    if (intermediates.len != 0) return null;
    switch (final) {
        'u' => return SemanticEvent.kitty_keyboard_query,
        'g' => return SemanticEvent{ .key_format_query = keyFormatParamAtOrDefault0(params, 0) },
        'J' => return decodePrivateEraseDisplay(
            eraseMode(paramAtOrDefault0(params, 0)) orelse return null,
            true,
        ),
        'K' => return SemanticEvent{
            .selective_erase_line = lineEraseMode(paramAtOrDefault0(params, 0)) orelse return null,
        },
        'W' => if (paramAtOrDefault0(params, 0) == 5) return SemanticEvent.reset_default_tab_stops,
        else => {},
    }
    return null;
}

fn decodePrivateEraseDisplay(mode: ScreenEraseMode, protected: bool) SemanticEvent {
    return switch (mode) {
        .cursor_to_end => SemanticEvent{ .erase_display_below = protected },
        .start_to_cursor => SemanticEvent{ .erase_display_above = protected },
        .all => SemanticEvent{ .erase_display_complete = protected },
        .scrollback => SemanticEvent{ .erase_display_scrollback = protected },
    };
}

fn modeReport(final: u8, params: []const i32, intermediates: []const u8) ?SemanticEvent {
    if (final == 'm' and paramAtOrDefault0(params, 0) == 4) return SemanticEvent.modify_other_keys_query;
    if (final == 'p' and intermediates.len == 1 and intermediates[0] == '$') {
        const mode = queryParam(params) orelse return null;
        return SemanticEvent{ .dec_mode_query = mode };
    }
    return null;
}

fn saveRestore(final: u8, params: []const i32, intermediates: []const u8) ?SemanticEvent {
    if (intermediates.len != 0) return null;
    return switch (final) {
        's' => SemanticEvent{ .dec_mode_save = collectParams(params) },
        'r' => SemanticEvent{ .dec_mode_restore = collectParams(params) },
        else => null,
    };
}

fn report(final: u8, params: []const i32, intermediates: []const u8) ?SemanticEvent {
    if (intermediates.len != 0) return null;
    const param = queryParam(params) orelse return null;
    return switch (final) {
        'i' => SemanticEvent{ .media_copy_request = .{ .private = true, .parameter = param } },
        'n' => switch (param) {
            5 => SemanticEvent.device_status_report,
            6 => SemanticEvent.dec_cursor_position_report,
            55, 56 => |status| SemanticEvent{ .dec_device_status_report = status },
            996 => SemanticEvent.color_preference_query,
            else => null,
        },
        else => null,
    };
}

// Returns one default-zero scalar and rejects trailing query parameters.
fn queryParam(params: []const i32) ?u16 {
    if (params.len > 1) return null;
    return paramAtOrDefault0(params, 0);
}

fn zeroQuery(params: []const i32) bool {
    return (queryParam(params) orelse return false) == 0;
}

const DcsEvent = @FieldType(parser_mod.Event, "dcs");

// Decodes one completed borrowed DCS payload; unsupported commands return null.
fn dcsProcess(dcs: DcsEvent) ?SemanticEvent {
    if (dcs.intermediates_len == 1 and dcs.intermediates[0] == '=' and
        dcs.final == 's' and dcs.param_count == 1)
    {
        return switch (dcs.params[0]) {
            1 => .{ .synchronized_output = true },
            2 => .{ .synchronized_output = false },
            else => null,
        };
    }
    if (dcs.intermediates_len == 1 and dcs.intermediates[0] == '$' and dcs.final == 'q')
        return SemanticEvent{ .dcs_request_status = dcs.payload };
    if (dcs.intermediates_len == 1 and dcs.intermediates[0] == '+' and dcs.final == 'q')
        return SemanticEvent{ .dcs_request_termcap = dcs.payload };
    if (dcs.intermediates_len == 1 and dcs.intermediates[0] == '+' and dcs.final == 'Q')
        return SemanticEvent{ .dcs_request_resource = dcs.payload };
    if (dcs.intermediates_len == 1 and dcs.intermediates[0] == '+' and dcs.final == 'p')
        return SemanticEvent{ .dcs_payload = .{ .kind = .xtsettcap, .payload = dcs.payload } };
    if (dcs.intermediates_len == 1 and dcs.intermediates[0] == '$' and dcs.final == 't') {
        if (dcs.param_count != 1) return null;
        return switch (dcs.params[0]) {
            1 => SemanticEvent{ .restore_cursor_information = dcs.payload },
            2 => SemanticEvent{ .restore_tab_stops = dcs.payload },
            else => null,
        };
    }
    if (dcs.final == '|') return SemanticEvent{ .dcs_payload = .{ .kind = .decudk, .payload = dcs.body } };
    if (dcs.intermediates_len == 1 and dcs.intermediates[0] == '!' and dcs.final == 'u')
        return SemanticEvent{ .dcs_payload = .{ .kind = .decaupss, .payload = dcs.body } };
    if (dcs.intermediates_len == 0) {
        if (dcs.final == 'p' and dcs.param_count == 1) {
            const kind: DcsPayloadKind = switch (dcs.params[0]) {
                1000 => .iterm_tmux_hook,
                2000 => .iterm_ssh_hook,
                else => return null,
            };
            return SemanticEvent{ .dcs_payload = .{ .kind = kind, .payload = dcs.payload } };
        }
        if (dcs.final == 't' and dcs.param_count == 0 and std.mem.startsWith(u8, dcs.payload, "tmux;"))
            return SemanticEvent{ .dcs_payload = .{ .kind = .iterm_tmux_wrap, .payload = dcs.payload[5..] } };
    }
    if (dcs.intermediates_len == 0 and dcs.param_count == 0 and dcs.final == '@' and
        std.mem.startsWith(u8, dcs.payload, "kitty-"))
    {
        if (std.mem.startsWith(u8, dcs.payload, "kitty-restore-cursor-appearance|"))
            return .restore_cursor_appearance;
        if (kittyDcsPayload(dcs.payload)) |payload|
            return SemanticEvent{ .dcs_payload = payload };
    }
    return null;
}

// Classifies Kitty's host-directed DCS prefixes and borrows exactly the bytes
// delivered to its handler, including the remote-command opening brace.
fn kittyDcsPayload(payload: []const u8) ?consequences.DcsInput {
    const commands = [_]struct { prefix: []const u8, kind: DcsPayloadKind, include_last: bool = false }{
        .{ .prefix = "kitty-cmd{", .kind = .kitty_remote_command, .include_last = true },
        .{ .prefix = "kitty-overlay-ready|", .kind = .kitty_overlay_ready },
        .{ .prefix = "kitty-kitten-result|", .kind = .kitty_result },
        .{ .prefix = "kitty-print|", .kind = .kitty_print },
        .{ .prefix = "kitty-echo|", .kind = .kitty_echo },
        .{ .prefix = "kitty-ssh|", .kind = .kitty_ssh },
        .{ .prefix = "kitty-ask|", .kind = .kitty_askpass },
        .{ .prefix = "kitty-clone|", .kind = .kitty_clone },
        .{ .prefix = "kitty-edit|", .kind = .kitty_edit },
    };
    for (commands) |command| {
        if (!std.mem.startsWith(u8, payload, command.prefix)) continue;
        const start = command.prefix.len - @as(usize, if (command.include_last) 1 else 0);
        return .{ .kind = command.kind, .payload = payload[start..] };
    }
    return null;
}

const TestIntermediate = enum {
    dollar,
    plus,
    bang,
};

fn dcsEvent(
    body: []const u8,
    payload: []const u8,
    final: u8,
    params: []const i32,
    param_count: u8,
    intermediate: ?TestIntermediate,
) DcsEvent {
    const intermediates: []const u8 = if (intermediate) |value|
        switch (value) {
            .dollar => "$",
            .plus => "+",
            .bang => "!",
        }
    else
        "";
    return .{
        .body = body,
        .payload = payload,
        .final = final,
        .params = params,
        .param_count = param_count,
        .intermediates = intermediates,
        .intermediates_len = @intCast(intermediates.len),
    };
}

test "dcs request payloads map to semantic events" {
    const empty = @as([24]i32, @splat(0));
    const status = dcsProcess(dcsEvent("$q q", " q", 'q', empty[0..], 0, .dollar)).?;
    try std.testing.expectEqualStrings(" q", status.dcs_request_status);

    const termcap = dcsProcess(dcsEvent("+q436F", "436F", 'q', empty[0..], 0, .plus)).?;
    try std.testing.expectEqualStrings("436F", termcap.dcs_request_termcap);

    const resource = dcsProcess(dcsEvent(
        "+Q6E616D65",
        "6E616D65",
        'Q',
        empty[0..],
        0,
        .plus,
    )).?;
    try std.testing.expectEqualStrings("6E616D65", resource.dcs_request_resource);
}

test "dcs legacy payload protocols classify host-neutral payloads" {
    const empty = @as([24]i32, @splat(0));

    const termcap = dcsProcess(dcsEvent(
        "+p436F=7661",
        "436F=7661",
        'p',
        empty[0..],
        0,
        .plus,
    )).?;
    try std.testing.expect(termcap.dcs_payload.kind == .xtsettcap);
    try std.testing.expectEqualStrings("436F=7661", termcap.dcs_payload.payload);

    try std.testing.expect(dcsProcess(dcsEvent(
        "1$tstate",
        "state",
        't',
        &.{1},
        1,
        .dollar,
    )).? == .restore_cursor_information);
    try std.testing.expect(dcsProcess(dcsEvent(
        "2$t8/16",
        "8/16",
        't',
        &.{2},
        1,
        .dollar,
    )).? == .restore_tab_stops);
    try std.testing.expect(dcsProcess(dcsEvent(
        "0;1|keys",
        "keys",
        '|',
        empty[0..],
        0,
        null,
    )).?.dcs_payload.kind == .decudk);
    try std.testing.expect(dcsProcess(dcsEvent(
        "0!uA",
        "A",
        'u',
        empty[0..],
        0,
        .bang,
    )).?.dcs_payload.kind == .decaupss);
}

const EscAction = union(enum) {
    line_feed,
    next_line,
    reverse_index,
    forward_index,
    back_index,
    primary_device_attributes,
    horizontal_tab_set,
    hard_reset,
    save_cursor,
    restore_cursor,
    application_keypad: bool,
    character_protection: ScreenProtection,
};

fn escAction(final: u8) ?EscAction {
    return switch (final) {
        'D' => .line_feed,
        'E' => .next_line,
        'M' => .reverse_index,
        '9' => .forward_index,
        '6' => .back_index,
        'Z' => .primary_device_attributes,
        'H' => .horizontal_tab_set,
        'c' => .hard_reset,
        '7' => .save_cursor,
        '8' => .restore_cursor,
        'V' => .{ .character_protection = .iso },
        'W' => .{ .character_protection = .none },
        '=' => EscAction{ .application_keypad = true },
        '>' => EscAction{ .application_keypad = false },
        else => null,
    };
}

// Decodes one completed ESC event; unsupported combinations return null.
fn escProcess(final: u8) ?SemanticEvent {
    switch (final) {
        0x17 => return SemanticEvent{ .legacy_control = .tek_copy },
        0x1C => return SemanticEvent{ .legacy_control = .tek_special_point_plot },
        'l' => return SemanticEvent{ .legacy_control = .hp_memory_lock },
        's' => return SemanticEvent{ .legacy_control = .tek_write_thru_short_dashed },
        else => {},
    }
    const mapped = escAction(final) orelse return null;
    return switch (mapped) {
        .line_feed => SemanticEvent.line_feed,
        .next_line => SemanticEvent.next_line,
        .reverse_index => SemanticEvent.reverse_index,
        .forward_index => SemanticEvent.forward_index,
        .back_index => SemanticEvent.back_index,
        .primary_device_attributes => SemanticEvent.primary_device_attributes,
        .horizontal_tab_set => SemanticEvent.horizontal_tab_set,
        .hard_reset => SemanticEvent.hard_reset,
        .save_cursor => SemanticEvent.save_cursor,
        .restore_cursor => SemanticEvent.restore_cursor,
        .application_keypad => |enabled| SemanticEvent{ .application_keypad = enabled },
        .character_protection => |protection| SemanticEvent{ .character_protection = protection },
    };
}

test "esc maps C1 7-bit aliases and cursor save restore" {
    try std.testing.expect(escProcess('D').? == .line_feed);
    try std.testing.expect(escProcess('E').? == .next_line);
    try std.testing.expect(escProcess('M').? == .reverse_index);
    try std.testing.expect(escProcess('7').? == .save_cursor);
    try std.testing.expect(escProcess('8').? == .restore_cursor);
}

test "esc maps DECID RIS and application keypad" {
    try std.testing.expect(escProcess('Z').? == .primary_device_attributes);
    try std.testing.expect(escProcess('c').? == .hard_reset);
    try std.testing.expect(escProcess('=').?.application_keypad);
    try std.testing.expect(!escProcess('>').?.application_keypad);
}

test "esc maps low legacy controls and ignores unsupported finals" {
    try std.testing.expect(escProcess(0x17).?.legacy_control == .tek_copy);
    try std.testing.expect(escProcess(0x1C).?.legacy_control == .tek_special_point_plot);
    try std.testing.expect(escProcess('l').?.legacy_control == .hp_memory_lock);
    try std.testing.expect(escProcess('s').?.legacy_control == .tek_write_thru_short_dashed);
    try std.testing.expectEqual(@as(?SemanticEvent, null), escProcess('z'));
}

// Reports malformed OSC 52 syntax, unsupported query input, invalid base64, or allocation failure.
const ClipboardSetError = error{
    InvalidCharacter,
    InvalidOsc52Payload,
    InvalidPadding,
    OutOfMemory,
    UnsupportedOsc52Query,
};

const ClipboardSizeError = error{
    InvalidOsc52Payload,
    InvalidPadding,
    UnsupportedOsc52Query,
};

const ClipboardIntoError = error{
    InvalidCharacter,
    InvalidOsc52Payload,
    InvalidPadding,
    ShortBuffer,
    UnsupportedOsc52Query,
};

// Decodes one complete borrowed OSC action into a canonical semantic event.
fn oscProcess(osc: parser_mod.OscAction) ?SemanticEvent {
    return switch (osc) {
        // A commandless OSC is the parser's legacy title form, not OSC 0.
        .raw_title => |v| SemanticEvent{ .title_set = v.payload },
        .title => |v| switch (v.command) {
            0 => SemanticEvent{ .title_and_icon_set = v.payload },
            2 => SemanticEvent{ .title_set = v.payload },
            else => null,
        },
        .icon => |v| SemanticEvent{ .icon_set = v.payload },
        .palette_control => |v| SemanticEvent{ .color_control = .{ .command = v.command, .payload = v.payload } },
        .palette_reset => |v| SemanticEvent{ .color_control = .{ .command = v.command, .payload = v.payload } },
        .dynamic_color => |v| SemanticEvent{ .color_control = .{ .command = v.command, .payload = v.payload } },
        .dynamic_reset => |v| SemanticEvent{ .color_control = .{ .command = v.command, .payload = v.payload } },
        .kitty_color => |v| SemanticEvent{ .color_control = .{ .command = v.command, .payload = v.payload } },
        .report_pwd => |v| SemanticEvent{ .working_directory_report = .{ .kind = .uri, .value = v.payload } },
        .shell_mark => |v| if (parseShellMark(v.payload)) |mark| SemanticEvent{ .shell_mark = mark } else null,
        .notification => |v| SemanticEvent{ .notification = .{
            .kind = .message,
            .command = v.command,
            .payload = v.payload,
        } },
        .pointer_shape => |v| SemanticEvent{ .pointer_shape = v.payload },
        .rxvt_extension => |v| SemanticEvent{ .notification = .{
            .kind = .message,
            .command = 777,
            .payload = v.payload,
        } },
        .iterm2 => |v| if (parse(v.command, v.payload)) |command| switch (command) {
            .cursor_shape => |shape| SemanticEvent{ .cursor_shape = shape },
            .report_cell_size => SemanticEvent.iterm_report_cell_size,
            .set_colors => |payload| SemanticEvent{ .iterm_set_colors = payload },
            .current_directory => |value| SemanticEvent{
                .working_directory_report = .{ .kind = .path, .value = value },
            },
            .remote_host => |value| SemanticEvent{ .remote_host_report = value },
            .clear_scrollback => SemanticEvent.clear_buffer,
            .shell_integration => |integration| SemanticEvent{
                .shell_integration_set = integration,
            },
            .notification => |payload| SemanticEvent{ .notification = .{
                .kind = .message,
                .command = 1337,
                .payload = payload,
            } },
            .steal_focus => SemanticEvent{ .notification = .{
                .kind = .steal_focus,
                .command = 1337,
                .payload = "",
            } },
            .request_attention => |payload| SemanticEvent{ .notification = .{
                .kind = .request_attention,
                .command = 1337,
                .payload = payload,
            } },
            .file_transfer => |payload| SemanticEvent{ .file_transfer_packet = .{
                .protocol = .iterm2_1337,
                .payload = payload,
            } },
        } else null,
        .kitty_color_stack_push => SemanticEvent{ .kitty_color_stack = .{ .push = 0 } },
        .kitty_color_stack_pop => SemanticEvent{ .kitty_color_stack = .{ .pop = 0 } },
        .hyperlink => |v| parseHyperlink(v.payload),
        .clipboard => |v| SemanticEvent{ .clipboard_set = v.payload },
        .kitty_clipboard => |v| SemanticEvent{ .kitty_clipboard_packet = v.payload },
        .kitty_file_transfer => |v| SemanticEvent{ .file_transfer_packet = .{
            .protocol = .kitty_5113,
            .payload = v.payload,
        } },
        .kitty_text_size => |v| SemanticEvent{ .text_size = .{ .payload = v.payload } },
        .kitty_drag_drop => |v| if (parseDragDrop(v.payload)) |command|
            SemanticEvent{ .drag_drop = command }
        else
            null,
        else => null,
    };
}

const ParsedDragDrop = struct {
    kind: DragDropCommandKind,
    command: u8,
    client_id: ?u32 = null,
    more: bool = false,
    operation: ?u2 = null,
    index: ?u32 = null,
    remote: bool = false,
    payload: []const u8,
};

fn parseDragDrop(bytes: []const u8) ?ParsedDragDrop {
    const separator = std.mem.indexOfScalar(u8, bytes, ';');
    const metadata = if (separator) |index| bytes[0..index] else bytes;
    const payload = if (separator) |index| bytes[index + 1 ..] else "";
    if (payload.len > drag_drop_packet_max_bytes) return null;
    var command: ?u8 = null;
    var client_id: ?u32 = null;
    var more = false;
    var operation: ?u2 = null;
    var x: ?i32 = null;
    var y: ?i32 = null;
    var pixel_x: ?i32 = null;
    var pixel_y: ?i32 = null;
    var seen: u8 = 0;
    var fields = std.mem.splitScalar(u8, metadata, ':');
    while (fields.next()) |field| {
        const equals = std.mem.indexOfScalar(u8, field, '=') orelse return null;
        if (equals != 1 or equals + 1 == field.len) return null;
        const key = field[0];
        const value = field[equals + 1 ..];
        const bit: u8 = switch (key) {
            't' => 1 << 0,
            'm' => 1 << 1,
            'i' => 1 << 2,
            'o' => 1 << 3,
            'x' => 1 << 4,
            'y' => 1 << 5,
            'X' => 1 << 6,
            'Y' => 1 << 7,
            else => return null,
        };
        if (seen & bit != 0) return null;
        seen |= bit;
        switch (key) {
            't' => {
                if (value.len != 1) return null;
                command = value[0];
            },
            'm' => {
                const parsed = std.fmt.parseInt(u32, value, 10) catch return null;
                if (parsed > 1) return null;
                more = parsed == 1;
            },
            'i' => client_id = std.fmt.parseInt(u32, value, 10) catch return null,
            'o' => {
                const parsed = std.fmt.parseInt(u32, value, 10) catch return null;
                if (parsed > 3) return null;
                operation = @intCast(parsed);
            },
            'x' => x = std.fmt.parseInt(i32, value, 10) catch return null,
            'y' => y = std.fmt.parseInt(i32, value, 10) catch return null,
            'X' => pixel_x = std.fmt.parseInt(i32, value, 10) catch return null,
            'Y' => pixel_y = std.fmt.parseInt(i32, value, 10) catch return null,
            else => unreachable,
        }
    }
    const kind: DragDropCommandKind = if (command == null) continuation: {
        if (seen & ~(@as(u8, (1 << 1) | (1 << 2))) != 0) return null;
        break :continuation .continuation;
    } else switch (command.?) {
        'a' => if (x == null and y == null and pixel_x == null and pixel_y == null and operation == null)
            .enable
        else
            .unsupported,
        'A' => if (x == null and y == null and pixel_x == null and pixel_y == null and operation == null)
            .disable
        else
            .unsupported,
        'm' => if (operation != null and x == null and y == null and pixel_x == null and pixel_y == null)
            .accept
        else
            .unsupported,
        'r' => if (x != null and x.? > 0 and y == null and pixel_x == null and pixel_y == null and operation == null)
            .request
        else if (operation != null and x == null and y == null and pixel_x == null and pixel_y == null)
            .complete
        else
            .unsupported,
        'q' => if (x == null and y == null and pixel_x == null and pixel_y == null and operation == null)
            .query
        else
            .unsupported,
        else => .unsupported,
    };
    return .{
        .kind = kind,
        .command = command orelse 0,
        .client_id = client_id,
        .more = more,
        .operation = operation,
        .index = if (x != null and x.? > 0) @intCast(x.?) else null,
        .remote = kind == .unsupported and (y != null or pixel_x != null or pixel_y != null or
            (command.? == 'a' and x != null)),
        .payload = payload,
    };
}

// Parses one OSC 8 URI and its first nonempty `id=` parameter without retaining parser memory.
fn parseHyperlink(payload: []const u8) ?SemanticEvent {
    const separator = std.mem.indexOfScalar(u8, payload, ';') orelse return null;
    const uri = payload[separator + 1 ..];
    if (uri.len == 0) return SemanticEvent.hyperlink_clear;
    var id: ?[]const u8 = null;
    var params = std.mem.splitScalar(u8, payload[0..separator], ':');
    while (params.next()) |param| {
        if (param.len > 3 and std.mem.startsWith(u8, param, "id=")) {
            id = param[3..];
            break;
        }
    }
    return SemanticEvent{ .hyperlink_set = .{ .uri = uri, .id = id } };
}

// Allocates and decodes one base64 OSC 52 payload into caller-owned memory.
fn decodeClipboardSet(allocator: std.mem.Allocator, raw: []const u8) ClipboardSetError![]u8 {
    const decoded_len = try decodedClipboardSetSize(raw);
    const out = try allocator.alloc(u8, @intCast(decoded_len));
    errdefer allocator.free(out);
    std.debug.assert(out.len == decoded_len);
    const written = decodeClipboardSetInto(raw, out) catch |err| switch (err) {
        error.ShortBuffer => unreachable,
        error.InvalidCharacter => return error.InvalidCharacter,
        error.InvalidOsc52Payload => return error.InvalidOsc52Payload,
        error.InvalidPadding => return error.InvalidPadding,
        error.UnsupportedOsc52Query => return error.UnsupportedOsc52Query,
    };
    std.debug.assert(written == decoded_len);
    return out;
}

fn decodedClipboardSetSize(raw: []const u8) ClipboardSizeError!u64 {
    const request = parseClipboardEnvelope(raw) orelse return error.InvalidOsc52Payload;
    if (request.kind == .query) return error.UnsupportedOsc52Query;
    return @intCast(try decodedBase64Size(request.data));
}

fn decodeClipboardSetInto(raw: []const u8, out: []u8) ClipboardIntoError!u64 {
    const request = parseClipboardEnvelope(raw) orelse return error.InvalidOsc52Payload;
    if (request.kind == .query) return error.UnsupportedOsc52Query;
    const decoded_len = try decodedBase64Size(request.data);
    if (out.len < decoded_len) return error.ShortBuffer;
    std.debug.assert(out.len >= decoded_len);
    std.base64.standard.Decoder.decode(out[0..decoded_len], request.data) catch |err| switch (err) {
        error.InvalidCharacter => return error.InvalidCharacter,
        error.InvalidPadding => return error.InvalidPadding,
        error.NoSpaceLeft => unreachable,
    };
    return @intCast(decoded_len);
}

fn decodedBase64Size(data: []const u8) error{InvalidPadding}!usize {
    // Size calculation cannot inspect alphabet bytes or consume destination space.
    return std.base64.standard.Decoder.calcSizeForSlice(data) catch |err| switch (err) {
        error.InvalidPadding => return error.InvalidPadding,
        error.InvalidCharacter, error.NoSpaceLeft => unreachable,
    };
}

// Classifies one complete OSC 52 payload while retaining selection bytes for host policy.
fn parseClipboardRequest(raw: []const u8) ?ParsedClipboardRequest {
    const request = parseClipboardEnvelope(raw) orelse return null;
    if (request.kind == .set and !validClipboardBase64(request.data)) return null;
    return request;
}

fn parseClipboardEnvelope(raw: []const u8) ?ParsedClipboardRequest {
    const separator = std.mem.indexOfScalar(u8, raw, ';') orelse return null;
    const selection = raw[0..separator];
    if (selection.len > clipboard_selection_bytes_max) return null;
    for (selection) |byte| switch (byte) {
        'c', 'p', 'q', 's', '0'...'7' => {},
        else => return null,
    };
    const data = raw[separator + 1 ..];
    return .{
        .selection = selection,
        .data = data,
        .kind = if (std.mem.eql(u8, data, "?")) .query else .set,
    };
}

fn validClipboardBase64(data: []const u8) bool {
    if (data.len % 4 != 0) return false;
    var padding: u2 = 0;
    for (data, 0..) |byte, index| switch (byte) {
        'A'...'Z', 'a'...'z', '0'...'9', '+', '/' => if (padding != 0) return false,
        '=' => {
            if (index < data.len -| 2 or padding == 2) return false;
            padding += 1;
        },
        else => return false,
    };
    return true;
}

test "OSC 52 clipboard set payload decodes" {
    const decoded = try decodeClipboardSet(std.testing.allocator, "c;SG93bA==");
    defer std.testing.allocator.free(decoded);
    try std.testing.expectEqualStrings("Howl", decoded);
}

test "OSC 52 clipboard query is unsupported for set drain" {
    try std.testing.expectError(error.UnsupportedOsc52Query, decodeClipboardSet(std.testing.allocator, "c;?"));
}

test "OSC 52 clipboard decode reports exact syntax base64 and allocation failures" {
    const decode: *const fn (std.mem.Allocator, []const u8) ClipboardSetError![]u8 = decodeClipboardSet;
    try std.testing.expectError(error.InvalidOsc52Payload, decode(std.testing.allocator, "SG93bA=="));
    try std.testing.expectError(error.InvalidPadding, decode(std.testing.allocator, "c;A"));
    try std.testing.expectError(error.InvalidCharacter, decode(std.testing.allocator, "c;!!!!"));

    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, decode(failing.allocator(), "c;SG93bA=="));
    try std.testing.expect(failing.has_induced_failure);

    var short: [3]u8 = undefined;
    try std.testing.expectError(error.ShortBuffer, decodeClipboardSetInto("c;SG93bA==", &short));
}

test "OSC title commands retain exact title and icon semantics" {
    try std.testing.expectEqualStrings(
        "Both",
        oscProcess(.{ .title = .{
            .command = 0,
            .payload = "Both",
            .term = .bel,
        } }).?.title_and_icon_set,
    );
    try std.testing.expectEqualStrings(
        "Title",
        oscProcess(.{ .title = .{
            .command = 2,
            .payload = "Title",
            .term = .bel,
        } }).?.title_set,
    );
    try std.testing.expectEqualStrings(
        "Raw Title",
        oscProcess(.{ .raw_title = .{
            .payload = "Raw Title",
            .term = .bel,
        } }).?.title_set,
    );
    try std.testing.expectEqualStrings(
        "Icon",
        oscProcess(.{ .icon = .{
            .payload = "Icon",
            .term = .bel,
        } }).?.icon_set,
    );
}

test "OSC hyperlink actions map to semantic events" {
    const explicit = oscProcess(.{ .hyperlink = .{
        .payload = "target=_blank:id=build;https://example.com",
        .term = .bel,
    } }).?.hyperlink_set;
    try std.testing.expectEqualStrings("https://example.com", explicit.uri);
    try std.testing.expectEqualStrings("build", explicit.id.?);
    try std.testing.expect(oscProcess(.{ .hyperlink = .{ .payload = ";", .term = .bel } }).? == .hyperlink_clear);
}

test "OSC clipboard and color controls preserve payloads" {
    try std.testing.expectEqualStrings(
        "c;Zm9v",
        oscProcess(.{ .clipboard = .{
            .command = 52,
            .payload = "c;Zm9v",
            .term = .bel,
        } }).?.clipboard_set,
    );

    const kitty_color = oscProcess(.{ .kitty_color = .{ .command = 21, .payload = "foreground=?", .term = .st } }).?;
    try std.testing.expectEqual(@as(u16, 21), kitty_color.color_control.command);
    try std.testing.expectEqualStrings("foreground=?", kitty_color.color_control.payload);

    const xterm_palette = oscProcess(.{ .palette_control = .{ .command = 4, .payload = "1;#ff0000", .term = .st } }).?;
    try std.testing.expectEqual(@as(u16, 4), xterm_palette.color_control.command);
    try std.testing.expectEqualStrings("1;#ff0000", xterm_palette.color_control.payload);
}

test "OSC shell mark maps to neutral semantic metadata" {
    const shell_mark = oscProcess(.{ .shell_mark = .{ .payload = "D;7", .term = .bel } }).?;
    try std.testing.expectEqual(@as(u8, 'D'), shell_mark.shell_mark.kind);
    try std.testing.expectEqual(@as(?i32, 7), shell_mark.shell_mark.status);
    try std.testing.expectEqual(@as(?i32, 9), parseShellMark("D;aid=nested;9;cl=x").?.status);
    try std.testing.expectEqual(@as(?i32, -3), parseShellMark("D;;-3;aid=x").?.status);
    try std.testing.expectEqual(@as(?i32, null), parseShellMark("D;aid=x;broken").?.status);
    try std.testing.expectEqual(@as(?i32, null), parseShellMark("C;7").?.status);
}

test "OSC Kitty host-policy payloads expose only retained terminal facts" {
    const notification = oscProcess(.{ .notification = .{
        .command = 99,
        .payload = "i=1:p=body;Hello",
        .term = .st,
    } }).?;
    try std.testing.expectEqual(NotificationKind.message, notification.notification.kind);
    try std.testing.expectEqual(@as(u16, 99), notification.notification.command);
    try std.testing.expectEqualStrings("i=1:p=body;Hello", notification.notification.payload);
    const pointer = oscProcess(.{ .pointer_shape = .{
        .payload = ">wait,pointer",
        .term = .st,
    } }).?;
    try std.testing.expectEqualStrings(">wait,pointer", pointer.pointer_shape);
    const push = oscProcess(.{ .kitty_color_stack_push = .st }).?;
    const pop = oscProcess(.{ .kitty_color_stack_pop = .st }).?;
    try std.testing.expectEqual(@as(u16, 0), push.kitty_color_stack.push);
    try std.testing.expectEqual(@as(u16, 0), pop.kitty_color_stack.pop);
    try std.testing.expectEqualStrings("type=write", oscProcess(.{ .kitty_clipboard = .{
        .payload = "type=write",
        .term = .st,
    } }).?.kitty_clipboard_packet);
    const transfer = oscProcess(.{ .kitty_file_transfer = .{
        .payload = "cmd=data",
        .term = .st,
    } }).?.file_transfer_packet;
    try std.testing.expect(transfer.protocol == .kitty_5113);
    try std.testing.expectEqualStrings("cmd=data", transfer.payload);
    try std.testing.expectEqualStrings("s=2;Big", oscProcess(.{ .kitty_text_size = .{
        .payload = "s=2;Big",
        .term = .st,
    } }).?.text_size.payload);
}

// Screen banks and borrowed semantic projection.

// Identifies whether a visible row comes from history or the active screen.
const RowSource = union(enum) {
    history: u32,
    screen: u16,
};

// Owns primary and alternate terminal screens.
const Set = struct {
    primary: Screen,
    alternate: Screen,
    alt_active: bool = false,

    /// Takes primary and alternate screen values into one screen set.
    pub fn init(primary: Screen, alternate: Screen) Set {
        return .{ .primary = primary, .alternate = alternate };
    }

    /// Returns the mutable screen selected by alternate-screen state.
    pub fn active(self: *Set) *Screen {
        return if (self.alt_active) &self.alternate else &self.primary;
    }

    /// Returns the borrowed screen selected by alternate-screen state.
    pub fn activeConst(self: *const Set) *const Screen {
        return if (self.alt_active) &self.alternate else &self.primary;
    }

    /// Resets the active screen while preserving alternate-screen identity.
    pub fn reset(self: *Set) void {
        self.active().reset();
    }

    /// Atomically resize primary and alternate screens.
    ///
    /// Allocation failure leaves both screens unchanged and at matching
    /// dimensions.
    pub fn resize(self: *Set, allocator: std.mem.Allocator, rows: u16, cols: u16) std.mem.Allocator.Error!void {
        var primary = try self.primary.prepareResize(allocator, rows, cols);
        errdefer primary.deinit(allocator);
        var alternate = try self.alternate.prepareResize(allocator, rows, cols);
        errdefer alternate.deinit(allocator);

        std.mem.swap(Screen, &self.primary, &primary);
        std.mem.swap(Screen, &self.alternate, &alternate);
        primary.deinit(allocator);
        alternate.deinit(allocator);
    }

    /// Copies one nonzero host cell-pixel fact to both screen identities.
    pub fn setCellPixelSize(self: *Set, width: u32, height: u32) void {
        self.primary.setCellPixelSize(width, height);
        self.alternate.setCellPixelSize(width, height);
    }

    /// Releases both screens through their shared terminal allocator.
    pub fn deinit(self: *Set, allocator: std.mem.Allocator) void {
        self.primary.deinit(allocator);
        self.alternate.deinit(allocator);
    }
};

/// Builds a borrowed viewport at a clamped scrollback offset.
fn visibleView(screen_state: *const Set, history_offset: u32) Terminal.SemanticView {
    const active = screen_state.activeConst();
    const history_count: u32 = if (screen_state.alt_active) 0 else active.historyCount();
    const offset = @min(history_offset, history_count);
    const rows_count: u32 = active.rows;
    const total_rows = history_count + rows_count;
    const start = if (total_rows >= rows_count + offset) total_rows - rows_count - offset else 0;
    const cursor_visible = active.cursor.visible and offset == 0;
    std.debug.assert(offset <= history_count);
    std.debug.assert(total_rows >= rows_count);
    std.debug.assert(start + rows_count <= total_rows);
    std.debug.assert(total_rows - (start + rows_count) == offset);
    return .{
        .rows = active.rows,
        .cols = active.cols,
        .cursor_row = active.cursor.row,
        .cursor_col = active.cursor.col,
        .cursor_visible = cursor_visible,
        .cursor_shape = active.cursor.effective_shape,
        .cursor_blink = active.cursor.blink_intent,
        .is_alternate_screen = screen_state.alt_active,
        .history_offset = offset,
        .history_count = history_count,
        .history_row_base = active.historyRowBase(),
        .start = start,
        .screen = active,
    };
}

/// Returns one history codepoint by recency.
fn historyCellAt(screen_state: *const Set, history_idx: u32, col: u16) Screen.Cell {
    if (screen_state.alt_active) return Screen.default_cell;
    return screen_state.primary.historyCellAt(history_idx, col);
}

/// Returns the configured active-screen history row capacity.
fn rowIndex(row: u16) u32 {
    return row;
}

/// Identifies one cell in stable projected history-and-screen coordinates.
const TerminalTextPoint = struct {
    row: i32,
    col: u16,
};

/// Identifies an inclusive terminal text range without owning gesture state.
const TerminalTextRange = struct {
    start: TerminalTextPoint,
    end: TerminalTextPoint,
};

fn orderedTextRange(range: TerminalTextRange) TerminalTextRange {
    if (range.start.row < range.end.row) return range;
    if (range.start.row > range.end.row) return .{ .start = range.end, .end = range.start };
    if (range.start.col <= range.end.col) return range;
    return .{ .start = range.end, .end = range.start };
}

// Failures produced while copying terminal cells into UTF-8 caller storage.
const CopyError = error{
    CodepointTooLarge,
    OutOfMemory,
    TextLimit,
    Utf8CannotEncodeSurrogateHalf,
};

fn rowSource(screen_state: *const Set, row: i32) ?RowSource {
    if (row < 0) return null;
    const active = screen_state.activeConst();
    const absolute: u32 = std.math.cast(u32, row) orelse return null;
    const history_base = if (screen_state.alt_active) 0 else screen_state.primary.historyRowBase();
    if (absolute < history_base) return null;
    const logical_row = absolute - history_base;
    const history_count = if (screen_state.alt_active) 0 else screen_state.primary.historyCount();
    if (logical_row < history_count) return .{ .history = history_count - 1 - logical_row };
    const screen_row = logical_row - history_count;
    if (screen_row >= active.rows) return null;
    return .{ .screen = @intCast(screen_row) };
}

fn contentEndExclusive(screen_state: *const Set, row: i32) u16 {
    const source = rowSource(screen_state, row) orelse return 0;
    const active = screen_state.activeConst();
    var scan = active.cols;
    while (scan > 0) {
        const idx = scan - 1;
        const cell = switch (source) {
            .history => |recency| active.historyCellAt(recency, idx),
            .screen => |screen_row| active.cellInfoAt(screen_row, idx),
        };
        if (cell.codepoint != 0 and cell.codepoint != ' ') return scan;
        scan -= 1;
    }
    return if (active.cols > 0) 1 else 0;
}

fn sourceRowWrapped(screen: *const Screen, source: RowSource) bool {
    return switch (source) {
        .history => |recency| screen.historyRowWrapped(recency),
        .screen => |row| screen.rowWrapped(row),
    };
}

// Copy one caller-selected semantic range into caller-owned UTF-8 memory.
//
// The caller owns a successful non-empty result. Invalid stored codepoints
// are reported exactly instead of trapping during integer narrowing.
fn copyTextRange(
    allocator: std.mem.Allocator,
    screen_state: *const Set,
    range: TerminalTextRange,
    max_bytes: usize,
) CopyError![]const u8 {
    const ordered_selection = orderedTextRange(range);
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var row = ordered_selection.start.row;
    while (row <= ordered_selection.end.row) : (row += 1) {
        const source = rowSource(screen_state, row) orelse break;
        const row_start = if (row == ordered_selection.start.row) ordered_selection.start.col else 0;
        const row_end = if (row == ordered_selection.end.row)
            @as(u16, @intCast(@min(@as(u32, ordered_selection.end.col) + 1, @as(u32, screen_state.activeConst().cols))))
        else
            contentEndExclusive(screen_state, row);
        if (row_end > row_start) {
            var col = row_start;
            while (col < row_end) : (col += 1) {
                const cell = switch (source) {
                    .history => |recency| screen_state.primary.historyCellAt(recency, col),
                    .screen => |screen_row| screen_state.activeConst().cellInfoAt(screen_row, col),
                };
                if (cell.codepoint == 0) continue;
                var utf8: [4]u8 = undefined;
                const codepoint = std.math.cast(u21, cell.codepoint) orelse return error.CodepointTooLarge;
                const len = try std.unicode.utf8Encode(codepoint, &utf8);
                if (out.items.len > max_bytes -| len) return error.TextLimit;
                try out.appendSlice(allocator, utf8[0..len]);
            }
        }
        if (row != ordered_selection.end.row and !sourceRowWrapped(screen_state.activeConst(), source)) {
            if (out.items.len == max_bytes) return error.TextLimit;
            try out.append(allocator, '\n');
        }
    }
    return out.toOwnedSlice(allocator);
}

// Semantic application and terminal reply generation.

// Apply one host-directed semantic event and retain its bounded consequence.
fn applyHostEvent(vt: *Terminal, event: SemanticEvent) ApplyError!bool {
    var scratch: input.Scratch = .{};
    const allocator = vt.allocator;
    switch (event) {
        .bell => try vt.consequences.ringBell(),
        .title_and_icon_set => |value| return vt.properties.replaceTitleAndIcon(value),
        .title_set => |title| return vt.properties.replaceTitle(title),
        .icon_set => |icon| return vt.properties.replaceIcon(icon),
        .shell_integration_set => |integration| return vt.properties.replaceShellIntegration(integration.version, integration.shell),
        .working_directory_report => |directory| return vt.properties.replaceWorkingDirectory(directory.kind, directory.value),
        .remote_host_report => |remote_host| return vt.properties.replaceRemoteHost(remote_host),
        .shell_mark => |mark| try vt.properties.replaceShellMark(mark.kind, mark.status, mark.metadata),
        .notification => |notification| try vt.consequences.retainNotification(
            notification.kind,
            notification.command,
            notification.payload,
        ),
        .pointer_shape => |payload| try vt.consequences.retainPointerShape(
            payload,
            vt.screen_state.alt_active,
        ),
        .window_request => |request| try vt.consequences.retainWindowRequest(request),
        .color_preference_query => try vt.consequences.retainColorPreferenceQuery(),
        .color_control => |cmd| {
            const before = vt.properties.colors;
            const output_before = byteCount(vt.reply_buffer.bytes());
            errdefer {
                vt.properties.colors = before;
                vt.reply_buffer.truncate(output_before);
            }
            switch (cmd.command) {
                21 => try handleKittyControl(allocator, &vt.properties.colors, &vt.reply_buffer, cmd.payload),
                4 => try handleXtermPaletteControl(
                    allocator,
                    &vt.properties.colors,
                    &vt.reply_buffer,
                    scratch.buf[0..],
                    cmd.payload,
                ),
                5 => try handleXtermSpecialPaletteControl(
                    allocator,
                    &vt.properties.colors,
                    &vt.reply_buffer,
                    scratch.buf[0..],
                    cmd.payload,
                ),
                10, 11, 12, 13, 14, 15, 16, 17, 18, 19 => try handleXtermDynamicColor(
                    allocator,
                    &vt.properties.colors,
                    &vt.reply_buffer,
                    scratch.buf[0..],
                    cmd.command,
                    cmd.payload,
                ),
                104 => resetXtermPalette(&vt.properties.colors, cmd.payload),
                110, 111, 112, 113, 114, 115, 116, 117, 118, 119 => resetXtermDynamicColor(
                    &vt.properties.colors,
                    cmd.command,
                    cmd.payload,
                ),
                else => {},
            }
            const colors_changed = !std.meta.eql(before, vt.properties.colors);

            return colors_changed or output_before != vt.reply_buffer.bytes().len;
        },
        .hyperlink_set => |spec| return vt.screen_state.active().setCurrentLinkId(try vt.properties.internHyperlink(spec)),
        .hyperlink_clear => return vt.screen_state.active().setCurrentLinkId(0),
        .clipboard_set => |payload| {
            const parsed = parseClipboardRequest(payload) orelse return false;
            try vt.consequences.admitClipboard(payload, @intCast(parsed.selection.len), parsed.kind, .osc52);
            return true;
        },
        .kitty_clipboard_packet => |payload| try vt.consequences.retainKittyClipboard(payload),
        .file_transfer_packet => |packet| try vt.consequences.retainFileTransfer(packet.protocol, packet.payload),
        .drag_drop => |command| try vt.consequences.retainDragDrop(.{
            .kind = command.kind,
            .command = command.command,
            .client_id = command.client_id,
            .more = command.more,
            .operation = command.operation,
            .index = command.index,
            .remote = command.remote,
            .payload = command.payload,
        }),
        .locator_reporting => |cfg| setReporting(&vt.locator, cfg.mode, cfg.unit),
        .locator_filter => |area| setFilter(&vt.locator, area),
        .locator_events => |modes| setEvents(&vt.locator, modes.params[0..modes.param_count]),
        .locator_request => |param| try appendReportForRequest(
            &vt.locator,
            allocator,
            &vt.reply_buffer,
            scratch.buf[0..],
            param,
        ),
        .media_copy_request => |request| try vt.consequences.retainMediaCopy(request),
        .dcs_payload => |payload| try vt.consequences.retainDcsPayload(payload),
        .string_payload => |payload| try vt.consequences.retainStringPayload(payload),
        .legacy_control => |kind| try vt.consequences.retainLegacyControl(kind),
        else => unreachable,
    }
    return true;
}

const xtversion_text = "howl-vt dev";
const terminal_report_max_bytes = 64;

const CursorReportView = struct {
    rows: u16,
    cols: u16,
    cursor_row: u16,
    cursor_col: u16,
    origin_mode: bool = false,
    origin_top: u16 = 0,
    origin_left: u16 = 0,
};

const RectChecksumRequest = struct {
    request_id: u16,
};

// Apply one report-directed semantic event to bounded host output.
fn applyReportEvent(vt: *Terminal, event: SemanticEvent) ApplyError!void {
    var scratch: input.Scratch = .{};
    const allocator = vt.allocator;
    const reply_buffer = &vt.reply_buffer;
    const encode_buf = scratch.buf[0..];
    const active = vt.screen_state.activeConst();
    const render_view = CursorReportView{
        .rows = active.rows,
        .cols = active.cols,
        .cursor_row = active.cursor.row,
        .cursor_col = active.cursor.col,
        .origin_mode = active.origin_mode,
        .origin_top = active.scroll_top,
        .origin_left = if (active.left_right_margin_mode) active.left_margin else 0,
    };
    const ansi_modes = AnsiView{
        .keyboard_action_mode = vt.modes.keyboard_action_mode,
        .insert_mode = active.insert_mode,
        .send_receive_mode = vt.modes.send_receive_mode,
        .newline_mode = vt.modes.newline_mode,
    };
    const dec_modes = DecView{
        .application_cursor_keys = vt.modes.application_cursor_keys,
        .application_keypad = vt.modes.application_keypad,
        .column_mode_132 = vt.modes.column_mode_132,
        .allow_column_mode = vt.modes.allow_column_mode,
        .preserve_screen_on_column_mode = vt.modes.preserve_screen_on_column_mode,
        .more_fix = vt.modes.more_fix,
        .auto_repeat = vt.modes.auto_repeat,
        .reverse_screen_mode = vt.modes.reverse_screen_mode,
        .origin_mode = active.origin_mode,
        .auto_wrap = active.auto_wrap,
        .left_right_margin_mode = active.left_right_margin_mode,
        .cursor_blink = active.cursor.blink_intent,
        .cursor_visible = active.cursor.visible,
        .alt_active = vt.screen_state.alt_active,
        .mouse_tracking = vt.modes.mouse_tracking,
        .mouse_protocol = vt.modes.mouse_protocol,
        .focus_reporting = vt.modes.focus_reporting,
        .alternate_scroll = vt.modes.alternate_scroll,
        .meta_sends_escape = vt.modes.meta_sends_escape,
        .report_key_up = vt.modes.report_key_up,
        .bracketed_paste = vt.modes.bracketed_paste,
        .synchronized_output = vt.modes.synchronized_output,
        .inband_resize_notifications = vt.modes.inband_resize_notifications,
        .color_preference_notifications = vt.modes.color_preference_notifications,
        .paste_events = vt.modes.paste_events,
        .reverse_wraparound = vt.modes.reverse_wraparound_mode,
        .extended_reverse_wraparound = vt.modes.extended_reverse_wraparound_mode,
        .sixel_display_mode = vt.modes.sixel_display_mode,
    };
    switch (event) {
        .ansi_mode_query => |mode| try appendAnsiModeReport(
            allocator,
            reply_buffer,
            encode_buf,
            mode,
            ansiModeStateForView(ansi_modes, mode),
        ),
        .modify_other_keys_query => try appendModifyOtherKeysReport(
            allocator,
            reply_buffer,
            encode_buf,
            vt.modes.modify_other_keys,
        ),
        .key_format_query => |resource| if (isKeyFormatResource(resource))
            try appendKeyFormatReport(
                allocator,
                reply_buffer,
                encode_buf,
                resource,
                vt.modes.key_format[resource],
            ),
        .dec_mode_query => |mode| try appendDecModeReport(
            allocator,
            reply_buffer,
            encode_buf,
            mode,
            decModeStateForView(dec_modes, mode),
        ),
        .dcs_request_status => |request| try appendDecrqssReply(allocator, reply_buffer, encode_buf, active, request),
        .dcs_request_termcap => |request| try appendTermcapReports(allocator, reply_buffer, request),
        .dcs_request_resource => |request| try appendResourceInvalidReport(allocator, reply_buffer, request),
        .device_status_report => try reply_buffer.appendCsi(.terminal, "0n"),
        .dec_device_status_report => |param| try appendDeviceStatusReport(allocator, reply_buffer, encode_buf, param),
        .cursor_position_report => try appendCursorPositionReport(allocator, reply_buffer, encode_buf, render_view),
        .dec_cursor_position_report => try appendDecCursorPositionReport(
            allocator,
            reply_buffer,
            encode_buf,
            render_view,
        ),
        .primary_device_attributes => {
            const payload = std.fmt.bufPrint(encode_buf, "?{d};22c", .{dec_conformance_level}) catch unreachable;
            try reply_buffer.appendCsi(.terminal, payload);
        },
        .secondary_device_attributes => try reply_buffer.appendCsi(.terminal, ">1;10;0c"),
        .tertiary_device_attributes => try reply_buffer.appendString(
            .terminal,
            .dcs,
            "!|00000000",
        ),
        .xtversion => try appendXtVersionReport(allocator, reply_buffer),
        .xttitlepos => try appendTitleStackPositionReport(allocator, reply_buffer, encode_buf, 0, 0),
        .xtchecksum => |flags| vt.xtchecksum_flags = flags,
        .rect_checksum_request => |req| try appendRectChecksumReport(
            allocator,
            reply_buffer,
            encode_buf,
            .{ .request_id = req.request_id },
            computeRectChecksum(active, vt.xtchecksum_flags, req.page, req.area),
        ),
        .selected_graphic_rendition_report => |area| try appendSelectedGraphicRenditionReport(
            allocator,
            reply_buffer,
            encode_buf,
            active,
            area,
        ),
        .screen_extent_report => try appendScreenExtentReport(allocator, reply_buffer, encode_buf, render_view),
        .parameters_report => |kind| try appendTerminalParametersReport(allocator, reply_buffer, encode_buf, kind),
        .window_title_report => try appendWindowTitleReport(vt),
        .xtreportcolors => try appendColorStackReport(allocator, reply_buffer, encode_buf, &vt.properties.color_stack),
        .iterm_report_cell_size => try appendItermCellSizeReport(vt, encode_buf),
        else => unreachable,
    }
}

fn applyTitleStack(host: *properties.State, command: @FieldType(SemanticEvent, "title_stack")) properties.PropertyError!properties.TitleStackEffect {
    if (command.option != 0 and command.option != 2) return .{};
    return switch (command.command) {
        .push => .{ .changed = try host.pushTitle() },
        .pop => host.popTitle(),
    };
}

fn appendWindowTitleReport(vt: *Terminal) ApplyError!void {
    const output = &vt.reply_buffer;
    const start = byteCount(output.bytes());
    errdefer output.truncate(start);
    try output.appendControl(.iterm, .osc);
    try output.append("l");
    if (vt.properties.current_title) |title| try output.append(title);
    try output.appendControl(.iterm, .st);
}

fn appendSizeReport(vt: *Terminal, scratch: []u8, kind: SizeReport) ApplyError!bool {
    const active = vt.screen_state.activeConst();
    const payload = switch (kind) {
        .text_cells => std.fmt.bufPrint(scratch, "8;{d};{d}t", .{ active.rows, active.cols }) catch unreachable,
        .cell_pixels => blk: {
            const cell = active.cellPixelSize() orelse return false;
            break :blk std.fmt.bufPrint(scratch, "6;{d};{d}t", .{ cell.height, cell.width }) catch unreachable;
        },
        .window_pixels => blk: {
            // Without a distinct host frame fact, Ps=2 retains the text-area fallback.
            const cell = active.cellPixelSize() orelse return false;
            const height = @as(u64, cell.height) * @as(u64, active.rows);
            const width = @as(u64, cell.width) * @as(u64, active.cols);
            break :blk std.fmt.bufPrint(scratch, "4;{d};{d}t", .{ height, width }) catch unreachable;
        },
    };
    try vt.reply_buffer.appendCsi(.terminal, payload);
    return true;
}

fn appendItermCellSizeReport(vt: *Terminal, scratch: []u8) ApplyError!void {
    const cell = vt.cellPixelSize() orelse return;
    // The current host supplies logical pixel metrics and owns no output-scale
    // protocol, so points equal pixels and the reported scale is exactly one.
    const payload = std.fmt.bufPrint(
        scratch,
        "1337;ReportCellSize={d};{d};1",
        .{ cell.height, cell.width },
    ) catch unreachable;
    try vt.reply_buffer.appendString(.iterm, .osc, payload);
}

fn appendDecrqssReply(
    allocator: std.mem.Allocator,
    output: *replies.Buffer,
    encode_buf: []u8,
    screen: *const Screen,
    request: []const u8,
) ApplyError!void {
    const start = byteCount(output.bytes());
    errdefer output.truncate(start);
    try output.appendControl(.terminal, .dcs);
    if (std.mem.eql(u8, request, "m")) {
        try output.append("1$r");
        try appendSgrAttrs(allocator, output, encode_buf, currentAttrs(screen));
        try output.appendControl(.terminal, .st);
        return;
    }
    if (decrqssPayload(encode_buf, screen, request)) |payload| {
        try output.append("1$r");
        try output.append(payload);
        try output.appendControl(.terminal, .st);
        return;
    }
    try output.append("0$r");
    try output.appendControl(.terminal, .st);
}

// Howl identifies as a VT220-class terminal in DA1 and DECRQSS DECSCL.
const dec_conformance_level: u8 = 62;

fn decrqssPayload(encode_buf: []u8, screen: *const Screen, request: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, request, "\"p")) {
        return std.fmt.bufPrint(encode_buf, "{d}\"p", .{dec_conformance_level}) catch null;
    }
    if (std.mem.eql(u8, request, "r")) {
        const bottom = if (screen.rows == 0) @as(u16, 0) else @min(screen.scroll_bottom, screen.rows - 1);
        return std.fmt.bufPrint(encode_buf, "{d};{d}r", .{ screen.scroll_top + 1, bottom + 1 }) catch null;
    }
    if (std.mem.eql(u8, request, "s")) {
        const left = if (screen.left_right_margin_mode) screen.left_margin else 0;
        const right = if (screen.left_right_margin_mode) screen.right_margin else screen.cols -| 1;
        return std.fmt.bufPrint(encode_buf, "{d};{d}s", .{ left + 1, right + 1 }) catch null;
    }
    if (std.mem.eql(u8, request, " q")) {
        const style = screen.cursor.effectiveStyle();
        const value: u8 = switch (style.shape) {
            .none => 1,
            .block => if (style.blink) 1 else 2,
            .underline => if (style.blink) 3 else 4,
            .bar => if (style.blink) 5 else 6,
        };
        return std.fmt.bufPrint(encode_buf, "{d} q", .{value}) catch null;
    }
    if (std.mem.eql(u8, request, "\"q")) {
        const value: u8 = if (screen.current_attrs.protected == .dec) 1 else 2;
        return std.fmt.bufPrint(encode_buf, "{d}\"q", .{value}) catch null;
    }
    if (std.mem.eql(u8, request, "*x")) {
        const value: u8 = if (screen.attr_change_extent_rect) 2 else 0;
        return std.fmt.bufPrint(encode_buf, "{d}*x", .{value}) catch null;
    }
    if (std.mem.eql(u8, request, "t")) {
        return std.fmt.bufPrint(encode_buf, "{d}t", .{@max(@as(u16, 24), screen.rows)}) catch null;
    }
    return null;
}

fn appendModifyOtherKeysReport(
    _: std.mem.Allocator,
    output: *replies.Buffer,
    encode_buf: []u8,
    value: i8,
) ApplyError!void {
    const payload = std.fmt.bufPrint(encode_buf, ">4;{d}m", .{value}) catch unreachable;
    try output.appendCsi(.terminal, payload);
}

fn appendKeyFormatReport(
    _: std.mem.Allocator,
    output: *replies.Buffer,
    encode_buf: []u8,
    resource: u8,
    value: u16,
) ApplyError!void {
    const payload = std.fmt.bufPrint(encode_buf, ">{d};{d}f", .{ resource, value }) catch unreachable;
    try output.appendCsi(.terminal, payload);
}

fn appendXtVersionReport(_: std.mem.Allocator, output: *replies.Buffer) ApplyError!void {
    try output.appendString(.terminal, .dcs, ">|" ++ xtversion_text);
}

const TermcapValue = union(enum) {
    flag,
    encoded: []const u8,
};

// Answers only capability facts owned by terminal state rather than host configuration.
fn termcapValue(encoded_name: []const u8) ?TermcapValue {
    if (hexNameEquals(encoded_name, "Co") or hexNameEquals(encoded_name, "colors"))
        return .{ .encoded = "323536" };
    if (hexNameEquals(encoded_name, "RGB")) return .{ .encoded = "38" };
    if (hexNameEquals(encoded_name, "Tc") or hexNameEquals(encoded_name, "Su")) return .flag;
    return null;
}

fn hexNameEquals(encoded: []const u8, name: []const u8) bool {
    if (encoded.len % 2 != 0 or encoded.len / 2 != name.len) return false;
    for (name, 0..) |byte, index| {
        const high = std.fmt.charToDigit(encoded[index * 2], 16) catch return false;
        const low = std.fmt.charToDigit(encoded[index * 2 + 1], 16) catch return false;
        if (((high << 4) | low) != byte) return false;
    }
    return true;
}

fn appendTermcapReports(
    _: std.mem.Allocator,
    output: *replies.Buffer,
    request: []const u8,
) ApplyError!void {
    const start = byteCount(output.bytes());
    errdefer output.truncate(start);
    var names = std.mem.splitScalar(u8, request, ';');
    while (names.next()) |encoded_name| {
        try output.appendControl(.terminal, .dcs);
        const value = termcapValue(encoded_name);
        try output.append(if (value == null) "0+r" else "1+r");
        try output.append(encoded_name);
        if (value) |known| switch (known) {
            .flag => {},
            .encoded => |encoded_value| {
                try output.append("=");
                try output.append(encoded_value);
            },
        };
        try output.appendControl(.terminal, .st);
    }
}

test "XTGETTCAP reply allocation failure rolls back the complete ordered response" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        appendTermcapReportsAllocation,
        .{},
    );
}

fn appendTermcapReportsAllocation(allocator: std.mem.Allocator) !void {
    var output = replies.Buffer.init(allocator);
    defer output.deinit();
    appendTermcapReports(allocator, &output, "436F;5463;626F677573") catch |failure| {
        try std.testing.expectEqual(@as(usize, 0), output.bytes().len);
        return failure;
    };
    try std.testing.expectEqualStrings(
        "\x1bP1+r436F=323536\x1b\\\x1bP1+r5463\x1b\\\x1bP0+r626F677573\x1b\\",
        output.bytes(),
    );
}

fn appendResourceInvalidReport(
    _: std.mem.Allocator,
    output: *replies.Buffer,
    request: []const u8,
) ApplyError!void {
    const start = byteCount(output.bytes());
    errdefer output.truncate(start);
    try output.appendControl(.terminal, .dcs);
    try output.append("0+R");
    try output.append(request);
    try output.appendControl(.terminal, .st);
}

fn appendTitleStackPositionReport(
    _: std.mem.Allocator,
    output: *replies.Buffer,
    encode_buf: []u8,
    current: u16,
    max: u16,
) ApplyError!void {
    const payload = std.fmt.bufPrint(encode_buf, "{d};{d}#S", .{ current, max }) catch unreachable;
    try output.appendCsi(.terminal, payload);
}

fn appendCursorPositionReport(
    _: std.mem.Allocator,
    output: *replies.Buffer,
    encode_buf: []u8,
    render_view: CursorReportView,
) ApplyError!void {
    const row = reportCursorCoordinate(render_view.cursor_row, render_view.origin_top, render_view.origin_mode);
    const col = reportCursorCoordinate(render_view.cursor_col, render_view.origin_left, render_view.origin_mode);
    const payload = std.fmt.bufPrint(
        encode_buf,
        "{d};{d}R",
        .{ row, col },
    ) catch unreachable;
    try output.appendCsi(.terminal, payload);
}

fn appendDecCursorPositionReport(
    _: std.mem.Allocator,
    output: *replies.Buffer,
    encode_buf: []u8,
    render_view: CursorReportView,
) ApplyError!void {
    const row = reportCursorCoordinate(render_view.cursor_row, render_view.origin_top, render_view.origin_mode);
    const col = reportCursorCoordinate(render_view.cursor_col, render_view.origin_left, render_view.origin_mode);
    const payload = std.fmt.bufPrint(
        encode_buf,
        "?{d};{d}R",
        .{ row, col },
    ) catch unreachable;
    try output.appendCsi(.terminal, payload);
}

// A restored cursor may precede current margins; relative reports clamp that
// valid cross-savepoint state to the first addressable origin coordinate.
fn reportCursorCoordinate(position: u16, origin: u16, relative: bool) u32 {
    const zero_based: u32 = if (relative) position -| origin else position;
    return zero_based + 1;
}

test "cursor report coordinate saturates origin and preserves one-based u16 extent" {
    try std.testing.expectEqual(@as(u32, 1), reportCursorCoordinate(2, 6, true));
    try std.testing.expectEqual(@as(u32, 65_536), reportCursorCoordinate(std.math.maxInt(u16), 0, false));
}

fn appendDecModeReport(
    _: std.mem.Allocator,
    output: *replies.Buffer,
    encode_buf: []u8,
    mode: u16,
    state: u8,
) ApplyError!void {
    const payload = std.fmt.bufPrint(encode_buf, "?{d};{d}$y", .{ mode, state }) catch unreachable;
    try output.appendCsi(.terminal, payload);
}

fn appendAnsiModeReport(
    _: std.mem.Allocator,
    output: *replies.Buffer,
    encode_buf: []u8,
    mode: u16,
    state: u8,
) ApplyError!void {
    const payload = std.fmt.bufPrint(encode_buf, "{d};{d}$y", .{ mode, state }) catch unreachable;
    try output.appendCsi(.terminal, payload);
}

fn appendColorStackReport(
    _: std.mem.Allocator,
    output: *replies.Buffer,
    encode_buf: []u8,
    stack: *const KittyColorStack,
) ApplyError!void {
    const index = if (stack.len == 0) 0 else stack.len - 1;
    const payload = std.fmt.bufPrint(encode_buf, "{d};{d}#Q", .{ index, stack.len }) catch unreachable;
    try output.appendCsi(.kitty, payload);
}

fn appendTabStopReport(
    _: std.mem.Allocator,
    output: *replies.Buffer,
    encode_buf: []u8,
    screen: *const Screen,
) ApplyError!void {
    const start = byteCount(output.bytes());
    errdefer output.truncate(start);
    try output.appendControl(.terminal, .dcs);
    try output.append("2$u");
    var first = true;
    var col: u16 = 0;
    while (col < screen.cols) : (col += 1) {
        if (!screen.tabStopAt(col)) continue;
        if (!first) try output.append("/");
        first = false;
        const text = std.fmt.bufPrint(encode_buf, "{d}", .{col + 1}) catch unreachable;
        try output.append(text);
    }
    try output.appendControl(.terminal, .st);
}

fn appendScreenExtentReport(
    _: std.mem.Allocator,
    output: *replies.Buffer,
    encode_buf: []u8,
    render_view: CursorReportView,
) ApplyError!void {
    const payload = std.fmt.bufPrint(encode_buf, "{d};{d};1;1;1\"w", .{ render_view.rows, render_view.cols }) catch unreachable;
    try output.appendCsi(.terminal, payload);
}

fn appendTerminalParametersReport(
    _: std.mem.Allocator,
    output: *replies.Buffer,
    encode_buf: []u8,
    kind: u16,
) ApplyError!void {
    if (kind > 1) return;
    const payload = std.fmt.bufPrint(encode_buf, "{d};1;1;128;128;1;0x", .{kind + 2}) catch unreachable;
    try output.appendCsi(.terminal, payload);
}

fn appendRectChecksumReport(
    _: std.mem.Allocator,
    output: *replies.Buffer,
    encode_buf: []u8,
    req: RectChecksumRequest,
    checksum: u16,
) ApplyError!void {
    const payload = std.fmt.bufPrint(encode_buf, "{d}!~{X:0>4}", .{ req.request_id, checksum }) catch unreachable;
    try output.appendString(.terminal, .dcs, payload);
}

fn appendSelectedGraphicRenditionReport(
    allocator: std.mem.Allocator,
    output: *replies.Buffer,
    encode_buf: []u8,
    screen: *const Screen,
    area: RectArea,
) ApplyError!void {
    const common = commonAttrsForRect(screen, area) orelse {
        try output.appendCsi(.terminal, "0m");
        return;
    };

    const start = byteCount(output.bytes());
    errdefer output.truncate(start);
    try output.appendControl(.terminal, .csi);
    try appendSgrAttrs(allocator, output, encode_buf, common);
}

// Appends one complete SGR parameter payload for retained terminal attributes.
fn appendSgrAttrs(
    allocator: std.mem.Allocator,
    output: *replies.Buffer,
    encode_buf: []u8,
    attrs: CommonAttrs,
) ApplyError!void {
    var first = true;
    try appendSgrParam(allocator, output, &first, "0");
    if (attrs.bold) try appendSgrParam(allocator, output, &first, "1");
    if (attrs.dim) try appendSgrParam(allocator, output, &first, "2");
    if (attrs.italic) try appendSgrParam(allocator, output, &first, "3");
    if (attrs.underline) try appendSgrParam(allocator, output, &first, underlineStyleParam(attrs.underline_style));
    if (attrs.blink) try appendSgrParam(allocator, output, &first, "5");
    if (attrs.reverse) try appendSgrParam(allocator, output, &first, "7");
    if (attrs.invisible) try appendSgrParam(allocator, output, &first, "8");
    if (attrs.strikethrough) try appendSgrParam(allocator, output, &first, "9");
    if (attrs.font != 0) {
        const font = std.fmt.bufPrint(encode_buf, "{d}", .{@as(u8, 10) + attrs.font}) catch unreachable;
        try appendSgrParam(allocator, output, &first, font);
    }
    try appendColorParam(allocator, output, encode_buf, &first, true, attrs.fg, Screen.default_cell_attrs.fg);
    try appendColorParam(allocator, output, encode_buf, &first, false, attrs.bg, Screen.default_cell_attrs.bg);
    if (attrs.underline and !colorEq(attrs.underline_color, Screen.default_underline_color)) {
        try appendExtendedColorParam(allocator, output, encode_buf, &first, 58, attrs.underline_color);
    }
    switch (attrs.baseline) {
        .normal => {},
        .raised => try appendSgrParam(allocator, output, &first, "73"),
        .lowered => try appendSgrParam(allocator, output, &first, "74"),
    }
    try output.append("m");
}

fn computeRectChecksum(screen: *const Screen, xtchecksum_flags: u16, page: u16, area: RectArea) u16 {
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
    font: u4,
    baseline: Screen.Baseline,
    bold: bool,
    dim: bool,
    italic: bool,
    underline: bool,
    underline_style: Screen.UnderlineStyle,
    underline_color: Screen.Color,
    blink: bool,
    reverse: bool,
    invisible: bool,
    strikethrough: bool,
    fg: Screen.Color,
    bg: Screen.Color,
};

// Copies current pen attributes into the shared bounded SGR report shape.
fn currentAttrs(screen: *const Screen) CommonAttrs {
    const attrs = screen.current_attrs;
    return .{
        .font = attrs.font,
        .baseline = attrs.baseline,
        .bold = attrs.bold,
        .dim = attrs.dim,
        .italic = attrs.italic,
        .underline = attrs.underline,
        .underline_style = attrs.underline_style,
        .underline_color = attrs.underline_color,
        .blink = attrs.blink,
        .reverse = attrs.reverse,
        .invisible = attrs.invisible,
        .strikethrough = attrs.strikethrough,
        .fg = attrs.fg,
        .bg = attrs.bg,
    };
}

fn commonAttrsForRect(screen: *const Screen, area: RectArea) ?CommonAttrs {
    const bounds = screen.rectBounds(area) orelse return null;
    const first_cell = screen.cellInfoAt(bounds.top, bounds.left);
    var common = CommonAttrs{
        .font = first_cell.attrs.font,
        .baseline = first_cell.attrs.baseline,
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
            if (attrs.font != common.font) common.font = 0;
            if (attrs.baseline != common.baseline) common.baseline = .normal;
            if (attrs.bold != common.bold) common.bold = false;
            if (attrs.dim != common.dim) common.dim = false;
            if (attrs.italic != common.italic) common.italic = false;
            if (attrs.underline != common.underline) common.underline = false;
            if (attrs.blink != common.blink) common.blink = false;
            if (attrs.reverse != common.reverse) common.reverse = false;
            if (attrs.invisible != common.invisible) common.invisible = false;
            if (attrs.strikethrough != common.strikethrough) common.strikethrough = false;
            if (attrs.underline_style != common.underline_style) common.underline_style = .straight;
            if (!colorEq(attrs.fg, common.fg)) common.fg = Screen.default_cell_attrs.fg;
            if (!colorEq(attrs.bg, common.bg)) common.bg = Screen.default_cell_attrs.bg;
            if (!colorEq(attrs.underline_color, common.underline_color)) {
                common.underline_color = Screen.default_underline_color;
            }
        }
    }
    if (!common.underline) {
        common.underline_style = .straight;
        common.underline_color = Screen.default_underline_color;
    }
    return common;
}

fn appendSgrParam(
    _: std.mem.Allocator,
    output: *replies.Buffer,
    first: *bool,
    text: []const u8,
) ApplyError!void {
    if (!first.*) try output.append(";");
    first.* = false;
    try output.append(text);
}

fn underlineStyleParam(style: Screen.UnderlineStyle) []const u8 {
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
    output: *replies.Buffer,
    encode_buf: []u8,
    first: *bool,
    is_fg: bool,
    color: Screen.Color,
    default_color: Screen.Color,
) ApplyError!void {
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
                const text = std.fmt.bufPrint(encode_buf, "{d}", .{code}) catch unreachable;
                try appendSgrParam(allocator, output, first, text);
                return;
            }
            try appendExtendedColorParam(allocator, output, encode_buf, first, if (is_fg) 38 else 48, color);
        },
        .rgb => try appendExtendedColorParam(allocator, output, encode_buf, first, if (is_fg) 38 else 48, color),
    }
}

fn appendExtendedColorParam(
    allocator: std.mem.Allocator,
    output: *replies.Buffer,
    encode_buf: []u8,
    first: *bool,
    prefix: u8,
    color: Screen.Color,
) ApplyError!void {
    switch (color.kind) {
        .default => return,
        .indexed => {
            const text = std.fmt.bufPrint(encode_buf, "{d};5;{d}", .{ prefix, color.value }) catch unreachable;
            try appendSgrParam(allocator, output, first, text);
        },
        .rgb => {
            const text = std.fmt.bufPrint(encode_buf, "{d};2;{d};{d};{d}", .{
                prefix,
                (color.value >> 16) & 0xFF,
                (color.value >> 8) & 0xFF,
                color.value & 0xFF,
            }) catch unreachable;
            try appendSgrParam(allocator, output, first, text);
        },
    }
}

fn colorEq(a: Screen.Color, b: Screen.Color) bool {
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
    try std.testing.expectEqualStrings("1 q", block_blink);

    screen.applyScreen(.{ .cursor_style = .{ .program_override = .{ .shape = .none, .blink = false } } });
    const no_shape = decrqssPayload(encode_buf[0..], &screen, " q").?;
    try std.testing.expectEqualStrings("1 q", no_shape);
}

test "DECRQSS reply allocation failure preserves prior pending output" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        appendDecrqssReplyAllocation,
        .{},
    );
}

fn appendDecrqssReplyAllocation(allocator: std.mem.Allocator) !void {
    var output = replies.Buffer.init(allocator);
    defer output.deinit();
    try output.append("kept");

    const screen = Screen.init(30, 80);
    var encode_buf: [terminal_report_max_bytes]u8 = undefined;
    appendDecrqssReply(allocator, &output, encode_buf[0..], &screen, "t") catch |failure| {
        try std.testing.expectEqualStrings("kept", output.bytes());
        return failure;
    };
    try std.testing.expectEqualStrings("kept\x1bP1$r30t\x1b\\", output.bytes());
}

test "DECRQSS reply capacity failure preserves the complete prior output" {
    const allocator = std.testing.allocator;
    var output = replies.Buffer.init(allocator);
    defer output.deinit();
    const retained = try allocator.alloc(u8, replies.max_bytes - 1);
    defer allocator.free(retained);
    @memset(retained, 'k');
    try output.append(retained);

    const screen = Screen.init(30, 80);
    var encode_buf: [terminal_report_max_bytes]u8 = undefined;
    try std.testing.expectError(
        error.ReplyLimit,
        appendDecrqssReply(allocator, &output, encode_buf[0..], &screen, "t"),
    );
    try std.testing.expectEqualSlices(u8, retained, output.bytes());
}

test "cursor position report payload names semantic cursor position" {
    var output = replies.Buffer.init(std.testing.allocator);
    defer output.deinit();
    var encode_buf: [64]u8 = undefined;

    try appendCursorPositionReport(std.testing.allocator, &output, encode_buf[0..], .{
        .rows = 24,
        .cols = 80,
        .cursor_row = 2,
        .cursor_col = 4,
    });
    try std.testing.expectEqualStrings("\x1b[3;5R", output.bytes());
}

const Rgb = properties.Rgb;
const osc_reply_max_bytes = 8;
const color_osc_max_bytes = 18;

const TerminalColorState = properties.ColorState;
const default_terminal_foreground = properties.default_foreground;
const default_terminal_background = properties.default_background;

const SpecialKey = enum { foreground, background, cursor, cursor_text, selection_background, selection_foreground };
const DynamicKey = enum {
    foreground,
    background,
    cursor,
    pointer_foreground,
    pointer_background,
    tektronix_foreground,
    tektronix_background,
    selection_background,
    tektronix_cursor,
    selection_foreground,
};
const SpecialPaletteKey = enum(u3) {
    bold = 0,
    underline = 1,
    blink = 2,
    reverse = 3,
    italic = 4,
};

// Applies or answers one OSC 4 palette request transactionally.
fn handleXtermPaletteControl(
    allocator: std.mem.Allocator,
    colors: *TerminalColorState,
    output: *replies.Buffer,
    encode_buf: []u8,
    payload: []const u8,
) ApplyError!void {
    var parts = std.mem.splitScalar(u8, payload, ';');
    while (parts.next()) |idx_text| {
        const value = parts.next() orelse break;
        const idx = std.fmt.parseUnsigned(u16, idx_text, 10) catch continue;
        if (std.mem.eql(u8, value, "?")) {
            const text = std.fmt.bufPrint(encode_buf, "4;{d};", .{idx}) catch unreachable;
            const start = byteCount(output.bytes());
            errdefer output.truncate(start);
            try output.appendControl(.terminal, .osc);
            try output.append(text);
            if (paletteTargetColor(colors.*, idx)) |color| try appendColorOsc(allocator, output, color);
            try output.appendControl(.terminal, .st);
        } else if (parseColor(value)) |color| {
            setPaletteTarget(colors, idx, color);
        }
    }
}

// Applies or answers one OSC 5 special-palette request transactionally.
fn handleXtermSpecialPaletteControl(
    allocator: std.mem.Allocator,
    colors: *TerminalColorState,
    output: *replies.Buffer,
    encode_buf: []u8,
    payload: []const u8,
) ApplyError!void {
    var parts = std.mem.splitScalar(u8, payload, ';');
    while (parts.next()) |idx_text| {
        const value = parts.next() orelse break;
        const idx = std.fmt.parseUnsigned(u3, idx_text, 10) catch continue;
        const text = std.fmt.bufPrint(encode_buf, "5;{d};", .{idx}) catch unreachable;
        if (std.mem.eql(u8, value, "?")) {
            const start = byteCount(output.bytes());
            errdefer output.truncate(start);
            try output.appendControl(.terminal, .osc);
            try output.append(text);
            if (colors.special_palette[idx]) |color| try appendColorOsc(allocator, output, color);
            try output.appendControl(.terminal, .st);
        } else if (parseColor(value)) |color| {
            colors.special_palette[idx] = color;
        }
    }
}

// Applies or answers one dynamic-color command transactionally.
fn handleXtermDynamicColor(
    allocator: std.mem.Allocator,
    colors: *TerminalColorState,
    output: *replies.Buffer,
    encode_buf: []u8,
    command: u16,
    payload: []const u8,
) ApplyError!void {
    var key = dynamicKeyForCommand(command) orelse return;
    var parts = std.mem.splitScalar(u8, payload, ';');
    while (parts.next()) |value| {
        if (std.mem.eql(u8, value, "?")) {
            try appendXtermDynamicColorReply(allocator, output, encode_buf, colors.*, key);
        } else if (parseColor(value)) |color| {
            setDynamicColor(colors, key, color);
        }
        key = nextDynamicKey(key) orelse return;
    }
}

// Resets selected OSC 104 palette entries or the complete palette.
fn resetXtermPalette(colors: *TerminalColorState, payload: []const u8) void {
    if (payload.len == 0) {
        colors.palette = buildDefaultPalette();
        return;
    }
    var parts = std.mem.splitScalar(u8, payload, ';');
    while (parts.next()) |idx_text| {
        const idx = std.fmt.parseUnsigned(u8, idx_text, 10) catch continue;
        resetPaletteTarget(colors, idx);
    }
}

// Resets one dynamic color selected by its OSC command.
fn resetXtermDynamicColor(colors: *TerminalColorState, command: u16, payload: []const u8) void {
    if (payload.len != 0) return;
    const key = dynamicKeyForResetCommand(command) orelse return;
    resetDynamicColor(colors, key);
}

// Converts a cursor color-control request into a semantic event when applicable.
fn cursorColorEvent(command: TerminalColorControlCommand) ?Screen.Action {
    if (command.command == 12) return cursorColorEventFromDynamicPayload(command.payload, .cursor);
    if (command.command == 112 and command.payload.len == 0) return .{ .cursor_color = null };
    if (command.command == 21) return cursorColorEventFromKittyPayload(command.payload);
    return null;
}

fn parseColor(value: []const u8) ?Rgb {
    const color_text = stripAlpha(std.mem.trim(u8, value, " \t\r\n"));
    if (color_text.len == 0) return null;
    if (std.mem.startsWith(u8, color_text, "#")) return parseHashColor(color_text[1..]);
    if (std.mem.startsWith(u8, color_text, "rgb:")) return parseRgbColor(color_text[4..]);
    if (std.ascii.eqlIgnoreCase(color_text, "black")) return .{ .r = 0, .g = 0, .b = 0 };
    if (std.ascii.eqlIgnoreCase(color_text, "red")) return .{ .r = 255, .g = 0, .b = 0 };
    if (std.ascii.eqlIgnoreCase(color_text, "green")) return .{ .r = 0, .g = 255, .b = 0 };
    if (std.ascii.eqlIgnoreCase(color_text, "blue")) return .{ .r = 0, .g = 0, .b = 255 };
    if (std.ascii.eqlIgnoreCase(color_text, "white")) return .{ .r = 255, .g = 255, .b = 255 };
    return null;
}

// Applies the iTerm SetColors subset represented by terminal presentation state.
//
// Bare and `srgb:` three- or six-digit values are accepted. Display-P3 and
// host-only selection, tab, badge, link, match, preset, and face-policy keys
// are intentionally left to an embedder with those domains. Matching iTerm's
// command loop, each valid pair commits independently while malformed or
// unsupported pairs are ignored without affecting their valid neighbors;
// `default` restores the corresponding native TerminalColorState default.
fn handleItermSetColors(colors: *TerminalColorState, payload: []const u8) void {
    const defaults = TerminalColorState{};
    var parts = std.mem.splitScalar(u8, payload, ',');
    while (parts.next()) |part| {
        const separator = std.mem.indexOfScalar(u8, part, '=') orelse continue;
        if (separator == 0 or separator + 1 == part.len) continue;
        const name = part[0..separator];
        const target = parseItermColorTarget(name) orelse continue;
        var value = part[separator + 1 ..];
        if (std.mem.eql(u8, value, "default")) {
            resetItermColor(colors, defaults, target);
            continue;
        }
        if (std.mem.startsWith(u8, value, "srgb:")) value = value[5..];
        if (std.mem.indexOfScalar(u8, value, ':') != null) continue;
        const rgb = parseItermHex(value) orelse continue;
        setItermColor(colors, target, rgb);
    }
}

const ItermColorTarget = union(enum) {
    foreground,
    background,
    cursor,
    cursor_text,
    palette: u8,
};

fn parseItermColorTarget(name: []const u8) ?ItermColorTarget {
    if (std.mem.eql(u8, name, "fg")) return .foreground;
    if (std.mem.eql(u8, name, "bg")) return .background;
    if (std.mem.eql(u8, name, "curbg")) return .cursor;
    if (std.mem.eql(u8, name, "curfg")) return .cursor_text;
    if (parseItermPaletteIndex(name)) |index| return .{ .palette = index };
    return null;
}

fn setItermColor(colors: *TerminalColorState, target: ItermColorTarget, rgb: Rgb) void {
    switch (target) {
        .foreground => colors.foreground = rgb,
        .background => colors.background = rgb,
        .cursor => colors.cursor = rgb,
        .cursor_text => colors.cursor_text = rgb,
        .palette => |index| colors.palette[index] = rgb,
    }
}

fn resetItermColor(
    colors: *TerminalColorState,
    defaults: TerminalColorState,
    target: ItermColorTarget,
) void {
    switch (target) {
        .foreground => colors.foreground = defaults.foreground,
        .background => colors.background = defaults.background,
        .cursor => colors.cursor = defaults.cursor,
        .cursor_text => colors.cursor_text = defaults.cursor_text,
        .palette => |index| colors.palette[index] = defaults.palette[index],
    }
}

fn parseItermHex(value: []const u8) ?Rgb {
    if (value.len != 3 and value.len != 6) return null;
    var expanded: [6]u8 = undefined;
    const hex = if (value.len == 3) blk: {
        for (value, 0..) |digit, index| {
            expanded[index * 2] = digit;
            expanded[index * 2 + 1] = digit;
        }
        break :blk expanded[0..];
    } else value;
    const rgb_value = std.fmt.parseUnsigned(u24, hex, 16) catch return null;
    return .{
        .r = @intCast(rgb_value >> 16),
        .g = @intCast((rgb_value >> 8) & 0xff),
        .b = @intCast(rgb_value & 0xff),
    };
}

fn parseItermPaletteIndex(name: []const u8) ?u8 {
    const names = [_][]const u8{
        "black",    "red",    "green",    "yellow",    "blue",    "magenta",    "cyan",    "white",
        "br_black", "br_red", "br_green", "br_yellow", "br_blue", "br_magenta", "br_cyan", "br_white",
    };
    for (names, 0..) |candidate, index|
        if (std.mem.eql(u8, name, candidate)) return @intCast(index);
    return null;
}

fn specialColorKey(key: []const u8) ?SpecialKey {
    if (std.mem.eql(u8, key, "foreground")) return .foreground;
    if (std.mem.eql(u8, key, "background")) return .background;
    if (std.mem.eql(u8, key, "cursor")) return .cursor;
    if (std.mem.eql(u8, key, "cursor_text")) return .cursor_text;
    if (std.mem.eql(u8, key, "selection_background")) return .selection_background;
    if (std.mem.eql(u8, key, "selection_foreground")) return .selection_foreground;
    return null;
}

// Reports whether a borrowed Kitty color key names supported state.
fn isKnownColorKey(key: []const u8) bool {
    if (specialColorKey(key) != null) return true;
    return (std.fmt.parseUnsigned(u8, key, 10) catch null) != null;
}

// Returns the current color for a recognized Kitty key.
fn colorForKey(colors: TerminalColorState, key: []const u8) ?Rgb {
    if (std.fmt.parseUnsigned(u8, key, 10)) |idx| return colors.palette[idx] else |_| {}
    if (specialColorKey(key)) |special| return switch (special) {
        .foreground => colors.foreground,
        .background => colors.background,
        .cursor => colors.cursor,
        .cursor_text => colors.cursor_text,
        .selection_background => colors.selection_background,
        .selection_foreground => colors.selection_foreground,
    };
    return null;
}

fn paletteTargetColor(colors: TerminalColorState, idx: u16) ?Rgb {
    if (idx < 256) return colors.palette[@intCast(idx)];
    const special_idx = idx - 256;
    if (special_idx >= colors.special_palette.len) return null;
    return colors.special_palette[special_idx];
}

fn setPaletteTarget(colors: *TerminalColorState, idx: u16, color: Rgb) void {
    if (idx < 256) {
        colors.palette[@intCast(idx)] = color;
        return;
    }
    const special_idx = idx - 256;
    if (special_idx >= colors.special_palette.len) return;
    colors.special_palette[special_idx] = color;
}

fn resetPaletteTarget(colors: *TerminalColorState, idx: u8) void {
    colors.palette[idx] = paletteColor(idx);
}

fn dynamicKeyForCommand(command: u16) ?DynamicKey {
    return switch (command) {
        10 => .foreground,
        11 => .background,
        12 => .cursor,
        13 => .pointer_foreground,
        14 => .pointer_background,
        15 => .tektronix_foreground,
        16 => .tektronix_background,
        17 => .selection_background,
        18 => .tektronix_cursor,
        19 => .selection_foreground,
        else => null,
    };
}

fn cursorColorEventFromDynamicPayload(payload: []const u8, key: SpecialKey) ?Screen.Action {
    var parts = std.mem.splitScalar(u8, payload, ';');
    const value = parts.next() orelse return null;
    if (std.mem.eql(u8, value, "?")) return null;
    return cursorColorEventForValue(key, value);
}

fn cursorColorEventFromKittyPayload(payload: []const u8) ?Screen.Action {
    const split = std.mem.indexOfScalar(u8, payload, '=') orelse return null;
    const key_text = payload[0..split];
    const value = payload[split + 1 ..];
    const key = specialColorKey(key_text) orelse return null;
    switch (key) {
        .cursor, .cursor_text => return cursorColorEventForValue(key, value),
        .foreground, .background, .selection_background, .selection_foreground => return null,
    }
}

fn cursorColorEventForValue(key: SpecialKey, value: []const u8) ?Screen.Action {
    if (std.mem.eql(u8, value, "?")) return null;
    if (value.len == 0) return switch (key) {
        .cursor => .{ .cursor_color = null },
        .cursor_text => .{ .cursor_text_color = null },
        else => null,
    };
    const rgb = parseColor(value) orelse return null;
    return switch (key) {
        .cursor => .{ .cursor_color = rgb },
        .cursor_text => .{ .cursor_text_color = rgb },
        else => null,
    };
}

fn dynamicKeyForResetCommand(command: u16) ?DynamicKey {
    return switch (command) {
        110 => .foreground,
        111 => .background,
        112 => .cursor,
        113 => .pointer_foreground,
        114 => .pointer_background,
        115 => .tektronix_foreground,
        116 => .tektronix_background,
        117 => .selection_background,
        118 => .tektronix_cursor,
        119 => .selection_foreground,
        else => null,
    };
}

fn nextDynamicKey(key: DynamicKey) ?DynamicKey {
    return switch (key) {
        .foreground => .background,
        .background => .cursor,
        .cursor => .pointer_foreground,
        .pointer_foreground => .pointer_background,
        .pointer_background => .tektronix_foreground,
        .tektronix_foreground => .tektronix_background,
        .tektronix_background => .selection_background,
        .selection_background => .tektronix_cursor,
        .tektronix_cursor => .selection_foreground,
        .selection_foreground => null,
    };
}

fn dynamicCommandForKey(key: DynamicKey) u16 {
    return switch (key) {
        .foreground => 10,
        .background => 11,
        .cursor => 12,
        .pointer_foreground => 13,
        .pointer_background => 14,
        .tektronix_foreground => 15,
        .tektronix_background => 16,
        .selection_background => 17,
        .tektronix_cursor => 18,
        .selection_foreground => 19,
    };
}

fn dynamicColor(colors: TerminalColorState, key: DynamicKey) ?Rgb {
    return switch (key) {
        .foreground => colors.foreground,
        .background => colors.background,
        .cursor => colors.cursor,
        .pointer_foreground => colors.pointer_foreground,
        .pointer_background => colors.pointer_background,
        .tektronix_foreground => colors.tektronix_foreground,
        .tektronix_background => colors.tektronix_background,
        .selection_background => colors.selection_background,
        .tektronix_cursor => colors.tektronix_cursor,
        .selection_foreground => colors.selection_foreground,
    };
}

fn setDynamicColor(colors: *TerminalColorState, key: DynamicKey, color: Rgb) void {
    switch (key) {
        .foreground => colors.foreground = color,
        .background => colors.background = color,
        .cursor => colors.cursor = color,
        .pointer_foreground => colors.pointer_foreground = color,
        .pointer_background => colors.pointer_background = color,
        .tektronix_foreground => colors.tektronix_foreground = color,
        .tektronix_background => colors.tektronix_background = color,
        .selection_background => colors.selection_background = color,
        .tektronix_cursor => colors.tektronix_cursor = color,
        .selection_foreground => colors.selection_foreground = color,
    }
}

fn resetDynamicColor(colors: *TerminalColorState, key: DynamicKey) void {
    switch (key) {
        .foreground => colors.foreground = default_terminal_foreground,
        .background => colors.background = default_terminal_background,
        .cursor => colors.cursor = null,
        .pointer_foreground => colors.pointer_foreground = null,
        .pointer_background => colors.pointer_background = null,
        .tektronix_foreground => colors.tektronix_foreground = null,
        .tektronix_background => colors.tektronix_background = null,
        .selection_background => colors.selection_background = null,
        .tektronix_cursor => colors.tektronix_cursor = null,
        .selection_foreground => colors.selection_foreground = null,
    }
}

// Appends one bounded rgb:RRRR/GGGG/BBBB OSC color reply.
fn appendColorOsc(_: std.mem.Allocator, output: *replies.Buffer, color: Rgb) ApplyError!void {
    var buf: [32]u8 = undefined;
    const text = formatColorOsc(buf[0..], color);
    try output.append(text);
}

// Parses and applies a recognized Kitty color key, ignoring invalid values.
fn setColorKey(colors: *TerminalColorState, key: []const u8, value: []const u8) void {
    if (std.fmt.parseUnsigned(u8, key, 10)) |idx| {
        if (parseColor(value)) |color| colors.palette[idx] = color;
        return;
    } else |_| {}
    if (value.len == 0) {
        setSpecialColorDynamic(colors, key);
    } else if (parseColor(value)) |color| {
        if (specialColorKey(key)) |special| setSpecialColor(colors, special, color);
    }
}

// Restores a recognized Kitty color key to its default value.
fn resetColorKey(colors: *TerminalColorState, key: []const u8) void {
    if (std.fmt.parseUnsigned(u8, key, 10)) |idx| {
        colors.palette[idx] = paletteColor(idx);
        return;
    } else |_| {}
    if (specialColorKey(key)) |special| switch (special) {
        .foreground => colors.foreground = default_terminal_foreground,
        .background => colors.background = default_terminal_background,
        .cursor => colors.cursor = null,
        .cursor_text => colors.cursor_text = null,
        .selection_background => colors.selection_background = null,
        .selection_foreground => colors.selection_foreground = null,
    };
}

fn appendXtermSpecialColorReply(
    allocator: std.mem.Allocator,
    output: *replies.Buffer,
    encode_buf: []u8,
    colors: TerminalColorState,
    key: SpecialKey,
) ApplyError!void {
    const osc: u8 = switch (key) {
        .foreground => 10,
        .background => 11,
        .cursor => 12,
        else => 10,
    };
    const color = switch (key) {
        .foreground => colors.foreground,
        .background => colors.background,
        .cursor => colors.cursor orelse colors.foreground,
        else => colors.foreground,
    };
    const text = std.fmt.bufPrint(encode_buf, "{d};", .{osc}) catch unreachable;
    const start = byteCount(output.bytes());
    errdefer output.truncate(start);
    try output.appendControl(.terminal, .osc);
    try output.append(text);
    try appendColorOsc(allocator, output, color);
    try output.appendControl(.terminal, .st);
}

fn appendXtermDynamicColorReply(
    allocator: std.mem.Allocator,
    output: *replies.Buffer,
    encode_buf: []u8,
    colors: TerminalColorState,
    key: DynamicKey,
) ApplyError!void {
    const text = std.fmt.bufPrint(encode_buf, "{d};", .{dynamicCommandForKey(key)}) catch unreachable;
    const start = byteCount(output.bytes());
    errdefer output.truncate(start);
    try output.appendControl(.terminal, .osc);
    try output.append(text);
    if (dynamicColor(colors, key)) |color| try appendColorOsc(allocator, output, color);
    try output.appendControl(.terminal, .st);
}

fn setSpecialColor(colors: *TerminalColorState, key: SpecialKey, color: Rgb) void {
    switch (key) {
        .foreground => colors.foreground = color,
        .background => colors.background = color,
        .cursor => colors.cursor = color,
        .cursor_text => colors.cursor_text = color,
        .selection_background => colors.selection_background = color,
        .selection_foreground => colors.selection_foreground = color,
    }
}

fn setSpecialColorDynamic(colors: *TerminalColorState, key: []const u8) void {
    if (specialColorKey(key)) |special| switch (special) {
        .foreground => {},
        .background => {},
        .cursor => colors.cursor = null,
        .cursor_text => colors.cursor_text = null,
        .selection_background => colors.selection_background = null,
        .selection_foreground => colors.selection_foreground = null,
    };
}

fn formatColorOsc(buf: []u8, color: Rgb) []const u8 {
    std.debug.assert(buf.len >= color_osc_max_bytes);
    return std.fmt.bufPrint(buf, "rgb:{x:0>4}/{x:0>4}/{x:0>4}", .{
        @as(u16, color.r) * 0x101,
        @as(u16, color.g) * 0x101,
        @as(u16, color.b) * 0x101,
    }) catch unreachable;
}

fn buildDefaultPalette() [256]Rgb {
    @setEvalBranchQuota(4096);
    var palette: [256]Rgb = undefined;
    var idx: u16 = 0;
    while (idx < 256) : (idx += 1) palette[idx] = paletteColor(@intCast(idx));
    return palette;
}

fn paletteColor(idx: u8) Rgb {
    if (idx < 16) return paletteAnsi16Color(idx);
    if (idx < 232) {
        const n = idx - 16;
        const r = cubeComponent(n / 36);
        const g = cubeComponent((n / 6) % 6);
        const b = cubeComponent(n % 6);
        return .{ .r = r, .g = g, .b = b };
    }
    const gray: u8 = 8 + (idx - 232) * 10;
    return .{ .r = gray, .g = gray, .b = gray };
}

fn cubeComponent(v: u8) u8 {
    return if (v == 0) 0 else 55 + v * 40;
}

fn paletteAnsi16Color(idx: u8) Rgb {
    return switch (idx) {
        0 => .{ .r = 0, .g = 0, .b = 0 },
        1 => .{ .r = 205, .g = 49, .b = 49 },
        2 => .{ .r = 13, .g = 188, .b = 121 },
        3 => .{ .r = 229, .g = 229, .b = 16 },
        4 => .{ .r = 36, .g = 114, .b = 200 },
        5 => .{ .r = 188, .g = 63, .b = 188 },
        6 => .{ .r = 17, .g = 168, .b = 205 },
        7 => .{ .r = 229, .g = 229, .b = 229 },
        8 => .{ .r = 102, .g = 102, .b = 102 },
        9 => .{ .r = 241, .g = 76, .b = 76 },
        10 => .{ .r = 35, .g = 209, .b = 139 },
        11 => .{ .r = 245, .g = 245, .b = 67 },
        12 => .{ .r = 59, .g = 142, .b = 234 },
        13 => .{ .r = 214, .g = 112, .b = 214 },
        14 => .{ .r = 41, .g = 184, .b = 219 },
        else => .{ .r = 255, .g = 255, .b = 255 },
    };
}

fn stripAlpha(value: []const u8) []const u8 {
    const at = std.mem.indexOfScalar(u8, value, '@') orelse return value;
    return value[0..at];
}

fn parseHashColor(hex: []const u8) ?Rgb {
    return switch (hex.len) {
        3 => blk: {
            const r = parseHexNibble(hex[0]) orelse return null;
            const g = parseHexNibble(hex[1]) orelse return null;
            const b = parseHexNibble(hex[2]) orelse return null;
            break :blk .{ .r = r * 0x11, .g = g * 0x11, .b = b * 0x11 };
        },
        6 => .{
            .r = parseHexByte(hex[0..2]) orelse return null,
            .g = parseHexByte(hex[2..4]) orelse return null,
            .b = parseHexByte(hex[4..6]) orelse return null,
        },
        9 => .{
            .r = parseHexByte(hex[0..2]) orelse return null,
            .g = parseHexByte(hex[3..5]) orelse return null,
            .b = parseHexByte(hex[6..8]) orelse return null,
        },
        12 => .{
            .r = parseHexByte(hex[0..2]) orelse return null,
            .g = parseHexByte(hex[4..6]) orelse return null,
            .b = parseHexByte(hex[8..10]) orelse return null,
        },
        else => null,
    };
}

fn parseRgbColor(text: []const u8) ?Rgb {
    var parts = std.mem.splitScalar(u8, text, '/');
    const r = parseRgbComponent(parts.next() orelse return null) orelse return null;
    const g = parseRgbComponent(parts.next() orelse return null) orelse return null;
    const b = parseRgbComponent(parts.next() orelse return null) orelse return null;
    if (parts.next() != null) return null;
    return .{ .r = r, .g = g, .b = b };
}

fn parseRgbComponent(text: []const u8) ?u8 {
    if (text.len == 0 or text.len > 4) return null;
    const value = std.fmt.parseUnsigned(u16, text, 16) catch return null;
    return switch (text.len) {
        1 => @intCast(value * 17),
        2 => @intCast(value),
        3 => @intCast(value >> 4),
        4 => @intCast(value >> 8),
        else => null,
    };
}

fn parseHexByte(text: []const u8) ?u8 {
    if (text.len != 2) return null;
    return std.fmt.parseUnsigned(u8, text, 16) catch null;
}

fn parseHexNibble(byte: u8) ?u8 {
    return switch (byte) {
        '0'...'9' => byte - '0',
        'a'...'f' => byte - 'a' + 10,
        'A'...'F' => byte - 'A' + 10,
        else => null,
    };
}

test "cursor color control mutates semantic cursor owner through screen apply" {
    var screen = Screen.init(2, 2);

    const cursor_event = cursorColorEvent(.{ .command = 12, .payload = "#010203" }).?;
    screen.applyScreen(.{ .cursor_color = cursor_event.cursor_color });
    try std.testing.expectEqual(@as(?Rgb, .{ .r = 1, .g = 2, .b = 3 }), screen.cursor.cursor_color);

    const cursor_text_event = cursorColorEvent(.{ .command = 21, .payload = "cursor_text=#040506" }).?;
    screen.applyScreen(.{ .cursor_text_color = cursor_text_event.cursor_text_color });
    try std.testing.expectEqual(@as(?Rgb, .{ .r = 4, .g = 5, .b = 6 }), screen.cursor.cursor_text_color);

    const reset_event = cursorColorEvent(.{ .command = 112, .payload = "" }).?;
    screen.applyScreen(.{ .cursor_color = reset_event.cursor_color });
    try std.testing.expectEqual(@as(?Rgb, null), screen.cursor.cursor_color);
}

// Apply one Kitty-directed semantic event and report exact state or output mutation.
fn applyKittyEvent(vt: *Terminal, event: SemanticEvent) ApplyError!bool {
    var scratch: input.Scratch = .{};
    const active_screen = vt.kitty.activeScreen(vt.screen_state.alt_active);
    const active_screen_const = vt.kitty.activeScreenConst(vt.screen_state.alt_active);
    switch (event) {
        .kitty_keyboard_set => |req| {
            return active_screen.keyboard.set(req.flags, req.mode);
        },
        .kitty_keyboard_query => {
            std.debug.assert(scratch.buf.len >= key_report_max_bytes);
            const payload = std.fmt.bufPrint(
                scratch.buf[0..],
                "?{d}u",
                .{active_screen_const.keyboard.flags},
            ) catch unreachable;
            try vt.reply_buffer.appendCsi(.kitty, payload);
            return true;
        },
        .kitty_keyboard_push => |flags| {
            return active_screen.keyboard.push(flags);
        },
        .kitty_keyboard_pop => |count| {
            return active_screen.keyboard.pop(count);
        },
        else => unreachable,
    }
}

// Applies one bounded color-stack mutation and reports rejected or empty operations as unchanged.
fn applyKittyColorStack(vt: *Terminal, command: KittyColorCommand) bool {
    return switch (command) {
        .push => |index| vt.properties.pushColor(index),
        .pop => |index| vt.properties.popColor(index),
    };
}

// Observable terminal mutations produced while applying one parser event.
const EventEffect = struct {
    changed: bool,
    title_changed: bool,
    icon_changed: bool,
};

/// Classify one parsed event into the canonical parser-to-domain vocabulary.
fn routeParserEvent(event: parser_mod.Event) ?SemanticEvent {
    switch (event) {
        .style_change => |sc| {
            const params = sc.params[0..sc.param_count];
            const intermediates = sc.intermediates[0..sc.intermediates_len];
            return csiProcess(sc.final, params, sc.separators, sc.leader, sc.private, intermediates);
        },
        .invoke_charset, .configure_charset => return null,
        .text => |s| return SemanticEvent{ .write_text = s },
        .codepoint => |cp| return SemanticEvent{ .write_codepoint = cp },
        .control => |c| return controlProcess(c),
        .osc => |osc_event| return oscProcess(osc_event),
        .screen_title => |title| return if (title.len == 0)
            null
        else
            SemanticEvent{ .title_and_icon_set = title },
        .esc_dispatch => |esc_dispatch| return escDispatchProcess(
            esc_dispatch.final,
            esc_dispatch.intermediates[0..esc_dispatch.intermediates_len],
        ),
        .apc => return null,
        .dcs => |dcs_data| return dcsProcess(dcs_data),
        .pm, .invalid_sequence => return null,
    }
}

fn escDispatchProcess(final: u8, intermediates: []const u8) ?SemanticEvent {
    if (std.mem.eql(u8, intermediates, " ")) return switch (final) {
        'F' => .{ .eight_bit_controls = false },
        'G' => .{ .eight_bit_controls = true },
        else => null,
    };
    if (intermediates.len != 0) return null;
    return escProcess(final);
}

/// Apply one parser event and report whether terminal or title state changed.
fn applyParserEvent(vt: *Terminal, event: parser_mod.Event) ApplyError!EventEffect {
    switch (event) {
        .invoke_charset => |slot| {
            const changed = vt.charset.selectGl(slot);
            return .{ .changed = changed, .title_changed = false, .icon_changed = false };
        },
        .configure_charset => |cfg| {
            const changed = vt.charset.configureCharset(cfg.slot, cfg.designation);
            return .{ .changed = changed, .title_changed = false, .icon_changed = false };
        },
        else => {},
    }

    const semantic = routeParserEvent(event) orelse return .{
        .changed = false,
        .title_changed = false,
        .icon_changed = false,
    };
    if (semantic == .title_stack) {
        const effect = try applyTitleStack(&vt.properties, semantic.title_stack);
        return .{
            .changed = effect.changed,
            .title_changed = effect.title_changed,
            .icon_changed = false,
        };
    }
    const title_changed = switch (semantic) {
        .title_and_icon_set => |value| !optionalBytesEqual(vt.properties.current_title, value),
        .title_set => |value| !optionalBytesEqual(vt.properties.current_title, value),
        else => false,
    };
    const icon_changed = switch (semantic) {
        .title_and_icon_set => |value| !optionalBytesEqual(vt.properties.current_icon, value),
        .icon_set => |value| !optionalBytesEqual(vt.properties.current_icon, value),
        else => false,
    };
    const changed = try applySemantic(vt, semantic);
    return .{
        .changed = changed,
        .title_changed = title_changed,
        .icon_changed = icon_changed,
    };
}

fn applySemantic(vt: *Terminal, event: SemanticEvent) ApplyError!bool {
    switch (event) {
        .hard_reset => vt.hardReset(),
        .soft_reset => return vt.softReset(),
        .save_cursor => return vt.saveCursor(),
        .restore_cursor => return vt.restoreCursor(),
        .enter_alt_screen => |opts| {
            return vt.switchScreenMode(true, opts.clear, opts.save_cursor);
        },
        .exit_alt_screen => |opts| {
            return vt.switchScreenMode(false, false, opts.restore_cursor);
        },
        .size_report => |kind| {
            var scratch: input.Scratch = .{};
            return try appendSizeReport(vt, scratch.buf[0..], kind);
        },
        .title_stack => unreachable,
        .ansi_mode_query,
        .modify_other_keys_query,
        .key_format_query,
        .dec_mode_query,
        .dcs_request_status,
        .dcs_request_termcap,
        .dcs_request_resource,
        .device_status_report,
        .dec_device_status_report,
        .cursor_position_report,
        .dec_cursor_position_report,
        .primary_device_attributes,
        .secondary_device_attributes,
        .tertiary_device_attributes,
        .xtversion,
        .xttitlepos,
        .xtchecksum,
        .rect_checksum_request,
        .selected_graphic_rendition_report,
        .screen_extent_report,
        .parameters_report,
        .window_title_report,
        .xtreportcolors,
        .iterm_report_cell_size,
        => try applyReportEvent(vt, event),

        .kitty_keyboard_set,
        .kitty_keyboard_query,
        .kitty_keyboard_push,
        .kitty_keyboard_pop,
        => return try applyKittyEvent(vt, event),

        .kitty_color_stack => |command| {
            const changed = applyKittyColorStack(vt, command);
            return changed;
        },
        .text_size => |command| return vt.screen_state.active().writeSizedText(command.payload),
        .sgr_stack_push => |params| return vt.pushSgr(params),
        .sgr_stack_pop => return vt.popSgr(),
        .restore_cursor_information => |payload| return vt.restoreCursorInformation(payload),
        .restore_tab_stops => |payload| return vt.restoreTabStops(payload),
        .restore_cursor_appearance => return vt.restoreCursorAppearance(),

        .focus_reporting => |enabled| return vt.setDecMode(1004, enabled),
        .mouse_tracking_off => return vt.setMouseTracking(.off),
        .mouse_tracking_x10 => return vt.setDecMode(9, true),
        .mouse_tracking_normal => return vt.setDecMode(1000, true),
        .mouse_tracking_button_event => return vt.setDecMode(1002, true),
        .mouse_tracking_any_event => return vt.setDecMode(1003, true),
        .mouse_protocol_utf8 => |enabled| return vt.setDecMode(1005, enabled),
        .mouse_protocol_sgr => |enabled| return vt.setDecMode(1006, enabled),
        .mouse_protocol_urxvt => |enabled| return vt.setDecMode(1015, enabled),
        .mouse_protocol_sgr_pixel => |enabled| return vt.setDecMode(1016, enabled),

        .application_cursor_keys,
        .application_keypad,
        .column_mode_132,
        .allow_column_mode,
        .preserve_screen_on_column_mode,
        .more_fix,
        .auto_repeat,
        .reverse_screen_mode,
        .eight_bit_controls,
        .left_right_margin_mode,
        .cursor_visible,
        .cursor_blink,
        .ansi_mode_set,
        .ansi_mode_reset,
        .modify_other_keys_set,
        .modify_other_keys_disable,
        .key_format_change,
        .pointer_mode,
        .reverse_wraparound_mode,
        .extended_reverse_wraparound_mode,
        .alternate_scroll,
        .meta_sends_escape,
        .report_key_up,
        .bracketed_paste,
        .synchronized_output,
        .inband_resize_notifications,
        .color_preference_notifications,
        .paste_events,
        .termios_signals,
        .dec_mode_set,
        .dec_mode_reset,
        .dec_mode_save,
        .dec_mode_restore,
        => return vt.applyModeEvent(event),

        .sgr => |sgr| return vt.screen_state.active().applySgr(
            screenSgrOperands(sgr.params, sgr.separators),
        ),

        .cursor_style => |value| {
            const cursor = &vt.screen_state.active().cursor;
            const before = cursor.*;
            vt.screen_state.active().applyScreen(.{ .cursor_style = value });
            return !std.meta.eql(before, cursor.*);
        },
        .cursor_shape => |value| {
            const cursor = &vt.screen_state.active().cursor;
            const before = cursor.*;
            vt.screen_state.active().applyScreen(.{ .cursor_shape = value });
            return !std.meta.eql(before, cursor.*);
        },

        .color_control => |control| {
            const primary_before = vt.screen_state.primary.cursor;
            const alternate_before = vt.screen_state.alternate.cursor;
            errdefer {
                vt.screen_state.primary.cursor = primary_before;
                vt.screen_state.alternate.cursor = alternate_before;
            }
            if (cursorColorEvent(control)) |cursor_event| {
                vt.screen_state.primary.applyScreen(cursor_event);
                vt.screen_state.alternate.applyScreen(cursor_event);
            }
            const host_changed = try applyHostEvent(vt, event);
            return host_changed or
                !std.meta.eql(primary_before, vt.screen_state.primary.cursor) or
                !std.meta.eql(alternate_before, vt.screen_state.alternate.cursor);
        },
        .iterm_set_colors => |payload| {
            const before = vt.properties.colors;
            handleItermSetColors(&vt.properties.colors, payload);
            const changed = !std.meta.eql(before, vt.properties.colors);

            return changed;
        },
        .bell,
        .title_and_icon_set,
        .title_set,
        .icon_set,
        .shell_integration_set,
        .working_directory_report,
        .remote_host_report,
        .shell_mark,
        .notification,
        .pointer_shape,
        .window_request,
        .color_preference_query,
        .hyperlink_set,
        .hyperlink_clear,
        .clipboard_set,
        .kitty_clipboard_packet,
        .file_transfer_packet,
        .drag_drop,
        .locator_reporting,
        .locator_filter,
        .locator_events,
        .locator_request,
        .media_copy_request,
        .dcs_payload,
        .string_payload,
        .legacy_control,
        => return applyHostEvent(vt, event),

        .line_feed, .next_line => {
            const active = vt.screen_state.active();
            const scrolls = active.cursor.row == active.scrollBottom();
            const history_scroll = !vt.screen_state.alt_active and active.scroll_top == 0 and
                active.scrollBottom() == active.rows - 1;
            if (!vt.screen_state.alt_active) {
                try vt.screen_state.primary.finalizeOutputLine(vt.allocator);
            }
            active.applyScreen(
                if (event == .next_line or vt.modes.newline_mode) .next_line else .line_feed,
            );
            if (scrolls and !history_scroll) {
                const graphics_changed = vt.graphics.scroll(
                    graphicsBank(vt),
                    graphicsScreenOrigin(vt) + active.scroll_top,
                    graphicsScreenOrigin(vt) + active.scrollBottom(),
                    1,
                    true,
                );
                std.debug.assert(!graphics_changed or vt.graphics.generation() != 0);
            }
        },
        .backspace => return vt.screen_state.active().backspace(vt.modes.reverse_wraparound_mode),
        .clear_buffer => return vt.clearBuffer(),
        .horizontal_tab => {
            const active = vt.screen_state.active();
            if (vt.modes.more_fix and active.wrap_pending) {
                if (!vt.screen_state.alt_active) {
                    try vt.screen_state.primary.finalizeOutputLine(vt.allocator);
                }
                active.applyScreen(.next_line);
                active.applyScreen(.horizontal_tab);
                return true;
            }
            active.applyScreen(.horizontal_tab);
            return true;
        },

        .erase_display_below => |protected| {
            const screen = vt.screen_state.active();
            const changed = screen.eraseDisplay(.cursor_to_end, protected);
            const origin = graphicsScreenOrigin(vt);
            var graphics_changed = vt.graphics.erase(
                graphicsBank(vt),
                origin + screen.cursor.row,
                origin + screen.cursor.row,
                screen.cursor.col,
                screen.cols - 1,
            );
            if (screen.cursor.row + 1 < screen.rows) graphics_changed =
                vt.graphics.erase(
                    graphicsBank(vt),
                    origin + screen.cursor.row + 1,
                    origin + screen.rows - 1,
                    0,
                    screen.cols - 1,
                ) or graphics_changed;
            return graphics_changed or changed;
        },
        .erase_display_above => |protected| {
            const screen = vt.screen_state.active();
            const changed = screen.eraseDisplay(.start_to_cursor, protected);
            const origin = graphicsScreenOrigin(vt);
            var graphics_changed = vt.graphics.erase(
                graphicsBank(vt),
                origin + screen.cursor.row,
                origin + screen.cursor.row,
                0,
                screen.cursor.col,
            );
            if (screen.cursor.row != 0) graphics_changed = vt.graphics.erase(
                graphicsBank(vt),
                origin,
                origin + screen.cursor.row - 1,
                0,
                screen.cols - 1,
            ) or graphics_changed;
            return graphics_changed or changed;
        },
        .erase_display_complete, .erase_display_scroll_complete => |protected| {
            const screen = vt.screen_state.active();
            const changed = screen.eraseDisplay(.all, protected);
            const origin = graphicsScreenOrigin(vt);
            return vt.graphics.erase(
                graphicsBank(vt),
                origin,
                origin + screen.rows - 1,
                0,
                screen.cols - 1,
            ) or changed;
        },
        .erase_display_scrollback => |protected| {
            return vt.screen_state.active().eraseDisplay(.scrollback, protected);
        },
        .erase_line => |mode| {
            const screen = vt.screen_state.active();
            const changed = screen.eraseLine(mode, false);
            const range = eraseLineColumns(screen, mode);
            return vt.graphics.erase(
                graphicsBank(vt),
                graphicsScreenOrigin(vt) + screen.cursor.row,
                graphicsScreenOrigin(vt) + screen.cursor.row,
                range[0],
                range[1],
            ) or changed;
        },
        .selective_erase_line => |mode| {
            return vt.screen_state.active().eraseLine(mode, true);
        },
        .erase_chars => |count| {
            const screen = vt.screen_state.active();
            const changed = screen.eraseChars(count);
            const right = @min(
                @as(u32, screen.cols - 1),
                @as(u32, screen.cursor.col) + @max(count, 1) - 1,
            );
            return vt.graphics.erase(
                graphicsBank(vt),
                graphicsScreenOrigin(vt) + screen.cursor.row,
                graphicsScreenOrigin(vt) + screen.cursor.row,
                screen.cursor.col,
                @intCast(right),
            ) or changed;
        },
        .rect_erase => |area| {
            const screen = vt.screen_state.active();
            const changed = screen.eraseRect(area, false);
            return eraseGraphicsRect(vt, screen, area) or changed;
        },
        .rect_selective_erase => |area| {
            const screen = vt.screen_state.active();
            const changed = screen.eraseRect(area, true);
            return eraseGraphicsRect(vt, screen, area) or changed;
        },
        .rect_fill => |request| return vt.screen_state.active().fillRect(request.area, request.ch),
        .rect_copy => |request| return vt.screen_state.active().copyRect(request),
        .rect_attrs_change => |request| return vt.screen_state.active().changeRectAttrs(
            request.area,
            request.attrs.params[0..request.attrs.param_count],
            request.reverse,
        ),
        .attr_change_extent_rect => |enabled| {
            return vt.screen_state.active().setRectAttrExtent(enabled);
        },
        .character_protection => |protection| {
            return vt.screen_state.active().setCharacterProtection(protection);
        },
        .repeat_preceding => |count| {
            return vt.screen_state.active().repeatPreceding(count);
        },
        .insert_columns => |count| {
            return vt.screen_state.active().insertColumns(count);
        },
        .delete_columns => |count| {
            return vt.screen_state.active().deleteColumns(count);
        },
        .insert_chars => |count| return vt.screen_state.active().insertChars(count),
        .delete_chars => |count| return vt.screen_state.active().deleteChars(count),
        .insert_lines => |count| {
            const screen = vt.screen_state.active();
            const changed = screen.insertLines(count);
            return vt.graphics.scroll(
                graphicsBank(vt),
                graphicsScreenOrigin(vt) + screen.cursor.row,
                graphicsScreenOrigin(vt) + screen.scrollBottom(),
                @max(count, 1),
                false,
            ) or changed;
        },
        .delete_lines => |count| {
            const screen = vt.screen_state.active();
            const changed = screen.deleteLines(count);
            return vt.graphics.scroll(
                graphicsBank(vt),
                graphicsScreenOrigin(vt) + screen.cursor.row,
                graphicsScreenOrigin(vt) + screen.scrollBottom(),
                @max(count, 1),
                true,
            ) or changed;
        },
        .scroll_up_lines => |count| {
            const screen = vt.screen_state.active();
            const changed = screen.scrollUpRegion(screen.scroll_top, screen.scrollBottom(), count);
            return vt.graphics.scroll(
                graphicsBank(vt),
                graphicsScreenOrigin(vt) + screen.scroll_top,
                graphicsScreenOrigin(vt) + screen.scrollBottom(),
                count,
                true,
            ) or changed;
        },
        .scroll_down_lines => |count| {
            const screen = vt.screen_state.active();
            const changed = screen.scrollDownRegion(screen.scroll_top, screen.scrollBottom(), count);
            return vt.graphics.scroll(
                graphicsBank(vt),
                graphicsScreenOrigin(vt) + screen.scroll_top,
                graphicsScreenOrigin(vt) + screen.scrollBottom(),
                count,
                false,
            ) or changed;
        },
        .forward_index => {
            const screen = vt.screen_state.active();
            const shifts = screen.cursor.col == screen.rightBoundary();
            const changed = screen.forwardIndex();
            if (!shifts) return changed;
            return vt.graphics.shiftColumns(
                graphicsBank(vt),
                graphicsScreenOrigin(vt) + screen.cursor.row,
                screen.leftBoundary(),
                screen.rightBoundary(),
                1,
                true,
            ) or changed;
        },
        .back_index => {
            const screen = vt.screen_state.active();
            const shifts = screen.cursor.col == screen.leftBoundary();
            const changed = screen.backIndex();
            if (!shifts) return changed;
            return vt.graphics.shiftColumns(
                graphicsBank(vt),
                graphicsScreenOrigin(vt) + screen.cursor.row,
                screen.leftBoundary(),
                screen.rightBoundary(),
                1,
                false,
            ) or changed;
        },
        .shift_left_columns => |count| return vt.screen_state.active().shiftColumnsLeft(count),
        .shift_right_columns => |count| return vt.screen_state.active().shiftColumnsRight(count),
        .reverse_index => {
            const screen = vt.screen_state.active();
            const scrolls = screen.cursor.row == screen.scroll_top;
            const changed = screen.reverseIndex();
            if (!scrolls) return changed;
            return vt.graphics.scroll(
                graphicsBank(vt),
                graphicsScreenOrigin(vt) + screen.scroll_top,
                graphicsScreenOrigin(vt) + screen.scrollBottom(),
                1,
                false,
            ) or changed;
        },
        .scroll_down_from_history => |count| return vt.screen_state.active().scrollDownFromHistory(count),
        .cursor_up,
        .cursor_down,
        .cursor_forward,
        .cursor_back,
        .cursor_next_line,
        .cursor_prev_line,
        .cursor_horizontal_absolute,
        .cursor_vertical_absolute,
        .cursor_position,
        => {
            const action = screenAction(event);
            std.debug.assert(action != null);
            return if (action) |value| vt.screen_state.active().moveCursor(value) else false;
        },
        .set_scroll_region => |region| {
            return vt.screen_state.active().setScrollRegion(region.top, region.bottom);
        },
        .set_left_right_margins => |margins| {
            return vt.screen_state.active().setLeftRightMargins(margins.left, margins.right);
        },
        .auto_wrap => |enabled| return vt.setDecMode(7, enabled),
        .origin_mode => |enabled| return vt.setDecMode(6, enabled),

        .write_text,
        .write_codepoint,
        .carriage_return,
        .horizontal_tab_forward,
        .horizontal_tab_back,
        .horizontal_tab_set,
        .tab_clear_current,
        .tab_clear_all,
        .cursor_color,
        .cursor_text_color,
        .insert_mode,
        .reset_default_tab_stops,
        => {
            const action = screenAction(event);
            std.debug.assert(action != null);
            if (action) |value| vt.screen_state.active().applyScreen(value);
        },
    }
    return true;
}

fn graphicsBank(vt: *const Terminal) graphics_mod.Bank {
    return if (vt.screen_state.alt_active) .alternate else .primary;
}

fn graphicsScreenOrigin(vt: *const Terminal) u64 {
    if (vt.screen_state.alt_active) return 0;
    const primary = &vt.screen_state.primary;
    return @as(u64, primary.historyRowBase()) + primary.historyCount();
}

fn eraseLineColumns(screen: *const Screen, mode: ScreenEraseMode) [2]u16 {
    return switch (mode) {
        .cursor_to_end => .{ screen.cursor.col, screen.cols - 1 },
        .start_to_cursor => .{ 0, screen.cursor.col },
        .all => .{ 0, screen.cols - 1 },
        .scrollback => unreachable,
    };
}

fn eraseGraphicsRect(vt: *Terminal, screen: *const Screen, area: RectArea) bool {
    if (area.top >= screen.rows or area.left >= screen.cols) return false;
    const bottom = @min(area.bottom orelse screen.rows - 1, screen.rows - 1);
    const right = @min(area.right orelse screen.cols - 1, screen.cols - 1);
    if (bottom < area.top or right < area.left) return false;
    const origin = graphicsScreenOrigin(vt);
    return vt.graphics.erase(
        graphicsBank(vt),
        origin + area.top,
        origin + bottom,
        area.left,
        right,
    );
}

// Reports parser allocation, parser bound, captured DCS bound, or retained-consequence failure.
const FeedError = error{
    ConsequenceLimit,
    OutOfMemory,
    PropertyLimit,
    ReplyLimit,
    ParsedEventLimit,
    StringControlLimit,
};

// Reports terminal mutation and distinct title or icon metadata changes.
const FeedSummary = struct {
    state_changed: bool,
    title_changed: bool,
    icon_changed: bool,
    history_lost: bool,
};

// Fragmented parser-stream ownership.

const DcsCapture = struct {
    const StartError = error{OutOfMemory};
    const PutError = error{ OutOfMemory, StringControlLimit };

    allocator: std.mem.Allocator,
    bytes: std.ArrayList(u8),
    params: [parser_mod.max_params]i32 = @as([parser_mod.max_params]i32, @splat(0)),
    intermediates: [parser_mod.max_intermediates]u8 = @as([parser_mod.max_intermediates]u8, @splat(0)),
    payload_start: usize = 0,
    final: u8 = 0,
    param_count: u8 = 0,
    intermediates_len: u8 = 0,
    active: bool = false,

    fn init(allocator: std.mem.Allocator) DcsCapture {
        return .{ .allocator = allocator, .bytes = .empty };
    }

    fn deinit(self: *DcsCapture) void {
        self.bytes.deinit(self.allocator);
    }

    fn reset(self: *DcsCapture) void {
        self.active = false;
        self.payload_start = 0;
        self.final = 0;
        self.param_count = 0;
        self.intermediates_len = 0;
        self.bytes.clearRetainingCapacity();
    }

    fn start(self: *DcsCapture, hook: parser_mod.DcsHook) StartError!void {
        std.debug.assert(hook.count <= parser_mod.max_params);
        std.debug.assert(hook.intermediates_len <= parser_mod.max_intermediates);
        self.reset();
        self.active = true;
        self.final = hook.final;
        self.param_count = hook.count;
        self.intermediates_len = hook.intermediates_len;
        std.mem.copyForwards(i32, self.params[0..hook.count], hook.params[0..hook.count]);
        std.mem.copyForwards(
            u8,
            self.intermediates[0..hook.intermediates_len],
            hook.intermediates[0..hook.intermediates_len],
        );

        errdefer self.reset();
        var idx: u8 = 0;
        while (idx < hook.count) : (idx += 1) {
            if (idx > 0) try self.bytes.append(self.allocator, ';');
            var text_buf: [32]u8 = undefined;
            const text = std.fmt.bufPrint(&text_buf, "{d}", .{hook.params[idx]}) catch unreachable;
            try self.bytes.appendSlice(self.allocator, text);
        }
        try self.bytes.appendSlice(self.allocator, self.intermediates[0..hook.intermediates_len]);
        try self.bytes.append(self.allocator, hook.final);
        self.payload_start = self.bytes.items.len;
    }

    fn put(self: *DcsCapture, byte: u8) PutError!void {
        std.debug.assert(self.active);
        const limit: usize = if (self.final == 'q' and self.intermediates_len == 0)
            sixel.max_encoded_bytes
        else
            parser_mod.max_metadata_control_bytes;
        if (self.bytes.items.len - self.payload_start >= limit) {
            return error.StringControlLimit;
        }
        try self.bytes.append(self.allocator, byte);
    }

    fn event(self: *const DcsCapture) parser_mod.Event {
        std.debug.assert(self.active);
        return .{ .dcs = .{
            .body = self.bytes.items,
            .payload = self.bytes.items[self.payload_start..],
            .final = self.final,
            .params = self.params[0..self.param_count],
            .param_count = self.param_count,
            .intermediates = self.intermediates[0..self.intermediates_len],
            .intermediates_len = self.intermediates_len,
        } };
    }
};

const StringCapture = struct {
    allocator: std.mem.Allocator,
    bytes: std.ArrayList(u8) = .empty,
    kind: ?StringPayloadKind = null,
    overflowed: bool = false,

    fn deinit(self: *StringCapture) void {
        self.bytes.deinit(self.allocator);
    }

    fn start(self: *StringCapture, kind: StringPayloadKind) void {
        self.bytes.clearRetainingCapacity();
        self.kind = kind;
        self.overflowed = false;
    }

    fn put(self: *StringCapture, byte: u8) error{OutOfMemory}!void {
        std.debug.assert(self.kind != null);
        if (self.overflowed) return;
        const limit: usize = if (self.kind == .apc and self.bytes.items.len != 0 and self.bytes.items[0] == 'G')
            graphics_mod.max_command_bytes + 1
        else
            dcs_payload_max_bytes;
        if (self.bytes.items.len >= limit) {
            self.overflowed = true;
            self.bytes.clearRetainingCapacity();
            return;
        }
        try self.bytes.append(self.allocator, byte);
    }

    fn reset(self: *StringCapture) void {
        self.bytes.clearRetainingCapacity();
        self.kind = null;
        self.overflowed = false;
    }
};

// Owns parser allocation and bounded DCS and generic string capture for one terminal lifetime.
const TerminalStreamState = struct {
    /// TerminalStream-state initialization can fail only while allocating parser storage.
    pub const InitError = error{OutOfMemory};

    parser: parser_mod.Parser,
    dcs: DcsCapture,
    string: StringCapture,

    /// Initializes parser storage and empty string captures with one borrowed allocator.
    fn initAlloc(allocator: std.mem.Allocator) InitError!TerminalStreamState {
        return .{
            .parser = try parser_mod.Parser.init(allocator),
            .dcs = DcsCapture.init(allocator),
            .string = .{ .allocator = allocator },
        };
    }

    /// Releases parser and string-capture allocations.
    fn deinit(self: *TerminalStreamState) void {
        self.dcs.deinit();
        self.string.deinit();
        self.parser.deinit();
    }
};

// Borrows one terminal while translating input bytes into terminal mutation.
const TerminalStream = struct {
    terminal: *Terminal,

    /// Creates a stream borrowing the terminal until the stream is discarded.
    fn init(terminal: *Terminal) TerminalStream {
        return .{ .terminal = terminal };
    }

    /// Feeds one byte and omits the optional mutation summary while preserving failures.
    fn next(self: *TerminalStream, byte: u8) FeedError!void {
        const summary = try self.nextSliceSummary(&.{byte});
        std.debug.assert(!summary.title_changed or summary.state_changed);
        std.debug.assert(!summary.icon_changed or summary.state_changed);
    }

    /// Feeds a borrowed byte slice and omits the optional mutation summary.
    fn nextSlice(self: *TerminalStream, bytes: []const u8) FeedError!void {
        const summary = try self.nextSliceSummary(bytes);
        std.debug.assert(!summary.title_changed or summary.state_changed);
        std.debug.assert(!summary.icon_changed or summary.state_changed);
    }

    fn nextSummary(self: *TerminalStream, byte: u8) FeedError!FeedSummary {
        var state_changed = false;
        var title_changed = false;
        var icon_changed = false;
        const state = &self.terminal.stream_state;

        errdefer {
            state.parser.reset();
            state.dcs.reset();
            state.string.reset();
        }

        const phases = state.parser.next(byte);
        if (state.parser.takeStringControlFailed()) |err| return err;

        for (phases) |phase| {
            if (phase) |action| {
                const effect = try self.applyAction(action);
                state_changed = state_changed or effect.changed;
                title_changed = title_changed or effect.title_changed;
                icon_changed = icon_changed or effect.icon_changed;
            }
        }

        return .{
            .state_changed = state_changed,
            .title_changed = title_changed,
            .icon_changed = icon_changed,
            .history_lost = false,
        };
    }

    /// Feeds a complete borrowed slice and merges per-byte mutation summaries.
    fn nextSliceSummary(self: *TerminalStream, bytes: []const u8) FeedError!FeedSummary {
        var summary: FeedSummary = .{
            .state_changed = false,
            .title_changed = false,
            .icon_changed = false,
            .history_lost = false,
        };
        var completed = false;
        defer if (!completed) self.terminal.completeStreamMutation(summary.state_changed);
        const history_loss_before = self.terminal.screen_state.primary.history_loss_generation;
        for (bytes) |byte| {
            const byte_summary = try self.nextSummary(byte);
            summary.state_changed = summary.state_changed or byte_summary.state_changed;
            summary.title_changed = summary.title_changed or byte_summary.title_changed;
            summary.icon_changed = summary.icon_changed or byte_summary.icon_changed;
        }
        summary.history_lost =
            self.terminal.screen_state.primary.history_loss_generation != history_loss_before;
        self.terminal.completeStreamMutation(summary.state_changed);
        completed = true;
        return summary;
    }

    fn applyAction(self: *TerminalStream, action: parser_mod.Action) FeedError!EventEffect {
        return switch (action) {
            .print => |cp| self.applyPrint(cp),
            .execute => |ctrl| self.applyExecute(ctrl),
            .invalid => try self.applyEvent(.invalid_sequence),
            .csi_dispatch => |csi| try self.applyEvent(.{ .style_change = .{
                .final = csi.final,
                .params = csi.params[0..csi.count],
                .separators = csi.separators,
                .param_count = csi.count,
                .leader = csi.leader,
                .private = csi.private,
                .intermediates = csi.intermediates[0..csi.intermediates_len],
                .intermediates_len = csi.intermediates_len,
            } }),
            .osc_dispatch => |osc| try self.applyEvent(.{ .osc = osc }),
            .screen_title => |title| try self.applyEvent(.{ .screen_title = title }),
            .apc_start => self.startString(.apc),
            .apc_put => |byte| self.putString(byte),
            .apc_end => self.endString(),
            .apc_cancel => self.cancelString(),
            .dcs_hook => |hook| self.startDcs(hook),
            .dcs_put => |byte| self.putDcs(byte),
            .dcs_unhook => self.endDcs(),
            .dcs_cancel => self.cancelDcs(),
            .pm_start => self.startString(.pm),
            .pm_put => |byte| self.putString(byte),
            .pm_end => self.endString(),
            .pm_cancel => self.cancelString(),
            .sos_start => self.startString(.sos),
            .sos_put => |byte| self.putString(byte),
            .sos_end => self.endString(),
            .sos_cancel => self.cancelString(),
            .esc_dispatch => |esc| self.applyEsc(esc),
        };
    }

    fn applyPrint(self: *TerminalStream, cp: u21) FeedError!EventEffect {
        const mapped = self.mapCodepoint(cp);
        if (mapped <= 0x7f) {
            const ascii: [1]u8 = .{@intCast(mapped)};
            return try self.applyEvent(.{ .text = ascii[0..] });
        }
        return try self.applyEvent(.{ .codepoint = mapped });
    }

    fn applyExecute(self: *TerminalStream, ctrl: u8) FeedError!EventEffect {
        switch (ctrl) {
            0x0E, 0x0F, 0x8E, 0x8F => {
                const slot: u8 = switch (ctrl) {
                    0x0E => 1,
                    0x0F => 0,
                    0x8E => 2,
                    0x8F => 3,
                    else => unreachable,
                };
                const changed = if (ctrl == 0x8E or ctrl == 0x8F)
                    self.terminal.charset.selectSingleShift(slot)
                else
                    self.terminal.charset.selectGl(slot);
                return .{
                    .changed = changed,
                    .title_changed = false,
                    .icon_changed = false,
                };
            },
            else => return try self.applyEvent(.{ .control = ctrl }),
        }
    }

    fn applyEsc(self: *TerminalStream, esc: parser_mod.EscAction) FeedError!EventEffect {
        if (esc.intermediates_len == 1) {
            switch (esc.intermediates[0]) {
                '(', ')', '*', '+' => {
                    const slot: u8 = switch (esc.intermediates[0]) {
                        '(' => 0,
                        ')' => 1,
                        '*' => 2,
                        '+' => 3,
                        else => unreachable,
                    };
                    const changed = self.terminal.charset.configureCharset(slot, esc.final);
                    return .{
                        .changed = changed,
                        .title_changed = false,
                        .icon_changed = false,
                    };
                },
                '#' => {
                    const active = self.terminal.screen_state.active();
                    const changed = switch (esc.final) {
                        '3' => active.applyLineGeometry(.double_height_top),
                        '4' => active.applyLineGeometry(.double_height_bottom),
                        '5' => active.applyLineGeometry(.single_width),
                        '6' => active.applyLineGeometry(.double_width),
                        '8' => active.alignmentDisplay(),
                        else => return try self.applyEvent(.{ .esc_dispatch = esc }),
                    };
                    return .{ .changed = changed, .title_changed = false, .icon_changed = false };
                },
                '%' => {
                    const latin1 = switch (esc.final) {
                        '@' => true,
                        'G' => false,
                        else => return try self.applyEvent(.{ .esc_dispatch = esc }),
                    };
                    return .{
                        .changed = self.terminal.stream_state.parser.selectLatin1(latin1),
                        .title_changed = false,
                        .icon_changed = false,
                    };
                },
                else => {},
            }
        }
        if (esc.intermediates_len == 0) {
            const changed = switch (esc.final) {
                'n' => self.terminal.charset.selectGl(2),
                'o' => self.terminal.charset.selectGl(3),
                '~' => self.terminal.charset.selectGr(1),
                '}' => self.terminal.charset.selectGr(2),
                '|' => self.terminal.charset.selectGr(3),
                'N' => self.terminal.charset.selectSingleShift(2),
                'O' => self.terminal.charset.selectSingleShift(3),
                else => return try self.applyEvent(.{ .esc_dispatch = esc }),
            };
            return .{ .changed = changed, .title_changed = false, .icon_changed = false };
        }
        return try self.applyEvent(.{ .esc_dispatch = esc });
    }

    fn applyEvent(self: *TerminalStream, event: parser_mod.Event) FeedError!EventEffect {
        return try applyParserEvent(self.terminal, event);
    }

    fn startDcs(self: *TerminalStream, hook: parser_mod.DcsHook) FeedError!EventEffect {
        try self.terminal.stream_state.dcs.start(hook);
        return .{
            .changed = false,
            .title_changed = false,
            .icon_changed = false,
        };
    }

    fn putDcs(self: *TerminalStream, byte: u8) FeedError!EventEffect {
        try self.terminal.stream_state.dcs.put(byte);
        return .{
            .changed = false,
            .title_changed = false,
            .icon_changed = false,
        };
    }

    fn endDcs(self: *TerminalStream) FeedError!EventEffect {
        const state = &self.terminal.stream_state;
        if (state.dcs.final == 'q' and state.dcs.intermediates_len == 0) {
            defer state.dcs.reset();
            return self.applySixel(
                state.dcs.bytes.items[state.dcs.payload_start..],
                state.dcs.params[0..state.dcs.param_count],
            );
        }
        const event = state.dcs.event();
        defer state.dcs.reset();
        return try applyParserEvent(self.terminal, event);
    }

    fn applySixel(self: *TerminalStream, payload: []const u8, params: []const i32) FeedError!EventEffect {
        if (params.len > 3) return discardedStringControl();
        for (params) |param| if (param < 0) return discardedStringControl();
        const p1: u16 = if (params.len > 0) @intCast(params[0]) else 0;
        const pan: u3 = switch (p1) {
            2 => 5,
            3, 4 => 3,
            7, 8, 9 => 1,
            else => 2,
        };
        const transparent = params.len > 1 and params[1] == 1;
        var image = sixel.decode(self.terminal.allocator, payload, .{
            .pan = pan,
            .pad = 1,
            .transparent = transparent,
        }) catch |failure| switch (failure) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Invalid, error.Unsupported, error.Quota => return discardedStringControl(),
        };
        errdefer image.deinit(self.terminal.allocator);
        const screen = self.terminal.screen_state.active();
        const cell_size = screen.cellPixelSize() orelse return discardedStringControl();
        const bank = graphicsBank(self.terminal);
        const row = if (self.terminal.modes.sixel_display_mode)
            graphicsScreenOrigin(self.terminal)
        else
            graphicsScreenOrigin(self.terminal) + screen.cursor.row;
        const col: u16 = if (self.terminal.modes.sixel_display_mode) 0 else screen.cursor.col;
        self.terminal.graphics.admitDecoded(
            image.pixels,
            image.width,
            image.height,
            bank,
            row,
            col,
            cell_size.width,
            cell_size.height,
        ) catch return discardedStringControl();
        image.pixels = &.{};
        if (!self.terminal.modes.sixel_display_mode) {
            const occupied_rows = (image.height + cell_size.height - 1) / cell_size.height;
            const saved_col = screen.cursor.col;
            var remaining = occupied_rows -| 1;
            while (remaining != 0) : (remaining -= 1) {
                const scrolls = screen.cursor.row == screen.scrollBottom();
                const history_scroll = !self.terminal.screen_state.alt_active and screen.scroll_top == 0 and
                    screen.scrollBottom() == screen.rows - 1;
                screen.lineFeed();
                if (scrolls and !history_scroll) {
                    const graphics_changed = self.terminal.graphics.scroll(
                        bank,
                        graphicsScreenOrigin(self.terminal) + screen.scroll_top,
                        graphicsScreenOrigin(self.terminal) + screen.scrollBottom(),
                        1,
                        true,
                    );
                    std.debug.assert(!graphics_changed or self.terminal.graphics.generation() != 0);
                }
            }
            screen.cursor.col = @min(saved_col, screen.lineRightBoundary(screen.cursor.row));
            screen.wrap_pending = false;
        }
        return .{ .changed = true, .title_changed = false, .icon_changed = false };
    }

    fn cancelDcs(self: *TerminalStream) EventEffect {
        self.terminal.stream_state.dcs.reset();
        return discardedStringControl();
    }

    fn startString(self: *TerminalStream, kind: StringPayloadKind) EventEffect {
        self.terminal.stream_state.string.start(kind);
        return discardedStringControl();
    }

    fn putString(self: *TerminalStream, byte: u8) FeedError!EventEffect {
        try self.terminal.stream_state.string.put(byte);
        return discardedStringControl();
    }

    fn endString(self: *TerminalStream) FeedError!EventEffect {
        const capture = &self.terminal.stream_state.string;
        if (capture.overflowed) {
            if (capturedKittyGraphics(capture)) self.terminal.graphics.cancel();
            capture.reset();
            return discardedStringControl();
        }
        if (capture.kind == .apc and capture.bytes.items.len != 0 and capture.bytes.items[0] == 'G') {
            defer capture.reset();
            return .{
                .changed = try applyKittyGraphicsPacket(self.terminal, capture.bytes.items[1..]),
                .title_changed = false,
                .icon_changed = false,
            };
        }
        const payload: consequences.StringInput = .{ .kind = capture.kind.?, .payload = capture.bytes.items };
        defer capture.reset();
        return .{
            .changed = try applySemantic(self.terminal, .{ .string_payload = payload }),
            .title_changed = false,
            .icon_changed = false,
        };
    }

    fn cancelString(self: *TerminalStream) EventEffect {
        const capture = &self.terminal.stream_state.string;
        if (capturedKittyGraphics(capture)) self.terminal.graphics.cancel();
        capture.reset();
        return discardedStringControl();
    }

    fn mapCodepoint(self: *TerminalStream, cp: u21) u21 {
        return self.terminal.charset.mapCodepoint(cp);
    }
};

fn capturedKittyGraphics(capture: *const StringCapture) bool {
    return capture.kind == .apc and capture.bytes.items.len != 0 and capture.bytes.items[0] == 'G';
}

fn discardedStringControl() EventEffect {
    return .{
        .changed = false,
        .title_changed = false,
        .icon_changed = false,
    };
}

fn applyKittyGraphicsPacket(terminal: *Terminal, packet: []const u8) ApplyError!bool {
    const response_reserve: usize = 96;
    if (graphics_mod.mayRespond(packet)) {
        if (terminal.reply_buffer.bytes().len >
            replies.max_bytes - response_reserve)
            return error.ReplyLimit;
        try terminal.reply_buffer.ensureUnusedCapacity(response_reserve);
    }
    const active = terminal.screen_state.activeConst();
    const bank: graphics_mod.Bank = if (terminal.screen_state.alt_active) .alternate else .primary;
    const row: u64 = if (bank == .alternate)
        active.cursor.row
    else
        @as(u64, active.history_row_base) + active.history_count + active.cursor.row;
    const cell = active.cellPixelSize();
    const result = try terminal.graphics.command(
        packet,
        bank,
        if (bank == .alternate) 0 else @as(u64, active.history_row_base) + active.history_count,
        row,
        active.cursor.col,
        if (cell) |value| value.width else 1,
        if (cell) |value| value.height else 1,
    );
    const respond = result.failure != null or result.response_id != null or
        result.response_number != null or result.response_frame != null;
    const suppressed = result.quiet == 2 or (result.quiet == 1 and result.failure == null);
    if (respond and !suppressed) {
        try terminal.reply_buffer.append("\x1b_G");
        var metadata: [48]u8 = undefined;
        if (result.response_id) |id| {
            const id_bytes = if (result.response_number) |number|
                if (result.response_frame) |frame_number|
                    std.fmt.bufPrint(&metadata, "i={d},I={d},r={d};", .{ id, number, frame_number })
                else
                    std.fmt.bufPrint(&metadata, "i={d},I={d};", .{ id, number })
            else if (result.response_frame) |frame_number|
                std.fmt.bufPrint(&metadata, "i={d},r={d};", .{ id, frame_number })
            else
                std.fmt.bufPrint(&metadata, "i={d};", .{id});
            const written = id_bytes catch return error.ReplyLimit;
            try terminal.reply_buffer.append(written);
        } else if (result.response_number) |number| {
            const number_bytes = std.fmt.bufPrint(&metadata, "I={d};", .{number}) catch
                return error.ReplyLimit;
            try terminal.reply_buffer.append(number_bytes);
        } else {
            try terminal.reply_buffer.append(";");
        }
        try terminal.reply_buffer.append(
            if (result.failure) |failure| failure.bytes() else "OK",
        );
        try terminal.reply_buffer.append("\x1b\\");
    }

    return result.changed or (respond and !suppressed);
}

test "stream state initialization reports parser allocation failure" {
    const init: *const fn (
        std.mem.Allocator,
    ) TerminalStreamState.InitError!TerminalStreamState = TerminalStreamState.initAlloc;
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, init(failing.allocator()));
    try std.testing.expect(failing.has_induced_failure);
}

test "DCS capture start and put report exact failures and remain reusable" {
    const start: *const fn (*DcsCapture, parser_mod.DcsHook) DcsCapture.StartError!void = DcsCapture.start;
    const put: *const fn (*DcsCapture, u8) DcsCapture.PutError!void = DcsCapture.put;
    const hook: parser_mod.DcsHook = .{
        .final = 'q',
        .params = &.{1},
        .count = 1,
        .intermediates = "$",
        .intermediates_len = 1,
    };

    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var capture = DcsCapture.init(failing.allocator());
    defer capture.deinit();

    try std.testing.expectError(error.OutOfMemory, start(&capture, hook));
    try std.testing.expect(!capture.active);
    try std.testing.expectEqual(@as(usize, 0), capture.bytes.items.len);

    failing.fail_index = std.math.maxInt(usize);
    try start(&capture, hook);
    const payload_start = capture.payload_start;
    failing.fail_index = failing.alloc_index;

    var put_count: u32 = 0;
    while (!failing.has_induced_failure) : (put_count += 1) {
        try std.testing.expect(put_count < parser_mod.max_metadata_control_bytes);
        put(&capture, 'x') catch |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            break;
        };
    }
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expect(capture.active);
    try std.testing.expectEqual(payload_start + put_count, capture.bytes.items.len);

    failing.fail_index = std.math.maxInt(usize);
    try put(&capture, 'y');
    while (capture.bytes.items.len - capture.payload_start < parser_mod.max_metadata_control_bytes) {
        try put(&capture, 'z');
    }
    try std.testing.expectError(error.StringControlLimit, put(&capture, 'z'));
    capture.reset();
    try std.testing.expect(!capture.active);
    try start(&capture, hook);
}

test "discarded string controls stream without retaining payload bytes" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 2);
    defer terminal.deinit();
    var stream = TerminalStream.init(&terminal);

    try stream.nextSlice("\x1b_G");
    try stream.nextSlice(&@as([8192]u8, @splat('x')));
    try stream.nextSlice("\x1b\\");
    try stream.nextSlice("\x1b^");
    try stream.nextSlice(&@as([8192]u8, @splat('y')));
    try stream.nextSlice("\x1b\\");
    try stream.nextSlice("\x1bX");
    try stream.nextSlice(&@as([8192]u8, @splat('z')));
    try stream.nextSlice("\x1b\\");
    try stream.nextSlice("ok");

    const view = terminal.semanticView(0);
    try std.testing.expectEqual(@as(u21, 'o'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'k'), view.cellAt(0, 1));
}

test "xterm pointer mode retains the clamped protocol resource value" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expectEqual(@as(u2, 1), terminal.modes.pointer_mode);
    try std.testing.expect((try terminal.feed("\x1b[>2p")).state_changed);
    try std.testing.expectEqual(@as(u2, 2), terminal.modes.pointer_mode);
    try std.testing.expect((try terminal.feed("\x1b[>9p")).state_changed);
    try std.testing.expectEqual(@as(u2, 3), terminal.modes.pointer_mode);
    try std.testing.expect((try terminal.feed("\x1b[>p")).state_changed);
    try std.testing.expectEqual(@as(u2, 1), terminal.modes.pointer_mode);
}

test "text extraction reports impossible retained codepoints exactly" {
    var terminal = try Terminal.init(std.testing.allocator, 1, 1);
    defer terminal.deinit();
    const range: Terminal.TextRange = .{
        .start = .{ .row = 0, .col = 0 },
        .end = .{ .row = 0, .col = 0 },
    };

    terminal.screen_state.primary.cells.?[0].codepoint = 0x110000;
    try std.testing.expectError(
        error.CodepointTooLarge,
        terminal.copyText(std.testing.allocator, range, std.math.maxInt(usize)),
    );
    terminal.screen_state.primary.cells.?[0].codepoint = 0xD800;
    try std.testing.expectError(
        error.Utf8CannotEncodeSurrogateHalf,
        terminal.copyText(std.testing.allocator, range, std.math.maxInt(usize)),
    );
}

const RestoredCursorInformation = struct {
    row: u16,
    col: u16,
    reverse: bool,
    blink: bool,
    underline: bool,
    bold: bool,
    wrap_pending: bool,
    origin_mode: bool,
    g0_designation: u8,
};

// Parses the VT300 DECCIR fields that iTerm2 applies while validating the
// complete four-slot designation suffix before any terminal mutation.
fn parseCursorInformation(payload: []const u8) ?RestoredCursorInformation {
    var fields: [10][]const u8 = undefined;
    var parts = std.mem.splitScalar(u8, payload, ';');
    for (&fields) |*field| field.* = parts.next() orelse return null;
    if (parts.next() != null) return null;

    const row = parsePresentationCoordinate(fields[0]) orelse return null;
    const col = parsePresentationCoordinate(fields[1]) orelse return null;
    if (parseDecimalPresentationField(fields[2]) == null) return null;
    if (fields[3].len != 1 or fields[4].len != 1 or fields[5].len != 1 or fields[8].len != 1)
        return null;

    const rendition = fields[3][0];
    if (rendition & 0xf0 != 0x40) return null;
    if (parseDecimalPresentationField(fields[6]) == null or
        parseDecimalPresentationField(fields[7]) == null) return null;

    var designation_offset: usize = 0;
    var g0_designation: u8 = 0;
    for (0..4) |slot| {
        const designation = consumePresentationDesignation(fields[9], &designation_offset) orelse return null;
        if (slot == 0) g0_designation = designation;
    }
    if (designation_offset != fields[9].len or g0_designation == '%') return null;

    return .{
        .row = row,
        .col = col,
        .reverse = rendition & 8 != 0,
        .blink = rendition & 4 != 0,
        .underline = rendition & 2 != 0,
        .bold = rendition & 1 != 0,
        .wrap_pending = fields[5][0] & 8 != 0,
        .origin_mode = fields[5][0] & 1 != 0,
        .g0_designation = g0_designation,
    };
}

fn parsePresentationCoordinate(field: []const u8) ?u16 {
    const value = parseDecimalPresentationField(field) orelse return null;
    return @intCast(@min(value -| 1, std.math.maxInt(u16)));
}

fn parseDecimalPresentationField(field: []const u8) ?u32 {
    return std.fmt.parseInt(u32, field, 10) catch null;
}

fn consumePresentationDesignation(payload: []const u8, offset: *usize) ?u8 {
    if (offset.* >= payload.len) return null;
    const byte = payload[offset.*];
    if (byte == '%' and offset.* + 1 < payload.len and payload[offset.* + 1] == '5') {
        offset.* += 2;
        return '%';
    }
    if (byte != 'B' and byte != '0') return null;
    offset.* += 1;
    return byte;
}

// Public terminal composition and lifecycle.

/// Host-neutral terminal state and protocol engine.
pub const Terminal = struct {
    /// Borrows a unified history-and-screen viewport until terminal mutation.
    pub const SemanticView = struct {
        rows: u16,
        cols: u16,
        cursor_row: u16,
        cursor_col: u16,
        cursor_visible: bool,
        cursor_shape: Screen.CursorShape,
        cursor_blink: bool,
        is_alternate_screen: bool,
        history_offset: u32,
        history_count: u32,
        history_row_base: u32,
        start: u32,
        screen: *const Screen,

        fn rowSource(self: *const SemanticView, row: u16) RowSource {
            if (self.rows == 0 or row >= self.rows) return .{ .screen = 0 };
            const src_row = self.start + rowIndex(row);
            std.debug.assert(self.start + rowIndex(self.rows) <= self.history_count + rowIndex(self.rows));
            std.debug.assert(src_row >= self.start);
            std.debug.assert(src_row < self.history_count + rowIndex(self.rows));
            if (src_row < self.history_count) return .{ .history = self.history_count - 1 - src_row };
            return .{ .screen = @intCast(@min(src_row - self.history_count, rowIndex(self.rows -| 1))) };
        }

        /// Borrows one complete visible row until the terminal is mutated.
        ///
        /// `row` must be in bounds. History and active-screen storage remain
        /// private; the returned cells share this view's mutation lifetime.
        pub fn rowCells(self: *const SemanticView, row: u16) []const Cell {
            std.debug.assert(row < self.rows);
            return switch (self.rowSource(row)) {
                .history => |recency| self.screen.historyRowCells(recency),
                .screen => |screen_row| self.screen.visibleRowCells(screen_row),
            };
        }

        /// Returns a copied viewport cell or the default cell for invalid coordinates.
        pub fn cellInfoAt(self: *const SemanticView, row: u16, col: u16) Cell {
            if (self.rows == 0 or row >= self.rows or col >= self.cols) return Screen.default_cell;
            return self.rowCells(row)[col];
        }

        /// Returns the codepoint of one visible cell.
        pub fn cellAt(self: *const SemanticView, row: u16, col: u16) u21 {
            return @intCast(self.cellInfoAt(row, col).codepoint);
        }

        /// Returns one visible row's DEC geometry without prescribing host scaling.
        pub fn lineGeometry(self: *const SemanticView, row: u16) Screen.LineGeometry {
            return switch (self.rowSource(row)) {
                .history => |recency| self.screen.historyLineGeometry(recency),
                .screen => |screen_row| self.screen.lineGeometry(screen_row),
            };
        }

        /// Returns the display depth contributed by one visible row.
        pub fn rowDepth(self: *const SemanticView, row: u16) u32 {
            if (self.rows == 0 or row >= self.rows) return self.history_offset;
            std.debug.assert(self.history_offset <= self.history_count);
            return self.history_offset + rowIndex(self.rows - 1 - row);
        }

        /// Returns the first blank column after visible row content.
        pub fn contentEndExclusive(self: *const SemanticView, row: u16) u16 {
            if (self.history_offset == 0 and row > self.cursor_row) return 0;
            var scan = self.cols;
            while (scan > 0) {
                const idx = scan - 1;
                const cell = self.cellInfoAt(row, idx);
                if (cell.codepoint != 0 and cell.codepoint != ' ') return scan;
                scan -= 1;
            }
            return if (self.cols > 0) 1 else 0;
        }
    };
    /// Identifies one cell in stable projected history-and-screen coordinates.
    pub const TextPoint = TerminalTextPoint;
    /// Identifies an inclusive text range supplied by the embedder.
    pub const TextRange = TerminalTextRange;
    /// Reports exact terminal-text extraction failures.
    pub const TextError = CopyError;
    /// Names one host-neutral request from the child to manipulate its containing window.
    pub const WindowOperation = WindowRequest;
    /// Copies one accepted ordered window request and its monotonic identity.
    pub const WindowOccurrence = WindowRequestOccurrence;
    /// Supplies one host-owned fact requested by a retained window query.
    pub const WindowQueryReply = WindowReply;
    /// Reports invalid zero dimensions or allocation failure during construction.
    pub const InitError = error{ InvalidDimensions, OutOfMemory };
    /// Reports invalid dimensions, bounded reply saturation, or allocation failure before resize mutation.
    pub const ResizeError = error{ InvalidDimensions, ConsequenceLimit, ReplyLimit } || std.mem.Allocator.Error;
    /// Reports a zero cell-pixel dimension before any screen mutation.
    pub const CellPixelSizeError = error{InvalidDimensions};
    /// Copies one nonzero host-provided terminal cell size in logical pixels.
    pub const CellPixelSize = struct {
        width: u32,
        height: u32,
    };
    /// Selects one host-observed color-scheme preference for a Kitty notification.
    pub const ColorSchemePreference = enum {
        dark,
        light,
    };
    /// Reports stale query identity, allocation failure, or bounded reply saturation.
    pub const ColorPreferenceReplyError = ApplyError || error{StaleColorPreferenceQuery};
    /// Borrows validated shell-integration identity from one state snapshot.
    pub const ShellIntegration = ItermShellIntegration;
    /// Borrows the latest child-reported directory bytes and their URI-or-path interpretation.
    pub const WorkingDirectory = WorkingDirectoryReport;
    /// Reports stale or non-query identity, allocation failure, or bounded OSC 22 reply saturation.
    pub const PointerShapeReplyError = ApplyError || error{ StalePointerShape, PointerShapeReplyMismatch };
    /// Exposes one parsed ordered Kitty OSC 72 command.
    pub const DragDropCommand = DragDropCommandView;
    /// Exposes one typed host-to-child Kitty OSC 72 event.
    pub const DragDropEvent = DragDropEventValue;
    /// Reports bounded OSC 72 event construction failure.
    pub const DragDropEventError = error{ OutOfMemory, ConsequenceLimit, ReplyLimit, InvalidArgument };
    /// Exposes the typed host-input vocabulary accepted by encodeInput.
    pub const InputEvent = input.Event;
    /// Exposes named physical keys whose terminal identity is not Unicode text.
    pub const NamedKey = input.KeyName;
    /// Validates Unicode physical-key identities before input encoding.
    pub const Key = input.InputKey;
    /// Provides caller-owned fixed scratch storage for allocation-free input encoding.
    pub const InputScratch = input.Scratch;
    /// Returns encoded input with explicit borrowed-or-owned byte lifetime.
    pub const EncodedInput = input.Encoded;
    /// Reports paste construction or bounded locator-report retention failure.
    pub const InputError = input.PasteError || replies.AppendError ||
        error{ InvalidUtf8, InvalidText, KeyTextLimit };
    /// Reports stale identity, allocation, or bounded reply saturation without consuming a clipboard query.
    pub const ClipboardReplyError = error{ OutOfMemory, ConsequenceLimit, PropertyLimit, ReplyLimit, StaleClipboardRequest };
    /// Reports a reply prefix larger than the currently retained byte count.
    pub const ReplyConsumeError = error{InvalidReplyCount};
    /// Reports stale identity, allocation, or bounded transfer saturation for one Kitty clipboard packet.
    /// Reports stale or mismatched host facts, allocation failure, or bounded reply saturation.
    pub const WindowReplyError = ApplyError || error{ StaleWindowRequest, WindowReplyMismatch };
    /// Exposes one borrowed OSC 52 operation or Kitty OSC 5522 packet.
    pub const ClipboardRequest = ClipboardRequestView;
    /// Identifies one retained color-preference query.
    pub const ColorPreferenceQuery = struct {
        id: u64,
    };
    /// Identifies one accepted BEL control.
    pub const Bell = struct {
        id: u64,
    };
    /// Exposes one ordered legacy terminal-mode transition.
    pub const LegacyControl = LegacyControlOccurrence;
    /// Borrows exactly one host-neutral terminal consequence.
    pub const Consequence = union(enum) {
        clipboard: ClipboardRequest,
        notification: Notification,
        pointer_shape: PointerShapeRequest,
        file_transfer: FileTransferPacket,
        drag_drop: DragDropCommand,
        window: WindowOccurrence,
        color_preference_query: ColorPreferenceQuery,
        bell: Bell,
        legacy_control: LegacyControl,
        media_copy: MediaCopyOccurrence,
        dcs: DcsPayloadOccurrence,
        string_control: StringPayloadOccurrence,

        /// Returns the process-lifetime occurrence identity.
        pub fn id(self: Consequence) u64 {
            return switch (self) {
                .clipboard => |value| value.generation,
                .notification => |value| value.generation,
                .pointer_shape => |value| value.generation,
                .file_transfer => |value| value.generation,
                .drag_drop => |value| value.generation,
                .window => |value| value.generation,
                .color_preference_query => |value| value.id,
                .bell => |value| value.id,
                .legacy_control => |value| value.generation,
                .media_copy => |value| value.generation,
                .dcs => |value| value.generation,
                .string_control => |value| value.generation,
            };
        }
    };
    /// Reports stale occurrence identity or a consequence requiring a reply.
    pub const ConsumeConsequenceError = error{ StaleConsequence, ReplyRequired };
    /// Uses the canonical copied terminal RGB value.
    pub const Rgb = Screen.Rgb;
    /// Uses the canonical default, indexed, or RGB cell color.
    pub const Color = Screen.Color;
    /// Uses the canonical complete cell attribute value.
    pub const CellAttrs = Screen.CellAttrs;
    /// Borrows one complete terminal cell.
    pub const Cell = Screen.Cell;
    /// Uses the canonical terminal underline style.
    pub const UnderlineStyle = Screen.UnderlineStyle;
    /// Uses the canonical terminal baseline displacement.
    pub const Baseline = Screen.Baseline;
    /// Uses the canonical resolved cursor shape.
    pub const CursorShape = Screen.CursorShape;
    /// Uses one row's DEC presentation geometry.
    pub const LineGeometry = Screen.LineGeometry;
    /// Provides the canonical default terminal cell attributes.
    pub const default_cell_attrs = Screen.default_cell_attrs;
    /// Provides the immutable terminal palette and dynamic-color defaults.
    pub const default_presentation = defaultPresentation();
    /// Borrows one immutable decoded terminal image.
    pub const Image = graphics_mod.ImageView;
    /// Reports one VT-owned image-animation service result.
    pub const GraphicsTick = graphics_mod.AnimationTick;
    /// Copies one image placement resolved into the visible viewport.
    pub const ImagePlacement = struct {
        /// Resolves retained image content.
        image_id: u32,
        /// Distinguishes placement churn.
        generation: u64,
        /// Identifies the visible viewport row.
        row: u16,
        /// Identifies the physical terminal column.
        col: u16,
        /// Selects the first decoded source column.
        source_x: u32,
        /// Selects the first decoded source row.
        source_y: u32,
        /// Counts selected decoded source columns.
        source_width: u32,
        /// Counts selected decoded source rows.
        source_height: u32,
        /// Offsets the destination within its anchor cell horizontally.
        cell_x: u32,
        /// Offsets the destination within its anchor cell vertically.
        cell_y: u32,
        /// Counts destination pixels horizontally.
        pixel_width: u32,
        /// Counts destination pixels vertically.
        pixel_height: u32,
        /// Orders the image relative to terminal text.
        z: i32,
    };
    /// Borrows coherent image-plane facts until terminal mutation.
    pub const Images = struct {
        plane: *const graphics_mod.Plane,
        bank: graphics_mod.Bank,
        visible_row_start: u64,
        rows: u16,
        generation: u64,
        content_generation: u64,

        /// Returns the dense retained image count.
        pub fn imageCount(self: *const Images) usize {
            return self.plane.image_count;
        }

        /// Borrows one retained image.
        pub fn image(self: *const Images, index: usize) ?Image {
            return self.plane.image(index);
        }

        /// Returns the dense retained placement count.
        pub fn placementCount(self: *const Images) usize {
            return self.plane.placement_count;
        }

        /// Copies one placement visible in the current bank and viewport.
        pub fn placement(self: *const Images, index: usize) ?ImagePlacement {
            const value = self.plane.placement(index) orelse return null;
            if (value.bank != self.bank or value.row < self.visible_row_start or
                value.row >= self.visible_row_start + self.rows)
                return null;
            return .{
                .image_id = value.image_id,
                .generation = value.generation,
                .row = @intCast(value.row - self.visible_row_start),
                .col = value.col,
                .source_x = value.source_x,
                .source_y = value.source_y,
                .source_width = value.source_width,
                .source_height = value.source_height,
                .cell_x = value.cell_x,
                .cell_y = value.cell_y,
                .pixel_width = value.pixel_width,
                .pixel_height = value.pixel_height,
                .z = value.z,
            };
        }
    };
    /// Names why one finalized logical line has no retained text.
    pub const LogicalOutputLossReason = OutputLossReason;

    /// Copies bounded evidence for one finalized line whose text was omitted.
    pub const LogicalOutputLoss = struct {
        /// Identifies the omitted finalized line in output order.
        id: u64,
        /// Reports the exact UTF-8 byte count measured without retaining text.
        byte_count: usize,
        /// Reports why the finalized text was not retained.
        reason: LogicalOutputLossReason,
    };

    /// Owns one bounded copy of finalized primary output and the current open line.
    pub const LogicalOutput = struct {
        /// Frees both copied slices for this result.
        allocator: std.mem.Allocator,
        /// Contains newline-separated finalized lines after the requested cursor.
        text: []u8,
        /// Contains the current primary logical line for this semantic observation.
        open_line: []u8,
        /// Reports that the open line did not fit after copied finalized evidence.
        open_line_omitted: bool,
        /// Owns ordered loss evidence within the copied cursor interval.
        losses: []LogicalOutputLoss,
        /// Identifies the oldest finalized line still retained.
        oldest: u64,
        /// Identifies the last finalized line copied, or the requested cursor.
        cursor: u64,
        /// Identifies the newest finalized line retained at observation time.
        newest: u64,
        /// Counts finalized lines copied into `text`.
        line_count: u16,
        /// Reports that another finalized line remains after `cursor`.
        more: bool,
        /// Binds `open_line` to one terminal semantic-state observation.
        semantic_sequence: u64,

        /// Releases both copied byte slices exactly once.
        pub fn deinit(self: *LogicalOutput) void {
            self.allocator.free(self.losses);
            self.allocator.free(self.open_line);
            self.allocator.free(self.text);
            self.* = undefined;
        }
    };

    /// Distinguishes copied output from exact cursor and retention failures.
    pub const LogicalOutputResult = union(enum) {
        /// Owns copied finalized and semantic-observation-scoped open output.
        output: LogicalOutput,
        /// Reports the oldest cursor after whole-line retention eviction.
        cursor_stale: u64,
        /// Reports the newest cursor when a request is from the future.
        cursor_ahead: u64,
        /// Identifies a retained line requiring a larger bounded request.
        line_too_long: u64,
        /// Reports that the open line alone exceeds the requested byte bound.
        open_line_too_long,
    };

    /// Reports invalid zero limits or copy allocation failure.
    pub const LogicalOutputError = std.mem.Allocator.Error || error{InvalidLimit};

    /// Copies the retained finalized-line identity bounds without output bytes.
    pub const LogicalOutputRange = struct {
        /// Identifies the oldest retained line, or the next identity when empty.
        oldest: u64,
        /// Identifies the newest retained line, or zero when empty.
        newest: u64,
    };

    const ScreenSet = Set;

    allocator: std.mem.Allocator,
    stream_state: TerminalStreamState,
    screen_state: ScreenSet,
    graphics: graphics_mod.Plane,
    modes: modes_mod.State = .{},
    saved_all_modes: SavedAllModes = .{},
    kitty: modes_mod.KeyboardState = .{},
    sgr_stack: [sgr_stack_capacity]SgrStackEntry = @splat(.{}),
    sgr_stack_len: u8 = 0,
    xtchecksum_flags: u16 = 0,
    properties: properties.State,
    reply_buffer: replies.Buffer,
    consequences: consequences.State,
    locator: Locator = .{},
    charset: charset_mod.State = .{},
    primary_savepoint: Savepoint = .{},
    alternate_savepoint: Savepoint = .{},
    semantic_sequence: u64 = 1,
    fn initWithScreens(
        allocator: std.mem.Allocator,
        stream_state: TerminalStreamState,
        state: Screen,
        alt_state: Screen,
    ) Terminal {
        return .{
            .allocator = allocator,
            .stream_state = stream_state,
            .screen_state = ScreenSet.init(state, alt_state),
            .graphics = graphics_mod.Plane.init(allocator),
            .properties = properties.State.init(allocator),
            .reply_buffer = replies.Buffer.init(allocator),
            .consequences = consequences.State.init(allocator),
        };
    }

    /// Initialize terminal state with owned primary and alternate cell storage.
    ///
    /// Both dimensions must be nonzero. The caller owns the returned terminal
    /// and must call `deinit`.
    pub fn init(allocator: std.mem.Allocator, rows: u16, cols: u16) InitError!Terminal {
        try validateDimensions(rows, cols);
        var stream_state = try TerminalStreamState.initAlloc(allocator);
        errdefer stream_state.deinit();
        var state = try Screen.initWithCells(allocator, rows, cols);
        errdefer state.deinit(allocator);
        var alt_state = try Screen.initWithCells(allocator, rows, cols);
        errdefer alt_state.deinit(allocator);
        return initWithScreens(allocator, stream_state, state, alt_state);
    }

    /// Initialize terminal state with owned cells and bounded primary history.
    ///
    /// Both dimensions must be nonzero. The caller owns the returned terminal
    /// and must call `deinit`. `history_capacity` bounds retained logical rows;
    /// the alternate screen never retains history.
    pub fn initWithHistory(
        allocator: std.mem.Allocator,
        rows: u16,
        cols: u16,
        history_capacity: u16,
    ) InitError!Terminal {
        try validateDimensions(rows, cols);
        var stream_state = try TerminalStreamState.initAlloc(allocator);
        errdefer stream_state.deinit();
        var state = try Screen.initWithCellsAndHistory(allocator, rows, cols, history_capacity);
        errdefer state.deinit(allocator);
        var alt_state = try Screen.initWithCells(allocator, rows, cols);
        errdefer alt_state.deinit(allocator);
        return initWithScreens(allocator, stream_state, state, alt_state);
    }

    /// Release Terminal resources.
    pub fn deinit(self: *Terminal) void {
        const allocator = self.allocator;
        self.graphics.deinit();
        self.consequences.deinit();
        self.properties.deinit();
        self.reply_buffer.deinit();
        self.screen_state.deinit(allocator);
        self.stream_state.deinit();
    }

    /// Applies a borrowed byte slice and reports mutation; failures reset transient parser state.
    pub fn feed(self: *Terminal, bytes: []const u8) FeedError!FeedSummary {
        var stream = TerminalStream.init(self);
        return stream.nextSliceSummary(bytes);
    }

    fn completeStreamMutation(
        self: *Terminal,
        state_changed: bool,
    ) void {
        const graphics_changed = self.graphics.evictBefore(
            self.screen_state.primary.historyRowBase(),
        );
        self.postApply(state_changed or graphics_changed);
    }

    /// Advances semantic mutation identity after routing.
    fn postApply(self: *Terminal, state_changed: bool) void {
        if (state_changed) advanceIdentity(&self.semantic_sequence);
    }

    /// Resize both terminal screens.
    ///
    /// Both dimensions must be nonzero. Invalid dimensions or allocation
    /// failure leave both screens and terminal semantic identity unchanged.
    pub fn resize(self: *Terminal, rows: u16, cols: u16) ResizeError!void {
        try validateDimensions(rows, cols);
        const output_before = byteCount(self.reply_buffer.bytes());
        errdefer self.reply_buffer.truncate(output_before);
        if (self.modes.inband_resize_notifications) try self.appendInbandResizeReport(rows, cols);
        try self.screen_state.resize(self.allocator, rows, cols);
        const primary_graphics_changed = self.graphics.clearBank(.primary);
        const alternate_graphics_changed = self.graphics.clearBank(.alternate);
        std.debug.assert(!primary_graphics_changed or self.graphics.generation() != 0);
        std.debug.assert(!alternate_graphics_changed or self.graphics.generation() != 0);
        advanceIdentity(&self.semantic_sequence);
    }

    // Appends one exact iTerm2/Kitty mode-2048 resize report when host pixel facts are known.
    fn appendInbandResizeReport(self: *Terminal, rows: u16, cols: u16) ResizeError!void {
        const cell = self.cellPixelSize() orelse return;
        const pixel_height = @as(u64, cell.height) * @as(u64, rows);
        const pixel_width = @as(u64, cell.width) * @as(u64, cols);
        var scratch: [96]u8 = undefined;
        const payload = std.fmt.bufPrint(
            scratch[0..],
            "48;{d};{d};{d};{d}t",
            .{ rows, cols, pixel_height, pixel_width },
        ) catch unreachable;
        try self.reply_buffer.appendCsi(.terminal, payload);
    }

    /// Sets nonzero cell pixels on both screens; zero dimensions are rejected unchanged.
    pub fn setCellPixelSize(
        self: *Terminal,
        width: u32,
        height: u32,
    ) CellPixelSizeError!void {
        if (width == 0 or height == 0) return error.InvalidDimensions;
        const previous = self.screen_state.primary.cellPixelSize();
        if (previous) |cell| {
            if (cell.width == width and cell.height == height) return;
        }

        self.screen_state.setCellPixelSize(width, height);
    }

    /// Returns configured nonzero cell pixels for protocol reports, when known.
    pub fn cellPixelSize(self: *const Terminal) ?CellPixelSize {
        const value = self.screen_state.activeConst().cellPixelSize() orelse return null;
        return .{ .width = value.width, .height = value.height };
    }

    /// Appends one Kitty color-preference notification when mode 2031 is enabled.
    ///
    /// Disabled mode returns false without mutation. Allocation or output-bound
    /// failure preserves pending output and the enabled mode.
    pub fn reportColorSchemePreference(
        self: *Terminal,
        preference: ColorSchemePreference,
    ) ApplyError!bool {
        if (!self.modes.color_preference_notifications) return false;
        try self.reply_buffer.appendCsi(
            .kitty,
            if (preference == .dark) "?997;1n" else "?997;2n",
        );
        advanceIdentity(&self.semantic_sequence);
        return true;
    }

    /// Reply to and consume the matching FIFO-head color-preference query transactionally.
    pub fn replyColorPreference(
        self: *Terminal,
        generation: u64,
        preference: ColorSchemePreference,
    ) ColorPreferenceReplyError!void {
        const consequence = self.consequenceHead() orelse return error.StaleColorPreferenceQuery;
        if (consequence.id() != generation or
            std.meta.activeTag(consequence) != .color_preference_query)
            return error.StaleColorPreferenceQuery;
        try self.reply_buffer.appendCsi(
            .kitty,
            if (preference == .dark) "?997;1n" else "?997;2n",
        );
        self.consequences.consumeHead(generation) catch return error.StaleColorPreferenceQuery;
        advanceIdentity(&self.semantic_sequence);
    }

    /// Applies RIS while preserving dimensions and owned allocations.
    pub fn hardReset(self: *Terminal) void {
        self.screen_state.reset();
        self.screen_state.primary.insert_mode = false;
        self.screen_state.alternate.insert_mode = false;
        self.modes = .{};
        self.saved_all_modes = .{};
        self.primary_savepoint.clear();
        self.alternate_savepoint.clear();
        self.charset = .{};
        self.stream_state.parser.resetTextEncoding();
        self.reply_buffer.resetFraming();
        self.kitty.resetTerminalState();
        self.locator = .{};
        self.consequences.resetTerminal();
        self.properties.resetTerminal();
        const graphics_changed = self.graphics.reset();
        std.debug.assert(!graphics_changed or self.graphics.generation() != 0);
    }

    // Applies DECSTR to active-bank state and terminal-global modes without erasing text or moving the cursor.
    fn softReset(self: *Terminal) bool {
        const active = self.screen_state.active();
        var changed = active.softReset();

        changed = replaceBool(&self.screen_state.primary.insert_mode, false) or changed;
        changed = replaceBool(&self.screen_state.alternate.insert_mode, false) or changed;
        changed = self.screen_state.primary.setLeftRightMarginMode(false) or changed;
        changed = self.screen_state.alternate.setLeftRightMarginMode(false) or changed;
        changed = replaceBool(&self.screen_state.primary.cursor.visible, true) or changed;
        changed = replaceBool(&self.screen_state.alternate.cursor.visible, true) or changed;

        changed = replaceBool(&self.modes.application_cursor_keys, false) or changed;
        changed = replaceBool(&self.modes.application_keypad, false) or changed;
        changed = replaceBool(&self.modes.column_mode_132, false) or changed;
        changed = replaceBool(&self.modes.preserve_screen_on_column_mode, false) or changed;
        changed = replaceBool(&self.modes.more_fix, false) or changed;
        changed = replaceBool(&self.modes.newline_mode, false) or changed;
        changed = replaceBool(&self.modes.focus_reporting, false) or changed;
        changed = replaceBool(&self.modes.bracketed_paste, false) or changed;
        changed = replaceBool(&self.modes.inband_resize_notifications, false) or changed;
        changed = replaceBool(&self.modes.reverse_wraparound_mode, false) or changed;
        changed = replaceBool(&self.modes.extended_reverse_wraparound_mode, false) or changed;
        changed = replaceBool(&self.modes.sixel_display_mode, false) or changed;
        if (self.modes.mouse_tracking != .off) changed = true;
        self.modes.mouse_tracking = .off;
        if (self.modes.mouse_protocol != .none) changed = true;
        self.modes.mouse_protocol = .none;
        changed = self.reply_buffer.setEightBitControls(false) or changed;
        changed = self.charset.reset() or changed;
        return changed;
    }

    // Restores Kitty's configured cursor appearance without changing cursor position.
    fn restoreCursorAppearance(self: *Terminal) bool {
        const active = &self.screen_state.active().cursor;
        const active_before = active.*;
        active.restoreDefaultStyle();

        var changed = !std.meta.eql(active_before, active.*);
        changed = replaceBool(&self.screen_state.primary.cursor.visible, true) or changed;
        changed = replaceBool(&self.screen_state.alternate.cursor.visible, true) or changed;
        if (self.screen_state.primary.cursor.cursor_color != null or
            self.screen_state.alternate.cursor.cursor_color != null or self.properties.colors.cursor != null) changed = true;
        self.screen_state.primary.cursor.cursor_color = null;
        self.screen_state.alternate.cursor.cursor_color = null;
        self.properties.colors.cursor = null;
        return changed;
    }

    // Pushes selected active rendition attributes onto the fixed iTerm2-compatible stack.
    fn pushSgr(self: *Terminal, params: ModeParams) bool {
        if (self.sgr_stack_len == sgr_stack_capacity) return false;
        self.sgr_stack[self.sgr_stack_len] = .{
            .attrs = self.screen_state.activeConst().current_attrs,
            .selection = sgrSelection(params),
        };
        self.sgr_stack_len += 1;
        return true;
    }

    // Pops one snapshot and restores only the attributes selected by its push.
    fn popSgr(self: *Terminal) bool {
        if (self.sgr_stack_len == 0) return false;
        self.sgr_stack_len -= 1;
        const entry = self.sgr_stack[self.sgr_stack_len];
        restoreSelectedSgr(&self.screen_state.active().current_attrs, entry);
        return true;
    }

    // Restores the iTerm2-owned DECCIR subset after complete payload validation.
    fn restoreCursorInformation(self: *Terminal, payload: []const u8) bool {
        const info = parseCursorInformation(payload) orelse return false;
        const active = self.screen_state.active();
        const cursor_before = active.cursor;
        const attrs_before = active.current_attrs;
        const wrap_before = active.wrap_pending;
        const origin_before = active.origin_mode;

        const row = @min(info.row, active.rows - 1);
        const col = @min(info.col, active.lineRightBoundary(row));
        active.cursor.setPositionByClient(row, col);
        active.current_attrs.reverse = info.reverse;
        active.current_attrs.blink = info.blink;
        active.current_attrs.underline = info.underline;
        active.current_attrs.bold = info.bold;
        active.wrap_pending = info.wrap_pending and active.auto_wrap and col == active.lineRightBoundary(row);
        active.origin_mode = info.origin_mode;
        const designation_changed = self.charset.configureCharset(0, info.g0_designation);

        return !std.meta.eql(cursor_before, active.cursor) or
            !std.meta.eql(attrs_before, active.current_attrs) or
            wrap_before != active.wrap_pending or origin_before != active.origin_mode or
            designation_changed;
    }

    // Replaces the active screen's bounded tab-stop set from one-based DECTABSR values.
    fn restoreTabStops(self: *Terminal, payload: []const u8) bool {
        const stops = self.screen_state.active().tab_stops orelse return false;
        var restored: [parser_mod.max_metadata_control_bytes / 2 + 1]u16 = undefined;
        var restored_count: usize = 0;
        var values = std.mem.splitScalar(u8, payload, '/');
        while (values.next()) |field| {
            // iTerm2 filters invalid members independently instead of rejecting the complete stop set.
            const one_based = std.fmt.parseInt(u32, field, 10) catch continue;
            if (one_based == 0 or one_based > stops.len) continue;
            std.debug.assert(restored_count < restored.len);
            restored[restored_count] = @intCast(one_based - 1);
            restored_count += 1;
        }
        std.sort.block(u16, restored[0..restored_count], {}, std.sort.asc(u16));

        var changed = false;
        var restored_index: usize = 0;
        for (stops, 0..) |*stop, col| {
            const column: u16 = @intCast(col);
            while (restored_index < restored_count and restored[restored_index] < column)
                restored_index += 1;
            const next = restored_index < restored_count and restored[restored_index] == column;
            changed = stop.* != next or changed;
            stop.* = next;
        }
        return changed;
    }

    /// Saves cursor presentation, rendition, charset, origin, and wrap state into the active screen slot.
    ///
    /// The result reports whether the bank-local savepoint changed.
    fn saveCursor(self: *Terminal) bool {
        const next = self.captureSavepoint();
        const savepoint = self.activeSavepoint();
        if (std.meta.eql(savepoint.*, next)) return false;
        savepoint.* = next;
        return true;
    }

    fn captureSavepoint(self: *const Terminal) Savepoint {
        const active = self.screen_state.activeConst();
        return .{
            .valid = true,
            .cursor = .{
                .row = active.cursor.row,
                .col = active.cursor.col,
                .style = active.cursor.effectiveStyle(),
                .visible = active.cursor.visible,
            },
            .current_attrs = active.current_attrs,
            .reverse_screen_mode = self.modes.reverse_screen_mode,
            .origin_mode = active.origin_mode,
            .auto_wrap = active.auto_wrap,
            .wrap_pending = active.wrap_pending,
            .gl_index = self.charset.gl_index,
            .gr_index = self.charset.gr_index,
            .designations = self.charset.designations,
        };
    }

    /// Restores the active bank savepoint and reports exact retained-state mutation.
    ///
    /// Position is clamped to current dimensions and a saved pending wrap survives
    /// only when the restored position remains at the active right boundary.
    fn restoreCursor(self: *Terminal) bool {
        const active = self.screen_state.active();
        const cursor_before = active.cursor;
        const visibility_before = .{
            self.screen_state.primary.cursor.visible,
            self.screen_state.alternate.cursor.visible,
        };
        const attrs_before = active.current_attrs;
        const wrap_pending_before = active.wrap_pending;
        const auto_wrap_before = active.auto_wrap;
        const origin_before = active.origin_mode;
        const reverse_before = self.modes.reverse_screen_mode;
        const charset_before = self.charset;

        self.restoreCursorState();
        const changed = !std.meta.eql(cursor_before, active.cursor) or
            !std.meta.eql(visibility_before, .{
                self.screen_state.primary.cursor.visible,
                self.screen_state.alternate.cursor.visible,
            }) or
            !std.meta.eql(attrs_before, active.current_attrs) or
            wrap_pending_before != active.wrap_pending or
            auto_wrap_before != active.auto_wrap or
            origin_before != active.origin_mode or
            reverse_before != self.modes.reverse_screen_mode or
            !std.meta.eql(charset_before, self.charset);

        return changed;
    }

    fn restoreCursorState(self: *Terminal) void {
        const active = self.screen_state.active();
        const savepoint = self.activeSavepointConst();
        active.wrap_pending = false;
        if (!savepoint.valid) {
            active.cursor.setPositionStructural(0, 0);
            self.modes.reverse_screen_mode = false;
            active.origin_mode = false;
            self.charset = .{};
            return;
        }

        self.modes.reverse_screen_mode = savepoint.reverse_screen_mode;
        active.origin_mode = savepoint.origin_mode;
        active.auto_wrap = savepoint.auto_wrap;
        active.current_attrs = savepoint.current_attrs;
        active.cursor.restoreSavedStyle(savepoint.cursor.style);
        self.screen_state.primary.cursor.visible = savepoint.cursor.visible;
        self.screen_state.alternate.cursor.visible = savepoint.cursor.visible;
        restoreCursorPosition(active, savepoint.cursor.row, savepoint.cursor.col);
        active.wrap_pending = savepoint.wrap_pending and active.cursor.col == active.rightBoundary();
        self.charset.gl_index = savepoint.gl_index;
        self.charset.gr_index = savepoint.gr_index;
        self.charset.single_shift = null;
        self.charset.designations = savepoint.designations;
    }

    /// Switches primary or alternate screen with explicit clear and cursor-save behavior.
    fn switchScreenMode(self: *Terminal, enable_alt: bool, clear_alt: bool, save_restore_cursor: bool) bool {
        if (enable_alt) {
            if (self.screen_state.alt_active) return false;
            if (save_restore_cursor) self.activeSavepoint().* = self.captureSavepoint();
            self.screen_state.alt_active = true;
            if (clear_alt) {
                self.screen_state.alternate.clearVisibleCells();
                const graphics_changed = self.graphics.clearBank(.alternate);
                std.debug.assert(!graphics_changed or self.graphics.generation() != 0);
            }
            self.screen_state.alternate.resetCursorForAltEntry();
            return true;
        }

        if (!self.screen_state.alt_active) return false;
        self.screen_state.alt_active = false;
        if (save_restore_cursor) self.restoreCursorState();
        return true;
    }

    /// Apply one canonical semantic mode event.
    fn applyModeEvent(self: *Terminal, event: SemanticEvent) bool {
        const changed = self.applyModeEventInner(event);

        return changed;
    }

    fn applyModeEventInner(self: *Terminal, event: SemanticEvent) bool {
        switch (event) {
            .application_cursor_keys => |enabled| return replaceBool(&self.modes.application_cursor_keys, enabled),
            .application_keypad => |enabled| return replaceBool(&self.modes.application_keypad, enabled),
            .column_mode_132 => |enabled| return self.setDecMode(3, enabled),
            .allow_column_mode => |enabled| return self.setDecMode(40, enabled),
            .preserve_screen_on_column_mode => |enabled| return self.setDecMode(95, enabled),
            .more_fix => |enabled| return self.setDecMode(41, enabled),
            .auto_repeat => |enabled| return self.setDecMode(8, enabled),
            .reverse_screen_mode => |enabled| return self.setDecMode(5, enabled),
            .eight_bit_controls => |enabled| {
                const changed = self.reply_buffer.setEightBitControls(enabled);
                return changed;
            },
            .left_right_margin_mode => |enabled| return self.setDecMode(69, enabled),
            .cursor_visible => |enabled| return self.setDecMode(25, enabled),
            .cursor_blink => |enabled| return self.setDecMode(12, enabled),
            .ansi_mode_set => |modes| return self.setAnsiModes(modes.params[0..modes.param_count], true),
            .ansi_mode_reset => |modes| return self.setAnsiModes(modes.params[0..modes.param_count], false),
            .modify_other_keys_set => |value| {
                if (self.modes.modify_other_keys == value) return false;
                self.modes.modify_other_keys = value;
                return true;
            },
            .modify_other_keys_disable => {
                if (self.modes.modify_other_keys == -1) return false;
                self.modes.modify_other_keys = -1;
                return true;
            },
            .key_format_change => |change| {
                if (change.resource) |resource| {
                    if (!isKeyFormatResource(resource)) return false;
                    const value = change.value orelse 0;
                    if (self.modes.key_format[resource] == value) return false;
                    self.modes.key_format[resource] = value;
                    return true;
                } else {
                    const empty = @as([8]u16, @splat(0));
                    if (std.mem.eql(u16, self.modes.key_format[0..], empty[0..])) return false;
                    self.modes.key_format = @as([8]u16, @splat(0));
                    return true;
                }
            },
            .pointer_mode => |value| {
                if (self.modes.pointer_mode == value) return false;
                self.modes.pointer_mode = value;
                return true;
            },
            .reverse_wraparound_mode => |enabled| return self.setDecMode(45, enabled),
            .extended_reverse_wraparound_mode => |enabled| {
                return self.setDecMode(1045, enabled);
            },
            .alternate_scroll => |enabled| return self.setDecMode(1007, enabled),
            .meta_sends_escape => |enabled| return self.setDecMode(1036, enabled),
            .report_key_up => |enabled| return self.setDecMode(1337, enabled),
            .bracketed_paste => |enabled| return replaceBool(&self.modes.bracketed_paste, enabled),
            .synchronized_output => |enabled| return replaceBool(&self.modes.synchronized_output, enabled),
            .inband_resize_notifications => |enabled| return self.setDecMode(2048, enabled),
            .color_preference_notifications => |enabled| return self.setDecMode(2031, enabled),
            .paste_events => |enabled| return self.setDecMode(5522, enabled),
            .termios_signals => |enabled| return self.setDecMode(19997, enabled),
            .dec_mode_set => |modes| return self.setDecModes(modes.params[0..modes.param_count], true),
            .dec_mode_reset => |modes| return self.setDecModes(modes.params[0..modes.param_count], false),
            .dec_mode_save => |modes| return self.saveDecModes(modes.params[0..modes.param_count]),
            .dec_mode_restore => |modes| return self.restoreDecModes(modes.params[0..modes.param_count]),
            else => unreachable,
        }
    }

    fn decModeState(self: *const Terminal, mode_number: u16) u8 {
        const active = self.screen_state.activeConst();
        return decModeStateForView(.{
            .application_cursor_keys = self.modes.application_cursor_keys,
            .application_keypad = self.modes.application_keypad,
            .column_mode_132 = self.modes.column_mode_132,
            .allow_column_mode = self.modes.allow_column_mode,
            .preserve_screen_on_column_mode = self.modes.preserve_screen_on_column_mode,
            .more_fix = self.modes.more_fix,
            .auto_repeat = self.modes.auto_repeat,
            .reverse_screen_mode = self.modes.reverse_screen_mode,
            .origin_mode = active.origin_mode,
            .auto_wrap = active.auto_wrap,
            .left_right_margin_mode = active.left_right_margin_mode,
            .cursor_blink = active.cursor.blink_intent,
            .cursor_visible = active.cursor.visible,
            .alt_active = self.screen_state.alt_active,
            .mouse_tracking = self.modes.mouse_tracking,
            .mouse_protocol = self.modes.mouse_protocol,
            .focus_reporting = self.modes.focus_reporting,
            .alternate_scroll = self.modes.alternate_scroll,
            .meta_sends_escape = self.modes.meta_sends_escape,
            .report_key_up = self.modes.report_key_up,
            .bracketed_paste = self.modes.bracketed_paste,
            .synchronized_output = self.modes.synchronized_output,
            .inband_resize_notifications = self.modes.inband_resize_notifications,
            .color_preference_notifications = self.modes.color_preference_notifications,
            .paste_events = self.modes.paste_events,
            .reverse_wraparound = self.modes.reverse_wraparound_mode,
            .extended_reverse_wraparound = self.modes.extended_reverse_wraparound_mode,
            .sixel_display_mode = self.modes.sixel_display_mode,
        }, mode_number);
    }

    fn setDecModes(self: *Terminal, mode_numbers: []const u16, enabled: bool) bool {
        var changed = false;
        for (mode_numbers) |mode_number| changed = self.setDecMode(mode_number, enabled) or changed;
        return changed;
    }

    fn saveDecModes(self: *Terminal, mode_numbers: []const u16) bool {
        if (mode_numbers.len == 0) return self.saveAllModes();
        var changed = false;
        for (mode_numbers) |mode_number| {
            const index = modes_mod.savedDecModeIndex(mode_number) orelse continue;
            const state = self.decModeState(mode_number);
            if (self.modes.saved_dec_modes[index] == state) continue;
            self.modes.saved_dec_modes[index] = state;
            changed = true;
        }
        return changed;
    }

    fn restoreDecModes(self: *Terminal, mode_numbers: []const u16) bool {
        if (mode_numbers.len == 0) return self.restoreAllModes();
        var changed = false;
        for (mode_numbers) |mode_number| {
            const index = modes_mod.savedDecModeIndex(mode_number) orelse continue;
            const state = self.modes.saved_dec_modes[index];
            switch (state) {
                1 => changed = self.setDecMode(mode_number, true) or changed,
                2 => changed = self.setDecMode(mode_number, false) or changed,
                else => {},
            }
        }
        return changed;
    }

    fn saveAllModes(self: *Terminal) bool {
        const active = self.screen_state.activeConst();
        const saved: SavedAllModes = .{
            .newline_mode = self.modes.newline_mode,
            .insert_mode = active.insert_mode,
            .auto_repeat = self.modes.auto_repeat,
            .bracketed_paste = self.modes.bracketed_paste,
            .focus_reporting = self.modes.focus_reporting,
            .color_preference_notifications = self.modes.color_preference_notifications,
            .paste_events = self.modes.paste_events,
            .inband_resize_notifications = self.modes.inband_resize_notifications,
            .application_cursor_keys = self.modes.application_cursor_keys,
            .cursor_visible = active.cursor.visible,
            .auto_wrap = active.auto_wrap,
            .mouse_tracking = self.modes.mouse_tracking,
            .mouse_protocol = self.modes.mouse_protocol,
            .reverse_screen_mode = self.modes.reverse_screen_mode,
        };
        if (std.meta.eql(self.saved_all_modes, saved)) return false;
        self.saved_all_modes = saved;
        return true;
    }

    fn restoreAllModes(self: *Terminal) bool {
        const saved = self.saved_all_modes;
        var changed = self.setAnsiModes(&.{20}, saved.newline_mode);
        changed = self.setAnsiModes(&.{4}, saved.insert_mode) or changed;
        changed = self.setDecMode(8, saved.auto_repeat) or changed;
        changed = self.setDecMode(2004, saved.bracketed_paste) or changed;
        changed = self.setDecMode(1004, saved.focus_reporting) or changed;
        changed = self.setDecMode(2031, saved.color_preference_notifications) or changed;
        changed = self.setDecMode(5522, saved.paste_events) or changed;
        changed = self.setDecMode(2048, saved.inband_resize_notifications) or changed;
        changed = self.setDecMode(1, saved.application_cursor_keys) or changed;
        changed = self.setDecMode(25, saved.cursor_visible) or changed;
        changed = self.setDecMode(7, saved.auto_wrap) or changed;
        changed = self.setMouseTracking(saved.mouse_tracking) or changed;
        changed = self.setMouseProtocol(saved.mouse_protocol) or changed;
        changed = self.setDecMode(5, saved.reverse_screen_mode) or changed;
        return changed;
    }

    fn setDecMode(self: *Terminal, mode_number: u16, enabled: bool) bool {
        const active = self.screen_state.active();
        const mode_changed = switch (mode_number) {
            // Recognized unsupported modes leave even pending-wrap state untouched.
            2, 4, 20, 42 => return false,
            1 => replaceBool(&self.modes.application_cursor_keys, enabled),
            3 => result: {
                if (!self.modes.allow_column_mode) return false;
                const changed = replaceBool(&self.modes.column_mode_132, enabled);
                // A repeated selection is not a new transition; DECNCSM preserves changed transitions.
                if (!changed or self.modes.preserve_screen_on_column_mode) break :result changed;
                var screen_changed = active.eraseDisplay(.all, false);
                const cursor_before = active.cursor;
                active.cursor.setPositionByClient(
                    if (active.origin_mode) active.scroll_top else 0,
                    0,
                );
                screen_changed = !std.meta.eql(cursor_before, active.cursor) or screen_changed;
                break :result screen_changed or changed;
            },
            40 => replaceBool(&self.modes.allow_column_mode, enabled),
            41 => replaceBool(&self.modes.more_fix, enabled),
            95 => replaceBool(&self.modes.preserve_screen_on_column_mode, enabled),
            5 => replaceBool(&self.modes.reverse_screen_mode, enabled),
            6 => changed: {
                const before = .{ active.origin_mode, active.cursor.row, active.cursor.col };
                active.applyScreen(.{ .origin_mode = enabled });
                break :changed !std.meta.eql(before, .{ active.origin_mode, active.cursor.row, active.cursor.col });
            },
            7 => changed: {
                const before = active.auto_wrap;
                active.applyScreen(.{ .auto_wrap = enabled });
                break :changed before != active.auto_wrap;
            },
            8 => replaceBool(&self.modes.auto_repeat, enabled),
            12 => active.cursor.setBlink(enabled),
            69 => result: {
                const inactive = if (self.screen_state.alt_active)
                    &self.screen_state.primary
                else
                    &self.screen_state.alternate;
                var changed = active.setLeftRightMarginMode(enabled);
                changed = replaceBool(&inactive.left_right_margin_mode, enabled) or changed;
                if (!enabled) {
                    changed = inactive.left_margin != 0 or
                        inactive.right_margin != inactive.cols -| 1 or changed;
                    inactive.left_margin = 0;
                    inactive.right_margin = inactive.cols -| 1;
                }
                break :result changed;
            },
            80 => replaceBool(&self.modes.sixel_display_mode, enabled),
            25 => result: {
                var changed = replaceBool(&self.screen_state.primary.cursor.visible, enabled);
                changed = replaceBool(&self.screen_state.alternate.cursor.visible, enabled) or changed;
                break :result changed;
            },
            45 => replaceBool(&self.modes.reverse_wraparound_mode, enabled),
            66 => replaceBool(&self.modes.application_keypad, enabled),
            47 => self.switchScreenMode(enabled, false, false),
            1047 => self.switchScreenMode(enabled, false, false),
            1048 => if (enabled) self.saveCursor() else self.restoreCursor(),
            1049 => self.switchScreenMode(enabled, true, true),
            1045 => replaceBool(&self.modes.extended_reverse_wraparound_mode, enabled),
            9 => self.setMouseTracking(if (enabled) .x10 else .off),
            1000 => self.setMouseTracking(if (enabled) .normal else .off),
            1002 => self.setMouseTracking(if (enabled) .button_event else .off),
            1003 => self.setMouseTracking(if (enabled) .any_event else .off),
            1004 => replaceBool(&self.modes.focus_reporting, enabled),
            1005 => self.setMouseProtocol(if (enabled) .utf8 else .none),
            1006 => self.setMouseProtocol(if (enabled) .sgr else .none),
            1007 => replaceBool(&self.modes.alternate_scroll, enabled),
            1015 => self.setMouseProtocol(if (enabled) .urxvt else .none),
            1016 => self.setMouseProtocol(if (enabled) .sgr_pixel else .none),
            1036 => replaceBool(&self.modes.meta_sends_escape, enabled),
            1337 => replaceBool(&self.modes.report_key_up, enabled),
            2004 => replaceBool(&self.modes.bracketed_paste, enabled),
            2026 => replaceBool(&self.modes.synchronized_output, enabled),
            2048 => replaceBool(&self.modes.inband_resize_notifications, enabled),
            2031 => replaceBool(&self.modes.color_preference_notifications, enabled),
            5522 => replaceBool(&self.modes.paste_events, enabled),
            19997 => replaceBool(&self.modes.termios_signals, enabled),
            else => return false,
        };
        return active.cancelPendingWrap() or mode_changed;
    }

    fn setAnsiModes(self: *Terminal, mode_numbers: []const u16, enabled: bool) bool {
        var changed = false;
        for (mode_numbers) |mode_number| switch (mode_number) {
            2 => changed = replaceBool(&self.modes.keyboard_action_mode, enabled) or changed,
            4 => {
                changed = replaceBool(&self.screen_state.primary.insert_mode, enabled) or changed;
                changed = replaceBool(&self.screen_state.alternate.insert_mode, enabled) or changed;
            },
            12 => changed = replaceBool(&self.modes.send_receive_mode, enabled) or changed,
            20 => changed = replaceBool(&self.modes.newline_mode, enabled) or changed,
            else => {},
        };
        return changed;
    }

    fn setMouseTracking(self: *Terminal, value: input.MouseTrackingMode) bool {
        const pending_changed = self.screen_state.active().cancelPendingWrap();
        if (self.modes.mouse_tracking == value) return pending_changed;
        self.modes.mouse_tracking = value;
        return true;
    }

    fn setMouseProtocol(self: *Terminal, value: input.MouseProtocol) bool {
        if (self.modes.mouse_protocol == value) return false;
        self.modes.mouse_protocol = value;
        return true;
    }

    /// Reports whether an enabled terminal mouse-tracking mode owns pointer input.
    pub fn mouseReportingEnabled(self: *const Terminal) bool {
        return self.modes.mouse_tracking != .off;
    }

    // Clears active display, history, and cursor as one exact terminal mutation.
    fn clearBuffer(self: *Terminal) bool {
        const active = self.screen_state.active();
        var changed = active.eraseDisplay(.all, false);
        changed = active.clearScrollback() or changed;
        const cursor_before = active.cursor;
        active.cursor.setPositionByClient(0, 0);
        changed = !std.meta.eql(cursor_before, active.cursor) or changed;
        return changed;
    }

    /// Reports whether mode 19997 requests foreground termios handling for typed one-byte keys.
    pub fn termiosSignals(self: *const Terminal) bool {
        return self.modes.termios_signals;
    }

    /// Reports whether mode 5522 requests the operator-triggered MIME paste exchange.
    pub fn pasteEvents(self: *const Terminal) bool {
        return self.modes.paste_events;
    }

    /// Reports whether mode 1007 translates alternate-screen wheel input.
    pub fn alternateScroll(self: *const Terminal) bool {
        return self.modes.alternate_scroll;
    }

    /// Reports whether mode 1036 prefixes Meta-modified legacy input with Escape.
    pub fn metaSendsEscape(self: *const Terminal) bool {
        return self.modes.meta_sends_escape;
    }

    /// Reports whether mode 1337 requests key-release input.
    pub fn reportKeyUp(self: *const Terminal) bool {
        return self.modes.report_key_up;
    }

    /// Copies the process-lifetime semantic mutation identity.
    ///
    /// The nonzero sequence advances for accepted terminal state or consequence
    /// mutation and remains stable for rejected, ignored, or repeated no-ops.
    /// It does not identify external observation or scheduling.
    pub fn semanticSequence(self: *const Terminal) u64 {
        return self.semantic_sequence;
    }

    /// Advances retained image animation against caller monotonic milliseconds.
    pub fn advanceGraphics(self: *Terminal, now_ms: u64) graphics_mod.AnimationTick {
        const tick = self.graphics.advanceAnimations(now_ms);
        if (tick.semantic_changed) self.postApply(true);
        return tick;
    }

    /// Borrows terminal cells and cursor facts at one caller-selected history offset.
    ///
    /// The offset is clamped to retained primary history. VT retains no
    /// viewport, follow, or scrolling intent.
    pub fn semanticView(self: *const Terminal, history_offset: u32) SemanticView {
        return visibleView(&self.screen_state, history_offset);
    }

    /// Copies terminal colors and reverse-screen state.
    pub fn presentation(self: *const Terminal) Presentation {
        const active = self.screen_state.activeConst();
        const colors = self.properties.colors;
        return .{
            .palette = colors.palette,
            .foreground = colors.foreground,
            .background = colors.background,
            .cursor = active.cursor.cursor_color orelse colors.cursor,
            .cursor_text = active.cursor.cursor_text_color orelse colors.cursor_text,
            .selection_background = colors.selection_background,
            .selection_foreground = colors.selection_foreground,
            .reverse_screen = self.modes.reverse_screen_mode,
        };
    }

    /// Borrows decoded images and placements at one caller-selected history offset.
    pub fn images(self: *const Terminal, history_offset: u32) Images {
        const view = visibleView(&self.screen_state, history_offset);
        return .{
            .plane = &self.graphics,
            .bank = if (view.is_alternate_screen) .alternate else .primary,
            .visible_row_start = if (view.is_alternate_screen)
                view.start
            else
                @as(u64, view.history_row_base) + view.start,
            .rows = view.rows,
            .generation = self.graphics.generation(),
            .content_generation = self.graphics.imageGeneration(),
        };
    }

    /// Reports whether synchronized-output mode is enabled.
    pub fn synchronizedOutput(self: *const Terminal) bool {
        return self.modes.synchronized_output;
    }

    /// Borrows the current OSC window title until terminal mutation.
    pub fn title(self: *const Terminal) ?[]const u8 {
        return self.properties.current_title;
    }

    /// Borrows the current OSC icon title until terminal mutation.
    pub fn icon(self: *const Terminal) ?[]const u8 {
        return self.properties.current_icon;
    }

    /// Borrows the latest child-reported working directory.
    pub fn workingDirectory(self: *const Terminal) ?WorkingDirectory {
        return self.properties.working_directory;
    }

    /// Borrows the latest child-reported remote host.
    pub fn remoteHost(self: *const Terminal) ?[]const u8 {
        return self.properties.remote_host;
    }

    /// Borrows the latest shell-integration identity.
    pub fn shellIntegration(self: *const Terminal) ?Terminal.ShellIntegration {
        const integration = self.properties.shell_integration orelse return null;
        return .{ .version = integration.version, .shell = integration.shell };
    }

    /// Copies the latest shell-mark semantic state.
    pub fn shellMark(self: *const Terminal) ShellMark {
        return self.properties.shell_mark;
    }

    /// Borrows the oldest retained consequence across every protocol family.
    pub fn consequenceHead(self: *const Terminal) ?Consequence {
        const head = self.consequences.head() orelse return null;
        return switch (head) {
            .clipboard => |value| .{ .clipboard = value },
            .notification => |value| .{ .notification = value },
            .pointer_shape => |value| .{ .pointer_shape = value },
            .file_transfer => |value| .{ .file_transfer = value },
            .drag_drop => |value| .{ .drag_drop = value },
            .window => |value| .{ .window = value },
            .color_preference => |id| .{ .color_preference_query = .{ .id = id } },
            .media_copy => |value| .{ .media_copy = value },
            .bell => |id| .{ .bell = .{ .id = id } },
            .legacy_control => |value| .{ .legacy_control = value },
            .dcs => |value| .{ .dcs = value },
            .string => |value| .{ .string_control = value },
        };
    }

    /// Returns the total bounded consequence count across every protocol family.
    pub fn consequenceCount(self: *const Terminal) u16 {
        return self.consequences.count();
    }

    /// Consumes the exact global head after external policy handles it.
    ///
    /// Clipboard and window queries remain retained until their typed reply
    /// operation serializes protocol-mandated bytes.
    pub fn consumeConsequence(
        self: *Terminal,
        id: u64,
    ) ConsumeConsequenceError!void {
        const head = self.consequenceHead() orelse return error.StaleConsequence;
        if (head.id() != id) return error.StaleConsequence;
        switch (head) {
            .clipboard => |value| {
                if (value.kind == .query) return error.ReplyRequired;
            },
            .notification, .pointer_shape, .file_transfer, .drag_drop => {},
            .window => |value| {
                if (isWindowQuery(value.request)) return error.ReplyRequired;
            },
            .color_preference_query => return error.ReplyRequired,
            .bell, .legacy_control, .media_copy, .dcs, .string_control => {},
        }
        self.consequences.consumeHead(id) catch return error.StaleConsequence;
        advanceIdentity(&self.semantic_sequence);
    }

    /// Returns the number of primary-history rows lost to bounded allocation failure.
    pub fn historyLossCount(self: *const Terminal) u64 {
        return self.screen_state.primary.history_loss_generation;
    }

    /// Returns the terminal reset identity governing pointer-shape stacks.
    pub fn pointerShapeResetSequence(self: *const Terminal) u64 {
        return self.consequences.pointer_shape_reset_generation;
    }

    /// Reports whether mode 2031 requests color-preference notifications.
    pub fn colorPreferenceNotifications(self: *const Terminal) bool {
        return self.modes.color_preference_notifications;
    }

    /// Copies finalized primary logical lines after `cursor` and one observation-scoped open line.
    pub fn copyLogicalOutput(
        self: *Terminal,
        allocator: std.mem.Allocator,
        cursor: u64,
        max_lines: u16,
        max_bytes: usize,
    ) LogicalOutputError!LogicalOutputResult {
        if (max_lines == 0 or max_bytes == 0 or max_bytes > Screen.retained_output_bytes_max) {
            return error.InvalidLimit;
        }
        const primary = &self.screen_state.primary;
        const count = primary.output_lines_count;
        const newest = primary.next_output_id - 1;
        const oldest = if (count == 0)
            primary.next_output_id
        else
            primary.output_lines.items[@intCast(primary.output_lines_start)].?.id;
        if (cursor > newest) return .{ .cursor_ahead = newest };
        if (oldest > 1 and cursor < oldest - 1) return .{ .cursor_stale = oldest };

        var text = std.ArrayList(u8).empty;
        errdefer text.deinit(allocator);
        var losses = std.ArrayList(LogicalOutputLoss).empty;
        errdefer losses.deinit(allocator);
        var entry_count: u16 = 0;
        var line_count: u16 = 0;
        var output_cursor = cursor;
        var more = false;
        var logical_index: u16 = 0;
        while (logical_index < count) : (logical_index += 1) {
            const slot = (primary.output_lines_start + @as(u32, @intCast(logical_index))) %
                @as(u32, @intCast(primary.output_lines.items.len));
            const line = primary.output_lines.items[@intCast(slot)].?;
            if (line.id <= cursor) continue;
            if (entry_count == max_lines) {
                more = true;
                break;
            }
            switch (line.value) {
                .loss => |loss| {
                    try losses.append(allocator, .{
                        .id = line.id,
                        .byte_count = loss.byte_count,
                        .reason = loss.reason,
                    });
                },
                .text => |line_text| {
                    const separator: usize = if (line_count == 0) 0 else 1;
                    const remaining = max_bytes - text.items.len;
                    if (separator > remaining or line_text.len > remaining - separator) {
                        if (entry_count == 0) return .{ .line_too_long = line.id };
                        more = true;
                        break;
                    }
                    if (separator != 0) try text.append(allocator, '\n');
                    try text.appendSlice(allocator, line_text);
                    line_count += 1;
                },
            }
            if (more) break;
            entry_count += 1;
            output_cursor = line.id;
        }
        var open_line_omitted = false;
        const open_line = copyOpenOutputLine(
            allocator,
            primary,
            max_bytes - text.items.len,
        ) catch |failure| switch (failure) {
            error.LineTooLong => if (entry_count == 0)
                return .open_line_too_long
            else blk: {
                open_line_omitted = true;
                break :blk try allocator.dupe(u8, "");
            },
            error.OutOfMemory => return error.OutOfMemory,
        };
        errdefer allocator.free(open_line);
        const owned_text = try text.toOwnedSlice(allocator);
        errdefer allocator.free(owned_text);
        const owned_losses = try losses.toOwnedSlice(allocator);
        errdefer allocator.free(owned_losses);
        const semantic_sequence = self.semantic_sequence;
        return .{ .output = .{
            .allocator = allocator,
            .text = owned_text,
            .open_line = open_line,
            .open_line_omitted = open_line_omitted,
            .losses = owned_losses,
            .oldest = oldest,
            .cursor = output_cursor,
            .newest = newest,
            .line_count = line_count,
            .more = more,
            .semantic_sequence = semantic_sequence,
        } };
    }

    /// Returns the current finalized primary-output retention bounds.
    pub fn logicalOutputRange(self: *const Terminal) LogicalOutputRange {
        const primary = &self.screen_state.primary;
        const count = primary.output_lines_count;
        return .{
            .oldest = if (count == 0)
                primary.next_output_id
            else
                primary.output_lines.items[@intCast(primary.output_lines_start)].?.id,
            .newest = primary.next_output_id - 1,
        };
    }

    /// Borrows the URI interned for one nonzero cell hyperlink identity.
    pub fn hyperlinkUri(self: *const Terminal, link_id: u32) ?[]const u8 {
        return self.properties.hyperlinkUriForId(link_id);
    }

    /// Copies one caller-supplied semantic cell range as UTF-8.
    ///
    /// Rows use stable projected history-and-screen coordinates. The caller
    /// owns the returned slice and must free it with `allocator`.
    pub fn copyText(
        self: *const Terminal,
        allocator: std.mem.Allocator,
        range: TextRange,
        max_bytes: usize,
    ) TextError![]const u8 {
        return copyTextRange(allocator, &self.screen_state, range, max_bytes);
    }

    /// Encode one host input event according to current terminal modes.
    ///
    /// Non-paste results borrow `scratch` or event bytes. Paste encoding may
    /// allocate through `allocator`; callers must always call `deinit` on the
    /// returned value. Paste length overflow is reported separately from
    /// allocator exhaustion. Mouse input may also fail while retaining a
    /// bounded locator report; failure preserves pending output and report
    /// latches.
    pub fn encodeInput(
        self: *Terminal,
        allocator: std.mem.Allocator,
        scratch: *InputScratch,
        event: InputEvent,
    ) InputError!EncodedInput {
        return switch (event) {
            .bytes => |bytes| .{ .bytes = bytes },
            .key => |key| .{ .bytes = try self.encodeKeyInput(scratch, key) },
            .mouse => |mouse| .{ .bytes = try self.encodeMouseInput(scratch, mouse) },
            .focus => |focus| .{ .bytes = self.encodeFocusInput(scratch, focus) },
            .paste => |text| input.encodePaste(self.modes.bracketed_paste, allocator, text),
        };
    }

    fn encodeKeyInput(
        self: *Terminal,
        scratch: *InputScratch,
        event: input.KeyEvent,
    ) error{ InvalidUtf8, InvalidText, KeyTextLimit }![]const u8 {
        if (self.modes.keyboard_action_mode) return scratch.buf[0..0];
        if (!self.modes.auto_repeat and event.action == .repeat) return scratch.buf[0..0];
        const kitty_flags = self.kitty.activeScreenConst(
            self.screen_state.alt_active,
        ).keyboard.flags;
        comptime std.debug.assert(@sizeOf(InputScratch) >=
            input.max_kitty_encoded_bytes);
        const encoded = input.encodeEvent(
            scratch.buf[0..],
            event.key,
            event.mods,
            event.action,
            event.shifted,
            event.alternate,
            event.legacy_text,
            event.text,
            self.modes.application_cursor_keys,
            self.modes.application_keypad,
            self.modes.modify_other_keys,
            self.modes.key_format[4],
            kitty_flags,
        ) catch |failure| switch (failure) {
            error.InvalidUtf8 => return error.InvalidUtf8,
            error.InvalidText => return error.InvalidText,
            error.KeyTextLimit => return error.KeyTextLimit,
            // InputScratch is mechanically larger than the complete encoding
            // bound asserted above; callers cannot reach this encoder error.
            error.EncodingLimit => unreachable,
        };
        if (self.modes.meta_sends_escape and event.mods.alt and
            event.legacy_text.len != 0 and
            encoded.ptr == event.legacy_text.ptr and encoded.len == event.legacy_text.len)
        {
            if (encoded.len >= scratch.buf.len) return error.KeyTextLimit;
            std.mem.copyBackwards(u8, scratch.buf[1 .. encoded.len + 1], encoded);
            scratch.buf[0] = 0x1b;
            return scratch.buf[0 .. encoded.len + 1];
        }
        if (self.modes.newline_mode and
            event.key == .named and
            event.key.named == .enter and
            std.mem.eql(u8, encoded, "\r"))
        {
            return input.writeScratch(scratch, "\r\n");
        }
        return encoded;
    }

    fn encodeMouseInput(self: *Terminal, scratch: *InputScratch, event: input.MouseEvent) replies.AppendError![]const u8 {
        try handleMouseEvent(&self.locator, self.allocator, &self.reply_buffer, scratch.buf[0..], event);
        const encoded = input.encodeMouse(scratch.buf[0..], event, self.modes.mouse_tracking, self.modes.mouse_protocol);
        std.debug.assert(encoded.len <= scratch.buf.len);
        return encoded;
    }

    fn encodeFocusInput(self: *const Terminal, scratch: *InputScratch, event: input.FocusEvent) []const u8 {
        if (!self.modes.focus_reporting) return scratch.buf[0..0];
        return input.writeScratch(scratch, switch (event) {
            .in => "\x1b[I",
            .out => "\x1b[O",
        });
    }

    /// Borrows ordered protocol reply bytes until the next terminal mutation.
    pub fn replyBytes(self: *const Terminal) []const u8 {
        return self.reply_buffer.bytes();
    }

    /// Consumes one successfully written reply prefix without allocating.
    ///
    /// A count larger than `replyBytes().len` preserves the complete queue.
    pub fn consumeReplyBytes(self: *Terminal, count: usize) ReplyConsumeError!void {
        try self.reply_buffer.consumePrefix(count);
        advanceIdentity(&self.semantic_sequence);
    }

    /// Drain and decode a pending OSC 52 clipboard-set consequence.
    ///
    /// A returned slice is owned by `allocator`; `null` means no decodable set
    /// request was pending. Allocation failure preserves the request.
    pub fn takeClipboard(
        self: *Terminal,
        generation: u64,
        allocator: std.mem.Allocator,
    ) error{ OutOfMemory, StaleClipboardRequest }!?[]u8 {
        const consequence = self.consequenceHead() orelse return error.StaleClipboardRequest;
        if (consequence.id() != generation or std.meta.activeTag(consequence) != .clipboard)
            return error.StaleClipboardRequest;
        const request = consequence.clipboard;
        if (request.protocol != .osc52 or request.kind != .set) return null;
        const decoded = decodeClipboardSet(allocator, request.payload) catch |failure| switch (failure) {
            error.OutOfMemory => return error.OutOfMemory,
            else => @panic("retained OSC 52 set failed prior grammar validation"),
        };
        self.consequences.consumeHead(generation) catch return error.StaleClipboardRequest;
        advanceIdentity(&self.semantic_sequence);
        return decoded;
    }

    /// Copies one decoded FIFO-head OSC 52 set without consuming it.
    ///
    /// The caller owns a successful slice with `allocator`. Stale identity,
    /// allocation failure, and the caller byte bound preserve the exact head.
    pub fn copyClipboard(
        self: *Terminal,
        generation: u64,
        allocator: std.mem.Allocator,
        max_bytes: usize,
    ) error{ OutOfMemory, StaleClipboardRequest, ClipboardLimit }!?[]u8 {
        const consequence = self.consequenceHead() orelse return error.StaleClipboardRequest;
        if (consequence.id() != generation or std.meta.activeTag(consequence) != .clipboard)
            return error.StaleClipboardRequest;
        const request = consequence.clipboard;
        if (request.protocol != .osc52 or request.kind != .set) return null;
        const decoded_len: usize = @intCast(
            decodedClipboardSetSize(request.payload) catch
                @panic("retained OSC 52 set failed prior grammar validation"),
        );
        if (decoded_len > max_bytes) return error.ClipboardLimit;
        return decodeClipboardSet(allocator, request.payload) catch |failure| switch (failure) {
            error.OutOfMemory => return error.OutOfMemory,
            else => @panic("retained OSC 52 set failed prior grammar validation"),
        };
    }

    /// Queue one host-approved OSC 52 reply and consume its query only after complete bounded serialization.
    pub fn replyClipboard(self: *Terminal, generation: u64, bytes: []const u8) ClipboardReplyError!bool {
        const consequence = self.consequenceHead() orelse return error.StaleClipboardRequest;
        if (consequence.id() != generation or std.meta.activeTag(consequence) != .clipboard)
            return error.StaleClipboardRequest;
        const request = consequence.clipboard;
        if (request.protocol != .osc52 or request.kind != .query) return false;
        try appendClipboardQueryReply(&self.reply_buffer, self.allocator, request.selection, bytes);
        self.consequences.consumeHead(generation) catch return error.StaleClipboardRequest;
        advanceIdentity(&self.semantic_sequence);
        return true;
    }

    /// Queue one exact reply for the matching FIFO-head OSC 22 query.
    pub fn replyPointerShape(
        self: *Terminal,
        generation: u64,
        payload: []const u8,
    ) PointerShapeReplyError!void {
        const consequence = self.consequenceHead() orelse return error.StalePointerShape;
        if (consequence.id() != generation or std.meta.activeTag(consequence) != .pointer_shape)
            return error.StalePointerShape;
        const request = consequence.pointer_shape;
        if (request.payload.len == 0 or request.payload[0] != '?')
            return error.PointerShapeReplyMismatch;
        try ensureRetainedBound(byteCount(payload), pointer_shape_reply_max_bytes);
        const output = &self.reply_buffer;
        const start = byteCount(output.bytes());
        errdefer output.truncate(start);
        try output.append("\x1b]22;");
        try output.append(payload);
        try output.append("\x1b\\");
        self.consequences.consumeHead(generation) catch return error.StalePointerShape;
        advanceIdentity(&self.semantic_sequence);
    }

    /// Serializes one host-owned Kitty OSC 72 event without retaining caller borrows.
    pub fn encodeDragDropEvent(
        self: *Terminal,
        event: DragDropEvent,
        allocator: std.mem.Allocator,
    ) DragDropEventError![]u8 {
        var output = replies.Buffer.init(allocator);
        output.copyFramingFrom(&self.reply_buffer);
        errdefer output.deinit();
        try output.appendControl(.terminal, .osc);
        try output.append("72;");
        var metadata: [192]u8 = undefined;
        switch (event) {
            .query => |value| {
                const header = if (value.client_id) |id|
                    std.fmt.bufPrint(&metadata, "t=q:i={d};", .{id}) catch
                        return error.ConsequenceLimit
                else
                    "t=q;";
                try output.append(header);
            },
            .move => |value| {
                if (value.mimes.len > drag_drop_packet_max_bytes) return error.ConsequenceLimit;
                const header = if (value.client_id) |id|
                    std.fmt.bufPrint(
                        &metadata,
                        "t={c}:i={d}:x={d}:y={d}:X={d}:Y={d}:o={d};",
                        .{ if (value.drop) @as(u8, 'M') else 'm', id, value.cell_x, value.cell_y, value.pixel_x, value.pixel_y, value.operation },
                    ) catch return error.ConsequenceLimit
                else
                    std.fmt.bufPrint(
                        &metadata,
                        "t={c}:x={d}:y={d}:X={d}:Y={d}:o={d};",
                        .{ if (value.drop) @as(u8, 'M') else 'm', value.cell_x, value.cell_y, value.pixel_x, value.pixel_y, value.operation },
                    ) catch return error.ConsequenceLimit;
                try output.append(header);
                try output.append(value.mimes);
            },
            .leave => |value| {
                const header = if (value.client_id) |id|
                    std.fmt.bufPrint(&metadata, "t=m:i={d}:x=-1:y=-1:X=0:Y=0:o=1;", .{id}) catch
                        return error.ConsequenceLimit
                else
                    "t=m:x=-1:y=-1:X=0:Y=0:o=1;";
                try output.append(header);
            },
            .data => |value| {
                if (value.index == 0 or value.bytes.len > drag_drop_data_max_bytes)
                    return error.InvalidArgument;
                const header = if (value.client_id) |id|
                    std.fmt.bufPrint(
                        &metadata,
                        "t=r:i={d}:x={d}:m={d};",
                        .{ id, value.index, @intFromBool(value.more) },
                    ) catch return error.ConsequenceLimit
                else
                    std.fmt.bufPrint(
                        &metadata,
                        "t=r:x={d}:m={d};",
                        .{ value.index, @intFromBool(value.more) },
                    ) catch return error.ConsequenceLimit;
                try output.append(header);
                const encoded_len = std.base64.standard.Encoder.calcSize(value.bytes.len);
                if (encoded_len > drag_drop_packet_max_bytes) return error.InvalidArgument;
                const encoded = try allocator.alloc(u8, encoded_len);
                defer allocator.free(encoded);
                const encoded_bytes = std.base64.standard.Encoder.encode(encoded, value.bytes);
                std.debug.assert(encoded_bytes.len == encoded.len);
                try output.append(encoded);
            },
            .failure => |value| {
                const header = if (value.index) |index|
                    if (value.client_id) |id|
                        std.fmt.bufPrint(
                            &metadata,
                            "t=R:i={d}:x={d};",
                            .{ id, index },
                        ) catch return error.ConsequenceLimit
                    else
                        std.fmt.bufPrint(&metadata, "t=R:x={d};", .{index}) catch
                            return error.ConsequenceLimit
                else if (value.client_id) |id|
                    std.fmt.bufPrint(&metadata, "t=R:i={d};", .{id}) catch
                        return error.ConsequenceLimit
                else
                    "t=R;";
                try output.append(header);
                try output.append(value.reason.bytes());
            },
        }
        try output.appendControl(.terminal, .st);
        return output.toOwnedSlice();
    }

    /// Queue one exact reply for the matching FIFO-head query, consuming it only after serialization.
    pub fn replyWindow(
        self: *Terminal,
        generation: u64,
        reply: WindowReply,
    ) WindowReplyError!void {
        const consequence = self.consequenceHead() orelse return error.StaleWindowRequest;
        if (consequence.id() != generation or std.meta.activeTag(consequence) != .window)
            return error.StaleWindowRequest;
        const occurrence = consequence.window;
        if (!windowReplyMatches(occurrence.request, reply)) return error.WindowReplyMismatch;

        const output = &self.reply_buffer;
        const start = byteCount(output.bytes());
        errdefer output.truncate(start);
        try appendWindowReply(output, self.allocator, reply);
        self.consequences.consumeHead(generation) catch return error.StaleWindowRequest;
        advanceIdentity(&self.semantic_sequence);
    }

    fn activeSavepoint(self: *Terminal) *Savepoint {
        return if (self.screen_state.alt_active) &self.alternate_savepoint else &self.primary_savepoint;
    }

    fn activeSavepointConst(self: *const Terminal) *const Savepoint {
        return if (self.screen_state.alt_active) &self.alternate_savepoint else &self.primary_savepoint;
    }

    fn restoreCursorPosition(active: *Screen, row: u16, col: u16) void {
        if (active.rows == 0 or active.cols == 0) {
            active.cursor.setPositionStructural(0, 0);
            return;
        }

        const top = if (active.origin_mode) active.scroll_top else 0;
        const bottom = if (active.origin_mode) @min(active.scroll_bottom, active.rows - 1) else active.rows - 1;
        const bounded_row = @max(top, @min(row, bottom));
        const bounded_col = @min(col, active.cols - 1);
        active.cursor.setPositionStructural(bounded_row, bounded_col);
    }

    /// Copies the palette, dynamic defaults, cursor colors, and screen-wide
    /// reverse state used to resolve terminal visual values.
    pub const Presentation = struct {
        palette: [256]Terminal.Rgb,
        foreground: Terminal.Rgb,
        background: Terminal.Rgb,
        cursor: ?Terminal.Rgb,
        cursor_text: ?Terminal.Rgb,
        selection_background: ?Terminal.Rgb,
        selection_foreground: ?Terminal.Rgb,
        reverse_screen: bool,
    };

    fn defaultPresentation() Presentation {
        const colors = TerminalColorState{};
        return .{
            .palette = colors.palette,
            .foreground = colors.foreground,
            .background = colors.background,
            .cursor = null,
            .cursor_text = null,
            .selection_background = null,
            .selection_foreground = null,
            .reverse_screen = false,
        };
    }
};

fn windowReplyMatches(request: WindowRequest, reply: WindowReply) bool {
    return switch (request) {
        .report_state => reply == .state,
        .report_position => reply == .position,
        .report_screen_cells => reply == .screen_cells,
        .report_icon_title => reply == .icon_title,
        else => false,
    };
}

fn appendWindowReply(
    output: *replies.Buffer,
    _: std.mem.Allocator,
    reply: WindowReply,
) ApplyError!void {
    var scratch: input.Scratch = .{};
    switch (reply) {
        .state => |state| try output.appendCsi(
            .iterm,
            if (state == .normal) "1t" else "2t",
        ),
        .position => |position| try output.appendCsi(
            .iterm,
            std.fmt.bufPrint(scratch.buf[0..], "3;{d};{d}t", .{ position.x, position.y }) catch
                @panic("bounded window-position reply exceeded scratch"),
        ),
        .screen_cells => |size| try output.appendCsi(
            .iterm,
            std.fmt.bufPrint(scratch.buf[0..], "9;{d};{d}t", .{ size.rows, size.cols }) catch
                @panic("bounded screen-cell reply exceeded scratch"),
        ),
        .icon_title => |title| {
            try ensureRetainedBound(byteCount(title), consequence_payload_max_bytes);
            try output.appendControl(.iterm, .osc);
            try output.append("L");
            try output.append(title);
            try output.appendControl(.iterm, .st);
        },
    }
}

fn isWindowQuery(request: WindowRequest) bool {
    return switch (request) {
        .report_state, .report_position, .report_screen_cells, .report_icon_title => true,
        else => false,
    };
}

fn validateDimensions(rows: u16, cols: u16) error{InvalidDimensions}!void {
    if (rows == 0 or cols == 0) return error.InvalidDimensions;
}

fn isKeyFormatResource(resource: u8) bool {
    return resource <= 4 or resource == 6 or resource == 7;
}

comptime {
    const maximum_cell_count =
        @as(u64, std.math.maxInt(u16)) * @as(u64, std.math.maxInt(u16));
    std.debug.assert(maximum_cell_count <= std.math.maxInt(u32));
    std.debug.assert(maximum_cell_count <= std.math.maxInt(usize));
}

test "terminal borrows bounded caller-selected history projections" {
    var vt = try Terminal.initWithHistory(std.testing.allocator, 3, 5, 8);
    defer vt.deinit();

    const feed = try vt.feed("1AAAA\r\n2BBBB\r\n3CCCC\r\n4DDDD");
    try std.testing.expect(feed.state_changed);
    try std.testing.expect(vt.semanticView(0).history_count > 0);
    const top = vt.semanticView(std.math.maxInt(u32));
    try std.testing.expectEqual(vt.semanticView(0).history_count, top.history_offset);
    const bottom = vt.semanticView(0);
    try std.testing.expectEqual(@as(u32, 0), bottom.history_offset);
}

test "terminal feed retains no caller viewport intent" {
    var vt = try Terminal.initWithHistory(std.testing.allocator, 3, 5, 8);
    defer vt.deinit();

    const initial_feed = try vt.feed("1AAAA\r\n2BBBB\r\n3CCCC\r\n4DDDD");
    try std.testing.expect(initial_feed.state_changed);
    const before = vt.semanticView(1).cellAt(0, 0);

    const append_feed = try vt.feed("\r\n5EEEE");
    try std.testing.expect(append_feed.state_changed);

    try std.testing.expectEqual(before, vt.semanticView(2).cellAt(0, 0));
    try std.testing.expectEqual(@as(u32, 0), vt.semanticView(0).history_offset);
}

test "feed summary and semantic state report dropped history" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var terminal = try Terminal.initWithHistory(failing.allocator(), 1, 2, 4);
    defer terminal.deinit();
    failing.fail_index = failing.alloc_index;

    const dropped = try terminal.feed("\x1b[S");
    try std.testing.expect(dropped.state_changed);
    try std.testing.expect(dropped.history_lost);
    try std.testing.expectEqual(
        @as(u64, 1),
        terminal.historyLossCount(),
    );

    failing.fail_index = std.math.maxInt(usize);
    const retained = try terminal.feed("\x1b[S");
    try std.testing.expect(!retained.history_lost);
    try std.testing.expectEqual(
        @as(u64, 1),
        terminal.historyLossCount(),
    );
}

test "terminal retains every bounded bell and remains reusable" {
    var vt = try Terminal.init(std.testing.allocator, 2, 2);
    defer vt.deinit();

    const first = try vt.feed("\x07");
    try std.testing.expect(first.state_changed);
    try std.testing.expectEqual(@as(u64, 1), vt.consequenceHead().?.bell.id);

    const second = try vt.feed("\x07x");
    try std.testing.expect(second.state_changed);
    try std.testing.expectEqual(@as(u16, 2), vt.consequenceCount());
    try std.testing.expectEqual(@as(u21, 'x'), vt.semanticView(0).cellAt(0, 0));

    try std.testing.expect((try vt.feed("\x07")).state_changed);
    while (vt.consequenceHead()) |consequence|
        try vt.consumeConsequence(consequence.id());
    const reused = try vt.feed("y");
    try std.testing.expect(reused.state_changed);
    try std.testing.expectEqual(@as(u21, 'y'), vt.semanticView(0).cellAt(0, 1));
}

test "OSC 66 fixed cluster is fragmented, bounded, and overwritten atomically" {
    var terminal = try Terminal.init(std.testing.allocator, 4, 8);
    defer terminal.deinit();
    const before = terminal.semanticSequence();
    const parts = [_][]const u8{
        "\x1b]66;s=2:w=2:n=1:",
        "d=2:v=1:h=2;Hi",
        "\x1b\\",
    };
    for (parts) |part| {
        const summary = try terminal.feed(part);
        std.debug.assert(!summary.title_changed and !summary.icon_changed);
    }
    try std.testing.expect(terminal.semanticSequence() > before);
    const screen = terminal.screen_state.activeConst();
    try std.testing.expectEqual(@as(u16, 4), screen.cursor.col);
    var row: u16 = 0;
    while (row < 2) : (row += 1) {
        var col: u16 = 0;
        while (col < 4) : (col += 1) {
            const cell = screen.cellInfoAt(row, col);
            try std.testing.expectEqual(@as(u8, 4), cell.width);
            try std.testing.expectEqual(@as(u8, 2), cell.height);
            try std.testing.expectEqual(@as(u8, @intCast(col)), cell.x);
            try std.testing.expectEqual(@as(u8, @intCast(row)), cell.y);
            try std.testing.expectEqual(@as(u4, 1), cell.subscale_n);
            try std.testing.expectEqual(@as(u4, 2), cell.subscale_d);
            try std.testing.expectEqual(@as(u2, 1), cell.vertical_align);
            try std.testing.expectEqual(@as(u2, 2), cell.horizontal_align);
            try std.testing.expectEqual(@as(u32, 'H'), cell.codepoint);
            try std.testing.expectEqual(@as(u8, 1), cell.combining_len);
            try std.testing.expectEqual(@as(u32, 'i'), cell.combining[0]);
        }
    }

    try std.testing.expect((try terminal.feed("\x1b[2;2HX")).state_changed);
    try std.testing.expectEqual(@as(u32, 'H'), terminal.screen_state.activeConst().cellInfoAt(1, 1).codepoint);
    try std.testing.expectEqual(@as(u32, 'X'), terminal.screen_state.activeConst().cellInfoAt(1, 4).codepoint);
    try std.testing.expect((try terminal.feed("\x1b[1;2HX")).state_changed);
    try std.testing.expectEqual(@as(u32, 'X'), terminal.screen_state.activeConst().cellInfoAt(0, 1).codepoint);
    try std.testing.expectEqual(@as(u32, ' '), terminal.screen_state.activeConst().cellInfoAt(0, 0).codepoint);
    try std.testing.expectEqual(@as(u32, ' '), terminal.screen_state.activeConst().cellInfoAt(1, 3).codepoint);
}

test "OSC 66 malformed and overlong cell text preserve terminal state" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    const sequence = terminal.semanticSequence();
    try std.testing.expect(!(try terminal.feed("\x1b]66;s=x;bad\x07")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b]66;w=2;abcde\x07")).state_changed);
    try std.testing.expect(!(try terminal.feed("\x1b]66;s=8:w=8;A\x07")).state_changed);
    try std.testing.expectEqual(sequence, terminal.semanticSequence());
    try std.testing.expectEqual(@as(u16, 0), terminal.screen_state.activeConst().cursor.col);
}

test "OSC 66 natural width splits bounded base and combining clusters" {
    var terminal = try Terminal.init(std.testing.allocator, 3, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("\x1b]66;s=2;A\xcc\x81B\x07")).state_changed);
    const screen = terminal.screen_state.activeConst();
    try std.testing.expectEqual(@as(u16, 4), screen.cursor.col);
    try std.testing.expectEqual(@as(u32, 'A'), screen.cellInfoAt(0, 0).codepoint);
    try std.testing.expectEqual(@as(u8, 1), screen.cellInfoAt(0, 0).combining_len);
    try std.testing.expectEqual(@as(u32, 0x301), screen.cellInfoAt(0, 0).combining[0]);
    try std.testing.expectEqual(@as(u32, 'B'), screen.cellInfoAt(0, 2).codepoint);
    try std.testing.expectEqual(@as(u8, 2), screen.cellInfoAt(1, 3).width);
    try std.testing.expectEqual(@as(u8, 1), screen.cellInfoAt(1, 3).y);
}

test "OSC 66 resize drops complete clusters without stale continuations" {
    var terminal = try Terminal.init(std.testing.allocator, 4, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("\x1b]66;s=2:w=2;Hi\x07")).state_changed);
    try terminal.resize(3, 5);
    const screen = terminal.screen_state.activeConst();
    var row: u16 = 0;
    while (row < screen.rows) : (row += 1) {
        var col: u16 = 0;
        while (col < screen.cols) : (col += 1) {
            const cell = screen.cellInfoAt(row, col);
            try std.testing.expectEqual(@as(u8, 1), cell.width);
            try std.testing.expectEqual(@as(u8, 1), cell.height);
            try std.testing.expectEqual(@as(u8, 0), cell.x);
            try std.testing.expectEqual(@as(u8, 0), cell.y);
        }
    }
}

test "OSC 66 cluster survives whole-grid scroll and erase repairs every member" {
    var terminal = try Terminal.init(std.testing.allocator, 5, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("\x1b[2;1H\x1b]66;s=2:w=2;Hi\x07")).state_changed);
    const screen = terminal.screen_state.active();
    try std.testing.expect(screen.scrollUpRegion(0, 4, 1));
    try std.testing.expectEqual(@as(u8, 0), screen.cellInfoAt(0, 0).y);
    try std.testing.expectEqual(@as(u8, 1), screen.cellInfoAt(1, 3).y);
    try std.testing.expect(screen.eraseRect(.{
        .top = 1,
        .left = 3,
        .bottom = 1,
        .right = 3,
    }, false));
    var row: u16 = 0;
    while (row < 2) : (row += 1) {
        var col: u16 = 0;
        while (col < 4) : (col += 1) {
            const cell = screen.cellInfoAt(row, col);
            try std.testing.expectEqual(@as(u8, 1), cell.width);
            try std.testing.expectEqual(@as(u8, 1), cell.height);
            try std.testing.expectEqual(@as(u32, 0), cell.codepoint);
        }
    }
}

test "OSC 66 rectangular copy rejects cluster source without destination mutation" {
    var terminal = try Terminal.init(std.testing.allocator, 4, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("\x1b]66;s=2:w=2;Hi\x07")).state_changed);
    const screen = terminal.screen_state.active();
    const before = screen.cellInfoAt(3, 6);
    try std.testing.expect(!screen.copyRect(.{
        .area = .{ .top = 0, .left = 0, .bottom = 1, .right = 3 },
        .source_page = 1,
        .dest_top = 2,
        .dest_left = 4,
        .dest_page = 1,
    }));
    try std.testing.expectEqualDeep(before, screen.cellInfoAt(3, 6));
    try std.testing.expectEqual(@as(u8, 4), screen.cellInfoAt(1, 3).width);
    try std.testing.expectEqual(@as(u8, 1), screen.cellInfoAt(1, 3).y);
}

test "OSC 66 character insertion removes the whole intersecting cluster" {
    var terminal = try Terminal.init(std.testing.allocator, 4, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("\x1b]66;s=2:w=2;Hi\x07")).state_changed);
    const screen = terminal.screen_state.active();
    screen.cursor.row = 0;
    screen.cursor.col = 1;
    try std.testing.expect(screen.insertChars(1));
    var row: u16 = 0;
    while (row < 2) : (row += 1) {
        var col: u16 = 0;
        while (col < 4) : (col += 1) {
            const cell = screen.cellInfoAt(row, col);
            try std.testing.expectEqual(@as(u8, 1), cell.width);
            try std.testing.expectEqual(@as(u8, 1), cell.height);
            try std.testing.expectEqual(@as(u8, 0), cell.x);
            try std.testing.expectEqual(@as(u8, 0), cell.y);
        }
    }
}

const CursorSavepoint = struct {
    row: u16 = 0,
    col: u16 = 0,
    style: Screen.CursorStyle = Screen.default_cursor_style,
    visible: bool = true,
};

// Stores cursor presentation, rendition, charset, origin, and wrap state for one screen-bank save slot.
const Savepoint = struct {
    valid: bool = false,
    cursor: CursorSavepoint = .{},
    current_attrs: Screen.CellAttrs = Screen.default_cell_attrs,
    reverse_screen_mode: bool = false,
    origin_mode: bool = false,
    auto_wrap: bool = true,
    wrap_pending: bool = false,
    gl_index: u8 = 0,
    gr_index: u8 = 1,
    designations: [4]u8 = .{ 'B', 'B', 'B', 'B' },

    /// Returns the savepoint to default cursor and charset state.
    pub fn clear(self: *Savepoint) void {
        self.* = .{};
    }
};

const RouteOwnerTests = struct {
    const ParserEvent = parser_mod.Event;
    const EraseMode = ScreenEraseMode;
    const csi_max_params = parser_mod.max_params;
    const empty_params = @as([csi_max_params]i32, @splat(0));
    const empty_separators = parser_mod.CsiSeparatorList.empty;
    const empty_intermediates = @as([parser_mod.max_intermediates]u8, @splat(0));

    fn makeStyleChange(comptime final: u8, comptime p0: i32, comptime p1: i32, comptime count: u8) ParserEvent {
        const params = [_]i32{ p0, p1 } ++ @as([(csi_max_params - 2)]i32, @splat(0));
        return ParserEvent{ .style_change = .{
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

    fn makeStyleChangeWithIntermediate(comptime final: u8, comptime intermediate: u8) ParserEvent {
        const params = @as([csi_max_params]i32, @splat(0));
        const intermediates = [_]u8{intermediate} ++ @as([(parser_mod.max_intermediates - 1)]u8, @splat(0));
        return ParserEvent{ .style_change = .{
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

    fn makeStyleChangeWithParamAndIntermediate(comptime final: u8, comptime p0: i32, comptime intermediate: u8) ParserEvent {
        const params = [_]i32{p0} ++ @as([(csi_max_params - 1)]i32, @splat(0));
        const intermediates = [_]u8{intermediate} ++ @as([(parser_mod.max_intermediates - 1)]u8, @splat(0));
        return ParserEvent{ .style_change = .{
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

    fn makePrivateStyleChange(comptime final: u8, comptime params_in: []const i32) ParserEvent {
        const params = comptime blk: {
            var out = @as([csi_max_params]i32, @splat(0));
            for (params_in, 0..) |value, idx| out[idx] = value;
            break :blk out;
        };
        return ParserEvent{ .style_change = .{
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

    fn makeEscFinal(final: u8) ParserEvent {
        return ParserEvent{ .esc_dispatch = .{
            .final = final,
            .intermediates = @as([4]u8, @splat(0)),
            .intermediates_len = 0,
        } };
    }

    fn expectDecModes(event: ParserEvent, enabled: bool, expected: []const u16) !void {
        const semantic = routeParserEvent(event) orelse return error.NoEvent;
        const modes = switch (semantic) {
            .dec_mode_set => |modes| if (enabled) modes else return error.UnexpectedEvent,
            .dec_mode_reset => |modes| if (!enabled) modes else return error.UnexpectedEvent,
            else => return error.UnexpectedEvent,
        };
        try std.testing.expectEqualSlices(u16, expected, modes.params[0..modes.param_count]);
    }

    test "actions: text event maps to write_text" {
        const sem = routeParserEvent(ParserEvent{ .text = "hello" }) orelse return error.NoEvent;
        try std.testing.expectEqualSlices(u8, "hello", sem.write_text);
    }

    test "actions: codepoint event maps to write_codepoint" {
        const sem = routeParserEvent(ParserEvent{ .codepoint = 0xE9 }) orelse return error.NoEvent;
        try std.testing.expectEqual(@as(u21, 0xE9), sem.write_codepoint);
    }

    test "actions: DEC private application cursor enable maps true" {
        var params = @as([csi_max_params]i32, @splat(0));
        params[0] = 1;
        const ev = ParserEvent{ .style_change = .{
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
        const ev = ParserEvent{ .style_change = .{
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
        const ev = ParserEvent{ .style_change = .{
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
        var ev = ParserEvent{ .style_change = .{
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
        var ev = ParserEvent{ .style_change = .{
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
            MediaCopyRequest{ .private = true, .parameter = 5 },
            routeParserEvent(ev).?.media_copy_request,
        );
    }

    test "actions: application keypad and modifyOtherKeys mappings" {
        try std.testing.expect(routeParserEvent(makeEscFinal('=')).?.application_keypad);
        try std.testing.expect(!routeParserEvent(makeEscFinal('>')).?.application_keypad);

        var params = @as([csi_max_params]i32, @splat(0));
        params[0] = 66;
        var ev = ParserEvent{ .style_change = .{
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
        ev = ParserEvent{ .style_change = .{
            .final = 'm',
            .params = params[0..],
            .separators = empty_separators,
            .param_count = 2,
            .leader = '>',
            .private = false,
            .intermediates = empty_intermediates[0..],
            .intermediates_len = 0,
        } };
        try std.testing.expectEqual(@as(i8, 2), routeParserEvent(ev).?.modify_other_keys_set);

        ev.style_change.final = 'n';
        try std.testing.expect(routeParserEvent(ev).? == .modify_other_keys_disable);

        ev.style_change.final = 'm';
        ev.style_change.leader = '?';
        ev.style_change.private = true;
        ev.style_change.param_count = 1;
        try std.testing.expect(routeParserEvent(ev).? == .modify_other_keys_query);
    }

    test "actions: xterm key format set reset and query mappings" {
        var params = @as([csi_max_params]i32, @splat(0));
        params[0] = 4;
        params[1] = 1;
        var ev = ParserEvent{ .style_change = .{
            .final = 'f',
            .params = params[0..],
            .separators = empty_separators,
            .param_count = 2,
            .leader = '>',
            .private = false,
            .intermediates = empty_intermediates[0..],
            .intermediates_len = 0,
        } };

        var change = routeParserEvent(ev).?.key_format_change;
        try std.testing.expectEqual(@as(?u8, 4), change.resource);
        try std.testing.expectEqual(@as(?u16, 1), change.value);

        ev.style_change.param_count = 1;
        change = routeParserEvent(ev).?.key_format_change;
        try std.testing.expectEqual(@as(?u8, 4), change.resource);
        try std.testing.expectEqual(@as(?u16, null), change.value);

        ev.style_change.param_count = 0;
        change = routeParserEvent(ev).?.key_format_change;
        try std.testing.expectEqual(@as(?u8, null), change.resource);
        try std.testing.expectEqual(@as(?u16, null), change.value);

        ev.style_change.final = 'g';
        ev.style_change.param_count = 1;
        ev.style_change.leader = '?';
        ev.style_change.private = true;
        try std.testing.expectEqual(@as(u8, 4), routeParserEvent(ev).?.key_format_query);
    }

    test "actions: xterm key format resource saturates above 255" {
        var params = @as([csi_max_params]i32, @splat(0));
        params[0] = 300;
        const ev = ParserEvent{ .style_change = .{
            .final = 'f',
            .params = params[0..],
            .separators = empty_separators,
            .param_count = 1,
            .leader = '>',
            .private = false,
            .intermediates = empty_intermediates[0..],
            .intermediates_len = 0,
        } };

        try std.testing.expectEqual(@as(?u8, 255), routeParserEvent(ev).?.key_format_change.resource);
    }

    test "actions: xterm key format query saturates above 255" {
        var params = @as([csi_max_params]i32, @splat(0));
        params[0] = 300;
        const ev = ParserEvent{ .style_change = .{
            .final = 'g',
            .params = params[0..],
            .separators = empty_separators,
            .param_count = 1,
            .leader = '?',
            .private = true,
            .intermediates = empty_intermediates[0..],
            .intermediates_len = 0,
        } };

        try std.testing.expectEqual(@as(u8, 255), routeParserEvent(ev).?.key_format_query);
    }

    test "actions: xterm key format non-positive params normalize to 0" {
        var params = @as([csi_max_params]i32, @splat(0));
        params[0] = -7;
        var ev = ParserEvent{ .style_change = .{
            .final = 'f',
            .params = params[0..],
            .separators = empty_separators,
            .param_count = 1,
            .leader = '>',
            .private = false,
            .intermediates = empty_intermediates[0..],
            .intermediates_len = 0,
        } };

        try std.testing.expectEqual(@as(?u8, 0), routeParserEvent(ev).?.key_format_change.resource);

        params[0] = 0;
        ev.style_change.final = 'g';
        ev.style_change.leader = '?';
        ev.style_change.private = true;
        try std.testing.expectEqual(@as(u8, 0), routeParserEvent(ev).?.key_format_query);
    }

    test "actions: xterm pointer mode maps bounded value" {
        var params = @as([csi_max_params]i32, @splat(0));
        params[0] = 2;
        var ev = ParserEvent{ .style_change = .{
            .final = 'p',
            .params = params[0..],
            .separators = empty_separators,
            .param_count = 1,
            .leader = '>',
            .private = false,
            .intermediates = empty_intermediates[0..],
            .intermediates_len = 0,
        } };
        try std.testing.expectEqual(@as(u2, 2), routeParserEvent(ev).?.pointer_mode);

        params[0] = 9;
        ev.style_change.params = params[0..];
        try std.testing.expectEqual(@as(u2, 3), routeParserEvent(ev).?.pointer_mode);

        ev.style_change.param_count = 0;
        try std.testing.expectEqual(@as(u2, 1), routeParserEvent(ev).?.pointer_mode);
    }

    test "actions: ANSI mode set reset and query map" {
        const set = routeParserEvent(makeStyleChange('h', 4, 20, 2)) orelse return error.NoEvent;
        try std.testing.expectEqual(@as(u8, 2), set.ansi_mode_set.param_count);
        try std.testing.expectEqual(@as(u16, 4), set.ansi_mode_set.params[0]);
        try std.testing.expectEqual(@as(u16, 20), set.ansi_mode_set.params[1]);

        const reset = routeParserEvent(makeStyleChange('l', 2, 0, 1)) orelse return error.NoEvent;
        try std.testing.expectEqual(@as(u8, 1), reset.ansi_mode_reset.param_count);
        try std.testing.expectEqual(@as(u16, 2), reset.ansi_mode_reset.params[0]);

        var params = @as([csi_max_params]i32, @splat(0));
        params[0] = 4;
        var intermediates = @as([4]u8, @splat(0));
        intermediates[0] = '$';
        const query = routeParserEvent(ParserEvent{ .style_change = .{
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
        const elr = routeParserEvent(ParserEvent{ .style_change = .{
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
        const req = routeParserEvent(ParserEvent{ .style_change = .{
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
        const filter = routeParserEvent(ParserEvent{ .style_change = .{
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
        const sle = routeParserEvent(ParserEvent{ .style_change = .{
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
};

comptime {
    std.debug.assert(@sizeOf(RouteOwnerTests) == 0);
}

const CsiMappingOwnerTests = struct {
    const ParserEvent = parser_mod.Event;
    const EraseMode = ScreenEraseMode;
    const csi_max_params = parser_mod.max_params;
    const empty_params = @as([csi_max_params]i32, @splat(0));
    const empty_separators = parser_mod.CsiSeparatorList.empty;
    const empty_intermediates = @as([parser_mod.max_intermediates]u8, @splat(0));

    fn makeStyleChange(comptime final: u8, comptime p0: i32, comptime p1: i32, comptime count: u8) ParserEvent {
        const params = [_]i32{ p0, p1 } ++ @as([(csi_max_params - 2)]i32, @splat(0));
        return ParserEvent{ .style_change = .{
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

    fn makeStyleChangeWithIntermediate(comptime final: u8, comptime intermediate: u8) ParserEvent {
        const params = @as([csi_max_params]i32, @splat(0));
        const intermediates = [_]u8{intermediate} ++ @as([(parser_mod.max_intermediates - 1)]u8, @splat(0));
        return ParserEvent{ .style_change = .{
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

    fn makeStyleChangeWithParamAndIntermediate(comptime final: u8, comptime p0: i32, comptime intermediate: u8) ParserEvent {
        const params = [_]i32{p0} ++ @as([(csi_max_params - 1)]i32, @splat(0));
        const intermediates = [_]u8{intermediate} ++ @as([(parser_mod.max_intermediates - 1)]u8, @splat(0));
        return ParserEvent{ .style_change = .{
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

    fn makePrivateStyleChange(comptime final: u8, comptime params_in: []const i32) ParserEvent {
        const params = comptime blk: {
            var out = @as([csi_max_params]i32, @splat(0));
            for (params_in, 0..) |value, index| out[index] = value;
            break :blk out;
        };
        return ParserEvent{ .style_change = .{
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
        try std.testing.expectEqual(@as(u16, 3), routeParserEvent(makeStyleChange('A', 3, 0, 1)).?.cursor_up);
        try std.testing.expectEqual(@as(u16, 1), routeParserEvent(makeStyleChange('A', 0, 0, 1)).?.cursor_up);
        try std.testing.expectEqual(@as(u16, 5), routeParserEvent(makeStyleChange('B', 5, 0, 1)).?.cursor_down);
        try std.testing.expectEqual(@as(u16, 5), routeParserEvent(makeStyleChange('e', 5, 0, 1)).?.cursor_down);
        try std.testing.expectEqual(@as(u16, 1), routeParserEvent(makeStyleChange('e', 0, 0, 1)).?.cursor_down);
        try std.testing.expectEqual(@as(u16, 2), routeParserEvent(makeStyleChange('C', 2, 0, 1)).?.cursor_forward);
        try std.testing.expectEqual(@as(u16, 2), routeParserEvent(makeStyleChange('a', 2, 0, 1)).?.cursor_forward);
        try std.testing.expectEqual(@as(u16, 1), routeParserEvent(makeStyleChange('a', 0, 0, 1)).?.cursor_forward);
        try std.testing.expectEqual(@as(u16, 4), routeParserEvent(makeStyleChange('D', 4, 0, 1)).?.cursor_back);
        try std.testing.expectEqual(@as(u16, 3), routeParserEvent(makeStyleChange('E', 3, 0, 1)).?.cursor_next_line);
        try std.testing.expectEqual(@as(u16, 1), routeParserEvent(makeStyleChange('E', 0, 0, 1)).?.cursor_next_line);
        try std.testing.expectEqual(@as(u16, 2), routeParserEvent(makeStyleChange('F', 2, 0, 1)).?.cursor_prev_line);
        try std.testing.expectEqual(@as(u16, 1), routeParserEvent(makeStyleChange('F', 0, 0, 1)).?.cursor_prev_line);
        try std.testing.expectEqual(@as(u16, 6), routeParserEvent(makeStyleChange('G', 7, 0, 1)).?.cursor_horizontal_absolute);
        try std.testing.expectEqual(@as(u16, 0), routeParserEvent(makeStyleChange('G', 0, 0, 1)).?.cursor_horizontal_absolute);
        try std.testing.expectEqual(@as(u16, 6), routeParserEvent(makeStyleChange('`', 7, 0, 1)).?.cursor_horizontal_absolute);
        try std.testing.expectEqual(@as(u16, 0), routeParserEvent(makeStyleChange('`', 0, 0, 1)).?.cursor_horizontal_absolute);
        try std.testing.expectEqual(@as(u16, 8), routeParserEvent(makeStyleChange('d', 9, 0, 1)).?.cursor_vertical_absolute);
        try std.testing.expectEqual(@as(u16, 0), routeParserEvent(makeStyleChange('d', 0, 0, 1)).?.cursor_vertical_absolute);
        try std.testing.expectEqual(@as(u16, 3), routeParserEvent(makeStyleChange('I', 3, 0, 1)).?.horizontal_tab_forward);
        try std.testing.expectEqual(@as(u16, 1), routeParserEvent(makeStyleChange('I', 0, 0, 1)).?.horizontal_tab_forward);
        try std.testing.expectEqual(std.math.maxInt(u16), routeParserEvent(makeStyleChange('I', 999999, 0, 1)).?.horizontal_tab_forward);
        try std.testing.expectEqual(@as(u16, 2), routeParserEvent(makeStyleChange('Z', 2, 0, 1)).?.horizontal_tab_back);
        try std.testing.expectEqual(@as(u16, 1), routeParserEvent(makeStyleChange('Z', 0, 0, 1)).?.horizontal_tab_back);
        try std.testing.expectEqual(std.math.maxInt(u16), routeParserEvent(makeStyleChange('Z', 999999, 0, 1)).?.horizontal_tab_back);
    }

    test "csi mapping: editing and scrolling" {
        try std.testing.expectEqual(@as(u16, 3), routeParserEvent(makeStyleChange('L', 3, 0, 1)).?.insert_lines);
        try std.testing.expectEqual(@as(u16, 1), routeParserEvent(makeStyleChange('M', 0, 0, 0)).?.delete_lines);
        try std.testing.expectEqual(@as(u16, 3), routeParserEvent(makeStyleChange('P', 3, 0, 1)).?.delete_chars);
        try std.testing.expectEqual(@as(u16, 1), routeParserEvent(makeStyleChange('P', 0, 0, 0)).?.delete_chars);
        try std.testing.expectEqual(@as(u16, 4), routeParserEvent(makeStyleChange('@', 4, 0, 1)).?.insert_chars);
        try std.testing.expectEqual(@as(u16, 1), routeParserEvent(makeStyleChange('@', 0, 0, 0)).?.insert_chars);
        try std.testing.expectEqual(@as(u16, 4), routeParserEvent(makeStyleChange('b', 4, 0, 1)).?.repeat_preceding);
        try std.testing.expectEqual(@as(u16, 1), routeParserEvent(makeStyleChange('b', 0, 0, 0)).?.repeat_preceding);
        try std.testing.expectEqual(@as(u16, 2), routeParserEvent(makeStyleChange('S', 2, 0, 1)).?.scroll_up_lines);
        try std.testing.expectEqual(@as(u16, 1), routeParserEvent(makeStyleChange('T', 0, 0, 0)).?.scroll_down_lines);

        var intermediates = @as([4]u8, @splat(0));
        intermediates[0] = '+';
        const params = [_]i32{3} ++ @as([(csi_max_params - 1)]i32, @splat(0));
        try std.testing.expectEqual(@as(u16, 3), routeParserEvent(ParserEvent{ .style_change = .{
            .final = 'T',
            .params = params[0..],
            .separators = empty_separators,
            .param_count = 1,
            .leader = 0,
            .private = false,
            .intermediates = intermediates[0..],
            .intermediates_len = 1,
        } }).?.scroll_down_from_history);
    }

    test "csi mapping: positioning, tab, erase, and reset semantics" {
        try std.testing.expectEqual(@as(u16, 1), routeParserEvent(makeStyleChange('r', 2, 5, 2)).?.set_scroll_region.top);
        try std.testing.expectEqual(@as(?u16, 4), routeParserEvent(makeStyleChange('r', 2, 5, 2)).?.set_scroll_region.bottom);
        try std.testing.expectEqual(@as(u16, 2), routeParserEvent(makeStyleChange('r', 3, 0, 1)).?.set_scroll_region.top);
        try std.testing.expectEqual(@as(?u16, null), routeParserEvent(makeStyleChange('r', 3, 0, 1)).?.set_scroll_region.bottom);
        try std.testing.expectEqual(@as(u16, 2), routeParserEvent(makeStyleChange('H', 3, 5, 2)).?.cursor_position.row);
        try std.testing.expectEqual(@as(u16, 4), routeParserEvent(makeStyleChange('H', 3, 5, 2)).?.cursor_position.col);
        try std.testing.expectEqual(@as(u16, 0), routeParserEvent(makeStyleChange('H', 0, 0, 0)).?.cursor_position.row);
        try std.testing.expectEqual(@as(u16, 0), routeParserEvent(makeStyleChange('H', 0, 0, 0)).?.cursor_position.col);
        try std.testing.expectEqual(@as(?SemanticEvent, null), routeParserEvent(makeStyleChange('Y', 1, 0, 1)));
        try std.testing.expect(routeParserEvent(makeStyleChangeWithIntermediate('p', '!')).? == .soft_reset);
        try std.testing.expect(routeParserEvent(makeStyleChange('g', 0, 0, 0)).? == .tab_clear_current);
        try std.testing.expect(routeParserEvent(makeStyleChange('g', 3, 0, 1)).? == .tab_clear_all);
        try std.testing.expect(routeParserEvent(makeStyleChange('g', 5, 0, 1)).? == .tab_clear_all);
        try std.testing.expect(routeParserEvent(makePrivateStyleChange('W', &.{5})).? == .reset_default_tab_stops);
        try std.testing.expect(!routeParserEvent(makeStyleChange('J', 0, 0, 0)).?.erase_display_below);
        try std.testing.expect(!routeParserEvent(makeStyleChange('J', 1, 0, 1)).?.erase_display_above);
        try std.testing.expect(!routeParserEvent(makeStyleChange('J', 2, 0, 1)).?.erase_display_complete);
        try std.testing.expect(!routeParserEvent(makeStyleChange('J', 3, 0, 1)).?.erase_display_scrollback);
        try std.testing.expect(routeParserEvent(makeStyleChange('J', 5, 0, 1)) == null);
        try std.testing.expectEqual(EraseMode.cursor_to_end, routeParserEvent(makeStyleChange('K', 0, 0, 0)).?.erase_line);
        try std.testing.expectEqual(EraseMode.start_to_cursor, routeParserEvent(makeStyleChange('K', 1, 0, 1)).?.erase_line);
        try std.testing.expectEqual(EraseMode.all, routeParserEvent(makeStyleChange('K', 2, 0, 1)).?.erase_line);
        try std.testing.expect(routeParserEvent(makeStyleChange('K', 5, 0, 1)) == null);
        try std.testing.expectEqual(@as(u16, 6), routeParserEvent(makeStyleChange('X', 6, 0, 1)).?.erase_chars);
        try std.testing.expectEqual(@as(u16, 1), routeParserEvent(makeStyleChange('X', 0, 0, 0)).?.erase_chars);
        try std.testing.expectEqual(@as(u16, 3), routeParserEvent(makeStyleChangeWithParamAndIntermediate('@', 3, ' ')).?.shift_left_columns);
        try std.testing.expectEqual(@as(u16, 1), routeParserEvent(makeStyleChangeWithIntermediate('A', ' ')).?.shift_right_columns);
        try std.testing.expect(routeParserEvent(makeStyleChangeWithParamAndIntermediate('q', 7, ' ')) == null);
    }

    test "csi mapping: protection, rectangular ops, and margins" {
        try std.testing.expect(routeParserEvent(makeStyleChangeWithParamAndIntermediate('q', 1, '"')).?.character_protection == .dec);
        try std.testing.expect(routeParserEvent(makeStyleChangeWithParamAndIntermediate('q', 2, '"')).?.character_protection == .none);
        try std.testing.expect(routeParserEvent(makePrivateStyleChange('J', &.{2})).?.erase_display_complete);
        try std.testing.expectEqual(EraseMode.start_to_cursor, routeParserEvent(makePrivateStyleChange('K', &.{1})).?.selective_erase_line);
        try std.testing.expect(routeParserEvent(makePrivateStyleChange('J', &.{5})) == null);
        try std.testing.expect(routeParserEvent(makePrivateStyleChange('K', &.{5})) == null);

        var params = @as([csi_max_params]i32, @splat(0));
        params[0] = 88;
        params[1] = 1;
        params[2] = 2;
        params[3] = 3;
        params[4] = 4;
        var intermediates = @as([4]u8, @splat(0));
        intermediates[0] = '$';
        const fill = routeParserEvent(ParserEvent{ .style_change = .{
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

        params = @as([csi_max_params]i32, @splat(0));
        params[0] = 1;
        params[1] = 1;
        params[2] = 2;
        params[3] = 2;
        params[4] = 1;
        params[5] = 3;
        params[6] = 4;
        params[7] = 1;
        const copy = routeParserEvent(ParserEvent{ .style_change = .{
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
        const insert_params = [_]i32{2} ++ @as([(csi_max_params - 1)]i32, @splat(0));
        try std.testing.expectEqual(@as(u16, 2), routeParserEvent(ParserEvent{ .style_change = .{
            .final = '}',
            .params = insert_params[0..],
            .separators = empty_separators,
            .param_count = 1,
            .leader = 0,
            .private = false,
            .intermediates = intermediates[0..],
            .intermediates_len = 1,
        } }).?.insert_columns);

        const delete_params = [_]i32{3} ++ @as([(csi_max_params - 1)]i32, @splat(0));
        try std.testing.expectEqual(@as(u16, 3), routeParserEvent(ParserEvent{ .style_change = .{
            .final = '~',
            .params = delete_params[0..],
            .separators = empty_separators,
            .param_count = 1,
            .leader = 0,
            .private = false,
            .intermediates = intermediates[0..],
            .intermediates_len = 1,
        } }).?.delete_columns);

        params = @as([csi_max_params]i32, @splat(0));
        params[0] = 1;
        params[1] = 1;
        params[2] = 2;
        params[3] = 2;
        params[4] = 1;
        intermediates[0] = '$';
        const change = routeParserEvent(ParserEvent{ .style_change = .{
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

        const reverse = routeParserEvent(ParserEvent{ .style_change = .{
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
        const extent_params = [_]i32{2} ++ @as([(csi_max_params - 1)]i32, @splat(0));
        try std.testing.expect(routeParserEvent(ParserEvent{ .style_change = .{
            .final = 'x',
            .params = extent_params[0..],
            .separators = empty_separators,
            .param_count = 1,
            .leader = 0,
            .private = false,
            .intermediates = intermediates[0..],
            .intermediates_len = 1,
        } }).?.attr_change_extent_rect);

        const margins = routeParserEvent(makeStyleChange('s', 2, 4, 2)).?;
        try std.testing.expectEqual(@as(u16, 1), margins.set_left_right_margins.left);
        try std.testing.expectEqual(@as(?u16, 3), margins.set_left_right_margins.right);
        const margins_on = routeParserEvent(makePrivateStyleChange('h', &.{69})).?;
        try std.testing.expect(margins_on == .dec_mode_set);
        try std.testing.expectEqual(@as(u16, 69), margins_on.dec_mode_set.params[0]);
        const margins_off = routeParserEvent(makePrivateStyleChange('l', &.{69})).?;
        try std.testing.expect(margins_off == .dec_mode_reset);
        try std.testing.expectEqual(@as(u16, 69), margins_off.dec_mode_reset.params[0]);
    }

    test "csi mapping: cursor style, save restore aliases, and invalid sequence" {
        try std.testing.expectEqual(@as(?SemanticEvent, null), routeParserEvent(ParserEvent.invalid_sequence));
        try std.testing.expect(routeParserEvent(makeStyleChange('s', 0, 0, 0)).? == .save_cursor);
        try std.testing.expect(routeParserEvent(makeStyleChange('u', 0, 0, 0)).? == .restore_cursor);
        var sem = routeParserEvent(makeStyleChangeWithParamAndIntermediate('q', 0, ' ')).?;
        try std.testing.expect(sem.cursor_style == .restore_default);
        sem = routeParserEvent(makeStyleChangeWithParamAndIntermediate('q', 4, ' ')).?;
        try std.testing.expectEqual(Terminal.CursorShape.underline, sem.cursor_style.program_override.shape);
        try std.testing.expect(!sem.cursor_style.program_override.blink);
        sem = routeParserEvent(makeStyleChangeWithParamAndIntermediate('q', 5, ' ')).?;
        try std.testing.expectEqual(Terminal.CursorShape.bar, sem.cursor_style.program_override.shape);
        try std.testing.expect(sem.cursor_style.program_override.blink);
        try std.testing.expect(routeParserEvent(makeStyleChangeWithParamAndIntermediate('q', 7, ' ')) == null);
    }

    test "csi mapping: mode query, save restore, and erase families" {
        var params = @as([csi_max_params]i32, @splat(0));
        params[0] = 1004;
        var intermediates = @as([4]u8, @splat(0));
        intermediates[0] = '$';
        const decrqm = routeParserEvent(ParserEvent{ .style_change = .{
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

        const save = routeParserEvent(makePrivateStyleChange('s', &.{ 1, 7, 1004 })).?;
        try std.testing.expectEqual(@as(u8, 3), save.dec_mode_save.param_count);
        try std.testing.expectEqual(@as(u16, 1), save.dec_mode_save.params[0]);
        try std.testing.expectEqual(@as(u16, 7), save.dec_mode_save.params[1]);
        try std.testing.expectEqual(@as(u16, 1004), save.dec_mode_save.params[2]);

        const restore = routeParserEvent(makePrivateStyleChange('r', &.{ 1, 7, 1004 })).?;
        try std.testing.expectEqual(@as(u8, 3), restore.dec_mode_restore.param_count);
        try std.testing.expectEqual(@as(u16, 1004), restore.dec_mode_restore.params[2]);

        const save_all = routeParserEvent(makePrivateStyleChange('s', &.{})).?;
        try std.testing.expectEqual(@as(u8, 0), save_all.dec_mode_save.param_count);
        const restore_all = routeParserEvent(makePrivateStyleChange('r', &.{})).?;
        try std.testing.expectEqual(@as(u8, 0), restore_all.dec_mode_restore.param_count);

        try std.testing.expect(!routeParserEvent(makeStyleChange('J', 0, 0, 0)).?.erase_display_below);
        try std.testing.expect(!routeParserEvent(makeStyleChange('J', 1, 0, 1)).?.erase_display_above);
        try std.testing.expect(!routeParserEvent(makeStyleChange('J', 2, 0, 1)).?.erase_display_complete);
        try std.testing.expect(!routeParserEvent(makeStyleChange('J', 3, 0, 1)).?.erase_display_scrollback);
        try std.testing.expect(routeParserEvent(makeStyleChange('J', 5, 0, 1)) == null);
        try std.testing.expectEqual(EraseMode.cursor_to_end, routeParserEvent(makeStyleChange('K', 0, 0, 0)).?.erase_line);
        try std.testing.expectEqual(EraseMode.start_to_cursor, routeParserEvent(makeStyleChange('K', 1, 0, 1)).?.erase_line);
        try std.testing.expectEqual(EraseMode.all, routeParserEvent(makeStyleChange('K', 2, 0, 1)).?.erase_line);
        try std.testing.expect(routeParserEvent(makeStyleChange('K', 5, 0, 1)) == null);
        try std.testing.expectEqual(@as(u16, 6), routeParserEvent(makeStyleChange('X', 6, 0, 1)).?.erase_chars);
        try std.testing.expectEqual(@as(u16, 1), routeParserEvent(makeStyleChange('X', 0, 0, 0)).?.erase_chars);
        try std.testing.expectEqual(@as(u16, 3), routeParserEvent(makeStyleChangeWithParamAndIntermediate('@', 3, ' ')).?.shift_left_columns);
        try std.testing.expectEqual(@as(u16, 1), routeParserEvent(makeStyleChangeWithIntermediate('A', ' ')).?.shift_right_columns);
        try std.testing.expect(routeParserEvent(makePrivateStyleChange('W', &.{5})).? == .reset_default_tab_stops);
    }
};

comptime {
    std.debug.assert(@sizeOf(CsiMappingOwnerTests) == 0);
}

const ReportRoutingOwnerTests = struct {
    const ParserEvent = parser_mod.Event;
    const csi_max_params = parser_mod.max_params;
    const empty_params = @as([csi_max_params]i32, @splat(0));
    const empty_separators = parser_mod.CsiSeparatorList.empty;
    const empty_intermediates = @as([parser_mod.max_intermediates]u8, @splat(0));

    fn makeStyleChange(comptime final: u8, comptime p0: i32, comptime p1: i32, comptime count: u8) ParserEvent {
        const params = [_]i32{ p0, p1 } ++ @as([(csi_max_params - 2)]i32, @splat(0));
        return ParserEvent{ .style_change = .{ .final = final, .params = params[0..], .separators = empty_separators, .param_count = count, .leader = 0, .private = false, .intermediates = empty_intermediates[0..], .intermediates_len = 0 } };
    }

    fn makePrivateStyleChange(comptime final: u8, comptime params_in: []const i32) ParserEvent {
        const params = comptime blk: {
            var out = @as([csi_max_params]i32, @splat(0));
            for (params_in, 0..) |value, index| out[index] = value;
            break :blk out;
        };
        return ParserEvent{ .style_change = .{ .final = final, .params = params[0..], .separators = empty_separators, .param_count = @intCast(params_in.len), .leader = '?', .private = true, .intermediates = empty_intermediates[0..], .intermediates_len = 0 } };
    }

    test "report mapping: DSR DECXCPR and DEC locator status map" {
        try std.testing.expect(routeParserEvent(makeStyleChange('n', 5, 0, 1)).? == .device_status_report);
        try std.testing.expect(routeParserEvent(makeStyleChange('n', 6, 0, 1)).? == .cursor_position_report);
        try std.testing.expect(routeParserEvent(makePrivateStyleChange('n', &.{6})).? == .dec_cursor_position_report);
        try std.testing.expectEqual(@as(u16, 55), routeParserEvent(makePrivateStyleChange('n', &.{55})).?.dec_device_status_report);
        try std.testing.expectEqual(@as(u16, 56), routeParserEvent(makePrivateStyleChange('n', &.{56})).?.dec_device_status_report);
        try std.testing.expect(routeParserEvent(makePrivateStyleChange('n', &.{996})).? == .color_preference_query);
    }

    test "report mapping: device attributes and title reports" {
        try std.testing.expect(routeParserEvent(makeStyleChange('c', 0, 0, 0)).? == .primary_device_attributes);
        const da2 = ParserEvent{ .style_change = .{ .final = 'c', .params = empty_params[0..], .separators = empty_separators, .param_count = 0, .leader = '>', .private = false, .intermediates = empty_intermediates[0..], .intermediates_len = 0 } };
        try std.testing.expect(routeParserEvent(da2).? == .secondary_device_attributes);
        var params = @as([csi_max_params]i32, @splat(0));
        params[0] = 0;
        const xtversion = ParserEvent{ .style_change = .{ .final = 'q', .params = params[0..], .separators = empty_separators, .param_count = 1, .leader = '>', .private = false, .intermediates = empty_intermediates[0..], .intermediates_len = 0 } };
        try std.testing.expect(routeParserEvent(xtversion).? == .xtversion);
        var intermediates = @as([4]u8, @splat(0));
        intermediates[0] = '#';
        const xttitlepos = ParserEvent{ .style_change = .{ .final = 'S', .params = empty_params[0..], .separators = empty_separators, .param_count = 0, .leader = 0, .private = false, .intermediates = intermediates[0..], .intermediates_len = 1 } };
        try std.testing.expect(routeParserEvent(xttitlepos).? == .xttitlepos);
        const da3 = ParserEvent{ .style_change = .{ .final = 'c', .params = empty_params[0..], .separators = empty_separators, .param_count = 0, .leader = '=', .private = false, .intermediates = empty_intermediates[0..], .intermediates_len = 0 } };
        try std.testing.expect(routeParserEvent(da3).? == .tertiary_device_attributes);
    }

    test "report mapping: checksum and report request families" {
        var intermediates = @as([4]u8, @splat(0));
        var params = @as([csi_max_params]i32, @splat(0));
        intermediates[0] = '"';
        try std.testing.expect(routeParserEvent(ParserEvent{ .style_change = .{ .final = 'v', .params = params[0..], .separators = empty_separators, .param_count = 0, .leader = 0, .private = false, .intermediates = intermediates[0..], .intermediates_len = 1 } }).? == .screen_extent_report);
        intermediates[0] = '#';
        params[0] = 3;
        try std.testing.expectEqual(@as(u16, 3), routeParserEvent(ParserEvent{ .style_change = .{ .final = 'y', .params = params[0..], .separators = empty_separators, .param_count = 1, .leader = 0, .private = false, .intermediates = intermediates[0..], .intermediates_len = 1 } }).?.xtchecksum);
        intermediates[0] = '*';
        params = @as([csi_max_params]i32, @splat(0));
        params[0] = 7;
        params[1] = 1;
        params[2] = 2;
        params[3] = 3;
        params[4] = 4;
        params[5] = 5;
        const crc = routeParserEvent(ParserEvent{ .style_change = .{ .final = 'y', .params = params[0..], .separators = empty_separators, .param_count = 6, .leader = 0, .private = false, .intermediates = intermediates[0..], .intermediates_len = 1 } }).?.rect_checksum_request;
        try std.testing.expectEqual(@as(u16, 7), crc.request_id);
        try std.testing.expectEqual(@as(u16, 1), crc.page);
        try std.testing.expectEqual(@as(u16, 1), routeParserEvent(makeStyleChange('x', 1, 0, 1)).?.parameters_report);
        intermediates[0] = '#';
        try std.testing.expect(routeParserEvent(ParserEvent{ .style_change = .{ .final = 'R', .params = empty_params[0..], .separators = empty_separators, .param_count = 0, .leader = 0, .private = false, .intermediates = intermediates[0..], .intermediates_len = 1 } }).? == .xtreportcolors);
    }

    test "report mapping: XTREPORTSGR maps selected graphic rendition report" {
        var intermediates = @as([4]u8, @splat(0));
        intermediates[0] = '#';
        var params = @as([csi_max_params]i32, @splat(0));
        params[0] = 1;
        params[1] = 2;
        params[2] = 3;
        params[3] = 4;
        const sgr = routeParserEvent(ParserEvent{ .style_change = .{ .final = '|', .params = params[0..], .separators = empty_separators, .param_count = 4, .leader = 0, .private = false, .intermediates = intermediates[0..], .intermediates_len = 1 } }).?.selected_graphic_rendition_report;
        try std.testing.expectEqual(@as(u16, 0), sgr.top);
        try std.testing.expectEqual(@as(u16, 1), sgr.left);
        try std.testing.expectEqual(@as(?u16, 2), sgr.bottom);
        try std.testing.expectEqual(@as(?u16, 3), sgr.right);
    }
};

comptime {
    std.debug.assert(@sizeOf(ReportRoutingOwnerTests) == 0);
}

test "input error surface excludes unrelated terminal owner limits" {
    const error_names = @typeInfo(Terminal.InputError).error_set.error_names orelse &.{};
    for (error_names) |name| {
        try std.testing.expect(!std.mem.eql(u8, name, "ConsequenceLimit"));
        try std.testing.expect(!std.mem.eql(u8, name, "PropertyLimit"));
    }
}
