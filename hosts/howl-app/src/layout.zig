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
pub const Divider = struct { node: u8, axis: Axis, rect: Rect, parent: Rect, ratio: f32 };

/// One segment or an aligned four-way junction captured for one pointer gesture.
pub const Drag = struct {
    dividers: [3]Divider = undefined,
    count: u8 = 0,
    x: f32,
    y: f32,

    /// True when both axes at a four-way junction move together.
    pub fn corner(self: Drag) bool {
        return self.count == 3;
    }

    /// Matches current divider identities after the grab has prepared the tree.
    pub fn contains(self: Drag, node: u8) bool {
        for (self.dividers[0..self.count]) |divider| if (divider.node == node) return true;
        return false;
    }
};

const snap_distance: f32 = 8;
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

    /// Cycles leaves in visual tree order, including while zoomed.
    pub fn cycle(self: *const Tree, reverse: bool) u8 {
        var slots: [pane_limit]u8 = undefined;
        var count: usize = 0;
        self.order(0, &slots, &count);
        var active: usize = 0;
        for (slots[0..count], 0..) |slot, index| if (slot == self.active) {
            active = index;
            break;
        };
        return slots[(active + (if (reverse) count - 1 else @as(usize, 1))) % count];
    }
    fn order(self: *const Tree, node: u8, slots: *[pane_limit]u8, count: *usize) void {
        switch (self.nodes[node]) {
            .pane => |slot| {
                slots[count.*] = slot;
                count.* += 1;
            },
            .split => |branch| {
                self.order(branch.first, slots, count);
                self.order(branch.second, slots, count);
            },
            // zig-audit: acknowledge unreachable
            // reason: Traversal starts at the owned root and follows only live split children; detached free nodes cannot be reached.
            .free => unreachable,
        }
    }
    /// Restores equal halves without replacing panes or altering focus.
    pub fn balance(self: *Tree) void {
        for (&self.nodes) |*node| if (node.* == .split) {
            node.split.ratio = 0.5;
        };
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

    /// Previews the exact grab surface without changing topology or focus.
    pub fn hover(self: *const Tree, rect: Rect, x: f32, y: f32) ?Drag {
        var preview = self.*;
        return preview.grab(rect, x, y);
    }

    /// Captures a segment, transposing aligned crossing cuts without moving panes.
    pub fn grab(self: *Tree, rect: Rect, x: f32, y: f32) ?Drag {
        if (!std.math.isFinite(x) or !std.math.isFinite(y) or !rect.contains(x, y)) return null;
        var places: [pane_limit]Placement = undefined;
        var dividers: [pane_limit - 1]Divider = undefined;
        // Each transpose descends from a shared cut into one of its halves.
        // No allocation, new node, pane movement or terminal identity change.
        for (0..pane_limit) |_| {
            const result = self.layout(rect, &places, &dividers);
            for (dividers[0..result.dividers]) |divider| {
                if (!divider.rect.contains(x, y)) continue;
                if (self.crossing(divider.node)) |cross| {
                    const at = if (cross.axis == .horizontal)
                        divider.parent.x + divider.parent.width * cross.ratio
                    else
                        divider.parent.y + divider.parent.height * cross.ratio;
                    const pointer = if (cross.axis == .horizontal) x else y;
                    if (@abs(pointer - at) <= 4) {
                        var held: Drag = .{ .x = x, .y = y, .count = 1 };
                        held.dividers[0] = divider;
                        const branch = self.nodes[divider.node].split;
                        for (dividers[0..result.dividers]) |other| {
                            if (other.node == branch.first or other.node == branch.second) {
                                held.dividers[held.count] = other;
                                held.count += 1;
                            }
                        }
                        std.debug.assert(held.count == 3);
                        return held;
                    }
                    self.transpose(divider.node);
                    break;
                }
                var held: Drag = .{ .x = x, .y = y, .count = 1 };
                held.dividers[0] = divider;
                return held;
            } else return null;
        }
        return null;
    }

    /// Moves only captured borders, snapping adjacent halves into an exact junction.
    pub fn drag(self: *Tree, held: Drag, x: f32, y: f32) void {
        if (!std.math.isFinite(x) or !std.math.isFinite(y)) return;
        for (held.dividers[0..held.count]) |divider| {
            if (divider.node >= self.nodes.len or self.nodes[divider.node] != .split) continue;
            const branch = &self.nodes[divider.node].split;
            if (branch.axis != divider.axis) continue;
            const span = if (branch.axis == .horizontal) divider.parent.width else divider.parent.height;
            if (!std.math.isFinite(span) or span <= 0) continue;
            const delta = if (branch.axis == .horizontal) x - held.x else y - held.y;
            var ratio = std.math.clamp(divider.ratio + delta / span, 0.1, 0.9);
            if (!held.corner()) {
                if (self.parentIndex(divider.node)) |parent| {
                    const enclosing = self.nodes[parent].split;
                    const sibling = self.nodes[if (enclosing.first == divider.node) enclosing.second else enclosing.first];
                    if (enclosing.axis != branch.axis and sibling == .split and sibling.split.axis == branch.axis and
                        @abs((ratio - sibling.split.ratio) * span) <= snap_distance)
                        ratio = sibling.split.ratio;
                }
            }
            branch.ratio = ratio;
        }
    }

    fn crossing(self: *const Tree, node: u8) ?Split {
        const branch = self.nodes[node].split;
        const a = self.nodes[branch.first];
        const b = self.nodes[branch.second];
        if (a != .split or b != .split or a.split.axis == branch.axis or
            a.split.axis != b.split.axis or a.split.ratio != b.split.ratio) return null;
        return a.split;
    }

    fn transpose(self: *Tree, node: u8) void {
        const branch = self.nodes[node].split;
        const a = self.nodes[branch.first].split;
        const b = self.nodes[branch.second].split;
        std.debug.assert(a.axis == b.axis and a.axis != branch.axis and a.ratio == b.ratio);
        self.nodes[node] = .{ .split = .{ .axis = a.axis, .ratio = a.ratio, .first = branch.first, .second = branch.second } };
        self.nodes[branch.first] = .{ .split = .{ .axis = branch.axis, .ratio = branch.ratio, .first = a.first, .second = b.first } };
        self.nodes[branch.second] = .{ .split = .{ .axis = branch.axis, .ratio = branch.ratio, .first = a.second, .second = b.second } };
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

    /// Moves the active pane's nearest border, detaching aligned halves like a pointer grab.
    pub fn resize(self: *Tree, rect: Rect, direction: Direction) bool {
        var child = self.leafIndex(self.active) orelse return false;
        const axis: Axis = switch (direction) {
            .left, .right => .horizontal,
            .up, .down => .vertical,
        };
        while (self.parentIndex(child)) |parent_node| {
            if (self.nodes[parent_node].split.axis == axis) {
                var places: [pane_limit]Placement = undefined;
                var dividers: [pane_limit - 1]Divider = undefined;
                var visible = self.*;
                visible.zoomed = false;
                const result = visible.layout(rect, &places, &dividers);
                var active_rect: Rect = undefined;
                for (places[0..result.panes]) |place| if (place.pane == self.active) {
                    active_rect = place.rect;
                    break;
                };
                for (dividers[0..result.dividers]) |divider| if (divider.node == parent_node) {
                    const x = if (axis == .horizontal) divider.rect.x + 4 else active_rect.x + active_rect.width / 2;
                    const y = if (axis == .vertical) divider.rect.y + 4 else active_rect.y + active_rect.height / 2;
                    const held = visible.grab(rect, x, y) orelse return false;
                    const first = held.dividers[0];
                    const before = visible.nodes[first.node].split.ratio;
                    const delta: f32 = switch (direction) {
                        .left, .up => -0.05,
                        .right, .down => 0.05,
                    };
                    visible.drag(held, x + (if (axis == .horizontal) first.parent.width * delta else 0), y + (if (axis == .vertical) first.parent.height * delta else 0));
                    if (visible.nodes[first.node].split.ratio == before) return false;
                    visible.zoomed = self.zoomed;
                    self.* = visible;
                    return true;
                };
                return false;
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
        dividers[divider_count.*] = .{ .node = index, .axis = branch.axis, .rect = lane, .parent = rect, .ratio = branch.ratio };
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
    const held = tree.grab(rect, 520, 20).?;
    tree.drag(held, -100, 20);
    const clamped = tree;
    tree.drag(held, std.math.nan(f32), 20);
    try std.testing.expectEqualDeep(clamped, tree);
    const accepted = tree.layout(rect, &places, &dividers);
    try std.testing.expectEqual(@as(u8, 2), accepted.panes);
    try std.testing.expectEqual(@as(f32, 100), places[0].rect.width);
}

test "pane cycling follows visual tree order after splits, swaps, zoom and collapse" {
    var tree = Tree.init();
    const right = try tree.split(.horizontal);
    const bottom = try tree.split(.vertical);
    try std.testing.expectEqual(@as(u8, 0), tree.cycle(false));
    try std.testing.expectEqual(right, tree.cycle(true));
    tree.active = 0;
    try std.testing.expectEqual(right, tree.cycle(false));
    try std.testing.expectEqual(bottom, tree.cycle(true));
    tree.zoomed = true;
    try std.testing.expectEqual(right, tree.cycle(false));
    tree.zoomed = false;
    try std.testing.expect(tree.swap(bottom));
    try std.testing.expectEqual(bottom, tree.cycle(false));
    try std.testing.expect(tree.resize(.{ .x = 0, .y = 0, .width = 1000, .height = 600 }, .left));
    tree.balance();
    for (tree.nodes) |node| if (node == .split) try std.testing.expectEqual(@as(f32, 0.5), node.split.ratio);
    const retired = try tree.close();
    try std.testing.expectEqual(@as(u8, 0), retired);
    try std.testing.expect(tree.cycle(false) != retired);
}

fn testGrid(axis: Axis) !Tree {
    var tree = Tree.init();
    const other: Axis = if (axis == .horizontal) .vertical else .horizontal;
    const right = try tree.split(axis);
    try std.testing.expectEqual(@as(u8, 2), try tree.split(other));
    tree.active = 0;
    try std.testing.expectEqual(@as(u8, 3), try tree.split(other));
    tree.active = right;
    return tree;
}

fn testRects(tree: *const Tree, rect: Rect) [pane_limit]Rect {
    var places: [pane_limit]Placement = undefined;
    var dividers: [pane_limit - 1]Divider = undefined;
    const result = tree.layout(rect, &places, &dividers);
    var rects: [pane_limit]Rect = @splat(.{ .x = 0, .y = 0, .width = 0, .height = 0 });
    for (places[0..result.panes]) |place| rects[place.pane] = place.rect;
    return rects;
}

fn expectTiling(tree: *const Tree, rect: Rect) !void {
    var places: [pane_limit]Placement = undefined;
    var dividers: [pane_limit - 1]Divider = undefined;
    var visible = tree.*;
    visible.zoomed = false;
    const result = visible.layout(rect, &places, &dividers);
    try std.testing.expectEqual(tree.count, result.panes);
    try std.testing.expectEqual(tree.count - 1, result.dividers);
    var seen: u8 = 0;
    var area: f64 = 0;
    for (places[0..result.panes], 0..) |place, i| {
        const mask = @as(u8, 1) << @intCast(place.pane);
        try std.testing.expect(seen & mask == 0);
        seen |= mask;
        const r = place.rect;
        try std.testing.expect(r.width > 0 and r.height > 0);
        try std.testing.expect(r.x >= rect.x - 0.001 and r.y >= rect.y - 0.001);
        try std.testing.expect(r.x + r.width <= rect.x + rect.width + 0.001);
        try std.testing.expect(r.y + r.height <= rect.y + rect.height + 0.001);
        area += @as(f64, r.width) * r.height;
        for (places[0..i]) |other| {
            const overlap_x = @min(r.x + r.width, other.rect.x + other.rect.width) - @max(r.x, other.rect.x);
            const overlap_y = @min(r.y + r.height, other.rect.y + other.rect.height) - @max(r.y, other.rect.y);
            try std.testing.expect(overlap_x <= 0.001 or overlap_y <= 0.001);
        }
    }
    try std.testing.expectApproxEqAbs(@as(f64, rect.width) * rect.height, area, 1);
    try std.testing.expect(seen & (@as(u8, 1) << @intCast(tree.active)) != 0);
}

test "either split order detaches a half, keeps staggered seams shared, snaps and switches axes" {
    const rect: Rect = .{ .x = 20, .y = 30, .width = 1000, .height = 600 };
    for ([_]Axis{ .horizontal, .vertical }) |axis| {
        var tree = try testGrid(axis);
        const before = tree;
        const original = testRects(&tree, rect);
        const x: f32 = if (axis == .horizontal) 520 else 270;
        const y: f32 = if (axis == .horizontal) 180 else 330;
        const preview = tree.hover(rect, x + 1, y + 1).?;
        try std.testing.expect(!preview.corner());
        try std.testing.expectEqualDeep(before, tree);
        const held = tree.grab(rect, x + 1, y + 1).?;
        try std.testing.expectEqualDeep(original, testRects(&tree, rect));
        try std.testing.expectEqual(before.active, tree.active);
        try std.testing.expectEqual(before.count, tree.count);
        const dx: f32 = if (axis == .horizontal) 120 else 0;
        const dy: f32 = if (axis == .vertical) 90 else 0;
        // The off-centre press must not move anything until the pointer moves.
        tree.drag(held, held.x, held.y);
        try std.testing.expectEqualDeep(original, testRects(&tree, rect));
        tree.drag(held, held.x + dx, held.y + dy);
        const detached = testRects(&tree, rect);
        if (axis == .horizontal) {
            try std.testing.expectEqual(@as(f32, 620), detached[0].width);
            try std.testing.expectEqual(original[3], detached[3]);
        } else {
            try std.testing.expectEqual(@as(f32, 390), detached[0].height);
            try std.testing.expectEqual(original[2], detached[2]);
        }
        // The crossing seam now has a T at each end, so it moves as one line.
        const shared = tree.grab(rect, if (axis == .horizontal) 270 else 520, if (axis == .horizontal) 330 else 180).?;
        try std.testing.expect(!shared.corner());
        const shared_branch = tree.nodes[shared.dividers[0].node].split;
        try std.testing.expect(shared_branch.axis != axis);
        // Rejoin within the 8px tolerance; the other half stays exactly fixed.
        tree.drag(held, held.x + (if (axis == .horizontal) @as(f32, 6) else 0), held.y + (if (axis == .vertical) @as(f32, 6) else 0));
        try std.testing.expectEqualDeep(original, testRects(&tree, rect));
        const other = tree.grab(rect, if (axis == .horizontal) 270 else 520, if (axis == .horizontal) 330 else 180).?;
        try std.testing.expect(!other.corner());
        try std.testing.expect(tree.nodes[other.dividers[0].node].split.axis != axis);
        tree.drag(other, other.x + (if (axis == .vertical) @as(f32, 100) else 0), other.y + (if (axis == .horizontal) @as(f32, 60) else 0));
        try expectTiling(&tree, rect);
    }
}

test "junction grab moves both axes, clamps, survives reversal and does not capture T junctions" {
    const rect: Rect = .{ .x = 0, .y = 34, .width = 1000, .height = 600 };
    for ([_]Axis{ .horizontal, .vertical }) |axis| {
        var tree = try testGrid(axis);
        const before = tree;
        const corner = tree.grab(rect, 500, 334).?;
        try std.testing.expect(corner.corner());
        try std.testing.expectEqualDeep(before, tree);
        tree.drag(corner, 650, 394);
        const moved = testRects(&tree, rect);
        try std.testing.expectApproxEqAbs(@as(f32, 650), moved[0].width, 0.001);
        try std.testing.expectApproxEqAbs(@as(f32, 360), moved[0].height, 0.001);
        for (0..100) |i| {
            tree.drag(corner, if (i % 2 == 0) -1000 else 2000, if (i % 2 == 0) -1000 else 2000);
            try expectTiling(&tree, rect);
        }
        tree.drag(corner, 500, 334);
        try std.testing.expectEqualDeep(testRects(&before, rect), testRects(&tree, rect));
        const half = tree.grab(rect, 500, 184).?;
        tree.drag(half, 600, 184);
        try std.testing.expect(!tree.hover(rect, 600, 334).?.corner());
        const invalid_before = tree;
        try std.testing.expect(tree.grab(rect, std.math.nan(f32), 30) == null);
        tree.drag(half, std.math.inf(f32), 30);
        try std.testing.expectEqualDeep(invalid_before, tree);
        tree.zoomed = true;
        try std.testing.expect(tree.grab(rect, 500, 334) == null);
    }
}

test "nested grid rotations preserve eight terminal slots, unaffected subtrees and close ownership" {
    const rect: Rect = .{ .x = 17.25, .y = 35.5, .width = 2392, .height = 1308 };
    var tree = Tree.init();
    try std.testing.expectEqual(@as(u8, 1), try tree.split(.vertical));
    tree.active = 0;
    const right = try tree.split(.horizontal);
    try std.testing.expectEqual(@as(u8, 3), try tree.split(.vertical));
    tree.active = 0;
    try std.testing.expectEqual(@as(u8, 4), try tree.split(.vertical));
    // Subdivide each corner further; transposition retains entire subtrees.
    for ([_]u8{ 0, right, 3 }, 0..) |slot, i| {
        tree.active = slot;
        try std.testing.expectEqual(@as(u8, @intCast(5 + i)), try tree.split(.horizontal));
    }
    try std.testing.expectEqual(@as(u8, 8), tree.count);
    const before = testRects(&tree, rect);
    const held = tree.grab(rect, rect.x + rect.width / 2, rect.y + rect.height / 8).?;
    try std.testing.expectEqualDeep(before, testRects(&tree, rect));
    for (0..1000) |i| {
        const dx = @as(f32, @floatFromInt(i % 451)) - 225;
        tree.drag(held, held.x + dx, held.y);
        try expectTiling(&tree, rect);
        try std.testing.expectEqual(before[1], testRects(&tree, rect)[1]);
    }
    const full = tree;
    try std.testing.expectError(error.PaneLimit, tree.split(.vertical));
    try std.testing.expectEqualDeep(full, tree);
    while (tree.count > 1) {
        const retired = try tree.close();
        try std.testing.expect(retired < pane_limit);
        try expectTiling(&tree, rect);
    }
}

test "keyboard resize detaches either aligned half and keeps focus and zoom identity" {
    const rect: Rect = .{ .x = 0, .y = 34, .width = 1000, .height = 600 };
    for ([_]Axis{ .horizontal, .vertical }) |axis| {
        var tree = try testGrid(axis);
        tree.active = 0;
        tree.zoomed = true;
        const original = tree;
        try std.testing.expect(tree.resize(rect, if (axis == .horizontal) .right else .down));
        try std.testing.expect(tree.zoomed);
        try std.testing.expectEqual(@as(u8, 0), tree.active);
        tree.zoomed = false;
        var visible = original;
        visible.zoomed = false;
        const before = testRects(&visible, rect);
        const after = testRects(&tree, rect);
        try std.testing.expectEqual(before[if (axis == .horizontal) @as(usize, 3) else 2], after[if (axis == .horizontal) @as(usize, 3) else 2]);
        try std.testing.expect(after[0].width > before[0].width or after[0].height > before[0].height);
        try expectTiling(&tree, rect);
    }
}

test "capture retains fractional ratios and snap tolerance only changes the dragged half" {
    const rect: Rect = .{ .x = 17.2, .y = 35.7, .width = 2392.3, .height = 1308.6 };
    var tree = try testGrid(.horizontal);
    tree.nodes[0].split.ratio = 0.35791;
    const x = rect.x + rect.width * tree.nodes[0].split.ratio;
    const y = rect.y + 100;
    const held = tree.grab(rect, x + 2, y).?;
    const before = tree;
    tree.drag(held, held.x, held.y);
    try std.testing.expectEqualDeep(before, tree);
    tree.drag(held, held.x + 9, held.y);
    try std.testing.expect(tree.nodes[held.dividers[0].node].split.ratio != held.dividers[0].ratio);
    tree.drag(held, held.x + 7, held.y);
    try std.testing.expectEqualDeep(before, tree);
    try expectTiling(&tree, rect);
}
