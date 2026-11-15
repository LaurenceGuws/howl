//! Shared native lane proofs using the public opaque owner and internal claim boundary.
const std = @import("std");
const output = @import("howl_vt_output");
const state = @import("output_state");
const support = @import("text_support");
const cache = @import("glyph_cache");
const shaped_text = @import("howl_text");
const a = std.testing.allocator;

const DiscoveryProof = struct {
    allocator: std.mem.Allocator,
    calls: u32 = 0,
};
var discovery_created: std.atomic.Value(u32) = .init(0);
var discovery_destroyed: std.atomic.Value(u32) = .init(0);
var discovery_calls: std.atomic.Value(u32) = .init(0);

fn proofCreate(allocator: std.mem.Allocator) ?output.FallbackContext {
    const proof = allocator.create(DiscoveryProof) catch return null;
    proof.* = .{ .allocator = allocator };
    const previous = discovery_created.fetchAdd(1, .monotonic);
    std.debug.assert(previous == 0);
    // zig-audit: acknowledge ptr_cast
    // reason: The proof factory passes its exact owned DiscoveryProof address to the owning store.
    return @ptrCast(proof);
}
fn proofState(context: output.FallbackContext) *DiscoveryProof {
    // zig-audit: acknowledge ptr_cast
    // reason: Only the test factory creates this opaque context.
    // zig-audit: acknowledge align_cast
    // reason: The original test allocation supplies the exact DiscoveryProof alignment.
    return @ptrCast(@alignCast(context));
}
fn proofFind(context: output.FallbackContext, variant: output.FontVariant, codepoints: []const u32) ?shaped_text.FallbackFile {
    if (variant != .regular) return null;
    proofState(context).calls += 1;
    const previous = discovery_calls.fetchAdd(1, .monotonic);
    std.debug.assert(previous < 4);
    if (codepoints.len == 1 and codepoints[0] == 0xe0b0)
        return .{ .path = @import("test_fonts").symbol_font };
    return null;
}
fn proofDestroy(context: output.FallbackContext) void {
    const proof = proofState(context);
    proof.allocator.destroy(proof);
    const previous = discovery_destroyed.fetchAdd(1, .monotonic);
    std.debug.assert(previous == 0);
}

fn makeStore(io: std.Io) !*output.PresentationStore {
    return output.initPresentationStore(a, io, .{ .regular = .{ .path = .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 12 } } } }, .{
        .shape_cache = .{ .entry_capacity = 128, .scalar_capacity = 2048, .glyph_capacity = 1024, .max_sequence_scalars = 80 },
        .shaped_capacity = 160,
        .raster_bytes = 512 * 512,
    });
}

