//! Tiny C-shaped seam from the Odin desktop shell to the existing Howl client.
//!
//! This bridge deliberately exports no wire structs or client backing layouts.
//! `howl-client` remains the sole decoder/action owner; Odin gets bounded UTF-8
//! presentation text, scalar snapshot metadata, and semantic input operations.

const std = @import("std");
const client = @import("howl_client");
const protocol = @import("howl_session").protocol;
const session_process = @import("session_process");

const render = @import("howl_render");
const canvas = render.canvas;
const terminal_render = render.terminal;

const RenderHandle = opaque {};
const render_resource_limit: usize = terminal_render.maximum_external_images + 1;
const render_atlas_extent: u16 = 512;
const render_pixel_capacity: usize = @as(usize, render_atlas_extent) * render_atlas_extent;
const render_command_capacity: usize = render.presentation.maximum_canvas_commands;

pub const RenderResourceInfo = extern struct {
    source: u64 = 0,
    resource: u64 = 0,
    generation: u64 = 0,
    pixel_count: u64 = 0,
    stride: u64 = 0,
    width: u16 = 0,
    height: u16 = 0,
    format: u8 = 0,
    _reserved: [7]u8 = @splat(0),
};

pub const RenderRemovalInfo = extern struct {
    source: u64 = 0,
    resource: u64 = 0,
    generation: u64 = 0,
};

pub const RenderCommandInfo = extern struct {
    resource_source: u64 = 0,
    resource: u64 = 0,
    generation: u64 = 0,
    color_rgba: u32 = 0,
    destination_x: i32 = 0,
    destination_y: i32 = 0,
    clip_x: i32 = 0,
    clip_y: i32 = 0,
    destination_width: u16 = 0,
    destination_height: u16 = 0,
    clip_width: u16 = 0,
    clip_height: u16 = 0,
    source_x: u16 = 0,
    source_y: u16 = 0,
    source_width: u16 = 0,
    source_height: u16 = 0,
    resource_width: u16 = 0,
    resource_height: u16 = 0,
    tag: u8 = 0,
    format: u8 = 0,
    cursor_component: u8 = 0,
    _reserved: u8 = 0,
};

const Render = struct {
    allocator: std.mem.Allocator,
    connection: client.Connection,
    fonts: *render.text.FontSet,
    content: *terminal_render.Content,
    composer: canvas.Composer,
    source: canvas.SourceId,
    cell_size: canvas.Size,
    frame_uploads: [render_resource_limit]canvas.FrameResourceUpload = undefined,
    frame_removals: [render_resource_limit]canvas.FrameResourceRef = undefined,
    frame_commands: []canvas.Command,
    frame_pixels: []u8,
    residencies: [render_resource_limit]canvas.Residency = undefined,
    residency_count: usize = 0,
    upload_count: usize = 0,
    removal_count: usize = 0,
    command_count: usize = 0,
    pixel_count: usize = 0,
    frame_revision: u64 = 0,
    session_revision: u64 = 0,
    surface: canvas.Size = .{ .width = 1, .height = 1 },
    last_error: [160]u8 = undefined,
    last_error_len: usize = 0,

    fn clearError(self: *Render) void {
        self.last_error_len = 0;
    }

    fn setError(self: *Render, stage: []const u8, failure_name: []const u8) void {
        const value = std.fmt.bufPrint(&self.last_error, "{s}:{s}", .{ stage, failure_name }) catch {
            self.last_error_len = 0;
            return;
        };
        self.last_error_len = value.len;
    }
};

fn renderContentConfig(cell_size: canvas.Size) terminal_render.ContentConfig {
    return .{
        .cell_size = cell_size,
        .box_drawing = .{
            .dpi_x = .{ .numerator = 96, .denominator = 1 },
            .dpi_y = .{ .numerator = 96, .denominator = 1 },
        },
        .shape_cache = .{
            .entry_capacity = 256,
            .scalar_capacity = 512,
            .glyph_capacity = 512,
            .max_sequence_scalars = 16,
        },
        .atlas = .{
            .width = render_atlas_extent,
            .height = render_atlas_extent,
            .entry_capacity = 256,
        },
        .shaped_capacity = 32,
        .raster_bytes = render_pixel_capacity,
        .command_capacity = render_command_capacity,
    };
}

