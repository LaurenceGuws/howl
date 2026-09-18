//! Single-pane dense terminal-cell fast lane for the native Vulkan canary.
//!
//! Rich Session state remains canonical. This adapter admits only cells whose
//! current generic presentation can be reproduced exactly by howl-vk's retained
//! terminal-cell backend. Rare glyph overhang is preserved through generic
//! alpha overlays in the same Vulkan render pass. Unsupported snapshots fall
//! back to generic Canvas.

const std = @import("std");
const client = @import("howl_client");
const text = @import("howl_text");
const howl_vk = @import("howl_vk");
const vk = howl_vk.abi;
const backend = howl_vk.terminal_cells;
const surface = howl_vk.surface;

const style_bold: u16 = 1 << 0;
const style_dim: u16 = 1 << 1;
const style_italic: u16 = 1 << 2;
const style_blink: u16 = 1 << 3;
const style_blink_fast: u16 = 1 << 4;
const style_reverse: u16 = 1 << 5;
const style_invisible: u16 = 1 << 6;
const style_underline: u16 = 1 << 7;
const style_strike: u16 = 1 << 8;
const known_style_bits: u16 = style_bold | style_dim | style_italic | style_blink |
    style_blink_fast | style_reverse | style_invisible | style_underline | style_strike;
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
    cached_reverse_screen: bool = false,
    cached_palette: [256]client.rich.Rgba = undefined,
    cached_foreground: client.rich.Rgba = undefined,
    cached_background: client.rich.Rgba = undefined,

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

    pub fn prepare(
        self: *Adapter,
        snapshot: *const client.rich.View,
        width: u16,
        height: u16,
    ) !?Prepared {
        if (try self.prepareShifted(snapshot, width, height)) |prepared| return prepared;
        if (try self.prepareIncremental(snapshot, width, height)) |prepared| return prepared;
        return self.prepareFull(snapshot, width, height);
    }

    fn prepareFull(
        self: *Adapter,
        snapshot: *const client.rich.View,
        width: u16,
        height: u16,
    ) !?Prepared {
        self.incremental_ready = false;
        const begin = snapshot.begin;
        if (begin.revision == 0 or begin.rows == 0 or begin.columns == 0 or
            snapshot.rows.len != begin.rows or snapshot.graphics.images.len != 0 or
            snapshot.graphics.placements.len != 0)
            return null;
        const cell_count = std.math.mul(usize, begin.rows, begin.columns) catch return null;
        if (cell_count == 0 or cell_count > backend.maximum_cells) return null;
        try self.ensureCapacity(cell_count);

        const cursor_draw = cursor(begin, &snapshot.presentation) catch |failure| switch (failure) {
            error.UnsupportedTransparency => return null,
        };
        var slot_seen: [ascii_count]bool = @splat(false);
        var upload_seen: [ascii_count]bool = @splat(false);
        var slot_count: usize = 0;
        var upload_count: usize = 0;
        var overlay_count: usize = 0;
        var instance_index: usize = 0;
        for (snapshot.rows, 0..) |row, row_index| {
            if (row.line_geometry != 0 or row.cells.len != begin.columns) return null;
            for (row.cells, 0..) |cell, column| {
                var projected = try self.instance(cell, &snapshot.presentation) orelse return null;
                if (projected.glyph_slot != backend.blank_glyph) {
                    const glyph_index: usize = projected.glyph_slot;
                    if (glyph_index >= ascii_count) return null;
                    const cached = try self.ensureGlyph(glyph_index) orelse return null;
                    switch (cached) {
                        .retained => |raster| {
                            if (!slot_seen[glyph_index]) {
                                slot_seen[glyph_index] = true;
                                self.slots[slot_count] = projected.glyph_slot;
                                self.rasters[slot_count] = raster;
                                slot_count += 1;
                            }
                        },
                        .overlay => |glyph| {
                            // Cursor replay recolors glyph coverage. Until the
                            // overlay path can split cursor-covered pixels from
                            // ordinary overhang, preserve exactness via fallback.
                            if (cursor_draw.visible and cursor_draw.row == row_index and
                                cursor_draw.col == column)
                                return null;
                            projected.glyph_slot = backend.blank_glyph;
                            const resource = surface.ResourceGeneration.init(
                                overlay_identity_base + glyph_index,
                                begin.revision,
                            ) catch return null;
                            if (!upload_seen[glyph_index]) {
                                upload_seen[glyph_index] = true;
                                self.overlay_uploads[upload_count] = .{
                                    .resource = resource,
                                    .kind = .alpha_mask,
                                    .width = glyph.width,
                                    .height = glyph.height,
                                    .stride = glyph.stride,
                                    .pixels = glyph.pixels,
                                };
                                upload_count += 1;
                            }
                            const cell_x = std.math.mul(
                                i64,
                                @as(i64, @intCast(column)),
                                @as(i64, self.metrics.advance_width),
                            ) catch return error.InvalidGeometry;
                            const cell_y = std.math.mul(
                                i64,
                                @as(i64, @intCast(row_index)),
                                @as(i64, self.metrics.line_height),
                            ) catch return error.InvalidGeometry;
                            const destination_x = std.math.add(i64, cell_x, glyph.x) catch
                                return error.InvalidGeometry;
                            const destination_y = std.math.add(i64, cell_y, glyph.y) catch
                                return error.InvalidGeometry;
                            self.overlay_commands[overlay_count] = .{ .alpha_mask = .{
                                .rect = .{
                                    .x = std.math.cast(i32, destination_x) orelse
                                        return error.InvalidGeometry,
                                    .y = std.math.cast(i32, destination_y) orelse
                                        return error.InvalidGeometry,
                                    .width = glyph.width,
                                    .height = glyph.height,
                                },
                                .clip = .{
                                    .x = 0,
                                    .y = std.math.cast(i32, cell_y) orelse
                                        return error.InvalidGeometry,
                                    .width = width,
                                    .height = self.metrics.line_height,
                                },
                                .resource = resource,
                                .color = packedFloat(projected.foreground),
                            } };
                            overlay_count += 1;
                        },
                    }
                }
                self.instances[instance_index] = projected;
                instance_index += 1;
            }
        }
        std.debug.assert(instance_index == cell_count);
        if (overlay_count == 0) self.rememberRetained(begin, &snapshot.presentation);
        return .{
            .rows = begin.rows,
            .cols = begin.columns,
            .width = width,
            .height = height,
            .instances = self.instances,
            .slots = self.slots[0..slot_count],
            .rasters = self.rasters[0..slot_count],
            .cursor = cursor_draw,
            .metrics = self.metrics,
            .clear_color = rgbaFloat(snapshot.presentation.background),
            .overlay_frame = .{
                .revision = begin.revision,
                .uploads = self.overlay_uploads[0..upload_count],
                .removals = &.{},
                .commands = self.overlay_commands[0..overlay_count],
            },
            .changed_rows = null,
            .row_shift = null,
        };
    }

    fn prepareShifted(
        self: *Adapter,
        snapshot: *const client.rich.View,
        width: u16,
        height: u16,
    ) !?Prepared {
        if (!self.incremental_ready) return null;
        const rows_up = snapshot.row_shift orelse return null;
        const repairs = snapshot.changed_rows orelse return null;
        const begin = snapshot.begin;
        if (rows_up == 0 or rows_up >= begin.rows or
            std.math.cast(i16, rows_up) == null or
            begin.rows != self.cached_rows or begin.columns != self.cached_cols or
            snapshot.rows.len != begin.rows or repairs.len != begin.rows or
            snapshot.graphics.images.len != 0 or snapshot.graphics.placements.len != 0)
            return null;
        const cell_count = std.math.mul(usize, begin.rows, begin.columns) catch return null;
        if (cell_count != self.instances.len or self.overlay_commands.len != cell_count or
            !self.sameCellPresentation(&snapshot.presentation))
            return null;

        const repair_limit = @max(@as(usize, 1), repairs.len / 3);
        var repair_count: usize = 0;
        for (repairs) |repair| {
            if (!repair) continue;
            repair_count += 1;
            if (repair_count > repair_limit) return null;
        }
        const exposed_first = begin.rows - rows_up;
        for (repairs[exposed_first..]) |repair| if (!repair) return null;

        const cursor_draw = cursor(begin, &snapshot.presentation) catch |failure| switch (failure) {
            error.UnsupportedTransparency => return null,
        };
        self.incremental_ready = false;
        const shifted_cells = std.math.mul(usize, rows_up, begin.columns) catch
            return error.InvalidGeometry;
        const retained_cells = cell_count - shifted_cells;
        std.mem.copyForwards(
            backend.Instance,
            self.instances[0..retained_cells],
            self.instances[shifted_cells..],
        );
        for (snapshot.rows, repairs, 0..) |row, repair, row_index| {
            if (!repair) continue;
            if (!try self.projectRetainedRow(row, row_index, begin.columns, &snapshot.presentation))
                return null;
        }
        const glyphs = (try self.collectRetainedGlyphs()) orelse return null;
        self.rememberRetained(begin, &snapshot.presentation);
        return .{
            .rows = begin.rows,
            .cols = begin.columns,
            .width = width,
            .height = height,
            .instances = self.instances,
            .slots = glyphs.slots,
            .rasters = glyphs.rasters,
            .cursor = cursor_draw,
            .metrics = self.metrics,
            .clear_color = rgbaFloat(snapshot.presentation.background),
            .overlay_frame = .{
                .revision = begin.revision,
                .uploads = &.{},
                .removals = &.{},
                .commands = &.{},
            },
            .changed_rows = repairs,
            .row_shift = rows_up,
        };
    }

    fn prepareIncremental(
        self: *Adapter,
        snapshot: *const client.rich.View,
        width: u16,
        height: u16,
    ) !?Prepared {
        if (!self.incremental_ready) return null;
        const changed_rows = snapshot.changed_rows orelse return null;
        const begin = snapshot.begin;
        if (begin.revision == 0 or begin.rows != self.cached_rows or begin.columns != self.cached_cols or
            snapshot.rows.len != begin.rows or changed_rows.len != begin.rows or
            snapshot.graphics.images.len != 0 or snapshot.graphics.placements.len != 0)
            return null;
        const cell_count = std.math.mul(usize, begin.rows, begin.columns) catch return null;
        if (cell_count != self.instances.len or self.overlay_commands.len != cell_count) return null;
        const changed_limit = @max(@as(usize, 1), changed_rows.len / 4);
        var changed_count: usize = 0;
        for (changed_rows) |changed| {
            if (!changed) continue;
            changed_count += 1;
            if (changed_count > changed_limit) return null;
        }
        if (!self.sameCellPresentation(&snapshot.presentation)) return null;

        const cursor_draw = cursor(begin, &snapshot.presentation) catch |failure| switch (failure) {
            error.UnsupportedTransparency => return null,
        };
        for (snapshot.rows, changed_rows, 0..) |row, changed, row_index| {
            if (!changed) continue;
            if (!try self.projectRetainedRow(row, row_index, begin.columns, &snapshot.presentation))
                return null;
        }

        const glyphs = (try self.collectRetainedGlyphs()) orelse return null;
        return .{
            .rows = begin.rows,
            .cols = begin.columns,
            .width = width,
            .height = height,
            .instances = self.instances,
            .slots = glyphs.slots,
            .rasters = glyphs.rasters,
            .cursor = cursor_draw,
            .metrics = self.metrics,
            .clear_color = rgbaFloat(snapshot.presentation.background),
            .overlay_frame = .{
                .revision = begin.revision,
                .uploads = &.{},
                .removals = &.{},
                .commands = &.{},
            },
            .changed_rows = changed_rows,
            .row_shift = null,
        };
    }

    fn projectRetainedRow(
        self: *Adapter,
        row: client.rich.Row,
        row_index: usize,
        columns: u16,
        presentation: *const client.rich.Presentation,
    ) !bool {
        if (row.line_geometry != 0 or row.cells.len != columns) return false;
        const first = row_index * @as(usize, columns);
        for (row.cells, 0..) |cell, column| {
            const projected = try self.instance(cell, presentation) orelse return false;
            if (projected.glyph_slot != backend.blank_glyph) {
                const glyph_index: usize = projected.glyph_slot;
                if (glyph_index >= ascii_count) return false;
                const cached = try self.ensureGlyph(glyph_index) orelse return false;
                switch (cached) {
                    .retained => {},
                    // Sparse retained updates cannot recreate exceptional
                    // overhang overlays; the caller falls back to full state.
                    .overlay => return false,
                }
            }
            self.instances[first + column] = projected;
        }
        return true;
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

    fn rememberRetained(
        self: *Adapter,
        begin: @FieldType(client.rich.View, "begin"),
        presentation: *const client.rich.Presentation,
    ) void {
        self.cached_rows = begin.rows;
        self.cached_cols = begin.columns;
        self.cached_reverse_screen = presentation.reverse_screen;
        self.cached_palette = presentation.palette;
        self.cached_foreground = presentation.foreground;
        self.cached_background = presentation.background;
        self.incremental_ready = true;
    }

    fn sameCellPresentation(
        self: *const Adapter,
        presentation: *const client.rich.Presentation,
    ) bool {
        return self.cached_reverse_screen == presentation.reverse_screen and
            std.meta.eql(self.cached_palette, presentation.palette) and
            std.meta.eql(self.cached_foreground, presentation.foreground) and
            std.meta.eql(self.cached_background, presentation.background);
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

    fn instance(
        _: *const Adapter,
        cell: client.rich.Cell,
        presentation: *const client.rich.Presentation,
    ) !?backend.Instance {
        if (cell.width != 1 or cell.height != 1 or cell.x != 0 or cell.y != 0 or
            cell.subscale_n != 0 or cell.subscale_d != 0 or cell.vertical_align != 0 or
            cell.horizontal_align != 0 or cell.semantic_width or cell.font != 0 or
            cell.baseline != 0 or cell.style_bits & ~known_style_bits != 0 or
            cell.style_bits & (style_dim | style_invisible) != 0 or
            (cell.style_bits & style_underline != 0 and cell.underline_style != 0))
            return null;
        if (cell.scalars.len > 1) return null;

        var glyph_slot = backend.blank_glyph;
        if (cell.scalars.len == 1) {
            const scalar = cell.scalars[0];
            if (scalar < ascii_first or scalar > ascii_last) return null;
            if (scalar != ' ') {
                // Punctuation can participate in contextual terminal ligatures
                // in the generic path. Dense admission is intentionally limited
                // to scalars whose current shaping semantics are independent.
                if (!(scalar >= '0' and scalar <= '9') and
                    !(scalar >= 'A' and scalar <= 'Z') and
                    !(scalar >= 'a' and scalar <= 'z'))
                    return null;
                glyph_slot = try backend.stableGlyphSlot(@intCast(scalar), false, false);
            }
        }

        var foreground = try resolveColor(cell.foreground, presentation, true);
        var background = try resolveColor(cell.background, presentation, false);
        const reversed = (cell.style_bits & style_reverse != 0) != presentation.reverse_screen;
        if (reversed) std.mem.swap([4]u8, &foreground, &background);
        const underline = try resolveColor(cell.underline_color, presentation, true);
        if (foreground[3] != 0xff or background[3] != 0xff or underline[3] != 0xff)
            return null;
        return .{
            .glyph_slot = glyph_slot,
            // Today's generic terminal path does not select bold/italic font
            // faces, and blink does not alter static presentation. Keep those
            // bits visually neutral here instead of reviving historical policy.
            .flags = .{
                .underline = cell.style_bits & style_underline != 0,
                .strikethrough = cell.style_bits & style_strike != 0,
            },
            .foreground = pack(foreground),
            .background = pack(background),
            .underline_color = pack(underline),
        };
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

fn cursor(
    begin: @FieldType(client.rich.Snapshot, "begin"),
    presentation: *const client.rich.Presentation,
) !backend.CursorDraw {
    if (!begin.cursor_visible or begin.cursor_shape == 3 or
        begin.cursor_row >= begin.rows or begin.cursor_column >= begin.columns)
        return .{};
    const color = rgba(presentation.cursor orelse presentation.foreground);
    const text_color = rgba(presentation.cursor_text orelse presentation.background);
    if (color[3] != 0xff or text_color[3] != 0xff) return error.UnsupportedTransparency;
    return .{
        .row = begin.cursor_row,
        .col = begin.cursor_column,
        .color = pack(color),
        .text_color = pack(text_color),
        .shape = switch (begin.cursor_shape) {
            1 => .underline,
            2 => .bar,
            else => .block,
        },
        .visible = true,
    };
}

const TextColor = @FieldType(client.rich.Cell, "foreground");

fn resolveColor(
    value: TextColor,
    presentation: *const client.rich.Presentation,
    foreground: bool,
) ![4]u8 {
    return switch (value.kind) {
        .default => rgba(if (foreground) presentation.foreground else presentation.background),
        .indexed => if (value.value < presentation.palette.len)
            rgba(presentation.palette[value.value])
        else
            error.InvalidColor,
        .rgb => .{
            @intCast((value.value >> 16) & 0xff),
            @intCast((value.value >> 8) & 0xff),
            @intCast(value.value & 0xff),
            0xff,
        },
    };
}

fn rgba(value: client.rich.Rgba) [4]u8 {
    return .{ value.r, value.g, value.b, value.a };
}

fn rgbaFloat(value: client.rich.Rgba) [4]f32 {
    return .{
        @as(f32, @floatFromInt(value.r)) / 255.0,
        @as(f32, @floatFromInt(value.g)) / 255.0,
        @as(f32, @floatFromInt(value.b)) / 255.0,
        @as(f32, @floatFromInt(value.a)) / 255.0,
    };
}

fn pack(value: [4]u8) u32 {
    return @as(u32, value[0]) |
        (@as(u32, value[1]) << 8) |
        (@as(u32, value[2]) << 16) |
        (@as(u32, value[3]) << 24);
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

test "dense terminal adapter retains ordinary ASCII and overlays fixture overhang" {
    const fonts = try text.FontSet.init(std.testing.allocator, .{
        .primary = @import("test_fonts").primary_font,
        .size = .{ .pixels = 16 },
    });
    defer fonts.deinit();
    var adapter = try Adapter.init(std.testing.allocator, fonts);
    defer adapter.deinit();
    const metrics = fonts.metrics();

    var a_scalar = [_]u32{'A'};
    var a_cells = [_]client.rich.Cell{testCell(&a_scalar)};
    var a_rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &a_cells }};
    var a_snapshot = testSnapshot(&a_rows, 1, 17, false);
    const a_view = a_snapshot.view();
    const a = (try adapter.prepare(
        &a_view,
        metrics.advance_width,
        metrics.line_height,
    )) orelse return error.ExpectedDenseAdmission;
    try std.testing.expectEqual(@as(usize, 0), a.overlay_frame.commands.len);
    try std.testing.expectEqual(@as(usize, 1), a.slots.len);
    try std.testing.expectEqual(
        try backend.stableGlyphSlot('A', false, false),
        a.instances[0].glyph_slot,
    );

    var j_scalar = [_]u32{'J'};
    var j_cells = [_]client.rich.Cell{testCell(&j_scalar)};
    var j_rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &j_cells }};
    var j_snapshot = testSnapshot(&j_rows, 1, 18, false);
    const j_view = j_snapshot.view();
    const j = (try adapter.prepare(
        &j_view,
        metrics.advance_width,
        metrics.line_height,
    )) orelse return error.ExpectedDenseAdmission;
    try std.testing.expectEqual(backend.blank_glyph, j.instances[0].glyph_slot);
    try std.testing.expectEqual(@as(usize, 1), j.overlay_frame.uploads.len);
    try std.testing.expectEqual(@as(usize, 1), j.overlay_frame.commands.len);
    switch (j.overlay_frame.commands[0]) {
        .alpha_mask => |overlay| {
            const right = @as(i64, overlay.rect.x) + overlay.rect.width;
            try std.testing.expect(overlay.rect.x < 0 or right > metrics.advance_width);
            try std.testing.expectEqual(@as(i32, 0), overlay.clip.x);
            try std.testing.expectEqual(@as(i32, 0), overlay.clip.y);
            try std.testing.expectEqual(@as(u32, metrics.advance_width), overlay.clip.width);
            try std.testing.expectEqual(@as(u32, metrics.line_height), overlay.clip.height);
        },
        else => return error.ExpectedOverhangOverlay,
    }
}

