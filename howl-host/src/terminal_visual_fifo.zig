//! Owns the bounded ordered handoff of VT visual transactions to Renderer.
//!
//! Terminal producers deep-copy complete journal transactions in one global
//! reservation order. Renderer borrows only the oldest ready transaction and
//! explicitly completes it. This module owns no terminal lifecycle, retained
//! pane grid, rendering, GPU, frame, or Window publication state.

const std = @import("std");
const handoff = @import("terminal_handoff");
const vt = @import("howl_vt");

const journal = vt.render_journal;
const linux = std.os.linux;
const eventfd_flags = linux.EFD.CLOEXEC | linux.EFD.NONBLOCK;

/// Bounds global ordered visual transactions retained between terminal owners and Renderer.
pub const queue_capacity: usize = 256;
/// Bounds all dynamically allocated operation and payload bytes retained by the queue.
pub const dynamic_payload_limit: usize = 64 * journal.maximum_cells * @sizeOf(journal.Cell);

/// Identifies the exact terminal owner of one visual transaction.
pub const Identity = struct {
    pane: handoff.PaneId,
    source: handoff.SourceId,
    lifecycle_revision: handoff.LifecycleRevision,
};

/// Identifies one committed transaction without exposing reusable slot storage.
pub const CompletionHandle = struct {
    slot: u16,
    generation: u64,
    sequence: u64,
};

/// Borrows one stable head transaction until `Fifo.complete` succeeds.
pub const Borrowed = struct {
    identity: Identity,
    sequence: u64,
    transaction: journal.Transaction,
    handle: CompletionHandle,
};

/// Reports queue pressure, invalid input, or allocation failure before commit.
pub const EnqueueError = error{ Pressure, InvalidIdentity, InvalidTransaction, OutOfMemory };
/// Reports a stale completion token or a token for a transaction not being drained.
pub const CompleteError = error{InvalidCompletion};
/// Reports native readiness-drain failure.
pub const DrainError = error{Signal};

const SlotState = enum(u8) { empty, writing, ready, draining, cancelled };

const Slot = struct {
    state: SlotState = .empty,
    generation: u64 = 0,
    sequence: u64 = 0,
    identity: Identity = undefined,
    inline_operations: [journal.inline_operation_capacity]journal.Operation = undefined,
    inline_cells: [journal.inline_cell_capacity]journal.Cell = undefined,
    operations: []journal.Operation = &.{},
    operation_count: usize = 0,
    cell_count: usize = 0,
    dynamic_operations: ?[]journal.Operation = null,
    dynamic_payload: ?[]u8 = null,
    dynamic_bytes: usize = 0,

    fn transaction(self: *const Slot) journal.Transaction {
        return .{ .operations = self.operations[0..self.operation_count] };
    }
};

const PayloadMeasure = struct {
    cells: usize = 0,
    auxiliary_bytes: usize = 0,
};

const WakePair = struct { ready: i32, capacity: i32 };

