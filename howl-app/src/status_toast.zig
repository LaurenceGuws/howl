//! One host-owned floating status/notice surface, never a terminal row,
//! tab title, mutable VT borrow, or second program-status database.
const std = @import("std");
const vt = @import("howl_vt");
const layout = @import("layout.zig");
const host = @import("program_status.zig");

/// Host placement preference; right keeps the left command prompt clear.
pub const Position = enum { top_right, top_left };
/// The palette role used for one active toast, independent of VT colors.
pub const Kind = enum { notice, running, blocked, done, failed };
const frames = [_][]const u8{ "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" };
/// One bounded spinner cadence shared by formatting and the SDL wake timer.
pub const frame_ms: u64 = 120;
/// One bounded copied paint instruction, with no retained typography objects.
pub const View = struct {
    bytes: [128]u8 = @splat(0),
    len: u8 = 0,
    kind: Kind,
    animated: bool = false,

    /// Borrows only this copied paint instruction, never child-origin bytes.
    pub fn text(self: *const View) []const u8 {
        return self.bytes[0..self.len];
    }
};

fn make(kind: Kind, animated: bool, value: []const u8) View {
    var result: View = .{ .kind = kind, .animated = animated };
    var end = @min(value.len, result.bytes.len);
    if (end < value.len) {
        while (end > 0 and value[end] & 0xc0 == 0x80) end -= 1;
    }
    @memcpy(result.bytes[0..end], value[0..end]);
    result.len = @intCast(end);
    return result;
}

/// One notice supersedes program status; otherwise OSC 7501 wins over OSC 9;4.
/// A missing app name is never guessed from the shell/title.
pub fn fromStatus(
    summary: host.Summary,
    task: vt.Terminal.Progress,
    notice: []const u8,
    now: u64,
) ?View {
    if (notice.len != 0) return make(.notice, false, notice);
    var scratch: [128]u8 = undefined;
    const spinner = frames[(now / frame_ms) % frames.len];
    const app = summary.appText();
    if (summary.state) |state| {
        const kind: Kind = switch (state) {
            .idle => return null,
            .working => .running,
            .blocked => .blocked,
            .done => .done,
            .@"error" => .failed,
        };
        const base = switch (state) {
            .idle => return null,
            .working => if (summary.progress) |p|
                (std.fmt.bufPrint(&scratch, "{s} {d}%", .{ spinner, p }) catch return null)
            else
                (std.fmt.bufPrint(&scratch, "{s} Working", .{spinner}) catch return null),
            .blocked => switch (summary.kind orelse .question) {
                .auth => "◷ Auth needed",
                .permission => "◷ Permission needed",
                .question => "◷ Waiting",
            },
            .done => "✓ Done",
            .@"error" => "✕ Failed",
        };
        if (app.len == 0) return make(kind, kind == .running, base);
        // Copy the formatted prefix to separate stack scratch before append.
        var text: [128]u8 = undefined;
        const combined = std.fmt.bufPrint(&text, "{s} - {s}", .{ base, app }) catch return null;
        return make(kind, kind == .running, combined);
    }
    const base = switch (task.kind) {
        .none => return null,
        .normal => std.fmt.bufPrint(&scratch, "{s} {d}%", .{ spinner, task.value orelse return null }) catch return null,
        .indeterminate => std.fmt.bufPrint(&scratch, "{s} Working", .{spinner}) catch return null,
        .paused => if (task.value) |value| std.fmt.bufPrint(&scratch, "◷ Paused {d}%", .{value}) catch return null else "◷ Paused",
        .failure => if (task.value) |value| std.fmt.bufPrint(&scratch, "✕ Failed {d}%", .{value}) catch return null else "✕ Failed",
    };
    const kind: Kind = switch (task.kind) {
        .none => return null,
        .normal, .indeterminate => .running,
        .paused => .blocked,
        .failure => .failed,
    };
    return make(kind, kind == .running, base);
}

/// Clamps the one toast entirely inside the physical window without
/// consuming terminal rows or shifting any PTY viewport geometry.
pub fn geometry(
    window_width: f32,
    window_height: f32,
    header_height: f32,
    text_width: f32,
    position: Position,
) ?layout.Rect {
    if (!std.math.isFinite(window_width) or !std.math.isFinite(window_height) or
        !std.math.isFinite(header_height) or !std.math.isFinite(text_width)) return null;
    if (window_width <= 0 or window_height <= 0) return null;
    const inset = @min(12, window_width / 4);
    const available = window_width - 2 * inset;
    const top = @max(0, header_height) + 8;
    const height: f32 = @min(30, window_height - top);
    if (height < 18 or available < 1) return null;
    // A one-line toast must remain a compact overlay, never a replacement
    // for a window-wide progress strip or a modal dialogue.
    const width = @min(available, @min(320, @max(46, @max(0, text_width) + 28)));
    const x = if (position == .top_right) window_width - inset - width else inset;
    return .{ .x = x, .y = top, .width = width, .height = height };
}

