//! Owns ordered named tabs, active identity, and global pane identity admission.
//!
//! Screen composes Tab and TiledPanes without terminal, platform, renderer, or
//! input policy. Names are its only allocated topology state.
//! Zero or duplicate Screen-issued identities and invalid retained geometry are
//! programmer-invariant violations. Forwarding methods panic at that internal
//! boundary rather than advertising impossible failures to callers.

const std = @import("std");
const tab_module = @import("tab.zig");
const tiled = @import("tiled_panes.zig");

/// One screen admits exactly sixteen ordered tabs at most.
pub const tab_limit: u8 = 16;
/// One screen admits exactly sixty-four pane identities across all tabs.
pub const live_pane_limit: u8 = 64;

/// Stable nonzero tab identity never reused by one Screen.
pub const TabId = enum(u64) { _ };
/// Stable nonzero pane identity never reused by one Screen.
pub const PaneId = tiled.PaneId;
/// Tiled-pane split axis.
pub const SplitAxis = tiled.SplitAxis;
/// Spatial focus and divider direction.
pub const Direction = tiled.Direction;
/// Bounded screen grid dimensions.
pub const GridSize = tiled.GridSize;
/// Exact pane grid rectangle.
pub const Rect = tiled.Rect;
/// Borrowed pane placement fact.
pub const Placement = tiled.Placement;

/// Stable identities created by one complete tab transaction.
pub const CreatedTab = struct {
    /// New stable tab identity.
    tab: TabId,
    /// New stable initial pane identity.
    pane: PaneId,
};

const Entry = struct {
    id: TabId,
    tab: tab_module.Tab,
};

