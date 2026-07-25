//! Persistent terminal presentation properties and bounded color state.

const std = @import("std");
const Screen = @import("screen.zig").Screen;

/// Three-channel color type shared with Screen.
pub const Rgb = Screen.Rgb;

/// Default terminal foreground color.
pub const default_foreground = Rgb{ .r = 220, .g = 220, .b = 220 };
/// Default terminal background color.
pub const default_background = Rgb{ .r = 24, .g = 25, .b = 33 };

/// Owns the terminal-wide palette and dynamic presentation colors.
pub const ColorState = struct {
    foreground: Rgb = default_foreground,
    background: Rgb = default_background,
    cursor: ?Rgb = null,
    pointer_foreground: ?Rgb = null,
    pointer_background: ?Rgb = null,
    tektronix_foreground: ?Rgb = null,
    tektronix_background: ?Rgb = null,
    tektronix_cursor: ?Rgb = null,
    cursor_text: ?Rgb = null,
    selection_background: ?Rgb = null,
    selection_foreground: ?Rgb = null,
    special_palette: [5]?Rgb = @as([5]?Rgb, @splat(null)),
    palette: [256]Rgb = buildDefaultPalette(),
};

/// Stores Kitty's bounded color snapshots and initialized slot extent.
pub const ColorStack = struct {
    stack: [10]ColorState = undefined,
    len: u8 = 0,
    slot_count: u8 = 0,
};

/// Maximum retained property metadata bytes.
pub const max_metadata_bytes: u32 = 1024;
/// Maximum retained title-stack depth.
pub const title_stack_limit: u8 = 10;
/// Maximum bytes in one retained hyperlink target.
pub const hyperlink_target_max_bytes: u32 = 2 * 1024;
/// Maximum retained hyperlink identities.
pub const hyperlink_target_max_count: u32 = 4096;

/// Owns one bounded shell mark.
pub const ShellMark = struct {
    generation: u64 = 0,
    kind: u8 = 0,
    status: ?i32 = null,
    metadata: []u8 = &[_]u8{},
};

/// Owns validated shell integration identity.
pub const ShellIntegration = struct { version: u32, shell: ?[]u8 };
/// Borrows one child-reported working directory.
/// Identifies URI versus filesystem-path directory reports.
pub const WorkingDirectoryKind = enum { uri, path };
/// Borrows one child-reported working directory.
pub const WorkingDirectory = struct { kind: WorkingDirectoryKind, value: []const u8 };
/// Borrows one parsed hyperlink specification.
pub const HyperlinkSpec = struct { uri: []const u8, id: ?[]const u8 };
/// Owns one interned hyperlink target.
pub const HyperlinkTarget = struct {
    storage: []u8,
    uri_len: u16,
    /// Borrows the retained URI bytes.
    pub fn uri(self: HyperlinkTarget) []const u8 {
        return self.storage[0..self.uri_len];
    }
    /// Borrows the optional retained identity bytes.
    pub fn id(self: HyperlinkTarget) ?[]const u8 {
        if (self.storage.len == self.uri_len) return null;
        return self.storage[self.uri_len..];
    }
    /// Reports whether this target exactly matches a parsed specification.
    pub fn matches(self: HyperlinkTarget, spec: HyperlinkSpec) bool {
        if (!std.mem.eql(u8, self.uri(), spec.uri)) return false;
        const retained = self.id();
        if (retained == null or spec.id == null) return retained == null and spec.id == null;
        return std.mem.eql(u8, retained.?, spec.id.?);
    }
};

/// Property-owned bound or allocation failure.
pub const PropertyError = error{ OutOfMemory, PropertyLimit };
/// Reports title-stack mutation effects.
pub const TitleStackEffect = struct { changed: bool = false, title_changed: bool = false };