/// Animation runs only while the visible toast shows running progress.
pub fn animationDelay(now: u64, view: ?View) ?u64 {
    const active = view orelse return null;
    if (!active.animated) return null;
    return frame_ms - now % frame_ms;
}

test "OSC 7501 validated program name creates one toast with no invented command" {
    var status: host.Summary = .{ .state = .working, .progress = 32, .count = 1 };
    @memcpy(status.app[0..3], "zig");
    status.app_len = 3;
    try std.testing.expectEqualStrings("⣾ 32% - zig", fromStatus(status, .{}, "", 0).?.text());
    const no_app = fromStatus(.{ .state = .working, .progress = 32, .count = 1 }, .{}, "", 0).?;
    try std.testing.expectEqualStrings("⣾ 32%", no_app.text());
    try std.testing.expectEqualStrings("⣽ 32% - zig", fromStatus(status, .{}, "", 120).?.text());
    try std.testing.expectEqualStrings("◷ Auth needed - zig", fromStatus(.{ .state = .blocked, .kind = .auth, .app = status.app, .app_len = 3 }, .{}, "", 0).?.text());
    try std.testing.expectEqualStrings("✓ Done - zig", fromStatus(.{ .state = .done, .app = status.app, .app_len = 3 }, .{}, "", 0).?.text());
    try std.testing.expectEqualStrings("✕ Failed - zig", fromStatus(.{ .state = .@"error", .app = status.app, .app_len = 3 }, .{}, "", 0).?.text());
}

test "OSC 9;4 fallback never invents a program and notices share the surface" {
    try std.testing.expect(fromStatus(.{}, .{}, "", 0) == null);
    try std.testing.expectEqualStrings("⣾ 67%", fromStatus(.{}, .{ .kind = .normal, .value = 67 }, "", 0).?.text());
    try std.testing.expectEqualStrings("⣾ Working", fromStatus(.{}, .{ .kind = .indeterminate }, "", 0).?.text());
    try std.testing.expectEqualStrings("◷ Paused 67%", fromStatus(.{}, .{ .kind = .paused, .value = 67 }, "", 0).?.text());
    try std.testing.expectEqualStrings("⚠ Config not saved", fromStatus(.{ .state = .working, .progress = 34 }, .{}, "⚠ Config not saved", 0).?.text());
    try std.testing.expectEqual(@as(?u64, 120), animationDelay(0, fromStatus(.{}, .{ .kind = .normal, .value = 1 }, "", 0)));
    try std.testing.expectEqual(@as(?u64, null), animationDelay(0, fromStatus(.{}, .{}, "notice", 0)));
}

test "toast geometry is right aligned and never changes the terminal grid" {
    const right = geometry(900, 600, 32, 120, .top_right).?;
    try std.testing.expectEqual(@as(f32, 900 - 12 - 148), right.x);
    try std.testing.expectEqual(@as(f32, 40), right.y);
    try std.testing.expectEqual(@as(f32, 30), right.height);
    const left = geometry(900, 600, 32, 120, .top_left).?;
    try std.testing.expectEqual(@as(f32, 12), left.x);
    try std.testing.expectEqual(@as(f32, 40), left.y);
    const no_header = geometry(900, 600, 0, 120, .top_right).?;
    try std.testing.expectEqual(@as(f32, 8), no_header.y);
    const capped = geometry(1200, 900, 32, 2000, .top_right).?;
    try std.testing.expectEqual(@as(f32, 320), capped.width);
    try std.testing.expectEqual(@as(f32, 1200 - 12 - 320), capped.x);
    const small = geometry(95, 90, 0, 2000, .top_right).?;
    try std.testing.expect(small.x >= 0 and small.x + small.width <= 95);
    try std.testing.expect(geometry(0, 80, 0, 30, .top_right) == null);
    try std.testing.expect(geometry(80, 10, 0, 30, .top_right) == null);
    try std.testing.expect(geometry(std.math.nan(f32), 80, 0, 30, .top_right) == null);
}

test "OSC 9 paused toast distinguishes an unspecified percentage from explicit zero" {
    try std.testing.expectEqualStrings("◷ Paused", fromStatus(.{}, .{ .kind = .paused }, "", 0).?.text());
    try std.testing.expectEqualStrings("◷ Paused 0%", fromStatus(.{}, .{ .kind = .paused, .value = 0 }, "", 0).?.text());
}

test "OSC 9 failure toast displays only an explicitly present percentage" {
    try std.testing.expectEqualStrings("✕ Failed", fromStatus(.{}, .{ .kind = .failure }, "", 0).?.text());
    try std.testing.expectEqualStrings("✕ Failed 0%", fromStatus(.{}, .{ .kind = .failure, .value = 0 }, "", 0).?.text());
    try std.testing.expectEqualStrings("✕ Failed 75%", fromStatus(.{}, .{ .kind = .failure, .value = 75 }, "", 0).?.text());
    try std.testing.expectEqualStrings("◷ Waiting", fromStatus(.{ .state = .blocked }, .{ .kind = .failure, .value = 75 }, "", 0).?.text());
}
