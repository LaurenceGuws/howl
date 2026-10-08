const std = @import("std");

/// Maximum leaves on one tab; topology requires exactly twice this minus one nodes.
pub const pane_limit: u8 = 8;
/// Side-by-side or top/bottom application layout, outside canonical terminal state.
pub const Axis = enum { horizontal, vertical };
/// Directional application focus/swap/resize intent.
pub const Direction = enum { left, right, up, down };
/// Logical window rectangle; no cell or canonical geometry authority.
pub const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    /// Tests the half-open pointer hit surface.
    pub fn contains(self: Rect, x: f32, y: f32) bool {
        return x >= self.x and y >= self.y and x < self.x + self.width and y < self.y + self.height;
    }
};
/// One visible pane slot and its current application rectangle.
pub const Placement = struct { pane: u8, rect: Rect };
/// One split's draggable divider; node identity stays inside its exact tab.
pub const Divider = struct { node: u8, axis: Axis, rect: Rect, parent: Rect };

const Split = struct { axis: Axis, first: u8, second: u8, ratio: f32 = 0.5 };
const Node = union(enum) { free, pane: u8, split: Split };

/// Fixed bounded pane topology. No heap nodes, terminal identities or transport state.
pub const Tree = struct {
    nodes: [pane_limit * 2 - 1]Node = @splat(.free),
    count: u8 = 1,
    active: u8 = 0,
    zoomed: bool = false,

    /// Creates a single pane in slot zero.
    pub fn init() Tree {
        var tree: Tree = .{};
        tree.nodes[0] = .{ .pane = 0 };
        return tree;
    }

    /// Splits the active leaf and returns a free pane slot; failure leaves topology untouched.
    pub fn split(self: *Tree, axis: Axis) error{PaneLimit}!u8 {
        if (self.count == pane_limit) return error.PaneLimit;
        var used: u8 = 0;
        var leaf: ?u8 = null;
        var first: ?u8 = null;
        var second: ?u8 = null;
        for (self.nodes, 0..) |node, index| switch (node) {
            .free => if (first == null) {
                first = @intCast(index);
            } else if (second == null) {
                second = @intCast(index);
            },
            .pane => |pane| {
                used |= @as(u8, 1) << @intCast(pane);
                if (pane == self.active) leaf = @intCast(index);
            },
            .split => {},
        };
        var slot: u8 = 0;
        while (used & (@as(u8, 1) << @intCast(slot)) != 0) : (slot += 1) {}
        std.debug.assert(slot < pane_limit and first != null and second != null and leaf != null);
        self.nodes[first.?] = .{ .pane = self.active };
        self.nodes[second.?] = .{ .pane = slot };
        self.nodes[leaf.?] = .{ .split = .{ .axis = axis, .first = first.?, .second = second.? } };
        self.active = slot;
        self.count += 1;
        self.zoomed = false;
        return slot;
    }

    /// Collapses the active leaf while preserving the complete sibling subtree.
    pub fn close(self: *Tree) error{LastPane}!u8 {
        if (self.count == 1) return error.LastPane;
        const retiring = self.active;
        const leaf = self.leafIndex(retiring).?;
        const parent = self.parentIndex(leaf).?;
        const branch = self.nodes[parent].split;
        const sibling = if (branch.first == leaf) branch.second else branch.first;
        self.nodes[parent] = self.nodes[sibling];
        self.nodes[sibling] = .free;
        self.nodes[leaf] = .free;
        self.count -= 1;
        self.active = self.firstPane(parent);
        self.zoomed = false;
        return retiring;
    }

    /// Returns placements and divider facts in stable tree order.
    pub fn layout(self: *const Tree, rect: Rect, placements: *[pane_limit]Placement, dividers: *[pane_limit - 1]Divider) struct { panes: u8, dividers: u8 } {
        if (self.zoomed) {
            placements[0] = .{ .pane = self.active, .rect = rect };
            return .{ .panes = 1, .dividers = 0 };
        }
        var result: struct { panes: u8, dividers: u8 } = .{ .panes = 0, .dividers = 0 };
        self.project(0, rect, placements, &result.panes, dividers, &result.dividers);
        return .{ .panes = result.panes, .dividers = result.dividers };
    }

    /// Applies a pointer to one exact divider's parent surface.
    pub fn drag(self: *Tree, divider: Divider, x: f32, y: f32) void {
        if (divider.node >= self.nodes.len or self.nodes[divider.node] != .split) return;
        const branch = &self.nodes[divider.node].split;
        const span = if (branch.axis == .horizontal) divider.parent.width else divider.parent.height;
        if (!std.math.isFinite(span) or span <= 0 or !std.math.isFinite(x) or !std.math.isFinite(y)) return;
        const at = if (branch.axis == .horizontal) x - divider.parent.x else y - divider.parent.y;
        branch.ratio = std.math.clamp(at / span, 0.1, 0.9);
    }

    /// Finds a directional neighbor by nonnegative edge distance, then cross-axis distance.
    pub fn neighbor(self: *const Tree, rect: Rect, direction: Direction) ?u8 {
        var places: [pane_limit]Placement = undefined;
        var dividers: [pane_limit - 1]Divider = undefined;
        var unzoomed = self.*;
        unzoomed.zoomed = false;
        const result = unzoomed.layout(rect, &places, &dividers);
        var current: Rect = undefined;
        for (places[0..result.panes]) |place| if (place.pane == self.active) {
            current = place.rect;
            break;
        };
        const cx = current.x + current.width / 2;
        const cy = current.y + current.height / 2;
        var best: ?u8 = null;
        var score: f32 = std.math.inf(f32);
        for (places[0..result.panes]) |place| {
            if (place.pane == self.active) continue;
            const dx = place.rect.x + place.rect.width / 2 - cx;
            const dy = place.rect.y + place.rect.height / 2 - cy;
            const gap: ?f32 = switch (direction) {
                .left => if (place.rect.x + place.rect.width <= current.x + 0.01) current.x - (place.rect.x + place.rect.width) else null,
                .right => if (place.rect.x >= current.x + current.width - 0.01) place.rect.x - (current.x + current.width) else null,
                .up => if (place.rect.y + place.rect.height <= current.y + 0.01) current.y - (place.rect.y + place.rect.height) else null,
                .down => if (place.rect.y >= current.y + current.height - 0.01) place.rect.y - (current.y + current.height) else null,
            };
            const along = gap orelse continue;
            const cross = switch (direction) {
                .left, .right => @abs(dy),
                .up, .down => @abs(dx),
            };
            const candidate = along * 10000 + cross;
            if (candidate < score) {
                score = candidate;
                best = place.pane;
            }
        }
        return best;
    }

    /// Swaps two pane slots without moving any terminal lifetime.
    pub fn swap(self: *Tree, other: u8) bool {
        const a = self.leafIndex(self.active) orelse return false;
        const b = self.leafIndex(other) orelse return false;
        self.nodes[a] = .{ .pane = other };
        self.nodes[b] = .{ .pane = self.active };
        return a != b;
    }

    /// Adjusts the nearest ancestor divider along the requested axis.
    pub fn resize(self: *Tree, direction: Direction) bool {
        var child = self.leafIndex(self.active) orelse return false;
        const axis: Axis = switch (direction) {
            .left, .right => .horizontal,
            .up, .down => .vertical,
        };
        while (self.parentIndex(child)) |parent_node| {
            const branch = &self.nodes[parent_node].split;
            if (branch.axis == axis) {
                const delta: f32 = switch (direction) {
                    .left, .up => -0.05,
                    .right, .down => 0.05,
                };
                const next = std.math.clamp(branch.ratio + delta, 0.1, 0.9);
                if (next == branch.ratio) return false;
                branch.ratio = next;
                return true;
            }
            child = parent_node;
        }
        return false;
    }

    fn leafIndex(self: *const Tree, pane: u8) ?u8 {
        for (self.nodes, 0..) |node, i| if (node == .pane and node.pane == pane) return @intCast(i);
        return null;
    }

    fn parentIndex(self: *const Tree, child: u8) ?u8 {
        for (self.nodes, 0..) |node, i| if (node == .split and (node.split.first == child or node.split.second == child)) return @intCast(i);
        return null;
    }

    fn firstPane(self: *const Tree, root: u8) u8 {
        var at = root;
        while (self.nodes[at] == .split) at = self.nodes[at].split.first;
        std.debug.assert(self.nodes[at] == .pane);
        return self.nodes[at].pane;
    }

    fn project(self: *const Tree, index: u8, rect: Rect, places: *[pane_limit]Placement, count: *u8, dividers: *[pane_limit - 1]Divider, divider_count: *u8) void {
        const node = self.nodes[index];
        if (node == .pane) {
            places[count.*] = .{ .pane = node.pane, .rect = rect };
            count.* += 1;
            return;
        }
        std.debug.assert(node == .split);
        const branch = node.split;
        var first = rect;
        var second = rect;
        var lane = rect;
        if (branch.axis == .horizontal) {
            first.width = rect.width * branch.ratio;
            second.x += first.width;
            second.width -= first.width;
            lane.x = second.x - 4;
            lane.width = 8;
        } else {
            first.height = rect.height * branch.ratio;
            second.y += first.height;
            second.height -= first.height;
            lane.y = second.y - 4;
            lane.height = 8;
        }
        dividers[divider_count.*] = .{ .node = index, .axis = branch.axis, .rect = lane, .parent = rect };
        divider_count.* += 1;
        self.project(branch.first, first, places, count, dividers, divider_count);
        self.project(branch.second, second, places, count, dividers, divider_count);
    }
};

