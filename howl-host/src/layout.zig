//! Owns the native host's deliberately small tab and tiled-pane topology.
//!
//! This is executable-local policy, not a shared client abstraction. It owns
//! only stable identities, bounded split trees, active/focused selection, and
//! deterministic rectangle projection. Instance, terminal, Wayland, and GPU
//! state stay outside this module.

const std = @import("std");

pub const max_tabs: u8 = 8;
pub const max_panes_per_tab: u8 = 8;
pub const max_panes: u8 = 32;
const max_nodes_per_tab: u8 = max_panes_per_tab * 2 - 1;
const no_node = std.math.maxInt(u8);

pub const TabId = enum(u32) { _ };
pub const PaneId = enum(u32) { _ };
pub const SplitAxis = enum { horizontal, vertical };

pub const Surface = struct {
    width: u32,
    height: u32,
};

pub const Rect = struct {
    x: u32,
    y: u32,
    width: u32,
    height: u32,
};

pub const Placement = struct {
    pane: PaneId,
    rect: Rect,
    focused: bool,
};

pub const CreatedTab = struct {
    tab: TabId,
    pane: PaneId,
};

const Split = struct {
    axis: SplitAxis,
    first: u8,
    second: u8,
    /// Signed cell bias from the deterministic half split.
    delta: i32 = 0,
};

const Node = union(enum) {
    free,
    pane: PaneId,
    split: Split,
};

const Tab = struct {
    id: TabId,
    nodes: [max_nodes_per_tab]Node = @splat(.free),
    root: u8 = 0,
    pane_count: u8 = 1,
    focused: PaneId,

    fn init(id: TabId, pane: PaneId) Tab {
        var result = Tab{ .id = id, .focused = pane };
        result.nodes[0] = .{ .pane = pane };
        return result;
    }

    fn findPane(self: *const Tab, pane: PaneId) ?u8 {
        for (self.nodes, 0..) |node, index| switch (node) {
            .pane => |candidate| if (candidate == pane) return @intCast(index),
            else => {},
        };
        return null;
    }

    fn findFree(self: *const Tab, skip: u8) ?u8 {
        for (self.nodes, 0..) |node, index| {
            if (index == skip) continue;
            if (node == .free) return @intCast(index);
        }
        return null;
    }

    fn findParent(self: *const Tab, child: u8) ?u8 {
        for (self.nodes, 0..) |node, index| switch (node) {
            .split => |split| if (split.first == child or split.second == child)
                return @intCast(index),
            else => {},
        };
        return null;
    }

    fn firstPane(self: *const Tab, node_index: u8) PaneId {
        var cursor = node_index;
        while (true) switch (self.nodes[cursor]) {
            .pane => |pane| return pane,
            .split => |split| cursor = split.first,
            .free => unreachable,
        };
    }

    fn splitFocused(self: *Tab, pane: PaneId, axis: SplitAxis) error{PaneLimit}!void {
        if (self.pane_count == max_panes_per_tab) return error.PaneLimit;
        const leaf = self.findPane(self.focused) orelse unreachable;
        const first = self.findFree(leaf) orelse unreachable;
        var candidate = self.*;
        candidate.nodes[first] = .{ .pane = candidate.focused };
        const second = candidate.findFree(leaf) orelse unreachable;
        candidate.nodes[second] = .{ .pane = pane };
        candidate.nodes[leaf] = .{ .split = .{ .axis = axis, .first = first, .second = second } };
        candidate.pane_count += 1;
        candidate.focused = pane;
        self.* = candidate;
    }

    fn closeFocused(self: *Tab) error{LastPane}!PaneId {
        if (self.pane_count == 1) return error.LastPane;
        const retiring = self.focused;
        const leaf = self.findPane(retiring) orelse unreachable;
        const parent = self.findParent(leaf) orelse unreachable;
        const split = self.nodes[parent].split;
        const sibling = if (split.first == leaf) split.second else split.first;
        var candidate = self.*;
        candidate.nodes[parent] = candidate.nodes[sibling];
        candidate.nodes[leaf] = .free;
        if (sibling != parent) candidate.nodes[sibling] = .free;
        candidate.pane_count -= 1;
        candidate.focused = candidate.firstPane(parent);
        self.* = candidate;
        return retiring;
    }

    fn collectPanes(
        self: *const Tab,
        node_index: u8,
        output: *[max_panes_per_tab]PaneId,
        count: *u8,
    ) void {
        switch (self.nodes[node_index]) {
            .free => unreachable,
            .pane => |pane| {
                output[count.*] = pane;
                count.* += 1;
            },
            .split => |split| {
                self.collectPanes(split.first, output, count);
                self.collectPanes(split.second, output, count);
            },
        }
    }

    fn nodeRect(self: *const Tab, target: u8, surface: Surface) ?Rect {
        return self.findNodeRect(
            self.root,
            target,
            .{ .x = 0, .y = 0, .width = surface.width, .height = surface.height },
        );
    }

    fn findNodeRect(self: *const Tab, node_index: u8, target: u8, rect: Rect) ?Rect {
        if (node_index == target) return rect;
        return switch (self.nodes[node_index]) {
            .free, .pane => null,
            .split => |split| found: {
                const extent = splitExtent(split, rect) catch break :found null;
                var first = rect;
                var second = rect;
                switch (split.axis) {
                    .horizontal => {
                        first.width = extent;
                        second.x += extent;
                        second.width -= extent;
                    },
                    .vertical => {
                        first.height = extent;
                        second.y += extent;
                        second.height -= extent;
                    },
                }
                break :found self.findNodeRect(split.first, target, first) orelse
                    self.findNodeRect(split.second, target, second);
            },
        };
    }

    fn project(
        self: *const Tab,
        surface: Surface,
        output: []Placement,
    ) error{ InvalidSurface, InsufficientOutput, GeometryLimit }![]const Placement {
        if (surface.width == 0 or surface.height == 0) return error.InvalidSurface;
        if (output.len < self.pane_count) return error.InsufficientOutput;
        var candidate: [max_panes_per_tab]Placement = undefined;
        var count: u8 = 0;
        try self.projectNode(
            self.root,
            .{ .x = 0, .y = 0, .width = surface.width, .height = surface.height },
            &candidate,
            &count,
        );
        std.debug.assert(count == self.pane_count);
        @memcpy(output[0..count], candidate[0..count]);
        return output[0..count];
    }

    fn projectNode(
        self: *const Tab,
        node_index: u8,
        rect: Rect,
        output: *[max_panes_per_tab]Placement,
        count: *u8,
    ) error{GeometryLimit}!void {
        switch (self.nodes[node_index]) {
            .free => unreachable,
            .pane => |pane| {
                output[count.*] = .{ .pane = pane, .rect = rect, .focused = pane == self.focused };
                count.* += 1;
            },
            .split => |split| {
                const extent = try splitExtent(split, rect);
                var first = rect;
                var second = rect;
                switch (split.axis) {
                    .horizontal => {
                        first.width = extent;
                        second.x += extent;
                        second.width -= extent;
                    },
                    .vertical => {
                        first.height = extent;
                        second.y += extent;
                        second.height -= extent;
                    },
                }
                try self.projectNode(split.first, first, output, count);
                try self.projectNode(split.second, second, output, count);
            },
        }
    }
};