/// Owns persistent terminal properties and all allocations backing them.
pub const State = struct {
    allocator: std.mem.Allocator,
    colors: ColorState = .{},
    color_stack: ColorStack = .{},
    current_title: ?[]u8 = null,
    current_icon: ?[]u8 = null,
    working_directory: ?WorkingDirectory = null,
    remote_host: ?[]u8 = null,
    title_stack: [title_stack_limit]?[]u8 = @as([title_stack_limit]?[]u8, @splat(null)),
    title_stack_len: u8 = 0,
    shell_integration: ?ShellIntegration = null,
    shell_mark: ShellMark = .{},
    hyperlinks: std.ArrayList(HyperlinkTarget),

    /// Initializes property storage with its retained allocator.
    pub fn init(allocator: std.mem.Allocator) State {
        return .{ .allocator = allocator, .hyperlinks = .empty };
    }
    /// Releases every property allocation through the retained allocator.
    pub fn deinit(self: *State) void {
        for (self.hyperlinks.items) |target| self.allocator.free(target.storage);
        self.hyperlinks.deinit(self.allocator);
        if (self.current_title) |v| self.allocator.free(v);
        if (self.current_icon) |v| self.allocator.free(v);
        if (self.working_directory) |v| self.allocator.free(v.value);
        if (self.remote_host) |v| self.allocator.free(v);
        for (self.title_stack[0..self.title_stack_len]) |v| self.allocator.free(v.?);
        if (self.shell_integration) |v| if (v.shell) |shell| self.allocator.free(shell);
        self.allocator.free(self.shell_mark.metadata);
    }

    /// Applies terminal reset to property-owned directory and color state.
    pub fn resetTerminal(self: *State) void {
        if (self.working_directory) |value| self.allocator.free(value.value);
        self.working_directory = null;
        const palette = self.colors.palette;
        const foreground = self.colors.foreground;
        const background = self.colors.background;
        self.colors = .{};
        self.colors.palette = palette;
        self.colors.foreground = foreground;
        self.colors.background = background;
        self.color_stack = .{};
    }

    fn bounded(bytes: []const u8) PropertyError!void {
        if (bytes.len > max_metadata_bytes) return error.PropertyLimit;
    }

    /// Replaces the retained title transactionally.
    pub fn replaceTitle(self: *State, bytes: []const u8) PropertyError!bool {
        return self.replaceBytes(&self.current_title, bytes);
    }
    /// Replaces the retained icon transactionally.
    pub fn replaceIcon(self: *State, bytes: []const u8) PropertyError!bool {
        return self.replaceBytes(&self.current_icon, bytes);
    }
    /// Replaces the retained remote-host identity transactionally.
    pub fn replaceRemoteHost(self: *State, bytes: []const u8) PropertyError!bool {
        return self.replaceBytes(&self.remote_host, bytes);
    }
    fn replaceBytes(self: *State, destination: *?[]u8, bytes: []const u8) PropertyError!bool {
        try bounded(bytes);
        if (if (destination.*) |old| std.mem.eql(u8, old, bytes) else false) return false;
        const owned = try self.allocator.dupe(u8, bytes);
        if (destination.*) |old| self.allocator.free(old);
        destination.* = owned;
        return true;
    }
    /// Replaces the retained URI/path directory transactionally.
    pub fn replaceWorkingDirectory(self: *State, kind: WorkingDirectoryKind, bytes: []const u8) PropertyError!bool {
        try bounded(bytes);
        if (self.working_directory) |old| if (old.kind == kind and std.mem.eql(u8, old.value, bytes)) return false;
        const owned = try self.allocator.dupe(u8, bytes);
        if (self.working_directory) |old| self.allocator.free(old.value);
        self.working_directory = .{ .kind = kind, .value = owned };
        return true;
    }
    /// Replaces title and icon together transactionally.
    pub fn replaceTitleAndIcon(self: *State, bytes: []const u8) PropertyError!bool {
        try bounded(bytes);
        const same_title = if (self.current_title) |old| std.mem.eql(u8, old, bytes) else false;
        const same_icon = if (self.current_icon) |old| std.mem.eql(u8, old, bytes) else false;
        if (same_title and same_icon) return false;
        const title = try self.allocator.dupe(u8, bytes);
        errdefer self.allocator.free(title);
        const icon = try self.allocator.dupe(u8, bytes);
        if (self.current_title) |old| self.allocator.free(old);
        if (self.current_icon) |old| self.allocator.free(old);
        self.current_title = title;
        self.current_icon = icon;
        return true;
    }
    /// Pushes the current title into the bounded stack.
    pub fn pushTitle(self: *State) PropertyError!bool {
        const current = self.current_title orelse return false;
        if (current.len == 0) return false;
        const owned = try self.allocator.dupe(u8, current);
        if (self.title_stack_len == title_stack_limit) {
            self.allocator.free(self.title_stack[0].?);
            std.mem.copyForwards(?[]u8, self.title_stack[0 .. title_stack_limit - 1], self.title_stack[1..title_stack_limit]);
            self.title_stack[title_stack_limit - 1] = owned;
        } else {
            self.title_stack[self.title_stack_len] = owned;
            self.title_stack_len += 1;
        }
        return true;
    }
    /// Restores and removes the most recent stacked title.
    pub fn popTitle(self: *State) TitleStackEffect {
        if (self.title_stack_len == 0) return .{};
        self.title_stack_len -= 1;
        const slot = &self.title_stack[self.title_stack_len];
        const restored = slot.*.?;
        slot.* = null;
        const changed = if (self.current_title) |old| !std.mem.eql(u8, old, restored) else true;
        if (self.current_title) |old| self.allocator.free(old);
        self.current_title = restored;
        return .{ .changed = true, .title_changed = changed };
    }

    /// Replaces shell integration identity transactionally.
    pub fn replaceShellIntegration(self: *State, version: u32, shell_value: ?[]const u8) PropertyError!bool {
        if (shell_value) |value| if (value.len > 32) return error.PropertyLimit;
        if (self.shell_integration) |old| {
            const same_shell = if (old.shell) |a| if (shell_value) |b| std.mem.eql(u8, a, b) else false else shell_value == null;
            if (old.version == version and same_shell) return false;
        }
        const shell = if (shell_value) |value| try self.allocator.dupe(u8, value) else null;
        if (self.shell_integration) |old| if (old.shell) |value| self.allocator.free(value);
        self.shell_integration = .{ .version = version, .shell = shell };
        return true;
    }

    /// Replaces the latest shell mark after validating its bounded metadata.
    pub fn replaceShellMark(self: *State, kind: u8, status: ?i32, metadata: []const u8) PropertyError!void {
        try bounded(metadata);
        if (self.shell_mark.generation == std.math.maxInt(u64)) return error.PropertyLimit;
        const owned = try self.allocator.dupe(u8, metadata);
        self.allocator.free(self.shell_mark.metadata);
        self.shell_mark = .{ .generation = self.shell_mark.generation + 1, .kind = kind, .status = status, .metadata = owned };
    }

    /// Interns one bounded hyperlink and returns its stable one-based identity.
    pub fn internHyperlink(self: *State, spec: HyperlinkSpec) PropertyError!u32 {
        for (self.hyperlinks.items, 0..) |existing, index| if (existing.matches(spec)) return @intCast(index + 1);
        const id_len = if (spec.id) |id| id.len else 0;
        const storage_len = std.math.add(usize, spec.uri.len, id_len) catch return error.PropertyLimit;
        if (storage_len > hyperlink_target_max_bytes or spec.uri.len > std.math.maxInt(u16) or self.hyperlinks.items.len >= hyperlink_target_max_count)
            return error.PropertyLimit;
        const storage = try self.allocator.alloc(u8, storage_len);
        @memcpy(storage[0..spec.uri.len], spec.uri);
        if (spec.id) |id| @memcpy(storage[spec.uri.len..], id);
        self.hyperlinks.append(self.allocator, .{ .storage = storage, .uri_len = @intCast(spec.uri.len) }) catch |err| {
            self.allocator.free(storage);
            return err;
        };
        return @intCast(self.hyperlinks.items.len);
    }

    /// Borrows the URI for a stable one-based hyperlink identity.
    pub fn hyperlinkUriForId(self: *const State, id: u32) ?[]const u8 {
        if (id == 0 or id > self.hyperlinks.items.len) return null;
        return self.hyperlinks.items[id - 1].uri();
    }
    /// Saves the current colors into the requested bounded Kitty slot.
    pub fn pushColor(self: *State, index: u16) bool {
        const stack = &self.color_stack;
        const colors = &self.colors;
        if (index > stack.stack.len) return false;
        if (index != 0) {
            const required: u8 = @intCast(index);
            const expanded = required > stack.slot_count;
            while (stack.slot_count < required) : (stack.slot_count += 1) stack.stack[stack.slot_count] = .{};
            if (!expanded and std.meta.eql(stack.stack[required - 1], colors.*)) return false;
            stack.stack[required - 1] = colors.*;
            return true;
        }
        if (stack.len == stack.slot_count and stack.slot_count < stack.stack.len) stack.slot_count += 1;
        if (stack.len == stack.stack.len) {
            std.mem.copyForwards(ColorState, stack.stack[0 .. stack.stack.len - 1], stack.stack[1..]);
            stack.len -= 1;
        }
        stack.stack[stack.len] = colors.*;
        stack.len += 1;
        return true;
    }

    /// Restores colors from the requested bounded Kitty slot.
    pub fn popColor(self: *State, index: u16) bool {
        const stack = &self.color_stack;
        const colors = &self.colors;
        if (index > stack.stack.len) return false;
        if (index != 0) {
            const slot: u8 = @intCast(index - 1);
            if (slot >= stack.slot_count) return false;
            if (std.meta.eql(colors.*, stack.stack[slot])) return false;
            colors.* = stack.stack[slot];
            return true;
        }
        if (stack.len == 0) return false;
        stack.len -= 1;
        colors.* = stack.stack[stack.len];
        stack.stack[stack.len] = .{};
        return true;
    }
};