fn renderSurface(rows: u16, columns: u16, cell: canvas.Size) !canvas.Size {
    const width = try std.math.mul(u32, columns, cell.width);
    const height = try std.math.mul(u32, rows, cell.height);
    if (width == 0 or height == 0 or width > std.math.maxInt(u16) or height > std.math.maxInt(u16))
        return error.InvalidSurface;
    return .{ .width = @intCast(width), .height = @intCast(height) };
}

pub export fn howl_odin_bridge_render_create(
    endpoint_ptr: [*]const u8,
    endpoint_len: usize,
    font_ptr: [*]const u8,
    font_len: usize,
    font_pixels: u16,
    diagnostic_ptr: [*]u8,
    diagnostic_capacity: usize,
    diagnostic_len: *usize,
) ?*RenderHandle {
    diagnostic_len.* = 0;
    if (endpoint_len == 0 or font_len == 0 or font_pixels == 0) {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "invalid_render_arguments");
        return null;
    }
    const allocator = std.heap.c_allocator;
    var connect_diagnostic: client.ConnectDiagnostic = .{};
    var connection = client.Connection.connectDiagnosed(
        allocator,
        endpoint_ptr[0..endpoint_len],
        &connect_diagnostic,
    ) catch |failure| {
        writeConnectDiagnostic(
            diagnostic_ptr,
            diagnostic_capacity,
            diagnostic_len,
            @errorName(failure),
            connect_diagnostic,
        );
        return null;
    };
    errdefer connection.deinit();
    const fonts = render.text.FontSet.init(allocator, .{
        .primary = font_ptr[0..font_len],
        .size = .{ .pixels = font_pixels },
    }) catch |failure| {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, @errorName(failure));
        return null;
    };
    errdefer fonts.deinit();
    const metrics = fonts.metrics();
    const cell_size = canvas.Size{
        .width = metrics.advance_width,
        .height = metrics.line_height,
    };
    const content = terminal_render.initContent(allocator, fonts, renderContentConfig(cell_size)) catch |failure| {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, @errorName(failure));
        return null;
    };
    errdefer terminal_render.deinitContent(content);
    var composer = canvas.Composer.init(allocator, .{
        .sources = 1,
        .retained_resources = render_resource_limit,
        .retained_commands = render_command_capacity,
        .retained_pixel_bytes = render_pixel_capacity,
        .composition_sources = 1,
        .candidate_resources = render_resource_limit,
        .candidate_commands = render_command_capacity,
        .candidate_pixel_bytes = render_pixel_capacity,
    }) catch |failure| {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, @errorName(failure));
        return null;
    };
    errdefer composer.deinit();
    const source = composer.registerSource() catch |failure| {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, @errorName(failure));
        return null;
    };
    const frame_commands = allocator.alloc(canvas.Command, render_command_capacity) catch {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "out_of_memory");
        return null;
    };
    errdefer allocator.free(frame_commands);
    const frame_pixels = allocator.alloc(u8, render_pixel_capacity) catch {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "out_of_memory");
        return null;
    };
    errdefer allocator.free(frame_pixels);
    const value = allocator.create(Render) catch {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "out_of_memory");
        return null;
    };
    value.* = .{
        .allocator = allocator,
        .connection = connection,
        .fonts = fonts,
        .content = content,
        .composer = composer,
        .source = source,
        .cell_size = cell_size,
        .frame_commands = frame_commands,
        .frame_pixels = frame_pixels,
    };
    return @ptrCast(value);
}

pub export fn howl_odin_bridge_render_destroy(raw: ?*RenderHandle) void {
    const value = raw orelse return;
    const renderer: *Render = @ptrCast(@alignCast(value));
    const allocator = renderer.allocator;
    allocator.free(renderer.frame_pixels);
    allocator.free(renderer.frame_commands);
    renderer.composer.deinit();
    terminal_render.deinitContent(renderer.content);
    renderer.fonts.deinit();
    renderer.connection.deinit();
    allocator.destroy(renderer);
}

