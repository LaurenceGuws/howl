//! Owns the executable's single explicit font-path argument.

const std = @import("std");
const howl_text = @import("howl_text");

/// Reports an absent, extra, oversized, or ambiguous font-path argument.
pub const Error = error{
    missing_font_path,
    extra_argument,
    font_path_too_long,
    font_path_contains_nul,
};

/// Returns exactly one bounded NUL-free path borrowed from the process args.
pub fn fontPath(arguments: []const []const u8) Error![]const u8 {
    if (arguments.len < 2) return error.missing_font_path;
    if (arguments.len > 2) return error.extra_argument;
    const path = arguments[1];
    if (path.len > howl_text.max_font_path_bytes)
        return error.font_path_too_long;
    if (std.mem.indexOfScalar(u8, path, 0) != null)
        return error.font_path_contains_nul;
    return path;
}

test "CLI requires exactly one bounded NUL-free font path" {
    try std.testing.expectError(error.missing_font_path, fontPath(&.{"howl-host"}));
    try std.testing.expectError(
        error.extra_argument,
        fontPath(&.{ "howl-host", "font.ttf", "extra" }),
    );
    var oversized: [howl_text.max_font_path_bytes + 1]u8 = undefined;
    @memset(&oversized, 'x');
    try std.testing.expectError(
        error.font_path_too_long,
        fontPath(&.{ "howl-host", &oversized }),
    );
    try std.testing.expectError(
        error.font_path_contains_nul,
        fontPath(&.{ "howl-host", "font\x00ignored" }),
    );
    try std.testing.expectEqualStrings(
        "/fonts/primary.ttf",
        try fontPath(&.{ "howl-host", "/fonts/primary.ttf" }),
    );
}
