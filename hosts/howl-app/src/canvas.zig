//! Retains content pixels and paints the cursor from complete immutable frames.
const std = @import("std");
const c = @import("desktop");
const instance = @import("howl_instance");
const terminal = @import("terminal.zig");
const selection = @import("selection.zig");
const cursor_effects = @import("cursor.zig");
const render = instance.render.terminal;

/// Host focus/blink composition over one immutable cursor frame.
pub const CursorDisplay = enum { shown, hidden, outline };

const resource_limit = render.maximum_frame_resources;
// SDL3.4.18 merges queued geometry. Historical NVIDIA client-array uploads
// above 4 MiB retained growing storage. Bound the whole content queue, including
// colour-only copies: 2048 quads need at most 393216 bytes of GL vertex data.
const batch_quads = 2048;
const quad_indices = blk: {
    @setEvalBranchQuota(batch_quads * 8);
    var indices: [batch_quads * 6]c_int = undefined;
    for (0..batch_quads) |quad| {
        const vertex: c_int = @intCast(quad * 4);
        indices[quad * 6 ..][0..6].* = .{ vertex, vertex + 1, vertex + 2, vertex, vertex + 2, vertex + 3 };
    }
    break :blk indices;
};

const Texture = struct {
    residency: render.Residency,
    texture: *c.SDL_Texture,
};

/// One graphical-thread scratch batch shared by all panes.
pub const Geometry = struct {
    vertices: [batch_quads * 4]c.SDL_Vertex = undefined,
    count: usize = 0,
    queued_quads: usize = 0,
    texture: ?*c.SDL_Texture = null,
    clip: c.SDL_Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },

    // SDL owns copied vertex data after RenderGeometry returns. Bound the
    // entire queued content batch, including RGBA copies, rather than forcing
    // a backend submission whenever texture or clip changes.
    fn reserve(self: *Geometry, renderer: *c.SDL_Renderer, quads: usize) !void {
        std.debug.assert(self.queued_quads <= batch_quads and quads <= batch_quads);
        if (self.queued_quads > batch_quads - quads) try self.submit(renderer);
    }

    fn submit(self: *Geometry, renderer: *c.SDL_Renderer) !void {
        if (self.queued_quads == 0) return;
        if (!c.SDL_FlushRenderer(renderer)) return error.SDLGeometry;
        self.queued_quads = 0;
    }

    fn flush(self: *Geometry, renderer: *c.SDL_Renderer) !void {
        if (self.count == 0) return;
        try self.reserve(renderer, self.count);
        if (!c.SDL_SetRenderClipRect(renderer, &self.clip) or
            !c.SDL_RenderGeometry(renderer, self.texture, &self.vertices, @intCast(self.count * 4), &quad_indices, @intCast(self.count * 6)))
            return error.SDLGeometry;
        self.queued_quads += self.count;
        self.count = 0;
    }

    fn finish(self: *Geometry, renderer: *c.SDL_Renderer) !void {
        try self.flush(renderer);
        try self.submit(renderer);
    }

    fn append(
        self: *Geometry,
        renderer: *c.SDL_Renderer,
        texture: ?*c.SDL_Texture,
        clip: c.SDL_Rect,
        dest: c.SDL_FRect,
        source: c.SDL_FRect,
        color: render.Color,
    ) !void {
        if (self.count == batch_quads or self.texture != texture or !rectEqual(self.clip, clip)) try self.flush(renderer);
        self.texture = texture;
        self.clip = clip;
        const base = self.count * 4;
        const rgba: c.SDL_FColor = .{
            .r = @as(f32, @floatFromInt(color.r)) / 255,
            .g = @as(f32, @floatFromInt(color.g)) / 255,
            .b = @as(f32, @floatFromInt(color.b)) / 255,
            .a = @as(f32, @floatFromInt(color.a)) / 255,
        };
        self.vertices[base..][0..4].* = .{
            .{ .position = .{ .x = dest.x, .y = dest.y }, .color = rgba, .tex_coord = .{ .x = source.x, .y = source.y } },
            .{ .position = .{ .x = dest.x + dest.w, .y = dest.y }, .color = rgba, .tex_coord = .{ .x = source.x + source.w, .y = source.y } },
            .{ .position = .{ .x = dest.x + dest.w, .y = dest.y + dest.h }, .color = rgba, .tex_coord = .{ .x = source.x + source.w, .y = source.y + source.h } },
            .{ .position = .{ .x = dest.x, .y = dest.y + dest.h }, .color = rgba, .tex_coord = .{ .x = source.x, .y = source.y + source.h } },
        };
        self.count += 1;
    }
};

