//! Owns bounded concrete tiled-pane rectangles, focus, and geometry mutation.
//!
//! Current rectangles are the complete topology. Mutations derive affected
//! pane groups from exact shared edges, validate a fixed-storage candidate,
//! and commit only a complete nonoverlapping grid tiling.

const std = @import("std");

/// One tab admits at most sixteen visible terminal panes.
pub const pane_limit: u8 = 16;
/// Maximum admitted terminal-grid width.
pub const max_cols: u16 = 512;
/// Maximum admitted terminal-grid height.
pub const max_rows: u16 = 256;
/// Minimum width retained by every pane.
pub const min_pane_cols: u16 = 2;
/// Minimum height retained by every pane.
pub const min_pane_rows: u16 = 1;

/// Stable nonzero terminal-pane identity issued by Screen.
pub const PaneId = enum(u64) { _ };

/// Selects the axis divided by a split.
pub const SplitAxis = enum {
    /// Divide columns into left and right children.
    horizontal,
    /// Divide rows into top and bottom children.
    vertical,
};

/// Selects deterministic spatial focus or divider movement.
pub const Direction = enum { left, right, up, down };

/// Bounded terminal-grid dimensions shared by a tab's tiled panes.
pub const GridSize = struct {
    /// Number of terminal cell columns.
    cols: u16,
    /// Number of terminal cell rows.
    rows: u16,
};

/// One exact nonempty rectangle in terminal-grid cells.
pub const Rect = struct {
    /// Zero-based left column.
    col: u16,
    /// Zero-based top row.
    row: u16,
    /// Width in terminal cells.
    cols: u16,
    /// Height in terminal cells.
    rows: u16,

    fn contains(self: Rect, col: u16, row: u16) bool {
        const col_value: u32 = col;
        const row_value: u32 = row;
        return col_value >= self.col and col_value < right(self) and
            row_value >= self.row and row_value < bottom(self);
    }
};

/// Borrowed pane identity and geometry written into caller-owned storage.
pub const Placement = struct {
    /// Stable pane identity.
    pane: PaneId,
    /// Exact tiled rectangle.
    rect: Rect,
    /// Whether this pane owns tab-local focus.
    focused: bool,
};

const Pane = struct {
    id: PaneId,
    rect: Rect,
};

const Span = struct {
    start: u16,
    end: u16,
};

const BoundaryGroup = struct {
    first: [pane_limit]bool = @splat(false),
    second: [pane_limit]bool = @splat(false),
    span: Span,
};

const CoordinateMap = struct {
    old: [pane_limit * 2]u16 = undefined,
    new: [pane_limit * 2]u16 = undefined,
    count: u8 = 0,

    fn index(self: *const CoordinateMap, value: u16) ?u8 {
        for (self.old[0..self.count], 0..) |candidate, candidate_index| {
            if (candidate == value) return @intCast(candidate_index);
        }
        return null;
    }
};

