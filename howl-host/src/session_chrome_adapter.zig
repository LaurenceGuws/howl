//! Owns Chrome constants and the checked SessionState-to-Render adapter.

const std = @import("std");
const render = @import("howl_render");
const session = @import("session_domain");
const chrome = render.chrome;

/// Errors returned while adapting semantic state or projecting Chrome.
pub const Error = session.Error || chrome.Error;
/// Default Host tab-bar height used for physical content-origin derivation.
pub const default_tab_bar_height: u16 = 24;
/// Shared scrollbar width bound.
pub const scrollbar_width: u16 = session.scrollbar_width;
/// Shared minimum scrollbar thumb bound.
pub const scrollbar_min_thumb: u16 = session.scrollbar_min_thumb;
/// Maximum session tab count exposed to the adapter.
pub const max_tabs: usize = session.max_tabs;
/// Maximum panes per session tab exposed to the adapter.
pub const max_panes_per_tab: usize = session.max_panes_per_tab;
/// Maximum live session panes exposed to the adapter.
pub const max_live_panes: usize = session.max_live_panes;
/// Maximum copied tab or pane label length.
pub const max_label_bytes: usize = session.max_label_bytes;

/// Caller-selected appearance used only while deriving Chrome primitives.
pub const Appearance = struct {
    style: chrome.Style,
    tab_active_background: chrome.Color,
    tab_inactive_background: chrome.Color,
};

/// Physical surface geometry supplied by Host configure.
pub const SurfaceGeometry = chrome.Size;

/// Host-owned surface-logical origin of content below the tab bar.
pub const ContentOrigin = struct { y: u16 };

/// Converts a nonzero semantic tab identity to its checked Render form.
pub fn toRenderTabId(id: session.TabId) chrome.Error!chrome.TabId {
    if (@backingInt(id) == 0) return error.InvalidIdentity;
    return @fromBackingInt(@intCast(@backingInt(id)));
}

/// Converts a nonzero semantic pane identity to its checked Render form.
pub fn toRenderPaneId(id: session.PaneId) chrome.Error!chrome.PaneId {
    if (@backingInt(id) == 0) return error.InvalidIdentity;
    return @fromBackingInt(@intCast(@backingInt(id)));
}

/// Converts a nonzero Render tab identity back to the semantic owner form.
pub fn fromRenderTabId(id: chrome.TabId) session.Error!session.TabId {
    if (@backingInt(id) == 0) return error.InvalidIdentity;
    return @fromBackingInt(@intCast(@backingInt(id)));
}

/// Converts a nonzero Render pane identity back to the semantic owner form.
pub fn fromRenderPaneId(id: chrome.PaneId) session.Error!session.PaneId {
    if (@backingInt(id) == 0) return error.InvalidIdentity;
    return @fromBackingInt(@intCast(@backingInt(id)));
}

/// Adds the checked Host content origin to a content-local semantic rectangle.
pub fn toRenderRect(local: session.Rect, origin: ContentOrigin) chrome.Error!chrome.Rect {
    if (local.width == 0 or local.height == 0 or local.x < 0 or local.y < 0)
        return error.InvalidRectangle;
    const y = std.math.add(i64, local.y, origin.y) catch return error.ArithmeticOverflow;
    if (y > std.math.maxInt(i32)) return error.ArithmeticOverflow;
    return .{ .x = local.x, .y = @intCast(y), .width = local.width, .height = local.height };
}

/// Derives the checked surface-logical content origin from tab-bar geometry.
pub fn contentOrigin(surface: SurfaceGeometry, tab_bar_height: u16) chrome.Error!ContentOrigin {
    if (surface.width == 0 or surface.height == 0) return error.InvalidSurface;
    return .{ .y = @min(tab_bar_height, surface.height - 1) };
}

fn validateContentExtent(
    state: *const session.SessionState,
    surface: SurfaceGeometry,
    origin: ContentOrigin,
) chrome.Error!void {
    if (surface.width == 0 or surface.height == 0 or origin.y >= surface.height)
        return error.InvalidSurface;
    if (state.content_size.width != surface.width or
        state.content_size.height != surface.height - origin.y)
        return error.InvalidSurface;
}

