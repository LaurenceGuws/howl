//! Bounded single-producer/single-consumer Render publication exchange.
//!
//! The terminal thread is the sole producer. One backend thread may hold at
//! most one immutable frame lease. Ready-but-unread frames are replaceable, so
//! backend delay never blocks canonical PTY/VT progress.

const std = @import("std");
const terminal = @import("howl_render").terminal;

/// Bounds the backend's accepted current resource set: one glyph atlas plus every visible terminal image.
pub const maximum_residencies: usize = terminal.maximum_external_images + 1;
/// Bounds accepted residency plus one frame's not-yet-accepted external-image uploads.
pub const maximum_prospective_residencies: usize =
    maximum_residencies + terminal.maximum_external_images;
const frame_slot_count: usize = 3;
const residency_slot_count: usize = 2;

const SlotState = enum(u8) {
    free,
    writing,
    ready,
    reading,
};

fn stateValue(value: SlotState) u8 {
    return @backingInt(value);
}

/// Borrows one immutable self-contained Render transaction from a leased publication slot.
pub const PublishedFrame = struct {
    sequence: u64,
    presentation_generation: u64,
    revision: u64,
    terminal_revision: u64,
    history_offset: u32,
    history_count: u32,
    history_row_base: u32,
    alternate_screen: bool,
    surface: terminal.Size,
    cell_size: terminal.Size,
    uploads: []const terminal.FrameResourceUpload,
    removals: []const terminal.ResourceRef,
    commands: []const terminal.Command,
    pixels: []const u8,
};

/// Owns the bounded SPSC frame slots and backend-residency feedback mailbox.
// zig-audit: acknowledge opaque_type
// reason: The exchange hides atomics, owned frame buffers, and slot state so callers can only use the bounded lease/publication protocol.
pub const Exchange = opaque {};

const FrameSlot = struct {
    state: std.atomic.Value(u8) = .init(stateValue(.free)),
    sequence: std.atomic.Value(u64) = .init(0),
    presentation_generation: u64 = 1,
    revision: u64 = 0,
    terminal_revision: u64 = 0,
    history_offset: u32 = 0,
    history_count: u32 = 0,
    history_row_base: u32 = 0,
    alternate_screen: bool = false,
    surface: terminal.Size = .{ .width = 1, .height = 1 },
    cell_size: terminal.Size = .{ .width = 1, .height = 1 },
    uploads: [maximum_residencies]terminal.FrameResourceUpload = undefined,
    removals: [maximum_residencies]terminal.ResourceRef = undefined,
    commands: []terminal.Command,
    pixels: []u8 = &.{},
    upload_count: usize = 0,
    removal_count: usize = 0,
    command_count: usize = 0,
    pixel_count: usize = 0,

    fn init(allocator: std.mem.Allocator, command_capacity: usize) !FrameSlot {
        if (command_capacity == 0) return error.InvalidCapacity;
        return .{
            .commands = try allocator.alloc(terminal.Command, command_capacity),
        };
    }

    fn deinit(self: *FrameSlot, allocator: std.mem.Allocator) void {
        allocator.free(self.commands);
        if (self.pixels.len != 0) allocator.free(self.pixels);
        self.* = undefined;
    }

    fn ensurePixels(self: *FrameSlot, allocator: std.mem.Allocator, needed: usize) !void {
        if (self.pixels.len >= needed) return;
        const replacement = try allocator.alloc(u8, needed);
        if (self.pixels.len != 0) allocator.free(self.pixels);
        self.pixels = replacement;
    }

    fn frame(self: *const FrameSlot) PublishedFrame {
        return .{
            .sequence = self.sequence.load(.acquire),
            .presentation_generation = self.presentation_generation,
            .revision = self.revision,
            .terminal_revision = self.terminal_revision,
            .history_offset = self.history_offset,
            .history_count = self.history_count,
            .history_row_base = self.history_row_base,
            .alternate_screen = self.alternate_screen,
            .surface = self.surface,
            .cell_size = self.cell_size,
            .uploads = self.uploads[0..self.upload_count],
            .removals = self.removals[0..self.removal_count],
            .commands = self.commands[0..self.command_count],
            .pixels = self.pixels[0..self.pixel_count],
        };
    }
};