test "prepared dense borrows survive adapter value movement" {
    const fonts = try text.FontSet.init(std.testing.allocator, .{
        .primary = @import("test_fonts").primary_font,
        .size = .{ .pixels = 16 },
    });
    defer fonts.deinit();
    var original = try Adapter.init(std.testing.allocator, fonts);
    const metrics = fonts.metrics();

    var a_scalar = [_]u32{'A'};
    var j_scalar = [_]u32{'J'};
    var cells = [_]client.rich.Cell{ testCell(&a_scalar), testCell(&j_scalar) };
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    var snapshot = testSnapshot(&rows, 2, 19, false);
    const snapshot_view = snapshot.view();
    const width = try std.math.mul(u16, metrics.advance_width, 2);
    const prepared = (try original.prepare(&snapshot_view, width, metrics.line_height)) orelse
        return error.ExpectedDenseAdmission;
    try std.testing.expectEqual(@as(usize, 1), prepared.slots.len);
    try std.testing.expectEqual(@as(usize, 1), prepared.rasters.len);
    try std.testing.expectEqual(@as(usize, 1), prepared.overlay_frame.uploads.len);

    const expected_slot = prepared.slots[0];
    const expected_raster_slot = prepared.rasters[0].slot;
    const expected_upload_resource = prepared.overlay_frame.uploads[0].resource;
    var moved = original;
    original = undefined;
    defer moved.deinit();

    try std.testing.expectEqual(expected_slot, prepared.slots[0]);
    try std.testing.expectEqual(expected_raster_slot, prepared.rasters[0].slot);
    try std.testing.expectEqual(expected_upload_resource, prepared.overlay_frame.uploads[0].resource);
}

