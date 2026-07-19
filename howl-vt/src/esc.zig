//! Decodes completed ESC sequences into terminal semantic events.

const std = @import("std");

const EscAction = union(enum) {
    line_feed,
    next_line,
    reverse_index,
    primary_device_attributes,
    horizontal_tab_set,
    reset_screen,
    save_cursor,
    restore_cursor,
    application_keypad: bool,
};

const events = @import("semantic_event.zig");
const SemanticEvent = events.SemanticEvent;

fn action(final: u8) ?EscAction {
    return switch (final) {
        'D' => .line_feed,
        'E' => .next_line,
        'M' => .reverse_index,
        'Z' => .primary_device_attributes,
        'H' => .horizontal_tab_set,
        'c' => .reset_screen,
        '7' => .save_cursor,
        '8' => .restore_cursor,
        '=' => EscAction{ .application_keypad = true },
        '>' => EscAction{ .application_keypad = false },
        else => null,
    };
}

/// Decodes one completed ESC event; unsupported combinations return null.
pub fn process(final: u8) ?SemanticEvent {
    switch (final) {
        0x17 => return SemanticEvent{ .legacy_control = .tek_copy },
        0x1C => return SemanticEvent{ .legacy_control = .tek_special_point_plot },
        'l' => return SemanticEvent{ .legacy_control = .hp_memory_lock },
        's' => return SemanticEvent{ .legacy_control = .tek_write_thru_short_dashed },
        else => {},
    }
    const mapped = action(final) orelse return null;
    return switch (mapped) {
        .line_feed => SemanticEvent.line_feed,
        .next_line => SemanticEvent.next_line,
        .reverse_index => SemanticEvent.reverse_index,
        .primary_device_attributes => SemanticEvent.primary_device_attributes,
        .horizontal_tab_set => SemanticEvent.horizontal_tab_set,
        .reset_screen => SemanticEvent.reset_screen,
        .save_cursor => SemanticEvent.save_cursor,
        .restore_cursor => SemanticEvent.restore_cursor,
        .application_keypad => |enabled| SemanticEvent{ .application_keypad = enabled },
    };
}

test "esc maps C1 7-bit aliases and cursor save restore" {
    try std.testing.expect(process('D').? == .line_feed);
    try std.testing.expect(process('E').? == .next_line);
    try std.testing.expect(process('M').? == .reverse_index);
    try std.testing.expect(process('7').? == .save_cursor);
    try std.testing.expect(process('8').? == .restore_cursor);
}

test "esc maps DECID RIS and application keypad" {
    try std.testing.expect(process('Z').? == .primary_device_attributes);
    try std.testing.expect(process('c').? == .reset_screen);
    try std.testing.expect(process('=').?.application_keypad);
    try std.testing.expect(!process('>').?.application_keypad);
}

test "esc maps low legacy controls and ignores unsupported finals" {
    try std.testing.expect(process(0x17).?.legacy_control == .tek_copy);
    try std.testing.expect(process(0x1C).?.legacy_control == .tek_special_point_plot);
    try std.testing.expect(process('l').?.legacy_control == .hp_memory_lock);
    try std.testing.expect(process('s').?.legacy_control == .tek_write_thru_short_dashed);
    try std.testing.expectEqual(@as(?SemanticEvent, null), process('z'));
}
