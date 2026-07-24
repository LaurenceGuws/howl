//! Owns one bounded session of tabs and split-pane geometry.
//!
//! The model has no terminal, renderer, or platform values. Names are the only
//! allocated state; topology mutations use fixed storage and either commit one
//! valid workspace or leave the prior state unchanged.

const std = @import("std");

// Public session bounds, identities, and geometry facts.

/// A session admits at most sixteen ordered tabs.
pub const max_tabs: u8 = 16;
/// One tab admits at most sixteen terminal panes.
pub const max_panes_per_tab: u8 = 16;
/// One session admits at most sixty-four terminal panes across all tabs.
pub const max_panes: u8 = 64;
const max_split_depth: u8 = 8;
const max_name_bytes: u8 = 128;
/// Maximum admitted workspace grid width used by native host layout.
pub const max_cols: u16 = 512;
/// Maximum admitted workspace grid height used by native host layout.
pub const max_rows: u16 = 256;
const min_pane_cols: u16 = 2;
const min_pane_rows: u16 = 1;

const max_nodes_per_tab: u8 = max_panes_per_tab * 2 - 1;
const no_node = std.math.maxInt(u8);

/// Stable identity supplied for the one process-owned session.
pub const SessionId = enum(u64) { _ };
/// Stable tab identity that is never reused by a Workspace.
pub const TabId = enum(u64) { _ };
/// Stable pane identity that is never reused by a Workspace.
pub const PaneId = enum(u64) { _ };

/// Selects left/right or top/bottom child geometry.
pub const SplitAxis = enum {
    /// Divide columns into left and right children.
    horizontal,
    /// Divide rows into top and bottom children.
    vertical,
};

/// Selects deterministic spatial focus movement.
pub const Direction = enum { left, right, up, down };

/// Grid dimensions shared by every tab in one workspace.
pub const Size = struct {
    /// Number of terminal cell columns.
    cols: u16,
    /// Number of terminal cell rows.
    rows: u16,
};

/// One pane's deterministic terminal-grid placement.
pub const Rect = struct {
    /// Zero-based left column.
    col: u16,
    /// Zero-based top row.
    row: u16,
    /// Positive pane width in cells.
    cols: u16,
    /// Positive pane height in cells.
    rows: u16,
};

/// Borrowed layout fact written into caller-owned bounded storage.
pub const PaneLayout = struct {
    /// Stable identity of the placed pane.
    pane: PaneId,
    /// Exact grid rectangle assigned by the split tree.
    rect: Rect,
    /// True only for the tab's focused pane.
    focused: bool,
};

/// Identities created by one new tab.
pub const CreatedTab = struct {
    /// Stable identity of the appended tab.
    tab: TabId,
    /// Stable identity of its initial focused pane.
    pane: PaneId,
};

// Fixed tab topology and allocated-name ownership.

const Split = struct {
    axis: SplitAxis,
    first: u8,
    second: u8,
    first_extent: u16,
};

const Node = union(enum) {
    free,
    pane: PaneId,
    split: Split,
};

const Tab = struct {
    id: TabId,
    name: []u8,
    nodes: [max_nodes_per_tab]Node = @splat(.free),
    root: u8 = 0,
    pane_count: u8 = 1,
    focused: PaneId,

    fn deinit(self: *Tab, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
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
            .split => |split| if (split.first == child or split.second == child) return @intCast(index),
            else => {},
        };
        return null;
    }

    fn firstPane(self: *const Tab, node_index: u8) PaneId {
        var index = node_index;
        while (true) switch (self.nodes[index]) {
            .pane => |pane| return pane,
            .split => |split| index = split.first,
            .free => unreachable,
        };
    }

    fn depth(self: *const Tab, node_index: u8) u8 {
        var depth_value: u8 = 0;
        var index = node_index;
        while (index != self.root) {
            index = self.findParent(index) orelse unreachable;
            depth_value += 1;
        }
        return depth_value;
    }
};

// Transactional workspace lifecycle and mutations.

