//! Optional source-independent immutable canonical logical-output snapshots.
const std = @import("std");
const Terminal = @import("howl_vt").Terminal;
const c = @import("vt_native_types");

/// Exact allocation and scalar-limit admission failures.
pub const Error = error{ OutOfMemory, InvalidArgument };
/// One immutable result; copying a pointer creates no owner.
/// Returned byte/loss borrows end at destroy, independently of source lifetime.
// zig-audit: acknowledge opaque_type
// reason: Only this module owns result allocation, copied storage and exact release.
pub const Owner = opaque {};
const State = struct {
    allocator: std.mem.Allocator,
    view: c.hvt_output_view,
    text: []u8,
    open_line: []u8,
    losses: []c.hvt_output_loss,
};

comptime {
    if (Terminal.maximum_logical_output_bytes != c.HVT_MAX_COPY_BYTES)
        @compileError("Canonical logical-output byte limit changed: review native admission");
}
fn state(value: *Owner) *State {
    // zig-audit: acknowledge ptr_cast
    // reason: Only constructor-owned State allocations are published as this Owner.
    // zig-audit: acknowledge align_cast
    // reason: The matching State allocation preserves its alignment through the opaque handle.
    return @ptrCast(@alignCast(value));
}
fn stateConst(value: *const Owner) *const State {
    // zig-audit: acknowledge ptr_cast
    // reason: This matching const Owner lends only immutable constructor-owned State.
    // zig-audit: acknowledge align_cast
    // reason: Construction preserves the private State alignment.
    return @ptrCast(@alignCast(value));
}

/// Copies one exact canonical outcome; no source reference survives this call.
/// Validate limits before allocating. DATA transfers copied text/open storage
/// only after complete native loss conversion; publication has no fallible tail.
pub fn create(allocator: std.mem.Allocator, observed: *const Terminal.Observation, cursor: u64, max_entries: u16, max_bytes: usize) Error!*Owner {
    if (max_entries == 0 or max_bytes == 0 or max_bytes > c.HVT_MAX_COPY_BYTES) return error.InvalidArgument;
    const storage = try allocator.create(State);
    errdefer allocator.destroy(storage);
    storage.* = .{
        .allocator = allocator,
        .view = std.mem.zeroes(c.hvt_output_view),
        .text = &.{},
        .open_line = &.{},
        .losses = &.{},
    };
    const result = observed.copyLogicalOutput(allocator, cursor, max_entries, max_bytes) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidLimit => error.InvalidArgument,
    };
    switch (result) {
        .output => |value| {
            var output = value;
            errdefer output.deinit();
            const losses = try allocator.alloc(c.hvt_output_loss, output.losses.len);
            errdefer allocator.free(losses);
            for (losses, output.losses) |*native, loss| native.* = .{
                .id = loss.id,
                .byte_count = loss.byte_count,
                .reason = switch (loss.reason) {
                    .line_too_long => c.HVT_OUTPUT_LOSS_LINE_TOO_LONG,
                },
                .reserved = @splat(0),
            };
            // No fallible work remains. Transfer the two canonical byte slices,
            // release only canonical loss storage, and retain the native records.
            storage.text = output.text;
            storage.open_line = output.open_line;
            storage.losses = losses;
            allocator.free(output.losses);
            storage.view = .{
                .text = if (storage.text.len == 0) null else storage.text.ptr,
                .text_len = storage.text.len,
                .open_line = if (storage.open_line.len == 0) null else storage.open_line.ptr,
                .open_line_len = storage.open_line.len,
                .losses = if (losses.len == 0) null else losses.ptr,
                .loss_count = losses.len,
                .terminal_revision = output.semantic_sequence,
                .oldest = output.oldest,
                .cursor = output.cursor,
                .newest = output.newest,
                .reported_id = 0,
                .line_count = output.line_count,
                .kind = c.HVT_OUTPUT_DATA,
                .more = @intFromBool(output.more),
                .open_line_omitted = @intFromBool(output.open_line_omitted),
                .reserved = @splat(0),
            };
        },
        .cursor_stale => |id| {
            storage.view.kind = c.HVT_OUTPUT_CURSOR_STALE;
            storage.view.reported_id = id;
        },
        .cursor_ahead => |id| {
            storage.view.kind = c.HVT_OUTPUT_CURSOR_AHEAD;
            storage.view.reported_id = id;
        },
        .line_too_long => |id| {
            storage.view.kind = c.HVT_OUTPUT_LINE_TOO_LONG;
            storage.view.reported_id = id;
        },
        .open_line_too_long => {
            storage.view.kind = c.HVT_OUTPUT_OPEN_LINE_TOO_LONG;
        },
    }
    // zig-audit: acknowledge ptr_cast
    // reason: Publish only the completely initialized matching State as its opaque Owner.
    return @ptrCast(storage);
}

/// Copies immutable metadata and result-owned spans; no source access or allocation.
pub fn read(value: *const Owner) c.hvt_output_view {
    return stateConst(value).view;
}

/// Releases only result-owned copied storage using its originating allocator.
pub fn destroy(value: *Owner) void {
    const storage = state(value);
    const allocator = storage.allocator;
    allocator.free(storage.losses);
    allocator.free(storage.open_line);
    allocator.free(storage.text);
    allocator.destroy(storage);
}
