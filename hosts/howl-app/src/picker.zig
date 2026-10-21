//! App-owned search and navigation. No I/O, retained catalogue or launch ownership.
const std = @import("std");
const widgets = @import("widgets.zig");
const config = @import("config.zig");
const discovery = @import("discovery.zig");
const keybindings = @import("keybindings.zig");

/// Complete bounded view: seven saved profiles, discovered recipes and two app actions.
pub const limit = @max(keybindings.definitions.len, discovery.limit + 9);
/// Saved commands have no inferred runtime category; Local is also a Shell.
pub const Filter = enum { all, saved, shell, repl, remote };
/// Visible chip labels in keyboard cycle order.
pub const labels = [_][]const u8{ "All", "Saved", "Shell", "REPL", "Remote" };

/// One disposable overlay. Hover never changes the keyboard's launch selection.
pub const Picker = struct {
    query: [128]u8 = @splat(0),
    len: usize = 0,
    edit: widgets.Text = .{},
    list: widgets.List = .{},
    profile: bool = false,
    filter: Filter = .all,

    /// Returns stable recipe/action indexes, ranked by exact, prefix, substring, then subsequence.
    /// Equal ranks retain source order. Filtering cannot reinterpret a saved command.
    pub fn indices(self: *const Picker, configuration: *const config.Config, discovered: ?*const discovery.Catalogue, out: *[limit]usize) error{InvalidDefaultProfile}!usize {
        var count: usize = 0;
        var ranks: [limit]u32 = undefined;
        const saved = configuration.profileCount();
        const profiles = @as(usize, saved) + (if (discovered) |catalogue| @as(usize, catalogue.count) else 0);
        const candidates = if (self.profile) profiles + 2 else keybindings.definitions.len;
        for (0..candidates) |i| {
            if (self.profile and self.filter != .all) {
                const accepted = if (i < saved)
                    self.filter == .saved or (i == 0 and self.filter == .shell)
                else if (i < profiles) switch (discovered.?.entries[i - saved].kind) {
                    .shell => self.filter == .shell,
                    .repl => self.filter == .repl,
                    .ssh => self.filter == .remote,
                } else false;
                if (!accepted) continue;
            }
            const label = if (!self.profile) keybindings.definitions[i].label else if (i < saved)
                (try configuration.profile(@intCast(i))).name
            else if (i < profiles)
                discovered.?.entries[i - saved].recipe.name
            else if (i == profiles) "Command Palette" else "Settings";
            const rank = match(label, self.query[0..self.len]) orelse continue;
            var at = count;
            while (at > 0 and rank < ranks[at - 1]) : (at -= 1) {
                out[at] = out[at - 1];
                ranks[at] = ranks[at - 1];
            }
            out[at] = i;
            ranks[at] = rank;
            count += 1;
        }
        return count;
    }
    /// Restarts navigation after a query/category change without changing either input.
    pub fn reset(self: *Picker) void {
        self.list = .{};
    }
    /// Shares the same UTF-8 editor as settings and installed fonts.
    pub fn append(self: *Picker, bytes: []const u8) error{ InvalidPickerText, PickerQueryLimit }!void {
        self.edit.insert(&self.query, &self.len, bytes) catch |failure| return switch (failure) {
            error.InvalidText => error.InvalidPickerText,
            error.TextLimit => error.PickerQueryLimit,
        };
        self.reset();
    }
    /// Moves the caret without changing query results.
    pub fn moveCursor(self: *Picker, direction: i8) void {
        self.edit.move(self.query[0..self.len], direction);
    }
    /// Removes the previous scalar or an explicitly selected complete query.
    pub fn erase(self: *Picker, all: bool) void {
        if (all) self.edit.select_all = true;
        self.edit.erase(&self.query, &self.len, false);
        self.reset();
    }
    /// Removes the following scalar.
    pub fn delete(self: *Picker) void {
        self.edit.erase(&self.query, &self.len, true);
        self.reset();
    }
    /// Shares the measured-caret viewport.
    pub fn revealCursor(self: *Picker, caret_width: f32, text_width: f32, width: f32) f32 {
        return self.edit.reveal(caret_width, text_width, width);
    }
    /// Changes category while retaining typed search; command palettes have no categories.
    pub fn cycle(self: *Picker, reverse: bool) void {
        if (!self.profile) return;
        const current: usize = @backingInt(self.filter);
        self.filter = @fromBackingInt(@intCast((current + (if (reverse) labels.len - 1 else @as(usize, 1))) % labels.len));
        self.reset();
    }
    /// Clamps after resize/filtering and moves the viewport only when selection leaves it.
    pub fn reveal(self: *Picker, count: usize, visible: usize) void {
        self.list.reveal(count, visible);
    }
    /// Scrolls using the same viewport policy as settings and fonts.
    pub fn scroll(self: *Picker, delta: i32, count: usize, visible: usize) void {
        self.list.scroll(delta, count, visible);
    }
};

