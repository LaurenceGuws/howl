const std = @import("std");
const bindings = @import("keybindings.zig");

const file_limit = 2 * 1024 * 1024;
const allocation_limit = 4 * 1024 * 1024;

/// The exact six schema-4 optional font paths; blank fields inherit discovery.
pub const Font = struct {
    regular: []const u8 = "",
    italic: []const u8 = "",
    bold: []const u8 = "",
    bold_italic: []const u8 = "",
    fallback: []const u8 = "",
    secondary_fallback: []const u8 = "",

    /// Borrows the regular/style/Arabic/CJK recipe in its canonical ordering.
    pub fn paths(self: Font) [6][]const u8 {
        return .{ self.regular, self.italic, self.bold, self.bold_italic, self.fallback, self.secondary_fallback };
    }
};
/// Persisted inherited-environment entry; launch support remains an explicit platform capability.
pub const Environment = struct { name: []const u8 = "", value: []const u8 = "" };
/// The schema-compatible launch or direct-attachment recipe, excluding terminal state.
pub const Profile = struct {
    id: []const u8 = "",
    name: []const u8 = "",
    mode: []const u8 = "",
    shell: []const u8 = "",
    command: []const u8 = "",
    cwd: []const u8 = "",
    endpoint: []const u8 = "",
    environment: []const Environment = &.{},
    font_pixels: i32 = 0,
};
/// Persisted Server label and control-listener endpoint; no Instance identity is guessed.
pub const Server = struct { label: []const u8 = "", endpoint: []const u8 = "" };
/// Existing odin.json vocabulary; older schemas normalize without writing the source file.
pub const Schema = struct {
    schema: i16 = 0,
    terminal_font_pixels: i32 = 0,
    startup_profile: i8 = 0,
    default_profile: []const u8 = "",
    profiles: []const Profile = &.{},
    servers: []const Server = &.{},
    keybindings: []const bindings.Override = &.{},
    app_theme: []const u8 = "",
    font: Font = .{},
};

/// Exact semantic validation failures, separate from JSON, allocation and filesystem errors.
pub const ValidationError = bindings.LoadError || std.Io.Dir.AccessError || error{
    UnsupportedSchema,
    InvalidFontSize,
    InvalidStartupProfile,
    InvalidTheme,
    ProfileLimit,
    InvalidProfileID,
    DuplicateProfileID,
    InvalidProfileName,
    InvalidProfileMode,
    InvalidProfileOwnership,
    InvalidProfileText,
    InvalidProfileEnvironment,
    DuplicateEnvironment,
    InvalidDefaultProfile,
    ServerLimit,
    InvalidServer,
    DuplicateServer,
    InvalidFontPath,
};

