//! Owns the small Host adapter and physical terminal GPU batch.
//!
//! Renderer supplies globally folded Grid candidates and exact Composer
//! placements. This owner translates resolved cells, shares one glyph atlas
//! per exact font epoch, partitions one mapped staging allocation, and records
//! terminal work into the caller's one command buffer and render pass.

const std = @import("std");
const render = @import("howl_render");
const howl_vk = @import("howl_vk");
const vk = howl_vk.abi;
const backend = howl_vk.terminal_cells;
const vk_surface = howl_vk.surface;
const fonts = @import("terminal_fonts");
const handoff = @import("terminal_handoff");

/// Maximum simultaneously borrowed pane descriptors in one physical batch.
pub const pane_limit: usize = 64;
/// Maximum admitted physical cells owned by one pane.
pub const pane_cell_limit: usize = 65_536;
/// Maximum admitted physical rows owned by one pane.
pub const pane_row_limit: usize = 128;
/// Exact aggregate cell admission across one bounded batch.
pub const aggregate_cell_limit: usize = pane_limit * pane_cell_limit;
/// Exact aggregate row admission across one bounded batch.
pub const aggregate_row_limit: usize = pane_limit * pane_row_limit;

/// Finite Host-adapter, font, terminal-cell, and raster failure set.
pub const Error = backend.Error || fonts.Error || render.text.GlyphWidthError ||
    render.text.RasterError || error{
    InvalidIdentity,
    InvalidGeometry,
    Capacity,
    CandidatePending,
    NoCandidate,
    ArithmeticOverflow,
    OutOfMemory,
};

/// Exact pane source and lifecycle epoch carried into physical ownership.
pub const Identity = extern struct {
    pane: u64,
    source: u64,
    lifecycle_revision: u64,
};

/// Borrows one pane owner and its existing Grid/Store candidate slices. It
/// owns offsets and qualified draw geometry, never cells or copy regions.
pub const BorrowedPaneCandidate = extern struct {
    identity: Identity,
    grid_update: ?*const render.terminal_cells.Update,
    pane: *Pane,
    font_candidate: ?*backend.FontGpu,
    instance_offset: usize,
    row_offset: usize,
    glyph_offset: usize,
    origin_x: i32,
    origin_y: i32,
    clip_x: i32,
    clip_y: i32,
    clip_width: u32,
    clip_height: u32,
    cell_width: u16,
    cell_height: u16,
    baseline: u16,
    flags: u16,
};

/// Owns only the bounded borrowed descriptor array for one frame attempt.
pub const TerminalBatch = extern struct {
    count: u8 = 0,
    _reserved: [7]u8 = @splat(0),
    candidates: [pane_limit]BorrowedPaneCandidate = undefined,
};

comptime {
    std.debug.assert(@sizeOf(BorrowedPaneCandidate) == 104);
    std.debug.assert(@sizeOf(TerminalBatch) == 6_664);
}

const candidate_flag: u16 = 1;
const visible_flag: u16 = 2;

/// Owns one exact pane Store and its persistent Vulkan resources.
pub const Pane = struct {
    identity: Identity,
    font: fonts.Ref,
    rows: u16,
    cols: u16,
    store: backend.Store,
    resources: backend.PaneResources,
    prepared: backend.Prepared = undefined,
    draw: backend.Draw = undefined,
    pending: bool = false,

    /// Releases persistent pane resources, Store state, and its font epoch.
    pub fn deinit(self: *Pane, owner: *Owner) void {
        self.resources.deinit(
            owner.device,
            owner.resources.descriptor_pool,
            owner.gpu_bytes,
        );
        self.store.deinit();
        owner.releaseFont(self.font);
        self.* = undefined;
    }
};

const FontOwner = struct {
    reference: fonts.Ref,
    references: u8,
    gpu: backend.FontGpu,
};

/// Supplies one already-prepared Grid candidate and its optional visible
/// placement in exact composition order.
pub const Input = struct {
    pane: *Pane,
    grid_update: ?*const render.terminal_cells.Update,
    placement: ?render.canvas.Composer.Placement,
    surface: Surface,
};

/// Pairs one logical compositor surface with its exact physical attachment.
pub const Surface = extern struct {
    logical_width: u32,
    logical_height: u32,
    physical_width: u32,
    physical_height: u32,
};

/// Stores one rectangle after exact logical-edge to physical-edge conversion.
pub const PhysicalRect = extern struct {
    x: u32,
    y: u32,
    width: u32,
    height: u32,
};

/// Stores one physical pane's admitted grid and trailing sub-cell remainder.
pub const GridGeometry = extern struct {
    rect: PhysicalRect,
    rows: u16,
    columns: u16,
    remainder_x: u16,
    remainder_y: u16,
};

comptime {
    std.debug.assert(@sizeOf(Surface) == 16);
    std.debug.assert(@alignOf(Surface) == 4);
    std.debug.assert(@sizeOf(PhysicalRect) == 16);
    std.debug.assert(@alignOf(PhysicalRect) == 4);
    std.debug.assert(@sizeOf(GridGeometry) == 24);
    std.debug.assert(@alignOf(GridGeometry) == 4);
}

const PhysicalPoint = extern struct { x: u32, y: u32 };