const ResidencySlot = struct {
    state: std.atomic.Value(u8) = .init(stateValue(.free)),
    sequence: std.atomic.Value(u64) = .init(0),
    presentation_generation: u64 = 0,
    values: [maximum_residencies]terminal.Residency = undefined,
    count: usize = 0,
};

const Impl = struct {
    allocator: std.mem.Allocator,
    frames: [frame_slot_count]FrameSlot,
    reader_active: std.atomic.Value(bool) = .init(false),
    producer_sequence: u64 = 0,
    residency: [residency_slot_count]ResidencySlot = .{ .{}, .{} },
    residency_sequence: u64 = 0,
};

/// Reports exchange allocation or invalid zero command capacity.
pub const InitError = std.mem.Allocator.Error || error{InvalidCapacity};

/// Allocates a three-slot SPSC exchange with fixed command capacity per publication.
pub fn init(
    allocator: std.mem.Allocator,
    command_capacity: usize,
) InitError!*Exchange {
    const impl = try allocator.create(Impl);
    errdefer allocator.destroy(impl);

    var initialized: usize = 0;
    errdefer {
        for (impl.frames[0..initialized]) |*slot| slot.deinit(allocator);
    }
    while (initialized < frame_slot_count) : (initialized += 1)
        impl.frames[initialized] = try FrameSlot.init(allocator, command_capacity);

    impl.allocator = allocator;
    impl.reader_active = .init(false);
    impl.producer_sequence = 0;
    impl.residency = .{ .{}, .{} };
    impl.residency_sequence = 0;

    // zig-audit: acknowledge ptr_cast
    // reason: This boundary owns the concrete Impl allocation and adapts it to the stable opaque Exchange handle without changing address or lifetime.
    return @ptrCast(impl);
}

/// Releases all publication storage after the backend has released every outstanding lease.
pub fn deinit(exchange: *Exchange) void {
    const impl = exchangeImpl(exchange);
    std.debug.assert(!impl.reader_active.load(.acquire));
    for (&impl.frames) |*slot| {
        std.debug.assert(slot.state.load(.acquire) != stateValue(.reading));
        slot.deinit(impl.allocator);
    }
    const allocator = impl.allocator;
    impl.* = undefined;
    allocator.destroy(impl);
}