/// Projects content-local SessionState into surface-coordinate Render inputs.
pub fn project(
    state: *const session.SessionState,
    appearance: Appearance,
    surface: SurfaceGeometry,
    origin: ContentOrigin,
    selections: []const chrome.Selection,
    primitives: []chrome.Primitive,
    text: []u8,
) chrome.Error!chrome.Output {
    try validateContentExtent(state, surface, origin);
    var tabs: [max_tabs]chrome.Tab = undefined;
    for (state.tabs[0..state.tab_count], 0..) |*tab, index| {
        tabs[index] = .{
            .id = try toRenderTabId(tab.id),
            .label = tab.label[0..tab.label_len],
            .active = index == state.active_tab,
        };
    }
    var panes: [max_panes_per_tab]chrome.Pane = undefined;
    const active = &state.tabs[state.active_tab];
    for (active.panes[0..active.pane_count], 0..) |*pane, index| {
        panes[index] = .{
            .id = try toRenderPaneId(pane.id),
            .rect = try toRenderRect(pane.rect, origin),
            .label = pane.label[0..pane.label_len],
            .focused = pane.focused,
            .scroll = if (pane.scroll) |scroll| .{ .visible = scroll.visible, .total = scroll.total, .start = scroll.start } else null,
            .layer = @fromBackingInt(@intCast(@backingInt(pane.layer))),
        };
    }
    return chrome.project(.{
        .surface = surface,
        .tab_bar_height = origin.y,
        .tabs = tabs[0..state.tab_count],
        .panes = panes[0..active.pane_count],
        .selections = selections,
        .style = appearance.style,
        .tab_active_background = appearance.tab_active_background,
        .tab_inactive_background = appearance.tab_inactive_background,
        .scrollbar_width = scrollbar_width,
        .scrollbar_min_thumb = scrollbar_min_thumb,
    }, primitives, text);
}

/// Hit-tests the original surface-coordinate pointer against projected geometry.
pub fn hitTest(
    state: *const session.SessionState,
    appearance: Appearance,
    surface: SurfaceGeometry,
    origin: ContentOrigin,
    point: chrome.Point,
) chrome.Error!?chrome.Hit {
    try validateContentExtent(state, surface, origin);
    var tabs: [max_tabs]chrome.Tab = undefined;
    for (state.tabs[0..state.tab_count], 0..) |*tab, index| {
        tabs[index] = .{ .id = try toRenderTabId(tab.id), .label = tab.label[0..tab.label_len], .active = index == state.active_tab };
    }
    var panes: [max_panes_per_tab]chrome.Pane = undefined;
    const active = &state.tabs[state.active_tab];
    for (active.panes[0..active.pane_count], 0..) |*pane, index| {
        panes[index] = .{
            .id = try toRenderPaneId(pane.id),
            .rect = try toRenderRect(pane.rect, origin),
            .label = pane.label[0..pane.label_len],
            .focused = pane.focused,
            .scroll = if (pane.scroll) |scroll| .{ .visible = scroll.visible, .total = scroll.total, .start = scroll.start } else null,
            .layer = @fromBackingInt(@intCast(@backingInt(pane.layer))),
        };
    }
    return chrome.hitTest(.{
        .surface = surface,
        .tab_bar_height = origin.y,
        .tabs = tabs[0..state.tab_count],
        .panes = panes[0..active.pane_count],
        .selections = &.{},
        .style = appearance.style,
        .tab_active_background = appearance.tab_active_background,
        .tab_inactive_background = appearance.tab_inactive_background,
        .scrollbar_width = scrollbar_width,
        .scrollbar_min_thumb = scrollbar_min_thumb,
    }, point);
}

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

test "Chrome adapter preserves content origin and surface hit coordinates" {
    var state = try session.SessionState.init(.{ .width = 80, .height = 16 });
    const appearance = testAppearance();
    const origin = try contentOrigin(.{ .width = 80, .height = 40 }, default_tab_bar_height);
    var primitives: [64]chrome.Primitive = undefined;
    var text: [512]u8 = undefined;
    const output = try project(&state, appearance, .{ .width = 80, .height = 40 }, origin, &.{}, &primitives, &text);
    try std.testing.expectEqual(@as(i32, 24), state.tabs[0].panes[0].rect.y + origin.y);
    try std.testing.expect(output.primitives.len > 0);
    try std.testing.expectEqualDeep(chrome.Hit{ .pane = @fromBackingInt(@intCast(@backingInt(state.focusedPaneId()))) }, try hitTest(&state, appearance, .{ .width = 80, .height = 40 }, origin, .{ .x = 1, .y = 25 }));
}