/// Owns the shared physical pipeline/staging, font epochs, and bounded adapter
/// scratch reused serially while constructing one TerminalBatch.
pub const Owner = struct {
    allocator: std.mem.Allocator,
    device: vk.VkDevice,
    memory: vk.VkPhysicalDeviceMemoryProperties,
    gpu_bytes: *u64,
    gpu_limit: u64,
    resources: backend.Resources,
    font_owners: [fonts.capacity]?FontOwner = @splat(null),
    cell_scratch: []backend.CellWriteInput,
    fill_scratch: []backend.Fill,
    row_scratch: []backend.RowRotation,
    slot_scratch: []u16,
    raster_scratch: []backend.GlyphRaster,
    tile_scratch: [][]u8,
    proof_staging: ?[]backend.Instance = null,
    batch: TerminalBatch = .{},
    batch_pending: bool = false,

    /// Creates the one physical terminal pipeline and bounded adapter storage.
    pub fn init(
        allocator: std.mem.Allocator,
        device: vk.VkDevice,
        memory: vk.VkPhysicalDeviceMemoryProperties,
        render_pass: vk.VkRenderPass,
        gpu_bytes: *u64,
        gpu_limit: u64,
    ) Error!Owner {
        var resources = try backend.Resources.init(
            device,
            memory,
            render_pass,
            gpu_bytes,
            gpu_limit,
        );
        errdefer resources.deinit(device, gpu_bytes);
        const cell_scratch = allocator.alloc(backend.CellWriteInput, pane_cell_limit) catch
            return error.OutOfMemory;
        errdefer allocator.free(cell_scratch);
        const fill_scratch = allocator.alloc(backend.Fill, pane_row_limit) catch
            return error.OutOfMemory;
        errdefer allocator.free(fill_scratch);
        const row_scratch = allocator.alloc(backend.RowRotation, pane_row_limit) catch
            return error.OutOfMemory;
        errdefer allocator.free(row_scratch);
        const slot_scratch = allocator.alloc(u16, backend.glyph_slots) catch
            return error.OutOfMemory;
        errdefer allocator.free(slot_scratch);
        const raster_scratch = allocator.alloc(backend.GlyphRaster, backend.glyph_slots) catch
            return error.OutOfMemory;
        errdefer allocator.free(raster_scratch);
        const tile_scratch = allocator.alloc([]u8, backend.glyph_slots) catch
            return error.OutOfMemory;
        return .{
            .allocator = allocator,
            .device = device,
            .memory = memory,
            .gpu_bytes = gpu_bytes,
            .gpu_limit = gpu_limit,
            .resources = resources,
            .cell_scratch = cell_scratch,
            .fill_scratch = fill_scratch,
            .row_scratch = row_scratch,
            .slot_scratch = slot_scratch,
            .raster_scratch = raster_scratch,
            .tile_scratch = tile_scratch,
        };
    }

    /// Constructs the same retained owner shape without Vulkan handles for
    /// deterministic owner proofs that never stage or record physical work.
    pub fn initProof(allocator: std.mem.Allocator, gpu_bytes: *u64) Error!Owner {
        const cell_scratch = allocator.alloc(backend.CellWriteInput, pane_cell_limit) catch
            return error.OutOfMemory;
        errdefer allocator.free(cell_scratch);
        const fill_scratch = allocator.alloc(backend.Fill, pane_row_limit) catch
            return error.OutOfMemory;
        errdefer allocator.free(fill_scratch);
        const row_scratch = allocator.alloc(backend.RowRotation, pane_row_limit) catch
            return error.OutOfMemory;
        errdefer allocator.free(row_scratch);
        const slot_scratch = allocator.alloc(u16, backend.glyph_slots) catch
            return error.OutOfMemory;
        errdefer allocator.free(slot_scratch);
        const raster_scratch = allocator.alloc(backend.GlyphRaster, backend.glyph_slots) catch
            return error.OutOfMemory;
        errdefer allocator.free(raster_scratch);
        const tile_scratch = allocator.alloc([]u8, backend.glyph_slots) catch
            return error.OutOfMemory;
        errdefer allocator.free(tile_scratch);
        const proof_staging = allocator.alloc(
            backend.Instance,
            backend.staging_byte_limit / @sizeOf(backend.Instance),
        ) catch return error.OutOfMemory;
        var resources = backend.Resources{};
        resources.mapped = @ptrCast(proof_staging.ptr);
        return .{
            .allocator = allocator,
            .device = null,
            .memory = std.mem.zeroes(vk.VkPhysicalDeviceMemoryProperties),
            .gpu_bytes = gpu_bytes,
            .gpu_limit = 0,
            .resources = resources,
            .cell_scratch = cell_scratch,
            .fill_scratch = fill_scratch,
            .row_scratch = row_scratch,
            .slot_scratch = slot_scratch,
            .raster_scratch = raster_scratch,
            .tile_scratch = tile_scratch,
            .proof_staging = proof_staging,
        };
    }

    /// Releases all terminal GPU and adapter ownership after GPU quiescence.
    pub fn deinit(self: *Owner) void {
        // A post-submit fatal exit deliberately leaves the exact terminal
        // candidates owned until GPU quiescence and enclosing pane teardown.
        // At that point destruction, rather than candidate rollback, is the
        // only valid release path.
        var index = self.font_owners.len;
        while (index != 0) {
            index -= 1;
            if (self.font_owners[index]) |*font| {
                std.debug.assert(font.references == 0);
                font.gpu.deinitPhysical(self.device, self.gpu_bytes);
                font.gpu.deinit();
            }
        }
        self.allocator.free(self.tile_scratch);
        self.allocator.free(self.raster_scratch);
        self.allocator.free(self.slot_scratch);
        self.allocator.free(self.row_scratch);
        self.allocator.free(self.fill_scratch);
        self.allocator.free(self.cell_scratch);
        if (self.proof_staging) |staging| {
            self.resources.mapped = null;
            self.allocator.free(staging);
        }
        self.resources.deinit(self.device, self.gpu_bytes);
        self.* = undefined;
    }

    /// Constructs exact-grid CPU/GPU owners after aggregate admission.
    pub fn createPane(
        self: *Owner,
        font_cache: *fonts.Cache,
        identity: Identity,
        font: fonts.Ref,
        rows: u16,
        cols: u16,
        first_replacement: backend.ReplacementKind,
    ) Error!Pane {
        if (self.device == null) return self.createPaneProof(
            font_cache,
            identity,
            font,
            rows,
            cols,
            first_replacement,
        );
        if (identity.pane == 0 or identity.source == 0 or
            identity.lifecycle_revision == 0)
            return error.InvalidIdentity;
        const limits = try exactLimits(rows, cols);
        const font_gpu = try self.acquireFont(font_cache, font);
        errdefer self.releaseFont(font);
        var store = try backend.Store.init(self.allocator, limits, first_replacement);
        errdefer store.deinit();
        const resources = try self.resources.createPane(
            self.device,
            self.memory,
            limits,
            font_gpu,
            self.gpu_bytes,
            self.gpu_limit,
        );
        return .{
            .identity = identity,
            .font = font,
            .rows = rows,
            .cols = cols,
            .store = store,
            .resources = resources,
        };
    }

    /// Constructs exact Store/FontGpu proof ownership without Vulkan handles.
    pub fn createPaneProof(
        self: *Owner,
        font_cache: *fonts.Cache,
        identity: Identity,
        font: fonts.Ref,
        rows: u16,
        cols: u16,
        first_replacement: backend.ReplacementKind,
    ) Error!Pane {
        if (self.device != null or identity.pane == 0 or identity.source == 0 or
            identity.lifecycle_revision == 0)
            return error.InvalidIdentity;
        const limits = try exactLimits(rows, cols);
        const index: usize = font.slot;
        if (index >= self.font_owners.len) return error.InvalidIdentity;
        if (self.font_owners[index]) |*owner| {
            if (!std.meta.eql(owner.reference, font)) return error.InvalidIdentity;
            owner.references = std.math.add(u8, owner.references, 1) catch
                return error.Capacity;
        } else {
            const metrics = try font_cache.metrics(font);
            self.font_owners[index] = .{
                .reference = font,
                .references = 1,
                .gpu = try backend.FontGpu.init(self.allocator, .{
                    .glyph_width = metrics.advance_width,
                    .glyph_height = metrics.line_height,
                }),
            };
        }
        errdefer self.releaseFont(font);
        return .{
            .identity = identity,
            .font = font,
            .rows = rows,
            .cols = cols,
            .store = try backend.Store.init(self.allocator, limits, first_replacement),
            .resources = .{},
        };
    }

    /// Prepares one bounded descriptor array. Inputs are already ordered with
    /// visible panes in Composer order and changed invisible panes afterward.
    pub fn prepare(
        self: *Owner,
        font_cache: *fonts.Cache,
        inputs: []const Input,
    ) Error!*const TerminalBatch {
        if (self.batch_pending) return error.CandidatePending;
        if (inputs.len > pane_limit) return error.Capacity;
        self.batch.count = 0;
        var prepared_fonts: [fonts.capacity]*backend.FontGpu = undefined;
        var prepared_font_count: usize = 0;
        var prepared_panes: [pane_limit]*Pane = undefined;
        var prepared_pane_count: usize = 0;
        errdefer {
            var font_index = prepared_font_count;
            while (font_index != 0) {
                font_index -= 1;
                prepared_fonts[font_index].discard() catch
                    @panic("terminal font candidate vanished");
            }
            var pane_index = prepared_pane_count;
            while (pane_index != 0) {
                pane_index -= 1;
                const pane = prepared_panes[pane_index];
                pane.store.discard() catch @panic("terminal Store candidate vanished");
                pane.pending = false;
            }
            self.batch.count = 0;
        }

        var instance_offset: usize = 0;
        var row_offset: usize = 0;
        for (inputs, 0..) |input, index| {
            try validateInput(inputs[0..index], input);
            const instance_bytes = if (input.grid_update) |update|
                try updateInstanceBytes(update)
            else
                0;
            const row_bytes = if (input.grid_update) |update|
                try updateRowBytes(update)
            else
                0;
            self.batch.candidates[index] = try descriptor(
                input,
                instance_offset,
                row_offset,
            );
            instance_offset = std.math.add(usize, instance_offset, instance_bytes) catch
                return error.ArithmeticOverflow;
            row_offset = std.math.add(usize, row_offset, row_bytes) catch
                return error.ArithmeticOverflow;
            if (instance_offset > aggregate_cell_limit * @sizeOf(backend.Instance) or
                row_offset > aggregate_row_limit * @sizeOf(u32))
                return error.Capacity;
        }

        for (inputs, 0..) |input, index| {
            if (input.grid_update == null) continue;
            const font_gpu = try self.fontFor(input.pane.font);
            var already_prepared = false;
            for (prepared_fonts[0..prepared_font_count]) |prior| {
                if (prior == font_gpu) already_prepared = true;
            }
            if (!already_prepared) {
                try self.prepareFont(font_cache, inputs, input.pane.font, font_gpu);
                prepared_fonts[prepared_font_count] = font_gpu;
                prepared_font_count += 1;
            }
            self.batch.candidates[index].font_candidate = font_gpu;
        }

        for (inputs, 0..) |input, index| {
            const pane = input.pane;
            if (input.grid_update) |update| {
                pane.prepared = try self.preparePane(
                    pane,
                    update,
                    .{
                        .instances = self.batch.candidates[index].instance_offset,
                        .rows = self.batch.candidates[index].row_offset,
                    },
                );
                pane.pending = true;
                prepared_panes[prepared_pane_count] = pane;
                prepared_pane_count += 1;
                self.batch.candidates[index].flags |= candidate_flag;
            }
            pane.draw = try qualifiedDraw(
                &pane.store,
                input,
                self.batch.candidates[index],
                try font_cache.metrics(pane.font),
            );
        }
        self.batch.count = @intCast(inputs.len);
        self.batch_pending = true;
        return &self.batch;
    }

    /// Copies every font and Store candidate into its exact mapped partition.
    pub fn stage(self: *Owner) Error!void {
        if (!self.batch_pending) return error.NoCandidate;
        for (self.batch.candidates[0..self.batch.count], 0..) |candidate, index| {
            if (candidate.font_candidate) |font| {
                var first = true;
                for (self.batch.candidates[0..index]) |prior| {
                    if (prior.font_candidate == font) first = false;
                }
                if (first) try font.stagePhysical();
            }
        }
        for (self.batch.candidates[0..self.batch.count]) |candidate| {
            if (candidate.flags & candidate_flag == 0) continue;
            try self.resources.stagePane(&candidate.pane.store, .{
                .instances = candidate.instance_offset,
                .rows = candidate.row_offset,
            });
        }
    }

    /// Records every terminal atlas/buffer transfer before the render pass.
    pub fn recordTransfers(self: *Owner, command: vk.VkCommandBuffer) Error!void {
        if (!self.batch_pending) return error.NoCandidate;
        for (self.batch.candidates[0..self.batch.count], 0..) |candidate, index| {
            if (candidate.font_candidate) |font| {
                var first = true;
                for (self.batch.candidates[0..index]) |prior| {
                    if (prior.font_candidate == font) first = false;
                }
                if (first) try font.recordTransfers(command);
            }
        }
        for (self.batch.candidates[0..self.batch.count]) |candidate| {
            if (candidate.flags & candidate_flag == 0) continue;
            const bindings = try self.resources.bindings(
                &candidate.pane.resources,
                try self.fontFor(candidate.pane.font),
            );
            try candidate.pane.store.recordTransfers(command, bindings, .{
                .instances = candidate.instance_offset,
                .rows = candidate.row_offset,
            });
        }
    }

    /// Records visible panes in the descriptor's accepted composition order.
    pub fn recordDraws(
        self: *Owner,
        command: vk.VkCommandBuffer,
        target: backend.DrawTarget,
    ) Error!void {
        if (!self.batch_pending) return error.NoCandidate;
        for (self.batch.candidates[0..self.batch.count]) |candidate| {
            if (candidate.flags & visible_flag == 0) continue;
            const font = try self.fontFor(candidate.pane.font);
            const bindings = try self.resources.bindings(
                &candidate.pane.resources,
                font,
            );
            try candidate.pane.store.recordDraw(
                command,
                bindings,
                candidate.pane.draw,
                target,
            );
        }
    }

    /// Accepts shared fonts first and then pane Stores after GPU completion.
    pub fn complete(self: *Owner) Error!void {
        if (!self.batch_pending) return error.NoCandidate;
        for (self.batch.candidates[0..self.batch.count]) |candidate| {
            if (candidate.font_candidate) |font|
                if (!font.completionReady()) return error.NoCandidate;
            if (candidate.flags & candidate_flag != 0 and
                (!candidate.pane.pending or !candidate.pane.store.candidatePending()))
                return error.NoCandidate;
        }
        for (self.batch.candidates[0..self.batch.count], 0..) |candidate, index| {
            if (candidate.font_candidate) |font| {
                var first = true;
                for (self.batch.candidates[0..index]) |prior| {
                    if (prior.font_candidate == font) first = false;
                }
                if (first) try font.complete();
            }
        }
        for (self.batch.candidates[0..self.batch.count]) |candidate| {
            if (candidate.flags & candidate_flag == 0) continue;
            try candidate.pane.store.complete();
            candidate.pane.pending = false;
        }
        self.batch_pending = false;
        self.batch.count = 0;
    }

    /// Rejects shared fonts and pane Stores in exact reverse preparation order.
    pub fn discard(self: *Owner) Error!void {
        if (!self.batch_pending) return error.NoCandidate;
        var index: usize = self.batch.count;
        while (index != 0) {
            index -= 1;
            const candidate = self.batch.candidates[index];
            if (candidate.font_candidate) |font| {
                var later = false;
                for (self.batch.candidates[index + 1 .. self.batch.count]) |following| {
                    if (following.font_candidate == font) later = true;
                }
                if (!later) try font.discard();
            }
        }
        index = self.batch.count;
        while (index != 0) {
            index -= 1;
            const candidate = self.batch.candidates[index];
            if (candidate.flags & candidate_flag == 0) continue;
            try candidate.pane.store.discard();
            candidate.pane.pending = false;
        }
        self.batch_pending = false;
        self.batch.count = 0;
    }

    /// Returns the number of Stores carrying a candidate in the active batch.
    pub fn candidateCount(self: *const Owner) usize {
        var result: usize = 0;
        for (self.batch.candidates[0..self.batch.count]) |candidate|
            result += @intFromBool(candidate.flags & candidate_flag != 0);
        return result;
    }

    fn acquireFont(
        self: *Owner,
        font_cache: *fonts.Cache,
        reference: fonts.Ref,
    ) Error!*backend.FontGpu {
        const index: usize = reference.slot;
        if (index >= self.font_owners.len) return error.InvalidIdentity;
        if (self.font_owners[index]) |*owner| {
            if (!std.meta.eql(owner.reference, reference)) return error.InvalidIdentity;
            owner.references = std.math.add(u8, owner.references, 1) catch
                return error.Capacity;
            return &owner.gpu;
        }
        const metrics = try font_cache.metrics(reference);
        var gpu = try backend.FontGpu.init(self.allocator, .{
            .glyph_width = metrics.advance_width,
            .glyph_height = metrics.line_height,
        });
        errdefer gpu.deinit();
        try gpu.initPhysical(
            self.device,
            self.memory,
            self.gpu_bytes,
            self.gpu_limit,
        );
        self.font_owners[index] = .{
            .reference = reference,
            .references = 1,
            .gpu = gpu,
        };
        return &self.font_owners[index].?.gpu;
    }

    fn releaseFont(self: *Owner, reference: fonts.Ref) void {
        const index: usize = reference.slot;
        const owner = &(self.font_owners[index] orelse
            @panic("terminal GPU font reference vanished"));
        if (!std.meta.eql(owner.reference, reference) or owner.references == 0)
            @panic("terminal GPU font identity became stale");
        owner.references -= 1;
        if (owner.references == 0) {
            owner.gpu.deinitPhysical(self.device, self.gpu_bytes);
            owner.gpu.deinit();
            self.font_owners[index] = null;
        }
    }

    fn fontFor(self: *Owner, reference: fonts.Ref) Error!*backend.FontGpu {
        const index: usize = reference.slot;
        if (index >= self.font_owners.len or self.font_owners[index] == null or
            !std.meta.eql(self.font_owners[index].?.reference, reference))
            return error.InvalidIdentity;
        return &self.font_owners[index].?.gpu;
    }

    fn prepareFont(
        self: *Owner,
        font_cache: *fonts.Cache,
        inputs: []const Input,
        reference: fonts.Ref,
        font_gpu: *backend.FontGpu,
    ) Error!void {
        var slot_count: usize = 0;
        for (inputs) |input| {
            if (!std.meta.eql(input.pane.font, reference)) continue;
            const update = input.grid_update orelse continue;
            for (update.glyphs) |key| {
                const slot = try glyphSlot(key);
                var seen = false;
                for (self.slot_scratch[0..slot_count]) |prior| {
                    if (prior == slot) seen = true;
                }
                if (!seen) {
                    self.slot_scratch[slot_count] = slot;
                    slot_count += 1;
                }
            }
        }
        var raster_count: usize = 0;
        errdefer freeTiles(self, raster_count);
        const metrics = try font_cache.metrics(reference);
        const font = try font_cache.borrow(reference);
        for (self.slot_scratch[0..slot_count]) |slot| {
            if (font_gpu.available(slot)) continue;
            const key = glyphKeyForSlot(slot);
            const tile_bytes = std.math.mul(usize, metrics.advance_width, metrics.line_height) catch
                return error.ArithmeticOverflow;
            const tile = self.allocator.alloc(u8, tile_bytes) catch
                return error.OutOfMemory;
            self.tile_scratch[raster_count] = tile;
            raster_count += 1;
            @memset(tile, 0);
            const glyph = try font.glyphForCodepoint(0, key.codepoint);
            var raster = try font.rasterize(
                self.allocator,
                0,
                glyph,
                metrics.advance_width,
            );
            defer raster.deinit();
            placeStyledRaster(tile, metrics, raster, key.bold, key.italic);
            self.raster_scratch[raster_count - 1] = .{
                .slot = slot,
                .width = metrics.advance_width,
                .height = metrics.line_height,
                .stride = metrics.advance_width,
                .pixels = tile,
            };
        }
        try font_gpu.prepare(
            self.slot_scratch[0..slot_count],
            self.raster_scratch[0..raster_count],
        );
        freeTiles(self, raster_count);
    }

    fn preparePane(
        self: *Owner,
        pane: *Pane,
        update: *const render.terminal_cells.Update,
        offsets: backend.StagingOffsets,
    ) Error!backend.Prepared {
        if (pane.pending) return error.CandidatePending;
        const expected_instances = try updateInstanceBytes(update);
        const expected_rows = try updateRowBytes(update);
        const mapped = try self.resources.mappedPane(
            offsets,
            expected_instances,
            expected_rows,
        );
        var replacement: ?backend.Replacement = null;
        if (update.replacement) |value| {
            const instances = std.mem.bytesAsSlice(
                backend.Instance,
                @as([]align(@alignOf(backend.Instance)) u8, @alignCast(mapped.instances)),
            );
            if (instances.len != value.cells.len) return error.InvalidGeometry;
            for (value.cells, instances) |cell, *instance|
                instance.* = try instanceForCell(cell);
            replacement = .{
                .kind = replacementKind(value.kind),
                .rows = value.rows,
                .cols = value.cols,
                .instances = instances,
            };
        }
        if (update.row_rotations.len > self.row_scratch.len or
            update.fills.len > self.fill_scratch.len or
            update.cells.len > self.cell_scratch.len or
            update.glyphs.len > self.slot_scratch.len)
            return error.Capacity;
        for (update.row_rotations, self.row_scratch[0..update.row_rotations.len]) |source, *destination|
            destination.* = .{
                .first = source.first,
                .count = source.count,
                .shift = source.shift,
            };
        for (update.fills, self.fill_scratch[0..update.fills.len]) |source, *destination|
            destination.* = .{
                .first = source.first,
                .count = source.count,
                .instance = try instanceForCell(source.cell),
            };
        for (update.cells, self.cell_scratch[0..update.cells.len]) |source, *destination|
            destination.* = .{
                .physical_index = source.physical_index,
                .instance = try instanceForCell(source.cell),
            };
        for (update.glyphs, self.slot_scratch[0..update.glyphs.len]) |key, *slot|
            slot.* = try glyphSlot(key);
        const prepared = try pane.store.prepare(.{
            .rows = update.rows,
            .cols = update.cols,
            .replacement = replacement,
            .row_rotations = self.row_scratch[0..update.row_rotations.len],
            .fills = self.fill_scratch[0..update.fills.len],
            .cells = self.cell_scratch[0..update.cells.len],
            .glyph_slots = self.slot_scratch[0..update.glyphs.len],
            .cursor = if (update.cursor) |cursor| cursorDraw(cursor) else null,
        }, try self.fontFor(pane.font));
        if (prepared.instance_staging_bytes != expected_instances or
            std.mem.sliceAsBytes(prepared.row_map).len != expected_rows)
            return error.InvalidGeometry;
        return prepared;
    }
};

