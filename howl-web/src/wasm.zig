//! Experimental browser byte pump. Session protocol and rich decoding stay shared.
const std = @import("std");
const p = @import("howl_session").protocol;
const rich = @import("howl_client").rich;
const canvas = @import("howl_render").canvas;

// A deliberately coarse canary budget, not the final terminal-renderer budget.
var input: [32768]u8 = undefined;
var packet: [p.header_bytes + p.maximum_payload_bytes]u8 = undefined;
var used: usize = 0;
var needed: usize = p.header_bytes;
var transcript: [p.maximum_snapshot_bytes]u8 = undefined;
var transcript_len: usize = 0;
var arena: [20 * 1024 * 1024]u8 = undefined;
var projection: [65536]u8 = undefined;
var projection_len: usize = 0;
var output: [p.header_bytes + 1 + 4096]u8 = undefined;
var output_len: usize = 0;
var identity: u64 = 0;
var revision: u64 = 0;
var terminal_revision: u64 = 0;
var rows: u32 = 0;
var columns: u32 = 0;
var failure: []const u8 = "";
const ControlOperation = enum { none, input, assign_resize, resize };
var control_operation: ControlOperation = .none;
var pending_resize_rows: u16 = 0;
var pending_resize_columns: u16 = 0;
// 0 closed, 1 awaiting welcome, 2 attached, 3 observing, 4 snapshot ready,
// 5 awaiting a control result, 6 control acknowledged, 99 terminal protocol error.
var phase: u32 = 0;

export fn hw_input_ptr() usize {
    return @intFromPtr(&input);
}
export fn hw_input_capacity() usize {
    return input.len;
}
export fn hw_output_ptr() usize {
    return @intFromPtr(&output);
}
export fn hw_output_len() usize {
    return output_len;
}
export fn hw_text_ptr() usize {
    return @intFromPtr(&projection);
}
export fn hw_text_len() usize {
    return projection_len;
}
export fn hw_snapshot_ptr() usize {
    return @intFromPtr(&transcript);
}
export fn hw_snapshot_len() usize {
    return transcript_len;
}
export fn hw_error_ptr() usize {
    return @intFromPtr(failure.ptr);
}
export fn hw_error_len() usize {
    return failure.len;
}
export fn hw_phase() u32 {
    return phase;
}
export fn hw_identity() u64 {
    return identity;
}
export fn hw_revision() u64 {
    return revision;
}
export fn hw_terminal_revision() u64 {
    return terminal_revision;
}
export fn hw_rows() u32 {
    return rows;
}
export fn hw_columns() u32 {
    return columns;
}
export fn hw_control_ready() u32 {
    return @intFromBool(controlReady());
}

fn fail(message: []const u8) u32 {
    failure = message;
    phase = 99;
    output_len = 0;
    return 0;
}

fn queue(kind: p.Kind, payload: []const u8) bool {
    if (payload.len > output.len - p.header_bytes) return false;
    p.encodeHeader(output[0..p.header_bytes], .{ .kind = kind, .payload_len = @intCast(payload.len) }) catch return false;
    @memcpy(output[p.header_bytes..][0..payload.len], payload);
    output_len = p.header_bytes + payload.len;
    return true;
}

fn controlReady() bool {
    return control_operation == .none and (phase == 2 or phase == 4 or phase == 6);
}

fn beginInput(payload: []const u8) u32 {
    if (!controlReady()) return 0;
    if (!queue(.input, payload)) return fail("InputEncodingFailed");
    control_operation = .input;
    phase = 5;
    return 1;
}

fn sendBytesInput(kind: p.InputKind, length: usize, validate_utf8: bool) u32 {
    if (!controlReady() or length == 0 or length > 4096) return 0;
    if (validate_utf8 and !std.unicode.utf8ValidateSlice(input[0..length])) return 0;
    var payload: [4097]u8 = undefined;
    payload[0] = @backingInt(kind);
    @memcpy(payload[1..][0..length], input[0..length]);
    return beginInput(payload[0 .. length + 1]);
}

export fn hw_reset() u32 {
    used = 0;
    needed = p.header_bytes;
    transcript_len = 0;
    projection_len = 0;
    identity = 0;
    revision = 0;
    terminal_revision = 0;
    rows = 0;
    columns = 0;
    failure = "";
    control_operation = .none;
    pending_resize_rows = 0;
    pending_resize_columns = 0;
    phase = 1;
    if (!queue(.hello, &.{})) return fail("HelloEncodingFailed");
    return 1;
}

export fn hw_observe(immediate: u32) u32 {
    if (!controlReady()) return 0;
    var payload: [p.payload_bytes.observe]u8 = undefined;
    p.encodeObserve(&payload, .{ .after_revision = if (immediate != 0) 0 else revision });
    if (!queue(.observe, &payload)) return fail("ObserveEncodingFailed");
    transcript_len = 0;
    phase = 3;
    return 1;
}