pub export fn howl_odin_bridge_render_observe(raw: ?*RenderHandle) i32 {
    const value = raw orelse return 1;
    const renderer: *Render = @ptrCast(@alignCast(value));
    renderer.clearError();
    var rich = client.rich.request(&renderer.connection, renderer.allocator, 0, 0) catch |failure| {
        renderer.setError("observe", @errorName(failure));
        return 2;
    };
    defer rich.deinit();
    if (rich.graphics.images.len != 0) {
        renderer.setError("render", "terminal_images_not_yet_supported");
        return 3;
    }
    const view = client.view.project(renderer.allocator, &rich) catch |failure| {
        renderer.setError("project", @errorName(failure));
        return 3;
    };
    defer client.view.deinit(view);
    const begin = client.view.begin(view).*;
    const surface = renderSurface(begin.rows, begin.columns, renderer.cell_size) catch |failure| {
        renderer.setError("surface", @errorName(failure));
        return 3;
    };
    renderer.composer.setComposition(.{
        .surface = surface,
        .sources = &.{.{
            .source = renderer.source,
            .origin = .{ .x = 0, .y = 0 },
            .clip = .{ .x = 0, .y = 0, .width = surface.width, .height = surface.height },
        }},
        .focused_source = renderer.source,
    }) catch |failure| {
        renderer.setError("composition", @errorName(failure));
        return 3;
    };
    const update = terminal_render.takeContentUpdate(renderer.content, view, .{
        .pane = 1,
        .source = renderer.source,
        .visible_set_revision = 1,
        .lifecycle_revision = 1,
    }) catch |failure| {
        renderer.setError("content", @errorName(failure));
        return 3;
    };
    renderer.composer.apply(renderer.source, update) catch |failure| {
        renderer.setError("apply", @errorName(failure));
        return 3;
    };
    const frame = renderer.composer.frame(
        renderer.residencies[0..renderer.residency_count],
        .{
            .uploads = &renderer.frame_uploads,
            .removals = &renderer.frame_removals,
            .commands = renderer.frame_commands,
            .pixels = renderer.frame_pixels,
        },
    ) catch |failure| {
        renderer.setError("frame", @errorName(failure));
        return 3;
    };
    renderer.upload_count = frame.uploads.len;
    renderer.removal_count = frame.removals.len;
    renderer.command_count = frame.commands.len;
    renderer.pixel_count = frame.pixels.len;
    renderer.frame_revision = @backingInt(frame.revision);
    renderer.session_revision = begin.revision;
    renderer.surface = surface;
    updateRenderResidency(renderer, frame.uploads, frame.removals);
    return 0;
}

fn updateRenderResidency(
    renderer: *Render,
    uploads: []const canvas.FrameResourceUpload,
    removals: []const canvas.FrameResourceRef,
) void {
    for (removals) |removal| {
        var index: usize = 0;
        while (index < renderer.residency_count) {
            if (std.meta.eql(renderer.residencies[index].resource, removal)) {
                renderer.residency_count -= 1;
                renderer.residencies[index] = renderer.residencies[renderer.residency_count];
                break;
            }
            index += 1;
        }
    }
    for (uploads) |upload| {
        var index: usize = 0;
        while (index < renderer.residency_count) : (index += 1) {
            const existing = renderer.residencies[index];
            if (@backingInt(existing.resource.source) == @backingInt(upload.resource.source) and
                @backingInt(existing.resource.resource) == @backingInt(upload.resource.resource))
            {
                renderer.residencies[index] = .{
                    .resource = upload.resource,
                    .format = upload.format,
                    .size = upload.size,
                };
                break;
            }
        }
        if (index == renderer.residency_count and renderer.residency_count < renderer.residencies.len) {
            renderer.residencies[renderer.residency_count] = .{
                .resource = upload.resource,
                .format = upload.format,
                .size = upload.size,
            };
            renderer.residency_count += 1;
        }
    }
}