/// Retains one bounded global FIFO and two directional nonblocking readiness descriptors.
pub const Fifo = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    mutex: std.Io.Mutex = .init,
    slots: [queue_capacity]Slot = @splat(.{}),
    head: u16 = 0,
    count: u16 = 0,
    next_generation: u64 = 1,
    next_sequence: u64 = 1,
    dynamic_bytes: usize = 0,
    ready_fd: i32,
    capacity_fd: i32,

    /// Creates independent ready and capacity eventfds without allocating queue storage.
    pub fn init(io: std.Io, allocator: std.mem.Allocator) error{Signal}!Fifo {
        const pair = try createWakePair();
        return .{
            .io = io,
            .allocator = allocator,
            .ready_fd = pair.ready,
            .capacity_fd = pair.capacity,
        };
    }

    /// Releases every dynamic slot owner in reverse slot order and closes capacity then ready.
    pub fn deinit(self: *Fifo) void {
        var index: usize = queue_capacity;
        while (index != 0) {
            index -= 1;
            self.releaseDynamic(&self.slots[index]);
        }
        closeDescriptor(self.capacity_fd);
        closeDescriptor(self.ready_fd);
        self.* = undefined;
    }

    /// Returns the descriptor readable when queue progress may expose a head transaction.
    pub fn readyDescriptor(self: *const Fifo) i32 {
        return self.ready_fd;
    }

    /// Returns the descriptor readable after slot or dynamic-budget capacity is released.
    pub fn capacityDescriptor(self: *const Fifo) i32 {
        return self.capacity_fd;
    }

    /// Deep-copies one complete transaction or leaves the caller-owned transaction unchanged.
    pub fn enqueue(self: *Fifo, owner: Identity, transaction: journal.Transaction) EnqueueError!u64 {
        if (!validIdentity(owner)) return error.InvalidIdentity;
        const measure = measureTransaction(transaction) catch return error.InvalidTransaction;
        const operation_bytes = if (transaction.operations.len > journal.inline_operation_capacity)
            std.math.mul(usize, transaction.operations.len, @sizeOf(journal.Operation)) catch return error.InvalidTransaction
        else
            0;
        const dynamic_cell_bytes = if (measure.cells > journal.inline_cell_capacity)
            std.math.mul(usize, measure.cells, @sizeOf(journal.Cell)) catch return error.InvalidTransaction
        else
            0;
        const payload_bytes = std.math.add(usize, dynamic_cell_bytes, measure.auxiliary_bytes) catch return error.InvalidTransaction;
        const dynamic_bytes = std.math.add(usize, operation_bytes, payload_bytes) catch return error.InvalidTransaction;
        if (dynamic_bytes > dynamic_payload_limit) return error.Pressure;

        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.count == queue_capacity or dynamic_bytes > dynamic_payload_limit - self.dynamic_bytes)
            return error.Pressure;

        const index = (@as(usize, self.head) + self.count) % queue_capacity;
        var slot = &self.slots[index];
        std.debug.assert(slot.state == .empty);
        const generation = self.nextGeneration() catch return error.Pressure;
        slot.* = .{
            .state = .writing,
            .generation = generation,
            .identity = owner,
            .dynamic_bytes = dynamic_bytes,
        };
        self.count += 1;
        self.dynamic_bytes += dynamic_bytes;

        self.copyTransaction(slot, transaction, measure, operation_bytes, payload_bytes) catch |failure| {
            self.releaseDynamic(slot);
            self.dynamic_bytes -= dynamic_bytes;
            slot.state = .cancelled;
            signal(self.ready_fd);
            signal(self.capacity_fd);
            return failure;
        };

        const sequence = self.nextSequence() catch {
            self.releaseDynamic(slot);
            self.dynamic_bytes -= dynamic_bytes;
            slot.state = .cancelled;
            signal(self.ready_fd);
            signal(self.capacity_fd);
            return error.Pressure;
        };
        slot.sequence = sequence;
        slot.state = .ready;
        signal(self.ready_fd);
        return sequence;
    }

    /// Skips cancelled head reservations and borrows exactly one oldest ready transaction.
    pub fn take(self: *Fifo) ?Borrowed {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        while (self.count != 0) {
            const index = self.head;
            var slot = &self.slots[index];
            switch (slot.state) {
                .cancelled => {
                    slot.* = .{};
                    self.head = @intCast((@as(usize, self.head) + 1) % queue_capacity);
                    self.count -= 1;
                    signal(self.capacity_fd);
                },
                .writing => return null,
                .ready => {
                    slot.state = .draining;
                    return .{
                        .identity = slot.identity,
                        .sequence = slot.sequence,
                        .transaction = slot.transaction(),
                        .handle = .{ .slot = index, .generation = slot.generation, .sequence = slot.sequence },
                    };
                },
                .draining => return null,
                .empty => unreachable,
            }
        }
        return null;
    }

    /// Releases exactly the currently borrowed head transaction and wakes pressured producers.
    pub fn complete(self: *Fifo, handle: CompletionHandle) CompleteError!void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.count == 0 or handle.slot != self.head) return error.InvalidCompletion;
        const slot = &self.slots[self.head];
        if (slot.state != .draining or slot.generation != handle.generation or slot.sequence != handle.sequence)
            return error.InvalidCompletion;
        self.dynamic_bytes -= slot.dynamic_bytes;
        self.releaseDynamic(slot);
        slot.* = .{};
        self.head = @intCast((@as(usize, self.head) + 1) % queue_capacity);
        self.count -= 1;
        signal(self.capacity_fd);
        if (self.count != 0) signal(self.ready_fd);
    }

    /// Drains coalesced ready edges; callers must then recheck `take` before blocking.
    pub fn drainReadyWake(self: *Fifo) DrainError!void {
        return drain(self.ready_fd);
    }

    /// Drains coalesced capacity edges; producers must then retry `enqueue` before blocking.
    pub fn drainCapacityWake(self: *Fifo) DrainError!void {
        return drain(self.capacity_fd);
    }

    /// Reports retained dynamic ownership for exact pressure and teardown proofs.
    pub fn retainedDynamicBytes(self: *Fifo) usize {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.dynamic_bytes;
    }

    fn copyTransaction(
        self: *Fifo,
        slot: *Slot,
        transaction: journal.Transaction,
        measure: PayloadMeasure,
        operation_bytes: usize,
        payload_bytes: usize,
    ) error{OutOfMemory}!void {
        if (operation_bytes != 0)
            slot.dynamic_operations = self.allocator.alloc(journal.Operation, transaction.operations.len) catch return error.OutOfMemory;
        errdefer self.releaseDynamic(slot);
        if (payload_bytes != 0)
            slot.dynamic_payload = self.allocator.alloc(u8, payload_bytes) catch return error.OutOfMemory;
        slot.operations = slot.dynamic_operations orelse slot.inline_operations[0..transaction.operations.len];
        slot.operation_count = transaction.operations.len;
        slot.cell_count = measure.cells;

        var cell_offset: usize = 0;
        var byte_offset: usize = if (measure.cells > journal.inline_cell_capacity)
            measure.cells * @sizeOf(journal.Cell)
        else
            0;
        for (transaction.operations, 0..) |operation, index| {
            slot.operations[index] = copyOperation(slot, operation, &cell_offset, &byte_offset);
        }
        std.debug.assert(cell_offset == measure.cells);
        std.debug.assert(byte_offset == payload_bytes);
    }

    fn releaseDynamic(self: *Fifo, slot: *Slot) void {
        if (slot.dynamic_payload) |payload| self.allocator.free(payload);
        if (slot.dynamic_operations) |operations| self.allocator.free(operations);
        slot.dynamic_payload = null;
        slot.dynamic_operations = null;
        slot.operations = &.{};
        slot.operation_count = 0;
        slot.cell_count = 0;
    }

    fn nextGeneration(self: *Fifo) error{Pressure}!u64 {
        if (self.next_generation == std.math.maxInt(u64)) return error.Pressure;
        const value = self.next_generation;
        self.next_generation += 1;
        return value;
    }

    fn nextSequence(self: *Fifo) error{Pressure}!u64 {
        if (self.next_sequence == std.math.maxInt(u64)) return error.Pressure;
        const value = self.next_sequence;
        self.next_sequence += 1;
        return value;
    }
};

