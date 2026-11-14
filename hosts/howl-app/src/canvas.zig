//! Retains content pixels and paints the cursor from complete immutable frames.
const std = @import("std");
const c = @import("desktop");
const app_presentation = @import("presentation.zig");
const terminal = @import("terminal.zig");
const selection = @import("selection.zig");
const cursor_effects = @import("cursor.zig");
const output_commands = @import("howl_vt_output_commands");
const output_limits = @import("howl_vt_output_limits");

/// Host focus/blink composition over one immutable cursor frame.
pub const CursorDisplay = enum { shown, hidden, outline };

// One alpha atlas, one optional colour atlas, and VT's bounded image resources.
const resource_limit = output_limits.maximum_output_images + 2;
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
    residency: output_commands.Residency,
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
        color: output_commands.Color,
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
    lease: ?terminal.Frame = null,
    owner: ?*terminal.Terminal = null,
    selection_paint: selection.Paint = .{},
    textures: [resource_limit]Texture = undefined,
    count: usize = 0,
    converted: std.ArrayList(u8) = .empty,
    generation: u64 = 0,
    content: ?*c.SDL_Texture = null,
    content_revision: ?u64 = null,
    visual_context: ?u64 = null,
    row_origin: u16 = 0,
    row_count: u16 = 0,
    row_generations: [output_limits.maximum_rows]u64 = @splat(0),
    content_size: output_commands.Size = .{ .width = 1, .height = 1 },

    /// Creates an empty backend resource owner with no canonical or frame authority.
    pub fn init(allocator: std.mem.Allocator) Canvas {
        return .{ .allocator = allocator };
    }

    /// Retires the held frame before releasing graphical resources and scratch.
    pub fn deinit(self: *Canvas) void {
        if (self.lease) |lease| {
            // zig-audit: acknowledge catch_unreachable
            // reason: Canvas owns this exact live direct pin until teardown.
            self.owner.?.releaseFrame(lease) catch unreachable;
        }
        self.clearTextures();
        self.converted.deinit(self.allocator);
        self.* = undefined;
    }

    /// Copies interaction facts from the same held cut used for drawing.
    pub fn frame(self: *const Canvas) ?@import("frame_info.zig").Info {
        if (self.lease) |*lease| return @import("frame_info.zig").Info.fromSnapshot(&lease.snapshot, lease.presentation_generation, lease.serial);
        return null;
    }

    /// Transfers an immutable publication only when ready; duplicate wakeups keep the old lease.
    pub fn update(self: *Canvas, renderer: *c.SDL_Renderer, owner: *terminal.Terminal) !void {
        const direct = (try owner.replaceFrame(if (self.lease) |*previous| previous else null, &self.selection_paint)) orelse return;
        self.lease = null;
        // zig-audit: acknowledge catch_unreachable
        // reason: The just-acquired pin belongs to this live terminal owner.
        errdefer owner.releaseFrame(direct) catch unreachable;
        try self.applySnapshotResources(renderer, direct.presentation_generation, &direct.snapshot);
        self.lease = direct;
        self.owner = owner;
    }

    /// Applies a validated immutable resource transaction on the graphical thread.
    /// Pixel storage is borrowed only for this call. On failure, applied resources
    /// may be partial; do not acknowledge residency or draw until a complete retry.
    pub fn applyResources(
        self: *Canvas,
        renderer: *c.SDL_Renderer,
        presentation_generation: u64,
        uploads: []const output_commands.FrameResourceUpload,
        removals: []const output_commands.ResourceRef,
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
            // SDL 3.4.18's software renderer RLE-compresses static textures;
            // alternating clipped scales can corrupt subsequent colour draws.
            const access: c.SDL_TextureAccess = if (upload.format == .rgba8) c.SDL_TEXTUREACCESS_STREAMING else c.SDL_TEXTUREACCESS_STATIC;
            const texture = c.SDL_CreateTexture(renderer, c.SDL_PIXELFORMAT_RGBA32, access, upload.size.width, upload.size.height) orelse return error.SDLTexture;
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
        // Retire image/color occurrences no longer present in this exact cut.
        // RGBA alone does not identify the font plane: external images share
        // that format, but keep independent identities 3..9.
        var resident: usize = 0;
        while (resident < self.count) {
            const existing = self.textures[resident].residency.resource;
            const id = @backingInt(existing.resource);
            const needed = if (id == 2)
                (snapshot.color_resource != null and std.meta.eql(existing, snapshot.color_resource.?))
            else if (id >= 3 and id <= 9) blk: {
                for (snapshot.graphics.images) |item| {
                    if (std.meta.eql(existing, item.resource)) break :blk true;
                }
                break :blk false;
            } else true;
            if (!needed) {
                self.remove(existing, true);
            } else resident += 1;
        }
        if (self.find(snapshot.resource) == null) {
            const upload: output_commands.FrameResourceUpload = .{ .resource = snapshot.resource, .format = .alpha8, .size = .{ .width = snapshot.atlas_width, .height = snapshot.atlas_height }, .pixel_offset = 0, .pixel_count = snapshot.atlas_pixels.len, .stride = snapshot.atlas_width };
            try self.applyResources(renderer, presentation_generation, &.{upload}, &.{}, snapshot.atlas_pixels);
        }
        if (snapshot.color_resource) |resource| {
            if (self.find(resource) == null) {
                const upload: output_commands.FrameResourceUpload = .{ .resource = resource, .format = .rgba8, .size = .{ .width = snapshot.color_atlas_width, .height = snapshot.color_atlas_height }, .pixel_offset = 0, .pixel_count = snapshot.color_atlas_pixels.len, .stride = @as(usize, snapshot.color_atlas_width) * 4 };
                try self.applyResources(renderer, presentation_generation, &.{upload}, &.{}, snapshot.color_atlas_pixels);
            }
        }
        for (snapshot.graphics.images) |image| {
            if (self.find(image.resource) != null) continue;
            const upload: output_commands.FrameResourceUpload = .{
                .resource = image.resource,
                .format = .rgba8,
                .size = image.size,
                .pixel_offset = 0,
                .pixel_count = image.pixels.len,
                .stride = @as(usize, image.size.width) * 4,
            };
            try self.applyResources(renderer, presentation_generation, &.{upload}, &.{}, image.pixels);
        }
    }

    /// Draws canonical commands with exact pane/resource clipping using shared bounded batches.
    pub fn draw(self: *Canvas, renderer: *c.SDL_Renderer, geometry: *Geometry, logical_pane: c.SDL_FRect, scale: f32, cursor: CursorDisplay, outline_pixels: u8, motion: ?cursor_effects.Visual) !void {
        std.debug.assert(outline_pixels >= 1 and outline_pixels <= 16);
        const info = self.frame() orelse return;
        const cut = if (self.lease) |*lease| &lease.snapshot else return;
        return self.drawCut(renderer, geometry, logical_pane, scale, cursor, outline_pixels, motion, info, cut);
    }

    fn drawCut(self: *Canvas, renderer: *c.SDL_Renderer, geometry: *Geometry, logical_pane: c.SDL_FRect, scale: f32, cursor: CursorDisplay, outline_pixels: u8, motion: ?cursor_effects.Visual, value: @import("frame_info.zig").Info, snapshot: *const @import("howl_vt_output").Snapshot) !void {
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
            const full = self.content_revision == null or self.visual_context != snapshot.visual_context or self.row_origin != snapshot.row_origin or self.row_count != snapshot.rows;
            if (full) {
                if (!c.SDL_SetRenderClipRect(renderer, null) or !c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 0) or !c.SDL_RenderClear(renderer)) return error.SDLTexture;
                try self.drawSnapshot(renderer, geometry, target_pane, snapshot, 0, snapshot.rows, false, null);
            } else {
                var row: u16 = 0;
                while (row < snapshot.rows) {
                    if (self.row_generations[row] == snapshot.row_generations[row]) {
                        row += 1;
                        continue;
                    }
                    const first = row;
                    row += 1;
                    while (row < snapshot.rows and self.row_generations[row] != snapshot.row_generations[row]) row += 1;
                    const row_clip: c.SDL_Rect = .{ .x = 0, .y = @intCast(@as(u32, first) * snapshot.cell_height), .w = snapshot.surface.width, .h = @intCast(@as(u32, row - first) * snapshot.cell_height) };
                    try self.drawSnapshot(renderer, geometry, target_pane, snapshot, first, row, false, row_clip);
                }
            }
            if (!c.SDL_SetRenderTarget(renderer, previous_target)) return error.SDLTexture;
            self.visual_context = snapshot.visual_context;
            self.row_origin = snapshot.row_origin;
            self.row_count = snapshot.rows;
            @memcpy(self.row_generations[0..snapshot.rows], snapshot.row_generations[0..snapshot.rows]);
            self.content_revision = snapshot.content_revision;
        }
        const clip = pixelClip(pane);
        const dest: c.SDL_FRect = .{ .x = pane.x, .y = pane.y, .w = @floatFromInt(snapshot.surface.width), .h = @floatFromInt(snapshot.surface.height) };
        if (!c.SDL_SetRenderClipRect(renderer, &clip) or !c.SDL_RenderTexture(renderer, target, null, &dest)) return error.SDLTexture;
        try self.drawSelection(renderer, pane, value);
        switch (cursor) {
            .hidden => {},
            .shown => if (motion) |visual| {
                try self.drawMovingCursor(renderer, geometry, pane, snapshot, visual);
            } else if (snapshot.cursor) |command| {
                try self.drawCommands(renderer, geometry, pane, &.{command});
                try self.drawCommands(renderer, geometry, pane, snapshot.cursor_ink);
            },
            .outline => if (snapshot.cursor_cell) |rect| if (snapshot.cursor) |command| {
                const color = command.solid.color;
                const width = @min(rect.width, outline_pixels);
                const height = @min(rect.height, outline_pixels);
                const commands = [_]output_commands.Command{
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

    fn drawMovingCursor(self: *Canvas, renderer: *c.SDL_Renderer, geometry: *Geometry, pane: c.SDL_FRect, snapshot: *const @import("howl_vt_output").Snapshot, visual: cursor_effects.Visual) !void {
        const cell = snapshot.cursor_cell orelse return;
        const body = (snapshot.cursor orelse return).solid;
        const ink = snapshot.cursor_text_color orelse return;
        std.debug.assert(visual.ghost_count <= visual.ghosts.len);
        var ghosts: [4]output_commands.Command = undefined;
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
            const replay = (try cursorRecolor(command, painted, ink, color_id)) orelse continue;
            try self.appendCommand(renderer, geometry, pane, pixelClip(pane), replay);
        };
        try geometry.finish(renderer);
    }

    fn drawSelection(self: *const Canvas, renderer: *c.SDL_Renderer, pane: c.SDL_FRect, value: @import("frame_info.zig").Info) !void {
        // Selection is a transient overlay, below the cursor and outside the
        // retained content texture. Its spans belong to this exact frame.
        if (self.selection_paint.rows == 0) return;
        const rows = value.surface.height / value.cell_size.height;
        const columns = value.surface.width / value.cell_size.width;
        if (!c.SDL_SetRenderDrawColor(renderer, 180, 180, 180, 100)) return error.SDLGeometry;
        for (0..@min(self.selection_paint.rows, rows)) |row| {
            var col: usize = 0;
            while (col < columns) {
                if (!self.selection_paint.contains(row, col)) {
                    col += 1;
                    continue;
                }
                const first = col;
                while (col < columns and self.selection_paint.contains(row, col)) : (col += 1) {}
                const rect: c.SDL_FRect = .{
                    .x = pane.x + @as(f32, @floatFromInt(first * value.cell_size.width)),
                    .y = pane.y + @as(f32, @floatFromInt(row * value.cell_size.height)),
                    .w = @floatFromInt((col - first) * value.cell_size.width),
                    .h = @floatFromInt(value.cell_size.height),
                };
                if (!c.SDL_RenderFillRect(renderer, &rect)) return error.SDLGeometry;
            }
        }
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
        self.visual_context = null;
    }

    fn beginCommands(renderer: *c.SDL_Renderer, geometry: *Geometry) !void {
        // Retire preceding UI/target commands, including a failed partial pass.
        if (!c.SDL_FlushRenderer(renderer)) return error.SDLGeometry;
        geometry.count = 0;
        geometry.queued_quads = 0;
    }

    /// Draws one flat final-command pass. Clear and redraw the target after failure.
    pub fn drawCommands(self: *Canvas, renderer: *c.SDL_Renderer, geometry: *Geometry, pane: c.SDL_FRect, commands: []const output_commands.Command) !void {
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
        for (snapshot.graphics.deep) |command|
            try self.appendCommand(renderer, geometry, pane, visible, command);
        for (first..end) |row| {
            var origin = pane;
            origin.y += @as(f32, @floatFromInt(row * snapshot.cell_height));
            for (snapshot.backgrounds[row]) |command|
                try self.appendCommand(renderer, geometry, origin, visible, command);
        }
        for (snapshot.graphics.negative) |command|
            try self.appendCommand(renderer, geometry, pane, visible, command);
        inline for (.{ "decorations", "glyphs" }) |phase| {
            for (first..end) |row| {
                var origin = pane;
                origin.y += @as(f32, @floatFromInt(row * snapshot.cell_height));
                for (@field(snapshot, phase)[row]) |command|
                    try self.appendCommand(renderer, geometry, origin, visible, command);
            }
        }
        for (snapshot.graphics.positive) |command|
            try self.appendCommand(renderer, geometry, pane, visible, command);
        if (show_cursor) if (snapshot.cursor) |command| {
            try self.appendCommand(renderer, geometry, pane, visible, command);
            for (snapshot.cursor_ink) |ink| try self.appendCommand(renderer, geometry, pane, visible, ink);
        };
        try geometry.finish(renderer);
    }

    fn appendCommand(self: *Canvas, renderer: *c.SDL_Renderer, geometry: *Geometry, pane: c.SDL_FRect, pane_clip: c.SDL_Rect, command: output_commands.Command) !void {
        switch (command) {
            .solid => |solid| try geometry.append(renderer, null, pane_clip, destination(solid.rect, pane), .{ .x = 0, .y = 0, .w = 0, .h = 0 }, solid.color),
            .alpha_mask => |mask| {
                const texture = self.find(mask.resource.resource) orelse return error.MissingTexture;
                const dest = destination(mask.destination, pane);
                const clip = commandClip(mask.destination, mask.clip, pane, pane_clip) orelse return;
                const src: output_commands.SourceRect = mask.resource.source orelse .{ .x = 0, .y = 0, .width = mask.resource.size.width, .height = mask.resource.size.height };
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
                const src: output_commands.SourceRect = image.resource.source orelse .{ .x = 0, .y = 0, .width = image.resource.size.width, .height = image.resource.size.height };
                const source: c.SDL_FRect = .{ .x = @floatFromInt(src.x), .y = @floatFromInt(src.y), .w = @floatFromInt(src.width), .h = @floatFromInt(src.height) };
                const dest = destination(image.destination, pane);
                try geometry.reserve(renderer, 1);
                if (!c.SDL_SetRenderClipRect(renderer, &clip) or
                    !c.SDL_RenderTexture(renderer, texture, &source, &dest)) return error.SDLTexture;
                geometry.queued_quads += 1;
            },
        }
    }

    fn find(self: *const Canvas, resource: output_commands.ResourceRef) ?*c.SDL_Texture {
        for (self.textures[0..self.count]) |texture| {
            if (texture.residency.resource.resource == resource.resource and
                texture.residency.resource.generation == resource.generation) return texture.texture;
        }
        return null;
    }

    fn remove(self: *Canvas, resource: output_commands.ResourceRef, exact: bool) void {
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

/// Repaint stationary ink through a moving host cursor without changing VT.
/// Alpha text uses cursor ink colour; intrinsic RGBA glyphs keep their pixels.
fn cursorRecolor(command: output_commands.Command, rect: output_commands.Rect, color: output_commands.Color, color_id: ?output_commands.ResourceId) output_commands.Error!?output_commands.Command {
    const Glyph = struct { destination: output_commands.Rect, clip: output_commands.Rect };
    const glyph: Glyph = switch (command) {
        .alpha_mask => |value| if (value.cursor_component) .{ .destination = value.destination, .clip = value.clip } else return null,
        .rgba => |value| if (color_id != null and value.resource.resource.resource == color_id.?) .{ .destination = value.destination, .clip = value.clip } else return null,
        .solid => return null,
    };
    const clip = (try output_commands.intersectRects(glyph.clip, rect)) orelse return null;
    if (try output_commands.intersectRects(glyph.destination, clip) == null) return null;
    var result = command;
    switch (result) {
        .alpha_mask => |*value| {
            value.clip = clip;
            value.color = color;
            value.cursor_component = false;
        },
        .rgba => |*value| value.clip = clip,
        .solid => return null,
    }
    return result;
}

test "moving cursor ink replays only clipped text and intrinsic colour glyphs" {
    const alpha: output_commands.ResourceRef = .{ .resource = try output_commands.ResourceId.init(1), .generation = @fromBackingInt(1) };
    const rgba: output_commands.ResourceRef = .{ .resource = try output_commands.ResourceId.init(2), .generation = @fromBackingInt(1) };
    const mask: output_commands.Command = .{ .alpha_mask = .{
        .destination = .{ .x = 1, .y = 1, .width = 5, .height = 5 },
        .clip = .{ .x = 2, .y = 2, .width = 4, .height = 4 },
        .resource = .{ .resource = alpha, .format = .alpha8, .size = .{ .width = 8, .height = 8 } },
        .color = .{ .r = 1, .g = 2, .b = 3, .a = 255 },
        .cursor_component = true,
    } };
    const cursor: output_commands.Rect = .{ .x = 4, .y = 3, .width = 3, .height = 5 };
    const ink: output_commands.Color = .{ .r = 240, .g = 241, .b = 242, .a = 255 };
    const recolored = (try cursorRecolor(mask, cursor, ink, null)).?.alpha_mask;
    try std.testing.expectEqualDeep(output_commands.Rect{ .x = 4, .y = 3, .width = 2, .height = 3 }, recolored.clip);
    try std.testing.expectEqualDeep(ink, recolored.color);
    try std.testing.expect(!recolored.cursor_component);
    var ordinary = mask;
    ordinary.alpha_mask.cursor_component = false;
    try std.testing.expect((try cursorRecolor(ordinary, cursor, ink, null)) == null);
    try std.testing.expect((try cursorRecolor(mask, .{ .x = 20, .y = 20, .width = 1, .height = 1 }, ink, null)) == null);
    try std.testing.expectError(error.InvalidRectangle, cursorRecolor(mask, .{ .x = 3, .y = 3, .width = 0, .height = 1 }, ink, null));
    const image: output_commands.Command = .{ .rgba = .{
        .destination = .{ .x = 1, .y = 1, .width = 5, .height = 5 },
        .clip = .{ .x = 2, .y = 2, .width = 4, .height = 4 },
        .resource = .{ .resource = rgba, .format = .rgba8, .size = .{ .width = 8, .height = 8 } },
    } };
    try std.testing.expect((try cursorRecolor(image, cursor, ink, alpha.resource)) == null);
    const clipped = (try cursorRecolor(image, cursor, ink, rgba.resource)).?.rgba;
    try std.testing.expectEqualDeep(recolored.clip, clipped.clip);
    try std.testing.expectEqualDeep(image.rgba.resource, clipped.resource);
}

fn cursorBody(body: output_commands.Rect, origin: output_commands.Rect, rect: output_commands.Rect) output_commands.Rect {
    return .{ .x = body.x + rect.x - origin.x, .y = body.y + rect.y - origin.y, .width = body.width, .height = body.height };
}

fn stretchedBody(body: output_commands.Rect, tail: [2]i32, surface: output_commands.Size) output_commands.Rect {
    const left = @max(0, @min(body.x, body.x + tail[0]));
    const top = @max(0, @min(body.y, body.y + tail[1]));
    const right = @min(@as(i32, surface.width), @max(body.x, body.x + tail[0]) + @as(i32, body.width));
    const bottom = @min(@as(i32, surface.height), @max(body.y, body.y + tail[1]) + @as(i32, body.height));
    std.debug.assert(right > left and bottom > top);
    return .{ .x = left, .y = top, .width = @intCast(right - left), .height = @intCast(bottom - top) };
}

fn destination(rect: output_commands.Rect, pane: c.SDL_FRect) c.SDL_FRect {
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

fn commandClip(ink: output_commands.Rect, clip: output_commands.Rect, pane: c.SDL_FRect, pane_clip: c.SDL_Rect) ?c.SDL_Rect {
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

fn contained(a: output_commands.Rect, b: output_commands.Rect) bool {
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
        const ink: output_commands.Rect = .{ .x = @as(i32, @intCast(i % 43)) - 21, .y = @as(i32, @intCast(i % 37)) - 18, .width = @intCast(2 + i % 19), .height = @intCast(2 + i % 29) };
        const clip: output_commands.Rect = switch (i % 3) {
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
    const clip: output_commands.Rect = .{ .x = -3, .y = 7, .width = 12, .height = 14 };
    try std.testing.expect(contained(.{ .x = -3, .y = 7, .width = 12, .height = 14 }, clip));
    try std.testing.expect(!contained(.{ .x = -4, .y = 7, .width = 12, .height = 14 }, clip));
    try std.testing.expect(!contained(.{ .x = -3, .y = 7, .width = 13, .height = 14 }, clip));
}

test "failed backend allocation retires its candidate; a fresh presentation generation rebuilds exact resources" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const presentation: app_presentation.Config = .{
        .text = .{ .private = .{ .regular = .{ .path = .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 15 } } } } },
        .box_drawing = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
        .shape_cache = .{ .entry_capacity = 32, .scalar_capacity = 128, .glyph_capacity = 128, .max_sequence_scalars = 16 },
        .atlas = .{ .width = 256, .height = 256, .entry_capacity = 128 },
        .shaped_capacity = 128,
        .raster_bytes = 256 * 256,
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
    const presentation: app_presentation.Config = .{
        .text = .{ .private = .{ .regular = .{ .path = .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 15 } } } } },
        .box_drawing = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
        .shape_cache = .{ .entry_capacity = 32, .scalar_capacity = 128, .glyph_capacity = 128, .max_sequence_scalars = 16 },
        .atlas = .{ .width = 256, .height = 256, .entry_capacity = 128 },
        .shaped_capacity = 128,
        .raster_bytes = 256 * 256,
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
        const value = backend.lease.?.snapshot;
        previous_revision = value.terminal_revision;
        try std.testing.expectEqual(step >= 2 and (step - 2) % 4 != 3, value.alternate);
        errdefer std.debug.print("alternate texture failure at step {d}, title {s}, textures {d}\n", .{ step, title, backend.count });
        try backend.draw(renderer, geometry, .{ .x = 0, .y = 0, .w = 250, .h = 100 }, 1, .shown, 1, null);
        try std.testing.expect(c.SDL_RenderPresent(renderer));
        try std.testing.expectEqual(@as(usize, 1) + @intFromBool(value.color_resource != null), backend.count);
        var retained: [250 * 100][3]u8 = undefined;
        const visible_width = @min(value.surface.width, 250);
        const visible_height = @min(value.surface.height, 100);
        for (0..visible_height) |y| for (0..visible_width) |x| {
            try std.testing.expect(c.SDL_ReadSurfacePixel(surface, @intCast(x), @intCast(y), &retained[y * visible_width + x][0], &retained[y * visible_width + x][1], &retained[y * visible_width + x][2], null));
        };
        try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255));
        try std.testing.expect(c.SDL_RenderClear(renderer));
        try backend.drawSnapshot(renderer, geometry, .{ .x = 0, .y = 0, .w = 250, .h = 100 }, &value, 0, value.rows, true, null);
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
    const presentation: app_presentation.Config = .{
        .text = .{ .private = .{ .regular = .{ .path = .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 15 } } } } },
        .box_drawing = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
        .shape_cache = .{ .entry_capacity = 32, .scalar_capacity = 128, .glyph_capacity = 128, .max_sequence_scalars = 16 },
        .atlas = .{ .width = 256, .height = 256, .entry_capacity = 128 },
        .shaped_capacity = 128,
        .raster_bytes = 256 * 256,
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
    const frame = backend.lease.?.snapshot;
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
    try backend.drawSnapshot(renderer, geometry, .{
        .x = 7,
        .y = 11,
        .w = @floatFromInt(frame.surface.width),
        .h = @floatFromInt(frame.surface.height),
    }, &frame, 0, frame.rows, true, null);
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
    const presentation: app_presentation.Config = .{
        .text = .{ .private = .{ .regular = .{ .path = .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 15 } } } } },
        .box_drawing = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
        .shape_cache = .{ .entry_capacity = 32, .scalar_capacity = 128, .glyph_capacity = 128, .max_sequence_scalars = 16 },
        .atlas = .{ .width = 256, .height = 256, .entry_capacity = 128 },
        .shaped_capacity = 128,
        .raster_bytes = 256 * 256,
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
    var retained_revision: ?u64 = null;
    var retained_texture: ?*c.SDL_Texture = null;
    for ([_][]const u8{ "2", "1", "4", "3", "6", "5" }) |style| {
        const previous = owner.snapshot().revision;
        var input: [2]u8 = .{ style[0], '\n' };
        try owner.submit(.{ .input = .{ .bytes = &input } });
        var attempts: u16 = 0;
        while (attempts < 5000) : (attempts += 1) {
            try backend.update(renderer, owner);
            const status = owner.snapshot();
            if (status.failure) |failure| return failure;
            if (status.presentation_failure) |failure| return failure;
            if (status.revision > previous) {
                if (backend.frame()) |frame| if (frame.terminal_revision == status.revision) break;
            }
            owner.requestFrame();
            try std.Io.sleep(threaded.io(), .fromMilliseconds(1), .awake);
        }
        if (attempts == 5000) return error.Timeout;
        const frame = backend.lease.?.snapshot;
        try std.testing.expectEqual((style[0] - '0') % 2 == 1, frame.cursor_blink);
        const expected_shape: @TypeOf(frame.cursor_shape.?) = switch (style[0]) {
            '1', '2' => .block,
            '3', '4' => .underline,
            else => .bar,
        };
        try std.testing.expectEqual(expected_shape, frame.cursor_shape.?);
        if (retained_revision) |revision|
            try std.testing.expectEqual(revision, frame.content_revision)
        else
            retained_revision = frame.content_revision;
        const pane: c.SDL_FRect = .{ .x = 0, .y = 0, .w = @floatFromInt(frame.surface.width), .h = @floatFromInt(frame.surface.height) };
        for ([_]CursorDisplay{ .shown, .hidden, .outline }) |mode|
            for ([_]f32{ 1, 1.25, 1.6, 2 }) |scale| {
                backend.selection_paint = .{ .rows = 2 };
                backend.selection_paint.add(0, 0, 1);
                try std.testing.expect(c.SDL_SetRenderScale(renderer, scale, scale));
                try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255));
                try std.testing.expect(c.SDL_RenderClear(renderer));
                try backend.draw(renderer, geometry, pane, scale, mode, 3, null);
                try std.testing.expect(c.SDL_RenderPresent(renderer));
                const texture = backend.content.?;
                if (retained_texture) |previous_texture|
                    try std.testing.expectEqual(previous_texture, texture)
                else
                    retained_texture = texture;
                var actual_x: f32 = 0;
                var actual_y: f32 = 0;
                try std.testing.expect(c.SDL_GetRenderScale(renderer, &actual_x, &actual_y));
                try std.testing.expectEqual(scale, actual_x);
                try std.testing.expectEqual(scale, actual_y);
                try std.testing.expect(!c.SDL_RenderClipEnabled(renderer));
            };
        const cursor_cell = frame.cursor_cell.?;
        var motion: cursor_effects.Visual = .{
            .rect = cursor_cell,
            .ghost_count = 1,
            .stretch = .{ 2, 0 },
        };
        motion.ghosts[0] = .{ .rect = cursor_cell, .alpha = 128 };
        try backend.draw(renderer, geometry, pane, 1, .shown, 3, motion);
        try std.testing.expect(c.SDL_RenderPresent(renderer));
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
    backend.selection_paint.add(0, 0, 1);
    const frame: @import("frame_info.zig").Info = .{
        .sequence = 1,
        .presentation_generation = 1,
        .terminal_revision = 1,
        .surface = .{ .width = 40, .height = 20 },
        .cell_size = .{ .width = 10, .height = 20 },
    };
    try std.testing.expect(c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND));
    for ([_]bool{ false, true }) |cleared| {
        if (cleared) backend.selection_paint = .{ .serial = 999 };
        try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255));
        try std.testing.expect(c.SDL_RenderClear(renderer));
        try backend.drawSelection(renderer, .{ .x = 0, .y = 0, .w = 40, .h = 20 }, frame);
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
    backgrounds: []const output_commands.Command,
    decorations: []const output_commands.Command,
    glyphs: []const output_commands.Command,
};

