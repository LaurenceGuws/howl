//! App-only cursor clocks over retained frames; never mutates VT or requests projection.
const std = @import("std");
const instance = @import("howl_instance");

/// Configured visible baseline; applications may still select or hide their cursor.
pub const Shape = enum {
    block,
    bar,
    underline,

    /// Converts the host preference to canonical cursor defaults.
    pub fn style(self: Shape) instance.Terminal.CursorStyle {
        return .{ .shape = switch (self) {
            .block => .block,
            .bar => .bar,
            .underline => .underline,
        }, .blink = true };
    }
};

/// Off preserves steady presentation; application follows DECSCUSR/DEC blink intent.
pub const Policy = enum { off, application, always };
/// Saved host timing only; VT and Render own no blink clock.
pub const Options = struct {
    policy: Policy = .off,
    interval_ms: u16 = 500,
    idle_ms: u32 = 0,

    /// Zero idle disables the stop; each phase stays between 100ms and 2s.
    pub fn valid(self: Options) bool {
        return self.interval_ms >= 100 and self.interval_ms <= 2000 and self.idle_ms <= 60_000;
    }
};

/// One pane's bounded presentation phase; canonical movement time is an identity, not our clock.
pub const Blink = struct {
    origin: ?u64 = null,
    options: Options = .{},
    movement: u64 = 0,
    generation: u64 = 0,
    alternate: bool = false,
    deadline: ?u64 = null,

    /// Restarts visibly on the next eligible focused presentation.
    pub fn reset(self: *Blink) void {
        self.* = .{};
    }

    /// Returns whether to compose the existing cursor suffix and its next exact phase deadline.
    pub fn update(self: *Blink, now: u64, frame: instance.PublishedFrame, focused: bool, options: Options) bool {
        std.debug.assert(options.valid());
        if (!focused or options.policy == .off or (options.policy == .application and !frame.cursor_blink) or
            frame.commands.len == frame.content_command_count)
        {
            self.reset();
            return true;
        }
        if (self.origin == null or now < self.origin.? or self.movement != frame.cursor_movement or
            self.generation != frame.presentation_generation or self.alternate != frame.alternate_screen or
            !std.meta.eql(self.options, options))
        {
            self.origin = now;
            self.options = options;
            self.movement = frame.cursor_movement;
            self.generation = frame.presentation_generation;
            self.alternate = frame.alternate_screen;
        }
        const elapsed = now - self.origin.?;
        if (options.idle_ms != 0 and elapsed >= options.idle_ms) {
            self.deadline = null;
            return true;
        }
        const interval: u64 = options.interval_ms;
        const phase_deadline = now +| (interval - elapsed % interval);
        self.deadline = if (options.idle_ms == 0) phase_deadline else @min(phase_deadline, self.origin.? +| options.idle_ms);
        return elapsed / interval % 2 == 0;
    }
};

/// Saved opt-in host motion; no perpetual timer or retained frame ownership.
pub const MotionOptions = struct {
    enabled: bool = false,
    duration_ms: u16 = 80,

    /// Keep the first movement implementation short and bounded.
    pub fn valid(self: MotionOptions) bool {
        return self.duration_ms >= 20 and self.duration_ms <= 250;
    }
};

const Rect = instance.render.terminal.Rect;

