//! Read-only launch discovery. Never executes a candidate or evaluates SSH directives.
const std = @import("std");
const c = @import("desktop");
const config = @import("config.zig");

/// A menu holds at most 512 discovered recipes; saved profiles have a separate bound.
pub const limit = 512;
const path_limit = 4096;
const file_limit = 256 * 1024;
const total_file_limit = 2 * 1024 * 1024;
const files_limit = 64;
const depth_limit = 8;

/// Presentation origin, independent of executable/argument launch semantics.
pub const Kind = enum { shell, repl, ssh };
/// Borrowed discovery fact; the catalogue owns every recipe byte.
pub const Entry = struct { kind: Kind, recipe: config.Profile };

const Preset = struct { executable: []const u8, name: []const u8, kind: Kind = .shell, arguments: []const []const u8 = &.{} };
const presets = [_]Preset{
    .{ .executable = "bash", .name = "Bash", .arguments = &.{"-i"} },
    .{ .executable = "zsh", .name = "Zsh", .arguments = &.{"-i"} },
    .{ .executable = "fish", .name = "Fish", .arguments = &.{"-i"} },
    .{ .executable = "nu", .name = "Nushell" },
    .{ .executable = "pwsh", .name = "PowerShell", .arguments = &.{"-NoLogo"} },
    .{ .executable = "powershell", .name = "PowerShell", .arguments = &.{"-NoLogo"} },
    .{ .executable = "dash", .name = "Dash", .arguments = &.{"-i"} },
    .{ .executable = "ksh", .name = "Ksh", .arguments = &.{"-i"} },
    .{ .executable = "mksh", .name = "Mksh", .arguments = &.{"-i"} },
    .{ .executable = "yash", .name = "Yash", .arguments = &.{"-i"} },
    .{ .executable = "ash", .name = "Ash", .arguments = &.{"-i"} },
    .{ .executable = "sh", .name = "POSIX sh", .arguments = &.{"-i"} },
    .{ .executable = "tcsh", .name = "Tcsh", .arguments = &.{"-i"} },
    .{ .executable = "csh", .name = "Csh", .arguments = &.{"-i"} },
    .{ .executable = "elvish", .name = "Elvish" },
    .{ .executable = "xonsh", .name = "Xonsh", .arguments = &.{"-i"} },
    .{ .executable = "osh", .name = "Oils osh", .arguments = &.{"-i"} },
    .{ .executable = "ysh", .name = "Oils ysh", .arguments = &.{"-i"} },
    .{ .executable = "python3", .name = "Python", .kind = .repl, .arguments = &.{"-q"} },
    .{ .executable = "python", .name = "Python", .kind = .repl, .arguments = &.{"-q"} },
    .{ .executable = "ipython", .name = "IPython", .kind = .repl },
    .{ .executable = "node", .name = "Node.js", .kind = .repl, .arguments = &.{"--interactive"} },
    .{ .executable = "irb", .name = "Ruby IRB", .kind = .repl },
    .{ .executable = "lua", .name = "Lua", .kind = .repl, .arguments = &.{"-i"} },
    .{ .executable = "luajit", .name = "LuaJIT", .kind = .repl, .arguments = &.{"-i"} },
    .{ .executable = "julia", .name = "Julia", .kind = .repl },
    .{ .executable = "R", .name = "R", .kind = .repl, .arguments = &.{"--no-save"} },
    .{ .executable = "jshell", .name = "Java JShell", .kind = .repl },
    .{ .executable = "iex", .name = "Elixir IEx", .kind = .repl },
    .{ .executable = "ghci", .name = "Haskell GHCi", .kind = .repl },
    .{ .executable = "utop", .name = "OCaml UTop", .kind = .repl },
    .{ .executable = "sqlite3", .name = "SQLite", .kind = .repl },
};

