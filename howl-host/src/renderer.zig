//! Exclusively owns Vulkan mutation and DRM release observation.

const std = @import("std");
const c = @import("renderer_c");
const shared = @import("shared.zig");

const terminal_retained_resource_limit: usize = 512 + 128 + 8;
const chrome_retained_resource_limit: usize = 512;
const frame_resource_limit: usize = 2048;
const frame_command_limit: usize = 32_768;
const howl_vk = @import("howl_vk");
const vk = howl_vk.abi;
const render_api = @import("howl_render");
const chrome_state = @import("chrome_state");
const vk_surface = howl_vk.surface;
const replay_command_limit: usize = vk_surface.max_commands;
const replay_pin_limit: usize = 2_048;
const input_actions = @import("input_actions");
const terminal_handoff = @import("terminal_handoff");
const dev_config = @import("dev_config");
const chrome_appearance = chrome_state.Appearance{
    .style = .{
        .foreground = .{ .r = 230, .g = 235, .b = 245, .a = 255 },
        .background = .{ .r = 20, .g = 24, .b = 32, .a = 255 },
        .border = .{ .r = 80, .g = 90, .b = 110, .a = 255 },
    },
    .tab_active_background = .{ .r = 48, .g = 72, .b = 112, .a = 255 },
    .tab_inactive_background = .{ .r = 28, .g = 34, .b = 46, .a = 255 },
};

const gpu_memory_limit: u64 = 512 * 1024 * 1024;
const configured_terminal_base_points: f64 = 16.0;

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

