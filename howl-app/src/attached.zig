const std = @import("std");
const posix = std.posix;
const instance = @import("howl_instance");
const client = @import("howl_client");
const server = @import("server_client");
const render = @import("howl_client_render");
const publication = instance.publication;
const selection = @import("selection.zig");
const desktop = @import("desktop.zig");

/// Explicit attachment identity; Server selection always names one exact incarnation.
pub const Target = union(enum) { direct: []const u8, server: server.Target };
/// Exact transported setup, observation and control failures.
pub const Error = client.Error || server.Error || client.actions.Error ||
    client.state.Error || client.consequences.Error || client.rich.Error || client.view.Error || client.images.Error || client.selection.Error || client.search.Error ||
    error{ InvalidTarget, ObserverWakeFailed };
/// Exact immutable transported projection failures.
pub const RenderError = render.Error || error{ PublicationBusy, InvalidPresentationGeometry };
/// Exact font/renderer and explicit geometry transaction failures.
pub const ConfigureError = instance.text.InitError || render.InitError || client.actions.Error ||
    error{ InvalidPresentationGeometry, PresentationGenerationOverflow };

fn endpoint(target: Target) []const u8 {
    return switch (target) {
        .direct => |value| value,
        .server => |value| value.endpoint,
    };
}
/// Validation precedes allocation and any network activity.
pub fn validate(target: Target) error{InvalidTarget}!void {
    const value = endpoint(target);
    if (value.len == 0 or value.len > 512 or std.mem.indexOfScalar(u8, value, 0) != null or
        !std.unicode.utf8ValidateSlice(value) or
        (!std.mem.startsWith(u8, value, "unix:") and !std.mem.startsWith(u8, value, "tcp://"))) return error.InvalidTarget;
    if (target == .server and (target.server.server_id == 0 or target.server.session_id == 0 or target.server.instance_id == 0)) return error.InvalidTarget;
}
fn connect(gpa: std.mem.Allocator, target: Target, interrupt: *client.Interrupt) Error!client.Connection {
    var diagnostic: client.ConnectDiagnostic = .{};
    return switch (target) {
        .direct => |value| client.Connection.connectCancelable(gpa, value, &diagnostic, interrupt),
        .server => |value| result: {
            const attached = try server.attach(gpa, value, &diagnostic, interrupt);
            break :result client.connectTransport(gpa, attached.stream, &diagnostic);
        },
    };
}

const Fonts = struct {
    values: [4]?*instance.text.FontSet = @splat(null),
    fn init(gpa: std.mem.Allocator, config: instance.FontFamilyConfig) instance.text.InitError!Fonts {
        var result: Fonts = .{};
        errdefer result.deinit();
        for ([_]?instance.FontConfig{ config.regular, config.italic, config.bold, config.bold_italic }, 0..) |value, i| {
            if (value) |source| result.values[i] = switch (source) {
                .path => |recipe| try instance.text.FontSet.init(gpa, recipe),
                .memory => |recipe| try instance.text.FontSet.initMemory(gpa, recipe),
            };
        }
        return result;
    }
    fn deinit(self: *Fonts) void {
        var i = self.values.len;
        while (i != 0) {
            i -= 1;
            if (self.values[i]) |font| font.deinit();
        }
    }
    fn faces(self: *const Fonts) render.FontFaces {
        return .{ .regular = self.values[0].?, .italic = self.values[1], .bold = self.values[2], .bold_italic = self.values[3] };
    }
    fn cell(self: *const Fonts) render.Size {
        const metrics = self.values[0].?.metrics();
        return .{ .width = metrics.advance_width, .height = metrics.line_height };
    }
};
const Presentation = struct {
    fonts: Fonts,
    renderer: *render.Renderer,
    atlas_bytes: usize,
    command_limit: usize,
    generation: u64 = 1,
    bindings: [render.maximum_external_images]render.ExternalImageBinding = undefined,
    binding_count: usize = 0,
    residency: [publication.maximum_residencies]render.Residency = undefined,
    residency_count: usize = 0,
    fn init(gpa: std.mem.Allocator, config: instance.PresentationConfig) ConfigureError!Presentation {
        var fonts = try Fonts.init(gpa, config.fonts);
        errdefer fonts.deinit();
        const renderer = try render.init(gpa, fonts.faces(), .{
            .cell_size = fonts.cell(),
            .box_drawing = config.box_drawing,
            .shape_cache = config.shape_cache,
            .atlas = config.atlas,
            .shaped_capacity = config.shaped_capacity,
            .raster_bytes = config.raster_bytes,
            .command_capacity = config.command_capacity,
            .command_limit = config.command_limit,
            .incremental_row_capacity = config.incremental_row_capacity,
            .incremental_command_capacity = config.incremental_command_capacity,
        });
        errdefer render.deinit(renderer);
        const atlas_bytes = std.math.mul(usize, config.atlas.width, config.atlas.height) catch return error.InvalidConfig;
        return .{ .fonts = fonts, .renderer = renderer, .atlas_bytes = atlas_bytes, .command_limit = if (config.command_limit == 0) config.command_capacity else config.command_limit };
    }
    fn deinit(self: *Presentation) void {
        render.deinit(self.renderer);
        self.fonts.deinit();
    }
};