/// Owns one bounded, platform-independent session workspace.
pub const Workspace = struct {
    allocator: std.mem.Allocator,
    /// Stable identity supplied by the process-level session owner.
    session: SessionId,
    tabs: [max_tabs]Tab = undefined,
    tab_count: u8 = 0,
    active_index: u8 = 0,
    pane_count: u8 = 0,
    next_tab: u64 = 1,
    next_pane: u64 = 1,
    size: Size,

    /// Create one workspace with one named tab and one focused pane.
    pub fn init(
        allocator: std.mem.Allocator,
        session: SessionId,
        name: []const u8,
        size: Size,
    ) error{ OutOfMemory, InvalidSession, InvalidName, InvalidSize }!Workspace {
        if (@intFromEnum(session) == 0) return error.InvalidSession;
        try validateName(name);
        try validateSize(size);
        const owned_name = try allocator.dupe(u8, name);
        var workspace = Workspace{ .allocator = allocator, .session = session, .size = size };
        workspace.tabs[0] = .{
            .id = @enumFromInt(1),
            .name = owned_name,
            .focused = @enumFromInt(1),
        };
        workspace.tabs[0].nodes[0] = .{ .pane = @enumFromInt(1) };
        workspace.tab_count = 1;
        workspace.pane_count = 1;
        workspace.next_tab = 2;
        workspace.next_pane = 2;
        return workspace;
    }

    /// Release every retained tab name through the initializer allocator.
    pub fn deinit(self: *Workspace) void {
        for (self.tabs[0..self.tab_count]) |*tab| tab.deinit(self.allocator);
        self.tab_count = 0;
        self.pane_count = 0;
    }

    /// Return the active stable tab identity.
    pub fn activeTab(self: *const Workspace) TabId {
        return self.tabs[self.active_index].id;
    }

    /// Write stable tab identities in current display order into caller storage.
    pub fn tabOrder(self: *const Workspace, output: *[max_tabs]TabId) []const TabId {
        for (self.tabs[0..self.tab_count], output[0..self.tab_count]) |tab, *id| id.* = tab.id;
        return output[0..self.tab_count];
    }

    /// Return the active tab's stable focused pane identity.
    pub fn focusedPane(self: *const Workspace) PaneId {
        return self.tabs[self.active_index].focused;
    }

    /// Return the exact retained tab name, borrowed until mutation or deinit.
    pub fn tabName(self: *const Workspace, id: TabId) error{StaleTab}![]const u8 {
        return self.tabs[try self.tabIndex(id)].name;
    }

    /// Append one tab and initial pane without changing the active tab.
    pub fn createTab(
        self: *Workspace,
        name: []const u8,
    ) error{ OutOfMemory, InvalidName, TabLimit, PaneLimit, IdExhausted }!CreatedTab {
        try validateName(name);
        if (self.tab_count == max_tabs) return error.TabLimit;
        if (self.pane_count == max_panes) return error.PaneLimit;
        if (self.next_tab == 0 or self.next_tab == std.math.maxInt(u64) or
            self.next_pane == 0 or self.next_pane == std.math.maxInt(u64)) return error.IdExhausted;
        const owned_name = try self.allocator.dupe(u8, name);
        const tab_id: TabId = @enumFromInt(self.next_tab);
        const pane_id: PaneId = @enumFromInt(self.next_pane);
        var tab = Tab{ .id = tab_id, .name = owned_name, .focused = pane_id };
        tab.nodes[0] = .{ .pane = pane_id };
        self.tabs[self.tab_count] = tab;
        self.tab_count += 1;
        self.pane_count += 1;
        self.next_tab += 1;
        self.next_pane += 1;
        return .{ .tab = tab_id, .pane = pane_id };
    }

    /// Close one tab, copy every retired pane identity, and choose the adjacent active tab.
    ///
    /// The returned slice aliases `removed` and remains owned by the caller.
    pub fn closeTab(
        self: *Workspace,
        id: TabId,
        removed: *[max_panes_per_tab]PaneId,
    ) error{ StaleTab, LastTab }![]const PaneId {
        const index = try self.tabIndex(id);
        if (self.tab_count == 1) return error.LastTab;
        var layouts: [max_panes_per_tab]PaneLayout = undefined;
        const panes = self.layoutTab(&self.tabs[index], &layouts) catch unreachable;
        for (panes, removed[0..panes.len]) |pane, *destination| destination.* = pane.pane;
        const removed_panes = self.tabs[index].pane_count;
        self.tabs[index].deinit(self.allocator);
        var cursor = index;
        while (cursor + 1 < self.tab_count) : (cursor += 1) self.tabs[cursor] = self.tabs[cursor + 1];
        self.tab_count -= 1;
        self.pane_count -= removed_panes;
        if (index < self.active_index) {
            self.active_index -= 1;
        } else if (index == self.active_index and self.active_index == self.tab_count) {
            self.active_index -= 1;
        }
        return removed[0..removed_panes];
    }

    /// Replace one tab name transactionally; byte-identical names are no-ops.
    pub fn renameTab(
        self: *Workspace,
        id: TabId,
        name: []const u8,
    ) error{ OutOfMemory, InvalidName, StaleTab }!bool {
        try validateName(name);
        const index = try self.tabIndex(id);
        if (std.mem.eql(u8, self.tabs[index].name, name)) return false;
        const replacement = try self.allocator.dupe(u8, name);
        self.allocator.free(self.tabs[index].name);
        self.tabs[index].name = replacement;
        return true;
    }

    /// Move one stable tab to a zero-based order index while retaining active identity.
    pub fn reorderTab(self: *Workspace, id: TabId, target: u8) error{ StaleTab, InvalidOrder }!bool {
        if (target >= self.tab_count) return error.InvalidOrder;
        const source = try self.tabIndex(id);
        if (source == target) return false;
        const active = self.activeTab();
        const moving = self.tabs[source];
        if (source < target) {
            var index = source;
            while (index < target) : (index += 1) self.tabs[index] = self.tabs[index + 1];
        } else {
            var index = source;
            while (index > target) : (index -= 1) self.tabs[index] = self.tabs[index - 1];
        }
        self.tabs[target] = moving;
        self.active_index = self.tabIndex(active) catch unreachable;
        return true;
    }

    /// Select one existing tab; selecting the active tab is a no-op.
    pub fn switchTab(self: *Workspace, id: TabId) error{StaleTab}!bool {
        const index = try self.tabIndex(id);
        if (index == self.active_index) return false;
        self.active_index = index;
        return true;
    }

    /// Split one pane into equal children, focus it, and return the new pane identity.
    pub fn splitPane(
        self: *Workspace,
        tab_id: TabId,
        pane_id: PaneId,
        axis: SplitAxis,
    ) error{ StaleTab, StalePane, PaneLimit, DepthLimit, GeometryLimit, IdExhausted }!PaneId {
        const tab = &self.tabs[try self.tabIndex(tab_id)];
        const pane_node = tab.findPane(pane_id) orelse return error.StalePane;
        if (tab.pane_count == max_panes_per_tab or self.pane_count == max_panes) return error.PaneLimit;
        if (tab.depth(pane_node) >= max_split_depth) return error.DepthLimit;
        const pane_rect = self.paneRect(tab, pane_id) catch return error.GeometryLimit;
        switch (axis) {
            .horizontal => if (pane_rect.cols < min_pane_cols * 2) return error.GeometryLimit,
            .vertical => if (pane_rect.rows < min_pane_rows * 2) return error.GeometryLimit,
        }
        if (self.next_pane == 0 or self.next_pane == std.math.maxInt(u64)) return error.IdExhausted;
        const first = tab.findFree(pane_node) orelse unreachable;
        const second = tab.findFree(first) orelse unreachable;
        const new_pane: PaneId = @enumFromInt(self.next_pane);
        tab.nodes[first] = .{ .pane = pane_id };
        tab.nodes[second] = .{ .pane = new_pane };
        tab.nodes[pane_node] = .{ .split = .{
            .axis = axis,
            .first = first,
            .second = second,
            .first_extent = switch (axis) {
                .horizontal => pane_rect.cols / 2,
                .vertical => pane_rect.rows / 2,
            },
        } };
        tab.pane_count += 1;
        tab.focused = new_pane;
        self.pane_count += 1;
        self.next_pane += 1;
        return new_pane;
    }

    /// Close and return one pane, focusing its surviving sibling subtree when needed.
    pub fn closePane(
        self: *Workspace,
        tab_id: TabId,
        pane_id: PaneId,
    ) error{ StaleTab, StalePane, LastPane }!PaneId {
        const tab = &self.tabs[try self.tabIndex(tab_id)];
        const pane_node = tab.findPane(pane_id) orelse return error.StalePane;
        if (tab.pane_count == 1) return error.LastPane;
        const parent = tab.findParent(pane_node) orelse unreachable;
        const split = tab.nodes[parent].split;
        const sibling = if (split.first == pane_node) split.second else split.first;
        const fallback = tab.firstPane(sibling);
        tab.nodes[parent] = tab.nodes[sibling];
        tab.nodes[pane_node] = .free;
        tab.nodes[sibling] = .free;
        tab.pane_count -= 1;
        self.pane_count -= 1;
        if (tab.focused == pane_id) tab.focused = fallback;
        return pane_id;
    }

    /// Move focus to the nearest pane in one direction; no candidate is a no-op.
    pub fn focus(self: *Workspace, direction: Direction) bool {
        const tab = &self.tabs[self.active_index];
        var layouts: [max_panes_per_tab]PaneLayout = undefined;
        const placed = self.layoutTab(tab, &layouts) catch unreachable;
        const current = for (placed) |placement| {
            if (placement.pane == tab.focused) break placement.rect;
        } else unreachable;
        var best: ?PaneLayout = null;
        for (placed) |candidate| {
            if (candidate.pane == tab.focused or !isInDirection(current, candidate.rect, direction)) continue;
            if (best == null or nearer(current, candidate, best.?, direction)) best = candidate;
        }
        const chosen = best orelse return false;
        tab.focused = chosen.pane;
        return true;
    }

    /// Focus one pane in the active tab; stale identities fail and repetition is a no-op.
    pub fn focusPane(self: *Workspace, pane_id: PaneId) error{StalePane}!bool {
        const tab = &self.tabs[self.active_index];
        if (tab.findPane(pane_id) == null) return error.StalePane;
        if (tab.focused == pane_id) return false;
        tab.focused = pane_id;
        return true;
    }

    /// Grow one pane toward the nearest matching divider by at most `cells`.
    ///
    /// The move saturates at each child subtree's minimum geometry. Zero,
    /// missing outer boundaries, and already-saturated dividers are no-ops.
    pub fn resizePane(
        self: *Workspace,
        tab_id: TabId,
        pane_id: PaneId,
        direction: Direction,
        cells: u16,
    ) error{ StaleTab, StalePane }!bool {
        if (cells == 0) return false;
        const tab = &self.tabs[try self.tabIndex(tab_id)];
        var child = tab.findPane(pane_id) orelse return error.StalePane;
        while (child != tab.root) {
            const parent = tab.findParent(child) orelse unreachable;
            const split = &tab.nodes[parent].split;
            const grows_first = switch (direction) {
                .right => split.axis == .horizontal and split.first == child,
                .left => split.axis == .horizontal and split.second == child,
                .down => split.axis == .vertical and split.first == child,
                .up => split.axis == .vertical and split.second == child,
            };
            if (grows_first) {
                const rect = self.nodeRect(tab, parent) orelse unreachable;
                const first_min = minimumSize(tab, split.first);
                const second_min = minimumSize(tab, split.second);
                const total = if (split.axis == .horizontal) rect.cols else rect.rows;
                const low = if (split.axis == .horizontal) first_min.cols else first_min.rows;
                const high = total - if (split.axis == .horizontal) second_min.cols else second_min.rows;
                const target = switch (direction) {
                    .right, .down => @min(high, std.math.add(u16, split.first_extent, cells) catch high),
                    .left, .up => if (cells >= split.first_extent - low) low else split.first_extent - cells,
                };
                if (target == split.first_extent) return false;
                split.first_extent = target;
                return true;
            }
            child = parent;
        }
        return false;
    }

    /// Resize every tab transactionally, preserving split extents or clamping to subtree minima.
    pub fn resize(self: *Workspace, size: Size) error{ InvalidSize, GeometryLimit }!bool {
        try validateSize(size);
        if (std.meta.eql(self.size, size)) return false;
        var extents: [max_tabs][max_nodes_per_tab]u16 = @splat(@splat(0));
        for (self.tabs[0..self.tab_count], 0..) |*tab, index| {
            try planResize(
                tab,
                tab.root,
                .{ .col = 0, .row = 0, .cols = size.cols, .rows = size.rows },
                &extents[index],
            );
        }
        for (self.tabs[0..self.tab_count], 0..) |*tab, tab_index| {
            for (&tab.nodes, 0..) |*node, node_index| switch (node.*) {
                .split => |*split| split.first_extent = extents[tab_index][node_index],
                else => {},
            };
        }
        self.size = size;
        return true;
    }

    /// Write one tab's complete deterministic pane layout into fixed caller storage.
    pub fn layout(
        self: *const Workspace,
        tab_id: TabId,
        output: *[max_panes_per_tab]PaneLayout,
    ) error{ StaleTab, GeometryLimit }![]const PaneLayout {
        return self.layoutTab(&self.tabs[try self.tabIndex(tab_id)], output);
    }

    fn validate(self: *const Workspace) error{InvalidWorkspace}!void {
        if (self.tab_count == 0 or self.tab_count > max_tabs or
            self.active_index >= self.tab_count) return error.InvalidWorkspace;
        if (self.pane_count == 0 or self.pane_count > max_panes) return error.InvalidWorkspace;
        validateSize(self.size) catch return error.InvalidWorkspace;
        if (@intFromEnum(self.session) == 0) return error.InvalidWorkspace;
        var pane_ids: [max_panes]PaneId = undefined;
        var pane_ids_count: u8 = 0;
        var maximum_tab_id: u64 = 0;
        var maximum_pane_id: u64 = 0;
        var layouts: [max_panes_per_tab]PaneLayout = undefined;
        for (self.tabs[0..self.tab_count], 0..) |*tab, tab_index| {
            if (@intFromEnum(tab.id) == 0) return error.InvalidWorkspace;
            maximum_tab_id = @max(maximum_tab_id, @intFromEnum(tab.id));
            if (tab.name.len == 0 or tab.name.len > max_name_bytes) return error.InvalidWorkspace;
            for (self.tabs[0..tab_index]) |prior| if (prior.id == tab.id) return error.InvalidWorkspace;
            if (tab.pane_count == 0 or tab.pane_count > max_panes_per_tab) return error.InvalidWorkspace;
            try validateTopology(tab, &pane_ids, &pane_ids_count);
            const placed = self.layoutTab(tab, &layouts) catch return error.InvalidWorkspace;
            if (placed.len != tab.pane_count) return error.InvalidWorkspace;
        }
        if (pane_ids_count != self.pane_count) return error.InvalidWorkspace;
        for (pane_ids[0..pane_ids_count]) |pane| maximum_pane_id = @max(maximum_pane_id, @intFromEnum(pane));
        if (self.next_tab <= maximum_tab_id or self.next_pane <= maximum_pane_id) return error.InvalidWorkspace;
    }

    fn tabIndex(self: *const Workspace, id: TabId) error{StaleTab}!u8 {
        for (self.tabs[0..self.tab_count], 0..) |tab, index| if (tab.id == id) return @intCast(index);
        return error.StaleTab;
    }

    fn paneRect(self: *const Workspace, tab: *const Tab, pane: PaneId) error{GeometryLimit}!Rect {
        var output: [max_panes_per_tab]PaneLayout = undefined;
        for (try self.layoutTab(tab, &output)) |placed| if (placed.pane == pane) return placed.rect;
        unreachable;
    }

    fn nodeRect(self: *const Workspace, tab: *const Tab, target: u8) ?Rect {
        return findNodeRect(
            tab,
            tab.root,
            target,
            .{ .col = 0, .row = 0, .cols = self.size.cols, .rows = self.size.rows },
        );
    }

    fn layoutTab(
        self: *const Workspace,
        tab: *const Tab,
        output: *[max_panes_per_tab]PaneLayout,
    ) error{GeometryLimit}![]const PaneLayout {
        var count: u8 = 0;
        try placeNode(
            tab,
            tab.root,
            .{ .col = 0, .row = 0, .cols = self.size.cols, .rows = self.size.rows },
            output,
            &count,
        );
        return output[0..count];
    }
};