fn testSnapshot(background: output_commands.Command, rows: []const CommandRow, cursor: ?output_commands.Command, ink: []const output_commands.Command, cell_height: u16) @import("howl_vt_output").Snapshot {
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
    const resource: output_commands.ResourceRef = .{ .resource = try output_commands.ResourceId.init(1), .generation = @fromBackingInt(1) };
    try backend.applyResources(renderer, 1, &.{.{ .resource = resource, .format = .alpha8, .size = .{ .width = 2, .height = 2 }, .pixel_offset = 0, .pixel_count = 4, .stride = 2 }}, &.{}, &.{ 255, 255, 255, 255 });
    const background: output_commands.Command = .{ .solid = .{ .rect = .{ .x = 0, .y = 0, .width = 8, .height = 8 }, .color = .{ .r = 0, .g = 0, .b = 0, .a = 255 } } };
    const row_background: output_commands.Command = .{ .solid = .{ .rect = .{ .x = 0, .y = 0, .width = 8, .height = 4 }, .color = .{ .r = 0, .g = 0, .b = 255, .a = 255 } } };
    const glyph: output_commands.Command = .{ .alpha_mask = .{
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
    const cursor: output_commands.Command = .{ .solid = .{ .rect = .{ .x = 0, .y = 0, .width = 2, .height = 4 }, .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 } } };
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
    const solid: output_commands.Command = .{ .solid = .{ .rect = .{ .x = 0, .y = 0, .width = 8, .height = 8 }, .color = .{ .r = 17, .g = 23, .b = 31, .a = 255 } } };
    const commands = try std.testing.allocator.alloc(output_commands.Command, batch_quads + 1);
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
    if (!c.SDL_SetRenderTarget(renderer, target)) return error.SDL;
    const background: output_commands.Command = .{ .solid = .{ .rect = .{ .x = 0, .y = 0, .width = 8, .height = 8 }, .color = .{ .r = 17, .g = 23, .b = 31, .a = 255 } } };
    const missing: output_commands.Command = .{ .alpha_mask = .{
        .destination = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        .clip = .{ .x = 0, .y = 0, .width = 8, .height = 8 },
        .resource = .{ .resource = .{ .resource = try output_commands.ResourceId.init(1), .generation = @fromBackingInt(1) }, .format = .alpha8, .size = .{ .width = 1, .height = 1 }, .source = null },
        .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    } };
    const pane: c.SDL_FRect = .{ .x = 0, .y = 0, .w = 8, .h = 8 };
    const bad = testSnapshot(background, &.{.{ .y = 0, .backgrounds = &.{}, .decorations = &.{}, .glyphs = &.{missing} }}, null, &.{}, 8);
    try std.testing.expectError(error.MissingTexture, backend.drawSnapshot(renderer, geometry, pane, &bad, 0, bad.rows, false, null));
    try std.testing.expect(c.SDL_GetRenderTarget(renderer) == target);
    try std.testing.expect(backend.content == target);
    try std.testing.expectEqual(@as(?u64, null), backend.content_revision);
    backend.content_revision = 456;
    try std.testing.expectError(error.MissingTexture, backend.drawSnapshot(renderer, geometry, pane, &bad, 0, bad.rows, false, .{ .x = 0, .y = 0, .w = 4, .h = 4 }));
    try std.testing.expect(c.SDL_GetRenderTarget(renderer) == target);
    try std.testing.expect(backend.content == target);
    try std.testing.expectEqual(@as(?u64, null), backend.content_revision);
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
    const background: output_commands.Command = .{ .solid = .{ .rect = .{ .x = 0, .y = 0, .width = 8, .height = 8 }, .color = .{ .r = 0, .g = 0, .b = 0, .a = 255 } } };
    const old: output_commands.Command = .{ .solid = .{ .rect = .{ .x = 0, .y = 0, .width = 8, .height = 4 }, .color = .{ .r = 17, .g = 23, .b = 31, .a = 255 } } };
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
    const font = try @import("howl_text").FontSet.init(std.testing.allocator, .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 18 } });
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