/// Holds one immutable canonical frame until a newer publication replaces it.
/// The producer retains two free/replaceable slots and never waits for this lease.
pub const Canvas = struct {
    allocator: std.mem.Allocator,
    lease: ?instance.RenderLease = null,
    direct_lease: ?instance.DirectLease = null,
    direct_owner: ?*terminal.Terminal = null,
    selection_paint: selection.Paint = .{},
    textures: [resource_limit]Texture = undefined,
    count: usize = 0,
    converted: std.ArrayList(u8) = .empty,
    generation: u64 = 0,
    content: ?*c.SDL_Texture = null,
    content_revision: ?u64 = null,
    direct_context: ?u64 = null,
    direct_origin: u16 = 0,
    direct_rows: u16 = 0,
    direct_generations: [instance.render.limits.maximum_rows]u64 = @splat(0),
    content_size: render.Size = .{ .width = 1, .height = 1 },
    cursor_rows: render.CursorRows = .{},
    cursor_index_revision: ?u64 = null,

    /// Creates an empty backend resource owner with no canonical or frame authority.
    pub fn init(allocator: std.mem.Allocator) Canvas {
        return .{ .allocator = allocator };
    }

    /// Retires the held frame before releasing graphical resources and scratch.
    pub fn deinit(self: *Canvas) void {
        if (self.lease) |*lease| lease.abandon();
        if (self.direct_lease) |lease| {
            // zig-audit: acknowledge catch_unreachable
            // reason: Canvas owns this exact live direct pin until teardown.
            self.direct_owner.?.releaseDirectFrame(lease) catch unreachable;
        }
        self.clearTextures();
        self.converted.deinit(self.allocator);
        self.* = undefined;
    }

    /// Copies interaction facts from the same held cut used for drawing.
    pub fn frame(self: *const Canvas) ?@import("frame_info.zig").Info {
        if (self.direct_lease) |*lease| return @import("frame_info.zig").Info.fromSnapshot(&lease.snapshot, lease.presentation_generation, lease.serial);
        return if (self.lease) |lease| @import("frame_info.zig").Info.fromLegacy(lease.value) else null;
    }

    /// Transfers an immutable publication only when ready; duplicate wakeups keep the old lease.
    pub fn update(self: *Canvas, renderer: *c.SDL_Renderer, owner: *terminal.Terminal) !void {
        if (owner.usesDirect()) {
            const direct = (try owner.replaceDirectFrame(if (self.direct_lease) |*previous| previous else null, &self.selection_paint)) orelse return;
            self.direct_lease = null;
            // zig-audit: acknowledge catch_unreachable
            // reason: The just-acquired direct pin belongs to this live owner.
            errdefer owner.releaseDirectFrame(direct) catch unreachable;
            try self.applySnapshotResources(renderer, direct.presentation_generation, &direct.snapshot);
            self.direct_lease = direct;
            self.direct_owner = owner;
            return;
        }
        var residency: [resource_limit]render.Residency = undefined;
        for (self.textures[0..self.count], 0..) |texture, index| residency[index] = texture.residency;
        var lease = (try owner.replaceFrame(if (self.lease) |*previous| previous else null, residency[0..self.count], &self.selection_paint)) orelse return;
        self.lease = null;
        errdefer lease.abandon();
        const value = lease.value;
        try self.applyResources(renderer, value.presentation_generation, value.uploads, value.removals, value.pixels);
        // Feedback describes the resources just applied, while frame storage stays leased.
        for (self.textures[0..self.count], 0..) |texture, index| residency[index] = texture.residency;
        try lease.reportResidency(residency[0..self.count]);
        self.lease = lease;
    }

    /// Applies a validated immutable resource transaction on the graphical thread.
    /// Pixel storage is borrowed only for this call. On failure, applied resources
    /// may be partial; do not acknowledge residency or draw until a complete retry.
    pub fn applyResources(
        self: *Canvas,
        renderer: *c.SDL_Renderer,
        presentation_generation: u64,
        uploads: []const render.FrameResourceUpload,
        removals: []const render.ResourceRef,
        pixels: []const u8,
    ) !void {
        if (self.generation != presentation_generation) {
            self.clearTextures();
            self.generation = presentation_generation;
        }
        for (removals) |resource| self.remove(resource, true);
        for (uploads) |upload| {
            const source = pixels[upload.pixel_offset..][0..upload.pixel_count];
            const width: usize = upload.size.width;
            const height: usize = upload.size.height;
            var upload_pixels: []const u8 = source;
            var stride = upload.stride;
            if (upload.format == .alpha8) {
                // Each upload replaces the whole scratch image; geometric slack buys no reuse.
                const bytes = width * height * 4;
                try self.converted.ensureTotalCapacityPrecise(self.allocator, bytes);
                self.converted.items.len = bytes;
                for (0..height) |y| for (0..width) |x| {
                    const at = (y * width + x) * 4;
                    self.converted.items[at..][0..4].* = .{ 255, 255, 255, source[y * upload.stride + x] };
                };
                upload_pixels = self.converted.items;
                stride = width * 4;
            }
            const texture = c.SDL_CreateTexture(renderer, c.SDL_PIXELFORMAT_RGBA32, c.SDL_TEXTUREACCESS_STATIC, upload.size.width, upload.size.height) orelse return error.SDLTexture;
            var owned = true;
            errdefer if (owned) c.SDL_DestroyTexture(texture);
            if (!c.SDL_SetTextureScaleMode(texture, c.SDL_SCALEMODE_NEAREST) or
                !c.SDL_SetTextureBlendMode(texture, c.SDL_BLENDMODE_BLEND) or
                !c.SDL_UpdateTexture(texture, null, upload_pixels.ptr, @intCast(stride))) return error.SDLTexture;
            self.remove(upload.resource, false);
            if (self.count == resource_limit) return error.ResourceLimit;
            self.textures[self.count] = .{
                .texture = texture,
                .residency = .{ .resource = upload.resource, .format = upload.format, .size = upload.size },
            };
            self.count += 1;
            owned = false;
        }
    }

    /// Brings the held VT snapshot's immutable atlas planes into the backend.
    /// Existing exact generations need no transfer; a failed upload can be retried.
    pub fn applySnapshotResources(
        self: *Canvas,
        renderer: *c.SDL_Renderer,
        presentation_generation: u64,
        snapshot: *const @import("howl_vt_output").Snapshot,
    ) !void {
        if (self.generation != presentation_generation) {
            self.clearTextures();
            self.generation = presentation_generation;
        }
        if (self.find(snapshot.resource) == null) {
            const upload: render.FrameResourceUpload = .{ .resource = snapshot.resource, .format = .alpha8, .size = .{ .width = snapshot.atlas_width, .height = snapshot.atlas_height }, .pixel_offset = 0, .pixel_count = snapshot.atlas_pixels.len, .stride = snapshot.atlas_width };
            try self.applyResources(renderer, presentation_generation, &.{upload}, &.{}, snapshot.atlas_pixels);
        }
        if (snapshot.color_resource) |resource| {
            if (self.find(resource) == null) {
                const upload: render.FrameResourceUpload = .{ .resource = resource, .format = .rgba8, .size = .{ .width = snapshot.color_atlas_width, .height = snapshot.color_atlas_height }, .pixel_offset = 0, .pixel_count = snapshot.color_atlas_pixels.len, .stride = @as(usize, snapshot.color_atlas_width) * 4 };
                try self.applyResources(renderer, presentation_generation, &.{upload}, &.{}, snapshot.color_atlas_pixels);
            }
        } else {
            // Direct output owns only its alpha and color planes. Retire a stale color plane.
            var index: usize = 0;
            while (index < self.count) {
                if (self.textures[index].residency.format == .rgba8) {
                    self.remove(self.textures[index].residency.resource, true);
                } else index += 1;
            }
        }
    }

    /// Draws canonical commands with exact pane/resource clipping using shared bounded batches.
    pub fn draw(self: *Canvas, renderer: *c.SDL_Renderer, geometry: *Geometry, logical_pane: c.SDL_FRect, scale: f32, cursor: CursorDisplay, outline_pixels: u8, motion: ?cursor_effects.Visual) !void {
        std.debug.assert(outline_pixels >= 1 and outline_pixels <= 16);
        const info = self.frame() orelse return;
        if (self.direct_lease) |*direct| return self.drawDirect(renderer, geometry, logical_pane, scale, cursor, outline_pixels, motion, info, &direct.snapshot);
        const value = (self.lease orelse return).value;
        // Canonical commands already use physical pixels. Dividing then letting
        // SDL scale them back introduces fractional cell edges and visible seams.
        var previous_x: f32 = 0;
        var previous_y: f32 = 0;
        if (!c.SDL_GetRenderScale(renderer, &previous_x, &previous_y) or
            !c.SDL_SetRenderScale(renderer, 1, 1)) return error.SDLScale;
        // zig-audit: acknowledge discard
        // reason: Best-effort state restoration on draw failure preserves the original SDL error.
        errdefer _ = c.SDL_SetRenderScale(renderer, previous_x, previous_y);
        // zig-audit: acknowledge discard
        // reason: Best-effort clip retirement on draw failure preserves the original SDL error.
        errdefer _ = c.SDL_SetRenderClipRect(renderer, null);
        const pane: c.SDL_FRect = .{
            .x = @round(logical_pane.x * scale),
            .y = @round(logical_pane.y * scale),
            .w = logical_pane.w * scale,
            .h = logical_pane.h * scale,
        };
        if (self.content == null or !std.meta.eql(self.content_size, value.surface)) {
            self.invalidateContent();
            const target = c.SDL_CreateTexture(renderer, c.SDL_PIXELFORMAT_RGBA32, c.SDL_TEXTUREACCESS_TARGET, value.surface.width, value.surface.height) orelse return error.SDLTexture;
            errdefer c.SDL_DestroyTexture(target);
            if (!c.SDL_SetTextureScaleMode(target, c.SDL_SCALEMODE_NEAREST) or
                !c.SDL_SetTextureBlendMode(target, c.SDL_BLENDMODE_NONE)) return error.SDLTexture;
            self.content = target;
            self.content_size = value.surface;
        }
        const target = self.content.?;
        if (self.content_revision != value.content_revision) {
            const previous_target = c.SDL_GetRenderTarget(renderer);
            if (!c.SDL_SetRenderTarget(renderer, target)) return error.SDLTexture;
            // zig-audit: acknowledge discard
            // reason: Restore the caller's render target on failure without hiding the original SDL error.
            errdefer _ = c.SDL_SetRenderTarget(renderer, previous_target);
            if (!c.SDL_SetRenderClipRect(renderer, null) or
                !c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 0) or
                !c.SDL_RenderClear(renderer)) return error.SDLTexture;
            try self.drawCommands(renderer, geometry, .{
                .x = 0,
                .y = 0,
                .w = @floatFromInt(value.surface.width),
                .h = @floatFromInt(value.surface.height),
            }, value.commands[0..value.content_command_count]);
            if (!c.SDL_SetRenderTarget(renderer, previous_target)) return error.SDLTexture;
            self.content_revision = value.content_revision;
        }
        const pane_clip = pixelClip(pane);
        const destination_rect: c.SDL_FRect = .{
            .x = pane.x,
            .y = pane.y,
            .w = @floatFromInt(value.surface.width),
            .h = @floatFromInt(value.surface.height),
        };
        if (!c.SDL_SetRenderClipRect(renderer, &pane_clip) or
            !c.SDL_RenderTexture(renderer, target, null, &destination_rect)) return error.SDLTexture;
        try self.drawSelection(renderer, pane, info);
        switch (cursor) {
            .shown => if (motion) |visual|
                try self.drawMovingCursor(renderer, geometry, pane, value, visual)
            else
                try self.drawCommands(renderer, geometry, pane, value.commands[value.content_command_count..]),
            .hidden => {},
            .outline => if (value.cursor) |overlay| {
                const r = overlay.rect;
                const width = @min(r.width, outline_pixels);
                const height = @min(r.height, outline_pixels);
                const right = r.x + @as(i32, r.width - width);
                const bottom = r.y + @as(i32, r.height - height);
                // Four bounded physical-pixel edges avoid scale-dependent SDL strokes.
                const commands = [_]render.Command{
                    .{ .solid = .{ .rect = .{ .x = r.x, .y = r.y, .width = r.width, .height = height }, .color = overlay.color } },
                    .{ .solid = .{ .rect = .{ .x = r.x, .y = bottom, .width = r.width, .height = height }, .color = overlay.color } },
                    .{ .solid = .{ .rect = .{ .x = r.x, .y = r.y, .width = width, .height = r.height }, .color = overlay.color } },
                    .{ .solid = .{ .rect = .{ .x = right, .y = r.y, .width = width, .height = r.height }, .color = overlay.color } },
                };
                try self.drawCommands(renderer, geometry, pane, &commands);
            },
        }
        if (!c.SDL_SetRenderClipRect(renderer, null)) return error.SDLClip;
        if (!c.SDL_SetRenderScale(renderer, previous_x, previous_y)) return error.SDLScale;
    }

    fn drawDirect(self: *Canvas, renderer: *c.SDL_Renderer, geometry: *Geometry, logical_pane: c.SDL_FRect, scale: f32, cursor: CursorDisplay, outline_pixels: u8, motion: ?cursor_effects.Visual, value: @import("frame_info.zig").Info, snapshot: *const @import("howl_vt_output").Snapshot) !void {
        var previous_x: f32 = 0;
        var previous_y: f32 = 0;
        if (!c.SDL_GetRenderScale(renderer, &previous_x, &previous_y) or !c.SDL_SetRenderScale(renderer, 1, 1)) return error.SDLScale;
        // zig-audit: acknowledge discard
        // reason: Preserve the original drawing error while restoring SDL state.
        errdefer _ = c.SDL_SetRenderScale(renderer, previous_x, previous_y);
        // zig-audit: acknowledge discard
        // reason: Preserve the original drawing error while retiring the clip.
        errdefer _ = c.SDL_SetRenderClipRect(renderer, null);
        const pane: c.SDL_FRect = .{ .x = @round(logical_pane.x * scale), .y = @round(logical_pane.y * scale), .w = logical_pane.w * scale, .h = logical_pane.h * scale };
        if (self.content == null or !std.meta.eql(self.content_size, snapshot.surface)) {
            self.invalidateContent();
            const target = c.SDL_CreateTexture(renderer, c.SDL_PIXELFORMAT_RGBA32, c.SDL_TEXTUREACCESS_TARGET, snapshot.surface.width, snapshot.surface.height) orelse return error.SDLTexture;
            errdefer c.SDL_DestroyTexture(target);
            if (!c.SDL_SetTextureScaleMode(target, c.SDL_SCALEMODE_NEAREST) or !c.SDL_SetTextureBlendMode(target, c.SDL_BLENDMODE_NONE)) return error.SDLTexture;
            self.content = target;
            self.content_size = snapshot.surface;
        }
        const target = self.content.?;
        if (self.content_revision != snapshot.content_revision) {
            const previous_target = c.SDL_GetRenderTarget(renderer);
            if (!c.SDL_SetRenderTarget(renderer, target)) return error.SDLTexture;
            // zig-audit: acknowledge discard
            // reason: Best-effort restoration keeps the original backend failure.
            errdefer _ = c.SDL_SetRenderTarget(renderer, previous_target);
            const target_pane: c.SDL_FRect = .{ .x = 0, .y = 0, .w = @floatFromInt(snapshot.surface.width), .h = @floatFromInt(snapshot.surface.height) };
            const full = self.content_revision == null or self.direct_context != snapshot.visual_context or self.direct_origin != snapshot.row_origin or self.direct_rows != snapshot.rows;
            if (full) {
                if (!c.SDL_SetRenderClipRect(renderer, null) or !c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 0) or !c.SDL_RenderClear(renderer)) return error.SDLTexture;
                try self.drawSnapshot(renderer, geometry, target_pane, snapshot, 0, snapshot.rows, false, null);
            } else {
                var row: u16 = 0;
                while (row < snapshot.rows) {
                    if (self.direct_generations[row] == snapshot.row_generations[row]) {
                        row += 1;
                        continue;
                    }
                    const first = row;
                    row += 1;
                    while (row < snapshot.rows and self.direct_generations[row] != snapshot.row_generations[row]) row += 1;
                    const row_clip: c.SDL_Rect = .{ .x = 0, .y = @intCast(@as(u32, first) * snapshot.cell_height), .w = snapshot.surface.width, .h = @intCast(@as(u32, row - first) * snapshot.cell_height) };
                    try self.drawSnapshot(renderer, geometry, target_pane, snapshot, first, row, false, row_clip);
                }
            }
            if (!c.SDL_SetRenderTarget(renderer, previous_target)) return error.SDLTexture;
            self.direct_context = snapshot.visual_context;
            self.direct_origin = snapshot.row_origin;
            self.direct_rows = snapshot.rows;
            @memcpy(self.direct_generations[0..snapshot.rows], snapshot.row_generations[0..snapshot.rows]);
            self.content_revision = snapshot.content_revision;
        }
        const clip = pixelClip(pane);
        const dest: c.SDL_FRect = .{ .x = pane.x, .y = pane.y, .w = @floatFromInt(snapshot.surface.width), .h = @floatFromInt(snapshot.surface.height) };
        if (!c.SDL_SetRenderClipRect(renderer, &clip) or !c.SDL_RenderTexture(renderer, target, null, &dest)) return error.SDLTexture;
        try self.drawSelection(renderer, pane, value);
        switch (cursor) {
            .hidden => {},
            .shown => if (motion) |visual| {
                try self.drawDirectMovingCursor(renderer, geometry, pane, snapshot, visual);
            } else if (snapshot.cursor) |command| {
                try self.drawCommands(renderer, geometry, pane, &.{command});
                try self.drawCommands(renderer, geometry, pane, snapshot.cursor_ink);
            },
            .outline => if (snapshot.cursor_cell) |rect| if (snapshot.cursor) |command| {
                const color = command.solid.color;
                const width = @min(rect.width, outline_pixels);
                const height = @min(rect.height, outline_pixels);
                const commands = [_]render.Command{
                    .{ .solid = .{ .rect = .{ .x = rect.x, .y = rect.y, .width = rect.width, .height = height }, .color = color } },
                    .{ .solid = .{ .rect = .{ .x = rect.x, .y = rect.y + @as(i32, rect.height - height), .width = rect.width, .height = height }, .color = color } },
                    .{ .solid = .{ .rect = .{ .x = rect.x, .y = rect.y, .width = width, .height = rect.height }, .color = color } },
                    .{ .solid = .{ .rect = .{ .x = rect.x + @as(i32, rect.width - width), .y = rect.y, .width = width, .height = rect.height }, .color = color } },
                };
                try self.drawCommands(renderer, geometry, pane, &commands);
            },
        }
        if (!c.SDL_SetRenderClipRect(renderer, null)) return error.SDLClip;
        if (!c.SDL_SetRenderScale(renderer, previous_x, previous_y)) return error.SDLScale;
    }

    fn drawDirectMovingCursor(self: *Canvas, renderer: *c.SDL_Renderer, geometry: *Geometry, pane: c.SDL_FRect, snapshot: *const @import("howl_vt_output").Snapshot, visual: cursor_effects.Visual) !void {
        const cell = snapshot.cursor_cell orelse return;
        const body = (snapshot.cursor orelse return).solid;
        const ink = snapshot.cursor_text_color orelse return;
        std.debug.assert(visual.ghost_count <= visual.ghosts.len);
        var ghosts: [4]render.Command = undefined;
        for (0..visual.ghost_count) |index| {
            const ghost = visual.ghosts[visual.ghost_count - 1 - index];
            var color = body.color;
            color.a = @intCast((@as(u16, color.a) * ghost.alpha + 127) / 255);
            ghosts[index] = .{ .solid = .{ .rect = cursorBody(body.rect, cell, ghost.rect), .color = color } };
        }
        if (visual.ghost_count != 0) try self.drawCommands(renderer, geometry, pane, ghosts[0..visual.ghost_count]);
        const painted = stretchedBody(cursorBody(body.rect, cell, visual.rect), visual.stretch, snapshot.surface);
        try self.drawCommands(renderer, geometry, pane, &.{.{ .solid = .{ .rect = painted, .color = body.color } }});
        if (snapshot.cursor_shape != .block and std.meta.eql(visual.stretch, [2]i32{ 0, 0 })) return;
        const color_id = if (snapshot.color_resource) |resource| resource.resource else null;
        try beginCommands(renderer, geometry);
        // VT clips each row's ink to that row, so only intersected rows can contribute.
        const first: usize = @intCast(@divFloor(painted.y, snapshot.cell_height));
        const end = @min(@as(usize, snapshot.rows), (@as(usize, @intCast(painted.y)) + painted.height - 1) / snapshot.cell_height + 1);
        for (first..end) |row| for (snapshot.glyphs[row]) |source| {
            var command = source;
            const y: i32 = @intCast(row * snapshot.cell_height);
            switch (command) {
                .alpha_mask => |*mask| {
                    mask.destination.y += y;
                    mask.clip.y += y;
                },
                .rgba => |*image| {
                    image.destination.y += y;
                    image.clip.y += y;
                },
                .solid => continue,
            }
            const replay = (try render.CursorRows.recolor(command, painted, ink, color_id)) orelse continue;
            try self.appendCommand(renderer, geometry, pane, pixelClip(pane), replay);
        };
        try geometry.finish(renderer);
    }

    fn drawMovingCursor(self: *Canvas, renderer: *c.SDL_Renderer, geometry: *Geometry, pane: c.SDL_FRect, value: instance.PublishedFrame, visual: cursor_effects.Visual) !void {
        const overlay = value.cursor orelse return;
        const suffix = value.commands[value.content_command_count..];
        if (suffix.len == 0) return;
        std.debug.assert(suffix[0] == .solid and visual.ghost_count <= visual.ghosts.len);
        var ghosts: [4]render.Command = undefined;
        for (0..visual.ghost_count) |index| {
            const ghost = visual.ghosts[visual.ghost_count - 1 - index];
            var color = suffix[0].solid.color;
            color.a = @intCast((@as(u16, color.a) * ghost.alpha + 127) / 255);
            ghosts[index] = .{ .solid = .{ .rect = cursorBody(suffix[0].solid.rect, overlay.rect, ghost.rect), .color = color } };
        }
        if (visual.ghost_count != 0) try self.drawCommands(renderer, geometry, pane, ghosts[0..visual.ghost_count]);
        const body = cursorBody(suffix[0].solid.rect, overlay.rect, visual.rect);
        const painted_rect = stretchedBody(body, visual.stretch, value.surface);
        const painted: render.Command = .{ .solid = .{ .rect = painted_rect, .color = suffix[0].solid.color } };
        try self.drawCommands(renderer, geometry, pane, &.{painted});
        if (overlay.shape != .block and std.meta.eql(visual.stretch, [2]i32{ 0, 0 })) return;
        const content = value.commands[0..value.content_command_count];
        if (self.cursor_index_revision != value.content_revision) {
            try self.cursor_rows.build(render.Command, content, value.surface, value.cell_size.height, overlay.color_resource);
            self.cursor_index_revision = value.content_revision;
        }
        for (self.cursor_rows.candidates(render.Command, content, painted_rect)) |command| {
            const replay = (try render.CursorRows.recolor(command, painted_rect, overlay.text_color, overlay.color_resource)) orelse continue;
            try self.appendCommand(renderer, geometry, pane, pixelClip(pane), replay);
        }
        try geometry.finish(renderer);
    }

    fn drawSelection(self: *const Canvas, renderer: *c.SDL_Renderer, pane: c.SDL_FRect, value: @import("frame_info.zig").Info) !void {
        // Selection is a transient overlay, below the cursor and outside the
        // retained content texture. Its spans belong to this exact frame.
        if (self.selection_paint.rows == 0) return;
        const rows = value.surface.height / value.cell_size.height;
        const columns = value.surface.width / value.cell_size.width;
        if (!c.SDL_SetRenderDrawColor(renderer, 180, 180, 180, 100)) return error.SDLGeometry;
        for (self.selection_paint.spans[0..@min(self.selection_paint.spans.len, @min(self.selection_paint.rows, rows))], 0..) |span, row| if (span) |range| {
            if (range.last < range.first or range.first >= columns) continue;
            const last = @min(range.last, columns - 1);
            const rect: c.SDL_FRect = .{
                .x = pane.x + @as(f32, @floatFromInt(@as(u32, range.first) * value.cell_size.width)),
                .y = pane.y + @as(f32, @floatFromInt(row * value.cell_size.height)),
                .w = @floatFromInt(@as(u32, last - range.first + 1) * value.cell_size.width),
                .h = @floatFromInt(value.cell_size.height),
            };
            if (!c.SDL_RenderFillRect(renderer, &rect)) return error.SDLGeometry;
        };
    }

    /// Discards backend content pixels; the next draw reconstructs from the held frame.
    pub fn invalidateContent(self: *Canvas) void {
        if (self.content) |target| c.SDL_DestroyTexture(target);
        self.content = null;
        self.invalidateContentRevision();
    }

    // A failed draw may have this texture bound; retire its validity, not storage.
    fn invalidateContentRevision(self: *Canvas) void {
        self.content_revision = null;
        self.direct_context = null;
        self.cursor_index_revision = null;
        self.cursor_rows.ready = false;
    }

    fn beginCommands(renderer: *c.SDL_Renderer, geometry: *Geometry) !void {
        // Retire preceding UI/target commands, including a failed partial pass.
        if (!c.SDL_FlushRenderer(renderer)) return error.SDLGeometry;
        geometry.count = 0;
        geometry.queued_quads = 0;
    }

    /// Draws one flat final-command pass. Clear and redraw the target after failure.
    pub fn drawCommands(self: *Canvas, renderer: *c.SDL_Renderer, geometry: *Geometry, pane: c.SDL_FRect, commands: []const render.Command) !void {
        const pane_clip = pixelClip(pane);
        try beginCommands(renderer, geometry);
        for (commands) |command| try self.appendCommand(renderer, geometry, pane, pane_clip, command);
        try geometry.finish(renderer);
    }

    /// Draws a bounded range directly from one held VT output snapshot.
    /// A failed pass invalidates retained content; callers must clear and redraw.
    pub fn drawSnapshot(
        self: *Canvas,
        renderer: *c.SDL_Renderer,
        geometry: *Geometry,
        pane: c.SDL_FRect,
        snapshot: *const @import("howl_vt_output").Snapshot,
        first: u16,
        end: u16,
        show_cursor: bool,
        device_clip: ?c.SDL_Rect,
    ) !void {
        if (first > end or end > snapshot.rows) return error.InvalidRows;
        const pane_clip = pixelClip(pane);
        var visible = pane_clip;
        if (device_clip) |clip| {
            if (!c.SDL_GetRectIntersection(&pane_clip, &clip, &visible)) return;
        }
        errdefer self.invalidateContentRevision();
        try beginCommands(renderer, geometry);
        try self.appendCommand(renderer, geometry, pane, visible, snapshot.background);
        inline for (.{ "backgrounds", "decorations", "glyphs" }) |phase| {
            for (first..end) |row| {
                var origin = pane;
                origin.y += @as(f32, @floatFromInt(row * snapshot.cell_height));
                for (@field(snapshot, phase)[row]) |command|
                    try self.appendCommand(renderer, geometry, origin, visible, command);
            }
        }
        if (show_cursor) if (snapshot.cursor) |command| {
            try self.appendCommand(renderer, geometry, pane, visible, command);
            for (snapshot.cursor_ink) |ink| try self.appendCommand(renderer, geometry, pane, visible, ink);
        };
        try geometry.finish(renderer);
    }

    fn appendCommand(self: *Canvas, renderer: *c.SDL_Renderer, geometry: *Geometry, pane: c.SDL_FRect, pane_clip: c.SDL_Rect, command: render.Command) !void {
        switch (command) {
            .solid => |solid| try geometry.append(renderer, null, pane_clip, destination(solid.rect, pane), .{ .x = 0, .y = 0, .w = 0, .h = 0 }, solid.color),
            .alpha_mask => |mask| {
                const texture = self.find(mask.resource.resource) orelse return error.MissingTexture;
                const dest = destination(mask.destination, pane);
                const clip = commandClip(mask.destination, mask.clip, pane, pane_clip) orelse return;
                const src: render.SourceRect = mask.resource.source orelse .{ .x = 0, .y = 0, .width = mask.resource.size.width, .height = mask.resource.size.height };
                const width: f32 = @floatFromInt(mask.resource.size.width);
                const height: f32 = @floatFromInt(mask.resource.size.height);
                try geometry.append(renderer, texture, clip, dest, .{
                    .x = @as(f32, @floatFromInt(src.x)) / width,
                    .y = @as(f32, @floatFromInt(src.y)) / height,
                    .w = @as(f32, @floatFromInt(src.width)) / width,
                    .h = @as(f32, @floatFromInt(src.height)) / height,
                }, mask.color);
            },
            .rgba => |image| {
                try geometry.flush(renderer);
                const texture = self.find(image.resource.resource) orelse return error.MissingTexture;
                const clip = commandClip(image.destination, image.clip, pane, pane_clip) orelse return;
                const src: render.SourceRect = image.resource.source orelse .{ .x = 0, .y = 0, .width = image.resource.size.width, .height = image.resource.size.height };
                const source: c.SDL_FRect = .{ .x = @floatFromInt(src.x), .y = @floatFromInt(src.y), .w = @floatFromInt(src.width), .h = @floatFromInt(src.height) };
                const dest = destination(image.destination, pane);
                try geometry.reserve(renderer, 1);
                if (!c.SDL_SetRenderClipRect(renderer, &clip) or
                    !c.SDL_RenderTexture(renderer, texture, &source, &dest)) return error.SDLTexture;
                geometry.queued_quads += 1;
            },
        }
    }

    fn find(self: *const Canvas, resource: render.ResourceRef) ?*c.SDL_Texture {
        for (self.textures[0..self.count]) |texture| {
            if (texture.residency.resource.resource == resource.resource and
                texture.residency.resource.generation == resource.generation) return texture.texture;
        }
        return null;
    }

    fn remove(self: *Canvas, resource: render.ResourceRef, exact: bool) void {
        for (self.textures[0..self.count], 0..) |texture, index| {
            if (texture.residency.resource.resource != resource.resource or
                (exact and texture.residency.resource.generation != resource.generation)) continue;
            c.SDL_DestroyTexture(texture.texture);
            self.count -= 1;
            self.textures[index] = self.textures[self.count];
            return;
        }
    }

    fn clearTextures(self: *Canvas) void {
        self.invalidateContent();
        for (self.textures[0..self.count]) |texture| c.SDL_DestroyTexture(texture.texture);
        self.count = 0;
    }
};