/// Host-local bounded multiplexing state.
pub const Mux = struct {
    tabs: [max_tabs]Tab = undefined,
    tab_count: u8 = 1,
    pane_count: u8 = 1,
    active_index: u8 = 0,
    next_tab: u32 = 2,
    next_pane: u32 = 2,

    pub fn init() Mux {
        var result = Mux{};
        result.tabs[0] = Tab.init(tabId(1), paneId(1));
        return result;
    }

    pub fn tabCount(self: *const Mux) u8 {
        return self.tab_count;
    }

    pub fn paneCount(self: *const Mux) u8 {
        return self.pane_count;
    }

    pub fn activeTab(self: *const Mux) TabId {
        return self.tabs[self.active_index].id;
    }

    pub fn focusedPane(self: *const Mux) PaneId {
        return self.tabs[self.active_index].focused;
    }

    pub fn createTab(self: *Mux) error{ TabLimit, PaneLimit, IdExhausted }!CreatedTab {
        if (self.tab_count == max_tabs) return error.TabLimit;
        if (self.pane_count == max_panes) return error.PaneLimit;
        if (self.next_tab == 0 or self.next_tab == std.math.maxInt(u32) or
            self.next_pane == 0 or self.next_pane == std.math.maxInt(u32)) return error.IdExhausted;
        const tab = tabId(self.next_tab);
        const pane = paneId(self.next_pane);
        self.tabs[self.tab_count] = Tab.init(tab, pane);
        self.active_index = self.tab_count;
        self.tab_count += 1;
        self.pane_count += 1;
        self.next_tab += 1;
        self.next_pane += 1;
        return .{ .tab = tab, .pane = pane };
    }

    pub fn switchTab(self: *Mux, id: TabId) error{StaleTab}!bool {
        const index = self.tabIndex(id) orelse return error.StaleTab;
        if (index == self.active_index) return false;
        self.active_index = index;
        return true;
    }

    /// Selects the next tab in retained display order and wraps.
    /// A one-tab mux is unchanged.
    pub fn nextTab(self: *Mux) bool {
        if (self.tab_count < 2) return false;
        self.active_index = (self.active_index + 1) % self.tab_count;
        return true;
    }

    pub fn closeActiveTab(self: *Mux) error{LastTab}!void {
        if (self.tab_count == 1) return error.LastTab;
        const index = self.active_index;
        self.pane_count -= self.tabs[index].pane_count;
        var cursor = index;
        while (cursor + 1 < self.tab_count) : (cursor += 1) self.tabs[cursor] = self.tabs[cursor + 1];
        self.tab_count -= 1;
        if (self.active_index == self.tab_count) self.active_index -= 1;
    }

    pub fn splitFocused(self: *Mux, axis: SplitAxis) error{ PaneLimit, IdExhausted }!PaneId {
        if (self.pane_count == max_panes or self.tabs[self.active_index].pane_count == max_panes_per_tab)
            return error.PaneLimit;
        if (self.next_pane == 0 or self.next_pane == std.math.maxInt(u32)) return error.IdExhausted;
        const pane = paneId(self.next_pane);
        try self.tabs[self.active_index].splitFocused(pane, axis);
        self.pane_count += 1;
        self.next_pane += 1;
        return pane;
    }

    pub fn closeFocused(self: *Mux) error{LastPane}!PaneId {
        const retired = try self.tabs[self.active_index].closeFocused();
        self.pane_count -= 1;
        return retired;
    }

    pub fn focusPane(self: *Mux, pane: PaneId) error{StalePane}!bool {
        const tab = &self.tabs[self.active_index];
        if (tab.findPane(pane) == null) return error.StalePane;
        if (tab.focused == pane) return false;
        tab.focused = pane;
        return true;
    }

    /// Cycles active-tab focus in deterministic projection order.
    /// A one-pane tab remains focused on its sole pane.
    pub fn focusNext(self: *Mux) PaneId {
        const tab = &self.tabs[self.active_index];
        var panes: [max_panes_per_tab]PaneId = undefined;
        var count: u8 = 0;
        tab.collectPanes(tab.root, &panes, &count);
        std.debug.assert(count == tab.pane_count and count != 0);
        for (panes[0..count], 0..) |pane, index| {
            if (pane != tab.focused) continue;
            const next = panes[(index + 1) % count];
            tab.focused = next;
            return next;
        }
        unreachable;
    }

    /// Grows (positive cells) or shrinks (negative cells) the focused pane
    /// against its immediate sibling. Saturation at one cell is a no-op.
    pub fn resizeFocused(self: *Mux, surface: Surface, cells: i32) error{InvalidSurface}!bool {
        if (surface.width == 0 or surface.height == 0) return error.InvalidSurface;
        if (cells == 0) return false;
        const tab = &self.tabs[self.active_index];
        const leaf = tab.findPane(tab.focused) orelse unreachable;
        const parent = tab.findParent(leaf) orelse return false;
        const parent_rect = tab.nodeRect(parent, surface) orelse return error.InvalidSurface;
        const split = &tab.nodes[parent].split;
        const current = splitExtent(split.*, parent_rect) catch return error.InvalidSurface;
        const total = if (split.axis == .horizontal) parent_rect.width else parent_rect.height;
        const signed_change: i64 = if (split.first == leaf) cells else -@as(i64, cells);
        const proposed = @as(i64, current) + signed_change;
        const target: u32 = @intCast(std.math.clamp(proposed, 1, @as(i64, total) - 1));
        if (target == current) return false;
        const base = total / 2;
        split.delta = @intCast(@as(i64, target) - @as(i64, base));
        return true;
    }

    pub fn activeLayout(
        self: *const Mux,
        surface: Surface,
        output: []Placement,
    ) error{ InvalidSurface, InsufficientOutput, GeometryLimit }![]const Placement {
        return self.tabs[self.active_index].project(surface, output);
    }

    /// Projects one stable pane in whichever retained tab owns it.
    pub fn paneRect(
        self: *const Mux,
        surface: Surface,
        pane: PaneId,
    ) error{ StalePane, InvalidSurface, GeometryLimit }!Rect {
        var storage: [max_panes_per_tab]Placement = undefined;
        for (self.tabs[0..self.tab_count]) |tab| {
            if (tab.findPane(pane) == null) continue;
            const placed = tab.project(surface, &storage) catch |failure| switch (failure) {
                error.InsufficientOutput => unreachable,
                else => |err| return err,
            };
            for (placed) |value| if (value.pane == pane) return value.rect;
            unreachable;
        }
        return error.StalePane;
    }

    fn tabIndex(self: *const Mux, id: TabId) ?u8 {
        for (self.tabs[0..self.tab_count], 0..) |tab, index| {
            if (tab.id == id) return @intCast(index);
        }
        return null;
    }
};