/// Owns one terminal-thread-only frame slot while a publication is being assembled.
pub const Writer = struct {
    exchange: *Exchange,
    index: usize,
    finished: bool = false,

    fn slot(self: *Writer) *FrameSlot {
        return &exchangeImpl(self.exchange).frames[self.index];
    }

    /// Borrows the fixed upload descriptor storage for this unpublished slot.
    pub fn uploadStorage(self: *Writer) []terminal.FrameResourceUpload {
        return &self.slot().uploads;
    }

    /// Borrows the fixed resource-removal storage for this unpublished slot.
    pub fn removalStorage(self: *Writer) []terminal.ResourceRef {
        return &self.slot().removals;
    }

    /// Borrows the fixed backend-command storage for this unpublished slot.
    pub fn commandStorage(self: *Writer) []terminal.Command {
        return self.slot().commands;
    }

    /// Ensures and borrows owned pixel storage that will remain stable for the eventual lease.
    pub fn pixelStorage(self: *Writer, needed: usize) std.mem.Allocator.Error![]u8 {
        const impl = exchangeImpl(self.exchange);
        const value = self.slot();
        try value.ensurePixels(impl.allocator, needed);
        return value.pixels;
    }

    /// Atomically publishes the completed slot and retires older unread candidates.
    pub fn finish(
        self: *Writer,
        presentation_generation: u64,
        revision: u64,
        terminal_revision: u64,
        history_offset: u32,
        history_count: u32,
        history_row_base: u32,
        alternate_screen: bool,
        surface: terminal.Size,
        cell_size: terminal.Size,
        upload_count: usize,
        removal_count: usize,
        command_count: usize,
        pixel_count: usize,
    ) void {
        const impl = exchangeImpl(self.exchange);
        const value = self.slot();
        std.debug.assert(!self.finished);
        std.debug.assert(presentation_generation != 0);
        std.debug.assert(terminal_revision != 0);
        std.debug.assert(history_offset <= history_count or alternate_screen);
        std.debug.assert(upload_count <= value.uploads.len);
        std.debug.assert(removal_count <= value.removals.len);
        std.debug.assert(command_count <= value.commands.len);
        std.debug.assert(pixel_count <= value.pixels.len);
        std.debug.assert(surface.width != 0 and surface.height != 0);
        std.debug.assert(cell_size.width != 0 and cell_size.height != 0);

        impl.producer_sequence +%= 1;
        if (impl.producer_sequence == 0) impl.producer_sequence = 1;
        value.presentation_generation = presentation_generation;
        value.revision = revision;
        value.terminal_revision = terminal_revision;
        value.history_offset = history_offset;
        value.history_count = history_count;
        value.history_row_base = history_row_base;
        value.alternate_screen = alternate_screen;
        value.surface = surface;
        value.cell_size = cell_size;
        value.upload_count = upload_count;
        value.removal_count = removal_count;
        value.command_count = command_count;
        value.pixel_count = pixel_count;
        value.sequence.store(impl.producer_sequence, .monotonic);
        value.state.store(stateValue(.ready), .release);
        self.finished = true;

        // A ready frame is only a latest-state candidate, never history. Retire
        // older unread candidates after publishing the new one.
        for (&impl.frames, 0..) |*other, index| {
            if (index == self.index) continue;
            retireReady(&other.state);
        }
    }

    /// Returns an unpublished writer slot to the free pool.
    pub fn abort(self: *Writer) void {
        if (self.finished) return;
        self.slot().state.store(stateValue(.free), .release);
        self.finished = true;
    }
};

/// Claims a free slot or replaces the oldest unread slot without waiting for the backend.
pub fn beginWrite(exchange: *Exchange) ?Writer {
    const impl = exchangeImpl(exchange);

    // Prefer unused storage.
    for (&impl.frames, 0..) |*slot, index| {
        if (slot.state.cmpxchgStrong(
            stateValue(.free),
            stateValue(.writing),
            .acq_rel,
            .acquire,
        ) == null)
            return .{ .exchange = exchange, .index = index };
    }

    // Coalesce by replacing an unread frame. A reading slot is immutable and
    // therefore never eligible.
    var chosen: ?usize = null;
    var chosen_sequence: u64 = std.math.maxInt(u64);
    for (&impl.frames, 0..) |*slot, index| {
        if (slot.state.load(.acquire) != stateValue(.ready)) continue;
        const sequence = slot.sequence.load(.monotonic);
        if (sequence < chosen_sequence) {
            chosen = index;
            chosen_sequence = sequence;
        }
    }
    const index = chosen orelse return null;
    const slot = &impl.frames[index];
    if (slot.state.cmpxchgStrong(
        stateValue(.ready),
        stateValue(.writing),
        .acq_rel,
        .acquire,
    ) != null)
        return beginWrite(exchange);
    return .{ .exchange = exchange, .index = index };
}

