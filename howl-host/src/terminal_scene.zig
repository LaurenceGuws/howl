//! Bridges one canonical Instance snapshot into the native Vulkan surface model.
//!
//! This owner is intentionally host-local. Instance remains canonical terminal
//! truth, Render owns terminal-frame projection, and howl-vk owns backend
//! residency and geometry. This file only composes those existing contracts.

const std = @import("std");
const local_terminal = @import("local_terminal");
const render = @import("howl_render");
const limits = render.limits;
const terminal = render.terminal;
const terminal_fast = @import("terminal_fast.zig");
const text = render.text;
const vk_surface = @import("howl_vk").surface;

const resource_limit: usize = terminal.maximum_external_images + 1;
const prospective_resource_limit: usize = resource_limit + terminal.maximum_external_images;
const overlay_resource_limit: usize = terminal_fast.overlay_resource_limit;
const atlas_extent: u16 = 512;
const atlas_pixel_bytes: usize = @as(usize, atlas_extent) * atlas_extent;
const command_capacity: usize = limits.maximum_frame_commands;
const surface_pixel_bytes: usize = 16 * 1024 * 1024;

const ExternalUpload = struct {
    external: terminal.FrameExternalResource,
    width: u32,
    height: u32,
    pixels: []const u8,
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

/// One explicit primary font plus ordered missing-cluster fallbacks.
pub const FontPaths = struct {
    primary: []const u8,
    fallbacks: []const []const u8 = &.{},
};

pub const Prepared = struct {
    rows: u16,
    cols: u16,
    width: u16,
    height: u16,
    /// Canonical VT cell-pixel lattice observed from the Instance.
    cell_pixel_width: u32,
    cell_pixel_height: u32,
    instance_revision: u64,
    history_offset: u32,
    history_count: u32,
    history_row_base: u32,
    alternate_screen: bool,
    leader_present: bool,
    you_are_leader: bool,
    mode: union(enum) {
        generic: GenericPrepared,
        fast: FastPrepared,
    },
};

/// Reports whether one prepared observation already owns the complete requested
/// canonical terminal geometry. Presentation width/height are deliberately not
/// used here: they are derived from this Scene's font metrics and may differ
/// from a stale Instance/PTy pixel lattice.
pub fn preparedMatchesGeometry(
    prepared: Prepared,
    rows: u16,
    cols: u16,
    cell_size: terminal.Size,
) bool {
    return prepared.rows == rows and
        prepared.cols == cols and
        prepared.cell_pixel_width == cell_size.width and
        prepared.cell_pixel_height == cell_size.height;
}

pub fn measureCellSize(
    allocator: std.mem.Allocator,
    font: FontPaths,
    font_pixels: u16,
) !terminal.Size {
    if (font_pixels == 0) return error.InvalidFontPixels;
    const fonts = try text.FontSet.init(allocator, .{
        .primary = font.primary,
        .fallbacks = font.fallbacks,
        .size = .{ .pixels = font_pixels },
    });
    defer fonts.deinit();
    const metrics = fonts.metrics();
    return .{ .width = metrics.advance_width, .height = metrics.line_height };
}

pub const Scene = struct {
    const Local = struct {
        owner: *local_terminal.Owner,
        // Borrowed from the Host Boundary; never drained or closed by Scene.
        stop_descriptor: i32,
        after_revision: u64 = 0,

        fn wait(self: Local) !void {
            var descriptors = [_]std.posix.pollfd{
                .{ .fd = self.owner.observationFd(), .events = std.posix.POLL.IN, .revents = 0 },
                .{ .fd = self.stop_descriptor, .events = std.posix.POLL.IN, .revents = 0 },
            };
            const ready = try std.posix.poll(&descriptors, -1);
            if (ready == 0) return error.ScenePoll;
            if (descriptors[1].revents != 0) return error.Stopping;
            if (descriptors[0].revents & (std.posix.POLL.ERR | std.posix.POLL.HUP | std.posix.POLL.NVAL) != 0)
                return error.ScenePoll;
        }
    };

    allocator: std.mem.Allocator,
    source: Local,
    fonts: *text.FontSet,
    fast: terminal_fast.Adapter,
    renderer: *terminal.Renderer,
    cell_size: terminal.Size,
    frame_uploads: []terminal.FrameResourceUpload,
    frame_removals: []terminal.ResourceRef,
    frame_commands: []terminal.Command,
    frame_pixels: []u8,
    surface_uploads: []vk_surface.Upload,
    surface_removals: []vk_surface.Removal,
    surface_commands: []vk_surface.FrameCommand,
    surface_residencies: []vk_surface.Residency,
    renderer_residencies: []terminal.Residency,
    image_bindings: [terminal.maximum_external_images]terminal.ExternalImageBinding = undefined,
    image_binding_count: usize = 0,
    builder: vk_surface.FrameBuilder,
    residency: vk_surface.ResidencyStore,
    overlay_residency: vk_surface.ResidencyStore,
    observation_pending: bool = false,
    local_fast_generations: [limits.maximum_rows]u64 = @splat(0),
    local_fast_rows: [limits.maximum_rows]bool = @splat(false),
    local_fast_rows_count: u16 = 0,
    local_fast_cols_count: u16 = 0,
    local_fast_alternate: bool = false,
    local_fast_cache_valid: bool = false,

    pub fn init(
        allocator: std.mem.Allocator,
        owner: *local_terminal.Owner,
        font: FontPaths,
        font_pixels: u16,
        stop_descriptor: i32,
    ) !Scene {
        if (font_pixels == 0) return error.InvalidFontPixels;
        if (stop_descriptor < 0) return error.InvalidStopDescriptor;
        return initSource(allocator, .{
            .owner = owner,
            .stop_descriptor = stop_descriptor,
        }, font, font_pixels);
    }

    fn initSource(
        allocator: std.mem.Allocator,
        source: Local,
        font: FontPaths,
        font_pixels: u16,
    ) !Scene {
        const fonts = try text.FontSet.init(allocator, .{
            .primary = font.primary,
            .fallbacks = font.fallbacks,
            .size = .{ .pixels = font_pixels },
        });
        errdefer fonts.deinit();
        const metrics = fonts.metrics();
        var fast = try terminal_fast.Adapter.init(allocator, fonts);
        errdefer fast.deinit();
        const cell_size = terminal.Size{
            .width = metrics.advance_width,
            .height = metrics.line_height,
        };
        const terminal_renderer = try terminal.init(
            allocator,
            terminal.FontFaces.single(fonts),
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
        errdefer terminal.deinit(terminal_renderer);

        const frame_uploads = try allocator.alloc(terminal.FrameResourceUpload, resource_limit);
        errdefer allocator.free(frame_uploads);
        const frame_removals = try allocator.alloc(terminal.ResourceRef, resource_limit);
        errdefer allocator.free(frame_removals);
        const frame_commands = try allocator.alloc(terminal.Command, command_capacity);
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
        const renderer_residencies = try allocator.alloc(terminal.Residency, prospective_resource_limit);
        errdefer allocator.free(renderer_residencies);
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
            .source = source,
            .fonts = fonts,
            .fast = fast,
            .renderer = terminal_renderer,
            .cell_size = cell_size,
            .frame_uploads = frame_uploads,
            .frame_removals = frame_removals,
            .frame_commands = frame_commands,
            .frame_pixels = frame_pixels,
            .surface_uploads = surface_uploads,
            .surface_removals = surface_removals,
            .surface_commands = surface_commands,
            .surface_residencies = surface_residencies,
            .renderer_residencies = renderer_residencies,
            .builder = builder,
            .residency = residency,
            .overlay_residency = overlay_residency,
        };
    }

    pub fn deinit(self: *Scene) void {
        self.overlay_residency.deinit();
        self.residency.deinit();
        self.builder.deinit();
        self.allocator.free(self.renderer_residencies);
        self.allocator.free(self.surface_residencies);
        self.allocator.free(self.surface_commands);
        self.allocator.free(self.surface_removals);
        self.allocator.free(self.surface_uploads);
        self.allocator.free(self.frame_pixels);
        self.allocator.free(self.frame_commands);
        self.allocator.free(self.frame_removals);
        self.allocator.free(self.frame_uploads);
        terminal.deinit(self.renderer);
        self.fast.deinit();
        self.fonts.deinit();
        self.* = undefined;
    }

    /// Drops only an outstanding presentation request. Canonical Instance state
    /// and accepted renderer/backend residency remain untouched.
    pub fn resetObserver(self: *Scene) void {
        self.observation_pending = false;
    }

    /// Arms one revision-relative direct observation.
    pub fn arm(self: *Scene, after_revision: u64) !void {
        if (self.observation_pending) return error.ObservationPending;
        self.source.after_revision = after_revision;
        self.source.owner.armObservation(after_revision);
        self.observation_pending = true;
    }

    pub fn readinessFd(self: *const Scene) std.posix.fd_t {
        return self.source.owner.observationFd();
    }

    pub fn receivePrepared(self: *Scene) !Prepared {
        while (true) {
            if (try self.tryReceivePrepared()) |prepared| return prepared;
            try self.source.wait();
        }
    }

    /// Stale or synchronized-held wakes return null without consuming the request.
    pub fn tryReceivePrepared(self: *Scene) !?Prepared {
        if (!self.observation_pending) return error.ObservationNotPending;
        var guard = try self.source.owner.observePublished(self.source.after_revision) orelse return null;
        defer guard.deinit();
        self.observation_pending = false;
        return try self.prepareLocal(guard.value, 0);
    }

    /// Projects one complete historical observation directly from the Instance.
    pub fn prepareHistory(self: *Scene, history_offset: u32) !Prepared {
        while (true) {
            if (try self.source.owner.observePublished(null)) |borrowed| {
                var guard = borrowed;
                defer guard.deinit();
                return self.prepareLocal(guard.value, history_offset);
            }
            try self.source.wait();
        }
    }

    fn prepareLocal(
        self: *Scene,
        observation: *const @import("howl_vt").Terminal.Observation,
        history_offset: u32,
    ) !Prepared {
        const cell_pixels = observation.cellPixelSize() orelse
            return error.InvalidGeometry;
        const view = observation.semanticView(history_offset);
        const width = std.math.mul(u16, view.cols, self.cell_size.width) catch
            return error.InvalidGeometry;
        const height = std.math.mul(u16, view.rows, self.cell_size.height) catch
            return error.InvalidGeometry;
        if (width == 0 or height == 0) return error.InvalidGeometry;

        if (history_offset == 0 and view.rows <= self.local_fast_rows.len) {
            const changed_rows = self.local_fast_rows[0..view.rows];
            const comparable = self.local_fast_cache_valid and
                self.local_fast_rows_count == view.rows and
                self.local_fast_cols_count == view.cols and
                self.local_fast_alternate == view.is_alternate_screen;
            var provenance_complete = true;
            for (changed_rows, 0..) |*changed, row_index| {
                const generation = view.rowGeneration(@intCast(row_index)) orelse {
                    provenance_complete = false;
                    changed.* = true;
                    continue;
                };
                changed.* = !comparable or generation != self.local_fast_generations[row_index];
            }
            if (provenance_complete) {
                if (try self.fast.prepareObservation(observation, changed_rows, width, height)) |fast| {
                    for (0..view.rows) |row_index|
                        self.local_fast_generations[row_index] =
                            view.rowGeneration(@intCast(row_index)).?;
                    self.local_fast_rows_count = view.rows;
                    self.local_fast_cols_count = view.cols;
                    self.local_fast_alternate = view.is_alternate_screen;
                    self.local_fast_cache_valid = true;
                    return .{
                        .rows = view.rows,
                        .cols = view.cols,
                        .width = width,
                        .height = height,
                        .cell_pixel_width = cell_pixels.width,
                        .cell_pixel_height = cell_pixels.height,
                        .instance_revision = observation.semanticSequence(),
                        .history_offset = view.history_offset,
                        .history_count = view.history_count,
                        .history_row_base = view.history_row_base,
                        .alternate_screen = view.is_alternate_screen,
                        .leader_present = false,
                        .you_are_leader = true,
                        .mode = .{ .fast = .{
                            .terminal = fast,
                            .plan = empty_plan,
                            .overlay_pending = false,
                        } },
                    };
                }
            }
            self.local_fast_cache_valid = false;
        } else {
            self.local_fast_cache_valid = false;
        }

        var candidate_bindings: [terminal.maximum_external_images]terminal.ExternalImageBinding = undefined;
        const bindings = try terminal.planObservationImageBindings(
            self.image_bindings[0..self.image_binding_count],
            terminal.usage(self.renderer),
            observation,
            history_offset,
            &candidate_bindings,
        );
        try terminal.updateObservation(
            self.renderer,
            observation,
            history_offset,
            bindings,
        );
        @memcpy(self.image_bindings[0..bindings.len], bindings);
        self.image_binding_count = bindings.len;

        var renderer_residency_count = try self.acceptedRendererResidencies();
        var external_uploads: [terminal.maximum_external_images]ExternalUpload = undefined;
        var external_upload_count: usize = 0;
        try self.prepareLocalExternalUploads(
            observation,
            history_offset,
            bindings,
            &renderer_residency_count,
            &external_uploads,
            &external_upload_count,
        );
        const generic = try self.finishGeneric(
            renderer_residency_count,
            external_uploads[0..external_upload_count],
        );
        return .{
            .rows = view.rows,
            .cols = view.cols,
            .width = width,
            .height = height,
            .cell_pixel_width = cell_pixels.width,
            .cell_pixel_height = cell_pixels.height,
            .instance_revision = observation.semanticSequence(),
            .history_offset = view.history_offset,
            .history_count = view.history_count,
            .history_row_base = view.history_row_base,
            .alternate_screen = view.is_alternate_screen,
            .leader_present = false,
            .you_are_leader = true,
            .mode = .{ .generic = generic },
        };
    }

    fn acceptedRendererResidencies(self: *Scene) !usize {
        const resident = try self.residency.enumerate(self.surface_residencies);
        if (resident.len > self.renderer_residencies.len) return error.Capacity;
        for (resident, 0..) |value, index| {
            self.renderer_residencies[index] = .{
                .resource = try renderResource(value.resource),
                .format = switch (value.kind) {
                    .alpha_mask => .alpha8,
                    .rgba => .rgba8,
                    .solid => return error.InvalidFrame,
                },
                .size = .{ .width = value.width, .height = value.height },
            };
        }
        return resident.len;
    }

    fn finishGeneric(
        self: *Scene,
        renderer_residency_count: usize,
        external_uploads: []const ExternalUpload,
    ) !GenericPrepared {
        const frame = try terminal.frame(
            self.renderer,
            self.renderer_residencies[0..renderer_residency_count],
            .{
                .uploads = self.frame_uploads,
                .removals = self.frame_removals,
                .commands = self.frame_commands,
                .pixels = self.frame_pixels,
            },
        );
        const generic = try adaptRendererFrame(
            frame,
            external_uploads,
            self.surface_uploads,
            self.surface_removals,
            self.surface_commands,
        );
        try self.residency.stage(generic);
        errdefer self.residency.discard();
        const plan = try self.builder.build(&self.residency, generic);
        return .{ .plan = plan };
    }

    fn prepareLocalExternalUploads(
        self: *Scene,
        observation: *const @import("howl_vt").Terminal.Observation,
        history_offset: u32,
        bindings: []const terminal.ExternalImageBinding,
        renderer_residency_count: *usize,
        uploads: *[terminal.maximum_external_images]ExternalUpload,
        upload_count: *usize,
    ) !void {
        var missing_storage: [terminal.maximum_external_images]terminal.FrameExternalResource = undefined;
        const missing = try terminal.missingExternalResources(
            self.renderer,
            self.renderer_residencies[0..renderer_residency_count.*],
            &missing_storage,
        );
        if (missing.len > uploads.len) return error.Capacity;
        const graphics = observation.images(history_offset);

        for (missing) |external| {
            if (external.format != .rgba8) return error.InvalidFrame;
            const binding = findImageBindingByResource(bindings, external.resource) orelse
                return error.InvalidFrame;
            const image = findObservationImage(
                &graphics,
                binding.image_id,
                binding.generation,
            ) orelse return error.InvalidFrame;
            const stride = std.math.mul(usize, @as(usize, external.size.width), 4) catch
                return error.ArithmeticOverflow;
            const pixel_count = std.math.mul(usize, stride, external.size.height) catch
                return error.ArithmeticOverflow;
            if (external.stride != stride or
                image.width != external.size.width or
                image.height != external.size.height or
                image.pixels.len != pixel_count)
                return error.InvalidFrame;
            uploads[upload_count.*] = .{
                .external = external,
                .width = image.width,
                .height = image.height,
                .pixels = image.pixels,
            };
            upload_count.* += 1;
            try upsertRendererResidency(
                self.renderer_residencies,
                renderer_residency_count,
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

    pub fn cellSize(self: *const Scene) terminal.Size {
        return self.cell_size;
    }

    /// Arms and receives one raw observation synchronously.
    pub fn prepare(self: *Scene, after_revision: u64) !Prepared {
        try self.arm(after_revision);
        return self.receivePrepared();
    }

    pub fn complete(self: *Scene) !void {
        if (self.residency.pending) try self.residency.complete();
        if (self.overlay_residency.pending) try self.overlay_residency.complete();
    }
};

fn findObservationImage(
    graphics: *const @import("howl_vt").Terminal.Images,
    image_id: u32,
    generation: u64,
) ?@import("howl_vt").Terminal.Image {
    var index: usize = 0;
    while (index < graphics.imageCount()) : (index += 1) {
        const image = graphics.image(index) orelse continue;
        if (image.id == image_id and image.generation == generation) return image;
    }
    return null;
}

fn findImageBindingByResource(
    bindings: []const terminal.ExternalImageBinding,
    resource: terminal.ResourceRef,
) ?terminal.ExternalImageBinding {
    for (bindings) |binding| {
        if (std.meta.eql(binding.resource, resource)) return binding;
    }
    return null;
}

fn upsertRendererResidency(
    storage: []terminal.Residency,
    count: *usize,
    value: terminal.Residency,
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

fn adaptRendererFrame(
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
            .width = @intCast(value.width),
            .height = @intCast(value.height),
            .stride = value.external.stride,
            .pixels = value.pixels,
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

fn surfaceResource(value: terminal.ResourceRef) error{InvalidFrame}!vk_surface.ResourceGeneration {
    value.validate() catch return error.InvalidFrame;
    return vk_surface.ResourceGeneration.init(
        @backingInt(value.resource),
        @backingInt(value.generation),
    ) catch error.InvalidFrame;
}

fn renderResource(value: vk_surface.ResourceGeneration) error{InvalidFrame}!terminal.ResourceRef {
    value.validate() catch return error.InvalidFrame;
    return .{
        .resource = terminal.ResourceId.fromEncoded(value.resource) catch
            return error.InvalidFrame,
        .generation = @fromBackingInt(value.generation),
    };
}

fn surfaceRect(value: terminal.Rect) vk_surface.Rect {
    return .{ .x = value.x, .y = value.y, .width = value.width, .height = value.height };
}

fn surfaceColor(value: terminal.Color) [4]f32 {
    return .{
        @as(f32, @floatFromInt(value.r)) / 255.0,
        @as(f32, @floatFromInt(value.g)) / 255.0,
        @as(f32, @floatFromInt(value.b)) / 255.0,
        @as(f32, @floatFromInt(value.a)) / 255.0,
    };
}

test "terminal scene prospective residency replaces one logical image identity" {
    var storage: [3]terminal.Residency = undefined;
    var count: usize = 0;
    const resource = try terminal.ResourceId.init(2);
    const first = terminal.Residency{
        .resource = .{ .resource = resource, .generation = @fromBackingInt(3) },
        .format = .rgba8,
        .size = .{ .width = 2, .height = 2 },
    };
    const replacement = terminal.Residency{
        .resource = .{ .resource = resource, .generation = @fromBackingInt(4) },
        .format = .rgba8,
        .size = .{ .width = 3, .height = 1 },
    };
    try upsertRendererResidency(&storage, &count, first);
    try upsertRendererResidency(&storage, &count, replacement);
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expectEqualDeep(replacement, storage[0]);

    const second = terminal.Residency{
        .resource = .{
            .resource = try terminal.ResourceId.init(3),
            .generation = @fromBackingInt(1),
        },
        .format = .rgba8,
        .size = .{ .width = 1, .height = 1 },
    };
    try upsertRendererResidency(&storage, &count, second);
    try std.testing.expectEqual(@as(usize, 2), count);
}

test "terminal scene adapts exact RGBA image into Vulkan upload" {
    const pixels = [_]u8{ 1, 2, 3, 4 };

    const resource = terminal.ResourceRef{
        .resource = try terminal.ResourceId.init(2),
        .generation = @fromBackingInt(9),
    };
    const external = ExternalUpload{
        .external = .{
            .resource = resource,
            .format = .rgba8,
            .size = .{ .width = 1, .height = 1 },
            .stride = 4,
        },
        .width = 1,
        .height = 1,
        .pixels = &pixels,
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
    const adapted = try adaptRendererFrame(
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

test "terminal scene projects one local Instance image without client transport" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    var owner = try local_terminal.Owner.init(
        std.testing.allocator,
        threaded.io(),
        std.testing.environ,
        .{
            .shell = "/bin/sh",
            .command = "printf 'A\\033_Ga=T,f=32,s=1,v=1,i=7;/////w==\\033\\\\'; sleep 30",
            .rows = 2,
            .columns = 4,
            .history_rows = 8,
        },
    );
    defer owner.deinit();
    var stop = try TestStop.init();
    defer stop.deinit();

    var ready = false;
    var attempts: u16 = 0;
    while (attempts < 2000) : (attempts += 1) {
        const state = owner.pollState();
        var descriptors = [_]std.posix.pollfd{.{
            .fd = state.descriptor,
            .events = std.posix.POLL.IN | std.posix.POLL.HUP,
            .revents = 0,
        }};
        const count = try std.posix.poll(&descriptors, 1);
        const serviced = try owner.service(
            count != 0 and descriptors[0].revents & (std.posix.POLL.IN | std.posix.POLL.HUP) != 0,
            false,
            try local_terminal.monotonicNs(),
        );
        try std.testing.expectEqual(serviced.write_pending, owner.pollState().write_pending);
        var guard = owner.observe();
        const view = guard.value.semanticView(0);
        const images = guard.value.images(0);
        ready = view.cellAt(0, 0) == 'A' and images.imageCount() != 0;
        guard.deinit();
        if (ready) break;
    }
    try std.testing.expect(ready);

    const fallbacks = [_][]const u8{@import("test_fonts").symbol_font};
    var scene = try Scene.init(
        std.testing.allocator,
        &owner,
        .{
            .primary = @import("test_fonts").primary_font,
            .fallbacks = &fallbacks,
        },
        16,
        stop.descriptor,
    );
    defer scene.deinit();
    try std.testing.expectEqual(
        @as(?u8, 1),
        try scene.fonts.faceFor(&.{0xe0b0}),
    );
    const prepared = try scene.prepareHistory(0);
    defer scene.discardPrepared(prepared);
    try std.testing.expect(prepared.mode == .generic);
    try std.testing.expectEqual(@as(usize, 1), scene.image_binding_count);

    const image_start = (@as(usize, vk_surface.image_atlas_extent) + 1) * 4;
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0xff, 0xff, 0xff, 0xff },
        scene.builder.rgba_pixels[image_start .. image_start + 4],
    );
}

test "terminal scene local historical frame cannot stale replay after output and reflow" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    var owner = try local_terminal.Owner.init(
        std.testing.allocator,
        threaded.io(),
        std.testing.environ,
        .{
            .shell = "/bin/sh",
            .command = "stty -echo; " ++
                "i=1; while [ $i -le 14 ]; do printf 'BASE-%02d-abcdefghijklmnop\\n' $i; i=$((i+1)); done; " ++
                "printf '\\033]0;BASE-READY\\007'; " ++
                "read line; " ++
                "i=15; while [ $i -le 28 ]; do printf 'NEXT-%02d-qrstuvwxyz012345\\n' $i; i=$((i+1)); done; " ++
                "printf '\\033]0;NEXT-READY\\007'; cat",
            .rows = 4,
            .columns = 8,
            .history_rows = 64,
        },
    );
    defer owner.deinit();
    var stop = try TestStop.init();
    defer stop.deinit();

    var attempts: u16 = 0;
    while (attempts < 4000) : (attempts += 1) {
        const state = owner.pollState();
        var descriptors = [_]std.posix.pollfd{.{
            .fd = state.descriptor,
            .events = std.posix.POLL.IN | std.posix.POLL.HUP |
                @as(i16, if (state.write_pending) std.posix.POLL.OUT else 0),
            .revents = 0,
        }};
        const count = try std.posix.poll(&descriptors, 1);
        const events = if (count == 0) 0 else descriptors[0].revents;
        const serviced = try owner.service(
            events & (std.posix.POLL.IN | std.posix.POLL.HUP) != 0,
            state.write_pending or events & std.posix.POLL.OUT != 0,
            try local_terminal.monotonicNs(),
        );
        try std.testing.expectEqual(
            serviced.write_pending,
            owner.pollState().write_pending,
        );
        var guard = owner.observe();
        const ready = if (guard.value.title()) |title|
            std.mem.eql(u8, title, "BASE-READY")
        else
            false;
        guard.deinit();
        if (ready) break;
    } else return error.Timeout;

    var scene = try Scene.init(
        std.testing.allocator,
        &owner,
        .{ .primary = @import("test_fonts").primary_font },
        16,
        stop.descriptor,
    );
    defer scene.deinit();

    const stale_history = try scene.prepareHistory(3);
    try std.testing.expectEqual(@as(u32, 3), stale_history.history_offset);
    try std.testing.expectEqual(@as(u16, 4), stale_history.rows);
    try std.testing.expectEqual(@as(u16, 8), stale_history.cols);
    const stale_revision = stale_history.instance_revision;

    // Keep stale_history outstanding while canonical state advances.
    try owner.input(.{ .bytes = "go\n" });
    attempts = 0;
    while (attempts < 4000) : (attempts += 1) {
        const state = owner.pollState();
        var descriptors = [_]std.posix.pollfd{.{
            .fd = state.descriptor,
            .events = std.posix.POLL.IN | std.posix.POLL.HUP |
                @as(i16, if (state.write_pending) std.posix.POLL.OUT else 0),
            .revents = 0,
        }};
        const count = try std.posix.poll(&descriptors, 1);
        const events = if (count == 0) 0 else descriptors[0].revents;
        const serviced = try owner.service(
            events & (std.posix.POLL.IN | std.posix.POLL.HUP) != 0,
            state.write_pending or events & std.posix.POLL.OUT != 0,
            try local_terminal.monotonicNs(),
        );
        try std.testing.expectEqual(
            serviced.write_pending,
            owner.pollState().write_pending,
        );
        var guard = owner.observe();
        const ready = if (guard.value.title()) |title|
            std.mem.eql(u8, title, "NEXT-READY")
        else
            false;
        guard.deinit();
        if (ready) break;
    } else return error.Timeout;

    const cell = scene.cellSize();
    try owner.resizeGeometry(6, 10, cell.width, cell.height);

    const current_revision = current: {
        var guard = owner.observe();
        defer guard.deinit();
        break :current guard.value.semanticSequence();
    };
    try std.testing.expect(current_revision > stale_revision);

    scene.discardPrepared(stale_history);

    const fresh_history = try scene.prepareHistory(3);
    try std.testing.expect(fresh_history.instance_revision >= current_revision);
    try std.testing.expect(fresh_history.instance_revision > stale_revision);
    try std.testing.expectEqual(@as(u32, 3), fresh_history.history_offset);
    try std.testing.expectEqual(@as(u16, 6), fresh_history.rows);
    try std.testing.expectEqual(@as(u16, 10), fresh_history.cols);
    scene.discardPrepared(fresh_history);

    const live = try scene.prepareHistory(0);
    defer scene.discardPrepared(live);
    try std.testing.expectEqual(@as(u32, 0), live.history_offset);
    try std.testing.expectEqual(@as(u16, 6), live.rows);
    try std.testing.expectEqual(@as(u16, 10), live.cols);
    try std.testing.expect(live.instance_revision >= current_revision);
    try std.testing.expect(live.instance_revision > stale_revision);
}

test "terminal scene prepared geometry compares canonical cell pixels, not presentation extent" {
    const prepared = Prepared{
        .rows = 26,
        .cols = 72,
        .width = 1008,
        .height = 884,
        .cell_pixel_width = 10,
        .cell_pixel_height = 20,
        .instance_revision = 1,
        .history_offset = 0,
        .history_count = 0,
        .history_row_base = 0,
        .alternate_screen = false,
        .leader_present = false,
        .you_are_leader = true,
        .mode = .{ .generic = .{ .plan = empty_plan } },
    };

    try std.testing.expect(preparedMatchesGeometry(
        prepared,
        26,
        72,
        .{ .width = 10, .height = 20 },
    ));
    try std.testing.expect(!preparedMatchesGeometry(
        prepared,
        26,
        72,
        .{ .width = 14, .height = 34 },
    ));
    try std.testing.expect(!preparedMatchesGeometry(
        prepared,
        25,
        72,
        .{ .width = 10, .height = 20 },
    ));
}

// Handshakes select the interleaving; the bounded poll only awaits child output.
fn testLocalTitle(owner: *local_terminal.Owner, title: []const u8, now_ns: u64) !void {
    try testLocalTitleState(owner, title, now_ns, false);
}

fn testLocalTitleState(owner: *local_terminal.Owner, title: []const u8, now_ns: u64, leader_may_exit: bool) !void {
    for (0..2000) |_| {
        const state = owner.pollState();
        var descriptors = [_]std.posix.pollfd{.{
            .fd = state.descriptor,
            .events = std.posix.POLL.IN | std.posix.POLL.HUP |
                @as(i16, if (state.write_pending) std.posix.POLL.OUT else 0),
            .revents = 0,
        }};
        const ready = try std.posix.poll(&descriptors, 1);
        const events = if (ready == 0) 0 else descriptors[0].revents;
        const result = try owner.service(
            events & (std.posix.POLL.IN | std.posix.POLL.HUP) != 0,
            state.write_pending or events & std.posix.POLL.OUT != 0,
            now_ns,
        );
        try std.testing.expect(!result.stream_closed);
        if (!leader_may_exit) try std.testing.expect(result.child_exit == null);
        var guard = owner.observe();
        const matched = if (guard.value.title()) |value| std.mem.eql(u8, title, value) else false;
        guard.deinit();
        if (matched) return;
    }
    return error.Timeout;
}

fn testSceneReadable(scene: *const Scene, expected: bool) !void {
    var descriptors = [_]std.posix.pollfd{.{
        .fd = scene.readinessFd(),
        .events = std.posix.POLL.IN,
        .revents = 0,
    }};
    const ready = try std.posix.poll(&descriptors, 0);
    try std.testing.expectEqual(expected, ready != 0);
}

test "terminal scene stale publication wake cannot expose a newer held frame" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    var owner = try local_terminal.Owner.init(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf '0\\033]0;ZERO\\007'; read step; " ++
            "printf 'A\\033]0;A\\007'; read step; " ++
            "printf '\\033[?2026hB\\033]0;B\\007'; read step; " ++
            "printf '\\033[?2026l\\033]0;DONE\\007'; read step",
        .rows = 2,
        .columns = 8,
        .history_rows = 8,
    });
    defer owner.deinit();
    var stop = try TestStop.init();
    defer stop.deinit();
    try testLocalTitle(&owner, "ZERO", 10);
    var scene = try Scene.init(std.testing.allocator, &owner, .{ .primary = @import("test_fonts").primary_font }, 16, stop.descriptor);
    defer scene.deinit();
    const first = try scene.prepare(0);
    try scene.complete();
    try scene.arm(first.instance_revision);
    try testSceneReadable(&scene, false);

    try owner.input(.{ .bytes = "go\n" });
    try testLocalTitle(&owner, "A", 20);
    try testSceneReadable(&scene, true); // Keep this eligible wake outstanding.
    try owner.input(.{ .bytes = "go\n" });
    try testLocalTitle(&owner, "B", 30);
    const held_revision = held: {
        var guard = owner.observe();
        defer guard.deinit();
        try std.testing.expect(guard.value.synchronizedOutput());
        try std.testing.expectEqual(@as(u21, 'B'), guard.value.semanticView(0).cellAt(0, 2));
        break :held guard.value.semanticSequence();
    };
    try std.testing.expect(held_revision > first.instance_revision);
    try std.testing.expect((try scene.tryReceivePrepared()) == null);
    try std.testing.expect(scene.observation_pending);
    try std.testing.expect(!scene.residency.pending);
    try testSceneReadable(&scene, false);
    try std.testing.expect((try scene.tryReceivePrepared()) == null);
    owner.armObservation(held_revision);
    try testSceneReadable(&scene, false);

    try owner.input(.{ .bytes = "go\n" });
    try testLocalTitle(&owner, "DONE", 40);
    try testSceneReadable(&scene, true);
    const released = try scene.receivePrepared();
    try std.testing.expect(released.instance_revision > held_revision);
    try scene.complete();
    try scene.arm(released.instance_revision);
    try testSceneReadable(&scene, false);
}

const TestStop = struct {
    descriptor: i32,
    fn init() !TestStop {
        const linux = std.os.linux;
        const fd = linux.eventfd(0, linux.EFD.CLOEXEC | linux.EFD.NONBLOCK);
        if (linux.errno(fd) != .SUCCESS) return error.Descriptor;
        return .{ .descriptor = @intCast(fd) };
    }
    fn signal(self: *TestStop) !void {
        const value: u64 = 1;
        const bytes = std.mem.asBytes(&value);
        if (std.os.linux.write(self.descriptor, bytes.ptr, bytes.len) != bytes.len) return error.Signal;
    }
    fn deinit(self: *TestStop) void {
        std.debug.assert(std.os.linux.close(self.descriptor) == 0);
        self.* = undefined;
    }
};

test "terminal scene held startup geometry and history wait remain cancellable" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    var owner = try local_terminal.Owner.init(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf '\\033[?2026hA\\033]0;HELD\\007'; read step",
        .rows = 2,
        .columns = 8,
        .history_rows = 8,
    });
    defer owner.deinit();
    var stop = try TestStop.init();
    defer stop.deinit();
    try testLocalTitle(&owner, "HELD", 10);
    var scene = try Scene.init(std.testing.allocator, &owner, .{ .primary = @import("test_fonts").primary_font }, 16, stop.descriptor);
    defer scene.deinit();
    try scene.arm(0);
    try std.testing.expect((try scene.tryReceivePrepared()) == null);
    try std.testing.expect(!scene.residency.pending);
    const cell = scene.cellSize();
    try owner.resizeGeometry(3, 12, cell.width, cell.height);
    // Resize updates published geometry but cannot release the held screen.
    try std.testing.expect((try scene.tryReceivePrepared()) == null);
    try testSceneReadable(&scene, false);
    try std.testing.expect(!owner.interactionState().keyboard_action_mode);
    try stop.signal();
    try std.testing.expectError(error.Stopping, scene.receivePrepared());
    scene.resetObserver();
    try std.testing.expectError(error.Stopping, scene.prepare(0));
    try std.testing.expectError(error.Stopping, scene.prepareHistory(0));
    try std.testing.expectError(error.Stopping, scene.prepareHistory(1));
    try std.testing.expect(!scene.residency.pending);
}

test "terminal scene idle synchronized timeout progresses without a new byte" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    var owner = try local_terminal.Owner.init(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf '\\033[?2026hA\\033]0;HELD\\007'; read step",
        .rows = 2,
        .columns = 8,
        .history_rows = 8,
    });
    defer owner.deinit();
    var stop = try TestStop.init();
    defer stop.deinit();
    try testLocalTitle(&owner, "HELD", 10);
    var scene = try Scene.init(std.testing.allocator, &owner, .{ .primary = @import("test_fonts").primary_font }, 16, stop.descriptor);
    defer scene.deinit();
    try scene.arm(0);
    try std.testing.expect((try scene.tryReceivePrepared()) == null);
    try std.testing.expect(!(try owner.service(false, false, 9 + std.time.ns_per_s)).changed);
    try testSceneReadable(&scene, false);
    try std.testing.expect(!(try owner.service(false, false, 10 + std.time.ns_per_s)).changed);
    try testSceneReadable(&scene, true);
    const current = try scene.receivePrepared();
    try scene.complete();
    try scene.arm(current.instance_revision);
    try std.testing.expect(!(try owner.service(false, false, 11 + std.time.ns_per_s)).changed);
    try testSceneReadable(&scene, false);
}