/// A pane's owned launch/attachment recipe; saved-config replacement cannot invalidate it.
pub const Recipe = struct {
    arena: std.heap.ArenaAllocator,
    value: Profile,

    /// Validates and copies every recipe string and environment row before returning.
    pub fn copy(allocator: std.mem.Allocator, supplied: Profile) !Recipe {
        try validateProfile(supplied);
        var result: Recipe = .{ .arena = .init(allocator), .value = supplied };
        errdefer result.arena.deinit();
        const owned = result.arena.allocator();
        inline for (.{ "id", "name", "mode", "shell", "command", "cwd", "endpoint" }) |field|
            @field(result.value, field) = try owned.dupe(u8, @field(supplied, field));
        const environment = try owned.alloc(Environment, supplied.environment.len);
        for (supplied.environment, environment) |source, *destination| destination.* = .{
            .name = try owned.dupe(u8, source.name),
            .value = try owned.dupe(u8, source.value),
        };
        result.value.environment = environment;
        return result;
    }
    /// Releases the recipe only after its pane's worker and all synchronous borrowers retire.
    pub fn deinit(self: *Recipe) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

const Storage = struct {
    bytes: []u8,
    fixed: std.heap.FixedBufferAllocator,
    parsed: std.json.Parsed(Schema),
};

/// Owns every decoded string in one bounded allocation; input bytes may retire immediately.
pub const Config = struct {
    allocator: std.mem.Allocator,
    value: Schema,
    storage: ?*Storage = null,

    /// Missing files use the same built-in Home startup and fifteen-pixel font as Odin.
    pub fn defaults(allocator: std.mem.Allocator) Config {
        return .{ .allocator = allocator, .value = .{
            .schema = 4,
            .terminal_font_pixels = 15,
            .startup_profile = 0,
            .app_theme = "howl_dark",
        } };
    }
    /// Parses schema 1..4 with fixed memory, owns strings, and rejects malformed/invalid data.
    pub fn parse(allocator: std.mem.Allocator, io: std.Io, bytes: []const u8) !Config {
        if (bytes.len > file_limit) return error.ConfigFileLimit;
        const storage = try allocator.create(Storage);
        errdefer allocator.destroy(storage);
        storage.bytes = try allocator.alloc(u8, allocation_limit);
        errdefer allocator.free(storage.bytes);
        storage.fixed = .init(storage.bytes);
        storage.parsed = std.json.parseFromSlice(Schema, storage.fixed.allocator(), bytes, .{
            .allocate = .alloc_always,
            .max_value_len = 4096,
            .ignore_unknown_fields = true,
        }) catch |failure| {
            if (failure == error.OutOfMemory) return error.ConfigAllocationLimit;
            return failure;
        };
        errdefer storage.parsed.deinit();
        const value = try validate(io, storage.parsed.value);
        return .{ .allocator = allocator, .value = value, .storage = storage };
    }
    /// Reads one bounded file; only FileNotFound chooses built-in defaults.
    pub fn loadAt(allocator: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, target: []const u8) !Config {
        const bytes = dir.readFileAlloc(io, target, allocator, .limited(file_limit)) catch |failure| {
            if (failure == error.FileNotFound) return defaults(allocator);
            return failure;
        };
        defer allocator.free(bytes);
        return parse(allocator, io, bytes);
    }
    /// Resolves the existing XDG_CONFIG_HOME/howl/odin.json path without inventing a second format.
    pub fn path(allocator: std.mem.Allocator, env: *const std.process.Environ.Map) ![]u8 {
        const xdg = env.get("XDG_CONFIG_HOME") orelse "";
        const home = env.get("HOME") orelse "";
        const root = if (xdg.len != 0) xdg else home;
        if (root.len == 0) return error.ConfigHomeMissing;
        if (root.len >= 4096 or std.mem.indexOfScalar(u8, root, 0) != null) return error.ConfigPathLimit;
        const result = try std.fs.path.join(allocator, if (xdg.len != 0) &.{ root, "howl", "odin.json" } else &.{ root, ".config", "howl", "odin.json" });
        if (result.len >= 4096) {
            allocator.free(result);
            return error.ConfigPathLimit;
        }
        return result;
    }
    /// Loads the user's existing saved configuration; parse errors never become defaults.
    pub fn load(allocator: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map) !Config {
        const target = try path(allocator, env);
        defer allocator.free(target);
        return loadAt(allocator, io, .cwd(), target);
    }
    /// Atomically replaces a complete validated schema-4 file; failure retires its private temporary.
    pub fn saveAt(self: *const Config, io: std.Io, dir: std.Io.Dir, target: []const u8) !void {
        var value = try validate(io, self.value);
        if (value.default_profile.len == 0) value.default_profile = if (value.startup_profile == 1) "local" else "home";
        value.startup_profile = if (std.mem.eql(u8, value.default_profile, "local")) 1 else 0;
        const bytes = try std.json.Stringify.valueAlloc(self.allocator, value, .{ .whitespace = .indent_2 });
        defer self.allocator.free(bytes);
        if (bytes.len > file_limit) return error.ConfigFileLimit;
        var atomic = try dir.createFileAtomic(io, target, .{ .make_path = true, .replace = true });
        defer atomic.deinit(io);
        try atomic.file.writeStreamingAll(io, bytes);
        try atomic.file.sync(io);
        try atomic.replace(io);
    }
    /// Saves to the same resolved location while retaining this live configuration on failure.
    pub fn save(self: *const Config, io: std.Io, env: *const std.process.Environ.Map) !void {
        const target = try path(self.allocator, env);
        defer self.allocator.free(target);
        try self.saveAt(io, .cwd(), target);
    }
    /// Retires the parser before its stable fixed allocator and backing memory.
    pub fn deinit(self: *Config) void {
        if (self.storage) |storage| {
            storage.parsed.deinit();
            self.allocator.free(storage.bytes);
            self.allocator.destroy(storage);
        }
        self.* = undefined;
    }
    /// Returns the validated catalogue size, including the two built-in recipes.
    pub fn profileCount(self: *const Config) u8 {
        return @intCast(self.value.profiles.len + 2);
    }
    /// Borrows one recipe for synchronous use; invalid catalogue indexes fail explicitly.
    pub fn profile(self: *const Config, index: u8) error{InvalidDefaultProfile}!Profile {
        return switch (index) {
            0 => .{ .id = "home", .name = "Home Instance", .mode = "attach", .endpoint = "tcp://127.0.0.1:39601" },
            1 => .{ .id = "local", .name = "Local shell", .mode = "launch" },
            else => if (index - 2 < self.value.profiles.len) self.value.profiles[index - 2] else error.InvalidDefaultProfile,
        };
    }
    /// Resolves the exact selected recipe; an unknown id never falls back to Local.
    pub fn defaultProfile(self: *const Config) error{InvalidDefaultProfile}!u8 {
        if (self.value.default_profile.len == 0) return @intCast(self.value.startup_profile);
        var index: u8 = 0;
        while (index < self.profileCount()) : (index += 1) {
            if (std.mem.eql(u8, (try self.profile(index)).id, self.value.default_profile)) return index;
        }
        return error.InvalidDefaultProfile;
    }
};

fn text(value: []const u8, maximum: usize, required: bool) bool {
    return value.len < maximum and (!required or value.len != 0) and
        std.mem.indexOfScalar(u8, value, 0) == null and std.unicode.utf8ValidateSlice(value);
}
fn id(value: []const u8) bool {
    if (!text(value, 48, true)) return false;
    for (value) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '-' and byte != '_' and byte != '.') return false;
    return true;
}
fn fontSize(value: i32, inherited: bool) bool {
    return (inherited and value == 0) or (value >= 8 and value <= 48);
}
fn validateProfile(p: Profile) !void {
    if (!id(p.id)) return error.InvalidProfileID;
    if (!text(p.name, 80, true)) return error.InvalidProfileName;
    const attach = std.ascii.eqlIgnoreCase(p.mode, "attach");
    if (!attach and !std.ascii.eqlIgnoreCase(p.mode, "launch")) return error.InvalidProfileMode;
    if (!fontSize(p.font_pixels, true)) return error.InvalidFontSize;
    if (!text(p.shell, 512, false) or !text(p.command, 4096, false) or !text(p.cwd, 1024, false) or
        !text(p.endpoint, 512, attach)) return error.InvalidProfileText;
    if (attach) {
        if (p.shell.len != 0 or p.command.len != 0 or p.cwd.len != 0 or p.environment.len != 0) return error.InvalidProfileOwnership;
    } else if (p.endpoint.len != 0) return error.InvalidProfileOwnership;
    if (p.environment.len > 16) return error.InvalidProfileEnvironment;
    for (p.environment, 0..) |entry, env_index| {
        if (!text(entry.name, 128, true) or std.mem.indexOfScalar(u8, entry.name, '=') != null or
            !text(entry.value, 2048, false)) return error.InvalidProfileEnvironment;
        for (p.environment[0..env_index]) |other| if (std.mem.eql(u8, entry.name, other.name)) return error.DuplicateEnvironment;
    }
}
fn validate(io: std.Io, supplied: Schema) ValidationError!Schema {
    if (supplied.schema < 1 or supplied.schema > 4) return error.UnsupportedSchema;
    if (!fontSize(supplied.terminal_font_pixels, false)) return error.InvalidFontSize;
    if (supplied.startup_profile < 0 or supplied.startup_profile > 1) return error.InvalidStartupProfile;
    var value = supplied;
    if (value.schema < 2) value.keybindings = &.{};
    if (value.schema < 3) {
        value.profiles = &.{};
        value.default_profile = "";
        value.app_theme = "howl_dark";
    }
    if (value.schema < 4) {
        value.servers = &.{};
        value.font = .{};
    }
    value.schema = 4;
    if (!std.mem.eql(u8, value.app_theme, "howl_dark") and !std.mem.eql(u8, value.app_theme, "slate") and
        !std.mem.eql(u8, value.app_theme, "high_contrast")) return error.InvalidTheme;
    const loaded_bindings = try bindings.Bindings.fromOverrides(value.keybindings);
    std.debug.assert(loaded_bindings.rows.len == bindings.definitions.len);
    if (value.profiles.len > 6) return error.ProfileLimit;
    for (value.profiles, 0..) |p, index| {
        try validateProfile(p);
        if (std.mem.eql(u8, p.id, "home") or std.mem.eql(u8, p.id, "local")) return error.DuplicateProfileID;
        for (value.profiles[0..index]) |other| if (std.mem.eql(u8, p.id, other.id)) return error.DuplicateProfileID;
    }
    if (value.servers.len > 16) return error.ServerLimit;
    for (value.servers, 0..) |server, index| {
        if (!text(server.label, 80, true) or !text(server.endpoint, 512, true) or
            (!std.mem.startsWith(u8, server.endpoint, "tcp://") and !std.mem.startsWith(u8, server.endpoint, "unix:"))) return error.InvalidServer;
        for (value.servers[0..index]) |other| if (std.mem.eql(u8, server.endpoint, other.endpoint)) return error.DuplicateServer;
    }
    for (value.font.paths()) |file| {
        if (!text(file, 4096, false)) return error.InvalidFontPath;
        if (file.len == 0) continue;
        if (!std.fs.path.isAbsolute(file)) return error.InvalidFontPath;
        std.Io.Dir.cwd().access(io, file, .{}) catch |failure| {
            if (failure == error.FileNotFound) return error.InvalidFontPath;
            return failure;
        };
    }
    const candidate: Config = .{ .allocator = std.heap.smp_allocator, .value = value };
    const selected = try candidate.defaultProfile();
    std.debug.assert(selected < candidate.profileCount());
    return value;
}