/// Admits one exact batch aggregate without widening pane or staging capacity.
pub fn checkedAggregate(
    cells: []const usize,
    rows: []const usize,
) Error!struct { cells: usize, rows: usize } {
    if (cells.len != rows.len or cells.len > pane_limit) return error.InvalidGeometry;
    var cell_total: usize = 0;
    var row_total: usize = 0;
    for (cells, rows) |pane_cells, pane_rows| {
        if (pane_cells == 0 or pane_cells > pane_cell_limit or
            pane_rows == 0 or pane_rows > pane_row_limit)
            return error.InvalidGeometry;
        cell_total = std.math.add(usize, cell_total, pane_cells) catch
            return error.ArithmeticOverflow;
        row_total = std.math.add(usize, row_total, pane_rows) catch
            return error.ArithmeticOverflow;
    }
    if (cell_total > aggregate_cell_limit or row_total > aggregate_row_limit)
        return error.Capacity;
    return .{ .cells = cell_total, .rows = row_total };
}

/// Converts every logical rectangle edge through the exact attachment ratio.
pub fn physicalRect(rect: render.canvas.Rect, surface: Surface) Error!PhysicalRect {
    if (surface.logical_width == 0 or surface.logical_height == 0 or
        surface.physical_width == 0 or surface.physical_height == 0 or
        rect.x < 0 or rect.y < 0 or rect.width == 0 or rect.height == 0)
        return error.InvalidGeometry;
    const left: u64 = @intCast(rect.x);
    const top: u64 = @intCast(rect.y);
    const right = std.math.add(u64, left, rect.width) catch
        return error.ArithmeticOverflow;
    const bottom = std.math.add(u64, top, rect.height) catch
        return error.ArithmeticOverflow;
    if (right > surface.logical_width or bottom > surface.logical_height)
        return error.InvalidGeometry;
    const physical_left = physicalBoundary(
        left,
        surface.physical_width,
        surface.logical_width,
    );
    const physical_top = physicalBoundary(
        top,
        surface.physical_height,
        surface.logical_height,
    );
    const physical_right = physicalBoundary(
        right,
        surface.physical_width,
        surface.logical_width,
    );
    const physical_bottom = physicalBoundary(
        bottom,
        surface.physical_height,
        surface.logical_height,
    );
    if (physical_right <= physical_left or physical_bottom <= physical_top)
        return error.InvalidGeometry;
    return .{
        .x = @intCast(physical_left),
        .y = @intCast(physical_top),
        .width = @intCast(physical_right - physical_left),
        .height = @intCast(physical_bottom - physical_top),
    };
}

