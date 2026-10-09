const std = @import("std");
const c = @import("desktop");
const instance = @import("howl_instance");
const terminal = @import("terminal.zig");
const render = instance.render.terminal;

const resource_limit = render.maximum_external_images + 1;
const batch_quads = 2048;

const Texture = struct {
    residency: render.Residency,
    texture: *c.SDL_Texture,
};

/// One graphical-thread scratch batch shared by all panes.
pub const Geometry = struct {
    vertices: [batch_quads * 4]c.SDL_Vertex = undefined,
    indices: [batch_quads * 6]c_int = undefined,
    count: usize = 0,
    texture: ?*c.SDL_Texture = null,
    clip: c.SDL_Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },

    fn flush(self: *Geometry, renderer: *c.SDL_Renderer) !void {
        if (self.count == 0) return;
        if (!c.SDL_SetRenderClipRect(renderer, &self.clip) or
            !c.SDL_RenderGeometry(renderer, self.texture, &self.vertices, @intCast(self.count * 4), &self.indices, @intCast(self.count * 6)))
            return error.SDLGeometry;
        self.count = 0;
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
        const vertex: c_int = @intCast(base);
        self.indices[self.count * 6 ..][0..6].* = .{ vertex, vertex + 1, vertex + 2, vertex, vertex + 2, vertex + 3 };
        self.count += 1;
    }
};

/// Holds one immutable canonical frame until a newer publication replaces it.
/// The producer retains two free/replaceable slots and never waits for this lease.
pub const Canvas = struct {
    allocator: std.mem.Allocator,
    lease: ?instance.RenderLease = null,
    textures: [resource_limit]Texture = undefined,
    count: usize = 0,
    converted: std.ArrayList(u8) = .empty,
    generation: u64 = 0,

    /// Creates an empty backend resource owner with no canonical or frame authority.
    pub fn init(allocator: std.mem.Allocator) Canvas {
        return .{ .allocator = allocator };
    }

    /// Retires the held frame before releasing graphical resources and scratch.
    pub fn deinit(self: *Canvas) void {
        if (self.lease) |*lease| lease.abandon();
        self.clearTextures();
        self.converted.deinit(self.allocator);
        self.* = undefined;
    }

    /// Borrows the held immutable publication; valid until update or deinit.
    pub fn frame(self: *const Canvas) ?instance.PublishedFrame {
        return if (self.lease) |lease| lease.value else null;
    }

    /// Transfers an immutable publication only when ready; duplicate wakeups keep the old lease.
    pub fn update(self: *Canvas, renderer: *c.SDL_Renderer, owner: *terminal.Terminal) !void {
        var residency: [resource_limit]render.Residency = undefined;
        for (self.textures[0..self.count], 0..) |texture, index| residency[index] = texture.residency;
        var lease = (try owner.replaceFrame(if (self.lease) |*previous| previous else null, residency[0..self.count])) orelse return;
        self.lease = null;
        errdefer lease.abandon();
        const value = lease.value;
        if (self.generation != value.presentation_generation) {
            self.clearTextures();
            self.generation = value.presentation_generation;
        }
        for (value.removals) |resource| self.remove(resource, true);
        for (value.uploads) |upload| {
            const source = value.pixels[upload.pixel_offset..][0..upload.pixel_count];
            const width: usize = upload.size.width;
            const height: usize = upload.size.height;
            var pixels: []const u8 = source;
            var stride = upload.stride;
            if (upload.format == .alpha8) {
                try self.converted.resize(self.allocator, width * height * 4);
                for (0..height) |y| for (0..width) |x| {
                    const at = (y * width + x) * 4;
                    self.converted.items[at..][0..4].* = .{ 255, 255, 255, source[y * upload.stride + x] };
                };
                pixels = self.converted.items;
                stride = width * 4;
            }
            const texture = c.SDL_CreateTexture(renderer, c.SDL_PIXELFORMAT_RGBA32, c.SDL_TEXTUREACCESS_STATIC, upload.size.width, upload.size.height) orelse return error.SDLTexture;
            var owned = true;
            errdefer if (owned) c.SDL_DestroyTexture(texture);
            if (!c.SDL_SetTextureScaleMode(texture, c.SDL_SCALEMODE_NEAREST) or
                !c.SDL_SetTextureBlendMode(texture, c.SDL_BLENDMODE_BLEND) or
                !c.SDL_UpdateTexture(texture, null, pixels.ptr, @intCast(stride))) return error.SDLTexture;
            self.remove(upload.resource, false);
            if (self.count == resource_limit) return error.ResourceLimit;
            self.textures[self.count] = .{
                .texture = texture,
                .residency = .{ .resource = upload.resource, .format = upload.format, .size = upload.size },
            };
            self.count += 1;
            owned = false;
        }
        self.lease = lease;
    }

    /// Draws canonical commands with exact pane/resource clipping using shared bounded batches.
    pub fn draw(self: *Canvas, renderer: *c.SDL_Renderer, geometry: *Geometry, pane: c.SDL_FRect, scale: f32) !void {
        const value = self.frame() orelse return;
        const pane_clip = pixelClip(pane);
        geometry.count = 0;
        for (value.commands) |command| {
            switch (command) {
                .solid => |solid| try geometry.append(renderer, null, pane_clip, destination(solid.rect, pane, scale), .{ .x = 0, .y = 0, .w = 0, .h = 0 }, solid.color),
                .alpha_mask => |mask| {
                    const texture = self.find(mask.resource.resource) orelse return error.MissingTexture;
                    const dest = destination(mask.destination, pane, scale);
                    var clip: c.SDL_Rect = undefined;
                    const requested = if (contained(mask.destination, mask.clip)) pane_clip else pixelClip(destination(mask.clip, pane, scale));
                    if (!c.SDL_GetRectIntersection(&requested, &pane_clip, &clip)) continue;
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
                    var clip: c.SDL_Rect = undefined;
                    const requested = if (contained(image.destination, image.clip)) pane_clip else pixelClip(destination(image.clip, pane, scale));
                    if (!c.SDL_GetRectIntersection(&requested, &pane_clip, &clip)) continue;
                    const src: render.SourceRect = image.resource.source orelse .{ .x = 0, .y = 0, .width = image.resource.size.width, .height = image.resource.size.height };
                    const source: c.SDL_FRect = .{ .x = @floatFromInt(src.x), .y = @floatFromInt(src.y), .w = @floatFromInt(src.width), .h = @floatFromInt(src.height) };
                    const dest = destination(image.destination, pane, scale);
                    if (!c.SDL_SetRenderClipRect(renderer, &clip) or
                        !c.SDL_RenderTexture(renderer, texture, &source, &dest)) return error.SDLTexture;
                },
            }
        }
        try geometry.flush(renderer);
        if (!c.SDL_SetRenderClipRect(renderer, null)) return error.SDLClip;
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
        for (self.textures[0..self.count]) |texture| c.SDL_DestroyTexture(texture.texture);
        self.count = 0;
    }
};

