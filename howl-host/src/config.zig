//! Owns bounded repository-local startup configuration for the host.
//!
//! The process root reads this file once before constructing any Boundary or
//! runtime thread. The process root retains one typed value, then copies only
//! owner-specific cursor views into the Host terminal and Renderer owners.

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

/// Selects the configured cursor shape.
pub const CursorShape = enum { block, beam, underline };
/// Selects the configured unfocused cursor shape.
pub const UnfocusedCursorShape = enum { hollow, block, beam, underline };

/// Retains one exact sRGB cursor color.
pub const Color = struct {
    /// Red channel.
    r: u8,
    /// Green channel.
    g: u8,
    /// Blue channel.
    b: u8,
};

/// Retains all accepted cursor configuration without a string dictionary.
pub const CursorConfig = struct {
    /// Focused cursor shape.
    shape: CursorShape,
    /// Focused cursor color.
    color: Color,
    /// Unfocused cursor shape.
    unfocused_shape: UnfocusedCursorShape,
    /// Beam thickness in points.
    beam_thickness_points: f64,
    /// Underline thickness in points.
    underline_thickness_points: f64,
};

/// Retains the configured semantic cursor shape for the Host terminal owner.
pub const CursorSemanticPolicy = struct {
    /// Configured default semantic cursor shape.
    shape: CursorShape,
};

/// Retains all cursor presentation policy for the Host Renderer owner.
pub const CursorPresentationPolicy = struct {
    /// Configured focused cursor color.
    color: Color,
    /// Configured shape used while the window is unfocused.
    unfocused_shape: UnfocusedCursorShape,
    /// Configured beam thickness in points.
    beam_thickness_points: f64,
    /// Configured underline thickness in points.
    underline_thickness_points: f64,
};

/// The only two cursor views that process-root startup may distribute.
pub const OwnerViews = struct {
    /// Exact view retained by the Host terminal owner.
    terminal: CursorSemanticPolicy,
    /// Exact view retained by the Host Renderer owner.
    renderer: CursorPresentationPolicy,
};