fn validIdentity(owner: Identity) bool {
    return @backingInt(owner.pane) != 0 and
        @backingInt(owner.source) != 0 and
        @backingInt(owner.lifecycle_revision) != 0;
}

fn measureTransaction(transaction: journal.Transaction) error{InvalidTransaction}!PayloadMeasure {
    if (transaction.operations.len == 0) return error.InvalidTransaction;
    var result: PayloadMeasure = .{};
    for (transaction.operations) |operation| switch (operation) {
        .set_cells => |set| result.cells = try addBounded(result.cells, set.cells.len, journal.maximum_cells),
        .fill, .copy, .cursor => {},
        .masked_fill => |fill| result.auxiliary_bytes = try addBounded(result.auxiliary_bytes, fill.mask.len, dynamic_payload_limit),
        .recolor => |recolor| {
            result.auxiliary_bytes = try addBounded(result.auxiliary_bytes, recolor.foreground.len, dynamic_payload_limit);
            result.auxiliary_bytes = try addBounded(result.auxiliary_bytes, recolor.background.len, dynamic_payload_limit);
            result.auxiliary_bytes = try addBounded(result.auxiliary_bytes, recolor.underline.len, dynamic_payload_limit);
            result.auxiliary_bytes = try addBounded(result.auxiliary_bytes, @sizeOf([256]journal.Rgb), dynamic_payload_limit);
        },
        .visual_patch => |patch| if (patch.changed_mask) |mask| {
            result.auxiliary_bytes = try addBounded(result.auxiliary_bytes, mask.len, dynamic_payload_limit);
        },
        .replace => |replace| result.cells = try addBounded(result.cells, replace.cells.len, journal.maximum_cells),
    };
    return result;
}