test "owning discovery admits a missing font exactly once and retires its context" {
    discovery_created.store(0, .monotonic);
    discovery_destroyed.store(0, .monotonic);
    discovery_calls.store(0, .monotonic);
    var threaded = std.Io.Threaded.init(a, .{});
    defer threaded.deinit();
    const store = try output.initPresentationStore(a, threaded.io(), .{
        .regular = .{ .path = .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 16 } } },
        .fallback_factory = .{ .create = proofCreate, .find = proofFind, .destroy = proofDestroy },
    }, .{
        .shape_cache = .{ .entry_capacity = 32, .scalar_capacity = 128, .glyph_capacity = 128, .max_sequence_scalars = 16 },
        .shaped_capacity = 32,
        .raster_bytes = 4096,
    });
    var live = true;
    defer if (live) output.releasePresentationStore(store);
    try std.testing.expectEqual(@as(u32, 1), discovery_created.load(.monotonic));
    try std.testing.expectEqual(@as(u32, 0), discovery_destroyed.load(.monotonic));

    support.claim(store);
    var claimed = true;
    defer if (claimed) support.unclaim(store);
    const lane = support.work(support.borrowStore(store));
    var clusters: [16]u32 = undefined;
    var glyphs: [32]shaped_text.Glyph = undefined;
    const symbol = [_]u32{0xe0b0};
    const first = try cache.resolveShape(lane.shape_cache, .regular, &symbol, &clusters, &glyphs);
    try std.testing.expectEqual(@as(u8, 1), first.face_index);
    const repeated = try cache.resolveShape(lane.shape_cache, .regular, &symbol, &clusters, &glyphs);
    try std.testing.expectEqual(@as(u8, 1), repeated.face_index);
    try std.testing.expectEqual(@as(u32, 1), discovery_calls.load(.monotonic));
    const missing = [_]u32{0x10ffff};
    const first_missing = try cache.resolveShape(lane.shape_cache, .regular, &missing, &clusters, &glyphs);
    try std.testing.expectEqual(@as(u8, 0), first_missing.face_index);
    const repeated_missing = try cache.resolveShape(lane.shape_cache, .regular, &missing, &clusters, &glyphs);
    try std.testing.expectEqual(first_missing.face_index, repeated_missing.face_index);
    try std.testing.expectEqual(@as(u32, 2), discovery_calls.load(.monotonic));
    support.unclaim(store);
    claimed = false;

    output.releasePresentationStore(store);
    live = false;
    try std.testing.expectEqual(@as(u32, 1), discovery_destroyed.load(.monotonic));
}
fn destroy(owner: *output.Terminal) void {
    // zig-audit: acknowledge catch_unreachable
    // reason: Each test releases every held lease before owner cleanup.
    owner.deinit() catch unreachable;
}
fn unpin(owner: *output.Terminal, lease: output.Lease) void {
    // zig-audit: acknowledge catch_unreachable
    // reason: Cleanup receives one live lease from its exact owner.
    owner.release(lease) catch unreachable;
}
fn ready(allocator: std.mem.Allocator, store: *output.PresentationStore) !*output.Terminal {
    const owner = try output.Terminal.initShared(allocator, store, .{});
    errdefer destroy(owner);
    try owner.feed("\x1b[?25lA");
    try owner.flush();
    return owner;
}

test "blank direct rows reserve no commands and later text preserves held blank output" {
    var threaded = std.Io.Threaded.init(a, .{});
    defer threaded.deinit();
    const store = try makeStore(threaded.io());
    defer output.releasePresentationStore(store);
    const owner = try state.State(true).initShared(a, store, .{});
    defer owner.deinit();

    try owner.flush();
    try std.testing.expectEqual(@as(usize, 0), owner.retainedCommandBytes());
    const blank = try owner.hold();
    var blank_held = true;
    defer if (blank_held) owner.release();
    try std.testing.expectEqual(@as(usize, 0), blank.glyphs[0].len);
    const pixels = try a.dupe(u8, blank.atlas_pixels);
    defer a.free(pixels);

    try owner.feed("\x1b[?25lA");
    try owner.flush();
    try std.testing.expect(owner.retainedCommandBytes() > 0);
    try std.testing.expectEqualSlices(u8, pixels, blank.atlas_pixels);
    try std.testing.expectEqual(@as(usize, 0), blank.glyphs[0].len);
    owner.release();
    blank_held = false;

    const text_cut = try owner.hold();
    defer owner.release();
    try std.testing.expect(text_cut.glyphs[0].len > 0);
    for (text_cut.glyphs[1..text_cut.rows]) |row| try std.testing.expectEqual(@as(usize, 0), row.len);
}

