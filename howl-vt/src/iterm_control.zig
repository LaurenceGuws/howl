//! Borrowed iTerm OSC 50, 133, and 1337 command decoding.
//!
//! Terminal owns every resulting state mutation and consequence. This module
//! accepts only the command families Howl intentionally exposes.

const std = @import("std");

/// Names the three iTerm cursor shapes without importing Screen ownership.
pub const CursorShape = enum {
    block,
    bar,
    underline,
};

/// Borrows one parsed OSC 133 shell mark until parser mutation.
pub const ShellMark = struct {
    kind: u8,
    status: ?i32,
    metadata: []const u8,
};

/// Borrows a decimal integration version and optional bounded shell identity.
pub const ShellIntegration = struct {
    version: u32,
    shell: ?[]const u8,
};

/// Names iTerm controls whose effects are safe inside the native terminal contract.
pub const Command = union(enum) {
    cursor_shape: CursorShape,
    report_cell_size,
    set_colors: []const u8,
    shell_integration: ShellIntegration,
    current_directory: []const u8,
    remote_host: []const u8,
    clear_scrollback,
    notification: []const u8,
    steal_focus,
    request_attention: []const u8,
    file_transfer: []const u8,
};

const maximum_shell_name_bytes: u8 = 32;

/// Decodes one borrowed OSC 50 or 1337 payload under its exact command family.
pub fn parse(command: u16, payload: []const u8) ?Command {
    return switch (command) {
        50 => parseCursorShape(payload),
        1337 => parse1337(payload),
        else => null,
    };
}

/// Parses one OSC 133 mark and the first positional command-exit status.
pub fn parseShellMark(payload: []const u8) ?ShellMark {
    if (payload.len == 0) return null;
    const separator = std.mem.indexOfScalar(u8, payload, ';') orelse payload.len;
    if (separator != 1) return null;
    const kind = payload[0];
    switch (kind) {
        'A', 'B', 'C', 'D' => {},
        else => return null,
    }
    const metadata = if (separator < payload.len) payload[separator + 1 ..] else "";
    const status = if (kind == 'D') parseShellExitStatus(metadata) else null;
    return .{ .kind = kind, .status = status, .metadata = metadata };
}

fn parse1337(payload: []const u8) ?Command {
    const separator = std.mem.indexOfScalar(u8, payload, '=') orelse {
        return if (std.mem.eql(u8, payload, "ReportCellSize"))
            .report_cell_size
        else if (std.mem.eql(u8, payload, "StealFocus"))
            .steal_focus
        else if (std.mem.eql(u8, payload, "ClearScrollback"))
            .clear_scrollback
        else if (std.mem.eql(u8, payload, "RequestAttention"))
            .{ .request_attention = "" }
        else
            null;
    };
    const key = payload[0..separator];
    const value = payload[separator + 1 ..];
    if (std.mem.eql(u8, key, "ReportCellSize")) return .report_cell_size;
    if (std.mem.eql(u8, key, "CursorShape")) return parseCursorShape(payload);
    if (std.mem.eql(u8, key, "SetColors")) return .{ .set_colors = value };
    if (std.mem.eql(u8, key, "CurrentDir")) return .{ .current_directory = value };
    if (std.mem.eql(u8, key, "RemoteHost")) return .{ .remote_host = value };
    if (std.mem.eql(u8, key, "ClearScrollback")) return .clear_scrollback;
    if (std.mem.eql(u8, key, "Notification")) return .{ .notification = value };
    if (std.mem.eql(u8, key, "StealFocus")) return .steal_focus;
    if (std.mem.eql(u8, key, "RequestAttention")) return .{ .request_attention = value };
    if (std.mem.eql(u8, key, "File") or
        std.mem.eql(u8, key, "MultipartFile") or
        std.mem.eql(u8, key, "FilePart") or
        std.mem.eql(u8, key, "FileEnd")) return .{ .file_transfer = payload };
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
            value.len == 0 or value.len > maximum_shell_name_bytes)
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

fn parseShellExitStatus(metadata: []const u8) ?i32 {
    var fields = std.mem.splitScalar(u8, metadata, ';');
    while (fields.next()) |field| {
        if (field.len == 0 or std.mem.indexOfScalar(u8, field, '=') != null) continue;
        if (std.fmt.parseInt(i32, field, 10)) |status| return status else |_| {}
    }
    return null;
}

