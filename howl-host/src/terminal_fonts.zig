//! Owns Renderer-local terminal native fonts keyed by resolved point and DPI.
//!
//! The cache is fixed to two complete maximum-pane epochs. Equal identities
//! share one FontSet; candidates are reference-counted and released
//! transactionally.
//! No PTY, VT, lifecycle queue, visual FIFO, or GPU state is owned here.

const std = @import("std");
const render = @import("howl_render");
const handoff = @import("terminal_handoff");

/// Retains one complete 64-pane accepted epoch and one replacement epoch.
pub const capacity: usize = 128;
const maximum_points: f64 = 60.0;

/// Stores one pane-local point offset in sorted pane order.
pub const PaneOffset = struct { pane: handoff.PaneId, offset_points: f64 };

/// Stores the accepted or candidate Renderer-local terminal font policy.
pub const Policy = struct {
    base_point_size: f64,
    count: u8,
    offsets: [64]PaneOffset,

    /// Constructs one finite positive base policy with no pane offsets.
    pub fn init(base_point_size: f64) error{InvalidPolicy}!Policy {
        if (!std.math.isFinite(base_point_size) or std.math.isNan(base_point_size) or base_point_size <= 0)
            return error.InvalidPolicy;
        return .{ .base_point_size = base_point_size, .count = 0, .offsets = std.mem.zeroes([64]PaneOffset) };
    }
};

/// Stores one normalized exact DPI rational.
pub const ExactRational = struct { numerator: u32, denominator: u32 };

/// Stores one accepted output scale and DPI identity.
pub const ScaleSnapshot = struct {
    revision: u64,
    dpi_x: ExactRational,
    dpi_y: ExactRational,
};

/// Identifies one exact native terminal-font configuration.
pub const Key = struct {
    points: f64,
    dpi_x: ExactRational,
    dpi_y: ExactRational,
};

/// Identifies one live cache entry without exposing native pointers.
pub const Ref = struct { slot: u8, generation: u64 };

/// Reports invalid policy/scale, cache pressure, or native construction failure.
pub const Error = error{ InvalidPolicy, InvalidScale, Capacity, StaleReference } ||
    render.text.InitError;

const Entry = struct {
    generation: u64,
    key: Key,
    refs: u8,
    font: render.text.FontSet,
};

/// Retains one 64-pane accepted epoch plus one 64-pane replacement epoch.
pub const Cache = struct {
    allocator: std.mem.Allocator,
    primary_path: []const u8,
    entries: [capacity]?Entry = @splat(null),
    next_generation: u64 = 1,

    /// Borrows the runtime-configured path; each FontSet copies it on acquire.
    pub fn init(allocator: std.mem.Allocator, primary_path: []const u8) error{InvalidPolicy}!Cache {
        if (primary_path.len == 0 or primary_path.len > render.text.max_font_path_bytes or
            std.mem.indexOfScalar(u8, primary_path, 0) != null)
            return error.InvalidPolicy;
        return .{ .allocator = allocator, .primary_path = primary_path };
    }

    /// Releases every remaining native font in reverse slot order.
    pub fn deinit(self: *Cache) void {
        var index: usize = self.entries.len;
        while (index != 0) {
            index -= 1;
            if (self.entries[index]) |*value| value.font.deinit();
        }
        self.* = undefined;
    }

    /// Resolves one pane's bounded point/DPI identity.
    pub fn keyFor(
        policy: Policy,
        scale: ScaleSnapshot,
        pane: handoff.PaneId,
    ) error{ InvalidPolicy, InvalidScale }!Key {
        if (!validPolicy(policy)) return error.InvalidPolicy;
        if (!validRational(scale.dpi_x) or !validRational(scale.dpi_y))
            return error.InvalidScale;
        const dpi_x = rationalValue(scale.dpi_x);
        const dpi_y = rationalValue(scale.dpi_y);
        const floor = @max(72.0 / dpi_x, 72.0 / dpi_y);
        const points = std.math.clamp(
            policy.base_point_size + offsetFor(policy, pane),
            floor,
            maximum_points,
        );
        return .{ .points = points, .dpi_x = scale.dpi_x, .dpi_y = scale.dpi_y };
    }

    /// Acquires an equal FontSet or constructs one complete new entry.
    pub fn acquire(self: *Cache, key: Key) Error!Ref {
        for (&self.entries, 0..) |*maybe_entry, index| if (maybe_entry.*) |*value| {
            if (!std.meta.eql(value.key, key)) continue;
            value.refs = std.math.add(u8, value.refs, 1) catch return error.Capacity;
            return .{ .slot = @intCast(index), .generation = value.generation };
        };
        var free: ?usize = null;
        for (self.entries, 0..) |entry, index| if (entry == null) {
            free = index;
            break;
        };
        const index = free orelse return error.Capacity;
        const generation = self.next_generation;
        self.next_generation = std.math.add(u64, generation, 1) catch return error.Capacity;
        var font = try render.text.FontSet.init(self.allocator, .{
            .primary = self.primary_path,
            .size = .{ .points = .{
                .points = key.points,
                .dpi_x = .{ .numerator = key.dpi_x.numerator, .denominator = key.dpi_x.denominator },
                .dpi_y = .{ .numerator = key.dpi_y.numerator, .denominator = key.dpi_y.denominator },
            } },
        });
        errdefer font.deinit();
        self.entries[index] = .{ .generation = generation, .key = key, .refs = 1, .font = font };
        return .{ .slot = @intCast(index), .generation = generation };
    }

    /// Releases one exact reference and destroys the last native owner.
    pub fn release(self: *Cache, reference: Ref) error{StaleReference}!void {
        const index: usize = reference.slot;
        if (index >= self.entries.len or self.entries[index] == null or
            self.entries[index].?.generation != reference.generation)
            return error.StaleReference;
        const value = &self.entries[index].?;
        std.debug.assert(value.refs != 0);
        value.refs -= 1;
        if (value.refs == 0) {
            value.font.deinit();
            self.entries[index] = null;
        }
    }

    /// Borrows exact metrics from one live FontSet.
    pub fn metrics(self: *Cache, reference: Ref) error{StaleReference}!render.text.Metrics {
        return (try self.getEntry(reference)).font.metrics;
    }

    /// Borrows the exact live native font for one synchronous Renderer batch.
    pub fn borrow(self: *Cache, reference: Ref) error{StaleReference}!*render.text.FontSet {
        return &(try self.getEntry(reference)).font;
    }

    /// Returns the exact point and DPI identity retained by a live reference.
    pub fn keyForRef(self: *Cache, reference: Ref) error{StaleReference}!Key {
        return (try self.getEntry(reference)).key;
    }

    fn getEntry(self: *Cache, reference: Ref) error{StaleReference}!*Entry {
        const index: usize = reference.slot;
        if (index >= self.entries.len or self.entries[index] == null or
            self.entries[index].?.generation != reference.generation)
            return error.StaleReference;
        return &self.entries[index].?;
    }
};

