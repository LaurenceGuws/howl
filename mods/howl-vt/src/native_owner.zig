//! Optional stable native owner for a caller-driven canonical VT.
//! No process, transport, scheduler or presentation lifetime enters this owner.
const std = @import("std");
const vt = @import("howl_vt");
const Terminal = vt.Terminal;
const c = @import("vt_native_types");
const queries = @import("native_queries.zig");

/// Canonical failures plus explicit boundary admission/capacity errors.
pub const Error = Terminal.InitError || Terminal.FeedError || Terminal.ResizeError ||
    Terminal.InputError || Terminal.ReplyConsumeError || Terminal.ConsumeConsequenceError ||
    Terminal.ClipboardReplyError || Terminal.PointerShapeReplyError ||
    Terminal.ColorPreferenceReplyError || Terminal.ContainerReplyError || queries.Error ||
    error{ InvalidArgument, ResourceLimit, BufferTooSmall, StaleRequest, RequestMismatch };

/// One owner; only these operations may mutate its private canonical Terminal.
// zig-audit: acknowledge opaque_type
// reason: Foreign/native callers receive lifecycle and const observation capabilities, not mutable Terminal storage.
pub const Owner = opaque {};
const State = struct { allocator: std.mem.Allocator, terminal: Terminal };

fn state(value: *Owner) *State {
    // zig-audit: acknowledge ptr_cast
    // reason: Only matching constructor-owned State allocations become Owner handles.
    // zig-audit: acknowledge align_cast
    // reason: The constructor-owned State alignment survives its opaque view.
    return @ptrCast(@alignCast(value));
}
fn stateConst(value: *const Owner) *const State {
    // zig-audit: acknowledge ptr_cast
    // reason: This const Owner is the matching constructor-owned State allocation.
    // zig-audit: acknowledge align_cast
    // reason: The constructor-owned State alignment survives its const opaque view.
    return @ptrCast(@alignCast(value));
}

comptime {
    if (@sizeOf(Terminal.InputScratch) != c.HVT_INPUT_BUFFER_BYTES)
        @compileError("Review native input capacity when canonical scratch changes");
    if (@typeInfo(vt.MutationSet).@"struct".field_names.len != 8)
        @compileError("Review native mutation bits when canonical fields change");
}

fn geometry(rows: u16, columns: u16, width: u32, height: u32) Error!?Terminal.CellPixelSize {
    if (rows == 0 or columns == 0 or (width == 0) != (height == 0)) return error.InvalidArgument;
    if (@as(u64, rows) * columns > c.HVT_MAX_SCREEN_CELLS) return error.ResourceLimit;
    return if (width == 0) null else .{ .width = width, .height = height };
}

/// Validates before allocation and constructs in place at a stable address.
pub fn create(allocator: std.mem.Allocator, config: *const c.hvt_config) Error!*Owner {
    if (config.reserved != 0) return error.InvalidArgument;
    const pixels = try geometry(config.rows, config.columns, config.cell_width, config.cell_height);
    const storage = try allocator.create(State);
    errdefer allocator.destroy(storage);
    storage.allocator = allocator;
    try Terminal.initWithHistoryInto(&storage.terminal, allocator, config.rows, config.columns, config.history_rows);
    errdefer storage.terminal.deinit();
    if (pixels) |value| try storage.terminal.setCellPixelSize(value.width, value.height);
    // zig-audit: acknowledge ptr_cast
    // reason: Publish only this complete matching State allocation as its opaque owner.
    return @ptrCast(storage);
}

/// Releases canonical state and the owner exactly once after all calls finish.
pub fn destroy(value: *Owner) void {
    const storage = state(value);
    const allocator = storage.allocator;
    storage.terminal.deinit();
    allocator.destroy(storage);
}

/// Lends only canonical const observation to synchronous optional adapters.
pub fn observation(value: *const Owner) *const Terminal.Observation {
    return stateConst(value).terminal.observation();
}