const Image = struct {
    resource: client.images.Resource,
    references: std.atomic.Value(u32) = .init(1),
    allocator: std.mem.Allocator,
    fn retain(self: *Image) void {
        const old = self.references.fetchAdd(1, .monotonic);
        // Cache replacement and a mailbox transfer can briefly retain six references.
        std.debug.assert(old != 0 and old < 6);
    }
    fn release(self: *Image) void {
        if (self.references.fetchSub(1, .acq_rel) != 1) return;
        self.resource.deinit();
        self.allocator.destroy(self);
    }
};
/// One owned immutable cut and copied interaction facts.
pub const Observation = struct {
    view: *client.view.Snapshot,
    interaction: instance.Terminal.InteractionState,
    images: [render.maximum_external_images]?*Image = @splat(null),
    /// Retires the sole owned semantic view.
    pub fn deinit(self: *Observation) void {
        for (self.images) |image| if (image) |value| value.release();
        client.view.deinit(self.view);
    }
};

/// Private transported owner. Its observer owns only immutable client projections.
pub const Attached = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    target: Target,
    control_interrupt: *client.Interrupt,
    control: ?client.Connection = null,
    observer: ?std.Thread = null,
    mutex: std.Io.Mutex = .init,
    stopping: bool = false,
    observer_interrupt: ?*client.Interrupt = null,
    epoch: u64 = 0,
    offset: u32 = 0,
    mailbox: ?Observation = null,
    failure: ?Error = null,
    wake_fd: posix.fd_t,
    exchange: *publication.Exchange,
    producer: *publication.Producer,
    presentation: Presentation,
    control_failure: ?Error = null,
    consequence_owned: bool = false,
    consequence_failure: ?client.consequences.Error = null,

    /// Owns route/fonts/exchange before asynchronous setup; no Instance is created.
    pub fn init(gpa: std.mem.Allocator, io: std.Io, target: Target, config: instance.PresentationConfig, wake_fd: posix.fd_t) !*Attached {
        try validate(target);
        const owned = try gpa.dupe(u8, endpoint(target));
        errdefer gpa.free(owned);
        var route = target;
        switch (route) {
            .direct => route.direct = owned,
            .server => route.server.endpoint = owned,
        }
        var presentation = try Presentation.init(gpa, config);
        errdefer presentation.deinit();
        const producer = try publication.init(gpa, config.command_capacity);
        const exchange = publication.consumer(producer);
        errdefer publication.deinit(producer);
        const interrupt = try client.Interrupt.init(gpa);
        errdefer interrupt.deinit();
        const self = try gpa.create(Attached);
        self.* = .{ .allocator = gpa, .io = io, .target = route, .control_interrupt = interrupt, .wake_fd = wake_fd, .exchange = exchange, .producer = producer, .presentation = presentation };
        return self;
    }
    /// Called only on the App's intent worker, never on the SDL thread.
    pub fn start(self: *Attached) !void {
        self.control = try connect(self.allocator, self.target, self.control_interrupt);
        self.observer = try std.Thread.spawn(.{}, observe, .{self});
    }
    /// Wakes setup, long observation and control I/O before either worker joins.
    pub fn stop(self: *Attached) void {
        self.mutex.lockUncancelable(self.io);
        self.stopping = true;
        if (self.observer_interrupt) |interrupt| interrupt.cancel() catch |failure| {
            self.failure = failure;
        };
        self.mutex.unlock(self.io);
        self.control_interrupt.cancel() catch |failure| {
            self.mutex.lockUncancelable(self.io);
            self.failure = failure;
            self.mutex.unlock(self.io);
        };
    }
    /// The intent worker and every backend lease must already be retired.
    pub fn deinit(self: *Attached) void {
        self.stop();
        if (self.observer) |thread| thread.join();
        if (self.mailbox) |*value| value.deinit();
        if (self.control) |*value| value.deinit();
        self.control_interrupt.deinit();
        publication.deinit(self.producer);
        self.presentation.deinit();
        const gpa = self.allocator;
        gpa.free(endpoint(self.target));
        gpa.destroy(self);
    }
    /// Transfers one mailbox cut without borrowing observer storage.
    pub fn take(self: *Attached) Error!?Observation {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.failure) |failure| return failure;
        const result = self.mailbox;
        self.mailbox = null;
        return result;
    }
    /// Cancels only a stale viewport request; the next connection names the same exact route.
    pub fn seek(self: *Attached, offset: u32) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.offset == offset) return;
        self.offset = offset;
        self.epoch +%= 1;
        if (self.mailbox) |*value| value.deinit();
        self.mailbox = null;
        if (self.observer_interrupt) |interrupt| interrupt.cancel() catch |failure| {
            self.failure = failure;
        };
    }
    fn observe(self: *Attached) void {
        self.observeLoop() catch |failure| {
            self.mutex.lockUncancelable(self.io);
            if (!self.stopping) self.failure = failure;
            self.mutex.unlock(self.io);
            self.wake();
        };
    }
    fn observeLoop(self: *Attached) !void {
        while (true) {
            const interrupt = try client.Interrupt.init(self.allocator);
            defer interrupt.deinit();
            self.mutex.lockUncancelable(self.io);
            if (self.stopping) {
                self.mutex.unlock(self.io);
                return;
            }
            const epoch = self.epoch;
            const offset = self.offset;
            self.observer_interrupt = interrupt;
            self.mutex.unlock(self.io);
            defer {
                self.mutex.lockUncancelable(self.io);
                self.observer_interrupt = null;
                self.mutex.unlock(self.io);
            }
            self.observeConnection(interrupt, epoch, offset) catch |failure| {
                self.mutex.lockUncancelable(self.io);
                const stopped = self.stopping;
                const superseded = self.epoch != epoch;
                self.mutex.unlock(self.io);
                if (stopped) return;
                if (!superseded or failure != error.ConnectionCanceled) return failure;
            };
        }
    }
    fn observeConnection(self: *Attached, interrupt: *client.Interrupt, epoch: u64, offset: u32) !void {
        var connection = try connect(self.allocator, self.target, interrupt);
        defer connection.deinit();
        var revision: u64 = 0;
        var cached: [render.maximum_external_images]?*Image = @splat(null);
        defer for (cached) |image| if (image) |value| value.release();
        while (true) {
            var raw = try client.rich.requestRaw(&connection, self.allocator, revision, offset);
            defer raw.deinit();
            const projected = try client.view.project(self.allocator, &raw);
            var cut: Observation = .{ .view = projected, .interaction = undefined };
            var cut_live = true;
            defer if (cut_live) cut.deinit();
            var next: [render.maximum_external_images]?*Image = @splat(null);
            var next_live = true;
            defer if (next_live) {
                for (next) |image| if (image) |value| value.release();
            };
            if (raw.graphics.images.len > next.len) return error.InvalidSnapshot;
            for (raw.graphics.images, 0..) |manifest, i| {
                for (cached) |image| if (image) |value| {
                    if (value.resource.image_id == manifest.image_id and value.resource.generation == manifest.generation) {
                        value.retain();
                        next[i] = value;
                        break;
                    }
                };
                if (next[i] == null) {
                    try connection.stream.beginOperation(5000);
                    defer connection.stream.endOperation();
                    var resource = try client.images.request(&connection, self.allocator, manifest.image_id, manifest.generation);
                    errdefer resource.deinit();
                    const image = try self.allocator.create(Image);
                    image.* = .{ .resource = resource, .allocator = self.allocator };
                    next[i] = image;
                }
                next[i].?.retain();
                cut.images[i] = next[i];
            }
            for (cached) |image| if (image) |value| value.release();
            cached = next;
            next_live = false;
            try connection.stream.beginOperation(5000);
            const state = try client.state.get(&connection);
            connection.stream.endOperation();
            var old: ?Observation = null;
            self.mutex.lockUncancelable(self.io);
            if (self.stopping or self.epoch != epoch) {
                self.mutex.unlock(self.io);
                return error.ConnectionCanceled;
            }
            old = self.mailbox;
            cut.interaction = interaction(state);
            self.mailbox = cut;
            cut_live = false;
            self.mutex.unlock(self.io);
            if (old) |*value| value.deinit();
            revision = raw.begin.revision;
            self.wake();
        }
    }
    fn wake(self: *Attached) void {
        const one: u64 = 1;
        while (true) {
            const result = posix.system.write(self.wake_fd, std.mem.asBytes(&one).ptr, 8);
            switch (posix.errno(result)) {
                .INTR => continue,
                .SUCCESS, .AGAIN => return,
                // zig-audit: acknowledge panic
                // reason: The State retires both borrowing workers before closing this eventfd; other errors violate that lifetime.
                else => @panic("attached wake descriptor failed"),
            }
        }
    }
    /// Sends canonical typed input on the independent bounded control lane.
    pub fn input(self: *Attached, event: instance.Input) client.actions.Error!void {
        const connection = &self.control.?;
        try connection.stream.beginOperation(5000);
        defer connection.stream.endOperation();
        switch (event) {
            .bytes => |value| if (value.len != 0) try client.actions.committedText(connection, value),
            .paste => |value| if (value.len != 0) try client.actions.paste(connection, value),
            .focus => |value| try client.actions.focus(connection, switch (value) {
                .in => .in,
                .out => .out,
            }),
            .key => |value| {
                const action: client.protocol.InputKeyAction = switch (value.action) {
                    .press => .press,
                    .repeat => .repeat,
                    .release => .release,
                };
                const kind: client.protocol.InputKeyKind = switch (value.key) {
                    .named => .named,
                    .unicode => .unicode,
                };
                const key_value: u32 = switch (value.key) {
                    .named => |key| switch (key) {
                        inline else => |tag| @backingInt(@field(client.protocol.InputKeyName, @tagName(tag))),
                    },
                    .unicode => |scalar| scalar.value,
                };
                try client.actions.keyInput(connection, .{ .kind = kind, .key_value = key_value, .action = action, .modifiers = @bitCast(value.mods), .shifted = if (value.shifted) |scalar| @as(u32, scalar) else null, .alternate = if (value.alternate) |scalar| @as(u32, scalar) else null, .legacy_text = value.legacy_text, .text = value.text });
            },
            .mouse => |value| try client.actions.mouse(connection, .{
                .kind = switch (value.kind) {
                    inline else => |tag| @field(client.protocol.InputMouseKind, @tagName(tag)),
                },
                .button = switch (value.button) {
                    inline else => |tag| @field(client.protocol.InputMouseButton, @tagName(tag)),
                },
                .modifiers = @bitCast(value.mod),
                .pixel_x = value.pixel_x,
                .pixel_y = value.pixel_y,
                .buttons_down = value.buttons_down,
                .row = value.row,
                .column = value.col,
            }),
        }
    }
    /// Explicit user intent takes geometry authority without resizing the terminal.
    pub fn acquireGeometry(self: *Attached) client.actions.Error!void {
        const connection = &self.control.?;
        try connection.stream.beginOperation(5000);
        defer connection.stream.endOperation();
        try client.actions.acquireGeometry(connection);
    }
    /// Ordinary resizing never acquires or steals geometry authority.
    pub fn resize(self: *Attached, rows: u16, columns: u16) client.actions.Error!void {
        const connection = &self.control.?;
        try connection.stream.beginOperation(5000);
        defer connection.stream.endOperation();
        const cell = self.presentation.fonts.cell();
        try client.actions.resizeGeometryOwned(connection, .{ .rows = rows, .columns = columns, .cell_pixel_width = cell.width, .cell_pixel_height = cell.height });
    }
    /// Commits owned presentation only after optional explicit geometry succeeds.
    pub fn reconfigure(self: *Attached, config: instance.PresentationConfig, surface: ?render.Size, rows: u16, columns: u16) ConfigureError!instance.PresentationGeometry {
        var candidate = try Presentation.init(self.allocator, config);
        errdefer candidate.deinit();
        if (self.presentation.generation == std.math.maxInt(u64)) return error.PresentationGenerationOverflow;
        candidate.generation = self.presentation.generation + 1;
        const cell = candidate.fonts.cell();
        var geometry: instance.PresentationGeometry = .{ .cell_size = cell, .rows = rows, .columns = columns };
        if (surface) |value| {
            geometry.rows = @intCast(std.math.clamp(value.height / cell.height, 1, render.limits.maximum_rows));
            geometry.columns = @intCast(std.math.clamp(value.width / cell.width, 1, render.limits.maximum_columns));
            const connection = &self.control.?;
            try connection.stream.beginOperation(5000);
            defer connection.stream.endOperation();
            client.actions.resizeGeometryOwned(connection, .{ .rows = geometry.rows, .columns = geometry.columns, .cell_pixel_width = cell.width, .cell_pixel_height = cell.height }) catch |failure| {
                if (failure != error.NotGeometryLeader and failure != error.ServerRejected) self.control_failure = failure;
                return failure;
            };
        }
        self.presentation.deinit();
        self.presentation = candidate;
        return geometry;
    }

    /// Claims the desktop role selected once per exact target by the App's pane lifetime owner.
    pub fn acquireDesktop(self: *Attached) Error!void {
        if (self.consequence_owned) return;
        const connection = &self.control.?;
        try connection.stream.beginOperation(5000);
        defer connection.stream.endOperation();
        try client.consequences.acquire(connection);
        self.consequence_owned = true;
        self.consequence_failure = null;
    }
    /// Services at most 64 exact FIFO effects; semantic observations wake this lane without an idle timer.
    pub fn drain(self: *Attached) Error!desktop.Applied {
        var result: desktop.Applied = .{};
        if (!self.consequence_owned) return result;
        const connection = &self.control.?;
        try connection.stream.beginOperation(5000);
        defer connection.stream.endOperation();
        var served: u8 = 0;
        while (served < 64) : (served += 1) {
            var head = client.consequences.observe(connection, self.allocator) catch |failure| {
                if (failure == error.NotAuthority) {
                    self.consequence_owned = false;
                    self.consequence_failure = error.NotAuthority;
                    return result;
                }
                return failure;
            };
            defer head.deinit();
            if (head.begin.kind == .none) {
                result.worked = false;
                return result;
            }
            result.worked = true;
            self.applyConsequence(&head, &result) catch |failure| {
                if (failure == error.ServerRejected) continue; // The exact occurrence expired before its reply.
                if (failure == error.NotAuthority) {
                    self.consequence_owned = false;
                    self.consequence_failure = error.NotAuthority;
                    return result;
                }
                return failure;
            };
        }
        return result;
    }
    fn applyConsequence(self: *Attached, head: *const client.consequences.Snapshot, result: *desktop.Applied) Error!void {
        const connection = &self.control.?;
        const begin = head.begin;
        if (begin.reply_required) {
            switch (begin.kind) {
                .clipboard => try client.consequences.reply(connection, begin.generation, .clipboard, ""),
                .pointer_shape => try client.consequences.reply(connection, begin.generation, .pointer_shape, "default"),
                .color_preference => try client.consequences.reply(connection, begin.generation, .color_preference, &.{1}),
                .container => {
                    if (begin.metadata[0] == @backingInt(client.protocol.ConsequenceContainerKind.report_screen_cells)) {
                        // This reply needs canonical current dimensions, not the app's surface.
                        var raw = try client.rich.requestRaw(connection, self.allocator, 0, 0);
                        defer raw.deinit();
                        var body: [8]u8 = undefined;
                        std.mem.writeInt(u32, body[0..4], raw.begin.rows, .big);
                        std.mem.writeInt(u32, body[4..8], raw.begin.columns, .big);
                        try client.consequences.reply(connection, begin.generation, .container_screen_cells, &body);
                    } else try client.consequences.reply(connection, begin.generation, .container_decline, "");
                },
                else => return error.InvalidSnapshot,
            }
        } else {
            const attention = begin.kind == .bell or (begin.kind == .notification and
                begin.metadata[0] != @backingInt(client.protocol.ConsequenceNotificationKind.message));
            try client.consequences.consume(connection, begin.generation);
            result.attention = result.attention or attention;
        }
    }

    /// Fetches one immediate canonical cut on the independent control connection.
    pub fn observeNow(self: *Attached, offset: u32) Error!*client.view.Snapshot {
        const connection = &self.control.?;
        try connection.stream.beginOperation(5000);
        defer connection.stream.endOperation();
        var raw = client.rich.requestRaw(connection, self.allocator, 0, offset) catch |failure| {
            self.control_failure = failure;
            return failure;
        };
        defer raw.deinit();
        return client.view.project(self.allocator, &raw);
    }
    /// Publishes owned image/glyph resources with the same immutable Canvas lease protocol.
    pub fn publish(self: *Attached, cut: *const Observation) RenderError!void {
        const present = &self.presentation;
        const view = cut.view;
        var candidate: [render.maximum_external_images]render.ExternalImageBinding = undefined;
        const bindings = try render.planExternalImageBindings(present.bindings[0..present.binding_count], render.usage(present.renderer), client.view.graphics(view).images, &candidate);
        try render.updateWithImageBindings(present.renderer, view, bindings);
        @memcpy(present.bindings[0..bindings.len], bindings);
        present.binding_count = bindings.len;
        if (publication.takeLatestResidency(self.producer, present.generation, &present.residency)) |accepted| present.residency_count = accepted.len;
        var missing_storage: [render.maximum_external_images]render.FrameExternalResource = undefined;
        const missing = try render.missingExternalResources(present.renderer, present.residency[0..present.residency_count], &missing_storage);
        var resources: [render.maximum_external_images]*const client.images.Resource = undefined;
        var resource_count: usize = 0;
        var prospective: [publication.maximum_prospective_residencies]render.Residency = undefined;
        @memcpy(prospective[0..present.residency_count], present.residency[0..present.residency_count]);
        var prospective_count = present.residency_count;
        var external_bytes: usize = 0;
        for (missing) |external| {
            var selected: ?render.ExternalImageBinding = null;
            for (bindings) |binding| if (std.meta.eql(binding.resource, external.resource)) {
                selected = binding;
                break;
            };
            const binding = selected orelse return error.InvalidImageBinding;
            var found: ?*const client.images.Resource = null;
            for (cut.images) |image| if (image) |value| {
                if (value.resource.image_id == binding.image_id and value.resource.generation == binding.generation) {
                    found = &value.resource;
                    break;
                }
            };
            const resource = found orelse return error.InvalidImageBinding;
            const stride = std.math.mul(usize, external.size.width, 4) catch return error.ArithmeticOverflow;
            const bytes = std.math.mul(usize, stride, external.size.height) catch return error.ArithmeticOverflow;
            if (external.format != .rgba8 or external.stride != stride or resource.width != external.size.width or
                resource.height != external.size.height or resource.pixels.len != bytes) return error.ExtentMismatch;
            resources[resource_count] = resource;
            resource_count += 1;
            external_bytes = std.math.add(usize, external_bytes, bytes) catch return error.ArithmeticOverflow;
            var at: ?usize = null;
            for (prospective[0..prospective_count], 0..) |accepted, i| if (accepted.resource.resource == external.resource.resource) {
                at = i;
                break;
            };
            if (at) |i| prospective[i] = .{ .resource = external.resource, .format = external.format, .size = external.size } else {
                if (prospective_count == prospective.len) return error.ResourceLimit;
                prospective[prospective_count] = .{ .resource = external.resource, .format = external.format, .size = external.size };
                prospective_count += 1;
            }
        }
        var writer = publication.beginWrite(self.producer) orelse return error.PublicationBusy;
        defer writer.abort();
        const pixels = try writer.pixelStorage(std.math.add(usize, external_bytes, present.atlas_bytes) catch return error.ArithmeticOverflow);
        const uploads = writer.uploadStorage();
        var offset: usize = 0;
        for (missing, resources[0..resource_count], 0..) |external, resource, i| {
            @memcpy(pixels[offset..][0..resource.pixels.len], resource.pixels);
            uploads[i] = .{ .resource = external.resource, .format = external.format, .size = external.size, .pixel_offset = offset, .pixel_count = resource.pixels.len, .stride = external.stride };
            offset += resource.pixels.len;
        }
        const frame = while (true) {
            const result = render.frame(present.renderer, prospective[0..prospective_count], .{
                .uploads = uploads[missing.len..],
                .removals = writer.removalStorage(),
                .commands = writer.commandStorage(),
                .pixels = pixels[external_bytes..],
            }) catch |failure| switch (failure) {
                error.CommandLimit => {
                    const capacity = writer.commandStorage().len;
                    if (capacity >= present.command_limit) return error.CommandLimit;
                    try writer.ensureCommandCapacity(@min(present.command_limit, @max(capacity + 1, std.math.mul(usize, capacity, 2) catch present.command_limit)));
                    continue;
                },
                else => |err| return err,
            };
            break result;
        };
        for (uploads[missing.len..][0..frame.uploads.len]) |*upload| upload.pixel_offset += external_bytes;
        const begin = client.view.begin(view);
        const cell = present.fonts.cell();
        const surface: render.Size = .{
            .width = std.math.mul(u16, begin.columns, cell.width) catch return error.InvalidPresentationGeometry,
            .height = std.math.mul(u16, begin.rows, cell.height) catch return error.InvalidPresentationGeometry,
        };
        writer.finish(present.generation, frame.revision, begin.terminal_revision, begin.history_offset, begin.history_count, begin.history_row_base, begin.alternate_screen, surface, cell, missing.len + frame.uploads.len, frame.removals.len, frame.commands.len, external_bytes + frame.pixels.len);
    }
};