fn physicalPoint(point: render.canvas.Composer.Point, surface: Surface) Error!PhysicalPoint {
    if (surface.logical_width == 0 or surface.logical_height == 0 or
        surface.physical_width == 0 or surface.physical_height == 0 or
        point.x < 0 or point.y < 0 or
        @as(u64, @intCast(point.x)) > surface.logical_width or
        @as(u64, @intCast(point.y)) > surface.logical_height)
        return error.InvalidGeometry;
    return .{
        .x = @intCast(physicalBoundary(
            @intCast(point.x),
            surface.physical_width,
            surface.logical_width,
        )),
        .y = @intCast(physicalBoundary(
            @intCast(point.y),
            surface.physical_height,
            surface.logical_height,
        )),
    };
}

/// Derives one exact physical cell grid and proves its bounded pane remainder.
pub fn gridGeometry(
    rect: PhysicalRect,
    metrics: render.text.Metrics,
) Error!GridGeometry {
    if (rect.width == 0 or rect.height == 0 or metrics.advance_width == 0 or
        metrics.line_height == 0)
        return error.InvalidGeometry;
    const rows_u32 = rect.height / metrics.line_height;
    const columns_u32 = rect.width / metrics.advance_width;
    if (rows_u32 == 0 or rows_u32 > pane_row_limit or columns_u32 == 0 or
        columns_u32 > std.math.maxInt(u16))
        return error.InvalidGeometry;
    const cells = std.math.mul(u32, rows_u32, columns_u32) catch
        return error.ArithmeticOverflow;
    if (cells > pane_cell_limit) return error.InvalidGeometry;
    const grid_width = std.math.mul(u32, columns_u32, metrics.advance_width) catch
        return error.ArithmeticOverflow;
    const grid_height = std.math.mul(u32, rows_u32, metrics.line_height) catch
        return error.ArithmeticOverflow;
    const remainder_x = rect.width - grid_width;
    const remainder_y = rect.height - grid_height;
    if (grid_width > rect.width or grid_height > rect.height or
        remainder_x >= metrics.advance_width or remainder_y >= metrics.line_height)
        return error.InvalidGeometry;
    return .{
        .rect = rect,
        .rows = @intCast(rows_u32),
        .columns = @intCast(columns_u32),
        .remainder_x = @intCast(remainder_x),
        .remainder_y = @intCast(remainder_y),
    };
}

