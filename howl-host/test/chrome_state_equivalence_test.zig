//! Test-only normalized equivalence oracle for the pre-extraction topology.

const std = @import("std");
const render = @import("howl_render");
const session = @import("session_domain");
const chrome_state = @import("chrome_state");
const chrome = render.chrome;

const Appearance = chrome_state.Appearance;
const default_tab_bar_height = chrome_state.default_tab_bar_height;
const max_tabs = chrome_state.max_tabs;
const max_panes_per_tab = chrome_state.max_panes_per_tab;
const max_live_panes = chrome_state.max_live_panes;
const max_label_bytes = chrome_state.max_label_bytes;
const scrollbar_width = chrome_state.scrollbar_width;
const scrollbar_min_thumb = chrome_state.scrollbar_min_thumb;

fn testAppearance() Appearance {
    return .{
        .style = .{
            .foreground = .{ .r = 230, .g = 235, .b = 245, .a = 255 },
            .background = .{ .r = 20, .g = 24, .b = 32, .a = 255 },
            .border = .{ .r = 80, .g = 90, .b = 110, .a = 255 },
        },
        .tab_active_background = .{ .r = 48, .g = 72, .b = 112, .a = 255 },
        .tab_inactive_background = .{ .r = 28, .g = 34, .b = 46, .a = 255 },
    };
}

const LegacyPane = struct {
    id: chrome.PaneId,
    rect: chrome.Rect,
    basis_rect: chrome.Rect,
    focused: bool,
    label: [max_label_bytes]u8 = undefined,
    label_len: u8 = 0,
    scroll: ?chrome.Scroll = null,
    layer: chrome.PaneLayer = .tiled,
};

const LegacyTab = struct {
    id: chrome.TabId,
    label: [max_label_bytes]u8 = undefined,
    label_len: u8 = 0,
    panes: [max_panes_per_tab]LegacyPane = undefined,
    pane_count: u8 = 0,
};

fn legacyScaleEdge(value: i64, old_extent: u16, new_extent: u16) !i64 {
    if (value < 0 or old_extent == 0) return error.InvalidGeometry;
    const product = std.math.mul(u64, @intCast(value), new_extent) catch return error.ArithmeticOverflow;
    return @intCast(product / old_extent);
}

