//! Deterministic proofs for caller-neutral chrome geometry and ownership.

const std = @import("std");
const chrome = @import("howl_render").chrome;

fn input() chrome.Input {
    return .{
        .surface = .{ .width = 80, .height = 40 },
        .tab_bar_height = 2,
        .tabs = &.{ .{ .id = @fromBackingInt(@intCast(1)), .label = "one", .active = true }, .{ .id = @fromBackingInt(@intCast(2)), .label = "two", .active = false } },
        .panes = &.{ .{
            .id = @fromBackingInt(@intCast(1)),
            .rect = .{ .x = 0, .y = 2, .width = 40, .height = 38 },
            .label = "left",
            .focused = true,
            .scroll = .{ .visible = 10, .total = 100, .start = 0 },
            .layer = .tiled,
        }, .{
            .id = @fromBackingInt(@intCast(2)),
            .rect = .{ .x = 40, .y = 2, .width = 40, .height = 38 },
            .label = "right",
            .focused = false,
            .scroll = null,
            .layer = .tiled,
        } },
        .selections = &.{},
        .style = .{ .foreground = .{ .r = 1, .g = 0, .b = 0, .a = 255 }, .background = .{ .r = 2, .g = 0, .b = 0, .a = 255 }, .border = .{ .r = 3, .g = 0, .b = 0, .a = 255 } },
        .tab_active_background = .{ .r = 4, .g = 0, .b = 0, .a = 255 },
        .tab_inactive_background = .{ .r = 5, .g = 0, .b = 0, .a = 255 },
        .scrollbar_width = 1,
        .scrollbar_min_thumb = 2,
    };
}

test "chrome output order and shared edge ownership are deterministic" {
    var output: [16]chrome.Primitive = undefined;
    var text: [64]u8 = undefined;
    const result = try chrome.project(input(), &output, &text);
    try std.testing.expectEqual(@as(usize, 10), result.primitives.len);
    try std.testing.expect(result.primitives[0] == .fill);
    try std.testing.expect(result.primitives[1] == .fill);
    try std.testing.expect(result.primitives[2] == .label);
    try std.testing.expect(result.primitives[5].border.edges.right == false);
}

test "chrome rejects insufficient output without mutation" {
    var output: [2]chrome.Primitive = undefined;
    output[0] = .{ .fill = .{ .rect = .{ .x = 1, .y = 1, .width = 1, .height = 1 }, .color = .{ .r = 7, .g = 0, .b = 0, .a = 255 } } };
    output[1] = output[0];
    const before = output;
    var text: [64]u8 = undefined;
    @memset(&text, 0x5a);
    const text_before = text;
    try std.testing.expectError(error.InsufficientOutput, chrome.project(input(), &output, &text));
    try std.testing.expectEqualDeep(before, output);
    try std.testing.expectEqualSlices(u8, &text_before, &text);
}

test "chrome rejects invalid geometry and aliased storage" {
    var output: [16]chrome.Primitive = undefined;
    output[0] = .{ .fill = .{ .rect = .{ .x = 1, .y = 1, .width = 1, .height = 1 }, .color = .{ .r = 1, .g = 2, .b = 3, .a = 4 } } };
    for (output[1..]) |*primitive| primitive.* = output[0];
    const output_before = output;
    var invalid = input();
    invalid.surface = .{ .width = 0, .height = 40 };
    var text: [64]u8 = undefined;
    @memset(&text, 0x5a);
    const text_before = text;
    try std.testing.expectError(error.InvalidSurface, chrome.project(invalid, &output, &text));
    try std.testing.expectEqualDeep(output_before, output);
    try std.testing.expectEqualSlices(u8, &text_before, &text);
    var invalid_panes = [_]chrome.Pane{.{ .id = @fromBackingInt(@intCast(1)), .rect = .{ .x = 0, .y = 0, .width = 0, .height = 1 }, .label = "", .focused = false, .scroll = null, .layer = .tiled }};
    invalid = input();
    invalid.panes = &invalid_panes;
    try std.testing.expectError(error.InvalidRectangle, chrome.project(invalid, &output, &text));
    try std.testing.expectEqualDeep(output_before, output);
    try std.testing.expectEqualSlices(u8, &text_before, &text);
    var panes: [1]chrome.Pane = .{.{
        .id = @fromBackingInt(@intCast(1)),
        .rect = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .label = "",
        .focused = false,
        .scroll = null,
        .layer = .tiled,
    }};
    const alias: []chrome.Primitive = @as([*]chrome.Primitive, @ptrCast(@alignCast(panes[0..].ptr)))[0..1];
    invalid = input();
    invalid.panes = &panes;
    try std.testing.expectError(error.AliasedStorage, chrome.project(invalid, alias, &text));
    var clean_output: [16]chrome.Primitive = undefined;
    const text_alias: []u8 = @as([*]u8, @ptrCast(@alignCast(panes[0..].ptr)))[0..@sizeOf(chrome.Pane)];
    try std.testing.expectError(error.AliasedStorage, chrome.project(invalid, &clean_output, text_alias));
}