test "Chrome adapter rejects inconsistent content extent before output or hit testing" {
    const state = try session.SessionState.init(.{ .width = 80, .height = 16 });
    const appearance = testAppearance();
    const surface = SurfaceGeometry{ .width = 80, .height = 39 };
    const origin = ContentOrigin{ .y = 24 };
    var primitives: [64]chrome.Primitive = @splat(.{ .fill = .{
        .rect = .{ .x = 3, .y = 4, .width = 5, .height = 6 },
        .color = .{ .r = 7, .g = 8, .b = 9, .a = 10 },
    } });
    var text: [512]u8 = undefined;
    @memset(&text, 0xa5);
    const primitives_before = primitives;
    const text_before = text;
    try std.testing.expectError(
        error.InvalidSurface,
        project(&state, appearance, surface, origin, &.{}, &primitives, &text),
    );
    try std.testing.expectEqualDeep(primitives_before, primitives);
    try std.testing.expectEqualSlices(u8, &text_before, &text);
    try std.testing.expectError(
        error.InvalidSurface,
        hitTest(&state, appearance, surface, origin, .{ .x = 1, .y = 25 }),
    );
}

test "Chrome adapter preserves tiny surfaces and hidden tabs" {
    var tiny = try session.SessionState.init(.{ .width = 8, .height = 1 });
    const tiny_origin = try contentOrigin(.{ .width = 8, .height = 1 }, default_tab_bar_height);
    var primitives: [32]chrome.Primitive = undefined;
    var text: [256]u8 = undefined;
    const tiny_output = try project(&tiny, testAppearance(), .{ .width = 8, .height = 1 }, tiny_origin, &.{}, &primitives, &text);
    try std.testing.expect(tiny_output.primitives.len > 0);
    try std.testing.expectEqual(@as(i32, 0), tiny.paneRect(tiny.focusedPaneId()).?.y);

    var state = try session.SessionState.init(.{ .width = 120, .height = 56 });
    const first_tab = state.activeTabId();
    const floating = try state.createFloatingPane(.{ .x = 12, .y = 8, .width = 60, .height = 36 }, "float");
    const other_tab = try state.createTab("other");
    try std.testing.expect(@backingInt(other_tab) != 0);
    const hidden = try project(&state, testAppearance(), .{ .width = 120, .height = 80 }, .{ .y = 24 }, &.{}, primitives[0..], text[0..]);
    try std.testing.expect(!std.mem.containsAtLeast(u8, hidden.text, 1, "float"));
    try state.switchTab(first_tab);
    const visible = try project(&state, testAppearance(), .{ .width = 120, .height = 80 }, .{ .y = 24 }, &.{}, primitives[0..], text[0..]);
    try std.testing.expect(std.mem.containsAtLeast(u8, visible.text, 1, "float"));
    const hit = try hitTest(&state, testAppearance(), .{ .width = 120, .height = 80 }, .{ .y = 24 }, .{ .x = 20, .y = 34 });
    try std.testing.expectEqual(floating, fromRenderPaneId(hit.?.pane));
}

test "Chrome adapter projects floating order and checked identity adaptation" {
    var state = try session.SessionState.init(.{ .width = 160, .height = 76 });
    const tiled = state.focusedPaneId();
    const first = try state.createFloatingPane(.{ .x = 20, .y = 8, .width = 80, .height = 40 }, "first");
    const second = try state.createFloatingPane(.{ .x = 50, .y = 16, .width = 80, .height = 40 }, "second");
    const surface = SurfaceGeometry{ .width = 160, .height = 100 };
    var primitives: [128]chrome.Primitive = undefined;
    var text: [1024]u8 = undefined;
    const appearance = testAppearance();
    try std.testing.expectEqual(second, fromRenderPaneId((try hitTest(&state, appearance, surface, .{ .y = 24 }, .{ .x = 60, .y = 50 })).?.pane));
    try state.raiseFloatingPane(first);
    try std.testing.expectEqual(first, fromRenderPaneId((try hitTest(&state, appearance, surface, .{ .y = 24 }, .{ .x = 60, .y = 50 })).?.pane));
    try std.testing.expectEqual(tiled, fromRenderPaneId((try hitTest(&state, appearance, surface, .{ .y = 24 }, .{ .x = 140, .y = 90 })).?.pane));
    const output = try project(&state, appearance, surface, .{ .y = 24 }, &.{}, &primitives, &text);
    try std.testing.expect(output.primitives.len > 0);
    try std.testing.expectError(error.InvalidIdentity, toRenderPaneId(@fromBackingInt(@intCast(0))));
    try std.testing.expectError(error.InvalidIdentity, fromRenderPaneId(@fromBackingInt(@intCast(0))));
}