/// Owns bounded tab order, active identity, and global stable identity issuance.
pub const Screen = struct {
    /// Allocator passed to every tab and retained name operation.
    allocator: std.mem.Allocator,
    /// Fixed ordered tab storage; only `tabs[0..tab_count]` is live.
    tabs: [tab_limit]Entry = undefined,
    /// Exact nonzero count of live ordered tabs.
    tab_count: u8 = 0,
    /// Zero-based active index within the live tab slice.
    active_index: u8 = 0,
    /// Exact aggregate pane count across every live tab.
    live_panes: u8 = 0,
    /// Next never-issued nonzero TabId backing value.
    next_tab: u64 = 1,
    /// Next never-issued nonzero PaneId backing value.
    next_pane: u64 = 1,
    /// Grid dimensions shared by every tab.
    size: GridSize,

    /// Construct one Screen with one named active tab and initial pane.
    pub fn init(
        allocator: std.mem.Allocator,
        name: []const u8,
        size: GridSize,
    ) error{ OutOfMemory, InvalidName, InvalidSize }!Screen {
        var result = Screen{ .allocator = allocator, .size = size };
        result.tabs[0] = .{
            .id = tabId(1),
            .tab = tab_module.Tab.init(allocator, name, paneId(1), size) catch |failure| switch (failure) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidName => return error.InvalidName,
                error.InvalidSize => return error.InvalidSize,
                error.InvalidPaneId => std.debug.panic("Screen generated zero initial PaneId", .{}),
            },
        };
        result.tab_count = 1;
        result.live_panes = 1;
        result.next_tab = 2;
        result.next_pane = 2;
        return result;
    }

    /// Release every tab name in reverse display order.
    pub fn deinit(self: *Screen) void {
        var count = self.tab_count;
        while (count > 0) {
            count -= 1;
            self.tabs[count].tab.deinit();
        }
        self.tab_count = 0;
        self.live_panes = 0;
    }

    /// Return the number of ordered tabs.
    pub fn tabCount(self: *const Screen) u8 {
        return self.tab_count;
    }

    /// Return the aggregate number of admitted pane identities.
    pub fn livePaneCount(self: *const Screen) u8 {
        return self.live_panes;
    }

    /// Return the active stable tab identity.
    pub fn activeTab(self: *const Screen) TabId {
        return self.tabs[self.active_index].id;
    }

    /// Return the active tab's focused pane identity.
    pub fn focusedPane(self: *const Screen) PaneId {
        return self.tabs[self.active_index].tab.tiled_panes.focused();
    }

    /// Write current stable tab order into caller-owned fixed storage.
    pub fn tabOrder(self: *const Screen, output: *[tab_limit]TabId) []const TabId {
        for (self.tabs[0..self.tab_count], output[0..self.tab_count]) |entry, *destination| {
            destination.* = entry.id;
        }
        return output[0..self.tab_count];
    }

    /// Borrow one retained tab name until rename, close, or deinit.
    pub fn tabName(self: *const Screen, id: TabId) error{StaleTab}![]const u8 {
        return self.tabs[try self.tabIndex(id)].tab.name();
    }

    /// Create and activate one complete named tab transactionally.
    pub fn createTab(
        self: *Screen,
        name: []const u8,
    ) error{
        OutOfMemory,
        InvalidName,
        TabLimit,
        PaneLimit,
        IdExhausted,
    }!CreatedTab {
        if (self.tab_count == tab_limit) return error.TabLimit;
        if (self.live_panes == live_pane_limit) return error.PaneLimit;
        if (self.next_tab == 0 or self.next_tab == std.math.maxInt(u64) or
            self.next_pane == 0 or self.next_pane == std.math.maxInt(u64)) return error.IdExhausted;
        const new_tab = tabId(self.next_tab);
        const new_pane = paneId(self.next_pane);
        const candidate = tab_module.Tab.init(self.allocator, name, new_pane, self.size) catch |failure| switch (failure) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidName => return error.InvalidName,
            error.InvalidPaneId => std.debug.panic("Screen generated zero PaneId", .{}),
            error.InvalidSize => std.debug.panic("Screen retained invalid grid size", .{}),
        };
        self.tabs[self.tab_count] = .{ .id = new_tab, .tab = candidate };
        self.active_index = self.tab_count;
        self.tab_count += 1;
        self.live_panes += 1;
        self.next_tab += 1;
        self.next_pane += 1;
        return .{ .tab = new_tab, .pane = new_pane };
    }

    /// Close one tab and activate the same position or its preceding neighbor.
    ///
    /// Retired pane identities are written in deterministic layout order.
    pub fn closeTab(
        self: *Screen,
        id: TabId,
        retired: *[tiled.pane_limit]PaneId,
    ) error{ StaleTab, LastTab }![]const PaneId {
        const index = try self.tabIndex(id);
        if (self.tab_count == 1) return error.LastTab;
        var placement_storage: [tiled.pane_limit]Placement = undefined;
        const placed = self.tabs[index].tab.tiled_panes.placements(&placement_storage) catch
            std.debug.panic("Screen retained invalid tab geometry", .{});
        for (placed, retired[0..placed.len]) |placement, *destination| destination.* = placement.pane;
        const removed_count: u8 = @intCast(placed.len);
        self.tabs[index].tab.deinit();
        var cursor = index;
        while (cursor + 1 < self.tab_count) : (cursor += 1) self.tabs[cursor] = self.tabs[cursor + 1];
        self.tab_count -= 1;
        self.live_panes -= removed_count;
        if (index < self.active_index) {
            self.active_index -= 1;
        } else if (index == self.active_index and self.active_index == self.tab_count) {
            self.active_index -= 1;
        }
        return retired[0..removed_count];
    }

    /// Rename one tab transactionally; identical bytes are a no-op.
    pub fn renameTab(
        self: *Screen,
        id: TabId,
        name: []const u8,
    ) error{ OutOfMemory, InvalidName, StaleTab }!bool {
        return self.tabs[try self.tabIndex(id)].tab.rename(name);
    }

    /// Move a stable tab to one valid zero-based display index.
    pub fn reorderTab(
        self: *Screen,
        id: TabId,
        target: u8,
    ) error{ StaleTab, InvalidOrder }!bool {
        if (target >= self.tab_count) return error.InvalidOrder;
        const source = try self.tabIndex(id);
        if (source == target) return false;
        const prior_active = self.active_index;
        const moving = self.tabs[source];
        if (source < target) {
            var index = source;
            while (index < target) : (index += 1) self.tabs[index] = self.tabs[index + 1];
        } else {
            var index = source;
            while (index > target) : (index -= 1) self.tabs[index] = self.tabs[index - 1];
        }
        self.tabs[target] = moving;
        self.active_index = if (prior_active == source)
            target
        else if (source < target and prior_active > source and prior_active <= target)
            prior_active - 1
        else if (source > target and prior_active >= target and prior_active < source)
            prior_active + 1
        else
            prior_active;
        return true;
    }

    /// Activate one stable tab; repetition is a no-op.
    pub fn switchTab(self: *Screen, id: TabId) error{StaleTab}!bool {
        const index = try self.tabIndex(id);
        if (index == self.active_index) return false;
        self.active_index = index;
        return true;
    }

    /// Split one pane in one tab and return a new globally stable identity.
    pub fn splitPane(
        self: *Screen,
        tab_id: TabId,
        target: PaneId,
        axis: SplitAxis,
    ) error{
        StaleTab,
        StalePane,
        PaneLimit,
        GeometryLimit,
        IdExhausted,
    }!PaneId {
        const index = try self.tabIndex(tab_id);
        if (self.live_panes == live_pane_limit or
            self.tabs[index].tab.tiled_panes.paneCount() == tiled.pane_limit) return error.PaneLimit;
        if (self.next_pane == 0 or self.next_pane == std.math.maxInt(u64)) return error.IdExhausted;
        const new_pane = paneId(self.next_pane);
        self.tabs[index].tab.tiled_panes.split(target, new_pane, axis) catch |failure| switch (failure) {
            error.StalePane => return error.StalePane,
            error.PaneLimit => return error.PaneLimit,
            error.GeometryLimit => return error.GeometryLimit,
            error.DuplicatePane => std.debug.panic("Screen reused a live PaneId", .{}),
            error.InvalidPaneId => std.debug.panic("Screen generated zero PaneId", .{}),
        };
        self.live_panes += 1;
        self.next_pane += 1;
        return new_pane;
    }

    /// Close one pane while preserving a valid deterministic focus fallback.
    pub fn closePane(
        self: *Screen,
        tab_id: TabId,
        pane: PaneId,
    ) error{ StaleTab, StalePane, LastPane, GeometryLimit }!void {
        const index = try self.tabIndex(tab_id);
        self.tabs[index].tab.tiled_panes.close(pane) catch |failure| switch (failure) {
            error.StalePane => return error.StalePane,
            error.LastPane => return error.LastPane,
            error.GeometryLimit => return error.GeometryLimit,
        };
        self.live_panes -= 1;
    }

    /// Focus one exact pane in the active tab.
    pub fn focusPane(self: *Screen, pane: PaneId) error{StalePane}!bool {
        return self.tabs[self.active_index].tab.tiled_panes.focusPane(pane) catch |failure| switch (failure) {
            error.StalePane => return error.StalePane,
            error.InvalidGeometry => std.debug.panic("Screen retained invalid focus geometry", .{}),
        };
    }

    /// Focus the active tab pane containing one grid cell.
    pub fn focusAt(self: *Screen, col: u16, row: u16) bool {
        return self.tabs[self.active_index].tab.tiled_panes.focusAt(col, row) catch
            std.debug.panic("Screen retained invalid pointer geometry", .{});
    }

    /// Move active-tab focus in one spatial direction.
    pub fn focusDirection(self: *Screen, direction: Direction) bool {
        return self.tabs[self.active_index].tab.tiled_panes.focusDirection(direction) catch
            std.debug.panic("Screen retained invalid directional geometry", .{});
    }

    /// Move one matching divider in one tab by an integer cell count.
    pub fn resizeDivider(
        self: *Screen,
        tab_id: TabId,
        pane: PaneId,
        direction: Direction,
        cells: u16,
    ) error{ StaleTab, StalePane }!bool {
        return self.tabs[try self.tabIndex(tab_id)].tab.tiled_panes.resizeDivider(pane, direction, cells) catch |failure| switch (failure) {
            error.StalePane => return error.StalePane,
            error.InvalidGeometry => std.debug.panic("Screen retained invalid divider geometry", .{}),
        };
    }

    /// Resize every tab transactionally to one bounded grid.
    pub fn resize(self: *Screen, size: GridSize) error{ InvalidSize, GeometryLimit }!bool {
        if (std.meta.eql(self.size, size)) return false;
        var candidates: [tab_limit]tiled.TiledPanes = undefined;
        for (self.tabs[0..self.tab_count], candidates[0..self.tab_count]) |entry, *candidate| {
            candidate.* = entry.tab.tiled_panes;
            const changed = try candidate.resize(size);
            std.debug.assert(changed);
        }
        for (self.tabs[0..self.tab_count], candidates[0..self.tab_count]) |*entry, candidate| {
            entry.tab.tiled_panes = candidate;
        }
        self.size = size;
        return true;
    }

    /// Write one tab's exact pane placements into caller-owned fixed storage.
    pub fn placements(
        self: *const Screen,
        tab_id: TabId,
        output: *[tiled.pane_limit]Placement,
    ) error{StaleTab}![]const Placement {
        return self.tabs[try self.tabIndex(tab_id)].tab.tiled_panes.placements(output) catch
            std.debug.panic("Screen retained invalid placement geometry", .{});
    }

    /// Validate global bounds, identity uniqueness, order, names, and every tab.
    pub fn validate(self: *const Screen) error{InvalidScreen}!void {
        if (self.tab_count == 0 or self.tab_count > tab_limit or self.active_index >= self.tab_count or
            self.live_panes == 0 or self.live_panes > live_pane_limit) return error.InvalidScreen;
        var pane_ids: [live_pane_limit]PaneId = undefined;
        var pane_count: u8 = 0;
        var maximum_tab: u64 = 0;
        var maximum_pane: u64 = 0;
        for (self.tabs[0..self.tab_count], 0..) |*entry, tab_index| {
            if (@backingInt(entry.id) == 0) return error.InvalidScreen;
            maximum_tab = @max(maximum_tab, @backingInt(entry.id));
            for (self.tabs[0..tab_index]) |prior| if (prior.id == entry.id) return error.InvalidScreen;
            entry.tab.validate() catch return error.InvalidScreen;
            var storage: [tiled.pane_limit]Placement = undefined;
            const placed = entry.tab.tiled_panes.placements(&storage) catch return error.InvalidScreen;
            for (placed) |placement| {
                if (pane_count == live_pane_limit) return error.InvalidScreen;
                for (pane_ids[0..pane_count]) |prior| if (prior == placement.pane) return error.InvalidScreen;
                pane_ids[pane_count] = placement.pane;
                pane_count += 1;
                maximum_pane = @max(maximum_pane, @backingInt(placement.pane));
            }
        }
        if (pane_count != self.live_panes or self.next_tab <= maximum_tab or self.next_pane <= maximum_pane)
            return error.InvalidScreen;
    }

    fn tabIndex(self: *const Screen, id: TabId) error{StaleTab}!u8 {
        for (self.tabs[0..self.tab_count], 0..) |entry, index| {
            if (entry.id == id) return @intCast(index);
        }
        return error.StaleTab;
    }
};