fn buildDefaultPalette() [256]Rgb {
    @setEvalBranchQuota(4096);
    var palette: [256]Rgb = undefined;
    var idx: u16 = 0;
    while (idx < 256) : (idx += 1) palette[idx] = paletteColor(@intCast(idx));
    return palette;
}

fn paletteColor(idx: u8) Rgb {
    if (idx < 16) return paletteAnsi16Color(idx);
    if (idx < 232) {
        const n = idx - 16;
        return .{ .r = cubeComponent(n / 36), .g = cubeComponent((n / 6) % 6), .b = cubeComponent(n % 6) };
    }
    const gray: u8 = 8 + (idx - 232) * 10;
    return .{ .r = gray, .g = gray, .b = gray };
}

fn cubeComponent(value: u8) u8 {
    return if (value == 0) 0 else 55 + value * 40;
}

fn paletteAnsi16Color(idx: u8) Rgb {
    return switch (idx) {
        0 => .{ .r = 0, .g = 0, .b = 0 },
        1 => .{ .r = 205, .g = 49, .b = 49 },
        2 => .{ .r = 13, .g = 188, .b = 121 },
        3 => .{ .r = 229, .g = 229, .b = 16 },
        4 => .{ .r = 36, .g = 114, .b = 200 },
        5 => .{ .r = 188, .g = 63, .b = 188 },
        6 => .{ .r = 17, .g = 168, .b = 205 },
        7 => .{ .r = 229, .g = 229, .b = 229 },
        8 => .{ .r = 102, .g = 102, .b = 102 },
        9 => .{ .r = 241, .g = 76, .b = 76 },
        10 => .{ .r = 35, .g = 209, .b = 139 },
        11 => .{ .r = 245, .g = 245, .b = 67 },
        12 => .{ .r = 59, .g = 142, .b = 234 },
        13 => .{ .r = 214, .g = 112, .b = 214 },
        14 => .{ .r = 41, .g = 184, .b = 219 },
        else => .{ .r = 255, .g = 255, .b = 255 },
    };
}