/// Owns one tab's fixed-capacity concrete rectangles and focused identity.
pub const TiledPanes = struct {
    /// Fixed pane storage; only `panes[0..count]` is live.
    panes: [pane_limit]Pane = undefined,
    /// Exact number of live pane records.
    count: u8 = 1,
    /// One reachable stable pane identity.
    focused_pane: PaneId,
    /// Complete grid covered exactly once by live rectangles.
    size: GridSize,

    /// Construct one valid tiled model containing its initial pane.
    pub fn init(initial: PaneId, size: GridSize) error{ InvalidPaneId, InvalidSize }!TiledPanes {
        if (@backingInt(initial) == 0) return error.InvalidPaneId;
        try validateSize(size);
        var result = TiledPanes{ .focused_pane = initial, .size = size };
        result.panes[0] = .{ .id = initial, .rect = fullRect(size) };
        return result;
    }

    /// Return the number of live pane records.
    pub fn paneCount(self: *const TiledPanes) u8 {
        return self.count;
    }

    /// Return the stable focused pane identity.
    pub fn focused(self: *const TiledPanes) PaneId {
        return self.focused_pane;
    }

    /// Return whether this tab contains a pane identity.
    pub fn contains(self: *const TiledPanes, pane: PaneId) bool {
        return self.paneIndex(pane) != null;
    }

    /// Write the complete deterministic record order into fixed caller storage.
    pub fn placements(
        self: *const TiledPanes,
        output: *[pane_limit]Placement,
    ) error{InvalidGeometry}![]const Placement {
        try self.validateGeometry();
        for (self.panes[0..self.count], output[0..self.count]) |pane, *placement| {
            placement.* = .{
                .pane = pane.id,
                .rect = pane.rect,
                .focused = pane.id == self.focused_pane,
            };
        }
        return output[0..self.count];
    }

    /// Return one pane's exact rectangle.
    pub fn paneRect(self: *const TiledPanes, pane: PaneId) error{StalePane}!Rect {
        const index = self.paneIndex(pane) orelse return error.StalePane;
        return self.panes[index].rect;
    }

    /// Split one target rectangle into two exact rectangles and focus the new pane.
    pub fn split(
        self: *TiledPanes,
        target: PaneId,
        new_pane: PaneId,
        axis: SplitAxis,
    ) error{ StalePane, DuplicatePane, InvalidPaneId, PaneLimit, GeometryLimit }!void {
        self.validateGeometry() catch return error.GeometryLimit;
        if (@backingInt(new_pane) == 0) return error.InvalidPaneId;
        if (self.contains(new_pane)) return error.DuplicatePane;
        const target_index = self.paneIndex(target) orelse return error.StalePane;
        if (self.count == pane_limit) return error.PaneLimit;
        const target_rect = self.panes[target_index].rect;
        var first = target_rect;
        var second = target_rect;
        switch (axis) {
            .horizontal => {
                if (target_rect.cols < min_pane_cols * 2) return error.GeometryLimit;
                first.cols = target_rect.cols / 2;
                second.col += first.cols;
                second.cols -= first.cols;
            },
            .vertical => {
                if (target_rect.rows < min_pane_rows * 2) return error.GeometryLimit;
                first.rows = target_rect.rows / 2;
                second.row += first.rows;
                second.rows -= first.rows;
            },
        }
        var candidate = self.*;
        candidate.panes[target_index].rect = first;
        candidate.panes[candidate.count] = .{ .id = new_pane, .rect = second };
        candidate.count += 1;
        candidate.focused_pane = new_pane;
        candidate.validateGeometry() catch return error.GeometryLimit;
        self.* = candidate;
    }

    /// Close one pane and fill its space with valid survivor rectangles.
    ///
    /// A complete neighboring edge group expands and connected overlaps are
    /// trimmed at exact boundaries. Failure to retain rectangles rejects the
    /// candidate without changing any pane.
    pub fn close(self: *TiledPanes, pane: PaneId) error{ StalePane, LastPane, GeometryLimit }!void {
        self.validateGeometry() catch return error.GeometryLimit;
        const target_index = self.paneIndex(pane) orelse return error.StalePane;
        if (self.count == 1) return error.LastPane;
        const target = self.panes[target_index].rect;
        const directions = [_]Direction{ .left, .right, .up, .down };
        for (directions) |direction| {
            const group = self.closeGroup(target_index, direction);
            if (!coversSpan(self, group, closeSpan(target, direction), direction)) continue;
            const fallback = chooseSelected(self, group);
            var candidate = self.*;
            if (!candidate.fillClosedSpace(target_index, direction, group)) continue;
            candidate.remove(target_index);
            if (candidate.focused_pane == pane)
                candidate.focused_pane = fallback orelse return error.GeometryLimit;
            candidate.validateGeometry() catch continue;
            self.* = candidate;
            return;
        }
        return error.GeometryLimit;
    }

    fn fillClosedSpace(
        self: *TiledPanes,
        target_index: u8,
        direction: Direction,
        selected: [pane_limit]bool,
    ) bool {
        const target = self.panes[target_index].rect;
        var candidate = self.*;
        for (candidate.panes[0..candidate.count], 0..) |*neighbor, index| {
            if (!selected[index]) continue;
            switch (direction) {
                .left => neighbor.rect.cols += target.cols,
                .right => {
                    neighbor.rect.col = target.col;
                    neighbor.rect.cols += target.cols;
                },
                .up => neighbor.rect.rows += target.rows,
                .down => {
                    neighbor.rect.row = target.row;
                    neighbor.rect.rows += target.rows;
                },
            }
        }
        for (candidate.panes[0..candidate.count], 0..) |*pane, index| {
            if (index == target_index or selected[index]) continue;
            for (candidate.panes[0..candidate.count], 0..) |expanded, expanded_index| {
                if (!selected[expanded_index] or !overlaps(pane.rect, expanded.rect)) continue;
                if (!trimOverlap(&pane.rect, expanded.rect)) return false;
            }
        }
        self.* = candidate;
        return true;
    }

    fn remove(self: *TiledPanes, index: u8) void {
        std.debug.assert(index < self.count);
        var cursor = index;
        while (cursor + 1 < self.count) : (cursor += 1) {
            self.panes[cursor] = self.panes[cursor + 1];
        }
        self.count -= 1;
    }

    /// Focus an exact pane identity; repetition is a no-op.
    pub fn focusPane(self: *TiledPanes, pane: PaneId) error{ StalePane, InvalidGeometry }!bool {
        try self.validateGeometry();
        if (!self.contains(pane)) return error.StalePane;
        if (self.focused_pane == pane) return false;
        self.focused_pane = pane;
        return true;
    }

    /// Focus the pane containing one grid cell; outside cells are exact no-ops.
    pub fn focusAt(self: *TiledPanes, col: u16, row: u16) error{InvalidGeometry}!bool {
        try self.validateGeometry();
        for (self.panes[0..self.count]) |pane| {
            if (!pane.rect.contains(col, row)) continue;
            if (self.focused_pane == pane.id) return false;
            self.focused_pane = pane.id;
            return true;
        }
        return false;
    }

    /// Move focus to the nearest pane in one direction; no candidate is a no-op.
    pub fn focusDirection(self: *TiledPanes, direction: Direction) error{InvalidGeometry}!bool {
        try self.validateGeometry();
        const current_index = self.paneIndex(self.focused_pane) orelse return error.InvalidGeometry;
        const current = self.panes[current_index].rect;
        var best: ?Pane = null;
        for (self.panes[0..self.count]) |candidate| {
            if (candidate.id == self.focused_pane or !isInDirection(current, candidate.rect, direction)) continue;
            if (best == null or nearer(current, candidate, best.?, direction)) best = candidate;
        }
        const chosen = best orelse return false;
        self.focused_pane = chosen.id;
        return true;
    }

    /// Move the complete contiguous shared boundary nearest one pane edge.
    ///
    /// Every pane touching either side of the connected boundary span moves
    /// together. Movement saturates at the minimum size of all shrinking panes.
    pub fn resizeDivider(
        self: *TiledPanes,
        pane: PaneId,
        direction: Direction,
        cells: u16,
    ) error{ StalePane, InvalidGeometry }!bool {
        if (cells == 0) return false;
        try self.validateGeometry();
        const index = self.paneIndex(pane) orelse return error.StalePane;
        const boundary = boundaryCoordinate(self.panes[index].rect, direction);
        if (boundary == 0 or
            (isHorizontalDirection(direction) and boundary == self.size.cols) or
            (!isHorizontalDirection(direction) and boundary == self.size.rows)) return false;
        const group = self.boundaryGroup(index, direction, boundary) orelse return false;
        var maximum = cells;
        for (self.panes[0..self.count], 0..) |record, record_index| {
            const shrinks = switch (direction) {
                .right, .down => group.second[record_index],
                .left, .up => group.first[record_index],
            };
            if (!shrinks) continue;
            const extent = if (isHorizontalDirection(direction)) record.rect.cols else record.rect.rows;
            const minimum = if (isHorizontalDirection(direction)) min_pane_cols else min_pane_rows;
            maximum = @min(maximum, extent - minimum);
        }
        if (maximum == 0) return false;
        var candidate = self.*;
        for (candidate.panes[0..candidate.count], 0..) |*record, record_index| {
            if (group.first[record_index]) switch (direction) {
                .right => record.rect.cols += maximum,
                .left => record.rect.cols -= maximum,
                .down => record.rect.rows += maximum,
                .up => record.rect.rows -= maximum,
            };
            if (group.second[record_index]) switch (direction) {
                .right => {
                    record.rect.col += maximum;
                    record.rect.cols -= maximum;
                },
                .left => {
                    record.rect.col -= maximum;
                    record.rect.cols += maximum;
                },
                .down => {
                    record.rect.row += maximum;
                    record.rect.rows -= maximum;
                },
                .up => {
                    record.rect.row -= maximum;
                    record.rect.rows += maximum;
                },
            };
        }
        candidate.validateGeometry() catch return error.InvalidGeometry;
        self.* = candidate;
        return true;
    }

    /// Resize current rectangle boundaries transactionally without split ancestry.
    pub fn resize(self: *TiledPanes, size: GridSize) error{ InvalidSize, GeometryLimit }!bool {
        self.validateGeometry() catch return error.GeometryLimit;
        try validateSize(size);
        if (std.meta.eql(self.size, size)) return false;
        var candidate = self.*;
        const columns = self.coordinateMap(.horizontal, size.cols) catch return error.GeometryLimit;
        const rows = self.coordinateMap(.vertical, size.rows) catch return error.GeometryLimit;
        for (candidate.panes[0..candidate.count]) |*pane| {
            const left_index = columns.index(pane.rect.col) orelse return error.GeometryLimit;
            const right_index = columns.index(@intCast(right(pane.rect))) orelse return error.GeometryLimit;
            const top_index = rows.index(pane.rect.row) orelse return error.GeometryLimit;
            const bottom_index = rows.index(@intCast(bottom(pane.rect))) orelse return error.GeometryLimit;
            pane.rect = .{
                .col = columns.new[left_index],
                .row = rows.new[top_index],
                .cols = columns.new[right_index] - columns.new[left_index],
                .rows = rows.new[bottom_index] - rows.new[top_index],
            };
        }
        candidate.size = size;
        candidate.validateGeometry() catch return error.GeometryLimit;
        self.* = candidate;
        return true;
    }

    /// Validate IDs, focus, rectangle arithmetic, bounds, overlap, and full coverage.
    pub fn validate(self: *const TiledPanes) error{InvalidModel}!void {
        self.validateGeometry() catch return error.InvalidModel;
    }

    fn paneIndex(self: *const TiledPanes, pane: PaneId) ?u8 {
        for (self.panes[0..self.count], 0..) |candidate, index| {
            if (candidate.id == pane) return @intCast(index);
        }
        return null;
    }

    fn validateGeometry(self: *const TiledPanes) error{InvalidGeometry}!void {
        validateSize(self.size) catch return error.InvalidGeometry;
        if (self.count == 0 or self.count > pane_limit) return error.InvalidGeometry;
        var focused_seen = false;
        var area: u32 = 0;
        for (self.panes[0..self.count], 0..) |pane, index| {
            if (@backingInt(pane.id) == 0 or
                pane.rect.cols < min_pane_cols or pane.rect.rows < min_pane_rows or
                right(pane.rect) > self.size.cols or bottom(pane.rect) > self.size.rows)
                return error.InvalidGeometry;
            for (self.panes[0..index]) |prior| {
                if (prior.id == pane.id or overlaps(prior.rect, pane.rect)) return error.InvalidGeometry;
            }
            if (pane.id == self.focused_pane) focused_seen = true;
            area += @as(u32, pane.rect.cols) * pane.rect.rows;
        }
        if (!focused_seen or area != @as(u32, self.size.cols) * self.size.rows)
            return error.InvalidGeometry;
    }

    fn boundaryGroup(
        self: *const TiledPanes,
        seed: u8,
        direction: Direction,
        boundary: u16,
    ) ?BoundaryGroup {
        var result = BoundaryGroup{ .span = paneSpan(self.panes[seed].rect, direction) };
        var changed = true;
        while (changed) {
            changed = false;
            for (self.panes[0..self.count], 0..) |pane, index| {
                const side = boundarySide(pane.rect, direction, boundary);
                if (side == 0 or !touchesSpan(paneSpan(pane.rect, direction), result.span)) continue;
                const selected = if (side < 0) &result.first[index] else &result.second[index];
                if (!selected.*) {
                    selected.* = true;
                    changed = true;
                }
                const span = paneSpan(pane.rect, direction);
                const expanded = Span{
                    .start = @min(result.span.start, span.start),
                    .end = @max(result.span.end, span.end),
                };
                if (expanded.start != result.span.start or expanded.end != result.span.end) {
                    result.span = expanded;
                    changed = true;
                }
            }
        }
        if (!coversSpan(self, result.first, result.span, direction) or
            !coversSpan(self, result.second, result.span, direction)) return null;
        return result;
    }

    fn closeGroup(self: *const TiledPanes, target: u8, direction: Direction) [pane_limit]bool {
        const rect = self.panes[target].rect;
        const boundary = boundaryCoordinate(rect, direction);
        const required = closeSpan(rect, direction);
        var result: [pane_limit]bool = @splat(false);
        for (self.panes[0..self.count], 0..) |candidate, index| {
            if (index == target or boundarySide(candidate.rect, direction, boundary) != closeNeighborSide(direction))
                continue;
            const span = paneSpan(candidate.rect, direction);
            if (span.start < required.end and required.start < span.end) result[index] = true;
        }
        return result;
    }

    fn coordinateMap(
        self: *const TiledPanes,
        axis: SplitAxis,
        new_extent: u16,
    ) error{GeometryLimit}!CoordinateMap {
        var result = CoordinateMap{};
        const old_extent = if (axis == .horizontal) self.size.cols else self.size.rows;
        for (self.panes[0..self.count]) |pane| {
            const start = if (axis == .horizontal) pane.rect.col else pane.rect.row;
            const end: u16 = @intCast(if (axis == .horizontal) right(pane.rect) else bottom(pane.rect));
            insertCoordinate(&result, start);
            insertCoordinate(&result, end);
        }
        if (result.old[result.count - 1] != old_extent) return error.GeometryLimit;
        var lower: [pane_limit * 2]u16 = @splat(0);
        var upper: [pane_limit * 2]u16 = @splat(new_extent);
        var boundary_index: u8 = 1;
        while (boundary_index < result.count) : (boundary_index += 1) {
            lower[boundary_index] = lower[boundary_index - 1];
            for (self.panes[0..self.count]) |pane| {
                const start = if (axis == .horizontal) pane.rect.col else pane.rect.row;
                const end: u16 = @intCast(if (axis == .horizontal) right(pane.rect) else bottom(pane.rect));
                if (result.old[boundary_index] != end) continue;
                const start_index = result.index(start) orelse return error.GeometryLimit;
                const minimum = if (axis == .horizontal) min_pane_cols else min_pane_rows;
                lower[boundary_index] = @max(lower[boundary_index], lower[start_index] + minimum);
            }
        }
        if (lower[result.count - 1] > new_extent) return error.GeometryLimit;
        var reverse = result.count - 1;
        upper[reverse] = new_extent;
        while (reverse > 0) {
            reverse -= 1;
            upper[reverse] = upper[reverse + 1];
            for (self.panes[0..self.count]) |pane| {
                const start = if (axis == .horizontal) pane.rect.col else pane.rect.row;
                const end: u16 = @intCast(if (axis == .horizontal) right(pane.rect) else bottom(pane.rect));
                if (result.old[reverse] != start) continue;
                const end_index = result.index(end) orelse return error.GeometryLimit;
                const minimum = if (axis == .horizontal) min_pane_cols else min_pane_rows;
                if (upper[end_index] < minimum) return error.GeometryLimit;
                upper[reverse] = @min(upper[reverse], upper[end_index] - minimum);
            }
        }
        result.new[0] = 0;
        boundary_index = 1;
        while (boundary_index + 1 < result.count) : (boundary_index += 1) {
            var required = result.new[boundary_index - 1];
            for (self.panes[0..self.count]) |pane| {
                const start = if (axis == .horizontal) pane.rect.col else pane.rect.row;
                const end: u16 = @intCast(if (axis == .horizontal) right(pane.rect) else bottom(pane.rect));
                if (result.old[boundary_index] != end) continue;
                const start_index = result.index(start) orelse return error.GeometryLimit;
                const minimum = if (axis == .horizontal) min_pane_cols else min_pane_rows;
                required = @max(required, result.new[start_index] + minimum);
            }
            const scaled: u16 = @intCast((@as(u32, result.old[boundary_index]) * new_extent +
                old_extent / 2) / old_extent);
            if (required > upper[boundary_index]) return error.GeometryLimit;
            result.new[boundary_index] = std.math.clamp(scaled, required, upper[boundary_index]);
        }
        result.new[result.count - 1] = new_extent;
        return result;
    }
};