/// Owns one bounded menu snapshot. Rebuilding or disabling discovery cannot alter live panes.
pub const Catalogue = struct {
    arena: std.heap.ArenaAllocator,
    entries: [limit]Entry = undefined,
    count: u16 = 0,
    visited: [files_limit][]const u8 = undefined,
    files: u8 = 0,
    bytes: usize = 0,
    inspected: usize = 0,

    fn init(allocator: std.mem.Allocator) Catalogue {
        return .{ .arena = .init(allocator) };
    }
    /// Discovers only enabled sources; missing conventional files are ordinary absence.
    pub fn create(allocator: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, value: config.Schema) !*Catalogue {
        const self = try allocator.create(Catalogue);
        self.* = .init(allocator);
        errdefer self.destroy(allocator);
        if (value.discover_shells) try self.shells(io, env, "/etc/shells");
        if (value.discover_ssh_hosts) {
            const a = self.arena.allocator();
            const home = env.get("HOME") orelse return error.DiscoveryHomeMissing;
            const base = try std.fs.path.join(a, &.{ home, ".ssh" });
            const user_file = try std.fs.path.join(a, &.{ base, "config" });
            if (try executable(a, io, env.get("PATH") orelse "", "ssh")) |ssh| {
                try self.sshFile(io, env, user_file, base, ssh, 0);
                try self.sshFile(io, env, "/etc/ssh/ssh_config", "/etc/ssh", ssh, 0);
            }
        }
        return self;
    }
    /// Releases the complete snapshot, including all decoded paths and argument arrays.
    pub fn destroy(self: *Catalogue, allocator: std.mem.Allocator) void {
        self.arena.deinit();
        allocator.destroy(self);
    }
    fn add(self: *Catalogue, kind: Kind, name: []const u8, program: []const u8, arguments: ?[]const []const u8) !void {
        for (self.entries[0..self.count]) |entry| {
            if (kind == .ssh and entry.kind == .ssh and std.ascii.eqlIgnoreCase(name, entry.recipe.name)) return;
            if (kind != .ssh and entry.kind != .ssh and (std.mem.eql(u8, program, entry.recipe.shell) or std.mem.eql(u8, name, entry.recipe.name))) return;
        }
        if (self.count == limit) return error.DiscoveryEntryLimit;
        const a = self.arena.allocator();
        const copied_args: ?[]const []const u8 = if (arguments) |args| blk: {
            const copies = try a.alloc([]const u8, args.len);
            for (args, copies) |arg, *copy| copy.* = try a.dupe(u8, arg);
            break :blk copies;
        } else null;
        var hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(if (kind == .ssh) name else program, &hash, .{});
        const hex = std.fmt.bytesToHex(hash[0..16].*, .lower);
        self.entries[self.count] = .{ .kind = kind, .recipe = .{
            .id = try std.fmt.allocPrint(a, "auto.{s}.{s}", .{ @tagName(kind), hex }),
            .name = try a.dupe(u8, name),
            .shell = try a.dupe(u8, program),
            .arguments = copied_args,
        } };
        self.count += 1;
    }
    fn shells(self: *Catalogue, io: std.Io, env: *const std.process.Environ.Map, shells_file: []const u8) !void {
        const a = self.arena.allocator();
        for (presets) |preset| if (try executable(a, io, env.get("PATH") orelse "", preset.executable)) |program| {
            try self.add(preset.kind, preset.name, program, preset.arguments);
        };
        const bytes = (try self.read(io, shells_file)) orelse return;
        defer a.free(bytes);
        var lines = std.mem.splitScalar(u8, bytes, '\n');
        while (lines.next()) |raw| {
            const line = std.mem.trim(u8, raw[0 .. std.mem.indexOfScalar(u8, raw, '#') orelse raw.len], " \t\r");
            if (line.len == 0) continue;
            if (!std.fs.path.isAbsolute(line)) return error.InvalidShellsFile;
            if (try executable(a, io, "", line)) |program| {
                const name = std.fs.path.basename(line);
                var known = false;
                for (presets) |preset| if (preset.kind == .shell and std.mem.eql(u8, name, preset.executable)) {
                    try self.add(.shell, preset.name, program, preset.arguments);
                    known = true;
                    break;
                };
                if (!known) try self.add(.shell, name, program, null);
            }
        }
    }
    fn read(self: *Catalogue, io: std.Io, file: []const u8) !?[]u8 {
        if (file.len == 0 or file.len >= path_limit) return error.DiscoveryPathLimit;
        const dir = std.Io.Dir.cwd();
        const stat = dir.statFile(io, file, .{}) catch |failure| {
            if (failure == error.FileNotFound) return null;
            return failure;
        };
        if (stat.kind != .file) return error.InvalidDiscoveryFile;
        if (stat.size > file_limit or stat.size > total_file_limit - self.bytes) return error.DiscoveryFileLimit;
        const bytes = try dir.readFileAlloc(io, file, self.arena.allocator(), .limited(@min(file_limit, total_file_limit - self.bytes)));
        self.bytes += bytes.len;
        if (!std.unicode.utf8ValidateSlice(bytes) or std.mem.indexOfScalar(u8, bytes, 0) != null) return error.InvalidDiscoveryText;
        return bytes;
    }
    fn sshFile(self: *Catalogue, io: std.Io, env: *const std.process.Environ.Map, file: []const u8, base: []const u8, ssh: []const u8, depth: u8) SshError!void {
        if (depth >= depth_limit) return error.SshIncludeDepth;
        const a = self.arena.allocator();
        const canonical = std.Io.Dir.cwd().realPathFileAlloc(io, file, a) catch |failure| {
            if (failure == error.FileNotFound) return;
            return failure;
        };
        var retained = false;
        defer if (!retained) a.free(canonical);
        for (self.visited[0..self.files]) |seen| if (std.mem.eql(u8, canonical, seen)) return;
        if (self.files == files_limit) return error.SshIncludeFileLimit;
        self.visited[self.files] = canonical;
        retained = true;
        self.files += 1;
        const bytes = (try self.read(io, canonical)) orelse return;
        defer a.free(bytes);
        var lines = std.mem.splitScalar(u8, bytes, '\n');
        while (lines.next()) |raw| {
            const line = std.mem.trim(u8, raw, " \t\r");
            if (line.len == 0 or line[0] == '#') continue;
            const split = std.mem.indexOfAny(u8, line, " \t=") orelse line.len;
            const key = line[0..split];
            if (!std.ascii.eqlIgnoreCase(key, "Host") and !std.ascii.eqlIgnoreCase(key, "Include")) continue;
            var tokens: Tokens = .{ .bytes = std.mem.trimStart(u8, line[split..], " \t=") };
            while (try tokens.next()) |token| {
                if (std.ascii.eqlIgnoreCase(key, "Host")) {
                    if (std.mem.indexOfAny(u8, token, "*?![") != null) continue;
                    if (!alias(token)) return error.InvalidSshAlias;
                    try self.add(.ssh, token, ssh, &.{ "-t", "--", token });
                } else {
                    var temporary = std.heap.ArenaAllocator.init(self.arena.child_allocator);
                    defer temporary.deinit();
                    const pattern = try includePath(temporary.allocator(), env, token, base);
                    var matches: Matches = .{ .allocator = temporary.allocator(), .inspected = &self.inspected };
                    try matches.expand(io, "/", pattern[1..], 0);
                    std.mem.sort([]const u8, matches.paths[0..matches.count], {}, struct {
                        fn less(_: void, left: []const u8, right: []const u8) bool {
                            return std.mem.lessThan(u8, left, right);
                        }
                    }.less);
                    for (matches.paths[0..matches.count]) |match| try self.sshFile(io, env, match, base, ssh, depth + 1);
                }
            }
        }
    }
};