pub export fn howl_odin_bridge_render_surface_width(raw: ?*RenderHandle) u16 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    return renderer.surface.width;
}

pub export fn howl_odin_bridge_render_surface_height(raw: ?*RenderHandle) u16 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    return renderer.surface.height;
}

pub export fn howl_odin_bridge_render_cell_width(raw: ?*RenderHandle) u16 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    return renderer.cell_size.width;
}

pub export fn howl_odin_bridge_render_cell_height(raw: ?*RenderHandle) u16 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    return renderer.cell_size.height;
}

pub export fn howl_odin_bridge_render_maximum_rows() u16 {
    return render.presentation.maximum_rows;
}

pub export fn howl_odin_bridge_render_maximum_columns() u16 {
    return render.presentation.maximum_columns;
}

pub export fn howl_odin_bridge_render_frame_revision(raw: ?*RenderHandle) u64 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    return renderer.frame_revision;
}

pub export fn howl_odin_bridge_render_session_revision(raw: ?*RenderHandle) u64 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    return renderer.session_revision;
}

pub export fn howl_odin_bridge_render_upload_count(raw: ?*RenderHandle) u32 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    return @intCast(renderer.upload_count);
}

pub export fn howl_odin_bridge_render_removal_count(raw: ?*RenderHandle) u32 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    return @intCast(renderer.removal_count);
}

pub export fn howl_odin_bridge_render_command_count(raw: ?*RenderHandle) u32 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    return @intCast(renderer.command_count);
}

fn fillRenderResourceRef(resource: canvas.FrameResourceRef, output: *RenderResourceInfo) void {
    output.source = @backingInt(resource.source);
    output.resource = @backingInt(resource.resource);
    output.generation = @backingInt(resource.generation);
}

fn fillRenderRemovalRef(resource: canvas.FrameResourceRef, output: *RenderRemovalInfo) void {
    output.source = @backingInt(resource.source);
    output.resource = @backingInt(resource.resource);
    output.generation = @backingInt(resource.generation);
}

pub export fn howl_odin_bridge_render_upload_info(
    raw: ?*RenderHandle,
    index: u32,
    output: *RenderResourceInfo,
) i32 {
    output.* = .{};
    const value = raw orelse return 1;
    const renderer: *Render = @ptrCast(@alignCast(value));
    if (index >= renderer.upload_count) return 2;
    const upload = renderer.frame_uploads[index];
    fillRenderResourceRef(upload.resource, output);
    output.pixel_count = upload.pixel_count;
    output.stride = upload.stride;
    output.width = upload.size.width;
    output.height = upload.size.height;
    output.format = @backingInt(upload.format);
    return 0;
}

pub export fn howl_odin_bridge_render_upload_copy(
    raw: ?*RenderHandle,
    index: u32,
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
) i32 {
    output_len.* = 0;
    const value = raw orelse return 1;
    const renderer: *Render = @ptrCast(@alignCast(value));
    if (index >= renderer.upload_count) return 2;
    const upload = renderer.frame_uploads[index];
    if (upload.pixel_offset + upload.pixel_count > renderer.pixel_count) return 3;
    if (output_capacity < upload.pixel_count) return 4;
    @memcpy(
        output_ptr[0..upload.pixel_count],
        renderer.frame_pixels[upload.pixel_offset .. upload.pixel_offset + upload.pixel_count],
    );
    output_len.* = upload.pixel_count;
    return 0;
}

pub export fn howl_odin_bridge_render_removal_info(
    raw: ?*RenderHandle,
    index: u32,
    output: *RenderRemovalInfo,
) i32 {
    output.* = .{};
    const value = raw orelse return 1;
    const renderer: *Render = @ptrCast(@alignCast(value));
    if (index >= renderer.removal_count) return 2;
    fillRenderRemovalRef(renderer.frame_removals[index], output);
    return 0;
}

fn colorBits(color: canvas.Color) u32 {
    return @as(u32, color.r) |
        (@as(u32, color.g) << 8) |
        (@as(u32, color.b) << 16) |
        (@as(u32, color.a) << 24);
}

