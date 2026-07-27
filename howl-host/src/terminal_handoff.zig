//! Owns one bounded copied terminal-producer update pending Renderer drainage.

const std = @import("std");
const render = @import("howl_render");
const canvas = render.canvas;
const terminal = render.terminal;

/// Reports invalid construction limits or allocation failure.
pub const InitError = error{
    InvalidLimits,
    OutOfMemory,
    ArithmeticOverflow,
};

/// Reports producer admission or exact terminal-update production failure.
pub const PublishError = error{
    InvalidContentLimits,
    Pending,
    Retired,
} || terminal.Content.TakeError;

/// Reports concurrent ownership transfer during pane retirement.
pub const RetireError = error{Busy};

const State = enum(u8) {
    free,
    writing,
    ready,
    draining,
    retired,
};

/// Transfers one copied `canvas.ProducerUpdate` between terminal and Renderer.
///
/// Successful initialization performs every allocation. `publish` performs
/// atomic admission before consuming terminal Content. Release/acquire state
/// transitions make copied bytes immutable and visible to exactly one Renderer
/// drain. Retirement may discard a ready update without applying it.
pub const PendingSlot = struct {
    allocator: std.mem.Allocator,
    uploads: []canvas.ResourceUpload,
    removals: []canvas.ResourceRemoval,
    commands: []canvas.Input,
    pixels: []u8,
    upload_count: usize = 0,
    removal_count: usize = 0,
    command_count: usize = 0,
    revision: canvas.ProducerRevision = @fromBackingInt(@intCast(0)),
    state: std.atomic.Value(u8) = .init(@backingInt(State.free)),

    /// Allocates the exact terminal Content transfer capacity transactionally.
    pub fn init(
        allocator: std.mem.Allocator,
        limits: terminal.Content.Limits,
    ) InitError!PendingSlot {
        if (limits.resources_per_update == 0 or limits.commands == 0 or
            limits.upload_bytes == 0)
            return error.InvalidLimits;
        const requested = requiredBytes(limits) catch
            return error.ArithmeticOverflow;
        if (requested == 0) return error.InvalidLimits;
        const uploads = allocator.alloc(
            canvas.ResourceUpload,
            limits.resources_per_update,
        ) catch
            return error.OutOfMemory;
        errdefer allocator.free(uploads);
        const removals = allocator.alloc(
            canvas.ResourceRemoval,
            limits.resources_per_update,
        ) catch
            return error.OutOfMemory;
        errdefer allocator.free(removals);
        const commands = allocator.alloc(canvas.Input, limits.commands) catch
            return error.OutOfMemory;
        errdefer allocator.free(commands);
        const pixels = allocator.alloc(u8, limits.upload_bytes) catch
            return error.OutOfMemory;
        return .{
            .allocator = allocator,
            .uploads = uploads,
            .removals = removals,
            .commands = commands,
            .pixels = pixels,
        };
    }

    /// Releases all copied storage in reverse allocation order.
    pub fn deinit(self: *PendingSlot) void {
        const state = self.loadState(.acquire);
        std.debug.assert(state == .free or state == .retired);
        self.allocator.free(self.pixels);
        self.allocator.free(self.commands);
        self.allocator.free(self.removals);
        self.allocator.free(self.uploads);
        self.* = undefined;
    }

    /// Atomically admits and copies one consumptive terminal Content update.
    ///
    /// Slot admission happens before `takeUpdate`. Pending or retired slots
    /// therefore leave Content untouched. Slot capacity comes from the same
    /// Content limits, making the subsequent copy infallible. A production
    /// failure restores the slot to free while Content performs its own exact
    /// rollback.
    pub fn publish(
        self: *PendingSlot,
        content: *terminal.Content,
        geometry: terminal.Content.Geometry,
    ) PublishError!void {
        if (self.claim(.free, .writing)) |state| switch (state) {
            .ready, .draining, .writing => return error.Pending,
            .retired => return error.Retired,
            .free => unreachable,
        };
        errdefer self.storeState(.free, .release);
        if (content.limits.resources_per_update != self.uploads.len or
            content.limits.commands != self.commands.len or
            content.limits.upload_bytes != self.pixels.len)
            return error.InvalidContentLimits;
        const update = try content.takeUpdate(geometry);
        self.copyTaken(update);
        self.storeState(.ready, .release);
    }

    fn copyTaken(self: *PendingSlot, update: canvas.ProducerUpdate) void {
        std.debug.assert(update.uploads.len <= self.uploads.len);
        std.debug.assert(update.removals.len <= self.removals.len);
        std.debug.assert(update.commands.len <= self.commands.len);
        var pixel_offset: usize = 0;
        for (update.uploads, 0..) |upload, index| {
            const bytes = upload.pixels.bytes;
            std.debug.assert(bytes.len <= self.pixels.len - pixel_offset);
            @memcpy(self.pixels[pixel_offset..][0..bytes.len], bytes);
            self.uploads[index] = upload;
            self.uploads[index].pixels.bytes =
                self.pixels[pixel_offset..][0..bytes.len];
            pixel_offset += bytes.len;
        }
        @memcpy(self.removals[0..update.removals.len], update.removals);
        @memcpy(self.commands[0..update.commands.len], update.commands);
        self.upload_count = update.uploads.len;
        self.removal_count = update.removals.len;
        self.command_count = update.commands.len;
        self.revision = update.revision;
    }

    /// Applies one immutable pending update and leaves the slot reusable.
    ///
    /// Acquire ownership observes every producer write. Composer rejection
    /// republishes the same immutable bytes; acceptance releases the slot.
    pub fn drain(
        self: *PendingSlot,
        composer: *canvas.Composer,
        source: canvas.SourceId,
    ) canvas.Composer.Error!bool {
        if (self.claim(.ready, .draining)) |state| switch (state) {
            .free, .writing, .retired => return false,
            .draining => return false,
            .ready => unreachable,
        };
        errdefer self.storeState(.ready, .release);
        try composer.apply(source, self.borrow());
        self.storeState(.free, .release);
        return true;
    }

    /// Retires this pane's transfer ownership, discarding any ready update.
    ///
    /// The caller retires the Composer source separately. A concurrent producer
    /// copy or Renderer drain returns `Busy`; lifecycle coordination must retry
    /// only after that bounded ownership transfer finishes.
    pub fn retire(self: *PendingSlot) RetireError!bool {
        while (true) switch (self.loadState(.acquire)) {
            .free => if (self.claim(.free, .retired) == null) return false,
            .ready => if (self.claim(.ready, .retired) == null) return true,
            .writing, .draining => return error.Busy,
            .retired => return false,
        };
    }

    fn borrow(self: *const PendingSlot) canvas.ProducerUpdate {
        std.debug.assert(self.loadState(.monotonic) == .draining);
        return .{
            .revision = self.revision,
            .uploads = self.uploads[0..self.upload_count],
            .removals = self.removals[0..self.removal_count],
            .commands = self.commands[0..self.command_count],
        };
    }

    fn claim(self: *PendingSlot, from: State, to: State) ?State {
        const actual = self.state.cmpxchgStrong(
            @backingInt(from),
            @backingInt(to),
            .acq_rel,
            .acquire,
        ) orelse return null;
        return @fromBackingInt(@intCast(actual));
    }

    fn loadState(
        self: *const PendingSlot,
        comptime order: std.builtin.AtomicOrder,
    ) State {
        return @fromBackingInt(@intCast(self.state.load(order)));
    }

    fn storeState(
        self: *PendingSlot,
        state: State,
        comptime order: std.builtin.AtomicOrder,
    ) void {
        self.state.store(@backingInt(state), order);
    }
};