fn expectDirectCanvasPixelParity(input: []const u8) !void {
    const output = @import("howl_vt_output");
    const a = std.testing.allocator;
    const font = try @import("howl_text").FontSet.init(a, .{ .primary = @import("test_fonts").primary_font, .fallbacks = &.{@import("test_fonts").colour_font}, .size = .{ .pixels = 20 } });
    defer font.deinit();
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

    const context = try selection.Context.fromFrame(@import("frame_info.zig").Info.fromSnapshot(&snap, 1, 1));
    try std.testing.expectEqual(@as(u16, 8), context.rows);
    try std.testing.expectEqual(@as(u16, 12), context.columns);
    const cursor_view = @import("frame_info.zig").Info.fromSnapshot(&snap, 1, 1);
    try std.testing.expectEqualDeep(snap.cursor_cell.?, cursor_view.cursor.?.rect);
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
    try second.applySnapshotResources(second_renderer, 1, &snap);
    const pane: c.SDL_FRect = .{ .x = 0, .y = 0, .w = @floatFromInt(snap.surface.width), .h = @floatFromInt(snap.surface.height) };
    // Paint the same immutable direct-VT cut through independent Canvas paths:
    // full immediate traversal versus retained content plus cursor overlay.
    try first.drawSnapshot(first_renderer, geometry, pane, &snap, 0, snap.rows, true, null);
    try second.drawCut(second_renderer, geometry, pane, 1, .shown, 1, null, cursor_view, &snap);
    if (!c.SDL_RenderPresent(first_renderer) or !c.SDL_RenderPresent(second_renderer)) return error.SDL;
    for (0..snap.surface.height) |y| for (0..snap.surface.width) |x| {
        var one: [4]u8 = undefined;
        var two: [4]u8 = undefined;
        if (!c.SDL_ReadSurfacePixel(first_surface, @intCast(x), @intCast(y), &one[0], &one[1], &one[2], &one[3]) or
            !c.SDL_ReadSurfacePixel(second_surface, @intCast(x), @intCast(y), &two[0], &two[1], &two[2], &two[3])) return error.SDL;
        if (!std.mem.eql(u8, &two, &one)) {
            std.debug.print("Canvas mismatch x={d} y={d} cell={d}x{d}: retained={any} immediate={any}\n", .{ x, y, snap.cell_width, snap.cell_height, two, one });
            return error.TestUnexpectedResult;
        }
    };
    try first.drawCut(first_renderer, geometry, pane, 1, .shown, 1, .{ .rect = snap.cursor_cell.? }, cursor_view, &snap);
    try std.testing.expect(c.SDL_RenderPresent(first_renderer));
    for (0..snap.surface.height) |y| for (0..snap.surface.width) |x| {
        var one: [4]u8 = undefined;
        var two: [4]u8 = undefined;
        if (!c.SDL_ReadSurfacePixel(first_surface, @intCast(x), @intCast(y), &one[0], &one[1], &one[2], &one[3]) or
            !c.SDL_ReadSurfacePixel(second_surface, @intCast(x), @intCast(y), &two[0], &two[1], &two[2], &two[3])) return error.SDL;
        try std.testing.expectEqualDeep(two, one);
    };
    const cell = snap.cursor_cell.?;
    var visual: cursor_effects.Visual = .{ .rect = .{ .x = cell.x - @as(i32, snap.cell_width), .y = cell.y, .width = cell.width, .height = cell.height }, .stretch = .{ -2, 0 }, .ghost_count = 1 };
    visual.ghosts[0] = .{ .rect = cell, .alpha = 128 };
    try first.drawCut(first_renderer, geometry, pane, 1, .shown, 1, visual, cursor_view, &snap);
    try std.testing.expect(c.SDL_RenderPresent(first_renderer));
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

test "direct sized text and block cursor agree across independent Canvas paths" {
    try expectDirectCanvasPixelParity("M😀\x1b[2;1H\x1b]66;s=1:w=2;WWW\x07\x1b[3;1H\x1b[1;4;9;38;2;200;80;50;48;5;17m\x1b]66;s=1:w=7;X\x07\x1b[0m\x1b[1;2H");
    try expectDirectCanvasPixelParity("M😀\x1b[2;1H\x1b[4;9m\x1b]66;s=2;X\x07\x1b[0m\x1b[2;4H\x1b[4:4m\x1b]66;s=2:n=2:d=3:h=2:v=2;I\x07\x1b[0m\x1b[2;10H\x1b[4:5m\x1b]66;s=2:n=1:d=2:h=1:v=1;I\x07\x1b[0m\x1b[2;8H\x1b]66;s=1:n=1:d=2:h=1:v=1;W\x07\x1b[5;1H\x1b[4:2;9m\x1b]66;s=3;e\u{0301}\x07\x1b[0m\x1b[5;4H\x1b[4:3m\x1b]66;s=2:n=2:d=3:h=2:v=2;I\x07\x1b[0m\x1b[5;7H\x1b]66;s=2:n=1:d=2:h=2:v=2;X\x07\x1b[5;10H\x1b]66;s=2:n=2:d=3:h=1:v=1;W\x07\x1b[7;10H\x1b]66;s=2;─\x07\x1b[1;2H");
    try expectDirectCanvasPixelParity("M😀\x1b[2;1H\x1b]66;s=2;😀\x07\x1b[2;6H\x1b]66;s=2:n=1:d=2:h=2:v=2;😀\x07\x1b[1;2H");
    try expectDirectCanvasPixelParity("M😀\x1b[2;1H\x1b]66;s=2;→\x07\x1b[2;5H\x1b]66;s=2:n=1:d=2:h=2:v=2;◆\x07\x1b[1;2H");
    try expectDirectCanvasPixelParity("M😀\x1b[2;1H\x1b]66;s=2:n=2:d=3:h=2:v=2;┼\x07\x1b[2;4H\x1b]66;s=3;█\x07\x1b[2;8H\x1b]66;s=2;⣿\x07\x1b[6;1H\x1b]66;s=2;\u{e0b0}\x07\x1b[1;2H");
}

test "direct worker retained Canvas matches its complete direct cut" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const presentation: app_presentation.Config = .{
        .text = .{ .private = .{ .regular = .{ .path = .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 15 } } } } },
        .box_drawing = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
        .shape_cache = .{ .entry_capacity = 32, .scalar_capacity = 128, .glyph_capacity = 128, .max_sequence_scalars = 16 },
        .atlas = .{ .width = 256, .height = 256, .entry_capacity = 128 },
        .shaped_capacity = 128,
        .raster_bytes = 256 * 256,
    };
    const owner = try terminal.Terminal.create(std.testing.allocator, threaded.io(), std.testing.environ, .{
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
        try std.testing.expectEqual(frame.terminal_revision, direct.lease.?.snapshot.terminal_revision);
        const snapshot = &direct.lease.?.snapshot;
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
    const font = try @import("howl_text").FontSet.init(std.testing.allocator, .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 12 } });
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
            try std.testing.expectError(error.MissingTexture, direct.drawCut(first_renderer, geometry, pane, 1, .hidden, 1, null, info, snapshot));
            try direct.applySnapshotResources(first_renderer, 1, snapshot);
        }
        try direct.drawCut(first_renderer, geometry, pane, 1, .hidden, 1, null, info, snapshot);
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