test "config owns decoded bytes and normalizes legacy schemas only in memory" {
    const json = "{\"schema\":1,\"terminal_font_pixels\":23,\"startup_profile\":1}";
    const bytes = try std.testing.allocator.dupe(u8, json);
    defer std.testing.allocator.free(bytes);
    var value = try Config.parse(std.testing.allocator, std.testing.io, bytes);
    defer value.deinit();
    @memset(bytes, '?');
    try std.testing.expectEqual(@as(i16, 4), value.value.schema);
    try std.testing.expectEqual(@as(i32, 23), value.value.terminal_font_pixels);
    try std.testing.expectEqualStrings("howl_dark", value.value.app_theme);
    try std.testing.expectEqual(@as(u8, 1), try value.defaultProfile());
    var current = try Config.parse(std.testing.allocator, std.testing.io, "{\"schema\":4,\"terminal_font_pixels\":15,\"app_theme\":\"high_contrast\",\"default_profile\":\"custom\",\"profiles\":[{\"id\":\"custom\",\"name\":\"Exact command\",\"mode\":\"launch\",\"command\":\"printf hi\",\"cwd\":\"/\"}]}");
    defer current.deinit();
    try std.testing.expectEqual(@as(u8, 2), try current.defaultProfile());
    try std.testing.expectEqualStrings("printf hi", (try current.profile(2)).command);
}