fn fillCommandResource(output: *RenderCommandInfo, resource: canvas.FrameResourceView) void {
    output.resource_source = @backingInt(resource.resource.source);
    output.resource = @backingInt(resource.resource.resource);
    output.generation = @backingInt(resource.resource.generation);
    output.format = @backingInt(resource.format);
    output.resource_width = resource.size.width;
    output.resource_height = resource.size.height;
    const source = resource.source orelse canvas.SourceRect{
        .x = 0,
        .y = 0,
        .width = resource.size.width,
        .height = resource.size.height,
    };
    output.source_x = source.x;
    output.source_y = source.y;
    output.source_width = source.width;
    output.source_height = source.height;
}

fn fillRectFields(
    destination: canvas.Rect,
    clip: canvas.Rect,
    output: *RenderCommandInfo,
) void {
    output.destination_x = destination.x;
    output.destination_y = destination.y;
    output.destination_width = destination.width;
    output.destination_height = destination.height;
    output.clip_x = clip.x;
    output.clip_y = clip.y;
    output.clip_width = clip.width;
    output.clip_height = clip.height;
}

pub export fn howl_odin_bridge_render_command_info(
    raw: ?*RenderHandle,
    index: u32,
    output: *RenderCommandInfo,
) i32 {
    output.* = .{};
    const value = raw orelse return 1;
    const renderer: *Render = @ptrCast(@alignCast(value));
    if (index >= renderer.command_count) return 2;
    switch (renderer.frame_commands[index]) {
        .solid => |command| {
            output.tag = 0;
            output.color_rgba = colorBits(command.color);
            fillRectFields(command.rect, command.rect, output);
        },
        .alpha_mask => |command| {
            output.tag = 1;
            output.color_rgba = colorBits(command.color);
            output.cursor_component = @intFromBool(command.cursor_component);
            fillRectFields(command.destination, command.clip, output);
            fillCommandResource(output, command.resource);
        },
        .rgba => |command| {
            output.tag = 2;
            fillRectFields(command.destination, command.clip, output);
            fillCommandResource(output, command.resource);
        },
    }
    return 0;
}

pub export fn howl_odin_bridge_render_copy_error(
    raw: ?*RenderHandle,
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
) void {
    output_len.* = 0;
    const value = raw orelse return;
    const renderer: *Render = @ptrCast(@alignCast(value));
    const count = @min(output_capacity, renderer.last_error_len);
    @memcpy(output_ptr[0..count], renderer.last_error[0..count]);
    output_len.* = count;
}

pub export fn howl_odin_bridge_render_resource_info_size() u32 {
    return @sizeOf(RenderResourceInfo);
}

pub export fn howl_odin_bridge_render_removal_info_size() u32 {
    return @sizeOf(RenderRemovalInfo);
}

pub export fn howl_odin_bridge_render_command_info_size() u32 {
    return @sizeOf(RenderCommandInfo);
}


const Handle = opaque {};
const CancellationHandle = opaque {};
const OwnedSessionHandle = opaque {};

const OwnedSession = struct {
    allocator: std.mem.Allocator,
    threaded: std.Io.Threaded,
    process: ?session_process.SessionProcess = null,
};

const Bridge = struct {
    allocator: std.mem.Allocator,
    connection: client.Connection,
    last_begin: ?protocol.SnapshotBegin = null,
    text_truncated: bool = false,
    last_error: [160]u8 = undefined,
    last_error_len: usize = 0,

    fn clearError(self: *Bridge) void {
        self.last_error_len = 0;
    }

    fn setError(self: *Bridge, stage: []const u8, failure_name: []const u8) void {
        const rendered = std.fmt.bufPrint(
            &self.last_error,
            "{s}:{s}",
            .{ stage, failure_name },
        ) catch {
            self.last_error_len = 0;
            return;
        };
        self.last_error_len = rendered.len;
    }
};

pub export fn howl_odin_bridge_version() u32 {
    return 2;
}

