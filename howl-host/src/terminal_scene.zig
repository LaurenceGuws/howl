//! Bridges one canonical Session snapshot into the native Vulkan surface model.
//!
//! This owner is intentionally host-local. Session remains canonical terminal
//! truth, Render owns terminal/Canvas projection, and howl-vk owns backend
//! residency and geometry. This file only composes those existing contracts.

const std = @import("std");
const client = @import("howl_client");
const presentation = @import("presentation");
const terminal = @import("terminal");
const canvas = terminal;
const terminal_fast = @import("terminal_fast.zig");
const text = @import("howl_text");
const vk_surface = @import("howl_vk").surface;

const resource_limit: usize = terminal.maximum_external_images + 1;
const prospective_resource_limit: usize = resource_limit + terminal.maximum_external_images;
const overlay_resource_limit: usize = terminal_fast.overlay_resource_limit;
const atlas_extent: u16 = 512;
const atlas_pixel_bytes: usize = @as(usize, atlas_extent) * atlas_extent;
const command_capacity: usize = presentation.maximum_canvas_commands;
const surface_pixel_bytes: usize = 16 * 1024 * 1024;

const ExternalUpload = struct {
    external: canvas.FrameExternalResource,
    fetched: client.images.Resource,
};

pub const GenericPrepared = struct {
    plan: vk_surface.Plan,
};

pub const FastPrepared = struct {
    terminal: terminal_fast.Prepared,
    plan: vk_surface.Plan,
    overlay_pending: bool,
};

const empty_plan = vk_surface.Plan{
    .vertices = &.{},
    .indices = &.{},
    .commands = &.{},
    .atlas_changed = false,
};

pub const Prepared = struct {
    rows: u16,
    cols: u16,
    width: u16,
    height: u16,
    session_revision: u64,
    leader_present: bool,
    you_are_leader: bool,
    mode: union(enum) {
        generic: GenericPrepared,
        fast: FastPrepared,
    },
};

pub fn measureCellSize(
    allocator: std.mem.Allocator,
    font_path: []const u8,
    font_pixels: u16,
) !canvas.Size {
    if (font_pixels == 0) return error.InvalidFontPixels;
    const fonts = try text.FontSet.init(allocator, .{
        .primary = font_path,
        .size = .{ .pixels = font_pixels },
    });
    defer fonts.deinit();
    const metrics = fonts.metrics();
    return .{ .width = metrics.advance_width, .height = metrics.line_height };
}

