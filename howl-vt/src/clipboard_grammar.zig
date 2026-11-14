//! Pure canonical OSC 52 envelope and replacement grammar.
const std = @import("std");
/// Maximum exact selector bytes accepted by VT.
pub const maximum_selection_bytes: u8 = 12;
/// Native OSC 52 operation inferred from the complete body.
pub const Kind = enum { set, query };
/// Immutable slices borrow the complete caller payload.
pub const ParsedRequest = struct { selection: []const u8, data: []const u8, kind: Kind };
/// Classifies one complete payload, including replacement Base64 validity.
pub fn parse(raw: []const u8) ?ParsedRequest {
    const request = parseEnvelope(raw) orelse return null;
    if (request.kind == .set and !validBase64(request.data)) return null;
    return request;
}
/// Validates selector and separator only; callers still validate replacement data.
pub fn parseEnvelope(raw: []const u8) ?ParsedRequest {
    const separator = std.mem.indexOfScalar(u8, raw, ';') orelse return null;
    const selection = raw[0..separator];
    if (selection.len > maximum_selection_bytes) return null;
    for (selection) |byte| switch (byte) {
        'c', 'p', 'q', 's', '0'...'7' => {},
        else => return null,
    };
    const data = raw[separator + 1 ..];
    return .{
        .selection = selection,
        .data = data,
        .kind = if (std.mem.eql(u8, data, "?")) .query else .set,
    };
}

fn validBase64(data: []const u8) bool {
    if (data.len % 4 != 0) return false;
    var padding: u2 = 0;
    for (data, 0..) |byte, index| switch (byte) {
        'A'...'Z', 'a'...'z', '0'...'9', '+', '/' => if (padding != 0) return false,
        '=' => {
            if (index < data.len -| 2 or padding == 2) return false;
            padding += 1;
        },
        else => return false,
    };
    return true;
}

test "OSC 52 grammar preserves selection and operation identity" {
    const replacement = parse("cp07;SG93bA==").?;
    try std.testing.expectEqualStrings("cp07", replacement.selection);
    try std.testing.expectEqualStrings("SG93bA==", replacement.data);
    try std.testing.expect(replacement.kind == .set);

    const query = parse(";?").?;
    try std.testing.expectEqualStrings("", query.selection);
    try std.testing.expect(query.kind == .query);

    try std.testing.expect(parse("x;SG93bA==") == null);
    try std.testing.expect(parse("c;!!!!") == null);
    try std.testing.expect(parse("c;?trailing") == null);
    try std.testing.expect(parse("ccccccccccccc;") == null);
}