// Host writes committed UTF-8 bytes into input, then requests one serialized send.
// Terminal escape encoding remains exclusively on the session/VT side.
export fn hw_send_text(length: usize) u32 {
    return sendBytesInput(.bytes, length, true);
}

export fn hw_send_paste(length: usize) u32 {
    return sendBytesInput(.paste, length, false);
}

export fn hw_send_named_key(key_value: u32, action_value: u32, modifiers: u32) u32 {
    if (!controlReady() or key_value < 1 or key_value > 58 or
        action_value < 1 or action_value > 3 or modifiers > std.math.maxInt(u8))
        return 0;
    var body: [p.typed_input.key_header_bytes]u8 = undefined;
    const encoded = p.encodeKeyInput(&body, .{
        .kind = .named,
        .key_value = key_value,
        .action = @fromBackingInt(@as(u8, @intCast(action_value))),
        .modifiers = @intCast(modifiers),
    }) catch return 0;
    var payload: [1 + p.typed_input.key_header_bytes]u8 = undefined;
    payload[0] = @backingInt(p.InputKind.key);
    @memcpy(payload[1..][0..encoded.len], encoded);
    return beginInput(payload[0 .. 1 + encoded.len]);
}

export fn hw_send_unicode_key(scalar: u32, action_value: u32, modifiers: u32) u32 {
    if (!controlReady() or action_value < 1 or action_value > 3 or modifiers > std.math.maxInt(u8)) return 0;
    var body: [p.typed_input.key_header_bytes]u8 = undefined;
    const encoded = p.encodeKeyInput(&body, .{
        .kind = .unicode,
        .key_value = scalar,
        .action = @fromBackingInt(@as(u8, @intCast(action_value))),
        .modifiers = @intCast(modifiers),
    }) catch return 0;
    var payload: [1 + p.typed_input.key_header_bytes]u8 = undefined;
    payload[0] = @backingInt(p.InputKind.key);
    @memcpy(payload[1..][0..encoded.len], encoded);
    return beginInput(payload[0 .. 1 + encoded.len]);
}

export fn hw_send_focus(focus_value: u32) u32 {
    if (!controlReady() or focus_value < 1 or focus_value > 2) return 0;
    var body: [p.typed_input.focus_bytes]u8 = undefined;
    p.encodeFocusInput(&body, @fromBackingInt(@as(u8, @intCast(focus_value))));
    const payload = [1 + p.typed_input.focus_bytes]u8{ @backingInt(p.InputKind.focus), body[0] };
    return beginInput(&payload);
}

export fn hw_send_resize(resize_rows: u32, resize_columns: u32) u32 {
    if (!controlReady() or resize_rows == 0 or resize_rows > std.math.maxInt(u16) or
        resize_columns == 0 or resize_columns > std.math.maxInt(u16))
        return 0;
    var payload: [p.payload_bytes.assign_leader]u8 = undefined;
    p.encodeAssignLeader(&payload, .{ .client_id = identity });
    if (!queue(.assign_leader, &payload)) return fail("ResizeLeaderEncodingFailed");
    pending_resize_rows = @intCast(resize_rows);
    pending_resize_columns = @intCast(resize_columns);
    control_operation = .assign_resize;
    phase = 5;
    return 1;
}

fn decodeSnapshot() rich.Error!void {
    var memory = std.heap.FixedBufferAllocator.init(&arena);
    var snapshot = try rich.decodeFrames(memory.allocator(), transcript[0..transcript_len]);
    defer snapshot.deinit();
    // Diagnostic text only. Real glyph rendering will consume the rich view.
    var length: usize = 0;
    for (snapshot.rows) |row| {
        for (row.cells) |cell| {
            if (cell.scalars.len == 0) {
                if (length == projection.len) return error.SnapshotTooLarge;
                projection[length] = ' ';
                length += 1;
            }
            for (cell.scalars) |scalar| {
                if (scalar > 0x10ffff) return error.InvalidSnapshot;
                var bytes: [4]u8 = undefined;
                const count = std.unicode.utf8Encode(@intCast(scalar), &bytes) catch return error.InvalidSnapshot;
                if (count > projection.len - length) return error.SnapshotTooLarge;
                @memcpy(projection[length..][0..count], bytes[0..count]);
                length += count;
            }
        }
        if (length == projection.len) return error.SnapshotTooLarge;
        projection[length] = '\n';
        length += 1;
    }
    projection_len = length;
    revision = snapshot.begin.revision;
    terminal_revision = snapshot.begin.terminal_revision;
    rows = snapshot.begin.rows;
    columns = snapshot.begin.columns;
}