test "terminal scene child exit releases held canonical state without an end" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    var owner = try local_terminal.Owner.init(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf '\\033[?2026hA\\033]0;HELD\\007'; read step; exit 0",
        .rows = 2,
        .columns = 8,
        .history_rows = 8,
    });
    defer owner.deinit();
    var stop = try TestStop.init();
    defer stop.deinit();
    try testLocalTitle(&owner, "HELD", 10);
    var scene = try Scene.init(std.testing.allocator, &owner, .{ .primary = @import("test_fonts").primary_font }, 16, stop.descriptor);
    defer scene.deinit();
    try scene.arm(0);
    try std.testing.expect((try scene.tryReceivePrepared()) == null);
    try owner.input(.{ .bytes = "exit\n" });
    for (0..2000) |_| {
        const state = owner.pollState();
        var descriptors = [_]std.posix.pollfd{.{
            .fd = state.descriptor,
            .events = std.posix.POLL.IN | std.posix.POLL.HUP |
                @as(i16, if (state.write_pending) std.posix.POLL.OUT else 0),
            .revents = 0,
        }};
        const ready = try std.posix.poll(&descriptors, 1);
        const events = if (ready == 0) 0 else descriptors[0].revents;
        const result = try owner.service(
            events & (std.posix.POLL.IN | std.posix.POLL.HUP) != 0,
            state.write_pending or events & std.posix.POLL.OUT != 0,
            20,
        );
        if (result.stream_closed or result.child_exit != null) break;
    } else return error.Timeout;
    const final = try scene.receivePrepared();
    try scene.complete();
    try scene.arm(final.instance_revision);
    // Lifecycle-only repeats do not synthesize later semantic revisions.
    try std.testing.expect((try scene.tryReceivePrepared()) == null);
}