fn physicalBoundary(value: u64, destination: u32, source: u32) u64 {
    return value * destination / source;
}

fn exactLimits(rows: u16, cols: u16) Error!backend.Limits {
    const cells = std.math.mul(usize, rows, cols) catch
        return error.ArithmeticOverflow;
    if (rows == 0 or rows > pane_row_limit or cols == 0 or cells > pane_cell_limit)
        return error.InvalidGeometry;
    return .{
        .rows = rows,
        .cols = cols,
        .sparse_cell_updates = cells,
        .structured_updates = rows,
    };
}

fn validateInput(prior: []const Input, input: Input) Error!void {
    if (input.surface.logical_width == 0 or input.surface.logical_height == 0 or
        input.surface.physical_width == 0 or input.surface.physical_height == 0 or
        input.pane.identity.pane == 0 or input.pane.identity.source == 0 or
        input.pane.identity.lifecycle_revision == 0)
        return error.InvalidIdentity;
    for (prior) |value|
        if (value.pane == input.pane or
            value.pane.identity.pane == input.pane.identity.pane)
            return error.InvalidIdentity;
    if (input.grid_update) |update| {
        if (update.rows != input.pane.rows or update.cols != input.pane.cols)
            return error.InvalidGeometry;
    }
    if (input.placement) |placement| {
        if (@backingInt(placement.source) != input.pane.identity.source)
            return error.InvalidIdentity;
        _ = try physicalRect(placement.clip, input.surface);
    }
}

