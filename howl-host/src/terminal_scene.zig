//! Bridges one canonical Session snapshot into the native Vulkan surface model.
//!
//! This owner is intentionally host-local. Session remains canonical terminal
//! truth, Render owns terminal/Canvas projection, and howl-vk owns backend
//! residency and geometry. This file only composes those existing contracts.

const std = @import("std");
const client = @import("howl_client");
const local_terminal = @import("local_terminal");
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
    width: u32,
    height: u32,
    pixels: []const u8,
    fetched: ?client.images.Resource = null,

    fn deinit(self: *ExternalUpload) void {
        if (self.fetched) |*owned| owned.deinit();
        self.* = undefined;
    }
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
    session_revision: u64,
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

pub fn measureCellSize(
    allocator: std.mem.Allocator,
    font: FontPaths,
    font_pixels: u16,
) !canvas.Size {
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
    const Remote = struct {
        connection: client.Connection,
        raw_cache: client.rich.RawCache,
    };

    const Source = union(enum) {
        remote: Remote,
        local: *local_terminal.Owner,
    };

    allocator: std.mem.Allocator,
    source: Source,
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
        font: FontPaths,
        font_pixels: u16,
    ) !Scene {
        if (font_pixels == 0) return error.InvalidFontPixels;
        var connection = try client.Connection.connect(allocator, endpoint);
        errdefer connection.deinit();
        var raw_cache = client.rich.RawCache.init(allocator);
        errdefer raw_cache.deinit();
        return initSource(
            allocator,
            .{ .remote = .{ .connection = connection, .raw_cache = raw_cache } },
            font,
            font_pixels,
        );
    }

    pub fn initLocal(
        allocator: std.mem.Allocator,
        owner: *local_terminal.Owner,
        font: FontPaths,
        font_pixels: u16,
    ) !Scene {
        if (font_pixels == 0) return error.InvalidFontPixels;
        return initSource(allocator, .{ .local = owner }, font, font_pixels);
    }

    fn initSource(
        allocator: std.mem.Allocator,
        source: Source,
        font: FontPaths,
        font_pixels: u16,
    ) !Scene {
        var owned_source = source;
        errdefer deinitSource(&owned_source);
        const fonts = try text.FontSet.init(allocator, .{
            .primary = font.primary,
            .fallbacks = font.fallbacks,
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
            .source = owned_source,
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
        deinitSource(&self.source);
        self.* = undefined;
    }

    fn deinitSource(owner_source: *Source) void {
        switch (owner_source.*) {
            .remote => |*remote_state| {
                remote_state.raw_cache.deinit();
                remote_state.connection.deinit();
            },
            .local => {},
        }
    }

    fn remoteSource(self: *Scene) !*Remote {
        if (self.source != .remote) return error.LocalScene;
        return &self.source.remote;
    }

    pub fn isLocal(self: *const Scene) bool {
        return switch (self.source) {
            .remote => false,
            .local => true,
        };
    }

    pub fn cancellation(self: *const Scene) error{ SocketDuplicateFailed, SocketOptionFailed }!client.Cancellation {
        return switch (self.source) {
            .remote => |source| source.connection.cancellation(),
            .local => unreachable,
        };
    }

    /// Replaces only the live observation stream after a host-local history
    /// excursion. Render/text/backend state remains resident; any old pending
    /// long-poll dies with the retired connection and cannot replay stale pixels.
    pub fn resetObserver(self: *Scene, endpoint: []const u8) !void {
        if (self.isLocal()) {
            self.observation_pending = false;
            return;
        }
        if (endpoint.len == 0) return error.InvalidEndpoint;
        var replacement = try client.Connection.connect(self.allocator, endpoint);
        errdefer replacement.deinit();
        const replacement_cache = client.rich.RawCache.init(self.allocator);

        const remote = try self.remoteSource();
        remote.connection.deinit();
        remote.raw_cache.deinit();
        remote.connection = replacement;
        remote.raw_cache = replacement_cache;
        self.observation_pending = false;
    }

    /// Arms one revision-relative delta observation without receiving it yet.
    pub fn arm(self: *Scene, after_revision: u64) !void {
        if (self.observation_pending) return error.ObservationPending;
        switch (self.source) {
            .remote => |*source| try source.raw_cache.sendDeltaRequest(
                &source.connection,
                after_revision,
                0,
            ),
            .local => |owner| owner.armObservation(after_revision),
        }
        self.observation_pending = true;
    }

    /// Borrows this Scene's socket only for readiness polling.
    pub fn readinessFd(self: *const Scene) std.posix.fd_t {
        return switch (self.source) {
            .remote => |source| source.connection.readinessFd(),
            .local => |owner| owner.observationFd(),
        };
    }

    /// Receives and projects exactly one previously armed delta/raw-fallback observation.
    pub fn receivePrepared(self: *Scene) !Prepared {
        if (!self.observation_pending) return error.ObservationNotPending;
        return switch (self.source) {
            .remote => |*source| blk: {
                const rich = try source.raw_cache.receive(&source.connection);
                self.observation_pending = false;
                break :blk try self.prepareRich(&rich, &source.connection);
            },
            .local => |owner| blk: {
                try owner.drainObservationWake();
                self.observation_pending = false;
                break :blk try self.prepareLocal(owner, 0);
            },
        };
    }

    /// Requests and projects one complete historical observation on a caller-owned
    /// control connection. Revision zero deliberately establishes a fresh baseline
    /// for the requested history offset without disturbing the live observer cache.
    pub fn prepareHistory(
        self: *Scene,
        connection: ?*client.Connection,
        history_offset: u32,
    ) !Prepared {
        switch (self.source) {
            .local => |owner| return self.prepareLocal(owner, history_offset),
            .remote => {},
        }
        const control = connection orelse return error.InvalidControl;
        var snapshot = try client.rich.requestRaw(
            control,
            self.allocator,
            0,
            history_offset,
        );
        defer snapshot.deinit();
        const rich = snapshot.view();
        return self.prepareRich(&rich, control);
    }

    fn prepareRich(
        self: *Scene,
        rich: *const client.rich.View,
        refill_connection: *client.Connection,
    ) !Prepared {
        const begin = rich.begin;
        const width = std.math.mul(u16, begin.columns, self.cell_size.width) catch
            return error.InvalidGeometry;
        const height = std.math.mul(u16, begin.rows, self.cell_size.height) catch
            return error.InvalidGeometry;
        if (width == 0 or height == 0) return error.InvalidGeometry;
        if (try self.fast.prepare(rich, width, height)) |fast| {
            var plan = empty_plan;
            var overlay_pending = false;
            if (fast.overlay_frame.commands.len != 0) {
                try self.overlay_residency.stage(fast.overlay_frame);
                errdefer self.overlay_residency.discard();
                plan = try self.builder.build(&self.overlay_residency, fast.overlay_frame);
                overlay_pending = true;
            }
            return preparedEnvelope(begin, width, height, .{ .fast = .{
                .terminal = fast,
                .plan = plan,
                .overlay_pending = overlay_pending,
            } });
        }

        const graphics = rich.graphics;
        var candidate_bindings: [terminal.maximum_external_images]terminal.ExternalImageBinding = undefined;
        const bindings = try terminal.planExternalImageBindings(
            self.image_bindings[0..self.image_binding_count],
            terminal.canvasUsage(self.canvas),
            graphics.images,
            &candidate_bindings,
        );
        try terminal.updateRichWithImageBindings(self.canvas, rich, bindings);
        @memcpy(self.image_bindings[0..bindings.len], bindings);
        self.image_binding_count = bindings.len;

        var canvas_residency_count = try self.acceptedCanvasResidencies();
        var external_uploads: [terminal.maximum_external_images]ExternalUpload = undefined;
        var external_upload_count: usize = 0;
        defer clearExternalUploads(&external_uploads, &external_upload_count);
        try self.prepareRemoteExternalUploads(
            refill_connection,
            bindings,
            &canvas_residency_count,
            &external_uploads,
            &external_upload_count,
        );
        const generic = try self.finishGeneric(
            canvas_residency_count,
            external_uploads[0..external_upload_count],
        );
        return preparedEnvelope(begin, width, height, .{ .generic = generic });
    }

    fn prepareLocal(
        self: *Scene,
        owner: *local_terminal.Owner,
        history_offset: u32,
    ) !Prepared {
        var guard = owner.observe();
        defer guard.deinit();
        const observation = guard.value;
        const view = observation.semanticView(history_offset);
        const width = std.math.mul(u16, view.cols, self.cell_size.width) catch
            return error.InvalidGeometry;
        const height = std.math.mul(u16, view.rows, self.cell_size.height) catch
            return error.InvalidGeometry;
        if (width == 0 or height == 0) return error.InvalidGeometry;

        var candidate_bindings: [terminal.maximum_external_images]terminal.ExternalImageBinding = undefined;
        const bindings = try terminal.planObservationImageBindings(
            self.image_bindings[0..self.image_binding_count],
            terminal.canvasUsage(self.canvas),
            observation,
            history_offset,
            &candidate_bindings,
        );
        try terminal.updateObservation(
            self.canvas,
            observation,
            history_offset,
            bindings,
        );
        @memcpy(self.image_bindings[0..bindings.len], bindings);
        self.image_binding_count = bindings.len;

        var canvas_residency_count = try self.acceptedCanvasResidencies();
        var external_uploads: [terminal.maximum_external_images]ExternalUpload = undefined;
        var external_upload_count: usize = 0;
        try self.prepareLocalExternalUploads(
            observation,
            history_offset,
            bindings,
            &canvas_residency_count,
            &external_uploads,
            &external_upload_count,
        );
        const generic = try self.finishGeneric(
            canvas_residency_count,
            external_uploads[0..external_upload_count],
        );
        return .{
            .rows = view.rows,
            .cols = view.cols,
            .width = width,
            .height = height,
            .session_revision = observation.semanticSequence(),
            .history_offset = view.history_offset,
            .history_count = view.history_count,
            .history_row_base = view.history_row_base,
            .alternate_screen = view.is_alternate_screen,
            .leader_present = false,
            .you_are_leader = true,
            .mode = .{ .generic = generic },
        };
    }

    fn acceptedCanvasResidencies(self: *Scene) !usize {
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
        return resident.len;
    }

    fn finishGeneric(
        self: *Scene,
        canvas_residency_count: usize,
        external_uploads: []const ExternalUpload,
    ) !GenericPrepared {
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

    fn prepareRemoteExternalUploads(
        self: *Scene,
        refill_connection: *client.Connection,
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
                refill_connection,
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

            uploads[upload_count.*] = .{
                .external = external,
                .width = fetched.width,
                .height = fetched.height,
                .pixels = fetched.pixels,
                .fetched = fetched,
            };
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

    fn prepareLocalExternalUploads(
        self: *Scene,
        observation: *const @import("howl_vt").Terminal.Observation,
        history_offset: u32,
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

fn preparedEnvelope(
    begin: @import("howl_session").protocol.SnapshotBegin,
    width: u16,
    height: u16,
    mode: @FieldType(Prepared, "mode"),
) Prepared {
    return .{
        .rows = begin.rows,
        .cols = begin.columns,
        .width = width,
        .height = height,
        .session_revision = begin.revision,
        .history_offset = begin.history_offset,
        .history_count = begin.history_count,
        .history_row_base = begin.history_row_base,
        .alternate_screen = begin.alternate_screen,
        .leader_present = begin.leader_present,
        .you_are_leader = begin.you_are_leader,
        .mode = mode,
    };
}

fn clearExternalUploads(
    uploads: *[terminal.maximum_external_images]ExternalUpload,
    count: *usize,
) void {
    while (count.* != 0) {
        count.* -= 1;
        uploads[count.*].deinit();
    }
}

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
        .width = fetched.width,
        .height = fetched.height,
        .pixels = fetched.pixels,
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

test "terminal scene projects one local Session image without client transport" {
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
    var scene = try Scene.initLocal(
        std.testing.allocator,
        &owner,
        .{
            .primary = @import("test_fonts").primary_font,
            .fallbacks = &fallbacks,
        },
        16,
    );
    defer scene.deinit();
    try std.testing.expectEqual(
        @as(?u8, 1),
        try scene.fonts.faceFor(&.{0xe0b0}),
    );
    const prepared = try scene.prepareHistory(null, 0);
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

test "local historical prepared frame cannot stale replay after output and reflow" {
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

    var attempts: u16 = 0;
    while (attempts < 4000) : (attempts += 1) {
        const state = owner.pollState();
        var descriptors = [_]std.posix.pollfd{.{
            .fd = state.descriptor,
            .events = std.posix.POLL.IN | std.posix.POLL.HUP |
                (if (state.write_pending) std.posix.POLL.OUT else 0),
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

    var scene = try Scene.initLocal(
        std.testing.allocator,
        &owner,
        .{ .primary = @import("test_fonts").primary_font },
        16,
    );
    defer scene.deinit();

    const stale_history = try scene.prepareHistory(null, 3);
    try std.testing.expectEqual(@as(u32, 3), stale_history.history_offset);
    try std.testing.expectEqual(@as(u16, 4), stale_history.rows);
    try std.testing.expectEqual(@as(u16, 8), stale_history.cols);
    const stale_revision = stale_history.session_revision;

    // Keep stale_history outstanding while canonical state advances.
    try owner.input(.{ .bytes = "go\n" });
    attempts = 0;
    while (attempts < 4000) : (attempts += 1) {
        const state = owner.pollState();
        var descriptors = [_]std.posix.pollfd{.{
            .fd = state.descriptor,
            .events = std.posix.POLL.IN | std.posix.POLL.HUP |
                (if (state.write_pending) std.posix.POLL.OUT else 0),
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

    const fresh_history = try scene.prepareHistory(null, 3);
    try std.testing.expect(fresh_history.session_revision >= current_revision);
    try std.testing.expect(fresh_history.session_revision > stale_revision);
    try std.testing.expectEqual(@as(u32, 3), fresh_history.history_offset);
    try std.testing.expectEqual(@as(u16, 6), fresh_history.rows);
    try std.testing.expectEqual(@as(u16, 10), fresh_history.cols);
    scene.discardPrepared(fresh_history);

    const live = try scene.prepareHistory(null, 0);
    defer scene.discardPrepared(live);
    try std.testing.expectEqual(@as(u32, 0), live.history_offset);
    try std.testing.expectEqual(@as(u16, 6), live.rows);
    try std.testing.expectEqual(@as(u16, 10), live.cols);
    try std.testing.expect(live.session_revision >= current_revision);
    try std.testing.expect(live.session_revision > stale_revision);
}
