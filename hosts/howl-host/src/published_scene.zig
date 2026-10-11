//! Adapts immutable Instance-owned Render publications to howl-vk.
//!
//! This backend owner knows no PTY, VT, font, terminal-history, or Instance
//! mutation API. One leased publication remains immutable through candidate
//! staging and GPU completion, then returns only exact Render residency.

const std = @import("std");
const c = @import("host_c");
const instance = @import("howl_instance");
const terminal = instance.render.terminal;
const vk_surface = @import("howl_vk").surface;

const resource_limit: usize = terminal.maximum_external_images + 1;
const surface_pixel_bytes: usize = 16 * 1024 * 1024;
const command_capacity: usize = instance.render.limits.maximum_frame_commands;

/// One backend-ready immutable terminal layer.
pub const Prepared = struct {
    rows: u16,
    cols: u16,
    width: u16,
    height: u16,
    cell_size: terminal.Size,
    render_revision: u64,
    presentation_generation: u64,
    plan: vk_surface.Plan,
};

/// Reports whether one publication already owns the requested physical grid.
pub fn preparedMatchesGeometry(
    prepared: Prepared,
    rows: u16,
    cols: u16,
    cell_size: terminal.Size,
) bool {
    return prepared.rows == rows and
        prepared.cols == cols and
        std.meta.eql(prepared.cell_size, cell_size);
}

/// Converts one Instance publication into one transactional Vulkan surface layer.
pub const Scene = struct {
    allocator: std.mem.Allocator,
    exchange: *instance.RenderExchange,
    readiness_fd: i32,
    stop_fd: i32,
    builder: vk_surface.FrameBuilder,
    residency: vk_surface.ResidencyStore,
    uploads: []vk_surface.Upload,
    removals: []vk_surface.Removal,
    commands: []vk_surface.FrameCommand,
    surface_residencies: []vk_surface.Residency,
    renderer_residencies: []terminal.Residency,
    pending: ?instance.RenderLease = null,
    presentation_generation: u64 = 0,

    /// Allocates only backend conversion/residency storage around a shared exchange.
    pub fn init(
        allocator: std.mem.Allocator,
        exchange: *instance.RenderExchange,
        readiness_fd: i32,
        stop_fd: i32,
    ) !Scene {
        if (readiness_fd < 0 or stop_fd < 0) return error.InvalidDescriptor;
        var builder = try vk_surface.FrameBuilder.init(allocator);
        errdefer builder.deinit();
        var residency = try vk_surface.ResidencyStore.init(
            allocator,
            .{ .resources = resource_limit, .pixel_bytes = surface_pixel_bytes },
        );
        errdefer residency.deinit();
        const uploads = try allocator.alloc(vk_surface.Upload, resource_limit);
        errdefer allocator.free(uploads);
        const removals = try allocator.alloc(vk_surface.Removal, resource_limit);
        errdefer allocator.free(removals);
        const commands = try allocator.alloc(vk_surface.FrameCommand, command_capacity);
        errdefer allocator.free(commands);
        const surface_residencies = try allocator.alloc(vk_surface.Residency, resource_limit);
        errdefer allocator.free(surface_residencies);
        const renderer_residencies = try allocator.alloc(terminal.Residency, resource_limit);
        return .{
            .allocator = allocator,
            .exchange = exchange,
            .readiness_fd = readiness_fd,
            .stop_fd = stop_fd,
            .builder = builder,
            .residency = residency,
            .uploads = uploads,
            .removals = removals,
            .commands = commands,
            .surface_residencies = surface_residencies,
            .renderer_residencies = renderer_residencies,
        };
    }

    /// Releases backend storage after every publication lease has been returned.
    pub fn deinit(self: *Scene) void {
        std.debug.assert(self.pending == null);
        self.allocator.free(self.renderer_residencies);
        self.allocator.free(self.surface_residencies);
        self.allocator.free(self.commands);
        self.allocator.free(self.removals);
        self.allocator.free(self.uploads);
        self.residency.deinit();
        self.builder.deinit();
        self.* = undefined;
    }

    /// Borrows the terminal-thread publication wake descriptor.
    pub fn readinessFd(self: *const Scene) i32 {
        return self.readiness_fd;
    }

    /// Waits until a publication or shutdown is observable, then claims newest.
    pub fn prepare(self: *Scene) !Prepared {
        while (true) {
            if (try self.tryReceivePrepared()) |prepared| return prepared;
            var descriptors = [_]c.pollfd{
                .{ .fd = self.readiness_fd, .events = c.POLLIN, .revents = 0 },
                .{ .fd = self.stop_fd, .events = c.POLLIN, .revents = 0 },
            };
            const ready = c.poll(&descriptors, descriptors.len, -1);
            if (ready < 0) {
                if (std.c.errno(ready) == .INTR) continue;
                return error.ScenePoll;
            }
            if (descriptors[1].revents != 0) return error.Stopping;
            if (descriptors[0].revents & (c.POLLERR | c.POLLHUP | c.POLLNVAL) != 0)
                return error.ScenePoll;
        }
    }

    /// Drains coalesced wakes and claims the newest unread publication, if any.
    pub fn tryReceivePrepared(self: *Scene) !?Prepared {
        if (self.pending != null) return error.PendingPublication;
        try drainWake(self.readiness_fd);
        var lease = instance.acquirePublishedFrame(self.exchange) orelse return null;
        var lease_owned = true;
        errdefer if (lease_owned) lease.abandon();

        if (self.presentation_generation != 0 and
            self.presentation_generation != lease.value.presentation_generation)
            self.residency.reset();

        const frame = try adaptPublishedFrame(
            lease.value,
            self.uploads,
            self.removals,
            self.commands,
        );
        try self.residency.stage(frame);
        errdefer self.residency.discard();
        const plan = try self.builder.build(&self.residency, frame);

        const cell = lease.value.cell_size;
        if (cell.width == 0 or cell.height == 0 or
            lease.value.surface.width % cell.width != 0 or
            lease.value.surface.height % cell.height != 0)
            return error.InvalidGeometry;
        const rows: u16 = lease.value.surface.height / cell.height;
        const cols: u16 = lease.value.surface.width / cell.width;
        if (rows == 0 or cols == 0) return error.InvalidGeometry;

        self.presentation_generation = lease.value.presentation_generation;
        self.pending = lease;
        lease_owned = false;
        return .{
            .rows = rows,
            .cols = cols,
            .width = lease.value.surface.width,
            .height = lease.value.surface.height,
            .cell_size = cell,
            .render_revision = lease.value.revision,
            .presentation_generation = lease.value.presentation_generation,
            .plan = plan,
        };
    }

    /// Commits the staged backend resources and reports exact accepted residency.
    pub fn complete(self: *Scene) !void {
        var lease = self.pending orelse return error.NoPendingPublication;
        self.pending = null;
        try self.residency.complete();
        try self.releaseLease(&lease);
    }

    /// Discards an unsubmitted candidate and reports the still-accepted residency.
    pub fn discardPrepared(self: *Scene, _: Prepared) !void {
        var lease = self.pending orelse return;
        self.pending = null;
        self.residency.discard();
        try self.releaseLease(&lease);
    }

    fn releaseLease(self: *Scene, lease: *instance.RenderLease) !void {
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
        try lease.release(self.renderer_residencies[0..resident.len]);
    }
};