fn addBounded(current: usize, amount: usize, maximum: usize) error{InvalidTransaction}!usize {
    const result = std.math.add(usize, current, amount) catch return error.InvalidTransaction;
    if (result > maximum) return error.InvalidTransaction;
    return result;
}

fn copyOperation(slot: *Slot, operation: journal.Operation, cell_offset: *usize, byte_offset: *usize) journal.Operation {
    return switch (operation) {
        .set_cells => |set| .{ .set_cells = .{
            .row = set.row,
            .col = set.col,
            .cells = copyCells(slot, set.cells, cell_offset),
        } },
        .fill => |fill| .{ .fill = fill },
        .copy => |copy| .{ .copy = copy },
        .masked_fill => |fill| .{ .masked_fill = .{
            .rect = fill.rect,
            .mask = copyBytes(slot, fill.mask, byte_offset),
            .cell = fill.cell,
        } },
        .recolor => |recolor| .{ .recolor = .{
            .foreground = copyBytes(slot, recolor.foreground, byte_offset),
            .background = copyBytes(slot, recolor.background, byte_offset),
            .underline = copyBytes(slot, recolor.underline, byte_offset),
            .rgb = copyRgbTable(slot, recolor.rgb, byte_offset),
        } },
        .visual_patch => |patch| .{ .visual_patch = .{
            .rect = patch.rect,
            .changed_mask = if (patch.changed_mask) |mask| copyBytes(slot, mask, byte_offset) else null,
            .set_style = patch.set_style,
            .clear_style = patch.clear_style,
            .toggle_style = patch.toggle_style,
            .swap_foreground_background = patch.swap_foreground_background,
            .foreground = patch.foreground,
            .background = patch.background,
            .underline = patch.underline,
        } },
        .replace => |replace| .{ .replace = .{
            .kind = replace.kind,
            .rows = replace.rows,
            .cols = replace.cols,
            .cells = copyCells(slot, replace.cells, cell_offset),
        } },
        .cursor => |cursor| .{ .cursor = cursor },
    };
}

fn copyCells(slot: *Slot, source: []const journal.Cell, offset: *usize) []const journal.Cell {
    const destination = if (slot.cell_count > journal.inline_cell_capacity) blk: {
        const bytes = slot.dynamic_payload.?[0 .. slot.cell_count * @sizeOf(journal.Cell)];
        const cells: []journal.Cell = @ptrCast(bytes);
        break :blk cells[offset.* .. offset.* + source.len];
    } else slot.inline_cells[offset.* .. offset.* + source.len];
    @memcpy(destination, source);
    offset.* += source.len;
    return destination;
}

fn copyBytes(slot: *Slot, source: []const u8, offset: *usize) []const u8 {
    const destination = slot.dynamic_payload.?[offset.* .. offset.* + source.len];
    @memcpy(destination, source);
    offset.* += source.len;
    return destination;
}

fn copyRgbTable(slot: *Slot, source: *const [256]journal.Rgb, offset: *usize) *const [256]journal.Rgb {
    const bytes = slot.dynamic_payload.?[offset.* .. offset.* + @sizeOf([256]journal.Rgb)];
    const destination: *[256]journal.Rgb = @ptrCast(bytes.ptr);
    destination.* = source.*;
    offset.* += @sizeOf([256]journal.Rgb);
    return destination;
}

fn createWakePair() error{Signal}!WakePair {
    const ready = try createEventfd();
    errdefer closeDescriptor(ready);
    return .{ .ready = ready, .capacity = try createEventfd() };
}

fn createEventfd() error{Signal}!i32 {
    const result = linux.eventfd(0, eventfd_flags);
    if (linux.errno(result) != .SUCCESS) return error.Signal;
    return std.math.cast(i32, result) orelse error.Signal;
}

fn closeDescriptor(fd: i32) void {
    if (std.posix.system.close(fd) != 0) @panic("terminal visual FIFO descriptor cleanup failed");
}

fn signal(fd: i32) void {
    const one: u64 = 1;
    const bytes = std.mem.asBytes(&one);
    while (true) {
        const result = std.posix.system.write(fd, bytes.ptr, bytes.len);
        if (result == bytes.len) return;
        if (result < 0 and std.posix.errno(result) == .INTR) continue;
        if (result < 0 and std.posix.errno(result) == .AGAIN) return;
        @panic("terminal visual FIFO wake failed");
    }
}

