//! Single-pane dense terminal-cell fast lane for the native Vulkan canary.
//!
//! Rich Instance state remains canonical. This adapter admits only cells whose
//! current generic presentation can be reproduced exactly by howl-vk's retained
//! terminal-cell backend. Rare glyph overhang is preserved through generic
//! alpha overlays in the same Vulkan render pass. Unsupported snapshots fall
//! back to terminal renderer.

const std = @import("std");
const VT = @import("howl_vt").Terminal;
const render = @import("howl_render");
const text = render.text;
const howl_vk = @import("howl_vk");
const vk = howl_vk.abi;
const backend = howl_vk.terminal_cells;
const surface = howl_vk.surface;

const ascii_first: u32 = 0x20;
const ascii_last: u32 = 0x7e;
const ascii_count: usize = ascii_last - ascii_first + 1;
const overlay_identity_base: u64 =
    surface.ResourceGeneration.max_identity - ascii_count + 1;

/// Maximum retained generic resources used by the exceptional-glyph overlay.
pub const overlay_resource_limit: usize = ascii_count;

const OverlayGlyph = struct {
    width: u16,
    height: u16,
    stride: usize,
    pixels: []const u8,
    x: i32,
    y: i32,
};

const CachedGlyph = union(enum) {
    retained: backend.GlyphRaster,
    overlay: OverlayGlyph,
};

pub const Placement = struct {
    x: i32,
    y: i32,
    width: u32,
    height: u32,
};

pub const Prepared = struct {
    rows: u16,
    cols: u16,
    width: u16,
    height: u16,
    instances: []const backend.Instance,
    slots: []const u16,
    rasters: []const backend.GlyphRaster,
    cursor: backend.CursorDraw,
    metrics: text.Metrics,
    clear_color: [4]f32,
    overlay_frame: surface.Frame,
    /// Exact changed-row mask for an admitted incremental frame. `null` means
    /// the retained backend must replace the complete instance grid.
    changed_rows: ?[]const bool = null,
    /// Canonical visible rows moved upward before `changed_rows` repairs.
    row_shift: ?u16 = null,
};

const RetainedGlyphs = struct {
    slots: []const u16,
    rasters: []const backend.GlyphRaster,
};

