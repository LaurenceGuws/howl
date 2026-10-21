//! App-only cursor blink over a complete retained frame; never mutates VT or requests projection.
const std = @import("std");
const instance = @import("howl_instance");

/// Off preserves steady presentation; application follows DECSCUSR/DEC blink intent.
pub const Policy = enum { off, application, always };
const half_period_ms: u64 = 500;

/// One pane's bounded presentation phase; canonical movement time is an identity, not our clock.
pub const Blink = struct {
    origin: u64 = 0,
    movement: u64 = 0,
    generation: u64 = 0,
    alternate: bool = false,
    deadline: ?u64 = null,

    /// Restarts visibly on the next eligible focused presentation.
    pub fn reset(self: *Blink) void {
        self.* = .{};
    }

    /// Returns whether to compose the existing cursor suffix and its next exact phase deadline.
    pub fn update(self: *Blink, now: u64, frame: instance.PublishedFrame, focused: bool, policy: Policy) bool {
        if (!focused or policy == .off or (policy == .application and !frame.cursor_blink) or
            frame.commands.len == frame.content_command_count)
        {
            self.reset();
            return true;
        }
        if (self.deadline == null or now < self.origin or self.movement != frame.cursor_movement or
            self.generation != frame.presentation_generation or self.alternate != frame.alternate_screen)
        {
            self.origin = now;
            self.movement = frame.cursor_movement;
            self.generation = frame.presentation_generation;
            self.alternate = frame.alternate_screen;
        }
        const elapsed = now - self.origin;
        self.deadline = now +| (half_period_ms - elapsed % half_period_ms);
        return elapsed / half_period_ms % 2 == 0;
    }
};

test "blink phases use deadlines, ignore content refresh and reset on movement or presentation ownership" {
    const command: instance.render.terminal.Command = .{ .solid = .{
        .rect = .{ .x = 0, .y = 0, .width = 10, .height = 20 },
        .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    } };
    var frame: instance.PublishedFrame = .{
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
    var blink: Blink = .{};
    try std.testing.expect(blink.update(100, frame, true, .application));
    try std.testing.expectEqual(@as(?u64, 600), blink.deadline);
    try std.testing.expect(blink.update(599, frame, true, .application));
    try std.testing.expect(!blink.update(600, frame, true, .application));
    frame.revision += 1; // Background output must not pin the cursor in its on phase.
    try std.testing.expect(!blink.update(900, frame, true, .application));
    try std.testing.expect(blink.update(1100, frame, true, .application));
    try std.testing.expect(!blink.update(2600, frame, true, .application));
    frame.cursor_movement += 1;
    try std.testing.expect(blink.update(2601, frame, true, .application));
    try std.testing.expectEqual(@as(?u64, 3101), blink.deadline);
    try std.testing.expect(!blink.update(3101, frame, true, .application));
    frame.presentation_generation += 1;
    try std.testing.expect(blink.update(3102, frame, true, .application));
    frame.alternate_screen = true;
    try std.testing.expect(blink.update(3602, frame, true, .application));
    try std.testing.expectEqual(@as(?u64, 4102), blink.deadline);
    // Inactive, hidden, history and steady cursors require no timer.
    try std.testing.expect(blink.update(4000, frame, false, .always));
    try std.testing.expect(blink.deadline == null);
    frame.cursor_blink = false;
    try std.testing.expect(blink.update(4000, frame, true, .application));
    try std.testing.expect(blink.deadline == null);
    try std.testing.expect(blink.update(4000, frame, true, .always));
    try std.testing.expect(blink.deadline != null);
    try std.testing.expect(blink.update(4100, frame, true, .off));
    try std.testing.expect(blink.deadline == null);
    frame.commands = &.{};
    try std.testing.expect(blink.update(4200, frame, true, .always));
    try std.testing.expect(blink.deadline == null);
}