fn cursorBody(body: render.Rect, origin: render.Rect, rect: render.Rect) render.Rect {
    return .{ .x = body.x + rect.x - origin.x, .y = body.y + rect.y - origin.y, .width = body.width, .height = body.height };
}

fn stretchedBody(body: render.Rect, tail: [2]i32, surface: render.Size) render.Rect {
    const left = @max(0, @min(body.x, body.x + tail[0]));
    const top = @max(0, @min(body.y, body.y + tail[1]));
    const right = @min(@as(i32, surface.width), @max(body.x, body.x + tail[0]) + @as(i32, body.width));
    const bottom = @min(@as(i32, surface.height), @max(body.y, body.y + tail[1]) + @as(i32, body.height));
    std.debug.assert(right > left and bottom > top);
    return .{ .x = left, .y = top, .width = @intCast(right - left), .height = @intCast(bottom - top) };
}

fn destination(rect: render.Rect, pane: c.SDL_FRect) c.SDL_FRect {
    return .{
        .x = pane.x + @as(f32, @floatFromInt(rect.x)),
        .y = pane.y + @as(f32, @floatFromInt(rect.y)),
        .w = @as(f32, @floatFromInt(rect.width)),
        .h = @as(f32, @floatFromInt(rect.height)),
    };
}

fn pixelClip(rect: c.SDL_FRect) c.SDL_Rect {
    const x: c_int = @intFromFloat(@floor(rect.x));
    const y: c_int = @intFromFloat(@floor(rect.y));
    return .{ .x = x, .y = y, .w = @as(c_int, @intFromFloat(@ceil(rect.x + rect.w))) - x, .h = @as(c_int, @intFromFloat(@ceil(rect.y + rect.h))) - y };
}

fn commandClip(ink: render.Rect, clip: render.Rect, pane: c.SDL_FRect, pane_clip: c.SDL_Rect) ?c.SDL_Rect {
    if (contained(ink, clip)) {
        if (pane_clip.w <= 0 or pane_clip.h <= 0) return null;
        return pane_clip;
    }
    const requested = pixelClip(destination(clip, pane));
    var visible: c.SDL_Rect = undefined;
    if (!c.SDL_GetRectIntersection(&requested, &pane_clip, &visible)) return null;
    return visible;
}

fn rectEqual(a: c.SDL_Rect, b: c.SDL_Rect) bool {
    return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h;
}

test "fractional pane clips cover edge pixels without crossing the integer pane bounds" {
    const clip = pixelClip(.{ .x = 10.2, .y = 5.8, .w = 15.4, .h = 20.1 });
    try std.testing.expectEqual(c.SDL_Rect{ .x = 10, .y = 5, .w = 16, .h = 21 }, clip);
}

fn contained(a: render.Rect, b: render.Rect) bool {
    return a.x >= b.x and a.y >= b.y and
        @as(i64, a.x) + a.width <= @as(i64, b.x) + b.width and
        @as(i64, a.y) + a.height <= @as(i64, b.y) + b.height;
}

test "command clipping equals SDL for contained clipped fractional negative and empty panes" {
    for (0..10000) |i| {
        const pane: c.SDL_FRect = .{
            .x = @as(f32, @floatFromInt(@as(i32, @intCast(i % 31)) - 15)) + @as(f32, @floatFromInt(i % 4)) / 4,
            .y = @as(f32, @floatFromInt(@as(i32, @intCast(i % 23)) - 11)) + @as(f32, @floatFromInt(i % 3)) / 3,
            .w = @floatFromInt(if (i % 17 == 0) @as(usize, 0) else 1 + i % 257),
            .h = @floatFromInt(if (i % 19 == 0) @as(usize, 0) else 1 + i % 193),
        };
        const pane_clip = pixelClip(pane);
        const ink: render.Rect = .{ .x = @as(i32, @intCast(i % 43)) - 21, .y = @as(i32, @intCast(i % 37)) - 18, .width = @intCast(2 + i % 19), .height = @intCast(2 + i % 29) };
        const clip: render.Rect = switch (i % 3) {
            0 => ink,
            1 => .{ .x = ink.x + 1, .y = ink.y + 1, .width = ink.width - 1, .height = ink.height - 1 },
            else => .{ .x = 0, .y = 0, .width = 320, .height = 200 },
        };
        const requested = if (contained(ink, clip)) pane_clip else pixelClip(destination(clip, pane));
        var intersection: c.SDL_Rect = undefined;
        const expected: ?c.SDL_Rect = if (c.SDL_GetRectIntersection(&requested, &pane_clip, &intersection)) intersection else null;
        try std.testing.expectEqualDeep(expected, commandClip(ink, clip, pane, pane_clip));
    }
}