/// Holds one immutable backend-thread publication until exact residency feedback is returned.
pub const Lease = struct {
    exchange: *Exchange,
    index: usize,
    value: PublishedFrame,
    released: bool = false,

    /// Releases this immutable frame and publishes the backend's exact current
    /// Render residency as the only feedback to the terminal producer.
    /// Reports malformed/oversized residency feedback or a violated single-consumer mailbox contract.
    pub const ReleaseError = terminal.Error || error{
        ResidencyLimit,
        ResidencyMailboxBusy,
    };

    /// Releases this lease and publishes only exact backend Render residency to the terminal thread.
    pub fn release(
        self: *Lease,
        residency: []const terminal.Residency,
    ) ReleaseError!void {
        if (self.released) return;
        const impl = exchangeImpl(self.exchange);
        defer {
            impl.frames[self.index].state.store(stateValue(.free), .release);
            impl.reader_active.store(false, .release);
            self.released = true;
        }
        if (residency.len > maximum_residencies) return error.ResidencyLimit;
        try terminal.validateResidencies(residency);
        if (!reportResidency(
            impl,
            self.value.presentation_generation,
            residency,
        )) return error.ResidencyMailboxBusy;
    }

    /// Releases a failed backend candidate without publishing residency feedback.
    ///
    /// This is only for adapter failure before a candidate could establish any
    /// new accepted backend state.
    pub fn abandon(self: *Lease) void {
        if (self.released) return;
        const impl = exchangeImpl(self.exchange);
        impl.frames[self.index].state.store(stateValue(.free), .release);
        impl.reader_active.store(false, .release);
        self.released = true;
    }
};

/// Claims the newest unread publication for the single backend consumer.
pub fn acquireLatest(exchange: *Exchange) ?Lease {
    const impl = exchangeImpl(exchange);
    if (impl.reader_active.cmpxchgStrong(false, true, .acq_rel, .acquire) != null)
        return null;

    while (true) {
        var chosen: ?usize = null;
        var chosen_sequence: u64 = 0;
        for (&impl.frames, 0..) |*slot, index| {
            if (slot.state.load(.acquire) != stateValue(.ready)) continue;
            const sequence = slot.sequence.load(.monotonic);
            if (chosen == null or sequence > chosen_sequence) {
                chosen = index;
                chosen_sequence = sequence;
            }
        }
        const index = chosen orelse {
            impl.reader_active.store(false, .release);
            return null;
        };
        const slot = &impl.frames[index];
        if (slot.state.cmpxchgStrong(
            stateValue(.ready),
            stateValue(.reading),
            .acq_rel,
            .acquire,
        ) != null)
            continue;

        // No producer may mutate a reading slot. The acquire transition pairs
        // with Writer.finish's release publication of all payload metadata.
        return .{
            .exchange = exchange,
            .index = index,
            .value = slot.frame(),
        };
    }
}

/// Copies the newest backend residency report into terminal-thread-owned storage.
/// Older unread reports are discarded. Null means the previous accepted
/// residency remains current.
pub fn takeLatestResidency(
    exchange: *Exchange,
    presentation_generation: u64,
    output: *[maximum_residencies]terminal.Residency,
) ?[]const terminal.Residency {
    const impl = exchangeImpl(exchange);
    while (true) {
        var chosen: ?usize = null;
        var chosen_sequence: u64 = 0;
        for (&impl.residency, 0..) |*slot, index| {
            if (slot.state.load(.acquire) != stateValue(.ready)) continue;
            const sequence = slot.sequence.load(.monotonic);
            if (chosen == null or sequence > chosen_sequence) {
                chosen = index;
                chosen_sequence = sequence;
            }
        }
        const index = chosen orelse return null;
        const slot = &impl.residency[index];
        if (slot.state.cmpxchgStrong(
            stateValue(.ready),
            stateValue(.reading),
            .acq_rel,
            .acquire,
        ) != null)
            continue;

        const matches = slot.presentation_generation == presentation_generation;
        if (matches)
            @memcpy(output[0..slot.count], slot.values[0..slot.count]);
        const count = if (matches) slot.count else 0;
        slot.state.store(stateValue(.free), .release);

        for (&impl.residency, 0..) |*other, other_index| {
            if (other_index == index) continue;
            retireReady(&other.state);
        }
        return if (matches) output[0..count] else null;
    }
}

