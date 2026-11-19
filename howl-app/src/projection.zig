//! Checked lease handoff of VT-owned borrowed output. The terminal worker
//! serializes prepare/replace/release; SDL only receives immutable cuts.
const std = @import("std");
const vt = @import("howl_vt");
const output = @import("howl_vt_output");
const state = @import("output_state");
const pty_vt = @import("pty_vt.zig");
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
/// Shared Text staging, canonical geometry and generation admission failures.
pub const ConfigureError = Borrowed.StageReplaceError || pty_vt.ResizeError || error{ GenerationOverflow, InvalidOwner };
/// Target geometry: retain the current grid, choose a grid, or derive one from a surface.
pub const Target = union(enum) {
    current,
    grid: struct { rows: u16, columns: u16 },
    surface: struct { width: u16, height: u16 },
};
/// Committed canonical lattice and grid returned to the app layout owner.
pub const Geometry = struct {
    rows: u16,
    columns: u16,
    cell_size: vt.Terminal.CellPixelSize,
};

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

    /// Retain the old Text/output owner until all fallible work succeeds.
    /// Font staging can wait on a shared Text claim, matching the current app contract.
    /// The caller serializes this with canonical service and output preparation.
    pub fn reconfigure(self: *Projection, core: *pty_vt.Core, store: *output.PresentationStore, config: state.SharedConfig, target: Target) ConfigureError!Geometry {
        return self.reconfigureWith(core, core, store, config, target);
    }

    // zig-audit: acknowledge anytype
    // reason: The actual app Core and a scripted resize failure prove the same atomic stage/commit path.
    fn reconfigureWith(self: *Projection, core: *pty_vt.Core, resizer: anytype, store: *output.PresentationStore, config: state.SharedConfig, target: Target) ConfigureError!Geometry {
        if (self.canonical != &core.terminal) return error.InvalidOwner;
        if (core.inputBlocked()) return error.InputPending;
        const next_generation = std.math.add(u64, self.presentation_generation, 1) catch return error.GenerationOverflow;
        const resolved = output.presentationStoreCellSize(store);
        const cell: vt.Terminal.CellPixelSize = .{ .width = resolved.width, .height = resolved.height };
        const current = core.terminal.semanticView(0);
        const rows, const columns = switch (target) {
            .current => .{ current.rows, current.cols },
            .grid => |grid| .{ grid.rows, grid.columns },
            .surface => |surface| geometry: {
                if (surface.width == 0 or surface.height == 0) return error.InvalidDimensions;
                const rows = surface.height / resolved.height;
                const columns = surface.width / resolved.width;
                if (rows == 0 or columns < 2) return error.InvalidDimensions;
                break :geometry .{ rows, columns };
            },
        };
        var replacement = try self.direct.stageWorkingShared(store, config, rows, columns);
        defer self.direct.discardWorking(&replacement);

        const previous_cell = core.terminal.cellPixelSize().?;
        if (current.rows != rows or current.cols != columns or
            previous_cell.width != cell.width or previous_cell.height != cell.height)
            try resizer.resizeGeometry(rows, columns, cell);
        self.direct.commitWorking(&replacement);
        self.presentation_generation = next_generation;
        return .{ .rows = rows, .columns = columns, .cell_size = cell };
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

test "app-owned shared font reconfigure rolls back stage and PTY failure before changing the generation" {
    const allocator = std.testing.allocator;
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const font = @import("test_fonts").primary_font;
    const shared_config: output.StoreConfig = .{
        .shape_cache = .{ .entry_capacity = 128, .scalar_capacity = 2048, .glyph_capacity = 1024, .max_sequence_scalars = 80 },
        .shaped_capacity = 160,
        .raster_bytes = 512 * 512,
    };
    const first = try output.initPresentationStore(allocator, threaded.io(), .{
        .regular = .{ .path = .{ .primary = font, .size = .{ .pixels = 12 } } },
    }, shared_config);
    defer output.releasePresentationStore(first);
    const next = try output.initPresentationStore(allocator, threaded.io(), .{
        .regular = .{ .path = .{ .primary = font, .size = .{ .pixels = 18 } } },
    }, shared_config);
    defer output.releasePresentationStore(next);
    const initial_cell = output.presentationStoreCellSize(first);
    const next_cell = output.presentationStoreCellSize(next);
    try std.testing.expect(next_cell.width > initial_cell.width);

    const core = try allocator.create(pty_vt.Core);
    defer allocator.destroy(core);
    try core.initInto(allocator, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "sleep 30",
        .rows = 2,
        .columns = 4,
        .history_rows = 8,
    }, .{ .width = initial_cell.width, .height = initial_cell.height });
    defer core.deinit();
    const projection = try Projection.create(allocator, &core.terminal, first, .{ .history_capacity = 8 });
    defer projection.destroy();
    try std.testing.expectEqual(@as(u32, 2), output.presentationStoreReferences(first));
    try std.testing.expectEqual(@as(u32, 1), output.presentationStoreReferences(next));
    try std.testing.expect((try core.terminal.feed("OLD")).stateChanged());
    try projection.prepare(0);
    const held = try projection.hold();
    var pinned: ?Frame = held;
    // zig-audit: acknowledge catch_unreachable
    // reason: The test always tracks the one exact live frame serial on this owner before teardown.
    defer if (pinned) |frame| projection.release(frame) catch unreachable;
    const glyphs = try allocator.dupe(output.commands.Command, held.snapshot.glyphs[0]);
    defer allocator.free(glyphs);
    const revision = core.terminal.semanticSequence();

    const invalid: state.SharedConfig = .{ .history_capacity = 8, .command_limit = std.math.maxInt(usize) };
    try std.testing.expectError(error.InvalidCommandLimit, projection.reconfigure(core, next, invalid, .current));
    try std.testing.expectEqual(@as(u32, 1), output.presentationStoreReferences(next));
    try std.testing.expectEqual(revision, core.terminal.semanticSequence());
    try std.testing.expectEqual(@as(u64, 1), projection.presentation_generation);

    const Failure = struct {
        calls: usize = 0,
        fn resizeGeometry(self: *@This(), _: u16, _: u16, _: vt.Terminal.CellPixelSize) pty_vt.ResizeError!void {
            self.calls += 1;
            return error.ResizeFailed;
        }
    };
    var failure: Failure = .{};
    const config: state.SharedConfig = .{ .history_capacity = 8 };
    try std.testing.expectError(error.ResizeFailed, projection.reconfigureWith(core, &failure, next, config, .{ .grid = .{ .rows = 3, .columns = 5 } }));
    try std.testing.expectEqual(@as(usize, 1), failure.calls);
    try std.testing.expectEqual(@as(u32, 1), output.presentationStoreReferences(next));
    try std.testing.expectEqual(@as(u32, 2), output.presentationStoreReferences(first));
    try std.testing.expectEqual(revision, core.terminal.semanticSequence());
    try std.testing.expectEqual(@as(u16, 2), core.terminal.semanticView(0).rows);
    try std.testing.expectEqual(@as(u32, initial_cell.width), core.terminal.cellPixelSize().?.width);
    try std.testing.expect(projection.direct.leased);
    try std.testing.expectEqualDeep(glyphs, held.snapshot.glyphs[0]);

    projection.presentation_generation = std.math.maxInt(u64);
    try std.testing.expectError(error.GenerationOverflow, projection.reconfigure(core, next, config, .current));
    projection.presentation_generation = 1;
    try std.testing.expectEqual(@as(u32, 1), output.presentationStoreReferences(next));
    try std.testing.expectError(error.InvalidDimensions, projection.reconfigure(core, next, config, .{ .surface = .{ .width = 0, .height = 100 } }));
    try std.testing.expectEqual(@as(u32, 1), output.presentationStoreReferences(next));

    const geometry = try projection.reconfigure(core, next, config, .{ .grid = .{ .rows = 3, .columns = 5 } });
    try std.testing.expectEqual(@as(u16, 3), geometry.rows);
    try std.testing.expectEqual(@as(u16, 5), geometry.columns);
    try std.testing.expectEqual(@as(u32, next_cell.width), geometry.cell_size.width);
    try std.testing.expectEqual(@as(u64, 2), projection.presentation_generation);
    try std.testing.expectEqual(@as(u16, 3), core.terminal.semanticView(0).rows);
    try std.testing.expectEqual(@as(u16, 5), core.terminal.semanticView(0).cols);
    try std.testing.expectEqual(@as(u32, 1), output.presentationStoreReferences(first));
    try std.testing.expectEqual(@as(u32, 2), output.presentationStoreReferences(next));
    try std.testing.expectEqualDeep(glyphs, held.snapshot.glyphs[0]);
    try projection.prepare(0);
    const fresh = try projection.replace(held);
    pinned = fresh;
    try std.testing.expectEqual(@as(u64, 2), fresh.presentation_generation);
    try std.testing.expectEqual(next_cell.width, fresh.snapshot.cell_width);
    try std.testing.expect(fresh.serial > held.serial);
    try std.testing.expectError(error.InvalidLease, projection.release(held));
    const unchanged = try projection.reconfigure(core, next, config, .{ .surface = .{
        .width = @intCast(@as(u32, next_cell.width) * 5),
        .height = @intCast(@as(u32, next_cell.height) * 3),
    } });
    try std.testing.expectEqual(@as(u16, 3), unchanged.rows);
    try std.testing.expectEqual(@as(u16, 5), unchanged.columns);
    try std.testing.expectEqual(@as(u64, 3), projection.presentation_generation);
}
