const std = @import("std");
const vt = @import("howl_vt");

/// Existing HTTP(S) desktop link policy's maximum URI bytes.
pub const uri_limit = 2048;
/// Existing file-drop path bound before POSIX quoting.
pub const file_limit = 4096;
/// Existing exact text-drop bound.
pub const text_limit = 64 * 1024;
/// Worst-case single-quote spelling, including closing quote and trailing separator.
pub const quoted_limit = file_limit * 4 + 3;
/// Exact file/text rejection; a drop never executes or interprets its content.
pub const DropError = error{ InvalidDrop, DropLimit };

/// Allows only explicit canonical HTTP(S), preserving Odin's bounded UTF-8 policy.
pub fn uriAllowed(uri: []const u8) bool {
    if (uri.len == 0 or uri.len > uri_limit or !std.unicode.utf8ValidateSlice(uri)) return false;
    for (uri) |byte| if (byte <= 0x20 or byte == 0x7f) return false;
    for ([_][]const u8{ "http://", "https://" }) |prefix|
        if (uri.len > prefix.len and std.ascii.eqlIgnoreCase(uri[0..prefix.len], prefix)) return true;
    return false;
}
/// Quotes one path as terminal paste text, keeping a trailing argument separator.
pub fn quoteFile(path: []const u8, output: []u8) DropError![]const u8 {
    if (path.len > file_limit) return error.DropLimit;
    if (path.len == 0 or !std.unicode.utf8ValidateSlice(path) or std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidDrop;
    var needed: usize = 3;
    for (path) |byte| needed += if (byte == '\'') @as(usize, 4) else 1;
    if (needed > output.len) return error.DropLimit;
    output[0] = '\'';
    var offset: usize = 1;
    for (path) |byte| {
        if (byte == '\'') {
            @memcpy(output[offset..][0..4], "'\\''");
            offset += 4;
        } else {
            output[offset] = byte;
            offset += 1;
        }
    }
    output[offset] = '\'';
    output[offset + 1] = ' ';
    return output[0 .. offset + 2];
}
/// Validates exact text paste without changing bytes or executing a shell.
pub fn dropText(text: []const u8) DropError![]const u8 {
    if (text.len > text_limit) return error.DropLimit;
    if (text.len == 0 or !std.unicode.utf8ValidateSlice(text) or std.mem.indexOfScalar(u8, text, 0) != null) return error.InvalidDrop;
    return text;
}
/// Measures SDL-owned sentinel data only within the accepted drop bound.
pub fn eventText(data: [*:0]const u8, file: bool) DropError![]const u8 {
    const limit: usize = if (file) file_limit else text_limit;
    for (0..limit + 1) |offset| if (data[offset] == 0) return data[0..offset];
    return error.DropLimit;
}
test "desktop HTTP policy rejects nonbrowser schemes whitespace controls malformed UTF8 and oversize" {
    for ([_][]const u8{ "https://howl.example/path?q=1", "HTTP://example.com", "http://127.0.0.1:8080/x", "https://例.example/界" }) |uri|
        try std.testing.expect(uriAllowed(uri));
    for ([_][]const u8{ "", "https://", "file:///secret", "mailto:a@b", "javascript:alert(1)", "https://example.com/a b", "https://example.com/a\nb", "https://x\x00y", "https://\xff" }) |uri|
        try std.testing.expect(!uriAllowed(uri));
    const too_long: [uri_limit + 1]u8 = @splat('x');
    try std.testing.expect(!uriAllowed(&too_long));
}
test "file and text drop preserve exact paste spelling while rejecting invalid and bounded inputs" {
    var output: [quoted_limit]u8 = undefined;
    try std.testing.expectEqualStrings("'/notes/Captain'\\''s $(touch nope).txt' ", try quoteFile("/notes/Captain's $(touch nope).txt", &output));
    try std.testing.expectEqualStrings("line one\n界 line two", try dropText("line one\n界 line two"));
    for ([_][]const u8{ "", "a\x00b", "\xff" }) |bad| {
        try std.testing.expectError(error.InvalidDrop, quoteFile(bad, &output));
        try std.testing.expectError(error.InvalidDrop, dropText(bad));
    }
    var short: [2]u8 = undefined;
    try std.testing.expectError(error.DropLimit, quoteFile("abc", &short));
    const huge: [file_limit + 1]u8 = @splat('x');
    try std.testing.expectError(error.DropLimit, quoteFile(&huge, &output));
    const huge_text: [text_limit + 1:0]u8 = @splat('x');
    try std.testing.expectError(error.DropLimit, dropText(&huge_text));
    try std.testing.expectError(error.DropLimit, eventText(&huge_text, false));
    try std.testing.expectError(error.DropLimit, eventText(&huge_text, true));
    try std.testing.expectEqualStrings("界\nline", try eventText("界\nline", false));
    const full: [file_limit]u8 = @splat('\'');
    try std.testing.expectEqual(@as(usize, quoted_limit), (try quoteFile(&full, &output)).len);
}

/// Host light/dark preference follows the configured background, independently of app chrome.
pub fn colorPreference(background: vt.Terminal.Rgb) vt.Terminal.ColorSchemePreference {
    const luma = @as(u32, background.r) * 299 + @as(u32, background.g) * 587 + @as(u32, background.b) * 114;
    return if (luma >= 128000) .light else .dark;
}
test "terminal background decides host color preference rather than application chrome" {
    try std.testing.expectEqual(vt.Terminal.ColorSchemePreference.light, colorPreference(.{ .r = 246, .g = 244, .b = 239 }));
    try std.testing.expectEqual(vt.Terminal.ColorSchemePreference.dark, colorPreference(.{ .r = 24, .g = 25, .b = 33 }));
}
