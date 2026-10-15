//! C export root for the optional VT-owned standalone artifact.
const std = @import("std");
const native = @import("howl_vt_native");
const owner = native.owner;
const c = native.c;
const heap = std.heap.c_allocator;
const Error = owner.Error || native.Error || native.requests.Error || native.graphics.Error || native.logical_output.Error;

fn failure(err: Error) u32 {
    return switch (err) {
        error.OutOfMemory => c.HVT_OUT_OF_MEMORY,
        error.InvalidArgument, error.InvalidDimensions, error.InvalidUtf8, error.InvalidText, error.InvalidRange, error.InvalidReplyCount, error.CodepointTooLarge, error.Utf8CannotEncodeSurrogateHalf => c.HVT_INVALID_ARGUMENT,
        error.ResourceLimit, error.ConsequenceLimit, error.ConsequencePressure, error.PropertyLimit, error.ReplyLimit, error.ParsedEventLimit, error.ScalarCapacity, error.KeyTextLimit, error.LengthOverflow, error.CoordinateLimit, error.Overflow, error.RequestLimit => c.HVT_RESOURCE_LIMIT,
        error.BufferTooSmall, error.TextLimit => c.HVT_BUFFER_TOO_SMALL,
        error.StaleRequest, error.StaleConsequence, error.StaleClipboardRequest, error.StalePointerShape, error.StaleColorPreferenceQuery, error.StaleContainerRequest => c.HVT_STALE_REQUEST,
        error.ReplyRequired => c.HVT_REPLY_REQUIRED,
        error.ContextChanged => c.HVT_CONTEXT_CHANGED,
        error.RequestMismatch, error.PointerShapeReplyMismatch, error.ContainerReplyMismatch => c.HVT_REQUEST_MISMATCH,
    };
}
fn mutable(raw: *c.hvt_terminal) *owner.Owner {
    // zig-audit: acknowledge ptr_cast
    // reason: Only the matching constructor-owned Owner allocation is adapted through the C opaque handle.
    return @ptrCast(raw);
}
fn constant(raw: *const c.hvt_terminal) *const owner.Owner {
    // zig-audit: acknowledge ptr_cast
    // reason: This C handle lends only the matching opaque owner const capability.
    return @ptrCast(raw);
}
fn address(start: usize, length: usize) Error!usize {
    return std.math.add(usize, start, length) catch error.InvalidArgument;
}
fn input(pointer: ?[*]const u8, length: usize, maximum: usize) Error![]const u8 {
    if (length > maximum) return error.ResourceLimit;
    const ptr = pointer orelse return if (length == 0) "" else error.InvalidArgument;
    // zig-audit: acknowledge discard
    // reason: Checked address addition validates the complete logical input extent before forming its slice.
    _ = try address(@intFromPtr(ptr), length);
    return ptr[0..length];
}
fn output(pointer: ?[*]u8, capacity: usize, extent: usize) Error![]u8 {
    if (capacity != 0 and pointer == null) return error.InvalidArgument;
    if (capacity < extent) return error.BufferTooSmall;
    if (extent == 0) return &.{};
    const ptr = pointer orelse return error.InvalidArgument;
    // zig-audit: acknowledge discard
    // reason: Only the admitted required output prefix is checked and sliced, never the unchecked full capacity.
    _ = try address(@intFromPtr(ptr), extent);
    return ptr[0..extent];
}
fn copyBudget(capacity: usize) Error!void {
    if (capacity > c.HVT_MAX_COPY_BYTES) return error.ResourceLimit;
}
fn completeSize(result: Error!void) Error!void {
    result catch |err| switch (err) {
        error.BufferTooSmall => {},
        else => return err,
    };
}

