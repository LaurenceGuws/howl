//! App-owned search and navigation. No I/O, retained catalogue or launch ownership.
const std = @import("std");
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
    cursor: usize = 0,
    query_scroll: f32 = 0,
    selected: usize = 0,
    first: usize = 0,
    hovered: ?usize = null,
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
            if (!self.profile and keybindings.definitions[i].target != .action) continue;
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
        self.selected = 0;
        self.first = 0;
        self.hovered = null;
    }
    /// Accepts only complete UTF-8 events and leaves the query untouched on failure.
    pub fn append(self: *Picker, bytes: []const u8) error{ InvalidPickerText, PickerQueryLimit }!void {
        if (!std.unicode.utf8ValidateSlice(bytes)) return error.InvalidPickerText;
        if (bytes.len > self.query.len - self.len) return error.PickerQueryLimit;
        std.mem.copyBackwards(u8, self.query[self.cursor + bytes.len .. self.len + bytes.len], self.query[self.cursor..self.len]);
        @memcpy(self.query[self.cursor..][0..bytes.len], bytes);
        self.len += bytes.len;
        self.cursor += bytes.len;
        self.reset();
    }
    /// Moves by complete UTF-8 codepoints without changing the search or list selection.
    pub fn moveCursor(self: *Picker, direction: i8) void {
        if (direction < 0 and self.cursor != 0) {
            self.cursor -= 1;
            while (self.cursor != 0 and self.query[self.cursor] & 0xc0 == 0x80) self.cursor -= 1;
        } else if (direction > 0 and self.cursor < self.len) {
            self.cursor += 1;
            while (self.cursor < self.len and self.query[self.cursor] & 0xc0 == 0x80) self.cursor += 1;
        }
    }
    /// Removes the previous codepoint, or clears the entire query when explicitly requested.
    pub fn erase(self: *Picker, all: bool) void {
        if (all) {
            self.len = 0;
            self.cursor = 0;
        } else if (self.cursor != 0) {
            const end = self.cursor;
            self.moveCursor(-1);
            std.mem.copyForwards(u8, self.query[self.cursor .. self.len - (end - self.cursor)], self.query[end..self.len]);
            self.len -= end - self.cursor;
        }
        self.reset();
    }
    /// Delete removes one complete codepoint after the caret.
    pub fn delete(self: *Picker) void {
        const start = self.cursor;
        self.moveCursor(1);
        const end = self.cursor;
        self.cursor = start;
        std.mem.copyForwards(u8, self.query[start .. self.len - (end - start)], self.query[end..self.len]);
        self.len -= end - start;
        self.reset();
    }
    /// Keeps the measured caret visible while bounding stale scroll after deletion or resize.
    pub fn revealCursor(self: *Picker, caret_width: f32, text_width: f32, width: f32) f32 {
        const available = @max(1, width);
        self.query_scroll = @min(self.query_scroll, @max(0, text_width - available));
        if (caret_width < self.query_scroll) self.query_scroll = caret_width;
        if (caret_width > self.query_scroll + available) self.query_scroll = caret_width - available;
        return self.query_scroll;
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
        const rows = @max(1, visible);
        self.selected = @min(self.selected, count -| 1);
        self.first = @min(self.first, count -| rows);
        if (self.selected < self.first) self.first = self.selected;
        if (self.selected >= self.first + rows) self.first = self.selected - rows + 1;
        if (self.hovered) |hover| if (hover < self.first or hover >= @min(count, self.first + rows)) {
            self.hovered = null;
        };
    }
    /// Scrolls the viewport independently; keeps Enter's selection inside the visible rows.
    pub fn scroll(self: *Picker, delta: i32, count: usize, visible: usize) void {
        const rows = @max(1, visible);
        self.first = @min(self.first, count -| rows);
        self.first = if (delta < 0) self.first -| @as(usize, @intCast(-@as(i64, delta))) else @min(count -| rows, self.first +| @as(usize, @intCast(delta)));
        self.selected = std.math.clamp(self.selected, self.first, @min(count -| 1, self.first + rows - 1));
        self.hovered = null;
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
        p.selected = selected;
        p.reveal(100, 10);
        try std.testing.expectEqual(@as(usize, 0), p.first);
    }
    p.selected = 10;
    p.reveal(100, 10);
    try std.testing.expectEqual(@as(usize, 1), p.first);
    p.hovered = 8;
    p.scroll(8, 100, 10);
    try std.testing.expectEqual(@as(usize, 9), p.first);
    try std.testing.expectEqual(@as(usize, 10), p.selected);
    try std.testing.expectEqual(@as(?usize, null), p.hovered);
    p.scroll(1000, 100, 10);
    try std.testing.expectEqual(@as(usize, 90), p.first);
    p.reveal(100, 4);
    try std.testing.expect(p.selected >= p.first and p.selected < p.first + 4);
    p.scroll(-1000, 0, 0);
    p.reveal(0, 0);
    try std.testing.expectEqual(@as(usize, 0), p.first);
    try std.testing.expectEqual(@as(usize, 0), p.selected);
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
    p.first = 500;
    p.scroll(1, 0, 8);
    try std.testing.expectEqual(@as(usize, 0), p.first);
    for (0..labels.len) |_| p.cycle(false);
    try std.testing.expectEqual(Filter.remote, p.filter);
    try std.testing.expectEqualStrings("host", p.query[0..p.len]);
}

test "palette caret inserts and deletes inside UTF8 text without splitting codepoints or overflowing" {
    var p: Picker = .{};
    try p.append("a界z");
    p.moveCursor(-1);
    p.moveCursor(-1);
    try std.testing.expectEqual(@as(usize, 1), p.cursor);
    try p.append("é");
    try std.testing.expectEqualStrings("aé界z", p.query[0..p.len]);
    p.erase(false);
    try std.testing.expectEqualStrings("a界z", p.query[0..p.len]);
    p.delete();
    try std.testing.expectEqualStrings("az", p.query[0..p.len]);
    try p.append("界");
    try std.testing.expectEqualStrings("a界z", p.query[0..p.len]);
    p.cursor = 0;
    p.moveCursor(-1);
    p.erase(false);
    try std.testing.expectEqual(@as(usize, 0), p.cursor);
    p.cursor = p.len;
    p.moveCursor(1);
    p.delete();
    try std.testing.expectEqualStrings("a界z", p.query[0..p.len]);
    const too_long: [128]u8 = @splat('x');
    try std.testing.expectError(error.PickerQueryLimit, p.append(&too_long));
    try std.testing.expectEqual(@as(usize, 5), p.cursor);
    try std.testing.expectEqualStrings("a界z", p.query[0..p.len]);
    try std.testing.expectEqual(@as(f32, 80), p.revealCursor(100, 100, 20));
    try std.testing.expectEqual(@as(f32, 0), p.revealCursor(0, 100, 20));
    p.erase(true);
    try std.testing.expectEqual(@as(usize, 0), p.cursor);
}