pub const Scene = struct {
    allocator: std.mem.Allocator,
    connection: client.Connection,
    raw_cache: client.rich.RawCache,
    fonts: *text.FontSet,
    fast: terminal_fast.Adapter,
    canvas: *terminal.Canvas,
    cell_size: canvas.Size,
    frame_uploads: []canvas.FrameResourceUpload,
    frame_removals: []canvas.ResourceRef,
    frame_commands: []canvas.Command,
    frame_pixels: []u8,
    surface_uploads: []vk_surface.Upload,
    surface_removals: []vk_surface.Removal,
    surface_commands: []vk_surface.FrameCommand,
    surface_residencies: []vk_surface.Residency,
    canvas_residencies: []canvas.Residency,
    image_bindings: [terminal.maximum_external_images]terminal.ExternalImageBinding = undefined,
    image_binding_count: usize = 0,
    builder: vk_surface.FrameBuilder,
    residency: vk_surface.ResidencyStore,
    overlay_residency: vk_surface.ResidencyStore,
    observation_pending: bool = false,

    pub fn init(
        allocator: std.mem.Allocator,
        endpoint: []const u8,
        font_path: []const u8,
        font_pixels: u16,
    ) !Scene {
        if (font_pixels == 0) return error.InvalidFontPixels;
        var connection = try client.Connection.connect(allocator, endpoint);
        errdefer connection.deinit();
        var raw_cache = client.rich.RawCache.init(allocator);
        errdefer raw_cache.deinit();
        const fonts = try text.FontSet.init(allocator, .{
            .primary = font_path,
            .size = .{ .pixels = font_pixels },
        });
        errdefer fonts.deinit();
        const metrics = fonts.metrics();
        var fast = try terminal_fast.Adapter.init(allocator, fonts);
        errdefer fast.deinit();
        const cell_size = canvas.Size{
            .width = metrics.advance_width,
            .height = metrics.line_height,
        };
        const terminal_canvas = try terminal.initCanvas(
            allocator,
            fonts,
            .{
                .cell_size = cell_size,
                .box_drawing = .{
                    .dpi_x = .{ .numerator = 96, .denominator = 1 },
                    .dpi_y = .{ .numerator = 96, .denominator = 1 },
                },
                .shape_cache = .{
                    .entry_capacity = 1024,
                    .scalar_capacity = 4096,
                    .glyph_capacity = 4096,
                    .max_sequence_scalars = 32,
                },
                .atlas = .{
                    .width = atlas_extent,
                    .height = atlas_extent,
                    .entry_capacity = 1024,
                },
                .shaped_capacity = 128,
                .raster_bytes = atlas_pixel_bytes,
                .command_capacity = command_capacity,
            },
        );
        errdefer terminal.deinitCanvas(terminal_canvas);

        const frame_uploads = try allocator.alloc(canvas.FrameResourceUpload, resource_limit);
        errdefer allocator.free(frame_uploads);
        const frame_removals = try allocator.alloc(canvas.ResourceRef, resource_limit);
        errdefer allocator.free(frame_removals);
        const frame_commands = try allocator.alloc(canvas.Command, command_capacity);
        errdefer allocator.free(frame_commands);
        const frame_pixels = try allocator.alloc(u8, atlas_pixel_bytes);
        errdefer allocator.free(frame_pixels);
        const surface_uploads = try allocator.alloc(vk_surface.Upload, resource_limit);
        errdefer allocator.free(surface_uploads);
        const surface_removals = try allocator.alloc(vk_surface.Removal, resource_limit);
        errdefer allocator.free(surface_removals);
        const surface_commands = try allocator.alloc(vk_surface.FrameCommand, command_capacity);
        errdefer allocator.free(surface_commands);
        const surface_residencies = try allocator.alloc(vk_surface.Residency, resource_limit);
        errdefer allocator.free(surface_residencies);
        const canvas_residencies = try allocator.alloc(canvas.Residency, prospective_resource_limit);
        errdefer allocator.free(canvas_residencies);
        var builder = try vk_surface.FrameBuilder.init(allocator);
        errdefer builder.deinit();
        var residency = try vk_surface.ResidencyStore.init(allocator, .{
            .resources = resource_limit,
            .pixel_bytes = surface_pixel_bytes,
        });
        errdefer residency.deinit();
        var overlay_residency = try vk_surface.ResidencyStore.init(allocator, .{
            .resources = overlay_resource_limit,
            .pixel_bytes = vk_surface.atlas_bytes,
        });
        errdefer overlay_residency.deinit();

        return .{
            .allocator = allocator,
            .connection = connection,
            .raw_cache = raw_cache,
            .fonts = fonts,
            .fast = fast,
            .canvas = terminal_canvas,
            .cell_size = cell_size,
            .frame_uploads = frame_uploads,
            .frame_removals = frame_removals,
            .frame_commands = frame_commands,
            .frame_pixels = frame_pixels,
            .surface_uploads = surface_uploads,
            .surface_removals = surface_removals,
            .surface_commands = surface_commands,
            .surface_residencies = surface_residencies,
            .canvas_residencies = canvas_residencies,
            .builder = builder,
            .residency = residency,
            .overlay_residency = overlay_residency,
        };
    }

    pub fn deinit(self: *Scene) void {
        self.overlay_residency.deinit();
        self.residency.deinit();
        self.builder.deinit();
        self.allocator.free(self.canvas_residencies);
        self.allocator.free(self.surface_residencies);
        self.allocator.free(self.surface_commands);
        self.allocator.free(self.surface_removals);
        self.allocator.free(self.surface_uploads);
        self.allocator.free(self.frame_pixels);
        self.allocator.free(self.frame_commands);
        self.allocator.free(self.frame_removals);
        self.allocator.free(self.frame_uploads);
        terminal.deinitCanvas(self.canvas);
        self.fast.deinit();
        self.fonts.deinit();
        self.raw_cache.deinit();
        self.connection.deinit();
        self.* = undefined;
    }

    pub fn cancellation(self: *const Scene) error{ SocketDuplicateFailed, SocketOptionFailed }!client.Cancellation {
        return self.connection.cancellation();
    }

    /// Arms one revision-relative delta observation without receiving it yet.
    pub fn arm(self: *Scene, after_revision: u64) !void {
        if (self.observation_pending) return error.ObservationPending;
        try self.raw_cache.sendDeltaRequest(&self.connection, after_revision, 0);
        self.observation_pending = true;
    }

    /// Borrows this Scene's socket only for readiness polling.
    pub fn readinessFd(self: *const Scene) std.posix.fd_t {
        return self.connection.readinessFd();
    }

    /// Receives and projects exactly one previously armed delta/raw-fallback observation.
    pub fn receivePrepared(self: *Scene) !Prepared {
        if (!self.observation_pending) return error.ObservationNotPending;
        const rich = try self.raw_cache.receive(&self.connection);
        self.observation_pending = false;
        const begin = rich.begin;
        const width = std.math.mul(u16, begin.columns, self.cell_size.width) catch
            return error.InvalidGeometry;
        const height = std.math.mul(u16, begin.rows, self.cell_size.height) catch
            return error.InvalidGeometry;
        if (width == 0 or height == 0) return error.InvalidGeometry;
        if (try self.fast.prepare(&rich, width, height)) |fast| {
            var plan = empty_plan;
            var overlay_pending = false;
            if (fast.overlay_frame.commands.len != 0) {
                try self.overlay_residency.stage(fast.overlay_frame);
                errdefer self.overlay_residency.discard();
                plan = try self.builder.build(&self.overlay_residency, fast.overlay_frame);
                overlay_pending = true;
            }
            return .{
                .rows = begin.rows,
                .cols = begin.columns,
                .width = width,
                .height = height,
                .session_revision = begin.revision,
                .leader_present = begin.leader_present,
                .you_are_leader = begin.you_are_leader,
                .mode = .{ .fast = .{
                    .terminal = fast,
                    .plan = plan,
                    .overlay_pending = overlay_pending,
                } },
            };
        }

        const view = try client.view.projectView(self.allocator, &rich);
        defer client.view.deinit(view);
        const graphics = client.view.graphics(view);
        var candidate_bindings: [terminal.maximum_external_images]terminal.ExternalImageBinding = undefined;
        const bindings = try terminal.planExternalImageBindings(
            self.image_bindings[0..self.image_binding_count],
            terminal.canvasUsage(self.canvas),
            graphics.images,
            &candidate_bindings,
        );
        try terminal.updateWithImageBindings(self.canvas, view, bindings);
        @memcpy(self.image_bindings[0..bindings.len], bindings);
        self.image_binding_count = bindings.len;

        const resident = try self.residency.enumerate(self.surface_residencies);
        if (resident.len > self.canvas_residencies.len) return error.Capacity;
        for (resident, 0..) |value, index| {
            self.canvas_residencies[index] = .{
                .resource = try canvasResource(value.resource),
                .format = switch (value.kind) {
                    .alpha_mask => .alpha8,
                    .rgba => .rgba8,
                    .solid => return error.InvalidFrame,
                },
                .size = .{ .width = value.width, .height = value.height },
            };
        }
        var canvas_residency_count = resident.len;
        var external_uploads: [terminal.maximum_external_images]ExternalUpload = undefined;
        var external_upload_count: usize = 0;
        defer clearExternalUploads(&external_uploads, &external_upload_count);
        try self.prepareExternalUploads(
            bindings,
            &canvas_residency_count,
            &external_uploads,
            &external_upload_count,
        );
        const frame = try terminal.frame(
            self.canvas,
            self.canvas_residencies[0..canvas_residency_count],
            .{
                .uploads = self.frame_uploads,
                .removals = self.frame_removals,
                .commands = self.frame_commands,
                .pixels = self.frame_pixels,
            },
        );
        const generic = try adaptCanvasFrame(
            frame,
            external_uploads[0..external_upload_count],
            self.surface_uploads,
            self.surface_removals,
            self.surface_commands,
        );
        try self.residency.stage(generic);
        errdefer self.residency.discard();
        const plan = try self.builder.build(&self.residency, generic);
        return .{
            .rows = begin.rows,
            .cols = begin.columns,
            .width = width,
            .height = height,
            .session_revision = begin.revision,
            .leader_present = begin.leader_present,
            .you_are_leader = begin.you_are_leader,
            .mode = .{ .generic = .{ .plan = plan } },
        };
    }

    fn prepareExternalUploads(
        self: *Scene,
        bindings: []const terminal.ExternalImageBinding,
        canvas_residency_count: *usize,
        uploads: *[terminal.maximum_external_images]ExternalUpload,
        upload_count: *usize,
    ) !void {
        var missing_storage: [terminal.maximum_external_images]canvas.FrameExternalResource = undefined;
        const missing = try terminal.missingExternalResources(
            self.canvas,
            self.canvas_residencies[0..canvas_residency_count.*],
            &missing_storage,
        );
        if (missing.len > uploads.len) return error.Capacity;

        for (missing) |external| {
            if (external.format != .rgba8) return error.InvalidFrame;
            const binding = findImageBindingByResource(bindings, external.resource) orelse
                return error.InvalidFrame;
            var fetched = try client.images.request(
                &self.connection,
                self.allocator,
                binding.image_id,
                binding.generation,
            );
            var fetched_owned = true;
            errdefer if (fetched_owned) fetched.deinit();

            const stride = std.math.mul(usize, @as(usize, external.size.width), 4) catch
                return error.ArithmeticOverflow;
            const pixel_count = std.math.mul(usize, stride, external.size.height) catch
                return error.ArithmeticOverflow;
            if (external.stride != stride or
                fetched.width != external.size.width or
                fetched.height != external.size.height or
                fetched.pixels.len != pixel_count)
                return error.InvalidFrame;

            uploads[upload_count.*] = .{ .external = external, .fetched = fetched };
            upload_count.* += 1;
            fetched_owned = false;
            try upsertCanvasResidency(
                self.canvas_residencies,
                canvas_residency_count,
                .{
                    .resource = external.resource,
                    .format = external.format,
                    .size = external.size,
                },
            );
        }
    }

    /// Abandons one prepared frame that will never be submitted. This is used
    /// by geometry transactions that must replace an initial observation before
    /// Vulkan ownership exists; accepted residency remains untouched.
    pub fn discardPrepared(self: *Scene, prepared: Prepared) void {
        switch (prepared.mode) {
            .generic => self.residency.discard(),
            .fast => |frame| if (frame.overlay_pending) self.overlay_residency.discard(),
        }
    }

    pub fn cellSize(self: *const Scene) canvas.Size {
        return self.cell_size;
    }

    /// Arms and receives one raw observation synchronously.
    pub fn prepare(self: *Scene, after_revision: u64) !Prepared {
        try self.arm(after_revision);
        return self.receivePrepared();
    }

    pub fn complete(self: *Scene) !void {
        try self.residency.complete();
    }
};