test "two public shared owners isolate held resources and remain live after caller release" {
    var threaded = std.Io.Threaded.init(a, .{});
    defer threaded.deinit();
    const store = try makeStore(threaded.io());
    var caller_live = true;
    defer if (caller_live) output.releasePresentationStore(store);
    const first = try ready(a, store);
    defer destroy(first);
    const second = try ready(a, store);
    defer destroy(second);
    try std.testing.expectEqual(@as(u32, 3), output.presentationStoreReferences(store));
    const held = try first.hold();
    defer unpin(first, held);
    const pixels = try a.dupe(u8, held.snapshot.atlas_pixels);
    defer a.free(pixels);
    const commands = try a.dupe(output.commands.Command, held.snapshot.glyphs[0]);
    defer a.free(commands);
    try std.testing.expectError(error.SharedStore, first.resetShapes());
    const usage = output.presentationStoreUsage(store);
    try std.testing.expect(usage.shape.entries != 0);
    try second.resetAtlas();
    try second.feed("\x1b[HBBBB");
    try second.flush();
    const other = try second.hold();
    defer unpin(second, other);
    try std.testing.expect(held.snapshot.atlas_pixels.ptr != other.snapshot.atlas_pixels.ptr);
    output.releasePresentationStore(store);
    caller_live = false;
    try first.feed("\x1b[HCCCC");
    try first.flush();
    try std.testing.expectEqualSlices(u8, pixels, held.snapshot.atlas_pixels);
    try std.testing.expectEqualDeep(commands, held.snapshot.glyphs[0]);
}

test "shared busy claim leaves feed independent and no-op cursor cuts claim free" {
    var threaded = std.Io.Threaded.init(a, .{});
    defer threaded.deinit();
    const store = try makeStore(threaded.io());
    defer output.releasePresentationStore(store);
    const owner = try ready(a, store);
    defer destroy(owner);
    support.claim(store);
    var claimed = true;
    defer if (claimed) support.unclaim(store);
    try owner.flush();
    try owner.feed("\x1b[5 q\x1b[?25h\x1b[2;2H");
    try owner.flush();
    try owner.feed("B");
    try std.testing.expectError(error.PresentationBusy, owner.flush());
    try owner.feed("\x1b[2;2HC");
    try std.testing.expectEqual(@as(u21, 'C'), owner.observation().semanticView(0).cellAt(1, 1));
    support.unclaim(store);
    claimed = false;
    try owner.flush();
    const held = try owner.hold();
    defer unpin(owner, held);
    try std.testing.expect(held.snapshot.glyphs[1].len != 0);
}

fn initFailure(allocator: std.mem.Allocator, store: *output.PresentationStore) !void {
    const owner = try output.Terminal.initShared(allocator, store, .{});
    defer destroy(owner);
}
test "shared initialization and replacement allocation failures restore references" {
    var threaded = std.Io.Threaded.init(a, .{});
    defer threaded.deinit();
    const store = try makeStore(threaded.io());
    defer output.releasePresentationStore(store);
    try std.testing.checkAllAllocationFailures(a, initFailure, .{store});
    try std.testing.expectEqual(@as(u32, 1), output.presentationStoreReferences(store));
    const next = try makeStore(threaded.io());
    defer output.releasePresentationStore(next);
    var failing = std.testing.FailingAllocator.init(a, .{});
    const owner = try ready(failing.allocator(), store);
    var owner_live = true;
    defer if (owner_live) destroy(owner);
    const before = owner.acceptedMetrics().?;
    var failures: usize = 0;
    for (0..32) |offset| {
        failing.fail_index = failing.alloc_index + offset;
        if (owner.replaceWorkingShared(next, .{})) |_| {
            failing.fail_index = std.math.maxInt(usize);
            break;
        } else |err| {
            failing.fail_index = std.math.maxInt(usize);
            try std.testing.expectEqual(error.OutOfMemory, err);
            failures += 1;
            try std.testing.expectEqual(@as(u32, 2), output.presentationStoreReferences(store));
            try std.testing.expectEqual(@as(u32, 1), output.presentationStoreReferences(next));
            try std.testing.expectEqualDeep(before, owner.acceptedMetrics().?);
        }
    } else return error.NoSuccessfulReplacement;
    try std.testing.expect(failures > 0);
    try std.testing.expectEqual(@as(u32, 1), output.presentationStoreReferences(store));
    try std.testing.expectEqual(@as(u32, 2), output.presentationStoreReferences(next));
    try owner.flush();
    try owner.deinit();
    owner_live = false;
    try std.testing.expectEqual(@as(u32, 1), output.presentationStoreReferences(next));
}

