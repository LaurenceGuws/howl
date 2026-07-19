//! Copies borrowed parser actions into caller-owned test and simulation storage.

const std = @import("std");
const parser_mod = @import("parser.zig");

/// Copies borrowed parser phase actions into arena-backed storage transactionally.
pub fn appendOwnedPhases(allocator: std.mem.Allocator, arena: std.mem.Allocator, actions: *std.ArrayList(parser_mod.Action), phases: parser_mod.PhaseActions) error{OutOfMemory}!void {
    for (phases) |phase| {
        if (phase) |action| try appendOwnedAction(allocator, arena, actions, action);
    }
}

fn appendOwnedAction(allocator: std.mem.Allocator, arena: std.mem.Allocator, actions: *std.ArrayList(parser_mod.Action), action: parser_mod.Action) error{OutOfMemory}!void {
    switch (action) {
        .csi_dispatch => |csi| {
            const params = try dupeArenaSlice(arena, i32, csi.params[0..csi.count]);
            const intermediates = try dupeArenaSlice(arena, u8, csi.intermediates[0..csi.intermediates_len]);
            try actions.append(allocator, .{ .csi_dispatch = .{
                .final = csi.final,
                .params = params,
                .separators = csi.separators,
                .count = csi.count,
                .leader = csi.leader,
                .private = csi.private,
                .intermediates = intermediates,
                .intermediates_len = csi.intermediates_len,
            } });
        },
        .dcs_hook => |hook| {
            const params = try dupeArenaSlice(arena, i32, hook.params[0..hook.count]);
            const intermediates = try dupeArenaSlice(arena, u8, hook.intermediates[0..hook.intermediates_len]);
            try actions.append(allocator, .{ .dcs_hook = .{
                .final = hook.final,
                .params = params,
                .count = hook.count,
                .intermediates = intermediates,
                .intermediates_len = hook.intermediates_len,
            } });
        },
        .osc_dispatch => |osc| {
            const owned = try arena.dupe(u8, osc.payload());
            try actions.append(allocator, .{ .osc_dispatch = switch (osc) {
                .raw_title => .{ .raw_title = .{ .payload = owned, .term = osc.term() } },
                .raw_other => .{ .raw_other = .{ .payload = owned, .term = osc.term() } },
                .title => |v| .{ .title = .{ .command = v.command, .payload = owned, .term = v.term } },
                .icon => .{ .icon = .{ .payload = owned, .term = osc.term() } },
                .palette_control => |v| .{ .palette_control = .{ .command = v.command, .payload = owned, .term = v.term } },
                .palette_reset => |v| .{ .palette_reset = .{ .command = v.command, .payload = owned, .term = v.term } },
                .dynamic_color => |v| .{ .dynamic_color = .{ .command = v.command, .payload = owned, .term = v.term } },
                .dynamic_reset => |v| .{ .dynamic_reset = .{ .command = v.command, .payload = owned, .term = v.term } },
                .report_pwd => .{ .report_pwd = .{ .payload = owned, .term = osc.term() } },
                .hyperlink => .{ .hyperlink = .{ .payload = owned, .term = osc.term() } },
                .notification => |v| .{ .notification = .{ .command = v.command, .payload = owned, .term = v.term } },
                .pointer_shape => .{ .pointer_shape = .{ .payload = owned, .term = osc.term() } },
                .clipboard => |v| .{ .clipboard = .{ .command = v.command, .payload = owned, .term = v.term } },
                .kitty_color => |v| .{ .kitty_color = .{ .command = v.command, .payload = owned, .term = v.term } },
                .kitty_text_size => .{ .kitty_text_size = .{ .payload = owned, .term = osc.term() } },
                .shell_mark => .{ .shell_mark = .{ .payload = owned, .term = osc.term() } },
                .rxvt_extension => .{ .rxvt_extension = .{ .payload = owned, .term = osc.term() } },
                .iterm2 => |v| .{ .iterm2 = .{
                    .command = v.command,
                    .payload = owned,
                    .term = v.term,
                } },
                .context_signal => .{ .context_signal = .{ .payload = owned, .term = osc.term() } },
                .kitty_color_stack_push => .{ .kitty_color_stack_push = osc.term() },
                .kitty_color_stack_pop => .{ .kitty_color_stack_pop = osc.term() },
                .kitty_file_transfer => .{ .kitty_file_transfer = .{ .payload = owned, .term = osc.term() } },
                .kitty_clipboard => .{ .kitty_clipboard = .{ .payload = owned, .term = osc.term() } },
            } });
        },
        else => try actions.append(allocator, action),
    }
}

fn dupeArenaSlice(arena: std.mem.Allocator, comptime T: type, data: []const T) error{OutOfMemory}![]const T {
    if (data.len == 0) return &.{};
    return try arena.dupe(T, data);
}