// Hostile-state validation and exact recursive layout.

fn validateTopology(
    tab: *const Tab,
    pane_ids: *[max_panes]PaneId,
    pane_ids_count: *u8,
) error{InvalidWorkspace}!void {
    if (tab.root >= tab.nodes.len) return error.InvalidWorkspace;
    var visited: [max_nodes_per_tab]bool = @splat(false);
    var stack_nodes: [max_nodes_per_tab]u8 = undefined;
    var stack_depths: [max_nodes_per_tab]u8 = undefined;
    var stack_count: u8 = 1;
    var panes_seen: u8 = 0;
    var used: u8 = 0;
    var focused_seen = false;
    stack_nodes[0] = tab.root;
    stack_depths[0] = 0;

    while (stack_count > 0) {
        stack_count -= 1;
        const node_index = stack_nodes[stack_count];
        const depth = stack_depths[stack_count];
        if (node_index >= tab.nodes.len or visited[node_index] or depth > max_split_depth)
            return error.InvalidWorkspace;
        visited[node_index] = true;
        used += 1;
        switch (tab.nodes[node_index]) {
            .free => return error.InvalidWorkspace,
            .pane => |pane| {
                if (@intFromEnum(pane) == 0 or pane_ids_count.* == pane_ids.len)
                    return error.InvalidWorkspace;
                for (pane_ids[0..pane_ids_count.*]) |prior| if (prior == pane) return error.InvalidWorkspace;
                pane_ids[pane_ids_count.*] = pane;
                pane_ids_count.* += 1;
                panes_seen += 1;
                if (pane == tab.focused) {
                    if (focused_seen) return error.InvalidWorkspace;
                    focused_seen = true;
                }
            },
            .split => |split| {
                if (depth == max_split_depth or split.first_extent == 0 or
                    split.first == split.second or split.first >= tab.nodes.len or split.second >= tab.nodes.len or
                    stack_count + 2 > stack_nodes.len)
                    return error.InvalidWorkspace;
                stack_nodes[stack_count] = split.second;
                stack_depths[stack_count] = depth + 1;
                stack_count += 1;
                stack_nodes[stack_count] = split.first;
                stack_depths[stack_count] = depth + 1;
                stack_count += 1;
            },
        }
    }
    for (tab.nodes, visited) |node, reached| if (node != .free and !reached) return error.InvalidWorkspace;
    if (!focused_seen or panes_seen != tab.pane_count or used != tab.pane_count * 2 - 1)
        return error.InvalidWorkspace;
}

