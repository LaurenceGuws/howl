//! Owns bounded repository-local startup configuration for the host.
//!
//! The process root reads this file once before constructing any Boundary or
//! runtime thread and retains only the bounded terminal font path.

const std = @import("std");
const build_options = @import("config_options");

/// The largest accepted configuration file, including comments.
pub const max_file_bytes: usize = 4096;
/// The largest single physical line accepted before comment stripping.
pub const max_line_bytes: usize = 256;
/// The largest one-shot shell command accepted by the host launcher.
pub const max_command_bytes: usize = 4096;
/// The largest UTF-8 font path retained by startup configuration.
pub const max_font_path_bytes: usize = 240;
/// The repository-local configuration used when `--config` is absent.
pub const default_path: []const u8 = build_options.repository_config_path;

/// Represents one complete validated configuration for parser-boundary tests.
pub const Config = struct {
    /// Inline storage for the configured primary terminal font path.
    font_path_bytes: [max_font_path_bytes]u8,
    /// Initialized prefix of `font_path_bytes`.
    font_path_len: u16,

    /// Returns the accepted operator-resolved development values.
    pub fn defaults() Config {
        const default_font_path = "../howl-render/testdata/primary.ttf";
        var result: Config = .{
            .font_path_bytes = @splat(0),
            .font_path_len = default_font_path.len,
        };
        @memcpy(result.font_path_bytes[0..default_font_path.len], default_font_path);
        return result;
    }

    /// Borrows the configured font path for the lifetime of this value.
    pub fn fontPath(self: *const Config) []const u8 {
        return self.font_path_bytes[0..self.font_path_len];
    }
};

/// Retains process-root command-line selection after bounded parsing.
pub const ParsedArguments = struct {
    config_path: []const u8,
    /// Optional one-shot command for the first successfully created pane.
    command: ?[]const u8,
};

/// Parses the complete bounded startup argument vector without allocation.
pub fn parseArguments(args: []const []const u8) error{InvalidArguments}!ParsedArguments {
    if (args.len == 0 or args[0].len == 0) return error.InvalidArguments;
    var config_path: []const u8 = default_path;
    var config_seen = false;
    var command: ?[]const u8 = null;
    var command_seen = false;
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const argument = args[index];
        if (std.mem.eql(u8, argument, "--config")) {
            if (config_seen or index + 1 >= args.len) return error.InvalidArguments;
            config_seen = true;
            index += 1;
            config_path = args[index];
            if (config_path.len == 0) return error.InvalidArguments;
        } else if (std.mem.eql(u8, argument, "--command")) {
            if (command_seen or index + 1 >= args.len) return error.InvalidArguments;
            command_seen = true;
            index += 1;
            command = args[index];
            if (command.?.len == 0 or command.?.len > max_command_bytes)
                return error.InvalidArguments;
        } else return error.InvalidArguments;
    }
    return .{
        .config_path = config_path,
        .command = command,
    };
}

/// Reports exact bounded syntax and value rejection.
pub const ParseError = error{
    ConfigTooLarge,
    UnknownKey,
    DuplicateKey,
    MalformedValue,
    InvalidValue,
};

/// Reports file access, bounded read, allocation, or parser failure.
pub const LoadError = std.Io.Dir.ReadFileAllocError || ParseError;

const key_count = 1;

/// Parses one complete configuration into typed storage for boundary tests.
pub fn parse(bytes: []const u8) ParseError!Config {
    var result = Config.defaults();
    try parseInto(bytes, &result);
    return result;
}

fn parseInto(bytes: []const u8, result: *Config) ParseError!void {
    if (bytes.len > max_file_bytes) return error.ConfigTooLarge;
    var seen: u16 = 0;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |physical| {
        if (physical.len > max_line_bytes) return error.MalformedValue;
        var line = physical;
        if (std.mem.indexOfScalar(u8, line, '#')) |comment|
            line = line[0..comment];
        line = trimAscii(line);
        if (line.len == 0) continue;
        var fields = std.mem.tokenizeAny(u8, line, " \t\r");
        const key = fields.next() orelse return error.MalformedValue;
        const bit = keyBit(key) orelse return error.UnknownKey;
        if (seen & bit != 0) return error.DuplicateKey;
        seen |= bit;
        switch (bit) {
            1 << 0 => try parseFontPath(fields.next(), result),
            else => unreachable,
        }
        if (fields.next() != null) return error.MalformedValue;
    }
    if (seen != (1 << key_count) - 1) return error.InvalidValue;
    return;
}

/// Loads one repository-local file into one complete typed startup value.
/// The returned value owns no heap bytes; the temporary file buffer is freed
/// before the value becomes visible to the process root.
pub fn loadFile(io: std.Io, allocator: std.mem.Allocator, path: []const u8) LoadError!Config {
    if (path.len == 0) return error.MalformedValue;
    const bytes = std.Io.Dir.cwd().readFileAlloc(
        io,
        path,
        allocator,
        .limited(max_file_bytes + 1),
    ) catch |failure| switch (failure) {
        error.StreamTooLong => return error.ConfigTooLarge,
        else => return failure,
    };
    defer allocator.free(bytes);
    return parse(bytes);
}

fn trimAscii(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t\r");
}

fn keyBit(key: []const u8) ?u16 {
    const names = [_][]const u8{"font.path"};
    for (names, 0..) |name, index| if (std.mem.eql(u8, key, name))
        return @as(u16, 1) << @intCast(index);
    return null;
}

fn parseFontPath(value: ?[]const u8, result: *Config) ParseError!void {
    const path = value orelse return error.MalformedValue;
    if (path.len == 0 or path.len > max_font_path_bytes) return error.InvalidValue;
    @memset(&result.font_path_bytes, 0);
    @memcpy(result.font_path_bytes[0..path.len], path);
    result.font_path_len = @intCast(path.len);
}

