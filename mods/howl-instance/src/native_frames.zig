//! Native backend endpoint lifetime and bulk projection over one immutable Instance lease.
//! Producer opens endpoints; exactly one backend thread acquires/reads/releases frames.
const std = @import("std");
const instance = @import("howl_instance");
/// Render owns the foreign payload schemas and projection.
pub const render = @import("howl_render_native");
const terminal = instance.render.terminal;
/// Exact Instance-owned foreign envelope.
pub const Info = @import("instance_native").c.hi_frame_info;
/// An opaque endpoint pins its publication exchange even when no frame is leased.
// zig-audit: acknowledge opaque_type
// reason: Only this module owns the endpoint allocation and its matching exchange borrow/lease.
pub const Stream = opaque {};
const State = struct {
    allocator: std.mem.Allocator,
    exchange: *instance.RenderExchange,
    lease: ?instance.RenderLease = null,
};
/// Bounded allocation and single-backend admission failures.
pub const OpenError = std.mem.Allocator.Error || error{ PresentationUnavailable, PublicationBorrowed };
/// Explicit backend release outcomes; invalid/busy feedback leaves the lease live.
pub const ReleaseError = error{ NoPendingFrame, InvalidResidency, FeedbackBusy };

fn state(raw: *Stream) *State {
    // zig-audit: acknowledge ptr_cast
    // reason: Only this module creates the allocator-owned State behind a matching live Stream.
    // zig-audit: acknowledge align_cast
    // reason: The matching Stream constructor preserves State's original allocation alignment.
    return @ptrCast(@alignCast(raw));
}
/// Opens on the producer thread before handing only this endpoint to the backend.
/// Parent destruction returns busy until close; callers publish the first new cut explicitly.
pub fn open(allocator: std.mem.Allocator, owner: *instance.Instance) OpenError!*Stream {
    const value = try allocator.create(State);
    errdefer allocator.destroy(value);
    const exchange = try instance.borrowRenderExchange(owner);
    value.* = .{ .allocator = allocator, .exchange = exchange };
    // zig-audit: acknowledge ptr_cast
    // reason: The module-owned State allocation is published only through its opaque endpoint.
    return @ptrCast(value);
}
/// Closes on the backend after it stops using all borrowed pixels/frame data.
/// Pending work is abandoned; dropping the parent borrow is the last exchange access.
pub fn close(raw: *Stream) void {
    const value = state(raw);
    if (value.lease) |*lease| lease.abandon();
    const exchange = value.exchange;
    const allocator = value.allocator;
    allocator.destroy(value);
    instance.releaseRenderExchange(exchange);
}
/// Claims the newest unread immutable frame without blocking canonical service.
pub fn acquire(raw: *Stream) error{ PendingFrame, NoFrame, FrameTooLarge }!void {
    const value = state(raw);
    if (value.lease != null) return error.PendingFrame;
    value.lease = instance.acquirePublishedFrame(value.exchange) orelse return error.NoFrame;
    const frame = value.lease.?.value;
    checkCounts(frame.commands.len, frame.content_command_count, frame.uploads.len, frame.removals.len) catch |failure| {
        abandon(raw);
        return failure;
    };
}

// Validate the advertised native envelope before retaining it for any foreign reader.
fn checkCounts(commands_count: usize, content_count: usize, uploads_count: usize, removals_count: usize) error{FrameTooLarge}!void {
    const maximum = std.math.maxInt(u32);
    if (commands_count > maximum or content_count > maximum or uploads_count > maximum or removals_count > maximum)
        return error.FrameTooLarge;
}

test "native envelope counts accept the exact u32 boundary and reject boundary plus one" {
    const maximum: usize = std.math.maxInt(u32);
    try checkCounts(maximum, maximum, maximum, maximum);
    if (comptime @bitSizeOf(usize) > 32) {
        try std.testing.expectError(error.FrameTooLarge, checkCounts(maximum + 1, 0, 0, 0));
        try std.testing.expectError(error.FrameTooLarge, checkCounts(0, maximum + 1, 0, 0));
        try std.testing.expectError(error.FrameTooLarge, checkCounts(0, 0, maximum + 1, 0));
        try std.testing.expectError(error.FrameTooLarge, checkCounts(0, 0, 0, maximum + 1));
    }
}
/// Borrows immutable publication data only while this endpoint retains its lease.
pub fn pending(raw: *Stream) ?*const instance.PublishedFrame {
    const value = state(raw);
    if (value.lease) |*lease| return &lease.value;
    return null;
}
/// Reports exact accepted backend resources then releases the frame.
/// No publication credit, clock, window or renderer scheduling lives here.
pub fn release(raw: *Stream, residency: []const terminal.Residency) ReleaseError!void {
    const value = state(raw);
    const lease = if (value.lease) |*held| held else return error.NoPendingFrame;
    lease.reportResidency(residency) catch |failure| {
        return if (failure == error.ResidencyMailboxBusy) error.FeedbackBusy else error.InvalidResidency;
    };
    lease.abandon();
    value.lease = null;
}
/// Abandons only a candidate which established no new backend resource state.
pub fn abandon(raw: *Stream) void {
    const value = state(raw);
    if (value.lease) |*lease| lease.abandon();
    value.lease = null;
}
/// Native payload projection and missing-lease rejection.
pub const CopyError = render.Error || error{NoPendingFrame};

/// Bulk copies all commands into caller storage; no Zig union layout crosses the boundary.
pub fn copyCommands(raw: *Stream, out: []render.CommandInfo) CopyError![]const render.CommandInfo {
    const frame = pending(raw) orelse return error.NoPendingFrame;
    return render.commands(frame.commands, out);
}
/// Bulk copies upload metadata and borrows its immutable pixel spans until release.
pub fn copyUploads(raw: *Stream, out: []render.Upload) CopyError![]const render.Upload {
    const frame = pending(raw) orelse return error.NoPendingFrame;
    return render.uploads(frame.uploads, frame.pixels, out);
}
/// Bulk copies exact resource retirement records into caller-owned storage.
pub fn copyRemovals(raw: *Stream, out: []render.RemovalInfo) CopyError![]const render.RemovalInfo {
    const frame = pending(raw) orelse return error.NoPendingFrame;
    return render.removals(frame.removals, out);
}

/// Copies a complete immutable envelope while the endpoint holds its frame.
pub fn info(raw: *Stream) error{NoPendingFrame}!Info {
    const frame = pending(raw) orelse return error.NoPendingFrame;
    return .{
        .sequence = frame.sequence,
        .presentation_generation = frame.presentation_generation,
        .revision = frame.revision,
        .content_revision = frame.content_revision,
        .terminal_revision = frame.terminal_revision,
        .command_count = @intCast(frame.commands.len),
        .content_command_count = @intCast(frame.content_command_count),
        .upload_count = @intCast(frame.uploads.len),
        .removal_count = @intCast(frame.removals.len),
        .history_offset = frame.history_offset,
        .history_count = frame.history_count,
        .history_row_base = frame.history_row_base,
        .background_rgba = render.background(frame.commands, frame.surface),
        .surface_width = frame.surface.width,
        .surface_height = frame.surface.height,
        .cell_width = frame.cell_size.width,
        .cell_height = frame.cell_size.height,
        .alternate_screen = @intFromBool(frame.alternate_screen),
        .reserved = @splat(0),
    };
}