fn validateName(name: []const u8) error{InvalidName}!void {
    if (name.len == 0 or name.len > max_name_bytes) return error.InvalidName;
}

fn validateSize(size: Size) error{InvalidSize}!void {
    if (size.cols < min_pane_cols or size.cols > max_cols or size.rows < min_pane_rows or size.rows > max_rows)
        return error.InvalidSize;
}

fn placeNode(
    tab: *const Tab,
    node_index: u8,
    rect: Rect,
    output: *[max_panes_per_tab]PaneLayout,
    count: *u8,
) error{GeometryLimit}!void {
    switch (tab.nodes[node_index]) {
        .free => return error.GeometryLimit,
        .pane => |pane| {
            if (rect.cols < min_pane_cols or rect.rows < min_pane_rows or count.* == output.len)
                return error.GeometryLimit;
            output[count.*] = .{ .pane = pane, .rect = rect, .focused = pane == tab.focused };
            count.* += 1;
        },
        .split => |split| switch (split.axis) {
            .horizontal => {
                const first_cols = split.first_extent;
                if (first_cols > rect.cols) return error.GeometryLimit;
                const second_cols = rect.cols - first_cols;
                if (first_cols < min_pane_cols or second_cols < min_pane_cols) return error.GeometryLimit;
                try placeNode(tab, split.first, .{
                    .col = rect.col,
                    .row = rect.row,
                    .cols = first_cols,
                    .rows = rect.rows,
                }, output, count);
                try placeNode(tab, split.second, .{
                    .col = rect.col + first_cols,
                    .row = rect.row,
                    .cols = second_cols,
                    .rows = rect.rows,
                }, output, count);
            },
            .vertical => {
                const first_rows = split.first_extent;
                if (first_rows > rect.rows) return error.GeometryLimit;
                const second_rows = rect.rows - first_rows;
                if (first_rows < min_pane_rows or second_rows < min_pane_rows) return error.GeometryLimit;
                try placeNode(tab, split.first, .{
                    .col = rect.col,
                    .row = rect.row,
                    .cols = rect.cols,
                    .rows = first_rows,
                }, output, count);
                try placeNode(tab, split.second, .{
                    .col = rect.col,
                    .row = rect.row + first_rows,
                    .cols = rect.cols,
                    .rows = second_rows,
                }, output, count);
            },
        },
    }
}