fn requiredBytes(
    limits: terminal.Content.Limits,
) error{ArithmeticOverflow}!usize {
    var result = std.math.mul(
        usize,
        limits.resources_per_update,
        @sizeOf(canvas.ResourceUpload),
    ) catch return error.ArithmeticOverflow;
    result = std.math.add(
        usize,
        result,
        std.math.mul(
            usize,
            limits.resources_per_update,
            @sizeOf(canvas.ResourceRemoval),
        ) catch return error.ArithmeticOverflow,
    ) catch return error.ArithmeticOverflow;
    result = std.math.add(
        usize,
        result,
        std.math.mul(
            usize,
            limits.commands,
            @sizeOf(canvas.Input),
        ) catch return error.ArithmeticOverflow,
    ) catch return error.ArithmeticOverflow;
    return std.math.add(usize, result, limits.upload_bytes) catch
        return error.ArithmeticOverflow;
}

test "copied pending update is immutable saturated and reusable" {
    var slot = try PendingSlot.init(std.testing.allocator, testLimits(1, 1, 4));
    defer slot.deinit();
    var pixels = [_]u8{ 1, 2, 3, 4 };
    var commands = [_]canvas.Input{.{ .solid = .{
        .rect = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .clip = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .color = .{ .r = 1, .g = 2, .b = 3, .a = 4 },
    } }};
    const update = canvas.ProducerUpdate{
        .revision = @fromBackingInt(@intCast(1)),
        .uploads = &.{.{
            .resource = .{
                .resource = @fromBackingInt(@intCast(1)),
                .generation = @fromBackingInt(@intCast(1)),
            },
            .format = .rgba8,
            .pixels = .{
                .bytes = &pixels,
                .width = 1,
                .height = 1,
                .stride = 4,
            },
        }},
        .removals = &.{},
        .commands = &commands,
    };
    try std.testing.expectEqual(
        @as(?State, null),
        slot.claim(.free, .writing),
    );
    slot.copyTaken(update);
    slot.storeState(.ready, .release);
    pixels = @splat(0xaa);
    commands[0].solid.color = .{ .r = 9, .g = 9, .b = 9, .a = 9 };
    try std.testing.expectEqual(
        @as(?State, .ready),
        slot.claim(.free, .writing),
    );
    try std.testing.expectEqualSlices(u8, &.{ 0xaa, 0xaa, 0xaa, 0xaa }, &pixels);
    try std.testing.expectEqual(
        canvas.Color{ .r = 9, .g = 9, .b = 9, .a = 9 },
        commands[0].solid.color,
    );
    try std.testing.expectEqual(
        @as(canvas.ProducerRevision, @fromBackingInt(@intCast(1))),
        slot.revision,
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 1, 2, 3, 4 },
        slot.uploads[0].pixels.bytes,
    );

    var composer = try canvas.Composer.init(std.testing.allocator, .{
        .sources = 1,
        .retained_resources = 1,
        .retained_commands = 1,
        .retained_pixel_bytes = 4,
        .composition_sources = 1,
        .candidate_resources = 1,
        .candidate_commands = 1,
        .candidate_pixel_bytes = 4,
    });
    defer composer.deinit();
    const source = try composer.registerSource();
    try std.testing.expectError(
        error.InvalidSource,
        slot.drain(&composer, @fromBackingInt(@intCast(99))),
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 1, 2, 3, 4 },
        slot.uploads[0].pixels.bytes,
    );
    try std.testing.expect(try slot.drain(&composer, source));
    try std.testing.expect(!(try slot.drain(&composer, source)));
    try std.testing.expectEqual(
        @as(?State, null),
        slot.claim(.free, .writing),
    );
    slot.copyTaken(.{
        .revision = @fromBackingInt(@intCast(2)),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{},
    });
    slot.storeState(.ready, .release);
    try std.testing.expect(try slot.retire());
}