/// Reports the exact owned native vocabulary/ABI version.
pub export fn hvt_abi_version() u32 {
    return c.HVT_NATIVE_VERSION;
}
/// Constructs one stable canonical owner and publishes only on complete success.
pub export fn hvt_create(version: u32, config: ?*const c.hvt_config, out: ?*?*c.hvt_terminal) u32 {
    if (version != c.HVT_NATIVE_VERSION) return c.HVT_VERSION_MISMATCH;
    const slot = out orelse return c.HVT_INVALID_ARGUMENT;
    if (slot.* != null) return c.HVT_INVALID_ARGUMENT;
    const request = config orelse return c.HVT_INVALID_ARGUMENT;
    const value = owner.create(heap, request) catch |err| return failure(err);
    // zig-audit: acknowledge ptr_cast
    // reason: Publish only this complete native Owner as its matching C opaque handle.
    slot.* = @ptrCast(value);
    return c.HVT_OK;
}
/// Clears and releases the exact owner; both forms of null are no-ops.
pub export fn hvt_release(out: ?*?*c.hvt_terminal) void {
    const slot = out orelse return;
    const raw = slot.* orelse return;
    slot.* = null;
    owner.destroy(mutable(raw));
}
/// Opens only a Reader reference; no mutable or lifetime-pinning VT authority.
pub export fn hvt_observation_open(version: u32, raw: ?*c.hvt_terminal, out: ?*?*c.hvt_observation) u32 {
    if (version != c.HVT_NATIVE_VERSION) return c.HVT_VERSION_MISMATCH;
    const slot = out orelse return c.HVT_INVALID_ARGUMENT;
    if (slot.* != null) return c.HVT_INVALID_ARGUMENT;
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    const reader = owner.openObservation(mutable(value)) catch |err| return failure(err);
    slot.* = native.observation.toC(reader);
    return c.HVT_OK;
}
/// Clears one Reader reference; both null forms are harmless, even after teardown.
pub export fn hvt_observation_release(out: ?*?*c.hvt_observation) u32 {
    const slot = out orelse return c.HVT_OK;
    const raw = slot.* orelse return c.HVT_OK;
    slot.* = null;
    native.observation.release(native.observation.fromC(raw));
    return c.HVT_OK;
}
/// Copies coherent actual viewport metadata without exposing a borrow.
pub export fn hvt_observe(raw: ?*const c.hvt_terminal, history: u32, out: ?*c.hvt_state) u32 {
    const result = out orelse return c.HVT_INVALID_ARGUMENT;
    result.* = std.mem.zeroes(c.hvt_state);
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    result.* = owner.observe(constant(value), history);
    return c.HVT_OK;
}
/// Publishes exact progress only for a complete successful canonical prefix.
pub export fn hvt_feed(raw: ?*c.hvt_terminal, ptr: ?[*]const u8, length: usize, timestamp: u64, out: ?*c.hvt_feed_progress) u32 {
    const result = out orelse return c.HVT_INVALID_ARGUMENT;
    result.* = std.mem.zeroes(c.hvt_feed_progress);
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    const bytes = input(ptr, length, c.HVT_MAX_INPUT_BYTES) catch |err| return failure(err);
    result.* = owner.feed(mutable(value), bytes, timestamp) catch |err| return failure(err);
    return c.HVT_OK;
}
/// Atomically resizes topology/pixels/replies; zero pixels preserve existing geometry.
pub export fn hvt_resize(raw: ?*c.hvt_terminal, rows: u16, columns: u16, width: u32, height: u32) u32 {
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    owner.resize(mutable(value), rows, columns, width, height) catch |err| return failure(err);
    return c.HVT_OK;
}
/// Applies canonical RIS while preserving retained queued work.
pub export fn hvt_reset(raw: ?*c.hvt_terminal) u32 {
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    owner.reset(mutable(value));
    return c.HVT_OK;
}
/// Services retained animation against caller-owned time.
pub export fn hvt_service_animations(raw: ?*c.hvt_terminal, timestamp: u64, out: ?*c.hvt_animation) u32 {
    const result = out orelse return c.HVT_INVALID_ARGUMENT;
    result.* = std.mem.zeroes(c.hvt_animation);
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    result.* = owner.serviceAnimations(mutable(value), timestamp);
    return c.HVT_OK;
}