fn drain(fd: i32) error{Signal}!void {
    var value: u64 = 0;
    while (true) {
        const count = std.posix.read(fd, std.mem.asBytes(&value)) catch |failure| switch (failure) {
            error.WouldBlock => return,
            else => return error.Signal,
        };
        if (count != @sizeOf(u64)) return error.Signal;
    }
}

fn testIdentity(value: u64) Identity {
    return .{
        .pane = @fromBackingInt(@intCast(value)),
        .source = @fromBackingInt(@intCast(value + 100)),
        .lifecycle_revision = @fromBackingInt(@intCast(value + 200)),
    };
}

const CursorSource = struct {
    operations: [1]journal.Operation,

    fn init(code: u16) CursorSource {
        return .{ .operations = .{.{ .cursor = .{ .row = code, .visible = true } }} };
    }

    fn transaction(self: *const CursorSource) journal.Transaction {
        return .{ .operations = &self.operations };
    }
};

fn enqueueForTest(fifo: *Fifo, owner: Identity, transaction: journal.Transaction) EnqueueError!void {
    const sequence = try fifo.enqueue(owner, transaction);
    std.mem.doNotOptimizeAway(sequence);
}

test "two producers preserve one global order and no producer merge" {
    var fifo = try Fifo.init(std.testing.io, std.testing.allocator);
    defer fifo.deinit();
    const five = CursorSource.init(5);
    const four = CursorSource.init(4);
    const five_again = CursorSource.init(5);
    try std.testing.expectEqual(@as(u64, 1), try fifo.enqueue(testIdentity(1), five.transaction()));
    try std.testing.expectEqual(@as(u64, 2), try fifo.enqueue(testIdentity(2), four.transaction()));
    try std.testing.expectEqual(@as(u64, 3), try fifo.enqueue(testIdentity(1), five_again.transaction()));
    for ([_]u16{ 5, 4, 5 }, 1..) |row, sequence| {
        const borrowed = fifo.take().?;
        try std.testing.expectEqual(@as(u64, sequence), borrowed.sequence);
        try std.testing.expectEqual(row, borrowed.transaction.operations[0].cursor.row);
        try fifo.complete(borrowed.handle);
    }
}

test "FIFO and slot layouts remain exact" {
    try std.testing.expectEqual(@as(usize, 645_192), @sizeOf(Fifo));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(Fifo));
    try std.testing.expectEqual(@as(usize, 2_520), @sizeOf(Slot));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(Slot));
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(journal.Operation));
    try std.testing.expectEqual(@as(usize, 46_137_344), dynamic_payload_limit);
}

test "all inline slots fill without allocation and draining blocks reuse" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var fifo = try Fifo.init(std.testing.io, failing.allocator());
    defer fifo.deinit();
    const transaction = CursorSource.init(1);
    for (0..queue_capacity) |index| {
        try enqueueForTest(&fifo, testIdentity(index + 1), transaction.transaction());
    }
    try std.testing.expectError(error.Pressure, fifo.enqueue(testIdentity(300), transaction.transaction()));
    const borrowed = fifo.take().?;
    try std.testing.expectError(error.Pressure, fifo.enqueue(testIdentity(301), transaction.transaction()));
    try fifo.complete(borrowed.handle);
    try enqueueForTest(&fifo, testIdentity(302), transaction.transaction());
}

test "replacement and auxiliary slices are deeply rebased" {
    var fifo = try Fifo.init(std.testing.io, std.testing.allocator);
    defer fifo.deinit();
    var pending: journal.Pending = .{};
    defer pending.deinit();
    var builder = try pending.prepare(std.testing.allocator, .{ .operations = 1, .cells = 40 });
    const cells = builder.cells(40);
    for (cells, 0..) |*cell, index| cell.* = .{
        .codepoint = @intCast('A' + index % 26),
        .foreground = .{ .r = @intCast(index), .g = 2, .b = 3 },
        .background = .{ .r = 4, .g = 5, .b = 6 },
        .underline_color = .{ .r = 7, .g = 8, .b = 9 },
    };
    builder.append(.{ .replace = .{ .kind = .resize, .rows = 5, .cols = 8, .cells = cells } });
    pending.commit();
    try enqueueForTest(&fifo, testIdentity(1), pending.view().?);
    pending.consume();
    const borrowed = fifo.take().?;
    try std.testing.expectEqual(@as(u8, 'N'), borrowed.transaction.operations[0].replace.cells[39].codepoint);
    try fifo.complete(borrowed.handle);
}