fn retireReady(state: *std.atomic.Value(u8)) void {
    const previous = state.cmpxchgStrong(
        stateValue(.ready),
        stateValue(.free),
        .acq_rel,
        .acquire,
    );
    if (previous == null) return;
}

fn reportResidency(
    impl: *Impl,
    presentation_generation: u64,
    residency: []const terminal.Residency,
) bool {
    std.debug.assert(residency.len <= maximum_residencies);
    var index: ?usize = null;
    for (&impl.residency, 0..) |*slot, candidate| {
        if (slot.state.cmpxchgStrong(
            stateValue(.free),
            stateValue(.writing),
            .acq_rel,
            .acquire,
        ) == null) {
            index = candidate;
            break;
        }
    }
    if (index == null) {
        for (&impl.residency, 0..) |*slot, candidate| {
            if (slot.state.cmpxchgStrong(
                stateValue(.ready),
                stateValue(.writing),
                .acq_rel,
                .acquire,
            ) == null) {
                index = candidate;
                break;
            }
        }
    }
    const selected = index orelse return false;
    const slot = &impl.residency[selected];
    slot.presentation_generation = presentation_generation;
    @memcpy(slot.values[0..residency.len], residency);
    slot.count = residency.len;
    impl.residency_sequence +%= 1;
    if (impl.residency_sequence == 0) impl.residency_sequence = 1;
    slot.sequence.store(impl.residency_sequence, .monotonic);
    slot.state.store(stateValue(.ready), .release);
    return true;
}

fn exchangeImpl(exchange: *Exchange) *Impl {
    // zig-audit: acknowledge ptr_cast
    // reason: Exchange is created only from an allocator-owned Impl at init and preserves that exact address and lifetime.
    // zig-audit: acknowledge align_cast
    // reason: The originating Impl allocation guarantees the alignment asserted when recovering the concrete owner.
    return @ptrCast(@alignCast(exchange));
}

test "ready publications coalesce while a held lease remains immutable" {
    const exchange = try init(std.testing.allocator, 4);
    defer deinit(exchange);

    var first = beginWrite(exchange).?;
    first.commandStorage()[0] = .{ .solid = .{
        .rect = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .color = .{ .r = 1, .g = 2, .b = 3, .a = 255 },
    } };
    first.finish(1, 1, 1, 0, 0, 0, false, .{ .width = 1, .height = 1 }, .{ .width = 1, .height = 1 }, 0, 0, 1, 0);

    var lease = acquireLatest(exchange).?;
    try std.testing.expectEqual(@as(u64, 1), lease.value.revision);

    var second = beginWrite(exchange).?;
    second.commandStorage()[0] = .{ .solid = .{
        .rect = .{ .x = 0, .y = 0, .width = 2, .height = 1 },
        .color = .{ .r = 4, .g = 5, .b = 6, .a = 255 },
    } };
    second.finish(1, 2, 2, 0, 0, 0, false, .{ .width = 2, .height = 1 }, .{ .width = 1, .height = 1 }, 0, 0, 1, 0);

    var third = beginWrite(exchange).?;
    third.commandStorage()[0] = .{ .solid = .{
        .rect = .{ .x = 0, .y = 0, .width = 3, .height = 1 },
        .color = .{ .r = 7, .g = 8, .b = 9, .a = 255 },
    } };
    third.finish(1, 3, 3, 0, 0, 0, false, .{ .width = 3, .height = 1 }, .{ .width = 1, .height = 1 }, 0, 0, 1, 0);

    // Held payload cannot be overwritten by producer coalescing.
    try std.testing.expectEqual(@as(u16, 1), lease.value.commands[0].solid.rect.width);
    try lease.release(&.{});

    var latest = acquireLatest(exchange).?;
    try std.testing.expectEqual(@as(u64, 3), latest.value.revision);
    try std.testing.expectEqual(@as(u16, 3), latest.value.commands[0].solid.rect.width);
    try latest.release(&.{});
}