test "config rejects invalid recipes, ownership, duplicate fields and explicit missing fonts" {
    const prefix = "{\"schema\":4,\"terminal_font_pixels\":15,\"app_theme\":\"howl_dark\",";
    try std.testing.expectError(error.UnsupportedSchema, Config.parse(std.testing.allocator, std.testing.io, "{\"schema\":99}"));
    try std.testing.expectError(error.InvalidFontSize, Config.parse(std.testing.allocator, std.testing.io, "{\"schema\":1,\"terminal_font_pixels\":7}"));
    try std.testing.expectError(error.DuplicateField, Config.parse(std.testing.allocator, std.testing.io, "{\"schema\":1,\"schema\":1,\"terminal_font_pixels\":15}"));
    try std.testing.expectError(error.InvalidDefaultProfile, Config.parse(std.testing.allocator, std.testing.io, prefix ++ "\"default_profile\":\"unknown\"}"));
    try std.testing.expectError(error.InvalidProfileOwnership, Config.parse(std.testing.allocator, std.testing.io, prefix ++ "\"profiles\":[{\"id\":\"remote\",\"name\":\"Remote\",\"mode\":\"attach\",\"endpoint\":\"unix:test\",\"command\":\"wrong\"}]}"));
    try std.testing.expectError(error.DuplicateProfileID, Config.parse(std.testing.allocator, std.testing.io, prefix ++ "\"profiles\":[{\"id\":\"local\",\"name\":\"shadow\",\"mode\":\"launch\"}]}"));
    try std.testing.expectError(error.DuplicateEnvironment, Config.parse(std.testing.allocator, std.testing.io, prefix ++ "\"profiles\":[{\"id\":\"local2\",\"name\":\"two\",\"mode\":\"launch\",\"environment\":[{\"name\":\"A\",\"value\":\"1\"},{\"name\":\"A\",\"value\":\"2\"}]}]}"));
    try std.testing.expectError(error.InvalidFontPath, Config.parse(std.testing.allocator, std.testing.io, prefix ++ "\"font\":{\"regular\":\"/definitely/missing/howl-font.ttf\"}}"));
}