test "color stack is bounded and restores exact state" {
    var state = State.init(std.testing.allocator);
    defer state.deinit();
    try std.testing.expect(state.pushColor(0));
    state.colors.foreground = .{ .r = 1, .g = 2, .b = 3 };
    try std.testing.expect(state.popColor(0));
    try std.testing.expectEqual(default_foreground, state.colors.foreground);
    try std.testing.expect(!state.popColor(0));
}

test "property state cleanup uses retained allocator" {
    var state = State.init(std.testing.allocator);
    state.current_title = try std.testing.allocator.dupe(u8, "title");
    state.remote_host = try std.testing.allocator.dupe(u8, "host");
    state.hyperlinks.append(std.testing.allocator, .{
        .storage = try std.testing.allocator.dupe(u8, "uri"),
        .uri_len = 3,
    }) catch |err| {
        state.deinit();
        return err;
    };
    state.deinit();
}

test "property replacements and hyperlink identities are transactional" {
    var state = State.init(std.testing.allocator);
    defer state.deinit();
    try std.testing.expect(try state.replaceTitle("one"));
    try std.testing.expect(!try state.replaceTitle("one"));
    try std.testing.expect(try state.replaceTitleAndIcon("two"));
    try std.testing.expectEqualStrings("two", state.current_title.?);
    try std.testing.expectEqualStrings("two", state.current_icon.?);
    const first = try state.internHyperlink(.{ .uri = "https://one.example", .id = null });
    const second = try state.internHyperlink(.{ .uri = "https://two.example", .id = "two" });
    try std.testing.expectEqual(@as(u32, 1), first);
    try std.testing.expectEqual(@as(u32, 2), second);
    try std.testing.expectEqualStrings("https://one.example", state.hyperlinkUriForId(first).?);
    const oversized = try std.testing.allocator.alloc(u8, max_metadata_bytes + 1);
    defer std.testing.allocator.free(oversized);
    @memset(oversized, 'x');
    try std.testing.expectError(error.PropertyLimit, state.replaceTitle(oversized));
}