test "chrome rejects every input and output alias relationship without mutation" {
    var tabs = [_]chrome.Tab{.{ .id = @fromBackingInt(@intCast(1)), .label = "tab", .active = true }};
    var panes = [_]chrome.Pane{.{ .id = @fromBackingInt(@intCast(1)), .rect = .{ .x = 0, .y = 0, .width = 8, .height = 8 }, .label = "pane", .focused = false, .scroll = null, .layer = .tiled }};
    var value = input();
    value.tabs = &tabs;
    value.panes = &panes;
    var clean_output: [16]chrome.Primitive = undefined;
    var clean_text: [32]u8 = undefined;

    const tabs_before = tabs;
    const primitive_tabs: []chrome.Primitive = @as([*]chrome.Primitive, @ptrCast(@alignCast(tabs[0..].ptr)))[0..1];
    try std.testing.expectError(error.AliasedStorage, chrome.project(value, primitive_tabs, &clean_text));
    try std.testing.expectEqualDeep(tabs_before, tabs);

    const panes_before = panes;
    const primitive_panes: []chrome.Primitive = @as([*]chrome.Primitive, @ptrCast(@alignCast(panes[0..].ptr)))[0..1];
    try std.testing.expectError(error.AliasedStorage, chrome.project(value, primitive_panes, &clean_text));
    try std.testing.expectEqualDeep(panes_before, panes);

    clean_output[0] = .{ .fill = .{ .rect = .{ .x = 0, .y = 0, .width = 1, .height = 1 }, .color = .{ .r = 1, .g = 2, .b = 3, .a = 4 } } };
    for (clean_output[1..]) |*primitive| primitive.* = clean_output[0];
    const output_before = clean_output;
    const primitive_text = std.mem.asBytes(&clean_output);
    try std.testing.expectError(error.AliasedStorage, chrome.project(value, &clean_output, primitive_text));
    try std.testing.expectEqualDeep(output_before, clean_output);

    const text_tabs: []u8 = @as([*]u8, @ptrCast(@alignCast(tabs[0..].ptr)))[0..@sizeOf(chrome.Tab)];
    try std.testing.expectError(error.AliasedStorage, chrome.project(value, &clean_output, text_tabs));
    try std.testing.expectEqualDeep(tabs_before, tabs);
    const text_panes: []u8 = @as([*]u8, @ptrCast(@alignCast(panes[0..].ptr)))[0..@sizeOf(chrome.Pane)];
    try std.testing.expectError(error.AliasedStorage, chrome.project(value, &clean_output, text_panes));
    try std.testing.expectEqualDeep(panes_before, panes);

    var label_backing: [@sizeOf(chrome.Primitive)]u8 align(@alignOf(chrome.Primitive)) = @splat('x');
    const label_before = label_backing;
    tabs[0].label = &label_backing;
    const primitive_label: []chrome.Primitive = @as([*]chrome.Primitive, @ptrCast(&label_backing))[0..1];
    try std.testing.expectError(error.AliasedStorage, chrome.project(value, primitive_label, &clean_text));
    try std.testing.expectEqualSlices(u8, &label_before, &label_backing);
    try std.testing.expectError(error.AliasedStorage, chrome.project(value, &clean_output, &label_backing));
    try std.testing.expectEqualSlices(u8, &label_before, &label_backing);
    tabs[0].label = "tab";
    panes[0].label = &label_backing;
    try std.testing.expectError(error.AliasedStorage, chrome.project(value, primitive_label, &clean_text));
    try std.testing.expectEqualSlices(u8, &label_before, &label_backing);
    try std.testing.expectError(error.AliasedStorage, chrome.project(value, &clean_output, &label_backing));
    try std.testing.expectEqualSlices(u8, &label_before, &label_backing);
}