test "config parses the complete accepted typed file" {
    const parsed = try parse(
        "# comment\n" ++
            "font.path ../howl-render/testdata/primary.ttf\n",
    );
    try std.testing.expectEqual(Config.defaults(), parsed);
    try std.testing.expectEqualStrings("../howl-render/testdata/primary.ttf", parsed.fontPath());
}

test "typed font configuration layout receipt" {
    try std.testing.expectEqual(@as(usize, 242), @sizeOf(Config));
    try std.testing.expectEqual(@as(usize, 2), @alignOf(Config));
}

test "config rejects missing, duplicate, unknown, malformed, and oversized records" {
    const complete = "font.path ../howl-render/testdata/primary.ttf\n";
    try std.testing.expectError(error.DuplicateKey, parse(complete ++ complete));
    try std.testing.expectError(error.UnknownKey, parse("cursor.shape beam\n"));
    try std.testing.expectError(error.InvalidValue, parse(""));
    try std.testing.expectError(error.MalformedValue, parse("font.path one two\n"));
    var oversized: [max_file_bytes + 1]u8 = undefined;
    @memset(&oversized, 'x');
    try std.testing.expectError(error.ConfigTooLarge, parse(&oversized));
}

test "config rejects bounded physical lines" {
    var long_line: [max_line_bytes + 1]u8 = undefined;
    @memset(&long_line, 'x');
    try std.testing.expect(long_line.len < max_file_bytes);
    try std.testing.expectError(error.MalformedValue, parse(&long_line));
    try std.testing.expectError(error.MalformedValue, parse("font.path\n"));
}

test "font path is retained inline at its exact bound" {
    var config = Config.defaults();
    const maximum: [max_font_path_bytes]u8 = @splat('a');
    try parseFontPath(&maximum, &config);
    try std.testing.expectEqualStrings(&maximum, config.fontPath());

    const oversized: [max_font_path_bytes + 1]u8 = @splat('b');
    try std.testing.expectError(error.InvalidValue, parseFontPath(&oversized, &config));
    try std.testing.expectError(error.InvalidValue, parseFontPath("", &config));
    try std.testing.expectEqualStrings(&maximum, config.fontPath());
}

test "startup arguments prove explicit selection, ordering, and rejection" {
    const explicit = try parseArguments(&.{
        "howl-host", "--config", "/tmp/howl.conf",
    });
    try std.testing.expectEqualStrings("/tmp/howl.conf", explicit.config_path);
    try std.testing.expect(explicit.command == null);
    try std.testing.expectError(error.InvalidArguments, parseArguments(&.{ "howl-host", "--config", "a", "--config", "b" }));
    try std.testing.expectError(error.InvalidArguments, parseArguments(&.{ "howl-host", "--config" }));
    try std.testing.expectError(error.InvalidArguments, parseArguments(&.{ "howl-host", "--unknown", "value" }));
}

test "startup command is bounded, optional, and one-shot at the parser boundary" {
    const parsed = try parseArguments(&.{
        "howl-host", "--command", "printf fixture",
    });
    try std.testing.expectEqualStrings("printf fixture", parsed.command.?);
    var too_long: [max_command_bytes + 1]u8 = undefined;
    @memset(&too_long, 'x');
    try std.testing.expectError(error.InvalidArguments, parseArguments(&.{ "howl-host", "--command", &too_long }));
    try std.testing.expectError(error.InvalidArguments, parseArguments(&.{ "howl-host", "--command", "" }));
    try std.testing.expectError(error.InvalidArguments, parseArguments(&.{ "howl-host", "--command", "a", "--command", "b" }));
    try std.testing.expectError(error.InvalidArguments, parseArguments(&.{ "howl-host", "--command" }));
}

test "config rejects allocation before retaining any configuration bytes" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    const path = "config-allocation-failure.conf";
    {
        var file = try std.Io.Dir.cwd().createFile(std.testing.io, path, .{ .truncate = true });
        defer file.close(std.testing.io);
        var writer = file.writer(std.testing.io, &.{});
        try writer.interface.writeAll("font.path /tmp/font.ttf\n");
    }
    defer std.Io.Dir.cwd().deleteFile(std.testing.io, path) catch {};
    try std.testing.expectError(error.OutOfMemory, loadFile(std.testing.io, failing.allocator(), path));
}

test "config reports a missing explicit file" {
    const path = "config-missing.conf";
    std.Io.Dir.cwd().deleteFile(std.testing.io, path) catch {};
    try std.testing.expectError(
        error.FileNotFound,
        loadFile(std.testing.io, std.testing.allocator, path),
    );
}

test "repository-local config validates at its compiled default path" {
    const loaded = try loadFile(std.testing.io, std.testing.allocator, default_path);
    try std.testing.expectEqualStrings(
        "/usr/share/fonts/TTF/IosevkaTermNerdFont-Regular.ttf",
        loaded.fontPath(),
    );
}

test "explicit config retains the exact font path" {
    const path = "config-explicit.conf";
    {
        var file = try std.Io.Dir.cwd().createFile(std.testing.io, path, .{ .truncate = true });
        defer file.close(std.testing.io);
        var writer = file.writer(std.testing.io, &.{});
        try writer.interface.writeAll("font.path /tmp/operator-font.ttf\n");
    }
    defer std.Io.Dir.cwd().deleteFile(std.testing.io, path) catch {};
    const loaded = try loadFile(std.testing.io, std.testing.allocator, path);
    try std.testing.expectEqualStrings("/tmp/operator-font.ttf", loaded.fontPath());
}