/// One pane's finite linear movement. Sizes/styles and ownership changes snap.
pub const Motion = struct {
    target: ?Rect = null,
    from_x: f64 = 0,
    from_y: f64 = 0,
    started: u64 = 0,
    generation: u64 = 0,
    alternate: bool = false,
    options: MotionOptions = .{},
    placement: [4]f32 = @splat(0),
    surface: instance.render.terminal.Size = .{ .width = 1, .height = 1 },
    cell_size: instance.render.terminal.Size = .{ .width = 1, .height = 1 },
    style: ?@TypeOf(@as(instance.render.terminal.CursorOverlay, undefined).shape) = null,
    deadline: ?u64 = null,

    /// Hidden panes/focus transitions must never resume an old flight.
    pub fn reset(self: *Motion) void {
        self.* = .{};
    }

    /// Samples current position before retargeting, preserving continuous motion.
    /// Returns null when canonical composition already represents this position.
    pub fn update(self: *Motion, now: u64, frame: instance.PublishedFrame, focused: bool, options: MotionOptions, placement: [4]f32) ?Rect {
        std.debug.assert(options.valid());
        const overlay = frame.cursor orelse {
            self.reset();
            return null;
        };
        const rect = overlay.rect;
        if (!focused or !options.enabled or frame.history_offset != 0) {
            self.reset();
            return null;
        }
        const changed_owner = self.target == null or self.generation != frame.presentation_generation or
            self.alternate != frame.alternate_screen or !std.meta.eql(self.placement, placement) or
            !std.meta.eql(self.surface, frame.surface) or !std.meta.eql(self.cell_size, frame.cell_size) or
            !std.meta.eql(self.options, options) or self.style != overlay.shape or now < self.started;
        const changed_size = if (self.target) |target| target.width != rect.width or target.height != rect.height else true;
        if (changed_owner or changed_size) {
            self.target = rect;
            self.from_x = @floatFromInt(rect.x);
            self.from_y = @floatFromInt(rect.y);
            self.started = now;
            self.generation = frame.presentation_generation;
            self.alternate = frame.alternate_screen;
            self.options = options;
            self.placement = placement;
            self.surface = frame.surface;
            self.cell_size = frame.cell_size;
            self.style = overlay.shape;
            self.deadline = null;
            return null;
        }
        const current = self.position(now);
        if (self.target.?.x != rect.x or self.target.?.y != rect.y) {
            self.from_x = current[0];
            self.from_y = current[1];
            self.target = rect;
            self.started = now;
        }
        const point = self.position(now);
        if (now - self.started >= options.duration_ms or
            (self.from_x == @as(f64, @floatFromInt(rect.x)) and self.from_y == @as(f64, @floatFromInt(rect.y))))
        {
            self.deadline = null;
            return null;
        }
        // Finite on-demand frames; completion gets its exact deadline.
        self.deadline = @min(now +| 16, self.started +| options.duration_ms);
        return .{ .x = @intFromFloat(@round(point[0])), .y = @intFromFloat(@round(point[1])), .width = rect.width, .height = rect.height };
    }

    fn position(self: *const Motion, now: u64) [2]f64 {
        const rect = self.target.?;
        const t = @as(f64, @floatFromInt(@min(now -| self.started, self.options.duration_ms))) / @as(f64, @floatFromInt(self.options.duration_ms));
        return .{
            self.from_x + (@as(f64, @floatFromInt(rect.x)) - self.from_x) * t,
            self.from_y + (@as(f64, @floatFromInt(rect.y)) - self.from_y) * t,
        };
    }
};

test "blink phases use deadlines, ignore content refresh and reset on movement or presentation ownership" {
    var frame = testFrame();
    var blink: Blink = .{};
    try std.testing.expect(blink.update(100, frame, true, .{ .policy = .application }));
    try std.testing.expectEqual(@as(?u64, 600), blink.deadline);
    try std.testing.expect(blink.update(599, frame, true, .{ .policy = .application }));
    try std.testing.expect(!blink.update(600, frame, true, .{ .policy = .application }));
    frame.revision += 1; // Background output must not pin the cursor in its on phase.
    try std.testing.expect(!blink.update(900, frame, true, .{ .policy = .application }));
    try std.testing.expect(blink.update(1100, frame, true, .{ .policy = .application }));
    try std.testing.expect(!blink.update(2600, frame, true, .{ .policy = .application }));
    frame.cursor_movement += 1;
    try std.testing.expect(blink.update(2601, frame, true, .{ .policy = .application }));
    try std.testing.expectEqual(@as(?u64, 3101), blink.deadline);
    try std.testing.expect(!blink.update(3101, frame, true, .{ .policy = .application }));
    frame.presentation_generation += 1;
    try std.testing.expect(blink.update(3102, frame, true, .{ .policy = .application }));
    frame.alternate_screen = true;
    try std.testing.expect(blink.update(3602, frame, true, .{ .policy = .application }));
    try std.testing.expectEqual(@as(?u64, 4102), blink.deadline);
    // Inactive, hidden, history and steady cursors require no timer.
    try std.testing.expect(blink.update(4000, frame, false, .{ .policy = .always }));
    try std.testing.expect(blink.deadline == null);
    frame.cursor_blink = false;
    try std.testing.expect(blink.update(4000, frame, true, .{ .policy = .application }));
    try std.testing.expect(blink.deadline == null);
    try std.testing.expect(blink.update(4000, frame, true, .{ .policy = .always }));
    try std.testing.expect(blink.deadline != null);
    try std.testing.expect(blink.update(4100, frame, true, .{ .policy = .off }));
    try std.testing.expect(blink.deadline == null);
    frame.commands = &.{};
    try std.testing.expect(blink.update(4200, frame, true, .{ .policy = .always }));
    try std.testing.expect(blink.deadline == null);
}