fn validateSize(size: GridSize) error{InvalidSize}!void {
    if (size.cols < min_pane_cols or size.cols > max_cols or
        size.rows < min_pane_rows or size.rows > max_rows) return error.InvalidSize;
}

fn fullRect(size: GridSize) Rect {
    return .{ .col = 0, .row = 0, .cols = size.cols, .rows = size.rows };
}

fn right(rect: Rect) u32 {
    return @as(u32, rect.col) + rect.cols;
}

fn bottom(rect: Rect) u32 {
    return @as(u32, rect.row) + rect.rows;
}

fn overlaps(a: Rect, b: Rect) bool {
    return @as(u32, a.col) < right(b) and @as(u32, b.col) < right(a) and
        @as(u32, a.row) < bottom(b) and @as(u32, b.row) < bottom(a);
}

fn isHorizontalDirection(direction: Direction) bool {
    return direction == .left or direction == .right;
}

fn boundaryCoordinate(rect: Rect, direction: Direction) u16 {
    return switch (direction) {
        .left => rect.col,
        .right => @intCast(right(rect)),
        .up => rect.row,
        .down => @intCast(bottom(rect)),
    };
}

fn paneSpan(rect: Rect, direction: Direction) Span {
    return switch (direction) {
        .left, .right => .{ .start = rect.row, .end = @intCast(bottom(rect)) },
        .up, .down => .{ .start = rect.col, .end = @intCast(right(rect)) },
    };
}