// The recursive reader has one exact error set; recursion cannot infer it.
const SshError = std.Io.Dir.RealPathFileAllocError ||
    @typeInfo(@typeInfo(@TypeOf(Catalogue.read)).@"fn".return_type.?).error_union.error_set ||
    @typeInfo(@typeInfo(@TypeOf(Catalogue.add)).@"fn".return_type.?).error_union.error_set ||
    @typeInfo(@typeInfo(@TypeOf(includePath)).@"fn".return_type.?).error_union.error_set ||
    @typeInfo(@typeInfo(@TypeOf(Tokens.next)).@"fn".return_type.?).error_union.error_set ||
    GlobError || error{ SshIncludeDepth, SshIncludeFileLimit, InvalidSshAlias };

fn executable(a: std.mem.Allocator, io: std.Io, path: []const u8, name: []const u8) !?[]const u8 {
    if (path.len > 64 * 1024) return error.DiscoveryPathLimit;
    if (name.len == 0 or name.len >= path_limit or std.mem.indexOfScalar(u8, name, 0) != null) return error.DiscoveryPathLimit;
    var directories = std.mem.splitScalar(u8, path, ':');
    while (directories.next()) |directory| {
        const candidate = if (std.fs.path.isAbsolute(name)) try a.dupe(u8, name) else try std.fs.path.join(a, &.{ if (directory.len == 0) "." else directory, name });
        defer a.free(candidate);
        if (candidate.len >= path_limit) return error.DiscoveryPathLimit;
        std.Io.Dir.cwd().access(io, candidate, .{ .execute = true }) catch |failure| {
            if (failure == error.FileNotFound or failure == error.AccessDenied or failure == error.PermissionDenied or failure == error.NotDir) {
                if (std.fs.path.isAbsolute(name)) return null;
                continue;
            }
            return failure;
        };
        const stat = try std.Io.Dir.cwd().statFile(io, candidate, .{});
        if (stat.kind != .file) continue;
        // Canonicalise the directory, preserving executable symlink names such as sh.
        const parent = try std.Io.Dir.cwd().realPathFileAlloc(io, std.fs.path.dirname(candidate) orelse ".", a);
        defer a.free(parent);
        return try std.fs.path.join(a, &.{ parent, std.fs.path.basename(candidate) });
    }
    return null;
}
fn alias(value: []const u8) bool {
    if (value.len == 0 or value.len > 240 or value[0] == '-') return false;
    for (value) |byte| if (!std.ascii.isAlphanumeric(byte) and std.mem.indexOfScalar(u8, "._-:+/%", byte) == null) return false;
    return true;
}
fn includePath(a: std.mem.Allocator, env: *const std.process.Environ.Map, input: []const u8, base: []const u8) ![]const u8 {
    var buffer: [path_limit]u8 = undefined;
    var out = std.Io.Writer.fixed(&buffer);
    var i: usize = 0;
    if (std.mem.startsWith(u8, input, "~/")) {
        try out.writeAll(env.get("HOME") orelse return error.DiscoveryHomeMissing);
        i = 1;
    } else if (std.mem.startsWith(u8, input, "~")) return error.UnsupportedSshInclude;
    while (i < input.len) {
        if (input[i] == '$' and i + 1 < input.len and input[i + 1] == '{') {
            const end = std.mem.indexOfScalarPos(u8, input, i + 2, '}') orelse return error.InvalidSshInclude;
            try out.writeAll(env.get(input[i + 2 .. end]) orelse return error.UnsupportedSshInclude);
            i = end + 1;
        } else if (input[i] == '%') {
            if (i + 1 == input.len) return error.InvalidSshInclude;
            switch (input[i + 1]) {
                '%' => try out.writeByte('%'),
                'd' => try out.writeAll(env.get("HOME") orelse return error.DiscoveryHomeMissing),
                else => return error.UnsupportedSshInclude,
            }
            i += 2;
        } else {
            try out.writeByte(input[i]);
            i += 1;
        }
    }
    const expanded = out.buffered();
    if (expanded.len == 0 or std.mem.indexOfScalar(u8, expanded, 0) != null) return error.InvalidSshInclude;
    const result = if (std.fs.path.isAbsolute(expanded)) try a.dupe(u8, expanded) else try std.fs.path.join(a, &.{ base, expanded });
    errdefer a.free(result);
    if (result.len >= path_limit or !std.fs.path.isAbsolute(result)) return error.DiscoveryPathLimit;
    return result;
}
const GlobError = std.mem.Allocator.Error || std.Io.Dir.OpenError || std.Io.Dir.Iterator.Error ||
    error{ SshIncludeFileLimit, SshIncludeDirectoryLimit, DiscoveryPathLimit, NoSpaceLeft };