fn minimumSize(tab: *const Tab, node_index: u8) Size {
    return switch (tab.nodes[node_index]) {
        .free => unreachable,
        .pane => .{ .cols = min_pane_cols, .rows = min_pane_rows },
        .split => |split| minimum: {
            const first = minimumSize(tab, split.first);
            const second = minimumSize(tab, split.second);
            break :minimum switch (split.axis) {
                .horizontal => .{ .cols = first.cols + second.cols, .rows = @max(first.rows, second.rows) },
                .vertical => .{ .cols = @max(first.cols, second.cols), .rows = first.rows + second.rows },
            };
        },
    };
}

fn planResize(
    tab: *const Tab,
    node_index: u8,
    rect: Rect,
    extents: *[max_nodes_per_tab]u16,
) error{GeometryLimit}!void {
    switch (tab.nodes[node_index]) {
        .free => return error.GeometryLimit,
        .pane => {
            if (rect.cols < min_pane_cols or rect.rows < min_pane_rows) return error.GeometryLimit;
        },
        .split => |split| {
            const first_min = minimumSize(tab, split.first);
            const second_min = minimumSize(tab, split.second);
            const total = if (split.axis == .horizontal) rect.cols else rect.rows;
            const low = if (split.axis == .horizontal) first_min.cols else first_min.rows;
            const second = if (split.axis == .horizontal) second_min.cols else second_min.rows;
            if (total < low + second) return error.GeometryLimit;
            const extent = std.math.clamp(split.first_extent, low, total - second);
            extents[node_index] = extent;
            switch (split.axis) {
                .horizontal => {
                    try planResize(tab, split.first, .{
                        .col = rect.col,
                        .row = rect.row,
                        .cols = extent,
                        .rows = rect.rows,
                    }, extents);
                    try planResize(tab, split.second, .{
                        .col = rect.col + extent,
                        .row = rect.row,
                        .cols = rect.cols - extent,
                        .rows = rect.rows,
                    }, extents);
                },
                .vertical => {
                    try planResize(tab, split.first, .{
                        .col = rect.col,
                        .row = rect.row,
                        .cols = rect.cols,
                        .rows = extent,
                    }, extents);
                    try planResize(tab, split.second, .{
                        .col = rect.col,
                        .row = rect.row + extent,
                        .cols = rect.cols,
                        .rows = rect.rows - extent,
                    }, extents);
                },
            }
        },
    }
}

fn findNodeRect(tab: *const Tab, node_index: u8, target: u8, rect: Rect) ?Rect {
    if (node_index == target) return rect;
    return switch (tab.nodes[node_index]) {
        .free, .pane => null,
        .split => |split| switch (split.axis) {
            .horizontal => findNodeRect(tab, split.first, target, .{
                .col = rect.col,
                .row = rect.row,
                .cols = split.first_extent,
                .rows = rect.rows,
            }) orelse findNodeRect(tab, split.second, target, .{
                .col = rect.col + split.first_extent,
                .row = rect.row,
                .cols = rect.cols - split.first_extent,
                .rows = rect.rows,
            }),
            .vertical => findNodeRect(tab, split.first, target, .{
                .col = rect.col,
                .row = rect.row,
                .cols = rect.cols,
                .rows = split.first_extent,
            }) orelse findNodeRect(tab, split.second, target, .{
                .col = rect.col,
                .row = rect.row + split.first_extent,
                .cols = rect.cols,
                .rows = rect.rows - split.first_extent,
            }),
        },
    };
}

// Directional focus and divider geometry.

fn isInDirection(current: Rect, candidate: Rect, direction: Direction) bool {
    return switch (direction) {
        .left => candidate.col + candidate.cols <= current.col,
        .right => current.col + current.cols <= candidate.col,
        .up => candidate.row + candidate.rows <= current.row,
        .down => current.row + current.rows <= candidate.row,
    };
}

fn nearer(current: Rect, candidate: PaneLayout, best: PaneLayout, direction: Direction) bool {
    const candidate_overlap = perpendicularOverlap(current, candidate.rect, direction);
    const best_overlap = perpendicularOverlap(current, best.rect, direction);
    if (candidate_overlap != best_overlap) return candidate_overlap;
    const candidate_gap = directionalGap(current, candidate.rect, direction);
    const best_gap = directionalGap(current, best.rect, direction);
    if (candidate_gap != best_gap) return candidate_gap < best_gap;
    const candidate_center = perpendicularCenterDistance(current, candidate.rect, direction);
    const best_center = perpendicularCenterDistance(current, best.rect, direction);
    if (candidate_center != best_center) return candidate_center < best_center;
    return @intFromEnum(candidate.pane) < @intFromEnum(best.pane);
}

fn perpendicularOverlap(a: Rect, b: Rect, direction: Direction) bool {
    return switch (direction) {
        .left, .right => a.row < b.row + b.rows and b.row < a.row + a.rows,
        .up, .down => a.col < b.col + b.cols and b.col < a.col + a.cols,
    };
}

fn directionalGap(a: Rect, b: Rect, direction: Direction) u16 {
    return switch (direction) {
        .left => a.col - (b.col + b.cols),
        .right => b.col - (a.col + a.cols),
        .up => a.row - (b.row + b.rows),
        .down => b.row - (a.row + a.rows),
    };
}

fn perpendicularCenterDistance(a: Rect, b: Rect, direction: Direction) u16 {
    const a_center, const b_center = switch (direction) {
        .left, .right => .{ a.row * 2 + a.rows, b.row * 2 + b.rows },
        .up, .down => .{ a.col * 2 + a.cols, b.col * 2 + b.cols },
    };
    return if (a_center > b_center) a_center - b_center else b_center - a_center;
}

fn sessionId(value: u64) SessionId {
    return @enumFromInt(value);
}