fn acceptFrame() u32 {
    const header = p.decodeHeader(packet[0..p.header_bytes]) catch |err| return fail(@errorName(err));
    const payload = packet[p.header_bytes..needed];
    switch (phase) {
        1 => {
            if (header.kind != .welcome) return fail("ExpectedWelcome");
            const welcome = p.decodeWelcome(payload) catch |err| return fail(@errorName(err));
            if (welcome.client_id == 0) return fail("ZeroIdentity");
            identity = welcome.client_id;
            phase = 2;
        },
        3 => {
            if ((transcript_len == 0 and header.kind != .snapshot_begin) or
                (transcript_len != 0 and header.kind != .snapshot_data and header.kind != .snapshot_end))
                return fail("UnexpectedSnapshotFrame");
            if (needed > transcript.len - transcript_len) return fail("SnapshotTooLarge");
            @memcpy(transcript[transcript_len..][0..needed], packet[0..needed]);
            transcript_len += needed;
            if (header.kind == .snapshot_end) {
                decodeSnapshot() catch |err| {
                    projection_len = 0;
                    return fail(@errorName(err));
                };
                phase = 4;
            }
        },
        5 => {
            if (header.kind != .result) return fail("ExpectedControlResult");
            const result = p.decodeResult(payload) catch |err| return fail(@errorName(err));
            switch (control_operation) {
                .input => {
                    if (result.request_kind != .input or result.code != .ok) return fail("InputRejected");
                    control_operation = .none;
                    phase = 6;
                },
                .assign_resize => {
                    if (result.request_kind != .assign_leader or result.code != .ok) return fail("ResizeLeaderRejected");
                    var resize_payload: [p.payload_bytes.resize]u8 = undefined;
                    p.encodeResize(&resize_payload, .{
                        .rows = pending_resize_rows,
                        .columns = pending_resize_columns,
                    });
                    if (!queue(.resize, &resize_payload)) return fail("ResizeEncodingFailed");
                    control_operation = .resize;
                    return 2;
                },
                .resize => {
                    if (result.request_kind != .resize or result.code != .ok) return fail("ResizeRejected");
                    pending_resize_rows = 0;
                    pending_resize_columns = 0;
                    control_operation = .none;
                    phase = 6;
                },
                .none => return fail("MissingControlOperation"),
            }
        },
        else => return fail("UnsolicitedFrame"),
    }
    return 1;
}

// WebSocket messages need not coincide with Howl frames, even at the header.
export fn hw_feed(length: usize) u32 {
    if (phase == 0 or phase == 99 or length > input.len) return 0;
    var offset: usize = 0;
    while (offset < length) {
        const count = @min(length - offset, needed - used);
        @memcpy(packet[used..][0..count], input[offset..][0..count]);
        offset += count;
        used += count;
        if (used != needed) continue;
        if (needed == p.header_bytes) {
            const header = p.decodeHeader(packet[0..p.header_bytes]) catch |err| return fail(@errorName(err));
            needed = p.header_bytes + header.payload_len;
            if (used != needed) continue;
        }
        const accepted = acceptFrame();
        if (accepted == 0) return 0;
        used = 0;
        needed = p.header_bytes;
        if (accepted == 2) {
            if (offset != length) return fail("ControlFollowupRequired");
            return 2;
        }
    }
    return 1;
}

export fn hw_finish() u32 {
    if (phase == 99) return 0;
    if (used != 0 or phase == 1 or phase == 3 or phase == 5) return fail("TruncatedResponse");
    control_operation = .none;
    pending_resize_rows = 0;
    pending_resize_columns = 0;
    phase = 0;
    output_len = 0;
    return 1;
}

// Actual shared Composer operations, not a compile-only import or glyph claim.
export fn hw_canvas_check() u32 {
    var memory = std.heap.FixedBufferAllocator.init(&arena);
    var composer = canvas.Composer.init(memory.allocator(), .{
        .sources = 1,
        .retained_resources = 1,
        .retained_commands = 4,
        .retained_pixel_bytes = 64,
        .composition_sources = 1,
        .candidate_resources = 1,
        .candidate_commands = 4,
        .candidate_pixel_bytes = 64,
    }) catch return 1;
    defer composer.deinit();
    const source = composer.registerSource() catch return 2;
    const inputs = [_]canvas.Input{.{ .solid = .{
        .rect = .{ .x = -4, .y = 2, .width = 20, .height = 10 },
        .clip = .{ .x = 0, .y = 0, .width = 12, .height = 12 },
        .color = .{ .r = 20, .g = 180, .b = 255, .a = 255 },
    } }};
    composer.apply(source, .{ .revision = @fromBackingInt(1), .uploads = &.{}, .removals = &.{}, .commands = &inputs }) catch return 3;
    const placements = [_]canvas.Composer.Placement{.{
        .source = source,
        .origin = .{ .x = 0, .y = 0 },
        .clip = .{ .x = 0, .y = 0, .width = 12, .height = 12 },
    }};
    composer.setComposition(.{ .surface = .{ .width = 12, .height = 12 }, .sources = &placements }) catch return 4;
    var commands: [4]canvas.Command = undefined;
    const frame = composer.frame(&.{}, .{ .uploads = &.{}, .removals = &.{}, .commands = &commands, .pixels = &.{} }) catch return 5;
    if (frame.commands.len != 1) return 6;
    const rect = frame.commands[0].solid.rect;
    return if (rect.x == 0 and rect.y == 2 and rect.width == 12 and rect.height == 10) 0 else 7;
}