const Matches = struct {
    allocator: std.mem.Allocator,
    inspected: *usize,
    paths: [files_limit][]const u8 = undefined,
    count: u8 = 0,
    fn expand(self: *Matches, io: std.Io, base: []const u8, rest: []const u8, depth: u8) GlobError!void {
        if (depth == 32) return error.DiscoveryPathLimit;
        const split = std.mem.indexOfScalar(u8, rest, '/') orelse rest.len;
        const component = rest[0..split];
        const tail = if (split < rest.len) rest[split + 1 ..] else null;
        var path_buffer: [path_limit]u8 = undefined;
        if (std.mem.indexOfAny(u8, component, "*?[") == null) {
            const path = try std.fmt.bufPrint(&path_buffer, "{s}/{s}", .{ base, component });
            if (tail) |next| return self.expand(io, path, next, depth + 1);
            return self.append(path);
        }
        var directory = std.Io.Dir.cwd().openDir(io, base, .{ .iterate = true }) catch |failure| {
            if (failure == error.FileNotFound or failure == error.NotDir) return;
            return failure;
        };
        defer directory.close(io);
        var pattern_buffer: [path_limit + 1]u8 = undefined;
        const pattern = try std.fmt.bufPrintSentinel(&pattern_buffer, "{s}", .{component}, 0);
        var iterator = directory.iterate();
        while (try iterator.next(io)) |entry| {
            if (self.inspected.* == 8192) return error.SshIncludeDirectoryLimit;
            self.inspected.* += 1;
            var name_buffer: [path_limit + 1]u8 = undefined;
            const name = try std.fmt.bufPrintSentinel(&name_buffer, "{s}", .{entry.name}, 0);
            if (c.fnmatch(pattern.ptr, name.ptr, c.FNM_PERIOD) != 0) continue;
            const path = try std.fmt.bufPrint(&path_buffer, "{s}/{s}", .{ base, entry.name });
            if (tail) |next| try self.expand(io, path, next, depth + 1) else try self.append(path);
        }
    }
    fn append(self: *Matches, path: []const u8) (std.mem.Allocator.Error || error{SshIncludeFileLimit})!void {
        if (self.count == files_limit) return error.SshIncludeFileLimit;
        self.paths[self.count] = try self.allocator.dupe(u8, path);
        self.count += 1;
    }
};