test "scrollbar handles no-scroll and minimum thumb bounds" {
    var output: [16]chrome.Primitive = undefined;
    var value = input();
    var panes = [_]chrome.Pane{ .{
        .id = @fromBackingInt(@intCast(1)),
        .rect = .{ .x = 0, .y = 2, .width = 40, .height = 38 },
        .label = "left",
        .focused = true,
        .scroll = .{ .visible = 100, .total = 100, .start = 0 },
        .layer = .tiled,
    }, .{
        .id = @fromBackingInt(@intCast(2)),
        .rect = .{ .x = 40, .y = 2, .width = 40, .height = 38 },
        .label = "right",
        .focused = false,
        .scroll = null,
        .layer = .tiled,
    } };
    value.panes = &panes;
    var text: [64]u8 = undefined;
    const no_scroll = try chrome.project(value, &output, &text);
    try std.testing.expectEqual(@as(usize, 9), no_scroll.primitives.len);
    panes[0].scroll = .{ .visible = 1, .total = 10_000, .start = 5_000 };
    const minimum = try chrome.project(value, &output, &text);
    var found_scrollbar = false;
    for (minimum.primitives) |primitive| if (primitive == .scrollbar) {
        found_scrollbar = true;
        try std.testing.expectEqual(@as(u16, 2), primitive.scrollbar.thumb.height);
    };
    try std.testing.expect(found_scrollbar);
}

test "chrome copies complete UTF-8 labels into caller text storage" {
    var tabs = [_]chrome.Tab{ .{ .id = @fromBackingInt(@intCast(1)), .label = "α", .active = true }, .{ .id = @fromBackingInt(@intCast(2)), .label = "β", .active = false } };
    var value = input();
    value.tabs = &tabs;
    var panes = [_]chrome.Pane{ .{ .id = @fromBackingInt(@intCast(1)), .rect = .{ .x = 0, .y = 2, .width = 40, .height = 38 }, .label = "left", .focused = true, .scroll = null, .layer = .tiled }, .{ .id = @fromBackingInt(@intCast(2)), .rect = .{ .x = 40, .y = 2, .width = 40, .height = 38 }, .label = "right", .focused = false, .scroll = null, .layer = .tiled } };
    value.panes = &panes;
    var output: [12]chrome.Primitive = undefined;
    var text: [64]u8 = undefined;
    const result = try chrome.project(value, &output, &text);
    try std.testing.expectEqualStrings("αβleftright", result.text);
    const expected = [_][]const u8{ "α", "β", "left", "right" };
    var labels: usize = 0;
    var offset: usize = 0;
    for (result.primitives) |primitive| if (primitive == .label) {
        try std.testing.expectEqualStrings(expected[labels], primitive.label.text);
        try std.testing.expectEqual(expected[labels].len, primitive.label.text.len);
        try std.testing.expectEqual(@intFromPtr(text[0..].ptr) + offset, @intFromPtr(primitive.label.text.ptr));
        offset += expected[labels].len;
        labels += 1;
    };
    try std.testing.expectEqual(@as(usize, 4), labels);
}