fn closeSpan(rect: Rect, direction: Direction) Span {
    return paneSpan(rect, direction);
}

fn boundarySide(rect: Rect, direction: Direction, boundary: u16) i2 {
    return switch (direction) {
        .left, .right => if (right(rect) == boundary)
            -1
        else if (rect.col == boundary)
            1
        else
            0,
        .up, .down => if (bottom(rect) == boundary)
            -1
        else if (rect.row == boundary)
            1
        else
            0,
    };
}

fn closeNeighborSide(direction: Direction) i2 {
    return switch (direction) {
        .left, .up => -1,
        .right, .down => 1,
    };
}

fn touchesSpan(a: Span, b: Span) bool {
    return a.start <= b.end and b.start <= a.end;
}

fn coversSpan(
    panes: *const TiledPanes,
    selected: [pane_limit]bool,
    required: Span,
    direction: Direction,
) bool {
    var cursor = required.start;
    while (cursor < required.end) {
        var next = cursor;
        for (panes.panes[0..panes.count], 0..) |pane, index| {
            if (!selected[index]) continue;
            const span = paneSpan(pane.rect, direction);
            if (span.start <= cursor and span.end > next) next = span.end;
        }
        if (next == cursor) return false;
        cursor = @min(next, required.end);
    }
    return true;
}