fn descriptor(input: Input, instance_offset: usize, row_offset: usize) Error!BorrowedPaneCandidate {
    var result = BorrowedPaneCandidate{
        .identity = input.pane.identity,
        .grid_update = input.grid_update,
        .pane = input.pane,
        .font_candidate = null,
        .instance_offset = instance_offset,
        .row_offset = row_offset,
        .glyph_offset = 0,
        .origin_x = 0,
        .origin_y = 0,
        .clip_x = 0,
        .clip_y = 0,
        .clip_width = 0,
        .clip_height = 0,
        .cell_width = 0,
        .cell_height = 0,
        .baseline = 0,
        .flags = 0,
    };
    if (input.placement) |placement| {
        const clip = try physicalRect(placement.clip, input.surface);
        const origin = try physicalPoint(placement.origin, input.surface);
        result.origin_x = @intCast(origin.x);
        result.origin_y = @intCast(origin.y);
        result.clip_x = @intCast(clip.x);
        result.clip_y = @intCast(clip.y);
        result.clip_width = clip.width;
        result.clip_height = clip.height;
        result.flags |= visible_flag;
    }
    return result;
}

fn updateInstanceBytes(update: *const render.terminal_cells.Update) Error!usize {
    var instances: usize = if (update.replacement) |replacement|
        replacement.cells.len
    else
        update.cells.len;
    if (update.replacement == null) {
        for (update.fills) |fill| {
            instances = std.math.add(usize, instances, fill.count) catch
                return error.ArithmeticOverflow;
        }
    }
    return std.math.mul(usize, instances, @sizeOf(backend.Instance)) catch
        return error.ArithmeticOverflow;
}

fn updateRowBytes(update: *const render.terminal_cells.Update) Error!usize {
    if (update.replacement == null and update.row_rotations.len == 0) return 0;
    return std.math.mul(usize, update.rows, @sizeOf(u32)) catch
        return error.ArithmeticOverflow;
}

fn qualifiedDraw(
    store: *const backend.Store,
    input: Input,
    candidate: BorrowedPaneCandidate,
    metrics: render.text.Metrics,
) Error!backend.Draw {
    var draw = try store.currentDraw();
    draw.cell_width = metrics.advance_width;
    draw.cell_height = metrics.line_height;
    draw.baseline = metrics.baseline;
    draw.underline_y = metrics.underline_y;
    draw.underline_height = metrics.underline_height;
    draw.strike_y = metrics.strike_y;
    draw.strike_height = metrics.strike_height;
    if (input.placement != null) {
        draw.origin_x = candidate.origin_x;
        draw.origin_y = candidate.origin_y;
        draw.clip_x = candidate.clip_x;
        draw.clip_y = candidate.clip_y;
        draw.clip_width = candidate.clip_width;
        draw.clip_height = candidate.clip_height;
    }
    return draw;
}

fn instanceForCell(cell: render.terminal_cells.Cell) Error!backend.Instance {
    if (cell.style.reserved != 0) return error.InvalidIdentity;
    return .{
        .glyph_slot = if (cell.codepoint == 0)
            backend.blank_glyph
        else
            try backend.stableGlyphSlot(
                cell.codepoint,
                cell.style.bold,
                cell.style.italic,
            ),
        .flags = .{
            .bold = cell.style.bold,
            .dim = cell.style.dim,
            .italic = cell.style.italic,
            .underline = cell.style.underline,
            .strikethrough = cell.style.strikethrough,
        },
        .foreground = packedColor(cell.foreground),
        .background = packedColor(cell.background),
        .underline_color = packedColor(cell.underline_color),
    };
}

fn packedColor(color: render.terminal_cells.Rgb) u32 {
    return @as(u32, color.r) |
        (@as(u32, color.g) << 8) |
        (@as(u32, color.b) << 16) |
        (@as(u32, 0xff) << 24);
}

fn glyphSlot(key: render.terminal_cells.GlyphKey) Error!u16 {
    if (key.reserved != 0 or key.codepoint < 0x20 or key.codepoint > 0x7e)
        return error.InvalidIdentity;
    return backend.stableGlyphSlot(key.codepoint, key.bold, key.italic);
}

fn glyphKeyForSlot(slot: u16) render.terminal_cells.GlyphKey {
    const style = slot / 95;
    return .{
        .codepoint = @intCast(0x20 + slot % 95),
        .bold = style & 1 != 0,
        .italic = style & 2 != 0,
    };
}

fn cursorDraw(cursor: render.terminal_cells.Cursor) backend.CursorDraw {
    if (!cursor.visible or cursor.shape == .hidden) return .{};
    return .{
        .row = cursor.row,
        .col = cursor.col,
        .color = packedColor(cursor.color),
        .text_color = packedColor(cursor.text_color),
        .shape = switch (cursor.shape) {
            .block => .block,
            .underline => .underline,
            .bar => .bar,
            .hidden => unreachable,
        },
        .visible = cursor.visible,
    };
}

fn replacementKind(kind: render.terminal_cells.ReplacementKind) backend.ReplacementKind {
    return switch (kind) {
        .initialization => .initialization,
        .resize => .resize,
        .alternate_grid => .alternate_grid,
    };
}

fn placeStyledRaster(
    tile: []u8,
    metrics: render.text.Metrics,
    raster: render.text.Raster,
    bold: bool,
    italic: bool,
) void {
    const top = @as(i32, metrics.baseline) - raster.top;
    for (0..raster.height) |source_y| {
        const destination_y = top + @as(i32, @intCast(source_y));
        if (destination_y < 0 or destination_y >= metrics.line_height) continue;
        for (0..raster.width) |source_x| {
            const shift: i32 = if (italic)
                @intCast(italicShift(metrics, @intCast(destination_y)))
            else
                0;
            const destination_x = @as(i32, raster.left) +
                @as(i32, @intCast(source_x)) + shift;
            const coverage = raster.pixels[source_y * raster.width + source_x];
            writeCoverage(tile, metrics, destination_x, destination_y, coverage);
            if (bold)
                writeCoverage(tile, metrics, destination_x + 1, destination_y, coverage);
        }
    }
}