test "chrome text capacity and invalid scroll failures preserve output" {
    var output: [16]chrome.Primitive = undefined;
    output[0] = .{ .fill = .{ .rect = .{ .x = 3, .y = 3, .width = 1, .height = 1 }, .color = .{ .r = 9, .g = 0, .b = 0, .a = 255 } } };
    for (output[1..]) |*primitive| primitive.* = output[0];
    const before = output;
    var tiny_text: [1]u8 = undefined;
    tiny_text[0] = 0x5a;
    const tiny_before = tiny_text;
    try std.testing.expectError(error.InsufficientText, chrome.project(input(), &output, &tiny_text));
    try std.testing.expectEqualDeep(before, output);
    try std.testing.expectEqualSlices(u8, &tiny_before, &tiny_text);

    var panes = [_]chrome.Pane{.{
        .id = @fromBackingInt(@intCast(1)),
        .rect = .{ .x = 0, .y = 2, .width = 40, .height = 38 },
        .label = "pane",
        .focused = false,
        .scroll = .{ .visible = 0, .total = 10, .start = 0 },
        .layer = .tiled,
    }};
    var value = input();
    value.panes = &panes;
    var text: [32]u8 = undefined;
    try std.testing.expectError(error.InvalidScroll, chrome.project(value, &output, &text));
    try std.testing.expectEqualDeep(before, output);
    panes[0].scroll = .{ .visible = 2, .total = 10, .start = 9 };
    try std.testing.expectError(error.InvalidScroll, chrome.project(value, &output, &text));
    try std.testing.expectEqualDeep(before, output);
}

test "hidden and empty tab bars emit no zero-sized primitives" {
    var output: [4]chrome.Primitive = undefined;
    var text: [8]u8 = undefined;
    var value = input();
    value.tab_bar_height = 0;
    value.tabs = &.{};
    value.panes = &.{};
    const hidden = try chrome.project(value, &output, &text);
    try std.testing.expectEqual(@as(usize, 0), hidden.primitives.len);
    value.tab_bar_height = 2;
    const empty = try chrome.project(value, &output, &text);
    try std.testing.expectEqual(@as(usize, 1), empty.primitives.len);
}

test "odd-width tabs preserve exact rectangles colors and clamped height" {
    var tabs = [_]chrome.Tab{ .{ .id = @fromBackingInt(@intCast(1)), .label = "a", .active = false }, .{ .id = @fromBackingInt(@intCast(2)), .label = "b", .active = true }, .{ .id = @fromBackingInt(@intCast(3)), .label = "c", .active = false } };
    var value = input();
    value.surface = .{ .width = 7, .height = 3 };
    value.tab_bar_height = 9;
    value.tabs = &tabs;
    value.panes = &.{};
    var output: [8]chrome.Primitive = undefined;
    var text: [3]u8 = undefined;
    const result = try chrome.project(value, &output, &text);
    try std.testing.expectEqualDeep(chrome.Rect{ .x = 0, .y = 0, .width = 7, .height = 3 }, result.primitives[0].fill.rect);
    try std.testing.expectEqualDeep(chrome.Rect{ .x = 0, .y = 0, .width = 2, .height = 3 }, result.primitives[1].fill.rect);
    try std.testing.expectEqualDeep(chrome.Rect{ .x = 2, .y = 0, .width = 2, .height = 3 }, result.primitives[3].fill.rect);
    try std.testing.expectEqualDeep(chrome.Rect{ .x = 4, .y = 0, .width = 3, .height = 3 }, result.primitives[5].fill.rect);
    try std.testing.expectEqual(value.tab_inactive_background, result.primitives[1].fill.color);
    try std.testing.expectEqual(value.tab_active_background, result.primitives[3].fill.color);
    try std.testing.expectEqual(value.tab_inactive_background, result.primitives[5].fill.color);
}

test "partially clipped panes stay within every surface edge" {
    var panes = [_]chrome.Pane{ .{
        .id = @fromBackingInt(@intCast(1)),
        .rect = .{ .x = -3, .y = -2, .width = 10, .height = 10 },
        .label = "edge",
        .focused = true,
        .scroll = null,
        .layer = .tiled,
    }, .{
        .id = @fromBackingInt(@intCast(2)),
        .rect = .{ .x = 75, .y = 35, .width = 10, .height = 10 },
        .label = "far",
        .focused = false,
        .scroll = null,
        .layer = .tiled,
    } };
    var value = input();
    value.tabs = &.{};
    value.panes = &panes;
    var output: [8]chrome.Primitive = undefined;
    var text: [16]u8 = undefined;
    const result = try chrome.project(value, &output, &text);
    const rect = result.primitives[1].border.rect;
    try std.testing.expectEqual(@as(i32, 0), rect.x);
    try std.testing.expectEqual(@as(i32, 0), rect.y);
    try std.testing.expect(rect.width <= value.surface.width and rect.height <= value.surface.height);
    const far = result.primitives[3].border.rect;
    try std.testing.expectEqual(@as(u16, 5), far.width);
    try std.testing.expectEqual(@as(u16, 5), far.height);
}