test "dense terminal adapter updates sparse rows and rejects broad churn" {
    const fonts = try text.FontSet.init(std.testing.allocator, .{
        .primary = @import("test_fonts").primary_font,
        .size = .{ .pixels = 16 },
    });
    defer fonts.deinit();
    var adapter = try Adapter.init(std.testing.allocator, fonts);
    defer adapter.deinit();
    const metrics = fonts.metrics();

    var a0 = [_]u32{'A'};
    var a1 = [_]u32{'A'};
    var a2 = [_]u32{'A'};
    var a3 = [_]u32{'A'};
    var initial_cells = [_][1]client.rich.Cell{
        .{testCell(&a0)}, .{testCell(&a1)}, .{testCell(&a2)}, .{testCell(&a3)},
    };
    var initial_rows = [_]client.rich.Row{
        .{ .wrapped = false, .line_geometry = 0, .cells = &initial_cells[0] },
        .{ .wrapped = false, .line_geometry = 0, .cells = &initial_cells[1] },
        .{ .wrapped = false, .line_geometry = 0, .cells = &initial_cells[2] },
        .{ .wrapped = false, .line_geometry = 0, .cells = &initial_cells[3] },
    };
    var initial_snapshot = testSnapshot(&initial_rows, 1, 24, false);
    const initial_view = initial_snapshot.view();
    const height = try std.math.mul(u16, metrics.line_height, 4);
    const initial = (try adapter.prepare(&initial_view, metrics.advance_width, height)) orelse
        return error.ExpectedDenseAdmission;
    try std.testing.expectEqual(@as(usize, 4), initial.instances.len);

    var b0 = [_]u32{'B'};
    var next_cells = [_][1]client.rich.Cell{
        .{testCell(&b0)}, .{testCell(&a1)}, .{testCell(&a2)}, .{testCell(&a3)},
    };
    var next_rows = [_]client.rich.Row{
        .{ .wrapped = false, .line_geometry = 0, .cells = &next_cells[0] },
        .{ .wrapped = false, .line_geometry = 0, .cells = &next_cells[1] },
        .{ .wrapped = false, .line_geometry = 0, .cells = &next_cells[2] },
        .{ .wrapped = false, .line_geometry = 0, .cells = &next_cells[3] },
    };
    var next_snapshot = testSnapshot(&next_rows, 1, 25, false);
    var next_view = next_snapshot.view();
    var sparse_changed = [_]bool{ true, false, false, false };
    next_view.changed_rows = &sparse_changed;
    const sparse = (try adapter.prepareIncremental(
        &next_view,
        metrics.advance_width,
        height,
    )) orelse return error.ExpectedIncrementalAdmission;
    try std.testing.expectEqual(
        try backend.stableGlyphSlot('B', false, false),
        sparse.instances[0].glyph_slot,
    );
    try std.testing.expectEqual(
        try backend.stableGlyphSlot('A', false, false),
        sparse.instances[1].glyph_slot,
    );

    var broad_changed = [_]bool{ true, true, false, false };
    next_view.changed_rows = &broad_changed;
    try std.testing.expect((try adapter.prepareIncremental(
        &next_view,
        metrics.advance_width,
        height,
    )) == null);
}

