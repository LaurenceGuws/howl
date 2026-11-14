//! Optional copied native terminal-request facts; no Server metadata, wire or host policy.
const std = @import("std");
const vt = @import("howl_vt");
const c = @import("vt_native_types");
const Terminal = vt.Terminal;
/// One fully initialized native C request descriptor; payload bytes are copied separately.
pub const Info = c.hvt_request;
/// Exact FIFO identity, payload bound and caller-capacity rejection.
pub const Error = error{ StaleRequest, RequestLimit, BufferTooSmall };
const Projection = struct { info: Info, payload: []const u8 };

fn project(value: Terminal.Consequence, revision: u64) Error!Projection {
    var result = Projection{ .info = std.mem.zeroes(Info), .payload = &.{} };
    result.info.occurrence_id = value.id();
    result.info.terminal_revision = revision;
    result.info.reply_required = @intFromBool(value.requiresReply());
    switch (value) {
        .clipboard => |request| {
            if (request.selection.len > request.payload.len or request.selection.len > c.HVT_MAX_REQUEST_PAYLOAD_BYTES) return error.RequestLimit;
            result.info.kind = c.HVT_REQUEST_CLIPBOARD;
            result.info.data.clipboard.operation = switch (request.kind) {
                .set => c.HVT_CLIPBOARD_SET,
                .query => c.HVT_CLIPBOARD_QUERY,
                .packet => c.HVT_CLIPBOARD_PACKET,
            };
            result.info.data.clipboard.protocol = switch (request.protocol) {
                .osc52 => c.HVT_CLIPBOARD_OSC52,
                .kitty_5522 => c.HVT_CLIPBOARD_KITTY_5522,
            };
            result.info.data.clipboard.selection_len = @intCast(request.selection.len);
            result.payload = request.payload;
        },
        .notification => |request| {
            result.info.kind = c.HVT_REQUEST_NOTIFICATION;
            result.info.data.notification.command = request.command;
            result.info.data.notification.kind = switch (request.kind) {
                .message => c.HVT_NOTIFICATION_MESSAGE,
                .steal_focus => c.HVT_NOTIFICATION_STEAL_FOCUS,
                .request_attention => c.HVT_NOTIFICATION_REQUEST_ATTENTION,
            };
            result.payload = request.payload;
        },
        .pointer_shape => |request| {
            result.info.kind = c.HVT_REQUEST_POINTER_SHAPE;
            result.info.data.pointer_shape.reset_generation = request.reset_generation;
            result.info.data.pointer_shape.alternate_screen = @intFromBool(request.alternate_screen);
            result.info.data.pointer_shape.query_requested = @intFromBool(request.payload.len != 0 and request.payload[0] == '?');
            result.payload = request.payload;
        },
        .file_transfer => |request| {
            result.info.kind = c.HVT_REQUEST_FILE_TRANSFER;
            result.info.data.file_transfer.protocol = switch (request.protocol) {
                .iterm2_1337 => c.HVT_FILE_ITERM2_1337,
                .kitty_5113 => c.HVT_FILE_KITTY_5113,
            };
            result.payload = request.payload;
        },
        .drag_drop => |request| {
            result.info.kind = c.HVT_REQUEST_DRAG_DROP;
            result.info.data.drag_drop.kind = switch (request.kind) {
                .enable => c.HVT_DRAG_ENABLE,
                .disable => c.HVT_DRAG_DISABLE,
                .accept => c.HVT_DRAG_ACCEPT,
                .request => c.HVT_DRAG_REQUEST,
                .complete => c.HVT_DRAG_COMPLETE,
                .query => c.HVT_DRAG_QUERY,
                .continuation => c.HVT_DRAG_CONTINUATION,
                .unsupported => c.HVT_DRAG_UNSUPPORTED,
            };
            result.info.data.drag_drop.command = request.command;
            result.info.data.drag_drop.more = @intFromBool(request.more);
            result.info.data.drag_drop.remote = @intFromBool(request.remote);
            result.info.data.drag_drop.has_client_id = @intFromBool(request.client_id != null);
            result.info.data.drag_drop.has_operation = @intFromBool(request.operation != null);
            result.info.data.drag_drop.has_index = @intFromBool(request.index != null);
            result.info.data.drag_drop.client_id = request.client_id orelse 0;
            result.info.data.drag_drop.operation = request.operation orelse 0;
            result.info.data.drag_drop.index = request.index orelse 0;
            result.payload = request.payload;
        },
        .container => |request| {
            result.info.kind = c.HVT_REQUEST_CONTAINER;
            result.info.data.container.operation = switch (request.request) {
                .deiconify => c.HVT_CONTAINER_DEICONIFY,
                .iconify => c.HVT_CONTAINER_ICONIFY,
                .move => c.HVT_CONTAINER_MOVE,
                .resize_pixels => c.HVT_CONTAINER_RESIZE_PIXELS,
                .raise => c.HVT_CONTAINER_RAISE,
                .lower => c.HVT_CONTAINER_LOWER,
                .resize_rows => c.HVT_CONTAINER_RESIZE_ROWS,
                .resize_columns => c.HVT_CONTAINER_RESIZE_COLUMNS,
                .resize_cells => c.HVT_CONTAINER_RESIZE_CELLS,
                .report_state => c.HVT_CONTAINER_REPORT_STATE,
                .report_position => c.HVT_CONTAINER_REPORT_POSITION,
                .report_screen_cells => c.HVT_CONTAINER_REPORT_SCREEN_CELLS,
                .report_icon_title => c.HVT_CONTAINER_REPORT_ICON_TITLE,
            };
            switch (request.request) {
                .move => |position| {
                    result.info.data.container.x = position.x;
                    result.info.data.container.y = position.y;
                },
                .resize_pixels => |size| {
                    result.info.data.container.width = size.width;
                    result.info.data.container.height = size.height;
                },
                .resize_rows => |rows| result.info.data.container.rows = rows,
                .resize_columns => |columns| result.info.data.container.columns = switch (columns) {
                    .columns_80 => 80,
                    .columns_132 => 132,
                },
                .resize_cells => |size| {
                    result.info.data.container.rows = size.rows;
                    result.info.data.container.columns = size.cols;
                },
                else => {},
            }
        },
        .color_preference_query => result.info.kind = c.HVT_REQUEST_COLOR_PREFERENCE,
        .media_copy => |request| {
            result.info.kind = c.HVT_REQUEST_MEDIA_COPY;
            result.info.data.media_copy.parameter = request.request.parameter;
            result.info.data.media_copy.is_private = @intFromBool(request.request.private);
        },
        .bell => result.info.kind = c.HVT_REQUEST_BELL,
        .legacy_control => |request| {
            result.info.kind = c.HVT_REQUEST_LEGACY_CONTROL;
            result.info.data.legacy_control.operation = switch (request.kind) {
                .tek_point_plot => c.HVT_LEGACY_TEK_POINT_PLOT,
                .tek_graph => c.HVT_LEGACY_TEK_GRAPH,
                .tek_incremental_plot => c.HVT_LEGACY_TEK_INCREMENTAL_PLOT,
                .tek_alpha => c.HVT_LEGACY_TEK_ALPHA,
                .tek_copy => c.HVT_LEGACY_TEK_COPY,
                .tek_special_point_plot => c.HVT_LEGACY_TEK_SPECIAL_POINT_PLOT,
                .tek_write_thru_short_dashed => c.HVT_LEGACY_TEK_WRITE_THRU_SHORT_DASHED,
                .hp_memory_lock => c.HVT_LEGACY_HP_MEMORY_LOCK,
            };
        },
        .dcs => |request| {
            result.info.kind = c.HVT_REQUEST_DCS;
            result.info.data.dcs.operation = switch (request.kind) {
                .xtsettcap => c.HVT_DCS_XTSETTCAP,
                .decudk => c.HVT_DCS_DECUDK,
                .decaupss => c.HVT_DCS_DECAUPSS,
                .iterm_tmux_hook => c.HVT_DCS_ITERM_TMUX_HOOK,
                .iterm_ssh_hook => c.HVT_DCS_ITERM_SSH_HOOK,
                .iterm_tmux_wrap => c.HVT_DCS_ITERM_TMUX_WRAP,
                .kitty_remote_command => c.HVT_DCS_KITTY_REMOTE_COMMAND,
                .kitty_overlay_ready => c.HVT_DCS_KITTY_OVERLAY_READY,
                .kitty_result => c.HVT_DCS_KITTY_RESULT,
                .kitty_print => c.HVT_DCS_KITTY_PRINT,
                .kitty_echo => c.HVT_DCS_KITTY_ECHO,
                .kitty_ssh => c.HVT_DCS_KITTY_SSH,
                .kitty_askpass => c.HVT_DCS_KITTY_ASKPASS,
                .kitty_clone => c.HVT_DCS_KITTY_CLONE,
                .kitty_edit => c.HVT_DCS_KITTY_EDIT,
            };
            result.payload = request.payload;
        },
        .string_control => |request| {
            result.info.kind = c.HVT_REQUEST_STRING_CONTROL;
            result.info.data.string_control.operation = switch (request.kind) {
                .apc => c.HVT_STRING_APC,
                .pm => c.HVT_STRING_PM,
                .sos => c.HVT_STRING_SOS,
            };
            result.payload = request.payload;
        },
    }
    if (result.payload.len > c.HVT_MAX_REQUEST_PAYLOAD_BYTES) return error.RequestLimit;
    result.info.payload_len = @intCast(result.payload.len);
    return result;
}