test "invalid UTF-8 and excessive visible tabs preserve both outputs" {
    var bad = input();
    var tabs = [_]chrome.Tab{.{ .id = @fromBackingInt(@intCast(1)), .label = &.{ 0xc3, 0x28 }, .active = true }};
    bad.tabs = &tabs;
    var output: [16]chrome.Primitive = undefined;
    output[0] = .{ .fill = .{ .rect = .{ .x = 1, .y = 1, .width = 1, .height = 1 }, .color = .{ .r = 8, .g = 0, .b = 0, .a = 255 } } };
    for (output[1..]) |*primitive| primitive.* = output[0];
    const before = output;
    var text: [64]u8 = undefined;
    @memset(&text, 0xa5);
    const text_before = text;
    try std.testing.expectError(error.InvalidText, chrome.project(bad, &output, &text));
    try std.testing.expectEqualDeep(before, output);
    try std.testing.expectEqualSlices(u8, &text_before, &text);
    var many: [81]chrome.Tab = undefined;
    for (&many, 0..) |*tab, index| tab.* = .{ .id = @fromBackingInt(@intCast(index + 1)), .label = "x", .active = index == 0 };
    bad = input();
    bad.surface.width = 80;
    bad.tabs = &many;
    try std.testing.expectError(error.InvalidTabBar, chrome.project(bad, &output, &text));
    try std.testing.expectEqualDeep(before, output);
}

test "scrollbar validates every tuple and preserves output" {
    var panes = [_]chrome.Pane{.{ .id = @fromBackingInt(@intCast(1)), .rect = .{ .x = 0, .y = 0, .width = 20, .height = 20 }, .label = "", .focused = false, .scroll = .{ .visible = 1, .total = 1, .start = 1 }, .layer = .tiled }};
    var value = input();
    value.tabs = &.{};
    value.panes = &panes;
    var output: [8]chrome.Primitive = undefined;
    output[0] = .{ .fill = .{ .rect = .{ .x = 0, .y = 0, .width = 1, .height = 1 }, .color = .{ .r = 1, .g = 1, .b = 1, .a = 1 } } };
    for (output[1..]) |*primitive| primitive.* = output[0];
    const before = output;
    var text: [8]u8 = undefined;
    @memset(&text, 0x5a);
    const initial_text = text;
    try std.testing.expectError(error.InvalidScroll, chrome.project(value, &output, &text));
    try std.testing.expectEqualDeep(before, output);
    try std.testing.expectEqualSlices(u8, &initial_text, &text);
    panes[0].scroll = .{ .visible = 3, .total = 2, .start = 0 };
    try std.testing.expectError(error.InvalidScroll, chrome.project(value, &output, &text));
    try std.testing.expectEqualSlices(u8, &initial_text, &text);
    panes[0].scroll = .{ .visible = 0, .total = 2, .start = 0 };
    try std.testing.expectError(error.InvalidScroll, chrome.project(value, &output, &text));
    try std.testing.expectEqualSlices(u8, &initial_text, &text);
    panes[0].scroll = .{ .visible = 10, .total = 100, .start = 0 };
    const start = try chrome.project(value, &output, &text);
    var start_y: i32 = 0;
    for (start.primitives) |primitive| {
        if (primitive == .scrollbar) start_y = primitive.scrollbar.thumb.y;
    }
    panes[0].scroll = .{ .visible = 10, .total = 100, .start = 50 };
    const middle = try chrome.project(value, &output, &text);
    var middle_y: i32 = 0;
    for (middle.primitives) |primitive| {
        if (primitive == .scrollbar) middle_y = primitive.scrollbar.thumb.y;
    }
    panes[0].scroll = .{ .visible = 10, .total = 100, .start = 90 };
    const end = try chrome.project(value, &output, &text);
    var end_y: i32 = 0;
    for (end.primitives) |primitive| {
        if (primitive == .scrollbar) end_y = primitive.scrollbar.thumb.y;
    }
    try std.testing.expectEqual(@as(i32, 0), start_y);
    try std.testing.expectEqual(@as(i32, 10), middle_y);
    try std.testing.expectEqual(@as(i32, 18), end_y);
    const output_before = output;
    const text_before = text;
    value.scrollbar_width = 0;
    try std.testing.expectError(error.InvalidScrollbar, chrome.project(value, &output, &text));
    try std.testing.expectEqualDeep(output_before, output);
    try std.testing.expectEqualSlices(u8, &text_before, &text);
}