test "overhanging commands keep their exact clip, contained quads share the pane clip" {
    const clip: render.Rect = .{ .x = -3, .y = 7, .width = 12, .height = 14 };
    try std.testing.expect(contained(.{ .x = -3, .y = 7, .width = 12, .height = 14 }, clip));
    try std.testing.expect(!contained(.{ .x = -4, .y = 7, .width = 12, .height = 14 }, clip));
    try std.testing.expect(!contained(.{ .x = -3, .y = 7, .width = 13, .height = 14 }, clip));
}

test "failed backend allocation retires its candidate; a fresh presentation generation rebuilds exact resources" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const presentation: instance.PresentationConfig = .{
        .text = .{ .private = .{ .regular = .{ .path = .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 15 } } } } },
        .box_drawing = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
        .shape_cache = .{ .entry_capacity = 32, .scalar_capacity = 128, .glyph_capacity = 128, .max_sequence_scalars = 16 },
        .atlas = .{ .width = 256, .height = 256, .entry_capacity = 128 },
        .shaped_capacity = 128,
        .raster_bytes = 256 * 256,
        .command_capacity = 256,
        .command_limit = instance.render.limits.maximum_frame_commands,
    };
    const owner = try terminal.Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf 'HELLO\\033]0;READY\\007'; read line; printf '\\033]0;CONTINUED\\007'; sleep 30",
        .rows = 4,
        .columns = 20,
    }, presentation, c.SDL_RegisterEvents(1), true);
    defer owner.destroy();
    var stage: []const u8 = "canonical READY";
    var accepted_generation: u64 = 0;
    errdefer std.debug.print("backend recovery failure at {s}; accepted generation {d}, canonical {any}, presentation {any}\n", .{ stage, accepted_generation, owner.snapshot().failure, owner.snapshot().presentation_failure });
    var attempts: u16 = 0;
    while (attempts < 5000) : (attempts += 1) {
        const status = owner.snapshot();
        if (std.mem.eql(u8, status.title[0..status.title_len], "READY")) break;
        if (status.failure) |failure| return failure;
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    if (attempts == 5000) return error.Timeout;
    const surface = c.SDL_CreateSurface(250, 100, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    // One RGBA copy of this fixed alpha plane must fit without geometric slack.
    const conversion = try std.testing.allocator.alloc(u8, 256 * 256 * 4);
    defer std.testing.allocator.free(conversion);
    var exact = std.heap.FixedBufferAllocator.init(conversion);
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var backend = Canvas.init(failing.allocator());
    defer backend.deinit();
    owner.requestFrame();
    stage = "injected backend allocation";
    var failed = false;
    attempts = 0;
    while (!failed and attempts < 5000) : (attempts += 1) {
        backend.update(renderer, owner) catch |failure| {
            try std.testing.expectEqual(error.OutOfMemory, failure);
            failed = true;
        };
        if (!failed) try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(failed);
    stage = "canonical CONTINUED after rejected backend";
    try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
    attempts = 0;
    while (attempts < 5000) : (attempts += 1) {
        const status = owner.snapshot();
        if (std.mem.eql(u8, status.title[0..status.title_len], "CONTINUED")) break;
        if (status.failure) |failure| return failure;
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    if (attempts == 5000) return error.Timeout;
    backend.deinit();
    backend = Canvas.init(exact.allocator());
    stage = "font reconfiguration";
    const configured = try owner.reconfigure(presentation, null);
    try std.testing.expect(configured.cell_size.width > 0);
    attempts = 0;
    while (backend.frame() == null and attempts < 5000) : (attempts += 1) {
        try backend.update(renderer, owner);
        if (backend.frame() == null) try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    stage = "fresh backend generation";
    const accepted = backend.frame() orelse return error.MissingFrame;
    try std.testing.expectEqual(conversion.len, backend.converted.items.len);
    try std.testing.expectEqual(conversion.len, backend.converted.capacity);
    accepted_generation = accepted.presentation_generation;
    try std.testing.expect(accepted.presentation_generation > 1);
    const geometry = try std.testing.allocator.create(Geometry);
    defer std.testing.allocator.destroy(geometry);
    geometry.* = .{};
    try backend.draw(renderer, geometry, .{ .x = 0, .y = 0, .w = 250, .h = 100 }, 1, .shown, 1, null);
    try std.testing.expect(c.SDL_RenderPresent(renderer));
    try std.testing.expectEqual(@as(?terminal.Failure, null), owner.snapshot().failure);
}

test "repeated alternate-screen blank and text cuts retain exact backend residency" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const presentation: instance.PresentationConfig = .{
        .text = .{ .private = .{ .regular = .{ .path = .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 15 } } } } },
        .box_drawing = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
        .shape_cache = .{ .entry_capacity = 32, .scalar_capacity = 128, .glyph_capacity = 128, .max_sequence_scalars = 16 },
        .atlas = .{ .width = 256, .height = 256, .entry_capacity = 128 },
        .shaped_capacity = 128,
        .raster_bytes = 256 * 256,
        .command_capacity = 256,
        .command_limit = instance.render.limits.maximum_frame_commands,
    };
    const owner = try terminal.Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf 'HELLO\\033]0;WARM\\007'; read line; printf '\\033[1;1H\\033]0;READY\\007'; i=0; while [ \"$i\" -lt 4 ]; do read line; printf '\\033[?1049h\\033[2J\\033[H\\033]0;BLANK\\007'; read line; printf 'HELLO\\033]0;TEXT\\007'; read line; printf '\\033[2J\\033[H\\033]0;EXIT-BLANK\\007'; read line; printf '\\033[?1049l\\033]0;MAIN\\007'; i=$((i+1)); done; read line",
        .rows = 4,
        .columns = 20,
    }, presentation, 0, true);
    defer owner.destroy();
    const surface = c.SDL_CreateSurface(250, 100, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    var backend = Canvas.init(std.testing.allocator);
    defer backend.deinit();
    const geometry = try std.testing.allocator.create(Geometry);
    defer std.testing.allocator.destroy(geometry);
    geometry.* = .{};
    var previous_revision: u64 = 0;
    for (0..18) |step| {
        if (step != 0) try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
        const title = if (step == 0) "WARM" else if (step == 1) "READY" else ([_][]const u8{ "BLANK", "TEXT", "EXIT-BLANK", "MAIN" })[(step - 2) % 4];
        var attempts: u16 = 0;
        while (attempts < 5000) : (attempts += 1) {
            try backend.update(renderer, owner);
            const status = owner.snapshot();
            if (status.failure) |failure| return failure;
            if (status.presentation_failure) |failure| return failure;
            if (std.mem.eql(u8, status.title[0..status.title_len], title)) {
                if (backend.frame()) |value| if (value.terminal_revision == status.revision and value.terminal_revision != previous_revision) break;
            }
            owner.requestFrame();
            try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
        }
        if (attempts == 5000) return error.Timeout;
        const value = backend.lease.?.value;
        previous_revision = value.terminal_revision;
        const blank = step >= 2 and (step - 2) % 2 == 0;
        try std.testing.expectEqual(step >= 2 and (step - 2) % 4 != 3, value.alternate_screen);
        errdefer std.debug.print("alternate texture failure at step {d}, title {s}, uploads {d}, removals {d}, textures {d}\n", .{ step, title, value.uploads.len, value.removals.len, backend.count });
        try backend.draw(renderer, geometry, .{ .x = 0, .y = 0, .w = 250, .h = 100 }, 1, .shown, 1, null);
        try std.testing.expect(c.SDL_RenderPresent(renderer));
        try std.testing.expectEqual(@as(usize, if (blank) 0 else 1), backend.count);
        var retained: [250 * 100][3]u8 = undefined;
        const visible_width = @min(value.surface.width, 250);
        const visible_height = @min(value.surface.height, 100);
        for (0..visible_height) |y| for (0..visible_width) |x| {
            try std.testing.expect(c.SDL_ReadSurfacePixel(surface, @intCast(x), @intCast(y), &retained[y * visible_width + x][0], &retained[y * visible_width + x][1], &retained[y * visible_width + x][2], null));
        };
        try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255));
        try std.testing.expect(c.SDL_RenderClear(renderer));
        try backend.drawCommands(renderer, geometry, .{ .x = 0, .y = 0, .w = 250, .h = 100 }, value.commands);
        try std.testing.expect(c.SDL_RenderPresent(renderer));
        for (0..visible_height) |y| for (0..visible_width) |x| {
            var pixel: [3]u8 = undefined;
            try std.testing.expect(c.SDL_ReadSurfacePixel(surface, @intCast(x), @intCast(y), &pixel[0], &pixel[1], &pixel[2], null));
            try std.testing.expectEqual(retained[y * visible_width + x], pixel);
        };
        owner.requestFrame();
    }
}

test "fractional SDL projection preserves every pixel of joined generated blocks and rules" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const presentation: instance.PresentationConfig = .{
        .text = .{ .private = .{ .regular = .{ .path = .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 15 } } } } },
        .box_drawing = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
        .shape_cache = .{ .entry_capacity = 32, .scalar_capacity = 128, .glyph_capacity = 128, .max_sequence_scalars = 16 },
        .atlas = .{ .width = 256, .height = 256, .entry_capacity = 128 },
        .shaped_capacity = 128,
        .raster_bytes = 256 * 256,
        .command_capacity = 256,
        .command_limit = instance.render.limits.maximum_frame_commands,
    };
    const owner = try terminal.Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "printf '\\033[?25l\\033[38;2;255;255;255m████\\r\\n████\\r\\n││││\\r\\n││││\\r\\n────\\r\\n────\\033]0;BLOCKS-READY\\007'; read line",
        .rows = 6,
        .columns = 4,
    }, presentation, 0, true);
    defer owner.destroy();
    const surface = c.SDL_CreateSurface(160, 160, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    var backend = Canvas.init(std.testing.allocator);
    defer backend.deinit();
    const geometry = try std.testing.allocator.create(Geometry);
    defer std.testing.allocator.destroy(geometry);
    geometry.* = .{};
    var attempts: u16 = 0;
    while (attempts < 5000) : (attempts += 1) {
        try backend.update(renderer, owner);
        const status = owner.snapshot();
        if (std.mem.eql(u8, status.title[0..status.title_len], "BLOCKS-READY")) {
            if (backend.frame()) |frame| if (frame.terminal_revision == status.revision) break;
        }
        if (status.failure) |failure| return failure;
        owner.requestFrame();
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    if (attempts == 5000) return error.Timeout;
    const frame = backend.lease.?.value;
    try std.testing.expect(frame.surface.width <= 160 and frame.surface.height <= 160);
    var reference: [160 * 160][3]u8 = undefined;
    for ([_]f32{ 1, 1.25, 1.5, 1.6, 1.7, 2 }) |scale| {
        try std.testing.expect(c.SDL_SetRenderScale(renderer, scale, scale));
        try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255));
        try std.testing.expect(c.SDL_RenderClear(renderer));
        try backend.draw(renderer, geometry, .{
            .x = 7 / scale,
            .y = 11 / scale,
            .w = @as(f32, @floatFromInt(frame.surface.width)) / scale,
            .h = @as(f32, @floatFromInt(frame.surface.height)) / scale,
        }, scale, .shown, 1, null);
        try std.testing.expect(c.SDL_RenderPresent(renderer));
        var restored_x: f32 = 0;
        var restored_y: f32 = 0;
        try std.testing.expect(c.SDL_GetRenderScale(renderer, &restored_x, &restored_y));
        try std.testing.expectEqual(scale, restored_x);
        try std.testing.expectEqual(scale, restored_y);
        for (0..frame.surface.height) |y| for (0..frame.surface.width) |x| {
            var red: u8 = 0;
            var green: u8 = 0;
            var blue: u8 = 0;
            try std.testing.expect(c.SDL_ReadSurfacePixel(surface, @intCast(x + 7), @intCast(y + 11), &red, &green, &blue, null));
            const pixel = [3]u8{ red, green, blue };
            const at = y * frame.surface.width + x;
            if (scale == 1) reference[at] = pixel;
            const solid_rows = y < frame.surface.height / 3;
            if ((solid_rows and (red != 255 or green != 255 or blue != 255)) or
                !std.mem.eql(u8, &reference[at], &pixel))
            {
                std.debug.print("generated block seam scale={d} pixel=({d},{d}) rgb=({d},{d},{d})\n", .{ scale, x, y, red, green, blue });
                return error.GeneratedBlockSeam;
            }
        };
    }
    // Compare the retained content/cursor composition with the original full
    // command draw, including pane translation and the same physical lattice.
    try std.testing.expect(c.SDL_SetRenderScale(renderer, 1, 1));
    try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255));
    try std.testing.expect(c.SDL_RenderClear(renderer));
    try backend.drawCommands(renderer, geometry, .{
        .x = 7,
        .y = 11,
        .w = @floatFromInt(frame.surface.width),
        .h = @floatFromInt(frame.surface.height),
    }, frame.commands);
    try std.testing.expect(c.SDL_RenderPresent(renderer));
    for (0..frame.surface.height) |y| for (0..frame.surface.width) |x| {
        var red: u8 = 0;
        var green: u8 = 0;
        var blue: u8 = 0;
        try std.testing.expect(c.SDL_ReadSurfacePixel(surface, @intCast(x + 7), @intCast(y + 11), &red, &green, &blue, null));
        try std.testing.expectEqual(reference[y * frame.surface.width + x], [3]u8{ red, green, blue });
    };
    try std.testing.expect(c.SDL_SetRenderScale(renderer, 2, 2));
    backend.clearTextures();
    try std.testing.expectError(error.MissingTexture, backend.draw(renderer, geometry, .{ .x = 0, .y = 0, .w = 80, .h = 80 }, 2, .shown, 1, null));
    var restored_x: f32 = 0;
    var restored_y: f32 = 0;
    try std.testing.expect(c.SDL_GetRenderScale(renderer, &restored_x, &restored_y));
    try std.testing.expectEqual(@as(f32, 2), restored_x);
    try std.testing.expectEqual(@as(f32, 2), restored_y);
    try std.testing.expect(!c.SDL_RenderClipEnabled(renderer));
}