fn splitExtent(split: Split, rect: Rect) error{GeometryLimit}!u32 {
    const total = switch (split.axis) {
        .horizontal => rect.width,
        .vertical => rect.height,
    };
    if (total < 2) return error.GeometryLimit;
    const base = total / 2;
    const adjusted = @as(i64, base) + split.delta;
    return @intCast(std.math.clamp(adjusted, 1, @as(i64, total) - 1));
}

fn tabId(value: u32) TabId {
    return @fromBackingInt(@intCast(value));
}

fn paneId(value: u32) PaneId {
    return @fromBackingInt(@intCast(value));
}

test "initial host topology is one full focused pane" {
    var mux = Mux.init();
    var output: [max_panes_per_tab]Placement = undefined;
    const layout = try mux.activeLayout(.{ .width = 120, .height = 80 }, &output);
    try std.testing.expectEqual(@as(usize, 1), layout.len);
    try std.testing.expectEqual(paneId(1), layout[0].pane);
    try std.testing.expectEqual(Rect{ .x = 0, .y = 0, .width = 120, .height = 80 }, layout[0].rect);
    try std.testing.expect(layout[0].focused);
}

test "nested horizontal and vertical splits remain deterministic" {
    var mux = Mux.init();
    const right = try mux.splitFocused(.horizontal);
    const lower_right = try mux.splitFocused(.vertical);
    try std.testing.expectEqual(paneId(2), right);
    try std.testing.expectEqual(paneId(3), lower_right);
    var output: [max_panes_per_tab]Placement = undefined;
    const layout = try mux.activeLayout(.{ .width = 101, .height = 51 }, &output);
    try std.testing.expectEqual(@as(usize, 3), layout.len);
    try std.testing.expectEqual(Rect{ .x = 0, .y = 0, .width = 50, .height = 51 }, layout[0].rect);
    try std.testing.expectEqual(Rect{ .x = 50, .y = 0, .width = 51, .height = 25 }, layout[1].rect);
    try std.testing.expectEqual(Rect{ .x = 50, .y = 25, .width = 51, .height = 26 }, layout[2].rect);
    try std.testing.expect(layout[2].focused);
}