test "horizontal and vertical pane junctions own shared edges once" {
    var panes = [_]chrome.Pane{ .{
        .id = @fromBackingInt(@intCast(1)),
        .rect = .{ .x = 0, .y = 0, .width = 20, .height = 10 },
        .label = "",
        .focused = false,
        .scroll = null,
        .layer = .tiled,
    }, .{
        .id = @fromBackingInt(@intCast(2)),
        .rect = .{ .x = 20, .y = 0, .width = 20, .height = 10 },
        .label = "",
        .focused = false,
        .scroll = null,
        .layer = .tiled,
    }, .{
        .id = @fromBackingInt(@intCast(3)),
        .rect = .{ .x = 0, .y = 10, .width = 20, .height = 10 },
        .label = "",
        .focused = false,
        .scroll = null,
        .layer = .tiled,
    } };
    var value = input();
    value.surface = .{ .width = 40, .height = 20 };
    value.tabs = &.{};
    value.panes = &panes;
    var output: [8]chrome.Primitive = undefined;
    var text: [1]u8 = undefined;
    const result = try chrome.project(value, &output, &text);
    try std.testing.expectEqualDeep(
        chrome.BorderEdges{ .right = false, .bottom = false },
        result.primitives[1].border.edges,
    );
    try std.testing.expectEqualDeep(chrome.BorderEdges{}, result.primitives[2].border.edges);
    try std.testing.expectEqualDeep(chrome.BorderEdges{}, result.primitives[3].border.edges);
}

test "floating panes preserve caller order clipping focus and topmost hit" {
    var panes = [_]chrome.Pane{
        .{ .id = @fromBackingInt(@intCast(1)), .rect = .{ .x = 0, .y = 2, .width = 80, .height = 38 }, .label = "tiled", .focused = false, .scroll = null, .layer = .tiled },
        .{ .id = @fromBackingInt(@intCast(2)), .rect = .{ .x = 10, .y = 8, .width = 40, .height = 24 }, .label = "lower", .focused = false, .scroll = null, .layer = .floating },
        .{ .id = @fromBackingInt(@intCast(3)), .rect = .{ .x = 30, .y = 12, .width = 60, .height = 30 }, .label = "upper", .focused = true, .scroll = null, .layer = .floating },
    };
    var value = input();
    value.tabs = &.{.{ .id = @fromBackingInt(@intCast(1)), .label = "one", .active = true }};
    value.panes = &panes;
    value.selections = &.{.{ .pane = @fromBackingInt(@intCast(3)), .rect = .{ .x = 20, .y = 10, .width = 80, .height = 40 }, .color = .{ .r = 10, .g = 20, .b = 30, .a = 255 } }};
    var primitives: [16]chrome.Primitive = undefined;
    var text: [32]u8 = undefined;
    const output = try chrome.project(value, &primitives, &text);
    try std.testing.expectEqualStrings("onetiledlowerupper", output.text);
    try std.testing.expectEqualDeep(chrome.Rect{ .x = 30, .y = 12, .width = 50, .height = 28 }, output.primitives[7].fill.rect);
    try std.testing.expectEqualDeep(chrome.Rect{ .x = 30, .y = 12, .width = 50, .height = 28 }, output.primitives[8].border.rect);
    try std.testing.expect(output.primitives[8].border.edges.top);
    const top = (try chrome.hitTest(value, .{ .x = 35, .y = 15 })).?.pane;
    try std.testing.expectEqual(@as(chrome.PaneId, @fromBackingInt(@intCast(3))), top);
    const lower = (try chrome.hitTest(value, .{ .x = 15, .y = 10 })).?.pane;
    try std.testing.expectEqual(@as(chrome.PaneId, @fromBackingInt(@intCast(2))), lower);
    const tab = (try chrome.hitTest(value, .{ .x = 1, .y = 1 })).?.tab;
    try std.testing.expectEqual(@as(chrome.TabId, @fromBackingInt(@intCast(1))), tab);
}

