//! Stateful NDJSON transport for composing the frozen Howl wire.
//!
//! One process owns one real Howl client connection. The first output record is
//! the negotiated `welcome`. Each subsequent input line maps directly to one
//! existing wire request and its corresponding response. Connection-local state
//! such as resize leadership therefore remains visible instead of being hidden
//! behind one-shot commands.

const std = @import("std");
const protocol = @import("howl_session").protocol;
const wire = @import("wire.zig");
const observe = @import("observe.zig");

pub const maximum_request_line_bytes: usize = 64 * 1024;

const WelcomeRecord = struct {
    record: []const u8 = "welcome",
    version: u16,
    features: u64,
    client_id: protocol.ClientId,
};

const ResultRecord = struct {
    record: []const u8 = "result",
    request_kind: []const u8,
    code: []const u8,
};

const InteractionStateRecord = struct {
    record: []const u8 = "interaction_state",
    terminal_revision: u64,
    keyboard_action_mode: bool,
    auto_repeat: bool,
    newline_mode: bool,
    application_cursor_keys: bool,
    application_keypad: bool,
    meta_sends_escape: bool,
    report_key_up: bool,
    bracketed_paste: bool,
    focus_reporting: bool,
    termios_signals: bool,
    alternate_scroll: bool,
    paste_events: bool,
    inband_resize_notifications: bool,
    mouse_tracking: []const u8,
    mouse_protocol: []const u8,
    modify_other_keys: i8,
    kitty_keyboard_flags: u8,
    key_format_resource_4: u16,
    pointer_mode: u2,
};