fn italicShift(metrics: render.text.Metrics, destination_y: u16) u16 {
    if (destination_y >= metrics.baseline) return 0;
    const distance = metrics.baseline - destination_y;
    const rounded = distance / 4 + @intFromBool(distance % 4 != 0);
    return @min(@as(u16, 2), rounded);
}

fn writeCoverage(
    tile: []u8,
    metrics: render.text.Metrics,
    destination_x: i32,
    destination_y: i32,
    coverage: u8,
) void {
    if (destination_x < 0 or destination_x >= metrics.advance_width or
        destination_y < 0 or destination_y >= metrics.line_height)
        return;
    const index = @as(usize, @intCast(destination_y)) * metrics.advance_width +
        @as(usize, @intCast(destination_x));
    tile[index] = @max(tile[index], coverage);
}

fn freeTiles(owner: *Owner, count: usize) void {
    var index = count;
    while (index != 0) {
        index -= 1;
        owner.allocator.free(owner.tile_scratch[index]);
    }
}

const ProofFixture = struct {
    fonts: fonts.Cache,
    gpu_bytes: u64,
    owner: Owner,
    font: fonts.Ref,
    grid: render.terminal_cells.Grid,
    pane: Pane,

    fn init(self: *ProofFixture, rows: u16, cols: u16) !void {
        self.fonts = try fonts.Cache.init(
            std.testing.allocator,
            "../howl-render/testdata/primary.ttf",
        );
        errdefer self.fonts.deinit();
        self.font = try self.fonts.acquire(try fonts.Cache.keyFor(
            try fonts.Policy.init(6.0),
            .{
                .revision = 1,
                .dpi_x = .{ .numerator = 96, .denominator = 1 },
                .dpi_y = .{ .numerator = 96, .denominator = 1 },
            },
            @fromBackingInt(1),
        ));
        errdefer self.fonts.release(self.font) catch unreachable;
        self.gpu_bytes = 0;
        self.owner = try Owner.initProof(std.testing.allocator, &self.gpu_bytes);
        errdefer self.owner.deinit();
        self.pane = try self.owner.createPaneProof(
            &self.fonts,
            .{ .pane = 1, .source = 2, .lifecycle_revision = 3 },
            self.font,
            rows,
            cols,
            .initialization,
        );
        errdefer self.pane.deinit(&self.owner);
        self.grid = try render.terminal_cells.Grid.init(
            std.testing.allocator,
            .{
                .rows = rows,
                .cols = cols,
                .structured_operations = rows,
                .sparse_cell_updates = @as(usize, rows) * cols,
            },
            rows,
            cols,
            render.terminal_cells.Cell.blank(
                .{ .r = 0xd8, .g = 0xde, .b = 0xe9 },
                .{ .r = 0x2e, .g = 0x34, .b = 0x40 },
            ),
        );
        errdefer self.grid.deinit();
        const initial = (try self.grid.prepare()).?;
        _ = try self.owner.prepare(&self.fonts, &.{.{
            .pane = &self.pane,
            .grid_update = &initial,
            .placement = null,
            .surface = .{
                .logical_width = cols,
                .logical_height = rows,
                .physical_width = cols,
                .physical_height = rows,
            },
        }});
        errdefer if (self.owner.batch_pending)
            self.owner.discard() catch unreachable;
        try self.owner.complete();
        try self.grid.complete();
    }

    fn deinit(self: *ProofFixture) void {
        self.pane.deinit(&self.owner);
        self.grid.deinit();
        self.owner.deinit();
        self.fonts.release(self.font) catch
            @panic("terminal proof font reference vanished");
        self.fonts.deinit();
        self.* = undefined;
    }

    fn prepare(self: *ProofFixture) !void {
        const update = (try self.grid.prepare()).?;
        _ = try self.owner.prepare(&self.fonts, &.{.{
            .pane = &self.pane,
            .grid_update = &update,
            .placement = null,
            .surface = .{
                .logical_width = self.pane.cols,
                .logical_height = self.pane.rows,
                .physical_width = self.pane.cols,
                .physical_height = self.pane.rows,
            },
        }});
    }

    fn complete(self: *ProofFixture) !void {
        try self.owner.complete();
        try self.grid.complete();
    }
};

test "T003 sparse ASCII conversion preserves slot colors and physical index" {
    var fixture: ProofFixture = undefined;
    try fixture.init(2, 4);
    defer fixture.deinit();
    const cell = render.terminal_cells.Cell.init(
        'A',
        .{ .r = 1, .g = 2, .b = 3 },
        .{ .r = 4, .g = 5, .b = 6 },
        .{ .r = 7, .g = 8, .b = 9 },
        .{},
    );
    const instance = try instanceForCell(cell);
    try std.testing.expectEqual(try backend.stableGlyphSlot('A', false, false), instance.glyph_slot);
    try std.testing.expectEqual(@as(u32, 0xff030201), instance.foreground);
    try std.testing.expectEqual(@as(u32, 0xff060504), instance.background);
    try std.testing.expectEqual(@as(u32, 0xff090807), instance.underline_color);
    try fixture.grid.set(1, 3, cell);
    try fixture.prepare();
    try std.testing.expectEqual(@as(usize, 1), fixture.pane.prepared.instance_copies.len);
    try std.testing.expectEqual(
        @as(u64, 7 * @sizeOf(backend.Instance)),
        fixture.pane.prepared.instance_copies[0].dstOffset,
    );
    try std.testing.expectEqual(backend.blank_glyph, (try fixture.pane.store.accepted(7)).glyph_slot);
    try fixture.complete();
    try std.testing.expectEqualDeep(instance, try fixture.pane.store.accepted(7));
}