fn clearExternalUploads(
    uploads: *[terminal.maximum_external_images]ExternalUpload,
    count: *usize,
) void {
    while (count.* != 0) {
        count.* -= 1;
        uploads[count.*].fetched.deinit();
    }
}

fn findImageBindingByResource(
    bindings: []const terminal.ExternalImageBinding,
    resource: canvas.ResourceRef,
) ?terminal.ExternalImageBinding {
    for (bindings) |binding| {
        if (std.meta.eql(binding.resource, resource)) return binding;
    }
    return null;
}

fn upsertCanvasResidency(
    storage: []canvas.Residency,
    count: *usize,
    value: canvas.Residency,
) error{Capacity}!void {
    for (storage[0..count.*]) |*existing| {
        if (existing.resource.resource == value.resource.resource) {
            existing.* = value;
            return;
        }
    }
    if (count.* == storage.len) return error.Capacity;
    storage[count.*] = value;
    count.* += 1;
}

fn adaptCanvasFrame(
    frame: terminal.Frame,
    external_uploads: []const ExternalUpload,
    uploads: []vk_surface.Upload,
    removals: []vk_surface.Removal,
    commands: []vk_surface.FrameCommand,
) !vk_surface.Frame {
    const upload_count = std.math.add(usize, frame.uploads.len, external_uploads.len) catch
        return error.ArithmeticOverflow;
    if (upload_count > uploads.len or
        frame.removals.len > removals.len or
        frame.commands.len > commands.len)
        return error.Capacity;
    for (frame.uploads, 0..) |value, index| {
        const end = std.math.add(usize, value.pixel_offset, value.pixel_count) catch
            return error.ArithmeticOverflow;
        if (end > frame.pixels.len) return error.Capacity;
        uploads[index] = .{
            .resource = try surfaceResource(value.resource),
            .kind = switch (value.format) {
                .alpha8 => .alpha_mask,
                .rgba8 => .rgba,
            },
            .width = value.size.width,
            .height = value.size.height,
            .stride = value.stride,
            .pixels = frame.pixels[value.pixel_offset..end],
        };
    }
    for (external_uploads, frame.uploads.len..) |value, index| {
        uploads[index] = .{
            .resource = try surfaceResource(value.external.resource),
            .kind = .rgba,
            .width = value.external.size.width,
            .height = value.external.size.height,
            .stride = value.external.stride,
            .pixels = value.fetched.pixels,
        };
    }
    for (frame.removals, 0..) |value, index| removals[index] = .{
        .resource = try surfaceResource(value),
    };
    for (frame.commands, 0..) |value, index| commands[index] = switch (value) {
        .solid => |solid| .{ .solid = .{
            .rect = surfaceRect(solid.rect),
            .clip = surfaceRect(solid.rect),
            .color = surfaceColor(solid.color),
        } },
        .alpha_mask => |mask| .{ .alpha_mask = .{
            .rect = surfaceRect(mask.destination),
            .clip = surfaceRect(mask.clip),
            .resource = try surfaceResource(mask.resource.resource),
            .source = if (mask.resource.source) |source| .{
                .x = source.x,
                .y = source.y,
                .width = source.width,
                .height = source.height,
            } else null,
            .color = surfaceColor(mask.color),
        } },
        .rgba => |rgba| .{ .rgba = .{
            .rect = surfaceRect(rgba.destination),
            .clip = surfaceRect(rgba.clip),
            .resource = try surfaceResource(rgba.resource.resource),
            .source = if (rgba.resource.source) |source| .{
                .x = source.x,
                .y = source.y,
                .width = source.width,
                .height = source.height,
            } else null,
        } },
    };
    return .{
        .revision = frame.revision,
        .uploads = uploads[0..upload_count],
        .removals = removals[0..frame.removals.len],
        .commands = commands[0..frame.commands.len],
    };
}