const LegacyTopology = struct {
    tabs: [max_tabs]LegacyTab = undefined,
    tab_count: u8 = 0,
    active_tab: u8 = 0,
    next_tab_id: u64 = 1,
    next_pane_id: u64 = 1,
    live_panes: u16 = 0,
    surface: chrome.Size,
    basis_surface: chrome.Size,
    tab_bar_height: u16,

    fn init(surface: chrome.Size, tab_bar_height: u16) !LegacyTopology {
        if (surface.width == 0 or surface.height <= tab_bar_height) return error.InvalidSurface;
        var result = LegacyTopology{
            .surface = surface,
            .basis_surface = surface,
            .tab_bar_height = tab_bar_height,
            .tab_count = 1,
            .live_panes = 1,
            .next_tab_id = 2,
            .next_pane_id = 2,
        };
        result.tabs[0] = .{ .id = @fromBackingInt(@intCast(1)), .pane_count = 1 };
        @memcpy(result.tabs[0].label[0..4], "main");
        result.tabs[0].label_len = 4;
        result.tabs[0].panes[0] = .{
            .id = @fromBackingInt(@intCast(1)),
            .rect = .{ .x = 0, .y = tab_bar_height, .width = surface.width, .height = surface.height - tab_bar_height },
            .basis_rect = .{ .x = 0, .y = tab_bar_height, .width = surface.width, .height = surface.height - tab_bar_height },
            .focused = true,
        };
        return result;
    }

    fn splitVertical(self: *LegacyTopology, pane_index: usize) !chrome.PaneId {
        const tab = &self.tabs[self.active_tab];
        if (pane_index >= tab.pane_count or tab.pane_count == max_panes_per_tab) return error.Capacity;
        const source = tab.panes[pane_index];
        const first_width = source.rect.width / 2;
        if (first_width == 0) return error.InvalidGeometry;
        const new_id: chrome.PaneId = @fromBackingInt(@intCast(self.next_pane_id));
        self.next_pane_id += 1;
        var second = source;
        second.id = new_id;
        second.rect = .{ .x = source.rect.x + first_width, .y = source.rect.y, .width = source.rect.width - first_width, .height = source.rect.height };
        second.basis_rect = second.rect;
        second.focused = true;
        tab.panes[pane_index].rect.width = first_width;
        tab.panes[pane_index].basis_rect.width = first_width;
        tab.panes[pane_index].focused = false;
        var index = tab.pane_count;
        while (index > pane_index + 1) : (index -= 1) tab.panes[index] = tab.panes[index - 1];
        tab.panes[pane_index + 1] = second;
        tab.pane_count += 1;
        self.live_panes += 1;
        return new_id;
    }

    fn createTab(self: *LegacyTopology, label: []const u8) !chrome.TabId {
        if (self.tab_count >= max_tabs or self.live_panes >= max_live_panes or label.len > max_label_bytes) return error.Capacity;
        const id: chrome.TabId = @fromBackingInt(@intCast(self.next_tab_id));
        const pane_id: chrome.PaneId = @fromBackingInt(@intCast(self.next_pane_id));
        self.next_tab_id += 1;
        self.next_pane_id += 1;
        var tab = LegacyTab{ .id = id, .pane_count = 1 };
        @memcpy(tab.label[0..label.len], label);
        tab.label_len = @intCast(label.len);
        tab.panes[0] = .{
            .id = pane_id,
            .rect = .{ .x = 0, .y = self.tab_bar_height, .width = self.surface.width, .height = self.surface.height - self.tab_bar_height },
            .basis_rect = .{ .x = 0, .y = self.tab_bar_height, .width = self.surface.width, .height = self.surface.height - self.tab_bar_height },
            .focused = true,
        };
        self.tabs[self.tab_count] = tab;
        self.active_tab = self.tab_count;
        self.tab_count += 1;
        self.live_panes += 1;
        return id;
    }

    fn closeTab(self: *LegacyTopology, id: chrome.TabId) !void {
        var index: usize = 0;
        while (index < self.tab_count and self.tabs[index].id != id) : (index += 1) {}
        if (index == self.tab_count) return error.InvalidId;
        const removed_index = index;
        self.live_panes -= self.tabs[index].pane_count;
        while (index + 1 < self.tab_count) : (index += 1) self.tabs[index] = self.tabs[index + 1];
        self.tab_count -= 1;
        if (self.tab_count == 0) {
            const replacement = try self.createTab("main");
            if (@backingInt(replacement) == 0) return error.InvalidId;
            self.active_tab = 0;
        } else if (self.active_tab >= self.tab_count) {
            self.active_tab = self.tab_count - 1;
        } else if (removed_index < self.active_tab) {
            self.active_tab -= 1;
        }
        self.basis_surface = self.surface;
        for (self.tabs[0..self.tab_count]) |*tab| {
            for (tab.panes[0..tab.pane_count]) |*pane| pane.basis_rect = pane.rect;
        }
    }

    fn resizeSurface(self: *LegacyTopology, surface: chrome.Size) !void {
        if (surface.width == 0 or surface.height <= self.tab_bar_height) return error.InvalidSurface;
        const old_content = chrome.Size{ .width = self.basis_surface.width, .height = self.basis_surface.height - self.tab_bar_height };
        const new_content = chrome.Size{ .width = surface.width, .height = surface.height - self.tab_bar_height };
        for (self.tabs[0..self.tab_count]) |*tab| {
            for (tab.panes[0..tab.pane_count]) |*pane| {
                const basis = pane.basis_rect;
                const right = std.math.add(i64, basis.x, basis.width) catch return error.ArithmeticOverflow;
                const bottom = std.math.sub(i64, std.math.add(i64, basis.y, basis.height) catch return error.ArithmeticOverflow, self.tab_bar_height) catch return error.ArithmeticOverflow;
                const local_y = std.math.sub(i64, basis.y, self.tab_bar_height) catch return error.ArithmeticOverflow;
                const new_x = try legacyScaleEdge(basis.x, old_content.width, new_content.width);
                const new_right = try legacyScaleEdge(right, old_content.width, new_content.width);
                const new_y = try legacyScaleEdge(local_y, old_content.height, new_content.height);
                const new_bottom = try legacyScaleEdge(bottom, old_content.height, new_content.height);
                if (new_right <= new_x or new_bottom <= new_y) return error.InvalidGeometry;
                pane.rect = .{ .x = @intCast(new_x), .y = @intCast(new_y + self.tab_bar_height), .width = @intCast(new_right - new_x), .height = @intCast(new_bottom - new_y) };
            }
        }
        self.surface = surface;
    }

    fn focusPane(self: *LegacyTopology, id: chrome.PaneId) !void {
        var candidate = self.*;
        const tab = &candidate.tabs[candidate.active_tab];
        var found = false;
        for (tab.panes[0..tab.pane_count]) |*pane| {
            pane.focused = pane.id == id;
            found = found or pane.focused;
        }
        if (!found) return error.InvalidId;
        self.* = candidate;
    }

    fn normalized(self: *const LegacyTopology) !session.SessionState {
        const content = session.Size{ .width = self.surface.width, .height = self.surface.height - self.tab_bar_height };
        var result = try session.SessionState.init(content);
        result.tabs = undefined;
        result.tab_count = self.tab_count;
        result.active_tab = self.active_tab;
        result.next_tab_id = self.next_tab_id;
        result.next_pane_id = self.next_pane_id;
        result.live_panes = self.live_panes;
        result.content_size = content;
        result.basis_content_size = .{ .width = self.basis_surface.width, .height = self.basis_surface.height - self.tab_bar_height };
        for (self.tabs[0..self.tab_count], 0..) |legacy_tab, tab_index| {
            var tab = session.Tab{ .id = try chrome_state.fromRenderTabId(legacy_tab.id), .pane_count = legacy_tab.pane_count };
            @memcpy(tab.label[0..legacy_tab.label_len], legacy_tab.label[0..legacy_tab.label_len]);
            tab.label_len = legacy_tab.label_len;
            for (legacy_tab.panes[0..legacy_tab.pane_count], 0..) |legacy_pane, pane_index| {
                const rect: session.Rect = .{
                    .x = legacy_pane.rect.x,
                    .y = legacy_pane.rect.y - self.tab_bar_height,
                    .width = legacy_pane.rect.width,
                    .height = legacy_pane.rect.height,
                };
                const basis_rect: session.Rect = .{
                    .x = legacy_pane.basis_rect.x,
                    .y = legacy_pane.basis_rect.y - self.tab_bar_height,
                    .width = legacy_pane.basis_rect.width,
                    .height = legacy_pane.basis_rect.height,
                };
                var pane = session.Pane{
                    .id = try chrome_state.fromRenderPaneId(legacy_pane.id),
                    .rect = rect,
                    .basis_rect = basis_rect,
                    .focused = legacy_pane.focused,
                    .layer = @fromBackingInt(@intCast(@backingInt(legacy_pane.layer))),
                };
                @memcpy(pane.label[0..legacy_pane.label_len], legacy_pane.label[0..legacy_pane.label_len]);
                pane.label_len = legacy_pane.label_len;
                pane.scroll = if (legacy_pane.scroll) |scroll| .{ .visible = scroll.visible, .total = scroll.total, .start = scroll.start } else null;
                tab.panes[pane_index] = pane;
            }
            result.tabs[tab_index] = tab;
        }
        try result.validate();
        return result;
    }

    fn project(self: *const LegacyTopology, appearance: Appearance, selections: []const chrome.Selection, primitives: []chrome.Primitive, text: []u8) chrome.Error!chrome.Output {
        var tabs: [max_tabs]chrome.Tab = undefined;
        for (self.tabs[0..self.tab_count], 0..) |*tab, index| {
            tabs[index] = .{ .id = tab.id, .label = tab.label[0..tab.label_len], .active = index == self.active_tab };
        }
        var panes: [max_panes_per_tab]chrome.Pane = undefined;
        const active = &self.tabs[self.active_tab];
        for (active.panes[0..active.pane_count], 0..) |*pane, index| {
            panes[index] = .{ .id = pane.id, .rect = pane.rect, .label = pane.label[0..pane.label_len], .focused = pane.focused, .scroll = pane.scroll, .layer = pane.layer };
        }
        return chrome.project(.{
            .surface = self.surface,
            .tab_bar_height = self.tab_bar_height,
            .tabs = tabs[0..self.tab_count],
            .panes = panes[0..active.pane_count],
            .selections = selections,
            .style = appearance.style,
            .tab_active_background = appearance.tab_active_background,
            .tab_inactive_background = appearance.tab_inactive_background,
            .scrollbar_width = scrollbar_width,
            .scrollbar_min_thumb = scrollbar_min_thumb,
        }, primitives, text);
    }

    fn hitTest(self: *const LegacyTopology, point: chrome.Point) chrome.Error!?chrome.Hit {
        var tabs: [max_tabs]chrome.Tab = undefined;
        for (self.tabs[0..self.tab_count], 0..) |*tab, index| tabs[index] = .{ .id = tab.id, .label = tab.label[0..tab.label_len], .active = index == self.active_tab };
        var panes: [max_panes_per_tab]chrome.Pane = undefined;
        const active = &self.tabs[self.active_tab];
        for (active.panes[0..active.pane_count], 0..) |*pane, index| panes[index] = .{ .id = pane.id, .rect = pane.rect, .label = pane.label[0..pane.label_len], .focused = pane.focused, .scroll = pane.scroll, .layer = pane.layer };
        const appearance = testAppearance();
        return chrome.hitTest(.{
            .surface = self.surface,
            .tab_bar_height = self.tab_bar_height,
            .tabs = tabs[0..self.tab_count],
            .panes = panes[0..active.pane_count],
            .selections = &.{},
            .style = appearance.style,
            .tab_active_background = appearance.tab_active_background,
            .tab_inactive_background = appearance.tab_inactive_background,
            .scrollbar_width = scrollbar_width,
            .scrollbar_min_thumb = scrollbar_min_thumb,
        }, point);
    }
};