/// Launches one client-owned canonical Session using the existing native
/// SessionProcess owner. The matching `howl-sessiond` must be packaged beside
/// the Odin executable. A null environment map deliberately inherits the
/// desktop client's current environment.
pub export fn howl_odin_bridge_owned_session_create(
    runtime_dir_ptr: [*]const u8,
    runtime_dir_len: usize,
    shell_ptr: [*]const u8,
    shell_len: usize,
    rows: u16,
    columns: u16,
    identity: u32,
    diagnostic_ptr: [*]u8,
    diagnostic_capacity: usize,
    diagnostic_len: *usize,
) ?*OwnedSessionHandle {
    diagnostic_len.* = 0;
    if (runtime_dir_len == 0 or shell_len == 0 or rows == 0 or columns == 0 or identity == 0) {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "invalid_session_launch");
        return null;
    }
    const allocator = std.heap.c_allocator;
    const owned = allocator.create(OwnedSession) catch {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "out_of_memory");
        return null;
    };
    owned.* = .{
        .allocator = allocator,
        .threaded = std.Io.Threaded.init(std.heap.page_allocator, .{}),
    };
    errdefer {
        owned.threaded.deinit();
        allocator.destroy(owned);
    }
    owned.process = session_process.SessionProcess.launchSibling(
        allocator,
        owned.threaded.io(),
        runtime_dir_ptr[0..runtime_dir_len],
        shell_ptr[0..shell_len],
        null,
        rows,
        columns,
        identity,
    ) catch |failure| {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, @errorName(failure));
        return null;
    };
    return @ptrCast(owned);
}

pub export fn howl_odin_bridge_owned_session_destroy(raw: ?*OwnedSessionHandle) void {
    const value = raw orelse return;
    const owned: *OwnedSession = @ptrCast(@alignCast(value));
    const allocator = owned.allocator;
    if (owned.process) |*process| process.deinit();
    owned.threaded.deinit();
    allocator.destroy(owned);
}

pub export fn howl_odin_bridge_owned_session_copy_endpoint(
    raw: ?*OwnedSessionHandle,
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
) i32 {
    output_len.* = 0;
    const value = raw orelse return 1;
    const owned: *OwnedSession = @ptrCast(@alignCast(value));
    const process = owned.process orelse return 2;
    if (output_capacity < process.endpoint.len) return 3;
    @memcpy(output_ptr[0..process.endpoint.len], process.endpoint);
    output_len.* = process.endpoint.len;
    return 0;
}

pub export fn howl_odin_bridge_create(
    endpoint_ptr: [*]const u8,
    endpoint_len: usize,
    diagnostic_ptr: [*]u8,
    diagnostic_capacity: usize,
    diagnostic_len: *usize,
) ?*Handle {
    diagnostic_len.* = 0;
    if (endpoint_len == 0) {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "invalid_endpoint");
        return null;
    }

    const allocator = std.heap.c_allocator;
    var connect_diagnostic: client.ConnectDiagnostic = .{};
    var connection = client.Connection.connectDiagnosed(
        allocator,
        endpoint_ptr[0..endpoint_len],
        &connect_diagnostic,
    ) catch |failure| {
        writeConnectDiagnostic(
            diagnostic_ptr,
            diagnostic_capacity,
            diagnostic_len,
            @errorName(failure),
            connect_diagnostic,
        );
        return null;
    };
    errdefer connection.deinit();

    const bridge = allocator.create(Bridge) catch {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "out_of_memory");
        return null;
    };
    bridge.* = .{
        .allocator = allocator,
        .connection = connection,
    };
    return @ptrCast(bridge);
}

pub export fn howl_odin_bridge_destroy(raw: ?*Handle) void {
    const value = raw orelse return;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    const allocator = bridge.allocator;
    bridge.connection.deinit();
    allocator.destroy(bridge);
}

