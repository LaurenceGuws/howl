//! Owns fixed bounded overflow scalars for one ordered cell cohort.

const std = @import("std");

/// Cells qualified by one fixed owner-local scalar page.
pub const page_cells: usize = 4096;
/// Scalar bytes retained by each fixed owner-local page.
pub const scalar_bank_bytes: usize = 8 * 1024;
/// Scalar slots retained by each fixed owner-local page.
pub const scalar_slots: usize = scalar_bank_bytes / @sizeOf(u32);
/// Scalars retained directly in one lead cell.
pub const inline_scalars: usize = 4;
/// Maximum accepted scalars in one grapheme.
pub const maximum_scalars: usize = 24;
/// Maximum overflow scalars owned by one lead-cell range.
pub const maximum_tail_scalars: usize = maximum_scalars - inline_scalars;
const free_region_limit: usize = scalar_slots + 1;

/// Names the first scalar slot of one exact bank-contained range.
///
/// Zero is canonical absence. A nonzero value is one plus the absolute slot
/// across this owner's ordered fixed-bank cohort. The owning lead cell's
/// `combining_len` supplies the range length; range metadata never duplicates
/// that authority.
pub const Range = enum(u32) {
    none = 0,
    _,
};

const FreeRegion = struct {
    offset: u16,
    count: u16,
};

const Page = struct {
    scalars: [scalar_slots]u32 = @splat(0),
    free_regions: [free_region_limit]FreeRegion =
        @splat(.{ .offset = 0, .count = 0 }),
    free_count: u16 = 1,

    fn init() Page {
        var result: Page = .{};
        result.free_regions[0] = .{ .offset = 0, .count = scalar_slots };
        return result;
    }
};