// Ranks fit bounded profile/action labels. No edit-distance correction guesses remote names.
fn match(value: []const u8, query: []const u8) ?u32 {
    if (query.len == 0 or std.ascii.eqlIgnoreCase(value, query)) return 0;
    if (query.len <= value.len) {
        for (0..value.len - query.len + 1) |start| {
            if (std.ascii.eqlIgnoreCase(value[start..][0..query.len], query))
                return (if (start == 0) @as(u32, 1) else 2) << 24 | @as(u32, @intCast(start)) << 12;
        }
    }
    var next: usize = 0;
    var first: usize = 0;
    for (value, 0..) |byte, i| {
        if (std.ascii.toLower(byte) != std.ascii.toLower(query[next])) continue;
        if (next == 0) first = i;
        next += 1;
        if (next == query.len) return @as(u32, 3) << 24 | @as(u32, @intCast(first)) << 12 | @as(u32, @intCast(i - first + 1));
    }
    return null;
}

test "ranked search prefers an exact destination before prefix, substring and abbreviation" {
    var configuration = try config.Config.parse(std.testing.allocator, std.testing.io, "{\"schema\":1,\"terminal_font_pixels\":15,\"profiles\":[{\"id\":\"a\",\"name\":\"prod-east\"},{\"id\":\"b\",\"name\":\"my-prod\"},{\"id\":\"c\",\"name\":\"prod\"},{\"id\":\"d\",\"name\":\"p-r-o-d\"}]}");
    defer configuration.deinit();
    var p: Picker = .{ .profile = true };
    try p.append("PROD");
    var indexes: [limit]usize = undefined;
    const count = try p.indices(&configuration, null, &indexes);
    try std.testing.expectEqualSlices(usize, &.{ 3, 1, 2, 4 }, indexes[0..count]);
    p.reset();
    try std.testing.expectEqualStrings("PROD", p.query[0..p.len]);
    try std.testing.expectEqual(@as(?u32, null), match("prod", "prdo"));
}

test "categories preserve custom saved identity and never admit app actions" {
    var configuration = try config.Config.parse(std.testing.allocator, std.testing.io, "{\"schema\":1,\"terminal_font_pixels\":15,\"profiles\":[{\"id\":\"custom\",\"name\":\"Mystery\",\"command\":\"ssh remote\"}]}");
    defer configuration.deinit();
    var catalogue: discovery.Catalogue = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer catalogue.arena.deinit();
    catalogue.entries[0] = .{ .kind = .shell, .recipe = .{ .name = "Fish" } };
    catalogue.entries[1] = .{ .kind = .repl, .recipe = .{ .name = "Python" } };
    catalogue.entries[2] = .{ .kind = .ssh, .recipe = .{ .name = "Remote" } };
    catalogue.count = 3;
    var p: Picker = .{ .profile = true };
    var indexes: [limit]usize = undefined;
    for ([_]Filter{ .saved, .shell, .repl, .remote }, [_][]const usize{ &.{ 0, 1 }, &.{ 0, 2 }, &.{3}, &.{4} }) |filter, expected| {
        p.filter = filter;
        const count = try p.indices(&configuration, &catalogue, &indexes);
        try std.testing.expectEqualSlices(usize, expected, indexes[0..count]);
    }
    try p.append("Python");
    p.filter = .remote;
    try std.testing.expectEqual(@as(usize, 0), try p.indices(&configuration, &catalogue, &indexes));
    p.cycle(true);
    try std.testing.expectEqual(Filter.repl, p.filter);
    try std.testing.expectEqualStrings("Python", p.query[0..p.len]);
    try std.testing.expectEqual(@as(usize, 1), try p.indices(&configuration, &catalogue, &indexes));
}