test "colour atlas survives alternating clipped scales" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    const a = std.testing.allocator;
    const surface = c.SDL_CreateSurface(228, 224, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    var canvas = Canvas.init(a);
    defer canvas.deinit();
    const geometry = try a.create(Geometry);
    defer a.destroy(geometry);
    geometry.* = .{};
    const id: output_commands.ResourceRef = .{ .resource = try output_commands.ResourceId.init(1), .generation = @fromBackingInt(1) };
    const pixels = try a.alloc(u8, 256 * 256 * 4);
    defer a.free(pixels);
    @memset(pixels, 0);
    for (0..16) |y| for (0..20) |x| {
        const at = (y * 256 + x) * 4;
        pixels[at..][0..4].* = .{ 255, 0, 0, 255 };
    };
    const upload: output_commands.FrameResourceUpload = .{ .resource = id, .format = .rgba8, .size = .{ .width = 256, .height = 256 }, .pixel_offset = 0, .pixel_count = pixels.len, .stride = 1024 };
    try canvas.applyResources(renderer, 1, &.{upload}, &.{}, pixels);
    const view: output_commands.ResourceView = .{ .resource = id, .format = .rgba8, .size = .{ .width = 256, .height = 256 }, .source = .{ .x = 0, .y = 0, .width = 20, .height = 16 } };
    const small: output_commands.Command = .{ .rgba = .{ .destination = .{ .x = 104, .y = 48, .width = 20, .height = 16 }, .clip = .{ .x = 104, .y = 48, .width = 20, .height = 8 }, .resource = view } };
    const large: output_commands.Command = .{ .rgba = .{ .destination = .{ .x = 0, .y = 41, .width = 38, .height = 30 }, .clip = .{ .x = 0, .y = 56, .width = 38, .height = 15 }, .resource = view } };
    const normal: output_commands.Command = .{ .rgba = .{ .destination = .{ .x = 28, .y = 6, .width = 20, .height = 16 }, .clip = .{ .x = 28, .y = 6, .width = 20, .height = 16 }, .resource = view } };
    const pane: c.SDL_FRect = .{ .x = 0, .y = 0, .w = 228, .h = 224 };
    try canvas.drawCommands(renderer, geometry, pane, &.{ small, large });
    try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, 220, 220, 220, 255));
    try std.testing.expect(c.SDL_RenderClear(renderer));
    try canvas.drawCommands(renderer, geometry, pane, &.{normal});
    try std.testing.expect(c.SDL_RenderPresent(renderer));
    var pixel: [4]u8 = undefined;
    try std.testing.expect(c.SDL_ReadSurfacePixel(surface, 28, 6, &pixel[0], &pixel[1], &pixel[2], &pixel[3]));
    try std.testing.expectEqualDeep([4]u8{ 255, 0, 0, 255 }, pixel);
}