/// Represents one complete validated configuration for parser-boundary tests.
pub const Config = struct {
    /// Inline storage for the configured primary terminal font path.
    font_path_bytes: [max_font_path_bytes]u8,
    /// Initialized prefix of `font_path_bytes`.
    font_path_len: u16,
    /// Complete immutable cursor configuration.
    cursor: CursorConfig,

    /// Returns the accepted operator-resolved development values.
    pub fn defaults() Config {
        const default_font_path = "../howl-render/testdata/primary.ttf";
        var result: Config = .{
            .font_path_bytes = @splat(0),
            .font_path_len = default_font_path.len,
            .cursor = .{
                .shape = .beam,
                .color = .{ .r = 0x73, .g = 0xf9, .b = 0x90 },
                .unfocused_shape = .hollow,
                .beam_thickness_points = 1.5,
                .underline_thickness_points = 2.0,
            },
        };
        @memcpy(result.font_path_bytes[0..default_font_path.len], default_font_path);
        return result;
    }

    /// Borrows the configured font path for the lifetime of this value.
    pub fn fontPath(self: *const Config) []const u8 {
        return self.font_path_bytes[0..self.font_path_len];
    }

    /// Copies only the semantic shape for the Host terminal owner.
    pub fn semanticPolicy(self: *const Config) CursorSemanticPolicy {
        return .{ .shape = self.cursor.shape };
    }

    /// Copies all presentation policy for the Host Renderer owner.
    pub fn presentationPolicy(self: *const Config) CursorPresentationPolicy {
        return .{
            .color = self.cursor.color,
            .unfocused_shape = self.cursor.unfocused_shape,
            .beam_thickness_points = self.cursor.beam_thickness_points,
            .underline_thickness_points = self.cursor.underline_thickness_points,
        };
    }

    /// Derives the exact two owner views used by process-root startup.
    pub fn ownerViews(self: *const Config) OwnerViews {
        return .{
            .terminal = self.semanticPolicy(),
            .renderer = self.presentationPolicy(),
        };
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

const key_count = 6;

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
        if (std.mem.indexOfScalar(u8, line, '#')) |comment| {
            // The color value is the one intentional hash-prefixed token in
            // this grammar; a later hash on the same record still starts a
            // comment.
            const prefix = trimAscii(line[0..comment]);
            if (!std.mem.eql(u8, prefix, "cursor.color")) {
                line = line[0..comment];
            } else if (std.mem.indexOfScalarPos(u8, line, comment + 1, '#')) |trailing| {
                line = line[0..trailing];
            }
        }
        line = trimAscii(line);
        if (line.len == 0) continue;
        var fields = std.mem.tokenizeAny(u8, line, " \t\r");
        const key = fields.next() orelse return error.MalformedValue;
        const bit = keyBit(key) orelse return error.UnknownKey;
        if (seen & bit != 0) return error.DuplicateKey;
        seen |= bit;
        switch (bit) {
            1 << 0 => try parseFontPath(fields.next(), result),
            1 << 1 => result.cursor.shape = try parseEnum(CursorShape, fields.next()),
            1 << 2 => result.cursor.color = try parseColor(fields.next()),
            1 << 3 => result.cursor.unfocused_shape = try parseEnum(UnfocusedCursorShape, fields.next()),
            1 << 4 => result.cursor.beam_thickness_points = try parsePositiveFloat(fields.next()),
            1 << 5 => result.cursor.underline_thickness_points = try parsePositiveFloat(fields.next()),
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
    const names = [_][]const u8{
        "font.path",
        "cursor.shape",
        "cursor.color",
        "cursor.unfocused_shape",
        "cursor.beam_thickness_points",
        "cursor.underline_thickness_points",
    };
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

fn parseEnum(comptime T: type, value: ?[]const u8) ParseError!T {
    const text = value orelse return error.MalformedValue;
    return std.meta.stringToEnum(T, text) orelse error.InvalidValue;
}

fn parseColor(value: ?[]const u8) ParseError!Color {
    const text = value orelse return error.MalformedValue;
    if (text.len != 7 or text[0] != '#') return error.InvalidValue;
    return .{
        .r = parseHexByte(text[1..3]) catch return error.InvalidValue,
        .g = parseHexByte(text[3..5]) catch return error.InvalidValue,
        .b = parseHexByte(text[5..7]) catch return error.InvalidValue,
    };
}

fn parseHexByte(text: []const u8) error{Invalid}!u8 {
    if (text.len != 2) return error.Invalid;
    const high = hexDigit(text[0]) orelse return error.Invalid;
    const low = hexDigit(text[1]) orelse return error.Invalid;
    return (@as(u8, high) << 4) | low;
}

fn hexDigit(value: u8) ?u8 {
    return switch (value) {
        '0'...'9' => value - '0',
        'a'...'f' => value - 'a' + 10,
        'A'...'F' => value - 'A' + 10,
        else => null,
    };
}

fn parsePositiveFloat(value: ?[]const u8) ParseError!f64 {
    const result = try parseFloat(value);
    if (result <= 0.0) return error.InvalidValue;
    return result;
}

fn parseNonNegativeFloat(value: ?[]const u8) ParseError!f64 {
    const result = try parseFloat(value);
    if (result < 0.0) return error.InvalidValue;
    return result;
}

fn parseFloat(value: ?[]const u8) ParseError!f64 {
    const text = value orelse return error.MalformedValue;
    const result = std.fmt.parseFloat(f64, text) catch return error.InvalidValue;
    if (!std.math.isFinite(result) or std.math.isNan(result)) return error.InvalidValue;
    return result;
}

test "config parses the complete accepted typed file" {
    const parsed = try parse(
        "# comment\n" ++
            "font.path ../howl-render/testdata/primary.ttf\n" ++
            "cursor.shape beam\n" ++
            "cursor.color #73f990\n" ++
            "cursor.unfocused_shape hollow\n" ++
            "cursor.beam_thickness_points 1.5\n" ++
            "cursor.underline_thickness_points 2.0\n",
    );
    try std.testing.expectEqual(Config.defaults(), parsed);
    try std.testing.expectEqualStrings("../howl-render/testdata/primary.ttf", parsed.fontPath());
    try std.testing.expectEqual(
        CursorSemanticPolicy{ .shape = .beam },
        parsed.semanticPolicy(),
    );
    try std.testing.expectEqual(parsed.cursor.beam_thickness_points, parsed.presentationPolicy().beam_thickness_points);
}

test "typed owner views copy values without retaining the complete config" {
    var config = Config.defaults();
    const semantic = config.semanticPolicy();
    const presentation = config.presentationPolicy();
    config.cursor.shape = .underline;
    config.cursor.beam_thickness_points = 7.0;
    try std.testing.expectEqual(CursorShape.beam, semantic.shape);
    try std.testing.expectEqual(@as(f64, 1.5), presentation.beam_thickness_points);
}

test "typed cursor configuration layout receipt" {
    // Pinned after removing unsupported Host blink and trail presentation.
    try std.testing.expectEqual(@as(usize, 272), @sizeOf(Config));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(Config));
    try std.testing.expectEqual(@as(usize, 1), @sizeOf(CursorSemanticPolicy));
    try std.testing.expectEqual(@as(usize, 1), @alignOf(CursorSemanticPolicy));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(CursorPresentationPolicy));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(CursorPresentationPolicy));
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(OwnerViews));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(OwnerViews));
}