pub const Adapter = struct {
    allocator: std.mem.Allocator,
    fonts: *text.FontSet,
    shape: *text.ShapeBuffer,
    metrics: text.Metrics,
    instances: []backend.Instance,
    overlay_commands: []surface.FrameCommand,
    tile_pixels: []u8,
    glyph_ready: [ascii_count]bool = @splat(false),
    glyphs: [ascii_count]CachedGlyph = undefined,
    slots: []u16,
    rasters: []backend.GlyphRaster,
    overlay_uploads: []surface.Upload,
    incremental_ready: bool = false,
    cached_rows: u16 = 0,
    cached_cols: u16 = 0,
    vt_presentation: VT.Presentation = undefined,
    vt_presentation_ready: bool = false,

    pub fn init(allocator: std.mem.Allocator, fonts: *text.FontSet) !Adapter {
        const metrics = fonts.metrics();
        if (metrics.advance_width == 0 or metrics.line_height == 0 or
            metrics.baseline >= metrics.line_height or
            metrics.underline_y >= metrics.line_height or
            metrics.strike_y >= metrics.line_height)
            return error.InvalidMetrics;
        const shape = try text.ShapeBuffer.init(allocator, 1);
        errdefer shape.deinit();
        const tile_bytes = try std.math.mul(
            usize,
            metrics.advance_width,
            metrics.line_height,
        );
        const tile_pixels = try allocator.alloc(
            u8,
            try std.math.mul(usize, ascii_count, tile_bytes),
        );
        errdefer allocator.free(tile_pixels);
        @memset(tile_pixels, 0);
        const slots = try allocator.alloc(u16, ascii_count);
        errdefer allocator.free(slots);
        const rasters = try allocator.alloc(backend.GlyphRaster, ascii_count);
        errdefer allocator.free(rasters);
        const overlay_uploads = try allocator.alloc(surface.Upload, ascii_count);
        errdefer allocator.free(overlay_uploads);
        return .{
            .allocator = allocator,
            .fonts = fonts,
            .shape = shape,
            .metrics = metrics,
            .instances = &.{},
            .overlay_commands = &.{},
            .tile_pixels = tile_pixels,
            .slots = slots,
            .rasters = rasters,
            .overlay_uploads = overlay_uploads,
        };
    }

    pub fn deinit(self: *Adapter) void {
        for (self.glyph_ready, 0..) |ready, index| {
            if (!ready) continue;
            switch (self.glyphs[index]) {
                .retained => {},
                .overlay => |glyph| self.allocator.free(glyph.pixels),
            }
        }
        if (self.overlay_commands.len != 0) self.allocator.free(self.overlay_commands);
        if (self.instances.len != 0) self.allocator.free(self.instances);
        self.allocator.free(self.overlay_uploads);
        self.allocator.free(self.rasters);
        self.allocator.free(self.slots);
        self.allocator.free(self.tile_pixels);
        self.shape.deinit();
        self.* = undefined;
    }

    /// Projects one direct canonical observation into the retained terminal-cell
    /// backend. Unsupported cells fall back to the terminal renderer owner.
    pub fn prepareObservation(
        self: *Adapter,
        observation: *const VT.Observation,
        changed_rows: []const bool,
        width: u16,
        height: u16,
    ) !?Prepared {
        const view = observation.semanticView(0);
        const presentation = observation.presentation();
        var images = observation.images(0);
        if (view.rows == 0 or view.cols == 0 or changed_rows.len != view.rows or
            images.imageCount() != 0 or images.placementCount() != 0)
            return null;
        const cell_count = std.math.mul(usize, view.rows, view.cols) catch return null;
        if (cell_count == 0 or cell_count > backend.maximum_cells) return null;
        // After any rejected frame, cheaply re-check only the scalar domain
        // before paying color resolution, glyph caching, or instance projection
        // across the complete canonical view. Successful retained frames skip
        // this preflight and keep the sparse changed-row path unchanged.
        if (!self.incremental_ready and !directScalarDomainSupported(&view)) return null;
        try self.ensureCapacity(cell_count);

        const cursor_draw = vtCursor(&view, &presentation) catch |failure| switch (failure) {
            error.UnsupportedTransparency => return null,
        };
        var changed_count: usize = 0;
        for (changed_rows) |changed| if (changed) {
            changed_count += 1;
        };
        const sparse_limit = @max(@as(usize, 1), changed_rows.len / 4);
        const can_sparse = self.incremental_ready and self.vt_presentation_ready and
            view.rows == self.cached_rows and view.cols == self.cached_cols and
            std.meta.eql(self.vt_presentation, presentation) and changed_count <= sparse_limit;
        // Any null/error after this point invalidates retained sparse eligibility.
        self.incremental_ready = false;

        if (!can_sparse) {
            for (0..view.rows) |row_index|
                if (!try self.projectVtRow(&view, @intCast(row_index), &presentation)) return null;
        } else {
            for (changed_rows, 0..) |changed, row_index| {
                if (!changed) continue;
                if (!try self.projectVtRow(&view, @intCast(row_index), &presentation)) return null;
            }
        }
        const glyphs = (try self.collectRetainedGlyphs()) orelse return null;
        self.cached_rows = view.rows;
        self.cached_cols = view.cols;
        self.vt_presentation = presentation;
        self.vt_presentation_ready = true;
        self.incremental_ready = true;
        return .{
            .rows = view.rows,
            .cols = view.cols,
            .width = width,
            .height = height,
            .instances = self.instances,
            .slots = glyphs.slots,
            .rasters = glyphs.rasters,
            .cursor = cursor_draw,
            .metrics = self.metrics,
            .clear_color = vtRgbaFloat(presentation.background),
            .overlay_frame = .{
                .revision = observation.semanticSequence(),
                .uploads = &.{},
                .removals = &.{},
                .commands = &.{},
            },
            .changed_rows = if (can_sparse) changed_rows else null,
            .row_shift = null,
        };
    }

    fn directScalarDomainSupported(view: *const VT.SemanticView) bool {
        for (0..view.rows) |row_index| {
            if (view.lineGeometry(@intCast(row_index)) != .single_width) return false;
            for (0..view.cols) |column| {
                const cell = view.cellInfoAt(@intCast(row_index), @intCast(column));
                if (cell.codepoint == 0 or cell.codepoint == ' ') continue;
                const scalar = std.math.cast(u8, cell.codepoint) orelse return false;
                const alnum = (scalar >= '0' and scalar <= '9') or
                    (scalar >= 'A' and scalar <= 'Z') or
                    (scalar >= 'a' and scalar <= 'z');
                if (!alnum) return false;
            }
        }
        return true;
    }

    fn projectVtRow(
        self: *Adapter,
        view: *const VT.SemanticView,
        row: u16,
        presentation: *const VT.Presentation,
    ) !bool {
        if (view.lineGeometry(row) != .single_width) return false;
        const first = @as(usize, row) * @as(usize, view.cols);
        for (0..view.cols) |column| {
            const cell = view.cellInfoAt(row, @intCast(column));
            const projected = try self.vtInstance(cell, presentation) orelse return false;
            if (projected.glyph_slot != backend.blank_glyph) {
                const glyph_index: usize = projected.glyph_slot;
                if (glyph_index >= ascii_count) return false;
                const cached = try self.ensureGlyph(glyph_index) orelse return false;
                if (cached != .retained) return false;
            }
            self.instances[first + column] = projected;
        }
        return true;
    }

    fn vtInstance(
        _: *const Adapter,
        cell: VT.Cell,
        presentation: *const VT.Presentation,
    ) !?backend.Instance {
        if (cell.width != 1 or cell.height != 1 or cell.x != 0 or cell.y != 0 or
            cell.subscale_n != 0 or cell.subscale_d != 0 or cell.vertical_align != 0 or
            cell.horizontal_align != 0 or cell.semantic_width or cell.attrs.font != 0 or
            cell.attrs.baseline != .normal or cell.attrs.dim or cell.attrs.invisible or
            (cell.attrs.underline and cell.attrs.underline_style != .straight) or
            cell.combining_len != 0)
            return null;
        var glyph_slot = backend.blank_glyph;
        if (cell.codepoint != 0 and cell.codepoint != ' ') {
            const scalar = std.math.cast(u8, cell.codepoint) orelse return null;
            const alnum = (scalar >= '0' and scalar <= '9') or
                (scalar >= 'A' and scalar <= 'Z') or
                (scalar >= 'a' and scalar <= 'z');
            if (!alnum) return null;
            glyph_slot = try backend.stableGlyphSlot(scalar, false, false);
        }
        var foreground = cell.attrs.fg.resolve(presentation.foreground, &presentation.palette);
        var background = cell.attrs.bg.resolve(presentation.background, &presentation.palette);
        if (cell.attrs.reverse != presentation.reverse_screen)
            std.mem.swap(VT.Rgb, &foreground, &background);
        const underline = cell.attrs.underline_color.resolve(presentation.foreground, &presentation.palette);
        if (foreground.a != 0xff or background.a != 0xff or underline.a != 0xff) return null;
        if (cell.attrs.strikethrough and !std.meta.eql(foreground, underline)) return null;
        const has_ink = cell.codepoint != 0;
        return .{
            .glyph_slot = glyph_slot,
            .flags = .{
                .underline = has_ink and cell.attrs.underline,
                .strikethrough = has_ink and cell.attrs.strikethrough,
            },
            .foreground = vtPack(foreground),
            .background = vtPack(background),
            .underline_color = vtPack(underline),
        };
    }

    fn collectRetainedGlyphs(self: *Adapter) !?RetainedGlyphs {
        var slot_seen: [ascii_count]bool = @splat(false);
        var slot_count: usize = 0;
        for (self.instances) |instance_value| {
            if (instance_value.glyph_slot == backend.blank_glyph) continue;
            const glyph_index: usize = instance_value.glyph_slot;
            if (glyph_index >= ascii_count or slot_seen[glyph_index]) continue;
            const cached = try self.ensureGlyph(glyph_index) orelse return null;
            const raster = switch (cached) {
                .retained => |value| value,
                .overlay => return null,
            };
            slot_seen[glyph_index] = true;
            self.slots[slot_count] = instance_value.glyph_slot;
            self.rasters[slot_count] = raster;
            slot_count += 1;
        }
        return .{
            .slots = self.slots[0..slot_count],
            .rasters = self.rasters[0..slot_count],
        };
    }

    fn ensureCapacity(self: *Adapter, cell_count: usize) !void {
        if (self.instances.len == cell_count and self.overlay_commands.len == cell_count) return;
        self.incremental_ready = false;
        if (self.instances.len != 0) self.allocator.free(self.instances);
        if (self.overlay_commands.len != 0) self.allocator.free(self.overlay_commands);
        self.instances = &.{};
        self.overlay_commands = &.{};
        errdefer {
            if (self.instances.len != 0) self.allocator.free(self.instances);
            self.instances = &.{};
        }
        self.instances = try self.allocator.alloc(backend.Instance, cell_count);
        self.overlay_commands = try self.allocator.alloc(surface.FrameCommand, cell_count);
    }

    fn ensureGlyph(self: *Adapter, index: usize) !?CachedGlyph {
        if (index >= ascii_count) return null;
        if (self.glyph_ready[index]) return self.glyphs[index];
        const scalar: u32 = ascii_first + @as(u32, @intCast(index));
        const codepoints = [_]u32{scalar};
        const clusters = [_]u32{0};
        var shaped: [1]text.Glyph = undefined;
        const run = self.fonts.shape(
            self.shape,
            .{ .codepoints = &codepoints, .clusters = &clusters },
            &shaped,
        ) catch return null;
        if (run.glyphs.len != 1 or run.glyphs[0].cluster != 0) return null;
        var raster = self.fonts.rasterize(
            self.allocator,
            run.face_index,
            run.glyphs[0].id,
        ) catch return null;
        defer raster.deinit();
        if (raster.width == 0 or raster.height == 0) return null;

        const glyph = run.glyphs[0];
        const x_26_6 = std.math.add(
            i64,
            @as(i64, glyph.x_offset),
            @as(i64, raster.left) * 64,
        ) catch return error.InvalidGeometry;
        var y_26_6 = std.math.mul(i64, @as(i64, self.metrics.baseline), 64) catch
            return error.InvalidGeometry;
        y_26_6 = std.math.sub(i64, y_26_6, @as(i64, glyph.y_offset)) catch
            return error.InvalidGeometry;
        y_26_6 = std.math.sub(i64, y_26_6, @as(i64, raster.top) * 64) catch
            return error.InvalidGeometry;
        const x = std.math.cast(i32, @divFloor(x_26_6, 64)) orelse
            return error.InvalidGeometry;
        const y = std.math.cast(i32, @divFloor(y_26_6, 64)) orelse
            return error.InvalidGeometry;
        const tile_width: usize = self.metrics.advance_width;
        const tile_height: usize = self.metrics.line_height;
        const fits = x >= 0 and y >= 0 and
            @as(usize, @intCast(x)) + raster.width <= tile_width and
            @as(usize, @intCast(y)) + raster.height <= tile_height;
        if (fits) {
            const tile_bytes = tile_width * tile_height;
            const pixels = self.tile_pixels[index * tile_bytes ..][0..tile_bytes];
            @memset(pixels, 0);
            for (0..raster.height) |row| {
                const src = row * @as(usize, raster.width);
                const dst = (@as(usize, @intCast(y)) + row) * tile_width +
                    @as(usize, @intCast(x));
                @memcpy(pixels[dst .. dst + raster.width], raster.pixels[src .. src + raster.width]);
            }
            self.glyphs[index] = .{ .retained = .{
                .slot = @intCast(index),
                .width = self.metrics.advance_width,
                .height = self.metrics.line_height,
                .stride = self.metrics.advance_width,
                .pixels = pixels,
            } };
        } else {
            const pixels = try self.allocator.dupe(u8, raster.pixels);
            self.glyphs[index] = .{ .overlay = .{
                .width = raster.width,
                .height = raster.height,
                .stride = raster.width,
                .pixels = pixels,
                .x = x,
                .y = y,
            } };
        }
        self.glyph_ready[index] = true;
        return self.glyphs[index];
    }
};

