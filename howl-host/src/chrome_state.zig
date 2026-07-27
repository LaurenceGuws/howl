//! Owns Renderer tab/pane topology and derives bounded chrome input facts.

const std = @import("std");
const render = @import("howl_render");
const chrome = render.chrome;
/// Selects the horizontal or vertical rectangle boundary affected by a split
/// or divider movement.
pub const Orientation = enum { horizontal, vertical };

/// Bounds the ordered tabs retained by one Renderer.
pub const max_tabs: usize = 8;
/// Bounds visible panes in each tab.
pub const max_panes_per_tab: usize = 16;
/// Bounds identities retained across all live tabs.
pub const max_live_panes: usize = 64;
/// Bounds one copied tab or pane label.
pub const max_label_bytes: usize = 96;
/// Default caller-supplied tab-bar geometry for the host surface.
pub const default_tab_bar_height: u16 = 24;
/// Bounds the host's currently admitted scrollbar geometry.
pub const scrollbar_width: u16 = 8;
/// Bounds the host's currently admitted minimum scrollbar thumb.
pub const scrollbar_min_thumb: u16 = 16;

const TabId = chrome.TabId;
const PaneId = chrome.PaneId;

/// Caller-selected visual facts used only while deriving chrome primitives.
/// Topology owns identities and rectangles, never presentation policy.
pub const Appearance = struct {
    style: chrome.Style,
    tab_active_background: chrome.Color,
    tab_inactive_background: chrome.Color,
};

/// Reports invalid caller facts without partially changing the state.
pub const Error = error{
    Capacity,
    InvalidText,
    InvalidId,
    InvalidGeometry,
    InvalidScroll,
    ArithmeticOverflow,
};

const Pane = struct {
    id: PaneId,
    rect: chrome.Rect,
    basis_rect: chrome.Rect,
    focused: bool,
    label: [max_label_bytes]u8 = undefined,
    label_len: u8 = 0,
    scroll: ?chrome.Scroll = null,
    layer: chrome.PaneLayer = .tiled,
};

const Tab = struct {
    id: TabId,
    label: [max_label_bytes]u8 = undefined,
    label_len: u8 = 0,
    panes: [max_panes_per_tab]Pane = undefined,
    pane_count: u8 = 0,
};