test "iTerm safe controls decode without accepting policy commands" {
    try std.testing.expect(parse(1337, "ReportCellSize").? == .report_cell_size);
    try std.testing.expect(parse(1337, "ReportCellSize=ignored").? == .report_cell_size);
    try std.testing.expectEqual(CursorShape.bar, parse(50, "CursorShape=1").?.cursor_shape);
    try std.testing.expectEqual(CursorShape.underline, parse(1337, "CursorShape=2").?.cursor_shape);
    try std.testing.expectEqualStrings("fg=fff", parse(1337, "SetColors=fg=fff").?.set_colors);
    try std.testing.expectEqualStrings("/work/tree", parse(1337, "CurrentDir=/work/tree").?.current_directory);
    try std.testing.expectEqualStrings("host", parse(1337, "RemoteHost=host").?.remote_host);
    try std.testing.expectEqualStrings("hello", parse(1337, "Notification=hello").?.notification);
    try std.testing.expect(parse(1337, "StealFocus").? == .steal_focus);
    try std.testing.expect(parse(1337, "StealFocus=ignored").? == .steal_focus);
    try std.testing.expect(parse(1337, "ClearScrollback=value").? == .clear_scrollback);
    try std.testing.expectEqualStrings("", parse(1337, "RequestAttention").?.request_attention);
    try std.testing.expectEqualStrings("fireworks", parse(1337, "RequestAttention=fireworks").?.request_attention);
    try std.testing.expectEqualStrings("FilePart=QQ==", parse(1337, "FilePart=QQ==").?.file_transfer);

    try std.testing.expect(parse(50, "CursorShape=9") == null);
    try std.testing.expect(parse(50, "SetColors=fg=fff") == null);
    try std.testing.expect(parse(50, "ShellIntegrationVersion=20;shell=bash") == null);
    try std.testing.expect(parse(50, "ReportCellSize") == null);
    try std.testing.expect(parse(49, "CursorShape=1") == null);
    try std.testing.expect(parse(1337, "Unknown=value") == null);
}

test "iTerm shell integration accepts one bounded identity only" {
    const integration = parse(1337, "ShellIntegrationVersion=20;shell=bash-5.3").?.shell_integration;
    try std.testing.expectEqual(@as(u32, 20), integration.version);
    try std.testing.expectEqualStrings("bash-5.3", integration.shell.?);
    try std.testing.expect(parse(1337, "ShellIntegrationVersion=20").?.shell_integration.shell == null);
    try std.testing.expect(parse(1337, "ShellIntegrationVersion=20;shell=bash;shell=zsh") == null);
    try std.testing.expect(parse(1337, "ShellIntegrationVersion=20;unknown=value") == null);
    try std.testing.expect(parse(1337, "ShellIntegrationVersion=broken;shell=bash") == null);
    try std.testing.expect(parse(1337, "ShellIntegrationVersion=20;shell=") == null);
    try std.testing.expect(parse(1337, "ShellIntegrationVersion=20;shell=bad/name") == null);

    const too_long = "ShellIntegrationVersion=20;shell=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";
    try std.testing.expect(parse(1337, too_long) == null);
}

test "iTerm shell marks preserve kind metadata and first positional status" {
    const mark = parseShellMark("D;aid=nested;9;cl=x").?;
    try std.testing.expectEqual(@as(u8, 'D'), mark.kind);
    try std.testing.expectEqualStrings("aid=nested;9;cl=x", mark.metadata);
    try std.testing.expectEqual(@as(?i32, 9), mark.status);
    try std.testing.expectEqual(@as(?i32, -3), parseShellMark("D;;-3;aid=x").?.status);
    try std.testing.expectEqual(@as(?i32, null), parseShellMark("D;aid=x;broken").?.status);
    try std.testing.expectEqual(@as(?i32, null), parseShellMark("C;7").?.status);
    try std.testing.expect(parseShellMark("") == null);
    try std.testing.expect(parseShellMark("AA;1") == null);
    try std.testing.expect(parseShellMark("X;1") == null);
}