const Waiter = struct {
    store: *output.PresentationStore,
    owner: ?*output.Terminal,
    result: ?*output.Terminal = null,
    done: std.atomic.Value(bool) = .init(false),
    // zig-audit: acknowledge anyerror
    // reason: The joined test worker reports either exact init or replacement failure unchanged.
    failure: ?anyerror = null,
    fn run(self: *Waiter) void {
        defer self.done.store(true, .release);
        if (self.owner) |owner| {
            owner.replaceWorkingShared(self.store, .{}) catch |err| {
                self.failure = err;
            };
        } else {
            self.result = output.Terminal.initShared(a, self.store, .{}) catch |err| blk: {
                self.failure = err;
                break :blk null;
            };
        }
    }
};
fn waitClaim(io: std.Io, store: *output.PresentationStore, owner: ?*output.Terminal) !void {
    support.claim(store);
    var claimed = true;
    var worker = Waiter{ .store = store, .owner = owner };
    const thread = std.Thread.spawn(.{}, Waiter.run, .{&worker}) catch |err| {
        support.unclaim(store);
        return err;
    };
    var joined = false;
    defer {
        if (claimed) support.unclaim(store);
        if (!joined) thread.join();
        if (worker.result) |result| destroy(result);
    }
    const start = std.Io.Clock.awake.now(io);
    while (!support.claimContendedForTest(store)) {
        if (worker.done.load(.acquire)) return error.DidNotWait;
        if (start.durationTo(std.Io.Clock.awake.now(io)).toNanoseconds() >= 5 * std.time.ns_per_s) return error.Timeout;
        std.atomic.spinLoopHint();
    }
    try std.testing.expect(!worker.done.load(.acquire));
    support.unclaim(store);
    claimed = false;
    thread.join();
    joined = true;
    if (worker.failure) |err| return err;
}
test "shared init and replacement wait for the real native claim outside transfer ownership" {
    var threaded = std.Io.Threaded.init(a, .{});
    defer threaded.deinit();
    const store = try makeStore(threaded.io());
    defer output.releasePresentationStore(store);
    try waitClaim(threaded.io(), store, null);
    try std.testing.expectEqual(@as(u32, 1), output.presentationStoreReferences(store));
    const owner = try ready(a, store);
    defer destroy(owner);
    try waitClaim(threaded.io(), store, owner);
    try std.testing.expectEqual(@as(u32, 2), output.presentationStoreReferences(store));
    try owner.flush();
}