/// Owns stable tab/pane identity and derives current tiled geometry directly
/// from pane rectangles. Renderer owns this lifecycle state; the Window never
/// observes it. It performs no allocation and retains no presentation policy.
pub const Topology = struct {
    tabs: [max_tabs]Tab = undefined,
    tab_count: u8 = 0,
    active_tab: u8 = 0,
    next_tab_id: u64 = 1,
    next_pane_id: u64 = 1,
    live_panes: u16 = 0,
    surface: chrome.Size,
    basis_surface: chrome.Size,
    tab_bar_height: u16,

    fn contentTop(self: *const Topology) u16 {
        return @min(self.tab_bar_height, self.surface.height - 1);
    }

    /// Creates one tab with one focused blank pane below `tab_bar_height`.
    /// The bar height is a caller-supplied geometry fact and must leave room
    /// for a positive pane area.
    pub fn init(surface: chrome.Size, tab_bar_height: u16) Error!Topology {
        if (surface.width == 0 or surface.height == 0) return error.InvalidGeometry;
        var result = Topology{ .surface = surface, .basis_surface = surface, .tab_bar_height = tab_bar_height };
        const first_tab = try result.createTabInternal("main", false);
        if (@backingInt(first_tab) == 0) return error.InvalidId;
        try validateLayout(&result);
        return result;
    }

    /// Returns the number of stable tabs retained by this state.
    pub fn tabCount(self: *const Topology) usize {
        return self.tab_count;
    }

    /// Returns the number of panes in one tab, or zero for an invalid index.
    pub fn paneCount(self: *const Topology, tab_index: usize) usize {
        if (tab_index >= self.tab_count) return 0;
        return self.tabs[tab_index].pane_count;
    }

    /// Returns the stable tab identity at an ordered index.
    pub fn tabId(self: *const Topology, tab_index: usize) ?TabId {
        if (tab_index >= self.tab_count) return null;
        return self.tabs[tab_index].id;
    }

    /// Returns the stable pane identity at an ordered tab index.
    pub fn paneId(self: *const Topology, tab_index: usize, pane_index: usize) ?PaneId {
        if (tab_index >= self.tab_count or pane_index >= self.tabs[tab_index].pane_count) return null;
        return self.tabs[tab_index].panes[pane_index].id;
    }

    /// Returns the active tab's stable identity.
    pub fn activeTabId(self: *const Topology) TabId {
        return self.tabs[self.active_tab].id;
    }

    /// Returns the active tab's ordered index.
    pub fn activeTabIndex(self: *const Topology) usize {
        return self.active_tab;
    }

    /// Returns the active tab's exact focused pane identity.
    pub fn focusedPaneId(self: *const Topology) PaneId {
        const tab = &self.tabs[self.active_tab];
        for (tab.panes[0..tab.pane_count]) |pane| if (pane.focused) return pane.id;
        @panic("validated topology lost focused pane");
    }

    /// Returns one retained pane's composition layer.
    pub fn paneLayer(self: *const Topology, id: PaneId) ?chrome.PaneLayer {
        const location = self.findPane(id) orelse return null;
        return self.tabs[location.tab].panes[location.pane].layer;
    }

    /// Copies one retained pane rectangle without exposing topology storage.
    pub fn paneRect(self: *const Topology, id: PaneId) ?chrome.Rect {
        const location = self.findPane(id) orelse return null;
        return self.tabs[location.tab].panes[location.pane].rect;
    }

    /// Reports whether one retained floating pane is already topmost in its
    /// tab's deterministic composition order.
    pub fn floatingPaneIsTopmost(self: *const Topology, id: PaneId) bool {
        const location = self.findPane(id) orelse return false;
        const tab = &self.tabs[location.tab];
        if (tab.panes[location.pane].layer != .floating) return false;
        for (tab.panes[location.pane + 1 .. tab.pane_count]) |pane| {
            if (pane.layer == .floating) return false;
        }
        return true;
    }

    /// Checks positive, non-overlapping, complete coverage and one focus fact
    /// for every retained tab. This is a deterministic owner invariant proof.
    pub fn validate(self: *const Topology) Error!void {
        try validateLayout(self);
    }

    /// Creates and activates an empty blank tab with one pane.
    pub fn createTab(self: *Topology, label: []const u8) Error!TabId {
        var candidate = self.*;
        const id = try candidate.createTabInternal(label, true);
        candidate.syncBasis();
        try validateLayout(&candidate);
        self.* = candidate;
        return id;
    }

    /// Closes one tab and activates its nearest surviving neighbor.
    pub fn closeTab(self: *Topology, id: TabId) Error!void {
        var candidate = self.*;
        try candidate.closeTabInPlace(id);
        candidate.syncBasis();
        try validateLayout(&candidate);
        self.* = candidate;
    }

    fn closeTabInPlace(self: *Topology, id: TabId) Error!void {
        const index = self.findTab(id) orelse return error.InvalidId;
        const removed = self.tabs[index].pane_count;
        var cursor = index;
        while (cursor + 1 < self.tab_count) : (cursor += 1) self.tabs[cursor] = self.tabs[cursor + 1];
        self.tab_count -= 1;
        self.live_panes -= removed;
        if (self.tab_count == 0) {
            const replacement = try self.createTabInternal("main", false);
            if (@backingInt(replacement) == 0) return error.InvalidId;
            self.active_tab = 0;
        } else if (self.active_tab >= self.tab_count) {
            self.active_tab = self.tab_count - 1;
        } else if (index < self.active_tab) {
            self.active_tab -= 1;
        }
    }

    /// Renames one tab using copied validated UTF-8 storage.
    pub fn renameTab(self: *Topology, id: TabId, label: []const u8) Error!void {
        const index = self.findTab(id) orelse return error.InvalidId;
        try validateLabel(label);
        copyLabel(&self.tabs[index].label, &self.tabs[index].label_len, label);
    }

    /// Switches the active tab without changing stable identities.
    pub fn switchTab(self: *Topology, id: TabId) Error!void {
        self.active_tab = @intCast(self.findTab(id) orelse return error.InvalidId);
    }

    /// Renames one retained pane using copied validated UTF-8 storage.
    pub fn renamePane(self: *Topology, id: PaneId, label: []const u8) Error!void {
        const location = self.findPane(id) orelse return error.InvalidId;
        try validateLabel(label);
        copyLabel(&self.tabs[location.tab].panes[location.pane].label, &self.tabs[location.tab].panes[location.pane].label_len, label);
    }

    /// Replaces one pane's scroll facts only when the tuple and current pane
    /// rectangle can produce the host's bounded scrollbar.
    pub fn setPaneScroll(self: *Topology, id: PaneId, scroll: ?chrome.Scroll) Error!void {
        const location = self.findPane(id) orelse return error.InvalidId;
        if (scroll) |value| try validatePaneScroll(value, self.tabs[location.tab].panes[location.pane].rect);
        self.tabs[location.tab].panes[location.pane].scroll = scroll;
    }

    /// Creates one focused floating pane above every current pane in the active
    /// tab. Candidate geometry and identity issuance commit together.
    pub fn createFloatingPane(self: *Topology, rect: chrome.Rect, label: []const u8) Error!PaneId {
        var candidate = self.*;
        const tab = &candidate.tabs[candidate.active_tab];
        if (candidate.live_panes >= max_live_panes or tab.pane_count >= max_panes_per_tab) return error.Capacity;
        try validateLabel(label);
        try validateFloatingRect(&candidate, rect);
        const id = try candidate.takePaneId();
        for (tab.panes[0..tab.pane_count]) |*pane| pane.focused = false;
        var pane = Pane{ .id = id, .rect = rect, .basis_rect = rect, .focused = true, .layer = .floating };
        copyLabel(&pane.label, &pane.label_len, label);
        tab.panes[tab.pane_count] = pane;
        tab.pane_count += 1;
        candidate.live_panes += 1;
        candidate.syncBasis();
        try validateLayout(&candidate);
        self.* = candidate;
        return id;
    }

    /// Replaces one floating pane rectangle transactionally.
    pub fn setFloatingRect(self: *Topology, id: PaneId, rect: chrome.Rect) Error!void {
        var candidate = self.*;
        const location = candidate.findPane(id) orelse return error.InvalidId;
        if (candidate.tabs[location.tab].panes[location.pane].layer != .floating) return error.InvalidId;
        try validateFloatingRect(&candidate, rect);
        candidate.tabs[location.tab].panes[location.pane].rect = rect;
        candidate.syncBasis();
        try validateLayout(&candidate);
        self.* = candidate;
    }

    /// Focuses and raises one floating pane to the top of its caller-owned order.
    pub fn raiseFloatingPane(self: *Topology, id: PaneId) Error!void {
        var candidate = self.*;
        const location = candidate.findPane(id) orelse return error.InvalidId;
        const tab = &candidate.tabs[location.tab];
        if (tab.panes[location.pane].layer != .floating) return error.InvalidId;
        const selected = tab.panes[location.pane];
        var index = location.pane;
        while (index + 1 < tab.pane_count) : (index += 1) tab.panes[index] = tab.panes[index + 1];
        tab.panes[tab.pane_count - 1] = selected;
        for (tab.panes[0..tab.pane_count]) |*pane| pane.focused = pane.id == id;
        try validateLayout(&candidate);
        self.* = candidate;
    }

    /// Focuses an exact retained pane without changing its geometry or order.
    pub fn focusPane(self: *Topology, id: PaneId) Error!void {
        const location = self.findPane(id) orelse return error.InvalidId;
        const tab = &self.tabs[location.tab];
        for (tab.panes[0..tab.pane_count]) |*pane| pane.focused = pane.id == id;
    }

    /// Reorders one tab in the visible ordered list.
    pub fn reorderTab(self: *Topology, id: TabId, destination: usize) Error!void {
        const source = self.findTab(id) orelse return error.InvalidId;
        if (destination >= self.tab_count) return error.InvalidId;
        if (source == destination) return;
        const active_id = self.tabs[self.active_tab].id;
        const saved = self.tabs[source];
        if (source < destination) {
            var index = source;
            while (index < destination) : (index += 1) self.tabs[index] = self.tabs[index + 1];
        } else {
            var index = source;
            while (index > destination) : (index -= 1) self.tabs[index] = self.tabs[index - 1];
        }
        self.tabs[destination] = saved;
        self.active_tab = @intCast(self.findTab(active_id).?);
        try validateLayout(self);
    }

    /// Applies a newer surface size while retaining stable identities and
    /// clipping each current pane rectangle to the bounded surface.
    pub fn resizeSurface(self: *Topology, surface: chrome.Size) Error!void {
        if (surface.width == 0 or surface.height == 0) return error.InvalidGeometry;
        var candidate = self.*;
        const old_width = self.basis_surface.width;
        const old_top = @min(self.tab_bar_height, self.basis_surface.height - 1);
        const new_top = @min(self.tab_bar_height, surface.height - 1);
        const old_content_height = self.basis_surface.height - old_top;
        const new_content_height = surface.height - new_top;
        candidate.surface = surface;
        for (candidate.tabs[0..candidate.tab_count]) |*tab| {
            for (tab.panes[0..tab.pane_count]) |*pane| {
                const basis = pane.basis_rect;
                const right = std.math.add(i64, basis.x, basis.width) catch return error.ArithmeticOverflow;
                const bottom = std.math.add(i64, basis.y, basis.height) catch return error.ArithmeticOverflow;
                const new_x = try scaleEdge(basis.x, old_width, surface.width);
                const new_right = try scaleEdge(right, old_width, surface.width);
                const relative_y = std.math.sub(i64, basis.y, old_top) catch return error.InvalidGeometry;
                const relative_bottom = std.math.sub(i64, bottom, old_top) catch return error.InvalidGeometry;
                const new_y = @as(i64, new_top) + try scaleEdge(relative_y, old_content_height, new_content_height);
                const new_bottom = @as(i64, new_top) + try scaleEdge(relative_bottom, old_content_height, new_content_height);
                if (new_right <= new_x or new_bottom <= new_y) return error.InvalidGeometry;
                pane.rect = .{ .x = @intCast(new_x), .y = @intCast(new_y), .width = @intCast(new_right - new_x), .height = @intCast(new_bottom - new_y) };
            }
        }
        try validateLayout(&candidate);
        self.* = candidate;
    }

    /// Splits one pane into two tiled rectangles and returns the new identity.
    pub fn split(self: *Topology, pane_id: PaneId, orientation: Orientation) Error!PaneId {
        const original = self.*;
        const location = self.findPane(pane_id) orelse return error.InvalidId;
        if (self.live_panes >= max_live_panes) return error.Capacity;
        const tab = &self.tabs[location.tab];
        if (tab.pane_count >= max_panes_per_tab) return error.Capacity;
        const source = tab.panes[location.pane];
        if (source.layer != .tiled) return error.InvalidGeometry;
        const first_width = if (orientation == .vertical) source.rect.width / 2 else source.rect.width;
        const first_height = if (orientation == .horizontal) source.rect.height / 2 else source.rect.height;
        if (first_width == 0 or first_height == 0) return error.InvalidGeometry;
        const second_width = if (orientation == .vertical) source.rect.width - first_width else source.rect.width;
        const second_height = if (orientation == .horizontal) source.rect.height - first_height else source.rect.height;
        if (second_width == 0 or second_height == 0) return error.InvalidGeometry;
        var first = source;
        first.rect.width = first_width;
        first.rect.height = first_height;
        var second = source;
        second.id = try self.takePaneId();
        second.focused = true;
        second.rect = .{
            .x = source.rect.x + if (orientation == .vertical) @as(i32, @intCast(first_width)) else 0,
            .y = source.rect.y + if (orientation == .horizontal) @as(i32, @intCast(first_height)) else 0,
            .width = second_width,
            .height = second_height,
        };
        first.focused = false;
        for (tab.panes[0..tab.pane_count]) |*pane| pane.focused = false;
        tab.panes[location.pane] = first;
        var index = tab.pane_count;
        while (index > location.pane + 1) : (index -= 1) tab.panes[index] = tab.panes[index - 1];
        tab.panes[location.pane + 1] = second;
        tab.pane_count += 1;
        self.live_panes += 1;
        validateLayout(self) catch |failure| {
            self.* = original;
            return failure;
        };
        self.syncBasis();
        return second.id;
    }

    /// Focuses the nearest pane in a cardinal direction by current geometry.
    pub fn focusDirection(self: *Topology, direction: enum { left, right, up, down }) Error!PaneId {
        const tab = &self.tabs[self.active_tab];
        var focused: usize = 0;
        for (tab.panes[0..tab.pane_count], 0..) |pane, index| {
            if (pane.focused) focused = index;
        }
        const source = tab.panes[focused].rect;
        var candidate: ?usize = null;
        var best_primary: i64 = std.math.maxInt(i64);
        var best_secondary: i64 = std.math.maxInt(i64);
        for (tab.panes[0..tab.pane_count], 0..) |pane, index| {
            if (index == focused) continue;
            const in_direction = switch (direction) {
                .left => @as(i64, pane.rect.x) + pane.rect.width <= source.x,
                .right => pane.rect.x >= @as(i64, source.x) + source.width,
                .up => @as(i64, pane.rect.y) + pane.rect.height <= source.y,
                .down => pane.rect.y >= @as(i64, source.y) + source.height,
            };
            if (!in_direction) continue;
            const perpendicular_overlap = if (direction == .left or direction == .right)
                pane.rect.y < source.y + source.height and source.y < pane.rect.y + pane.rect.height
            else
                pane.rect.x < source.x + source.width and source.x < pane.rect.x + pane.rect.width;
            if (!perpendicular_overlap) continue;
            const primary = switch (direction) {
                .left => @as(i64, source.x) - (pane.rect.x + pane.rect.width),
                .right => @as(i64, pane.rect.x) - (source.x + source.width),
                .up => @as(i64, source.y) - (pane.rect.y + pane.rect.height),
                .down => @as(i64, pane.rect.y) - (source.y + source.height),
            };
            const source_center = if (direction == .left or direction == .right) @as(i64, source.y) * 2 + source.height else @as(i64, source.x) * 2 + source.width;
            const candidate_center = if (direction == .left or direction == .right) @as(i64, pane.rect.y) * 2 + pane.rect.height else @as(i64, pane.rect.x) * 2 + pane.rect.width;
            const secondary: i64 = @intCast(@abs(source_center - candidate_center));
            const best_id = if (candidate) |best| @backingInt(tab.panes[best].id) else std.math.maxInt(u64);
            if (primary < best_primary or
                (primary == best_primary and secondary < best_secondary) or
                (primary == best_primary and secondary == best_secondary and @backingInt(pane.id) < best_id))
            {
                candidate = index;
                best_primary = primary;
                best_secondary = secondary;
            }
        }
        const selected = candidate orelse return tab.panes[focused].id;
        for (tab.panes[0..tab.pane_count]) |*pane| pane.focused = false;
        tab.panes[selected].focused = true;
        return tab.panes[selected].id;
    }

    /// Resizes one pane edge while preserving positive rectangles.
    pub fn resizeDivider(self: *Topology, pane_id: PaneId, delta: i32, orientation: Orientation) Error!void {
        var candidate = self.*;
        const location = candidate.findPane(pane_id) orelse return error.InvalidId;
        const tab = &candidate.tabs[location.tab];
        const source = tab.panes[location.pane].rect;
        if (tab.panes[location.pane].layer != .tiled) return error.InvalidGeometry;
        var edge: i64 = if (orientation == .vertical) @as(i64, source.x) + source.width else @as(i64, source.y) + source.height;
        var movement: i64 = delta;
        if (!hasOpposite(tab, location.pane, orientation, edge, source)) {
            edge = if (orientation == .vertical) source.x else source.y;
            // Delta is the requested physical divider movement.  The same
            // sign applies whether the divider is the pane's trailing or
            // leading edge; this keeps Up/Down and Left/Right opposite.
            movement = @as(i64, delta);
        }
        var span_start: i64 = if (orientation == .vertical) source.y else source.x;
        var span_end = span_start + if (orientation == .vertical) source.height else source.width;
        var expanded = true;
        while (expanded) {
            expanded = false;
            for (tab.panes[0..tab.pane_count]) |pane| {
                if (pane.layer == .floating) continue;
                if (!touchesEdge(pane.rect, orientation, edge)) continue;
                const start: i64 = if (orientation == .vertical) pane.rect.y else pane.rect.x;
                const finish = start + if (orientation == .vertical) pane.rect.height else pane.rect.width;
                if (finish < span_start or start > span_end) continue;
                const next_start = @min(span_start, start);
                const next_end = @max(span_end, finish);
                expanded = expanded or next_start != span_start or next_end != span_end;
                span_start = next_start;
                span_end = next_end;
            }
        }
        var left_count: usize = 0;
        var right_count: usize = 0;
        for (tab.panes[0..tab.pane_count]) |*pane| {
            if (pane.layer == .floating) continue;
            const start: i64 = if (orientation == .vertical) pane.rect.y else pane.rect.x;
            const finish = start + if (orientation == .vertical) pane.rect.height else pane.rect.width;
            if (start < span_start or finish > span_end) continue;
            const before = if (orientation == .vertical) @as(i64, pane.rect.x) + pane.rect.width else @as(i64, pane.rect.y) + pane.rect.height;
            const after = if (orientation == .vertical) @as(i64, pane.rect.x) else @as(i64, pane.rect.y);
            if (before == edge) {
                const extent = std.math.add(i64, if (orientation == .vertical) pane.rect.width else pane.rect.height, movement) catch return error.ArithmeticOverflow;
                if (extent <= 0 or extent > std.math.maxInt(u16)) return error.InvalidGeometry;
                if (orientation == .vertical) pane.rect.width = @intCast(extent) else pane.rect.height = @intCast(extent);
                left_count += 1;
            } else if (after == edge) {
                const extent = std.math.sub(i64, if (orientation == .vertical) pane.rect.width else pane.rect.height, movement) catch return error.ArithmeticOverflow;
                if (extent <= 0 or extent > std.math.maxInt(u16)) return error.InvalidGeometry;
                if (orientation == .vertical) {
                    pane.rect.x = @intCast(@as(i64, pane.rect.x) + movement);
                    pane.rect.width = @intCast(extent);
                } else {
                    pane.rect.y = @intCast(@as(i64, pane.rect.y) + movement);
                    pane.rect.height = @intCast(extent);
                }
                right_count += 1;
            }
        }
        if (left_count == 0 or right_count == 0) return error.InvalidGeometry;
        try validateLayout(&candidate);
        candidate.syncBasis();
        self.* = candidate;
    }

    /// Closes a pane, preserving another focused identity when the removed pane
    /// was unfocused and choosing a deterministic neighbor only when needed.
    pub fn closePane(self: *Topology, pane_id: PaneId) Error!void {
        const location = self.findPane(pane_id) orelse return error.InvalidId;
        if (self.tabs[location.tab].pane_count == 1) return self.closeTab(self.tabs[location.tab].id);
        var candidate = self.*;
        const tab = &candidate.tabs[location.tab];
        const removed = tab.panes[location.pane];
        if (removed.layer == .tiled and !fillRemovedRectangle(tab, location.pane, removed)) return error.InvalidGeometry;
        var index = location.pane;
        while (index + 1 < tab.pane_count) : (index += 1) tab.panes[index] = tab.panes[index + 1];
        tab.pane_count -= 1;
        candidate.live_panes -= 1;
        if (removed.focused) {
            for (tab.panes[0..tab.pane_count]) |*pane| pane.focused = false;
            tab.panes[@min(location.pane, tab.pane_count - 1)].focused = true;
        }
        candidate.syncBasis();
        try validateLayout(&candidate);
        self.* = candidate;
    }

    /// Projects active-pane chrome and all tab labels into caller storage.
    pub fn project(self: *const Topology, appearance: Appearance, selections: []const chrome.Selection, primitives: []chrome.Primitive, text: []u8) chrome.Error!chrome.Output {
        var tabs: [max_tabs]chrome.Tab = undefined;
        for (self.tabs[0..self.tab_count], 0..) |*tab, index| tabs[index] = .{ .id = tab.id, .label = tab.label[0..tab.label_len], .active = index == self.active_tab };
        var panes: [max_panes_per_tab]chrome.Pane = undefined;
        const active = &self.tabs[self.active_tab];
        for (active.panes[0..active.pane_count], 0..) |*pane, index| {
            panes[index] = .{
                .id = pane.id,
                .rect = pane.rect,
                .label = pane.label[0..pane.label_len],
                .focused = pane.focused,
                .scroll = pane.scroll,
                .layer = pane.layer,
            };
        }
        return chrome.project(.{
            .surface = self.surface,
            .tab_bar_height = self.contentTop(),
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

    /// Resolves the topmost visible tab or pane identity through Render's
    /// caller-neutral geometry contract.
    pub fn hitTest(self: *const Topology, appearance: Appearance, point: chrome.Point) chrome.Error!?chrome.Hit {
        var tabs: [max_tabs]chrome.Tab = undefined;
        for (self.tabs[0..self.tab_count], 0..) |*tab, index| tabs[index] = .{ .id = tab.id, .label = tab.label[0..tab.label_len], .active = index == self.active_tab };
        var panes: [max_panes_per_tab]chrome.Pane = undefined;
        const active = &self.tabs[self.active_tab];
        for (active.panes[0..active.pane_count], 0..) |*pane, index| panes[index] = .{
            .id = pane.id,
            .rect = pane.rect,
            .label = pane.label[0..pane.label_len],
            .focused = pane.focused,
            .scroll = pane.scroll,
            .layer = pane.layer,
        };
        return chrome.hitTest(.{
            .surface = self.surface,
            .tab_bar_height = self.contentTop(),
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

    fn createTabInternal(self: *Topology, label: []const u8, activate: bool) Error!TabId {
        if (self.tab_count >= max_tabs or self.live_panes >= max_live_panes) return error.Capacity;
        try validateLabel(label);
        if (self.next_tab_id == 0 or self.next_tab_id == std.math.maxInt(u64) or
            self.next_pane_id == 0 or self.next_pane_id == std.math.maxInt(u64))
            return error.Capacity;
        const id: TabId = @fromBackingInt(self.next_tab_id);
        const pane_id: PaneId = @fromBackingInt(self.next_pane_id);
        var tab = Tab{ .id = id, .pane_count = 1 };
        copyLabel(&tab.label, &tab.label_len, label);
        const rect = chrome.Rect{ .x = 0, .y = self.contentTop(), .width = self.surface.width, .height = self.surface.height - self.contentTop() };
        tab.panes[0] = .{ .id = pane_id, .rect = rect, .basis_rect = rect, .focused = true };
        self.tabs[self.tab_count] = tab;
        if (activate) self.active_tab = self.tab_count;
        self.tab_count += 1;
        self.live_panes += 1;
        self.next_tab_id += 1;
        self.next_pane_id += 1;
        return id;
    }

    fn takePaneId(self: *Topology) Error!PaneId {
        if (self.next_pane_id == 0 or self.next_pane_id == std.math.maxInt(u64)) return error.Capacity;
        const value = self.next_pane_id;
        self.next_pane_id += 1;
        return @fromBackingInt(@intCast(value));
    }

    fn syncBasis(self: *Topology) void {
        self.basis_surface = self.surface;
        for (self.tabs[0..self.tab_count]) |*tab| {
            for (tab.panes[0..tab.pane_count]) |*pane| {
                pane.basis_rect = pane.rect;
            }
        }
    }

    fn findTab(self: *const Topology, id: TabId) ?usize {
        for (self.tabs[0..self.tab_count], 0..) |tab, index| if (tab.id == id) return index;
        return null;
    }

    const Location = struct { tab: usize, pane: usize };
    fn findPane(self: *const Topology, id: PaneId) ?Location {
        for (self.tabs[0..self.tab_count], 0..) |tab, tab_index| for (tab.panes[0..tab.pane_count], 0..) |pane, pane_index| if (pane.id == id) return .{ .tab = tab_index, .pane = pane_index };
        return null;
    }
};

fn scaleEdge(value: i64, old_extent: u16, new_extent: u16) Error!i64 {
    if (value < 0 or old_extent == 0) return error.InvalidGeometry;
    const product = std.math.mul(u64, @intCast(value), new_extent) catch return error.ArithmeticOverflow;
    return @intCast(product / old_extent);
}

fn hasOpposite(tab: *const Tab, source_index: usize, orientation: Orientation, edge: i64, source: chrome.Rect) bool {
    for (tab.panes[0..tab.pane_count], 0..) |pane, index| {
        if (index == source_index) continue;
        if (pane.layer == .floating) continue;
        const after = if (orientation == .vertical) @as(i64, pane.rect.x) else @as(i64, pane.rect.y);
        const start = if (orientation == .vertical) @as(i64, pane.rect.y) else @as(i64, pane.rect.x);
        const finish = start + if (orientation == .vertical) pane.rect.height else pane.rect.width;
        const source_start = if (orientation == .vertical) @as(i64, source.y) else @as(i64, source.x);
        const source_finish = source_start + if (orientation == .vertical) source.height else source.width;
        if (after == edge and start < source_finish and source_start < finish) return true;
    }
    return false;
}

fn touchesEdge(rect: chrome.Rect, orientation: Orientation, edge: i64) bool {
    const before = if (orientation == .vertical) @as(i64, rect.x) + rect.width else @as(i64, rect.y) + rect.height;
    const after = if (orientation == .vertical) @as(i64, rect.x) else @as(i64, rect.y);
    return before == edge or after == edge;
}

fn validateLayout(self: *const Topology) Error!void {
    if (self.tab_count == 0 or self.tab_count > max_tabs or self.active_tab >= self.tab_count) return error.InvalidGeometry;
    var counted_panes: u16 = 0;
    for (self.tabs[0..self.tab_count]) |tab| {
        if (@backingInt(tab.id) == 0) return error.InvalidId;
        if (tab.pane_count == 0) return error.InvalidGeometry;
        counted_panes = std.math.add(u16, counted_panes, tab.pane_count) catch return error.ArithmeticOverflow;
        var tiled_area: u64 = 0;
        var focused: u8 = 0;
        var floating_seen = false;
        for (tab.panes[0..tab.pane_count], 0..) |pane, index| {
            if (@backingInt(pane.id) == 0) return error.InvalidId;
            if (pane.rect.x < 0 or pane.rect.y < self.contentTop() or pane.rect.width == 0 or pane.rect.height == 0) return error.InvalidGeometry;
            if (pane.scroll) |scroll| try validatePaneScroll(scroll, pane.rect);
            const right = std.math.add(i64, pane.rect.x, pane.rect.width) catch return error.ArithmeticOverflow;
            const bottom = std.math.add(i64, pane.rect.y, pane.rect.height) catch return error.ArithmeticOverflow;
            if (right > self.surface.width or bottom > self.surface.height) return error.InvalidGeometry;
            if (pane.layer == .floating) {
                floating_seen = true;
            } else {
                if (floating_seen) return error.InvalidGeometry;
                tiled_area = std.math.add(u64, tiled_area, @as(u64, pane.rect.width) * pane.rect.height) catch return error.ArithmeticOverflow;
            }
            if (pane.focused) focused += 1;
            for (tab.panes[0..index]) |other| {
                if (pane.layer == .floating or other.layer == .floating) continue;
                const overlap = pane.rect.x < other.rect.x + other.rect.width and other.rect.x < pane.rect.x + pane.rect.width and pane.rect.y < other.rect.y + other.rect.height and other.rect.y < pane.rect.y + pane.rect.height;
                if (overlap) return error.InvalidGeometry;
            }
        }
        if (tiled_area != @as(u64, self.surface.width) * (self.surface.height - self.contentTop()) or focused != 1) return error.InvalidGeometry;
    }
    if (counted_panes != self.live_panes or counted_panes > max_live_panes) return error.InvalidGeometry;
    for (self.tabs[0..self.tab_count], 0..) |tab, tab_index| {
        for (self.tabs[0..tab_index]) |other| if (tab.id == other.id) return error.InvalidId;
        for (tab.panes[0..tab.pane_count], 0..) |pane, pane_index| {
            for (self.tabs[0..tab_index]) |other_tab|
                for (other_tab.panes[0..other_tab.pane_count]) |other|
                    if (pane.id == other.id) return error.InvalidId;
            for (tab.panes[0..pane_index]) |other| if (pane.id == other.id) return error.InvalidId;
        }
    }
}

fn validateFloatingRect(self: *const Topology, rect: chrome.Rect) Error!void {
    if (rect.width == 0 or rect.height == 0 or rect.x < 0 or rect.y < self.contentTop()) return error.InvalidGeometry;
    const right = std.math.add(i64, rect.x, rect.width) catch return error.ArithmeticOverflow;
    const bottom = std.math.add(i64, rect.y, rect.height) catch return error.ArithmeticOverflow;
    if (right > self.surface.width or bottom > self.surface.height) return error.InvalidGeometry;
}

fn validatePaneScroll(scroll: chrome.Scroll, rect: chrome.Rect) Error!void {
    if (scroll.visible == 0 or scroll.visible > scroll.total or scroll.start > scroll.total - scroll.visible) return error.InvalidScroll;
    if (scroll.visible < scroll.total and (rect.width < scrollbar_width or rect.height < scrollbar_min_thumb)) return error.InvalidGeometry;
}

fn fillRemovedRectangle(tab: *Tab, removed_index: usize, removed: Pane) bool {
    const Side = enum { right, left, bottom, top };
    for ([_]Side{ .right, .left, .bottom, .top }) |side| {
        var covered: u32 = 0;
        for (tab.panes[0..tab.pane_count], 0..) |other, index| {
            if (index == removed_index) continue;
            if (other.layer == .floating) continue;
            const adjacent = switch (side) {
                .right => other.rect.x == removed.rect.x + removed.rect.width,
                .left => other.rect.x + other.rect.width == removed.rect.x,
                .bottom => other.rect.y == removed.rect.y + removed.rect.height,
                .top => other.rect.y + other.rect.height == removed.rect.y,
            };
            if (!adjacent) continue;
            const contained = switch (side) {
                .right, .left => other.rect.y >= removed.rect.y and
                    other.rect.y + other.rect.height <= removed.rect.y + removed.rect.height,
                .bottom, .top => other.rect.x >= removed.rect.x and
                    other.rect.x + other.rect.width <= removed.rect.x + removed.rect.width,
            };
            if (!contained) continue;
            const start = switch (side) {
                .right, .left => @max(other.rect.y, removed.rect.y),
                .bottom, .top => @max(other.rect.x, removed.rect.x),
            };
            const finish = switch (side) {
                .right, .left => @min(other.rect.y + other.rect.height, removed.rect.y + removed.rect.height),
                .bottom, .top => @min(other.rect.x + other.rect.width, removed.rect.x + removed.rect.width),
            };
            if (finish > start) covered += @intCast(finish - start);
        }
        const required: u32 = if (side == .right or side == .left) removed.rect.height else removed.rect.width;
        if (covered != required) continue;
        for (tab.panes[0..tab.pane_count], 0..) |*other, index| {
            if (index == removed_index) continue;
            if (other.layer == .floating) continue;
            const contained = switch (side) {
                .right, .left => other.rect.y >= removed.rect.y and
                    other.rect.y + other.rect.height <= removed.rect.y + removed.rect.height,
                .bottom, .top => other.rect.x >= removed.rect.x and
                    other.rect.x + other.rect.width <= removed.rect.x + removed.rect.width,
            };
            if (!contained) continue;
            switch (side) {
                .right => if (other.rect.x == removed.rect.x + removed.rect.width) {
                    other.rect.x = removed.rect.x;
                    other.rect.width += removed.rect.width;
                },
                .left => if (other.rect.x + other.rect.width == removed.rect.x) {
                    other.rect.width += removed.rect.width;
                },
                .bottom => if (other.rect.y == removed.rect.y + removed.rect.height) {
                    other.rect.y = removed.rect.y;
                    other.rect.height += removed.rect.height;
                },
                .top => if (other.rect.y + other.rect.height == removed.rect.y) {
                    other.rect.height += removed.rect.height;
                },
            }
        }
        return true;
    }
    return false;
}

fn copyLabel(storage: *[max_label_bytes]u8, length: *u8, source: []const u8) void {
    @memcpy(storage[0..source.len], source);
    length.* = @intCast(source.len);
}

fn validateLabel(source: []const u8) Error!void {
    if (source.len > max_label_bytes or !std.unicode.utf8ValidateSlice(source)) return error.InvalidText;
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

test "chrome state preserves identities and projects deterministic output" {
    var state = try Topology.init(.{ .width = 640, .height = 480 }, 24);
    try std.testing.expectEqual(@as(i32, 24), state.tabs[0].panes[0].rect.y);
    const first_tab = state.tabId(0).?;
    const first_pane = state.paneId(0, 0).?;
    const second_pane = try state.split(first_pane, .vertical);
    try std.testing.expectEqual(first_tab, state.tabId(0).?);
    try std.testing.expectEqual(first_pane, state.paneId(0, 0).?);
    try std.testing.expectEqual(second_pane, state.paneId(0, 1).?);
    const second_tab = try state.createTab("第二");
    const second_tab_pane = state.paneId(1, 0).?;
    try state.renamePane(second_tab_pane, "pane");
    try state.setPaneScroll(second_tab_pane, .{ .visible = 10, .total = 40, .start = 5 });
    try state.switchTab(second_tab);
    try std.testing.expectEqual(second_tab, state.activeTabId());
    var primitives: [128]chrome.Primitive = undefined;
    var text: [1024]u8 = undefined;
    const output = try state.project(testAppearance(), &.{}, &primitives, &text);
    try std.testing.expect(output.primitives.len > 0);
    try std.testing.expect(std.mem.containsAtLeast(u8, output.text, 1, "第二"));
    try std.testing.expect(std.mem.endsWith(u8, output.text, "pane"));
    try state.switchTab(first_tab);
    try std.testing.expectEqual(second_pane, try state.focusDirection(.right));
    try state.resizeDivider(second_pane, -1, .vertical);
    try state.reorderTab(first_tab, 0);
    try state.closeTab(second_tab);
    try std.testing.expectEqual(first_tab, state.activeTabId());
    try state.validate();
    try state.closePane(first_pane);
    try state.validate();
}

test "chrome state keeps bounded tab and pane capacities" {
    var state = try Topology.init(.{ .width = 640, .height = 480 }, 24);
    while (state.tabCount() < max_tabs) {
        const created_tab = try state.createTab("tab");
        try std.testing.expect(@backingInt(created_tab) != 0);
    }
    try std.testing.expectError(error.Capacity, state.createTab("overflow"));
    try state.switchTab(state.tabId(0).?);
    try state.resizeSurface(.{ .width = 321, .height = 241 });
    var pane = state.paneId(0, 0).?;
    var split_index: usize = 0;
    while (state.paneCount(0) < max_panes_per_tab) : (split_index += 1) {
        pane = try state.split(pane, if (split_index % 2 == 0) .vertical else .horizontal);
    }
    try std.testing.expectEqual(max_panes_per_tab, state.paneCount(0));
    try std.testing.expectError(error.Capacity, state.split(pane, .vertical));
    var total_panes: usize = 0;
    for (0..max_tabs) |tab_index| total_panes += state.paneCount(tab_index);
    for (0..max_tabs) |tab_index| {
        var tab_pane = state.paneId(tab_index, 0).?;
        var tab_split: usize = 0;
        while (state.paneCount(tab_index) < max_panes_per_tab and total_panes < max_live_panes) : (tab_split += 1) {
            tab_pane = try state.split(tab_pane, if (tab_split % 2 == 0) .vertical else .horizontal);
            total_panes += 1;
        }
    }
    try std.testing.expectEqual(max_live_panes, total_panes);
    try std.testing.expectError(error.Capacity, state.split(pane, .vertical));
    try std.testing.expectError(error.InvalidText, state.renameTab(state.tabId(0).?, &[_]u8{0xff}));
    try std.testing.expectEqual(@as(u16, 321), state.surface.width);
    try state.validate();
}

test "topology mutations preserve tiled coverage through resize and closure" {
    var state = try Topology.init(.{ .width = 321, .height = 241 }, 24);
    const root = state.paneId(0, 0).?;
    const right = try state.split(root, .vertical);
    const lower = try state.split(root, .horizontal);
    try std.testing.expect(lower != root);
    try state.validate();
    try state.resizeSurface(.{ .width = 640, .height = 480 });
    try state.validate();
    try std.testing.expectEqual(right, try state.focusDirection(.right));
    try state.resizeDivider(state.paneId(0, 0).?, -2, .horizontal);
    try state.validate();
    try state.closePane(root);
    try state.validate();
}

test "hostile surface collapse preserves the complete retained topology" {
    var state = try Topology.init(.{ .width = 320, .height = 240 }, 24);
    const root = state.paneId(0, 0).?;
    const right = try state.split(root, .vertical);
    const lower_right = try state.split(right, .horizontal);
    const lower_left = try state.split(root, .horizontal);
    try std.testing.expect(lower_right != lower_left);
    const before = state;
    try std.testing.expectError(error.InvalidGeometry, state.resizeSurface(.{ .width = 1, .height = 1 }));
    try std.testing.expectEqualDeep(before, state);
    try std.testing.expectEqual(chrome.Size{ .width = 320, .height = 240 }, state.surface);
}

test "continuous resize derives from one stable current-layout basis" {
    var state = try Topology.init(.{ .width = 321, .height = 241 }, 24);
    const root = state.paneId(0, 0).?;
    const right = try state.split(root, .vertical);
    const lower_right = try state.split(right, .horizontal);
    const lower_left = try state.split(root, .horizontal);
    try std.testing.expect(lower_right != lower_left);
    try state.resizeDivider(root, 7, .vertical);
    const basis = state;
    for (0..128) |_| {
        try state.resizeSurface(.{ .width = 997, .height = 613 });
        try state.resizeSurface(.{ .width = 173, .height = 89 });
        try state.resizeSurface(.{ .width = 321, .height = 241 });
    }
    try std.testing.expectEqualDeep(basis, state);
}

test "connected T junction divider and close preserve complete tiling" {
    var state = try Topology.init(.{ .width = 320, .height = 240 }, 24);
    const left = state.paneId(0, 0).?;
    const right = try state.split(left, .vertical);
    const lower_left = try state.split(left, .horizontal);
    try state.resizeDivider(left, 11, .vertical);
    try state.validate();
    try state.closePane(right);
    try state.validate();
    try std.testing.expectEqual(@as(usize, 2), state.paneCount(0));
    try state.closePane(lower_left);
    try state.validate();
}

test "validation rejects duplicate zero and inconsistent identities" {
    var state = try Topology.init(.{ .width = 80, .height = 40 }, 24);
    const second = try state.createTab("second");
    state.tabs[1].id = state.tabs[0].id;
    try std.testing.expectError(error.InvalidId, state.validate());
    state.tabs[1].id = second;
    state.tabs[1].panes[0].id = @fromBackingInt(0);
    try std.testing.expectError(error.InvalidId, state.validate());
    state.tabs[1].panes[0].id = @fromBackingInt(2);
    state.live_panes = 1;
    try std.testing.expectError(error.InvalidGeometry, state.validate());
}

test "scroll retention is exact and geometry mutations stay renderable" {
    var state = try Topology.init(.{ .width = 80, .height = 40 }, 24);
    const pane = state.paneId(0, 0).?;
    try std.testing.expectError(error.InvalidScroll, state.setPaneScroll(pane, .{ .visible = 0, .total = 4, .start = 0 }));
    try state.setPaneScroll(pane, .{ .visible = 4, .total = 8, .start = 0 });
    try std.testing.expectError(error.InvalidGeometry, state.split(pane, .horizontal));
    try state.validate();
}

test "tiny compositor surfaces remain deterministic with a clamped tab bar" {
    var state = try Topology.init(.{ .width = 8, .height = 1 }, 24);
    try state.validate();
    var primitives: [16]chrome.Primitive = undefined;
    var text: [128]u8 = undefined;
    const output = try state.project(testAppearance(), &.{}, &primitives, &text);
    try std.testing.expect(output.primitives.len > 0);
    try std.testing.expectEqual(@as(i32, 0), state.tabs[0].panes[0].rect.y);
    try std.testing.expectEqual(@as(u16, 1), state.tabs[0].panes[0].rect.height);
}

test "tab and pane identity issuance commits together" {
    var state = try Topology.init(.{ .width = 80, .height = 40 }, 24);
    const next_tab = state.next_tab_id;
    state.next_pane_id = std.math.maxInt(u64);
    try std.testing.expectError(error.Capacity, state.createTab("blocked"));
    try std.testing.expectEqual(next_tab, state.next_tab_id);
    try std.testing.expectEqual(@as(usize, 1), state.tabCount());
    try state.validate();
}

test "floating panes retain order geometry focus hit and transactional identity" {
    var state = try Topology.init(.{ .width = 160, .height = 100 }, 24);
    const tiled = state.paneId(0, 0).?;
    const first = try state.createFloatingPane(.{ .x = 20, .y = 32, .width = 80, .height = 48 }, "first");
    const second = try state.createFloatingPane(.{ .x = 50, .y = 40, .width = 80, .height = 48 }, "second");
    try std.testing.expectEqual(second, (try state.hitTest(testAppearance(), .{ .x = 60, .y = 50 })).?.pane);
    try state.raiseFloatingPane(first);
    try std.testing.expectEqual(first, (try state.hitTest(testAppearance(), .{ .x = 60, .y = 50 })).?.pane);
    try state.setFloatingRect(first, .{ .x = 24, .y = 30, .width = 60, .height = 40 });
    try std.testing.expectEqual(tiled, (try state.hitTest(testAppearance(), .{ .x = 140, .y = 90 })).?.pane);
    const next = state.next_pane_id;
    const before = state;
    try std.testing.expectError(error.InvalidGeometry, state.createFloatingPane(.{ .x = -1, .y = 10, .width = 5, .height = 5 }, "bad"));
    try std.testing.expectEqual(next, state.next_pane_id);
    try std.testing.expectEqualDeep(before, state);
    try state.resizeSurface(.{ .width = 200, .height = 120 });
    try state.closePane(first);
    try std.testing.expectEqual(second, (try state.hitTest(testAppearance(), .{ .x = 70, .y = 60 })).?.pane);
    try state.validate();
}

test "closing background panes preserves focus and focused closure falls back" {
    var state = try Topology.init(.{ .width = 160, .height = 100 }, 24);
    const tiled = state.paneId(0, 0).?;
    const other_tiled = try state.split(tiled, .vertical);
    try std.testing.expect(other_tiled != tiled);
    const first = try state.createFloatingPane(.{ .x = 20, .y = 32, .width = 40, .height = 32 }, "first");
    const second = try state.createFloatingPane(.{ .x = 60, .y = 32, .width = 40, .height = 32 }, "second");
    const third = try state.createFloatingPane(.{ .x = 80, .y = 40, .width = 40, .height = 32 }, "third");
    try state.closePane(tiled);
    try std.testing.expect(state.findPane(third).?.pane < state.tabs[0].pane_count);
    try std.testing.expect(state.tabs[0].panes[state.findPane(third).?.pane].focused);
    try state.closePane(second);
    try std.testing.expect(state.tabs[0].panes[state.findPane(third).?.pane].focused);
    try state.closePane(third);
    try std.testing.expect(state.tabs[0].panes[state.findPane(first).?.pane].focused);
    try state.validate();
}

test "hidden tabs retain floating state outside visible composition" {
    var state = try Topology.init(.{ .width = 120, .height = 80 }, 20);
    const first_tab = state.activeTabId();
    const floating = try state.createFloatingPane(.{ .x = 12, .y = 28, .width = 60, .height = 36 }, "float");
    const second_tab = try state.createTab("other");
    try std.testing.expectEqual(second_tab, state.activeTabId());
    var primitives: [32]chrome.Primitive = undefined;
    var text: [256]u8 = undefined;
    const hidden = try state.project(testAppearance(), &.{}, &primitives, &text);
    try std.testing.expect(!std.mem.containsAtLeast(u8, hidden.text, 1, "float"));
    try state.switchTab(first_tab);
    try std.testing.expectEqual(floating, (try state.hitTest(testAppearance(), .{ .x = 20, .y = 30 })).?.pane);
    const visible = try state.project(testAppearance(), &.{.{ .pane = floating, .rect = .{ .x = 1, .y = 24, .width = 4, .height = 4 }, .color = .{ .r = 1, .g = 2, .b = 3, .a = 4 } }}, &primitives, &text);
    try std.testing.expect(std.mem.containsAtLeast(u8, visible.text, 1, "float"));
}