const Tokens = struct {
    bytes: []const u8,
    scratch: [path_limit]u8 = undefined,
    fn next(self: *Tokens) error{ InvalidSshConfig, DiscoveryPathLimit }!?[]const u8 {
        self.bytes = std.mem.trimStart(u8, self.bytes, " \t\r");
        if (self.bytes.len == 0 or self.bytes[0] == '#') return null;
        var count: usize = 0;
        var quote: ?u8 = null;
        var i: usize = 0;
        while (i < self.bytes.len) : (i += 1) {
            const byte = self.bytes[i];
            if (byte == '\\') {
                i += 1;
                if (i == self.bytes.len) return error.InvalidSshConfig;
            } else if (quote) |q| {
                if (byte == q) {
                    quote = null;
                    continue;
                }
            } else if (byte == '"' or byte == '\'') {
                quote = byte;
                continue;
            } else if (byte == '#' or byte == ' ' or byte == '\t' or byte == '\r') break;
            if (count == self.scratch.len) return error.DiscoveryPathLimit;
            self.scratch[count] = self.bytes[i];
            count += 1;
        }
        if (quote != null) return error.InvalidSshConfig;
        self.bytes = self.bytes[i..];
        return self.scratch[0..count];
    }
};

test "SSH alias discovery follows quoted relative Includes, deduplicates cycles and never evaluates commands" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const io = std.testing.io;
    const root = try temporary.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    try temporary.dir.createDir(io, "conf space", .default_dir);
    try temporary.dir.writeFile(io, .{ .sub_path = "config", .data = "Host first other *.wild !excluded [ab]ox\nInclude \"conf space/*.conf\"\nMatch exec \"touch NEVER\"\nProxyCommand $(touch NEVER)\nHost first\n" });
    try temporary.dir.writeFile(io, .{ .sub_path = "conf space/a.conf", .data = "hOsT=third # note\nHost .host machine/.host\nInclude config\n" });
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put("HOME", root);
    var catalogue = Catalogue.init(std.testing.allocator);
    defer catalogue.arena.deinit();
    const file = try std.fs.path.join(std.testing.allocator, &.{ root, "config" });
    defer std.testing.allocator.free(file);
    try catalogue.sshFile(io, &env, file, root, "/usr/bin/ssh", 0);
    try std.testing.expectEqual(@as(u16, 5), catalogue.count);
    try std.testing.expectEqualStrings("third", catalogue.entries[2].recipe.name);
    try std.testing.expectEqualDeep(@as([]const []const u8, &.{ "-t", "--", "third" }), catalogue.entries[2].recipe.arguments.?);
    try std.testing.expectError(error.FileNotFound, temporary.dir.access(io, "NEVER", .{}));
    var recipe = try config.Recipe.copy(std.testing.allocator, catalogue.entries[2].recipe);
    defer recipe.deinit();
    catalogue.entries[2].recipe = .{};
    try std.testing.expectEqualStrings("third", recipe.value.arguments.?[2]);
}