test "set fill copy and cursor variants preserve exact values" {
    var fifo = try Fifo.init(std.testing.io, std.testing.allocator);
    defer fifo.deinit();
    var cells = [_]journal.Cell{std.mem.zeroes(journal.Cell)};
    cells[0].codepoint = 'q';
    const rect: journal.Rect = .{ .row = 1, .col = 2, .rows = 3, .cols = 4 };
    var operations = [_]journal.Operation{
        .{ .set_cells = .{ .row = 5, .col = 6, .cells = &cells } },
        .{ .fill = .{ .rect = rect, .cell = cells[0] } },
        .{ .copy = .{ .source = rect, .destination_row = 7, .destination_col = 8 } },
        .{ .cursor = .{ .row = 9, .col = 10, .shape = .bar, .visible = true } },
    };
    try enqueueForTest(&fifo, testIdentity(1), .{ .operations = &operations });
    cells[0].codepoint = 'x';
    const borrowed = fifo.take().?;
    try std.testing.expectEqual(@as(u8, 'q'), borrowed.transaction.operations[0].set_cells.cells[0].codepoint);
    try std.testing.expectEqual(rect, borrowed.transaction.operations[1].fill.rect);
    try std.testing.expectEqual(@as(u16, 8), borrowed.transaction.operations[2].copy.destination_col);
    try std.testing.expectEqual(journal.CursorShape.bar, borrowed.transaction.operations[3].cursor.shape);
    try fifo.complete(borrowed.handle);
}

test "recolor masked fill and visual patch masks are deeply rebased" {
    var fifo = try Fifo.init(std.testing.io, std.testing.allocator);
    defer fifo.deinit();
    var foreground = [_]u8{ 1, 2 };
    var background = [_]u8{ 3, 4 };
    var underline = [_]u8{ 5, 6 };
    var rgb: [256]journal.Rgb = @splat(.{ .r = 7, .g = 8, .b = 9 });
    var fill_mask = [_]u8{ 0xaa, 0x55 };
    var patch_mask = [_]u8{0xf0};
    var operations = [_]journal.Operation{
        .{ .recolor = .{ .foreground = &foreground, .background = &background, .underline = &underline, .rgb = &rgb } },
        .{ .masked_fill = .{ .rect = .{ .row = 0, .col = 0, .rows = 1, .cols = 2 }, .mask = &fill_mask, .cell = std.mem.zeroes(journal.Cell) } },
        .{ .visual_patch = .{ .rect = .{ .row = 0, .col = 0, .rows = 1, .cols = 1 }, .changed_mask = &patch_mask } },
        .{ .visual_patch = .{ .rect = .{ .row = 1, .col = 1, .rows = 1, .cols = 1 }, .changed_mask = null } },
    };
    try enqueueForTest(&fifo, testIdentity(1), .{ .operations = &operations });
    foreground[0] = 99;
    background[0] = 99;
    underline[0] = 99;
    rgb[0].r = 99;
    fill_mask[0] = 0;
    patch_mask[0] = 0;
    const borrowed = fifo.take().?;
    try std.testing.expectEqual(@as(u8, 1), borrowed.transaction.operations[0].recolor.foreground[0]);
    try std.testing.expectEqual(@as(u8, 3), borrowed.transaction.operations[0].recolor.background[0]);
    try std.testing.expectEqual(@as(u8, 5), borrowed.transaction.operations[0].recolor.underline[0]);
    try std.testing.expectEqual(@as(u8, 7), borrowed.transaction.operations[0].recolor.rgb[0].r);
    try std.testing.expectEqual(@as(u8, 0xaa), borrowed.transaction.operations[1].masked_fill.mask[0]);
    try std.testing.expectEqual(@as(u8, 0xf0), borrowed.transaction.operations[2].visual_patch.changed_mask.?[0]);
    try std.testing.expectEqual(@as(?[]const u8, null), borrowed.transaction.operations[3].visual_patch.changed_mask);
    try fifo.complete(borrowed.handle);
}

