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
const frames = @import("instance_native_frames");

// zig-audit: acknowledge anytype
// reason: This private conversion accepts only matching C/native opaque handle pointers at exact exported sites.
fn convert(comptime T: type, value: anytype) T {
    // zig-audit: acknowledge ptr_cast
    // reason: Only matching local Instance or frame endpoint handles are adapted; no records or headless specializations are reinterpreted.
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
    instance.tryDeinit(value) catch return c.HI_BUSY;
    slot.* = null;
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
    const selected = native.signalFromTag(tag) orelse return c.HI_INVALID_ARGUMENT;
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
    return hi_service_turn_policy(raw, c.HI_SERVICE_HEADLESS, readable, writable, timestamp, out);
}
/// Services one explicit caller-selected policy with canonical pressure/fallback behavior.
pub export fn hi_service_turn_policy(raw: ?*c.hi_instance, policy: u8, readable: u8, writable: u8, timestamp: u64, out: ?*c.hi_service) u32 {
    const result = out orelse return c.HI_INVALID_ARGUMENT;
    result.* = std.mem.zeroes(c.hi_service);
    const raw_value = raw orelse return c.HI_INVALID_ARGUMENT;
    if (readable > 1 or writable > 1) return c.HI_INVALID_ARGUMENT;
    if (comptime builtin.os.tag != .linux) return c.HI_UNSUPPORTED;
    const value = convert(*Instance, raw_value);
    const descriptor = instance.descriptor(value) catch |err| return status(err);
    const selected: instance.ConsequencePolicy = switch (policy) {
        c.HI_SERVICE_HEADLESS => .headless,
        c.HI_SERVICE_RETAIN => .retain,
        else => return c.HI_INVALID_ARGUMENT,
    };
    const turn = instance.serviceWithConsequencePolicy(value, readable == 1, writable == 1, timestamp, selected) catch |err| return status(err);
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

/// Opens one lifetime-pinning backend endpoint on the producer thread.
pub export fn hi_frame_open(version: u32, raw: ?*c.hi_instance, out: ?*?*c.hi_frame_stream) u32 {
    if (version != c.HI_ABI_VERSION) return c.HI_VERSION_MISMATCH;
    const slot = out orelse return c.HI_INVALID_ARGUMENT;
    const owner = raw orelse return c.HI_INVALID_ARGUMENT;
    if (slot.* != null) return c.HI_INVALID_ARGUMENT;
    const stream = frames.open(heap, convert(*Instance, owner)) catch |failure| return switch (failure) {
        error.OutOfMemory => c.HI_OUT_OF_MEMORY,
        error.PresentationUnavailable => c.HI_PRESENTATION_UNAVAILABLE,
        error.PublicationBorrowed => c.HI_BUSY,
    };
    slot.* = convert(*c.hi_frame_stream, stream);
    return c.HI_OK;
}
/// Closes only after the backend stops using borrowed frame pixels.
pub export fn hi_frame_close(out: ?*?*c.hi_frame_stream) void {
    const slot = out orelse return;
    const value = slot.* orelse return;
    slot.* = null;
    frames.close(convert(*frames.Stream, value));
}
/// Claims one newest immutable frame and copies its Instance-owned envelope.
pub export fn hi_frame_acquire(raw: ?*c.hi_frame_stream, out: ?*c.hi_frame_info) u32 {
    const result = out orelse return c.HI_INVALID_ARGUMENT;
    result.* = std.mem.zeroes(c.hi_frame_info);
    const value = raw orelse return c.HI_INVALID_ARGUMENT;
    const stream = convert(*frames.Stream, value);
    frames.acquire(stream) catch |failure| return switch (failure) {
        error.PendingFrame => c.HI_BUSY,
        error.NoFrame => c.HI_NO_FRAME,
        error.FrameTooLarge => c.HI_RESOURCE_LIMIT,
    };
    result.* = frames.info(stream) catch return c.HI_NO_FRAME;
    return c.HI_OK;
}
fn frameCopyFailure(failure: (frames.render.Error || error{NoPendingFrame})) u32 {
    return switch (failure) {
        error.BufferTooSmall => c.HI_RESOURCE_LIMIT,
        error.InvalidPixelSpan => c.HI_OPERATION_FAILED,
        error.NoPendingFrame => c.HI_NO_FRAME,
    };
}
/// Copies the complete drawing array in one call into caller-owned storage.
pub export fn hi_frame_commands(raw: ?*c.hi_frame_stream, out: ?[*]frames.render.CommandInfo, capacity: usize) u32 {
    const value = raw orelse return c.HI_INVALID_ARGUMENT;
    const stream = convert(*frames.Stream, value);
    const frame = frames.pending(stream) orelse return c.HI_NO_FRAME;
    const count = frame.commands.len;
    if (capacity < count) return c.HI_RESOURCE_LIMIT;
    // Capacity is caller-owned; form only the exact leased extent we will write.
    const storage: []frames.render.CommandInfo = if (out) |ptr| ptr[0..count] else if (count == 0) &.{} else return c.HI_INVALID_ARGUMENT;
    // zig-audit: acknowledge discard
    // reason: The caller knows the immutable count from hi_frame_info; only projection status is returned here.
    _ = frames.copyCommands(convert(*frames.Stream, value), storage) catch |failure| return frameCopyFailure(failure);
    return c.HI_OK;
}
/// Copies upload metadata and borrows the exact immutable pixels until release.
pub export fn hi_frame_uploads(raw: ?*c.hi_frame_stream, out: ?[*]frames.render.Upload, capacity: usize) u32 {
    const value = raw orelse return c.HI_INVALID_ARGUMENT;
    if (capacity > instance.render.terminal.maximum_external_images + 1) return c.HI_RESOURCE_LIMIT;
    const storage: []frames.render.Upload = if (out) |ptr| ptr[0..capacity] else if (capacity == 0) &.{} else return c.HI_INVALID_ARGUMENT;
    // zig-audit: acknowledge discard
    // reason: The immutable count is in hi_frame_info; borrowed pixel metadata is supplied through the output array.
    _ = frames.copyUploads(convert(*frames.Stream, value), storage) catch |failure| return frameCopyFailure(failure);
    return c.HI_OK;
}
/// Copies all exact resource retirements in one call.
pub export fn hi_frame_removals(raw: ?*c.hi_frame_stream, out: ?[*]frames.render.RemovalInfo, capacity: usize) u32 {
    const value = raw orelse return c.HI_INVALID_ARGUMENT;
    if (capacity > instance.render.terminal.maximum_external_images + 1) return c.HI_RESOURCE_LIMIT;
    const storage: []frames.render.RemovalInfo = if (out) |ptr| ptr[0..capacity] else if (capacity == 0) &.{} else return c.HI_INVALID_ARGUMENT;
    // zig-audit: acknowledge discard
    // reason: The caller obtains the immutable retirement count from hi_frame_info.
    _ = frames.copyRemovals(convert(*frames.Stream, value), storage) catch |failure| return frameCopyFailure(failure);
    return c.HI_OK;
}
/// Publishes exact backend residency feedback, leaving the lease held on rejection.
pub export fn hi_frame_release(raw: ?*c.hi_frame_stream, values: [*c]const c.hrc_residency, count: usize) u32 {
    const value = raw orelse return c.HI_INVALID_ARGUMENT;
    if (count > instance.render.terminal.maximum_external_images + 1) return c.HI_RESOURCE_LIMIT;
    if (count != 0 and values == null) return c.HI_INVALID_ARGUMENT;
    var storage: [instance.render.terminal.maximum_external_images + 1]instance.render.terminal.Residency = undefined;
    for (0..count) |index| {
        const item = values[index];
        if (item._reserved[0] != 0 or item._reserved[1] != 0 or item._reserved[2] != 0) return c.HI_INVALID_ARGUMENT;
        const format: instance.render.terminal.ResourceFormat = switch (item.format) {
            0 => .alpha8,
            1 => .rgba8,
            else => return c.HI_INVALID_ARGUMENT,
        };
        storage[index] = .{ .resource = .{
            .resource = @fromBackingInt(item.resource),
            .generation = @fromBackingInt(item.generation),
        }, .format = format, .size = .{ .width = item.width, .height = item.height } };
    }
    frames.release(convert(*frames.Stream, value), storage[0..count]) catch |failure| return switch (failure) {
        error.NoPendingFrame => c.HI_NO_FRAME,
        error.InvalidResidency => c.HI_INVALID_ARGUMENT,
        error.FeedbackBusy => c.HI_BUSY,
    };
    return c.HI_OK;
}
/// Abandons a candidate that changed no accepted backend resources.
pub export fn hi_frame_abandon(raw: ?*c.hi_frame_stream) u32 {
    const value = raw orelse return c.HI_INVALID_ARGUMENT;
    frames.abandon(convert(*frames.Stream, value));
    return c.HI_OK;
}

/// Explicit producer presentation work; scheduling and frame demand remain caller-owned.
pub export fn hi_publish_frame(raw: ?*c.hi_instance, history: u32) u32 {
    const value = raw orelse return c.HI_INVALID_ARGUMENT;
    instance.publishRenderAt(convert(*Instance, value), history) catch |failure| {
        return switch (failure) {
            error.PresentationUnavailable => c.HI_PRESENTATION_UNAVAILABLE,
            error.PresentationBusy, error.PublicationBusy => c.HI_BUSY,
            error.OutOfMemory => c.HI_OUT_OF_MEMORY,
            else => c.HI_OPERATION_FAILED,
        };
    };
    return c.HI_OK;
}

const queries = vt.queries;
fn queryFailure(failure: queries.Error) u32 {
    return switch (failure) {
        error.OutOfMemory => c.HI_OUT_OF_MEMORY,
        error.InvalidArgument, error.InvalidRange, error.CodepointTooLarge, error.Utf8CannotEncodeSurrogateHalf => c.HI_INVALID_ARGUMENT,
        error.ContextChanged => c.HI_CONTEXT_CHANGED,
        error.TextLimit, error.BufferTooSmall => c.HI_BUFFER_TOO_SMALL,
        error.CoordinateLimit, error.Overflow => c.HI_RESOURCE_LIMIT,
    };
}
fn queryOutput(ptr: [*c]u8, capacity: usize) ?[]u8 {
    if (capacity > 1024 * 1024) return null;
    if (ptr != null) return ptr[0..capacity];
    return if (capacity == 0) &.{} else null;
}
/// Copies an exact VT-owned match; query scratch and all mutation remain on the owner thread.
pub export fn hi_search(raw: ?*const c.hi_instance, ptr: [*c]const u8, len: usize, reverse: u8, origin_present: u8, row: i32, column: u16, out: ?*vt.c.hvt_search_match) u32 {
    const result = out orelse return c.HI_INVALID_ARGUMENT;
    result.* = .{};
    const owner = raw orelse return c.HI_INVALID_ARGUMENT;
    if (reverse > 1 or origin_present > 1) return c.HI_INVALID_ARGUMENT;
    const query = bytes(ptr, len, c.HVT_MAX_SEARCH_QUERY_BYTES) orelse return c.HI_INVALID_ARGUMENT;
    queries.search(instance.terminal(convert(*const Instance, owner)), heap, query, reverse != 0, origin_present != 0, row, column, result) catch |failure| return queryFailure(failure);
    return c.HI_OK;
}
/// Expands copied canonical selection endpoints against an exact geometry context.
pub export fn hi_expand_selection(raw: ?*const c.hi_instance, kind: u8, history: u32, row: i32, column: u16, columns: u16, alternate: u8, out: ?*vt.c.hvt_selection_range) u32 {
    const result = out orelse return c.HI_INVALID_ARGUMENT;
    result.* = .{};
    const owner = raw orelse return c.HI_INVALID_ARGUMENT;
    if (alternate > 1) return c.HI_INVALID_ARGUMENT;
    queries.expandSelection(instance.terminal(convert(*const Instance, owner)), kind, history, row, column, columns, alternate != 0, result) catch |failure| return queryFailure(failure);
    return c.HI_OK;
}
/// Copies complete selected text; a failure leaves byte output untouched and length zero.
pub export fn hi_copy_selection(raw: ?*const c.hi_instance, start_row: i32, start_column: u16, end_row: i32, end_column: u16, columns: u16, alternate: u8, out: [*c]u8, capacity: usize, length: ?*usize) u32 {
    const copied = length orelse return c.HI_INVALID_ARGUMENT;
    copied.* = 0;
    const owner = raw orelse return c.HI_INVALID_ARGUMENT;
    if (alternate > 1) return c.HI_INVALID_ARGUMENT;
    if (capacity > 1024 * 1024) return c.HI_RESOURCE_LIMIT;
    const output = queryOutput(out, capacity) orelse return c.HI_INVALID_ARGUMENT;
    copied.* = queries.copySelection(instance.terminal(convert(*const Instance, owner)), heap, start_row, start_column, end_row, end_column, columns, alternate != 0, output) catch |failure| return queryFailure(failure);
    return c.HI_OK;
}
/// Copies one exact hyperlink and reports required bytes on a capacity failure.
pub export fn hi_copy_hyperlink(raw: ?*const c.hi_instance, history: u32, row: i32, column: u16, columns: u16, alternate: u8, out: [*c]u8, capacity: usize, length: ?*usize) u32 {
    const required = length orelse return c.HI_INVALID_ARGUMENT;
    required.* = 0;
    const owner = raw orelse return c.HI_INVALID_ARGUMENT;
    if (alternate > 1) return c.HI_INVALID_ARGUMENT;
    if (capacity > 1024 * 1024) return c.HI_RESOURCE_LIMIT;
    const output = queryOutput(out, capacity) orelse return c.HI_INVALID_ARGUMENT;
    queries.copyHyperlink(instance.terminal(convert(*const Instance, owner)), history, row, column, columns, alternate != 0, output, required) catch |failure| return queryFailure(failure);
    return c.HI_OK;
}
/// Copies exactly the current row-shape extent; insufficient capacity writes no rows.
pub export fn hi_copy_row_shapes(raw: ?*const c.hi_instance, history: u32, out: ?[*]vt.c.hvt_row_shape, capacity: usize, count: ?*usize) u32 {
    const required = count orelse return c.HI_INVALID_ARGUMENT;
    required.* = 0;
    const owner = raw orelse return c.HI_INVALID_ARGUMENT;
    const observation = instance.terminal(convert(*const Instance, owner));
    const rows = observation.semanticView(history).rows;
    required.* = rows;
    if (capacity < rows) return c.HI_BUFFER_TOO_SMALL;
    const output: []vt.c.hvt_row_shape = if (out) |ptr| ptr[0..rows] else if (rows == 0) &.{} else return c.HI_INVALID_ARGUMENT;
    required.* = queries.copyRowShapes(observation, history, output) catch |failure| return queryFailure(failure);
    return c.HI_OK;
}
/// Copies a versioned VT interaction record without exporting enum representation.
pub export fn hi_interaction(raw: ?*const c.hi_instance, out: ?*vt.c.hvt_interaction) u32 {
    const result = out orelse return c.HI_INVALID_ARGUMENT;
    result.* = .{};
    const owner = raw orelse return c.HI_INVALID_ARGUMENT;
    result.* = queries.interaction(instance.terminal(convert(*const Instance, owner)));
    return c.HI_OK;
}

const RequestMutationError = native.ReplyError || instance.ConsumeConsequenceError;
fn requestFailure(failure: RequestMutationError) u32 {
    return switch (failure) {
        error.OutOfMemory => c.HI_OUT_OF_MEMORY,
        error.InvalidArgument => c.HI_INVALID_ARGUMENT,
        error.ReplyLimit, error.ConsequenceLimit => c.HI_RESOURCE_LIMIT,
        error.ReplyRequired => c.HI_REPLY_REQUIRED,
        error.RequestMismatch, error.PointerShapeReplyMismatch, error.ContainerReplyMismatch => c.HI_REQUEST_MISMATCH,
        error.StaleConsequence, error.StaleClipboardRequest, error.StalePointerShape, error.StaleColorPreferenceQuery, error.StaleContainerRequest => c.HI_STALE_REQUEST,
    };
}
fn requestCopyFailure(failure: vt.requests.Error) u32 {
    return switch (failure) {
        error.StaleRequest => c.HI_STALE_REQUEST,
        error.RequestLimit => c.HI_RESOURCE_LIMIT,
        error.BufferTooSmall => c.HI_BUFFER_TOO_SMALL,
    };
}
/// Copies one complete VT-owned descriptor; no mutable terminal or payload borrow escapes.
pub export fn hi_request_head(raw: ?*const c.hi_instance, out: ?*vt.requests.Info) u32 {
    const result = out orelse return c.HI_INVALID_ARGUMENT;
    result.* = std.mem.zeroes(vt.requests.Info);
    const owner = raw orelse return c.HI_INVALID_ARGUMENT;
    vt.requests.head(instance.terminal(convert(*const Instance, owner)), result) catch |failure| return requestCopyFailure(failure);
    return c.HI_OK;
}
/// Copies the exact current-head payload or reports its required byte extent.
pub export fn hi_copy_request_payload(raw: ?*const c.hi_instance, id: u64, out: [*c]u8, capacity: usize, length: ?*usize) u32 {
    const required = length orelse return c.HI_INVALID_ARGUMENT;
    required.* = 0;
    const owner = raw orelse return c.HI_INVALID_ARGUMENT;
    if (capacity > vt.c.HVT_MAX_REQUEST_PAYLOAD_BYTES) return c.HI_RESOURCE_LIMIT;
    const output = queryOutput(out, capacity) orelse return c.HI_INVALID_ARGUMENT;
    vt.requests.copyPayload(instance.terminal(convert(*const Instance, owner)), id, output, required) catch |failure| return requestCopyFailure(failure);
    return c.HI_OK;
}
/// Acknowledges only the matching consumable head; required replies are explicit.
pub export fn hi_consume_request(raw: ?*c.hi_instance, id: u64) u32 {
    const owner = raw orelse return c.HI_INVALID_ARGUMENT;
    native.consumeRequest(convert(*Instance, owner), id) catch |failure| return requestFailure(failure);
    return c.HI_OK;
}

/// Admits one named canonical exact-head operation without polling or flushing.
pub export fn hi_reply_clipboard(raw: ?*c.hi_instance, id: u64, ptr: [*c]const u8, len: usize) u32 {
    const owner = raw orelse return c.HI_INVALID_ARGUMENT;
    if (len > vt.c.HVT_MAX_REQUEST_PAYLOAD_BYTES) return c.HI_RESOURCE_LIMIT;
    const text = bytes(ptr, len, vt.c.HVT_MAX_REQUEST_PAYLOAD_BYTES) orelse return c.HI_INVALID_ARGUMENT;
    native.replyClipboard(convert(*Instance, owner), id, text) catch |failure| return requestFailure(failure);
    return c.HI_OK;
}

/// Admits one named canonical exact-head operation without polling or flushing.
pub export fn hi_reply_pointer_shape(raw: ?*c.hi_instance, id: u64, ptr: [*c]const u8, len: usize) u32 {
    const owner = raw orelse return c.HI_INVALID_ARGUMENT;
    if (len > vt.c.HVT_MAX_REQUEST_PAYLOAD_BYTES) return c.HI_RESOURCE_LIMIT;
    const text = bytes(ptr, len, vt.c.HVT_MAX_REQUEST_PAYLOAD_BYTES) orelse return c.HI_INVALID_ARGUMENT;
    native.replyPointerShape(convert(*Instance, owner), id, text) catch |failure| return requestFailure(failure);
    return c.HI_OK;
}

/// Admits one named canonical exact-head operation without polling or flushing.
pub export fn hi_reply_color_preference(raw: ?*c.hi_instance, id: u64, preference: u8) u32 {
    const owner = raw orelse return c.HI_INVALID_ARGUMENT;
    native.replyColorPreference(convert(*Instance, owner), id, preference) catch |failure| return requestFailure(failure);
    return c.HI_OK;
}

/// Admits one named canonical exact-head operation without polling or flushing.
pub export fn hi_reply_container_state(raw: ?*c.hi_instance, id: u64, state: u8) u32 {
    const owner = raw orelse return c.HI_INVALID_ARGUMENT;
    native.replyContainerState(convert(*Instance, owner), id, state) catch |failure| return requestFailure(failure);
    return c.HI_OK;
}

/// Admits one named canonical exact-head operation without polling or flushing.
pub export fn hi_reply_container_position(raw: ?*c.hi_instance, id: u64, x: u32, y: u32) u32 {
    const owner = raw orelse return c.HI_INVALID_ARGUMENT;
    native.replyContainerPosition(convert(*Instance, owner), id, x, y) catch |failure| return requestFailure(failure);
    return c.HI_OK;
}

/// Admits one named canonical exact-head operation without polling or flushing.
pub export fn hi_reply_container_screen_cells(raw: ?*c.hi_instance, id: u64, rows: u32, columns: u32) u32 {
    const owner = raw orelse return c.HI_INVALID_ARGUMENT;
    native.replyContainerScreenCells(convert(*Instance, owner), id, rows, columns) catch |failure| return requestFailure(failure);
    return c.HI_OK;
}

/// Admits one named canonical exact-head operation without polling or flushing.
pub export fn hi_reply_container_icon_title(raw: ?*c.hi_instance, id: u64, ptr: [*c]const u8, len: usize) u32 {
    const owner = raw orelse return c.HI_INVALID_ARGUMENT;
    if (len > vt.c.HVT_MAX_REQUEST_PAYLOAD_BYTES) return c.HI_RESOURCE_LIMIT;
    const text = bytes(ptr, len, vt.c.HVT_MAX_REQUEST_PAYLOAD_BYTES) orelse return c.HI_INVALID_ARGUMENT;
    native.replyContainerIconTitle(convert(*Instance, owner), id, text) catch |failure| return requestFailure(failure);
    return c.HI_OK;
}

/// Admits one named canonical exact-head operation without polling or flushing.
pub export fn hi_decline_container(raw: ?*c.hi_instance, id: u64) u32 {
    const owner = raw orelse return c.HI_INVALID_ARGUMENT;
    native.declineContainer(convert(*Instance, owner), id) catch |failure| return requestFailure(failure);
    return c.HI_OK;
}
