//! Owns Host render orchestration from input, session, terminal, and Composer
//! coordination through physical replay, deadlines, sole Vulkan mutation, and
//! DRM release observation.

const std = @import("std");
const c = @import("renderer_c");
const linux = std.os.linux;
const window_render_boundary = @import("window_render_boundary.zig");

const terminal_retained_resource_limit: usize = 512 + 128 + 8;
const chrome_retained_resource_limit: usize = 512;
const frame_resource_limit: usize = 2048;
const frame_command_limit: usize = 32_768;
const howl_vk = @import("howl_vk");
const vk = howl_vk.abi;
const render_api = @import("howl_render");
const session_chrome_adapter = @import("session_chrome_adapter");
const session = @import("session_domain");
const vk_surface = howl_vk.surface;
const replay_command_limit: usize = vk_surface.max_commands;
const replay_pin_limit: usize = 2_048;
const input_actions = @import("input_actions");
const wayland = @import("howl_wayland");
const terminal_handoff = @import("terminal_handoff");
const dev_config = @import("dev_config");
const chrome_appearance = session_chrome_adapter.Appearance{
    .style = .{
        .foreground = .{ .r = 230, .g = 235, .b = 245, .a = 255 },
        .background = .{ .r = 20, .g = 24, .b = 32, .a = 255 },
        .border = .{ .r = 80, .g = 90, .b = 110, .a = 255 },
    },
    .tab_active_background = .{ .r = 48, .g = 72, .b = 112, .a = 255 },
    .tab_inactive_background = .{ .r = 28, .g = 34, .b = 46, .a = 255 },
};

const gpu_memory_limit: u64 = 512 * 1024 * 1024;
const configured_terminal_base_points: f64 = 12.0;
const render_open_flags = linux.O{ .ACCMODE = .RDWR, .CLOEXEC = true };
const render_etime: c_int = -@as(c_int, @intCast(@backingInt(std.posix.E.TIME)));

const RetiredTerminalSource = struct {
    pane: render_api.chrome.PaneId,
    source: render_api.canvas.SourceId,
};

const ChromeRetry = struct {
    update: render_api.canvas.ProducerUpdate,
    surface: render_api.canvas.Size,
    terminal_placements: [terminal_handoff.visible_member_limit]render_api.canvas.Composer.Placement,
    terminal_count: u8,
    visible_revision: ?u64,
    topology_revision: ?terminal_handoff.LifecycleRevision,
};

/// Retains Kitty-shaped trail presentation facts for one active tab.
///
/// The record is backend-neutral and never writes a position back into VT.
const CursorTrail = struct {
    needs_render: bool = false,
    updated_at: u64 = 0,
    opacity: f32 = 0,
    corner_x: [4]f32 = .{ 0, 0, 0, 0 },
    corner_y: [4]f32 = .{ 0, 0, 0, 0 },
    cursor_edge_x: [2]f32 = .{ 0, 0 },
    cursor_edge_y: [2]f32 = .{ 0, 0 },
    /// Accumulated clip of the physically accepted transition endpoints.  It
    /// remains through retargets while a new target is admitted so the trail
    /// can span every still-visible outgoing pane.
    endpoint_clip: vk_surface.Rect = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    /// Clip of the newly admitted endpoint.  It becomes endpoint_clip only
    /// after an accepted frame settles the trail exactly at that endpoint.
    target_clip: vk_surface.Rect = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
};

const TrailSlot = struct {
    id: ?session.TabId = null,
    trail: CursorTrail = .{},
    initialized: bool = false,
};

const TrailTransferCandidate = struct {
    from: session.TabId,
    to: session.TabId,
    trail: CursorTrail = .{},
    initialized: bool = false,
    deadline: ?u64 = null,
};

const AcceptedTrailSurface = struct {
    owner: session.TabId,
    trail: CursorTrail,
    initialized: bool,
};

// Kitty's retained vertex order: right-top, right-bottom, left-bottom,
// left-top.  Initialization and every target update use these same identities.
const trail_corner_x = [4]usize{ 1, 1, 0, 0 };
const trail_corner_y = [4]usize{ 0, 1, 1, 0 };
const trail_frame_interval_ns: u64 = std.time.ns_per_s / 60;

const CursorTrailEdges = struct {
    x: [2]f32,
    y: [2]f32,
};

fn checkedTrailClipUnion(
    left: vk_surface.Rect,
    right: vk_surface.Rect,
) !vk_surface.Rect {
    if (left.width == 0 or left.height == 0 or right.width == 0 or right.height == 0)
        return error.InvalidFrame;
    const left_right = std.math.add(i64, @as(i64, left.x), @as(i64, left.width)) catch
        return error.InvalidFrame;
    const left_bottom = std.math.add(i64, @as(i64, left.y), @as(i64, left.height)) catch
        return error.InvalidFrame;
    const right_right = std.math.add(i64, @as(i64, right.x), @as(i64, right.width)) catch
        return error.InvalidFrame;
    const right_bottom = std.math.add(i64, @as(i64, right.y), @as(i64, right.height)) catch
        return error.InvalidFrame;
    const x = @min(@as(i64, left.x), @as(i64, right.x));
    const y = @min(@as(i64, left.y), @as(i64, right.y));
    const max_x = @max(left_right, right_right);
    const max_y = @max(left_bottom, right_bottom);
    if (x < 0 or y < 0 or
        max_x <= x or max_y <= y or
        max_x > std.math.maxInt(i32) or max_y > std.math.maxInt(i32))
        return error.InvalidFrame;
    const width = max_x - x;
    const height = max_y - y;
    if (width > std.math.maxInt(u32) or height > std.math.maxInt(u32))
        return error.InvalidFrame;
    return .{
        .x = @intCast(x),
        .y = @intCast(y),
        .width = @intCast(width),
        .height = @intCast(height),
    };
}

fn prepareTrailRetargetClip(
    trail: *CursorTrail,
    next_clip: vk_surface.Rect,
    active: bool,
) !void {
    var candidate = trail.*;
    if (active) {
        candidate.endpoint_clip = try checkedTrailClipUnion(
            candidate.endpoint_clip,
            candidate.target_clip,
        );
    }
    const admitted_clip = try checkedTrailClipUnion(candidate.endpoint_clip, next_clip);
    if (admitted_clip.width == 0 or admitted_clip.height == 0)
        return error.InvalidFrame;
    trail.* = candidate;
}

fn trailEdges(overlay: vk_surface.CursorOverlay) !CursorTrailEdges {
    const right = std.math.add(i32, overlay.rect.x, @intCast(overlay.rect.width)) catch
        return error.InvalidFrame;
    const bottom = std.math.add(i32, overlay.rect.y, @intCast(overlay.rect.height)) catch
        return error.InvalidFrame;
    return .{
        .x = .{ @floatFromInt(overlay.rect.x), @floatFromInt(right) },
        .y = .{ @floatFromInt(overlay.rect.y), @floatFromInt(bottom) },
    };
}

fn trailSnap(
    trail: *CursorTrail,
    edges: CursorTrailEdges,
    endpoint_clip: vk_surface.Rect,
    now: u64,
    visible: bool,
) void {
    trail.cursor_edge_x = edges.x;
    trail.cursor_edge_y = edges.y;
    for (0..4) |index| {
        trail.corner_x[index] = edges.x[trail_corner_x[index]];
        trail.corner_y[index] = edges.y[trail_corner_y[index]];
    }
    trail.updated_at = now;
    trail.opacity = if (visible) 1.0 else 0.0;
    trail.needs_render = false;
    trail.endpoint_clip = endpoint_clip;
    trail.target_clip = endpoint_clip;
}

fn trailPrepareTargetAt(
    trail: *CursorTrail,
    overlay: vk_surface.CursorOverlay,
    cell_size: render_api.canvas.Size,
    now: u64,
    movement_timestamp_ns: u64,
    policy: dev_config.CursorPresentationPolicy,
    trail_deadline_out: *?u64,
    initialized: *bool,
) !void {
    const edges = try trailEdges(overlay);
    const delay_ns = std.math.mul(u64, policy.trail_delay_ms, std.time.ns_per_ms) catch
        return error.InvalidFrame;
    const admission_base = if (movement_timestamp_ns == 0)
        now
    else
        @min(movement_timestamp_ns, now);
    const candidate_deadline = std.math.add(u64, admission_base, delay_ns) catch
        return error.InvalidFrame;
    if (!initialized.*) {
        trailSnap(trail, edges, overlay.clip, now, overlay.visible);
        initialized.* = true;
        trail_deadline_out.* = null;
        return;
    }
    const same_target = std.meta.eql(trail.cursor_edge_x, edges.x) and
        std.meta.eql(trail.cursor_edge_y, edges.y);
    if (overlay.visible and same_target and trail_deadline_out.* != null) return;
    if (overlay.visible and same_target and trail.opacity >= 1.0 and !trail.needs_render) {
        trail_deadline_out.* = null;
        return;
    }
    trail.cursor_edge_x = edges.x;
    trail.cursor_edge_y = edges.y;
    if (!overlay.visible) {
        trailSnap(trail, edges, overlay.clip, now, false);
        trail_deadline_out.* = null;
        return;
    }
    if (same_target and trail.opacity == 0 and !trail.needs_render) {
        trailSnap(trail, edges, overlay.clip, now, true);
        trail_deadline_out.* = null;
        return;
    }
    if (policy.trail_start_threshold_cells != 0 and !trail.needs_render and
        cell_size.width != 0 and cell_size.height != 0)
    {
        const dx = @as(i32, @intFromFloat(@round(
            (trail.corner_x[0] - edges.x[1]) / @as(f32, @floatFromInt(cell_size.width)),
        )));
        const dy = @as(i32, @intFromFloat(@round(
            (trail.corner_y[0] - edges.y[0]) / @as(f32, @floatFromInt(cell_size.height)),
        )));
        if (@abs(dx) + @abs(dy) <= policy.trail_start_threshold_cells) {
            trailSnap(trail, edges, overlay.clip, now, true);
            trail_deadline_out.* = null;
            return;
        }
    }
    // The old endpoint clip is retained in endpoint_clip; the target clip is
    // transferred only with the physical frame carrying this trail.
    trail.target_clip = overlay.clip;
    trail.updated_at = now;
    trail_deadline_out.* = @max(candidate_deadline, now);
}

fn trailPrepareTarget(
    trail: *CursorTrail,
    overlay: vk_surface.CursorOverlay,
    cell_size: render_api.canvas.Size,
    now: u64,
    policy: dev_config.CursorPresentationPolicy,
    trail_deadline_out: *?u64,
    initialized: *bool,
) !void {
    return trailPrepareTargetAt(
        trail,
        overlay,
        cell_size,
        now,
        now,
        policy,
        trail_deadline_out,
        initialized,
    );
}

fn trailAdvance(
    trail: *CursorTrail,
    now: u64,
    policy: dev_config.CursorPresentationPolicy,
    trail_deadline_out: *?u64,
) bool {
    if (trail_deadline_out.*) |value| if (now < value) return false;
    trail_deadline_out.* = null;
    const elapsed = now -| trail.updated_at;
    trail.updated_at = now;
    const dt = @as(f32, @floatFromInt(elapsed)) / @as(f32, @floatFromInt(std.time.ns_per_s));
    const fast = @as(f32, @floatCast(policy.trail_decay_seconds.start_seconds));
    const slow = @as(f32, @floatCast(policy.trail_decay_seconds.end_seconds));
    if (trail.opacity < 1.0 and slow > 0) {
        trail.opacity = @min(1.0, trail.opacity + dt / slow);
    }
    const target_x = trail.cursor_edge_x;
    const target_y = trail.cursor_edge_y;
    const center_x = (target_x[0] + target_x[1]) * 0.5;
    const center_y = (target_y[0] + target_y[1]) * 0.5;
    const diagonal = std.math.sqrt(
        (target_x[1] - target_x[0]) * (target_x[1] - target_x[0]) +
            (target_y[0] - target_y[1]) * (target_y[0] - target_y[1]),
    ) * 0.5;
    if (diagonal > 0 and dt > 0 and (fast > 0 or slow > 0)) {
        var dot: [4]f32 = undefined;
        var dx: [4]f32 = undefined;
        var dy: [4]f32 = undefined;
        var min_dot = std.math.floatMax(f32);
        var max_dot = -std.math.floatMax(f32);
        for (0..4) |index| {
            const tx = target_x[trail_corner_x[index]];
            const ty = target_y[trail_corner_y[index]];
            dx[index] = tx - trail.corner_x[index];
            dy[index] = ty - trail.corner_y[index];
            const distance = std.math.sqrt(dx[index] * dx[index] + dy[index] * dy[index]);
            if (distance <= 0) {
                dot[index] = 0;
            } else {
                dot[index] = (dx[index] * (tx - center_x) + dy[index] * (ty - center_y)) /
                    diagonal / distance;
            }
            min_dot = @min(min_dot, dot[index]);
            max_dot = @max(max_dot, dot[index]);
        }
        for (0..4) |index| {
            if (dx[index] == 0 and dy[index] == 0) continue;
            const decay = if (min_dot == max_dot)
                slow
            else
                slow + (fast - slow) * (dot[index] - min_dot) / (max_dot - min_dot);
            if (decay <= 0) {
                trail.corner_x[index] = target_x[trail_corner_x[index]];
                trail.corner_y[index] = target_y[trail_corner_y[index]];
                continue;
            }
            const step = 1.0 - std.math.exp2(-10.0 * dt / decay);
            trail.corner_x[index] += dx[index] * step;
            trail.corner_y[index] += dy[index] * step;
        }
    }
    // Kitty settles in physical coordinates.  A half-cell threshold leaves
    // a visibly detached trail on large fonts; the exact completion bound is
    // half a physical pixel on each axis.
    const x_threshold: f32 = 0.5;
    const y_threshold: f32 = 0.5;
    const previous_needs_render = trail.needs_render;
    trail.needs_render = false;
    var corners_settled = true;
    for (0..4) |index| {
        if (@abs(target_x[trail_corner_x[index]] - trail.corner_x[index]) > x_threshold or
            @abs(target_y[trail_corner_y[index]] - trail.corner_y[index]) > y_threshold)
        {
            corners_settled = false;
        }
    }
    if (corners_settled) {
        for (0..4) |index| {
            trail.corner_x[index] = target_x[trail_corner_x[index]];
            trail.corner_y[index] = target_y[trail_corner_y[index]];
        }
    } else {
        trail.needs_render = true;
    }
    const opacity_settled = trail.opacity == 0 or trail.opacity >= 1.0;
    if (!opacity_settled) trail.needs_render = true;
    if (trail.needs_render) {
        trail_deadline_out.* = std.math.add(u64, now, trail_frame_interval_ns) catch null;
    }
    return trail.needs_render or previous_needs_render;
}

test "cursor trail state follows Kitty delay, easing, threshold, and visibility" {
    const policy = dev_config.Config.defaults().presentationPolicy();
    const cell_size = render_api.canvas.Size{ .width = 10, .height = 20 };
    const base_overlay = vk_surface.CursorOverlay{
        .rect = .{ .x = 20, .y = 40, .width = 10, .height = 20 },
        .clip = .{ .x = 0, .y = 0, .width = 200, .height = 200 },
        .shape = .block,
        .color = .{ 0.45, 0.98, 0.56, 1 },
        .text_color = .{ 1, 1, 1, 1 },
        .visible = true,
    };
    var trail = CursorTrail{};
    var initialized = false;
    var trail_deadline: ?u64 = null;
    try trailPrepareTarget(&trail, base_overlay, cell_size, 100, policy, &trail_deadline, &initialized);
    try std.testing.expect(initialized);
    try std.testing.expectEqual(@as(f32, 1.0), trail.opacity);
    try std.testing.expect(trail_deadline == null);
    try std.testing.expectEqual(@as(f32, 30), trail.corner_x[0]);
    try std.testing.expectEqual(@as(f32, 40), trail.corner_y[0]);

    var moved = base_overlay;
    moved.rect.x += 30;
    try trailPrepareTarget(&trail, moved, cell_size, 200, policy, &trail_deadline, &initialized);
    try std.testing.expectEqual(@as(u64, 1_000_200), trail_deadline.?);
    try std.testing.expect(!trail.needs_render);
    try trailPrepareTarget(&trail, moved, cell_size, 300, policy, &trail_deadline, &initialized);
    try std.testing.expectEqual(@as(u64, 1_000_200), trail_deadline.?);
    const before = trail;
    try std.testing.expect(!trailAdvance(&trail, 500_000, policy, &trail_deadline));
    try std.testing.expectEqual(before, trail);
    try std.testing.expect(trailAdvance(&trail, 1_100_000, policy, &trail_deadline));
    try std.testing.expect(trail.needs_render);
    try std.testing.expect(trail.corner_x[0] > before.corner_x[0]);
    try std.testing.expect(trail_deadline.? > 1_100_000);
    try std.testing.expect(trailAdvance(&trail, 10_000_000_000, policy, &trail_deadline));
    try std.testing.expect(!trailAdvance(&trail, 10_000_000_001, policy, &trail_deadline));
    try std.testing.expectEqual([4]f32{ 60, 60, 50, 50 }, trail.corner_x);
    try std.testing.expectEqual([4]f32{ 40, 60, 60, 40 }, trail.corner_y);
    try std.testing.expectEqual(@as(f32, 1.0), trail.opacity);
    try std.testing.expect(trail_deadline == null);

    var timestamped = trail;
    var timestamped_initialized = true;
    var timestamped_deadline: ?u64 = null;
    var timestamped_target = moved;
    timestamped_target.rect.x += 10;
    try trailPrepareTargetAt(
        &timestamped,
        timestamped_target,
        cell_size,
        2_000_000,
        1_000_000,
        policy,
        &timestamped_deadline,
        &timestamped_initialized,
    );
    // The movement happened before Host acceptance, so the configured delay
    // is already elapsed and the candidate is due immediately.
    try std.testing.expectEqual(@as(u64, 2_000_000), timestamped_deadline.?);

    // Completion is a physical-pixel rule, not a cell-sized rule.  A
    // subpixel remainder must snap on the next due frame.
    var subpixel = trail;
    subpixel.corner_x = .{ 59.51, 60.49, 50.49, 49.51 };
    subpixel.corner_y = .{ 40.49, 59.51, 60.49, 39.51 };
    subpixel.needs_render = true;
    subpixel.updated_at = 0;
    var subpixel_deadline: ?u64 = null;
    try std.testing.expect(trailAdvance(&subpixel, 1, policy, &subpixel_deadline));
    try std.testing.expect(!trailAdvance(&subpixel, 2, policy, &subpixel_deadline));
    try std.testing.expectEqual([4]f32{ 60, 60, 50, 50 }, subpixel.corner_x);
    try std.testing.expectEqual([4]f32{ 40, 60, 60, 40 }, subpixel.corner_y);
    try std.testing.expect(subpixel_deadline == null);

    var hidden = moved;
    hidden.visible = false;
    try trailPrepareTarget(&trail, hidden, cell_size, 2_000_000, policy, &trail_deadline, &initialized);
    try std.testing.expectEqual(@as(f32, 0.0), trail.opacity);
    try std.testing.expect(!trail.needs_render);
    try std.testing.expect(trail_deadline == null);
    hidden.visible = true;
    try trailPrepareTarget(&trail, hidden, cell_size, 2_100_000, policy, &trail_deadline, &initialized);
    try std.testing.expectEqual(@as(f32, 1.0), trail.opacity);
    try std.testing.expectEqual(@as(f32, 60), trail.corner_x[0]);
    try std.testing.expect(trail_deadline == null);

    const accepted_before_overflow = trail;
    const deadline_before_overflow = trail_deadline;
    try std.testing.expectError(
        error.InvalidFrame,
        trailPrepareTarget(
            &trail,
            base_overlay,
            cell_size,
            std.math.maxInt(u64),
            policy,
            &trail_deadline,
            &initialized,
        ),
    );
    try std.testing.expectEqual(accepted_before_overflow, trail);
    try std.testing.expectEqual(deadline_before_overflow, trail_deadline);

    var threshold_policy = policy;
    threshold_policy.trail_start_threshold_cells = 4;
    trailSnap(
        &trail,
        .{ .x = .{ 20, 30 }, .y = .{ 40, 60 } },
        base_overlay.clip,
        3_000_000,
        true,
    );
    var near = base_overlay;
    near.rect.x += 10;
    try trailPrepareTarget(&trail, near, cell_size, 3_100_000, threshold_policy, &trail_deadline, &initialized);
    try std.testing.expectEqual(@as(f32, 40), trail.corner_x[0]);
    try std.testing.expect(trail_deadline == null);
}

fn trailCornersInsideClip(corner_x: [4]f32, corner_y: [4]f32, clip: vk_surface.Rect) bool {
    const right = @as(f32, @floatFromInt(clip.x)) + @as(f32, @floatFromInt(clip.width));
    const bottom = @as(f32, @floatFromInt(clip.y)) + @as(f32, @floatFromInt(clip.height));
    for (corner_x, corner_y) |x, y| {
        if (x < @as(f32, @floatFromInt(clip.x)) or x > right or
            y < @as(f32, @floatFromInt(clip.y)) or y > bottom)
            return false;
    }
    return true;
}

test "cursor trail submits Kitty direct corners for one-cell cursor shapes" {
    const clip = vk_surface.Rect{ .x = 0, .y = 0, .width = 256, .height = 256 };
    const canvas_clip = render_api.canvas.Rect{ .x = 0, .y = 0, .width = 256, .height = 256 };
    const shapes = .{ render_api.canvas.CursorShape.block, .bar, .underline };
    const expected_x = .{
        [4]f32{ 20, 20, 10, 10 },
        [4]f32{ 11, 11, 10, 10 },
        [4]f32{ 20, 20, 10, 10 },
    };
    const expected_y = .{
        [4]f32{ 30, 50, 50, 30 },
        [4]f32{ 30, 50, 50, 30 },
        [4]f32{ 49, 50, 50, 49 },
    };
    inline for (shapes, expected_x, expected_y) |shape, want_x, want_y| {
        const binding = render_api.canvas.CursorBinding{
            .pane = 1,
            .source = @fromBackingInt(2),
            .terminal_sequence = 1,
            .cursor_revision = 1,
            .visible_set_revision = 1,
            .lifecycle_revision = 1,
            .rect = .{ .x = 10, .y = 30, .width = 10, .height = 20 },
            .clip = canvas_clip,
            .shape = shape,
            .visible = true,
        };
        const placement = render_api.canvas.Composer.Placement{
            .source = binding.source,
            .origin = .{ .x = 0, .y = 0 },
            .clip = canvas_clip,
        };
        const overlay = (try cursorOverlayForPlacement(binding, placement)).?;
        const edges = try trailEdges(overlay);
        var trail = CursorTrail{};
        trailSnap(&trail, edges, overlay.clip, 1, true);
        try std.testing.expectEqual(want_x, trail.corner_x);
        try std.testing.expectEqual(want_y, trail.corner_y);
        try std.testing.expect(trailCornersInsideClip(trail.corner_x, trail.corner_y, clip));

        var animated = trail;
        for (0..4) |index| animated.corner_x[index] -= 20;
        animated.updated_at = 0;
        animated.needs_render = true;
        var animation_deadline: ?u64 = 0;
        try std.testing.expect(trailAdvance(
            &animated,
            16_000_000,
            dev_config.Config.defaults().presentationPolicy(),
            &animation_deadline,
        ));
        for (0..4) |index| {
            const target_x = edges.x[trail_corner_x[index]];
            const target_y = edges.y[trail_corner_y[index]];
            try std.testing.expect(animated.corner_x[index] >= target_x - 20 and animated.corner_x[index] <= target_x);
            try std.testing.expectEqual(target_y, animated.corner_y[index]);
        }
    }
}

test "cursor trail direct corners remain inside accumulated split-focus clips" {
    const start = vk_surface.Rect{ .x = 10, .y = 20, .width = 10, .height = 20 };
    const horizontal = vk_surface.Rect{ .x = 210, .y = 20, .width = 10, .height = 20 };
    const vertical = vk_surface.Rect{ .x = 10, .y = 220, .width = 10, .height = 20 };
    const diagonal = vk_surface.Rect{ .x = 210, .y = 220, .width = 10, .height = 20 };
    const moves = .{
        .{ start, horizontal, [4]f32{ 220, 220, 210, 210 }, [4]f32{ 20, 40, 40, 20 } },
        .{ start, vertical, [4]f32{ 20, 20, 10, 10 }, [4]f32{ 220, 240, 240, 220 } },
        .{ start, diagonal, [4]f32{ 220, 220, 210, 210 }, [4]f32{ 220, 240, 240, 220 } },
    };
    const start_x = [4]f32{ 20, 20, 10, 10 };
    const start_y = [4]f32{ 20, 40, 40, 20 };
    inline for (moves) |move| {
        const accumulated = try checkedTrailClipUnion(move[0], move[1]);
        try std.testing.expect(trailCornersInsideClip(start_x, start_y, accumulated));
        try std.testing.expect(trailCornersInsideClip(move[2], move[3], accumulated));
    }
}

test "cursor trail Kitty timing and easing numeric receipt" {
    // Kitty cursor_trail.c:84-124, with dt=0.016s, fast=.1s, slow=.4s.
    // The constants below are the independent binary32 trajectory receipt,
    // not a second implementation of the state machine.
    var trail = CursorTrail{
        .updated_at = 0,
        .opacity = 1,
        .corner_x = .{ 0, 0, 0, 0 },
        .corner_y = .{ 0, 0, 0, 0 },
        .cursor_edge_x = .{ 30, 40 },
        .cursor_edge_y = .{ 20, 40 },
        .needs_render = true,
    };
    var receipt_deadline: ?u64 = 0;
    const policy = dev_config.Config.defaults().presentationPolicy();
    try std.testing.expect(trailAdvance(&trail, 16_000_000, policy, &receipt_deadline));
    const expected_x = [4]f32{ 14.035134, 26.80492, 13.645503, 7.2642517 };
    const expected_y = [4]f32{ 7.017567, 26.80492, 18.194004, 4.8428345 };
    for (0..4) |index| {
        try std.testing.expect(@abs(trail.corner_x[index] - expected_x[index]) < 0.0001);
        try std.testing.expect(@abs(trail.corner_y[index] - expected_y[index]) < 0.0001);
    }
    try std.testing.expectEqual(@as(u64, 16_000_000 + trail_frame_interval_ns), receipt_deadline.?);
}

test "cursor trail advancement preserves Kitty corner identity" {
    const policy = dev_config.Config.defaults().presentationPolicy();
    var trail = CursorTrail{
        .updated_at = 0,
        .needs_render = true,
        .opacity = 1,
        .corner_x = .{ 20, 20, 10, 10 },
        .corner_y = .{ 30, 50, 50, 30 },
        .cursor_edge_x = .{ 70, 80 },
        .cursor_edge_y = .{ 90, 110 },
    };
    const initial_x = trail.corner_x;
    const initial_y = trail.corner_y;
    var frame_deadline: ?u64 = 0;
    var requested_frames: usize = 0;
    const samples = [_]u64{ 16_000_000, 32_000_000, 48_000_000, 10_000_000_000 };
    for (samples) |now| {
        if (trailAdvance(&trail, now, policy, &frame_deadline)) requested_frames += 1;
        for (0..4) |index| {
            const target_x = trail.cursor_edge_x[trail_corner_x[index]];
            const target_y = trail.cursor_edge_y[trail_corner_y[index]];
            const min_x = @min(initial_x[index], target_x);
            const max_x = @max(initial_x[index], target_x);
            const min_y = @min(initial_y[index], target_y);
            const max_y = @max(initial_y[index], target_y);
            try std.testing.expect(trail.corner_x[index] >= min_x and trail.corner_x[index] <= max_x);
            try std.testing.expect(trail.corner_y[index] >= min_y and trail.corner_y[index] <= max_y);
        }
    }
    try std.testing.expect(requested_frames >= 3);
    try std.testing.expectEqual([4]f32{ 80, 80, 70, 70 }, trail.corner_x);
    try std.testing.expectEqual([4]f32{ 90, 110, 110, 90 }, trail.corner_y);
}

test "cursor trail layout retains endpoint clips" {
    try std.testing.expectEqual(@as(usize, 96), @sizeOf(CursorTrail));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(CursorTrail));
}

test "trail endpoint clip union is checked and bounded" {
    const union_clip = try checkedTrailClipUnion(
        .{ .x = 10, .y = 20, .width = 10, .height = 20 },
        .{ .x = 30, .y = 40, .width = 10, .height = 20 },
    );
    try std.testing.expectEqual(
        vk_surface.Rect{ .x = 10, .y = 20, .width = 30, .height = 40 },
        union_clip,
    );
    try std.testing.expectError(
        error.InvalidFrame,
        checkedTrailClipUnion(
            .{ .x = -1, .y = 20, .width = 10, .height = 20 },
            .{ .x = 30, .y = 40, .width = 10, .height = 20 },
        ),
    );
    try std.testing.expectError(
        error.InvalidFrame,
        checkedTrailClipUnion(
            .{ .x = std.math.maxInt(i32), .y = 0, .width = 1, .height = 1 },
            .{ .x = std.math.maxInt(i32), .y = 0, .width = 1, .height = 1 },
        ),
    );
}

test "cursor trail candidate rejection preserves accepted state" {
    var work: CanvasWork = undefined;
    work.trails = undefined;
    const tab_id: session.TabId = @fromBackingInt(@intCast(7));
    work.trails[0] = .{ .id = tab_id };
    work.trail_scratch_tab = tab_id;
    work.trail_deadline = 700;
    work.trail_previous_deadline = 700;
    work.trail_scratch_deadline = 1_700;
    work.trail_scratch = .{
        .opacity = 0.5,
        .needs_render = true,
        .endpoint_clip = .{ .x = 10, .y = 10, .width = 20, .height = 20 },
        .target_clip = .{ .x = 40, .y = 40, .width = 20, .height = 20 },
    };
    const accepted = CursorTrail{
        .opacity = 1.0,
        .updated_at = 9,
        .endpoint_clip = .{ .x = 10, .y = 10, .width = 20, .height = 20 },
        .target_clip = .{ .x = 40, .y = 40, .width = 20, .height = 20 },
    };
    work.trails[0].trail = accepted;
    work.trails[0].initialized = true;
    discardTrailAnimation(&work, false);
    try std.testing.expectEqual(accepted, work.trails[0].trail);
    try std.testing.expect(work.trails[0].initialized);
    try std.testing.expectEqual(@as(?u64, 700), work.trail_deadline);
    try std.testing.expect(work.trail_scratch_tab == null);
    try std.testing.expect(work.trail_scratch_deadline == null);
    try std.testing.expect(work.trail_previous_deadline == null);
}

test "trail clip lifetime spans accepted frames and settles exactly" {
    var work: CanvasWork = undefined;
    work.trails = undefined;
    const tab_id: session.TabId = @fromBackingInt(@intCast(8));
    const old_clip = vk_surface.Rect{ .x = 10, .y = 10, .width = 20, .height = 20 };
    const new_clip = vk_surface.Rect{ .x = 100, .y = 100, .width = 20, .height = 20 };
    const replacement_clip = vk_surface.Rect{ .x = 200, .y = 40, .width = 20, .height = 20 };
    work.trails[0] = .{
        .id = tab_id,
        .initialized = true,
        .trail = .{
            .needs_render = true,
            .opacity = 1,
            .endpoint_clip = old_clip,
            .target_clip = new_clip,
        },
    };

    work.trail_scratch = work.trails[0].trail;
    work.trail_scratch_tab = tab_id;
    work.trail_scratch_deadline = 2;
    commitTrailAnimation(&work);
    try std.testing.expectEqual(old_clip, work.trails[0].trail.endpoint_clip);
    try std.testing.expectEqual(new_clip, work.trails[0].trail.target_clip);

    // A newer target during the active transition changes only target_clip;
    // the currently visible outgoing path remains covered by old_clip.
    work.trail_scratch = work.trails[0].trail;
    work.trail_scratch.target_clip = replacement_clip;
    work.trail_scratch.needs_render = true;
    work.trail_scratch_tab = tab_id;
    work.trail_scratch_deadline = 3;
    commitTrailAnimation(&work);
    try std.testing.expectEqual(old_clip, work.trails[0].trail.endpoint_clip);
    try std.testing.expectEqual(replacement_clip, work.trails[0].trail.target_clip);

    work.trail_scratch = work.trails[0].trail;
    work.trail_scratch.needs_render = false;
    work.trail_scratch_tab = tab_id;
    work.trail_scratch_deadline = null;
    commitTrailAnimation(&work);
    try std.testing.expectEqual(replacement_clip, work.trails[0].trail.endpoint_clip);
}

test "active retarget accumulates A B C coverage transactionally" {
    const clip_a = vk_surface.Rect{ .x = 0, .y = 0, .width = 20, .height = 20 };
    const clip_b = vk_surface.Rect{ .x = 100, .y = 100, .width = 20, .height = 20 };
    const clip_c = vk_surface.Rect{ .x = 200, .y = 40, .width = 20, .height = 20 };
    var trail = CursorTrail{
        .needs_render = true,
        .endpoint_clip = clip_a,
        .target_clip = clip_b,
        .corner_x = .{ 120, 120, 100, 100 },
        .corner_y = .{ 100, 120, 120, 100 },
        .cursor_edge_x = .{ 100, 120 },
        .cursor_edge_y = .{ 100, 120 },
    };
    const before_reversal = trail;
    try prepareTrailRetargetClip(&trail, clip_a, true);
    trail.target_clip = clip_a;
    const reversal_clip = try checkedTrailClipUnion(trail.endpoint_clip, clip_a);
    try std.testing.expect(trailCornersInsideClip(trail.corner_x, trail.corner_y, reversal_clip));
    trail.cursor_edge_x = .{ 0, 20 };
    trail.cursor_edge_y = .{ 0, 20 };
    trail.updated_at = 0;
    var reversal_deadline: ?u64 = 0;
    try std.testing.expect(trailAdvance(&trail, 16_000_000, dev_config.Config.defaults().presentationPolicy(), &reversal_deadline));
    try std.testing.expect(trailCornersInsideClip(trail.corner_x, trail.corner_y, reversal_clip));

    try prepareTrailRetargetClip(&trail, clip_c, true);
    trail.target_clip = clip_c;
    const abc_clip = try checkedTrailClipUnion(trail.endpoint_clip, clip_c);
    try std.testing.expect(trailCornersInsideClip(trail.corner_x, trail.corner_y, abc_clip));
    trail.cursor_edge_x = .{ 200, 220 };
    trail.cursor_edge_y = .{ 40, 60 };
    trail.updated_at = 16_000_000;
    reversal_deadline = 16_000_000;
    var retarget_frames: usize = 0;
    for ([_]u64{ 32_000_000, 48_000_000, 64_000_000 }) |now| {
        if (trailAdvance(&trail, now, dev_config.Config.defaults().presentationPolicy(), &reversal_deadline)) retarget_frames += 1;
        try std.testing.expect(trailCornersInsideClip(trail.corner_x, trail.corner_y, abc_clip));
    }
    try std.testing.expect(retarget_frames > 0);

    const before_failure = trail;
    try std.testing.expectError(
        error.InvalidFrame,
        prepareTrailRetargetClip(&trail, .{ .x = -1, .y = 0, .width = 20, .height = 20 }, true),
    );
    try std.testing.expectEqual(before_failure, trail);
    try std.testing.expect(!std.meta.eql(before_reversal.endpoint_clip, trail.endpoint_clip));
}

test "due trail transitions survive continuous ordinary redraw candidates" {
    const policy = dev_config.Config.defaults().presentationPolicy();
    const tab_id: session.TabId = @fromBackingInt(@intCast(31));
    var work: CanvasWork = undefined;
    resetTrailRecords(&work);
    work.trails[0] = .{
        .id = tab_id,
        .initialized = true,
        .trail = .{
            .updated_at = 0,
            .corner_x = .{ 10, 10, 0, 0 },
            .corner_y = .{ 0, 20, 20, 0 },
            .cursor_edge_x = .{ 100, 110 },
            .cursor_edge_y = .{ 0, 20 },
            .opacity = 1,
            .needs_render = true,
        },
    };
    work.trail_deadline = 0;
    var now: u64 = 0;
    var accepted_frames: usize = 0;
    for (0..4) |_| {
        now += trail_frame_interval_ns;
        var candidate = work.trails[0].trail;
        var candidate_deadline = work.trail_deadline;
        try std.testing.expect(trailAdvance(&candidate, now, policy, &candidate_deadline));
        work.trail_scratch = candidate;
        work.trail_scratch_tab = tab_id;
        work.trail_scratch_deadline = candidate_deadline;
        work.trail_previous_deadline = work.trail_deadline;
        work.trail_frame_pending = true;

        // This is the same commit path used when an ordinary terminal redraw
        // carries the due trail quad; no quiet-terminal turn is required.
        commitTrailAnimation(&work);
        work.trail_frame_pending = false;
        accepted_frames += 1;
        try std.testing.expectEqual(@as(?session.TabId, null), work.trail_scratch_tab);
        try std.testing.expect(work.trails[0].trail.corner_x[0] > 0);
    }
    try std.testing.expectEqual(@as(usize, 4), accepted_frames);
}

const CanvasPlanResult = union(enum) {
    blocked,
    retry,
    accepted: vk_surface.Plan,
};

/// Owns the residency and replay candidates returned by one accepted canvas
/// plan until the physical frame acceptance boundary. A successful union
/// result is not itself a commit: callers can still block while resolving the
/// focused source or fail during physical preparation.
const CandidateOwnershipGuard = struct {
    work: *CanvasWork,
    armed: bool = true,

    fn disarm(self: *CandidateOwnershipGuard) void {
        self.armed = false;
    }

    fn discard(self: *CandidateOwnershipGuard) void {
        if (!self.armed) return;
        self.work.residency.discard();
        self.work.replay.discard();
        self.armed = false;
    }

    fn deinit(self: *CandidateOwnershipGuard) void {
        self.discard();
    }
};

fn focusedSourceForCandidate(
    work: *const CanvasWork,
    candidate: *const session.SessionState,
    pending: ?*const PendingTopology,
) ?render_api.canvas.SourceId {
    const render_pane = session_chrome_adapter.toRenderPaneId(candidate.focusedPaneId()) catch return null;
    if (work.terminals.sourceFor(render_pane)) |source| return source;
    if (pending) |value|
        if (value.new_pane) |pane|
            if (@backingInt(pane) == @backingInt(render_pane))
                return value.new_source.?;
    return null;
}

test "cursor candidate guard rolls back blocked pane and tab resolution" {
    var residency = try vk_surface.ResidencyStore.init(
        std.testing.allocator,
        .{ .resources = 2, .pixel_bytes = 16 },
    );
    defer residency.deinit();
    var replay = try ReplayState.init(std.testing.allocator);
    defer replay.deinit();
    var work: CanvasWork = undefined;
    work.residency = &residency;
    work.replay = &replay;
    var topology = try session.SessionState.init(
        .{ .width = 320, .height = 240 },
    );
    const first_tab = topology.activeTabId();
    const first_pane = topology.focusedPaneId();
    const second_tab = try topology.createTab("retry");
    try topology.switchTab(second_tab);
    const second_pane = topology.focusedPaneId();
    try std.testing.expect(first_tab != second_tab);
    try std.testing.expect(first_pane != second_pane);

    const empty_frame = vk_surface.Frame{
        .revision = 1,
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{},
    };
    const empty_plan = vk_surface.Plan{
        .vertices = &.{},
        .indices = &.{},
        .commands = &.{},
        .atlas_changed = false,
    };
    const accepted_commands = replay.acceptedPlan().commands;

    // A plan can be accepted while a focused pane source disappears before
    // physical overlay resolution. The guard must release both staged roles
    // and leave the prior canonical replay frame untouched.
    try residency.stage(empty_frame);
    try replay.capture(empty_plan, empty_frame);
    {
        var guard = CandidateOwnershipGuard{ .work = &work };
        const focused_pane_source: ?u64 = null;
        try std.testing.expectEqual(second_pane, topology.focusedPaneId());
        if (focused_pane_source == null) guard.discard();
        guard.deinit();
    }
    try std.testing.expect(!residency.pending);
    try std.testing.expect(!replay.pending);
    try std.testing.expectEqual(@as(usize, 0), accepted_commands.len);
    try std.testing.expectEqual(@as(usize, 0), replay.acceptedPlan().commands.len);

    // The exact retry may stage both roles again once the pane source is
    // live; disarming is the successful physical-acceptance boundary.
    try residency.stage(empty_frame);
    try replay.capture(empty_plan, empty_frame);
    {
        var guard = CandidateOwnershipGuard{ .work = &work };
        const focused_pane_source: ?u64 = 1;
        try std.testing.expectEqual(second_pane, topology.focusedPaneId());
        if (focused_pane_source != null) guard.disarm();
        guard.deinit();
    }
    try std.testing.expect(residency.pending);
    try std.testing.expect(replay.pending);
    residency.discard();
    replay.discard();

    // A tab switch has the same post-plan source-resolution boundary and
    // must not inherit a staged candidate from the closed tab.
    try residency.stage(empty_frame);
    try replay.capture(empty_plan, empty_frame);
    {
        var guard = CandidateOwnershipGuard{ .work = &work };
        const switched_tab_source: ?u64 = null;
        try topology.switchTab(first_tab);
        try std.testing.expectEqual(first_pane, topology.focusedPaneId());
        if (switched_tab_source == null) guard.discard();
        guard.deinit();
    }
    try std.testing.expect(!residency.pending);
    try std.testing.expect(!replay.pending);
}

test "bootstrap cursor source resolves before lifecycle activation" {
    var terminals = try terminal_handoff.Boundary.init(
        std.testing.io,
        std.testing.allocator,
        .{
            .commands = 32,
            .upload_bytes = 4096,
            .cells = 32,
            .rows = 8,
            .images = 1,
            .placements = 1,
            .image_bytes = 4096,
            .glyphs = 16,
            .masks = 8,
            .resources_per_update = 16,
            .raster_bytes = 4096,
            .decoration_bytes = 4096,
        },
    );
    defer terminals.deinit();
    var work: CanvasWork = undefined;
    work.terminals = &terminals;
    const topology = try session.SessionState.init(
        .{ .width = 320, .height = 240 },
    );
    const pane = try session_chrome_adapter.toRenderPaneId(topology.focusedPaneId());
    var pending: PendingTopology = undefined;
    pending.new_pane = pane;
    pending.new_source = @fromBackingInt(7);
    try std.testing.expectEqual(
        pending.new_source.?,
        focusedSourceForCandidate(&work, &topology, &pending),
    );
    pending.new_pane = null;
    try std.testing.expectEqual(
        @as(?render_api.canvas.SourceId, null),
        focusedSourceForCandidate(&work, &topology, &pending),
    );
}

const ReplayCohort = struct {
    vertices: []vk_surface.Vertex,
    indices: []u32,
    commands: []vk_surface.Command,
    pins: []vk_surface.ResourceGeneration,
    vertex_count: usize = 0,
    index_count: usize = 0,
    command_count: usize = 0,
    pin_count: usize = 0,
};

const ReplayState = struct {
    allocator: std.mem.Allocator,
    cohorts: [2]ReplayCohort,
    accepted: usize = 0,
    pending: bool = false,
    accepted_slot: ?usize = null,
    retiring_cohort: ?usize = null,
    retiring_slot: ?usize = null,

    fn init(allocator: std.mem.Allocator) !ReplayState {
        var cohorts: [2]ReplayCohort = undefined;
        var initialized: usize = 0;
        errdefer while (initialized > 0) {
            initialized -= 1;
            allocator.free(cohorts[initialized].pins);
            allocator.free(cohorts[initialized].commands);
            allocator.free(cohorts[initialized].indices);
            allocator.free(cohorts[initialized].vertices);
        };
        for (&cohorts) |*cohort| {
            var allocated: usize = 0;
            errdefer freePartialCohort(allocator, cohort, &allocated);
            cohort.* = .{
                .vertices = undefined,
                .indices = undefined,
                .commands = undefined,
                .pins = undefined,
            };
            cohort.vertices = try allocator.alloc(vk_surface.Vertex, replay_command_limit * 4);
            allocated = 1;
            cohort.indices = try allocator.alloc(u32, replay_command_limit * 6);
            allocated = 2;
            cohort.commands = try allocator.alloc(vk_surface.Command, replay_command_limit);
            allocated = 3;
            cohort.pins = try allocator.alloc(vk_surface.ResourceGeneration, replay_pin_limit);
            allocated = 4;
            initialized += 1;
        }
        return .{ .allocator = allocator, .cohorts = cohorts };
    }

    fn freePartialCohort(
        allocator: std.mem.Allocator,
        cohort: *ReplayCohort,
        allocated: *usize,
    ) void {
        while (allocated.* > 0) {
            allocated.* -= 1;
            switch (allocated.*) {
                0 => allocator.free(cohort.vertices),
                1 => allocator.free(cohort.indices),
                2 => allocator.free(cohort.commands),
                3 => allocator.free(cohort.pins),
                else => unreachable,
            }
        }
    }

    fn deinit(self: *ReplayState) void {
        for (&self.cohorts) |*cohort| {
            self.allocator.free(cohort.pins);
            self.allocator.free(cohort.commands);
            self.allocator.free(cohort.indices);
            self.allocator.free(cohort.vertices);
        }
        self.* = undefined;
    }

    fn candidate(self: *ReplayState) *ReplayCohort {
        return &self.cohorts[1 - self.accepted];
    }

    fn acceptedSlot(self: *const ReplayState) ?usize {
        return self.accepted_slot;
    }

    fn canCapture(self: *const ReplayState) bool {
        return self.retiring_slot == null and !self.pending;
    }

    fn acceptedPlan(self: *const ReplayState) vk_surface.Plan {
        const cohort = &self.cohorts[self.accepted];
        return .{
            .vertices = cohort.vertices[0..cohort.vertex_count],
            .indices = cohort.indices[0..cohort.index_count],
            .commands = cohort.commands[0..cohort.command_count],
            .atlas_changed = false,
            .image_atlas_changed = false,
        };
    }

    fn capture(self: *ReplayState, plan: vk_surface.Plan, frame: vk_surface.Frame) !void {
        if (self.retiring_slot != null) return error.Retiring;
        if (plan.commands.len > frame_command_limit or
            frame.commands.len > frame_command_limit)
            return error.InvalidFrame;
        // Count and validate the complete pin cohort before touching the
        // staging role. The stack plan is fixed at the accepted bound, so a
        // pressure rejection cannot partially overwrite a reusable cohort.
        var planned_pins: [replay_pin_limit]vk_surface.ResourceGeneration = undefined;
        var planned_pin_count: usize = 0;
        for (frame.commands) |command| {
            const resource: ?vk_surface.ResourceGeneration = switch (command) {
                .solid => null,
                .alpha_mask => |value| value.resource,
                .rgba => |value| value.resource,
            };
            if (resource) |value| {
                value.validate() catch return error.InvalidFrame;
                var seen = false;
                for (planned_pins[0..planned_pin_count]) |prior| {
                    if (std.meta.eql(prior, value)) seen = true;
                }
                if (!seen) {
                    if (planned_pin_count == planned_pins.len) return error.InvalidFrame;
                    planned_pins[planned_pin_count] = value;
                    planned_pin_count += 1;
                }
            }
        }
        const cohort = self.candidate();
        if (plan.vertices.len > cohort.vertices.len or
            plan.indices.len > cohort.indices.len or
            plan.commands.len > cohort.commands.len)
            return error.InvalidFrame;
        @memcpy(cohort.vertices[0..plan.vertices.len], plan.vertices);
        @memcpy(cohort.indices[0..plan.indices.len], plan.indices);
        @memcpy(cohort.commands[0..plan.commands.len], plan.commands);
        cohort.vertex_count = plan.vertices.len;
        cohort.index_count = plan.indices.len;
        cohort.command_count = plan.commands.len;
        @memcpy(cohort.pins[0..planned_pin_count], planned_pins[0..planned_pin_count]);
        cohort.pin_count = planned_pin_count;
        self.pending = true;
    }

    fn commit(self: *ReplayState, slot_index: usize) void {
        std.debug.assert(self.pending);
        std.debug.assert(self.retiring_cohort == null);
        if (self.accepted_slot) |old_slot| {
            self.retiring_cohort = self.accepted;
            self.retiring_slot = old_slot;
        }
        self.accepted = 1 - self.accepted;
        self.accepted_slot = slot_index;
        self.pending = false;
    }

    /// Commits a physical cursor presentation without changing the canonical
    /// cursor-free command cohort. The staging bytes have been restored to the
    /// base before this method is called.
    fn commitCursor(self: *ReplayState, slot_index: usize) void {
        std.debug.assert(self.pending);
        std.debug.assert(self.retiring_slot == null);
        if (self.accepted_slot) |old_slot| {
            self.retiring_slot = old_slot;
        }
        self.accepted_slot = slot_index;
        self.pending = false;
    }

    /// Restores the staging role to an exact canonical base after its bytes
    /// were used synchronously to record a cursor presentation.
    fn restoreCandidateBase(self: *ReplayState, base: vk_surface.Plan) void {
        const cohort = self.candidate();
        @memcpy(cohort.vertices[0..base.vertices.len], base.vertices);
        @memcpy(cohort.indices[0..base.indices.len], base.indices);
        @memcpy(cohort.commands[0..base.commands.len], base.commands);
        cohort.vertex_count = base.vertices.len;
        cohort.index_count = base.indices.len;
        cohort.command_count = base.commands.len;
        // Replay never changes the candidate pin cohort.  Keeping it here is
        // essential for an ordinary replacement: the candidate already owns
        // the newly accepted base pins, while a cursor-only replay borrows the
        // canonical accepted pins.
    }

    fn releaseRetiring(self: *ReplayState, slot_index: usize) void {
        if (self.retiring_slot == slot_index) {
            self.retiring_cohort = null;
            self.retiring_slot = null;
        }
    }

    fn discard(self: *ReplayState) void {
        self.candidate().vertex_count = 0;
        self.candidate().index_count = 0;
        self.candidate().command_count = 0;
        self.candidate().pin_count = 0;
        self.pending = false;
    }
};

test "ReplayState.init rolls back every allocation position" {
    for (0..8) |fail_index| {
        var failing = std.testing.FailingAllocator.init(
            std.testing.allocator,
            .{ .fail_index = fail_index },
        );
        try std.testing.expectError(
            error.OutOfMemory,
            ReplayState.init(failing.allocator()),
        );
    }
    var replay = try ReplayState.init(std.testing.allocator);
    replay.deinit();
}

test "cursor replay cohorts role-swap and reject pressure transactionally" {
    var replay = try ReplayState.init(std.testing.allocator);
    defer replay.deinit();

    const resource = try vk_surface.ResourceGeneration.shared(1, 1);
    const vertices = [_]vk_surface.Vertex{
        .{ .position = .{ 0, 0 }, .uv = .{ 0, 0 }, .color = .{ 1, 1, 1, 1 } },
        .{ .position = .{ 1, 0 }, .uv = .{ 1, 0 }, .color = .{ 1, 1, 1, 1 } },
        .{ .position = .{ 1, 1 }, .uv = .{ 1, 1 }, .color = .{ 1, 1, 1, 1 } },
        .{ .position = .{ 0, 1 }, .uv = .{ 0, 1 }, .color = .{ 1, 1, 1, 1 } },
    };
    const indices = [_]u32{ 0, 1, 2, 0, 2, 3 };
    const commands = [_]vk_surface.Command{.{
        .kind = .alpha_mask_cursor,
        .first_index = 0,
        .index_count = 6,
        .clip = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
    }};
    const frame_commands = [_]vk_surface.FrameCommand{.{ .alpha_mask = .{
        .rect = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .clip = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .resource = resource,
        .color = .{ 1, 1, 1, 1 },
    } }};
    const plan = vk_surface.Plan{
        .vertices = &vertices,
        .indices = &indices,
        .commands = &commands,
        .atlas_changed = false,
    };
    const frame = vk_surface.Frame{
        .revision = 1,
        .uploads = &.{},
        .removals = &.{},
        .commands = &frame_commands,
    };

    try std.testing.expectEqual(@as(usize, 0), replay.acceptedPlan().commands.len);
    try replay.capture(plan, frame);
    try std.testing.expect(replay.pending);
    replay.discard();
    try std.testing.expectEqual(@as(usize, 0), replay.acceptedPlan().commands.len);

    try replay.capture(plan, frame);
    replay.commit(2);
    try std.testing.expectEqual(@as(usize, 1), replay.acceptedPlan().commands.len);
    try std.testing.expectEqual(@as(usize, 1), replay.cohorts[replay.accepted].pin_count);
    const accepted_command = replay.acceptedPlan().commands[0];

    const too_many_commands = replay.candidate().commands[0 .. frame_command_limit + 1];
    try std.testing.expectError(error.InvalidFrame, replay.capture(
        .{ .vertices = &.{}, .indices = &.{}, .commands = too_many_commands, .atlas_changed = false },
        frame,
    ));
    try std.testing.expectEqual(accepted_command, replay.acceptedPlan().commands[0]);
    try std.testing.expectEqual(@as(usize, 1), replay.cohorts[replay.accepted].pin_count);

    // A committed replacement keeps the previous physical role pinned until
    // its exact ring slot is released; staging cannot overwrite that role.
    try replay.capture(plan, frame);
    replay.commit(0);
    try std.testing.expectEqual(@as(?usize, 2), replay.retiring_slot);
    try std.testing.expectEqual(@as(?usize, 0), replay.acceptedSlot());
    var replay_slots = [_]Slot{ .{}, .{}, .{} };
    replay_slots[0].release_point = 4;
    replay_slots[1].release_point = 9;
    replay_slots[2].release_point = 7;
    const release_facts = window_render_boundary.RetiredRing{
        .generation = 1,
        .presented_mask = 0b101,
        .release_points = .{ 4, 9, 7 },
    };
    var unrelated_release = release_facts;
    unrelated_release.presented_mask = 0b001;
    try std.testing.expect(retiringSlotReady(&replay, unrelated_release, &replay_slots) == null);
    try std.testing.expectEqual(
        @as(?usize, 2),
        retiringSlotReady(&replay, release_facts, &replay_slots),
    );
    try std.testing.expectError(error.Retiring, replay.capture(plan, frame));
    // Slot 1 sorts before the retiring slot 2, but the exact retiring role is
    // reconciled first; selecting slot 1 must never leave capture blocked.
    const released_slots = [_]usize{ 1, 2 };
    for (released_slots) |slot| {
        if (replay.retiring_slot == slot) {
            replay.releaseRetiring(slot);
            break;
        }
    }
    try std.testing.expect(replay.canCapture());

    const pressure = try std.testing.allocator.alloc(vk_surface.FrameCommand, replay_pin_limit + 1);
    defer std.testing.allocator.free(pressure);
    for (pressure, 0..) |*command, index| {
        command.* = .{ .alpha_mask = .{
            .rect = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
            .clip = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
            .resource = try vk_surface.ResourceGeneration.shared(index + 2, 1),
            .color = .{ 1, 1, 1, 1 },
        } };
    }
    try std.testing.expectError(error.InvalidFrame, replay.capture(
        .{ .vertices = &.{}, .indices = &.{}, .commands = &.{}, .atlas_changed = false },
        .{ .revision = 2, .uploads = &.{}, .removals = &.{}, .commands = pressure },
    ));
    try std.testing.expectEqual(accepted_command, replay.acceptedPlan().commands[0]);
    try std.testing.expectEqual(@as(usize, 1), replay.cohorts[replay.accepted].pin_count);
}

test "cursor placement translates pane-local geometry and clips at Composer placement" {
    const binding = render_api.canvas.CursorBinding{
        .pane = 1,
        .source = @fromBackingInt(2),
        .terminal_sequence = 4,
        .cursor_revision = 3,
        .visible_set_revision = 5,
        .lifecycle_revision = 6,
        .rect = .{ .x = 8, .y = 0, .width = 8, .height = 16 },
        .clip = .{ .x = 0, .y = 0, .width = 24, .height = 32 },
        .shape = .block,
        .visible = true,
    };
    const placement = render_api.canvas.Composer.Placement{
        .source = binding.source,
        .origin = .{ .x = 24, .y = 40 },
        .clip = .{ .x = 24, .y = 40, .width = 16, .height = 24 },
    };
    const overlay = (try cursorOverlayForPlacement(binding, placement)).?;
    try std.testing.expectEqual(@as(i32, 40), overlay.rect.y);
    try std.testing.expectEqual(@as(i32, 40), overlay.clip.y);
    try std.testing.expectEqual(@as(u32, 16), overlay.clip.width);
    try std.testing.expectEqual(@as(u32, 24), overlay.clip.height);
    try std.testing.expect(overlay.rect.y != 0);
}

test "cursor-only replay keeps the canonical base across ten updates" {
    var replay = try ReplayState.init(std.testing.allocator);
    defer replay.deinit();
    const vertices = [_]vk_surface.Vertex{
        .{ .position = .{ 0, 0 }, .uv = .{ 0, 0 }, .color = .{ 1, 1, 1, 1 } },
        .{ .position = .{ 8, 0 }, .uv = .{ 1, 0 }, .color = .{ 1, 1, 1, 1 } },
        .{ .position = .{ 8, 16 }, .uv = .{ 1, 1 }, .color = .{ 1, 1, 1, 1 } },
        .{ .position = .{ 0, 16 }, .uv = .{ 0, 1 }, .color = .{ 1, 1, 1, 1 } },
    };
    const indices = [_]u32{ 0, 1, 2, 0, 2, 3 };
    const commands = [_]vk_surface.Command{.{
        .kind = .solid,
        .first_index = 0,
        .index_count = 6,
        .clip = .{ .x = 0, .y = 0, .width = 8, .height = 16 },
    }};
    const plan = vk_surface.Plan{
        .vertices = &vertices,
        .indices = &indices,
        .commands = &commands,
        .atlas_changed = false,
    };
    try replay.capture(plan, .{
        .revision = 1,
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{},
    });
    replay.commit(0);
    const canonical = replay.acceptedPlan();
    const canonical_commands = canonical.commands[0];
    var expected_count: ?usize = null;
    for (0..10) |index| {
        const candidate_cohort = replay.candidate();
        const presented = try vk_surface.replayCursor(
            canonical,
            .{
                .rect = .{ .x = @intCast(index), .y = 0, .width = 8, .height = 16 },
                .clip = .{ .x = 0, .y = 0, .width = 32, .height = 16 },
                .shape = .bar,
                .color = .{ 0, 0, 0, 1 },
                .text_color = .{ 1, 1, 1, 1 },
                .visible = true,
            },
            .{
                .vertices = candidate_cohort.vertices,
                .indices = candidate_cohort.indices,
                .commands = candidate_cohort.commands,
            },
        );
        if (expected_count) |count|
            try std.testing.expectEqual(count, presented.commands.len)
        else
            expected_count = presented.commands.len;
        replay.pending = true;
        replay.restoreCandidateBase(canonical);
        replay.commitCursor(1);
        if (replay.retiring_slot) |slot| replay.releaseRetiring(slot);
        try std.testing.expectEqual(canonical_commands, replay.acceptedPlan().commands[0]);
        try std.testing.expectEqual(@as(usize, 1), replay.acceptedPlan().commands.len);
    }
}

const RedrawResult = enum {
    blocked,
    retry,
    published,
};

const CursorReplayResult = enum {
    blocked,
    rejected,
    retry,
    published,
};

const ReplayCompletionError = error{
    Stopping,
    CompletionLimit,
    InvalidRevision,
};

const PostSubmitDisposition = enum { fatal };

const CursorReplayPreparation = union(enum) {
    rejected,
    prepared: vk_surface.Plan,
};

const CursorOverlayPreparation = union(enum) {
    blocked,
    rejected,
    prepared: vk_surface.CursorOverlay,
};

fn prepareCursorReplayCandidate(
    base: vk_surface.Plan,
    overlay: vk_surface.CursorOverlay,
    buffers: vk_surface.CursorReplayBuffers,
) !CursorReplayPreparation {
    if (base.commands.len > frame_command_limit or
        base.vertices.len > frame_command_limit * 4 or
        base.indices.len > frame_command_limit * 6)
        return error.InvalidReplayBase;
    if (buffers.vertices.len != vk_surface.max_vertices or
        buffers.indices.len != vk_surface.max_indices or
        buffers.commands.len != vk_surface.max_commands)
        return error.ReplayCapacity;
    const candidate = vk_surface.replayCursor(
        base,
        overlay,
        buffers,
    ) catch |failure| switch (failure) {
        error.InvalidCursorOverlay => return .rejected,
        error.InvalidReplayBase,
        error.ReplayCapacity,
        => return failure,
    };
    return .{ .prepared = candidate };
}

fn classifyReplayCompletionFailure(
    _: ReplayCompletionError,
) PostSubmitDisposition {
    return .fatal;
}

fn discardRejectedCursorReplay(
    work: *CanvasWork,
    pending: *?terminal_handoff.CursorPublication,
    trail_only: bool,
) void {
    if (trail_only) {
        discardTrailAnimation(work, false);
        work.trail_frame_pending = false;
    } else {
        dropPendingCursor(pending);
    }
}

fn commitCursorReplayAcceptance(
    work: *CanvasWork,
    publication: ?terminal_handoff.CursorPublication,
    accepted_overlay: vk_surface.CursorOverlay,
    trail_only: bool,
    slot_index: usize,
    slot: *Slot,
    release_point: u64,
    next_acquire_point: *u64,
    following_acquire_point: u64,
) void {
    work.replay.commitCursor(slot_index);
    if (!trail_only) if (publication) |value| {
        work.last_cursor_publication = value;
        work.accepted_cursor_color = accepted_overlay.color;
    };
    slot.release_point = release_point;
    next_acquire_point.* = following_acquire_point;
}

test "cursor replay preparation rejects candidate facts and preserves accepted ownership" {
    try std.testing.expectEqual(
        frame_command_limit * 2 + 2,
        vk_surface.max_commands,
    );
    try std.testing.expectEqual(vk_surface.max_commands * 4, vk_surface.max_vertices);
    try std.testing.expectEqual(vk_surface.max_commands * 6, vk_surface.max_indices);
    var replay = try ReplayState.init(std.testing.allocator);
    defer replay.deinit();
    const base = replay.acceptedPlan();
    const candidate = replay.candidate();
    const buffers = vk_surface.CursorReplayBuffers{
        .vertices = candidate.vertices,
        .indices = candidate.indices,
        .commands = candidate.commands,
    };
    const invalid_overlay = vk_surface.CursorOverlay{
        .rect = .{ .x = 0, .y = 0, .width = 0, .height = 1 },
        .clip = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .shape = .block,
        .color = .{ 1, 1, 1, 1 },
        .text_color = .{ 0, 0, 0, 1 },
        .visible = true,
    };
    try std.testing.expectEqual(
        CursorReplayPreparation.rejected,
        try prepareCursorReplayCandidate(base, invalid_overlay, buffers),
    );
    try std.testing.expect(!replay.pending);
    try std.testing.expect(replay.acceptedSlot() == null);
    try std.testing.expectEqual(@as(usize, 0), replay.acceptedPlan().vertices.len);
    try std.testing.expectEqual(@as(usize, 0), replay.acceptedPlan().indices.len);
    try std.testing.expectEqual(@as(usize, 0), replay.acceptedPlan().commands.len);
    try std.testing.expectEqual(@as(usize, 0), candidate.vertex_count);
    try std.testing.expectEqual(@as(usize, 0), candidate.index_count);
    try std.testing.expectEqual(@as(usize, 0), candidate.command_count);

    var valid_overlay = invalid_overlay;
    valid_overlay.rect.width = 1;
    const prepared = try prepareCursorReplayCandidate(
        base,
        valid_overlay,
        buffers,
    );
    try std.testing.expectEqual(@as(usize, 1), prepared.prepared.commands.len);

    const publication = terminal_handoff.CursorPublication{
        .pane = @fromBackingInt(41),
        .source = @fromBackingInt(42),
        .terminal_sequence = 7,
        .cursor_revision = 8,
        .visible_set_revision = 9,
        .lifecycle_revision = @fromBackingInt(10),
        .target = .{
            .row = 0,
            .col = 0,
            .visible = true,
            .shape = .block,
            .blink = false,
            .blink_fast = false,
            .cursor_color = .{},
            .text_color = .{},
        },
    };
    var work: CanvasWork = undefined;
    work.replay = &replay;
    work.last_cursor_publication = null;
    work.accepted_cursor_color = null;
    var pending: ?terminal_handoff.CursorPublication = publication;
    var slot = Slot{};
    var next_acquire_point: u64 = 11;
    discardRejectedCursorReplay(&work, &pending, false);
    try std.testing.expect(pending == null);
    try std.testing.expect(replay.acceptedSlot() == null);
    try std.testing.expectEqual(@as(u64, 0), slot.release_point);
    try std.testing.expectEqual(@as(u64, 11), next_acquire_point);
    try std.testing.expect(work.last_cursor_publication == null);

    work.trail_scratch_tab = @fromBackingInt(1);
    work.trail_scratch_transfer = false;
    work.trail_previous_deadline = 14;
    work.trail_scratch_deadline = 15;
    work.trail_deadline = 16;
    work.trail_frame_pending = true;
    discardRejectedCursorReplay(&work, &pending, true);
    try std.testing.expect(work.trail_scratch_tab == null);
    try std.testing.expect(!work.trail_frame_pending);
    try std.testing.expectEqual(@as(?u64, 14), work.trail_deadline);

    replay.pending = true;
    replay.restoreCandidateBase(base);
    commitCursorReplayAcceptance(
        &work,
        publication,
        valid_overlay,
        false,
        1,
        &slot,
        12,
        &next_acquire_point,
        13,
    );
    try std.testing.expectEqual(@as(?usize, 1), replay.acceptedSlot());
    try std.testing.expectEqual(publication, work.last_cursor_publication.?);
    try std.testing.expectEqual(valid_overlay.color, work.accepted_cursor_color.?);
    try std.testing.expectEqual(@as(u64, 12), slot.release_point);
    try std.testing.expectEqual(@as(u64, 13), next_acquire_point);

    var malformed_base = base;
    malformed_base.trail_mask = .{ .x = 0, .y = 0, .width = 1, .height = 1 };
    try std.testing.expectError(
        error.InvalidReplayBase,
        prepareCursorReplayCandidate(malformed_base, valid_overlay, buffers),
    );
    var oversized_base = base;
    oversized_base.commands = candidate.commands[0 .. frame_command_limit + 1];
    try std.testing.expectError(
        error.InvalidReplayBase,
        prepareCursorReplayCandidate(oversized_base, valid_overlay, buffers),
    );
    const short_buffers = vk_surface.CursorReplayBuffers{
        .vertices = candidate.vertices[0 .. candidate.vertices.len - 1],
        .indices = candidate.indices,
        .commands = candidate.commands,
    };
    try std.testing.expectError(
        error.ReplayCapacity,
        prepareCursorReplayCandidate(base, valid_overlay, short_buffers),
    );
    try std.testing.expectEqual(
        PostSubmitDisposition.fatal,
        classifyReplayCompletionFailure(error.CompletionLimit),
    );
    try std.testing.expectEqual(
        PostSubmitDisposition.fatal,
        classifyReplayCompletionFailure(error.Stopping),
    );
    try std.testing.expectEqual(
        PostSubmitDisposition.fatal,
        classifyReplayCompletionFailure(error.InvalidRevision),
    );
}

const RedrawSchedule = enum {
    wait,
    retry,
    published,
};

fn scheduleRedraw(
    result: RedrawResult,
    local_retry_turn: bool,
) error{InvalidFrame}!RedrawSchedule {
    return switch (result) {
        .blocked => .wait,
        .retry => if (local_retry_turn)
            error.InvalidFrame
        else
            .retry,
        .published => .published,
    };
}

const BootstrapSource = struct {
    pane: render_api.chrome.PaneId,
    source: render_api.canvas.SourceId,
};

const PreparedBootstrapPublication = struct {
    boundary: terminal_handoff.Boundary.PreparedVisibleSet,
    placements: [terminal_handoff.visible_member_limit]render_api.canvas.Composer.Placement,
    count: u8,
    committed: bool = false,

    fn commit(
        self: *PreparedBootstrapPublication,
        work: *CanvasWork,
    ) void {
        self.boundary.commit();
        @memcpy(
            work.pending_placements[0..self.count],
            self.placements[0..self.count],
        );
        work.pending_count = self.count;
        work.pending_visible_revision = self.boundary.revision;
        self.committed = true;
    }

    fn deinit(self: *PreparedBootstrapPublication) void {
        if (self.committed) return;
        self.boundary.deinit();
        self.committed = true;
    }
};

const CanvasWork = struct {
    composer: *render_api.canvas.Composer,
    content: *render_api.chrome.Content,
    source: render_api.canvas.SourceId,
    surface: render_api.canvas.Size = .{ .width = 0, .height = 0 },
    content_origin: session_chrome_adapter.ContentOrigin = .{ .y = 0 },
    producer_revision: u64 = 0,
    frame_uploads: []render_api.canvas.ResourceUploadFact,
    frame_removals: []render_api.canvas.FrameResourceRef,
    frame_commands: []render_api.canvas.Command,
    frame_pixels: []u8,
    surface_uploads: []vk_surface.Upload,
    surface_removals: []vk_surface.Removal,
    surface_commands: []vk_surface.FrameCommand,
    surface_residencies: []vk_surface.Residency,
    canvas_residencies: []render_api.canvas.Residency,
    builder: *vk_surface.FrameBuilder,
    residency: *vk_surface.ResidencyStore,
    terminals: *terminal_handoff.Boundary,
    /// Startup-retained presentation view consumed by cursor geometry, trail
    /// timing, and frame-demand ownership; no reload path exists.
    cursor_policy: dev_config.CursorPresentationPolicy,
    /// One fixed trail record per exact bounded TabId. Ordered tab slots are
    /// never the ownership key, so close/reorder/reuse cannot inherit a trail.
    trails: [session_chrome_adapter.max_tabs]TrailSlot = undefined,
    trail_scratch: CursorTrail = .{},
    trail_scratch_tab: ?session.TabId = null,
    trail_scratch_deadline: ?u64 = null,
    trail_previous_deadline: ?u64 = null,
    trail_scratch_transfer: bool = false,
    /// A tab presentation transfer is only a candidate until the physical
    /// trail replay carrying it is accepted.
    trail_transfer: ?TrailTransferCandidate = null,
    trail_transfer_previous_deadline: ?u64 = null,
    trail_deadline: ?u64 = null,
    trail_frame_pending: bool = false,
    /// Last physically accepted presentation, independent of semantic TabId
    /// slot lifetime. Retired tabs may lose their semantic slot while this
    /// snapshot remains the source for the next accepted transfer.
    accepted_trail_surface: ?AcceptedTrailSurface = null,
    last_cursor_publication: ?terminal_handoff.CursorPublication = null,
    /// Background color from the last physically accepted cursor overlay.
    /// Semantic cursor updates do not advance this value until Composer/ring
    /// acceptance, matching Kitty's last-rendered cursor fallback.
    accepted_cursor_color: ?[4]f32 = null,
    terminal_font_policy: terminal_handoff.FontPolicy,
    terminal_scale: ?terminal_handoff.ScaleSnapshot = null,
    font_request_high_water: u64 = 0,
    next_visible_revision: u64 = 1,
    visible_placements: [terminal_handoff.visible_member_limit]render_api.canvas.Composer.Placement = undefined,
    visible_count: u8 = 0,
    pending_visible_revision: ?u64 = null,
    pending_placements: [terminal_handoff.visible_member_limit]render_api.canvas.Composer.Placement = undefined,
    pending_count: u8 = 0,
    retired_sources: [64]RetiredTerminalSource = undefined,
    retired_source_count: u8 = 0,
    /// Borrows Chrome Content output until one exact candidate is accepted.
    ///
    /// While populated, buildCanvasPlan does not mutate or extract Content and
    /// defers later topology projection to the caller's next loop turn.
    chrome_retry: ?ChromeRetry = null,
    replay: *ReplayState,
};

fn resetTrailRecords(work: *CanvasWork) void {
    for (&work.trails) |*slot| slot.* = .{};
    work.trail_scratch = .{};
    work.trail_scratch_tab = null;
    work.trail_scratch_deadline = null;
    work.trail_previous_deadline = null;
    work.trail_scratch_transfer = false;
    work.trail_transfer = null;
    work.trail_transfer_previous_deadline = null;
    work.trail_deadline = null;
    work.trail_frame_pending = false;
    work.accepted_trail_surface = null;
    work.last_cursor_publication = null;
}

/// Copies the last physically accepted trail presentation to a newly active
/// TabId. The incoming semantic target is retargeted separately, so this
/// helper carries only physical presentation state and never aliases storage.
fn transferTrailPresentation(
    candidate: *TrailTransferCandidate,
    outgoing: ?AcceptedTrailSurface,
    now: u64,
) void {
    candidate.initialized = false;
    candidate.trail = .{};
    if (outgoing) |surface| {
        if (!surface.initialized) return;
        candidate.trail = surface.trail;
        candidate.initialized = true;
    } else return;
    candidate.trail.needs_render = true;
    // Kitty restarts the transferred animation clock at the active-tab
    // transition time; it does not use a zero sentinel.
    candidate.trail.updated_at = now;
}

fn prepareTrailTransferCandidate(
    work: *CanvasWork,
    tab_id: session.TabId,
    now: u64,
) void {
    const accepted_owner = if (work.accepted_trail_surface) |surface| surface.owner else null;
    var transfer = work.trail_transfer;
    if (transfer) |pending| {
        if (pending.to != tab_id) {
            // A newer accepted topology supersedes an unpresented transfer.
            // Restore the pending scheduler state and retain the old owner.
            transfer = null;
            work.trail_transfer = null;
            work.trail_deadline = work.trail_transfer_previous_deadline;
            work.trail_transfer_previous_deadline = null;
            work.trail_frame_pending = false;
        }
    }
    if (transfer == null and accepted_owner != null and accepted_owner.? != tab_id) {
        var candidate = TrailTransferCandidate{
            .from = accepted_owner.?,
            .to = tab_id,
        };
        transferTrailPresentation(&candidate, work.accepted_trail_surface, now);
        transfer = candidate;
        work.trail_transfer_previous_deadline = work.trail_deadline;
    }
    work.trail_transfer = transfer;
}

fn findTrailSlot(work: *const CanvasWork, tab_id: session.TabId) ?usize {
    for (work.trails, 0..) |slot, index| {
        if (slot.id) |id| if (id == tab_id) return index;
    }
    return null;
}

fn topologyHasTrailTab(topology: *const session.SessionState, tab_id: session.TabId) bool {
    for (0..topology.tabCount()) |index| {
        if (topology.tabId(index).? == tab_id) return true;
    }
    return false;
}

fn reconcileTrailTopology(work: *CanvasWork, topology: *const session.SessionState) !void {
    var candidate = work.trails;
    for (&candidate) |*slot| {
        if (slot.id) |id| {
            if (!topologyHasTrailTab(topology, id)) slot.* = .{};
        }
    }
    for (0..topology.tabCount()) |index| {
        const tab_id = topology.tabId(index).?;
        var present = false;
        for (candidate) |slot| {
            if (slot.id) |id| {
                if (id == tab_id) {
                    present = true;
                    break;
                }
            }
        }
        if (!present) {
            var inserted = false;
            for (&candidate) |*slot| {
                if (slot.id == null) {
                    slot.* = .{ .id = tab_id };
                    inserted = true;
                    break;
                }
            }
            if (!inserted) return error.InvalidFrame;
        }
    }
    work.trails = candidate;
}

fn syncAcceptedTrail(
    work: *CanvasWork,
    topology: *const session.SessionState,
    now: u64,
    reset: bool,
) !void {
    const tab_id = topology.activeTabId();
    const slot_index = findTrailSlot(work, tab_id) orelse return error.InvalidFrame;
    var candidate_slot = work.trails[slot_index];
    prepareTrailTransferCandidate(work, tab_id, now);
    const transfer = work.trail_transfer;
    const active_transition = transfer != null;
    if (transfer == null and reset) {
        candidate_slot = .{ .id = tab_id };
    }
    const pane = topology.focusedPaneId();
    const source = work.terminals.sourceFor(session_chrome_adapter.toRenderPaneId(pane) catch return error.InvalidFrame) orelse {
        work.trail_deadline = null;
        work.trail_frame_pending = false;
        if (transfer) |candidate| {
            var updated = candidate;
            updated.deadline = null;
            work.trail_transfer = updated;
        }
        return;
    };
    const binding = work.composer.cursorBinding(source) orelse {
        work.trail_deadline = null;
        work.trail_frame_pending = false;
        if (transfer) |candidate| {
            var updated = candidate;
            updated.deadline = null;
            work.trail_transfer = updated;
        }
        return;
    };
    const overlay = (try cursorOverlayForBinding(work, source)) orelse {
        work.trail_deadline = null;
        work.trail_frame_pending = false;
        if (transfer) |candidate| {
            var updated = candidate;
            updated.deadline = null;
            work.trail_transfer = updated;
        }
        return;
    };
    if (transfer) |candidate| {
        var candidate_transfer = candidate;
        var candidate_trail = candidate_transfer.trail;
        var candidate_initialized = candidate_transfer.initialized;
        if (candidate_initialized and overlay.visible) {
            try prepareTrailRetargetClip(
                &candidate_trail,
                overlay.clip,
                candidate_trail.needs_render or candidate_transfer.deadline != null,
            );
        }
        var candidate_deadline = candidate_transfer.deadline;
        const movement_timestamp_ns = if (work.last_cursor_publication) |publication|
            if (publication.source == source) publication.target.movement_timestamp_ns else now
        else
            now;
        try trailPrepareTargetAt(
            &candidate_trail,
            overlay,
            binding.cell_size,
            now,
            movement_timestamp_ns,
            work.cursor_policy,
            &candidate_deadline,
            &candidate_initialized,
        );
        candidate_transfer.trail = candidate_trail;
        candidate_transfer.initialized = candidate_initialized;
        candidate_transfer.deadline = candidate_deadline;
        work.trail_transfer = candidate_transfer;
        work.trail_deadline = candidate_deadline;
        work.trail_frame_pending = false;
        return;
    }
    if (candidate_slot.initialized and overlay.visible) {
        // A retarget during an active transition must retain every endpoint
        // already visible in the current direct corner quad.  Fold the prior
        // target into endpoint_clip before replacing target_clip; otherwise
        // an A->B->A reversal would clip corners still near B down to A.
        try prepareTrailRetargetClip(
            &candidate_slot.trail,
            overlay.clip,
            candidate_slot.trail.needs_render or work.trail_deadline != null,
        );
    }
    // A tab transition restarts the incoming presentation clock.  Never let
    // the outgoing tab's due time short-circuit the transferred target.
    var candidate_deadline = if (active_transition) null else work.trail_deadline;
    const movement_timestamp_ns = if (work.last_cursor_publication) |publication|
        if (publication.source == source) publication.target.movement_timestamp_ns else now
    else
        now;
    try trailPrepareTargetAt(
        &candidate_slot.trail,
        overlay,
        binding.cell_size,
        now,
        movement_timestamp_ns,
        work.cursor_policy,
        &candidate_deadline,
        &candidate_slot.initialized,
    );
    work.trails[slot_index] = candidate_slot;
    work.trail_deadline = candidate_deadline;
    work.trail_frame_pending = false;
}

/// Advances the physically accepted trail snapshot after the frame carrying
/// the corresponding trail/cursor presentation has been accepted. Semantic
/// synchronization must not call this before replay/ring acceptance.
fn acceptTrailSurfaceSnapshot(work: *CanvasWork, tab_id: session.TabId) !void {
    const slot_index = findTrailSlot(work, tab_id) orelse return error.InvalidFrame;
    work.accepted_trail_surface = .{
        .owner = tab_id,
        .trail = work.trails[slot_index].trail,
        .initialized = work.trails[slot_index].initialized,
    };
}

fn prepareTrailAnimation(
    work: *CanvasWork,
    topology: *const session.SessionState,
    now: u64,
) !bool {
    const tab_id = topology.activeTabId();
    const slot_index = findTrailSlot(work, tab_id) orelse return false;
    const transfer = if (work.trail_transfer) |candidate|
        if (candidate.to == tab_id) candidate else return false
    else
        null;
    const initialized = if (transfer) |candidate|
        candidate.initialized
    else
        work.trails[slot_index].initialized;
    if (!initialized) return false;
    const pane = topology.focusedPaneId();
    const source = work.terminals.sourceFor(session_chrome_adapter.toRenderPaneId(pane) catch return false) orelse return false;
    if (work.composer.cursorBinding(source) == null) return false;
    const old_deadline = if (transfer) |value| value.deadline else work.trail_deadline;
    var candidate = if (transfer) |value| value.trail else work.trails[slot_index].trail;
    var candidate_deadline = old_deadline;
    if (!trailAdvance(
        &candidate,
        now,
        work.cursor_policy,
        &candidate_deadline,
    )) {
        if (transfer) |value| {
            var updated = value;
            updated.deadline = candidate_deadline;
            work.trail_transfer = updated;
        }
        work.trail_deadline = candidate_deadline;
        return false;
    }
    work.trail_scratch = candidate;
    work.trail_scratch_tab = tab_id;
    work.trail_scratch_deadline = candidate_deadline;
    work.trail_previous_deadline = old_deadline;
    work.trail_scratch_transfer = transfer != null;
    return true;
}

fn commitTrailAnimation(work: *CanvasWork) void {
    const tab_id = work.trail_scratch_tab orelse return;
    const slot_index = findTrailSlot(work, tab_id) orelse {
        discardTrailAnimation(work, false);
        return;
    };
    const transfer_commit = work.trail_scratch_transfer;
    work.trails[slot_index].trail = work.trail_scratch;
    work.trails[slot_index].initialized = true;
    // Keep the original endpoint clip for every in-flight frame.  The
    // animated direct corner quad can still occupy the outgoing pane until
    // its corners and opacity have physically settled; only then may the
    // target clip become the new accepted endpoint.
    if (!work.trail_scratch.needs_render and work.trail_scratch_deadline == null) {
        work.trails[slot_index].trail.endpoint_clip =
            work.trails[slot_index].trail.target_clip;
    }
    work.trail_deadline = work.trail_scratch_deadline;
    work.trail_scratch_tab = null;
    work.trail_scratch_deadline = null;
    work.trail_previous_deadline = null;
    work.trail_scratch_transfer = false;
    if (transfer_commit) {
        if (work.trail_transfer) |transfer| {
            if (transfer.to == tab_id) {
                work.trail_transfer = null;
                work.trail_transfer_previous_deadline = null;
            }
        }
    }
    work.accepted_trail_surface = .{
        .owner = tab_id,
        .trail = work.trails[slot_index].trail,
        .initialized = work.trails[slot_index].initialized,
    };
    work.trail_frame_pending = work.trail_deadline != null;
}

fn discardTrailAnimation(work: *CanvasWork, retry_at_candidate_deadline: bool) void {
    if (work.trail_scratch_tab == null) return;
    work.trail_deadline = if (work.trail_scratch_transfer)
        if (work.trail_transfer) |transfer| transfer.deadline else null
    else if (retry_at_candidate_deadline)
        work.trail_scratch_deadline
    else
        work.trail_previous_deadline;
    work.trail_scratch_tab = null;
    work.trail_scratch_deadline = null;
    work.trail_previous_deadline = null;
    work.trail_scratch_transfer = false;
}

const Slot = struct {
    width: u32 = 0,
    height: u32 = 0,
    coordinate_width: u32 = 0,
    coordinate_height: u32 = 0,
    image: vk.VkImage = null,
    memory: vk.VkDeviceMemory = null,
    release_handle: u32 = 0,
    plane_count: u8 = 0,
    planes: [window_render_boundary.plane_limit]window_render_boundary.Plane = undefined,
    external: bool = false,
    attachment: vk_surface.Attachment = .{},
    owned_bytes: u64 = 0,
    release_point: u64 = 0,
    clear_color: [4]f32 = .{ 0, 0, 0, 1 },

    fn deinit(self: *Slot, device: vk.VkDevice, drm_fd: i32, gpu_bytes: *u64) void {
        self.attachment.deinit(device);
        if (self.release_handle != 0) destroySyncobj(drm_fd, self.release_handle);
        if (self.image != null) vk.vkDestroyImage(device, self.image, null);
        if (self.memory != null) vk.vkFreeMemory(device, self.memory, null);
        gpu_bytes.* -= self.owned_bytes;
        self.* = .{};
    }
};

const OfferedFds = struct {
    dma: i32 = -1,
    acquire: i32 = -1,
    timeline: i32 = -1,
};

/// Runs the sole Vulkan/DRM owner until the bounded ring completes or fails.
/// All operational failures are recorded as the first Render runtime failure.
pub fn run(
    boundary: *window_render_boundary.Boundary,
    terminals: *terminal_handoff.Boundary,
    allocator: std.mem.Allocator,
    font_path: []const u8,
    cursor_policy: dev_config.CursorPresentationPolicy,
) void {
    runFallible(
        boundary,
        terminals,
        allocator,
        font_path,
        cursor_policy,
    ) catch |failure| {
        std.debug.print("Render failure: {s}\n", .{@errorName(failure)});
        boundary.requestStop(.render);
    };
    boundary.markStopped(.render);
}

fn runFallible(
    boundary: *window_render_boundary.Boundary,
    terminals: *terminal_handoff.Boundary,
    allocator: std.mem.Allocator,
    font_path: []const u8,
    cursor_policy: dev_config.CursorPresentationPolicy,
) !void {
    const feedback = try waitFeedback(boundary);
    const initial_surface = try waitConfigure(boundary);
    try checkGpuBudget(initial_surface.physical_width, initial_surface.physical_height);
    var chrome = try session.SessionState.init(contentExtent(renderExtent(initial_surface), try session_chrome_adapter.contentOrigin(renderExtent(initial_surface), session_chrome_adapter.default_tab_bar_height)));
    var composer = try render_api.canvas.Composer.init(allocator, .{
        .sources = session_chrome_adapter.max_live_panes + 1,
        .retained_resources = frame_resource_limit,
        .retained_commands = frame_command_limit,
        .retained_pixel_bytes = 16 * 1024 * 1024,
        .composition_sources = session_chrome_adapter.max_live_panes + 1,
        .candidate_resources = 1024,
        .candidate_commands = frame_command_limit,
        .candidate_pixel_bytes = 4 * 1024 * 1024,
    });
    defer composer.deinit();
    const chrome_source = try composer.registerSource();
    var chrome_content = try render_api.chrome.Content.init(allocator, .{
        .primitives = 256,
        .text_bytes = (session_chrome_adapter.max_tabs + session_chrome_adapter.max_panes_per_tab) * session_chrome_adapter.max_label_bytes,
        .label_scalars = 4096,
        .shaped_glyphs = 4096,
        .glyphs = 512,
        .commands = 2048,
        .resources_per_update = 512,
        .upload_bytes = 8 * 1024 * 1024,
        .raster_bytes = 512 * 1024,
    }, .{ .primary = font_path, .size = .{ .pixels = 16 } });
    defer chrome_content.deinit();
    const frame_uploads = try allocator.alloc(
        render_api.canvas.ResourceUploadFact,
        frame_resource_limit,
    );
    defer allocator.free(frame_uploads);
    const frame_removals = try allocator.alloc(
        render_api.canvas.FrameResourceRef,
        frame_resource_limit,
    );
    defer allocator.free(frame_removals);
    const frame_commands = try allocator.alloc(
        render_api.canvas.Command,
        replay_command_limit,
    );
    defer allocator.free(frame_commands);
    const frame_pixels = try allocator.alloc(u8, 8 * 1024 * 1024);
    defer allocator.free(frame_pixels);
    var surface_uploads: [frame_resource_limit]vk_surface.Upload = undefined;
    var surface_removals: [frame_resource_limit]vk_surface.Removal = undefined;
    const surface_commands = try allocator.alloc(
        vk_surface.FrameCommand,
        replay_command_limit,
    );
    defer allocator.free(surface_commands);
    var surface_residencies: [frame_resource_limit]vk_surface.Residency = undefined;
    var canvas_residencies: [frame_resource_limit]render_api.canvas.Residency = undefined;
    var surface_builder = try vk_surface.FrameBuilder.init(allocator);
    defer surface_builder.deinit();
    var surface_residency = try vk_surface.ResidencyStore.init(allocator, .{
        .resources = frame_resource_limit,
        .pixel_bytes = 8 * 1024 * 1024,
    });
    defer surface_residency.deinit();
    var replay = try ReplayState.init(allocator);
    defer replay.deinit();
    var canvas_work = CanvasWork{
        .composer = &composer,
        .content = &chrome_content,
        .source = chrome_source,
        .surface = renderExtent(initial_surface),
        .content_origin = try session_chrome_adapter.contentOrigin(renderExtent(initial_surface), session_chrome_adapter.default_tab_bar_height),
        .frame_uploads = frame_uploads,
        .frame_removals = frame_removals,
        .frame_commands = frame_commands,
        .frame_pixels = frame_pixels,
        .surface_uploads = &surface_uploads,
        .surface_removals = &surface_removals,
        .surface_commands = surface_commands,
        .surface_residencies = &surface_residencies,
        .canvas_residencies = &canvas_residencies,
        .builder = &surface_builder,
        .residency = &surface_residency,
        .terminals = terminals,
        .cursor_policy = cursor_policy,
        .terminal_font_policy = try terminal_handoff.FontPolicy.init(
            configured_terminal_base_points,
        ),
        .replay = &replay,
    };
    resetTrailRecords(&canvas_work);
    try reconcileTrailTopology(&canvas_work, &chrome);
    try retainTerminalScale(
        canvas_work.terminals,
        canvas_work.terminal_font_policy,
        &canvas_work.terminal_scale,
        &canvas_work.font_request_high_water,
        initial_surface,
    );
    var chrome_primitives: [256]render_api.chrome.Primitive = undefined;
    var chrome_text: [(session_chrome_adapter.max_tabs + session_chrome_adapter.max_panes_per_tab) * session_chrome_adapter.max_label_bytes]u8 = undefined;
    if (feedback.device == 0 or feedback.fourcc != 0x34324241) return error.UnsupportedFeedback;

    var application = std.mem.zeroes(vk.VkApplicationInfo);
    application.sType = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO;
    application.pApplicationName = "howl-host";
    application.applicationVersion = vk.VK_MAKE_VERSION(0, 1, 3);
    application.pEngineName = "none";
    application.engineVersion = 0;
    application.apiVersion = vk.VK_API_VERSION_1_3;
    var instance_info = std.mem.zeroes(vk.VkInstanceCreateInfo);
    instance_info.sType = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    instance_info.pApplicationInfo = &application;
    var instance: vk.VkInstance = undefined;
    if (vk.vkCreateInstance(&instance_info, null, &instance) != vk.VK_SUCCESS) return error.VulkanInstance;
    defer vk.vkDestroyInstance(instance, null);

    const selected = try selectPhysical(instance, feedback.device);
    const physical = selected.device;
    try requireExtensions(physical);
    var synchronization2 = std.mem.zeroes(vk.VkPhysicalDeviceSynchronization2Features);
    synchronization2.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES;
    var timeline = std.mem.zeroes(vk.VkPhysicalDeviceTimelineSemaphoreFeatures);
    timeline.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TIMELINE_SEMAPHORE_FEATURES;
    synchronization2.pNext = @ptrCast(&timeline);
    var features = std.mem.zeroes(vk.VkPhysicalDeviceFeatures2);
    features.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
    features.pNext = @ptrCast(&synchronization2);
    vk.vkGetPhysicalDeviceFeatures2(physical, &features);
    if (synchronization2.synchronization2 == 0 or timeline.timelineSemaphore == 0) return error.RequiredFeature;

    const dedicated_only = try queryFormat(physical, feedback.modifier);
    const family = try graphicsFamily(physical);
    const priority: f32 = 1;
    var queue_info = std.mem.zeroes(vk.VkDeviceQueueCreateInfo);
    queue_info.sType = vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    queue_info.queueFamilyIndex = family;
    queue_info.queueCount = 1;
    queue_info.pQueuePriorities = &priority;
    const names = [_][*:0]const u8{
        "VK_EXT_external_memory_dma_buf",
        "VK_EXT_image_drm_format_modifier",
        "VK_KHR_external_memory_fd",
        "VK_KHR_external_semaphore_fd",
        "VK_KHR_timeline_semaphore",
        "VK_KHR_synchronization2",
    };
    synchronization2.synchronization2 = vk.VK_TRUE;
    timeline.timelineSemaphore = vk.VK_TRUE;
    var device_info = std.mem.zeroes(vk.VkDeviceCreateInfo);
    device_info.sType = vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    device_info.pNext = @ptrCast(&synchronization2);
    device_info.queueCreateInfoCount = 1;
    device_info.pQueueCreateInfos = &queue_info;
    device_info.enabledExtensionCount = names.len;
    device_info.ppEnabledExtensionNames = @ptrCast(&names);
    var device: vk.VkDevice = undefined;
    if (vk.vkCreateDevice(physical, &device_info, null, &device) != vk.VK_SUCCESS) return error.VulkanDevice;
    defer vk.vkDestroyDevice(device, null);
    var queue: vk.VkQueue = undefined;
    vk.vkGetDeviceQueue(device, family, 0, &queue);
    if (queue == null) return error.VulkanDevice;

    const drm_fd = try openRenderNode(selected.render_major, selected.render_minor);
    defer closeDescriptor(drm_fd);
    const dispatch = howl_vk.dispatch.load(device) catch return error.FunctionLoad;

    var memory_properties: vk.VkPhysicalDeviceMemoryProperties = undefined;
    vk.vkGetPhysicalDeviceMemoryProperties(physical, &memory_properties);
    var gpu_bytes: u64 = 0;
    var graphics = try vk_surface.Context.init(device, memory_properties, &gpu_bytes, gpu_memory_limit);
    defer graphics.deinit(device, &gpu_bytes);
    const plane_count = try modifierPlaneCount(physical, feedback.modifier);
    var acquire_handle: u32 = 0;
    if (c.drmSyncobjCreate(drm_fd, 0, &acquire_handle) != 0) return error.Syncobj;
    defer destroySyncobj(drm_fd, acquire_handle);
    var rings = [_][window_render_boundary.slot_count]Slot{
        .{ .{}, .{}, .{} },
        .{ .{}, .{}, .{} },
    };
    defer {
        var ring_index = rings.len;
        while (ring_index > 0) {
            ring_index -= 1;
            var index = window_render_boundary.slot_count;
            while (index > 0) {
                index -= 1;
                rings[ring_index][index].deinit(device, drm_fd, &gpu_bytes);
            }
        }
    }
    var offers: [window_render_boundary.slot_count]window_render_boundary.SlotOffer = undefined;
    var offered_fds = [_]OfferedFds{ .{}, .{}, .{} };
    errdefer for (&offered_fds) |*fds| {
        if (fds.dma >= 0) closeDescriptor(fds.dma);
        if (fds.acquire >= 0) closeDescriptor(fds.acquire);
        if (fds.timeline >= 0) closeDescriptor(fds.timeline);
    };
    for (&rings[0], 0..) |*slot, index| {
        try constructSlot(slot, &graphics, device, memory_properties, feedback.modifier, dedicated_only, plane_count, initial_surface, &dispatch, drm_fd, &offers[index], &offered_fds[index], &gpu_bytes);
        if (c.drmSyncobjHandleToFD(drm_fd, acquire_handle, &offered_fds[index].acquire) != 0) return error.Syncobj;
        offers[index].acquire_timeline_fd = offered_fds[index].acquire;
    }
    try boundary.publishOffers(offers);
    for (&offered_fds) |*fds| fds.* = .{};
    try waitWindowRing(boundary, initial_surface.generation);
    try composer.setComposition(.{
        .surface = renderExtent(initial_surface),
        .sources = &.{},
    });

    var pool_info = std.mem.zeroes(vk.VkCommandPoolCreateInfo);
    pool_info.sType = vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    pool_info.flags = vk.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    pool_info.queueFamilyIndex = family;
    var pool: vk.VkCommandPool = undefined;
    if (vk.vkCreateCommandPool(device, &pool_info, null, &pool) != vk.VK_SUCCESS) return error.Command;
    defer vk.vkDestroyCommandPool(device, pool, null);
    var command_info = std.mem.zeroes(vk.VkCommandBufferAllocateInfo);
    command_info.sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    command_info.commandPool = pool;
    command_info.level = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    command_info.commandBufferCount = 1;
    var command: vk.VkCommandBuffer = undefined;
    if (vk.vkAllocateCommandBuffers(device, &command_info, &command) != vk.VK_SUCCESS) return error.Command;
    var queue_active = false;
    defer if (queue_active) {
        if (vk.vkDeviceWaitIdle(device) != vk.VK_SUCCESS) @panic("Render failed to quiesce Vulkan during cleanup");
    };

    const colors = [_][4]f32{
        .{ 0.08, 0.16, 0.24, 1 },
        .{ 0.12, 0.48, 0.20, 1 },
        .{ 0.52, 0.16, 0.56, 1 },
    };
    var next_acquire_point: u64 = 4;
    const initial_plan = try buildAcceptedCanvasPlan(&canvas_work);
    errdefer surface_residency.discard();
    errdefer replay.discard();
    for (&rings[0], 0..) |*slot, index| {
        queue_active = true;
        try render(&graphics, device, queue, family, command, slot, colors[index], initial_plan, surface_builder.alpha_pixels, surface_builder.rgba_pixels, if (index == 0) @as(?*vk_surface.ResidencyStore, &surface_residency) else null, null, &dispatch, drm_fd, acquire_handle, index + 1);
        try boundary.publishCompletion(.{ .generation = initial_surface.generation, .revision = index + 1, .slot = @intCast(index), .acquire_point = index + 1, .release_point = 1 });
        slot.release_point = 1;
    }
    replay.commit(window_render_boundary.slot_count - 1);

    // The first generation exercises real slot reuse before any resize: once
    // Window has superseded slot 0, import its compositor release fence into
    // a Vulkan wait semaphore, reacquire the image, and publish a fourth clear.
    try waitTimeline(drm_fd, rings[0][0].release_handle, 1);
    var release_sync_fd: i32 = -1;
    if (c.drmSyncobjExportSyncFile(drm_fd, rings[0][0].release_handle, &release_sync_fd) != 0) return error.Syncobj;
    errdefer if (release_sync_fd >= 0) closeDescriptor(release_sync_fd);
    const release_wait = try importReleaseSemaphore(device, &dispatch, &release_sync_fd);
    defer vk.vkDestroySemaphore(device, release_wait, null);
    const reuse_plan = try buildAcceptedCanvasPlan(&canvas_work);
    errdefer surface_residency.discard();
    errdefer replay.discard();
    try render(&graphics, device, queue, family, command, &rings[0][0], .{ 0.72, 0.18, 0.20, 1 }, reuse_plan, surface_builder.alpha_pixels, surface_builder.rgba_pixels, &surface_residency, release_wait, &dispatch, drm_fd, acquire_handle, next_acquire_point);
    try boundary.publishCompletion(.{ .generation = initial_surface.generation, .revision = next_acquire_point, .slot = 0, .acquire_point = next_acquire_point, .release_point = 2 });
    replay.commit(0);
    rings[0][0].release_point = 2;
    next_acquire_point += 1;

    var active_ring: usize = 0;
    var active_generation = initial_surface.generation;
    var actions = input_actions.State{};
    var terminal_redraw_pending = false;
    var cursor_replay_pending: ?terminal_handoff.CursorPublication = null;
    var local_redraw_retry_pending = false;
    var terminal_topology_committed = false;
    var deferred_topology_input: ?DeferredTopologyInput = null;
    var retained_configure: ?window_render_boundary.SurfaceConfig = null;
    var configure_work_pending = false;
    var pending_topology: ?PendingTopology =
        if (canvas_work.terminal_scale != null)
            try prepareInitialTerminalTopology(
                &canvas_work,
                &chrome,
                initial_surface,
            )
        else
            null;
    defer if (pending_topology) |*pending| pending.deinit();
    while (!boundary.shouldStop()) {
        if (boundary.takeConfigure()) |surface| {
            retainNewestConfigure(&retained_configure, surface);
            configure_work_pending = true;
        }
        if (configure_work_pending) {
            configure_work_pending = false;
            const surface = retained_configure.?;
            try retainTerminalScale(
                canvas_work.terminals,
                canvas_work.terminal_font_policy,
                &canvas_work.terminal_scale,
                &canvas_work.font_request_high_water,
                surface,
            );
            if (!terminal_topology_committed) {
                var candidate_chrome = chrome;
                const surface_extent = renderExtent(surface);
                const origin = session_chrome_adapter.contentOrigin(surface_extent, session_chrome_adapter.default_tab_bar_height) catch {
                    clearRetainedConfigure(&retained_configure);
                    continue;
                };
                candidate_chrome.resizeSurface(contentExtent(surface_extent, origin)) catch |failure| switch (failure) {
                    error.InvalidGeometry => {
                        clearRetainedConfigure(&retained_configure);
                        continue;
                    },
                    else => return failure,
                };
                if (pending_topology) |*pending| {
                    pending.deinit();
                    pending_topology = null;
                }
                chrome = candidate_chrome;
                if (canvas_work.terminal_scale != null)
                    pending_topology = try prepareInitialTerminalTopology(
                        &canvas_work,
                        &chrome,
                        surface,
                    );
                clearRetainedConfigure(&retained_configure);
                continue;
            }
            const pending_generation = if (pending_topology) |pending|
                if (pending.surface) |value| value.generation else active_generation
            else
                active_generation;
            if (surface.generation <= pending_generation) {
                clearRetainedConfigure(&retained_configure);
                continue;
            }
            const configure_disposition = try attemptConfigureReplacement(
                &canvas_work,
                &chrome,
                &pending_topology,
                surface,
            );
            applyConfigureDisposition(&retained_configure, configure_disposition);
        }
        if (terminal_topology_committed and deferred_topology_input == null)
            try drainInput(
                boundary,
                &actions,
                &canvas_work,
                &chrome,
                chrome_appearance,
                &pending_topology,
                &deferred_topology_input,
            );
        const local_redraw_retry_turn = local_redraw_retry_pending;
        local_redraw_retry_pending = false;
        if (!local_redraw_retry_turn) {
            const wake = try waitRenderWakeBlockingUntil(
                boundary,
                terminals,
                canvas_work.trail_deadline,
            );
            if (wake.terminal) {
                terminal_redraw_pending = terminals.hasReadyUpdates() or
                    terminal_redraw_pending;
                reconcileFocusedCursor(
                    terminals,
                    try session_chrome_adapter.toRenderPaneId(chrome.focusedPaneId()),
                    &cursor_replay_pending,
                );
                if (deferred_topology_input != null) {
                    switch (try retryDeferredTopologyInput(
                        &canvas_work,
                        &chrome,
                        &pending_topology,
                        &deferred_topology_input,
                        chrome_appearance,
                        canvas_work.surface,
                        canvas_work.content_origin,
                    )) {
                        .accepted => {},
                        .rejected => {},
                        .retry => {},
                    }
                }
                configure_work_pending = shouldRetryConfigureAfterWake(
                    retained_configure,
                    wake.terminal,
                );
            }
            if (wake.deadline and pending_topology == null and terminal_topology_committed) {
                const now = try monotonicNow();
                if (try prepareTrailAnimation(&canvas_work, &chrome, now))
                    canvas_work.trail_frame_pending = true;
            }
        }
        const terminal_status = terminals.status();
        if (terminal_status.stopped)
            return if (terminal_status.failed)
                error.TerminalRuntime
            else
                error.TerminalStopped;
        if (pending_topology) |*pending| {
            if (pending.phase == .awaiting_admission) {
                if (pending.observeAdmission()) |_| {
                    pending.deinit();
                    pending_topology = null;
                }
            }
            if (pending_topology) |*admitted| {
                if (admitted.phase == .admitted and admitted.surface != null) {
                    const surface = admitted.surface.?;
                    const admitted_surface_extent = renderExtent(surface);
                    const admitted_origin = try session_chrome_adapter.contentOrigin(
                        admitted_surface_extent,
                        session_chrome_adapter.default_tab_bar_height,
                    );
                    try checkGpuBudget(surface.physical_width, surface.physical_height);
                    if (!try releaseReplayRetirementIfReady(
                        boundary,
                        &replay,
                        active_generation,
                        &rings[active_ring],
                        drm_fd,
                    )) {
                        terminal_redraw_pending = true;
                        continue;
                    }
                    var bootstrap_publication: ?PreparedBootstrapPublication =
                        if (admitted.new_source != null)
                            try prepareBootstrapPublicationAt(
                                &canvas_work,
                                &admitted.candidate.state,
                                admitted.bootstrap(),
                                admitted_origin,
                            )
                        else
                            null;
                    defer if (bootstrap_publication) |*publication|
                        publication.deinit();
                    var local_retry_used = false;
                    const admission_result = retry: while (true) {
                        const result = try buildCanvasPlanAt(
                            &canvas_work,
                            &admitted.candidate.state,
                            admitted.revision,
                            admitted.bootstrap(),
                            chrome_appearance,
                            &chrome_primitives,
                            &chrome_text,
                            admitted_surface_extent,
                            admitted_origin,
                        );
                        switch (result) {
                            .retry => {
                                if (local_retry_used)
                                    return error.InvalidFrame;
                                local_retry_used = true;
                            },
                            else => break :retry result,
                        }
                    };
                    switch (admission_result) {
                        .blocked => {
                            terminal_redraw_pending = true;
                            continue;
                        },
                        .retry => return error.InvalidFrame,
                        .accepted => surface_residency.discard(),
                    }
                    const replacement = 1 - active_ring;
                    for (&rings[replacement]) |*slot| slot.* = .{};
                    var replacement_offers: [window_render_boundary.slot_count]window_render_boundary.SlotOffer = undefined;
                    var replacement_fds = [_]OfferedFds{ .{}, .{}, .{} };
                    errdefer for (&replacement_fds) |*fds| {
                        if (fds.dma >= 0) closeDescriptor(fds.dma);
                        if (fds.acquire >= 0) closeDescriptor(fds.acquire);
                        if (fds.timeline >= 0) closeDescriptor(fds.timeline);
                    };
                    var superseded = false;
                    for (&rings[replacement], 0..) |*slot, index| {
                        try constructSlot(slot, &graphics, device, memory_properties, feedback.modifier, dedicated_only, plane_count, surface, &dispatch, drm_fd, &replacement_offers[index], &replacement_fds[index], &gpu_bytes);
                        if (c.drmSyncobjHandleToFD(drm_fd, acquire_handle, &replacement_fds[index].acquire) != 0) return error.Syncobj;
                        replacement_offers[index].acquire_timeline_fd = replacement_fds[index].acquire;
                        if (!boundary.isLatestGeneration(surface.generation)) {
                            superseded = true;
                            break;
                        }
                    }
                    if (superseded) {
                        // The accepted plan was only a candidate until the
                        // replacement ring completed admission.  A stale
                        // generation must release its replay staging role
                        // before the next topology attempt can capture it.
                        replay.discard();
                        for (&replacement_fds) |*fds| {
                            if (fds.dma >= 0) closeDescriptor(fds.dma);
                            if (fds.acquire >= 0) closeDescriptor(fds.acquire);
                            if (fds.timeline >= 0) closeDescriptor(fds.timeline);
                            fds.* = .{};
                        }
                        for (&rings[replacement]) |*slot|
                            slot.deinit(device, drm_fd, &gpu_bytes);
                        continue;
                    }
                    boundary.publishOffers(replacement_offers) catch |failure| switch (failure) {
                        error.InvalidOffer => {
                            if (!boundary.isLatestGeneration(surface.generation)) {
                                replay.discard();
                                for (&replacement_fds) |*fds| {
                                    if (fds.dma >= 0) closeDescriptor(fds.dma);
                                    if (fds.acquire >= 0) closeDescriptor(fds.acquire);
                                    if (fds.timeline >= 0) closeDescriptor(fds.timeline);
                                    fds.* = .{};
                                }
                                for (&rings[replacement]) |*slot|
                                    slot.deinit(device, drm_fd, &gpu_bytes);
                                continue;
                            }
                            return failure;
                        },
                        else => return failure,
                    };
                    for (&replacement_fds) |*fds| fds.* = .{};
                    try waitWindowRing(boundary, surface.generation);
                    var completion_batch: [window_render_boundary.slot_count]window_render_boundary.Completion = undefined;
                    var candidate_acquire = next_acquire_point;
                    const resized_plan = try buildAcceptedCanvasPlan(&canvas_work);
                    errdefer surface_residency.discard();
                    errdefer replay.discard();
                    const resized_cursor_color = if (canvas_work.terminals.sourceFor(try session_chrome_adapter.toRenderPaneId(admitted.candidate.state.focusedPaneId()))) |source|
                        if (try cursorOverlayForBinding(&canvas_work, source)) |overlay| overlay.color else null
                    else
                        null;
                    const physical_resized_plan = try physicalPlanForBase(
                        &canvas_work,
                        resized_plan,
                        try session_chrome_adapter.toRenderPaneId(admitted.candidate.state.focusedPaneId()),
                        null,
                    );
                    for (&rings[replacement], 0..) |*slot, index| {
                        try render(&graphics, device, queue, family, command, slot, .{ 0.08 + @as(f32, @floatFromInt(index)) * 0.12, 0.22, 0.44, 1 }, physical_resized_plan, surface_builder.alpha_pixels, surface_builder.rgba_pixels, if (index == 0) @as(?*vk_surface.ResidencyStore, &surface_residency) else null, null, &dispatch, drm_fd, acquire_handle, candidate_acquire);
                        completion_batch[index] = .{
                            .generation = surface.generation,
                            .revision = candidate_acquire,
                            .slot = @intCast(index),
                            .acquire_point = candidate_acquire,
                            .release_point = 1,
                        };
                        candidate_acquire = std.math.add(u64, candidate_acquire, 1) catch
                            return error.RevisionOverflow;
                    }
                    // The replacement ring has copied the cursor-bearing
                    // candidate. Keep the replay cohort itself cursor-free so
                    // the next physical cursor update starts from the new
                    // canonical base.
                    replay.restoreCandidateBase(resized_plan);
                    var prepared_completions = try boundary.prepareCompletions(&completion_batch);
                    defer prepared_completions.deinit();
                    try admitted.commit();
                    chrome = admitted.candidate.state;
                    canvas_work.surface = renderExtent(surface);
                    canvas_work.content_origin = try session_chrome_adapter.contentOrigin(
                        canvas_work.surface,
                        session_chrome_adapter.default_tab_bar_height,
                    );
                    terminal_topology_committed = true;
                    if (bootstrap_publication) |*publication|
                        publication.commit(&canvas_work);
                    prepared_completions.commit();
                    replay.commit(window_render_boundary.slot_count - 1);
                    if (resized_cursor_color) |color| canvas_work.accepted_cursor_color = color;
                    for (&rings[replacement]) |*slot| slot.release_point = 1;
                    next_acquire_point = candidate_acquire;
                    const old_ring = active_ring;
                    const old_generation = active_generation;
                    pending_topology = null;
                    active_ring = replacement;
                    active_generation = surface.generation;
                    try reconcileTrailTopology(&canvas_work, &chrome);
                    try syncAcceptedTrail(&canvas_work, &chrome, try monotonicNow(), true);
                    if (canvas_work.trail_transfer == null)
                        try acceptTrailSurfaceSnapshot(&canvas_work, chrome.activeTabId());
                    reconcileFocusedCursor(
                        terminals,
                        try session_chrome_adapter.toRenderPaneId(chrome.focusedPaneId()),
                        &cursor_replay_pending,
                    );
                    try waitReleasePoints(boundary, old_generation, &rings[old_ring], drm_fd);
                    boundary.requestWindowRingRetirement(old_generation);
                    try waitWindowRingRetired(boundary, old_generation);
                    if (replay.retiring_slot) |slot_index|
                        replay.releaseRetiring(slot_index);
                    for (&rings[old_ring]) |*slot|
                        slot.deinit(device, drm_fd, &gpu_bytes);
                } else if (admitted.phase == .admitted) {
                    var trail_candidate_carried = false;
                    const redraw_result = try redrawChrome(
                        boundary,
                        &chrome,
                        &canvas_work,
                        chrome_appearance,
                        &chrome_primitives,
                        &chrome_text,
                        &graphics,
                        device,
                        queue,
                        family,
                        command,
                        &rings[active_ring],
                        active_generation,
                        &dispatch,
                        drm_fd,
                        acquire_handle,
                        &next_acquire_point,
                        admitted,
                        false,
                        &trail_candidate_carried,
                    );
                    switch (try scheduleRedraw(
                        redraw_result,
                        local_redraw_retry_turn,
                    )) {
                        .wait => {
                            terminal_redraw_pending = true;
                        },
                        .retry => {
                            local_redraw_retry_pending = true;
                            terminal_redraw_pending = true;
                            continue;
                        },
                        .published => {
                            pending_topology = null;
                            if (cursor_replay_pending) |publication|
                                canvas_work.last_cursor_publication = publication;
                            canvas_work.trail_frame_pending = false;
                            discardTrailAnimation(&canvas_work, false);
                            // redrawChrome commits the pending topology in
                            // this branch.  Reconcile exact TabId trail
                            // ownership before binding the newly active tab;
                            // otherwise a same-surface tab creation reaches
                            // syncAcceptedTrail without a slot and becomes a
                            // fatal InvalidFrame.
                            try reconcileTrailTopology(&canvas_work, &chrome);
                            try syncAcceptedTrail(&canvas_work, &chrome, try monotonicNow(), false);
                            if (canvas_work.trail_transfer == null)
                                try acceptTrailSurfaceSnapshot(&canvas_work, chrome.activeTabId());
                            dropPendingCursor(&cursor_replay_pending);
                            reconcileFocusedCursor(
                                terminals,
                                try session_chrome_adapter.toRenderPaneId(chrome.focusedPaneId()),
                                &cursor_replay_pending,
                            );
                        },
                    }
                }
            }
        }
        if ((cursor_replay_pending != null or canvas_work.trail_frame_pending) and
            !terminal_redraw_pending and pending_topology == null and
            terminal_topology_committed)
        {
            const focused_pane = chrome.focusedPaneId();
            const focused_source = canvas_work.terminals.sourceFor(try session_chrome_adapter.toRenderPaneId(focused_pane));
            const trail_only = cursor_replay_pending == null;
            var trail_publication: ?terminal_handoff.CursorPublication =
                if (trail_only) canvas_work.last_cursor_publication else null;
            const replay_pending = if (trail_only) &trail_publication else &cursor_replay_pending;
            const replay_result = try replayCursorFrame(
                boundary,
                &canvas_work,
                replay_pending,
                focused_source,
                trail_only,
                &rings[active_ring],
                active_generation,
                &graphics,
                device,
                queue,
                family,
                command,
                &dispatch,
                drm_fd,
                acquire_handle,
                &next_acquire_point,
            );
            switch (replay_result) {
                .published => {
                    if (trail_only) {
                        commitTrailAnimation(&canvas_work);
                        canvas_work.trail_frame_pending = false;
                    } else {
                        canvas_work.last_cursor_publication = replay_pending.*;
                        dropPendingCursor(&cursor_replay_pending);
                        try syncAcceptedTrail(&canvas_work, &chrome, try monotonicNow(), false);
                        if (canvas_work.trail_transfer == null)
                            try acceptTrailSurfaceSnapshot(&canvas_work, chrome.activeTabId());
                    }
                },
                .retry => {
                    if (trail_only) discardTrailAnimation(&canvas_work, false);
                    local_redraw_retry_pending = true;
                },
                .rejected => {
                    discardRejectedCursorReplay(
                        &canvas_work,
                        &cursor_replay_pending,
                        trail_only,
                    );
                },
                .blocked => if (trail_only) discardTrailAnimation(&canvas_work, true),
            }
        }
        if (terminal_redraw_pending and pending_topology == null) {
            var trail_candidate_carried = false;
            const redraw_result = redrawChrome(
                boundary,
                &chrome,
                &canvas_work,
                chrome_appearance,
                &chrome_primitives,
                &chrome_text,
                &graphics,
                device,
                queue,
                family,
                command,
                &rings[active_ring],
                active_generation,
                &dispatch,
                drm_fd,
                acquire_handle,
                &next_acquire_point,
                null,
                cursor_replay_pending == null,
                &trail_candidate_carried,
            ) catch |failure| switch (failure) {
                error.NoReleasedSlot => continue,
                else => return failure,
            };
            switch (try scheduleRedraw(
                redraw_result,
                local_redraw_retry_turn,
            )) {
                .wait => terminal_redraw_pending = true,
                .retry => {
                    local_redraw_retry_pending = true;
                    terminal_redraw_pending = true;
                    continue;
                },
                .published => {
                    terminal_redraw_pending = false;
                    if (cursor_replay_pending) |publication|
                        canvas_work.last_cursor_publication = publication;
                    if (trail_candidate_carried) {
                        commitTrailAnimation(&canvas_work);
                        canvas_work.trail_frame_pending = false;
                    } else {
                        canvas_work.trail_frame_pending = false;
                        discardTrailAnimation(&canvas_work, false);
                    }
                    if (!trail_candidate_carried)
                        try syncAcceptedTrail(&canvas_work, &chrome, try monotonicNow(), false);
                    if (!trail_candidate_carried and canvas_work.trail_transfer == null)
                        try acceptTrailSurfaceSnapshot(&canvas_work, chrome.activeTabId());
                    dropPendingCursor(&cursor_replay_pending);
                },
            }
        }
    }
    try waitReleasePoints(boundary, active_generation, &rings[active_ring], drm_fd);
    boundary.requestWindowRingRetirement(active_generation);
    try waitWindowRingRetired(boundary, active_generation);
    if (vk.vkDeviceWaitIdle(device) != vk.VK_SUCCESS) return error.DeviceIdle;
    queue_active = false;
}

fn checkGpuBudget(width: u32, height: u32) !void {
    const pixels = std.math.mul(u64, width, height) catch return error.GpuMemoryLimit;
    // Reject impossible replacement geometry before Vulkan construction. The
    // six exported-image allocations are subsequently charged from their
    // exact VkMemoryRequirements.size alongside the shared atlas/staging.
    const bytes = std.math.mul(u64, pixels, 4 * window_render_boundary.slot_count * 2) catch return error.GpuMemoryLimit;
    if (bytes > gpu_memory_limit) return error.GpuMemoryLimit;
}

fn renderExtent(surface: window_render_boundary.SurfaceConfig) render_api.canvas.Size {
    return .{
        .width = @intCast(surface.logical_width),
        .height = @intCast(surface.logical_height),
    };
}

fn contentExtent(surface: render_api.canvas.Size, origin: session_chrome_adapter.ContentOrigin) session.Size {
    std.debug.assert(surface.width != 0 and surface.height != 0);
    std.debug.assert(origin.y < surface.height);
    return .{ .width = surface.width, .height = surface.height - origin.y };
}

fn retainTerminalScale(
    terminals: *terminal_handoff.Boundary,
    policy: terminal_handoff.FontPolicy,
    retained: *?terminal_handoff.ScaleSnapshot,
    request_high_water: *u64,
    surface: window_render_boundary.SurfaceConfig,
) !void {
    const snapshot = try terminalScaleSnapshot(surface);
    if (std.meta.eql(retained.*, snapshot)) return;
    const revision = std.math.add(u64, request_high_water.*, 1) catch
        return error.FontRevisionExhausted;
    try terminals.requestFont(.{
        .revision = revision,
        .scale = snapshot,
        .policy = policy,
    });
    request_high_water.* = revision;
    retained.* = snapshot;
}

fn retainNewestConfigure(
    retained: *?window_render_boundary.SurfaceConfig,
    incoming: window_render_boundary.SurfaceConfig,
) void {
    if (retained.* == null or incoming.generation > retained.*.?.generation)
        retained.* = incoming;
}

fn clearRetainedConfigure(
    retained: *?window_render_boundary.SurfaceConfig,
) void {
    retained.* = null;
}

fn applyConfigureDisposition(
    retained: *?window_render_boundary.SurfaceConfig,
    disposition: TopologyReplacementDisposition,
) void {
    switch (disposition) {
        .accepted, .rejected => clearRetainedConfigure(retained),
        .retry => {},
    }
}

fn shouldRetryConfigureAfterWake(
    retained: ?window_render_boundary.SurfaceConfig,
    terminal_wake: bool,
) bool {
    return terminal_wake and retained != null;
}

fn terminalScaleSnapshot(
    surface: window_render_boundary.SurfaceConfig,
) !?terminal_handoff.ScaleSnapshot {
    if (surface.dpi_x == null and surface.dpi_y == null) return null;
    const dpi_x = surface.dpi_x orelse return error.InvalidFrame;
    const dpi_y = surface.dpi_y orelse return error.InvalidFrame;
    if (surface.scale_revision == 0) return error.InvalidFrame;
    return .{
        .revision = surface.scale_revision,
        .dpi_x = .{
            .numerator = dpi_x.numerator,
            .denominator = dpi_x.denominator,
        },
        .dpi_y = .{
            .numerator = dpi_y.numerator,
            .denominator = dpi_y.denominator,
        },
    };
}

test "configure retention keeps only the newest generation" {
    var boundary = try window_render_boundary.Boundary.init(std.testing.io);
    defer boundary.deinit();
    const base = window_render_boundary.SurfaceConfig{
        .generation = 1,
        .logical_width = 800,
        .logical_height = 600,
        .physical_width = 800,
        .physical_height = 600,
        .scale_revision = 0,
        .buffer_scale = 1,
        .use_viewport = false,
    };
    try boundary.publishConfigure(800, 600, 800, 600, 0, null, null, 1, false);
    var retained: ?window_render_boundary.SurfaceConfig = boundary.takeConfigure();
    try std.testing.expectEqual(@as(u64, 1), retained.?.generation);
    var newer = base;
    newer.logical_width = 1024;
    try boundary.publishConfigure(1024, 600, 1024, 600, 0, null, null, 1, false);
    retainNewestConfigure(&retained, boundary.takeConfigure().?);
    try std.testing.expectEqual(@as(u64, 2), retained.?.generation);
    retainNewestConfigure(&retained, base);
    try std.testing.expectEqual(@as(u64, 2), retained.?.generation);
    applyConfigureDisposition(&retained, .retry);
    try std.testing.expect(retained != null);
    applyConfigureDisposition(&retained, .accepted);
    try std.testing.expect(retained == null);
    retained = base;
    applyConfigureDisposition(&retained, .rejected);
    try std.testing.expect(retained == null);
    retained = base;
    try std.testing.expect(shouldRetryConfigureAfterWake(retained, true));
    try std.testing.expect(!shouldRetryConfigureAfterWake(retained, false));
    try std.testing.expect(!shouldRetryConfigureAfterWake(null, true));
}

fn policyOffsetIndex(
    policy: *const terminal_handoff.FontPolicy,
    pane: render_api.chrome.PaneId,
) ?usize {
    for (policy.offsets[0..policy.count], 0..) |offset, index| {
        const retained = @backingInt(offset.pane);
        const requested = @backingInt(pane);
        if (retained == requested) return index;
        if (retained > requested) return null;
    }
    return null;
}

fn policyOffset(
    policy: *const terminal_handoff.FontPolicy,
    pane: render_api.chrome.PaneId,
) f64 {
    const index = policyOffsetIndex(policy, pane) orelse return 0.0;
    return policy.offsets[index].offset_points;
}

fn setPolicyOffset(
    policy: *terminal_handoff.FontPolicy,
    pane: render_api.chrome.PaneId,
    value: f64,
) error{ InvalidFontPolicy, FontPolicyCapacity }!void {
    if (@backingInt(pane) == 0 or
        !std.math.isFinite(value) or std.math.isNan(value))
        return error.InvalidFontPolicy;
    var next = policy.*;
    if (policyOffsetIndex(policy, pane)) |index| {
        if (value == 0.0) {
            var cursor = index;
            while (cursor + 1 < next.count) : (cursor += 1)
                next.offsets[cursor] = next.offsets[cursor + 1];
            next.count -= 1;
        } else {
            next.offsets[index].offset_points = value;
        }
    } else if (value != 0.0) {
        if (next.count == next.offsets.len) return error.FontPolicyCapacity;
        var index: usize = 0;
        while (index < next.count and
            @backingInt(next.offsets[index].pane) < @backingInt(pane)) : (index += 1)
        {}
        var cursor: usize = next.count;
        while (cursor > index) : (cursor -= 1)
            next.offsets[cursor] = next.offsets[cursor - 1];
        next.offsets[index] = .{ .pane = pane, .offset_points = value };
        next.count += 1;
    }
    policy.* = next;
}

fn pruneFontPolicy(
    policy: *terminal_handoff.FontPolicy,
    topology: *const session.SessionState,
) void {
    var next = policy.*;
    var retained: u8 = 0;
    for (policy.offsets[0..policy.count]) |offset| {
        if (!topologyContainsRender(topology, offset.pane)) continue;
        next.offsets[retained] = offset;
        retained += 1;
    }
    next.count = retained;
    policy.* = next;
}

fn adjustPolicyOffset(
    policy: *terminal_handoff.FontPolicy,
    pane: render_api.chrome.PaneId,
    delta: f64,
    scale: terminal_handoff.ScaleSnapshot,
) error{ InvalidFontPolicy, FontPolicyCapacity }!void {
    if (!std.math.isFinite(delta) or std.math.isNan(delta) or delta == 0.0)
        return error.InvalidFontPolicy;
    const floor = try pointFloor(scale);
    const ceiling = configured_terminal_base_points * 10.0;
    const offset = policyOffset(policy, pane);
    const raw = policy.base_point_size + offset;
    if (!std.math.isFinite(floor) or !std.math.isFinite(ceiling) or
        !std.math.isFinite(raw) or floor <= 0.0 or ceiling < floor)
        return error.InvalidFontPolicy;
    if ((delta < 0.0 and raw <= floor) or
        (delta > 0.0 and raw >= ceiling))
        return;
    const candidate = raw + delta;
    if (!std.math.isFinite(candidate)) return error.InvalidFontPolicy;
    if (delta < 0.0 and candidate <= floor)
        return setPolicyOffset(policy, pane, floor - policy.base_point_size);
    if (delta > 0.0 and candidate >= ceiling)
        return setPolicyOffset(
            policy,
            pane,
            ceiling - policy.base_point_size,
        );
    try setPolicyOffset(policy, pane, offset + delta);
}

fn pointFloor(
    scale: terminal_handoff.ScaleSnapshot,
) error{InvalidFontPolicy}!f64 {
    const dpi_x = @as(f64, @floatFromInt(scale.dpi_x.numerator)) /
        @as(f64, @floatFromInt(scale.dpi_x.denominator));
    const dpi_y = @as(f64, @floatFromInt(scale.dpi_y.numerator)) /
        @as(f64, @floatFromInt(scale.dpi_y.denominator));
    const floor = @max(72.0 / dpi_x, 72.0 / dpi_y);
    if (!std.math.isFinite(floor) or floor <= 0.0)
        return error.InvalidFontPolicy;
    return floor;
}

fn publishFontPolicy(
    terminals: *terminal_handoff.Boundary,
    policy: *terminal_handoff.FontPolicy,
    scale: ?terminal_handoff.ScaleSnapshot,
    request_high_water: *u64,
    candidate: terminal_handoff.FontPolicy,
) !void {
    if (std.meta.eql(candidate, policy.*)) return;
    const revision = std.math.add(u64, request_high_water.*, 1) catch
        return error.FontRevisionExhausted;
    try terminals.requestFont(.{
        .revision = revision,
        .scale = scale,
        .policy = candidate,
    });
    request_high_water.* = revision;
    policy.* = candidate;
}

fn requestPaneFontAction(
    terminals: *terminal_handoff.Boundary,
    policy: *terminal_handoff.FontPolicy,
    scale: ?terminal_handoff.ScaleSnapshot,
    request_high_water: *u64,
    topology: *const session.SessionState,
    action: input_actions.Action,
) !void {
    var candidate = policy.*;
    pruneFontPolicy(&candidate, topology);
    const pane = try session_chrome_adapter.toRenderPaneId(topology.focusedPaneId());
    switch (action) {
        .font_increase => try adjustPolicyOffset(
            &candidate,
            pane,
            1.0,
            scale orelse return error.FactualScaleUnavailable,
        ),
        .font_decrease => try adjustPolicyOffset(
            &candidate,
            pane,
            -1.0,
            scale orelse return error.FactualScaleUnavailable,
        ),
        .font_reset => try setPolicyOffset(&candidate, pane, 0.0),
        else => return error.InvalidFontAction,
    }
    try publishFontPolicy(
        terminals,
        policy,
        scale,
        request_high_water,
        candidate,
    );
}

fn requestBaseFontAction(
    terminals: *terminal_handoff.Boundary,
    policy: *terminal_handoff.FontPolicy,
    scale: ?terminal_handoff.ScaleSnapshot,
    request_high_water: *u64,
    topology: *const session.SessionState,
    action: input_actions.Action,
) !void {
    var candidate = policy.*;
    pruneFontPolicy(&candidate, topology);
    const ceiling = configured_terminal_base_points * 10.0;
    const requested = switch (action) {
        .font_base_increase => increase: {
            if (scale == null) return error.FactualScaleUnavailable;
            break :increase candidate.base_point_size + 1.0;
        },
        .font_base_decrease => decrease: {
            if (scale == null) return error.FactualScaleUnavailable;
            break :decrease candidate.base_point_size - 1.0;
        },
        .font_base_reset => configured_terminal_base_points,
        else => return error.InvalidFontAction,
    };
    if (!std.math.isFinite(requested)) return error.InvalidFontPolicy;
    const floor = if (scale) |factual|
        try pointFloor(factual)
    else
        0.0;
    candidate.base_point_size = std.math.clamp(requested, floor, ceiling);
    try publishFontPolicy(
        terminals,
        policy,
        scale,
        request_high_water,
        candidate,
    );
}

test "integer and fractional surfaces retain the logical Canvas extent" {
    const integer = window_render_boundary.SurfaceConfig{
        .generation = 1,
        .logical_width = 100,
        .logical_height = 80,
        .physical_width = 200,
        .physical_height = 160,
        .scale_revision = 1,
        .buffer_scale = 2,
        .use_viewport = false,
    };
    const fractional = window_render_boundary.SurfaceConfig{
        .generation = 2,
        .logical_width = 100,
        .logical_height = 80,
        .physical_width = 150,
        .physical_height = 120,
        .scale_revision = 2,
        .buffer_scale = 1,
        .use_viewport = true,
    };
    try std.testing.expectEqual(render_api.canvas.Size{ .width = 100, .height = 80 }, renderExtent(integer));
    try std.testing.expectEqual(render_api.canvas.Size{ .width = 100, .height = 80 }, renderExtent(fractional));
}

test "Renderer copies only factual accepted DPI through terminal Boundary" {
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(window_render_boundary.ExactRational));
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(window_render_boundary.SurfaceConfig));
    try std.testing.expectEqual(
        @as(usize, 24),
        @sizeOf(terminal_handoff.ScaleSnapshot),
    );
    try std.testing.expectEqual(
        @as(usize, 1_040),
        @sizeOf(terminal_handoff.FontPolicy),
    );
    try std.testing.expectEqual(
        @as(usize, 1_080),
        @sizeOf(terminal_handoff.FontRequest),
    );
    var terminals = try terminal_handoff.Boundary.init(
        std.testing.io,
        std.testing.allocator,
        .{
            .commands = 4,
            .upload_bytes = 16,
            .cells = 4,
            .rows = 4,
            .images = 1,
            .placements = 1,
            .image_bytes = 16,
            .glyphs = 4,
            .masks = 4,
            .resources_per_update = 4,
            .raster_bytes = 16,
            .decoration_bytes = 16,
        },
    );
    defer terminals.deinit();
    const policy = try terminal_handoff.FontPolicy.init(16.0);
    var retained: ?terminal_handoff.ScaleSnapshot = null;
    var request_high_water: u64 = 0;
    const provisional = window_render_boundary.SurfaceConfig{
        .generation = 1,
        .logical_width = 100,
        .logical_height = 80,
        .physical_width = 100,
        .physical_height = 80,
        .scale_revision = 0,
        .buffer_scale = 1,
        .use_viewport = false,
    };
    try retainTerminalScale(
        &terminals,
        policy,
        &retained,
        &request_high_water,
        provisional,
    );
    try std.testing.expect(retained == null);
    try std.testing.expect(terminals.takeFontRequest() == null);
    var accepted = provisional;
    accepted.generation = 2;
    accepted.scale_revision = 7;
    accepted.physical_width = 160;
    accepted.physical_height = 128;
    accepted.use_viewport = true;
    accepted.dpi_x = .{ .numerator = 768, .denominator = 5 };
    accepted.dpi_y = .{ .numerator = 768, .denominator = 5 };
    try retainTerminalScale(
        &terminals,
        policy,
        &retained,
        &request_high_water,
        accepted,
    );
    const request = terminals.takeFontRequest().?;
    const snapshot = request.scale.?;
    try std.testing.expectEqual(@as(u64, 7), snapshot.revision);
    try std.testing.expectEqual(
        terminal_handoff.ExactRational{
            .numerator = 768,
            .denominator = 5,
        },
        snapshot.dpi_x,
    );
    try retainTerminalScale(
        &terminals,
        policy,
        &retained,
        &request_high_water,
        accepted,
    );
    try std.testing.expect(terminals.takeFontRequest() == null);
    var awaiting = accepted;
    awaiting.generation = 3;
    awaiting.dpi_x = null;
    awaiting.dpi_y = null;
    try retainTerminalScale(
        &terminals,
        policy,
        &retained,
        &request_high_water,
        awaiting,
    );
    const cleared = terminals.takeFontRequest().?;
    try std.testing.expect(cleared.scale == null);
    try std.testing.expect(retained == null);
    accepted.scale_revision = 0;
    try std.testing.expectError(
        error.InvalidFrame,
        retainTerminalScale(
            &terminals,
            policy,
            &retained,
            &request_high_water,
            accepted,
        ),
    );
    try std.testing.expect(retained == null);
    try std.testing.expect(terminals.takeFontRequest() == null);
}

test "Renderer pane point mutations clamp independently and reset omits zero" {
    var policy = try terminal_handoff.FontPolicy.init(10.0);
    const first: render_api.chrome.PaneId = @fromBackingInt(1);
    const second: render_api.chrome.PaneId = @fromBackingInt(2);
    const scale = terminal_handoff.ScaleSnapshot{
        .revision = 1,
        .dpi_x = .{ .numerator = 72, .denominator = 1 },
        .dpi_y = .{ .numerator = 72, .denominator = 1 },
    };
    try setPolicyOffset(&policy, first, -9.0);
    try setPolicyOffset(&policy, second, 2.0);
    const retained_second = policyOffset(&policy, second);
    try adjustPolicyOffset(&policy, first, -1.0, scale);
    try std.testing.expectEqual(@as(f64, -9.0), policyOffset(&policy, first));
    try adjustPolicyOffset(&policy, first, 1.0, scale);
    try std.testing.expectEqual(@as(f64, -8.0), policyOffset(&policy, first));
    try std.testing.expectEqual(retained_second, policyOffset(&policy, second));
    try setPolicyOffset(&policy, first, 0.0);
    try std.testing.expectEqual(@as(f64, 0.0), policyOffset(&policy, first));
    try std.testing.expectEqual(@as(u8, 1), policy.count);
    try std.testing.expectEqual(second, policy.offsets[0].pane);
}

test "focused pane actions coalesce retained point state through real Boundary" {
    var terminals = try terminal_handoff.Boundary.init(
        std.testing.io,
        std.testing.allocator,
        .{
            .commands = 4,
            .upload_bytes = 16,
            .cells = 4,
            .rows = 4,
            .images = 1,
            .placements = 1,
            .image_bytes = 16,
            .glyphs = 4,
            .masks = 4,
            .resources_per_update = 4,
            .raster_bytes = 16,
            .decoration_bytes = 16,
        },
    );
    defer terminals.deinit();
    var topology = try session.SessionState.init(
        .{ .width = 100, .height = 80 },
    );
    const pane = topology.focusedPaneId();
    const render_pane = try session_chrome_adapter.toRenderPaneId(pane);
    var policy = try terminal_handoff.FontPolicy.init(10.0);
    const scale = terminal_handoff.ScaleSnapshot{
        .revision = 1,
        .dpi_x = .{ .numerator = 72, .denominator = 1 },
        .dpi_y = .{ .numerator = 72, .denominator = 1 },
    };
    var high_water: u64 = 0;
    try requestPaneFontAction(
        &terminals,
        &policy,
        scale,
        &high_water,
        &topology,
        .font_increase,
    );
    try requestPaneFontAction(
        &terminals,
        &policy,
        scale,
        &high_water,
        &topology,
        .font_increase,
    );
    const newest = terminals.takeFontRequest().?;
    try std.testing.expectEqual(@as(u64, 2), newest.revision);
    try std.testing.expectEqual(@as(f64, 2.0), policyOffset(&newest.policy, render_pane));
    try requestPaneFontAction(
        &terminals,
        &policy,
        scale,
        &high_water,
        &topology,
        .font_reset,
    );
    const reset = terminals.takeFontRequest().?;
    try std.testing.expectEqual(@as(u8, 0), reset.policy.count);
    try std.testing.expectEqual(@as(u64, 3), reset.revision);
}

test "policy pruning retains hidden panes and removes a full stale table" {
    var terminals = try terminal_handoff.Boundary.init(
        std.testing.io,
        std.testing.allocator,
        .{
            .commands = 4,
            .upload_bytes = 16,
            .cells = 4,
            .rows = 4,
            .images = 1,
            .placements = 1,
            .image_bytes = 16,
            .glyphs = 4,
            .masks = 4,
            .resources_per_update = 4,
            .raster_bytes = 16,
            .decoration_bytes = 16,
        },
    );
    defer terminals.deinit();
    var topology = try session.SessionState.init(
        .{ .width = 640, .height = 480 },
    );
    const first_tab = topology.tabId(0).?;
    const first = topology.focusedPaneId();
    const closed = try topology.split(first, .horizontal);
    const render_closed = try session_chrome_adapter.toRenderPaneId(closed);
    try topology.closePane(closed);
    const hidden_tab = try topology.createTab("hidden");
    try std.testing.expect(@backingInt(hidden_tab) != 0);
    const hidden = topology.focusedPaneId();
    const render_hidden = try session_chrome_adapter.toRenderPaneId(hidden);
    try topology.switchTab(first_tab);
    try std.testing.expectEqual(first, topology.focusedPaneId());

    var policy = try terminal_handoff.FontPolicy.init(16.0);
    policy.count = 64;
    policy.offsets[0] = .{ .pane = render_closed, .offset_points = 1.0 };
    policy.offsets[1] = .{ .pane = render_hidden, .offset_points = 2.0 };
    for (policy.offsets[2..], 0..) |*offset, index| {
        offset.* = .{
            .pane = @fromBackingInt(@intCast(100 + index)),
            .offset_points = 3.0,
        };
    }
    const scale = terminal_handoff.ScaleSnapshot{
        .revision = 1,
        .dpi_x = .{ .numerator = 96, .denominator = 1 },
        .dpi_y = .{ .numerator = 96, .denominator = 1 },
    };
    var high_water: u64 = 0;
    try requestPaneFontAction(
        &terminals,
        &policy,
        scale,
        &high_water,
        &topology,
        .font_increase,
    );
    const request = terminals.takeFontRequest().?;
    try std.testing.expectEqual(@as(u64, 1), request.revision);
    try std.testing.expectEqual(@as(u8, 2), request.policy.count);
    try std.testing.expectEqual(@as(f64, 1.0), policyOffset(&request.policy, try session_chrome_adapter.toRenderPaneId(first)));
    try std.testing.expectEqual(@as(f64, 2.0), policyOffset(&request.policy, render_hidden));
    try std.testing.expectEqual(@as(f64, 0.0), policyOffset(&request.policy, render_closed));
    try std.testing.expectEqual(request.policy, policy);
}

test "window base actions preserve every pane offset through real Boundary" {
    var terminals = try terminal_handoff.Boundary.init(
        std.testing.io,
        std.testing.allocator,
        .{
            .commands = 4,
            .upload_bytes = 16,
            .cells = 4,
            .rows = 4,
            .images = 1,
            .placements = 1,
            .image_bytes = 16,
            .glyphs = 4,
            .masks = 4,
            .resources_per_update = 4,
            .raster_bytes = 16,
            .decoration_bytes = 16,
        },
    );
    defer terminals.deinit();
    var topology = try session.SessionState.init(
        .{ .width = 320, .height = 240 },
    );
    const first = topology.focusedPaneId();
    const second = try topology.split(first, .horizontal);
    const render_first = try session_chrome_adapter.toRenderPaneId(first);
    const render_second = try session_chrome_adapter.toRenderPaneId(second);
    var policy = try terminal_handoff.FontPolicy.init(
        configured_terminal_base_points,
    );
    try setPolicyOffset(&policy, render_first, -2.0);
    try setPolicyOffset(&policy, render_second, 3.0);
    const retained_offsets = policy.offsets;
    const scale = terminal_handoff.ScaleSnapshot{
        .revision = 1,
        .dpi_x = .{ .numerator = 96, .denominator = 1 },
        .dpi_y = .{ .numerator = 96, .denominator = 1 },
    };
    var high_water: u64 = 0;
    try requestBaseFontAction(
        &terminals,
        &policy,
        scale,
        &high_water,
        &topology,
        .font_base_increase,
    );
    try std.testing.expectEqual(@as(f64, 13.0), policy.base_point_size);
    try std.testing.expectEqual(retained_offsets, policy.offsets);
    try requestBaseFontAction(
        &terminals,
        &policy,
        null,
        &high_water,
        &topology,
        .font_base_reset,
    );
    const reset_without_dpi = terminals.takeFontRequest().?;
    try std.testing.expect(reset_without_dpi.scale == null);
    try std.testing.expectEqual(
        configured_terminal_base_points,
        reset_without_dpi.policy.base_point_size,
    );
    try std.testing.expectEqual(retained_offsets, reset_without_dpi.policy.offsets);
    try requestBaseFontAction(
        &terminals,
        &policy,
        scale,
        &high_water,
        &topology,
        .font_base_decrease,
    );
    try requestBaseFontAction(
        &terminals,
        &policy,
        scale,
        &high_water,
        &topology,
        .font_base_increase,
    );
    const newest = terminals.takeFontRequest().?;
    try std.testing.expectEqual(
        configured_terminal_base_points,
        newest.policy.base_point_size,
    );
    try std.testing.expectEqual(retained_offsets, newest.policy.offsets);
    try std.testing.expectEqual(@as(u64, 4), newest.revision);
}

fn buildCanvasPlan(
    work: *CanvasWork,
    topology: *const session.SessionState,
    topology_revision: ?terminal_handoff.LifecycleRevision,
    bootstrap: ?BootstrapSource,
    appearance: session_chrome_adapter.Appearance,
    primitives: []render_api.chrome.Primitive,
    text: []u8,
) !CanvasPlanResult {
    return buildCanvasPlanAt(
        work,
        topology,
        topology_revision,
        bootstrap,
        appearance,
        primitives,
        text,
        work.surface,
        work.content_origin,
    );
}

fn buildCanvasPlanAt(
    work: *CanvasWork,
    topology: *const session.SessionState,
    topology_revision: ?terminal_handoff.LifecycleRevision,
    bootstrap: ?BootstrapSource,
    appearance: session_chrome_adapter.Appearance,
    primitives: []render_api.chrome.Primitive,
    text: []u8,
    surface_geometry: render_api.canvas.Size,
    content_origin: session_chrome_adapter.ContentOrigin,
) !CanvasPlanResult {
    while (work.terminals.takeRetired()) |retired| {
        if (work.retired_source_count == work.retired_sources.len)
            return error.InvalidTopology;
        work.retired_sources[work.retired_source_count] = .{
            .pane = retired.pane,
            .source = retired.source,
        };
        work.retired_source_count += 1;
    }
    var desired: [terminal_handoff.visible_member_limit]render_api.canvas.Composer.Placement = undefined;
    var desired_members: [terminal_handoff.visible_member_limit]terminal_handoff.VisibleMember = undefined;
    var desired_count: usize = 0;
    var desired_complete = true;
    var surface: render_api.canvas.Size = undefined;
    var producer_revision = work.producer_revision;
    var chrome_change: ?render_api.canvas.Composer.SourceChange = null;
    const retrying_chrome = work.chrome_retry != null;
    const retry_topology_revision = if (work.chrome_retry) |retry|
        retry.topology_revision
    else
        null;
    const retry_superseded = retrying_chrome and
        retry_topology_revision != topology_revision;
    if (work.chrome_retry) |retry| {
        surface = retry.surface;
        producer_revision = @backingInt(retry.update.revision);
        chrome_change = .{ .source = work.source, .update = retry.update };
        desired_count = retry.terminal_count;
        @memcpy(
            desired[0..desired_count],
            retry.terminal_placements[0..desired_count],
        );
    } else {
        const output = try session_chrome_adapter.project(
            topology,
            appearance,
            surface_geometry,
            content_origin,
            &.{},
            primitives,
            text,
        );
        try work.content.apply(output);
        const update = try work.content.takeUpdate();
        producer_revision = @backingInt(update.revision);
        if (producer_revision < work.producer_revision)
            return error.InvalidRevision;
        chrome_change = if (producer_revision > work.producer_revision) .{
            .source = work.source,
            .update = update,
        } else null;
        surface = output.surface;
        const active_tab = topology.activeTabIndex();
        for (0..topology.paneCount(active_tab)) |pane_index| {
            const pane = topology.paneId(active_tab, pane_index) orelse
                return error.InvalidTopology;
            const render_pane = try session_chrome_adapter.toRenderPaneId(pane);
            const source = work.terminals.sourceFor(render_pane) orelse
                if (bootstrap) |value|
                    if (value.pane == render_pane) value.source else {
                        desired_complete = false;
                        continue;
                    }
                else {
                    desired_complete = false;
                    continue;
                };
            if (desired_count == desired.len) return error.InvalidTopology;
            const rect = topology.paneRect(pane) orelse
                return error.InvalidTopology;
            const physical_rect = try session_chrome_adapter.toRenderRect(rect, content_origin);
            desired[desired_count] = .{
                .source = source,
                .origin = .{ .x = physical_rect.x, .y = physical_rect.y },
                .clip = physical_rect,
            };
            if (bootstrap == null or source != bootstrap.?.source) {
                desired_members[desired_count] = .{
                    .pane = render_pane,
                    .source = source,
                };
            }
            desired_count += 1;
        }
        if (desired_complete and bootstrap == null)
            try updateVisibleComposition(
                work,
                desired[0..desired_count],
                desired_members[0..desired_count],
            );
    }
    var claimed_visible_revision: ?u64 = null;
    const required_visible_revision = if (retry_superseded)
        null
    else if (work.chrome_retry) |retry|
        retry.visible_revision
    else
        work.pending_visible_revision;
    if (required_visible_revision) |revision| {
        if (desired_complete and
            (retrying_chrome or placementsEqual(
                desired[0..desired_count],
                work.pending_placements[0..work.pending_count],
            )) and
            work.terminals.visibleSetStatus(revision) == .ready)
        {
            work.terminals.claimVisibleSet(revision) catch |failure| switch (failure) {
                // The readiness check and exclusive claim are separate
                // locked observations. A terminal retirement or newer
                // producer can invalidate the request between them; keep
                // the accepted composition and retry the candidate instead
                // of turning that expected race into Renderer failure.
                error.Stale => return .blocked,
            };
            claimed_visible_revision = revision;
        }
    }
    errdefer if (claimed_visible_revision) |revision|
        work.terminals.releaseVisibleSetClaim(revision) catch
            @panic("visible-set composition claim could not be restored");
    var placements: [terminal_handoff.visible_member_limit + 1]render_api.canvas.Composer.Placement = undefined;
    const terminal_placements = if (retry_superseded)
        desired[0..0]
    else if (retrying_chrome)
        desired[0..desired_count]
    else if (bootstrap != null)
        desired[0..desired_count]
    else if (claimed_visible_revision != null)
        work.pending_placements[0..work.pending_count]
    else
        work.visible_placements[0..work.visible_count];
    const terminal_snapshot_exact = desired_complete and placementsEqual(
        terminal_placements,
        desired[0..desired_count],
    );
    var placement_count: usize = terminal_placements.len;
    @memcpy(placements[0..placement_count], terminal_placements);
    placements[placement_count] = .{
        .source = work.source,
        .origin = .{ .x = 0, .y = 0 },
        .clip = .{ .x = 0, .y = 0, .width = surface.width, .height = surface.height },
    };
    placement_count += 1;
    const focused_source = blk: {
        const focused_pane = topology.focusedPaneId();
        const render_focused_pane = try session_chrome_adapter.toRenderPaneId(focused_pane);
        if (work.terminals.sourceFor(render_focused_pane)) |source|
            if (placementContainsSource(terminal_placements, source)) break :blk source;
        if (bootstrap) |value| {
            if (value.pane == render_focused_pane and
                placementContainsSource(terminal_placements, value.source))
                break :blk value.source;
        }
        break :blk null;
    };
    if (!retrying_chrome and chrome_change != null) {
        var retry = ChromeRetry{
            .update = chrome_change.?.update,
            .surface = surface,
            .terminal_placements = undefined,
            .terminal_count = @intCast(terminal_placements.len),
            .visible_revision = claimed_visible_revision,
            .topology_revision = topology_revision,
        };
        @memcpy(
            retry.terminal_placements[0..terminal_placements.len],
            terminal_placements,
        );
        work.chrome_retry = retry;
    }
    const candidate_result: ?terminal_handoff.CandidateDrainResult =
        if (retrying_chrome and required_visible_revision != null and
        claimed_visible_revision == null)
            null
        else
            work.terminals.applyCandidate(
                work.composer,
                chrome_change,
                .{
                    .surface = surface,
                    .sources = placements[0..placement_count],
                    .focused_source = focused_source,
                },
                claimed_visible_revision,
                if (bootstrap != null and !retry_superseded)
                    .bootstrap_replacement
                else
                    .ordinary,
            ) catch |failure| switch (failure) {
                error.ResourceLimit,
                error.CommandLimit,
                error.PixelLimit,
                error.CompositionLimit,
                error.Stale,
                => blk: {
                    if (claimed_visible_revision) |revision| {
                        try work.terminals.releaseVisibleSetClaim(revision);
                        claimed_visible_revision = null;
                    }
                    break :blk null;
                },
                else => return failure,
            };
    if (candidate_result) |result| {
        if (result.accepted > session_chrome_adapter.max_live_panes)
            return error.InvalidFrame;
        if (chrome_change != null) {
            work.producer_revision = producer_revision;
            work.chrome_retry = null;
        }
        if (claimed_visible_revision != null) {
            @memcpy(
                work.visible_placements[0..work.pending_count],
                work.pending_placements[0..work.pending_count],
            );
            work.visible_count = work.pending_count;
            work.pending_visible_revision = null;
            work.pending_count = 0;
            claimed_visible_revision = null;
        } else if (bootstrap != null and !retry_superseded) {
            @memcpy(
                work.visible_placements[0..desired_count],
                desired[0..desired_count],
            );
            work.visible_count = @intCast(desired_count);
        }
    } else {
        return .blocked;
    }
    if (!terminal_snapshot_exact or
        (retrying_chrome and retry_topology_revision != topology_revision))
    {
        // A superseded retry is only a local retry when its stale update was
        // actually accepted and cleared.  If the cleanup candidate remains
        // blocked, preserve it for external progress instead of converting a
        // second local retry into a fatal InvalidFrame.
        return if (retrying_chrome and retry_superseded and work.chrome_retry == null)
            .retry
        else
            .blocked;
    }
    var retired_index: usize = 0;
    while (retired_index < work.retired_source_count) {
        const retired = work.retired_sources[retired_index];
        if (placementContainsSource(
            work.visible_placements[0..work.visible_count],
            retired.source,
        )) {
            retired_index += 1;
            continue;
        }
        try work.composer.removeSource(retired.source);
        try work.terminals.finishRetired(retired.pane);
        work.retired_source_count -= 1;
        work.retired_sources[retired_index] =
            work.retired_sources[work.retired_source_count];
    }
    const accepted = buildAcceptedCanvasPlan(work) catch |failure| switch (failure) {
        error.Retiring => return .blocked,
        else => return failure,
    };
    return .{ .accepted = accepted };
}

fn buildAcceptedCanvasPlan(work: *CanvasWork) !vk_surface.Plan {
    errdefer work.replay.discard();
    const surface_resident = try work.residency.enumerate(
        work.surface_residencies,
    );
    for (surface_resident, 0..) |value, index| {
        work.canvas_residencies[index] = .{
            .resource = try canvasResource(value.resource),
            .format = switch (value.kind) {
                .alpha_mask => .alpha8,
                .rgba => .rgba8,
                .solid => return error.InvalidFrame,
            },
            .size = .{ .width = value.width, .height = value.height },
        };
    }
    const base_frame = try work.composer.frameCursorFree(work.canvas_residencies[0..surface_resident.len], .{
        .uploads = work.frame_uploads,
        .removals = work.frame_removals,
        .commands = work.frame_commands,
        .pixels = work.frame_pixels,
    });
    const generic_base = try adaptCanvasFrame(base_frame, work.surface_uploads, work.surface_removals, work.surface_commands);
    try work.residency.stage(generic_base);
    errdefer work.residency.discard();
    const base_plan = try work.builder.build(work.residency, generic_base);
    try work.replay.capture(base_plan, generic_base);
    // The accepted Renderer cohort is deliberately cursor-free. Cursor
    // presentation is appended synchronously by the caller and the staging
    // cohort is restored to this exact base before ordinary commit.
    return base_plan;
}

fn updateVisibleComposition(
    work: *CanvasWork,
    desired: []const render_api.canvas.Composer.Placement,
    members: []const terminal_handoff.VisibleMember,
) !void {
    std.debug.assert(desired.len == members.len);
    if (work.pending_visible_revision) |revision| {
        if (placementsEqual(
            desired,
            work.pending_placements[0..work.pending_count],
        )) {
            switch (work.terminals.visibleSetStatus(revision)) {
                .pending => return,
                .stale => {
                    work.pending_visible_revision = null;
                    work.pending_count = 0;
                },
                .ready => {
                    return;
                },
            }
        }
    }
    if (placementsEqual(desired, work.visible_placements[0..work.visible_count]))
        return;
    const revision = work.next_visible_revision;
    work.next_visible_revision = std.math.add(u64, revision, 1) catch
        return error.RevisionOverflow;
    try work.terminals.publishVisibleSet(revision, members);
    @memcpy(work.pending_placements[0..desired.len], desired);
    work.pending_count = @intCast(desired.len);
    work.pending_visible_revision = revision;
}

fn prepareBootstrapPublication(
    work: *CanvasWork,
    topology: *const session.SessionState,
    bootstrap: ?BootstrapSource,
) !PreparedBootstrapPublication {
    return prepareBootstrapPublicationAt(
        work,
        topology,
        bootstrap,
        work.content_origin,
    );
}

fn prepareBootstrapPublicationAt(
    work: *CanvasWork,
    topology: *const session.SessionState,
    bootstrap: ?BootstrapSource,
    content_origin: session_chrome_adapter.ContentOrigin,
) !PreparedBootstrapPublication {
    var members: [terminal_handoff.visible_member_limit]terminal_handoff.VisibleMember =
        undefined;
    var placements: [terminal_handoff.visible_member_limit]render_api.canvas.Composer.Placement =
        undefined;
    var count: usize = 0;
    const active_tab = topology.activeTabIndex();
    for (0..topology.paneCount(active_tab)) |pane_index| {
        const pane = topology.paneId(active_tab, pane_index) orelse
            return error.InvalidTopology;
        const render_pane = try session_chrome_adapter.toRenderPaneId(pane);
        const source = work.terminals.sourceFor(render_pane) orelse
            if (bootstrap) |value|
                if (value.pane == render_pane) value.source else return error.InvalidTopology
            else
                return error.InvalidTopology;
        const rect = topology.paneRect(pane) orelse
            return error.InvalidTopology;
        const physical_rect = try session_chrome_adapter.toRenderRect(rect, content_origin);
        if (count == members.len) return error.InvalidTopology;
        members[count] = .{ .pane = render_pane, .source = source };
        placements[count] = .{
            .source = source,
            .origin = .{ .x = physical_rect.x, .y = physical_rect.y },
            .clip = physical_rect,
        };
        count += 1;
    }
    const revision = work.next_visible_revision;
    work.next_visible_revision = std.math.add(u64, revision, 1) catch
        return error.RevisionOverflow;
    return .{
        .boundary = try work.terminals.prepareVisibleSet(
            revision,
            members[0..count],
        ),
        .placements = placements,
        .count = @intCast(count),
    };
}

fn placementsEqual(
    left: []const render_api.canvas.Composer.Placement,
    right: []const render_api.canvas.Composer.Placement,
) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| if (!std.meta.eql(a, b)) return false;
    return true;
}

fn placementContainsSource(
    placements: []const render_api.canvas.Composer.Placement,
    source: render_api.canvas.SourceId,
) bool {
    for (placements) |placement| if (placement.source == source) return true;
    return false;
}

fn adaptCanvasFrame(
    frame: render_api.canvas.Composer.Frame,
    uploads: []vk_surface.Upload,
    removals: []vk_surface.Removal,
    commands: []vk_surface.FrameCommand,
) !vk_surface.Frame {
    if (frame.uploads.len > uploads.len or frame.removals.len > removals.len or frame.commands.len > commands.len) return error.Capacity;
    for (frame.uploads, 0..) |value, index| {
        const end = std.math.add(usize, value.pixel_offset, value.pixel_count) catch return error.ArithmeticOverflow;
        if (end > frame.pixels.len) return error.Capacity;
        uploads[index] = .{
            .resource = try surfaceResource(value.resource),
            .kind = switch (value.format) {
                .alpha8 => .alpha_mask,
                .rgba8 => .rgba,
            },
            .width = value.size.width,
            .height = value.size.height,
            .stride = value.stride,
            .pixels = frame.pixels[value.pixel_offset..end],
        };
    }
    for (frame.removals, 0..) |value, index| removals[index] = .{
        .resource = try surfaceResource(value),
    };
    for (frame.commands, 0..) |value, index| commands[index] = switch (value) {
        .solid => |solid| .{ .solid = .{ .rect = surfaceRect(solid.rect), .clip = surfaceRect(solid.rect), .color = surfaceColor(solid.color) } },
        .alpha_mask => |mask| .{ .alpha_mask = .{
            .rect = surfaceRect(mask.destination),
            .clip = surfaceRect(mask.clip),
            .resource = try surfaceResource(mask.resource.resource),
            .source = if (mask.resource.source) |source| .{ .x = source.x, .y = source.y, .width = source.width, .height = source.height } else null,
            .color = surfaceColor(mask.color),
            .cursor_component = mask.cursor_component,
        } },
        .rgba => |rgba| .{ .rgba = .{
            .rect = surfaceRect(rgba.destination),
            .clip = surfaceRect(rgba.clip),
            .resource = try surfaceResource(rgba.resource.resource),
            .source = if (rgba.resource.source) |source| .{ .x = source.x, .y = source.y, .width = source.width, .height = source.height } else null,
        } },
    };
    return .{
        .revision = @backingInt(frame.revision),
        .uploads = uploads[0..frame.uploads.len],
        .removals = removals[0..frame.removals.len],
        .commands = commands[0..frame.commands.len],
    };
}

fn surfaceResource(
    value: render_api.canvas.FrameResourceRef,
) error{InvalidFrame}!vk_surface.ResourceGeneration {
    return vk_surface.ResourceGeneration.init(
        @backingInt(value.source),
        @backingInt(value.resource),
        @backingInt(value.generation),
    ) catch error.InvalidFrame;
}

fn canvasResource(
    value: vk_surface.ResourceGeneration,
) error{InvalidFrame}!render_api.canvas.FrameResourceRef {
    const resource = render_api.canvas.ResourceId.fromEncoded(
        value.resource,
    ) catch return error.InvalidFrame;
    return render_api.canvas.FrameResourceRef.init(
        @fromBackingInt(@intCast(value.source)),
        resource,
        @fromBackingInt(@intCast(value.generation)),
    ) catch return error.InvalidFrame;
}

fn surfaceRect(value: render_api.canvas.Rect) vk_surface.Rect {
    return .{ .x = value.x, .y = value.y, .width = value.width, .height = value.height };
}

fn intersectSurfaceRect(left: vk_surface.Rect, right: vk_surface.Rect) ?vk_surface.Rect {
    const left_x = @max(left.x, right.x);
    const left_y = @max(left.y, right.y);
    const left_width = std.math.cast(i32, left.width) orelse return null;
    const right_width = std.math.cast(i32, right.width) orelse return null;
    const left_height = std.math.cast(i32, left.height) orelse return null;
    const right_height = std.math.cast(i32, right.height) orelse return null;
    const right_x = @min(
        std.math.add(i32, left.x, left_width) catch return null,
        std.math.add(i32, right.x, right_width) catch return null,
    );
    const right_y = @min(
        std.math.add(i32, left.y, left_height) catch return null,
        std.math.add(i32, right.y, right_height) catch return null,
    );
    if (right_x <= left_x or right_y <= left_y) return null;
    return .{
        .x = left_x,
        .y = left_y,
        .width = @intCast(right_x - left_x),
        .height = @intCast(right_y - left_y),
    };
}

fn translateSurfaceRect(
    local: vk_surface.Rect,
    placement: render_api.canvas.Composer.Placement,
) !vk_surface.Rect {
    return .{
        .x = std.math.add(i32, local.x, placement.origin.x) catch
            return error.InvalidFrame,
        .y = std.math.add(i32, local.y, placement.origin.y) catch
            return error.InvalidFrame,
        .width = local.width,
        .height = local.height,
    };
}

fn cursorOverlayForPlacement(
    binding: render_api.canvas.CursorBinding,
    placement: render_api.canvas.Composer.Placement,
) !?vk_surface.CursorOverlay {
    const local_rect = surfaceRect(binding.rect);
    const local_clip = surfaceRect(binding.clip);
    const rect = try translateSurfaceRect(local_rect, placement);
    const translated_clip = try translateSurfaceRect(local_clip, placement);
    const clip = intersectSurfaceRect(translated_clip, surfaceRect(placement.clip)) orelse
        return null;
    if (intersectSurfaceRect(rect, clip) == null) return null;
    const shape: vk_surface.CursorOverlayShape = switch (binding.shape) {
        .block => .block,
        .underline => .underline,
        .bar => .bar,
        .none => .none,
    };
    var shaped_rect = rect;
    switch (shape) {
        .underline => {
            shaped_rect.y = std.math.add(i32, shaped_rect.y, @intCast(shaped_rect.height - 1)) catch
                return error.InvalidFrame;
            shaped_rect.height = 1;
        },
        .bar => shaped_rect.width = 1,
        .block, .none => {},
    }
    return .{
        .rect = shaped_rect,
        .clip = clip,
        .shape = shape,
        .color = surfaceColor(binding.color),
        .text_color = surfaceColor(binding.text_color),
        .visible = binding.visible and shape != .none,
    };
}

fn placementForSource(
    work: *const CanvasWork,
    source: render_api.canvas.SourceId,
) ?render_api.canvas.Composer.Placement {
    for (work.visible_placements[0..work.visible_count]) |placement|
        if (placement.source == source) return placement;
    return null;
}

fn surfaceColor(value: render_api.canvas.Color) [4]f32 {
    return .{ @as(f32, @floatFromInt(value.r)) / 255.0, @as(f32, @floatFromInt(value.g)) / 255.0, @as(f32, @floatFromInt(value.b)) / 255.0, @as(f32, @floatFromInt(value.a)) / 255.0 };
}

fn cursorOverlayFor(
    work: *const CanvasWork,
    publication: terminal_handoff.CursorPublication,
    require_newer: bool,
) !?vk_surface.CursorOverlay {
    const binding = work.composer.cursorBinding(publication.source) orelse
        return null;
    if (binding.pane != @backingInt(publication.pane) or
        binding.source != publication.source or
        binding.cell_size.width == 0 or binding.cell_size.height == 0 or
        binding.visible_set_revision != publication.visible_set_revision or
        binding.lifecycle_revision != @backingInt(publication.lifecycle_revision) or
        (require_newer and publication.cursor_revision <= binding.cursor_revision) or
        publication.terminal_sequence < binding.terminal_sequence)
        return error.InvalidFrame;
    const placement = placementForSource(work, publication.source) orelse return null;
    const x_offset = std.math.mul(
        i32,
        @intCast(publication.target.col),
        @intCast(binding.cell_size.width),
    ) catch return error.InvalidFrame;
    const y_offset = std.math.mul(
        i32,
        @intCast(publication.target.row),
        @intCast(binding.cell_size.height),
    ) catch return error.InvalidFrame;
    var target_binding = binding;
    target_binding.rect = .{
        .x = std.math.add(i32, binding.cell_origin.x, x_offset) catch
            return error.InvalidFrame,
        .y = std.math.add(i32, binding.cell_origin.y, y_offset) catch
            return error.InvalidFrame,
        .width = binding.cell_size.width,
        .height = binding.cell_size.height,
    };
    target_binding.shape = switch (publication.target.shape) {
        .block => .block,
        .underline => .underline,
        .bar => .bar,
        .none => .none,
    };
    target_binding.color = .{
        .r = publication.target.cursor_color.r,
        .g = publication.target.cursor_color.g,
        .b = publication.target.cursor_color.b,
        .a = publication.target.cursor_color.a,
    };
    target_binding.text_color = .{
        .r = publication.target.text_color.r,
        .g = publication.target.text_color.g,
        .b = publication.target.text_color.b,
        .a = publication.target.text_color.a,
    };
    target_binding.visible = publication.target.visible;
    return cursorOverlayForPlacement(target_binding, placement);
}

fn cursorOverlayForBinding(
    work: *const CanvasWork,
    source: render_api.canvas.SourceId,
) !?vk_surface.CursorOverlay {
    const binding = work.composer.cursorBinding(source) orelse return null;
    const placement = placementForSource(work, source) orelse return null;
    return cursorOverlayForPlacement(binding, placement);
}

fn acceptedCursorOverlay(
    work: *const CanvasWork,
    source: render_api.canvas.SourceId,
) !CursorOverlayPreparation {
    return .{ .prepared = (try cursorOverlayForBinding(work, source)) orelse
        return .blocked };
}

fn publicationCursorOverlay(
    work: *const CanvasWork,
    publication: terminal_handoff.CursorPublication,
    require_newer: bool,
) !CursorOverlayPreparation {
    // Validate accepted Composer binding and placement facts independently.
    // Any error here is accepted-state corruption and must remain observable.
    if ((try cursorOverlayForBinding(work, publication.source)) == null)
        return .blocked;
    const overlay = cursorOverlayFor(
        work,
        publication,
        require_newer,
    ) catch return .rejected;
    return .{ .prepared = overlay orelse return .rejected };
}

test "accepted cursor geometry is fatal while publication mismatch rejects" {
    var composer = try render_api.canvas.Composer.init(std.testing.allocator, .{
        .sources = 1,
        .retained_resources = 1,
        .retained_commands = 1,
        .retained_pixel_bytes = 1,
        .composition_sources = 1,
        .candidate_resources = 1,
        .candidate_commands = 1,
        .candidate_pixel_bytes = 1,
    });
    defer composer.deinit();
    const source = try composer.registerSource();
    try composer.apply(source, .{
        .revision = @fromBackingInt(1),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{},
        .cursor_binding = .{
            .pane = 1,
            .source = source,
            .terminal_sequence = 1,
            .cursor_revision = 1,
            .visible_set_revision = 1,
            .lifecycle_revision = 1,
            .rect = .{ .x = 1, .y = 0, .width = 1, .height = 1 },
            .cell_size = .{ .width = 1, .height = 1 },
            .clip = .{ .x = 0, .y = 0, .width = 2, .height = 2 },
            .visible = true,
        },
    });
    var work: CanvasWork = undefined;
    work.composer = &composer;
    work.visible_count = 1;
    work.visible_placements[0] = .{
        .source = source,
        .origin = .{ .x = std.math.maxInt(i32), .y = 0 },
        .clip = .{ .x = 0, .y = 0, .width = 2, .height = 2 },
    };
    try std.testing.expectError(
        error.InvalidFrame,
        acceptedCursorOverlay(&work, source),
    );

    work.visible_placements[0].origin.x = 0;
    const publication = terminal_handoff.CursorPublication{
        .pane = @fromBackingInt(1),
        .source = source,
        .terminal_sequence = 1,
        .cursor_revision = 2,
        .visible_set_revision = 2,
        .lifecycle_revision = @fromBackingInt(1),
        .target = .{
            .row = 0,
            .col = 0,
            .visible = true,
            .shape = .block,
            .blink = false,
            .blink_fast = false,
            .cursor_color = .{},
            .text_color = .{},
        },
    };
    try std.testing.expectEqual(
        CursorOverlayPreparation.rejected,
        try publicationCursorOverlay(&work, publication, true),
    );
}

fn physicalPlanForBase(
    work: *CanvasWork,
    base: vk_surface.Plan,
    focused_pane: render_api.chrome.PaneId,
    trail: ?*const CursorTrail,
) !vk_surface.Plan {
    const source = work.terminals.sourceFor(focused_pane) orelse return base;
    var overlay = (try cursorOverlayForBinding(work, source)) orelse return base;
    if (trail) |value| {
        const trail_clip = try checkedTrailClipUnion(
            value.endpoint_clip,
            overlay.clip,
        );
        overlay.trail = .{
            .corner_x = value.corner_x,
            .corner_y = value.corner_y,
            .clip = trail_clip,
            .opacity = value.opacity,
            .color = work.accepted_cursor_color orelse overlay.color,
            .cursor_rect = overlay.rect,
        };
    }
    const candidate = work.replay.candidate();
    return vk_surface.replayCursor(
        base,
        overlay,
        .{
            .vertices = candidate.vertices,
            .indices = candidate.indices,
            .commands = candidate.commands,
        },
    );
}

fn waitFeedback(boundary: *window_render_boundary.Boundary) !window_render_boundary.Feedback {
    var wakes: u8 = 0;
    while (wakes < 8) : (wakes += 1) {
        if (boundary.readFeedback()) |value| return value;
        if (boundary.shouldStop()) return error.Stopping;
        try waitRenderWake(boundary);
    }
    return error.FeedbackTimeout;
}

fn waitConfigure(boundary: *window_render_boundary.Boundary) !window_render_boundary.SurfaceConfig {
    var wakes: u8 = 0;
    while (wakes < 32) : (wakes += 1) {
        if (boundary.takeConfigure()) |value| return value;
        if (boundary.shouldStop()) return error.Stopping;
        try waitRenderWake(boundary);
    }
    return error.ConfigureTimeout;
}

fn waitWindowRing(boundary: *window_render_boundary.Boundary, generation: u64) !void {
    const absolute = std.math.add(u64, try monotonicNow(), 2_000_000_000) catch
        return error.Clock;
    while (true) {
        if (boundary.isWindowRingReady(generation)) return;
        if (boundary.shouldStop()) return error.Stopping;
        if (!try waitRenderWakeUntil(boundary, absolute))
            return error.WindowRingTimeout;
    }
}

fn waitReleasePoints(boundary: *window_render_boundary.Boundary, generation: u64, slots: *[window_render_boundary.slot_count]Slot, drm_fd: i32) !void {
    if (generation == 0) return;
    var wakes: u8 = 0;
    while (wakes < 32) : (wakes += 1) {
        if (boundary.releaseFacts(generation)) |retired| {
            for (0..window_render_boundary.slot_count) |index| {
                if ((retired.presented_mask & (@as(u8, 1) << @intCast(index))) != 0) {
                    try waitTimeline(drm_fd, slots[index].release_handle, retired.release_points[index]);
                }
            }
            // Window has made the generation ineligible for any later
            // presentation. Presented slots have completed their release
            // points; unpresented wrappers were never acquired by compositor.
            for (slots) |*slot| slot.external = false;
            return;
        }
        try waitRenderWake(boundary);
    }
    return error.ReleaseObservationTimeout;
}

fn waitWindowRingRetired(boundary: *window_render_boundary.Boundary, generation: u64) !void {
    if (generation == 0) return;
    var wakes: u8 = 0;
    while (wakes < 32) : (wakes += 1) {
        if (boundary.takeWindowRingRetired(generation)) |_| return;
        try waitRenderWake(boundary);
    }
    return error.WindowRetirementTimeout;
}

fn waitRenderWake(boundary: *window_render_boundary.Boundary) !void {
    var descriptor = std.posix.pollfd{
        .fd = boundary.renderFd(),
        .events = std.posix.POLL.IN,
        .revents = 0,
    };
    const result = try pollWithoutDeadline(TypedPoll, (&descriptor)[0..1], 2_000);
    if (result > 0) {
        try boundary.drainRenderWake();
        return;
    }
    return error.WakeTimeout;
}

fn waitRenderWakeUntil(boundary: *window_render_boundary.Boundary, absolute: u64) !bool {
    var descriptor = std.posix.pollfd{
        .fd = boundary.renderFd(),
        .events = std.posix.POLL.IN,
        .revents = 0,
    };
    const ready = try pollUntil(DeadlinePoll, (&descriptor)[0..1], absolute) orelse return false;
    if (ready == 0) return error.Wake;
    try boundary.drainRenderWake();
    return true;
}

const RenderWake = struct {
    terminal: bool,
    deadline: bool,
};

fn waitRenderWakeBlockingUntil(
    boundary: *window_render_boundary.Boundary,
    terminals: *terminal_handoff.Boundary,
    absolute: ?u64,
) !RenderWake {
    var descriptors = [_]std.posix.pollfd{
        .{ .fd = boundary.renderFd(), .events = std.posix.POLL.IN, .revents = 0 },
        .{ .fd = terminals.rendererFd(), .events = std.posix.POLL.IN, .revents = 0 },
    };
    const result = if (absolute) |deadline_value|
        try pollUntil(DeadlinePoll, &descriptors, deadline_value) orelse
            return .{ .terminal = false, .deadline = true }
    else
        try pollWithoutDeadline(TypedPoll, &descriptors, -1);
    if (result == 0) return .{ .terminal = false, .deadline = true };
    const boundary_woke = descriptors[0].revents & std.posix.POLL.IN != 0;
    if (boundary_woke) try boundary.drainRenderWake();
    const terminal_dirty = descriptors[1].revents & std.posix.POLL.IN != 0;
    if (terminal_dirty) try terminals.drainRendererWake();
    return .{ .terminal = terminal_dirty, .deadline = false };
}

const DeadlinePoll = struct {
    fn now() !u64 {
        return monotonicNow();
    }

    fn poll(descriptors: []std.posix.pollfd, timeout: i32) c_int {
        return std.posix.system.poll(
            descriptors.ptr,
            @intCast(descriptors.len),
            timeout,
        );
    }

    fn errno(result: c_int) std.posix.E {
        return std.posix.errno(result);
    }
};

const TypedPoll = struct {
    fn poll(descriptors: []std.posix.pollfd, timeout: i32) std.posix.PollError!usize {
        return std.posix.poll(descriptors, timeout);
    }
};

fn pollWithoutDeadline(
    comptime Ops: type,
    descriptors: []std.posix.pollfd,
    timeout: i32,
) error{Wake}!usize {
    for (descriptors) |*descriptor| descriptor.revents = 0;
    return Ops.poll(descriptors, timeout) catch error.Wake;
}

fn pollUntil(
    comptime Ops: type,
    descriptors: []std.posix.pollfd,
    absolute: u64,
) !?usize {
    while (true) {
        const now = try Ops.now();
        if (now >= absolute) return null;
        const remaining = absolute - now;
        const milliseconds = std.math.divCeil(
            u64,
            remaining,
            std.time.ns_per_ms,
        ) catch return error.Clock;
        const timeout: i32 = @intCast(@min(
            milliseconds,
            @as(u64, std.math.maxInt(i32)),
        ));
        for (descriptors) |*descriptor| descriptor.revents = 0;
        const result = Ops.poll(descriptors, timeout);
        if (result > 0) return std.math.cast(usize, result) orelse return error.Wake;
        if (result == 0) return null;
        if (Ops.errno(result) == .INTR) continue;
        return error.Wake;
    }
}

test "Renderer poll preserves timeout ownership EINTR deadlines and wake classification" {
    const NonDeadline = struct {
        var call_count: u8 = 0;
        var timeouts: [2]i32 = .{ 0, 0 };
        var revents_clean: [2]bool = .{ false, false };

        fn poll(descriptors: []std.posix.pollfd, timeout: i32) std.posix.PollError!usize {
            timeouts[call_count] = timeout;
            revents_clean[call_count] = descriptors[0].revents == 0;
            call_count += 1;
            return 0;
        }
    };
    NonDeadline.call_count = 0;
    var descriptor = std.posix.pollfd{
        .fd = 7,
        .events = std.posix.POLL.IN,
        .revents = std.posix.POLL.HUP,
    };
    try std.testing.expectEqual(
        @as(usize, 0),
        try pollWithoutDeadline(NonDeadline, (&descriptor)[0..1], 2_000),
    );
    descriptor.revents = std.posix.POLL.ERR;
    try std.testing.expectEqual(
        @as(usize, 0),
        try pollWithoutDeadline(NonDeadline, (&descriptor)[0..1], 0),
    );
    try std.testing.expectEqual([2]i32{ 2_000, 0 }, NonDeadline.timeouts);
    try std.testing.expectEqual([2]bool{ true, true }, NonDeadline.revents_clean);

    const NonDeadlineFailure = struct {
        fn poll(_: []std.posix.pollfd, _: i32) std.posix.PollError!usize {
            return error.SystemResources;
        }
    };
    try std.testing.expectError(
        error.Wake,
        pollWithoutDeadline(NonDeadlineFailure, (&descriptor)[0..1], 2_000),
    );

    const InterruptedDeadline = struct {
        var now_count: u8 = 0;
        var poll_count: u8 = 0;
        var timeouts: [2]i32 = .{ 0, 0 };
        var revents_clean: [2]bool = .{ false, false };

        fn now() !u64 {
            const values = [2]u64{ 5 * std.time.ns_per_ms, 7 * std.time.ns_per_ms };
            const value = values[now_count];
            now_count += 1;
            return value;
        }

        fn poll(descriptors: []std.posix.pollfd, timeout: i32) c_int {
            timeouts[poll_count] = timeout;
            revents_clean[poll_count] = descriptors[0].revents == 0;
            if (poll_count == 0) descriptors[0].revents = std.posix.POLL.IN;
            poll_count += 1;
            return if (poll_count == 1) -1 else 0;
        }

        fn errno(_: c_int) std.posix.E {
            return .INTR;
        }
    };
    InterruptedDeadline.now_count = 0;
    InterruptedDeadline.poll_count = 0;
    descriptor.revents = std.posix.POLL.HUP;
    try std.testing.expect((try pollUntil(
        InterruptedDeadline,
        (&descriptor)[0..1],
        10 * std.time.ns_per_ms,
    )) == null);
    try std.testing.expectEqual([2]i32{ 5, 3 }, InterruptedDeadline.timeouts);
    try std.testing.expectEqual([2]bool{ true, true }, InterruptedDeadline.revents_clean);

    const DeadlineFailure = struct {
        fn now() !u64 {
            return 1;
        }

        fn poll(_: []std.posix.pollfd, _: i32) c_int {
            return -1;
        }

        fn errno(_: c_int) std.posix.E {
            return .BADF;
        }
    };
    try std.testing.expectError(
        error.Wake,
        pollUntil(DeadlineFailure, (&descriptor)[0..1], std.time.ns_per_ms),
    );

    const limits: render_api.terminal.Content.Limits = .{
        .commands = 32,
        .upload_bytes = 4096,
        .cells = 32,
        .rows = 4,
        .images = 1,
        .placements = 2,
        .image_bytes = 4096,
        .glyphs = 8,
        .masks = 2,
        .resources_per_update = 8,
        .raster_bytes = 4096,
        .decoration_bytes = 1024,
    };
    var boundary_only = try window_render_boundary.Boundary.init(std.testing.io);
    defer boundary_only.deinit();
    var quiet_terminals = try terminal_handoff.Boundary.init(
        std.testing.io,
        std.testing.allocator,
        limits,
    );
    defer quiet_terminals.deinit();
    boundary_only.requestStop(null);
    const boundary_wake = try waitRenderWakeBlockingUntil(
        &boundary_only,
        &quiet_terminals,
        null,
    );
    try std.testing.expect(!boundary_wake.terminal);
    try std.testing.expect(!boundary_wake.deadline);

    var quiet_boundary = try window_render_boundary.Boundary.init(std.testing.io);
    defer quiet_boundary.deinit();
    var terminal_only = try terminal_handoff.Boundary.init(
        std.testing.io,
        std.testing.allocator,
        limits,
    );
    defer terminal_only.deinit();
    terminal_only.shutdown();
    const terminal_wake = try waitRenderWakeBlockingUntil(
        &quiet_boundary,
        &terminal_only,
        null,
    );
    try std.testing.expect(terminal_wake.terminal);
    try std.testing.expect(!terminal_wake.deadline);
}

const InputErrorDisposition = enum { reject, fatal };

fn sessionCandidateDisposition(action: input_actions.Action, failure: session.Error) InputErrorDisposition {
    return switch (failure) {
        error.Capacity => switch (action) {
            .new_tab,
            .split_horizontal,
            .split_vertical,
            => .reject,
            else => .fatal,
        },
        error.InvalidGeometry => switch (action) {
            .split_horizontal,
            .split_vertical,
            .resize_left,
            .resize_right,
            .resize_up,
            .resize_down,
            => .reject,
            else => .fatal,
        },
        error.InvalidText,
        error.InvalidId,
        error.InvalidIdentity,
        error.InvalidScroll,
        error.ArithmeticOverflow,
        => .fatal,
    };
}

fn pointerCandidateDisposition(failure: input_actions.PointerError) InputErrorDisposition {
    return switch (failure) {
        error.Capacity,
        error.InvalidId,
        error.InvalidGeometry,
        => .reject,
        error.InvalidSurface,
        error.InvalidRectangle,
        error.InvalidTabBar,
        error.InvalidScrollbar,
        => .reject,
        error.InvalidText,
        error.InvalidScroll,
        error.InvalidIdentity,
        error.ArithmeticOverflow,
        error.InvalidOrder,
        error.InsufficientOutput,
        error.InsufficientText,
        error.AliasedStorage,
        => .fatal,
    };
}

fn pointerFoldDisposition(_: session.Error) InputErrorDisposition {
    return .fatal;
}

fn drainInput(
    boundary: *window_render_boundary.Boundary,
    actions: *input_actions.State,
    canvas_work: *CanvasWork,
    topology: *session.SessionState,
    appearance: session_chrome_adapter.Appearance,
    pending: *?PendingTopology,
    deferred: *?DeferredTopologyInput,
) !void {
    while (boundary.takeInput()) |event| {
        const basis = if (pending.*) |*value|
            &value.candidate.state
        else
            topology;
        var retry_input: ?DeferredTopologyInput = null;
        const candidate: ?session.SessionCandidate = switch (event) {
            .key => |key| key_result: {
                const decision = actions.key(key) catch |failure| switch (failure) {
                    error.CaptureFull => {
                        // The bounded host-capture table remains unchanged. The
                        // unmatched press and its later release both follow the
                        // ordinary terminal-input path instead of being lost.
                        try canvas_work.terminals.publishKey(
                            try session_chrome_adapter.toRenderPaneId(topology.focusedPaneId()),
                            key,
                        );
                        continue;
                    },
                };
                break :key_result switch (decision) {
                    .action => |action| action_result: {
                        break :action_result switch (action) {
                            .font_increase,
                            .font_decrease,
                            .font_reset,
                            .font_base_increase,
                            .font_base_decrease,
                            .font_base_reset,
                            => blk: {
                                switch (action) {
                                    .font_increase,
                                    .font_decrease,
                                    .font_reset,
                                    => requestPaneFontAction(
                                        canvas_work.terminals,
                                        &canvas_work.terminal_font_policy,
                                        canvas_work.terminal_scale,
                                        &canvas_work.font_request_high_water,
                                        topology,
                                        action,
                                    ) catch |failure| {
                                        const disposition: InputErrorDisposition = switch (failure) {
                                            error.Stopping,
                                            error.InvalidFontAction,
                                            error.ArithmeticOverflow,
                                            error.InvalidText,
                                            error.InvalidIdentity,
                                            error.InvalidScroll,
                                            error.InvalidSurface,
                                            error.InvalidRectangle,
                                            error.InvalidTabBar,
                                            error.InvalidScrollbar,
                                            error.InvalidOrder,
                                            error.InsufficientOutput,
                                            error.InsufficientText,
                                            error.AliasedStorage,
                                            => .fatal,
                                            else => .reject,
                                        };
                                        if (disposition == .fatal) return failure;
                                        continue;
                                    },
                                    .font_base_increase,
                                    .font_base_decrease,
                                    .font_base_reset,
                                    => requestBaseFontAction(
                                        canvas_work.terminals,
                                        &canvas_work.terminal_font_policy,
                                        canvas_work.terminal_scale,
                                        &canvas_work.font_request_high_water,
                                        topology,
                                        action,
                                    ) catch |failure| {
                                        const disposition: InputErrorDisposition = switch (failure) {
                                            error.Stopping, error.InvalidFontAction => .fatal,
                                            else => .reject,
                                        };
                                        if (disposition == .fatal) return failure;
                                        continue;
                                    },
                                    else => unreachable,
                                }
                                break :blk null;
                            },
                            else => candidate: {
                                retry_input = .{ .action = action };
                                break :candidate input_actions.candidate(
                                    basis,
                                    action,
                                ) catch |failure| switch (sessionCandidateDisposition(action, failure)) {
                                    .reject => continue,
                                    .fatal => return failure,
                                };
                            },
                        };
                    },
                    .consumed => null,
                    .unmatched => unmatched: {
                        try canvas_work.terminals.publishKey(
                            try session_chrome_adapter.toRenderPaneId(topology.focusedPaneId()),
                            key,
                        );
                        break :unmatched null;
                    },
                };
            },
            .keyboard_leave => reset: {
                try canvas_work.terminals.publishFocus(
                    try session_chrome_adapter.toRenderPaneId(topology.focusedPaneId()),
                    .{ .focus = .out },
                );
                actions.clear();
                break :reset null;
            },
            .keyboard_reset => reset: {
                actions.clear();
                break :reset null;
            },
            .button => |button| blk: {
                retry_input = .{ .button = button };
                const accepted = input_actions.pointerCandidate(
                    topology,
                    appearance,
                    canvas_work.surface,
                    canvas_work.content_origin,
                    button,
                ) catch |failure| switch (pointerCandidateDisposition(failure)) {
                    .reject => continue,
                    .fatal => return failure,
                };
                if (accepted == null or pending.* == null) break :blk accepted;
                break :blk foldPointerCandidate(
                    &pending.*.?.candidate.state,
                    topology,
                    &accepted.?.state,
                ) catch |failure| switch (pointerFoldDisposition(failure)) {
                    .reject => continue,
                    .fatal => return failure,
                };
            },
            .keyboard_enter => enter: {
                try canvas_work.terminals.publishFocus(
                    try session_chrome_adapter.toRenderPaneId(topology.focusedPaneId()),
                    .{ .focus = .in },
                );
                break :enter null;
            },
            .axis, .pointer_enter, .pointer_leave => null,
        };
        if (candidate) |next| {
            switch (try attemptTopologyReplacement(
                canvas_work,
                topology,
                next.state,
                pending,
                null,
            )) {
                .accepted => {},
                .rejected => {},
                .retry => {
                    deferred.* = retry_input.?;
                    return;
                },
            }
        }
    }
}

const PendingTopologyPhase = enum {
    awaiting_admission,
    admitted,
};

const PendingTopology = struct {
    candidate: session.SessionCandidate,
    composer: *render_api.canvas.Composer,
    lifecycle: terminal_handoff.Boundary.PreparedLifecycle,
    revision: terminal_handoff.LifecycleRevision,
    phase: PendingTopologyPhase = .awaiting_admission,
    new_pane: ?render_api.chrome.PaneId,
    new_source: ?render_api.canvas.SourceId,
    surface: ?window_render_boundary.SurfaceConfig = null,
    committed: bool = false,

    fn observeAdmission(self: *PendingTopology) ?terminal_handoff.AdmissionRejection {
        const result = self.lifecycle.admissionResult() orelse return null;
        switch (result) {
            .admitted => {
                self.phase = .admitted;
            },
            .rejected => |rejection| {
                return rejection;
            },
        }
        return null;
    }

    fn commit(self: *PendingTopology) !void {
        try self.lifecycle.commitAdmitted();
        self.committed = true;
    }

    fn bootstrap(self: *const PendingTopology) ?BootstrapSource {
        return if (self.new_pane) |pane| .{
            .pane = pane,
            .source = self.new_source.?,
        } else null;
    }

    fn deinit(self: *PendingTopology) void {
        if (self.committed) return;
        self.lifecycle.deinit();
        if (self.new_source) |source|
            self.composer.removeSource(source) catch
                @panic("prepared terminal source rollback failed");
    }
};

fn prepareTerminalTopology(
    work: *CanvasWork,
    current: *const session.SessionState,
    candidate: *const session.SessionState,
    surface: ?window_render_boundary.SurfaceConfig,
) !PendingTopology {
    var operations: [128]terminal_handoff.Lifecycle = undefined;
    var operation_count: usize = 0;
    var inputs: [2]terminal_handoff.TerminalInput = undefined;
    var input_count: usize = 0;
    var new_panes: usize = 0;
    var registration_pane: ?render_api.chrome.PaneId = null;
    for (0..candidate.tabCount()) |tab_index| {
        for (0..candidate.paneCount(tab_index)) |pane_index| {
            const pane = candidate.paneId(tab_index, pane_index) orelse
                return error.InvalidTopology;
            const render_pane = try session_chrome_adapter.toRenderPaneId(pane);
            const rect = candidate.paneRect(pane) orelse
                return error.InvalidTopology;
            const pixels = try panePixelsLocal(rect);
            if (!topologyContainsSemantic(current, pane)) {
                operations[operation_count] = .{ .create = .{
                    .pane = render_pane,
                    .pixels = pixels,
                } };
                operation_count += 1;
                new_panes += 1;
                registration_pane = render_pane;
            } else {
                const old_rect = current.paneRect(pane) orelse
                    return error.InvalidTopology;
                const old_pixels = try panePixelsLocal(old_rect);
                if (!std.meta.eql(old_pixels, pixels)) {
                    operations[operation_count] = .{ .resize = .{
                        .pane = render_pane,
                        .pixels = pixels,
                    } };
                    operation_count += 1;
                }
            }
        }
    }
    if (current.focusedPaneId() != candidate.focusedPaneId()) {
        // A closing focused owner is destroyed before copied input is
        // serviced, so it neither needs nor may receive a later focus-out.
        // Surviving owners still receive the exact focus transition.
        if (shouldPublishFocusOut(current, candidate)) {
            inputs[input_count] = .{ .focus = .{
                .pane = try session_chrome_adapter.toRenderPaneId(current.focusedPaneId()),
                .event = .{ .focus = .out },
            } };
            input_count += 1;
        }
        inputs[input_count] = .{ .focus = .{
            .pane = try session_chrome_adapter.toRenderPaneId(candidate.focusedPaneId()),
            .event = .{ .focus = .in },
        } };
        input_count += 1;
    }
    for (0..current.tabCount()) |tab_index| {
        for (0..current.paneCount(tab_index)) |pane_index| {
            const pane = current.paneId(tab_index, pane_index) orelse
                return error.InvalidTopology;
            if (!topologyContainsSemantic(candidate, pane)) {
                operations[operation_count] = .{ .close = try session_chrome_adapter.toRenderPaneId(pane) };
                operation_count += 1;
            }
        }
    }
    // Current Host actions admit at most one new terminal owner per redraw;
    // rejecting a wider candidate before any registration keeps slot/source
    // construction transactional without a second lifecycle pool.
    if (new_panes > 1) return error.TerminalCapacity;
    const source = if (registration_pane != null)
        try work.composer.registerSource()
    else
        null;
    errdefer if (source) |value|
        work.composer.removeSource(value) catch
            @panic("new terminal source rollback failed");
    const registration: ?terminal_handoff.Registration = if (source) |value|
        .{ .pane = registration_pane.?, .source = value }
    else
        null;
    var lifecycle = try work.terminals.prepareLifecycle(
        operations[0..operation_count],
        inputs[0..input_count],
        registration,
    );
    errdefer lifecycle.deinit();
    const revision = try lifecycle.publishAdmission();
    return .{
        .candidate = .{ .state = candidate.* },
        .composer = work.composer,
        .lifecycle = lifecycle,
        .revision = revision,
        .new_pane = registration_pane,
        .new_source = source,
        .surface = surface,
    };
}

fn prepareInitialTerminalTopology(
    work: *CanvasWork,
    candidate: *const session.SessionState,
    surface: window_render_boundary.SurfaceConfig,
) !PendingTopology {
    const pane = candidate.focusedPaneId();
    const render_pane = try session_chrome_adapter.toRenderPaneId(pane);
    const rect = candidate.paneRect(pane) orelse return error.InvalidTopology;
    const source = try work.composer.registerSource();
    errdefer work.composer.removeSource(source) catch
        @panic("initial terminal source rollback failed");
    const operations = [_]terminal_handoff.Lifecycle{.{ .create = .{
        .pane = render_pane,
        .pixels = try panePixelsLocal(rect),
    } }};
    var lifecycle = try work.terminals.prepareLifecycle(
        &operations,
        &.{},
        .{ .pane = render_pane, .source = source },
    );
    errdefer lifecycle.deinit();
    const revision = try lifecycle.publishAdmission();
    return .{
        .candidate = .{ .state = candidate.* },
        .composer = work.composer,
        .lifecycle = lifecycle,
        .revision = revision,
        .new_pane = render_pane,
        .new_source = source,
        .surface = surface,
    };
}

const TerminalTopologyRequirements = struct {
    operations: usize,
    inputs: usize,
    new_panes: usize,
};

const TopologyReplacementDisposition = enum {
    accepted,
    rejected,
    retry,
};

const DeferredTopologyInput = union(enum) {
    action: input_actions.Action,
    button: wayland.input.Button,
};

fn attemptTopologyReplacement(
    work: *CanvasWork,
    accepted: *const session.SessionState,
    prospective: session.SessionState,
    pending: *?PendingTopology,
    surface: ?window_render_boundary.SurfaceConfig,
) !TopologyReplacementDisposition {
    replacePendingTopology(
        work,
        accepted,
        prospective,
        pending,
        surface,
    ) catch |failure| switch (failure) {
        error.InvalidTopology,
        error.TerminalCapacity,
        error.InvalidPane,
        error.DuplicatePane,
        error.UnknownPane,
        => return .rejected,
        error.OwnerLimit,
        error.OperationLimit,
        error.CandidatePending,
        => return .retry,
        else => return failure,
    };
    return .accepted;
}

fn attemptConfigureReplacement(
    work: *CanvasWork,
    accepted: *const session.SessionState,
    pending: *?PendingTopology,
    surface: window_render_boundary.SurfaceConfig,
) !TopologyReplacementDisposition {
    var candidate_chrome = if (pending.*) |value|
        value.candidate.state
    else
        accepted.*;
    const surface_extent = renderExtent(surface);
    const origin = session_chrome_adapter.contentOrigin(
        surface_extent,
        session_chrome_adapter.default_tab_bar_height,
    ) catch |failure| switch (failure) {
        error.InvalidSurface => return .rejected,
        else => return failure,
    };
    candidate_chrome.resizeSurface(contentExtent(surface_extent, origin)) catch |failure| switch (failure) {
        error.InvalidGeometry => return .rejected,
        else => return failure,
    };
    return attemptTopologyReplacement(
        work,
        accepted,
        candidate_chrome,
        pending,
        surface,
    );
}

fn candidateForDeferredTopologyInput(
    deferred: DeferredTopologyInput,
    accepted: *const session.SessionState,
    pending: ?*const PendingTopology,
    appearance: session_chrome_adapter.Appearance,
    surface: session_chrome_adapter.SurfaceGeometry,
    origin: session_chrome_adapter.ContentOrigin,
) !?session.SessionCandidate {
    return switch (deferred) {
        .action => |action| input_actions.candidate(
            if (pending) |value| &value.candidate.state else accepted,
            action,
        ),
        .button => |button| blk: {
            const pointer = try input_actions.pointerCandidate(
                accepted,
                appearance,
                surface,
                origin,
                button,
            ) orelse break :blk null;
            break :blk if (pending) |value|
                try foldPointerCandidate(
                    &value.candidate.state,
                    accepted,
                    &pointer.state,
                )
            else
                pointer;
        },
    };
}

fn retryDeferredTopologyInput(
    work: *CanvasWork,
    accepted: *const session.SessionState,
    pending: *?PendingTopology,
    deferred: *?DeferredTopologyInput,
    appearance: session_chrome_adapter.Appearance,
    surface: session_chrome_adapter.SurfaceGeometry,
    origin: session_chrome_adapter.ContentOrigin,
) !TopologyReplacementDisposition {
    const retained = deferred.* orelse return .rejected;
    const candidate = try candidateForDeferredTopologyInput(
        retained,
        accepted,
        if (pending.*) |*value| value else null,
        appearance,
        surface,
        origin,
    ) orelse {
        deferred.* = null;
        return .rejected;
    };
    const disposition = try attemptTopologyReplacement(
        work,
        accepted,
        candidate.state,
        pending,
        null,
    );
    if (disposition != .retry) deferred.* = null;
    return disposition;
}

fn preflightTerminalTopology(
    current: *const session.SessionState,
    candidate: *const session.SessionState,
) !TerminalTopologyRequirements {
    try validateTerminalTopology(candidate);
    var operations: usize = 0;
    var new_panes: usize = 0;
    for (0..candidate.tabCount()) |tab_index| {
        for (0..candidate.paneCount(tab_index)) |pane_index| {
            const pane = candidate.paneId(tab_index, pane_index) orelse
                return error.InvalidTopology;
            if (!topologyContainsSemantic(current, pane)) new_panes += 1;
            const rect = candidate.paneRect(pane) orelse
                return error.InvalidTopology;
            if (!topologyContainsSemantic(current, pane) or
                !std.meta.eql(
                    try panePixelsLocal(rect),
                    try panePixelsLocal(current.paneRect(pane) orelse rect),
                ))
                operations += 1;
        }
    }
    for (0..current.tabCount()) |tab_index| {
        for (0..current.paneCount(tab_index)) |pane_index| {
            const pane = current.paneId(tab_index, pane_index) orelse
                return error.InvalidTopology;
            if (!topologyContainsSemantic(candidate, pane)) operations += 1;
        }
    }
    if (new_panes > 1 or operations > 128) return error.TerminalCapacity;
    const inputs: usize = if (current.focusedPaneId() ==
        candidate.focusedPaneId())
        0
    else if (shouldPublishFocusOut(current, candidate))
        2
    else
        1;
    return .{
        .operations = operations,
        .inputs = inputs,
        .new_panes = new_panes,
    };
}

fn replacePendingTopology(
    work: *CanvasWork,
    accepted: *const session.SessionState,
    prospective: session.SessionState,
    pending: *?PendingTopology,
    surface: ?window_render_boundary.SurfaceConfig,
) !void {
    const requirements = preflightTerminalTopology(accepted, &prospective) catch |failure| {
        return failure;
    };
    work.terminals.preflightLifecycleReplacement(
        requirements.operations,
        requirements.inputs,
        requirements.new_panes != 0,
    ) catch |failure| return failure;
    var retained_surface = surface;
    if (pending.*) |*old| {
        if (retained_surface == null) retained_surface = old.surface;
        old.deinit();
        pending.* = null;
    }
    pending.* = prepareTerminalTopology(
        work,
        accepted,
        &prospective,
        retained_surface,
    ) catch |failure| {
        return failure;
    };
}

fn foldPointerCandidate(
    pending: *const session.SessionState,
    accepted: *const session.SessionState,
    pointer: *const session.SessionState,
) !?session.SessionCandidate {
    var result = pending.*;
    var changed = false;
    if (pointer.activeTabId() != accepted.activeTabId()) {
        try result.switchTab(pointer.activeTabId());
        changed = true;
    }
    if (pointer.focusedPaneId() != accepted.focusedPaneId()) {
        const pane = pointer.focusedPaneId();
        if (result.paneLayer(pane) == .floating)
            try result.raiseFloatingPane(pane)
        else
            try result.focusPane(pane);
        changed = true;
    }
    return if (changed) .{ .state = result } else null;
}

fn topologyContainsRender(
    topology: *const session.SessionState,
    pane: render_api.chrome.PaneId,
) bool {
    const semantic_pane = session_chrome_adapter.fromRenderPaneId(pane) catch return false;
    return topology.paneRect(semantic_pane) != null;
}

fn topologyContainsSemantic(
    topology: *const session.SessionState,
    pane: session.PaneId,
) bool {
    return topology.paneRect(pane) != null;
}

fn shouldPublishFocusOut(
    current: *const session.SessionState,
    candidate: *const session.SessionState,
) bool {
    return current.focusedPaneId() != candidate.focusedPaneId() and
        topologyContainsSemantic(candidate, current.focusedPaneId());
}

test "focused close omits stale focus-out while surviving focus change retains it" {
    var current = try session.SessionState.init(
        .{ .width = 320, .height = 240 },
    );
    const first = current.focusedPaneId();
    const second = try current.split(first, .horizontal);
    var surviving = current;
    try surviving.focusPane(first);
    try std.testing.expect(shouldPublishFocusOut(&current, &surviving));
    var closing = current;
    try closing.closePane(second);
    try std.testing.expect(!shouldPublishFocusOut(&current, &closing));
}

fn admitPendingForTest(pending: *PendingTopology) !void {
    const request = pending.lifecycle.boundary.takeLifecycleAdmission().?;
    var result = terminal_handoff.LifecycleAdmissionResult{
        .admitted = .{ .count = 0 },
    };
    for (request.operations[0..request.operation_count]) |operation| switch (operation) {
        .create => |value| {
            result.admitted.grids[result.admitted.count] = .{
                .pane = value.pane,
                .rows = 1,
                .columns = 1,
            };
            result.admitted.count += 1;
        },
        .resize => |value| {
            result.admitted.grids[result.admitted.count] = .{
                .pane = value.pane,
                .rows = 1,
                .columns = 1,
            };
            result.admitted.count += 1;
        },
        .close => {},
    };
    try pending.lifecycle.boundary.completeLifecycleAdmission(
        request.revision,
        result,
    );
    try std.testing.expect(pending.observeAdmission() == null);
    try std.testing.expectEqual(PendingTopologyPhase.admitted, pending.phase);
}

const LifecycleShape = struct {
    operations: [128]terminal_handoff.Lifecycle = undefined,
    operation_count: u8,
    inputs: [2]terminal_handoff.TerminalInput = undefined,
    input_count: u8,
    registration_pane: ?render_api.chrome.PaneId,
    registration_source: ?render_api.canvas.SourceId,
};

fn lifecycleShapeForTest(
    current: *const session.SessionState,
    candidate: *const session.SessionState,
) !LifecycleShape {
    var boundary = try terminal_handoff.Boundary.init(
        std.testing.io,
        std.testing.allocator,
        .{
            .commands = 32_768,
            .upload_bytes = 4 * 1024 * 1024,
            .cells = 32_768,
            .rows = 128,
            .images = 8,
            .placements = 8,
            .image_bytes = 256 * 1024,
            .glyphs = 512,
            .masks = 128,
            .resources_per_update = terminal_retained_resource_limit,
            .raster_bytes = 4 * 1024 * 1024,
            .decoration_bytes = 256 * 1024,
        },
    );
    defer boundary.deinit();
    var composer = try render_api.canvas.Composer.init(std.testing.allocator, .{
        .sources = 4,
        .retained_resources = 1,
        .retained_commands = 1,
        .retained_pixel_bytes = 1,
        .composition_sources = 1,
        .candidate_resources = 1,
        .candidate_commands = 1,
        .candidate_pixel_bytes = 1,
    });
    defer composer.deinit();
    for (0..current.tabCount()) |tab_index| {
        for (0..current.paneCount(tab_index)) |pane_index| {
            const current_pane = current.paneId(tab_index, pane_index).?;
            const render_current_pane = try session_chrome_adapter.toRenderPaneId(current_pane);
            const source = try composer.registerSource();
            try boundary.register(render_current_pane, source, try panePixelsLocal(current.paneRect(current_pane).?));
            try std.testing.expect(boundary.takeLifecycle().? == .create);
            try boundary.markLive(render_current_pane);
        }
    }
    var work: CanvasWork = undefined;
    work.composer = &composer;
    work.terminals = &boundary;
    var prepared = try prepareTerminalTopology(&work, current, candidate, null);
    defer prepared.deinit();
    const request = boundary.takeLifecycleAdmission().?;
    var result = LifecycleShape{
        .operation_count = request.operation_count,
        .input_count = request.input_count,
        .registration_pane = if (request.registration) |registration| registration.pane else null,
        .registration_source = if (request.registration) |registration| registration.source else null,
    };
    @memcpy(result.operations[0..result.operation_count], request.operations[0..result.operation_count]);
    @memcpy(result.inputs[0..result.input_count], request.inputs[0..result.input_count]);
    return result;
}

test "session transitions derive exact Host lifecycle receipts" {
    var base = try session.SessionState.init(.{ .width = 321, .height = 217 });
    const base_pane = try session_chrome_adapter.toRenderPaneId(base.focusedPaneId());
    const no_op_shape = try lifecycleShapeForTest(&base, &base);
    try std.testing.expectEqual(@as(u8, 0), no_op_shape.operation_count);
    try std.testing.expectEqual(@as(u8, 0), no_op_shape.input_count);
    try std.testing.expect(no_op_shape.registration_pane == null);
    try std.testing.expect(no_op_shape.registration_source == null);

    var created = base;
    const created_tab = try created.createTab("other");
    try std.testing.expectEqual(@as(u64, 2), @backingInt(created_tab));
    const created_pane = try session_chrome_adapter.toRenderPaneId(created.focusedPaneId());
    const create_shape = try lifecycleShapeForTest(&base, &created);
    try std.testing.expectEqual(@as(u8, 1), create_shape.operation_count);
    try std.testing.expectEqual(@as(u8, 2), create_shape.input_count);
    try std.testing.expectEqual(created_pane, create_shape.registration_pane.?);
    try std.testing.expectEqual(@as(u64, 2), @backingInt(create_shape.registration_source.?));
    switch (create_shape.operations[0]) {
        .create => |operation| {
            try std.testing.expectEqual(created_pane, operation.pane);
            try std.testing.expectEqual(render_api.canvas.Size{ .width = 321, .height = 217 }, operation.pixels);
        },
        else => return error.TestUnexpectedResult,
    }
    switch (create_shape.inputs[0]) {
        .focus => |input| {
            try std.testing.expectEqual(base_pane, input.pane);
            switch (input.event) {
                .focus => |event| try std.testing.expectEqual(@as(@TypeOf(event), .out), event),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
    switch (create_shape.inputs[1]) {
        .focus => |input| {
            try std.testing.expectEqual(created_pane, input.pane);
            switch (input.event) {
                .focus => |event| try std.testing.expectEqual(@as(@TypeOf(event), .in), event),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }

    var resized = base;
    try resized.resizeSurface(.{ .width = 322, .height = 218 });
    const resize_shape = try lifecycleShapeForTest(&base, &resized);
    try std.testing.expectEqual(@as(u8, 1), resize_shape.operation_count);
    try std.testing.expectEqual(@as(u8, 0), resize_shape.input_count);
    try std.testing.expect(resize_shape.registration_pane == null);
    try std.testing.expect(resize_shape.registration_source == null);
    switch (resize_shape.operations[0]) {
        .resize => |operation| {
            try std.testing.expectEqual(base_pane, operation.pane);
            try std.testing.expectEqual(render_api.canvas.Size{ .width = 322, .height = 218 }, operation.pixels);
        },
        else => return error.TestUnexpectedResult,
    }

    var closed = created;
    try closed.closeTab(closed.activeTabId());
    const close_shape = try lifecycleShapeForTest(&created, &closed);
    try std.testing.expectEqual(@as(u8, 1), close_shape.operation_count);
    try std.testing.expectEqual(@as(u8, 1), close_shape.input_count);
    try std.testing.expect(close_shape.registration_pane == null);
    try std.testing.expect(close_shape.registration_source == null);
    switch (close_shape.operations[0]) {
        .close => |pane| try std.testing.expectEqual(created_pane, pane),
        else => return error.TestUnexpectedResult,
    }
    switch (close_shape.inputs[0]) {
        .focus => |input| {
            try std.testing.expectEqual(base_pane, input.pane);
            switch (input.event) {
                .focus => |event| try std.testing.expectEqual(@as(@TypeOf(event), .in), event),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }

    var focused = base;
    const focused_pane = try focused.split(focused.focusedPaneId(), .vertical);
    const render_focused_pane = try session_chrome_adapter.toRenderPaneId(focused_pane);
    try focused.focusPane(focused_pane);
    const focus_shape = try lifecycleShapeForTest(&base, &focused);
    try std.testing.expectEqual(@as(u8, 2), focus_shape.operation_count);
    try std.testing.expectEqual(@as(u8, 2), focus_shape.input_count);
    try std.testing.expectEqual(render_focused_pane, focus_shape.registration_pane.?);
    try std.testing.expectEqual(@as(u64, 2), @backingInt(focus_shape.registration_source.?));
    switch (focus_shape.operations[0]) {
        .resize => |operation| {
            try std.testing.expectEqual(base_pane, operation.pane);
            try std.testing.expectEqual(render_api.canvas.Size{ .width = 160, .height = 217 }, operation.pixels);
        },
        else => return error.TestUnexpectedResult,
    }
    switch (focus_shape.operations[1]) {
        .create => |operation| {
            try std.testing.expectEqual(render_focused_pane, operation.pane);
            try std.testing.expectEqual(render_api.canvas.Size{ .width = 161, .height = 217 }, operation.pixels);
        },
        else => return error.TestUnexpectedResult,
    }
    switch (focus_shape.inputs[0]) {
        .focus => |input| {
            try std.testing.expectEqual(base_pane, input.pane);
            switch (input.event) {
                .focus => |event| try std.testing.expectEqual(@as(@TypeOf(event), .out), event),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
    switch (focus_shape.inputs[1]) {
        .focus => |input| {
            try std.testing.expectEqual(render_focused_pane, input.pane);
            switch (input.event) {
                .focus => |event| try std.testing.expectEqual(@as(@TypeOf(event), .in), event),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "terminal lifecycle copies exact pane pixels even when grid quantization could match" {
    var boundary = try terminal_handoff.Boundary.init(
        std.testing.io,
        std.testing.allocator,
        .{
            .commands = 32_768,
            .upload_bytes = 4 * 1024 * 1024,
            .cells = 32_768,
            .rows = 128,
            .images = 8,
            .placements = 8,
            .image_bytes = 256 * 1024,
            .glyphs = 512,
            .masks = 128,
            .resources_per_update = terminal_retained_resource_limit,
            .raster_bytes = 4 * 1024 * 1024,
            .decoration_bytes = 256 * 1024,
        },
    );
    defer boundary.deinit();
    var composer = try render_api.canvas.Composer.init(std.testing.allocator, .{
        .sources = 2,
        .retained_resources = 1,
        .retained_commands = 1,
        .retained_pixel_bytes = 1,
        .composition_sources = 1,
        .candidate_resources = 1,
        .candidate_commands = 1,
        .candidate_pixel_bytes = 1,
    });
    defer composer.deinit();
    var current = try session.SessionState.init(
        .{ .width = 320, .height = 240 },
    );
    const pane = current.focusedPaneId();
    const initial_rect = current.paneRect(pane).?;
    const render_pane = try session_chrome_adapter.toRenderPaneId(pane);
    const source = try composer.registerSource();
    try boundary.register(render_pane, source, try panePixelsLocal(initial_rect));
    const created = boundary.takeLifecycle().?;
    try std.testing.expectEqual(
        try panePixelsLocal(initial_rect),
        created.create.pixels,
    );
    try boundary.markLive(render_pane);

    var candidate = current;
    try candidate.resizeSurface(.{ .width = 321, .height = 241 });
    const resized_rect = candidate.paneRect(pane).?;
    var work: CanvasWork = undefined;
    work.composer = &composer;
    work.terminals = &boundary;
    var prepared = try prepareTerminalTopology(
        &work,
        &current,
        &candidate,
        null,
    );
    defer prepared.deinit();
    try admitPendingForTest(&prepared);
    try prepared.commit();
    const resized = boundary.takeLifecycle().?;
    try std.testing.expectEqual(
        try panePixelsLocal(resized_rect),
        resized.resize.pixels,
    );
}

test "second pending pane creation preserves the first admitted candidate" {
    var boundary = try terminal_handoff.Boundary.init(
        std.testing.io,
        std.testing.allocator,
        .{
            .commands = 32_768,
            .upload_bytes = 4 * 1024 * 1024,
            .cells = 32_768,
            .rows = 128,
            .images = 8,
            .placements = 8,
            .image_bytes = 256 * 1024,
            .glyphs = 512,
            .masks = 128,
            .resources_per_update = terminal_retained_resource_limit,
            .raster_bytes = 4 * 1024 * 1024,
            .decoration_bytes = 256 * 1024,
        },
    );
    defer boundary.deinit();
    var composer = try render_api.canvas.Composer.init(std.testing.allocator, .{
        .sources = 2,
        .retained_resources = 1,
        .retained_commands = 1,
        .retained_pixel_bytes = 1,
        .composition_sources = 1,
        .candidate_resources = 1,
        .candidate_commands = 1,
        .candidate_pixel_bytes = 1,
    });
    defer composer.deinit();
    var accepted = try session.SessionState.init(
        .{ .width = 320, .height = 240 },
    );
    const first = accepted.focusedPaneId();
    const render_first = try session_chrome_adapter.toRenderPaneId(first);
    const first_source = try composer.registerSource();
    try boundary.register(
        render_first,
        first_source,
        try panePixelsLocal(accepted.paneRect(first).?),
    );
    try std.testing.expect(boundary.takeLifecycle().? == .create);
    try boundary.markLive(render_first);
    var split = accepted;
    const split_pane = try split.split(first, .horizontal);
    try std.testing.expect(@backingInt(split_pane) != 0);
    var work: CanvasWork = undefined;
    work.composer = &composer;
    work.terminals = &boundary;
    var pending: ?PendingTopology = try prepareTerminalTopology(
        &work,
        &accepted,
        &split,
        null,
    );
    defer if (pending) |*value| value.deinit();
    const revision = pending.?.revision;
    const source = pending.?.new_source;
    const pane_count = pending.?.candidate.state.paneCount(0);
    try std.testing.expectError(error.NotAdmitted, pending.?.commit());
    try std.testing.expectEqual(@as(usize, 1), accepted.paneCount(0));
    try std.testing.expect(boundary.takeLifecycle() == null);
    var second_split = pending.?.candidate.state;
    const second_split_pane = try second_split.split(
        second_split.focusedPaneId(),
        .vertical,
    );
    try std.testing.expect(@backingInt(second_split_pane) != 0);
    try std.testing.expectError(
        error.TerminalCapacity,
        replacePendingTopology(
            &work,
            &accepted,
            second_split,
            &pending,
            null,
        ),
    );
    try std.testing.expectEqual(revision, pending.?.revision);
    try std.testing.expectEqual(source, pending.?.new_source);
    try std.testing.expectEqual(pane_count, pending.?.candidate.state.paneCount(0));
    try std.testing.expect(boundary.takeLifecycle() == null);
}

test "pending focus resize close and reorder folds issue fresh identities" {
    var boundary = try terminal_handoff.Boundary.init(
        std.testing.io,
        std.testing.allocator,
        .{
            .commands = 32_768,
            .upload_bytes = 4 * 1024 * 1024,
            .cells = 32_768,
            .rows = 128,
            .images = 8,
            .placements = 8,
            .image_bytes = 256 * 1024,
            .glyphs = 512,
            .masks = 128,
            .resources_per_update = terminal_retained_resource_limit,
            .raster_bytes = 4 * 1024 * 1024,
            .decoration_bytes = 256 * 1024,
        },
    );
    defer boundary.deinit();
    var composer = try render_api.canvas.Composer.init(std.testing.allocator, .{
        .sources = 8,
        .retained_resources = 1,
        .retained_commands = 1,
        .retained_pixel_bytes = 1,
        .composition_sources = 1,
        .candidate_resources = 1,
        .candidate_commands = 1,
        .candidate_pixel_bytes = 1,
    });
    defer composer.deinit();
    var accepted = try session.SessionState.init(
        .{ .width = 320, .height = 240 },
    );
    const first = accepted.focusedPaneId();
    const render_first = try session_chrome_adapter.toRenderPaneId(first);
    const accepted_source = try composer.registerSource();
    try boundary.register(
        render_first,
        accepted_source,
        try panePixelsLocal(accepted.paneRect(first).?),
    );
    try std.testing.expect(boundary.takeLifecycle().? == .create);
    try boundary.markLive(render_first);
    var work: CanvasWork = undefined;
    work.composer = &composer;
    work.terminals = &boundary;

    var split = accepted;
    const second = try split.split(first, .horizontal);
    var pending: ?PendingTopology = try prepareTerminalTopology(
        &work,
        &accepted,
        &split,
        null,
    );
    defer if (pending) |*value| value.deinit();
    const first_revision = pending.?.revision;
    const first_pending_source = pending.?.new_source.?;

    var focused = pending.?.candidate.state;
    try focused.focusPane(first);
    try replacePendingTopology(
        &work,
        &accepted,
        focused,
        &pending,
        null,
    );
    try std.testing.expect(
        @backingInt(pending.?.revision) > @backingInt(first_revision),
    );
    try std.testing.expect(
        @backingInt(pending.?.new_source.?) >
            @backingInt(first_pending_source),
    );
    try std.testing.expectEqual(first, pending.?.candidate.state.focusedPaneId());

    const focus_revision = pending.?.revision;
    var resized = pending.?.candidate.state;
    try resized.resizeSurface(.{ .width = 321, .height = 241 });
    try replacePendingTopology(
        &work,
        &accepted,
        resized,
        &pending,
        null,
    );
    try std.testing.expect(
        @backingInt(pending.?.revision) > @backingInt(focus_revision),
    );

    const resize_revision = pending.?.revision;
    var closed = pending.?.candidate.state;
    try closed.closePane(second);
    try replacePendingTopology(
        &work,
        &accepted,
        closed,
        &pending,
        null,
    );
    try std.testing.expect(
        @backingInt(pending.?.revision) > @backingInt(resize_revision),
    );
    try std.testing.expect(pending.?.new_source == null);
    try std.testing.expectEqual(@as(usize, 1), pending.?.candidate.state.paneCount(0));

    pending.?.deinit();
    pending = null;
    var new_tab = accepted;
    const tab = try new_tab.createTab("two");
    try std.testing.expectEqual(@as(usize, 2), new_tab.tabCount());
    pending = try prepareTerminalTopology(&work, &accepted, &new_tab, null);
    const tab_revision = pending.?.revision;
    var reordered = pending.?.candidate.state;
    try reordered.reorderTab(tab, 0);
    try replacePendingTopology(
        &work,
        &accepted,
        reordered,
        &pending,
        null,
    );
    try std.testing.expect(
        @backingInt(pending.?.revision) > @backingInt(tab_revision),
    );
    try std.testing.expectEqual(tab, pending.?.candidate.state.tabId(0).?);
}

test "PendingTopology has one fixed allocation-free value" {
    try std.testing.expectEqual(@as(usize, 20_552), @sizeOf(PendingTopology));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(PendingTopology));
    try std.testing.expectEqual(
        @as(usize, 544),
        @sizeOf(PreparedBootstrapPublication),
    );
}

test "deferred topology retry has one fixed allocation-free value" {
    try std.testing.expectEqual(@as(usize, 40), @sizeOf(DeferredTopologyInput));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(DeferredTopologyInput));
    try std.testing.expectEqual(@as(usize, 48), @sizeOf(?DeferredTopologyInput));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(?DeferredTopologyInput));
}

test "drainInput forwards capture overflow press and release explicitly" {
    var input_boundary = try window_render_boundary.Boundary.init(std.testing.io);
    defer input_boundary.deinit();
    var terminals = try terminal_handoff.Boundary.init(
        std.testing.io,
        std.testing.allocator,
        .{
            .commands = 32_768,
            .upload_bytes = 4 * 1024 * 1024,
            .cells = 32_768,
            .rows = 128,
            .images = 8,
            .placements = 8,
            .image_bytes = 256 * 1024,
            .glyphs = 512,
            .masks = 128,
            .resources_per_update = terminal_retained_resource_limit,
            .raster_bytes = 4 * 1024 * 1024,
            .decoration_bytes = 256 * 1024,
        },
    );
    defer terminals.deinit();
    var topology = try session.SessionState.init(.{ .width = 320, .height = 240 });
    const pane = try session_chrome_adapter.toRenderPaneId(topology.focusedPaneId());
    try terminals.register(pane, @fromBackingInt(@intCast(1)), .{ .width = 320, .height = 240 });
    try std.testing.expect(terminals.takeLifecycle() != null);
    try terminals.markLive(pane);

    var actions = input_actions.State{};
    var captured: wayland.input.Key = std.mem.zeroes(wayland.input.Key);
    captured.state = .pressed;
    captured.keysym = .t;
    captured.semantic_modifiers = .{ .control = true, .shift = true };
    for (0..16) |index| {
        captured.keycode = @intCast(index + 1);
        try std.testing.expect((try actions.key(captured)).action == .new_tab);
    }
    captured.keycode = 100;
    try input_boundary.publishInput(.{ .key = captured });
    var work: CanvasWork = undefined;
    work.terminals = &terminals;
    var pending: ?PendingTopology = null;
    var deferred: ?DeferredTopologyInput = null;
    try drainInput(
        &input_boundary,
        &actions,
        &work,
        &topology,
        chrome_appearance,
        &pending,
        &deferred,
    );
    const forwarded_press = terminals.takeInput() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(captured, forwarded_press.key.key);

    captured.state = .released;
    try input_boundary.publishInput(.{ .key = captured });
    try drainInput(
        &input_boundary,
        &actions,
        &work,
        &topology,
        chrome_appearance,
        &pending,
        &deferred,
    );
    const forwarded_release = terminals.takeInput() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(captured, forwarded_release.key.key);
    try std.testing.expectEqual(@as(u8, 16), actions.capturedCount());

    actions.clear();
    topology = try session.SessionState.init(.{ .width = 1, .height = 1 });
    var rejected_action = captured;
    rejected_action.keycode = 200;
    rejected_action.state = .pressed;
    rejected_action.keysym = .enter;
    rejected_action.semantic_modifiers = .{ .control = true, .shift = true };
    try input_boundary.publishInput(.{ .key = rejected_action });
    try drainInput(
        &input_boundary,
        &actions,
        &work,
        &topology,
        chrome_appearance,
        &pending,
        &deferred,
    );
    try std.testing.expectEqual(@as(u8, 1), actions.capturedCount());
    try std.testing.expect(pending == null and deferred == null);
    try std.testing.expect(terminals.takeInput() == null);

    actions.clear();
    for (0..16) |index| {
        captured.keycode = @intCast(index + 1);
        captured.state = .pressed;
        captured.keysym = .t;
        captured.semantic_modifiers = .{ .control = true, .shift = true };
        try std.testing.expect((try actions.key(captured)).action == .new_tab);
    }
    captured.keycode = 201;
    const unregistered = try topology.createTab("unregistered");
    try std.testing.expect(@backingInt(unregistered) != 0);
    try input_boundary.publishInput(.{ .key = captured });
    try std.testing.expectError(
        error.UnknownPane,
        drainInput(
            &input_boundary,
            &actions,
            &work,
            &topology,
            chrome_appearance,
            &pending,
            &deferred,
        ),
    );
}

test "drainInput candidate dispositions are exhaustive" {
    inline for ([_]session.Error{error.Capacity}) |failure| {
        inline for ([_]input_actions.Action{ .new_tab, .split_horizontal, .split_vertical }) |action|
            try std.testing.expectEqual(.reject, sessionCandidateDisposition(action, failure));
    }
    inline for ([_]session.Error{error.InvalidGeometry}) |failure| {
        inline for ([_]input_actions.Action{
            .split_horizontal,
            .split_vertical,
            .resize_left,
            .resize_right,
            .resize_up,
            .resize_down,
        }) |action|
            try std.testing.expectEqual(.reject, sessionCandidateDisposition(action, failure));
    }
    inline for ([_]session.Error{
        error.InvalidText,
        error.InvalidId,
        error.InvalidIdentity,
        error.InvalidScroll,
        error.ArithmeticOverflow,
    }) |failure| {
        try std.testing.expectEqual(.fatal, sessionCandidateDisposition(.new_tab, failure));
    }
    inline for ([_]input_actions.PointerError{
        error.Capacity,
        error.InvalidId,
        error.InvalidGeometry,
        error.InvalidSurface,
        error.InvalidRectangle,
        error.InvalidTabBar,
        error.InvalidScrollbar,
    }) |failure| {
        try std.testing.expectEqual(.reject, pointerCandidateDisposition(failure));
    }
    inline for ([_]input_actions.PointerError{
        error.InvalidText,
        error.InvalidScroll,
        error.InvalidIdentity,
        error.ArithmeticOverflow,
        error.InvalidOrder,
        error.InsufficientOutput,
        error.InsufficientText,
        error.AliasedStorage,
    }) |failure| {
        try std.testing.expectEqual(.fatal, pointerCandidateDisposition(failure));
    }
    inline for ([_]session.Error{
        error.Capacity,
        error.InvalidText,
        error.InvalidId,
        error.InvalidIdentity,
        error.InvalidGeometry,
        error.InvalidScroll,
        error.ArithmeticOverflow,
    }) |failure| {
        try std.testing.expectEqual(.fatal, pointerFoldDisposition(failure));
    }
}

test "drainInput propagates fatal session candidate invariants" {
    var input_boundary = try window_render_boundary.Boundary.init(std.testing.io);
    defer input_boundary.deinit();
    var terminals = try terminal_handoff.Boundary.init(
        std.testing.io,
        std.testing.allocator,
        .{
            .commands = 32_768,
            .upload_bytes = 4 * 1024 * 1024,
            .cells = 32_768,
            .rows = 128,
            .images = 8,
            .placements = 8,
            .image_bytes = 256 * 1024,
            .glyphs = 512,
            .masks = 128,
            .resources_per_update = terminal_retained_resource_limit,
            .raster_bytes = 4 * 1024 * 1024,
            .decoration_bytes = 256 * 1024,
        },
    );
    defer terminals.deinit();
    var topology = try session.SessionState.init(.{ .width = 320, .height = 240 });
    topology.next_tab_id = std.math.maxInt(u64);
    var key: wayland.input.Key = std.mem.zeroes(wayland.input.Key);
    key.keycode = 1;
    key.state = .pressed;
    key.keysym = .w;
    key.semantic_modifiers = .{ .control = true, .shift = true };
    try input_boundary.publishInput(.{ .key = key });
    var actions = input_actions.State{};
    var work: CanvasWork = undefined;
    work.terminals = &terminals;
    var pending: ?PendingTopology = null;
    var deferred: ?DeferredTopologyInput = null;
    try std.testing.expectError(
        error.Capacity,
        drainInput(
            &input_boundary,
            &actions,
            &work,
            &topology,
            chrome_appearance,
            &pending,
            &deferred,
        ),
    );
    try std.testing.expect(pending == null and deferred == null);
}

test "provisional startup frame exposes no terminal lifecycle or topology" {
    var terminals = try terminal_handoff.Boundary.init(
        std.testing.io,
        std.testing.allocator,
        .{
            .commands = 32_768,
            .upload_bytes = 4 * 1024 * 1024,
            .cells = 32_768,
            .rows = 128,
            .images = 8,
            .placements = 8,
            .image_bytes = 256 * 1024,
            .glyphs = 512,
            .masks = 128,
            .resources_per_update = terminal_retained_resource_limit,
            .raster_bytes = 4 * 1024 * 1024,
            .decoration_bytes = 256 * 1024,
        },
    );
    defer terminals.deinit();
    var composer = try render_api.canvas.Composer.init(
        std.testing.allocator,
        .{
            .sources = 4,
            .retained_resources = 1,
            .retained_commands = 1,
            .retained_pixel_bytes = 1,
            .composition_sources = 1,
            .candidate_resources = 1,
            .candidate_commands = 1,
            .candidate_pixel_bytes = 1,
        },
    );
    defer composer.deinit();
    try composer.setComposition(.{
        .surface = .{ .width = 320, .height = 240 },
        .sources = &.{},
    });
    var uploads: [1]render_api.canvas.ResourceUploadFact = undefined;
    var removals: [1]render_api.canvas.FrameResourceRef = undefined;
    var commands: [1]render_api.canvas.Command = undefined;
    var pixels: [1]u8 = undefined;
    const provisional = try composer.frame(&.{}, .{
        .uploads = &uploads,
        .removals = &removals,
        .commands = &commands,
        .pixels = &pixels,
    });
    try std.testing.expectEqual(@as(usize, 0), provisional.uploads.len);
    try std.testing.expectEqual(@as(usize, 0), provisional.commands.len);
    try std.testing.expect(terminals.takeLifecycle() == null);

    const topology = try session.SessionState.init(
        .{ .width = 320, .height = 240 },
    );
    var work: CanvasWork = undefined;
    work.composer = &composer;
    work.terminals = &terminals;
    var pending = try prepareInitialTerminalTopology(
        &work,
        &topology,
        .{
            .generation = 2,
            .logical_width = 320,
            .logical_height = 240,
            .physical_width = 320,
            .physical_height = 240,
            .scale_revision = 1,
            .dpi_x = .{ .numerator = 96, .denominator = 1 },
            .dpi_y = .{ .numerator = 96, .denominator = 1 },
            .buffer_scale = 1,
            .use_viewport = false,
        },
    );
    const source = pending.new_source.?;
    const request = terminals.takeLifecycleAdmission().?;
    try std.testing.expectEqual(pending.revision, request.revision);
    try std.testing.expect(terminals.sourceFor(try session_chrome_adapter.toRenderPaneId(topology.focusedPaneId())) == null);
    pending.deinit();
    try std.testing.expect(terminals.takeLifecycle() == null);
    try std.testing.expectError(error.RetiredSource, composer.removeSource(source));
}

test "semantic tab and split candidates project and shape through the production Chrome owner" {
    var content = try render_api.chrome.Content.init(
        std.testing.allocator,
        .{
            .primitives = 256,
            .text_bytes = (session_chrome_adapter.max_tabs + session_chrome_adapter.max_panes_per_tab) * session_chrome_adapter.max_label_bytes,
            .label_scalars = 256,
            .shaped_glyphs = 256,
            .glyphs = 128,
            .commands = 2048,
            .resources_per_update = 512,
            .upload_bytes = 8 * 1024 * 1024,
            .raster_bytes = 512 * 1024,
        },
        .{ .primary = "../howl-render/testdata/primary.ttf", .size = .{ .pixels = 16 } },
    );
    defer content.deinit();
    var primitives: [256]render_api.chrome.Primitive = undefined;
    var text: [(session_chrome_adapter.max_tabs + session_chrome_adapter.max_panes_per_tab) * session_chrome_adapter.max_label_bytes]u8 = undefined;
    const surface = render_api.canvas.Size{ .width = 320, .height = 240 };
    const origin = session_chrome_adapter.ContentOrigin{ .y = session_chrome_adapter.default_tab_bar_height };
    var state = try session.SessionState.init(.{ .width = 320, .height = 216 });

    const projectAndShape = struct {
        fn run(
            value: *const session.SessionState,
            retained: *render_api.chrome.Content,
            surface_value: render_api.canvas.Size,
            origin_value: session_chrome_adapter.ContentOrigin,
            primitive_storage: []render_api.chrome.Primitive,
            text_storage: []u8,
        ) !void {
            const output = try session_chrome_adapter.project(
                value,
                chrome_appearance,
                surface_value,
                origin_value,
                &.{},
                primitive_storage,
                text_storage,
            );
            const expected_tabs = if (value.tabCount() == 1) "main" else "maintab";
            try std.testing.expect(std.mem.containsAtLeast(u8, output.text, 1, expected_tabs));
            try std.testing.expect(!std.mem.containsAtLeast(u8, output.text, 1, &.{0}));
            const active_tab = value.activeTabIndex();
            for (0..value.paneCount(active_tab)) |pane_index| {
                const pane = value.paneId(active_tab, pane_index).?;
                const local = value.paneRect(pane).?;
                const physical = try session_chrome_adapter.toRenderRect(local, origin_value);
                try std.testing.expect(physical.y >= origin_value.y);
                try std.testing.expect(
                    physical.y + @as(i32, @intCast(physical.height)) <= surface_value.height,
                );
            }
            try retained.apply(output);
            const update = try retained.takeUpdate();
            try std.testing.expect(@backingInt(update.revision) != 0);
        }
    }.run;

    try projectAndShape(&state, &content, surface, origin, &primitives, &text);
    const created_tab = try state.createTab("tab");
    try std.testing.expect(@backingInt(created_tab) != 0);
    try projectAndShape(&state, &content, surface, origin, &primitives, &text);
    try state.switchTab(state.tabId(0).?);
    for (0..3) |_| {
        const horizontal = try state.split(state.focusedPaneId(), .horizontal);
        try std.testing.expect(@backingInt(horizontal) != 0);
        for (0..state.paneCount(state.activeTabIndex())) |pane_index| {
            try state.renamePane(state.paneId(state.activeTabIndex(), pane_index).?, "pane");
        }
        try projectAndShape(&state, &content, surface, origin, &primitives, &text);
        const vertical = try state.split(state.focusedPaneId(), .vertical);
        try std.testing.expect(@backingInt(vertical) != 0);
        for (0..state.paneCount(state.activeTabIndex())) |pane_index| {
            try state.renamePane(state.paneId(state.activeTabIndex(), pane_index).?, "pane");
        }
        try projectAndShape(&state, &content, surface, origin, &primitives, &text);
    }
}

test "semantic split candidates retain pane labels through the production Chrome owner" {
    var content = try render_api.chrome.Content.init(
        std.testing.allocator,
        .{
            .primitives = 256,
            .text_bytes = session_chrome_adapter.max_panes_per_tab * session_chrome_adapter.max_label_bytes,
            .label_scalars = 256,
            .shaped_glyphs = 256,
            .glyphs = 128,
            .commands = 2048,
            .resources_per_update = 512,
            .upload_bytes = 8 * 1024 * 1024,
            .raster_bytes = 512 * 1024,
        },
        .{ .primary = "../howl-render/testdata/primary.ttf", .size = .{ .pixels = 16 } },
    );
    defer content.deinit();
    var primitives: [256]render_api.chrome.Primitive = undefined;
    var text: [session_chrome_adapter.max_panes_per_tab * session_chrome_adapter.max_label_bytes]u8 = undefined;
    const surface = render_api.canvas.Size{ .width = 320, .height = 240 };
    const origin = session_chrome_adapter.ContentOrigin{ .y = session_chrome_adapter.default_tab_bar_height };
    var state = try session.SessionState.init(.{ .width = 320, .height = 216 });

    for (0..3) |_| {
        const horizontal = try state.split(state.focusedPaneId(), .horizontal);
        try std.testing.expect(@backingInt(horizontal) != 0);
        for (0..state.paneCount(state.activeTabIndex())) |pane_index| {
            try state.renamePane(state.paneId(state.activeTabIndex(), pane_index).?, "pane");
        }
        const vertical = try state.split(state.focusedPaneId(), .vertical);
        try std.testing.expect(@backingInt(vertical) != 0);
        for (0..state.paneCount(state.activeTabIndex())) |pane_index| {
            try state.renamePane(state.paneId(state.activeTabIndex(), pane_index).?, "pane");
        }
        const output = try session_chrome_adapter.project(
            &state,
            chrome_appearance,
            surface,
            origin,
            &.{},
            &primitives,
            &text,
        );
        try std.testing.expect(!std.mem.containsAtLeast(u8, output.text, 1, &.{0}));
        try content.apply(output);
        const update = try content.takeUpdate();
        try std.testing.expect(@backingInt(update.revision) != 0);
    }
}

test "undersized pending topology rejection removes provisional source" {
    var terminals = try terminal_handoff.Boundary.init(
        std.testing.io,
        std.testing.allocator,
        .{
            .commands = 128,
            .upload_bytes = 64 * 1024,
            .cells = 128,
            .rows = 8,
            .images = 1,
            .placements = 8,
            .image_bytes = 4096,
            .glyphs = 32,
            .masks = 8,
            .resources_per_update = 32,
            .raster_bytes = 64 * 1024,
            .decoration_bytes = 4096,
        },
    );
    defer terminals.deinit();
    var composer = try render_api.canvas.Composer.init(std.testing.allocator, .{
        .sources = 16,
        .retained_resources = 1,
        .retained_commands = 1,
        .retained_pixel_bytes = 1,
        .composition_sources = 1,
        .candidate_resources = 1,
        .candidate_commands = 1,
        .candidate_pixel_bytes = 1,
    });
    defer composer.deinit();
    var accepted = try session.SessionState.init(.{ .width = 80, .height = 24 });
    for (0..6) |_| {
        accepted = (try input_actions.candidate(
            &accepted,
            .split_vertical,
        )).?.state;
    }
    for (0..accepted.paneCount(0)) |index| {
        const pane = accepted.paneId(0, index).?;
        const render_pane = try session_chrome_adapter.toRenderPaneId(pane);
        const source = try composer.registerSource();
        try terminals.register(
            render_pane,
            source,
            try panePixelsLocal(accepted.paneRect(pane).?),
        );
        try std.testing.expect(terminals.takeLifecycle() != null);
        try terminals.markLive(render_pane);
    }
    var candidate_state = (try input_actions.candidate(
        &accepted,
        .split_vertical,
    )).?.state;
    const accepted_bytes = accepted;
    const new_pane = candidate_state.focusedPaneId();
    try std.testing.expectEqual(@as(i32, 1), candidate_state.paneRect(new_pane).?.width);
    var work: CanvasWork = undefined;
    work.composer = &composer;
    work.terminals = &terminals;
    var pending: ?PendingTopology = null;
    try replacePendingTopology(
        &work,
        &accepted,
        candidate_state,
        &pending,
        null,
    );
    defer if (pending) |*value| value.deinit();
    const provisional_source = pending.?.new_source.?;
    const revision = pending.?.revision;
    const request = pending.?.lifecycle.boundary.takeLifecycleAdmission().?;
    try std.testing.expectEqual(revision, request.revision);
    try terminals.completeLifecycleAdmission(
        revision,
        .{ .rejected = .invalid_extent },
    );
    try std.testing.expectEqual(
        .invalid_extent,
        pending.?.observeAdmission().?,
    );
    pending.?.deinit();
    pending = null;
    try std.testing.expectEqualDeep(accepted_bytes, accepted);
    try std.testing.expect(
        terminals.sourceFor(try session_chrome_adapter.toRenderPaneId(new_pane)) == null,
    );
    try std.testing.expect(terminals.takeLifecycle() == null);
    try std.testing.expectError(
        error.RetiredSource,
        composer.removeSource(provisional_source),
    );
}

test "cancelled topology replacements reuse Composer storage and retain accepted state" {
    var terminals = try terminal_handoff.Boundary.init(
        std.testing.io,
        std.testing.allocator,
        .{
            .commands = 32,
            .upload_bytes = 4096,
            .cells = 32,
            .rows = 4,
            .images = 1,
            .placements = 2,
            .image_bytes = 4096,
            .glyphs = 8,
            .masks = 2,
            .resources_per_update = 8,
            .raster_bytes = 4096,
            .decoration_bytes = 1024,
        },
    );
    defer terminals.deinit();
    var composer = try render_api.canvas.Composer.init(std.testing.allocator, .{
        .sources = 2,
        .retained_resources = 1,
        .retained_commands = 1,
        .retained_pixel_bytes = 1,
        .composition_sources = 2,
        .candidate_resources = 1,
        .candidate_commands = 1,
        .candidate_pixel_bytes = 1,
    });
    defer composer.deinit();
    const accepted = try session.SessionState.init(.{ .width = 80, .height = 24 });
    const accepted_bytes = accepted;
    const pane = try session_chrome_adapter.toRenderPaneId(accepted.focusedPaneId());
    const accepted_source = try composer.registerSource();
    try terminals.register(
        pane,
        accepted_source,
        try panePixelsLocal(accepted.paneRect(accepted.focusedPaneId()).?),
    );
    try std.testing.expect(terminals.takeLifecycle() != null);
    try terminals.markLive(pane);

    var work: CanvasWork = undefined;
    work.composer = &composer;
    work.terminals = &terminals;
    var pending: ?PendingTopology = null;
    for (0..130) |_| {
        const candidate = (try input_actions.candidate(
            &accepted,
            .split_vertical,
        )).?.state;
        try replacePendingTopology(
            &work,
            &accepted,
            candidate,
            &pending,
            null,
        );
        try std.testing.expect(pending != null);
        pending.?.deinit();
        pending = null;
        try std.testing.expectEqualDeep(accepted_bytes, accepted);
        try std.testing.expect(terminals.takeLifecycle() == null);
    }
    const final_candidate = (try input_actions.candidate(
        &accepted,
        .split_vertical,
    )).?.state;
    try replacePendingTopology(
        &work,
        &accepted,
        final_candidate,
        &pending,
        null,
    );
    defer if (pending) |*value| value.deinit();
    try std.testing.expect(pending != null);
    try std.testing.expectEqualDeep(accepted_bytes, accepted);
}

test "topology replacement distinguishes rejection retry progress and fatal failure" {
    var terminals = try terminal_handoff.Boundary.init(
        std.testing.io,
        std.testing.allocator,
        .{
            .commands = 32,
            .upload_bytes = 4096,
            .cells = 32,
            .rows = 4,
            .images = 1,
            .placements = 2,
            .image_bytes = 4096,
            .glyphs = 8,
            .masks = 2,
            .resources_per_update = 8,
            .raster_bytes = 4096,
            .decoration_bytes = 1024,
        },
    );
    defer terminals.deinit();
    var composer = try render_api.canvas.Composer.init(std.testing.allocator, .{
        .sources = 2,
        .retained_resources = 1,
        .retained_commands = 1,
        .retained_pixel_bytes = 1,
        .composition_sources = 2,
        .candidate_resources = 1,
        .candidate_commands = 1,
        .candidate_pixel_bytes = 1,
    });
    defer composer.deinit();
    const accepted = try session.SessionState.init(.{ .width = 80, .height = 24 });
    const accepted_bytes = accepted;
    const pane = try session_chrome_adapter.toRenderPaneId(accepted.focusedPaneId());
    const accepted_source = try composer.registerSource();
    try terminals.register(
        pane,
        accepted_source,
        try panePixelsLocal(accepted.paneRect(accepted.focusedPaneId()).?),
    );
    try terminals.markLive(pane);
    for (0..127) |index|
        try terminals.resize(pane, .{
            .width = @intCast(80 + index),
            .height = 24,
        });

    var work: CanvasWork = undefined;
    work.composer = &composer;
    work.terminals = &terminals;
    work.surface = .{ .width = 80, .height = 48 };
    work.content_origin = .{ .y = 24 };
    var pending: ?PendingTopology = null;
    var window_boundary = try window_render_boundary.Boundary.init(std.testing.io);
    defer window_boundary.deinit();
    try window_boundary.publishConfigure(
        96,
        48,
        96,
        48,
        1,
        .{ .numerator = 96, .denominator = 1 },
        .{ .numerator = 96, .denominator = 1 },
        1,
        false,
    );
    var retained_configure: ?window_render_boundary.SurfaceConfig = window_boundary.takeConfigure();
    work.terminal_font_policy = try terminal_handoff.FontPolicy.init(16.0);
    work.terminal_scale = null;
    work.font_request_high_water = 0;
    try retainTerminalScale(
        work.terminals,
        work.terminal_font_policy,
        &work.terminal_scale,
        &work.font_request_high_water,
        retained_configure.?,
    );
    try std.testing.expect(work.terminals.takeFontRequest() != null);
    try retainTerminalScale(
        work.terminals,
        work.terminal_font_policy,
        &work.terminal_scale,
        &work.font_request_high_water,
        retained_configure.?,
    );
    try std.testing.expect(work.terminals.takeFontRequest() == null);
    try std.testing.expectEqual(
        TopologyReplacementDisposition.retry,
        try attemptConfigureReplacement(
            &work,
            &accepted,
            &pending,
            retained_configure.?,
        ),
    );
    try std.testing.expect(retained_configure != null);
    var deferred: ?DeferredTopologyInput = .{ .action = .split_vertical };
    try std.testing.expectEqual(
        TopologyReplacementDisposition.retry,
        try retryDeferredTopologyInput(
            &work,
            &accepted,
            &pending,
            &deferred,
            chrome_appearance,
            work.surface,
            work.content_origin,
        ),
    );
    try std.testing.expect(deferred != null);
    try std.testing.expect(pending == null);
    try std.testing.expectEqualDeep(accepted_bytes, accepted);
    try terminals.drainRendererWake();
    while (terminals.takeLifecycle() != null) {}
    var renderer_wake = std.posix.pollfd{
        .fd = terminals.rendererFd(),
        .events = std.posix.POLL.IN,
        .revents = 0,
    };
    try std.testing.expectEqual(
        @as(usize, 1),
        try std.posix.poll((&renderer_wake)[0..1], 0),
    );
    try terminals.drainRendererWake();
    try std.testing.expectEqual(
        TopologyReplacementDisposition.accepted,
        try attemptConfigureReplacement(
            &work,
            &accepted,
            &pending,
            retained_configure.?,
        ),
    );
    clearRetainedConfigure(&retained_configure);
    pending.?.deinit();
    pending = null;
    try std.testing.expectEqual(
        TopologyReplacementDisposition.accepted,
        try retryDeferredTopologyInput(
            &work,
            &accepted,
            &pending,
            &deferred,
            chrome_appearance,
            work.surface,
            work.content_origin,
        ),
    );
    try std.testing.expect(deferred == null);
    try std.testing.expect(pending != null);
    pending.?.deinit();
    pending = null;
    try std.testing.expectEqualDeep(accepted_bytes, accepted);

    const invalid_surface = window_render_boundary.SurfaceConfig{
        .generation = 3,
        .logical_width = 0,
        .logical_height = 0,
        .physical_width = 0,
        .physical_height = 0,
        .scale_revision = 0,
        .buffer_scale = 1,
        .use_viewport = false,
    };
    try std.testing.expectEqual(
        TopologyReplacementDisposition.rejected,
        try attemptConfigureReplacement(
            &work,
            &accepted,
            &pending,
            invalid_surface,
        ),
    );
    try std.testing.expect(pending == null);
    try std.testing.expectEqualDeep(accepted_bytes, accepted);

    var rejected_state = accepted;
    const second_tab = try rejected_state.createTab("second");
    try std.testing.expect(@backingInt(second_tab) != 0);
    const second_pane = try rejected_state.split(
        rejected_state.focusedPaneId(),
        .vertical,
    );
    try std.testing.expect(@backingInt(second_pane) != 0);
    try std.testing.expectEqual(
        TopologyReplacementDisposition.rejected,
        try attemptTopologyReplacement(
            &work,
            &accepted,
            rejected_state,
            &pending,
            null,
        ),
    );
    try std.testing.expect(pending == null);
    try std.testing.expectEqualDeep(accepted_bytes, accepted);

    var one_source_composer = try render_api.canvas.Composer.init(
        std.testing.allocator,
        .{
            .sources = 1,
            .retained_resources = 1,
            .retained_commands = 1,
            .retained_pixel_bytes = 1,
            .composition_sources = 1,
            .candidate_resources = 1,
            .candidate_commands = 1,
            .candidate_pixel_bytes = 1,
        },
    );
    defer one_source_composer.deinit();
    const full_source = try one_source_composer.registerSource();
    try std.testing.expect(@backingInt(full_source) != 0);
    work.composer = &one_source_composer;
    deferred = .{ .action = .split_vertical };
    try std.testing.expectError(
        error.SourceLimit,
        retryDeferredTopologyInput(
            &work,
            &accepted,
            &pending,
            &deferred,
            chrome_appearance,
            work.surface,
            work.content_origin,
        ),
    );
    try std.testing.expect(pending == null);
    try std.testing.expectEqualDeep(accepted_bytes, accepted);

    terminals.shutdown();
    const fatal_surface = window_render_boundary.SurfaceConfig{
        .generation = 4,
        .logical_width = 96,
        .logical_height = 48,
        .physical_width = 96,
        .physical_height = 48,
        .scale_revision = 0,
        .buffer_scale = 1,
        .use_viewport = false,
    };
    try std.testing.expectError(
        error.Stopping,
        attemptConfigureReplacement(
            &work,
            &accepted,
            &pending,
            fatal_surface,
        ),
    );
    try std.testing.expect(pending == null);
    try std.testing.expectEqualDeep(accepted_bytes, accepted);
}

test "owner retirement wakes and progresses one retained topology input" {
    var terminals = try terminal_handoff.Boundary.init(
        std.testing.io,
        std.testing.allocator,
        .{
            .commands = 32,
            .upload_bytes = 4096,
            .cells = 32,
            .rows = 4,
            .images = 1,
            .placements = 2,
            .image_bytes = 4096,
            .glyphs = 8,
            .masks = 2,
            .resources_per_update = 8,
            .raster_bytes = 4096,
            .decoration_bytes = 1024,
        },
    );
    defer terminals.deinit();
    var composer = try render_api.canvas.Composer.init(std.testing.allocator, .{
        .sources = 65,
        .retained_resources = 1,
        .retained_commands = 1,
        .retained_pixel_bytes = 1,
        .composition_sources = 65,
        .candidate_resources = 1,
        .candidate_commands = 1,
        .candidate_pixel_bytes = 1,
    });
    defer composer.deinit();
    var panes: [64]render_api.chrome.PaneId = undefined;
    var sources: [64]render_api.canvas.SourceId = undefined;
    for (&panes, &sources, 0..) |*pane, *source, index| {
        pane.* = @fromBackingInt(@intCast(if (index == 0) 1 else 1_000 + index));
        source.* = try composer.registerSource();
        try terminals.register(
            pane.*,
            source.*,
            .{ .width = 80, .height = 24 },
        );
        const member = try terminals.activateTransfer(pane.*);
        try std.testing.expectEqual(pane.*, member.pane_id);
        try std.testing.expectEqual(source.*, member.source_id);
        try terminals.markLive(pane.*);
    }
    while (terminals.takeLifecycle() != null) {}
    try terminals.drainRendererWake();

    const accepted = try session.SessionState.init(.{ .width = 80, .height = 24 });
    const accepted_bytes = accepted;
    var work: CanvasWork = undefined;
    work.composer = &composer;
    work.terminals = &terminals;
    work.surface = .{ .width = 80, .height = 48 };
    work.content_origin = .{ .y = 24 };
    var pending: ?PendingTopology = null;
    var window_boundary = try window_render_boundary.Boundary.init(std.testing.io);
    defer window_boundary.deinit();
    try window_boundary.publishConfigure(
        80,
        48,
        80,
        48,
        0,
        null,
        null,
        1,
        false,
    );
    var retained_configure: ?window_render_boundary.SurfaceConfig =
        window_boundary.takeConfigure();
    var deferred: ?DeferredTopologyInput = .{ .action = .split_vertical };
    try std.testing.expectEqual(
        TopologyReplacementDisposition.retry,
        try retryDeferredTopologyInput(
            &work,
            &accepted,
            &pending,
            &deferred,
            chrome_appearance,
            work.surface,
            work.content_origin,
        ),
    );
    try std.testing.expect(deferred != null);
    try std.testing.expect(pending == null);
    try std.testing.expect(retained_configure != null);

    const retiring_pane = panes[panes.len - 1];
    try terminals.close(retiring_pane);
    const close = terminals.takeLifecycle().?;
    try std.testing.expectEqual(retiring_pane, close.close);
    try terminals.drainRendererWake();
    try std.testing.expect(try terminals.retireTransfer(retiring_pane));
    try terminals.markRetired(retiring_pane);
    const retired = terminals.takeRetired().?;
    try std.testing.expectEqual(retiring_pane, retired.pane);
    try std.testing.expectEqual(sources[sources.len - 1], retired.source);
    try terminals.drainRendererWake();
    try composer.removeSource(retired.source);
    try terminals.finishRetired(retired.pane);
    var renderer_wake = std.posix.pollfd{
        .fd = terminals.rendererFd(),
        .events = std.posix.POLL.IN,
        .revents = 0,
    };
    try std.testing.expectEqual(
        @as(usize, 1),
        try std.posix.poll((&renderer_wake)[0..1], 0),
    );
    try terminals.drainRendererWake();

    try std.testing.expectEqual(
        TopologyReplacementDisposition.accepted,
        try retryDeferredTopologyInput(
            &work,
            &accepted,
            &pending,
            &deferred,
            chrome_appearance,
            work.surface,
            work.content_origin,
        ),
    );
    defer if (pending) |*value| value.deinit();
    try std.testing.expect(deferred == null);
    try std.testing.expect(pending != null);
    try std.testing.expectEqual(
        TopologyReplacementDisposition.accepted,
        try attemptConfigureReplacement(
            &work,
            &accepted,
            &pending,
            retained_configure.?,
        ),
    );
    clearRetainedConfigure(&retained_configure);
    pending.?.deinit();
    pending = null;
    try std.testing.expectEqualDeep(accepted_bytes, accepted);
}

test "one complete terminal and Chrome resource set fits every runtime bank" {
    try std.testing.expect(
        terminal_retained_resource_limit <= 1024,
    );
    try std.testing.expect(
        terminal_retained_resource_limit + chrome_retained_resource_limit <=
            frame_resource_limit,
    );
}

test "borrowed Chrome retry preserves one consumptive sparse update" {
    try std.testing.expectEqual(@as(usize, 720), @sizeOf(ChromeRetry));
    var content = try render_api.chrome.Content.init(
        std.testing.allocator,
        .{
            .primitives = 4,
            .text_bytes = 16,
            .label_scalars = 16,
            .shaped_glyphs = 16,
            .glyphs = 16,
            .commands = 16,
            .resources_per_update = 16,
            .upload_bytes = 4096,
            .raster_bytes = 4096,
        },
        .{
            .primary = "../howl-render/testdata/primary.ttf",
            .size = .{ .pixels = 16 },
        },
    );
    defer content.deinit();
    const label = "R";
    const primitives = [_]render_api.chrome.Primitive{.{ .label = .{
        .rect = .{ .x = 0, .y = 0, .width = 16, .height = 16 },
        .text = label,
        .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    } }};
    try content.apply(.{
        .surface = .{ .width = 32, .height = 16 },
        .primitives = &primitives,
        .text = label,
    });
    const update = try content.takeUpdate();
    try std.testing.expectEqual(@as(usize, 1), update.uploads.len);
    const upload_pixels = update.uploads[0].pixels.bytes;
    var expected_pixels: [4096]u8 = undefined;
    @memcpy(expected_pixels[0..upload_pixels.len], upload_pixels);
    const expected_resource = update.uploads[0].resource;
    const expected_revision = update.revision;

    const retry = ChromeRetry{
        .update = update,
        .surface = .{ .width = 32, .height = 16 },
        .terminal_placements = undefined,
        .terminal_count = 0,
        .visible_revision = null,
        .topology_revision = null,
    };
    var composer = try render_api.canvas.Composer.init(
        std.testing.allocator,
        .{
            .sources = 2,
            .retained_resources = 1,
            .retained_commands = 32,
            .retained_pixel_bytes = 8192,
            .composition_sources = 2,
            .candidate_resources = 16,
            .candidate_commands = 16,
            .candidate_pixel_bytes = 4096,
        },
    );
    defer composer.deinit();
    const blocker = try composer.registerSource();
    const chrome_source = try composer.registerSource();
    const blocker_ref = render_api.canvas.ResourceRef{
        .resource = try render_api.canvas.ResourceId.local(1),
        .generation = @fromBackingInt(@intCast(1)),
    };
    const blocker_pixel = [_]u8{0x44};
    try composer.apply(blocker, .{
        .revision = @fromBackingInt(@intCast(1)),
        .uploads = &.{.{
            .resource = blocker_ref,
            .format = .alpha8,
            .pixels = .{
                .bytes = &blocker_pixel,
                .width = 1,
                .height = 1,
                .stride = 1,
            },
        }},
        .removals = &.{},
        .commands = &.{},
    });
    const chrome_placement = [_]render_api.canvas.Composer.Placement{.{
        .source = chrome_source,
        .origin = .{ .x = 0, .y = 0 },
        .clip = .{ .x = 0, .y = 0, .width = 32, .height = 16 },
    }};
    try std.testing.expectError(
        error.ResourceLimit,
        composer.applyCandidate(.{
            .changes = &.{.{
                .source = chrome_source,
                .update = retry.update,
            }},
            .composition = .{
                .surface = retry.surface,
                .sources = &chrome_placement,
            },
        }),
    );
    try std.testing.expectEqual(expected_revision, retry.update.revision);
    try std.testing.expectEqual(expected_resource, retry.update.uploads[0].resource);
    try std.testing.expectEqualSlices(
        u8,
        expected_pixels[0..upload_pixels.len],
        retry.update.uploads[0].pixels.bytes,
    );
    try composer.removeSource(blocker);
    try composer.applyCandidate(.{
        .changes = &.{.{
            .source = chrome_source,
            .update = retry.update,
        }},
        .composition = .{
            .surface = retry.surface,
            .sources = &chrome_placement,
        },
    });
    var uploads: [16]render_api.canvas.ResourceUploadFact = undefined;
    var removals: [16]render_api.canvas.FrameResourceRef = undefined;
    var commands: [32]render_api.canvas.Command = undefined;
    var pixels: [8192]u8 = undefined;
    const frame = try composer.frame(&.{}, .{
        .uploads = &uploads,
        .removals = &removals,
        .commands = &commands,
        .pixels = &pixels,
    });
    try std.testing.expectEqual(expected_revision, update.revision);
    try std.testing.expectEqual(@as(usize, 1), frame.uploads.len);
    try std.testing.expectEqual(expected_resource.resource, frame.uploads[0].resource.resource);
    try std.testing.expectEqualSlices(
        u8,
        expected_pixels[0..upload_pixels.len],
        frame.pixels[frame.uploads[0].pixel_offset .. frame.uploads[0].pixel_offset + frame.uploads[0].pixel_count],
    );
}

test "Renderer Chrome retry cannot authorize a newer topology snapshot" {
    var terminals = try terminal_handoff.Boundary.init(
        std.testing.io,
        std.testing.allocator,
        .{
            .commands = 32,
            .upload_bytes = 4096,
            .cells = 32,
            .rows = 8,
            .images = 1,
            .placements = 1,
            .image_bytes = 4096,
            .glyphs = 16,
            .masks = 8,
            .resources_per_update = 16,
            .raster_bytes = 4096,
            .decoration_bytes = 4096,
        },
    );
    defer terminals.deinit();
    var content = try render_api.chrome.Content.init(
        std.testing.allocator,
        .{
            .primitives = 32,
            .text_bytes = 128,
            .label_scalars = 64,
            .shaped_glyphs = 64,
            .glyphs = 32,
            .commands = 128,
            .resources_per_update = 32,
            .upload_bytes = 32 * 1024,
            .raster_bytes = 4096,
        },
        .{
            .primary = "../howl-render/testdata/primary.ttf",
            .size = .{ .pixels = 16 },
        },
    );
    defer content.deinit();
    var composer = try render_api.canvas.Composer.init(
        std.testing.allocator,
        .{
            .sources = 5,
            .retained_resources = 32,
            .retained_commands = 256,
            .retained_pixel_bytes = 64 * 1024,
            .composition_sources = 3,
            .candidate_resources = 32,
            .candidate_commands = 128,
            .candidate_pixel_bytes = 32 * 1024,
        },
    );
    defer composer.deinit();
    const blocker = try composer.registerSource();
    const chrome_source = try composer.registerSource();
    const terminal_source = try composer.registerSource();
    var blocker_refs: [32]render_api.canvas.ResourceRef = undefined;
    var blocker_uploads: [32]render_api.canvas.ResourceUpload = undefined;
    var blocker_pixels: [32]u8 = undefined;
    for (&blocker_uploads, 0..) |*upload, index| {
        blocker_pixels[index] = @intCast(index);
        blocker_refs[index] = .{
            .resource = try render_api.canvas.ResourceId.local(index + 1),
            .generation = @fromBackingInt(1),
        };
        upload.* = .{
            .resource = blocker_refs[index],
            .format = .alpha8,
            .pixels = .{
                .bytes = blocker_pixels[index..][0..1],
                .width = 1,
                .height = 1,
                .stride = 1,
            },
        };
    }
    try composer.apply(blocker, .{
        .revision = @fromBackingInt(1),
        .uploads = &blocker_uploads,
        .removals = &.{},
        .commands = &.{},
    });
    var frame_uploads: [32]render_api.canvas.ResourceUploadFact = undefined;
    var frame_removals: [32]render_api.canvas.FrameResourceRef = undefined;
    var frame_commands: [256]render_api.canvas.Command = undefined;
    var frame_pixels: [64 * 1024]u8 = undefined;
    var surface_uploads: [32]vk_surface.Upload = undefined;
    var surface_removals: [32]vk_surface.Removal = undefined;
    var surface_commands: [256]vk_surface.FrameCommand = undefined;
    var surface_residencies: [32]vk_surface.Residency = undefined;
    var canvas_residencies: [32]render_api.canvas.Residency = undefined;
    var builder = try vk_surface.FrameBuilder.init(std.testing.allocator);
    defer builder.deinit();
    var residency = try vk_surface.ResidencyStore.init(
        std.testing.allocator,
        .{ .resources = 32, .pixel_bytes = 64 * 1024 },
    );
    defer residency.deinit();
    var replay = try ReplayState.init(std.testing.allocator);
    defer replay.deinit();
    const default_config = dev_config.Config.defaults();
    var work = CanvasWork{
        .composer = &composer,
        .content = &content,
        .source = chrome_source,
        .surface = .{ .width = 320, .height = 240 },
        .content_origin = .{ .y = session_chrome_adapter.default_tab_bar_height },
        .frame_uploads = &frame_uploads,
        .frame_removals = &frame_removals,
        .frame_commands = &frame_commands,
        .frame_pixels = &frame_pixels,
        .surface_uploads = &surface_uploads,
        .surface_removals = &surface_removals,
        .surface_commands = &surface_commands,
        .surface_residencies = &surface_residencies,
        .canvas_residencies = &canvas_residencies,
        .builder = &builder,
        .residency = &residency,
        .terminals = &terminals,
        .cursor_policy = default_config.presentationPolicy(),
        .terminal_font_policy = try terminal_handoff.FontPolicy.init(16.0),
        .replay = &replay,
    };
    try std.testing.expectEqual(default_config.presentationPolicy(), work.cursor_policy);
    const accepted_topology = try session.SessionState.init(
        .{ .width = 320, .height = 216 },
    );
    const pane = accepted_topology.focusedPaneId();
    const render_pane = try session_chrome_adapter.toRenderPaneId(pane);
    try terminals.register(
        render_pane,
        terminal_source,
        .{ .width = 320, .height = 216 },
    );
    const lifecycle = terminals.takeLifecycle() orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqual(render_pane, lifecycle.create.pane);
    const member = try terminals.activateTransfer(render_pane);
    const terminal_command = render_api.canvas.Input{ .solid = .{
        .rect = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .clip = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .color = .{ .r = 1, .g = 2, .b = 3, .a = 255 },
    } };
    const token = try terminals.reserveUpdate(member);
    try terminals.publishUpdate(token, .{
        .revision = @fromBackingInt(1),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{terminal_command},
    });
    var topology_a = accepted_topology;
    const cancelled_pane = try topology_a.split(pane, .horizontal);
    const render_cancelled_pane = try session_chrome_adapter.toRenderPaneId(cancelled_pane);
    var cancelled_pending = try prepareTerminalTopology(
        &work,
        &accepted_topology,
        &topology_a,
        null,
    );
    try admitPendingForTest(&cancelled_pending);
    const cancelled_source = cancelled_pending.new_source orelse
        return error.TestUnexpectedResult;
    const revision_a = cancelled_pending.revision;
    var primitives: [256]render_api.chrome.Primitive = undefined;
    var text: [
        (session_chrome_adapter.max_tabs + session_chrome_adapter.max_panes_per_tab) *
            session_chrome_adapter.max_label_bytes
    ]u8 = undefined;
    switch (try buildCanvasPlan(
        &work,
        &topology_a,
        revision_a,
        .{ .pane = render_cancelled_pane, .source = cancelled_source },
        chrome_appearance,
        &primitives,
        &text,
    )) {
        .blocked => {},
        .retry => return error.TestUnexpectedResult,
        .accepted => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqual(
        revision_a,
        work.chrome_retry.?.topology_revision.?,
    );
    try std.testing.expect(terminals.visibleSetRequest() == null);

    try composer.removeSource(blocker);
    cancelled_pending.deinit();
    try std.testing.expect(terminals.sourceFor(try session_chrome_adapter.toRenderPaneId(cancelled_pane)) == null);
    var topology_b = accepted_topology;
    const replacement_pane = try topology_b.split(pane, .horizontal);
    try std.testing.expectEqual(cancelled_pane, replacement_pane);
    try topology_b.renameTab(topology_b.activeTabId(), "newer");
    var replacement_pending = try prepareTerminalTopology(
        &work,
        &accepted_topology,
        &topology_b,
        null,
    );
    defer replacement_pending.deinit();
    try admitPendingForTest(&replacement_pending);
    const replacement_source = replacement_pending.new_source orelse
        return error.TestUnexpectedResult;
    const render_replacement_pane = try session_chrome_adapter.toRenderPaneId(replacement_pane);
    try std.testing.expect(
        @backingInt(replacement_source) > @backingInt(cancelled_source),
    );
    const revision_b = replacement_pending.revision;
    var retained_topology = accepted_topology;
    const superseded_result = try buildCanvasPlan(
        &work,
        &topology_b,
        revision_b,
        .{ .pane = render_replacement_pane, .source = replacement_source },
        chrome_appearance,
        &primitives,
        &text,
    );
    switch (superseded_result) {
        .blocked => return error.TestUnexpectedResult,
        .retry => {},
        .accepted => return error.TestUnexpectedResult,
    }
    var local_retry_pending = false;
    var local_retry_count: u8 = 0;
    switch (try scheduleRedraw(.retry, false)) {
        .retry => {
            local_retry_pending = true;
            local_retry_count += 1;
        },
        .wait, .published => return error.TestUnexpectedResult,
    }
    try std.testing.expectError(
        error.InvalidFrame,
        scheduleRedraw(.retry, true),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        retained_topology.paneCount(0),
    );
    try std.testing.expect(work.chrome_retry == null);
    try std.testing.expectEqual(@as(u8, 0), work.visible_count);
    const local_retry_turn = local_retry_pending;
    local_retry_pending = false;
    var before_uploads: [32]render_api.canvas.ResourceUploadFact = undefined;
    var before_removals: [32]render_api.canvas.FrameResourceRef = undefined;
    var before_commands: [256]render_api.canvas.Command = undefined;
    var before_pixels: [64 * 1024]u8 = undefined;
    const before_frame = try composer.frame(&.{}, .{
        .uploads = &before_uploads,
        .removals = &before_removals,
        .commands = &before_commands,
        .pixels = &before_pixels,
    });
    const before_visible = terminals.acceptedVisibleSet();
    const next_visible_revision = work.next_visible_revision;
    work.next_visible_revision = std.math.maxInt(u64);
    try std.testing.expectError(
        error.RevisionOverflow,
        prepareBootstrapPublication(
            &work,
            &topology_b,
            replacement_pending.bootstrap(),
        ),
    );
    try std.testing.expectEqual(
        PendingTopologyPhase.admitted,
        replacement_pending.phase,
    );
    try std.testing.expect(terminals.takeLifecycle() == null);
    try std.testing.expect(terminals.visibleSetRequest() == null);
    try std.testing.expectEqual(
        @as(usize, 1),
        retained_topology.paneCount(0),
    );
    var after_uploads: [32]render_api.canvas.ResourceUploadFact = undefined;
    var after_removals: [32]render_api.canvas.FrameResourceRef = undefined;
    var after_commands: [256]render_api.canvas.Command = undefined;
    var after_pixels: [64 * 1024]u8 = undefined;
    const after_frame = try composer.frame(&.{}, .{
        .uploads = &after_uploads,
        .removals = &after_removals,
        .commands = &after_commands,
        .pixels = &after_pixels,
    });
    try std.testing.expectEqual(before_frame.revision, after_frame.revision);
    try std.testing.expectEqualDeep(before_frame.uploads, after_frame.uploads);
    try std.testing.expectEqualDeep(before_frame.removals, after_frame.removals);
    try std.testing.expectEqualDeep(before_frame.commands, after_frame.commands);
    try std.testing.expectEqualSlices(u8, before_frame.pixels, after_frame.pixels);
    try std.testing.expectEqualDeep(
        before_visible,
        terminals.acceptedVisibleSet(),
    );
    work.next_visible_revision = next_visible_revision;
    var replacement_publication = try prepareBootstrapPublication(
        &work,
        &topology_b,
        replacement_pending.bootstrap(),
    );
    defer replacement_publication.deinit();
    const exact = try buildCanvasPlan(
        &work,
        &topology_b,
        revision_b,
        .{ .pane = render_replacement_pane, .source = replacement_source },
        chrome_appearance,
        &primitives,
        &text,
    );
    switch (exact) {
        .blocked => return error.TestUnexpectedResult,
        .retry => return error.TestUnexpectedResult,
        .accepted => {
            residency.discard();
            try std.testing.expectEqual(
                RedrawSchedule.published,
                try scheduleRedraw(.published, local_retry_turn),
            );
        },
    }
    try std.testing.expectEqual(@as(u8, 1), local_retry_count);
    try std.testing.expect(!local_retry_pending);
    try replacement_pending.commit();
    retained_topology = topology_b;
    replacement_publication.commit(&work);
    try std.testing.expectEqual(@as(u8, 2), work.visible_count);
    try std.testing.expectEqualStrings(
        "newer",
        (try session_chrome_adapter.project(
            &retained_topology,
            chrome_appearance,
            .{ .width = 320, .height = 240 },
            .{ .y = 24 },
            &.{},
            &primitives,
            &text,
        )).text[0.."newer".len],
    );
    var observed_replacement_create = false;
    while (terminals.takeLifecycle()) |replacement_lifecycle| {
        switch (replacement_lifecycle) {
            .create => |create| {
                try std.testing.expectEqual(render_replacement_pane, create.pane);
                observed_replacement_create = true;
            },
            .resize, .close => {},
        }
    }
    try std.testing.expect(observed_replacement_create);
    const replacement_member = try terminals.activateTransfer(
        render_replacement_pane,
    );
    const replacement_request = terminals.visibleSetRequest() orelse
        return error.TestUnexpectedResult;
    const replacement_group = try terminals.reserveVisibleGroup(
        replacement_request.revision,
        &.{replacement_member},
    );
    try terminals.publishUpdate(replacement_group.tokens[0], .{
        .revision = @fromBackingInt(1),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{terminal_command},
    });
    try terminals.completeVisibleSet(
        replacement_request.revision,
        &.{
            .{
                .member = .{ .pane = try session_chrome_adapter.toRenderPaneId(pane), .source = terminal_source },
                .revision = @fromBackingInt(1),
            },
            .{
                .member = .{
                    .pane = try session_chrome_adapter.toRenderPaneId(replacement_pane),
                    .source = replacement_source,
                },
                .revision = @fromBackingInt(1),
            },
        },
        true,
    );
    switch (try buildCanvasPlan(
        &work,
        &retained_topology,
        revision_b,
        null,
        chrome_appearance,
        &primitives,
        &text,
    )) {
        .blocked => return error.TestUnexpectedResult,
        .retry => return error.TestUnexpectedResult,
        .accepted => residency.discard(),
    }
    const replacement_reuse = try terminals.reserveUpdate(
        replacement_member,
    );
    try terminals.cancelUpdate(replacement_reuse);

    const later = try terminals.reserveUpdate(member);
    try terminals.publishUpdate(later, .{
        .revision = @fromBackingInt(2),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{terminal_command},
    });
    for (0..window_render_boundary.slot_count) |_| {
        const replacement_plan = try buildAcceptedCanvasPlan(&work);
        try std.testing.expect(replacement_plan.commands.len != 0);
        residency.discard();
    }
    try std.testing.expectError(error.Busy, terminals.reserveUpdate(member));
    switch (try buildCanvasPlan(
        &work,
        &retained_topology,
        revision_b,
        null,
        chrome_appearance,
        &primitives,
        &text,
    )) {
        .blocked => return error.TestUnexpectedResult,
        .retry => return error.TestUnexpectedResult,
        .accepted => residency.discard(),
    }
    const reused = try terminals.reserveUpdate(member);
    try terminals.cancelUpdate(reused);
}

test "CanvasWork cursor retention layout receipt" {
    // d67cb4b baseline: 4096 bytes; the prior cursor view retained 56 bytes.
    // Trail records, exact TabId slots, endpoint clips, scratch, deadlines,
    // demand, accepted presentation ownership, transfer candidate, and the
    // latest publication, accepted cursor color, and absolute-position
    // timestamp add 1504 bytes, yielding the exact 5656-byte record.
    const baseline_size: usize = 4096;
    const prior_cursor_delta: usize = 56;
    const trail_delta: usize = 1504;
    try std.testing.expectEqual(@as(usize, 8), @alignOf(CanvasWork));
    try std.testing.expectEqual(
        baseline_size + prior_cursor_delta + trail_delta,
        @sizeOf(CanvasWork),
    );
}

test "active TabId transfers the accepted trail presentation" {
    var topology = try session.SessionState.init(
        .{ .width = 640, .height = 480 },
    );
    var work: CanvasWork = undefined;
    resetTrailRecords(&work);
    try reconcileTrailTopology(&work, &topology);
    const first = topology.activeTabId();
    const second = try topology.createTab("incoming");
    try topology.switchTab(first); // incoming retains semantic state while hidden
    try reconcileTrailTopology(&work, &topology);
    const first_slot = findTrailSlot(&work, first).?;
    const second_slot = findTrailSlot(&work, second).?;
    work.trails[first_slot] = .{
        .id = first,
        .initialized = true,
        .trail = .{
            .needs_render = false,
            .updated_at = 91,
            .opacity = 0.75,
            .corner_x = .{ 11, 21, 21, 11 },
            .corner_y = .{ 12, 12, 32, 32 },
            .endpoint_clip = .{ .x = 1, .y = 2, .width = 30, .height = 40 },
            .target_clip = .{ .x = 5, .y = 6, .width = 20, .height = 24 },
        },
    };
    work.trails[second_slot] = .{ .id = second };
    work.accepted_trail_surface = .{
        .owner = first,
        .trail = work.trails[first_slot].trail,
        .initialized = true,
    };

    // A -> B copies the last physically accepted state, then marks only the
    // transferred presentation as due; exact semantic targets remain per tab.
    var transfer = TrailTransferCandidate{ .from = first, .to = second };
    transferTrailPresentation(&transfer, work.accepted_trail_surface, 2_000);
    try std.testing.expect(transfer.initialized);
    try std.testing.expect(transfer.trail.needs_render);
    try std.testing.expectEqual(@as(u64, 2_000), transfer.trail.updated_at);
    try std.testing.expectEqual(work.trails[first_slot].trail.corner_x, transfer.trail.corner_x);
    try std.testing.expectEqual(work.trails[first_slot].trail.corner_y, transfer.trail.corner_y);
    try std.testing.expectEqual(work.trails[first_slot].trail.endpoint_clip, transfer.trail.endpoint_clip);

    // B -> A transfers the currently accepted B presentation, not A's stale
    // historical record. This is the Kitty presentation-transfer rule.
    transfer.trail.corner_x = .{ 101, 111, 111, 101 };
    transfer.trail.corner_y = .{ 102, 102, 122, 122 };
    transfer.trail.opacity = 0.4;
    work.accepted_trail_surface = .{ .owner = second, .trail = transfer.trail, .initialized = true };
    var reverse = TrailTransferCandidate{ .from = second, .to = first };
    transferTrailPresentation(&reverse, work.accepted_trail_surface, 3_000);
    try std.testing.expectEqual(transfer.trail.corner_x, reverse.trail.corner_x);
    try std.testing.expectEqual(transfer.trail.corner_y, reverse.trail.corner_y);
    try std.testing.expectEqual(transfer.trail.opacity, reverse.trail.opacity);
    try std.testing.expect(reverse.trail.needs_render);
    try std.testing.expectEqual(@as(u64, 3_000), reverse.trail.updated_at);

    // A -> B superseded by C is rebased from A, not from speculative B.
    work.accepted_trail_surface = .{ .owner = first, .trail = reverse.trail, .initialized = true };
    work.trail_transfer = .{
        .from = first,
        .to = second,
        .trail = transfer.trail,
        .initialized = true,
        .deadline = 400,
    };
    work.trail_transfer_previous_deadline = 300;
    work.trail_deadline = 400;
    try topology.closeTab(second);
    try reconcileTrailTopology(&work, &topology);
    const third = try topology.createTab("superseding");
    prepareTrailTransferCandidate(&work, third, 5_000);
    try std.testing.expectEqual(first, work.trail_transfer.?.from);
    try std.testing.expectEqual(third, work.trail_transfer.?.to);
    try std.testing.expectEqual(first, work.accepted_trail_surface.?.owner);
    try std.testing.expectEqual(@as(u64, 300), work.trail_transfer_previous_deadline.?);

    // Retiring the accepted semantic TabId does not retire the physical
    // snapshot. A replacement can still animate from that accepted surface.
    try topology.closeTab(first);
    try reconcileTrailTopology(&work, &topology);
    try topology.closeTab(third);
    try reconcileTrailTopology(&work, &topology);
    const closed_replacement = try topology.createTab("closed-replacement");
    try reconcileTrailTopology(&work, &topology);
    prepareTrailTransferCandidate(&work, closed_replacement, 6_000);
    try std.testing.expectEqual(first, work.trail_transfer.?.from);
    try std.testing.expect(work.trail_transfer.?.initialized);
    try std.testing.expectEqual(first, work.accepted_trail_surface.?.owner);

    // A closed TabId is retired before any slot can be reused, so a delayed
    // transfer cannot leak its accepted presentation into the replacement.
    try topology.closeTab(closed_replacement);
    try reconcileTrailTopology(&work, &topology);
    const replacement = try topology.createTab("replacement");
    try reconcileTrailTopology(&work, &topology);
    const replacement_slot = findTrailSlot(&work, replacement).?;
    try std.testing.expect(!work.trails[replacement_slot].initialized);
    try std.testing.expectEqual(@as(f32, 0), work.trails[replacement_slot].trail.opacity);
    try std.testing.expectEqual(first, work.accepted_trail_surface.?.owner);
}

test "accepted topology tab transition transfers through Composer bindings" {
    var terminals = try terminal_handoff.Boundary.init(
        std.testing.io,
        std.testing.allocator,
        .{
            .commands = 16,
            .upload_bytes = 1024,
            .cells = 16,
            .rows = 4,
            .images = 1,
            .placements = 4,
            .image_bytes = 1024,
            .glyphs = 8,
            .masks = 4,
            .resources_per_update = 4,
            .raster_bytes = 1024,
            .decoration_bytes = 1024,
        },
    );
    defer terminals.deinit();
    var composer = try render_api.canvas.Composer.init(
        std.testing.allocator,
        .{
            .sources = 4,
            .retained_resources = 4,
            .retained_commands = 8,
            .retained_pixel_bytes = 1024,
            .composition_sources = 4,
            .candidate_resources = 4,
            .candidate_commands = 8,
            .candidate_pixel_bytes = 1024,
        },
    );
    defer composer.deinit();
    var topology = try session.SessionState.init(
        .{ .width = 640, .height = 480 },
    );
    const first_tab = topology.activeTabId();
    const second_tab = try topology.createTab("incoming");
    try topology.switchTab(first_tab);
    const first_pane = topology.focusedPaneId();
    try topology.switchTab(second_tab);
    const second_pane = topology.focusedPaneId();
    try topology.switchTab(first_tab);

    const first_source = try composer.registerSource();
    const second_source = try composer.registerSource();
    const pane_ids = [_]render_api.chrome.PaneId{
        try session_chrome_adapter.toRenderPaneId(first_pane),
        try session_chrome_adapter.toRenderPaneId(second_pane),
    };
    const sources = [_]render_api.canvas.SourceId{ first_source, second_source };
    var placements: [2]render_api.canvas.Composer.Placement = undefined;
    const solid = render_api.canvas.Input{ .solid = .{
        .rect = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .clip = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .color = .{ .r = 1, .g = 2, .b = 3, .a = 255 },
    } };
    for (pane_ids, sources, 0..) |pane, source, index| {
        const semantic_pane = if (index == 0) first_pane else second_pane;
        const rect = topology.paneRect(semantic_pane).?;
        try terminals.register(pane, source, .{ .width = rect.width, .height = rect.height });
        try std.testing.expect(terminals.takeLifecycle() != null);
        const member = try terminals.activateTransfer(pane);
        try std.testing.expectEqual(pane, member.pane_id);
        try std.testing.expectEqual(source, member.source_id);
        try terminals.markLive(pane);
        try composer.apply(source, .{
            .revision = @fromBackingInt(1),
            .uploads = &.{},
            .removals = &.{},
            .commands = &.{solid},
            .cursor_binding = .{
                .pane = @backingInt(pane),
                .source = source,
                .terminal_sequence = 1,
                .cursor_revision = 1,
                .visible_set_revision = 1,
                .lifecycle_revision = 1,
                .rect = .{ .x = @intCast(index * 20), .y = 24, .width = 10, .height = 20 },
                .cell_size = .{ .width = 10, .height = 20 },
                .clip = .{ .x = 0, .y = 24, .width = 640, .height = 456 },
                .visible = true,
            },
        });
        placements[index] = .{
            .source = source,
            .origin = .{ .x = rect.x, .y = rect.y },
            .clip = .{ .x = rect.x, .y = rect.y, .width = rect.width, .height = rect.height },
        };
    }
    terminals.visible_members[0..2].* = .{
        .{ .pane = pane_ids[0], .source = first_source },
        .{ .pane = pane_ids[1], .source = second_source },
    };
    terminals.visible_member_count = 2;
    terminals.visible_revision = 1;
    terminals.visible_initialized = true;
    try composer.setComposition(.{
        .surface = .{ .width = 640, .height = 480 },
        .sources = &placements,
        .focused_source = first_source,
    });

    var replay = try ReplayState.init(std.testing.allocator);
    defer replay.deinit();
    var work: CanvasWork = undefined;
    work.composer = &composer;
    work.terminals = &terminals;
    work.cursor_policy = dev_config.Config.defaults().presentationPolicy();
    work.replay = &replay;
    @memcpy(work.visible_placements[0..2], &placements);
    work.visible_count = 2;
    resetTrailRecords(&work);
    try reconcileTrailTopology(&work, &topology);
    try syncAcceptedTrail(&work, &topology, 1_000, true);
    // Semantic synchronization alone does not establish a physical surface
    // snapshot; the initial frame must cross the acceptance boundary first.
    try std.testing.expect(work.accepted_trail_surface == null);
    const first_slot = findTrailSlot(&work, first_tab).?;
    work.trails[first_slot].trail.corner_x = .{ 11, 21, 21, 11 };
    work.trails[first_slot].trail.corner_y = .{ 12, 12, 32, 32 };
    work.trails[first_slot].trail.opacity = 0.6;
    work.trails[first_slot].trail.needs_render = false;
    try acceptTrailSurfaceSnapshot(&work, first_tab);

    // A newer semantic target may update the tab-local candidate before its
    // physical replay is accepted.  The surface snapshot must remain the
    // last accepted presentation for a later tab transfer.
    const accepted_surface_before_retarget = work.accepted_trail_surface.?;
    work.trails[first_slot].trail.corner_x = .{ 31, 41, 41, 31 };
    work.trails[first_slot].trail.corner_y = .{ 32, 32, 52, 52 };
    try syncAcceptedTrail(&work, &topology, 1_500, false);
    try std.testing.expectEqual(accepted_surface_before_retarget, work.accepted_trail_surface.?);

    // The second tab retained its binding while hidden. Once the accepted
    // topology switches to it, the production sync path copies the outgoing
    // physical state and restarts the Kitty transition clock.
    try topology.switchTab(second_tab);
    try composer.setComposition(.{
        .surface = .{ .width = 640, .height = 480 },
        .sources = &placements,
        .focused_source = second_source,
    });
    try syncAcceptedTrail(&work, &topology, 2_000, false);
    const second_slot = findTrailSlot(&work, second_tab).?;
    const pending_transfer = work.trail_transfer.?;
    try std.testing.expectEqual(first_tab, pending_transfer.from);
    try std.testing.expectEqual(second_tab, pending_transfer.to);
    try std.testing.expect(pending_transfer.initialized);
    try std.testing.expect(pending_transfer.trail.needs_render);
    try std.testing.expectEqual(@as(u64, 2_000), pending_transfer.trail.updated_at);
    try std.testing.expect(!work.trails[second_slot].initialized);
    try std.testing.expectEqual(first_tab, work.accepted_trail_surface.?.owner);
    try std.testing.expectEqual(accepted_surface_before_retarget.trail.corner_x, pending_transfer.trail.corner_x);
    try std.testing.expectEqual(accepted_surface_before_retarget.trail.corner_y, pending_transfer.trail.corner_y);
    try std.testing.expect(work.trail_deadline != null);

    // A rejected physical replay leaves both the outgoing accepted state and
    // the incoming transfer candidate byte-identical; the exact retry then
    // commits the transfer and its owner together.
    const accepted_before_rejection = work.trails[first_slot];
    const transfer_before_rejection = work.trail_transfer.?;
    const surface_before_rejection = work.accepted_trail_surface.?;
    try std.testing.expect(try prepareTrailAnimation(&work, &topology, 2_000_000_000));
    discardTrailAnimation(&work, false);
    try std.testing.expectEqual(accepted_before_rejection, work.trails[first_slot]);
    try std.testing.expectEqual(transfer_before_rejection, work.trail_transfer.?);
    try std.testing.expectEqual(surface_before_rejection, work.accepted_trail_surface.?);
    try std.testing.expect(try prepareTrailAnimation(&work, &topology, 3_000_000_000));
    commitTrailAnimation(&work);
    try std.testing.expect(work.trails[second_slot].initialized);
    try std.testing.expectEqual(second_tab, work.accepted_trail_surface.?.owner);
    try std.testing.expect(work.trail_transfer == null);

    // B -> A with no accepted A binding retains the pending transfer rather
    // than advancing ownership. Restoring the binding later retargets the
    // retained B presentation and commits it only with the replay frame.
    try topology.switchTab(first_tab);
    try composer.setComposition(.{
        .surface = .{ .width = 640, .height = 480 },
        .sources = &placements,
        .focused_source = first_source,
    });
    const first_before_missing_binding = work.trails[first_slot];
    try composer.apply(first_source, .{
        .revision = @fromBackingInt(2),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{solid},
        .cursor_binding = null,
    });
    try syncAcceptedTrail(&work, &topology, 3_000, false);
    try std.testing.expectEqual(first_before_missing_binding, work.trails[first_slot]);
    try std.testing.expectEqual(second_tab, work.accepted_trail_surface.?.owner);
    try std.testing.expectEqual(first_tab, work.trail_transfer.?.to);
    try std.testing.expectEqual(work.trails[second_slot].trail.corner_x, work.trail_transfer.?.trail.corner_x);
    try std.testing.expectEqual(work.trails[second_slot].trail.corner_y, work.trail_transfer.?.trail.corner_y);
    try std.testing.expect(work.trail_transfer.?.deadline == null);
    try composer.apply(first_source, .{
        .revision = @fromBackingInt(3),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{solid},
        .cursor_binding = .{
            .pane = @backingInt(first_pane),
            .source = first_source,
            .terminal_sequence = 1,
            .cursor_revision = 1,
            .visible_set_revision = 1,
            .lifecycle_revision = 1,
            .rect = .{ .x = 0, .y = 24, .width = 10, .height = 20 },
            .cell_size = .{ .width = 10, .height = 20 },
            .clip = .{ .x = 0, .y = 24, .width = 640, .height = 456 },
            .visible = true,
        },
    });
    try syncAcceptedTrail(&work, &topology, 4_000, false);
    const missing_transfer_before_rejection = work.trail_transfer.?;
    try std.testing.expect(try prepareTrailAnimation(&work, &topology, 2_000_000_000));
    discardTrailAnimation(&work, false);
    try std.testing.expectEqual(second_tab, work.accepted_trail_surface.?.owner);
    try std.testing.expectEqual(missing_transfer_before_rejection, work.trail_transfer.?);
    try std.testing.expect(try prepareTrailAnimation(&work, &topology, 2_000_000_000));
    commitTrailAnimation(&work);
    try std.testing.expectEqual(first_tab, work.accepted_trail_surface.?.owner);
    try std.testing.expect(work.trail_transfer == null);
}

test "cursor trail storage follows exact TabId lifecycle" {
    var topology = try session.SessionState.init(
        .{ .width = 640, .height = 480 },
    );
    var work: CanvasWork = undefined;
    resetTrailRecords(&work);
    try reconcileTrailTopology(&work, &topology);
    const first = topology.activeTabId();
    const second = try topology.createTab("hidden");
    try reconcileTrailTopology(&work, &topology);
    work.trails[findTrailSlot(&work, first).?].trail.opacity = 0.25;
    work.trails[findTrailSlot(&work, second).?].trail.opacity = 0.75;
    try topology.switchTab(first);
    try reconcileTrailTopology(&work, &topology);
    try std.testing.expectEqual(@as(f32, 0.25), work.trails[findTrailSlot(&work, first).?].trail.opacity);
    try std.testing.expectEqual(@as(f32, 0.75), work.trails[findTrailSlot(&work, second).?].trail.opacity);
    try topology.closeTab(second);
    try reconcileTrailTopology(&work, &topology);
    const third = try topology.createTab("replacement");
    try reconcileTrailTopology(&work, &topology);
    try std.testing.expect(third != second);
    try std.testing.expectEqual(@as(f32, 0.25), work.trails[findTrailSlot(&work, first).?].trail.opacity);
    try std.testing.expectEqual(@as(f32, 0), work.trails[findTrailSlot(&work, third).?].trail.opacity);
}

test "Host focus directions admit one physical trail quad" {
    // This is a Host-only topology receipt: input_actions selects the real
    // focus candidate, Composer owns the accepted source bindings, and the
    // replay preparation must carry one trail quad for every cardinal move.
    // It deliberately stops before Vulkan recording, so no PTY, GUI, or
    // terminal-output fixture can mask a directional presentation defect.
    const actions = [_]input_actions.Action{
        .focus_up,
        .focus_left,
        .focus_down,
        .focus_right,
    };
    var replay = try ReplayState.init(std.testing.allocator);
    defer replay.deinit();
    for (actions) |action| {
        var terminals = try terminal_handoff.Boundary.init(
            std.testing.io,
            std.testing.allocator,
            .{
                .commands = 64,
                .upload_bytes = 4096,
                .cells = 64,
                .rows = 16,
                .images = 1,
                .placements = 8,
                .image_bytes = 4096,
                .glyphs = 16,
                .masks = 8,
                .resources_per_update = 16,
                .raster_bytes = 4096,
                .decoration_bytes = 4096,
            },
        );
        defer terminals.deinit();
        var composer = try render_api.canvas.Composer.init(
            std.testing.allocator,
            .{
                .sources = 8,
                .retained_resources = 8,
                .retained_commands = 16,
                .retained_pixel_bytes = 4096,
                .composition_sources = 8,
                .candidate_resources = 8,
                .candidate_commands = 16,
                .candidate_pixel_bytes = 4096,
            },
        );
        defer composer.deinit();

        var accepted = try session.SessionState.init(
            .{ .width = 640, .height = 480 },
        );
        const root = accepted.focusedPaneId();
        const right = try accepted.split(root, .vertical);
        const lower_right = try accepted.split(right, .horizontal);
        const lower_left = try accepted.split(root, .horizontal);
        switch (action) {
            .focus_up, .focus_right => try accepted.focusPane(lower_left),
            .focus_left => try accepted.focusPane(lower_right),
            .focus_down => try accepted.focusPane(root),
            else => unreachable,
        }
        const candidate = (try input_actions.candidate(&accepted, action)).?.state;

        var panes: [4]render_api.chrome.PaneId = undefined;
        var sources: [4]render_api.canvas.SourceId = undefined;
        var placements: [4]render_api.canvas.Composer.Placement = undefined;
        for (0..4) |index| {
            panes[index] = try session_chrome_adapter.toRenderPaneId(accepted.paneId(0, index).?);
            sources[index] = try composer.registerSource();
            const pane_rect = accepted.paneRect(try session_chrome_adapter.fromRenderPaneId(panes[index])).?;
            try terminals.register(
                panes[index],
                sources[index],
                .{ .width = pane_rect.width, .height = pane_rect.height },
            );
            try std.testing.expect(terminals.takeLifecycle() != null);
            const member = try terminals.activateTransfer(panes[index]);
            try std.testing.expectEqual(panes[index], member.pane_id);
            try std.testing.expectEqual(sources[index], member.source_id);
            try terminals.markLive(panes[index]);
            placements[index] = .{
                .source = sources[index],
                .origin = .{ .x = pane_rect.x, .y = pane_rect.y },
                .clip = .{
                    .x = pane_rect.x,
                    .y = pane_rect.y,
                    .width = pane_rect.width,
                    .height = pane_rect.height,
                },
            };
        }
        terminals.visible_members[0..4].* = .{
            .{ .pane = panes[0], .source = sources[0] },
            .{ .pane = panes[1], .source = sources[1] },
            .{ .pane = panes[2], .source = sources[2] },
            .{ .pane = panes[3], .source = sources[3] },
        };
        terminals.visible_member_count = 4;
        terminals.visible_revision = 1;
        terminals.visible_initialized = true;
        const solid = render_api.canvas.Input{ .solid = .{
            .rect = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
            .clip = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
            .color = .{ .r = 1, .g = 2, .b = 3, .a = 255 },
        } };
        for (0..4) |index| {
            const pane_rect = accepted.paneRect(try session_chrome_adapter.fromRenderPaneId(panes[index])).?;
            try composer.apply(sources[index], .{
                .revision = @fromBackingInt(1),
                .uploads = &.{},
                .removals = &.{},
                .commands = &.{solid},
                .cursor_binding = .{
                    .pane = @backingInt(panes[index]),
                    .source = sources[index],
                    .terminal_sequence = 1,
                    .cursor_revision = 1,
                    .visible_set_revision = 1,
                    .lifecycle_revision = 1,
                    .rect = .{ .x = 0, .y = 0, .width = 10, .height = 20 },
                    .cell_size = .{ .width = 10, .height = 20 },
                    .clip = .{ .x = 0, .y = 0, .width = pane_rect.width, .height = pane_rect.height },
                    .visible = true,
                },
            });
        }
        try composer.setComposition(.{
            .surface = .{ .width = 640, .height = 480 },
            .sources = &placements,
            .focused_source = sources[0],
        });

        var work: CanvasWork = undefined;
        work.composer = &composer;
        work.terminals = &terminals;
        work.cursor_policy = dev_config.Config.defaults().presentationPolicy();
        work.replay = &replay;
        @memcpy(work.visible_placements[0..4], &placements);
        work.visible_count = 4;
        resetTrailRecords(&work);
        try reconcileTrailTopology(&work, &accepted);
        try syncAcceptedTrail(&work, &accepted, 1_000_000, true);
        const old_pane = accepted.focusedPaneId();
        const old_source = terminals.sourceFor(try session_chrome_adapter.toRenderPaneId(old_pane)).?;
        const old_overlay = (try cursorOverlayForBinding(&work, old_source)).?;
        const accepted_before_target = work.trails[findTrailSlot(&work, accepted.activeTabId()).?].trail;

        var candidate_placements = placements;
        for (0..4) |index| {
            const pane_rect = candidate.paneRect(try session_chrome_adapter.fromRenderPaneId(panes[index])).?;
            candidate_placements[index].origin = .{ .x = pane_rect.x, .y = pane_rect.y };
            candidate_placements[index].clip = .{
                .x = pane_rect.x,
                .y = pane_rect.y,
                .width = pane_rect.width,
                .height = pane_rect.height,
            };
        }
        try composer.setComposition(.{
            .surface = .{ .width = 640, .height = 480 },
            .sources = &candidate_placements,
            .focused_source = terminals.sourceFor(try session_chrome_adapter.toRenderPaneId(candidate.focusedPaneId())),
        });
        @memcpy(work.visible_placements[0..4], &candidate_placements);
        try reconcileTrailTopology(&work, &candidate);
        try syncAcceptedTrail(&work, &candidate, 2_000_000, false);
        const new_pane = candidate.focusedPaneId();
        const new_source = terminals.sourceFor(try session_chrome_adapter.toRenderPaneId(new_pane)).?;
        const new_overlay = (try cursorOverlayForBinding(&work, new_source)).?;
        try std.testing.expect(old_pane != new_pane);
        try std.testing.expect(old_source != new_source);
        try std.testing.expect(!std.meta.eql(old_overlay.rect, new_overlay.rect));
        const accepted_after_target = work.trails[findTrailSlot(&work, candidate.activeTabId()).?].trail;
        try std.testing.expectEqual(accepted_before_target.corner_x, accepted_after_target.corner_x);
        try std.testing.expectEqual(accepted_before_target.corner_y, accepted_after_target.corner_y);
        try std.testing.expect(work.trail_deadline != null);
        try std.testing.expect(try prepareTrailAnimation(&work, &candidate, 4_000_000));
        const accepted_before_rejection = accepted_after_target;
        work.trail_frame_pending = true;
        const base = vk_surface.Plan{
            .vertices = &.{},
            .indices = &.{},
            .commands = &.{},
            .atlas_changed = false,
        };
        const physical = try physicalPlanForBase(
            &work,
            base,
            try session_chrome_adapter.toRenderPaneId(candidate.focusedPaneId()),
            &work.trail_scratch,
        );
        const expected_trail_clip = try checkedTrailClipUnion(
            old_overlay.clip,
            new_overlay.clip,
        );
        const expected_cursor_clip = intersectSurfaceRect(new_overlay.clip, new_overlay.rect).?;
        try std.testing.expect(intersectSurfaceRect(expected_trail_clip, old_overlay.rect) != null);
        try std.testing.expect(intersectSurfaceRect(expected_trail_clip, new_overlay.rect) != null);
        try std.testing.expectEqual(expected_trail_clip, physical.commands[0].clip);
        try std.testing.expectEqual(expected_cursor_clip, physical.commands[1].clip);
        const expected_right = std.math.add(
            i32,
            expected_trail_clip.x,
            @intCast(expected_trail_clip.width),
        ) catch return error.InvalidFrame;
        const expected_bottom = std.math.add(
            i32,
            expected_trail_clip.y,
            @intCast(expected_trail_clip.height),
        ) catch return error.InvalidFrame;
        for (work.trail_scratch.corner_x, work.trail_scratch.corner_y) |x, y| {
            try std.testing.expect(x >= @as(f32, @floatFromInt(expected_trail_clip.x)));
            try std.testing.expect(y >= @as(f32, @floatFromInt(expected_trail_clip.y)));
            try std.testing.expect(x <= @as(f32, @floatFromInt(expected_right)));
            try std.testing.expect(y <= @as(f32, @floatFromInt(expected_bottom)));
        }
        const accepted_before_invalid_union = work.trails[findTrailSlot(&work, candidate.activeTabId()).?].trail;
        const candidate_commands_before_invalid_union = replay.candidate().command_count;
        var invalid_union_trail = work.trail_scratch;
        invalid_union_trail.endpoint_clip.x = -1;
        try std.testing.expectError(
            error.InvalidFrame,
            physicalPlanForBase(
                &work,
                base,
                try session_chrome_adapter.toRenderPaneId(candidate.focusedPaneId()),
                &invalid_union_trail,
            ),
        );
        try std.testing.expectEqual(
            accepted_before_invalid_union,
            work.trails[findTrailSlot(&work, candidate.activeTabId()).?].trail,
        );
        try std.testing.expectEqual(candidate_commands_before_invalid_union, replay.candidate().command_count);
        var trail_commands: usize = 0;
        for (physical.commands) |command| {
            if (command.kind == .trail) trail_commands += 1;
        }
        try std.testing.expectEqual(@as(usize, 1), trail_commands);
        try std.testing.expectEqual(@as(usize, 2), physical.commands.len);
        var rejected_overlay = (try cursorOverlayForBinding(&work, new_source)).?;
        rejected_overlay.trail = .{
            .corner_x = work.trail_scratch.corner_x,
            .corner_y = work.trail_scratch.corner_y,
            .clip = rejected_overlay.clip,
            .opacity = work.trail_scratch.opacity,
            .color = rejected_overlay.color,
            .cursor_rect = rejected_overlay.rect,
        };
        var rejected_vertices: [4]vk_surface.Vertex = undefined;
        var rejected_indices: [6]u32 = undefined;
        var rejected_commands: [1]vk_surface.Command = undefined;
        try std.testing.expectError(
            error.ReplayCapacity,
            vk_surface.replayCursor(
                base,
                rejected_overlay,
                .{
                    .vertices = &rejected_vertices,
                    .indices = &rejected_indices,
                    .commands = &rejected_commands,
                },
            ),
        );
        discardTrailAnimation(&work, false);
        try std.testing.expectEqual(
            accepted_before_rejection,
            work.trails[findTrailSlot(&work, candidate.activeTabId()).?].trail,
        );

        // Every accepted in-flight frame retains the outgoing clip.  Only
        // the frame whose corners and opacity are settled promotes the
        // destination clip, after which the next physical plan collapses to
        // the destination pane.
        var accepted_frames: usize = 0;
        var settled = false;
        var animation_now: u64 = 5_000_000;
        while (animation_now < 20_000_000_000) : (animation_now += 100_000_000) {
            if (!try prepareTrailAnimation(&work, &candidate, animation_now)) continue;
            const candidate_settled = !work.trail_scratch.needs_render and
                work.trail_scratch_deadline == null;
            const frame = try physicalPlanForBase(
                &work,
                base,
                try session_chrome_adapter.toRenderPaneId(candidate.focusedPaneId()),
                &work.trail_scratch,
            );
            try std.testing.expectEqual(expected_trail_clip, frame.commands[0].clip);
            commitTrailAnimation(&work);
            const accepted_frame = work.trails[findTrailSlot(&work, candidate.activeTabId()).?].trail;
            if (candidate_settled) {
                try std.testing.expectEqual(new_overlay.clip, accepted_frame.endpoint_clip);
                settled = true;
                break;
            }
            try std.testing.expectEqual(old_overlay.clip, accepted_frame.endpoint_clip);
            accepted_frames += 1;
        }
        try std.testing.expect(accepted_frames >= 2);
        try std.testing.expect(settled);
        const settled_frame = work.trails[findTrailSlot(&work, candidate.activeTabId()).?].trail;
        const collapsed = try physicalPlanForBase(
            &work,
            base,
            try session_chrome_adapter.toRenderPaneId(candidate.focusedPaneId()),
            &settled_frame,
        );
        try std.testing.expectEqual(new_overlay.clip, collapsed.commands[0].clip);
    }
}

test "compact resource adaptation preserves local and shared namespaces mechanically" {
    try std.testing.expectEqual(
        @as(usize, 16),
        @sizeOf(render_api.canvas.ResourceRef),
    );
    try std.testing.expectEqual(
        @as(usize, 24),
        @sizeOf(render_api.canvas.FrameResourceRef),
    );
    try std.testing.expectEqual(
        @as(usize, 56),
        @sizeOf(render_api.canvas.ResourceUpload),
    );
    try std.testing.expectEqual(
        @as(usize, 72),
        @sizeOf(render_api.canvas.Input),
    );
    try std.testing.expectEqual(
        @as(usize, 56),
        @sizeOf(render_api.canvas.ResourceUploadFact),
    );
    try std.testing.expectEqual(
        @as(usize, 80),
        @sizeOf(render_api.canvas.Command),
    );
    try std.testing.expectEqual(
        @as(usize, 24),
        @sizeOf(vk_surface.ResourceGeneration),
    );
    const generation: render_api.canvas.ResourceGeneration = @fromBackingInt(@intCast(5));
    const source: render_api.canvas.SourceId = @fromBackingInt(@intCast(7));
    const local = try render_api.canvas.FrameResourceRef.local(source, .{
        .resource = try render_api.canvas.ResourceId.local(11),
        .generation = generation,
    });
    const colliding_local = try render_api.canvas.FrameResourceRef.local(
        @fromBackingInt(@intCast(8)),
        .{
            .resource = try render_api.canvas.ResourceId.local(11),
            .generation = generation,
        },
    );
    const shared_resource = try render_api.canvas.FrameResourceRef.shared(.{
        .resource = try render_api.canvas.ResourceId.shared(11),
        .generation = generation,
    });
    const local_vk = try surfaceResource(local);
    const colliding_local_vk = try surfaceResource(colliding_local);
    const shared_vk = try surfaceResource(shared_resource);
    try std.testing.expect(!std.meta.eql(local_vk, shared_vk));
    try std.testing.expect(!std.meta.eql(local_vk, colliding_local_vk));
    try std.testing.expectEqual(local, try canvasResource(local_vk));
    try std.testing.expectEqual(
        colliding_local,
        try canvasResource(colliding_local_vk),
    );
    try std.testing.expectEqual(shared_resource, try canvasResource(shared_vk));
    const pixels = [_]u8{ 1, 2, 3, 4 };
    const frame = render_api.canvas.Composer.Frame{
        .revision = @fromBackingInt(@intCast(13)),
        .uploads = &.{.{
            .resource = local,
            .format = .rgba8,
            .size = .{ .width = 1, .height = 1 },
            .pixel_offset = 0,
            .pixel_count = pixels.len,
            .stride = 4,
        }},
        .removals = &.{},
        .commands = &.{.{ .rgba = .{
            .destination = .{ .x = 2, .y = 3, .width = 1, .height = 1 },
            .clip = .{ .x = 2, .y = 3, .width = 1, .height = 1 },
            .resource = .{
                .resource = local,
                .format = .rgba8,
                .size = .{ .width = 1, .height = 1 },
            },
        } }},
        .pixels = &pixels,
    };
    var uploads: [1]vk_surface.Upload = undefined;
    var removals: [1]vk_surface.Removal = undefined;
    var commands: [1]vk_surface.FrameCommand = undefined;
    const adapted = try adaptCanvasFrame(
        frame,
        &uploads,
        &removals,
        &commands,
    );
    try std.testing.expectEqual(@as(u64, 13), adapted.revision);
    try std.testing.expectEqual(local_vk, adapted.uploads[0].resource);
    try std.testing.expectEqualSlices(u8, &pixels, adapted.uploads[0].pixels);
    try std.testing.expectEqual(local_vk, adapted.commands[0].rgba.resource);
}

fn panePixelsLocal(rect: session.Rect) error{InvalidTopology}!render_api.canvas.Size {
    if (rect.width == 0 or rect.height == 0) return error.InvalidTopology;
    return .{ .width = rect.width, .height = rect.height };
}

fn redrawChrome(
    boundary: *window_render_boundary.Boundary,
    topology: *session.SessionState,
    canvas_work: *CanvasWork,
    appearance: session_chrome_adapter.Appearance,
    primitives: *[256]render_api.chrome.Primitive,
    text: *[(session_chrome_adapter.max_tabs + session_chrome_adapter.max_panes_per_tab) * session_chrome_adapter.max_label_bytes]u8,
    graphics: *vk_surface.Context,
    device: vk.VkDevice,
    queue: vk.VkQueue,
    family: u32,
    command: vk.VkCommandBuffer,
    slots: *[window_render_boundary.slot_count]Slot,
    generation: u64,
    dispatch: *const howl_vk.dispatch.ExternalImageDispatch,
    drm_fd: i32,
    acquire_handle: u32,
    next_acquire_point: *u64,
    pending: ?*PendingTopology,
    include_trail: bool,
    trail_candidate_carried: *bool,
) !RedrawResult {
    trail_candidate_carried.* = false;
    if (!try releaseReplayRetirementIfReady(
        boundary,
        canvas_work.replay,
        generation,
        slots,
        drm_fd,
    )) return .blocked;
    const candidate = if (pending) |value| value.candidate.state else topology.*;
    const topology_revision = if (pending) |value| value.revision else null;
    const projection_surface = if (pending) |value|
        if (value.surface) |surface| renderExtent(surface) else canvas_work.surface
    else
        canvas_work.surface;
    const projection_origin = if (pending) |value|
        if (value.surface) |surface|
            try session_chrome_adapter.contentOrigin(renderExtent(surface), session_chrome_adapter.default_tab_bar_height)
        else
            canvas_work.content_origin
    else
        canvas_work.content_origin;
    try validateTerminalTopology(&candidate);
    var bootstrap_publication: ?PreparedBootstrapPublication =
        if (pending) |value|
            if (value.new_source != null)
                try prepareBootstrapPublicationAt(
                    canvas_work,
                    &candidate,
                    value.bootstrap(),
                    projection_origin,
                )
            else
                null
        else
            null;
    defer if (bootstrap_publication) |*publication| publication.deinit();
    const plan_result = try buildCanvasPlanAt(
        canvas_work,
        &candidate,
        topology_revision,
        if (pending) |value| value.bootstrap() else null,
        appearance,
        primitives,
        text,
        projection_surface,
        projection_origin,
    );
    const composer_plan = switch (plan_result) {
        .blocked => return .blocked,
        .retry => return .retry,
        .accepted => |plan| plan,
    };
    var candidate_guard = CandidateOwnershipGuard{ .work = canvas_work };
    defer candidate_guard.deinit();
    // Composer's accepted commands are cursor-free.  The only physical
    // presentation derived from this candidate is one focused overlay, and
    // it is translated through the exact terminal placement before replay.
    const trail_candidate: ?*const CursorTrail = if (include_trail and pending == null and
        canvas_work.trail_frame_pending and
        canvas_work.trail_scratch_tab == candidate.activeTabId())
        &canvas_work.trail_scratch
    else
        null;
    const focused_source = focusedSourceForCandidate(
        canvas_work,
        &candidate,
        pending,
    ) orelse return .blocked;
    // A bootstrap source is valid before lifecycle activation, but it has no
    // cursor binding until its first accepted terminal update. The frame may
    // therefore carry the cursor-free base once; later binding admission
    // supplies the exact overlay without stranding the topology candidate.
    const accepted_cursor_overlay = try cursorOverlayForBinding(
        canvas_work,
        focused_source,
    );
    const accepted_cursor_color = if (accepted_cursor_overlay) |overlay| overlay.color else null;
    const physical_plan = try physicalPlanForBase(
        canvas_work,
        composer_plan,
        try session_chrome_adapter.toRenderPaneId(candidate.focusedPaneId()),
        trail_candidate,
    );
    trail_candidate_carried.* = trail_candidate != null;
    const slot_index = try releasedSlot(
        boundary,
        generation,
        slots,
        drm_fd,
        canvas_work.replay.acceptedSlot(),
    );
    if (!boundary.canPublishCompletion(generation))
        return error.CompletionUnavailable;
    const slot = &slots[slot_index];
    const acquire_point = next_acquire_point.*;
    const following_acquire_point = std.math.add(u64, acquire_point, 1) catch return error.RevisionOverflow;
    const release_point = std.math.add(u64, slot.release_point, 1) catch return error.RevisionOverflow;
    var release_sync_fd: i32 = -1;
    if (c.drmSyncobjExportSyncFile(drm_fd, slot.release_handle, &release_sync_fd) != 0) return error.Syncobj;
    errdefer if (release_sync_fd >= 0) closeDescriptor(release_sync_fd);
    const release_wait = try importReleaseSemaphore(device, dispatch, &release_sync_fd);
    defer vk.vkDestroySemaphore(device, release_wait, null);
    try render(
        graphics,
        device,
        queue,
        family,
        command,
        slot,
        slot.clear_color,
        physical_plan,
        canvas_work.builder.alpha_pixels,
        canvas_work.builder.rgba_pixels,
        canvas_work.residency,
        release_wait,
        dispatch,
        drm_fd,
        acquire_handle,
        acquire_point,
    );
    // The candidate bytes were used only for this synchronous recording.  Do
    // not let a cursor-bearing presentation become the next replay base.
    canvas_work.replay.restoreCandidateBase(composer_plan);
    const completion = window_render_boundary.Completion{
        .generation = generation,
        .revision = acquire_point,
        .slot = @intCast(slot_index),
        .acquire_point = acquire_point,
        .release_point = release_point,
    };
    var prepared_completion = try boundary.prepareCompletions(&.{completion});
    defer prepared_completion.deinit();
    if (pending) |value| {
        try value.commit();
        topology.* = candidate;
        if (bootstrap_publication) |*publication|
            publication.commit(canvas_work);
    }
    prepared_completion.commit();
    canvas_work.replay.commit(slot_index);
    candidate_guard.disarm();
    if (accepted_cursor_color) |color| canvas_work.accepted_cursor_color = color;
    slot.release_point = release_point;
    next_acquire_point.* = following_acquire_point;
    return .published;
}

/// Records one physical cursor replacement without touching Composer, Pool, or
/// terminal Content. The accepted replay cohort remains authoritative until
/// completion preparation commits the replacement ring candidate.
fn replayCursorFrame(
    boundary: *window_render_boundary.Boundary,
    work: *CanvasWork,
    pending: *?terminal_handoff.CursorPublication,
    focused_source: ?render_api.canvas.SourceId,
    trail_only: bool,
    slots: *[window_render_boundary.slot_count]Slot,
    generation: u64,
    graphics: *vk_surface.Context,
    device: vk.VkDevice,
    queue: vk.VkQueue,
    family: u32,
    command: vk.VkCommandBuffer,
    dispatch: *const howl_vk.dispatch.ExternalImageDispatch,
    drm_fd: i32,
    acquire_handle: u32,
    next_acquire_point: *u64,
) !CursorReplayResult {
    const publication = pending.*;
    if (!trail_only and publication == null) return .blocked;
    if (focused_source == null) return .blocked;
    if (publication) |value| {
        if (focused_source.? != value.source and !trail_only) return .rejected;
    }
    const overlay_preparation: CursorOverlayPreparation = if (trail_only)
        if (publication) |value|
            if (value.source == focused_source.?)
                try trailOverlayForPublication(work, value)
            else
                try acceptedCursorOverlay(work, focused_source.?)
        else
            try acceptedCursorOverlay(work, focused_source.?)
    else
        try publicationCursorOverlay(work, publication.?, true);
    var accepted_overlay = switch (overlay_preparation) {
        .blocked => return .blocked,
        .rejected => return .rejected,
        .prepared => |value| value,
    };
    if (trail_only) {
        const trail_clip = checkedTrailClipUnion(
            work.trail_scratch.endpoint_clip,
            accepted_overlay.clip,
        ) catch return .rejected;
        accepted_overlay.trail = .{
            .corner_x = work.trail_scratch.corner_x,
            .corner_y = work.trail_scratch.corner_y,
            .clip = trail_clip,
            .opacity = work.trail_scratch.opacity,
            .color = work.accepted_cursor_color orelse accepted_overlay.color,
            .cursor_rect = accepted_overlay.rect,
        };
    }
    // Reconcile the exact old replay role before asking the ring for any
    // candidate slot.  A different released slot must never be allowed to
    // hide an unreleased retiring cohort.
    if (!try releaseReplayRetirementIfReady(
        boundary,
        work.replay,
        generation,
        slots,
        drm_fd,
    )) return .blocked;
    const slot_index = releasedSlot(
        boundary,
        generation,
        slots,
        drm_fd,
        work.replay.acceptedSlot(),
    ) catch |failure| switch (failure) {
        error.NoReleasedSlot => return .blocked,
        else => return failure,
    };
    if (!work.replay.canCapture()) return .blocked;
    const base = work.replay.acceptedPlan();
    const candidate_cohort = work.replay.candidate();
    const preparation = try prepareCursorReplayCandidate(
        base,
        accepted_overlay,
        .{
            .vertices = candidate_cohort.vertices,
            .indices = candidate_cohort.indices,
            .commands = candidate_cohort.commands,
        },
    );
    const candidate = switch (preparation) {
        .rejected => return .rejected,
        .prepared => |value| value,
    };
    candidate_cohort.vertex_count = candidate.vertices.len;
    candidate_cohort.index_count = candidate.indices.len;
    candidate_cohort.command_count = candidate.commands.len;
    candidate_cohort.pin_count = work.replay.cohorts[work.replay.accepted].pin_count;
    @memcpy(
        candidate_cohort.pins[0..candidate_cohort.pin_count],
        work.replay.cohorts[work.replay.accepted].pins[0..candidate_cohort.pin_count],
    );
    work.replay.pending = true;
    errdefer work.replay.discard();
    if (!boundary.canPublishCompletion(generation)) return .blocked;
    const slot = &slots[slot_index];
    const acquire_point = next_acquire_point.*;
    const following_acquire_point = try std.math.add(u64, acquire_point, 1);
    const release_point = try std.math.add(u64, slot.release_point, 1);
    var release_sync_fd: i32 = -1;
    if (c.drmSyncobjExportSyncFile(drm_fd, slot.release_handle, &release_sync_fd) != 0)
        return error.Syncobj;
    errdefer if (release_sync_fd >= 0) closeDescriptor(release_sync_fd);
    const release_wait = try importReleaseSemaphore(
        device,
        dispatch,
        &release_sync_fd,
    );
    defer vk.vkDestroySemaphore(device, release_wait, null);
    // A preview-driven cursor burst can publish another target while this
    // candidate is being prepared.  Revalidate at the last point before
    // physical submission so an older target is never presented when the
    // newer one is already waiting in the Boundary inbox: transfer that
    // exact latest publication to the local pending slot and retry without a
    // terminal wake or a full Content/Pool/Composer rebuild.
    if (!trail_only and takeNewerCursorReplay(
        work.terminals,
        publication.?,
        pending,
    )) {
        work.replay.discard();
        return .retry;
    }
    render(
        graphics,
        device,
        queue,
        family,
        command,
        slot,
        slot.clear_color,
        candidate,
        work.builder.alpha_pixels,
        work.builder.rgba_pixels,
        null,
        release_wait,
        dispatch,
        drm_fd,
        acquire_handle,
        acquire_point,
    ) catch |failure| return failure;
    // Restore the canonical cursor-free bytes before the physical slot is
    // accepted.  The presented candidate remains owned by the ring slot; the
    // replay cohort stays a stable base for the next cursor-only update.
    work.replay.restoreCandidateBase(base);
    const completion = window_render_boundary.Completion{
        .generation = generation,
        .revision = acquire_point,
        .slot = @intCast(slot_index),
        .acquire_point = acquire_point,
        .release_point = release_point,
    };
    // Submission has already occurred.  A completion reservation failure is
    // therefore a non-retryable owner failure; retrying would submit the same
    // physical slot twice without a tracked completion.
    var prepared = boundary.prepareCompletions(&.{completion}) catch |failure| {
        std.debug.assert(
            classifyReplayCompletionFailure(failure) == .fatal,
        );
        return failure;
    };
    defer prepared.deinit();
    prepared.commit();
    commitCursorReplayAcceptance(
        work,
        publication,
        accepted_overlay,
        trail_only,
        slot_index,
        slot,
        release_point,
        next_acquire_point,
        following_acquire_point,
    );
    return .published;
}

/// Selects the newest target available for a trail-only replay.  An older
/// retained publication can legitimately lag a newer Composer binding after
/// hidden-pane catch-up, so the accepted binding wins in that case.
fn trailOverlayForPublication(
    work: *const CanvasWork,
    publication: terminal_handoff.CursorPublication,
) !CursorOverlayPreparation {
    const binding = work.composer.cursorBinding(publication.source) orelse
        return .blocked;
    const accepted = try acceptedCursorOverlay(work, publication.source);
    if (publication.cursor_revision < binding.cursor_revision) return accepted;
    return publicationCursorOverlay(work, publication, false);
}

fn takeNewerCursorReplay(
    terminals: *terminal_handoff.Boundary,
    publication: terminal_handoff.CursorPublication,
    pending: *?terminal_handoff.CursorPublication,
) bool {
    const newest = terminals.takeCursor(publication.pane) orelse return false;
    std.debug.assert(newest.source == publication.source);
    std.debug.assert(newest.cursor_revision > publication.cursor_revision);
    pending.* = newest;
    return true;
}

test "cursor replay supersession transfers the newest inbox target" {
    var terminals = try terminal_handoff.Boundary.init(
        std.testing.io,
        std.testing.allocator,
        .{
            .commands = 4,
            .upload_bytes = 16,
            .cells = 4,
            .rows = 4,
            .images = 1,
            .placements = 1,
            .image_bytes = 16,
            .glyphs = 4,
            .masks = 4,
            .resources_per_update = 4,
            .raster_bytes = 16,
            .decoration_bytes = 16,
        },
    );
    defer terminals.deinit();

    const pane: render_api.chrome.PaneId = @fromBackingInt(701);
    const source: render_api.canvas.SourceId = @fromBackingInt(702);
    try terminals.register(pane, source, .{ .width = 8, .height = 8 });
    try std.testing.expect(terminals.takeLifecycle() != null);
    try terminals.markLive(pane);
    terminals.visible_revision = 1;
    terminals.visible_initialized = true;
    terminals.visible_members[0] = .{ .pane = pane, .source = source };
    terminals.visible_member_count = 1;
    const identity = (try terminals.cursorPublicationIdentity(pane, source)).?;
    const target = terminal_handoff.CursorTarget{
        .row = 2,
        .col = 3,
        .visible = true,
        .shape = .block,
        .blink = false,
        .blink_fast = false,
        .cursor_color = .{},
        .text_color = .{},
    };
    const first = terminal_handoff.CursorPublication{
        .pane = pane,
        .source = source,
        .terminal_sequence = 1,
        .cursor_revision = 1,
        .visible_set_revision = identity.visible_set_revision,
        .lifecycle_revision = identity.lifecycle_revision,
        .target = target,
    };
    try terminals.publishCursor(first);
    var pending: ?terminal_handoff.CursorPublication = terminals.takeCursor(pane).?;
    var second = first;
    second.terminal_sequence = 2;
    second.cursor_revision = 2;
    second.target.col = 4;
    try terminals.publishCursor(second);

    try std.testing.expect(takeNewerCursorReplay(
        &terminals,
        first,
        &pending,
    ));
    try std.testing.expectEqual(second, pending.?);
    try std.testing.expect(terminals.takeCursor(pane) == null);
}

fn validateTerminalTopology(candidate: *const session.SessionState) !void {
    for (0..candidate.tabCount()) |tab_index| {
        for (0..candidate.paneCount(tab_index)) |pane_index| {
            const pane = candidate.paneId(tab_index, pane_index) orelse
                return error.InvalidTopology;
            const rect = candidate.paneRect(pane) orelse
                return error.InvalidTopology;
            if (rect.width == 0 or rect.height == 0)
                return error.InvalidTopology;
        }
    }
}

/// Keeps only the newest cursor publication belonging to the currently
/// focused live pane.  This is called both after terminal wakes and after an
/// accepted topology/focus transition, because focus input can commit without
/// a second PTY wake.
fn reconcileFocusedCursor(
    terminals: *terminal_handoff.Boundary,
    focused_pane: render_api.chrome.PaneId,
    pending: *?terminal_handoff.CursorPublication,
) void {
    const focused_source = terminals.sourceFor(focused_pane);
    if (focused_source == null)
        dropPendingCursor(pending)
    else if (pending.* != null and pending.*.?.source != focused_source.?)
        dropPendingCursor(pending);
    retainFocusedCursor(focused_source, pending, null);
    if (focused_source == null) return;
    if (terminals.takeCursor(focused_pane)) |publication| {
        retainFocusedCursor(focused_source, pending, publication);
    }
}

fn dropPendingCursor(pending: *?terminal_handoff.CursorPublication) void {
    pending.* = null;
}

fn retainFocusedCursor(
    focused_source: ?render_api.canvas.SourceId,
    pending: *?terminal_handoff.CursorPublication,
    newest: ?terminal_handoff.CursorPublication,
) void {
    if (pending.*) |publication| {
        if (focused_source == null or publication.source != focused_source.?)
            dropPendingCursor(pending);
    }
    if (newest) |publication| {
        if (focused_source != null and publication.source == focused_source.?) {
            if (pending.*) |old| if (!std.meta.eql(old, publication))
                dropPendingCursor(pending);
            pending.* = publication;
        }
    }
}

test "focused cursor handoff drops A and accepts B without a terminal wake" {
    const pane_a: render_api.chrome.PaneId = @fromBackingInt(11);
    const pane_b: render_api.chrome.PaneId = @fromBackingInt(12);
    const source_a: render_api.canvas.SourceId = @fromBackingInt(21);
    const source_b: render_api.canvas.SourceId = @fromBackingInt(22);
    const target = terminal_handoff.CursorTarget{
        .row = 2,
        .col = 3,
        .visible = true,
        .shape = .block,
        .blink = false,
        .blink_fast = false,
        .cursor_color = .{ .r = 1, .g = 2, .b = 3 },
        .text_color = .{ .r = 4, .g = 5, .b = 6 },
    };
    const publication_a = terminal_handoff.CursorPublication{
        .pane = pane_a,
        .source = source_a,
        .terminal_sequence = 7,
        .cursor_revision = 7,
        .visible_set_revision = 1,
        .lifecycle_revision = @fromBackingInt(1),
        .target = target,
    };
    const publication_b = terminal_handoff.CursorPublication{
        .pane = pane_b,
        .source = source_b,
        .terminal_sequence = 8,
        .cursor_revision = 8,
        .visible_set_revision = 1,
        .lifecycle_revision = @fromBackingInt(1),
        .target = target,
    };
    var pending: ?terminal_handoff.CursorPublication = publication_a;
    retainFocusedCursor(source_a, &pending, null);
    try std.testing.expectEqual(publication_a, pending.?);
    // B's inbox publication is retained while A is focused. Once the Host
    // focus transition is accepted, the same latest value is consumed without
    // requiring another terminal descriptor wake.
    retainFocusedCursor(source_b, &pending, publication_b);
    try std.testing.expectEqual(publication_b, pending.?);
}

fn releasedSlot(
    boundary: *window_render_boundary.Boundary,
    generation: u64,
    slots: *[window_render_boundary.slot_count]Slot,
    drm_fd: i32,
    excluded_slot: ?usize,
) !usize {
    const facts = boundary.releaseFacts(generation) orelse return error.NoReleasedSlot;
    var first_candidate: ?usize = null;
    for (0..window_render_boundary.slot_count) |index| {
        if (excluded_slot == index) continue;
        const presented = (facts.presented_mask & (@as(u8, 1) << @intCast(index))) != 0;
        if (!presented or facts.release_points[index] != slots[index].release_point) continue;
        if (first_candidate == null) first_candidate = index;
        if (try timelineReady(drm_fd, slots[index].release_handle, slots[index].release_point)) return index;
    }
    const index = first_candidate orelse return error.NoReleasedSlot;
    try waitTimeline(drm_fd, slots[index].release_handle, slots[index].release_point);
    return index;
}

/// Retires the old replay role only after its exact compositor release point
/// is available. Until then both fixed roles remain occupied and no candidate
/// may overwrite the old frame's command or resource-generation pins.
fn releaseReplayRetirementIfReady(
    boundary: *window_render_boundary.Boundary,
    replay: *ReplayState,
    generation: u64,
    slots: *[window_render_boundary.slot_count]Slot,
    drm_fd: i32,
) !bool {
    const retiring_slot = replay.retiring_slot orelse return true;
    const facts = boundary.releaseFacts(generation) orelse return false;
    const ready_slot = retiringSlotReady(replay, facts, slots) orelse return false;
    std.debug.assert(ready_slot == retiring_slot);
    try waitTimeline(drm_fd, slots[ready_slot].release_handle, slots[ready_slot].release_point);
    replay.releaseRetiring(ready_slot);
    return true;
}

fn retiringSlotReady(
    replay: *const ReplayState,
    facts: window_render_boundary.RetiredRing,
    slots: *const [window_render_boundary.slot_count]Slot,
) ?usize {
    const slot = replay.retiring_slot orelse return null;
    const presented = (facts.presented_mask & (@as(u8, 1) << @intCast(slot))) != 0;
    if (!presented or facts.release_points[slot] != slots[slot].release_point)
        return null;
    return slot;
}

const Physical = struct {
    device: vk.VkPhysicalDevice,
    render_major: i64,
    render_minor: i64,
};

fn selectPhysical(instance: vk.VkInstance, feedback_device: u64) !Physical {
    const feedback_major = directMajor(feedback_device) orelse return error.PhysicalDevice;
    const feedback_minor = directMinor(feedback_device) orelse return error.PhysicalDevice;
    var count: u32 = 0;
    if (vk.vkEnumeratePhysicalDevices(instance, &count, null) != vk.VK_SUCCESS or count == 0 or count > 8) return error.PhysicalDevice;
    var devices: [8]vk.VkPhysicalDevice = undefined;
    if (vk.vkEnumeratePhysicalDevices(instance, &count, &devices) != vk.VK_SUCCESS) return error.PhysicalDevice;
    for (devices[0..count]) |device| {
        var drm = std.mem.zeroes(vk.VkPhysicalDeviceDrmPropertiesEXT);
        drm.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRM_PROPERTIES_EXT;
        var properties = std.mem.zeroes(vk.VkPhysicalDeviceProperties2);
        properties.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2;
        properties.pNext = @ptrCast(&drm);
        vk.vkGetPhysicalDeviceProperties2(device, &properties);
        const render_match = drm.hasRender != 0 and drm.renderMajor == feedback_major and drm.renderMinor == feedback_minor;
        const primary_match = drm.hasPrimary != 0 and drm.primaryMajor == feedback_major and drm.primaryMinor == feedback_minor;
        if (render_match or primary_match) {
            if (drm.hasRender == 0) return error.PhysicalDevice;
            return .{ .device = device, .render_major = drm.renderMajor, .render_minor = drm.renderMinor };
        }
    }
    return error.PhysicalDevice;
}

fn openRenderNode(major: i64, minor: i64) !i32 {
    var path: [64]u8 = undefined;
    for (128..256) |index| {
        const name_bytes = std.fmt.bufPrint(path[0 .. path.len - 1], "/dev/dri/renderD{d}", .{index}) catch return error.DrmOpen;
        path[name_bytes.len] = 0;
        const name: [*:0]const u8 = @ptrCast(&path);
        var status = std.mem.zeroes(linux.Statx);
        const stat_result = linux.statx(linux.AT.FDCWD, name, 0, linux.STATX.BASIC_STATS, &status);
        if (statxDevice(stat_result, &status)) |device| {
            if (device.major != major or device.minor != minor) continue;
        } else continue;
        return mapRenderOpenResult(linux.open(name, render_open_flags, 0));
    }
    return error.DrmOpen;
}

const StatxDevice = struct { major: i64, minor: i64 };

fn statxDevice(result: usize, status: *const linux.Statx) ?StatxDevice {
    if (linux.errno(result) != .SUCCESS) return null;
    if (!status.mask.TYPE or !status.mask.MODE) return null;
    return .{
        .major = status.rdev_major,
        .minor = status.rdev_minor,
    };
}

fn directMajor(device: u64) ?u32 {
    const value = ((device & 0x0000_0000_000f_ff00) >> 8) |
        ((device & 0xffff_f000_0000_0000) >> 32);
    return std.math.cast(u32, value);
}

fn directMinor(device: u64) ?u32 {
    const value = ((device & 0x0000_0000_0000_00ff) >> 0) |
        ((device & 0x00000ffffff00000) >> 12);
    return std.math.cast(u32, value);
}

fn mapRenderOpenResult(result: usize) !i32 {
    if (linux.errno(result) != .SUCCESS) return error.DrmOpen;
    return std.math.cast(i32, result) orelse error.DrmOpen;
}

fn isRenderTimeout(result: c_int) bool {
    return result == render_etime;
}

fn requireExtensions(physical: vk.VkPhysicalDevice) !void {
    var count: u32 = 0;
    if (vk.vkEnumerateDeviceExtensionProperties(physical, null, &count, null) != vk.VK_SUCCESS or count > 512) return error.Extensions;
    var properties: [512]vk.VkExtensionProperties = undefined;
    if (vk.vkEnumerateDeviceExtensionProperties(physical, null, &count, &properties) != vk.VK_SUCCESS) return error.Extensions;
    const required = [_][]const u8{
        "VK_EXT_external_memory_dma_buf",
        "VK_EXT_image_drm_format_modifier",
        "VK_KHR_external_memory_fd",
        "VK_KHR_external_semaphore_fd",
        "VK_KHR_timeline_semaphore",
        "VK_KHR_synchronization2",
    };
    for (required) |name| {
        for (properties[0..count]) |property| {
            if (std.mem.eql(u8, std.mem.sliceTo(&property.extensionName, 0), name)) break;
        } else return error.Extensions;
    }
}

fn queryFormat(physical: vk.VkPhysicalDevice, modifier: u64) !bool {
    var modifier_info = std.mem.zeroes(vk.VkPhysicalDeviceImageDrmFormatModifierInfoEXT);
    modifier_info.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_DRM_FORMAT_MODIFIER_INFO_EXT;
    modifier_info.drmFormatModifier = modifier;
    modifier_info.sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE;
    var external_info = std.mem.zeroes(vk.VkPhysicalDeviceExternalImageFormatInfo);
    external_info.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTERNAL_IMAGE_FORMAT_INFO;
    external_info.handleType = vk.VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT;
    external_info.pNext = @ptrCast(&modifier_info);
    var info = std.mem.zeroes(vk.VkPhysicalDeviceImageFormatInfo2);
    info.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_FORMAT_INFO_2;
    info.format = vk.VK_FORMAT_R8G8B8A8_UNORM;
    info.type = vk.VK_IMAGE_TYPE_2D;
    info.tiling = vk.VK_IMAGE_TILING_DRM_FORMAT_MODIFIER_EXT;
    info.usage = vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    info.pNext = @ptrCast(&external_info);
    var external = std.mem.zeroes(vk.VkExternalImageFormatProperties);
    external.sType = vk.VK_STRUCTURE_TYPE_EXTERNAL_IMAGE_FORMAT_PROPERTIES;
    var properties = std.mem.zeroes(vk.VkImageFormatProperties2);
    properties.sType = vk.VK_STRUCTURE_TYPE_IMAGE_FORMAT_PROPERTIES_2;
    properties.pNext = @ptrCast(&external);
    if (vk.vkGetPhysicalDeviceImageFormatProperties2(physical, &info, &properties) != vk.VK_SUCCESS) return error.ImageFormat;
    const value = external.externalMemoryProperties;
    if ((value.externalMemoryFeatures & vk.VK_EXTERNAL_MEMORY_FEATURE_EXPORTABLE_BIT) == 0 or (value.compatibleHandleTypes & vk.VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT) == 0) return error.ImageFormat;
    return (value.externalMemoryFeatures & vk.VK_EXTERNAL_MEMORY_FEATURE_DEDICATED_ONLY_BIT) != 0;
}

fn graphicsFamily(physical: vk.VkPhysicalDevice) !u32 {
    var count: u32 = 0;
    vk.vkGetPhysicalDeviceQueueFamilyProperties(physical, &count, null);
    if (count == 0 or count > 32) return error.Queue;
    var properties: [32]vk.VkQueueFamilyProperties = undefined;
    vk.vkGetPhysicalDeviceQueueFamilyProperties(physical, &count, &properties);
    for (properties[0..count], 0..) |property, index| {
        if ((property.queueFlags & vk.VK_QUEUE_GRAPHICS_BIT) != 0) return @intCast(index);
    }
    return error.Queue;
}

fn modifierPlaneCount(physical: vk.VkPhysicalDevice, modifier: u64) !u8 {
    var list = std.mem.zeroes(vk.VkDrmFormatModifierPropertiesListEXT);
    list.sType = vk.VK_STRUCTURE_TYPE_DRM_FORMAT_MODIFIER_PROPERTIES_LIST_EXT;
    var properties = std.mem.zeroes(vk.VkFormatProperties2);
    properties.sType = vk.VK_STRUCTURE_TYPE_FORMAT_PROPERTIES_2;
    properties.pNext = @ptrCast(&list);
    vk.vkGetPhysicalDeviceFormatProperties2(physical, vk.VK_FORMAT_R8G8B8A8_UNORM, &properties);
    if (list.drmFormatModifierCount == 0 or list.drmFormatModifierCount > 64) return error.Modifier;
    var values: [64]vk.VkDrmFormatModifierPropertiesEXT = undefined;
    list.pDrmFormatModifierProperties = &values;
    vk.vkGetPhysicalDeviceFormatProperties2(physical, vk.VK_FORMAT_R8G8B8A8_UNORM, &properties);
    for (values[0..list.drmFormatModifierCount]) |value| {
        if (value.drmFormatModifier == modifier and value.drmFormatModifierPlaneCount > 0 and value.drmFormatModifierPlaneCount <= window_render_boundary.plane_limit) return @intCast(value.drmFormatModifierPlaneCount);
    }
    return error.Modifier;
}

fn constructSlot(slot: *Slot, graphics: *const vk_surface.Context, device: vk.VkDevice, memory_properties: vk.VkPhysicalDeviceMemoryProperties, modifier: u64, dedicated_only: bool, plane_count: u8, surface: window_render_boundary.SurfaceConfig, dispatch: *const howl_vk.dispatch.ExternalImageDispatch, drm_fd: i32, offer: *window_render_boundary.SlotOffer, offered_fds: *OfferedFds, gpu_bytes: *u64) !void {
    slot.width = surface.physical_width;
    slot.height = surface.physical_height;
    slot.coordinate_width = surface.logical_width;
    slot.coordinate_height = surface.logical_height;
    var selected_modifier = modifier;
    var modifier_list = std.mem.zeroes(vk.VkImageDrmFormatModifierListCreateInfoEXT);
    modifier_list.sType = vk.VK_STRUCTURE_TYPE_IMAGE_DRM_FORMAT_MODIFIER_LIST_CREATE_INFO_EXT;
    modifier_list.drmFormatModifierCount = 1;
    modifier_list.pDrmFormatModifiers = &selected_modifier;
    var external = std.mem.zeroes(vk.VkExternalMemoryImageCreateInfo);
    external.sType = vk.VK_STRUCTURE_TYPE_EXTERNAL_MEMORY_IMAGE_CREATE_INFO;
    external.handleTypes = vk.VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT;
    external.pNext = @ptrCast(&modifier_list);
    var info = std.mem.zeroes(vk.VkImageCreateInfo);
    info.sType = vk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    info.pNext = @ptrCast(&external);
    info.imageType = vk.VK_IMAGE_TYPE_2D;
    info.format = vk.VK_FORMAT_R8G8B8A8_UNORM;
    info.extent = .{ .width = surface.physical_width, .height = surface.physical_height, .depth = 1 };
    info.mipLevels = 1;
    info.arrayLayers = 1;
    info.samples = vk.VK_SAMPLE_COUNT_1_BIT;
    info.tiling = vk.VK_IMAGE_TILING_DRM_FORMAT_MODIFIER_EXT;
    info.usage = vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    info.sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE;
    info.initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED;
    if (vk.vkCreateImage(device, &info, null, &slot.image) != vk.VK_SUCCESS) return error.Image;
    var requirements: vk.VkMemoryRequirements = undefined;
    vk.vkGetImageMemoryRequirements(device, slot.image, &requirements);
    const owned_bytes = requirements.size;
    const total_bytes = std.math.add(u64, gpu_bytes.*, owned_bytes) catch return error.GpuMemoryLimit;
    if (total_bytes > gpu_memory_limit) return error.GpuMemoryLimit;
    var memory_type: ?u32 = null;
    for (0..memory_properties.memoryTypeCount) |index| {
        if ((requirements.memoryTypeBits & (@as(u32, 1) << @intCast(index))) != 0 and (memory_properties.memoryTypes[index].propertyFlags & vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) != 0) {
            memory_type = @intCast(index);
            break;
        }
    }
    var export_info = std.mem.zeroes(vk.VkExportMemoryAllocateInfo);
    export_info.sType = vk.VK_STRUCTURE_TYPE_EXPORT_MEMORY_ALLOCATE_INFO;
    export_info.handleTypes = vk.VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT;
    var dedicated = std.mem.zeroes(vk.VkMemoryDedicatedAllocateInfo);
    dedicated.sType = vk.VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO;
    dedicated.image = slot.image;
    export_info.pNext = if (dedicated_only) @ptrCast(&dedicated) else null;
    var allocation = std.mem.zeroes(vk.VkMemoryAllocateInfo);
    allocation.sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    allocation.pNext = @ptrCast(&export_info);
    allocation.allocationSize = requirements.size;
    allocation.memoryTypeIndex = memory_type orelse return error.Memory;
    if (vk.vkAllocateMemory(device, &allocation, null, &slot.memory) != vk.VK_SUCCESS) return error.Memory;
    if (vk.vkBindImageMemory(device, slot.image, slot.memory, 0) != vk.VK_SUCCESS) return error.Memory;
    slot.attachment = try graphics.createAttachment(device, slot.image, surface.physical_width, surface.physical_height);
    slot.owned_bytes = owned_bytes;
    gpu_bytes.* += owned_bytes;
    var actual = std.mem.zeroes(vk.VkImageDrmFormatModifierPropertiesEXT);
    actual.sType = vk.VK_STRUCTURE_TYPE_IMAGE_DRM_FORMAT_MODIFIER_PROPERTIES_EXT;
    if (dispatch.get_modifier(device, slot.image, &actual) != vk.VK_SUCCESS or actual.drmFormatModifier != modifier) return error.Modifier;
    const aspects = [_]vk.VkImageAspectFlags{ vk.VK_IMAGE_ASPECT_MEMORY_PLANE_0_BIT_EXT, vk.VK_IMAGE_ASPECT_MEMORY_PLANE_1_BIT_EXT, vk.VK_IMAGE_ASPECT_MEMORY_PLANE_2_BIT_EXT, vk.VK_IMAGE_ASPECT_MEMORY_PLANE_3_BIT_EXT };
    slot.plane_count = plane_count;
    for (0..plane_count) |plane| {
        const subresource = vk.VkImageSubresource{ .aspectMask = aspects[plane], .mipLevel = 0, .arrayLayer = 0 };
        var layout: vk.VkSubresourceLayout = undefined;
        vk.vkGetImageSubresourceLayout(device, slot.image, &subresource, &layout);
        if (layout.offset > std.math.maxInt(u32) or layout.rowPitch > std.math.maxInt(u32)) return error.Plane;
        slot.planes[plane] = .{ .offset = @intCast(layout.offset), .stride = @intCast(layout.rowPitch) };
    }
    var fd_info = std.mem.zeroes(vk.VkMemoryGetFdInfoKHR);
    fd_info.sType = vk.VK_STRUCTURE_TYPE_MEMORY_GET_FD_INFO_KHR;
    fd_info.memory = slot.memory;
    fd_info.handleType = vk.VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT;
    if (dispatch.get_memory_fd(device, &fd_info, &offered_fds.dma) != vk.VK_SUCCESS or offered_fds.dma < 0) return error.DmaBuf;
    if (c.drmSyncobjCreate(drm_fd, 0, &slot.release_handle) != 0) return error.Syncobj;
    if (c.drmSyncobjHandleToFD(drm_fd, slot.release_handle, &offered_fds.timeline) != 0) return error.Syncobj;
    offer.* = .{ .generation = surface.generation, .width = surface.physical_width, .height = surface.physical_height, .dma_fd = offered_fds.dma, .acquire_timeline_fd = -1, .release_timeline_fd = offered_fds.timeline, .plane_count = plane_count, .planes = slot.planes };
}

fn render(graphics: *vk_surface.Context, device: vk.VkDevice, queue: vk.VkQueue, family: u32, command: vk.VkCommandBuffer, slot: *Slot, color: [4]f32, surface_plan: vk_surface.Plan, alpha_pixels: []const u8, rgba_pixels: []const u8, residency_commit: ?*vk_surface.ResidencyStore, wait_semaphore: ?vk.VkSemaphore, dispatch: *const howl_vk.dispatch.ExternalImageDispatch, drm_fd: i32, acquire_handle: u32, acquire_point: u64) !void {
    errdefer if (residency_commit) |store| store.discard();
    try graphics.stage(
        surface_plan,
        alpha_pixels,
        rgba_pixels,
        slot.coordinate_width,
        slot.coordinate_height,
    );
    if (vk.vkResetCommandBuffer(command, 0) != vk.VK_SUCCESS) return error.Command;
    var begin = std.mem.zeroes(vk.VkCommandBufferBeginInfo);
    begin.sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    if (vk.vkBeginCommandBuffer(command, &begin) != vk.VK_SUCCESS) return error.Command;
    const range = vk.VkImageSubresourceRange{ .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, .baseMipLevel = 0, .levelCount = 1, .baseArrayLayer = 0, .layerCount = 1 };
    var barrier = vk.VkImageMemoryBarrier{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .pNext = null,
        .srcAccessMask = 0,
        .dstAccessMask = vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        .oldLayout = if (slot.external) vk.VK_IMAGE_LAYOUT_GENERAL else vk.VK_IMAGE_LAYOUT_UNDEFINED,
        .newLayout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .srcQueueFamilyIndex = if (slot.external) vk.VK_QUEUE_FAMILY_EXTERNAL else vk.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = if (slot.external) family else vk.VK_QUEUE_FAMILY_IGNORED,
        .image = slot.image,
        .subresourceRange = range,
    };
    vk.vkCmdPipelineBarrier(command, vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, 0, 0, null, 0, null, 1, &barrier);
    const recording = try graphics.record(
        command,
        slot.attachment,
        slot.width,
        slot.height,
        slot.coordinate_width,
        slot.coordinate_height,
        surface_plan,
        color,
    );
    barrier.srcAccessMask = vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
    barrier.dstAccessMask = 0;
    barrier.oldLayout = vk.VK_IMAGE_LAYOUT_GENERAL;
    barrier.newLayout = vk.VK_IMAGE_LAYOUT_GENERAL;
    barrier.srcQueueFamilyIndex = family;
    barrier.dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_EXTERNAL;
    vk.vkCmdPipelineBarrier(command, vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, vk.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0, 0, null, 0, null, 1, &barrier);
    if (vk.vkEndCommandBuffer(command) != vk.VK_SUCCESS) return error.Command;
    var export_info = std.mem.zeroes(vk.VkExportSemaphoreCreateInfo);
    export_info.sType = vk.VK_STRUCTURE_TYPE_EXPORT_SEMAPHORE_CREATE_INFO;
    export_info.handleTypes = vk.VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_SYNC_FD_BIT;
    var semaphore_info = std.mem.zeroes(vk.VkSemaphoreCreateInfo);
    semaphore_info.sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
    semaphore_info.pNext = @ptrCast(&export_info);
    var completion: vk.VkSemaphore = undefined;
    if (vk.vkCreateSemaphore(device, &semaphore_info, null, &completion) != vk.VK_SUCCESS) return error.Semaphore;
    defer vk.vkDestroySemaphore(device, completion, null);
    const wait_stage: vk.VkPipelineStageFlags = vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    var submit = std.mem.zeroes(vk.VkSubmitInfo);
    submit.sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO;
    if (wait_semaphore) |wait| {
        submit.waitSemaphoreCount = 1;
        submit.pWaitSemaphores = &wait;
        submit.pWaitDstStageMask = &wait_stage;
    }
    submit.commandBufferCount = 1;
    submit.pCommandBuffers = &command;
    submit.signalSemaphoreCount = 1;
    submit.pSignalSemaphores = &completion;
    if (vk.vkQueueSubmit(queue, 1, &submit, null) != vk.VK_SUCCESS) return error.Submit;
    var fd_info = std.mem.zeroes(vk.VkSemaphoreGetFdInfoKHR);
    fd_info.sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_GET_FD_INFO_KHR;
    fd_info.semaphore = completion;
    fd_info.handleType = vk.VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_SYNC_FD_BIT;
    var sync_fd: i32 = -1;
    if (dispatch.get_semaphore_fd(device, &fd_info, &sync_fd) != vk.VK_SUCCESS or sync_fd < 0) return error.Semaphore;
    defer closeDescriptor(sync_fd);
    var temporary: u32 = 0;
    if (c.drmSyncobjCreate(drm_fd, 0, &temporary) != 0) return error.Syncobj;
    defer destroySyncobj(drm_fd, temporary);
    if (c.drmSyncobjImportSyncFile(drm_fd, temporary, sync_fd) != 0) return error.Syncobj;
    var handles = [_]u32{temporary};
    if (c.drmSyncobjWait(drm_fd, &handles, 1, try deadline(), 0, null) != 0) return error.RenderTimeout;
    graphics.complete(recording);
    if (residency_commit) |store| try store.complete();
    if (c.drmSyncobjTransfer(drm_fd, acquire_handle, acquire_point, temporary, 0, 0) != 0) return error.Syncobj;
    try waitTimeline(drm_fd, acquire_handle, acquire_point);
    slot.external = true;
    slot.clear_color = color;
}

fn waitTimeline(drm_fd: i32, handle: u32, point: u64) !void {
    var handles = [_]u32{handle};
    var points = [_]u64{point};
    const flags = c.DRM_SYNCOBJ_WAIT_FLAGS_WAIT_FOR_SUBMIT | c.DRM_SYNCOBJ_WAIT_FLAGS_WAIT_AVAILABLE;
    if (c.drmSyncobjTimelineWait(drm_fd, &handles, &points, 1, try deadline(), flags, null) != 0) return error.ReleaseAvailability;
    if (c.drmSyncobjTimelineWait(drm_fd, &handles, &points, 1, try deadline(), 0, null) != 0) return error.ReleaseCompletion;
}

fn timelineReady(drm_fd: i32, handle: u32, point: u64) !bool {
    var handles = [_]u32{handle};
    var points = [_]u64{point};
    const timeout = std.math.cast(i64, try monotonicNow()) orelse return error.Clock;
    const flags = c.DRM_SYNCOBJ_WAIT_FLAGS_WAIT_FOR_SUBMIT | c.DRM_SYNCOBJ_WAIT_FLAGS_WAIT_AVAILABLE;
    const available = c.drmSyncobjTimelineWait(drm_fd, &handles, &points, 1, timeout, flags, null);
    if (isRenderTimeout(available)) return false;
    if (available != 0) return error.ReleaseAvailability;
    const complete = c.drmSyncobjTimelineWait(drm_fd, &handles, &points, 1, timeout, 0, null);
    if (isRenderTimeout(complete)) return false;
    if (complete != 0) return error.ReleaseCompletion;
    return true;
}

fn importReleaseSemaphore(device: vk.VkDevice, dispatch: *const howl_vk.dispatch.ExternalImageDispatch, sync_fd: *i32) !vk.VkSemaphore {
    var export_info = std.mem.zeroes(vk.VkExportSemaphoreCreateInfo);
    export_info.sType = vk.VK_STRUCTURE_TYPE_EXPORT_SEMAPHORE_CREATE_INFO;
    export_info.handleTypes = vk.VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_SYNC_FD_BIT;
    var create_info = std.mem.zeroes(vk.VkSemaphoreCreateInfo);
    create_info.sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
    create_info.pNext = @ptrCast(&export_info);
    var semaphore: vk.VkSemaphore = undefined;
    if (vk.vkCreateSemaphore(device, &create_info, null, &semaphore) != vk.VK_SUCCESS) return error.Semaphore;
    errdefer vk.vkDestroySemaphore(device, semaphore, null);
    var import_info = std.mem.zeroes(vk.VkImportSemaphoreFdInfoKHR);
    import_info.sType = vk.VK_STRUCTURE_TYPE_IMPORT_SEMAPHORE_FD_INFO_KHR;
    import_info.semaphore = semaphore;
    import_info.handleType = vk.VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_SYNC_FD_BIT;
    import_info.fd = sync_fd.*;
    if (dispatch.import_semaphore_fd(device, &import_info) != vk.VK_SUCCESS) return error.Semaphore;
    sync_fd.* = -1;
    return semaphore;
}

fn deadline() !i64 {
    return deadlineFromMonotonic(try monotonicNow());
}

fn deadlineFromMonotonic(now: u64) !i64 {
    const absolute = std.math.add(u64, now, 2_000_000_000) catch
        return error.Clock;
    return std.math.cast(i64, absolute) orelse return error.Clock;
}

fn monotonicNow() !u64 {
    var now: std.posix.timespec = undefined;
    return mapMonotonicResult(linux.clock_gettime(std.posix.CLOCK.MONOTONIC, &now), &now);
}

fn mapMonotonicResult(result: usize, timestamp: *const std.posix.timespec) !u64 {
    if (linux.errno(result) != .SUCCESS) return error.Clock;
    return monotonicTimestamp(timestamp.sec, timestamp.nsec);
}

fn monotonicTimestamp(seconds: i64, nanoseconds: i64) !u64 {
    const seconds_u64 = std.math.cast(u64, seconds) orelse return error.Clock;
    const nanoseconds_u64 = std.math.cast(u64, nanoseconds) orelse return error.Clock;
    if (nanoseconds_u64 >= 1_000_000_000) return error.Clock;
    const whole = std.math.mul(u64, seconds_u64, 1_000_000_000) catch return error.Clock;
    return std.math.add(u64, whole, nanoseconds_u64) catch return error.Clock;
}

fn closeSucceeded(result: usize) bool {
    return linux.errno(result) == .SUCCESS;
}

fn closeDescriptor(descriptor: i32) void {
    if (!closeSucceeded(linux.close(descriptor))) @panic("Render descriptor cleanup failed");
}

fn destroySyncobj(drm_fd: i32, handle: u32) void {
    if (c.drmSyncobjDestroy(drm_fd, handle) != 0) @panic("Render syncobj cleanup failed");
}

test "renderer fd and monotonic boundary receipts" {
    try std.testing.expect(render_open_flags.ACCMODE == .RDWR);
    try std.testing.expect(render_open_flags.CLOEXEC);
    const flags_bits: u32 = @bitCast(render_open_flags);
    try std.testing.expectEqual(@as(u32, 0x0008_0002), flags_bits);
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(std.posix.timespec));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(std.posix.timespec));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(std.posix.timespec, "sec"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(std.posix.timespec, "nsec"));

    try std.testing.expectEqual(@as(i32, 7), try mapRenderOpenResult(7));
    try std.testing.expectError(error.DrmOpen, mapRenderOpenResult(std.math.maxInt(i32) + 1));
    try std.testing.expectError(error.DrmOpen, mapRenderOpenResult(std.math.maxInt(usize)));

    try std.testing.expect(isRenderTimeout(render_etime));
    try std.testing.expect(!isRenderTimeout(0));
    try std.testing.expect(!isRenderTimeout(render_etime + 1));

    try std.testing.expectEqual(@as(u64, 1_500_000_000), try monotonicTimestamp(1, 500_000_000));
    try std.testing.expectEqual(@as(u64, 999_999_999), try monotonicTimestamp(0, 999_999_999));
    const valid_timestamp = std.posix.timespec{ .sec = 1, .nsec = 500_000_000 };
    try std.testing.expectEqual(@as(u64, 1_500_000_000), try mapMonotonicResult(0, &valid_timestamp));
    try std.testing.expectError(error.Clock, mapMonotonicResult(std.math.maxInt(usize), &valid_timestamp));
    try std.testing.expectError(error.Clock, monotonicTimestamp(-1, 0));
    try std.testing.expectError(error.Clock, monotonicTimestamp(0, 1_000_000_000));
    try std.testing.expectError(error.Clock, monotonicTimestamp(std.math.maxInt(i64), 0));

    const ordinary_now: u64 = 7_654_321_000;
    const expected_deadline: i64 = 9_654_321_000;
    const ordinary_deadline = try deadlineFromMonotonic(ordinary_now);
    try std.testing.expectEqualSlices(
        u8,
        std.mem.asBytes(&expected_deadline),
        std.mem.asBytes(&ordinary_deadline),
    );
    const last_representable_now: u64 = @intCast(std.math.maxInt(i64) - 2_000_000_000);
    try std.testing.expectEqual(
        std.math.maxInt(i64),
        try deadlineFromMonotonic(last_representable_now),
    );
    try std.testing.expectError(
        error.Clock,
        deadlineFromMonotonic(last_representable_now + 1),
    );
    try std.testing.expectError(
        error.Clock,
        deadlineFromMonotonic(std.math.maxInt(u64)),
    );

    try std.testing.expect(closeSucceeded(0));
    try std.testing.expect(!closeSucceeded(std.math.maxInt(usize)));
}

test "renderer translated boundary census is migrated while DRM remains" {
    const source = @embedFile("renderer.zig");
    inline for (.{
        "CLOCK_MONOTONIC", "ETIME",       "O_CLOEXEC", "O_RDWR", "clock_gettime", "close", "open", "timespec",
        "stat",            "struct_stat", "major",     "minor",
    }) |name| {
        var token: [64]u8 = undefined;
        const rendered = try std.fmt.bufPrint(&token, "c.{s}", .{name});
        try std.testing.expect(std.mem.indexOf(u8, source, rendered) == null);
    }
}

test "renderer statx and device extraction receipts" {
    var status = std.mem.zeroes(linux.Statx);
    status.mask = .{ .TYPE = true, .MODE = true };
    status.rdev_major = 0x1ffff;
    status.rdev_minor = 0x1fffff;
    const device = statxDevice(0, &status).?;
    try std.testing.expectEqual(@as(i64, 0x1ffff), device.major);
    try std.testing.expectEqual(@as(i64, 0x1fffff), device.minor);
    status.mask = .{};
    try std.testing.expect(statxDevice(0, &status) == null);
    status.mask = .{ .TYPE = true };
    try std.testing.expect(statxDevice(0, &status) == null);
    status.mask = .{ .MODE = true };
    try std.testing.expect(statxDevice(0, &status) == null);
    status.mask = .{ .TYPE = true, .MODE = true };
    try std.testing.expect(statxDevice(std.math.maxInt(usize), &status) == null);

    try std.testing.expectEqual(@as(u32, 0), directMajor(0).?);
    try std.testing.expectEqual(@as(u32, 0), directMinor(0).?);
    try std.testing.expectEqual(@as(u32, 0), directMajor(0xff).?);
    try std.testing.expectEqual(@as(u32, 0xff), directMinor(0xff).?);
    try std.testing.expectEqual(@as(u32, 0xfff), directMajor(0x0000_0000_000f_ff00).?);
    try std.testing.expectEqual(@as(u32, 0xffff_f000), directMajor(0xffff_f000_0000_0000).?);
    try std.testing.expectEqual(@as(u32, 0xffff_ffff), directMajor(std.math.maxInt(u64)).?);
    try std.testing.expectEqual(@as(u32, 0xffff_ffff), directMinor(std.math.maxInt(u64)).?);
    try std.testing.expectEqual(@as(u32, 0xffffff00), directMinor(0x00000ffffff00000).?);
}