fn surfaceResource(value: canvas.ResourceRef) error{InvalidFrame}!vk_surface.ResourceGeneration {
    value.validate() catch return error.InvalidFrame;
    return vk_surface.ResourceGeneration.init(
        @backingInt(value.resource),
        @backingInt(value.generation),
    ) catch error.InvalidFrame;
}

fn canvasResource(value: vk_surface.ResourceGeneration) error{InvalidFrame}!canvas.ResourceRef {
    value.validate() catch return error.InvalidFrame;
    return .{
        .resource = canvas.ResourceId.fromEncoded(value.resource) catch
            return error.InvalidFrame,
        .generation = @fromBackingInt(value.generation),
    };
}

fn surfaceRect(value: canvas.Rect) vk_surface.Rect {
    return .{ .x = value.x, .y = value.y, .width = value.width, .height = value.height };
}

fn surfaceColor(value: canvas.Color) [4]f32 {
    return .{
        @as(f32, @floatFromInt(value.r)) / 255.0,
        @as(f32, @floatFromInt(value.g)) / 255.0,
        @as(f32, @floatFromInt(value.b)) / 255.0,
        @as(f32, @floatFromInt(value.a)) / 255.0,
    };
}

test "terminal scene prospective residency replaces one logical image identity" {
    var storage: [3]canvas.Residency = undefined;
    var count: usize = 0;
    const resource = try canvas.ResourceId.init(2);
    const first = canvas.Residency{
        .resource = .{ .resource = resource, .generation = @fromBackingInt(3) },
        .format = .rgba8,
        .size = .{ .width = 2, .height = 2 },
    };
    const replacement = canvas.Residency{
        .resource = .{ .resource = resource, .generation = @fromBackingInt(4) },
        .format = .rgba8,
        .size = .{ .width = 3, .height = 1 },
    };
    try upsertCanvasResidency(&storage, &count, first);
    try upsertCanvasResidency(&storage, &count, replacement);
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expectEqualDeep(replacement, storage[0]);

    const second = canvas.Residency{
        .resource = .{
            .resource = try canvas.ResourceId.init(3),
            .generation = @fromBackingInt(1),
        },
        .format = .rgba8,
        .size = .{ .width = 1, .height = 1 },
    };
    try upsertCanvasResidency(&storage, &count, second);
    try std.testing.expectEqual(@as(usize, 2), count);
}