test "lease feedback publishes only newest exact residency" {
    const exchange = try init(std.testing.allocator, 1);
    defer deinit(exchange);

    var writer = beginWrite(exchange).?;
    writer.finish(1, 1, 1, 0, 0, 0, false, .{ .width = 1, .height = 1 }, .{ .width = 1, .height = 1 }, 0, 0, 0, 0);
    var lease = acquireLatest(exchange).?;

    const resource = try terminal.ResourceId.init(9);
    const accepted = terminal.Residency{
        .resource = .{ .resource = resource, .generation = @fromBackingInt(@intCast(4)) },
        .format = .rgba8,
        .size = .{ .width = 2, .height = 3 },
    };
    try lease.release(&.{accepted});

    var storage: [maximum_residencies]terminal.Residency = undefined;
    const feedback = takeLatestResidency(exchange, 1, &storage).?;
    try std.testing.expectEqual(@as(usize, 1), feedback.len);
    try std.testing.expectEqualDeep(accepted, feedback[0]);
}

const ConcurrentHold = struct {
    exchange: *Exchange,
    acquired: std.atomic.Value(bool) = .init(false),
    release_now: std.atomic.Value(bool) = .init(false),
    failed: std.atomic.Value(bool) = .init(false),

    fn run(self: *ConcurrentHold) void {
        var lease = acquireLatest(self.exchange) orelse {
            self.failed.store(true, .release);
            return;
        };
        const width = switch (lease.value.commands[0]) {
            .solid => |solid| solid.rect.width,
            else => {
                self.failed.store(true, .release);
                lease.release(&.{}) catch {
                    self.failed.store(true, .release);
                };
                return;
            },
        };
        self.acquired.store(true, .release);
        while (!self.release_now.load(.acquire))
            std.atomic.spinLoopHint();
        const retained = switch (lease.value.commands[0]) {
            .solid => |solid| solid.rect.width,
            else => 0,
        };
        if (retained != width)
            self.failed.store(true, .release);
        lease.release(&.{}) catch {
            self.failed.store(true, .release);
        };
    }
};

test "backend lease remains immutable while producer coalesces a burst" {
    const exchange = try init(std.testing.allocator, 1);
    defer deinit(exchange);

    var initial = beginWrite(exchange).?;
    initial.commandStorage()[0] = .{ .solid = .{
        .rect = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .color = .{ .r = 1, .g = 2, .b = 3, .a = 255 },
    } };
    initial.finish(
        1,
        1,
        1,
        0,
        0,
        0,
        false,
        .{ .width = 1, .height = 1 },
        .{ .width = 1, .height = 1 },
        0,
        0,
        1,
        0,
    );

    var hold = ConcurrentHold{ .exchange = exchange };
    const backend = try std.Thread.spawn(.{}, ConcurrentHold.run, .{&hold});
    while (!hold.acquired.load(.acquire))
        std.atomic.spinLoopHint();

    var revision: u64 = 2;
    while (revision <= 101) : (revision += 1) {
        var writer = beginWrite(exchange) orelse return error.PublicationBusy;
        const width: u16 = @intCast((revision % 100) + 1);
        writer.commandStorage()[0] = .{ .solid = .{
            .rect = .{ .x = 0, .y = 0, .width = width, .height = 1 },
            .color = .{ .r = 4, .g = 5, .b = 6, .a = 255 },
        } };
        writer.finish(
            1,
            revision,
            revision,
            0,
            0,
            0,
            false,
            .{ .width = width, .height = 1 },
            .{ .width = 1, .height = 1 },
            0,
            0,
            1,
            0,
        );
    }

    hold.release_now.store(true, .release);
    backend.join();
    try std.testing.expect(!hold.failed.load(.acquire));

    var latest = acquireLatest(exchange).?;
    try std.testing.expectEqual(@as(u64, 101), latest.value.revision);
    try latest.release(&.{});
}