fn tabId(value: u64) TabId {
    return @fromBackingInt(@intCast(value));
}

fn paneId(value: u64) PaneId {
    return @fromBackingInt(@intCast(value));
}

test "screen owns tab order names active identity and deterministic close fallback" {
    var screen = try Screen.init(std.testing.allocator, "one", .{ .cols = 81, .rows = 25 });
    defer screen.deinit();
    const first = screen.activeTab();
    const second = try screen.createTab("two");
    const third = try screen.createTab("three");
    try std.testing.expectEqual(third.tab, screen.activeTab());
    try std.testing.expect(try screen.renameTab(second.tab, "second"));
    try std.testing.expect(try screen.reorderTab(third.tab, 0));
    try std.testing.expectEqual(third.tab, screen.activeTab());
    try std.testing.expect(try screen.switchTab(first));

    var order_storage: [tab_limit]TabId = undefined;
    const order = screen.tabOrder(&order_storage);
    try std.testing.expectEqualSlices(TabId, &.{ third.tab, first, second.tab }, order);
    var retired: [tiled.pane_limit]PaneId = undefined;
    const removed = try screen.closeTab(first, &retired);
    try std.testing.expectEqual(@as(usize, 1), removed.len);
    try std.testing.expectEqual(second.tab, screen.activeTab());
    try std.testing.expectError(error.StaleTab, screen.switchTab(first));
    const removed_active = try screen.closeTab(second.tab, &retired);
    try std.testing.expectEqual(@as(usize, 1), removed_active.len);
    try std.testing.expectEqual(third.tab, screen.activeTab());
    try std.testing.expectError(error.LastTab, screen.closeTab(third.tab, &retired));
    try screen.validate();
}

