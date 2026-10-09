const std = @import("std");
const instance = @import("howl_instance");
const layout = @import("layout.zig");

/// Copied history geometry; neither frame storage nor canonical text is retained.
pub const Bar = struct {
    track: layout.Rect,
    thumb: layout.Rect,
    count: u32,

    /// Derives a bounded overlay from the accepted frame without changing canonical columns.
    pub fn fromFrame(rect: layout.Rect, frame: instance.PublishedFrame, scale: f32) ?Bar {
        if (frame.alternate_screen or frame.history_count == 0 or frame.cell_size.height == 0 or !std.math.isFinite(scale) or scale <= 0 or rect.width <= 0 or rect.height <= 0) return null;
        const rows = frame.surface.height / frame.cell_size.height;
        if (rows == 0 or frame.history_offset > frame.history_count) return null;
        const height = @min(rect.height, @as(f32, @floatFromInt(frame.surface.height)) / scale);
        const width = @min(7, rect.width);
        const track: layout.Rect = .{ .x = rect.x + rect.width - width, .y = rect.y, .width = width, .height = height };
        const total = @as(f64, @floatFromInt(frame.history_count)) + @as(f64, @floatFromInt(rows));
        const thumb_height = std.math.clamp(@as(f64, height) * @as(f64, @floatFromInt(rows)) / total, @min(18, height), height);
        const position = 1 - @as(f64, @floatFromInt(frame.history_offset)) / @as(f64, @floatFromInt(frame.history_count));
        return .{
            .track = track,
            .thumb = .{ .x = track.x, .y = track.y + @as(f32, @floatCast(position * (@as(f64, height) - thumb_height))), .width = width, .height = @floatCast(thumb_height) },
            .count = frame.history_count,
        };
    }
    /// Maps a clamped captured pointer to a bounded seek, preserving its thumb grab position.
    pub fn seek(self: Bar, y: f32, grab: f32) ?u32 {
        if (!std.math.isFinite(y) or !std.math.isFinite(grab)) return null;
        const span = self.track.height - self.thumb.height;
        if (span <= 0) return 0;
        const position = std.math.clamp((@as(f64, y) - self.track.y - grab) / span, 0, 1);
        return @intFromFloat(@round((1 - position) * @as(f64, @floatFromInt(self.count))));
    }
};

test "scrollbar endpoints fractional geometry bounded capture and alternate suppression" {
    var frame: instance.PublishedFrame = undefined;
    frame.alternate_screen = false;
    frame.history_count = 100;
    frame.history_offset = 50;
    frame.cell_size = .{ .width = 17, .height = 41 };
    frame.surface = .{ .width = 1530, .height = 820 };
    const rect: layout.Rect = .{ .x = 10, .y = 20, .width = 900, .height = 500 };
    const bar = Bar.fromFrame(rect, frame, 1.7).?;
    try std.testing.expect(bar.track.x == 903);
    try std.testing.expectEqual(@as(?u32, 100), bar.seek(-1000, 5));
    try std.testing.expectEqual(@as(?u32, 0), bar.seek(10000, 5));
    try std.testing.expectEqual(@as(?u32, 50), bar.seek(bar.thumb.y + 5, 5));
    try std.testing.expect(bar.seek(std.math.nan(f32), 0) == null);
    frame.alternate_screen = true;
    try std.testing.expect(Bar.fromFrame(rect, frame, 1.7) == null);
    frame.alternate_screen = false;
    frame.history_count = 0;
    try std.testing.expect(Bar.fromFrame(rect, frame, 1.7) == null);
}