test "hit testing preflights covered malformed panes and tab geometry" {
    var panes = [_]chrome.Pane{
        .{ .id = @fromBackingInt(@intCast(1)), .rect = .{ .x = 0, .y = 2, .width = 0, .height = 38 }, .label = "", .focused = false, .scroll = null, .layer = .tiled },
        .{ .id = @fromBackingInt(@intCast(2)), .rect = .{ .x = 0, .y = 2, .width = 80, .height = 38 }, .label = "", .focused = true, .scroll = null, .layer = .floating },
    };
    var value = input();
    value.panes = &panes;
    try std.testing.expectError(error.InvalidRectangle, chrome.hitTest(value, .{ .x = 10, .y = 10 }));

    var tabs = [_]chrome.Tab{
        .{ .id = @fromBackingInt(@intCast(1)), .label = "a", .active = true },
        .{ .id = @fromBackingInt(@intCast(2)), .label = "b", .active = false },
    };
    value = input();
    value.surface = .{ .width = 1, .height = 40 };
    value.tabs = &tabs;
    try std.testing.expectError(error.InvalidTabBar, chrome.hitTest(value, .{ .x = 0, .y = 39 }));
}

test "caller selection clips and preserves deterministic primitive phase" {
    var value = input();
    value.tab_bar_height = 0;
    value.tabs = &.{};
    value.panes = &.{.{ .id = @fromBackingInt(@intCast(1)), .rect = .{ .x = 0, .y = 0, .width = 80, .height = 40 }, .label = "", .focused = true, .scroll = null, .layer = .tiled }};
    value.selections = &.{
        .{ .pane = @fromBackingInt(@intCast(1)), .rect = .{ .x = -4, .y = 3, .width = 10, .height = 5 }, .color = .{ .r = 1, .g = 2, .b = 3, .a = 4 } },
        .{ .pane = @fromBackingInt(@intCast(1)), .rect = .{ .x = 70, .y = 35, .width = 20, .height = 10 }, .color = .{ .r = 5, .g = 6, .b = 7, .a = 8 } },
    };
    var primitives: [3]chrome.Primitive = undefined;
    var text: [1]u8 = undefined;
    const output = try chrome.project(value, &primitives, &text);
    try std.testing.expectEqualDeep(chrome.Rect{ .x = 0, .y = 3, .width = 6, .height = 5 }, output.primitives[0].fill.rect);
    try std.testing.expectEqualDeep(chrome.Rect{ .x = 70, .y = 35, .width = 10, .height = 5 }, output.primitives[1].fill.rect);
}