test "missing config differs from malformed data; rejected save and rename failure preserve accepted state" {
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    var value = try Config.loadAt(std.testing.allocator, std.testing.io, temporary.dir, "odin.json");
    defer value.deinit();
    try std.testing.expectEqual(@as(u8, 0), try value.defaultProfile());
    value.value.terminal_font_pixels = 23;
    value.value.default_profile = "local";
    try value.saveAt(std.testing.io, temporary.dir, "odin.json");
    var reopened = try Config.loadAt(std.testing.allocator, std.testing.io, temporary.dir, "odin.json");
    defer reopened.deinit();
    try std.testing.expectEqual(@as(i32, 23), reopened.value.terminal_font_pixels);
    try std.testing.expectEqual(@as(u8, 1), try reopened.defaultProfile());
    const before = try temporary.dir.readFileAlloc(std.testing.io, "odin.json", std.testing.allocator, .limited(file_limit));
    defer std.testing.allocator.free(before);
    value.value.terminal_font_pixels = 7;
    try std.testing.expectError(error.InvalidFontSize, value.saveAt(std.testing.io, temporary.dir, "odin.json"));
    const after = try temporary.dir.readFileAlloc(std.testing.io, "odin.json", std.testing.allocator, .limited(file_limit));
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualSlices(u8, before, after);
    value.value.terminal_font_pixels = 23;
    try temporary.dir.createDir(std.testing.io, "occupied", .default_dir);
    try std.testing.expectError(error.IsDir, value.saveAt(std.testing.io, temporary.dir, "occupied"));
    const unchanged = try temporary.dir.readFileAlloc(std.testing.io, "odin.json", std.testing.allocator, .limited(file_limit));
    defer std.testing.allocator.free(unchanged);
    try std.testing.expectEqualSlices(u8, before, unchanged);
    var iterator = temporary.dir.iterate();
    var count: usize = 0;
    while (try iterator.next(std.testing.io)) |entry| {
        try std.testing.expect(std.mem.eql(u8, entry.name, "odin.json") or std.mem.eql(u8, entry.name, "occupied"));
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), count);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "broken.json", .data = "{" });
    try std.testing.expectError(error.UnexpectedEndOfInput, Config.loadAt(std.testing.allocator, std.testing.io, temporary.dir, "broken.json"));
}

test "oversized files and hostile arrays are bounded before accepting configuration" {
    const bytes = try std.testing.allocator.alloc(u8, file_limit + 1);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectError(error.ConfigFileLimit, Config.parse(std.testing.allocator, std.testing.io, bytes));
    var huge: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer huge.deinit();
    try huge.writer.writeAll("{\"schema\":4,\"terminal_font_pixels\":15,\"app_theme\":\"howl_dark\",\"profiles\":[");
    for (0..50000) |index| try huge.writer.writeAll(if (index == 0) "{}" else ",{}");
    try huge.writer.writeAll("]}");
    try std.testing.expectError(error.ConfigAllocationLimit, Config.parse(std.testing.allocator, std.testing.io, huge.written()));
}

fn allocationProof(allocator: std.mem.Allocator) !void {
    var value = try Config.parse(allocator, std.testing.io, "{\"schema\":1,\"terminal_font_pixels\":15}");
    defer value.deinit();
}
test "config constructor releases every completed resource on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProof, .{});
}