test "terminal scene descendant frame stays held after the leader exits" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    var owner = try local_terminal.Owner.init(std.testing.allocator, threaded.io(), std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; trap '' HUP; exec 3<&0; " ++
            "(printf 'A\\033]0;BASE\\007'; read step; " ++
            "printf '\\033[?2026hB\\033]0;HELD\\007'; read step; " ++
            "printf '\\033[?2026l\\033]0;DONE\\007'; read step) <&3 & exit 0",
        .rows = 2,
        .columns = 8,
        .history_rows = 8,
    });
    defer owner.deinit();
    var stop = try TestStop.init();
    defer stop.deinit();
    try testLocalTitleState(&owner, "BASE", 10, true);
    for (0..2000) |_| {
        const result = try owner.service(false, false, 20);
        try std.testing.expect(!result.stream_closed);
        if (result.child_exit != null) break;
        // Await the real leader-exit occurrence, not a guessed wall-clock sleep.
        var descriptor = [_]std.posix.pollfd{.{
            .fd = owner.pollState().descriptor,
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};
        const ready = try std.posix.poll(&descriptor, 1);
        try std.testing.expect(ready <= descriptor.len);
    } else return error.Timeout;
    var scene = try Scene.init(std.testing.allocator, &owner, .{ .primary = @import("test_fonts").primary_font }, 16, stop.descriptor);
    defer scene.deinit();
    const first = try scene.prepare(0);
    try scene.complete();
    try scene.arm(first.instance_revision);
    try owner.input(.{ .bytes = "go\n" });
    try testLocalTitleState(&owner, "HELD", 30, true);
    const held = try scene.tryReceivePrepared();
    try std.testing.expectEqual(@as(?u64, null), if (held) |frame| frame.instance_revision else null);
    try std.testing.expect(!scene.residency.pending);
    try owner.input(.{ .bytes = "go\n" });
    try testLocalTitleState(&owner, "DONE", 40, true);
    const done = try scene.receivePrepared();
    try std.testing.expect(done.instance_revision > first.instance_revision);
    try scene.complete();
}
