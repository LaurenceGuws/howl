const std = @import("std");
const config = @import("config.zig");
const bindings = @import("keybindings.zig");

/// Qualified settings groups; every mutable field uses the same bounded editor.
pub const Page = enum { startup, interaction, appearance, colors, mappings, defaults, profiles };
/// Human titles in stable sidebar order.
pub const titles = [_][]const u8{ "Startup", "Interaction", "Appearance", "Color schemes", "Mappings", "Profiles", "Edit profile" };
/// Maximum derived rows for six custom profiles, sixteen environment pairs each and the mapping registry.
pub const row_limit = 416;
/// Editable custom-profile fields; built-in profiles must first be duplicated.
pub const ProfileField = enum { name, shell, command, cwd, font_pixels };
/// One catalogue index and exact custom-profile field.
pub const ProfileTarget = struct { index: u8, field: ProfileField };
/// One bounded environment row and its name/value field.
pub const EnvironmentTarget = struct { profile: u8, index: u8, name: bool };
/// Exact setting or owned catalogue operation; no terminal state enters an editor.
pub const Target = union(enum) {
    default_font,
    font_family,
    default_profile,
    theme,
    font: u8,
    binding: u8,
    profile: ProfileTarget,
    environment: EnvironmentTarget,
    set_default: u8,
    add_profile,
    clone_profile: u8,
    delete_profile: u8,
    add_environment: u8,
    delete_environment: struct { profile: u8, index: u8 },
    move_environment: struct { profile: u8, index: u8, delta: i8 },
    information: []const u8,
};
/// A borrowed derived row; rebuilt after every accepted configuration replacement.
pub const Row = struct {
    page: Page,
    label: []const u8,
    scope: []const u8 = "",
    target: Target,

    /// Reads a field without allocating or exposing mutable configuration storage.
    pub fn text(self: Row, current: *const config.Config, buffer: []u8) ![]const u8 {
        const value = current.value;
        return switch (self.target) {
            .default_font => try std.fmt.bufPrint(buffer, "{d}", .{value.terminal_font_pixels}),
            .default_profile => (try current.profile(try current.defaultProfile())).id,
            .theme => value.app_theme,
            .font => |index| if (index < 6) value.font.paths()[index] else error.InvalidSetting,
            .binding => |index| blk: {
                if (index >= bindings.definitions.len) return error.InvalidSetting;
                for (value.keybindings) |entry| if (std.mem.eql(u8, entry.action, bindings.definitions[index].id)) break :blk entry.shortcut;
                break :blk bindings.definitions[index].default_shortcut;
            },
            .profile => |field| blk: {
                const recipe = try current.profile(field.index);
                break :blk switch (field.field) {
                    .font_pixels => if (recipe.font_pixels == 0) "" else try std.fmt.bufPrint(buffer, "{d}", .{recipe.font_pixels}),
                    inline else => |tag| @field(recipe, @tagName(tag)),
                };
            },
            .environment => |field| blk: {
                const recipe = try current.profile(field.profile);
                if (field.index >= recipe.environment.len) return error.InvalidSetting;
                const entry = recipe.environment[field.index];
                break :blk if (field.name) entry.name else entry.value;
            },
            .information => |message| message,
            .set_default => |index| if (index == try current.defaultProfile()) "Default" else "Set default",
            else => "",
        };
    }
    /// Only actual text fields enter the edit buffer; catalogue operations are explicit rows.
    pub fn editable(self: Row) bool {
        return switch (self.target) {
            .default_font, .default_profile, .theme, .font, .binding, .profile, .environment => true,
            else => false,
        };
    }
};
const Builder = struct {
    out: *[row_limit]Row,
    count: u16 = 0,
    fn add(self: *Builder, row: Row) error{SettingsRowLimit}!void {
        if (self.count == self.out.len) return error.SettingsRowLimit;
        self.out[self.count] = row;
        self.count += 1;
    }
};
/// Derives bounded rows from one validated live config; it retains no configuration pointers.
pub fn rows(current: *const config.Config, out: *[row_limit]Row) !u16 {
    var b: Builder = .{ .out = out };
    try b.add(.{ .page = .startup, .label = "Default profile", .target = .default_profile });
    try b.add(.{ .page = .interaction, .label = "Terminal input", .target = .{ .information = "Negotiated keys/mouse, owned input, local IME and stable history" } });
    try b.add(.{ .page = .appearance, .label = "Installed font family", .target = .font_family });
    try b.add(.{ .page = .appearance, .label = "Default terminal font size (8–48)", .target = .default_font });
    const font_labels = [_][]const u8{ "Regular font", "Italic font", "Bold font", "Bold italic font", "Arabic fallback", "CJK fallback" };
    for (font_labels, 0..) |label, index| try b.add(.{ .page = .appearance, .label = label, .target = .{ .font = @intCast(index) } });
    try b.add(.{ .page = .colors, .label = "Application theme", .target = .theme });
    for (bindings.definitions, 0..) |definition, index| try b.add(.{ .page = .mappings, .label = definition.label, .target = .{ .binding = @intCast(index) } });
    for (0..current.profileCount()) |number| {
        const index: u8 = @intCast(number);
        const recipe = try current.profile(index);
        try b.add(.{ .page = .defaults, .label = recipe.name, .scope = recipe.id, .target = .{ .set_default = index } });
        try b.add(.{ .page = .profiles, .label = "Duplicate profile", .scope = recipe.name, .target = .{ .clone_profile = index } });
        if (index == 0) {
            for ([_][]const u8{ "Name", "Shell", "Command", "Working directory", "Font size" }, [_][]const u8{ recipe.name, "Inherited login shell", "Interactive shell", "Inherited directory", "Default" }) |label, value| {
                try b.add(.{ .page = .profiles, .label = label, .scope = recipe.name, .target = .{ .information = value } });
            }
            continue;
        }
        for ([_]ProfileField{ .name, .shell, .command, .cwd, .font_pixels }) |tag| {
            try b.add(.{ .page = .profiles, .label = switch (tag) {
                .name => "Name",
                .shell => "Shell",
                .command => "Command",
                .cwd => "Working directory",
                .font_pixels => "Font size (blank inherits)",
            }, .scope = recipe.name, .target = .{ .profile = .{ .index = index, .field = tag } } });
        }
        for (recipe.environment, 0..) |entry, env_index| {
            try b.add(.{ .page = .profiles, .label = "Environment name", .scope = recipe.name, .target = .{ .environment = .{ .profile = index, .index = @intCast(env_index), .name = true } } });
            try b.add(.{ .page = .profiles, .label = "Environment value", .scope = entry.name, .target = .{ .environment = .{ .profile = index, .index = @intCast(env_index), .name = false } } });
            try b.add(.{ .page = .profiles, .label = "Delete environment entry", .scope = entry.name, .target = .{ .delete_environment = .{ .profile = index, .index = @intCast(env_index) } } });
        }
        try b.add(.{ .page = .profiles, .label = "Add environment entry", .scope = recipe.name, .target = .{ .add_environment = index } });
        try b.add(.{ .page = .profiles, .label = "Delete profile", .scope = recipe.name, .target = .{ .delete_profile = index } });
    }
    try b.add(.{ .page = .profiles, .label = "New launch profile", .target = .add_profile });
    return b.count;
}
/// Produces a fully validated owned candidate; failure leaves the live config and source file untouched.
pub fn change(current: *const config.Config, io: std.Io, target: Target, text: []const u8) !config.Config {
    var value = current.value;
    var profiles: [6]config.Profile = @splat(.{});
    var environment: [16]config.Environment = @splat(.{});
    var overrides: [bindings.definitions.len]bindings.Override = @splat(.{});
    var updated_bindings = try bindings.Bindings.fromOverrides(value.keybindings);
    var generated: [128]u8 = undefined;
    if (value.profiles.len > profiles.len) return error.ProfileLimit;
    @memcpy(profiles[0..value.profiles.len], value.profiles);
    switch (target) {
        .default_font => value.terminal_font_pixels = try std.fmt.parseInt(i32, text, 10),
        .default_profile => value.default_profile = text,
        .theme => value.app_theme = text,
        .font => |index| {
            if (index >= 6) return error.InvalidSetting;
            switch (index) {
                0 => value.font.regular = text,
                1 => value.font.italic = text,
                2 => value.font.bold = text,
                3 => value.font.bold_italic = text,
                4 => value.font.fallback = text,
                5 => value.font.secondary_fallback = text,
                else => return error.InvalidSetting,
            }
        },
        .binding => |index| {
            try updated_bindings.set(index, text);
            var count: usize = 0;
            for (&updated_bindings.rows, bindings.definitions) |*binding, definition| {
                if (!binding.customized) continue;
                overrides[count] = .{ .action = definition.id, .shortcut = binding.text[0..binding.len] };
                count += 1;
            }
            value.keybindings = overrides[0..count];
        },
        .set_default => |index| value.default_profile = (try current.profile(index)).id,
        .profile => |field| {
            const recipe = try mutableProfile(&profiles, value.profiles.len, field.index);
            switch (field.field) {
                .font_pixels => recipe.font_pixels = if (text.len == 0) 0 else try std.fmt.parseInt(i32, text, 10),
                inline else => |tag| @field(recipe, @tagName(tag)) = text,
            }
            value.profiles = profiles[0..value.profiles.len];
        },
        .environment => |field| {
            const recipe = try mutableProfile(&profiles, value.profiles.len, field.profile);
            if (field.index >= recipe.environment.len) return error.InvalidSetting;
            @memcpy(environment[0..recipe.environment.len], recipe.environment);
            if (field.name) environment[field.index].name = text else environment[field.index].value = text;
            recipe.environment = environment[0..recipe.environment.len];
            value.profiles = profiles[0..value.profiles.len];
        },
        .add_environment => |index| {
            const recipe = try mutableProfile(&profiles, value.profiles.len, index);
            if (recipe.environment.len == environment.len) return error.InvalidProfileEnvironment;
            @memcpy(environment[0..recipe.environment.len], recipe.environment);
            const name = try environmentName(recipe.environment, &generated);
            environment[recipe.environment.len] = .{ .name = name, .value = "" };
            recipe.environment = environment[0 .. recipe.environment.len + 1];
            value.profiles = profiles[0..value.profiles.len];
        },
        .delete_environment => |field| {
            const recipe = try mutableProfile(&profiles, value.profiles.len, field.profile);
            if (field.index >= recipe.environment.len) return error.InvalidSetting;
            @memcpy(environment[0..recipe.environment.len], recipe.environment);
            const count = recipe.environment.len - 1;
            std.mem.copyForwards(config.Environment, environment[field.index..count], environment[field.index + 1 .. count + 1]);
            recipe.environment = environment[0..count];
            value.profiles = profiles[0..value.profiles.len];
        },
        .move_environment => |field| {
            const recipe = try mutableProfile(&profiles, value.profiles.len, field.profile);
            const destination = @as(i16, field.index) + field.delta;
            if (field.index >= recipe.environment.len or destination < 0 or destination >= recipe.environment.len) return error.InvalidSetting;
            @memcpy(environment[0..recipe.environment.len], recipe.environment);
            std.mem.swap(config.Environment, &environment[field.index], &environment[@intCast(destination)]);
            recipe.environment = environment[0..recipe.environment.len];
            value.profiles = profiles[0..value.profiles.len];
        },
        .add_profile, .clone_profile => {
            if (value.profiles.len == profiles.len) return error.ProfileLimit;
            const recipe = if (target == .clone_profile) try current.profile(target.clone_profile) else config.Profile{ .name = "New profile" };
            profiles[value.profiles.len] = recipe;
            profiles[value.profiles.len].id = try profileID(current, &generated);
            value.profiles = profiles[0 .. value.profiles.len + 1];
        },
        .delete_profile => |index| {
            if (index == 0 or index - 1 >= value.profiles.len) return error.InvalidSetting;
            if (index == try current.defaultProfile()) value.default_profile = "local";
            const count = value.profiles.len - 1;
            const retiring = index - 1;
            std.mem.copyForwards(config.Profile, profiles[retiring..count], profiles[retiring + 1 .. count + 1]);
            value.profiles = profiles[0..count];
        },
        .font_family, .information => return error.ReadOnlySetting,
    }
    return config.Config.fromValue(current.allocator, io, value);
}
fn mutableProfile(profiles: *[6]config.Profile, count: usize, index: u8) error{InvalidSetting}!*config.Profile {
    if (index == 0 or index - 1 >= count) return error.InvalidSetting;
    return &profiles[index - 1];
}
fn profileID(current: *const config.Config, buffer: []u8) ![]const u8 {
    for (1..10) |number| {
        const id = try std.fmt.bufPrint(buffer, "profile_{d}", .{number});
        var found = false;
        for (current.value.profiles) |recipe| if (std.mem.eql(u8, recipe.id, id)) {
            found = true;
            break;
        };
        if (!found) return id;
    }
    return error.ProfileLimit;
}
fn environmentName(entries: []const config.Environment, buffer: []u8) ![]const u8 {
    for (1..18) |number| {
        const name = try std.fmt.bufPrint(buffer, "VAR_{d}", .{number});
        var found = false;
        for (entries) |entry| if (std.mem.eql(u8, entry.name, name)) {
            found = true;
            break;
        };
        if (!found) return name;
    }
    return error.InvalidProfileEnvironment;
}
/// Small edit/search state. The live configuration owns row values; only committed candidates allocate.
pub const Editor = struct {
    page: Page = .startup,
    selected: usize = 0,
    profile: u8 = 0,
    content_focus: bool = false,
    search: bool = false,
    query: [128]u8 = @splat(0),
    query_len: usize = 0,
    editing: ?Target = null,
    recording: bool = false,
    select_all: bool = false,
    buffer: [4096]u8 = @splat(0),
    len: usize = 0,
    delete_pending: ?u8 = null,

    /// Filters global search or the current page without retaining borrowed rows.
    pub fn indices(self: *const Editor, supplied: []const Row, out: *[row_limit]u16) usize {
        var count: usize = 0;
        for (supplied, 0..) |row, index| {
            if (!self.search and row.page != self.page) continue;
            if (!self.search and self.page == .profiles) {
                const profile_index: ?u8 = switch (row.target) {
                    .information => 0,
                    .profile => |field| field.index,
                    .environment => |field| field.profile,
                    .add_environment => |index_value| index_value,
                    .delete_environment => |field| field.profile,
                    else => null,
                };
                if (profile_index == null or profile_index.? != self.profile) continue;
            }
            const query = self.query[0..self.query_len];
            if (self.search and !contains(row.label, query) and !contains(row.scope, query)) continue;
            out[count] = @intCast(index);
            count += 1;
        }
        return count;
    }
    /// Copies one editable value, initially selected, before SDL text events can change it.
    pub fn begin(self: *Editor, row: Row, current: *const config.Config) !void {
        if (!row.editable()) return error.ReadOnlySetting;
        var scratch: [32]u8 = undefined;
        const value = try row.text(current, &scratch);
        if (value.len >= self.buffer.len) return error.SettingsTextLimit;
        @memcpy(self.buffer[0..value.len], value);
        self.len = value.len;
        self.editing = row.target;
        self.select_all = value.len != 0;
        self.recording = false;
    }
    /// Appends one complete valid UTF-8 commit atomically, bounded independently of field validation.
    pub fn append(self: *Editor, text: []const u8) error{ SettingsTextLimit, InvalidSettingsText }!void {
        if (self.editing != null) {
            const start = if (self.select_all) 0 else self.len;
            if (text.len >= self.buffer.len - start) return error.SettingsTextLimit;
        } else if (self.search) {
            if (text.len > self.query.len - self.query_len) return error.SettingsTextLimit;
        } else return;
        if (!std.unicode.utf8ValidateSlice(text) or std.mem.indexOfScalar(u8, text, 0) != null) return error.InvalidSettingsText;
        if (self.editing != null) {
            const start = if (self.select_all) 0 else self.len;
            if (text.len >= self.buffer.len - start) return error.SettingsTextLimit;
            @memcpy(self.buffer[start..][0..text.len], text);
            self.len = start + text.len;
            self.select_all = false;
        } else if (self.search) {
            if (text.len > self.query.len - self.query_len) return error.SettingsTextLimit;
            @memcpy(self.query[self.query_len..][0..text.len], text);
            self.query_len += text.len;
            self.selected = 0;
            self.delete_pending = null;
        }
    }
    /// Removes one complete trailing UTF-8 scalar, or the selected complete field.
    pub fn backspace(self: *Editor) void {
        if (self.editing != null) {
            if (self.select_all) self.len = 0 else trim(&self.buffer, &self.len);
            self.select_all = false;
        } else if (self.search) {
            trim(&self.query, &self.query_len);
            self.selected = 0;
        }
    }
    /// Retires the edit transaction; it never touches a terminal or a saved file.
    pub fn cancel(self: *Editor) void {
        self.editing = null;
        self.recording = false;
        self.select_all = false;
        self.len = 0;
        self.delete_pending = null;
    }
};
fn trim(bytes: []const u8, len: *usize) void {
    if (len.* == 0) return;
    len.* -= 1;
    while (len.* != 0 and bytes[len.*] & 0xc0 == 0x80) len.* -= 1;
}
fn contains(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    for (0..haystack.len - needle.len + 1) |index| if (std.ascii.eqlIgnoreCase(haystack[index..][0..needle.len], needle)) return true;
    return false;
}