test "dense terminal adapter rotates retained rows and repairs exact exceptions" {
    const fonts = try text.FontSet.init(std.testing.allocator, .{
        .primary = @import("test_fonts").primary_font,
        .size = .{ .pixels = 16 },
    });
    defer fonts.deinit();
    var adapter = try Adapter.init(std.testing.allocator, fonts);
    defer adapter.deinit();
    const metrics = fonts.metrics();

    var initial_scalars = [_][1]u32{
        .{'A'}, .{'B'}, .{'C'}, .{'D'}, .{'E'}, .{'F'},
    };
    var initial_cells: [6][1]client.rich.Cell = undefined;
    var initial_rows: [6]client.rich.Row = undefined;
    for (&initial_cells, &initial_rows, 0..) |*cells, *row, index| {
        cells.* = .{testCell(&initial_scalars[index])};
        row.* = .{ .wrapped = false, .line_geometry = 0, .cells = cells };
    }
    var initial_snapshot = testSnapshot(&initial_rows, 1, 30, false);
    const initial_view = initial_snapshot.view();
    const height = try std.math.mul(u16, metrics.line_height, 6);
    const initial = (try adapter.prepare(&initial_view, metrics.advance_width, height)) orelse
        return error.ExpectedDenseAdmission;
    try std.testing.expectEqual(@as(usize, 6), initial.instances.len);

    var next_scalars = [_][1]u32{
        .{'B'}, .{'X'}, .{'D'}, .{'E'}, .{'F'}, .{'G'},
    };
    var next_cells: [6][1]client.rich.Cell = undefined;
    var next_rows: [6]client.rich.Row = undefined;
    for (&next_cells, &next_rows, 0..) |*cells, *row, index| {
        cells.* = .{testCell(&next_scalars[index])};
        row.* = .{ .wrapped = false, .line_geometry = 0, .cells = cells };
    }
    var next_snapshot = testSnapshot(&next_rows, 1, 31, false);
    var next_view = next_snapshot.view();
    var broad_changed: [6]bool = @splat(true);
    var repairs = [_]bool{ false, true, false, false, false, true };
    next_view.changed_rows = &broad_changed;
    next_view.row_shift = 1;
    next_view.changed_rows = &repairs;
    const shifted = (try adapter.prepare(&next_view, metrics.advance_width, height)) orelse
        return error.ExpectedShiftAdmission;

    try std.testing.expectEqual(@as(?u16, 1), shifted.row_shift);
    try std.testing.expectEqualSlices(bool, &repairs, shifted.changed_rows.?);
    for ([_]u8{ 'B', 'X', 'D', 'E', 'F', 'G' }, shifted.instances) |scalar, instance_value|
        try std.testing.expectEqual(
            try backend.stableGlyphSlot(scalar, false, false),
            instance_value.glyph_slot,
        );
}