/// Retains one range record per cell and one 8 KiB scalar bank per 4096 cells.
///
/// Allocation occurs only in `init`. Every mutation is bounded and
/// allocation-free. Ranges may name any bank page owned by this storage, so
/// moving an accepted cell across a page boundary transfers its range without
/// requiring fresh scalar capacity.
pub const Storage = struct {
    allocator: std.mem.Allocator,
    ranges: []Range,
    pages: []Page,

    /// Allocates the exact fixed bank cohort and canonical empty range table.
    pub fn init(
        allocator: std.mem.Allocator,
        cell_capacity: usize,
    ) error{ OutOfMemory, InvalidCapacity }!Storage {
        return initForCopy(allocator, cell_capacity, 0);
    }

    /// Reserves enough fresh pages to copy the given count of already accepted
    /// tail scalars in ranges no longer than maximum_tail_scalars. Before a
    /// first-fit copy spills to a new page, at most maximum_tail_scalars - 1
    /// slots can remain unused in each preceding page.
    pub fn initForCopy(
        allocator: std.mem.Allocator,
        cell_capacity: usize,
        tail_scalars: usize,
    ) error{ OutOfMemory, InvalidCapacity }!Storage {
        if (cell_capacity == 0) return error.InvalidCapacity;
        const maximum = std.math.mul(usize, cell_capacity, maximum_tail_scalars) catch
            return error.InvalidCapacity;
        if (tail_scalars > maximum) return error.InvalidCapacity;
        const cell_pages = std.math.divCeil(usize, cell_capacity, page_cells) catch
            return error.InvalidCapacity;
        const copy_pages = std.math.divCeil(usize, tail_scalars, scalar_slots - maximum_tail_scalars + 1) catch
            return error.InvalidCapacity;
        const page_count = @max(cell_pages, copy_pages);
        const total_slots = std.math.mul(usize, page_count, scalar_slots) catch
            return error.InvalidCapacity;
        if (total_slots > std.math.maxInt(u32))
            return error.InvalidCapacity;
        const ranges = allocator.alloc(Range, cell_capacity) catch
            return error.OutOfMemory;
        errdefer allocator.free(ranges);
        @memset(ranges, .none);
        const pages = allocator.alloc(Page, page_count) catch
            return error.OutOfMemory;
        errdefer allocator.free(pages);
        for (pages) |*page| page.* = Page.init();
        return .{ .allocator = allocator, .ranges = ranges, .pages = pages };
    }

    /// Experimental explicit growth. Existing mutation remains allocation-free;
    /// callers must arrange safe input failure handling before using this path.
    /// Successful growth invalidates borrowed page slices, not range identities.
    pub fn growOnePage(self: *Storage) error{ OutOfMemory, ScalarCapacity }!void {
        // A page unable to fit even the largest range has gaps of at most
        // maximum_tail_scalars - 1. With n occupied ranges (each at most
        // maximum_tail_scalars), it holds at most n ranges and n+1 gaps.
        // Thus each blocked page needs at least this many occupied ranges,
        // including when free space is fragmented throughout the page.
        const min_ranges = (scalar_slots - (maximum_tail_scalars - 1) + (2 * maximum_tail_scalars - 2)) / (2 * maximum_tail_scalars - 1);
        // Budget one retained range per cell, one temporary replacement and
        // one unblocked page. Multiple externally held Prepared ranges also
        // consume this budget; callers must handle ScalarCapacity.
        const max_ranges = std.math.add(usize, self.ranges.len, 1) catch return error.ScalarCapacity;
        const cap = std.math.add(usize, max_ranges / min_ranges, 1) catch return error.ScalarCapacity;
        if (self.pages.len >= cap) return error.ScalarCapacity;
        const new_count = std.math.add(usize, self.pages.len, 1) catch return error.ScalarCapacity;
        const slots = std.math.mul(usize, new_count, scalar_slots) catch return error.ScalarCapacity;
        if (slots > std.math.maxInt(u32)) return error.ScalarCapacity;
        const replacement = self.allocator.alloc(Page, new_count) catch return error.OutOfMemory;
        @memcpy(replacement[0..self.pages.len], self.pages);
        replacement[self.pages.len] = Page.init();
        self.allocator.free(self.pages);
        self.pages = replacement;
    }

    /// Releases the complete fixed owner-local cohort.
    pub fn deinit(self: *Storage) void {
        self.allocator.free(self.pages);
        self.allocator.free(self.ranges);
        self.* = undefined;
    }

    /// Returns exact retained overflow scalars for one lead-cell index.
    pub fn tail(
        self: *const Storage,
        cell: usize,
        combining_len: u8,
    ) error{InvalidRange}![]const u32 {
        const count = try self.validate(cell, combining_len);
        return self.tailValidated(cell, count);
    }

    /// Validates one cell's sole scalar-count authority against its range.
    pub inline fn validate(
        self: *const Storage,
        cell: usize,
        combining_len: u8,
    ) error{InvalidRange}!usize {
        if (cell >= self.ranges.len or
            combining_len >= maximum_scalars)
            return error.InvalidRange;
        const count = @as(usize, combining_len) -|
            (inline_scalars - 1);
        const range = self.ranges[cell];
        if (range == .none)
            return if (count == 0) 0 else error.InvalidRange;
        if (count == 0 or count > maximum_tail_scalars)
            return error.InvalidRange;
        const location = decode(range);
        if (location.page >= self.pages.len or
            location.offset + count > scalar_slots)
            return error.InvalidRange;
        return count;
    }

    /// Boolean correspondence query for borrowed validation boundaries.
    pub fn validRange(
        self: *const Storage,
        cell: usize,
        combining_len: u8,
    ) bool {
        const count = self.validate(cell, combining_len) catch return false;
        return count <= maximum_tail_scalars;
    }

    /// Reports overlap with either mutable retained storage region.
    pub fn aliases(self: *const Storage, bytes: []const u8) bool {
        return overlaps(std.mem.sliceAsBytes(self.ranges), bytes) or
            overlaps(std.mem.sliceAsBytes(self.pages), bytes);
    }

    /// Reports whether two owners overlap in either mutable backing allocation.
    pub fn overlapsStorage(
        self: *const Storage,
        other: *const Storage,
    ) bool {
        return self.aliases(std.mem.sliceAsBytes(other.ranges)) or
            self.aliases(std.mem.sliceAsBytes(other.pages));
    }

    /// Returns the exact number of cell range records owned by this cohort.
    pub fn cellCapacity(self: *const Storage) usize {
        return self.ranges.len;
    }

    /// Reports whether any fixed scalar bank owns an allocated range.
    ///
    /// Prepared ranges count as allocated until they are released or
    /// committed, so callers may safely skip cell-by-cell tail cleanup only
    /// when this reports false.
    pub fn hasAllocatedRanges(self: *const Storage) bool {
        for (self.pages) |*page| {
            if (page.free_count != 1) return true;
            const free = page.free_regions[0];
            if (free.offset != 0 or free.count != scalar_slots) return true;
        }
        return false;
    }

    /// Plans the next deterministic first-fit range without mutating storage.
    ///
    /// The outgoing cells are treated as virtually free. Earlier plans are
    /// treated as occupied. Counts come only from their owning cell state.
    pub fn planFirstFit(
        self: *const Storage,
        count: usize,
        outgoing_start: usize,
        outgoing_combining: []const u8,
        planned: []const Range,
        planned_combining: []const u8,
    ) error{ InvalidRange, ScalarCapacity }!Range {
        if (count == 0 or count > maximum_tail_scalars or
            planned.len != planned_combining.len or
            outgoing_start > self.ranges.len or
            outgoing_combining.len > self.ranges.len - outgoing_start)
            return error.InvalidRange;
        for (outgoing_combining, 0..) |combining_len, index| {
            const validated = try self.validate(
                outgoing_start + index,
                combining_len,
            );
            // zig-audit: acknowledge unreachable
            // reason: The surrounding validation and exhaustive state machine exclude this branch; reaching it would prove an internal invariant violation.
            if (validated > maximum_tail_scalars) unreachable;
        }
        for (planned, planned_combining) |range, combining_len| {
            const planned_count = tailCount(combining_len) orelse
                return error.InvalidRange;
            if ((range == .none) != (planned_count == 0))
                return error.InvalidRange;
            if (range != .none) {
                const location = decode(range);
                if (location.page >= self.pages.len or
                    location.offset + planned_count > scalar_slots)
                    return error.InvalidRange;
            }
        }

        for (self.pages, 0..) |_, page_index| {
            var offset: usize = 0;
            while (offset + count <= scalar_slots) : (offset += 1) {
                if (self.planExtentFree(
                    page_index,
                    offset,
                    count,
                    outgoing_start,
                    outgoing_combining,
                    planned,
                    planned_combining,
                )) {
                    const absolute = page_index * scalar_slots + offset;
                    return @fromBackingInt(
                        @as(u32, @intCast(absolute)) + 1,
                    );
                }
            }
        }
        return error.ScalarCapacity;
    }

    /// Replaces one exact lead tail transactionally.
    pub fn set(
        self: *Storage,
        cell: usize,
        old_combining_len: u8,
        values: []const u32,
    ) error{ InvalidRange, ScalarCapacity }!void {
        if (cell >= self.ranges.len)
            return error.InvalidRange;
        if (values.len == 0 or values.len > maximum_tail_scalars)
            return error.ScalarCapacity;
        const old_count = try self.validate(cell, old_combining_len);
        // zig-audit: acknowledge unreachable
        // reason: The surrounding validation and exhaustive state machine exclude this branch; reaching it would prove an internal invariant violation.
        if (old_count > maximum_tail_scalars) unreachable;
        const old = self.ranges[cell];
        if (old != .none and std.mem.eql(
            u32,
            try self.tail(cell, old_combining_len),
            values,
        ))
            return;

        var prepared = try self.prepare(values);
        try prepared.commit(cell, old_combining_len);
    }

    /// Experimental fallible growth path. The existing `set` contract remains
    /// allocation-free until terminal input can retain/retry failures safely.
    pub fn setGrowing(
        self: *Storage,
        cell: usize,
        old_combining_len: u8,
        values: []const u32,
    ) error{ InvalidRange, ScalarCapacity, OutOfMemory }!void {
        if (values.len == 0 or values.len > maximum_tail_scalars)
            return error.ScalarCapacity;
        self.set(cell, old_combining_len, values) catch |failure| switch (failure) {
            error.InvalidRange => return failure,
            error.ScalarCapacity => {
                // Values may borrow the old page array, which growth replaces.
                var copied: [maximum_tail_scalars]u32 = undefined;
                @memcpy(copied[0..values.len], values);
                try self.growOnePage();
                try self.set(cell, old_combining_len, copied[0..values.len]);
            },
        };
    }

    /// Reserves and initializes one exact range before any caller mutation.
    pub fn prepare(
        self: *Storage,
        values: []const u32,
    ) error{ScalarCapacity}!Prepared {
        if (values.len == 0 or values.len > maximum_tail_scalars)
            return error.ScalarCapacity;
        const allocation = self.find(values.len) orelse
            return error.ScalarCapacity;
        const page = &self.pages[allocation.page];
        const offset = page.free_regions[allocation.region].offset;
        consume(page, allocation.region, values.len);
        @memcpy(page.scalars[offset..][0..values.len], values);
        const absolute = std.math.add(
            usize,
            // zig-audit: acknowledge catch_unreachable
            // reason: The operation runs on state or storage already validated/reserved by this owner; failure would contradict the established invariant.
            std.math.mul(usize, allocation.page, scalar_slots) catch unreachable,
            offset,
            // zig-audit: acknowledge catch_unreachable
            // reason: The operation runs on state or storage already validated/reserved by this owner; failure would contradict the established invariant.
        ) catch unreachable;
        std.debug.assert(absolute < std.math.maxInt(u32));
        return .{
            .owner = self,
            .range = @fromBackingInt(@intCast(@as(u32, @intCast(absolute)) + 1)),
            .count = @intCast(values.len),
        };
    }

    /// Releases one exact cell range and restores canonical zero ownership.
    pub inline fn clear(
        self: *Storage,
        cell: usize,
        combining_len: u8,
    ) error{InvalidRange}!void {
        const count = try self.validate(cell, combining_len);
        self.clearValidated(cell, count);
    }

    inline fn clearValidated(self: *Storage, cell: usize, count: usize) void {
        const old = self.ranges[cell];
        if (old == .none) return;
        self.ranges[cell] = .none;
        self.release(old, count);
    }

    /// Transfers one accepted range without allocating or copying scalar bytes.
    pub fn move(
        self: *Storage,
        source: usize,
        source_combining_len: u8,
        destination: usize,
        destination_combining_len: u8,
    ) error{InvalidRange}!void {
        const source_count = try self.validate(source, source_combining_len);
        const destination_count = try self.validate(
            destination,
            destination_combining_len,
        );
        if (source_count > maximum_tail_scalars or
            destination_count > maximum_tail_scalars)
            // zig-audit: acknowledge unreachable
            // reason: The surrounding validation and exhaustive state machine exclude this branch; reaching it would prove an internal invariant violation.
            unreachable;
        if (source == destination) return;
        try self.clear(destination, destination_combining_len);
        self.ranges[destination] = self.ranges[source];
        self.ranges[source] = .none;
    }

    /// Copies one sequence into independent destination ownership.
    pub fn copy(
        source: *const Storage,
        source_cell: usize,
        source_combining_len: u8,
        destination: *Storage,
        destination_cell: usize,
        destination_combining_len: u8,
    ) error{ InvalidRange, ScalarCapacity }!void {
        const source_count = try source.validate(
            source_cell,
            source_combining_len,
        );
        const destination_count = try destination.validate(
            destination_cell,
            destination_combining_len,
        );
        if (source_count > maximum_tail_scalars or
            destination_count > maximum_tail_scalars)
            // zig-audit: acknowledge unreachable
            // reason: The surrounding validation and exhaustive state machine exclude this branch; reaching it would prove an internal invariant violation.
            unreachable;
        const values = try source.tail(source_cell, source_combining_len);
        if (values.len == 0) {
            try destination.clear(
                destination_cell,
                destination_combining_len,
            );
            return;
        }
        try destination.set(
            destination_cell,
            destination_combining_len,
            values,
        );
    }

    /// Clears every range and restores every bank to one free region.
    pub fn clearAll(self: *Storage) void {
        @memset(self.ranges, .none);
        for (self.pages) |*page| page.* = Page.init();
    }

    fn find(self: *const Storage, count: usize) ?struct {
        page: usize,
        region: usize,
    } {
        for (self.pages, 0..) |page, page_index| {
            for (page.free_regions[0..page.free_count], 0..) |region, region_index| {
                if (region.count >= count)
                    return .{ .page = page_index, .region = region_index };
            }
        }
        return null;
    }

    fn planExtentFree(
        self: *const Storage,
        page_index: usize,
        offset: usize,
        count: usize,
        outgoing_start: usize,
        outgoing_combining: []const u8,
        planned: []const Range,
        planned_combining: []const u8,
    ) bool {
        var scalar = offset;
        while (scalar < offset + count) : (scalar += 1) {
            if (!self.slotVirtuallyFree(
                page_index,
                scalar,
                outgoing_start,
                outgoing_combining,
            )) return false;
            for (planned, planned_combining) |range, combining_len| {
                if (range == .none) continue;
                const location = decode(range);
                const planned_count = tailCount(combining_len) orelse
                    return false;
                if (location.page == page_index and
                    scalar >= location.offset and
                    scalar < location.offset + planned_count)
                    return false;
            }
        }
        return true;
    }

    fn slotVirtuallyFree(
        self: *const Storage,
        page_index: usize,
        scalar: usize,
        outgoing_start: usize,
        outgoing_combining: []const u8,
    ) bool {
        const page = &self.pages[page_index];
        for (page.free_regions[0..page.free_count]) |region| {
            if (scalar >= region.offset and
                scalar < @as(usize, region.offset) + region.count)
                return true;
        }
        for (outgoing_combining, 0..) |combining_len, index| {
            const range = self.ranges[outgoing_start + index];
            if (range == .none) continue;
            const location = decode(range);
            const count = tailCount(combining_len) orelse return false;
            if (location.page == page_index and
                scalar >= location.offset and scalar < location.offset + count)
                return true;
        }
        return false;
    }

    fn tailCount(combining_len: u8) ?usize {
        if (combining_len >= maximum_scalars) return null;
        return @as(usize, combining_len) -| (inline_scalars - 1);
    }

    fn tailValidated(
        self: *const Storage,
        cell: usize,
        count: usize,
    ) []const u32 {
        const range = self.ranges[cell];
        if (range == .none) return &.{};
        const location = decode(range);
        return self.pages[location.page].scalars[location.offset..][0..count];
    }

    fn consume(page: *Page, region_index: usize, count: usize) void {
        const region = &page.free_regions[region_index];
        std.debug.assert(region.count >= count);
        region.offset += @intCast(count);
        region.count -= @intCast(count);
        if (region.count != 0) return;
        std.mem.copyForwards(
            FreeRegion,
            page.free_regions[region_index .. page.free_count - 1],
            page.free_regions[region_index + 1 .. page.free_count],
        );
        page.free_count -= 1;
        page.free_regions[page.free_count] = .{ .offset = 0, .count = 0 };
    }

    fn release(self: *Storage, range: Range, range_count: usize) void {
        const location = decode(range);
        const page = &self.pages[location.page];
        const offset: u16 = @intCast(location.offset);
        const count: u16 = @intCast(range_count);
        @memset(page.scalars[offset..][0..count], 0);
        var index: usize = 0;
        while (index < page.free_count and
            page.free_regions[index].offset < offset) : (index += 1)
        {}
        const joins_previous = index != 0 and
            @as(usize, page.free_regions[index - 1].offset) +
                page.free_regions[index - 1].count == offset;
        const joins_next = index < page.free_count and
            @as(usize, offset) + count == page.free_regions[index].offset;
        if (joins_previous and joins_next) {
            page.free_regions[index - 1].count +=
                count + page.free_regions[index].count;
            std.mem.copyForwards(
                FreeRegion,
                page.free_regions[index .. page.free_count - 1],
                page.free_regions[index + 1 .. page.free_count],
            );
            page.free_count -= 1;
            return;
        }
        if (joins_previous) {
            page.free_regions[index - 1].count += count;
            return;
        }
        if (joins_next) {
            page.free_regions[index].offset = offset;
            page.free_regions[index].count += count;
            return;
        }
        std.debug.assert(page.free_count < page.free_regions.len);
        std.mem.copyBackwards(
            FreeRegion,
            page.free_regions[index + 1 .. page.free_count + 1],
            page.free_regions[index..page.free_count],
        );
        page.free_regions[index] = .{ .offset = offset, .count = count };
        page.free_count += 1;
    }

    fn decode(range: Range) struct { page: usize, offset: usize } {
        std.debug.assert(range != .none);
        const absolute: usize = @backingInt(range) - 1;
        return .{
            .page = absolute / scalar_slots,
            .offset = absolute % scalar_slots,
        };
    }

    fn overlaps(first: []const u8, second: []const u8) bool {
        if (first.len == 0 or second.len == 0) return false;
        const first_start = @intFromPtr(first.ptr);
        const second_start = @intFromPtr(second.ptr);
        return if (first_start <= second_start)
            second_start - first_start < first.len
        else
            first_start - second_start < second.len;
    }
};