test "terminal reset clears property-owned transient state" {
    var state = State.init(std.testing.allocator);
    defer state.deinit();
    try std.testing.expect(try state.replaceTitle("title"));
    try std.testing.expect(try state.replaceIcon("icon"));
    try std.testing.expect(try state.replaceRemoteHost("host"));
    try std.testing.expect(try state.replaceWorkingDirectory(.path, "/tmp/howl"));
    try std.testing.expect(try state.replaceShellIntegration(1, "zsh"));
    try state.replaceShellMark('A', 0, "mark");
    try std.testing.expect(try state.pushTitle());
    const link_id = try state.internHyperlink(.{ .uri = "https://howl.example", .id = null });
    const palette = state.colors.palette;
    state.colors.foreground = .{ .r = 1, .g = 2, .b = 3 };
    state.colors.background = .{ .r = 4, .g = 5, .b = 6 };
    state.colors.cursor = .{ .r = 7, .g = 8, .b = 9 };
    state.colors.special_palette[0] = .{ .r = 10, .g = 11, .b = 12 };
    const foreground = state.colors.foreground;
    const background = state.colors.background;
    try std.testing.expect(state.pushColor(0));
    state.resetTerminal();
    try std.testing.expectEqual(@as(?WorkingDirectory, null), state.working_directory);
    try std.testing.expectEqual(@as(u8, 0), state.color_stack.len);
    try std.testing.expectEqual(@as(u8, 0), state.color_stack.slot_count);
    try std.testing.expectEqual(palette, state.colors.palette);
    try std.testing.expectEqual(foreground, state.colors.foreground);
    try std.testing.expectEqual(background, state.colors.background);
    try std.testing.expectEqual(@as(?Rgb, null), state.colors.cursor);
    try std.testing.expectEqual(@as(?Rgb, null), state.colors.special_palette[0]);
    try std.testing.expectEqualStrings("title", state.current_title.?);
    try std.testing.expectEqualStrings("icon", state.current_icon.?);
    try std.testing.expectEqualStrings("host", state.remote_host.?);
    try std.testing.expectEqual(@as(u32, 1), state.shell_integration.?.version);
    try std.testing.expectEqualStrings("zsh", state.shell_integration.?.shell.?);
    try std.testing.expectEqualStrings("mark", state.shell_mark.metadata);
    try std.testing.expectEqual(@as(u8, 1), state.title_stack_len);
    try std.testing.expectEqual(@as(u32, 1), link_id);
    try std.testing.expectEqualStrings("https://howl.example", state.hyperlinkUriForId(link_id).?);
}
