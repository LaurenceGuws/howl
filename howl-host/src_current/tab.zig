//! Owns one named tab and its bounded tiled terminal-pane identities.

const std = @import("std");
const tiled = @import("tiled_panes.zig");

/// Maximum retained UTF-8-opaque tab-name bytes.
pub const name_limit: usize = 128;

/// Owns one allocated tab name and one platform-independent tiled-pane model.
pub const Tab = struct {
    /// Allocator that owns `name_bytes` for the complete tab lifetime.
    allocator: std.mem.Allocator,
    /// Exact retained name bytes, bounded by `name_limit`.
    name_bytes: []u8,
    /// Tab-local pane topology, geometry, and focus.
    tiled_panes: tiled.TiledPanes,

    /// Allocate one tab name and construct one initial tiled pane.
    pub fn init(
        allocator: std.mem.Allocator,
        initial_name: []const u8,
        initial_pane: tiled.PaneId,
        size: tiled.GridSize,
    ) error{ OutOfMemory, InvalidName, InvalidPaneId, InvalidSize }!Tab {
        try validateName(initial_name);
        const owned_name = try allocator.dupe(u8, initial_name);
        errdefer allocator.free(owned_name);
        return .{
            .allocator = allocator,
            .name_bytes = owned_name,
            .tiled_panes = try .init(initial_pane, size),
        };
    }

    /// Release the retained name through the initializer allocator.
    pub fn deinit(self: *Tab) void {
        self.allocator.free(self.name_bytes);
        self.name_bytes = self.name_bytes[0..0];
    }

    /// Borrow the exact retained name until rename or deinit.
    pub fn name(self: *const Tab) []const u8 {
        return self.name_bytes;
    }

    /// Replace the retained name transactionally; identical bytes are a no-op.
    pub fn rename(self: *Tab, replacement: []const u8) error{ OutOfMemory, InvalidName }!bool {
        try validateName(replacement);
        if (std.mem.eql(u8, self.name_bytes, replacement)) return false;
        const owned_name = try self.allocator.dupe(u8, replacement);
        self.allocator.free(self.name_bytes);
        self.name_bytes = owned_name;
        return true;
    }

    /// Validate the name and tiled topology owned by this tab.
    pub fn validate(self: *const Tab) error{InvalidTab}!void {
        validateName(self.name_bytes) catch return error.InvalidTab;
        self.tiled_panes.validate() catch return error.InvalidTab;
    }
};

fn validateName(name: []const u8) error{InvalidName}!void {
    if (name.len == 0 or name.len > name_limit) return error.InvalidName;
}

fn paneId(value: u64) tiled.PaneId {
    return @fromBackingInt(@intCast(value));
}

test "tab owns bounded transactional name" {
    var tab = try Tab.init(std.testing.allocator, "one", paneId(1), .{ .cols = 80, .rows = 24 });
    defer tab.deinit();
    try std.testing.expectEqualStrings("one", tab.name());
    try std.testing.expect(!(try tab.rename("one")));
    try std.testing.expect(try tab.rename("two"));
    try std.testing.expectEqualStrings("two", tab.name());
    try std.testing.expectError(error.InvalidName, tab.rename(""));
    var maximum_name: [name_limit]u8 = @splat('x');
    try std.testing.expect(try tab.rename(&maximum_name));
    var oversized_name: [name_limit + 1]u8 = @splat('x');
    try std.testing.expectError(error.InvalidName, tab.rename(&oversized_name));
    try tab.validate();
}

test "tab rename allocation failure preserves exact owned state" {
    var tab = try Tab.init(std.testing.allocator, "one", paneId(1), .{ .cols = 80, .rows = 24 });
    defer tab.deinit();
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    const prior_allocator = tab.allocator;
    tab.allocator = failing.allocator();
    try std.testing.expectError(error.OutOfMemory, tab.rename("replacement"));
    tab.allocator = prior_allocator;
    try std.testing.expectEqualStrings("one", tab.name());
    try tab.validate();
}