/// Owns one initialized but not yet cell-associated range.
pub const Prepared = struct {
    owner: *Storage,
    range: Range,
    count: u5,
    active: bool = true,

    /// Associates the prepared range with one exact cell without failure.
    pub fn commit(
        self: *Prepared,
        cell: usize,
        old_combining_len: u8,
    ) error{InvalidRange}!void {
        if (!self.active) return error.InvalidRange;
        const old_count = try self.owner.validate(cell, old_combining_len);
        self.commitValidated(cell, old_count);
    }

    /// Commits only when preflight predicted this exact first-fit identity.
    pub fn commitPlanned(
        self: *Prepared,
        expected: Range,
        cell: usize,
        old_combining_len: u8,
    ) error{InvalidRange}!void {
        if (self.range != expected) return error.InvalidRange;
        try self.commit(cell, old_combining_len);
    }

    fn commitValidated(self: *Prepared, cell: usize, old_count: usize) void {
        std.debug.assert(self.active and cell < self.owner.ranges.len);
        const old = self.owner.ranges[cell];
        self.owner.ranges[cell] = self.range;
        if (old != .none) self.owner.release(old, old_count);
        self.active = false;
    }

    /// Releases a cancelled reservation exactly.
    pub fn deinit(self: *Prepared) void {
        if (!self.active) return;
        self.owner.release(self.range, self.count);
        self.active = false;
    }
};