test "eight nested panes fill disjoint slots; failed ninth split and final close leave topology unchanged" {
    var tree = Tree.init();
    for (0..7) |i| try std.testing.expectEqual(@as(u8, @intCast(i + 1)), try tree.split(if (i % 2 == 0) .horizontal else .vertical));
    const full = tree;
    try std.testing.expectError(error.PaneLimit, tree.split(.horizontal));
    try std.testing.expectEqualDeep(full, tree);
    while (tree.count > 1) {
        const retired = try tree.close();
        try std.testing.expect(retired < pane_limit);
    }
    const last = tree;
    try std.testing.expectError(error.LastPane, tree.close());
    try std.testing.expectEqualDeep(last, tree);
}

test "closing a parent leaf promotes its complete nested sibling and directional swap preserves focus identity" {
    var tree = Tree.init();
    try std.testing.expectEqual(@as(u8, 1), try tree.split(.horizontal));
    try std.testing.expectEqual(@as(u8, 2), try tree.split(.vertical));
    tree.active = 0;
    try std.testing.expectEqual(@as(u8, 0), try tree.close());
    try std.testing.expectEqual(@as(u8, 2), tree.count);
    var places: [pane_limit]Placement = undefined;
    var dividers: [pane_limit - 1]Divider = undefined;
    const rect: Rect = .{ .x = 0, .y = 0, .width = 1000, .height = 600 };
    const result = tree.layout(rect, &places, &dividers);
    try std.testing.expectEqual(@as(u8, 2), result.panes);
    try std.testing.expectEqual(@as(f32, 1000), places[0].rect.width);
    const neighbor = tree.neighbor(rect, .down) orelse return error.MissingNeighbor;
    const focused = tree.active;
    try std.testing.expect(tree.swap(neighbor));
    try std.testing.expectEqual(focused, tree.active);
    try std.testing.expect(tree.neighbor(rect, .up) != null);
}

test "divider drag clamps outside the parent and rejects a nonfinite pointer" {
    var tree = Tree.init();
    try std.testing.expectEqual(@as(u8, 1), try tree.split(.horizontal));
    var places: [pane_limit]Placement = undefined;
    var dividers: [pane_limit - 1]Divider = undefined;
    const rect: Rect = .{ .x = 20, .y = 10, .width = 1000, .height = 600 };
    const result = tree.layout(rect, &places, &dividers);
    try std.testing.expectEqual(@as(u8, 1), result.dividers);
    tree.drag(dividers[0], -100, 20);
    const clamped = tree;
    tree.drag(dividers[0], std.math.nan(f32), 20);
    try std.testing.expectEqualDeep(clamped, tree);
    const accepted = tree.layout(rect, &places, &dividers);
    try std.testing.expectEqual(@as(u8, 2), accepted.panes);
    try std.testing.expectEqual(@as(f32, 100), places[0].rect.width);
}
