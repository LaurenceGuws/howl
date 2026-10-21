//! App-only cursor blink over a complete retained frame; never mutates VT or requests projection.
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