/// Copies coherent actual viewport facts; requested history is canonically clamped.
pub fn observe(value: *const Owner, history: u32) c.hvt_state {
    const terminal = &stateConst(value).terminal;
    const view = terminal.semanticView(history);
    const pixels = terminal.cellPixelSize();
    return .{
        .terminal_revision = terminal.semanticSequence(),
        .content_revision = terminal.contentSequence(),
        .history_row_base = view.history_row_base,
        .history_count = view.history_count,
        .history_offset = view.history_offset,
        .cell_width = if (pixels) |pixel| pixel.width else 0,
        .cell_height = if (pixels) |pixel| pixel.height else 0,
        .rows = view.rows,
        .columns = view.cols,
        .cursor_row = view.cursor_row,
        .cursor_column = view.cursor_col,
        .alternate_screen = @intFromBool(view.is_alternate_screen),
        .cursor_visible = @intFromBool(view.cursor_visible),
        .synchronized_output = @intFromBool(terminal.synchronizedOutput()),
        .reserved = 0,
    };
}

fn mutationBits(value: vt.MutationSet) u32 {
    return (if (value.cursor) @as(u32, c.HVT_MUTATION_CURSOR) else 0) |
        (if (value.text) @as(u32, c.HVT_MUTATION_TEXT) else 0) |
        (if (value.viewport) @as(u32, c.HVT_MUTATION_VIEWPORT) else 0) |
        (if (value.images) @as(u32, c.HVT_MUTATION_IMAGES) else 0) |
        (if (value.mode) @as(u32, c.HVT_MUTATION_MODE) else 0) |
        (if (value.title) @as(u32, c.HVT_MUTATION_TITLE) else 0) |
        (if (value.icon) @as(u32, c.HVT_MUTATION_ICON) else 0) |
        (if (value.history_loss) @as(u32, c.HVT_MUTATION_HISTORY_LOSS) else 0);
}

/// Returns exact successful progress only; canonical errors may have applied a prefix.
pub fn feed(value: *Owner, bytes: []const u8, timestamp: u64) Error!c.hvt_feed_progress {
    if (bytes.len > c.HVT_MAX_INPUT_BYTES) return error.ResourceLimit;
    const terminal = &state(value).terminal;
    const progress = try terminal.feedAtServiceBoundary(bytes, timestamp);
    return .{
        .terminal_revision = terminal.semanticSequence(),
        .content_revision = terminal.contentSequence(),
        .consumed = progress.consumed,
        .mutations = mutationBits(progress.summary.mutations),
        .synchronized_ended = @intFromBool(progress.summary.synchronized_output.ended),
        .trailing_effect = @intFromBool(progress.summary.synchronized_output.trailing_effect),
        .held = @intFromBool(terminal.synchronizedOutput()),
        .reserved = 0,
    };
}

/// Commits topology, optional pixels, replies and revisions as one transaction.
pub fn resize(value: *Owner, rows: u16, columns: u16, width: u32, height: u32) Error!void {
    const pixels = try geometry(rows, columns, width, height);
    var candidate = try state(value).terminal.prepareResizeGeometry(rows, columns, pixels);
    defer candidate.deinit();
    candidate.commit();
}

/// Applies canonical RIS; preserved queued work still belongs to the caller.
pub fn reset(value: *Owner) void {
    state(value).terminal.hardReset();
}

/// Advances canonical image animation using caller-owned monotonic time.
pub fn serviceAnimations(value: *Owner, timestamp: u64) c.hvt_animation {
    const result = state(value).terminal.serviceAnimations(timestamp);
    return .{ .next_ms = result.next_ms orelse 0, .changed = @intFromBool(result.changed), .deadline_present = @intFromBool(result.next_ms != null), .reserved = @splat(0) };
}

/// Returns the mandatory admission extent, independently of current encoding modes.
pub fn inputCapacity(event: Terminal.InputEvent) Error!usize {
    return switch (event) {
        .paste => |bytes| if (bytes.len > c.HVT_MAX_INPUT_BYTES) error.ResourceLimit else bytes.len + c.HVT_PASTE_EXTRA_BYTES,
        .bytes => |bytes| if (bytes.len > c.HVT_MAX_INPUT_BYTES) error.ResourceLimit else bytes.len,
        else => c.HVT_INPUT_BUFFER_BYTES,
    };
}

fn checkDisjoint(input: []const u8, output: []u8) Error!void {
    if (input.len == 0 or output.len == 0) return;
    const input_start = @intFromPtr(input.ptr);
    const output_start = @intFromPtr(output.ptr);
    const input_end = std.math.add(usize, input_start, input.len) catch return error.InvalidArgument;
    const output_end = std.math.add(usize, output_start, output.len) catch return error.InvalidArgument;
    if (input_start < output_end and output_start < input_end) return error.InvalidArgument;
}