fn destination(rect: render.Rect, pane: c.SDL_FRect, scale: f32) c.SDL_FRect {
    return .{
        .x = pane.x + @as(f32, @floatFromInt(rect.x)) / scale,
        .y = pane.y + @as(f32, @floatFromInt(rect.y)) / scale,
        .w = @as(f32, @floatFromInt(rect.width)) / scale,
        .h = @as(f32, @floatFromInt(rect.height)) / scale,
    };
}

fn pixelClip(rect: c.SDL_FRect) c.SDL_Rect {
    const x: c_int = @intFromFloat(@floor(rect.x));
    const y: c_int = @intFromFloat(@floor(rect.y));
    return .{ .x = x, .y = y, .w = @as(c_int, @intFromFloat(@ceil(rect.x + rect.w))) - x, .h = @as(c_int, @intFromFloat(@ceil(rect.y + rect.h))) - y };
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
        .fonts = .{ .regular = .{ .path = .{ .primary = @import("test_fonts").primary_font, .size = .{ .pixels = 15 } } } },
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
    backend = Canvas.init(std.testing.allocator);
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
    accepted_generation = accepted.presentation_generation;
    try std.testing.expect(accepted.presentation_generation > 1);
    const geometry = try std.testing.allocator.create(Geometry);
    defer std.testing.allocator.destroy(geometry);
    geometry.* = .{};
    try backend.draw(renderer, geometry, .{ .x = 0, .y = 0, .w = 250, .h = 100 }, 1);
    try std.testing.expect(c.SDL_RenderPresent(renderer));
    try std.testing.expectEqual(@as(?terminal.Failure, null), owner.snapshot().failure);
}
