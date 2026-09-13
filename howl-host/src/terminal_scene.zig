//! Bridges one canonical Session snapshot into the native Vulkan surface model.
//!
//! This owner is intentionally host-local. Session remains canonical terminal
//! truth, Render owns terminal/Canvas projection, and howl-vk owns backend
//! residency and geometry. This file only composes those existing contracts.

const std = @import("std");
const client = @import("howl_client");
const canvas = @import("canvas");
const presentation = @import("presentation");
const terminal = @import("terminal");
const terminal_fast = @import("terminal_fast.zig");
const text = @import("howl_text");
const vk_surface = @import("howl_vk").surface;

const resource_limit: usize = terminal.maximum_external_images + 1;
const overlay_resource_limit: usize = terminal_fast.overlay_resource_limit;
const atlas_extent: u16 = 512;
const atlas_pixel_bytes: usize = @as(usize, atlas_extent) * atlas_extent;
const command_capacity: usize = presentation.maximum_canvas_commands;
const surface_pixel_bytes: usize = 16 * 1024 * 1024;

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
    width: u16,
    height: u16,
    session_revision: u64,
    mode: union(enum) {
        generic: GenericPrepared,
        fast: FastPrepared,
    },
};

pub const Scene = struct {
    allocator: std.mem.Allocator,
    connection: client.Connection,
    fonts: *text.FontSet,
    fast: terminal_fast.Adapter,
    content: *terminal.Content,
    composer: canvas.Composer,
    source: canvas.SourceId,
    cell_size: canvas.Size,
    frame_uploads: []canvas.FrameResourceUpload,
    frame_removals: []canvas.FrameResourceRef,
    frame_commands: []canvas.Command,
    frame_pixels: []u8,
    surface_uploads: []vk_surface.Upload,
    surface_removals: []vk_surface.Removal,
    surface_commands: []vk_surface.FrameCommand,
    surface_residencies: []vk_surface.Residency,
    canvas_residencies: []canvas.Residency,
    builder: vk_surface.FrameBuilder,
    residency: vk_surface.ResidencyStore,
    overlay_residency: vk_surface.ResidencyStore,

    pub fn init(
        allocator: std.mem.Allocator,
        endpoint: []const u8,
        font_path: []const u8,
    ) !Scene {
        var connection = try client.Connection.connect(allocator, endpoint);
        errdefer connection.deinit();
        const fonts = try text.FontSet.init(allocator, .{
            .primary = font_path,
            .size = .{ .pixels = 16 },
        });
        errdefer fonts.deinit();
        const metrics = fonts.metrics();
        var fast = try terminal_fast.Adapter.init(allocator, fonts);
        errdefer fast.deinit();
        const cell_size = canvas.Size{
            .width = metrics.advance_width,
            .height = metrics.line_height,
        };
        const content = try terminal.initContent(
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
        errdefer terminal.deinitContent(content);
        var composer = try canvas.Composer.init(allocator, .{
            .sources = 1,
            .retained_resources = resource_limit,
            .retained_commands = command_capacity,
            .retained_pixel_bytes = atlas_pixel_bytes,
            .composition_sources = 1,
            .candidate_resources = resource_limit,
            .candidate_commands = command_capacity,
            .candidate_pixel_bytes = atlas_pixel_bytes,
        });
        errdefer composer.deinit();
        const source = try composer.registerSource();

        const frame_uploads = try allocator.alloc(canvas.FrameResourceUpload, resource_limit);
        errdefer allocator.free(frame_uploads);
        const frame_removals = try allocator.alloc(canvas.FrameResourceRef, resource_limit);
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
        const canvas_residencies = try allocator.alloc(canvas.Residency, resource_limit);
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
            .fonts = fonts,
            .fast = fast,
            .content = content,
            .composer = composer,
            .source = source,
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
        self.composer.deinit();
        terminal.deinitContent(self.content);
        self.fast.deinit();
        self.fonts.deinit();
        self.connection.deinit();
        self.* = undefined;
    }

    pub fn cancellation(self: *const Scene) error{ SocketDuplicateFailed, SocketOptionFailed }!client.Cancellation {
        return self.connection.cancellation();
    }

    pub fn prepare(self: *Scene, after_revision: u64) !Prepared {
        var rich = try client.rich.requestRaw(&self.connection, self.allocator, after_revision, 0);
        defer rich.deinit();
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
                .width = width,
                .height = height,
                .session_revision = begin.revision,
                .mode = .{ .fast = .{
                    .terminal = fast,
                    .plan = plan,
                    .overlay_pending = overlay_pending,
                } },
            };
        }

        const view = try client.view.project(self.allocator, &rich);
        defer client.view.deinit(view);
        if (client.view.graphics(view).images.len != 0)
            return error.GraphicsRefillNotImplemented;
        const placement = canvas.Composer.Placement{
            .source = self.source,
            .origin = .{ .x = 0, .y = 0 },
            .clip = .{ .x = 0, .y = 0, .width = width, .height = height },
        };
        try self.composer.setComposition(.{
            .surface = .{ .width = width, .height = height },
            .sources = &.{placement},
            .focused_source = self.source,
        });
        const update = try terminal.takeContentUpdate(
            self.content,
            view,
            .{
                .pane = 1,
                .source = self.source,
                .visible_set_revision = 1,
                .lifecycle_revision = 1,
            },
        );
        try self.composer.apply(self.source, update);

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
        const frame = try self.composer.frame(
            self.canvas_residencies[0..resident.len],
            .{
                .uploads = self.frame_uploads,
                .removals = self.frame_removals,
                .commands = self.frame_commands,
                .pixels = self.frame_pixels,
            },
        );
        const generic = try adaptCanvasFrame(
            frame,
            self.surface_uploads,
            self.surface_removals,
            self.surface_commands,
        );
        try self.residency.stage(generic);
        errdefer self.residency.discard();
        const plan = try self.builder.build(&self.residency, generic);
        return .{
            .width = width,
            .height = height,
            .session_revision = begin.revision,
            .mode = .{ .generic = .{ .plan = plan } },
        };
    }

    pub fn complete(self: *Scene) !void {
        try self.residency.complete();
    }
};

fn adaptCanvasFrame(
    frame: canvas.Composer.Frame,
    uploads: []vk_surface.Upload,
    removals: []vk_surface.Removal,
    commands: []vk_surface.FrameCommand,
) !vk_surface.Frame {
    if (frame.uploads.len > uploads.len or
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
        .revision = @backingInt(frame.revision),
        .uploads = uploads[0..frame.uploads.len],
        .removals = removals[0..frame.removals.len],
        .commands = commands[0..frame.commands.len],
    };
}

fn surfaceResource(value: canvas.FrameResourceRef) error{InvalidFrame}!vk_surface.ResourceGeneration {
    return vk_surface.ResourceGeneration.init(
        @backingInt(value.source),
        @backingInt(value.resource),
        @backingInt(value.generation),
    ) catch error.InvalidFrame;
}

fn canvasResource(value: vk_surface.ResourceGeneration) error{InvalidFrame}!canvas.FrameResourceRef {
    const resource = canvas.ResourceId.fromEncoded(value.resource) catch
        return error.InvalidFrame;
    return canvas.FrameResourceRef.init(
        @fromBackingInt(@intCast(value.source)),
        resource,
        @fromBackingInt(@intCast(value.generation)),
    ) catch error.InvalidFrame;
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