fn chooseFirst(current: ?PaneId, candidate: PaneId) PaneId {
    const prior = current orelse return candidate;
    return if (@backingInt(candidate) < @backingInt(prior)) candidate else prior;
}

fn chooseSelected(panes: *const TiledPanes, selected: [pane_limit]bool) ?PaneId {
    var result: ?PaneId = null;
    for (panes.panes[0..panes.count], 0..) |pane, index| {
        if (selected[index]) result = chooseFirst(result, pane.id);
    }
    return result;
}

fn trimOverlap(rect: *Rect, obstacle: Rect) bool {
    const original_right = right(rect.*);
    const original_bottom = bottom(rect.*);
    const overlap_left = @max(@as(u32, rect.col), obstacle.col);
    const overlap_right = @min(original_right, right(obstacle));
    const overlap_top = @max(@as(u32, rect.row), obstacle.row);
    const overlap_bottom = @min(original_bottom, bottom(obstacle));
    if (overlap_left >= overlap_right or overlap_top >= overlap_bottom) return true;
    if (overlap_left == rect.col and overlap_right == original_right) {
        if (overlap_top == rect.row) {
            rect.row = @intCast(overlap_bottom);
            rect.rows = @intCast(original_bottom - overlap_bottom);
            return rect.rows >= min_pane_rows;
        }
        if (overlap_bottom == original_bottom) {
            rect.rows = @intCast(overlap_top - rect.row);
            return rect.rows >= min_pane_rows;
        }
    }
    if (overlap_top == rect.row and overlap_bottom == original_bottom) {
        if (overlap_left == rect.col) {
            rect.col = @intCast(overlap_right);
            rect.cols = @intCast(original_right - overlap_right);
            return rect.cols >= min_pane_cols;
        }
        if (overlap_right == original_right) {
            rect.cols = @intCast(overlap_left - rect.col);
            return rect.cols >= min_pane_cols;
        }
    }
    return false;
}

fn insertCoordinate(map: *CoordinateMap, value: u16) void {
    if (map.index(value) != null) return;
    std.debug.assert(map.count < map.old.len);
    var index = map.count;
    while (index > 0 and map.old[index - 1] > value) : (index -= 1) {
        map.old[index] = map.old[index - 1];
    }
    map.old[index] = value;
    map.count += 1;
}

fn isInDirection(current: Rect, candidate: Rect, direction: Direction) bool {
    return switch (direction) {
        .left => right(candidate) <= current.col,
        .right => right(current) <= candidate.col,
        .up => bottom(candidate) <= current.row,
        .down => bottom(current) <= candidate.row,
    };
}

fn nearer(current: Rect, candidate: Pane, best: Pane, direction: Direction) bool {
    const candidate_overlap = perpendicularOverlap(current, candidate.rect, direction);
    const best_overlap = perpendicularOverlap(current, best.rect, direction);
    if (candidate_overlap != best_overlap) return candidate_overlap;
    const candidate_gap = directionalGap(current, candidate.rect, direction);
    const best_gap = directionalGap(current, best.rect, direction);
    if (candidate_gap != best_gap) return candidate_gap < best_gap;
    const candidate_center = perpendicularCenterDistance(current, candidate.rect, direction);
    const best_center = perpendicularCenterDistance(current, best.rect, direction);
    if (candidate_center != best_center) return candidate_center < best_center;
    return @backingInt(candidate.id) < @backingInt(best.id);
}