test "dense terminal adapter refuses semantics it cannot reproduce exactly" {
    const fonts = try text.FontSet.init(std.testing.allocator, .{
        .primary = @import("test_fonts").primary_font,
        .size = .{ .pixels = 16 },
    });
    defer fonts.deinit();
    var adapter = try Adapter.init(std.testing.allocator, fonts);
    defer adapter.deinit();
    const metrics = fonts.metrics();

    var punctuation = [_]u32{'-'};
    var punctuation_cells = [_]client.rich.Cell{testCell(&punctuation)};
    var punctuation_rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &punctuation_cells }};
    var punctuation_snapshot = testSnapshot(&punctuation_rows, 1, 21, false);
    const punctuation_view = punctuation_snapshot.view();
    try std.testing.expect((try adapter.prepare(
        &punctuation_view,
        metrics.advance_width,
        metrics.line_height,
    )) == null);

    var dim_scalar = [_]u32{'A'};
    var dim_cells = [_]client.rich.Cell{testCell(&dim_scalar)};
    dim_cells[0].style_bits = style_dim;
    var dim_rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &dim_cells }};
    var dim_snapshot = testSnapshot(&dim_rows, 1, 22, false);
    const dim_view = dim_snapshot.view();
    try std.testing.expect((try adapter.prepare(
        &dim_view,
        metrics.advance_width,
        metrics.line_height,
    )) == null);

    var j_scalar = [_]u32{'J'};
    var cursor_cells = [_]client.rich.Cell{testCell(&j_scalar)};
    var cursor_rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cursor_cells }};
    var cursor_snapshot = testSnapshot(&cursor_rows, 1, 23, true);
    const cursor_view = cursor_snapshot.view();
    try std.testing.expect((try adapter.prepare(
        &cursor_view,
        metrics.advance_width,
        metrics.line_height,
    )) == null);
}