/// Copies head facts only; no head returns kind NONE with the current terminal revision.
pub fn head(observation: *const Terminal.Observation, output: *Info) Error!void {
    output.* = std.mem.zeroes(Info);
    output.terminal_revision = observation.semanticSequence();
    const value = observation.consequenceHead() orelse return;
    output.* = (try project(value, observation.semanticSequence())).info;
}

/// Copies the complete exact-head payload or reports required bytes without a write.
/// Caller serializes owner mutation; no retained payload pointer crosses this boundary.
pub fn copyPayload(observation: *const Terminal.Observation, id: u64, output: []u8, required: *usize) Error!void {
    required.* = 0;
    const value = observation.consequenceHead() orelse return error.StaleRequest;
    if (value.id() != id) return error.StaleRequest;
    const projected = try project(value, observation.semanticSequence());
    required.* = projected.payload.len;
    if (output.len < projected.payload.len) return error.BufferTooSmall;
    @memcpy(output[0..projected.payload.len], projected.payload);
}

test "native request projection covers every canonical family with native typed fields" {
    const values = [_]Terminal.Consequence{
        .{ .clipboard = .{ .generation = 1, .selection = "c", .payload = "c;?", .kind = .query, .protocol = .osc52 } },
        .{ .notification = .{ .generation = 2, .kind = .request_attention, .command = 9, .payload = "attention" } },
        .{ .pointer_shape = .{ .generation = 3, .reset_generation = 7, .alternate_screen = true, .payload = "?default" } },
        .{ .file_transfer = .{ .generation = 4, .protocol = .kitty_5113, .payload = "packet" } },
        .{ .drag_drop = .{ .generation = 5, .kind = .request, .command = 'd', .client_id = 17, .more = true, .operation = 2, .index = 9, .remote = true, .payload = "mime" } },
        .{ .container = .{ .generation = 6, .request = .{ .resize_cells = .{ .rows = 99, .cols = 101 } } } },
        .{ .color_preference_query = .{ .id = 7 } },
        .{ .media_copy = .{ .generation = 8, .request = .{ .private = true, .parameter = 16 } } },
        .{ .bell = .{ .id = 9 } },
        .{ .legacy_control = .{ .generation = 10, .kind = .hp_memory_lock } },
        .{ .dcs = .{ .generation = 11, .kind = .iterm_ssh_hook, .payload = "raw" } },
        .{ .string_control = .{ .generation = 12, .kind = .pm, .payload = "raw" } },
    };
    for (values, 0..) |value, index| {
        const projected = try project(value, 42);
        try std.testing.expectEqual(@as(u64, index + 1), projected.info.occurrence_id);
        try std.testing.expectEqual(@as(u8, @intCast(index + 1)), projected.info.kind);
        try std.testing.expectEqual(@as(u64, 42), projected.info.terminal_revision);
        try std.testing.expectEqual(@as(u16, 0), projected.info._reserved);
        try std.testing.expectEqual(projected.payload.len, @as(usize, projected.info.payload_len));
    }
    const clipboard = (try project(values[0], 42)).info;
    try std.testing.expect(clipboard.reply_required == 1 and clipboard.data.clipboard.operation == c.HVT_CLIPBOARD_QUERY and clipboard.data.clipboard.selection_len == 1);
    const pointer = (try project(values[2], 42)).info;
    try std.testing.expect(pointer.reply_required == 0 and pointer.data.pointer_shape.query_requested == 1 and pointer.data.pointer_shape.alternate_screen == 1 and pointer.data.pointer_shape.reset_generation == 7);
    const drag = (try project(values[4], 42)).info.data.drag_drop;
    try std.testing.expect(drag.has_client_id == 1 and drag.has_operation == 1 and drag.has_index == 1 and drag.client_id == 17 and drag.operation == 2 and drag.index == 9 and drag.more == 1 and drag.remote == 1);
    const absent: Terminal.Consequence = .{ .drag_drop = .{ .generation = 13, .kind = .query, .command = 'q', .client_id = null, .more = false, .operation = null, .index = null, .remote = false, .payload = "" } };
    const absent_drag = (try project(absent, 42)).info.data.drag_drop;
    try std.testing.expect(absent_drag.has_client_id == 0 and absent_drag.has_operation == 0 and absent_drag.has_index == 0 and absent_drag.client_id == 0 and absent_drag.operation == 0 and absent_drag.index == 0 and absent_drag.more == 0 and absent_drag.remote == 0);
    const container = (try project(values[5], 42)).info.data.container;
    try std.testing.expect(container.operation == c.HVT_CONTAINER_RESIZE_CELLS and container.rows == 99 and container.columns == 101);
    try std.testing.expectEqual(@as(usize, 56), @sizeOf(Info));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(Info, "data"));
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(c.hvt_request_data));
}