fn packedFloat(value: u32) [4]f32 {
    return .{
        @as(f32, @floatFromInt(value & 0xff)) / 255.0,
        @as(f32, @floatFromInt((value >> 8) & 0xff)) / 255.0,
        @as(f32, @floatFromInt((value >> 16) & 0xff)) / 255.0,
        @as(f32, @floatFromInt((value >> 24) & 0xff)) / 255.0,
    };
}

pub const Gpu = struct {
    allocator: std.mem.Allocator,
    limits: backend.Limits,
    font: backend.FontGpu,
    resources: backend.Resources,
    pane: backend.PaneResources,
    store: backend.Store,
    cell_updates: []backend.CellWriteInput,
    physical_rows: []u32,
    first: bool = true,
    pending: bool = false,

    pub fn init(
        allocator: std.mem.Allocator,
        device: vk.VkDevice,
        properties: vk.VkPhysicalDeviceMemoryProperties,
        render_pass: vk.VkRenderPass,
        gpu_bytes: *u64,
        gpu_limit: u64,
        frame: Prepared,
    ) !Gpu {
        const sparse_rows = @max(@as(usize, 1), @as(usize, frame.rows) / 3);
        const sparse_cells = try std.math.mul(usize, sparse_rows, frame.cols);
        const limits = backend.Limits{
            .rows = frame.rows,
            .cols = frame.cols,
            .sparse_cell_updates = sparse_cells,
            .structured_updates = 1,
        };
        var font = try backend.FontGpu.init(allocator, .{
            .glyph_width = frame.metrics.advance_width,
            .glyph_height = frame.metrics.line_height,
        });
        errdefer font.deinit();
        try font.initPhysical(device, properties, gpu_bytes, gpu_limit);
        errdefer font.deinitPhysical(device, gpu_bytes);
        const staging_payload = try backend.physicalPayloadBytes(limits);
        var resources = try backend.Resources.init(
            device,
            properties,
            render_pass,
            .{
                .descriptor_panes = 1,
                .instance_bytes = staging_payload.instances,
                .row_bytes = staging_payload.row_map,
            },
            gpu_bytes,
            gpu_limit,
        );
        errdefer resources.deinit(device, gpu_bytes);
        var pane = try resources.createPane(device, properties, limits, &font, gpu_bytes, gpu_limit);
        errdefer pane.deinit(device, resources.descriptor_pool, gpu_bytes);
        var store = try backend.Store.init(allocator, limits, .initialization);
        errdefer store.deinit();
        const cell_updates = try allocator.alloc(backend.CellWriteInput, sparse_cells);
        errdefer allocator.free(cell_updates);
        const physical_rows = try allocator.alloc(u32, frame.rows);
        errdefer allocator.free(physical_rows);
        return .{
            .allocator = allocator,
            .limits = limits,
            .font = font,
            .resources = resources,
            .pane = pane,
            .store = store,
            .cell_updates = cell_updates,
            .physical_rows = physical_rows,
        };
    }

    pub fn deinit(self: *Gpu, device: vk.VkDevice, gpu_bytes: *u64) void {
        if (self.pending) self.discard();
        self.allocator.free(self.physical_rows);
        self.allocator.free(self.cell_updates);
        self.store.deinit();
        self.pane.deinit(device, self.resources.descriptor_pool, gpu_bytes);
        self.resources.deinit(device, gpu_bytes);
        self.font.deinitPhysical(device, gpu_bytes);
        self.font.deinit();
        self.* = undefined;
    }

    pub fn geometryMatches(self: *const Gpu, frame: Prepared) bool {
        return frame.rows == self.limits.rows and frame.cols == self.limits.cols;
    }

    pub fn prepare(self: *Gpu, frame: Prepared) !void {
        if (self.pending or frame.rows != self.limits.rows or frame.cols != self.limits.cols)
            return error.InvalidGeometry;
        try self.font.prepare(frame.slots, frame.rasters);
        errdefer self.font.discard() catch {};
        var rotation_storage: [1]backend.RowRotation = undefined;
        var row_rotations: []const backend.RowRotation = &.{};
        var sparse: ?[]const backend.CellWriteInput = null;
        if (!self.first) {
            if (frame.row_shift) |rows_up| {
                const repairs = frame.changed_rows orelse return error.InvalidGeometry;
                const signed_shift = std.math.cast(i16, rows_up) orelse
                    return error.InvalidGeometry;
                rotation_storage[0] = .{
                    .first = 0,
                    .count = frame.rows,
                    .shift = -signed_shift,
                };
                row_rotations = &rotation_storage;
                const physical_rows = try self.store.projectPhysicalRows(
                    row_rotations,
                    self.physical_rows,
                );
                sparse = try sparseCellWrites(
                    frame.rows,
                    frame.cols,
                    frame.instances,
                    repairs,
                    physical_rows,
                    self.cell_updates,
                );
            } else if (frame.changed_rows) |changed_rows| {
                sparse = try sparseCellWrites(
                    frame.rows,
                    frame.cols,
                    frame.instances,
                    changed_rows,
                    null,
                    self.cell_updates,
                );
            }
        }
        const prepared = try self.store.prepare(.{
            .rows = frame.rows,
            .cols = frame.cols,
            .replacement = if (sparse == null) .{
                .kind = if (self.first) .initialization else .resize,
                .rows = frame.rows,
                .cols = frame.cols,
                .instances = frame.instances,
            } else null,
            .row_rotations = row_rotations,
            .fills = &.{},
            .cells = sparse orelse &.{},
            .glyph_slots = frame.slots,
            .cursor = frame.cursor,
        }, &self.font);
        const expected_instances = if (sparse) |writes| writes.len else frame.instances.len;
        const expected_bytes = std.math.mul(usize, expected_instances, @sizeOf(backend.Instance)) catch
            return error.InvalidGeometry;
        if (prepared.rows != frame.rows or prepared.cols != frame.cols or
            (prepared.replacement != null) != (sparse == null) or
            (prepared.row_copy != null) != (sparse == null or row_rotations.len != 0) or
            prepared.instance_staging_bytes != expected_bytes)
            return error.InvalidGeometry;
        errdefer self.store.discard() catch {};
        try self.font.stagePhysical();
        try self.resources.stagePane(&self.store, .{ .instances = 0, .rows = 0 });
        self.pending = true;
    }

    pub fn recordTransfers(self: *Gpu, command: vk.VkCommandBuffer) !void {
        if (!self.pending) return error.NoCandidate;
        try self.font.recordTransfers(command);
        try self.store.recordTransfers(
            command,
            try self.resources.bindings(&self.pane, &self.font),
            .{ .instances = 0, .rows = 0 },
        );
    }

    pub fn recordDraw(
        self: *Gpu,
        command: vk.VkCommandBuffer,
        frame: Prepared,
        placement: Placement,
        physical_width: u32,
        physical_height: u32,
    ) !void {
        if (placement.x < 0 or placement.y < 0 or
            placement.width != frame.width or placement.height != frame.height)
            return error.InvalidGeometry;
        var draw = try self.store.currentDraw();
        draw.origin_x = placement.x;
        draw.origin_y = placement.y;
        draw.clip_x = placement.x;
        draw.clip_y = placement.y;
        draw.clip_width = placement.width;
        draw.clip_height = placement.height;
        draw.cell_width = frame.metrics.advance_width;
        draw.cell_height = frame.metrics.line_height;
        draw.baseline = frame.metrics.baseline;
        draw.underline_y = frame.metrics.underline_y;
        draw.underline_height = frame.metrics.underline_height;
        draw.strike_y = frame.metrics.strike_y;
        draw.strike_height = frame.metrics.strike_height;
        try self.store.recordDraw(
            command,
            try self.resources.bindings(&self.pane, &self.font),
            draw,
            .{ .physical_width = physical_width, .physical_height = physical_height },
        );
    }

    pub fn complete(self: *Gpu) !void {
        if (!self.pending or !self.font.completionReady() or !self.store.candidatePending())
            return error.NoCandidate;
        try self.font.complete();
        try self.store.complete();
        self.first = false;
        self.pending = false;
    }

    pub fn discard(self: *Gpu) void {
        if (!self.pending) return;
        if (self.font.candidatePending()) self.font.discard() catch {};
        if (self.store.candidatePending()) self.store.discard() catch {};
        self.pending = false;
    }
};