fn encode(value: *c.hvt_terminal, event: native.Terminal.InputEvent, ptr: ?[*]u8, capacity: usize, written: *usize) u32 {
    const extent = owner.inputCapacity(event) catch |err| return failure(err);
    const buffer = output(ptr, capacity, extent) catch |err| return failure(err);
    written.* = owner.encode(mutable(value), event, buffer) catch |err| return failure(err);
    return c.HVT_OK;
}
/// Encodes one defined physical key after caller-capacity admission.
pub export fn hvt_encode_named_key(raw: ?*c.hvt_terminal, key: u8, action: u8, mods: u8, ptr: ?[*]u8, capacity: usize, out: ?*usize) u32 {
    const written = out orelse return c.HVT_INVALID_ARGUMENT;
    written.* = 0;
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    const event = native.namedInput(key, action, mods) catch |err| return failure(err);
    return encode(value, event, ptr, capacity, written);
}
/// Encodes a validated Unicode physical key without retaining caller storage.
pub export fn hvt_encode_unicode_key(raw: ?*c.hvt_terminal, scalar: u32, action: u8, mods: u8, ptr: ?[*]u8, capacity: usize, out: ?*usize) u32 {
    const written = out orelse return c.HVT_INVALID_ARGUMENT;
    written.* = 0;
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    const event = native.unicodeInput(scalar, action, mods) catch |err| return failure(err);
    return encode(value, event, ptr, capacity, written);
}
/// Rejects undefined mouse metadata and shortage before locator effects.
pub export fn hvt_encode_mouse(raw: ?*c.hvt_terminal, kind: u8, button: u8, mods: u8, buttons: u8, row: i32, column: u16, pixels: u8, x: u32, y: u32, ptr: ?[*]u8, capacity: usize, out: ?*usize) u32 {
    const written = out orelse return c.HVT_INVALID_ARGUMENT;
    written.* = 0;
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    const event = native.mouseInput(kind, button, mods, buttons, row, column, pixels, x, y) catch |err| return failure(err);
    return encode(value, event, ptr, capacity, written);
}
/// Encodes focus reporting only after minimum caller capacity is admitted.
pub export fn hvt_encode_focus(raw: ?*c.hvt_terminal, focus: u8, ptr: ?[*]u8, capacity: usize, out: ?*usize) u32 {
    const written = out orelse return c.HVT_INVALID_ARGUMENT;
    written.* = 0;
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    const event = native.focusInput(focus) catch |err| return failure(err);
    return encode(value, event, ptr, capacity, written);
}
/// Checks both exact paste ranges before forming either slice or encoding.
pub export fn hvt_encode_paste(raw: ?*c.hvt_terminal, ptr: ?[*]const u8, length: usize, target: ?[*]u8, capacity: usize, out: ?*usize) u32 {
    const written = out orelse return c.HVT_INVALID_ARGUMENT;
    written.* = 0;
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    if (length > c.HVT_MAX_INPUT_BYTES) return c.HVT_RESOURCE_LIMIT;
    if (length != 0 and ptr == null) return c.HVT_INVALID_ARGUMENT;
    if (capacity != 0 and target == null) return c.HVT_INVALID_ARGUMENT;
    const extent = length + c.HVT_PASTE_EXTRA_BYTES;
    if (capacity < extent) return c.HVT_BUFFER_TOO_SMALL;
    const destination = target orelse return c.HVT_INVALID_ARGUMENT;
    const destination_start = @intFromPtr(destination);
    const destination_end = address(destination_start, extent) catch |err| return failure(err);
    if (ptr) |source| {
        const source_start = @intFromPtr(source);
        const source_end = address(source_start, length) catch |err| return failure(err);
        if (length != 0 and source_start < destination_end and destination_start < source_end)
            return c.HVT_INVALID_ARGUMENT;
    }
    const bytes = input(ptr, length, c.HVT_MAX_INPUT_BYTES) catch |err| return failure(err);
    return encode(value, .{ .paste = bytes }, target, capacity, written);
}
/// Copies every queued byte without consuming or exposing a borrow.
pub export fn hvt_copy_replies(raw: ?*const c.hvt_terminal, ptr: ?[*]u8, capacity: usize, out: ?*usize) u32 {
    const required = out orelse return c.HVT_INVALID_ARGUMENT;
    required.* = 0;
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    copyBudget(capacity) catch |err| return failure(err);
    completeSize(owner.copyReplies(constant(value), &.{}, required)) catch |err| return failure(err);
    const buffer = output(ptr, capacity, required.*) catch |err| return failure(err);
    owner.copyReplies(constant(value), buffer, required) catch |err| return failure(err);
    return c.HVT_OK;
}
/// Consumes only an externally delivered prefix; zero preserves revisions.
pub export fn hvt_consume_replies(raw: ?*c.hvt_terminal, count: usize) u32 {
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    owner.consumeReplies(mutable(value), count) catch |err| return failure(err);
    return c.HVT_OK;
}
/// Copies one scalar/occupancy record from the selected viewport.
pub export fn hvt_copy_cell(raw: ?*const c.hvt_terminal, history: u32, row: u16, column: u16, out: ?*c.hvt_cell) u32 {
    const result = out orelse return c.HVT_INVALID_ARGUMENT;
    result.* = std.mem.zeroes(c.hvt_cell);
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    var cell = std.mem.zeroes(c.hvt_cell);
    native.copyCell(owner.observation(constant(value)), history, row, column, &cell) catch |err| return failure(err);
    result.* = cell;
    return c.HVT_OK;
}
/// Copies a bounded retained-history search result with canonical cut semantics.
pub export fn hvt_search(raw: ?*const c.hvt_terminal, ptr: ?[*]const u8, length: usize, reverse: u8, origin: u8, row: i32, column: u16, out: ?*c.hvt_search_match) u32 {
    const result = out orelse return c.HVT_INVALID_ARGUMENT;
    result.* = std.mem.zeroes(c.hvt_search_match);
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    if (reverse > 1 or origin > 1) return c.HVT_INVALID_ARGUMENT;
    const query = input(ptr, length, c.HVT_MAX_SEARCH_QUERY_BYTES) catch |err| return failure(err);
    var match = std.mem.zeroes(c.hvt_search_match);
    owner.search(constant(value), query, reverse == 1, origin == 1, row, column, &match) catch |err| return failure(err);
    result.* = match;
    return c.HVT_OK;
}
/// Expands copied stable selection coordinates using canonical native queries.
pub export fn hvt_expand_selection(raw: ?*const c.hvt_terminal, kind: u8, history: u32, row: i32, column: u16, columns: u16, alternate: u8, out: ?*c.hvt_selection_range) u32 {
    const result = out orelse return c.HVT_INVALID_ARGUMENT;
    result.* = std.mem.zeroes(c.hvt_selection_range);
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    if (alternate > 1) return c.HVT_INVALID_ARGUMENT;
    var range = std.mem.zeroes(c.hvt_selection_range);
    native.queries.expandSelection(owner.observation(constant(value)), kind, history, row, column, columns, alternate == 1, &range) catch |err| return failure(err);
    result.* = range;
    return c.HVT_OK;
}
/// Copies complete selected text; bounded shortage leaves caller bytes untouched.
pub export fn hvt_copy_selection(raw: ?*const c.hvt_terminal, start_row: i32, start_column: u16, end_row: i32, end_column: u16, columns: u16, alternate: u8, ptr: ?[*]u8, capacity: usize, out: ?*usize) u32 {
    const written = out orelse return c.HVT_INVALID_ARGUMENT;
    written.* = 0;
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    if (alternate > 1) return c.HVT_INVALID_ARGUMENT;
    copyBudget(capacity) catch |err| return failure(err);
    const buffer = output(ptr, capacity, capacity) catch |err| return failure(err);
    written.* = owner.copySelection(constant(value), start_row, start_column, end_row, end_column, columns, alternate == 1, buffer) catch |err| return failure(err);
    return c.HVT_OK;
}
/// Copies a complete URI with exact required bytes and context validation.
pub export fn hvt_copy_hyperlink(raw: ?*const c.hvt_terminal, history: u32, row: i32, column: u16, columns: u16, alternate: u8, ptr: ?[*]u8, capacity: usize, out: ?*usize) u32 {
    const required = out orelse return c.HVT_INVALID_ARGUMENT;
    required.* = 0;
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    if (alternate > 1) return c.HVT_INVALID_ARGUMENT;
    copyBudget(capacity) catch |err| return failure(err);
    const observation = owner.observation(constant(value));
    completeSize(native.queries.copyHyperlink(observation, history, row, column, columns, alternate == 1, &.{}, required)) catch |err| return failure(err);
    const buffer = output(ptr, capacity, required.*) catch |err| return failure(err);
    native.queries.copyHyperlink(observation, history, row, column, columns, alternate == 1, buffer, required) catch |err| return failure(err);
    return c.HVT_OK;
}
/// Copies every row shape or reports exact extent without modifying the array.
pub export fn hvt_copy_row_shapes(raw: ?*const c.hvt_terminal, history: u32, ptr: ?[*]c.hvt_row_shape, capacity: usize, out: ?*usize) u32 {
    const required = out orelse return c.HVT_INVALID_ARGUMENT;
    required.* = 0;
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    const observation = owner.observation(constant(value));
    required.* = observation.semanticView(history).rows;
    if (capacity != 0 and ptr == null) return c.HVT_INVALID_ARGUMENT;
    if (capacity < required.*) return c.HVT_BUFFER_TOO_SMALL;
    const target = ptr orelse return c.HVT_INVALID_ARGUMENT;
    const bytes = std.math.mul(usize, required.*, @sizeOf(c.hvt_row_shape)) catch return c.HVT_INVALID_ARGUMENT;
    // zig-audit: acknowledge discard
    // reason: Check the complete advertised record extent before creating its typed slice.
    _ = address(@intFromPtr(target), bytes) catch |err| return failure(err);
    const count = native.queries.copyRowShapes(observation, history, target[0..required.*]) catch |err| return failure(err);
    std.debug.assert(count == required.*);
    return c.HVT_OK;
}
/// Copies interaction tags without exposing mode storage.
pub export fn hvt_get_interaction(raw: ?*const c.hvt_terminal, out: ?*c.hvt_interaction) u32 {
    const result = out orelse return c.HVT_INVALID_ARGUMENT;
    result.* = std.mem.zeroes(c.hvt_interaction);
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    result.* = native.queries.interaction(owner.observation(constant(value)));
    return c.HVT_OK;
}
/// Copies exact-head facts only; observation does not apply host policy.
pub export fn hvt_request_head(raw: ?*const c.hvt_terminal, out: ?*c.hvt_request) u32 {
    const result = out orelse return c.HVT_INVALID_ARGUMENT;
    result.* = std.mem.zeroes(c.hvt_request);
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    var request = std.mem.zeroes(c.hvt_request);
    native.requests.head(owner.observation(constant(value)), &request) catch |err| return failure(err);
    result.* = request;
    return c.HVT_OK;
}
/// Copies one complete exact-head payload, never a terminal borrow.
pub export fn hvt_copy_request_payload(raw: ?*const c.hvt_terminal, id: u64, ptr: ?[*]u8, capacity: usize, out: ?*usize) u32 {
    const required = out orelse return c.HVT_INVALID_ARGUMENT;
    required.* = 0;
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    copyBudget(capacity) catch |err| return failure(err);
    const observation = owner.observation(constant(value));
    completeSize(native.requests.copyPayload(observation, id, &.{}, required)) catch |err| return failure(err);
    const buffer = output(ptr, capacity, required.*) catch |err| return failure(err);
    native.requests.copyPayload(observation, id, buffer, required) catch |err| return failure(err);
    return c.HVT_OK;
}
/// Consumes only an exact non-required FIFO head.
pub export fn hvt_consume_request(raw: ?*c.hvt_terminal, id: u64) u32 {
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    owner.consumeRequest(mutable(value), id) catch |err| return failure(err);
    return c.HVT_OK;
}
/// Supplies caller-approved clipboard bytes through canonical serialization.
pub export fn hvt_reply_clipboard(raw: ?*c.hvt_terminal, id: u64, ptr: ?[*]const u8, length: usize) u32 {
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    const bytes = input(ptr, length, c.HVT_MAX_INPUT_BYTES) catch |err| return failure(err);
    owner.replyClipboard(mutable(value), id, bytes) catch |err| return failure(err);
    return c.HVT_OK;
}
/// Supplies a matching pointer query response without retaining caller bytes.
pub export fn hvt_reply_pointer_shape(raw: ?*c.hvt_terminal, id: u64, ptr: ?[*]const u8, length: usize) u32 {
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    const bytes = input(ptr, length, c.HVT_MAX_INPUT_BYTES) catch |err| return failure(err);
    owner.replyPointerShape(mutable(value), id, bytes) catch |err| return failure(err);
    return c.HVT_OK;
}
/// Validates preference before invoking the exact typed reply.
pub export fn hvt_reply_color_preference(raw: ?*c.hvt_terminal, id: u64, preference: u8) u32 {
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    const selected: native.Terminal.ColorSchemePreference = switch (preference) {
        c.HVT_COLOR_DARK => .dark,
        c.HVT_COLOR_LIGHT => .light,
        else => return c.HVT_INVALID_ARGUMENT,
    };
    owner.replyColorPreference(mutable(value), id, selected) catch |err| return failure(err);
    return c.HVT_OK;
}
/// Supplies a defined container state, preserving type/identity rejection.
pub export fn hvt_reply_container_state(raw: ?*c.hvt_terminal, id: u64, state: u8) u32 {
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    const reply: native.Terminal.ContainerReply = .{ .state = switch (state) {
        c.HVT_CONTAINER_STATE_NORMAL => .normal,
        c.HVT_CONTAINER_STATE_ICONIFIED => .iconified,
        else => return c.HVT_INVALID_ARGUMENT,
    } };
    owner.replyContainer(mutable(value), id, reply) catch |err| return failure(err);
    return c.HVT_OK;
}
/// Serializes native window position through VT-owned grammar.
pub export fn hvt_reply_container_position(raw: ?*c.hvt_terminal, id: u64, x: u32, y: u32) u32 {
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    owner.replyContainer(mutable(value), id, .{ .position = .{ .x = x, .y = y } }) catch |err| return failure(err);
    return c.HVT_OK;
}
/// Serializes native screen dimensions through VT-owned grammar.
pub export fn hvt_reply_container_screen_cells(raw: ?*c.hvt_terminal, id: u64, rows: u32, columns: u32) u32 {
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    owner.replyContainer(mutable(value), id, .{ .screen_cells = .{ .rows = rows, .cols = columns } }) catch |err| return failure(err);
    return c.HVT_OK;
}
/// Supplies bounded icon-title bytes only to the matching typed request.
pub export fn hvt_reply_container_icon_title(raw: ?*c.hvt_terminal, id: u64, ptr: ?[*]const u8, length: usize) u32 {
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    const bytes = input(ptr, length, c.HVT_MAX_INPUT_BYTES) catch |err| return failure(err);
    owner.replyContainer(mutable(value), id, .{ .icon_title = bytes }) catch |err| return failure(err);
    return c.HVT_OK;
}
/// Explicitly declines a matching container query without fabricating state.
pub export fn hvt_decline_container(raw: ?*c.hvt_terminal, id: u64) u32 {
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    owner.declineContainer(mutable(value), id) catch |err| return failure(err);
    return c.HVT_OK;
}

