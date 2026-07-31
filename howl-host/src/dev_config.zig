//! Owns the bounded repository-local startup configuration for the host.
//!
//! The process root reads this file once before constructing any Boundary or
//! runtime thread. Validation retains no configuration value at this stage;
//! cursor owners consume narrow typed views in the next checkpoint.

const std = @import("std");
const build_options = @import("dev_config_options");

/// The largest accepted development configuration file, including comments.
pub const max_file_bytes: usize = 4096;
/// The largest single physical line accepted before comment stripping.
pub const max_line_bytes: usize = 256;
/// The repository-local configuration used when `--config` is absent.
pub const default_path: []const u8 = build_options.repository_config_path;

/// Selects the configured cursor shape.
pub const CursorShape = enum { block, beam, underline };
/// Selects the configured unfocused cursor shape.
pub const UnfocusedCursorShape = enum { hollow, block, beam, underline };
/// Selects the bounded blink interval policy.
pub const BlinkInterval = enum { system };
/// Selects the bounded trail color policy.
pub const TrailColor = enum { cursor };

/// Retains one exact sRGB cursor color.
pub const Color = struct {
    /// Red channel.
    r: u8,
    /// Green channel.
    g: u8,
    /// Blue channel.
    b: u8,
};

/// Retains the two Kitty-compatible trail decay endpoints in seconds.
pub const TrailDecay = struct {
    /// Initial retained trail opacity endpoint in seconds.
    start_seconds: f64,
    /// Final retained trail opacity endpoint in seconds.
    end_seconds: f64,
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
    /// Blink interval policy.
    blink_interval: BlinkInterval,
    /// Inactivity duration after which blinking stops.
    stop_blinking_after_seconds: f64,
    /// Cursor-trail delay in milliseconds.
    trail_delay_ms: u32,
    /// Cursor-trail decay endpoints.
    trail_decay_seconds: TrailDecay,
    /// Number of cursor cells required before trail admission.
    trail_start_threshold_cells: u16,
    /// Cursor-trail color policy.
    trail_color: TrailColor,
};

/// Represents one complete validated configuration for parser-boundary tests.
pub const Config = struct {
    /// Complete immutable cursor configuration.
    cursor: CursorConfig,

    /// Returns the accepted operator-resolved development values.
    pub fn defaults() Config {
        return .{
            .cursor = .{
                .shape = .beam,
                .color = .{ .r = 0x73, .g = 0xf9, .b = 0x90 },
                .unfocused_shape = .hollow,
                .beam_thickness_points = 1.5,
                .underline_thickness_points = 2.0,
                .blink_interval = .system,
                .stop_blinking_after_seconds = 15.0,
                .trail_delay_ms = 1,
                .trail_decay_seconds = .{ .start_seconds = 0.1, .end_seconds = 0.4 },
                .trail_start_threshold_cells = 0,
                .trail_color = .cursor,
            },
        };
    }
};

/// Retains the two process-root command-line paths after bounded parsing.
pub const ParsedArguments = struct {
    font_path: []const u8,
    config_path: []const u8,
};

/// Parses the complete bounded startup argument vector without allocation.
pub fn parseArguments(args: []const []const u8) error{InvalidArguments}!ParsedArguments {
    if (args.len == 0 or args[0].len == 0) return error.InvalidArguments;
    var font_path: ?[]const u8 = null;
    var config_path: []const u8 = default_path;
    var config_seen = false;
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const argument = args[index];
        if (std.mem.eql(u8, argument, "--font")) {
            if (font_path != null or index + 1 >= args.len) return error.InvalidArguments;
            index += 1;
            font_path = args[index];
            if (font_path.?.len == 0) return error.InvalidArguments;
        } else if (std.mem.eql(u8, argument, "--config")) {
            if (config_seen or index + 1 >= args.len) return error.InvalidArguments;
            config_seen = true;
            index += 1;
            config_path = args[index];
            if (config_path.len == 0) return error.InvalidArguments;
        } else return error.InvalidArguments;
    }
    return .{
        .font_path = font_path orelse return error.InvalidArguments,
        .config_path = config_path,
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

const key_count = 11;

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
            1 << 0 => result.cursor.shape = try parseEnum(CursorShape, fields.next()),
            1 << 1 => result.cursor.color = try parseColor(fields.next()),
            1 << 2 => result.cursor.unfocused_shape = try parseEnum(UnfocusedCursorShape, fields.next()),
            1 << 3 => result.cursor.beam_thickness_points = try parsePositiveFloat(fields.next()),
            1 << 4 => result.cursor.underline_thickness_points = try parsePositiveFloat(fields.next()),
            1 << 5 => result.cursor.blink_interval = try parseEnum(BlinkInterval, fields.next()),
            1 << 6 => result.cursor.stop_blinking_after_seconds = try parseNonNegativeFloat(fields.next()),
            1 << 7 => result.cursor.trail_delay_ms = try parseUnsigned(u32, fields.next()),
            1 << 8 => {
                result.cursor.trail_decay_seconds.start_seconds =
                    try parseNonNegativeFloat(fields.next());
                result.cursor.trail_decay_seconds.end_seconds =
                    try parseNonNegativeFloat(fields.next());
                if (result.cursor.trail_decay_seconds.end_seconds <
                    result.cursor.trail_decay_seconds.start_seconds)
                    return error.InvalidValue;
            },
            1 << 9 => result.cursor.trail_start_threshold_cells =
                try parseUnsigned(u16, fields.next()),
            1 << 10 => result.cursor.trail_color = try parseEnum(TrailColor, fields.next()),
            else => unreachable,
        }
        if (fields.next() != null) return error.MalformedValue;
    }
    if (seen != (1 << key_count) - 1) return error.InvalidValue;
    return;
}