fn sparseCellWrites(
    rows: u16,
    cols: u16,
    instances: []const backend.Instance,
    changed_rows: []const bool,
    physical_rows: ?[]const u32,
    output: []backend.CellWriteInput,
) ![]const backend.CellWriteInput {
    const cell_count = try std.math.mul(usize, rows, cols);
    if (rows == 0 or cols == 0 or instances.len != cell_count or changed_rows.len != rows or
        (physical_rows != null and physical_rows.?.len != rows))
        return error.InvalidGeometry;
    var count: usize = 0;
    for (changed_rows, 0..) |changed, row| {
        if (!changed) continue;
        const source_first = try std.math.mul(usize, row, cols);
        const physical_row: usize = if (physical_rows) |mapping| blk: {
            if (mapping[row] >= rows) return error.InvalidGeometry;
            break :blk mapping[row];
        } else row;
        const destination_first = try std.math.mul(usize, physical_row, cols);
        for (instances[source_first .. source_first + cols], 0..) |instance_value, column| {
            if (count == output.len) return error.InvalidGeometry;
            output[count] = .{
                .physical_index = std.math.cast(u32, destination_first + column) orelse
                    return error.InvalidGeometry,
                .instance = instance_value,
            };
            count += 1;
        }
    }
    return output[0..count];
}