fn perpendicularOverlap(a: Rect, b: Rect, direction: Direction) bool {
    return switch (direction) {
        .left, .right => @as(u32, a.row) < bottom(b) and @as(u32, b.row) < bottom(a),
        .up, .down => @as(u32, a.col) < right(b) and @as(u32, b.col) < right(a),
    };
}

fn directionalGap(a: Rect, b: Rect, direction: Direction) u16 {
    return switch (direction) {
        .left => a.col - @as(u16, @intCast(right(b))),
        .right => b.col - @as(u16, @intCast(right(a))),
        .up => a.row - @as(u16, @intCast(bottom(b))),
        .down => b.row - @as(u16, @intCast(bottom(a))),
    };
}

fn perpendicularCenterDistance(a: Rect, b: Rect, direction: Direction) u16 {
    const a_center: u32, const b_center: u32 = switch (direction) {
        .left, .right => .{ @as(u32, a.row) * 2 + a.rows, @as(u32, b.row) * 2 + b.rows },
        .up, .down => .{ @as(u32, a.col) * 2 + a.cols, @as(u32, b.col) * 2 + b.cols },
    };
    return @intCast(if (a_center > b_center) a_center - b_center else b_center - a_center);
}

fn paneId(value: u64) PaneId {
    return @fromBackingInt(@intCast(value));
}

const CloseExploration = struct {
    states: u32 = 0,
    close_attempts: u32 = 0,
    close_successes: u32 = 0,
    close_limits: u32 = 0,
};

fn sharesEdge(a: Rect, b: Rect) bool {
    const vertical = (right(a) == b.col or right(b) == a.col) and
        @as(u32, a.row) < bottom(b) and @as(u32, b.row) < bottom(a);
    const horizontal = (bottom(a) == b.row or bottom(b) == a.row) and
        @as(u32, a.col) < right(b) and @as(u32, b.col) < right(a);
    return vertical or horizontal;
}

fn expectLocalClose(before: TiledPanes, after: TiledPanes, closed: PaneId) !void {
    try after.validate();
    try std.testing.expectEqual(before.count - 1, after.count);
    try std.testing.expect(!after.contains(closed));

    const closed_index = before.paneIndex(closed) orelse return error.TestUnexpectedResult;
    var changed: [pane_limit]bool = @splat(false);
    var reached: [pane_limit]bool = @splat(false);
    reached[closed_index] = true;
    var changed_count: u8 = 0;

    for (before.panes[0..before.count], 0..) |pane, index| {
        if (pane.id == closed) continue;
        const after_index = after.paneIndex(pane.id) orelse return error.TestUnexpectedResult;
        changed[index] = !std.meta.eql(pane.rect, after.panes[after_index].rect);
        if (changed[index]) changed_count += 1;
    }
    try std.testing.expect(changed_count > 0);

    var advanced = true;
    while (advanced) {
        advanced = false;
        for (before.panes[0..before.count], 0..) |pane, index| {
            if (!changed[index] or reached[index]) continue;
            for (before.panes[0..before.count], 0..) |neighbor, neighbor_index| {
                if (reached[neighbor_index] and sharesEdge(pane.rect, neighbor.rect)) {
                    reached[index] = true;
                    advanced = true;
                    break;
                }
            }
        }
    }
    for (changed[0..before.count], reached[0..before.count]) |was_changed, was_reached| {
        if (was_changed) try std.testing.expect(was_reached);
    }
    if (before.focused_pane != closed) {
        try std.testing.expectEqual(before.focused_pane, after.focused_pane);
    } else {
        try std.testing.expect(after.contains(after.focused_pane));
    }
}

fn exploreCloseLayouts(
    state: TiledPanes,
    depth: u8,
    next_id: u64,
    exploration: *CloseExploration,
) !void {
    try state.validate();
    exploration.states += 1;

    if (state.count > 1) {
        for (state.panes[0..state.count]) |pane| {
            exploration.close_attempts += 1;
            var candidate = state;
            if (candidate.close(pane.id)) {
                exploration.close_successes += 1;
                try expectLocalClose(state, candidate, pane.id);
                if (depth > 0) try exploreCloseLayouts(candidate, depth - 1, next_id, exploration);
            } else |failure| switch (failure) {
                error.GeometryLimit => {
                    exploration.close_limits += 1;
                    try std.testing.expectEqualDeep(state, candidate);
                },
                error.StalePane, error.LastPane => return error.TestUnexpectedResult,
            }
        }
    }
    if (depth == 0) return;

    for (state.panes[0..state.count]) |pane| {
        for ([_]SplitAxis{ .horizontal, .vertical }) |axis| {
            var candidate = state;
            candidate.split(pane.id, paneId(next_id), axis) catch |failure| switch (failure) {
                error.GeometryLimit, error.PaneLimit => {
                    try std.testing.expectEqualDeep(state, candidate);
                    continue;
                },
                error.StalePane, error.DuplicatePane, error.InvalidPaneId => return error.TestUnexpectedResult,
            };
            try exploreCloseLayouts(candidate, depth - 1, next_id + 1, exploration);
        }
    }

    for (state.panes[0..state.count]) |pane| {
        for ([_]Direction{ .left, .right, .up, .down }) |direction| {
            var candidate = state;
            const changed = candidate.resizeDivider(pane.id, direction, 1) catch
                return error.TestUnexpectedResult;
            if (changed) try exploreCloseLayouts(candidate, depth - 1, next_id, exploration);
        }
    }

    for ([_]GridSize{
        .{ .cols = 4, .rows = 2 },
        .{ .cols = 5, .rows = 3 },
        .{ .cols = 6, .rows = 4 },
        .{ .cols = 7, .rows = 5 },
    }) |size| {
        var candidate = state;
        const changed = candidate.resize(size) catch |failure| switch (failure) {
            error.GeometryLimit => {
                try std.testing.expectEqualDeep(state, candidate);
                continue;
            },
            error.InvalidSize => return error.TestUnexpectedResult,
        };
        if (changed) try exploreCloseLayouts(candidate, depth - 1, next_id, exploration);
    }
}