test "allocation failure and retirement preserve ownership" {
    var failing = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{ .fail_index = 2 },
    );
    try std.testing.expectError(
        error.OutOfMemory,
        PendingSlot.init(failing.allocator(), testLimits(1, 1, 1)),
    );

    var slot = try PendingSlot.init(std.testing.allocator, testLimits(1, 1, 1));
    defer slot.deinit();
    try std.testing.expectEqual(
        @as(?State, null),
        slot.claim(.free, .writing),
    );
    try std.testing.expectError(error.Busy, slot.retire());
    slot.copyTaken(.{
        .revision = @fromBackingInt(@intCast(1)),
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{},
    });
    slot.storeState(.ready, .release);
    try std.testing.expectEqual(
        @as(?State, null),
        slot.claim(.ready, .draining),
    );
    try std.testing.expectError(error.Busy, slot.retire());
    slot.storeState(.ready, .release);
    try std.testing.expect(try slot.retire());
    try std.testing.expectError(error.Retired, slot.publish(
        undefined,
        undefined,
    ));
}

test "terminal receipt slot has exact bounded allocation" {
    var slot = try PendingSlot.init(
        std.testing.allocator,
        testLimits(32, 64, 8192),
    );
    defer slot.deinit();
    try std.testing.expectEqual(
        @as(usize, 15104),
        try requiredBytes(testLimits(32, 64, 8192)),
    );
    try std.testing.expectEqual(@as(usize, 120), @sizeOf(PendingSlot));
    try std.testing.expectEqual(
        @as(usize, 974336),
        (try requiredBytes(testLimits(32, 64, 8192)) +
            @sizeOf(PendingSlot)) * 64,
    );
}

test "release acquire transfers immutable bytes between threads" {
    var slot = try PendingSlot.init(std.testing.allocator, testLimits(1, 1, 4));
    defer slot.deinit();
    var context = ThreadProof{ .slot = &slot };
    const producer = try std.Thread.spawn(.{}, ThreadProof.publish, .{&context});
    defer producer.join();

    var rounds: usize = 0;
    while (slot.claim(.ready, .draining) != null) : (rounds += 1) {
        if (rounds == 1_000_000) return error.TestExpectedEqual;
        std.atomic.spinLoopHint();
    }
    try std.testing.expectEqualSlices(
        u8,
        &.{ 1, 2, 3, 4 },
        slot.uploads[0].pixels.bytes,
    );
    slot.storeState(.free, .release);
}

const ThreadProof = struct {
    slot: *PendingSlot,

    fn publish(self: *ThreadProof) void {
        var pixels = [_]u8{ 1, 2, 3, 4 };
        std.debug.assert(self.slot.claim(.free, .writing) == null);
        self.slot.copyTaken(.{
            .revision = @fromBackingInt(@intCast(1)),
            .uploads = &.{.{
                .resource = .{
                    .resource = @fromBackingInt(@intCast(1)),
                    .generation = @fromBackingInt(@intCast(1)),
                },
                .format = .rgba8,
                .pixels = .{
                    .bytes = &pixels,
                    .width = 1,
                    .height = 1,
                    .stride = 4,
                },
            }},
            .removals = &.{},
            .commands = &.{},
        });
        pixels = @splat(0xaa);
        self.slot.storeState(.ready, .release);
    }
};

fn testLimits(
    resources: usize,
    commands: usize,
    upload_bytes: usize,
) terminal.Content.Limits {
    return .{
        .cells = 1,
        .rows = 1,
        .images = 1,
        .placements = 1,
        .image_bytes = 1,
        .glyphs = 1,
        .masks = 1,
        .commands = commands,
        .resources_per_update = resources,
        .upload_bytes = upload_bytes,
        .raster_bytes = 1,
        .decoration_bytes = 1,
    };
}