test "direct output borrows one canonical VT and survives producer resize" {
    const vt = @import("howl_vt");
    const Candidate = @import("output_state").State(false);
    var threaded = std.Io.Threaded.init(a, .{});
    defer threaded.deinit();
    const store = try makeStore(threaded.io());
    defer output.releasePresentationStore(store);
    const canonical = try a.create(vt.Terminal);
    defer a.destroy(canonical);
    try vt.Terminal.initWithHistoryInto(canonical, a, 2, 4, 32);
    defer canonical.deinit();
    try std.testing.expectError(error.HistoryCapacityMismatch, Candidate.initBorrowedShared(a, canonical, store, .{}));
    try std.testing.expectError(error.PixelSizeMismatch, Candidate.initBorrowedShared(a, canonical, store, .{ .history_capacity = 32 }));
    try std.testing.expectEqual(@as(u32, 1), output.presentationStoreReferences(store));
    const cell = output.presentationStoreCellSize(store);
    try canonical.setCellPixelSize(cell.width, cell.height);
    const direct = try Candidate.initBorrowedShared(a, canonical, store, .{ .history_capacity = 32 });
    var direct_live = true;
    defer if (direct_live) direct.deinit();
    try std.testing.expect((try canonical.feed("\x1b[?25lA")).stateChanged());
    try direct.flush();
    const held = try direct.hold();
    var held_live = true;
    defer if (held_live) direct.release();
    try std.testing.expectEqual(@as(u16, 2), held.rows);
    try std.testing.expect(held.glyphs[0].len != 0);
    const saved = try a.dupe(output.commands.Command, held.glyphs[0]);
    defer a.free(saved);
    try canonical.setCellPixelSize(cell.width + 1, cell.height);
    try std.testing.expectError(error.PixelSizeMismatch, direct.flush());
    try std.testing.expectEqualDeep(saved, held.glyphs[0]);
    try canonical.setCellPixelSize(cell.width, cell.height);
    try canonical.resize(42, 128);
    try std.testing.expect((try canonical.feed("\x1b[42;128HZ")).stateChanged());
    try direct.flush();
    try std.testing.expectEqual(@as(u16, 42), direct.accepted_rows);
    try std.testing.expectEqual(@as(u16, 128), direct.accepted_cols);
    try std.testing.expectEqualDeep(saved, held.glyphs[0]);
    direct.release();
    held_live = false;
    direct.deinit();
    direct_live = false;
    try std.testing.expectEqual(@as(u32, 1), output.presentationStoreReferences(store));
    try std.testing.expect((try canonical.feed("A")).stateChanged());
    try canonical.resize(2, 513);
    try std.testing.expectError(error.UnsupportedDimensions, Candidate.initBorrowedShared(a, canonical, store, .{ .history_capacity = 32 }));
    try std.testing.expectEqual(@as(u32, 1), output.presentationStoreReferences(store));
}

fn borrowedInitFailure(allocator: std.mem.Allocator, canonical: *@import("howl_vt").Terminal, store: *output.PresentationStore) !void {
    const Candidate = @import("output_state").State(false);
    const direct = try Candidate.initBorrowedShared(allocator, canonical, store, .{ .history_capacity = 8 });
    defer direct.deinit();
}

test "borrowed output initialization failures retain canonical and shared ownership" {
    const vt = @import("howl_vt");
    var threaded = std.Io.Threaded.init(a, .{});
    defer threaded.deinit();
    const store = try makeStore(threaded.io());
    defer output.releasePresentationStore(store);
    const canonical = try a.create(vt.Terminal);
    defer a.destroy(canonical);
    try vt.Terminal.initWithHistoryInto(canonical, a, 2, 4, 8);
    defer canonical.deinit();
    const cell = output.presentationStoreCellSize(store);
    try canonical.setCellPixelSize(cell.width, cell.height);
    try std.testing.expect((try canonical.feed("A")).stateChanged());
    try std.testing.checkAllAllocationFailures(a, borrowedInitFailure, .{ canonical, store });
    try std.testing.expectEqual(@as(u32, 1), output.presentationStoreReferences(store));
    try std.testing.expectEqual(@as(u21, 'A'), canonical.observation().semanticView(0).cellAt(0, 0));
    try std.testing.expect((try canonical.feed("B")).stateChanged());
}

test "shared short scratch preserves long contextual shaping" {
    const text = @import("howl_text");
    const path = @import("test_fonts").normal_ligature_font;
    var threaded = std.Io.Threaded.init(a, .{});
    defer threaded.deinit();
    const store = try output.initPresentationStore(a, threaded.io(), .{ .regular = .{ .path = .{ .primary = path, .size = .{ .pixels = 12 } } } }, .{
        .shape_cache = .{ .entry_capacity = 256, .scalar_capacity = 512, .glyph_capacity = 512, .max_sequence_scalars = 24 },
        .shaped_capacity = 32,
        .raster_bytes = 512 * 512,
    });
    defer output.releasePresentationStore(store);
    const font = try text.FontSet.init(a, .{ .primary = path, .size = .{ .pixels = 12 } });
    defer font.deinit();
    const atlas: output.AtlasConfig = .{ .width = 512, .height = 512, .entry_capacity = 256 };
    const shared = try output.Terminal.initShared(a, store, .{ .atlas = atlas });
    defer destroy(shared);
    const private = try output.Terminal.initConfig(a, font, .{ .atlas = atlas });
    defer destroy(private);
    const bytes = "\x1b[?25l\x1b[H==>==>==>==>==>==>==>==>==>==>==>==>==>==>==>";
    try shared.feed(bytes);
    try private.feed(bytes);
    try shared.flush();
    try private.flush();
    const one = try shared.hold();
    defer unpin(shared, one);
    const two = try private.hold();
    defer unpin(private, two);
    try std.testing.expectEqualDeep(two.snapshot.glyphs[0], one.snapshot.glyphs[0]);
    try std.testing.expectEqualSlices(u8, two.snapshot.atlas_pixels, one.snapshot.atlas_pixels);
}

