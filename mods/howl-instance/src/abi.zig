//! C exports for the artifact-owned Instance contract. Zig hosts reuse native helpers without emitting these exports.
const std = @import("std");
const builtin = @import("builtin");
const instance = @import("howl_instance");
const native = @import("instance_native");
const vt = native.vt;
const c = native.c;
const Instance = native.Instance;
const InputError = native.InputError;
const sendNamedKey = native.sendNamedKey;
const sendUnicodeKey = native.sendUnicodeKey;
const sendMouse = native.sendMouse;
const sendFocus = native.sendFocus;
const heap = std.heap.c_allocator;

// zig-audit: acknowledge anytype
// reason: This private conversion accepts only matching C/native opaque handle pointers at exact exported sites.
fn convert(comptime T: type, value: anytype) T {
    // zig-audit: acknowledge ptr_cast
    // reason: Both handles name the exact local Instance allocation; no records or headless specializations are reinterpreted.
    // zig-audit: acknowledge align_cast
    // reason: The live constructor-owned opaque pointer retains the native owner alignment.
    return @ptrCast(@alignCast(value));
}
const Error = InputError || instance.InitError || instance.ResizeError || instance.ServiceError;
fn status(err: Error) u32 {
    if (comptime builtin.os.tag != .linux) return c.HI_UNSUPPORTED;
    return switch (err) {
        error.OutOfMemory => c.HI_OUT_OF_MEMORY,
        error.InvalidArgument, error.InvalidDimensions, error.InvalidEnvironment, error.InvalidUtf8, error.InvalidText => c.HI_INVALID_ARGUMENT,
        error.EnvironmentByteLimit, error.EnvironmentCountLimit, error.WriteQueueFull, error.LengthOverflow, error.KeyTextLimit, error.ReplyLimit, error.ScalarCapacity, error.ConsequenceLimit, error.ConsequencePressure, error.PropertyLimit, error.ParsedEventLimit => c.HI_RESOURCE_LIMIT,
        error.UnsupportedPlatform => c.HI_UNSUPPORTED,
        error.WriteFailed, error.WouldBlock, error.EndOfStream, error.ReadFailed, error.NotStarted, error.ForegroundGroupFailed, error.SignalFailed, error.TermiosQueryFailed, error.AlreadyStarted, error.ChildCwdFailed, error.ChildExecFailed, error.ChildSessionFailed, error.ChildStdioFailed, error.ForkFailed, error.LaunchStatusFailed, error.LaunchStatusPipeFailed, error.MasterConfigureFailed, error.OpenPtyFailed, error.ShellUnavailable, error.ResizeFailed, error.Interrupted, error.ChildClosed, error.ObserveFailed, error.StaleClipboardRequest, error.StaleColorPreferenceQuery, error.StaleContainerRequest, error.ContainerReplyMismatch, error.StalePointerShape, error.PointerShapeReplyMismatch => c.HI_OPERATION_FAILED,
    };
}
fn bytes(ptr: [*c]const u8, len: usize, maximum: usize) ?[]const u8 {
    if (len > maximum) return null;
    if (ptr != null) return ptr[0..len];
    return if (len == 0) "" else null;
}
fn launchBytes(value: c.hi_bytes, maximum: usize) ?[]const u8 {
    const text = bytes(value.data, value.len, maximum) orelse return null;
    if (std.mem.indexOfScalar(u8, text, 0) != null) return null;
    return text;
}
/// Reports the version of the owned native contract.
pub export fn hi_abi_version() u32 {
    return c.HI_ABI_VERSION;
}

