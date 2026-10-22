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

/// One closed-form position curve; retargeting always samples its current point.
pub const Easing = enum {
    linear,
    ease_out,

    fn value(self: Easing, t: f64) f64 {
        std.debug.assert(t >= 0 and t <= 1);
        return switch (self) {
            .linear => t,
            .ease_out => 1 - (1 - t) * (1 - t) * (1 - t),
        };
    }
};

/// Optional bounded decoration of the moving host cursor.
pub const Effect = enum { none, stretch, trail };

/// Saved opt-in host motion; no perpetual timer or retained frame ownership.
pub const MotionOptions = struct {
    enabled: bool = false,
    duration_ms: u16 = 80,
    easing: Easing = .linear,
    effect: Effect = .none,

    /// All movement and tail lifetimes stay short and bounded.
    pub fn valid(self: MotionOptions) bool {
        return self.duration_ms >= 20 and self.duration_ms <= 250;
    }
};

const Rect = instance.render.terminal.Rect;
const trail_limit = 4;

/// One translucent historic cursor body; never carries translated glyph ink.
pub const Ghost = struct {
    rect: Rect = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
    alpha: u8 = 0,
};

/// Complete bounded host composition for this instant.
pub const Visual = struct {
    rect: Rect,
    /// Signed tail offset bounded to one cursor width/height.
    stretch: [2]i32 = .{ 0, 0 },
    ghosts: [trail_limit]Ghost = @splat(.{}),
    ghost_count: u8 = 0,
};