test "workspace owns transactional tab identity order names and fallback" {
    var workspace = try Workspace.init(std.testing.allocator, sessionId(7), "one", .{ .cols = 81, .rows = 25 });
    defer workspace.deinit();
    try workspace.validate();
    const one = workspace.activeTab();
    const two = try workspace.createTab("two");
    const three = try workspace.createTab("three");
    try workspace.validate();
    var order_storage: [max_tabs]TabId = undefined;
    try std.testing.expectEqualSlices(TabId, &.{ one, two.tab, three.tab }, workspace.tabOrder(&order_storage));
    try std.testing.expect(try workspace.switchTab(two.tab));
    try std.testing.expect(try workspace.reorderTab(one, 2));
    try std.testing.expectEqual(two.tab, workspace.activeTab());
    try std.testing.expect(try workspace.renameTab(two.tab, "second"));
    try std.testing.expect(!(try workspace.renameTab(two.tab, "second")));
    try std.testing.expectEqualStrings("second", try workspace.tabName(two.tab));
    var removed: [max_panes_per_tab]PaneId = undefined;
    try std.testing.expectEqualSlices(PaneId, &.{two.pane}, try workspace.closeTab(two.tab, &removed));
    try std.testing.expectEqual(three.tab, workspace.activeTab());
    const removed_one = try workspace.closeTab(one, &removed);
    try std.testing.expectEqual(@as(usize, 1), removed_one.len);
    try std.testing.expectError(error.LastTab, workspace.closeTab(three.tab, &removed));
    try std.testing.expectError(error.StaleTab, workspace.switchTab(two.tab));
    try std.testing.expectError(error.InvalidOrder, workspace.reorderTab(three.tab, 1));
    try std.testing.expectError(error.InvalidName, workspace.renameTab(three.tab, ""));
    try std.testing.expectEqualStrings("three", try workspace.tabName(three.tab));
    try workspace.validate();
}

test "workspace split focus close and odd geometry are deterministic" {
    var workspace = try Workspace.init(std.testing.allocator, sessionId(1), "tab", .{ .cols = 81, .rows = 25 });
    defer workspace.deinit();
    const tab = workspace.activeTab();
    const first = workspace.focusedPane();
    const right = try workspace.splitPane(tab, first, .horizontal);
    const bottom_right = try workspace.splitPane(tab, right, .vertical);
    try workspace.validate();

    var layouts: [max_panes_per_tab]PaneLayout = undefined;
    const placed = try workspace.layout(tab, &layouts);
    try std.testing.expectEqual(@as(usize, 3), placed.len);
    try std.testing.expectEqual(Rect{ .col = 0, .row = 0, .cols = 40, .rows = 25 }, placed[0].rect);
    try std.testing.expectEqual(Rect{ .col = 40, .row = 0, .cols = 41, .rows = 12 }, placed[1].rect);
    try std.testing.expectEqual(Rect{ .col = 40, .row = 12, .cols = 41, .rows = 13 }, placed[2].rect);
    try std.testing.expectEqual(bottom_right, workspace.focusedPane());
    try std.testing.expect(workspace.focus(.up));
    try std.testing.expectEqual(right, workspace.focusedPane());
    try std.testing.expect(workspace.focus(.left));
    try std.testing.expectEqual(first, workspace.focusedPane());
    try std.testing.expect(!workspace.focus(.left));
    try std.testing.expect(try workspace.resize(.{ .cols = 82, .rows = 26 }));
    try std.testing.expect(!(try workspace.resize(.{ .cols = 82, .rows = 26 })));

    try std.testing.expectEqual(first, try workspace.closePane(tab, first));
    try std.testing.expectEqual(right, workspace.focusedPane());
    try std.testing.expectEqual(right, try workspace.closePane(tab, right));
    try std.testing.expectEqual(bottom_right, workspace.focusedPane());
    try std.testing.expectError(error.LastPane, workspace.closePane(tab, bottom_right));
    try std.testing.expectError(error.StalePane, workspace.closePane(tab, @enumFromInt(999)));
    try workspace.validate();
}

test "workspace divider resize owns nested minimum saturation and outer clamping" {
    var workspace = try Workspace.init(std.testing.allocator, sessionId(1), "tab", .{ .cols = 81, .rows = 25 });
    defer workspace.deinit();
    const tab = workspace.activeTab();
    const left = workspace.focusedPane();
    const right = try workspace.splitPane(tab, left, .horizontal);
    const bottom_right = try workspace.splitPane(tab, right, .vertical);
    var layouts: [max_panes_per_tab]PaneLayout = undefined;

    try std.testing.expect(try workspace.resizePane(tab, bottom_right, .up, 5));
    var placed = try workspace.layout(tab, &layouts);
    try std.testing.expectEqual(Rect{ .col = 40, .row = 0, .cols = 41, .rows = 7 }, placed[1].rect);
    try std.testing.expectEqual(Rect{ .col = 40, .row = 7, .cols = 41, .rows = 18 }, placed[2].rect);
    try std.testing.expect(try workspace.resizePane(tab, bottom_right, .left, 5));
    placed = try workspace.layout(tab, &layouts);
    try std.testing.expectEqual(@as(u16, 35), placed[0].rect.cols);
    try std.testing.expectEqual(@as(u16, 46), placed[1].rect.cols);
    try std.testing.expect(try workspace.resizePane(tab, bottom_right, .left, max_cols));
    try std.testing.expect(!(try workspace.resizePane(tab, bottom_right, .left, 1)));
    try std.testing.expect(!(try workspace.resizePane(tab, bottom_right, .right, 1)));
    placed = try workspace.layout(tab, &layouts);
    try std.testing.expectEqual(min_pane_cols, placed[0].rect.cols);

    try std.testing.expect(try workspace.resize(.{ .cols = 100, .rows = 30 }));
    placed = try workspace.layout(tab, &layouts);
    try std.testing.expectEqual(min_pane_cols, placed[0].rect.cols);
    try std.testing.expectEqual(@as(u16, 7), placed[1].rect.rows);
    try std.testing.expect(try workspace.resize(.{ .cols = 6, .rows = 2 }));
    placed = try workspace.layout(tab, &layouts);
    try std.testing.expectEqual(Rect{ .col = 0, .row = 0, .cols = 2, .rows = 2 }, placed[0].rect);
    try std.testing.expectEqual(Rect{ .col = 2, .row = 0, .cols = 4, .rows = 1 }, placed[1].rect);
    try std.testing.expectEqual(Rect{ .col = 2, .row = 1, .cols = 4, .rows = 1 }, placed[2].rect);
    try std.testing.expectError(error.GeometryLimit, workspace.resize(.{ .cols = 5, .rows = 1 }));
    try std.testing.expectEqual(Size{ .cols = 6, .rows = 2 }, workspace.size);
    const preserved = try workspace.layout(tab, &layouts);
    try std.testing.expectEqual(Rect{ .col = 0, .row = 0, .cols = 2, .rows = 2 }, preserved[0].rect);
    try workspace.validate();
}