test "direct Canvas cursor and selection pixels match an independent SDL composition" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    const surface = c.SDL_CreateSurface(96, 64, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    try std.testing.expect(c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND));
    var backend = Canvas.init(std.testing.allocator);
    defer backend.deinit();
    const geometry = try std.testing.allocator.create(Geometry);
    defer std.testing.allocator.destroy(geometry);
    geometry.* = .{};

    const background_color: output_commands.Color = .{ .r = 10, .g = 20, .b = 30, .a = 255 };
    const cursor_color: output_commands.Color = .{ .r = 230, .g = 40, .b = 70, .a = 255 };
    const background: output_commands.Command = .{ .solid = .{ .rect = .{ .x = 0, .y = 0, .width = 40, .height = 20 }, .color = background_color } };
    const cursor_rect: output_commands.Rect = .{ .x = 10, .y = 0, .width = 10, .height = 10 };
    const cursor_command: output_commands.Command = .{ .solid = .{ .rect = cursor_rect, .color = cursor_color } };
    var snapshot = testSnapshot(background, &.{
        .{ .y = 0, .backgrounds = &.{}, .decorations = &.{}, .glyphs = &.{} },
        .{ .y = 10, .backgrounds = &.{}, .decorations = &.{}, .glyphs = &.{} },
    }, cursor_command, &.{}, 10);
    snapshot.surface = .{ .width = 40, .height = 20 };
    snapshot.cols = 4;
    snapshot.cell_width = 10;
    snapshot.cursor_cell = cursor_rect;
    snapshot.cursor_shape = .block;
    snapshot.cursor_text_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 };
    snapshot.content_revision = 1;
    snapshot.visual_context = 1;
    const info = @import("frame_info.zig").Info.fromSnapshot(&snapshot, 1, 1);

    var drawn: [96 * 64][4]u8 = undefined;
    for ([_]CursorDisplay{ .shown, .hidden, .outline }) |mode|
        for ([_]bool{ false, true }) |selected|
            for ([_]bool{ false, true }) |moving|
                for ([_]f32{ 1, 1.25, 1.6, 2 }) |scale| {
                    backend.selection_paint = .{ .rows = 2 };
                    if (selected) backend.selection_paint.add(0, 0, 1);
                    var visual: cursor_effects.Visual = .{
                        .rect = .{ .x = 20, .y = 0, .width = 10, .height = 10 },
                        .ghost_count = 1,
                        .stretch = .{ 5, 0 },
                    };
                    visual.ghosts[0] = .{ .rect = .{ .x = 15, .y = 0, .width = 10, .height = 10 }, .alpha = 128 };
                    const motion: ?cursor_effects.Visual = if (moving) visual else null;
                    try std.testing.expect(c.SDL_SetRenderScale(renderer, scale, scale));
                    try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255));
                    try std.testing.expect(c.SDL_RenderClear(renderer));
                    try backend.drawCut(renderer, geometry, .{ .x = 7 / scale, .y = 11 / scale, .w = 40 / scale, .h = 20 / scale }, scale, mode, 3, motion, info, &snapshot);
                    try std.testing.expect(c.SDL_RenderPresent(renderer));
                    var xscale: f32 = 0;
                    var yscale: f32 = 0;
                    try std.testing.expect(c.SDL_GetRenderScale(renderer, &xscale, &yscale));
                    try std.testing.expectEqual(scale, xscale);
                    try std.testing.expectEqual(scale, yscale);
                    try std.testing.expect(!c.SDL_RenderClipEnabled(renderer));
                    for (0..64) |y| for (0..96) |x| {
                        const pixel = &drawn[y * 96 + x];
                        try std.testing.expect(c.SDL_ReadSurfacePixel(surface, @intCast(x), @intCast(y), &pixel[0], &pixel[1], &pixel[2], &pixel[3]));
                    };

                    // Reference uses SDL rectangles only, no Canvas command traversal or row code.
                    try std.testing.expect(c.SDL_SetRenderScale(renderer, 1, 1));
                    try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255));
                    try std.testing.expect(c.SDL_RenderClear(renderer));
                    try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, background_color.r, background_color.g, background_color.b, 255));
                    const pane: c.SDL_FRect = .{ .x = 7, .y = 11, .w = 40, .h = 20 };
                    try std.testing.expect(c.SDL_RenderFillRect(renderer, &pane));
                    if (selected) {
                        try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, 180, 180, 180, 100));
                        const selected_rect: c.SDL_FRect = .{ .x = 7, .y = 11, .w = 20, .h = 10 };
                        try std.testing.expect(c.SDL_RenderFillRect(renderer, &selected_rect));
                    }
                    if (mode != .hidden) {
                        try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, cursor_color.r, cursor_color.g, cursor_color.b, 255));
                        if (mode == .outline) {
                            const edges = [_]c.SDL_FRect{
                                .{ .x = 17, .y = 11, .w = 10, .h = 3 },
                                .{ .x = 17, .y = 18, .w = 10, .h = 3 },
                                .{ .x = 17, .y = 11, .w = 3, .h = 10 },
                                .{ .x = 24, .y = 11, .w = 3, .h = 10 },
                            };
                            for (edges) |edge| try std.testing.expect(c.SDL_RenderFillRect(renderer, &edge));
                        } else if (moving) {
                            try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, cursor_color.r, cursor_color.g, cursor_color.b, 128));
                            const ghost: c.SDL_FRect = .{ .x = 22, .y = 11, .w = 10, .h = 10 };
                            try std.testing.expect(c.SDL_RenderFillRect(renderer, &ghost));
                            try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, cursor_color.r, cursor_color.g, cursor_color.b, 255));
                            const stretched: c.SDL_FRect = .{ .x = 27, .y = 11, .w = 15, .h = 10 };
                            try std.testing.expect(c.SDL_RenderFillRect(renderer, &stretched));
                        } else {
                            const stationary: c.SDL_FRect = .{ .x = 17, .y = 11, .w = 10, .h = 10 };
                            try std.testing.expect(c.SDL_RenderFillRect(renderer, &stationary));
                        }
                    }
                    try std.testing.expect(c.SDL_RenderPresent(renderer));
                    for (0..64) |y| for (0..96) |x| {
                        var expected: [4]u8 = undefined;
                        try std.testing.expect(c.SDL_ReadSurfacePixel(surface, @intCast(x), @intCast(y), &expected[0], &expected[1], &expected[2], &expected[3]));
                        if (!std.mem.eql(u8, &drawn[y * 96 + x], &expected)) {
                            std.debug.print("cursor pixel mismatch: mode={s}, selected={}, moving={}, scale={d}, x={d}, y={d}: actual={any} expected={any}\n", .{ @tagName(mode), selected, moving, scale, x, y, drawn[y * 96 + x], expected });
                            return error.CanvasPixelMismatch;
                        }
                    };
                };
}