test "split focus resize and close derive from current T-junction rectangles" {
    var panes = try TiledPanes.init(paneId(1), .{ .cols = 8, .rows = 4 });
    try panes.split(paneId(1), paneId(2), .horizontal);
    try panes.split(paneId(2), paneId(3), .vertical);
    try panes.validate();

    try std.testing.expect(try panes.focusDirection(.up));
    try std.testing.expectEqual(paneId(2), panes.focused());
    try std.testing.expect(try panes.focusDirection(.left));
    try std.testing.expectEqual(paneId(1), panes.focused());
    try std.testing.expect(try panes.focusAt(7, 3));
    try std.testing.expectEqual(paneId(3), panes.focused());
    try std.testing.expect(!(try panes.focusAt(8, 4)));

    try std.testing.expect(try panes.resizeDivider(paneId(1), .right, 1));
    try std.testing.expectEqual(Rect{ .col = 0, .row = 0, .cols = 5, .rows = 4 }, try panes.paneRect(paneId(1)));
    try std.testing.expectEqual(Rect{ .col = 5, .row = 0, .cols = 3, .rows = 2 }, try panes.paneRect(paneId(2)));
    try std.testing.expectEqual(Rect{ .col = 5, .row = 2, .cols = 3, .rows = 2 }, try panes.paneRect(paneId(3)));

    try panes.close(paneId(1));
    try std.testing.expectEqual(Rect{ .col = 0, .row = 0, .cols = 8, .rows = 2 }, try panes.paneRect(paneId(2)));
    try std.testing.expectEqual(Rect{ .col = 0, .row = 2, .cols = 8, .rows = 2 }, try panes.paneRect(paneId(3)));
    try panes.validate();
}

test "bounded reachable layouts close locally or preserve exact bytes" {
    var exploration = CloseExploration{};
    const seeds = [_]GridSize{
        .{ .cols = 4, .rows = 2 },
        .{ .cols = 6, .rows = 4 },
        .{ .cols = 7, .rows = 5 },
    };
    for (seeds, 0..) |size, index| {
        const initial = try TiledPanes.init(paneId(index + 1), size);
        try exploreCloseLayouts(initial, 2, 100 + index * 100, &exploration);
    }
    try std.testing.expect(exploration.states > 100);
    try std.testing.expect(exploration.close_attempts > 100);
    try std.testing.expect(exploration.close_successes > 100);
}

test "divider resize moves every pane on a complete multi-neighbor span" {
    var panes = try TiledPanes.init(paneId(1), .{ .cols = 12, .rows = 8 });
    try panes.split(paneId(1), paneId(2), .horizontal);
    try panes.split(paneId(1), paneId(3), .vertical);
    try panes.split(paneId(2), paneId(4), .vertical);
    try std.testing.expect(try panes.resizeDivider(paneId(3), .right, 2));
    try std.testing.expectEqual(Rect{ .col = 0, .row = 0, .cols = 8, .rows = 4 }, try panes.paneRect(paneId(1)));
    try std.testing.expectEqual(Rect{ .col = 0, .row = 4, .cols = 8, .rows = 4 }, try panes.paneRect(paneId(3)));
    try std.testing.expectEqual(Rect{ .col = 8, .row = 0, .cols = 4, .rows = 4 }, try panes.paneRect(paneId(2)));
    try std.testing.expectEqual(Rect{ .col = 8, .row = 4, .cols = 4, .rows = 4 }, try panes.paneRect(paneId(4)));
    try panes.validate();
}

test "grouped close expands a complete deterministic neighboring edge" {
    var panes = try TiledPanes.init(paneId(1), .{ .cols = 12, .rows = 8 });
    try panes.split(paneId(1), paneId(2), .horizontal);
    try panes.split(paneId(2), paneId(3), .vertical);
    try std.testing.expect(try panes.focusPane(paneId(1)));
    try panes.close(paneId(1));
    try std.testing.expectEqual(paneId(2), panes.focused());
    try std.testing.expectEqual(Rect{ .col = 0, .row = 0, .cols = 12, .rows = 4 }, try panes.paneRect(paneId(2)));
    try std.testing.expectEqual(Rect{ .col = 0, .row = 4, .cols = 12, .rows = 4 }, try panes.paneRect(paneId(3)));
    try panes.validate();
}