test "styled raster treatment has exact bytes clipping and no tile bleed" {
    const metrics = render.text.Metrics{
        .advance_width = 5,
        .line_height = 4,
        .baseline = 3,
        .underline_y = 3,
        .underline_height = 1,
        .strike_y = 1,
        .strike_height = 1,
    };
    var pixels = [_]u8{ 0x10, 0x20, 0x30, 0x40 };
    const raster = render.text.Raster{
        .allocator = std.testing.allocator,
        .width = 2,
        .height = 2,
        .left = 0,
        .top = 3,
        .pixels = &pixels,
    };
    var regular: [20]u8 = @splat(0);
    var bold: [20]u8 = @splat(0);
    var italic: [20]u8 = @splat(0);
    var bold_italic: [20]u8 = @splat(0);
    placeStyledRaster(&regular, metrics, raster, false, false);
    placeStyledRaster(&bold, metrics, raster, true, false);
    placeStyledRaster(&italic, metrics, raster, false, true);
    placeStyledRaster(&bold_italic, metrics, raster, true, true);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0x10, 0x20, 0, 0, 0, 0x30, 0x40, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
        &regular,
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0x10, 0x20, 0x20, 0, 0, 0x30, 0x40, 0x40, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
        &bold,
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0, 0x10, 0x20, 0, 0, 0, 0x30, 0x40, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
        &italic,
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0, 0x10, 0x20, 0x20, 0, 0, 0x30, 0x40, 0x40, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
        &bold_italic,
    );

    var guarded: [22]u8 = @splat(0xcc);
    @memset(guarded[1..21], 0);
    var clipped_raster = raster;
    clipped_raster.left = -1;
    clipped_raster.top = 4;
    placeStyledRaster(guarded[1..21], metrics, clipped_raster, false, false);
    try std.testing.expectEqual(@as(u8, 0xcc), guarded[0]);
    try std.testing.expectEqual(@as(u8, 0xcc), guarded[21]);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0x40, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
        guarded[1..21],
    );
}

test "T004 physical style rasters and shader decoration values remain exact" {
    var fixture: ProofFixture = undefined;
    try fixture.init(1, 4);
    defer fixture.deinit();
    const styles = [_]render.terminal_cells.Style{
        .{},
        .{ .bold = true },
        .{ .italic = true },
        .{ .bold = true, .dim = true, .italic = true, .underline = true, .strikethrough = true },
    };
    var slots: [styles.len]u16 = undefined;
    for (styles, 0..) |style, index| {
        const cell = render.terminal_cells.Cell.init(
            'x',
            .{ .r = 1, .g = 2, .b = 3 },
            .{ .r = 4, .g = 5, .b = 6 },
            .{ .r = 7, .g = 8, .b = 9 },
            style,
        );
        const instance = try instanceForCell(cell);
        slots[index] = try backend.stableGlyphSlot('x', style.bold, style.italic);
        try std.testing.expectEqual(slots[index], instance.glyph_slot);
        try fixture.grid.set(0, @intCast(index), cell);
    }
    try fixture.prepare();
    const metrics = try fixture.fonts.metrics(fixture.font);
    const font_candidate = try (try fixture.owner.fontFor(fixture.font)).prepared();
    try std.testing.expectEqual(styles.len, font_candidate.uploads.len);
    var tiles: [styles.len][]const u8 = undefined;
    for (slots, 0..) |slot, index| {
        for (font_candidate.uploads) |upload| {
            if (upload.slot == slot) {
                tiles[index] = upload.pixels;
                try std.testing.expectEqual(
                    @as(usize, metrics.advance_width) * metrics.line_height,
                    upload.pixels.len,
                );
                try std.testing.expectEqual(
                    @as(u32, metrics.advance_width),
                    upload.region.bufferRowLength,
                );
                try std.testing.expectEqual(
                    @as(i32, slot % backend.glyph_atlas_columns) * metrics.advance_width,
                    upload.region.imageOffset.x,
                );
                try std.testing.expectEqual(
                    @as(i32, slot / backend.glyph_atlas_columns) * metrics.line_height,
                    upload.region.imageOffset.y,
                );
                try std.testing.expectEqual(
                    @as(u32, metrics.advance_width),
                    upload.region.imageExtent.width,
                );
                try std.testing.expectEqual(
                    @as(u32, metrics.line_height),
                    upload.region.imageExtent.height,
                );
                break;
            }
        } else return error.GlyphUnavailable;
    }
    for (tiles, 0..) |left, left_index| {
        for (tiles[left_index + 1 ..]) |right|
            try std.testing.expect(!std.mem.eql(u8, left, right));
    }
    const decorated = try instanceForCell(render.terminal_cells.Cell.init(
        'x',
        .{ .r = 1, .g = 2, .b = 3 },
        .{ .r = 4, .g = 5, .b = 6 },
        .{ .r = 7, .g = 8, .b = 9 },
        styles[3],
    ));
    try std.testing.expect(decorated.flags.bold and decorated.flags.dim and
        decorated.flags.italic and decorated.flags.underline and
        decorated.flags.strikethrough);
    try std.testing.expectEqual(@as(u32, 0xff090807), decorated.underline_color);
    try std.testing.expectEqual(metrics.underline_y, fixture.pane.draw.underline_y);
    try std.testing.expectEqual(metrics.underline_height, fixture.pane.draw.underline_height);
    try std.testing.expectEqual(metrics.strike_y, fixture.pane.draw.strike_y);
    try std.testing.expectEqual(metrics.strike_height, fixture.pane.draw.strike_height);
    try fixture.complete();
}

test "T005 static cursor shapes convert without replay state" {
    var fixture: ProofFixture = undefined;
    try fixture.init(4, 4);
    defer fixture.deinit();
    const shapes = [_]render.terminal_cells.CursorShape{
        render.terminal_cells.CursorShape.block,
        .underline,
        .bar,
        .hidden,
    };
    for (shapes) |shape| {
        const visible = shape != .hidden;
        const input = render.terminal_cells.Cursor{
            .row = if (visible) 2 else 0,
            .col = if (visible) 3 else 0,
            .color = if (visible) .{ .r = 1, .g = 2, .b = 3 } else .{ .r = 0, .g = 0, .b = 0 },
            .text_color = if (visible) .{ .r = 4, .g = 5, .b = 6 } else .{ .r = 0, .g = 0, .b = 0 },
            .shape = shape,
            .visible = visible,
        };
        try fixture.grid.setCursor(input);
        try fixture.prepare();
        const cursor = fixture.pane.draw.cursor;
        try std.testing.expectEqual(visible, cursor.visible);
        try std.testing.expectEqual(@backingInt(shape), @backingInt(cursor.shape));
        if (visible) {
            try std.testing.expectEqual(@as(u16, 2), cursor.row);
            try std.testing.expectEqual(@as(u16, 3), cursor.col);
            try std.testing.expectEqual(@as(u32, 0xff030201), cursor.color);
            try std.testing.expectEqual(@as(u32, 0xff060504), cursor.text_color);
        } else {
            try std.testing.expectEqualDeep(backend.CursorDraw{}, cursor);
        }
        try fixture.complete();
    }
}

test "aggregate admission and borrowed descriptor receipt are exact" {
    try std.testing.expectEqual(@as(usize, 104), @sizeOf(BorrowedPaneCandidate));
    try std.testing.expectEqual(@as(usize, 6_664), @sizeOf(TerminalBatch));
    const admitted = try checkedAggregate(&.{ 10, 20, 30 }, &.{ 1, 2, 3 });
    try std.testing.expectEqual(@as(usize, 60), admitted.cells);
    try std.testing.expectEqual(@as(usize, 6), admitted.rows);
    try std.testing.expectError(error.InvalidGeometry, checkedAggregate(
        &.{pane_cell_limit + 1},
        &.{1},
    ));
}