test "direct graphics depth bands and removal repaint exact pixels" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    const surface = c.SDL_CreateSurface(40, 20, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    var backend = Canvas.init(std.testing.allocator);
    defer backend.deinit();
    const geometry = try std.testing.allocator.create(Geometry);
    defer std.testing.allocator.destroy(geometry);
    geometry.* = .{};

    const black: output_commands.Color = .{ .r = 0, .g = 0, .b = 0, .a = 255 };
    const blue: output_commands.Color = .{ .r = 0, .g = 0, .b = 255, .a = 255 };
    const cyan: output_commands.Color = .{ .r = 0, .g = 255, .b = 255, .a = 255 };
    const yellow: output_commands.Color = .{ .r = 255, .g = 255, .b = 0, .a = 255 };
    const solid = struct {
        fn make(x: i32, width: u16, color: output_commands.Color) output_commands.Command {
            return .{ .solid = .{ .rect = .{ .x = x, .y = 0, .width = width, .height = 10 }, .color = color } };
        }
    }.make;
    const default_background: output_commands.Command = .{ .solid = .{ .rect = .{ .x = 0, .y = 0, .width = 40, .height = 20 }, .color = black } };
    var snapshot = testSnapshot(default_background, &.{
        .{ .y = 0, .backgrounds = &.{ solid(0, 8, blue), solid(10, 10, blue) }, .decorations = &.{solid(12, 2, cyan)}, .glyphs = &.{ solid(10, 2, yellow), solid(20, 10, yellow) } },
        .{ .y = 10, .backgrounds = &.{}, .decorations = &.{}, .glyphs = &.{} },
    }, null, &.{}, 10);
    snapshot.surface = .{ .width = 40, .height = 20 };
    snapshot.cols = 4;
    snapshot.cell_width = 10;
    snapshot.atlas_pixels = &.{255};
    snapshot.content_revision = 1;
    snapshot.visual_context = 1;

    const red_id: output_commands.ResourceRef = .{ .resource = try output_commands.ResourceId.init(3), .generation = @fromBackingInt(1) };
    const green_id: output_commands.ResourceRef = .{ .resource = try output_commands.ResourceId.init(4), .generation = @fromBackingInt(1) };
    const white_id: output_commands.ResourceRef = .{ .resource = try output_commands.ResourceId.init(5), .generation = @fromBackingInt(1) };
    const image_type = @TypeOf(snapshot.graphics.images[0]);
    const images = [_]image_type{
        .{ .resource = red_id, .size = .{ .width = 1, .height = 1 }, .pixels = &.{ 255, 0, 0, 255 } },
        .{ .resource = green_id, .size = .{ .width = 1, .height = 1 }, .pixels = &.{ 0, 255, 0, 255 } },
        .{ .resource = white_id, .size = .{ .width = 1, .height = 1 }, .pixels = &.{ 255, 255, 255, 255 } },
    };
    const rgba = struct {
        fn make(x: i32, resource: output_commands.ResourceRef) output_commands.Command {
            return .{ .rgba = .{
                .destination = .{ .x = x, .y = 0, .width = 10, .height = 10 },
                .clip = .{ .x = 0, .y = 0, .width = 40, .height = 20 },
                .resource = .{ .resource = resource, .format = .rgba8, .size = .{ .width = 1, .height = 1 } },
            } };
        }
    }.make;
    const deep = [_]output_commands.Command{rgba(0, red_id)};
    const negative = [_]output_commands.Command{rgba(10, green_id)};
    const positive = [_]output_commands.Command{rgba(20, white_id)};
    snapshot.graphics = .{ .deep = &deep, .negative = &negative, .positive = &positive, .images = &images };
    const pane: c.SDL_FRect = .{ .x = 0, .y = 0, .w = 40, .h = 20 };

    try backend.applySnapshotResources(renderer, 1, &snapshot);
    try backend.drawCut(renderer, geometry, pane, 1, .hidden, 1, null, @import("frame_info.zig").Info.fromSnapshot(&snapshot, 1, 1), &snapshot);
    try std.testing.expect(c.SDL_RenderPresent(renderer));
    const points = [_]struct { x: i32, expected: [4]u8 }{
        .{ .x = 5, .expected = .{ 0, 0, 255, 255 } }, // deep red below blue background
        .{ .x = 9, .expected = .{ 255, 0, 0, 255 } }, // deep red remains visible outside nondefault background
        .{ .x = 11, .expected = .{ 255, 255, 0, 255 } }, // glyph above negative image
        .{ .x = 13, .expected = .{ 0, 255, 255, 255 } }, // decoration above negative image
        .{ .x = 18, .expected = .{ 0, 255, 0, 255 } }, // negative image above blue background
        .{ .x = 25, .expected = .{ 255, 255, 255, 255 } }, // nonnegative image above text
        .{ .x = 35, .expected = .{ 0, 0, 0, 255 } },
    };
    for (points) |point| {
        var pixel: [4]u8 = undefined;
        try std.testing.expect(c.SDL_ReadSurfacePixel(surface, point.x, 5, &pixel[0], &pixel[1], &pixel[2], &pixel[3]));
        try std.testing.expectEqualDeep(point.expected, pixel);
    }

    // Image-only removal changes no terminal row generation. It must still
    // retire backend pixels and completely reconstruct the retained target.
    snapshot.graphics = .{};
    snapshot.content_revision = 2;
    snapshot.visual_context = 2;
    try backend.applySnapshotResources(renderer, 1, &snapshot);
    try std.testing.expectEqual(@as(usize, 1), backend.count);
    try backend.drawCut(renderer, geometry, pane, 1, .hidden, 1, null, @import("frame_info.zig").Info.fromSnapshot(&snapshot, 1, 2), &snapshot);
    try std.testing.expect(c.SDL_RenderPresent(renderer));
    var removed: [4]u8 = undefined;
    try std.testing.expect(c.SDL_ReadSurfacePixel(surface, 25, 5, &removed[0], &removed[1], &removed[2], &removed[3]));
    // Removing the positive image reveals the yellow text beneath it.
    try std.testing.expectEqualDeep([4]u8{ 255, 255, 0, 255 }, removed);
}