/// Checks output before stateful encoding, copies only actual bytes, retains no borrow.
pub fn encode(value: *Owner, event: Terminal.InputEvent, output: []u8) Error!usize {
    const extent = try inputCapacity(event);
    if (output.len < extent) return error.BufferTooSmall;
    switch (event) {
        .paste, .bytes => |bytes| try checkDisjoint(bytes, output[0..extent]),
        else => {},
    }
    const storage = state(value);
    var scratch: Terminal.InputScratch = .{};
    var encoded = try storage.terminal.encodeInput(storage.allocator, &scratch, event);
    defer encoded.deinit();
    std.debug.assert(encoded.bytes.len <= extent);
    @memcpy(output[0..encoded.bytes.len], encoded.bytes);
    return encoded.bytes.len;
}

/// Copies complete queued reply bytes without consuming or borrowing them.
pub fn copyReplies(value: *const Owner, output: []u8, required: *usize) Error!void {
    required.* = 0;
    if (output.len > c.HVT_MAX_COPY_BYTES) return error.ResourceLimit;
    const bytes = stateConst(value).terminal.replyBytes();
    required.* = bytes.len;
    if (output.len < bytes.len) return error.BufferTooSmall;
    @memcpy(output[0..bytes.len], bytes);
}

/// Zero is a true no-op; invalid prefixes leave the complete queue unchanged.
pub fn consumeReplies(value: *Owner, count: usize) Error!void {
    if (count == 0) return;
    try state(value).terminal.consumeReplyBytes(count);
}

/// Reuses canonical native search with the same injectable owner allocator.
pub fn search(value: *const Owner, query: []const u8, reverse: bool, origin: bool, row: i32, column: u16, output: *c.hvt_search_match) Error!void {
    return queries.search(observation(value), stateConst(value).allocator, query, reverse, origin, row, column, output);
}

/// Reuses complete canonical extraction without lending a live terminal.
pub fn copySelection(value: *const Owner, start_row: i32, start_column: u16, end_row: i32, end_column: u16, columns: u16, alternate: bool, output: []u8) Error!usize {
    return queries.copySelection(observation(value), stateConst(value).allocator, start_row, start_column, end_row, end_column, columns, alternate, output);
}

/// Acknowledges only a consumable exact FIFO head.
pub fn consumeRequest(value: *Owner, id: u64) Error!void {
    try state(value).terminal.consumeConsequence(id);
}
fn replyBytes(bytes: []const u8) Error!void {
    if (bytes.len > c.HVT_MAX_INPUT_BYTES) return error.ResourceLimit;
}
// Identity precedes family: an unrelated ID remains stale even for a different head kind.
fn requireRequest(value: *Owner, id: u64, family: std.meta.Tag(Terminal.Consequence)) Error!void {
    const head = state(value).terminal.consequenceHead() orelse return error.StaleRequest;
    if (head.id() != id) return error.StaleRequest;
    if (std.meta.activeTag(head) != family) return error.RequestMismatch;
}
/// Replies atomically to a matching OSC52 query; other clipboard kinds are explicit mismatch.
pub fn replyClipboard(value: *Owner, id: u64, bytes: []const u8) Error!void {
    try replyBytes(bytes);
    try requireRequest(value, id, .clipboard);
    if (!try state(value).terminal.replyClipboard(id, bytes)) return error.RequestMismatch;
}
/// Supplies only one matching pointer query; canonical limits and rollback remain authoritative.
pub fn replyPointerShape(value: *Owner, id: u64, bytes: []const u8) Error!void {
    try replyBytes(bytes);
    try requireRequest(value, id, .pointer_shape);
    try state(value).terminal.replyPointerShape(id, bytes);
}
/// Supplies one typed preference without inventing host policy.
pub fn replyColorPreference(value: *Owner, id: u64, preference: Terminal.ColorSchemePreference) Error!void {
    try requireRequest(value, id, .color_preference_query);
    try state(value).terminal.replyColorPreference(id, preference);
}
/// Supplies one typed container response without wire serialization.
pub fn replyContainer(value: *Owner, id: u64, reply: Terminal.ContainerReply) Error!void {
    if (reply == .icon_title) try replyBytes(reply.icon_title);
    try requireRequest(value, id, .container);
    try state(value).terminal.replyContainer(id, reply);
}
/// Declines only an exact matching container query.
pub fn declineContainer(value: *Owner, id: u64) Error!void {
    try requireRequest(value, id, .container);
    try state(value).terminal.declineContainerQuery(id);
}
