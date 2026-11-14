//! App-private checked handoff of VT-owned borrowed output. The SDL worker
//! serializes prepare/replace/release; GUI consumers only hold immutable cuts.
//! This is test-only until the app worker replaces its Instance ownership.
const std = @import("std");
const vt = @import("howl_vt");
const output = @import("howl_vt_output");
const state = @import("output_state");
const Borrowed = state.State(false);

/// Copied descriptor with a borrowed immutable output snapshot. Copies retain
/// the same pin; only its exact live owner and serial may retire that pin.
pub const Frame = struct {
    snapshot: state.Snapshot,
    owner: *const Projection,
    occurrence: u64,
    serial: u64,
    presentation_generation: u64,
};

/// A cut is unavailable, already held, or has exhausted its checked serial.
pub const HoldError = Borrowed.HoldError || error{LeaseSequenceOverflow};
/// Only an exact, currently pinned cut can be retired.
pub const ReleaseError = error{InvalidLease};
/// Replacement also validates the previous caller-provided cut.
pub const ReplaceError = HoldError || ReleaseError;

/// Lifetime owner sits beside the canonical PTY/VT Core, never in the GUI.
/// The caller must keep `canonical` address-stable until this owner is retired.
pub const Projection = struct {
    allocator: std.mem.Allocator,
    canonical: *vt.Terminal,
    direct: *Borrowed,
    serial: u64 = 0,
    presentation_generation: u64 = 1,

    /// Retains a shared Text store without transferring ownership from the caller.
    pub fn create(allocator: std.mem.Allocator, canonical: *vt.Terminal, store: *output.PresentationStore, config: state.SharedConfig) Borrowed.BorrowedInitError!*Projection {
        const self = try allocator.create(Projection);
        errdefer allocator.destroy(self);
        const direct = try Borrowed.initBorrowedShared(allocator, canonical, store, config);
        self.* = .{ .allocator = allocator, .canonical = canonical, .direct = direct };
        return self;
    }

    /// A pinned cut must be retired before destroying either owner.
    pub fn tryDestroy(self: *Projection) error{PublicationBorrowed}!void {
        if (self.direct.leased) return error.PublicationBorrowed;
        self.destroy();
    }

    /// Quiesced teardown, with a debug assertion against an outstanding GUI pin.
    pub fn destroy(self: *Projection) void {
        std.debug.assert(!self.direct.leased);
        const allocator = self.allocator;
        self.direct.deinit();
        allocator.destroy(self);
    }

    /// Prepare can advance while a consumer holds an older immutable cut.
    pub fn prepare(self: *Projection, history_offset: u32) Borrowed.FlushError!void {
        self.direct.selectHistoryOffset(history_offset);
        try self.direct.flush();
    }

    /// Transfers one ready immutable cut with a nonreused serial on this owner.
    pub fn hold(self: *Projection) HoldError!Frame {
        if (self.serial == std.math.maxInt(u64)) return error.LeaseSequenceOverflow;
        const snapshot = try self.direct.hold();
        self.serial += 1;
        return .{
            .snapshot = snapshot,
            .owner = self,
            .occurrence = self.canonical.observation().occurrenceIdentity(),
            .serial = self.serial,
            .presentation_generation = self.presentation_generation,
        };
    }

    /// Rejects a stale/foreign previous frame before retiring the live pin.
    /// Readiness and serial preflight preserve the old lease on failure.
    pub fn replace(self: *Projection, previous: ?Frame) ReplaceError!Frame {
        if (!self.direct.ready) return error.NotReady;
        if (self.serial == std.math.maxInt(u64)) return error.LeaseSequenceOverflow;
        if (previous) |old| {
            try self.release(old);
        } else if (self.direct.leased) return error.LeaseBusy;
        return self.hold();
    }

    /// Validate before touching internal pinned row or resource storage.
    pub fn release(self: *Projection, frame: Frame) ReleaseError!void {
        if (frame.owner != self or frame.occurrence != self.canonical.observation().occurrenceIdentity() or
            !self.direct.leased or frame.serial != self.serial)
            return error.InvalidLease;
        self.direct.release();
    }
};

test "app-owned borrowed projection rejects foreign and stale leases without releasing the live cut" {
    const allocator = std.testing.allocator;
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const store = try output.initPresentationStore(allocator, threaded.io(), .{
        .regular = .{ .path = .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 12 } } },
    }, .{
        .shape_cache = .{ .entry_capacity = 128, .scalar_capacity = 2048, .glyph_capacity = 1024, .max_sequence_scalars = 80 },
        .shaped_capacity = 160,
        .raster_bytes = 512 * 512,
    });
    defer output.releasePresentationStore(store);

    var canonical_a: vt.Terminal = undefined;
    try vt.Terminal.initWithHistoryInto(&canonical_a, allocator, 2, 4, 8);
    defer canonical_a.deinit();
    var canonical_b: vt.Terminal = undefined;
    try vt.Terminal.initWithHistoryInto(&canonical_b, allocator, 2, 4, 8);
    defer canonical_b.deinit();
    const cell = output.presentationStoreCellSize(store);
    try canonical_a.setCellPixelSize(cell.width, cell.height);
    try canonical_b.setCellPixelSize(cell.width, cell.height);
    const a = try Projection.create(allocator, &canonical_a, store, .{ .history_capacity = 8 });
    defer a.destroy();
    const b = try Projection.create(allocator, &canonical_b, store, .{ .history_capacity = 8 });
    defer b.destroy();
    try std.testing.expectEqual(@as(u32, 3), output.presentationStoreReferences(store));

    try std.testing.expect((try canonical_a.feed("A")).stateChanged());
    try std.testing.expect((try canonical_b.feed("B")).stateChanged());
    try a.prepare(0);
    try b.prepare(0);
    const held_a = try a.hold();
    const held_b = try b.hold();
    try std.testing.expect(held_a.snapshot.glyphs[0].len != 0);
    const original = try allocator.dupe(output.commands.Command, held_a.snapshot.glyphs[0]);
    defer allocator.free(original);
    try std.testing.expectError(error.PublicationBorrowed, a.tryDestroy());
    try std.testing.expectError(error.InvalidLease, a.replace(held_b));
    try std.testing.expectError(error.InvalidLease, b.release(held_a));
    try std.testing.expectError(error.LeaseBusy, a.hold());
    try std.testing.expect(a.direct.leased);
    try std.testing.expect(b.direct.leased);

    try std.testing.expect((try canonical_a.feed("C")).stateChanged());
    try a.prepare(0);
    try std.testing.expectEqualDeep(original, held_a.snapshot.glyphs[0]);
    const fresh = try a.replace(held_a);
    try std.testing.expect(fresh.serial > held_a.serial);
    try std.testing.expect(fresh.snapshot.terminal_revision > held_a.snapshot.terminal_revision);
    try std.testing.expectError(error.InvalidLease, a.release(held_a));
    a.serial = std.math.maxInt(u64);
    try std.testing.expectError(error.LeaseSequenceOverflow, a.replace(fresh));
    a.serial = fresh.serial;
    try std.testing.expect(a.direct.leased);
    try a.release(fresh);
    try std.testing.expectError(error.InvalidLease, a.release(fresh));
    try b.release(held_b);
    try std.testing.expectEqual(@as(u32, 3), output.presentationStoreReferences(store));
}