test "SDL queue budget admits its exact limit and retires before the next packet" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    const surface = c.SDL_CreateSurface(8, 8, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    const geometry = try std.testing.allocator.create(Geometry);
    defer std.testing.allocator.destroy(geometry);
    geometry.* = .{};
    geometry.queued_quads = batch_quads - 1;
    try geometry.reserve(renderer, 1);
    try std.testing.expectEqual(batch_quads - 1, geometry.queued_quads);
    geometry.queued_quads += 1;
    try geometry.reserve(renderer, 1);
    try std.testing.expectEqual(@as(usize, 0), geometry.queued_quads);
    geometry.queued_quads = 1;
    try geometry.reserve(renderer, batch_quads);
    try std.testing.expectEqual(@as(usize, 0), geometry.queued_quads);
    geometry.queued_quads = batch_quads;
    try geometry.finish(renderer);
    try std.testing.expectEqual(@as(usize, 0), geometry.queued_quads);
}

test "cursor shapes blink and outline above selection at fractional scales without replacing texture or frame" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const presentation: instance.PresentationConfig = .{
        .text = .{ .private = .{ .regular = .{ .path = .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 15 } } } } },
        .box_drawing = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
        .shape_cache = .{ .entry_capacity = 32, .scalar_capacity = 128, .glyph_capacity = 128, .max_sequence_scalars = 16 },
        .atlas = .{ .width = 256, .height = 256, .entry_capacity = 128 },
        .shaped_capacity = 128,
        .raster_bytes = 256 * 256,
        .command_capacity = 256,
        .command_limit = instance.render.limits.maximum_frame_commands,
    };
    const owner = try terminal.Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf 'W\\033[1;1H\\033]0;CURSOR-READY\\007'; while read line; do printf '\\033[%s q' \"$line\"; done",
        .rows = 2,
        .columns = 4,
        .color_defaults = .{
            .foreground = .{ .r = 245, .g = 245, .b = 245 },
            .background = .{ .r = 10, .g = 20, .b = 30 },
            .cursor = .{ .r = 240, .g = 20, .b = 30 },
            .cursor_text = .{ .r = 20, .g = 240, .b = 30 },
        },
    }, presentation, 0, true);
    defer owner.destroy();
    const surface = c.SDL_CreateSurface(160, 160, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    try std.testing.expect(c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND));
    var backend = Canvas.init(std.testing.allocator);
    defer backend.deinit();
    const geometry = try std.testing.allocator.create(Geometry);
    defer std.testing.allocator.destroy(geometry);
    geometry.* = .{};
    var ready_attempts: u16 = 0;
    while (ready_attempts < 5000) : (ready_attempts += 1) {
        try backend.update(renderer, owner);
        const status = owner.snapshot();
        if (status.failure) |failure| return failure;
        if (std.mem.eql(u8, status.title[0..status.title_len], "CURSOR-READY")) {
            if (backend.frame()) |frame| if (frame.terminal_revision == status.revision) break;
        }
        owner.requestFrame();
        try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
    }
    if (ready_attempts == 5000) return error.Timeout;
    var retained_revision: ?u64 = null;
    var retained_texture: ?*c.SDL_Texture = null;
    var pixels: [160 * 160][3]u8 = undefined;
    for ([_][]const u8{ "2", "1", "4", "3", "6", "5" }) |style| {
        const before_revision = owner.snapshot().revision;
        var input: [2]u8 = .{ style[0], '\n' };
        try owner.submit(.{ .input = .{ .bytes = &input } });
        var attempts: u16 = 0;
        while (attempts < 5000) : (attempts += 1) {
            try backend.update(renderer, owner);
            const status = owner.snapshot();
            if (status.failure) |failure| return failure;
            if (status.revision > before_revision) {
                if (backend.frame()) |frame| if (frame.terminal_revision == status.revision) break;
            }
            owner.requestFrame();
            try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
        }
        if (attempts == 5000) return error.Timeout;
        const frame = backend.lease.?.value;
        try std.testing.expectEqual((style[0] - '0') % 2 == 1, frame.cursor_blink);
        try std.testing.expect(frame.content_command_count < frame.commands.len);
        if (retained_revision) |revision| try std.testing.expectEqual(revision, frame.content_revision) else retained_revision = frame.content_revision;
        const pane: c.SDL_FRect = .{ .x = 0, .y = 0, .w = @floatFromInt(frame.surface.width), .h = @floatFromInt(frame.surface.height) };
        for ([_]CursorDisplay{ .shown, .hidden, .outline }) |mode| for ([_]f32{ 1, 1.25, 1.6, 2 }) |scale| for ([_]bool{ false, true }) |selected| for ([_]u8{ 1, 3, 16 }) |outline| {
            backend.selection_paint = .{ .rows = 2 };
            if (selected) backend.selection_paint.spans[0] = .{ .first = 0, .last = 1 };
            try std.testing.expect(c.SDL_SetRenderScale(renderer, scale, scale));
            try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255));
            try std.testing.expect(c.SDL_RenderClear(renderer));
            try backend.draw(renderer, geometry, pane, scale, mode, outline, null);
            try std.testing.expect(c.SDL_RenderPresent(renderer));
            const target = backend.content.?;
            if (retained_texture) |previous| try std.testing.expectEqual(previous, target) else retained_texture = target;
            var green_ink: usize = 0;
            for (0..frame.surface.height) |y| for (0..frame.surface.width) |x| {
                const at = y * frame.surface.width + x;
                const pixel = &pixels[at];
                try std.testing.expect(c.SDL_ReadSurfacePixel(surface, @intCast(x), @intCast(y), &pixel[0], &pixel[1], &pixel[2], null));
                if (@as(u16, pixel[1]) > @as(u16, pixel[0]) + 50 and @as(u16, pixel[1]) > @as(u16, pixel[2]) + 50) green_ink += 1;
            };
            try std.testing.expect((green_ink != 0) == (mode == .shown and (style[0] == '1' or style[0] == '2')));
            try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255));
            try std.testing.expect(c.SDL_RenderClear(renderer));
            // Independent full-command oracle plus bounded physical outline edges.
            try std.testing.expect(c.SDL_SetRenderScale(renderer, 1, 1));
            try backend.drawCommands(renderer, geometry, pane, frame.commands[0..frame.content_command_count]);
            if (selected) {
                try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, 180, 180, 180, 100));
                const selected_rect: c.SDL_FRect = .{ .x = 0, .y = 0, .w = @floatFromInt(2 * frame.cell_size.width), .h = @floatFromInt(frame.cell_size.height) };
                try std.testing.expect(c.SDL_RenderFillRect(renderer, &selected_rect));
            }
            if (mode == .shown) try backend.drawCommands(renderer, geometry, pane, frame.commands[frame.content_command_count..]);
            try std.testing.expect(c.SDL_RenderPresent(renderer));
            for (0..frame.surface.height) |y| for (0..frame.surface.width) |x| {
                var actual: [3]u8 = undefined;
                try std.testing.expect(c.SDL_ReadSurfacePixel(surface, @intCast(x), @intCast(y), &actual[0], &actual[1], &actual[2], null));
                if (mode == .outline) {
                    const overlay = frame.cursor.?;
                    const r = overlay.rect;
                    const left: usize = @intCast(r.x);
                    const top: usize = @intCast(r.y);
                    if (x >= left and x < left + r.width and y >= top and y < top + r.height and
                        (x - left < @min(r.width, outline) or left + r.width - 1 - x < @min(r.width, outline) or
                            y - top < @min(r.height, outline) or top + r.height - 1 - y < @min(r.height, outline)))
                        actual = .{ overlay.color.r, overlay.color.g, overlay.color.b };
                }
                try std.testing.expectEqual(pixels[y * frame.surface.width + x], actual);
            };
            try std.testing.expectEqual(target, backend.content.?);
            try std.testing.expectEqual(frame.sequence, backend.frame().?.sequence);
            try std.testing.expectEqual(frame.content_revision, backend.content_revision.?);
        };
        for ([_]f32{ 1, 1.25, 1.6, 2 }) |scale| for ([_][2]i32{ .{ 1, 0 }, .{ @intCast(frame.cell_size.width / 2), 0 }, .{ @intCast(frame.cell_size.width), 0 }, .{ @intCast(frame.cell_size.width / 2), @intCast(frame.cell_size.height / 2) } }) |point| for ([_]bool{ false, true }) |selected| for (0..4) |effect| {
            const moving: render.Rect = .{ .x = point[0], .y = point[1], .width = frame.cursor.?.rect.width, .height = frame.cursor.?.rect.height };
            var visual: cursor_effects.Visual = .{ .rect = moving };
            if (effect == 1) visual.stretch = .{ -@as(i32, frame.cell_size.width), -@as(i32, frame.cell_size.height) };
            if (effect == 2) visual.stretch = .{ frame.cell_size.width, frame.cell_size.height };
            if (effect == 3) {
                visual.ghost_count = 4;
                for (&visual.ghosts, 0..) |*ghost, index| ghost.* = .{
                    .rect = .{ .x = @intCast(index * frame.cell_size.width), .y = frame.cell_size.height, .width = moving.width, .height = moving.height },
                    .alpha = @intCast(72 - index * 18),
                };
            }
            backend.selection_paint = .{ .rows = 2 };
            if (selected) backend.selection_paint.spans[0] = .{ .first = 0, .last = 1 };
            try std.testing.expect(c.SDL_SetRenderScale(renderer, scale, scale));
            try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255));
            try std.testing.expect(c.SDL_RenderClear(renderer));
            try backend.draw(renderer, geometry, pane, scale, .shown, 1, visual);
            try std.testing.expect(c.SDL_RenderPresent(renderer));
            for (0..frame.surface.height) |y| for (0..frame.surface.width) |x| {
                const pixel = &pixels[y * frame.surface.width + x];
                try std.testing.expect(c.SDL_ReadSurfacePixel(surface, @intCast(x), @intCast(y), &pixel[0], &pixel[1], &pixel[2], null));
            };
            // Independent whole-content oracle; only clips move, glyph destinations never do.
            try std.testing.expect(c.SDL_SetRenderScale(renderer, 1, 1));
            try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255));
            try std.testing.expect(c.SDL_RenderClear(renderer));
            try backend.drawCommands(renderer, geometry, pane, frame.commands[0..frame.content_command_count]);
            try backend.drawSelection(renderer, pane, @import("frame_info.zig").Info.fromLegacy(frame));
            for (0..visual.ghost_count) |index| {
                const ghost = visual.ghosts[visual.ghost_count - 1 - index];
                const original = frame.commands[frame.content_command_count].solid;
                const alpha: u8 = @intCast((@as(u16, original.color.a) * ghost.alpha + 127) / 255);
                try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, original.color.r, original.color.g, original.color.b, alpha));
                const ghost_rect: c.SDL_FRect = .{ .x = @floatFromInt(original.rect.x + ghost.rect.x), .y = @floatFromInt(original.rect.y + ghost.rect.y), .w = @floatFromInt(original.rect.width), .h = @floatFromInt(original.rect.height) };
                try std.testing.expect(c.SDL_RenderFillRect(renderer, &ghost_rect));
            }
            var solid = frame.commands[frame.content_command_count];
            solid.solid.rect.x += moving.x;
            solid.solid.rect.y += moving.y;
            if (effect == 1 or effect == 2) {
                const base: c.SDL_Rect = .{ .x = solid.solid.rect.x, .y = solid.solid.rect.y, .w = solid.solid.rect.width, .h = solid.solid.rect.height };
                var tail = base;
                tail.x += visual.stretch[0];
                tail.y += visual.stretch[1];
                var union_rect: c.SDL_Rect = undefined;
                try std.testing.expect(c.SDL_GetRectUnion(&base, &tail, &union_rect));
                const whole: c.SDL_Rect = .{ .x = 0, .y = 0, .w = frame.surface.width, .h = frame.surface.height };
                var clipped: c.SDL_Rect = undefined;
                try std.testing.expect(c.SDL_GetRectIntersection(&whole, &union_rect, &clipped));
                solid.solid.rect = .{ .x = clipped.x, .y = clipped.y, .width = @intCast(clipped.w), .height = @intCast(clipped.h) };
            }
            try backend.drawCommands(renderer, geometry, pane, &.{solid});
            if (frame.cursor.?.shape == .block or effect == 1 or effect == 2) {
                const cursor_clip: c.SDL_Rect = .{ .x = solid.solid.rect.x, .y = solid.solid.rect.y, .w = solid.solid.rect.width, .h = solid.solid.rect.height };
                for (frame.commands[0..frame.content_command_count]) |command| {
                    var replay = command;
                    switch (replay) {
                        .alpha_mask => |*ink| {
                            if (!ink.cursor_component) continue;
                            const original: c.SDL_Rect = .{ .x = ink.clip.x, .y = ink.clip.y, .w = ink.clip.width, .h = ink.clip.height };
                            var intersection: c.SDL_Rect = undefined;
                            if (!c.SDL_GetRectIntersection(&original, &cursor_clip, &intersection)) continue;
                            ink.clip = .{ .x = intersection.x, .y = intersection.y, .width = @intCast(intersection.w), .height = @intCast(intersection.h) };
                            ink.color = frame.cursor.?.text_color;
                        },
                        else => continue,
                    }
                    try backend.drawCommands(renderer, geometry, pane, &.{replay});
                }
            }
            try std.testing.expect(c.SDL_RenderPresent(renderer));
            for (0..frame.surface.height) |y| for (0..frame.surface.width) |x| {
                var actual: [3]u8 = undefined;
                try std.testing.expect(c.SDL_ReadSurfacePixel(surface, @intCast(x), @intCast(y), &actual[0], &actual[1], &actual[2], null));
                try std.testing.expectEqual(pixels[y * frame.surface.width + x], actual);
            };
            try std.testing.expectEqual(retained_texture.?, backend.content.?);
            try std.testing.expectEqual(frame.sequence, backend.frame().?.sequence);
            try std.testing.expectEqual(frame.content_revision, backend.content_revision.?);
        };
    }
}