fn drainWake(descriptor: i32) error{Signal}!void {
    var value: u64 = 0;
    while (true) {
        const result = c.read(descriptor, &value, @sizeOf(u64));
        if (result == @sizeOf(u64)) continue;
        if (result < 0 and std.c.errno(result) == .INTR) continue;
        if (result < 0 and std.c.errno(result) == .AGAIN) return;
        return error.Signal;
    }
}

fn adaptPublishedFrame(
    published: instance.PublishedFrame,
    uploads: []vk_surface.Upload,
    removals: []vk_surface.Removal,
    commands: []vk_surface.FrameCommand,
) !vk_surface.Frame {
    if (published.uploads.len > uploads.len or
        published.removals.len > removals.len or
        published.commands.len > commands.len)
        return error.Capacity;

    for (published.uploads, 0..) |value, index| {
        const end = std.math.add(usize, value.pixel_offset, value.pixel_count) catch
            return error.ArithmeticOverflow;
        if (end > published.pixels.len) return error.Capacity;
        uploads[index] = .{
            .resource = try surfaceResource(value.resource),
            .kind = switch (value.format) {
                .alpha8 => .alpha_mask,
                .rgba8 => .rgba,
            },
            .width = value.size.width,
            .height = value.size.height,
            .stride = value.stride,
            .pixels = published.pixels[value.pixel_offset..end],
        };
    }
    for (published.removals, 0..) |value, index| removals[index] = .{
        .resource = try surfaceResource(value),
    };
    for (published.commands, 0..) |value, index| commands[index] = switch (value) {
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
        .revision = published.revision,
        .uploads = uploads[0..published.uploads.len],
        .removals = removals[0..published.removals.len],
        .commands = commands[0..published.commands.len],
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

test "published scene converts one owned RGBA upload without terminal state" {
    const resource = terminal.ResourceRef{
        .resource = try terminal.ResourceId.init(2),
        .generation = @fromBackingInt(9),
    };
    const pixels = [_]u8{ 1, 2, 3, 4 };
    const published = instance.PublishedFrame{
        .sequence = 1,
        .presentation_generation = 1,
        .revision = 1,
        .terminal_revision = 1,
        .history_offset = 0,
        .history_count = 0,
        .history_row_base = 0,
        .alternate_screen = false,
        .surface = .{ .width = 10, .height = 20 },
        .cell_size = .{ .width = 10, .height = 20 },
        .uploads = &.{.{
            .resource = resource,
            .format = .rgba8,
            .size = .{ .width = 1, .height = 1 },
            .pixel_offset = 0,
            .pixel_count = 4,
            .stride = 4,
        }},
        .removals = &.{},
        .commands = &.{},
        .pixels = &pixels,
    };
    var uploads: [1]vk_surface.Upload = undefined;
    var removals: [1]vk_surface.Removal = undefined;
    var commands: [1]vk_surface.FrameCommand = undefined;
    const frame = try adaptPublishedFrame(
        published,
        &uploads,
        &removals,
        &commands,
    );
    try std.testing.expectEqual(@as(usize, 1), frame.uploads.len);
    try std.testing.expectEqual(vk_surface.Kind.rgba, frame.uploads[0].kind);
    try std.testing.expectEqualSlices(u8, &pixels, frame.uploads[0].pixels);
}