test "native VT image-only removal invalidates Canvas without synthetic revisions" {
    const output = @import("howl_vt_output");
    const font = try @import("howl_text").FontSet.init(std.testing.allocator, .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 12 } });
    defer font.deinit();
    const owner = try output.Terminal.init(std.testing.allocator, font);
    // zig-audit: acknowledge catch_unreachable
    // reason: Both scoped snapshots release before this owner is destroyed.
    defer owner.deinit() catch unreachable;
    try owner.resize(2, 4);
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    const surface = c.SDL_CreateSurface(100, 60, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    var backend = Canvas.init(std.testing.allocator);
    defer backend.deinit();
    const geometry = try std.testing.allocator.create(Geometry);
    defer std.testing.allocator.destroy(geometry);
    geometry.* = .{};

    try owner.feed("\x1b_Ga=T,f=32,s=1,v=1,i=56,C=1,q=2;/wAA/w==\x1b\\");
    try owner.flush();
    var first_content: u64 = 0;
    var first_context: u64 = 0;
    {
        const held = try owner.hold();
        // zig-audit: acknowledge catch_unreachable
        // reason: Scoped test borrows exactly the current immutable output.
        defer owner.release(held) catch unreachable;
        const snapshot = &held.snapshot;
        try std.testing.expectEqual(@as(usize, 1), snapshot.graphics.images.len);
        first_content = snapshot.content_revision;
        first_context = snapshot.visual_context;
        try backend.applySnapshotResources(renderer, 1, snapshot);
        const pane: c.SDL_FRect = .{ .x = 0, .y = 0, .w = @floatFromInt(snapshot.surface.width), .h = @floatFromInt(snapshot.surface.height) };
        try backend.drawCut(renderer, geometry, pane, 1, .hidden, 1, null, @import("frame_info.zig").Info.fromSnapshot(snapshot, 1, 1), snapshot);
        try std.testing.expect(c.SDL_RenderPresent(renderer));
        var pixel: [4]u8 = undefined;
        try std.testing.expect(c.SDL_ReadSurfacePixel(surface, 0, 0, &pixel[0], &pixel[1], &pixel[2], &pixel[3]));
        try std.testing.expectEqualDeep([4]u8{ 255, 0, 0, 255 }, pixel);
    }

    try owner.feed("\x1b_Ga=d,d=A,q=2\x1b\\");
    try owner.flush();
    {
        const held = try owner.hold();
        // zig-audit: acknowledge catch_unreachable
        // reason: Scoped test borrows exactly the current immutable output.
        defer owner.release(held) catch unreachable;
        const snapshot = &held.snapshot;
        try std.testing.expectEqual(@as(usize, 0), snapshot.graphics.images.len);
        try std.testing.expect(snapshot.content_revision > first_content);
        try std.testing.expect(snapshot.visual_context > first_context);
        try backend.applySnapshotResources(renderer, 1, snapshot);
        try std.testing.expectEqual(@as(usize, 1), backend.count);
        const pane: c.SDL_FRect = .{ .x = 0, .y = 0, .w = @floatFromInt(snapshot.surface.width), .h = @floatFromInt(snapshot.surface.height) };
        try backend.drawCut(renderer, geometry, pane, 1, .hidden, 1, null, @import("frame_info.zig").Info.fromSnapshot(snapshot, 1, 2), snapshot);
        try std.testing.expect(c.SDL_RenderPresent(renderer));
        var pixel: [4]u8 = undefined;
        try std.testing.expect(c.SDL_ReadSurfacePixel(surface, 0, 0, &pixel[0], &pixel[1], &pixel[2], &pixel[3]));
        const color = snapshot.background.solid.color;
        try std.testing.expectEqualDeep([4]u8{ color.r, color.g, color.b, color.a }, pixel);
    }
}