test "pending drag requests retain accepted selection paint; accepted clear removes it" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    const surface = c.SDL_CreateSurface(40, 20, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    var backend = Canvas.init(std.testing.allocator);
    defer backend.deinit();
    backend.selection_paint = .{ .serial = 11, .rows = 1 };
    backend.selection_paint.spans[0] = .{ .first = 0, .last = 1 };
    const frame: instance.PublishedFrame = .{
        .sequence = 1,
        .presentation_generation = 1,
        .revision = 1,
        .terminal_revision = 1,
        .history_offset = 0,
        .history_count = 0,
        .history_row_base = 0,
        .alternate_screen = false,
        .surface = .{ .width = 40, .height = 20 },
        .cell_size = .{ .width = 10, .height = 20 },
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{},
        .pixels = &.{},
    };
    try std.testing.expect(c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND));
    for ([_]bool{ false, true }) |cleared| {
        if (cleared) backend.selection_paint = .{ .serial = 999 };
        try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255));
        try std.testing.expect(c.SDL_RenderClear(renderer));
        try backend.drawSelection(renderer, .{ .x = 0, .y = 0, .w = 40, .h = 20 }, @import("frame_info.zig").Info.fromLegacy(frame));
        try std.testing.expect(c.SDL_RenderPresent(renderer));
        var red: u8 = 0;
        try std.testing.expect(c.SDL_ReadSurfacePixel(surface, 5, 5, &red, null, null, null));
        try std.testing.expect(if (cleared) red == 0 else red > 0);
        try std.testing.expect(!c.SDL_RenderClipEnabled(renderer));
    }
}

// Synthetic row input used only by the Canvas tests below.
const CommandRow = struct {
    y: i32,
    backgrounds: []const render.Command,
    decorations: []const render.Command,
    glyphs: []const render.Command,
};

fn testSnapshot(background: render.Command, rows: []const CommandRow, cursor: ?render.Command, ink: []const render.Command, cell_height: u16) @import("howl_vt_output").Snapshot {
    var snapshot: @import("howl_vt_output").Snapshot = .{
        .rows = @intCast(rows.len),
        .cols = 1,
        .glyphs = @splat(&.{}),
        .backgrounds = @splat(&.{}),
        .decorations = @splat(&.{}),
        .background = background,
        .cursor = cursor,
        .cursor_shape = null,
        .cursor_text_color = null,
        .cursor_ink = ink,
        .cell_width = 1,
        .cell_height = cell_height,
        .atlas_pixels = &.{},
        .atlas_width = 1,
        .atlas_height = 1,
        .resource = .{ .resource = @fromBackingInt(@intCast(1)), .generation = @fromBackingInt(@intCast(1)) },
    };
    for (rows, 0..) |row, index| {
        std.debug.assert(row.y == @as(i32, @intCast(index * cell_height)));
        snapshot.backgrounds[index] = row.backgrounds;
        snapshot.decorations[index] = row.decorations;
        snapshot.glyphs[index] = row.glyphs;
    }
    return snapshot;
}

test "row command phases share flat SDL traversal and preserve full pane clipping" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    const surface = c.SDL_CreateSurface(16, 16, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    var backend = Canvas.init(std.testing.allocator);
    defer backend.deinit();
    const geometry = try std.testing.allocator.create(Geometry);
    defer std.testing.allocator.destroy(geometry);
    geometry.* = .{};
    const resource: render.ResourceRef = .{ .resource = try render.ResourceId.init(1), .generation = @fromBackingInt(1) };
    try backend.applyResources(renderer, 1, &.{.{ .resource = resource, .format = .alpha8, .size = .{ .width = 2, .height = 2 }, .pixel_offset = 0, .pixel_count = 4, .stride = 2 }}, &.{}, &.{ 255, 255, 255, 255 });
    const background: render.Command = .{ .solid = .{ .rect = .{ .x = 0, .y = 0, .width = 8, .height = 8 }, .color = .{ .r = 0, .g = 0, .b = 0, .a = 255 } } };
    const row_background: render.Command = .{ .solid = .{ .rect = .{ .x = 0, .y = 0, .width = 8, .height = 4 }, .color = .{ .r = 0, .g = 0, .b = 255, .a = 255 } } };
    const glyph: render.Command = .{ .alpha_mask = .{
        .destination = .{ .x = -1, .y = -1, .width = 4, .height = 4 },
        .clip = .{ .x = 0, .y = 0, .width = 8, .height = 4 },
        .resource = .{ .resource = resource, .format = .alpha8, .size = .{ .width = 2, .height = 2 }, .source = null },
        .color = .{ .r = 255, .g = 0, .b = 0, .a = 255 },
    } };
    const rows = [_]CommandRow{
        .{ .y = 0, .backgrounds = &.{row_background}, .decorations = &.{}, .glyphs = &.{glyph} },
        .{ .y = 4, .backgrounds = &.{row_background}, .decorations = &.{}, .glyphs = &.{glyph} },
    };
    var flat_background = row_background;
    flat_background.solid.rect.y += 4;
    var flat_glyph = glyph;
    flat_glyph.alpha_mask.destination.y += 4;
    flat_glyph.alpha_mask.clip.y += 4;
    const cursor: render.Command = .{ .solid = .{ .rect = .{ .x = 0, .y = 0, .width = 2, .height = 4 }, .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 } } };
    var cursor_ink = glyph;
    cursor_ink.alpha_mask.clip = .{ .x = 0, .y = 0, .width = 2, .height = 4 };
    cursor_ink.alpha_mask.color = .{ .r = 0, .g = 0, .b = 0, .a = 255 };
    const pane: c.SDL_FRect = .{ .x = 3, .y = 2, .w = 8, .h = 8 };
    const snapshot = testSnapshot(background, &rows, cursor, &.{cursor_ink}, 4);
    var expected: [16 * 16][4]u8 = undefined;
    for (0..2) |pass| {
        if (!c.SDL_SetRenderClipRect(renderer, null) or !c.SDL_SetRenderDrawColor(renderer, 0, 255, 0, 255) or !c.SDL_RenderClear(renderer)) return error.SDL;
        if (pass == 0)
            try backend.drawCommands(renderer, geometry, pane, &.{ background, row_background, flat_background, glyph, flat_glyph, cursor, cursor_ink })
        else
            try backend.drawSnapshot(renderer, geometry, pane, &snapshot, 0, snapshot.rows, true, null);
        if (!c.SDL_RenderPresent(renderer)) return error.SDL;
        for (0..16) |y| for (0..16) |x| {
            var pixel: [4]u8 = undefined;
            if (!c.SDL_ReadSurfacePixel(surface, @intCast(x), @intCast(y), &pixel[0], &pixel[1], &pixel[2], &pixel[3])) return error.SDL;
            if (pass == 0) expected[y * 16 + x] = pixel else try std.testing.expectEqualDeep(expected[y * 16 + x], pixel);
        };
    }
    backend.clearTextures();
    backend.content_revision = 123;
    try std.testing.expectError(error.MissingTexture, backend.drawSnapshot(renderer, geometry, pane, &snapshot, 0, snapshot.rows, false, null));
    try std.testing.expectEqual(@as(?u64, null), backend.content_revision);
}

test "synthetic row consumer crosses 2048 quads without producer command limits" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    const surface = c.SDL_CreateSurface(8, 8, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    var backend = Canvas.init(std.testing.allocator);
    defer backend.deinit();
    const geometry = try std.testing.allocator.create(Geometry);
    defer std.testing.allocator.destroy(geometry);
    geometry.* = .{};
    const solid: render.Command = .{ .solid = .{ .rect = .{ .x = 0, .y = 0, .width = 8, .height = 8 }, .color = .{ .r = 17, .g = 23, .b = 31, .a = 255 } } };
    const commands = try std.testing.allocator.alloc(render.Command, batch_quads + 1);
    defer std.testing.allocator.free(commands);
    @memset(commands, solid);
    const rows = [_]CommandRow{.{ .y = 0, .backgrounds = &.{}, .decorations = &.{}, .glyphs = commands }};
    const snapshot = testSnapshot(solid, &rows, null, &.{}, 8);
    try backend.drawSnapshot(renderer, geometry, .{ .x = 0, .y = 0, .w = 8, .h = 8 }, &snapshot, 0, snapshot.rows, false, null);
    try std.testing.expectEqual(@as(usize, 0), geometry.count);
    try std.testing.expectEqual(@as(usize, 0), geometry.queued_quads);
    if (!c.SDL_RenderPresent(renderer)) return error.SDL;
    var pixel: [4]u8 = undefined;
    if (!c.SDL_ReadSurfacePixel(surface, 3, 3, &pixel[0], &pixel[1], &pixel[2], &pixel[3])) return error.SDL;
    try std.testing.expectEqualDeep([4]u8{ 17, 23, 31, 255 }, pixel);
}

test "failed row pass invalidates metadata without destroying an active target and redraw recovers" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    const surface = c.SDL_CreateSurface(8, 8, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    var backend = Canvas.init(std.testing.allocator);
    defer backend.deinit();
    const geometry = try std.testing.allocator.create(Geometry);
    defer std.testing.allocator.destroy(geometry);
    geometry.* = .{};
    const target = c.SDL_CreateTexture(renderer, c.SDL_PIXELFORMAT_RGBA32, c.SDL_TEXTUREACCESS_TARGET, 8, 8) orelse return error.SDL;
    backend.content = target;
    backend.content_revision = 123;
    backend.cursor_index_revision = 123;
    if (!c.SDL_SetRenderTarget(renderer, target)) return error.SDL;
    const background: render.Command = .{ .solid = .{ .rect = .{ .x = 0, .y = 0, .width = 8, .height = 8 }, .color = .{ .r = 17, .g = 23, .b = 31, .a = 255 } } };
    const missing: render.Command = .{ .alpha_mask = .{
        .destination = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .clip = .{ .x = 0, .y = 0, .width = 8, .height = 8 },
        .resource = .{ .resource = .{ .resource = try render.ResourceId.init(1), .generation = @fromBackingInt(1) }, .format = .alpha8, .size = .{ .width = 1, .height = 1 }, .source = null },
        .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    } };
    const pane: c.SDL_FRect = .{ .x = 0, .y = 0, .w = 8, .h = 8 };
    const bad = testSnapshot(background, &.{.{ .y = 0, .backgrounds = &.{}, .decorations = &.{}, .glyphs = &.{missing} }}, null, &.{}, 8);
    try std.testing.expectError(error.MissingTexture, backend.drawSnapshot(renderer, geometry, pane, &bad, 0, bad.rows, false, null));
    try std.testing.expect(c.SDL_GetRenderTarget(renderer) == target);
    try std.testing.expect(backend.content == target);
    try std.testing.expectEqual(@as(?u64, null), backend.content_revision);
    try std.testing.expectEqual(@as(?u64, null), backend.cursor_index_revision);
    backend.content_revision = 456;
    backend.cursor_index_revision = 456;
    try std.testing.expectError(error.MissingTexture, backend.drawSnapshot(renderer, geometry, pane, &bad, 0, bad.rows, false, .{ .x = 0, .y = 0, .w = 4, .h = 4 }));
    try std.testing.expect(c.SDL_GetRenderTarget(renderer) == target);
    try std.testing.expect(backend.content == target);
    try std.testing.expectEqual(@as(?u64, null), backend.content_revision);
    try std.testing.expectEqual(@as(?u64, null), backend.cursor_index_revision);
    // A failed pass is not pixel-atomic: explicitly clear the complete target.
    if (!c.SDL_SetRenderClipRect(renderer, null) or !c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 0) or !c.SDL_RenderClear(renderer)) return error.SDL;
    const empty = testSnapshot(background, &.{}, null, &.{}, 8);
    try backend.drawSnapshot(renderer, geometry, pane, &empty, 0, 0, false, null);
    if (!c.SDL_SetRenderTarget(renderer, null) or !c.SDL_RenderTexture(renderer, target, null, null) or !c.SDL_RenderPresent(renderer)) return error.SDL;
    var pixel: [4]u8 = undefined;
    if (!c.SDL_ReadSurfacePixel(surface, 3, 3, &pixel[0], &pixel[1], &pixel[2], &pixel[3])) return error.SDL;
    try std.testing.expectEqualDeep([4]u8{ 17, 23, 31, 255 }, pixel);
}