/// Copies canonical graphics through the same optional VT-owned helper as Instance.
pub export fn hvt_copy_graphics(raw: ?*const c.hvt_terminal, history: u32, images: ?[*]c.hvt_image, image_capacity: usize, placements: ?[*]c.hvt_image_placement, placement_capacity: usize, out: ?*c.hvt_graphics) u32 {
    const result = out orelse return c.HVT_INVALID_ARGUMENT;
    result.* = std.mem.zeroes(c.hvt_graphics);
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    native.graphics.copyManifest(owner.observation(constant(value)), history, images, image_capacity, placements, placement_capacity, result) catch |err| return failure(err);
    return c.HVT_OK;
}
/// Copies exact current image bytes, never a terminal-owned pointer.
pub export fn hvt_copy_image_pixels(raw: ?*const c.hvt_terminal, revision: u64, id: u32, generation: u64, bytes: ?[*]u8, capacity: usize, out: ?*usize) u32 {
    const required = out orelse return c.HVT_INVALID_ARGUMENT;
    required.* = 0;
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    native.graphics.copyPixels(owner.observation(constant(value)), revision, id, generation, bytes, capacity, required) catch |err| return failure(err);
    return c.HVT_OK;
}

/// Allocates an immutable canonical logical-output result independent of source lifetime.
pub export fn hvt_output_open(version: u32, raw: ?*const c.hvt_terminal, cursor: u64, max_entries: u16, max_bytes: usize, out: ?*?*c.hvt_output) u32 {
    if (version != c.HVT_NATIVE_VERSION) return c.HVT_VERSION_MISMATCH;
    const slot = out orelse return c.HVT_INVALID_ARGUMENT;
    if (slot.* != null) return c.HVT_INVALID_ARGUMENT;
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    const result = native.logical_output.create(heap, owner.observation(constant(value)), cursor, max_entries, max_bytes) catch |err| return failure(err);
    // zig-audit: acknowledge ptr_cast
    // reason: Only the exact VT-owned immutable result is published as its matching C handle.
    slot.* = @ptrCast(result);
    return c.HVT_OK;
}
/// Returns immutable result-owned spans; zeros fixed output before null rejection.
pub export fn hvt_output_read(raw: ?*const c.hvt_output, out: ?*c.hvt_output_view) u32 {
    const result = out orelse return c.HVT_INVALID_ARGUMENT;
    result.* = std.mem.zeroes(c.hvt_output_view);
    const value = raw orelse return c.HVT_INVALID_ARGUMENT;
    // zig-audit: acknowledge ptr_cast
    // reason: The matching C result handle lends only the exact optional native Owner.
    result.* = native.logical_output.read(@ptrCast(value));
    return c.HVT_OK;
}
/// Clears and releases one result after all immutable borrows end; nulls are no-ops.
pub export fn hvt_output_release(out: ?*?*c.hvt_output) void {
    const slot = out orelse return;
    const value = slot.* orelse return;
    slot.* = null;
    // zig-audit: acknowledge ptr_cast
    // reason: Only constructor-owned result handles enter the exact native destructor.
    native.logical_output.destroy(@ptrCast(value));
}