fn expectSemanticEqual(left: *const session.SessionState, right: *const session.SessionState) !void {
    try std.testing.expectEqual(left.tab_count, right.tab_count);
    try std.testing.expectEqual(left.active_tab, right.active_tab);
    try std.testing.expectEqual(left.next_tab_id, right.next_tab_id);
    try std.testing.expectEqual(left.next_pane_id, right.next_pane_id);
    try std.testing.expectEqual(left.live_panes, right.live_panes);
    try std.testing.expectEqual(left.content_size, right.content_size);
    try std.testing.expectEqual(left.basis_content_size, right.basis_content_size);
    for (left.tabs[0..left.tab_count], right.tabs[0..right.tab_count]) |left_tab, right_tab| {
        try std.testing.expectEqual(left_tab.id, right_tab.id);
        try std.testing.expectEqualSlices(u8, left_tab.label[0..left_tab.label_len], right_tab.label[0..right_tab.label_len]);
        try std.testing.expectEqual(left_tab.pane_count, right_tab.pane_count);
        for (left_tab.panes[0..left_tab.pane_count], right_tab.panes[0..right_tab.pane_count]) |left_pane, right_pane| {
            try std.testing.expectEqual(left_pane.id, right_pane.id);
            try std.testing.expectEqual(left_pane.rect, right_pane.rect);
            try std.testing.expectEqual(left_pane.basis_rect, right_pane.basis_rect);
            try std.testing.expectEqual(left_pane.focused, right_pane.focused);
            try std.testing.expectEqual(left_pane.scroll, right_pane.scroll);
            try std.testing.expectEqual(left_pane.layer, right_pane.layer);
            try std.testing.expectEqualSlices(u8, left_pane.label[0..left_pane.label_len], right_pane.label[0..right_pane.label_len]);
        }
    }
}