test "clipped row subset repairs retained pixels exactly and intersects the pane" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    const surface = c.SDL_CreateSurface(16, 16, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    var backend = Canvas.init(std.testing.allocator);
    defer backend.deinit();
    const geometry = try std.testing.allocator.create(Geometry);
    defer std.testing.allocator.destroy(geometry);
    geometry.* = .{};
    const pane: c.SDL_FRect = .{ .x = 3, .y = 2, .w = 8, .h = 8 };
    const background: render.Command = .{ .solid = .{ .rect = .{ .x = 0, .y = 0, .width = 8, .height = 8 }, .color = .{ .r = 0, .g = 0, .b = 0, .a = 255 } } };
    const old: render.Command = .{ .solid = .{ .rect = .{ .x = 0, .y = 0, .width = 8, .height = 4 }, .color = .{ .r = 17, .g = 23, .b = 31, .a = 255 } } };
    var changed = old;
    changed.solid.color.r = 255;
    // Ink spans outside the pane: the device clip must still be pane-bounded.
    changed.solid.rect.x = -3;
    changed.solid.rect.width = 16;
    var rows = [_]CommandRow{
        .{ .y = 0, .backgrounds = &.{}, .decorations = &.{}, .glyphs = &.{old} },
        .{ .y = 4, .backgrounds = &.{}, .decorations = &.{}, .glyphs = &.{old} },
    };
    var snapshot = testSnapshot(background, &rows, null, &.{}, 4);
    if (!c.SDL_SetRenderDrawColor(renderer, 0, 255, 0, 255) or !c.SDL_RenderClear(renderer)) return error.SDL;
    try backend.drawSnapshot(renderer, geometry, pane, &snapshot, 0, snapshot.rows, false, null);
    if (!c.SDL_RenderPresent(renderer)) return error.SDL;
    var before: [16 * 16][4]u8 = undefined;
    for (0..16) |y| for (0..16) |x| {
        const pixel = &before[y * 16 + x];
        if (!c.SDL_ReadSurfacePixel(surface, @intCast(x), @intCast(y), &pixel[0], &pixel[1], &pixel[2], &pixel[3])) return error.SDL;
    };
    rows[1].glyphs = &.{changed};
    snapshot.glyphs[1] = rows[1].glyphs;
    try backend.drawSnapshot(renderer, geometry, pane, &snapshot, 1, 2, false, .{ .x = 0, .y = 6, .w = 16, .h = 4 });
    if (!c.SDL_RenderPresent(renderer)) return error.SDL;
    var repaired: [16 * 16][4]u8 = undefined;
    for (0..16) |y| for (0..16) |x| {
        const pixel = &repaired[y * 16 + x];
        if (!c.SDL_ReadSurfacePixel(surface, @intCast(x), @intCast(y), &pixel[0], &pixel[1], &pixel[2], &pixel[3])) return error.SDL;
        if (x < 3 or x >= 11 or y < 6 or y >= 10) try std.testing.expectEqualDeep(before[y * 16 + x], pixel.*);
    };
    // Full redraw is the oracle, including all pixels outside the damage band.
    if (!c.SDL_SetRenderClipRect(renderer, null) or !c.SDL_SetRenderDrawColor(renderer, 0, 255, 0, 255) or !c.SDL_RenderClear(renderer)) return error.SDL;
    try backend.drawSnapshot(renderer, geometry, pane, &snapshot, 0, snapshot.rows, false, null);
    if (!c.SDL_RenderPresent(renderer)) return error.SDL;
    for (0..16) |y| for (0..16) |x| {
        var pixel: [4]u8 = undefined;
        if (!c.SDL_ReadSurfacePixel(surface, @intCast(x), @intCast(y), &pixel[0], &pixel[1], &pixel[2], &pixel[3])) return error.SDL;
        try std.testing.expectEqualDeep(repaired[y * 16 + x], pixel);
    };
    // No intersection means no pass, not even a geometry reset.
    geometry.count = 1;
    backend.content_revision = 123;
    try backend.drawSnapshot(renderer, geometry, pane, &snapshot, 0, snapshot.rows, false, .{ .x = 30, .y = 30, .w = 1, .h = 1 });
    try backend.drawSnapshot(renderer, geometry, pane, &snapshot, 0, snapshot.rows, false, .{ .x = 3, .y = 2, .w = 0, .h = 8 });
    try std.testing.expectEqual(@as(usize, 1), geometry.count);
    try std.testing.expectEqual(@as(?u64, 123), backend.content_revision);
    geometry.count = 0;
}

test "VT block cursor final commands paint fill and ink through Canvas" {
    const output = @import("howl_vt_output");
    const font = try instance.text.FontSet.init(std.testing.allocator, .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 18 } });
    defer font.deinit();
    const owner = try output.Terminal.init(std.testing.allocator, font);
    // zig-audit: acknowledge catch_unreachable
    // reason: The defer below releases the only held lease first.
    defer owner.deinit() catch unreachable;
    try owner.resize(2, 4);
    try owner.feed("A\x1b[H");
    try owner.flush();
    const lease = try owner.hold();
    // zig-audit: acknowledge catch_unreachable
    // reason: This is the only lease from this live owner and is released once.
    defer owner.release(lease) catch unreachable;
    const snap = lease.snapshot;
    const solid = snap.cursor.?.solid;
    try std.testing.expect(snap.cursor_ink.len != 0);
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    const surface = c.SDL_CreateSurface(snap.surface.width, snap.surface.height, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    var backend = Canvas.init(std.testing.allocator);
    defer backend.deinit();
    const geometry = try std.testing.allocator.create(Geometry);
    defer std.testing.allocator.destroy(geometry);
    geometry.* = .{};
    try backend.applyResources(renderer, 1, &.{.{ .resource = snap.resource, .format = .alpha8, .size = .{ .width = snap.atlas_width, .height = snap.atlas_height }, .pixel_offset = 0, .pixel_count = snap.atlas_pixels.len, .stride = snap.atlas_width }}, &.{}, snap.atlas_pixels);
    const pane: c.SDL_FRect = .{ .x = 0, .y = 0, .w = @floatFromInt(snap.surface.width), .h = @floatFromInt(snap.surface.height) };
    try std.testing.expectError(error.InvalidRows, backend.drawSnapshot(renderer, geometry, pane, &snap, 0, 3, true, null));
    try backend.drawSnapshot(renderer, geometry, pane, &snap, 0, snap.rows, true, null);
    if (!c.SDL_RenderPresent(renderer)) return error.SDL;
    var fill: usize = 0;
    var ink: usize = 0;
    for (0..solid.rect.height) |y| for (0..solid.rect.width) |x| {
        var pixel: [3]u8 = undefined;
        if (!c.SDL_ReadSurfacePixel(surface, @intCast(x), @intCast(y), &pixel[0], &pixel[1], &pixel[2], null)) return error.SDL;
        if (pixel[0] == solid.color.r and pixel[1] == solid.color.g and pixel[2] == solid.color.b) fill += 1 else ink += 1;
    };
    try std.testing.expect(fill != 0 and ink != 0);
}