/// One pane's finite motion/effects. Sizes/styles and ownership changes snap.
pub const Motion = struct {
    const Sample = struct { rect: Rect, at: u64 };
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
    samples: [trail_limit]Sample = undefined,
    sample_count: u8 = 0,
    last_rect: ?Rect = null,
    last_seen: u64 = 0,
    last_emit: u64 = 0,
    deadline: ?u64 = null,

    /// Hidden panes/focus transitions must never resume an old flight or tail.
    pub fn reset(self: *Motion) void {
        self.* = .{};
    }

    /// Samples current position before retargeting. Null uses the canonical suffix.
    pub fn update(self: *Motion, now: u64, frame: instance.PublishedFrame, focused: bool, options: MotionOptions, placement: [4]f32) ?Visual {
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
            !std.meta.eql(self.options, options) or now < self.last_seen;
        const changed_cursor = if (self.target) |previous| self.style != overlay.shape or
            previous.width != rect.width or previous.height != rect.height else true;
        if (changed_owner or changed_cursor) {
            self.reset();
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
            self.last_rect = rect;
            self.last_seen = now;
            self.last_emit = now;
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
        var visual: Visual = .{ .rect = .{
            .x = @intFromFloat(@round(point[0])),
            .y = @intFromFloat(@round(point[1])),
            .width = rect.width,
            .height = rect.height,
        } };
        const moving = now - self.started < options.duration_ms and
            (self.from_x != @as(f64, @floatFromInt(rect.x)) or self.from_y != @as(f64, @floatFromInt(rect.y)));
        self.deadline = if (moving) @min(now +| 16, self.started +| options.duration_ms) else null;
        switch (options.effect) {
            .none => {},
            .stretch => if (moving) {
                const t = self.progress(now);
                const envelope = 4 * t * (1 - t);
                const dx = @as(f64, @floatFromInt(rect.x)) - self.from_x;
                const dy = @as(f64, @floatFromInt(rect.y)) - self.from_y;
                visual.stretch = .{
                    @intFromFloat(@round(-std.math.sign(dx) * @min(@abs(dx), @as(f64, @floatFromInt(rect.width))) * envelope)),
                    @intFromFloat(@round(-std.math.sign(dy) * @min(@abs(dy), @as(f64, @floatFromInt(rect.height))) * envelope)),
                };
            },
            .trail => {
                const lifetime: u64 = @min(@as(u64, options.duration_ms) * 2, 200);
                var retained: u8 = 0;
                for (self.samples[0..self.sample_count]) |sample| {
                    if (now -| sample.at >= lifetime) continue;
                    self.samples[retained] = sample;
                    retained += 1;
                }
                self.sample_count = retained;
                if (moving and now - self.last_emit >= 16) {
                    if (self.last_rect) |previous| if (!std.meta.eql(previous, visual.rect) and now -| self.last_seen < lifetime) {
                        const count: usize = @min(self.sample_count, trail_limit - 1);
                        @memmove(self.samples[1 .. count + 1], self.samples[0..count]);
                        self.samples[0] = .{ .rect = previous, .at = self.last_seen };
                        self.sample_count = @intCast(count + 1);
                        self.last_emit = now;
                    };
                }
                for (self.samples[0..self.sample_count], 0..) |sample, index| {
                    const age = now -| sample.at;
                    std.debug.assert(age < lifetime);
                    const alpha: u64 = (lifetime - age) * 72 / lifetime;
                    visual.ghosts[index] = .{ .rect = sample.rect, .alpha = @intCast(alpha) };
                    const next = @min(now +| 16, sample.at +| lifetime);
                    self.deadline = @min(self.deadline orelse next, next);
                }
                visual.ghost_count = self.sample_count;
            },
        }
        self.last_rect = visual.rect;
        self.last_seen = now;
        return if (moving or visual.ghost_count != 0) visual else null;
    }

    fn progress(self: *const Motion, now: u64) f64 {
        return @as(f64, @floatFromInt(@min(now -| self.started, self.options.duration_ms))) / @as(f64, @floatFromInt(self.options.duration_ms));
    }

    fn position(self: *const Motion, now: u64) [2]f64 {
        const rect = self.target.?;
        const t = self.options.easing.value(self.progress(now));
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
    var rect = motion.update(100, frame, true, options, placement).?.rect;
    try std.testing.expectEqual(@as(i32, 0), rect.x);
    try std.testing.expectEqual(@as(?u64, 116), motion.deadline);
    frame.revision += 1; // Content refresh must not restart an ongoing flight.
    rect = motion.update(140, frame, true, options, placement).?.rect;
    try std.testing.expectEqual(@as(i32, 40), rect.x);
    try std.testing.expectEqual(@as(i32, 20), rect.y);
    frame.cursor.?.rect.x = 0; // Rapid reversal starts at the current visual point.
    rect = motion.update(140, frame, true, options, placement).?.rect;
    try std.testing.expectEqual(@as(i32, 40), rect.x);
    try std.testing.expectEqual(@as(i32, 20), rect.y);
    rect = motion.update(160, frame, true, options, placement).?.rect;
    try std.testing.expectEqual(@as(i32, 30), rect.x);
    try std.testing.expectEqual(@as(i32, 25), rect.y);
    rect = motion.update(219, frame, true, options, placement).?.rect;
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

test "easing samples its closed curve and reverses from the current visual point" {
    var frame = testFrame();
    frame.surface = .{ .width = 200, .height = 100 };
    frame.cursor = .{ .rect = .{ .x = 0, .y = 0, .width = 10, .height = 20 }, .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 }, .text_color = .{ .r = 0, .g = 0, .b = 0, .a = 255 }, .shape = .block, .color_resource = null };
    var motion: Motion = .{};
    const options: MotionOptions = .{ .enabled = true, .easing = .ease_out };
    const placement: [4]f32 = .{ 0, 0, 200, 100 };
    try std.testing.expectEqual(null, motion.update(100, frame, true, options, placement));
    frame.cursor.?.rect.x = 80;
    try std.testing.expectEqual(@as(i32, 0), motion.update(100, frame, true, options, placement).?.rect.x);
    try std.testing.expectEqual(@as(i32, 70), motion.update(140, frame, true, options, placement).?.rect.x);
    frame.cursor.?.rect.x = 0;
    try std.testing.expectEqual(@as(i32, 70), motion.update(140, frame, true, options, placement).?.rect.x);
    try std.testing.expectEqual(@as(i32, 9), motion.update(180, frame, true, options, placement).?.rect.x);
    try std.testing.expectEqual(null, motion.update(220, frame, true, options, placement));
    try std.testing.expectEqual(null, motion.deadline);
    for ([_]Easing{ .linear, .ease_out }) |curve| {
        var previous: f64 = 0;
        for (0..101) |i| {
            const value = curve.value(@as(f64, @floatFromInt(i)) / 100);
            try std.testing.expect(value >= previous and value >= 0 and value <= 1);
            previous = value;
        }
        try std.testing.expectEqual(@as(f64, 1), previous);
    }
}

test "stretch stays within one cursor extent and collapses at exact completion" {
    var frame = testFrame();
    frame.surface = .{ .width = 200, .height = 100 };
    frame.cursor = .{ .rect = .{ .x = 80, .y = 40, .width = 10, .height = 20 }, .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 }, .text_color = .{ .r = 0, .g = 0, .b = 0, .a = 255 }, .shape = .block, .color_resource = null };
    const options: MotionOptions = .{ .enabled = true, .effect = .stretch };
    const placement: [4]f32 = .{ 0, 0, 200, 100 };
    for ([_][2]i32{ .{ 0, 0 }, .{ 160, 80 }, .{ 0, 80 }, .{ 160, 0 } }) |target| {
        var motion: Motion = .{};
        try std.testing.expectEqual(null, motion.update(100, frame, true, options, placement));
        var moved = frame;
        moved.cursor.?.rect.x = target[0];
        moved.cursor.?.rect.y = target[1];
        const first = motion.update(100, moved, true, options, placement).?;
        try std.testing.expectEqualDeep([2]i32{ 0, 0 }, first.stretch);
        for (1..80) |elapsed| {
            const visual = motion.update(100 + elapsed, moved, true, options, placement).?;
            try std.testing.expect(@abs(visual.stretch[0]) <= frame.cursor.?.rect.width);
            try std.testing.expect(@abs(visual.stretch[1]) <= frame.cursor.?.rect.height);
            try std.testing.expect(visual.ghost_count == 0);
        }
        try std.testing.expectEqual(null, motion.update(180, moved, true, options, placement));
        try std.testing.expectEqual(null, motion.deadline);
    }
}

test "four trail samples fade out finitely and exact last expiry retires the timer" {
    var frame = testFrame();
    frame.surface = .{ .width = 200, .height = 100 };
    frame.cursor = .{ .rect = .{ .x = 0, .y = 0, .width = 10, .height = 20 }, .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 }, .text_color = .{ .r = 0, .g = 0, .b = 0, .a = 255 }, .shape = .block, .color_resource = null };
    var motion: Motion = .{};
    const options: MotionOptions = .{ .enabled = true, .effect = .trail };
    const placement: [4]f32 = .{ 0, 0, 200, 100 };
    try std.testing.expectEqual(null, motion.update(0, frame, true, options, placement));
    frame.cursor.?.rect.x = 80;
    try std.testing.expectEqual(@as(u8, 0), motion.update(0, frame, true, options, placement).?.ghost_count);
    for (1..5) |i| {
        const visual = motion.update(i * 16, frame, true, options, placement).?;
        try std.testing.expectEqual(@as(u8, @intCast(i)), visual.ghost_count);
        for (visual.ghosts[0..visual.ghost_count]) |ghost| try std.testing.expect(ghost.alpha <= 72);
    }
    const tail = motion.update(80, frame, true, options, placement).?;
    try std.testing.expectEqual(@as(i32, 80), tail.rect.x);
    try std.testing.expectEqual(@as(u8, 4), tail.ghost_count);
    try std.testing.expect(motion.deadline != null);
    const last = motion.update(207, frame, true, options, placement).?;
    try std.testing.expectEqual(@as(u8, 1), last.ghost_count);
    try std.testing.expectEqual(@as(?u64, 208), motion.deadline);
    try std.testing.expectEqual(null, motion.update(208, frame, true, options, placement));
    try std.testing.expectEqual(null, motion.deadline);
    try std.testing.expectEqual(null, motion.update(9000, frame, true, options, placement));
    try std.testing.expectEqual(@as(u8, 0), motion.sample_count);
}