test "screen pane identities are stable and mutations roll back on failure" {
    var screen = try Screen.init(std.testing.allocator, "one", .{ .cols = 4, .rows = 1 });
    defer screen.deinit();
    const tab = screen.activeTab();
    const first = screen.focusedPane();
    const second = try screen.splitPane(tab, first, .horizontal);
    const before = screen;
    try std.testing.expectError(error.GeometryLimit, screen.splitPane(tab, first, .horizontal));
    try std.testing.expectEqual(before.next_pane, screen.next_pane);
    try std.testing.expectEqual(before.live_panes, screen.live_panes);
    try std.testing.expectError(error.StalePane, screen.focusPane(paneId(999)));
    try screen.closePane(tab, second);
    try std.testing.expectEqual(first, screen.focusedPane());
    try screen.validate();
}

test "screen enforces tab and aggregate pane capacities" {
    var screen = try Screen.init(std.testing.allocator, "one", .{ .cols = 512, .rows = 256 });
    defer screen.deinit();
    while (screen.tabs[screen.active_index].tab.tiled_panes.paneCount() < 4) {
        const focused = screen.focusedPane();
        const axis: SplitAxis = if (screen.livePaneCount() % 2 == 0) .horizontal else .vertical;
        const pane = try screen.splitPane(screen.activeTab(), focused, axis);
        try std.testing.expectEqual(pane, screen.focusedPane());
    }
    while (screen.tabCount() < tab_limit) {
        const created = try screen.createTab("tab");
        while (screen.tabs[screen.active_index].tab.tiled_panes.paneCount() < 4) {
            const focused = screen.focusedPane();
            const axis: SplitAxis = if (screen.livePaneCount() % 2 == 0) .horizontal else .vertical;
            const pane = try screen.splitPane(created.tab, focused, axis);
            try std.testing.expectEqual(pane, screen.focusedPane());
        }
    }
    try std.testing.expectEqual(live_pane_limit, screen.livePaneCount());
    try std.testing.expectError(error.TabLimit, screen.createTab("overflow"));
    try std.testing.expectError(
        error.PaneLimit,
        screen.splitPane(screen.activeTab(), screen.focusedPane(), .horizontal),
    );
    try screen.validate();
}

