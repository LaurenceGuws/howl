//! Decodes completed OSC controls and bounded clipboard payloads.

const std = @import("std");
const events = @import("semantic_event.zig");
const parser_mod = @import("parser.zig");
const iterm = @import("iterm.zig");

const SemanticEvent = events.SemanticEvent;

/// Reports malformed OSC 52 syntax, unsupported query input, invalid base64, or allocation failure.
pub const ClipboardSetError = error{
    InvalidCharacter,
    InvalidOsc52Payload,
    InvalidPadding,
    OutOfMemory,
    UnsupportedOsc52Query,
};

const ClipboardSizeError = error{
    InvalidOsc52Payload,
    InvalidPadding,
    UnsupportedOsc52Query,
};

const ClipboardIntoError = error{
    InvalidCharacter,
    InvalidOsc52Payload,
    InvalidPadding,
    ShortBuffer,
    UnsupportedOsc52Query,
};

/// Decodes one complete borrowed OSC action into a canonical semantic event.
pub fn process(osc: parser_mod.OscAction) ?SemanticEvent {
    return switch (osc) {
        // A commandless OSC is the parser's legacy title form, not OSC 0.
        .raw_title => |v| SemanticEvent{ .title_set = v.payload },
        .title => |v| switch (v.command) {
            0 => SemanticEvent{ .title_and_icon_set = v.payload },
            2 => SemanticEvent{ .title_set = v.payload },
            else => null,
        },
        .icon => |v| SemanticEvent{ .icon_set = v.payload },
        .palette_control => |v| SemanticEvent{ .color_control = .{ .command = v.command, .payload = v.payload } },
        .palette_reset => |v| SemanticEvent{ .color_control = .{ .command = v.command, .payload = v.payload } },
        .dynamic_color => |v| SemanticEvent{ .color_control = .{ .command = v.command, .payload = v.payload } },
        .dynamic_reset => |v| SemanticEvent{ .color_control = .{ .command = v.command, .payload = v.payload } },
        .kitty_color => |v| SemanticEvent{ .color_control = .{ .command = v.command, .payload = v.payload } },
        .shell_mark => |v| if (iterm.parseShellMark(v.payload)) |mark| SemanticEvent{ .shell_mark = mark } else null,
        .iterm2 => |v| if (iterm.parse(v.command, v.payload)) |command| switch (command) {
            .cursor_shape => |shape| SemanticEvent{ .cursor_shape = shape },
            .report_cell_size => SemanticEvent.iterm_report_cell_size,
            .set_colors => |payload| SemanticEvent{ .iterm_set_colors = payload },
            .shell_integration => |integration| SemanticEvent{
                .shell_integration_set = integration,
            },
        } else null,
        .kitty_color_stack_push => SemanticEvent{ .kitty_color_stack = .push },
        .kitty_color_stack_pop => SemanticEvent{ .kitty_color_stack = .pop },
        .hyperlink => |v| blk: {
            const separator = std.mem.indexOfScalar(u8, v.payload, ';') orelse break :blk null;
            const uri = v.payload[separator + 1 ..];
            if (uri.len == 0) break :blk SemanticEvent.hyperlink_clear;
            break :blk SemanticEvent{ .hyperlink_set = uri };
        },
        .clipboard => |v| SemanticEvent{ .clipboard_set = v.payload },
        else => null,
    };
}

/// Allocates and decodes one base64 OSC 52 payload into caller-owned memory.
pub fn decodeClipboardSet(allocator: std.mem.Allocator, raw: []const u8) ClipboardSetError![]u8 {
    const decoded_len = try decodedClipboardSetSize(raw);
    const out = try allocator.alloc(u8, @intCast(decoded_len));
    errdefer allocator.free(out);
    std.debug.assert(out.len == decoded_len);
    const written = decodeClipboardSetInto(raw, out) catch |err| switch (err) {
        error.ShortBuffer => unreachable,
        error.InvalidCharacter => return error.InvalidCharacter,
        error.InvalidOsc52Payload => return error.InvalidOsc52Payload,
        error.InvalidPadding => return error.InvalidPadding,
        error.UnsupportedOsc52Query => return error.UnsupportedOsc52Query,
    };
    std.debug.assert(written == decoded_len);
    return out;
}

fn decodedClipboardSetSize(raw: []const u8) ClipboardSizeError!u64 {
    const data = clipboardData(raw) orelse return error.InvalidOsc52Payload;
    if (std.mem.eql(u8, data, "?")) return error.UnsupportedOsc52Query;
    return @intCast(try decodedBase64Size(data));
}

fn decodeClipboardSetInto(raw: []const u8, out: []u8) ClipboardIntoError!u64 {
    const data = clipboardData(raw) orelse return error.InvalidOsc52Payload;
    if (std.mem.eql(u8, data, "?")) return error.UnsupportedOsc52Query;
    const decoded_len = try decodedBase64Size(data);
    if (out.len < decoded_len) return error.ShortBuffer;
    std.debug.assert(out.len >= decoded_len);
    std.base64.standard.Decoder.decode(out[0..decoded_len], data) catch |err| switch (err) {
        error.InvalidCharacter => return error.InvalidCharacter,
        error.InvalidPadding => return error.InvalidPadding,
        error.NoSpaceLeft => unreachable,
    };
    return @intCast(decoded_len);
}