fn interaction(source: client.protocol.InteractionStateSnapshot) instance.Terminal.InteractionState {
    var result: instance.Terminal.InteractionState = undefined;
    inline for (@typeInfo(instance.Terminal.InteractionState).@"struct".field_names, @typeInfo(instance.Terminal.InteractionState).@"struct".field_types) |name, field_type| {
        switch (field_type) {
            instance.Terminal.MouseTrackingMode => result.mouse_tracking = switch (source.mouse_tracking) {
                inline else => |tag| @field(instance.Terminal.MouseTrackingMode, @tagName(tag)),
            },
            instance.Terminal.MouseProtocol => result.mouse_protocol = switch (source.mouse_protocol) {
                inline else => |tag| @field(instance.Terminal.MouseProtocol, @tagName(tag)),
            },
            else => @field(result, name) = @field(source, name),
        }
    }
    return result;
}
/// Copies stable retained-domain facts from a transported cut.
pub fn context(begin: client.protocol.SnapshotBegin) selection.Context {
    return .{ .rows = begin.rows, .columns = begin.columns, .history_count = begin.history_count, .history_row_base = begin.history_row_base, .history_offset = begin.history_offset, .alternate = begin.alternate_screen };
}
/// Copies typed client selection identity into App selection vocabulary.
pub fn fromRange(range: client.selection.Range) selection.Range {
    return .{ .anchor = .{ .row = range.anchor.row, .col = range.anchor.column }, .focus = .{ .row = range.focus.row, .col = range.focus.column }, .columns = range.columns, .alternate = range.alternate_screen };
}
/// Copies App selection identity into a canonical extraction request.
pub fn toRange(range: selection.Range) client.selection.Range {
    return .{ .anchor = .{ .row = range.anchor.row, .column = range.anchor.col }, .focus = .{ .row = range.focus.row, .column = range.focus.col }, .columns = range.columns, .alternate_screen = range.alternate };
}

test "attachment routes reject incomplete identity before allocating or contacting an endpoint" {
    try validate(.{ .direct = "unix:/owned/socket" });
    try validate(.{ .server = .{ .endpoint = "tcp://127.0.0.1:43127", .server_id = 7, .session_id = 8, .instance_id = 9 } });
    try std.testing.expectError(error.InvalidTarget, validate(.{ .direct = "https://example.invalid" }));
    try std.testing.expectError(error.InvalidTarget, validate(.{ .direct = "unix:x\x00wrong" }));
    inline for (.{ "server_id", "session_id", "instance_id" }) |field| {
        var target: server.Target = .{ .endpoint = "unix:x", .server_id = 7, .session_id = 8, .instance_id = 9 };
        @field(target, field) = 0;
        try std.testing.expectError(error.InvalidTarget, validate(.{ .server = target }));
    }
}