test "tabs own independent trees and stable identities" {
    var mux = Mux.init();
    const first_tab = mux.activeTab();
    const first_split = try mux.splitFocused(.horizontal);
    const created = try mux.createTab();
    try std.testing.expect(created.tab != first_tab);
    try std.testing.expect(created.pane != first_split);
    const second_split = try mux.splitFocused(.vertical);
    try std.testing.expect(@backingInt(second_split) != 0);
    try std.testing.expectEqual(@as(u8, 2), mux.tabCount());
    try std.testing.expectEqual(@as(u8, 4), mux.paneCount());
    try std.testing.expect(try mux.switchTab(first_tab));
    try std.testing.expectEqual(first_split, mux.focusedPane());
}

test "pane rect projects inactive tab geometry from stable identity" {
    var mux = Mux.init();
    const first = mux.focusedPane();
    const created = try mux.createTab();
    try std.testing.expectEqual(Rect{ .x = 0, .y = 0, .width = 91, .height = 37 }, try mux.paneRect(.{ .width = 91, .height = 37 }, first));
    try std.testing.expectEqual(Rect{ .x = 0, .y = 0, .width = 91, .height = 37 }, try mux.paneRect(.{ .width = 91, .height = 37 }, created.pane));
    try std.testing.expectError(error.StalePane, mux.paneRect(.{ .width = 91, .height = 37 }, paneId(999)));
}