fn decodedBase64Size(data: []const u8) error{InvalidPadding}!usize {
    // Size calculation cannot inspect alphabet bytes or consume destination space.
    return std.base64.standard.Decoder.calcSizeForSlice(data) catch |err| switch (err) {
        error.InvalidPadding => return error.InvalidPadding,
        error.InvalidCharacter, error.NoSpaceLeft => unreachable,
    };
}

fn clipboardData(raw: []const u8) ?[]const u8 {
    const sep = std.mem.indexOfScalar(u8, raw, ';') orelse return null;
    return raw[sep + 1 ..];
}

test "OSC 52 clipboard set payload decodes" {
    const decoded = try decodeClipboardSet(std.testing.allocator, "c;SG93bA==");
    defer std.testing.allocator.free(decoded);
    try std.testing.expectEqualStrings("Howl", decoded);
}

test "OSC 52 clipboard query is unsupported for set drain" {
    try std.testing.expectError(error.UnsupportedOsc52Query, decodeClipboardSet(std.testing.allocator, "c;?"));
}

test "OSC 52 clipboard decode reports exact syntax base64 and allocation failures" {
    const decode: *const fn (std.mem.Allocator, []const u8) ClipboardSetError![]u8 = decodeClipboardSet;
    try std.testing.expectError(error.InvalidOsc52Payload, decode(std.testing.allocator, "SG93bA=="));
    try std.testing.expectError(error.InvalidPadding, decode(std.testing.allocator, "c;A"));
    try std.testing.expectError(error.InvalidCharacter, decode(std.testing.allocator, "c;!!!!"));

    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, decode(failing.allocator(), "c;SG93bA=="));
    try std.testing.expect(failing.has_induced_failure);

    var short: [3]u8 = undefined;
    try std.testing.expectError(error.ShortBuffer, decodeClipboardSetInto("c;SG93bA==", &short));
}

test "OSC title commands retain exact title and icon semantics" {
    try std.testing.expectEqualStrings(
        "Both",
        process(.{ .title = .{
            .command = 0,
            .payload = "Both",
            .term = .bel,
        } }).?.title_and_icon_set,
    );
    try std.testing.expectEqualStrings(
        "Title",
        process(.{ .title = .{
            .command = 2,
            .payload = "Title",
            .term = .bel,
        } }).?.title_set,
    );
    try std.testing.expectEqualStrings(
        "Raw Title",
        process(.{ .raw_title = .{
            .payload = "Raw Title",
            .term = .bel,
        } }).?.title_set,
    );
    try std.testing.expectEqualStrings(
        "Icon",
        process(.{ .icon = .{
            .payload = "Icon",
            .term = .bel,
        } }).?.icon_set,
    );
}

test "OSC hyperlink actions map to semantic events" {
    try std.testing.expectEqualStrings("https://example.com", process(.{ .hyperlink = .{ .payload = ";https://example.com", .term = .bel } }).?.hyperlink_set);
    try std.testing.expect(process(.{ .hyperlink = .{ .payload = ";", .term = .bel } }).? == .hyperlink_clear);
}

test "OSC clipboard and color controls preserve payloads" {
    try std.testing.expectEqualStrings("c;Zm9v", process(.{ .clipboard = .{ .command = 52, .payload = "c;Zm9v", .term = .bel } }).?.clipboard_set);

    const kitty_color = process(.{ .kitty_color = .{ .command = 21, .payload = "foreground=?", .term = .st } }).?;
    try std.testing.expectEqual(@as(u16, 21), kitty_color.color_control.command);
    try std.testing.expectEqualStrings("foreground=?", kitty_color.color_control.payload);

    const xterm_palette = process(.{ .palette_control = .{ .command = 4, .payload = "1;#ff0000", .term = .st } }).?;
    try std.testing.expectEqual(@as(u16, 4), xterm_palette.color_control.command);
    try std.testing.expectEqualStrings("1;#ff0000", xterm_palette.color_control.payload);
}

test "OSC shell mark maps to neutral semantic metadata" {
    const shell_mark = process(.{ .shell_mark = .{ .payload = "D;7", .term = .bel } }).?;
    try std.testing.expectEqual(@as(u8, 'D'), shell_mark.shell_mark.kind);
    try std.testing.expectEqual(@as(?i32, 7), shell_mark.shell_mark.status);
}

test "OSC Kitty policy payloads remain parser facts without semantic effects" {
    try std.testing.expect(process(.{ .notification = .{
        .command = 99,
        .payload = "i=1:p=body;Hello",
        .term = .st,
    } }) == null);
    try std.testing.expect(process(.{ .pointer_shape = .{
        .payload = ">wait,pointer",
        .term = .st,
    } }) == null);
    const push = process(.{ .kitty_color_stack_push = .st }).?;
    const pop = process(.{ .kitty_color_stack_pop = .st }).?;
    try std.testing.expect(push.kitty_color_stack == .push);
    try std.testing.expect(pop.kitty_color_stack == .pop);
    try std.testing.expect(process(.{ .kitty_clipboard = .{
        .payload = "type=write",
        .term = .st,
    } }) == null);
    try std.testing.expect(process(.{ .kitty_file_transfer = .{
        .payload = "cmd=data",
        .term = .st,
    } }) == null);
    try std.testing.expect(process(.{ .kitty_text_size = .{
        .payload = "s=2;Big",
        .term = .st,
    } }) == null);
}