test "workspace outer resize preflights every tab before committing extents" {
    var workspace = try Workspace.init(std.testing.allocator, sessionId(1), "one", .{ .cols = 20, .rows = 4 });
    defer workspace.deinit();
    const first_tab = workspace.activeTab();
    const right = try workspace.splitPane(first_tab, workspace.focusedPane(), .horizontal);
    try std.testing.expectEqual(right, workspace.focusedPane());
    const second_tab = try workspace.createTab("two");
    const bottom = try workspace.splitPane(second_tab.tab, second_tab.pane, .vertical);
    try std.testing.expectEqual(bottom, workspace.tabs[1].focused);
    const first_extent = workspace.tabs[0].nodes[workspace.tabs[0].root].split.first_extent;
    const second_extent = workspace.tabs[1].nodes[workspace.tabs[1].root].split.first_extent;

    try std.testing.expectError(error.GeometryLimit, workspace.resize(.{ .cols = 6, .rows = 1 }));
    try std.testing.expectEqual(Size{ .cols = 20, .rows = 4 }, workspace.size);
    try std.testing.expectEqual(first_extent, workspace.tabs[0].nodes[workspace.tabs[0].root].split.first_extent);
    try std.testing.expectEqual(second_extent, workspace.tabs[1].nodes[workspace.tabs[1].root].split.first_extent);
    try workspace.validate();
}

test "workspace direct focus accepts only active pane identities" {
    var workspace = try Workspace.init(std.testing.allocator, sessionId(1), "one", .{ .cols = 80, .rows = 24 });
    defer workspace.deinit();
    const first_tab = workspace.activeTab();
    const first = workspace.focusedPane();
    const right = try workspace.splitPane(first_tab, first, .horizontal);
    const second = try workspace.createTab("two");
    try std.testing.expect(try workspace.focusPane(first));
    try std.testing.expect(!(try workspace.focusPane(first)));
    try std.testing.expectError(error.StalePane, workspace.focusPane(second.pane));
    try std.testing.expect(try workspace.focusPane(right));
    try std.testing.expect(try workspace.switchTab(second.tab));
    try std.testing.expectError(error.StalePane, workspace.focusPane(right));
    try workspace.validate();
}

test "workspace close reports exact retired panes before identity disappears" {
    var workspace = try Workspace.init(std.testing.allocator, sessionId(1), "one", .{ .cols = 80, .rows = 24 });
    defer workspace.deinit();
    const first_tab = workspace.activeTab();
    const first = workspace.focusedPane();
    const second = try workspace.splitPane(first_tab, first, .horizontal);
    const third = try workspace.splitPane(first_tab, second, .vertical);
    const other = try workspace.createTab("two");
    var removed: [max_panes_per_tab]PaneId = undefined;
    try std.testing.expectEqualSlices(PaneId, &.{ first, second, third }, try workspace.closeTab(first_tab, &removed));
    var layouts: [max_panes_per_tab]PaneLayout = undefined;
    try std.testing.expectError(error.StaleTab, workspace.layout(first_tab, &layouts));
    try std.testing.expectEqual(other.tab, workspace.activeTab());
    try workspace.validate();
}

test "workspace validation rejects hostile topology before recursive layout" {
    var workspace = try Workspace.init(std.testing.allocator, sessionId(1), "one", .{ .cols = 80, .rows = 24 });
    defer workspace.deinit();
    const tab_id = workspace.activeTab();
    const first = workspace.focusedPane();
    const second = try workspace.splitPane(tab_id, first, .horizontal);
    const tab = &workspace.tabs[0];
    const root = tab.root;
    const original = tab.nodes;

    tab.nodes[root].split.first = root;
    try std.testing.expectError(error.InvalidWorkspace, workspace.validate());
    tab.nodes = original;

    const free = tab.findFree(no_node).?;
    tab.nodes[free] = .{ .pane = @enumFromInt(999) };
    try std.testing.expectError(error.InvalidWorkspace, workspace.validate());
    tab.nodes = original;

    const second_node = tab.findPane(second).?;
    tab.nodes[second_node] = .{ .pane = first };
    try std.testing.expectError(error.InvalidWorkspace, workspace.validate());
    tab.nodes = original;

    const nested = try workspace.splitPane(tab_id, second, .vertical);

    workspace.next_pane = @intFromEnum(nested);
    try std.testing.expectError(error.InvalidWorkspace, workspace.validate());
    workspace.next_pane = @intFromEnum(nested) + 1;
    try workspace.validate();
}

test "workspace validation rejects a split beyond the owned depth bound" {
    var workspace = try Workspace.init(std.testing.allocator, sessionId(1), "deep", .{ .cols = max_cols, .rows = 1 });
    defer workspace.deinit();
    const tab_id = workspace.activeTab();
    var pane = workspace.focusedPane();
    for (0..max_split_depth) |_| pane = try workspace.splitPane(tab_id, pane, .horizontal);
    const tab = &workspace.tabs[0];
    const pane_node = tab.findPane(pane).?;
    const first = tab.findFree(pane_node).?;
    const second = tab.findFree(first).?;
    tab.nodes[first] = .{ .pane = pane };
    tab.nodes[second] = .{ .pane = @enumFromInt(workspace.next_pane) };
    tab.nodes[pane_node] = .{ .split = .{
        .axis = .vertical,
        .first = first,
        .second = second,
        .first_extent = 1,
    } };
    tab.pane_count += 1;
    workspace.pane_count += 1;
    workspace.next_pane += 1;
    try std.testing.expectError(error.InvalidWorkspace, workspace.validate());
}