fn testCombiningLen(tail_count: usize) u8 {
    return @intCast(tail_count + inline_scalars - 1);
}

test "bounded scalar storage cleans up every fixed construction failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        testConstructStorage,
        .{},
    );
}

fn testConstructStorage(allocator: std.mem.Allocator) !void {
    var storage = try Storage.init(allocator, page_cells * 2);
    storage.deinit();
}

test "bounded scalar storage transfers ownership across physical pages" {
    var storage = try Storage.init(std.testing.allocator, page_cells * 2);
    defer storage.deinit();
    const values = [_]u32{ 5, 6, 7, 8, 9 };
    try storage.set(page_cells - 1, 0, &values);
    try storage.move(
        page_cells - 1,
        testCombiningLen(values.len),
        page_cells,
        0,
    );
    try std.testing.expectEqualSlices(
        u32,
        &values,
        try storage.tail(page_cells, testCombiningLen(values.len)),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        (try storage.tail(page_cells - 1, 0)).len,
    );
}

test "allocated range fact follows prepared and committed scalar ownership" {
    var storage = try Storage.init(std.testing.allocator, page_cells * 2);
    defer storage.deinit();
    try std.testing.expect(!storage.hasAllocatedRanges());

    var prepared = try storage.prepare(&.{ 1, 2, 3, 4, 5 });
    try std.testing.expect(storage.hasAllocatedRanges());
    prepared.deinit();
    try std.testing.expect(!storage.hasAllocatedRanges());

    try storage.set(17, 0, &.{ 6, 7, 8, 9, 10 });
    try std.testing.expect(storage.hasAllocatedRanges());
    try storage.clear(17, testCombiningLen(5));
    try std.testing.expect(!storage.hasAllocatedRanges());
}