fn expectDirectNativeCanvasParity(input: []const u8) !void {
    const output = @import("howl_vt_output");
    const a = std.testing.allocator;
    const font = try instance.text.FontSet.init(a, .{ .primary = @import("test_fonts").primary_font, .fallbacks = &.{@import("test_fonts").colour_font}, .size = .{ .pixels = 20 } });
    defer font.deinit();
    const metrics = font.metrics();
    const atlas: output.AtlasConfig = .{ .width = 256, .height = 256, .color_height = 256, .entry_capacity = 128 };
    const direct = try output.Terminal.initConfig(a, font, .{ .atlas = atlas });
    // zig-audit: acknowledge catch_unreachable
    // reason: The single direct lease below is released before teardown.
    defer direct.deinit() catch unreachable;
    try direct.resize(8, 12);
    try direct.feed(input);
    try direct.flush();
    const lease = try direct.hold();
    // zig-audit: acknowledge catch_unreachable
    // reason: This is the sole live lease from this owner.
    defer direct.release(lease) catch unreachable;
    const snap = lease.snapshot;
    try std.testing.expect(snap.color_resource != null);

    const vt = try a.create(instance.Terminal);
    defer a.destroy(vt);
    try instance.Terminal.initWithHistoryInto(vt, a, 8, 12, 0);
    defer vt.deinit();
    try vt.setCellPixelSize(metrics.advance_width, metrics.line_height);
    try std.testing.expect((try vt.feed(input)).stateChanged());
    const native = try render.initPrivate(a, .{ .regular = font }, .{
        .cell_size = .{ .width = metrics.advance_width, .height = metrics.line_height },
        .box_drawing = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
        .shape_cache = .{ .entry_capacity = 256, .scalar_capacity = 2048, .glyph_capacity = 1024, .max_sequence_scalars = 80 },
        .atlas = atlas,
        .shaped_capacity = 160,
        .raster_bytes = 512 * 512,
        .command_capacity = 512,
    });
    defer render.deinit(native);
    try render.updateObservation(native, vt.observation(), 0, &.{});
    var uploads: [render.maximum_frame_resources]render.FrameResourceUpload = undefined;
    var removals: [render.maximum_frame_resources]render.ResourceRef = undefined;
    var commands: [512]render.Command = undefined;
    const pixels = try a.alloc(u8, 256 * 256 * 5);
    defer a.free(pixels);
    const old = try render.frame(native, &.{}, .{ .uploads = &uploads, .removals = &removals, .commands = &commands, .pixels = pixels });
    const context = try selection.Context.fromFrame(@import("frame_info.zig").Info.fromSnapshot(&snap, 1, 1));
    try std.testing.expectEqual(@as(u16, 8), context.rows);
    try std.testing.expectEqual(@as(u16, 12), context.columns);
    const cursor_view = @import("frame_info.zig").Info.fromSnapshot(&snap, 1, 1);
    try std.testing.expectEqualDeep(old.cursor.?.rect, cursor_view.cursor.?.rect);
    try std.testing.expectEqual(@as(@TypeOf(cursor_view.cursor.?.shape), .block), cursor_view.cursor.?.shape);
    try std.testing.expect(cursor_view.has_cursor_command);

    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    const first_surface = c.SDL_CreateSurface(snap.surface.width, snap.surface.height, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(first_surface);
    const second_surface = c.SDL_CreateSurface(snap.surface.width, snap.surface.height, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(second_surface);
    const first_renderer = c.SDL_CreateSoftwareRenderer(first_surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(first_renderer);
    const second_renderer = c.SDL_CreateSoftwareRenderer(second_surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(second_renderer);
    var first = Canvas.init(a);
    defer first.deinit();
    var second = Canvas.init(a);
    defer second.deinit();
    const geometry = try a.create(Geometry);
    defer a.destroy(geometry);
    geometry.* = .{};
    try first.applySnapshotResources(first_renderer, 1, &snap);
    const alpha_texture = first.find(snap.resource) orelse return error.MissingTexture;
    try first.applySnapshotResources(first_renderer, 1, &snap);
    try std.testing.expect(alpha_texture == first.find(snap.resource).?);
    try second.applyResources(second_renderer, 1, old.uploads, old.removals, old.pixels);
    const pane: c.SDL_FRect = .{ .x = 0, .y = 0, .w = @floatFromInt(snap.surface.width), .h = @floatFromInt(snap.surface.height) };
    try first.drawSnapshot(first_renderer, geometry, pane, &snap, 0, snap.rows, true, null);
    try second.drawCommands(second_renderer, geometry, pane, old.commands);
    if (!c.SDL_RenderPresent(first_renderer) or !c.SDL_RenderPresent(second_renderer)) return error.SDL;
    for (0..snap.surface.height) |y| for (0..snap.surface.width) |x| {
        var one: [4]u8 = undefined;
        var two: [4]u8 = undefined;
        if (!c.SDL_ReadSurfacePixel(first_surface, @intCast(x), @intCast(y), &one[0], &one[1], &one[2], &one[3]) or
            !c.SDL_ReadSurfacePixel(second_surface, @intCast(x), @intCast(y), &two[0], &two[1], &two[2], &two[3])) return error.SDL;
        try std.testing.expectEqualDeep(two, one);
    };
    try first.drawDirect(first_renderer, geometry, pane, 1, .shown, 1, .{ .rect = snap.cursor_cell.? }, cursor_view, &snap);
    try std.testing.expect(c.SDL_RenderPresent(first_renderer));
    for (0..snap.surface.height) |y| for (0..snap.surface.width) |x| {
        var one: [4]u8 = undefined;
        var two: [4]u8 = undefined;
        if (!c.SDL_ReadSurfacePixel(first_surface, @intCast(x), @intCast(y), &one[0], &one[1], &one[2], &one[3]) or
            !c.SDL_ReadSurfacePixel(second_surface, @intCast(x), @intCast(y), &two[0], &two[1], &two[2], &two[3])) return error.SDL;
        try std.testing.expectEqualDeep(two, one);
    };
    const old_value: instance.PublishedFrame = .{
        .sequence = 1,
        .presentation_generation = 1,
        .revision = old.revision,
        .content_revision = old.content_revision,
        .content_command_count = old.content_command_count,
        .cursor = old.cursor,
        .terminal_revision = 1,
        .history_offset = 0,
        .history_count = 0,
        .history_row_base = 0,
        .alternate_screen = false,
        .surface = snap.surface,
        .cell_size = .{ .width = snap.cell_width, .height = snap.cell_height },
        .uploads = old.uploads,
        .removals = old.removals,
        .commands = old.commands,
        .pixels = old.pixels,
    };
    const cell = snap.cursor_cell.?;
    var visual: cursor_effects.Visual = .{ .rect = .{ .x = cell.x - @as(i32, snap.cell_width), .y = cell.y, .width = cell.width, .height = cell.height }, .stretch = .{ -2, 0 }, .ghost_count = 1 };
    visual.ghosts[0] = .{ .rect = cell, .alpha = 128 };
    try first.drawDirect(first_renderer, geometry, pane, 1, .shown, 1, visual, cursor_view, &snap);
    try std.testing.expect(c.SDL_SetRenderDrawColor(second_renderer, 0, 0, 0, 0));
    try std.testing.expect(c.SDL_RenderClear(second_renderer));
    try second.drawCommands(second_renderer, geometry, pane, old.commands[0..old.content_command_count]);
    try second.drawMovingCursor(second_renderer, geometry, pane, old_value, visual);
    try std.testing.expect(c.SDL_RenderPresent(first_renderer));
    try std.testing.expect(c.SDL_RenderPresent(second_renderer));
    for (0..snap.surface.height) |y| for (0..snap.surface.width) |x| {
        var one: [4]u8 = undefined;
        var two: [4]u8 = undefined;
        if (!c.SDL_ReadSurfacePixel(first_surface, @intCast(x), @intCast(y), &one[0], &one[1], &one[2], &one[3]) or
            !c.SDL_ReadSurfacePixel(second_surface, @intCast(x), @intCast(y), &two[0], &two[1], &two[2], &two[3])) return error.SDL;
        try std.testing.expectEqualDeep(two, one);
    };
    var without_color = snap;
    without_color.color_resource = null;
    try first.applySnapshotResources(first_renderer, 1, &without_color);
    try std.testing.expectEqual(@as(usize, 1), first.count);
    try first.applySnapshotResources(first_renderer, 1, &snap);
    try std.testing.expectEqual(@as(usize, 2), first.count);
    try first.applySnapshotResources(first_renderer, 2, &snap);
    try std.testing.expectEqual(@as(usize, 2), first.count);
    try std.testing.expectEqual(@as(u64, 2), first.generation);
}

test "direct sized text and block cursor match native software Canvas" {
    try expectDirectNativeCanvasParity("M😀\x1b[2;1H\x1b]66;s=1:w=2;WWW\x07\x1b[3;1H\x1b[1;4;9;38;2;200;80;50;48;5;17m\x1b]66;s=1:w=7;X\x07\x1b[0m\x1b[1;2H");
    try expectDirectNativeCanvasParity("M😀\x1b[2;1H\x1b]66;s=2;X\x07\x1b[5;1H\x1b]66;s=3;e\u{0301}\x07\x1b[1;2H");
}

test "direct worker retained Canvas matches its complete direct cut" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const presentation: instance.PresentationConfig = .{
        .text = .{ .private = .{ .regular = .{ .path = .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 15 } } } } },
        .box_drawing = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
        .shape_cache = .{ .entry_capacity = 32, .scalar_capacity = 128, .glyph_capacity = 128, .max_sequence_scalars = 16 },
        .atlas = .{ .width = 256, .height = 256, .entry_capacity = 128 },
        .shaped_capacity = 128,
        .raster_bytes = 256 * 256,
        .command_capacity = 256,
        .command_limit = instance.render.limits.maximum_frame_commands,
    };
    const owner = try terminal.Terminal.createDirect(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf 'HELLO\\033]0;READY\\007'; read line; printf '\\r\\nWORLD\\033]0;DONE\\007'; sleep 30",
        .rows = 4,
        .columns = 20,
        .history_rows = 8,
    }, presentation, c.SDL_RegisterEvents(1), true);
    defer owner.destroy();
    const first_surface = c.SDL_CreateSurface(250, 100, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(first_surface);
    const second_surface = c.SDL_CreateSurface(250, 100, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(second_surface);
    const first_renderer = c.SDL_CreateSoftwareRenderer(first_surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(first_renderer);
    const second_renderer = c.SDL_CreateSoftwareRenderer(second_surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(second_renderer);
    var direct = Canvas.init(std.testing.allocator);
    defer direct.deinit();
    var reference = Canvas.init(std.testing.allocator);
    defer reference.deinit();
    const geometry = try std.testing.allocator.create(Geometry);
    defer std.testing.allocator.destroy(geometry);
    geometry.* = .{};
    for (0..2) |step| {
        if (step != 0) try owner.submit(.{ .input = .{ .bytes = "GO\n" } });
        const title = if (step == 0) "READY" else "DONE";
        var ready = false;
        for (0..5000) |_| {
            try direct.update(first_renderer, owner);
            const status = owner.snapshot();
            if (status.failure) |failure| return failure;
            if (status.presentation_failure) |failure| return failure;
            if (std.mem.eql(u8, status.title[0..status.title_len], title)) if (direct.frame()) |frame| {
                if (frame.terminal_revision == status.revision) {
                    ready = true;
                    break;
                }
            };
            owner.requestFrame();
            try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
        }
        if (!ready) return error.Timeout;
        const frame = direct.frame().?;
        try std.testing.expectEqual(frame.terminal_revision, direct.direct_lease.?.snapshot.terminal_revision);
        const snapshot = &direct.direct_lease.?.snapshot;
        try reference.applySnapshotResources(second_renderer, frame.presentation_generation, snapshot);
        const pane: c.SDL_FRect = .{ .x = 0, .y = 0, .w = 250, .h = 100 };
        try direct.draw(first_renderer, geometry, pane, 1, .shown, 1, null);
        try reference.drawSnapshot(second_renderer, geometry, pane, snapshot, 0, snapshot.rows, true, null);
        try std.testing.expect(c.SDL_RenderPresent(first_renderer));
        try std.testing.expect(c.SDL_RenderPresent(second_renderer));
        for (0..@min(frame.surface.height, 100)) |y| for (0..@min(frame.surface.width, 250)) |x| {
            var first: [3]u8 = undefined;
            var second: [3]u8 = undefined;
            try std.testing.expect(c.SDL_ReadSurfacePixel(first_surface, @intCast(x), @intCast(y), &first[0], &first[1], &first[2], null));
            try std.testing.expect(c.SDL_ReadSurfacePixel(second_surface, @intCast(x), @intCast(y), &second[0], &second[1], &second[2], null));
            try std.testing.expectEqualDeep(second, first);
        };
        if (snapshot.cursor_cell) |cell| {
            try direct.draw(first_renderer, geometry, pane, 1, .shown, 1, .{ .rect = cell });
            try std.testing.expect(c.SDL_RenderPresent(first_renderer));
            for (0..@min(frame.surface.height, 100)) |y| for (0..@min(frame.surface.width, 250)) |x| {
                var first: [3]u8 = undefined;
                var second: [3]u8 = undefined;
                try std.testing.expect(c.SDL_ReadSurfacePixel(first_surface, @intCast(x), @intCast(y), &first[0], &first[1], &first[2], null));
                try std.testing.expect(c.SDL_ReadSurfacePixel(second_surface, @intCast(x), @intCast(y), &second[0], &second[1], &second[2], null));
                try std.testing.expectEqualDeep(second, first);
            };
        }
        owner.requestFrame();
    }
}

test "direct retained row repair matches full repaint across viewport changes and recovery" {
    const output = @import("howl_vt_output");
    const font = try instance.text.FontSet.init(std.testing.allocator, .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 12 } });
    defer font.deinit();
    const owner = try output.Terminal.initConfig(std.testing.allocator, font, .{ .history_capacity = 8 });
    // zig-audit: acknowledge catch_unreachable
    // reason: Each loop iteration releases its only direct lease.
    defer owner.deinit() catch unreachable;
    try owner.resize(4, 10);
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    const first_surface = c.SDL_CreateSurface(200, 100, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(first_surface);
    const second_surface = c.SDL_CreateSurface(200, 100, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(second_surface);
    const first_renderer = c.SDL_CreateSoftwareRenderer(first_surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(first_renderer);
    const second_renderer = c.SDL_CreateSoftwareRenderer(second_surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(second_renderer);
    var direct = Canvas.init(std.testing.allocator);
    defer direct.deinit();
    var reference = Canvas.init(std.testing.allocator);
    defer reference.deinit();
    const geometry = try std.testing.allocator.create(Geometry);
    defer std.testing.allocator.destroy(geometry);
    geometry.* = .{};
    const cuts = [_][]const u8{
        "\x1b[?25lalpha\r\nbeta\r\ngamma",
        "\x1b[2;2H\x1b[31;44mZ",
        "\x1b[4;1H\x1b[0mrow4",
        "\x1b[2;1H\x1b[2Knew",
        "\x1b[4;1H\nscroll",
        "",
        "\x1b[?1049h\x1b[H\x1b[32mALT",
        "\x1b[?1049l",
        "\x1b[2J\x1b[Hfinal",
    };
    for (cuts, 0..) |bytes, index| {
        if (index == 5) owner.selectHistoryOffset(1);
        if (index == 6) {
            owner.selectHistoryOffset(0);
            try owner.resize(5, 12);
        }
        try owner.feed(bytes);
        try owner.flush();
        const lease = try owner.hold();
        const snapshot = &lease.snapshot;
        if (index == 5) try std.testing.expectEqual(@as(u32, 1), snapshot.history_offset);
        if (index == 6) try std.testing.expectEqual(@as(u16, 5), snapshot.rows);
        const info = @import("frame_info.zig").Info.fromSnapshot(snapshot, 1, index + 1);
        try direct.applySnapshotResources(first_renderer, 1, snapshot);
        try reference.applySnapshotResources(second_renderer, 1, snapshot);
        const pane: c.SDL_FRect = .{ .x = 0, .y = 0, .w = @floatFromInt(snapshot.surface.width), .h = @floatFromInt(snapshot.surface.height) };
        if (index == 3) {
            direct.clearTextures();
            try std.testing.expectError(error.MissingTexture, direct.drawDirect(first_renderer, geometry, pane, 1, .hidden, 1, null, info, snapshot));
            try direct.applySnapshotResources(first_renderer, 1, snapshot);
        }
        try direct.drawDirect(first_renderer, geometry, pane, 1, .hidden, 1, null, info, snapshot);
        try reference.drawSnapshot(second_renderer, geometry, pane, snapshot, 0, snapshot.rows, false, null);
        try std.testing.expect(c.SDL_RenderPresent(first_renderer));
        try std.testing.expect(c.SDL_RenderPresent(second_renderer));
        for (0..snapshot.surface.height) |y| for (0..snapshot.surface.width) |x| {
            var first: [4]u8 = undefined;
            var second: [4]u8 = undefined;
            try std.testing.expect(c.SDL_ReadSurfacePixel(first_surface, @intCast(x), @intCast(y), &first[0], &first[1], &first[2], &first[3]));
            try std.testing.expect(c.SDL_ReadSurfacePixel(second_surface, @intCast(x), @intCast(y), &second[0], &second[1], &second[2], &second[3]));
            try std.testing.expectEqualDeep(second, first);
        };
        try owner.release(lease);
    }
}