/// Validates one repository-local file without retaining its typed result.
/// Temporary file bytes are freed on parser failure and allocation failure.
pub fn validateFile(io: std.Io, allocator: std.mem.Allocator, path: []const u8) LoadError!void {
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
    var validated = Config.defaults();
    try parseInto(bytes, &validated);
}

fn trimAscii(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t\r");
}

fn keyBit(key: []const u8) ?u16 {
    const names = [_][]const u8{
        "cursor.shape",
        "cursor.color",
        "cursor.unfocused_shape",
        "cursor.beam_thickness_points",
        "cursor.underline_thickness_points",
        "cursor.blink_interval",
        "cursor.stop_blinking_after_seconds",
        "cursor.trail_delay_ms",
        "cursor.trail_decay_seconds",
        "cursor.trail_start_threshold_cells",
        "cursor.trail_color",
    };
    for (names, 0..) |name, index| if (std.mem.eql(u8, key, name))
        return @as(u16, 1) << @intCast(index);
    return null;
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

fn parseUnsigned(comptime T: type, value: ?[]const u8) ParseError!T {
    const text = value orelse return error.MalformedValue;
    return std.fmt.parseInt(T, text, 10) catch return error.InvalidValue;
}

test "development config parses the complete accepted typed file" {
    const parsed = try parse(
        "# comment\n" ++
            "cursor.shape beam\n" ++
            "cursor.color #73f990\n" ++
            "cursor.unfocused_shape hollow\n" ++
            "cursor.beam_thickness_points 1.5\n" ++
            "cursor.underline_thickness_points 2.0\n" ++
            "cursor.blink_interval system\n" ++
            "cursor.stop_blinking_after_seconds 15.0\n" ++
            "cursor.trail_delay_ms 1\n" ++
            "cursor.trail_decay_seconds 0.1 0.4\n" ++
            "cursor.trail_start_threshold_cells 0\n" ++
            "cursor.trail_color cursor\n",
    );
    try std.testing.expectEqual(Config.defaults(), parsed);
}

test "development config rejects missing, duplicate, unknown, malformed, and oversized records" {
    const complete = "cursor.shape beam\n" ++
        "cursor.color #73f990\n" ++
        "cursor.unfocused_shape hollow\n" ++
        "cursor.beam_thickness_points 1.5\n" ++
        "cursor.underline_thickness_points 2.0\n" ++
        "cursor.blink_interval system\n" ++
        "cursor.stop_blinking_after_seconds 15.0\n" ++
        "cursor.trail_delay_ms 1\n" ++
        "cursor.trail_decay_seconds 0.1 0.4\n" ++
        "cursor.trail_start_threshold_cells 0\n" ++
        "cursor.trail_color cursor\n";
    try std.testing.expectError(error.DuplicateKey, parse(complete ++ "cursor.shape beam\n"));
    try std.testing.expectError(error.UnknownKey, parse("cursor.nope value\n"));
    try std.testing.expectError(error.InvalidValue, parse("cursor.color nope\n"));
    try std.testing.expectError(error.MalformedValue, parse("cursor.shape beam extra\n"));
    var oversized: [max_file_bytes + 1]u8 = undefined;
    @memset(&oversized, 'x');
    try std.testing.expectError(error.ConfigTooLarge, parse(&oversized));
}

test "development config rejects bounded physical lines and invalid typed values" {
    var long_line: [max_line_bytes + 1]u8 = undefined;
    @memset(&long_line, 'x');
    try std.testing.expect(long_line.len < max_file_bytes);
    try std.testing.expectError(error.MalformedValue, parse(&long_line));
    try std.testing.expectError(error.InvalidValue, parse("cursor.shape diagonal\n"));
    try std.testing.expectError(error.InvalidValue, parse("cursor.beam_thickness_points -1\n"));
    try std.testing.expectError(error.InvalidValue, parse("cursor.beam_thickness_points nan\n"));
    try std.testing.expectError(error.InvalidValue, parse("cursor.beam_thickness_points inf\n"));
    try std.testing.expectError(error.InvalidValue, parse("cursor.trail_decay_seconds 0.4 0.1\n"));
    try std.testing.expectError(error.InvalidValue, parse("cursor.trail_delay_ms -1\n"));
    try std.testing.expectError(error.InvalidValue, parse("cursor.trail_delay_ms 4294967296\n"));
    try std.testing.expectError(error.InvalidValue, parse("cursor.trail_start_threshold_cells 65536\n"));
    try std.testing.expectError(error.MalformedValue, parse("cursor.trail_decay_seconds 0.1\n"));
}

test "startup arguments prove explicit selection, ordering, and rejection" {
    const explicit = try parseArguments(&.{
        "howl-host", "--config", "/tmp/howl.conf", "--font", "font.ttf",
    });
    try std.testing.expectEqualStrings("/tmp/howl.conf", explicit.config_path);
    try std.testing.expectEqualStrings("font.ttf", explicit.font_path);
    const reversed = try parseArguments(&.{
        "howl-host", "--font", "font.ttf", "--config", "/tmp/howl.conf",
    });
    try std.testing.expectEqualStrings(explicit.config_path, reversed.config_path);
    try std.testing.expectError(error.InvalidArguments, parseArguments(&.{ "howl-host", "--config", "a", "--config", "b", "--font", "f" }));
    try std.testing.expectError(error.InvalidArguments, parseArguments(&.{ "howl-host", "--config" }));
    try std.testing.expectError(error.InvalidArguments, parseArguments(&.{ "howl-host", "--font", "f", "--unknown", "x" }));
}

test "development config rejects allocation before retaining any configuration bytes" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    const path = "dev-config-allocation-failure.conf";
    {
        var file = try std.Io.Dir.cwd().createFile(std.testing.io, path, .{ .truncate = true });
        defer file.close(std.testing.io);
        var writer = file.writer(std.testing.io, &.{});
        try writer.interface.writeAll("cursor.shape beam\n");
    }
    defer std.Io.Dir.cwd().deleteFile(std.testing.io, path) catch {};
    try std.testing.expectError(error.OutOfMemory, validateFile(std.testing.io, failing.allocator(), path));
}