test "cross-page move ignores full destination-associated bank" {
    var storage = try Storage.init(std.testing.allocator, page_cells * 2);
    defer storage.deinit();
    const source_values = [_]u32{ 1, 2, 3, 4, 5 };
    try storage.set(0, 0, &source_values);
    const full: [maximum_tail_scalars]u32 = @splat(9);
    var cell: usize = 1;
    var bank_zero_full: usize = 0;
    while (bank_zero_full < (scalar_slots - source_values.len) /
        maximum_tail_scalars) : (bank_zero_full += 1)
    {
        try storage.set(cell, 0, &full);
        cell += 1;
    }
    var remainder: [maximum_tail_scalars]u32 = @splat(7);
    const first_remainder = (scalar_slots - source_values.len) %
        maximum_tail_scalars;
    try storage.set(cell, 0, remainder[0..first_remainder]);
    cell += 1;
    var bank_one_full: usize = 0;
    while (bank_one_full < scalar_slots / maximum_tail_scalars) : (bank_one_full += 1) {
        try storage.set(cell, 0, &full);
        cell += 1;
    }
    const second_remainder = scalar_slots % maximum_tail_scalars;
    try storage.set(cell, 0, remainder[0..second_remainder]);
    const token = storage.ranges[0];
    try std.testing.expectError(
        error.ScalarCapacity,
        storage.set(page_cells, 0, &.{42}),
    );
    try storage.move(
        0,
        testCombiningLen(source_values.len),
        page_cells,
        0,
    );
    try std.testing.expectEqual(.none, storage.ranges[0]);
    try std.testing.expectEqual(token, storage.ranges[page_cells]);
    try std.testing.expectEqualSlices(
        u32,
        &source_values,
        try storage.tail(
            page_cells,
            testCombiningLen(source_values.len),
        ),
    );
}

test "cleared offsets are canonical and owner copies never transfer tokens" {
    var first = try Storage.init(std.testing.allocator, page_cells);
    defer first.deinit();
    var second = try Storage.init(std.testing.allocator, page_cells);
    defer second.deinit();
    const values = [_]u32{ 3, 1, 4, 1, 5 };
    try first.set(17, 0, &values);
    const first_token = first.ranges[17];
    try Storage.copy(
        &first,
        17,
        testCombiningLen(values.len),
        &second,
        23,
        0,
    );
    try std.testing.expect(first.ranges[17] == first_token);
    try std.testing.expect(second.ranges[23] != .none);
    try first.clear(17, testCombiningLen(values.len));
    try std.testing.expectEqual(.none, first.ranges[17]);
    try std.testing.expectEqual(@as(usize, 0), (try first.tail(17, 0)).len);
    try std.testing.expectEqualSlices(
        u32,
        &values,
        try second.tail(23, testCombiningLen(values.len)),
    );
    try second.clear(23, testCombiningLen(values.len));
    try std.testing.expectEqual(.none, second.ranges[23]);
    try std.testing.expect(second.validRange(23, 0));
    try std.testing.expect(!second.validRange(
        23,
        testCombiningLen(values.len),
    ));
}

test "bounded scalar pressure preserves accepted bytes" {
    var storage = try Storage.init(std.testing.allocator, page_cells);
    defer storage.deinit();
    const full: [maximum_tail_scalars]u32 = @splat(1);
    var cell: usize = 0;
    while (cell < scalar_slots / maximum_tail_scalars) : (cell += 1)
        try storage.set(cell, 0, &full);
    const remainder: [scalar_slots % maximum_tail_scalars]u32 = @splat(2);
    try storage.set(cell, 0, &remainder);
    cell += 1;
    const before_range = storage.ranges[cell];
    try std.testing.expectError(error.ScalarCapacity, storage.set(cell, 0, &.{5}));
    try std.testing.expectEqual(before_range, storage.ranges[cell]);
}