test "shared output admits a dense decorated multi-glyph row" {
    var threaded = std.Io.Threaded.init(a, .{});
    defer threaded.deinit();
    const store = try makeStore(threaded.io());
    defer output.releasePresentationStore(store);
    const owner = try output.Terminal.initShared(a, store, .{});
    defer destroy(owner);
    try owner.resize(1, 512);
    try owner.feed("\x1b[?25l\x1b[?7l\x1b[4:2;9m");
    for (0..512) |col| {
        try owner.feed(if (col % 2 == 0) "\x1b[41m" else "\x1b[44m");
        try owner.feed("x\u{0301}\u{0301}\u{0301}\u{0301}");
    }
    try owner.flush();
    const held = try owner.hold();
    defer unpin(owner, held);
    const count = held.snapshot.backgrounds[0].len + held.snapshot.decorations[0].len + held.snapshot.glyphs[0].len;
    try std.testing.expect(count > 512 * 5);
}

test "cached shape cannot exceed the consuming lane scratch" {
    var threaded = std.Io.Threaded.init(a, .{});
    defer threaded.deinit();
    const store = try output.initPresentationStore(a, threaded.io(), .{ .regular = .{ .path = .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 12 } } } }, .{
        .shape_cache = .{ .entry_capacity = 128, .scalar_capacity = 2048, .glyph_capacity = 1024, .max_sequence_scalars = 80 },
        .shaped_capacity = 1,
        .raster_bytes = 512 * 512,
    });
    defer output.releasePresentationStore(store);
    const owner = try ready(a, store);
    defer destroy(owner);
    const held = try owner.hold();
    defer unpin(owner, held);
    const before = try a.dupe(output.commands.Command, held.snapshot.glyphs[0]);
    defer a.free(before);
    {
        support.claim(store);
        defer support.unclaim(store);
        const lane = support.work(support.borrowStore(store));
        const sequence = [_]u32{ 'x', 0x0301, 0x0301, 0x0301, 0x0301 };
        var clusters: [24]u32 = undefined;
        var glyphs: [32]shaped_text.Glyph = undefined;
        const shaped = try cache.resolveShape(lane.shape_cache, .regular, &sequence, &clusters, &glyphs);
        try std.testing.expect(shaped.glyphs.len > 1);
    }
    try owner.feed("\x1b[Hx\u{0301}\u{0301}\u{0301}\u{0301}");
    try std.testing.expectError(error.InsufficientGlyphs, owner.flush());
    try std.testing.expectEqualDeep(before, held.snapshot.glyphs[0]);
}