fn vtPack(value: VT.Rgb) u32 {
    return @as(u32, value.r) |
        (@as(u32, value.g) << 8) |
        (@as(u32, value.b) << 16) |
        (@as(u32, value.a) << 24);
}

fn vtRgbaFloat(value: VT.Rgb) [4]f32 {
    return .{
        @as(f32, @floatFromInt(value.r)) / 255.0,
        @as(f32, @floatFromInt(value.g)) / 255.0,
        @as(f32, @floatFromInt(value.b)) / 255.0,
        @as(f32, @floatFromInt(value.a)) / 255.0,
    };
}

fn vtCursor(view: *const VT.SemanticView, presentation: *const VT.Presentation) !backend.CursorDraw {
    if (!view.cursor_visible or view.cursor_shape == .none or
        view.cursor_row >= view.rows or view.cursor_col >= view.cols)
        return .{};
    const color = presentation.cursor orelse presentation.foreground;
    const text_color = presentation.cursor_text orelse presentation.background;
    if (color.a != 0xff or text_color.a != 0xff) return error.UnsupportedTransparency;
    return .{
        .row = view.cursor_row,
        .col = view.cursor_col,
        .color = vtPack(color),
        .text_color = vtPack(text_color),
        .shape = switch (view.cursor_shape) {
            .underline => .underline,
            .bar => .bar,
            else => .block,
        },
        .visible = true,
    };
}