test "set classifies an invalid cell index without mutation" {
    var storage = try Storage.init(std.testing.allocator, 1);
    defer storage.deinit();
    const ranges_before = storage.ranges[0];
    const pages_before = storage.pages[0];
    try std.testing.expectError(
        error.InvalidRange,
        storage.set(1, 0, &.{1}),
    );
    try std.testing.expectEqual(ranges_before, storage.ranges[0]);
    try std.testing.expectEqualDeep(pages_before, storage.pages[0]);
}

test "absolute range encoding covers maximum existing VT dimensions" {
    const maximum_cells = @as(usize, std.math.maxInt(u16)) *
        @as(usize, std.math.maxInt(u16));
    const bank_count = try std.math.divCeil(usize, maximum_cells, page_cells);
    const slot_count = try std.math.mul(usize, bank_count, scalar_slots);
    try std.testing.expectEqual(@as(usize, 4_294_836_225), maximum_cells);
    try std.testing.expectEqual(@as(usize, 1_048_545), bank_count);
    try std.testing.expectEqual(@as(usize, 2_147_420_160), slot_count);
    try std.testing.expect(slot_count <= std.math.maxInt(u32));
    try std.testing.expect(slot_count <= @as(usize, 1) << 31);

    const final: Range = @fromBackingInt(@intCast(@as(u32, @intCast(slot_count))));
    const decoded = Storage.decode(final);
    try std.testing.expectEqual(bank_count - 1, decoded.page);
    try std.testing.expectEqual(scalar_slots - 1, decoded.offset);
    try std.testing.expectEqual(@as(usize, 4), @sizeOf(Range));
}

test "range validity derives presence and count from the owning cell state" {
    var storage = try Storage.init(std.testing.allocator, page_cells * 2);
    defer storage.deinit();

    try std.testing.expect(storage.validRange(page_cells + 7, 0));
    try std.testing.expect(!storage.validRange(
        page_cells + 7,
        inline_scalars,
    ));

    const values = [_]u32{ 1, 2, 3, 4, 5 };
    try storage.set(page_cells + 7, 0, &values);
    try std.testing.expect(storage.validRange(
        page_cells + 7,
        testCombiningLen(values.len),
    ));
    try std.testing.expect(!storage.validRange(page_cells + 7, 0));
    try std.testing.expect(!storage.validRange(
        page_cells + 7,
        maximum_scalars,
    ));
}

test "owner-native alias ranges preserve exact boundary semantics" {
    var storage = try Storage.init(std.testing.allocator, page_cells);
    defer storage.deinit();
    const owned = std.mem.sliceAsBytes(storage.ranges);

    try std.testing.expect(!Storage.overlaps(owned[0..0], owned));
    try std.testing.expect(!Storage.overlaps(owned[0..8], owned[8..16]));
    try std.testing.expect(Storage.overlaps(owned[0..8], owned[7..16]));
    try std.testing.expect(Storage.overlaps(owned[0..16], owned[4..12]));
    try std.testing.expect(Storage.overlaps(owned[4..12], owned[0..16]));
    try std.testing.expect(!Storage.overlaps(owned[0..4], owned[8..12]));
    try std.testing.expect(storage.aliases(owned[8..16]));

    const shallow_alias = storage;
    try std.testing.expect(storage.overlapsStorage(&shallow_alias));

    var independent = try Storage.init(std.testing.allocator, page_cells);
    defer independent.deinit();
    try std.testing.expect(!storage.overlapsStorage(&independent));
}

test "invalid source and destination correspondence preserves all ownership" {
    var first = try Storage.init(std.testing.allocator, page_cells);
    defer first.deinit();
    var second = try Storage.init(std.testing.allocator, page_cells);
    defer second.deinit();
    const values = [_]u32{ 8, 6, 7, 5, 3, 0, 9 };
    const accepted_len = testCombiningLen(values.len);
    try first.set(11, 0, &values);
    try second.set(19, 0, &values);

    const first_ranges = try std.testing.allocator.dupe(Range, first.ranges);
    defer std.testing.allocator.free(first_ranges);
    const first_pages = try std.testing.allocator.dupe(Page, first.pages);
    defer std.testing.allocator.free(first_pages);
    const second_ranges = try std.testing.allocator.dupe(Range, second.ranges);
    defer std.testing.allocator.free(second_ranges);
    const second_pages = try std.testing.allocator.dupe(Page, second.pages);
    defer std.testing.allocator.free(second_pages);

    try std.testing.expectError(
        error.InvalidRange,
        first.set(11, 0, &.{1}),
    );
    try std.testing.expectError(error.InvalidRange, first.clear(11, 0));
    try std.testing.expectError(error.InvalidRange, first.tail(11, 0));
    try std.testing.expectError(
        error.InvalidRange,
        first.move(11, 0, 12, 0),
    );
    try std.testing.expectError(
        error.InvalidRange,
        Storage.copy(&first, 11, 0, &second, 19, accepted_len),
    );
    var prepared = try first.prepare(&.{1});
    try std.testing.expectError(
        error.InvalidRange,
        prepared.commit(11, 0),
    );
    prepared.deinit();

    try std.testing.expectEqualSlices(Range, first_ranges, first.ranges);
    try std.testing.expectEqualSlices(u8, std.mem.sliceAsBytes(first_pages), std.mem.sliceAsBytes(first.pages));
    try std.testing.expectEqualSlices(Range, second_ranges, second.ranges);
    try std.testing.expectEqualSlices(u8, std.mem.sliceAsBytes(second_pages), std.mem.sliceAsBytes(second.pages));
}