pub fn run(init: std.process.Init, connection: *wire.Connection) !void {
    var stdout_buffer: [16 * 1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    try emit(&stdout.interface, WelcomeRecord{
        .version = connection.version,
        .features = connection.features,
        .client_id = connection.client_id,
    });
    try stdout.interface.flush();

    var stdin_buffer: [maximum_request_line_bytes]u8 = undefined;
    var stdin = std.Io.File.stdin().readerStreaming(init.io, &stdin_buffer);
    while (try stdin.interface.takeDelimiter('\n')) |line| {
        if (line.len == 0) continue;
        if (line.len > maximum_request_line_bytes) return error.RequestTooLarge;
        var parsed = std.json.parseFromSlice(std.json.Value, init.gpa, line, .{}) catch
            return error.InvalidRequest;
        defer parsed.deinit();
        if (parsed.value != .object) return error.InvalidRequest;
        try dispatch(connection, init.gpa, &stdout.interface, parsed.value.object);
        try stdout.interface.flush();
    }
}

fn dispatch(
    connection: *wire.Connection,
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    object: std.json.ObjectMap,
) !void {
    const request = try requiredString(object, "request");
    if (std.mem.eql(u8, request, "interaction_state")) {
        try onlyKeys(object, &.{"request"});
        if (connection.features & protocol.feature(.interaction_state) == 0)
            return error.InteractionStateUnsupported;
        try connection.send(.interaction_state, &.{});
        var frame = try connection.receive();
        defer frame.deinit();
        if (frame.kind != .interaction_state_snapshot) return error.UnexpectedFrame;
        const state = try protocol.decodeInteractionStateSnapshot(frame.payload);
        try emit(writer, InteractionStateRecord{
            .terminal_revision = state.terminal_revision,
            .keyboard_action_mode = state.keyboard_action_mode,
            .auto_repeat = state.auto_repeat,
            .newline_mode = state.newline_mode,
            .application_cursor_keys = state.application_cursor_keys,
            .application_keypad = state.application_keypad,
            .meta_sends_escape = state.meta_sends_escape,
            .report_key_up = state.report_key_up,
            .bracketed_paste = state.bracketed_paste,
            .focus_reporting = state.focus_reporting,
            .termios_signals = state.termios_signals,
            .alternate_scroll = state.alternate_scroll,
            .paste_events = state.paste_events,
            .inband_resize_notifications = state.inband_resize_notifications,
            .mouse_tracking = @tagName(state.mouse_tracking),
            .mouse_protocol = @tagName(state.mouse_protocol),
            .modify_other_keys = state.modify_other_keys,
            .kitty_keyboard_flags = state.kitty_keyboard_flags,
            .key_format_resource_4 = state.key_format_resource_4,
            .pointer_mode = state.pointer_mode,
        });
        return;
    }
    if (std.mem.eql(u8, request, "observe")) {
        try onlyKeys(object, &.{ "request", "after_revision", "history_offset" });
        const after_revision = try optionalUnsigned(u64, object, "after_revision", 0);
        const history_offset = try optionalUnsigned(u32, object, "history_offset", 0);
        var payload: [protocol.payload_bytes.observe]u8 = undefined;
        protocol.encodeObserve(&payload, .{
            .after_revision = after_revision,
            .history_offset = history_offset,
        });
        try connection.send(.observe, &payload);
        try observe.receiveAndEmitSnapshot(connection, allocator, writer);
        return;
    }
    if (std.mem.eql(u8, request, "input_bytes")) {
        try onlyKeys(object, &.{ "request", "bytes_hex" });
        const bytes = try decodeHexAlloc(allocator, try requiredString(object, "bytes_hex"));
        defer allocator.free(bytes);
        try sendBytesInput(connection, .bytes, bytes);
        return receiveResult(connection, writer, .input);
    }
    if (std.mem.eql(u8, request, "paste")) {
        try onlyKeys(object, &.{ "request", "text", "bytes_hex" });
        const text = object.get("text");
        const hex = object.get("bytes_hex");
        if ((text == null) == (hex == null)) return error.InvalidRequest;
        if (text) |value| {
            if (value != .string) return error.InvalidRequest;
            try sendBytesInput(connection, .paste, value.string);
        } else {
            const bytes = try decodeHexAlloc(allocator, try requiredString(object, "bytes_hex"));
            defer allocator.free(bytes);
            try sendBytesInput(connection, .paste, bytes);
        }
        return receiveResult(connection, writer, .input);
    }
    if (std.mem.eql(u8, request, "key")) {
        return keyRequest(connection, allocator, writer, object);
    }
    if (std.mem.eql(u8, request, "mouse")) {
        return mouseRequest(connection, writer, object);
    }
    if (std.mem.eql(u8, request, "focus")) {
        try onlyKeys(object, &.{ "request", "value" });
        const value_text = try requiredString(object, "value");
        const value: protocol.InputFocus = if (std.mem.eql(u8, value_text, "in"))
            .in
        else if (std.mem.eql(u8, value_text, "out"))
            .out
        else
            return error.InvalidRequest;
        var body: [protocol.typed_input.focus_bytes]u8 = undefined;
        protocol.encodeFocusInput(&body, value);
        var payload: [1 + protocol.typed_input.focus_bytes]u8 = undefined;
        payload[0] = @backingInt(protocol.InputKind.focus);
        @memcpy(payload[1..], &body);
        try connection.send(.input, &payload);
        return receiveResult(connection, writer, .input);
    }
    if (std.mem.eql(u8, request, "assign_leader")) {
        try onlyKeys(object, &.{ "request", "client_id" });
        const client_id = try requiredUnsigned(protocol.ClientId, object, "client_id");
        var payload: [protocol.payload_bytes.assign_leader]u8 = undefined;
        protocol.encodeAssignLeader(&payload, .{ .client_id = client_id });
        try connection.send(.assign_leader, &payload);
        return receiveResult(connection, writer, .assign_leader);
    }
    if (std.mem.eql(u8, request, "resize")) {
        try onlyKeys(object, &.{ "request", "rows", "columns" });
        const rows = try requiredUnsigned(u16, object, "rows");
        const columns = try requiredUnsigned(u16, object, "columns");
        var payload: [protocol.payload_bytes.resize]u8 = undefined;
        protocol.encodeResize(&payload, .{ .rows = rows, .columns = columns });
        try connection.send(.resize, &payload);
        return receiveResult(connection, writer, .resize);
    }
    if (std.mem.eql(u8, request, "signal")) {
        try onlyKeys(object, &.{ "request", "value" });
        const raw = try requiredUnsigned(u8, object, "value");
        const signal: protocol.Signal = switch (raw) {
            1 => .hangup,
            2 => .interrupt,
            3 => .resize_notify,
            9 => .kill,
            15 => .terminate,
            else => return error.InvalidRequest,
        };
        var payload: [protocol.payload_bytes.signal]u8 = undefined;
        protocol.encodeSignal(&payload, signal);
        try connection.send(.signal, &payload);
        return receiveResult(connection, writer, .signal);
    }
    return error.InvalidRequest;
}

fn keyRequest(
    connection: *wire.Connection,
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    object: std.json.ObjectMap,
) !void {
    try onlyKeys(object, &.{
        "request",
        "key_kind",
        "key_value",
        "action",
        "modifiers",
        "shifted",
        "alternate",
        "legacy_bytes_hex",
        "text",
    });
    const kind_text = try requiredString(object, "key_kind");
    const kind: protocol.InputKeyKind = if (std.mem.eql(u8, kind_text, "named"))
        .named
    else if (std.mem.eql(u8, kind_text, "unicode"))
        .unicode
    else
        return error.InvalidRequest;
    const action_text = try requiredString(object, "action");
    const action: protocol.InputKeyAction = if (std.mem.eql(u8, action_text, "press"))
        .press
    else if (std.mem.eql(u8, action_text, "repeat"))
        .repeat
    else if (std.mem.eql(u8, action_text, "release"))
        .release
    else
        return error.InvalidRequest;
    const legacy = if (object.get("legacy_bytes_hex")) |value| blk: {
        if (value != .string) return error.InvalidRequest;
        break :blk try decodeHexAlloc(allocator, value.string);
    } else try allocator.alloc(u8, 0);
    defer allocator.free(legacy);
    const text = if (object.get("text")) |value| blk: {
        if (value != .string) return error.InvalidRequest;
        break :blk value.string;
    } else "";
    const input = protocol.KeyInput{
        .kind = kind,
        .key_value = try requiredUnsigned(u32, object, "key_value"),
        .action = action,
        .modifiers = try optionalUnsigned(u8, object, "modifiers", 0),
        .shifted = try optionalMaybeUnsigned(u32, object, "shifted"),
        .alternate = try optionalMaybeUnsigned(u32, object, "alternate"),
        .legacy_text = legacy,
        .text = text,
    };
    const maximum_body = protocol.typed_input.key_header_bytes +
        protocol.typed_input.maximum_legacy_key_bytes +
        protocol.typed_input.maximum_key_text_bytes;
    var payload: [1 + maximum_body]u8 = undefined;
    payload[0] = @backingInt(protocol.InputKind.key);
    const body = try protocol.encodeKeyInput(payload[1..], input);
    try connection.send(.input, payload[0 .. 1 + body.len]);
    return receiveResult(connection, writer, .input);
}

fn mouseRequest(
    connection: *wire.Connection,
    writer: *std.Io.Writer,
    object: std.json.ObjectMap,
) !void {
    try onlyKeys(object, &.{
        "request",
        "kind",
        "button",
        "modifiers",
        "buttons_down",
        "row",
        "column",
        "pixel_x",
        "pixel_y",
    });
    const kind_text = try requiredString(object, "kind");
    const kind: protocol.InputMouseKind = if (std.mem.eql(u8, kind_text, "press"))
        .press
    else if (std.mem.eql(u8, kind_text, "release"))
        .release
    else if (std.mem.eql(u8, kind_text, "move"))
        .move
    else if (std.mem.eql(u8, kind_text, "wheel"))
        .wheel
    else
        return error.InvalidRequest;
    const button_text = try requiredString(object, "button");
    const button: protocol.InputMouseButton = if (std.mem.eql(u8, button_text, "none"))
        .none
    else if (std.mem.eql(u8, button_text, "left"))
        .left
    else if (std.mem.eql(u8, button_text, "middle"))
        .middle
    else if (std.mem.eql(u8, button_text, "right"))
        .right
    else if (std.mem.eql(u8, button_text, "wheel_up"))
        .wheel_up
    else if (std.mem.eql(u8, button_text, "wheel_down"))
        .wheel_down
    else
        return error.InvalidRequest;
    const pixel_x = try optionalMaybeUnsigned(u32, object, "pixel_x");
    const pixel_y = try optionalMaybeUnsigned(u32, object, "pixel_y");
    if ((pixel_x == null) != (pixel_y == null)) return error.InvalidRequest;
    const row_raw = try requiredInteger(object, "row");
    const row = std.math.cast(i32, row_raw) orelse return error.InvalidRequest;
    const input = protocol.MouseInput{
        .kind = kind,
        .button = button,
        .modifiers = try optionalUnsigned(u8, object, "modifiers", 0),
        .buttons_down = try optionalUnsigned(u8, object, "buttons_down", 0),
        .row = row,
        .column = try requiredUnsigned(u16, object, "column"),
        .pixel_x = pixel_x,
        .pixel_y = pixel_y,
    };
    var body: [protocol.typed_input.mouse_bytes]u8 = undefined;
    try protocol.encodeMouseInput(&body, input);
    var payload: [1 + protocol.typed_input.mouse_bytes]u8 = undefined;
    payload[0] = @backingInt(protocol.InputKind.mouse);
    @memcpy(payload[1..], &body);
    try connection.send(.input, &payload);
    return receiveResult(connection, writer, .input);
}

fn sendBytesInput(
    connection: *wire.Connection,
    kind: protocol.InputKind,
    bytes: []const u8,
) !void {
    if (kind != .bytes and kind != .paste) return error.InvalidRequest;
    if (bytes.len + 1 > protocol.maximum_request_payload_bytes) return error.RequestTooLarge;
    const payload = try connection.allocator.alloc(u8, bytes.len + 1);
    defer connection.allocator.free(payload);
    payload[0] = @backingInt(kind);
    @memcpy(payload[1..], bytes);
    try connection.send(.input, payload);
}

fn receiveResult(
    connection: *wire.Connection,
    writer: *std.Io.Writer,
    expected: protocol.Kind,
) !void {
    var frame = try connection.receive();
    defer frame.deinit();
    if (frame.kind != .result) return error.UnexpectedFrame;
    const result = try protocol.decodeResult(frame.payload);
    if (result.request_kind != expected) return error.UnexpectedFrame;
    try emit(writer, ResultRecord{
        .request_kind = @tagName(result.request_kind),
        .code = @tagName(result.code),
    });
}

fn emit(writer: *std.Io.Writer, value: anytype) !void {
    try std.json.Stringify.value(value, .{}, writer);
    try writer.writeByte('\n');
}

fn onlyKeys(object: std.json.ObjectMap, allowed: []const []const u8) error{InvalidRequest}!void {
    var iterator = object.iterator();
    while (iterator.next()) |entry| {
        var found = false;
        for (allowed) |name| {
            if (std.mem.eql(u8, entry.key_ptr.*, name)) {
                found = true;
                break;
            }
        }
        if (!found) return error.InvalidRequest;
    }
}

fn requiredString(object: std.json.ObjectMap, name: []const u8) error{InvalidRequest}![]const u8 {
    const value = object.get(name) orelse return error.InvalidRequest;
    if (value != .string or value.string.len == 0) return error.InvalidRequest;
    return value.string;
}

fn requiredInteger(object: std.json.ObjectMap, name: []const u8) error{InvalidRequest}!i64 {
    const value = object.get(name) orelse return error.InvalidRequest;
    if (value != .integer) return error.InvalidRequest;
    return value.integer;
}

fn requiredUnsigned(comptime T: type, object: std.json.ObjectMap, name: []const u8) error{InvalidRequest}!T {
    return std.math.cast(T, try requiredInteger(object, name)) orelse error.InvalidRequest;
}

fn optionalUnsigned(
    comptime T: type,
    object: std.json.ObjectMap,
    name: []const u8,
    fallback: T,
) error{InvalidRequest}!T {
    const value = object.get(name) orelse return fallback;
    if (value != .integer) return error.InvalidRequest;
    return std.math.cast(T, value.integer) orelse error.InvalidRequest;
}

fn optionalMaybeUnsigned(
    comptime T: type,
    object: std.json.ObjectMap,
    name: []const u8,
) error{InvalidRequest}!?T {
    const value = object.get(name) orelse return null;
    if (value != .integer) return error.InvalidRequest;
    return std.math.cast(T, value.integer) orelse error.InvalidRequest;
}

fn decodeHexAlloc(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    if (text.len % 2 != 0) return error.InvalidRequest;
    const output = try allocator.alloc(u8, text.len / 2);
    errdefer allocator.free(output);
    for (output, 0..) |*slot, index| {
        const high = hexNibble(text[index * 2]) orelse return error.InvalidRequest;
        const low = hexNibble(text[index * 2 + 1]) orelse return error.InvalidRequest;
        slot.* = (high << 4) | low;
    }
    return output;
}

fn hexNibble(byte: u8) ?u8 {
    return switch (byte) {
        '0'...'9' => byte - '0',
        'a'...'f' => byte - 'a' + 10,
        'A'...'F' => byte - 'A' + 10,
        else => null,
    };
}

test "hex byte transport is exact and rejects malformed input" {
    const bytes = try decodeHexAlloc(std.testing.allocator, "001bff41");
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0x1b, 0xff, 'A' }, bytes);
    try std.testing.expectError(error.InvalidRequest, decodeHexAlloc(std.testing.allocator, "0"));
    try std.testing.expectError(error.InvalidRequest, decodeHexAlloc(std.testing.allocator, "gg"));
}