test "direct canonical retained adapter consumes exact sparse row facts" {
    const fonts = try text.FontSet.init(std.testing.allocator, .{
        .primary = @import("test_fonts").primary_font,
        .size = .{ .pixels = 16 },
    });
    defer fonts.deinit();
    var adapter = try Adapter.init(std.testing.allocator, fonts);
    defer adapter.deinit();
    var terminal = try VT.init(std.testing.allocator, 4, 4);
    defer terminal.deinit();
    const metrics = fonts.metrics();
    const width = try std.math.mul(u16, metrics.advance_width, 4);
    const height = try std.math.mul(u16, metrics.line_height, 4);

    try std.testing.expect((try terminal.feed("\x1b[?25l\x1b[38;5;1mA\x1b[4;4HZ")).stateChanged());
    var changed: [4]bool = @splat(true);
    const first = (try adapter.prepareObservation(
        terminal.observation(),
        &changed,
        width,
        height,
    )) orelse return error.ExpectedDenseAdmission;
    try std.testing.expect(first.changed_rows == null);
    try std.testing.expectEqual(
        try backend.stableGlyphSlot('A', false, false),
        first.instances[0].glyph_slot,
    );
    const presentation = terminal.presentation();
    try std.testing.expectEqual(
        vtPack(presentation.palette[1]),
        first.instances[0].foreground,
    );

    try std.testing.expect((try terminal.feed("\x1b[2;2HB")).stateChanged());
    changed = .{ false, true, false, false };
    const sparse = (try adapter.prepareObservation(
        terminal.observation(),
        &changed,
        width,
        height,
    )) orelse return error.ExpectedIncrementalAdmission;
    try std.testing.expectEqualSlices(bool, &changed, sparse.changed_rows.?);
    try std.testing.expectEqual(
        try backend.stableGlyphSlot('A', false, false),
        sparse.instances[0].glyph_slot,
    );
    try std.testing.expectEqual(
        try backend.stableGlyphSlot('B', false, false),
        sparse.instances[5].glyph_slot,
    );

    try std.testing.expect((try terminal.feed("\x1b[2;3H:\x1b[2;4H|")).stateChanged());
    try std.testing.expect((try adapter.prepareObservation(
        terminal.observation(),
        &changed,
        width,
        height,
    )) == null);
    try std.testing.expect(!adapter.incremental_ready);
    try std.testing.expect(!adapter.glyph_ready[':' - ascii_first]);
    try std.testing.expect(!adapter.glyph_ready['|' - ascii_first]);

    try std.testing.expect((try terminal.feed("\x1b[2;3H  ")).stateChanged());
    const recovered = (try adapter.prepareObservation(
        terminal.observation(),
        &changed,
        width,
        height,
    )) orelse return error.ExpectedRecoveredAdmission;
    try std.testing.expect(recovered.changed_rows == null);
    try std.testing.expect(adapter.incremental_ready);
}