test "virtual outgoing preflight exactly predicts infallible first fit" {
    var storage = try Storage.init(std.testing.allocator, page_cells);
    defer storage.deinit();
    const first = [_]u32{ 1, 2, 3, 4, 5 };
    const second = [_]u32{ 6, 7, 8 };
    try storage.set(10, 0, &first);
    try storage.set(11, 0, &second);
    const outgoing = [_]u8{
        testCombiningLen(first.len),
        testCombiningLen(second.len),
    };
    const incoming = [_]u8{
        testCombiningLen(second.len),
        testCombiningLen(first.len),
    };
    var plans = [_]Range{ .none, .none };
    plans[0] = try storage.planFirstFit(
        second.len,
        10,
        &outgoing,
        plans[0..0],
        incoming[0..0],
    );
    plans[1] = try storage.planFirstFit(
        first.len,
        10,
        &outgoing,
        plans[0..1],
        incoming[0..1],
    );

    try storage.clear(10, outgoing[0]);
    try storage.clear(11, outgoing[1]);
    var prepared_first = try storage.prepare(&second);
    try std.testing.expectEqual(plans[0], prepared_first.range);
    try prepared_first.commit(10, 0);
    var prepared_second = try storage.prepare(&first);
    try std.testing.expectEqual(plans[1], prepared_second.range);
    try prepared_second.commit(11, 0);
}

test "fresh copy reserves for concentrated accepted tails" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidCapacity, Storage.initForCopy(allocator, 1, maximum_tail_scalars + 1));
    var storage = try Storage.initForCopy(allocator, 512, 512 * 5);
    defer storage.deinit();
    const values = [_]u32{ 1, 2, 3, 4, 5 };
    for (0..512) |cell| try storage.set(cell, 0, &values);
    for (0..512) |cell| try std.testing.expectEqualSlices(u32, &values, try storage.tail(cell, testCombiningLen(values.len)));
}

test "fresh copy packs varied bounded ranges without assuming exact page division" {
    const allocator = std.testing.allocator;
    var scalar_count: usize = 0;
    for (0..512) |cell| scalar_count += 1 + cell % maximum_tail_scalars;
    var storage = try Storage.initForCopy(allocator, 512, scalar_count);
    defer storage.deinit();
    const values: [maximum_tail_scalars]u32 = @splat(7);
    for (0..512) |cell| {
        const count = 1 + cell % maximum_tail_scalars;
        try storage.set(cell, 0, values[0..count]);
    }
    for (0..512) |cell| {
        const count = 1 + cell % maximum_tail_scalars;
        try std.testing.expectEqualSlices(u32, values[0..count], try storage.tail(cell, testCombiningLen(count)));
    }
}

fn initConcentratedCopy(allocator: std.mem.Allocator) !void {
    var storage = try Storage.initForCopy(allocator, 512, 512 * 5);
    defer storage.deinit();
}

test "concentrated copy initialization releases partial allocations" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, initConcentratedCopy, .{});
}

test "explicit growth preserves ranges and failed allocation leaves storage intact" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var storage = try Storage.init(failing.allocator(), 512);
    defer storage.deinit();
    const values: [maximum_tail_scalars]u32 = @splat(17);
    var used: usize = 0;
    while (used < scalar_slots / maximum_tail_scalars) : (used += 1) try storage.set(used, 0, &values);
    try std.testing.expectError(error.ScalarCapacity, storage.set(used, 0, &values));
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, storage.growOnePage());
    try std.testing.expectEqual(@as(usize, 1), storage.pages.len);
    try std.testing.expectEqualSlices(u32, &values, try storage.tail(0, testCombiningLen(values.len)));
    failing.fail_index = std.math.maxInt(usize);
    try storage.growOnePage();
    try storage.set(used, 0, &values);
    try std.testing.expectEqualSlices(u32, &values, try storage.tail(0, testCombiningLen(values.len)));
    try std.testing.expectEqualSlices(u32, &values, try storage.tail(used, testCombiningLen(values.len)));
}

test "explicit bounded growth retains concentrated and diverse tails" {
    var storage = try Storage.init(std.testing.allocator, 512);
    defer storage.deinit();
    var expected: [maximum_tail_scalars]u32 = undefined;
    for (0..512) |cell| {
        const count = 1 + cell % maximum_tail_scalars;
        for (0..count) |i| expected[i] = @intCast(cell * maximum_tail_scalars + i);
        storage.set(cell, 0, expected[0..count]) catch |failure| switch (failure) {
            error.ScalarCapacity => {
                try storage.growOnePage();
                try storage.set(cell, 0, expected[0..count]);
            },
            error.InvalidRange => return failure,
        };
    }
    try std.testing.expect(storage.pages.len > 1);
    for (0..512) |cell| {
        const count = 1 + cell % maximum_tail_scalars;
        for (0..count) |i| expected[i] = @intCast(cell * maximum_tail_scalars + i);
        try std.testing.expectEqualSlices(u32, expected[0..count], try storage.tail(cell, testCombiningLen(count)));
    }
    while (true) storage.growOnePage() catch |failure| switch (failure) {
        error.ScalarCapacity => break,
        error.OutOfMemory => return failure,
    };
    try std.testing.expectError(error.ScalarCapacity, storage.growOnePage());
    for (0..512) |cell| {
        const count = 1 + cell % maximum_tail_scalars;
        for (0..count) |i| expected[i] = @intCast(cell * maximum_tail_scalars + i);
        try std.testing.expectEqualSlices(u32, expected[0..count], try storage.tail(cell, testCombiningLen(count)));
    }
}