test "development config reports a missing explicit file" {
    const path = "dev-config-missing.conf";
    std.Io.Dir.cwd().deleteFile(std.testing.io, path) catch {};
    try std.testing.expectError(
        error.FileNotFound,
        validateFile(std.testing.io, std.testing.allocator, path),
    );
}

test "repository-local development config validates at its compiled default path" {
    try validateFile(std.testing.io, std.testing.allocator, default_path);
}

test "explicit config path selects the requested file" {
    const path = "dev-config-explicit.conf";
    {
        var file = try std.Io.Dir.cwd().createFile(std.testing.io, path, .{ .truncate = true });
        defer file.close(std.testing.io);
        var writer = file.writer(std.testing.io, &.{});
        try writer.interface.writeAll(
            "cursor.shape underline\n" ++
                "cursor.color #010203\n" ++
                "cursor.unfocused_shape beam\n" ++
                "cursor.beam_thickness_points 2\n" ++
                "cursor.underline_thickness_points 3\n" ++
                "cursor.blink_interval system\n" ++
                "cursor.stop_blinking_after_seconds 0\n" ++
                "cursor.trail_delay_ms 7\n" ++
                "cursor.trail_decay_seconds 0.2 0.3\n" ++
                "cursor.trail_start_threshold_cells 4\n" ++
                "cursor.trail_color cursor\n",
        );
    }
    defer std.Io.Dir.cwd().deleteFile(std.testing.io, path) catch {};
    try validateFile(std.testing.io, std.testing.allocator, path);
}