test "direct canonical retained adapter preserves empty decorations and rejects strike color mismatch" {
    const fonts = try text.FontSet.init(std.testing.allocator, .{
        .primary = @import("test_fonts").primary_font,
        .size = .{ .pixels = 16 },
    });
    defer fonts.deinit();
    const metrics = fonts.metrics();
    const width = try std.math.mul(u16, metrics.advance_width, 4);
    const height = try std.math.mul(u16, metrics.line_height, 4);
    const changed: [4]bool = @splat(true);

    {
        var adapter = try Adapter.init(std.testing.allocator, fonts);
        defer adapter.deinit();
        var terminal = try VT.init(std.testing.allocator, 4, 4);
        defer terminal.deinit();
        try std.testing.expect((try terminal.feed("\x1b[?25l\x1b[4;9m\x1b[2J")).stateChanged());
        const prepared = (try adapter.prepareObservation(
            terminal.observation(),
            &changed,
            width,
            height,
        )) orelse return error.ExpectedDenseAdmission;
        for (prepared.instances) |instance_value| {
            try std.testing.expect(!instance_value.flags.underline);
            try std.testing.expect(!instance_value.flags.strikethrough);
        }
    }

    {
        var adapter = try Adapter.init(std.testing.allocator, fonts);
        defer adapter.deinit();
        var terminal = try VT.init(std.testing.allocator, 4, 4);
        defer terminal.deinit();
        try std.testing.expect((try terminal.feed(
            "\x1b[?25l\x1b[38;2;255;0;0;58;2;0;0;255;9m ",
        )).stateChanged());
        try std.testing.expect((try adapter.prepareObservation(
            terminal.observation(),
            &changed,
            width,
            height,
        )) == null);
        try std.testing.expect(!adapter.incremental_ready);
    }
}