fn offsetFor(policy: Policy, pane: handoff.PaneId) f64 {
    for (policy.offsets[0..policy.count]) |offset| {
        if (offset.pane == pane) return offset.offset_points;
        if (@backingInt(offset.pane) > @backingInt(pane)) break;
    }
    return 0.0;
}

fn rationalValue(value: ExactRational) f64 {
    return @as(f64, @floatFromInt(value.numerator)) /
        @as(f64, @floatFromInt(value.denominator));
}

fn validRational(value: ExactRational) bool {
    return value.numerator != 0 and value.denominator != 0 and
        std.math.gcd(value.numerator, value.denominator) == 1;
}

fn validPolicy(policy: Policy) bool {
    if (!std.math.isFinite(policy.base_point_size) or std.math.isNan(policy.base_point_size) or
        policy.base_point_size <= 0 or policy.count > policy.offsets.len)
        return false;
    var previous: u64 = 0;
    for (policy.offsets[0..policy.count]) |offset| {
        const pane = @backingInt(offset.pane);
        if (pane == 0 or pane <= previous or !std.math.isFinite(offset.offset_points) or
            std.math.isNan(offset.offset_points) or offset.offset_points == 0)
            return false;
        previous = pane;
    }
    return true;
}

test "equal resolved identities share one Renderer-local FontSet" {
    var cache = try Cache.init(std.testing.allocator, "../howl-render/testdata/primary.ttf");
    defer cache.deinit();
    const policy = try Policy.init(6.0);
    const scale = ScaleSnapshot{
        .revision = 1,
        .dpi_x = .{ .numerator = 96, .denominator = 1 },
        .dpi_y = .{ .numerator = 96, .denominator = 1 },
    };
    const first = try cache.acquire(try Cache.keyFor(policy, scale, @fromBackingInt(1)));
    const second = try cache.acquire(try Cache.keyFor(policy, scale, @fromBackingInt(2)));
    try std.testing.expectEqual(first, second);
    try cache.release(second);
    try cache.release(first);
}

test "distinct accepted and replacement pane epochs fit atomically" {
    var cache = try Cache.init(std.testing.allocator, "../howl-render/testdata/primary.ttf");
    defer cache.deinit();
    var references: [capacity]Ref = undefined;
    for (&references, 0..) |*reference, index| {
        reference.* = try cache.acquire(.{
            .points = 6.0 + @as(f64, @floatFromInt(index)) / 1024.0,
            .dpi_x = .{ .numerator = 96 + @as(u32, @intCast(index)), .denominator = 1 },
            .dpi_y = .{ .numerator = 96, .denominator = 1 },
        });
    }
    try std.testing.expectError(error.Capacity, cache.acquire(.{
        .points = 7.0,
        .dpi_x = .{ .numerator = 1024, .denominator = 1 },
        .dpi_y = .{ .numerator = 96, .denominator = 1 },
    }));
    var index = references.len;
    while (index != 0) {
        index -= 1;
        try cache.release(references[index]);
    }
}