test "native request copies preserve FIFO identity and distinguish mandatory from requested replies" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 8);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("\x1b]52;c;?\x07\x07")).stateChanged());
    var first: Info = undefined;
    try head(terminal.observation(), &first);
    try std.testing.expect(first.kind == c.HVT_REQUEST_CLIPBOARD and first.reply_required == 1);
    var payload: [32]u8 = undefined;
    payload[0] = 77;
    var required: usize = 99;
    try std.testing.expectError(error.StaleRequest, copyPayload(terminal.observation(), first.occurrence_id + 1, &payload, &required));
    try std.testing.expect(required == 0 and payload[0] == 77);
    try std.testing.expectError(error.BufferTooSmall, copyPayload(terminal.observation(), first.occurrence_id, payload[0..1], &required));
    try std.testing.expect(required == 3 and payload[0] == 77);
    try std.testing.expectError(error.ReplyRequired, terminal.consumeConsequence(first.occurrence_id));
    try copyPayload(terminal.observation(), first.occurrence_id, &payload, &required);
    try std.testing.expectEqualStrings("c;?", payload[0..required]);
    try std.testing.expect(try terminal.replyClipboard(first.occurrence_id, ""));
    try std.testing.expectEqualStrings("\x1b]52;c;\x1b\\", terminal.replyBytes());
    var next: Info = undefined;
    try head(terminal.observation(), &next);
    try std.testing.expect(next.kind == c.HVT_REQUEST_BELL and next.occurrence_id > first.occurrence_id);
    try terminal.consumeConsequence(next.occurrence_id);
    try head(terminal.observation(), &next);
    try std.testing.expect(next.kind == c.HVT_REQUEST_NONE and next.occurrence_id == 0);
    try std.testing.expectEqualStrings("c;?", payload[0..required]);
    try std.testing.expect((try terminal.feed("\x1b]22;?default\x07")).stateChanged());
    try head(terminal.observation(), &next);
    try std.testing.expect(next.kind == c.HVT_REQUEST_POINTER_SHAPE and next.reply_required == 0 and next.data.pointer_shape.query_requested == 1);
    try terminal.consumeConsequence(next.occurrence_id);
}

test "native request byte bound rejects before count narrowing" {
    const payload = try std.testing.allocator.alloc(u8, c.HVT_MAX_REQUEST_PAYLOAD_BYTES + 1);
    defer std.testing.allocator.free(payload);
    @memset(payload, 'a');
    const exact: Terminal.Consequence = .{ .clipboard = .{ .generation = 1, .selection = "", .payload = payload[0..c.HVT_MAX_REQUEST_PAYLOAD_BYTES], .kind = .set, .protocol = .osc52 } };
    try std.testing.expectEqual(@as(u32, c.HVT_MAX_REQUEST_PAYLOAD_BYTES), (try project(exact, 1)).info.payload_len);
    const excessive: Terminal.Consequence = .{ .clipboard = .{ .generation = 1, .selection = "", .payload = payload, .kind = .set, .protocol = .osc52 } };
    try std.testing.expectError(error.RequestLimit, project(excessive, 1));
}