test "terminal scene adapts exact fetched RGBA image into Vulkan upload" {
    const pixels = try std.testing.allocator.dupe(u8, &.{ 1, 2, 3, 4 });
    var fetched = client.images.Resource{
        .allocator = std.testing.allocator,
        .image_id = 7,
        .generation = 9,
        .width = 1,
        .height = 1,
        .pixels = pixels,
    };
    defer fetched.deinit();

    const resource = canvas.ResourceRef{
        .resource = try canvas.ResourceId.init(2),
        .generation = @fromBackingInt(9),
    };
    const external = ExternalUpload{
        .external = .{
            .resource = resource,
            .format = .rgba8,
            .size = .{ .width = 1, .height = 1 },
            .stride = 4,
        },
        .fetched = fetched,
    };
    const frame = terminal.Frame{
        .revision = 1,
        .uploads = &.{},
        .removals = &.{},
        .commands = &.{},
        .pixels = &.{},
    };
    var uploads: [1]vk_surface.Upload = undefined;
    var removals: [1]vk_surface.Removal = undefined;
    var commands: [1]vk_surface.FrameCommand = undefined;
    const adapted = try adaptCanvasFrame(
        frame,
        &.{external},
        &uploads,
        &removals,
        &commands,
    );
    try std.testing.expectEqual(@as(usize, 1), adapted.uploads.len);
    const upload = adapted.uploads[0];
    try std.testing.expectEqual(vk_surface.Kind.rgba, upload.kind);
    try std.testing.expectEqual(@as(u64, 2), upload.resource.resource);
    try std.testing.expectEqual(@as(u64, 9), upload.resource.generation);
    try std.testing.expectEqual(@as(u16, 1), upload.width);
    try std.testing.expectEqual(@as(u16, 1), upload.height);
    try std.testing.expectEqual(@as(usize, 4), upload.stride);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, upload.pixels);
}