/// Copies bounded launch/environment before publishing one canonical owner.
pub export fn hi_create(version: u32, request: ?*const c.hi_launch, out: ?*?*c.hi_instance) u32 {
    if (version != c.HI_ABI_VERSION) return c.HI_VERSION_MISMATCH;
    const launch = request orelse return c.HI_INVALID_ARGUMENT;
    const slot = out orelse return c.HI_INVALID_ARGUMENT;
    if (slot.* != null or launch.reserved != 0) return c.HI_INVALID_ARGUMENT;
    if (comptime builtin.os.tag != .linux) return c.HI_UNSUPPORTED;
    const shell = launchBytes(launch.shell, 4096) orelse return c.HI_INVALID_ARGUMENT;
    const command = launchBytes(launch.command, 64 * 1024) orelse return c.HI_INVALID_ARGUMENT;
    const cwd = launchBytes(launch.cwd, 4096) orelse return c.HI_INVALID_ARGUMENT;
    if (shell.len == 0 or launch.rows == 0 or launch.columns == 0 or
        launch.cell_width == 0 or launch.cell_height == 0) return c.HI_INVALID_ARGUMENT;
    if (launch.environment_count > 1024) return c.HI_RESOURCE_LIMIT;
    if (launch.environment_count != 0 and launch.environment == null) return c.HI_INVALID_ARGUMENT;
    var count: usize = 0;
    var input_bytes: usize = 0;
    // Reserve exact canonical identity entries including terminators.
    var total: usize = "TERM=xterm-256color".len + 1 + "COLORTERM=truecolor".len + 1;
    for (0..launch.environment_count) |index| {
        const entry = launchBytes(launch.environment[index], 1024 * 1024) orelse return c.HI_INVALID_ARGUMENT;
        input_bytes = std.math.add(usize, input_bytes, entry.len + 1) catch return c.HI_RESOURCE_LIMIT;
        if (input_bytes > 1024 * 1024) return c.HI_RESOURCE_LIMIT;
        const equals = std.mem.indexOfScalar(u8, entry, '=') orelse return c.HI_INVALID_ARGUMENT;
        if (equals == 0) return c.HI_INVALID_ARGUMENT;
        for (0..index) |previous| {
            const earlier = launchBytes(launch.environment[previous], 1024 * 1024) orelse return c.HI_INVALID_ARGUMENT;
            const end = std.mem.indexOfScalar(u8, earlier, '=') orelse return c.HI_INVALID_ARGUMENT;
            if (std.mem.eql(u8, entry[0..equals], earlier[0..end])) return c.HI_INVALID_ARGUMENT;
        }
        if (std.mem.eql(u8, entry[0..equals], "TERM") or std.mem.eql(u8, entry[0..equals], "COLORTERM")) continue;
        count += 1;
        total = std.math.add(usize, total, entry.len + 1) catch return c.HI_RESOURCE_LIMIT;
        if (total > 1024 * 1024) return c.HI_RESOURCE_LIMIT;
    }
    if (count > 1022) return c.HI_RESOURCE_LIMIT;
    const entries = heap.allocSentinel(?[*:0]const u8, launch.environment_count, null) catch return c.HI_OUT_OF_MEMORY;
    defer heap.free(entries);
    var copied: usize = 0;
    defer for (entries[0..copied]) |entry| heap.free(std.mem.span(entry.?));
    for (0..launch.environment_count) |index| {
        const entry = launchBytes(launch.environment[index], 1024 * 1024) orelse return c.HI_INVALID_ARGUMENT;
        const copy = heap.dupeSentinel(u8, entry, 0) catch return c.HI_OUT_OF_MEMORY;
        entries[index] = copy.ptr;
        copied += 1;
    }
    const value = instance.init(heap, .{ .block = .{ .slice = entries } }, .{
        .shell = shell,
        .command = if (command.len == 0) null else command,
        .cwd = if (cwd.len == 0) null else cwd,
        .rows = launch.rows,
        .columns = launch.columns,
        .history_rows = launch.history_rows,
        .cell_pixel_width = launch.cell_width,
        .cell_pixel_height = launch.cell_height,
    }) catch |err| return status(err);
    slot.* = convert(*c.hi_instance, value);
    return c.HI_OK;
}
/// Releases a plain native owner; null is a successful no-op.
pub export fn hi_destroy(out: ?*?*c.hi_instance) u32 {
    const slot = out orelse return c.HI_INVALID_ARGUMENT;
    const raw = slot.* orelse return c.HI_OK;
    const value = convert(*Instance, raw);
    // Presented owners are not admitted by the version-1 lifecycle yet.
    if (instance.presented(value)) return c.HI_UNSUPPORTED;
    slot.* = null;
    instance.deinit(value);
    return c.HI_OK;
}
/// Admits copied child input in canonical order.
pub export fn hi_send_text(raw: ?*c.hi_instance, ptr: [*c]const u8, len: usize) u32 {
    const value = raw orelse return c.HI_INVALID_ARGUMENT;
    const text = bytes(ptr, len, 64 * 1024) orelse return c.HI_INVALID_ARGUMENT;
    instance.input(convert(*Instance, value), .{ .bytes = text }) catch |err| return status(err);
    return c.HI_OK;
}
/// Admits one bounded semantic paste through canonical VT encoding.
pub export fn hi_send_paste(raw: ?*c.hi_instance, ptr: [*c]const u8, len: usize) u32 {
    const value = raw orelse return c.HI_INVALID_ARGUMENT;
    const text = bytes(ptr, len, 64 * 1024) orelse return c.HI_INVALID_ARGUMENT;
    instance.input(convert(*Instance, value), .{ .paste = text }) catch |err| return status(err);
    return c.HI_OK;
}
/// Uses the shared native named-key implementation.
pub export fn hi_send_named_key(raw: ?*c.hi_instance, key: u8, action: u8, mods: u8) u32 {
    const value = raw orelse return c.HI_INVALID_ARGUMENT;
    sendNamedKey(convert(*Instance, value), key, action, mods) catch |err| return status(err);
    return c.HI_OK;
}
/// Uses the shared native Unicode-key implementation.
pub export fn hi_send_unicode_key(raw: ?*c.hi_instance, scalar: u32, action: u8, mods: u8) u32 {
    const value = raw orelse return c.HI_INVALID_ARGUMENT;
    sendUnicodeKey(convert(*Instance, value), scalar, action, mods) catch |err| return status(err);
    return c.HI_OK;
}
/// Uses the shared native mouse-input implementation.
pub export fn hi_send_mouse(raw: ?*c.hi_instance, kind: u8, button: u8, mods: u8, buttons: u8, row: i32, col: u16, pixels: u8, x: u32, y: u32) u32 {
    const value = raw orelse return c.HI_INVALID_ARGUMENT;
    sendMouse(convert(*Instance, value), kind, button, mods, buttons, row, col, pixels, x, y) catch |err| return status(err);
    return c.HI_OK;
}
/// Uses the shared native focus-input implementation.
pub export fn hi_send_focus(raw: ?*c.hi_instance, focus: u8) u32 {
    const value = raw orelse return c.HI_INVALID_ARGUMENT;
    sendFocus(convert(*Instance, value), focus) catch |err| return status(err);
    return c.HI_OK;
}
/// Commits explicit geometry without performing or scheduling a render.
pub export fn hi_resize(raw: ?*c.hi_instance, rows: u16, cols: u16, width: u32, height: u32) u32 {
    const value = raw orelse return c.HI_INVALID_ARGUMENT;
    if (width > 65535 or height > 65535) return c.HI_INVALID_ARGUMENT;
    instance.resizeGeometry(convert(*Instance, value), rows, cols, @intCast(width), @intCast(height)) catch |err| return status(err);
    return c.HI_OK;
}
/// Delivers a fixed process-group signal and reports its exact outcome.
pub export fn hi_signal_group(raw: ?*c.hi_instance, tag: u8, out: ?*u8) u32 {
    const result = out orelse return c.HI_INVALID_ARGUMENT;
    result.* = 0;
    const value = raw orelse return c.HI_INVALID_ARGUMENT;
    const selected: instance.Signal = switch (tag) {
        c.HI_HANGUP => .hangup,
        c.HI_INTERRUPT => .interrupt,
        c.HI_RESIZE_NOTIFY => .resize_notify,
        c.HI_KILL => .kill,
        c.HI_TERMINATE => .terminate,
        else => return c.HI_INVALID_ARGUMENT,
    };
    result.* = switch (instance.signal(convert(*Instance, value), selected)) {
        .delivered => c.HI_SIGNAL_DELIVERED,
        .target_missing => c.HI_SIGNAL_TARGET_MISSING,
        .permission_denied => c.HI_SIGNAL_PERMISSION_DENIED,
        .native_signal_failed => c.HI_SIGNAL_NATIVE_FAILURE,
    };
    return c.HI_OK;
}
/// Services one bounded headless turn; monotonic_ns uses caller-owned monotonic nanoseconds.
pub export fn hi_service_turn(raw: ?*c.hi_instance, readable: u8, writable: u8, timestamp: u64, out: ?*c.hi_service) u32 {
    const result = out orelse return c.HI_INVALID_ARGUMENT;
    result.* = std.mem.zeroes(c.hi_service);
    const raw_value = raw orelse return c.HI_INVALID_ARGUMENT;
    if (readable > 1 or writable > 1) return c.HI_INVALID_ARGUMENT;
    if (comptime builtin.os.tag != .linux) return c.HI_UNSUPPORTED;
    const value = convert(*Instance, raw_value);
    const descriptor = instance.descriptor(value) catch |err| return status(err);
    const turn = instance.service(value, readable == 1, writable == 1, timestamp) catch |err| return status(err);
    result.* = .{
        .terminal_revision = instance.terminal(value).semanticSequence(),
        .descriptor = descriptor,
        .descriptor_kind = 1,
        .animation_wait_ms = turn.animation_wait_ms orelse 0,
        .animation_wait_present = @intFromBool(turn.animation_wait_ms != null),
        .changed = @intFromBool(turn.changed),
        .viewport_changed = @intFromBool(turn.viewport_changed),
        .stream_closed = @intFromBool(turn.stream_closed),
        .write_pending = @intFromBool(instance.writePending(value)),
        .buffered_output_pending = @intFromBool(instance.bufferedOutputPending(value)),
        .exit_kind = if (turn.child_exit) |exit| switch (exit) {
            .code => 1,
            .signal => 2,
        } else 0,
        .exit_value = if (turn.child_exit) |exit| switch (exit) {
            .code => |code| code,
            .signal => |signal| signal,
        } else 0,
        .sync_ended = @intFromBool(turn.synchronized_output.ended),
        .sync_trailing_effect = @intFromBool(turn.synchronized_output.trailing_effect),
        .retained_fallback = @intFromBool(turn.retained_consequence_fallback),
        .reserved = @splat(0),
    };
    return c.HI_OK;
}
/// VT owns copied cell vocabulary and projection; Instance supplies only the observation capability.
pub export fn hi_copy_cell(raw: ?*const c.hi_instance, history: u32, row: u16, col: u16, out: ?*c.hvt_cell) u32 {
    const result = out orelse return c.HI_INVALID_ARGUMENT;
    result.* = std.mem.zeroes(c.hvt_cell);
    const value = raw orelse return c.HI_INVALID_ARGUMENT;
    var copied: vt.c.hvt_cell = undefined;
    vt.copyCell(instance.terminal(convert(*const Instance, value)), history, row, col, &copied) catch return c.HI_INVALID_ARGUMENT;
    result.* = .{ .scalars = copied.scalars, .scalar_count = copied.scalar_count, .width = copied.width, .height = copied.height, .x = copied.x, .y = copied.y, .reserved = @splat(0) };
    return c.HI_OK;
}