test "next tab follows retained order and wraps" {
    var mux = Mux.init();
    const first = mux.activeTab();
    const second = try mux.createTab();
    try std.testing.expectEqual(second.tab, mux.activeTab());
    try std.testing.expect(mux.nextTab());
    try std.testing.expectEqual(first, mux.activeTab());
    try std.testing.expect(mux.nextTab());
    try std.testing.expectEqual(second.tab, mux.activeTab());

    var single = Mux.init();
    try std.testing.expect(!single.nextTab());
}

test "focus next follows projection order and wraps" {
    var mux = Mux.init();
    const right = try mux.splitFocused(.horizontal);
    try std.testing.expectEqual(right, mux.focusedPane());
    try std.testing.expectEqual(paneId(1), mux.focusNext());
    try std.testing.expectEqual(right, mux.focusNext());
    try std.testing.expectEqual(right, mux.focusedPane());

    var single = Mux.init();
    try std.testing.expectEqual(paneId(1), single.focusNext());
}

test "closing focused pane collapses its parent and chooses a survivor" {
    var mux = Mux.init();
    const right = try mux.splitFocused(.horizontal);
    const lower = try mux.splitFocused(.vertical);
    try std.testing.expectEqual(lower, try mux.closeFocused());
    try std.testing.expectEqual(right, mux.focusedPane());
    var output: [max_panes_per_tab]Placement = undefined;
    const layout = try mux.activeLayout(.{ .width = 100, .height = 40 }, &output);
    try std.testing.expectEqual(@as(usize, 2), layout.len);
    try std.testing.expectEqual(Rect{ .x = 50, .y = 0, .width = 50, .height = 40 }, layout[1].rect);
    try std.testing.expect(layout[1].focused);
}

test "tab and pane bounds fail without consuming identities" {
    var mux = Mux.init();
    var first_new: PaneId = undefined;
    for (1..max_panes_per_tab) |index| {
        const pane = try mux.splitFocused(if (index % 2 == 0) .horizontal else .vertical);
        if (index == 1) first_new = pane;
    }
    try std.testing.expectError(error.PaneLimit, mux.splitFocused(.horizontal));
    try std.testing.expectEqual(paneId(2), first_new);
    while (mux.tabCount() < max_tabs) {
        const created = try mux.createTab();
        try std.testing.expect(@backingInt(created.tab) != 0);
    }
    try std.testing.expectError(error.TabLimit, mux.createTab());
}

test "focused pane grow and shrink own exact split extent" {
    var mux = Mux.init();
    const right = try mux.splitFocused(.horizontal);
    try std.testing.expectEqual(right, mux.focusedPane());
    var output: [max_panes_per_tab]Placement = undefined;
    var placed = try mux.activeLayout(.{ .width = 94, .height = 39 }, &output);
    try std.testing.expectEqual(@as(u32, 47), placed[0].rect.width);
    try std.testing.expectEqual(@as(u32, 47), placed[1].rect.width);
    try std.testing.expect(try mux.resizeFocused(.{ .width = 94, .height = 39 }, 1));
    placed = try mux.activeLayout(.{ .width = 94, .height = 39 }, &output);
    try std.testing.expectEqual(@as(u32, 46), placed[0].rect.width);
    try std.testing.expectEqual(@as(u32, 48), placed[1].rect.width);
    try std.testing.expect(try mux.resizeFocused(.{ .width = 94, .height = 39 }, -2));
    placed = try mux.activeLayout(.{ .width = 94, .height = 39 }, &output);
    try std.testing.expectEqual(@as(u32, 48), placed[0].rect.width);
    try std.testing.expectEqual(@as(u32, 46), placed[1].rect.width);
}

test "projection failure never mutates topology" {
    var mux = Mux.init();
    const first_split = try mux.splitFocused(.horizontal);
    const second_split = try mux.splitFocused(.horizontal);
    try std.testing.expect(first_split != second_split);
    const before = mux;
    var output: [max_panes_per_tab]Placement = undefined;
    try std.testing.expectError(error.GeometryLimit, mux.activeLayout(.{ .width = 2, .height = 10 }, &output));
    try std.testing.expectEqualSlices(u8, std.mem.asBytes(&before), std.mem.asBytes(&mux));
}