fn testPresentation() client.rich.Presentation {
    return .{
        .cursor_age_ns = null,
        .presence_bits = 0,
        .flags = 0,
        .reverse_screen = false,
        .palette = @splat(.{ .r = 0, .g = 0, .b = 0, .a = 0xff }),
        .foreground = .{ .r = 0xee, .g = 0xee, .b = 0xee, .a = 0xff },
        .background = .{ .r = 1, .g = 2, .b = 3, .a = 0xff },
        .cursor = null,
        .cursor_text = null,
        .selection_background = null,
        .selection_foreground = null,
    };
}

fn testCell(scalars: []u32) client.rich.Cell {
    return .{
        .scalars = scalars,
        .width = 1,
        .height = 1,
        .x = 0,
        .y = 0,
        .subscale_n = 0,
        .subscale_d = 0,
        .vertical_align = 0,
        .horizontal_align = 0,
        .semantic_width = false,
        .font = 0,
        .baseline = 0,
        .underline_style = 0,
        .protection = 0,
        .style_bits = 0,
        .foreground = .{ .kind = .default, .value = 0 },
        .background = .{ .kind = .default, .value = 0 },
        .underline_color = .{ .kind = .default, .value = 0 },
        .link_id = 0,
    };
}

fn testSnapshot(
    rows: []client.rich.Row,
    columns: u16,
    revision: u64,
    cursor_visible: bool,
) client.rich.Snapshot {
    return .{
        .allocator = std.testing.allocator,
        .begin = .{
            .revision = revision,
            .terminal_revision = revision,
            .history_offset = 0,
            .history_count = 0,
            .history_row_base = 0,
            .rows = @intCast(rows.len),
            .columns = columns,
            .cursor_row = 0,
            .cursor_column = 0,
            .cursor_shape = 0,
            .cursor_visible = cursor_visible,
            .cursor_blink = false,
            .alternate_screen = false,
            .stream_closed = false,
            .child_exited = false,
            .leader_present = false,
            .you_are_leader = false,
        },
        .presentation = testPresentation(),
        .rows = rows,
        .hyperlinks = &.{},
    };
}