test "rapid effect retargeting stays bounded visibility clears tails and live colors preserve motion" {
    var frame = testFrame();
    frame.surface = .{ .width = 200, .height = 100 };
    frame.cursor = .{ .rect = .{ .x = 0, .y = 0, .width = 10, .height = 20 }, .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 }, .text_color = .{ .r = 0, .g = 0, .b = 0, .a = 255 }, .shape = .bar, .color_resource = null };
    const placement: [4]f32 = .{ 0, 0, 200, 100 };
    for ([_]Easing{ .linear, .ease_out }) |curve| for ([_]Effect{ .none, .stretch, .trail }) |effect| {
        var motion: Motion = .{};
        var cut = frame;
        const options: MotionOptions = .{ .enabled = true, .duration_ms = 250, .easing = curve, .effect = effect };
        try std.testing.expectEqual(null, motion.update(0, cut, true, options, placement));
        for (1..1001) |i| {
            cut.cursor.?.rect.x = if (i % 2 == 0) 0 else 160;
            const visual = motion.update(i * 7, cut, true, options, placement).?;
            try std.testing.expect(visual.rect.x >= 0 and visual.rect.x <= 160);
            try std.testing.expect(visual.ghost_count <= 4 and motion.sample_count <= 4);
        }
        try std.testing.expectEqual(null, motion.update(7500, cut, true, options, placement));
        try std.testing.expectEqual(null, motion.deadline);
        cut.cursor.?.rect.x = if (cut.cursor.?.rect.x == 0) 160 else 0;
        try std.testing.expect(motion.update(7501, cut, true, options, placement) != null);
        try std.testing.expectEqual(null, motion.update(7510, cut, false, options, placement));
        try std.testing.expect(motion.target == null and motion.sample_count == 0 and motion.deadline == null);
        try std.testing.expectEqual(null, motion.update(7511, cut, true, options, placement));
        cut.cursor.?.rect.x = if (cut.cursor.?.rect.x == 0) 160 else 0;
        try std.testing.expect(motion.update(7512, cut, true, options, placement) != null);
        cut.cursor.?.text_color.g = 1;
        cut.cursor.?.color.r = 100;
        // Colors naturally change across inverse/styled cells; latest frame colors
        // compose over the same ongoing visual flight rather than pinning it.
        try std.testing.expect(motion.update(7513, cut, true, options, placement) != null);
        try std.testing.expect(motion.deadline != null);
    };
}