test "sparse retained GPU writes target identity and projected physical rows" {
    var instances: [6]backend.Instance = undefined;
    for (&instances, 1..) |*instance_value, slot| instance_value.* = .{
        .glyph_slot = @intCast(slot),
        .flags = .{},
        .foreground = 0,
        .background = 0,
        .underline_color = 0,
    };
    var changed = [_]bool{ false, true, false };
    var output: [2]backend.CellWriteInput = undefined;
    const writes = try sparseCellWrites(3, 2, &instances, &changed, null, &output);
    try std.testing.expectEqual(@as(usize, 2), writes.len);
    try std.testing.expectEqual(@as(u32, 2), writes[0].physical_index);
    try std.testing.expectEqual(@as(u16, 3), writes[0].instance.glyph_slot);
    try std.testing.expectEqual(@as(u32, 3), writes[1].physical_index);
    try std.testing.expectEqual(@as(u16, 4), writes[1].instance.glyph_slot);

    changed = .{ true, false, false };
    const physical_rows = [_]u32{ 2, 0, 1 };
    const mapped = try sparseCellWrites(3, 2, &instances, &changed, &physical_rows, &output);
    try std.testing.expectEqual(@as(u32, 4), mapped[0].physical_index);
    try std.testing.expectEqual(@as(u16, 1), mapped[0].instance.glyph_slot);
    try std.testing.expectEqual(@as(u32, 5), mapped[1].physical_index);
    try std.testing.expectEqual(@as(u16, 2), mapped[1].instance.glyph_slot);

    @memset(&changed, false);
    const cursor_only = try sparseCellWrites(3, 2, &instances, &changed, null, &output);
    try std.testing.expectEqual(@as(usize, 0), cursor_only.len);
}