test "screen allocation failures preserve names order and identities" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var screen = try Screen.init(allocator, "one", .{ .cols = 80, .rows = 24 });
    defer screen.deinit();
    const first = screen.activeTab();
    const second = try screen.createTab("two");
    try std.testing.expectEqual(second.tab, screen.activeTab());
    try std.testing.expectEqualStrings("one", try screen.tabName(first));
    try screen.validate();
}

test "every Screen public operation executes through its direct boundary" {
    var screen = try Screen.init(std.testing.allocator, "one", .{ .cols = 12, .rows = 8 });
    errdefer screen.deinit();
    try std.testing.expectEqual(@as(u8, 1), screen.tabCount());
    try std.testing.expectEqual(@as(u8, 1), screen.livePaneCount());
    const first_tab = screen.activeTab();
    const first_pane = screen.focusedPane();
    var order_storage: [tab_limit]TabId = undefined;
    try std.testing.expectEqualSlices(TabId, &.{first_tab}, screen.tabOrder(&order_storage));
    try std.testing.expectEqualStrings("one", try screen.tabName(first_tab));
    try std.testing.expect(try screen.renameTab(first_tab, "first"));
    try screen.validate();

    const second_tab = try screen.createTab("second");
    try std.testing.expectEqual(second_tab.tab, screen.activeTab());
    try std.testing.expect(try screen.switchTab(first_tab));
    const split_pane = try screen.splitPane(first_tab, first_pane, .horizontal);
    try std.testing.expectEqual(split_pane, screen.focusedPane());
    try std.testing.expect(try screen.focusPane(first_pane));
    try std.testing.expect(screen.focusAt(11, 7));
    try std.testing.expectEqual(split_pane, screen.focusedPane());
    try std.testing.expect(screen.focusDirection(.left));
    try std.testing.expectEqual(first_pane, screen.focusedPane());
    try std.testing.expect(try screen.resizeDivider(first_tab, first_pane, .right, 1));

    var placement_storage: [tiled.pane_limit]Placement = undefined;
    try std.testing.expectEqual(
        @as(usize, 2),
        (try screen.placements(first_tab, &placement_storage)).len,
    );
    try std.testing.expect(try screen.resize(.{ .cols = 14, .rows = 9 }));
    try std.testing.expect(try screen.reorderTab(second_tab.tab, 0));
    try screen.closePane(first_tab, split_pane);
    try std.testing.expectEqual(@as(u8, 2), screen.livePaneCount());
    var retired: [tiled.pane_limit]PaneId = undefined;
    try std.testing.expectEqual(
        @as(usize, 1),
        (try screen.closeTab(second_tab.tab, &retired)).len,
    );
    try std.testing.expectEqual(first_tab, screen.activeTab());
    try screen.validate();
    screen.deinit();
}