test "workspace depth count and geometry limits preserve exact state" {
    var workspace = try Workspace.init(std.testing.allocator, sessionId(1), "deep", .{ .cols = max_cols, .rows = 1 });
    defer workspace.deinit();
    const tab = workspace.activeTab();
    var pane = workspace.focusedPane();
    for (0..max_split_depth) |_| pane = try workspace.splitPane(tab, pane, .horizontal);
    try std.testing.expectError(error.DepthLimit, workspace.splitPane(tab, pane, .vertical));
    try std.testing.expectEqual(@as(u8, max_split_depth + 1), workspace.tabs[0].pane_count);
    try std.testing.expectError(error.GeometryLimit, workspace.resize(.{ .cols = 4, .rows = 1 }));
    try std.testing.expectEqual(Size{ .cols = max_cols, .rows = 1 }, workspace.size);
    try std.testing.expectError(error.InvalidSize, workspace.resize(.{ .cols = 0, .rows = 1 }));
    try workspace.validate();

    while (workspace.tabs[0].pane_count < max_panes_per_tab) {
        const root_first = workspace.tabs[0].firstPane(workspace.tabs[0].root);
        const created = try workspace.splitPane(tab, root_first, .horizontal);
        try std.testing.expectEqual(created, workspace.tabs[0].focused);
    }
    const count_before = workspace.pane_count;
    try std.testing.expectError(error.PaneLimit, workspace.splitPane(tab, workspace.focusedPane(), .vertical));
    try std.testing.expectEqual(count_before, workspace.pane_count);
    try workspace.validate();
}

test "workspace tab and session pane capacities preserve state" {
    var workspace = try Workspace.init(std.testing.allocator, sessionId(1), "0", .{ .cols = 64, .rows = 32 });
    defer workspace.deinit();
    while (workspace.tab_count < max_tabs) {
        var name: [3]u8 = undefined;
        const text = try std.fmt.bufPrint(&name, "{d}", .{workspace.tab_count});
        const created = try workspace.createTab(text);
        try std.testing.expectEqualStrings(text, try workspace.tabName(created.tab));
    }
    const tab_count = workspace.tab_count;
    const pane_count = workspace.pane_count;
    try std.testing.expectError(error.TabLimit, workspace.createTab("overflow"));
    try std.testing.expectEqual(tab_count, workspace.tab_count);
    try std.testing.expectEqual(pane_count, workspace.pane_count);
    try workspace.validate();
}

test "workspace enforces the session pane bound across valid tabs" {
    var workspace = try Workspace.init(
        std.testing.allocator,
        sessionId(1),
        "0",
        .{ .cols = max_cols, .rows = max_rows },
    );
    defer workspace.deinit();
    var tabs: [4]TabId = undefined;
    tabs[0] = workspace.activeTab();
    for (1..tabs.len) |index| {
        var name: [1]u8 = .{@intCast('0' + index)};
        tabs[index] = (try workspace.createTab(&name)).tab;
    }
    for (tabs) |tab| try fillTab(&workspace, tab);
    try std.testing.expectEqual(max_panes, workspace.pane_count);
    try std.testing.expectError(error.PaneLimit, workspace.createTab("blocked"));
    try workspace.validate();
}

fn fillTab(workspace: *Workspace, tab_id: TabId) !void {
    var layouts: [max_panes_per_tab]PaneLayout = undefined;
    while (workspace.tabs[try workspace.tabIndex(tab_id)].pane_count < max_panes_per_tab) {
        const placed = try workspace.layout(tab_id, &layouts);
        var split = false;
        for (placed) |layout_value| {
            const tab = &workspace.tabs[try workspace.tabIndex(tab_id)];
            const node = tab.findPane(layout_value.pane).?;
            if (tab.depth(node) >= max_split_depth) continue;
            if (layout_value.rect.cols >= min_pane_cols * 2) {
                const created = try workspace.splitPane(tab_id, layout_value.pane, .horizontal);
                try std.testing.expectEqual(created, workspace.tabs[try workspace.tabIndex(tab_id)].focused);
                split = true;
                break;
            }
            if (layout_value.rect.rows >= min_pane_rows * 2) {
                const created = try workspace.splitPane(tab_id, layout_value.pane, .vertical);
                try std.testing.expectEqual(created, workspace.tabs[try workspace.tabIndex(tab_id)].focused);
                split = true;
                break;
            }
        }
        try std.testing.expect(split);
    }
}

test "workspace name allocations roll back exactly" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var workspace = try Workspace.init(allocator, sessionId(1), "one", .{ .cols = 80, .rows = 24 });
    defer workspace.deinit();
    const first = workspace.activeTab();
    const created = workspace.createTab("two") catch |failure| {
        try std.testing.expectEqual(@as(u8, 1), workspace.tab_count);
        try std.testing.expectEqual(@as(u8, 1), workspace.pane_count);
        try std.testing.expectEqualStrings("one", try workspace.tabName(first));
        try workspace.validate();
        return failure;
    };
    const renamed = workspace.renameTab(created.tab, "renamed") catch |failure| {
        try std.testing.expectEqual(@as(u8, 2), workspace.tab_count);
        try std.testing.expectEqualStrings("two", try workspace.tabName(created.tab));
        try workspace.validate();
        return failure;
    };
    try std.testing.expect(renamed);
    try std.testing.expectEqualStrings("renamed", try workspace.tabName(created.tab));
    try workspace.validate();
}

test "workspace rejects zero and exhausted identities without mutation" {
    try std.testing.expectError(
        error.InvalidSession,
        Workspace.init(std.testing.allocator, @enumFromInt(0), "zero", .{ .cols = 80, .rows = 24 }),
    );
    var workspace = try Workspace.init(std.testing.allocator, sessionId(1), "one", .{ .cols = 80, .rows = 24 });
    defer workspace.deinit();
    workspace.next_tab = std.math.maxInt(u64);
    try std.testing.expectError(error.IdExhausted, workspace.createTab("two"));
    workspace.next_tab = 2;
    workspace.next_pane = std.math.maxInt(u64);
    try std.testing.expectError(error.IdExhausted, workspace.createTab("two"));
    try std.testing.expectEqual(@as(u8, 1), workspace.tab_count);
    try workspace.validate();
}