test "viewport stays still until needed; wheel, empty results and resize keep selection valid" {
    var p: Picker = .{};
    for (0..6) |selected| {
        p.list.selected = selected;
        p.reveal(100, 10);
        try std.testing.expectEqual(@as(usize, 0), p.list.first);
    }
    p.list.selected = 10;
    p.reveal(100, 10);
    try std.testing.expectEqual(@as(usize, 1), p.list.first);
    p.list.hovered = 8;
    p.scroll(8, 100, 10);
    try std.testing.expectEqual(@as(usize, 9), p.list.first);
    try std.testing.expectEqual(@as(usize, 10), p.list.selected);
    try std.testing.expectEqual(@as(?usize, null), p.list.hovered);
    p.scroll(1000, 100, 10);
    try std.testing.expectEqual(@as(usize, 90), p.list.first);
    p.reveal(100, 4);
    try std.testing.expect(p.list.selected >= p.list.first and p.list.selected < p.list.first + 4);
    p.scroll(-1000, 0, 0);
    p.reveal(0, 0);
    try std.testing.expectEqual(@as(usize, 0), p.list.first);
    try std.testing.expectEqual(@as(usize, 0), p.list.selected);
    const maximum: [128]u8 = @splat('a');
    try p.append(&maximum);
    try std.testing.expectError(error.PickerQueryLimit, p.append("b"));
    try std.testing.expectError(error.InvalidPickerText, p.append("\xff"));
    try std.testing.expectEqual(@as(usize, 128), p.len);
    p.erase(true);
    try p.append("é");
    p.erase(false);
    try std.testing.expectEqual(@as(usize, 0), p.len);
}

test "a full catalogue stays bounded and keeps exact launch indexes through filtering" {
    var configuration = config.Config.defaults(std.testing.allocator);
    defer configuration.deinit();
    var catalogue: discovery.Catalogue = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer catalogue.arena.deinit();
    for (&catalogue.entries) |*entry| entry.* = .{ .kind = .ssh, .recipe = .{ .name = "host" } };
    catalogue.count = discovery.limit;
    var p: Picker = .{ .profile = true, .filter = .remote };
    var indexes: [limit]usize = undefined;
    try p.append("host");
    try std.testing.expectEqual(@as(usize, discovery.limit), try p.indices(&configuration, &catalogue, &indexes));
    for (indexes[0..discovery.limit], 1..) |index, expected| try std.testing.expectEqual(expected, index);
    p.list.first = 500;
    p.scroll(1, 0, 8);
    try std.testing.expectEqual(@as(usize, 0), p.list.first);
    for (0..labels.len) |_| p.cycle(false);
    try std.testing.expectEqual(Filter.remote, p.filter);
    try std.testing.expectEqualStrings("host", p.query[0..p.len]);
}

test "palette caret inserts and deletes inside UTF8 text without splitting codepoints or overflowing" {
    var p: Picker = .{};
    try p.append("a界z");
    p.moveCursor(-1);
    p.moveCursor(-1);
    try std.testing.expectEqual(@as(usize, 1), p.edit.cursor);
    try p.append("é");
    try std.testing.expectEqualStrings("aé界z", p.query[0..p.len]);
    p.erase(false);
    try std.testing.expectEqualStrings("a界z", p.query[0..p.len]);
    p.delete();
    try std.testing.expectEqualStrings("az", p.query[0..p.len]);
    try p.append("界");
    try std.testing.expectEqualStrings("a界z", p.query[0..p.len]);
    p.edit.cursor = 0;
    p.moveCursor(-1);
    p.erase(false);
    try std.testing.expectEqual(@as(usize, 0), p.edit.cursor);
    p.edit.cursor = p.len;
    p.moveCursor(1);
    p.delete();
    try std.testing.expectEqualStrings("a界z", p.query[0..p.len]);
    const too_long: [128]u8 = @splat('x');
    try std.testing.expectError(error.PickerQueryLimit, p.append(&too_long));
    try std.testing.expectEqual(@as(usize, 5), p.edit.cursor);
    try std.testing.expectEqualStrings("a界z", p.query[0..p.len]);
    try std.testing.expectEqual(@as(f32, 80), p.revealCursor(100, 100, 20));
    try std.testing.expectEqual(@as(f32, 0), p.revealCursor(0, 100, 20));
    p.erase(true);
    try std.testing.expectEqual(@as(usize, 0), p.edit.cursor);
}