fn accept(current: *config.Config, target: Target, text: []const u8) !void {
    var candidate = try change(current, std.testing.io, target, text);
    std.mem.swap(config.Config, current, &candidate);
    candidate.deinit();
}
test "settings candidates own generated recipes, validate hostile edits and preserve the accepted source" {
    var current = config.Config.defaults(std.testing.allocator);
    defer current.deinit();
    try accept(&current, .add_profile, "");
    try accept(&current, .{ .profile = .{ .index = 1, .field = .name } }, "Build shell");
    try accept(&current, .{ .profile = .{ .index = 1, .field = .command } }, "exec /bin/sh");
    try accept(&current, .{ .add_environment = 1 }, "");
    try accept(&current, .{ .add_environment = 1 }, "");
    try accept(&current, .{ .environment = .{ .profile = 1, .index = 1, .name = false } }, "exact");
    try accept(&current, .{ .move_environment = .{ .profile = 1, .index = 1, .delta = -1 } }, "");
    try std.testing.expectEqualStrings("exact", current.value.profiles[0].environment[0].value);
    try std.testing.expectError(error.DuplicateEnvironment, change(&current, std.testing.io, .{ .environment = .{ .profile = 1, .index = 0, .name = true } }, "VAR_1"));
    try std.testing.expectError(error.InvalidFontSize, change(&current, std.testing.io, .default_font, "49"));
    try std.testing.expectError(error.InvalidSetting, change(&current, std.testing.io, .{ .delete_profile = 0 }, ""));
    try std.testing.expectEqualStrings("Build shell", current.value.profiles[0].name);
    try accept(&current, .{ .clone_profile = 1 }, "");
    try std.testing.expectEqualStrings("profile_2", current.value.profiles[1].id);
    try std.testing.expectEqualStrings("exec /bin/sh", current.value.profiles[1].command);
    try accept(&current, .{ .set_default = 1 }, "");
    try accept(&current, .{ .delete_profile = 1 }, "");
    try std.testing.expectEqual(@as(u8, 0), try current.defaultProfile());
}
test "settings text and global search stay bounded and preserve complete Unicode input" {
    var current = config.Config.defaults(std.testing.allocator);
    defer current.deinit();
    var all: [row_limit]Row = undefined;
    const count = try rows(&current, &all);
    var indices: [row_limit]u16 = undefined;
    var editor: Editor = .{ .search = true };
    try editor.append("Regular font");
    try std.testing.expectEqual(@as(usize, 1), editor.indices(all[0..count], &indices));
    try editor.begin(all[indices[0]], &current);
    try editor.append("/é");
    editor.backspace();
    try std.testing.expectEqualStrings("/", editor.buffer[0..editor.len]);
    const before = editor.len;
    try std.testing.expectError(error.InvalidSettingsText, editor.append("\xff"));
    try std.testing.expectEqual(before, editor.len);
    const huge: [4096]u8 = @splat('a');
    try std.testing.expectError(error.SettingsTextLimit, editor.append(&huge));
    try std.testing.expectEqual(before, editor.len);
    editor.cancel();
    try std.testing.expect(editor.editing == null);
}
fn allocationProof(a: std.mem.Allocator) !void {
    var current = config.Config.defaults(a);
    defer current.deinit();
    var candidate = try change(&current, std.testing.io, .{ .clone_profile = 0 }, "");
    defer candidate.deinit();
    var mapped = try change(&candidate, std.testing.io, .{ .binding = 0 }, "Ctrl+Alt+T");
    defer mapped.deinit();
}
test "settings candidate construction retires every partial allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProof, .{});
}
test "maximum saved catalogues fit the settings row budget with all editable environment pairs" {
    var env_names: [16][32]u8 = undefined;
    var environment: [16]config.Environment = undefined;
    for (&environment, &env_names, 0..) |*entry, *buffer, index| entry.* = .{ .name = try std.fmt.bufPrint(buffer, "VAR_{d}", .{index}), .value = "value" };
    var profiles: [6]config.Profile = undefined;
    for (&profiles, [_][]const u8{ "a", "b", "c", "d", "e", "f" }) |*recipe, id| recipe.* = .{ .id = id, .name = id, .environment = &environment };
    var schema = config.Config.defaults(std.testing.allocator).value;
    schema.profiles = &profiles;
    var current = try config.Config.fromValue(std.testing.allocator, std.testing.io, schema);
    defer current.deinit();
    var all: [row_limit]Row = undefined;
    const count = try rows(&current, &all);
    try std.testing.expect(count < row_limit);
    var names: usize = 0;
    var values: usize = 0;
    for (all[0..count]) |row| if (row.target == .environment) {
        if (row.target.environment.name) names += 1 else values += 1;
    };
    try std.testing.expectEqual(@as(usize, 96), names);
    try std.testing.expectEqual(names, values);
}