test "discovery rejects ambiguous aliases, unsupported expansions, malformed quotes and explicit bounds" {
    try std.testing.expect(!alias("-oProxyCommand=bad"));
    try std.testing.expect(!alias("$(echo bad)"));
    try std.testing.expect(alias("server:22"));
    try std.testing.expect(alias("machine/.host"));
    try std.testing.expect(alias("vsock%3"));
    var tokens: Tokens = .{ .bytes = "\"broken" };
    try std.testing.expectError(error.InvalidSshConfig, tokens.next());
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put("HOME", "/home/test");
    try env.put("PART", "hosts/*.conf");
    try std.testing.expectError(error.UnsupportedSshInclude, includePath(std.testing.allocator, &env, "%h/conf", "/unused"));
    const expanded = try includePath(std.testing.allocator, &env, "~/.ssh/$" ++ "{PART}", "/unused");
    defer std.testing.allocator.free(expanded);
    try std.testing.expectEqualStrings("/home/test/.ssh/hosts/*.conf", expanded);
}

test "entry overflow and aggregate file limit fail without accepting an extra recipe" {
    var catalogue = Catalogue.init(std.testing.allocator);
    defer catalogue.arena.deinit();
    for (0..limit) |i| {
        var name: [32]u8 = undefined;
        const alias_name = try std.fmt.bufPrint(&name, "host-{d}", .{i});
        try catalogue.add(.ssh, alias_name, "/usr/bin/ssh", &.{ "-t", "--", alias_name });
    }
    try std.testing.expectError(error.DiscoveryEntryLimit, catalogue.add(.ssh, "extra", "/usr/bin/ssh", &.{ "-t", "--", "extra" }));
    try std.testing.expectEqual(@as(u16, limit), catalogue.count);
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "config", .data = "Host x\n" });
    const file = try temporary.dir.realPathFileAlloc(std.testing.io, "config", std.testing.allocator);
    defer std.testing.allocator.free(file);
    catalogue.bytes = total_file_limit;
    try std.testing.expectError(error.DiscoveryFileLimit, catalogue.read(std.testing.io, file));
}