fn testFrame() instance.PublishedFrame {
    const command: instance.render.terminal.Command = .{ .solid = .{
        .rect = .{ .x = 0, .y = 0, .width = 10, .height = 20 },
        .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    } };
    return .{
        .sequence = 1,
        .presentation_generation = 1,
        .revision = 1,
        .terminal_revision = 1,
        .history_offset = 0,
        .history_count = 0,
        .history_row_base = 0,
        .alternate_screen = false,
        .surface = .{ .width = 10, .height = 20 },
        .cell_size = .{ .width = 10, .height = 20 },
        .commands = &.{command},
        .uploads = &.{},
        .removals = &.{},
        .pixels = &.{},
        .cursor_blink = true,
        .cursor_movement = 99,
    };
}

test "configured cadence stops steadily at idle deadline and resumes only on activity or preference change" {
    var frame = testFrame();
    var blink: Blink = .{};
    var options: Options = .{ .policy = .application, .interval_ms = 200, .idle_ms = 450 };
    try std.testing.expect(blink.update(100, frame, true, options));
    try std.testing.expectEqual(@as(?u64, 300), blink.deadline);
    try std.testing.expect(!blink.update(300, frame, true, options));
    try std.testing.expectEqual(@as(?u64, 500), blink.deadline);
    try std.testing.expect(blink.update(500, frame, true, options));
    try std.testing.expectEqual(@as(?u64, 550), blink.deadline);
    try std.testing.expect(blink.update(550, frame, true, options));
    try std.testing.expectEqual(null, blink.deadline);
    frame.revision += 1;
    try std.testing.expect(blink.update(1000, frame, true, options));
    try std.testing.expectEqual(null, blink.deadline);
    frame.cursor_movement += 1;
    try std.testing.expect(blink.update(1001, frame, true, options));
    try std.testing.expect(!blink.update(1201, frame, true, options));
    blink.reset(); // Accepted typing/paste does not need canonical echo.
    try std.testing.expect(blink.update(1202, frame, true, options));
    try std.testing.expectEqual(@as(?u64, 1402), blink.deadline);
    options.interval_ms = 100;
    try std.testing.expect(blink.update(1250, frame, true, options));
    try std.testing.expectEqual(@as(?u64, 1350), blink.deadline);
    try std.testing.expect(!blink.update(1350, frame, true, options));
    try std.testing.expect(blink.update(1200, frame, true, options)); // Caller clock rollback.
    try std.testing.expectEqual(@as(?u64, 1300), blink.deadline);
    options.idle_ms = 0;
    try std.testing.expect(blink.update(1301, frame, true, options));
    try std.testing.expect(blink.update(9999, frame, true, options));
    try std.testing.expectEqual(@as(?u64, 10001), blink.deadline);
    try std.testing.expect(!(Options{ .interval_ms = 99 }).valid());
    try std.testing.expect(!(Options{ .interval_ms = 2001 }).valid());
    try std.testing.expect(!(Options{ .idle_ms = 60_001 }).valid());
}

