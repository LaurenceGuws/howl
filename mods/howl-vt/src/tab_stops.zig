//! Bounded terminal tab-stop storage and default/fallback semantics.
//!
//! Screen owns cursor movement. This module owns one optional per-column flag
//! buffer, its allocation lifetime, reset behavior, and resize-prefix copying.

const std = @import("std");
const parser = @import("parser.zig");

/// Owns explicit tab stops when storage exists and otherwise supplies defaults.
pub const State = struct {
    stops: ?[]bool = null,

    /// Provides an allocation-free state with default stops every eight columns.
    pub const empty: State = .{};

    /// Allocates one explicit stop flag per nonzero column and installs defaults.
    pub fn init(allocator: std.mem.Allocator, columns: u16) std.mem.Allocator.Error!State {
        if (columns == 0) return empty;
        const stops = try allocator.alloc(bool, columns);
        setDefaults(stops);
        return .{ .stops = stops };
    }

    /// Allocates replacement stops, preserving the source's overlapping explicit prefix.
    pub fn initCopied(
        allocator: std.mem.Allocator,
        columns: u16,
        source: State,
    ) std.mem.Allocator.Error!State {
        var result = try init(allocator, columns);
        errdefer result.deinit(allocator);
        const destination = result.stops orelse return result;
        const existing = source.stops orelse return result;
        const count = @min(destination.len, existing.len);
        @memcpy(destination[0..count], existing[0..count]);
        return result;
    }

    /// Releases explicit stop storage and restores the allocation-free empty state.
    pub fn deinit(self: *State, allocator: std.mem.Allocator) void {
        if (self.stops) |stops| allocator.free(stops);
        self.* = empty;
    }

    /// Reports an explicit stop or the standard eight-column fallback.
    pub fn at(self: State, column: u16) bool {
        if (self.stops) |stops| {
            if (column < stops.len) return stops[column];
        }
        return defaultAt(column);
    }

    /// Sets one in-bounds explicit stop; allocation-free states remain unchanged.
    pub fn set(self: *State, column: u16) void {
        const stops = self.stops orelse return;
        if (column < stops.len) stops[column] = true;
    }

    /// Clears one in-bounds explicit stop; allocation-free states remain unchanged.
    pub fn clear(self: *State, column: u16) void {
        const stops = self.stops orelse return;
        if (column < stops.len) stops[column] = false;
    }

    /// Clears every explicit stop while preserving allocation ownership.
    pub fn clearAll(self: *State) void {
        if (self.stops) |stops| @memset(stops, false);
    }

    /// Restores explicit defaults while preserving allocation ownership.
    pub fn reset(self: *State) void {
        if (self.stops) |stops| setDefaults(stops);
    }

    /// Restores explicit defaults and reports whether any stored flag changed.
    pub fn resetChanged(self: *State) bool {
        const stops = self.stops orelse return false;
        var changed = false;
        for (stops, 0..) |stop, column| {
            if (stop != defaultAt(column)) changed = true;
        }
        setDefaults(stops);
        return changed;
    }

    /// Replaces explicit stops from one-based DECTABSR fields, ignoring invalid members.
    pub fn replaceOneBased(self: *State, payload: []const u8) bool {
        const stops = self.stops orelse return false;
        if (payload.len > parser.max_metadata_control_bytes) return false;
        var restored: [parser.max_metadata_control_bytes / 2 + 1]u16 = undefined;
        var restored_count: usize = 0;
        var values = std.mem.splitScalar(u8, payload, '/');
        while (values.next()) |field| {
            const one_based = std.fmt.parseInt(u32, field, 10) catch continue;
            if (one_based == 0 or one_based > stops.len) continue;
            std.debug.assert(restored_count < restored.len);
            restored[restored_count] = @intCast(one_based - 1);
            restored_count += 1;
        }
        std.sort.block(u16, restored[0..restored_count], {}, std.sort.asc(u16));

        var changed = false;
        var restored_index: usize = 0;
        for (stops, 0..) |*stop, column| {
            const bounded_column: u16 = @intCast(column);
            while (restored_index < restored_count and restored[restored_index] < bounded_column)
                restored_index += 1;
            const next = restored_index < restored_count and
                restored[restored_index] == bounded_column;
            changed = stop.* != next or changed;
            stop.* = next;
        }
        return changed;
    }

    /// Reports whether explicit storage exactly owns the requested column count.
    pub fn ownsColumns(self: State, columns: u16) bool {
        return if (self.stops) |stops|
            stops.len == columns
        else
            columns == 0;
    }
};