fn allocationProof(a: std.mem.Allocator) !void {
    const catalogue = try a.create(Catalogue);
    catalogue.* = .init(a);
    defer catalogue.destroy(a);
    try catalogue.add(.ssh, "alias", "/usr/bin/ssh", &.{ "-t", "--", "alias" });
    var recipe = try config.Recipe.copy(a, catalogue.entries[0].recipe);
    defer recipe.deinit();
}
test "discovery and recipe ownership release every allocation on failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProof, .{});
}

test "installed discovery uses executable files, preserves per-program flags and never starts candidates" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const io = std.testing.io;
    const root = try temporary.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    for ([_][]const u8{ "nu", "node" }) |name| try temporary.dir.writeFile(io, .{
        .sub_path = name,
        .data = "#!/bin/sh\nprintf ran > MUST_NOT_RUN\n",
        .flags = .{ .permissions = .fromMode(0o700) },
    });
    try temporary.dir.createDir(io, "bash", .default_dir);
    try temporary.dir.writeFile(io, .{ .sub_path = "pwsh", .data = "not executable" });
    const shell = try std.fs.path.join(std.testing.allocator, &.{ root, "nu" });
    defer std.testing.allocator.free(shell);
    try temporary.dir.writeFile(io, .{ .sub_path = "shells", .data = shell });
    const shell_file = try std.fs.path.join(std.testing.allocator, &.{ root, "shells" });
    defer std.testing.allocator.free(shell_file);
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put("PATH", root);
    var catalogue = Catalogue.init(std.testing.allocator);
    defer catalogue.arena.deinit();
    try catalogue.shells(io, &env, shell_file);
    try std.testing.expectEqual(@as(u16, 2), catalogue.count);
    try std.testing.expectEqualStrings("Nushell", catalogue.entries[0].recipe.name);
    try std.testing.expectEqual(@as(usize, 0), catalogue.entries[0].recipe.arguments.?.len);
    try std.testing.expectEqualStrings("--interactive", catalogue.entries[1].recipe.arguments.?[0]);
    try std.testing.expectError(error.FileNotFound, temporary.dir.access(io, "MUST_NOT_RUN", .{}));
}

test "include depth, directory scanning and match storage have independent finite bounds" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const io = std.testing.io;
    const root = try temporary.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    for (0..10) |index| {
        var name: [32]u8 = undefined;
        var data: [64]u8 = undefined;
        try temporary.dir.writeFile(io, .{
            .sub_path = try std.fmt.bufPrint(&name, "level-{d}", .{index}),
            .data = try std.fmt.bufPrint(&data, "Include level-{d}\n", .{index + 1}),
        });
    }
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var catalogue = Catalogue.init(std.testing.allocator);
    defer catalogue.arena.deinit();
    const first = try std.fs.path.join(std.testing.allocator, &.{ root, "level-0" });
    defer std.testing.allocator.free(first);
    try std.testing.expectError(error.SshIncludeDepth, catalogue.sshFile(io, &env, first, root, "/usr/bin/ssh", 0));
    var examined: usize = 8192;
    var matches: Matches = .{ .allocator = std.testing.allocator, .inspected = &examined };
    try std.testing.expectError(error.SshIncludeDirectoryLimit, matches.expand(io, root, "*", 0));
    matches.count = files_limit;
    try std.testing.expectError(error.SshIncludeFileLimit, matches.append("extra"));
}