test "saved shortcut text outlives registry iteration and the previous config" {
    const c = @import("desktop");
    var candidate = owned: {
        var current = config.Config.defaults(std.testing.allocator);
        defer current.deinit();
        break :owned try change(&current, std.testing.io, .{ .binding = 0 }, "Ctrl+Alt+T");
    };
    defer candidate.deinit();
    try std.testing.expectEqualStrings("Ctrl+Alt+T", candidate.value.keybindings[0].shortcut);
    const loaded = try bindings.Bindings.fromOverrides(candidate.value.keybindings);
    try std.testing.expectEqual(@as(?usize, 0), loaded.find(c.SDLK_T, c.SDL_KMOD_LCTRL | c.SDL_KMOD_LALT));
    var second = try change(&candidate, std.testing.io, .{ .binding = 3 }, "Ctrl+Shift+G");
    defer second.deinit();
    const changed = try bindings.Bindings.fromOverrides(second.value.keybindings);
    try std.testing.expectEqual(@as(?usize, 3), changed.find(c.SDLK_G, c.SDL_KMOD_LCTRL | c.SDL_KMOD_LSHIFT));
    try std.testing.expectEqual(@as(?usize, 0), changed.find(c.SDLK_T, c.SDL_KMOD_LCTRL | c.SDL_KMOD_LALT));
}

test "profile editor shows only selected recipe while global search still finds all recipes" {
    var current = config.Config.defaults(std.testing.allocator);
    defer current.deinit();
    try accept(&current, .add_profile, "");
    try accept(&current, .add_profile, "");
    var all: [row_limit]Row = undefined;
    const count = try rows(&current, &all);
    var found: [row_limit]u16 = undefined;
    var editor: Editor = .{ .page = .profiles, .profile = 1 };
    const shown = editor.indices(all[0..count], &found);
    try std.testing.expect(shown > 0);
    for (found[0..shown]) |index_value| switch (all[index_value].target) {
        .profile => |field| try std.testing.expectEqual(@as(u8, 1), field.index),
        .add_environment => |value| try std.testing.expectEqual(@as(u8, 1), value),
        else => return error.UnexpectedProfileRow,
    };
    editor.search = true;
    const global = editor.indices(all[0..count], &found);
    try std.testing.expect(global > shown);
}