test "screen explicit allocation failures preserve prior state" {
    var screen = try Screen.init(std.testing.allocator, "one", .{ .cols = 80, .rows = 24 });
    defer screen.deinit();
    const first = screen.activeTab();
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    screen.allocator = failing.allocator();
    try std.testing.expectError(error.OutOfMemory, screen.createTab("two"));
    try std.testing.expectEqual(@as(u8, 1), screen.tabCount());
    try std.testing.expectEqual(first, screen.activeTab());
    try std.testing.expectEqual(@as(u64, 2), screen.next_tab);
    try std.testing.expectEqual(@as(u64, 2), screen.next_pane);
    try screen.validate();
}

test "screen stale ids exhaustion and invalid order preserve exact state" {
    var screen = try Screen.init(std.testing.allocator, "one", .{ .cols = 80, .rows = 24 });
    defer screen.deinit();
    const before_tab = screen.activeTab();
    const before_pane = screen.focusedPane();
    try std.testing.expectError(error.StaleTab, screen.switchTab(tabId(99)));
    try std.testing.expectError(error.InvalidOrder, screen.reorderTab(before_tab, 1));
    try std.testing.expectError(error.StaleTab, screen.splitPane(tabId(99), before_pane, .horizontal));
    try std.testing.expectEqual(before_tab, screen.activeTab());
    try std.testing.expectEqual(before_pane, screen.focusedPane());

    screen.next_tab = std.math.maxInt(u64);
    try std.testing.expectError(error.IdExhausted, screen.createTab("two"));
    screen.next_tab = 2;
    screen.next_pane = std.math.maxInt(u64);
    try std.testing.expectError(error.IdExhausted, screen.splitPane(before_tab, before_pane, .horizontal));
    screen.next_pane = 2;
    try screen.validate();
}

test "screen resize commits all tabs or preserves all geometry" {
    var screen = try Screen.init(std.testing.allocator, "one", .{ .cols = 8, .rows = 4 });
    defer screen.deinit();
    const first_tab = screen.activeTab();
    const first_pane = screen.focusedPane();
    const second_pane = try screen.splitPane(first_tab, first_pane, .horizontal);
    const second_tab = try screen.createTab("two");
    const fourth_pane = try screen.splitPane(second_tab.tab, second_tab.pane, .vertical);
    try std.testing.expectEqual(fourth_pane, screen.focusedPane());

    var before_first_storage: [tiled.pane_limit]Placement = undefined;
    var before_second_storage: [tiled.pane_limit]Placement = undefined;
    const before_first = try screen.placements(first_tab, &before_first_storage);
    const before_second = try screen.placements(second_tab.tab, &before_second_storage);
    try std.testing.expectError(error.GeometryLimit, screen.resize(.{ .cols = 3, .rows = 1 }));

    var after_first_storage: [tiled.pane_limit]Placement = undefined;
    var after_second_storage: [tiled.pane_limit]Placement = undefined;
    try std.testing.expectEqualSlices(
        Placement,
        before_first,
        try screen.placements(first_tab, &after_first_storage),
    );
    try std.testing.expectEqualSlices(
        Placement,
        before_second,
        try screen.placements(second_tab.tab, &after_second_storage),
    );
    try std.testing.expect(try screen.resize(.{ .cols = 9, .rows = 5 }));
    try std.testing.expectEqual(@as(u16, 9), (try screen.tabs[0].tab.tiled_panes.paneRect(second_pane)).col +
        (try screen.tabs[0].tab.tiled_panes.paneRect(second_pane)).cols);
    try screen.validate();
}