test "saved path uses the existing XDG location and empty XDG inherits HOME" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try std.testing.expectError(error.ConfigHomeMissing, Config.path(std.testing.allocator, &env));
    try env.put("HOME", "/home/example");
    const home = try Config.path(std.testing.allocator, &env);
    defer std.testing.allocator.free(home);
    try std.testing.expectEqualStrings("/home/example/.config/howl/odin.json", home);
    try env.put("XDG_CONFIG_HOME", "/config");
    const xdg = try Config.path(std.testing.allocator, &env);
    defer std.testing.allocator.free(xdg);
    try std.testing.expectEqualStrings("/config/howl/odin.json", xdg);
    try env.put("XDG_CONFIG_HOME", "");
    const inherited = try Config.path(std.testing.allocator, &env);
    defer std.testing.allocator.free(inherited);
    try std.testing.expectEqualStrings(home, inherited);
}

test "schema two retains mappings and schema four preserves Server rows and rejects hostile text" {
    var legacy = try Config.parse(std.testing.allocator, std.testing.io, "{\"schema\":2,\"terminal_font_pixels\":15,\"keybindings\":[{\"action\":\"new_tab\",\"shortcut\":\"F11\"},{\"action\":\"toggle_fullscreen\",\"shortcut\":\"Ctrl+T\"}]}");
    defer legacy.deinit();
    try std.testing.expectEqual(@as(usize, 2), legacy.value.keybindings.len);
    try std.testing.expectEqualStrings("howl_dark", legacy.value.app_theme);
    const prefix = "{\"schema\":4,\"terminal_font_pixels\":15,\"app_theme\":\"howl_dark\",";
    var current = try Config.parse(std.testing.allocator, std.testing.io, prefix ++ "\"servers\":[{\"label\":\"one\",\"endpoint\":\"unix:/one\"}]}");
    defer current.deinit();
    try std.testing.expectEqualStrings("unix:/one", current.value.servers[0].endpoint);
    try std.testing.expectError(error.DuplicateServer, Config.parse(std.testing.allocator, std.testing.io, prefix ++ "\"servers\":[{\"label\":\"one\",\"endpoint\":\"unix:/one\"},{\"label\":\"two\",\"endpoint\":\"unix:/one\"}]}"));
    try std.testing.expectError(error.InvalidProfileText, Config.parse(std.testing.allocator, std.testing.io, prefix ++ "\"profiles\":[{\"id\":\"one\",\"name\":\"one\",\"mode\":\"launch\",\"command\":\"bad\\u0000command\"}]}"));
}

test "pane recipe remains exact after parsed configuration retires" {
    var recipe = owned: {
        var value = try Config.parse(std.testing.allocator, std.testing.io, "{\"schema\":4,\"terminal_font_pixels\":15,\"app_theme\":\"howl_dark\",\"profiles\":[{\"id\":\"one\",\"name\":\"One\",\"mode\":\"launch\",\"shell\":\"/bin/sh\",\"command\":\"printf exact\",\"cwd\":\"/\",\"environment\":[{\"name\":\"A\",\"value\":\"B\"}],\"font_pixels\":23}]}");
        defer value.deinit();
        break :owned try Recipe.copy(std.testing.allocator, try value.profile(2));
    };
    defer recipe.deinit();
    try std.testing.expectEqualStrings("printf exact", recipe.value.command);
    try std.testing.expectEqualStrings("/bin/sh", recipe.value.shell);
    try std.testing.expectEqualStrings("B", recipe.value.environment[0].value);
    try std.testing.expectEqual(@as(i32, 23), recipe.value.font_pixels);
}
fn recipeAllocationProof(allocator: std.mem.Allocator) !void {
    var recipe = try Recipe.copy(allocator, .{ .id = "one", .name = "One", .mode = "launch", .command = "printf exact", .environment = &.{.{ .name = "A", .value = "B" }} });
    defer recipe.deinit();
}
test "recipe copy rejects hostile ownership and retires every partial allocation" {
    try std.testing.expectError(error.InvalidProfileOwnership, Recipe.copy(std.testing.allocator, .{ .id = "remote", .name = "Remote", .mode = "attach", .endpoint = "unix:/one", .command = "wrong" }));
    try std.testing.checkAllAllocationFailures(std.testing.allocator, recipeAllocationProof, .{});
}
