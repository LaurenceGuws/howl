//! Native observation authority, teardown, allocation and concurrent-release proofs.
const std = @import("std");
const native = @import("howl_vt_native");
const owner = native.owner;
const source = native.observation;

fn create(allocator: std.mem.Allocator) !*owner.Owner {
    const config = native.c.hvt_config{ .rows = 2, .columns = 8, .history_rows = 0, .reserved = 0, .cell_width = 8, .cell_height = 16 };
    return owner.create(allocator, &config);
}
test "native observation exposes Reader and Controller as distinct exact capabilities" {
    try std.testing.expect(source.Reader != source.Controller);
    try std.testing.expect(@TypeOf(source.retire) == fn (*source.Controller) void);
    try std.testing.expect(@TypeOf(source.release) == fn (*source.Reader) void);
    try std.testing.expect(@TypeOf(source.read) == fn (*const source.Reader) source.ReadError!*const native.Terminal.Observation);
    const value = try create(std.testing.allocator);
    defer owner.destroy(value);
    const before = owner.observe(value, 0);
    const reader = try owner.openObservation(value);
    defer source.release(reader);
    try std.testing.expect(try source.read(reader) == owner.observation(value));
    try std.testing.expect(source.fromC(source.toC(reader)) == reader);
    try std.testing.expectEqualDeep(before, owner.observe(value, 0));
}

test "native owner and capability unwind every allocation prefix across retirement" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, campaign, .{});
}
fn campaign(allocator: std.mem.Allocator) !void {
    const value = try create(allocator);
    var live = true;
    defer if (live) owner.destroy(value);
    const reader = try owner.openObservation(value);
    defer source.release(reader);
    const peer = try source.retain(reader);
    defer source.release(peer);
    owner.destroy(value);
    live = false;
    try std.testing.expectError(error.SourceClosed, source.read(reader));
    try std.testing.expectError(error.SourceClosed, source.read(peer));
}

test "observation open is lazy transactional and reuses its capability without allocation" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const value = try create(failing.allocator());
    defer owner.destroy(value);
    const before = owner.observe(value, 0);
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, owner.openObservation(value));
    try std.testing.expectEqualDeep(before, owner.observe(value, 0));
    failing.fail_index = std.math.maxInt(usize);
    const reader = try owner.openObservation(value);
    defer source.release(reader);
    failing.fail_index = failing.alloc_index;
    const peer = try owner.openObservation(value);
    defer source.release(peer);
    try std.testing.expect(reader == peer);
    const retained = try source.retain(peer);
    defer source.release(retained);
    try std.testing.expectEqualDeep(before, owner.observe(value, 0));
}

test "source reference ceiling includes Controller open and downstream references" {
    const value = try create(std.testing.allocator);
    defer owner.destroy(value);
    const reader = try owner.openObservation(value);
    defer source.release(reader);
    var extras: [source.maximum_references - 2]*source.Reader = undefined;
    var count: usize = 0;
    defer for (extras[0..count]) |extra| source.release(extra);
    for (&extras) |*extra| {
        extra.* = try source.retain(reader);
        count += 1;
    }
    const before = owner.observe(value, 0);
    try std.testing.expectError(error.ResourceLimit, source.retain(reader));
    try std.testing.expectError(error.ResourceLimit, owner.openObservation(value));
    try std.testing.expect(try source.read(reader) == owner.observation(value));
    try std.testing.expectEqualDeep(before, owner.observe(value, 0));
    count -= 1;
    source.release(extras[count]);
    const replacement = try owner.openObservation(value);
    defer source.release(replacement);
    try std.testing.expect(replacement == reader);
}

test "retired Reader cannot revive when canonical owner allocation address is reused" {
    const memory = try std.testing.allocator.alloc(u8, 32 * 1024 * 1024);
    defer std.testing.allocator.free(memory);
    var arena = std.heap.FixedBufferAllocator.init(memory);
    const first = try create(arena.allocator());
    var first_live = true;
    defer if (first_live) owner.destroy(first);
    const address = @intFromPtr(first);
    // Keep the capability allocator independent so resetting fully-freed canonical
    // storage cannot itself invalidate the retained identity/lifetime allocation.
    const controller = try source.create(std.testing.allocator, owner.observation(first));
    var controller_live = true;
    defer if (controller_live) source.retire(controller);
    const reader = try source.open(controller);
    defer source.release(reader);
    source.retire(controller);
    controller_live = false;
    owner.destroy(first);
    first_live = false;
    arena.reset();
    const second = try create(arena.allocator());
    defer owner.destroy(second);
    try std.testing.expectEqual(address, @intFromPtr(second));
    const second_reader = try owner.openObservation(second);
    defer source.release(second_reader);
    try std.testing.expect(reader != second_reader);
    try std.testing.expectError(error.SourceClosed, source.read(reader));
    try std.testing.expect(try source.read(second_reader) == owner.observation(second));
}

test "independent retained Readers release concurrently after source retirement" {
    const value = try create(std.testing.allocator);
    var owner_live = true;
    defer if (owner_live) owner.destroy(value);
    const reader = try owner.openObservation(value);
    var reader_live = true;
    defer if (reader_live) source.release(reader);
    var gate = std.atomic.Value(bool).init(false);
    var failed = std.atomic.Value(bool).init(false);
    const Worker = struct {
        fn run(reference: *source.Reader, start: *std.atomic.Value(bool), bad: *std.atomic.Value(bool)) void {
            while (!start.load(.acquire)) std.atomic.spinLoopHint();
            if (source.read(reference)) |pointer| {
                // zig-audit: acknowledge discard
                // reason: A still-live pointer is itself the failure; never dereference canonical storage after retirement.
                _ = pointer;
                bad.store(true, .release);
            } else |err| {
                if (err != error.SourceClosed) bad.store(true, .release);
            }
            source.release(reference);
        }
    };
    var workers: [8]std.Thread = undefined;
    var count: usize = 0;
    var joined = false;
    defer if (!joined) {
        gate.store(true, .release);
        for (workers[0..count]) |worker| worker.join();
    };
    for (&workers) |*worker| {
        const reference = try source.retain(reader);
        worker.* = std.Thread.spawn(.{}, Worker.run, .{ reference, &gate, &failed }) catch |err| {
            source.release(reference);
            return err;
        };
        count += 1;
    }
    owner.destroy(value);
    owner_live = false;
    source.release(reader);
    reader_live = false;
    gate.store(true, .release);
    for (workers) |worker| worker.join();
    joined = true;
    try std.testing.expect(!failed.load(.acquire));
}