test "automatic row limit follows a replacement shaping lane" {
    const Candidate = @import("output_state").State(false);
    var threaded = std.Io.Threaded.init(a, .{});
    defer threaded.deinit();
    const first = try makeStore(threaded.io());
    defer output.releasePresentationStore(first);
    const second = try output.initPresentationStore(a, threaded.io(), .{ .regular = .{ .path = .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 12 } } } }, .{
        .shape_cache = .{ .entry_capacity = 128, .scalar_capacity = 2048, .glyph_capacity = 1024, .max_sequence_scalars = 80 },
        .shaped_capacity = 1,
        .raster_bytes = 512 * 512,
    });
    defer output.releasePresentationStore(second);
    const direct = try Candidate.initShared(a, first, .{});
    defer direct.deinit();
    try std.testing.expectEqual(@as(usize, 0), direct.config.command_limit);
    const previous = direct.command_limit;
    var replacement = try direct.stageWorkingShared(second, .{ .command_limit = direct.config.command_limit }, 24, 80);
    defer direct.discardWorking(&replacement);
    direct.commitWorking(&replacement);
    try std.testing.expectEqual(@as(usize, 0), direct.config.command_limit);
    try std.testing.expect(direct.command_limit < previous);
    var back = try direct.stageWorkingShared(first, .{ .command_limit = direct.config.command_limit }, 24, 80);
    defer direct.discardWorking(&back);
    direct.commitWorking(&back);
    try std.testing.expectEqual(previous, direct.command_limit);
    var explicit = try direct.stageWorkingShared(second, .{ .command_limit = 8 }, 24, 80);
    defer direct.discardWorking(&explicit);
    direct.commitWorking(&explicit);
    try std.testing.expectEqual(@as(usize, 8), direct.config.command_limit);
    try std.testing.expectEqual(@as(usize, 8), direct.command_limit);
}

test "automatic command bound admits a dense fractional dotted row" {
    var threaded = std.Io.Threaded.init(a, .{});
    defer threaded.deinit();
    const store = try output.initPresentationStore(a, threaded.io(), .{ .regular = .{ .path = .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 48 } } } }, .{
        .shape_cache = .{ .entry_capacity = 128, .scalar_capacity = 2048, .glyph_capacity = 1024, .max_sequence_scalars = 80 },
        .shaped_capacity = 1,
        .raster_bytes = 512 * 512,
    });
    defer output.releasePresentationStore(store);
    const owner = try output.Terminal.initShared(a, store, .{ .atlas = .{ .width = 512, .height = 512, .entry_capacity = 128 } });
    defer destroy(owner);
    try owner.resize(1, 512);
    try owner.feed("\x1b[?25l\x1b[?7l\x1b[4:4m");
    for (0..512) |_| try owner.feed("\x1b]66;s=1:n=1:d=2;X\x07");
    try owner.flush();
    const held = try owner.hold();
    defer unpin(owner, held);
    const count = held.snapshot.backgrounds[0].len + held.snapshot.decorations[0].len + held.snapshot.glyphs[0].len;
    // The prior automatic cap allowed only 512 * (1 shaped glyph + 4) + 1024.
    try std.testing.expect(count > 512 * 5 + 1024);
}

test "automatic row limit follows replacement font width" {
    const Candidate = @import("output_state").State(false);
    var threaded = std.Io.Threaded.init(a, .{});
    defer threaded.deinit();
    const small = try makeStore(threaded.io());
    defer output.releasePresentationStore(small);
    const large = try output.initPresentationStore(a, threaded.io(), .{ .regular = .{ .path = .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 48 } } } }, .{
        .shape_cache = .{ .entry_capacity = 128, .scalar_capacity = 2048, .glyph_capacity = 1024, .max_sequence_scalars = 80 },
        .shaped_capacity = 160,
        .raster_bytes = 512 * 512,
    });
    defer output.releasePresentationStore(large);
    const direct = try Candidate.initShared(a, small, .{});
    defer direct.deinit();
    const before = direct.command_limit;
    var replacement = try direct.stageWorkingShared(large, .{}, 24, 80);
    defer direct.discardWorking(&replacement);
    direct.commitWorking(&replacement);
    try std.testing.expect(direct.command_limit > before);
    var back = try direct.stageWorkingShared(small, .{}, 24, 80);
    defer direct.discardWorking(&back);
    direct.commitWorking(&back);
    try std.testing.expectEqual(before, direct.command_limit);
}