const CanvasPlanResult = union(enum) {
    blocked,
    retry,
    accepted: vk_surface.Plan,
};

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
            cohort.* = .{
                .vertices = try allocator.alloc(vk_surface.Vertex, replay_command_limit * 4),
                .indices = try allocator.alloc(u32, replay_command_limit * 6),
                .commands = try allocator.alloc(vk_surface.Command, replay_command_limit),
                .pins = try allocator.alloc(vk_surface.ResourceGeneration, replay_pin_limit),
            };
            initialized += 1;
        }
        return .{ .allocator = allocator, .cohorts = cohorts };
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
    const release_facts = shared.RetiredRing{
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
    /// Startup-retained presentation view; animation and geometry application
    /// remain unchanged until their dedicated cursor checkpoints.
    cursor_policy: dev_config.CursorPresentationPolicy,
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

const Slot = struct {
    width: u32 = 0,
    height: u32 = 0,
    coordinate_width: u32 = 0,
    coordinate_height: u32 = 0,
    image: vk.VkImage = null,
    memory: vk.VkDeviceMemory = null,
    release_handle: u32 = 0,
    plane_count: u8 = 0,
    planes: [shared.plane_limit]shared.Plane = undefined,
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
    boundary: *shared.Boundary,
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
    boundary: *shared.Boundary,
    terminals: *terminal_handoff.Boundary,
    allocator: std.mem.Allocator,
    font_path: []const u8,
    cursor_policy: dev_config.CursorPresentationPolicy,
) !void {
    const feedback = try waitFeedback(boundary);
    const initial_surface = try waitConfigure(boundary);
    try checkGpuBudget(initial_surface.physical_width, initial_surface.physical_height);
    var chrome = try chrome_state.Topology.init(renderExtent(initial_surface), chrome_state.default_tab_bar_height);
    var composer = try render_api.canvas.Composer.init(allocator, .{
        .sources = chrome_state.max_live_panes + 1,
        .retained_resources = frame_resource_limit,
        .retained_commands = frame_command_limit,
        .retained_pixel_bytes = 16 * 1024 * 1024,
        .composition_sources = chrome_state.max_live_panes + 1,
        .candidate_resources = 1024,
        .candidate_commands = frame_command_limit,
        .candidate_pixel_bytes = 4 * 1024 * 1024,
    });
    defer composer.deinit();
    const chrome_source = try composer.registerSource();
    var chrome_content = try render_api.chrome.Content.init(allocator, .{
        .primitives = 256,
        .text_bytes = (chrome_state.max_tabs + chrome_state.max_panes_per_tab) * chrome_state.max_label_bytes,
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
    try retainTerminalScale(
        canvas_work.terminals,
        canvas_work.terminal_font_policy,
        &canvas_work.terminal_scale,
        &canvas_work.font_request_high_water,
        initial_surface,
    );
    var chrome_primitives: [256]render_api.chrome.Primitive = undefined;
    var chrome_text: [(chrome_state.max_tabs + chrome_state.max_panes_per_tab) * chrome_state.max_label_bytes]u8 = undefined;
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
    var rings = [_][shared.slot_count]Slot{
        .{ .{}, .{}, .{} },
        .{ .{}, .{}, .{} },
    };
    defer {
        var ring_index = rings.len;
        while (ring_index > 0) {
            ring_index -= 1;
            var index = shared.slot_count;
            while (index > 0) {
                index -= 1;
                rings[ring_index][index].deinit(device, drm_fd, &gpu_bytes);
            }
        }
    }
    var offers: [shared.slot_count]shared.SlotOffer = undefined;
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
    replay.commit(shared.slot_count - 1);

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
            try retainTerminalScale(
                canvas_work.terminals,
                canvas_work.terminal_font_policy,
                &canvas_work.terminal_scale,
                &canvas_work.font_request_high_water,
                surface,
            );
            if (!terminal_topology_committed) {
                var candidate_chrome = chrome;
                candidate_chrome.resizeSurface(renderExtent(surface)) catch |failure| switch (failure) {
                    error.InvalidGeometry => continue,
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
                continue;
            }
            const pending_generation = if (pending_topology) |pending|
                if (pending.surface) |value| value.generation else active_generation
            else
                active_generation;
            if (surface.generation <= pending_generation) continue;
            var candidate_chrome = if (pending_topology) |pending|
                pending.candidate
            else
                chrome;
            candidate_chrome.resizeSurface(renderExtent(surface)) catch |failure| switch (failure) {
                error.InvalidGeometry => continue,
                else => return failure,
            };
            replacePendingTopology(
                &canvas_work,
                &chrome,
                candidate_chrome,
                &pending_topology,
                surface,
            ) catch continue;
        }
        if (terminal_topology_committed)
            try drainInput(
                boundary,
                &actions,
                &canvas_work,
                &chrome,
                chrome_appearance,
                &pending_topology,
            );
        const local_redraw_retry_turn = local_redraw_retry_pending;
        local_redraw_retry_pending = false;
        if (!local_redraw_retry_turn) {
            const terminal_woke = try waitRenderWakeBlocking(boundary, terminals);
            if (terminal_woke) {
                terminal_redraw_pending = terminals.hasReadyUpdates() or
                    terminal_redraw_pending;
                reconcileFocusedCursor(
                    terminals,
                    chrome.focusedPaneId(),
                    &cursor_replay_pending,
                );
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
                            try prepareBootstrapPublication(
                                &canvas_work,
                                &admitted.candidate,
                                admitted.bootstrap(),
                            )
                        else
                            null;
                    defer if (bootstrap_publication) |*publication|
                        publication.deinit();
                    var local_retry_used = false;
                    const admission_result = retry: while (true) {
                        const result = try buildCanvasPlan(
                            &canvas_work,
                            &admitted.candidate,
                            admitted.revision,
                            admitted.bootstrap(),
                            chrome_appearance,
                            &chrome_primitives,
                            &chrome_text,
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
                    var replacement_offers: [shared.slot_count]shared.SlotOffer = undefined;
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
                    var completion_batch: [shared.slot_count]shared.Completion = undefined;
                    var candidate_acquire = next_acquire_point;
                    const resized_plan = try buildAcceptedCanvasPlan(&canvas_work);
                    errdefer surface_residency.discard();
                    errdefer replay.discard();
                    const physical_resized_plan = try physicalPlanForBase(
                        &canvas_work,
                        resized_plan,
                        admitted.candidate.focusedPaneId(),
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
                    chrome = admitted.candidate;
                    terminal_topology_committed = true;
                    if (bootstrap_publication) |*publication|
                        publication.commit(&canvas_work);
                    prepared_completions.commit();
                    replay.commit(shared.slot_count - 1);
                    for (&rings[replacement]) |*slot| slot.release_point = 1;
                    next_acquire_point = candidate_acquire;
                    const old_ring = active_ring;
                    const old_generation = active_generation;
                    pending_topology = null;
                    active_ring = replacement;
                    active_generation = surface.generation;
                    reconcileFocusedCursor(
                        terminals,
                        chrome.focusedPaneId(),
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
                    );
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
                            pending_topology = null;
                            dropPendingCursor(&cursor_replay_pending);
                            reconcileFocusedCursor(
                                terminals,
                                chrome.focusedPaneId(),
                                &cursor_replay_pending,
                            );
                        },
                    }
                }
            }
        }
        if (cursor_replay_pending != null and
            !terminal_redraw_pending and pending_topology == null and
            terminal_topology_committed)
        {
            const focused_pane = chrome.focusedPaneId();
            const focused_source = canvas_work.terminals.sourceFor(focused_pane);
            const replay_result = try replayCursorFrame(
                boundary,
                &canvas_work,
                &cursor_replay_pending,
                focused_source,
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
                .published => dropPendingCursor(&cursor_replay_pending),
                .retry => local_redraw_retry_pending = true,
                .blocked => {},
            }
        }
        if (terminal_redraw_pending and pending_topology == null) {
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
    const bytes = std.math.mul(u64, pixels, 4 * shared.slot_count * 2) catch return error.GpuMemoryLimit;
    if (bytes > gpu_memory_limit) return error.GpuMemoryLimit;
}

fn renderExtent(surface: shared.SurfaceConfig) render_api.canvas.Size {
    return .{
        .width = @intCast(surface.logical_width),
        .height = @intCast(surface.logical_height),
    };
}

fn retainTerminalScale(
    terminals: *terminal_handoff.Boundary,
    policy: terminal_handoff.FontPolicy,
    retained: *?terminal_handoff.ScaleSnapshot,
    request_high_water: *u64,
    surface: shared.SurfaceConfig,
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

fn terminalScaleSnapshot(
    surface: shared.SurfaceConfig,
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
    topology: *const chrome_state.Topology,
) void {
    var next = policy.*;
    var retained: u8 = 0;
    for (policy.offsets[0..policy.count]) |offset| {
        if (!topologyContains(topology, offset.pane)) continue;
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
    topology: *const chrome_state.Topology,
    action: input_actions.Action,
) !void {
    var candidate = policy.*;
    pruneFontPolicy(&candidate, topology);
    const pane = topology.focusedPaneId();
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
    topology: *const chrome_state.Topology,
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
    const integer = shared.SurfaceConfig{
        .generation = 1,
        .logical_width = 100,
        .logical_height = 80,
        .physical_width = 200,
        .physical_height = 160,
        .scale_revision = 1,
        .buffer_scale = 2,
        .use_viewport = false,
    };
    const fractional = shared.SurfaceConfig{
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
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(shared.ExactRational));
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(shared.SurfaceConfig));
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
    const provisional = shared.SurfaceConfig{
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
    var topology = try chrome_state.Topology.init(
        .{ .width = 100, .height = 80 },
        chrome_state.default_tab_bar_height,
    );
    const pane = topology.focusedPaneId();
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
    try std.testing.expectEqual(@as(f64, 2.0), policyOffset(&newest.policy, pane));
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
    var topology = try chrome_state.Topology.init(
        .{ .width = 640, .height = 480 },
        chrome_state.default_tab_bar_height,
    );
    const first_tab = topology.tabId(0).?;
    const first = topology.focusedPaneId();
    const closed = try topology.split(first, .horizontal);
    try topology.closePane(closed);
    const hidden_tab = try topology.createTab("hidden");
    try std.testing.expect(@backingInt(hidden_tab) != 0);
    const hidden = topology.focusedPaneId();
    try topology.switchTab(first_tab);
    try std.testing.expectEqual(first, topology.focusedPaneId());

    var policy = try terminal_handoff.FontPolicy.init(16.0);
    policy.count = 64;
    policy.offsets[0] = .{ .pane = closed, .offset_points = 1.0 };
    policy.offsets[1] = .{ .pane = hidden, .offset_points = 2.0 };
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
    try std.testing.expectEqual(@as(f64, 1.0), policyOffset(&request.policy, first));
    try std.testing.expectEqual(@as(f64, 2.0), policyOffset(&request.policy, hidden));
    try std.testing.expectEqual(@as(f64, 0.0), policyOffset(&request.policy, closed));
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
    var topology = try chrome_state.Topology.init(
        .{ .width = 320, .height = 240 },
        chrome_state.default_tab_bar_height,
    );
    const first = topology.focusedPaneId();
    const second = try topology.split(first, .horizontal);
    var policy = try terminal_handoff.FontPolicy.init(
        configured_terminal_base_points,
    );
    try setPolicyOffset(&policy, first, -2.0);
    try setPolicyOffset(&policy, second, 3.0);
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
    try std.testing.expectEqual(@as(f64, 17.0), policy.base_point_size);
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
    topology: *const chrome_state.Topology,
    topology_revision: ?terminal_handoff.LifecycleRevision,
    bootstrap: ?BootstrapSource,
    appearance: chrome_state.Appearance,
    primitives: []render_api.chrome.Primitive,
    text: []u8,
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
        const output = try topology.project(appearance, &.{}, primitives, text);
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
            const source = work.terminals.sourceFor(pane) orelse
                if (bootstrap) |value|
                    if (value.pane == pane) value.source else {
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
            desired[desired_count] = .{
                .source = source,
                .origin = .{ .x = rect.x, .y = rect.y },
                .clip = rect,
            };
            if (bootstrap == null or source != bootstrap.?.source) {
                desired_members[desired_count] = .{
                    .pane = pane,
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
        if (work.terminals.sourceFor(focused_pane)) |source|
            if (placementContainsSource(terminal_placements, source)) break :blk source;
        if (bootstrap) |value| {
            if (value.pane == focused_pane and
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
        if (result.accepted > chrome_state.max_live_panes)
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
        return if (retrying_chrome and retry_superseded)
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

fn waitCanvasPlan(
    boundary: *shared.Boundary,
    work: *CanvasWork,
    topology: *const chrome_state.Topology,
    topology_revision: ?terminal_handoff.LifecycleRevision,
    appearance: chrome_state.Appearance,
    primitives: []render_api.chrome.Primitive,
    text: []u8,
) !vk_surface.Plan {
    while (true) {
        switch (try buildCanvasPlan(
            work,
            topology,
            topology_revision,
            null,
            appearance,
            primitives,
            text,
        )) {
            .accepted => |plan| return plan,
            .retry => continue,
            .blocked => {},
        }
        switch (try waitRenderWakeBlocking(boundary, work.terminals)) {
            true, false => {},
        }
        if (boundary.shouldStop()) return error.Stopping;
        const status = work.terminals.status();
        if (status.stopped)
            return if (status.failed)
                error.TerminalRuntime
            else
                error.TerminalStopped;
    }
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
    topology: *const chrome_state.Topology,
    bootstrap: ?BootstrapSource,
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
        const source = work.terminals.sourceFor(pane) orelse
            if (bootstrap) |value|
                if (value.pane == pane) value.source else return error.InvalidTopology
            else
                return error.InvalidTopology;
        const rect = topology.paneRect(pane) orelse
            return error.InvalidTopology;
        if (count == members.len) return error.InvalidTopology;
        members[count] = .{ .pane = pane, .source = source };
        placements[count] = .{
            .source = source,
            .origin = .{ .x = rect.x, .y = rect.y },
            .clip = rect,
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
) !?vk_surface.CursorOverlay {
    const binding = work.composer.cursorBinding(publication.source) orelse
        return null;
    if (binding.pane != @backingInt(publication.pane) or
        binding.source != publication.source or
        binding.cell_size.width == 0 or binding.cell_size.height == 0 or
        binding.visible_set_revision != publication.visible_set_revision or
        binding.lifecycle_revision != @backingInt(publication.lifecycle_revision) or
        publication.cursor_revision <= binding.cursor_revision or
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

fn physicalPlanForBase(
    work: *CanvasWork,
    base: vk_surface.Plan,
    focused_pane: render_api.chrome.PaneId,
) !vk_surface.Plan {
    const source = work.terminals.sourceFor(focused_pane) orelse return base;
    const overlay = (try cursorOverlayForBinding(work, source)) orelse return base;
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

fn waitFeedback(boundary: *shared.Boundary) !shared.Feedback {
    var wakes: u8 = 0;
    while (wakes < 8) : (wakes += 1) {
        if (boundary.readFeedback()) |value| return value;
        if (boundary.shouldStop()) return error.Stopping;
        try waitRenderWake(boundary);
    }
    return error.FeedbackTimeout;
}

fn waitConfigure(boundary: *shared.Boundary) !shared.SurfaceConfig {
    var wakes: u8 = 0;
    while (wakes < 32) : (wakes += 1) {
        if (boundary.takeConfigure()) |value| return value;
        if (boundary.shouldStop()) return error.Stopping;
        try waitRenderWake(boundary);
    }
    return error.ConfigureTimeout;
}

fn waitWindowRing(boundary: *shared.Boundary, generation: u64) !void {
    const absolute = std.math.add(u64, try monotonicNow(), 2_000_000_000) catch
        return error.Clock;
    while (true) {
        if (boundary.isWindowRingReady(generation)) return;
        if (boundary.shouldStop()) return error.Stopping;
        if (!try waitRenderWakeUntil(boundary, absolute))
            return error.WindowRingTimeout;
    }
}

fn waitReleasePoints(boundary: *shared.Boundary, generation: u64, slots: *[shared.slot_count]Slot, drm_fd: i32) !void {
    if (generation == 0) return;
    var wakes: u8 = 0;
    while (wakes < 32) : (wakes += 1) {
        if (boundary.releaseFacts(generation)) |retired| {
            for (0..shared.slot_count) |index| {
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

fn waitWindowRingRetired(boundary: *shared.Boundary, generation: u64) !void {
    if (generation == 0) return;
    var wakes: u8 = 0;
    while (wakes < 32) : (wakes += 1) {
        if (boundary.takeWindowRingRetired(generation)) |_| return;
        try waitRenderWake(boundary);
    }
    return error.WindowRetirementTimeout;
}

fn waitRenderWake(boundary: *shared.Boundary) !void {
    var descriptor = c.pollfd{ .fd = boundary.renderFd(), .events = c.POLLIN, .revents = 0 };
    while (true) {
        const result = c.poll(&descriptor, 1, 2_000);
        if (result > 0) {
            try boundary.drainRenderWake();
            return;
        }
        if (result == 0) return error.WakeTimeout;
        if (std.c.errno(result) != .INTR) return error.Wake;
    }
}

fn waitRenderWakeUntil(boundary: *shared.Boundary, absolute: u64) !bool {
    var descriptor = c.pollfd{
        .fd = boundary.renderFd(),
        .events = c.POLLIN,
        .revents = 0,
    };
    while (true) {
        const now = try monotonicNow();
        if (now >= absolute) return false;
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
        const result = c.poll(&descriptor, 1, timeout);
        if (result > 0) {
            try boundary.drainRenderWake();
            return true;
        }
        if (result == 0) return false;
        if (std.c.errno(result) != .INTR) return error.Wake;
    }
}

fn waitRenderWakeBlocking(
    boundary: *shared.Boundary,
    terminals: *terminal_handoff.Boundary,
) !bool {
    var descriptors = [_]c.pollfd{
        .{ .fd = boundary.renderFd(), .events = c.POLLIN, .revents = 0 },
        .{ .fd = terminals.rendererFd(), .events = c.POLLIN, .revents = 0 },
    };
    while (true) {
        const result = c.poll(&descriptors, descriptors.len, -1);
        if (result > 0) {
            const boundary_woke = descriptors[0].revents & c.POLLIN != 0;
            if (boundary_woke)
                try boundary.drainRenderWake();
            const terminal_dirty = descriptors[1].revents & c.POLLIN != 0;
            if (terminal_dirty) try terminals.drainRendererWake();
            return terminal_dirty;
        }
        if (result < 0 and std.c.errno(result) == .INTR) continue;
        return error.Wake;
    }
}

fn drainInput(
    boundary: *shared.Boundary,
    actions: *input_actions.State,
    canvas_work: *CanvasWork,
    topology: *chrome_state.Topology,
    appearance: chrome_state.Appearance,
    pending: *?PendingTopology,
) !void {
    while (boundary.takeInput()) |event| {
        const basis = if (pending.*) |*value|
            &value.candidate
        else
            topology;
        const candidate: ?chrome_state.Topology = switch (event) {
            .key => |key| switch (actions.key(key) catch continue) {
                .action => |action| switch (action) {
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
                            ) catch continue,
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
                            ) catch continue,
                            else => unreachable,
                        }
                        break :blk null;
                    },
                    else => input_actions.candidate(basis, action) catch continue,
                },
                .consumed => null,
                .unmatched => unmatched: {
                    try canvas_work.terminals.publishKey(
                        topology.focusedPaneId(),
                        key,
                    );
                    break :unmatched null;
                },
            },
            .keyboard_leave => reset: {
                try canvas_work.terminals.publishFocus(
                    topology.focusedPaneId(),
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
                const accepted = input_actions.pointerCandidate(
                    topology,
                    appearance,
                    button,
                ) catch continue;
                if (accepted == null or pending.* == null) break :blk accepted;
                break :blk foldPointerCandidate(
                    &pending.*.?.candidate,
                    topology,
                    &accepted.?,
                ) catch continue;
            },
            .keyboard_enter => enter: {
                try canvas_work.terminals.publishFocus(
                    topology.focusedPaneId(),
                    .{ .focus = .in },
                );
                break :enter null;
            },
            .axis, .pointer_enter, .pointer_leave => null,
        };
        if (candidate) |next| {
            replacePendingTopology(
                canvas_work,
                topology,
                next,
                pending,
                null,
            ) catch continue;
        }
    }
}

const PendingTopologyPhase = enum {
    awaiting_admission,
    admitted,
};

const PendingTopology = struct {
    candidate: chrome_state.Topology,
    composer: *render_api.canvas.Composer,
    lifecycle: terminal_handoff.Boundary.PreparedLifecycle,
    revision: terminal_handoff.LifecycleRevision,
    phase: PendingTopologyPhase = .awaiting_admission,
    new_pane: ?render_api.chrome.PaneId,
    new_source: ?render_api.canvas.SourceId,
    surface: ?shared.SurfaceConfig = null,
    committed: bool = false,

    fn observeAdmission(self: *PendingTopology) ?terminal_handoff.AdmissionRejection {
        const result = self.lifecycle.admissionResult() orelse return null;
        switch (result) {
            .admitted => self.phase = .admitted,
            .rejected => |rejection| return rejection,
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
    current: *const chrome_state.Topology,
    candidate: *const chrome_state.Topology,
    surface: ?shared.SurfaceConfig,
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
            const rect = candidate.paneRect(pane) orelse
                return error.InvalidTopology;
            const pixels = try panePixels(rect);
            if (!topologyContains(current, pane)) {
                operations[operation_count] = .{ .create = .{
                    .pane = pane,
                    .pixels = pixels,
                } };
                operation_count += 1;
                new_panes += 1;
                registration_pane = pane;
            } else {
                const old_rect = current.paneRect(pane) orelse
                    return error.InvalidTopology;
                const old_pixels = try panePixels(old_rect);
                if (!std.meta.eql(old_pixels, pixels)) {
                    operations[operation_count] = .{ .resize = .{
                        .pane = pane,
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
                .pane = current.focusedPaneId(),
                .event = .{ .focus = .out },
            } };
            input_count += 1;
        }
        inputs[input_count] = .{ .focus = .{
            .pane = candidate.focusedPaneId(),
            .event = .{ .focus = .in },
        } };
        input_count += 1;
    }
    for (0..current.tabCount()) |tab_index| {
        for (0..current.paneCount(tab_index)) |pane_index| {
            const pane = current.paneId(tab_index, pane_index) orelse
                return error.InvalidTopology;
            if (!topologyContains(candidate, pane)) {
                operations[operation_count] = .{ .close = pane };
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
        .candidate = candidate.*,
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
    candidate: *const chrome_state.Topology,
    surface: shared.SurfaceConfig,
) !PendingTopology {
    const pane = candidate.focusedPaneId();
    const rect = candidate.paneRect(pane) orelse return error.InvalidTopology;
    const source = try work.composer.registerSource();
    errdefer work.composer.removeSource(source) catch
        @panic("initial terminal source rollback failed");
    const operations = [_]terminal_handoff.Lifecycle{.{ .create = .{
        .pane = pane,
        .pixels = try panePixels(rect),
    } }};
    var lifecycle = try work.terminals.prepareLifecycle(
        &operations,
        &.{},
        .{ .pane = pane, .source = source },
    );
    errdefer lifecycle.deinit();
    const revision = try lifecycle.publishAdmission();
    return .{
        .candidate = candidate.*,
        .composer = work.composer,
        .lifecycle = lifecycle,
        .revision = revision,
        .new_pane = pane,
        .new_source = source,
        .surface = surface,
    };
}

const TerminalTopologyRequirements = struct {
    operations: usize,
    inputs: usize,
    new_panes: usize,
};

fn preflightTerminalTopology(
    current: *const chrome_state.Topology,
    candidate: *const chrome_state.Topology,
) !TerminalTopologyRequirements {
    try validateTerminalTopology(candidate);
    var operations: usize = 0;
    var new_panes: usize = 0;
    for (0..candidate.tabCount()) |tab_index| {
        for (0..candidate.paneCount(tab_index)) |pane_index| {
            const pane = candidate.paneId(tab_index, pane_index) orelse
                return error.InvalidTopology;
            if (!topologyContains(current, pane)) new_panes += 1;
            const rect = candidate.paneRect(pane) orelse
                return error.InvalidTopology;
            if (!topologyContains(current, pane) or
                !std.meta.eql(
                    try panePixels(rect),
                    try panePixels(current.paneRect(pane) orelse rect),
                ))
                operations += 1;
        }
    }
    for (0..current.tabCount()) |tab_index| {
        for (0..current.paneCount(tab_index)) |pane_index| {
            const pane = current.paneId(tab_index, pane_index) orelse
                return error.InvalidTopology;
            if (!topologyContains(candidate, pane)) operations += 1;
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
    accepted: *const chrome_state.Topology,
    prospective: chrome_state.Topology,
    pending: *?PendingTopology,
    surface: ?shared.SurfaceConfig,
) !void {
    const requirements = try preflightTerminalTopology(accepted, &prospective);
    try work.terminals.preflightLifecycleReplacement(
        requirements.operations,
        requirements.inputs,
        requirements.new_panes != 0,
    );
    var retained_surface = surface;
    if (pending.*) |*old| {
        if (retained_surface == null) retained_surface = old.surface;
        old.deinit();
        pending.* = null;
    }
    pending.* = try prepareTerminalTopology(
        work,
        accepted,
        &prospective,
        retained_surface,
    );
}

fn foldPointerCandidate(
    pending: *const chrome_state.Topology,
    accepted: *const chrome_state.Topology,
    pointer: *const chrome_state.Topology,
) !?chrome_state.Topology {
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
    return if (changed) result else null;
}

fn topologyContains(
    topology: *const chrome_state.Topology,
    pane: render_api.chrome.PaneId,
) bool {
    return topology.paneRect(pane) != null;
}

fn shouldPublishFocusOut(
    current: *const chrome_state.Topology,
    candidate: *const chrome_state.Topology,
) bool {
    return current.focusedPaneId() != candidate.focusedPaneId() and
        topologyContains(candidate, current.focusedPaneId());
}

test "focused close omits stale focus-out while surviving focus change retains it" {
    var current = try chrome_state.Topology.init(
        .{ .width = 320, .height = 240 },
        chrome_state.default_tab_bar_height,
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
    var current = try chrome_state.Topology.init(
        .{ .width = 320, .height = 240 },
        chrome_state.default_tab_bar_height,
    );
    const pane = current.focusedPaneId();
    const initial_rect = current.paneRect(pane).?;
    const source = try composer.registerSource();
    try boundary.register(pane, source, try panePixels(initial_rect));
    const created = boundary.takeLifecycle().?;
    try std.testing.expectEqual(
        try panePixels(initial_rect),
        created.create.pixels,
    );
    try boundary.markLive(pane);

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
        try panePixels(resized_rect),
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
    var accepted = try chrome_state.Topology.init(
        .{ .width = 320, .height = 240 },
        chrome_state.default_tab_bar_height,
    );
    const first = accepted.focusedPaneId();
    const first_source = try composer.registerSource();
    try boundary.register(
        first,
        first_source,
        try panePixels(accepted.paneRect(first).?),
    );
    try std.testing.expect(boundary.takeLifecycle().? == .create);
    try boundary.markLive(first);
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
    const pane_count = pending.?.candidate.paneCount(0);
    try std.testing.expectError(error.NotAdmitted, pending.?.commit());
    try std.testing.expectEqual(@as(usize, 1), accepted.paneCount(0));
    try std.testing.expect(boundary.takeLifecycle() == null);
    var second_split = pending.?.candidate;
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
    try std.testing.expectEqual(pane_count, pending.?.candidate.paneCount(0));
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
    var accepted = try chrome_state.Topology.init(
        .{ .width = 320, .height = 240 },
        chrome_state.default_tab_bar_height,
    );
    const first = accepted.focusedPaneId();
    const accepted_source = try composer.registerSource();
    try boundary.register(
        first,
        accepted_source,
        try panePixels(accepted.paneRect(first).?),
    );
    try std.testing.expect(boundary.takeLifecycle().? == .create);
    try boundary.markLive(first);
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

    var focused = pending.?.candidate;
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
    try std.testing.expectEqual(first, pending.?.candidate.focusedPaneId());

    const focus_revision = pending.?.revision;
    var resized = pending.?.candidate;
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
    var closed = pending.?.candidate;
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
    try std.testing.expectEqual(@as(usize, 1), pending.?.candidate.paneCount(0));

    pending.?.deinit();
    pending = null;
    var new_tab = accepted;
    const tab = try new_tab.createTab("two");
    try std.testing.expectEqual(@as(usize, 2), new_tab.tabCount());
    pending = try prepareTerminalTopology(&work, &accepted, &new_tab, null);
    const tab_revision = pending.?.revision;
    var reordered = pending.?.candidate;
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
    try std.testing.expectEqual(tab, pending.?.candidate.tabId(0).?);
}

test "PendingTopology has one fixed allocation-free value" {
    try std.testing.expectEqual(@as(usize, 20_552), @sizeOf(PendingTopology));
    try std.testing.expectEqual(
        @as(usize, 544),
        @sizeOf(PreparedBootstrapPublication),
    );
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

    const topology = try chrome_state.Topology.init(
        .{ .width = 320, .height = 240 },
        chrome_state.default_tab_bar_height,
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
    try std.testing.expect(terminals.sourceFor(topology.focusedPaneId()) == null);
    pending.deinit();
    try std.testing.expect(terminals.takeLifecycle() == null);
    try std.testing.expectError(error.RetiredSource, composer.removeSource(source));
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
    const accepted_topology = try chrome_state.Topology.init(
        .{ .width = 320, .height = 240 },
        chrome_state.default_tab_bar_height,
    );
    const pane = accepted_topology.focusedPaneId();
    try terminals.register(
        pane,
        terminal_source,
        .{ .width = 320, .height = 216 },
    );
    const lifecycle = terminals.takeLifecycle() orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqual(pane, lifecycle.create.pane);
    const member = try terminals.activateTransfer(pane);
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
        (chrome_state.max_tabs + chrome_state.max_panes_per_tab) *
            chrome_state.max_label_bytes
    ]u8 = undefined;
    switch (try buildCanvasPlan(
        &work,
        &topology_a,
        revision_a,
        .{ .pane = cancelled_pane, .source = cancelled_source },
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
    try std.testing.expect(terminals.sourceFor(cancelled_pane) == null);
    var topology_b = accepted_topology;
    const replacement_pane = try topology_b.split(pane, .horizontal);
    try std.testing.expectEqual(cancelled_pane, replacement_pane);
    try topology_b.resizeSurface(.{ .width = 321, .height = 241 });
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
    try std.testing.expect(
        @backingInt(replacement_source) > @backingInt(cancelled_source),
    );
    const revision_b = replacement_pending.revision;
    var retained_topology = accepted_topology;
    const superseded_result = try buildCanvasPlan(
        &work,
        &topology_b,
        revision_b,
        .{ .pane = replacement_pane, .source = replacement_source },
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
        .{ .pane = replacement_pane, .source = replacement_source },
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
        (try retained_topology.project(
            chrome_appearance,
            &.{},
            &primitives,
            &text,
        )).text[0.."newer".len],
    );
    var observed_replacement_create = false;
    while (terminals.takeLifecycle()) |replacement_lifecycle| {
        switch (replacement_lifecycle) {
            .create => |create| {
                try std.testing.expectEqual(replacement_pane, create.pane);
                observed_replacement_create = true;
            },
            .resize, .close => {},
        }
    }
    try std.testing.expect(observed_replacement_create);
    const replacement_member = try terminals.activateTransfer(
        replacement_pane,
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
                .member = .{ .pane = pane, .source = terminal_source },
                .revision = @fromBackingInt(1),
            },
            .{
                .member = .{
                    .pane = replacement_pane,
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
    for (0..shared.slot_count) |_| {
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
    // d67cb4b baseline: 4096 bytes; the retained presentation view adds 56.
    const baseline_size: usize = 4096;
    const retained_delta: usize = 56;
    try std.testing.expectEqual(@as(usize, 8), @alignOf(CanvasWork));
    try std.testing.expectEqual(baseline_size + retained_delta, @sizeOf(CanvasWork));
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

fn panePixels(rect: render_api.chrome.Rect) error{InvalidTopology}!render_api.canvas.Size {
    if (rect.width == 0 or rect.height == 0) return error.InvalidTopology;
    return .{ .width = rect.width, .height = rect.height };
}

fn redrawChrome(
    boundary: *shared.Boundary,
    topology: *chrome_state.Topology,
    canvas_work: *CanvasWork,
    appearance: chrome_state.Appearance,
    primitives: *[256]render_api.chrome.Primitive,
    text: *[(chrome_state.max_tabs + chrome_state.max_panes_per_tab) * chrome_state.max_label_bytes]u8,
    graphics: *vk_surface.Context,
    device: vk.VkDevice,
    queue: vk.VkQueue,
    family: u32,
    command: vk.VkCommandBuffer,
    slots: *[shared.slot_count]Slot,
    generation: u64,
    dispatch: *const howl_vk.dispatch.ExternalImageDispatch,
    drm_fd: i32,
    acquire_handle: u32,
    next_acquire_point: *u64,
    pending: ?*PendingTopology,
) !RedrawResult {
    if (!try releaseReplayRetirementIfReady(
        boundary,
        canvas_work.replay,
        generation,
        slots,
        drm_fd,
    )) return .blocked;
    const candidate = if (pending) |value| value.candidate else topology.*;
    const topology_revision = if (pending) |value| value.revision else null;
    try validateTerminalTopology(&candidate);
    var bootstrap_publication: ?PreparedBootstrapPublication =
        if (pending) |value|
            if (value.new_source != null)
                try prepareBootstrapPublication(
                    canvas_work,
                    &candidate,
                    value.bootstrap(),
                )
            else
                null
        else
            null;
    defer if (bootstrap_publication) |*publication| publication.deinit();
    const plan_result = try buildCanvasPlan(
        canvas_work,
        &candidate,
        topology_revision,
        if (pending) |value| value.bootstrap() else null,
        appearance,
        primitives,
        text,
    );
    const composer_plan = switch (plan_result) {
        .blocked => return .blocked,
        .retry => return .retry,
        .accepted => |plan| plan,
    };
    // Composer's accepted commands are cursor-free.  The only physical
    // presentation derived from this candidate is one focused overlay, and
    // it is translated through the exact terminal placement before replay.
    const physical_plan = try physicalPlanForBase(
        canvas_work,
        composer_plan,
        candidate.focusedPaneId(),
    );
    // Both the staged residency and replay candidate remain owned by this
    // construction until completion acceptance.  Install rollback before
    // probing ring capacity so a blocked candidate cannot strand either.
    errdefer canvas_work.residency.discard();
    errdefer canvas_work.replay.discard();
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
    const completion = shared.Completion{
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
    slot.release_point = release_point;
    next_acquire_point.* = following_acquire_point;
    return .published;
}

/// Records one physical cursor replacement without touching Composer, Pool, or
/// terminal Content. The accepted replay cohort remains authoritative until
/// completion preparation commits the replacement ring candidate.
fn replayCursorFrame(
    boundary: *shared.Boundary,
    work: *CanvasWork,
    pending: *?terminal_handoff.CursorPublication,
    focused_source: ?render_api.canvas.SourceId,
    slots: *[shared.slot_count]Slot,
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
) !RedrawResult {
    const publication = pending.* orelse return .blocked;
    if (focused_source == null or focused_source.? != publication.source)
        return .blocked;
    const overlay = (cursorOverlayFor(work, publication) catch return .blocked) orelse
        return .blocked;
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
    if (base.commands.len > frame_command_limit) return .blocked;
    const candidate_cohort = work.replay.candidate();
    const candidate = vk_surface.replayCursor(
        base,
        overlay,
        .{
            .vertices = candidate_cohort.vertices,
            .indices = candidate_cohort.indices,
            .commands = candidate_cohort.commands,
        },
    ) catch return .blocked;
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
    const following_acquire_point = std.math.add(u64, acquire_point, 1) catch
        return .blocked;
    const release_point = std.math.add(u64, slot.release_point, 1) catch
        return .blocked;
    var release_sync_fd: i32 = -1;
    if (c.drmSyncobjExportSyncFile(drm_fd, slot.release_handle, &release_sync_fd) != 0)
        return .blocked;
    errdefer if (release_sync_fd >= 0) closeDescriptor(release_sync_fd);
    const release_wait = importReleaseSemaphore(device, dispatch, &release_sync_fd) catch
        return .blocked;
    defer vk.vkDestroySemaphore(device, release_wait, null);
    // A preview-driven cursor burst can publish another target while this
    // candidate is being prepared.  Revalidate at the last point before
    // physical submission so an older target is never presented when the
    // newer one is already waiting in the Boundary inbox: transfer that
    // exact latest publication to the local pending slot and retry without a
    // terminal wake or a full Content/Pool/Composer rebuild.
    if (takeNewerCursorReplay(
        work.terminals,
        publication,
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
    ) catch return .blocked;
    // Restore the canonical cursor-free bytes before the physical slot is
    // accepted.  The presented candidate remains owned by the ring slot; the
    // replay cohort stays a stable base for the next cursor-only update.
    work.replay.restoreCandidateBase(base);
    const completion = shared.Completion{
        .generation = generation,
        .revision = acquire_point,
        .slot = @intCast(slot_index),
        .acquire_point = acquire_point,
        .release_point = release_point,
    };
    var prepared = boundary.prepareCompletions(&.{completion}) catch return .blocked;
    defer prepared.deinit();
    prepared.commit();
    work.replay.commitCursor(slot_index);
    slot.release_point = release_point;
    next_acquire_point.* = following_acquire_point;
    return .published;
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

fn validateTerminalTopology(candidate: *const chrome_state.Topology) !void {
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
    boundary: *shared.Boundary,
    generation: u64,
    slots: *[shared.slot_count]Slot,
    drm_fd: i32,
    excluded_slot: ?usize,
) !usize {
    const facts = boundary.releaseFacts(generation) orelse return error.NoReleasedSlot;
    var first_candidate: ?usize = null;
    for (0..shared.slot_count) |index| {
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
    boundary: *shared.Boundary,
    replay: *ReplayState,
    generation: u64,
    slots: *[shared.slot_count]Slot,
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
    facts: shared.RetiredRing,
    slots: *const [shared.slot_count]Slot,
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
    const feedback_major = c.major(feedback_device);
    const feedback_minor = c.minor(feedback_device);
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
        var status: c.struct_stat = undefined;
        if (c.stat(name, &status) != 0) continue;
        if (c.major(status.st_rdev) != major or c.minor(status.st_rdev) != minor) continue;
        const descriptor = c.open(name, c.O_RDWR | c.O_CLOEXEC);
        if (descriptor >= 0) return descriptor;
        return error.DrmOpen;
    }
    return error.DrmOpen;
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
        if (value.drmFormatModifier == modifier and value.drmFormatModifierPlaneCount > 0 and value.drmFormatModifierPlaneCount <= shared.plane_limit) return @intCast(value.drmFormatModifierPlaneCount);
    }
    return error.Modifier;
}

fn constructSlot(slot: *Slot, graphics: *const vk_surface.Context, device: vk.VkDevice, memory_properties: vk.VkPhysicalDeviceMemoryProperties, modifier: u64, dedicated_only: bool, plane_count: u8, surface: shared.SurfaceConfig, dispatch: *const howl_vk.dispatch.ExternalImageDispatch, drm_fd: i32, offer: *shared.SlotOffer, offered_fds: *OfferedFds, gpu_bytes: *u64) !void {
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
    if (available == -c.ETIME) return false;
    if (available != 0) return error.ReleaseAvailability;
    const complete = c.drmSyncobjTimelineWait(drm_fd, &handles, &points, 1, timeout, 0, null);
    if (complete == -c.ETIME) return false;
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
    return @intCast(try std.math.add(u64, try monotonicNow(), 2_000_000_000));
}

fn monotonicNow() !u64 {
    var now: c.timespec = undefined;
    if (c.clock_gettime(c.CLOCK_MONOTONIC, &now) != 0) return error.Clock;
    const seconds = try std.math.mul(u64, @intCast(now.tv_sec), 1_000_000_000);
    return try std.math.add(u64, seconds, @intCast(now.tv_nsec));
}

fn closeDescriptor(descriptor: i32) void {
    if (c.close(descriptor) != 0) @panic("Render descriptor cleanup failed");
}

fn destroySyncobj(drm_fd: i32, handle: u32) void {
    if (c.drmSyncobjDestroy(drm_fd, handle) != 0) @panic("Render syncobj cleanup failed");
}
