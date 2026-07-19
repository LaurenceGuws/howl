//! Decodes bounded iTerm shell-integration controls with terminal-owned effects.

const std = @import("std");
const cursor = @import("screen/cursor.zig");

/// Borrows one parsed OSC 133 shell mark until parser mutation.
pub const ShellMark = struct {
    kind: u8,
    status: ?i32,
    metadata: []const u8,
};

/// Borrows a decimal version and optional bounded `shell` identity.
/// Duplicate, malformed, or unknown suffix keys reject the complete update.
pub const ShellIntegration = struct {
    version: u32,
    shell: ?[]const u8,
};

/// Bounds one shell name without creating a generic metadata namespace.
pub const shell_name_max_bytes: u8 = 32;

/// Names iTerm controls whose effects are safe inside the native terminal contract.
pub const Command = union(enum) {
    cursor_shape: cursor.CursorShape,
    report_cell_size,
    set_colors: []const u8,
    shell_integration: ShellIntegration,
};

/// Decodes one borrowed OSC 50 or 1337 payload under its exact command family.
pub fn parse(osc_command: u16, payload: []const u8) ?Command {
    return switch (osc_command) {
        50 => parseCursorShape(payload),
        1337 => parse1337(payload),
        else => null,
    };
}

fn parse1337(payload: []const u8) ?Command {
    const separator = std.mem.indexOfScalar(u8, payload, '=') orelse {
        return if (std.mem.eql(u8, payload, "ReportCellSize"))
            .report_cell_size
        else
            null;
    };
    const key = payload[0..separator];
    const value = payload[separator + 1 ..];
    // iTerm ignores the value of this request key.
    if (std.mem.eql(u8, key, "ReportCellSize")) return .report_cell_size;
    if (std.mem.eql(u8, key, "CursorShape")) return parseCursorShape(payload);
    if (std.mem.eql(u8, key, "SetColors")) return .{ .set_colors = value };
    if (std.mem.eql(u8, key, "ShellIntegrationVersion"))
        return .{ .shell_integration = parseShellIntegration(value) orelse return null };
    return null;
}

fn parseCursorShape(payload: []const u8) ?Command {
    const prefix = "CursorShape=";
    if (!std.mem.startsWith(u8, payload, prefix)) return null;
    const value = payload[prefix.len..];
    if (value.len != 1) return null;
    return .{ .cursor_shape = switch (value[0]) {
        '0' => .block,
        '1' => .bar,
        '2' => .underline,
        else => return null,
    } };
}

fn parseShellIntegration(payload: []const u8) ?ShellIntegration {
    var parts = std.mem.splitScalar(u8, payload, ';');
    const version_text = parts.next() orelse return null;
    if (version_text.len == 0) return null;
    const version = std.fmt.parseUnsigned(u32, version_text, 10) catch return null;
    var shell: ?[]const u8 = null;
    while (parts.next()) |part| {
        const separator = std.mem.indexOfScalar(u8, part, '=') orelse return null;
        const key = part[0..separator];
        const value = part[separator + 1 ..];
        if (!std.mem.eql(u8, key, "shell") or shell != null or
            value.len == 0 or value.len > shell_name_max_bytes)
            return null;
        for (value) |byte| if (!isShellNameByte(byte)) return null;
        shell = value;
    }
    return .{ .version = version, .shell = shell };
}

fn isShellNameByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or
        byte == '.' or byte == '_' or byte == '+' or byte == '-';
}

/// Parses one OSC 133 mark and optional command-exit status.
pub fn parseShellMark(payload: []const u8) ?ShellMark {
    if (payload.len == 0) return null;
    const separator = std.mem.indexOfScalar(u8, payload, ';') orelse payload.len;
    const kind = payload[0];
    const metadata = if (separator < payload.len) payload[separator + 1 ..] else "";
    const status = if (kind == 'D' and metadata.len > 0)
        std.fmt.parseInt(i32, metadata, 10) catch null
    else
        null;
    return .{ .kind = kind, .status = status, .metadata = metadata };
}

test "iTerm safe controls decode without accepting policy commands" {
    try std.testing.expect(parse(1337, "ReportCellSize").? == .report_cell_size);
    try std.testing.expect(parse(1337, "ReportCellSize=ignored").? == .report_cell_size);
    try std.testing.expectEqual(cursor.CursorShape.bar, parse(50, "CursorShape=1").?.cursor_shape);
    try std.testing.expectEqual(cursor.CursorShape.bar, parse(1337, "CursorShape=1").?.cursor_shape);
    try std.testing.expectEqualStrings("fg=fff", parse(1337, "SetColors=fg=fff").?.set_colors);
    const integration = parse(1337, "ShellIntegrationVersion=20;shell=bash").?.shell_integration;
    try std.testing.expectEqual(@as(u32, 20), integration.version);
    try std.testing.expectEqualStrings("bash", integration.shell.?);
    try std.testing.expect(parse(1337, "ShellIntegrationVersion=20;shell=bash;shell=zsh") == null);
    try std.testing.expect(parse(1337, "ShellIntegrationVersion=20;unknown=value") == null);
    try std.testing.expect(parse(1337, "ShellIntegrationVersion=broken;shell=bash") == null);
    try std.testing.expect(parse(50, "CursorShape=9") == null);
    try std.testing.expect(parse(50, "SetColors=fg=fff") == null);
    try std.testing.expect(parse(50, "ShellIntegrationVersion=20;shell=bash") == null);
    try std.testing.expect(parse(50, "ReportCellSize") == null);
    try std.testing.expect(parse(49, "CursorShape=1") == null);
    try std.testing.expect(parse(1337, "CurrentDir=/tmp") == null);
}