test "split selection draws both runs without painting their gap" {
    if (!c.SDL_Init(c.SDL_INIT_EVENTS)) return error.SDL;
    defer c.SDL_Quit();
    const surface = c.SDL_CreateSurface(50, 10, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    var backend = Canvas.init(std.testing.allocator);
    defer backend.deinit();
    backend.selection_paint = .{ .rows = 1 };
    backend.selection_paint.add(0, 0, 1);
    backend.selection_paint.add(0, 3, 4);
    const frame: @import("frame_info.zig").Info = .{
        .sequence = 1,
        .presentation_generation = 1,
        .terminal_revision = 1,
        .surface = .{ .width = 50, .height = 10 },
        .cell_size = .{ .width = 10, .height = 10 },
    };
    try std.testing.expect(c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND));
    try std.testing.expect(c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255));
    try std.testing.expect(c.SDL_RenderClear(renderer));
    try backend.drawSelection(renderer, .{ .x = 0, .y = 0, .w = 50, .h = 10 }, frame);
    try std.testing.expect(c.SDL_RenderPresent(renderer));
    for ([_]i32{ 5, 15, 25, 35, 45 }, 0..) |x, index| {
        var red: u8 = 0;
        try std.testing.expect(c.SDL_ReadSurfacePixel(surface, x, 5, &red, null, null, null));
        try std.testing.expect(if (index == 2) red == 0 else red > 0);
    }
}