test "fragmented pool grows without invalidating retained tails" {
    var storage = try Storage.init(std.testing.allocator, 512);
    defer storage.deinit();
    const filler: [19]u32 = @splat(11);
    for (0..102) |i| {
        try storage.set(i * 2, 0, &.{7});
        try storage.set(i * 2 + 1, 0, &filler);
    }
    try storage.set(204, 0, &.{ 1, 2, 3, 4, 5, 6, 7, 8 });
    for (0..102) |i| try storage.clear(i * 2 + 1, testCombiningLen(filler.len));
    const long: [20]u32 = @splat(99);
    try std.testing.expectError(error.ScalarCapacity, storage.set(205, 0, &long));
    try storage.growOnePage();
    try storage.set(205, 0, &long);
    for (0..102) |i| try std.testing.expectEqualSlices(u32, &.{7}, try storage.tail(i * 2, testCombiningLen(1)));
    try std.testing.expectEqualSlices(u32, &long, try storage.tail(205, testCombiningLen(20)));
}

test "bounded page growth survives deterministic scalar churn" {
    const cells = 256;
    var storage = try Storage.init(std.testing.allocator, cells);
    defer storage.deinit();
    var lengths: [cells]u8 = @splat(0);
    var random: u64 = 0x82719fed103;
    for (0..30000) |turn| {
        random = random *% 6364136223846793005 +% 1442695040888963407;
        const cell: usize = @intCast((random >> 16) % cells);
        const old = lengths[cell];
        const old_combining = if (old == 0) 0 else testCombiningLen(old);
        if ((random >> 40) % 5 == 0) {
            try storage.clear(cell, old_combining);
            lengths[cell] = 0;
        } else {
            const count: usize = @intCast(1 + ((random >> 32) % maximum_tail_scalars));
            var values: [maximum_tail_scalars]u32 = undefined;
            @memset(values[0..count], @intCast(cell + 1));
            storage.set(cell, old_combining, values[0..count]) catch |failure| switch (failure) {
                error.ScalarCapacity => {
                    try storage.growOnePage();
                    try storage.set(cell, old_combining, values[0..count]);
                },
                error.InvalidRange => return failure,
            };
            lengths[cell] = @intCast(count);
        }
        if (turn % 97 == 0) {
            for (lengths, 0..) |length, i| {
                if (length == 0) continue;
                const actual = try storage.tail(i, testCombiningLen(length));
                try std.testing.expectEqual(@as(usize, length), actual.len);
                for (actual) |value| try std.testing.expectEqual(@as(u32, @intCast(i + 1)), value);
            }
        }
    }
}

test "fallible growing set preserves old tails on out of memory" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var storage = try Storage.init(failing.allocator(), 512);
    defer storage.deinit();
    const values: [20]u32 = @splat(7);
    for (0..102) |cell| try storage.set(cell, 0, &values);
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, storage.setGrowing(102, 0, &values));
    try std.testing.expectEqual(@as(usize, 1), storage.pages.len);
    try std.testing.expectEqualSlices(u32, &values, try storage.tail(0, testCombiningLen(20)));
    try std.testing.expectEqual(@as(usize, 0), (try storage.tail(102, 0)).len);
    failing.fail_index = std.math.maxInt(usize);
    try storage.setGrowing(102, 0, &values);
    try std.testing.expectEqualSlices(u32, &values, try storage.tail(102, testCombiningLen(20)));
}

test "fallible growing set preserves values borrowed from a relocated page" {
    var storage = try Storage.init(std.testing.allocator, 512);
    defer storage.deinit();
    const values: [20]u32 = @splat(17);
    for (0..102) |cell| try storage.set(cell, 0, &values);
    const borrowed = try storage.tail(0, testCombiningLen(20));
    try storage.setGrowing(102, 0, borrowed);
    try std.testing.expectEqualSlices(u32, &values, try storage.tail(102, testCombiningLen(20)));
    try std.testing.expectEqualSlices(u32, &values, try storage.tail(0, testCombiningLen(20)));
}

test "growing set stays allocation free while existing pages fit" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var storage = try Storage.init(failing.allocator(), 512);
    defer storage.deinit();
    failing.fail_index = failing.alloc_index;
    try storage.setGrowing(0, 0, &.{ 1, 2, 3 });
    try std.testing.expect(!failing.has_induced_failure);
    try std.testing.expectEqualSlices(u32, &.{ 1, 2, 3 }, try storage.tail(0, testCombiningLen(3)));
}

test "growth budget admits a heavily fragmented valid page layout" {
    var storage = try Storage.init(std.testing.allocator, 512);
    defer storage.deinit();
    // Seven pages each hold 53 separate 20-scalar tails with 19-slot gaps.
    // Although 141 cell records remain free, no page can fit one more tail.
    while (storage.pages.len < 7) try storage.growOnePage();
    var index: usize = 0;
    for (storage.pages, 0..) |*page, page_index| {
        page.* = Page.init();
        page.free_count = 52;
        for (0..53) |range_index| {
            const offset = range_index * 39;
            @memset(page.scalars[offset..][0..20], 17);
            storage.ranges[index] = @fromBackingInt(@intCast(page_index * scalar_slots + offset + 1));
            index += 1;
            if (range_index < 52) page.free_regions[range_index] = .{ .offset = @intCast(offset + 20), .count = 19 };
        }
    }
    const values: [20]u32 = @splat(29);
    try storage.setGrowing(index, 0, &values);
    try std.testing.expectEqual(@as(usize, 8), storage.pages.len);
    try std.testing.expectEqualSlices(u32, &values, try storage.tail(index, testCombiningLen(20)));
    for (0..index) |cell| {
        const retained = try storage.tail(cell, testCombiningLen(20));
        for (retained) |value| try std.testing.expectEqual(@as(u32, 17), value);
    }
}