fn defaultAt(column: usize) bool {
    return column != 0 and column % 8 == 0;
}

fn setDefaults(stops: []bool) void {
    @memset(stops, false);
    for (stops, 0..) |*stop, column| {
        if (defaultAt(column)) stop.* = true;
    }
}

test "allocation-free tab stops retain standard fallback semantics" {
    var state = State.empty;
    try std.testing.expect(!state.at(0));
    try std.testing.expect(state.at(8));
    try std.testing.expect(state.at(16));
    try std.testing.expect(!state.at(17));
    state.set(3);
    state.clear(8);
    state.clearAll();
    state.reset();
    try std.testing.expect(state.at(8));
    try std.testing.expect(!state.resetChanged());
}

test "owned tab stops mutate clear and report exact default restoration" {
    var state = try State.init(std.testing.allocator, 18);
    defer state.deinit(std.testing.allocator);
    try std.testing.expect(state.ownsColumns(18));
    try std.testing.expect(state.at(8));
    try std.testing.expect(state.at(16));

    state.clear(8);
    state.set(3);
    try std.testing.expect(!state.at(8));
    try std.testing.expect(state.at(3));
    try std.testing.expect(state.resetChanged());
    try std.testing.expect(state.at(8));
    try std.testing.expect(!state.at(3));
    try std.testing.expect(!state.resetChanged());

    state.clearAll();
    try std.testing.expect(!state.at(8));
    state.reset();
    try std.testing.expect(state.at(8));
}

test "resize copy preserves overlap and defaults only new columns" {
    var source = try State.init(std.testing.allocator, 10);
    defer source.deinit(std.testing.allocator);
    source.clear(8);
    source.set(3);

    var wider = try State.initCopied(std.testing.allocator, 18, source);
    defer wider.deinit(std.testing.allocator);
    try std.testing.expect(wider.at(3));
    try std.testing.expect(!wider.at(8));
    try std.testing.expect(wider.at(16));

    var narrower = try State.initCopied(std.testing.allocator, 4, wider);
    defer narrower.deinit(std.testing.allocator);
    try std.testing.expect(narrower.at(3));
    // Queries beyond explicit storage retain the allocation-free default rule.
    try std.testing.expect(narrower.at(8));
}

test "DECTABSR replacement ignores invalid members and reports exact mutation" {
    var state = try State.init(std.testing.allocator, 18);
    defer state.deinit(std.testing.allocator);

    try std.testing.expect(state.replaceOneBased("3/11/999/bad/0/3"));
    try std.testing.expect(state.at(2));
    try std.testing.expect(state.at(10));
    try std.testing.expect(!state.at(8));
    try std.testing.expect(!state.replaceOneBased("11/3/3"));
    try std.testing.expect(state.replaceOneBased(""));
    try std.testing.expect(!state.at(2));
    try std.testing.expect(!state.at(10));

    const oversized = try std.testing.allocator.alloc(
        u8,
        parser.max_metadata_control_bytes + 1,
    );
    defer std.testing.allocator.free(oversized);
    @memset(oversized, '1');
    try std.testing.expect(!state.replaceOneBased(oversized));
}

test "tab-stop construction reports allocation failure without an owner" {
    const init: *const fn (std.mem.Allocator, u16) std.mem.Allocator.Error!State = State.init;
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, init(failing.allocator(), 80));
    try std.testing.expect(failing.has_induced_failure);

    const empty_state = try init(failing.allocator(), 0);
    try std.testing.expect(empty_state.ownsColumns(0));
}