test "motion retargets continuously and retires its exact completion deadline" {
    var frame = testFrame();
    frame.surface = .{ .width = 200, .height = 100 };
    frame.cursor = .{ .rect = .{ .x = 0, .y = 0, .width = 10, .height = 20 }, .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 }, .text_color = .{ .r = 0, .g = 0, .b = 0, .a = 255 }, .shape = .block, .color_resource = null };
    var motion: Motion = .{};
    const options: MotionOptions = .{ .enabled = true };
    const placement: [4]f32 = .{ 0, 0, 200, 100 };
    try std.testing.expectEqual(null, motion.update(100, frame, true, options, placement));
    try std.testing.expectEqual(null, motion.deadline);
    frame.cursor.?.rect.x = 80;
    frame.cursor.?.rect.y = 40;
    var rect = motion.update(100, frame, true, options, placement).?;
    try std.testing.expectEqual(@as(i32, 0), rect.x);
    try std.testing.expectEqual(@as(?u64, 116), motion.deadline);
    frame.revision += 1; // Content refresh must not restart an ongoing flight.
    rect = motion.update(140, frame, true, options, placement).?;
    try std.testing.expectEqual(@as(i32, 40), rect.x);
    try std.testing.expectEqual(@as(i32, 20), rect.y);
    frame.cursor.?.rect.x = 0; // Rapid reversal starts at the current visual point.
    rect = motion.update(140, frame, true, options, placement).?;
    try std.testing.expectEqual(@as(i32, 40), rect.x);
    try std.testing.expectEqual(@as(i32, 20), rect.y);
    rect = motion.update(160, frame, true, options, placement).?;
    try std.testing.expectEqual(@as(i32, 30), rect.x);
    try std.testing.expectEqual(@as(i32, 25), rect.y);
    rect = motion.update(219, frame, true, options, placement).?;
    try std.testing.expectEqual(@as(?u64, 220), motion.deadline);
    try std.testing.expect(rect.x >= 0 and rect.y <= 40);
    try std.testing.expectEqual(null, motion.update(220, frame, true, options, placement));
    try std.testing.expectEqual(null, motion.deadline);
    try std.testing.expectEqual(null, motion.update(9000, frame, true, options, placement));
    try std.testing.expectEqual(null, motion.deadline);
}

test "motion snaps across focus viewport geometry style preference and clock changes" {
    var frame = testFrame();
    frame.surface = .{ .width = 200, .height = 100 };
    frame.cursor = .{ .rect = .{ .x = 0, .y = 0, .width = 10, .height = 20 }, .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 }, .text_color = .{ .r = 0, .g = 0, .b = 0, .a = 255 }, .shape = .bar, .color_resource = null };
    const placement: [4]f32 = .{ 0, 0, 200, 100 };
    for (0..12) |change| {
        var motion: Motion = .{};
        var options: MotionOptions = .{ .enabled = true };
        var cut = frame;
        try std.testing.expectEqual(null, motion.update(100, cut, true, options, placement));
        cut.cursor.?.rect.x = 80;
        try std.testing.expect(motion.update(101, cut, true, options, placement) != null);
        var focused = true;
        var placed = placement;
        var now: u64 = 120;
        switch (change) {
            0 => focused = false,
            1 => cut.presentation_generation += 1,
            2 => cut.alternate_screen = true,
            3 => placed[0] = 1,
            4 => cut.cursor.?.rect.width = 20,
            5 => cut.cursor.?.shape = .underline,
            6 => options.enabled = false,
            7 => options.duration_ms = 100,
            8 => cut.history_offset = 1,
            9 => now = 50,
            10 => cut.surface.width += 1,
            11 => cut.cell_size.width += 1,
            else => return error.UnexpectedTestCase,
        }
        try std.testing.expectEqual(null, motion.update(now, cut, focused, options, placed));
        try std.testing.expectEqual(null, motion.deadline);
    }
    var motion: Motion = .{};
    const options: MotionOptions = .{ .enabled = true };
    try std.testing.expectEqual(null, motion.update(1, frame, true, options, placement));
    frame.cursor.?.rect.x = 40;
    try std.testing.expect(motion.update(2, frame, true, options, placement) != null);
    frame.cursor = null;
    try std.testing.expectEqual(null, motion.update(3, frame, true, options, placement));
    try std.testing.expect(motion.target == null and motion.deadline == null);
    try std.testing.expect(!(MotionOptions{ .duration_ms = 19 }).valid());
    try std.testing.expect(!(MotionOptions{ .duration_ms = 251 }).valid());
}