test "allocation failure cancels in order and leaves source unchanged" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var fifo = try Fifo.init(std.testing.io, failing.allocator());
    defer fifo.deinit();
    var cells: [40]journal.Cell = @splat(std.mem.zeroes(journal.Cell));
    cells[0].codepoint = 'x';
    var failed_operations = [_]journal.Operation{.{ .replace = .{ .kind = .resize, .rows = 5, .cols = 8, .cells = &cells } }};
    try std.testing.expectError(error.OutOfMemory, fifo.enqueue(testIdentity(1), .{ .operations = &failed_operations }));
    try std.testing.expectEqual(@as(u8, 'x'), cells[0].codepoint);
    failing.fail_index = std.math.maxInt(usize);
    const later = CursorSource.init(9);
    try std.testing.expectEqual(@as(u64, 1), try fifo.enqueue(testIdentity(2), later.transaction()));
    const borrowed = fifo.take().?;
    try std.testing.expectEqual(@as(u16, 9), borrowed.transaction.operations[0].cursor.row);
    try fifo.complete(borrowed.handle);
}

test "allocation failure leaves a VT Pending transaction active" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var fifo = try Fifo.init(std.testing.io, failing.allocator());
    defer fifo.deinit();
    var pending: journal.Pending = .{};
    defer pending.deinit();
    var builder = try pending.prepare(std.testing.allocator, .{ .operations = 1, .cells = 40 });
    const cells = builder.cells(40);
    @memset(cells, std.mem.zeroes(journal.Cell));
    cells[0].codepoint = 'p';
    builder.append(.{ .replace = .{ .kind = .resize, .rows = 5, .cols = 8, .cells = cells } });
    pending.commit();
    try std.testing.expectError(error.OutOfMemory, fifo.enqueue(testIdentity(1), pending.view().?));
    try std.testing.expectEqual(@as(u8, 'p'), pending.view().?.operations[0].replace.cells[0].codepoint);
}

test "dynamic budget pressure releases only after completion" {
    var fifo = try Fifo.init(std.testing.io, std.testing.allocator);
    defer fifo.deinit();
    const bytes = try std.testing.allocator.alloc(u8, dynamic_payload_limit);
    defer std.testing.allocator.free(bytes);
    var operations = [_]journal.Operation{.{ .masked_fill = .{
        .rect = .{ .row = 0, .col = 0, .rows = 1, .cols = 1 },
        .mask = bytes,
        .cell = std.mem.zeroes(journal.Cell),
    } }};
    try enqueueForTest(&fifo, testIdentity(1), .{ .operations = &operations });
    var one = [_]u8{1};
    operations[0].masked_fill.mask = &one;
    try std.testing.expectError(error.Pressure, fifo.enqueue(testIdentity(2), .{ .operations = &operations }));
    const borrowed = fifo.take().?;
    try fifo.complete(borrowed.handle);
    try enqueueForTest(&fifo, testIdentity(2), .{ .operations = &operations });
}

test "completion identity and readiness recheck are exact" {
    var fifo = try Fifo.init(std.testing.io, std.testing.allocator);
    defer fifo.deinit();
    const transaction = CursorSource.init(1);
    try enqueueForTest(&fifo, testIdentity(1), transaction.transaction());
    try fifo.drainReadyWake();
    const borrowed = fifo.take().?;
    var wrong = borrowed.handle;
    wrong.generation += 1;
    try std.testing.expectError(error.InvalidCompletion, fifo.complete(wrong));
    try std.testing.expect(fifo.take() == null);
    try fifo.complete(borrowed.handle);
    try fifo.drainCapacityWake();
    try std.testing.expect(fifo.take() == null);
    try enqueueForTest(&fifo, testIdentity(2), transaction.transaction());
    try fifo.drainReadyWake();
    try std.testing.expect(fifo.take() != null);
}

test "reverse teardown frees dynamic ownership in every slot state" {
    var fifo = try Fifo.init(std.testing.io, std.testing.allocator);
    const states = [_]SlotState{ .writing, .ready, .draining, .cancelled };
    for (states, 0..) |state, index| {
        fifo.slots[index].state = state;
        fifo.slots[index].dynamic_payload = try std.testing.allocator.alloc(u8, index + 1);
        fifo.slots[index].dynamic_operations = try std.testing.allocator.alloc(journal.Operation, 1);
        fifo.slots[index].operations = fifo.slots[index].dynamic_operations.?;
    }
    fifo.deinit();
}