test "identity order and selection alias failures preserve caller output" {
    var value = input();
    var panes = [_]chrome.Pane{
        .{ .id = @fromBackingInt(@intCast(1)), .rect = .{ .x = 0, .y = 2, .width = 80, .height = 38 }, .label = "", .focused = true, .scroll = null, .layer = .floating },
        .{ .id = @fromBackingInt(@intCast(2)), .rect = .{ .x = 0, .y = 2, .width = 80, .height = 38 }, .label = "", .focused = false, .scroll = null, .layer = .tiled },
    };
    value.panes = &panes;
    var primitives: [8]chrome.Primitive = undefined;
    primitives[0] = .{ .fill = .{ .rect = .{ .x = 1, .y = 1, .width = 1, .height = 1 }, .color = .{ .r = 9, .g = 8, .b = 7, .a = 6 } } };
    for (primitives[1..]) |*primitive| primitive.* = primitives[0];
    const before = primitives;
    var text: [8]u8 = undefined;
    @memset(&text, 0xa5);
    const text_before = text;
    try std.testing.expectError(error.InvalidOrder, chrome.project(value, &primitives, &text));
    try std.testing.expectEqualDeep(before, primitives);
    try std.testing.expectEqualSlices(u8, &text_before, &text);

    panes[0].layer = .tiled;
    panes[1].layer = .floating;
    panes[1].id = panes[0].id;
    try std.testing.expectError(error.InvalidIdentity, chrome.project(value, &primitives, &text));
    try std.testing.expectEqualDeep(before, primitives);

    var selections = [_]chrome.Selection{.{ .pane = @fromBackingInt(@intCast(1)), .rect = .{ .x = 1, .y = 1, .width = 1, .height = 1 }, .color = .{ .r = 1, .g = 1, .b = 1, .a = 1 } }};
    value.panes = &.{};
    value.selections = &selections;
    const alias: []chrome.Primitive = @as([*]chrome.Primitive, @ptrCast(@alignCast(selections[0..].ptr)))[0..1];
    try std.testing.expectError(error.AliasedStorage, chrome.project(value, alias, &text));
    try std.testing.expectEqualDeep(chrome.Selection{ .pane = @fromBackingInt(@intCast(1)), .rect = .{ .x = 1, .y = 1, .width = 1, .height = 1 }, .color = .{ .r = 1, .g = 1, .b = 1, .a = 1 } }, selections[0]);
    const selection_bytes = std.mem.asBytes(&selections);
    try std.testing.expectError(error.AliasedStorage, chrome.project(value, &primitives, selection_bytes));
    try std.testing.expectEqualDeep(chrome.Selection{ .pane = @fromBackingInt(@intCast(1)), .rect = .{ .x = 1, .y = 1, .width = 1, .height = 1 }, .color = .{ .r = 1, .g = 1, .b = 1, .a = 1 } }, selections[0]);
    value.panes = panes[0..1];
    try std.testing.expectError(error.InsufficientOutput, chrome.project(value, primitives[0..0], &text));
    try std.testing.expectEqualDeep(before, primitives);
    try std.testing.expectEqualSlices(u8, &text_before, &text);
}

test "selection owners are preflighted and failures preserve both outputs" {
    var value = input();
    var pane = [_]chrome.Pane{.{ .id = @fromBackingInt(@intCast(1)), .rect = .{ .x = 0, .y = 2, .width = 80, .height = 38 }, .label = "", .focused = true, .scroll = null, .layer = .tiled }};
    value.panes = &pane;
    var primitives: [16]chrome.Primitive = undefined;
    primitives[0] = .{ .fill = .{ .rect = .{ .x = 1, .y = 1, .width = 1, .height = 1 }, .color = .{ .r = 7, .g = 8, .b = 9, .a = 10 } } };
    for (primitives[1..]) |*primitive| primitive.* = primitives[0];
    const primitives_before = primitives;
    var text: [32]u8 = undefined;
    @memset(&text, 0x5a);
    const text_before = text;
    var selections = [_]chrome.Selection{.{ .pane = @fromBackingInt(@intCast(0)), .rect = .{ .x = 1, .y = 3, .width = 2, .height = 2 }, .color = .{ .r = 1, .g = 2, .b = 3, .a = 4 } }};
    value.selections = &selections;
    try std.testing.expectError(error.InvalidIdentity, chrome.project(value, &primitives, &text));
    try std.testing.expectEqualDeep(primitives_before, primitives);
    try std.testing.expectEqualSlices(u8, &text_before, &text);
    selections[0].pane = @fromBackingInt(@intCast(99));
    try std.testing.expectError(error.InvalidIdentity, chrome.project(value, &primitives, &text));
    try std.testing.expectEqualDeep(primitives_before, primitives);
    try std.testing.expectEqualSlices(u8, &text_before, &text);
}