fn expectHitEquivalent(left: ?chrome.Hit, right: ?chrome.Hit) !void {
    try std.testing.expectEqual(left != null, right != null);
    if (left) |left_hit| {
        const right_hit = right.?;
        switch (left_hit) {
            .tab => |id| try std.testing.expectEqual(id, try chrome_state.toRenderTabId(try chrome_state.fromRenderTabId(switch (right_hit) {
                .tab => |right_id| right_id,
                .pane => return error.TestUnexpectedResult,
            }))),
            .pane => |id| try std.testing.expectEqual(id, try chrome_state.toRenderPaneId(try chrome_state.fromRenderPaneId(switch (right_hit) {
                .pane => |right_id| right_id,
                .tab => return error.TestUnexpectedResult,
            }))),
        }
    }
}

fn expectProjectedEquivalent(old: chrome.Output, modern: chrome.Output) !void {
    try std.testing.expectEqual(old.surface, modern.surface);
    try std.testing.expectEqualDeep(old.primitives, modern.primitives);
    try std.testing.expectEqualSlices(u8, old.text, modern.text);
}

test "normalized legacy and content-local topology remain equivalent" {
    var legacy = try LegacyTopology.init(.{ .width = 320, .height = 240 }, default_tab_bar_height);
    var modern = try session.SessionState.init(.{ .width = 320, .height = 216 });
    try expectSemanticEqual(&modern, &(try legacy.normalized()));

    const appearance = testAppearance();
    var old_primitives: [256]chrome.Primitive = undefined;
    var old_text: [4096]u8 = undefined;
    var modern_primitives: [256]chrome.Primitive = undefined;
    var modern_text: [4096]u8 = undefined;
    const old_output = try legacy.project(appearance, &.{}, &old_primitives, &old_text);
    const modern_output = try chrome_state.project(&modern, appearance, .{ .width = 320, .height = 240 }, .{ .y = 24 }, &.{}, &modern_primitives, &modern_text);
    try expectProjectedEquivalent(old_output, modern_output);
    for ([_]chrome.Point{ .{ .x = 1, .y = 1 }, .{ .x = 1, .y = 25 }, .{ .x = 319, .y = 239 }, .{ .x = -1, .y = -1 } }) |point| {
        try expectHitEquivalent(try legacy.hitTest(point), try chrome_state.hitTest(&modern, appearance, .{ .width = 320, .height = 240 }, .{ .y = 24 }, point));
    }

    const old_tab = try legacy.createTab("other");
    const modern_tab = try modern.createTab("other");
    try std.testing.expectEqual(old_tab, try chrome_state.toRenderTabId(modern_tab));
    try expectSemanticEqual(&modern, &(try legacy.normalized()));
    try legacy.resizeSurface(.{ .width = 400, .height = 300 });
    try modern.resizeSurface(.{ .width = 400, .height = 276 });
    try expectSemanticEqual(&modern, &(try legacy.normalized()));
    try legacy.closeTab(old_tab);
    try modern.closeTab(modern_tab);
    try expectSemanticEqual(&modern, &(try legacy.normalized()));

    const old_new_pane = try legacy.splitVertical(0);
    const modern_new_pane = try modern.split(modern.focusedPaneId(), .vertical);
    try std.testing.expectEqual(old_new_pane, try chrome_state.toRenderPaneId(modern_new_pane));
    try legacy.focusPane(old_new_pane);
    try modern.focusPane(modern_new_pane);
    try expectSemanticEqual(&modern, &(try legacy.normalized()));
    const old_after = try legacy.project(appearance, &.{}, &old_primitives, &old_text);
    const modern_after = try chrome_state.project(&modern, appearance, .{ .width = 400, .height = 300 }, .{ .y = 24 }, &.{}, &modern_primitives, &modern_text);
    try expectProjectedEquivalent(old_after, modern_after);
    for ([_]chrome.Point{ .{ .x = 1, .y = 25 }, .{ .x = 250, .y = 25 }, .{ .x = 399, .y = 299 } }) |point| {
        try expectHitEquivalent(try legacy.hitTest(point), try chrome_state.hitTest(&modern, appearance, .{ .width = 400, .height = 300 }, .{ .y = 24 }, point));
    }

    const before_invalid = modern;
    const legacy_before_invalid = try legacy.normalized();
    try std.testing.expectError(error.InvalidId, legacy.focusPane(@fromBackingInt(@intCast(0))));
    try std.testing.expectError(error.InvalidId, modern.focusPane(@fromBackingInt(@intCast(0))));
    try expectSemanticEqual(&before_invalid, &modern);
    try expectSemanticEqual(&legacy_before_invalid, &(try legacy.normalized()));
    try std.testing.expectError(error.InvalidSurface, legacy.resizeSurface(.{ .width = 0, .height = 300 }));
    try std.testing.expectError(error.InvalidGeometry, modern.resizeSurface(.{ .width = 0, .height = 276 }));
    try expectSemanticEqual(&before_invalid, &modern);
    try expectSemanticEqual(&legacy_before_invalid, &(try legacy.normalized()));
}