test "config rejects missing, duplicate, unknown, malformed, and oversized records" {
    const complete = "font.path ../howl-render/testdata/primary.ttf\n" ++
        "cursor.shape beam\n" ++
        "cursor.color #73f990\n" ++
        "cursor.unfocused_shape hollow\n" ++
        "cursor.beam_thickness_points 1.5\n" ++
        "cursor.underline_thickness_points 2.0\n";
    try std.testing.expectError(error.DuplicateKey, parse(complete ++ "cursor.shape beam\n"));
    try std.testing.expectError(error.UnknownKey, parse("cursor.nope value\n"));
    try std.testing.expectError(error.InvalidValue, parse("cursor.color nope\n"));
    try std.testing.expectError(error.MalformedValue, parse("cursor.shape beam extra\n"));
    var oversized: [max_file_bytes + 1]u8 = undefined;
    @memset(&oversized, 'x');
    try std.testing.expectError(error.ConfigTooLarge, parse(&oversized));
}

test "config rejects bounded physical lines and invalid typed values" {
    var long_line: [max_line_bytes + 1]u8 = undefined;
    @memset(&long_line, 'x');
    try std.testing.expect(long_line.len < max_file_bytes);
    try std.testing.expectError(error.MalformedValue, parse(&long_line));
    try std.testing.expectError(error.InvalidValue, parse("cursor.shape diagonal\n"));
    try std.testing.expectError(error.InvalidValue, parse("cursor.beam_thickness_points -1\n"));
    try std.testing.expectError(error.InvalidValue, parse("cursor.beam_thickness_points nan\n"));
    try std.testing.expectError(error.InvalidValue, parse("cursor.beam_thickness_points inf\n"));
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
        try writer.interface.writeAll("cursor.shape beam\n");
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
    const owners = loaded.ownerViews();
    try std.testing.expectEqual(CursorShape.beam, owners.terminal.shape);
    try std.testing.expectEqual(Color{ .r = 0x73, .g = 0xf9, .b = 0x90 }, owners.renderer.color);
    try std.testing.expectEqual(UnfocusedCursorShape.hollow, owners.renderer.unfocused_shape);
}

test "explicit config retains font and exact cursor owner views" {
    const path = "config-explicit.conf";
    {
        var file = try std.Io.Dir.cwd().createFile(std.testing.io, path, .{ .truncate = true });
        defer file.close(std.testing.io);
        var writer = file.writer(std.testing.io, &.{});
        try writer.interface.writeAll(
            "font.path /tmp/operator-font.ttf\n" ++
                "cursor.shape underline\n" ++
                "cursor.color #010203\n" ++
                "cursor.unfocused_shape beam\n" ++
                "cursor.beam_thickness_points 2\n" ++
                "cursor.underline_thickness_points 3\n",
        );
    }
    defer std.Io.Dir.cwd().deleteFile(std.testing.io, path) catch {};
    const loaded = try loadFile(std.testing.io, std.testing.allocator, path);
    const owners = loaded.ownerViews();
    try std.testing.expectEqualStrings("/tmp/operator-font.ttf", loaded.fontPath());
    try std.testing.expectEqual(CursorSemanticPolicy{ .shape = .underline }, owners.terminal);
    try std.testing.expectEqual(Color{ .r = 1, .g = 2, .b = 3 }, owners.renderer.color);
    try std.testing.expectEqual(UnfocusedCursorShape.beam, owners.renderer.unfocused_shape);
    try std.testing.expectEqual(@as(f64, 2.0), owners.renderer.beam_thickness_points);
    try std.testing.expectEqual(@as(f64, 3.0), owners.renderer.underline_thickness_points);
}