/// Creates one independent wake handle for a potentially blocking observation.
///
/// The duplicate never sends Howl protocol bytes. It only shuts down the
/// observer socket so another thread can leave a blocked receive during client
/// teardown.
pub export fn howl_odin_bridge_cancellation_create(raw: ?*Handle) ?*CancellationHandle {
    const value = raw orelse return null;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    const cancellation = bridge.allocator.create(client.Cancellation) catch return null;
    cancellation.* = bridge.connection.cancellation() catch {
        bridge.allocator.destroy(cancellation);
        return null;
    };
    return @ptrCast(cancellation);
}

pub export fn howl_odin_bridge_cancellation_cancel(raw: ?*CancellationHandle) i32 {
    const value = raw orelse return 1;
    const cancellation: *client.Cancellation = @ptrCast(@alignCast(value));
    cancellation.cancel() catch return 2;
    return 0;
}

pub export fn howl_odin_bridge_cancellation_destroy(raw: ?*CancellationHandle) void {
    const value = raw orelse return;
    const cancellation: *client.Cancellation = @ptrCast(@alignCast(value));
    const allocator = std.heap.c_allocator;
    cancellation.deinit();
    allocator.destroy(cancellation);
}

/// Requests one complete current viewport and projects it to bounded UTF-8.
///
/// Revision zero is the intended immediate-snapshot canary lane. Later the Odin
/// client may use revision-relative blocking observation on a worker without
/// changing this ownership boundary.
pub export fn howl_odin_bridge_snapshot(
    raw: ?*Handle,
    after_revision: u64,
    history_offset: u32,
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
) i32 {
    output_len.* = 0;
    const value = raw orelse return 1;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    bridge.clearError();

    var rich = client.rich.request(
        &bridge.connection,
        bridge.allocator,
        after_revision,
        history_offset,
    ) catch |failure| {
        bridge.setError("observe", @errorName(failure));
        return 2;
    };
    defer rich.deinit();

    const projected = client.view.project(bridge.allocator, &rich) catch |failure| {
        bridge.setError("project", @errorName(failure));
        return 3;
    };
    defer client.view.deinit(projected);

    const text = client.view.writeVisibleText(projected, output_ptr[0..output_capacity]);
    bridge.last_begin = client.view.begin(projected).*;
    bridge.text_truncated = text.truncated;
    output_len.* = text.bytes_written;
    return 0;
}

pub export fn howl_odin_bridge_send_text(
    raw: ?*Handle,
    bytes_ptr: [*]const u8,
    bytes_len: usize,
) i32 {
    const value = raw orelse return 1;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    client.actions.committedText(&bridge.connection, bytes_ptr[0..bytes_len]) catch |failure| {
        bridge.setError("text", @errorName(failure));
        return 2;
    };
    return 0;
}

pub export fn howl_odin_bridge_send_named_key(
    raw: ?*Handle,
    key_value: u8,
    action_value: u8,
    modifiers: u8,
) i32 {
    const value = raw orelse return 1;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    if (modifiers & ~protocol.typed_input.modifiers.known != 0) return 3;
    const key = std.enums.fromInt(protocol.InputKeyName, key_value) orelse return 3;
    const action = std.enums.fromInt(protocol.InputKeyAction, action_value) orelse return 3;
    client.actions.namedKey(&bridge.connection, key, action, modifiers) catch |failure| {
        bridge.setError("key", @errorName(failure));
        return 2;
    };
    return 0;
}

pub export fn howl_odin_bridge_send_unicode_key(
    raw: ?*Handle,
    scalar: u32,
    action_value: u8,
    modifiers: u8,
) i32 {
    const value = raw orelse return 1;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    if (modifiers & ~protocol.typed_input.modifiers.known != 0) return 3;
    const action = std.enums.fromInt(protocol.InputKeyAction, action_value) orelse return 3;
    client.actions.unicodeKey(&bridge.connection, scalar, action, modifiers) catch |failure| {
        bridge.setError("unicode_key", @errorName(failure));
        return 2;
    };
    return 0;
}

pub export fn howl_odin_bridge_send_resize(
    raw: ?*Handle,
    rows: u16,
    columns: u16,
) i32 {
    const value = raw orelse return 1;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    client.actions.resize(&bridge.connection, rows, columns) catch |failure| {
        bridge.setError("resize", @errorName(failure));
        return 2;
    };
    return 0;
}

