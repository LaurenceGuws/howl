//! Owns C0 byte classification and conversion into terminal control events.

const std = @import("std");

const C0Action = enum {
    bell,
    line_feed,
    carriage_return,
    backspace,
    horizontal_tab,
};

const C0 = enum(u8) {
    bell = 0x07,
    backspace = 0x08,
    horizontal_tab = 0x09,
    line_feed = 0x0A,
    vertical_tab = 0x0B,
    form_feed = 0x0C,
    carriage_return = 0x0D,
    file_separator = 0x1C,
    group_separator = 0x1D,
    record_separator = 0x1E,
    unit_separator = 0x1F,
    _,
};

const events = @import("semantic_event.zig");
const legacy_control = @import("legacy_control.zig");
const SemanticEvent = events.SemanticEvent;

/// Classifies one byte as its exact C0 code without rejecting unknown values.
pub fn fromByte(byte: u8) C0 {
    return @enumFromInt(byte);
}

fn action(control: C0) ?C0Action {
    return switch (control) {
        .bell => .bell,
        .line_feed, .vertical_tab, .form_feed => .line_feed,
        .carriage_return => .carriage_return,
        .backspace => .backspace,
        .horizontal_tab => .horizontal_tab,
        else => null,
    };
}

/// Converts a C0 code into its terminal mutation, or null when it is ignored.
pub fn process(control: C0) ?SemanticEvent {
    switch (control) {
        .file_separator => return SemanticEvent{ .legacy_control = .tek_point_plot },
        .group_separator => return SemanticEvent{ .legacy_control = .tek_graph },
        .record_separator => return SemanticEvent{ .legacy_control = .tek_incremental_plot },
        .unit_separator => return SemanticEvent{ .legacy_control = .tek_alpha },
        else => {},
    }
    const mapped = action(control) orelse return null;
    return switch (mapped) {
        .bell => SemanticEvent.bell,
        .line_feed => SemanticEvent.line_feed,
        .carriage_return => SemanticEvent.carriage_return,
        .backspace => SemanticEvent.backspace,
        .horizontal_tab => SemanticEvent.horizontal_tab,
    };
}

test "c0 handled controls keep protocol values" {
    try std.testing.expectEqual(@as(u8, 0x07), @intFromEnum(C0.bell));
    try std.testing.expectEqual(@as(u8, 0x08), @intFromEnum(C0.backspace));
    try std.testing.expectEqual(@as(u8, 0x09), @intFromEnum(C0.horizontal_tab));
    try std.testing.expectEqual(@as(u8, 0x0A), @intFromEnum(C0.line_feed));
    try std.testing.expectEqual(@as(u8, 0x0B), @intFromEnum(C0.vertical_tab));
    try std.testing.expectEqual(@as(u8, 0x0C), @intFromEnum(C0.form_feed));
    try std.testing.expectEqual(@as(u8, 0x0D), @intFromEnum(C0.carriage_return));
}

test "c0 maps line and cursor stream controls" {
    try std.testing.expect(process(.bell).? == .bell);
    try std.testing.expect(process(.line_feed).? == .line_feed);
    try std.testing.expect(process(.vertical_tab).? == .line_feed);
    try std.testing.expect(process(.form_feed).? == .line_feed);
    try std.testing.expect(process(.carriage_return).? == .carriage_return);
    try std.testing.expect(process(.backspace).? == .backspace);
    try std.testing.expect(process(.horizontal_tab).? == .horizontal_tab);
}

test "c0 legacy controls map host-neutral state" {
    try std.testing.expectEqual(legacy_control.LegacyControlKind.tek_point_plot, process(.file_separator).?.legacy_control);
    try std.testing.expectEqual(legacy_control.LegacyControlKind.tek_graph, process(.group_separator).?.legacy_control);
    try std.testing.expectEqual(legacy_control.LegacyControlKind.tek_incremental_plot, process(.record_separator).?.legacy_control);
    try std.testing.expectEqual(legacy_control.LegacyControlKind.tek_alpha, process(.unit_separator).?.legacy_control);
}

test "c0 ignores unsupported controls" {
    try std.testing.expectEqual(@as(?SemanticEvent, null), process(fromByte(0x00)));
}