test "resize preserves a valid non-slicing rectangle tiling without ancestry" {
    var panes = try TiledPanes.init(paneId(1), .{ .cols = 6, .rows = 6 });
    panes.count = 5;
    panes.panes[0] = .{ .id = paneId(1), .rect = .{ .col = 0, .row = 0, .cols = 4, .rows = 2 } };
    panes.panes[1] = .{ .id = paneId(2), .rect = .{ .col = 4, .row = 0, .cols = 2, .rows = 4 } };
    panes.panes[2] = .{ .id = paneId(3), .rect = .{ .col = 2, .row = 4, .cols = 4, .rows = 2 } };
    panes.panes[3] = .{ .id = paneId(4), .rect = .{ .col = 0, .row = 2, .cols = 2, .rows = 4 } };
    panes.panes[4] = .{ .id = paneId(5), .rect = .{ .col = 2, .row = 2, .cols = 2, .rows = 2 } };
    try panes.validate();
    try std.testing.expect(try panes.resize(.{ .cols = 9, .rows = 7 }));
    try panes.validate();
    try std.testing.expectEqual(Rect{ .col = 3, .row = 2, .cols = 3, .rows = 3 }, try panes.paneRect(paneId(5)));
}

test "pinwheel center close repairs only connected rectangles" {
    var panes = try TiledPanes.init(paneId(1), .{ .cols = 6, .rows = 6 });
    panes.count = 5;
    panes.panes[0] = .{ .id = paneId(1), .rect = .{ .col = 0, .row = 0, .cols = 4, .rows = 2 } };
    panes.panes[1] = .{ .id = paneId(2), .rect = .{ .col = 4, .row = 0, .cols = 2, .rows = 4 } };
    panes.panes[2] = .{ .id = paneId(3), .rect = .{ .col = 2, .row = 4, .cols = 4, .rows = 2 } };
    panes.panes[3] = .{ .id = paneId(4), .rect = .{ .col = 0, .row = 2, .cols = 2, .rows = 4 } };
    panes.panes[4] = .{ .id = paneId(5), .rect = .{ .col = 2, .row = 2, .cols = 2, .rows = 2 } };
    panes.focused_pane = paneId(5);
    const before = panes;
    try panes.close(paneId(5));
    try std.testing.expectEqual(@as(u8, 4), panes.paneCount());
    try std.testing.expectEqual(paneId(4), panes.focused());
    try std.testing.expectEqual(before.panes[0].rect, try panes.paneRect(paneId(1)));
    try std.testing.expectEqual(before.panes[1].rect, try panes.paneRect(paneId(2)));
    try std.testing.expectEqual(
        Rect{ .col = 4, .row = 4, .cols = 2, .rows = 2 },
        try panes.paneRect(paneId(3)),
    );
    try std.testing.expectEqual(
        Rect{ .col = 0, .row = 2, .cols = 4, .rows = 4 },
        try panes.paneRect(paneId(4)),
    );
    try panes.validate();

    var hostile = before;
    hostile.panes[0].rect.cols -= 1;
    const hostile_before = hostile;
    try std.testing.expectError(error.GeometryLimit, hostile.close(paneId(5)));
    try std.testing.expectEqualDeep(hostile_before, hostile);
}

test "invalid operations and hostile rectangle arithmetic preserve exact bytes" {
    var panes = try TiledPanes.init(paneId(1), .{ .cols = 4, .rows = 2 });
    try panes.split(paneId(1), paneId(2), .horizontal);
    const before = panes;
    try std.testing.expectError(error.GeometryLimit, panes.split(paneId(1), paneId(3), .horizontal));
    try std.testing.expectEqualDeep(before, panes);
    try std.testing.expectError(error.DuplicatePane, panes.split(paneId(1), paneId(2), .vertical));
    try std.testing.expectEqualDeep(before, panes);
    try std.testing.expectError(error.GeometryLimit, panes.resize(.{ .cols = 3, .rows = 2 }));
    try std.testing.expectEqualDeep(before, panes);

    var overflow = panes;
    overflow.panes[0].rect.col = std.math.maxInt(u16);
    try std.testing.expectError(error.InvalidModel, overflow.validate());
    try std.testing.expectError(error.GeometryLimit, overflow.resize(.{ .cols = 5, .rows = 2 }));
    var overlap = panes;
    overlap.panes[1].rect.col = 1;
    try std.testing.expectError(error.InvalidModel, overlap.validate());
    var hole = panes;
    hole.panes[1].rect.cols -= 1;
    try std.testing.expectError(error.InvalidModel, hole.validate());
    var zero = panes;
    zero.panes[1].id = paneId(0);
    try std.testing.expectError(error.InvalidModel, zero.validate());
}

test "capacities bounds and minimum saturation are exact" {
    try std.testing.expectError(error.InvalidPaneId, TiledPanes.init(paneId(0), .{ .cols = 2, .rows = 1 }));
    try std.testing.expectError(error.InvalidSize, TiledPanes.init(paneId(1), .{ .cols = 1, .rows = 1 }));
    try std.testing.expectError(
        error.InvalidSize,
        TiledPanes.init(paneId(1), .{ .cols = max_cols + 1, .rows = max_rows }),
    );
    var panes = try TiledPanes.init(paneId(1), .{ .cols = 512, .rows = 256 });
    var next: u64 = 2;
    while (panes.paneCount() < pane_limit) : (next += 1) {
        try panes.split(panes.focused(), paneId(next), if (next % 2 == 0) .horizontal else .vertical);
    }
    try std.testing.expectError(error.PaneLimit, panes.split(panes.focused(), paneId(17), .horizontal));
    try panes.validate();

    var minimum = try TiledPanes.init(paneId(20), .{ .cols = 4, .rows = 2 });
    try minimum.split(paneId(20), paneId(21), .horizontal);
    try minimum.split(paneId(21), paneId(22), .vertical);
    try std.testing.expect(!(try minimum.resizeDivider(paneId(20), .right, 1)));
    try std.testing.expect(!(try minimum.resizeDivider(paneId(21), .down, 1)));
}