pub export fn howl_odin_bridge_copy_error(
    raw: ?*Handle,
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
) void {
    output_len.* = 0;
    const value = raw orelse return;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    const count = @min(output_capacity, bridge.last_error_len);
    @memcpy(output_ptr[0..count], bridge.last_error[0..count]);
    output_len.* = count;
}

pub export fn howl_odin_bridge_revision(raw: ?*Handle) u64 {
    return if (lastBegin(raw)) |begin| begin.revision else 0;
}

pub export fn howl_odin_bridge_terminal_revision(raw: ?*Handle) u64 {
    return if (lastBegin(raw)) |begin| begin.terminal_revision else 0;
}

pub export fn howl_odin_bridge_rows(raw: ?*Handle) u16 {
    return if (lastBegin(raw)) |begin| begin.rows else 0;
}

pub export fn howl_odin_bridge_columns(raw: ?*Handle) u16 {
    return if (lastBegin(raw)) |begin| begin.columns else 0;
}

pub export fn howl_odin_bridge_cursor_row(raw: ?*Handle) u16 {
    return if (lastBegin(raw)) |begin| begin.cursor_row else 0;
}

pub export fn howl_odin_bridge_cursor_column(raw: ?*Handle) u16 {
    return if (lastBegin(raw)) |begin| begin.cursor_column else 0;
}

pub export fn howl_odin_bridge_cursor_visible(raw: ?*Handle) u8 {
    return if (lastBegin(raw)) |begin| @intFromBool(begin.cursor_visible) else 0;
}

pub export fn howl_odin_bridge_cursor_shape(raw: ?*Handle) u8 {
    return if (lastBegin(raw)) |begin| begin.cursor_shape else 0;
}

pub export fn howl_odin_bridge_alternate_screen(raw: ?*Handle) u8 {
    return if (lastBegin(raw)) |begin| @intFromBool(begin.alternate_screen) else 0;
}

pub export fn howl_odin_bridge_history_count(raw: ?*Handle) u32 {
    return if (lastBegin(raw)) |begin| begin.history_count else 0;
}

pub export fn howl_odin_bridge_text_truncated(raw: ?*Handle) u8 {
    const value = raw orelse return 0;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    return @intFromBool(bridge.text_truncated);
}

fn lastBegin(raw: ?*Handle) ?protocol.SnapshotBegin {
    const value = raw orelse return null;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    return bridge.last_begin;
}

fn writeDiagnostic(
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
    message: []const u8,
) void {
    const count = @min(output_capacity, message.len);
    @memcpy(output_ptr[0..count], message[0..count]);
    output_len.* = count;
}

fn writeConnectDiagnostic(
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
    failure_name: []const u8,
    diagnostic: client.ConnectDiagnostic,
) void {
    if (output_capacity == 0) return;
    const rendered = std.fmt.bufPrint(
        output_ptr[0..output_capacity],
        "{s} stage={s} os_error={d}",
        .{ failure_name, @tagName(diagnostic.stage), diagnostic.os_error },
    ) catch return;
    output_len.* = rendered.len;
}

test "bridge named key action values stay protocol-aligned" {
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(protocol.InputKeyName.enter));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(protocol.InputKeyName.backspace));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(protocol.InputKeyAction.press));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(protocol.InputKeyAction.release));
    try std.testing.expectEqual(@as(u8, 1), protocol.typed_input.modifiers.shift);
    try std.testing.expectEqual(@as(u8, 4), protocol.typed_input.modifiers.control);
}

test "Odin Canvas C records stay fixed and format tags follow Canvas" {
    try std.testing.expectEqual(@as(usize, 56), @sizeOf(RenderResourceInfo));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(RenderRemovalInfo));
    try std.testing.expectEqual(@as(usize, 72), @sizeOf(RenderCommandInfo));
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(canvas.ResourceFormat.alpha8));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(canvas.ResourceFormat.rgba8));
}
